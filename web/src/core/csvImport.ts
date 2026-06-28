// TS CSV importer (docs/13 §9; product-spec §8). Mirrors the Swift importer:
// RFC-4180-lite tokenizer + header aliases + per-row validation, producing an
// `ImportPreview` of valid `Subscription`s and `ImportRowError`s. Nothing is
// written until the user confirms — importing adds only the `valid` rows.
//
// Reuses the existing locale-aware number parser (normalizeNumberString) and the
// minor-units money parser (parseMoney). Money is Int64 minor units, never floats.

import { normalizeNumberString } from './predictor';
import { parseMoney, MoneyError } from './money';
import type { CurrencyCode } from './currency';
import type { BillingPeriod } from './normalization';
import type { PaymentMethod, UsageState } from '../types/database';
import type { Subscription } from '../features/subscriptions/types';

export interface ImportRowError {
  /** 1-based row number in the data body (header is not counted). */
  row: number;
  /** The offending canonical field, when applicable. */
  field?: string;
  message: string;
}

export interface ImportPreview {
  valid: Subscription[];
  errors: ImportRowError[];
  /** Number of data rows (excludes header). */
  totalRows: number;
}

const CURRENCIES: readonly CurrencyCode[] = ['EUR', 'USD', 'BTC'];
const BILLING_PERIODS: readonly BillingPeriod[] = ['weekly', 'monthly', 'quarterly', 'yearly'];
const PAYMENT_METHODS: readonly PaymentMethod[] = [
  'credit_card',
  'debit_card',
  'paypal',
  'bank_transfer',
  'apple_pay',
  'google_pay',
  'crypto',
  'other',
];
const USAGE_STATES: readonly UsageState[] = ['active', 'rarely', 'unused'];

// MARK: - Header aliases (case-insensitive). Maps a header token -> canonical column.

const HEADER_ALIASES: Record<string, string> = {
  // name
  name: 'name',
  service: 'name',
  title: 'name',
  subscription: 'name',
  // amount
  amount: 'amount',
  monthly_cost: 'amount',
  monthly_amount: 'amount',
  cost: 'amount',
  price: 'amount',
  // currency
  currency: 'currency',
  ccy: 'currency',
  // billing_period
  billing_period: 'billing_period',
  billing: 'billing_period',
  period: 'billing_period',
  cycle: 'billing_period',
  // payment_method
  payment_method: 'payment_method',
  payment: 'payment_method',
  method: 'payment_method',
  // category
  category: 'category',
  // usage_state
  usage_state: 'usage_state',
  usage: 'usage_state',
  status: 'usage_state',
  // start_date
  start_date: 'start_date',
  start: 'start_date',
  since: 'start_date',
  date: 'start_date',
  // vendor_url
  url: 'vendor_url',
  vendor_url: 'vendor_url',
  website: 'vendor_url',
};

/**
 * RFC-4180-lite tokenizer (docs/13 §9.4). Splits the full CSV text into rows of
 * fields. Handles quoted fields containing commas and CRLF/LF, escaped `""`
 * quotes, and embedded newlines inside quotes. O(len).
 */
export function tokenizeCSV(text: string): string[][] {
  const rows: string[][] = [];
  let field = '';
  let row: string[] = [];
  let inQuotes = false;
  let i = 0;
  const n = text.length;

  const endField = () => {
    row.push(field);
    field = '';
  };
  const endRow = () => {
    endField();
    rows.push(row);
    row = [];
  };

  while (i < n) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i += 2;
          continue;
        }
        inQuotes = false;
        i += 1;
        continue;
      }
      field += c;
      i += 1;
      continue;
    }
    if (c === '"') {
      inQuotes = true;
      i += 1;
      continue;
    }
    if (c === ',') {
      endField();
      i += 1;
      continue;
    }
    if (c === '\r') {
      // CRLF or lone CR -> row break.
      endRow();
      if (text[i + 1] === '\n') i += 2;
      else i += 1;
      continue;
    }
    if (c === '\n') {
      endRow();
      i += 1;
      continue;
    }
    field += c;
    i += 1;
  }
  // Flush the trailing field/row unless the text ended exactly on a newline.
  if (field.length > 0 || row.length > 0) endRow();
  return rows;
}

function snake(token: string): string {
  return token
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, '_');
}

const today = (): string => new Date().toISOString().slice(0, 10);

/** yyyy-MM-dd validation (calendar-real, not just regex). */
function isValidISODate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [y, m, d] = value.split('-').map(Number);
  if (m < 1 || m > 12 || d < 1 || d > 31) return false;
  const dt = new Date(Date.UTC(y, m - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d;
}

/** The canonical, mappable target fields (mirrors the Swift `CSVField`). */
export type CSVField =
  | 'name'
  | 'amount'
  | 'currency'
  | 'billing_period'
  | 'payment_method'
  | 'category'
  | 'usage_state'
  | 'start_date'
  | 'vendor_url';

export const CSV_FIELDS: readonly CSVField[] = [
  'name',
  'amount',
  'currency',
  'billing_period',
  'payment_method',
  'category',
  'usage_state',
  'start_date',
  'vendor_url',
];

/** Mapping of a canonical field to the 0-based column index it reads from. */
export type ColumnMapping = Partial<Record<CSVField, number>>;

export interface HeaderAnalysis {
  /** Raw header tokens (trimmed), in column order. */
  headers: string[];
  /** Auto-detected field -> column index (alias match; missing fields absent). */
  autoMapping: ColumnMapping;
}

/** Build the alias-based auto-mapping for a (tokenized) header row. */
function autoDetectMapping(header: string[]): ColumnMapping {
  const mapping: ColumnMapping = {};
  header.forEach((raw, idx) => {
    const canonical = HEADER_ALIASES[snake(raw)] as CSVField | undefined;
    if (canonical && mapping[canonical] === undefined) mapping[canonical] = idx;
  });
  return mapping;
}

/**
 * Inspect a CSV's header: the raw tokens + the auto-detected field->column map.
 * This is the read the column-mapping UI uses to seed its selectors.
 */
export function analyzeHeader(text: string): HeaderAnalysis {
  const rows = tokenizeCSV(text);
  const nonEmpty = rows.filter((r) => !(r.length === 1 && r[0].trim() === ''));
  if (nonEmpty.length === 0) return { headers: [], autoMapping: {} };
  const headers = nonEmpty[0].map((h) => h.trim());
  return { headers, autoMapping: autoDetectMapping(nonEmpty[0]) };
}

/**
 * Parse a subscriptions CSV into a previewable `ImportPreview`. Collects ALL
 * errors per row (1-based, header excluded). A missing required column (`name`
 * or `amount`) fails the whole file via a single row-0 error.
 */
export function parseSubscriptionsCSV(text: string): ImportPreview {
  const rows = tokenizeCSV(text);
  // Drop fully-empty rows (e.g. a trailing blank line).
  const nonEmpty = rows.filter((r) => !(r.length === 1 && r[0].trim() === ''));

  if (nonEmpty.length === 0) {
    return { valid: [], errors: [{ row: 0, message: 'Empty CSV.' }], totalRows: 0 };
  }

  const colIndex = autoDetectMapping(nonEmpty[0]);

  const dataRows = nonEmpty.slice(1);
  const totalRows = dataRows.length;

  // Required-column gate (whole-file failure, not per-row).
  const missing: string[] = [];
  if (colIndex.name === undefined) missing.push('name');
  if (colIndex.amount === undefined) missing.push('amount');
  if (missing.length > 0) {
    return {
      valid: [],
      errors: [{ row: 0, message: `Missing required column(s): ${missing.join(', ')}.` }],
      totalRows,
    };
  }

  return buildPreview(dataRows, colIndex, totalRows);
}

/**
 * Parse a CSV with an EXPLICIT field -> column-index mapping (the UI's
 * user-overridable mapping). Mirrors the Swift `parse(_:mapping:)`: fields absent
 * from the mapping fall back to their defaults, and there is no whole-file
 * required-column gate (the caller enforces that name/amount are mapped).
 */
export function parseSubscriptionsCSVWithMapping(
  text: string,
  mapping: ColumnMapping
): ImportPreview {
  const rows = tokenizeCSV(text);
  const nonEmpty = rows.filter((r) => !(r.length === 1 && r[0].trim() === ''));
  if (nonEmpty.length === 0) {
    return { valid: [], errors: [], totalRows: 0 };
  }
  const dataRows = nonEmpty.slice(1);
  return buildPreview(dataRows, mapping, dataRows.length);
}

/** Shared per-row validation core used by both the auto and explicit paths. */
function buildPreview(
  dataRows: string[][],
  colIndex: ColumnMapping,
  totalRows: number
): ImportPreview {
  const cell = (cols: string[], canonical: CSVField): string => {
    const idx = colIndex[canonical];
    if (idx === undefined || idx < 0) return '';
    return (cols[idx] ?? '').trim();
  };

  const valid: Subscription[] = [];
  const errors: ImportRowError[] = [];

  dataRows.forEach((cols, i) => {
    const rowNumber = i + 1; // 1-based, header excluded
    const rowErrors: ImportRowError[] = [];

    // name — required, 1..120 chars
    const name = cell(cols, 'name');
    if (name.length === 0) {
      rowErrors.push({ row: rowNumber, field: 'name', message: 'Missing name' });
    } else if (name.length > 120) {
      rowErrors.push({ row: rowNumber, field: 'name', message: 'Name too long (max 120)' });
    }

    // currency — default EUR; must be supported
    const currencyRaw = cell(cols, 'currency');
    let currency: CurrencyCode = 'EUR';
    if (currencyRaw.length > 0) {
      const upper = currencyRaw.toUpperCase();
      if (CURRENCIES.includes(upper as CurrencyCode)) {
        currency = upper as CurrencyCode;
      } else {
        rowErrors.push({ row: rowNumber, field: 'currency', message: 'Unsupported currency' });
      }
    }

    // amount — locale-aware parse to minor units of the row currency
    const amountRaw = cell(cols, 'amount');
    let amountMinor = 0;
    if (amountRaw.length === 0) {
      rowErrors.push({ row: rowNumber, field: 'amount', message: 'Invalid amount' });
    } else {
      try {
        amountMinor = parseMoney(normalizeNumberString(amountRaw), currency);
      } catch (err) {
        const message =
          err instanceof MoneyError && err.kind === 'tooManyFractionalDigits'
            ? 'Invalid amount'
            : 'Invalid amount';
        rowErrors.push({ row: rowNumber, field: 'amount', message });
      }
    }

    // billing_period — default monthly
    const periodRaw = cell(cols, 'billing_period').toLowerCase();
    let billingPeriod: BillingPeriod = 'monthly';
    if (periodRaw.length > 0) {
      if (BILLING_PERIODS.includes(periodRaw as BillingPeriod)) {
        billingPeriod = periodRaw as BillingPeriod;
      } else {
        rowErrors.push({
          row: rowNumber,
          field: 'billing_period',
          message: 'Invalid billing period',
        });
      }
    }

    // payment_method — default other
    const methodRaw = cell(cols, 'payment_method').toLowerCase();
    let paymentMethod: PaymentMethod = 'other';
    if (methodRaw.length > 0) {
      if (PAYMENT_METHODS.includes(methodRaw as PaymentMethod)) {
        paymentMethod = methodRaw as PaymentMethod;
      } else {
        rowErrors.push({
          row: rowNumber,
          field: 'payment_method',
          message: 'Unsupported payment method',
        });
      }
    }

    // usage_state — default active
    const usageRaw = cell(cols, 'usage_state').toLowerCase();
    let usageState: UsageState = 'active';
    if (usageRaw.length > 0) {
      if (USAGE_STATES.includes(usageRaw as UsageState)) {
        usageState = usageRaw as UsageState;
      } else {
        rowErrors.push({
          row: rowNumber,
          field: 'usage_state',
          message: 'Unsupported usage state',
        });
      }
    }

    // start_date — default today, else yyyy-MM-dd
    const dateRaw = cell(cols, 'start_date');
    let startDate = today();
    if (dateRaw.length > 0) {
      if (isValidISODate(dateRaw)) {
        startDate = dateRaw;
      } else {
        rowErrors.push({ row: rowNumber, field: 'start_date', message: 'Invalid start date' });
      }
    }

    // vendor_url — optional
    const urlRaw = cell(cols, 'vendor_url');
    const vendorURL = urlRaw.length > 0 ? urlRaw : null;

    // category — optional, default Other
    const categoryRaw = cell(cols, 'category');
    const categoryName = categoryRaw.length > 0 ? categoryRaw : 'Other';

    if (rowErrors.length > 0) {
      errors.push(...rowErrors);
      return;
    }

    valid.push({
      id: `import-${Date.now()}-${rowNumber}`,
      name,
      vendorURL,
      icon: null,
      amountMinor,
      currency,
      billingPeriod,
      paymentMethod,
      categoryName,
      usageState,
      favorite: false,
      sortOrder: Number.MAX_SAFE_INTEGER,
      startDate,
    });
  });

  return { valid, errors, totalRows };
}

/** A small sample CSV exercising aliases + valid/invalid rows for the UI. */
export const SAMPLE_CSV = `name,monthly_cost,currency,billing_period,payment_method,category
Netflix,12.99,EUR,monthly,credit_card,Streaming
GitHub,"100,00",USD,yearly,paypal,Developer
Figma,abc,USD,monthly,credit_card,Design`;

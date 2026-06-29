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
import type { BillingPeriod, IncomeFrequency } from './normalization';
import type { PaymentMethod, UsageState } from '../types/database';
import type { Subscription } from '../features/subscriptions/types';
import type {
  ExpenseCategory,
  FixedExpense,
  IncomeSource,
  VariableExpense,
} from '../features/cashflow/types';

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
 * Sniff the field delimiter from the header line: count un-quoted `,` `;` `\t`
 * occurrences in the text before the first un-quoted record break, and pick the
 * most frequent. Comma wins on a tie or when none appear (legacy default).
 * Mirrors the Swift `CSVImportKit.detectDelimiter`.
 */
function detectDelimiter(text: string): string {
  let commas = 0;
  let semis = 0;
  let tabs = 0;
  let inQuotes = false;
  let i = 0;
  const n = text.length;
  while (i < n) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          i += 2;
          continue;
        }
        inQuotes = false;
        i += 1;
        continue;
      }
      i += 1;
      continue;
    }
    if (c === '"') {
      inQuotes = true;
      i += 1;
      continue;
    }
    if (c === ',') commas += 1;
    else if (c === ';') semis += 1;
    else if (c === '\t') tabs += 1;
    else if (c === '\r' || c === '\n') break; // end of header line
    i += 1;
  }
  // Most frequent wins; comma is preferred on a tie / when none are present.
  if (semis > commas && semis >= tabs) return ';';
  if (tabs > commas && tabs > semis) return '\t';
  return ',';
}

/**
 * RFC-4180-lite tokenizer (docs/13 §9.4). Splits the full CSV text into rows of
 * fields. Handles quoted fields containing commas and CRLF/LF, escaped `""`
 * quotes, and embedded newlines inside quotes. O(len).
 *
 * Additive de-DE / Excel hardening (docs/13 §9): a leading UTF-8 BOM (U+FEFF) is
 * stripped before tokenizing, and the field delimiter is sniffed from the first
 * (header) line — un-quoted occurrences of `,` `;` and `\t` are counted and the
 * most frequent wins (tie / none → comma, preserving the legacy comma behavior).
 * Full UTF-16 byte-level decoding stays a file-read concern (out of scope here).
 */
export function tokenizeCSV(input: string): string[][] {
  // (1) Strip a leading UTF-8 BOM so header aliases still match on Excel exports.
  const text = input.charCodeAt(0) === 0xfeff ? input.slice(1) : input;
  // (2) Sniff the delimiter from the header line.
  const delimiter = detectDelimiter(text);

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
    if (c === delimiter) {
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

// MARK: - Shared field parsers (mirrors the Swift `CSVImportKit` helpers).

/** Parse a currency cell. Blank → EUR default (no error). Unknown → EUR + error. */
function parseCurrencyCell(
  raw: string,
  row: number,
  errors: ImportRowError[]
): CurrencyCode {
  if (raw.length === 0) return 'EUR';
  const upper = raw.toUpperCase();
  if (CURRENCIES.includes(upper as CurrencyCode)) return upper as CurrencyCode;
  errors.push({ row, field: 'currency', message: 'Unsupported currency' });
  return 'EUR';
}

/** Parse a required amount cell into minor units for `currency` (HALF-UP). Blank or
 *  unparseable → 0 with an "Invalid amount" error. */
function parseAmountCell(
  raw: string,
  currency: CurrencyCode,
  row: number,
  errors: ImportRowError[]
): number {
  if (raw.length === 0) {
    errors.push({ row, field: 'amount', message: 'Invalid amount' });
    return 0;
  }
  try {
    return parseMoney(normalizeNumberString(raw), currency);
  } catch (err) {
    // Keep a stable message regardless of MoneyError kind (mirrors iOS).
    void (err instanceof MoneyError);
    errors.push({ row, field: 'amount', message: 'Invalid amount' });
    return 0;
  }
}

/** Parse a loose boolean cell: true/yes/1/y/on → true; false/no/0/n/off → false;
 *  blank → null (caller's default). Anything else → null + error. */
function parseBoolCell(
  raw: string,
  field: string,
  row: number,
  errors: ImportRowError[]
): boolean | null {
  const v = raw.trim().toLowerCase();
  if (v.length === 0) return null;
  if (['true', 'yes', '1', 'y', 'on'].includes(v)) return true;
  if (['false', 'no', '0', 'n', 'off'].includes(v)) return false;
  errors.push({ row, field, message: 'Invalid boolean (expected true/false)' });
  return null;
}

/** Resolve a category NAME to an existing expense category id (case-insensitive,
 *  trimmed). Blank or no match → null (Uncategorized). Never an error. */
function resolveCategoryID(
  name: string,
  categories: ExpenseCategory[]
): string | null {
  const needle = name.trim().toLowerCase();
  if (needle.length === 0) return null;
  return categories.find((c) => c.name.toLowerCase() === needle)?.id ?? null;
}

const NAME_MAX = 120;

/** Validate a required name cell (1..120 chars). */
function validateName(name: string, row: number, errors: ImportRowError[]): void {
  if (name.length === 0) {
    errors.push({ row, field: 'name', message: 'Missing name' });
  } else if (name.length > NAME_MAX) {
    errors.push({ row, field: 'name', message: 'Name too long (max 120 characters)' });
  }
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

// ===========================================================================
// MARK: - Generalized entity importers (income + fixed/variable expenses)
//
// Mirrors the Swift `CSVImportKit` + `EntityCSVImporters`: one tokenizer, alias
// auto-mapping, a generic explicit-mapping row loop collecting ALL per-row errors,
// and per-type field specs + builders. Reuses the same tokenizer / number-parser /
// validation helpers above — nothing about the RFC-4180 tokenizer is duplicated.
// ===========================================================================

/** A previewable result over any entity (mirrors the Swift `EntityImportPreview`). */
export interface EntityImportPreview<Entity> {
  valid: Entity[];
  errors: ImportRowError[];
  totalRows: number;
}

/** Per-field column index for an arbitrary field enum. */
export type FieldMapping<Field extends string> = Partial<Record<Field, number>>;

/** Header analysis for an arbitrary field enum. */
export interface EntityHeaderAnalysis<Field extends string> {
  headers: string[];
  autoMapping: FieldMapping<Field>;
}

type AliasMap<Field extends string> = Partial<Record<Field, readonly string[]>>;

/** Build the alias auto-mapping for a tokenized header using a per-field alias set.
 *  First alias match wins per field; first column wins on duplicate aliases. */
function autoDetectMappingFor<Field extends string>(
  header: string[],
  aliases: AliasMap<Field>
): FieldMapping<Field> {
  const mapping: FieldMapping<Field> = {};
  header.forEach((raw, idx) => {
    const token = snake(raw);
    (Object.keys(aliases) as Field[]).forEach((field) => {
      const set = aliases[field];
      if (set && set.includes(token) && mapping[field] === undefined) {
        mapping[field] = idx;
      }
    });
  });
  return mapping;
}

/** Inspect a CSV header with a per-field alias set: raw tokens + the auto-mapping. */
function analyzeHeaderFor<Field extends string>(
  text: string,
  aliases: AliasMap<Field>
): EntityHeaderAnalysis<Field> {
  const rows = tokenizeCSV(text);
  const nonEmpty = rows.filter((r) => !(r.length === 1 && r[0].trim() === ''));
  if (nonEmpty.length === 0) return { headers: [], autoMapping: {} };
  const headers = nonEmpty[0].map((h) => h.trim());
  return { headers, autoMapping: autoDetectMappingFor(nonEmpty[0], aliases) };
}

type RowResult<Entity> = { ok: true; entity: Entity } | { ok: false; errors: ImportRowError[] };

/** Generic explicit-mapping row loop. Header is row 1; data rows start at row 2.
 *  Wholly-blank rows are skipped. Delegates per-row construction to `build`. */
function parseEntityCSV<Field extends string, Entity>(
  text: string,
  mapping: FieldMapping<Field>,
  build: (cell: (key: Field) => string, rowNumber: number) => RowResult<Entity>
): EntityImportPreview<Entity> {
  const rows = tokenizeCSV(text);
  const nonEmpty = rows.filter((r) => !(r.length === 1 && r[0].trim() === ''));
  if (nonEmpty.length === 0) return { valid: [], errors: [], totalRows: 0 };

  const dataRows = nonEmpty.slice(1);
  const valid: Entity[] = [];
  const errors: ImportRowError[] = [];
  let totalRows = 0;

  dataRows.forEach((cols, i) => {
    const isBlank = cols.every((c) => c.trim() === '');
    if (isBlank) return;
    totalRows += 1;
    const rowNumber = i + 2; // header is row 1
    const cell = (key: Field): string => {
      const idx = mapping[key];
      if (idx === undefined || idx < 0 || idx >= cols.length) return '';
      return (cols[idx] ?? '').trim();
    };
    const result = build(cell, rowNumber);
    if (result.ok) valid.push(result.entity);
    else errors.push(...result.errors);
  });

  return { valid, errors, totalRows };
}

const importId = (prefix: string, row: number): string =>
  `${prefix}-${Date.now()}-${row}`;

// MARK: - Income (IncomeSource)

export type IncomeCSVField = 'name' | 'amount' | 'currency' | 'frequency' | 'next_payment' | 'notes';

export const INCOME_CSV_FIELDS: readonly IncomeCSVField[] = [
  'name',
  'amount',
  'currency',
  'frequency',
  'next_payment',
  'notes',
];

const INCOME_FREQUENCIES: readonly IncomeFrequency[] = ['weekly', 'monthly', 'yearly', 'one_time'];

const INCOME_ALIASES: AliasMap<IncomeCSVField> = {
  name: ['name', 'source', 'title', 'income'],
  amount: ['amount', 'pay', 'salary', 'income_amount', 'monthly_amount'],
  currency: ['currency', 'ccy'],
  frequency: ['frequency', 'freq', 'period', 'cycle'],
  next_payment: ['next_payment', 'next', 'payday', 'next_pay', 'date'],
  notes: ['notes', 'note', 'memo', 'description'],
};

export function analyzeIncomeHeader(text: string): EntityHeaderAnalysis<IncomeCSVField> {
  return analyzeHeaderFor(text, INCOME_ALIASES);
}

export function parseIncomeCSVWithMapping(
  text: string,
  mapping: FieldMapping<IncomeCSVField>
): EntityImportPreview<IncomeSource> {
  return parseEntityCSV<IncomeCSVField, IncomeSource>(text, mapping, (cell, row) => {
    const errors: ImportRowError[] = [];

    const name = cell('name');
    validateName(name, row, errors);

    const currency = parseCurrencyCell(cell('currency'), row, errors);
    const amountMinor = parseAmountCell(cell('amount'), currency, row, errors);

    let frequency: IncomeFrequency = 'monthly';
    const freqRaw = cell('frequency').toLowerCase();
    if (freqRaw.length > 0) {
      if (INCOME_FREQUENCIES.includes(freqRaw as IncomeFrequency)) {
        frequency = freqRaw as IncomeFrequency;
      } else {
        errors.push({
          row,
          field: 'frequency',
          message: 'Invalid frequency (weekly/monthly/yearly/one_time)',
        });
      }
    }

    let nextPayment: string | null = null;
    const nextRaw = cell('next_payment');
    if (nextRaw.length > 0) {
      if (isValidISODate(nextRaw)) nextPayment = nextRaw;
      else
        errors.push({
          row,
          field: 'next_payment',
          message: 'Invalid date (expected yyyy-MM-dd)',
        });
    }

    if (errors.length > 0) return { ok: false, errors };
    return {
      ok: true,
      entity: { id: importId('inc', row), name, amountMinor, currency, frequency, nextPayment },
    };
  });
}

// MARK: - Fixed expense (FixedExpense). Category is a NAME resolved to an id.

export type FixedExpenseCSVField =
  | 'name'
  | 'amount'
  | 'currency'
  | 'category'
  | 'frequency'
  | 'due_date'
  | 'autopay'
  | 'notes';

export const FIXED_EXPENSE_CSV_FIELDS: readonly FixedExpenseCSVField[] = [
  'name',
  'amount',
  'currency',
  'category',
  'frequency',
  'due_date',
  'autopay',
  'notes',
];

const FIXED_EXPENSE_ALIASES: AliasMap<FixedExpenseCSVField> = {
  name: ['name', 'bill', 'title', 'expense'],
  amount: ['amount', 'cost', 'price', 'monthly_cost', 'monthly_amount'],
  currency: ['currency', 'ccy'],
  category: ['category', 'cat'],
  frequency: ['frequency', 'freq', 'period', 'cycle', 'billing_period'],
  due_date: ['due_date', 'due', 'date'],
  autopay: ['autopay', 'auto_pay', 'auto'],
  notes: ['notes', 'note', 'memo', 'description'],
};

export function analyzeFixedExpenseHeader(
  text: string
): EntityHeaderAnalysis<FixedExpenseCSVField> {
  return analyzeHeaderFor(text, FIXED_EXPENSE_ALIASES);
}

export function parseFixedExpenseCSVWithMapping(
  text: string,
  mapping: FieldMapping<FixedExpenseCSVField>,
  categories: ExpenseCategory[]
): EntityImportPreview<FixedExpense> {
  return parseEntityCSV<FixedExpenseCSVField, FixedExpense>(text, mapping, (cell, row) => {
    const errors: ImportRowError[] = [];

    const name = cell('name');
    validateName(name, row, errors);

    const currency = parseCurrencyCell(cell('currency'), row, errors);
    const amountMinor = parseAmountCell(cell('amount'), currency, row, errors);

    const categoryId = resolveCategoryID(cell('category'), categories);

    // frequency → BillingPeriod (weekly/monthly/quarterly/yearly), default monthly.
    let billingPeriod: BillingPeriod = 'monthly';
    const freqRaw = cell('frequency').toLowerCase();
    if (freqRaw.length > 0) {
      if (BILLING_PERIODS.includes(freqRaw as BillingPeriod)) {
        billingPeriod = freqRaw as BillingPeriod;
      } else {
        errors.push({
          row,
          field: 'frequency',
          message: 'Invalid frequency (weekly/monthly/quarterly/yearly)',
        });
      }
    }

    let dueDate: string | null = null;
    const dueRaw = cell('due_date');
    if (dueRaw.length > 0) {
      if (isValidISODate(dueRaw)) dueDate = dueRaw;
      else
        errors.push({
          row,
          field: 'due_date',
          message: 'Invalid date (expected yyyy-MM-dd)',
        });
    }

    // autopay is parsed/validated (collects an error) but not stored on the web
    // FixedExpense type (mirrors iOS validation; web model omits the field today).
    parseBoolCell(cell('autopay'), 'autopay', row, errors);

    if (errors.length > 0) return { ok: false, errors };
    return {
      ok: true,
      entity: { id: importId('fix', row), name, amountMinor, currency, categoryId, billingPeriod, dueDate },
    };
  });
}

// MARK: - Variable expense (VariableExpense). `date` (spent_on) is REQUIRED.

export type VariableExpenseCSVField =
  | 'name'
  | 'amount'
  | 'currency'
  | 'category'
  | 'date'
  | 'notes';

export const VARIABLE_EXPENSE_CSV_FIELDS: readonly VariableExpenseCSVField[] = [
  'name',
  'amount',
  'currency',
  'category',
  'date',
  'notes',
];

const VARIABLE_EXPENSE_ALIASES: AliasMap<VariableExpenseCSVField> = {
  name: ['name', 'title', 'expense', 'merchant', 'description'],
  amount: ['amount', 'cost', 'price', 'spent'],
  currency: ['currency', 'ccy'],
  category: ['category', 'cat'],
  date: ['spent_on', 'date', 'spent', 'on'],
  notes: ['notes', 'note', 'memo'],
};

export function analyzeVariableExpenseHeader(
  text: string
): EntityHeaderAnalysis<VariableExpenseCSVField> {
  return analyzeHeaderFor(text, VARIABLE_EXPENSE_ALIASES);
}

export function parseVariableExpenseCSVWithMapping(
  text: string,
  mapping: FieldMapping<VariableExpenseCSVField>,
  categories: ExpenseCategory[]
): EntityImportPreview<VariableExpense> {
  return parseEntityCSV<VariableExpenseCSVField, VariableExpense>(text, mapping, (cell, row) => {
    const errors: ImportRowError[] = [];

    const name = cell('name');
    validateName(name, row, errors);

    const currency = parseCurrencyCell(cell('currency'), row, errors);
    const amountMinor = parseAmountCell(cell('amount'), currency, row, errors);

    const categoryId = resolveCategoryID(cell('category'), categories);

    // date — REQUIRED ISO date
    let spentOn = today();
    const dateRaw = cell('date');
    if (dateRaw.length === 0) {
      errors.push({ row, field: 'date', message: 'Missing date (expected yyyy-MM-dd)' });
    } else if (isValidISODate(dateRaw)) {
      spentOn = dateRaw;
    } else {
      errors.push({ row, field: 'date', message: 'Invalid date (expected yyyy-MM-dd)' });
    }

    if (errors.length > 0) return { ok: false, errors };
    return {
      ok: true,
      entity: { id: importId('var', row), name, amountMinor, currency, categoryId, spentOn },
    };
  });
}

// MARK: - Sample CSVs per type (for the UI's "Load sample").

export const SAMPLE_INCOME_CSV = `name,amount,currency,frequency,next_payment
Salary,3000.00,EUR,monthly,2026-07-01
Dividend,150,USD,yearly,
Gift,abc,EUR,one_time,`;

export const SAMPLE_FIXED_EXPENSE_CSV = `name,amount,currency,category,frequency,due_date,autopay
Rent,1200.00,EUR,Housing,monthly,2026-07-01,true
Insurance,90,EUR,Utilities,monthly,2026-07-15,no
Mystery,30,EUR,Nope,monthly,,`;

export const SAMPLE_VARIABLE_EXPENSE_CSV = `name,amount,currency,category,spent_on
Groceries,45.20,EUR,Groceries,2026-06-10
Lunch,12.50,EUR,Dining,2026-06-15
Misc,abc,EUR,Other,2026-06-16`;

// ===========================================================================
// MARK: - Duplicate detection (docs/13 §9; M6 follow-up)
//
// A PURE, additive helper shared with the Swift core (MATCHING vectors). Given a
// list of valid rows (each carrying name + amountMinor + currency) and an optional
// set of EXISTING entity keys, flag the rows that look like duplicates — either
// another valid row earlier in the SAME file, or a row matching an existing entity.
// The hint is ADVISORY: importing all valid rows stays the default; the UI offers an
// "import non-duplicates only" affordance. Nothing here mutates the ImportPreview.
// ===========================================================================

/** The minimal shape a row needs for duplicate detection. */
export interface DedupeCandidate {
  name: string;
  amountMinor: number;
  currency: CurrencyCode;
}

/**
 * The canonical dedupe key for a row: `name|amountMinor|currency`, with the name
 * lowercased + trimmed (whitespace collapsed) and the currency uppercased. Same
 * formula on Swift + web so existing-key sets are portable across the boundary.
 */
export function dedupeKey(name: string, amountMinor: number, currency: CurrencyCode): string {
  const normName = name.trim().toLowerCase().replace(/\s+/g, ' ');
  return `${normName}|${amountMinor}|${currency.toUpperCase()}`;
}

/** Why a row was flagged: it matches an existing entity, an earlier CSV row, or both. */
export type DuplicateReason = 'existing' | 'within-csv' | 'both';

/** A flagged row: its 0-based index into the input `rows`, its key, and the reason. */
export interface DuplicateFlag {
  /** 0-based index into the `rows` array passed to `detectDuplicates`. */
  index: number;
  key: string;
  reason: DuplicateReason;
}

export interface DuplicateReport {
  /** Flags in input order, one per row that is a likely duplicate. */
  flags: DuplicateFlag[];
  /** The flagged 0-based indices, for quick membership checks (`flaggedIndices.has(i)`). */
  flaggedIndices: Set<number>;
  /** Total number of flagged rows (`flags.length`). */
  count: number;
}

/**
 * Detect likely-duplicate rows among `rows`. A row is flagged when its dedupe key
 * matches (a) an entry in `existingKeys` (an existing entity → reason `existing`),
 * and/or (b) an EARLIER row in `rows` with the same key (→ reason `within-csv`).
 * The FIRST occurrence of an in-CSV key is NOT flagged for that reason (only the
 * later repeats), so importing without the flagged rows keeps one copy. A row that
 * is both an existing match and a later repeat gets reason `both`.
 *
 * Pure: never mutates inputs. Returns flags in input order.
 */
export function detectDuplicates(
  rows: readonly DedupeCandidate[],
  existingKeys: ReadonlySet<string> = new Set()
): DuplicateReport {
  const flags: DuplicateFlag[] = [];
  const flaggedIndices = new Set<number>();
  const seen = new Set<string>();

  rows.forEach((row, index) => {
    const key = dedupeKey(row.name, row.amountMinor, row.currency);
    const matchesExisting = existingKeys.has(key);
    const matchesEarlier = seen.has(key);
    seen.add(key);

    if (!matchesExisting && !matchesEarlier) return;
    const reason: DuplicateReason =
      matchesExisting && matchesEarlier ? 'both' : matchesExisting ? 'existing' : 'within-csv';
    flags.push({ index, key, reason });
    flaggedIndices.add(index);
  });

  return { flags, flaggedIndices, count: flags.length };
}

/** Build an existing-keys set from any entities carrying name + amountMinor + currency. */
export function existingKeySet(entities: readonly DedupeCandidate[]): Set<string> {
  const set = new Set<string>();
  for (const e of entities) set.add(dedupeKey(e.name, e.amountMinor, e.currency));
  return set;
}

// CSV Import page (M6) — load · map · preview · partial import. Choose an import
// type (Subscriptions / Income / Fixed expenses / Variable expenses), paste or upload
// a CSV, review/override the detected column→field mapping (auto-seeded from the alias
// match), preview the valid rows + errors before anything is written, then import only
// the valid rows via the matching repository hook (same create path as manual add). One
// glass language; reuses GlassCard + glass tokens. Logic lives in core/csvImport.ts.

import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { GlassCard } from '../../components/GlassCard';
import { Page } from '../../components/AppShell';
import { useSubscriptions } from '../subscriptions/useSubscriptions';
import { useCashFlow } from '../cashflow/useCashFlow';
import { formatMoney } from '../../core/money';
import {
  analyzeHeader,
  parseSubscriptionsCSVWithMapping,
  analyzeIncomeHeader,
  parseIncomeCSVWithMapping,
  analyzeFixedExpenseHeader,
  parseFixedExpenseCSVWithMapping,
  analyzeVariableExpenseHeader,
  parseVariableExpenseCSVWithMapping,
  CSV_FIELDS,
  INCOME_CSV_FIELDS,
  FIXED_EXPENSE_CSV_FIELDS,
  VARIABLE_EXPENSE_CSV_FIELDS,
  SAMPLE_CSV,
  SAMPLE_INCOME_CSV,
  SAMPLE_FIXED_EXPENSE_CSV,
  SAMPLE_VARIABLE_EXPENSE_CSV,
  detectDuplicates,
  existingKeySet,
  type CSVField,
  type IncomeCSVField,
  type FixedExpenseCSVField,
  type VariableExpenseCSVField,
  type ImportRowError,
  type DuplicateReport,
} from '../../core/csvImport';
import type { CurrencyCode } from '../../core/currency';
import type { ExpenseCategory } from '../cashflow/types';

// MARK: - Import-type selector

type ImportType = 'subscriptions' | 'income' | 'fixed' | 'variable';

const IMPORT_TYPES: { value: ImportType; label: string }[] = [
  { value: 'subscriptions', label: 'Subscriptions' },
  { value: 'income', label: 'Income' },
  { value: 'fixed', label: 'Fixed expenses' },
  { value: 'variable', label: 'Variable expenses' },
];

/** A previewable row reduced to the columns the shared preview table renders. */
interface PreviewRow {
  id: string;
  name: string;
  amountMinor: number;
  currency: CurrencyCode;
  /** Period / frequency, when the type has one. */
  cadence: string | null;
  /** Category display name, resolved from id when applicable. */
  category: string | null;
}

interface TypedPreview {
  rows: PreviewRow[];
  errors: ImportRowError[];
  totalRows: number;
}

/** The mapping is keyed by string field names across all types. */
type AnyMapping = Record<string, number>;

interface TypeSpec {
  /** Mappable canonical fields, in display order. */
  fields: readonly string[];
  /** Required fields that must resolve to a column before previewing. */
  required: readonly string[];
  /** Human labels per field. */
  labels: Record<string, string>;
  /** A per-type sample CSV for "Load sample". */
  sample: string;
  /** The header-alias hint shown under the textarea. */
  hint: string;
  /** Whether the preview shows a Category column. */
  hasCategory: boolean;
  /** Whether the preview shows a Period/Frequency column. */
  hasCadence: boolean;
}

const TYPE_SPECS: Record<ImportType, TypeSpec> = {
  subscriptions: {
    fields: CSV_FIELDS,
    required: ['name', 'amount'],
    labels: {
      name: 'Name',
      amount: 'Amount',
      currency: 'Currency',
      billing_period: 'Billing period',
      payment_method: 'Payment method',
      category: 'Category',
      usage_state: 'Usage state',
      start_date: 'Start date',
      vendor_url: 'URL',
    },
    sample: SAMPLE_CSV,
    hint: 'name / amount / currency / billing_period / payment_method / category / usage_state / start_date / url',
    hasCategory: true,
    hasCadence: true,
  },
  income: {
    fields: INCOME_CSV_FIELDS,
    required: ['name', 'amount'],
    labels: {
      name: 'Name',
      amount: 'Amount',
      currency: 'Currency',
      frequency: 'Frequency',
      next_payment: 'Next payment',
      notes: 'Notes',
    },
    sample: SAMPLE_INCOME_CSV,
    hint: 'name / amount / currency / frequency / next_payment / notes',
    hasCategory: false,
    hasCadence: true,
  },
  fixed: {
    fields: FIXED_EXPENSE_CSV_FIELDS,
    required: ['name', 'amount'],
    labels: {
      name: 'Name',
      amount: 'Amount',
      currency: 'Currency',
      category: 'Category',
      frequency: 'Frequency',
      due_date: 'Due date',
      autopay: 'Autopay',
      notes: 'Notes',
    },
    sample: SAMPLE_FIXED_EXPENSE_CSV,
    hint: 'name / amount / currency / category / frequency / due_date / autopay / notes',
    hasCategory: true,
    hasCadence: true,
  },
  variable: {
    fields: VARIABLE_EXPENSE_CSV_FIELDS,
    required: ['name', 'amount', 'date'],
    labels: {
      name: 'Name',
      amount: 'Amount',
      currency: 'Currency',
      category: 'Category',
      date: 'Date',
      notes: 'Notes',
    },
    sample: SAMPLE_VARIABLE_EXPENSE_CSV,
    hint: 'name / amount / currency / category / date (spent_on) / notes',
    hasCategory: true,
    hasCadence: false,
  },
};

/** Sentinel select value meaning "ignore this field" (no column mapped). */
const IGNORE = -1;

// MARK: - Remembered mappings per import type (localStorage; keyed by type)
//
// Persist the user's last column→field mapping for each import type and pre-apply it
// on the next import of that type, overriding the alias auto-detect when the saved
// mapping still resolves to a column that exists in the current header. Saved on a
// successful import; the platform store is localStorage on web (iOS uses UserDefaults).

const MAPPING_STORAGE_PREFIX = 'finmate.import.mapping.';

function mappingStorageKey(type: ImportType): string {
  return `${MAPPING_STORAGE_PREFIX}${type}`;
}

function loadRememberedMapping(type: ImportType): AnyMapping | null {
  try {
    const raw = localStorage.getItem(mappingStorageKey(type));
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (parsed === null || typeof parsed !== 'object') return null;
    const out: AnyMapping = {};
    for (const [field, idx] of Object.entries(parsed as Record<string, unknown>)) {
      if (typeof idx === 'number' && Number.isInteger(idx) && idx >= 0) out[field] = idx;
    }
    return out;
  } catch {
    return null;
  }
}

function saveRememberedMapping(type: ImportType, mapping: AnyMapping): void {
  try {
    localStorage.setItem(mappingStorageKey(type), JSON.stringify(mapping));
  } catch {
    // Storage unavailable / quota — remembering mappings is best-effort.
  }
}

/**
 * Merge a remembered mapping over the alias auto-detect for a given header. The
 * remembered mapping wins, but only for columns that still exist in this header
 * (so a saved index past the column count is dropped rather than mis-mapping).
 */
function applyRememberedMapping(
  type: ImportType,
  auto: AnyMapping,
  headerCount: number
): AnyMapping {
  const remembered = loadRememberedMapping(type);
  if (!remembered) return auto;
  const merged: AnyMapping = { ...auto };
  for (const [field, idx] of Object.entries(remembered)) {
    if (idx < headerCount) merged[field] = idx;
  }
  return merged;
}

/** Analyze a header for the chosen type → the raw tokens + the seed mapping. */
function analyzeFor(type: ImportType, text: string): { headers: string[]; autoMapping: AnyMapping } {
  switch (type) {
    case 'subscriptions':
      return analyzeHeader(text) as { headers: string[]; autoMapping: AnyMapping };
    case 'income':
      return analyzeIncomeHeader(text) as { headers: string[]; autoMapping: AnyMapping };
    case 'fixed':
      return analyzeFixedExpenseHeader(text) as { headers: string[]; autoMapping: AnyMapping };
    case 'variable':
      return analyzeVariableExpenseHeader(text) as { headers: string[]; autoMapping: AnyMapping };
  }
}

/** Parse the chosen type with an explicit mapping → a normalized preview. */
function parseFor(
  type: ImportType,
  text: string,
  mapping: AnyMapping,
  categories: ExpenseCategory[],
  categoryName: (id: string | null) => string
): TypedPreview {
  switch (type) {
    case 'subscriptions': {
      const p = parseSubscriptionsCSVWithMapping(text, mapping as Partial<Record<CSVField, number>>);
      return {
        rows: p.valid.map((s) => ({
          id: s.id,
          name: s.name,
          amountMinor: s.amountMinor,
          currency: s.currency,
          cadence: s.billingPeriod,
          category: s.categoryName,
        })),
        errors: p.errors,
        totalRows: p.totalRows,
      };
    }
    case 'income': {
      const p = parseIncomeCSVWithMapping(text, mapping as Partial<Record<IncomeCSVField, number>>);
      return {
        rows: p.valid.map((i) => ({
          id: i.id,
          name: i.name,
          amountMinor: i.amountMinor,
          currency: i.currency,
          cadence: i.frequency,
          category: null,
        })),
        errors: p.errors,
        totalRows: p.totalRows,
      };
    }
    case 'fixed': {
      const p = parseFixedExpenseCSVWithMapping(
        text,
        mapping as Partial<Record<FixedExpenseCSVField, number>>,
        categories
      );
      return {
        rows: p.valid.map((e) => ({
          id: e.id,
          name: e.name,
          amountMinor: e.amountMinor,
          currency: e.currency,
          cadence: e.billingPeriod,
          category: categoryName(e.categoryId),
        })),
        errors: p.errors,
        totalRows: p.totalRows,
      };
    }
    case 'variable': {
      const p = parseVariableExpenseCSVWithMapping(
        text,
        mapping as Partial<Record<VariableExpenseCSVField, number>>,
        categories
      );
      return {
        rows: p.valid.map((e) => ({
          id: e.id,
          name: e.name,
          amountMinor: e.amountMinor,
          currency: e.currency,
          cadence: null,
          category: categoryName(e.categoryId),
        })),
        errors: p.errors,
        totalRows: p.totalRows,
      };
    }
  }
}

export function Import() {
  const navigate = useNavigate();
  const { add, subscriptions } = useSubscriptions();
  const {
    addIncome,
    addFixed,
    addVariable,
    expenseCategories,
    categoryName,
    incomes,
    fixedExpenses,
    variableExpenses,
  } = useCashFlow();

  const [importType, setImportType] = useState<ImportType>('subscriptions');
  const spec = TYPE_SPECS[importType];

  const [text, setText] = useState('');

  // Column mapping: the detected header tokens + the user-overridable field→column
  // map. `headerAnalyzed` gates the mapping card (paste-only state before then).
  const [headers, setHeaders] = useState<string[]>([]);
  const [mapping, setMapping] = useState<AnyMapping>({});
  const [headerAnalyzed, setHeaderAnalyzed] = useState(false);

  const [preview, setPreview] = useState<TypedPreview | null>(null);
  const [fileError, setFileError] = useState<string | null>(null);
  const [imported, setImported] = useState<number | null>(null);
  /** When on, the import action skips rows flagged as likely duplicates. */
  const [skipDuplicates, setSkipDuplicates] = useState(false);

  // Existing-entity dedupe keys for the selected type (name|amountMinor|currency).
  // Used to flag preview rows that match an already-saved entity.
  const existingKeys = useMemo(() => {
    switch (importType) {
      case 'subscriptions':
        return existingKeySet(subscriptions);
      case 'income':
        return existingKeySet(incomes);
      case 'fixed':
        return existingKeySet(fixedExpenses);
      case 'variable':
        return existingKeySet(variableExpenses);
    }
  }, [importType, subscriptions, incomes, fixedExpenses, variableExpenses]);

  // Duplicate report over the current preview rows (within-CSV + against existing).
  const duplicates: DuplicateReport | null = useMemo(
    () => (preview ? detectDuplicates(preview.rows, existingKeys) : null),
    [preview, existingKeys]
  );

  /** Reset everything back to the paste/empty state (keeps the chosen type). */
  const resetFlow = () => {
    setPreview(null);
    setImported(null);
    setHeaderAnalyzed(false);
    setHeaders([]);
    setMapping({});
    setFileError(null);
    setSkipDuplicates(false);
  };

  /** Analyze the current text's header and seed the user-overridable mapping. The
   *  remembered mapping for this type (if any) is pre-applied over the alias detect. */
  const runAnalyze = (source: string, type: ImportType = importType) => {
    const analysis = analyzeFor(type, source);
    setHeaders(analysis.headers);
    setMapping(applyRememberedMapping(type, analysis.autoMapping, analysis.headers.length));
    setHeaderAnalyzed(analysis.headers.length > 0);
    setPreview(null);
    setImported(null);
    setSkipDuplicates(false);
  };

  /** Switching type re-analyzes the current text against the new type's aliases. */
  const onChangeType = (type: ImportType) => {
    setImportType(type);
    setPreview(null);
    setImported(null);
    setFileError(null);
    if (text.trim().length > 0) runAnalyze(text, type);
    else {
      setHeaderAnalyzed(false);
      setHeaders([]);
      setMapping({});
    }
  };

  const onFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFileError(null);
    const file = e.target.files?.[0];
    if (!file) return;
    if (!file.name.toLowerCase().endsWith('.csv') && file.type !== 'text/csv') {
      setFileError('Only CSV files are supported.');
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      const content = String(reader.result ?? '');
      resetFlow();
      setText(content);
      runAnalyze(content);
    };
    reader.onerror = () => setFileError('Could not read file.');
    reader.readAsText(file);
    // Allow re-picking the same file.
    e.target.value = '';
  };

  const loadSample = () => {
    resetFlow();
    setText(spec.sample);
    runAnalyze(spec.sample);
  };

  /** Set (or clear, when `IGNORE`) a field's mapped column; invalidates the preview. */
  const setFieldColumn = (field: string, value: number) => {
    setMapping((prev) => {
      const next = { ...prev };
      if (value < 0) delete next[field];
      else next[field] = value;
      return next;
    });
    setPreview(null);
  };

  const requiredFieldsMapped = spec.required.every((f) => mapping[f] !== undefined);

  const runPreview = () => {
    if (!requiredFieldsMapped) return;
    setImported(null);
    setPreview(parseFor(importType, text, mapping, expenseCategories, categoryName));
  };

  const doImport = async () => {
    if (!preview) return;
    // The valid rows produced by each importer line up 1:1 with `preview.rows`
    // (same parse, same order), so the duplicate flags index both alike. When
    // "import non-duplicates only" is on, skip the flagged indices.
    const flagged = skipDuplicates && duplicates ? duplicates.flaggedIndices : new Set<number>();
    const keep = <T,>(items: T[]): T[] => items.filter((_, i) => !flagged.has(i));

    let count = 0;
    switch (importType) {
      case 'subscriptions': {
        const sub = parseSubscriptionsCSVWithMapping(text, mapping as Partial<Record<CSVField, number>>);
        const rows = keep(sub.valid);
        for (const s of rows) await add(s);
        count = rows.length;
        break;
      }
      case 'income': {
        const inc = parseIncomeCSVWithMapping(text, mapping as Partial<Record<IncomeCSVField, number>>);
        const rows = keep(inc.valid);
        for (const i of rows) await addIncome(i);
        count = rows.length;
        break;
      }
      case 'fixed': {
        const fx = parseFixedExpenseCSVWithMapping(
          text,
          mapping as Partial<Record<FixedExpenseCSVField, number>>,
          expenseCategories
        );
        const rows = keep(fx.valid);
        for (const e of rows) await addFixed(e);
        count = rows.length;
        break;
      }
      case 'variable': {
        const va = parseVariableExpenseCSVWithMapping(
          text,
          mapping as Partial<Record<VariableExpenseCSVField, number>>,
          expenseCategories
        );
        const rows = keep(va.valid);
        for (const e of rows) await addVariable(e);
        count = rows.length;
        break;
      }
    }
    // Remember this type's column→field mapping for the next import of the type.
    saveRememberedMapping(importType, mapping);
    resetFlow();
    setText('');
    setImported(count);
  };

  const importedNoun =
    importType === 'subscriptions'
      ? 'subscription'
      : importType === 'income'
        ? 'income source'
        : importType === 'fixed'
          ? 'fixed expense'
          : 'variable expense';

  const importedDestination = importType === 'subscriptions' ? '/subscriptions' : '/cash-flow';

  return (
    <Page title="Import CSV">
      <div className="fm-stack">
        <GlassCard>
          <label className="fm-field-label" htmlFor="import-type">
            What are you importing?
          </label>
          <select
            id="import-type"
            className="fm-select"
            style={{ marginBottom: 'var(--fm-space-3)' }}
            value={importType}
            onChange={(e) => onChangeType(e.target.value as ImportType)}
            aria-label="Import type"
          >
            {IMPORT_TYPES.map((t) => (
              <option key={t.value} value={t.value}>
                {t.label}
              </option>
            ))}
          </select>

          <div
            className="fm-secondary"
            style={{ fontSize: 'var(--fm-font-subheadline)', marginBottom: 'var(--fm-space-3)' }}
          >
            Paste a {IMPORT_TYPES.find((t) => t.value === importType)?.label.toLowerCase()} CSV or
            choose a file. Header aliases ({spec.hint}) are detected automatically; map any columns
            that don't match, then preview before anything is saved.
          </div>

          <label className="fm-field-label" htmlFor="csv-text">
            CSV text
          </label>
          <textarea
            id="csv-text"
            className="fm-input"
            style={{ minHeight: 140, fontFamily: 'ui-monospace, monospace', resize: 'vertical' }}
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder={'name,amount,currency\nExample,12.99,EUR'}
          />

          <div
            className="fm-row"
            style={{ gap: 'var(--fm-space-2)', marginTop: 'var(--fm-space-3)', flexWrap: 'wrap' }}
          >
            <button
              type="button"
              className="fm-btn"
              onClick={() => runAnalyze(text)}
              disabled={text.trim().length === 0}
            >
              Map columns
            </button>
            <button type="button" className="fm-btn-ghost fm-btn" onClick={loadSample}>
              Load sample
            </button>
            <label className="fm-btn-ghost fm-btn" style={{ cursor: 'pointer' }}>
              Choose file
              <input
                type="file"
                accept=".csv,text/csv"
                onChange={onFile}
                style={{ display: 'none' }}
              />
            </label>
          </div>

          {fileError && (
            <div className="fm-error" style={{ marginTop: 'var(--fm-space-2)' }} role="alert">
              {fileError}
            </div>
          )}
          {imported !== null && (
            <div style={{ marginTop: 'var(--fm-space-3)' }}>
              <div style={{ fontWeight: 600, marginBottom: 'var(--fm-space-2)' }}>
                Imported {imported} {importedNoun}
                {imported === 1 ? '' : 's'}.
              </div>
              <button
                type="button"
                className="fm-btn-ghost fm-btn"
                onClick={() => navigate(importedDestination)}
              >
                {importType === 'subscriptions' ? 'View subscriptions' : 'View cash flow'}
              </button>
            </div>
          )}
        </GlassCard>

        {headerAnalyzed && (
          <MappingSection
            fields={spec.fields}
            labels={spec.labels}
            required={spec.required}
            headers={headers}
            mapping={mapping}
            requiredFieldsMapped={requiredFieldsMapped}
            onChange={setFieldColumn}
            onPreview={runPreview}
          />
        )}

        {preview && (
          <PreviewSection
            preview={preview}
            spec={spec}
            importedNoun={importedNoun}
            duplicates={duplicates}
            skipDuplicates={skipDuplicates}
            onToggleSkipDuplicates={setSkipDuplicates}
            onImport={doImport}
          />
        )}
      </div>
    </Page>
  );
}

function MappingSection({
  fields,
  labels,
  required,
  headers,
  mapping,
  requiredFieldsMapped,
  onChange,
  onPreview,
}: {
  fields: readonly string[];
  labels: Record<string, string>;
  required: readonly string[];
  headers: string[];
  mapping: AnyMapping;
  requiredFieldsMapped: boolean;
  onChange: (field: string, value: number) => void;
  onPreview: () => void;
}) {
  const requiredLabel = required.map((f) => labels[f]).join(', ');
  return (
    <GlassCard>
      <div style={{ fontWeight: 600, marginBottom: 'var(--fm-space-1)' }}>Map columns</div>
      <div
        className="fm-secondary"
        style={{ fontSize: 'var(--fm-font-footnote)', marginBottom: 'var(--fm-space-3)' }}
      >
        Detected {headers.length} column{headers.length === 1 ? '' : 's'}. Match each Finmate field
        to a column. {requiredLabel} {required.length === 1 ? 'is' : 'are'} required.
      </div>

      <div className="fm-stack" style={{ gap: 'var(--fm-space-2)' }}>
        {fields.map((field) => {
          const isRequired = required.includes(field);
          const selectId = `map-${field}`;
          return (
            <div
              key={field}
              className="fm-row"
              style={{ justifyContent: 'space-between', gap: 'var(--fm-space-3)', alignItems: 'center' }}
            >
              <label className="fm-field-label" htmlFor={selectId} style={{ margin: 0 }}>
                {labels[field]}
                {isRequired && (
                  <span
                    style={{
                      color: 'var(--fm-warning)',
                      marginLeft: 'var(--fm-space-1)',
                      fontSize: 'var(--fm-font-caption)',
                    }}
                  >
                    Required
                  </span>
                )}
              </label>
              <select
                id={selectId}
                className="fm-select"
                style={{ maxWidth: 200 }}
                value={mapping[field] ?? IGNORE}
                onChange={(e) => onChange(field, Number(e.target.value))}
                aria-label={`${labels[field]} column`}
              >
                <option value={IGNORE}>— Ignore</option>
                {headers.map((token, idx) => (
                  <option key={idx} value={idx}>
                    {token.trim() === '' ? `Column ${idx + 1}` : token}
                  </option>
                ))}
              </select>
            </div>
          );
        })}
      </div>

      {!requiredFieldsMapped && (
        <div
          className="fm-error"
          style={{ marginTop: 'var(--fm-space-2)', fontSize: 'var(--fm-font-footnote)' }}
          role="alert"
        >
          Map {requiredLabel} to continue.
        </div>
      )}

      <button
        type="button"
        className="fm-btn"
        style={{ marginTop: 'var(--fm-space-3)', width: '100%' }}
        onClick={onPreview}
        disabled={!requiredFieldsMapped}
      >
        Preview rows
      </button>
    </GlassCard>
  );
}

function PreviewSection({
  preview,
  spec,
  importedNoun,
  duplicates,
  skipDuplicates,
  onToggleSkipDuplicates,
  onImport,
}: {
  preview: TypedPreview;
  spec: TypeSpec;
  importedNoun: string;
  duplicates: DuplicateReport | null;
  skipDuplicates: boolean;
  onToggleSkipDuplicates: (next: boolean) => void;
  onImport: () => void | Promise<void>;
}) {
  const dupCount = duplicates?.count ?? 0;
  // How many rows actually get written, given the skip-duplicates toggle.
  const importCount = skipDuplicates ? preview.rows.length - dupCount : preview.rows.length;
  return (
    <>
      <GlassCard>
        <div className="fm-row" style={{ justifyContent: 'space-between', marginBottom: 'var(--fm-space-3)' }}>
          <div style={{ fontWeight: 600 }}>
            Preview — {preview.rows.length} valid / {preview.errors.length} error
            {preview.errors.length === 1 ? '' : 's'} of {preview.totalRows} row
            {preview.totalRows === 1 ? '' : 's'}
          </div>
          <button
            type="button"
            className="fm-btn"
            onClick={() => void onImport()}
            disabled={importCount === 0}
          >
            Import {importCount} {skipDuplicates && dupCount > 0 ? 'non-duplicate' : 'valid'}
          </button>
        </div>

        {dupCount > 0 && (
          <div
            className="fm-row"
            style={{
              justifyContent: 'space-between',
              alignItems: 'center',
              gap: 'var(--fm-space-3)',
              marginBottom: 'var(--fm-space-3)',
              flexWrap: 'wrap',
            }}
          >
            <div className="fm-secondary" style={{ fontSize: 'var(--fm-font-footnote)' }} role="status">
              {dupCount} possible duplicate{dupCount === 1 ? '' : 's'} detected (matching an existing{' '}
              {importedNoun} or another row). Importing all rows by default — the hint is advisory.
            </div>
            <label
              className="fm-row"
              style={{
                gap: 'var(--fm-space-2)',
                alignItems: 'center',
                fontSize: 'var(--fm-font-footnote)',
                cursor: 'pointer',
              }}
            >
              <input
                type="checkbox"
                checked={skipDuplicates}
                onChange={(e) => onToggleSkipDuplicates(e.target.checked)}
                aria-label="Import non-duplicates only"
              />
              Import non-duplicates only
            </label>
          </div>
        )}

        {preview.rows.length > 0 ? (
          <div style={{ overflowX: 'auto' }}>
            <table
              style={{ width: '100%', borderCollapse: 'collapse', fontSize: 'var(--fm-font-callout)' }}
            >
              <thead>
                <tr style={{ textAlign: 'left' }}>
                  <th style={cellHead}>Name</th>
                  <th style={cellHead}>Amount</th>
                  {spec.hasCadence && <th style={cellHead}>Period</th>}
                  {spec.hasCategory && <th style={cellHead}>Category</th>}
                </tr>
              </thead>
              <tbody>
                {preview.rows.map((r, i) => {
                  const isDup = duplicates?.flaggedIndices.has(i) ?? false;
                  const dimmed = isDup && skipDuplicates;
                  return (
                    <tr
                      key={r.id}
                      style={{
                        borderTop: '1px solid var(--fm-hairline)',
                        opacity: dimmed ? 0.45 : 1,
                      }}
                    >
                      <td style={cell}>
                        {r.name}
                        {isDup && (
                          <span
                            style={dupBadge}
                            title="Matches an existing entry or another row in this file"
                          >
                            possible duplicate
                          </span>
                        )}
                      </td>
                      <td style={cell}>{formatMoney(r.amountMinor, r.currency)}</td>
                      {spec.hasCadence && <td style={cell}>{r.cadence ?? '—'}</td>}
                      {spec.hasCategory && <td style={cell}>{r.category ?? 'Uncategorized'}</td>}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="fm-secondary" style={{ fontSize: 'var(--fm-font-callout)' }}>
            No valid {importedNoun} rows to import.
          </div>
        )}
      </GlassCard>

      {preview.errors.length > 0 && (
        <GlassCard>
          <div style={{ fontWeight: 600, marginBottom: 'var(--fm-space-2)' }}>Errors</div>
          <ul style={{ margin: 0, paddingLeft: 18 }}>
            {preview.errors.map((e, i) => (
              <li key={`${e.row}-${e.field ?? 'file'}-${i}`} className="fm-error">
                {e.row === 0 ? 'File' : `Row ${e.row}`}
                {e.field ? ` · ${e.field}` : ''}: {e.message}
              </li>
            ))}
          </ul>
        </GlassCard>
      )}
    </>
  );
}

const cellHead: React.CSSProperties = {
  padding: 'var(--fm-space-1) var(--fm-space-2)',
  fontWeight: 600,
  color: 'var(--fm-label-secondary)',
};
const cell: React.CSSProperties = { padding: 'var(--fm-space-2)' };
const dupBadge: React.CSSProperties = {
  display: 'inline-block',
  marginLeft: 'var(--fm-space-2)',
  padding: '1px 8px',
  borderRadius: 'var(--fm-radius-pill)',
  fontSize: 'var(--fm-font-caption2)',
  fontWeight: 600,
  color: 'var(--fm-warning)',
  border: '1px solid var(--fm-warning)',
  verticalAlign: 'middle',
  whiteSpace: 'nowrap',
};

// CSV Import page (M6) — load · map · preview · partial import. Choose an import
// type (Subscriptions / Income / Fixed expenses / Variable expenses), paste or upload
// a CSV, review/override the detected column→field mapping (auto-seeded from the alias
// match), preview the valid rows + errors before anything is written, then import only
// the valid rows via the matching repository hook (same create path as manual add). One
// glass language; reuses GlassCard + glass tokens. Logic lives in core/csvImport.ts.

import { useState } from 'react';
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
  type CSVField,
  type IncomeCSVField,
  type FixedExpenseCSVField,
  type VariableExpenseCSVField,
  type ImportRowError,
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
  const { add } = useSubscriptions();
  const {
    addIncome,
    addFixed,
    addVariable,
    expenseCategories,
    categoryName,
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

  /** Reset everything back to the paste/empty state (keeps the chosen type). */
  const resetFlow = () => {
    setPreview(null);
    setImported(null);
    setHeaderAnalyzed(false);
    setHeaders([]);
    setMapping({});
    setFileError(null);
  };

  /** Analyze the current text's header and seed the user-overridable mapping. */
  const runAnalyze = (source: string, type: ImportType = importType) => {
    const analysis = analyzeFor(type, source);
    setHeaders(analysis.headers);
    setMapping(analysis.autoMapping);
    setHeaderAnalyzed(analysis.headers.length > 0);
    setPreview(null);
    setImported(null);
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
    const p = parseFor(importType, text, mapping, expenseCategories, categoryName);
    const count = p.rows.length;
    switch (importType) {
      case 'subscriptions': {
        const sub = parseSubscriptionsCSVWithMapping(text, mapping as Partial<Record<CSVField, number>>);
        for (const s of sub.valid) await add(s);
        break;
      }
      case 'income': {
        const inc = parseIncomeCSVWithMapping(text, mapping as Partial<Record<IncomeCSVField, number>>);
        for (const i of inc.valid) await addIncome(i);
        break;
      }
      case 'fixed': {
        const fx = parseFixedExpenseCSVWithMapping(
          text,
          mapping as Partial<Record<FixedExpenseCSVField, number>>,
          expenseCategories
        );
        for (const e of fx.valid) await addFixed(e);
        break;
      }
      case 'variable': {
        const va = parseVariableExpenseCSVWithMapping(
          text,
          mapping as Partial<Record<VariableExpenseCSVField, number>>,
          expenseCategories
        );
        for (const e of va.valid) await addVariable(e);
        break;
      }
    }
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
            style={{ marginBottom: 12 }}
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

          <div className="fm-secondary" style={{ fontSize: 14, marginBottom: 12 }}>
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

          <div className="fm-row" style={{ gap: 10, marginTop: 12, flexWrap: 'wrap' }}>
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
            <div className="fm-error" style={{ marginTop: 10 }} role="alert">
              {fileError}
            </div>
          )}
          {imported !== null && (
            <div style={{ marginTop: 12 }}>
              <div style={{ fontWeight: 600, marginBottom: 6 }}>
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
      <div style={{ fontWeight: 600, marginBottom: 4 }}>Map columns</div>
      <div className="fm-secondary" style={{ fontSize: 13, marginBottom: 12 }}>
        Detected {headers.length} column{headers.length === 1 ? '' : 's'}. Match each Finmate field
        to a column. {requiredLabel} {required.length === 1 ? 'is' : 'are'} required.
      </div>

      <div className="fm-stack" style={{ gap: 8 }}>
        {fields.map((field) => {
          const isRequired = required.includes(field);
          const selectId = `map-${field}`;
          return (
            <div
              key={field}
              className="fm-row"
              style={{ justifyContent: 'space-between', gap: 12, alignItems: 'center' }}
            >
              <label className="fm-field-label" htmlFor={selectId} style={{ margin: 0 }}>
                {labels[field]}
                {isRequired && (
                  <span style={{ color: 'var(--fm-warning, #d97706)', marginLeft: 6, fontSize: 12 }}>
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
        <div className="fm-error" style={{ marginTop: 10, fontSize: 13 }} role="alert">
          Map {requiredLabel} to continue.
        </div>
      )}

      <button
        type="button"
        className="fm-btn"
        style={{ marginTop: 12, width: '100%' }}
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
  onImport,
}: {
  preview: TypedPreview;
  spec: TypeSpec;
  importedNoun: string;
  onImport: () => void | Promise<void>;
}) {
  return (
    <>
      <GlassCard>
        <div className="fm-row" style={{ justifyContent: 'space-between', marginBottom: 12 }}>
          <div style={{ fontWeight: 600 }}>
            Preview — {preview.rows.length} valid / {preview.errors.length} error
            {preview.errors.length === 1 ? '' : 's'} of {preview.totalRows} row
            {preview.totalRows === 1 ? '' : 's'}
          </div>
          <button
            type="button"
            className="fm-btn"
            onClick={() => void onImport()}
            disabled={preview.rows.length === 0}
          >
            Import {preview.rows.length} valid
          </button>
        </div>

        {preview.rows.length > 0 ? (
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 14 }}>
              <thead>
                <tr style={{ textAlign: 'left' }}>
                  <th style={cellHead}>Name</th>
                  <th style={cellHead}>Amount</th>
                  {spec.hasCadence && <th style={cellHead}>Period</th>}
                  {spec.hasCategory && <th style={cellHead}>Category</th>}
                </tr>
              </thead>
              <tbody>
                {preview.rows.map((r) => (
                  <tr key={r.id} style={{ borderTop: '1px solid var(--fm-glass-border)' }}>
                    <td style={cell}>{r.name}</td>
                    <td style={cell}>{formatMoney(r.amountMinor, r.currency)}</td>
                    {spec.hasCadence && <td style={cell}>{r.cadence ?? '—'}</td>}
                    {spec.hasCategory && <td style={cell}>{r.category ?? 'Uncategorized'}</td>}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="fm-secondary" style={{ fontSize: 14 }}>
            No valid {importedNoun} rows to import.
          </div>
        )}
      </GlassCard>

      {preview.errors.length > 0 && (
        <GlassCard>
          <div style={{ fontWeight: 600, marginBottom: 8 }}>Errors</div>
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
  padding: '6px 8px',
  fontWeight: 600,
  color: 'var(--fm-label-secondary)',
};
const cell: React.CSSProperties = { padding: '8px' };

// CSV Import page (M6) — load · map · preview · partial import. Paste or upload a
// subscriptions CSV, review/override the detected column→field mapping (auto-seeded
// from the alias match), preview the valid rows + errors before anything is written,
// then import only the valid rows via the shared subscriptions hook (same create path
// as manual add). One glass language; reuses GlassCard + glass tokens. Logic lives in
// core/csvImport.ts.

import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { GlassCard } from '../../components/GlassCard';
import { Page } from '../../components/AppShell';
import { useSubscriptions } from '../subscriptions/useSubscriptions';
import { formatMoney } from '../../core/money';
import {
  analyzeHeader,
  parseSubscriptionsCSVWithMapping,
  CSV_FIELDS,
  SAMPLE_CSV,
  type ColumnMapping,
  type CSVField,
  type ImportPreview,
} from '../../core/csvImport';

/** Human-facing labels for each canonical field (mirrors the Swift `displayName`). */
const FIELD_LABELS: Record<CSVField, string> = {
  name: 'Name',
  amount: 'Amount',
  currency: 'Currency',
  billing_period: 'Billing period',
  payment_method: 'Payment method',
  category: 'Category',
  usage_state: 'Usage state',
  start_date: 'Start date',
  vendor_url: 'URL',
};

/** Required fields must resolve to a column before previewing (mirrors `isRequired`). */
const REQUIRED_FIELDS: readonly CSVField[] = ['name', 'amount'];

/** Sentinel select value meaning "ignore this field" (no column mapped). */
const IGNORE = -1;

export function Import() {
  const navigate = useNavigate();
  const { add } = useSubscriptions();

  const [text, setText] = useState('');

  // Column mapping: the detected header tokens + the user-overridable field→column
  // map. `headerAnalyzed` gates the mapping card (paste-only state before then).
  const [headers, setHeaders] = useState<string[]>([]);
  const [mapping, setMapping] = useState<ColumnMapping>({});
  const [headerAnalyzed, setHeaderAnalyzed] = useState(false);

  const [preview, setPreview] = useState<ImportPreview | null>(null);
  const [fileError, setFileError] = useState<string | null>(null);
  const [imported, setImported] = useState<number | null>(null);

  /** Reset everything back to the paste/empty state. */
  const resetFlow = () => {
    setPreview(null);
    setImported(null);
    setHeaderAnalyzed(false);
    setHeaders([]);
    setMapping({});
    setFileError(null);
  };

  /** Analyze the current text's header and seed the user-overridable mapping. */
  const runAnalyze = (source: string) => {
    const analysis = analyzeHeader(source);
    setHeaders(analysis.headers);
    setMapping(analysis.autoMapping);
    setHeaderAnalyzed(analysis.headers.length > 0);
    setPreview(null);
    setImported(null);
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
    setText(SAMPLE_CSV);
    runAnalyze(SAMPLE_CSV);
  };

  /** Set (or clear, when `IGNORE`) a field's mapped column; invalidates the preview. */
  const setFieldColumn = (field: CSVField, value: number) => {
    setMapping((prev) => {
      const next = { ...prev };
      if (value < 0) delete next[field];
      else next[field] = value;
      return next;
    });
    setPreview(null);
  };

  const requiredFieldsMapped = REQUIRED_FIELDS.every((f) => mapping[f] !== undefined);

  const runPreview = () => {
    if (!requiredFieldsMapped) return;
    setImported(null);
    setPreview(parseSubscriptionsCSVWithMapping(text, mapping));
  };

  const doImport = async () => {
    if (!preview) return;
    const toImport = preview.valid;
    for (const sub of toImport) {
      await add(sub);
    }
    const count = toImport.length;
    resetFlow();
    setText('');
    setImported(count);
  };

  return (
    <Page title="Import CSV">
      <div className="fm-stack">
        <GlassCard>
          <div className="fm-secondary" style={{ fontSize: 14, marginBottom: 12 }}>
            Paste a subscriptions CSV or choose a file. Header aliases (name / amount /
            currency / billing_period / payment_method / category / usage_state /
            start_date / url) are detected automatically; map any columns that don't
            match, then preview before anything is saved.
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
            placeholder={'name,amount,currency,billing_period\nNetflix,12.99,EUR,monthly'}
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
                Imported {imported} subscription{imported === 1 ? '' : 's'}.
              </div>
              <button
                type="button"
                className="fm-btn-ghost fm-btn"
                onClick={() => navigate('/subscriptions')}
              >
                View subscriptions
              </button>
            </div>
          )}
        </GlassCard>

        {headerAnalyzed && (
          <MappingSection
            headers={headers}
            mapping={mapping}
            requiredFieldsMapped={requiredFieldsMapped}
            onChange={setFieldColumn}
            onPreview={runPreview}
          />
        )}

        {preview && <PreviewSection preview={preview} onImport={doImport} />}
      </div>
    </Page>
  );
}

function MappingSection({
  headers,
  mapping,
  requiredFieldsMapped,
  onChange,
  onPreview,
}: {
  headers: string[];
  mapping: ColumnMapping;
  requiredFieldsMapped: boolean;
  onChange: (field: CSVField, value: number) => void;
  onPreview: () => void;
}) {
  return (
    <GlassCard>
      <div style={{ fontWeight: 600, marginBottom: 4 }}>Map columns</div>
      <div className="fm-secondary" style={{ fontSize: 13, marginBottom: 12 }}>
        Detected {headers.length} column{headers.length === 1 ? '' : 's'}. Match each
        Finmate field to a column. Name and Amount are required.
      </div>

      <div className="fm-stack" style={{ gap: 8 }}>
        {CSV_FIELDS.map((field) => {
          const required = REQUIRED_FIELDS.includes(field);
          const selectId = `map-${field}`;
          return (
            <div
              key={field}
              className="fm-row"
              style={{ justifyContent: 'space-between', gap: 12, alignItems: 'center' }}
            >
              <label className="fm-field-label" htmlFor={selectId} style={{ margin: 0 }}>
                {FIELD_LABELS[field]}
                {required && (
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
                aria-label={`${FIELD_LABELS[field]} column`}
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
          Map Name and Amount to continue.
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
  onImport,
}: {
  preview: ImportPreview;
  onImport: () => void | Promise<void>;
}) {
  return (
    <>
      <GlassCard>
        <div className="fm-row" style={{ justifyContent: 'space-between', marginBottom: 12 }}>
          <div style={{ fontWeight: 600 }}>
            Preview — {preview.valid.length} valid / {preview.errors.length} error
            {preview.errors.length === 1 ? '' : 's'} of {preview.totalRows} row
            {preview.totalRows === 1 ? '' : 's'}
          </div>
          <button
            type="button"
            className="fm-btn"
            onClick={() => void onImport()}
            disabled={preview.valid.length === 0}
          >
            Import {preview.valid.length} valid
          </button>
        </div>

        {preview.valid.length > 0 ? (
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 14 }}>
              <thead>
                <tr style={{ textAlign: 'left' }}>
                  <th style={cellHead}>Name</th>
                  <th style={cellHead}>Amount</th>
                  <th style={cellHead}>Period</th>
                  <th style={cellHead}>Category</th>
                </tr>
              </thead>
              <tbody>
                {preview.valid.map((s) => (
                  <tr key={s.id} style={{ borderTop: '1px solid var(--fm-glass-border)' }}>
                    <td style={cell}>{s.name}</td>
                    <td style={cell}>{formatMoney(s.amountMinor, s.currency)}</td>
                    <td style={cell}>{s.billingPeriod}</td>
                    <td style={cell}>{s.categoryName}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="fm-secondary" style={{ fontSize: 14 }}>
            No valid rows to import.
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

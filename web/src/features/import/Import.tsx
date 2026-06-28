// CSV Import page (M6) — paste or upload a subscriptions CSV, preview the valid
// rows + errors before anything is written, then import only the valid rows via
// the shared subscriptions hook (same create path as manual add). One glass
// language; reuses GlassCard + glass tokens. Logic lives in core/csvImport.ts.

import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { GlassCard } from '../../components/GlassCard';
import { Page } from '../../components/AppShell';
import { useSubscriptions } from '../subscriptions/useSubscriptions';
import { formatMoney } from '../../core/money';
import {
  parseSubscriptionsCSV,
  SAMPLE_CSV,
  type ImportPreview,
} from '../../core/csvImport';

export function Import() {
  const navigate = useNavigate();
  const { add } = useSubscriptions();
  const [text, setText] = useState('');
  const [preview, setPreview] = useState<ImportPreview | null>(null);
  const [fileError, setFileError] = useState<string | null>(null);
  const [imported, setImported] = useState<number | null>(null);

  const runPreview = (source: string) => {
    setImported(null);
    setPreview(parseSubscriptionsCSV(source));
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
      setText(content);
      runPreview(content);
    };
    reader.readAsText(file);
  };

  const loadSample = () => {
    setFileError(null);
    setText(SAMPLE_CSV);
    runPreview(SAMPLE_CSV);
  };

  const doImport = async () => {
    if (!preview) return;
    for (const sub of preview.valid) {
      await add(sub);
    }
    setImported(preview.valid.length);
    setPreview(null);
    setText('');
  };

  return (
    <Page title="Import CSV">
      <div className="fm-stack">
        <GlassCard>
          <div className="fm-secondary" style={{ fontSize: 14, marginBottom: 12 }}>
            Paste a subscriptions CSV or choose a file. We map common column names
            (name / amount / currency / billing_period / payment_method / category /
            usage_state / start_date / url), validate every row, and let you preview
            before anything is saved.
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
              onClick={() => runPreview(text)}
              disabled={text.trim().length === 0}
            >
              Preview
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

        {preview && (
          <PreviewSection preview={preview} onImport={doImport} />
        )}
      </div>
    </Page>
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

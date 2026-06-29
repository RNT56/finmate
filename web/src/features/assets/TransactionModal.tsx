// Record-transaction modal for an asset — buy / sell / dividend / other under
// average-cost basis (ADR-0015). Builds validated inputs via the pure assetForm helper;
// the hook applies the pure `applyTransaction` and re-marks the asset so the portfolio
// value/gain recompute. Same GlassCard overlay + glass form styles as AddSubscription.

import { useState } from 'react';
import { GlassCard } from '../../components/GlassCard';
import type { AssetTransactionKind, FinancialAsset } from '../../core/assets';
import { buildTransaction, type TransactionFormDraft, type TransactionInput } from './assetForm';

interface Props {
  asset: FinancialAsset;
  onSubmit: (input: TransactionInput) => void | Promise<void>;
  onClose: () => void;
}

const KINDS: { value: AssetTransactionKind; label: string }[] = [
  { value: 'buy', label: 'Buy' },
  { value: 'sell', label: 'Sell' },
  { value: 'dividend', label: 'Dividend' },
  { value: 'other', label: 'Other' },
];

export function TransactionModal({ asset, onSubmit, onClose }: Props) {
  const [draft, setDraft] = useState<TransactionFormDraft>({
    kind: 'buy',
    quantity: '',
    price: '',
    fees: '',
  });
  const [error, setError] = useState<string | null>(null);

  const set = <K extends keyof TransactionFormDraft>(key: K, value: TransactionFormDraft[K]) =>
    setDraft((d) => ({ ...d, [key]: value }));

  const movesQuantity = draft.kind === 'buy' || draft.kind === 'sell';

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    const result = buildTransaction(draft, asset.currency);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    void onSubmit(result.value);
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={`Record transaction for ${asset.name}`}
      onClick={onClose}
      className="fm-modal-overlay"
    >
      <GlassCard className="fm-modal-sheet">
        <div onClick={(e) => e.stopPropagation()}>
          <h2 className="fm-modal-title" style={{ marginBottom: 'var(--fm-space-1)' }}>
            Record transaction
          </h2>
          <div
            className="fm-secondary"
            style={{ fontSize: 'var(--fm-font-footnote)', marginBottom: 'var(--fm-space-3)' }}
          >
            {asset.name} · {asset.currency}
          </div>
          <form className="fm-stack" onSubmit={submit}>
            <div>
              <label className="fm-field-label" htmlFor="txn-kind">
                Type
              </label>
              <select
                id="txn-kind"
                className="fm-select"
                value={draft.kind}
                onChange={(e) => set('kind', e.target.value as AssetTransactionKind)}
              >
                {KINDS.map((k) => (
                  <option key={k.value} value={k.value}>
                    {k.label}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="fm-field-label" htmlFor="txn-qty">
                Quantity{movesQuantity ? '' : ' (optional)'}
              </label>
              <input
                id="txn-qty"
                className="fm-input"
                inputMode="decimal"
                placeholder="0.0"
                value={draft.quantity}
                onChange={(e) => set('quantity', e.target.value)}
              />
            </div>

            <div className="fm-row" style={{ gap: 'var(--fm-space-3)' }}>
              <div style={{ flex: 1 }}>
                <label className="fm-field-label" htmlFor="txn-price">
                  Price per unit
                </label>
                <input
                  id="txn-price"
                  className="fm-input"
                  inputMode="decimal"
                  placeholder="50000"
                  value={draft.price}
                  onChange={(e) => set('price', e.target.value)}
                />
              </div>
              <div style={{ flex: 1 }}>
                <label className="fm-field-label" htmlFor="txn-fees">
                  Fees (optional)
                </label>
                <input
                  id="txn-fees"
                  className="fm-input"
                  inputMode="decimal"
                  placeholder="0.00"
                  value={draft.fees}
                  onChange={(e) => set('fees', e.target.value)}
                />
              </div>
            </div>

            {error && <div className="fm-error">{error}</div>}

            <div className="fm-modal-actions">
              <button type="button" className="fm-btn fm-btn-ghost" onClick={onClose}>
                Cancel
              </button>
              <button type="submit" className="fm-btn">
                Record
              </button>
            </div>
          </form>
        </div>
      </GlassCard>
    </div>
  );
}

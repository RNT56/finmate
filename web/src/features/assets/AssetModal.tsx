// Add/Edit modal for a FinancialAsset. Mirrors the AddSubscription template: GlassCard
// overlay, shared glass form styles, money parsed via the core parser. Builds the asset
// through the pure assetForm helpers (unit-tested) so validation lives outside React.

import { useState } from 'react';
import { GlassCard } from '../../components/GlassCard';
import type { CurrencyCode } from '../../core/currency';
import { allAssetTypes, assetTypeLabel, type AssetType, type FinancialAsset } from '../../core/assets';
import { majorValue } from '../../core/money';
import { buildAsset, newAssetId, type AssetFormDraft } from './assetForm';

interface Props {
  existing: FinancialAsset | null;
  onSave: (asset: FinancialAsset) => void | Promise<void>;
  onClose: () => void;
}

const CURRENCIES: CurrencyCode[] = ['EUR', 'USD', 'BTC'];

function majorString(minor: number, currency: CurrencyCode): string {
  if (minor === 0) return '';
  return String(majorValue(minor, currency));
}

function initialDraft(existing: FinancialAsset | null): AssetFormDraft {
  if (!existing) {
    return {
      name: '',
      type: 'crypto',
      currency: 'EUR',
      quantity: '',
      costBasis: '',
      unitPrice: '',
      notes: '',
    };
  }
  return {
    name: existing.name,
    type: existing.type,
    currency: existing.currency,
    quantity: existing.quantity === 0 ? '' : String(existing.quantity),
    costBasis: majorString(existing.purchasePriceMinor, existing.currency),
    unitPrice: majorString(existing.currentPriceMinor, existing.currency),
    notes: existing.notes ?? '',
  };
}

export function AssetModal({ existing, onSave, onClose }: Props) {
  const [draft, setDraft] = useState<AssetFormDraft>(() => initialDraft(existing));
  const [error, setError] = useState<string | null>(null);

  const id = existing ? existing.id : newAssetId();
  const set = <K extends keyof AssetFormDraft>(key: K, value: AssetFormDraft[K]) =>
    setDraft((d) => ({ ...d, [key]: value }));

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    const result = buildAsset(draft, id);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    void onSave(result.value);
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={existing ? 'Edit asset' : 'Add asset'}
      onClick={onClose}
      className="fm-modal-overlay"
    >
      <GlassCard className="fm-modal-sheet">
        <div onClick={(e) => e.stopPropagation()}>
          <h2 className="fm-modal-title">{existing ? 'Edit asset' : 'Add asset'}</h2>
          <form className="fm-stack" onSubmit={submit}>
            <div>
              <label className="fm-field-label" htmlFor="asset-name">
                Name (e.g. Bitcoin, World ETF)
              </label>
              <input
                id="asset-name"
                className="fm-input"
                value={draft.name}
                autoFocus
                onChange={(e) => set('name', e.target.value)}
              />
            </div>

            <div className="fm-row" style={{ gap: 'var(--fm-space-3)' }}>
              <div style={{ flex: 1 }}>
                <label className="fm-field-label" htmlFor="asset-type">
                  Type
                </label>
                <select
                  id="asset-type"
                  className="fm-select"
                  value={draft.type}
                  onChange={(e) => set('type', e.target.value as AssetType)}
                >
                  {allAssetTypes.map((t) => (
                    <option key={t} value={t}>
                      {assetTypeLabel(t)}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="fm-field-label" htmlFor="asset-currency">
                  Currency
                </label>
                <select
                  id="asset-currency"
                  className="fm-select"
                  value={draft.currency}
                  onChange={(e) => set('currency', e.target.value as CurrencyCode)}
                >
                  {CURRENCIES.map((c) => (
                    <option key={c} value={c}>
                      {c}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            <div>
              <label className="fm-field-label" htmlFor="asset-qty">
                Quantity (units / coins)
              </label>
              <input
                id="asset-qty"
                className="fm-input"
                inputMode="decimal"
                placeholder="0.5"
                value={draft.quantity}
                onChange={(e) => set('quantity', e.target.value)}
              />
            </div>

            <div className="fm-row" style={{ gap: 'var(--fm-space-3)' }}>
              <div style={{ flex: 1 }}>
                <label className="fm-field-label" htmlFor="asset-cost">
                  Total cost basis
                </label>
                <input
                  id="asset-cost"
                  className="fm-input"
                  inputMode="decimal"
                  placeholder="20000"
                  value={draft.costBasis}
                  onChange={(e) => set('costBasis', e.target.value)}
                />
              </div>
              <div style={{ flex: 1 }}>
                <label className="fm-field-label" htmlFor="asset-price">
                  Price per unit
                </label>
                <input
                  id="asset-price"
                  className="fm-input"
                  inputMode="decimal"
                  placeholder="50000"
                  value={draft.unitPrice}
                  onChange={(e) => set('unitPrice', e.target.value)}
                />
              </div>
            </div>

            <div>
              <label className="fm-field-label" htmlFor="asset-notes">
                Notes (optional)
              </label>
              <input
                id="asset-notes"
                className="fm-input"
                value={draft.notes}
                onChange={(e) => set('notes', e.target.value)}
              />
            </div>

            {error && <div className="fm-error">{error}</div>}

            <div className="fm-modal-actions">
              <button type="button" className="fm-btn fm-btn-ghost" onClick={onClose}>
                Cancel
              </button>
              <button type="submit" className="fm-btn">
                Save
              </button>
            </div>
          </form>
        </div>
      </GlassCard>
    </div>
  );
}

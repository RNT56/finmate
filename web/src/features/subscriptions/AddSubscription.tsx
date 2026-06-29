// AddSubscription — mirrors the iOS AddSubscriptionView. Live category inference
// via the ported predictor; amount parsed through the core money parser (HALF-UP,
// rejects over-precision / negatives).

import { useMemo, useState } from 'react';
import { GlassCard } from '../../components/GlassCard';
import { predict } from '../../core/predictor';
import { parseMoney, MoneyError } from '../../core/money';
import type { Subscription } from './types';
import type { BillingPeriod } from '../../core/normalization';

interface Props {
  onSave: (sub: Subscription) => void | Promise<void>;
  onClose: () => void;
}

export function AddSubscription({ onSave, onClose }: Props) {
  const [name, setName] = useState('');
  const [amount, setAmount] = useState('');
  const [period, setPeriod] = useState<BillingPeriod>('monthly');
  const [error, setError] = useState<string | null>(null);

  // Live prediction: a recognized name auto-fills the category (and a suggested cost).
  const prediction = useMemo(() => predict(name), [name]);
  const inferredCategory = prediction?.category ?? 'Other';

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    const raw = amount.trim();
    let minor: number;
    try {
      minor = raw === '' ? 0 : parseMoney(raw, 'EUR');
    } catch (err) {
      setError(
        err instanceof MoneyError && err.kind === 'tooManyFractionalDigits'
          ? 'Enter a valid amount (max 2 decimals).'
          : 'Enter a valid, non-negative amount.',
      );
      return;
    }
    if (!name.trim()) {
      setError('Enter a service name.');
      return;
    }
    void onSave({
      id: `sub-${Date.now()}`,
      name: name.trim(),
      vendorURL: prediction?.vendorURL ?? null,
      icon: prediction?.icon ?? null,
      amountMinor: minor,
      currency: 'EUR',
      billingPeriod: period,
      paymentMethod: 'other',
      categoryName: inferredCategory,
      usageState: 'active',
      favorite: false,
      sortOrder: Number.MAX_SAFE_INTEGER,
      startDate: new Date().toISOString().slice(0, 10),
    });
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Add subscription"
      onClick={onClose}
      className="fm-modal-overlay"
    >
      <GlassCard className="fm-modal-sheet">
        <div onClick={(e) => e.stopPropagation()}>
          <h2 className="fm-modal-title">Add subscription</h2>
          <form className="fm-stack" onSubmit={submit}>
            <div>
              <label className="fm-field-label" htmlFor="sub-name">
                Name (e.g. Netflix, ChatGPT)
              </label>
              <input
                id="sub-name"
                className="fm-input"
                data-testid="subscription-name"
                value={name}
                autoFocus
                onChange={(e) => setName(e.target.value)}
              />
            </div>

            <div>
              <span className="fm-field-label">Category (auto)</span>
              <span className="fm-badge" aria-live="polite">
                {inferredCategory}
              </span>
            </div>

            <div>
              <label className="fm-field-label" htmlFor="sub-amount">
                Amount in EUR
              </label>
              <input
                id="sub-amount"
                className="fm-input"
                data-testid="subscription-amount"
                inputMode="decimal"
                placeholder="12.99"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
              />
            </div>

            <div>
              <label className="fm-field-label" htmlFor="sub-period">
                Billing period
              </label>
              <select
                id="sub-period"
                className="fm-select"
                value={period}
                onChange={(e) => setPeriod(e.target.value as BillingPeriod)}
              >
                <option value="weekly">Weekly</option>
                <option value="monthly">Monthly</option>
                <option value="quarterly">Quarterly</option>
                <option value="yearly">Yearly</option>
              </select>
            </div>

            {error && <div className="fm-error">{error}</div>}

            <div className="fm-modal-actions">
              <button type="button" className="fm-btn fm-btn-ghost" onClick={onClose}>
                Cancel
              </button>
              <button type="submit" className="fm-btn" data-testid="subscription-save">
                Save
              </button>
            </div>
          </form>
        </div>
      </GlassCard>
    </div>
  );
}

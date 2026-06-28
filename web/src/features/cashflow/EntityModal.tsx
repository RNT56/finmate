// Add/Edit modal for an Income source, Fixed expense, or Variable expense.
// Mirrors the iOS Add forms and the web AddSubscription template: GlassCard overlay,
// shared glass form styles, amount parsed via the core money parser. Builds the entity
// through the pure entityForm helpers (unit-tested) so validation lives outside React.

import { useState } from 'react';
import { GlassCard } from '../../components/GlassCard';
import type { CurrencyCode } from '../../core/currency';
import type { BillingPeriod, IncomeFrequency } from '../../core/normalization';
import {
  buildFixed,
  buildIncome,
  buildVariable,
  newEntityId,
  type EntityFormDraft,
  type EntityKind,
} from './entityForm';
import { majorValue } from '../../core/money';
import type { FixedExpense, IncomeSource, VariableExpense } from './types';

type Entity = IncomeSource | FixedExpense | VariableExpense;

interface Props {
  kind: EntityKind;
  /** Existing entity for edit; null for add. */
  existing: Entity | null;
  onSave: (entity: Entity) => void | Promise<void>;
  onClose: () => void;
}

const CURRENCIES: CurrencyCode[] = ['EUR', 'USD', 'BTC'];

const INCOME_FREQUENCIES: { value: IncomeFrequency; label: string }[] = [
  { value: 'weekly', label: 'Weekly' },
  { value: 'monthly', label: 'Monthly' },
  { value: 'yearly', label: 'Yearly' },
  { value: 'one_time', label: 'One-time' },
];

const BILLING_PERIODS: { value: BillingPeriod; label: string }[] = [
  { value: 'weekly', label: 'Weekly' },
  { value: 'monthly', label: 'Monthly' },
  { value: 'quarterly', label: 'Quarterly' },
  { value: 'yearly', label: 'Yearly' },
];

const TITLES: Record<EntityKind, { add: string; edit: string; label: string }> = {
  income: { add: 'Add income', edit: 'Edit income', label: 'income source' },
  fixed: { add: 'Add fixed expense', edit: 'Edit fixed expense', label: 'fixed expense' },
  variable: { add: 'Add variable expense', edit: 'Edit variable expense', label: 'variable expense' },
};

/** Amount as a plain major-unit string for prefilling the edit form. */
function amountString(minor: number, currency: CurrencyCode): string {
  if (minor === 0) return '';
  return String(majorValue(minor, currency));
}

function initialDraft(kind: EntityKind, existing: Entity | null): EntityFormDraft {
  if (!existing) {
    return {
      name: '',
      amount: '',
      currency: 'EUR',
      cadence: kind === 'income' ? 'monthly' : 'monthly',
      categoryName: '',
      date: '',
    };
  }
  if (kind === 'income') {
    const inc = existing as IncomeSource;
    return {
      name: inc.name,
      amount: amountString(inc.amountMinor, inc.currency),
      currency: inc.currency,
      cadence: inc.frequency,
      categoryName: '',
      date: inc.nextPayment ?? '',
    };
  }
  if (kind === 'fixed') {
    const fx = existing as FixedExpense;
    return {
      name: fx.name,
      amount: amountString(fx.amountMinor, fx.currency),
      currency: fx.currency,
      cadence: fx.billingPeriod,
      categoryName: fx.categoryName,
      date: fx.dueDate ?? '',
    };
  }
  const va = existing as VariableExpense;
  return {
    name: va.name,
    amount: amountString(va.amountMinor, va.currency),
    currency: va.currency,
    cadence: 'monthly',
    categoryName: va.categoryName,
    date: va.spentOn,
  };
}

export function EntityModal({ kind, existing, onSave, onClose }: Props) {
  const [draft, setDraft] = useState<EntityFormDraft>(() => initialDraft(kind, existing));
  const [error, setError] = useState<string | null>(null);

  const titles = TITLES[kind];
  const id = existing ? (existing as Entity).id : newEntityId(kind === 'income' ? 'inc' : kind === 'fixed' ? 'fix' : 'var');
  const set = <K extends keyof EntityFormDraft>(key: K, value: EntityFormDraft[K]) =>
    setDraft((d) => ({ ...d, [key]: value }));

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    const result =
      kind === 'income'
        ? buildIncome(draft, id)
        : kind === 'fixed'
          ? buildFixed(draft, id)
          : buildVariable(draft, id);
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
      aria-label={existing ? titles.edit : titles.add}
      onClick={onClose}
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0,0,0,0.35)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 16,
        zIndex: 100,
      }}
    >
      <GlassCard className="fm-glass" style={{ width: 'min(440px, 100%)' }}>
        <div onClick={(e) => e.stopPropagation()}>
          <h2 style={{ marginTop: 0, fontSize: 20 }}>{existing ? titles.edit : titles.add}</h2>
          <form className="fm-stack" onSubmit={submit}>
            <div>
              <label className="fm-field-label" htmlFor="ent-name">
                Name
              </label>
              <input
                id="ent-name"
                className="fm-input"
                value={draft.name}
                autoFocus
                onChange={(e) => set('name', e.target.value)}
              />
            </div>

            <div className="fm-row" style={{ gap: 12 }}>
              <div style={{ flex: 1 }}>
                <label className="fm-field-label" htmlFor="ent-amount">
                  Amount
                </label>
                <input
                  id="ent-amount"
                  className="fm-input"
                  inputMode="decimal"
                  placeholder="0.00"
                  value={draft.amount}
                  onChange={(e) => set('amount', e.target.value)}
                />
              </div>
              <div>
                <label className="fm-field-label" htmlFor="ent-currency">
                  Currency
                </label>
                <select
                  id="ent-currency"
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

            {kind !== 'variable' && (
              <div>
                <label className="fm-field-label" htmlFor="ent-cadence">
                  {kind === 'income' ? 'Frequency' : 'Billing period'}
                </label>
                <select
                  id="ent-cadence"
                  className="fm-select"
                  value={draft.cadence}
                  onChange={(e) => set('cadence', e.target.value as IncomeFrequency | BillingPeriod)}
                >
                  {(kind === 'income' ? INCOME_FREQUENCIES : BILLING_PERIODS).map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                    </option>
                  ))}
                </select>
              </div>
            )}

            {kind !== 'income' && (
              <div>
                <label className="fm-field-label" htmlFor="ent-category">
                  Category
                </label>
                <input
                  id="ent-category"
                  className="fm-input"
                  placeholder="e.g. Housing, Groceries"
                  value={draft.categoryName}
                  onChange={(e) => set('categoryName', e.target.value)}
                />
              </div>
            )}

            <div>
              <label className="fm-field-label" htmlFor="ent-date">
                {kind === 'income'
                  ? 'Next payment (optional)'
                  : kind === 'fixed'
                    ? 'Due date (optional)'
                    : 'Spent on'}
              </label>
              <input
                id="ent-date"
                className="fm-input"
                type="date"
                value={draft.date}
                onChange={(e) => set('date', e.target.value)}
              />
            </div>

            {error && <div className="fm-error">{error}</div>}

            <div className="fm-row" style={{ justifyContent: 'flex-end', marginTop: 4 }}>
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

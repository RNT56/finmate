// Cash Flow page (M2) — KPI cards (Monthly Income / Monthly Expenses / Net /
// Savings rate %), an income-vs-expenses bar, and an expense breakdown list.
// All figures come from the core/cashflow algorithms (docs/13 §6); one glass language.

import { useState } from 'react';
import { GlassCard } from '../../components/GlassCard';
import { ErrorCard } from '../../components/ErrorCard';
import { SkeletonList } from '../../components/Skeleton';
import { ChartDataTable } from '../../components/ChartDataTable';
import { Page } from '../../components/AppShell';
import { formatMoney } from '../../core/money';
import { describeIncomeExpenses } from '../../core/chartDescription';
import { useCashFlow } from './useCashFlow';
import { MoneyFlow } from './MoneyFlow';
import { EntityModal } from './EntityModal';
import { fixedMonthlyAmountMinor } from './types';
import type { FixedExpense, IncomeSource, VariableExpense } from './types';
import type { EntityKind } from './entityForm';

const EUR_LOCALE = 'de-DE';

type Entity = IncomeSource | FixedExpense | VariableExpense;
type ModalState = { kind: EntityKind; existing: Entity | null } | null;

export function CashFlow() {
  const {
    loading,
    error,
    reload,
    metrics,
    incomes,
    fixedExpenses,
    variableExpenses,
    fixedMinor,
    variableMinor,
    subscriptionsMinor,
    breakdown,
    expenseCategories,
    categoryName,
    displayCurrency,
    addIncome,
    removeIncome,
    addFixed,
    removeFixed,
    addVariable,
    removeVariable,
  } = useCashFlow();

  const [modal, setModal] = useState<ModalState>(null);

  const fmt = (minor: number) =>
    formatMoney(minor, displayCurrency, EUR_LOCALE);
  const savingsPct = (metrics.savingsRate * 100).toFixed(1);
  const netPositive = metrics.netMinor >= 0;

  const saveEntity = async (entity: Entity) => {
    if (!modal) return;
    if (modal.kind === 'income') await addIncome(entity as IncomeSource);
    else if (modal.kind === 'fixed') await addFixed(entity as FixedExpense);
    else await addVariable(entity as VariableExpense);
    setModal(null);
  };

  if (error) {
    return (
      <Page title="Cash Flow">
        <ErrorCard
          title="Couldn't load cash flow"
          message={error}
          onRetry={() => void reload()}
        />
      </Page>
    );
  }

  if (loading) {
    return (
      <Page title="Cash Flow">
        <SkeletonList count={4} />
      </Page>
    );
  }

  return (
    <Page title="Cash Flow">
      <div className="fm-stack">
        <GlassCard>
          <div
            className="fm-secondary"
            style={{ fontWeight: 600, fontSize: 14, marginBottom: 12 }}
          >
            Money flow
          </div>
          <MoneyFlow
            flow={{
              incomeMinor: metrics.incomeMinor,
              fixedMinor,
              variableMinor,
              subscriptionsMinor,
            }}
            currency={displayCurrency}
          />
        </GlassCard>

        <div
          style={{
            display: 'grid',
            gap: 'var(--fm-spacing)',
            gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
          }}
        >
          <Kpi
            label="Monthly income"
            value={loading ? '—' : fmt(metrics.incomeMinor)}
          />
          <Kpi
            label="Monthly expenses"
            value={loading ? '—' : fmt(metrics.expenseMinor)}
          />
          <Kpi
            label="Net"
            value={loading ? '—' : fmt(metrics.netMinor)}
            tone={netPositive ? 'positive' : 'negative'}
          />
          <Kpi
            label="Savings rate"
            value={loading ? '—' : `${savingsPct}%`}
            tone={netPositive ? 'positive' : 'negative'}
          />
        </div>

        <GlassCard>
          <div
            className="fm-secondary"
            style={{ fontWeight: 600, fontSize: 14, marginBottom: 12 }}
          >
            Income vs. expenses
          </div>
          <IncomeExpenseBar
            incomeMinor={metrics.incomeMinor}
            expenseMinor={metrics.expenseMinor}
            format={fmt}
          />
        </GlassCard>

        <GlassCard>
          <div
            className="fm-secondary"
            style={{ fontWeight: 600, fontSize: 14, marginBottom: 8 }}
          >
            Expense breakdown
          </div>
          <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
            {breakdown.map((row) => {
              const share =
                metrics.expenseMinor === 0
                  ? 0
                  : row.amountMinor / metrics.expenseMinor;
              return (
                <li
                  key={row.label}
                  style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    padding: '8px 0',
                    borderTop: '1px solid var(--fm-glass-border)',
                  }}
                >
                  <span>{row.label}</span>
                  <span
                    style={{ display: 'flex', gap: 12, alignItems: 'baseline' }}
                  >
                    <span className="fm-secondary" style={{ fontSize: 13 }}>
                      {(share * 100).toFixed(0)}%
                    </span>
                    <span className="fm-amount">{fmt(row.amountMinor)}</span>
                  </span>
                </li>
              );
            })}
            {breakdown.length === 0 && (
              <li className="fm-secondary" style={{ padding: '8px 0' }}>
                No expenses tracked yet.
              </li>
            )}
          </ul>
          <div
            className="fm-secondary"
            style={{ fontSize: 12, marginTop: 8 }}
            aria-hidden="true"
          >
            Fixed {fmt(fixedMinor)} · Subscriptions {fmt(subscriptionsMinor)} ·
            Variable {fmt(variableMinor)}
          </div>
        </GlassCard>

        <EntitySection
          title="Income sources"
          addLabel="+ Add income"
          onAdd={() => setModal({ kind: 'income', existing: null })}
          rows={incomes.map((i) => ({
            id: i.id,
            primary: i.name,
            secondary: i.frequency,
            amount: fmt(i.amountMinor),
            entity: i,
          }))}
          emptyLabel="No income sources yet."
          onEdit={(e) => setModal({ kind: 'income', existing: e })}
          onDelete={removeIncome}
        />

        <EntitySection
          title="Fixed expenses"
          addLabel="+ Add fixed"
          onAdd={() => setModal({ kind: 'fixed', existing: null })}
          rows={fixedExpenses.map((e) => ({
            id: e.id,
            primary: e.name,
            secondary: `${categoryName(e.categoryId)} · ${e.billingPeriod} · ${fmt(fixedMonthlyAmountMinor(e))}/mo`,
            amount: fmt(e.amountMinor),
            entity: e,
          }))}
          emptyLabel="No fixed expenses yet."
          onEdit={(e) => setModal({ kind: 'fixed', existing: e })}
          onDelete={removeFixed}
        />

        <EntitySection
          title="Variable expenses (this month)"
          addLabel="+ Add variable"
          onAdd={() => setModal({ kind: 'variable', existing: null })}
          rows={variableExpenses.map((e) => ({
            id: e.id,
            primary: e.name,
            secondary: `${categoryName(e.categoryId)} · ${e.spentOn}`,
            amount: fmt(e.amountMinor),
            entity: e,
          }))}
          emptyLabel="No variable expenses yet."
          onEdit={(e) => setModal({ kind: 'variable', existing: e })}
          onDelete={removeVariable}
        />
      </div>

      {modal && (
        <EntityModal
          kind={modal.kind}
          existing={modal.existing}
          categories={expenseCategories}
          onClose={() => setModal(null)}
          onSave={saveEntity}
        />
      )}
    </Page>
  );
}

interface SectionRow {
  id: string;
  primary: string;
  secondary: string;
  amount: string;
  entity: Entity;
}

function EntitySection({
  title,
  addLabel,
  onAdd,
  rows,
  emptyLabel,
  onEdit,
  onDelete,
}: {
  title: string;
  addLabel: string;
  onAdd: () => void;
  rows: SectionRow[];
  emptyLabel: string;
  onEdit: (entity: Entity) => void;
  onDelete: (id: string) => void | Promise<void>;
}) {
  return (
    <GlassCard>
      <div
        className="fm-row"
        style={{
          justifyContent: 'space-between',
          alignItems: 'center',
          marginBottom: 8,
        }}
      >
        <span
          className="fm-secondary"
          style={{ fontWeight: 600, fontSize: 14 }}
        >
          {title}
        </span>
        <button
          type="button"
          className="fm-btn"
          style={{ padding: '6px 12px', fontSize: 13 }}
          onClick={onAdd}
        >
          {addLabel}
        </button>
      </div>
      <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
        {rows.map((row) => (
          <li
            key={row.id}
            className="fm-row"
            style={{
              justifyContent: 'space-between',
              alignItems: 'center',
              gap: 12,
              padding: '10px 0',
              borderTop: '1px solid var(--fm-glass-border)',
            }}
          >
            <span style={{ flex: 1, minWidth: 0 }}>
              <span style={{ fontWeight: 600, display: 'block' }}>
                {row.primary}
              </span>
              <span className="fm-secondary" style={{ fontSize: 13 }}>
                {row.secondary}
              </span>
            </span>
            <span className="fm-amount">{row.amount}</span>
            <span className="fm-row" style={{ gap: 6 }}>
              <button
                type="button"
                className="fm-btn fm-btn-ghost"
                style={{ padding: '6px 10px', fontSize: 13 }}
                aria-label={`Edit ${row.primary}`}
                onClick={() => onEdit(row.entity)}
              >
                Edit
              </button>
              <button
                type="button"
                className="fm-btn fm-btn-ghost"
                style={{ padding: '6px 10px', fontSize: 13 }}
                aria-label={`Delete ${row.primary}`}
                onClick={() => void onDelete(row.id)}
              >
                Delete
              </button>
            </span>
          </li>
        ))}
        {rows.length === 0 && (
          <li className="fm-secondary" style={{ padding: '8px 0' }}>
            {emptyLabel}
          </li>
        )}
      </ul>
    </GlassCard>
  );
}

function Kpi({
  label,
  value,
  tone = 'neutral',
}: {
  label: string;
  value: string;
  tone?: 'neutral' | 'positive' | 'negative';
}) {
  const color =
    tone === 'positive'
      ? 'var(--fm-positive, #1f9d55)'
      : tone === 'negative'
        ? 'var(--fm-negative, #d23f3f)'
        : 'inherit';
  return (
    <GlassCard>
      <div className="fm-secondary" style={{ fontWeight: 600, fontSize: 14 }}>
        {label}
      </div>
      <div
        className="fm-amount"
        style={{ fontSize: 26, marginTop: 6, color }}
        aria-live="polite"
      >
        {value}
      </div>
    </GlassCard>
  );
}

/** Tiny inline-SVG paired bar: income (full reference) vs. expenses (scaled). */
function IncomeExpenseBar({
  incomeMinor,
  expenseMinor,
  format,
}: {
  incomeMinor: number;
  expenseMinor: number;
  format: (minor: number) => string;
}) {
  const max = Math.max(incomeMinor, expenseMinor, 1);
  const width = 600;
  const barH = 28;
  const gap = 16;
  const labelW = 90;
  const trackW = width - labelW - 110;
  const incomeW = (incomeMinor / max) * trackW;
  const expenseW = (expenseMinor / max) * trackW;
  const { summary, rows } = describeIncomeExpenses(
    incomeMinor,
    expenseMinor,
    format
  );

  return (
    <>
      <span className="fm-sr-only" role="img" aria-label={summary} />
      <ChartDataTable
        caption="Income versus expenses"
        labelHeader="Measure"
        valueHeader="Amount"
        rows={rows}
      />
      <svg
        viewBox={`0 0 ${width} ${barH * 2 + gap}`}
        width="100%"
        aria-hidden="true"
      >
        <text
          x={0}
          y={barH / 2 + 5}
          fontSize={14}
          fill="var(--fm-label-secondary)"
        >
          Income
        </text>
        <rect
          x={labelW}
          y={0}
          width={trackW}
          height={barH}
          rx={8}
          fill="var(--fm-glass-border)"
        />
        <rect
          x={labelW}
          y={0}
          width={incomeW}
          height={barH}
          rx={8}
          fill="var(--fm-positive, #1f9d55)"
        />
        <text
          x={labelW + trackW + 8}
          y={barH / 2 + 5}
          fontSize={13}
          fill="currentColor"
        >
          {format(incomeMinor)}
        </text>

        <text
          x={0}
          y={barH + gap + barH / 2 + 5}
          fontSize={14}
          fill="var(--fm-label-secondary)"
        >
          Expenses
        </text>
        <rect
          x={labelW}
          y={barH + gap}
          width={trackW}
          height={barH}
          rx={8}
          fill="var(--fm-glass-border)"
        />
        <rect
          x={labelW}
          y={barH + gap}
          width={expenseW}
          height={barH}
          rx={8}
          fill="var(--fm-negative, #d23f3f)"
        />
        <text
          x={labelW + trackW + 8}
          y={barH + gap + barH / 2 + 5}
          fontSize={13}
          fill="currentColor"
        >
          {format(expenseMinor)}
        </text>
      </svg>
    </>
  );
}

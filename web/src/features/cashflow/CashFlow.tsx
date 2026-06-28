// Cash Flow page (M2) — KPI cards (Monthly Income / Monthly Expenses / Net /
// Savings rate %), an income-vs-expenses bar, and an expense breakdown list.
// All figures come from the core/cashflow algorithms (docs/13 §6); one glass language.

import { GlassCard } from '../../components/GlassCard';
import { Page } from '../../components/AppShell';
import { formatMoney } from '../../core/money';
import { useCashFlow } from './useCashFlow';
import { MoneyFlow } from './MoneyFlow';

const EUR_LOCALE = 'de-DE';

export function CashFlow() {
  const {
    loading,
    metrics,
    fixedMinor,
    variableMinor,
    subscriptionsMinor,
    breakdown,
    displayCurrency,
  } = useCashFlow();

  const fmt = (minor: number) => formatMoney(minor, displayCurrency, EUR_LOCALE);
  const savingsPct = (metrics.savingsRate * 100).toFixed(1);
  const netPositive = metrics.netMinor >= 0;

  return (
    <Page title="Cash Flow">
      <div className="fm-stack">
        <GlassCard>
          <div className="fm-secondary" style={{ fontWeight: 600, fontSize: 14, marginBottom: 12 }}>
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
          <Kpi label="Monthly income" value={loading ? '—' : fmt(metrics.incomeMinor)} />
          <Kpi label="Monthly expenses" value={loading ? '—' : fmt(metrics.expenseMinor)} />
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
          <div className="fm-secondary" style={{ fontWeight: 600, fontSize: 14, marginBottom: 12 }}>
            Income vs. expenses
          </div>
          <IncomeExpenseBar
            incomeMinor={metrics.incomeMinor}
            expenseMinor={metrics.expenseMinor}
            format={fmt}
          />
        </GlassCard>

        <GlassCard>
          <div className="fm-secondary" style={{ fontWeight: 600, fontSize: 14, marginBottom: 8 }}>
            Expense breakdown
          </div>
          <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
            {breakdown.map((row) => {
              const share = metrics.expenseMinor === 0 ? 0 : row.amountMinor / metrics.expenseMinor;
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
                  <span style={{ display: 'flex', gap: 12, alignItems: 'baseline' }}>
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
            Fixed {fmt(fixedMinor)} · Subscriptions {fmt(subscriptionsMinor)} · Variable{' '}
            {fmt(variableMinor)}
          </div>
        </GlassCard>
      </div>
    </Page>
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
      <div className="fm-amount" style={{ fontSize: 26, marginTop: 6, color }} aria-live="polite">
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

  return (
    <svg
      viewBox={`0 0 ${width} ${barH * 2 + gap}`}
      width="100%"
      role="img"
      aria-label={`Income ${format(incomeMinor)}, expenses ${format(expenseMinor)}`}
    >
      <text x={0} y={barH / 2 + 5} fontSize={14} fill="var(--fm-label-secondary)">
        Income
      </text>
      <rect x={labelW} y={0} width={trackW} height={barH} rx={8} fill="var(--fm-glass-border)" />
      <rect x={labelW} y={0} width={incomeW} height={barH} rx={8} fill="var(--fm-positive, #1f9d55)" />
      <text x={labelW + trackW + 8} y={barH / 2 + 5} fontSize={13} fill="currentColor">
        {format(incomeMinor)}
      </text>

      <text x={0} y={barH + gap + barH / 2 + 5} fontSize={14} fill="var(--fm-label-secondary)">
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
  );
}

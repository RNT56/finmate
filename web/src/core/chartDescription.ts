// PURE chart/flow accessibility descriptions (docs/06 §a11y, M3-FLOW-04 + M7-A11Y-*).
//
// These helpers turn the already-computed figures into (a) a one-line spoken summary
// for a chart's `aria-label` and (b) an ordered set of {label, value} rows that the
// renderer exposes as an sr-only <table> fallback so a screen-reader user hears the
// same figures a sighted user sees. No DOM, no formatting policy beyond a caller-
// supplied `format(minor) → string` — so it is deterministic and unit-tested, and
// mirrors the iOS Domain description helpers (matching row order + phrasing).

import type { MoneyFlow } from './moneyflow';
import {
  BUCKET_LABELS,
  savingsMinor,
  totalExpensesMinor,
  type BucketKind,
} from './moneyflow';
import type { AssetSlice } from './assets';
import { assetTypeLabel } from './assets';

/** Format a minor-unit integer into a display string (currency-aware, caller-owned). */
export type MoneyFormatter = (minor: number) => string;

/** A single screen-reader table row: a category label and its formatted value. */
export interface ChartDataRow {
  label: string;
  value: string;
}

/** A chart's accessible description: a spoken summary + the tabular fallback rows. */
export interface ChartDescription {
  summary: string;
  rows: ChartDataRow[];
}

function pctOf(part: number, whole: number): number {
  return whole === 0 ? 0 : Math.round((part / whole) * 100);
}

// MARK: - Money-flow Sankey (M3)

/** Stable description order: income first, then the four buckets, then a totals tail. */
const FLOW_BUCKET_ORDER: readonly BucketKind[] = [
  'fixed',
  'variable',
  'subscriptions',
  'savings',
];

/**
 * Describe the bucketed money flow: "Income X splits into Fixed Y (n% of income), …".
 * Rows are "Income", each non-zero bucket ("Income → Fixed" style label) with value +
 * percent, then "Total expenses" and "Savings". Empty when there is nothing tracked.
 */
export function describeMoneyFlow(
  flow: MoneyFlow,
  format: MoneyFormatter
): ChartDescription {
  const income = flow.incomeMinor;
  const expenses = totalExpensesMinor(flow);
  const savings = savingsMinor(flow);

  if (income === 0 && expenses === 0) {
    return {
      summary: 'Money flow. No income or expenses tracked yet.',
      rows: [],
    };
  }

  const bucketValues: Record<BucketKind, number> = {
    fixed: flow.fixedMinor,
    variable: flow.variableMinor,
    subscriptions: flow.subscriptionsMinor,
    savings,
  };

  const active = FLOW_BUCKET_ORDER.filter((k) => bucketValues[k] > 0);

  const splitClause = active
    .map(
      (k) =>
        `${BUCKET_LABELS[k]} ${format(bucketValues[k])} (${pctOf(bucketValues[k], income)}% of income)`
    )
    .join(', ');

  const summary =
    `Money flow. Income ${format(income)} splits into ${splitClause}. ` +
    `Total expenses ${format(expenses)}, savings ${format(savings)}.`;

  const rows: ChartDataRow[] = [{ label: 'Income', value: format(income) }];
  for (const k of active) {
    rows.push({
      label: `Income → ${BUCKET_LABELS[k]}`,
      value: `${format(bucketValues[k])} (${pctOf(bucketValues[k], income)}%)`,
    });
  }
  rows.push({ label: 'Total expenses', value: format(expenses) });
  rows.push({ label: 'Savings', value: format(savings) });

  return { summary, rows };
}

// MARK: - Income vs. expenses bar (M2)

/** Describe the paired income/expenses bar + the net result. */
export function describeIncomeExpenses(
  incomeMinor: number,
  expenseMinor: number,
  format: MoneyFormatter
): ChartDescription {
  const net = incomeMinor - expenseMinor;
  const netWord = net >= 0 ? 'net positive' : 'net negative';
  const summary =
    `Income versus expenses. Income ${format(incomeMinor)}, ` +
    `expenses ${format(expenseMinor)}. Net ${format(net)}, ${netWord}.`;
  return {
    summary,
    rows: [
      { label: 'Income', value: format(incomeMinor) },
      { label: 'Expenses', value: format(expenseMinor) },
      { label: 'Net', value: format(net) },
    ],
  };
}

// MARK: - Assets allocation donut (M5)

/**
 * Describe the by-type allocation donut: each slice with its share and value, in the
 * caller's (descending-by-value) order. Empty when there are no slices.
 */
export function describeAllocation(
  slices: AssetSlice[],
  format: MoneyFormatter
): ChartDescription {
  if (slices.length === 0) {
    return {
      summary: 'Portfolio allocation by asset type. No assets yet.',
      rows: [],
    };
  }
  const clause = slices
    .map(
      (s) =>
        `${assetTypeLabel(s.type)} ${Math.round(s.share * 100)}% (${format(s.totalMinor)})`
    )
    .join(', ');
  return {
    summary: `Portfolio allocation by asset type. ${clause}.`,
    rows: slices.map((s) => ({
      label: assetTypeLabel(s.type),
      value: `${Math.round(s.share * 100)}% · ${format(s.totalMinor)}`,
    })),
  };
}

import { describe, it, expect } from 'vitest';
import {
  layout,
  makeMoneyFlow,
  ribbonPath,
  savingsMinor,
  totalExpensesMinor,
  BUCKET_ORDER,
  type MoneyFlow,
} from './moneyflow';
import { CurrencyConverter, type ExchangeRates } from './currency';
import type { FixedExpenseItem, IncomeItem, VariableExpenseItem } from './cashflow';

// Mirrors the Swift MoneyFlowLayoutTests vectors (docs/13 §6.5, docs/14 §11, ADR-0016).
// Canonical sample flow shared with the Cash Flow KPIs:
//   income 380000; fixed 119000; variable 40000; subscriptions 2648;
//   savings = 380000 − 161648 = 218352; total = 380000 (income == sum).
const sample: MoneyFlow = {
  incomeMinor: 380000,
  fixedMinor: 119000,
  variableMinor: 40000,
  subscriptionsMinor: 2648,
};

const SIZE = { width: 360, height: 260, padding: 16, nodeWidth: 14, nodeGap: 8 };

describe('MoneyFlow model', () => {
  it('totalExpenses + savings (savings absorbs the remainder)', () => {
    expect(totalExpensesMinor(sample)).toBe(161648);
    expect(savingsMinor(sample)).toBe(218352);
  });

  it('clamps savings at 0 when over budget', () => {
    const over: MoneyFlow = {
      incomeMinor: 100000,
      fixedMinor: 70000,
      variableMinor: 50000,
      subscriptionsMinor: 0,
    };
    expect(totalExpensesMinor(over)).toBe(120000);
    expect(savingsMinor(over)).toBe(0);
  });
});

describe('layout() — canonical flow', () => {
  const result = layout(sample, SIZE);
  const plotH = SIZE.height - SIZE.padding * 2; // 228
  const activeCount = 4; // Fixed, Variable, Subscriptions, Savings all > 0
  const gaps = (activeCount - 1) * SIZE.nodeGap; // 24
  const usableH = plotH - gaps; // 204

  it('total = max(income, Σbuckets) = 380000 (income == sum)', () => {
    expect(result.total).toBe(380000);
  });

  it('bucket nodes appear in the fixed order Fixed, Variable, Subscriptions, Savings', () => {
    const bucketIds = result.nodes.filter((n) => n.id !== 'income').map((n) => n.id);
    expect(bucketIds).toEqual([...BUCKET_ORDER]);
  });

  it('each bucket height fraction = value/total', () => {
    const byId = Object.fromEntries(result.nodes.map((n) => [n.id, n]));
    expect(byId.fixed.h / usableH).toBeCloseTo(119000 / 380000, 6); // ≈0.3132
    expect(byId.variable.h / usableH).toBeCloseTo(40000 / 380000, 6); // ≈0.1053
    expect(byId.subscriptions.h / usableH).toBeCloseTo(2648 / 380000, 6); // ≈0.0070
    expect(byId.savings.h / usableH).toBeCloseTo(218352 / 380000, 6); // ≈0.5746
  });

  it('every node height ≤ usableH', () => {
    for (const n of result.nodes.filter((x) => x.id !== 'income')) {
      expect(n.h).toBeLessThanOrEqual(usableH + 1e-9);
    }
  });

  it('sum of bucket heights + gaps ≤ usableH + gaps (fits the plot)', () => {
    const buckets = result.nodes.filter((n) => n.id !== 'income');
    const sumH = buckets.reduce((s, n) => s + n.h, 0);
    expect(sumH + gaps).toBeLessThanOrEqual(plotH + 1e-9);
  });

  it('income node height = income/total · usableH, vertically centered', () => {
    const income = result.nodes.find((n) => n.id === 'income')!;
    expect(income.h).toBeCloseTo((380000 / 380000) * usableH, 6);
    const center = income.y + income.h / 2;
    expect(center).toBeCloseTo(SIZE.padding + plotH / 2, 6);
  });

  it('income-side link bands partition the income node right edge in order', () => {
    const income = result.nodes.find((n) => n.id === 'income')!;
    // First band starts at the income node top.
    expect(result.links[0].incomeY0).toBeCloseTo(income.y, 6);
    // Bands are contiguous (each starts where the previous ended).
    for (let i = 1; i < result.links.length; i++) {
      expect(result.links[i].incomeY0).toBeCloseTo(result.links[i - 1].incomeY1, 6);
    }
    // Last band ends at the income node bottom.
    const last = result.links[result.links.length - 1];
    expect(last.incomeY1).toBeCloseTo(income.y + income.h, 6);
  });

  it('each ribbon thickness equals its bucket height at both ends', () => {
    const byId = Object.fromEntries(result.nodes.map((n) => [n.id, n]));
    for (const link of result.links) {
      const node = byId[link.id];
      expect(link.bucketY1 - link.bucketY0).toBeCloseTo(node.h, 6);
      expect(link.incomeY1 - link.incomeY0).toBeCloseTo(node.h, 6);
    }
  });

  it('ribbonPath emits a closed cubic-Bézier path', () => {
    const d = ribbonPath(result.links[0]);
    expect(d.startsWith('M ')).toBe(true);
    expect(d).toContain('C ');
    expect(d.trimEnd().endsWith('Z')).toBe(true);
  });
});

describe('layout() — over-budget case (no Savings node)', () => {
  const over: MoneyFlow = {
    incomeMinor: 100000,
    fixedMinor: 120000,
    variableMinor: 0,
    subscriptionsMinor: 0,
  };
  const result = layout(over, SIZE);

  it('total = max(income, Σbuckets) = 120000', () => {
    expect(result.total).toBe(120000);
  });

  it('has no Savings node', () => {
    expect(result.nodes.some((n) => n.id === 'savings')).toBe(false);
  });

  it('income node height = 100000/120000 · usableH (single active bucket, no gaps)', () => {
    const plotH = SIZE.height - SIZE.padding * 2; // 228
    const usableH = plotH; // one active bucket → 0 gaps
    const income = result.nodes.find((n) => n.id === 'income')!;
    expect(income.h).toBeCloseTo((100000 / 120000) * usableH, 6);
    expect(income.h).toBeLessThanOrEqual(usableH + 1e-9);
  });
});

describe('layout() — income with no expenses (all saved)', () => {
  const allSaved: MoneyFlow = {
    incomeMinor: 200000,
    fixedMinor: 0,
    variableMinor: 0,
    subscriptionsMinor: 0,
  };
  const result = layout(allSaved, SIZE);

  it('single Income → Savings ribbon', () => {
    const buckets = result.nodes.filter((n) => n.id !== 'income');
    expect(buckets).toHaveLength(1);
    expect(buckets[0].id).toBe('savings');
    expect(result.links).toHaveLength(1);
    expect(result.links[0].id).toBe('savings');
  });
});

// MARK: makeMoneyFlow — mixed-currency, converted to a display currency (docs/13 §6.5/§7).
// Mirrors Swift CashFlowTests.mixedCurrencyMoneyFlowBucketsConvert with the SAME vectors.
// Sample rates: eurUsd 1.10 (USD per EUR), btcEur 50_000, btcUsd 55_000.
describe('makeMoneyFlow (converter-aware)', () => {
  const SAMPLE_RATES: ExchangeRates = {
    eurUsd: 1.1,
    btcEur: 50_000,
    btcUsd: 55_000,
    fetchedAt: 0,
  };
  const converter = new CurrencyConverter(SAMPLE_RATES);

  it('converts each income/fixed/variable bucket before summing', () => {
    const income: IncomeItem[] = [
      { amountMinor: 300_000, currency: 'EUR', frequency: 'monthly' },
      { amountMinor: 110_000, currency: 'USD', frequency: 'monthly' },
    ];
    const fixed: FixedExpenseItem[] = [
      { amountMinor: 110_000, currency: 'EUR', billingPeriod: 'monthly' },
    ];
    const variable: VariableExpenseItem[] = [{ amountMinor: 11_000, currency: 'USD' }];
    const flow = makeMoneyFlow(income, fixed, variable, 5_000, 'EUR', converter);
    expect(flow.incomeMinor).toBe(400_000); // €4000
    expect(flow.fixedMinor).toBe(110_000); // €1100
    expect(flow.variableMinor).toBe(10_000); // $110 → €100
    expect(flow.subscriptionsMinor).toBe(5_000);
    // savings = 400000 − (110000 + 10000 + 5000) = 275000.
    expect(savingsMinor(flow)).toBe(275_000);
  });
});

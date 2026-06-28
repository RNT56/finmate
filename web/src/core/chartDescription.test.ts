import { describe, expect, it } from 'vitest';
import {
  describeAllocation,
  describeIncomeExpenses,
  describeMoneyFlow,
} from './chartDescription';
import type { MoneyFlow } from './moneyflow';
import type { AssetSlice } from './assets';

// A trivial euro-cents formatter so the assertions are exact and locale-free.
const fmt = (minor: number) => {
  const sign = minor < 0 ? '-' : '';
  const abs = Math.abs(minor);
  return `${sign}€${(abs / 100).toFixed(2)}`;
};

describe('describeMoneyFlow', () => {
  const flow: MoneyFlow = {
    incomeMinor: 400_000, // €4,000
    fixedMinor: 120_000, // €1,200 (30%)
    variableMinor: 80_000, // €800 (20%)
    subscriptionsMinor: 40_000, // €400 (10%)
  };
  // savings = 4000 - (1200+800+400) = €1,600 (40%)

  it('summarizes income splitting into each non-zero bucket with percentages', () => {
    const { summary } = describeMoneyFlow(flow, fmt);
    expect(summary).toBe(
      'Money flow. Income €4000.00 splits into Fixed €1200.00 (30% of income), ' +
        'Variable €800.00 (20% of income), Subscriptions €400.00 (10% of income), ' +
        'Savings €1600.00 (40% of income). Total expenses €2400.00, savings €1600.00.'
    );
  });

  it('emits ordered table rows: income, each bucket, totals tail', () => {
    const { rows } = describeMoneyFlow(flow, fmt);
    expect(rows).toEqual([
      { label: 'Income', value: '€4000.00' },
      { label: 'Income → Fixed', value: '€1200.00 (30%)' },
      { label: 'Income → Variable', value: '€800.00 (20%)' },
      { label: 'Income → Subscriptions', value: '€400.00 (10%)' },
      { label: 'Income → Savings', value: '€1600.00 (40%)' },
      { label: 'Total expenses', value: '€2400.00' },
      { label: 'Savings', value: '€1600.00' },
    ]);
  });

  it('omits zero buckets from the split clause and rows', () => {
    const { summary, rows } = describeMoneyFlow(
      {
        incomeMinor: 200_000,
        fixedMinor: 50_000,
        variableMinor: 0,
        subscriptionsMinor: 0,
      },
      fmt
    );
    expect(summary).not.toContain('Variable');
    expect(summary).not.toContain('Subscriptions');
    expect(rows.some((r) => r.label.includes('Variable'))).toBe(false);
    // Fixed + Savings remain.
    expect(rows.map((r) => r.label)).toContain('Income → Fixed');
    expect(rows.map((r) => r.label)).toContain('Income → Savings');
  });

  it('reports the empty state when nothing is tracked', () => {
    const { summary, rows } = describeMoneyFlow(
      {
        incomeMinor: 0,
        fixedMinor: 0,
        variableMinor: 0,
        subscriptionsMinor: 0,
      },
      fmt
    );
    expect(summary).toBe('Money flow. No income or expenses tracked yet.');
    expect(rows).toEqual([]);
  });

  it('clamps over-budget months to zero savings', () => {
    const { rows } = describeMoneyFlow(
      {
        incomeMinor: 100_000,
        fixedMinor: 90_000,
        variableMinor: 30_000,
        subscriptionsMinor: 0,
      },
      fmt
    );
    const savings = rows.find((r) => r.label === 'Savings');
    expect(savings?.value).toBe('€0.00');
  });
});

describe('describeIncomeExpenses', () => {
  it('summarizes income, expenses, and a positive net', () => {
    const { summary, rows } = describeIncomeExpenses(400_000, 240_000, fmt);
    expect(summary).toBe(
      'Income versus expenses. Income €4000.00, expenses €2400.00. Net €1600.00, net positive.'
    );
    expect(rows).toEqual([
      { label: 'Income', value: '€4000.00' },
      { label: 'Expenses', value: '€2400.00' },
      { label: 'Net', value: '€1600.00' },
    ]);
  });

  it('marks an over-spend as net negative with a signed net', () => {
    const { summary, rows } = describeIncomeExpenses(100_000, 150_000, fmt);
    expect(summary).toContain('net negative');
    expect(rows[2]).toEqual({ label: 'Net', value: '-€500.00' });
  });
});

describe('describeAllocation', () => {
  const slices: AssetSlice[] = [
    { type: 'crypto', totalMinor: 600_000, count: 1, share: 0.6 },
    { type: 'stock', totalMinor: 400_000, count: 2, share: 0.4 },
  ];

  it('summarizes each slice with share and value in order', () => {
    const { summary, rows } = describeAllocation(slices, fmt);
    expect(summary).toBe(
      'Portfolio allocation by asset type. Crypto 60% (€6000.00), Stock 40% (€4000.00).'
    );
    expect(rows).toEqual([
      { label: 'Crypto', value: '60% · €6000.00' },
      { label: 'Stock', value: '40% · €4000.00' },
    ]);
  });

  it('reports the empty state with no slices', () => {
    const { summary, rows } = describeAllocation([], fmt);
    expect(summary).toBe('Portfolio allocation by asset type. No assets yet.');
    expect(rows).toEqual([]);
  });
});

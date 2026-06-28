import { describe, it, expect } from 'vitest';
import {
  monthlyFactor,
  monthlyIncomeMinor,
  monthlyExpensesMinor,
  cashFlowMetrics,
} from './cashflow';

// Mirrors the Swift CashFlowTests / AnalyticsTests vectors (docs/13 §6).

describe('monthlyFactor', () => {
  it('weekly is 52/12, monthly 1, yearly 1/12, one_time 0', () => {
    expect(monthlyFactor('weekly')).toBeCloseTo(52 / 12, 10);
    expect(monthlyFactor('monthly')).toBe(1);
    expect(monthlyFactor('yearly')).toBeCloseTo(1 / 12, 10);
    expect(monthlyFactor('one_time')).toBe(0);
  });
});

describe('monthlyIncomeMinor', () => {
  it('Salary 320000 + Freelance 60000 (both monthly) -> 380000', () => {
    expect(
      monthlyIncomeMinor([
        { amountMinor: 320000, frequency: 'monthly' },
        { amountMinor: 60000, frequency: 'monthly' },
      ]),
    ).toBe(380000);
  });

  it('excludes one_time income from the recurring roll-up', () => {
    expect(
      monthlyIncomeMinor([
        { amountMinor: 320000, frequency: 'monthly' },
        { amountMinor: 500000, frequency: 'one_time' },
      ]),
    ).toBe(320000);
  });

  it('normalizes weekly ×52/12 and yearly /12 HALF-UP', () => {
    // weekly 10000 -> 10000*52/12 = 43333.33 -> 43333; yearly 120000 -> 10000
    expect(monthlyIncomeMinor([{ amountMinor: 10000, frequency: 'weekly' }])).toBe(43333);
    expect(monthlyIncomeMinor([{ amountMinor: 120000, frequency: 'yearly' }])).toBe(10000);
  });

  it('empty list -> 0 (no NaN)', () => {
    expect(monthlyIncomeMinor([])).toBe(0);
  });
});

describe('monthlyExpensesMinor', () => {
  it('sums fixed + variable + subscriptions roll-up', () => {
    // fixed 119000 + subs 2648 + variable 40000 = 161648
    expect(monthlyExpensesMinor(119000, 40000, 2648)).toBe(161648);
  });
});

describe('cashFlowMetrics', () => {
  it('savings rate vector (income 224000, expense 100000) -> net 124000, ~0.5536', () => {
    const m = cashFlowMetrics(224000, 100000);
    expect(m.netMinor).toBe(124000);
    expect(Math.abs(m.savingsRate - 0.5536)).toBeLessThan(0.001);
  });

  it('zero income -> savings rate 0 (zero-guarded)', () => {
    expect(cashFlowMetrics(0, 500).savingsRate).toBe(0);
  });

  it('sample data: income 380000, expenses 161648 -> net 218352, rate ~0.5746', () => {
    const m = cashFlowMetrics(380000, 161648);
    expect(m.incomeMinor).toBe(380000);
    expect(m.expenseMinor).toBe(161648);
    expect(m.netMinor).toBe(218352);
    expect(Math.abs(m.savingsRate - 218352 / 380000)).toBeLessThan(1e-9);
  });

  it('over-budget month yields a negative net and negative savings rate', () => {
    const m = cashFlowMetrics(100000, 130000);
    expect(m.netMinor).toBe(-30000);
    expect(m.savingsRate).toBeLessThan(0);
  });
});

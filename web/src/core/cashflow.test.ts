import { describe, it, expect } from 'vitest';
import {
  monthlyFactor,
  monthlyIncomeMinor,
  monthlyExpensesMinor,
  cashFlowMetrics,
  monthlyIncomeMinorIn,
  fixedMonthlyMinorIn,
  variableThisMonthMinorIn,
  subscriptionsMonthlyMinorIn,
  cashFlowMetricsIn,
  type FixedExpenseItem,
  type IncomeItem,
  type SubscriptionItem,
  type VariableExpenseItem,
} from './cashflow';
import { CurrencyConverter, type ExchangeRates } from './currency';

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

// MARK: Mixed-currency, converted to a display currency (docs/13 §6/§7)
// Mirrors Swift CashFlowTests "Mixed-currency" cases with the SAME vectors.
// Sample rates: eurUsd 1.10 (USD per EUR), btcEur 50_000, btcUsd 55_000.

const SAMPLE_RATES: ExchangeRates = {
  eurUsd: 1.1,
  btcEur: 50_000,
  btcUsd: 55_000,
  fetchedAt: 0,
};
const sampleConverter = new CurrencyConverter(SAMPLE_RATES);

describe('monthlyIncomeMinorIn (converter-aware)', () => {
  it('converts each income per item before summing (€3000 + $1100→€1000 = €4000)', () => {
    const income: IncomeItem[] = [
      { amountMinor: 300_000, currency: 'EUR', frequency: 'monthly' },
      { amountMinor: 110_000, currency: 'USD', frequency: 'monthly' },
    ];
    expect(monthlyIncomeMinorIn(income, 'EUR', sampleConverter)).toBe(400_000);
    // Same inputs displayed in USD: €3000→$3300 + $1100 = $4400.
    expect(monthlyIncomeMinorIn(income, 'USD', sampleConverter)).toBe(440_000);
    // Stored amounts/currencies are untouched (display-only conversion).
    expect(income[0]).toEqual({ amountMinor: 300_000, currency: 'EUR', frequency: 'monthly' });
    expect(income[1]).toEqual({ amountMinor: 110_000, currency: 'USD', frequency: 'monthly' });
  });

  it('matches the plain overload when every item is already in the display currency', () => {
    const income: IncomeItem[] = [
      { amountMinor: 320_000, currency: 'EUR', frequency: 'monthly' },
      { amountMinor: 60_000, currency: 'EUR', frequency: 'monthly' },
    ];
    expect(monthlyIncomeMinorIn(income, 'EUR', sampleConverter)).toBe(
      monthlyIncomeMinor(income.map((i) => ({ amountMinor: i.amountMinor, frequency: i.frequency }))),
    );
  });

  it('excludes one_time income and empty list -> 0', () => {
    expect(
      monthlyIncomeMinorIn(
        [
          { amountMinor: 300_000, currency: 'EUR', frequency: 'monthly' },
          { amountMinor: 500_000, currency: 'USD', frequency: 'one_time' },
        ],
        'EUR',
        sampleConverter,
      ),
    ).toBe(300_000);
    expect(monthlyIncomeMinorIn([], 'EUR', sampleConverter)).toBe(0);
  });
});

describe('fixedMonthlyMinorIn / variableThisMonthMinorIn (converter-aware)', () => {
  it('converts fixed monthly-equivalents per item (€1100 + $220→€200 = €1300)', () => {
    const fixed: FixedExpenseItem[] = [
      { amountMinor: 110_000, currency: 'EUR', billingPeriod: 'monthly' },
      { amountMinor: 22_000, currency: 'USD', billingPeriod: 'monthly' },
    ];
    expect(fixedMonthlyMinorIn(fixed, 'EUR', sampleConverter)).toBe(130_000);
  });

  it('converts this-month variable per item ($110 → €100)', () => {
    const variable: VariableExpenseItem[] = [{ amountMinor: 11_000, currency: 'USD' }];
    expect(variableThisMonthMinorIn(variable, 'EUR', sampleConverter)).toBe(10_000);
  });
});

describe('subscriptionsMonthlyMinorIn (converter-aware)', () => {
  it('converts each subscription per item (€12.99 + $11→€10 = €22.99)', () => {
    const subs: SubscriptionItem[] = [
      { monthlyMinor: 1_299, currency: 'EUR' },
      { monthlyMinor: 1_100, currency: 'USD' },
    ];
    expect(subscriptionsMonthlyMinorIn(subs, 'EUR', sampleConverter)).toBe(2_299);
  });
});

describe('cashFlowMetricsIn (converter-aware)', () => {
  it('converts every income & expense before summing (income €4000, expenses €1450)', () => {
    const income: IncomeItem[] = [
      { amountMinor: 300_000, currency: 'EUR', frequency: 'monthly' },
      { amountMinor: 110_000, currency: 'USD', frequency: 'monthly' },
    ];
    const fixed: FixedExpenseItem[] = [
      { amountMinor: 110_000, currency: 'EUR', billingPeriod: 'monthly' },
      { amountMinor: 22_000, currency: 'USD', billingPeriod: 'monthly' },
    ];
    const variable: VariableExpenseItem[] = [{ amountMinor: 11_000, currency: 'USD' }];
    // Subscriptions already in display currency (e.g. €50).
    const m = cashFlowMetricsIn(income, fixed, variable, 5_000, 'EUR', sampleConverter);
    expect(m.incomeMinor).toBe(400_000); // €4000
    // expenses = €1300 fixed + €100 variable + €50 subs = €1450.
    expect(m.expenseMinor).toBe(145_000);
    expect(m.netMinor).toBe(255_000);
  });
});

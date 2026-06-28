// TS mirror of Domain/Calculations.swift CashFlowMetrics + IncomeFrequency (docs/13 §6).
// net = income − expenses; savings rate = net / income (0 when income is 0).
// Income frequency normalization: weekly ×52/12, monthly ×1, yearly /12,
// one_time excluded from the recurring monthly roll-up. Integer minor units; HALF-UP.

import { roundHalfUp } from './currency';
import type { IncomeFrequency } from './normalization';
import { incomeMonthlyMinorUnits } from './normalization';

export type { IncomeFrequency } from './normalization';

/**
 * Monthly-equivalent factor for an income frequency, as a fraction.
 * one_time contributes 0 to a recurring monthly roll-up (docs/13 §6.1).
 * Mirrors IncomeFrequency.monthlyFactor in the Swift Domain.
 */
export function monthlyFactor(frequency: IncomeFrequency): number {
  switch (frequency) {
    case 'weekly':
      return 52 / 12;
    case 'monthly':
      return 1;
    case 'yearly':
      return 1 / 12;
    case 'one_time':
      return 0;
  }
}

/** A recurring income source contribution (currency-agnostic minor units). */
export interface IncomeContribution {
  amountMinor: number;
  frequency: IncomeFrequency;
}

/**
 * Total monthly-equivalent income in minor units (docs/13 §6.1).
 * Each source is normalized HALF-UP per docs/13 §3 then summed; one_time excluded.
 */
export function monthlyIncomeMinor(incomes: IncomeContribution[]): number {
  let total = 0;
  for (const income of incomes) {
    total += incomeMonthlyMinorUnits(income.amountMinor, income.frequency);
  }
  return total;
}

/**
 * Total monthly expenses in minor units: fixed (monthly-equivalent already) +
 * variable (current-month actuals) + the subscriptions monthly roll-up (docs/13 §6.2).
 */
export function monthlyExpensesMinor(
  fixedMinor: number,
  variableMinor: number,
  subscriptionsMonthlyMinor: number,
): number {
  return fixedMinor + variableMinor + subscriptionsMonthlyMinor;
}

export interface CashFlowMetrics {
  incomeMinor: number;
  expenseMinor: number;
  netMinor: number;
  /** net / income, in (−∞, 1]. Zero income ⇒ 0 (zero-guarded). */
  savingsRate: number;
}

/** Cash-flow metric set (docs/13 §6). Mirrors Swift CashFlowMetrics. */
export function cashFlowMetrics(incomeMinor: number, expenseMinor: number): CashFlowMetrics {
  const netMinor = incomeMinor - expenseMinor;
  return {
    incomeMinor,
    expenseMinor,
    netMinor,
    savingsRate: incomeMinor === 0 ? 0 : netMinor / incomeMinor,
  };
}

// roundHalfUp re-exported for callers building monthly factors inline.
export { roundHalfUp };

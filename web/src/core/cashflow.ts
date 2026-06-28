// TS mirror of Domain/Calculations.swift CashFlowMetrics + IncomeFrequency (docs/13 §6).
// net = income − expenses; savings rate = net / income (0 when income is 0).
// Income frequency normalization: weekly ×52/12, monthly ×1, yearly /12,
// one_time excluded from the recurring monthly roll-up. Integer minor units; HALF-UP.

import type { CurrencyCode, CurrencyConverter } from './currency';
import { roundHalfUp } from './currency';
import type { BillingPeriod, IncomeFrequency } from './normalization';
import { incomeMonthlyMinorUnits, monthlyMinorUnits } from './normalization';

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

// MARK: - Converter-aware, display-currency aggregation (docs/13 §6/§7)
//
// TS mirror of the Swift `CashFlow` / `MoneyFlow.make` converter overloads. Each
// item's monthly-equivalent `Money` is converted to the display currency at READ
// time, HALF-UP, BEFORE summing — so the KPIs/money-flow are expressed in the
// display currency AND mixed-currency inputs sum correctly (the plain overloads
// latently mis-sum those). Stored amounts/currencies are NEVER mutated (the
// Substimate bug). Unconvertible items (rate unavailable, differing currency) are
// skipped rather than corrupting the total — mirrors the assets/subscriptions
// `convertOrSame` convention.

/** Convert `minorUnits` of `from` into `to`, contributing 0 when the rate is
 *  unavailable and the currencies differ (never silently guess). */
function convertOrZero(
  minorUnits: number,
  from: CurrencyCode,
  to: CurrencyCode,
  converter: CurrencyConverter,
): number {
  const converted = converter.convert(minorUnits, from, to);
  if (converted.ok) return converted.minorUnits;
  return from === to ? minorUnits : 0;
}

/** A recurring income source carrying its own stored currency. */
export interface IncomeItem {
  amountMinor: number;
  currency: CurrencyCode;
  frequency: IncomeFrequency;
}

/** A fixed expense carrying its own stored currency + billing period. */
export interface FixedExpenseItem {
  amountMinor: number;
  currency: CurrencyCode;
  billingPeriod: BillingPeriod;
}

/** A this-month variable expense carrying its own stored currency. */
export interface VariableExpenseItem {
  amountMinor: number;
  currency: CurrencyCode;
}

/** A subscription's monthly-equivalent amount carrying its own stored currency. */
export interface SubscriptionItem {
  monthlyMinor: number;
  currency: CurrencyCode;
}

/**
 * Σ convert(income.monthly-equivalent → displayCurrency), in minor units
 * (docs/13 §6.1/§7). `one_time` excluded; each source normalized then converted
 * before summing (HALF-UP, display-only). Mirrors Swift
 * `CashFlow.monthlyIncomeMinor(_:displayCurrency:converter:)`.
 */
export function monthlyIncomeMinorIn(
  incomes: IncomeItem[],
  displayCurrency: CurrencyCode,
  converter: CurrencyConverter,
): number {
  let total = 0;
  for (const income of incomes) {
    const monthly = incomeMonthlyMinorUnits(income.amountMinor, income.frequency);
    total += convertOrZero(monthly, income.currency, displayCurrency, converter);
  }
  return total;
}

/**
 * Σ convert(fixed.monthly-equivalent → displayCurrency), in minor units
 * (docs/13 §6.2/§7). Mirrors Swift `CashFlow.fixedMonthlyMinor(_:displayCurrency:converter:)`.
 */
export function fixedMonthlyMinorIn(
  fixed: FixedExpenseItem[],
  displayCurrency: CurrencyCode,
  converter: CurrencyConverter,
): number {
  let total = 0;
  for (const exp of fixed) {
    const monthly = monthlyMinorUnits(exp.amountMinor, exp.billingPeriod);
    total += convertOrZero(monthly, exp.currency, displayCurrency, converter);
  }
  return total;
}

/**
 * Σ convert(variable → displayCurrency), in minor units (docs/13 §6.2/§7). The
 * caller pre-filters to the current month. Mirrors Swift
 * `CashFlow.variableThisMonthMinor(_:displayCurrency:converter:)`.
 */
export function variableThisMonthMinorIn(
  variable: VariableExpenseItem[],
  displayCurrency: CurrencyCode,
  converter: CurrencyConverter,
): number {
  let total = 0;
  for (const exp of variable) {
    total += convertOrZero(exp.amountMinor, exp.currency, displayCurrency, converter);
  }
  return total;
}

/**
 * Σ convert(subscription.monthly-equivalent → displayCurrency), in minor units
 * (docs/13 §3/§7). Each subscription's monthly amount is converted per item before
 * summing. Mirrors Swift `CashFlow.subscriptionsMonthlyMinor(_:displayCurrency:converter:)`.
 */
export function subscriptionsMonthlyMinorIn(
  subscriptions: SubscriptionItem[],
  displayCurrency: CurrencyCode,
  converter: CurrencyConverter,
): number {
  let total = 0;
  for (const sub of subscriptions) {
    total += convertOrZero(sub.monthlyMinor, sub.currency, displayCurrency, converter);
  }
  return total;
}

/**
 * Build `CashFlowMetrics` with every income & expense converted to `displayCurrency`
 * at read time before summing (docs/13 §6/§7). `subscriptionsMonthlyMinor` is expected
 * already in the display currency (compute via `subscriptionsMonthlyMinorIn`). Stored
 * amounts are never mutated. Mirrors Swift `CashFlow.metrics(…displayCurrency:converter:)`.
 */
export function cashFlowMetricsIn(
  income: IncomeItem[],
  fixed: FixedExpenseItem[],
  variable: VariableExpenseItem[],
  subscriptionsMonthlyMinor: number,
  displayCurrency: CurrencyCode,
  converter: CurrencyConverter,
): CashFlowMetrics {
  const incomeMinor = monthlyIncomeMinorIn(income, displayCurrency, converter);
  const fixedMonthly = fixedMonthlyMinorIn(fixed, displayCurrency, converter);
  const variableMonth = variableThisMonthMinorIn(variable, displayCurrency, converter);
  const expenseMinor = fixedMonthly + variableMonth + subscriptionsMonthlyMinor;
  return cashFlowMetrics(incomeMinor, expenseMinor);
}

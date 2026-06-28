// TS mirror of Domain/Calculations.swift BillingPeriodMath + IncomeFrequency (docs/13 §3, §6).
// Period -> canonical monthly/annual minor units. HALF-UP rounding.

import { roundHalfUp } from './currency';

export type BillingPeriod = 'weekly' | 'monthly' | 'quarterly' | 'yearly';
export type IncomeFrequency = 'weekly' | 'monthly' | 'yearly' | 'one_time';

/**
 * Canonical MONTHLY minor units for a charge billed on `period`.
 * weekly ×52/12, monthly ×1, quarterly /3, yearly /12 — HALF-UP.
 */
export function monthlyMinorUnits(amountMinor: number, period: BillingPeriod): number {
  let monthly: number;
  switch (period) {
    case 'weekly':
      monthly = (amountMinor * 52) / 12;
      break;
    case 'monthly':
      monthly = amountMinor;
      break;
    case 'quarterly':
      monthly = amountMinor / 3;
      break;
    case 'yearly':
      monthly = amountMinor / 12;
      break;
  }
  return roundHalfUp(monthly);
}

/**
 * Canonical ANNUAL minor units. Quarterly uses ×4 directly (not monthly×12) to
 * avoid compounding the rounding error (docs/13 §3 assumption).
 */
export function annualMinorUnits(amountMinor: number, period: BillingPeriod): number {
  let annual: number;
  switch (period) {
    case 'weekly':
      annual = amountMinor * 52;
      break;
    case 'monthly':
      annual = amountMinor * 12;
      break;
    case 'quarterly':
      annual = amountMinor * 4;
      break;
    case 'yearly':
      annual = amountMinor;
      break;
  }
  return roundHalfUp(annual);
}

/**
 * Monthly-equivalent minor units for a recurring income source.
 * one_time contributes 0 to a recurring monthly roll-up (docs/13 §6.1).
 */
export function incomeMonthlyMinorUnits(amountMinor: number, frequency: IncomeFrequency): number {
  switch (frequency) {
    case 'weekly':
      return roundHalfUp((amountMinor * 52) / 12);
    case 'monthly':
      return amountMinor;
    case 'yearly':
      return roundHalfUp(amountMinor / 12);
    case 'one_time':
      return 0;
  }
}

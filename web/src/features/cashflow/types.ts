// Domain mirror of income & expense entities (camelCase) + repository protocol.
// Mirrors Domain/Entities.swift (IncomeSource / FixedExpense / VariableExpense) and
// the docs/05 income_sources / fixed_expenses / variable_expenses schema.

import type { CurrencyCode } from '../../core/currency';
import type { BillingPeriod, IncomeFrequency } from '../../core/normalization';
import { monthlyMinorUnits } from '../../core/normalization';

export interface IncomeSource {
  id: string;
  name: string;
  amountMinor: number;
  currency: CurrencyCode;
  frequency: IncomeFrequency;
  /** ISO date of the next scheduled payment (payday anchor, docs/13 §11.2); null = unscheduled. */
  nextPayment: string | null;
}

export interface FixedExpense {
  id: string;
  name: string;
  amountMinor: number;
  currency: CurrencyCode;
  billingPeriod: BillingPeriod;
  categoryName: string;
  /** ISO date the expense is due (recurrence anchor, docs/13 §11); null = no schedule. */
  dueDate: string | null;
}

export interface VariableExpense {
  id: string;
  name: string;
  amountMinor: number;
  currency: CurrencyCode;
  categoryName: string;
  /** ISO date the spend occurred (current-month actuals roll into expenses). */
  spentOn: string;
}

/** Canonical monthly-equivalent minor units for a fixed expense, own currency. */
export function fixedMonthlyAmountMinor(expense: FixedExpense): number {
  return monthlyMinorUnits(expense.amountMinor, expense.billingPeriod);
}

/** Repository protocol — the store calls this, never the SDK directly (docs/03). */
export interface CashFlowRepository {
  incomes(): Promise<IncomeSource[]>;
  fixedExpenses(): Promise<FixedExpense[]>;
  variableExpenses(): Promise<VariableExpense[]>;
}

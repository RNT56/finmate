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
  /** Normalized FK to `categories(id)` (docs/05 §3.5, ADR-0022); null = uncategorized.
   *  The display name is resolved client-side from the categories list, mirroring
   *  `Subscription` / iOS `FixedExpense.categoryID`. */
  categoryId: string | null;
  /** ISO date the expense is due (recurrence anchor, docs/13 §11); null = no schedule. */
  dueDate: string | null;
}

export interface VariableExpense {
  id: string;
  name: string;
  amountMinor: number;
  currency: CurrencyCode;
  /** Normalized FK to `categories(id)` (docs/05 §3.6, ADR-0022); null = uncategorized. */
  categoryId: string | null;
  /** ISO date the spend occurred (current-month actuals roll into expenses). */
  spentOn: string;
}

/** An expense category (docs/05 §categories; ADR-0022). Mirrors Domain `Category`
 *  (kind = expense). Names are resolved from these rows for display. */
export interface ExpenseCategory {
  id: string;
  name: string;
  slug: string;
}

/** Canonical monthly-equivalent minor units for a fixed expense, own currency. */
export function fixedMonthlyAmountMinor(expense: FixedExpense): number {
  return monthlyMinorUnits(expense.amountMinor, expense.billingPeriod);
}

/** Resolve a category id to its display name, falling back to "Uncategorized"
 *  (ADR-0022). Label-agnostic breakdown math stays unchanged; only display resolves. */
export function categoryNameFor(
  id: string | null,
  categories: ExpenseCategory[],
): string {
  if (id === null) return 'Uncategorized';
  return categories.find((c) => c.id === id)?.name ?? 'Uncategorized';
}

/** Repository protocol — the store calls this, never the SDK directly (docs/03). */
export interface CashFlowRepository {
  incomes(): Promise<IncomeSource[]>;
  fixedExpenses(): Promise<FixedExpense[]>;
  variableExpenses(): Promise<VariableExpense[]>;
  /** Expense-kind categories, for resolving `categoryId → name` and the form select. */
  expenseCategories(): Promise<ExpenseCategory[]>;

  upsertIncome(income: IncomeSource): Promise<void>;
  deleteIncome(id: string): Promise<void>;

  upsertFixed(expense: FixedExpense): Promise<void>;
  deleteFixed(id: string): Promise<void>;

  upsertVariable(expense: VariableExpense): Promise<void>;
  deleteVariable(id: string): Promise<void>;
}

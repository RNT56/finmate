// SupabaseCashFlowRepository — live implementation of the `CashFlowRepository`
// protocol over the RLS-protected `income_sources`, `fixed_expenses` and
// `variable_expenses` tables (docs/03 §3; docs/05 §income_and_expenses). RLS scopes
// every row to auth.uid() (docs/07 §3); money stays integer minor units; snake_case
// columns <-> camelCase Domain are translated by the mappers below.

import type { SupabaseClient } from '@supabase/supabase-js';
import type {
  CategoryRow,
  Database,
  FixedExpenseRow,
  IncomeSourceRow,
  VariableExpenseRow,
} from '../../types/database';
import type {
  CashFlowRepository,
  ExpenseCategory,
  FixedExpense,
  IncomeSource,
  VariableExpense,
} from './types';

export function incomeFromRow(row: IncomeSourceRow): IncomeSource {
  return {
    id: row.id,
    name: row.name,
    amountMinor: row.amount_minor,
    currency: row.currency,
    frequency: row.frequency,
    nextPayment: row.next_payment,
  };
}

export function fixedExpenseFromRow(row: FixedExpenseRow): FixedExpense {
  return {
    id: row.id,
    name: row.name,
    amountMinor: row.amount_minor,
    currency: row.currency,
    billingPeriod: row.billing_period,
    categoryId: row.category_id,
    dueDate: row.due_date,
  };
}

export function variableExpenseFromRow(row: VariableExpenseRow): VariableExpense {
  return {
    id: row.id,
    name: row.name,
    amountMinor: row.amount_minor,
    currency: row.currency,
    categoryId: row.category_id,
    spentOn: row.spent_on,
  };
}

export function expenseCategoryFromRow(row: CategoryRow): ExpenseCategory {
  return { id: row.id, name: row.name, slug: row.slug };
}

/** Domain -> Insert/Update payload. Omits `user_id` (RLS owner default) and the
 *  server-managed timestamps. */
export function incomeToRow(income: IncomeSource): Partial<IncomeSourceRow> {
  return {
    id: income.id,
    name: income.name,
    amount_minor: income.amountMinor,
    currency: income.currency,
    frequency: income.frequency,
    next_payment: income.nextPayment,
  };
}

/** Domain -> Insert/Update payload. `categoryId` is the normalized FK column. */
export function fixedExpenseToRow(expense: FixedExpense): Partial<FixedExpenseRow> {
  return {
    id: expense.id,
    name: expense.name,
    amount_minor: expense.amountMinor,
    currency: expense.currency,
    billing_period: expense.billingPeriod,
    category_id: expense.categoryId,
    due_date: expense.dueDate,
  };
}

/** Domain -> Insert/Update payload (see `fixedExpenseToRow` re: category). */
export function variableExpenseToRow(expense: VariableExpense): Partial<VariableExpenseRow> {
  return {
    id: expense.id,
    name: expense.name,
    amount_minor: expense.amountMinor,
    currency: expense.currency,
    category_id: expense.categoryId,
    spent_on: expense.spentOn,
  };
}

export class SupabaseCashFlowRepository implements CashFlowRepository {
  constructor(private readonly client: SupabaseClient<Database>) {}

  async incomes(): Promise<IncomeSource[]> {
    const { data, error } = await this.client
      .from('income_sources')
      .select('*')
      .order('name', { ascending: true });
    if (error) throw error;
    return (data ?? []).map(incomeFromRow);
  }

  async fixedExpenses(): Promise<FixedExpense[]> {
    const { data, error } = await this.client
      .from('fixed_expenses')
      .select('*')
      .order('name', { ascending: true });
    if (error) throw error;
    return (data ?? []).map(fixedExpenseFromRow);
  }

  async variableExpenses(): Promise<VariableExpense[]> {
    const { data, error } = await this.client
      .from('variable_expenses')
      .select('*')
      .order('spent_on', { ascending: false });
    if (error) throw error;
    return (data ?? []).map(variableExpenseFromRow);
  }

  async expenseCategories(): Promise<ExpenseCategory[]> {
    const { data, error } = await this.client
      .from('categories')
      .select('*')
      .eq('kind', 'expense')
      .order('name', { ascending: true });
    if (error) throw error;
    return (data ?? []).map(expenseCategoryFromRow);
  }

  async upsertIncome(income: IncomeSource): Promise<void> {
    const { error } = await this.client
      .from('income_sources')
      .upsert(incomeToRow(income), { onConflict: 'id' });
    if (error) throw error;
  }

  async deleteIncome(id: string): Promise<void> {
    const { error } = await this.client.from('income_sources').delete().eq('id', id);
    if (error) throw error;
  }

  async upsertFixed(expense: FixedExpense): Promise<void> {
    const { error } = await this.client
      .from('fixed_expenses')
      .upsert(fixedExpenseToRow(expense), { onConflict: 'id' });
    if (error) throw error;
  }

  async deleteFixed(id: string): Promise<void> {
    const { error } = await this.client.from('fixed_expenses').delete().eq('id', id);
    if (error) throw error;
  }

  async upsertVariable(expense: VariableExpense): Promise<void> {
    const { error } = await this.client
      .from('variable_expenses')
      .upsert(variableExpenseToRow(expense), { onConflict: 'id' });
    if (error) throw error;
  }

  async deleteVariable(id: string): Promise<void> {
    const { error } = await this.client.from('variable_expenses').delete().eq('id', id);
    if (error) throw error;
  }
}

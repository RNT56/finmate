// SupabaseCashFlowRepository — live implementation of the `CashFlowRepository`
// protocol over the RLS-protected `income_sources`, `fixed_expenses` and
// `variable_expenses` tables (docs/03 §3; docs/05 §income_and_expenses). RLS scopes
// every row to auth.uid() (docs/07 §3); money stays integer minor units; snake_case
// columns <-> camelCase Domain are translated by the mappers below.

import type { SupabaseClient } from '@supabase/supabase-js';
import type {
  Database,
  FixedExpenseRow,
  IncomeSourceRow,
  VariableExpenseRow,
} from '../../types/database';
import type {
  CashFlowRepository,
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

export function fixedExpenseFromRow(
  row: FixedExpenseRow,
  categoryName = '',
): FixedExpense {
  return {
    id: row.id,
    name: row.name,
    amountMinor: row.amount_minor,
    currency: row.currency,
    billingPeriod: row.billing_period,
    categoryName,
    dueDate: row.due_date,
  };
}

export function variableExpenseFromRow(
  row: VariableExpenseRow,
  categoryName = '',
): VariableExpense {
  return {
    id: row.id,
    name: row.name,
    amountMinor: row.amount_minor,
    currency: row.currency,
    categoryName,
    spentOn: row.spent_on,
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
    return (data ?? []).map((row) => fixedExpenseFromRow(row));
  }

  async variableExpenses(): Promise<VariableExpense[]> {
    const { data, error } = await this.client
      .from('variable_expenses')
      .select('*')
      .order('spent_on', { ascending: false });
    if (error) throw error;
    return (data ?? []).map((row) => variableExpenseFromRow(row));
  }
}

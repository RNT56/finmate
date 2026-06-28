// Store/hook for the cash-flow slice — mirrors the iOS @Observable cash-flow store.
// Talks to repository protocols only; subscriptions roll-up reuses the M1 store.

import { useCallback, useEffect, useMemo, useState } from 'react';
import type { CurrencyCode } from '../../core/currency';
import {
  cashFlowMetrics,
  monthlyExpensesMinor,
  monthlyIncomeMinor,
  type CashFlowMetrics,
} from '../../core/cashflow';
import type { CashFlowRepository, FixedExpense, IncomeSource, VariableExpense } from './types';
import { fixedMonthlyAmountMinor } from './types';
import { InMemoryCashFlowRepository } from './repository';
import { getRepositories } from '../../lib/repositories';
import { useSubscriptions } from '../subscriptions/useSubscriptions';

export interface ExpenseBreakdownRow {
  label: string;
  amountMinor: number;
}

export interface UseCashFlow {
  loading: boolean;
  metrics: CashFlowMetrics;
  incomes: IncomeSource[];
  fixedExpenses: FixedExpense[];
  variableExpenses: VariableExpense[];
  fixedMinor: number;
  variableMinor: number;
  subscriptionsMinor: number;
  breakdown: ExpenseBreakdownRow[];
  displayCurrency: CurrencyCode;

  addIncome: (income: IncomeSource) => Promise<void>;
  removeIncome: (id: string) => Promise<void>;
  addFixed: (expense: FixedExpense) => Promise<void>;
  removeFixed: (id: string) => Promise<void>;
  addVariable: (expense: VariableExpense) => Promise<void>;
  removeVariable: (id: string) => Promise<void>;
}

const DISPLAY_CURRENCY: CurrencyCode = 'EUR';

export function useCashFlow(
  repository: CashFlowRepository = getRepositories().cashFlow,
): UseCashFlow {
  const [incomes, setIncomes] = useState<IncomeSource[]>([]);
  const [fixedExpenses, setFixedExpenses] = useState<FixedExpense[]>([]);
  const [variableExpenses, setVariableExpenses] = useState<VariableExpense[]>([]);
  const [loading, setLoading] = useState(true);

  // Subscriptions monthly roll-up comes from the shared M1 store (same sample data).
  const { monthlyTotalMinor, loading: subsLoading } = useSubscriptions();
  const subscriptionsMinor = monthlyTotalMinor(DISPLAY_CURRENCY);

  const load = useCallback(async () => {
    setLoading(true);
    const [inc, fix, vari] = await Promise.all([
      repository.incomes(),
      repository.fixedExpenses(),
      repository.variableExpenses(),
    ]);
    setIncomes(inc);
    setFixedExpenses(fix);
    setVariableExpenses(vari);
    setLoading(false);
  }, [repository]);

  useEffect(() => {
    void load();
  }, [load]);

  const addIncome = useCallback(
    async (income: IncomeSource) => {
      await repository.upsertIncome(income);
      await load();
    },
    [repository, load],
  );
  const removeIncome = useCallback(
    async (id: string) => {
      await repository.deleteIncome(id);
      await load();
    },
    [repository, load],
  );
  const addFixed = useCallback(
    async (expense: FixedExpense) => {
      await repository.upsertFixed(expense);
      await load();
    },
    [repository, load],
  );
  const removeFixed = useCallback(
    async (id: string) => {
      await repository.deleteFixed(id);
      await load();
    },
    [repository, load],
  );
  const addVariable = useCallback(
    async (expense: VariableExpense) => {
      await repository.upsertVariable(expense);
      await load();
    },
    [repository, load],
  );
  const removeVariable = useCallback(
    async (id: string) => {
      await repository.deleteVariable(id);
      await load();
    },
    [repository, load],
  );

  const fixedMinor = useMemo(
    () => fixedExpenses.reduce((sum, e) => sum + fixedMonthlyAmountMinor(e), 0),
    [fixedExpenses],
  );

  const variableMinor = useMemo(
    () => variableExpenses.reduce((sum, e) => sum + e.amountMinor, 0),
    [variableExpenses],
  );

  const incomeMinor = useMemo(
    () =>
      monthlyIncomeMinor(
        incomes.map((i) => ({ amountMinor: i.amountMinor, frequency: i.frequency })),
      ),
    [incomes],
  );

  const expenseMinor = useMemo(
    () => monthlyExpensesMinor(fixedMinor, variableMinor, subscriptionsMinor),
    [fixedMinor, variableMinor, subscriptionsMinor],
  );

  const metrics = useMemo(
    () => cashFlowMetrics(incomeMinor, expenseMinor),
    [incomeMinor, expenseMinor],
  );

  const breakdown = useMemo<ExpenseBreakdownRow[]>(
    () =>
      [
        { label: 'Fixed expenses', amountMinor: fixedMinor },
        { label: 'Subscriptions', amountMinor: subscriptionsMinor },
        { label: 'Variable (this month)', amountMinor: variableMinor },
      ]
        .filter((row) => row.amountMinor > 0)
        .sort((a, b) => b.amountMinor - a.amountMinor),
    [fixedMinor, subscriptionsMinor, variableMinor],
  );

  return {
    loading: loading || subsLoading,
    metrics,
    incomes,
    fixedExpenses,
    variableExpenses,
    fixedMinor,
    variableMinor,
    subscriptionsMinor,
    breakdown,
    displayCurrency: DISPLAY_CURRENCY,
    addIncome,
    removeIncome,
    addFixed,
    removeFixed,
    addVariable,
    removeVariable,
  };
}

/** Shared in-memory repo so all screens see the same sample data. */
export const sharedCashFlowRepository: CashFlowRepository = new InMemoryCashFlowRepository();

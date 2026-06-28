// Store/hook for the cash-flow slice — mirrors the iOS @Observable cash-flow store.
// Talks to repository protocols only; subscriptions roll-up reuses the M1 store.

import { useCallback, useEffect, useMemo, useState } from 'react';
import { CurrencyConverter, type CurrencyCode } from '../../core/currency';
import {
  cashFlowMetricsIn,
  fixedMonthlyMinorIn,
  variableThisMonthMinorIn,
  type CashFlowMetrics,
} from '../../core/cashflow';
import type {
  CashFlowRepository,
  ExpenseCategory,
  FixedExpense,
  IncomeSource,
  VariableExpense,
} from './types';
import { categoryNameFor } from './types';
import { InMemoryCashFlowRepository } from './repository';
import { getRepositories } from '../../lib/repositories';
import { useSubscriptions } from '../subscriptions/useSubscriptions';
import { usePreferences } from '../settings/usePreferences';
import { APP_RATES } from '../../lib/rates';

export interface ExpenseBreakdownRow {
  label: string;
  amountMinor: number;
}

export interface UseCashFlow {
  loading: boolean;
  /** Captured load error (null on the happy path); drives the inline error card. */
  error: string | null;
  /** Re-run the load (the error card's Retry action). */
  reload: () => Promise<void>;
  metrics: CashFlowMetrics;
  incomes: IncomeSource[];
  fixedExpenses: FixedExpense[];
  variableExpenses: VariableExpense[];
  fixedMinor: number;
  variableMinor: number;
  subscriptionsMinor: number;
  breakdown: ExpenseBreakdownRow[];
  /** Expense categories for the form select + display resolution (ADR-0022). */
  expenseCategories: ExpenseCategory[];
  /** Resolve a `categoryId → name` ("Uncategorized" fallback) for row labels. */
  categoryName: (id: string | null) => string;
  displayCurrency: CurrencyCode;

  addIncome: (income: IncomeSource) => Promise<void>;
  removeIncome: (id: string) => Promise<void>;
  addFixed: (expense: FixedExpense) => Promise<void>;
  removeFixed: (id: string) => Promise<void>;
  addVariable: (expense: VariableExpense) => Promise<void>;
  removeVariable: (id: string) => Promise<void>;
}

export function useCashFlow(
  repository: CashFlowRepository = getRepositories().cashFlow
): UseCashFlow {
  const [incomes, setIncomes] = useState<IncomeSource[]>([]);
  const [fixedExpenses, setFixedExpenses] = useState<FixedExpense[]>([]);
  const [variableExpenses, setVariableExpenses] = useState<VariableExpense[]>(
    []
  );
  const [expenseCategories, setExpenseCategories] = useState<ExpenseCategory[]>(
    []
  );
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // App-wide display currency is the single source of truth in Settings (docs/02 §12).
  const { preferences } = usePreferences();
  const displayCurrency = preferences.defaultCurrency;
  const converter = useMemo(() => new CurrencyConverter(APP_RATES), []);

  // Subscriptions monthly roll-up comes from the shared M1 store (same sample data),
  // converted to the SAME display currency so the breakdown/expenses agree.
  const {
    monthlyTotalMinor,
    loading: subsLoading,
    error: subsError,
  } = useSubscriptions();
  const subscriptionsMinor = monthlyTotalMinor(displayCurrency);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [inc, fix, vari, cats] = await Promise.all([
        repository.incomes(),
        repository.fixedExpenses(),
        repository.variableExpenses(),
        repository.expenseCategories(),
      ]);
      setIncomes(inc);
      setFixedExpenses(fix);
      setVariableExpenses(vari);
      setExpenseCategories(cats);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load cash flow.');
    } finally {
      setLoading(false);
    }
  }, [repository]);

  useEffect(() => {
    void load();
  }, [load]);

  const addIncome = useCallback(
    async (income: IncomeSource) => {
      await repository.upsertIncome(income);
      await load();
    },
    [repository, load]
  );
  const removeIncome = useCallback(
    async (id: string) => {
      await repository.deleteIncome(id);
      await load();
    },
    [repository, load]
  );
  const addFixed = useCallback(
    async (expense: FixedExpense) => {
      await repository.upsertFixed(expense);
      await load();
    },
    [repository, load]
  );
  const removeFixed = useCallback(
    async (id: string) => {
      await repository.deleteFixed(id);
      await load();
    },
    [repository, load]
  );
  const addVariable = useCallback(
    async (expense: VariableExpense) => {
      await repository.upsertVariable(expense);
      await load();
    },
    [repository, load]
  );
  const removeVariable = useCallback(
    async (id: string) => {
      await repository.deleteVariable(id);
      await load();
    },
    [repository, load]
  );

  // Every roll-up converts each item to the display currency at READ time before
  // summing (docs/13 §6/§7) — stored amounts are never mutated. This both expresses
  // the figures in the display currency AND correctly sums mixed-currency inputs.
  const fixedMinor = useMemo(
    () =>
      fixedMonthlyMinorIn(
        fixedExpenses.map((e) => ({
          amountMinor: e.amountMinor,
          currency: e.currency,
          billingPeriod: e.billingPeriod,
        })),
        displayCurrency,
        converter
      ),
    [fixedExpenses, displayCurrency, converter]
  );

  const variableMinor = useMemo(
    () =>
      variableThisMonthMinorIn(
        variableExpenses.map((e) => ({
          amountMinor: e.amountMinor,
          currency: e.currency,
        })),
        displayCurrency,
        converter
      ),
    [variableExpenses, displayCurrency, converter]
  );

  const metrics = useMemo(
    () =>
      cashFlowMetricsIn(
        incomes.map((i) => ({
          amountMinor: i.amountMinor,
          currency: i.currency,
          frequency: i.frequency,
        })),
        fixedExpenses.map((e) => ({
          amountMinor: e.amountMinor,
          currency: e.currency,
          billingPeriod: e.billingPeriod,
        })),
        variableExpenses.map((e) => ({
          amountMinor: e.amountMinor,
          currency: e.currency,
        })),
        subscriptionsMinor,
        displayCurrency,
        converter
      ),
    [incomes, fixedExpenses, variableExpenses, subscriptionsMinor, displayCurrency, converter]
  );

  const categoryName = useCallback(
    (id: string | null) => categoryNameFor(id, expenseCategories),
    [expenseCategories]
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
    [fixedMinor, subscriptionsMinor, variableMinor]
  );

  return {
    loading: loading || subsLoading,
    error: error ?? subsError,
    reload: load,
    metrics,
    incomes,
    fixedExpenses,
    variableExpenses,
    fixedMinor,
    variableMinor,
    subscriptionsMinor,
    breakdown,
    expenseCategories,
    categoryName,
    displayCurrency,
    addIncome,
    removeIncome,
    addFixed,
    removeFixed,
    addVariable,
    removeVariable,
  };
}

/** Shared in-memory repo so all screens see the same sample data. */
export const sharedCashFlowRepository: CashFlowRepository =
  new InMemoryCashFlowRepository();

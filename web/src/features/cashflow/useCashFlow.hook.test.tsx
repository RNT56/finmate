// Hook-layer tests for useCashFlow — the React store wiring the CashFlowRepository
// protocol + core/cashflow metrics into the UI. Mirrors the iOS CashFlowStore tests.
//
// useCashFlow internally consumes usePreferences() (for the display currency) and
// useSubscriptions() (for the subscriptions roll-up), so tests render it inside a
// PreferencesProvider with an injected in-memory preferences repo. The cash-flow
// repository itself is a hand-rolled mock. The subscriptions roll-up comes from the
// default (offline sample) repo = €26.48, matching the rest of the suite.
//
// @vitest-environment jsdom

import { describe, it, expect, beforeEach } from 'vitest';
import type { ReactNode } from 'react';
import { renderHook, waitFor, act } from '@testing-library/react';
import { useCashFlow } from './useCashFlow';
import { usePreferences, PreferencesProvider } from '../settings/usePreferences';
import {
  InMemoryPreferencesRepository,
  type PreferencesRepository,
  type UserPreferences,
} from '../../core/preferences';
import type {
  CashFlowRepository,
  ExpenseCategory,
  FixedExpense,
  IncomeSource,
  VariableExpense,
} from './types';

const SAMPLE_CATEGORIES: ExpenseCategory[] = [
  { id: 'cat-housing', name: 'Housing', slug: 'housing' },
  { id: 'cat-groceries', name: 'Groceries', slug: 'groceries' },
];

class MockCashFlowRepository implements CashFlowRepository {
  incomeStore = new Map<string, IncomeSource>();
  fixedStore = new Map<string, FixedExpense>();
  variableStore = new Map<string, VariableExpense>();

  constructor(
    seedInc: IncomeSource[] = [],
    seedFixed: FixedExpense[] = [],
    seedVar: VariableExpense[] = []
  ) {
    seedInc.forEach((i) => this.incomeStore.set(i.id, { ...i }));
    seedFixed.forEach((e) => this.fixedStore.set(e.id, { ...e }));
    seedVar.forEach((e) => this.variableStore.set(e.id, { ...e }));
  }

  async incomes() {
    return [...this.incomeStore.values()].map((i) => ({ ...i }));
  }
  async fixedExpenses() {
    return [...this.fixedStore.values()].map((e) => ({ ...e }));
  }
  async variableExpenses() {
    return [...this.variableStore.values()].map((e) => ({ ...e }));
  }
  async expenseCategories() {
    return SAMPLE_CATEGORIES.map((c) => ({ ...c }));
  }
  async upsertIncome(income: IncomeSource) {
    this.incomeStore.set(income.id, { ...income });
  }
  async deleteIncome(id: string) {
    this.incomeStore.delete(id);
  }
  async upsertFixed(expense: FixedExpense) {
    this.fixedStore.set(expense.id, { ...expense });
  }
  async deleteFixed(id: string) {
    this.fixedStore.delete(id);
  }
  async upsertVariable(expense: VariableExpense) {
    this.variableStore.set(expense.id, { ...expense });
  }
  async deleteVariable(id: string) {
    this.variableStore.delete(id);
  }
}

class ThrowingCashFlowRepository implements CashFlowRepository {
  async incomes(): Promise<IncomeSource[]> {
    throw new Error('cashflow boom');
  }
  async fixedExpenses(): Promise<FixedExpense[]> {
    return [];
  }
  async variableExpenses(): Promise<VariableExpense[]> {
    return [];
  }
  async expenseCategories(): Promise<ExpenseCategory[]> {
    return [];
  }
  async upsertIncome(): Promise<void> {}
  async deleteIncome(): Promise<void> {}
  async upsertFixed(): Promise<void> {}
  async deleteFixed(): Promise<void> {}
  async upsertVariable(): Promise<void> {}
  async deleteVariable(): Promise<void> {}
}

function income(overrides: Partial<IncomeSource> = {}): IncomeSource {
  return {
    id: 'inc-1',
    name: 'Salary',
    amountMinor: 320000,
    currency: 'EUR',
    frequency: 'monthly',
    nextPayment: null,
    ...overrides,
  };
}
function fixed(overrides: Partial<FixedExpense> = {}): FixedExpense {
  return {
    id: 'fix-1',
    name: 'Rent',
    amountMinor: 110000,
    currency: 'EUR',
    billingPeriod: 'monthly',
    categoryId: 'cat-housing',
    dueDate: null,
    ...overrides,
  };
}
function variable(overrides: Partial<VariableExpense> = {}): VariableExpense {
  return {
    id: 'var-1',
    name: 'Groceries',
    amountMinor: 40000,
    currency: 'EUR',
    categoryId: 'cat-groceries',
    spentOn: new Date().toISOString().slice(0, 10),
    ...overrides,
  };
}

/** Provider wrapper with an injected, controllable preferences repo. */
function wrapperWith(prefsRepo: PreferencesRepository) {
  return function Wrapper({ children }: { children: ReactNode }) {
    return <PreferencesProvider repository={prefsRepo}>{children}</PreferencesProvider>;
  };
}

/** Renders useCashFlow alongside usePreferences so tests can flip the currency live. */
function renderCashFlow(
  repo: CashFlowRepository,
  prefsRepo: PreferencesRepository = new InMemoryPreferencesRepository()
) {
  return renderHook(
    () => ({ cf: useCashFlow(repo), prefs: usePreferences() }),
    { wrapper: wrapperWith(prefsRepo) }
  );
}

describe('useCashFlow (hook)', () => {
  let repo: MockCashFlowRepository;

  beforeEach(() => {
    repo = new MockCashFlowRepository(
      [income({ id: 'inc-1', amountMinor: 320000 }), income({ id: 'inc-2', name: 'Freelance', amountMinor: 60000 })],
      [fixed({ id: 'fix-1', amountMinor: 110000 }), fixed({ id: 'fix-2', name: 'Insurance', amountMinor: 9000 })],
      [variable({ id: 'var-1', amountMinor: 40000 })]
    );
  });

  it('loads incomes/expenses/categories and computes metrics (happy path)', async () => {
    const { result } = renderCashFlow(repo);
    await waitFor(() => expect(result.current.cf.loading).toBe(false));
    expect(result.current.cf.error).toBeNull();
    expect(result.current.cf.incomes).toHaveLength(2);
    expect(result.current.cf.fixedExpenses).toHaveLength(2);
    expect(result.current.cf.variableExpenses).toHaveLength(1);
    // income 380000; fixed 119000; variable 40000; subscriptions 2648 (sample).
    expect(result.current.cf.metrics.incomeMinor).toBe(380000);
    expect(result.current.cf.fixedMinor).toBe(119000);
    expect(result.current.cf.variableMinor).toBe(40000);
    expect(result.current.cf.subscriptionsMinor).toBe(2648);
    expect(result.current.cf.metrics.expenseMinor).toBe(119000 + 40000 + 2648);
  });

  it('loads empty (no NaN; zero metrics for income/fixed/variable)', async () => {
    const { result } = renderCashFlow(new MockCashFlowRepository([], [], []));
    await waitFor(() => expect(result.current.cf.loading).toBe(false));
    expect(result.current.cf.incomes).toHaveLength(0);
    expect(result.current.cf.metrics.incomeMinor).toBe(0);
    expect(result.current.cf.fixedMinor).toBe(0);
    expect(result.current.cf.variableMinor).toBe(0);
  });

  it('addIncome() upserts then reloads (income recompute)', async () => {
    const { result } = renderCashFlow(repo);
    await waitFor(() => expect(result.current.cf.loading).toBe(false));
    await act(async () => {
      await result.current.cf.addIncome(income({ id: 'inc-3', name: 'Bonus', amountMinor: 20000 }));
    });
    await waitFor(() => expect(result.current.cf.incomes).toHaveLength(3));
    expect(result.current.cf.metrics.incomeMinor).toBe(400000);
  });

  it('addFixed() upserts then reloads (fixed recompute)', async () => {
    const { result } = renderCashFlow(repo);
    await waitFor(() => expect(result.current.cf.loading).toBe(false));
    await act(async () => {
      await result.current.cf.addFixed(fixed({ id: 'fix-3', name: 'Gym', amountMinor: 5000 }));
    });
    await waitFor(() => expect(result.current.cf.fixedExpenses).toHaveLength(3));
    expect(result.current.cf.fixedMinor).toBe(124000);
  });

  it('addVariable() upserts then reloads (variable recompute)', async () => {
    const { result } = renderCashFlow(repo);
    await waitFor(() => expect(result.current.cf.loading).toBe(false));
    await act(async () => {
      await result.current.cf.addVariable(variable({ id: 'var-2', name: 'Dinner', amountMinor: 6000 }));
    });
    await waitFor(() => expect(result.current.cf.variableExpenses).toHaveLength(2));
    expect(result.current.cf.variableMinor).toBe(46000);
  });

  it('remove* deletes then reloads', async () => {
    const { result } = renderCashFlow(repo);
    await waitFor(() => expect(result.current.cf.loading).toBe(false));
    await act(async () => {
      await result.current.cf.removeIncome('inc-2');
      await result.current.cf.removeFixed('fix-2');
    });
    await waitFor(() => expect(result.current.cf.incomes).toHaveLength(1));
    expect(result.current.cf.metrics.incomeMinor).toBe(320000);
    expect(result.current.cf.fixedMinor).toBe(110000);
  });

  it('switching display currency recomputes aggregates (EUR -> USD @ 1.10)', async () => {
    const { result } = renderCashFlow(repo);
    await waitFor(() => expect(result.current.cf.loading).toBe(false));
    expect(result.current.cf.displayCurrency).toBe('EUR');
    const eurIncome = result.current.cf.metrics.incomeMinor;
    expect(eurIncome).toBe(380000);

    act(() => {
      result.current.prefs.update({ defaultCurrency: 'USD' });
    });
    await waitFor(() => expect(result.current.cf.displayCurrency).toBe('USD'));
    // EUR 380000 -> USD @ 1.10 = 418000.
    expect(result.current.cf.metrics.incomeMinor).toBe(418000);
    // Fixed 119000 EUR -> 130900 USD.
    expect(result.current.cf.fixedMinor).toBe(130900);
  });

  it('captures a load error into error state', async () => {
    const prefsRepo = new InMemoryPreferencesRepository();
    const { result } = renderCashFlow(new ThrowingCashFlowRepository(), prefsRepo);
    await waitFor(() => expect(result.current.cf.loading).toBe(false));
    expect(result.current.cf.error).toBe('cashflow boom');
  });

  it('starts from an injected display currency (USD)', async () => {
    const usdPrefs = new InMemoryPreferencesRepository({
      appearance: 'system',
      defaultCurrency: 'USD',
      biometricLockEnabled: false,
      paymentRemindersEnabled: true,
      paydayRemindersEnabled: true,
      reminderLeadTimeDays: 2,
    } satisfies UserPreferences);
    const { result } = renderCashFlow(repo, usdPrefs);
    await waitFor(() => expect(result.current.cf.loading).toBe(false));
    expect(result.current.cf.displayCurrency).toBe('USD');
    expect(result.current.cf.metrics.incomeMinor).toBe(418000);
  });
});

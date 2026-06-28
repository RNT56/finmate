// InMemoryCashFlowRepository + SAMPLE DATA — mirrors the iOS in-memory repo / sample
// data pattern. Figures match the iOS slice so both clients display identical numbers:
//   income  = Salary 320000 + Freelance 60000 (both monthly) = 380000 (€3,800.00)
//   fixed   = Rent 110000 + Insurance 9000 (both monthly)     = 119000 (€1,190.00)
//   variable (current month) = Groceries 40000                =  40000 (€400.00)
//   subscriptions monthly roll-up (from the M1 sample data)    =   2648 (€26.48)

import type {
  CashFlowRepository,
  FixedExpense,
  IncomeSource,
  VariableExpense,
} from './types';

export const sampleIncomes: IncomeSource[] = [
  {
    id: 'inc-salary',
    name: 'Salary',
    amountMinor: 320000, // €3,200.00 / month
    currency: 'EUR',
    frequency: 'monthly',
    nextPayment: '2026-01-25', // payday on the 25th each month
  },
  {
    id: 'inc-freelance',
    name: 'Freelance',
    amountMinor: 60000, // €600.00 / month
    currency: 'EUR',
    frequency: 'monthly',
    nextPayment: '2026-01-10', // freelance invoice on the 10th
  },
];

export const sampleFixedExpenses: FixedExpense[] = [
  {
    id: 'fix-rent',
    name: 'Rent',
    amountMinor: 110000, // €1,100.00 / month
    currency: 'EUR',
    billingPeriod: 'monthly',
    categoryName: 'Housing',
    dueDate: '2026-01-01', // rent due on the 1st
  },
  {
    id: 'fix-insurance',
    name: 'Insurance',
    amountMinor: 9000, // €90.00 / month
    currency: 'EUR',
    billingPeriod: 'monthly',
    categoryName: 'Insurance',
    dueDate: '2026-01-18', // insurance debit on the 18th
  },
];

export const sampleVariableExpenses: VariableExpense[] = [
  {
    id: 'var-groceries',
    name: 'Groceries',
    amountMinor: 40000, // €400.00 this month
    currency: 'EUR',
    categoryName: 'Groceries',
    spentOn: '2026-06-15',
  },
];

export class InMemoryCashFlowRepository implements CashFlowRepository {
  constructor(
    private readonly seedIncomes: IncomeSource[] = sampleIncomes,
    private readonly seedFixed: FixedExpense[] = sampleFixedExpenses,
    private readonly seedVariable: VariableExpense[] = sampleVariableExpenses,
  ) {}

  async incomes(): Promise<IncomeSource[]> {
    return this.seedIncomes.map((i) => ({ ...i }));
  }

  async fixedExpenses(): Promise<FixedExpense[]> {
    return this.seedFixed.map((e) => ({ ...e }));
  }

  async variableExpenses(): Promise<VariableExpense[]> {
    return this.seedVariable.map((e) => ({ ...e }));
  }
}

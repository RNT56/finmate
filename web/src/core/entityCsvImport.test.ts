// Entity CSV importer tests — SAME vectors as the Swift `EntityCSVImportersTests`
// (docs/13 §9, docs/02 §6). Income + fixed/variable expenses on the shared kit:
// clean, dirty, multi-currency, category name→id, missing-required.

import { describe, it, expect } from 'vitest';
import {
  analyzeIncomeHeader,
  parseIncomeCSVWithMapping,
  analyzeFixedExpenseHeader,
  parseFixedExpenseCSVWithMapping,
  analyzeVariableExpenseHeader,
  parseVariableExpenseCSVWithMapping,
} from './csvImport';
import type { ExpenseCategory } from '../features/cashflow/types';

// ===========================================================================
// Income
// ===========================================================================
describe('IncomeCSVImporter', () => {
  it('analyzeHeader returns raw tokens + alias auto-mapping', () => {
    const csv = ['Source, Pay ,CCY,Freq', 'Salary,3000,EUR,monthly'].join('\n');
    const a = analyzeIncomeHeader(csv);
    expect(a.headers).toEqual(['Source', 'Pay', 'CCY', 'Freq']);
    expect(a.autoMapping.name).toBe(0);
    expect(a.autoMapping.amount).toBe(1);
    expect(a.autoMapping.currency).toBe(2);
    expect(a.autoMapping.frequency).toBe(3);
    expect(a.autoMapping.notes).toBeUndefined();
  });

  it('imports clean rows with frequency + next_payment parsed', () => {
    const csv = [
      'name,amount,currency,frequency,next_payment,notes',
      'Salary,3000.00,EUR,monthly,2026-07-01,Main job',
      'Dividend,150,USD,yearly,,',
      'Gift,50,EUR,one_time,,Birthday',
    ].join('\n');
    const mapping = analyzeIncomeHeader(csv).autoMapping;
    const preview = parseIncomeCSVWithMapping(csv, mapping);
    expect(preview.totalRows).toBe(3);
    expect(preview.valid).toHaveLength(3);
    expect(preview.valid[0].name).toBe('Salary');
    expect(preview.valid[0].amountMinor).toBe(300000);
    expect(preview.valid[0].frequency).toBe('monthly');
    expect(preview.valid[0].nextPayment).toBe('2026-07-01');
    expect(preview.valid[2].frequency).toBe('one_time');
    expect(preview.valid[1].currency).toBe('USD');
  });

  it('handles multi-currency: EUR/USD cents, BTC sats', () => {
    const csv = [
      'name,amount,currency',
      'Salary,3000,EUR',
      'Bonus,1000,USD',
      'Mining,0.00012345,BTC',
    ].join('\n');
    const mapping = analyzeIncomeHeader(csv).autoMapping;
    const preview = parseIncomeCSVWithMapping(csv, mapping);
    expect(preview.valid).toHaveLength(3);
    expect(preview.valid[0].amountMinor).toBe(300000);
    expect(preview.valid[1].amountMinor).toBe(100000);
    expect(preview.valid[2].amountMinor).toBe(12345);
    expect(preview.valid[2].currency).toBe('BTC');
  });

  it('collects ALL dirty-row errors', () => {
    const csv = [
      'name,amount,currency,frequency,next_payment',
      'Salary,abc,EUR,monthly,2026-07-01',
      'Side,500,GBP,monthly,2026-07-01',
      'Odd,500,EUR,fortnightly,2026-07-01',
      'Bad,500,EUR,monthly,not-a-date',
      ',500,EUR,monthly,2026-07-01',
    ].join('\n');
    const mapping = analyzeIncomeHeader(csv).autoMapping;
    const preview = parseIncomeCSVWithMapping(csv, mapping);
    expect(preview.totalRows).toBe(5);
    expect(preview.valid).toHaveLength(0);
    expect(preview.errors.some((e) => e.row === 2 && e.field === 'amount')).toBe(true);
    expect(preview.errors.some((e) => e.row === 3 && e.field === 'currency')).toBe(true);
    expect(preview.errors.some((e) => e.row === 4 && e.field === 'frequency')).toBe(true);
    expect(preview.errors.some((e) => e.row === 5 && e.field === 'next_payment')).toBe(true);
    expect(preview.errors.some((e) => e.row === 6 && e.field === 'name')).toBe(true);
  });

  it('errors a row whose required amount is blank', () => {
    const csv = ['name,amount', 'Salary,'].join('\n');
    const mapping = analyzeIncomeHeader(csv).autoMapping;
    const preview = parseIncomeCSVWithMapping(csv, mapping);
    expect(preview.valid).toHaveLength(0);
    expect(preview.errors.some((e) => e.row === 2 && e.field === 'amount')).toBe(true);
  });
});

// ===========================================================================
// Fixed expense
// ===========================================================================
const fixedCategories: ExpenseCategory[] = [
  { id: 'cat-housing', name: 'Housing', slug: 'housing' },
  { id: 'cat-utilities', name: 'Utilities', slug: 'utilities' },
];

describe('FixedExpenseCSVImporter', () => {
  it('analyzeHeader auto-maps category/frequency/due_date/autopay', () => {
    const csv = [
      'name,amount,currency,category,frequency,due_date,autopay',
      'Rent,1200,EUR,Housing,monthly,2026-07-01,true',
    ].join('\n');
    const a = analyzeFixedExpenseHeader(csv);
    expect(a.autoMapping.name).toBe(0);
    expect(a.autoMapping.amount).toBe(1);
    expect(a.autoMapping.category).toBe(3);
    expect(a.autoMapping.frequency).toBe(4);
    expect(a.autoMapping.due_date).toBe(5);
    expect(a.autoMapping.autopay).toBe(6);
  });

  it('resolves category NAME → id (case-insensitive) + parses autopay bool', () => {
    const csv = [
      'name,amount,currency,category,frequency,due_date,autopay',
      'Rent,1200.00,EUR,Housing,monthly,2026-07-01,true',
      'Power,90,EUR,utilities,monthly,2026-07-15,no',
      'Unknown,30,EUR,Mystery,monthly,,',
    ].join('\n');
    const mapping = analyzeFixedExpenseHeader(csv).autoMapping;
    const preview = parseFixedExpenseCSVWithMapping(csv, mapping, fixedCategories);
    expect(preview.valid).toHaveLength(3);
    expect(preview.valid[0].amountMinor).toBe(120000);
    expect(preview.valid[0].categoryId).toBe('cat-housing');
    expect(preview.valid[1].categoryId).toBe('cat-utilities'); // case-insensitive
    expect(preview.valid[2].categoryId).toBeNull(); // "Mystery" → Uncategorized
  });

  it('handles multi-currency: EUR/USD cents, BTC sats', () => {
    const csv = ['name,amount,currency', 'Rent,1200,EUR', 'Server,20,USD', 'Cold,0.001,BTC'].join(
      '\n'
    );
    const mapping = analyzeFixedExpenseHeader(csv).autoMapping;
    const preview = parseFixedExpenseCSVWithMapping(csv, mapping, fixedCategories);
    expect(preview.valid).toHaveLength(3);
    expect(preview.valid[0].amountMinor).toBe(120000);
    expect(preview.valid[1].amountMinor).toBe(2000);
    expect(preview.valid[2].amountMinor).toBe(100000);
    expect(preview.valid[2].currency).toBe('BTC');
  });

  it('collects ALL dirty-row errors (incl. invalid autopay)', () => {
    const csv = [
      'name,amount,currency,frequency,due_date,autopay',
      'Rent,1200,EUR,monthly,2026-07-01,true',
      'Bad,xx,EUR,monthly,2026-07-01,true',
      'Cur,10,GBP,monthly,2026-07-01,true',
      'Freq,10,EUR,fortnightly,2026-07-01,true',
      'Date,10,EUR,monthly,nope,true',
      'Auto,10,EUR,monthly,2026-07-01,maybe',
    ].join('\n');
    const mapping = analyzeFixedExpenseHeader(csv).autoMapping;
    const preview = parseFixedExpenseCSVWithMapping(csv, mapping, fixedCategories);
    expect(preview.valid).toHaveLength(1);
    expect(preview.errors.some((e) => e.row === 3 && e.field === 'amount')).toBe(true);
    expect(preview.errors.some((e) => e.row === 4 && e.field === 'currency')).toBe(true);
    expect(preview.errors.some((e) => e.row === 5 && e.field === 'frequency')).toBe(true);
    expect(preview.errors.some((e) => e.row === 6 && e.field === 'due_date')).toBe(true);
    expect(preview.errors.some((e) => e.row === 7 && e.field === 'autopay')).toBe(true);
  });

  it('errors a row whose required name is blank', () => {
    const csv = ['name,amount', ',1200'].join('\n');
    const mapping = analyzeFixedExpenseHeader(csv).autoMapping;
    const preview = parseFixedExpenseCSVWithMapping(csv, mapping, fixedCategories);
    expect(preview.valid).toHaveLength(0);
    expect(preview.errors.some((e) => e.row === 2 && e.field === 'name')).toBe(true);
  });

  it('supports weekly frequency (BillingPeriod.weekly)', () => {
    const csv = ['name,amount,frequency', 'Cleaner,50,weekly'].join('\n');
    const mapping = analyzeFixedExpenseHeader(csv).autoMapping;
    const preview = parseFixedExpenseCSVWithMapping(csv, mapping, fixedCategories);
    expect(preview.valid).toHaveLength(1);
    expect(preview.valid[0].billingPeriod).toBe('weekly');
  });
});

// ===========================================================================
// Variable expense
// ===========================================================================
const variableCategories: ExpenseCategory[] = [
  { id: 'cat-groceries', name: 'Groceries', slug: 'groceries' },
  { id: 'cat-dining', name: 'Dining', slug: 'dining' },
];

describe('VariableExpenseCSVImporter', () => {
  it('analyzeHeader auto-maps spent_on → date', () => {
    const csv = [
      'name,amount,currency,category,spent_on',
      'Lunch,12.50,EUR,Dining,2026-06-15',
    ].join('\n');
    const a = analyzeVariableExpenseHeader(csv);
    expect(a.autoMapping.name).toBe(0);
    expect(a.autoMapping.amount).toBe(1);
    expect(a.autoMapping.category).toBe(3);
    expect(a.autoMapping.date).toBe(4);
  });

  it('resolves category NAME → id (case-insensitive)', () => {
    const csv = [
      'name,amount,currency,category,spent_on',
      'Groceries,45.20,EUR,Groceries,2026-06-10',
      'Lunch,12.50,EUR,dining,2026-06-15',
      'Misc,5,EUR,Nope,2026-06-16',
    ].join('\n');
    const mapping = analyzeVariableExpenseHeader(csv).autoMapping;
    const preview = parseVariableExpenseCSVWithMapping(csv, mapping, variableCategories);
    expect(preview.valid).toHaveLength(3);
    expect(preview.valid[0].amountMinor).toBe(4520);
    expect(preview.valid[0].categoryId).toBe('cat-groceries');
    expect(preview.valid[1].categoryId).toBe('cat-dining'); // case-insensitive
    expect(preview.valid[2].categoryId).toBeNull();
  });

  it('handles multi-currency: EUR/USD cents, BTC sats', () => {
    const csv = [
      'name,amount,currency,spent_on',
      'A,10,EUR,2026-06-10',
      'B,10,USD,2026-06-10',
      'C,0.0005,BTC,2026-06-10',
    ].join('\n');
    const mapping = analyzeVariableExpenseHeader(csv).autoMapping;
    const preview = parseVariableExpenseCSVWithMapping(csv, mapping, variableCategories);
    expect(preview.valid).toHaveLength(3);
    expect(preview.valid[0].amountMinor).toBe(1000);
    expect(preview.valid[1].amountMinor).toBe(1000);
    expect(preview.valid[2].amountMinor).toBe(50000);
    expect(preview.valid[2].currency).toBe('BTC');
  });

  it('requires date — missing/invalid errors, valid carried through', () => {
    const csv = [
      'name,amount,spent_on',
      'NoDate,10,',
      'BadDate,10,not-a-date',
      'Good,10,2026-06-10',
    ].join('\n');
    const mapping = analyzeVariableExpenseHeader(csv).autoMapping;
    const preview = parseVariableExpenseCSVWithMapping(csv, mapping, variableCategories);
    expect(preview.totalRows).toBe(3);
    expect(preview.valid).toHaveLength(1);
    expect(preview.valid[0].name).toBe('Good');
    expect(preview.valid[0].spentOn).toBe('2026-06-10');
    expect(preview.errors.some((e) => e.row === 2 && e.field === 'date')).toBe(true);
    expect(preview.errors.some((e) => e.row === 3 && e.field === 'date')).toBe(true);
  });

  it('collects ALL dirty-row errors', () => {
    const csv = [
      'name,amount,currency,spent_on',
      'Good,10,EUR,2026-06-10',
      ',10,EUR,2026-06-10',
      'Bad,xx,EUR,2026-06-10',
      'Cur,10,GBP,2026-06-10',
    ].join('\n');
    const mapping = analyzeVariableExpenseHeader(csv).autoMapping;
    const preview = parseVariableExpenseCSVWithMapping(csv, mapping, variableCategories);
    expect(preview.valid).toHaveLength(1);
    expect(preview.errors.some((e) => e.row === 3 && e.field === 'name')).toBe(true);
    expect(preview.errors.some((e) => e.row === 4 && e.field === 'amount')).toBe(true);
    expect(preview.errors.some((e) => e.row === 5 && e.field === 'currency')).toBe(true);
  });

  it('recovers rows under an explicit mapping over an unmappable header', () => {
    const csv = ['c0,c1,c2', 'Lunch,12.50,2026-06-15'].join('\n');
    const preview = parseVariableExpenseCSVWithMapping(
      csv,
      { name: 0, amount: 1, date: 2 },
      variableCategories
    );
    expect(preview.valid).toHaveLength(1);
    expect(preview.valid[0].name).toBe('Lunch');
    expect(preview.valid[0].amountMinor).toBe(1250);
  });
});

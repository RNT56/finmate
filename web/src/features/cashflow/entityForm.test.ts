import { describe, expect, it } from 'vitest';
import { buildFixed, buildIncome, buildVariable, newEntityId, type EntityFormDraft } from './entityForm';

function draft(overrides: Partial<EntityFormDraft> = {}): EntityFormDraft {
  return {
    name: 'Salary',
    amount: '3200',
    currency: 'EUR',
    cadence: 'monthly',
    categoryName: 'Housing',
    date: '',
    ...overrides,
  };
}

describe('buildIncome', () => {
  it('parses amount via the money parser into minor units', () => {
    const r = buildIncome(draft({ amount: '3200.50' }), 'inc-1');
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.amountMinor).toBe(320050);
      expect(r.value.frequency).toBe('monthly');
      expect(r.value.id).toBe('inc-1');
      expect(r.value.nextPayment).toBeNull();
    }
  });

  it('keeps a supplied next-payment date', () => {
    const r = buildIncome(draft({ date: '2026-07-25' }), 'inc-1');
    expect(r.ok && r.value.nextPayment).toBe('2026-07-25');
  });

  it('rejects an empty name', () => {
    const r = buildIncome(draft({ name: '  ' }), 'inc-1');
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toMatch(/name/i);
  });

  it('rejects a negative amount', () => {
    const r = buildIncome(draft({ amount: '-5' }), 'inc-1');
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toMatch(/non-negative/i);
  });

  it('rejects over-precision', () => {
    const r = buildIncome(draft({ amount: '1.234' }), 'inc-1');
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toMatch(/2 decimals/i);
  });

  it('rejects zero', () => {
    const r = buildIncome(draft({ amount: '0' }), 'inc-1');
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toMatch(/greater than zero/i);
  });
});

describe('buildFixed', () => {
  it('builds a fixed expense with billing period and category', () => {
    const r = buildFixed(draft({ name: 'Rent', amount: '1100', cadence: 'monthly', date: '2026-07-01' }), 'fix-1');
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.amountMinor).toBe(110000);
      expect(r.value.billingPeriod).toBe('monthly');
      expect(r.value.categoryName).toBe('Housing');
      expect(r.value.dueDate).toBe('2026-07-01');
    }
  });

  it('defaults a blank category to Other', () => {
    const r = buildFixed(draft({ categoryName: '   ' }), 'fix-1');
    expect(r.ok && r.value.categoryName).toBe('Other');
  });
});

describe('buildVariable', () => {
  it('builds a variable expense, defaulting spentOn to the supplied today', () => {
    const r = buildVariable(draft({ name: 'Groceries', amount: '40' }), 'var-1', '2026-06-28');
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.amountMinor).toBe(4000);
      expect(r.value.spentOn).toBe('2026-06-28');
    }
  });

  it('keeps an explicit spentOn date', () => {
    const r = buildVariable(draft({ date: '2026-06-15' }), 'var-1', '2026-06-28');
    expect(r.ok && r.value.spentOn).toBe('2026-06-15');
  });
});

describe('newEntityId', () => {
  it('prefixes the id', () => {
    expect(newEntityId('inc')).toMatch(/^inc-\d+$/);
  });
});

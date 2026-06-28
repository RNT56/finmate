import { describe, it, expect } from 'vitest';
import { monthlyMinorUnits, annualMinorUnits, incomeMonthlyMinorUnits } from './normalization';

// Worked vectors mirror the Swift Domain tests (docs/13 §3, §6).

describe('monthlyMinorUnits', () => {
  it('T3.1a yearly €120 -> €10.00/mo', () => {
    expect(monthlyMinorUnits(12000, 'yearly')).toBe(1000);
  });

  it('T3.1b weekly $100 -> $433.33/mo (×52/12, HALF-UP)', () => {
    expect(monthlyMinorUnits(10000, 'weekly')).toBe(43333);
  });

  it('T3.1c quarterly €30 -> €10.00/mo', () => {
    expect(monthlyMinorUnits(3000, 'quarterly')).toBe(1000);
  });

  it('T3.1d monthly identity', () => {
    expect(monthlyMinorUnits(1549, 'monthly')).toBe(1549);
  });

  it('T3.1e weekly €1 -> €4.33/mo (not ×4)', () => {
    expect(monthlyMinorUnits(100, 'weekly')).toBe(433);
  });

  it('iCloud+ €29.99/yr -> €2.50/mo (Home total ingredient)', () => {
    expect(monthlyMinorUnits(2999, 'yearly')).toBe(250);
  });
});

describe('annualMinorUnits', () => {
  it('T3.1b weekly $100 -> $5,200/yr', () => {
    expect(annualMinorUnits(10000, 'weekly')).toBe(520000);
  });
  it('monthly €15.49 -> €185.88/yr', () => {
    expect(annualMinorUnits(1549, 'monthly')).toBe(18588);
  });
  it('quarterly €30 -> €120/yr (×4 direct)', () => {
    expect(annualMinorUnits(3000, 'quarterly')).toBe(12000);
  });
});

describe('incomeMonthlyMinorUnits', () => {
  it('weekly €100 income -> €433.33/mo', () => {
    expect(incomeMonthlyMinorUnits(10000, 'weekly')).toBe(43333);
  });
  it('one_time contributes 0 to recurring monthly', () => {
    expect(incomeMonthlyMinorUnits(50000, 'one_time')).toBe(0);
  });
  it('yearly /12 HALF-UP', () => {
    expect(incomeMonthlyMinorUnits(400000, 'yearly')).toBe(33333);
  });
});

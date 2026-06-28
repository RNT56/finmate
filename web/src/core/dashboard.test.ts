import { describe, it, expect } from 'vitest';
import {
  defaultOrder,
  resolveOrder,
  reorder,
  moveUp,
  moveDown,
  toggleHidden,
  isKnownCardId,
  type DashboardCardId,
} from './dashboard';

// Mirrors the Swift Domain Dashboard vectors (docs/02 §3, docs/05 §3.11):
// default order, unknown ids dropped, new defaults appended, reorder.

describe('defaultOrder', () => {
  it('is the canonical six cards in the locked order', () => {
    expect(defaultOrder).toEqual([
      'subscriptionsTotal',
      'netCashFlow',
      'savingsRate',
      'portfolioValue',
      'upcomingCharges',
      'activeServices',
    ]);
  });
});

describe('isKnownCardId', () => {
  it('recognizes known ids and rejects others', () => {
    expect(isKnownCardId('subscriptionsTotal')).toBe(true);
    expect(isKnownCardId('activeServices')).toBe(true);
    expect(isKnownCardId('bogusCard')).toBe(false);
    expect(isKnownCardId('')).toBe(false);
  });
});

describe('resolveOrder', () => {
  it('returns the full default order for null/undefined/empty', () => {
    expect(resolveOrder(null)).toEqual([...defaultOrder]);
    expect(resolveOrder(undefined)).toEqual([...defaultOrder]);
    expect(resolveOrder([])).toEqual([...defaultOrder]);
  });

  it('preserves a valid saved order verbatim', () => {
    const saved: DashboardCardId[] = [
      'savingsRate',
      'netCashFlow',
      'subscriptionsTotal',
      'activeServices',
      'upcomingCharges',
      'portfolioValue',
    ];
    expect(resolveOrder(saved)).toEqual(saved);
  });

  it('drops unknown ids from a saved order', () => {
    expect(resolveOrder(['savingsRate', 'ghostCard', 'netCashFlow'])).toEqual([
      // kept (saved order), then the remaining defaults appended in default order
      'savingsRate',
      'netCashFlow',
      'subscriptionsTotal',
      'portfolioValue',
      'upcomingCharges',
      'activeServices',
    ]);
  });

  it('appends new default cards a stale saved order is missing', () => {
    // an older layout that only knew the first three cards
    expect(resolveOrder(['savingsRate', 'subscriptionsTotal', 'netCashFlow'])).toEqual([
      'savingsRate',
      'subscriptionsTotal',
      'netCashFlow',
      'portfolioValue',
      'upcomingCharges',
      'activeServices',
    ]);
  });

  it('de-duplicates repeated ids', () => {
    expect(resolveOrder(['netCashFlow', 'netCashFlow', 'savingsRate'])).toEqual([
      'netCashFlow',
      'savingsRate',
      'subscriptionsTotal',
      'portfolioValue',
      'upcomingCharges',
      'activeServices',
    ]);
  });
});

describe('reorder', () => {
  it('moves a card from one index to another (new array, original untouched)', () => {
    const order = [...defaultOrder];
    const out = reorder(order, 0, 2);
    expect(out).toEqual([
      'netCashFlow',
      'savingsRate',
      'subscriptionsTotal',
      'portfolioValue',
      'upcomingCharges',
      'activeServices',
    ]);
    expect(order).toEqual([...defaultOrder]); // immutable
  });

  it('moves a later card earlier', () => {
    expect(reorder([...defaultOrder], 4, 1)).toEqual([
      'subscriptionsTotal',
      'upcomingCharges',
      'netCashFlow',
      'savingsRate',
      'portfolioValue',
      'activeServices',
    ]);
  });

  it('clamps out-of-range indices', () => {
    expect(reorder([...defaultOrder], -3, 99)).toEqual([
      'netCashFlow',
      'savingsRate',
      'portfolioValue',
      'upcomingCharges',
      'activeServices',
      'subscriptionsTotal',
    ]);
  });

  it('is a no-op when from === to', () => {
    expect(reorder([...defaultOrder], 2, 2)).toEqual([...defaultOrder]);
  });
});

describe('moveUp / moveDown', () => {
  it('moveUp swaps with the previous card', () => {
    expect(moveUp([...defaultOrder], 1)).toEqual([
      'netCashFlow',
      'subscriptionsTotal',
      'savingsRate',
      'portfolioValue',
      'upcomingCharges',
      'activeServices',
    ]);
  });

  it('moveUp at the top is a no-op', () => {
    expect(moveUp([...defaultOrder], 0)).toEqual([...defaultOrder]);
  });

  it('moveDown swaps with the next card', () => {
    expect(moveDown([...defaultOrder], 0)).toEqual([
      'netCashFlow',
      'subscriptionsTotal',
      'savingsRate',
      'portfolioValue',
      'upcomingCharges',
      'activeServices',
    ]);
  });

  it('moveDown at the bottom is a no-op', () => {
    const last = defaultOrder.length - 1;
    expect(moveDown([...defaultOrder], last)).toEqual([...defaultOrder]);
  });
});

describe('toggleHidden', () => {
  it('adds a visible card to the hidden set', () => {
    const out = toggleHidden(new Set(), 'savingsRate');
    expect(out.has('savingsRate')).toBe(true);
    expect(out.size).toBe(1);
  });

  it('removes a hidden card from the hidden set', () => {
    const out = toggleHidden(new Set<DashboardCardId>(['savingsRate']), 'savingsRate');
    expect(out.has('savingsRate')).toBe(false);
    expect(out.size).toBe(0);
  });

  it('returns a new set, leaving the original untouched', () => {
    const original = new Set<DashboardCardId>(['netCashFlow']);
    const out = toggleHidden(original, 'savingsRate');
    expect(original.has('savingsRate')).toBe(false);
    expect(out.has('savingsRate')).toBe(true);
  });
});

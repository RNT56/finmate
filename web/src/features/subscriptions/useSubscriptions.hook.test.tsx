// Hook-layer tests for useSubscriptions — the React store that wires the
// SubscriptionRepository protocol into the UI. Mirrors the iOS SubscriptionsStore
// tests. Uses a hand-rolled mock repository implementing SubscriptionRepository.
//
// @vitest-environment jsdom

import { describe, it, expect, beforeEach } from 'vitest';
import { renderHook, waitFor, act } from '@testing-library/react';
import { useSubscriptions } from './useSubscriptions';
import type { Subscription, SubscriptionRepository } from './types';

function makeSub(overrides: Partial<Subscription> = {}): Subscription {
  return {
    id: 'sub-1',
    name: 'Netflix',
    vendorURL: null,
    icon: null,
    amountMinor: 1299,
    currency: 'EUR',
    billingPeriod: 'monthly',
    paymentMethod: 'credit_card',
    categoryName: 'Entertainment',
    usageState: 'active',
    favorite: false,
    sortOrder: 0,
    startDate: '2026-01-01',
    ...overrides,
  };
}

/** Hand-rolled in-memory mock implementing the repository protocol. */
class MockSubscriptionRepository implements SubscriptionRepository {
  store = new Map<string, Subscription>();
  constructor(seed: Subscription[] = []) {
    seed.forEach((s) => this.store.set(s.id, { ...s }));
  }
  async all(): Promise<Subscription[]> {
    return [...this.store.values()].map((s) => ({ ...s }));
  }
  async upsert(sub: Subscription): Promise<void> {
    this.store.set(sub.id, { ...sub });
  }
  async remove(id: string): Promise<void> {
    this.store.delete(id);
  }
}

/** A repo whose reads reject, to drive the error path. */
class ThrowingSubscriptionRepository implements SubscriptionRepository {
  async all(): Promise<Subscription[]> {
    throw new Error('subs boom');
  }
  async upsert(): Promise<void> {}
  async remove(): Promise<void> {}
}

describe('useSubscriptions (hook)', () => {
  let repo: MockSubscriptionRepository;

  beforeEach(() => {
    repo = new MockSubscriptionRepository([
      makeSub({ id: 'sub-1', amountMinor: 1299 }),
      makeSub({ id: 'sub-2', name: 'Spotify', amountMinor: 1099 }),
    ]);
  });

  it('loads from the repository (happy path)', async () => {
    const { result } = renderHook(() => useSubscriptions(repo));
    expect(result.current.loading).toBe(true);
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.subscriptions).toHaveLength(2);
    expect(result.current.error).toBeNull();
    // 1299 + 1099 = 2398 cents monthly-equivalent.
    expect(result.current.monthlyTotalMinor('EUR')).toBe(2398);
  });

  it('loads empty (no items, no NaN total)', async () => {
    const empty = new MockSubscriptionRepository([]);
    const { result } = renderHook(() => useSubscriptions(empty));
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.subscriptions).toHaveLength(0);
    expect(result.current.monthlyTotalMinor('EUR')).toBe(0);
  });

  it('add() upserts then reloads', async () => {
    const { result } = renderHook(() => useSubscriptions(repo));
    await waitFor(() => expect(result.current.loading).toBe(false));
    await act(async () => {
      await result.current.add(makeSub({ id: 'sub-3', amountMinor: 500 }));
    });
    await waitFor(() => expect(result.current.subscriptions).toHaveLength(3));
    expect(result.current.monthlyTotalMinor('EUR')).toBe(2898);
  });

  it('remove() deletes then reloads', async () => {
    const { result } = renderHook(() => useSubscriptions(repo));
    await waitFor(() => expect(result.current.loading).toBe(false));
    await act(async () => {
      await result.current.remove('sub-2');
    });
    await waitFor(() => expect(result.current.subscriptions).toHaveLength(1));
    expect(result.current.monthlyTotalMinor('EUR')).toBe(1299);
  });

  it('captures a load error into error state', async () => {
    const { result } = renderHook(() =>
      useSubscriptions(new ThrowingSubscriptionRepository())
    );
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.error).toBe('subs boom');
    expect(result.current.subscriptions).toHaveLength(0);
  });
});

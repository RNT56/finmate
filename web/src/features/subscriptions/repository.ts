// InMemorySubscriptionRepository — mirrors the iOS InMemorySubscriptionRepository
// + SampleData (App/Sources/Subscriptions.swift). Lets the app build/preview with
// no live Supabase backend. A Supabase-backed implementation swaps in behind the
// same `SubscriptionRepository` seam.

import type { Subscription, SubscriptionRepository } from './types';

export const sampleSubscriptions: Subscription[] = [
  {
    id: 'sub-netflix',
    name: 'Netflix',
    vendorURL: 'netflix.com',
    icon: 'play',
    amountMinor: 1299, // €12.99
    currency: 'EUR',
    billingPeriod: 'monthly',
    paymentMethod: 'credit_card',
    categoryName: 'Streaming',
    usageState: 'active',
    favorite: false,
    sortOrder: 0,
    startDate: '2026-01-04',
  },
  {
    id: 'sub-spotify',
    name: 'Spotify',
    vendorURL: 'spotify.com',
    icon: 'music',
    amountMinor: 1099, // €10.99
    currency: 'EUR',
    billingPeriod: 'monthly',
    paymentMethod: 'paypal',
    categoryName: 'Music',
    usageState: 'active',
    favorite: false,
    sortOrder: 1,
    startDate: '2026-02-12',
  },
  {
    id: 'sub-icloud',
    name: 'iCloud+',
    vendorURL: 'icloud.com',
    icon: 'cloud',
    amountMinor: 2999, // €29.99 / yr
    currency: 'EUR',
    billingPeriod: 'yearly',
    paymentMethod: 'apple_pay',
    categoryName: 'Productivity',
    usageState: 'rarely',
    favorite: false,
    sortOrder: 2,
    startDate: '2025-06-20',
  },
];

export class InMemorySubscriptionRepository implements SubscriptionRepository {
  private store: Map<string, Subscription>;

  constructor(seed: Subscription[] = sampleSubscriptions) {
    this.store = new Map(seed.map((s) => [s.id, { ...s }]));
  }

  async all(): Promise<Subscription[]> {
    return [...this.store.values()].sort((a, b) => a.sortOrder - b.sortOrder);
  }

  async upsert(sub: Subscription): Promise<void> {
    this.store.set(sub.id, { ...sub });
  }

  async remove(id: string): Promise<void> {
    this.store.delete(id);
  }
}

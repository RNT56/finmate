import { describe, it, expect } from 'vitest';
import { subscriptionFromRow, subscriptionToRow } from './supabaseRepository';
import type { SubscriptionRow } from '../../types/database';
import type { Subscription } from './types';

const row: SubscriptionRow = {
  id: 'sub-netflix',
  user_id: 'user-1',
  name: 'Netflix',
  vendor_url: 'netflix.com',
  icon: 'play',
  amount_minor: 1299,
  currency: 'EUR',
  billing_period: 'monthly',
  payment_method: 'credit_card',
  category_id: 'cat-streaming',
  usage_state: 'active',
  start_date: '2026-01-04',
  end_date: null,
  auto_renew: true,
  favorite: false,
  reminders_enabled: true,
  sort_order: 0,
  notes: null,
  created_at: '2026-01-04T00:00:00Z',
  updated_at: '2026-01-04T00:00:00Z',
};

describe('subscription row <-> domain mappers', () => {
  it('maps a row to the camelCase Domain shape, preserving integer minor units', () => {
    const sub = subscriptionFromRow(row, 'Streaming');
    expect(sub).toEqual<Subscription>({
      id: 'sub-netflix',
      name: 'Netflix',
      vendorURL: 'netflix.com',
      icon: 'play',
      amountMinor: 1299,
      currency: 'EUR',
      billingPeriod: 'monthly',
      paymentMethod: 'credit_card',
      categoryName: 'Streaming',
      usageState: 'active',
      favorite: false,
      sortOrder: 0,
      startDate: '2026-01-04',
    });
  });

  it('defaults a null payment_method to "other"', () => {
    const sub = subscriptionFromRow({ ...row, payment_method: null });
    expect(sub.paymentMethod).toBe('other');
  });

  it('round-trips snake_case <-> camelCase for the persisted columns', () => {
    const sub = subscriptionFromRow(row, 'Streaming');
    const back = subscriptionToRow(sub);
    expect(back.amount_minor).toBe(1299);
    expect(back.vendor_url).toBe('netflix.com');
    expect(back.billing_period).toBe('monthly');
    expect(back.sort_order).toBe(0);
    expect(back.start_date).toBe('2026-01-04');
  });
});

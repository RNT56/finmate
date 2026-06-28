// SupabaseSubscriptionRepository — the live implementation of the
// `SubscriptionRepository` protocol, backed by @supabase/supabase-js against the
// RLS-protected `subscriptions` table (docs/03 §3 DataLayer; docs/05 §subscriptions).
//
// Only the public anon key ships in the client; RLS gates every row by auth.uid()
// (docs/07 §3), so reads/writes are implicitly scoped to the signed-in user — the
// repository never sets user_id on insert, it is filled server-side by the
// new-user/owner default. snake_case columns <-> camelCase Domain are translated by
// the mappers below; money stays integer minor units end-to-end (docs/05).

import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, SubscriptionRow } from '../../types/database';
import type { Subscription, SubscriptionRepository } from './types';

/** Row -> Domain (snake_case -> camelCase). `category_id` has no name on the row;
 *  the category name is resolved separately, so we fall back to an empty label. */
export function subscriptionFromRow(
  row: SubscriptionRow,
  categoryName = '',
): Subscription {
  return {
    id: row.id,
    name: row.name,
    vendorURL: row.vendor_url,
    icon: row.icon,
    amountMinor: row.amount_minor,
    currency: row.currency,
    billingPeriod: row.billing_period,
    paymentMethod: row.payment_method ?? 'other',
    categoryName,
    usageState: row.usage_state,
    favorite: row.favorite,
    sortOrder: row.sort_order,
    startDate: row.start_date,
  };
}

type SubscriptionInsert = Database['public']['Tables']['subscriptions']['Insert'];

/** Domain -> Insert/Update payload (camelCase -> snake_case). Omits `user_id`
 *  (RLS owner default), `category_id` (name<->id resolution is out of scope here),
 *  and the server-managed timestamps. */
export function subscriptionToRow(sub: Subscription): SubscriptionInsert {
  return {
    id: sub.id,
    name: sub.name,
    vendor_url: sub.vendorURL,
    icon: sub.icon,
    amount_minor: sub.amountMinor,
    currency: sub.currency,
    billing_period: sub.billingPeriod,
    payment_method: sub.paymentMethod,
    usage_state: sub.usageState,
    favorite: sub.favorite,
    sort_order: sub.sortOrder,
    start_date: sub.startDate,
  };
}

export class SupabaseSubscriptionRepository implements SubscriptionRepository {
  constructor(private readonly client: SupabaseClient<Database>) {}

  async all(): Promise<Subscription[]> {
    const { data, error } = await this.client
      .from('subscriptions')
      .select('*')
      .order('sort_order', { ascending: true });
    if (error) throw error;
    return (data ?? []).map((row) => subscriptionFromRow(row));
  }

  async upsert(sub: Subscription): Promise<void> {
    const { error } = await this.client
      .from('subscriptions')
      .upsert(subscriptionToRow(sub), { onConflict: 'id' });
    if (error) throw error;
  }

  async remove(id: string): Promise<void> {
    const { error } = await this.client.from('subscriptions').delete().eq('id', id);
    if (error) throw error;
  }
}

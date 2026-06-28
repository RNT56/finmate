// SupabasePreferencesRepository — live implementation of the `PreferencesRepository`
// protocol over the RLS-protected `user_preferences` per-user singleton table
// (docs/03 §3; docs/05 §3.10). RLS scopes the single row to auth.uid() (docs/07 §3).
//
// The Domain `PreferencesRepository` protocol is SYNCHRONOUS (load()/save()) because
// the iOS/web Settings stores read it eagerly. Supabase I/O is async, so this repo
// keeps an in-memory cache that load()/save() serve synchronously, and writes through
// to Postgres on a best-effort fire-and-forget basis. Call refresh() once after sign-in
// to hydrate the cache from the server; until then defaults (or the last cached value)
// are returned — the UI never blocks on the network.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, UserPreferencesRow } from '../../types/database';
import {
  type PreferencesRepository,
  type UserPreferences,
  defaultPreferences,
  normalizePreferences,
} from '../../core/preferences';

/** Row -> Domain (snake_case -> camelCase). */
export function preferencesFromRow(row: UserPreferencesRow): UserPreferences {
  return normalizePreferences({
    appearance: row.appearance,
    defaultCurrency: row.default_currency,
    biometricLockEnabled: row.biometric_lock_enabled,
    paymentRemindersEnabled: row.payment_reminders_enabled,
    paydayRemindersEnabled: row.payday_reminders_enabled,
    reminderLeadTimeDays: row.reminder_lead_time_days,
  });
}

type UserPreferencesInsert = Database['public']['Tables']['user_preferences']['Insert'];

/** Domain -> Insert/Update payload. Omits `user_id` (RLS owner default), the
 *  server-managed timestamps, and the iOS-only biometric timeout. */
export function preferencesToRow(prefs: UserPreferences): UserPreferencesInsert {
  return {
    appearance: prefs.appearance,
    default_currency: prefs.defaultCurrency,
    biometric_lock_enabled: prefs.biometricLockEnabled,
    payment_reminders_enabled: prefs.paymentRemindersEnabled,
    payday_reminders_enabled: prefs.paydayRemindersEnabled,
    reminder_lead_time_days: prefs.reminderLeadTimeDays,
  };
}

export class SupabasePreferencesRepository implements PreferencesRepository {
  private cache: UserPreferences = defaultPreferences;

  constructor(private readonly client: SupabaseClient<Database>) {}

  /** Hydrate the cache from the user's single row; safe to call after sign-in. */
  async refresh(): Promise<UserPreferences> {
    const { data, error } = await this.client
      .from('user_preferences')
      .select('*')
      .limit(1)
      .maybeSingle();
    if (error) throw error;
    this.cache = data ? preferencesFromRow(data) : defaultPreferences;
    return this.cache;
  }

  load(): UserPreferences {
    return this.cache;
  }

  save(prefs: UserPreferences): void {
    const next = normalizePreferences(prefs);
    this.cache = next;
    // Fire-and-forget write-through; the UI does not block on the network.
    void this.persist(next);
  }

  /** Upsert the user's single preferences row. */
  private async persist(prefs: UserPreferences): Promise<void> {
    const { error } = await this.client
      .from('user_preferences')
      .upsert(preferencesToRow(prefs), { onConflict: 'user_id' });
    if (error) {
      // Best-effort: surface to the console but never throw on the UI path.
      console.error('Failed to persist user preferences', error);
    }
  }
}

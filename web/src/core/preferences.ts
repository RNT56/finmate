// TS mirror of the Swift Domain UserPreferences (docs/02 §12, docs/05 §3.10).
// Settings surface: appearance, default display currency, reminder toggles +
// lead-time, biometric lock (iOS-only flag), with safe defaults and a clamped
// reminder lead-time. Implement once per language; iOS and web agree on shape.

import type { CurrencyCode } from './currency';

/** App-wide appearance preference. `system` follows prefers-color-scheme. */
export type Appearance = 'system' | 'light' | 'dark';

/** Reminder lead-time bounds (days before a charge/payday). */
export const MIN_REMINDER_LEAD_TIME_DAYS = 0;
export const MAX_REMINDER_LEAD_TIME_DAYS = 30;
export const DEFAULT_REMINDER_LEAD_TIME_DAYS = 2;

/** Canonical user preferences (docs/05 §3.10 `user_preferences`). */
export interface UserPreferences {
  appearance: Appearance;
  defaultCurrency: CurrencyCode;
  /** iOS-only; persisted for parity but the web client cannot honor it. */
  biometricLockEnabled: boolean;
  paymentRemindersEnabled: boolean;
  paydayRemindersEnabled: boolean;
  reminderLeadTimeDays: number;
}

/** The defaults a fresh account starts with. */
export const defaultPreferences: UserPreferences = {
  appearance: 'system',
  defaultCurrency: 'EUR',
  biometricLockEnabled: false,
  paymentRemindersEnabled: true,
  paydayRemindersEnabled: true,
  reminderLeadTimeDays: DEFAULT_REMINDER_LEAD_TIME_DAYS,
};

/** Clamp + integer-coerce a reminder lead-time into the allowed 0…30 range. */
export function clampReminderLeadTimeDays(days: number): number {
  if (!Number.isFinite(days)) return DEFAULT_REMINDER_LEAD_TIME_DAYS;
  const whole = Math.round(days);
  if (whole < MIN_REMINDER_LEAD_TIME_DAYS) return MIN_REMINDER_LEAD_TIME_DAYS;
  if (whole > MAX_REMINDER_LEAD_TIME_DAYS) return MAX_REMINDER_LEAD_TIME_DAYS;
  return whole;
}

/**
 * Normalize an arbitrary (possibly persisted / partial) object into a valid
 * UserPreferences, filling gaps with defaults and clamping the lead-time.
 */
export function normalizePreferences(raw: Partial<UserPreferences> | null | undefined): UserPreferences {
  const appearance: Appearance =
    raw?.appearance === 'light' || raw?.appearance === 'dark' || raw?.appearance === 'system'
      ? raw.appearance
      : defaultPreferences.appearance;
  const defaultCurrency: CurrencyCode =
    raw?.defaultCurrency === 'EUR' || raw?.defaultCurrency === 'USD' || raw?.defaultCurrency === 'BTC'
      ? raw.defaultCurrency
      : defaultPreferences.defaultCurrency;
  return {
    appearance,
    defaultCurrency,
    biometricLockEnabled: raw?.biometricLockEnabled ?? defaultPreferences.biometricLockEnabled,
    paymentRemindersEnabled: raw?.paymentRemindersEnabled ?? defaultPreferences.paymentRemindersEnabled,
    paydayRemindersEnabled: raw?.paydayRemindersEnabled ?? defaultPreferences.paydayRemindersEnabled,
    reminderLeadTimeDays: clampReminderLeadTimeDays(
      raw?.reminderLeadTimeDays ?? defaultPreferences.reminderLeadTimeDays,
    ),
  };
}

// MARK: - Repository (mirrors the Swift PreferencesRepository protocol)

/** Abstracts preference persistence; stores call this, never storage directly. */
export interface PreferencesRepository {
  load(): UserPreferences;
  save(prefs: UserPreferences): void;
}

/** In-memory implementation (parity with the Swift in-memory repo; for tests). */
export class InMemoryPreferencesRepository implements PreferencesRepository {
  private prefs: UserPreferences;

  constructor(initial: UserPreferences = defaultPreferences) {
    this.prefs = normalizePreferences(initial);
  }

  load(): UserPreferences {
    return this.prefs;
  }

  save(prefs: UserPreferences): void {
    this.prefs = normalizePreferences(prefs);
  }
}

const STORAGE_KEY = 'finmate.preferences.v1';

/** localStorage-backed repository for the web demo (no Supabase wired yet). */
export class LocalStoragePreferencesRepository implements PreferencesRepository {
  load(): UserPreferences {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return defaultPreferences;
      return normalizePreferences(JSON.parse(raw) as Partial<UserPreferences>);
    } catch {
      return defaultPreferences;
    }
  }

  save(prefs: UserPreferences): void {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(normalizePreferences(prefs)));
    } catch {
      // localStorage unavailable (private mode / SSR) — best effort only.
    }
  }
}

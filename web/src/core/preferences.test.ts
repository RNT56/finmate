import { describe, it, expect } from 'vitest';
import {
  defaultPreferences,
  clampReminderLeadTimeDays,
  normalizePreferences,
  InMemoryPreferencesRepository,
  MIN_REMINDER_LEAD_TIME_DAYS,
  MAX_REMINDER_LEAD_TIME_DAYS,
  DEFAULT_REMINDER_LEAD_TIME_DAYS,
} from './preferences';

// Mirrors the Swift UserPreferences defaults + lead-time clamp (docs/05 §3.10).

describe('defaultPreferences', () => {
  it('matches the canonical defaults: system, EUR, false, true, true, 2', () => {
    expect(defaultPreferences.appearance).toBe('system');
    expect(defaultPreferences.defaultCurrency).toBe('EUR');
    expect(defaultPreferences.biometricLockEnabled).toBe(false);
    expect(defaultPreferences.paymentRemindersEnabled).toBe(true);
    expect(defaultPreferences.paydayRemindersEnabled).toBe(true);
    expect(defaultPreferences.reminderLeadTimeDays).toBe(2);
    expect(DEFAULT_REMINDER_LEAD_TIME_DAYS).toBe(2);
  });
});

describe('clampReminderLeadTimeDays', () => {
  it('clamps below the minimum to 0', () => {
    expect(clampReminderLeadTimeDays(-5)).toBe(MIN_REMINDER_LEAD_TIME_DAYS);
    expect(clampReminderLeadTimeDays(-1)).toBe(0);
  });

  it('clamps above the maximum to 30', () => {
    expect(clampReminderLeadTimeDays(31)).toBe(MAX_REMINDER_LEAD_TIME_DAYS);
    expect(clampReminderLeadTimeDays(1000)).toBe(30);
  });

  it('passes through in-range values and rounds fractions', () => {
    expect(clampReminderLeadTimeDays(0)).toBe(0);
    expect(clampReminderLeadTimeDays(2)).toBe(2);
    expect(clampReminderLeadTimeDays(30)).toBe(30);
    expect(clampReminderLeadTimeDays(2.4)).toBe(2);
    expect(clampReminderLeadTimeDays(2.6)).toBe(3);
  });

  it('falls back to the default for non-finite input', () => {
    expect(clampReminderLeadTimeDays(NaN)).toBe(DEFAULT_REMINDER_LEAD_TIME_DAYS);
    expect(clampReminderLeadTimeDays(Infinity)).toBe(DEFAULT_REMINDER_LEAD_TIME_DAYS);
  });
});

describe('normalizePreferences', () => {
  it('fills missing fields with defaults', () => {
    expect(normalizePreferences(null)).toEqual(defaultPreferences);
    expect(normalizePreferences({})).toEqual(defaultPreferences);
  });

  it('rejects invalid enums and clamps the lead-time', () => {
    const out = normalizePreferences({
      // @ts-expect-error invalid on purpose
      appearance: 'neon',
      // @ts-expect-error invalid on purpose
      defaultCurrency: 'GBP',
      reminderLeadTimeDays: 99,
    });
    expect(out.appearance).toBe('system');
    expect(out.defaultCurrency).toBe('EUR');
    expect(out.reminderLeadTimeDays).toBe(30);
  });

  it('preserves valid values', () => {
    const out = normalizePreferences({
      appearance: 'dark',
      defaultCurrency: 'BTC',
      biometricLockEnabled: true,
      paymentRemindersEnabled: false,
      paydayRemindersEnabled: false,
      reminderLeadTimeDays: 7,
    });
    expect(out).toEqual({
      appearance: 'dark',
      defaultCurrency: 'BTC',
      biometricLockEnabled: true,
      paymentRemindersEnabled: false,
      paydayRemindersEnabled: false,
      reminderLeadTimeDays: 7,
    });
  });
});

describe('InMemoryPreferencesRepository', () => {
  it('round-trips save/load and clamps on save', () => {
    const repo = new InMemoryPreferencesRepository();
    expect(repo.load()).toEqual(defaultPreferences);
    repo.save({ ...defaultPreferences, appearance: 'light', reminderLeadTimeDays: 50 });
    expect(repo.load().appearance).toBe('light');
    expect(repo.load().reminderLeadTimeDays).toBe(30);
  });
});

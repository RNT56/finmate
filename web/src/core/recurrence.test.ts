// Recurrence engine vectors — IDENTICAL to the Swift Domain suite (docs/13 §11).
// All dates are midnight UTC; reference = 2026-06-28 per the docs test table.

import { describe, expect, it } from 'vitest';
import {
  clampDay,
  daysInMonth,
  events,
  fixedExpenseDueDates,
  incomePaydays,
  reminderDates,
  subscriptionCharges,
  utcDate,
  type CalendarEvent,
} from './recurrence';

const REFERENCE = utcDate(2026, 6, 28);

/** Render a list of Dates as ISO yyyy-mm-dd for stable assertions. */
function iso(dates: Date[]): string[] {
  return dates.map((d) => d.toISOString().slice(0, 10));
}

describe('day-of-month clamping helpers', () => {
  it('daysInMonth is leap-year aware', () => {
    expect(daysInMonth(2026, 2)).toBe(28);
    expect(daysInMonth(2024, 2)).toBe(29);
    expect(daysInMonth(2026, 4)).toBe(30);
    expect(daysInMonth(2026, 1)).toBe(31);
  });

  it('clampDay clamps anchor to month length', () => {
    expect(clampDay(2026, 2, 31)).toBe(28);
    expect(clampDay(2024, 2, 31)).toBe(29);
    expect(clampDay(2026, 4, 31)).toBe(30);
    expect(clampDay(2026, 1, 31)).toBe(31);
  });
});

describe('subscriptionCharges (docs/13 §11.1)', () => {
  // T11.a — monthly sub started 2026-01-15, window June 2026 → one charge 06-15.
  it('calendar_monthlyDayOfMonth', () => {
    const charges = subscriptionCharges(
      utcDate(2026, 1, 15),
      'monthly',
      utcDate(2026, 6, 1),
      utcDate(2026, 6, 30),
    );
    expect(iso(charges)).toEqual(['2026-06-15']);
  });

  // T11.b — yearly sub started 2025-03-10, year 2026 → one charge 2026-03-10.
  it('calendar_yearlyAnniversaryOnce', () => {
    const charges = subscriptionCharges(
      utcDate(2025, 3, 10),
      'yearly',
      utcDate(2026, 1, 1),
      utcDate(2026, 12, 31),
    );
    expect(iso(charges)).toEqual(['2026-03-10']);
  });

  // T11.c — sub started 2026-01-31, window Feb 2026 → clamps to 2026-02-28.
  it('calendar_clampJan31ToFeb28', () => {
    const charges = subscriptionCharges(
      utcDate(2026, 1, 31),
      'monthly',
      utcDate(2026, 2, 1),
      utcDate(2026, 2, 28),
    );
    expect(iso(charges)).toEqual(['2026-02-28']);
  });

  // T11.d — sub started 2024-01-31, window Feb 2024 (leap) → clamps to 2024-02-29.
  it('calendar_clampLeapFeb29', () => {
    const charges = subscriptionCharges(
      utcDate(2024, 1, 31),
      'monthly',
      utcDate(2024, 2, 1),
      utcDate(2024, 2, 29),
    );
    expect(iso(charges)).toEqual(['2024-02-29']);
  });

  // The 31st anchor does not drift: Jan→31, Feb→28, Mar→31, Apr→30.
  it('monthly 31st anchor clamps per-month without drifting', () => {
    const charges = subscriptionCharges(
      utcDate(2026, 1, 31),
      'monthly',
      utcDate(2026, 1, 1),
      utcDate(2026, 4, 30),
    );
    expect(iso(charges)).toEqual(['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30']);
  });

  // T11.g — weekly sub started 2026-06-01, window June.
  it('calendar_weeklySteps', () => {
    const charges = subscriptionCharges(
      utcDate(2026, 6, 1),
      'weekly',
      utcDate(2026, 6, 1),
      utcDate(2026, 6, 30),
    );
    expect(iso(charges)).toEqual([
      '2026-06-01',
      '2026-06-08',
      '2026-06-15',
      '2026-06-22',
      '2026-06-29',
    ]);
  });

  it('returns empty when the start date is after the window', () => {
    const charges = subscriptionCharges(
      utcDate(2026, 8, 1),
      'monthly',
      utcDate(2026, 6, 1),
      utcDate(2026, 6, 30),
    );
    expect(charges).toEqual([]);
  });

  it('window filter excludes out-of-range occurrences', () => {
    // Monthly from Jan 10, but only the March window is requested.
    const charges = subscriptionCharges(
      utcDate(2026, 1, 10),
      'monthly',
      utcDate(2026, 3, 1),
      utcDate(2026, 3, 31),
    );
    expect(iso(charges)).toEqual(['2026-03-10']);
  });
});

describe('incomePaydays (docs/13 §11.2)', () => {
  // Monthly income anchored on the 15th → the 15th of each month in-window.
  it('monthly income on the 15th lands on the 15th each month', () => {
    const days = incomePaydays(
      'monthly',
      utcDate(2026, 1, 15),
      REFERENCE,
      utcDate(2026, 1, 1),
      utcDate(2026, 4, 30),
    );
    expect(iso(days)).toEqual(['2026-01-15', '2026-02-15', '2026-03-15', '2026-04-15']);
  });

  // T11.h — one_time income only appears if in-window.
  it('income_oneTimeSingleMarker (in window)', () => {
    const days = incomePaydays(
      'one_time',
      utcDate(2026, 6, 30),
      REFERENCE,
      utcDate(2026, 6, 1),
      utcDate(2026, 6, 30),
    );
    expect(iso(days)).toEqual(['2026-06-30']);
  });

  it('one_time income excluded when out of window', () => {
    const days = incomePaydays(
      'one_time',
      utcDate(2026, 7, 30),
      REFERENCE,
      utcDate(2026, 6, 1),
      utcDate(2026, 6, 30),
    );
    expect(days).toEqual([]);
  });

  it('one_time income with no anchor yields nothing', () => {
    const days = incomePaydays(
      'one_time',
      null,
      REFERENCE,
      utcDate(2026, 6, 1),
      utcDate(2026, 6, 30),
    );
    expect(days).toEqual([]);
  });

  it('weekly income steps every 7 days within window', () => {
    const days = incomePaydays(
      'weekly',
      utcDate(2026, 6, 5),
      REFERENCE,
      utcDate(2026, 6, 1),
      utcDate(2026, 6, 30),
    );
    expect(iso(days)).toEqual(['2026-06-05', '2026-06-12', '2026-06-19', '2026-06-26']);
  });
});

describe('fixedExpenseDueDates (docs/13 §11)', () => {
  it('monthly due date recurs on its anchor day, clamped', () => {
    const days = fixedExpenseDueDates(
      utcDate(2026, 1, 31),
      'monthly',
      utcDate(2026, 2, 1),
      utcDate(2026, 3, 31),
    );
    expect(iso(days)).toEqual(['2026-02-28', '2026-03-31']);
  });
});

describe('events aggregation (docs/13 §11.4)', () => {
  it('sorts by date then kind (income < subscription < fixedExpense)', () => {
    const all = events(
      utcDate(2026, 6, 1),
      utcDate(2026, 6, 30),
      [{ title: 'Salary', amountMinor: 320000, currency: 'EUR', frequency: 'monthly', anchor: utcDate(2026, 6, 15) }],
      [{ title: 'Netflix', amountMinor: 1299, currency: 'EUR', billingPeriod: 'monthly', startDate: utcDate(2026, 6, 15) }],
      [{ title: 'Rent', amountMinor: 110000, currency: 'EUR', frequency: 'monthly', dueDate: utcDate(2026, 6, 1) }],
      REFERENCE,
    );
    expect(all.map((e) => `${e.date.toISOString().slice(0, 10)}/${e.kind}`)).toEqual([
      '2026-06-01/fixedExpense',
      '2026-06-15/income',
      '2026-06-15/subscription',
    ]);
  });

  it('skips fixed expenses with no due date', () => {
    const all = events(
      utcDate(2026, 6, 1),
      utcDate(2026, 6, 30),
      [],
      [],
      [{ title: 'Mystery', amountMinor: 100, currency: 'EUR', frequency: 'monthly', dueDate: null }],
      REFERENCE,
    );
    expect(all).toEqual([]);
  });
});

describe('reminderDates (docs/13 §11.5)', () => {
  const evt = (date: Date): CalendarEvent => ({
    date,
    kind: 'subscription',
    title: 'Spotify',
    amountMinor: 1099,
    currency: 'EUR',
  });

  // T11.e — lead time of 2 days shifts the fire date back two days.
  it('reminder_leadTimeTwoDays', () => {
    const [reminder] = reminderDates([evt(utcDate(2026, 7, 1))], 2);
    expect(reminder.fireDate.toISOString().slice(0, 10)).toBe('2026-06-29');
  });

  it('leadDays = 0 fires on the event day', () => {
    const [reminder] = reminderDates([evt(utcDate(2026, 7, 1))], 0);
    expect(reminder.fireDate.toISOString().slice(0, 10)).toBe('2026-07-01');
  });

  // T11.f — a past fire date is the caller's filter; the pure transform still
  // returns the (past) fire date so the caller can compare it against now.
  it('reminder_pastNotScheduled (pure transform returns the past date)', () => {
    const [reminder] = reminderDates([evt(utcDate(2026, 6, 20))], 2);
    expect(reminder.fireDate.toISOString().slice(0, 10)).toBe('2026-06-18');
    // Caller schedules only when fireDate >= now (2026-06-28): this one is past.
    expect(reminder.fireDate.getTime() < REFERENCE.getTime()).toBe(true);
  });
});

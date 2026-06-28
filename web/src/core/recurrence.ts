// TS mirror of the Domain payday-calendar & recurrence engine (docs/13 §11).
// PURE & DETERMINISTIC: every entry point takes an explicit reference Date and a
// fixed window — never calls Date.now() internally, so the test vectors are stable.
//
// Date math is done in UTC to avoid DST / local-offset drift. Month and year
// stepping CLAMP the day-of-month to the target month length (a charge anchored
// on the 31st lands on Feb 28/29) using explicit clamping — never relying on JS
// Date's silent month overflow (new Date(2026, 1, 31) → Mar 03).

import type { CurrencyCode } from './currency';
import type { BillingPeriod, IncomeFrequency } from './normalization';

/** A single dated money event projected into the calendar (docs/13 §11). */
export interface CalendarEvent {
  /** Midnight-UTC date the event lands on. */
  date: Date;
  kind: EventKind;
  title: string;
  /** Already-computed minor units (no money rounding happens here). */
  amountMinor: number;
  currency: CurrencyCode;
}

export type EventKind = 'income' | 'subscription' | 'fixedExpense';

/** A reminder: the source event plus the (pure) fire date (docs/13 §11.5). */
export interface ReminderDate {
  event: CalendarEvent;
  fireDate: Date;
}

/** Half-open kind sort order so `events()` is deterministic (date then kind). */
const KIND_ORDER: Record<EventKind, number> = {
  income: 0,
  subscription: 1,
  fixedExpense: 2,
};

// ---------------------------------------------------------------------------
// UTC date helpers (the "fixed Gregorian/UTC calendar")
// ---------------------------------------------------------------------------

/** Midnight-UTC instant for a y/m/d triple (month is 1-based here for clarity). */
export function utcDate(year: number, month1: number, day: number): Date {
  return new Date(Date.UTC(year, month1 - 1, day));
}

/** Strip any time component, normalizing to midnight UTC. */
export function startOfDayUTC(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

/** Days in a (1-based) month, leap-year aware. */
export function daysInMonth(year: number, month1: number): number {
  // Day 0 of the next month is the last day of this month.
  return new Date(Date.UTC(year, month1, 0)).getUTCDate();
}

/** Clamp a day-of-month anchor to the target month's length (docs/13 §11.3). */
export function clampDay(year: number, month1: number, anchorDay: number): number {
  return Math.min(anchorDay, daysInMonth(year, month1));
}

function addDaysUTC(date: Date, days: number): Date {
  const d = startOfDayUTC(date);
  return new Date(d.getTime() + days * 86_400_000);
}

/**
 * Advance by whole months WITHOUT drifting the anchor: the rendered occurrence
 * clamps to the short month, but stepping is computed from the original anchor
 * day so March still uses the 31st even after Feb clamped to the 28th.
 */
function addMonthsFromAnchor(year: number, month0: number, anchorDay: number, months: number): Date {
  const total = month0 + months;
  const targetYear = year + Math.floor(total / 12);
  const targetMonth0 = ((total % 12) + 12) % 12;
  const day = clampDay(targetYear, targetMonth0 + 1, anchorDay);
  return new Date(Date.UTC(targetYear, targetMonth0, day));
}

function isOnOrAfter(a: Date, b: Date): boolean {
  return a.getTime() >= b.getTime();
}

function isOnOrBefore(a: Date, b: Date): boolean {
  return a.getTime() <= b.getTime();
}

// ---------------------------------------------------------------------------
// Subscription charge projection (docs/13 §11.1)
// ---------------------------------------------------------------------------

/**
 * Charge dates for a subscription stepping from `startDate` by `billingPeriod`
 * across [windowStart, windowEnd] (inclusive). Month/quarter/year steps clamp
 * the day-of-month; weekly steps every 7 days. Returns ascending midnight-UTC dates.
 */
export function subscriptionCharges(
  startDate: Date,
  billingPeriod: BillingPeriod,
  windowStart: Date,
  windowEnd: Date,
): Date[] {
  const start = startOfDayUTC(startDate);
  const end = startOfDayUTC(windowEnd);
  const from = startOfDayUTC(windowStart);
  if (start.getTime() > end.getTime()) return [];

  const out: Date[] = [];
  const anchorDay = start.getUTCDate();
  const anchorYear = start.getUTCFullYear();
  const anchorMonth0 = start.getUTCMonth();

  if (billingPeriod === 'weekly') {
    let d = start;
    while (isOnOrBefore(d, end)) {
      if (isOnOrAfter(d, from)) out.push(d);
      d = addDaysUTC(d, 7);
    }
    return out;
  }

  const monthStep = billingPeriod === 'monthly' ? 1 : billingPeriod === 'quarterly' ? 3 : 12;
  let i = 0;
  // Guard against runaway loops: a year window can hold at most ~366 monthly steps.
  while (i < 100_000) {
    const d = addMonthsFromAnchor(anchorYear, anchorMonth0, anchorDay, monthStep * i);
    if (d.getTime() > end.getTime()) break;
    if (isOnOrAfter(d, from)) out.push(d);
    i += 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Income paydays (docs/13 §11.2)
// ---------------------------------------------------------------------------

/**
 * Income payday dates within [windowStart, windowEnd].
 * - one_time: a single marker at `anchor` if it falls in the window.
 * - weekly/monthly/yearly: step from `anchor` (the nextPayment date, or the
 *   reference date when nextPayment is null), same clamping rules.
 * `anchor` may be null only for one_time with no scheduled payment → no markers.
 */
export function incomePaydays(
  frequency: IncomeFrequency,
  anchor: Date | null,
  reference: Date,
  windowStart: Date,
  windowEnd: Date,
): Date[] {
  if (frequency === 'one_time') {
    if (anchor === null) return [];
    const a = startOfDayUTC(anchor);
    return inWindow(a, windowStart, windowEnd) ? [a] : [];
  }

  const base = startOfDayUTC(anchor ?? reference);
  const from = startOfDayUTC(windowStart);
  const end = startOfDayUTC(windowEnd);
  const out: Date[] = [];

  if (frequency === 'weekly') {
    // Roll the base forward/back so we don't miss occurrences before `base`
    // that still fall in the window; simplest: walk from base across the window.
    let d = base;
    // Step backward to at most one period before the window start.
    while (d.getTime() > from.getTime()) d = addDaysUTC(d, -7);
    while (isOnOrBefore(d, end)) {
      if (isOnOrAfter(d, from)) out.push(d);
      d = addDaysUTC(d, 7);
    }
    return out;
  }

  const monthStep = frequency === 'monthly' ? 1 : 12;
  const anchorDay = base.getUTCDate();
  const anchorYear = base.getUTCFullYear();
  const anchorMonth0 = base.getUTCMonth();
  // Walk from a few steps before the base to cover windows preceding the anchor.
  for (let i = -1200; i < 1200; i += 1) {
    const d = addMonthsFromAnchor(anchorYear, anchorMonth0, anchorDay, monthStep * i);
    if (d.getTime() > end.getTime()) break;
    if (isOnOrAfter(d, from)) out.push(d);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Fixed-expense due dates (docs/13 §11) — same shape as subscriptions
// ---------------------------------------------------------------------------

/** Due dates for a fixed expense stepping from `dueDate` by `frequency`. */
export function fixedExpenseDueDates(
  dueDate: Date,
  frequency: BillingPeriod,
  windowStart: Date,
  windowEnd: Date,
): Date[] {
  return subscriptionCharges(dueDate, frequency, windowStart, windowEnd);
}

function inWindow(d: Date, windowStart: Date, windowEnd: Date): boolean {
  const s = startOfDayUTC(windowStart);
  const e = startOfDayUTC(windowEnd);
  return d.getTime() >= s.getTime() && d.getTime() <= e.getTime();
}

// ---------------------------------------------------------------------------
// Aggregate events (docs/13 §11.4)
// ---------------------------------------------------------------------------

export interface IncomeEntity {
  title: string;
  amountMinor: number;
  currency: CurrencyCode;
  frequency: IncomeFrequency;
  /** nextPayment anchor, or null. */
  anchor: Date | null;
}

export interface SubscriptionEntity {
  title: string;
  amountMinor: number;
  currency: CurrencyCode;
  billingPeriod: BillingPeriod;
  startDate: Date;
}

export interface FixedExpenseEntity {
  title: string;
  amountMinor: number;
  currency: CurrencyCode;
  frequency: BillingPeriod;
  dueDate: Date | null;
}

/**
 * Project all entities into the window, returning events sorted by date then
 * kind (income < subscription < fixedExpense). Pure; `reference` only seeds
 * income anchors that have no nextPayment.
 */
export function events(
  windowStart: Date,
  windowEnd: Date,
  incomes: IncomeEntity[],
  subscriptions: SubscriptionEntity[],
  fixedExpenses: FixedExpenseEntity[],
  reference: Date,
): CalendarEvent[] {
  const out: CalendarEvent[] = [];

  for (const inc of incomes) {
    for (const date of incomePaydays(inc.frequency, inc.anchor, reference, windowStart, windowEnd)) {
      out.push({ date, kind: 'income', title: inc.title, amountMinor: inc.amountMinor, currency: inc.currency });
    }
  }

  for (const sub of subscriptions) {
    for (const date of subscriptionCharges(sub.startDate, sub.billingPeriod, windowStart, windowEnd)) {
      out.push({ date, kind: 'subscription', title: sub.title, amountMinor: sub.amountMinor, currency: sub.currency });
    }
  }

  for (const fx of fixedExpenses) {
    if (fx.dueDate === null) continue;
    for (const date of fixedExpenseDueDates(fx.dueDate, fx.frequency, windowStart, windowEnd)) {
      out.push({ date, kind: 'fixedExpense', title: fx.title, amountMinor: fx.amountMinor, currency: fx.currency });
    }
  }

  out.sort((a, b) => {
    const byDate = a.date.getTime() - b.date.getTime();
    if (byDate !== 0) return byDate;
    const byKind = KIND_ORDER[a.kind] - KIND_ORDER[b.kind];
    if (byKind !== 0) return byKind;
    return a.title.localeCompare(b.title);
  });

  return out;
}

// ---------------------------------------------------------------------------
// Lead-time reminders (docs/13 §11.5)
// ---------------------------------------------------------------------------

/**
 * Pure reminder fire dates: fireDate = startOfDay(event.date) − leadTimeDays.
 * Scheduling/authorization (and the `fireDate >= now` past-filter) is the
 * caller's concern — this stays a pure transform so it is deterministic.
 */
export function reminderDates(events: CalendarEvent[], leadTimeDays: number): ReminderDate[] {
  return events.map((event) => ({
    event,
    fireDate: addDaysUTC(event.date, -leadTimeDays),
  }));
}

// Calendar store/hook — projects the shared subscription + income/expense sample
// data into the viewed month via the pure core/recurrence engine (docs/13 §11).
// Talks to repository protocols only; no money rounding here.

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  events as projectEvents,
  startOfDayUTC,
  utcDate,
  type CalendarEvent,
  type FixedExpenseEntity,
  type IncomeEntity,
  type SubscriptionEntity,
} from '../../core/recurrence';
import { InMemorySubscriptionRepository } from '../subscriptions/repository';
import type { SubscriptionRepository } from '../subscriptions/types';
import { sharedCashFlowRepository } from '../cashflow/useCashFlow';
import type { CashFlowRepository } from '../cashflow/types';

/** Parse an ISO yyyy-mm-dd string to a midnight-UTC Date, or null. */
function parseISO(iso: string | null): Date | null {
  if (iso === null) return null;
  const [y, m, d] = iso.split('-').map((p) => Number.parseInt(p, 10));
  return utcDate(y, m, d);
}

export interface MonthView {
  /** 1-based year/month being viewed. */
  year: number;
  /** 1-based month (1 = January). */
  month: number;
}

export interface UseCalendar {
  loading: boolean;
  view: MonthView;
  /** All events in the viewed month, sorted by date then kind. */
  events: CalendarEvent[];
  /** Events for one day, keyed by yyyy-mm-dd. */
  eventsByDay: Map<string, CalendarEvent[]>;
  goPrevMonth: () => void;
  goNextMonth: () => void;
}

/** The fixed reference "today" so the demo is deterministic (matches docs/13). */
const REFERENCE = utcDate(2026, 6, 28);

const sharedSubscriptionRepository: SubscriptionRepository = new InMemorySubscriptionRepository();

export function useCalendar(
  initialView: MonthView = { year: REFERENCE.getUTCFullYear(), month: REFERENCE.getUTCMonth() + 1 },
  subscriptionRepo: SubscriptionRepository = sharedSubscriptionRepository,
  cashFlowRepo: CashFlowRepository = sharedCashFlowRepository,
): UseCalendar {
  const [view, setView] = useState<MonthView>(initialView);
  const [loading, setLoading] = useState(true);
  const [incomes, setIncomes] = useState<IncomeEntity[]>([]);
  const [subscriptions, setSubscriptions] = useState<SubscriptionEntity[]>([]);
  const [fixedExpenses, setFixedExpenses] = useState<FixedExpenseEntity[]>([]);

  const load = useCallback(async () => {
    setLoading(true);
    const [subs, inc, fix] = await Promise.all([
      subscriptionRepo.all(),
      cashFlowRepo.incomes(),
      cashFlowRepo.fixedExpenses(),
    ]);
    setSubscriptions(
      subs.map((s) => ({
        title: s.name,
        amountMinor: s.amountMinor,
        currency: s.currency,
        billingPeriod: s.billingPeriod,
        startDate: parseISO(s.startDate) ?? REFERENCE,
      })),
    );
    setIncomes(
      inc.map((i) => ({
        title: i.name,
        amountMinor: i.amountMinor,
        currency: i.currency,
        frequency: i.frequency,
        anchor: parseISO(i.nextPayment),
      })),
    );
    setFixedExpenses(
      fix.map((f) => ({
        title: f.name,
        amountMinor: f.amountMinor,
        currency: f.currency,
        frequency: f.billingPeriod,
        dueDate: parseISO(f.dueDate),
      })),
    );
    setLoading(false);
  }, [subscriptionRepo, cashFlowRepo]);

  useEffect(() => {
    void load();
  }, [load]);

  const windowStart = useMemo(() => utcDate(view.year, view.month, 1), [view]);
  const windowEnd = useMemo(
    () => utcDate(view.year, view.month + 1, 0), // day 0 of next month = last day
    [view],
  );

  const monthEvents = useMemo(
    () => projectEvents(windowStart, windowEnd, incomes, subscriptions, fixedExpenses, REFERENCE),
    [windowStart, windowEnd, incomes, subscriptions, fixedExpenses],
  );

  const eventsByDay = useMemo(() => {
    const map = new Map<string, CalendarEvent[]>();
    for (const e of monthEvents) {
      const key = startOfDayUTC(e.date).toISOString().slice(0, 10);
      const bucket = map.get(key);
      if (bucket) bucket.push(e);
      else map.set(key, [e]);
    }
    return map;
  }, [monthEvents]);

  const goPrevMonth = useCallback(() => {
    setView((v) => (v.month === 1 ? { year: v.year - 1, month: 12 } : { year: v.year, month: v.month - 1 }));
  }, []);

  const goNextMonth = useCallback(() => {
    setView((v) => (v.month === 12 ? { year: v.year + 1, month: 1 } : { year: v.year, month: v.month + 1 }));
  }, []);

  return {
    loading,
    view,
    events: monthEvents,
    eventsByDay,
    goPrevMonth,
    goNextMonth,
  };
}

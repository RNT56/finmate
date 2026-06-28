// Store/hook for the subscriptions slice — mirrors the iOS @Observable
// SubscriptionsStore (unidirectional MVVM). Talks to a repository protocol only.

import { useCallback, useEffect, useMemo, useState } from 'react';
import type { Subscription, SubscriptionRepository } from './types';
import { monthlyAmountMinor } from './types';
import { InMemorySubscriptionRepository } from './repository';
import { CurrencyConverter, type CurrencyCode, type ExchangeRates } from '../../core/currency';

// Fixed sample rate snapshot — in production this comes from the market-data
// Edge Function via the ExchangeRateProvider repository (docs/13 §2).
const SAMPLE_RATES: ExchangeRates = {
  eurUsd: 1.0825,
  btcEur: 58234.5,
  btcUsd: 63038.85,
  fetchedAt: Date.now(),
};

export interface UseSubscriptions {
  subscriptions: Subscription[];
  loading: boolean;
  add: (sub: Subscription) => Promise<void>;
  remove: (id: string) => Promise<void>;
  /** Total monthly-equivalent spend converted to `displayCurrency`, in minor units. */
  monthlyTotalMinor: (displayCurrency: CurrencyCode) => number;
}

export function useSubscriptions(
  repository: SubscriptionRepository = sharedRepository,
): UseSubscriptions {
  const [subscriptions, setSubscriptions] = useState<Subscription[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setSubscriptions(await repository.all());
    setLoading(false);
  }, [repository]);

  useEffect(() => {
    void load();
  }, [load]);

  const add = useCallback(
    async (sub: Subscription) => {
      await repository.upsert(sub);
      await load();
    },
    [repository, load],
  );

  const remove = useCallback(
    async (id: string) => {
      await repository.remove(id);
      await load();
    },
    [repository, load],
  );

  const converter = useMemo(() => new CurrencyConverter(SAMPLE_RATES), []);

  const monthlyTotalMinor = useCallback(
    (displayCurrency: CurrencyCode): number =>
      monthlyTotalForDisplay(subscriptions, displayCurrency, converter),
    [subscriptions, converter],
  );

  return { subscriptions, loading, add, remove, monthlyTotalMinor };
}

/**
 * Pure aggregation (unit-tested): per-sub monthly-equivalent, converted to the
 * display currency, summed in minor units. Mirrors docs/13 §6.2 subscriptions roll-up.
 */
export function monthlyTotalForDisplay(
  subscriptions: Subscription[],
  displayCurrency: CurrencyCode,
  converter: CurrencyConverter,
): number {
  let total = 0;
  for (const sub of subscriptions) {
    const monthly = monthlyAmountMinor(sub);
    const converted = converter.convert(monthly, sub.currency, displayCurrency);
    // Rate unavailable -> only contribute when already in the display currency
    // (never silently guess); sample data is all-EUR so this is exact.
    if (converted.ok) total += converted.minorUnits;
    else if (sub.currency === displayCurrency) total += monthly;
  }
  return total;
}

/** A single shared in-memory repo so all screens see the same sample/added data. */
export const sharedRepository: SubscriptionRepository = new InMemorySubscriptionRepository();

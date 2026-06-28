// App-wide sample exchange-rate snapshot — the single offline rate source shared by
// every analytic (cash flow, subscriptions, assets, Home dashboard). In production
// these come from the `market-data` Edge Function via the MarketDataRateProvider
// (ADR-0010), never a client-side provider; this is the offline fallback used when
// Supabase is not configured. Identical to the iOS `AssetsSampleData.sampleRates`
// (eurUsd 1.10, btcEur 50_000, btcUsd 55_000) so both clients agree on every figure.

import type { ExchangeRates } from '../core/currency';

/** Canonical offline rates: eurUsd 1.10 (USD per EUR), btcEur 50_000, btcUsd 55_000. */
export const APP_RATES: ExchangeRates = {
  eurUsd: 1.1,
  btcEur: 50_000,
  btcUsd: 55_000,
  fetchedAt: Date.now(),
};

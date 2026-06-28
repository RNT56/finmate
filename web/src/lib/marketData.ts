// MarketDataRateProvider — mirrors the iOS `ExchangeRateProvider` protocol. Fetches
// the canonical exchange-rate snapshot from the server-side `market-data` Edge
// Function (ADR-0010, docs/04 §6.2), NEVER from a client-side provider: the provider
// key stays server-side and only authenticated app users can invoke it (verify_jwt).
//
// The Edge Function returns snake_case JSON { eur_usd, btc_eur, btc_usd, fetched_at }
// where fetched_at is an ISO8601 string; this maps it to the Domain `ExchangeRates`
// (camelCase, fetchedAt = ms epoch — docs/13 §2).

import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../types/database';
import type { ExchangeRates } from '../core/currency';

/** The raw snake_case shape returned by the `market-data` Edge Function (docs/04 §6.2). */
export interface MarketDataResponse {
  eur_usd: number;
  btc_eur: number;
  btc_usd: number;
  /** ISO8601 timestamp. */
  fetched_at: string;
}

/** Edge Function JSON -> Domain `ExchangeRates` (snake_case -> camelCase, ISO -> ms). */
export function ratesFromResponse(res: MarketDataResponse): ExchangeRates {
  const parsed = Date.parse(res.fetched_at);
  return {
    eurUsd: res.eur_usd,
    btcEur: res.btc_eur,
    btcUsd: res.btc_usd,
    fetchedAt: Number.isNaN(parsed) ? Date.now() : parsed,
  };
}

/** Abstracts exchange-rate fetching; mirrors the Swift `ExchangeRateProvider`. */
export interface RateProvider {
  latest(): Promise<ExchangeRates>;
}

export class MarketDataRateProvider implements RateProvider {
  constructor(private readonly client: SupabaseClient<Database>) {}

  async latest(): Promise<ExchangeRates> {
    const { data, error } = await this.client.functions.invoke<MarketDataResponse>('market-data');
    if (error) throw error;
    if (!data) throw new Error('market-data returned no data');
    return ratesFromResponse(data);
  }
}

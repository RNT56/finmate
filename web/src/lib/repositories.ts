// Repository selector (docs/03 §3 DataLayer). One place decides whether the app runs
// on the LIVE Supabase backend or the offline IN-MEMORY sample repos:
//
//   * If getSupabase() returns a client (VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY
//     are configured), use the Supabase-backed implementations.
//   * Otherwise fall back to the existing in-memory sample repos so the app builds
//     and previews offline EXACTLY as today — no behavior change when unconfigured.
//
// Stores/hooks consume the protocols here, never the SDK directly. The selection is
// memoized so every screen shares one repo instance (parity with the in-memory
// `shared*Repository` singletons).

import { getSupabase } from './supabase';

import type { SubscriptionRepository } from '../features/subscriptions/types';
import { sharedRepository as inMemorySubscriptions } from '../features/subscriptions/useSubscriptions';
import { SupabaseSubscriptionRepository } from '../features/subscriptions/supabaseRepository';

import type { CashFlowRepository } from '../features/cashflow/types';
import { sharedCashFlowRepository as inMemoryCashFlow } from '../features/cashflow/useCashFlow';
import { SupabaseCashFlowRepository } from '../features/cashflow/supabaseRepository';

import type { AssetsRepository } from '../features/assets/repository';
import { sharedAssetsRepository as inMemoryAssets } from '../features/assets/repository';
import { SupabaseAssetsRepository } from '../features/assets/supabaseRepository';

import type { PreferencesRepository } from '../core/preferences';
import { LocalStoragePreferencesRepository } from '../core/preferences';
import { SupabasePreferencesRepository } from '../features/settings/supabaseRepository';

import type { RateProvider } from './marketData';
import { MarketDataRateProvider } from './marketData';

/** True when the live Supabase backend is selected (env configured). */
export const usingSupabase: boolean = getSupabase() !== null;

interface Repositories {
  subscriptions: SubscriptionRepository;
  cashFlow: CashFlowRepository;
  assets: AssetsRepository;
  preferences: PreferencesRepository;
  /** Live rate provider; null when offline (hooks fall back to sample rates). */
  rateProvider: RateProvider | null;
}

let cached: Repositories | null = null;

/** The selected repositories — Supabase when configured, in-memory otherwise. */
export function getRepositories(): Repositories {
  if (cached) return cached;
  const client = getSupabase();
  cached = client
    ? {
        subscriptions: new SupabaseSubscriptionRepository(client),
        cashFlow: new SupabaseCashFlowRepository(client),
        assets: new SupabaseAssetsRepository(client),
        preferences: new SupabasePreferencesRepository(client),
        rateProvider: new MarketDataRateProvider(client),
      }
    : {
        subscriptions: inMemorySubscriptions,
        cashFlow: inMemoryCashFlow,
        assets: inMemoryAssets,
        preferences: new LocalStoragePreferencesRepository(),
        rateProvider: null,
      };
  return cached;
}

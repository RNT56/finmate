// Store/hook for the assets slice (M5) — mirrors the iOS @Observable assets store.
// Talks to a repository protocol only; all valuation math comes from core/assets.
// The display currency is a parameter so the EUR/USD/BTC switcher re-converts the
// portfolio totals (display-only, non-mutating — docs/13 §2; product spec §11).

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  type AssetSlice,
  type AssetTransactionKind,
  type FinancialAsset,
  applyTransaction,
  assetDistribution,
  portfolioCostBasisMinor,
  portfolioGainMinor,
  portfolioValueMinor,
} from '../../core/assets';
import { CurrencyConverter, type CurrencyCode } from '../../core/currency';
import { type AssetsRepository } from './repository';
import { getRepositories } from '../../lib/repositories';
import { APP_RATES } from '../../lib/rates';

export interface UseAssets {
  loading: boolean;
  /** Captured load error (null on the happy path); drives the inline error card. */
  error: string | null;
  /** Re-run the load (the error card's Retry action). */
  reload: () => Promise<void>;
  assets: FinancialAsset[];
  /** Portfolio total value in `displayCurrency` minor units. */
  totalValueMinor: number;
  /** Portfolio total cost basis in `displayCurrency` minor units. */
  totalCostMinor: number;
  /** Portfolio unrealized gain/loss in `displayCurrency` minor units. */
  totalGainMinor: number;
  /** Gain as a fraction of cost basis; 0 when cost basis is 0. */
  totalGainPct: number;
  /** Descending-by-value distribution by asset type (converted). */
  distribution: AssetSlice[];
  converter: CurrencyConverter;

  /** Insert or update an asset, then reload (portfolio/gain recompute). */
  saveAsset: (asset: FinancialAsset) => Promise<void>;
  /** Delete an asset by id, then reload. */
  removeAsset: (id: string) => Promise<void>;
  /**
   * Apply a buy/sell/dividend/other transaction to an asset under average-cost
   * basis (pure `applyTransaction`), persist the re-marked asset, then reload.
   */
  recordTransaction: (
    assetId: string,
    txn: {
      kind: AssetTransactionKind;
      quantity: number;
      priceMinor: number;
      feesMinor: number;
    }
  ) => Promise<void>;
}

export function useAssets(
  displayCurrency: CurrencyCode,
  repository: AssetsRepository = getRepositories().assets
): UseAssets {
  const [assets, setAssets] = useState<FinancialAsset[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setAssets(await repository.all());
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load assets.');
    } finally {
      setLoading(false);
    }
  }, [repository]);

  useEffect(() => {
    void load();
  }, [load]);

  const saveAsset = useCallback(
    async (asset: FinancialAsset) => {
      await repository.upsert(asset);
      await load();
    },
    [repository, load]
  );

  const removeAsset = useCallback(
    async (id: string) => {
      await repository.remove(id);
      await load();
    },
    [repository, load]
  );

  const recordTransaction = useCallback(
    async (
      assetId: string,
      txn: {
        kind: AssetTransactionKind;
        quantity: number;
        priceMinor: number;
        feesMinor: number;
      }
    ) => {
      const current = await repository.all();
      const target = current.find((a) => a.id === assetId);
      if (!target) return;
      await repository.upsert(applyTransaction(target, txn));
      await load();
    },
    [repository, load]
  );

  const converter = useMemo(
    () => new CurrencyConverter(APP_RATES),
    []
  );

  const totalValueMinor = useMemo(
    () => portfolioValueMinor(assets, displayCurrency, converter),
    [assets, displayCurrency, converter]
  );
  const totalCostMinor = useMemo(
    () => portfolioCostBasisMinor(assets, displayCurrency, converter),
    [assets, displayCurrency, converter]
  );
  const totalGainMinor = useMemo(
    () => portfolioGainMinor(assets, displayCurrency, converter),
    [assets, displayCurrency, converter]
  );
  const totalGainPct =
    totalCostMinor === 0 ? 0 : totalGainMinor / totalCostMinor;
  const distribution = useMemo(
    () => assetDistribution(assets, displayCurrency, converter),
    [assets, displayCurrency, converter]
  );

  return {
    loading,
    error,
    reload: load,
    assets,
    totalValueMinor,
    totalCostMinor,
    totalGainMinor,
    totalGainPct,
    distribution,
    converter,
    saveAsset,
    removeAsset,
    recordTransaction,
  };
}

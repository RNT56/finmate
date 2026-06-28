// Hook-layer tests for useAssets — the React store wiring the AssetsRepository
// protocol + core/assets valuation into the UI. Mirrors the iOS AssetsStore tests.
// Uses a hand-rolled mock repository.
//
// @vitest-environment jsdom

import { describe, it, expect, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { useAssets } from './useAssets';
import type { AssetsRepository } from './repository';
import type { FinancialAsset } from '../../core/assets';

function makeAsset(overrides: Partial<FinancialAsset> = {}): FinancialAsset {
  return {
    id: 'asset-1',
    name: 'Bitcoin',
    type: 'crypto',
    currency: 'EUR',
    quantity: 0.5,
    purchasePriceMinor: 2_000_000,
    currentPriceMinor: 5_000_000,
    valueMinor: 2_500_000,
    notes: null,
    ...overrides,
  };
}

class MockAssetsRepository implements AssetsRepository {
  store = new Map<string, FinancialAsset>();
  constructor(seed: FinancialAsset[] = []) {
    seed.forEach((a) => this.store.set(a.id, { ...a }));
  }
  async all(): Promise<FinancialAsset[]> {
    return [...this.store.values()].map((a) => ({ ...a }));
  }
  async upsert(asset: FinancialAsset): Promise<void> {
    this.store.set(asset.id, { ...asset });
  }
  async remove(id: string): Promise<void> {
    this.store.delete(id);
  }
}

class ThrowingAssetsRepository implements AssetsRepository {
  async all(): Promise<FinancialAsset[]> {
    throw new Error('assets boom');
  }
  async upsert(): Promise<void> {}
  async remove(): Promise<void> {}
}

describe('useAssets (hook)', () => {
  let repo: MockAssetsRepository;

  beforeEach(() => {
    repo = new MockAssetsRepository([
      makeAsset({
        id: 'asset-btc',
        purchasePriceMinor: 2_000_000,
        valueMinor: 2_500_000,
      }),
      makeAsset({
        id: 'asset-etf',
        name: 'World ETF',
        type: 'etf',
        quantity: 10,
        purchasePriceMinor: 150_000,
        currentPriceMinor: 18_000,
        valueMinor: 180_000,
      }),
    ]);
  });

  it('loads and computes portfolio totals (happy path)', async () => {
    const { result } = renderHook(() => useAssets('EUR', repo));
    expect(result.current.loading).toBe(true);
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.assets).toHaveLength(2);
    expect(result.current.error).toBeNull();
    // value 2_500_000 + 180_000 = 2_680_000; cost 2_000_000 + 150_000 = 2_150_000.
    expect(result.current.totalValueMinor).toBe(2_680_000);
    expect(result.current.totalCostMinor).toBe(2_150_000);
    expect(result.current.totalGainMinor).toBe(530_000);
  });

  it('loads empty (no NaN, gain pct 0)', async () => {
    const { result } = renderHook(() => useAssets('EUR', new MockAssetsRepository([])));
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.assets).toHaveLength(0);
    expect(result.current.totalValueMinor).toBe(0);
    expect(result.current.totalGainPct).toBe(0);
  });

  it('saveAsset() upserts then reloads (totals recompute)', async () => {
    const { result } = renderHook(() => useAssets('EUR', repo));
    await waitFor(() => expect(result.current.loading).toBe(false));
    await result.current.saveAsset(
      makeAsset({ id: 'asset-cash', type: 'cash', valueMinor: 100_000, purchasePriceMinor: 100_000 })
    );
    await waitFor(() => expect(result.current.assets).toHaveLength(3));
    expect(result.current.totalValueMinor).toBe(2_780_000);
  });

  it('removeAsset() deletes then reloads', async () => {
    const { result } = renderHook(() => useAssets('EUR', repo));
    await waitFor(() => expect(result.current.loading).toBe(false));
    await result.current.removeAsset('asset-etf');
    await waitFor(() => expect(result.current.assets).toHaveLength(1));
    expect(result.current.totalValueMinor).toBe(2_500_000);
  });

  it('recordTransaction() applies average-cost basis then reloads (recompute)', async () => {
    const single = new MockAssetsRepository([
      makeAsset({
        id: 'asset-btc',
        quantity: 0.5,
        purchasePriceMinor: 2_000_000,
        currentPriceMinor: 5_000_000,
        valueMinor: 2_500_000,
      }),
    ]);
    const { result } = renderHook(() => useAssets('EUR', single));
    await waitFor(() => expect(result.current.loading).toBe(false));
    // Buy 0.5 more @ €50,000/BTC (priceMinor 5_000_000), no fees.
    await result.current.recordTransaction('asset-btc', {
      kind: 'buy',
      quantity: 0.5,
      priceMinor: 5_000_000,
      feesMinor: 0,
    });
    await waitFor(() => expect(result.current.assets[0].quantity).toBeCloseTo(1, 8));
    // cost basis grows by 0.5 * 5_000_000 = 2_500_000 -> 4_500_000.
    expect(result.current.totalCostMinor).toBe(4_500_000);
  });

  it('recordTransaction() on a missing asset is a no-op', async () => {
    const { result } = renderHook(() => useAssets('EUR', repo));
    await waitFor(() => expect(result.current.loading).toBe(false));
    const before = result.current.assets.length;
    await result.current.recordTransaction('nope', {
      kind: 'buy',
      quantity: 1,
      priceMinor: 1000,
      feesMinor: 0,
    });
    expect(result.current.assets).toHaveLength(before);
  });

  it('switching display currency recomputes totals (EUR -> USD @ 1.10)', async () => {
    const { result, rerender } = renderHook(
      ({ ccy }: { ccy: 'EUR' | 'USD' }) => useAssets(ccy, repo),
      { initialProps: { ccy: 'EUR' as 'EUR' | 'USD' } }
    );
    await waitFor(() => expect(result.current.loading).toBe(false));
    const eurValue = result.current.totalValueMinor;
    expect(eurValue).toBe(2_680_000);

    rerender({ ccy: 'USD' });
    await waitFor(() => expect(result.current.totalValueMinor).not.toBe(eurValue));
    // EUR minor 2_680_000 -> USD @ 1.10 = 2_948_000.
    expect(result.current.totalValueMinor).toBe(2_948_000);
  });

  it('captures a load error into error state', async () => {
    const { result } = renderHook(() => useAssets('EUR', new ThrowingAssetsRepository()));
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.error).toBe('assets boom');
    expect(result.current.assets).toHaveLength(0);
  });
});

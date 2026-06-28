// InMemoryAssetsRepository + SAMPLE DATA — mirrors the iOS in-memory repo pattern.
// Figures match the shared M5 sample portfolio so both clients display identical
// numbers (docs/05 §3.7; ADR-0015 average-cost basis):
//   Bitcoin (crypto, EUR, qty 0.5, cost 2_000_000, value 2_500_000) -> +500_000
//   World ETF (etf, EUR, qty 10,  cost   150_000, value   180_000) -> + 30_000
//   ACME     (stock, EUR, qty 5,  cost    50_000, value    45_000) -> -  5_000
//   Portfolio value 2_725_000 (€27,250), cost 2_200_000, gain +525_000 (€5,250).

import type { FinancialAsset } from '../../core/assets';

export const sampleAssets: FinancialAsset[] = [
  {
    id: 'asset-btc',
    name: 'Bitcoin',
    type: 'crypto',
    currency: 'EUR',
    quantity: 0.5,
    purchasePriceMinor: 2_000_000, // €20,000 total cost basis
    currentPriceMinor: 5_000_000, // €50,000 per BTC
    valueMinor: 2_500_000, // €25,000 current value
    notes: 'Cold storage',
  },
  {
    id: 'asset-etf',
    name: 'World ETF',
    type: 'etf',
    currency: 'EUR',
    quantity: 10,
    purchasePriceMinor: 150_000, // €1,500 total cost basis
    currentPriceMinor: 18_000, // €180 per share
    valueMinor: 180_000, // €1,800 current value
    notes: null,
  },
  {
    id: 'asset-acme',
    name: 'ACME',
    type: 'stock',
    currency: 'EUR',
    quantity: 5,
    purchasePriceMinor: 50_000, // €500 total cost basis
    currentPriceMinor: 9_000, // €90 per share
    valueMinor: 45_000, // €450 current value
    notes: null,
  },
];

/** Repository protocol — the store calls this, never the SDK directly (docs/03). */
export interface AssetsRepository {
  all(): Promise<FinancialAsset[]>;
  upsert(asset: FinancialAsset): Promise<void>;
  remove(id: string): Promise<void>;
}

export class InMemoryAssetsRepository implements AssetsRepository {
  private store: Map<string, FinancialAsset>;

  constructor(seed: FinancialAsset[] = sampleAssets) {
    this.store = new Map(seed.map((a) => [a.id, { ...a }]));
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

/** A single shared in-memory repo so all screens see the same sample data. */
export const sharedAssetsRepository: AssetsRepository = new InMemoryAssetsRepository();

import { describe, it, expect } from 'vitest';
import {
  type AssetType,
  type FinancialAsset,
  allAssetTypes,
  assetTypeLabel,
  unrealizedGainMinor,
  gainPct,
  portfolioValueMinor,
  portfolioCostBasisMinor,
  portfolioGainMinor,
  assetDistribution,
  applyTransaction,
} from './assets';
import { CurrencyConverter, type ExchangeRates } from './currency';

// Mirrors the Swift AssetValuationTests vectors (docs/13; ADR-0015).
// Sample portfolio — IDENTICAL to the web/iOS sample repos so figures agree:
//   Bitcoin (crypto, EUR, qty 0.5, cost 2_000_000, value 2_500_000) -> +500_000
//   World ETF (etf, EUR, qty 10,  cost   150_000, value   180_000) -> + 30_000
//   ACME     (stock, EUR, qty 5,  cost    50_000, value    45_000) -> -  5_000
//   Portfolio value 2_725_000, cost 2_200_000, unrealized gain +525_000.

const bitcoin: FinancialAsset = {
  id: 'a-btc',
  name: 'Bitcoin',
  type: 'crypto',
  currency: 'EUR',
  quantity: 0.5,
  purchasePriceMinor: 2_000_000,
  currentPriceMinor: 5_000_000, // 0.5 * 5_000_000 = 2_500_000 = value
  valueMinor: 2_500_000,
  notes: null,
};

const worldEtf: FinancialAsset = {
  id: 'a-etf',
  name: 'World ETF',
  type: 'etf',
  currency: 'EUR',
  quantity: 10,
  purchasePriceMinor: 150_000,
  currentPriceMinor: 18_000, // 10 * 18_000 = 180_000 = value
  valueMinor: 180_000,
  notes: null,
};

const acme: FinancialAsset = {
  id: 'a-acme',
  name: 'ACME',
  type: 'stock',
  currency: 'EUR',
  quantity: 5,
  purchasePriceMinor: 50_000,
  currentPriceMinor: 9_000, // 5 * 9_000 = 45_000 = value
  valueMinor: 45_000,
  notes: null,
};

const portfolio = [bitcoin, worldEtf, acme];

// Sample display rates (identical both clients): eurUsd 1.10, btcEur 50000, btcUsd 55000.
const SAMPLE_RATES: ExchangeRates = {
  eurUsd: 1.1,
  btcEur: 50_000,
  btcUsd: 55_000,
  fetchedAt: 0,
};
const eurConverter = new CurrencyConverter(SAMPLE_RATES);

describe('AssetType vocabulary (ADR-0023: canonical union, mirrors Swift)', () => {
  it('enumerates all 7 canonical asset types', () => {
    expect(allAssetTypes).toEqual([
      'crypto',
      'stock',
      'etf',
      'cash',
      'savings',
      'real_estate',
      'other',
    ]);
  });

  it('maps every type to a human label (incl. Savings / Real estate)', () => {
    const labels: Record<AssetType, string> = {
      crypto: 'Crypto',
      stock: 'Stock',
      etf: 'ETF',
      cash: 'Cash',
      savings: 'Savings',
      real_estate: 'Real estate',
      other: 'Other',
    };
    for (const t of allAssetTypes) {
      expect(assetTypeLabel(t)).toBe(labels[t]);
    }
  });
});

describe('unrealizedGainMinor / gainPct', () => {
  it('Bitcoin +500_000 (+25%)', () => {
    expect(unrealizedGainMinor(bitcoin)).toBe(500_000);
    expect(gainPct(bitcoin)).toBeCloseTo(0.25, 10);
  });

  it('World ETF +30_000 (+20%)', () => {
    expect(unrealizedGainMinor(worldEtf)).toBe(30_000);
    expect(gainPct(worldEtf)).toBeCloseTo(0.2, 10);
  });

  it('ACME -5_000 (-10%)', () => {
    expect(unrealizedGainMinor(acme)).toBe(-5_000);
    expect(gainPct(acme)).toBeCloseTo(-0.1, 10);
  });

  it('zero cost basis -> gainPct 0 (no divide-by-zero)', () => {
    const cash: FinancialAsset = {
      id: 'a-cash',
      name: 'Cash',
      type: 'cash',
      currency: 'EUR',
      quantity: 1,
      purchasePriceMinor: 0,
      currentPriceMinor: 10_000,
      valueMinor: 10_000,
      notes: null,
    };
    expect(unrealizedGainMinor(cash)).toBe(10_000);
    expect(gainPct(cash)).toBe(0);
  });
});

describe('portfolio totals (EUR display, same-currency, no conversion)', () => {
  it('value 2_725_000, cost 2_200_000, gain +525_000', () => {
    expect(portfolioValueMinor(portfolio, 'EUR', eurConverter)).toBe(2_725_000);
    expect(portfolioCostBasisMinor(portfolio, 'EUR', eurConverter)).toBe(2_200_000);
    expect(portfolioGainMinor(portfolio, 'EUR', eurConverter)).toBe(525_000);
  });

  it('empty portfolio totals are zero', () => {
    expect(portfolioValueMinor([], 'EUR', eurConverter)).toBe(0);
    expect(portfolioCostBasisMinor([], 'EUR', eurConverter)).toBe(0);
    expect(portfolioGainMinor([], 'EUR', eurConverter)).toBe(0);
  });
});

describe('portfolio totals converted to USD (eurUsd 1.10)', () => {
  it('value 2_725_000 EUR -> 2_997_500 cents USD', () => {
    // 2_725_000 cents EUR = €27,250 -> $29,975 = 2_997_500 cents.
    expect(portfolioValueMinor(portfolio, 'USD', eurConverter)).toBe(2_997_500);
    // 2_200_000 cents EUR = €22,000 -> $24,200 = 2_420_000 cents.
    expect(portfolioCostBasisMinor(portfolio, 'USD', eurConverter)).toBe(2_420_000);
    expect(portfolioGainMinor(portfolio, 'USD', eurConverter)).toBe(577_500);
  });
});

describe('portfolio value converted to BTC (btcEur 50000)', () => {
  it('€27,250 / €50,000 per BTC = 0.545 BTC = 54_500_000 sats', () => {
    // value €27,250 -> 0.545 BTC -> 54_500_000 sats.
    expect(portfolioValueMinor(portfolio, 'BTC', eurConverter)).toBe(54_500_000);
  });
});

describe('assetDistribution', () => {
  it('three slices by type, descending by value, with shares summing to 1', () => {
    const slices = assetDistribution(portfolio, 'EUR', eurConverter);
    expect(slices.map((s) => s.type)).toEqual(['crypto', 'etf', 'stock']);
    expect(slices.map((s) => s.totalMinor)).toEqual([2_500_000, 180_000, 45_000]);
    expect(slices.every((s) => s.count === 1)).toBe(true);
    // crypto share = 2_500_000 / 2_725_000.
    expect(slices[0].share).toBeCloseTo(2_500_000 / 2_725_000, 10);
    const shareSum = slices.reduce((s, x) => s + x.share, 0);
    expect(shareSum).toBeCloseTo(1, 10);
  });

  it('aggregates multiple assets of the same type and breaks value ties by type name', () => {
    const extraEtf: FinancialAsset = { ...worldEtf, id: 'a-etf2', valueMinor: 20_000, purchasePriceMinor: 20_000 };
    const slices = assetDistribution([worldEtf, extraEtf], 'EUR', eurConverter);
    expect(slices).toHaveLength(1);
    expect(slices[0].type).toBe('etf');
    expect(slices[0].totalMinor).toBe(200_000);
    expect(slices[0].count).toBe(2);
    expect(slices[0].share).toBeCloseTo(1, 10);
  });

  it('empty portfolio -> no slices', () => {
    expect(assetDistribution([], 'EUR', eurConverter)).toEqual([]);
  });
});

describe('applyTransaction (average-cost basis)', () => {
  // ETF: qty 10, total cost 150_000, per-unit price 18_000, value 180_000.
  it('buy adds quantity, adds qty*price+fees to cost basis, re-marks value', () => {
    const next = applyTransaction(worldEtf, {
      kind: 'buy',
      quantity: 5,
      priceMinor: 20_000, // per-unit
      feesMinor: 1_000,
    });
    expect(next.quantity).toBe(15);
    // 150_000 + 5*20_000 + 1_000 = 251_000
    expect(next.purchasePriceMinor).toBe(251_000);
    expect(next.currentPriceMinor).toBe(20_000);
    // value = 15 * 20_000 = 300_000
    expect(next.valueMinor).toBe(300_000);
  });

  it('sell removes basis at the average unit cost (realized P/L excluded) and re-marks value', () => {
    // avg unit cost = 150_000 / 10 = 15_000. Sell 4 -> remove 60_000 basis.
    const next = applyTransaction(worldEtf, {
      kind: 'sell',
      quantity: 4,
      priceMinor: 25_000,
      feesMinor: 0,
    });
    expect(next.quantity).toBe(6);
    expect(next.purchasePriceMinor).toBe(90_000); // 150_000 - 60_000
    expect(next.currentPriceMinor).toBe(25_000);
    expect(next.valueMinor).toBe(150_000); // 6 * 25_000
  });

  it('selling the whole position resets quantity and cost basis to 0', () => {
    const next = applyTransaction(worldEtf, {
      kind: 'sell',
      quantity: 10,
      priceMinor: 19_000,
      feesMinor: 0,
    });
    expect(next.quantity).toBe(0);
    expect(next.purchasePriceMinor).toBe(0);
    expect(next.valueMinor).toBe(0);
  });

  it('over-selling clamps quantity at 0 (cannot go negative)', () => {
    const next = applyTransaction(worldEtf, {
      kind: 'sell',
      quantity: 99,
      priceMinor: 19_000,
      feesMinor: 0,
    });
    expect(next.quantity).toBe(0);
    expect(next.purchasePriceMinor).toBe(0);
  });

  it('dividend/other do not change quantity or cost basis but can re-mark price', () => {
    const div = applyTransaction(worldEtf, {
      kind: 'dividend',
      quantity: 0,
      priceMinor: 19_000,
      feesMinor: 0,
    });
    expect(div.quantity).toBe(10);
    expect(div.purchasePriceMinor).toBe(150_000);
    expect(div.currentPriceMinor).toBe(19_000);
    expect(div.valueMinor).toBe(190_000); // re-marked: 10 * 19_000

    // priceMinor 0 leaves the per-unit price untouched.
    const other = applyTransaction(worldEtf, {
      kind: 'other',
      quantity: 0,
      priceMinor: 0,
      feesMinor: 0,
    });
    expect(other.currentPriceMinor).toBe(18_000);
    expect(other.valueMinor).toBe(180_000);
  });

  it('is pure — does not mutate the input asset', () => {
    const before = { ...worldEtf };
    applyTransaction(worldEtf, { kind: 'buy', quantity: 1, priceMinor: 20_000, feesMinor: 0 });
    expect(worldEtf).toEqual(before);
  });
});

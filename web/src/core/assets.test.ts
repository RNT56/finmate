import { describe, it, expect } from 'vitest';
import {
  type FinancialAsset,
  unrealizedGainMinor,
  gainPct,
  portfolioValueMinor,
  portfolioCostBasisMinor,
  portfolioGainMinor,
  assetDistribution,
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

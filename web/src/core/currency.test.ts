import { describe, it, expect } from 'vitest';
import {
  CurrencyConverter,
  type ExchangeRates,
  satsFromBTC,
  btcFromSats,
  ratesAreStale,
  roundHalfUp,
} from './currency';

// Rates from docs/13 §2.3 worked vectors.
const rates: ExchangeRates = {
  eurUsd: 1.0825,
  btcEur: 58234.5,
  btcUsd: 63038.85,
  fetchedAt: Date.parse('2026-06-28T09:14:32Z'),
};

describe('CurrencyConverter', () => {
  const c = new CurrencyConverter(rates);

  it('T2.3a EUR -> USD half-up: €10.00 -> $10.83', () => {
    const r = c.convert(1000, 'EUR', 'USD');
    expect(r.ok && r.minorUnits).toBe(1083);
  });

  it('T2.3b USD -> EUR: $10.83 -> €10.00', () => {
    const r = c.convert(1083, 'USD', 'EUR');
    expect(r.ok && r.minorUnits).toBe(1000);
  });

  it('T2.3c EUR -> BTC sats: €500 @ €50k/BTC -> 1,000,000 sats', () => {
    const flat = new CurrencyConverter({ ...rates, btcEur: 50000 });
    const r = flat.convert(50000, 'EUR', 'BTC'); // €500.00
    expect(r.ok && r.minorUnits).toBe(1_000_000);
  });

  it('T2.3d BTC -> USD: 0.0005 BTC -> $31.52', () => {
    const r = c.convert(50000, 'BTC', 'USD');
    expect(r.ok && r.minorUnits).toBe(3152);
  });

  it('T2.3e identity returns input unchanged', () => {
    const r = c.convert(2500, 'USD', 'USD');
    expect(r.ok && r.minorUnits).toBe(2500);
  });

  it('T2.3f rate unavailable when btcEur is missing', () => {
    const noBtc = new CurrencyConverter({ ...rates, btcEur: 0 });
    const r = noBtc.convert(1000, 'EUR', 'BTC');
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.kind).toBe('rateUnavailable');
      expect(r.error.from).toBe('EUR');
      expect(r.error.to).toBe('BTC');
    }
  });

  it('half-up boundary: 1 USD-cent -> EUR @ 2.0 -> 1 EUR-cent', () => {
    const c2 = new CurrencyConverter({ ...rates, eurUsd: 2.0 });
    const r = c2.convert(1, 'USD', 'EUR'); // 0.01 / 2.0 = 0.005 -> half up -> 0.01
    expect(r.ok && r.minorUnits).toBe(1);
  });
});

describe('BTC <-> sats', () => {
  it('T2.4a 0.0005 BTC -> 50000 sats', () => {
    expect(satsFromBTC(0.0005)).toBe(50000);
  });
  it('T2.4b 1 BTC -> 100,000,000 sats', () => {
    expect(satsFromBTC(1)).toBe(100_000_000);
  });
  it('T2.4d 123,456,789 sats -> 1.23456789 BTC', () => {
    expect(btcFromSats(123_456_789)).toBeCloseTo(1.23456789, 8);
  });
});

describe('ratesAreStale', () => {
  it('T2.5a false within 24h', () => {
    const f = Date.parse('2026-06-28T00:00:00Z');
    const now = Date.parse('2026-06-28T12:00:00Z');
    expect(ratesAreStale({ ...rates, fetchedAt: f }, now)).toBe(false);
  });
  it('T2.5b true beyond 24h', () => {
    const f = Date.parse('2026-06-26T00:00:00Z');
    const now = Date.parse('2026-06-28T00:00:01Z');
    expect(ratesAreStale({ ...rates, fetchedAt: f }, now)).toBe(true);
  });
  it('T2.5c false exactly at 24h boundary', () => {
    const f = Date.parse('2026-06-27T00:00:00Z');
    const now = Date.parse('2026-06-28T00:00:00Z');
    expect(ratesAreStale({ ...rates, fetchedAt: f }, now)).toBe(false);
  });
});

describe('roundHalfUp', () => {
  it('rounds halves away from zero', () => {
    expect(roundHalfUp(0.5)).toBe(1);
    expect(roundHalfUp(1.5)).toBe(2);
    expect(roundHalfUp(2.5)).toBe(3); // not banker's rounding
    expect(roundHalfUp(43333.333)).toBe(43333);
  });
});

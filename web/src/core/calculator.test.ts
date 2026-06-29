import { describe, it, expect } from 'vitest';
import { CurrencyConverter, type ExchangeRates } from './currency';
import { computeBtcConversion } from './calculator';

// Stubbed sample rates: btcEur 50_000 => €500 / €50,000 per BTC = 0.01 BTC = 1_000_000 sats.
const SAMPLE_RATES: ExchangeRates = {
  eurUsd: 1.1,
  btcEur: 50_000,
  btcUsd: 55_000,
  fetchedAt: 0,
};

const sample = new CurrencyConverter(SAMPLE_RATES);

describe('computeBtcConversion', () => {
  it('€500 at €50,000/BTC -> 0.01 BTC = 1,000,000 sats', () => {
    const r = computeBtcConversion('500', 'EUR', sample);
    expect(r).not.toBeNull();
    expect(r?.fiatMinor).toBe(50_000); // 500 EUR in cents
    expect(r?.sats).toBe(1_000_000);
    expect(r?.btc).toBeCloseTo(0.01, 12);
  });

  it('$550 at $55,000/BTC -> 1,000,000 sats', () => {
    const r = computeBtcConversion('550', 'USD', sample);
    expect(r?.sats).toBe(1_000_000);
  });

  it('is rate-dependent: a different rate set yields different sats', () => {
    const cheaper = new CurrencyConverter({ ...SAMPLE_RATES, btcEur: 25_000 });
    const base = computeBtcConversion('500', 'EUR', sample);
    const other = computeBtcConversion('500', 'EUR', cheaper);
    expect(base?.sats).toBe(1_000_000);
    // Half the BTC price => twice the sats for the same fiat.
    expect(other?.sats).toBe(2_000_000);
    expect(other?.sats).not.toBe(base?.sats);
  });

  it('empty input -> null', () => {
    expect(computeBtcConversion('', 'EUR', sample)).toBeNull();
    expect(computeBtcConversion('   ', 'EUR', sample)).toBeNull();
  });

  it('negative input -> null', () => {
    expect(computeBtcConversion('-500', 'EUR', sample)).toBeNull();
  });

  it('non-numeric input -> null', () => {
    expect(computeBtcConversion('abc', 'EUR', sample)).toBeNull();
    expect(computeBtcConversion('1,5', 'EUR', sample)).toBeNull();
  });

  it('over-precision fiat input (more than 2 fraction digits) -> null', () => {
    expect(computeBtcConversion('1.234', 'EUR', sample)).toBeNull();
  });

  it('zero is a valid amount -> 0 sats', () => {
    const r = computeBtcConversion('0', 'EUR', sample);
    expect(r?.fiatMinor).toBe(0);
    expect(r?.sats).toBe(0);
    expect(r?.btc).toBe(0);
  });

  it('returns null when the BTC rate is unavailable', () => {
    const noRate = new CurrencyConverter({ ...SAMPLE_RATES, btcEur: 0 });
    expect(computeBtcConversion('500', 'EUR', noRate)).toBeNull();
  });
});

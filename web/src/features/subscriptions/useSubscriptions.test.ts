import { describe, it, expect } from 'vitest';
import { monthlyTotalForDisplay } from './useSubscriptions';
import { sampleSubscriptions } from './repository';
import { CurrencyConverter, type ExchangeRates } from '../../core/currency';

const rates: ExchangeRates = {
  eurUsd: 1.0825,
  btcEur: 58234.5,
  btcUsd: 63038.85,
  fetchedAt: Date.now(),
};

describe('monthlyTotalForDisplay', () => {
  it('sample data (Netflix €12.99 + Spotify €10.99 + iCloud+ €29.99/yr) -> €26.48', () => {
    const converter = new CurrencyConverter(rates);
    // 1299 + 1099 + monthly(2999 yearly) = 1299 + 1099 + 250 = 2648 cents = €26.48
    expect(monthlyTotalForDisplay(sampleSubscriptions, 'EUR', converter)).toBe(2648);
  });

  it('empty list -> 0 (no NaN)', () => {
    const converter = new CurrencyConverter(rates);
    expect(monthlyTotalForDisplay([], 'EUR', converter)).toBe(0);
  });
});

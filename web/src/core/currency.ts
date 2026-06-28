// TS mirror of Domain/Money.swift CurrencyCode + ExchangeRates + CurrencyConverter
// (docs/13 §2). Money is Int64 minor units; in TS we use integer `number` for minor
// units (max sats for the 21M BTC supply = 2.1e15 < Number.MAX_SAFE_INTEGER = 9.007e15).

/** ISO-ish currency code. BTC's "minor unit" is the satoshi (1e8 per BTC). */
export type CurrencyCode = 'EUR' | 'USD' | 'BTC';

/** Satoshis in one bitcoin. */
export const satsPerBTC = 100_000_000;

/** Number of fractional digits in one major unit (cents = 2, sats = 8). */
export function minorUnitDigits(currency: CurrencyCode): number {
  return currency === 'BTC' ? 8 : 2;
}

/** Minor units in one major unit: 100 (cents) or 100_000_000 (satoshis). */
export function minorUnitsPerMajor(currency: CurrencyCode): number {
  return currency === 'BTC' ? satsPerBTC : 100;
}

export function currencySymbol(currency: CurrencyCode): string {
  switch (currency) {
    case 'EUR':
      return '€';
    case 'USD':
      return '$';
    case 'BTC':
      return '₿';
  }
}

// MARK: - Exchange rates & conversion (docs/13 §2)

/**
 * Canonical rate snapshot returned by the `market-data` Edge Function.
 * `eurUsd` = USD per 1 EUR; `btcEur` = EUR per 1 BTC; `btcUsd` = USD per 1 BTC.
 */
export interface ExchangeRates {
  eurUsd: number;
  btcEur: number;
  btcUsd: number;
  /** ISO8601 timestamp (ms epoch) the rates were fetched. */
  fetchedAt: number;
}

export type ConversionError = { kind: 'rateUnavailable'; from: CurrencyCode; to: CurrencyCode };

/** Rates are shown with a staleness indicator past 24h but still used (docs/13 §2.5). */
export function ratesAreStale(rates: ExchangeRates, now: number, maxAgeMs = 86_400_000): boolean {
  return now - rates.fetchedAt > maxAgeMs;
}

/**
 * Display-only currency conversion. NEVER mutates a stored amount — returns a new
 * minor-unit amount in the target currency (docs/13 §2; fixes Substimate's
 * pre-store-conversion bug). All three EUR/USD/BTC pairs carried; triangulation table.
 */
export class CurrencyConverter {
  constructor(public readonly rates: ExchangeRates) {}

  /** Target major units per 1 source major unit, or null if unavailable. */
  rate(from: CurrencyCode, to: CurrencyCode): number | null {
    if (from === to) return 1;
    const inv = (d: number): number | null => (d <= 0 ? null : 1 / d);
    const { eurUsd, btcEur, btcUsd } = this.rates;
    switch (`${from}->${to}`) {
      case 'EUR->USD':
        return eurUsd > 0 ? eurUsd : null;
      case 'USD->EUR':
        return inv(eurUsd);
      case 'BTC->EUR':
        return btcEur > 0 ? btcEur : null;
      case 'EUR->BTC':
        return inv(btcEur);
      case 'BTC->USD':
        return btcUsd > 0 ? btcUsd : null;
      case 'USD->BTC':
        return inv(btcUsd);
      default:
        return null;
    }
  }

  /**
   * Convert `minorUnits` of `from` into the target currency's minor units.
   * HALF-UP to the target minor units. Throws nothing — returns a discriminated
   * result so callers can fall back to the stored source amount unconverted.
   */
  convert(
    minorUnits: number,
    from: CurrencyCode,
    to: CurrencyCode,
  ): { ok: true; minorUnits: number } | { ok: false; error: ConversionError } {
    if (from === to) return { ok: true, minorUnits };
    const r = this.rate(from, to);
    if (r === null) return { ok: false, error: { kind: 'rateUnavailable', from, to } };
    const sourceMajor = minorUnits / minorUnitsPerMajor(from);
    const targetMajor = sourceMajor * r;
    const scaled = targetMajor * minorUnitsPerMajor(to);
    return { ok: true, minorUnits: roundHalfUp(scaled) };
  }
}

// MARK: - BTC <-> satoshis (docs/13 §2.4)

/** HALF-UP whole sats from a BTC major-unit amount. A sat is indivisible. */
export function satsFromBTC(btc: number): number {
  return roundHalfUp(btc * satsPerBTC);
}

/** Exact BTC major units from a sat count. */
export function btcFromSats(sats: number): number {
  return sats / satsPerBTC;
}

/**
 * HALF-UP rounding (round-half-away-from-zero). All monetary amounts are
 * non-negative on parse, so this is exactly "round half up"; we still handle
 * negatives correctly for signed computed deltas (docs/13 conventions).
 */
export function roundHalfUp(value: number): number {
  // Guard tiny binary floating dust so e.g. 0.005 * 100 -> 0.5 rounds up, not down.
  const sign = value < 0 ? -1 : 1;
  const abs = Math.abs(value);
  const EPS = 1e-9;
  return sign * Math.floor(abs + 0.5 + EPS);
}

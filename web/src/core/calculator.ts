// BTC calculator compute model (M5-CALC) — pure, testable extraction of the
// fiat -> BTC/sats conversion + input validation that the Calculator view ran
// inline. Display-only and non-mutating (docs/13 §2): never stores or pre-converts.
// In production the rates come from the market-data Edge Function (ADR-0010).

import { CurrencyConverter, type CurrencyCode, btcFromSats } from './currency';
import { parseMoney } from './money';

/** Result of a successful fiat -> BTC conversion. All money is integer minor units. */
export interface BtcConversion {
  /** The parsed source amount, in the source fiat's minor units (cents). */
  fiatMinor: number;
  /** The converted amount in satoshis (BTC minor units). */
  sats: number;
  /** The converted amount in BTC major units (display-only float). */
  btc: number;
}

/**
 * Convert a user-entered fiat amount string into BTC/sats using `converter`.
 * Returns `null` when the input is invalid (empty, negative, non-numeric, or
 * over-precision for the fiat) or when the rate is unavailable — mirroring the
 * view's "Enter a valid amount." fallback. Pure: no state, no mutation.
 */
export function computeBtcConversion(
  amountText: string,
  fiat: CurrencyCode,
  converter: CurrencyConverter,
): BtcConversion | null {
  let minor: number;
  try {
    minor = parseMoney(amountText, fiat);
  } catch {
    return null;
  }
  const sats = converter.convert(minor, fiat, 'BTC');
  if (!sats.ok) return null;
  return {
    fiatMinor: minor,
    sats: sats.minorUnits,
    btc: btcFromSats(sats.minorUnits),
  };
}

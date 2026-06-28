// TS mirror of Domain/Money.swift parse/format (docs/13 §1.6, §1.7).
// Money is Int64 minor units + a CurrencyCode. Never floating-point money.

import {
  type CurrencyCode,
  minorUnitDigits,
  minorUnitsPerMajor,
  roundHalfUp,
} from './currency';

export type MoneyErrorKind =
  | 'negativeAmount'
  | 'tooManyFractionalDigits'
  | 'invalidNumber'
  | 'overflow';

export class MoneyError extends Error {
  constructor(
    public readonly kind: MoneyErrorKind,
    public readonly allowed?: number,
  ) {
    super(kind);
    this.name = 'MoneyError';
  }
}

const MAX_SAFE_MINOR = Number.MAX_SAFE_INTEGER; // 9.007e15 — comfortably above 21M BTC in sats

/**
 * Parse an already-locale-normalized canonical decimal string (POSIX `.`
 * separator, e.g. "12.99", "0.00050000") into integer minor units.
 * HALF-UP rounding; rejects negatives, over-precision, non-numbers, and overflow.
 * Locale grouping (commas, "1.234,56") is the caller's job — see normalizeNumberString.
 */
export function parseMoney(input: string, currency: CurrencyCode): number {
  const trimmed = input.trim();
  if (trimmed.length === 0) throw new MoneyError('invalidNumber');
  if (trimmed.startsWith('-')) throw new MoneyError('negativeAmount');

  // Strict numeric form: optional leading + then digits, optional single `.` + digits.
  if (!/^\+?\d*(\.\d+)?$/.test(trimmed) || !/\d/.test(trimmed)) {
    throw new MoneyError('invalidNumber');
  }

  const dotIndex = trimmed.indexOf('.');
  if (dotIndex >= 0) {
    const frac = trimmed.length - dotIndex - 1;
    if (frac > minorUnitDigits(currency)) {
      throw new MoneyError('tooManyFractionalDigits', minorUnitDigits(currency));
    }
  }

  const value = Number(trimmed);
  if (!Number.isFinite(value)) throw new MoneyError('invalidNumber');
  if (value < 0) throw new MoneyError('negativeAmount');

  const scaled = value * minorUnitsPerMajor(currency);
  const minor = roundHalfUp(scaled);
  if (minor > MAX_SAFE_MINOR) throw new MoneyError('overflow');
  return minor;
}

/** Major-unit decimal value (for conversion / formatting only). */
export function majorValue(minorUnits: number, currency: CurrencyCode): number {
  return minorUnits / minorUnitsPerMajor(currency);
}

/**
 * Locale-aware display string. BTC renders whole sats with grouping + " sats";
 * EUR/USD use Intl currency formatting with exactly the currency's fraction digits.
 */
export function formatMoney(
  minorUnits: number,
  currency: CurrencyCode,
  locale?: string,
): string {
  if (currency === 'BTC') {
    const grouped = new Intl.NumberFormat(locale ?? 'en-US', {
      maximumFractionDigits: 0,
    }).format(minorUnits);
    return `${grouped} sats`;
  }
  const digits = minorUnitDigits(currency);
  const resolvedLocale = locale ?? (currency === 'EUR' ? 'de-DE' : 'en-US');
  return new Intl.NumberFormat(resolvedLocale, {
    style: 'currency',
    currency,
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(majorValue(minorUnits, currency));
}

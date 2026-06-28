import { describe, it, expect } from 'vitest';
import { parseMoney, formatMoney, MoneyError } from './money';

// Worked vectors mirror the Swift Domain tests (docs/13 §1.6, §1.7).

describe('parseMoney', () => {
  it('T1.6a parses basic EUR', () => {
    expect(parseMoney('12.99', 'EUR')).toBe(1299);
  });

  it('T1.6b parses basic USD', () => {
    expect(parseMoney('4.00', 'USD')).toBe(400);
  });

  it('T1.6c parses BTC sats', () => {
    expect(parseMoney('0.00050000', 'BTC')).toBe(50000);
  });

  it('T1.6i parses single-decimal EUR', () => {
    expect(parseMoney('12.5', 'EUR')).toBe(1250);
  });

  it('T1.6d rejects too many fractional digits (EUR)', () => {
    expect(() => parseMoney('12.999', 'EUR')).toThrowError(MoneyError);
    try {
      parseMoney('12.999', 'EUR');
    } catch (e) {
      expect((e as MoneyError).kind).toBe('tooManyFractionalDigits');
      expect((e as MoneyError).allowed).toBe(2);
    }
  });

  it('T1.6e rejects too many fractional digits (BTC)', () => {
    expect(() => parseMoney('0.000000001', 'BTC')).toThrowError(MoneyError);
  });

  it('T1.6f rejects negative', () => {
    try {
      parseMoney('-1.00', 'EUR');
      throw new Error('should have thrown');
    } catch (e) {
      expect((e as MoneyError).kind).toBe('negativeAmount');
    }
  });

  it('T1.6g rejects invalid / empty', () => {
    expect(() => parseMoney('abc', 'EUR')).toThrowError(MoneyError);
    expect(() => parseMoney('', 'EUR')).toThrowError(MoneyError);
    expect(() => parseMoney('1.2.3', 'EUR')).toThrowError(MoneyError);
  });

  it('handles zero', () => {
    expect(parseMoney('0', 'EUR')).toBe(0);
    expect(parseMoney('0.00', 'EUR')).toBe(0);
  });
});

describe('formatMoney', () => {
  it('T1.7b formats USD in en-US', () => {
    expect(formatMoney(400, 'USD', 'en-US')).toBe('$4.00');
  });

  it('T1.7c formats BTC sats with grouping', () => {
    expect(formatMoney(12_345_678, 'BTC')).toBe('12,345,678 sats');
  });

  it('formats EUR with two fraction digits', () => {
    // de-DE renders "12,99 €"; assert the digits + symbol are present regardless of NBSP.
    const s = formatMoney(1299, 'EUR', 'de-DE');
    expect(s).toContain('12,99');
    expect(s).toContain('€');
  });
});

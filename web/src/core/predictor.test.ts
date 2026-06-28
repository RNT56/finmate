import { describe, it, expect } from 'vitest';
import { predict, inferCategory, normalizeNumberString } from './predictor';
import { parseMoney, MoneyError } from './money';

// Worked vectors mirror the Swift Domain tests (docs/13 §10, §9.1).

describe('predict / inferCategory', () => {
  it('github -> Coding category', () => {
    expect(inferCategory('github')).toBe('Coding');
    expect(predict('github')?.category).toBe('Coding');
  });

  it('exact match prefills seed', () => {
    const p = predict('netflix');
    expect(p?.category).toBe('Streaming');
    expect(p?.suggestedAmountMinor).toBe(1299);
    expect(p?.vendorURL).toBe('netflix.com');
  });

  it('substring match wins (e.g. "my netflix")', () => {
    const p = predict('my netflix account');
    expect(p?.suggestedAmountMinor).toBe(1299);
    expect(p?.category).toBe('Streaming');
  });

  it('unknown name still infers Other with no prefill', () => {
    const p = predict('zzz unknown service');
    expect(p?.category).toBe('Other');
    expect(p?.suggestedAmountMinor).toBeNull();
    expect(p?.vendorURL).toBeNull();
  });

  it('names shorter than 2 chars never predict', () => {
    expect(predict('a')).toBeNull();
    expect(predict(' ')).toBeNull();
    expect(predict('')).toBeNull();
  });

  it('AI Chat keywords', () => {
    expect(inferCategory('Claude Pro')).toBe('AI Chat');
    expect(inferCategory('ChatGPT Plus')).toBe('AI Chat');
  });
});

describe('normalizeNumberString + parseMoney (locale-aware)', () => {
  it('"1.234,56" (European) -> 123456 cents', () => {
    expect(parseMoney(normalizeNumberString('1.234,56'), 'EUR')).toBe(123456);
  });

  it('"1,234.56" (US) -> 123456 cents', () => {
    expect(parseMoney(normalizeNumberString('1,234.56'), 'EUR')).toBe(123456);
  });

  it('"12,99" lone comma decimal -> 1299 cents', () => {
    expect(parseMoney(normalizeNumberString('12,99'), 'EUR')).toBe(1299);
  });

  it('rejects ambiguous "1,234" (single sep, 3 trailing digits)', () => {
    expect(() => parseMoney(normalizeNumberString('1,234'), 'EUR')).toThrowError(MoneyError);
  });
});

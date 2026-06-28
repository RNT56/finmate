// CSV importer tests — SAME vectors as the Swift suite (docs/13 §9.4–9.5).
// Tokenizer, header aliases, locale-aware amount parsing, per-row validation.

import { describe, it, expect } from 'vitest';
import {
  tokenizeCSV,
  parseSubscriptionsCSV,
  parseSubscriptionsCSVWithMapping,
  analyzeHeader,
  type ColumnMapping,
} from './csvImport';

describe('tokenizeCSV (RFC-4180-lite)', () => {
  it('splits simple comma rows', () => {
    expect(tokenizeCSV('a,b,c')).toEqual([['a', 'b', 'c']]);
  });

  it('keeps a quoted field containing a comma as ONE field', () => {
    const rows = tokenizeCSV('name,amount\n"Acme, Inc",10.00');
    expect(rows[1]).toEqual(['Acme, Inc', '10.00']);
  });

  it('unescapes doubled quotes inside a quoted field', () => {
    const rows = tokenizeCSV('"a ""b"" c"');
    expect(rows[0]).toEqual(['a "b" c']);
  });

  it('handles CRLF and LF line breaks alike', () => {
    expect(tokenizeCSV('a,b\r\nc,d\ne,f')).toEqual([
      ['a', 'b'],
      ['c', 'd'],
      ['e', 'f'],
    ]);
  });
});

describe('parseSubscriptionsCSV — 3-row vector (valid / bad amount / bad currency)', () => {
  const csv = [
    'name,amount,currency,billing_period,payment_method',
    'Netflix,12.99,EUR,monthly,credit_card',
    'BadAmount,abc,USD,monthly,credit_card',
    'BadCurrency,9.99,GBP,monthly,credit_card',
  ].join('\n');

  const preview = parseSubscriptionsCSV(csv);

  it('keeps exactly the one valid row', () => {
    expect(preview.totalRows).toBe(3);
    expect(preview.valid).toHaveLength(1);
    expect(preview.valid[0].name).toBe('Netflix');
    expect(preview.valid[0].amountMinor).toBe(1299);
    expect(preview.valid[0].currency).toBe('EUR');
    expect(preview.valid[0].billingPeriod).toBe('monthly');
    expect(preview.valid[0].paymentMethod).toBe('credit_card');
  });

  it('reports an amount error on row 2 and a currency error on row 3', () => {
    const row2 = preview.errors.filter((e) => e.row === 2);
    const row3 = preview.errors.filter((e) => e.row === 3);
    expect(row2.some((e) => e.field === 'amount')).toBe(true);
    expect(row3.some((e) => e.field === 'currency')).toBe(true);
  });
});

describe('parseSubscriptionsCSV — quoted comma field', () => {
  it('parses a quoted name containing a comma as one field', () => {
    const csv = 'name,amount\n"Acme, Inc",10.00';
    const preview = parseSubscriptionsCSV(csv);
    expect(preview.valid).toHaveLength(1);
    expect(preview.valid[0].name).toBe('Acme, Inc');
  });
});

describe('parseSubscriptionsCSV — European amount', () => {
  it('parses "1.234,56" to 123456 minor units', () => {
    const csv = 'name,amount\nThing,"1.234,56"';
    const preview = parseSubscriptionsCSV(csv);
    expect(preview.valid).toHaveLength(1);
    expect(preview.valid[0].amountMinor).toBe(123456);
  });
});

describe('parseSubscriptionsCSV — missing name', () => {
  it('errors a row whose name is blank', () => {
    const csv = 'name,amount\n,9.99';
    const preview = parseSubscriptionsCSV(csv);
    expect(preview.valid).toHaveLength(0);
    expect(preview.errors.some((e) => e.row === 1 && e.field === 'name')).toBe(true);
  });
});

describe('parseSubscriptionsCSV — header aliases', () => {
  it('maps monthly_cost -> amount and service -> name', () => {
    const csv = 'service,monthly_cost\nDropbox,11.99';
    const preview = parseSubscriptionsCSV(csv);
    expect(preview.valid).toHaveLength(1);
    expect(preview.valid[0].name).toBe('Dropbox');
    expect(preview.valid[0].amountMinor).toBe(1199);
  });

  it('maps url/website -> vendor_url and ccy -> currency', () => {
    const csv = 'title,price,ccy,website\nNotion,8.00,USD,notion.so';
    const preview = parseSubscriptionsCSV(csv);
    expect(preview.valid).toHaveLength(1);
    expect(preview.valid[0].currency).toBe('USD');
    expect(preview.valid[0].vendorURL).toBe('notion.so');
  });
});

describe('parseSubscriptionsCSV — defaults & whole-file failure', () => {
  it('applies defaults (EUR / monthly / other / active) when columns are blank/absent', () => {
    const csv = 'name,amount\nMinimal,5.00';
    const sub = parseSubscriptionsCSV(csv).valid[0];
    expect(sub.currency).toBe('EUR');
    expect(sub.billingPeriod).toBe('monthly');
    expect(sub.paymentMethod).toBe('other');
    expect(sub.usageState).toBe('active');
    expect(sub.categoryName).toBe('Other');
  });

  it('fails the whole file (row 0) when a required column is missing', () => {
    const csv = 'name,currency\nNetflix,EUR';
    const preview = parseSubscriptionsCSV(csv);
    expect(preview.valid).toHaveLength(0);
    expect(preview.errors).toHaveLength(1);
    expect(preview.errors[0].row).toBe(0);
  });

  it('collects ALL errors for a single bad row', () => {
    const csv = 'name,amount,currency,billing_period\n,abc,GBP,fortnightly';
    const errs = parseSubscriptionsCSV(csv).errors.filter((e) => e.row === 1);
    const fields = new Set(errs.map((e) => e.field));
    expect(fields.has('name')).toBe(true);
    expect(fields.has('amount')).toBe(true);
    expect(fields.has('currency')).toBe(true);
    expect(fields.has('billing_period')).toBe(true);
  });
});

// SAME vectors as the Swift explicit-mapping suite (header analysis + override).
describe('analyzeHeader + explicit mapping', () => {
  it('reports the raw tokens and the alias auto-mapping', () => {
    const csv = 'Service, Monthly Cost ,CCY\nNetflix,12.99,EUR';
    const { headers, autoMapping } = analyzeHeader(csv);
    expect(headers).toEqual(['Service', 'Monthly Cost', 'CCY']);
    expect(autoMapping.name).toBe(0);
    expect(autoMapping.amount).toBe(1);
    expect(autoMapping.currency).toBe(2);
    expect(autoMapping.usage_state).toBeUndefined();
  });

  it('matches the auto path on a clean, alias-detectable CSV', () => {
    const csv = [
      'name,amount,currency,billing_period,payment_method',
      'Netflix,12.99,EUR,monthly,credit_card',
      'BadAmount,abc,EUR,monthly,paypal',
      'BadCurrency,5.00,GBP,monthly,credit_card',
    ].join('\n');
    const auto = parseSubscriptionsCSV(csv);
    const explicit = parseSubscriptionsCSVWithMapping(csv, analyzeHeader(csv).autoMapping);
    expect(explicit.valid.map((s) => s.name)).toEqual(auto.valid.map((s) => s.name));
    expect(explicit.valid.map((s) => s.amountMinor)).toEqual(auto.valid.map((s) => s.amountMinor));
    expect(explicit.errors).toEqual(auto.errors);
    expect(explicit.valid).toHaveLength(1);
    expect(explicit.valid[0].amountMinor).toBe(1299);
  });

  it('requires an explicit mapping when headers do NOT auto-detect', () => {
    const csv = 'col_a,col_b,col_c\nNetflix,12.99,EUR\nSpotify,7.99,USD';
    const auto = parseSubscriptionsCSV(csv);
    expect(auto.valid).toHaveLength(0); // whole-file failure: no name/amount column
    expect(analyzeHeader(csv).autoMapping).toEqual({});

    const mapping: ColumnMapping = { name: 0, amount: 1, currency: 2 };
    const explicit = parseSubscriptionsCSVWithMapping(csv, mapping);
    expect(explicit.totalRows).toBe(2);
    expect(explicit.valid).toHaveLength(2);
    expect(explicit.valid[0].name).toBe('Netflix');
    expect(explicit.valid[0].amountMinor).toBe(1299);
    expect(explicit.valid[0].currency).toBe('EUR');
    expect(explicit.valid[1].amountMinor).toBe(799);
    expect(explicit.valid[1].currency).toBe('USD');
  });

  it('handles multi-currency under an explicit mapping (EUR/USD cents, BTC sats)', () => {
    const csv = 'X,Y,Z\nNetflix,12.99,EUR\nGitHub,100,USD\nWallet,0.00012345,BTC';
    const explicit = parseSubscriptionsCSVWithMapping(csv, { name: 0, amount: 1, currency: 2 });
    expect(explicit.valid).toHaveLength(3);
    expect(explicit.valid[0].amountMinor).toBe(1299);
    expect(explicit.valid[1].amountMinor).toBe(10000);
    expect(explicit.valid[1].currency).toBe('USD');
    expect(explicit.valid[2].amountMinor).toBe(12345);
    expect(explicit.valid[2].currency).toBe('BTC');
  });

  it('collects dirty-row errors under an explicit mapping', () => {
    const csv = ['a,b,c', 'Netflix,12.99,EUR', ',9.99,EUR', 'Spotify,abc,EUR', 'GitHub,5.00,GBP'].join(
      '\n'
    );
    const explicit = parseSubscriptionsCSVWithMapping(csv, { name: 0, amount: 1, currency: 2 });
    expect(explicit.totalRows).toBe(4);
    expect(explicit.valid).toHaveLength(1);
    expect(explicit.errors.some((e) => e.row === 2 && e.field === 'name')).toBe(true);
    expect(explicit.errors.some((e) => e.row === 3 && e.field === 'amount')).toBe(true);
    expect(explicit.errors.some((e) => e.row === 4 && e.field === 'currency')).toBe(true);
  });

  it('honors remapped columns and ignores unmapped fields (default applies)', () => {
    const csv = 'name,amount,currency\nignore-me,8.50,Spotify';
    const explicit = parseSubscriptionsCSVWithMapping(csv, { name: 2, amount: 1 });
    expect(explicit.valid).toHaveLength(1);
    expect(explicit.valid[0].name).toBe('Spotify'); // from col 2
    expect(explicit.valid[0].amountMinor).toBe(850);
    expect(explicit.valid[0].currency).toBe('EUR'); // unmapped -> default
  });
});

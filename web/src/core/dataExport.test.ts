import { describe, it, expect } from 'vitest';
import {
  buildExportBundle,
  serializeExportBundle,
  bundleCurrencies,
  EXPORT_SCHEMA_VERSION,
  EXPORT_FILENAME,
  type ExportSources,
} from './dataExport';
import { defaultPreferences } from './preferences';
import type { FinancialAsset } from './assets';
import type {
  IncomeSource,
  FixedExpense,
  VariableExpense,
} from '../features/cashflow/types';
import type { Subscription } from '../features/subscriptions/types';

// docs/07 §9.3 — data export. The contract under test:
//   * money stays RAW minor units + ISO currency (never pre-formatted / converted)
//   * schemaVersion + exportedAt at the top of the bundle
//   * every owned entity is present and round-trips through JSON unchanged.

const subscription: Subscription = {
  id: 'sub-1',
  name: 'Netflix',
  vendorURL: null,
  icon: null,
  amountMinor: 1299, // €12.99 — stays as 1299, never "€12.99"
  currency: 'EUR',
  billingPeriod: 'monthly',
  paymentMethod: 'credit_card',
  categoryName: 'Entertainment',
  usageState: 'active',
  favorite: false,
  sortOrder: 0,
  startDate: '2026-01-01',
};

const income: IncomeSource = {
  id: 'inc-1',
  name: 'Salary',
  amountMinor: 350000, // $3,500.00
  currency: 'USD',
  frequency: 'monthly',
  nextPayment: '2026-07-01',
};

const fixed: FixedExpense = {
  id: 'fix-1',
  name: 'Rent',
  amountMinor: 120000,
  currency: 'EUR',
  billingPeriod: 'monthly',
  categoryId: '00000000-0000-0000-0000-0000000000C1',
  dueDate: '2026-07-01',
};

const variable: VariableExpense = {
  id: 'var-1',
  name: 'Groceries',
  amountMinor: 4567,
  currency: 'EUR',
  categoryId: '00000000-0000-0000-0000-0000000000C2',
  spentOn: '2026-06-15',
};

const asset: FinancialAsset = {
  id: 'asset-btc',
  name: 'Bitcoin',
  type: 'crypto',
  currency: 'BTC',
  quantity: 0.5,
  purchasePriceMinor: 50_000_000, // 0.5 BTC in sats — raw, not formatted
  currentPriceMinor: 100_000_000,
  valueMinor: 50_000_000,
  notes: 'Cold storage',
};

function sources(): ExportSources {
  return {
    subscriptions: async () => [subscription],
    incomeSources: async () => [income],
    fixedExpenses: async () => [fixed],
    variableExpenses: async () => [variable],
    financialAssets: async () => [asset],
    preferences: () => defaultPreferences,
  };
}

const FIXED_NOW = new Date('2026-06-28T12:00:00.000Z');

describe('buildExportBundle — shape', () => {
  it('stamps the schema version and an ISO exportedAt', async () => {
    const bundle = await buildExportBundle(sources(), FIXED_NOW);
    expect(bundle.schemaVersion).toBe(EXPORT_SCHEMA_VERSION);
    expect(bundle.exportedAt).toBe('2026-06-28T12:00:00.000Z');
  });

  it('includes every owned entity collection', async () => {
    const bundle = await buildExportBundle(sources(), FIXED_NOW);
    expect(bundle.data.subscriptions).toHaveLength(1);
    expect(bundle.data.incomeSources).toHaveLength(1);
    expect(bundle.data.fixedExpenses).toHaveLength(1);
    expect(bundle.data.variableExpenses).toHaveLength(1);
    expect(bundle.data.financialAssets).toHaveLength(1);
  });

  it('carries preferences in a separate field (not among financial records)', async () => {
    const bundle = await buildExportBundle(sources(), FIXED_NOW);
    expect(bundle.preferences).toEqual(defaultPreferences);
    expect('preferences' in bundle.data).toBe(false);
  });

  it('deep-copies entities so the bundle never aliases live repo state', async () => {
    const src = sources();
    const original = (await src.subscriptions())[0];
    const bundle = await buildExportBundle(src, FIXED_NOW);
    bundle.data.subscriptions[0].name = 'MUTATED';
    expect(original.name).toBe('Netflix');
  });
});

describe('buildExportBundle — money stays minor units', () => {
  it('exports amounts as raw Int64 minor units, never pre-formatted', async () => {
    const bundle = await buildExportBundle(sources(), FIXED_NOW);
    expect(bundle.data.subscriptions[0].amountMinor).toBe(1299);
    expect(bundle.data.incomeSources[0].amountMinor).toBe(350000);
    expect(bundle.data.fixedExpenses[0].amountMinor).toBe(120000);
    expect(bundle.data.variableExpenses[0].amountMinor).toBe(4567);
  });

  it('keeps the ISO currency code alongside each amount (no display conversion)', async () => {
    const bundle = await buildExportBundle(sources(), FIXED_NOW);
    expect(bundle.data.subscriptions[0].currency).toBe('EUR');
    expect(bundle.data.incomeSources[0].currency).toBe('USD');
    expect(bundle.data.financialAssets[0].currency).toBe('BTC');
    // Multiple currencies survive — entities were NOT collapsed to one display currency.
    expect(bundle.data.financialAssets[0].valueMinor).toBe(50_000_000);
    expect(bundleCurrencies(bundle)).toEqual(new Set(['EUR', 'USD', 'BTC']));
  });

  it('serialized JSON contains no formatted-money strings', async () => {
    const bundle = await buildExportBundle(sources(), FIXED_NOW);
    const json = serializeExportBundle(bundle);
    expect(json).not.toContain('€');
    expect(json).not.toContain('$');
    expect(json).not.toContain('12.99');
    expect(json).toContain('"amountMinor": 1299');
    expect(json).toContain('"currency": "EUR"');
  });

  it('round-trips losslessly through JSON.parse', async () => {
    const bundle = await buildExportBundle(sources(), FIXED_NOW);
    const roundTripped = JSON.parse(serializeExportBundle(bundle));
    expect(roundTripped).toEqual(bundle);
  });
});

describe('export filename', () => {
  it('is finmate-export.json', () => {
    expect(EXPORT_FILENAME).toBe('finmate-export.json');
  });
});

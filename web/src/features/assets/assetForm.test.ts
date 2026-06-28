import { describe, expect, it } from 'vitest';
import { applyTransaction, type FinancialAsset } from '../../core/assets';
import {
  buildAsset,
  buildTransaction,
  newAssetId,
  parseQuantity,
  type AssetFormDraft,
  type TransactionFormDraft,
} from './assetForm';

function assetDraft(overrides: Partial<AssetFormDraft> = {}): AssetFormDraft {
  return {
    name: 'Bitcoin',
    type: 'crypto',
    currency: 'EUR',
    quantity: '0.5',
    costBasis: '20000',
    unitPrice: '50000',
    notes: '',
    ...overrides,
  };
}

function txnDraft(overrides: Partial<TransactionFormDraft> = {}): TransactionFormDraft {
  return { kind: 'buy', quantity: '0.5', price: '50000', fees: '', ...overrides };
}

describe('parseQuantity', () => {
  it('parses a fractional quantity', () => {
    expect(parseQuantity('0.5')).toEqual({ ok: true, value: 0.5 });
  });
  it('rejects empty, non-numeric, and negative', () => {
    expect(parseQuantity('').ok).toBe(false);
    expect(parseQuantity('abc').ok).toBe(false);
    expect(parseQuantity('-1').ok).toBe(false);
  });
});

describe('buildAsset', () => {
  it('builds an asset and derives valueMinor = quantity × unit price', () => {
    const r = buildAsset(assetDraft(), 'asset-1');
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.purchasePriceMinor).toBe(2_000_000);
      expect(r.value.currentPriceMinor).toBe(5_000_000);
      expect(r.value.valueMinor).toBe(2_500_000); // 0.5 × 5_000_000
      expect(r.value.notes).toBeNull();
    }
  });

  it('rejects an empty name', () => {
    const r = buildAsset(assetDraft({ name: ' ' }), 'asset-1');
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toMatch(/name/i);
  });

  it('rejects an invalid quantity', () => {
    const r = buildAsset(assetDraft({ quantity: 'x' }), 'asset-1');
    expect(r.ok).toBe(false);
  });

  it('rejects a negative cost basis (money parser)', () => {
    const r = buildAsset(assetDraft({ costBasis: '-5' }), 'asset-1');
    expect(r.ok).toBe(false);
  });

  it('keeps trimmed notes', () => {
    const r = buildAsset(assetDraft({ notes: '  cold storage  ' }), 'asset-1');
    expect(r.ok && r.value.notes).toBe('cold storage');
  });
});

describe('buildTransaction', () => {
  it('builds a buy with quantity, price, and fees in minor units', () => {
    const r = buildTransaction(txnDraft({ quantity: '0.5', price: '50000', fees: '10' }), 'EUR');
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value).toEqual({ kind: 'buy', quantity: 0.5, priceMinor: 5_000_000, feesMinor: 1000 });
    }
  });

  it('requires a positive quantity for buy/sell', () => {
    expect(buildTransaction(txnDraft({ kind: 'sell', quantity: '0' }), 'EUR').ok).toBe(false);
    expect(buildTransaction(txnDraft({ kind: 'buy', quantity: '' }), 'EUR').ok).toBe(false);
  });

  it('allows dividend/other with no quantity', () => {
    const r = buildTransaction(txnDraft({ kind: 'dividend', quantity: '', price: '52000' }), 'EUR');
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.quantity).toBe(0);
  });

  it('feeds applyTransaction to recompute value/gain (buy increases position)', () => {
    const asset: FinancialAsset = {
      id: 'asset-btc',
      name: 'Bitcoin',
      type: 'crypto',
      currency: 'EUR',
      quantity: 0.5,
      purchasePriceMinor: 2_000_000,
      currentPriceMinor: 5_000_000,
      valueMinor: 2_500_000,
      notes: null,
    };
    const built = buildTransaction(txnDraft({ kind: 'buy', quantity: '0.5', price: '60000' }), 'EUR');
    expect(built.ok).toBe(true);
    if (built.ok) {
      const next = applyTransaction(asset, built.value);
      expect(next.quantity).toBe(1);
      // costBasis += qty × priceMinor = 0.5 × 6_000_000 = 3_000_000
      expect(next.purchasePriceMinor).toBe(2_000_000 + 3_000_000);
      expect(next.currentPriceMinor).toBe(6_000_000);
      expect(next.valueMinor).toBe(6_000_000); // 1 × 6_000_000
    }
  });
});

describe('newAssetId', () => {
  it('prefixes the id', () => {
    expect(newAssetId()).toMatch(/^asset-\d+$/);
  });
});

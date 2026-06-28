// TS mirror of the Domain asset math (docs/13; docs/05 §3.7–3.8; ADR-0015).
// Average-cost basis (ADR-0015):
//   purchasePriceMinor = TOTAL cost basis (minor units, asset.currency)
//   currentPriceMinor  = latest PER-UNIT price (minor units, asset.currency)
//   valueMinor         = current TOTAL value (minor units, asset.currency)
//   unrealized gain    = valueMinor − purchasePriceMinor
// Portfolio aggregation converts each asset's value/cost to a display currency via
// the existing CurrencyConverter (display-only, non-mutating — docs/13 §2). Money is
// Int64 minor units; in TS integer `number` (well below Number.MAX_SAFE_INTEGER).

import type { CurrencyCode } from './currency';
import { CurrencyConverter, roundHalfUp } from './currency';

/** Asset class (docs/05 §3.7 financial_assets.type). Mirrors Swift `AssetType`. */
export type AssetType = 'crypto' | 'stock' | 'etf' | 'cash' | 'other';

export const allAssetTypes: AssetType[] = ['crypto', 'stock', 'etf', 'cash', 'other'];

/** Human label for an asset type. */
export function assetTypeLabel(type: AssetType): string {
  switch (type) {
    case 'crypto':
      return 'Crypto';
    case 'stock':
      return 'Stock';
    case 'etf':
      return 'ETF';
    case 'cash':
      return 'Cash';
    case 'other':
      return 'Other';
  }
}

/** A held financial asset (docs/05 §3.7). Mirrors Swift `FinancialAsset`. */
export interface FinancialAsset {
  id: string;
  name: string;
  type: AssetType;
  currency: CurrencyCode;
  /** Units held (shares, coins, …). Fractional allowed. */
  quantity: number;
  /** TOTAL cost basis in minor units (ADR-0015). */
  purchasePriceMinor: number;
  /** Latest PER-UNIT price in minor units (ADR-0015). */
  currentPriceMinor: number;
  /** Current TOTAL value in minor units (ADR-0015). */
  valueMinor: number;
  notes: string | null;
}

/** A buy/sell/dividend/other transaction on an asset (docs/05 §3.8). */
export type AssetTransactionKind = 'buy' | 'sell' | 'dividend' | 'other';

export interface AssetTransaction {
  id: string;
  assetId: string;
  kind: AssetTransactionKind;
  quantity: number;
  /** PER-UNIT price in minor units. */
  priceMinor: number;
  feesMinor: number;
  /** ISO date the transaction occurred. */
  date: string;
  notes: string | null;
}

// MARK: - Average-cost transaction application (docs/02 §9; docs/13; ADR-0015)

/**
 * Apply a buy/sell/dividend/other transaction to an asset under AVERAGE-COST basis
 * (ADR-0015), returning a NEW asset (pure, non-mutating). Money stays integer minor
 * units; `currentPriceMinor` is the latest per-unit price and re-marks `valueMinor`.
 *
 *   buy   → quantity += qty; costBasis += qty*price + fees; mark to `price`.
 *   sell  → reduces quantity and removes cost basis at the *average* unit cost
 *           (so realized P/L is excluded from the remaining basis); mark to `price`.
 *   dividend / other → no quantity/basis change; only re-marks the per-unit price
 *           when a positive `priceMinor` is supplied.
 *
 * `valueMinor` is always recomputed as quantity × currentPriceMinor (HALF-UP), so the
 * portfolio value/gain recompute after every write. Quantity is clamped at ≥ 0 and a
 * fully-closed position resets the cost basis to 0.
 */
export function applyTransaction(
  asset: FinancialAsset,
  txn: { kind: AssetTransactionKind; quantity: number; priceMinor: number; feesMinor: number },
): FinancialAsset {
  const qty = Math.max(0, txn.quantity);
  const price = Math.max(0, txn.priceMinor);
  const fees = Math.max(0, txn.feesMinor);

  let quantity = asset.quantity;
  let costBasis = asset.purchasePriceMinor;
  let currentPrice = asset.currentPriceMinor;

  switch (txn.kind) {
    case 'buy': {
      quantity = asset.quantity + qty;
      costBasis = asset.purchasePriceMinor + qty * price + fees;
      if (price > 0) currentPrice = price;
      break;
    }
    case 'sell': {
      const avgUnitCost = asset.quantity > 0 ? asset.purchasePriceMinor / asset.quantity : 0;
      const sold = Math.min(qty, asset.quantity);
      quantity = asset.quantity - sold;
      // Remove basis proportionally at the average unit cost (realized P/L excluded).
      costBasis = quantity <= 0 ? 0 : asset.purchasePriceMinor - avgUnitCost * sold;
      if (price > 0) currentPrice = price;
      break;
    }
    case 'dividend':
    case 'other': {
      if (price > 0) currentPrice = price;
      break;
    }
  }

  const value = roundHalfUp(quantity * currentPrice);
  return {
    ...asset,
    quantity,
    purchasePriceMinor: roundHalfUp(costBasis),
    currentPriceMinor: roundHalfUp(currentPrice),
    valueMinor: value,
  };
}

// MARK: - Per-asset unrealized gain (ADR-0015)

/** Unrealized gain/loss in minor units: valueMinor − purchasePriceMinor. */
export function unrealizedGainMinor(asset: FinancialAsset): number {
  return asset.valueMinor - asset.purchasePriceMinor;
}

/** Unrealized gain as a fraction of cost basis; 0 when cost basis is 0. */
export function gainPct(asset: FinancialAsset): number {
  if (asset.purchasePriceMinor === 0) return 0;
  return unrealizedGainMinor(asset) / asset.purchasePriceMinor;
}

// MARK: - Portfolio totals (display-currency conversion, non-mutating)

/**
 * Convert `minorUnits` of `from` into `to`, contributing 0 when the rate is
 * unavailable and currencies differ (never silently guess; mirrors the
 * subscriptions roll-up convention).
 */
function convertOrSame(
  minorUnits: number,
  from: CurrencyCode,
  to: CurrencyCode,
  converter: CurrencyConverter,
): number {
  const converted = converter.convert(minorUnits, from, to);
  if (converted.ok) return converted.minorUnits;
  return from === to ? minorUnits : 0;
}

/** Σ convert(asset.value → displayCurrency), in minor units (docs/13 §2). */
export function portfolioValueMinor(
  assets: FinancialAsset[],
  displayCurrency: CurrencyCode,
  converter: CurrencyConverter,
): number {
  let total = 0;
  for (const a of assets) {
    total += convertOrSame(a.valueMinor, a.currency, displayCurrency, converter);
  }
  return total;
}

/** Σ convert(asset.cost-basis → displayCurrency), in minor units (docs/13 §2). */
export function portfolioCostBasisMinor(
  assets: FinancialAsset[],
  displayCurrency: CurrencyCode,
  converter: CurrencyConverter,
): number {
  let total = 0;
  for (const a of assets) {
    total += convertOrSame(a.purchasePriceMinor, a.currency, displayCurrency, converter);
  }
  return total;
}

/** Portfolio unrealized gain in `displayCurrency`: value − cost basis. */
export function portfolioGainMinor(
  assets: FinancialAsset[],
  displayCurrency: CurrencyCode,
  converter: CurrencyConverter,
): number {
  return (
    portfolioValueMinor(assets, displayCurrency, converter) -
    portfolioCostBasisMinor(assets, displayCurrency, converter)
  );
}

// MARK: - Distribution by asset type (reuses the category-distribution shape)

/** One slice of the by-type portfolio distribution. Mirrors Swift `AssetSlice`. */
export interface AssetSlice {
  type: AssetType;
  /** Converted total value in `displayCurrency` minor units. */
  totalMinor: number;
  count: number;
  /** Fraction of the grand total value (0…1). */
  share: number;
}

/**
 * Aggregate assets into descending-by-value slices by `AssetType`, each value
 * converted to `displayCurrency`. Mirrors `Analytics.categoryDistribution`
 * (docs/13 §5.1): grand-total share, ties broken by type name.
 */
export function assetDistribution(
  assets: FinancialAsset[],
  displayCurrency: CurrencyCode,
  converter: CurrencyConverter,
): AssetSlice[] {
  if (assets.length === 0) return [];
  const totals = new Map<AssetType, { sum: number; count: number }>();
  for (const a of assets) {
    const converted = convertOrSame(a.valueMinor, a.currency, displayCurrency, converter);
    const cur = totals.get(a.type) ?? { sum: 0, count: 0 };
    totals.set(a.type, { sum: cur.sum + converted, count: cur.count + 1 });
  }
  let grand = 0;
  for (const v of totals.values()) grand += v.sum;
  return Array.from(totals.entries())
    .map(([type, v]) => ({
      type,
      totalMinor: v.sum,
      count: v.count,
      share: grand === 0 ? 0 : v.sum / grand,
    }))
    .sort((a, b) => (a.totalMinor !== b.totalMinor ? b.totalMinor - a.totalMinor : a.type < b.type ? -1 : 1));
}

// Pure helpers that build/validate FinancialAsset + transaction inputs from raw form
// text. Money goes through the core parser (HALF-UP, rejects negatives / over-precision);
// quantity is parsed as a non-negative finite number. Unit-tested — no React, no I/O.

import { parseMoney, MoneyError } from '../../core/money';
import type { CurrencyCode } from '../../core/currency';
import type { AssetTransactionKind, AssetType, FinancialAsset } from '../../core/assets';

export type AssetBuildResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: string };

/** Raw text fields collected from the add/edit asset modal. */
export interface AssetFormDraft {
  name: string;
  type: AssetType;
  currency: CurrencyCode;
  /** Units held (e.g. "0.5", "10"). */
  quantity: string;
  /** TOTAL cost basis, major-unit string (e.g. "20000"). */
  costBasis: string;
  /** Latest PER-UNIT price, major-unit string (e.g. "50000"). */
  unitPrice: string;
  notes: string;
}

/** Raw text fields collected from the record-transaction modal. */
export interface TransactionFormDraft {
  kind: AssetTransactionKind;
  quantity: string;
  /** PER-UNIT price, major-unit string. */
  price: string;
  /** Fees, major-unit string ('' = 0). */
  fees: string;
}

function moneyErrorMessage(err: unknown): string {
  if (err instanceof MoneyError && err.kind === 'tooManyFractionalDigits') {
    return 'Enter a valid amount (max 2 decimals).';
  }
  return 'Enter a valid, non-negative amount.';
}

/** Parse a quantity string into a finite, non-negative number. */
export function parseQuantity(input: string): AssetBuildResult<number> {
  const trimmed = input.trim();
  if (trimmed === '') return { ok: false, error: 'Enter a quantity.' };
  const value = Number(trimmed);
  if (!Number.isFinite(value)) return { ok: false, error: 'Enter a valid quantity.' };
  if (value < 0) return { ok: false, error: 'Quantity cannot be negative.' };
  return { ok: true, value };
}

/** A stable id for a new asset; editing keeps the existing id. */
export function newAssetId(): string {
  return `asset-${Date.now()}`;
}

/**
 * Build a FinancialAsset from a draft. `valueMinor` is derived as
 * quantity × unitPrice (consistent with `applyTransaction`'s mark-to-market), so the
 * portfolio value/gain recompute correctly after the write.
 */
export function buildAsset(
  draft: AssetFormDraft,
  id: string,
): AssetBuildResult<FinancialAsset> {
  const name = draft.name.trim();
  if (!name) return { ok: false, error: 'Enter an asset name.' };

  const qty = parseQuantity(draft.quantity);
  if (!qty.ok) return qty;

  let costBasisMinor: number;
  let unitPriceMinor: number;
  try {
    costBasisMinor = draft.costBasis.trim() === '' ? 0 : parseMoney(draft.costBasis.trim(), draft.currency);
    unitPriceMinor = draft.unitPrice.trim() === '' ? 0 : parseMoney(draft.unitPrice.trim(), draft.currency);
  } catch (err) {
    return { ok: false, error: moneyErrorMessage(err) };
  }

  const valueMinor = Math.round(qty.value * unitPriceMinor);
  return {
    ok: true,
    value: {
      id,
      name,
      type: draft.type,
      currency: draft.currency,
      quantity: qty.value,
      purchasePriceMinor: costBasisMinor,
      currentPriceMinor: unitPriceMinor,
      valueMinor,
      notes: draft.notes.trim() === '' ? null : draft.notes.trim(),
    },
  };
}

/** Parsed, validated transaction inputs ready for `applyTransaction`. */
export interface TransactionInput {
  kind: AssetTransactionKind;
  quantity: number;
  priceMinor: number;
  feesMinor: number;
}

/** Build validated transaction inputs from a draft, in the asset's currency. */
export function buildTransaction(
  draft: TransactionFormDraft,
  currency: CurrencyCode,
): AssetBuildResult<TransactionInput> {
  // buy/sell move quantity, so they require a positive quantity; dividend/other
  // only re-mark the price and may carry no quantity.
  const requiresQuantity = draft.kind === 'buy' || draft.kind === 'sell';
  let quantity = 0;
  if (requiresQuantity) {
    const qty = parseQuantity(draft.quantity);
    if (!qty.ok) return qty;
    if (qty.value <= 0) return { ok: false, error: 'Enter a quantity greater than zero.' };
    quantity = qty.value;
  } else if (draft.quantity.trim() !== '') {
    const qty = parseQuantity(draft.quantity);
    if (!qty.ok) return qty;
    quantity = qty.value;
  }

  let priceMinor: number;
  let feesMinor: number;
  try {
    priceMinor = draft.price.trim() === '' ? 0 : parseMoney(draft.price.trim(), currency);
    feesMinor = draft.fees.trim() === '' ? 0 : parseMoney(draft.fees.trim(), currency);
  } catch (err) {
    return { ok: false, error: moneyErrorMessage(err) };
  }

  return { ok: true, value: { kind: draft.kind, quantity, priceMinor, feesMinor } };
}

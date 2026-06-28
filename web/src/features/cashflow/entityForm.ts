// Pure helpers that build/validate Income & Expense entities from raw form input.
// Shared by the add/edit modals; amount goes through the core money parser (HALF-UP,
// rejects negatives / over-precision). Unit-tested — no React, no I/O.

import { parseMoney, MoneyError } from '../../core/money';
import type { CurrencyCode } from '../../core/currency';
import type { BillingPeriod, IncomeFrequency } from '../../core/normalization';
import type { FixedExpense, IncomeSource, VariableExpense } from './types';

/** Raw text fields collected from an income/expense modal. */
export interface EntityFormDraft {
  name: string;
  amount: string;
  currency: CurrencyCode;
  /** Income frequency OR expense billing period, depending on the entity. */
  cadence: IncomeFrequency | BillingPeriod;
  /** Selected category id (FK to `categories`); '' = uncategorized. */
  categoryId: string;
  /** ISO date string (anchor / due / spent-on); '' = unscheduled where allowed. */
  date: string;
}

export type EntityKind = 'income' | 'fixed' | 'variable';

export type EntityBuildResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: string };

/** Friendly message for a money-parse failure, matching the Add-Subscription copy. */
function moneyErrorMessage(err: unknown): string {
  if (err instanceof MoneyError && err.kind === 'tooManyFractionalDigits') {
    return 'Enter a valid amount (max 2 decimals).';
  }
  return 'Enter a valid, non-negative amount.';
}

/** Parse the shared name + amount, returning the trimmed name and minor units. */
function parseNameAndAmount(
  draft: EntityFormDraft,
): EntityBuildResult<{ name: string; minor: number }> {
  const name = draft.name.trim();
  if (!name) return { ok: false, error: 'Enter a name.' };
  let minor: number;
  try {
    minor = parseMoney(draft.amount.trim(), draft.currency);
  } catch (err) {
    return { ok: false, error: moneyErrorMessage(err) };
  }
  if (minor <= 0) return { ok: false, error: 'Enter an amount greater than zero.' };
  return { ok: true, value: { name, minor } };
}

/** A stable id for a new entity (`prefix-<timestamp>`); editing keeps the existing id. */
export function newEntityId(prefix: string): string {
  return `${prefix}-${Date.now()}`;
}

/** Build an IncomeSource from a draft (id supplied for edit, generated for add). */
export function buildIncome(
  draft: EntityFormDraft,
  id: string,
): EntityBuildResult<IncomeSource> {
  const parsed = parseNameAndAmount(draft);
  if (!parsed.ok) return parsed;
  return {
    ok: true,
    value: {
      id,
      name: parsed.value.name,
      amountMinor: parsed.value.minor,
      currency: draft.currency,
      frequency: draft.cadence as IncomeFrequency,
      nextPayment: draft.date.trim() === '' ? null : draft.date,
    },
  };
}

/** Build a FixedExpense from a draft. */
export function buildFixed(
  draft: EntityFormDraft,
  id: string,
): EntityBuildResult<FixedExpense> {
  const parsed = parseNameAndAmount(draft);
  if (!parsed.ok) return parsed;
  return {
    ok: true,
    value: {
      id,
      name: parsed.value.name,
      amountMinor: parsed.value.minor,
      currency: draft.currency,
      billingPeriod: draft.cadence as BillingPeriod,
      categoryId: draft.categoryId.trim() === '' ? null : draft.categoryId,
      dueDate: draft.date.trim() === '' ? null : draft.date,
    },
  };
}

/** Build a VariableExpense from a draft (spentOn defaults to today when blank). */
export function buildVariable(
  draft: EntityFormDraft,
  id: string,
  today: string = new Date().toISOString().slice(0, 10),
): EntityBuildResult<VariableExpense> {
  const parsed = parseNameAndAmount(draft);
  if (!parsed.ok) return parsed;
  return {
    ok: true,
    value: {
      id,
      name: parsed.value.name,
      amountMinor: parsed.value.minor,
      currency: draft.currency,
      categoryId: draft.categoryId.trim() === '' ? null : draft.categoryId,
      spentOn: draft.date.trim() === '' ? today : draft.date,
    },
  };
}

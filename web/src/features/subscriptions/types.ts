// Domain mirror of Subscription (camelCase) + repository protocol.
// Mirrors Domain/Entities.swift + App/Sources/Subscriptions.swift.

import type { CurrencyCode } from '../../core/currency';
import type { BillingPeriod } from '../../core/normalization';
import { monthlyMinorUnits } from '../../core/normalization';
import type { PaymentMethod, UsageState } from '../../types/database';

export interface Subscription {
  id: string;
  name: string;
  vendorURL: string | null;
  icon: string | null;
  amountMinor: number;
  currency: CurrencyCode;
  billingPeriod: BillingPeriod;
  paymentMethod: PaymentMethod;
  categoryName: string;
  usageState: UsageState;
  favorite: boolean;
  sortOrder: number;
  /** ISO date the subscription's billing anchor started (docs/13 §11.1). */
  startDate: string;
}

/** Canonical monthly-equivalent minor units in the subscription's own currency. */
export function monthlyAmountMinor(sub: Subscription): number {
  return monthlyMinorUnits(sub.amountMinor, sub.billingPeriod);
}

/** Repository protocol — stores call this, never the SDK directly (docs/03). */
export interface SubscriptionRepository {
  all(): Promise<Subscription[]>;
  upsert(sub: Subscription): Promise<void>;
  remove(id: string): Promise<void>;
}

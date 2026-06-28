// TS types mirroring the normative Postgres schema (docs/05). snake_case in Postgres,
// camelCase mappers live in the repositories. Money is `bigint amount_minor` + ISO
// `currency`; in TS, minor units are integer `number` (safe < 2^53). This is the
// shape `@supabase/supabase-js` is generically parameterized over (Database).

import type { CurrencyCode } from '../core/currency';
import type { BillingPeriod, IncomeFrequency } from '../core/normalization';

export type UsageState = 'active' | 'rarely' | 'unused';

export type PaymentMethod =
  | 'credit_card'
  | 'debit_card'
  | 'paypal'
  | 'bank_transfer'
  | 'apple_pay'
  | 'google_pay'
  | 'crypto'
  | 'other';

export type CategoryKind = 'subscription' | 'expense';

/** docs/05 §subscriptions */
export type SubscriptionRow = {
  id: string;
  user_id: string;
  name: string;
  vendor_url: string | null;
  icon: string | null;
  amount_minor: number;
  currency: CurrencyCode;
  billing_period: BillingPeriod;
  payment_method: PaymentMethod | null;
  category_id: string | null;
  usage_state: UsageState;
  start_date: string; // date
  end_date: string | null;
  auto_renew: boolean;
  favorite: boolean;
  reminders_enabled: boolean;
  sort_order: number;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

/** docs/05 §categories */
export type CategoryRow = {
  id: string;
  user_id: string;
  name: string;
  slug: string;
  kind: CategoryKind;
  is_protected: boolean;
  created_at: string;
  updated_at: string;
}

/** docs/05 §income_sources */
export type IncomeSourceRow = {
  id: string;
  user_id: string;
  name: string;
  amount_minor: number;
  currency: CurrencyCode;
  frequency: IncomeFrequency;
  next_payment: string | null;
  created_at: string;
  updated_at: string;
}

/** docs/05 §fixed_expenses */
export type FixedExpenseRow = {
  id: string;
  user_id: string;
  name: string;
  amount_minor: number;
  currency: CurrencyCode;
  billing_period: BillingPeriod;
  category_id: string | null;
  due_date: string | null;
  created_at: string;
  updated_at: string;
}

/** docs/05 §variable_expenses */
export type VariableExpenseRow = {
  id: string;
  user_id: string;
  name: string;
  amount_minor: number;
  currency: CurrencyCode;
  category_id: string | null;
  spent_on: string; // date
  created_at: string;
  updated_at: string;
}

/**
 * The asset classes the Postgres `financial_assets.asset_type` CHECK allows
 * (docs/05 §3.7). Note these differ from the Domain `AssetType` (`etf`/`cash`):
 * the repository mapper translates between the two vocabularies.
 */
export type AssetTypeRow = 'stock' | 'crypto' | 'savings' | 'real_estate' | 'other';

/** docs/05 §3.7 financial_assets (average-cost semantics). */
export type FinancialAssetRow = {
  id: string;
  user_id: string;
  name: string;
  asset_type: AssetTypeRow;
  currency: CurrencyCode;
  /** Current TOTAL market value (minor units). */
  value_minor: number;
  /** Units held; numeric(38,8) arrives as `number` (well within range). */
  quantity: number | null;
  /** TOTAL cost basis (minor units), average-cost. */
  purchase_price_minor: number | null;
  purchase_date: string | null;
  /** Latest PER-UNIT price (minor units). */
  current_price_minor: number | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

/** docs/05 §3.10 user_preferences (per-user singleton). */
export type UserPreferencesRow = {
  id: string;
  user_id: string;
  appearance: 'system' | 'light' | 'dark';
  biometric_lock_enabled: boolean;
  biometric_lock_timeout_seconds: number;
  default_currency: CurrencyCode;
  payment_reminders_enabled: boolean;
  payday_reminders_enabled: boolean;
  reminder_lead_time_days: number;
  created_at: string;
  updated_at: string;
}

interface TableShape<Row> {
  Row: Row;
  Insert: Partial<Row>;
  Update: Partial<Row>;
  /** No FK relationships are modeled in this hand-written contract. Required by
   *  @supabase/supabase-js's GenericTable so it can resolve Row/Insert types. */
  Relationships: [];
}

/** The generic Database type @supabase/supabase-js is parameterized over. */
export interface Database {
  public: {
    Tables: {
      subscriptions: TableShape<SubscriptionRow>;
      categories: TableShape<CategoryRow>;
      income_sources: TableShape<IncomeSourceRow>;
      fixed_expenses: TableShape<FixedExpenseRow>;
      variable_expenses: TableShape<VariableExpenseRow>;
      financial_assets: TableShape<FinancialAssetRow>;
      user_preferences: TableShape<UserPreferencesRow>;
    };
    Views: Record<string, never>;
    Functions: Record<string, never>;
    Enums: {
      usage_state: UsageState;
      payment_method: PaymentMethod;
      billing_period: BillingPeriod;
      category_kind: CategoryKind;
    };
  };
}

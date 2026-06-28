-- =============================================================================
-- 20260628000300_subscriptions.sql
-- -----------------------------------------------------------------------------
-- Purpose : The flagship subscriptions table. Integer minor-unit money in the
--           subscription's own currency, one `favorite` boolean, normalized
--           category_id FK, explicit sort_order, per-row reminders opt-in.
-- Creates : public.subscriptions + indexes + RLS (ENABLE + FORCE) + 4 owner-only
--           policies + updated_at trigger + user_id immutability guard.
-- Depends : categories (category_id FK), set_updated_at(), prevent_user_id_change().
-- Normative source: docs/05-data-model.md §3.1.
-- Idempotent: CREATE TABLE IF NOT EXISTS; guarded index/policy/trigger creation.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.subscriptions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name            text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
  vendor_url      text,
  icon            text,
  amount_minor    bigint NOT NULL CHECK (amount_minor >= 0),
  currency        text   NOT NULL DEFAULT 'EUR' CHECK (currency IN ('EUR','USD','BTC')),
  billing_period  text   NOT NULL DEFAULT 'monthly'
                    CHECK (billing_period IN ('weekly','monthly','quarterly','yearly')),
  payment_method  text   CHECK (payment_method IN (
                      'credit_card','debit_card','paypal','bank_transfer',
                      'apple_pay','google_pay','crypto','other')),
  category_id     uuid REFERENCES public.categories(id) ON DELETE SET NULL,
  usage_state     text NOT NULL DEFAULT 'active'
                    CHECK (usage_state IN ('active','rarely','unused')),
  start_date      date NOT NULL DEFAULT (now() AT TIME ZONE 'utc')::date,
  end_date        date,
  auto_renew      boolean NOT NULL DEFAULT true,
  favorite        boolean NOT NULL DEFAULT false,
  reminders_enabled boolean NOT NULL DEFAULT false,
  sort_order      integer NOT NULL DEFAULT 0,
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT subscriptions_date_order CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id       ON public.subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_category_id   ON public.subscriptions(category_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_user_sort     ON public.subscriptions(user_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_subscriptions_user_favorite ON public.subscriptions(user_id, favorite)
  WHERE favorite = true;

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subscriptions_select ON public.subscriptions;
CREATE POLICY subscriptions_select ON public.subscriptions
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS subscriptions_insert ON public.subscriptions;
CREATE POLICY subscriptions_insert ON public.subscriptions
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS subscriptions_update ON public.subscriptions;
CREATE POLICY subscriptions_update ON public.subscriptions
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS subscriptions_delete ON public.subscriptions;
CREATE POLICY subscriptions_delete ON public.subscriptions
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

DROP TRIGGER IF EXISTS set_subscriptions_updated_at ON public.subscriptions;
CREATE TRIGGER set_subscriptions_updated_at
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS guard_user_id_subscriptions ON public.subscriptions;
CREATE TRIGGER guard_user_id_subscriptions
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_change();

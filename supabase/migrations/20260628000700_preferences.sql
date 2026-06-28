-- =============================================================================
-- 20260628000700_preferences.sql
-- -----------------------------------------------------------------------------
-- Purpose : Per-user singleton preference tables — currency_preferences (display
--           currency + cached exchange_rates jsonb), user_preferences (appearance,
--           biometric lock, default currency, notification/reminder opt-ins),
--           dashboard_layouts (ordered card_order text[]).
-- Creates : public.currency_preferences, public.user_preferences,
--           public.dashboard_layouts, each UNIQUE(user_id), RLS (ENABLE + FORCE),
--           4 owner-only policies, updated_at trigger, user_id guard.
-- Depends : set_updated_at(), prevent_user_id_change().
-- Note    : exchange_rates is a CACHE only, never the system of record. Canonical
--           key schema { "eur_usd", "btc_eur", "btc_usd", "fetched_at" }
--           (docs/04-tech-stack.md). Stored money is never pre-converted.
-- Normative source: docs/05-data-model.md §3.9, §3.10, §3.11.
-- Idempotent: CREATE TABLE IF NOT EXISTS; guarded index/policy/trigger creation.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- currency_preferences
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.currency_preferences (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  display_currency text NOT NULL DEFAULT 'EUR' CHECK (display_currency IN ('EUR','USD','BTC')),
  -- Canonical key schema: { "eur_usd", "btc_eur", "btc_usd", "fetched_at" } (see 04-tech-stack.md).
  -- Cache only; never the system of record. Empty {} until the first market-data fetch.
  exchange_rates   jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- Row-level cache write time; the authoritative rate age is exchange_rates->>'fetched_at'.
  last_updated     timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT currency_preferences_user_unique UNIQUE (user_id)
);

ALTER TABLE public.currency_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.currency_preferences FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS currency_pref_select ON public.currency_preferences;
CREATE POLICY currency_pref_select ON public.currency_preferences
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS currency_pref_insert ON public.currency_preferences;
CREATE POLICY currency_pref_insert ON public.currency_preferences
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS currency_pref_update ON public.currency_preferences;
CREATE POLICY currency_pref_update ON public.currency_preferences
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS currency_pref_delete ON public.currency_preferences;
CREATE POLICY currency_pref_delete ON public.currency_preferences
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

DROP TRIGGER IF EXISTS set_currency_preferences_updated_at ON public.currency_preferences;
CREATE TRIGGER set_currency_preferences_updated_at
  BEFORE UPDATE ON public.currency_preferences
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS guard_user_id_currency_preferences ON public.currency_preferences;
CREATE TRIGGER guard_user_id_currency_preferences
  BEFORE UPDATE ON public.currency_preferences
  FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_change();

-- -----------------------------------------------------------------------------
-- user_preferences
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_preferences (
  id                            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  appearance                    text NOT NULL DEFAULT 'system'
                                  CHECK (appearance IN ('system','light','dark')),
  biometric_lock_enabled        boolean NOT NULL DEFAULT false,
  biometric_lock_timeout_seconds integer NOT NULL DEFAULT 300 CHECK (biometric_lock_timeout_seconds >= 0),
  default_currency              text NOT NULL DEFAULT 'EUR' CHECK (default_currency IN ('EUR','USD','BTC')),
  payment_reminders_enabled     boolean NOT NULL DEFAULT true,
  payday_reminders_enabled      boolean NOT NULL DEFAULT true,
  reminder_lead_time_days       integer NOT NULL DEFAULT 2
                                  CHECK (reminder_lead_time_days BETWEEN 0 AND 30),
  created_at                    timestamptz NOT NULL DEFAULT now(),
  updated_at                    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_preferences_user_unique UNIQUE (user_id)
);

ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_pref_select ON public.user_preferences;
CREATE POLICY user_pref_select ON public.user_preferences
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS user_pref_insert ON public.user_preferences;
CREATE POLICY user_pref_insert ON public.user_preferences
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS user_pref_update ON public.user_preferences;
CREATE POLICY user_pref_update ON public.user_preferences
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS user_pref_delete ON public.user_preferences;
CREATE POLICY user_pref_delete ON public.user_preferences
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

DROP TRIGGER IF EXISTS set_user_preferences_updated_at ON public.user_preferences;
CREATE TRIGGER set_user_preferences_updated_at
  BEFORE UPDATE ON public.user_preferences
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS guard_user_id_user_preferences ON public.user_preferences;
CREATE TRIGGER guard_user_id_user_preferences
  BEFORE UPDATE ON public.user_preferences
  FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_change();

-- -----------------------------------------------------------------------------
-- dashboard_layouts
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dashboard_layouts (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  card_order text[] NOT NULL DEFAULT ARRAY[]::text[],
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT dashboard_layouts_user_unique UNIQUE (user_id)
);

ALTER TABLE public.dashboard_layouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dashboard_layouts FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dashboard_select ON public.dashboard_layouts;
CREATE POLICY dashboard_select ON public.dashboard_layouts
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS dashboard_insert ON public.dashboard_layouts;
CREATE POLICY dashboard_insert ON public.dashboard_layouts
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS dashboard_update ON public.dashboard_layouts;
CREATE POLICY dashboard_update ON public.dashboard_layouts
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS dashboard_delete ON public.dashboard_layouts;
CREATE POLICY dashboard_delete ON public.dashboard_layouts
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

DROP TRIGGER IF EXISTS set_dashboard_layouts_updated_at ON public.dashboard_layouts;
CREATE TRIGGER set_dashboard_layouts_updated_at
  BEFORE UPDATE ON public.dashboard_layouts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS guard_user_id_dashboard_layouts ON public.dashboard_layouts;
CREATE TRIGGER guard_user_id_dashboard_layouts
  BEFORE UPDATE ON public.dashboard_layouts
  FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_change();

-- =============================================================================
-- 20260628000400_subscription_price_history.sql
-- -----------------------------------------------------------------------------
-- Purpose : Append-only audit log of every price/currency change on a
--           subscription, written automatically by a SECURITY DEFINER trigger.
--           Read-only from the client (SELECT policy only; no I/U/D policies).
-- Creates : public.subscription_price_history + indexes + RLS (ENABLE + FORCE)
--           + SELECT-only policy; the log_subscription_price_change() trigger
--           function + AFTER INSERT OR UPDATE OF (amount_minor, currency) trigger.
-- Depends : subscriptions (parent FK).
-- Security: Rows are written ONLY by the SECURITY DEFINER trigger (pinned
--           search_path, REVOKE ALL FROM PUBLIC, no authenticated grant). The
--           function trusts NEW.user_id, which RLS on subscriptions already
--           proved equals auth.uid() at write time.
-- Normative source: docs/05-data-model.md §3.2 and §4.2.
-- Idempotent: CREATE TABLE IF NOT EXISTS; CREATE OR REPLACE FUNCTION;
--             guarded index/policy/trigger creation.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.subscription_price_history (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES public.subscriptions(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount_minor    bigint NOT NULL CHECK (amount_minor >= 0),
  currency        text   NOT NULL CHECK (currency IN ('EUR','USD','BTC')),
  effective_from  timestamptz NOT NULL,
  is_correction   boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sph_subscription_id ON public.subscription_price_history(subscription_id);
CREATE INDEX IF NOT EXISTS idx_sph_user_id         ON public.subscription_price_history(user_id);
CREATE INDEX IF NOT EXISTS idx_sph_effective_from  ON public.subscription_price_history(subscription_id, effective_from DESC);

ALTER TABLE public.subscription_price_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_price_history FORCE ROW LEVEL SECURITY;

-- Read-only to clients. Rows are written ONLY by the SECURITY DEFINER trigger.
DROP POLICY IF EXISTS sph_select ON public.subscription_price_history;
CREATE POLICY sph_select ON public.subscription_price_history
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
-- Intentionally NO insert/update/delete policies for authenticated users.

-- -----------------------------------------------------------------------------
-- log_subscription_price_change(): the only writer of the history table.
-- Fires on INSERT and whenever amount_minor OR currency changes (IS DISTINCT
-- FROM handles NULL transitions). Stores the native amount_minor + currency.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_subscription_price_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (TG_OP = 'INSERT')
     OR (OLD.amount_minor IS DISTINCT FROM NEW.amount_minor)
     OR (OLD.currency     IS DISTINCT FROM NEW.currency) THEN
    INSERT INTO public.subscription_price_history (
      subscription_id, user_id, amount_minor, currency, effective_from, is_correction
    ) VALUES (
      NEW.id,
      NEW.user_id,
      NEW.amount_minor,
      NEW.currency,
      CASE WHEN TG_OP = 'INSERT'
           THEN COALESCE(NEW.start_date::timestamptz, now())
           ELSE now() END,
      false
    );
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.log_subscription_price_change() FROM PUBLIC;

DROP TRIGGER IF EXISTS subscription_price_change_trigger ON public.subscriptions;
CREATE TRIGGER subscription_price_change_trigger
  AFTER INSERT OR UPDATE OF amount_minor, currency
  ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.log_subscription_price_change();

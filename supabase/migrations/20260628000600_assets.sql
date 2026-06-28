-- =============================================================================
-- 20260628000600_assets.sql
-- -----------------------------------------------------------------------------
-- Purpose : Assets / investments — financial_assets (average-cost semantics)
--           and its child asset_transactions (buy/sell/dividend/other lots).
-- Creates : public.financial_assets, public.asset_transactions, each with
--           indexes, RLS (ENABLE + FORCE) and 4 owner-only policies.
--           financial_assets has updated_at trigger + user_id guard;
--           asset_transactions is append-mostly (no updated_at).
-- Depends : set_updated_at(), prevent_user_id_change().
-- Money   : value_minor = current TOTAL market value; purchase_price_minor =
--           TOTAL cost basis (average-cost); current_price_minor = PER-UNIT.
--           quantity is numeric(38,8) (a count of units, not money).
-- Normative source: docs/05-data-model.md §3.7, §3.8.
-- Idempotent: CREATE TABLE IF NOT EXISTS; guarded index/policy/trigger creation.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- financial_assets
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.financial_assets (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name                 text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
  asset_type           text NOT NULL
                         CHECK (asset_type IN ('stock','crypto','savings','real_estate','other')),
  currency             text NOT NULL DEFAULT 'EUR' CHECK (currency IN ('EUR','USD','BTC')),
  value_minor          bigint NOT NULL CHECK (value_minor >= 0),
  quantity             numeric(38,8),
  purchase_price_minor bigint CHECK (purchase_price_minor IS NULL OR purchase_price_minor >= 0),
  purchase_date        date,
  current_price_minor  bigint CHECK (current_price_minor IS NULL OR current_price_minor >= 0),
  notes                text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

COMMENT ON COLUMN public.financial_assets.purchase_price_minor IS
  'TOTAL cost basis: aggregate amount invested across all buys, average-cost method (v1; FIFO deferred, ADR-0015). NOT per-unit.';
COMMENT ON COLUMN public.financial_assets.current_price_minor IS
  'Latest PER-UNIT market price (one unit/share/coin).';
COMMENT ON COLUMN public.financial_assets.value_minor IS
  'Current TOTAL market value of the holding. Unrealized gain/loss = value_minor - purchase_price_minor.';

CREATE INDEX IF NOT EXISTS idx_financial_assets_user_id ON public.financial_assets(user_id);
CREATE INDEX IF NOT EXISTS idx_financial_assets_type    ON public.financial_assets(user_id, asset_type);

ALTER TABLE public.financial_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_assets FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS financial_assets_select ON public.financial_assets;
CREATE POLICY financial_assets_select ON public.financial_assets
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS financial_assets_insert ON public.financial_assets;
CREATE POLICY financial_assets_insert ON public.financial_assets
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS financial_assets_update ON public.financial_assets;
CREATE POLICY financial_assets_update ON public.financial_assets
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS financial_assets_delete ON public.financial_assets;
CREATE POLICY financial_assets_delete ON public.financial_assets
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

DROP TRIGGER IF EXISTS set_financial_assets_updated_at ON public.financial_assets;
CREATE TRIGGER set_financial_assets_updated_at
  BEFORE UPDATE ON public.financial_assets
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS guard_user_id_financial_assets ON public.financial_assets;
CREATE TRIGGER guard_user_id_financial_assets
  BEFORE UPDATE ON public.financial_assets
  FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_change();

-- -----------------------------------------------------------------------------
-- asset_transactions (append-mostly; no updated_at per docs/05 §3.8 note)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.asset_transactions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id     uuid NOT NULL REFERENCES public.financial_assets(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  txn_type     text NOT NULL CHECK (txn_type IN ('buy','sell','dividend','other')),
  quantity     numeric(38,8) NOT NULL,
  price_minor  bigint NOT NULL CHECK (price_minor >= 0),
  fees_minor   bigint CHECK (fees_minor IS NULL OR fees_minor >= 0),
  currency     text NOT NULL DEFAULT 'EUR' CHECK (currency IN ('EUR','USD','BTC')),
  date         date NOT NULL,
  notes        text,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_asset_txn_user_id  ON public.asset_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_asset_txn_asset_id ON public.asset_transactions(asset_id);
CREATE INDEX IF NOT EXISTS idx_asset_txn_date     ON public.asset_transactions(asset_id, date DESC);

ALTER TABLE public.asset_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asset_transactions FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS asset_txn_select ON public.asset_transactions;
CREATE POLICY asset_txn_select ON public.asset_transactions
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS asset_txn_insert ON public.asset_transactions;
CREATE POLICY asset_txn_insert ON public.asset_transactions
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS asset_txn_update ON public.asset_transactions;
CREATE POLICY asset_txn_update ON public.asset_transactions
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS asset_txn_delete ON public.asset_transactions;
CREATE POLICY asset_txn_delete ON public.asset_transactions
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- Guard user_id immutability even though there is no updated_at clock.
DROP TRIGGER IF EXISTS guard_user_id_asset_transactions ON public.asset_transactions;
CREATE TRIGGER guard_user_id_asset_transactions
  BEFORE UPDATE ON public.asset_transactions
  FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_change();

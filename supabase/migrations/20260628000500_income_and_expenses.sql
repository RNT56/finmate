-- =============================================================================
-- 20260628000500_income_and_expenses.sql
-- -----------------------------------------------------------------------------
-- Purpose : Income and expense ledgers — income_sources, fixed_expenses,
--           variable_expenses. Integer minor-unit money in each row's own
--           currency; expenses carry a normalized category_id FK.
-- Creates : public.income_sources, public.fixed_expenses,
--           public.variable_expenses, each with indexes, RLS (ENABLE + FORCE),
--           4 owner-only policies, updated_at trigger, user_id guard.
-- Depends : categories (category_id FKs), set_updated_at(), prevent_user_id_change().
-- Normative source: docs/05-data-model.md §3.4, §3.5, §3.6.
-- Idempotent: CREATE TABLE IF NOT EXISTS; guarded index/policy/trigger creation.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- income_sources
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.income_sources (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
  amount_minor bigint NOT NULL CHECK (amount_minor >= 0),
  currency     text   NOT NULL DEFAULT 'EUR' CHECK (currency IN ('EUR','USD','BTC')),
  frequency    text   NOT NULL
                 CHECK (frequency IN ('weekly','monthly','yearly','one_time')),
  next_payment date,
  notes        text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_income_sources_user_id      ON public.income_sources(user_id);
CREATE INDEX IF NOT EXISTS idx_income_sources_next_payment ON public.income_sources(user_id, next_payment);

ALTER TABLE public.income_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.income_sources FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS income_sources_select ON public.income_sources;
CREATE POLICY income_sources_select ON public.income_sources
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS income_sources_insert ON public.income_sources;
CREATE POLICY income_sources_insert ON public.income_sources
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS income_sources_update ON public.income_sources;
CREATE POLICY income_sources_update ON public.income_sources
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS income_sources_delete ON public.income_sources;
CREATE POLICY income_sources_delete ON public.income_sources
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

DROP TRIGGER IF EXISTS set_income_sources_updated_at ON public.income_sources;
CREATE TRIGGER set_income_sources_updated_at
  BEFORE UPDATE ON public.income_sources
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS guard_user_id_income_sources ON public.income_sources;
CREATE TRIGGER guard_user_id_income_sources
  BEFORE UPDATE ON public.income_sources
  FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_change();

-- -----------------------------------------------------------------------------
-- fixed_expenses
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fixed_expenses (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
  amount_minor bigint NOT NULL CHECK (amount_minor >= 0),
  currency     text   NOT NULL DEFAULT 'EUR' CHECK (currency IN ('EUR','USD','BTC')),
  category_id  uuid REFERENCES public.categories(id) ON DELETE SET NULL,
  due_date     date,
  frequency    text NOT NULL CHECK (frequency IN ('monthly','quarterly','yearly')),
  autopay      boolean NOT NULL DEFAULT false,
  notes        text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fixed_expenses_user_id     ON public.fixed_expenses(user_id);
CREATE INDEX IF NOT EXISTS idx_fixed_expenses_category_id ON public.fixed_expenses(category_id);
CREATE INDEX IF NOT EXISTS idx_fixed_expenses_due_date    ON public.fixed_expenses(user_id, due_date);

ALTER TABLE public.fixed_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fixed_expenses FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS fixed_expenses_select ON public.fixed_expenses;
CREATE POLICY fixed_expenses_select ON public.fixed_expenses
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS fixed_expenses_insert ON public.fixed_expenses;
CREATE POLICY fixed_expenses_insert ON public.fixed_expenses
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS fixed_expenses_update ON public.fixed_expenses;
CREATE POLICY fixed_expenses_update ON public.fixed_expenses
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS fixed_expenses_delete ON public.fixed_expenses;
CREATE POLICY fixed_expenses_delete ON public.fixed_expenses
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

DROP TRIGGER IF EXISTS set_fixed_expenses_updated_at ON public.fixed_expenses;
CREATE TRIGGER set_fixed_expenses_updated_at
  BEFORE UPDATE ON public.fixed_expenses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS guard_user_id_fixed_expenses ON public.fixed_expenses;
CREATE TRIGGER guard_user_id_fixed_expenses
  BEFORE UPDATE ON public.fixed_expenses
  FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_change();

-- -----------------------------------------------------------------------------
-- variable_expenses (the user-picked calendar day column is named `spent_on`)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.variable_expenses (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name         text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
  amount_minor bigint NOT NULL CHECK (amount_minor >= 0),
  currency     text   NOT NULL DEFAULT 'EUR' CHECK (currency IN ('EUR','USD','BTC')),
  category_id  uuid REFERENCES public.categories(id) ON DELETE SET NULL,
  spent_on     date NOT NULL,
  notes        text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_variable_expenses_user_id     ON public.variable_expenses(user_id);
CREATE INDEX IF NOT EXISTS idx_variable_expenses_category_id ON public.variable_expenses(category_id);
CREATE INDEX IF NOT EXISTS idx_variable_expenses_spent_on    ON public.variable_expenses(user_id, spent_on DESC);

ALTER TABLE public.variable_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.variable_expenses FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS variable_expenses_select ON public.variable_expenses;
CREATE POLICY variable_expenses_select ON public.variable_expenses
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS variable_expenses_insert ON public.variable_expenses;
CREATE POLICY variable_expenses_insert ON public.variable_expenses
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS variable_expenses_update ON public.variable_expenses;
CREATE POLICY variable_expenses_update ON public.variable_expenses
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS variable_expenses_delete ON public.variable_expenses;
CREATE POLICY variable_expenses_delete ON public.variable_expenses
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

DROP TRIGGER IF EXISTS set_variable_expenses_updated_at ON public.variable_expenses;
CREATE TRIGGER set_variable_expenses_updated_at
  BEFORE UPDATE ON public.variable_expenses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS guard_user_id_variable_expenses ON public.variable_expenses;
CREATE TRIGGER guard_user_id_variable_expenses
  BEFORE UPDATE ON public.variable_expenses
  FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_change();

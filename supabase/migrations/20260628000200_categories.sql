-- =============================================================================
-- 20260628000200_categories.sql
-- -----------------------------------------------------------------------------
-- Purpose : The single, normalized categories table that replaces Substimate's
--           three competing category mechanisms. A `kind` discriminator
--           ('subscription' | 'expense') splits the namespace.
-- Creates : public.categories + indexes + RLS (ENABLE + FORCE) + 4 owner-only
--           policies + updated_at trigger + user_id immutability guard.
-- Security: RLS owner-only on auth.uid() = user_id; protected rows cannot be
--           deleted (DELETE policy filters is_protected = false).
-- Normative source: docs/05-data-model.md §3.3.
-- Idempotent: CREATE TABLE IF NOT EXISTS; guarded index/policy/trigger creation.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.categories (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind         text NOT NULL CHECK (kind IN ('subscription','expense')),
  name         text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
  slug         text NOT NULL CHECK (slug ~ '^[a-z0-9_]+$'),
  symbol       text,
  color_hex    text CHECK (color_hex IS NULL OR color_hex ~* '^#[0-9a-f]{6}$'),
  sort_order   integer NOT NULL DEFAULT 0,
  is_protected boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  -- A category name is unique within (user, kind): the same "Other" can exist
  -- once as a subscription category and once as an expense category.
  CONSTRAINT categories_user_kind_name_unique UNIQUE (user_id, kind, name),
  -- Slug is likewise unique per (user, kind); this is the seed upsert conflict target.
  CONSTRAINT categories_user_kind_slug_unique UNIQUE (user_id, kind, slug)
);

CREATE INDEX IF NOT EXISTS idx_categories_user_id   ON public.categories(user_id);
CREATE INDEX IF NOT EXISTS idx_categories_user_kind ON public.categories(user_id, kind);

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS categories_select ON public.categories;
CREATE POLICY categories_select ON public.categories
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS categories_insert ON public.categories;
CREATE POLICY categories_insert ON public.categories
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS categories_update ON public.categories;
CREATE POLICY categories_update ON public.categories
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Protected defaults cannot be deleted: the policy filters them out of DELETE entirely.
DROP POLICY IF EXISTS categories_delete ON public.categories;
CREATE POLICY categories_delete ON public.categories
  FOR DELETE TO authenticated USING (auth.uid() = user_id AND is_protected = false);

DROP TRIGGER IF EXISTS set_categories_updated_at ON public.categories;
CREATE TRIGGER set_categories_updated_at
  BEFORE UPDATE ON public.categories
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS guard_user_id_categories ON public.categories;
CREATE TRIGGER guard_user_id_categories
  BEFORE UPDATE ON public.categories
  FOR EACH ROW EXECUTE FUNCTION public.prevent_user_id_change();

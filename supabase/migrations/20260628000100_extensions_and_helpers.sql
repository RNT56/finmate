-- =============================================================================
-- 20260628000100_extensions_and_helpers.sql
-- -----------------------------------------------------------------------------
-- Purpose : Bootstrap the Finmate database with required extensions and the
--           shared, hardened helper/trigger functions used by every table.
-- Creates : extensions (pgcrypto for gen_random_uuid; uuid-ossp as belt-and-
--           braces), and the SECURITY DEFINER trigger functions
--           set_updated_at() and prevent_user_id_change().
-- Security: Both functions are SECURITY DEFINER with SET search_path = public,
--           REVOKE ALL FROM PUBLIC, and are NOT granted to authenticated — they
--           run only from BEFORE UPDATE triggers, never as client RPCs.
--           Normative source: docs/05-data-model.md §4.1.
-- Idempotent: extensions IF NOT EXISTS; functions via CREATE OR REPLACE.
-- =============================================================================

-- gen_random_uuid() lives in pgcrypto on managed Supabase Postgres.
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA extensions;
-- uuid-ossp kept available for completeness; gen_random_uuid() is the PK default.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

-- -----------------------------------------------------------------------------
-- set_updated_at(): stamp updated_at = now() on every UPDATE.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Trigger-only; never client-callable. No GRANT to authenticated.
REVOKE ALL ON FUNCTION public.set_updated_at() FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- prevent_user_id_change(): defensively forbid user_id reassignment.
-- RLS already blocks cross-user writes; this turns a silent ownership change
-- into a hard error.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prevent_user_id_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'user_id is immutable';
  END IF;
  RETURN NEW;
END;
$$;

-- Trigger-only; never client-callable. No GRANT to authenticated.
REVOKE ALL ON FUNCTION public.prevent_user_id_change() FROM PUBLIC;

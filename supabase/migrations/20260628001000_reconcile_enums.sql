-- =============================================================================
-- 20260628001000_reconcile_enums.sql
-- -----------------------------------------------------------------------------
-- Purpose : Reconcile the last DTO↔schema enum divergences flagged during the
--           live data-layer wiring (CLAUDE §2 "Remaining build"). Widens two
--           inline CHECK constraints to the canonical union sets so the schema,
--           the Swift Domain, and the web TS core all agree:
--             • financial_assets.asset_type → the UNION
--                 {crypto, stock, etf, cash, savings, real_estate, other}
--               (schema gains etf+cash; Domain gains savings + real_estate).
--             • fixed_expenses.frequency → {weekly, monthly, quarterly, yearly}
--               (gains weekly, matching Domain BillingPeriod; income_sources
--               already allows weekly, BillingPeriodMath already normalizes it).
-- Depends : 20260628000500_income_and_expenses.sql (fixed_expenses),
--           20260628000600_assets.sql (financial_assets).
-- Normative source: docs/05-data-model.md §3.5, §3.7; ADR-0023 (docs/12).
-- Idempotent: DROP CONSTRAINT IF EXISTS + ADD CONSTRAINT. The original inline
--   CHECKs carry the default name `<table>_<column>_check`; IF EXISTS makes the
--   drop safe regardless of whether that default name is present. RLS, indexes,
--   triggers, and all other constraints are left untouched.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- financial_assets.asset_type → canonical UNION set
-- -----------------------------------------------------------------------------
ALTER TABLE public.financial_assets
  DROP CONSTRAINT IF EXISTS financial_assets_asset_type_check,
  ADD CONSTRAINT financial_assets_asset_type_check
    CHECK (asset_type IN ('crypto','stock','etf','cash','savings','real_estate','other'));

-- -----------------------------------------------------------------------------
-- fixed_expenses.frequency → add 'weekly'
-- -----------------------------------------------------------------------------
ALTER TABLE public.fixed_expenses
  DROP CONSTRAINT IF EXISTS fixed_expenses_frequency_check,
  ADD CONSTRAINT fixed_expenses_frequency_check
    CHECK (frequency IN ('weekly','monthly','quarterly','yearly'));

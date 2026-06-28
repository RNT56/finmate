-- =============================================================================
-- 20260628000800_rpcs.sql
-- -----------------------------------------------------------------------------
-- Purpose : Client-callable RPCs invoked from Swift via supabase.rpc(...).
-- Creates : get_user_categories(p_kind text), batch_reorder_subscriptions(jsonb),
--           delete_subscription(uuid), subscription_price_at(uuid, timestamptz).
-- Depends : categories, subscriptions, subscription_price_history,
--           fixed_expenses, variable_expenses.
-- Security: Every RPC is SECURITY DEFINER, SET search_path = public,
--           REVOKE ALL FROM PUBLIC, GRANT EXECUTE TO authenticated, derives
--           ownership ONLY from auth.uid() (never a caller-supplied user_id),
--           validates input, and owner-checks per row before any mutation.
-- Normative source: docs/05-data-model.md §5.1–§5.4.
-- Idempotent: CREATE OR REPLACE FUNCTION.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- get_user_categories(p_kind): categories of one kind with live usage counts.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_user_categories(p_kind text)
RETURNS TABLE (
  id           uuid,
  kind         text,
  name         text,
  slug         text,
  symbol       text,
  color_hex    text,
  sort_order   integer,
  is_protected boolean,
  usage_count  bigint
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.id, c.kind, c.name, c.slug, c.symbol, c.color_hex, c.sort_order, c.is_protected,
         CASE
           WHEN p_kind = 'subscription' THEN
             (SELECT COUNT(*) FROM public.subscriptions s
               WHERE s.category_id = c.id AND s.user_id = auth.uid())
           ELSE
             (SELECT COUNT(*) FROM public.fixed_expenses fe
               WHERE fe.category_id = c.id AND fe.user_id = auth.uid())
           + (SELECT COUNT(*) FROM public.variable_expenses ve
               WHERE ve.category_id = c.id AND ve.user_id = auth.uid())
         END AS usage_count
  FROM public.categories c
  WHERE c.user_id = auth.uid()
    AND c.kind = p_kind
  ORDER BY c.sort_order, c.name;
$$;

REVOKE ALL ON FUNCTION public.get_user_categories(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_categories(text) TO authenticated;

-- -----------------------------------------------------------------------------
-- batch_reorder_subscriptions(updates): reorder cards by updating sort_order
-- only (Substimate corrupted created_at). Validates the JSON array and
-- owner-checks each row before updating it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.batch_reorder_subscriptions(updates jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item record;
BEGIN
  IF jsonb_typeof(updates) <> 'array' THEN
    RAISE EXCEPTION 'updates must be a JSON array';
  END IF;
  IF jsonb_array_length(updates) = 0 THEN
    RAISE EXCEPTION 'updates array cannot be empty';
  END IF;

  FOR item IN
    SELECT (value->>'id')::uuid AS id,
           (value->>'sort_order')::int AS sort_order
    FROM jsonb_array_elements(updates)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.subscriptions
      WHERE id = item.id AND user_id = auth.uid()
    ) THEN
      RAISE EXCEPTION 'Access denied for subscription %', item.id;
    END IF;

    UPDATE public.subscriptions
    SET sort_order = item.sort_order
    WHERE id = item.id AND user_id = auth.uid();
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.batch_reorder_subscriptions(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.batch_reorder_subscriptions(jsonb) TO authenticated;

-- -----------------------------------------------------------------------------
-- delete_subscription(sub_id): direct delete keyed on auth.uid()
-- (cascades remove price history).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_subscription(sub_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.subscriptions
  WHERE id = sub_id AND user_id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.delete_subscription(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_subscription(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- subscription_price_at(p_subscription_id, p_at): effective price at a date
-- (lifetime-cost analytics helper).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.subscription_price_at(p_subscription_id uuid, p_at timestamptz)
RETURNS TABLE (amount_minor bigint, currency text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT h.amount_minor, h.currency
  FROM public.subscription_price_history h
  JOIN public.subscriptions s ON s.id = h.subscription_id
  WHERE h.subscription_id = p_subscription_id
    AND s.user_id = auth.uid()
    AND h.effective_from <= p_at
  ORDER BY h.effective_from DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.subscription_price_at(uuid, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.subscription_price_at(uuid, timestamptz) TO authenticated;

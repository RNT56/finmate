-- =============================================================================
-- 20260628000900_new_user_bootstrap.sql
-- -----------------------------------------------------------------------------
-- Purpose : Seed every new auth.users row with the default category taxonomies
--           (18 subscription + 11 expense categories) and the three singleton
--           preference rows, via an AFTER INSERT trigger on auth.users.
-- Creates : seed_default_categories(uuid), handle_new_user() (trigger fn), and
--           the on_auth_user_created trigger on auth.users.
-- Depends : categories, user_preferences, currency_preferences,
--           dashboard_layouts (all must exist first — they do, per migration order).
-- Security: Both functions are SECURITY DEFINER, SET search_path = public,
--           REVOKE ALL FROM PUBLIC, and are NOT granted to authenticated — they
--           are trigger-only. Their target user is the trigger's NEW.id, never a
--           client-supplied argument.
-- Normative source: docs/05-data-model.md §7.2.
-- Idempotent: CREATE OR REPLACE FUNCTION; ON CONFLICT DO NOTHING seeds;
--             guarded trigger creation.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- seed_default_categories(p_user_id): seed both taxonomies for one user.
-- "All"/"Favorites" are NEVER seeded — they are UI pseudo-filters. Only the
-- per-kind "Other" rows are protected.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seed_default_categories(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- kind,           name,               slug,                symbol,                  protected
  defaults text[][] := ARRAY[
    -- Subscription taxonomy (18) ----------------------------------------------
    ['subscription', 'Other',              'other',             'square.grid.2x2',       'true'],
    ['subscription', 'Streaming',          'streaming',         'play.tv',               'false'],
    ['subscription', 'Music',              'music',             'music.note',            'false'],
    ['subscription', 'Gaming',             'gaming',            'gamecontroller',        'false'],
    ['subscription', 'Productivity',       'productivity',      'checklist',             'false'],
    ['subscription', 'AI Chat',            'ai_chat',           'bubble.left.and.text.bubble.right', 'false'],
    ['subscription', 'Coding',             'coding',            'chevron.left.forwardslash.chevron.right', 'false'],
    ['subscription', 'Diffusion',          'diffusion',         'paintbrush',            'false'],
    ['subscription', 'Audio Generation',   'audio_generation',  'waveform',              'false'],
    ['subscription', 'Video Generation',   'video_generation',  'film',                  'false'],
    ['subscription', 'Cloud Services',     'cloud_services',    'cloud',                 'false'],
    ['subscription', 'Fitness',            'fitness',           'figure.run',            'false'],
    ['subscription', 'Health',             'health',            'heart',                 'false'],
    ['subscription', 'Food',               'food',              'fork.knife',            'false'],
    ['subscription', 'Transport',          'transport',         'car',                   'false'],
    ['subscription', 'Financial',          'financial',         'banknote',              'false'],
    ['subscription', 'Creative',           'creative',          'paintpalette',          'false'],
    ['subscription', 'Social',             'social',            'person.2',              'false'],
    -- Expense taxonomy (11) ---------------------------------------------------
    ['expense',      'Housing',            'housing',           'house',                 'false'],
    ['expense',      'Transportation',     'transportation',    'car',                   'false'],
    ['expense',      'Food',               'food',              'fork.knife',            'false'],
    ['expense',      'Utilities',          'utilities',         'bolt',                  'false'],
    ['expense',      'Insurance',          'insurance',         'shield',                'false'],
    ['expense',      'Healthcare',         'healthcare',        'cross.case',            'false'],
    ['expense',      'Entertainment',      'entertainment',     'theatermasks',          'false'],
    ['expense',      'Shopping',           'shopping',          'bag',                   'false'],
    ['expense',      'Education',          'education',         'graduationcap',         'false'],
    ['expense',      'Savings',            'savings',           'banknote',              'false'],
    ['expense',      'Other',              'other',             'square.grid.2x2',       'true']
  ];
  i int;
BEGIN
  FOR i IN 1 .. array_length(defaults, 1) LOOP
    INSERT INTO public.categories (user_id, kind, name, slug, symbol, is_protected, sort_order)
    VALUES (p_user_id, defaults[i][1], defaults[i][2], defaults[i][3], defaults[i][4],
            defaults[i][5]::boolean, i)
    ON CONFLICT (user_id, kind, slug) DO NOTHING;
  END LOOP;
END;
$$;

-- Invoked ONLY by handle_new_user() (the auth.users AFTER INSERT trigger).
-- NOT client-callable: no GRANT to authenticated.
REVOKE ALL ON FUNCTION public.seed_default_categories(uuid) FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- handle_new_user(): seed categories + the three singleton preference rows.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.seed_default_categories(NEW.id);
  INSERT INTO public.user_preferences (user_id) VALUES (NEW.id) ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.currency_preferences (user_id) VALUES (NEW.id) ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.dashboard_layouts (user_id) VALUES (NEW.id) ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- Trigger-only (auth.users AFTER INSERT); never client-callable. No GRANT to authenticated.
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

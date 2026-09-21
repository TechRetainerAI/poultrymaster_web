-- =============================================================================
-- 318_UserQuickLinks.postgres.sql
--
-- Purpose
-- -------
-- Let a user choose what sits in their own Quick Links bar, per company.
--
-- WHY ONE ROW WITH A JSON ARRAY, AND NOT A ROW PER LINK
-- =====================================================
-- A row-per-link table cannot say "this user chose to have NO quick links".
-- Zero rows would mean both "never customised, show the defaults" and "removed
-- every one", and the difference is the whole feature: a user who clears the
-- bar and finds the defaults back the next morning has not been given a choice,
-- they have been given a bug.
--
-- One row holding a jsonb array says it plainly. No row at all = never
-- customised = the page's own defaults. A row holding [] = customised to
-- nothing. The array also carries the ORDER for free, which a row-per-link
-- table would need a sortorder column and a rewrite of it on every save to
-- keep.
--
-- WHY PER COMPANY AND NOT PER USER
-- ================================
-- One login owns several companies and they are not the same business: a
-- poultry farm's daily work is production records and egg sorting, a water
-- company's is production and distribution. The pages do not even exist across
-- the two. Keying on (userid, farmid) is what makes the bar mean anything after
-- a company switch.
--
-- WHAT THIS TABLE DOES NOT DO
-- ===========================
-- It does not grant anything. An href stored here is a preference about what is
-- SHOWN, and the rail still runs every financial row through its own
-- permission gate when it renders. A user who stores /cash-flow here and is
-- later denied Cash Flow sees nothing new -- the gate drops the row and the
-- stored preference goes on sitting there harmlessly until they are allowed it
-- again. Storing anything else would make a shortcut list a way around
-- permissions, which is the one thing it must never be.
--
-- Idempotent. Safe to run more than once.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The table.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.userquicklinks (
    userquicklinkid serial PRIMARY KEY,
    userid          text        NOT NULL,
    farmid          text        NOT NULL,
    -- A JSON array of hrefs, in the order they are to be shown.
    hrefs           jsonb       NOT NULL DEFAULT '[]'::jsonb,
    createdat       timestamp   NOT NULL DEFAULT now(),
    updatedat       timestamp   NOT NULL DEFAULT now()
);

-- One row per user per company. This is also what makes the upsert below a
-- single statement rather than a read-then-write race.
CREATE UNIQUE INDEX IF NOT EXISTS ux_userquicklinks_user_farm
    ON public.userquicklinks (lower(userid), lower(farmid));

DO $$
BEGIN
    -- hrefs must be an ARRAY. Without this a caller could store an object or a
    -- bare string and the reader would hand the nav a shape it cannot map,
    -- which surfaces as an empty rail rather than as an error.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'ck_userquicklinks_hrefs_array') THEN
        ALTER TABLE public.userquicklinks
            ADD CONSTRAINT ck_userquicklinks_hrefs_array
            CHECK (jsonb_typeof(hrefs) = 'array');
    END IF;

    -- A shortcut bar with forty rows in it is not a shortcut bar. The cap is
    -- here rather than only in the dialog because the dialog is not the only
    -- thing that can call the endpoint.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'ck_userquicklinks_hrefs_len') THEN
        ALTER TABLE public.userquicklinks
            ADD CONSTRAINT ck_userquicklinks_hrefs_len
            CHECK (jsonb_array_length(hrefs) <= 20);
    END IF;
END $$;

COMMENT ON TABLE public.userquicklinks IS
    'One row per user per company: the hrefs that user wants in their Quick '
    'Links bar, in order. No row = the page defaults. [] = deliberately empty.';

-- -----------------------------------------------------------------------------
-- 2. Read.
--
-- Returns at most one row, and NO row when the user has never customised --
-- which the caller must be able to tell apart from an empty array. Returning a
-- default-filled row here would destroy exactly the distinction section 1 of
-- this file exists to keep.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spuserquicklinks_get(
    p_userid text,
    p_farmid text
) RETURNS TABLE(
    userid    text,
    farmid    text,
    hrefs     jsonb,
    updatedat timestamp
)
LANGUAGE sql STABLE
AS $function$
    SELECT q.userid, q.farmid, q.hrefs, q.updatedat
    FROM   public.userquicklinks q
    WHERE  lower(q.userid) = lower(p_userid)
      AND  lower(q.farmid) = lower(p_farmid);
$function$;

-- -----------------------------------------------------------------------------
-- 3. Write.
--
-- Replace-all, by design: the dialog sends the whole bar as the user left it,
-- so there is no add/remove pair to get out of step with each other, and no
-- half-applied save.
--
-- Duplicates are dropped and order is preserved -- the same page twice is not
-- something the dialog can produce, but it is something a hand-made request
-- can, and a bar with two identical rows would render two identical rows.
-- WITH ORDINALITY is what keeps the user's order through the DISTINCT.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spuserquicklinks_set(
    p_userid text,
    p_farmid text,
    p_hrefs  jsonb
) RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_clean jsonb;
BEGIN
    IF COALESCE(btrim(p_userid), '') = '' THEN
        RAISE EXCEPTION '318: a user id is required.';
    END IF;
    IF COALESCE(btrim(p_farmid), '') = '' THEN
        RAISE EXCEPTION '318: a company id is required.';
    END IF;
    IF p_hrefs IS NULL OR jsonb_typeof(p_hrefs) <> 'array' THEN
        RAISE EXCEPTION '318: hrefs must be a JSON array.';
    END IF;

    SELECT COALESCE(jsonb_agg(h.href ORDER BY h.first_at), '[]'::jsonb)
    INTO   v_clean
    FROM (
        SELECT e.value #>> '{}'   AS href,
               MIN(e.ord)         AS first_at
        FROM   jsonb_array_elements(p_hrefs) WITH ORDINALITY AS e(value, ord)
        -- Only strings, only non-blank ones, and only real paths. An href is
        -- matched against the rail by exact string, so anything that is not one
        -- of its hrefs is dead weight that will never render.
        WHERE  jsonb_typeof(e.value) = 'string'
          AND  btrim(e.value #>> '{}') <> ''
          AND  left(btrim(e.value #>> '{}'), 1) = '/'
        GROUP  BY e.value #>> '{}'
    ) h;

    IF jsonb_array_length(v_clean) > 20 THEN
        RAISE EXCEPTION '318: a Quick Links bar may hold at most 20 links.';
    END IF;

    INSERT INTO public.userquicklinks (userid, farmid, hrefs)
    VALUES (btrim(p_userid), btrim(p_farmid), v_clean)
    ON CONFLICT (lower(userid), lower(farmid))
    DO UPDATE SET hrefs = EXCLUDED.hrefs, updatedat = now();

    RETURN v_clean;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Back to the defaults.
--
-- DELETE, not "set to the default list". The defaults live in the frontend nav
-- config and they change as the product does; a reset that COPIED today's
-- defaults into this table would freeze them, and the user who reset would be
-- the one person who never sees a newly added shortcut.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spuserquicklinks_reset(
    p_userid text,
    p_farmid text
) RETURNS void
LANGUAGE sql
AS $function$
    DELETE FROM public.userquicklinks
    WHERE  lower(userid) = lower(p_userid)
      AND  lower(farmid) = lower(p_farmid);
$function$;

-- -----------------------------------------------------------------------------
-- 5. Verify.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_missing text;
    v_out     jsonb;
BEGIN
    SELECT string_agg(want, ', ')
    INTO   v_missing
    FROM   (VALUES
        ('spuserquicklinks_get'),
        ('spuserquicklinks_set'),
        ('spuserquicklinks_reset')
    ) AS w(want)
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = w.want);

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '318: missing function(s): %', v_missing;
    END IF;

    -- End to end against a user id no one can have, then cleaned up: proves the
    -- upsert, the de-duplication, the order and the reset actually run rather
    -- than merely compiling.
    v_out := public.spuserquicklinks_set(
                 '__318_selftest__', '__318_selftest__',
                 '["/sales", "/expenses", "/sales", "", "not-a-path", 42]'::jsonb);
    IF v_out <> '["/sales", "/expenses"]'::jsonb THEN
        RAISE EXCEPTION '318: set() did not clean and order as expected: %', v_out;
    END IF;

    v_out := public.spuserquicklinks_set(
                 '__318_SELFTEST__', '__318_selftest__', '[]'::jsonb);
    IF (SELECT count(*) FROM public.userquicklinks
         WHERE userid = '__318_selftest__') <> 1 THEN
        RAISE EXCEPTION '318: the user/company key is case sensitive; it must not be.';
    END IF;
    IF (SELECT hrefs FROM public.spuserquicklinks_get(
            '__318_selftest__', '__318_selftest__')) <> '[]'::jsonb THEN
        RAISE EXCEPTION '318: an emptied bar did not come back empty.';
    END IF;

    PERFORM public.spuserquicklinks_reset('__318_selftest__', '__318_selftest__');
    IF EXISTS (SELECT 1 FROM public.spuserquicklinks_get(
                   '__318_selftest__', '__318_selftest__')) THEN
        RAISE EXCEPTION '318: reset left a row behind.';
    END IF;

    RAISE NOTICE '318_UserQuickLinks: 1 table, 3 functions, verified.';
END $$;

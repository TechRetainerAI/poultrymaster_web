-- =============================================================================
-- 328_PoultryFarmSetupDraft.postgres.sql
--
-- Purpose
-- -------
-- Keep an unfinished Initial Farm Setup, so a farm can walk away from it and
-- come back.
--
-- WHAT HAPPENS TODAY
-- ==================
-- The draft lives in the browser's sessionStorage and nowhere else. It survives
-- a refresh and nothing more: navigating to another page for reference and
-- coming back loses it, because restoring depends on the URL still carrying
-- ?step= and a bare link does not. Closing the tab loses it outright.
--
-- A bulk setup is twenty minutes of typing. Losing it to a misclick is the kind
-- of thing that stops a farm trusting the tool.
--
-- ONE DRAFT PER COMPANY, NOT PER USER
-- ===================================
-- Deliberate. A farm's onboarding is one piece of work, not one per person: the
-- manager who starts it on the office desktop should be able to finish it on a
-- phone in the pens, and a supervisor should be able to pick up what a colleague
-- began. updatedby records who touched it last so the wizard can say so before
-- anyone resumes someone else's work.
--
-- The cost is that two people editing at once will overwrite each other, last
-- write winning. That is the same shape as the advisory lock already guarding
-- completion (FarmSetupService), and a far smaller risk than losing the work.
--
-- WHY jsonb AND NOT COLUMNS
-- =========================
-- This is a FORM IN PROGRESS, not a record. Half of it is invalid by definition
-- while someone is typing -- blank bird counts, a flock with no pen yet -- and
-- modelling that as columns would mean a schema that has to accept nonsense, and
-- a migration every time the wizard grows a field. The draft is only ever read
-- back by the screen that wrote it; the moment it becomes real data it goes
-- through sppoultryopeningposition_insert and friends, which do validate.
--
-- The draft is DELETED when the setup completes. It is scaffolding, and leaving
-- it behind would offer to resume work that has already been done.
--
-- Idempotent. Safe to run more than once.
-- EFFECT ON TODAY'S NUMBERS: none. Nothing reads this but the wizard.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The draft.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultryfarmsetupdraft (
    farmsetupdraftid serial PRIMARY KEY,
    farmid           text      NOT NULL,

    -- The wizard's own draft object, verbatim. See the note above on why this is
    -- not a set of columns.
    draft            jsonb     NOT NULL,

    -- Where they were, so resuming lands on the screen they left rather than at
    -- the beginning.
    step             integer   NOT NULL DEFAULT 0,
    phase            text,

    updatedby        text,
    updatedat        timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    createdat        timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

-- One per company. lower() for the same reason poultryfarmsetup uses it: a farm
-- id differing only in case is the same company.
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryfarmsetupdraft_farm
    ON public.poultryfarmsetupdraft (lower(farmid));

-- -----------------------------------------------------------------------------
-- 2. Save. Upsert, because there is only ever one and it is written constantly.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryfarmsetupdraft_save(
    p_farmid    text,
    p_draft     jsonb,
    p_step      integer,
    p_phase     text,
    p_updatedby text)
RETURNS timestamp
LANGUAGE plpgsql
AS $function$
DECLARE
    v_at timestamp;
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN
        RAISE EXCEPTION '328: farmid is required.';
    END IF;

    INSERT INTO public.poultryfarmsetupdraft (farmid, draft, step, phase, updatedby, updatedat)
    VALUES (p_farmid, p_draft, COALESCE(p_step, 0), p_phase, p_updatedby, (now() AT TIME ZONE 'utc'))
    -- The existing row is referenced by the table's UNQUALIFIED name here;
    -- schema-qualifying it is a "missing FROM-clause entry" error.
    ON CONFLICT (lower(farmid)) DO UPDATE
        SET draft     = EXCLUDED.draft,
            step      = EXCLUDED.step,
            phase     = EXCLUDED.phase,
            updatedby = EXCLUDED.updatedby,
            updatedat = EXCLUDED.updatedat
    RETURNING updatedat INTO v_at;

    RETURN v_at;
END
$function$;

-- -----------------------------------------------------------------------------
-- 3. Read it back.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryfarmsetupdraft_get(p_farmid text)
RETURNS TABLE(
    farmsetupdraftid integer,
    farmid           text,
    draft            jsonb,
    step             integer,
    phase            text,
    updatedby        text,
    updatedat        timestamp,
    createdat        timestamp)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT d.farmsetupdraftid, d.farmid::text, d.draft, d.step, d.phase::text,
           d.updatedby::text, d.updatedat, d.createdat
    FROM   public.poultryfarmsetupdraft d
    WHERE  lower(d.farmid) = lower(p_farmid);
END
$function$;

-- -----------------------------------------------------------------------------
-- 4. Throw it away -- on completion, or when the farm says start over.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryfarmsetupdraft_delete(p_farmid text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_rc integer;
BEGIN
    DELETE FROM public.poultryfarmsetupdraft d
    WHERE lower(d.farmid) = lower(p_farmid);

    GET DIAGNOSTICS v_rc = ROW_COUNT;
    RETURN v_rc;  -- 0 is not an error: there may be nothing to discard.
END
$function$;

-- -----------------------------------------------------------------------------
-- 5. Grants, matching the app login used by every other function here.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON public.poultryfarmsetupdraft TO poultryapp;
        GRANT USAGE, SELECT ON SEQUENCE public.poultryfarmsetupdraft_farmsetupdraftid_seq TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryfarmsetupdraft_save(text, jsonb, integer, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryfarmsetupdraft_get(text)    TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryfarmsetupdraft_delete(text) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 6. Verification. Runs after COMMIT so a failure here does not undo the
--    migration -- it tells you the migration is wrong, which is different.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_missing text;
    v_farm    text := '__328_selftest__';
    v_at      timestamp;
    v_again   timestamp;
BEGIN
    SELECT string_agg(want, ', ')
    INTO   v_missing
    FROM   (VALUES
        ('sppoultryfarmsetupdraft_save'),
        ('sppoultryfarmsetupdraft_get'),
        ('sppoultryfarmsetupdraft_delete')
    ) AS w(want)
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = w.want);

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '328: missing function(s): %', v_missing;
    END IF;

    v_at := public.sppoultryfarmsetupdraft_save(
        v_farm, '{"batches":[],"houses":[],"flocks":[]}'::jsonb, 2, 'pens', '__328__');
    IF v_at IS NULL THEN
        RAISE EXCEPTION '328: save returned no timestamp.';
    END IF;

    IF (SELECT step FROM public.sppoultryfarmsetupdraft_get(v_farm)) <> 2 THEN
        RAISE EXCEPTION '328: the draft did not read back at the step it was saved on.';
    END IF;

    -- Saving again REPLACES; a wizard writes this constantly and must not
    -- accumulate a row per keystroke.
    v_again := public.sppoultryfarmsetupdraft_save(
        v_farm, '{"batches":[1],"houses":[],"flocks":[]}'::jsonb, 3, 'allocate', '__328__');
    IF (SELECT count(*) FROM public.poultryfarmsetupdraft WHERE lower(farmid) = v_farm) <> 1 THEN
        RAISE EXCEPTION '328: a second save created a second draft.';
    END IF;
    IF (SELECT step FROM public.sppoultryfarmsetupdraft_get(v_farm)) <> 3 THEN
        RAISE EXCEPTION '328: a second save did not replace the first.';
    END IF;

    -- The company key must not be case sensitive, as with poultryfarmsetup.
    PERFORM public.sppoultryfarmsetupdraft_save(
        '__328_SELFTEST__', '{"batches":[],"houses":[],"flocks":[]}'::jsonb, 1, NULL, '__328__');
    IF (SELECT count(*) FROM public.poultryfarmsetupdraft WHERE lower(farmid) = v_farm) <> 1 THEN
        RAISE EXCEPTION '328: the company key is case sensitive; it must not be.';
    END IF;

    IF public.sppoultryfarmsetupdraft_delete(v_farm) <> 1 THEN
        RAISE EXCEPTION '328: delete did not remove the draft.';
    END IF;
    IF (SELECT count(*) FROM public.sppoultryfarmsetupdraft_get(v_farm)) <> 0 THEN
        RAISE EXCEPTION '328: the draft survived being deleted.';
    END IF;
    -- Discarding nothing is not an error.
    IF public.sppoultryfarmsetupdraft_delete(v_farm) <> 0 THEN
        RAISE EXCEPTION '328: deleting an absent draft reported a deletion.';
    END IF;

    RAISE NOTICE '328_PoultryFarmSetupDraft: 1 table, 3 functions, verified.';
END $$;

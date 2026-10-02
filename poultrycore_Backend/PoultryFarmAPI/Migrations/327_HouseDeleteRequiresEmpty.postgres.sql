-- =============================================================================
-- 327_HouseDeleteRequiresEmpty.postgres.sql
--
-- Purpose
-- -------
-- Stop a house being deleted while birds are still in it.
--
-- WHAT HAPPENS TODAY
-- ==================
-- sphouse_delete is an unguarded DELETE FROM houses, and the houses table has NO
-- foreign keys pointing at it -- nothing in the schema refuses. flock.houseid is
-- a plain integer, so deleting a pen that holds flocks leaves every one of them
-- pointing at a house id that no longer exists. The flocks keep their birds and
-- lose their location, silently: no error, no cascade, no null-out.
--
-- The Houses page cannot catch it either. It never loads flocks, so it has no
-- idea whether the pen it is about to delete is occupied.
--
-- THE RULE
-- ========
-- A house with ACTIVE flocks in it cannot be deleted. Active is the same
-- definition occupancy uses everywhere else in this application -- see
-- FlockController.BuildOccupancy and FlockAllocationValidator -- so "occupied"
-- means one thing across the whole module.
--
-- WHY NOT ALSO BLOCK ON INACTIVE FLOCKS
-- =====================================
-- An inactive flock still names the house it lived in, and deleting the house
-- does orphan that reference too. But a pen that has been decommissioned must
-- remain deletable, and a farm that has ever used a house would otherwise be
-- stuck with it forever. Blocking on what is standing there now is the rule the
-- farm actually means by "the house is in use".
--
-- WHY A GUARD AND NOT A FOREIGN KEY
-- =================================
-- A FK on flock.houseid would be the stronger fix and is the right long-term
-- answer. It is not this migration: houseid is nullable and this schema has
-- never enforced it, so existing rows would have to be audited for ids that
-- already point at nothing before a constraint could be added without failing.
-- That is its own piece of work; this closes the hole that is losing data now.
--
-- Idempotent. Safe to run more than once.
-- EFFECT ON TODAY'S NUMBERS: none. It only refuses a delete that would have
-- orphaned flocks.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.sphouse_delete(
    p_houseid integer,
    p_userid  text,
    p_farmid  text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_rc     integer;
    v_flocks integer;
    v_birds  integer;
    v_name   text;
BEGIN
    -- Refuse BEFORE deleting. The message names what is in the way, because
    -- "could not delete" without a reason is what sends someone to support.
    SELECT count(*)::int, COALESCE(SUM(f.quantity), 0)::int
    INTO   v_flocks, v_birds
    FROM   flock f
    WHERE  f.houseid = p_houseid
      AND  f.farmid = p_farmid
      AND  f.active = TRUE
      AND  COALESCE(f.isdeleted, FALSE) = FALSE;

    IF v_flocks > 0 THEN
        SELECT h.housename INTO v_name
        FROM   houses h
        WHERE  h.houseid = p_houseid AND h.farmid = p_farmid;

        RAISE EXCEPTION
            '% still has % flock(s) in it holding % bird(s). Move or close them before deleting the house.',
            COALESCE(v_name, 'That house'), v_flocks, v_birds
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    DELETE FROM houses h
    WHERE h.houseid = p_houseid
      AND h.userid = p_userid
      AND h.farmid = p_farmid;

    GET DIAGNOSTICS v_rc = ROW_COUNT;
    IF v_rc = 0 THEN
        RAISE EXCEPTION 'House not found or access denied';
    END IF;
END
$function$;

-- -----------------------------------------------------------------------------
-- Read side: how many birds a house holds, so a caller can ask before offering
-- a delete rather than finding out by being refused.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sphouse_getoccupancy(p_farmid text)
RETURNS TABLE(houseid integer, activeflocks integer, occupied integer)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT f.houseid,
           count(*)::int,
           COALESCE(SUM(f.quantity), 0)::int
    FROM   flock f
    WHERE  f.farmid = p_farmid
      AND  f.houseid IS NOT NULL
      AND  f.active = TRUE
      AND  COALESCE(f.isdeleted, FALSE) = FALSE
    GROUP  BY f.houseid;
END
$function$;

DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.sphouse_delete(integer, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sphouse_getoccupancy(text)          TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification. Runs after COMMIT so a failure here does not undo the migration.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_farm  text := '__327_selftest__';
    v_house integer;
    v_flock integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'public' AND p.proname = 'sphouse_getoccupancy') THEN
        RAISE EXCEPTION '327: sphouse_getoccupancy is missing.';
    END IF;

    INSERT INTO houses (userid, farmid, housename, capacity, location)
    VALUES ('__327__', v_farm, 'Selftest Pen', 100, NULL)
    RETURNING houseid INTO v_house;

    -- Empty: deletes cleanly.
    PERFORM public.sphouse_delete(v_house, '__327__', v_farm);
    IF EXISTS (SELECT 1 FROM houses WHERE houseid = v_house) THEN
        RAISE EXCEPTION '327: an empty house was not deleted.';
    END IF;

    -- Occupied: refused, and the house survives.
    INSERT INTO houses (userid, farmid, housename, capacity, location)
    VALUES ('__327__', v_farm, 'Selftest Pen 2', 100, NULL)
    RETURNING houseid INTO v_house;

    INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, batchid, houseid)
    VALUES ('__327__', v_farm, 'Selftest flock', CURRENT_DATE, 'Brown', 50, TRUE, -327, v_house)
    RETURNING flockid INTO v_flock;

    BEGIN
        PERFORM public.sphouse_delete(v_house, '__327__', v_farm);
        RAISE EXCEPTION '327: a house holding flocks was deleted.';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;  -- expected
    END;

    IF NOT EXISTS (SELECT 1 FROM houses WHERE houseid = v_house) THEN
        RAISE EXCEPTION '327: the refused delete removed the house anyway.';
    END IF;

    IF (SELECT occupied FROM public.sphouse_getoccupancy(v_farm) WHERE houseid = v_house) <> 50 THEN
        RAISE EXCEPTION '327: occupancy did not report the 50 birds.';
    END IF;

    -- Once the flock is closed, the pen can go.
    UPDATE flock SET active = FALSE WHERE flockid = v_flock;
    PERFORM public.sphouse_delete(v_house, '__327__', v_farm);
    IF EXISTS (SELECT 1 FROM houses WHERE houseid = v_house) THEN
        RAISE EXCEPTION '327: a house whose flocks are all closed could not be deleted.';
    END IF;

    -- flock carries a soft-delete trigger, so this row is retired rather than
    -- removed; scoped to a farm id no company can have.
    DELETE FROM flock WHERE flockid = v_flock;
    DELETE FROM houses WHERE farmid = v_farm;

    RAISE NOTICE '327_HouseDeleteRequiresEmpty: 2 functions, verified.';
END $$;

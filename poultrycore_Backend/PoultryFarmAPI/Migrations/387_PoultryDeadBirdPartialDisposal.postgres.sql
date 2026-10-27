-- =============================================================================
-- 387_PoultryDeadBirdPartialDisposal.postgres.sql
--
-- Purpose
-- -------
-- 386 for dead birds. A production record's mortality was all-or-nothing
-- (372): Keep put every dead bird into Dead Birds stock, "Disposed
-- immediately" disposed every one. A farm that buries some of the day's dead
-- birds and keeps the rest (to sell or use) could not record that.
--
-- productionrecords.mortalitydisposed = how many of the record's dead birds
-- were disposed at once. The rest go into Dead Birds stock.
--   NULL   (every record before this migration, and an older client) -- the
--          372 rule: mortalitydisposition Disposed = all, Keep = none.
--   0..n   that many, n = the record's mortality. More than n is refused.
-- mortalitydisposition is kept in step (Disposed when any were disposed).
--
-- No backfill: NULL already means what the record had. Records before the
-- byproduct cutover stay history, disposed in full (381).
--
-- Live birds are unchanged: they fall by the whole mortality whatever is
-- disposed. Only the Dead Birds stock split changes.
--
-- Deploy order: this migration, then the API, then the web app. The old API
-- keeps working: the new setdisposition parameter has a default, and the
-- dispositions reader only gains a trailing column.
-- =============================================================================
BEGIN;

ALTER TABLE public.productionrecords ADD COLUMN IF NOT EXISTS mortalitydisposed integer;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_productionrecords_mortalitydisposed') THEN
        ALTER TABLE public.productionrecords ADD CONSTRAINT ck_productionrecords_mortalitydisposed
            CHECK (mortalitydisposed IS NULL OR mortalitydisposed >= 0);
    END IF;
END $$;

-- How many of a record's broken eggs / dead birds are disposed at once. The
-- 386 rule (fnpoultry_brokeneggsdisposed) under a name that fits both; the 386
-- function stays, as a wrapper, for anything already calling it.
CREATE OR REPLACE FUNCTION public.fnpoultry_disposedatonce(p_count integer, p_disposed integer,
    p_disposition text, p_hist boolean)
RETURNS integer LANGUAGE sql IMMUTABLE AS $f$
    SELECT CASE
             WHEN p_hist                     THEN GREATEST(COALESCE(p_count, 0), 0)
             WHEN p_disposed IS NOT NULL     THEN LEAST(GREATEST(p_disposed, 0), GREATEST(COALESCE(p_count, 0), 0))
             WHEN p_disposition = 'Disposed' THEN GREATEST(COALESCE(p_count, 0), 0)
             ELSE 0
           END;
$f$;

CREATE OR REPLACE FUNCTION public.fnpoultry_brokeneggsdisposed(p_broken integer, p_disposed integer,
    p_disposition text, p_hist boolean)
RETURNS integer LANGUAGE sql IMMUTABLE AS $f$
    SELECT fnpoultry_disposedatonce(p_broken, p_disposed, p_disposition, p_hist);
$f$;

-- ------------------------------------------------------- the sync (body of 386) --
CREATE OR REPLACE FUNCTION public.sppoultrybyproduct_syncforproduction(p_farmid text, p_recordid integer,
    p_remove boolean DEFAULT false, p_by text DEFAULT NULL::text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    v_pr       record;
    v_cutover  timestamp;
    v_hist     boolean;
    v_broken   numeric := 0;
    v_bout     numeric := 0;
    v_dead     numeric := 0;
    v_dout     numeric := 0;
    v_bb       numeric;
    v_db       numeric;
    v_label    text;
BEGIN
    SELECT pr.* INTO v_pr FROM productionrecords pr WHERE pr.id = p_recordid AND pr.farmid = p_farmid;
    IF NOT FOUND THEN RETURN; END IF;

    -- 381: a record entered before the cutover is history, already disposed:
    -- it is posted (so reports see it) but never adds to stock.
    SELECT s.cutoverat INTO v_cutover FROM poultrybyproductsettings s WHERE s.farmid = p_farmid;
    v_hist  := v_cutover IS NOT NULL AND v_pr.createdat < v_cutover;

    IF NOT p_remove THEN
        v_broken := GREATEST(COALESCE(v_pr.brokeneggs, 0), 0);
        v_dead   := GREATEST(COALESCE(v_pr.mortality, 0), 0);
        -- 386 / 387: some, all or none disposed at once.
        v_bout   := fnpoultry_disposedatonce(v_pr.brokeneggs, v_pr.brokeneggsdisposed, v_pr.brokeneggdisposition, v_hist);
        v_dout   := fnpoultry_disposedatonce(v_pr.mortality,  v_pr.mortalitydisposed,  v_pr.mortalitydisposition,  v_hist);
    END IF;
    v_label := CASE WHEN v_hist THEN 'History (before tracking) - ' ELSE '' END
               || 'Production ' || to_char(v_pr.date, 'YYYY-MM-DD');
    v_bb := fnpoultry_byproductonhand(p_farmid, 'BrokenEggs');
    v_db := fnpoultry_byproductonhand(p_farmid, 'DeadBirds');

    -- Disposal first when it shrinks (a reversal puts it back before the
    -- generation comes off), generation first when it grows.
    PERFORM sppoultrybyproduct_post(p_farmid, 'BrokenEggs', 'Broken Egg Disposal', p_recordid,
        -v_bout, v_pr.date, 'Disposed at once - ' || v_label, p_by);
    PERFORM sppoultrybyproduct_post(p_farmid, 'BrokenEggs', 'Broken Egg Prod', p_recordid, v_broken, v_pr.date, 'Broken eggs - ' || v_label, p_by);
    PERFORM sppoultrybyproduct_post(p_farmid, 'DeadBirds', 'Mortality Disposal', p_recordid,
        -v_dout, v_pr.date, 'Disposed at once - ' || v_label, p_by);
    PERFORM sppoultrybyproduct_post(p_farmid, 'DeadBirds', 'Mortality In', p_recordid, v_dead, v_pr.date, 'Mortality - ' || v_label, p_by);

    PERFORM fnpoultry_byproductguard(p_farmid, 'BrokenEggs', v_bb, CASE WHEN p_remove THEN 'reversal' ELSE 'change' END);
    PERFORM fnpoultry_byproductguard(p_farmid, 'DeadBirds',  v_db, CASE WHEN p_remove THEN 'reversal' ELSE 'change' END);
END
$function$;

-- ------------------------------------------------------- setdisposition --
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT p.oid::regprocedure AS sig FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname IN ('sppoultryproduction_setdisposition', 'sppoultryproduction_dispositions') LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig;
    END LOOP;
END $$;

-- p_brokeneggsdisposed / p_mortalitydisposed: how many were disposed at once
-- (NULL = from the Keep / Disposed choice: Disposed = all, Keep = none).
CREATE FUNCTION public.sppoultryproduction_setdisposition(p_farmid text, p_recordid integer,
    p_mortalitydisposition text, p_brokeneggdisposition text, p_by text DEFAULT NULL::text,
    p_brokeneggsdisposed integer DEFAULT NULL, p_mortalitydisposed integer DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    v_pr       record;
    v_broken   integer;
    v_dead     integer;
    v_bout     integer;
    v_dout     integer;
    v_bdisp    text;
    v_mdisp    text;
BEGIN
    SELECT pr.*, (s.cutoverat IS NOT NULL AND pr.createdat < s.cutoverat) AS hist INTO v_pr
    FROM   productionrecords pr
    LEFT   JOIN poultrybyproductsettings s ON s.farmid = pr.farmid
    WHERE  pr.id = p_recordid AND pr.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Production record not found for this company.' USING ERRCODE = 'P0001';
    END IF;
    v_broken := GREATEST(COALESCE(v_pr.brokeneggs, 0), 0);
    v_dead   := GREATEST(COALESCE(v_pr.mortality, 0), 0);

    -- 381: history is already disposed; stock still held is entered by hand.
    IF v_pr.hist AND ((p_mortalitydisposition = 'Keep' AND v_dead > 0)
                   OR (p_brokeneggdisposition = 'Keep' AND v_broken > 0)
                   OR (p_brokeneggsdisposed IS NOT NULL AND p_brokeneggsdisposed < v_broken)
                   OR (p_mortalitydisposed  IS NOT NULL AND p_mortalitydisposed  < v_dead)) THEN
        RAISE EXCEPTION 'This record was entered before Broken Eggs and Dead Birds were tracked, so its broken eggs and dead birds count as already disposed. If you still hold some, add them with Stock movements > New movement > Opening Inventory.'
            USING ERRCODE = 'P0001';
    END IF;

    -- 386: broken eggs. A count wins over the Keep / Disposed choice.
    IF p_brokeneggsdisposed IS NOT NULL THEN
        IF p_brokeneggsdisposed < 0 THEN
            RAISE EXCEPTION 'Broken eggs disposed cannot be negative.' USING ERRCODE = 'P0001';
        END IF;
        IF p_brokeneggsdisposed > v_broken THEN
            RAISE EXCEPTION 'Broken eggs disposed (%) cannot be more than the broken eggs recorded (%).',
                p_brokeneggsdisposed, v_broken USING ERRCODE = 'P0001';
        END IF;
        v_bout := p_brokeneggsdisposed;
    ELSIF NULLIF(p_brokeneggdisposition, '') IS NOT NULL THEN
        v_bout := CASE WHEN p_brokeneggdisposition = 'Disposed' THEN v_broken ELSE 0 END;   -- older client
    ELSE
        v_bout := v_pr.brokeneggsdisposed;                                                  -- not sent: unchanged
    END IF;

    -- 387: dead birds, the same way.
    IF p_mortalitydisposed IS NOT NULL THEN
        IF p_mortalitydisposed < 0 THEN
            RAISE EXCEPTION 'Dead birds disposed cannot be negative.' USING ERRCODE = 'P0001';
        END IF;
        IF p_mortalitydisposed > v_dead THEN
            RAISE EXCEPTION 'Dead birds disposed (%) cannot be more than the deaths recorded (%).',
                p_mortalitydisposed, v_dead USING ERRCODE = 'P0001';
        END IF;
        v_dout := p_mortalitydisposed;
    ELSIF NULLIF(p_mortalitydisposition, '') IS NOT NULL THEN
        v_dout := CASE WHEN p_mortalitydisposition = 'Disposed' THEN v_dead ELSE 0 END;
    ELSE
        v_dout := v_pr.mortalitydisposed;
    END IF;

    v_bdisp := CASE WHEN v_bout IS NULL THEN v_pr.brokeneggdisposition WHEN v_bout > 0 THEN 'Disposed' ELSE 'Keep' END;
    v_mdisp := CASE WHEN v_dout IS NULL THEN v_pr.mortalitydisposition WHEN v_dout > 0 THEN 'Disposed' ELSE 'Keep' END;

    UPDATE productionrecords pr
    SET    mortalitydisposition = v_mdisp,
           brokeneggdisposition = v_bdisp,
           brokeneggsdisposed   = v_bout,
           mortalitydisposed    = v_dout
    WHERE  pr.id = p_recordid AND pr.farmid = p_farmid
      -- Nothing to write when nothing changes: no pointless trigger run.
      AND  (pr.mortalitydisposition IS DISTINCT FROM v_mdisp
            OR pr.brokeneggdisposition IS DISTINCT FROM v_bdisp
            OR pr.brokeneggsdisposed   IS DISTINCT FROM v_bout
            OR pr.mortalitydisposed    IS DISTINCT FROM v_dout);
    PERFORM sppoultrybyproduct_syncforproduction(p_farmid, p_recordid, FALSE, p_by);
END
$function$;

-- ------------------------------------------------------- dispositions reader --
-- 387: + mortalitydisposed (trailing, after 386's brokeneggsdisposed).
CREATE FUNCTION public.sppoultryproduction_dispositions(p_farmid text)
RETURNS TABLE(id integer, mortalitydisposition text, brokeneggdisposition text,
              brokeneggsdisposed integer, mortalitydisposed integer)
LANGUAGE sql STABLE AS $function$
    -- 381: a record entered before the cutover shows as Disposed (history).
    SELECT pr.id,
           CASE WHEN h.hist AND COALESCE(pr.mortality, 0) > 0  THEN 'Disposed' ELSE pr.mortalitydisposition END,
           CASE WHEN h.hist AND COALESCE(pr.brokeneggs, 0) > 0 THEN 'Disposed' ELSE pr.brokeneggdisposition END,
           fnpoultry_disposedatonce(pr.brokeneggs, pr.brokeneggsdisposed, pr.brokeneggdisposition, h.hist),
           fnpoultry_disposedatonce(pr.mortality,  pr.mortalitydisposed,  pr.mortalitydisposition,  h.hist)
    FROM   productionrecords pr
    LEFT   JOIN poultrybyproductsettings s ON s.farmid = pr.farmid
    CROSS  JOIN LATERAL (SELECT (s.cutoverat IS NOT NULL AND pr.createdat < s.cutoverat) AS hist) h
    WHERE  pr.farmid = p_farmid
      AND  (pr.mortalitydisposition <> 'Keep' OR pr.brokeneggdisposition <> 'Keep'
            OR COALESCE(pr.brokeneggsdisposed, 0) > 0 OR COALESCE(pr.mortalitydisposed, 0) > 0
            OR (h.hist AND (COALESCE(pr.mortality, 0) > 0 OR COALESCE(pr.brokeneggs, 0) > 0)));
$function$;

COMMIT;

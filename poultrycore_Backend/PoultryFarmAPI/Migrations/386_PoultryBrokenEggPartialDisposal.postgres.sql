-- =============================================================================
-- 386_PoultryBrokenEggPartialDisposal.postgres.sql
--
-- Purpose
-- -------
-- A production record's broken eggs were all-or-nothing (372): Keep put every
-- one into Broken Eggs stock, "Disposed immediately" disposed every one. A farm
-- that throws some of the day's broken eggs away and keeps the rest (to sell
-- or use) could not record that.
--
-- productionrecords.brokeneggsdisposed = how many of the record's broken eggs
-- were disposed at once. The rest go into Broken Eggs stock.
--   NULL   (every record before this migration, and an older client) -- the
--          372 rule: brokeneggdisposition Disposed = all, Keep = none.
--   0..n   that many, n = the record's broken eggs. More than n is refused.
-- brokeneggdisposition is kept in step (Disposed when any were disposed) so
-- older readers still see a sensible value.
--
-- No backfill: NULL already means what the record had. Records before the
-- byproduct cutover stay history, disposed in full (381).
--
-- The ledger rows are unchanged in kind ('Broken Egg Disposal' for the
-- record), so reports, trackers and the byproduct ledger need no change.
--
-- Deploy order: this migration, then the API, then the web app. The old API
-- keeps working: the new setdisposition parameter has a default, and the
-- dispositions reader only gains a trailing column.
-- =============================================================================
BEGIN;

ALTER TABLE public.productionrecords ADD COLUMN IF NOT EXISTS brokeneggsdisposed integer;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_productionrecords_brokeneggsdisposed') THEN
        ALTER TABLE public.productionrecords ADD CONSTRAINT ck_productionrecords_brokeneggsdisposed
            CHECK (brokeneggsdisposed IS NULL OR brokeneggsdisposed >= 0);
    END IF;
END $$;

-- How many of a record's broken eggs are disposed at once. One rule for the
-- sync and the reader.
CREATE OR REPLACE FUNCTION public.fnpoultry_brokeneggsdisposed(p_broken integer, p_disposed integer,
    p_disposition text, p_hist boolean)
RETURNS integer LANGUAGE sql IMMUTABLE AS $f$
    SELECT CASE
             WHEN p_hist                   THEN GREATEST(COALESCE(p_broken, 0), 0)
             WHEN p_disposed IS NOT NULL   THEN LEAST(GREATEST(p_disposed, 0), GREATEST(COALESCE(p_broken, 0), 0))
             WHEN p_disposition = 'Disposed' THEN GREATEST(COALESCE(p_broken, 0), 0)
             ELSE 0
           END;
$f$;

-- ------------------------------------------------------- the sync (live body of 381) --
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
    v_mdisp    text;
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
    v_mdisp := CASE WHEN v_hist THEN 'Disposed' ELSE v_pr.mortalitydisposition END;

    IF NOT p_remove THEN
        v_broken := GREATEST(COALESCE(v_pr.brokeneggs, 0), 0);
        v_dead   := GREATEST(COALESCE(v_pr.mortality, 0), 0);
        -- 386: some, all or none of the broken eggs disposed at once.
        v_bout   := fnpoultry_brokeneggsdisposed(v_pr.brokeneggs, v_pr.brokeneggsdisposed, v_pr.brokeneggdisposition, v_hist);
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
        CASE WHEN v_mdisp = 'Disposed' THEN -v_dead ELSE 0 END, v_pr.date, 'Disposed at once - ' || v_label, p_by);
    PERFORM sppoultrybyproduct_post(p_farmid, 'DeadBirds', 'Mortality In', p_recordid, v_dead, v_pr.date, 'Mortality - ' || v_label, p_by);

    PERFORM fnpoultry_byproductguard(p_farmid, 'BrokenEggs', v_bb, CASE WHEN p_remove THEN 'reversal' ELSE 'change' END);
    PERFORM fnpoultry_byproductguard(p_farmid, 'DeadBirds',  v_db, CASE WHEN p_remove THEN 'reversal' ELSE 'change' END);
END
$function$;

-- ------------------------------------------------------- setdisposition --
-- Signature grows by one defaulted parameter: drop every overload BY NAME.
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT p.oid::regprocedure AS sig FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname IN ('sppoultryproduction_setdisposition', 'sppoultryproduction_dispositions') LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig;
    END LOOP;
END $$;

-- p_brokeneggsdisposed: how many broken eggs were disposed at once (NULL =
-- from p_brokeneggdisposition: Disposed = all, Keep = none).
CREATE FUNCTION public.sppoultryproduction_setdisposition(p_farmid text, p_recordid integer,
    p_mortalitydisposition text, p_brokeneggdisposition text, p_by text DEFAULT NULL::text,
    p_brokeneggsdisposed integer DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    v_pr       record;
    v_broken   integer;
    v_disposed integer;
    v_bdisp    text;
BEGIN
    SELECT pr.*, (s.cutoverat IS NOT NULL AND pr.createdat < s.cutoverat) AS hist INTO v_pr
    FROM   productionrecords pr
    LEFT   JOIN poultrybyproductsettings s ON s.farmid = pr.farmid
    WHERE  pr.id = p_recordid AND pr.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Production record not found for this company.' USING ERRCODE = 'P0001';
    END IF;
    v_broken := GREATEST(COALESCE(v_pr.brokeneggs, 0), 0);

    -- 381: history is already disposed; stock still held is entered by hand.
    IF v_pr.hist AND ((p_mortalitydisposition = 'Keep' AND COALESCE(v_pr.mortality, 0) > 0)
                   OR (p_brokeneggdisposition = 'Keep' AND v_broken > 0)
                   OR (p_brokeneggsdisposed IS NOT NULL AND p_brokeneggsdisposed < v_broken)) THEN
        RAISE EXCEPTION 'This record was entered before Broken Eggs and Dead Birds were tracked, so its broken eggs and dead birds count as already disposed. If you still hold some, add them with Stock movements > New movement > Opening Inventory.'
            USING ERRCODE = 'P0001';
    END IF;

    -- 386: a count wins over the Keep / Disposed choice.
    IF p_brokeneggsdisposed IS NOT NULL THEN
        IF p_brokeneggsdisposed < 0 THEN
            RAISE EXCEPTION 'Broken eggs disposed cannot be negative.' USING ERRCODE = 'P0001';
        END IF;
        IF p_brokeneggsdisposed > v_broken THEN
            RAISE EXCEPTION 'Broken eggs disposed (%) cannot be more than the broken eggs recorded (%).',
                p_brokeneggsdisposed, v_broken USING ERRCODE = 'P0001';
        END IF;
        v_disposed := p_brokeneggsdisposed;
    ELSIF NULLIF(p_brokeneggdisposition, '') IS NOT NULL THEN
        -- An older client: Disposed = all of them, Keep = none.
        v_disposed := CASE WHEN p_brokeneggdisposition = 'Disposed' THEN v_broken ELSE 0 END;
    ELSE
        v_disposed := v_pr.brokeneggsdisposed;       -- not sent: unchanged
    END IF;
    v_bdisp := CASE
                 WHEN v_disposed IS NULL THEN v_pr.brokeneggdisposition
                 WHEN v_disposed > 0     THEN 'Disposed'
                 ELSE 'Keep'
               END;

    UPDATE productionrecords pr
    SET    mortalitydisposition = COALESCE(NULLIF(p_mortalitydisposition, ''), pr.mortalitydisposition),
           brokeneggdisposition = v_bdisp,
           brokeneggsdisposed   = v_disposed
    WHERE  pr.id = p_recordid AND pr.farmid = p_farmid
      -- Nothing to write when nothing changes: no pointless trigger run.
      AND  (pr.mortalitydisposition IS DISTINCT FROM COALESCE(NULLIF(p_mortalitydisposition, ''), pr.mortalitydisposition)
            OR pr.brokeneggdisposition IS DISTINCT FROM v_bdisp
            OR pr.brokeneggsdisposed   IS DISTINCT FROM v_disposed);
    PERFORM sppoultrybyproduct_syncforproduction(p_farmid, p_recordid, FALSE, p_by);
END
$function$;

-- ------------------------------------------------------- dispositions reader --
-- 386: + brokeneggsdisposed, the count actually disposed (trailing column, so
-- the old API's reads by position still work).
CREATE FUNCTION public.sppoultryproduction_dispositions(p_farmid text)
RETURNS TABLE(id integer, mortalitydisposition text, brokeneggdisposition text, brokeneggsdisposed integer)
LANGUAGE sql STABLE AS $function$
    -- 381: a record entered before the cutover shows as Disposed (history).
    SELECT pr.id,
           CASE WHEN h.hist AND COALESCE(pr.mortality, 0) > 0  THEN 'Disposed' ELSE pr.mortalitydisposition END,
           CASE WHEN h.hist AND COALESCE(pr.brokeneggs, 0) > 0 THEN 'Disposed' ELSE pr.brokeneggdisposition END,
           fnpoultry_brokeneggsdisposed(pr.brokeneggs, pr.brokeneggsdisposed, pr.brokeneggdisposition, h.hist)
    FROM   productionrecords pr
    LEFT   JOIN poultrybyproductsettings s ON s.farmid = pr.farmid
    CROSS  JOIN LATERAL (SELECT (s.cutoverat IS NOT NULL AND pr.createdat < s.cutoverat) AS hist) h
    WHERE  pr.farmid = p_farmid
      AND  (pr.mortalitydisposition <> 'Keep' OR pr.brokeneggdisposition <> 'Keep'
            OR COALESCE(pr.brokeneggsdisposed, 0) > 0
            OR (h.hist AND (COALESCE(pr.mortality, 0) > 0 OR COALESCE(pr.brokeneggs, 0) > 0)));
$function$;

COMMIT;

-- =============================================================================
-- 381_PoultryByproductHistory.postgres.sql                 (requires 372, 379)
--
-- Purpose
-- -------
-- Byproduct stock (372) started at the cutover: production records entered
-- BEFORE it put nothing into Broken Eggs / Dead Birds, so the reports could not
-- see any of the broken eggs or mortality already recorded.
--
-- Decision (user, 2026-10-15): history counts as ALREADY DISPOSED. Each record
-- entered before the cutover gets its generation row AND a matching disposal
-- row, so
--   * reports (Byproduct Inventory & Disposition, Mortality, flock reports)
--     show the full history as generated and disposed;
--   * stock on hand does not change -- nothing appears that is not there.
--
-- How:
--   sppoultrybyproduct_syncforproduction  a record entered before the cutover
--       is no longer skipped; its dispositions are taken as Disposed whatever
--       the columns say (they default to Keep). So editing or deleting an old
--       record can never add stock either. The production records themselves
--       are NOT updated (that would fire the closeout, sorting and feed-usage
--       triggers on 100s of old rows).
--   sppoultryproduction_dispositions  reports Disposed for such a record, so
--       the form shows "Disposed immediately".
--   sppoultryproduction_setdisposition  refuses Keep on such a record, with
--       the way to enter stock still held (an Opening Inventory movement).
--   Backfill: every pre-cutover record with broken eggs or mortality is
--       synced, and its rows are stamped with the record's own entry time
--       (effectivedate = the record's date, as 379), so Stock movements lists
--       them with their records rather than at the top today.
--
-- Egg-sorting breakage before the cutover is not included.
-- =============================================================================
BEGIN;

-- ------------------------------------------------------- 1. the sync -------
CREATE OR REPLACE FUNCTION public.sppoultrybyproduct_syncforproduction(p_farmid text, p_recordid integer, p_remove boolean DEFAULT false, p_by text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_pr       record;
    v_cutover  timestamp;
    v_hist     boolean;
    v_broken   numeric := 0;
    v_dead     numeric := 0;
    v_bdisp    text;
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
    v_bdisp := CASE WHEN v_hist THEN 'Disposed' ELSE v_pr.brokeneggdisposition END;
    v_mdisp := CASE WHEN v_hist THEN 'Disposed' ELSE v_pr.mortalitydisposition END;

    IF NOT p_remove THEN
        v_broken := GREATEST(COALESCE(v_pr.brokeneggs, 0), 0);
        v_dead   := GREATEST(COALESCE(v_pr.mortality, 0), 0);
    END IF;
    v_label := CASE WHEN v_hist THEN 'History (before tracking) - ' ELSE '' END
               || 'Production ' || to_char(v_pr.date, 'YYYY-MM-DD');
    v_bb := fnpoultry_byproductonhand(p_farmid, 'BrokenEggs');
    v_db := fnpoultry_byproductonhand(p_farmid, 'DeadBirds');

    -- Disposal first when it shrinks (a reversal puts it back before the
    -- generation comes off), generation first when it grows.
    PERFORM sppoultrybyproduct_post(p_farmid, 'BrokenEggs', 'Broken Egg Disposal', p_recordid,
        CASE WHEN v_bdisp = 'Disposed' THEN -v_broken ELSE 0 END, v_pr.date, 'Disposed at once - ' || v_label, p_by);
    PERFORM sppoultrybyproduct_post(p_farmid, 'BrokenEggs', 'Broken Egg Prod', p_recordid, v_broken, v_pr.date, 'Broken eggs - ' || v_label, p_by);
    PERFORM sppoultrybyproduct_post(p_farmid, 'DeadBirds', 'Mortality Disposal', p_recordid,
        CASE WHEN v_mdisp = 'Disposed' THEN -v_dead ELSE 0 END, v_pr.date, 'Disposed at once - ' || v_label, p_by);
    PERFORM sppoultrybyproduct_post(p_farmid, 'DeadBirds', 'Mortality In', p_recordid, v_dead, v_pr.date, 'Mortality - ' || v_label, p_by);

    PERFORM fnpoultry_byproductguard(p_farmid, 'BrokenEggs', v_bb, CASE WHEN p_remove THEN 'reversal' ELSE 'change' END);
    PERFORM fnpoultry_byproductguard(p_farmid, 'DeadBirds',  v_db, CASE WHEN p_remove THEN 'reversal' ELSE 'change' END);
END
$function$;

-- ------------------------------------------- 2. what the form is shown ------
CREATE OR REPLACE FUNCTION public.sppoultryproduction_dispositions(p_farmid text)
 RETURNS TABLE(id integer, mortalitydisposition text, brokeneggdisposition text)
 LANGUAGE sql
 STABLE
AS $function$
    -- 381: a record entered before the cutover shows as Disposed (history).
    SELECT pr.id,
           CASE WHEN h.hist AND COALESCE(pr.mortality, 0) > 0  THEN 'Disposed' ELSE pr.mortalitydisposition END,
           CASE WHEN h.hist AND COALESCE(pr.brokeneggs, 0) > 0 THEN 'Disposed' ELSE pr.brokeneggdisposition END
    FROM   productionrecords pr
    LEFT   JOIN poultrybyproductsettings s ON s.farmid = pr.farmid
    CROSS  JOIN LATERAL (SELECT (s.cutoverat IS NOT NULL AND pr.createdat < s.cutoverat) AS hist) h
    WHERE  pr.farmid = p_farmid
      AND  (pr.mortalitydisposition <> 'Keep' OR pr.brokeneggdisposition <> 'Keep'
            OR (h.hist AND (COALESCE(pr.mortality, 0) > 0 OR COALESCE(pr.brokeneggs, 0) > 0)));
$function$;

-- ------------------------------------------- 3. setting it from the form ----
CREATE OR REPLACE FUNCTION public.sppoultryproduction_setdisposition(p_farmid text, p_recordid integer, p_mortalitydisposition text, p_brokeneggdisposition text, p_by text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_pr   record;
    v_hist boolean;
BEGIN
    SELECT pr.*, (s.cutoverat IS NOT NULL AND pr.createdat < s.cutoverat) AS hist INTO v_pr
    FROM   productionrecords pr
    LEFT   JOIN poultrybyproductsettings s ON s.farmid = pr.farmid
    WHERE  pr.id = p_recordid AND pr.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Production record not found for this company.' USING ERRCODE = 'P0001';
    END IF;

    -- 381: history is already disposed; stock still held is entered by hand.
    IF v_pr.hist AND ((p_mortalitydisposition = 'Keep' AND COALESCE(v_pr.mortality, 0) > 0)
                   OR (p_brokeneggdisposition = 'Keep' AND COALESCE(v_pr.brokeneggs, 0) > 0)) THEN
        RAISE EXCEPTION 'This record was entered before Broken Eggs and Dead Birds were tracked, so its broken eggs and dead birds count as already disposed. If you still hold some, add them with Stock movements > New movement > Opening Inventory.'
            USING ERRCODE = 'P0001';
    END IF;

    UPDATE productionrecords pr
    SET    mortalitydisposition = COALESCE(NULLIF(p_mortalitydisposition, ''), pr.mortalitydisposition),
           brokeneggdisposition = COALESCE(NULLIF(p_brokeneggdisposition, ''), pr.brokeneggdisposition)
    WHERE  pr.id = p_recordid AND pr.farmid = p_farmid
      -- Nothing to write when nothing changes: no pointless trigger run.
      AND  (pr.mortalitydisposition IS DISTINCT FROM COALESCE(NULLIF(p_mortalitydisposition, ''), pr.mortalitydisposition)
            OR pr.brokeneggdisposition IS DISTINCT FROM COALESCE(NULLIF(p_brokeneggdisposition, ''), pr.brokeneggdisposition));
    PERFORM sppoultrybyproduct_syncforproduction(p_farmid, p_recordid, FALSE, p_by);
END
$function$;

-- ------------------------------------------------------- 4. backfill -------
DO $$
DECLARE
    v_r record;
    v_n integer := 0;
BEGIN
    FOR v_r IN
        SELECT pr.farmid, pr.id
        FROM   productionrecords pr
        JOIN   poultrybyproductsettings s ON s.farmid = pr.farmid
        WHERE  pr.createdat < s.cutoverat
          AND  (COALESCE(pr.brokeneggs, 0) > 0 OR COALESCE(pr.mortality, 0) > 0)
          AND  EXISTS (SELECT 1 FROM poultryproducts p WHERE p.farmid = pr.farmid AND p.systemrole IS NOT NULL)
        ORDER  BY pr.farmid, pr.date, pr.id
    LOOP
        PERFORM sppoultrybyproduct_syncforproduction(v_r.farmid, v_r.id, FALSE, 'migration381');
        v_n := v_n + 1;
    END LOOP;

    -- Listed with their records, not at the top of Stock movements today.
    UPDATE poultrystocktransactions t
    SET    createddate = pr.createdat
    FROM   productionrecords pr, poultryproducts p
    WHERE  p.poultryproductid = t.poultryproductid AND p.systemrole IS NOT NULL
      AND  pr.id = t.relatedid AND pr.farmid = t.farmid
      AND  t.createdby = 'migration381'
      AND  t.txntype IN ('Broken Egg Prod', 'Broken Egg Disposal', 'Mortality In', 'Mortality Disposal');

    RAISE NOTICE '381: % production record(s) from before tracking posted as history (generated and disposed)', v_n;
END
$$;

COMMIT;

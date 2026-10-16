-- =============================================================================
-- byproduct-history.test.sql -- checks for migration 381.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f).
-- Records entered before byproduct tracking count as generated AND disposed:
-- reports see them, stock on hand does not move.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_bad  integer;
    v_r    record;
    v_b0   numeric;
    v_d0   numeric;
    v_failed boolean;
BEGIN
    -- 1. Every pre-cutover record with broken eggs / mortality is posted as
    --    history: generation = the record's figures, disposal = the same, negated.
    SELECT count(*) INTO v_bad
    FROM   productionrecords pr
    JOIN   poultrybyproductsettings s ON s.farmid = pr.farmid
    WHERE  pr.createdat < s.cutoverat
      AND  (COALESCE(pr.brokeneggs, 0) > 0 OR COALESCE(pr.mortality, 0) > 0)
      AND  EXISTS (SELECT 1 FROM poultryproducts p WHERE p.farmid = pr.farmid AND p.systemrole IS NOT NULL)
      AND  (
             COALESCE((SELECT sum(t.quantity) FROM poultrystocktransactions t WHERE t.farmid = pr.farmid AND t.relatedid = pr.id AND t.txntype = 'Broken Egg Prod'), 0)     <> COALESCE(pr.brokeneggs, 0)
          OR COALESCE((SELECT sum(t.quantity) FROM poultrystocktransactions t WHERE t.farmid = pr.farmid AND t.relatedid = pr.id AND t.txntype = 'Broken Egg Disposal'), 0) <> -COALESCE(pr.brokeneggs, 0)
          OR COALESCE((SELECT sum(t.quantity) FROM poultrystocktransactions t WHERE t.farmid = pr.farmid AND t.relatedid = pr.id AND t.txntype = 'Mortality In'), 0)        <> COALESCE(pr.mortality, 0)
          OR COALESCE((SELECT sum(t.quantity) FROM poultrystocktransactions t WHERE t.farmid = pr.farmid AND t.relatedid = pr.id AND t.txntype = 'Mortality Disposal'), 0)  <> -COALESCE(pr.mortality, 0));
    IF v_bad > 0 THEN RAISE EXCEPTION 'FAIL 1: % pre-tracking record(s) not posted as generated + disposed', v_bad; END IF;
    RAISE NOTICE 'ok 1 every pre-tracking record: generated and disposed in full';

    -- 2. History nets to zero: it adds nothing to stock on hand.
    SELECT count(*) INTO v_bad FROM (
        SELECT t.farmid, sum(t.quantity) AS net
        FROM   poultrystocktransactions t
        JOIN   productionrecords pr ON pr.id = t.relatedid AND pr.farmid = t.farmid
        JOIN   poultrybyproductsettings s ON s.farmid = pr.farmid
        WHERE  pr.createdat < s.cutoverat
          AND  t.txntype IN ('Broken Egg Prod', 'Broken Egg Disposal', 'Mortality In', 'Mortality Disposal')
        GROUP  BY t.farmid) x
    WHERE  x.net <> 0;
    IF v_bad > 0 THEN RAISE EXCEPTION 'FAIL 2: history moved stock on hand for % compan(ies)', v_bad; END IF;
    RAISE NOTICE 'ok 2 history nets to zero on hand';

    -- 3. The form is shown Disposed, Keep is refused, Disposed re-saves to no change.
    SELECT pr.farmid, pr.id, pr.brokeneggs, pr.mortality INTO v_r
    FROM   productionrecords pr
    JOIN   poultrybyproductsettings s ON s.farmid = pr.farmid
    WHERE  pr.createdat < s.cutoverat AND COALESCE(pr.mortality, 0) > 0
    ORDER  BY pr.id DESC LIMIT 1;
    IF v_r.id IS NULL THEN
        RAISE NOTICE 'byproduct history: all checks passed (no pre-tracking record to edit)';
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultryproduction_dispositions(v_r.farmid) d
                   WHERE d.id = v_r.id AND d.mortalitydisposition = 'Disposed') THEN
        RAISE EXCEPTION 'FAIL 3a: old record not shown as Disposed'; END IF;

    v_failed := FALSE;
    BEGIN
        PERFORM sppoultryproduction_setdisposition(v_r.farmid, v_r.id, 'Keep', NULL, 'check381');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE;
    END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3b: Keep accepted on a pre-tracking record'; END IF;

    v_b0 := fnpoultry_byproductonhand(v_r.farmid, 'BrokenEggs');
    v_d0 := fnpoultry_byproductonhand(v_r.farmid, 'DeadBirds');
    PERFORM sppoultryproduction_setdisposition(v_r.farmid, v_r.id, 'Disposed', 'Disposed', 'check381');
    -- Even with the columns left at Keep, a resync adds no stock.
    PERFORM sppoultrybyproduct_syncforproduction(v_r.farmid, v_r.id, FALSE, 'check381');
    IF fnpoultry_byproductonhand(v_r.farmid, 'BrokenEggs') <> v_b0 OR fnpoultry_byproductonhand(v_r.farmid, 'DeadBirds') <> v_d0 THEN
        RAISE EXCEPTION 'FAIL 3c: re-saving an old record moved stock'; END IF;

    -- Removing it (as a delete does) takes generation and disposal off together.
    PERFORM sppoultrybyproduct_syncforproduction(v_r.farmid, v_r.id, TRUE, 'check381');
    IF fnpoultry_byproductonhand(v_r.farmid, 'DeadBirds') <> v_d0 THEN
        RAISE EXCEPTION 'FAIL 3d: removing an old record moved Dead Birds'; END IF;
    RAISE NOTICE 'ok 3 old record: shown Disposed, Keep refused, edits and removal leave stock alone';

    RAISE NOTICE 'byproduct history: all checks passed';
END $$;

ROLLBACK;

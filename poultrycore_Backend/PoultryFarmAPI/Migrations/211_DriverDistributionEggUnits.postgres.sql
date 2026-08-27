-- =============================================================================
-- 211_DriverDistributionEggUnits.postgres.sql
--
-- Problem
-- -------
-- Two independent defects in the poultry driver-distribution flow, both visible
-- as egg counts that move by the wrong amount after /poultry-driver-returns.
--
-- 1. CRATES WRITTEN INTO AN EGG-PIECE LEDGER.
--    Since migration 206 the egg product's unit is 'Egg' and every egg quantity
--    in the system is a piece count -- production records, sales, and the
--    poultrystocktransactions ledger that migration 204 made the single source
--    of truth. The driver-distribution functions never got that memo and post
--    raw CRATE counts:
--
--      sppoultryvehicleloading_approve  'Driver Load Out',  -li.cratesloaded
--      sppoultrydriverreturn_approve    'Driver Return In',  ri.cratesreturned
--      sppoultrydriverreturn_approve    poultryproductionloss.quantitylost
--      sppoultrydriverreturn_approve    sale.quantity
--
--    Each loading carries an eggspercrate (always 30) that was stored and never
--    used to convert. So a 29-crate loading removed 29 eggs from stock instead
--    of 870 -- a 30x understatement -- and the pre-flight "insufficient stock"
--    check compared eggs-on-hand against a crate count, so it could not catch
--    an over-load either.
--
-- 2. THE GENERATED SALE WAS DEDUCTED A SECOND TIME.
--    The intended model is sound: the load-out takes the eggs off the farm, the
--    return puts the UNSOLD ones back, and the sold portion simply stays out.
--    The sale row that sppoultrydriverreturn_approve writes exists to book the
--    revenue, not to move stock.
--
--    But /egg-tracker derived its outflow from the sale table AND from the
--    non-production/non-sale ledger moves, so it deducted the sold eggs twice --
--    once as 'Driver Load Out', again as the sale. The Egg Stock Balance report
--    (migration 205) had the identical defect. That is why the tracker read
--    lower than /poultry-inventory by exactly the sold quantity on every
--    reconciled delivery.
--
--    Migration 204's backfill also wrote a ledger 'Sale' row for every egg sale
--    with no exclusion for driver-generated ones, so returns approved before 204
--    are double-deducted in /poultry-inventory too.
--
-- Measured on the live database before this migration:
--   farm 3c4ac3cd : inventory 3,851  tracker 3,822  -- true figure 3,010
--   farm 224f8096 : inventory 32,338                -- true figure 31,236
--
-- Fix
-- ---
--   0. fnpoultrycrateunits(productid, eggspercrate) -- the crate->stock-unit
--      multiplier. Returns eggspercrate ONLY for a raw-egg product, else 1, so
--      loading birds or any other crate-priced finished good is untouched.
--   1. Patch the three write-path functions to convert.
--   2. Guard sppoultryeggstock_syncforsale so editing a driver-generated sale
--      from /sales cannot re-introduce the duplicate ledger row.
--   3. Rebuild sppoultryreport_eggstockbalance to exclude driver/delivery sales.
--   4. Backfill the rows already written wrong.
--
-- The frontend half is lib/utils/egg-ledger.ts (isStockLedgerBackedSale).
--
-- The write-path patches are applied as targeted text replacements on the live
-- function bodies -- the same technique migration 206 used -- so every line the
-- fix does not touch stays byte-identical to whichever migration last defined
-- it. Each replacement asserts its anchor was found, so a drifted body aborts
-- the migration rather than silently skipping the fix.
--
-- Idempotent throughout: the patches are anchored on the pre-fix text and skip
-- if already applied, and every backfill sets a target value computed from the
-- source tables rather than multiplying what is already there.
-- =============================================================================

\set ON_ERROR_STOP on

-- -----------------------------------------------------------------------------
-- 0. The crate -> stock-unit multiplier.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrycrateunits(p_poultryproductid integer, p_eggspercrate integer)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    -- Eggs are the only product whose ledger unit differs from the crate the
    -- driver module counts in. Birds and other finished goods are stocked in
    -- whatever unit they are loaded in, so they convert 1:1.
    SELECT CASE
             WHEN EXISTS (SELECT 1 FROM poultryproducts p
                          WHERE p.poultryproductid = p_poultryproductid
                            AND COALESCE(p.israweggproduct, FALSE) = TRUE)
             THEN GREATEST(COALESCE(p_eggspercrate, 30), 1)
             ELSE 1
           END;
$$;

-- -----------------------------------------------------------------------------
-- 1. Patch the write-path functions.
-- -----------------------------------------------------------------------------
DO $patch$
DECLARE
    v_def     text;
    v_new     text;
    v_applied int := 0;
    v_skipped int := 0;

    -- (anchor, replacement) pairs, grouped by function.
    v_edits text[][] := ARRAY[
        -- ---- sppoultryvehicleloading_approve -------------------------------
        -- Pre-flight: compare like for like, and report the shortfall in the
        -- ledger's own unit rather than in crates.
        ['sppoultryvehicleloading_approve',
         E'    SELECT p.name::text, COALESCE(s.onhand, 0), li.cratesloaded\n    INTO   v_shortname, v_shorthave, v_shortneed',
         E'    SELECT p.name::text, COALESCE(s.onhand, 0),\n           li.cratesloaded * fnpoultrycrateunits(li.poultryproductid, li.eggspercrate)\n    INTO   v_shortname, v_shorthave, v_shortneed'],

        ['sppoultryvehicleloading_approve',
         E'    WHERE  li.poultryvehicleloadingid = p_poultryvehicleloadingid AND COALESCE(s.onhand, 0) < li.cratesloaded\n    LIMIT 1;',
         E'    WHERE  li.poultryvehicleloadingid = p_poultryvehicleloadingid\n      AND  COALESCE(s.onhand, 0) < li.cratesloaded * fnpoultrycrateunits(li.poultryproductid, li.eggspercrate)\n    LIMIT 1;'],

        -- The load-out itself.
        ['sppoultryvehicleloading_approve',
         E'    SELECT p_farmid, li.poultryproductid, \'Driver Load Out\', -li.cratesloaded, li.unitprice, p_poultryvehicleloadingid,',
         E'    SELECT p_farmid, li.poultryproductid, \'Driver Load Out\',\n           -li.cratesloaded * fnpoultrycrateunits(li.poultryproductid, li.eggspercrate),\n           li.unitprice, p_poultryvehicleloadingid,'],

        -- ---- sppoultrydriverreturn_approve --------------------------------
        -- Carry the loading's eggspercrate so every conversion below can use it.
        ['sppoultrydriverreturn_approve',
         E'    v_lostcrates integer;',
         E'    v_lostcrates integer;\n    v_eggspercrate integer;'],

        ['sppoultrydriverreturn_approve',
         E'    SELECT vl.poultryproductid, vl.expectedsellingpricepercrate, vl.poultrydriverid\n      INTO v_productid, v_pricepercrate, v_driverid',
         E'    SELECT vl.poultryproductid, vl.expectedsellingpricepercrate, vl.poultrydriverid, vl.eggspercrate\n      INTO v_productid, v_pricepercrate, v_driverid, v_eggspercrate'],

        -- (a) Returned crates back into stock, per item and in the aggregate.
        ['sppoultrydriverreturn_approve',
         E'        SELECT p_farmid, ri.poultryproductid, \'Driver Return In\', ri.cratesreturned, ri.unitprice, p_poultrydriverreturnid,',
         E'        SELECT p_farmid, ri.poultryproductid, \'Driver Return In\',\n               ri.cratesreturned * fnpoultrycrateunits(ri.poultryproductid, v_eggspercrate),\n               ri.unitprice, p_poultrydriverreturnid,'],

        ['sppoultrydriverreturn_approve',
         E'        VALUES (p_farmid, v_productid, \'Driver Return In\', v_cratesreturned, v_pricepercrate, p_poultrydriverreturnid,',
         E'        VALUES (p_farmid, v_productid, \'Driver Return In\',\n                v_cratesreturned * fnpoultrycrateunits(v_productid, v_eggspercrate),\n                v_pricepercrate, p_poultrydriverreturnid,'],

        -- (b) Damaged + missing crates -> production loss.
        ['sppoultrydriverreturn_approve',
         E'                v_lostcrates, (v_lostcrates * v_pricepercrate)::numeric(14,2), \'Driver return damaged/missing crates\');',
         E'                v_lostcrates * fnpoultrycrateunits(v_productid, v_eggspercrate),\n                (v_lostcrates * v_pricepercrate)::numeric(14,2), \'Driver return damaged/missing crates\');'],

        -- (c) The generated sale. Egg sales store quantity in EGGS and unitprice
        --     PER CRATE -- the convention the /sales form already writes (see
        --     app/sales/page.tsx: quantity = crates*30, amount = crates*price).
        --     So only the quantity is scaled; v_up and the total stay as they
        --     were and the cash figure is unchanged.
        ['sppoultrydriverreturn_approve',
         E'        VALUES (v_user, v_dated, \'Eggs\', v_qty, v_up, v_cs.tot::numeric(18,2), v_method,',
         E'        VALUES (v_user, v_dated, \'Eggs\', v_qty * fnpoultrycrateunits(v_productid, v_eggspercrate), v_up, v_cs.tot::numeric(18,2), v_method,'],

        -- ---- sppoultryeggstock_syncforsale --------------------------------
        -- A driver/delivery sale is already covered by its load-out and
        -- return-in moves. Without this guard, opening that sale in /sales and
        -- saving it would call this function and re-create the duplicate row
        -- that section 4 deletes below.
        ['sppoultryeggstock_syncforsale',
         E'    IF (COALESCE(p_qtysold, 0) <= 0) THEN RETURN; END IF;',
         E'    IF (COALESCE(p_qtysold, 0) <= 0) THEN RETURN; END IF;\n\n    -- Sales generated by a driver return / delivery move no stock of their own:\n    -- the eggs left as \'Driver Load Out\' and came back as \'Driver Return In\'.\n    IF EXISTS (SELECT 1 FROM sale s\n               WHERE s.saleid = p_saleid AND s.farmid = p_farmid\n                 AND (s.saledescription ILIKE \'Driver return #%\' OR s.saledescription ILIKE \'Delivery #%\')) THEN\n        RETURN;\n    END IF;']
    ];
    i int;
BEGIN
    FOR i IN 1 .. array_length(v_edits, 1) LOOP
        SELECT m.definition INTO v_def
        FROM   pg_proc p
        JOIN   pg_namespace n ON n.oid = p.pronamespace
        JOIN   LATERAL (SELECT pg_get_functiondef(p.oid) AS definition) m ON TRUE
        WHERE  n.nspname = 'public' AND p.proname = v_edits[i][1]
        LIMIT  1;

        IF v_def IS NULL THEN
            RAISE EXCEPTION '211: function %() not found.', v_edits[i][1];
        END IF;

        IF position(v_edits[i][3] IN v_def) > 0 THEN
            -- Replacement already present: this edit has been applied before.
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        IF position(v_edits[i][2] IN v_def) = 0 THEN
            RAISE EXCEPTION '211: anchor % not found in %() and its replacement is absent -- the function body has drifted, refusing to guess.',
                            left(v_edits[i][2], 60), v_edits[i][1];
        END IF;

        v_new := replace(v_def, v_edits[i][2], v_edits[i][3]);
        EXECUTE v_new;
        v_applied := v_applied + 1;
    END LOOP;

    RAISE NOTICE '211: % write-path edit(s) applied, % already present.', v_applied, v_skipped;
END
$patch$;

-- -----------------------------------------------------------------------------
-- 2. Egg Stock Balance report: stop counting driver/delivery sales.
--
-- Those eggs are already netted out by the openingstockmoves / stockmovesinrange
-- columns (the 'Driver Load Out' and 'Driver Return In' rows). Counting the
-- generated sale as well deducted the sold portion twice. Only the two sale
-- subqueries change; everything else is migration 205 verbatim.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryreport_eggstockbalance(p_farmid text, p_startdate date, p_enddate date)
 RETURNS TABLE(openingproducedsaleable bigint, openingadjustments bigint, openingsales bigint, productionadded bigint, brokeninrange bigint, adjustmentsinrange bigint, salesinrange bigint, openingstockmoves bigint, stockmovesinrange bigint)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        -- Opening saleable eggs produced before the range
        COALESCE((SELECT SUM(r.totalproduction::bigint
                             - (COALESCE(r.brokeneggs,0)+COALESCE(r.meatyeggs,0)+COALESCE(r.softeggs,0)+COALESCE(r.losteggs,0))::bigint)
                  FROM productionrecords r
                  WHERE r.farmid = p_farmid AND r.date < p_startdate), 0)::bigint            AS openingproducedsaleable,
        COALESCE((SELECT SUM(a.eggdelta) FROM egginventoryadjustment a
                  WHERE a.farmid = p_farmid AND a.adjustmentdate < p_startdate), 0)::bigint  AS openingadjustments,
        -- Eggs sold before the range (reduces opening on-hand). Sales generated
        -- by a driver return / delivery are excluded: those eggs are already
        -- netted out by the stock-move columns below, and counting them here as
        -- well deducted the sold portion twice.
        COALESCE((SELECT SUM(trunc(s.quantity)::bigint) FROM sale s
                  WHERE s.farmid = p_farmid AND s.product ILIKE '%egg%' AND s.saledate < p_startdate
                    AND NOT (COALESCE(s.saledescription,'') ILIKE 'Driver return #%'
                          OR COALESCE(s.saledescription,'') ILIKE 'Delivery #%')), 0)::bigint AS openingsales,
        COALESCE((SELECT SUM(r.totalproduction::bigint) FROM productionrecords r
                  WHERE r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate), 0)::bigint AS productionadded,
        COALESCE((SELECT SUM((COALESCE(r.brokeneggs,0)+COALESCE(r.meatyeggs,0)+COALESCE(r.softeggs,0)+COALESCE(r.losteggs,0))::bigint)
                  FROM productionrecords r
                  WHERE r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate), 0)::bigint AS brokeninrange,
        COALESCE((SELECT SUM(a.eggdelta) FROM egginventoryadjustment a
                  WHERE a.farmid = p_farmid AND a.adjustmentdate >= p_startdate AND a.adjustmentdate < (p_enddate + 1)), 0)::bigint AS adjustmentsinrange,
        -- Eggs sold within the range (reduces current on-hand), same exclusion.
        COALESCE((SELECT SUM(trunc(s.quantity)::bigint) FROM sale s
                  WHERE s.farmid = p_farmid AND s.product ILIKE '%egg%'
                    AND s.saledate >= p_startdate AND s.saledate < (p_enddate + 1)
                    AND NOT (COALESCE(s.saledescription,'') ILIKE 'Driver return #%'
                          OR COALESCE(s.saledescription,'') ILIKE 'Delivery #%')), 0)::bigint AS salesinrange,
        -- Stock-ledger moves on the egg product that are neither production nor a
        -- sale: driver load-outs, deliveries, restocks and the Set stock /
        -- Reconcile corrections made from /poultry-inventory. Migration 204 made
        -- the ledger the single source of truth for egg stock; this report was the
        -- last figure still blind to these rows, which is why it disagreed with
        -- both /poultry-inventory and /egg-tracker. Production and Sale rows are
        -- excluded because they are already counted from the source tables above.
        COALESCE((SELECT SUM(trunc(t.quantity)::bigint)
                  FROM poultrystocktransactions t
                  JOIN poultryproducts p ON p.poultryproductid = t.poultryproductid
                  WHERE t.farmid = p_farmid
                    AND (COALESCE(p.israweggproduct,FALSE) = TRUE OR p.name IN ('Eggs','Chicken Eggs'))
                    AND t.txntype NOT IN ('Production','Sale')
                    AND t.createddate < p_startdate), 0)::bigint AS openingstockmoves,
        COALESCE((SELECT SUM(trunc(t.quantity)::bigint)
                  FROM poultrystocktransactions t
                  JOIN poultryproducts p ON p.poultryproductid = t.poultryproductid
                  WHERE t.farmid = p_farmid
                    AND (COALESCE(p.israweggproduct,FALSE) = TRUE OR p.name IN ('Eggs','Chicken Eggs'))
                    AND t.txntype NOT IN ('Production','Sale')
                    AND t.createddate >= p_startdate AND t.createddate < (p_enddate + 1)), 0)::bigint AS stockmovesinrange;
END
$function$;

-- -----------------------------------------------------------------------------
-- 3. Backfill the rows already written in crates.
--
-- Every UPDATE sets a TARGET computed from the source tables, so re-running
-- converges instead of multiplying by 30 again.
--
-- The multiplier is taken from the LEDGER row's product, not the loading item's:
-- migration 204 merged duplicate raw-egg products and repointed the ledger, so
-- for loading #30 the item still names the retired product 22 while the ledger
-- row correctly names the canonical product 10.
--
-- Both UPDATEs are restricted to loadings/returns that resolve to exactly one
-- ledger row and one product; section 4 reports anything left unconverted
-- rather than letting it pass silently.
-- -----------------------------------------------------------------------------

-- 3a. Drop the duplicate ledger 'Sale' rows for driver/delivery-generated sales.
--     Migration 204's backfill created these with no exclusion; the fixed model
--     covers those eggs with the load-out / return-in pair instead.
--
--     This runs FIRST: 3b below deletes some of those sale rows outright, and
--     sppoultrydriverreturn_reverse removes a sale without calling
--     sppoultryeggstock_syncforsale, which would strand the ledger row here as
--     an orphan pointing at a sale id that no longer exists.
DELETE FROM poultrystocktransactions t
USING  sale s
WHERE  t.txntype   = 'Sale'
  AND  t.relatedid = s.saleid
  AND  t.farmid    = s.farmid
  AND  (COALESCE(s.saledescription,'') ILIKE 'Driver return #%'
     OR COALESCE(s.saledescription,'') ILIKE 'Delivery #%');

-- 3b. Void farm b55bf33e's loading #30 / driver return #2.
--
--     That loading booked 2,000 crates -- 60,000 eggs -- in a single day
--     against a farm whose entire lifetime saleable production is 33,812 eggs,
--     with GHS 90,000 recorded as collected. It is not a real delivery, and
--     converting its units honestly would take the farm to -11,089 eggs on
--     hand. Unwound through the module's own reversal path so the sale, the
--     cash adjustment and the stock row all go together.
--
--     Narrowly guarded: only this one loading, only while it still matches the
--     shape described above, so a re-run after the void is a no-op and no other
--     farm's data can be caught by it.
DO $void$
DECLARE
    v_farm text := 'b55bf33e-a5ba-4d9b-a287-1dea39a84f13';
    v_lid  integer := 30;
    v_rid  integer;
BEGIN
    SELECT r.poultrydriverreturnid INTO v_rid
    FROM   poultrydriverreturns r
    JOIN   poultryvehicleloadings l ON l.poultryvehicleloadingid = r.poultryvehicleloadingid
    WHERE  r.farmid = v_farm
      AND  r.poultryvehicleloadingid = v_lid
      AND  r.status = 'Approved'
      AND  l.cratesloaded = 2000
    LIMIT  1;

    IF v_rid IS NULL THEN
        RAISE NOTICE '211: loading #% on farm % already voided (or no longer matches) -- skipping.', v_lid, left(v_farm, 8);
        RETURN;
    END IF;

    PERFORM sppoultrydriverreturn_reverse(v_rid, v_farm);
    PERFORM sppoultrydriverreturn_delete(v_rid, v_farm);
    PERFORM sppoultryvehicleloading_cancel(v_lid, v_farm);

    RAISE NOTICE '211: voided loading #% and driver return #% on farm % (2,000-crate bad record).',
                 v_lid, v_rid, left(v_farm, 8);
END
$void$;

-- 3c. 'Driver Load Out'
UPDATE poultrystocktransactions t
SET    quantity = -(agg.total_crates * fnpoultrycrateunits(t.poultryproductid, agg.eggspercrate))
FROM (
    SELECT l.poultryvehicleloadingid       AS lid,
           l.farmid                        AS farmid,
           l.eggspercrate                  AS eggspercrate,
           SUM(li.cratesloaded)            AS total_crates,
           COUNT(DISTINCT li.poultryproductid) AS nprod
    FROM   poultryvehicleloadings l
    JOIN   poultryvehicleloadingitems li ON li.poultryvehicleloadingid = l.poultryvehicleloadingid
    GROUP  BY l.poultryvehicleloadingid, l.farmid, l.eggspercrate
) agg
WHERE  t.txntype  = 'Driver Load Out'
  AND  t.relatedid = agg.lid
  AND  t.farmid    = agg.farmid
  AND  agg.nprod   = 1
  AND  1 = (SELECT COUNT(*) FROM poultrystocktransactions t2
            WHERE t2.txntype = 'Driver Load Out' AND t2.relatedid = t.relatedid AND t2.farmid = t.farmid)
  AND  t.quantity <> -(agg.total_crates * fnpoultrycrateunits(t.poultryproductid, agg.eggspercrate));

-- 3d. 'Driver Return In'
UPDATE poultrystocktransactions t
SET    quantity = agg.total_crates * fnpoultrycrateunits(t.poultryproductid, agg.eggspercrate)
FROM (
    SELECT r.poultrydriverreturnid          AS rid,
           r.farmid                         AS farmid,
           l.eggspercrate                   AS eggspercrate,
           SUM(ri.cratesreturned)           AS total_crates,
           COUNT(DISTINCT ri.poultryproductid) AS nprod
    FROM   poultrydriverreturns r
    JOIN   poultryvehicleloadings l ON l.poultryvehicleloadingid = r.poultryvehicleloadingid
    JOIN   poultrydriverreturnitems ri ON ri.poultrydriverreturnid = r.poultrydriverreturnid
    GROUP  BY r.poultrydriverreturnid, r.farmid, l.eggspercrate
) agg
WHERE  t.txntype  = 'Driver Return In'
  AND  t.relatedid = agg.rid
  AND  t.farmid    = agg.farmid
  AND  agg.nprod   = 1
  AND  1 = (SELECT COUNT(*) FROM poultrystocktransactions t2
            WHERE t2.txntype = 'Driver Return In' AND t2.relatedid = t.relatedid AND t2.farmid = t.farmid)
  AND  t.quantity <> agg.total_crates * fnpoultrycrateunits(t.poultryproductid, agg.eggspercrate);

-- 3e. poultryproductionloss.quantitylost for damaged/missing crates.
UPDATE poultryproductionloss pl
SET    quantitylost = src.lostcrates * fnpoultrycrateunits(src.ledgerproductid, src.eggspercrate)
FROM (
    SELECT r.poultrydriverreturnid AS rid,
           r.farmid                AS farmid,
           l.eggspercrate          AS eggspercrate,
           COALESCE(r.cratesdamaged,0) + COALESCE(r.missingcrates,0) AS lostcrates,
           COALESCE((SELECT t.poultryproductid FROM poultrystocktransactions t
                     WHERE t.txntype = 'Driver Load Out' AND t.relatedid = l.poultryvehicleloadingid
                       AND t.farmid = l.farmid LIMIT 1), l.poultryproductid) AS ledgerproductid
    FROM   poultrydriverreturns r
    JOIN   poultryvehicleloadings l ON l.poultryvehicleloadingid = r.poultryvehicleloadingid
) src
WHERE  pl.sourcetype = 'PoultryDriverReturn'
  AND  pl.sourceid   = src.rid
  AND  pl.farmid     = src.farmid
  AND  src.lostcrates > 0
  AND  pl.quantitylost <> src.lostcrates * fnpoultrycrateunits(src.ledgerproductid, src.eggspercrate);

-- 3f. The generated sale rows: quantity in eggs, unitprice left per crate.
--     Crates are re-derived exactly the way sppoultrydriverreturn_approve
--     derives them, so this converges on the same number the fixed function
--     would now write.
UPDATE sale s
SET    quantity = src.crates * fnpoultrycrateunits(src.ledgerproductid, src.eggspercrate)
FROM (
    SELECT cs.generatedsaleid AS saleid,
           r.farmid           AS farmid,
           l.eggspercrate     AS eggspercrate,
           CASE WHEN COALESCE(items.q, 0) > 0                    THEN items.q
                WHEN COALESCE(l.expectedsellingpricepercrate,0) > 0
                     THEN round(cs.totalamount / l.expectedsellingpricepercrate)
                ELSE r.cratessold
           END AS crates,
           COALESCE((SELECT t.poultryproductid FROM poultrystocktransactions t
                     WHERE t.txntype = 'Driver Load Out' AND t.relatedid = l.poultryvehicleloadingid
                       AND t.farmid = l.farmid LIMIT 1), l.poultryproductid) AS ledgerproductid
    FROM   poultrydriverreturncustomersales cs
    JOIN   poultrydriverreturns r ON r.poultrydriverreturnid = cs.poultrydriverreturnid
    JOIN   poultryvehicleloadings l ON l.poultryvehicleloadingid = r.poultryvehicleloadingid
    LEFT   JOIN LATERAL (SELECT SUM(csi.quantity) AS q
                         FROM poultrydriverreturncustomersaleitems csi
                         WHERE csi.poultrydriverreturncustomersaleid = cs.poultrydriverreturncustomersaleid) items ON TRUE
    WHERE  cs.generatedsaleid IS NOT NULL
) src
WHERE  s.saleid = src.saleid
  AND  s.farmid = src.farmid
  AND  s.quantity <> src.crates * fnpoultrycrateunits(src.ledgerproductid, src.eggspercrate);

-- -----------------------------------------------------------------------------
-- 4. Report anything the backfill could not convert, rather than passing
--    silently. A multi-product loading, or a loading whose ledger rows were
--    split, needs a hand correction.
-- -----------------------------------------------------------------------------
DO $verify$
DECLARE
    r record;
    n int := 0;
BEGIN
    FOR r IN
        SELECT t.poultrystocktransactionid, t.farmid, t.txntype, t.quantity, t.relatedid, t.note
        FROM   poultrystocktransactions t
        WHERE  t.txntype IN ('Driver Load Out', 'Driver Return In')
          AND  EXISTS (SELECT 1 FROM poultryproducts p
                       WHERE p.poultryproductid = t.poultryproductid
                         AND COALESCE(p.israweggproduct, FALSE) = TRUE)
          AND  abs(t.quantity) > 0
          AND  abs(t.quantity) < 30      -- still plausibly a crate count
        ORDER  BY t.poultrystocktransactionid
    LOOP
        RAISE WARNING '211: ledger row % (% %, related #%) still looks like a crate count -- convert by hand.',
                      r.poultrystocktransactionid, r.txntype, r.quantity, r.relatedid;
        n := n + 1;
    END LOOP;

    IF n = 0 THEN
        RAISE NOTICE '211: no unconverted driver ledger rows remain.';
    END IF;
END
$verify$;

DO $grant$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'Techretainer') THEN
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.fnpoultrycrateunits(integer, integer) TO "Techretainer"';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.sppoultryreport_eggstockbalance(text, date, date) TO "Techretainer"';
    END IF;
END
$grant$;

-- 211_DriverDistributionEggUnits.postgres.sql complete.

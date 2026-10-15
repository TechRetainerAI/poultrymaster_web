-- =============================================================================
-- 375_PoultryByproductReports.postgres.sql                   (requires 372-374)
--
-- Purpose (Phase 4 of the poultry inventory traceability programme)
-- -------
-- 1. ONE classified ledger of Broken Eggs / Dead Birds movements
--    (fnpoultry_byproductledger) and the report built on it
--    (sppoultryreport_byproducts): per byproduct and flock --
--        Opening + Generated + Manual in - Sold - Disposed - Internal use
--        - Manual out +/- Reversals = Closing,   plus sales revenue.
--    Rows a flock cannot be traced for (egg sorting breakage, unattributed
--    manual entries) stay POOLED (flock NULL) -- never guessed onto a flock.
--
-- 2. Reports that sorted sales by the word "egg" stop counting Broken Eggs as
--    egg sales, and Dead Birds stop counting as live bird revenue:
--       fnpoultrysale_revenueline   new line 'ByproductSales' (P&L shows it as
--                                   its own revenue line)
--       sppoultryreport_plsummary   folds it into "other revenue" so the summary
--                                   columns still add up to total revenue
--       sppoultryreport_profitlossbyflock, fnflock_lifetimesummary,
--       sppoultryreport_eggstockbalance   egg figures exclude Broken Eggs
--
-- Production history is never rewritten by a sale or disposal: generation is
-- what production made; what happened afterwards is in its own columns.
-- Read-only: no stock, sale or money row is written.
-- =============================================================================
BEGIN;

CREATE FUNCTION pg_temp.m375_patch(p_fn text, p_marker text, p_old text, p_new text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
    v_oid oid;
    v_n   integer;
    v_def text;
    v_old text := replace(p_old, chr(13), '');
    v_new text := replace(p_new, chr(13), '');
BEGIN
    SELECT count(*), min(p.oid) INTO v_n, v_oid
    FROM   pg_proc p WHERE p.proname = p_fn AND p.pronamespace = 'public'::regnamespace;
    IF v_n <> 1 THEN
        RAISE EXCEPTION '375: expected exactly one %, found %', p_fn, v_n;
    END IF;
    v_def := replace(pg_get_functiondef(v_oid), chr(13), '');
    IF position(replace(p_marker, chr(13), '') IN v_def) > 0 THEN
        RAISE NOTICE '375: % already patched (%), skipped', p_fn, p_marker;
        RETURN;
    END IF;
    v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / greatest(length(v_old), 1);
    IF v_n <> 1 THEN
        RAISE EXCEPTION '375: anchor for % (%) found % times, expected %', p_fn, p_marker, v_n, 1;
    END IF;
    EXECUTE replace(v_def, v_old, v_new);
    RAISE NOTICE '375: patched % (%)', p_fn, p_marker;
END
$f$;

-- ------------------------------------------- 1. the classified ledger --
CREATE OR REPLACE FUNCTION public.fnpoultry_byproductledger(p_farmid text)
RETURNS TABLE(txnid integer, role text, productname text, bdate date, txntype text, category text,
              quantity numeric, flockid integer, batchid integer, saleid integer, revenue numeric,
              manualmovementid integer, note text)
LANGUAGE sql STABLE AS $f$
    SELECT t.poultrystocktransactionid,
           p.systemrole,
           p.name::text,
           COALESCE(t.effectivedate, t.createddate::date),
           t.txntype::text,
           CASE
               WHEN t.manualreversal OR t.txntype = 'Sale Reversal'                      THEN 'Reversal'
               WHEN t.txntype IN ('Broken Egg Prod', 'Sorting Breakage', 'Mortality In',
                                  'Hist Mortality In', 'Breakage In')                     THEN 'Generated'
               WHEN t.txntype IN ('Broken Egg Disposal', 'Mortality Disposal',
                                  'Hist Mortality Disp', 'Disposal')                      THEN 'Disposed'
               WHEN t.txntype = 'Sale'                                                    THEN 'Sold'
               WHEN t.txntype = 'InternalUse'                                             THEN 'InternalUse'
               WHEN t.quantity >= 0                                                       THEN 'ManualIn'
               ELSE 'ManualOut'
           END,
           t.quantity,
           -- The flock: stamped on the row (manual movements, sales), or the
           -- production record a production row came from. Sorting is pooled.
           COALESCE(t.flockid, pr.flockid),
           COALESCE(t.batchid, f.batchid),
           CASE WHEN t.txntype IN ('Sale', 'Sale Reversal') THEN t.relatedid END,
           CASE WHEN t.txntype = 'Sale'          THEN  COALESCE(l.totalamount, 0)
                WHEN t.txntype = 'Sale Reversal' THEN -COALESCE(l.totalamount, 0)
                ELSE 0 END,
           t.manualmovementid,
           t.note::text
    FROM   poultrystocktransactions t
    JOIN   poultryproducts p ON p.poultryproductid = t.poultryproductid AND p.farmid = t.farmid
    LEFT   JOIN productionrecords pr
           ON pr.id = t.relatedid AND pr.farmid = t.farmid AND t.flockid IS NULL
          AND t.txntype IN ('Broken Egg Prod', 'Broken Egg Disposal', 'Mortality In', 'Mortality Disposal')
    LEFT   JOIN flock f ON f.flockid = COALESCE(t.flockid, pr.flockid)
    LEFT   JOIN saleline l ON l.salelineid = t.salelineid AND t.txntype IN ('Sale', 'Sale Reversal')
    WHERE  t.farmid = p_farmid AND p.systemrole IS NOT NULL;
$f$;

-- ------------------------------------------------------- 2. the report --
-- One row per byproduct and flock (flock NULL = pooled). p_flockid narrows to
-- one flock (its pooled stock is not that flock's); p_role to one byproduct;
-- p_byflock FALSE gives one row per byproduct.
CREATE OR REPLACE FUNCTION public.sppoultryreport_byproducts(
    p_farmid text, p_startdate date, p_enddate date,
    p_flockid integer DEFAULT NULL, p_role text DEFAULT NULL, p_byflock boolean DEFAULT TRUE)
RETURNS TABLE(role text, productname text, flockid integer, flockname text, batchid integer, batchcode text,
              opening numeric, generated numeric, sold numeric, disposed numeric, internaluse numeric,
              manualin numeric, manualout numeric, reversals numeric, closing numeric, revenue numeric,
              unitsoldprice numeric)
LANGUAGE sql STABLE AS $f$
    WITH l AS (
        SELECT x.*, CASE WHEN p_byflock THEN x.flockid END AS gflock
        FROM   fnpoultry_byproductledger(p_farmid) x
        WHERE  x.bdate <= p_enddate
          AND  (p_flockid IS NULL OR x.flockid = p_flockid)
          AND  (p_role IS NULL OR x.role = p_role)
    ),
    roles AS (   -- both byproducts always appear for the company, even at zero
        SELECT p.systemrole AS role, p.name::text AS productname
        FROM   poultryproducts p
        WHERE  p.farmid = p_farmid AND p.systemrole IS NOT NULL AND (p_role IS NULL OR p.systemrole = p_role)
    ),
    g AS (
        SELECT l.role, l.gflock,
               SUM(l.quantity) FILTER (WHERE l.bdate < p_startdate)                                   AS opening,
               SUM(l.quantity) FILTER (WHERE l.bdate >= p_startdate AND l.category = 'Generated')    AS generated,
               -SUM(l.quantity) FILTER (WHERE l.bdate >= p_startdate AND l.category = 'Sold')        AS sold,
               -SUM(l.quantity) FILTER (WHERE l.bdate >= p_startdate AND l.category = 'Disposed')    AS disposed,
               -SUM(l.quantity) FILTER (WHERE l.bdate >= p_startdate AND l.category = 'InternalUse') AS internaluse,
               SUM(l.quantity) FILTER (WHERE l.bdate >= p_startdate AND l.category = 'ManualIn')     AS manualin,
               -SUM(l.quantity) FILTER (WHERE l.bdate >= p_startdate AND l.category = 'ManualOut')   AS manualout,
               SUM(l.quantity) FILTER (WHERE l.bdate >= p_startdate AND l.category = 'Reversal')     AS reversals,
               SUM(l.quantity)                                                                        AS closing,
               SUM(l.revenue) FILTER (WHERE l.bdate >= p_startdate)                                   AS revenue
        FROM   l
        GROUP  BY l.role, l.gflock
    )
    SELECT r.role, r.productname, g.gflock, f.name::text, f.batchid, b.batchcode::text,
           COALESCE(g.opening, 0), COALESCE(g.generated, 0), COALESCE(g.sold, 0), COALESCE(g.disposed, 0),
           COALESCE(g.internaluse, 0), COALESCE(g.manualin, 0), COALESCE(g.manualout, 0), COALESCE(g.reversals, 0),
           COALESCE(g.closing, 0), COALESCE(g.revenue, 0),
           CASE WHEN COALESCE(g.sold, 0) > 0 THEN round(COALESCE(g.revenue, 0) / g.sold, 2) END
    FROM   roles r
    LEFT   JOIN g ON g.role = r.role
    LEFT   JOIN flock f ON f.flockid = g.gflock
    LEFT   JOIN mainflockbatch b ON b.batchid = f.batchid
    -- A flock filter shows only that flock's rows; without one, a byproduct
    -- with no movement at all still shows once, at zero.
    WHERE  (g.role IS NOT NULL OR p_flockid IS NULL)
    ORDER  BY r.role, f.name NULLS LAST;
$f$;

-- The movements behind the report, for drill-down / audit.
CREATE OR REPLACE FUNCTION public.sppoultryreport_byproductmovements(
    p_farmid text, p_startdate date, p_enddate date,
    p_flockid integer DEFAULT NULL, p_role text DEFAULT NULL, p_category text DEFAULT NULL)
RETURNS TABLE(txnid integer, bdate date, role text, productname text, category text, txntype text,
              quantity numeric, flockid integer, flockname text, batchcode text, saleid integer,
              revenue numeric, manualmovementid integer, movementno text, note text)
LANGUAGE sql STABLE AS $f$
    SELECT x.txnid, x.bdate, x.role, x.productname, x.category, x.txntype, x.quantity, x.flockid, f.name::text,
           b.batchcode::text, x.saleid, x.revenue, x.manualmovementid, m.movementno, x.note
    FROM   fnpoultry_byproductledger(p_farmid) x
    LEFT   JOIN flock f ON f.flockid = x.flockid
    LEFT   JOIN mainflockbatch b ON b.batchid = x.batchid
    LEFT   JOIN poultrymanualstockmovements m ON m.movementid = x.manualmovementid
    WHERE  x.bdate BETWEEN p_startdate AND p_enddate
      AND  (p_flockid IS NULL OR x.flockid = p_flockid)
      AND  (p_role IS NULL OR x.role = p_role)
      AND  (p_category IS NULL OR x.category = p_category)
    ORDER  BY x.bdate DESC, x.txnid DESC;
$f$;

-- ------------------------------------------------- 3. revenue lines --
CREATE OR REPLACE FUNCTION public.fnpoultrysale_revenueline(p_product text)
 RETURNS text LANGUAGE sql IMMUTABLE AS $function$
    SELECT CASE
        WHEN public.fnpoultrysale_byproductrole(p_product) IS NOT NULL THEN 'ByproductSales'   -- 375
        WHEN p_product ILIKE '%egg%' THEN 'EggSales'
        WHEN p_product ILIKE '%manure%' OR p_product ILIKE '%droppings%'
          OR p_product ILIKE '%compost%' THEN 'ManureSales'
        WHEN p_product ILIKE '%feed%' OR p_product ILIKE '%mash%'
          OR p_product ILIKE '%pellet%' THEN 'FeedSales'
        WHEN p_product ILIKE '%bird%'     OR p_product ILIKE '%layer%'
          OR p_product ILIKE '%broiler%'  OR p_product ILIKE '%cockerel%'
          OR p_product ILIKE '%chick%'    OR p_product ILIKE '%cock%'
          OR p_product ILIKE '%hen%'      OR p_product ILIKE '%spent%'
          OR p_product ILIKE '%pullet%'   OR p_product ILIKE '%fowl%'
          OR p_product ILIKE '%culled%'   OR p_product ILIKE '%chicken%' THEN 'BirdSales'
        ELSE 'OtherRevenue'
    END;
$function$;

CREATE OR REPLACE FUNCTION public.fnpoultrysale_revenuelabel(p_line text)
 RETURNS text LANGUAGE sql IMMUTABLE AS $function$
    SELECT CASE p_line
        WHEN 'EggSales'       THEN 'Egg Sales'
        WHEN 'BirdSales'      THEN 'Bird Sales'
        WHEN 'ManureSales'    THEN 'Manure Sales'
        WHEN 'FeedSales'      THEN 'Feed Sales'
        WHEN 'ByproductSales' THEN 'Byproduct Sales (Broken Eggs / Dead Birds)'   -- 375
        ELSE 'Other Operating Revenue'
    END;
$function$;

SELECT pg_temp.m375_patch('sppoultryreport_plsummary', '375: byproduct sales are other revenue here',
$o$            COALESCE(SUM(amount) FILTER (WHERE linekey = 'OtherRevenue'), 0) AS otherrevenue,$o$,
$n$            COALESCE(SUM(amount) FILTER (WHERE linekey IN ('OtherRevenue', 'ByproductSales')), 0) AS otherrevenue,   -- 375: byproduct sales are other revenue here$n$);

-- ----------------------------------------- 4. egg / bird by-name readers --
SELECT pg_temp.m375_patch('sppoultryreport_profitlossbyflock', '375: byproducts are neither eggs nor live birds',
$o$            SUM(CASE WHEN s.product ILIKE '%egg%' THEN s.totalamount ELSE 0 END)                    AS c_eggrevenue,
            SUM(CASE WHEN s.product NOT ILIKE '%egg%' AND ($o$,
$n$            -- 375: byproducts are neither eggs nor live birds (they count in total revenue)
            SUM(CASE WHEN s.product ILIKE '%egg%' AND fnpoultrysale_byproductrole(s.product) IS NULL THEN s.totalamount ELSE 0 END) AS c_eggrevenue,
            SUM(CASE WHEN s.product NOT ILIKE '%egg%' AND fnpoultrysale_byproductrole(s.product) IS NULL AND ($n$);

SELECT pg_temp.m375_patch('fnflock_lifetimesummary', '375: Broken Eggs are not egg revenue',
$o$               SUM(s.totalamount) FILTER (WHERE lower(COALESCE(s.product, '')) LIKE '%egg%') AS c_egg,$o$,
$n$               SUM(s.totalamount) FILTER (WHERE lower(COALESCE(s.product, '')) LIKE '%egg%'
                                           AND fnpoultrysale_byproductrole(s.product) IS NULL) AS c_egg,   -- 375: Broken Eggs are not egg revenue$n$);

-- Egg stock balance: the two sale sums (before and in the period).
DO $$
DECLARE
    v_def text;
    v_n   integer;
BEGIN
    v_def := replace(pg_get_functiondef('public.sppoultryreport_eggstockbalance'::regproc), chr(13), '');
    IF position('375: not Broken Eggs' IN v_def) > 0 THEN
        RAISE NOTICE '375: sppoultryreport_eggstockbalance already patched, skipped';
        RETURN;
    END IF;
    v_n := (length(v_def) - length(replace(v_def, $o$s.status = 'Posted' AND s.product ILIKE '%egg%'$o$, ''))) / length($o$s.status = 'Posted' AND s.product ILIKE '%egg%'$o$);
    IF v_n <> 2 THEN
        RAISE EXCEPTION '375: eggstockbalance anchor found % times, expected 2', v_n;
    END IF;
    EXECUTE replace(v_def, $o$s.status = 'Posted' AND s.product ILIKE '%egg%'$o$,
                    $n$s.status = 'Posted' AND s.product ILIKE '%egg%' AND fnpoultrysale_byproductrole(s.product) IS NULL /* 375: not Broken Eggs */$n$);
    RAISE NOTICE '375: patched sppoultryreport_eggstockbalance';
END $$;

COMMIT;

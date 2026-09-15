-- =============================================================================
-- 268_PoultryCostRecognitionReads.postgres.sql
--
-- Purpose
-- -------
-- Phase 2, part 5: the READ side. Sections 43 to 47 ask the screens to show the
-- difference between what stock cost and what has actually reached Profit &
-- Loss. Every number needed for that already exists after 261-267; none of it
-- is reachable from .NET, because data access here is stored procedures only.
--
-- This file adds nothing to the model. It exposes it.
--
-- WHAT THIS FILE IS NOT
-- =====================
-- It is not a redefinition of any existing figure. totalcost, costperoutputunit,
-- unitcost and every report built on them come back byte for byte unchanged;
-- each function below is reproduced from its LIVE definition and only gains
-- columns at the END of its RETURNS TABLE, which is the one place a column can
-- be added without moving an existing ordinal.
--
-- It is also not a write path. Nothing here updates a row.
--
-- THE READS
-- =========
--   sppoultryrawmaterialpurchase_getall    a lot's snapshot + what it still owes
--                                          the P&L  (sections 43, 47)
--   sppoultryrawmaterialusage_gethistory   what a single consumption actually
--                                          recognised, and out of how many
--                                          cost layers  (sections 43, 44, 45)
--   sppoultryfeedproductionbatch_getbyid_rs1
--                                          production cost vs cost carried
--                                          forward into the feed  (section 46)
--   sppoultryinventoryvaluation_getall     per item: physical stock,
--   sppoultrycostlayeraudit_getall         operational value, deferred value,
--                                          and whether they can be trusted
--                                          (sections 31, 47)
--
-- OPERATIONAL COST AND RECOGNISED COST ARE DIFFERENT NUMBERS
-- ==========================================================
-- On a usage row they answer different questions:
--
--   operationalcost   what the stock drawn was worth. Always populated. This is
--                     the number a farm manager means by "what did that feed
--                     cost me", and it is what cost-per-bird is built on.
--   recognizedcost    only the part that hit the P&L AT THIS MOMENT. Zero for
--                     stock already expensed at purchase -- not because the
--                     feed was free, but because the expense was taken earlier.
--
-- Reporting only the second would tell an expense-at-purchase farm that all its
-- feed usage is free. Reporting only the first would double-count. Both are
-- returned, and costrecognitionstatus says in words which case a row is in so
-- the UI never has to infer it from a zero.
--
-- REVERSED USAGE
-- ==============
-- A reversed usage row keeps its allocations (append-only, migration 266), so
-- its costs still read back as they were drawn. isreversed already distinguishes
-- it and costrecognitionstatus says "Reversed" outright, so a caller summing the
-- column can filter on either.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Purchases: the cost-recognition snapshot and the deferred balance.
--
-- Reproduced from the LIVE definition. Columns 1-29 are unchanged.
--
-- deferredunitcost is per PRODUCTION unit to match productionunitcost directly
-- above it -- the two are comparable only if they are per the same unit, and a
-- lot bought in bags but consumed in kg would otherwise read as fifty times its
-- real deferred rate.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryrawmaterialpurchase_getall(text, date, date);

CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialpurchase_getall(p_farmid text, p_fromdate date DEFAULT NULL::date, p_todate date DEFAULT NULL::date)
 RETURNS TABLE(poultryrawmaterialpurchaseid integer, farmid text, poultryrawmaterialitemid integer, suppliername text, supplierid integer, purchasedate timestamp without time zone, quantity numeric, unitcost numeric, totalcost numeric, productionunit text, productionunitsperpurchaseunit numeric, paymentmethod text, amountpaid numeric, receipturl text, notes text, createdby text, createdat timestamp without time zone, updatedat timestamp without time zone, poultrycashaccountid integer, remainingquantity numeric, sourcefeedproductionbatchid integer, itemname text, category text, unitofmeasure text, balance numeric, productionquantity numeric, productionunitcost numeric, feedproductionbatchnumber text, feedproductionrole text, costrecognitionmethod text, deferredtotalcost numeric, deferredremainingcost numeric, deferredunitcost numeric, costrecognitionstatus text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT p.poultryrawmaterialpurchaseid, p.farmid::text, p.poultryrawmaterialitemid, p.suppliername::text,
           p.supplierid, p.purchasedate, p.quantity, p.unitcost, p.totalcost, p.productionunit::text,
           p.productionunitsperpurchaseunit, p.paymentmethod::text, p.amountpaid, p.receipturl::text,
           p.notes::text, p.createdby::text, p.createdat, p.updatedat, p.poultrycashaccountid,
           p.remainingquantity, p.sourcefeedproductionbatchid,
           i.itemname::text, i.category::text, i.unitofmeasure::text,
           (p.totalcost - p.amountpaid)::numeric(14,2) AS balance,
           (p.quantity * COALESCE(p.productionunitsperpurchaseunit, 1))::numeric(18,3) AS productionquantity,
           (CASE WHEN COALESCE(p.productionunitsperpurchaseunit, 0) > 0
                 THEN p.totalcost / NULLIF(p.quantity * p.productionunitsperpurchaseunit, 0)
                 ELSE NULL END)::numeric(18,4) AS productionunitcost,
           b.batchnumber::text AS feedproductionbatchnumber,
           (CASE WHEN b.poultryfeedproductionbatchid IS NULL THEN NULL
                 WHEN b.finishedfeeditemid = p.poultryrawmaterialitemid THEN 'Produced'
                 ELSE 'Purchased' END)::text AS feedproductionrole,
           -- 268. The snapshot taken when the lot was created (261/265). It is
           -- deliberately the lot's own value and not today's setting: changing
           -- the farm default must not restate a lot that has already been
           -- expensed.
           p.costrecognitionmethod::text,
           p.deferredtotalcost,
           p.deferredremainingcost,
           fnpoultrylot_deferredunitcost(p.deferredremainingcost, p.remainingquantity,
                                         p.productionunitsperpurchaseunit)::numeric(18,4)
               AS deferredunitcost,
           (CASE
                WHEN fnpoultrycostrecognition_expenseatpurchase(p.costrecognitionmethod)
                     THEN 'Expensed at purchase'
                WHEN COALESCE(p.deferredremainingcost, 0) > 0
                     THEN 'Deferred - not yet expensed'
                ELSE 'Deferred - fully expensed'
            END)::text AS costrecognitionstatus
    FROM   poultryrawmaterialpurchases p
    INNER  JOIN poultryrawmaterialitems i ON i.poultryrawmaterialitemid = p.poultryrawmaterialitemid
    LEFT   JOIN poultryfeedproductionbatches b
           ON b.poultryfeedproductionbatchid = p.sourcefeedproductionbatchid
    WHERE  p.farmid = p_farmid
       AND (p_fromdate IS NULL OR p.purchasedate::date >= p_fromdate)
       AND (p_todate   IS NULL OR p.purchasedate::date <= p_todate)
    ORDER  BY p.purchasedate DESC, p.poultryrawmaterialpurchaseid DESC;
END;
$function$;

COMMENT ON FUNCTION public.sppoultryrawmaterialpurchase_getall(text, date, date) IS
    'Raw material purchases with, since 268, the lot cost-recognition snapshot '
    'and its remaining deferred balance. Columns 1-29 are unchanged.';

-- -----------------------------------------------------------------------------
-- 2. Usage history: what a consumption drew, and what it recognised.
--
-- Reproduced from the LIVE definition. Columns 1-22 are unchanged.
--
-- The aggregate is one LATERAL rather than a correlated subquery per column so
-- the allocation rows are visited once, not three times, on a screen that lists
-- every usage a farm has ever recorded.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryrawmaterialusage_gethistory(text, integer, date, date);

CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialusage_gethistory(p_farmid text, p_poultryrawmaterialitemid integer DEFAULT NULL::integer, p_fromdate date DEFAULT NULL::date, p_todate date DEFAULT NULL::date)
 RETURNS TABLE(poultryrawmaterialusageid integer, farmid text, poultryrawmaterialitemid integer, poultryproductionbatchid integer, useddate timestamp without time zone, quantityused numeric, expectedquantityused numeric, variance numeric, variancereason text, usedbystaffid integer, notes text, createdby text, createdat timestamp without time zone, unitcost numeric, productionrecordid integer, poultryfeedproductionbatchid integer, isreversed boolean, reversedat timestamp without time zone, itemname text, unitofmeasure text, feedproductionbatchnumber text, feedproductionfeedname text, operationalcost numeric, recognizedcost numeric, costlayercount integer, costrecognitionstatus text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT u.poultryrawmaterialusageid, u.farmid::text, u.poultryrawmaterialitemid, u.poultryproductionbatchid,
           u.useddate, u.quantityused, u.expectedquantityused, u.variance, u.variancereason::text,
           u.usedbystaffid, u.notes::text, u.createdby::text, u.createdat, u.unitcost, u.productionrecordid,
           u.poultryfeedproductionbatchid, u.isreversed, u.reversedat,
           i.itemname::text, i.unitofmeasure::text,
           b.batchnumber::text AS feedproductionbatchnumber,
           fi.itemname::text   AS feedproductionfeedname,
           -- 268. What the stock drawn was worth. Always populated, whichever
           -- recognition method the lots were on.
           COALESCE(a.operational, 0)::numeric(14,2) AS operationalcost,
           -- 268. What of it reached the P&L at this consumption. Zero on
           -- expense-at-purchase stock -- the expense was taken at the purchase,
           -- not that the feed was free.
           COALESCE(a.deferred, 0)::numeric(14,2)    AS recognizedcost,
           COALESCE(a.layers, 0)::integer            AS costlayercount,
           (CASE
                WHEN u.isreversed THEN 'Reversed'
                WHEN COALESCE(a.layers, 0) = 0 THEN 'No cost layers'
                WHEN COALESCE(a.deferred, 0) > 0 THEN 'Expensed at consumption'
                ELSE 'Already expensed at purchase'
            END)::text AS costrecognitionstatus
    FROM   poultryrawmaterialusage u
    INNER  JOIN poultryrawmaterialitems i ON i.poultryrawmaterialitemid = u.poultryrawmaterialitemid
    LEFT   JOIN poultryfeedproductionbatches b
           ON b.poultryfeedproductionbatchid = u.poultryfeedproductionbatchid
    LEFT   JOIN poultryrawmaterialitems fi
           ON fi.poultryrawmaterialitemid = b.finishedfeeditemid
    LEFT   JOIN LATERAL (
               SELECT SUM(ub.quantitydrawn * ub.unitcostatdraw) AS operational,
                      SUM(ub.deferredcostdrawn)                 AS deferred,
                      COUNT(*)                                  AS layers
               FROM   poultryrawmaterialusagebatch ub
               WHERE  ub.poultryrawmaterialusageid = u.poultryrawmaterialusageid
           ) a ON TRUE
    WHERE  u.farmid = p_farmid
       AND (p_poultryrawmaterialitemid IS NULL OR u.poultryrawmaterialitemid = p_poultryrawmaterialitemid)
       AND (p_fromdate IS NULL OR u.useddate::date >= p_fromdate)
       AND (p_todate   IS NULL OR u.useddate::date <= p_todate)
    ORDER  BY u.useddate DESC, u.poultryrawmaterialusageid DESC;
END;
$function$;

COMMENT ON FUNCTION public.sppoultryrawmaterialusage_gethistory(text, integer, date, date) IS
    'Raw material usage history with, since 268, the operational cost of the '
    'stock drawn, the part of it recognised at consumption, and how many cost '
    'layers the draw crossed. Columns 1-22 are unchanged.';

-- -----------------------------------------------------------------------------
-- 3. Feed production detail: production cost vs cost carried forward.
--
-- Reproduced from the LIVE definition. Columns 1-25 are unchanged.
--
-- Section 46 wants two figures side by side, and they are genuinely different:
--
--   totalproductioncost      what the batch cost to make. Ingredients at their
--                            drawn cost plus milling, labour, transport. This is
--                            what cost-per-kg has always been and it does not
--                            change.
--   deferredproductioncost   only the part still waiting to be expensed. Lower
--                            whenever some ingredient was already expensed at
--                            purchase, and ZERO for a batch mixed entirely from
--                            expensed stock -- expensing such a batch again when
--                            the feed is eaten is precisely the double charge
--                            Phase 2 exists to prevent.
--
-- Both are read from the finished-feed LOT rather than recomputed: that lot is
-- where 265 recorded the transfer, and recomputing here would be a second
-- formula to keep in step with it.
--
-- deferredunitcost is deliberately built from deferredtotalcost over the
-- quantity PRODUCED, not from the remaining balance over the remaining stock:
-- it is the rate this batch carried forward, the counterpart of
-- costperoutputunit, and it must not drift as the feed is eaten.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryfeedproductionbatch_getbyid_rs1(text, integer);

CREATE OR REPLACE FUNCTION public.sppoultryfeedproductionbatch_getbyid_rs1(p_farmid text, p_poultryfeedproductionbatchid integer)
 RETURNS TABLE(poultryfeedproductionbatchid integer, farmid text, batchnumber text, productiondate timestamp without time zone, finishedfeeditemid integer, formulaid integer, quantityproduced numeric, outputunit text, totalingredientcost numeric, totaladditionalcost numeric, totalproductioncost numeric, costperoutputunit numeric, status text, notes text, createdby text, createdat timestamp without time zone, updatedat timestamp without time zone, postedby text, postedat timestamp without time zone, reversedby text, reversedat timestamp without time zone, reversalreason text, finishedfeeditemname text, finishedfeedunit text, formulaname text, costrecognitionmethod text, deferredproductioncost numeric, deferredremainingcost numeric, deferredunitcost numeric, costrecognitionstatus text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT b.poultryfeedproductionbatchid,
           b.farmid::text,
           b.batchnumber::text,
           b.productiondate,
           b.finishedfeeditemid,
           b.formulaid,
           b.quantityproduced,
           b.outputunit::text,
           b.totalingredientcost,
           b.totaladditionalcost,
           b.totalproductioncost,
           b.costperoutputunit,
           b.status::text,
           b.notes::text,
           b.createdby::text,
           b.createdat,
           b.updatedat,
           b.postedby::text,
           b.postedat,
           b.reversedby::text,
           b.reversedat,
           b.reversalreason::text,
           i.itemname::text,
           i.unitofmeasure::text,
           f.formulaname::text,
           -- 268. The finished-feed lot 265 created when the batch was posted. A
           -- draft or reversed batch has no lot, and the columns below read
           -- NULL/0 -- correct, because nothing has been carried anywhere yet.
           fl.costrecognitionmethod::text,
           COALESCE(fl.deferredtotalcost, 0)::numeric(14,2)     AS deferredproductioncost,
           COALESCE(fl.deferredremainingcost, 0)::numeric(14,2) AS deferredremainingcost,
           fnpoultrylot_deferredunitcost(fl.deferredtotalcost, b.quantityproduced, 1)::numeric(18,4)
               AS deferredunitcost,
           (CASE
                WHEN fl.poultryrawmaterialpurchaseid IS NULL THEN 'Not posted'
                WHEN COALESCE(fl.deferredtotalcost, 0) = 0
                     THEN 'Ingredients already expensed at purchase'
                WHEN COALESCE(fl.deferredtotalcost, 0) < b.totalproductioncost
                     THEN 'Part of the cost already expensed at purchase'
                ELSE 'Cost carried forward to feed inventory'
            END)::text AS costrecognitionstatus
    FROM   poultryfeedproductionbatches b
    LEFT   JOIN poultryrawmaterialitems i ON i.poultryrawmaterialitemid = b.finishedfeeditemid
    LEFT   JOIN poultryfeedformulas     f ON f.poultryfeedformulaid     = b.formulaid
    LEFT   JOIN poultryrawmaterialpurchases fl
           ON  fl.sourcefeedproductionbatchid = b.poultryfeedproductionbatchid
           AND fl.poultryrawmaterialitemid    = b.finishedfeeditemid
    WHERE  b.farmid = p_farmid AND b.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid;
END;
$function$;

COMMENT ON FUNCTION public.sppoultryfeedproductionbatch_getbyid_rs1(text, integer) IS
    'Feed production batch header with, since 268, the deferred cost carried '
    'into the finished-feed lot beside the unchanged production cost. Columns '
    '1-25 are unchanged.';

-- -----------------------------------------------------------------------------
-- 4. Two thin wrappers so .NET can reach 267 at all.
--
-- fnpoultryinventoryvaluation and fnpoultrycostlayeraudit are set-returning
-- functions, and this codebase reaches the database through stored procedures
-- only. Rather than teach the service layer a second calling convention, wrap
-- them. Neither wrapper adds logic: the definition of a valuation stays in one
-- place, 267.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryinventoryvaluation_getall(p_farmid text)
 RETURNS TABLE(poultryrawmaterialitemid integer, itemname text, category text, unitofmeasure text,
               usagemethod text, effectivemethod text, costrecognitionsource text,
               physicalquantity numeric, costlayerquantity numeric, quantitydrift numeric,
               operationalvalue numeric, deferredvalue numeric, openlots integer, deferredlots integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM fnpoultryinventoryvaluation(p_farmid);
END;
$function$;

COMMENT ON FUNCTION public.sppoultryinventoryvaluation_getall(text) IS
    'SP wrapper over fnpoultryinventoryvaluation so the .NET layer can read '
    'per-item operational and deferred inventory value.';

CREATE OR REPLACE FUNCTION public.sppoultrycostlayeraudit_getall(p_farmid text)
 RETURNS TABLE(finding text, severity text, itemid integer, itemname text,
               purchaseid integer, amount numeric, detail text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM fnpoultrycostlayeraudit(p_farmid);
END;
$function$;

COMMENT ON FUNCTION public.sppoultrycostlayeraudit_getall(text) IS
    'SP wrapper over fnpoultrycostlayeraudit. Returns NO ROWS on a healthy '
    'farm, like fnbalanceaudit.';

-- -----------------------------------------------------------------------------
-- Post-conditions. Reads only, so the assertion is that nothing moved.
-- -----------------------------------------------------------------------------
SELECT 'purchase read still returns every lot' AS check,
       (SELECT COUNT(*) FROM poultryrawmaterialpurchases p WHERE p.farmid = f.farmid) AS expected,
       (SELECT COUNT(*) FROM sppoultryrawmaterialpurchase_getall(f.farmid)) AS actual
FROM  (SELECT farmid FROM poultryrawmaterialpurchases GROUP BY farmid ORDER BY COUNT(*) DESC LIMIT 1) f;

SELECT 'usage read still returns every usage' AS check,
       (SELECT COUNT(*) FROM poultryrawmaterialusage u WHERE u.farmid = f.farmid) AS expected,
       (SELECT COUNT(*) FROM sppoultryrawmaterialusage_gethistory(f.farmid)) AS actual
FROM  (SELECT farmid FROM poultryrawmaterialusage GROUP BY farmid ORDER BY COUNT(*) DESC LIMIT 1) f;

SELECT 'no allocation recognises more than the stock it drew was worth' AS check,
       COUNT(*) AS should_be_zero
FROM   poultryrawmaterialusagebatch ub
WHERE  ub.deferredcostdrawn > (ub.quantitydrawn * ub.unitcostatdraw) + 0.01;

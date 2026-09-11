-- =============================================================================
-- 289_PoultryDeferredQueuePosition.postgres.sql
--
-- Purpose
-- -------
-- Answer the question the Awaiting P&L page raises and cannot currently settle:
--
--     "Why is this 5,000 not moving? I consumed 300 kg and nothing happened."
--
-- WHAT WAS ACTUALLY HAPPENING
-- ===========================
-- Nothing was wrong. A farm that switches to EXPENSE_WHEN_CONSUMED keeps every
-- lot it already owns stamped EXPENSE_WHEN_PURCHASED (261, deliberately), and
-- the new deferred lot is by definition the NEWEST one. Under FIFO -- the
-- default costing method -- the newest lot is drawn LAST.
--
-- So on a real farm:
--
--     lot  74  Aug 17    0 kg left   expensed at purchase
--     lot  84  Aug 24  402 kg left   expensed at purchase
--     lot  94  Aug 26   10 kg left   expensed at purchase
--     lot 317  Sep 11  500 kg left   DEFERRED 5,000     <-- 412 kg behind
--
-- 412 kg has to be consumed before a single pesewa of that 5,000 can be
-- recognised. Every consumption until then correctly produces no expense, and
-- correctly looks like a broken feature.
--
-- This file adds three read-only columns so the page can say so outright. It
-- changes no behaviour: the costing engine, the draw order and the deferred
-- balances are all untouched.
--
-- THE ORDER IS COPIED FROM THE ENGINE, NOT REINVENTED
-- ===================================================
-- The whole value of this figure is that it predicts what the engine will
-- actually do next. So the ORDER BY below is the one inside
-- sppoultryrawmaterialitem_consumebatches, reproduced exactly -- including the
-- LIFO id tie-break for same-day lots and the ASC id fallback. The pool filter
-- is the engine's too: same item, same farm, remainingquantity > 0.
--
-- If the engine's ordering is ever changed, THIS MUST CHANGE WITH IT. A queue
-- indicator that disagrees with the engine is worse than none, because it would
-- be believed.
--
-- WHY QUANTITY AND NOT JUST A POSITION
-- ------------------------------------
-- "4th in line" does not tell an owner what to do. "412 kg ahead of it" does:
-- it is the number of kilos they have to feed out before this cost starts
-- reaching the P&L, and it is directly comparable to the daily feed rate they
-- already know.
--
-- NULL, NOT ZERO, FOR A SPENT LOT
-- -------------------------------
-- A lot with no stock left is not in the draw pool at all, so it has no
-- position and nothing ahead of it. NULL says "not queued"; 0 would say "next
-- to be drawn", which is the opposite.
--
-- EFFECT ON TODAY'S NUMBERS: none. Two functions redefined to return three more
-- columns. No writer, no table, no change to any existing column's value.
--
-- Order: after 288.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Drop by NAME. Both functions gain columns, and CREATE OR REPLACE cannot
--    change a return type; an orphaned overload would let Npgsql bind the old
--    one by named argument and silently serve a row without the new columns.
-- -----------------------------------------------------------------------------
DO $drop$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM   pg_proc p
        JOIN   pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('fnpoultrydeferredpurchase_rows',
                             'sppoultrydeferredpurchase_getall',
                             'sppoultrydeferredpurchase_summary')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- -----------------------------------------------------------------------------
-- 1. Purchase rows, now with the lot's place in the consumption queue.
--
-- Columns 1-28 are exactly as 288 defined them. The last three are new.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrydeferredpurchase_rows(p_farmid text)
RETURNS TABLE(
    poultryrawmaterialpurchaseid integer,
    purchasedate                 timestamp without time zone,
    poultryrawmaterialitemid     integer,
    itemname                     text,
    category                     text,
    unitofmeasure                text,
    productionunit               text,
    supplierid                   integer,
    suppliername                 text,

    purchasedquantity            numeric,
    consumedquantity             numeric,
    remainingquantity            numeric,

    operationalcost              numeric,
    deferredtotalcost            numeric,
    recognizedcost               numeric,
    deferredremainingcost        numeric,
    recognitionpercent           numeric,

    allocatedrecognizedcost      numeric,
    recognitiondrift             numeric,

    costrecognitionmethod        text,
    recognitionmethodlabel       text,
    status                       text,
    exceptionreason              text,

    sourcefeedproductionbatchid  integer,
    feedproductionbatchnumber    text,
    islotproduced                boolean,

    recognitionevents            integer,
    lastrecognitiondate          timestamp without time zone,

    -- 289. FIFO | LIFO | HIFO -- the item's costing method, which decides the
    -- draw order and therefore everything below it.
    costingmethod                text,
    -- 289. Where this lot sits in the queue for its item, 1 = drawn next.
    -- NULL when the lot has no stock left, so it is not queued at all.
    queueposition                integer,
    -- 289. How much stock (production units) will be consumed before this lot
    -- is reached. 0 means it is next. THE number an owner needs.
    quantityaheadinqueue         numeric
)
LANGUAGE sql STABLE
AS $function$
    WITH pool AS (
        -- The engine's pool, its order, and its unit conversion. See the header:
        -- this is a copy of sppoultryrawmaterialitem_consumebatches, not a
        -- parallel idea of how consumption picks lots.
        SELECT p.poultryrawmaterialpurchaseid AS lotid,
               ROW_NUMBER() OVER w AS rn,
               -- Running total INCLUDING this lot, less this lot: what has to
               -- be drawn before this one is touched.
               SUM(p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1))
                   OVER (PARTITION BY p.farmid, p.poultryrawmaterialitemid
                         ORDER BY
                             CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'FIFO' THEN p.purchasedate END ASC,
                             CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'LIFO' THEN p.purchasedate END DESC,
                             CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'HIFO' THEN p.unitcost END DESC,
                             CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'LIFO' THEN p.poultryrawmaterialpurchaseid END DESC,
                             p.poultryrawmaterialpurchaseid ASC
                         ROWS UNBOUNDED PRECEDING)
               - (p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1))
                   AS ahead
        FROM   poultryrawmaterialpurchases p
        INNER  JOIN poultryrawmaterialitems i
               ON i.poultryrawmaterialitemid = p.poultryrawmaterialitemid
        WHERE  p.farmid = p_farmid
          AND  p.remainingquantity > 0
        WINDOW w AS (PARTITION BY p.farmid, p.poultryrawmaterialitemid
                     ORDER BY
                         CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'FIFO' THEN p.purchasedate END ASC,
                         CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'LIFO' THEN p.purchasedate END DESC,
                         CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'HIFO' THEN p.unitcost END DESC,
                         CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'LIFO' THEN p.poultryrawmaterialpurchaseid END DESC,
                         p.poultryrawmaterialpurchaseid ASC)
    )
    SELECT p.poultryrawmaterialpurchaseid,
           p.purchasedate,
           p.poultryrawmaterialitemid,
           i.itemname::text,
           i.category::text,
           i.unitofmeasure::text,
           COALESCE(p.productionunit, i.unitofmeasure)::text,
           p.supplierid,
           p.suppliername::text,

           (p.quantity * m.mult)::numeric(18,3),
           ((p.quantity - COALESCE(p.remainingquantity, 0)) * m.mult)::numeric(18,3),
           (COALESCE(p.remainingquantity, 0) * m.mult)::numeric(18,3),

           p.totalcost::numeric(14,2),
           p.deferredtotalcost::numeric(14,2),
           (p.deferredtotalcost - p.deferredremainingcost)::numeric(14,2),
           p.deferredremainingcost::numeric(14,2),
           (CASE WHEN p.deferredtotalcost > 0
                 THEN (p.deferredtotalcost - p.deferredremainingcost) * 100.0 / p.deferredtotalcost
                 ELSE 0 END)::numeric(9,2),

           COALESCE(a.recognized, 0)::numeric(14,2),
           ((p.deferredtotalcost - p.deferredremainingcost)
            - COALESCE(a.recognized, 0))::numeric(14,2),

           p.costrecognitionmethod::text,
           (CASE WHEN fnpoultrycostrecognition_expenseatpurchase(p.costrecognitionmethod)
                 THEN 'Expense when purchased'
                 ELSE 'Expense when used' END)::text,

           (CASE
                WHEN p.deferredremainingcost > 0 AND COALESCE(p.remainingquantity, 0) <= 0
                     THEN 'Exception'
                WHEN ABS((p.deferredtotalcost - p.deferredremainingcost)
                         - COALESCE(a.recognized, 0)) > 0.05
                     THEN 'Exception'
                WHEN fnpoultrycostrecognition_expenseatpurchase(p.costrecognitionmethod)
                     OR p.deferredtotalcost = 0
                     THEN 'Expensed at purchase'
                WHEN p.deferredremainingcost >= p.deferredtotalcost THEN 'Not yet expensed'
                WHEN p.deferredremainingcost <= 0                   THEN 'Fully expensed'
                ELSE 'Partly expensed'
            END)::text,

           (CASE
                WHEN p.deferredremainingcost > 0 AND COALESCE(p.remainingquantity, 0) <= 0
                     THEN 'Stock is finished but cost is still held as deferred. It was most '
                       || 'likely removed by an internal-use or stock-adjustment entry, which '
                       || 'does not draw from cost layers.'
                WHEN ABS((p.deferredtotalcost - p.deferredremainingcost)
                         - COALESCE(a.recognized, 0)) > 0.05
                     THEN 'The lot balance and its recorded usages disagree on how much has '
                       || 'been expensed. Neither figure should be quoted until this is checked.'
                ELSE NULL
            END)::text,

           p.sourcefeedproductionbatchid,
           b.batchnumber::text,
           COALESCE(p.sourcefeedproductionbatchid IS NOT NULL
                    AND b.finishedfeeditemid = p.poultryrawmaterialitemid, false),

           COALESCE(a.events, 0)::int,
           a.lastdate,

           -- 289.
           COALESCE(i.usagemethod, 'FIFO')::text,
           q.rn::integer,
           q.ahead::numeric(18,3)
    FROM   poultryrawmaterialpurchases p
    INNER  JOIN poultryrawmaterialitems i
           ON i.poultryrawmaterialitemid = p.poultryrawmaterialitemid
    CROSS  JOIN LATERAL (
               SELECT COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1) AS mult
           ) m
    LEFT   JOIN poultryfeedproductionbatches b
           ON b.poultryfeedproductionbatchid = p.sourcefeedproductionbatchid
    LEFT   JOIN pool q
           ON q.lotid = p.poultryrawmaterialpurchaseid
    LEFT   JOIN LATERAL (
               SELECT SUM(ub.deferredcostdrawn) AS recognized,
                      COUNT(*)                  AS events,
                      MAX(u.useddate)           AS lastdate
               FROM   poultryrawmaterialusagebatch ub
               JOIN   poultryrawmaterialusage u
                      ON u.poultryrawmaterialusageid = ub.poultryrawmaterialusageid
               WHERE  ub.poultryrawmaterialpurchaseid = p.poultryrawmaterialpurchaseid
                 AND  NOT COALESCE(u.isreversed, false)
           ) a ON TRUE
    WHERE  p.farmid = p_farmid;
$function$;

COMMENT ON FUNCTION public.fnpoultrydeferredpurchase_rows(text) IS
    'One row per purchase lot: deferred basis, what has reached Profit & Loss, '
    'what is still waiting, and since 289 the lot''s place in the consumption '
    'queue -- the reason a deferred cost can sit still while stock is consumed.';

-- -----------------------------------------------------------------------------
-- 2. The filtered list. Unchanged but for the three new columns.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrydeferredpurchase_getall(
    p_farmid     text,
    p_scope      text    DEFAULT 'DEFERRED',
    p_itemid     integer DEFAULT NULL,
    p_supplierid integer DEFAULT NULL,
    p_category   text    DEFAULT NULL,
    p_fromdate   date    DEFAULT NULL,
    p_todate     date    DEFAULT NULL,
    p_search     text    DEFAULT NULL
)
RETURNS TABLE(
    poultryrawmaterialpurchaseid integer,
    purchasedate                 timestamp without time zone,
    poultryrawmaterialitemid     integer,
    itemname                     text,
    category                     text,
    unitofmeasure                text,
    productionunit               text,
    supplierid                   integer,
    suppliername                 text,
    purchasedquantity            numeric,
    consumedquantity             numeric,
    remainingquantity            numeric,
    operationalcost              numeric,
    deferredtotalcost            numeric,
    recognizedcost               numeric,
    deferredremainingcost        numeric,
    recognitionpercent           numeric,
    allocatedrecognizedcost      numeric,
    recognitiondrift             numeric,
    costrecognitionmethod        text,
    recognitionmethodlabel       text,
    status                       text,
    exceptionreason              text,
    sourcefeedproductionbatchid  integer,
    feedproductionbatchnumber    text,
    islotproduced                boolean,
    recognitionevents            integer,
    lastrecognitiondate          timestamp without time zone,
    costingmethod                text,
    queueposition                integer,
    quantityaheadinqueue         numeric
)
LANGUAGE sql STABLE
AS $function$
    SELECT r.*
    FROM   public.fnpoultrydeferredpurchase_rows(p_farmid) r
    WHERE  (CASE COALESCE(NULLIF(p_scope, ''), 'DEFERRED')
                 WHEN 'DEFERRED'   THEN r.deferredremainingcost > 0
                 WHEN 'RECOGNIZED' THEN r.deferredtotalcost > 0
                                        AND r.deferredremainingcost <= 0
                 WHEN 'EXCEPTION'  THEN r.status = 'Exception'
                 ELSE TRUE
            END)
      AND  (p_itemid     IS NULL OR r.poultryrawmaterialitemid = p_itemid)
      AND  (p_supplierid IS NULL OR r.supplierid = p_supplierid)
      AND  (p_category   IS NULL OR r.category = p_category)
      AND  (p_fromdate   IS NULL OR r.purchasedate::date >= p_fromdate)
      AND  (p_todate     IS NULL OR r.purchasedate::date <= p_todate)
      AND  (NULLIF(p_search, '') IS NULL
            OR r.itemname     ILIKE '%' || p_search || '%'
            OR COALESCE(r.suppliername, '') ILIKE '%' || p_search || '%'
            OR r.poultryrawmaterialpurchaseid::text = p_search)
    ORDER  BY r.purchasedate DESC, r.poultryrawmaterialpurchaseid DESC;
$function$;

COMMENT ON FUNCTION public.sppoultrydeferredpurchase_getall(text, text, integer, integer, text, date, date, text) IS
    'The Awaiting P&L list. Defaults to lots with cost still waiting; '
    'RECOGNIZED, EXCEPTION and ALL widen it.';

-- -----------------------------------------------------------------------------
-- 3. Summary. Rebuilt only because section 2 was dropped by name above and it
--    calls it; the shape and every figure are unchanged from 288.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrydeferredpurchase_summary(
    p_farmid     text,
    p_scope      text    DEFAULT 'DEFERRED',
    p_itemid     integer DEFAULT NULL,
    p_supplierid integer DEFAULT NULL,
    p_category   text    DEFAULT NULL,
    p_fromdate   date    DEFAULT NULL,
    p_todate     date    DEFAULT NULL,
    p_search     text    DEFAULT NULL
)
RETURNS TABLE(
    remainingdeferredcost numeric,
    recognizedcost        numeric,
    deferredbasis         numeric,
    operationalcost       numeric,
    purchasecount         integer,
    deferredpurchases     integer,
    fullyrecognized       integer,
    notrecognized         integer,
    exceptions            integer,
    exceptiondrift        numeric,
    recognitionpercent    numeric,
    -- 289. How many of the filtered lots cannot be reached yet because older
    -- stock stands in front of them. Zero is the reassuring answer.
    blockedpurchases      integer,
    blockedcost           numeric
)
LANGUAGE sql STABLE
AS $function$
    SELECT COALESCE(SUM(r.deferredremainingcost), 0)::numeric(14,2),
           COALESCE(SUM(r.recognizedcost), 0)::numeric(14,2),
           COALESCE(SUM(r.deferredtotalcost), 0)::numeric(14,2),
           COALESCE(SUM(r.operationalcost), 0)::numeric(14,2),
           COUNT(*)::int,
           COUNT(*) FILTER (WHERE r.deferredremainingcost > 0)::int,
           COUNT(*) FILTER (WHERE r.deferredtotalcost > 0
                              AND r.deferredremainingcost <= 0)::int,
           COUNT(*) FILTER (WHERE r.deferredtotalcost > 0
                              AND r.recognizedcost <= 0)::int,
           COUNT(*) FILTER (WHERE r.status = 'Exception')::int,
           COALESCE(SUM(r.recognitiondrift) FILTER (WHERE r.status = 'Exception'), 0)::numeric(14,2),
           (CASE WHEN COALESCE(SUM(r.deferredtotalcost), 0) > 0
                 THEN SUM(r.recognizedcost) * 100.0 / SUM(r.deferredtotalcost)
                 ELSE 0 END)::numeric(9,2),
           COUNT(*) FILTER (WHERE r.deferredremainingcost > 0
                              AND COALESCE(r.quantityaheadinqueue, 0) > 0)::int,
           COALESCE(SUM(r.deferredremainingcost) FILTER (
               WHERE r.deferredremainingcost > 0
                 AND COALESCE(r.quantityaheadinqueue, 0) > 0), 0)::numeric(14,2)
    FROM   public.sppoultrydeferredpurchase_getall(
               p_farmid, p_scope, p_itemid, p_supplierid, p_category,
               p_fromdate, p_todate, p_search) r;
$function$;

COMMENT ON FUNCTION public.sppoultrydeferredpurchase_summary(text, text, integer, integer, text, date, date, text) IS
    'Summary cards for the Awaiting P&L page. Calls the list function so the '
    'totals and the rows cannot drift apart. Since 289 it also reports how much '
    'of the deferred cost is queued behind older stock.';

COMMIT;

-- =============================================================================
-- 281_WaterCostRecognitionReads.postgres.sql
--
-- Purpose
-- -------
-- The read surface for the water Deferred inventory cost page. The water mirror
-- of 288 + 289 combined -- poultry needed two files because 289 was written
-- after the page shipped and had to redefine three functions; water gets the
-- final shape in one.
--
-- Five functions, no writes, no behaviour change of any kind:
--
--   fnwaterdeferredpurchase_rows      one row per purchase lot: what was
--                                     deferred, what has reached the P&L, what
--                                     is still waiting, and where the lot sits
--                                     in the consumption queue
--   spwaterdeferredpurchase_getall    that list, filtered
--   spwaterdeferredpurchase_summary   the cards above it, computed FROM the
--                                     list so the two cannot disagree
--   spwaterdeferredpurchase_history   every draw against one lot
--   spwaterconsumption_costbreakdown  the other direction: how one production
--                                     batch's cost was arrived at
--
-- THE QUESTION THE QUEUE COLUMNS ANSWER
-- =====================================
-- Copied from 289, which was written because the page could not settle the
-- question owners actually ask: "I consumed film all month -- why is this
-- purchase still showing as not expensed?"
--
-- Because FIFO reached the older lot first. `queueposition` and
-- `quantityaheadinqueue` say so directly: 1 means this lot is next, and the
-- quantity is how much stock has to be drawn before it is touched.
--
-- THE ORDERING IS COPIED FROM THE ENGINE, NOT REINVENTED
-- ------------------------------------------------------
-- The window below is a copy of spwaterrawmaterialitem_consumebatches' ORDER BY,
-- including water's NULLS FIRST / NULLS LAST which poultry's copy does not have.
-- If the engine's order ever changes, this must change with it or the page will
-- confidently predict the wrong lot.
--
-- WHERE WATER DIFFERS FROM POULTRY
-- ================================
-- 1. NO PRODUCED LOTS. Poultry's rows carry sourcefeedproductionbatchid,
--    feedproductionbatchnumber and islotproduced, because feed production writes
--    a finished-feed lot back into the same table. Water has no such path (278's
--    header proves it), so those three columns do not exist here rather than
--    being present and always null.
--
-- 2. NO isreversed COLUMN. poultryrawmaterialusage carries isreversed/reversedat
--    because poultry reverses append-only. Water REOPENS a batch, and
--    spwaterproductionbatch_reopen DELETEs the allocation rows outright -- so a
--    reversed draw is simply not there to be read. The two fields are still in
--    the returned shape, because the API and the page are written against the
--    poultry contract, and they are emitted as constants: there is no state they
--    could report. Everything this function returns is live.
--
-- 3. ONE SOURCE, NOT FOUR. A water draw can only come from a production batch:
--    _consumebatches is called from spwaterproductionbatch_approve and nowhere
--    else. So poultry's productionrecordid / poultryproductionbatchid / flockid /
--    poultryfeedproductionbatchid collapse to waterproductionbatchid, and
--    sourcelabel names the batch and the product it was making.
--
-- 4. THE EXPENSE JOIN. Poultry keys its consumption expense on the production
--    record and has to guard a uuid cast of farmid. Water keys on the production
--    BATCH (279) with sourcetype in the three consumption types, and
--    waterexpenses.farmid is text like the rest of the water schema, so no cast
--    is needed. Only live rows count: reopen soft-deletes the recognition row,
--    so `isdeleted = false` is what makes a reopened batch read as unexpensed.
--
-- EFFECT ON TODAY'S NUMBERS: none. Five new read-only functions.
--
-- Order: after 279.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Refuse to run out of order.
-- -----------------------------------------------------------------------------
DO $guard$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE  table_name = 'waterrawmaterialusagebatch'
          AND  column_name = 'deferredcostdrawn'
    ) THEN
        RAISE EXCEPTION '281 requires 277 (waterrawmaterialusagebatch.deferredcostdrawn is missing).';
    END IF;
END
$guard$;

-- -----------------------------------------------------------------------------
-- 1. One row per lot.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fnwaterdeferredpurchase_rows(text);
CREATE OR REPLACE FUNCTION public.fnwaterdeferredpurchase_rows(p_farmid text)
RETURNS TABLE(
    waterrawmaterialpurchaseid integer,
    purchasedate               timestamp without time zone,
    waterrawmaterialitemid     integer,
    itemname                   text,
    category                   text,
    unitofmeasure              text,
    productionunit             text,
    supplierid                 integer,
    suppliername               text,

    purchasedquantity          numeric,
    consumedquantity           numeric,
    remainingquantity          numeric,

    operationalcost            numeric,
    deferredtotalcost          numeric,
    recognizedcost             numeric,
    deferredremainingcost      numeric,
    recognitionpercent         numeric,

    allocatedrecognizedcost    numeric,
    recognitiondrift           numeric,

    costrecognitionmethod      text,
    recognitionmethodlabel     text,
    status                     text,
    exceptionreason            text,

    recognitionevents          integer,
    lastrecognitiondate        timestamp without time zone,

    -- FIFO | LIFO | HIFO -- the item's costing method, which decides the draw
    -- order and therefore everything below it.
    costingmethod              text,
    -- Where this lot sits in the queue for its item, 1 = drawn next. NULL when
    -- the lot has no stock left, so it is not queued at all.
    queueposition              integer,
    -- How much stock (production units) will be consumed before this lot is
    -- reached. 0 means it is next. THE number an owner needs.
    quantityaheadinqueue       numeric
)
LANGUAGE sql STABLE
AS $function$
    WITH pool AS (
        -- The engine's pool, its order and its unit conversion. A COPY of
        -- spwaterrawmaterialitem_consumebatches, not a parallel idea of how
        -- consumption picks lots. NULLS FIRST / NULLS LAST included, because
        -- water's engine has them.
        SELECT p.waterrawmaterialpurchaseid AS lotid,
               ROW_NUMBER() OVER w AS rn,
               SUM(p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1))
                   OVER (PARTITION BY p.farmid, p.waterrawmaterialitemid
                         ORDER BY
                             CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'FIFO' THEN p.purchasedate END ASC NULLS FIRST,
                             CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'LIFO' THEN p.purchasedate END DESC NULLS LAST,
                             CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'HIFO' THEN p.unitcost END DESC NULLS LAST,
                             CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'LIFO' THEN p.waterrawmaterialpurchaseid END DESC NULLS LAST,
                             p.waterrawmaterialpurchaseid ASC
                         ROWS UNBOUNDED PRECEDING)
               - (p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1))
                   AS ahead
        FROM   waterrawmaterialpurchases p
        INNER  JOIN waterrawmaterialitems i
               ON i.waterrawmaterialitemid = p.waterrawmaterialitemid
        WHERE  p.farmid = p_farmid
          AND  p.remainingquantity > 0
        WINDOW w AS (PARTITION BY p.farmid, p.waterrawmaterialitemid
                     ORDER BY
                         CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'FIFO' THEN p.purchasedate END ASC NULLS FIRST,
                         CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'LIFO' THEN p.purchasedate END DESC NULLS LAST,
                         CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'HIFO' THEN p.unitcost END DESC NULLS LAST,
                         CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'LIFO' THEN p.waterrawmaterialpurchaseid END DESC NULLS LAST,
                         p.waterrawmaterialpurchaseid ASC)
    )
    SELECT p.waterrawmaterialpurchaseid,
           p.purchasedate,
           p.waterrawmaterialitemid,
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
           (CASE WHEN fnwatercostrecognition_expenseatpurchase(p.costrecognitionmethod)
                 THEN 'Expense when purchased'
                 ELSE 'Expense when used' END)::text,

           (CASE
                WHEN p.deferredremainingcost > 0 AND COALESCE(p.remainingquantity, 0) <= 0
                     THEN 'Exception'
                WHEN ABS((p.deferredtotalcost - p.deferredremainingcost)
                         - COALESCE(a.recognized, 0)) > 0.05
                     THEN 'Exception'
                WHEN fnwatercostrecognition_expenseatpurchase(p.costrecognitionmethod)
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

           COALESCE(a.events, 0)::int,
           a.lastdate,

           COALESCE(i.usagemethod, 'FIFO')::text,
           q.rn::integer,
           q.ahead::numeric(18,3)
    FROM   waterrawmaterialpurchases p
    INNER  JOIN waterrawmaterialitems i
           ON i.waterrawmaterialitemid = p.waterrawmaterialitemid
    CROSS  JOIN LATERAL (
               SELECT COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1) AS mult
           ) m
    LEFT   JOIN pool q
           ON q.lotid = p.waterrawmaterialpurchaseid
    -- No isreversed filter, unlike poultry: water's reopen DELETEs the
    -- allocations, so anything still here is live by construction.
    LEFT   JOIN LATERAL (
               SELECT SUM(ub.deferredcostdrawn) AS recognized,
                      COUNT(*)                  AS events,
                      MAX(u.useddate)           AS lastdate
               FROM   waterrawmaterialusagebatch ub
               JOIN   waterrawmaterialusage u
                      ON u.waterrawmaterialusageid = ub.waterrawmaterialusageid
               WHERE  ub.waterrawmaterialpurchaseid = p.waterrawmaterialpurchaseid
           ) a ON TRUE
    WHERE  p.farmid = p_farmid;
$function$;

COMMENT ON FUNCTION public.fnwaterdeferredpurchase_rows(text) IS
    'One row per purchase lot: deferred basis, what has reached Profit & Loss, '
    'what is still waiting, and the lot''s place in the consumption queue -- the '
    'reason a deferred cost can sit still while stock is consumed.';

-- -----------------------------------------------------------------------------
-- 2. The filtered list.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spwaterdeferredpurchase_getall(text, text, integer, integer, text, date, date, text);
CREATE OR REPLACE FUNCTION public.spwaterdeferredpurchase_getall(
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
    waterrawmaterialpurchaseid integer,
    purchasedate               timestamp without time zone,
    waterrawmaterialitemid     integer,
    itemname                   text,
    category                   text,
    unitofmeasure              text,
    productionunit             text,
    supplierid                 integer,
    suppliername               text,
    purchasedquantity          numeric,
    consumedquantity           numeric,
    remainingquantity          numeric,
    operationalcost            numeric,
    deferredtotalcost          numeric,
    recognizedcost             numeric,
    deferredremainingcost      numeric,
    recognitionpercent         numeric,
    allocatedrecognizedcost    numeric,
    recognitiondrift           numeric,
    costrecognitionmethod      text,
    recognitionmethodlabel     text,
    status                     text,
    exceptionreason            text,
    recognitionevents          integer,
    lastrecognitiondate        timestamp without time zone,
    costingmethod              text,
    queueposition              integer,
    quantityaheadinqueue       numeric
)
LANGUAGE sql STABLE
AS $function$
    SELECT r.*
    FROM   public.fnwaterdeferredpurchase_rows(p_farmid) r
    WHERE  (CASE COALESCE(NULLIF(p_scope, ''), 'DEFERRED')
                 WHEN 'DEFERRED'   THEN r.deferredremainingcost > 0
                 WHEN 'RECOGNIZED' THEN r.deferredtotalcost > 0
                                        AND r.deferredremainingcost <= 0
                 WHEN 'EXCEPTION'  THEN r.status = 'Exception'
                 ELSE TRUE
            END)
      AND  (p_itemid     IS NULL OR r.waterrawmaterialitemid = p_itemid)
      AND  (p_supplierid IS NULL OR r.supplierid = p_supplierid)
      AND  (p_category   IS NULL OR r.category = p_category)
      AND  (p_fromdate   IS NULL OR r.purchasedate::date >= p_fromdate)
      AND  (p_todate     IS NULL OR r.purchasedate::date <= p_todate)
      AND  (NULLIF(p_search, '') IS NULL
            OR r.itemname     ILIKE '%' || p_search || '%'
            OR COALESCE(r.suppliername, '') ILIKE '%' || p_search || '%'
            OR r.waterrawmaterialpurchaseid::text = p_search)
    ORDER  BY r.purchasedate DESC, r.waterrawmaterialpurchaseid DESC;
$function$;

COMMENT ON FUNCTION public.spwaterdeferredpurchase_getall(text, text, integer, integer, text, date, date, text) IS
    'The Deferred inventory cost list. Defaults to lots with cost still '
    'waiting; RECOGNIZED, EXCEPTION and ALL widen it.';

-- -----------------------------------------------------------------------------
-- 3. Summary. Computed FROM the list above, so the cards and the rows under
--    them cannot drift apart.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spwaterdeferredpurchase_summary(text, text, integer, integer, text, date, date, text);
CREATE OR REPLACE FUNCTION public.spwaterdeferredpurchase_summary(
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
    -- How many of the filtered lots cannot be reached yet because older stock
    -- stands in front of them. Zero is the reassuring answer.
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
    FROM   public.spwaterdeferredpurchase_getall(
               p_farmid, p_scope, p_itemid, p_supplierid, p_category,
               p_fromdate, p_todate, p_search) r;
$function$;

COMMENT ON FUNCTION public.spwaterdeferredpurchase_summary(text, text, integer, integer, text, date, date, text) IS
    'Summary cards for the Deferred inventory cost page. Calls the list function '
    'so the totals and the rows cannot drift apart. Also reports how much of the '
    'deferred cost is queued behind older stock.';

-- -----------------------------------------------------------------------------
-- 4. Every draw against one lot.
--
-- isreversed / reversedat are constants. See the header: water's reopen deletes
-- the allocation, so a reversed draw is not here to be read. They are kept in
-- the shape because the API and page were written against the poultry contract.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spwaterdeferredpurchase_history(text, integer);
CREATE OR REPLACE FUNCTION public.spwaterdeferredpurchase_history(
    p_farmid     text,
    p_purchaseid integer
)
RETURNS TABLE(
    waterrawmaterialusageid integer,
    useddate                timestamp without time zone,
    sourcetype              text,
    sourcelabel             text,
    waterproductionbatchid  integer,
    productionbatchnumber   text,
    productname             text,
    itemname                text,
    productionunit          text,
    quantitydrawn           numeric,
    unitcostatdraw          numeric,
    operationalcost         numeric,
    -- This allocation's own recognised amount. Zero on a lot that was expensed
    -- at purchase -- the stock was not free, its cost was taken earlier.
    recognizedcost          numeric,
    recognitionoutcome      text,
    isreversed              boolean,
    reversedat              timestamp without time zone,
    expenseid               integer,
    -- The whole BATCH's recognition expense for this category group, not this
    -- row's share. recognizedcost is this row's share.
    expenseamount           numeric,
    expensestatus           text
)
LANGUAGE sql STABLE
AS $function$
    SELECT u.waterrawmaterialusageid,
           u.useddate,
           'Production Batch'::text,
           -- One human label per row, so the UI never assembles one from
           -- nullable ids and gets it wrong differently in two places.
           (CASE
                WHEN u.waterproductionbatchid IS NOT NULL
                     -- waterproducts names its column `name`, not
                     -- `productname` -- the output column below keeps the
                     -- contract's spelling.
                     THEN concat('Batch ', COALESCE(b.batchnumber, u.waterproductionbatchid::text),
                                 COALESCE(' - ' || pr.name, ''))
                ELSE concat('Usage #', u.waterrawmaterialusageid)
            END)::text,
           u.waterproductionbatchid,
           b.batchnumber::text,
           pr.name::text,

           i.itemname::text,
           COALESCE(p.productionunit, i.unitofmeasure)::text,
           ub.quantitydrawn::numeric(18,3),
           ub.unitcostatdraw::numeric(18,4),
           (ub.quantitydrawn * ub.unitcostatdraw)::numeric(14,2),
           ub.deferredcostdrawn::numeric(14,2),
           (CASE
                WHEN COALESCE(ub.deferredcostdrawn, 0) > 0 THEN 'Expensed now'
                ELSE 'Already expensed at purchase'
            END)::text,

           false,
           NULL::timestamp without time zone,
           x.expenseid,
           x.netamount::numeric(14,2),
           (CASE
                WHEN x.expenseid IS NULL THEN 'No expense - nothing was deferred'
                ELSE 'Posted'
            END)::text
    FROM   waterrawmaterialusagebatch ub
    INNER  JOIN waterrawmaterialusage u
           ON u.waterrawmaterialusageid = ub.waterrawmaterialusageid
    INNER  JOIN waterrawmaterialpurchases p
           ON p.waterrawmaterialpurchaseid = ub.waterrawmaterialpurchaseid
    INNER  JOIN waterrawmaterialitems i
           ON i.waterrawmaterialitemid = u.waterrawmaterialitemid
    LEFT   JOIN waterproductionbatches b
           ON b.waterproductionbatchid = u.waterproductionbatchid
          AND b.farmid = u.farmid
    LEFT   JOIN waterproducts pr
           ON pr.waterproductid = b.waterproductid
    -- 279's recognition expense for THIS item's category group on that batch.
    -- Live rows only: reopen soft-deletes it, which is what makes a reopened
    -- batch correctly read as having recognised nothing.
    LEFT   JOIN LATERAL (
               SELECT MIN(e.waterexpenseid) AS expenseid,
                      SUM(e.amount)         AS netamount
               FROM   waterexpenses e
               WHERE  u.waterproductionbatchid IS NOT NULL
                 AND  e.farmid   = p_farmid
                 AND  e.sourceid = u.waterproductionbatchid
                 AND  e.isdeleted = FALSE
                 AND  e.sourcetype = CASE fnwatercostrecognition_categorygroup(i.category::text)
                                          WHEN 'Packaging' THEN 'WaterPackagingConsumption'
                                          WHEN 'Treatment' THEN 'WaterTreatmentConsumption'
                                          ELSE 'WaterSuppliesConsumption' END
           ) x ON TRUE
    WHERE  ub.waterrawmaterialpurchaseid = p_purchaseid
      AND  p.farmid = p_farmid
    ORDER  BY u.useddate, u.waterrawmaterialusageid;
$function$;

COMMENT ON FUNCTION public.spwaterdeferredpurchase_history(text, integer) IS
    'Every usage that drew on one purchase lot, with the quantity taken, the '
    'unit cost it was taken at and what of it reached Profit & Loss. '
    'expenseamount is the whole batch''s recognition expense for that category '
    'group, not this row''s share -- recognizedcost is this row''s share.';

-- -----------------------------------------------------------------------------
-- 5. The other direction: how ONE production batch's consumption cost was
--    arrived at, lot by lot.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spwaterconsumption_costbreakdown(text, integer);
CREATE OR REPLACE FUNCTION public.spwaterconsumption_costbreakdown(
    p_farmid                 text,
    p_waterproductionbatchid integer
)
RETURNS TABLE(
    waterrawmaterialusageid    integer,
    waterrawmaterialitemid     integer,
    itemname                   text,
    category                   text,
    useddate                   timestamp without time zone,
    totalquantityused          numeric,
    productionunit             text,

    -- The lot this line of the breakdown drew from.
    waterrawmaterialpurchaseid integer,
    purchasedate               timestamp without time zone,
    suppliername               text,

    quantitydrawn              numeric,
    unitcostatdraw             numeric,
    operationalcost            numeric,
    recognizedcost             numeric,
    lotrecognitionmethod       text,
    recognitionlabel           text,
    isreversed                 boolean
)
LANGUAGE sql STABLE
AS $function$
    SELECT u.waterrawmaterialusageid,
           u.waterrawmaterialitemid,
           i.itemname::text,
           i.category::text,
           u.useddate,
           u.quantityused::numeric(18,3),
           COALESCE(p.productionunit, i.unitofmeasure)::text,

           p.waterrawmaterialpurchaseid,
           p.purchasedate,
           p.suppliername::text,

           ub.quantitydrawn::numeric(18,3),
           ub.unitcostatdraw::numeric(18,4),
           (ub.quantitydrawn * ub.unitcostatdraw)::numeric(14,2),
           ub.deferredcostdrawn::numeric(14,2),
           p.costrecognitionmethod::text,
           -- The LOT's snapshot decides, not the item's current setting. Two
           -- rows of one breakdown can and do disagree here -- that is the whole
           -- point of showing it.
           (CASE
                WHEN fnwatercostrecognition_expenseatpurchase(p.costrecognitionmethod)
                     THEN 'Expensed at purchase'
                WHEN COALESCE(ub.deferredcostdrawn, 0) > 0
                     THEN 'Expense when used'
                ELSE 'Expense when used - already fully expensed'
            END)::text,
           false
    FROM   waterrawmaterialusage u
    INNER  JOIN waterrawmaterialusagebatch ub
           ON ub.waterrawmaterialusageid = u.waterrawmaterialusageid
    INNER  JOIN waterrawmaterialpurchases p
           ON p.waterrawmaterialpurchaseid = ub.waterrawmaterialpurchaseid
    INNER  JOIN waterrawmaterialitems i
           ON i.waterrawmaterialitemid = u.waterrawmaterialitemid
    WHERE  u.farmid = p_farmid
      AND  u.waterproductionbatchid = p_waterproductionbatchid
    ORDER  BY i.itemname, p.purchasedate, p.waterrawmaterialpurchaseid;
$function$;

COMMENT ON FUNCTION public.spwaterconsumption_costbreakdown(text, integer) IS
    'How one production batch''s consumption cost was arrived at: every lot '
    'drawn, the quantity and unit cost taken from each, and whether that lot was '
    'already expensed at purchase or is being expensed now.';

-- -----------------------------------------------------------------------------
-- 6. Grants.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.fnwaterdeferredpurchase_rows(text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spwaterdeferredpurchase_getall(text, text, integer, integer, text, date, date, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spwaterdeferredpurchase_summary(text, text, integer, integer, text, date, date, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spwaterdeferredpurchase_history(text, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spwaterconsumption_costbreakdown(text, integer) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification. Every function must exist and answer for a real company.
-- -----------------------------------------------------------------------------
DO $verify$
DECLARE
    v_farm text;
    v_n    integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE '281: no water company to verify against.';
        RETURN;
    END IF;

    SELECT COUNT(*) INTO v_n FROM fnwaterdeferredpurchase_rows(v_farm);
    RAISE NOTICE '281: rows() answered for % lots.', v_n;

    SELECT COUNT(*) INTO v_n FROM spwaterdeferredpurchase_getall(v_farm, 'ALL');
    RAISE NOTICE '281: getall(ALL) answered for % lots.', v_n;

    -- The invariant that matters: the cards are computed FROM the list, so a
    -- lot counted in one must be counted in the other.
    IF (SELECT purchasecount FROM spwaterdeferredpurchase_summary(v_farm, 'ALL')) <> v_n THEN
        RAISE EXCEPTION '281: the summary and the list disagree on how many lots there are.';
    END IF;
    RAISE NOTICE '281: summary agrees with the list.';

    PERFORM * FROM spwaterdeferredpurchase_history(v_farm, 0);
    PERFORM * FROM spwaterconsumption_costbreakdown(v_farm, 0);
    RAISE NOTICE '281: history and breakdown execute.';
END
$verify$;

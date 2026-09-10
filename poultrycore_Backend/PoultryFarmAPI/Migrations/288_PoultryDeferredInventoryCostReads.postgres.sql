-- =============================================================================
-- 288_PoultryDeferredInventoryCostReads.postgres.sql
--
-- Purpose
-- -------
-- Phase 3: make the deferred balance EXPLAINABLE.
--
-- 261-268 built the engine and it is not touched here. This file adds nothing
-- but reads -- five functions, no table, no column, no writer. The deferred
-- number on the inventory screen stops being a total nobody can take apart and
-- becomes a number you can click, expand, and follow to the cedi.
--
-- WHY NO NEW TABLES
-- =================
-- The obvious reading of "persist which purchases supplied each usage" is a new
-- recognition-allocation table. That table already exists and has since long
-- before this work:
--
--   poultryrawmaterialpurchases    IS the cost layer. quantity, unitcost,
--                                  remainingquantity, and since 264 the
--                                  deferred pair.
--   poultryrawmaterialusagebatch   IS the allocation. One row per lot a usage
--                                  drew from: quantitydrawn, unitcostatdraw,
--                                  and since 264 deferredcostdrawn -- the part
--                                  of that draw that became a P&L expense.
--
-- Those five columns are exactly the audit record this phase needs. A second
-- table beside them would be a second answer to "how much of this purchase is
-- left", and the two would disagree inside a month. So: reads only.
--
-- THE TWO WAYS TO COUNT RECOGNISED COST, AND WHY BOTH ARE REPORTED
-- ================================================================
-- There are two independent sources for "how much of this lot has reached the
-- P&L", and they are derived differently on purpose:
--
--   THE LOT SAYS      deferredtotalcost - deferredremainingcost
--                     Authoritative. The balance is decremented as the lot is
--                     drawn and RESTORED on reversal (266), so it is already
--                     net of everything that has been undone.
--
--   THE ALLOCATIONS   SUM(deferredcostdrawn) over draws whose usage is live.
--   SAY               Independent. Rebuilt from the individual draws.
--
-- On a healthy lot they agree. When they do not, something has moved stock
-- without going through the cost engine -- an internal-use row, a stock
-- adjustment, a stranded layer of the kind 267 already reports -- and the row
-- is flagged Exception rather than quietly showing whichever number is smaller.
--
-- Reporting one and hiding the other would make the disagreement invisible,
-- which is how a costing bug survives a year.
--
-- WHY RECOGNISED COST IS NOT INFERRED FROM QUANTITY
-- =================================================
-- "8% of the bag is gone, so 8% of the cost is recognised" is wrong here and
-- the brief is right to forbid it. A produced-feed lot's deferred cost is the
-- deferred SHARE of its ingredients, not its whole cost, so cost and quantity
-- deplete at different rates by design. Every figure below comes from the
-- deferred columns or from the allocations, never from a quantity ratio.
--
-- STATUS, AND THE ONE THE BRIEF ASKS FOR THAT IS NOT HERE
-- =======================================================
--   Expensed at purchase    nothing was ever deferred; consuming it is free
--   Not yet expensed        deferred, nothing drawn yet
--   Partly expensed         some drawn
--   Fully expensed          balance down to zero
--   Exception               the two counts disagree, or cost is stranded on a
--                           lot with no stock left to consume
--
-- The brief also lists "Reversed". It is deliberately NOT a purchase status: a
-- purchase is not reversed, a RECOGNITION is. Reversal restores the lot's
-- balance, so a fully-reversed lot correctly reads "Not yet expensed" again --
-- which is the true state of it. The reversal itself is visible where it
-- happened, on the history rows in section 4, which carry isreversed.
--
-- UNITS
-- =====
-- Every quantity below is in PRODUCTION units -- the unit stock is consumed in.
-- poultryrawmaterialusagebatch.quantitydrawn is already in those units and
-- unitcostatdraw is per those units, so the allocation rows need no conversion;
-- the purchase columns do, and get it via the mult expression in section 1.
-- A lot bought in 50kg bags and fed out in kg would otherwise report
-- "10 purchased, 995 consumed".
--
-- EFFECT ON TODAY'S NUMBERS: none. Five new read-only functions. Nothing that
-- writes, and no existing function redefined.
--
-- Order: after 287.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Drop by NAME, not by signature.
--
-- Same reason as 261: these gain columns as the screen grows, and CREATE OR
-- REPLACE cannot change a return type. An orphaned overload would let Npgsql
-- bind the old one by named argument and silently serve stale columns.
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
                             'sppoultrydeferredpurchase_summary',
                             'sppoultrydeferredpurchase_history',
                             'sppoultryconsumption_costbreakdown')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- -----------------------------------------------------------------------------
-- 1. One row per purchase lot: what was deferred, what has reached the P&L,
--    and what is still waiting.
--
-- Every lot is returned, including the expense-at-purchase ones. The caller
-- filters; a function that silently dropped them would make "All purchases"
-- impossible to build and would hide the very rows somebody checking for a
-- misconfigured item needs to see.
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

    -- Physical, in production units.
    purchasedquantity            numeric,
    consumedquantity             numeric,
    remainingquantity            numeric,

    -- Money. operationalcost is what the stock cost and is NOT the deferred
    -- basis: on an expense-at-purchase lot it is a real number while the
    -- deferred basis is zero.
    operationalcost              numeric,
    deferredtotalcost            numeric,
    recognizedcost               numeric,
    deferredremainingcost        numeric,
    recognitionpercent           numeric,

    -- The independent cross-check. See the header.
    allocatedrecognizedcost      numeric,
    recognitiondrift             numeric,

    costrecognitionmethod        text,
    recognitionmethodlabel       text,
    status                       text,
    exceptionreason              text,

    -- Provenance: a produced lot has no supplier, it has a batch.
    sourcefeedproductionbatchid  integer,
    feedproductionbatchnumber    text,
    islotproduced                boolean,

    recognitionevents            integer,
    lastrecognitiondate          timestamp without time zone
)
LANGUAGE sql STABLE
AS $function$
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
           -- AUTHORITATIVE recognised figure: what the lot opened with, less
           -- what it still holds. Already net of reversals, because reversal
           -- puts the balance back (266).
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

           -- Status. Exception is tested FIRST: a lot that disagrees with its
           -- own allocations must not be reported as merely "partly expensed",
           -- because the progress figure on it cannot be trusted.
           --
           -- The 0.05 tolerance is two rounding steps on numeric(14,2). Tighter
           -- would flag ordinary half-pesewa rounding across a many-layer draw;
           -- looser would hide a real one-pesewa-per-row leak.
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
           -- COALESCE, not a bare comparison: with no batch joined this is
           -- NULL rather than false, and a NULL boolean reaching the UI reads
           -- as "unknown provenance" on every ordinary purchase.
           COALESCE(p.sourcefeedproductionbatchid IS NOT NULL
                    AND b.finishedfeeditemid = p.poultryrawmaterialitemid, false),

           COALESCE(a.events, 0)::int,
           a.lastdate
    FROM   poultryrawmaterialpurchases p
    INNER  JOIN poultryrawmaterialitems i
           ON i.poultryrawmaterialitemid = p.poultryrawmaterialitemid
    -- One multiplier expression, referenced by every quantity column below, so
    -- the purchase-to-production conversion cannot drift between them.
    CROSS  JOIN LATERAL (
               SELECT COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1) AS mult
           ) m
    LEFT   JOIN poultryfeedproductionbatches b
           ON b.poultryfeedproductionbatchid = p.sourcefeedproductionbatchid
    -- The allocation side of the cross-check. Reversed usages are excluded
    -- because their cost was given back to the lot; counting them would make
    -- every reversal look like a drift.
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
    'what is still waiting, and an independent recount from the allocations. '
    'Rows whose two counts disagree are flagged Exception rather than averaged.';

-- -----------------------------------------------------------------------------
-- 2. The filtered list.
--
-- p_scope is the one filter that is not a plain equality, and it is the default
-- view of the page:
--
--   DEFERRED   remaining deferred cost > 0. What is still waiting. THE DEFAULT,
--              because the question the page answers is "what has not hit the
--              P&L yet" and a farm has far more settled lots than open ones.
--   RECOGNIZED lots that were deferred and are now fully expensed. Deliberately
--              excludes expense-at-purchase lots: they were never deferred, so
--              listing them as "fully recognised" would overstate what this
--              mechanism has actually done.
--   EXCEPTION  only the rows that need looking at.
--   ALL        every purchase, however it was recognised.
--
-- Filtering happens here rather than in section 1 so the summary in section 3
-- can apply the identical predicate to the identical source and cannot drift
-- from the table it is summarising.
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
-- The column list is spelled out rather than SETOF'd: a function returning
-- TABLE(...) does not create a named composite type, so there is nothing to
-- write SETOF against. Section 1 stays the single definition of what a row
-- MEANS; this repeats only its shape.
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
    lastrecognitiondate          timestamp without time zone
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
      -- Matched against the three things somebody actually types: the item, the
      -- supplier, and the purchase number they are holding.
      AND  (NULLIF(p_search, '') IS NULL
            OR r.itemname     ILIKE '%' || p_search || '%'
            OR COALESCE(r.suppliername, '') ILIKE '%' || p_search || '%'
            OR r.poultryrawmaterialpurchaseid::text = p_search)
    ORDER  BY r.purchasedate DESC, r.poultryrawmaterialpurchaseid DESC;
$function$;

COMMENT ON FUNCTION public.sppoultrydeferredpurchase_getall(text, text, integer, integer, text, date, date, text) IS
    'The Deferred Inventory Costs list. Defaults to lots with cost still '
    'waiting; RECOGNIZED, EXCEPTION and ALL widen it.';

-- -----------------------------------------------------------------------------
-- 3. The summary cards.
--
-- Same source and the same predicate as section 2 -- it calls it -- so the
-- cards can never disagree with the rows underneath them, which is the usual
-- way a filtered summary goes wrong.
--
-- NO QUANTITY TOTAL. The brief asks for one "where meaningful" and then says
-- quantities in different units must not be blindly summed; on a filter
-- spanning kg feed and ml medication there is no meaningful total, so it is
-- left out rather than shipped as a number nobody can defend. Quantity is on
-- every row, where it has a unit attached.
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
    -- What is still waiting. The headline, and the number the inventory
    -- screen's "Awaiting Profit & Loss" card links here to explain.
    remainingdeferredcost numeric,
    -- What these same purchases have already put into the P&L.
    recognizedcost        numeric,
    -- What they deferred to begin with. recognized + remaining, except on
    -- Exception rows -- which is exactly why the drift figure is returned too.
    deferredbasis         numeric,
    operationalcost       numeric,
    purchasecount         integer,
    deferredpurchases     integer,
    fullyrecognized       integer,
    notrecognized         integer,
    exceptions            integer,
    exceptiondrift        numeric,
    recognitionpercent    numeric
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
           -- Progress across the whole filter, weighted by money rather than by
           -- row count: one 78,000 lot barely started matters more than ten
           -- small ones finished.
           (CASE WHEN COALESCE(SUM(r.deferredtotalcost), 0) > 0
                 THEN SUM(r.recognizedcost) * 100.0 / SUM(r.deferredtotalcost)
                 ELSE 0 END)::numeric(9,2)
    FROM   public.sppoultrydeferredpurchase_getall(
               p_farmid, p_scope, p_itemid, p_supplierid, p_category,
               p_fromdate, p_todate, p_search) r;
$function$;

COMMENT ON FUNCTION public.sppoultrydeferredpurchase_summary(text, text, integer, integer, text, date, date, text) IS
    'Summary cards for the Deferred Inventory Costs page. Calls the list '
    'function so the totals and the rows cannot drift apart.';

-- -----------------------------------------------------------------------------
-- 4. Recognition history: which usages drew on THIS purchase.
--
-- The expand-a-row half of the page, and the answer to "these specific feed
-- usages caused the 6,500".
--
-- THE EXPENSE LINK IS PER RECORD, NOT PER ALLOCATION
-- ---------------------------------------------------
-- 266 writes ONE expense per production record covering everything that record
-- consumed, which may include a second item drawing on other lots entirely. So
-- expenseamount below is the RECORD's expense, not this allocation's share, and
-- is named and commented to say so. Splitting it per lot would be inventing a
-- number: the expense was never apportioned that way.
--
-- recognizedcost IS this allocation's share, and it comes from the allocation
-- row itself. That is the figure to trust, and the one the totals use.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrydeferredpurchase_history(
    p_farmid     text,
    p_purchaseid integer
)
RETURNS TABLE(
    poultryrawmaterialusageid integer,
    useddate                  timestamp without time zone,
    sourcetype                text,
    sourcelabel               text,
    productionrecordid        integer,
    poultryproductionbatchid  integer,
    productionbatchnumber     text,
    flockid                   integer,
    flockname                 text,
    poultryfeedproductionbatchid integer,
    feedproductionbatchnumber text,

    itemname                  text,
    productionunit            text,
    quantitydrawn             numeric,
    unitcostatdraw            numeric,
    operationalcost           numeric,
    -- This allocation's own recognised amount. Zero on a lot that was expensed
    -- at purchase -- the stock was not free, its cost was taken earlier.
    recognizedcost            numeric,
    recognitionoutcome        text,

    isreversed                boolean,
    reversedat                timestamp without time zone,
    expenseid                 integer,
    -- The whole record's expense. See the note above.
    expenseamount             numeric,
    expensestatus             text
)
LANGUAGE sql STABLE
AS $function$
    SELECT u.poultryrawmaterialusageid,
           u.useddate,
           (CASE
                WHEN u.poultryfeedproductionbatchid IS NOT NULL THEN 'Feed Production'
                WHEN i.category = 'Medication'                  THEN 'Medication Usage'
                ELSE 'Feed Usage'
            END)::text,
           -- One human label per row so the UI never has to assemble one from
           -- three nullable ids and get it wrong differently in two places.
           (CASE
                WHEN u.poultryfeedproductionbatchid IS NOT NULL
                     THEN concat('Feed Production ', COALESCE(fb.batchnumber, u.poultryfeedproductionbatchid::text))
                WHEN u.productionrecordid IS NOT NULL
                     THEN concat('Production Record #', u.productionrecordid,
                                 COALESCE(' - ' || f.name, ''))
                WHEN u.poultryproductionbatchid IS NOT NULL
                     THEN concat('Batch ', COALESCE(pb.batchnumber, u.poultryproductionbatchid::text))
                ELSE concat('Usage #', u.poultryrawmaterialusageid)
            END)::text,
           u.productionrecordid,
           u.poultryproductionbatchid,
           pb.batchnumber::text,
           pr.flockid,
           f.name::text,
           u.poultryfeedproductionbatchid,
           fb.batchnumber::text,

           i.itemname::text,
           COALESCE(p.productionunit, i.unitofmeasure)::text,
           ub.quantitydrawn::numeric(18,3),
           ub.unitcostatdraw::numeric(18,4),
           (ub.quantitydrawn * ub.unitcostatdraw)::numeric(14,2),
           ub.deferredcostdrawn::numeric(14,2),
           (CASE
                WHEN COALESCE(u.isreversed, false)     THEN 'Reversed'
                WHEN COALESCE(ub.deferredcostdrawn, 0) > 0
                     THEN 'Expensed now'
                ELSE 'Already expensed at purchase'
            END)::text,

           COALESCE(u.isreversed, false),
           u.reversedat,
           x.expenseid,
           x.netamount::numeric(14,2),
           (CASE
                WHEN x.expenseid IS NULL      THEN 'No expense - nothing was deferred'
                WHEN COALESCE(x.netamount, 0) = 0 THEN 'Reversed - net zero'
                ELSE 'Posted'
            END)::text
    FROM   poultryrawmaterialusagebatch ub
    INNER  JOIN poultryrawmaterialusage u
           ON u.poultryrawmaterialusageid = ub.poultryrawmaterialusageid
    INNER  JOIN poultryrawmaterialpurchases p
           ON p.poultryrawmaterialpurchaseid = ub.poultryrawmaterialpurchaseid
    INNER  JOIN poultryrawmaterialitems i
           ON i.poultryrawmaterialitemid = u.poultryrawmaterialitemid
    LEFT   JOIN poultryproductionbatches pb
           ON pb.poultryproductionbatchid = u.poultryproductionbatchid
    LEFT   JOIN poultryfeedproductionbatches fb
           ON fb.poultryfeedproductionbatchid = u.poultryfeedproductionbatchid
    -- productionrecords is one of the pre-poultry tables: its key is plain id,
    -- not productionrecordid. The column on the usage row that points AT it is
    -- productionrecordid, which is the pair that makes this join easy to write
    -- backwards.
    LEFT   JOIN productionrecords pr
           ON pr.id = u.productionrecordid AND pr.farmid = u.farmid
    LEFT   JOIN flock f
           ON f.flockid = pr.flockid AND f.farmid = pr.farmid
    -- The record's consumption expense, netted across the original and any
    -- compensating rows 266 appended. Net zero means it has been reversed.
    -- farmid on expense is a uuid where the poultry tables use varchar, so the
    -- cast is guarded exactly as 266 guards it: a farm id that will not cast
    -- has no linked expenses and must still return its history.
    LEFT   JOIN LATERAL (
               SELECT MIN(e.expenseid)          AS expenseid,
                      SUM(e.amount)             AS netamount
               FROM   expense e
               WHERE  u.productionrecordid IS NOT NULL
                 AND  e.sourceid   = u.productionrecordid
                 AND  e.sourcetype = CASE WHEN i.category = 'Medication'
                                          THEN 'PoultryMedicationConsumption'
                                          ELSE 'PoultryFeedConsumption' END
                 AND  e.farmid = (CASE WHEN p_farmid ~
                                       '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                                       THEN p_farmid::uuid ELSE NULL END)
           ) x ON TRUE
    WHERE  ub.poultryrawmaterialpurchaseid = p_purchaseid
      AND  p.farmid = p_farmid
    ORDER  BY u.useddate, u.poultryrawmaterialusageid;
$function$;

COMMENT ON FUNCTION public.sppoultrydeferredpurchase_history(text, integer) IS
    'Every usage that drew on one purchase lot, with the quantity taken, the '
    'unit cost it was taken at and what of it reached Profit & Loss. '
    'expenseamount is the whole production record''s expense, not this row''s '
    'share -- recognizedcost is this row''s share.';

-- -----------------------------------------------------------------------------
-- 5. The other direction: how ONE usage's cost was arrived at.
--
-- Section 4 reads down from a purchase. This reads up from a consumption --
-- "Feed consumed 150kg, cost 900, of which 400 is new expense; where did that
-- come from" -- and is what the production-record breakdown and the expense
-- page's View Cost Breakdown both show.
--
-- Keyed on the PRODUCTION RECORD rather than the usage row, for the same reason
-- 266 links its expense that way: editing a record deletes and rewrites its
-- usage rows, so a usage id captured in a link dangles after the first edit.
--
-- One row per (usage line, lot drawn). A record consuming feed and medication
-- returns both, which is what its single expense covers.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryconsumption_costbreakdown(
    p_farmid             text,
    p_productionrecordid integer
)
RETURNS TABLE(
    poultryrawmaterialusageid    integer,
    poultryrawmaterialitemid     integer,
    itemname                     text,
    category                     text,
    useddate                     timestamp without time zone,
    totalquantityused            numeric,
    productionunit               text,

    -- The lot this line of the breakdown drew from.
    poultryrawmaterialpurchaseid integer,
    purchasedate                 timestamp without time zone,
    suppliername                 text,
    sourcefeedproductionbatchid  integer,
    feedproductionbatchnumber    text,

    quantitydrawn                numeric,
    unitcostatdraw               numeric,
    operationalcost              numeric,
    recognizedcost               numeric,
    lotrecognitionmethod         text,
    recognitionlabel             text,
    isreversed                   boolean
)
LANGUAGE sql STABLE
AS $function$
    SELECT u.poultryrawmaterialusageid,
           u.poultryrawmaterialitemid,
           i.itemname::text,
           i.category::text,
           u.useddate,
           u.quantityused::numeric(18,3),
           COALESCE(p.productionunit, i.unitofmeasure)::text,

           p.poultryrawmaterialpurchaseid,
           p.purchasedate,
           p.suppliername::text,
           p.sourcefeedproductionbatchid,
           fb.batchnumber::text,

           ub.quantitydrawn::numeric(18,3),
           ub.unitcostatdraw::numeric(18,4),
           (ub.quantitydrawn * ub.unitcostatdraw)::numeric(14,2),
           ub.deferredcostdrawn::numeric(14,2),
           p.costrecognitionmethod::text,
           -- The LOT's snapshot decides, not the item's current setting. Two
           -- rows of one breakdown can and do disagree here -- that is the
           -- whole point of showing it.
           (CASE
                WHEN fnpoultrycostrecognition_expenseatpurchase(p.costrecognitionmethod)
                     THEN 'Expensed at purchase'
                WHEN COALESCE(ub.deferredcostdrawn, 0) > 0
                     THEN 'Expense when used'
                ELSE 'Expense when used - already fully expensed'
            END)::text,
           COALESCE(u.isreversed, false)
    FROM   poultryrawmaterialusage u
    INNER  JOIN poultryrawmaterialusagebatch ub
           ON ub.poultryrawmaterialusageid = u.poultryrawmaterialusageid
    INNER  JOIN poultryrawmaterialpurchases p
           ON p.poultryrawmaterialpurchaseid = ub.poultryrawmaterialpurchaseid
    INNER  JOIN poultryrawmaterialitems i
           ON i.poultryrawmaterialitemid = u.poultryrawmaterialitemid
    LEFT   JOIN poultryfeedproductionbatches fb
           ON fb.poultryfeedproductionbatchid = p.sourcefeedproductionbatchid
    WHERE  u.farmid = p_farmid
      AND  u.productionrecordid = p_productionrecordid
    ORDER  BY i.itemname, p.purchasedate, p.poultryrawmaterialpurchaseid;
$function$;

COMMENT ON FUNCTION public.sppoultryconsumption_costbreakdown(text, integer) IS
    'How one production record''s consumption cost was arrived at: every lot '
    'drawn, the quantity and unit cost taken from each, and whether that lot '
    'was already expensed at purchase or is being expensed now.';

COMMIT;

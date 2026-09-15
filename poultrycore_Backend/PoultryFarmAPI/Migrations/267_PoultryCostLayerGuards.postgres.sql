-- =============================================================================
-- 267_PoultryCostLayerGuards.postgres.sql
--
-- Purpose
-- -------
-- Phase 2, part 4: the two numbers a deferring farm needs to read, and the
-- audit that says when they cannot be trusted.
--
-- WHAT THIS FILE IS NOT
-- =====================
-- It is not the unsafe-reversal guards, because those already existed and this
-- work found them rather than writing them:
--
--   ..._purchase_delete    "Cannot delete: this purchase batch has already been
--                          drawn from by a production/medication record."
--   ...feedproduction_reverse
--                          "This batch cannot be reversed because some of the
--                          produced feed has already been used."
--
-- That is sections 29, 30 and 72 of the brief, in place long before Phase 2.
-- Both now also restore deferred cost (266), which is the only thing they were
-- missing. Adding a second layer of guard beside them would be two rules to
-- keep in step.
--
-- TWO INVENTORY VALUES, NOT ONE
-- =============================
-- Section 31 asks for the distinction and it is a real one:
--
--   operational value   what the stock cost. What it is worth to the business,
--                       what cost-per-kg is built on, and what an owner means
--                       by "how much stock do I have".
--   deferred value      only the part still waiting to hit Profit & Loss. Zero
--                       for stock bought under expense-on-purchase, however
--                       much that stock cost.
--
-- They are equal only on a farm that defers everything, and they are reported
-- separately so nobody reads a deferred value of zero as "worthless stock". The
-- existing screens that say "inventory value" are NOT redefined by this file --
-- nothing here changes an existing read.
--
-- THE DRIFT THIS SURFACES, AND WHY IT IS NOT FIXED HERE
-- =====================================================
-- An item's physical quantity and the sum of its lots are supposed to agree.
-- On this database they already do not, for several items and by large margins,
-- because two paths move stock WITHOUT drawing lots:
--
--   internal use          reduces currentquantity, writes its own non-cash
--                         expense (216), never touches remainingquantity
--   stock adjustments     the same
--
-- That predates all of this work. It matters more now: on a DEFERRED item,
-- stock that leaves without drawing a lot takes no deferred cost with it, so
-- that cost is stranded -- never recognised, sitting on a lot whose stock is
-- gone.
--
-- This file REPORTS that and does not repair it. Section 51 asks for exactly
-- that, and the reasons are worth stating: the drift has several causes with
-- different correct answers (a loss, a correction, a count fix, a genuine
-- consumption), silently rewriting lots would destroy the evidence needed to
-- tell them apart, and inventing a recognition for stock nobody costed would be
-- the double-expensing this whole phase exists to prevent.
--
-- Wiring internal use and adjustments into the costing engine is Phase 3 work,
-- and it needs the business to say which of those four things a negative
-- adjustment means before any code can be right.
--
-- EFFECT ON TODAY'S NUMBERS: none. Two read-only functions. Nothing is written,
-- altered or repaired.
--
-- Order: after 266.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Drop by NAME: both return tables and may gain columns later.
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
          AND  p.proname IN ('fnpoultryinventoryvaluation',
                             'fnpoultrycostlayeraudit',
                             'sppoultryinventoryvaluation_summary')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- -----------------------------------------------------------------------------
-- 1. Per-item valuation: both numbers, side by side, with the drift.
--
-- One row per item that has stock or lots. Reporting the drift on the same row
-- as the values is deliberate: a deferred value is only as trustworthy as the
-- agreement between the stock and the lots behind it, and separating the two
-- would let someone quote the first without seeing the second.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryinventoryvaluation(p_farmid text)
RETURNS TABLE(
    poultryrawmaterialitemid integer,
    itemname                 text,
    category                 text,
    unitofmeasure            text,
    usagemethod              text,
    -- What the item is set to do with FUTURE purchases. Says nothing about the
    -- lots already in stock, which carry their own snapshots.
    effectivemethod          text,
    costrecognitionsource    text,

    -- Physical, as the item record has it.
    physicalquantity         numeric,
    -- Physical, as the lots have it. These should agree.
    costlayerquantity        numeric,
    quantitydrift            numeric,

    -- What the remaining stock cost.
    operationalvalue         numeric,
    -- Of which, still waiting to reach Profit & Loss.
    deferredvalue            numeric,

    openlots                 integer,
    deferredlots             integer
)
LANGUAGE sql STABLE
AS $function$
    SELECT i.poultryrawmaterialitemid,
           i.itemname::text, i.category::text, i.unitofmeasure::text, i.usagemethod::text,
           r.method, r.source,

           COALESCE(i.currentquantity, 0)::numeric(18,3),
           COALESCE(l.poolqty, 0)::numeric(18,3),
           (COALESCE(i.currentquantity, 0) - COALESCE(l.poolqty, 0))::numeric(18,3),

           -- Operational value of what is LEFT: the remaining stock at its own
           -- lot's unit cost, in purchase units -- which is the basis unitcost
           -- is quoted in.
           COALESCE(l.opvalue, 0)::numeric(14,2),
           COALESCE(l.defvalue, 0)::numeric(14,2),

           COALESCE(l.openlots, 0)::int,
           COALESCE(l.deflots, 0)::int
    FROM   poultryrawmaterialitems i
    CROSS  JOIN LATERAL public.fnpoultrycostrecognition_effective(
                            p_farmid, i.poultryrawmaterialitemid, i.category, NULL) r
    LEFT   JOIN LATERAL (
        SELECT SUM(p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1)) AS poolqty,
               SUM(p.remainingquantity * p.unitcost)                                               AS opvalue,
               SUM(p.deferredremainingcost)                                                        AS defvalue,
               COUNT(*) FILTER (WHERE p.remainingquantity > 0)                                     AS openlots,
               COUNT(*) FILTER (WHERE p.deferredremainingcost > 0)                                 AS deflots
        FROM   poultryrawmaterialpurchases p
        WHERE  p.farmid = i.farmid AND p.poultryrawmaterialitemid = i.poultryrawmaterialitemid
          AND  p.remainingquantity > 0
    ) l ON TRUE
    WHERE  i.farmid = p_farmid
      AND  (COALESCE(i.currentquantity, 0) <> 0 OR COALESCE(l.poolqty, 0) <> 0)
    ORDER  BY i.itemname;
$function$;

COMMENT ON FUNCTION public.fnpoultryinventoryvaluation(text) IS
    'Per item: operational value (what the stock cost) AND deferred value (what '
    'has yet to reach the P&L), with the drift between physical stock and the '
    'cost layers. The two values differ, and reporting one without the other is '
    'how somebody quotes a deferred zero as though the stock were worthless.';

-- -----------------------------------------------------------------------------
-- 2. The audit. Returns NOTHING when healthy.
--
-- Same shape and same promise as fnbalanceaudit: an empty result is the good
-- answer, so it can be watched rather than read. Every row names a finding, the
-- item, the amount and what it means, because a diagnostic nobody can act on is
-- just an alarm.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrycostlayeraudit(p_farmid text)
RETURNS TABLE(
    finding      text,
    severity     text,     -- Corrupt | Stranded | Drift
    itemid       integer,
    itemname     text,
    purchaseid   integer,
    amount       numeric,
    detail       text
)
LANGUAGE sql STABLE
AS $function$
    -- ---- Corrupt: the numbers contradict themselves. Should be impossible;
    -- ---- the 264 check constraint refuses most of it. Watched anyway, because
    -- ---- a constraint added later cannot see rows written earlier.
    SELECT 'DeferredExceedsOriginal'::text, 'Corrupt'::text,
           p.poultryrawmaterialitemid, i.itemname::text, p.poultryrawmaterialpurchaseid,
           (p.deferredremainingcost - p.deferredtotalcost)::numeric(14,2),
           'A lot has more deferred cost left than it ever had.'::text
    FROM   poultryrawmaterialpurchases p
    JOIN   poultryrawmaterialitems i ON i.poultryrawmaterialitemid = p.poultryrawmaterialitemid
    WHERE  p.farmid = p_farmid AND p.deferredremainingcost > p.deferredtotalcost + 0.005

    UNION ALL
    -- A lot expensed at purchase must never carry deferred cost: its cost is
    -- already in the P&L, so recognising it again would be the double-expense.
    SELECT 'ExpensedLotCarriesDeferred', 'Corrupt',
           p.poultryrawmaterialitemid, i.itemname::text, p.poultryrawmaterialpurchaseid,
           p.deferredremainingcost::numeric(14,2),
           'A lot expensed at purchase still carries deferred cost; consuming it would expense the same money twice.'
    FROM   poultryrawmaterialpurchases p
    JOIN   poultryrawmaterialitems i ON i.poultryrawmaterialitemid = p.poultryrawmaterialitemid
    WHERE  p.farmid = p_farmid
      AND  p.costrecognitionmethod = 'EXPENSE_WHEN_PURCHASED'
      AND  p.deferredremainingcost > 0.005

    UNION ALL
    -- ---- Stranded: cost that can no longer be recognised, because the stock
    -- ---- it belonged to has gone.
    SELECT 'DeferredOnEmptyLot', 'Stranded',
           p.poultryrawmaterialitemid, i.itemname::text, p.poultryrawmaterialpurchaseid,
           p.deferredremainingcost::numeric(14,2),
           'The lot is empty but still holds deferred cost. Nothing can draw it now, so it will never reach the P&L.'
    FROM   poultryrawmaterialpurchases p
    JOIN   poultryrawmaterialitems i ON i.poultryrawmaterialitemid = p.poultryrawmaterialitemid
    WHERE  p.farmid = p_farmid
      AND  p.remainingquantity <= 0.0005 AND p.deferredremainingcost > 0.005

    UNION ALL
    -- ---- Drift: physical stock and the lots disagree.
    -- ---- On an item with no deferred cost this is an old, harmless
    -- ---- bookkeeping gap. On a DEFERRED item it is money: stock that left
    -- ---- without drawing a lot took no cost with it.
    SELECT 'StockLeftWithoutDrawingLots',
           CASE WHEN COALESCE(v.deferredvalue, 0) > 0 THEN 'Stranded' ELSE 'Drift' END,
           v.poultryrawmaterialitemid, v.itemname, NULL::integer,
           v.quantitydrift::numeric(14,2),
           CASE WHEN COALESCE(v.deferredvalue, 0) > 0
                THEN 'Physical stock is below the cost layers on an item that defers cost. Internal use and stock adjustments move stock without drawing lots, so that cost cannot now be recognised. See migration 267.'
                ELSE 'Physical stock and the cost layers disagree. Harmless while nothing is deferred, but it means lot-based costing cannot be trusted for this item.'
           END
    FROM   public.fnpoultryinventoryvaluation(p_farmid) v
    WHERE  ABS(v.quantitydrift) > 0.0005

    UNION ALL
    -- ---- The allocations must not claim more than the lot ever deferred.
    SELECT 'AllocationsExceedLot', 'Corrupt',
           p.poultryrawmaterialitemid, i.itemname::text, p.poultryrawmaterialpurchaseid,
           (a.drawn - p.deferredtotalcost)::numeric(14,2),
           'More deferred cost has been drawn from this lot than it ever had.'
    FROM   poultryrawmaterialpurchases p
    JOIN   poultryrawmaterialitems i ON i.poultryrawmaterialitemid = p.poultryrawmaterialitemid
    JOIN   LATERAL (
        SELECT COALESCE(SUM(b.deferredcostdrawn), 0) AS drawn
        FROM   poultryrawmaterialusagebatch b
        WHERE  b.poultryrawmaterialpurchaseid = p.poultryrawmaterialpurchaseid
    ) a ON TRUE
    WHERE  p.farmid = p_farmid AND a.drawn > p.deferredtotalcost + 0.005

    ORDER  BY 2, 4;
$function$;

COMMENT ON FUNCTION public.fnpoultrycostlayeraudit(text) IS
    'Returns NOTHING when healthy, like fnbalanceaudit. Corrupt = the numbers '
    'contradict themselves. Stranded = deferred cost that can no longer reach '
    'the P&L. Drift = stock and lots disagree. This function REPORTS; it never '
    'repairs, because the causes need different answers and rewriting lots '
    'would destroy the evidence.';

-- -----------------------------------------------------------------------------
-- 3. Farm totals, for the API.
--
-- Deliberately does NOT add up to a single "inventory value": that is the
-- question this whole file exists to split in two.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryinventoryvaluation_summary(p_farmid text)
RETURNS TABLE(
    itemswithstock     integer,
    operationalvalue   numeric,
    deferredvalue      numeric,
    itemsdeferring     integer,
    openlots           integer,
    deferredlots       integer,
    -- Non-zero means the two above are only as good as the drift allows, so the
    -- API can badge the figure rather than presenting it as settled.
    itemswithdrift     integer,
    auditfindings      integer
)
LANGUAGE sql STABLE
AS $function$
    SELECT COUNT(*)::int,
           COALESCE(SUM(v.operationalvalue), 0)::numeric(14,2),
           COALESCE(SUM(v.deferredvalue), 0)::numeric(14,2),
           COUNT(*) FILTER (WHERE v.deferredvalue > 0)::int,
           COALESCE(SUM(v.openlots), 0)::int,
           COALESCE(SUM(v.deferredlots), 0)::int,
           COUNT(*) FILTER (WHERE ABS(v.quantitydrift) > 0.0005)::int,
           (SELECT COUNT(*)::int FROM public.fnpoultrycostlayeraudit(p_farmid))
    FROM   public.fnpoultryinventoryvaluation(p_farmid) v;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'no lot contradicts itself' AS check,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END AS result
FROM   farms f
CROSS  JOIN LATERAL fnpoultrycostlayeraudit(f.farmid) a
WHERE  f.type = 'Poultry' AND a.severity = 'Corrupt'

UNION ALL
-- Nothing is deferred anywhere yet, so nothing can be stranded.
SELECT 'no deferred cost is stranded',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   farms f
CROSS  JOIN LATERAL fnpoultrycostlayeraudit(f.farmid) a
WHERE  f.type = 'Poultry' AND a.severity = 'Stranded'

UNION ALL
-- Drift is EXPECTED and pre-existing. Counted, not asserted away: the number is
-- the point, and it is what Phase 3 has to work through.
SELECT 'pre-existing drift (reported, not fixed)',
       COUNT(*) || ' item(s)'
FROM   farms f
CROSS  JOIN LATERAL fnpoultrycostlayeraudit(f.farmid) a
WHERE  f.type = 'Poultry' AND a.severity = 'Drift';

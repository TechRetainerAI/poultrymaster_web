-- =============================================================================
-- 221_WaterInventoryTracker.postgres.sql
--
-- Purpose
-- -------
-- Opening / in / out / closing stock per water product for a period, plus the
-- movements behind each figure. Water has an inventory snapshot (
-- spWaterInventory_GetStockSummary, the inventory-report page) and a flat
-- movement list (the stock-movement report), but nothing that reconciles the
-- two: nobody can currently answer "this product says 1,700 -- why?"
--
-- The unit problem this has to solve first
-- ----------------------------------------
-- waterstocktransactions carries two quantity columns and the codebase sums
-- them two different, contradictory ways:
--
--   quantity      INT, signed, in the ENTRY unit (bags). Rounded, by type.
--   basequantity  numeric, signed, in the BASE unit (sachets). Added by 084.
--
-- Migration 212's header states "water stock is summed in BASE units, never
-- bags". Migration 092 had already made that false: spWaterProduct_GetAll sums
-- plain quantity, and that is what every inventory screen shows. Meanwhile
-- fnwaterproductavgcost and migration 178 sum COALESCE(basequantity, quantity).
--
-- Only TWO of the seven txntypes populate basequantity:
--
--   Sale          (via spWaterSale_CreateV2, migration 084)  -- sets it
--   InternalUse   (migrations 212/213)                       -- sets it
--   Restock       (production approve, 039/063/067/188)      -- NULL
--   LoadOut       (vehicle loading approve)                  -- NULL
--   LoadReturnIn  (driver return approve)                    -- NULL
--   Adjust        (reopen, void, set-stock, corrections)     -- NULL
--   Return        (spWaterSale_Cancel, migration 026)        -- NULL
--
-- So COALESCE(basequantity, quantity) adds +10 (bags) to -300 (sachets) on any
-- product with sachetsperbag > 1. Opening + in - out = closing is exactly the
-- arithmetic that exposes that, which is why the tracker cannot be built on
-- either existing derivation.
--
-- Why the fix below is exact, not a guess
-- ---------------------------------------
-- Every one of the five types that leaves basequantity NULL writes a WHOLE BAG
-- COUNT into quantity: Restock writes goodbags, LoadOut and LoadReturnIn write
-- bags, Adjust writes a bag delta, and Return negates a bag-denominated Sale.
-- None of them can carry a part-bag. So
--
--     COALESCE(basequantity, quantity * sachetsperbag)
--
-- reproduces the true base-unit figure for all seven types rather than
-- approximating it. That is what makes this a READ-side fix: no backfill, no
-- write-path change, and no touching the pre-204 water SPs -- whose Postgres
-- bodies are not in this repo at all (001-210 are T-SQL kept as the logic of
-- record; the live functions were converted elsewhere).
--
-- Do not "simplify" the COALESCE away. Dropping either half silently reintroduces
-- the bug for a different subset of rows.
--
-- A sachet product with a NULL sachetsperbag falls back to a factor of 1, not to
-- 30 as migration 212 does when writing. 212 is writing a row it controls; here
-- we are reading history, and inventing a 30x multiplier would invent stock.
-- The verification block at the bottom lists any such product.
--
-- What this migration adds
-- ------------------------
--   fnwaterstockledger(farm)                  -- every movement, normalised
--   spwaterinventorytracker_get(farm,from,to) -- per product: open/in/out/close
--   spwaterinventorytracker_movements(...)    -- one product, running balance
--
-- Known gap, deliberately not papered over: losses do not move this ledger.
-- spWaterLossRecord_Approve only flips a status and waterproductionlosses is
-- written as a side effect of batch approval, so burst sachets and missing
-- stock never appear as an "out". The tracker reports the ledger honestly; it
-- does not invent the missing rows. The UI says so.
--
-- Idempotent: CREATE OR REPLACE only. No table is altered, no data is written.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The normalised ledger. One row per stock transaction, in base units.
-- -----------------------------------------------------------------------------
-- Set-returning and STABLE so the tracker functions below, and anything added
-- later, share ONE definition of what a movement is worth.
CREATE OR REPLACE FUNCTION public.fnwaterstockledger(p_farmid text)
RETURNS TABLE (
    stocktxnid      integer,
    waterproductid  integer,
    productname     text,
    txntype         text,
    movementlabel   text,
    createddate     timestamp,
    quantitybags    numeric,
    basequantity    numeric,   -- normalised; never NULL
    unitfactor      numeric,   -- sachets per bag applied to this row
    unitcost        numeric,
    relatedsaleid   integer,
    relatedid       integer,
    note            text,
    createdby       text
)
LANGUAGE sql
STABLE
AS $$
    SELECT st.stocktxnid,
           st.waterproductid,
           p.name,
           st.txntype,
           -- Labelled here rather than in the client so the two callers and any
           -- future one cannot drift apart on wording.
           CASE st.txntype
             WHEN 'Restock'      THEN 'Production'
             WHEN 'Sale'         THEN 'Sale'
             WHEN 'Return'       THEN 'Sale returned'
             WHEN 'LoadOut'      THEN 'Loaded to vehicle'
             WHEN 'LoadReturnIn' THEN 'Returned from vehicle'
             WHEN 'Adjust'       THEN 'Adjustment'
             WHEN 'InternalUse'  THEN 'Internal use'
             ELSE COALESCE(st.txntype, 'Movement')
           END,
           st.createddate,
           st.quantity::numeric,
           COALESCE(st.basequantity, st.quantity::numeric * f.factor),
           f.factor,
           st.unitcost,
           st.relatedsaleid,
           st.relatedid,
           st.note,
           st.createdby
    FROM   waterstocktransactions st
    JOIN   waterproducts p
           ON p.waterproductid = st.waterproductid
    CROSS  JOIN LATERAL (
        SELECT CASE
                 WHEN COALESCE(p.issachetproduct, FALSE)
                 THEN GREATEST(COALESCE(p.sachetsperbag, 1), 1)::numeric
                 ELSE 1::numeric
               END AS factor
    ) f
    WHERE  st.farmid = p_farmid;
$$;

-- -----------------------------------------------------------------------------
-- 2. Per-product position for a period.
-- -----------------------------------------------------------------------------
-- Opening is everything strictly BEFORE p_from; the window is [p_from, p_to]
-- inclusive of the whole end day, so a caller passing two equal dates gets that
-- one day rather than nothing.
--
-- Products with no movement at all are still returned, with their opening as
-- closing -- a product sitting untouched all month is a fact worth showing, and
-- dropping it would make the page disagree with the inventory screen.
CREATE OR REPLACE FUNCTION public.spwaterinventorytracker_get(
    p_farmid text, p_from date, p_to date)
RETURNS TABLE (
    waterproductid   integer,
    productname      text,
    sku              text,
    baseunit         text,
    issachetproduct  boolean,
    sachetsperbag    numeric,
    openingbase      numeric,
    stockinbase      numeric,
    stockoutbase     numeric,
    closingbase      numeric,
    openingbags      numeric,
    closingbags      numeric,
    unitcost         numeric,
    closingvalue     numeric,
    movementcount    integer
)
LANGUAGE sql
STABLE
AS $$
    WITH factor AS (
        SELECT p.waterproductid,
               p.name, p.sku, p.baseunit,
               COALESCE(p.issachetproduct, FALSE) AS issachetproduct,
               CASE WHEN COALESCE(p.issachetproduct, FALSE)
                    THEN GREATEST(COALESCE(p.sachetsperbag, 1), 1)::numeric
                    ELSE 1::numeric
               END AS f
        FROM   waterproducts p
        WHERE  p.farmid = p_farmid
    ),
    led AS (
        SELECT l.waterproductid, l.basequantity, l.createddate
        FROM   public.fnwaterstockledger(p_farmid) l
    ),
    agg AS (
        SELECT fa.waterproductid,
               COALESCE(SUM(l.basequantity)
                        FILTER (WHERE l.createddate < p_from::timestamp), 0) AS opening,
               COALESCE(SUM(l.basequantity)
                        FILTER (WHERE l.createddate >= p_from::timestamp
                                  AND l.createddate <  (p_to + 1)::timestamp
                                  AND l.basequantity > 0), 0) AS movedin,
               COALESCE(SUM(-l.basequantity)
                        FILTER (WHERE l.createddate >= p_from::timestamp
                                  AND l.createddate <  (p_to + 1)::timestamp
                                  AND l.basequantity < 0), 0) AS movedout,
               COUNT(l.basequantity)
                        FILTER (WHERE l.createddate >= p_from::timestamp
                                  AND l.createddate <  (p_to + 1)::timestamp) AS moves
        FROM   factor fa
        LEFT   JOIN led l ON l.waterproductid = fa.waterproductid
        GROUP  BY fa.waterproductid
    )
    SELECT fa.waterproductid,
           fa.name,
           fa.sku,
           COALESCE(fa.baseunit, CASE WHEN fa.issachetproduct THEN 'Sachet' ELSE 'Unit' END),
           fa.issachetproduct,
           fa.f,
           a.opening,
           a.movedin,
           a.movedout,
           a.opening + a.movedin - a.movedout,
           ROUND(a.opening / fa.f, 3),
           ROUND((a.opening + a.movedin - a.movedout) / fa.f, 3),
           c.cost,
           ROUND((a.opening + a.movedin - a.movedout) * c.cost, 2),
           a.moves::integer
    FROM   factor fa
    JOIN   agg a ON a.waterproductid = fa.waterproductid
    CROSS  JOIN LATERAL (
        -- Migration 218's unit-aware cost, asked in the BASE unit because the
        -- closing figure is in base units. Do not re-derive it here; 218 is the
        -- single place that decides what a unit of stock is worth.
        SELECT COALESCE(
                 public.fnwaterproductentrycost(p_farmid, fa.waterproductid, 'Sachet'),
                 0) AS cost
    ) c
    ORDER BY fa.name;
$$;

-- -----------------------------------------------------------------------------
-- 3. The movements behind one product's figures, with a running balance.
-- -----------------------------------------------------------------------------
-- The running balance is seeded from the same opening the position table shows,
-- so the last row of this list lands exactly on that row's closing. If it ever
-- does not, the two functions have drifted and one of them is wrong.
CREATE OR REPLACE FUNCTION public.spwaterinventorytracker_movements(
    p_farmid text, p_waterproductid integer, p_from date, p_to date)
RETURNS TABLE (
    stocktxnid     integer,
    createddate    timestamp,
    txntype        text,
    movementlabel  text,
    basequantity   numeric,
    quantitybags   numeric,
    runningbase    numeric,
    unitcost       numeric,
    note           text,
    createdby      text
)
LANGUAGE sql
STABLE
AS $$
    WITH opening AS (
        SELECT COALESCE(SUM(l.basequantity), 0) AS bal
        FROM   public.fnwaterstockledger(p_farmid) l
        WHERE  l.waterproductid = p_waterproductid
          AND  l.createddate < p_from::timestamp
    ),
    win AS (
        SELECT l.*
        FROM   public.fnwaterstockledger(p_farmid) l
        WHERE  l.waterproductid = p_waterproductid
          AND  l.createddate >= p_from::timestamp
          AND  l.createddate <  (p_to + 1)::timestamp
    )
    SELECT w.stocktxnid,
           w.createddate,
           w.txntype,
           w.movementlabel,
           w.basequantity,
           w.quantitybags,
           (SELECT bal FROM opening)
             + SUM(w.basequantity) OVER (ORDER BY w.createddate, w.stocktxnid
                                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
           w.unitcost,
           w.note,
           w.createdby
    FROM   win w
    ORDER  BY w.createddate, w.stocktxnid;
$$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'tracker functions (3 expected)' AS check,
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'MISSING (' || count(*) || ')' END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('fnwaterstockledger',
                     'spwaterinventorytracker_get',
                     'spwaterinventorytracker_movements');

-- Sachet products with no sachetsperbag configured. Each one is normalised with
-- a factor of 1, so its bag figures will read as base units. Expect zero rows;
-- any row here is a Product setup gap, not a tracker bug.
SELECT p.farmid, p.waterproductid, p.name, p.sachetsperbag
FROM   waterproducts p
WHERE  COALESCE(p.issachetproduct, FALSE)
  AND  COALESCE(p.sachetsperbag, 0) <= 1;

-- How far the old bag-sum disagrees with the normalised base-sum, per product.
-- Rows are EXPECTED here wherever Internal Use or a CreateV2 sale moved a
-- part-bag: quantity is an INT, so those rows rounded on the way in and the bag
-- column genuinely lost information the base column kept. A large drift on a
-- product with no internal use is worth investigating.
SELECT l.waterproductid,
       max(l.productname)                                  AS product,
       SUM(l.quantitybags)                                 AS old_bag_sum,
       ROUND(SUM(l.basequantity) / max(l.unitfactor), 3)   AS normalised_bag_sum,
       ROUND(SUM(l.basequantity) / max(l.unitfactor)
             - SUM(l.quantitybags), 3)                     AS drift_bags
FROM   public.fnwaterstockledger(
           (SELECT farmid FROM waterproducts LIMIT 1)) l
GROUP  BY l.waterproductid
HAVING ROUND(SUM(l.basequantity) / max(l.unitfactor) - SUM(l.quantitybags), 3) <> 0
ORDER  BY abs(SUM(l.basequantity) / max(l.unitfactor) - SUM(l.quantitybags)) DESC;

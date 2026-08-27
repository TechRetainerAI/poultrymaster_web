-- =============================================================================
-- 228_WaterStockBaseQuantityBackfill.postgres.sql
--
-- Purpose
-- -------
-- "Insufficient sachet stock for <product>" on a product the Water Inventory
-- page shows as In stock with tens of thousands of sachets. Both screens are
-- reading the same table and disagreeing.
--
-- The bug
-- -------
-- waterstocktransactions has TWO quantity columns:
--
--   quantity      integer  -- BAGS. The original column (026). Migration 179
--                             says so outright: "Quantity is INT (bags)".
--   basequantity  numeric  -- BASE UNITS (sachets). Added by 084 when sachet /
--                             bag selling units arrived.
--
-- Every writer sets `quantity`. Exactly ONE writer sets `basequantity`: the
-- sale path in 084, which writes it NEGATIVE. Production restock (039/063/067/
-- 188), delivery load and return (041/061/064/065/068/083/120/122/166), manual
-- adjustments (059/166b) and set-stock (179) all leave it NULL.
--
-- The sale-creation guard is:
--
--     on-hand := SUM(waterstocktransactions.basequantity)
--
-- SUM() skips NULLs, so that expression can only ever see SALES. For any sachet
-- product it is the negative of everything ever sold, and it can never be
-- positive -- so a sachet product can never be sold twice, no matter how much
-- was produced. That is exactly the shape of the live data: every product with
-- a negative on-hand is a product that has sold something.
--
-- Non-sachet products were never affected because the guard is scoped
-- `WHERE p.issachetproduct = true` -- which is why the other negative balances
-- in this database went unnoticed rather than blocking anything.
--
-- The fix
-- -------
-- Complete the column and keep it complete, rather than rewrite twenty writers
-- (and miss the twenty-first). Two parts:
--
--   1. BACKFILL every existing NULL basequantity from quantity, converting bags
--      to base units for sachet products.
--   2. A BEFORE INSERT/UPDATE TRIGGER that fills basequantity from quantity
--      whenever a writer omits it. One database object instead of twenty
--      function rewrites, and it covers writers that do not exist yet.
--
-- Deliberately NOT changed: the sale procedure. Its guard is correct arithmetic
-- over a column that was simply incomplete. Fix the data, leave the reader.
--
-- Idempotent, transactional. Re-running touches nothing (the backfill matches
-- only NULLs, and the trigger is dropped and recreated).
--
-- NOTE ON A SECOND, SEPARATE DEFECT -- read before trusting `quantity`:
-- the sale path writes `quantity` in SELLING units, not bags: selling 5 sachets
-- writes quantity = -5 into a bags-denominated column, i.e. it subtracts 5 BAGS.
-- This migration does NOT fix that, because `quantity` is an integer and a
-- 5-sachet sale is a sixth of a bag -- there is nowhere to put it. After this
-- migration `basequantity` is the trustworthy ledger and `quantity` is
-- advisory. Moving the Inventory page and the delivery guard onto basequantity
-- is the follow-up; it is a code change, not a data change, so it is not here.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Bags -> base units for one product.
-- -----------------------------------------------------------------------------
-- A sachet product stores bags in `quantity` and sells in sachets, so one bag is
-- sachetsperbag base units. Everything else is 1:1. COALESCE(...,1) so a sachet
-- product with no sachetsperbag set degrades to 1:1 rather than to zero -- zero
-- would silently erase its whole stock history.
CREATE OR REPLACE FUNCTION public.fnwaterstockbaseqty(
    p_waterproductid integer, p_quantity numeric)
RETURNS numeric
LANGUAGE sql
STABLE
AS $function$
    SELECT (p_quantity * CASE
                WHEN p.issachetproduct IS TRUE THEN COALESCE(NULLIF(p.sachetsperbag, 0), 1)
                ELSE 1
            END)::numeric
    FROM   waterproducts p
    WHERE  p.waterproductid = p_waterproductid;
$function$;

-- -----------------------------------------------------------------------------
-- 2. Backfill.
-- -----------------------------------------------------------------------------
-- Only NULLs. A row that already carries a basequantity was written by the sale
-- path, which knows the true base quantity of what it sold -- recomputing it
-- from `quantity` would REPLACE a correct sachet figure with a wrong one,
-- because that is precisely the row whose `quantity` is in selling units.
UPDATE waterstocktransactions t
SET    basequantity = COALESCE(fnwaterstockbaseqty(t.waterproductid, t.quantity::numeric),
                               t.quantity::numeric)
WHERE  t.basequantity IS NULL;

-- -----------------------------------------------------------------------------
-- 3. Keep it complete.
-- -----------------------------------------------------------------------------
-- Fires only when the writer omitted basequantity, so the sale path -- the one
-- writer that computes it properly, in selling units it alone understands --
-- keeps full control of its own rows.
CREATE OR REPLACE FUNCTION public.trgwaterstockbaseqty()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.basequantity IS NULL AND NEW.quantity IS NOT NULL THEN
        NEW.basequantity := COALESCE(
            fnwaterstockbaseqty(NEW.waterproductid, NEW.quantity::numeric),
            NEW.quantity::numeric);
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS tr_waterstocktransactions_baseqty ON waterstocktransactions;

CREATE TRIGGER tr_waterstocktransactions_baseqty
    BEFORE INSERT OR UPDATE ON waterstocktransactions
    FOR EACH ROW
    EXECUTE FUNCTION trgwaterstockbaseqty();

-- -----------------------------------------------------------------------------
-- 4. What the guard now sees.
-- -----------------------------------------------------------------------------
-- Every sachet product, with the on-hand the sale check reads. Anything still
-- negative here has genuinely sold more than it produced -- a real stock
-- shortfall to correct with a stock-take, not a bug in this migration.
CREATE OR REPLACE FUNCTION public.fnwaterstockonhandaudit(p_farmid text DEFAULT NULL::text)
RETURNS TABLE(
    waterproductid  integer,
    farmid          text,
    productname     text,
    issachetproduct boolean,
    sachetsperbag   integer,
    onhand_base     numeric,
    sum_quantity    bigint,
    txn_rows        bigint)
LANGUAGE sql
STABLE
AS $function$
    SELECT p.waterproductid, p.farmid::text, p.name::text,
           p.issachetproduct, p.sachetsperbag,
           COALESCE(SUM(t.basequantity), 0)::numeric(18,4),
           COALESCE(SUM(t.quantity), 0)::bigint,
           COUNT(t.stocktxnid)::bigint
    FROM   waterproducts p
    LEFT   JOIN waterstocktransactions t ON t.waterproductid = p.waterproductid
    WHERE  (p_farmid IS NULL OR p.farmid = p_farmid)
    GROUP  BY p.waterproductid, p.farmid, p.name, p.issachetproduct, p.sachetsperbag
    ORDER  BY p.farmid, p.name;
$function$;

COMMIT;

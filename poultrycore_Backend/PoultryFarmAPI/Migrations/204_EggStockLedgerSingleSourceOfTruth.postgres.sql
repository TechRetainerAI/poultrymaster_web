-- =============================================================================
-- 204 (PostgreSQL): egg stock = the ledger, and the ledger is complete.
-- Data half. Idempotent + fully reversible (everything is tagged migration-204).
-- Scope: only farms that ALREADY have a raw-egg product, so no farm silently
-- gains egg tracking it never had.
-- =============================================================================
BEGIN;

CREATE TEMP TABLE _eggfarm ON COMMIT DROP AS
SELECT DISTINCT ON (p.farmid) p.farmid, p.poultryproductid AS eggid
FROM   poultryproducts p
WHERE  COALESCE(p.israweggproduct, FALSE) = TRUE OR p.name IN ('Eggs','Chicken Eggs')
ORDER  BY p.farmid, COALESCE(p.israweggproduct,FALSE) DESC, p.poultryproductid;

-- --- BEFORE -----------------------------------------------------------------
SELECT 'BEFORE' AS phase, e.farmid, e.eggid,
       COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                 WHERE t.farmid=e.farmid AND t.poultryproductid=e.eggid),0) AS ledger_sum
FROM _eggfarm e ORDER BY e.farmid;

-- --- 1. Merge duplicate raw-egg products into the canonical one -------------
UPDATE poultrystocktransactions t
SET    poultryproductid = e.eggid
FROM   _eggfarm e, poultryproducts d
WHERE  d.poultryproductid = t.poultryproductid
  AND  d.farmid = e.farmid
  AND  t.farmid = e.farmid
  AND  d.poultryproductid <> e.eggid
  AND  (COALESCE(d.israweggproduct,FALSE) = TRUE OR d.name IN ('Eggs','Chicken Eggs'));

UPDATE poultryproducts d
SET    israweggproduct = FALSE,
       isactive        = FALSE,
       notes           = COALESCE(NULLIF(d.notes,''), '') || ' [merged into egg product by migration-204]',
       updateddate     = NOW()
FROM   _eggfarm e
WHERE  d.farmid = e.farmid
  AND  d.poultryproductid <> e.eggid
  AND  (COALESCE(d.israweggproduct,FALSE) = TRUE OR d.name IN ('Eggs','Chicken Eggs'));

-- --- 2. Backfill missing 'Production' ledger rows ----------------------------
-- Saleable = collected - broken - meaty - soft - lost (migration 198's rule),
-- floored at 0. Delta-based, so re-running is a no-op.
INSERT INTO poultrystocktransactions
       (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createddate, createdby)
SELECT pr.farmid, e.eggid, 'Production', d.delta, NULL, pr.id,
       'Egg production (backfill)', pr.date::timestamp, 'migration-204'
FROM   productionrecords pr
JOIN   _eggfarm e ON e.farmid = pr.farmid
CROSS  JOIN LATERAL (
    SELECT GREATEST(0, COALESCE(pr.totalproduction,0) - COALESCE(pr.brokeneggs,0)
                     - COALESCE(pr.meatyeggs,0) - COALESCE(pr.softeggs,0) - COALESCE(pr.losteggs,0))
         - COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                     WHERE t.farmid=pr.farmid AND t.txntype='Production' AND t.relatedid=pr.id),0) AS delta
) d
WHERE  d.delta <> 0;

-- --- 3. Backfill missing egg 'Sale' ledger rows ------------------------------
INSERT INTO poultrystocktransactions
       (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createddate, createdby)
SELECT s.farmid, e.eggid, 'Sale', d.delta, NULL, s.saleid,
       'Egg sale (backfill)', s.saledate::timestamp, 'migration-204'
FROM   sale s
JOIN   _eggfarm e ON e.farmid = s.farmid
CROSS  JOIN LATERAL (
    SELECT (-GREATEST(0, COALESCE(s.quantity,0)))
         - COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                     WHERE t.farmid=s.farmid AND t.txntype='Sale' AND t.relatedid=s.saleid),0) AS delta
) d
WHERE  s.product ILIKE '%egg%' AND d.delta <> 0;

-- --- AFTER ------------------------------------------------------------------
SELECT 'AFTER' AS phase, e.farmid, e.eggid,
       COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                 WHERE t.farmid=e.farmid AND t.poultryproductid=e.eggid),0) AS ledger_sum,
       COALESCE((SELECT SUM(GREATEST(0, COALESCE(pr.totalproduction,0)-COALESCE(pr.brokeneggs,0)
                            -COALESCE(pr.meatyeggs,0)-COALESCE(pr.softeggs,0)-COALESCE(pr.losteggs,0)))
                 FROM productionrecords pr WHERE pr.farmid=e.farmid),0) AS saleable_produced,
       COALESCE((SELECT SUM(s.quantity) FROM sale s WHERE s.farmid=e.farmid AND s.product ILIKE '%egg%'),0) AS egg_sales,
       COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                 WHERE t.farmid=e.farmid AND t.poultryproductid=e.eggid
                   AND t.txntype NOT IN ('Production','Sale')),0) AS manual_moves
FROM _eggfarm e ORDER BY e.farmid;

COMMIT;

-- ===========================================================================
-- Function half. Eggs are now an ordinary ledger-backed product.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.sppoultryproduct_getall(p_farmid text)
 RETURNS TABLE(poultryproductid integer, farmid text, name text, sku text, unit text, unitprice numeric, producttype text, isactive boolean, notes text, createddate timestamp without time zone, updateddate timestamp without time zone, israweggproduct boolean, requiresrecipesetup boolean, size text, isbirdproduct boolean, stockonhand numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_birdid integer;
    v_birdsleft numeric;
BEGIN
    -- Birds are the only finished product whose stock is NOT the ledger: they are
    -- derived from the birds left in the flocks (migration 143 / the Production Log).
    --
    -- Eggs used to be special too (migration 150 re-derived them from
    -- ProductionRecords as total-broken) because the stock ledger was incomplete.
    -- Migration 204 backfilled every missing Production/Sale row, so the ledger is
    -- now the single source of truth for eggs like every other product. That also
    -- makes this figure agree with the Egg Tracker's "Eggs on hand", which the old
    -- formula could not: it ignored meaty/soft/lost eggs and double-counted
    -- under-posted production.
    SELECT p.poultryproductid INTO v_birdid
    FROM   poultryproducts p
    WHERE  p.farmid = p_farmid AND (p.isbirdproduct = TRUE OR p.name = 'Birds')
    ORDER  BY p.isbirdproduct DESC NULLS LAST, p.poultryproductid
    LIMIT 1;

    v_birdsleft := COALESCE((
        SELECT SUM(CASE
                     WHEN lr.noofbirdsleft IS NULL          THEN f.quantity
                     WHEN lr.noofbirdsleft < 0              THEN 0
                     WHEN lr.noofbirdsleft > f.quantity     THEN f.quantity
                     ELSE lr.noofbirdsleft
                   END)
        FROM   flock f
        LEFT   JOIN LATERAL (
            SELECT pr.noofbirdsleft
            FROM   productionrecords pr
            WHERE  pr.farmid = p_farmid AND pr.flockid = f.flockid
            ORDER  BY pr.date DESC
            LIMIT 1
        ) lr ON TRUE
        WHERE  f.farmid = p_farmid AND f.active = TRUE AND f.hasarrived = TRUE
           AND COALESCE(f.isdeleted, FALSE) = FALSE), 0);

    RETURN QUERY
    SELECT p.poultryproductid, p.farmid::text, p.name::text, p.sku::text, p.unit::text,
           p.unitprice, p.producttype::text, p.isactive, p.notes::text, p.createddate,
           p.updateddate, p.israweggproduct, p.requiresrecipesetup, p.size::text, p.isbirdproduct,
           (CASE
                WHEN v_birdid IS NOT NULL AND p.poultryproductid = v_birdid THEN v_birdsleft
                ELSE COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                               WHERE t.poultryproductid = p.poultryproductid AND t.farmid = p.farmid), 0)
            END)::numeric(18,3) AS stockonhand
    FROM   poultryproducts p
    WHERE  p.farmid = p_farmid
    ORDER  BY p.isactive DESC NULLS LAST, p.name;
END;
$function$;



CREATE OR REPLACE FUNCTION public.sppoultryproduct_setstock(p_farmid text, p_poultryproductid integer, p_targetquantity numeric, p_note text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_isbird boolean := FALSE;
    v_current numeric;
    v_delta numeric;
BEGIN
    SELECT COALESCE(COALESCE(p.isbirdproduct, FALSE) = TRUE OR p.name = 'Birds', FALSE)
    INTO   v_isbird
    FROM   poultryproducts p
    WHERE  p.poultryproductid = p_poultryproductid AND p.farmid = p_farmid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product not found for this company.';
    END IF;

    IF v_isbird THEN
        RAISE EXCEPTION 'Bird stock is worked out from the birds left in your flocks, so it cannot be set here. Correct it in the flock / production records (record mortality, or edit the flock).';
    END IF;

    -- Current stock exactly as sppoultryproduct_getall shows it: the ledger sum
    -- (eggs included, since migration 204 made the egg ledger complete).
    v_current := COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                           WHERE t.poultryproductid = p_poultryproductid AND t.farmid = p_farmid), 0);

    v_delta := p_targetquantity - v_current;

    IF v_delta <> 0 THEN
        INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, note, createdby)
        VALUES (p_farmid, p_poultryproductid, 'Adjustment', v_delta, COALESCE(p_note, 'Stock-take correction'), p_createdby);
    END IF;

    RETURN COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                     WHERE t.poultryproductid = p_poultryproductid AND t.farmid = p_farmid), 0);
END;
$function$;



CREATE OR REPLACE FUNCTION public.sppoultryproduct_reconcilestock(p_farmid text, p_poultryproductid integer DEFAULT NULL::integer)
 RETURNS TABLE(poultryproductid integer, name text, stockin numeric, stockout numeric, currentstock numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_birdid integer;
    v_birdsplaced numeric;
    v_birdsleft numeric;
BEGIN
    SELECT p.poultryproductid INTO v_birdid
    FROM   poultryproducts p
    WHERE  p.farmid = p_farmid AND (COALESCE(p.isbirdproduct, FALSE) = TRUE OR p.name = 'Birds')
    ORDER  BY p.isbirdproduct DESC NULLS LAST, p.poultryproductid
    LIMIT 1;

    v_birdsplaced := COALESCE((
        SELECT SUM(f.quantity) FROM flock f
        WHERE f.farmid = p_farmid AND f.active = TRUE AND f.hasarrived = TRUE
          AND COALESCE(f.isdeleted, FALSE) = FALSE), 0);

    v_birdsleft := COALESCE((
        SELECT SUM(CASE WHEN lr.noofbirdsleft IS NULL      THEN f.quantity
                        WHEN lr.noofbirdsleft < 0          THEN 0
                        WHEN lr.noofbirdsleft > f.quantity THEN f.quantity
                        ELSE lr.noofbirdsleft END)
        FROM flock f
        LEFT JOIN LATERAL (
            SELECT pr.noofbirdsleft FROM productionrecords pr
            WHERE pr.farmid = p_farmid AND pr.flockid = f.flockid
            ORDER BY pr.date DESC LIMIT 1
        ) lr ON TRUE
        WHERE f.farmid = p_farmid AND f.active = TRUE AND f.hasarrived = TRUE
          AND COALESCE(f.isdeleted, FALSE) = FALSE), 0);

    -- Eggs reconcile from the ledger like every other product (migration 204).
    RETURN QUERY
    SELECT p.poultryproductid,
           p.name::text,
           (CASE
                WHEN p.poultryproductid = v_birdid THEN v_birdsplaced
                ELSE COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                               WHERE t.poultryproductid = p.poultryproductid AND t.farmid = p.farmid
                                 AND t.quantity > 0), 0)
           END)::numeric(18,3) AS stockin,
           (CASE
                WHEN p.poultryproductid = v_birdid THEN v_birdsplaced - v_birdsleft
                ELSE COALESCE((SELECT SUM(-t.quantity) FROM poultrystocktransactions t
                               WHERE t.poultryproductid = p.poultryproductid AND t.farmid = p.farmid
                                 AND t.quantity < 0), 0)
           END)::numeric(18,3) AS stockout,
           (CASE
                WHEN p.poultryproductid = v_birdid THEN v_birdsleft
                ELSE COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                               WHERE t.poultryproductid = p.poultryproductid AND t.farmid = p.farmid), 0)
           END)::numeric(18,3) AS currentstock
    FROM   poultryproducts p
    WHERE  p.farmid = p_farmid AND (p_poultryproductid IS NULL OR p.poultryproductid = p_poultryproductid)
    ORDER  BY p.name;
END;
$function$;

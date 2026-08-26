-- =============================================================================
-- 214_FixWaterInternalUsageItemsJsonKeys.postgres.sql
--
-- Symptom
-- -------
-- Saving an Internal Use record appeared to work -- the header row was written,
-- a reference number was issued -- but the product line vanished. The list then
-- showed no product, no quantity and a zero cost, and posting failed with
-- "Add at least one product before posting."
--
--   waterinternalusage      1 row   IU-2026-0001
--   waterinternalusageitems 0 rows
--
-- Cause
-- -----
-- json_to_recordset matches JSON keys to the column names in its AS clause
-- CASE-SENSITIVELY, and unquoted identifiers in that clause fold to lowercase.
-- The service sends idiomatic camelCase:
--
--     [{"waterProductId":17,"entryQuantity":5,"entryUnitCost":9}]
--
-- while migration 212 declared the recordset as
--
--     AS j(waterproductid integer, entryquantity numeric, ...)
--
-- so "waterProductId" never matched waterproductid. Every column came back NULL,
-- and the guard `WHERE j.waterproductid IS NOT NULL` -- there to skip blank
-- lines -- then dropped every row. Silently: no error, header committed.
--
-- Demonstrated on the live database:
--     json_to_recordset('[{"waterProductId":17}]') AS j(waterproductid integer)
--       -> NULL
--     json_to_recordset('[{"waterProductId":17}]') AS j("waterProductId" integer)
--       -> 17
--
-- Fix
-- ---
-- Quote the identifiers so they keep their camelCase and match the payload. The
-- read path already emits camelCase via json_build_object, so this also makes
-- the write path symmetrical with it: one JSON shape in both directions.
--
-- Idempotent: CREATE OR REPLACE only. No data change -- the dropped lines were
-- never written, so there is nothing to backfill; re-enter any affected draft.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.spwaterinternalusage_replaceitems(
    p_waterinternalusageid integer, p_farmid text, p_itemsjson text)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    DELETE FROM waterinternalusageitems WHERE waterinternalusageid = p_waterinternalusageid;

    IF p_itemsjson IS NULL OR btrim(p_itemsjson) IN ('', '[]') THEN
        RETURN;
    END IF;

    INSERT INTO waterinternalusageitems (
        waterinternalusageid, farmid, waterproductid, entryquantity, entryunit,
        unitsperentryunit, stockquantity, quantityperstaff,
        entryunitcost, unitcost, totalcost, itemnotes)
    SELECT p_waterinternalusageid,
           p_farmid,
           j."waterProductId",
           j."entryQuantity",
           COALESCE(NULLIF(btrim(j."entryUnit"), ''), COALESCE(p.baseunit, p.unit)),
           v.factor,
           ROUND(j."entryQuantity" * v.factor, 3),
           j."quantityPerStaff",
           COALESCE(j."entryUnitCost", 0),
           -- Derived per base unit, for valuation reporting. entryUnitCost is
           -- the figure the user stands behind (migration 213).
           ROUND(COALESCE(j."entryUnitCost", 0) / GREATEST(v.factor, 0.000001), 4),
           -- Multiplication only -- no divide-by-30 drift.
           ROUND(j."entryQuantity" * COALESCE(j."entryUnitCost", 0), 2),
           j."itemNotes"
    FROM   json_to_recordset(p_itemsjson::json) AS j(
               "waterProductId"   integer,
               "entryQuantity"    numeric,
               "entryUnit"        text,
               "quantityPerStaff" numeric,
               "entryUnitCost"    numeric,
               "itemNotes"        text)
    LEFT   JOIN waterproducts p ON p.waterproductid = j."waterProductId"
    CROSS  JOIN LATERAL (
        SELECT CASE
                 WHEN lower(COALESCE(j."entryUnit", '')) = 'bag'
                 THEN GREATEST(COALESCE(p.sachetsperbag, 30), 1)::numeric
                 ELSE 1::numeric
               END AS factor
    ) v
    WHERE  j."waterProductId" IS NOT NULL
      AND  COALESCE(j."entryQuantity", 0) > 0;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification: round-trip a realistic payload through the function and back
-- out again, then roll it back. Proves keys bind, the conversion applies and the
-- line total is costed -- the three things that were broken.
-- -----------------------------------------------------------------------------
BEGIN;

DO $verify$
DECLARE
    v_farm text;
    v_prod integer;
    v_id   integer;
    v_rows integer;
    r      record;
BEGIN
    SELECT p.farmid, p.waterproductid INTO v_farm, v_prod
    FROM   waterproducts p WHERE COALESCE(p.issachetproduct, FALSE) = TRUE LIMIT 1;

    IF v_farm IS NULL THEN
        RAISE NOTICE '214: no sachet product on file, skipping the round-trip check.';
        RETURN;
    END IF;

    INSERT INTO waterinternalusage (farmid, category, status, createdby)
    VALUES (v_farm, 'StaffWelfare', 'Draft', '214-verify')
    RETURNING waterinternalusageid INTO v_id;

    PERFORM public.spwaterinternalusage_replaceitems(
        v_id, v_farm,
        '[{"waterProductId":' || v_prod || ',"entryQuantity":5,"entryUnit":"Bag","entryUnitCost":9}]');

    SELECT count(*) INTO v_rows FROM waterinternalusageitems WHERE waterinternalusageid = v_id;
    IF v_rows <> 1 THEN
        RAISE EXCEPTION '214: expected 1 item row, got %. The key binding is still wrong.', v_rows;
    END IF;

    SELECT entryquantity, entryunit, unitsperentryunit, stockquantity, entryunitcost, unitcost, totalcost
    INTO   r
    FROM   waterinternalusageitems WHERE waterinternalusageid = v_id;

    RAISE NOTICE '214: 5 bags -> % sachets, cost % per bag = % total (% per sachet).',
        r.stockquantity, r.entryunitcost, r.totalcost, r.unitcost;

    IF r.stockquantity <= r.entryquantity THEN
        RAISE EXCEPTION '214: the bag->sachet conversion did not apply.';
    END IF;
    IF r.totalcost <= 0 THEN
        RAISE EXCEPTION '214: the line was not costed.';
    END IF;
END;
$verify$;

ROLLBACK;

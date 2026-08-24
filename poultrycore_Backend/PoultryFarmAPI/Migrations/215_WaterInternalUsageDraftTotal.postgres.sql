-- =============================================================================
-- 215_WaterInternalUsageDraftTotal.postgres.sql
--
-- Symptom
-- -------
-- A saved Internal Use draft showed its product and quantity but a cost of 0.00,
-- both in the list and on the record itself -- even though the line was costed
-- correctly:
--
--   waterinternalusageitems : entryunitcost 6.0000/bag, totalcost 60.00
--   waterinternalusage      : totalcostvalue 0.00
--
-- Cause
-- -----
-- waterinternalusage.totalcostvalue is the denormalised header figure the list
-- and the linked expense both read, and migration 212 only ever wrote it inside
-- spwaterinternalusage_post. A Draft therefore had no total until it was posted,
-- which is precisely backwards: the number exists to help someone decide whether
-- to post.
--
-- Fix
-- ---
-- Roll the header total up whenever the lines change, in
-- spwaterinternalusage_replaceitems -- the single place both insert and update
-- go through. Posting still recomputes it (it fills in any blank costs from the
-- weighted average first), so the two paths agree.
--
-- Also backfills any existing draft whose header total drifted from its lines.
--
-- Idempotent: CREATE OR REPLACE, and the backfill sets an absolute value derived
-- from the item rows rather than adding to what is there.
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

    IF p_itemsjson IS NOT NULL AND btrim(p_itemsjson) NOT IN ('', '[]') THEN
        INSERT INTO waterinternalusageitems (
            waterinternalusageid, farmid, waterproductid, entryquantity, entryunit,
            unitsperentryunit, stockquantity, quantityperstaff,
            entryunitcost, unitcost, totalcost, itemnotes)
        -- Identifiers stay quoted: json_to_recordset matches keys case-sensitively
        -- and the payload is camelCase (migration 214).
        SELECT p_waterinternalusageid,
               p_farmid,
               j."waterProductId",
               j."entryQuantity",
               COALESCE(NULLIF(btrim(j."entryUnit"), ''), COALESCE(p.baseunit, p.unit)),
               v.factor,
               ROUND(j."entryQuantity" * v.factor, 3),
               j."quantityPerStaff",
               COALESCE(j."entryUnitCost", 0),
               ROUND(COALESCE(j."entryUnitCost", 0) / GREATEST(v.factor, 0.000001), 4),
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
    END IF;

    -- Keep the header in step with its lines, draft included. Without this a
    -- draft reads 0.00 everywhere until it is posted.
    UPDATE waterinternalusage h
    SET    totalcostvalue = COALESCE((
               SELECT SUM(i.totalcost) FROM waterinternalusageitems i
               WHERE  i.waterinternalusageid = h.waterinternalusageid), 0),
           updatedat = (now() at time zone 'utc')
    WHERE  h.waterinternalusageid = p_waterinternalusageid;
END;
$function$;

-- Repair anything already saved with a stale header total.
UPDATE waterinternalusage h
SET    totalcostvalue = t.sum_total
FROM (
    SELECT i.waterinternalusageid AS id, COALESCE(SUM(i.totalcost), 0) AS sum_total
    FROM   waterinternalusageitems i GROUP BY i.waterinternalusageid
) t
WHERE h.waterinternalusageid = t.id
  AND h.totalcostvalue IS DISTINCT FROM t.sum_total;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification: no header should disagree with the sum of its lines.
-- -----------------------------------------------------------------------------
SELECT 'headers out of step with their lines' AS check,
       count(*)::text AS result
FROM   waterinternalusage h
WHERE  h.totalcostvalue IS DISTINCT FROM COALESCE((
           SELECT SUM(i.totalcost) FROM waterinternalusageitems i
           WHERE  i.waterinternalusageid = h.waterinternalusageid), 0);

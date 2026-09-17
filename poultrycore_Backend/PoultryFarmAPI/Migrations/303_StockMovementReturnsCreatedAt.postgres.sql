-- =============================================================================
-- 303_StockMovementReturnsCreatedAt.postgres.sql
--
-- Purpose
-- -------
-- The last list reader still missing a creation timestamp: poultry stock
-- movements. Completes the set started in 301 and continued in 302, so every
-- transaction table in the frontend can show a time beside the date.
--
-- NOTE ON VERIFICATION
-- ====================
-- `inventorytransactions` is EMPTY on dev (0 rows), so unlike 301 and 302 the
-- dry run cannot prove the new column is populated from real data -- there is no
-- data. What it can and does prove is that the function still compiles, still
-- returns the same (empty) shape, and keeps its grant. The column itself is
-- non-nullable in practice because every writer sets it, but that is an
-- inference here rather than a measurement, and worth knowing.
--
-- Source column is `createddate`; the output is normalised to `createdat` to
-- match 301 and 302, so the C# and the frontend know only one name.
--
-- Reproduced from the live definition; the only change is marked "303:".
--
-- Adding a column to RETURNS TABLE changes the return type, so this is a
-- DROP + CREATE, and the grant is reissued afterwards.
--
-- Order: after 302.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

DROP FUNCTION IF EXISTS public.spinventorytransaction_getbyitem(integer, text);

CREATE FUNCTION public.spinventorytransaction_getbyitem(p_itemid integer, p_farmid text)
 RETURNS TABLE(farmid text, userid text, transactionid integer, itemid integer,
               transactiondate timestamp without time zone, quantitychange numeric,
               transactiontype text, remarks text,
               createdat timestamp)          -- 303: added
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        t.farmid::text,
        t.userid::text,
        t.transactionid,
        t.itemid,
        t.transactiondate,
        t.quantitychange,
        t.transactiontype::text,
        t.remarks::text,
        t.createddate                         -- 303: added (table spells it createddate)
    FROM inventorytransactions t
    WHERE t.itemid = p_itemid
      AND t.farmid = p_farmid
    ORDER BY t.transactiondate DESC;
END
$function$;

DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.spinventorytransaction_getbyitem(integer, text) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'returns createdat' AS check,
       CASE WHEN pg_get_function_result(p.oid) ILIKE '%createdat%' THEN 'OK' ELSE 'MISSING' END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname='public' AND p.proname='spinventorytransaction_getbyitem'

UNION ALL
SELECT 'api role can execute',
       CASE WHEN has_function_privilege('poultryapp', p.oid, 'EXECUTE') THEN 'OK' ELSE 'NO GRANT' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname='public' AND p.proname='spinventorytransaction_getbyitem'

UNION ALL
-- It must still run. With no rows this proves compilation and shape, not data.
SELECT 'still executes (0 rows expected on dev)',
       COALESCE((SELECT COUNT(*)::text FROM public.spinventorytransaction_getbyitem(
                    COALESCE((SELECT itemid FROM inventoryitem LIMIT 1), 0),
                    COALESCE((SELECT farmid::text FROM farms LIMIT 1), ''))), 'FAILED');

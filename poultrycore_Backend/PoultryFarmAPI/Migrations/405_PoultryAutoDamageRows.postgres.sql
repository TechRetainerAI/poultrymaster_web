-- =============================================================================
-- 405_PoultryAutoDamageRows.postgres.sql
--
-- Purpose
-- -------
-- The Poultry Loss & Damage page lists damaged eggs from three sources next to
-- the manual loss records:
--   ProductionRecord  productionrecords.brokeneggs > 0
--   DriverReturn /    poultryproductionloss rows (driver returns, deliveries,
--   Delivery /        production batches) -- already one row per loss
--   ProductionBatch
--   EggSorting        poultrystocktransactions 'Egg Loss' rows (breakage / loss
--                     on an egg class), always negative
--
-- The page used to build these in the browser from ALL production records and
-- the WHOLE stock ledger. This reads only the damage rows, for a date range.
--
-- Read-only. The rows are derived, never stored: no table, no trigger, nothing
-- to keep in sync. Editing or deleting a source changes its row.
--
-- Dates are business dates: productionrecords.date, poultryproductionloss
-- .lossdate::date, and COALESCE(effectivedate, createddate::date) for ledger
-- rows (373 gave manual movements an effective date).
--
-- Deploy order: this migration, then the API, then the web app. The web app
-- falls back to building the rows itself when the endpoint is missing, so any
-- order works -- this one is just the fast path.
-- =============================================================================
BEGIN;

DROP FUNCTION IF EXISTS public.sppoultryloss_autodamage(text, date, date);

CREATE FUNCTION public.sppoultryloss_autodamage(p_farmid text, p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL)
RETURNS TABLE (
    sourcetype     text,
    sourceid       integer,
    lossdate       date,
    losstype       text,
    productname    text,
    quantity       numeric,
    estimatedvalue numeric,
    details        text,
    flockname      text,
    brokeneggs     integer,
    disposed       integer
)
LANGUAGE sql STABLE AS $function$
    -- 1. Broken eggs on production records. disposed uses the 390 rule; a
    --    record from before the byproduct cutover (381) counts as all disposed.
    SELECT 'ProductionRecord'::text,
           pr.id,
           pr.date::date,
           'Damage'::text,
           'Broken eggs'::text,
           pr.brokeneggs::numeric,
           NULL::numeric,
           NULL::text,
           f.name::text,
           pr.brokeneggs::integer,
           public.fnpoultry_brokeneggsdisposed(
               pr.brokeneggs::integer, pr.brokeneggsdisposed, pr.brokeneggdisposition,
               (s.cutoverat IS NOT NULL AND pr.createdat < s.cutoverat))
    FROM   productionrecords pr
    LEFT   JOIN flock f ON f.flockid = pr.flockid
    LEFT   JOIN poultrybyproductsettings s ON s.farmid = pr.farmid
    WHERE  pr.farmid = p_farmid
      AND  COALESCE(pr.brokeneggs, 0) > 0
      AND  (p_fromdate IS NULL OR pr.date::date >= p_fromdate)
      AND  (p_todate   IS NULL OR pr.date::date <= p_todate)

    UNION ALL

    -- 2. Driver-return, delivery and production-batch losses.
    SELECT CASE pl.sourcetype WHEN 'PoultryDriverReturn' THEN 'DriverReturn'
                              WHEN 'PoultryDelivery'     THEN 'Delivery'
                              ELSE 'ProductionBatch' END,
           pl.sourceid,
           pl.lossdate::date,
           'Damage'::text,
           COALESCE(p.name::text, 'Eggs'),
           pl.quantitylost::numeric,
           pl.estimatedvalue::numeric,
           pl.reason::text,
           NULL::text,
           NULL::integer,
           NULL::integer
    FROM   poultryproductionloss pl
    LEFT   JOIN poultryproducts p ON p.poultryproductid = pl.poultryproductid AND p.farmid = pl.farmid
    WHERE  pl.farmid = p_farmid
      AND  COALESCE(pl.quantitylost, 0) > 0
      AND  (p_fromdate IS NULL OR pl.lossdate::date >= p_fromdate)
      AND  (p_todate   IS NULL OR pl.lossdate::date <= p_todate)

    UNION ALL

    -- 3. Egg-class breakage / loss from the Egg Sorting workspace.
    SELECT 'EggSorting'::text,
           t.poultrystocktransactionid,
           COALESCE(t.effectivedate, t.createddate::date),
           'Damage'::text,
           COALESCE(p.name::text || ' eggs', 'Eggs'),
           abs(t.quantity)::numeric,
           NULL::numeric,
           COALESCE(t.note::text, t.reason::text),
           NULL::text,
           NULL::integer,
           NULL::integer
    FROM   poultrystocktransactions t
    LEFT   JOIN poultryproducts p ON p.poultryproductid = t.poultryproductid AND p.farmid = t.farmid
    WHERE  t.farmid = p_farmid
      AND  t.txntype = 'Egg Loss'
      AND  t.quantity < 0
      AND  (p_fromdate IS NULL OR COALESCE(t.effectivedate, t.createddate::date) >= p_fromdate)
      AND  (p_todate   IS NULL OR COALESCE(t.effectivedate, t.createddate::date) <= p_todate)

    ORDER  BY 3 DESC, 1, 2 DESC;
$function$;

-- Smoke test: the function must plan and run against the live tables.
DO $$
BEGIN
    PERFORM * FROM public.sppoultryloss_autodamage('__no_such_farm__', current_date - 30, current_date);
END $$;

COMMIT;

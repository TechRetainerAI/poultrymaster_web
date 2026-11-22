-- =============================================================================
-- 464  Water: Inventory Restock Forecast (days of supply)
--                                            (Water port of poultry 337)
-- =============================================================================
--
-- "Preforms: 1,800 pcs, using about 620 a day, about 2.9 days left --
-- estimated to run out on the 2nd."
--
-- CONSUMPTION = a live (not reversed) waterrawmaterialusage row, dated to its
-- production batch's production date (else the usage's own date). Purchases
-- (stock in), adjustments (write-offs, corrections, receipt reversals) and
-- reversed usage are not consumption.
--
-- AVERAGE over the LAST N COMPLETE business days, ending YESTERDAY in the
-- company's timezone; days without usage count as zero. An item first stocked
-- inside the window is averaged over the days it had stock; fewer than
-- minhistorydays gives "Not enough history", never a wild figure.
-- Units: usage and stock are both in the item's own unit; the purchase-unit
-- equivalent (bags, rolls ...) comes from the latest lot.
--
-- STATES (never Infinity / NaN): Negative, OutOfStock, InsufficientHistory,
-- NoRecentUsage, Critical / Warning / Healthy against the company's
-- thresholds (defaults 3 and 7 days). Estimated stock-out = today +
-- floor(days of supply), always labelled an estimate.
--
-- Same output as sppoultrystocksupply (expecteddailyusage is always NULL:
-- Water has no per-unit usage rates). DERIVED, NOT STORED: no alert or
-- purchase is ever written. Read-only functions + a settings table.
-- Idempotent.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.waterstocksupplysettings (
    farmid          text PRIMARY KEY,
    lookbackdays    integer      NOT NULL DEFAULT 7,
    criticaldays    numeric(8,2) NOT NULL DEFAULT 3,
    warningdays     numeric(8,2) NOT NULL DEFAULT 7,
    minhistorydays  integer      NOT NULL DEFAULT 3,
    updatedby       text,
    updatedatutc    timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_waterstocksupply_numbers CHECK (
        lookbackdays BETWEEN 1 AND 90 AND minhistorydays BETWEEN 1 AND 90
        AND criticaldays >= 0 AND warningdays > criticaldays)
);

DROP FUNCTION IF EXISTS public.spwaterstocksupplysettings_get(text);
CREATE FUNCTION public.spwaterstocksupplysettings_get(p_farmid text)
RETURNS TABLE(lookbackdays integer, criticaldays numeric, warningdays numeric, minhistorydays integer,
              iscustomised boolean, updatedby text, updatedatutc timestamptz)
LANGUAGE sql STABLE AS $function$
    SELECT COALESCE(s.lookbackdays, 7), COALESCE(s.criticaldays, 3), COALESCE(s.warningdays, 7),
           COALESCE(s.minhistorydays, 3), s.farmid IS NOT NULL, s.updatedby, s.updatedatutc
    FROM (SELECT 1) one
    LEFT JOIN public.waterstocksupplysettings s ON s.farmid = p_farmid;
$function$;

CREATE OR REPLACE FUNCTION public.spwaterstocksupplysettings_set(
    p_farmid text, p_lookbackdays integer, p_criticaldays numeric, p_warningdays numeric,
    p_minhistorydays integer, p_updatedby text)
RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN RAISE EXCEPTION 'Company ID is required.'; END IF;
    IF p_warningdays <= p_criticaldays THEN
        RAISE EXCEPTION 'The warning level must be more days than the critical level.';
    END IF;
    INSERT INTO waterstocksupplysettings AS t (farmid, lookbackdays, criticaldays, warningdays, minhistorydays, updatedby, updatedatutc)
    VALUES (p_farmid, p_lookbackdays, p_criticaldays, p_warningdays, p_minhistorydays, p_updatedby, now())
    ON CONFLICT (farmid) DO UPDATE SET
        lookbackdays = EXCLUDED.lookbackdays, criticaldays = EXCLUDED.criticaldays,
        warningdays = EXCLUDED.warningdays, minhistorydays = EXCLUDED.minhistorydays,
        updatedby = EXCLUDED.updatedby, updatedatutc = now();
END;
$function$;

-- THE definition of Water raw-material consumption, per item, per business day.
DROP FUNCTION IF EXISTS public.fnwaterrawmaterial_dailyconsumption(text, date, date);
CREATE FUNCTION public.fnwaterrawmaterial_dailyconsumption(p_farmid text, p_from date, p_to date)
RETURNS TABLE(waterrawmaterialitemid integer, usagedate date, quantity numeric)
LANGUAGE sql STABLE AS $function$
    SELECT u.waterrawmaterialitemid,
           COALESCE(pb.productiondate, u.useddate::date) AS usagedate,
           sum(u.quantityused)
    FROM   waterrawmaterialusage u
    LEFT   JOIN waterproductionbatches pb
           ON pb.waterproductionbatchid = u.waterproductionbatchid AND pb.farmid = u.farmid
    WHERE  u.farmid = p_farmid
      AND  NOT COALESCE(u.isreversed, FALSE)
      AND  COALESCE(u.quantityused, 0) > 0
      AND  COALESCE(pb.productiondate, u.useddate::date) BETWEEN p_from AND p_to
    GROUP  BY u.waterrawmaterialitemid, COALESCE(pb.productiondate, u.useddate::date);
$function$;

DROP FUNCTION IF EXISTS public.spwaterstocksupply(text, integer, timestamptz);
CREATE FUNCTION public.spwaterstocksupply(
    p_farmid text, p_lookbackdays integer DEFAULT NULL, p_asof timestamptz DEFAULT now())
RETURNS TABLE(
    waterrawmaterialitemid integer, itemname text, category text, unitofmeasure text,
    purchaseunitofmeasure text, unitsperpurchaseunit numeric, currentquantity numeric,
    minimumstockalert numeric, belowreorder boolean,
    businessdate date, windowfrom date, windowto date, lookbackdays integer, windowdays integer,
    consumedqty numeric, usagedays integer, avgdailyusage numeric, daysofsupply numeric,
    estimatedstockout date, status text, severityrank integer,
    criticaldays numeric, warningdays numeric, expecteddailyusage numeric)
LANGUAGE plpgsql STABLE AS $function$
#variable_conflict use_column
DECLARE
    v_today date := (p_asof AT TIME ZONE public.fncompany_timezone(p_farmid))::date;
    s       record;
    v_look  integer;
    v_from  date;
    v_to    date;
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN RAISE EXCEPTION 'Company ID is required.'; END IF;
    SELECT * INTO s FROM public.spwaterstocksupplysettings_get(p_farmid);
    v_look := LEAST(GREATEST(COALESCE(p_lookbackdays, s.lookbackdays), 1), 90);
    v_to   := v_today - 1;
    v_from := v_today - v_look;

    RETURN QUERY
    WITH items AS (
        SELECT i.waterrawmaterialitemid AS id, i.itemname::text AS name, i.category::text AS cat,
               i.unitofmeasure::text AS unit, i.purchaseunitofmeasure::text AS punit,
               COALESCE(i.currentquantity, 0) AS qty, i.minimumstockalert AS minstock,
               COALESCE((SELECT min(p.purchasedate)::date FROM waterrawmaterialpurchases p
                         WHERE p.farmid = p_farmid AND p.waterrawmaterialitemid = i.waterrawmaterialitemid
                           AND COALESCE(p.lotsource, '') <> 'ManualDeferredCost'),
                        i.createdat::date, v_today) AS firststock,
               (SELECT NULLIF(p.productionunitsperpurchaseunit, 0) FROM waterrawmaterialpurchases p
                WHERE p.farmid = p_farmid AND p.waterrawmaterialitemid = i.waterrawmaterialitemid
                  AND COALESCE(p.lotsource, '') <> 'ManualDeferredCost'
                ORDER BY p.purchasedate DESC, p.waterrawmaterialpurchaseid DESC LIMIT 1) AS perpunit
        FROM   waterrawmaterialitems i
        WHERE  i.farmid = p_farmid AND COALESCE(i.isactive, TRUE)
    ),
    used AS (
        SELECT c.waterrawmaterialitemid AS id, sum(c.quantity) AS qty, count(DISTINCT c.usagedate)::int AS days
        FROM   public.fnwaterrawmaterial_dailyconsumption(p_farmid, v_from, v_to) c
        GROUP  BY c.waterrawmaterialitemid
    ),
    calc AS (
        SELECT it.*,
               GREATEST(LEAST(v_look, v_today - it.firststock), 0) AS wdays,
               COALESCE(u.qty, 0) AS consumed,
               COALESCE(u.days, 0) AS udays
        FROM items it LEFT JOIN used u ON u.id = it.id
    ),
    rated AS (
        SELECT c.*,
               CASE WHEN c.consumed > 0 AND c.wdays >= s.minhistorydays THEN c.consumed / c.wdays END AS avgd
        FROM calc c
    ),
    classified AS (
        SELECT r.*,
               CASE
                   WHEN r.qty < 0                       THEN 'Negative'
                   WHEN r.wdays < s.minhistorydays      THEN 'InsufficientHistory'
                   WHEN r.consumed = 0                  THEN 'NoRecentUsage'
                   WHEN r.qty = 0                       THEN 'OutOfStock'
                   WHEN r.qty / r.avgd < s.criticaldays THEN 'Critical'
                   WHEN r.qty / r.avgd < s.warningdays  THEN 'Warning'
                   ELSE 'Healthy'
               END AS st,
               CASE
                   WHEN r.qty < 0 THEN NULL
                   WHEN r.qty = 0 AND r.avgd IS NOT NULL THEN 0::numeric
                   WHEN r.avgd IS NOT NULL THEN round(r.qty / r.avgd, 1)
               END AS dos
        FROM rated r
    )
    SELECT c.id, c.name, c.cat, c.unit, c.punit, c.perpunit, c.qty, c.minstock,
           COALESCE(c.minstock, 0) > 0 AND c.qty <= c.minstock,
           v_today, v_from, v_to, v_look, c.wdays,
           round(c.consumed, 3), c.udays, round(c.avgd, 3), c.dos,
           CASE WHEN c.dos IS NOT NULL THEN v_today + floor(c.dos)::int END,
           c.st,
           CASE c.st WHEN 'Negative' THEN 0 WHEN 'OutOfStock' THEN 1 WHEN 'Critical' THEN 2 WHEN 'Warning' THEN 3
                     WHEN 'Healthy' THEN 4 WHEN 'InsufficientHistory' THEN 5 ELSE 6 END,
           s.criticaldays, s.warningdays,
           NULL::numeric
    FROM classified c
    ORDER BY 21, c.dos NULLS LAST, c.name;
END;
$function$;

COMMIT;

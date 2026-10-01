-- =============================================================================
-- 337_PoultryDaysOfSupply.postgres.sql
--
-- Purpose
-- -------
-- Turn "Layer Mash is low" into "Layer Mash: 1,800 kg, using about 620 kg a
-- day, about 2.9 days left -- estimated to run out Oct 2".
--
-- WHAT COUNTS AS CONSUMPTION (and what does not)
-- ==============================================
-- Consumption is a live (isreversed = FALSE) poultryrawmaterialusage row that
-- is LINKED to either
--   * a production record  -- feed / medication given to a flock, dated to the
--                             record's date (the day the birds used it), or
--   * a feed production batch -- ingredients milled into finished feed, dated
--                             to the batch's production date.
-- Everything else is excluded by construction:
--   * purchases             -- stock IN, not usage (poultryrawmaterialpurchases)
--   * reversals             -- isreversed rows, and the "Reversal of produced
--                              feed" drain row, which is linked to neither
--   * stock adjustments     -- poultryrawmaterialadjustments: reversals put back,
--                              and manual 'Decrease' write-offs are wastage /
--                              corrections, not birds eating
-- An edited production record's usage is rewritten by the engine, so only its
-- current lines are ever counted -- never an old and a new version.
--
-- HOW THE AVERAGE IS TAKEN
-- ========================
-- Over the LAST N COMPLETE business days, ending YESTERDAY in the company's
-- timezone (today is still in progress and would drag the average down).
-- N defaults to 7 -- the same window Daily Closing's low-feed check and the
-- feed-distribution recent average already use -- and is configurable
-- (poultrystocksupplysettings.lookbackdays, or per call).
--
-- Days without usage count as zero (a real average, not "average of busy
-- days"). A product whose FIRST stock arrived inside the window is averaged
-- over the days it has actually had stock, so a new product is not diluted by
-- days before it existed; if that is fewer than minhistorydays (default 3), no
-- figure is given ("Not enough history") rather than a wild one.
--
-- Units: consumption and current stock are both in the item's own production
-- unit (kg, litre, ...), so days of supply needs no conversion. The purchase-
-- unit equivalent (e.g. bags) is returned alongside for the restock prompt,
-- using the latest lot's units-per-purchase-unit.
--
-- STATES (deterministic; never Infinity / NaN)
-- ============================================
--   Negative            current stock below zero (a correction is owed; no
--                       days figure and no stock-out date)
--   OutOfStock          zero stock and recent usage
--   InsufficientHistory fewer than minhistorydays with stock
--   NoRecentUsage       nothing used in the window -- no days-of-supply figure
--   Critical / Warning / Healthy -- days of supply against the farm's
--                       thresholds (criticaldays default 3, warningdays 7)
-- Estimated stock-out = company today + floor(days of supply), labelled as an
-- estimate everywhere it is shown.
--
-- Optional (Prompt 8): for a feed with a saved rate (poultryfeedrates, 335),
-- expecteddailyusage = active flocks' current birds x the rate, for comparison
-- with actual usage. Null when no rate is saved -- never a default.
--
-- DERIVED, NOT STORED: nothing here writes an alert or a notification, so a
-- page load can never spam anyone. Persisting alerts would be a separate
-- decision with its own de-duplication.
--
-- Depends on 298 (company time) and 335 (feed rates). Idempotent.
-- EFFECT ON TODAY'S NUMBERS: none (read-only functions + a settings table).
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS public.poultrystocksupplysettings (
    farmid          text PRIMARY KEY,
    lookbackdays    integer      NOT NULL DEFAULT 7,
    criticaldays    numeric(8,2) NOT NULL DEFAULT 3,
    warningdays     numeric(8,2) NOT NULL DEFAULT 7,
    minhistorydays  integer      NOT NULL DEFAULT 3,
    updatedby       text,
    updatedatutc    timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_poultrystocksupply_numbers CHECK (
        lookbackdays BETWEEN 1 AND 90 AND minhistorydays BETWEEN 1 AND 90
        AND criticaldays >= 0 AND warningdays > criticaldays)
);

DROP FUNCTION IF EXISTS public.sppoultrystocksupplysettings_get(text);
CREATE FUNCTION public.sppoultrystocksupplysettings_get(p_farmid text)
RETURNS TABLE(lookbackdays integer, criticaldays numeric, warningdays numeric, minhistorydays integer,
              iscustomised boolean, updatedby text, updatedatutc timestamptz)
LANGUAGE sql
STABLE
AS $function$
    SELECT COALESCE(s.lookbackdays, 7), COALESCE(s.criticaldays, 3), COALESCE(s.warningdays, 7),
           COALESCE(s.minhistorydays, 3), s.farmid IS NOT NULL, s.updatedby, s.updatedatutc
    FROM (SELECT 1) one
    LEFT JOIN public.poultrystocksupplysettings s ON s.farmid = p_farmid;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrystocksupplysettings_set(
    p_farmid text, p_lookbackdays integer, p_criticaldays numeric, p_warningdays numeric,
    p_minhistorydays integer, p_updatedby text)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN RAISE EXCEPTION 'Company ID is required.'; END IF;
    IF p_warningdays <= p_criticaldays THEN
        RAISE EXCEPTION 'The warning level must be more days than the critical level.';
    END IF;
    INSERT INTO poultrystocksupplysettings AS t (farmid, lookbackdays, criticaldays, warningdays, minhistorydays, updatedby, updatedatutc)
    VALUES (p_farmid, p_lookbackdays, p_criticaldays, p_warningdays, p_minhistorydays, p_updatedby, now())
    ON CONFLICT (farmid) DO UPDATE SET
        lookbackdays = EXCLUDED.lookbackdays, criticaldays = EXCLUDED.criticaldays,
        warningdays = EXCLUDED.warningdays, minhistorydays = EXCLUDED.minhistorydays,
        updatedby = EXCLUDED.updatedby, updatedatutc = now();
END;
$function$;

-- -----------------------------------------------------------------------------
-- THE definition of raw-material consumption, per item, per business day.
-- One place, so anything that needs "how much was used" agrees.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fnpoultryrawmaterial_dailyconsumption(text, date, date);
CREATE FUNCTION public.fnpoultryrawmaterial_dailyconsumption(p_farmid text, p_from date, p_to date)
RETURNS TABLE(poultryrawmaterialitemid integer, usagedate date, quantity numeric)
LANGUAGE sql
STABLE
AS $function$
    SELECT u.poultryrawmaterialitemid,
           COALESCE(pr.date, fb.productiondate::date) AS usagedate,
           sum(u.quantityused)
    FROM   poultryrawmaterialusage u
    LEFT   JOIN productionrecords pr
           ON pr.id = u.productionrecordid AND pr.farmid = u.farmid
    LEFT   JOIN poultryfeedproductionbatches fb
           ON fb.poultryfeedproductionbatchid = u.poultryfeedproductionbatchid AND fb.farmid = u.farmid
    WHERE  u.farmid = p_farmid
      AND  NOT COALESCE(u.isreversed, FALSE)
      AND  (pr.id IS NOT NULL OR fb.poultryfeedproductionbatchid IS NOT NULL)
      AND  COALESCE(pr.date, fb.productiondate::date) BETWEEN p_from AND p_to
    GROUP  BY u.poultryrawmaterialitemid, COALESCE(pr.date, fb.productiondate::date);
$function$;

-- -----------------------------------------------------------------------------
-- Days of supply for every active raw-material item of a company.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultrystocksupply(text, integer, timestamptz);
CREATE FUNCTION public.sppoultrystocksupply(
    p_farmid       text,
    p_lookbackdays integer     DEFAULT NULL,
    p_asof         timestamptz DEFAULT now())
RETURNS TABLE(
    poultryrawmaterialitemid integer, itemname text, category text, unitofmeasure text,
    purchaseunitofmeasure text, unitsperpurchaseunit numeric, currentquantity numeric,
    minimumstockalert numeric, belowreorder boolean,
    businessdate date, windowfrom date, windowto date, lookbackdays integer, windowdays integer,
    consumedqty numeric, usagedays integer, avgdailyusage numeric, daysofsupply numeric,
    estimatedstockout date, status text, severityrank integer,
    criticaldays numeric, warningdays numeric, expecteddailyusage numeric)
LANGUAGE plpgsql
STABLE
AS $function$
#variable_conflict use_column
DECLARE
    v_today date := (p_asof AT TIME ZONE public.fncompany_timezone(p_farmid))::date;
    s       record;
    v_look  integer;
    v_from  date;
    v_to    date;
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN RAISE EXCEPTION 'Company ID is required.'; END IF;
    SELECT * INTO s FROM public.sppoultrystocksupplysettings_get(p_farmid);
    v_look := LEAST(GREATEST(COALESCE(p_lookbackdays, s.lookbackdays), 1), 90);
    v_to   := v_today - 1;            -- complete days only
    v_from := v_today - v_look;

    RETURN QUERY
    WITH items AS (
        SELECT i.poultryrawmaterialitemid AS id, i.itemname::text AS name, i.category::text AS cat,
               i.unitofmeasure::text AS unit, i.purchaseunitofmeasure::text AS punit,
               COALESCE(i.currentquantity, 0) AS qty, i.minimumstockalert AS minstock,
               -- The day the item first had stock (its first purchase / produced
               -- lot); an item never stocked counts from its creation.
               COALESCE((SELECT min(p.purchasedate)::date FROM poultryrawmaterialpurchases p
                         WHERE p.farmid = p_farmid AND p.poultryrawmaterialitemid = i.poultryrawmaterialitemid),
                        i.createdat::date, v_today) AS firststock,
               (SELECT NULLIF(p.productionunitsperpurchaseunit, 0) FROM poultryrawmaterialpurchases p
                WHERE p.farmid = p_farmid AND p.poultryrawmaterialitemid = i.poultryrawmaterialitemid
                ORDER BY p.purchasedate DESC, p.poultryrawmaterialpurchaseid DESC LIMIT 1) AS perpunit
        FROM   poultryrawmaterialitems i
        WHERE  i.farmid = p_farmid AND COALESCE(i.isactive, TRUE)
    ),
    used AS (
        SELECT c.poultryrawmaterialitemid AS id, sum(c.quantity) AS qty, count(DISTINCT c.usagedate)::int AS days
        FROM   public.fnpoultryrawmaterial_dailyconsumption(p_farmid, v_from, v_to) c
        GROUP  BY c.poultryrawmaterialitemid
    ),
    birds AS (
        -- Current birds of every live flock: last record's birds left, else placed.
        SELECT COALESCE(sum(COALESCE(
                   (SELECT pr.noofbirdsleft FROM productionrecords pr
                    WHERE pr.farmid = p_farmid AND pr.flockid = f.flockid
                    ORDER BY pr.date DESC, pr.id DESC LIMIT 1), f.quantity)), 0) AS n
        FROM flock f
        WHERE f.farmid = p_farmid AND f.active AND f.hasarrived AND NOT COALESCE(f.isdeleted, FALSE)
    ),
    calc AS (
        SELECT it.*,
               -- Complete days in the window the item actually had stock for.
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
               -- Negative stock has no days figure: it is not "0 days left", it is
               -- a count that is wrong and owes a correction.
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
           (SELECT round(b.n * fr.gramsperbirdperday / 1000.0, 3)
            FROM poultryfeedrates fr, birds b
            WHERE fr.farmid = p_farmid AND fr.poultryrawmaterialitemid = c.id)
    FROM classified c
    ORDER BY 21, c.dos NULLS LAST, c.name;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification (rolled back by the sentinel).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    a   text := '__337_selftest_a__';
    b   text := '__337_selftest_b__';
    -- Company A is in Pacific/Auckland. 2026-03-10 10:00 UTC = 23:00 on the
    -- 10th there (today = the 10th); 11:30 UTC is already the 11th.
    t_day  timestamptz := '2026-03-10 10:00:00+00';
    t_next timestamptz := '2026-03-10 11:30:00+00';
    d   date := date '2026-03-10';
    who text := '__337__';
    fl integer; flb integer;
    i_norm integer; i_zero integer; i_new integer; i_neg integer; i_out integer; i_bag integer; i_ing integer; i_b integer;
    fp integer;
    r record;
    k integer;
    rec integer;
BEGIN
    BEGIN
        INSERT INTO farms (id, farmid, name, email, type, timezoneid)
        VALUES (a, a, 'Selftest A', 'a@selftest.invalid', 'Poultry', 'Pacific/Auckland'),
               (b, b, 'Selftest B', 'b@selftest.invalid', 'Poultry', 'Pacific/Auckland');
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'F', d - 60, 'Brown', 1840, TRUE, TRUE, -337, timestamp '2026-01-01') RETURNING flockid INTO fl;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, b, 'FB', d - 60, 'Brown', 100, TRUE, TRUE, -337, timestamp '2026-01-01') RETURNING flockid INTO flb;

        -- Items. Every "old" item had its first stock 40 days ago.
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, currentquantity, isactive, minimumstockalert)
        VALUES (a, 'Layer Mash', 'FinishedFeed', 'kg', 'Bag', 1800, TRUE, 2000) RETURNING poultryrawmaterialitemid INTO i_norm;
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
        VALUES (a, 'Idle Grit', 'Supplement', 'kg', 100, TRUE) RETURNING poultryrawmaterialitemid INTO i_zero;
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
        VALUES (a, 'New Starter', 'FinishedFeed', 'kg', 500, TRUE) RETURNING poultryrawmaterialitemid INTO i_new;
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
        VALUES (a, 'Broken Count', 'Medication', 'litre', -5, TRUE) RETURNING poultryrawmaterialitemid INTO i_neg;
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
        VALUES (a, 'Empty Grower', 'FinishedFeed', 'kg', 0, TRUE) RETURNING poultryrawmaterialitemid INTO i_out;
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, currentquantity, isactive)
        VALUES (a, 'Bagged Mash', 'FinishedFeed', 'kg', 'Bag', 500, TRUE) RETURNING poultryrawmaterialitemid INTO i_bag;
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
        VALUES (a, 'Maize', 'FeedIngredient', 'kg', 1000, TRUE) RETURNING poultryrawmaterialitemid INTO i_ing;
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
        VALUES (b, 'Layer Mash', 'FinishedFeed', 'kg', 1800, TRUE) RETURNING poultryrawmaterialitemid INTO i_b;

        INSERT INTO poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
            productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod, deferredtotalcost, deferredremainingcost)
        SELECT a, x, d - 40, 1, 1, 1, 1, 0, 'EXPENSE_WHEN_PURCHASED', 0, 0
        FROM unnest(ARRAY[i_norm, i_zero, i_neg, i_out, i_ing]) x;
        -- Bagged Mash: bought in 50 kg bags. New Starter: first stock only yesterday.
        INSERT INTO poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
            productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod, deferredtotalcost, deferredremainingcost)
        VALUES (a, i_bag, d - 40, 10, 50, 500, 50, 10, 'EXPENSE_WHEN_PURCHASED', 0, 0),
               (a, i_new, d - 1, 500, 1, 500, 1, 500, 'EXPENSE_WHEN_PURCHASED', 0, 0),
               -- A purchase INSIDE the window must not read as usage.
               (a, i_norm, d - 2, 999, 1, 999, 1, 999, 'EXPENSE_WHEN_PURCHASED', 0, 0),
               (b, i_b, d - 40, 1, 1, 1, 1, 0, 'EXPENSE_WHEN_PURCHASED', 0, 0);

        -- One production record per day d-7 .. d-1 (the 7-day window) plus d
        -- itself (today: must NOT count yet).
        FOR k IN 0..7 LOOP
            INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
                noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
            VALUES (a, who, who, 10, 70, d - k, 1840, 0, 1840, 0, 1, 1, 1, 3, fl, 'ManualSingleFlock', now())
            RETURNING id INTO rec;
            -- Layer Mash 620 kg every day, including today.
            INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, productionrecordid, quantityused, isreversed)
            VALUES (a, i_norm, rec, 620, FALSE);
            -- Bagged Mash 25 kg a day in the window.
            IF k >= 1 THEN
                INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, productionrecordid, quantityused, isreversed)
                VALUES (a, i_bag, rec, 25, FALSE);
            END IF;
            -- A reversed draw of Layer Mash on the same day: must be ignored.
            INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, productionrecordid, quantityused, isreversed)
            VALUES (a, i_norm, rec, 10000, TRUE);
            IF k = 3 THEN
                INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, productionrecordid, quantityused, isreversed)
                VALUES (a, i_out, rec, 70, FALSE), (a, i_neg, rec, 2, FALSE);
            END IF;
        END LOOP;
        -- An unlinked usage row (like the "Reversal of produced feed" drain): ignored.
        INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, quantityused, isreversed, useddate)
        VALUES (a, i_norm, 50000, FALSE, d - 2);
        -- A manual write-off adjustment: not consumption.
        INSERT INTO poultryrawmaterialadjustments (farmid, poultryrawmaterialitemid, adjusteddate, quantity, movementtype, note, createdby)
        VALUES (a, i_norm, d - 2, -300, 'Decrease', 'spoiled', who);
        -- Maize milled into feed on d-4 (feed production counts as consumption).
        INSERT INTO poultryfeedproductionbatches (farmid, batchnumber, finishedfeeditemid, productiondate, status)
        VALUES (a, '337-FP', i_norm, d - 4, 'Posted') RETURNING poultryfeedproductionbatchid INTO fp;
        INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, poultryfeedproductionbatchid, quantityused, isreversed)
        VALUES (a, i_ing, fp, 700, FALSE);
        -- Company B used its Layer Mash too, heavily.
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (b, who, who, 10, 70, d - 1, 100, 0, 100, 0, 1, 1, 1, 3, flb, 'ManualSingleFlock', now()) RETURNING id INTO rec;
        INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, productionrecordid, quantityused, isreversed)
        VALUES (b, i_b, rec, 9000, FALSE);

        -- ---- Normal consumption: 620 kg/day, 1,800 kg -> 2.9 days, Critical --
        SELECT * INTO r FROM public.sppoultrystocksupply(a, NULL, t_day) x WHERE x.poultryrawmaterialitemid = i_norm;
        IF r.consumedqty <> 4340 OR r.avgdailyusage <> 620 OR r.daysofsupply <> 2.9 OR r.status <> 'Critical'
           OR r.estimatedstockout <> d + 2 OR r.windowfrom <> d - 7 OR r.windowto <> d - 1 OR r.usagedays <> 7
           OR NOT r.belowreorder THEN
            RAISE EXCEPTION '337: Layer Mash wrong (purchases, reversals, write-offs, unlinked rows and today must all be excluded): %', r;
        END IF;

        -- ---- Zero consumption --------------------------------------------------
        SELECT * INTO r FROM public.sppoultrystocksupply(a, NULL, t_day) x WHERE x.poultryrawmaterialitemid = i_zero;
        IF r.status <> 'NoRecentUsage' OR r.daysofsupply IS NOT NULL OR r.avgdailyusage IS NOT NULL OR r.estimatedstockout IS NOT NULL THEN
            RAISE EXCEPTION '337: zero consumption should give no figure: %', r;
        END IF;

        -- ---- Insufficient history (new product) -------------------------------
        SELECT * INTO r FROM public.sppoultrystocksupply(a, NULL, t_day) x WHERE x.poultryrawmaterialitemid = i_new;
        IF r.status <> 'InsufficientHistory' OR r.daysofsupply IS NOT NULL OR r.windowdays <> 1 THEN
            RAISE EXCEPTION '337: a product stocked yesterday should be InsufficientHistory: %', r;
        END IF;

        -- ---- Negative stock ---------------------------------------------------
        SELECT * INTO r FROM public.sppoultrystocksupply(a, NULL, t_day) x WHERE x.poultryrawmaterialitemid = i_neg;
        IF r.status <> 'Negative' OR r.daysofsupply IS NOT NULL OR r.estimatedstockout IS NOT NULL THEN
            RAISE EXCEPTION '337: negative stock wrong: %', r;
        END IF;

        -- ---- Out of stock with recent usage -----------------------------------
        SELECT * INTO r FROM public.sppoultrystocksupply(a, NULL, t_day) x WHERE x.poultryrawmaterialitemid = i_out;
        IF r.status <> 'OutOfStock' OR r.daysofsupply <> 0 OR r.estimatedstockout <> d THEN
            RAISE EXCEPTION '337: out of stock wrong: %', r;
        END IF;

        -- ---- Units: kg usage against kg stock; bags for the restock prompt ----
        SELECT * INTO r FROM public.sppoultrystocksupply(a, NULL, t_day) x WHERE x.poultryrawmaterialitemid = i_bag;
        IF r.avgdailyusage <> 25 OR r.daysofsupply <> 20 OR r.status <> 'Healthy'
           OR r.unitsperpurchaseunit <> 50 OR r.purchaseunitofmeasure <> 'Bag' THEN
            RAISE EXCEPTION '337: bagged item wrong (500 kg / 25 kg a day = 20 days; 50 kg per bag): %', r;
        END IF;

        -- ---- Feed production draws count, on the batch's date -----------------
        SELECT * INTO r FROM public.sppoultrystocksupply(a, NULL, t_day) x WHERE x.poultryrawmaterialitemid = i_ing;
        IF r.consumedqty <> 700 OR r.avgdailyusage <> 100 OR r.daysofsupply <> 10 THEN
            RAISE EXCEPTION '337: maize milled into feed should count (700 kg / 7 days): %', r;
        END IF;

        -- ---- Lookback: 14 days halves the average (only 7 days of usage) ------
        SELECT * INTO r FROM public.sppoultrystocksupply(a, 14, t_day) x WHERE x.poultryrawmaterialitemid = i_norm;
        IF r.avgdailyusage <> 310 OR r.daysofsupply <> 5.8 OR r.status <> 'Warning' OR r.lookbackdays <> 14 THEN
            RAISE EXCEPTION '337: 14-day lookback wrong: %', r;
        END IF;

        -- ---- Timezone: at 11:30 UTC it is the 11th in Auckland; the 10th is now
        --      a complete day and joins the window ---------------------------
        SELECT * INTO r FROM public.sppoultrystocksupply(a, NULL, t_next) x WHERE x.poultryrawmaterialitemid = i_norm;
        IF r.businessdate <> d + 1 OR r.windowto <> d OR r.consumedqty <> 4340 OR r.windowfrom <> d - 6 THEN
            RAISE EXCEPTION '337: business-date window wrong at the day boundary: %', r;
        END IF;

        -- ---- Thresholds are the farm's own -----------------------------------
        PERFORM public.sppoultrystocksupplysettings_set(a, 7, 1, 2, 3, who);
        SELECT * INTO r FROM public.sppoultrystocksupply(a, NULL, t_day) x WHERE x.poultryrawmaterialitemid = i_norm;
        IF r.status <> 'Healthy' OR r.criticaldays <> 1 THEN
            RAISE EXCEPTION '337: custom thresholds (1 / 2 days) should make 2.9 days Healthy: %', r;
        END IF;
        BEGIN
            PERFORM public.sppoultrystocksupplysettings_set(a, 7, 5, 5, 3, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '337: accepted warning <= critical.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- ---- Company isolation ------------------------------------------------
        SELECT * INTO r FROM public.sppoultrystocksupply(b, NULL, t_day) x WHERE x.poultryrawmaterialitemid = i_b;
        IF r.consumedqty <> 9000 THEN
            RAISE EXCEPTION '337: company B should see only its own 9000: %', r;
        END IF;
        IF EXISTS (SELECT 1 FROM public.sppoultrystocksupply(b, NULL, t_day) x WHERE x.poultryrawmaterialitemid = i_norm) THEN
            RAISE EXCEPTION '337: company B sees company A''s item.';
        END IF;

        -- ---- Expected usage from a saved feed rate (optional) -----------------
        INSERT INTO poultryfeedrates (farmid, poultryrawmaterialitemid, gramsperbirdperday) VALUES (a, i_norm, 112.5);
        SELECT * INTO r FROM public.sppoultrystocksupply(a, NULL, t_day) x WHERE x.poultryrawmaterialitemid = i_norm;
        IF r.expecteddailyusage <> 207 THEN
            RAISE EXCEPTION '337: 1,840 birds x 112.5 g should expect 207 kg/day, got %.', r.expecteddailyusage;
        END IF;
        IF (SELECT x.expecteddailyusage FROM public.sppoultrystocksupply(a, NULL, t_day) x WHERE x.poultryrawmaterialitemid = i_bag) IS NOT NULL THEN
            RAISE EXCEPTION '337: an item with no saved rate must have no expected usage.';
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '__337_ok__';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;
    END;
    RAISE NOTICE '337_PoultryDaysOfSupply: verified (normal, zero, insufficient history, negative, out of stock, reversed/purchases/write-offs/unlinked excluded, feed production, units, lookback, timezone, thresholds, isolation, expected usage).';
END $$;

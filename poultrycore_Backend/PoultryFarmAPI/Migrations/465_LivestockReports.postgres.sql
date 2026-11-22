-- 465: Livestock reports and trackers.
--
-- Needs 458-464. Read-only: nothing here writes. Every figure comes from the
-- same ledgers and records the pages use (head movements, stock movements,
-- daily records, sales lines), so a report can never disagree with a page.
--
--   splivestockreport_production  -- per group: head, deaths, mortality, eggs
--                                    and lay rate, milk per animal, feed per head;
--                                    plus the farm's daily totals
--   splivestockreport_feed        -- feed used by item and by group, kg and cost
--   splivestockreport_medicine    -- medicine/vaccine used by item and by group
--   splivestockreport_sales       -- sales by what was sold, by customer, by day
--   splivestockreport_mortality   -- deaths and culls by group, with causes
--   splivestockreport_breeding    -- births and litter sizes by kind and by mother
--   splivestockreport_herd        -- the herd now: head, tagged, sex, age bands
--   splivestockreport_groupsummary-- one group's whole life in one view
--   splivestocktracker            -- a month as days x groups (deaths, eggs,
--                                    milk, feed kg, head) -- the poultry trackers
--
-- Permission: api/Livestock/reports -> livestock.reports (seeded in 463).

BEGIN;

CREATE OR REPLACE FUNCTION public.splivestockreport_production(p_farmid text, p_from date, p_to date, p_speciescode text DEFAULT NULL)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH g AS (
        SELECT g.*, s.name AS speciesname, s.produceseggs, s.producesmilk
        FROM livestockgroups g JOIN livestockspecies s ON s.speciescode = g.speciescode
        WHERE g.farmid = p_farmid AND NOT g.isdeleted AND g.startdate <= p_to AND (g.closeddate IS NULL OR g.closeddate >= p_from)
          AND (p_speciescode IS NULL OR g.speciescode = p_speciescode)
    ), r AS (
        SELECT pr.* FROM livestockproductionrecords pr JOIN g ON g.groupid = pr.groupid
        WHERE NOT pr.isdeleted AND pr.recorddate BETWEEN p_from AND p_to
    ), gr AS (
        SELECT g.groupid, g.name, g.speciesname, g.produceseggs, g.producesmilk,
               fnlivestock_groupheadasof(g.groupid, p_from - 1) AS headstart,
               fnlivestock_groupheadasof(g.groupid, p_to) AS headend,
               (SELECT count(*) FROM r WHERE r.groupid = g.groupid) AS records,
               (SELECT COALESCE(-SUM(quantity), 0) FROM livestockheadmovements m WHERE m.groupid = g.groupid AND m.reversedat IS NULL
                  AND m.movementtype = 'Death' AND m.movementdate BETWEEN p_from AND p_to) AS deaths,
               (SELECT SUM(eggscollected) FROM r WHERE r.groupid = g.groupid) AS eggs,
               (SELECT SUM(eggsbroken) FROM r WHERE r.groupid = g.groupid) AS broken,
               (SELECT SUM(milklitres) FROM r WHERE r.groupid = g.groupid) AS milk,
               -- animal-days: the head at the START of each record's day, summed (hen-day style:
               -- deaths and sales during the day do not shrink that day's rate)
               (SELECT SUM(fnlivestock_groupheadasof(g.groupid, r.recorddate - 1)) FROM r WHERE r.groupid = g.groupid) AS animaldays,
               (SELECT SUM(l.quantity * i.kgperunit) FROM livestockproductionlines l JOIN r ON r.recordid = l.recordid
                  JOIN livestockitems i ON i.itemid = l.itemid WHERE r.groupid = g.groupid AND l.linetype = 'Feed' AND NOT l.isreversed) AS feedkg
        FROM g
    )
    SELECT jsonb_build_object(
        'from', p_from, 'to', p_to,
        'groups', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'groupId', groupid, 'name', name, 'speciesName', speciesname, 'producesEggs', produceseggs, 'producesMilk', producesmilk,
            'headStart', headstart, 'headEnd', headend, 'records', records, 'deaths', deaths,
            'mortalityPct', CASE WHEN headstart > 0 THEN round(deaths * 100.0 / headstart, 2) END,
            'eggs', eggs, 'broken', broken,
            'layRatePct', CASE WHEN produceseggs AND animaldays > 0 AND eggs IS NOT NULL THEN round(eggs * 100.0 / animaldays, 1) END,
            'milk', milk,
            'milkPerAnimalDay', CASE WHEN producesmilk AND animaldays > 0 AND milk IS NOT NULL THEN round(milk / animaldays, 2) END,
            'feedKg', round(feedkg, 1),
            'feedPerAnimalDayKg', CASE WHEN animaldays > 0 AND feedkg IS NOT NULL THEN round(feedkg / animaldays, 3) END)
            ORDER BY speciesname, name), '[]'::jsonb) FROM gr),
        'daily', (SELECT COALESCE(jsonb_agg(jsonb_build_object('date', d, 'eggs', eggs, 'milk', milk, 'deaths', deaths) ORDER BY d), '[]'::jsonb)
                  FROM (SELECT recorddate AS d, SUM(eggscollected) AS eggs, SUM(milklitres) AS milk, SUM(deaths) AS deaths FROM r GROUP BY recorddate) x));
$f$;

-- Stock used from records, treatments and health records, by item and by group.
CREATE OR REPLACE FUNCTION public.fnlivestock_usagereport(p_farmid text, p_from date, p_to date, p_cats text[])
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH u AS (
        SELECT m.itemid, i.name AS itemname, i.unit, i.kgperunit, m.groupid, -m.quantity AS qty, -m.totalcost AS cost, m.sourcetype
        FROM livestockstockmovements m JOIN livestockitems i ON i.itemid = m.itemid
        WHERE m.farmid = p_farmid AND m.reversedat IS NULL AND m.movementtype = 'Usage'
          AND m.sourcetype IN ('ProductionRecord', 'TreatmentDay', 'HealthRecord')
          AND i.category = ANY (p_cats) AND m.movementdate BETWEEN p_from AND p_to
    )
    SELECT jsonb_build_object(
        'from', p_from, 'to', p_to,
        'totalCost', (SELECT COALESCE(SUM(cost), 0) FROM u),
        'byItem', (SELECT COALESCE(jsonb_agg(jsonb_build_object('itemId', itemid, 'name', itemname, 'unit', unit, 'quantity', qty,
                      'kg', CASE WHEN kgperunit IS NOT NULL THEN round(qty * kgperunit, 1) END, 'cost', cost) ORDER BY cost DESC), '[]'::jsonb)
                   FROM (SELECT itemid, itemname, unit, kgperunit, SUM(qty) AS qty, SUM(cost) AS cost FROM u GROUP BY 1, 2, 3, 4) x),
        'byGroup', (SELECT COALESCE(jsonb_agg(jsonb_build_object('groupId', x.groupid, 'name', g.name, 'cost', x.cost, 'kg', x.kg,
                       'head', fnlivestock_groupheadasof(x.groupid, p_to)) ORDER BY x.cost DESC), '[]'::jsonb)
                    FROM (SELECT groupid, SUM(cost) AS cost, round(SUM(qty * kgperunit), 1) AS kg FROM u WHERE groupid IS NOT NULL GROUP BY groupid) x
                    JOIN livestockgroups g ON g.groupid = x.groupid),
        'bySource', (SELECT COALESCE(jsonb_object_agg(sourcetype, cost), '{}'::jsonb) FROM (SELECT sourcetype, SUM(cost) AS cost FROM u GROUP BY 1) x));
$f$;

CREATE OR REPLACE FUNCTION public.splivestockreport_feed(p_farmid text, p_from date, p_to date)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT fnlivestock_usagereport(p_farmid, p_from, p_to, ARRAY['Feed']);
$f$;

CREATE OR REPLACE FUNCTION public.splivestockreport_medicine(p_farmid text, p_from date, p_to date)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT fnlivestock_usagereport(p_farmid, p_from, p_to, ARRAY['Medication', 'Vaccine']) || jsonb_build_object(
        'treatments', (SELECT count(*) FROM livestocktreatments t WHERE t.farmid = p_farmid AND t.startdate <= p_to AND t.enddate >= p_from AND t.status <> 'Cancelled'),
        'healthRecords', (SELECT count(*) FROM livestockhealthrecords h WHERE h.farmid = p_farmid AND NOT h.isdeleted AND h.recorddate BETWEEN p_from AND p_to),
        'illnesses', (SELECT COALESCE(jsonb_agg(jsonb_build_object('diagnosis', diag, 'cases', n, 'affected', aff) ORDER BY n DESC), '[]'::jsonb)
                      FROM (SELECT COALESCE(NULLIF(btrim(diagnosis), ''), 'Not diagnosed') AS diag, count(*) AS n, SUM(COALESCE(affected, 1)) AS aff
                            FROM livestockhealthrecords WHERE farmid = p_farmid AND NOT isdeleted AND kind = 'Illness' AND recorddate BETWEEN p_from AND p_to
                            GROUP BY 1) x));
$f$;

CREATE OR REPLACE FUNCTION public.splivestockreport_sales(p_farmid text, p_from date, p_to date)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH l AS (
        SELECT s.saleid, s.saledate, s.customerid, c.name AS customername, l.linetype, l.quantity, l.linetotal, l.costtotal,
               CASE WHEN l.linetype = 'Product' THEN i.name ELSE COALESCE(sp1.name, sp2.name) END AS what,
               CASE WHEN l.linetype = 'Product' THEN i.unit ELSE 'head' END AS unit
        FROM livestocksalelines l JOIN livestocksales s ON s.saleid = l.saleid
        LEFT JOIN customer c ON c.customerid = s.customerid
        LEFT JOIN livestockitems i ON i.itemid = l.itemid
        LEFT JOIN livestockgroups g ON g.groupid = l.groupid LEFT JOIN livestockspecies sp1 ON sp1.speciescode = g.speciescode
        LEFT JOIN livestockanimals a ON a.animalid = l.animalid LEFT JOIN livestockspecies sp2 ON sp2.speciescode = a.speciescode
        WHERE s.farmid = p_farmid AND s.reversedat IS NULL AND s.saledate BETWEEN p_from AND p_to
    )
    SELECT jsonb_build_object(
        'from', p_from, 'to', p_to,
        'total', (SELECT COALESCE(SUM(linetotal), 0) FROM l),
        'sales', (SELECT count(DISTINCT saleid) FROM l),
        'received', (SELECT COALESCE(SUM(al.amount), 0) FROM livestockcustomerallocations al
                     JOIN livestockcustomerpayments p ON p.paymentid = al.paymentid AND p.reversedat IS NULL
                     JOIN livestocksales s ON s.saleid = al.saleid AND s.reversedat IS NULL AND s.farmid = p_farmid AND s.saledate BETWEEN p_from AND p_to),
        'byWhat', (SELECT COALESCE(jsonb_agg(jsonb_build_object('what', what, 'kind', linetype, 'unit', unit, 'quantity', qty, 'amount', amt,
                      'averagePrice', CASE WHEN qty > 0 THEN round(amt / qty, 2) END) ORDER BY amt DESC), '[]'::jsonb)
                   FROM (SELECT what, CASE WHEN linetype = 'Product' THEN 'Product' ELSE 'Animals' END AS linetype, unit,
                                SUM(quantity) AS qty, SUM(linetotal) AS amt FROM l GROUP BY 1, 2, 3) x),
        'byCustomer', (SELECT COALESCE(jsonb_agg(jsonb_build_object('customerId', customerid, 'name', COALESCE(customername, 'Walk-in'),
                          'sales', n, 'amount', amt, 'owes', CASE WHEN customerid IS NULL THEN 0 ELSE fnlivestock_customerowes(p_farmid, customerid) END)
                          ORDER BY amt DESC), '[]'::jsonb)
                       FROM (SELECT customerid, customername, count(DISTINCT saleid) AS n, SUM(linetotal) AS amt FROM l GROUP BY 1, 2) x),
        'daily', (SELECT COALESCE(jsonb_agg(jsonb_build_object('date', saledate, 'amount', amt) ORDER BY saledate), '[]'::jsonb)
                  FROM (SELECT saledate, SUM(linetotal) AS amt FROM l GROUP BY 1) x));
$f$;

CREATE OR REPLACE FUNCTION public.splivestockreport_mortality(p_farmid text, p_from date, p_to date)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH d AS (
        SELECT m.groupid, m.movementtype, -m.quantity AS n, m.notes, m.sourcetype, m.sourceid, m.animalid
        FROM livestockheadmovements m
        WHERE m.farmid = p_farmid AND m.reversedat IS NULL AND m.movementtype IN ('Death', 'Cull') AND m.movementdate BETWEEN p_from AND p_to
    )
    SELECT jsonb_build_object(
        'from', p_from, 'to', p_to,
        'deaths', (SELECT COALESCE(SUM(n) FILTER (WHERE movementtype = 'Death'), 0) FROM d),
        'culls', (SELECT COALESCE(SUM(n) FILTER (WHERE movementtype = 'Cull'), 0) FROM d),
        'byGroup', (SELECT COALESCE(jsonb_agg(jsonb_build_object('groupId', g.groupid, 'name', g.name, 'speciesName', s.name,
                       'headStart', fnlivestock_groupheadasof(g.groupid, p_from - 1), 'deaths', x.deaths, 'culls', x.culls,
                       'mortalityPct', CASE WHEN fnlivestock_groupheadasof(g.groupid, p_from - 1) > 0
                                            THEN round(x.deaths * 100.0 / fnlivestock_groupheadasof(g.groupid, p_from - 1), 2) END)
                       ORDER BY x.deaths DESC), '[]'::jsonb)
                    FROM (SELECT groupid, COALESCE(SUM(n) FILTER (WHERE movementtype = 'Death'), 0) AS deaths,
                                 COALESCE(SUM(n) FILTER (WHERE movementtype = 'Cull'), 0) AS culls FROM d GROUP BY groupid) x
                    JOIN livestockgroups g ON g.groupid = x.groupid JOIN livestockspecies s ON s.speciescode = g.speciescode),
        -- Causes: the cause on the daily record, the note on a tagged animal's death, or the change's own note.
        'causes', (SELECT COALESCE(jsonb_agg(jsonb_build_object('cause', cause, 'deaths', n) ORDER BY n DESC), '[]'::jsonb)
                   FROM (SELECT COALESCE(NULLIF(btrim(CASE WHEN d.sourcetype = 'ProductionRecord' THEN pr.deathcause
                                                           WHEN d.animalid IS NOT NULL THEN a.statusnotes ELSE d.notes END), ''), 'Not recorded') AS cause,
                                SUM(d.n) AS n
                         FROM d LEFT JOIN livestockproductionrecords pr ON d.sourcetype = 'ProductionRecord' AND pr.recordid = d.sourceid
                         LEFT JOIN livestockanimals a ON a.animalid = d.animalid
                         WHERE d.movementtype = 'Death' GROUP BY 1) x));
$f$;

CREATE OR REPLACE FUNCTION public.splivestockreport_breeding(p_farmid text, p_from date, p_to date)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH e AS (
        SELECT e.*, s.name AS speciesname, s.youngterm FROM livestockbreedingevents e JOIN livestockspecies s ON s.speciescode = e.speciescode
        WHERE e.farmid = p_farmid AND NOT e.isdeleted AND e.eventdate BETWEEN p_from AND p_to
    )
    SELECT jsonb_build_object(
        'from', p_from, 'to', p_to,
        'bySpecies', (SELECT COALESCE(jsonb_agg(jsonb_build_object('speciesName', speciesname, 'youngTerm', youngterm,
                         'matings', matings, 'births', births, 'bornAlive', alive, 'bornDead', dead,
                         'averageLitter', CASE WHEN births > 0 THEN round((alive + dead)::numeric / births, 1) END,
                         'survivalPct', CASE WHEN alive + dead > 0 THEN round(alive * 100.0 / (alive + dead), 1) END,
                         'weaned', weaned, 'lost', lost) ORDER BY speciesname), '[]'::jsonb)
                      FROM (SELECT speciesname, youngterm,
                                   count(*) FILTER (WHERE eventtype = 'Mating') AS matings,
                                   count(*) FILTER (WHERE eventtype = 'Birth') AS births,
                                   COALESCE(SUM(bornalive) FILTER (WHERE eventtype = 'Birth'), 0) AS alive,
                                   COALESCE(SUM(borndead) FILTER (WHERE eventtype = 'Birth'), 0) AS dead,
                                   COALESCE(SUM(weanedcount) FILTER (WHERE eventtype = 'Weaning'), 0) AS weaned,
                                   count(*) FILTER (WHERE eventtype = 'Loss') AS lost
                            FROM e GROUP BY 1, 2) x),
        'byMother', (SELECT COALESCE(jsonb_agg(jsonb_build_object('animalId', damid, 'tagNumber', tag, 'births', births, 'bornAlive', alive,
                        'averageLitter', round((alive + dead)::numeric / births, 1)) ORDER BY alive DESC), '[]'::jsonb)
                     FROM (SELECT e.damid, a.tagnumber AS tag, count(*) AS births, SUM(e.bornalive) AS alive, SUM(e.borndead) AS dead
                           FROM e JOIN livestockanimals a ON a.animalid = e.damid WHERE e.eventtype = 'Birth' GROUP BY 1, 2) x));
$f$;

CREATE OR REPLACE FUNCTION public.splivestockreport_herd(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'speciesCode', s.speciescode, 'name', s.name,
        'head', (SELECT COALESCE(SUM(fnlivestock_grouphead(g.groupid)), 0) FROM livestockgroups g WHERE g.farmid = p_farmid AND g.speciescode = s.speciescode AND NOT g.isdeleted),
        'groups', (SELECT count(*) FROM livestockgroups g WHERE g.farmid = p_farmid AND g.speciescode = s.speciescode AND g.status = 'Active' AND NOT g.isdeleted),
        'tagged', x.tagged, 'females', x.females, 'males', x.males,
        'ageBands', jsonb_build_object('under6Months', x.a0, 'sixTo12Months', x.a1, 'oneTo2Years', x.a2, 'over2Years', x.a3, 'unknown', x.au))
        ORDER BY s.sortorder), '[]'::jsonb)
    FROM livestockspecies s JOIN livestockfarmspecies fs ON fs.speciescode = s.speciescode AND fs.farmid = p_farmid
    CROSS JOIN LATERAL (
        SELECT count(*) AS tagged, count(*) FILTER (WHERE sex = 'Female') AS females, count(*) FILTER (WHERE sex = 'Male') AS males,
               count(*) FILTER (WHERE birthdate > (now() at time zone 'utc')::date - 183) AS a0,
               count(*) FILTER (WHERE birthdate <= (now() at time zone 'utc')::date - 183 AND birthdate > (now() at time zone 'utc')::date - 365) AS a1,
               count(*) FILTER (WHERE birthdate <= (now() at time zone 'utc')::date - 365 AND birthdate > (now() at time zone 'utc')::date - 730) AS a2,
               count(*) FILTER (WHERE birthdate <= (now() at time zone 'utc')::date - 730) AS a3,
               count(*) FILTER (WHERE birthdate IS NULL) AS au
        FROM livestockanimals a WHERE a.farmid = p_farmid AND a.speciescode = s.speciescode AND a.status = 'Active' AND NOT a.isdeleted) x;
$f$;

-- One group's whole life: in, out, now, feed, money.
CREATE OR REPLACE FUNCTION public.splivestockreport_groupsummary(p_farmid text, p_groupid integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE v_g livestockgroups%ROWTYPE; v_to date; v_pl jsonb; v_growth jsonb;
BEGIN
    SELECT * INTO v_g FROM livestockgroups WHERE groupid = p_groupid AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That group was not found.' USING ERRCODE = 'P0001';
    END IF;
    v_to := COALESCE(v_g.closeddate, (now() at time zone 'utc')::date);
    v_pl := splivestock_profitloss(p_farmid, v_g.startdate, v_to, p_groupid);
    v_growth := splivestockgrowth(p_farmid, p_groupid);
    RETURN fnlivestock_groupjson(p_groupid) || jsonb_build_object(
        'lifeDays', v_to - v_g.startdate + 1,
        'movements', (SELECT COALESCE(jsonb_object_agg(movementtype, n), '{}'::jsonb) FROM (
                        SELECT movementtype, SUM(abs(quantity)) AS n FROM livestockheadmovements
                        WHERE groupid = p_groupid AND reversedat IS NULL GROUP BY 1) x),
        'records', (SELECT count(*) FROM livestockproductionrecords WHERE groupid = p_groupid AND NOT isdeleted),
        'eggs', (SELECT SUM(eggscollected) FROM livestockproductionrecords WHERE groupid = p_groupid AND NOT isdeleted),
        'milk', (SELECT SUM(milklitres) FROM livestockproductionrecords WHERE groupid = p_groupid AND NOT isdeleted),
        'feedKg', v_growth->'feedKgTotal',
        'latestWeightKg', v_growth->'weighIns'->0->'avgWeightKg',
        'profitLoss', v_pl);
END
$f$;

-- A month as days x groups. p_kind: Deaths | Eggs | Milk | Feed | Head.
CREATE OR REPLACE FUNCTION public.splivestocktracker(p_farmid text, p_month date, p_kind text)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE v_from date := date_trunc('month', p_month)::date; v_to date; v_groups jsonb;
BEGIN
    IF p_kind NOT IN ('Deaths', 'Eggs', 'Milk', 'Feed', 'Head') THEN
        RAISE EXCEPTION 'Unknown tracker.' USING ERRCODE = 'P0001';
    END IF;
    v_to := LEAST((v_from + interval '1 month')::date - 1, (now() at time zone 'utc')::date);
    SELECT COALESCE(jsonb_agg(jsonb_build_object('groupId', g.groupid, 'name', g.name) ORDER BY s.sortorder, lower(g.name)), '[]'::jsonb) INTO v_groups
    FROM livestockgroups g JOIN livestockspecies s ON s.speciescode = g.speciescode
    WHERE g.farmid = p_farmid AND NOT g.isdeleted AND g.startdate <= v_to AND (g.closeddate IS NULL OR g.closeddate >= v_from)
      AND (p_kind <> 'Eggs' OR s.produceseggs) AND (p_kind <> 'Milk' OR s.producesmilk);

    RETURN jsonb_build_object('month', v_from, 'kind', p_kind, 'groups', v_groups,
        'days', (SELECT COALESCE(jsonb_agg(jsonb_build_object('date', d.day::date, 'values', (
                    SELECT COALESCE(jsonb_object_agg((ge->>'groupId'), v), '{}'::jsonb) FROM (
                        SELECT ge, CASE p_kind
                            WHEN 'Deaths' THEN (SELECT -SUM(quantity) FROM livestockheadmovements m WHERE m.groupid = (ge->>'groupId')::int
                                                AND m.reversedat IS NULL AND m.movementtype = 'Death' AND m.movementdate = d.day::date)
                            WHEN 'Eggs' THEN (SELECT SUM(eggscollected) FROM livestockproductionrecords r WHERE r.groupid = (ge->>'groupId')::int
                                              AND NOT r.isdeleted AND r.recorddate = d.day::date)
                            WHEN 'Milk' THEN (SELECT SUM(milklitres) FROM livestockproductionrecords r WHERE r.groupid = (ge->>'groupId')::int
                                              AND NOT r.isdeleted AND r.recorddate = d.day::date)
                            WHEN 'Feed' THEN (SELECT round(SUM(-m.quantity * i.kgperunit), 1) FROM livestockstockmovements m JOIN livestockitems i ON i.itemid = m.itemid
                                              WHERE m.groupid = (ge->>'groupId')::int AND m.reversedat IS NULL AND m.movementtype = 'Usage'
                                                AND i.category = 'Feed' AND m.movementdate = d.day::date)
                            ELSE fnlivestock_groupheadasof((ge->>'groupId')::int, d.day::date)::numeric END AS v
                        FROM jsonb_array_elements(v_groups) ge) x WHERE v IS NOT NULL AND v <> 0)) ORDER BY d.day), '[]'::jsonb)
                 FROM generate_series(v_from, v_to, interval '1 day') d(day)));
END
$f$;

COMMIT;

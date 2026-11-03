-- =============================================================================
-- broiler-kpis.test.sql -- checks for migration 402.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Fixtures live on
-- random farm ids. The worked example:
--
--   1,000 chicks for 5,000; 50 died; 4,200 kg feed; age 42 days
--   500 birds sold weighed at 1,250 kg (per kg, 10 / kg = 12,500)
--   300 birds sold unweighed for 7,500 -> 300 x 2.5 kg (avg sale weight) = 750 kg
--   150 birds still in the house, weighed in at 2,000 g -> 300 kg
--   kg produced 2,300 (estimated) | FCR 1.826 | liveability 95.00 %
--   avg weight 2.421 kg | EPEF 300 | cost / kg 2.17 | revenue / kg 10.00
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_a      text := 'kpitest-' || md5(random()::text);
    v_today  date;
    v_batch  integer;
    v_f      integer;
    v_f2     integer;
    v_r      record;
    v_n      numeric;
BEGIN
    v_today := fncompany_businessdate(v_a);

    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, costperchick, totalcost)
    VALUES ('u', v_a, 'KPI-1', 'Batch', 'Cobb 500', 1000, v_today - 42, 5, 5000) RETURNING batchid INTO v_batch;
    INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, batchid)
    VALUES ('u', v_a, 'Broilers KPI', v_today - 42, 'Cobb 500', 1000, v_batch) RETURNING flockid INTO v_f;

    INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, date, noofbirds, mortality, noofbirdsleft, feedkg,
        production9am, production12pm, production4pm, totalproduction, ageindays, flockid)
    VALUES (v_a, 'u', 'u', 0, v_today - 40, 1000, 30, 970, 2000, 0, 0, 0, 0, 2, v_f),
           (v_a, 'u', 'u', 3, v_today - 20, 970, 20, 950, 2200, 0, 0, 0, 0, 22, v_f);

    PERFORM sppoultryweighin_save(v_a, v_f, v_today - 7, p_samplesize => 50, p_avgweightg => 2000);

    PERFORM sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, NULL, NULL, 'Cash', NULL, FALSE, NULL, v_f,
        jsonb_build_array(jsonb_build_object('product', 'Chicken', 'quantity', 500, 'totalAmount', 12500,
            'pricingBasis', 'PerKg', 'liveWeightKg', 1250, 'pricePerKg', 10))::text);
    PERFORM sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, NULL, NULL, 'Cash', NULL, FALSE, NULL, v_f,
        jsonb_build_array(jsonb_build_object('product', 'Chicken', 'quantity', 300, 'unitPrice', 25, 'totalAmount', 7500))::text);

    SELECT * INTO v_r FROM fnflock_broilerkpis(v_a, v_f);

    -- 1. Birds.
    IF v_r.birdsstarted <> 1000 OR v_r.deaths <> 50 OR v_r.liveabilitypct <> 95.00 OR v_r.ageindays <> 42
       OR v_r.birdssold <> 800 OR v_r.birdssoldweighed <> 500 OR v_r.livebirds <> 150 THEN
        RAISE EXCEPTION 'FAIL 1 birds: %', v_r;
    END IF;
    RAISE NOTICE 'ok 1 birds, liveability, age';

    -- 2. Weight.
    IF v_r.kgsoldweighed <> 1250 OR v_r.avgsaleweightkg <> 2.5 OR v_r.kgsoldestimated <> 750
       OR v_r.latestavgweightkg <> 2 OR v_r.kginhouseestimated <> 300 OR v_r.kgproduced <> 2300
       OR NOT v_r.kgisestimated OR v_r.avgliveweightkg <> 2.421 THEN
        RAISE EXCEPTION 'FAIL 2 weight: %', v_r;
    END IF;
    RAISE NOTICE 'ok 2 kg sold, in house, produced';

    -- 3. Efficiency.
    IF v_r.feedkg <> 4200 OR v_r.fcr <> 1.826 OR v_r.epef <> 300 THEN
        RAISE EXCEPTION 'FAIL 3 FCR / EPEF: fcr % epef %', v_r.fcr, v_r.epef;
    END IF;
    RAISE NOTICE 'ok 3 FCR, EPEF';

    -- 4. Money -- the flock summary's own cost, chick cost included.
    IF v_r.birdcost <> 5000 OR v_r.totalcost <> 5000 OR v_r.costperkg <> 2.17
       OR v_r.birdsalerevenue <> 20000 OR v_r.revenueperkg <> 10.00 OR v_r.profit <> 15000 OR v_r.profitperkg <> 6.52 THEN
        RAISE EXCEPTION 'FAIL 4 money: %', v_r;
    END IF;
    SELECT s.totalcost INTO v_n FROM fnflock_lifetimesummary(v_a, v_f) s;
    IF v_n <> v_r.totalcost THEN RAISE EXCEPTION 'FAIL 4b: differs from the flock summary'; END IF;
    IF v_r.missing IS NOT NULL THEN RAISE EXCEPTION 'FAIL 4c: missing %', v_r.missing; END IF;
    RAISE NOTICE 'ok 4 cost and revenue per kg';

    -- 5. Unknown stays unknown: live birds and no weigh-in, no weights on sales.
    INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, batchid)
    VALUES ('u', v_a, 'Broilers unweighed', v_today - 20, 'Ross 308', 200, v_batch) RETURNING flockid INTO v_f2;
    SELECT * INTO v_r FROM fnflock_broilerkpis(v_a, v_f2);
    IF v_r.kgproduced IS NOT NULL OR v_r.fcr IS NOT NULL OR v_r.epef IS NOT NULL OR v_r.costperkg IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL 5a: guessed figures %', v_r;
    END IF;
    IF v_r.missing NOT LIKE '%No weigh-in%' OR v_r.missing NOT LIKE '%No feed%' THEN
        RAISE EXCEPTION 'FAIL 5b: missing %', v_r.missing;
    END IF;
    RAISE NOTICE 'ok 5 nothing guessed';

    -- 6. Filter: broilers only.
    UPDATE flock SET flocktype = 'Layer' WHERE flockid = v_f2;
    IF EXISTS (SELECT 1 FROM fnflock_broilerkpis(v_a, NULL, TRUE) k WHERE k.flockid = v_f2) THEN
        RAISE EXCEPTION 'FAIL 6: layer flock listed';
    END IF;
    RAISE NOTICE 'ok 6 broilers-only filter';

    -- 7. P&L by flock: the chick cost, in the period the flock started.
    SELECT * INTO v_r FROM sppoultryreport_profitlossbyflock(v_a, v_today - 60, v_today, v_f, TRUE);
    IF v_r.birdcost <> 5000 OR v_r.birdsalesrevenue <> 20000 THEN RAISE EXCEPTION 'FAIL 7a: %', v_r; END IF;
    SELECT * INTO v_r FROM sppoultryreport_profitlossbyflock(v_a, v_today - 10, v_today, v_f, TRUE);
    IF v_r.birdcost <> 0 THEN RAISE EXCEPTION 'FAIL 7b: charged outside the start period: %', v_r.birdcost; END IF;
    RAISE NOTICE 'ok 7 P&L by flock chick cost';

    RAISE NOTICE 'broiler kpis: all checks passed';
END
$$;

ROLLBACK;

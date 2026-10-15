-- =============================================================================
-- byproduct-reports.test.sql -- checks for migration 375.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Uses the open,
-- batched flock with the most production records on dev.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm    text;
    v_user    text;
    v_flock   integer;
    v_batch   integer;
    v_birds   integer;
    v_rec     integer;
    v_sale    integer;
    v_today   date;
    v_r       record;
    v_x       numeric;
    v_y       numeric;
    v_bad     integer;
    v_d       date;
BEGIN
    -- 1. The identity holds for every company's rows, as the data stands.
    SELECT count(*) INTO v_bad
    FROM   (SELECT DISTINCT farmid FROM poultryproducts WHERE systemrole IS NOT NULL) c
    CROSS  JOIN LATERAL sppoultryreport_byproducts(c.farmid, CURRENT_DATE - 60, CURRENT_DATE + 1) r
    WHERE  r.opening + r.generated + r.manualin - r.sold - r.disposed - r.internaluse - r.manualout + r.reversals <> r.closing;
    IF v_bad > 0 THEN RAISE EXCEPTION 'FAIL 1: % rows do not reconcile', v_bad; END IF;
    RAISE NOTICE 'ok 1 opening + generated + in - sold - disposed - used - out +/- reversals = closing, every company';

    SELECT f.farmid, f.flockid, f.batchid INTO v_farm, v_flock, v_batch
    FROM   flock f JOIN productionrecords pr ON pr.flockid = f.flockid AND pr.farmid = f.farmid
    WHERE  f.active AND NOT f.isdeleted AND f.closeddate IS NULL AND f.batchid IS NOT NULL
    GROUP  BY f.farmid, f.flockid, f.batchid ORDER BY count(*) DESC LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'byproduct reports: all checks passed';
        RETURN;
    END IF;
    SELECT fa.owneruserid INTO v_user FROM farms fa WHERE fa.id::text = v_farm OR fa.farmid::text = v_farm LIMIT 1;
    v_user  := COALESCE(v_user, 'check375');
    v_today := fncompany_businessdate(v_farm);
    PERFORM sppoultryproduct_ensurebyproducts(v_farm);
    -- A day this flock has no production record for (one record per flock per day).
    SELECT d::date INTO v_d FROM generate_series(v_today - 1, v_today - 400, interval '-1 day') d
    WHERE NOT EXISTS (SELECT 1 FROM productionrecords pr WHERE pr.farmid = v_farm AND pr.flockid = v_flock AND pr.date::date = d::date)
    ORDER BY d DESC LIMIT 1;
    SELECT GREATEST(COALESCE(pr.noofbirdsleft, 100), 100) INTO v_birds FROM productionrecords pr
    WHERE  pr.flockid = v_flock AND pr.farmid = v_farm ORDER BY pr.date DESC, pr.id DESC LIMIT 1;

    -- A known story for the flock today: 20 broken + 3 dead from production,
    -- 2 dead disposed, 5 broken sold, 10 broken entered pooled.
    SELECT r.generated, r.closing INTO v_x, v_y FROM sppoultryreport_byproducts(v_farm, v_d, v_today, v_flock, 'BrokenEggs') r;
    v_x := COALESCE(v_x, 0); v_y := COALESCE(v_y, 0);
    v_rec := spproductionrecord_insert(p_farmid => v_farm, p_createdby => 'check375', p_userid => 'check375',
        p_ageinweeks => 30, p_ageindays => 210, p_date => v_d, p_noofbirds => v_birds, p_mortality => 3,
        p_noofbirdsleft => v_birds - 3, p_feedkg => 0, p_production9am => 500, p_production12pm => 0, p_production4pm => 0,
        p_totalproduction => 500, p_flockid => v_flock, p_brokeneggs => 20);
    PERFORM sppoultrymanualmovement_post(v_farm, fnpoultry_byproduct(v_farm, 'DeadBirds'), NULL, 'Decrease', 2, NULL, v_batch, v_flock,
        v_today, 'Disposal', NULL, NULL, NULL, 'check375');
    PERFORM sppoultrymanualmovement_post(v_farm, fnpoultry_byproduct(v_farm, 'BrokenEggs'), NULL, 'Increase', 10, NULL, NULL, NULL,
        v_today, 'Opening Inventory', NULL, NULL, NULL, 'check375');
    v_sale := (sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
              p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
              p_description => 'check375', p_flockid => v_flock,
              p_linesjson => '[{"product":"Broken Eggs","eggProductId":null,"quantity":5,"unitPrice":2,"totalAmount":10}]',
              p_requestkey => 'check-375-a')::jsonb->>'saleId')::integer;

    -- 2. The flock's row.
    SELECT * INTO v_r FROM sppoultryreport_byproducts(v_farm, v_d, v_today, v_flock, 'BrokenEggs') r;
    IF v_r.generated - v_x <> 20 OR v_r.sold < 5 OR v_r.revenue < 10 THEN
        RAISE EXCEPTION 'FAIL 2a: broken eggs by flock %', row_to_json(v_r); END IF;
    IF v_r.closing - v_y <> 15 THEN RAISE EXCEPTION 'FAIL 2b: flock closing moved by % (want 15)', v_r.closing - v_y; END IF;
    SELECT * INTO v_r FROM sppoultryreport_byproducts(v_farm, v_d, v_today, v_flock, 'DeadBirds') r;
    IF v_r.generated < 3 OR v_r.disposed < 2 THEN RAISE EXCEPTION 'FAIL 2c: dead birds by flock %', row_to_json(v_r); END IF;
    RAISE NOTICE 'ok 2 flock row: broken +20 generated, 5 sold for 10, dead 3 generated, 2 disposed';

    -- 3. Pooled stock is never put on a flock.
    IF NOT EXISTS (SELECT 1 FROM sppoultryreport_byproducts(v_farm, v_d, v_today, NULL, 'BrokenEggs') r
                   WHERE r.flockid IS NULL AND r.manualin >= 10) THEN RAISE EXCEPTION 'FAIL 3a: pooled row'; END IF;
    IF (SELECT r.manualin FROM sppoultryreport_byproducts(v_farm, v_d, v_today, v_flock, 'BrokenEggs') r) >= 10 THEN
        RAISE EXCEPTION 'FAIL 3b: pooled entry put on the flock'; END IF;
    -- One row per byproduct when not split by flock, and it equals the stock on hand.
    IF (SELECT r.closing FROM sppoultryreport_byproducts(v_farm, v_today - 3650, v_today, NULL, 'BrokenEggs', FALSE) r)
       <> fnpoultry_byproductonhand(v_farm, 'BrokenEggs') THEN RAISE EXCEPTION 'FAIL 3c: closing <> on hand'; END IF;
    RAISE NOTICE 'ok 3 pooled entries stay pooled; total closing = Broken Eggs on hand';

    -- 4. Sale reversal shows as a reversal and takes the revenue back.
    v_x := (SELECT r.revenue FROM sppoultryreport_byproducts(v_farm, v_d, v_today, NULL, 'BrokenEggs', FALSE) r);
    PERFORM sppoultrysale_reverse(v_farm, v_sale, 'Other', 'check375', '{}'::jsonb, NULL, NULL, v_user);
    SELECT * INTO v_r FROM sppoultryreport_byproducts(v_farm, v_d, v_today, NULL, 'BrokenEggs', FALSE) r;
    IF v_r.reversals < 5 OR v_r.revenue <> v_x - 10 THEN RAISE EXCEPTION 'FAIL 4: reversal %', row_to_json(v_r); END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultryreport_byproductmovements(v_farm, v_d, v_today, NULL, 'BrokenEggs', 'Reversal')) THEN
        RAISE EXCEPTION 'FAIL 4b: movement list'; END IF;
    RAISE NOTICE 'ok 4 a reversed sale is a reversal, revenue back out';

    -- 5. Revenue lines.
    IF fnpoultrysale_revenueline('Broken Eggs') <> 'ByproductSales' OR fnpoultrysale_revenueline('Dead Birds') <> 'ByproductSales'
       OR fnpoultrysale_revenueline('Fresh Eggs') <> 'EggSales' OR fnpoultrysale_revenueline('Chicken') <> 'BirdSales' THEN
        RAISE EXCEPTION 'FAIL 5a: revenue lines'; END IF;
    v_sale := (sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
              p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
              p_description => 'check375', p_flockid => v_flock,
              p_linesjson => '[{"product":"Broken Eggs","eggProductId":null,"quantity":4,"unitPrice":3,"totalAmount":12}]',
              p_requestkey => 'check-375-b')::jsonb->>'saleId')::integer;
    IF NOT EXISTS (SELECT 1 FROM sppoultryreport_pllines(v_farm, v_today, v_today) x WHERE x.linekey = 'ByproductSales' AND x.amount >= 12) THEN
        RAISE EXCEPTION 'FAIL 5b: no Byproduct Sales line on P&L'; END IF;
    SELECT s.otherrevenue INTO v_x FROM sppoultryreport_plsummary(v_farm, v_today, v_today) s;
    IF v_x < 12 THEN RAISE EXCEPTION 'FAIL 5c: summary lost the byproduct revenue'; END IF;
    IF (SELECT x.c_egg FROM (SELECT eggrevenue AS c_egg FROM sppoultryreport_profitlossbyflock(v_farm, v_today, v_today) WHERE flockid = v_flock) x)
       >= (SELECT COALESCE(sum(totalamount), 0) FROM sale WHERE farmid = v_farm AND flockid = v_flock AND status = 'Posted'
           AND saledate::date = v_today AND product ILIKE '%egg%') AND
       (SELECT COALESCE(sum(totalamount), 0) FROM sale WHERE farmid = v_farm AND flockid = v_flock AND status = 'Posted'
           AND saledate::date = v_today AND product ILIKE '%egg%') > 0 THEN
        RAISE EXCEPTION 'FAIL 5d: P&L by flock counts Broken Eggs as egg revenue'; END IF;
    RAISE NOTICE 'ok 5 byproduct sales: own P&L line, in other revenue, not egg revenue by flock';

    -- 6. Egg stock balance does not count Broken Eggs sold as eggs sold.
    SELECT x.salesinrange INTO v_x FROM sppoultryreport_eggstockbalance(v_farm, v_today, v_today) x;
    IF v_x <> COALESCE((SELECT sum(trunc(s.quantity)) FROM sale s WHERE s.farmid = v_farm AND s.status = 'Posted'
                         AND s.product ILIKE '%egg%' AND fnpoultrysale_byproductrole(s.product) IS NULL
                         AND s.saledate >= v_today AND s.saledate < v_today + 1
                         AND NOT (COALESCE(s.saledescription,'') ILIKE 'Driver return #%' OR COALESCE(s.saledescription,'') ILIKE 'Delivery #%')), 0) THEN
        RAISE EXCEPTION 'FAIL 6: egg stock balance sales %', v_x; END IF;
    RAISE NOTICE 'ok 6 egg stock balance leaves Broken Eggs out of eggs sold';

    RAISE NOTICE 'byproduct reports: all checks passed';
END $$;

ROLLBACK;

-- =============================================================================
-- eggs-sold-eggs-only.test.sql -- checks for migration 403.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Fixtures live on
-- a random farm id.
--
--   300 eggs produced; sold: 100 Fresh Eggs (300), 10 Chicken (500), 5 Manure (25)
--   eggs sold 100 | closing egg stock 200 | income 825 (every sale)
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_a      text := 'eggsold-' || md5(random()::text);
    v_today  date;
    v_batch  integer;
    v_f      integer;
    v_r      record;
BEGIN
    v_today := fncompany_businessdate(v_a);

    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate)
    VALUES ('u', v_a, 'E-1', 'Batch', 'Isa Brown', 500, v_today - 200) RETURNING batchid INTO v_batch;
    INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, batchid)
    VALUES ('u', v_a, 'Mixed farm', v_today - 200, 'Isa Brown', 500, v_batch) RETURNING flockid INTO v_f;
    -- The farm's unsorted egg product, which an egg sale takes its stock from.
    INSERT INTO poultryproducts (farmid, name, israweggproduct) VALUES (v_a, 'Eggs', TRUE);
    INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, date, noofbirds, mortality, noofbirdsleft, feedkg,
        production9am, production12pm, production4pm, totalproduction, ageindays, flockid)
    VALUES (v_a, 'u', 'u', 28, v_today, 500, 0, 500, 0, 300, 0, 0, 300, 200, v_f);

    PERFORM sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, NULL, NULL, 'Cash', NULL, FALSE, NULL, v_f,
        jsonb_build_array(jsonb_build_object('product', 'Fresh Eggs', 'quantity', 100, 'unitPrice', 90, 'totalAmount', 300))::text);
    PERFORM sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, NULL, NULL, 'Cash', NULL, FALSE, NULL, v_f,
        jsonb_build_array(jsonb_build_object('product', 'Chicken', 'quantity', 10, 'unitPrice', 50, 'totalAmount', 500))::text);
    PERFORM sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, NULL, NULL, 'Cash', NULL, FALSE, NULL, NULL,
        jsonb_build_array(jsonb_build_object('product', 'Manure', 'quantity', 5, 'unitPrice', 5, 'totalAmount', 25))::text);

    -- 1. Daily closing.
    SELECT * INTO v_r FROM fnpoultrydailyclosing_livetotals(v_a, v_today);
    IF v_r.eggssold <> 100 THEN RAISE EXCEPTION 'FAIL 1a: eggs sold %', v_r.eggssold; END IF;
    IF v_r.closingstock <> 200 THEN RAISE EXCEPTION 'FAIL 1b: closing egg stock %', v_r.closingstock; END IF;
    IF v_r.totalincome <> 825 THEN RAISE EXCEPTION 'FAIL 1c: income lost a sale: %', v_r.totalincome; END IF;
    RAISE NOTICE 'ok 1 daily closing';

    -- 2. Closing report.
    SELECT * INTO v_r FROM sppoultryclosingreport_get(v_a, v_today, v_today);
    IF v_r.eggssold <> 100 THEN RAISE EXCEPTION 'FAIL 2a: eggs sold %', v_r.eggssold; END IF;
    IF v_r.totalsales <> 825 THEN RAISE EXCEPTION 'FAIL 2b: sales lost one: %', v_r.totalsales; END IF;
    RAISE NOTICE 'ok 2 closing report';

    RAISE NOTICE 'eggs sold eggs only: all checks passed';
END
$$;

ROLLBACK;

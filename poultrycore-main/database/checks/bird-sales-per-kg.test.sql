-- =============================================================================
-- bird-sales-per-kg.test.sql -- checks for migration 401.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Fixtures live on
-- random farm ids, never on a real company.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_a      text := 'kgtest-' || md5(random()::text);
    v_today  date;
    v_batch  integer;
    v_f      integer;
    v_res    jsonb;
    v_id     integer;
    v_id2    integer;
    v_r      record;
    v_n      bigint;
    v_rec    integer;
    v_failed boolean;
    v_lines  jsonb;
BEGIN
    v_today := fncompany_businessdate(v_a);

    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate)
    VALUES ('u', v_a, 'K-1', 'Batch', 'Cobb 500', 1000, v_today - 40) RETURNING batchid INTO v_batch;
    INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, batchid)
    VALUES ('u', v_a, 'Broilers K', v_today - 40, 'Cobb 500', 1000, v_batch) RETURNING flockid INTO v_f;

    -- 1. Per kg, one line: amount = kg x price, per-bird price = amount / birds.
    v_res := sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, 'Kg Customer', NULL, 'Cash', NULL, FALSE,
        NULL, v_f, jsonb_build_array(jsonb_build_object(
            'product', 'Chicken', 'quantity', 100, 'unitPrice', 1, 'totalAmount', 7500,
            'pricingBasis', 'PerKg', 'liveWeightKg', 250, 'pricePerKg', 30))::text);
    v_id := (v_res->>'saleId')::int;
    SELECT s.quantity, s.unitprice, s.totalamount INTO v_r FROM sale s WHERE s.saleid = v_id;
    IF v_r.quantity <> 100 OR v_r.unitprice <> 75 OR v_r.totalamount <> 7500 THEN RAISE EXCEPTION 'FAIL 1a: %', v_r; END IF;
    SELECT l.pricingbasis, l.liveweightkg, l.priceperkg, l.calculatedamount, l.quantity INTO v_r
      FROM saleline l WHERE l.saleid = v_id;
    IF v_r.pricingbasis <> 'PerKg' OR v_r.liveweightkg <> 250 OR v_r.priceperkg <> 30
       OR v_r.calculatedamount <> 7500 OR v_r.quantity <> 100 THEN RAISE EXCEPTION 'FAIL 1b: %', v_r; END IF;
    -- The birds left the flock as birds, not kilograms.
    SELECT p.birdssold INTO v_n FROM fnflock_birdposition(v_a, v_f) p;
    IF v_n <> 100 THEN RAISE EXCEPTION 'FAIL 1c: birds sold %', v_n; END IF;
    RAISE NOTICE 'ok 1 per-kg sale';

    -- 2. Amount must match, unless overridden.
    v_failed := false;
    BEGIN PERFORM sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, NULL, NULL, 'Cash', NULL, FALSE, NULL, v_f,
        jsonb_build_array(jsonb_build_object('product', 'Chicken', 'quantity', 10, 'totalAmount', 999,
            'pricingBasis', 'PerKg', 'liveWeightKg', 25, 'pricePerKg', 30))::text);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2a: wrong amount accepted'; END IF;
    v_res := sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, NULL, NULL, 'Cash', NULL, FALSE, NULL, v_f,
        jsonb_build_array(jsonb_build_object('product', 'Chicken', 'quantity', 10, 'totalAmount', 700,
            'pricingBasis', 'PerKg', 'liveWeightKg', 25, 'pricePerKg', 30, 'amountOverridden', true))::text);
    SELECT l.amountoverridden, l.calculatedamount, l.totalamount INTO v_r FROM saleline l WHERE l.saleid = (v_res->>'saleId')::int;
    IF NOT v_r.amountoverridden OR v_r.calculatedamount <> 750 OR v_r.totalamount <> 700 THEN RAISE EXCEPTION 'FAIL 2b: %', v_r; END IF;
    RAISE NOTICE 'ok 2 amount checked, override kept';

    -- 3. Refusals.
    v_failed := false;
    BEGIN PERFORM sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, NULL, NULL, 'Cash', NULL, FALSE, NULL, v_f,
        jsonb_build_array(jsonb_build_object('product', 'Chicken', 'quantity', 10, 'totalAmount', 0,
            'pricingBasis', 'PerKg', 'pricePerKg', 30))::text);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3a: per kg without kg'; END IF;
    v_failed := false;
    BEGIN PERFORM sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, NULL, NULL, 'Cash', NULL, FALSE, NULL, v_f,
        jsonb_build_array(jsonb_build_object('product', 'Chicken', 'quantity', 10.5, 'totalAmount', 750,
            'pricingBasis', 'PerKg', 'liveWeightKg', 25, 'pricePerKg', 30))::text);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3b: half a bird'; END IF;
    v_failed := false;
    BEGIN PERFORM sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, NULL, NULL, 'Cash', NULL, FALSE, NULL, v_f,
        jsonb_build_array(jsonb_build_object('product', 'Chicken', 'quantity', 2, 'totalAmount', 1500,
            'pricingBasis', 'PerKg', 'liveWeightKg', 50, 'pricePerKg', 30))::text);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3c: 25 kg a bird'; END IF;
    v_failed := false;
    BEGIN PERFORM sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, NULL, NULL, 'Cash', NULL, FALSE, NULL, v_f,
        jsonb_build_array(jsonb_build_object('product', 'Chicken', 'quantity', 2, 'totalAmount', 10,
            'pricingBasis', 'PerLeg'))::text);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3d: unknown basis'; END IF;
    RAISE NOTICE 'ok 3 refusals';

    -- 4. Per bird with the weight recorded: money as typed, weight kept.
    v_res := sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, NULL, NULL, 'Cash', NULL, FALSE, NULL, v_f,
        jsonb_build_array(jsonb_build_object('product', 'Chicken', 'quantity', 20, 'unitPrice', 80, 'totalAmount', 1600,
            'pricingBasis', 'PerBird', 'liveWeightKg', 48.5))::text);
    SELECT l.pricingbasis, l.liveweightkg, l.priceperkg, l.unitprice, l.totalamount INTO v_r
      FROM saleline l WHERE l.saleid = (v_res->>'saleId')::int;
    IF v_r.pricingbasis <> 'PerBird' OR v_r.liveweightkg <> 48.5 OR v_r.priceperkg IS NOT NULL
       OR v_r.unitprice <> 80 OR v_r.totalamount <> 1600 THEN RAISE EXCEPTION 'FAIL 4: %', v_r; END IF;
    RAISE NOTICE 'ok 4 per bird with weight';

    -- 5. Several per-kg lines in one sale.
    v_res := sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, NULL, NULL, 'Cash', NULL, FALSE, NULL, v_f,
        jsonb_build_array(
            jsonb_build_object('product', 'Chicken', 'quantity', 10, 'totalAmount', 750,
                               'pricingBasis', 'PerKg', 'liveWeightKg', 25, 'pricePerKg', 30),
            jsonb_build_object('product', 'Chicken', 'quantity', 4, 'totalAmount', 360,
                               'pricingBasis', 'PerKg', 'liveWeightKg', 12, 'pricePerKg', 30))::text);
    v_id2 := (v_res->>'saleId')::int;
    SELECT s.quantity, s.totalamount, s.unitprice INTO v_r FROM sale s WHERE s.saleid = v_id2;
    IF v_r.quantity <> 14 OR v_r.totalamount <> 1110 OR v_r.unitprice <> 79.29 THEN RAISE EXCEPTION 'FAIL 5a: %', v_r; END IF;
    SELECT sum(l.liveweightkg) INTO v_n FROM saleline l WHERE l.saleid = v_id2;
    IF v_n <> 37 THEN RAISE EXCEPTION 'FAIL 5b: kg %', v_n; END IF;
    v_lines := fnpoultrysale_lines(v_id2);
    IF v_lines->1->>'pricingBasis' <> 'PerKg' OR (v_lines->1->>'liveWeightKg')::numeric <> 12 THEN
        RAISE EXCEPTION 'FAIL 5c: %', v_lines;
    END IF;
    RAISE NOTICE 'ok 5 multi-line + reader';

    -- 6. A bird line sent the old way is unchanged: no basis, no weight.
    v_res := sppoultrysale_creategroup(v_a, 'u', v_today::timestamp, NULL, NULL, 'Cash', NULL, FALSE, NULL, v_f,
        jsonb_build_array(jsonb_build_object('product', 'Chicken', 'quantity', 3, 'unitPrice', 70, 'totalAmount', 210))::text);
    SELECT l.pricingbasis, l.liveweightkg INTO v_r FROM saleline l WHERE l.saleid = (v_res->>'saleId')::int;
    IF v_r.pricingbasis IS NOT NULL OR v_r.liveweightkg IS NOT NULL THEN RAISE EXCEPTION 'FAIL 6: %', v_r; END IF;
    RAISE NOTICE 'ok 6 old bird line unchanged';

    -- 7. Closeout path: a single sale, weight recorded afterwards, once.
    v_id := spsale_insert(p_userid => 'u', p_farmid => v_a, p_saledate => v_today::timestamp, p_product => 'Birds',
        p_quantity => 50, p_unitprice => 60, p_totalamount => 3000, p_paymentmethod => NULL, p_customername => NULL,
        p_flockid => v_f, p_saledescription => 'Flock closeout: test', p_paid => FALSE, p_size => NULL, p_customerid => NULL);
    PERFORM sppoultrysale_setliveweight(v_a, v_id, 'PerKg', 100, 30, FALSE, 'u');
    SELECT l.pricingbasis, l.liveweightkg, l.priceperkg, l.totalamount INTO v_r FROM saleline l WHERE l.saleid = v_id;
    IF v_r.pricingbasis <> 'PerKg' OR v_r.liveweightkg <> 100 OR v_r.priceperkg <> 30 OR v_r.totalamount <> 3000 THEN
        RAISE EXCEPTION 'FAIL 7a: %', v_r;
    END IF;
    v_failed := false;
    BEGIN PERFORM sppoultrysale_setliveweight(v_a, v_id, 'PerBird', 90, NULL, FALSE, 'u');
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7b: written twice'; END IF;

    v_id := spsale_insert(p_userid => 'u', p_farmid => v_a, p_saledate => v_today::timestamp, p_product => 'Birds',
        p_quantity => 10, p_unitprice => 60, p_totalamount => 600, p_paymentmethod => NULL, p_customername => NULL,
        p_flockid => v_f, p_saledescription => 'Flock closeout: test', p_paid => FALSE, p_size => NULL, p_customerid => NULL);
    v_failed := false;
    BEGIN PERFORM sppoultrysale_setliveweight(v_a, v_id, 'PerKg', 25, 30, FALSE, 'u');   -- 750, not 600
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7c: money-changing weight accepted'; END IF;
    v_failed := false;
    BEGIN PERFORM sppoultrysale_setliveweight('kgtest-other', v_id, 'PerBird', 25, NULL, FALSE, 'u');
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7d: another company'; END IF;
    -- The system bypass is switched back off, so the line guard still stands
    -- for whatever runs next in the transaction. (A hand UPDATE cannot prove
    -- it here: the guard admits a sale created earlier in this transaction.)
    IF COALESCE(current_setting('poultry.sale_system', true), 'off') <> 'off' THEN
        RAISE EXCEPTION 'FAIL 7e: line guard left open';
    END IF;
    RAISE NOTICE 'ok 7 closeout weight, write-once, money-neutral';

    -- 8. Meat withdrawal from medication on a production record.
    INSERT INTO productionrecords (farmid, createdby, ageinweeks, date, noofbirds, mortality, noofbirdsleft, feedkg,
        production9am, production12pm, production4pm, totalproduction, ageindays, flockid)
    VALUES (v_a, 'u', 4, v_today - 3, 820, 0, 820, 0, 0, 0, 0, 0, 37, v_f) RETURNING id INTO v_rec;
    INSERT INTO poultrymedicationproductsettings (farmid, poultryrawmaterialitemid, meatwithdrawaldays)
    VALUES (v_a, -398, 5);
    INSERT INTO productionrecordmedications (farmid, productionrecordid, poultryrawmaterialitemid, itemname, quantityconsumed)
    VALUES (v_a, v_rec, -398, 'Test antibiotic', 1);

    SELECT * INTO v_r FROM fnpoultryflock_meatwithdrawal(v_a, v_today) w WHERE w.flockid = v_f;
    IF NOT FOUND OR v_r.withdrawaluntil <> v_today + 2 OR v_r.itemname <> 'Test antibiotic' THEN
        RAISE EXCEPTION 'FAIL 8a: %', v_r;
    END IF;
    SELECT count(*) INTO v_n FROM fnpoultryflock_meatwithdrawal(v_a, v_today + 2);
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 8b: the last day is inside'; END IF;
    SELECT count(*) INTO v_n FROM fnpoultryflock_meatwithdrawal(v_a, v_today + 3);
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 8c: still in withdrawal after it ended'; END IF;
    SELECT count(*) INTO v_n FROM fnpoultryflock_meatwithdrawal(v_a, v_today - 4);
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 8d: in withdrawal before the dose'; END IF;
    RAISE NOTICE 'ok 8 meat withdrawal';

    RAISE NOTICE 'bird sales per kg: all checks passed';
END
$$;

ROLLBACK;

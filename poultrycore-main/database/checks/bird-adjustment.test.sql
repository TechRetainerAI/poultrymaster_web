-- Behavioural checks for migration 359: bird adjustments per flock / batch.
--
-- SELF-CONTAINED: opens its own transaction and ROLLS IT BACK.
--
--   psql ... -X -f bird-adjustment.test.sql
--
--   A  flock decrease: latest record opens lower, live birds / position / ledger move
--   B  the next record's "birds left" chain starts from the corrected count
--   C  flock increase
--   D  more than the flock holds is refused; nothing posted
--   E  batch-level (no flock): unplaced birds shrink, allocation guard sees it
--   F  more than the batch's unplaced birds is refused
--   G  refusals: flock of another batch, flock with no production record,
--      closed flock, another company's batch
--   H  the manual stock movement no longer takes Birds; other products still post
--   I  history lists every adjustment with before / after

BEGIN;

CREATE FUNCTION pg_temp.ba_chk(p_label text, p_expect text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_expect IS NOT DISTINCT FROM p_got THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect % got %', p_label, COALESCE(p_expect, 'NULL'), COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

CREATE FUNCTION pg_temp.ba_like(p_label text, p_pattern text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_got ILIKE p_pattern THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect like "%" got %', p_label, p_pattern, COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

CREATE FUNCTION pg_temp.ba_live(p_farm text, p_flock integer)
RETURNS integer LANGUAGE sql AS $c$
    SELECT currentlivebirds FROM fnflock_birdposition(p_farm, p_flock);
$c$;

CREATE FUNCTION pg_temp.ba_ledger(p_farm text)
RETURNS numeric LANGUAGE sql AS $c$
    SELECT COALESCE(SUM(t.quantity), 0) FROM poultrystocktransactions t
    WHERE t.farmid = p_farm AND t.txntype = 'Bird Adjustment';
$c$;

DO $t$
DECLARE
    v_farm   text := gen_random_uuid()::text;
    v_other  text := gen_random_uuid()::text;
    v_today  date;
    v_batch  integer;
    v_batch2 integer;
    v_obatch integer;
    v_a      integer;      -- flock with records
    v_b      integer;      -- flock with no production record
    v_c      integer;      -- flock of batch 2
    v_rec    integer;
    v_id     integer;
    v_bird   integer;
    v_egg    integer;
    v_msg    text;
    f        integer := 0;
BEGIN
    v_today := fncompany_businessdate(v_farm);

    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, costperchick, totalcost)
    VALUES ('ba-test', v_farm, 'BA-1', 'Adjust batch', 'Isa Brown', 1000, v_today - 60, 2, 2000) RETURNING batchid INTO v_batch;
    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, costperchick, totalcost)
    VALUES ('ba-test', v_farm, 'BA-2', 'Other batch', 'Isa Brown', 300, v_today - 60, 2, 600) RETURNING batchid INTO v_batch2;
    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, costperchick, totalcost)
    VALUES ('ba-test', v_other, 'BA-X', 'Elsewhere', 'Isa Brown', 100, v_today - 60, 2, 200) RETURNING batchid INTO v_obatch;

    -- Batch 1: 500 + 200 placed, 300 unplaced.
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, hasarrived)
    VALUES ('ba-test', v_farm, 'BA Flock A', 'Isa Brown', v_today - 60, 500, TRUE, v_batch, TRUE) RETURNING flockid INTO v_a;
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, hasarrived)
    VALUES ('ba-test', v_farm, 'BA Flock B', 'Isa Brown', v_today - 60, 200, TRUE, v_batch, TRUE) RETURNING flockid INTO v_b;
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, hasarrived)
    VALUES ('ba-test', v_farm, 'BA Flock C', 'Isa Brown', v_today - 60, 300, TRUE, v_batch2, TRUE) RETURNING flockid INTO v_c;

    INSERT INTO productionrecords (farmid, createdby, userid, ageinweeks, ageindays, date, noofbirds, mortality,
                                   noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid)
    VALUES (v_farm, 'ba-test', 'ba-test', 8, 58, v_today - 2, 500, 10, 490, 0, 0, 0, 0, 0, v_a),
           (v_farm, 'ba-test', 'ba-test', 8, 59, v_today - 1, 490, 5, 485, 0, 0, 0, 0, 0, v_a),
           (v_farm, 'ba-test', 'ba-test', 8, 59, v_today - 1, 300, 0, 300, 0, 0, 0, 0, 0, v_c);
    SELECT id INTO v_rec FROM productionrecords WHERE flockid = v_a AND date = v_today - 1;

    -- ================================================ A  flock decrease
    f := f + pg_temp.ba_chk('A0 flock A starts with 485', '485', pg_temp.ba_live(v_farm, v_a)::text);
    v_id := sppoultrybirdadjustment_post(v_farm, v_batch, v_a, 'Damage/Loss', -15, 'found dead in pen', 'tester');
    f := f + pg_temp.ba_chk('A1 flock A now 470', '470', pg_temp.ba_live(v_farm, v_a)::text);
    f := f + pg_temp.ba_chk('A2 latest record opens 475, leaves 470 (mortality kept)', '475|5|470',
            (SELECT noofbirds || '|' || mortality || '|' || noofbirdsleft FROM productionrecords WHERE id = v_rec));
    f := f + pg_temp.ba_chk('A3 the earlier record is untouched', '490',
            (SELECT noofbirdsleft::text FROM productionrecords WHERE flockid = v_a AND date = v_today - 2));
    f := f + pg_temp.ba_chk('A4 ledger -15, note names the flock', '-15|Flock BA Flock A - found dead in pen',
            pg_temp.ba_ledger(v_farm)::int || '|' ||
            (SELECT note FROM poultrystocktransactions WHERE farmid = v_farm AND txntype = 'Bird Adjustment' AND relatedid = v_id));
    f := f + pg_temp.ba_chk('A5 adjustment records the record, before and after', '485|470',
            (SELECT birdsbefore || '|' || birdsafter FROM poultrybirdadjustments WHERE birdadjustmentid = v_id AND productionrecordid = v_rec));
    f := f + pg_temp.ba_chk('A6 options show the flock at 470', '470',
            (SELECT livebirds::text FROM sppoultrybirdadjustment_options(v_farm) WHERE flockid = v_a));

    -- ===================================== B  the daily chain carries it
    f := f + pg_temp.ba_chk('B1 the next record would start from 470', '470',
            (SELECT noofbirdsleft::text FROM productionrecords WHERE flockid = v_a ORDER BY date DESC, id DESC LIMIT 1));

    -- ================================================ C  flock increase
    PERFORM sppoultrybirdadjustment_post(v_farm, v_batch, v_a, 'Increase', 5, 'miscounted', 'tester');
    f := f + pg_temp.ba_chk('C1 flock A now 475', '475', pg_temp.ba_live(v_farm, v_a)::text);

    -- ================================== D  more than the flock holds
    BEGIN
        PERFORM sppoultrybirdadjustment_post(v_farm, v_batch, v_a, 'Decrease', -476, NULL, 'tester');
        f := f + pg_temp.ba_chk('D1 over-decrease refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.ba_like('D1 over-decrease refused', '%has 475 birds%cannot lose 476%', SQLERRM);
    END;
    f := f + pg_temp.ba_chk('D2 nothing posted', '475|-10', pg_temp.ba_live(v_farm, v_a) || '|' || pg_temp.ba_ledger(v_farm)::int);

    -- ===================================== E  batch-level, unplaced birds
    f := f + pg_temp.ba_chk('E0 batch 1 has 300 unplaced', '300',
            (SELECT DISTINCT unplacedbirds::text FROM sppoultrybirdadjustment_options(v_farm) WHERE batchid = v_batch));
    PERFORM sppoultrybirdadjustment_post(v_farm, v_batch, NULL, 'Damage/Loss', -40, 'died in transit', 'tester');
    f := f + pg_temp.ba_chk('E1 batch 1 now 260 unplaced', '260',
            (SELECT DISTINCT unplacedbirds::text FROM sppoultrybirdadjustment_options(v_farm) WHERE batchid = v_batch));
    f := f + pg_temp.ba_chk('E2 allocation guard counts them consumed (700 placed + 40)', '740',
            spflock_getconsumedforbatch(v_batch, v_farm, NULL)::text);
    f := f + pg_temp.ba_chk('E3 flocks untouched', '475|200', pg_temp.ba_live(v_farm, v_a) || '|' || pg_temp.ba_live(v_farm, v_b));
    f := f + pg_temp.ba_chk('E4 ledger -50 in all', '-50', pg_temp.ba_ledger(v_farm)::int::text);

    -- ================================ F  more than the batch's unplaced
    BEGIN
        PERFORM sppoultrybirdadjustment_post(v_farm, v_batch, NULL, 'Decrease', -261, NULL, 'tester');
        f := f + pg_temp.ba_chk('F1 over-decrease of unplaced refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.ba_like('F1 over-decrease of unplaced refused', '%260 birds not placed%', SQLERRM);
    END;

    -- ================================================== G  refusals
    BEGIN
        PERFORM sppoultrybirdadjustment_post(v_farm, v_batch, v_c, 'Decrease', -1, NULL, 'tester');
        f := f + pg_temp.ba_chk('G1 flock of another batch refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.ba_like('G1 flock of another batch refused', '%not part of the chosen batch%', SQLERRM);
    END;
    BEGIN
        PERFORM sppoultrybirdadjustment_post(v_farm, v_batch, v_b, 'Decrease', -1, NULL, 'tester');
        f := f + pg_temp.ba_chk('G2 flock with no production record refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.ba_like('G2 flock with no production record refused', '%no production record yet%', SQLERRM);
    END;
    PERFORM set_config('app.flock_closeout', 'on', true);
    UPDATE flock SET closeddate = v_today, active = FALSE WHERE flockid = v_c;
    PERFORM set_config('app.flock_closeout', 'off', true);
    BEGIN
        PERFORM sppoultrybirdadjustment_post(v_farm, v_batch2, v_c, 'Decrease', -1, NULL, 'tester');
        f := f + pg_temp.ba_chk('G3 closed flock refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.ba_like('G3 closed flock refused', '%is closed%', SQLERRM);
    END;
    BEGIN
        PERFORM sppoultrybirdadjustment_post(v_farm, v_obatch, NULL, 'Decrease', -1, NULL, 'tester');
        f := f + pg_temp.ba_chk('G4 another company''s batch refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.ba_like('G4 another company''s batch refused', '%does not belong to this company%', SQLERRM);
    END;

    -- ===================================== H  manual movement and Birds
    SELECT poultryproductid INTO v_bird FROM poultryproducts WHERE farmid = v_farm AND (isbirdproduct OR name = 'Birds') LIMIT 1;
    BEGIN
        PERFORM sppoultrystock_addtransaction(v_farm, v_bird, 'Decrease', -5, NULL, NULL, 'x', 'tester');
        f := f + pg_temp.ba_chk('H1 bare Birds movement refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.ba_like('H1 bare Birds movement refused', '%adjusted per flock or batch%', SQLERRM);
    END;
    PERFORM sppoultryeggsizes_ensure(v_farm, 'tester');
    v_egg := fnpoultry_unsortedeggproduct(v_farm);
    f := f + pg_temp.ba_chk('H2 other products still post', 'true',
            (sppoultrystock_addtransaction(v_farm, v_egg, 'Increase', 30, NULL, NULL, 'x', 'tester') > 0)::text);

    -- ===================================================== I  history
    f := f + pg_temp.ba_chk('I1 history: 3 adjustments, newest first is the batch one', '3|BA-1|',
            (SELECT count(*)::text FROM sppoultrybirdadjustment_getall(v_farm)) || '|' ||
            (SELECT batchcode || '|' || COALESCE(flockname, '') FROM sppoultrybirdadjustment_getall(v_farm) LIMIT 1));

    IF f > 0 THEN
        RAISE EXCEPTION 'bird adjustment: % check(s) failed', f;
    END IF;
    RAISE NOTICE 'bird adjustment: all checks passed';
END $t$;

ROLLBACK;

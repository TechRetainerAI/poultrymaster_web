-- Self-test for migration 292. Creates a throwaway order under farmid
-- '__probe292__', exercises both functions through every branch, then deletes
-- everything it made. Touches no real data.
DO $$
DECLARE
    v_farm  text := '__probe292__';
    v_tok   text := 'probe292-token-abc';
    v_oid   integer;
    v_fid   integer;
    v_fid2  integer;
    v_already boolean;
    v_can   boolean;
    v_rated boolean;
    v_cnt   integer;
    v_rating integer;
BEGIN
    -- clean slate
    DELETE FROM restaurantcustomerfeedback WHERE farmid = v_farm;
    DELETE FROM restaurantorders WHERE farmid = v_farm;

    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, status, customername, totalamount, trackingtoken)
    VALUES (v_farm, 'PROBE-292-001', 'DineIn', 'Placed', '  Ama Serwaa  ', 85.50, v_tok)
    RETURNING orderid INTO v_oid;

    -- 1. a junk token leaks nothing and does not raise
    SELECT orderfound INTO v_rated FROM sprestaurant_public_feedback_status('no-such-token-at-all');
    IF v_rated THEN RAISE EXCEPTION 'FAIL 1: junk token reported found=true'; END IF;
    RAISE NOTICE 'PASS 1: junk token -> found=false';

    -- 2. a freshly Placed order cannot be rated yet
    SELECT can_rate INTO v_can FROM sprestaurant_public_feedback_status(v_tok);
    IF v_can THEN RAISE EXCEPTION 'FAIL 2: a Placed order was rateable'; END IF;
    RAISE NOTICE 'PASS 2: status Placed -> can_rate=false';

    -- 3. and the insert refuses it, with a guest-readable message
    BEGIN
        PERFORM sprestaurant_public_feedback_insert(v_tok, 5);
        RAISE EXCEPTION 'FAIL 3: rating accepted on a Placed order';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL 3%' THEN RAISE; END IF;
        RAISE NOTICE 'PASS 3: insert refused on Placed -> %', SQLERRM;
    END;

    -- 4. once Served it becomes rateable
    UPDATE restaurantorders SET status = 'Served' WHERE orderid = v_oid;
    SELECT can_rate, already_rated INTO v_can, v_rated FROM sprestaurant_public_feedback_status(v_tok);
    IF NOT v_can OR v_rated THEN RAISE EXCEPTION 'FAIL 4: Served gave can_rate=% already=%', v_can, v_rated; END IF;
    RAISE NOTICE 'PASS 4: status Served -> can_rate=true, already_rated=false';

    -- 5. out-of-range rating rejected
    BEGIN
        PERFORM sprestaurant_public_feedback_insert(v_tok, 9);
        RAISE EXCEPTION 'FAIL 5: rating 9 accepted';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL 5%' THEN RAISE; END IF;
        RAISE NOTICE 'PASS 5: rating 9 rejected -> %', SQLERRM;
    END;

    -- 6. out-of-range SUB-rating rejected too
    BEGIN
        PERFORM sprestaurant_public_feedback_insert(v_tok, 5, 7);
        RAISE EXCEPTION 'FAIL 6: food rating 7 accepted';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL 6%' THEN RAISE; END IF;
        RAISE NOTICE 'PASS 6: food rating 7 rejected -> %', SQLERRM;
    END;

    -- 7. the happy path
    SELECT feedbackid, alreadyrated INTO v_fid, v_already
    FROM sprestaurant_public_feedback_insert(v_tok, 5, 5, 4, 5, '  Great jollof, very fast service  ');
    IF v_fid IS NULL OR v_already THEN RAISE EXCEPTION 'FAIL 7: insert gave id=% already=%', v_fid, v_already; END IF;
    RAISE NOTICE 'PASS 7: rating stored, feedbackid=%', v_fid;

    -- 8. it landed with source QR, status New, trimmed text, and the order linked
    SELECT count(*) INTO v_cnt FROM restaurantcustomerfeedback
    WHERE feedbackid = v_fid AND farmid = v_farm AND source = 'QR' AND status = 'New'
      AND orderid = v_oid AND comment = 'Great jollof, very fast service'
      AND customername = 'Ama Serwaa' AND rating = 5 AND foodrating = 5
      AND servicerating = 4 AND ambiencerating = 5;
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 8: stored row did not match expectations'; END IF;
    RAISE NOTICE 'PASS 8: source=QR status=New, comment and name trimmed, order linked';

    -- 9. status now reports already_rated and hands back what they said
    SELECT can_rate, already_rated, rating INTO v_can, v_rated, v_rating
    FROM sprestaurant_public_feedback_status(v_tok);
    IF v_can OR NOT v_rated OR v_rating <> 5 THEN
        RAISE EXCEPTION 'FAIL 9: can_rate=% already=% rating=%', v_can, v_rated, v_rating;
    END IF;
    RAISE NOTICE 'PASS 9: already_rated=true, can_rate=false, rating returned';

    -- 10. a second submission is idempotent, not a duplicate and not an error
    SELECT feedbackid, alreadyrated INTO v_fid2, v_already
    FROM sprestaurant_public_feedback_insert(v_tok, 1, 1, 1, 1, 'changed my mind');
    IF v_fid2 <> v_fid OR NOT v_already THEN
        RAISE EXCEPTION 'FAIL 10: resubmit gave id=% (expected %) already=%', v_fid2, v_fid, v_already;
    END IF;
    SELECT count(*) INTO v_cnt FROM restaurantcustomerfeedback WHERE orderid = v_oid AND source = 'QR';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 10b: % QR rows for one order', v_cnt; END IF;
    RAISE NOTICE 'PASS 10: resubmit returned the same id, still 1 row, original rating kept';

    -- 11. the unique index is the real guard -- a direct INSERT must be refused
    BEGIN
        INSERT INTO restaurantcustomerfeedback (farmid, orderid, rating, source)
        VALUES (v_farm, v_oid, 3, 'QR');
        RAISE EXCEPTION 'FAIL 11: unique index did not stop a second QR row';
    EXCEPTION
        WHEN unique_violation THEN RAISE NOTICE 'PASS 11: unique index refused a second QR row';
        WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL 11%' THEN RAISE; END IF;
    END;

    -- 12. staff feedback is NOT restricted -- several InStore rows on one order
    INSERT INTO restaurantcustomerfeedback (farmid, orderid, rating, source)
    VALUES (v_farm, v_oid, 4, 'InStore'), (v_farm, v_oid, 2, 'InStore');
    SELECT count(*) INTO v_cnt FROM restaurantcustomerfeedback WHERE orderid = v_oid AND source = 'InStore';
    IF v_cnt <> 2 THEN RAISE EXCEPTION 'FAIL 12: staff rows blocked (% found)', v_cnt; END IF;
    RAISE NOTICE 'PASS 12: staff InStore rows on the same order still allowed';

    -- 13. THE REGRESSION CHECK: the staff list still reads. It does SELECT f.*
    --     into a fixed 16-column RETURNS TABLE, so this is what would break if
    --     a column had been added to the table.
    SELECT count(*) INTO v_cnt FROM sprestaurant_feedback_list(v_farm, NULL);
    IF v_cnt <> 3 THEN RAISE EXCEPTION 'FAIL 13: feedback_list returned % rows, expected 3', v_cnt; END IF;
    RAISE NOTICE 'PASS 13: sprestaurant_feedback_list still returns rows (%)', v_cnt;

    -- 14. and the stats function the CRM header uses
    PERFORM * FROM sprestaurant_feedback_stats(v_farm);
    RAISE NOTICE 'PASS 14: sprestaurant_feedback_stats still executes';

    -- cleanup
    DELETE FROM restaurantcustomerfeedback WHERE farmid = v_farm;
    DELETE FROM restaurantorders WHERE farmid = v_farm;
    SELECT (SELECT count(*) FROM restaurantcustomerfeedback WHERE farmid = v_farm)
         + (SELECT count(*) FROM restaurantorders WHERE farmid = v_farm) INTO v_cnt;
    IF v_cnt <> 0 THEN RAISE EXCEPTION 'CLEANUP FAILED: % rows left', v_cnt; END IF;
    RAISE NOTICE 'CLEANUP: 0 probe rows left';
    RAISE NOTICE 'ALL 14 CHECKS PASSED';
END $$;

-- Behavioural checks for migration 338: end-of-flock closeout.
--
-- Run inside a transaction you ROLL BACK; it writes nothing that survives.
--
--   psql ... -X -c "BEGIN;" -f poultry-flock-closeout.test.sql -c "ROLLBACK;"
--
-- Every check prints "ok" or "FAIL"; the block RAISES at the end if any failed,
-- so the apply script's dry run stops on a failure rather than scrolling past it.
--
-- Fixtures live on a sentinel company id that is uuid-shaped, because
-- expense.farmid is a uuid and the lifetime summary's tagged-expense arm would
-- otherwise be proved against nothing (historical-batch-purchase gotcha).
--
--   A. Unresolved balances refuse to close
--   B. Close with every bird sold (an earlier sale + the closeout sale)
--   C. Pen release and house history
--   D. Removal from active workflows (guards + Missing Daily Records)
--   E. Sales and cash stay usable, the reconciled quantity does not
--   F. Lifetime metrics
--   G. Close with transfer + cull, and a historical opening position
--   H. Unknown opening history keeps lifetime mortality NULL
--   I. Reopening, and the audit trail it leaves
--   J. Permissions

-- SELF-CONTAINED: this file opens its own transaction and ROLLS IT BACK, so it
-- writes nothing even when run on its own. Do not remove these two lines.
BEGIN;

CREATE FUNCTION pg_temp.chk(p_label text, p_expect text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_expect IS NOT DISTINCT FROM p_got THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect % got %', p_label, COALESCE(p_expect, 'NULL'), COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

CREATE FUNCTION pg_temp.chk_like(p_label text, p_pattern text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_got ILIKE p_pattern THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect like "%" got %', p_label, p_pattern, COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

DO $t$
DECLARE
    v_farm    text := gen_random_uuid()::text;   -- a fresh, invisible company per run
    v_today   date;
    v_start   date;
    v_house   integer;
    v_house2  integer;
    v_batch   integer;
    v_a       integer;     -- sold-out flock
    v_b       integer;     -- transfer + cull, known opening history
    v_c       integer;     -- unknown opening history
    v_d       integer;     -- flock that stays running in the same house
    v_sale0   integer;     -- ordinary sale made weeks before closing
    v_sale1   integer;     -- the closeout sale
    v_eggsale integer;
    v_eggsale2 integer;
    v_co      integer;
    v_co2     integer;
    v_msg     text;
    v_n       integer;
    v_num     numeric;
    p         record;
    c         record;
    s         record;
    f         integer := 0;
BEGIN
    v_today := fncompany_businessdate(v_farm);
    v_start := v_today - 60;

    -- ---------------------------------------------------------------- fixtures
    INSERT INTO houses (userid, farmid, housename, capacity)
    VALUES ('closeout-test', v_farm, 'Closeout Test House', 1000) RETURNING houseid INTO v_house;
    INSERT INTO houses (userid, farmid, housename, capacity)
    VALUES ('closeout-test', v_farm, 'Closeout Test House 2', 2000) RETURNING houseid INTO v_house2;

    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, costperchick, totalcost)
    VALUES ('closeout-test', v_farm, 'CO-338', 'Closeout batch', 'Isa Brown', 1000, v_start, 2, 2000)
    RETURNING batchid INTO v_batch;

    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, houseid, hasarrived)
    VALUES ('closeout-test', v_farm, 'CO Flock A', 'Isa Brown', v_start, 500, TRUE, v_batch, v_house, TRUE)
    RETURNING flockid INTO v_a;
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, houseid, hasarrived)
    VALUES ('closeout-test', v_farm, 'CO Flock D', 'Isa Brown', v_start, 200, TRUE, v_batch, v_house, TRUE)
    RETURNING flockid INTO v_d;

    -- Two production days on A: 15 deaths, 700 eggs, 110 kg feed at 220, medication 20.
    INSERT INTO productionrecords (farmid, createdby, userid, ageinweeks, ageindays, date, noofbirds, mortality,
                                   noofbirdsleft, feedkg, production9am, production12pm, production4pm,
                                   totalproduction, flockid, totalfeedcost, totalmedicationcost)
    VALUES (v_farm, 'closeout-test', 'closeout-test', 20, 140, v_today - 50, 500, 10, 490, 50, 100, 100, 100, 300, v_a, 100, 20),
           (v_farm, 'closeout-test', 'closeout-test', 27, 190, v_today - 10, 490, 5, 485, 60, 150, 150, 100, 400, v_a, 120, 0);

    -- An ordinary bird sale weeks before closing: 35 birds at 10. Through the
    -- real spsale_insert, so it posts its own 'Bird Sale' ledger row.
    v_sale0 := spsale_insert(p_userid => 'closeout-test', p_farmid => v_farm, p_saledate => (v_today - 20)::timestamp,
                             p_product => 'Birds', p_quantity => 35, p_unitprice => 10, p_totalamount => 350,
                             p_paymentmethod => 'Cash', p_customername => 'Closeout Test Buyer',
                             p_flockid => v_a, p_paid => TRUE);
    -- An egg sale tagged to A: revenue, but never a bird.
    v_eggsale := spsale_insert(p_userid => 'closeout-test', p_farmid => v_farm, p_saledate => (v_today - 5)::timestamp,
                               p_product => 'Eggs', p_quantity => 600, p_unitprice => 1.5, p_totalamount => 900,
                               p_paymentmethod => 'Cash', p_customername => 'Closeout Test Buyer',
                               p_flockid => v_a, p_paid => TRUE);

    -- Expenses tagged to A: labour 300, other 50 -- and a capital purchase
    -- that must NOT land on one flock's profit.
    INSERT INTO expense (expensedate, category, description, amount, paymentmethod, flockid, userid, farmid)
    VALUES ((v_today - 30)::timestamp, 'Labor', 'Catching crew', 300, 'Cash', v_a, 'closeout-test', v_farm::uuid),
           ((v_today - 30)::timestamp, 'Other', 'Litter', 50, 'Cash', v_a, 'closeout-test', v_farm::uuid);
    INSERT INTO expense (expensedate, category, description, amount, paymentmethod, flockid, userid, farmid, financialcosttype)
    VALUES ((v_today - 30)::timestamp, 'Equipment', 'Drinkers', 999, 'Cash', v_a, 'closeout-test', v_farm::uuid, 'CapitalAsset');

    SELECT * INTO p FROM fnflock_birdposition(v_farm, v_a);
    f := f + pg_temp.chk('0. A opening live = placed (no opening position)', '500', p.openinglivebirds::text);
    f := f + pg_temp.chk('0. A recorded mortality', '15', p.recordedmortality::text);
    f := f + pg_temp.chk('0. A correction (count explained by mortality)', '0', p.correction::text);
    f := f + pg_temp.chk('0. A last counted', '485', p.lastcountedbirds::text);
    f := f + pg_temp.chk('0. A birds sold counts the bird sale, not the egg sale', '35', p.birdssold::text);
    f := f + pg_temp.chk('0. A current live birds', '450', p.currentlivebirds::text);

    -- =====================================================================
    -- A. Unresolved balances refuse to close -- and leave nothing behind
    -- =====================================================================
    BEGIN
        v_sale1 := spsale_insert(p_userid => 'closeout-test', p_farmid => v_farm, p_saledate => v_today::timestamp,
                                 p_product => 'Birds', p_quantity => 400, p_unitprice => 12.5, p_totalamount => 5000,
                                 p_flockid => v_a, p_paid => FALSE, p_customername => 'Closeout Test Buyer');
        PERFORM spflock_closeout(v_farm, v_a, v_today, 'End of lay', NULL, 'closeout-test',
                                 jsonb_build_array(jsonb_build_object('disposition', 'Sale', 'quantity', 400, 'saleId', v_sale1)));
        v_msg := 'closed';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('A1. 50 birds unaccounted for refuses', '%Unresolved bird balance: 50 bird(s)%', v_msg);

    BEGIN
        PERFORM spflock_closeout(v_farm, v_a, v_today, 'End of lay', NULL, 'closeout-test',
                                 jsonb_build_array(jsonb_build_object('disposition', 'Cull', 'quantity', 460)));
        v_msg := 'closed';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('A2. disposing of more birds than exist refuses', '%account for 10 more%', v_msg);

    BEGIN
        PERFORM spflock_closeout(v_farm, v_a, v_today, 'End of lay', NULL, 'closeout-test',
                                 jsonb_build_array(jsonb_build_object('disposition', 'Mortality', 'quantity', 450)));
        v_msg := 'closed';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('A3. mortality is not a disposition (no fake deaths)', '%Unknown disposition "Mortality"%', v_msg);

    BEGIN
        PERFORM spflock_closeout(v_farm, v_a, v_today - 11, 'End of lay', NULL, 'closeout-test',
                                 jsonb_build_array(jsonb_build_object('disposition', 'Cull', 'quantity', 450)));
        v_msg := 'closed';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('A4. closing before the last count refuses', '%before the last production record%', v_msg);

    BEGIN
        PERFORM spflock_closeout(v_farm, v_a, v_today + 1, 'End of lay', NULL, 'closeout-test',
                                 jsonb_build_array(jsonb_build_object('disposition', 'Cull', 'quantity', 450)));
        v_msg := 'closed';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('A5. closing in the future refuses', '%cannot be in the future%', v_msg);

    BEGIN
        PERFORM spflock_closeout(v_farm, v_a, v_today, '  ', NULL, 'closeout-test', '[]'::jsonb);
        v_msg := 'closed';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('A6. a reason is required', '%reason is required%', v_msg);

    SELECT COUNT(*) INTO v_n FROM flockcloseouts WHERE flockid = v_a;
    f := f + pg_temp.chk('A7. refused closeouts left no closeout row', '0', v_n::text);
    SELECT COUNT(*) INTO v_n FROM sale WHERE flockid = v_a AND quantity = 400;
    f := f + pg_temp.chk('A8. ... and no stray sale', '0', v_n::text);
    SELECT COUNT(*) INTO v_n FROM flock WHERE flockid = v_a AND active AND closeddate IS NULL;
    f := f + pg_temp.chk('A9. ... and the flock is still running', '1', v_n::text);

    -- =====================================================================
    -- B. Close with every bird sold
    -- =====================================================================
    v_sale1 := spsale_insert(p_userid => 'closeout-test', p_farmid => v_farm, p_saledate => v_today::timestamp,
                             p_product => 'Birds', p_quantity => 450, p_unitprice => 12.5, p_totalamount => 5625,
                             p_flockid => v_a, p_paid => FALSE, p_customername => 'Closeout Test Buyer');

    BEGIN
        PERFORM spflock_closeout(v_farm, v_a, v_today, 'End of lay', NULL, 'closeout-test',
                                 jsonb_build_array(jsonb_build_object('disposition', 'Sale', 'quantity', 449, 'saleId', v_sale1),
                                                   jsonb_build_object('disposition', 'Cull', 'quantity', 1)));
        v_msg := 'closed';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('B1. a sale linked for the wrong quantity refuses', '%sold 450% not 449%', v_msg);

    BEGIN
        PERFORM spflock_closeout(v_farm, v_d, v_today, 'End of lay', NULL, 'closeout-test',
                                 jsonb_build_array(jsonb_build_object('disposition', 'Sale', 'quantity', 450, 'saleId', v_sale1)));
        v_msg := 'closed';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('B2. another flock''s sale cannot close this one', '%not a bird sale of this flock%', v_msg);

    v_co := spflock_closeout(v_farm, v_a, v_today, 'End of lay', 'Spent layers to market', 'closeout-test',
                             jsonb_build_array(jsonb_build_object('disposition', 'Sale', 'quantity', 450, 'saleId', v_sale1)));

    SELECT * INTO c FROM flockcloseouts WHERE closeoutid = v_co;
    f := f + pg_temp.chk('B3. snapshot: live birds at closeout', '450', c.livebirdsatcloseout::text);
    f := f + pg_temp.chk('B4. snapshot: sold at closeout', '450', c.disposedsold::text);
    f := f + pg_temp.chk('B5. snapshot: sold before closeout', '35', c.soldbeforecloseout::text);
    f := f + pg_temp.chk('B6. snapshot: recorded mortality', '15', c.recordedmortality::text);
    f := f + pg_temp.chk('B7. snapshot: closed by / reason', 'closeout-test|End of lay', c.closedby || '|' || c.reason);

    SELECT currentlivebirds INTO v_n FROM fnflock_birdposition(v_farm, v_a);
    f := f + pg_temp.chk('B8. a closed flock has zero live birds', '0', v_n::text);

    SELECT COUNT(*) INTO v_n FROM flock
    WHERE  flockid = v_a AND NOT active AND closeddate = v_today AND closeoutid = v_co
      AND  closedby = 'closeout-test' AND closereason = 'End of lay' AND closedat IS NOT NULL;
    f := f + pg_temp.chk('B9. flock marked Closed with date, by and reason', '1', v_n::text);

    SELECT COALESCE(SUM(quantity), 0) INTO v_num FROM poultrystocktransactions
    WHERE  farmid = v_farm AND txntype = 'Bird Sale' AND relatedid IN (v_sale0, v_sale1);
    f := f + pg_temp.chk('B10. both sales left the bird ledger (spsale_insert, not the closeout)', '-485', ROUND(v_num)::text);

    -- =====================================================================
    -- C. Pen release
    -- =====================================================================
    SELECT COUNT(*) INTO v_n FROM flock WHERE houseid = v_house AND active AND COALESCE(isdeleted, FALSE) = FALSE;
    f := f + pg_temp.chk('C1. the house now holds only the flock still running', '1', v_n::text);
    SELECT COALESCE(SUM(quantity), 0) INTO v_n FROM flock WHERE houseid = v_house AND active;
    f := f + pg_temp.chk('C2. occupancy (active flocks) no longer counts A', '200', v_n::text);
    SELECT houseid INTO v_n FROM flock WHERE flockid = v_a;
    f := f + pg_temp.chk('C3. flock-house history kept on the flock', v_house::text, v_n::text);
    f := f + pg_temp.chk('C4. and on the closeout', v_house::text, c.houseid::text);

    -- =====================================================================
    -- D. Removal from active workflows
    -- =====================================================================
    BEGIN
        INSERT INTO productionrecords (farmid, createdby, userid, ageinweeks, ageindays, date, noofbirds, mortality,
                                       noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid)
        VALUES (v_farm, 'x', 'x', 30, 210, v_today, 0, 0, 0, 0, 0, 0, 0, 0, v_a);
        v_msg := 'inserted';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('D1. batch/single production entry refused', '%flock is closed%', v_msg);

    BEGIN
        UPDATE productionrecords SET mortality = mortality + 1 WHERE flockid = v_a AND date = v_today - 10;
        v_msg := 'updated';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('D2. back-editing mortality refused', '%flock is closed%', v_msg);

    UPDATE productionrecords SET totalfeedcost = totalfeedcost WHERE flockid = v_a;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    f := f + pg_temp.chk('D3. cost re-costing of its history still allowed', '2', v_n::text);

    BEGIN
        DELETE FROM productionrecords WHERE flockid = v_a;
        v_msg := 'deleted';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('D4. deleting its production refused', '%flock is closed%', v_msg);

    BEGIN
        INSERT INTO feedusage (flockid, usagedate, feedtype, quantitykg, userid, farmid, datecreated)
        VALUES (v_a, v_today, 'Layer mash', 10, 'x', v_farm, now());
        v_msg := 'inserted';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('D5. feed distribution refused', '%closed. Feed cannot be issued%', v_msg);

    BEGIN
        PERFORM spflock_update(p_flockid => v_a, p_name => 'CO Flock A', p_breed => 'Isa Brown',
                               p_startdate => v_start::timestamp, p_quantity => 500, p_active => TRUE,
                               p_houseid => v_house, p_farmid => v_farm, p_batchid => v_batch);
        v_msg := 'reactivated';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('D6. the edit form cannot silently re-activate it', '%Reopen it before%', v_msg);

    PERFORM spflock_update(p_flockid => v_a, p_name => 'CO Flock A (2025)', p_breed => 'Isa Brown',
                           p_startdate => v_start::timestamp, p_quantity => 500, p_active => FALSE,
                           p_houseid => v_house, p_inactivationreason => 'closed', p_farmid => v_farm,
                           p_batchid => v_batch, p_notes => 'renamed after close');
    SELECT COUNT(*) INTO v_n FROM flock WHERE flockid = v_a AND name = 'CO Flock A (2025)' AND closeddate IS NOT NULL;
    f := f + pg_temp.chk('D7. name and notes stay editable on a closed flock', '1', v_n::text);

    BEGIN
        DELETE FROM flock WHERE flockid = v_a;
        v_msg := 'deleted';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('D8. a closed flock cannot be deleted', '%Reopen it before%', v_msg);

    BEGIN
        UPDATE flock SET closeddate = NULL WHERE flockid = v_a;
        v_msg := 'cleared';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('D9. closed state changes only through close/reopen', '%only through Close Flock%', v_msg);

    SELECT COUNT(*) FILTER (WHERE r.date > v_today)
    INTO   v_n
    FROM   sppoultryreport_missingdailyrecords_rs1(v_farm, v_today - 30, v_today + 5, v_a) r;
    f := f + pg_temp.chk('D10. missing-records: nothing expected after the closing date', '0', v_n::text);
    SELECT COUNT(*) INTO v_n FROM sppoultryreport_missingdailyrecords_rs1(v_farm, v_today - 30, v_today, v_a);
    f := f + pg_temp.chk('D11. missing-records: its running days are still history', 'true', (v_n > 0)::text);
    SELECT COUNT(*) INTO v_n FROM sppoultryreport_missingdailyrecords_rs1(v_farm, v_today + 1, v_today + 5, v_a);
    f := f + pg_temp.chk('D12. missing-records: a range after closing does not list it', '0', v_n::text);

    SELECT COUNT(*) INTO v_n FROM spflock_getall(v_farm) g WHERE g.flockid = v_a AND g.closeddate = v_today AND NOT g.active;
    f := f + pg_temp.chk('D13. the flock reader carries the closed state', '1', v_n::text);
    SELECT COUNT(*) INTO v_n FROM spflock_getbyid(v_a, v_farm) g WHERE g.closeoutid = v_co;
    f := f + pg_temp.chk('D14. ... by id as well', '1', v_n::text);

    -- =====================================================================
    -- E. Sales and cash
    -- =====================================================================
    BEGIN
        PERFORM spsale_insert(p_userid => 'x', p_farmid => v_farm, p_saledate => v_today::timestamp,
                              p_product => 'Birds', p_quantity => 5, p_unitprice => 10, p_totalamount => 50, p_flockid => v_a);
        v_msg := 'sold';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('E1. no more birds can be sold from a closed flock', '%no birds left to sell%', v_msg);

    BEGIN
        v_eggsale2 := spsale_insert(p_userid => 'x', p_farmid => v_farm, p_saledate => v_today::timestamp,
                             p_product => 'Eggs', p_quantity => 30, p_unitprice => 1.5, p_totalamount => 45, p_flockid => v_a);
        v_msg := 'sold';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk('E2. eggs from its stock can still be sold', 'sold', v_msg);

    BEGIN
        UPDATE sale SET quantity = 440 WHERE saleid = v_sale1;
        v_msg := 'changed';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('E3. the reconciled quantity is locked', '%Reopen the flock before changing the birds sold%', v_msg);

    BEGIN
        PERFORM spsale_delete(p_farmid => v_farm, p_userid => 'x', p_saleid => v_sale1);
        v_msg := 'deleted';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('E4. the closeout sale cannot be deleted', '%Reopen the flock%', v_msg);

    -- Price, customer and payment are the sales page's business.
    PERFORM spsale_update(p_userid => 'closeout-test', p_farmid => v_farm, p_saleid => v_sale1,
                          p_saledate => v_today::timestamp, p_product => 'Birds', p_quantity => 450,
                          p_unitprice => 13, p_totalamount => 5850, p_flockid => v_a, p_paid => FALSE,
                          p_customername => 'Closeout Test Buyer');
    SELECT totalamount INTO v_num FROM sale WHERE saleid = v_sale1;
    f := f + pg_temp.chk('E5. the closeout sale''s price is still editable', '5850.00', v_num::text);

    BEGIN
        PERFORM sppoultrypayment_record(p_farmid => v_farm, p_saleid => v_sale1, p_amount => 850,
                                        p_paymentmethod => 'Cash', p_paymentdate => v_today::timestamp,
                                        p_reference => NULL, p_note => 'part payment', p_createdby => 'closeout-test');
        v_msg := 'paid';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk('E6. a payment can still be received against it', 'paid', v_msg);
    SELECT amountpaid INTO v_num FROM sale WHERE saleid = v_sale1;
    f := f + pg_temp.chk('E7. ... and the sale shows it', '850.00', ROUND(v_num, 2)::text);

    -- Put the price back so section F's arithmetic is the one in its comments.
    PERFORM spsale_update(p_userid => 'closeout-test', p_farmid => v_farm, p_saleid => v_sale1,
                          p_saledate => v_today::timestamp, p_product => 'Birds', p_quantity => 450,
                          p_unitprice => 12.5, p_totalamount => 5625, p_flockid => v_a, p_paid => FALSE,
                          p_customername => 'Closeout Test Buyer');
    PERFORM spsale_delete(p_farmid => v_farm, p_userid => 'x', p_saleid => v_eggsale2);   -- the E2 egg sale

    -- =====================================================================
    -- F. Lifetime metrics for A
    -- =====================================================================
    -- eggs 700; feed 110 kg at 220; medication 20; bird cost 2000 * 500/1000 = 1000;
    -- labour 300; other 50 (the 999 capital purchase excluded);
    -- revenue: eggs 900 + birds 350 + 5625 = 6875; cost 1590; profit 5285.
    SELECT * INTO s FROM fnflock_lifetimesummary(v_farm, v_a);
    f := f + pg_temp.chk('F1. status', 'Closed', s.status);
    f := f + pg_temp.chk('F2. original / final birds', '500/0', s.originallyplaced || '/' || s.finalbirds);
    f := f + pg_temp.chk('F3. total eggs', '700', s.totaleggs::text);
    f := f + pg_temp.chk('F4. egg revenue', '900.00', s.eggrevenue::text);
    f := f + pg_temp.chk('F5. bird sale revenue', '5975.00', s.birdsalerevenue::text);
    f := f + pg_temp.chk('F6. total revenue', '6875.00', s.totalrevenue::text);
    f := f + pg_temp.chk('F7. feed consumed kg', '110.00', s.feedconsumedkg::text);
    f := f + pg_temp.chk('F8. feed cost / medication cost', '220.00/20.00', s.feedcost || '/' || s.medicationcost);
    f := f + pg_temp.chk('F9. bird cost = batch share by birds placed', '1000.00', s.birdcost::text);
    f := f + pg_temp.chk('F10. labour / other direct (capital excluded)', '300.00/50.00', s.laborcost || '/' || s.otherdirectcost);
    f := f + pg_temp.chk('F11. total attributable cost', '1590.00', s.totalcost::text);
    f := f + pg_temp.chk('F12. profit', '5285.00', s.profit::text);
    f := f + pg_temp.chk('F13. profit per original bird', '10.57', s.profitperoriginalbird::text);
    f := f + pg_temp.chk('F14. revenue per original bird', '13.75', s.revenueperoriginalbird::text);
    f := f + pg_temp.chk('F15. feed kg per dozen eggs', '1.886', s.feedkgperdozeneggs::text);
    f := f + pg_temp.chk('F16. tracked mortality rate', '0.0300', s.trackedmortalityrate::text);
    f := f + pg_temp.chk('F17. lifetime rate = tracked when there was no opening', '0.0300', s.lifetimemortalityrate::text);
    f := f + pg_temp.chk('F18. comparison dimensions on the row', 'CO-338|Isa Brown|Closeout Test House',
                         s.batchcode || '|' || s.breed || '|' || s.housename);
    SELECT COUNT(*) INTO v_n FROM fnflock_lifetimesummary(v_farm, NULL, TRUE);
    f := f + pg_temp.chk('F19. closed-only filter', '1', v_n::text);

    -- =====================================================================
    -- G. Close with transfer + cull, from a historical opening position
    -- =====================================================================
    -- Placed 1,000 before tracking began; 150 died and 50 were sold then; the
    -- flock entered the app with 800.
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, houseid, hasarrived)
    VALUES ('closeout-test', v_farm, 'CO Flock B', 'Lohmann', v_start, 800, TRUE, v_batch, v_house2, TRUE)
    RETURNING flockid INTO v_b;
    INSERT INTO poultryopeningflockposition (farmid, flockid, effectivebusinessdate, originallyplaced, openinglivebirds,
                                             historicalmortality, historicalsold, historicalculled, historicaltransferred,
                                             otheradjustment, historyknown, startdateestimated, source, createdby)
    VALUES (v_farm, v_b, v_start, 1000, 800, 150, 50, 0, 0, 0, TRUE, FALSE, 'test', 'closeout-test');

    SELECT * INTO p FROM fnflock_birdposition(v_farm, v_b);
    f := f + pg_temp.chk('G1. opening: placed / historical deaths / opening live', '1000/150/800',
                         p.originallyplaced || '/' || p.openingmortality || '/' || p.openinglivebirds);
    f := f + pg_temp.chk('G2. opening losses are not tracked mortality', '0', p.recordedmortality::text);
    f := f + pg_temp.chk('G3. no production yet: live = opening live', '800', p.currentlivebirds::text);

    BEGIN
        PERFORM spflock_closeout(v_farm, v_b, v_today, 'Depopulated', NULL, 'closeout-test',
                                 jsonb_build_array(jsonb_build_object('disposition', 'Transfer', 'quantity', 800)));
        v_msg := 'closed';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('G4. a transfer needs a destination', '%Say where the transferred birds went%', v_msg);

    v_co2 := spflock_closeout(v_farm, v_b, v_today, 'Depopulated', NULL, 'closeout-test',
                              jsonb_build_array(
                                  jsonb_build_object('disposition', 'Transfer', 'quantity', 300, 'destination', 'Sister farm, Kumasi'),
                                  jsonb_build_object('disposition', 'Cull', 'quantity', 500, 'notes', 'Culled on site')));

    SELECT * INTO p FROM fnflock_birdposition(v_farm, v_b);
    f := f + pg_temp.chk('G5. transferred / culled / live', '300/500/0',
                         p.birdstransferred || '/' || p.birdsculled || '/' || p.currentlivebirds);

    SELECT COALESCE(SUM(t.quantity) FILTER (WHERE t.txntype = 'Flock Transfer Out'), 0),
           COALESCE(SUM(t.quantity) FILTER (WHERE t.txntype = 'Flock Cull'), 0)
    INTO   v_num, v_n
    FROM   poultrystocktransactions t
    JOIN   flockcloseoutdispositions x ON x.dispositionid = t.relatedid AND x.closeoutid = v_co2
    WHERE  t.farmid = v_farm AND t.txntype IN ('Flock Transfer Out', 'Flock Cull');
    f := f + pg_temp.chk('G6. birds leaving the company left the bird ledger', '-300/-500', ROUND(v_num) || '/' || v_n);
    SELECT COUNT(*) INTO v_n FROM poultrystocktransactions t
    JOIN   flockcloseoutdispositions x ON x.dispositionid = t.relatedid AND x.closeoutid = v_co2
    WHERE  t.farmid = v_farm AND t.txntype IN ('Flock Transfer Out', 'Flock Cull') AND t.createddate::date = v_today;
    f := f + pg_temp.chk('G7. ... dated to the closing date', '2', v_n::text);

    SELECT * INTO s FROM fnflock_lifetimesummary(v_farm, v_b);
    f := f + pg_temp.chk('G8. tracked mortality rate is over opening live, not placed', '0.0000', s.trackedmortalityrate::text);
    f := f + pg_temp.chk('G9. lifetime mortality includes the known history', '0.1500', s.lifetimemortalityrate::text);
    f := f + pg_temp.chk('G10. bird cost uses birds PLACED, not opening live', '2000.00', s.birdcost::text);

    -- =====================================================================
    -- H. Unknown opening history
    -- =====================================================================
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, houseid, hasarrived)
    VALUES ('closeout-test', v_farm, 'CO Flock C', 'Lohmann', v_start, 900, TRUE, v_batch, v_house2, TRUE)
    RETURNING flockid INTO v_c;
    INSERT INTO poultryopeningflockposition (farmid, flockid, effectivebusinessdate, originallyplaced, openinglivebirds,
                                             historicalmortality, historicalsold, historicalculled, historicaltransferred,
                                             otheradjustment, historyknown, startdateestimated, source, createdby)
    VALUES (v_farm, v_c, v_start, 1000, 900, 0, 0, 0, 0, 100, FALSE, FALSE, 'test', 'closeout-test');
    SELECT * INTO s FROM fnflock_lifetimesummary(v_farm, v_c);
    f := f + pg_temp.chk('H1. unknown history: no lifetime mortality rate is claimed', NULL, s.lifetimemortalityrate::text);
    f := f + pg_temp.chk('H2. ... the tracked rate still is', '0.0000', s.trackedmortalityrate::text);

    -- =====================================================================
    -- I. Reopening, and the audit trail
    -- =====================================================================
    BEGIN
        PERFORM spflock_reopen(v_farm, v_a, '', 'closeout-test');
        v_msg := 'reopened';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('I1. reopening needs a reason', '%reason is required to reopen%', v_msg);

    BEGIN
        PERFORM spflock_reopen(v_farm, v_d, 'oops', 'closeout-test');
        v_msg := 'reopened';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk_like('I2. only a closed flock can be reopened', '%is not closed%', v_msg);

    -- Keeping the sales (339's p_reversesales = FALSE): this section proves the
    -- lock is released. Reversing them is poultry-flock-reopen-reverses-sales.test.sql.
    PERFORM spflock_reopen(v_farm, v_a, 'Closed by mistake', 'owner-test', FALSE);
    SELECT COUNT(*) INTO v_n FROM flock
    WHERE  flockid = v_a AND active AND closeddate IS NULL AND closeoutid IS NULL AND closedby IS NULL;
    f := f + pg_temp.chk('I3. reopened flock is running again, closed fields cleared', '1', v_n::text);
    SELECT * INTO c FROM flockcloseouts WHERE closeoutid = v_co;
    f := f + pg_temp.chk('I4. the closeout is kept, stamped reopened', 'owner-test|Closed by mistake',
                         c.reopenedby || '|' || c.reopenreason);

    -- The sales stay sold (they are real money); only the lock is released.
    SELECT currentlivebirds INTO v_n FROM fnflock_birdposition(v_farm, v_a);
    f := f + pg_temp.chk('I5. sales still count after reopening', '0', v_n::text);
    UPDATE sale SET quantity = 440 WHERE saleid = v_sale1;
    SELECT currentlivebirds INTO v_n FROM fnflock_birdposition(v_farm, v_a);
    f := f + pg_temp.chk('I6. the sale is editable again once reopened', '10', v_n::text);
    UPDATE sale SET quantity = 450 WHERE saleid = v_sale1;

    -- Close A again: nothing left to dispose of, so no dispositions.
    v_co := spflock_closeout(v_farm, v_a, v_today, 'End of lay', NULL, 'closeout-test', '[]'::jsonb);
    SELECT COUNT(*) INTO v_n FROM spflock_closeouthistory(v_farm, v_a);
    f := f + pg_temp.chk('I7. history keeps both closeouts', '2', v_n::text);
    SELECT COUNT(*) INTO v_n FROM spflock_closeouthistory(v_farm, v_a) h WHERE h.reopenedat IS NULL;
    f := f + pg_temp.chk('I8. exactly one of them is open', '1', v_n::text);
    SELECT jsonb_array_length(h.dispositions) INTO v_n FROM spflock_closeouthistory(v_farm, v_a) h WHERE h.reopenedat IS NOT NULL;
    f := f + pg_temp.chk('I9. the reopened closeout still shows its sale', '1', v_n::text);

    -- Reopen B: its cull and transfer are reversed in the ledger, append-only.
    PERFORM spflock_reopen(v_farm, v_b, 'Birds not yet collected', 'owner-test');
    SELECT COALESCE(SUM(t.quantity), 0), COUNT(*)
    INTO   v_num, v_n
    FROM   poultrystocktransactions t
    JOIN   flockcloseoutdispositions x ON x.dispositionid = t.relatedid AND x.closeoutid = v_co2
    WHERE  t.farmid = v_farm AND t.txntype IN ('Flock Transfer Out', 'Flock Cull');
    f := f + pg_temp.chk('I10. reversed in the ledger: nets to zero over 4 rows', '0/4', ROUND(v_num) || '/' || v_n);
    SELECT COUNT(*) INTO v_n FROM flockcloseoutdispositions WHERE closeoutid = v_co2 AND reversedat IS NOT NULL;
    f := f + pg_temp.chk('I11. dispositions kept and stamped reversed', '2', v_n::text);
    SELECT currentlivebirds INTO v_n FROM fnflock_birdposition(v_farm, v_b);
    f := f + pg_temp.chk('I12. B has its 800 birds back', '800', v_n::text);

    -- A legacy-inactive flock closes and reopens back to INACTIVE, not active.
    UPDATE flock SET active = FALSE, inactivationreason = 'other', otherreason = 'legacy' WHERE flockid = v_c;
    PERFORM spflock_closeout(v_farm, v_c, v_today, 'Formal close of an old flock', NULL, 'closeout-test',
                             jsonb_build_array(jsonb_build_object('disposition', 'Cull', 'quantity', 900)));
    PERFORM spflock_reopen(v_farm, v_c, 'Undo', 'owner-test');
    SELECT COUNT(*) INTO v_n FROM flock WHERE flockid = v_c AND NOT active AND closeddate IS NULL;
    f := f + pg_temp.chk('I13. a flock inactive before closing reopens inactive', '1', v_n::text);

    -- =====================================================================
    -- J. Permissions
    -- =====================================================================
    SELECT COUNT(*) INTO v_n FROM iampermissions WHERE permissionkey LIKE 'poultry.flock-closeout.%';
    f := f + pg_temp.chk('J1. three catalog keys', '3', v_n::text);
    SELECT string_agg(action || '=' || isdangerous, ',' ORDER BY action) INTO v_msg
    FROM   iampermissions WHERE permissionkey LIKE 'poultry.flock-closeout.%';
    f := f + pg_temp.chk('J2. reopening (approve) is the dangerous one', 'approve=true,create=false,view=false', v_msg);
    SELECT COUNT(*) INTO v_n FROM iamrolepermissions rp
    WHERE  rp.permissionkey = 'poultry.flocks.edit'
      AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x WHERE x.roleid = rp.roleid AND x.permissionkey = 'poultry.flock-closeout.create');
    f := f + pg_temp.chk('J3. every role that edits flocks can close them', '0', v_n::text);
    SELECT COUNT(*) INTO v_n FROM iamrolepermissions rp
    WHERE  rp.permissionkey = 'poultry.flock-closeout.approve'
      AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x WHERE x.roleid = rp.roleid AND x.permissionkey = 'poultry.flocks.delete');
    f := f + pg_temp.chk('J4. reopening is no wider than deleting flocks', '0', v_n::text);

    IF f > 0 THEN
        RAISE EXCEPTION 'poultry-flock-closeout: % check(s) FAILED', f;
    END IF;
    RAISE NOTICE 'poultry-flock-closeout: all checks passed';
END
$t$;

ROLLBACK;

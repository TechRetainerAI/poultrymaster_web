-- Behavioural checks for migration 266: consumption reaches Profit & Loss.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates items, purchases and consumption.
--
--   psql ... -X -c "BEGIN;" -f poultry-consumption-recognition.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 266
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- These are the brief's own worked examples, section by section.
--
--   A   59  expensed feed: buy 100 kg for 1,000, use 20 -> NO further expense
--   B   60  deferred feed: buy 100 kg for 1,000, use 20 -> +200, 800 left
--   C   62  medication: 500 ml for 50,000, use 50 -> +5,000, 45,000 left
--   D   66  mixed layers: one draw across an expensed lot and a deferred one
--   E   69  reversal: stock, deferred cost and the expense all come back
--   F   20  consumption moves NO cash and creates NO supplier payment
--   G   73  supplier payment independence
--   H       an edit re-recognises without drifting
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **The same cedi is never expensed twice.** A is the half everyone forgets:
-- stock that was already paid for and expensed must cost nothing more when it
-- is eaten. D is the same claim at lot level, where it is easiest to get wrong.

-- -----------------------------------------------------------------------------
-- productionrecordfeeds carries a foreign key to productionrecords, so a
-- consumption test needs real records rather than invented ids. This makes the
-- smallest row the NOT NULL columns will accept and hands back its id.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.zz_makerecord(p_farmid text)
RETURNS integer
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_id integer;
BEGIN
    INSERT INTO productionrecords
        (farmid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
         noofbirdsleft, feedkg, production9am, production12pm, production4pm,
         totalproduction, sourcetype)
    VALUES (p_farmid, 'ZZ tester', 20, 140, CURRENT_DATE, 100, 0, 100, 0, 0, 0, 0, 0,
            'ManualSingleFlock')
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$fn$;


DO $t$
DECLARE
    v_farm text;
    v_feedP integer;  -- finished feed, expensed at purchase (item override)
    v_feedC integer;  -- finished feed, deferred
    v_med   integer;  -- medication, deferred
    v_lot   integer;
    v_exp0 numeric; v_exp1 numeric; v_exp2 numeric;
    v_cash0 numeric; v_pay0 integer; v_tx0 integer;
    v_rec integer;
    -- One real production record per scenario.
    v_r1 integer; v_r2 integer; v_r3 integer; v_r4 integer;
    v_r5 integer; v_r6 integer; v_r7 integer;
    v_acct integer;
BEGIN
    SELECT f.farmid INTO v_farm
    FROM   farms f
    WHERE  f.type = 'Poultry'
      AND  f.farmid ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ORDER  BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No uuid-shaped poultry company to test against.'; END IF;
    RAISE NOTICE '   using poultry farm %', v_farm;

    v_r1 := pg_temp.zz_makerecord(v_farm);
    v_r2 := pg_temp.zz_makerecord(v_farm);
    v_r3 := pg_temp.zz_makerecord(v_farm);
    v_r4 := pg_temp.zz_makerecord(v_farm);
    v_r5 := pg_temp.zz_makerecord(v_farm);
    v_r6 := pg_temp.zz_makerecord(v_farm);
    v_r7 := pg_temp.zz_makerecord(v_farm);

    -- The farm may have no cash accounts at all, in which case "cash did not
    -- move" would pass by comparing zero with zero and "cash DID move" could
    -- never pass. Give it one with money in it so both are real questions.
    INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance,
                                     currentbalance, allownegativebalance, isactive)
    VALUES (v_farm, 'ZZ CR Bank', 'BankAccount', 500000, 500000, FALSE, TRUE)
    RETURNING poultrycashaccountid INTO v_acct;

    DELETE FROM poultryfinancialsettings WHERE farmid = v_farm;
    PERFORM sppoultryfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_CONSUMED', NULL, 'ZZ tester');

    v_feedP := sppoultryrawmaterialitem_insert(v_farm, 'ZZ CR Feed Purchased', 'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg',
                                               'EXPENSE_WHEN_PURCHASED');
    v_feedC := sppoultryrawmaterialitem_insert(v_farm, 'ZZ CR Feed Deferred',  'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg');
    v_med   := sppoultryrawmaterialitem_insert(v_farm, 'ZZ CR Vaccine',        'Medication',   'ml', 0, NULL, 'FIFO', 'ml');

    -- =====================================================================
    -- A. Expensed at purchase: using it costs nothing more. (brief 59)
    -- =====================================================================
    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp0 FROM expense e WHERE e.farmid::text = v_farm;

    PERFORM sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_feedP,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 100, p_unitcost => 10, p_totalcost => 1000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 1000, p_createdby => 'ZZ tester');

    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp1 FROM expense e WHERE e.farmid::text = v_farm;
    RAISE NOTICE 'A1. purchase expensed 1000 expect  1000.00  got %', (v_exp1 - v_exp0);

    -- Use 20 kg.
    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_r1, p_createdby => 'ZZ tester',
        p_feedsjson => ('[{"itemId":' || v_feedP::text || ',"qty":20}]'));

    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp2 FROM expense e WHERE e.farmid::text = v_farm;
    -- **THE** check on this side. The cost was already paid and already booked.
    RAISE NOTICE 'A2. using it costs NOTHING expect     0.00  got %', (v_exp2 - v_exp1);
    RAISE NOTICE 'A3. but stock did fall    expect    80.00  got %',
        (SELECT currentquantity FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = v_feedP);
    RAISE NOTICE 'A4. no consumption expense expect        0  got %',
        (SELECT COUNT(*) FROM expense WHERE farmid::text = v_farm
          AND sourcetype = 'PoultryFeedConsumption' AND sourceid = v_r1);

    -- =====================================================================
    -- B. Deferred: purchase costs nothing, using it does. (brief 60)
    -- =====================================================================
    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp0 FROM expense e WHERE e.farmid::text = v_farm;

    v_lot := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_feedC,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 100, p_unitcost => 10, p_totalcost => 1000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 1000, p_createdby => 'ZZ tester');

    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp1 FROM expense e WHERE e.farmid::text = v_farm;
    RAISE NOTICE 'B1. purchase expensed 0    expect     0.00  got %', (v_exp1 - v_exp0);
    RAISE NOTICE 'B2. deferred value is 1000 expect  1000.00  got %',
        (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot);

    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_r2, p_createdby => 'ZZ tester',
        p_feedsjson => ('[{"itemId":' || v_feedC::text || ',"qty":20}]'));

    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp2 FROM expense e WHERE e.farmid::text = v_farm;
    -- **THE** check on this side.
    RAISE NOTICE 'B3. using it costs 200     expect   200.00  got %', (v_exp2 - v_exp1);
    RAISE NOTICE 'B4. deferred value is 800  expect   800.00  got %',
        (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot);
    RAISE NOTICE 'B5. stock is 80            expect    80.00  got %',
        (SELECT currentquantity FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = v_feedC);
    -- It lands in the FEED line of the P&L, not in Other.
    RAISE NOTICE 'B6. category is Feed Cost  expect Feed Cost  got %',
        (SELECT category FROM expense WHERE farmid::text = v_farm
          AND sourcetype = 'PoultryFeedConsumption' AND sourceid = v_r2 LIMIT 1);
    RAISE NOTICE 'B7. and it is NonCash      expect  NonCash  got %',
        (SELECT paymentmethod FROM expense WHERE farmid::text = v_farm
          AND sourcetype = 'PoultryFeedConsumption' AND sourceid = v_r2 LIMIT 1);

    -- =====================================================================
    -- C. Medication, in ml. (brief 62)
    -- =====================================================================
    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp1 FROM expense e WHERE e.farmid::text = v_farm;

    PERFORM sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_med,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 500, p_unitcost => 100, p_totalcost => 50000,
        p_productionunit => 'ml', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 50000, p_createdby => 'ZZ tester');

    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_r3, p_createdby => 'ZZ tester',
        p_medicationsjson => ('[{"itemId":' || v_med::text || ',"qty":50}]'));

    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp2 FROM expense e WHERE e.farmid::text = v_farm;
    RAISE NOTICE 'C1. 50 ml costs 5000       expect  5000.00  got %', (v_exp2 - v_exp1);
    RAISE NOTICE 'C2. 45000 still deferred   expect 45000.00  got %',
        (SELECT COALESCE(SUM(deferredremainingcost), 0) FROM poultryrawmaterialpurchases
          WHERE farmid = v_farm AND poultryrawmaterialitemid = v_med);
    -- It lands in the MEDICATION line, not with the feed.
    RAISE NOTICE 'C3. category is Medication expect Medication  got %',
        (SELECT category FROM expense WHERE farmid::text = v_farm
          AND sourcetype = 'PoultryMedicationConsumption' AND sourceid = v_r3 LIMIT 1);
    RAISE NOTICE 'C4. no feed expense for it expect        0  got %',
        (SELECT COUNT(*) FROM expense WHERE farmid::text = v_farm
          AND sourcetype = 'PoultryFeedConsumption' AND sourceid = v_r3);

    -- =====================================================================
    -- D. Mixed layers in one draw. (brief 66)
    -- =====================================================================
    DECLARE
        v_mix integer; v_lotOld integer; v_lotNew integer;
    BEGIN
        v_mix := sppoultryrawmaterialitem_insert(v_farm, 'ZZ CR Mixed Feed', 'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg',
                                                 'EXPENSE_WHEN_PURCHASED');
        -- An old lot bought while the item was expensed at purchase.
        v_lotOld := sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_mix,
            p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc') - interval '2 days',
            p_quantity => 100, p_unitcost => 10, p_totalcost => 1000,
            p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 1000, p_createdby => 'ZZ tester');

        -- The item is switched to deferred; the NEXT lot is deferred, the old one
        -- keeps its own snapshot.
        PERFORM sppoultryrawmaterialitem_update(
            v_mix, v_farm, 'ZZ CR Mixed Feed', 'FinishedFeed', 'kg', 0, TRUE, NULL, 'FIFO', 'kg',
            'EXPENSE_WHEN_CONSUMED', TRUE);
        v_lotNew := sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_mix,
            p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc') - interval '1 day',
            p_quantity => 100, p_unitcost => 10, p_totalcost => 1000,
            p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 1000, p_createdby => 'ZZ tester');

        -- The old lot kept its own treatment. Changing the item did not
        -- reinterpret it. (brief 39)
        RAISE NOTICE 'D1. old lot kept its own   expect EXPENSE_WHEN_PURCHASED  got %',
            (SELECT costrecognitionmethod FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lotOld);
        RAISE NOTICE 'D2. new lot is deferred    expect EXPENSE_WHEN_CONSUMED  got %',
            (SELECT costrecognitionmethod FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lotNew);

        SELECT COALESCE(SUM(e.amount), 0) INTO v_exp1 FROM expense e WHERE e.farmid::text = v_farm;

        -- FIFO 150 kg: all 100 of the old lot, then 50 of the new one.
        PERFORM sppoultryproductionrawmaterialsync(
            p_farmid => v_farm, p_productionid => v_r4, p_createdby => 'ZZ tester',
            p_feedsjson => ('[{"itemId":' || v_mix::text || ',"qty":150}]'));

        SELECT COALESCE(SUM(e.amount), 0) INTO v_exp2 FROM expense e WHERE e.farmid::text = v_farm;
        -- 150 kg physically gone, but only the 50 kg from the deferred lot costs.
        RAISE NOTICE 'D3. only the deferred 500  expect   500.00  got %', (v_exp2 - v_exp1);
        RAISE NOTICE 'D4. old lot emptied        expect     0.00  got %',
            (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lotOld);
        RAISE NOTICE 'D5. new lot half gone      expect    50.00  got %',
            (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lotNew);
        RAISE NOTICE 'D6. 500 still deferred     expect   500.00  got %',
            (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lotNew);
    END;

    -- =====================================================================
    -- E. Consumption moves no cash and owes nobody. (brief 20)
    -- =====================================================================
    SELECT COALESCE(SUM(a.currentbalance), 0) INTO v_cash0 FROM poultrycashaccounts a WHERE a.farmid = v_farm;
    SELECT COUNT(*) INTO v_pay0 FROM poultrysupplierpayments WHERE farmid = v_farm;
    SELECT COUNT(*) INTO v_tx0  FROM poultrycashtransactions WHERE farmid = v_farm;

    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_r5, p_createdby => 'ZZ tester',
        p_feedsjson => ('[{"itemId":' || v_feedC::text || ',"qty":10}]'));

    RAISE NOTICE 'E1. cash did not move     expect        t  got %',
        ((SELECT COALESCE(SUM(a.currentbalance), 0) FROM poultrycashaccounts a WHERE a.farmid = v_farm) = v_cash0);
    RAISE NOTICE 'E2. no supplier payment    expect        t  got %',
        ((SELECT COUNT(*) FROM poultrysupplierpayments WHERE farmid = v_farm) = v_pay0);
    RAISE NOTICE 'E3. no cash transaction    expect        t  got %',
        ((SELECT COUNT(*) FROM poultrycashtransactions WHERE farmid = v_farm) = v_tx0);
    -- And the non-cash expense stays out of the cash-flow report.
    RAISE NOTICE 'E4. invisible to cash flow expect        0  got %',
        (SELECT COUNT(*) FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'Expense'
            AND r.sourcerowid IN (SELECT expenseid FROM expense WHERE farmid::text = v_farm
                                   AND sourcetype IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption')));
    -- ...and out of payables, so consuming stock never becomes a debt.
    RAISE NOTICE 'E5. and out of payables    expect        0  got %',
        (SELECT COUNT(*) FROM fnpoultrypayables(v_farm) d
          WHERE d.documenttype = 'Expense'
            AND d.documentid IN (SELECT expenseid FROM expense WHERE farmid::text = v_farm
                                  AND sourcetype IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption')));

    -- =====================================================================
    -- F. Reversal gives back the stock, the cost and the expense. (brief 69)
    -- =====================================================================
    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp1 FROM expense e WHERE e.farmid::text = v_farm;

    -- Empty lines = the delete path: a pure reversal.
    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_r2, p_createdby => 'ZZ tester');

    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp2 FROM expense e WHERE e.farmid::text = v_farm;
    -- The 200 from section B comes back off.
    RAISE NOTICE 'F1. expense reversed -200  expect  -200.00  got %', (v_exp2 - v_exp1);
    -- Append-only: the original is still there, with an opposite beside it.
    RAISE NOTICE 'F2. both rows kept         expect        2  got %',
        (SELECT COUNT(*) FROM expense WHERE farmid::text = v_farm
          AND sourcetype = 'PoultryFeedConsumption' AND sourceid = v_r2);
    RAISE NOTICE 'F3. and they net to zero   expect     0.00  got %',
        (SELECT COALESCE(SUM(amount), 0) FROM expense WHERE farmid::text = v_farm
          AND sourcetype = 'PoultryFeedConsumption' AND sourceid = v_r2);
    -- The deferred cost is back on the exact lot it came from, so consuming the
    -- stock again will recognise it again -- and only once.
    -- B took 20 kg and E took another 10, leaving 70. Reversing only B's record
    -- gives back its 20 -- so 90 kg and 900 of deferred cost, NOT the full 100.
    -- A reversal restores what THAT record drew, not the lot's whole history.
    RAISE NOTICE 'F4. deferred restored      expect   900.00  got %',
        (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot);
    RAISE NOTICE 'F5. and the stock with it  expect    90.00  got %',
        (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot);
    -- E's 10 kg is untouched by B's reversal: 100 of deferred cost is still
    -- recognised, and still only once.
    RAISE NOTICE 'F6. E is left alone        expect   100.00  got %',
        (SELECT COALESCE(SUM(amount), 0) FROM expense WHERE farmid::text = v_farm
          AND sourcetype = 'PoultryFeedConsumption' AND sourceid = v_r5);

    -- =====================================================================
    -- G. Supplier payment independence. (brief 73)
    -- =====================================================================
    DECLARE
        v_gitem integer; v_glot integer; v_gsup integer; v_gexp numeric; v_gcash numeric;
    BEGIN
        v_gitem := sppoultryrawmaterialitem_insert(v_farm, 'ZZ CR Credit Maize', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'kg');
        v_gsup  := fnpoultrysupplier_resolve(v_farm, 'ZZ CR Supplier', 'ZZ tester');

        SELECT COALESCE(SUM(e.amount), 0) INTO v_gexp FROM expense e WHERE e.farmid::text = v_farm;

        -- 100,000 on credit, deferred.
        v_glot := sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_gitem,
            p_suppliername => 'ZZ CR Supplier', p_supplierid => v_gsup,
            p_purchasedate => (now() at time zone 'utc'),
            p_quantity => 10000, p_unitcost => 10, p_totalcost => 100000,
            p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Credit', p_amountpaid => 0, p_createdby => 'ZZ tester');

        -- The insert SP takes no cash account; the pay-balance path reads it off
        -- the purchase row. Set it, or the payment has nowhere to draw from and
        -- G5 could not tell "no cash moved" from "no account exists".
        UPDATE poultryrawmaterialpurchases SET poultrycashaccountid = v_acct
        WHERE  poultryrawmaterialpurchaseid = v_glot;

        RAISE NOTICE 'G1. P&L still 0           expect     0.00  got %',
            ((SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm) - v_gexp);
        RAISE NOTICE 'G2. but owed 100000       expect 100000.00  got %',
            (SELECT (totalcost - amountpaid) FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_glot);

        -- Pay 40,000. Money moves; the P&L does not.
        SELECT COALESCE(SUM(a.currentbalance), 0) INTO v_gcash FROM poultrycashaccounts a WHERE a.farmid = v_farm;
        PERFORM sppoultryrawmaterialpurchase_paybalance(
            v_glot, v_farm, 40000, 'Cash', (now() at time zone 'utc'), 'ZZ tester');

        RAISE NOTICE 'G3. P&L STILL 0           expect     0.00  got %',
            ((SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm) - v_gexp);
        RAISE NOTICE 'G4. debt down to 60000    expect 60000.00  got %',
            (SELECT (totalcost - amountpaid) FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_glot);
        RAISE NOTICE 'G5. and cash DID move     expect        t  got %',
            ((SELECT COALESCE(SUM(a.currentbalance), 0) FROM poultrycashaccounts a WHERE a.farmid = v_farm) < v_gcash);

        -- Now consume 1,000 kg = 10,000 of cost. THAT is when the P&L moves.
        PERFORM sppoultryproductionrawmaterialsync(
            p_farmid => v_farm, p_productionid => v_r6, p_createdby => 'ZZ tester',
            p_feedsjson => ('[{"itemId":' || v_gitem::text || ',"qty":1000}]'));

        RAISE NOTICE 'G6. consumption costs 10000 expect 10000.00  got %',
            ((SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm) - v_gexp);
        -- Paying more still does not touch the P&L.
        PERFORM sppoultryrawmaterialpurchase_paybalance(
            v_glot, v_farm, 10000, 'Cash', (now() at time zone 'utc'), 'ZZ tester');
        RAISE NOTICE 'G7. paying more adds none expect 10000.00  got %',
            ((SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm) - v_gexp);
    END;

    -- =====================================================================
    -- H. Editing re-recognises without drifting.
    -- =====================================================================
    DECLARE
        v_hexp numeric;
    BEGIN
        SELECT COALESCE(SUM(e.amount), 0) INTO v_hexp FROM expense e WHERE e.farmid::text = v_farm;

        -- Record v_r7 uses 10 kg, then is edited to 30 kg, then to 5 kg.
        PERFORM sppoultryproductionrawmaterialsync(
            p_farmid => v_farm, p_productionid => v_r7, p_createdby => 'ZZ tester',
            p_feedsjson => ('[{"itemId":' || v_feedC::text || ',"qty":10}]'));
        PERFORM sppoultryproductionrawmaterialsync(
            p_farmid => v_farm, p_productionid => v_r7, p_createdby => 'ZZ tester',
            p_feedsjson => ('[{"itemId":' || v_feedC::text || ',"qty":30}]'));
        PERFORM sppoultryproductionrawmaterialsync(
            p_farmid => v_farm, p_productionid => v_r7, p_createdby => 'ZZ tester',
            p_feedsjson => ('[{"itemId":' || v_feedC::text || ',"qty":5}]'));

        -- Three edits later, the net recognition is for 5 kg -- 50 -- not for
        -- 10 + 30 + 5. Each edit gave back what the last one took.
        RAISE NOTICE 'H1. net is the LAST edit   expect    50.00  got %',
            ((SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm) - v_hexp);
        RAISE NOTICE 'H2. and the rows sum to it expect    50.00  got %',
            (SELECT COALESCE(SUM(amount), 0) FROM expense WHERE farmid::text = v_farm
              AND sourcetype = 'PoultryFeedConsumption' AND sourceid = v_r7);
        -- Nothing was deleted on the way; every step is on the record.
        RAISE NOTICE 'H3. append-only throughout expect        t  got %',
            ((SELECT COUNT(*) FROM expense WHERE farmid::text = v_farm
               AND sourcetype = 'PoultryFeedConsumption' AND sourceid = v_r7) >= 5);
    END;
END
$t$;

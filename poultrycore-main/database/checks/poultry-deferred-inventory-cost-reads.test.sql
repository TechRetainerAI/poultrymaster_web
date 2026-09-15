-- Behavioural checks for migration 288: the deferred-cost read surface.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates items, purchases and consumption.
--
--   psql ... -X -c "BEGIN;" -f poultry-deferred-inventory-cost-reads.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 288
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- WHAT THIS FILE DOES *NOT* RE-TEST
-- ---------------------------------
-- 288 adds no writer. Whether the right amount reaches the P&L is settled in
-- poultry-consumption-recognition.test.sql and is not repeated here -- the
-- brief's tests 1, 3, 5, 6, 7, 9 and 10 all live there. Re-asserting them
-- against a read would only prove the read agrees with itself.
--
-- What IS tested here is the claim 288 actually makes: that the numbers on the
-- page can be taken apart and add up.
--
--   A   the purchase row: deferred basis, recognised, remaining, progress
--   B   multi-layer draw -- BOTH allocations persisted and readable (test 2)
--   C   the breakdown reads back the exact FIFO split, not an average (22)
--   D   mixed methods in one draw: per-LOT labels, not per-item (8)
--   E   status ladder: not yet -> partly -> fully expensed (13, 14)
--   F   summary cards equal the sum of the rows they sit above
--   G   scope filters, and what RECOGNIZED deliberately leaves out
--   H   historical integrity: a later purchase does not restate an old draw (11)
--   I   reversal: the balance comes back and the history says so (7)
--   J   the Exception flag fires on a stranded lot (24)
--   K   re-running the same sync does not double-count (test 4)
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **Every figure decomposes.** A purchase's recognised total must equal the sum
-- of the history rows underneath it (A6/B6), and the summary must equal the sum
-- of the purchase rows (F). If either fails, the page is showing a number the
-- owner cannot take apart -- which is the whole thing this phase set out to fix.

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
    v_item integer;   -- deferred feed
    v_mix  integer;   -- feed used for the mixed-method draw
    v_strand integer; -- feed used for the stranded-lot check
    v_p1 integer; v_p2 integer; v_p3 integer;
    v_lotP integer; v_lotC integer; v_lotS integer;
    v_r1 integer; v_r2 integer; v_r3 integer; v_r4 integer; v_r5 integer;
    v_n integer; v_a numeric; v_b numeric;
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

    DELETE FROM poultryfinancialsettings WHERE farmid = v_farm;
    PERFORM sppoultryfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_CONSUMED', NULL, 'ZZ tester');

    -- =====================================================================
    -- A. The purchase row. Buy 1,000 kg at 5; use 100. (brief test 1)
    -- =====================================================================
    v_item := sppoultryrawmaterialitem_insert(v_farm, 'ZZ DR Feed', 'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg');

    v_p1 := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_item,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 1000, p_unitcost => 5, p_totalcost => 5000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 5000, p_createdby => 'ZZ tester');

    RAISE NOTICE 'A1. status before any use  expect Not yet expensed  got %',
        (SELECT status FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_p1);

    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_r1, p_createdby => 'ZZ tester',
        p_feedsjson => ('[{"itemId":' || v_item::text || ',"qty":100}]'));

    RAISE NOTICE 'A2. recognised so far      expect   500.00  got %',
        (SELECT recognizedcost FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_p1);
    RAISE NOTICE 'A3. still deferred         expect  4500.00  got %',
        (SELECT deferredremainingcost FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_p1);
    RAISE NOTICE 'A4. quantity remaining     expect   900.00  got %',
        (SELECT remainingquantity FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_p1);
    RAISE NOTICE 'A5. progress percent       expect    10.00  got %',
        (SELECT recognitionpercent FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_p1);
    -- **THE** decomposition check: the headline equals its own history.
    RAISE NOTICE 'A6. history sums to it     expect   500.00  got %',
        (SELECT COALESCE(SUM(recognizedcost), 0)
           FROM sppoultrydeferredpurchase_history(v_farm, v_p1));
    RAISE NOTICE 'A7. and the two counts agree expect  0.00  got %',
        (SELECT recognitiondrift FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_p1);
    RAISE NOTICE 'A8. status is now          expect Partly expensed  got %',
        (SELECT status FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_p1);

    -- =====================================================================
    -- B/C. FIFO across two lots: 100 @ 5 then 200 @ 8, draw 150. (test 2, 22)
    --
    -- Expect 100x5 = 500 from the first and 50x8 = 400 from the second, an
    -- operational cost of 900 and an effective 6.00/kg -- which is NOT a rate
    -- either lot was bought at, and is exactly why the split has to be stored.
    -- =====================================================================
    DECLARE
        v_fifo integer; v_l1 integer; v_l2 integer;
    BEGIN
        v_fifo := sppoultryrawmaterialitem_insert(v_farm, 'ZZ DR FIFO Feed', 'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg');

        v_l1 := sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_fifo,
            p_suppliername => 'ZZ Supplier', p_purchasedate => ((now() at time zone 'utc') - interval '2 days'),
            p_quantity => 100, p_unitcost => 5, p_totalcost => 500,
            p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 500, p_createdby => 'ZZ tester');
        v_l2 := sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_fifo,
            p_suppliername => 'ZZ Supplier', p_purchasedate => ((now() at time zone 'utc') - interval '1 day'),
            p_quantity => 200, p_unitcost => 8, p_totalcost => 1600,
            p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 1600, p_createdby => 'ZZ tester');

        PERFORM sppoultryproductionrawmaterialsync(
            p_farmid => v_farm, p_productionid => v_r2, p_createdby => 'ZZ tester',
            p_feedsjson => ('[{"itemId":' || v_fifo::text || ',"qty":150}]'));

        RAISE NOTICE 'B1. breakdown has 2 layers expect        2  got %',
            (SELECT COUNT(*) FROM sppoultryconsumption_costbreakdown(v_farm, v_r2));
        RAISE NOTICE 'B2. older lot drawn 100 kg expect   100.00  got %',
            (SELECT quantitydrawn FROM sppoultryconsumption_costbreakdown(v_farm, v_r2)
              WHERE poultryrawmaterialpurchaseid = v_l1);
        RAISE NOTICE 'B3.   at 5.00 = 500        expect   500.00  got %',
            (SELECT operationalcost FROM sppoultryconsumption_costbreakdown(v_farm, v_r2)
              WHERE poultryrawmaterialpurchaseid = v_l1);
        RAISE NOTICE 'B4. newer lot drawn 50 kg  expect    50.00  got %',
            (SELECT quantitydrawn FROM sppoultryconsumption_costbreakdown(v_farm, v_r2)
              WHERE poultryrawmaterialpurchaseid = v_l2);
        RAISE NOTICE 'B5.   at 8.00 = 400        expect   400.00  got %',
            (SELECT operationalcost FROM sppoultryconsumption_costbreakdown(v_farm, v_r2)
              WHERE poultryrawmaterialpurchaseid = v_l2);
        RAISE NOTICE 'B6. total operational 900  expect   900.00  got %',
            (SELECT SUM(operationalcost) FROM sppoultryconsumption_costbreakdown(v_farm, v_r2));
        -- The blended rate is a DISPLAY figure derived from the split, never
        -- the other way round.
        RAISE NOTICE 'B7. effective rate 6.00/kg expect     6.00  got %',
            (SELECT ROUND(SUM(operationalcost) / NULLIF(SUM(quantitydrawn), 0), 2)
               FROM sppoultryconsumption_costbreakdown(v_farm, v_r2));
        RAISE NOTICE 'B8. the older lot is spent expect Fully expensed  got %',
            (SELECT status FROM fnpoultrydeferredpurchase_rows(v_farm)
              WHERE poultryrawmaterialpurchaseid = v_l1);
        RAISE NOTICE 'B9. the newer one partly   expect Partly expensed  got %',
            (SELECT status FROM fnpoultrydeferredpurchase_rows(v_farm)
              WHERE poultryrawmaterialpurchaseid = v_l2);

        -- =================================================================
        -- H. Historical integrity: buying more must not restate the draw
        --    that already happened. (brief test 11)
        -- =================================================================
        PERFORM sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_fifo,
            p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
            p_quantity => 500, p_unitcost => 99, p_totalcost => 49500,
            p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 49500, p_createdby => 'ZZ tester');

        RAISE NOTICE 'H1. old draw still 900     expect   900.00  got %',
            (SELECT SUM(operationalcost) FROM sppoultryconsumption_costbreakdown(v_farm, v_r2));
        RAISE NOTICE 'H2. old lot still 5.00/kg  expect     5.00  got %',
            (SELECT unitcostatdraw FROM sppoultryconsumption_costbreakdown(v_farm, v_r2)
              WHERE poultryrawmaterialpurchaseid = v_l1);
    END;

    -- =====================================================================
    -- D. Mixed methods in ONE draw. The label is per LOT. (brief 8)
    --
    -- An expensed lot of 100 @ 5 and a deferred lot of 50 @ 8, drawn together:
    -- operational 900, but only the deferred 400 may reach the P&L again.
    -- =====================================================================
    DECLARE
        v_before numeric; v_after numeric;
    BEGIN
        v_mix := sppoultryrawmaterialitem_insert(v_farm, 'ZZ DR Mixed', 'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg',
                                                 'EXPENSE_WHEN_PURCHASED');
        v_lotP := sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_mix,
            p_suppliername => 'ZZ Supplier', p_purchasedate => ((now() at time zone 'utc') - interval '2 days'),
            p_quantity => 100, p_unitcost => 5, p_totalcost => 500,
            p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 500, p_createdby => 'ZZ tester');

        -- Flip the item to deferred, so the NEXT lot carries a different
        -- snapshot from the one above. This is the situation the per-lot rule
        -- exists for.
        PERFORM sppoultryrawmaterialitem_update(
            p_poultryrawmaterialitemid => v_mix, p_farmid => v_farm,
            p_itemname => 'ZZ DR Mixed', p_category => 'FinishedFeed', p_unitofmeasure => 'kg',
            p_minimumstockalert => 0, p_isactive => TRUE, p_notes => NULL,
            p_usagemethod => 'FIFO', p_purchaseunitofmeasure => 'kg',
            p_costrecognitionoverride => 'EXPENSE_WHEN_CONSUMED',
            p_setcostrecognitionoverride => TRUE);

        v_lotC := sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_mix,
            p_suppliername => 'ZZ Supplier', p_purchasedate => ((now() at time zone 'utc') - interval '1 day'),
            p_quantity => 50, p_unitcost => 8, p_totalcost => 400,
            p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 400, p_createdby => 'ZZ tester');

        SELECT COALESCE(SUM(e.amount), 0) INTO v_before FROM expense e WHERE e.farmid::text = v_farm;

        PERFORM sppoultryproductionrawmaterialsync(
            p_farmid => v_farm, p_productionid => v_r3, p_createdby => 'ZZ tester',
            p_feedsjson => ('[{"itemId":' || v_mix::text || ',"qty":150}]'));

        SELECT COALESCE(SUM(e.amount), 0) INTO v_after FROM expense e WHERE e.farmid::text = v_farm;

        RAISE NOTICE 'D1. operational cost 900   expect   900.00  got %',
            (SELECT SUM(operationalcost) FROM sppoultryconsumption_costbreakdown(v_farm, v_r3));
        -- **THE** double-count check, read through the breakdown.
        RAISE NOTICE 'D2. newly recognised 400   expect   400.00  got %',
            (SELECT SUM(recognizedcost) FROM sppoultryconsumption_costbreakdown(v_farm, v_r3));
        RAISE NOTICE 'D3. already expensed 500   expect   500.00  got %',
            (SELECT SUM(operationalcost - recognizedcost)
               FROM sppoultryconsumption_costbreakdown(v_farm, v_r3));
        RAISE NOTICE 'D4. ONE expense of 400     expect   400.00  got %', (v_after - v_before);
        RAISE NOTICE 'D5. and it IS one row      expect        1  got %',
            (SELECT COUNT(*) FROM expense WHERE farmid::text = v_farm
              AND sourcetype = 'PoultryFeedConsumption' AND sourceid = v_r3);
        -- The two rows of one breakdown disagree, and must.
        RAISE NOTICE 'D6. old lot labelled       expect Expensed at purchase  got %',
            (SELECT recognitionlabel FROM sppoultryconsumption_costbreakdown(v_farm, v_r3)
              WHERE poultryrawmaterialpurchaseid = v_lotP);
        RAISE NOTICE 'D7. new lot labelled       expect Expense when used  got %',
            (SELECT recognitionlabel FROM sppoultryconsumption_costbreakdown(v_farm, v_r3)
              WHERE poultryrawmaterialpurchaseid = v_lotC);
        -- An expensed lot still shows its usage in history -- with zero
        -- recognised. Hiding it would lose the audit trail.
        RAISE NOTICE 'D8. expensed lot has hist. expect        1  got %',
            (SELECT COUNT(*) FROM sppoultrydeferredpurchase_history(v_farm, v_lotP));
        RAISE NOTICE 'D9.   recognising nothing  expect     0.00  got %',
            (SELECT COALESCE(SUM(recognizedcost), 0)
               FROM sppoultrydeferredpurchase_history(v_farm, v_lotP));
    END;

    -- =====================================================================
    -- F. The cards equal the rows. A summary that can drift from the table
    --    under it is worse than no summary.
    -- =====================================================================
    SELECT COALESCE(SUM(r.deferredremainingcost), 0) INTO v_a
    FROM   sppoultrydeferredpurchase_getall(v_farm, 'DEFERRED') r;
    SELECT s.remainingdeferredcost INTO v_b
    FROM   sppoultrydeferredpurchase_summary(v_farm, 'DEFERRED') s;
    RAISE NOTICE 'F1. cards match rows       expect     0.00  got %', (v_a - v_b);

    SELECT COUNT(*) INTO v_n FROM sppoultrydeferredpurchase_getall(v_farm, 'DEFERRED');
    RAISE NOTICE 'F2. count matches too      expect        0  got %',
        (v_n - (SELECT purchasecount FROM sppoultrydeferredpurchase_summary(v_farm, 'DEFERRED')));

    -- =====================================================================
    -- G. Scope. RECOGNIZED means "was deferred and now is not" -- an
    --    expense-at-purchase lot was never deferred and must not be counted
    --    as an achievement of this mechanism.
    -- =====================================================================
    RAISE NOTICE 'G1. DEFERRED excludes spent expect       0  got %',
        (SELECT COUNT(*) FROM sppoultrydeferredpurchase_getall(v_farm, 'DEFERRED')
          WHERE deferredremainingcost <= 0);
    RAISE NOTICE 'G2. RECOGNIZED all settled  expect        0  got %',
        (SELECT COUNT(*) FROM sppoultrydeferredpurchase_getall(v_farm, 'RECOGNIZED')
          WHERE deferredremainingcost > 0);
    RAISE NOTICE 'G3. RECOGNIZED skips at-purchase expect  0  got %',
        (SELECT COUNT(*) FROM sppoultrydeferredpurchase_getall(v_farm, 'RECOGNIZED')
          WHERE deferredtotalcost = 0);
    RAISE NOTICE 'G4. ALL >= DEFERRED         expect        t  got %',
        ((SELECT COUNT(*) FROM sppoultrydeferredpurchase_getall(v_farm, 'ALL'))
         >= (SELECT COUNT(*) FROM sppoultrydeferredpurchase_getall(v_farm, 'DEFERRED')));
    RAISE NOTICE 'G5. item filter narrows     expect        1  got %',
        (SELECT COUNT(DISTINCT poultryrawmaterialitemid)
           FROM sppoultrydeferredpurchase_getall(v_farm, 'ALL', v_item));

    -- =====================================================================
    -- I. Reversal. The balance comes back, and the history says why.
    --    (brief test 7, read side)
    -- =====================================================================
    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_r1, p_createdby => 'ZZ tester',
        p_feedsjson => '[]');

    RAISE NOTICE 'I1. recognised back to 0   expect     0.00  got %',
        (SELECT recognizedcost FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_p1);
    RAISE NOTICE 'I2. deferred restored      expect  5000.00  got %',
        (SELECT deferredremainingcost FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_p1);
    -- Not "Reversed": the lot is genuinely back to untouched, and saying so is
    -- more truthful than a status that describes how it got there.
    RAISE NOTICE 'I3. status back to          expect Not yet expensed  got %',
        (SELECT status FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_p1);
    RAISE NOTICE 'I4. no drift after reversal expect     0.00  got %',
        (SELECT recognitiondrift FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_p1);

    -- =====================================================================
    -- K. Idempotency: syncing the same record again with the same lines must
    --    not recognise a second time. (brief test 4)
    -- =====================================================================
    DECLARE
        v_e1 numeric; v_e2 numeric;
    BEGIN
        SELECT COALESCE(SUM(e.amount), 0) INTO v_e1 FROM expense e WHERE e.farmid::text = v_farm;
        PERFORM sppoultryproductionrawmaterialsync(
            p_farmid => v_farm, p_productionid => v_r3, p_createdby => 'ZZ tester',
            p_feedsjson => ('[{"itemId":' || v_mix::text || ',"qty":150}]'));
        SELECT COALESCE(SUM(e.amount), 0) INTO v_e2 FROM expense e WHERE e.farmid::text = v_farm;
        RAISE NOTICE 'K1. re-sync adds nothing   expect     0.00  got %', (v_e2 - v_e1);
        RAISE NOTICE 'K2. breakdown still 2 rows expect        2  got %',
            (SELECT COUNT(*) FROM sppoultryconsumption_costbreakdown(v_farm, v_r3));
        RAISE NOTICE 'K3. still 400 recognised   expect   400.00  got %',
            (SELECT SUM(recognizedcost) FROM sppoultryconsumption_costbreakdown(v_farm, v_r3));
    END;

    -- =====================================================================
    -- J. The Exception flag. Stock removed WITHOUT drawing cost layers --
    --    which is what internal use and stock adjustments do today (267,
    --    and section 24 of the brief) -- strands deferred cost on a lot with
    --    nothing left to consume. The page must say so, not average it away.
    -- =====================================================================
    v_strand := sppoultryrawmaterialitem_insert(v_farm, 'ZZ DR Stranded', 'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg');
    v_lotS := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_strand,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 100, p_unitcost => 10, p_totalcost => 1000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 1000, p_createdby => 'ZZ tester');

    -- Empty the LOT without touching its deferred balance: exactly the shape a
    -- stock adjustment leaves behind.
    UPDATE poultryrawmaterialpurchases SET remainingquantity = 0
    WHERE  poultryrawmaterialpurchaseid = v_lotS;

    RAISE NOTICE 'J1. stranded lot flagged   expect Exception  got %',
        (SELECT status FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_lotS);
    RAISE NOTICE 'J2. and it says why        expect  not null  got %',
        (SELECT exceptionreason IS NOT NULL FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_lotS);
    RAISE NOTICE 'J3. EXCEPTION scope finds it expect      t  got %',
        (SELECT COUNT(*) > 0 FROM sppoultrydeferredpurchase_getall(v_farm, 'EXCEPTION')
          WHERE poultryrawmaterialpurchaseid = v_lotS);
    -- Emitted as a BOOLEAN, not as ">0". The apply script auto-compares every
    -- "expect X got Y" pair and aborts on a mismatch; an expectation it cannot
    -- parse as a number or t/f never equals the value, so a relational
    -- expectation written literally would fail a run that was perfectly fine.
    RAISE NOTICE 'J4. summary counts it      expect        t  got %',
        (SELECT exceptions > 0 FROM sppoultrydeferredpurchase_summary(v_farm, 'ALL'));

    RAISE NOTICE '   -- all checks emitted; compare each expect/got pair above --';
END
$t$;

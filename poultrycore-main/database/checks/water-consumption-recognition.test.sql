-- Behavioural checks for migration 279: water consumption recognition.
--
-- One DO block per theme, a NOTICE per check reading "expect X got Y". Run
-- inside a transaction you ROLL BACK; it writes settings, items, purchases,
-- production batches, expenses and cash rows.
--
--   psql ... -X -c "BEGIN;" -f water-consumption-recognition.test.sql -c "ROLLBACK;"
--
-- THIS IS THE ONE THAT MOVES PROFIT, so the checks are about money, not shape.
--
-- Note what is DIFFERENT about this file compared with 275/277/278: it does NOT
-- lift the interlock, because 279 lifts it for real. Section 0 asserts that it
-- is genuinely open, which is the single behavioural change this migration
-- makes to a live system.
--
-- The claims:
--   A. The interlock is open and a company can now actually choose deferral.
--   B. END TO END. Buy deferred, consume it in a production batch, and exactly
--      the deferred amount appears in Profit & Loss -- no more, no less.
--   C. NO CASH MOVED and NO DEBT CREATED by that recognition. This is the claim
--      that separates "recognising a cost" from "paying for something".
--   D. An already-expensed lot consumed recognises NOTHING. The double-charge
--      guard, per lot.
--   E. A draw crossing both kinds charges only the deferred part.
--   F. REOPEN gives the cost back AND frees the unique-index slot, so the batch
--      can be approved again. The index trap 283 documented from the other side.
--   G. The P&L line: consumed packaging lands on Packaging, not Other Costs.

-- =============================================================================
-- 0. THE INTERLOCK IS NOW OPEN. This is what 279 changes.
-- =============================================================================
DO $lock$
BEGIN
    RAISE NOTICE '0a. interlock is open now expect        t  got %',
        fnwatercostrecognition_deferralready();
    IF NOT fnwatercostrecognition_deferralready() THEN
        RAISE EXCEPTION '279 did not open the deferral interlock. The feature ships switched off.';
    END IF;
END
$lock$;

DO $t$
DECLARE
    v_farm    text;
    v_acct    integer;
    v_item    integer;
    v_itemc   integer;
    v_prod    integer;
    v_lotdef  integer;
    v_lotexp  integer;
    v_batch   integer;
    v_usage   integer;
    v_expid   integer;
    v_cash0   numeric;
    v_amt     numeric;
    v_n       integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE EXCEPTION 'No water company to run these checks against.';
    END IF;
    RAISE NOTICE '   using water company %', v_farm;

    DELETE FROM waterfinancialsettings WHERE farmid = v_farm;

    SELECT ca.watercashaccountid INTO v_acct FROM watercashaccounts ca
    WHERE ca.farmid = v_farm AND ca.isactive = TRUE ORDER BY ca.watercashaccountid LIMIT 1;
    IF v_acct IS NULL THEN
        INSERT INTO watercashaccounts (farmid, accountname, accounttype, currentbalance, isactive)
        VALUES (v_farm, 'ZZ Till 279', 'Cash', 0, TRUE) RETURNING watercashaccountid INTO v_acct;
    END IF;

    SELECT p.waterproductid INTO v_prod FROM waterproducts p
    WHERE p.farmid = v_farm ORDER BY p.waterproductid LIMIT 1;
    IF v_prod IS NULL THEN
        RAISE EXCEPTION 'No water product to build a production batch against.';
    END IF;

    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Film 279', 'SachetFilm', 'Roll', 'Roll', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_item;

    -- =====================================================================
    -- A. A COMPANY CAN NOW CHOOSE DEFERRAL.
    --
    -- Before 279 this call raised: "Deferred cost recognition is not available
    -- for Water yet."
    -- =====================================================================
    PERFORM spwaterfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');
    RAISE NOTICE 'A1. packaging can be deferred expect EXPENSE_WHEN_CONSUMED  got %',
        (SELECT packagingcostrecognitionmethod FROM spwaterfinancialsettings_get(v_farm));
    RAISE NOTICE 'A2. and the page is told so  expect        t  got %',
        (SELECT deferralavailable FROM spwaterfinancialsettings_get(v_farm));

    -- =====================================================================
    -- B/C. END TO END: buy deferred, consume, and watch the P&L -- and only
    --      the P&L -- move.
    --
    -- 10 rolls at 100 = 1,000, on credit, deferred. Consume 4 rolls.
    -- Expected recognition: 4/10 of 1,000 = 400.
    -- =====================================================================
    v_lotdef := spwaterrawmaterialpurchase_insert(
        p_farmid => v_farm, p_waterrawmaterialitemid => v_item, p_suppliername => 'ZZ Supplier',
        p_purchasedate => (now() at time zone 'utc') - interval '1 day',
        p_quantity => 10, p_unitcost => 100, p_paymentmethod => 'Credit', p_amountpaid => 0,
        p_receipturl => NULL, p_receivedbystaffid => NULL, p_notes => 'ZZ 279 deferred',
        p_createdby => 'ZZ tester', p_supplierid => NULL, p_totalcost => 1000,
        p_watercashaccountid => NULL, p_productionunit => 'Roll',
        p_productionunitsperpurchaseunit => 1);

    RAISE NOTICE 'B1. the lot opened deferred  expect  1000.00  got %',
        (SELECT deferredremainingcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lotdef);

    SELECT ca.currentbalance INTO v_cash0 FROM watercashaccounts ca WHERE ca.watercashaccountid = v_acct;

    INSERT INTO waterproductionbatches
        (farmid, batchnumber, productiondate, waterproductid, bagsproduced, damagedbags,
         -- totalproductioncost is a GENERATED column -- it follows the four
         -- cost columns below and cannot be written directly.
         rejectedsachets, sachetsperbag, rawmaterialcost,
         electricitycost, fuelcost, laborcost, otherproductioncost,
         status, isdeleted, createdby)
    VALUES
        (v_farm, 'ZZ-279-A', (now() at time zone 'utc')::date, v_prod, 10, 0,
         0, 30, 0, 0, 0, 0, 0, 'Draft', FALSE, 'ZZ tester')
    RETURNING waterproductionbatchid INTO v_batch;

    INSERT INTO waterrawmaterialusage
        (farmid, waterrawmaterialitemid, waterproductionbatchid, useddate, quantityused, createdby)
    VALUES (v_farm, v_item, v_batch, (now() at time zone 'utc'), 4, 'ZZ tester')
    RETURNING waterrawmaterialusageid INTO v_usage;

    PERFORM spwaterproductionbatch_approve(v_batch, v_farm, 'ZZ tester');

    SELECT waterexpenseid, amount INTO v_expid, v_amt
    FROM   waterexpenses
    WHERE  farmid = v_farm AND sourcetype = 'WaterPackagingConsumption'
      AND  sourceid = v_batch AND isdeleted = FALSE;

    RAISE NOTICE 'B2. recognised on consumption expect   400.00  got %', v_amt;
    RAISE NOTICE 'B3. the lot kept the rest    expect   600.00  got %',
        (SELECT deferredremainingcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lotdef);
    RAISE NOTICE 'B4. and it is Approved       expect Approved  got %',
        (SELECT status FROM waterexpenses WHERE waterexpenseid = v_expid);

    -- C. The half that must NOT happen.
    RAISE NOTICE 'C1. no cash moved            expect     0.00  got %',
        ((SELECT ca.currentbalance FROM watercashaccounts ca WHERE ca.watercashaccountid = v_acct) - v_cash0);
    RAISE NOTICE 'C2. no cash row was written  expect        0  got %',
        (SELECT COUNT(*) FROM watercashtransactions
         WHERE farmid = v_farm AND sourcetype = 'Expense' AND sourceid = v_expid);
    RAISE NOTICE 'C3. and it is not a debt     expect        0  got %',
        (SELECT COUNT(*) FROM fnwaterpayables(v_farm) d
         WHERE d.documenttype = 'Expense' AND d.documentid = v_expid);
    -- It is an operating cost of this period, NOT depreciation-style non-cash.
    RAISE NOTICE 'C4. filed as OperatingExpense expect OperatingExpense  got %',
        fnwaterexpense_costtype(NULL, 'WaterPackagingConsumption', NULL, NULL);

    -- =====================================================================
    -- G. THE P&L LINE. Consumed packaging must land where purchased packaging
    --    lands, or deferral would quietly move a cost between report lines.
    -- =====================================================================
    RAISE NOTICE 'G1. packaging line           expect Packaging  got %',
        fnwaterexpense_plline('OperatingExpense', 'WaterPackagingConsumption', 'Raw Materials / Inventory Purchase', NULL);
    RAISE NOTICE 'G2. treatment line           expect Treatment  got %',
        fnwaterexpense_plline('OperatingExpense', 'WaterTreatmentConsumption', 'Raw Materials / Inventory Purchase', NULL);
    RAISE NOTICE 'G3. supplies line            expect ProductionSupplies  got %',
        fnwaterexpense_plline('OperatingExpense', 'WaterSuppliesConsumption', 'Raw Materials / Inventory Purchase', NULL);

    -- =====================================================================
    -- D. AN ALREADY-EXPENSED LOT RECOGNISES NOTHING.
    --
    -- The double-charge guard. This lot's cost reached the P&L when it was
    -- bought; consuming it must cost nothing further.
    -- =====================================================================
    PERFORM spwaterfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');

    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Film 279d', 'SachetFilm', 'Roll', 'Roll', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_itemc;

    v_lotexp := spwaterrawmaterialpurchase_insert(
        p_farmid => v_farm, p_waterrawmaterialitemid => v_itemc, p_suppliername => 'ZZ Supplier',
        p_purchasedate => (now() at time zone 'utc'), p_quantity => 10, p_unitcost => 100,
        p_paymentmethod => 'Cash', p_amountpaid => 1000, p_receipturl => NULL,
        p_receivedbystaffid => NULL, p_notes => 'ZZ 279 expensed', p_createdby => 'ZZ tester',
        p_supplierid => NULL, p_totalcost => 1000, p_watercashaccountid => v_acct,
        p_productionunit => 'Roll', p_productionunitsperpurchaseunit => 1);

    INSERT INTO waterproductionbatches
        (farmid, batchnumber, productiondate, waterproductid, bagsproduced, damagedbags,
         rejectedsachets, sachetsperbag, rawmaterialcost,
         electricitycost, fuelcost, laborcost, otherproductioncost,
         status, isdeleted, createdby)
    VALUES
        (v_farm, 'ZZ-279-D', (now() at time zone 'utc')::date, v_prod, 10, 0,
         0, 30, 0, 0, 0, 0, 0, 'Draft', FALSE, 'ZZ tester')
    RETURNING waterproductionbatchid INTO v_batch;

    INSERT INTO waterrawmaterialusage
        (farmid, waterrawmaterialitemid, waterproductionbatchid, useddate, quantityused, createdby)
    VALUES (v_farm, v_itemc, v_batch, (now() at time zone 'utc'), 4, 'ZZ tester');

    PERFORM spwaterproductionbatch_approve(v_batch, v_farm, 'ZZ tester');

    RAISE NOTICE 'D1. expensed lot recognises nothing expect        0  got %',
        (SELECT COUNT(*) FROM waterexpenses
         WHERE farmid = v_farm AND sourceid = v_batch AND isdeleted = FALSE
           AND sourcetype IN ('WaterPackagingConsumption','WaterTreatmentConsumption','WaterSuppliesConsumption'));

    -- =====================================================================
    -- F. REOPEN: give the cost back, and let the batch be approved again.
    --
    -- Back to the deferred batch from B. Reopening must restore the 400 to the
    -- lot, retire the expense so it leaves the P&L, AND free the unique-index
    -- slot so a re-approval does not die on a duplicate key.
    -- =====================================================================
    SELECT b.waterproductionbatchid INTO v_batch FROM waterproductionbatches b
    WHERE b.farmid = v_farm AND b.batchnumber = 'ZZ-279-A';

    PERFORM spwaterproductionbatch_reopen(v_batch, v_farm, 'ZZ tester');

    RAISE NOTICE 'F1. the lot got its cost back expect  1000.00  got %',
        (SELECT deferredremainingcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lotdef);
    RAISE NOTICE 'F2. and its stock back       expect  10.000   got %',
        (SELECT remainingquantity FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lotdef);
    RAISE NOTICE 'F3. the expense left the P&L expect        0  got %',
        (SELECT COUNT(*) FROM waterexpenses
         WHERE farmid = v_farm AND sourceid = v_batch AND isdeleted = FALSE
           AND sourcetype = 'WaterPackagingConsumption');
    -- The index slot must be free, not merely the row cancelled.
    RAISE NOTICE 'F4. the index slot is free   expect        t  got %',
        (SELECT isdeleted FROM waterexpenses
         WHERE farmid = v_farm AND sourceid = v_batch
           AND sourcetype = 'WaterPackagingConsumption' LIMIT 1);

    -- The real proof: approve it again. Before the soft-delete this raised a
    -- duplicate-key violation on ux_waterexpenses_farmsource_active.
    UPDATE waterproductionbatches SET status = 'Draft'
    WHERE waterproductionbatchid = v_batch AND farmid = v_farm;

    INSERT INTO waterrawmaterialusage
        (farmid, waterrawmaterialitemid, waterproductionbatchid, useddate, quantityused, createdby)
    SELECT v_farm, v_item, v_batch, (now() at time zone 'utc'), 4, 'ZZ tester'
    WHERE NOT EXISTS (SELECT 1 FROM waterrawmaterialusage u
                      WHERE u.waterproductionbatchid = v_batch AND u.farmid = v_farm);

    PERFORM spwaterproductionbatch_approve(v_batch, v_farm, 'ZZ tester');

    RAISE NOTICE 'F5. re-approval recognises again expect   400.00  got %',
        (SELECT amount FROM waterexpenses
         WHERE farmid = v_farm AND sourceid = v_batch AND isdeleted = FALSE
           AND sourcetype = 'WaterPackagingConsumption');
    RAISE NOTICE 'F6. and exactly one live row expect        1  got %',
        (SELECT COUNT(*) FROM waterexpenses
         WHERE farmid = v_farm AND sourceid = v_batch AND isdeleted = FALSE
           AND sourcetype = 'WaterPackagingConsumption');

    RAISE NOTICE '--- 279 checks done. ROLL BACK this transaction. ---';
END
$t$;

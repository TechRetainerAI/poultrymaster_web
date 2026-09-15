-- Behavioural checks for migration 281: the water Deferred inventory cost reads.
--
-- One DO block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it writes items, purchases, batches and usage.
--
--   psql ... -X -c "BEGIN;" -f water-cost-recognition-reads.test.sql -c "ROLLBACK;"
--
-- These are READ functions, so the claims are all of the form "the page will
-- show the truth":
--   A. A deferred lot reads as deferred, with the right basis and percentage.
--   B. After consumption it reads as partly expensed, and the recognised figure
--      agrees with the lot balance -- the drift column is what catches a
--      disagreement, so it must be ZERO on a healthy lot.
--   C. THE QUEUE. Two lots of one item: the older is next (position 1, nothing
--      ahead), the younger is queued behind it by exactly the older's quantity.
--      This is the question the page exists to answer -- "why is this purchase
--      still not expensed?" -- so it is the check that matters most.
--   D. The summary is computed FROM the list, so the two cannot disagree.
--   E. Scope filters select what they claim to.
--   F. History shows the draw, names the batch and product, and finds 279's
--      recognition expense.
--   G. The breakdown shows, per lot, whether it was expensed at purchase or is
--      being expensed now -- two rows of one batch disagreeing is the point.

DO $t$
DECLARE
    v_farm   text;
    v_item   integer;
    v_prod   integer;
    v_lotold integer;
    v_lotnew integer;
    v_lotexp integer;
    v_batch  integer;
    v_r      record;
    v_n      integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE EXCEPTION 'No water company to run these checks against.';
    END IF;
    SELECT p.waterproductid INTO v_prod FROM waterproducts p
    WHERE p.farmid = v_farm ORDER BY p.waterproductid LIMIT 1;
    IF v_prod IS NULL THEN
        RAISE EXCEPTION 'No water product to build a production batch against.';
    END IF;
    RAISE NOTICE '   using water company %', v_farm;

    DELETE FROM waterfinancialsettings WHERE farmid = v_farm;
    PERFORM spwaterfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');

    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Film 281', 'SachetFilm', 'Roll', 'Roll', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_item;

    -- Two deferred lots of the same item, older first. FIFO, so the older is
    -- drawn first and the younger waits behind all 10 of its rolls.
    v_lotold := spwaterrawmaterialpurchase_insert(
        p_farmid => v_farm, p_waterrawmaterialitemid => v_item, p_suppliername => 'ZZ Supplier A',
        p_purchasedate => (now() at time zone 'utc') - interval '5 days',
        p_quantity => 10, p_unitcost => 100, p_paymentmethod => 'Credit', p_amountpaid => 0,
        p_receipturl => NULL, p_receivedbystaffid => NULL, p_notes => 'ZZ 281 old',
        p_createdby => 'ZZ tester', p_supplierid => NULL, p_totalcost => 1000,
        p_watercashaccountid => NULL, p_productionunit => 'Roll',
        p_productionunitsperpurchaseunit => 1);

    v_lotnew := spwaterrawmaterialpurchase_insert(
        p_farmid => v_farm, p_waterrawmaterialitemid => v_item, p_suppliername => 'ZZ Supplier B',
        p_purchasedate => (now() at time zone 'utc') - interval '1 day',
        p_quantity => 5, p_unitcost => 200, p_paymentmethod => 'Credit', p_amountpaid => 0,
        p_receipturl => NULL, p_receivedbystaffid => NULL, p_notes => 'ZZ 281 new',
        p_createdby => 'ZZ tester', p_supplierid => NULL, p_totalcost => 1000,
        p_watercashaccountid => NULL, p_productionunit => 'Roll',
        p_productionunitsperpurchaseunit => 1);

    -- =====================================================================
    -- A. A DEFERRED LOT READS AS DEFERRED.
    -- =====================================================================
    SELECT * INTO v_r FROM fnwaterdeferredpurchase_rows(v_farm) r
    WHERE r.waterrawmaterialpurchaseid = v_lotold;

    RAISE NOTICE 'A1. status                   expect Not yet expensed  got %', v_r.status;
    RAISE NOTICE 'A2. deferred basis           expect  1000.00  got %', v_r.deferredtotalcost;
    RAISE NOTICE 'A3. still waiting            expect  1000.00  got %', v_r.deferredremainingcost;
    RAISE NOTICE 'A4. reached the P&L          expect     0.00  got %', v_r.recognizedcost;
    RAISE NOTICE 'A5. percent recognised       expect     0.00  got %', v_r.recognitionpercent;
    RAISE NOTICE 'A6. method label             expect Expense when used  got %', v_r.recognitionmethodlabel;
    RAISE NOTICE 'A7. no exception reason      expect        t  got %', (v_r.exceptionreason IS NULL);

    -- =====================================================================
    -- C. THE QUEUE. Checked before any consumption, while both lots are whole.
    -- =====================================================================
    RAISE NOTICE 'C1. older lot is next        expect        1  got %', v_r.queueposition;
    RAISE NOTICE 'C2. with nothing ahead of it expect   0.000   got %', v_r.quantityaheadinqueue;
    RAISE NOTICE 'C3. and its costing method   expect FIFO  got %', v_r.costingmethod;

    SELECT * INTO v_r FROM fnwaterdeferredpurchase_rows(v_farm) r
    WHERE r.waterrawmaterialpurchaseid = v_lotnew;
    RAISE NOTICE 'C4. newer lot is second      expect        2  got %', v_r.queueposition;
    RAISE NOTICE 'C5. queued behind 10 rolls   expect  10.000   got %', v_r.quantityaheadinqueue;

    -- The summary turns that into the sentence the page shows.
    SELECT * INTO v_r FROM spwaterdeferredpurchase_summary(v_farm, 'DEFERRED', v_item);
    RAISE NOTICE 'C6. one lot is blocked       expect        1  got %', v_r.blockedpurchases;
    RAISE NOTICE 'C7. holding 1000 behind it   expect  1000.00  got %', v_r.blockedcost;

    -- =====================================================================
    -- D. THE SUMMARY AGREES WITH THE LIST.
    -- =====================================================================
    SELECT COUNT(*) INTO v_n FROM spwaterdeferredpurchase_getall(v_farm, 'DEFERRED', v_item);
    RAISE NOTICE 'D1. list has both lots       expect        2  got %', v_n;
    RAISE NOTICE 'D2. summary counts the same  expect        2  got %',
        (SELECT purchasecount FROM spwaterdeferredpurchase_summary(v_farm, 'DEFERRED', v_item));
    RAISE NOTICE 'D3. and totals their basis   expect  2000.00  got %',
        (SELECT deferredbasis FROM spwaterdeferredpurchase_summary(v_farm, 'DEFERRED', v_item));

    -- =====================================================================
    -- B. AFTER CONSUMPTION. Draw 4 of the older lot's 10 rolls: 400 recognised.
    -- =====================================================================
    INSERT INTO waterproductionbatches
        (farmid, batchnumber, productiondate, waterproductid, bagsproduced, damagedbags,
         rejectedsachets, sachetsperbag, rawmaterialcost,
         electricitycost, fuelcost, laborcost, otherproductioncost,
         status, isdeleted, createdby)
    VALUES
        (v_farm, 'ZZ-281-A', (now() at time zone 'utc')::date, v_prod, 10, 0,
         0, 30, 0, 0, 0, 0, 0, 'Draft', FALSE, 'ZZ tester')
    RETURNING waterproductionbatchid INTO v_batch;

    INSERT INTO waterrawmaterialusage
        (farmid, waterrawmaterialitemid, waterproductionbatchid, useddate, quantityused, createdby)
    VALUES (v_farm, v_item, v_batch, (now() at time zone 'utc'), 4, 'ZZ tester');

    PERFORM spwaterproductionbatch_approve(v_batch, v_farm, 'ZZ tester');

    SELECT * INTO v_r FROM fnwaterdeferredpurchase_rows(v_farm) r
    WHERE r.waterrawmaterialpurchaseid = v_lotold;

    RAISE NOTICE 'B1. now partly expensed      expect Partly expensed  got %', v_r.status;
    RAISE NOTICE 'B2. recognised so far        expect   400.00  got %', v_r.recognizedcost;
    RAISE NOTICE 'B3. still waiting            expect   600.00  got %', v_r.deferredremainingcost;
    RAISE NOTICE 'B4. percent                  expect    40.00  got %', v_r.recognitionpercent;
    RAISE NOTICE 'B5. consumed quantity        expect   4.000   got %', v_r.consumedquantity;
    RAISE NOTICE 'B6. one recognition event   expect        1  got %', v_r.recognitionevents;
    -- THE INTEGRITY CHECK. The lot's own balance and the sum of its allocations
    -- must agree; drift is what the Exception status keys on.
    RAISE NOTICE 'B7. no drift                 expect     0.00  got %', v_r.recognitiondrift;
    RAISE NOTICE 'B8. so not an exception      expect        t  got %', (v_r.status <> 'Exception');

    -- =====================================================================
    -- E. SCOPE FILTERS.
    -- =====================================================================
    RAISE NOTICE 'E1. EXCEPTION scope is empty expect        0  got %',
        (SELECT COUNT(*) FROM spwaterdeferredpurchase_getall(v_farm, 'EXCEPTION', v_item));
    RAISE NOTICE 'E2. RECOGNIZED scope is empty expect        0  got %',
        (SELECT COUNT(*) FROM spwaterdeferredpurchase_getall(v_farm, 'RECOGNIZED', v_item));
    RAISE NOTICE 'E3. search by supplier finds one expect        1  got %',
        (SELECT COUNT(*) FROM spwaterdeferredpurchase_getall(v_farm, 'ALL', v_item, NULL, NULL, NULL, NULL, 'Supplier B'));

    -- =====================================================================
    -- F. HISTORY.
    -- =====================================================================
    SELECT * INTO v_r FROM spwaterdeferredpurchase_history(v_farm, v_lotold) h LIMIT 1;
    RAISE NOTICE 'F1. one draw is listed       expect        1  got %',
        (SELECT COUNT(*) FROM spwaterdeferredpurchase_history(v_farm, v_lotold));
    RAISE NOTICE 'F2. quantity drawn           expect   4.000   got %', v_r.quantitydrawn;
    RAISE NOTICE 'F3. recognised on that draw  expect   400.00  got %', v_r.recognizedcost;
    RAISE NOTICE 'F4. outcome                  expect Expensed now  got %', v_r.recognitionoutcome;
    RAISE NOTICE 'F5. names the batch          expect ZZ-281-A  got %', v_r.productionbatchnumber;
    RAISE NOTICE 'F6. and names the product    expect        t  got %', (v_r.productname IS NOT NULL);
    -- It found 279's expense, which is what ties the page to the P&L.
    RAISE NOTICE 'F7. found the expense        expect   400.00  got %', v_r.expenseamount;
    RAISE NOTICE 'F8. and calls it posted      expect Posted  got %', v_r.expensestatus;

    -- =====================================================================
    -- G. BREAKDOWN.
    -- =====================================================================
    SELECT * INTO v_r FROM spwaterconsumption_costbreakdown(v_farm, v_batch) b LIMIT 1;
    RAISE NOTICE 'G1. one lot was drawn        expect        1  got %',
        (SELECT COUNT(*) FROM spwaterconsumption_costbreakdown(v_farm, v_batch));
    RAISE NOTICE 'G2. from the older lot       expect        t  got %',
        (v_r.waterrawmaterialpurchaseid = v_lotold);
    RAISE NOTICE 'G3. operational cost         expect   400.00  got %', v_r.operationalcost;
    RAISE NOTICE 'G4. recognised               expect   400.00  got %', v_r.recognizedcost;
    RAISE NOTICE 'G5. label                    expect Expense when used  got %', v_r.recognitionlabel;

    RAISE NOTICE '--- 281 checks done. ROLL BACK this transaction. ---';
END
$t$;

-- Behavioural checks for migration 262: a deferred purchase writes no P&L expense.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates items, purchases and payments.
--
--   psql ... -X -c "BEGIN;" -f poultry-deferred-purchase-expense.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 262
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- HOW THIS FILE IS ORGANISED
-- --------------------------
-- The same story is told twice against the same farm, once per method, and the
-- two are compared. Section A is EXPENSE_WHEN_PURCHASED and exists to prove
-- **nothing changed**; section B is EXPENSE_WHEN_CONSUMED and proves the cost
-- is withheld from the P&L and from nowhere else.
--
-- The scenario, both times:
--
--   buy 100 bags at 1,000 = 100,000, paying 40,000 up front
--   pay the supplier a further 25,000
--   edit the purchase
--
-- The claims:
--   1. **EXPENSE_WHEN_PURCHASED is untouched.** The expense follows the money,
--      as it always has: 40,000 at entry, 25,000 on payment, and an edit
--      rebalances rather than duplicates.
--   2. **EXPENSE_WHEN_CONSUMED writes no expense at all** -- not at entry, not
--      on the later payment, and not when the purchase is edited.
--   3. **Cash, supplier balance and stock are identical either way.** Paying
--      for something and expensing it are different events, and only the
--      second one moved.
--   4. The snapshot is what decides, not today's setting: flipping the farm
--      back after the purchase changes nothing about that purchase.

DO $t$
DECLARE
    v_farm  text;
    v_acct  integer;
    v_item  integer;
    v_sup   integer;

    v_pA integer; v_pB integer;

    v_exp0 numeric; v_exp1 numeric; v_exp2 numeric; v_exp3 numeric;
    v_expB1 numeric; v_expB2 numeric; v_expB3 numeric;
    v_stock0 numeric; v_stockA numeric; v_stockB numeric;
    v_cash0 numeric; v_cashA numeric; v_cashB numeric;
    v_balA numeric; v_balB numeric;
BEGIN
    SELECT f.farmid INTO v_farm
    FROM   farms f
    WHERE  f.type = 'Poultry'
      -- The farm id has to cast to uuid or the expense link never runs at all,
      -- and every expense claim below would pass for the wrong reason.
      AND  f.farmid ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ORDER  BY f.farmid
    LIMIT  1;
    IF v_farm IS NULL THEN
        RAISE EXCEPTION 'No poultry company with a uuid-shaped id; the expense link cannot be exercised.';
    END IF;
    RAISE NOTICE '   using poultry farm %', v_farm;

    DELETE FROM poultryfinancialsettings WHERE farmid = v_farm;

    INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance,
                                     currentbalance, allownegativebalance, isactive)
    VALUES (v_farm, 'ZZ Cost Recognition Bank', 'BankAccount', 500000, 500000, FALSE, TRUE)
    RETURNING poultrycashaccountid INTO v_acct;

    v_item := sppoultryrawmaterialitem_insert(
        v_farm, 'ZZ Maize CR', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'bag');
    v_sup  := fnpoultrysupplier_resolve(v_farm, 'ZZ Feed Supplier', 'ZZ tester');

    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp0 FROM expense e WHERE e.farmid::text = v_farm;
    SELECT i.currentquantity INTO v_stock0 FROM poultryrawmaterialitems i
     WHERE i.poultryrawmaterialitemid = v_item;
    SELECT a.currentbalance INTO v_cash0 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;

    -- =====================================================================
    -- A. EXPENSE_WHEN_PURCHASED -- today's behaviour, and it must not move.
    -- =====================================================================
    -- No settings row at all, which is the state every farm is in right now.
    v_pA := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_item,
        p_suppliername => 'ZZ Feed Supplier', p_supplierid => v_sup,
        p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 100, p_unitcost => 1000, p_totalcost => 100000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 50,
        p_paymentmethod => 'Cash', p_amountpaid => 40000,
        p_notes => 'ZZ immediate', p_createdby => 'ZZ tester');

    RAISE NOTICE 'A1. snapshotted purchased  expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT costrecognitionmethod FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_pA);

    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp1 FROM expense e WHERE e.farmid::text = v_farm;
    -- The expense follows the MONEY, not the invoice: 40,000 paid, 40,000 booked.
    RAISE NOTICE 'A2. expense is what was paid expect 40000.00  got %', (v_exp1 - v_exp0);
    RAISE NOTICE 'A3. one linked expense row expect        1  got %',
        (SELECT COUNT(*) FROM expense e WHERE e.farmid::text = v_farm
          AND e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = v_pA);
    -- Stock is in production units: 100 bags x 50 kg.
    SELECT i.currentquantity INTO v_stockA FROM poultryrawmaterialitems i
     WHERE i.poultryrawmaterialitemid = v_item;
    RAISE NOTICE 'A4. stock up by 5000       expect  5000.00  got %', (v_stockA - v_stock0);

    -- Pay another 25,000 of the outstanding 60,000.
    PERFORM sppoultryrawmaterialpurchase_paybalance(
        v_pA, v_farm, 25000, 'Cash', (now() at time zone 'utc'), 'ZZ tester');

    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp2 FROM expense e WHERE e.farmid::text = v_farm;
    RAISE NOTICE 'A5. payment books its cost expect 25000.00  got %', (v_exp2 - v_exp1);
    RAISE NOTICE 'A6. two linked rows now    expect        2  got %',
        (SELECT COUNT(*) FROM expense e WHERE e.farmid::text = v_farm
          AND e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = v_pA);
    -- 207's invariant: the linked rows sum to what has been paid.
    RAISE NOTICE 'A7. rows sum to amountpaid expect        t  got %',
        ((SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm
           AND e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = v_pA)
         = (SELECT pu.amountpaid FROM poultryrawmaterialpurchases pu WHERE pu.poultryrawmaterialpurchaseid = v_pA));

    -- Editing rebalances the first row rather than adding another.
    PERFORM sppoultryrawmaterialpurchase_update(
        v_pA, v_farm, 'ZZ Feed Supplier', v_sup, (now() at time zone 'utc'),
        100, 1000, 100000, 'kg', 50, 'Cash', 65000, NULL, 'ZZ immediate edited');

    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp3 FROM expense e WHERE e.farmid::text = v_farm;
    RAISE NOTICE 'A8. edit adds nothing new  expect     0.00  got %', (v_exp3 - v_exp2);
    RAISE NOTICE 'A9. still two linked rows  expect        2  got %',
        (SELECT COUNT(*) FROM expense e WHERE e.farmid::text = v_farm
          AND e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = v_pA);

    SELECT a.currentbalance INTO v_cashA FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    SELECT (pu.totalcost - pu.amountpaid) INTO v_balA
    FROM   poultryrawmaterialpurchases pu WHERE pu.poultryrawmaterialpurchaseid = v_pA;
    RAISE NOTICE 'A10. still owes 35000      expect 35000.00  got %', v_balA;

    -- =====================================================================
    -- B. EXPENSE_WHEN_CONSUMED -- the cost is withheld, and only the cost.
    -- =====================================================================
    PERFORM sppoultryfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');

    SELECT COALESCE(SUM(e.amount), 0) INTO v_expB1 FROM expense e WHERE e.farmid::text = v_farm;
    -- Changing the setting is not itself an accounting event.
    RAISE NOTICE 'B0. setting change is inert expect     0.00  got %', (v_expB1 - v_exp3);

    v_pB := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_item,
        p_suppliername => 'ZZ Feed Supplier', p_supplierid => v_sup,
        p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 100, p_unitcost => 1000, p_totalcost => 100000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 50,
        p_paymentmethod => 'Cash', p_amountpaid => 40000,
        p_notes => 'ZZ deferred', p_createdby => 'ZZ tester');

    RAISE NOTICE 'B1. snapshotted consumed   expect EXPENSE_WHEN_CONSUMED  got %',
        (SELECT costrecognitionmethod FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_pB);

    -- **THE** check.
    SELECT COALESCE(SUM(e.amount), 0) INTO v_expB2 FROM expense e WHERE e.farmid::text = v_farm;
    RAISE NOTICE 'B2. NO expense at entry    expect     0.00  got %', (v_expB2 - v_expB1);
    RAISE NOTICE 'B3. no linked expense row  expect        0  got %',
        (SELECT COUNT(*) FROM expense e WHERE e.farmid::text = v_farm
          AND e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = v_pB);

    -- ...and nothing else was withheld with it.
    SELECT i.currentquantity INTO v_stockB FROM poultryrawmaterialitems i
     WHERE i.poultryrawmaterialitemid = v_item;
    RAISE NOTICE 'B4. stock rose the same    expect  5000.00  got %', (v_stockB - v_stockA);
    RAISE NOTICE 'B5. purchase cost kept     expect 100000.00  got %',
        (SELECT totalcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_pB);
    -- Phase 2 needs the unit cost and the remaining quantity to value what is
    -- left; both are preserved exactly as for an immediate purchase.
    RAISE NOTICE 'B6. unit cost kept         expect  1000.00  got %',
        (SELECT unitcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_pB);
    RAISE NOTICE 'B7. FIFO layer intact      expect   100.00  got %',
        (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_pB);
    SELECT (pu.totalcost - pu.amountpaid) INTO v_balB
    FROM   poultryrawmaterialpurchases pu WHERE pu.poultryrawmaterialpurchaseid = v_pB;
    RAISE NOTICE 'B8. still owes 60000       expect 60000.00  got %', v_balB;

    -- The second half of the deferral: paying the supplier must not book it.
    PERFORM sppoultryrawmaterialpurchase_paybalance(
        v_pB, v_farm, 25000, 'Cash', (now() at time zone 'utc'), 'ZZ tester');

    SELECT COALESCE(SUM(e.amount), 0) INTO v_expB3 FROM expense e WHERE e.farmid::text = v_farm;
    RAISE NOTICE 'B9. payment books nothing  expect     0.00  got %', (v_expB3 - v_expB2);
    RAISE NOTICE 'B10. still no linked row   expect        0  got %',
        (SELECT COUNT(*) FROM expense e WHERE e.farmid::text = v_farm
          AND e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = v_pB);
    -- But the money DID move, and the debt DID fall. That is the distinction
    -- the whole feature rests on.
    RAISE NOTICE 'B11. but the debt fell     expect 35000.00  got %',
        (SELECT (pu.totalcost - pu.amountpaid) FROM poultryrawmaterialpurchases pu
          WHERE pu.poultryrawmaterialpurchaseid = v_pB);
    RAISE NOTICE 'B12. and a payment exists  expect        1  got %',
        (SELECT COUNT(*) FROM poultrysupplierpayments sp
          WHERE sp.farmid = v_farm AND sp.supplierid = v_sup
            AND EXISTS (SELECT 1 FROM supplierpaymentallocation sa
                        WHERE sa.paymentid = sp.poultrysupplierpaymentid
                          AND sa.documenttype = 'RawMaterialPurchase'
                          AND sa.documentid = v_pB));

    -- The 207 repair path must not resurrect the expense on an edit.
    PERFORM sppoultryrawmaterialpurchase_update(
        v_pB, v_farm, 'ZZ Feed Supplier', v_sup, (now() at time zone 'utc'),
        100, 1000, 100000, 'kg', 50, 'Cash', 65000, NULL, 'ZZ deferred edited');

    RAISE NOTICE 'B13. edit creates no expense expect     0.00  got %',
        ((SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm) - v_expB3);
    RAISE NOTICE 'B14. still no linked row   expect        0  got %',
        (SELECT COUNT(*) FROM expense e WHERE e.farmid::text = v_farm
          AND e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = v_pB);

    -- =====================================================================
    -- C. The snapshot decides, not the setting.
    -- =====================================================================
    PERFORM sppoultryfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');

    RAISE NOTICE 'C1. deferred stays deferred expect EXPENSE_WHEN_CONSUMED  got %',
        (SELECT costrecognitionmethod FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_pB);
    RAISE NOTICE 'C2. immediate stays immediate expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT costrecognitionmethod FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_pA);

    -- Paying the deferred purchase AFTER the farm switched back still books
    -- nothing: the purchase's own snapshot governs it, for ever.
    v_expB3 := (SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm);
    PERFORM sppoultryrawmaterialpurchase_paybalance(
        v_pB, v_farm, 10000, 'Cash', (now() at time zone 'utc'), 'ZZ tester');
    RAISE NOTICE 'C3. later payment still mute expect     0.00  got %',
        ((SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm) - v_expB3);

    -- And an immediate purchase made while the farm is deferred elsewhere still
    -- behaves immediately, because only FEED was deferred.
    PERFORM sppoultryfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');
    DECLARE
        v_med  integer;
        v_pMed integer;
        v_before numeric;
    BEGIN
        v_med := sppoultryrawmaterialitem_insert(
            v_farm, 'ZZ Vaccine CR', 'Medication', 'ml', 0, NULL, 'FIFO', 'bottle');
        v_before := (SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm);
        v_pMed := sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_med,
            p_suppliername => 'ZZ Feed Supplier', p_supplierid => v_sup,
            p_purchasedate => (now() at time zone 'utc'),
            p_quantity => 10, p_unitcost => 500, p_totalcost => 5000,
            p_productionunit => 'ml', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 5000,
            p_createdby => 'ZZ tester');
        RAISE NOTICE 'C4. medication unaffected  expect  5000.00  got %',
            ((SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm) - v_before);
        RAISE NOTICE 'C5. and snapshotted so    expect EXPENSE_WHEN_PURCHASED  got %',
            (SELECT costrecognitionmethod FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_pMed);
    END;

    -- =====================================================================
    -- D. An item override reaches the purchase.
    -- =====================================================================
    -- Farm defers feed; this item opts out. A purchase of it must be immediate.
    DECLARE
        v_ovr   integer;
        v_pOvr  integer;
        v_before numeric;
    BEGIN
        v_ovr := sppoultryrawmaterialitem_insert(
            v_farm, 'ZZ Soya CR', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'bag',
            'EXPENSE_WHEN_PURCHASED');
        v_before := (SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm);
        v_pOvr := sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_ovr,
            p_suppliername => 'ZZ Feed Supplier', p_supplierid => v_sup,
            p_purchasedate => (now() at time zone 'utc'),
            p_quantity => 10, p_unitcost => 200, p_totalcost => 2000,
            p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 2000,
            p_createdby => 'ZZ tester');
        RAISE NOTICE 'D1. override beats the farm expect  2000.00  got %',
            ((SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm) - v_before);
        RAISE NOTICE 'D2. and is snapshotted     expect EXPENSE_WHEN_PURCHASED  got %',
            (SELECT costrecognitionmethod FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_pOvr);
    END;
END
$t$;

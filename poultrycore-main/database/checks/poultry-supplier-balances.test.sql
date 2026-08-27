DO $t$
DECLARE
    v_farm text := '3c4ac3cd-8792-4739-9b20-5f3b7d655a02';
    v_acct integer := 21;   -- Bank Account
    v_sup integer; v_item integer;
    p1 integer; p2 integer; p3 integer;
    v_pay integer; v_bal numeric; v_cash numeric; v_n integer;
BEGIN
    v_sup := fnpoultrysupplier_resolve(v_farm, 'ZZ Maize Supplier Ltd', 'tester');
    UPDATE supplier SET paymenttermsdays = 0 WHERE supplierid = v_sup;
    UPDATE poultrycashaccounts SET currentbalance = 100000, allownegativebalance = false
    WHERE poultrycashaccountid = v_acct;

    SELECT poultryrawmaterialitemid INTO v_item FROM poultryrawmaterialitems
    WHERE farmid = v_farm LIMIT 1;
    IF v_item IS NULL THEN
        INSERT INTO poultryrawmaterialitems (farmid, itemname, createdat)
        VALUES (v_farm, 'ZZ Test Maize', now() at time zone 'utc')
        RETURNING poultryrawmaterialitemid INTO v_item;
    END IF;

    -- three purchases: 1000 (400 paid), 1500 (0 paid), 500 (200 paid)
    INSERT INTO poultryrawmaterialpurchases
      (farmid, poultryrawmaterialitemid, suppliername, supplierid, purchasedate, quantity, unitcost, totalcost, amountpaid, poultrycashaccountid, createdby, createdat, remainingquantity)
    VALUES (v_farm, v_item, 'ZZ Maize Supplier Ltd', v_sup, (CURRENT_DATE-40), 10, 100, 1000, 400, v_acct, 'tester', now() at time zone 'utc', 10)
    RETURNING poultryrawmaterialpurchaseid INTO p1;
    INSERT INTO poultryrawmaterialpurchases
      (farmid, poultryrawmaterialitemid, suppliername, supplierid, purchasedate, quantity, unitcost, totalcost, amountpaid, poultrycashaccountid, createdby, createdat, remainingquantity)
    VALUES (v_farm, v_item, 'ZZ Maize Supplier Ltd', v_sup, (CURRENT_DATE-20), 15, 100, 1500, 0, v_acct, 'tester', now() at time zone 'utc', 15)
    RETURNING poultryrawmaterialpurchaseid INTO p2;
    INSERT INTO poultryrawmaterialpurchases
      (farmid, poultryrawmaterialitemid, suppliername, supplierid, purchasedate, quantity, unitcost, totalcost, amountpaid, poultrycashaccountid, createdby, createdat, remainingquantity)
    VALUES (v_farm, v_item, 'ZZ Maize Supplier Ltd', v_sup, (CURRENT_DATE-5), 5, 100, 500, 200, v_acct, 'tester', now() at time zone 'utc', 5)
    RETURNING poultryrawmaterialpurchaseid INTO p3;

    -- Seed each purchase's own cash line the way a real insert would, so the
    -- test measures the payment's effect and not the missing history.
    PERFORM sppoultryrawmaterialpurchasecash_sync(v_farm, p1, v_acct, TRUE, 'tester');
    PERFORM sppoultryrawmaterialpurchasecash_sync(v_farm, p2, v_acct, TRUE, 'tester');
    PERFORM sppoultryrawmaterialpurchasecash_sync(v_farm, p3, v_acct, TRUE, 'tester');

    SELECT SUM(totalbalance) INTO v_bal FROM sppoultrysupplierbalances(v_farm, NULL, NULL, v_sup);
    RAISE NOTICE 'A. payable balance             expect 2400.00  got %', v_bal;
    SELECT count(*) INTO v_n FROM sppoultrysupplieropenpurchases(v_farm, v_sup);
    RAISE NOTICE 'B. open purchases              expect       3  got %', v_n;

    SELECT currentbalance INTO v_cash FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    RAISE NOTICE 'C. cash after seeding purchases expect 99400.00 got %', v_cash;

    -- BULK payment of 1000: 600 -> p1 (clears it), 400 -> p2
    v_pay := sppoultrysupplierpayment_record(v_farm, v_sup, 1000,
        jsonb_build_array(jsonb_build_object('documenttype','RawMaterialPurchase','documentid',p1,'amount',600),
                          jsonb_build_object('documenttype','RawMaterialPurchase','documentid',p2,'amount',400)),
        'Bank', NULL, v_acct, 'SP-001', 'bulk payable', 'SupplierBalances', 'tester');

    SELECT SUM(totalbalance) INTO v_bal FROM sppoultrysupplierbalances(v_farm, NULL, NULL, v_sup);
    RAISE NOTICE 'D. payable after 1000 bulk     expect 1400.00  got %', v_bal;
    RAISE NOTICE 'E. purchase 1 amountpaid       expect 1000.00  got %', (SELECT amountpaid FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid=p1);
    RAISE NOTICE 'F. purchase 2 amountpaid       expect  400.00  got %', (SELECT amountpaid FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid=p2);
    RAISE NOTICE 'G. purchase 3 untouched        expect  200.00  got %', (SELECT amountpaid FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid=p3);
    SELECT count(*) INTO v_n FROM sppoultrysupplieropenpurchases(v_farm, v_sup);
    RAISE NOTICE 'H. open purchases after        expect       2  got %', v_n;

    SELECT currentbalance INTO v_cash FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    RAISE NOTICE 'I. cash after 1000 out         expect 98400.00 got %', v_cash;

    SELECT COALESCE(SUM(amount),0) INTO v_bal FROM poultrycashtransactions
    WHERE farmid=v_farm AND sourcetype='PoultrySupplierPayment' AND sourceid=v_pay;
    RAISE NOTICE 'J. payment cash tx             expect -1000.00 got %', v_bal;

    SELECT count(*) INTO v_n FROM sppoultrysupplierpayment_allocations(v_farm, v_pay);
    RAISE NOTICE 'K. allocations                 expect       2  got %', v_n;

    SELECT COALESCE(SUM(amount),0) INTO v_bal FROM expense
    WHERE description LIKE 'Supplier payment #' || v_pay::text || ' against %';
    RAISE NOTICE 'L. expense booked (207 invar.) expect 1000.00  got %', v_bal;

    SELECT count(*) INTO v_n FROM fnbalanceaudit(v_farm, 'poultry');
    RAISE NOTICE 'M. audit drift rows            expect       0  got %', v_n;

    -- pay-balance from the Purchases page must produce an allocation too
    PERFORM sppoultryrawmaterialpurchase_paybalance(p3, v_farm, 300, 'Cash', NULL, 'tester');
    RAISE NOTICE 'N. p3 paid via purchase page   expect  500.00  got %', (SELECT amountpaid FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid=p3);
    SELECT count(*) INTO v_n FROM supplierpaymentallocation
    WHERE farmid=v_farm AND module='poultry' AND documenttype='RawMaterialPurchase' AND documentid=p3 AND status='Posted';
    RAISE NOTICE 'O. allocation from pay-balance expect       1  got %', v_n;
    SELECT SUM(totalbalance) INTO v_bal FROM sppoultrysupplierbalances(v_farm, NULL, NULL, v_sup);
    RAISE NOTICE 'P. payable after 300 more      expect 1100.00  got %', v_bal;

    -- statement
    SELECT runningbalance INTO v_bal FROM (
        SELECT runningbalance, row_number() OVER () rn FROM sppoultrysupplierstatement(v_farm, v_sup, NULL, NULL)) z
        ORDER BY rn DESC LIMIT 1;
    RAISE NOTICE 'Q. statement closing balance   expect 1100.00  got %', v_bal;

    -- REVERSE the bulk payment
    PERFORM sppoultrysupplierpayment_reverse(v_farm, v_pay, 'wrong supplier', 'tester');
    SELECT SUM(totalbalance) INTO v_bal FROM sppoultrysupplierbalances(v_farm, NULL, NULL, v_sup);
    RAISE NOTICE 'R. payable after reversal      expect 2100.00  got %', v_bal;
    SELECT currentbalance INTO v_cash FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    RAISE NOTICE 'S. cash after reversal         expect 99100.00 got %', v_cash;
    SELECT COALESCE(SUM(amount),0) INTO v_bal FROM expense
    WHERE description LIKE 'Supplier payment #' || v_pay::text || ' against %';
    RAISE NOTICE 'T. expense removed on reversal expect    0.00  got %', v_bal;
    SELECT count(*) INTO v_n FROM fnbalanceaudit(v_farm, 'poultry');
    RAISE NOTICE 'U. audit drift after reversal  expect       0  got %', v_n;

    -- negatives
    BEGIN
        PERFORM sppoultrysupplierpayment_record(v_farm, v_sup, 999999,
            jsonb_build_array(jsonb_build_object('documenttype','RawMaterialPurchase','documentid',p2,'amount',999999)),
            'Bank', NULL, v_acct, NULL, NULL, 'SupplierBalances', 'tester');
        RAISE NOTICE 'V. overdraw cash account       expect   BLOCK  got ALLOWED  <-- BUG';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'V. overdraw cash account       expect   BLOCK  got BLOCK';
    END;
    BEGIN
        PERFORM sppoultrysupplierpayment_record(v_farm, v_sup, 5000,
            jsonb_build_array(jsonb_build_object('documenttype','RawMaterialPurchase','documentid',p2,'amount',5000)),
            'Bank', NULL, v_acct, NULL, NULL, 'SupplierBalances', 'tester');
        RAISE NOTICE 'W. over-allocate one purchase  expect   BLOCK  got ALLOWED  <-- BUG';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'W. over-allocate one purchase  expect   BLOCK  got BLOCK';
    END;
    BEGIN
        PERFORM sppoultrysupplierpayment_record(v_farm, v_sup, 100,
            jsonb_build_array(jsonb_build_object('documenttype','Nonsense','documentid',p2,'amount',100)),
            'Bank', NULL, v_acct, NULL, NULL, 'SupplierBalances', 'tester');
        RAISE NOTICE 'X. unknown document type      expect   BLOCK  got ALLOWED  <-- BUG';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'X. unknown document type       expect   BLOCK  got BLOCK';
    END;
    BEGIN
        PERFORM sppoultrysupplierpayment_reverse(v_farm, v_pay, 'again', 'tester');
        RAISE NOTICE 'Y. double reversal             expect   BLOCK  got ALLOWED  <-- BUG';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Y. double reversal             expect   BLOCK  got BLOCK';
    END;
    BEGIN
        -- purchase belongs to this farm but to NO supplier: must not attach to v_sup
        PERFORM sppoultrysupplierpayment_record(v_farm, v_sup, 50,
            jsonb_build_array(jsonb_build_object('documenttype','RawMaterialPurchase','documentid',
              (SELECT poultryrawmaterialpurchaseid FROM poultryrawmaterialpurchases
               WHERE farmid=v_farm AND supplierid IS NULL AND totalcost>amountpaid LIMIT 1),'amount',50)),
            'Bank', NULL, v_acct, NULL, NULL, 'SupplierBalances', 'tester');
        RAISE NOTICE 'Z. purchase of other supplier  expect   BLOCK  got ALLOWED  <-- BUG';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Z. purchase of other supplier  expect   BLOCK  got BLOCK';
    END;
END
$t$;

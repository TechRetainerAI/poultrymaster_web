-- Behavioural checks for migration 238/239: expenses as payable documents.
--
-- Same shape as poultry-supplier-balances.test.sql -- one DO block, a NOTICE per
-- check reading "expect X got Y", then a set of negative cases that must each be
-- blocked. Run it inside a transaction you ROLL BACK; it creates suppliers,
-- expenses and payments.
--
--   psql ... -X -c "BEGIN;" -f poultry-expense-payables.test.sql -c "ROLLBACK;"
--
-- The farm id and cash account id below are hardcoded to a dev company. Change
-- them before running anywhere else.
--
-- What this file is really testing is the ONE claim 238 makes: that expenses can
-- become payables without a single existing number moving. Checks A and B are
-- that claim; everything after is the new behaviour.

DO $t$
DECLARE
    v_farm text := '3c4ac3cd-8792-4739-9b20-5f3b7d655a02';
    v_acct integer := 21;   -- Bank Account
    v_sup integer; v_item integer;
    e_paid integer; e_unpaid integer; e_part integer; e_nosup integer; e_noncash integer;
    p1 integer;
    v_pay integer; v_bal numeric; v_cash numeric; v_n integer; v_txt text;
    v_before_out numeric; v_after_out numeric;
BEGIN
    v_sup := fnpoultrysupplier_resolve(v_farm, 'ZZ Expense Supplier Ltd', 'tester');
    UPDATE supplier SET paymenttermsdays = 0 WHERE supplierid = v_sup;
    UPDATE poultrycashaccounts SET currentbalance = 100000, allownegativebalance = false
    WHERE poultrycashaccountid = v_acct;

    -- =====================================================================
    -- A. THE NO-OP CLAIM. Measure total cash OUTflow before anything is added.
    -- =====================================================================
    SELECT COALESCE(SUM(-r.amount), 0) INTO v_before_out
    FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r WHERE r.amount < 0;
    RAISE NOTICE 'A. baseline outflow measured             got %', v_before_out;

    SELECT COUNT(*) INTO v_n FROM fnpoultrypayables(v_farm) d WHERE d.documenttype = 'Expense';
    RAISE NOTICE 'B. legacy expenses as payables  expect       0  got %', v_n;
    -- Every pre-238 expense has amountpaid NULL, which resolves to "paid in
    -- full", so none of them owes anything and none can appear here.

    -- =====================================================================
    -- Four expenses covering every payment state, plus one purchase to prove a
    -- single payment can settle a bill and a purchase together.
    -- =====================================================================
    -- Paid in full: amountpaid NULL is the legacy shape and must stay off payables.
    INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                         supplier, supplierid, amountpaid, userid, farmid, createddate)
    VALUES ((CURRENT_DATE - 30), 'Utilities', 'ZZ paid bill', 500, 'Cash',
            'ZZ Expense Supplier Ltd', v_sup, NULL, 'tester', v_farm::uuid, now() at time zone 'utc')
    RETURNING expenseid INTO e_paid;

    INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                         supplier, supplierid, amountpaid, duedate, userid, farmid, createddate)
    VALUES ((CURRENT_DATE - 20), 'Utilities', 'ZZ unpaid bill', 1000, 'Cash',
            'ZZ Expense Supplier Ltd', v_sup, 0, (CURRENT_DATE - 1), 'tester', v_farm::uuid, now() at time zone 'utc')
    RETURNING expenseid INTO e_unpaid;

    INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                         supplier, supplierid, amountpaid, userid, farmid, createddate)
    VALUES ((CURRENT_DATE - 10), 'Feed', 'ZZ part-paid bill', 800, 'Cash',
            'ZZ Expense Supplier Ltd', v_sup, 300, 'tester', v_farm::uuid, now() at time zone 'utc')
    RETURNING expenseid INTO e_part;

    -- Unpaid but with nobody to owe: a legitimate record that must never appear
    -- on Supplier Balances, because putting it there would invent a creditor.
    INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                         supplierid, amountpaid, userid, farmid, createddate)
    VALUES ((CURRENT_DATE - 5), 'Utilities', 'ZZ unpaid, no supplier', 700, 'Cash',
            NULL, 0, 'tester', v_farm::uuid, now() at time zone 'utc')
    RETURNING expenseid INTO e_nosup;

    -- Internal use. Stock left, money did not (216).
    INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                         supplier, supplierid, amountpaid, userid, farmid, createddate, sourcetype)
    VALUES ((CURRENT_DATE - 5), 'Internal Use', 'ZZ internal use', 900, 'NonCash',
            'ZZ Expense Supplier Ltd', v_sup, 0, 'tester', v_farm::uuid, now() at time zone 'utc',
            'PoultryInternalUsage')
    RETURNING expenseid INTO e_noncash;

    -- ---- the generated column -------------------------------------------
    SELECT paymentstatus INTO v_txt FROM expense WHERE expenseid = e_paid;
    RAISE NOTICE 'C. paid status            expect     Paid  got %', v_txt;
    SELECT paymentstatus INTO v_txt FROM expense WHERE expenseid = e_unpaid;
    RAISE NOTICE 'D. unpaid status          expect   Unpaid  got %', v_txt;
    SELECT paymentstatus INTO v_txt FROM expense WHERE expenseid = e_part;
    RAISE NOTICE 'E. part status     expect PartiallyPaid  got %', v_txt;
    SELECT paymentstatus INTO v_txt FROM expense WHERE expenseid = e_noncash;
    RAISE NOTICE 'F. non-cash status        expect  NonCash  got %', v_txt;

    -- ---- which of them are payables --------------------------------------
    SELECT COUNT(*) INTO v_n FROM fnpoultrypayables(v_farm) d
    WHERE d.documenttype = 'Expense' AND d.balance > 0;
    RAISE NOTICE 'G. open expense payables  expect        2  got %', v_n;
    -- unpaid + part-paid. NOT the paid one, NOT the supplier-less one, NOT the
    -- non-cash one.

    SELECT COUNT(*) INTO v_n FROM fnpoultrypayables(v_farm) d
    WHERE d.documenttype = 'Expense' AND d.documentid IN (e_nosup, e_noncash);
    RAISE NOTICE 'H. no-supplier + non-cash excluded expect 0  got %', v_n;

    SELECT SUM(d.balance) INTO v_bal FROM fnpoultrypayables(v_farm) d
    WHERE d.documenttype = 'Expense';
    RAISE NOTICE 'I. expense payable balance expect 1500.00  got %', v_bal;   -- 1000 + 500

    -- An expense's own due date beats the supplier's terms (which are 0 here).
    SELECT duedate INTO v_txt FROM sppoultrysupplieropenpurchases(v_farm, v_sup)
    WHERE documenttype = 'Expense' AND documentid = e_unpaid;
    RAISE NOTICE 'J. explicit due date honoured expect % got %', (CURRENT_DATE - 1), v_txt;

    -- BOTH open bills are overdue, not just the one with an explicit due date:
    -- this supplier's paymenttermsdays is 0, so a bill's derived due date is its
    -- own expense date, and both were dated in the past.
    SELECT COUNT(*) INTO v_n FROM sppoultrysupplieropenpurchases(v_farm, v_sup)
    WHERE isoverdue;
    RAISE NOTICE 'K. overdue open items     expect        2  got %', v_n;

    -- =====================================================================
    -- L-Q. A payment against ONE expense.
    -- =====================================================================
    SELECT currentbalance INTO v_cash FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;

    v_pay := sppoultrysupplierpayment_record(v_farm, v_sup, 400,
        jsonb_build_array(jsonb_build_object('documenttype','Expense','documentid',e_unpaid,'amount',400)),
        'Bank', NULL, v_acct, 'SPX-001', 'part payment of a bill', 'SupplierBalances', 'tester');

    RAISE NOTICE 'L. expense amountpaid     expect   400.00  got %',
        (SELECT amountpaid FROM expense WHERE expenseid = e_unpaid);
    RAISE NOTICE 'M. expense status  expect PartiallyPaid  got %',
        (SELECT paymentstatus FROM expense WHERE expenseid = e_unpaid);

    SELECT documentbalancebefore || ' -> ' || documentbalanceafter INTO v_txt
    FROM supplierpaymentallocation
    WHERE farmid = v_farm AND module = 'poultry' AND paymentid = v_pay;
    RAISE NOTICE 'N. before -> after  expect 1000.00 -> 600.00  got %', v_txt;

    -- THE POINT OF THE WHOLE DESIGN: paying a bill must not book a second one.
    SELECT COUNT(*) INTO v_n FROM expense
    WHERE description LIKE 'Supplier payment #' || v_pay::text || ' against %';
    RAISE NOTICE 'O. NO second expense row  expect        0  got %', v_n;

    SELECT COALESCE(SUM(amount), 0) INTO v_bal FROM poultrycashtransactions
    WHERE farmid = v_farm AND sourcetype = 'PoultrySupplierPayment' AND sourceid = v_pay;
    RAISE NOTICE 'P. payment cash tx        expect  -400.00  got %', v_bal;

    SELECT currentbalance INTO v_bal FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    RAISE NOTICE 'Q. cash moved by exactly 400  expect % got %', (v_cash - 400), v_bal;

    -- =====================================================================
    -- R-V. ONE payment across a bill AND a purchase.
    -- =====================================================================
    SELECT poultryrawmaterialitemid INTO v_item FROM poultryrawmaterialitems
    WHERE farmid = v_farm LIMIT 1;
    IF v_item IS NULL THEN
        INSERT INTO poultryrawmaterialitems (farmid, itemname, createdat)
        VALUES (v_farm, 'ZZ Test Maize', now() at time zone 'utc')
        RETURNING poultryrawmaterialitemid INTO v_item;
    END IF;

    INSERT INTO poultryrawmaterialpurchases
      (farmid, poultryrawmaterialitemid, suppliername, supplierid, purchasedate, quantity,
       unitcost, totalcost, amountpaid, poultrycashaccountid, createdby, createdat, remainingquantity)
    VALUES (v_farm, v_item, 'ZZ Expense Supplier Ltd', v_sup, (CURRENT_DATE - 15), 10, 100, 1000, 0,
            v_acct, 'tester', now() at time zone 'utc', 10)
    RETURNING poultryrawmaterialpurchaseid INTO p1;

    v_pay := sppoultrysupplierpayment_record(v_farm, v_sup, 900,
        jsonb_build_array(
            jsonb_build_object('documenttype','Expense','documentid',e_part,'amount',400),
            jsonb_build_object('documenttype','RawMaterialPurchase','documentid',p1,'amount',500)),
        'Bank', NULL, v_acct, 'SPX-002', 'one payment, two kinds of payable', 'SupplierBalances', 'tester');

    SELECT COUNT(*) INTO v_n FROM poultrysupplierpayments WHERE poultrysupplierpaymentid = v_pay;
    RAISE NOTICE 'R. ONE payment header     expect        1  got %', v_n;
    SELECT COUNT(*) INTO v_n FROM supplierpaymentallocation
    WHERE farmid = v_farm AND module = 'poultry' AND paymentid = v_pay;
    RAISE NOTICE 'S. TWO allocations        expect        2  got %', v_n;
    SELECT COUNT(*) INTO v_n FROM poultrycashtransactions
    WHERE farmid = v_farm AND sourcetype = 'PoultrySupplierPayment' AND sourceid = v_pay;
    RAISE NOTICE 'T. ONE cash-out           expect        1  got %', v_n;

    -- 300 was paid when the bill was entered, this payment adds 400: 700 of 800,
    -- so 100 is still owed. Not "fully paid" -- the allocation is capped by what
    -- the bill still owed, which is the point.
    RAISE NOTICE 'U. expense paid 300+400   expect   700.00  got %',
        (SELECT amountpaid FROM expense WHERE expenseid = e_part);
    RAISE NOTICE 'U2. and still owes        expect   100.00  got %',
        (SELECT d.balance FROM fnpoultrypayables(v_farm) d
         WHERE d.documenttype = 'Expense' AND d.documentid = e_part);
    RAISE NOTICE 'V. purchase amountpaid    expect   500.00  got %',
        (SELECT amountpaid FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = p1);

    -- The purchase leg still books its expense row (207's invariant); the
    -- expense leg still does not. One payment, two different and correct rules.
    SELECT COUNT(*) INTO v_n FROM expense
    WHERE description LIKE 'Supplier payment #' || v_pay::text || ' against %';
    RAISE NOTICE 'W. purchase leg books 1 expense  expect 1  got %', v_n;

    -- =====================================================================
    -- X. THE CASH-FLOW ARMS MUST SUM, NOT DOUBLE.
    -- =====================================================================
    -- Outflow added should be exactly the cash that actually moved: 400 + 900,
    -- plus the 300 already paid at entry on e_part, plus the two bills' paid
    -- portions recognised at entry (500 for e_paid, 0 for e_unpaid/e_nosup) and
    -- the purchase's own line, which the allocation carved back out.
    SELECT COALESCE(SUM(-r.amount), 0) INTO v_after_out
    FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r WHERE r.amount < 0;
    RAISE NOTICE 'X. outflow added  expect  2100.00  got %', (v_after_out - v_before_out);
    -- 500 (e_paid) + 300 (e_part at entry) + 400 (payment 1) + 900 (payment 2).
    -- e_noncash contributes nothing: NonCash is excluded outright.

    SELECT COUNT(*) INTO v_n FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r
    WHERE r.rowsource = 'ExpensePayment';
    RAISE NOTICE 'Y. ExpensePayment rows    expect        2  got %', v_n;

    SELECT COUNT(*) INTO v_n FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r
    WHERE r.sourceid = e_noncash;
    RAISE NOTICE 'Z. non-cash never in cash flow  expect  0  got %', v_n;

    -- =====================================================================
    -- AA-AD. Reversal.
    -- =====================================================================
    PERFORM sppoultrysupplierpayment_reverse(v_farm, v_pay, 'test reversal', 'tester');

    RAISE NOTICE 'AA. expense balance restored expect 300.00 got %',
        (SELECT amountpaid FROM expense WHERE expenseid = e_part);
    RAISE NOTICE 'AB. purchase restored      expect     0.00  got %',
        (SELECT amountpaid FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = p1);
    SELECT COUNT(*) INTO v_n FROM supplierpaymentallocation
    WHERE farmid = v_farm AND module = 'poultry' AND paymentid = v_pay AND status = 'Posted';
    RAISE NOTICE 'AC. allocations reversed   expect        0  got %', v_n;
    -- Kept, never deleted: the audit trail is the whole reason for append-only.
    SELECT COUNT(*) INTO v_n FROM supplierpaymentallocation
    WHERE farmid = v_farm AND module = 'poultry' AND paymentid = v_pay;
    RAISE NOTICE 'AD. allocation rows kept   expect        2  got %', v_n;

    -- =====================================================================
    -- AE. The invariant. Must be empty throughout.
    -- =====================================================================
    SELECT COUNT(*) INTO v_n FROM fnbalanceaudit(v_farm, 'poultry');
    RAISE NOTICE 'AE. fnbalanceaudit rows    expect        0  got %', v_n;

    -- =====================================================================
    -- Negative cases. Each must be BLOCKED.
    -- =====================================================================
    BEGIN
        PERFORM sppoultrysupplierpayment_record(v_farm, v_sup, 9999,
            jsonb_build_array(jsonb_build_object('documenttype','Expense','documentid',e_unpaid,'amount',9999)),
            'Bank', NULL, v_acct, NULL, NULL, 'SupplierBalances', 'tester');
        RAISE NOTICE 'N1. over-applying to a bill               <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N1. over-applying to a bill               blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM sppoultrysupplierpayment_record(v_farm, v_sup, 100,
            jsonb_build_array(jsonb_build_object('documenttype','Expense','documentid',e_noncash,'amount',100)),
            'Bank', NULL, v_acct, NULL, NULL, 'SupplierBalances', 'tester');
        RAISE NOTICE 'N2. paying a non-cash internal cost       <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N2. paying a non-cash internal cost       blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM sppoultrysupplierpayment_record(v_farm, v_sup, 100,
            jsonb_build_array(jsonb_build_object('documenttype','Expense','documentid',e_nosup,'amount',100)),
            'Bank', NULL, v_acct, NULL, NULL, 'SupplierBalances', 'tester');
        RAISE NOTICE 'N3. paying a bill with no supplier        <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N3. paying a bill with no supplier        blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM sppoultrysupplierpayment_record(v_farm, v_sup, 100,
            jsonb_build_array(jsonb_build_object('documenttype','Expense','documentid',e_paid,'amount',100)),
            'Bank', NULL, v_acct, NULL, NULL, 'SupplierBalances', 'tester');
        RAISE NOTICE 'N4. paying an already-settled bill        <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N4. paying an already-settled bill        blocked: %', SQLERRM;
    END;

    -- An edit must never contradict money that has already moved.
    BEGIN
        PERFORM spexpense_update(e_unpaid, (CURRENT_DATE - 20)::timestamp, 'Utilities',
            'ZZ unpaid bill', 100, 'Cash', 'ZZ Expense Supplier Ltd', NULL, 'tester',
            v_farm::uuid, false, NULL, NULL, v_sup, NULL, NULL);
        RAISE NOTICE 'N5. cutting a bill below what was paid    <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N5. cutting a bill below what was paid    blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spexpense_insert((CURRENT_DATE)::timestamp, 'Utilities', 'ZZ bad', 100, 'Cash',
            NULL, NULL, 'tester', v_farm::uuid, NULL, NULL, v_sup, 500, NULL);
        RAISE NOTICE 'N6. paying more than the bill total       <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N6. paying more than the bill total       blocked: %', SQLERRM;
    END;

    RAISE NOTICE '--- done. ROLL BACK this transaction. ---';
END
$t$;

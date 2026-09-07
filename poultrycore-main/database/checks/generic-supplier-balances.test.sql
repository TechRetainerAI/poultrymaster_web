-- Behavioural checks for migration 248: the Generic payables side.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y", then negative
-- cases that must each be blocked. Run inside a transaction you ROLL BACK; it
-- creates suppliers, expenses, purchases and payments.
--
--   psql ... -X -c "BEGIN;" -f generic-supplier-balances.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 248
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- The two claims this file tests:
--   1. A Generic bill can be part-paid and settled later, through the same
--      payment + allocation machinery poultry and water use.
--   2. Nothing existing moved. genericexpenses was empty; purchases are read,
--      never rewritten, until a payment actually settles one.

DO $t$
DECLARE
    v_farm text := '056af97f-2099-481c-b5ac-3af20e3ef2b2';   -- Saas (Generic)
    v_sup  integer; v_sup2 integer; v_acct integer;
    e_bill integer; e_nosup integer; e_noncash integer; e_system integer;
    v_pur  integer; v_cat integer;
    v_pay  integer; v_n integer; v_bal numeric; v_cash numeric; v_txt text;
    v_before_payables numeric;
BEGIN
    -- =====================================================================
    -- Setup.
    -- =====================================================================
    INSERT INTO genericsuppliers (farmid, suppliername, paymenttermsdays, openingbalance,
                                  currentbalance, isactive, isdeleted, createdat)
    VALUES (v_farm, 'ZZ Cloud Provider', 0, 0, 0, TRUE, FALSE, now() at time zone 'utc')
    RETURNING genericsupplierid INTO v_sup;

    INSERT INTO genericsuppliers (farmid, suppliername, paymenttermsdays, openingbalance,
                                  currentbalance, isactive, isdeleted, createdat)
    VALUES (v_farm, 'ZZ Other Vendor', 0, 0, 0, TRUE, FALSE, now() at time zone 'utc')
    RETURNING genericsupplierid INTO v_sup2;

    -- genericexpenses.genericexpensecategoryid is NOT NULL, so the bills below
    -- need a category to hang on.
    SELECT genericexpensecategoryid INTO v_cat
    FROM   genericexpensecategories WHERE farmid = v_farm ORDER BY 1 LIMIT 1;
    IF v_cat IS NULL THEN
        INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat)
        VALUES (v_farm, 'ZZ Test Category', TRUE, FALSE, now() at time zone 'utc')
        RETURNING genericexpensecategoryid INTO v_cat;
    END IF;

    INSERT INTO genericcashaccounts (farmid, accountname, accounttype, openingbalance,
                                     currentbalance, allownegativebalance, isactive, createdat)
    VALUES (v_farm, 'ZZ Test Bank', 'Bank', 100000, 100000, FALSE, TRUE, now() at time zone 'utc')
    RETURNING genericcashaccountid INTO v_acct;

    -- THE NO-OP CLAIM: measure payables before adding anything of our own.
    SELECT COALESCE(SUM(d.balance), 0) INTO v_before_payables
    FROM   fngenericpayables(v_farm) d WHERE d.balance > 0;
    RAISE NOTICE 'A. payables before          expect     0.00  got %', v_before_payables;

    -- =====================================================================
    -- B-F. An unpaid bill becomes a payable.
    -- =====================================================================
    INSERT INTO genericexpenses (farmid, expensedate, description, amount, genericsupplierid,
                                 genericexpensecategoryid, paymentmethod, amountpaid, duedate,
                                 status, isdeleted, createdat)
    VALUES (v_farm, (CURRENT_DATE - 10), 'ZZ hosting bill', 1000, v_sup,
            v_cat, 'Bank', 0, (CURRENT_DATE - 1), 'Approved', FALSE, now() at time zone 'utc')
    RETURNING genericexpenseid INTO e_bill;

    RAISE NOTICE 'B. status is Unpaid         expect   Unpaid  got %',
        (SELECT paymentstatus FROM genericexpenses WHERE genericexpenseid = e_bill);
    RAISE NOTICE 'C. it is a payable          expect  1000.00  got %',
        (SELECT COALESCE(SUM(d.balance), 0) FROM fngenericpayables(v_farm) d
          WHERE d.documenttype = 'Expense' AND d.documentid = e_bill);
    RAISE NOTICE 'D. supplier owes it         expect  1000.00  got %',
        (SELECT COALESCE(SUM(b.totalbalance), 0) FROM spgenericsupplierbalances(v_farm) b
          WHERE b.partyid = v_sup);
    RAISE NOTICE 'E. and it is overdue        expect  1000.00  got %',
        (SELECT COALESCE(SUM(b.overdueamount), 0) FROM spgenericsupplierbalances(v_farm) b
          WHERE b.partyid = v_sup);
    RAISE NOTICE 'F. one open bill listed     expect        1  got %',
        (SELECT COUNT(*) FROM spgenericsupplieropenbills(v_farm, v_sup, NULL, NULL, 'All'));

    -- =====================================================================
    -- G-M. Paying it: part, then the rest.
    -- =====================================================================
    SELECT currentbalance INTO v_cash FROM genericcashaccounts WHERE genericcashaccountid = v_acct;

    v_pay := spgenericsupplierpayment_record(
        v_farm, v_sup, 400,
        jsonb_build_array(jsonb_build_object('documenttype','Expense','documentid',e_bill,'amount',400)),
        'Bank', NULL, v_acct, 'SP-001', 'part payment', 'SupplierBalances', 'tester');

    RAISE NOTICE 'G. expense amountpaid       expect   400.00  got %',
        (SELECT amountpaid FROM genericexpenses WHERE genericexpenseid = e_bill);
    RAISE NOTICE 'H. status PartiallyPaid  expect PartiallyPaid  got %',
        (SELECT paymentstatus FROM genericexpenses WHERE genericexpenseid = e_bill);
    RAISE NOTICE 'I. balance now              expect   600.00  got %',
        (SELECT COALESCE(SUM(d.balance), 0) FROM fngenericpayables(v_farm) d
          WHERE d.documenttype = 'Expense' AND d.documentid = e_bill);
    RAISE NOTICE 'J. ONE cash-out of 400      expect   400.00  got %',
        (v_cash - (SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct));
    RAISE NOTICE 'K. one cash row, not two    expect        1  got %',
        (SELECT COUNT(*) FROM genericcashtransactions
          WHERE farmid = v_farm AND sourcetype = 'SupplierPayment' AND sourceid = v_pay);

    -- Balance before/after is snapshotted, not recomputed later.
    SELECT balancebefore || ' -> ' || balanceafter INTO v_txt
    FROM   spgenericsupplierpayment_allocations(v_farm, v_pay) LIMIT 1;
    RAISE NOTICE 'L. before -> after  expect 1000.00 -> 600.00  got %', v_txt;

    -- NO expense row is booked when a bill is paid: the bill IS the cost.
    RAISE NOTICE 'M. no extra expense booked  expect        1  got %',
        (SELECT COUNT(*) FROM genericexpenses WHERE farmid = v_farm AND description LIKE 'ZZ%');

    -- =====================================================================
    -- N-Q. One payment across a bill AND a purchase.
    -- =====================================================================
    INSERT INTO genericpurchases (farmid, purchasedate, genericsupplierid, totalamount,
                                  amountpaid, balance, paymentstatus, status, isdeleted, createdat)
    VALUES (v_farm, (CURRENT_DATE - 5), v_sup, 500, 0, 500, 'Unpaid', 'Approved',
            FALSE, now() at time zone 'utc')
    RETURNING genericpurchaseid INTO v_pur;

    v_pay := spgenericsupplierpayment_record(
        v_farm, v_sup, 1100,
        jsonb_build_array(
            jsonb_build_object('documenttype','Expense','documentid',e_bill,'amount',600),
            jsonb_build_object('documenttype','Purchase','documentid',v_pur,'amount',500)),
        'Bank', NULL, v_acct, 'SP-002', 'one payment, two kinds of bill', 'SupplierBalances', 'tester');

    RAISE NOTICE 'N. ONE payment header       expect        1  got %',
        (SELECT COUNT(*) FROM genericsupplierpayments WHERE genericsupplierpaymentid = v_pay);
    RAISE NOTICE 'O. TWO allocations          expect        2  got %',
        (SELECT COUNT(*) FROM supplierpaymentallocation
          WHERE farmid = v_farm AND module = 'generic' AND paymentid = v_pay);
    RAISE NOTICE 'P. bill fully Paid          expect     Paid  got %',
        (SELECT paymentstatus FROM genericexpenses WHERE genericexpenseid = e_bill);
    RAISE NOTICE 'Q. purchase fully Paid      expect     Paid  got %',
        (SELECT paymentstatus FROM genericpurchases WHERE genericpurchaseid = v_pur);
    RAISE NOTICE 'R. supplier owes nothing    expect        0  got %',
        (SELECT COUNT(*) FROM spgenericsupplierbalances(v_farm) b WHERE b.partyid = v_sup);

    -- =====================================================================
    -- S-V. What must NEVER be payable.
    -- =====================================================================
    INSERT INTO genericexpenses (farmid, expensedate, description, amount, genericsupplierid,
                                 genericexpensecategoryid, paymentmethod, amountpaid, status,
                                 isdeleted, createdat)
    VALUES (v_farm, CURRENT_DATE, 'ZZ petty cash', 60, NULL, v_cat, 'Cash', 0, 'Approved',
            FALSE, now() at time zone 'utc')
    RETURNING genericexpenseid INTO e_nosup;
    RAISE NOTICE 'S. no supplier: not payable expect        0  got %',
        (SELECT COUNT(*) FROM fngenericpayables(v_farm) d
          WHERE d.documenttype = 'Expense' AND d.documentid = e_nosup);

    INSERT INTO genericexpenses (farmid, expensedate, description, amount, genericsupplierid,
                                 genericexpensecategoryid, paymentmethod, amountpaid, status,
                                 isdeleted, createdat)
    VALUES (v_farm, CURRENT_DATE, 'ZZ internal use', 90, v_sup, v_cat, 'NonCash', 0, 'Approved',
            FALSE, now() at time zone 'utc')
    RETURNING genericexpenseid INTO e_noncash;
    RAISE NOTICE 'T. NonCash: not payable     expect        0  got %',
        (SELECT COUNT(*) FROM fngenericpayables(v_farm) d
          WHERE d.documenttype = 'Expense' AND d.documentid = e_noncash);

    -- The trap: a supplier payment's own shadow expense row must never become a
    -- debt to the supplier just paid, payable again, forever.
    INSERT INTO genericexpenses (farmid, expensedate, description, amount, genericsupplierid,
                                 genericexpensecategoryid, paymentmethod, amountpaid, status,
                                 sourcetype, sourceid, isdeleted, createdat)
    VALUES (v_farm, CURRENT_DATE, 'ZZ shadow row', 250, v_sup, v_cat, 'Bank', 0, 'Approved',
            'GenericSupplierPayment', v_pay, FALSE, now() at time zone 'utc')
    RETURNING genericexpenseid INTO e_system;
    RAISE NOTICE 'U. system row: not payable  expect        0  got %',
        (SELECT COUNT(*) FROM fngenericpayables(v_farm) d
          WHERE d.documenttype = 'Expense' AND d.documentid = e_system);

    RAISE NOTICE 'V. audit clean              expect        0  got %',
        (SELECT COUNT(*) FROM fngenericbalanceaudit(v_farm));

    -- =====================================================================
    -- W-Z. Reversal.
    -- =====================================================================
    SELECT currentbalance INTO v_cash FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    PERFORM spgenericsupplierpayment_reverse(v_farm, v_pay, 'test reversal', 'tester');

    RAISE NOTICE 'W. bill owed again          expect   600.00  got %',
        (SELECT COALESCE(SUM(d.balance), 0) FROM fngenericpayables(v_farm) d
          WHERE d.documenttype = 'Expense' AND d.documentid = e_bill);
    RAISE NOTICE 'X. purchase owed again      expect   500.00  got %',
        (SELECT COALESCE(SUM(d.balance), 0) FROM fngenericpayables(v_farm) d
          WHERE d.documenttype = 'Purchase' AND d.documentid = v_pur);
    RAISE NOTICE 'Y. rows KEPT, not deleted   expect        2  got %',
        (SELECT COUNT(*) FROM supplierpaymentallocation
          WHERE farmid = v_farm AND module = 'generic' AND paymentid = v_pay);
    RAISE NOTICE 'Z. none still Posted        expect        0  got %',
        (SELECT COUNT(*) FROM supplierpaymentallocation
          WHERE farmid = v_farm AND module = 'generic' AND paymentid = v_pay AND status = 'Posted');
    RAISE NOTICE 'AA. cash returned           expect  1100.00  got %',
        ((SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct) - v_cash);
    RAISE NOTICE 'AB. history says Reversed   expect Reversed  got %',
        (SELECT status FROM spgenericsupplierpayment_history(v_farm, v_sup, NULL, NULL, NULL, NULL)
          WHERE paymentid = v_pay);
    RAISE NOTICE 'AC. audit still clean       expect        0  got %',
        (SELECT COUNT(*) FROM fngenericbalanceaudit(v_farm));

    -- =====================================================================
    -- Negative cases. Each must be BLOCKED.
    -- =====================================================================
    BEGIN
        PERFORM spgenericsupplierpayment_record(v_farm, v_sup, 9999,
            jsonb_build_array(jsonb_build_object('documenttype','Expense','documentid',e_bill,'amount',9999)),
            'Bank', NULL, v_acct, NULL, NULL, 'SupplierBalances', 'tester');
        RAISE NOTICE 'N1. over-applying to a bill            <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N1. over-applying to a bill            blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericsupplierpayment_record(v_farm, v_sup, 700,
            jsonb_build_array(jsonb_build_object('documenttype','Expense','documentid',e_bill,'amount',500)),
            'Bank', NULL, v_acct, NULL, NULL, 'SupplierBalances', 'tester');
        RAISE NOTICE 'N2. allocations not equal to payment   <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N2. allocations not equal to payment   blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericsupplierpayment_record(v_farm, v_sup2, 100,
            jsonb_build_array(jsonb_build_object('documenttype','Expense','documentid',e_bill,'amount',100)),
            'Bank', NULL, v_acct, NULL, NULL, 'SupplierBalances', 'tester');
        RAISE NOTICE 'N3. paying another supplier bill       <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N3. paying another supplier bill       blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericsupplierpayment_record(v_farm, v_sup, 100,
            jsonb_build_array(jsonb_build_object('documenttype','Expense','documentid',e_noncash,'amount',100)),
            'Bank', NULL, v_acct, NULL, NULL, 'SupplierBalances', 'tester');
        RAISE NOTICE 'N4. paying a non-cash internal cost    <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N4. paying a non-cash internal cost    blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericsupplierpayment_reverse(v_farm, v_pay, 'again', 'tester');
        RAISE NOTICE 'N5. reversing twice                    <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N5. reversing twice                    blocked: %', SQLERRM;
    END;

    RAISE NOTICE '--- done. ROLL BACK this transaction. ---';
END
$t$;

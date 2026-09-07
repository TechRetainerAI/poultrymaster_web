-- Behavioural checks for migration 245: money paid on a bill AT ENTRY becomes a
-- real supplier payment.
--
-- Same shape as poultry-expense-payables.test.sql -- one DO block, a NOTICE per
-- check reading "expect X got Y", then negative cases that must each be blocked.
-- Run it inside a transaction you ROLL BACK; it creates suppliers, expenses and
-- payments.
--
--   psql ... -X -c "BEGIN;" -f poultry-expense-entry-payments.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 245 (with
-- its own BEGIN;/COMMIT; stripped) ahead of this body inside the same
-- BEGIN; ... ROLLBACK;.
--
-- The farm id and cash account id below are hardcoded to a dev company. Change
-- them before running anywhere else.
--
-- The two claims this file exists to test:
--   1. Paying a supplier bill through the expense form now leaves a record on
--      Supplier Payments, and moves the cash exactly ONCE.
--   2. Nothing else changed. Petty cash, internal use and unpaid bills take the
--      byte-for-byte path they took before.

DO $t$
DECLARE
    v_farm text := '3c4ac3cd-8792-4739-9b20-5f3b7d655a02';
    v_acct integer := 21;   -- Bank Account
    v_sup  integer;
    e_paid integer; e_part integer; e_unpaid integer; e_nosup integer; e_noncash integer;
    v_n integer; v_cash numeric; v_start numeric; v_txt text; v_bal numeric;
BEGIN
    v_sup := fnpoultrysupplier_resolve(v_farm, 'ZZ Entry Payment Supplier', 'tester');
    UPDATE supplier SET paymenttermsdays = 0 WHERE supplierid = v_sup;
    UPDATE poultrycashaccounts SET currentbalance = 100000, allownegativebalance = false
    WHERE poultrycashaccountid = v_acct;
    SELECT currentbalance INTO v_start FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;

    -- =====================================================================
    -- A-F. A supplier bill entered as PAID IN FULL.
    -- =====================================================================
    e_paid := spexpense_insert(
        (CURRENT_DATE - 5)::timestamp, 'Utilities', 'ZZ paid at entry', 500, 'Cash',
        'ZZ Entry Payment Supplier', NULL, 'tester', v_farm::uuid,
        NULL, NULL, v_sup, NULL, NULL, v_acct);

    RAISE NOTICE 'A. a payment was recorded   expect        1  got %',
        (SELECT COUNT(*) FROM supplierpaymentallocation sa
          WHERE sa.module = 'poultry' AND sa.documenttype = 'Expense'
            AND sa.documentid = e_paid AND sa.status = 'Posted');

    RAISE NOTICE 'B. it says ExpenseEntry  expect ExpenseEntry  got %',
        (SELECT sp.sourcetype FROM poultrysupplierpayments sp
          JOIN supplierpaymentallocation sa ON sa.paymentid = sp.poultrysupplierpaymentid
         WHERE sa.module = 'poultry' AND sa.documenttype = 'Expense' AND sa.documentid = e_paid
         LIMIT 1);

    RAISE NOTICE 'C. the bill reads Paid      expect     Paid  got %',
        (SELECT paymentstatus FROM expense WHERE expenseid = e_paid);

    RAISE NOTICE 'D. amountpaid is the total  expect   500.00  got %',
        (SELECT COALESCE(amountpaid, amount) FROM expense WHERE expenseid = e_paid);

    -- The whole point of the design: the bill's own cash line resolves to
    -- "paid minus allocations" = 0, and the payment's CashOut carries the money.
    PERFORM sppoultryexpensecash_sync(v_farm, e_paid, v_acct, 500, 'ZZ paid at entry', 'tester');
    SELECT v_start - currentbalance INTO v_cash
    FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    RAISE NOTICE 'E. cash moved ONCE          expect   500.00  got %', v_cash;

    RAISE NOTICE 'F. nothing left owing       expect     0.00  got %',
        (SELECT COALESCE(SUM(d.balance), 0) FROM fnpoultrypayables(v_farm) d
          WHERE d.documenttype = 'Expense' AND d.documentid = e_paid);

    -- =====================================================================
    -- G-J. A bill entered PART paid, then topped up by an edit.
    -- =====================================================================
    e_part := spexpense_insert(
        (CURRENT_DATE - 4)::timestamp, 'Utilities', 'ZZ part paid at entry', 1000, 'Cash',
        'ZZ Entry Payment Supplier', NULL, 'tester', v_farm::uuid,
        NULL, NULL, v_sup, 300, NULL, v_acct);

    RAISE NOTICE 'G. entry payment of 300     expect   300.00  got %',
        (SELECT COALESCE(SUM(sa.amountapplied), 0) FROM supplierpaymentallocation sa
          WHERE sa.module = 'poultry' AND sa.documenttype = 'Expense'
            AND sa.documentid = e_part AND sa.status = 'Posted');

    RAISE NOTICE 'H. status PartiallyPaid  expect PartiallyPaid  got %',
        (SELECT paymentstatus FROM expense WHERE expenseid = e_part);

    -- Topping up 300 -> 800 is a SECOND payment of 500, not a restatement.
    PERFORM spexpense_update(
        e_part, (CURRENT_DATE - 4)::timestamp, 'Utilities', 'ZZ part paid at entry', 1000, 'Cash',
        'ZZ Entry Payment Supplier', NULL, 'tester', v_farm::uuid,
        FALSE, NULL, NULL, v_sup, 800, NULL, v_acct);

    RAISE NOTICE 'I. TWO payments now         expect        2  got %',
        (SELECT COUNT(*) FROM supplierpaymentallocation sa
          WHERE sa.module = 'poultry' AND sa.documenttype = 'Expense'
            AND sa.documentid = e_part AND sa.status = 'Posted');

    RAISE NOTICE 'J. the delta only           expect   500.00  got %',
        (SELECT sa.amountapplied FROM supplierpaymentallocation sa
          WHERE sa.module = 'poultry' AND sa.documenttype = 'Expense'
            AND sa.documentid = e_part AND sa.status = 'Posted'
          ORDER BY sa.allocationid DESC LIMIT 1);

    RAISE NOTICE 'K. totalling 800            expect   800.00  got %',
        (SELECT COALESCE(amountpaid, amount) FROM expense WHERE expenseid = e_part);

    RAISE NOTICE 'L. still owes 200           expect   200.00  got %',
        (SELECT COALESCE(SUM(d.balance), 0) FROM fnpoultrypayables(v_farm) d
          WHERE d.documenttype = 'Expense' AND d.documentid = e_part);

    -- =====================================================================
    -- M-Q. NOTHING ELSE CHANGED. Three bills that must take the old path.
    -- =====================================================================
    e_unpaid := spexpense_insert(
        (CURRENT_DATE - 3)::timestamp, 'Utilities', 'ZZ unpaid bill', 700, 'Cash',
        'ZZ Entry Payment Supplier', NULL, 'tester', v_farm::uuid,
        NULL, NULL, v_sup, 0, (CURRENT_DATE + 7), v_acct);

    RAISE NOTICE 'M. unpaid: no payment       expect        0  got %',
        (SELECT COUNT(*) FROM supplierpaymentallocation sa
          WHERE sa.module = 'poultry' AND sa.documenttype = 'Expense' AND sa.documentid = e_unpaid);
    RAISE NOTICE 'N. and it is a payable      expect   700.00  got %',
        (SELECT COALESCE(SUM(d.balance), 0) FROM fnpoultrypayables(v_farm) d
          WHERE d.documenttype = 'Expense' AND d.documentid = e_unpaid);

    -- Petty cash: paid, but there is nobody to owe, so nothing to record.
    e_nosup := spexpense_insert(
        (CURRENT_DATE - 2)::timestamp, 'Utilities', 'ZZ petty cash', 60, 'Cash',
        'Corner shop', NULL, 'tester', v_farm::uuid,
        NULL, NULL, NULL, NULL, NULL, v_acct);
    RAISE NOTICE 'O. no supplier: no payment  expect        0  got %',
        (SELECT COUNT(*) FROM supplierpaymentallocation sa
          WHERE sa.module = 'poultry' AND sa.documenttype = 'Expense' AND sa.documentid = e_nosup);
    RAISE NOTICE 'P. and amountpaid is NULL   expect        t  got %',
        (SELECT amountpaid IS NULL FROM expense WHERE expenseid = e_nosup);

    -- Internal use: stock left, no money moved.
    e_noncash := spexpense_insert(
        (CURRENT_DATE - 1)::timestamp, 'Internal Use', 'ZZ internal use', 90, 'NonCash',
        'ZZ Entry Payment Supplier', NULL, 'tester', v_farm::uuid,
        NULL, NULL, v_sup, NULL, NULL, NULL);
    RAISE NOTICE 'Q. NonCash: no payment      expect        0  got %',
        (SELECT COUNT(*) FROM supplierpaymentallocation sa
          WHERE sa.module = 'poultry' AND sa.documenttype = 'Expense' AND sa.documentid = e_noncash);

    -- Paid, with a supplier, but no account named: we do not know where the
    -- money left from, and a payment with no account posts no CashOut while
    -- zeroing the bill's own cash line. So it takes the old path instead.
    -- This is also what makes the migration safe to apply before the API that
    -- passes the account is redeployed.
    DECLARE e_noacct integer;
    BEGIN
        e_noacct := spexpense_insert(
            (CURRENT_DATE)::timestamp, 'Utilities', 'ZZ paid, no account', 400, 'Cash',
            'ZZ Entry Payment Supplier', NULL, 'tester', v_farm::uuid,
            NULL, NULL, v_sup, NULL, NULL, NULL);
        RAISE NOTICE 'U. no account: no payment   expect        0  got %',
            (SELECT COUNT(*) FROM supplierpaymentallocation sa
              WHERE sa.module = 'poultry' AND sa.documenttype = 'Expense'
                AND sa.documentid = e_noacct);
        RAISE NOTICE 'V. and it reads Paid        expect     Paid  got %',
            (SELECT paymentstatus FROM expense WHERE expenseid = e_noacct);
    END;

    -- =====================================================================
    -- R-T. The ledger and the invariant.
    -- =====================================================================
    SELECT COUNT(*) INTO v_n FROM sppoultrysupplierpayment_history(v_farm, v_sup, NULL, NULL, NULL, NULL) h
    WHERE h.sourcetype = 'ExpenseEntry';
    RAISE NOTICE 'R. on Supplier Payments     expect        3  got %', v_n;

    -- One allocation each, so the ledger shows them inline rather than expandable.
    RAISE NOTICE 'S. each is a single line    expect        t  got %',
        (SELECT bool_and(h.allocationcount = 1)
           FROM sppoultrysupplierpayment_history(v_farm, v_sup, NULL, NULL, NULL, NULL) h
          WHERE h.sourcetype = 'ExpenseEntry');

    RAISE NOTICE 'T. audit clean              expect        0  got %',
        (SELECT COUNT(*) FROM fnbalanceaudit(v_farm, 'poultry'));

    -- =====================================================================
    -- Negative cases. Each must be BLOCKED.
    -- =====================================================================
    BEGIN
        -- The behaviour chosen deliberately: to take money back you reverse the
        -- payment, so the correction is visible instead of silent.
        PERFORM spexpense_update(
            e_part, (CURRENT_DATE - 4)::timestamp, 'Utilities', 'ZZ part paid at entry', 1000, 'Cash',
            'ZZ Entry Payment Supplier', NULL, 'tester', v_farm::uuid,
            FALSE, NULL, NULL, v_sup, 200, NULL, v_acct);
        RAISE NOTICE 'N1. cutting amount paid below payments <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N1. cutting amount paid below payments blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spexpense_update(
            e_part, (CURRENT_DATE - 4)::timestamp, 'Utilities', 'ZZ part paid at entry', 500, 'Cash',
            'ZZ Entry Payment Supplier', NULL, 'tester', v_farm::uuid,
            FALSE, NULL, NULL, v_sup, 500, NULL, v_acct);
        RAISE NOTICE 'N2. cutting the total below payments   <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N2. cutting the total below payments   blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spexpense_insert(
            CURRENT_DATE::timestamp, 'Utilities', 'ZZ overpaid', 100, 'Cash',
            'ZZ Entry Payment Supplier', NULL, 'tester', v_farm::uuid,
            NULL, NULL, v_sup, 900, NULL, v_acct);
        RAISE NOTICE 'N3. paying more than the bill          <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N3. paying more than the bill          blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spexpense_insert(
            CURRENT_DATE::timestamp, 'Utilities', 'ZZ negative', 100, 'Cash',
            'ZZ Entry Payment Supplier', NULL, 'tester', v_farm::uuid,
            NULL, NULL, v_sup, -5, NULL, v_acct);
        RAISE NOTICE 'N4. a negative amount paid             <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N4. a negative amount paid             blocked: %', SQLERRM;
    END;

    RAISE NOTICE '--- done. ROLL BACK this transaction. ---';
END
$t$;

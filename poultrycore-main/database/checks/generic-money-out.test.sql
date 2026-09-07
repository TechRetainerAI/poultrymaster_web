-- Behavioural checks for migration 249: recurring expenses, staff payments and
-- owner money on the Generic side.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y", then negative
-- cases that must each be blocked. Run inside a transaction you ROLL BACK.
--
--   psql ... -X -c "BEGIN;" -f generic-money-out.test.sql -c "ROLLBACK;"
--
-- The three claims this file tests:
--   1. A recurring expense catches up every period it is behind, ONCE, and
--      moves cash exactly once per generated bill.
--   2. A staff payment posts a real expense and one CashOut, and reversing it
--      takes both back without deleting the record of what happened.
--   3. Owner money moves cash and NOTHING else -- it is neither revenue nor an
--      operating expense, so profit is untouched by how the owner funds things.

DO $t$
DECLARE
    v_farm text := '056af97f-2099-481c-b5ac-3af20e3ef2b2';   -- Saas (Generic)
    v_cat integer; v_acct integer; v_staff integer; v_sup integer;
    v_rec integer; v_pay integer; v_owner integer;
    v_n integer; v_cash numeric; v_start numeric; v_expenses numeric; v_txt text;
BEGIN
    -- =====================================================================
    -- Setup.
    -- =====================================================================
    SELECT genericexpensecategoryid INTO v_cat
    FROM   genericexpensecategories WHERE farmid = v_farm ORDER BY 1 LIMIT 1;
    IF v_cat IS NULL THEN
        INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat)
        VALUES (v_farm, 'ZZ Hosting', TRUE, FALSE, now() at time zone 'utc')
        RETURNING genericexpensecategoryid INTO v_cat;
    END IF;

    INSERT INTO genericcashaccounts (farmid, accountname, accounttype, openingbalance,
                                     currentbalance, allownegativebalance, isactive, createdat)
    VALUES (v_farm, 'ZZ Bank', 'Bank', 100000, 100000, FALSE, TRUE, now() at time zone 'utc')
    RETURNING genericcashaccountid INTO v_acct;

    INSERT INTO genericstaff (farmid, firstname, lastname, role, salarytype, basepay,
                              workertype, isactive, isdeleted, createdat)
    VALUES (v_farm, 'ZZ', 'Developer', 'Other', 'Monthly', 3000,
            'Contractor', TRUE, FALSE, now() at time zone 'utc')
    RETURNING genericstaffid INTO v_staff;

    SELECT currentbalance INTO v_start FROM genericcashaccounts WHERE genericcashaccountid = v_acct;

    -- =====================================================================
    -- A-H. A recurring expense, three months behind.
    -- =====================================================================
    v_rec := spgenericrecurringexpense_insert(
        v_farm, 'ZZ Cloud Hosting', v_cat, 600, 'Monthly',
        (CURRENT_DATE - INTERVAL '2 months')::date,
        NULL, NULL, 'Bank', v_acct, TRUE, TRUE, 'monthly cloud bill', 'tester');

    RAISE NOTICE 'A. it is due                expect        t  got %',
        (SELECT isdue FROM spgenericrecurringexpense_getall(v_farm, NULL)
          WHERE genericrecurringexpenseid = v_rec);
    RAISE NOTICE 'B. preview shows it         expect        1  got %',
        (SELECT COUNT(*) FROM spgenericrecurringexpense_preview(v_farm, NULL));
    RAISE NOTICE 'C. nothing generated yet    expect        0  got %',
        (SELECT generatedcount FROM spgenericrecurringexpense_getall(v_farm, NULL)
          WHERE genericrecurringexpenseid = v_rec);

    v_n := spgenericrecurringexpense_generate(v_farm, NULL, 'tester');
    RAISE NOTICE 'D. catch-up generated       expect        3  got %', v_n;

    RAISE NOTICE 'E. three expenses exist     expect        3  got %',
        (SELECT COUNT(*) FROM genericexpenses
          WHERE farmid = v_farm AND genericrecurringexpenseid = v_rec
            AND NOT COALESCE(isdeleted, FALSE));

    RAISE NOTICE 'F. cash moved 3 x 600       expect  1800.00  got %',
        (v_start - (SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct));

    RAISE NOTICE 'G. each reads Paid          expect        3  got %',
        (SELECT COUNT(*) FROM genericexpenses
          WHERE farmid = v_farm AND genericrecurringexpenseid = v_rec
            AND paymentstatus = 'Paid');

    -- Pressing Generate again must not bill the same months twice.
    v_n := spgenericrecurringexpense_generate(v_farm, NULL, 'tester');
    RAISE NOTICE 'H. re-run adds nothing      expect        0  got %', v_n;

    -- A paused one generates nothing at all.
    PERFORM spgenericrecurringexpense_setstatus(v_rec, v_farm, 'Paused', 'tester', NULL);
    RAISE NOTICE 'I. paused: not in preview   expect        0  got %',
        (SELECT COUNT(*) FROM spgenericrecurringexpense_preview(v_farm, (CURRENT_DATE + 400)));

    -- =====================================================================
    -- J-P. Paying a contractor.
    -- =====================================================================
    SELECT currentbalance INTO v_cash FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    SELECT COUNT(*) INTO v_expenses FROM genericexpenses
    WHERE farmid = v_farm AND NOT COALESCE(isdeleted, FALSE);

    v_pay := spgenericstaffpayment_record(
        v_farm, v_staff, 3000, NULL, 'Bank', v_acct, NULL,
        (CURRENT_DATE - 30), (CURRENT_DATE - 1), NULL, 'SAL-001', 'tester');

    RAISE NOTICE 'J. an expense was booked    expect        1  got %',
        ((SELECT COUNT(*) FROM genericexpenses
           WHERE farmid = v_farm AND NOT COALESCE(isdeleted, FALSE)) - v_expenses);
    RAISE NOTICE 'K. it is the payment''s own  expect        t  got %',
        (SELECT sp.genericexpenseid IS NOT NULL FROM genericstaffpayments sp
          WHERE sp.genericstaffpaymentid = v_pay);
    RAISE NOTICE 'L. cash out of 3000         expect  3000.00  got %',
        (v_cash - (SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct));
    RAISE NOTICE 'M. one cash row, not two    expect        1  got %',
        (SELECT COUNT(*) FROM genericcashtransactions
          WHERE farmid = v_farm AND sourcetype = 'GenericStaffPayment' AND sourceid = v_pay);
    RAISE NOTICE 'N. history shows the payee  expect ZZ Developer  got %',
        (SELECT staffname FROM spgenericstaffpayment_getall(v_farm, v_staff, NULL, NULL) LIMIT 1);

    PERFORM spgenericstaffpayment_reverse(v_farm, v_pay, 'paid twice by mistake', 'tester');
    RAISE NOTICE 'O. cash came back           expect  3000.00  got %',
        ((SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct) - v_cash + 3000);
    RAISE NOTICE 'P. expense left the books   expect        t  got %',
        (SELECT e.isdeleted FROM genericexpenses e
          JOIN genericstaffpayments sp ON sp.genericexpenseid = e.genericexpenseid
         WHERE sp.genericstaffpaymentid = v_pay);
    RAISE NOTICE 'Q. record KEPT, not deleted expect Reversed  got %',
        (SELECT status FROM genericstaffpayments WHERE genericstaffpaymentid = v_pay);

    -- =====================================================================
    -- R-W. Owner money is neither revenue nor an expense.
    -- =====================================================================
    SELECT currentbalance INTO v_cash FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    SELECT COUNT(*) INTO v_expenses FROM genericexpenses
    WHERE farmid = v_farm AND NOT COALESCE(isdeleted, FALSE);

    v_owner := spgenericownerentry_record(
        v_farm, 'Contribution', 5000, v_acct, NULL, 'Bank', 'ZZ Owner', 'OC-001',
        'startup funding', 'tester');

    RAISE NOTICE 'R. contribution: cash in    expect  5000.00  got %',
        ((SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct) - v_cash);
    RAISE NOTICE 'S. NO expense was booked    expect        0  got %',
        ((SELECT COUNT(*) FROM genericexpenses
           WHERE farmid = v_farm AND NOT COALESCE(isdeleted, FALSE)) - v_expenses);
    RAISE NOTICE 'T. and NO sale was booked   expect        0  got %',
        (SELECT COUNT(*) FROM genericsales
          WHERE farmid = v_farm AND notes ILIKE '%owner%');

    SELECT currentbalance INTO v_cash FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    PERFORM spgenericownerentry_record(
        v_farm, 'Draw', 1200, v_acct, NULL, 'Bank', 'ZZ Owner', 'OD-001', 'owner draw', 'tester');
    RAISE NOTICE 'U. draw: cash out           expect  1200.00  got %',
        (v_cash - (SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct));

    RAISE NOTICE 'V. both listed              expect        2  got %',
        (SELECT COUNT(*) FROM spgenericownerentry_getall(v_farm, NULL, NULL, NULL));

    SELECT currentbalance INTO v_cash FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    PERFORM spgenericownerentry_reverse(v_farm, v_owner, 'entered twice', 'tester');
    RAISE NOTICE 'W. reversal takes it back   expect  5000.00  got %',
        (v_cash - (SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct));

    -- =====================================================================
    -- Negative cases. Each must be BLOCKED.
    -- =====================================================================
    BEGIN
        PERFORM spgenericrecurringexpense_insert(
            v_farm, 'ZZ bad frequency', v_cat, 100, 'Fortnightly', CURRENT_DATE,
            NULL, NULL, NULL, NULL, TRUE, TRUE, NULL, 'tester');
        RAISE NOTICE 'N1. unknown frequency                  <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N1. unknown frequency                  blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericrecurringexpense_insert(
            v_farm, 'ZZ backwards', v_cat, 100, 'Monthly', CURRENT_DATE,
            NULL, (CURRENT_DATE - 30), NULL, NULL, TRUE, TRUE, NULL, 'tester');
        RAISE NOTICE 'N2. end date before start              <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N2. end date before start              blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericrecurringexpense_setstatus(v_rec, v_farm, 'Cancelled', 'tester', NULL);
        RAISE NOTICE 'N3. cancelling with no reason          <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N3. cancelling with no reason          blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericstaffpayment_record(v_farm, v_staff, -5, NULL, 'Bank', v_acct);
        RAISE NOTICE 'N4. a negative staff payment           <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N4. a negative staff payment           blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericstaffpayment_reverse(v_farm, v_pay, 'again', 'tester');
        RAISE NOTICE 'N5. reversing a payment twice          <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N5. reversing a payment twice          blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericownerentry_record(v_farm, 'Contribution', 100, NULL);
        RAISE NOTICE 'N6. owner money with no account        <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N6. owner money with no account        blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericownerentry_record(v_farm, 'Salary', 100, v_acct);
        RAISE NOTICE 'N7. an invented entry type             <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N7. an invented entry type             blocked: %', SQLERRM;
    END;

    RAISE NOTICE '--- done. ROLL BACK this transaction. ---';
END
$t$;

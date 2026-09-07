-- Behavioural checks for migrations 242-244: Generic subscription billing,
-- invoices on genericsales, and customer payments with allocation.
--
-- Same shape as the poultry checks: one DO $t$ block, a NOTICE per check reading
-- "expect X got Y", then negative cases that must each be blocked. Run it inside
-- a transaction you ROLL BACK; it creates a company profile, a customer, a
-- subscription, invoices and payments.
--
--   psql ... -X -c "BEGIN;" -f generic-subscription-billing.test.sql -c "ROLLBACK;"
--
-- To validate the migrations and their behaviour in one pass, concatenate
-- 242/243/244 (with their own BEGIN;/COMMIT; stripped) ahead of this body inside
-- the same BEGIN; ... ROLLBACK;.
--
-- The farm id below is a real Generic company on dev. NOTE it is farms.FARMID,
-- not farms.id -- the two never match and passing the wrong one yields "Company
-- not found" rather than an error you can read.

DO $t$
DECLARE
    v_farm text := '31f82b93-91ac-4022-ba1e-975d115fc072';  -- Tech Retainer LLC
    v_cust integer; v_plan integer; v_sub integer; v_acct integer;
    v_pay integer; v_n integer; v_bal numeric; v_txt text; v_cash numeric;
    v_inv1 integer; v_inv2 integer;
BEGIN
    -- =====================================================================
    -- Setup: a SaaS company with a customer on a GHC 500/month plan,
    -- backdated two months so catch-up billing is exercised.
    -- =====================================================================
    INSERT INTO genericcompanyprofiles (farmid, defaultcurrency, createdat)
    VALUES (v_farm, 'GHC', now() at time zone 'utc')
    ON CONFLICT DO NOTHING;

    PERFORM spgenericbusinesstemplate_apply(v_farm, 'SubscriptionServiceBusiness', 'SaaS', 'tester');

    SELECT paymentstatus INTO v_txt FROM genericsales WHERE 1=0;  -- keep v_txt typed

    INSERT INTO genericcustomers (farmid, customername, customertype, creditlimit,
                                  paymenttermsdays, openingbalance, currentbalance,
                                  isactive, isdeleted, createdat)
    VALUES (v_farm, 'ZZ Acme Ltd', 'Business', 0, 0, 0, 0, TRUE, FALSE, now() at time zone 'utc')
    RETURNING genericcustomerid INTO v_cust;

    SELECT genericserviceid INTO v_plan FROM genericservices
    WHERE farmid = v_farm AND servicename = 'Monthly Subscription';

    SELECT genericcashaccountid INTO v_acct FROM genericcashaccounts
    WHERE farmid = v_farm ORDER BY genericcashaccountid LIMIT 1;
    UPDATE genericcashaccounts SET currentbalance = 10000 WHERE genericcashaccountid = v_acct;

    RAISE NOTICE 'A. template applied         expect     SaaS  got %',
        (SELECT genericindustrytemplate FROM genericcompanyprofiles WHERE farmid = v_farm);
    RAISE NOTICE 'B. subscription modules on  expect     true  got %',
        (SELECT enablesubscriptions FROM spgenericmodulesettings_get(v_farm));
    RAISE NOTICE 'C. stock modules off        expect    false  got %',
        (SELECT enableproducts FROM spgenericmodulesettings_get(v_farm));

    -- The Service Plans page reads this, and it must see the seeded plans with
    -- the frequency the template gave them.
    RAISE NOTICE 'C2. seeded plans           expect       >0  got %',
        (SELECT COUNT(*) FROM spgenericserviceplan_getall(v_farm));
    RAISE NOTICE 'C3. monthly plan frequency expect  Monthly  got %',
        (SELECT billingfrequency FROM spgenericserviceplan_getall(v_farm)
          WHERE servicename = 'Monthly Subscription');

    PERFORM spgenericserviceplan_setplan(v_plan, v_farm, 'Recurring', 'Quarterly');
    RAISE NOTICE 'C4. frequency is editable  expect Quarterly  got %',
        (SELECT billingfrequency FROM spgenericserviceplan_getall(v_farm)
          WHERE genericserviceid = v_plan);
    PERFORM spgenericserviceplan_setplan(v_plan, v_farm, 'Recurring', 'Monthly');

    v_sub := spgenericsubscription_insert(
        v_farm, v_cust, v_plan, (CURRENT_DATE - INTERVAL '2 months')::date,
        'Monthly', 500, 0, 0, 14, TRUE, NULL, 'Bank', v_acct, 'ZZ test', 'tester');
    PERFORM spgenericsubscription_setstatus(v_sub, v_farm, 'Active', 'tester', NULL);

    RAISE NOTICE 'D. subscription number      expect  SUB-....  got %',
        (SELECT subscriptionnumber FROM genericsubscriptions WHERE genericsubscriptionid = v_sub);

    -- =====================================================================
    -- E-J. Billing.
    -- =====================================================================
    SELECT COUNT(*) INTO v_n FROM spgenericbillingrun_preview(v_farm);
    RAISE NOTICE 'E. preview shows the sub    expect        1  got %', v_n;

    PERFORM spgenericbillingrun_generate(v_farm, NULL, 'tester');

    SELECT COUNT(*) INTO v_n FROM genericsales
    WHERE farmid = v_farm AND genericsubscriptionid = v_sub;
    RAISE NOTICE 'F. catch-up invoices        expect        3  got %', v_n;

    RAISE NOTICE 'G. invoices are DRAFT       expect        3  got %',
        (SELECT COUNT(*) FROM genericsales WHERE farmid = v_farm
           AND genericsubscriptionid = v_sub AND status = 'Draft');

    -- A draft is not a receivable, so nothing is owed yet.
    SELECT COALESCE(SUM(totalbalance), 0) INTO v_bal FROM spgenericcustomerbalances(v_farm);
    RAISE NOTICE 'H. balance while draft      expect     0.00  got %', v_bal;

    -- Pressing generate twice must not bill the customer twice.
    PERFORM spgenericbillingrun_generate(v_farm, NULL, 'tester');
    SELECT COUNT(*) INTO v_n FROM genericsales
    WHERE farmid = v_farm AND genericsubscriptionid = v_sub;
    RAISE NOTICE 'I. re-run adds nothing      expect        3  got %', v_n;

    RAISE NOTICE 'J. due date = start + 14    expect        t  got %',
        (SELECT bool_and(duedate = billingperiodstart + 14) FROM genericsales
          WHERE farmid = v_farm AND genericsubscriptionid = v_sub);

    -- =====================================================================
    -- K-Q. Approve two invoices, then pay across both.
    -- =====================================================================
    SELECT genericsaleid INTO v_inv1 FROM genericsales
    WHERE farmid = v_farm AND genericsubscriptionid = v_sub ORDER BY billingperiodstart LIMIT 1;
    SELECT genericsaleid INTO v_inv2 FROM genericsales
    WHERE farmid = v_farm AND genericsubscriptionid = v_sub AND genericsaleid <> v_inv1
    ORDER BY billingperiodstart LIMIT 1;

    PERFORM spgenericsale_approve(v_inv1, v_farm, 'tester');
    PERFORM spgenericsale_approve(v_inv2, v_farm, 'tester');

    SELECT COALESCE(SUM(totalbalance), 0) INTO v_bal FROM spgenericcustomerbalances(v_farm);
    RAISE NOTICE 'K. balance after approve    expect  1000.00  got %', v_bal;

    SELECT COUNT(*) INTO v_n FROM spgenericcustomeropeninvoices(v_farm, v_cust);
    RAISE NOTICE 'L. open invoices            expect        2  got %', v_n;

    SELECT currentbalance INTO v_cash FROM genericcashaccounts WHERE genericcashaccountid = v_acct;

    -- ONE payment across BOTH invoices: 500 clears the first, 200 part-pays the second.
    v_pay := spgenericcustomerpayment_record(
        v_farm, v_cust, 700,
        jsonb_build_array(jsonb_build_object('saleid', v_inv1, 'amount', 500),
                          jsonb_build_object('saleid', v_inv2, 'amount', 200)),
        'Bank', NULL, v_acct, 'RCPT-001', 'part payment', 'CustomerBalances', 'tester');

    RAISE NOTICE 'M. ONE payment header       expect        1  got %',
        (SELECT COUNT(*) FROM genericcustomerpayments WHERE genericcustomerpaymentid = v_pay);
    RAISE NOTICE 'N. TWO allocations          expect        2  got %',
        (SELECT COUNT(*) FROM customerpaymentallocation
          WHERE farmid = v_farm AND module = 'generic' AND paymentid = v_pay);
    RAISE NOTICE 'O. first invoice Paid       expect     Paid  got %',
        (SELECT paymentstatus FROM genericsales WHERE genericsaleid = v_inv1);
    RAISE NOTICE 'P. second PartiallyPaid  expect PartiallyPaid  got %',
        (SELECT paymentstatus FROM genericsales WHERE genericsaleid = v_inv2);

    SELECT COALESCE(SUM(totalbalance), 0) INTO v_bal FROM spgenericcustomerbalances(v_farm);
    RAISE NOTICE 'Q. balance after payment    expect   300.00  got %', v_bal;

    RAISE NOTICE 'R. ONE cash-in of 700       expect   700.00  got %',
        ((SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct) - v_cash);
    RAISE NOTICE 'S. one cash row, not two    expect        1  got %',
        (SELECT COUNT(*) FROM genericcashtransactions
          WHERE farmid = v_farm AND sourcetype = 'CustomerPayment' AND sourceid = v_pay);

    -- Balance before/after are snapshotted, not recomputed later.
    SELECT salebalancebefore || ' -> ' || salebalanceafter INTO v_txt
    FROM customerpaymentallocation
    WHERE farmid = v_farm AND module = 'generic' AND paymentid = v_pay AND saleid = v_inv2;
    RAISE NOTICE 'T. before -> after  expect 500.00 -> 300.00  got %', v_txt;

    SELECT COUNT(*) INTO v_n FROM spgenericcustomerpayment_history(v_farm, v_cust);
    RAISE NOTICE 'U. payment history rows     expect        1  got %', v_n;
    RAISE NOTICE 'V. history says Posted      expect   Posted  got %',
        (SELECT status FROM spgenericcustomerpayment_history(v_farm, v_cust) LIMIT 1);
    RAISE NOTICE 'W. statement lines          expect        3  got %',
        (SELECT COUNT(*) FROM spgenericcustomerstatement(v_farm, v_cust));

    RAISE NOTICE 'X. audit clean              expect        0  got %',
        (SELECT COUNT(*) FROM fngenericbalanceaudit(v_farm));

    -- =====================================================================
    -- Y-AB. Reversal.
    -- =====================================================================
    PERFORM spgenericcustomerpayment_reverse(v_farm, v_pay, 'test reversal', 'tester');

    SELECT COALESCE(SUM(totalbalance), 0) INTO v_bal FROM spgenericcustomerbalances(v_farm);
    RAISE NOTICE 'Y. balance restored         expect  1000.00  got %', v_bal;
    RAISE NOTICE 'Z. allocations reversed     expect        0  got %',
        (SELECT COUNT(*) FROM customerpaymentallocation
          WHERE farmid = v_farm AND module = 'generic' AND paymentid = v_pay AND status = 'Posted');
    RAISE NOTICE 'AA. rows KEPT, not deleted  expect        2  got %',
        (SELECT COUNT(*) FROM customerpaymentallocation
          WHERE farmid = v_farm AND module = 'generic' AND paymentid = v_pay);
    RAISE NOTICE 'AB. cash returned           expect     0.00  got %',
        ((SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct) - v_cash);
    RAISE NOTICE 'AC. audit still clean       expect        0  got %',
        (SELECT COUNT(*) FROM fngenericbalanceaudit(v_farm));

    -- =====================================================================
    -- Negative cases. Each must be BLOCKED.
    -- =====================================================================
    BEGIN
        PERFORM spgenericcustomerpayment_record(v_farm, v_cust, 9999,
            jsonb_build_array(jsonb_build_object('saleid', v_inv1, 'amount', 9999)),
            'Bank', NULL, v_acct, NULL, NULL, 'CustomerBalances', 'tester');
        RAISE NOTICE 'N1. over-applying to an invoice        <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N1. over-applying to an invoice        blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericcustomerpayment_record(v_farm, v_cust, 700,
            jsonb_build_array(jsonb_build_object('saleid', v_inv1, 'amount', 500)),
            'Bank', NULL, v_acct, NULL, NULL, 'CustomerBalances', 'tester');
        RAISE NOTICE 'N2. allocations not equal to payment   <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N2. allocations not equal to payment   blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericcustomerpayment_record(v_farm, v_cust, 100,
            jsonb_build_array(jsonb_build_object('saleid', v_inv1, 'amount', 50),
                              jsonb_build_object('saleid', v_inv1, 'amount', 50)),
            'Bank', NULL, v_acct, NULL, NULL, 'CustomerBalances', 'tester');
        RAISE NOTICE 'N3. same invoice twice                 <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N3. same invoice twice                 blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericcustomerpayment_reverse(v_farm, v_pay, 'again', 'tester');
        RAISE NOTICE 'N4. reversing twice                    <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N4. reversing twice                    blocked: %', SQLERRM;
    END;

    -- A FRESH payment, so this tests the empty-reason guard and not the
    -- already-reversed guard that sits ahead of it.
    v_pay := spgenericcustomerpayment_record(v_farm, v_cust, 100,
        jsonb_build_array(jsonb_build_object('saleid', v_inv1, 'amount', 100)),
        'Bank', NULL, v_acct, NULL, NULL, 'CustomerBalances', 'tester');
    BEGIN
        PERFORM spgenericcustomerpayment_reverse(v_farm, v_pay, '   ', 'tester');
        RAISE NOTICE 'N5. reversing with no reason           <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N5. reversing with no reason           blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericserviceplan_setplan(v_plan, v_farm, 'Recurring', 'Fortnightly');
        RAISE NOTICE 'N7. unknown billing frequency          <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N7. unknown billing frequency          blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericsubscription_setstatus(v_sub, v_farm, 'Cancelled', 'tester', NULL);
        RAISE NOTICE 'N6. cancelling with no reason          <-- BUG, allowed';
    EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'N6. cancelling with no reason          blocked: %', SQLERRM;
    END;

    RAISE NOTICE '--- done. ROLL BACK this transaction. ---';
END
$t$;

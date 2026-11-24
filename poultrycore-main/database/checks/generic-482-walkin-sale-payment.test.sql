-- 482_Enock_GenericWalkInSalePayment: a paid walk-in Generic sale approves.
-- Self-contained: BEGIN ... ROLLBACK. Builds its own walk-in draft sale in the
-- Generic company that has the most sales, so it runs on any database.
BEGIN;
DO $$
DECLARE
    v_farm     text;
    v_acct     integer;
    v_sale     integer;
    v_pay      integer;
    v_cash0    numeric;
    v_cash1    numeric;
    v_n        integer;
    v_led      integer;
BEGIN
    SELECT s.farmid INTO v_farm FROM genericsales s GROUP BY s.farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT a.genericcashaccountid, a.currentbalance INTO v_acct, v_cash0
    FROM genericcashaccounts a WHERE a.farmid = v_farm ORDER BY a.genericcashaccountid LIMIT 1;
    IF v_acct IS NULL THEN RAISE EXCEPTION 'FAIL 482.0: no cash account in %', v_farm; END IF;

    -- a draft walk-in sale, paid in full, no items (approval of the payment path only)
    INSERT INTO genericsales (farmid, saledate, status, genericcustomerid, genericcashaccountid,
                              totalamount, amountpaid, paymentmethod, createdby)
    VALUES (v_farm, now() AT TIME ZONE 'utc', 'Draft', NULL, v_acct, 250, 250, 'Cash', '482-check')
    RETURNING genericsaleid INTO v_sale;
    SELECT count(*) INTO v_led FROM genericcustomerledger WHERE farmid = v_farm;

    -- 1. approving it no longer violates the customer foreign key
    PERFORM spgenericsale_approve(v_sale, v_farm, '482-check');
    SELECT p.genericcustomerpaymentid INTO v_pay FROM genericcustomerpayments p
    WHERE p.farmid = v_farm AND p.linkedsaleid = v_sale AND p.genericcustomerid IS NULL AND p.amount = 250;
    IF v_pay IS NULL THEN RAISE EXCEPTION 'FAIL 482.1: no walk-in payment (no customer) for the sale'; END IF;
    RAISE NOTICE 'ok 482.1 a paid walk-in sale approves; its payment has no customer (not 0)';

    -- 2. the cash came in, pointing at that payment; no customer ledger line
    SELECT count(*) INTO v_n FROM genericcashtransactions t
    WHERE t.farmid = v_farm AND t.sourcetype = 'CustomerPayment' AND t.sourceid = v_pay AND t.transactiontype = 'CashIn' AND t.amount = 250;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 482.2: % CashIn rows for the walk-in payment', v_n; END IF;
    SELECT a.currentbalance INTO v_cash1 FROM genericcashaccounts a WHERE a.genericcashaccountid = v_acct;
    IF v_cash1 - v_cash0 <> 250 THEN RAISE EXCEPTION 'FAIL 482.2: cash moved by %', v_cash1 - v_cash0; END IF;
    IF (SELECT count(*) FROM genericcustomerledger WHERE farmid = v_farm) <> v_led THEN
        RAISE EXCEPTION 'FAIL 482.2: a walk-in sale wrote a customer ledger line';
    END IF;
    RAISE NOTICE 'ok 482.2 cash +250 against the payment; no customer ledger line';

    -- 3. the payments list shows it (not hidden by an inner join), as customer 0 "Walk-in customer"
    SELECT count(*) INTO v_n FROM spgenericcustomerpayment_getall(v_farm, NULL) g
    WHERE g.genericcustomerpaymentid = v_pay AND g.genericcustomerid = 0 AND g.customername = 'Walk-in customer';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 482.3: walk-in payment not listed as Walk-in customer'; END IF;
    SELECT count(*) INTO v_n FROM spgenericcustomerpayment_getbyid(v_pay, v_farm);
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 482.3: getbyid does not return the walk-in payment'; END IF;
    RAISE NOTICE 'ok 482.3 the walk-in payment is listed and readable as "Walk-in customer"';

    -- 4. reversing it moves the cash back and touches no customer
    PERFORM spgenericcustomerpayment_reverse(v_farm, v_pay, '482 check', '482-check');
    IF (SELECT status FROM genericcustomerpayments WHERE genericcustomerpaymentid = v_pay) <> 'Reversed' THEN
        RAISE EXCEPTION 'FAIL 482.4: payment not reversed';
    END IF;
    SELECT a.currentbalance INTO v_cash1 FROM genericcashaccounts a WHERE a.genericcashaccountid = v_acct;
    IF v_cash1 <> v_cash0 THEN RAISE EXCEPTION 'FAIL 482.4: cash after reversal % (expected %)', v_cash1, v_cash0; END IF;
    IF (SELECT count(*) FROM genericcustomerledger WHERE farmid = v_farm) <> v_led THEN
        RAISE EXCEPTION 'FAIL 482.4: reversing a walk-in payment wrote a customer ledger line';
    END IF;
    RAISE NOTICE 'ok 482.4 reversing the walk-in payment returns the cash and touches no customer';

    -- 5. nothing anywhere uses customer 0
    IF EXISTS (SELECT 1 FROM genericcustomerpayments WHERE genericcustomerid = 0) THEN
        RAISE EXCEPTION 'FAIL 482.5: a payment with customer 0 exists';
    END IF;
    RAISE NOTICE 'ok 482.5 no payment carries customer 0';

    RAISE NOTICE 'generic 482: all checks passed';
END $$;
ROLLBACK;

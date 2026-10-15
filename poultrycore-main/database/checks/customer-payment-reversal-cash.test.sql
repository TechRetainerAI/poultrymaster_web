-- =============================================================================
-- customer-payment-reversal-cash.test.sql -- checks for migration 377.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f).
-- A reversed customer payment keeps its Money In and has a separate Money Out
-- for the reversal -- in the cash book and in Cash Flow -- netting to zero.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm  text;
    v_acct  integer;
    v_cust  integer;
    v_sale  integer;
    v_user  text;
    v_grp   uuid;
    v_bal0  numeric;
    v_bal   numeric;
    v_n     integer;
    v_x     numeric;
    v_today date;
BEGIN
    -- 1. Every reversed payment that had cash (an account, not an opening
    --    credit or credit note) has both cash book rows.
    SELECT count(*) INTO v_n
    FROM  (SELECT p.farmid, p.paymentgroupid, SUM(p.amount) AS amt
           FROM   poultrypayments p
           WHERE  p.status = 'Reversed' AND p.paymentgroupid IS NOT NULL
             AND  COALESCE(p.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote')
           GROUP  BY p.farmid, p.paymentgroupid) g
    WHERE  g.amt > 0
      AND  fnpoultrypaymentgroupaccount_any(g.farmid, g.paymentgroupid) IS NOT NULL
      AND  (NOT EXISTS (SELECT 1 FROM poultrycashtransactions ct WHERE ct.farmid = g.farmid
                        AND ct.paymentgroupid = g.paymentgroupid AND ct.sourcetype = 'CustomerPayment' AND ct.amount > 0)
         OR NOT EXISTS (SELECT 1 FROM poultrycashtransactions ct WHERE ct.farmid = g.farmid
                        AND ct.paymentgroupid = g.paymentgroupid AND ct.sourcetype = 'CustomerPaymentReversal' AND ct.amount < 0));
    IF v_n > 0 THEN RAISE EXCEPTION 'FAIL 1: % reversed customer payment(s) without both cash book rows', v_n; END IF;
    RAISE NOTICE 'ok 1 every reversed customer payment has its CashIn and its reversal CashOut';

    -- An open sale with a customer, on a company with an active cash account.
    SELECT s.farmid, s.saleid, s.customerid, a.poultrycashaccountid INTO v_farm, v_sale, v_cust, v_acct
    FROM   sale s
    JOIN   poultrycashaccounts a ON a.farmid = s.farmid AND a.isactive
    WHERE  s.status = 'Posted' AND s.customerid IS NOT NULL
      AND  fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid) >= 10
      AND  (a.allownegativebalance OR a.currentbalance >= 100)
    ORDER  BY s.saleid DESC
    LIMIT  1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'customer payment reversal cash: all checks passed (no open sale to test with)';
        RETURN;
    END IF;
    SELECT fa.owneruserid INTO v_user FROM farms fa WHERE fa.id::text = v_farm OR fa.farmid::text = v_farm LIMIT 1;
    v_user  := COALESCE(v_user, 'check377');
    v_today := fncompany_businessdate(v_farm);

    -- 2. A payment on the sale, reversed: the receipt stays, the reversal is added.
    SELECT currentbalance INTO v_bal0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_grp := sppoultrycustomerpayment_record(v_farm, v_cust, 10,
                 jsonb_build_array(jsonb_build_object('saleid', v_sale, 'amount', 10)),
                 'Cash', v_today::timestamp, v_acct, 'CHK-377', NULL, 'CustomerBalances', v_user);
    PERFORM sppoultrycustomerpayment_reverse(v_farm, v_grp, 'Duplicate entry', v_user);

    IF (SELECT count(*) FROM poultrycashtransactions WHERE farmid = v_farm AND paymentgroupid = v_grp
        AND sourcetype = 'CustomerPayment' AND amount = 10) <> 1 THEN
        RAISE EXCEPTION 'FAIL 2a: the receipt''s CashIn is gone'; END IF;
    IF (SELECT count(*) FROM poultrycashtransactions WHERE farmid = v_farm AND paymentgroupid = v_grp
        AND sourcetype = 'CustomerPaymentReversal' AND amount = -10 AND transactiontype = 'CashOut') <> 1 THEN
        RAISE EXCEPTION 'FAIL 2b: no reversal CashOut'; END IF;
    SELECT currentbalance INTO v_bal FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    IF v_bal <> v_bal0 THEN RAISE EXCEPTION 'FAIL 2c: account off by %', v_bal - v_bal0; END IF;
    RAISE NOTICE 'ok 2 cash book: receipt kept, reversal added, balance back where it was';

    -- 3. Cash Flow: both legs, net zero.
    SELECT count(*), COALESCE(sum(r.amount), 0) INTO v_n, v_x
    FROM   sppoultrycashflow_rows(v_farm, v_today::timestamp, (v_today + 1)::timestamp) r
    WHERE  r.rowsource IN ('Receipt', 'ReceiptReversal')
      AND  r.sourcerowid = (SELECT min(p.poultrypaymentid) FROM poultrypayments p WHERE p.paymentgroupid = v_grp);
    IF v_n <> 2 OR v_x <> 0 THEN RAISE EXCEPTION 'FAIL 3: cash flow legs % netting %', v_n, v_x; END IF;
    RAISE NOTICE 'ok 3 cash flow: Money In on the payment day, Money Out for the reversal, net zero';

    -- 4. An advance (nothing applied), reversed from Customer Credits: same two legs.
    v_grp := sppoultrycustomerpayment_record(v_farm, v_cust, 7, '[]'::jsonb,
                 'Cash', v_today::timestamp, v_acct, NULL, 'check377', 'PaymentsPage', v_user);
    PERFORM sppoultrycustomercredit_reverse(v_farm, v_grp, 'Posted by mistake', v_user);   -- an advance is reversed from Customer Credits
    SELECT count(*), COALESCE(sum(amount), 0) INTO v_n, v_x FROM poultrycashtransactions
    WHERE  farmid = v_farm AND paymentgroupid = v_grp AND sourcetype IN ('CustomerPayment', 'CustomerPaymentReversal');
    IF v_n <> 2 OR v_x <> 0 THEN RAISE EXCEPTION 'FAIL 4: advance cash rows % netting %', v_n, v_x; END IF;
    SELECT currentbalance INTO v_bal FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    IF v_bal <> v_bal0 THEN RAISE EXCEPTION 'FAIL 4b: account off by %', v_bal - v_bal0; END IF;
    RAISE NOTICE 'ok 4 a reversed advance keeps its receipt and adds the reversal';

    -- 5. A resync changes nothing.
    PERFORM sppoultrycustomerpaymentcash_sync(v_farm, v_grp, v_user);
    SELECT count(*) INTO v_n FROM poultrycashtransactions
    WHERE  farmid = v_farm AND paymentgroupid = v_grp AND sourcetype IN ('CustomerPayment', 'CustomerPaymentReversal');
    SELECT currentbalance INTO v_bal FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    IF v_n <> 2 OR v_bal <> v_bal0 THEN RAISE EXCEPTION 'FAIL 5: resync left % rows, balance off by %', v_n, v_bal - v_bal0; END IF;
    RAISE NOTICE 'ok 5 resync is idempotent';

    RAISE NOTICE 'customer payment reversal cash: all checks passed';
END $$;

ROLLBACK;

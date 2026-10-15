-- =============================================================================
-- supplier-payment-reversal-cash.test.sql -- checks for migration 376.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f).
-- A reversed supplier payment keeps its Money Out and gains a separate
-- Money In -- in the cash book and in Cash Flow -- and balances net to zero.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm  text;
    v_acct  integer;
    v_sup   integer;
    v_doc   record;
    v_pay   integer;
    v_bal0  numeric;
    v_bal   numeric;
    v_n     integer;
    v_x     numeric;
    v_today date;
BEGIN
    -- 1. Every payment reversed before 376 got its rows back (backfill).
    SELECT count(*) INTO v_n
    FROM   poultrysupplierpayments sp
    WHERE  sp.status = 'Reversed' AND NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)
      AND  COALESCE(sp.totalamount, 0) > 0 AND sp.poultrycashaccountid IS NOT NULL
      AND  EXISTS (SELECT 1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = sp.poultrycashaccountid AND a.farmid = sp.farmid)
      AND  ((SELECT count(*) FROM poultrycashtransactions ct
             WHERE ct.farmid = sp.farmid AND ct.sourceid = sp.poultrysupplierpaymentid
               AND ct.sourcetype = 'PoultrySupplierPayment' AND ct.amount = -sp.totalamount) <> 1
         OR (SELECT count(*) FROM poultrycashtransactions ct
             WHERE ct.farmid = sp.farmid AND ct.sourceid = sp.poultrysupplierpaymentid
               AND ct.sourcetype = 'PoultrySupplierPaymentReversal' AND ct.amount = sp.totalamount) <> 1);
    IF v_n > 0 THEN RAISE EXCEPTION 'FAIL 1: % reversed payment(s) without both cash book rows', v_n; END IF;
    RAISE NOTICE 'ok 1 every reversed supplier payment has its CashOut and its reversal CashIn';

    -- An open payable on a company with a cash account that can take the payment.
    SELECT d.documenttype, d.documentid, d.supplierid, d.balance, a.poultrycashaccountid AS acct, a.farmid
    INTO   v_doc
    FROM   poultrycashaccounts a
    CROSS  JOIN LATERAL fnpoultrypayables(a.farmid) d
    WHERE  a.isactive AND (a.allownegativebalance OR a.currentbalance >= 50)
      AND  d.balance >= 10 AND d.supplierid IS NOT NULL
    ORDER  BY a.farmid, d.documentid
    LIMIT  1;
    IF v_doc IS NULL THEN
        RAISE NOTICE 'supplier payment reversal cash: all checks passed (no open payable to test with)';
        RETURN;
    END IF;
    v_farm := v_doc.farmid; v_acct := v_doc.acct; v_sup := v_doc.supplierid;
    v_today := fncompany_businessdate(v_farm);

    -- 2. A payment against that payable, then reversed.
    SELECT currentbalance INTO v_bal0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_pay := sppoultrysupplierpayment_record(v_farm, v_sup, 10,
        jsonb_build_array(jsonb_build_object('documenttype', v_doc.documenttype, 'documentid', v_doc.documentid, 'amount', 10)),
        'Cash', v_today::timestamp, v_acct, 'CHK-376', 'check376', 'SupplierBalances', 'check376');
    SELECT currentbalance INTO v_bal FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    IF v_bal <> v_bal0 - 10 THEN RAISE EXCEPTION 'FAIL 2a: payment moved the account by %', v_bal - v_bal0; END IF;

    PERFORM sppoultrysupplierpayment_reverse(v_farm, v_pay, 'Duplicate entry', 'check376');

    SELECT count(*) INTO v_n FROM poultrycashtransactions
    WHERE  farmid = v_farm AND sourceid = v_pay AND sourcetype = 'PoultrySupplierPayment' AND amount = -10;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 2b: the payment''s CashOut is gone (% rows)', v_n; END IF;
    SELECT count(*) INTO v_n FROM poultrycashtransactions
    WHERE  farmid = v_farm AND sourceid = v_pay AND sourcetype = 'PoultrySupplierPaymentReversal'
      AND  amount = 10 AND transactiontype = 'CashIn';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 2c: no reversal CashIn (% rows)', v_n; END IF;
    SELECT currentbalance INTO v_bal FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    IF v_bal <> v_bal0 THEN RAISE EXCEPTION 'FAIL 2d: account off by % after the reversal', v_bal - v_bal0; END IF;
    RAISE NOTICE 'ok 2 cash book: payment kept, reversal added, balance back where it was';

    -- 3. Cash Flow shows both legs, and they net to zero.
    SELECT count(*), COALESCE(sum(r.amount), 0) INTO v_n, v_x
    FROM   sppoultrycashflow_rows(v_farm, v_today::timestamp, (v_today + 1)::timestamp) r
    WHERE  r.sourceid = v_pay AND r.rowsource IN ('SupplierPayment', 'SupplierPaymentReversal');
    IF v_n <> 2 OR v_x <> 0 THEN RAISE EXCEPTION 'FAIL 3a: cash flow legs % netting %', v_n, v_x; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycashflow_rows(v_farm, v_today::timestamp, (v_today + 1)::timestamp) r
                   WHERE r.sourceid = v_pay AND r.rowsource = 'SupplierPayment' AND r.amount = -10 AND r.transactiontype = 'CashOut')
       OR NOT EXISTS (SELECT 1 FROM sppoultrycashflow_rows(v_farm, v_today::timestamp, (v_today + 1)::timestamp) r
                   WHERE r.sourceid = v_pay AND r.rowsource = 'SupplierPaymentReversal' AND r.amount = 10 AND r.transactiontype = 'CashIn') THEN
        RAISE EXCEPTION 'FAIL 3b: a leg is missing or has the wrong sign'; END IF;
    -- The payment is not ALSO still counted by the Posted-only arms.
    SELECT count(*) INTO v_n FROM sppoultrycashflow_rows(v_farm, v_today::timestamp, (v_today + 1)::timestamp) r
    WHERE  r.rowsource IN ('SupplierAdvance') AND r.sourceid = v_pay;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 3c: reversed payment still counted as an advance'; END IF;
    RAISE NOTICE 'ok 3 cash flow: Money Out on the payment day, Money In for the reversal, net zero';

    -- 4. A resync changes nothing (two rows, same balance).
    PERFORM sppoultrysupplierpaymentcash_sync(v_farm, v_pay, 'check376');
    SELECT count(*) INTO v_n FROM poultrycashtransactions
    WHERE  farmid = v_farm AND sourceid = v_pay AND sourcetype IN ('PoultrySupplierPayment', 'PoultrySupplierPaymentReversal');
    SELECT currentbalance INTO v_bal FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    IF v_n <> 2 OR v_bal <> v_bal0 THEN RAISE EXCEPTION 'FAIL 4: resync left % rows, balance off by %', v_n, v_bal - v_bal0; END IF;
    RAISE NOTICE 'ok 4 resync is idempotent';

    -- 5. An advance (nothing applied) reversed: same two legs.
    v_pay := sppoultrysupplierpayment_record(v_farm, v_sup, 7, '[]'::jsonb,
        'Cash', v_today::timestamp, v_acct, 'CHK-376b', 'check376', 'SupplierBalances', 'check376');
    PERFORM sppoultrysupplierpayment_reverse(v_farm, v_pay, 'Posted by mistake', 'check376');
    SELECT count(*), COALESCE(sum(r.amount), 0) INTO v_n, v_x
    FROM   sppoultrycashflow_rows(v_farm, v_today::timestamp, (v_today + 1)::timestamp) r
    WHERE  r.sourceid = v_pay AND r.rowsource IN ('SupplierPayment', 'SupplierPaymentReversal', 'SupplierAdvance');
    IF v_n <> 2 OR v_x <> 0 THEN RAISE EXCEPTION 'FAIL 5: advance legs % netting %', v_n, v_x; END IF;
    SELECT currentbalance INTO v_bal FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    IF v_bal <> v_bal0 THEN RAISE EXCEPTION 'FAIL 5b: balance off by %', v_bal - v_bal0; END IF;
    RAISE NOTICE 'ok 5 a reversed advance shows both legs too';

    RAISE NOTICE 'supplier payment reversal cash: all checks passed';
END $$;

ROLLBACK;

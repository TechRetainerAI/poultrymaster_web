-- =============================================================================
-- Checks for 421 (Water credits programme W0).  SELF-ROLLING-BACK: every
-- fixture lives inside this file's own BEGIN ... ROLLBACK, in a real Water
-- company (so uuid / FK rules hold), dated 2030 so no real data mixes in.
-- Prints 'water W0: all checks passed' on success.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $t$
DECLARE
    v_farm  text;
    v_cust  integer;
    v_acct  integer;
    v_supp  integer;
    v_item  integer;
    v_sale  integer;
    v_saleb integer;
    v_p1    integer;
    v_p2    integer;
    v_pay   integer;
    v_grp   uuid;
    v_n     numeric;
    v_bal0  numeric;
    v_lt    record;
    d1 date := DATE '2030-01-10';
    d2 date := DATE '2030-01-11';
    d3 date := DATE '2030-01-12';
BEGIN
    SELECT a.farmid INTO v_farm FROM watercashaccounts a ORDER BY a.watercashaccountid LIMIT 1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'no water company to test in'; END IF;

    INSERT INTO watercustomers (farmid, name) VALUES (v_farm, '__w0_customer') RETURNING watercustomerid INTO v_cust;

    -- ---------------------------------------------------------- 1. Sales page
    INSERT INTO watersales (farmid, watercustomerid, saledate, totalamount, amountpaid, status)
    VALUES (v_farm, v_cust, d1::timestamp + interval '9 hours', 100, 0, 'Pending') RETURNING watersaleid INTO v_sale;

    v_pay := spwaterpayment_record(v_farm, v_sale, 60, 'Cash', d2::timestamp + interval '10 hours', NULL, NULL, '__w0');
    IF (SELECT watercustomerid FROM waterpayments WHERE waterpaymentid = v_pay) IS DISTINCT FROM v_cust THEN
        RAISE EXCEPTION 'FAIL 1a: payment does not name its customer';
    END IF;
    IF (SELECT sourcetype FROM waterpayments WHERE waterpaymentid = v_pay) IS DISTINCT FROM 'SaleEntry' THEN
        RAISE EXCEPTION 'FAIL 1b: payment source is not SaleEntry';
    END IF;
    SELECT paymentgroupid INTO v_grp FROM waterpayments WHERE waterpaymentid = v_pay;
    PERFORM spwatercustomerpayment_reverse(v_farm, v_grp, 'test', '__w0');
    PERFORM spwaterpayment_record(v_farm, v_sale, 30, 'Cash', d2::timestamp + interval '11 hours', NULL, NULL, '__w0');
    SELECT amountpaid INTO v_n FROM watersales WHERE watersaleid = v_sale;
    IF v_n <> 30 THEN RAISE EXCEPTION 'FAIL 1c: amountpaid % after a reversal + new payment of 30', v_n; END IF;
    RAISE NOTICE 'ok 1 Sales-page payment counts Posted payments only and names its customer';

    -- ---------------------------------------------------------- 2. Daily closing
    -- sale A (d1, 100) got 30 on d2 above.  Owed at the end of d1 = 100.
    SELECT * INTO v_lt FROM fnwaterdailyclosing_livetotals(v_farm, d1);
    IF v_lt.creditsales <> 100 + COALESCE((SELECT SUM(public.fnwatersale_owedasof(v_farm, s.watersaleid, d1))
                                           FROM watersales s WHERE s.farmid = v_farm AND s.watersaleid <> v_sale
                                             AND s.status <> 'Cancelled' AND COALESCE(s.sourcetype,'') <> 'DeliveryRun'
                                             AND s.saledate >= d1 AND s.saledate < d1 + 1), 0) THEN
        RAISE EXCEPTION 'FAIL 2a: credit sales on d1 = % (a later payment rewrote the day)', v_lt.creditsales;
    END IF;
    IF public.fnwatersale_owedasof(v_farm, v_sale, d1) <> 100 OR public.fnwatersale_owedasof(v_farm, v_sale, d2) <> 70 THEN
        RAISE EXCEPTION 'FAIL 2b: owed-as-of wrong';
    END IF;
    -- sale B made AND paid on d2: its payment must not also be a collection.
    INSERT INTO watersales (farmid, watercustomerid, saledate, totalamount, amountpaid, status)
    VALUES (v_farm, v_cust, d2::timestamp + interval '8 hours', 50, 0, 'Pending') RETURNING watersaleid INTO v_saleb;
    PERFORM spwaterpayment_record(v_farm, v_saleb, 50, 'Cash', d2::timestamp + interval '12 hours', NULL, NULL, '__w0');
    SELECT COALESCE(SUM(p.amount), 0) INTO v_n FROM waterpayments p
    WHERE p.farmid = v_farm AND p.createdby <> '__w0' AND COALESCE(p.status,'Posted') = 'Posted'
      AND COALESCE(p.sourcetype,'') <> 'DeliveryRun' AND p.paymentdate >= d2 AND p.paymentdate < d2 + 1;
    SELECT * INTO v_lt FROM fnwaterdailyclosing_livetotals(v_farm, d2);
    -- collections on d2 = the 30 on sale A only (60 was reversed; 50 is sale B's same-day payment)
    IF v_lt.customercollections <> 30 + v_n THEN
        RAISE EXCEPTION 'FAIL 2c: collections on d2 = %, expected %', v_lt.customercollections, 30 + v_n;
    END IF;
    RAISE NOTICE 'ok 2 closing: credit owed at end of day; reversed and same-day payments not collections';

    -- ---------------------------------------------------------- 3 + 4. supplier payment
    INSERT INTO watercashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, isactive)
    VALUES (v_farm, '__w0_account', 'Cash', 10000, 10000, TRUE) RETURNING watercashaccountid INTO v_acct;
    v_supp := spwatersupplier_insert(v_farm, '__w0_supplier', NULL, NULL, NULL, NULL, NULL, NULL, '__w0');
    v_item := spwaterrawmaterialitem_insert(v_farm, '__w0_item', 'PackagingRoll', 'kg', 0, 0, TRUE, NULL, 'kg', 'FIFO');
    v_p1 := spwaterrawmaterialpurchase_insert(v_farm, v_item, '__w0_supplier', d3::timestamp, 10, 30, 'Credit', 0,
                                              NULL, NULL, NULL, '__w0', v_supp, 300, NULL, 'kg', 1);
    v_p2 := spwaterrawmaterialpurchase_insert(v_farm, v_item, '__w0_supplier', d3::timestamp, 10, 20, 'Credit', 0,
                                              NULL, NULL, NULL, '__w0', v_supp, 200, NULL, 'kg', 1);
    -- P1 is deferred stock: its cost reaches the P&L when consumed, not when paid.
    UPDATE waterrawmaterialpurchases SET costrecognitionmethod = 'EXPENSE_WHEN_CONSUMED'
    WHERE waterrawmaterialpurchaseid = v_p1;

    v_pay := spwatersupplierpayment_record(v_farm, v_supp, 500,
                 jsonb_build_array(jsonb_build_object('documenttype','RawMaterialPurchase','documentid',v_p1,'amount',300),
                                   jsonb_build_object('documenttype','RawMaterialPurchase','documentid',v_p2,'amount',200)),
                 'Cash', d3::timestamp + interval '10 hours', v_acct, NULL, NULL, 'SupplierBalances', '__w0');
    SELECT currentbalance INTO v_n FROM watercashaccounts WHERE watercashaccountid = v_acct;
    IF v_n <> 9500 THEN RAISE EXCEPTION 'FAIL 3a: balance after paying 500 = %', v_n; END IF;

    SELECT COALESCE(SUM(-r.amount), 0) INTO v_n
    FROM spwatercashflow_rows(v_farm, d3::timestamp, d3::timestamp + interval '1 day') r
    WHERE r.rowsource IN ('Expense', 'SupplierPurchasePayment') AND r.sourceid IN (v_pay)
       OR (r.rowsource = 'Expense' AND r.sourceid IN (SELECT waterexpenseid FROM waterexpenses
                                                      WHERE sourcetype = 'WaterSupplierPayment' AND sourceid = v_pay));
    IF v_n <> 500 THEN RAISE EXCEPTION 'FAIL 4a: Cash Flow shows % out for a 500 payment (deferred part missing?)', v_n; END IF;

    PERFORM spwatersupplierpayment_reverse(v_farm, v_pay, 'test', '__w0');
    SELECT currentbalance INTO v_n FROM watercashaccounts WHERE watercashaccountid = v_acct;
    IF v_n <> 10000 THEN RAISE EXCEPTION 'FAIL 3b: balance after reversing = % (deferred part not given back)', v_n; END IF;
    RAISE NOTICE 'ok 3 reversal gives back all the cash that left';

    SELECT COALESCE(SUM(r.amount) FILTER (WHERE r.rowsource = 'SupplierPurchasePayment'), 0),
           COALESCE(SUM(r.amount) FILTER (WHERE r.rowsource = 'SupplierPaymentReversal'), 0)
    INTO   v_n, v_bal0
    -- whole history: the reversal is stamped with the real clock (2026), the
    -- fixture payment is dated 2030.
    FROM spwatercashflow_rows(v_farm, NULL, NULL) r
    WHERE r.sourceid = v_pay;
    IF v_n <> -500 OR v_bal0 <> 500 THEN
        RAISE EXCEPTION 'FAIL 4b: reversed payment in Cash Flow: out %, back in %', v_n, v_bal0;
    END IF;
    IF EXISTS (SELECT 1 FROM spwatercashflow_rows(v_farm, NULL, NULL) r
               WHERE r.rowsource = 'Expense' AND r.sourceid IN (SELECT waterexpenseid FROM waterexpenses
                                                                WHERE sourcetype = 'WaterSupplierPayment' AND sourceid = v_pay)) THEN
        RAISE EXCEPTION 'FAIL 4c: the aggregated payment expense is still read as cash';
    END IF;
    IF (SELECT category FROM spwatercashflow_detail(v_farm, NULL, NULL) d
        WHERE d.rowsource = 'SupplierPurchasePayment' AND d.sourceid = v_pay LIMIT 1) <> 'Raw Materials / Inventory Purchase' THEN
        RAISE EXCEPTION 'FAIL 4d: category';
    END IF;
    RAISE NOTICE 'ok 4 Cash Flow: full purchase out on its date, reversal back in on its date';

    RAISE NOTICE 'water W0: all checks passed';
END
$t$;

ROLLBACK;

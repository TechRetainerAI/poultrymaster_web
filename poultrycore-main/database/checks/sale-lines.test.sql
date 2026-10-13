-- Behavioural checks for migration 358: ONE sale header, many sale lines.
--
-- SELF-CONTAINED: opens its own transaction and ROLLS IT BACK.
--
--   psql ... -X -f sale-lines.test.sql
--
-- Companies are fresh uuids per run (no farms row = legacy poultry, UTC).
--
--   T1  one-line sale: 1 sale, 1 line, 1 movement, 1 payment, 1 allocation, 1 receipt
--   T2  two-line paid sale: 1 sale, 2 lines, 2 movements, ONE payment / allocation / receipt / Cash Flow row
--   T3  two-line unpaid sale: one open sale of 834, no cash
--   T4  existing balance + new two-line sale = 2 open sales, 834.33
--   T5  partial payment against the header
--   T6  bulk payment across 2 real sales: 1 payment, 2 allocations, 1 receipt
--   T7  reversal restores each line's class, one reversal
--   T8  split tender: 2 payments, 2 receipts, same sale, paid in full
--   T9  reports: egg sales report has one row per line; sale count counts headers
--   T10 double submit with a request key posts once
--   T11 guards: posted lines locked, mixed products / foreign class refused

BEGIN;

CREATE FUNCTION pg_temp.sl_chk(p_label text, p_expect text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_expect IS NOT DISTINCT FROM p_got THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect % got %', p_label, COALESCE(p_expect, 'NULL'), COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

CREATE FUNCTION pg_temp.sl_like(p_label text, p_pattern text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_got ILIKE p_pattern THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect like "%" got %', p_label, p_pattern, COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

CREATE FUNCTION pg_temp.sl_onhand(p_farm text, p_product integer)
RETURNS numeric LANGUAGE sql AS $c$
    SELECT COALESCE(SUM(t.quantity), 0) FROM poultrystocktransactions t
    WHERE t.farmid = p_farm AND t.poultryproductid = p_product;
$c$;

-- Ends the "creating transaction" for the sales made so far, as a new request would.
CREATE FUNCTION pg_temp.sl_later() RETURNS void LANGUAGE sql AS $c$
    SELECT set_config('poultry.sale_fresh', '', true);
$c$;

-- A sale through the Add Sale group path, as SaleService.CreateGroup calls it.
CREATE FUNCTION pg_temp.sl_sale(p_farm text, p_cust integer, p_acct integer, p_paid boolean, p_lines jsonb,
                                p_desc text, p_key text DEFAULT NULL)
RETURNS integer LANGUAGE sql AS $c$
    SELECT (sppoultrysale_creategroup(p_farm, 'tester', (fncompany_businessdate(p_farm) - 1)::timestamp,
                                      (SELECT name FROM customer WHERE customerid = p_cust), p_cust,
                                      'Cash', p_acct, p_paid, p_desc, NULL, p_lines::text, p_key)->>'saleId')::int;
$c$;

CREATE FUNCTION pg_temp.sl_line(p_class integer, p_qty numeric, p_total numeric)
RETURNS jsonb LANGUAGE sql AS $c$
    SELECT jsonb_build_object('product', 'Fresh Eggs', 'eggProductId', p_class, 'quantity', p_qty,
                              'unitPrice', round(p_total / (p_qty / 30), 2), 'totalAmount', p_total);
$c$;

DO $t$
DECLARE
    v_farm  text := gen_random_uuid()::text;
    v_other text := gen_random_uuid()::text;
    v_acct  integer;
    v_cust  integer;
    v_cust2 integer;
    v_cust3 integer;
    v_uns   integer;
    v_large integer;
    v_med   integer;
    v_s     integer;
    v_s2    integer;
    v_a     integer;
    v_grp   uuid;
    v_l0    numeric;
    v_m0    numeric;
    v_res   jsonb;
    f       integer := 0;
BEGIN
    -- ---------------------------------------------------------------- setup
    PERFORM sppoultryeggsizes_ensure(v_farm, 'tester');
    v_uns := fnpoultry_unsortedeggproduct(v_farm);
    SELECT c.poultryproductid INTO v_large FROM sppoultryeggclasses_get(v_farm, TRUE) c WHERE c.name = 'Large';
    SELECT c.poultryproductid INTO v_med   FROM sppoultryeggclasses_get(v_farm, TRUE) c WHERE c.name = 'Medium';
    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, note, createdby)
    VALUES (v_farm, v_uns, 'Production', 9000, 'test', 'tester'),
           (v_farm, v_large, 'Sorting In', 9000, 'test', 'tester'),
           (v_farm, v_med, 'Sorting In', 9000, 'test', 'tester');
    v_acct := sppoultrycashaccount_insert(v_farm, 'Main Cash', 'Cash', 0, TRUE, NULL);
    INSERT INTO customer (userid, name, farmid) VALUES ('tester', 'First Customer', v_farm) RETURNING customerid INTO v_cust;
    INSERT INTO customer (userid, name, farmid) VALUES ('tester', 'comfort', v_farm) RETURNING customerid INTO v_cust2;
    INSERT INTO customer (userid, name, farmid) VALUES ('tester', 'Split', v_farm) RETURNING customerid INTO v_cust3;

    -- ================================================= T1  one-line sale
    v_s := pg_temp.sl_sale(v_farm, v_cust, v_acct, TRUE, jsonb_build_array(pg_temp.sl_line(v_large, 300, 500)), 'T1');
    PERFORM pg_temp.sl_later();
    f := f + pg_temp.sl_chk('T1 one sale, one line', '1|1',
            (SELECT count(*) FROM sale WHERE farmid = v_farm AND saledescription = 'T1')::text || '|' ||
            (SELECT count(*) FROM saleline WHERE saleid = v_s)::text);
    f := f + pg_temp.sl_chk('T1 one movement, on its line', '1|-300.000',
            (SELECT count(*) FROM poultrystocktransactions t JOIN saleline l ON l.salelineid = t.salelineid
             WHERE t.relatedid = v_s AND t.txntype = 'Sale')::text || '|' ||
            (SELECT sum(quantity) FROM poultrystocktransactions WHERE relatedid = v_s AND txntype = 'Sale' AND poultryproductid = v_large)::text);
    f := f + pg_temp.sl_chk('T1 one payment, one allocation, one receipt', '1|1|1',
            (SELECT count(*) FROM poultrypayments WHERE saleid = v_s)::text || '|' ||
            (SELECT count(*) FROM customerpaymentallocation WHERE module = 'poultry' AND saleid = v_s AND farmid = v_farm)::text || '|' ||
            (SELECT count(*) FROM poultrycashtransactions ct JOIN poultrypayments pp ON pp.paymentgroupid = ct.paymentgroupid
             WHERE pp.saleid = v_s AND ct.transactiontype = 'CashIn')::text);

    -- ============================================ T2  two-line paid sale
    v_l0 := pg_temp.sl_onhand(v_farm, v_large);
    v_m0 := pg_temp.sl_onhand(v_farm, v_med);
    v_s := pg_temp.sl_sale(v_farm, v_cust, v_acct, TRUE,
            jsonb_build_array(pg_temp.sl_line(v_large, 757, 1185.97), pg_temp.sl_line(v_med, 548, 730.67)), 'T2');
    PERFORM pg_temp.sl_later();
    f := f + pg_temp.sl_chk('T2 ONE sale header', '1|true|1916.64|SG-',
            (SELECT count(*) FROM sale WHERE farmid = v_farm AND saledescription = 'T2')::text || '|' ||
            (SELECT ismultiline::text || '|' || totalamount::text || '|' || left(salegroupno, 3) FROM sale WHERE saleid = v_s));
    f := f + pg_temp.sl_chk('T2 two lines that add up', '2|1916.64',
            (SELECT count(*)::text || '|' || sum(totalamount)::text FROM saleline WHERE saleid = v_s));
    f := f + pg_temp.sl_chk('T2 two movements: Large -757, Medium -548', '-757|-548',
            (pg_temp.sl_onhand(v_farm, v_large) - v_l0)::int::text || '|' || (pg_temp.sl_onhand(v_farm, v_med) - v_m0)::int::text);
    f := f + pg_temp.sl_chk('T2 each movement on its own line', '2',
            (SELECT count(DISTINCT salelineid) FROM poultrystocktransactions WHERE relatedid = v_s AND txntype = 'Sale')::text);
    SELECT paymentgroupid INTO v_grp FROM poultrypayments WHERE saleid = v_s;
    f := f + pg_temp.sl_chk('T2 one payment row, one allocation of 1916.64', '1|1|1916.64',
            (SELECT count(*) FROM poultrypayments WHERE paymentgroupid = v_grp)::text || '|' ||
            (SELECT count(*)::text || '|' || sum(amountapplied)::text FROM customerpaymentallocation WHERE module = 'poultry' AND saleid = v_s));
    f := f + pg_temp.sl_chk('T2 one cash receipt of 1916.64', '1|1916.64',
            (SELECT count(*)::text || '|' || sum(amount)::text FROM poultrycashtransactions WHERE paymentgroupid = v_grp));
    f := f + pg_temp.sl_chk('T2 Cash Flow: ONE Money In row of 1916.64', '1|1916.64',
            (SELECT count(*)::text || '|' || sum(amount)::text FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r
             WHERE r.rowsource = 'Receipt' AND r.sourceid = v_s));
    f := f + pg_temp.sl_like('T2 Cash Flow names the sale and customer', 'Sale SG-% · First Customer · PAY-%',
            (SELECT description FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r WHERE r.rowsource = 'Receipt' AND r.sourceid = v_s));
    f := f + pg_temp.sl_chk('T2 Payments: 1 sale, labelled with its lines', '1|Fresh Eggs · 2 lines',
            (SELECT count(*)::text || '|' || min(product) FROM sppoultrycustomerpayment_allocations(v_farm, v_grp)));
    f := f + pg_temp.sl_chk('T2 sale read returns the lines', '2|2',
            (SELECT linecount::text || '|' || jsonb_array_length(salelines::jsonb)::text FROM spsale_getbyid(v_s, v_farm)));

    -- ========================================== T3  two-line unpaid sale
    v_s := pg_temp.sl_sale(v_farm, v_cust2, v_acct, FALSE,
            jsonb_build_array(pg_temp.sl_line(v_large, 360, 564), pg_temp.sl_line(v_med, 180, 270)), 'T3');
    PERFORM pg_temp.sl_later();
    f := f + pg_temp.sl_chk('T3 one open sale of 834', '1|834.00',
            (SELECT count(*)::text || '|' || sum(balance)::text FROM sppoultrycustomeropensales(v_farm, v_cust2)));
    f := f + pg_temp.sl_chk('T3 no cash, no payment', '0|0',
            (SELECT count(*) FROM poultrycashtransactions WHERE farmid = v_farm AND sourcetype = 'Sale' AND sourceid = v_s)::text || '|' ||
            (SELECT count(*) FROM poultrypayments WHERE saleid = v_s)::text);
    f := f + pg_temp.sl_chk('T3 two deductions', '2',
            (SELECT count(*) FROM poultrystocktransactions WHERE relatedid = v_s AND txntype = 'Sale')::text);

    -- ===================================== T4  earlier balance + this sale
    v_s2 := pg_temp.sl_sale(v_farm, v_cust2, v_acct, FALSE, jsonb_build_array(pg_temp.sl_line(v_large, 50, 83.33)), 'T4 old');
    PERFORM pg_temp.sl_later();
    PERFORM sppoultrypayment_record(v_farm, v_s2, 83, 'Cash', fncompany_businessdate(v_farm)::timestamp, NULL, 'part', 'tester');
    f := f + pg_temp.sl_chk('T4 two open sales, 834.33 owed', '2|834.33',
            (SELECT count(*)::text || '|' || sum(balance)::text FROM sppoultrycustomeropensales(v_farm, v_cust2)));

    -- =============================================== T6  bulk payment
    v_grp := sppoultrycustomerpayment_record(v_farm, v_cust2, 834.33,
               jsonb_build_array(jsonb_build_object('saleid', v_s2, 'amount', 0.33), jsonb_build_object('saleid', v_s, 'amount', 834)),
               'Cash', fncompany_businessdate(v_farm)::timestamp, v_acct, NULL, NULL, 'CustomerBalances', 'tester');
    f := f + pg_temp.sl_chk('T6 one payment, two allocations (not three), one receipt', '2|1|834.33',
            (SELECT count(*) FROM customerpaymentallocation ca JOIN poultrypayments pp ON pp.poultrypaymentid = ca.paymentid
             WHERE pp.paymentgroupid = v_grp AND ca.module = 'poultry')::text || '|' ||
            (SELECT count(*)::text || '|' || sum(amount)::text FROM poultrycashtransactions WHERE paymentgroupid = v_grp));
    f := f + pg_temp.sl_chk('T6 Cash Flow: one row for the bulk payment', '1|834.33|2 sales',
            (SELECT count(*)::text || '|' || sum(amount)::text || '|' || split_part(min(description), ' · ', 1)
             FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r
             WHERE r.rowsource = 'Receipt' AND r.sourcerowid IN (SELECT poultrypaymentid FROM poultrypayments WHERE paymentgroupid = v_grp)));
    f := f + pg_temp.sl_chk('T6 nothing owed', '0', (SELECT count(*) FROM sppoultrycustomeropensales(v_farm, v_cust2))::text);

    -- ============================================= T5  partial payment
    v_s := pg_temp.sl_sale(v_farm, v_cust2, v_acct, FALSE,
            jsonb_build_array(pg_temp.sl_line(v_large, 360, 564), pg_temp.sl_line(v_med, 180, 270)), 'T5');
    PERFORM pg_temp.sl_later();
    PERFORM sppoultrypayment_record(v_farm, v_s, 500, 'Cash', fncompany_businessdate(v_farm)::timestamp, NULL, 'part', 'tester');
    f := f + pg_temp.sl_chk('T5 paid 500, owes 334, one allocation', '500.00|334.00|1|Partially Paid',
            (SELECT amountpaid::text || '|' || balance::text FROM sppoultrycustomeropensales(v_farm, v_cust2) WHERE saleid = v_s) || '|' ||
            (SELECT count(*) FROM customerpaymentallocation WHERE module = 'poultry' AND saleid = v_s AND status = 'Posted')::text || '|' ||
            (SELECT status FROM sppoultrycustomeropensales(v_farm, v_cust2) WHERE saleid = v_s));

    -- ============================================= T7  reversal per line
    v_s := pg_temp.sl_sale(v_farm, v_cust, v_acct, TRUE,
            jsonb_build_array(pg_temp.sl_line(v_large, 757, 1185.97), pg_temp.sl_line(v_med, 548, 730.67)), 'T7');
    PERFORM pg_temp.sl_later();
    v_l0 := pg_temp.sl_onhand(v_farm, v_large);
    v_m0 := pg_temp.sl_onhand(v_farm, v_med);
    v_res := sppoultrysale_reversalpreview(v_farm, v_s);
    f := f + pg_temp.sl_chk('T7 preview: one sale, two lines', '1|2',
            jsonb_array_length(v_res->'saleIds')::text || '|' || jsonb_array_length(v_res->'lines')::text);
    PERFORM sppoultrysale_reverse(v_farm, v_s, 'Wrong quantity', NULL,
            jsonb_build_object((v_res->'payments'->0->>'key'), 'ReversePayment'), NULL, NULL, 'tester');
    f := f + pg_temp.sl_chk('T7 Large +757, Medium +548', '757|548',
            (pg_temp.sl_onhand(v_farm, v_large) - v_l0)::int::text || '|' || (pg_temp.sl_onhand(v_farm, v_med) - v_m0)::int::text);
    f := f + pg_temp.sl_chk('T7 each restore on its line', '2',
            (SELECT count(DISTINCT salelineid) FROM poultrystocktransactions WHERE relatedid = v_s AND txntype = 'Sale Reversal')::text);
    f := f + pg_temp.sl_chk('T7 one sale reversed, one reversal record', 'Reversed|1',
            (SELECT status FROM sale WHERE saleid = v_s) || '|' ||
            (SELECT count(*) FROM poultrysalereversals WHERE farmid = v_farm AND v_s = ANY (saleids))::text);
    f := f + pg_temp.sl_chk('T7 allocation released, money back out', '0|-1916.64',
            (SELECT count(*) FROM customerpaymentallocation WHERE module = 'poultry' AND saleid = v_s AND status = 'Posted')::text || '|' ||
            (SELECT sum(amount)::text FROM poultrycashtransactions ct WHERE ct.farmid = v_farm AND ct.transactiontype = 'CashOut'
             AND ct.paymentgroupid IN (SELECT paymentgroupid FROM poultrypayments WHERE saleid = v_s)));

    -- ============================================== T8  split tender
    v_s := pg_temp.sl_sale(v_farm, v_cust3, v_acct, FALSE,
            jsonb_build_array(pg_temp.sl_line(v_large, 757, 1185.97), pg_temp.sl_line(v_med, 548, 730.67)), 'T8');
    PERFORM pg_temp.sl_later();
    PERFORM sppoultrypayment_record(v_farm, v_s, 1000, 'Cash', fncompany_businessdate(v_farm)::timestamp, NULL, 'cash', 'tester');
    PERFORM sppoultrypayment_record(v_farm, v_s, 916.64, 'Mobile Money', fncompany_businessdate(v_farm)::timestamp, NULL, 'momo', 'tester');
    f := f + pg_temp.sl_chk('T8 1 sale, 2 payments, 2 allocations, 2 receipts, nothing owed', '2|2|2|0',
            (SELECT count(DISTINCT paymentgroupid) FROM poultrypayments WHERE saleid = v_s)::text || '|' ||
            (SELECT count(*) FROM customerpaymentallocation WHERE module = 'poultry' AND saleid = v_s AND status = 'Posted')::text || '|' ||
            (SELECT count(*) FROM poultrycashtransactions ct WHERE ct.paymentgroupid IN (SELECT paymentgroupid FROM poultrypayments WHERE saleid = v_s))::text || '|' ||
            (SELECT count(*) FROM sppoultrycustomeropensales(v_farm, v_cust3))::text);

    -- ================================================== T9  reports
    f := f + pg_temp.sl_chk('T9 egg sales report: one row per line of T8', '2|1916.64',
            (SELECT count(*)::text || '|' || sum(totalamount)::text
             FROM sppoultryreport_eggsales_rs1(v_farm, '2000-01-01', '2100-01-01') WHERE saleid = v_s));
    f := f + pg_temp.sl_chk('T9 headers counted once', '1',
            (SELECT count(DISTINCT saleid) FROM sppoultryreport_eggsales_rs1(v_farm, '2000-01-01', '2100-01-01') WHERE saleid = v_s)::text);

    -- ===================================== T10  double submit, one sale
    v_s  := pg_temp.sl_sale(v_farm, v_cust, v_acct, TRUE,
             jsonb_build_array(pg_temp.sl_line(v_large, 60, 100), pg_temp.sl_line(v_med, 60, 90)), 'T10', 'req-1');
    v_s2 := pg_temp.sl_sale(v_farm, v_cust, v_acct, TRUE,
             jsonb_build_array(pg_temp.sl_line(v_large, 60, 100), pg_temp.sl_line(v_med, 60, 90)), 'T10', 'req-1');
    PERFORM pg_temp.sl_later();
    f := f + pg_temp.sl_chk('T10 same sale returned, posted once', 'true|1|2|1',
            (v_s = v_s2)::text || '|' ||
            (SELECT count(*) FROM sale WHERE farmid = v_farm AND saledescription = 'T10')::text || '|' ||
            (SELECT count(*) FROM poultrystocktransactions WHERE relatedid = v_s AND txntype = 'Sale')::text || '|' ||
            (SELECT count(*) FROM poultrypayments WHERE saleid = v_s)::text);

    -- ================================================== T11  guards
    BEGIN
        UPDATE saleline SET totalamount = 1 WHERE saleid = v_s AND lineno = 2;
        f := f + pg_temp.sl_chk('T11a posted line edit refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sl_like('T11a posted line edit refused', '%posted%lines%', SQLERRM);
    END;
    BEGIN
        v_a := pg_temp.sl_sale(v_farm, v_cust, v_acct, FALSE,
                jsonb_build_array(pg_temp.sl_line(v_large, 30, 50),
                                  jsonb_build_object('product', 'Manure', 'quantity', 2, 'unitPrice', 10, 'totalAmount', 20)), 'T11');
        f := f + pg_temp.sl_chk('T11b mixed products refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sl_like('T11b mixed products refused', '%same product%', SQLERRM);
    END;
    PERFORM sppoultryeggsizes_ensure(v_other, 'tester');
    BEGIN
        v_a := pg_temp.sl_sale(v_farm, v_cust, v_acct, FALSE,
                jsonb_build_array(pg_temp.sl_line(v_large, 30, 50),
                                  pg_temp.sl_line((SELECT c.poultryproductid FROM sppoultryeggclasses_get(v_other, TRUE) c WHERE c.name = 'Large'), 30, 50)), 'T11');
        f := f + pg_temp.sl_chk('T11c another company''s egg class refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sl_like('T11c another company''s egg class refused', '%egg class does not belong%', SQLERRM);
    END;
    f := f + pg_temp.sl_chk('T11d every header equals its lines', '0',
            (SELECT count(*) FROM sale s WHERE s.farmid = v_farm
               AND s.totalamount <> (SELECT sum(l.totalamount) FROM saleline l WHERE l.saleid = s.saleid))::text);

    IF f > 0 THEN
        RAISE EXCEPTION 'sale lines: % check(s) failed', f;
    END IF;
    RAISE NOTICE 'sale lines: all checks passed';
END $t$;

ROLLBACK;

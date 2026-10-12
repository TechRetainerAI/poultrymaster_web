-- Behavioural checks for migrations 351/352: posted sales are immutable,
-- Sale Reversal, Customer Credit, Refunds (poultry).
--
-- SELF-CONTAINED: opens its own transaction and ROLLS IT BACK.
--
--   psql ... -X -f sale-reversal.test.sql
--
-- Companies are fresh uuids per run (no farms row = legacy poultry, UTC).
--
--   A  Posted sale is locked (update / direct UPDATE / DELETE refused, note allowed)
--   B  Fully paid sale, keep payment as customer credit
--   C  Fully paid sale, reverse the associated payment
--   D  Unpaid sale
--   E  Bulk customer payment: only the allocation is released
--   F  Partly paid sale
--   G  Correct Sale, lower amount, credit applied
--   H  Correct Sale, higher amount, credit applied
--   I  Multi-size egg sale restores each size, not Unsorted
--   J  Refund part of the credit
--   K  Double reversal / idempotency key
--   L  Stale preview
--   M  Company isolation
--   N  Walk-in paid sale (no customer): money can only be reversed
--   O  Bird sale restores birds
--   P  Reversing a payment whose credit was applied elsewhere
--   Q  Reports: revenue, receivables, statement, egg stock balance, Cash Flow

BEGIN;

CREATE FUNCTION pg_temp.sr_chk(p_label text, p_expect text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_expect IS NOT DISTINCT FROM p_got THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect % got %', p_label, COALESCE(p_expect, 'NULL'), COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

CREATE FUNCTION pg_temp.sr_like(p_label text, p_pattern text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_got ILIKE p_pattern THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect like "%" got %', p_label, p_pattern, COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

-- A sale exactly as SaleService.Insert writes it (one transaction): the row,
-- its egg class, its cash, and -- when paid to a known customer -- the
-- SaleEntry payment that replaces the residual.
CREATE FUNCTION pg_temp.sr_mksale(p_farm text, p_product text, p_qty numeric, p_price numeric, p_cust integer,
                               p_custname text, p_acct integer, p_paid boolean, p_class integer DEFAULT NULL,
                               p_flock integer DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $c$
DECLARE v integer; v_total numeric := p_qty * p_price;
BEGIN
    v := spsale_insert('tester', p_farm, (fncompany_businessdate(p_farm) - 3)::timestamp, p_product, p_qty, p_price,
                       v_total, 'Cash', p_custname, p_flock, 'test sale', p_paid, NULL, p_cust);
    IF p_class IS NOT NULL THEN
        PERFORM sppoultrysale_setegg(p_farm, v, p_class, NULL, 'tester');
    END IF;
    PERFORM sppoultrysalecash_sync(p_farm, v, p_acct, v_total, p_paid, 'test', 'tester');
    IF p_paid AND p_cust IS NOT NULL THEN
        UPDATE sale SET paid = false WHERE saleid = v;
        PERFORM sppoultrypayment_record(p_farm, v, v_total, 'Cash', (fncompany_businessdate(p_farm) - 3)::timestamp,
                                        NULL, 'Paid at point of sale', 'tester');
    END IF;
    RETURN v;
END $c$;

CREATE FUNCTION pg_temp.sr_onhand(p_farm text, p_product integer)
RETURNS numeric LANGUAGE sql AS $c$
    SELECT COALESCE(SUM(t.quantity), 0) FROM poultrystocktransactions t
    WHERE t.farmid = p_farm AND t.poultryproductid = p_product;
$c$;

CREATE FUNCTION pg_temp.sr_bal(p_acct integer)
RETURNS numeric LANGUAGE sql AS $c$
    SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = p_acct;
$c$;

CREATE FUNCTION pg_temp.sr_ledger(p_farm text, p_acct integer)
RETURNS numeric LANGUAGE sql AS $c$
    SELECT (SELECT a.openingbalance FROM poultrycashaccounts a WHERE a.poultrycashaccountid = p_acct)
         + COALESCE(SUM(t.amount), 0) FROM poultrycashtransactions t
    WHERE t.farmid = p_farm AND t.poultrycashaccountid = p_acct;
$c$;

-- Ends the "creating transaction" for the sales made so far, as a new request would.
CREATE FUNCTION pg_temp.sr_later() RETURNS void LANGUAGE sql AS $c$
    SELECT set_config('poultry.sale_fresh', '', true);
$c$;

DO $t$
DECLARE
    v_farm  text := gen_random_uuid()::text;
    v_other text := gen_random_uuid()::text;
    v_acct  integer;
    v_momo  integer;
    v_oacct integer;
    v_cust  integer;
    v_cust2 integer;
    v_ocust integer;
    v_uns   integer;
    v_large integer;
    v_med   integer;
    v_bird  integer;
    v_s     integer;
    v_s2    integer;
    v_s3    integer;
    v_new   integer;
    v_rev   integer;
    v_rev2  integer;
    v_grp   uuid;
    v_cin   integer;
    v_pv    jsonb;
    v_open  numeric;
    v_b0    numeric;
    v_l0    numeric;
    v_n     integer;
    v_txt   text;
    v_json  text;
    f       integer := 0;
BEGIN
    -- ---------------------------------------------------------------- setup
    PERFORM sppoultryeggsizes_ensure(v_farm, 'tester');
    v_uns   := fnpoultry_unsortedeggproduct(v_farm);
    SELECT c.poultryproductid INTO v_large FROM sppoultryeggclasses_get(v_farm, TRUE) c WHERE c.name = 'Large';
    SELECT c.poultryproductid INTO v_med   FROM sppoultryeggclasses_get(v_farm, TRUE) c WHERE c.name = 'Medium';
    -- stock to sell from
    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, note, createdby)
    VALUES (v_farm, v_uns, 'Production', 5000, 'test', 'tester'),
           (v_farm, v_large, 'Sorting In', 5000, 'test', 'tester'),
           (v_farm, v_med, 'Sorting In', 5000, 'test', 'tester');

    v_acct  := sppoultrycashaccount_insert(v_farm, 'Main Cash', 'Cash', 100000, TRUE, NULL);
    v_momo  := sppoultrycashaccount_insert(v_farm, 'MoMo', 'MobileMoney', 0, TRUE, NULL);
    v_oacct := sppoultrycashaccount_insert(v_other, 'Other Cash', 'Cash', 1000, TRUE, NULL);
    INSERT INTO customer (userid, name, farmid) VALUES ('tester', 'Teacher', v_farm) RETURNING customerid INTO v_cust;
    INSERT INTO customer (userid, name, farmid) VALUES ('tester', 'Second', v_farm) RETURNING customerid INTO v_cust2;
    INSERT INTO customer (userid, name, farmid) VALUES ('tester', 'Elsewhere', v_other) RETURNING customerid INTO v_ocust;

    -- ======================================================= A  the lock
    v_s := pg_temp.sr_mksale(v_farm, 'Eggs', 300, 25, v_cust, 'Teacher', v_acct, TRUE, v_large);
    PERFORM pg_temp.sr_later();

    BEGIN
        PERFORM spsale_update('tester', v_farm, v_s, (fncompany_businessdate(v_farm) - 3)::timestamp, 'Eggs', 290, 25, 7250,
                              'Cash', 'Teacher', NULL, 'test sale', TRUE, NULL, v_cust);
        f := f + pg_temp.sr_chk('A1 quantity edit refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('A1 quantity edit refused', '%posted%quantity%total%Reverse%', SQLERRM);
    END;
    BEGIN
        PERFORM spsale_update('tester', v_farm, v_s, (fncompany_businessdate(v_farm) - 3)::timestamp, 'Eggs', 300, 25, 7500,
                              'Cash', 'Teacher', NULL, 'test sale', FALSE, NULL, v_cust);
        f := f + pg_temp.sr_chk('A2 Paid -> Pending refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('A2 Paid -> Pending refused', '%paid / pending%', SQLERRM);
    END;
    PERFORM spsale_update('tester', v_farm, v_s, (fncompany_businessdate(v_farm) - 3)::timestamp, 'Eggs', 300, 25, 7500,
                          'Cash', 'Teacher', NULL, 'delivered to the school', TRUE, NULL, v_cust);
    f := f + pg_temp.sr_chk('A3 description-only edit saved', 'delivered to the school',
                         (SELECT saledescription FROM sale WHERE saleid = v_s));
    BEGIN
        UPDATE sale SET unitprice = 20, totalamount = 6000 WHERE saleid = v_s;
        f := f + pg_temp.sr_chk('A4 direct UPDATE refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('A4 direct UPDATE refused', '%posted%Reverse%', SQLERRM);
    END;
    BEGIN
        DELETE FROM sale WHERE saleid = v_s;
        f := f + pg_temp.sr_chk('A5 direct DELETE refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('A5 direct DELETE refused', '%cannot be deleted%', SQLERRM);
    END;
    BEGIN
        PERFORM spsale_delete(v_farm, 'tester', v_s);
        f := f + pg_temp.sr_chk('A6 spsale_delete refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('A6 spsale_delete refused', '%Reverse it instead%', SQLERRM);
    END;
    f := f + pg_temp.sr_chk('A7 a new sale is Posted', 'Posted', (SELECT status FROM sale WHERE saleid = v_s));

    -- =========================================== B  paid sale, keep as credit
    -- v_s: 300 Large eggs x 25 = 7,500, paid in cash to Main Cash.
    v_b0 := pg_temp.sr_bal(v_acct);
    v_open := pg_temp.sr_onhand(v_farm, v_large);
    v_pv := sppoultrysale_reversalpreview(v_farm, v_s);
    f := f + pg_temp.sr_chk('B1 preview total', '7500.00', (v_pv->>'total')::numeric(14,2)::text);
    f := f + pg_temp.sr_chk('B2 preview paid', '7500.00', (v_pv->>'paid')::numeric(14,2)::text);
    f := f + pg_temp.sr_chk('B3 one payment, sale-generated', 'true', (v_pv->'payments'->0->>'saleGenerated'));
    f := f + pg_temp.sr_chk('B4 both choices offered', '["KeepAsCredit", "ReversePayment"]', (v_pv->'payments'->0->'allowed')::text);
    f := f + pg_temp.sr_chk('B5 default is keep as credit', 'KeepAsCredit', v_pv->'payments'->0->>'default');
    f := f + pg_temp.sr_chk('B6 restores 300 Large', '300.000|' || v_large, (v_pv->'lines'->0->>'restoreQuantity') || '|' || (v_pv->'lines'->0->>'restoreProductId'));
    f := f + pg_temp.sr_chk('B7 no blockers', '[]', (v_pv->'blockers')::text);

    -- 354: a reason from the list is enough; only "Other" needs words.
    BEGIN
        PERFORM sppoultrysale_reverse(v_farm, v_s, NULL, '   ', '{}'::jsonb, NULL, NULL, 'tester');
        f := f + pg_temp.sr_chk('B8 a reason is required', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('B8 a reason is required', '%reason%', SQLERRM);
    END;
    BEGIN
        PERFORM sppoultrysale_reverse(v_farm, v_s, 'Other', NULL, '{}'::jsonb, NULL, NULL, 'tester');
        f := f + pg_temp.sr_chk('B8b "Other" needs a note', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('B8b "Other" needs a note', '%what happened%', SQLERRM);
    END;

    v_rev := sppoultrysale_reverse(v_farm, v_s, 'Wrong price', 'Customer was charged the old price',
                                   '{}'::jsonb, v_pv->>'fingerprint', 'idem-B', 'tester');
    f := f + pg_temp.sr_chk('B9 sale Reversed', 'Reversed', (SELECT status FROM sale WHERE saleid = v_s));
    f := f + pg_temp.sr_chk('B10 300 Large restored', (v_open + 300)::text, pg_temp.sr_onhand(v_farm, v_large)::text);
    f := f + pg_temp.sr_chk('B11 original Sale movement kept', '1',
                         (SELECT count(*)::text FROM poultrystocktransactions WHERE farmid = v_farm AND relatedid = v_s AND txntype = 'Sale'));
    f := f + pg_temp.sr_chk('B12 opposite Sale Reversal row', '300.000',
                         (SELECT sum(quantity)::numeric(14,3)::text FROM poultrystocktransactions WHERE farmid = v_farm AND relatedid = v_s AND txntype = 'Sale Reversal'));
    f := f + pg_temp.sr_chk('B13 payment stays Posted', 'Posted', (SELECT status FROM poultrypayments WHERE saleid = v_s));
    f := f + pg_temp.sr_chk('B14 allocation Reversed', 'Reversed',
                         (SELECT ca.status FROM customerpaymentallocation ca JOIN poultrypayments pp ON pp.poultrypaymentid = ca.paymentid
                          WHERE ca.module = 'poultry' AND pp.saleid = v_s AND ca.saleid = v_s));
    f := f + pg_temp.sr_chk('B15 cash unchanged', v_b0::text, pg_temp.sr_bal(v_acct)::text);
    f := f + pg_temp.sr_chk('B16 ledger = balance', pg_temp.sr_bal(v_acct)::text, pg_temp.sr_ledger(v_farm, v_acct)::numeric(14,2)::text);
    f := f + pg_temp.sr_chk('B17 customer credit 7,500', '7500.00', fnpoultrycustomer_credit(v_farm, v_cust)::text);
    f := f + pg_temp.sr_chk('B18 no receivable', '0', (SELECT count(*)::text FROM sppoultrycustomeropensales(v_farm, v_cust)));
    f := f + pg_temp.sr_chk('B19 reversal record: credit 7,500, no cash out', 'KeepAsCredit|7500.00|0.00',
                         (SELECT paymenthandling || '|' || creditcreated || '|' || cashreversed FROM poultrysalereversals WHERE salereversalid = v_rev));
    f := f + pg_temp.sr_chk('B20 idempotency key returns the same reversal', v_rev::text,
                         sppoultrysale_reverse(v_farm, v_s, 'Wrong price', 'again', '{}'::jsonb, NULL, 'idem-B', 'tester')::text);

    -- =========================================== K  double reversal
    BEGIN
        PERFORM sppoultrysale_reverse(v_farm, v_s, NULL, 'twice', '{}'::jsonb, NULL, NULL, 'tester');
        f := f + pg_temp.sr_chk('K1 second reversal refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('K1 second reversal refused', '%already been reversed%', SQLERRM);
    END;
    f := f + pg_temp.sr_chk('K2 still one Sale Reversal row', '1',
                         (SELECT count(*)::text FROM poultrystocktransactions WHERE farmid = v_farm AND relatedid = v_s AND txntype = 'Sale Reversal'));
    f := f + pg_temp.sr_chk('K3 credit not doubled', '7500.00', fnpoultrycustomer_credit(v_farm, v_cust)::text);
    BEGIN
        UPDATE sale SET saledescription = 'x' WHERE saleid = v_s;
        f := f + pg_temp.sr_chk('K4 reversed sale frozen', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('K4 reversed sale frozen', '%has been reversed%', SQLERRM);
    END;

    -- ======================================== G  correct sale, lower amount
    -- Re-enter at 20/egg = 6,000 on credit, linked, then apply 6,000 of credit.
    v_b0 := pg_temp.sr_bal(v_acct);
    v_new := pg_temp.sr_mksale(v_farm, 'Eggs', 300, 20, v_cust, 'Teacher', v_acct, FALSE, v_large);
    PERFORM sppoultrysale_linkcorrection(v_farm, v_new, v_s, 'tester');
    f := f + pg_temp.sr_chk('G1 corrected sale links back', v_s::text, (SELECT correctssaleid::text FROM sale WHERE saleid = v_new));
    f := f + pg_temp.sr_chk('G2 reversal links forward', v_new::text, (SELECT correctionsaleid::text FROM poultrysalereversals WHERE salereversalid = v_rev));
    v_n := (SELECT count(*) FROM poultrycashtransactions WHERE farmid = v_farm);
    PERFORM sppoultrycustomercredit_apply(v_farm, v_cust, v_new, 6000, 'tester');
    f := f + pg_temp.sr_chk('G3 corrected sale paid', 'true|6000.00',
                         (SELECT paid::text || '|' || amountpaid::numeric(14,2) FROM sale WHERE saleid = v_new));
    f := f + pg_temp.sr_chk('G4 remaining credit 1,500', '1500.00', fnpoultrycustomer_credit(v_farm, v_cust)::text);
    f := f + pg_temp.sr_chk('G5 no new cash receipt', v_b0::text, pg_temp.sr_bal(v_acct)::text);
    f := f + pg_temp.sr_chk('G6 no new cash row', v_n::text, (SELECT count(*)::text FROM poultrycashtransactions WHERE farmid = v_farm));
    f := f + pg_temp.sr_chk('G7 no new payment row', '0', (SELECT count(*)::text FROM poultrypayments WHERE saleid = v_new));
    f := f + pg_temp.sr_chk('G7b payment history: the payment once, at 7,500', '1|7500.00',
                         (SELECT count(*) || '|' || max(totalamount)::numeric(14,2) FROM sppoultrycustomerpayment_history(v_farm, v_cust)
                          WHERE paymentgroupid = (SELECT paymentgroupid FROM poultrypayments WHERE saleid = v_s)));
    f := f + pg_temp.sr_chk('G7c the corrected sale''s history shows the credit it was paid with', '1',
                         (SELECT count(*)::text FROM sppoultrycustomerpayment_history(v_farm, NULL, v_new)));
    f := f + pg_temp.sr_chk('G8 Cash Flow: no residual for the credit-paid sale', '0',
                         (SELECT count(*)::text FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r WHERE r.rowsource = 'SaleResidual' AND r.sourceid = v_new));
    BEGIN
        PERFORM sppoultrysale_linkcorrection(v_farm, v_new, v_s, 'tester');
        PERFORM sppoultrysale_linkcorrection(v_farm, pg_temp.sr_mksale(v_farm, 'Eggs', 1, 1, v_cust, 'Teacher', v_acct, FALSE), v_s, 'tester');
        f := f + pg_temp.sr_chk('G9 only one correction per reversal', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('G9 only one correction per reversal', '%already corrected%', SQLERRM);
    END;

    -- ======================================== H  correct sale, higher amount
    v_s2 := pg_temp.sr_mksale(v_farm, 'Eggs', 300, 25, v_cust2, 'Second', v_acct, TRUE);   -- Unsorted
    PERFORM pg_temp.sr_later();
    PERFORM sppoultrysale_reverse(v_farm, v_s2, 'Wrong price', 'should be 30', '{}'::jsonb, NULL, NULL, 'tester');
    v_b0 := pg_temp.sr_bal(v_acct);
    v_new := pg_temp.sr_mksale(v_farm, 'Eggs', 300, 30, v_cust2, 'Second', v_acct, FALSE);
    PERFORM sppoultrysale_linkcorrection(v_farm, v_new, v_s2, 'tester');
    PERFORM sppoultrycustomercredit_apply(v_farm, v_cust2, v_new, 7500, 'tester');
    f := f + pg_temp.sr_chk('H1 paid 7,500, owes 1,500', '7500.00|1500.00',
                         (SELECT amountpaid::numeric(14,2) || '|' || fnpoultrysalebalance(paid, totalamount, amountpaid) FROM sale WHERE saleid = v_new));
    f := f + pg_temp.sr_chk('H2 no new Money In', v_b0::text, pg_temp.sr_bal(v_acct)::text);
    f := f + pg_temp.sr_chk('H3 credit used up', '0.00', fnpoultrycustomer_credit(v_farm, v_cust2)::text);
    BEGIN
        PERFORM sppoultrycustomercredit_apply(v_farm, v_cust2, v_new, 100, 'tester');
        f := f + pg_temp.sr_chk('H4 cannot apply more credit than held', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('H4 cannot apply more credit than held', '%only has%credit%', SQLERRM);
    END;

    -- ======================================== C  paid sale, reverse payment
    v_s3 := pg_temp.sr_mksale(v_farm, 'Eggs', 300, 25, v_cust2, 'Second', v_acct, TRUE, v_large);
    PERFORM pg_temp.sr_later();
    v_b0 := pg_temp.sr_bal(v_acct);
    v_open := pg_temp.sr_onhand(v_farm, v_large);
    SELECT paymentgroupid INTO v_grp FROM poultrypayments WHERE saleid = v_s3;
    -- 353: the receipt is kept, not rebuilt -- same row, same creator.
    SELECT poultrycashtransactionid INTO v_cin FROM poultrycashtransactions
    WHERE  farmid = v_farm AND paymentgroupid = v_grp AND sourcetype = 'CustomerPayment';
    UPDATE poultrycashtransactions SET createdby = 'original clerk' WHERE poultrycashtransactionid = v_cin;
    v_rev := sppoultrysale_reverse(v_farm, v_s3, 'Duplicate sale', 'entered twice',
                                   jsonb_build_object(v_grp::text, 'ReversePayment'), NULL, NULL, 'tester');
    f := f + pg_temp.sr_chk('C1 payment Reversed', 'Reversed', (SELECT status FROM poultrypayments WHERE saleid = v_s3));
    f := f + pg_temp.sr_chk('C2 cash -7,500 on the original account', (v_b0 - 7500)::text, pg_temp.sr_bal(v_acct)::text);
    f := f + pg_temp.sr_chk('C3 ledger keeps the CashIn and adds a CashOut', '7500.00|-7500.00',
                         (SELECT string_agg(amount::numeric(14,2)::text, '|' ORDER BY amount DESC) FROM poultrycashtransactions
                          WHERE farmid = v_farm AND paymentgroupid = v_grp));
    f := f + pg_temp.sr_chk('C4 ledger = balance', pg_temp.sr_bal(v_acct)::text, pg_temp.sr_ledger(v_farm, v_acct)::numeric(14,2)::text);
    f := f + pg_temp.sr_chk('C4b the original CashIn row is kept (id, creator)', v_cin::text || '|original clerk|7500.00',
                         (SELECT poultrycashtransactionid || '|' || createdby || '|' || amount FROM poultrycashtransactions
                          WHERE farmid = v_farm AND paymentgroupid = v_grp AND sourcetype = 'CustomerPayment'));
    f := f + pg_temp.sr_chk('C5 Cash Flow: receipt stays, reversal is Money Out (contra-sales)', '7500.00|-7500.00|OperatingIn',
                         (SELECT max(amount) FILTER (WHERE rowsource = 'Receipt')::numeric(14,2) || '|' ||
                                 max(amount) FILTER (WHERE rowsource = 'ReceiptReversal')::numeric(14,2) || '|' ||
                                 max(flowgroup) FILTER (WHERE rowsource = 'ReceiptReversal')
                          FROM sppoultrycashflow_rows(v_farm, NULL, NULL) WHERE sourceid = v_s3));
    f := f + pg_temp.sr_chk('C6 not an expense', '0', (SELECT count(*)::text FROM sppoultrycashflow_detail(v_farm, NULL, NULL)
                                                    WHERE sourceid = v_s3 AND flowgroup = 'OperatingOut'));
    f := f + pg_temp.sr_chk('C7 stock restored', (v_open + 300)::text, pg_temp.sr_onhand(v_farm, v_large)::text);
    f := f + pg_temp.sr_chk('C8 no credit created', '0.00', fnpoultrycustomer_credit(v_farm, v_cust2)::text);
    f := f + pg_temp.sr_chk('C9 reversal record', 'ReversePayment|0.00|7500.00',
                         (SELECT paymenthandling || '|' || creditcreated || '|' || cashreversed FROM poultrysalereversals WHERE salereversalid = v_rev));
    f := f + pg_temp.sr_chk('C10 payment still in history', '1', (SELECT count(*)::text FROM poultrypayments WHERE saleid = v_s3));

    -- ======================================================= D  unpaid sale
    v_s := pg_temp.sr_mksale(v_farm, 'Eggs', 400, 25, v_cust2, 'Second', v_acct, FALSE);
    PERFORM pg_temp.sr_later();
    v_b0 := pg_temp.sr_bal(v_acct);
    v_n := (SELECT count(*) FROM poultrycashtransactions WHERE farmid = v_farm);
    v_open := pg_temp.sr_onhand(v_farm, v_uns);
    v_pv := sppoultrysale_reversalpreview(v_farm, v_s);
    f := f + pg_temp.sr_chk('D1 no payments to handle', '0', jsonb_array_length(v_pv->'payments')::text);
    f := f + pg_temp.sr_chk('D2 outstanding 10,000', '10000.00', (v_pv->>'outstanding')::numeric(14,2)::text);
    v_rev := sppoultrysale_reverse(v_farm, v_s, 'Entered by mistake', NULL, '{}'::jsonb, NULL, NULL, 'tester');
    f := f + pg_temp.sr_chk('D0 a listed reason alone is enough', 'Entered by mistake|Entered by mistake|',
                         (SELECT s.reversalreason || '|' || r.reasoncode || '|' || r.reason FROM sale s
                          JOIN poultrysalereversals r ON r.salereversalid = s.salereversalid WHERE s.saleid = v_s));
    f := f + pg_temp.sr_chk('D3 handling None', 'None', (SELECT paymenthandling FROM poultrysalereversals WHERE salereversalid = v_rev));
    f := f + pg_temp.sr_chk('D4 cash untouched', v_b0::text, pg_temp.sr_bal(v_acct)::text);
    f := f + pg_temp.sr_chk('D5 no cash rows written', v_n::text, (SELECT count(*)::text FROM poultrycashtransactions WHERE farmid = v_farm));
    f := f + pg_temp.sr_chk('D6 Unsorted restored', (v_open + 400)::text, pg_temp.sr_onhand(v_farm, v_uns)::text);
    f := f + pg_temp.sr_chk('D7 receivable gone', '0', (SELECT count(*)::text FROM sppoultrycustomeropensales(v_farm, v_cust2) WHERE saleid = v_s));

    -- ================================================== E  bulk payment
    v_s  := pg_temp.sr_mksale(v_farm, 'Eggs', 300, 25, v_cust, 'Teacher', v_acct, FALSE);   -- A 7,500
    v_s2 := pg_temp.sr_mksale(v_farm, 'Eggs', 200, 25, v_cust, 'Teacher', v_acct, FALSE);   -- B 5,000
    v_s3 := pg_temp.sr_mksale(v_farm, 'Eggs', 300, 25, v_cust, 'Teacher', v_acct, FALSE);   -- C 7,500
    v_grp := sppoultrycustomerpayment_record(v_farm, v_cust, 20000,
                 jsonb_build_array(jsonb_build_object('saleid', v_s, 'amount', 7500),
                                   jsonb_build_object('saleid', v_s2, 'amount', 5000),
                                   jsonb_build_object('saleid', v_s3, 'amount', 7500)),
                 'Cash', (fncompany_businessdate(v_farm) - 1)::timestamp, v_acct, NULL, NULL, 'CustomerBalances', 'tester');
    PERFORM pg_temp.sr_later();
    v_b0 := pg_temp.sr_bal(v_acct);
    v_l0 := fnpoultrycustomer_credit(v_farm, v_cust);
    v_pv := sppoultrysale_reversalpreview(v_farm, v_s);
    f := f + pg_temp.sr_chk('E1 bulk payment: credit only', '["KeepAsCredit"]', (v_pv->'payments'->0->'allowed')::text);
    f := f + pg_temp.sr_like('E2 explains why', '%received on its own%', v_pv->'payments'->0->>'reverseUnavailableReason');
    BEGIN
        PERFORM sppoultrysale_reverse(v_farm, v_s, NULL, 'x', jsonb_build_object(v_grp::text, 'ReversePayment'), NULL, NULL, 'tester');
        f := f + pg_temp.sr_chk('E3 reversing the bulk payment refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('E3 reversing the bulk payment refused', '%received on its own%', SQLERRM);
    END;
    PERFORM sppoultrysale_reverse(v_farm, v_s, 'Wrong customer', 'was for someone else', '{}'::jsonb, NULL, NULL, 'tester');
    f := f + pg_temp.sr_chk('E4 payment stays Posted, 20,000', 'Posted|20000.00',
                         (SELECT min(status) || '|' || sum(amount)::numeric(14,2) FROM poultrypayments WHERE paymentgroupid = v_grp));
    f := f + pg_temp.sr_chk('E5 A released, B and C kept', 'Reversed|Posted|Posted',
                         (SELECT string_agg(ca.status, '|' ORDER BY ca.saleid) FROM customerpaymentallocation ca
                          JOIN poultrypayments pp ON pp.poultrypaymentid = ca.paymentid WHERE pp.paymentgroupid = v_grp));
    f := f + pg_temp.sr_chk('E6 credit +7,500', (v_l0 + 7500)::text, fnpoultrycustomer_credit(v_farm, v_cust)::text);
    f := f + pg_temp.sr_chk('E7 cash unchanged', v_b0::text, pg_temp.sr_bal(v_acct)::text);
    f := f + pg_temp.sr_chk('E8 B and C still paid', 'true|true',
                         (SELECT string_agg(paid::text, '|' ORDER BY saleid) FROM sale WHERE saleid IN (v_s2, v_s3)));

    -- ================================================== F  part-paid sale
    v_s := pg_temp.sr_mksale(v_farm, 'Eggs', 400, 25, v_cust2, 'Second', v_acct, FALSE);    -- 10,000
    PERFORM sppoultrypayment_record(v_farm, v_s, 4000, 'Cash', fncompany_businessdate(v_farm)::timestamp, NULL, 'part', 'tester');
    PERFORM pg_temp.sr_later();
    v_b0 := pg_temp.sr_bal(v_acct);
    v_pv := sppoultrysale_reversalpreview(v_farm, v_s);
    f := f + pg_temp.sr_chk('F1 paid 4,000, owes 6,000', '4000.00|6000.00',
                         (v_pv->>'paid')::numeric(14,2) || '|' || (v_pv->>'outstanding')::numeric(14,2));
    PERFORM sppoultrysale_reverse(v_farm, v_s, 'Wrong quantity', 'x', '{}'::jsonb, NULL, NULL, 'tester');
    f := f + pg_temp.sr_chk('F2 credit 4,000', '4000.00', fnpoultrycustomer_credit(v_farm, v_cust2)::text);
    f := f + pg_temp.sr_chk('F3 cash unchanged', v_b0::text, pg_temp.sr_bal(v_acct)::text);
    f := f + pg_temp.sr_chk('F4 no receivable left', '0', (SELECT count(*)::text FROM sppoultrycustomeropensales(v_farm, v_cust2) WHERE saleid = v_s));

    -- ================================================== J  refund
    v_b0 := pg_temp.sr_bal(v_momo);
    v_open := pg_temp.sr_onhand(v_farm, v_uns);
    v_n := sppoultrycustomerrefund_record(v_farm, v_cust2, 2500, v_momo, 'MoMo', NULL, 'Customer asked for money back', 'tester');
    f := f + pg_temp.sr_chk('J1 credit 4,000 -> 1,500', '1500.00', fnpoultrycustomer_credit(v_farm, v_cust2)::text);
    f := f + pg_temp.sr_chk('J2 refund paid from the chosen account', (v_b0 - 2500)::text, pg_temp.sr_bal(v_momo)::text);
    f := f + pg_temp.sr_chk('J3 refund numbered', 'RF-00001', (SELECT refundnumber FROM poultrycustomerrefunds WHERE refundid = v_n));
    f := f + pg_temp.sr_chk('J4 Cash Flow: Money Out, not an expense', '-2500.00|OperatingIn|Customer refunds',
                         (SELECT amount::numeric(14,2) || '|' || flowgroup || '|' || category FROM sppoultrycashflow_detail(v_farm, NULL, NULL)
                          WHERE rowsource = 'CustomerRefund' AND sourceid = v_n));
    f := f + pg_temp.sr_chk('J5 no stock moved', v_open::text, pg_temp.sr_onhand(v_farm, v_uns)::text);
    f := f + pg_temp.sr_chk('J6 statement shows the refund as a debit', '2500.00',
                         (SELECT debit::text FROM sppoultrycustomerstatement(v_farm, v_cust2) WHERE entrytype = 'Refund'));
    BEGIN
        PERFORM sppoultrycustomerrefund_record(v_farm, v_cust2, 2000, v_momo, 'MoMo', NULL, 'too much', 'tester');
        f := f + pg_temp.sr_chk('J7 refund above credit refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('J7 refund above credit refused', '%only has%credit%', SQLERRM);
    END;
    f := f + pg_temp.sr_chk('J8 momo ledger = balance', pg_temp.sr_bal(v_momo)::text, pg_temp.sr_ledger(v_farm, v_momo)::numeric(14,2)::text);

    -- ========================================= I  multi-size egg sale
    v_json := json_build_array(json_build_object('product', 'Eggs', 'eggProductId', v_large, 'quantity', 300, 'unitPrice', 2, 'totalAmount', 600),
                               json_build_object('product', 'Eggs', 'eggProductId', v_med,   'quantity', 150, 'unitPrice', 2, 'totalAmount', 300))::text;
    v_txt := sppoultrysale_creategroup(v_farm, 'tester', (fncompany_businessdate(v_farm) - 2)::timestamp, 'Teacher', v_cust,
                                       'Cash', v_acct, TRUE, 'two sizes', NULL, v_json)::text;
    SELECT min(saleid) INTO v_s FROM sale WHERE farmid = v_farm AND saledescription = 'two sizes';
    PERFORM pg_temp.sr_later();
    v_open := pg_temp.sr_onhand(v_farm, v_large);
    v_l0 := pg_temp.sr_onhand(v_farm, v_med);
    v_b0 := pg_temp.sr_onhand(v_farm, v_uns);
    v_pv := sppoultrysale_reversalpreview(v_farm, v_s);
    f := f + pg_temp.sr_chk('I1 the whole SG sale is reversed together', '2', jsonb_array_length(v_pv->'saleIds')::text);
    PERFORM sppoultrysale_reverse(v_farm, v_s, 'Wrong product', 'x', '{}'::jsonb, NULL, NULL, 'tester');
    f := f + pg_temp.sr_chk('I2 Large +300', (v_open + 300)::text, pg_temp.sr_onhand(v_farm, v_large)::text);
    f := f + pg_temp.sr_chk('I3 Medium +150', (v_l0 + 150)::text, pg_temp.sr_onhand(v_farm, v_med)::text);
    f := f + pg_temp.sr_chk('I4 Unsorted untouched', v_b0::text, pg_temp.sr_onhand(v_farm, v_uns)::text);
    f := f + pg_temp.sr_chk('I5 both rows Reversed', 'Reversed', (SELECT string_agg(DISTINCT status, ',') FROM sale WHERE farmid = v_farm AND saledescription = 'two sizes'));
    f := f + pg_temp.sr_chk('I6 egg ledger labels the reversal', '2',
                         (SELECT count(*)::text FROM sppoultryeggledger(v_farm) WHERE txntype = 'Sale Reversal' AND reference LIKE 'Reversal of SG-%'));

    -- ===================================== N  walk-in paid sale, no customer
    v_s := pg_temp.sr_mksale(v_farm, 'Eggs', 100, 25, NULL, NULL, v_acct, TRUE);   -- residual cash, no payment row
    PERFORM pg_temp.sr_later();
    v_b0 := pg_temp.sr_bal(v_acct);
    v_pv := sppoultrysale_reversalpreview(v_farm, v_s);
    f := f + pg_temp.sr_chk('N1 money received at the sale', 'AT-SALE|["ReversePayment"]',
                         (v_pv->'payments'->0->>'key') || '|' || (v_pv->'payments'->0->'allowed')::text);
    BEGIN
        PERFORM sppoultrysale_reverse(v_farm, v_s, NULL, 'x', '{"AT-SALE":"KeepAsCredit"}'::jsonb, NULL, NULL, 'tester');
        f := f + pg_temp.sr_chk('N2 no credit without a customer', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('N2 no credit without a customer', '%no customer%', SQLERRM);
    END;
    PERFORM sppoultrysale_reverse(v_farm, v_s, 'Duplicate sale', 'x', '{}'::jsonb, NULL, NULL, 'tester');
    f := f + pg_temp.sr_chk('N3 cash -2,500', (v_b0 - 2500)::text, pg_temp.sr_bal(v_acct)::text);
    f := f + pg_temp.sr_chk('N4 recorded as the payment it should have been, then reversed', 'SaleEntry|Reversed',
                         (SELECT sourcetype || '|' || status FROM poultrypayments WHERE saleid = v_s));
    f := f + pg_temp.sr_chk('N5 ledger = balance', pg_temp.sr_bal(v_acct)::text, pg_temp.sr_ledger(v_farm, v_acct)::numeric(14,2)::text);
    f := f + pg_temp.sr_chk('N6 Cash Flow nets to zero for the sale', '0.00',
                         (SELECT COALESCE(sum(amount), 0)::numeric(14,2)::text FROM sppoultrycashflow_rows(v_farm, NULL, NULL) WHERE sourceid = v_s
                            AND rowsource IN ('Receipt', 'ReceiptReversal', 'SaleResidual')));

    -- ======================================================== O  bird sale
    v_s := pg_temp.sr_mksale(v_farm, 'Birds', 10, 50, v_cust, 'Teacher', v_acct, FALSE);
    PERFORM pg_temp.sr_later();
    SELECT poultryproductid INTO v_bird FROM poultrystocktransactions WHERE farmid = v_farm AND relatedid = v_s AND txntype = 'Bird Sale' LIMIT 1;
    v_open := pg_temp.sr_onhand(v_farm, v_bird);
    PERFORM sppoultrysale_reverse(v_farm, v_s, NULL, 'x', '{}'::jsonb, NULL, NULL, 'tester');
    f := f + pg_temp.sr_chk('O1 birds back', (v_open + 10)::text, pg_temp.sr_onhand(v_farm, v_bird)::text);
    f := f + pg_temp.sr_chk('O2 Bird Sale movements net to zero', '0.000',
                         (SELECT sum(quantity)::numeric(14,3)::text FROM poultrystocktransactions WHERE farmid = v_farm AND relatedid = v_s AND txntype = 'Bird Sale'));

    -- ===================================================== L  stale preview
    v_s := pg_temp.sr_mksale(v_farm, 'Eggs', 100, 25, v_cust, 'Teacher', v_acct, FALSE);
    PERFORM pg_temp.sr_later();
    v_pv := sppoultrysale_reversalpreview(v_farm, v_s);
    PERFORM sppoultrypayment_record(v_farm, v_s, 1000, 'Cash', fncompany_businessdate(v_farm)::timestamp, NULL, 'meanwhile', 'tester');
    BEGIN
        PERFORM sppoultrysale_reverse(v_farm, v_s, NULL, 'x', '{}'::jsonb, v_pv->>'fingerprint', NULL, 'tester');
        f := f + pg_temp.sr_chk('L1 stale preview refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('L1 stale preview refused', '%changed after the reversal preview%', SQLERRM);
    END;
    f := f + pg_temp.sr_chk('L2 nothing reversed', 'Posted', (SELECT status FROM sale WHERE saleid = v_s));

    -- =================================================== M  company isolation
    v_s2 := pg_temp.sr_mksale(v_other, 'Eggs', 10, 25, v_ocust, 'Elsewhere', v_oacct, FALSE);
    BEGIN
        PERFORM sppoultrycustomercredit_apply(v_farm, v_cust, v_s2, 100, 'tester');
        f := f + pg_temp.sr_chk('M1 credit cannot pay another company''s sale', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('M1 credit cannot pay another company''s sale', '%not found for this company%', SQLERRM);
    END;
    f := f + pg_temp.sr_chk('M2 other company''s sale not visible', 'NotFound',
                         sppoultrysale_reversalpreview(v_farm, v_s2)->'blockers'->0->>'code');
    BEGIN
        PERFORM sppoultrycustomerrefund_record(v_farm, v_cust, 10, v_oacct, 'Cash', NULL, 'x', 'tester');
        f := f + pg_temp.sr_chk('M3 refund from another company''s account refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('M3 refund from another company''s account refused', '%cash account%', SQLERRM);
    END;
    BEGIN
        PERFORM sppoultrycustomerrefund_record(v_farm, v_ocust, 10, v_acct, 'Cash', NULL, 'x', 'tester');
        f := f + pg_temp.sr_chk('M4 refund to another company''s customer refused', 'refused', 'accepted');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.sr_like('M4 refund to another company''s customer refused', '%does not belong%', SQLERRM);
    END;

    -- ========== P  reversing a payment whose credit was applied elsewhere
    -- Teacher's 1,500 credit (left over from G) -> sale X; then reverse the
    -- payment that held it: X must go back to owing.
    v_s := pg_temp.sr_mksale(v_farm, 'Eggs', 60, 25, v_cust, 'Teacher', v_acct, FALSE);   -- 1,500
    PERFORM sppoultrycustomercredit_apply(v_farm, v_cust, v_s, 1500, 'tester');
    SELECT pp.paymentgroupid INTO v_grp FROM customerpaymentallocation ca JOIN poultrypayments pp ON pp.poultrypaymentid = ca.paymentid
    WHERE ca.module = 'poultry' AND ca.saleid = v_s AND ca.status = 'Posted' LIMIT 1;
    f := f + pg_temp.sr_chk('P1 credit paid the sale', 'true', (SELECT paid::text FROM sale WHERE saleid = v_s));
    PERFORM sppoultrycustomerpayment_reverse(v_farm, v_grp, 'wrong receipt', 'tester');
    f := f + pg_temp.sr_chk('P2 sale owes again', 'false|0.00', (SELECT paid::text || '|' || amountpaid::numeric(14,2) FROM sale WHERE saleid = v_s));
    f := f + pg_temp.sr_chk('P3 ledger = balance', pg_temp.sr_bal(v_acct)::text, pg_temp.sr_ledger(v_farm, v_acct)::numeric(14,2)::text);

    -- ================================================================ Q  reports
    f := f + pg_temp.sr_chk('Q1 revenue excludes reversed sales', '0',
                         (SELECT count(*)::text FROM fnpoultrypl_revenuelines(v_farm, '2000-01-01', '2100-01-01') r
                          JOIN sale s ON s.saleid = r.saleid WHERE s.status = 'Reversed'));
    f := f + pg_temp.sr_chk('Q2 receivables exclude reversed sales', '0',
                         (SELECT count(*)::text FROM sppoultrycustomeropensales(v_farm, v_cust) o
                          JOIN sale s ON s.saleid = o.saleid WHERE s.status = 'Reversed'));
    f := f + pg_temp.sr_chk('Q3 balance audit has no reversed sale', '0',
                         (SELECT count(*)::text FROM fnbalanceaudit(v_farm, 'poultry') a
                          JOIN sale s ON s.saleid = a.documentid WHERE a.side = 'customer' AND s.status = 'Reversed'));
    f := f + pg_temp.sr_chk('Q4 egg stock report counts sold eggs once', '0',
                         (SELECT (r.salesinrange + r.stockmovesinrange
                                  - (SELECT -COALESCE(sum(t.quantity), 0)::bigint FROM poultrystocktransactions t
                                     WHERE t.farmid = v_farm AND fnpoultry_iseggclass(v_farm, t.poultryproductid)
                                       AND t.txntype IN ('Sale', 'Sale Reversal')
                                       AND t.relatedid IN (SELECT saleid FROM sale WHERE farmid = v_farm AND status = 'Posted'))
                                  - (SELECT COALESCE(sum(t.quantity), 0)::bigint FROM poultrystocktransactions t
                                     WHERE t.farmid = v_farm AND fnpoultry_iseggclass(v_farm, t.poultryproductid)
                                       AND t.txntype NOT IN ('Production', 'Sale', 'Sale Reversal')))::text
                          FROM sppoultryreport_eggstockbalance(v_farm, '2000-01-01', '2100-01-01') r));
    f := f + pg_temp.sr_chk('Q5 main cash ledger = balance at the end', pg_temp.sr_bal(v_acct)::text,
                         pg_temp.sr_ledger(v_farm, v_acct)::numeric(14,2)::text);
    f := f + pg_temp.sr_chk('Q6 Cash Flow closing = ledger movement (Main Cash + MoMo)',
                         ((pg_temp.sr_ledger(v_farm, v_acct) - 100000) + pg_temp.sr_ledger(v_farm, v_momo))::numeric(14,2)::text,
                         (SELECT cashathand::numeric(14,2)::text FROM sppoultrycashflow_summary(v_farm, NULL, NULL)));

    IF f > 0 THEN
        RAISE EXCEPTION '% sale reversal check(s) failed', f;
    END IF;
    RAISE NOTICE 'sale reversal: all checks passed';
END $t$;

ROLLBACK;

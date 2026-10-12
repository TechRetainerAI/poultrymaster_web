-- Behavioural checks for migrations 345 (Receive Purchase) and 346 (Cash Flow
-- for deferred stock purchases).
--
-- SELF-CONTAINED: opens its own transaction and ROLLS IT BACK, so it writes
-- nothing even when run on its own.
--
--   psql ... -X -f poultry-receive-purchase.test.sql
--
-- Every check prints "ok" or "FAIL"; the block RAISES at the end if any failed,
-- so the apply script's dry run stops on a failure rather than scrolling past.
--
-- Fixtures live on a fresh uuid-shaped company per run: expense.farmid is a
-- uuid, and the expense arm of a supplier payment silently does nothing for a
-- farm id that will not cast (historical-batch-purchase gotcha), so a
-- non-uuid sentinel would "prove" no-double-expense against nothing.
--
--   A  Paid purchase, expensed as paid (purchase-based)
--   B  Credit purchase
--   C  Part payment 10,000 / 4,000 / 6,000, then settled from Supplier Balances
--   D  Paid purchase, expensed when used (consumption-based) + Cash Flow (346)
--   E  Mixed invoice: one purchase-based line, one consumption-based line
--   F  Additional costs: pro-rata landed cost, pennies to the last line
--   G  FIFO / LIFO / HIFO draw from receipt lots
--   H  Supplier balance, inventory value, no-double-count totals
--   I  Reversal (paid, purchase-based) -- append-only
--   J  Reversal (consumption-based) -- deferred and Cash Flow drop out
--   K  Reversal blocked: consumed, stock short, other payment, reconciled
--   L  Duplicate prevention: request id, invoice reference, lot lock
--   M  Validation
--   N  Company isolation
--   O  Permissions

BEGIN;

CREATE FUNCTION pg_temp.chk(p_label text, p_expect text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_expect IS NOT DISTINCT FROM p_got THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect % got %', p_label, COALESCE(p_expect, 'NULL'), COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

CREATE FUNCTION pg_temp.chk_like(p_label text, p_pattern text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_got ILIKE p_pattern THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect like "%" got %', p_label, p_pattern, COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

-- One receipt line as the C# side serialises it (lowercase keys).
CREATE FUNCTION pg_temp.ln(p_item integer, p_qty numeric, p_cost numeric,
                           p_unit text DEFAULT NULL, p_mult numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE sql AS $c$
    SELECT jsonb_build_object('itemid', p_item, 'quantity', p_qty, 'unitcost', p_cost,
                              'productionunit', p_unit, 'productionunitsperpurchaseunit', p_mult);
$c$;

DO $t$
DECLARE
    v_farm   text := gen_random_uuid()::text;
    v_other  text := gen_random_uuid()::text;
    v_gid    uuid;
    v_today  date;
    v_d      timestamp;
    v_sup    integer;
    v_sup2   integer;
    v_osup   integer;
    v_acct   integer;
    v_acct2  integer;
    v_oacct  integer;
    i_ewp    integer;    -- expensed as paid
    i_ewc    integer;    -- expensed when used
    i_fifo   integer;
    i_lifo   integer;
    i_hifo   integer;
    i_other  integer;    -- belongs to the other company
    r_a integer; r_b integer; r_c integer; r_d integer; r_e integer; r_f integer;
    r_g1 integer; r_g2 integer; r_k integer; r_k2 integer; r_k3 integer; r_l integer;
    v_lot    integer;
    v_lot2   integer;
    v_pay    integer;
    v_use    integer;
    v_rid    integer;
    v_req    uuid := gen_random_uuid();
    v_n      integer;
    v_num    numeric;
    v_num2   numeric;
    v_txt    text;
    v_cash0  numeric;
    v_cf0    numeric;
    f        integer := 0;
BEGIN
    v_gid   := v_farm::uuid;
    v_today := fncompany_businessdate(v_farm);
    v_d     := (v_today - 3)::timestamp;

    -- ---------------------------------------------------------------- fixtures
    INSERT INTO supplier (userid, farmid, name, createddate, paymenttermsdays)
    VALUES ('tester', v_farm, 'ZZ Feed Mill Ltd', now(), 30) RETURNING supplierid INTO v_sup;
    INSERT INTO supplier (userid, farmid, name, createddate, paymenttermsdays)
    VALUES ('tester', v_farm, 'ZZ Vet Supplies', now(), 0) RETURNING supplierid INTO v_sup2;
    INSERT INTO supplier (userid, farmid, name, createddate, paymenttermsdays)
    VALUES ('tester', v_other, 'ZZ Someone Else', now(), 0) RETURNING supplierid INTO v_osup;

    INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, allownegativebalance)
    VALUES (v_farm, 'ZZ Cash', 'Cash', 100000, 100000, false) RETURNING poultrycashaccountid INTO v_acct;
    INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, allownegativebalance)
    VALUES (v_farm, 'ZZ Petty', 'Cash', 100, 100, false) RETURNING poultrycashaccountid INTO v_acct2;
    INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, allownegativebalance)
    VALUES (v_other, 'ZZ Their Cash', 'Cash', 100000, 100000, false) RETURNING poultrycashaccountid INTO v_oacct;

    INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, usagemethod, costrecognitionoverride, createdat)
    VALUES (v_farm, 'ZZ Maize', 'Feed Ingredient', 'kg', 0, true, 'FIFO', 'EXPENSE_WHEN_PURCHASED', now()) RETURNING poultryrawmaterialitemid INTO i_ewp;
    INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, usagemethod, costrecognitionoverride, createdat)
    VALUES (v_farm, 'ZZ Vaccine', 'Medication', 'dose', 0, true, 'FIFO', 'EXPENSE_WHEN_CONSUMED', now()) RETURNING poultryrawmaterialitemid INTO i_ewc;
    INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, usagemethod, createdat)
    VALUES (v_farm, 'ZZ Soya FIFO', 'Feed Ingredient', 'kg', 0, true, 'FIFO', now()) RETURNING poultryrawmaterialitemid INTO i_fifo;
    INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, usagemethod, createdat)
    VALUES (v_farm, 'ZZ Soya LIFO', 'Feed Ingredient', 'kg', 0, true, 'LIFO', now()) RETURNING poultryrawmaterialitemid INTO i_lifo;
    INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, usagemethod, createdat)
    VALUES (v_farm, 'ZZ Soya HIFO', 'Feed Ingredient', 'kg', 0, true, 'HIFO', now()) RETURNING poultryrawmaterialitemid INTO i_hifo;
    INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, createdat)
    VALUES (v_other, 'ZZ Their Maize', 'Feed Ingredient', 'kg', 0, true, now()) RETURNING poultryrawmaterialitemid INTO i_other;

    SELECT COALESCE(SUM(-r.amount) FILTER (WHERE r.amount < 0), 0) INTO v_cf0
    FROM   sppoultrycashflow_rows(v_farm, NULL, NULL) r;
    f := f + pg_temp.chk('0. empty company has no cash flow', '0', v_cf0::text);

    -- ===================================================== A. paid, purchase-based
    r_a := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, 'INV-A1', NULL, 'paid now',
              jsonb_build_array(pg_temp.ln(i_ewp, 10, 100)), 0, NULL, 1000, 'Cash', v_acct, NULL, 'tester');
    SELECT rl.poultryrawmaterialpurchaseid INTO v_lot FROM poultrypurchasereceiptlines rl WHERE rl.poultrypurchasereceiptid = r_a;

    f := f + pg_temp.chk('A1. stock raised by receipt', '10.000',
            (SELECT currentquantity::numeric(14,3)::text FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = i_ewp));
    f := f + pg_temp.chk('A2. one cost layer, full remaining', '10.000',
            (SELECT remainingquantity::numeric(14,3)::text FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot));
    f := f + pg_temp.chk('A3. method stamped from the item', 'EXPENSE_WHEN_PURCHASED',
            (SELECT costrecognitionmethod FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot));
    f := f + pg_temp.chk('A4. lot fully paid', '1000.00',
            (SELECT amountpaid::text FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot));
    f := f + pg_temp.chk('A5. cash account down 1000', '99000.00',
            (SELECT currentbalance::text FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct));
    f := f + pg_temp.chk('A6. exactly one cash line, the supplier payment', '1|-1000.00',
            (SELECT COUNT(*)::text || '|' || SUM(ct.amount)::text FROM poultrycashtransactions ct
             JOIN poultrysupplierpayments sp ON sp.poultrysupplierpaymentid = ct.sourceid
             WHERE ct.farmid = v_farm AND ct.sourcetype = 'PoultrySupplierPayment'
               AND sp.poultrysupplierpaymentid = (SELECT poultrysupplierpaymentid FROM poultrypurchasereceipts WHERE poultrypurchasereceiptid = r_a)));
    f := f + pg_temp.chk('A7. no purchase-level cash line (no double cash)', '0',
            (SELECT COUNT(*)::text FROM poultrycashtransactions WHERE farmid = v_farm AND sourcetype = 'RawMaterialPurchase'));
    f := f + pg_temp.chk('A8. expense booked once, = paid', '1|1000.00',
            (SELECT COUNT(*)::text || '|' || SUM(amount)::text FROM expense
             WHERE farmid = v_gid AND sourcetype = 'PoultryRawMaterialPurchase' AND sourceid = v_lot));
    f := f + pg_temp.chk('A9. payment sourcetype', 'ReceivePurchase',
            (SELECT sp.sourcetype FROM poultrysupplierpayments sp JOIN poultrypurchasereceipts r ON r.poultrysupplierpaymentid = sp.poultrysupplierpaymentid WHERE r.poultrypurchasereceiptid = r_a));
    f := f + pg_temp.chk('A10. receipt status', 'Paid|0.00|RCV-00001',
            (SELECT paymentstatus || '|' || balance::text || '|' || receiptnumber FROM sppoultrypurchasereceipt_getall(v_farm, NULL, NULL, NULL, r_a)));
    f := f + pg_temp.chk('A11. nothing payable', '0',
            (SELECT COUNT(*)::text FROM fnpoultrypayables(v_farm) WHERE balance > 0));
    f := f + pg_temp.chk('A12. cash flow out = 1000 exactly (expense arm only)', '1000.00',
            (SELECT SUM(-amount)::numeric(14,2)::text FROM sppoultrycashflow_rows(v_farm, NULL, NULL) WHERE amount < 0));

    -- ============================================================ B. credit
    r_b := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, 'INV-B1', v_today + 14, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 5, 100)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
    SELECT rl.poultryrawmaterialpurchaseid INTO v_lot2 FROM poultrypurchasereceiptlines rl WHERE rl.poultrypurchasereceiptid = r_b;
    f := f + pg_temp.chk('B1. payable = total', '500.00',
            (SELECT balance::text FROM fnpoultrypayables(v_farm) WHERE documentid = v_lot2 AND documenttype = 'RawMaterialPurchase'));
    f := f + pg_temp.chk('B2. payable carries the receipt due date', (v_today + 14)::text,
            (SELECT duedate::text FROM fnpoultrypayables(v_farm) WHERE documentid = v_lot2 AND documenttype = 'RawMaterialPurchase'));
    f := f + pg_temp.chk('B3. payable referenced by receipt number', 'RCV-00002',
            (SELECT reference FROM fnpoultrypayables(v_farm) WHERE documentid = v_lot2 AND documenttype = 'RawMaterialPurchase'));
    f := f + pg_temp.chk('B4. no cash moved', '99000.00',
            (SELECT currentbalance::text FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct));
    f := f + pg_temp.chk('B5. no expense yet', '0',
            (SELECT COUNT(*)::text FROM expense WHERE farmid = v_gid AND sourceid = v_lot2 AND sourcetype = 'PoultryRawMaterialPurchase'));
    f := f + pg_temp.chk('B6. no payment created', 'Unpaid|',
            (SELECT paymentstatus || '|' || COALESCE(poultrysupplierpaymentid::text, '') FROM sppoultrypurchasereceipt_getall(v_farm, NULL, NULL, NULL, r_b)));
    f := f + pg_temp.chk('B7. stock raised', '15.000',
            (SELECT currentquantity::numeric(14,3)::text FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = i_ewp));

    -- =========================================== C. part payment 10,000 / 4,000
    r_c := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, 'INV-C1', v_today + 30, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 100, 100)), 0, NULL, 4000, 'MoMo', v_acct, NULL, 'tester');
    SELECT rl.poultryrawmaterialpurchaseid INTO v_lot FROM poultrypurchasereceiptlines rl WHERE rl.poultrypurchasereceiptid = r_c;
    f := f + pg_temp.chk('C1. receipt 10000 / paid 4000 / balance 6000', '10000.00|4000.00|6000.00|Part paid',
            (SELECT totalcost::text || '|' || amountpaid::text || '|' || balance::text || '|' || paymentstatus
             FROM sppoultrypurchasereceipt_getall(v_farm, NULL, NULL, NULL, r_c)));
    f := f + pg_temp.chk('C2. payable 6000', '6000.00',
            (SELECT balance::text FROM fnpoultrypayables(v_farm) WHERE documentid = v_lot AND documenttype = 'RawMaterialPurchase'));
    f := f + pg_temp.chk('C3. cash down 4000 more', '95000.00',
            (SELECT currentbalance::text FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct));
    f := f + pg_temp.chk('C4. expense = 4000 (cash-basis, the rest when paid)', '4000.00',
            (SELECT SUM(amount)::text FROM expense WHERE farmid = v_gid AND sourceid = v_lot AND sourcetype = 'PoultryRawMaterialPurchase'));

    -- Settle the 6000 from Supplier Balances -- the existing path, untouched.
    v_pay := sppoultrysupplierpayment_record(v_farm, v_sup, 6000,
               jsonb_build_array(jsonb_build_object('documenttype', 'RawMaterialPurchase', 'documentid', v_lot, 'amount', 6000)),
               'Bank', v_today::timestamp, v_acct, 'SB-1', NULL, 'SupplierBalances', 'tester');
    f := f + pg_temp.chk('C5. now Paid', 'Paid|0.00|10000.00',
            (SELECT paymentstatus || '|' || balance::text || '|' || amountpaid::text FROM sppoultrypurchasereceipt_getall(v_farm, NULL, NULL, NULL, r_c)));
    f := f + pg_temp.chk('C6. total expense = invoice, never more', '10000.00',
            (SELECT SUM(amount)::text FROM expense WHERE farmid = v_gid AND sourceid = v_lot AND sourcetype = 'PoultryRawMaterialPurchase'));
    f := f + pg_temp.chk('C7. balance audit clean', '0',
            (SELECT COUNT(*)::text FROM fnbalanceaudit(v_farm, 'poultry')));

    -- ============================================ D. paid, consumption-based
    SELECT COALESCE(SUM(-r.amount) FILTER (WHERE r.amount < 0), 0) INTO v_cf0 FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r;
    r_d := sppoultrypurchasereceipt_post(v_farm, v_sup2, NULL, v_d, 'VET-1', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewc, 200, 10)), 0, NULL, 2000, 'Cash', v_acct, NULL, 'tester');
    SELECT rl.poultryrawmaterialpurchaseid INTO v_lot FROM poultrypurchasereceiptlines rl WHERE rl.poultrypurchasereceiptid = r_d;
    f := f + pg_temp.chk('D1. lot deferred', 'EXPENSE_WHEN_CONSUMED|2000.00|2000.00',
            (SELECT costrecognitionmethod || '|' || deferredtotalcost::text || '|' || deferredremainingcost::text
             FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot));
    f := f + pg_temp.chk('D2. NO expense on purchase or on payment', '0',
            (SELECT COUNT(*)::text FROM expense WHERE farmid = v_gid AND sourceid = v_lot));
    f := f + pg_temp.chk('D3. cash still moved (95000 - 6000 settle - 2000)', '87000.00',
            (SELECT currentbalance::text FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct));
    f := f + pg_temp.chk('D4. awaiting P&L', 'Not yet expensed|2000.00',
            (SELECT status || '|' || deferredremainingcost::text FROM fnpoultrydeferredpurchase_rows(v_farm) WHERE poultryrawmaterialpurchaseid = v_lot));
    f := f + pg_temp.chk('D5. (346) Cash Flow shows the 2000 once', '2000.00|1',
            (SELECT SUM(-amount)::numeric(14,2)::text || '|' || COUNT(*)::text FROM sppoultrycashflow_rows(v_farm, NULL, NULL)
             WHERE rowsource IN ('InventoryPurchase', 'InventoryPurchasePayment') AND sourceid = v_lot));
    f := f + pg_temp.chk('D6. Cash Flow out rose by exactly 2000', '2000.00',
            ((SELECT COALESCE(SUM(-r.amount) FILTER (WHERE r.amount < 0), 0) FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r) - v_cf0)::numeric(14,2)::text);
    f := f + pg_temp.chk('D7. detail buckets it under RawMaterialPurchase', 'RawMaterialPurchase',
            (SELECT DISTINCT category FROM sppoultrycashflow_detail(v_farm, NULL, NULL) WHERE rowsource = 'InventoryPurchasePayment'));

    -- ============================================== E. mixed invoice, part paid
    SELECT COALESCE(SUM(-r.amount) FILTER (WHERE r.amount < 0), 0) INTO v_cf0 FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r;
    SELECT currentbalance INTO v_cash0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    r_e := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, 'INV-E1', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 3, 100), pg_temp.ln(i_ewc, 70, 10)), 0, NULL, 500, 'Cash', v_acct, NULL, 'tester');
    f := f + pg_temp.chk('E1. allocation fills line 1 then line 2', '300.00|200.00',
            (SELECT string_agg(sa.amountapplied::text, '|' ORDER BY rl.lineno)
             FROM poultrypurchasereceiptlines rl
             JOIN supplierpaymentallocation sa ON sa.documentid = rl.poultryrawmaterialpurchaseid AND sa.documenttype = 'RawMaterialPurchase' AND sa.status = 'Posted'
             WHERE rl.poultrypurchasereceiptid = r_e));
    f := f + pg_temp.chk('E2. expense only for the purchase-based line', '300.00',
            (SELECT COALESCE(SUM(e.amount), 0)::text FROM expense e
             JOIN poultrypurchasereceiptlines rl ON rl.poultryrawmaterialpurchaseid = e.sourceid
             WHERE e.farmid = v_gid AND e.sourcetype = 'PoultryRawMaterialPurchase' AND rl.poultrypurchasereceiptid = r_e));
    f := f + pg_temp.chk('E3. cash down 500', '500.00', (v_cash0 - (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct))::text);
    f := f + pg_temp.chk('E4. Cash Flow out rose by exactly 500 (300 expense + 200 deferred)', '500.00',
            ((SELECT COALESCE(SUM(-r.amount) FILTER (WHERE r.amount < 0), 0) FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r) - v_cf0)::numeric(14,2)::text);
    f := f + pg_temp.chk('E5. split shown on the receipt', '300.00|700.00',
            (SELECT expensedatpurchasecost::text || '|' || deferredcost::text FROM sppoultrypurchasereceipt_getall(v_farm, NULL, NULL, NULL, r_e)));
    f := f + pg_temp.chk('E6. balance 500', '500.00',
            (SELECT balance::text FROM sppoultrypurchasereceipt_getall(v_farm, NULL, NULL, NULL, r_e)));

    -- ========================================================= F. additional costs
    r_f := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, 'INV-F1', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_fifo, 10, 100), pg_temp.ln(i_fifo, 30, 100)), 100, 'Transport', 0, NULL, NULL, NULL, 'tester');
    f := f + pg_temp.chk('F1. 100 spread 25/75 by value', '25.00|75.00',
            (SELECT string_agg(allocatedadditionalcost::text, '|' ORDER BY lineno) FROM poultrypurchasereceiptlines WHERE poultrypurchasereceiptid = r_f));
    f := f + pg_temp.chk('F2. lots carry landed totals', '1025.00|3075.00',
            (SELECT string_agg(pu.totalcost::text, '|' ORDER BY rl.lineno) FROM poultrypurchasereceiptlines rl
             JOIN poultryrawmaterialpurchases pu ON pu.poultryrawmaterialpurchaseid = rl.poultryrawmaterialpurchaseid WHERE rl.poultrypurchasereceiptid = r_f));
    f := f + pg_temp.chk('F3. landed unit cost', '102.50|102.50',
            (SELECT string_agg(pu.unitcost::text, '|' ORDER BY rl.lineno) FROM poultrypurchasereceiptlines rl
             JOIN poultryrawmaterialpurchases pu ON pu.poultryrawmaterialpurchaseid = rl.poultryrawmaterialpurchaseid WHERE rl.poultrypurchasereceiptid = r_f));
    f := f + pg_temp.chk('F4. sum of lots = receipt total exactly', '4100.00|4100.00',
            (SELECT (SELECT totalcost::text FROM poultrypurchasereceipts WHERE poultrypurchasereceiptid = r_f) || '|' || SUM(pu.totalcost)::text
             FROM poultrypurchasereceiptlines rl JOIN poultryrawmaterialpurchases pu ON pu.poultryrawmaterialpurchaseid = rl.poultryrawmaterialpurchaseid
             WHERE rl.poultrypurchasereceiptid = r_f));
    -- pennies: 0.10 over three equal lines -> 0.03, 0.03, 0.04
    v_rid := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, 'INV-F2', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_fifo, 1, 1), pg_temp.ln(i_fifo, 1, 1), pg_temp.ln(i_fifo, 1, 1)), 0.10, NULL, 0, NULL, NULL, NULL, 'tester');
    f := f + pg_temp.chk('F5. rounding pennies go to the last line', '0.03|0.03|0.04',
            (SELECT string_agg(allocatedadditionalcost::text, '|' ORDER BY lineno) FROM poultrypurchasereceiptlines WHERE poultrypurchasereceiptid = v_rid));
    -- free goods with a delivery charge: weighted by quantity
    v_rid := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, 'INV-F3', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_fifo, 1, 0), pg_temp.ln(i_fifo, 3, 0)), 40, NULL, 0, NULL, NULL, NULL, 'tester');
    f := f + pg_temp.chk('F6. free lines share by quantity', '10.00|30.00',
            (SELECT string_agg(allocatedadditionalcost::text, '|' ORDER BY lineno) FROM poultrypurchasereceiptlines WHERE poultrypurchasereceiptid = v_rid));

    -- ======================================================= G. FIFO / LIFO / HIFO
    -- Two receipts per item: older @ 100, newer @ 120. Then draw 5.
    r_g1 := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d - interval '1 day', 'INV-G1', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_lifo, 10, 100), pg_temp.ln(i_hifo, 10, 100)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
    r_g2 := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, 'INV-G2', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_lifo, 10, 120), pg_temp.ln(i_hifo, 10, 120)), 0, NULL, 0, NULL, NULL, NULL, 'tester');

    INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, quantityused, unitcost, notes, createdby)
    VALUES (v_farm, i_fifo, 5, 0, 'test draw', 'tester') RETURNING poultryrawmaterialusageid INTO v_use;
    f := f + pg_temp.chk('G1. FIFO draws the oldest receipt lot (landed 102.50)', '102.5000',
            (SELECT sppoultryrawmaterialitem_consumebatches(v_farm, i_fifo, v_use, 5)::numeric(14,4)::text));
    INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, quantityused, unitcost, notes, createdby)
    VALUES (v_farm, i_lifo, 5, 0, 'test draw', 'tester') RETURNING poultryrawmaterialusageid INTO v_use;
    f := f + pg_temp.chk('G2. LIFO draws the newest receipt lot', '120.0000',
            (SELECT sppoultryrawmaterialitem_consumebatches(v_farm, i_lifo, v_use, 5)::numeric(14,4)::text));
    INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, quantityused, unitcost, notes, createdby)
    VALUES (v_farm, i_hifo, 5, 0, 'test draw', 'tester') RETURNING poultryrawmaterialusageid INTO v_use;
    f := f + pg_temp.chk('G3. HIFO draws the dearest receipt lot', '120.0000',
            (SELECT sppoultryrawmaterialitem_consumebatches(v_farm, i_hifo, v_use, 5)::numeric(14,4)::text));
    UPDATE poultryrawmaterialitems SET currentquantity = currentquantity - 5
    WHERE  poultryrawmaterialitemid IN (i_fifo, i_lifo, i_hifo);   -- what the usage service does alongside the draw

    -- ================================== H. supplier balance, value, no double count
    -- Open for v_sup: B 500 + E 500 + F 4100 + F2 3.10 + F3 40 + G1 2000 + G2 2400 = 9543.10
    f := f + pg_temp.chk('H1. supplier balance = sum of open receipts', '9543.10',
            (SELECT SUM(totalbalance)::text FROM sppoultrysupplierbalances(v_farm, NULL, NULL, v_sup)));
    f := f + pg_temp.chk('H2. receipts balance agrees with payables', '9543.10',
            (SELECT SUM(balance)::text FROM sppoultrypurchasereceipt_getall(v_farm) WHERE supplierid = v_sup));
    f := f + pg_temp.chk('H3. inventory value (deferred item) = remaining deferred', '2700.00',
            (SELECT deferredvalue::text FROM fnpoultryinventoryvaluation(v_farm) WHERE poultryrawmaterialitemid = i_ewc));
    f := f + pg_temp.chk('H4. stock agrees with purchases-usage+adjustments', '0',
            (SELECT COUNT(*)::text FROM sppoultryrawmaterialitem_recalculatestock(v_farm, NULL) WHERE delta <> 0));
    f := f + pg_temp.chk('H5. cost-layer audit clean', '0',
            (SELECT COUNT(*)::text FROM fnpoultrycostlayeraudit(v_farm)));
    f := f + pg_temp.chk('H6. total expense = paid on purchase-based lines only (1000+4000+6000+300)', '11300.00',
            (SELECT SUM(amount)::text FROM expense WHERE farmid = v_gid));
    f := f + pg_temp.chk('H7. total cash out = total paid (1000+4000+6000+2000+500)', '13500.00',
            (100000 - (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct))::text);
    f := f + pg_temp.chk('H8. Cash Flow out = cash ledger out', '13500.00',
            (SELECT SUM(-amount)::numeric(14,2)::text FROM sppoultrycashflow_rows(v_farm, NULL, NULL) WHERE amount < 0));

    -- ======================================== I. reversal, paid purchase-based (A)
    SELECT rl.poultryrawmaterialpurchaseid INTO v_lot FROM poultrypurchasereceiptlines rl WHERE rl.poultrypurchasereceiptid = r_a;
    SELECT currentbalance INTO v_cash0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    f := f + pg_temp.chk('I0. nothing blocks it', NULL,
            (SELECT reversalblocker FROM sppoultrypurchasereceipt_getall(v_farm, NULL, NULL, NULL, r_a)));
    f := f + pg_temp.chk('I1. reverse returns lines reversed', '1',
            sppoultrypurchasereceipt_reverse(v_farm, r_a, 'entered against the wrong supplier', 'tester')::text);
    f := f + pg_temp.chk('I2. receipt Reversed, nothing owed', 'Reversed|Reversed|0.00',
            (SELECT status || '|' || paymentstatus || '|' || balance::text FROM sppoultrypurchasereceipt_getall(v_farm, NULL, NULL, NULL, r_a)));
    f := f + pg_temp.chk('I3. lot KEPT, emptied, stamped', '1|0.000|true',
            (SELECT COUNT(*)::text || '|' || MAX(remainingquantity)::numeric(14,3)::text || '|' || bool_and(reversedat IS NOT NULL)::text
             FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot));
    f := f + pg_temp.chk('I4. opposite stock adjustment written', '-10.000|PurchaseReceiptReversal',
            (SELECT a.quantity::numeric(14,3)::text || '|' || a.movementtype FROM poultryrawmaterialadjustments a
             JOIN poultrypurchasereceiptlines rl ON rl.reversaladjustmentid = a.poultryrawmaterialadjustmentid
             WHERE rl.poultrypurchasereceiptid = r_a));
    f := f + pg_temp.chk('I5. cash restored', '1000.00',
            ((SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) - v_cash0)::text);
    f := f + pg_temp.chk('I6. payment Reversed, header + allocation kept', 'Reversed|Reversed',
            (SELECT sp.status || '|' || sa.status FROM poultrysupplierpayments sp
             JOIN supplierpaymentallocation sa ON sa.paymentid = sp.poultrysupplierpaymentid AND sa.module = 'poultry'
             WHERE sp.poultrysupplierpaymentid = (SELECT poultrysupplierpaymentid FROM poultrypurchasereceipts WHERE poultrypurchasereceiptid = r_a)));
    f := f + pg_temp.chk('I7. its expense removed (207: no negative expense rows)', '0',
            (SELECT COUNT(*)::text FROM expense WHERE farmid = v_gid AND sourceid = v_lot AND sourcetype = 'PoultryRawMaterialPurchase'));
    f := f + pg_temp.chk('I8. not a payable', '0',
            (SELECT COUNT(*)::text FROM fnpoultrypayables(v_farm) WHERE documentid = v_lot AND documenttype = 'RawMaterialPurchase'));
    f := f + pg_temp.chk('I9. purchase history shows it reversed with no balance', 'true|0.00|Reversed|RCV-00001',
            (SELECT isreversed::text || '|' || balance::text || '|' || costrecognitionstatus || '|' || receiptnumber
             FROM sppoultryrawmaterialpurchase_getall(v_farm, NULL, NULL) WHERE poultryrawmaterialpurchaseid = v_lot));
    f := f + pg_temp.chk('I10. stock still reconciles', '0',
            (SELECT COUNT(*)::text FROM sppoultryrawmaterialitem_recalculatestock(v_farm, NULL) WHERE delta <> 0));
    f := f + pg_temp.chk('I11. audits clean', '0|0',
            (SELECT (SELECT COUNT(*) FROM fnpoultrycostlayeraudit(v_farm))::text || '|' || (SELECT COUNT(*) FROM fnbalanceaudit(v_farm, 'poultry'))::text));
    f := f + pg_temp.chk('I12. closing report period purchases exclude it', 'true',
            ((SELECT totalrawmaterialpurchases FROM sppoultryclosingreport_get(v_farm, v_today - 30, v_today))
             = (SELECT SUM(totalcost) FROM poultryrawmaterialpurchases WHERE farmid = v_farm AND reversedat IS NULL))::text);
    BEGIN
        PERFORM sppoultrypurchasereceipt_reverse(v_farm, r_a, 'again', 'tester');
        f := f + pg_temp.chk('I13. second reversal refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.chk_like('I13. second reversal refused', '%already reversed%', SQLERRM);
    END;
    BEGIN
        PERFORM sppoultrypurchasereceipt_reverse(v_farm, r_b, '   ', 'tester');
        f := f + pg_temp.chk('I14. reason required', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.chk_like('I14. reason required', '%reason%', SQLERRM);
    END;

    -- ================================== J. reversal, consumption-based paid (D)
    SELECT rl.poultryrawmaterialpurchaseid INTO v_lot FROM poultrypurchasereceiptlines rl WHERE rl.poultrypurchasereceiptid = r_d;
    PERFORM sppoultrypurchasereceipt_reverse(v_farm, r_d, 'duplicate', 'tester');
    f := f + pg_temp.chk('J1. deferred lot no longer awaiting P&L', '0',
            (SELECT COUNT(*)::text FROM fnpoultrydeferredpurchase_rows(v_farm) WHERE poultryrawmaterialpurchaseid = v_lot));
    f := f + pg_temp.chk('J2. deferred cost released without an expense', '0.00|0',
            (SELECT deferredremainingcost::text || '|' || (SELECT COUNT(*) FROM expense WHERE farmid = v_gid AND sourceid = v_lot)::text
             FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot));
    f := f + pg_temp.chk('J3. its Cash Flow rows gone with the payment', '0',
            (SELECT COUNT(*)::text FROM sppoultrycashflow_rows(v_farm, NULL, NULL) WHERE rowsource LIKE 'InventoryPurchase%' AND sourceid = v_lot));
    f := f + pg_temp.chk('J4. Cash Flow still equals the ledger after reversals', 'true',
            ((SELECT SUM(-amount) FROM sppoultrycashflow_rows(v_farm, NULL, NULL) WHERE amount < 0)
             = (100000 - (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct)))::text);
    f := f + pg_temp.chk('J5. cost-layer audit clean', '0', (SELECT COUNT(*)::text FROM fnpoultrycostlayeraudit(v_farm)));

    -- ================================================= K. reversal blocked
    -- K1 consumed: G1's LIFO lot is the OLDER one, untouched; its HIFO lot too.
    --    G2's LIFO/HIFO lots were drawn.
    f := f + pg_temp.chk_like('K1. consumed lot blocks reversal', '%already been used%',
            (SELECT reversalblocker FROM sppoultrypurchasereceipt_getall(v_farm, NULL, NULL, NULL, r_g2)));
    BEGIN
        PERFORM sppoultrypurchasereceipt_reverse(v_farm, r_g2, 'test', 'tester');
        f := f + pg_temp.chk('K2. reverse raises on consumed', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.chk_like('K2. reverse raises on consumed', '%already been used%', SQLERRM);
    END;
    f := f + pg_temp.chk('K3. nothing changed by the refused reversal', 'Posted',
            (SELECT status FROM poultrypurchasereceipts WHERE poultrypurchasereceiptid = r_g2));

    -- K4 stock short: internal use took stock without drawing lots.
    r_k := sppoultrypurchasereceipt_post(v_farm, v_sup2, NULL, v_d, 'VET-K', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewc, 10, 10)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
    PERFORM sppoultryrawmaterialitem_adjust(v_farm, i_ewc, -(SELECT currentquantity - 5 FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = i_ewc), NULL, 'Decrease', 'test', 'tester');
    f := f + pg_temp.chk_like('K4. stock short blocks reversal', '%only 5%',
            (SELECT reversalblocker FROM sppoultrypurchasereceipt_getall(v_farm, NULL, NULL, NULL, r_k)));

    -- K5 another payment applied: credit receipt paid later from Supplier Balances.
    r_k2 := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, 'INV-K2', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 1, 50)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
    SELECT rl.poultryrawmaterialpurchaseid INTO v_lot FROM poultrypurchasereceiptlines rl WHERE rl.poultrypurchasereceiptid = r_k2;
    v_pay := sppoultrysupplierpayment_record(v_farm, v_sup, 50,
               jsonb_build_array(jsonb_build_object('documenttype', 'RawMaterialPurchase', 'documentid', v_lot, 'amount', 50)),
               'Cash', v_today::timestamp, v_acct, NULL, NULL, 'SupplierBalances', 'tester');
    f := f + pg_temp.chk_like('K5. later supplier payment blocks reversal', 'Supplier payment #' || v_pay || '%',
            (SELECT reversalblocker FROM sppoultrypurchasereceipt_getall(v_farm, NULL, NULL, NULL, r_k2)));
    PERFORM sppoultrysupplierpayment_reverse(v_farm, v_pay, 'test', 'tester');
    f := f + pg_temp.chk('K6. once that payment is reversed, it can be', NULL,
            (SELECT reversalblocker FROM sppoultrypurchasereceipt_getall(v_farm, NULL, NULL, NULL, r_k2)));

    -- K7 reconciled payment.
    r_k3 := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, 'INV-K3', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 1, 70)), 0, NULL, 70, 'Cash', v_acct, NULL, 'tester');
    UPDATE poultrycashtransactions SET clearingstatus = 'Cleared'
    WHERE  farmid = v_farm AND sourcetype = 'PoultrySupplierPayment'
      AND  sourceid = (SELECT poultrysupplierpaymentid FROM poultrypurchasereceipts WHERE poultrypurchasereceiptid = r_k3);
    f := f + pg_temp.chk_like('K7. reconciled payment blocks reversal', '%cash reconciliation%',
            (SELECT reversalblocker FROM sppoultrypurchasereceipt_getall(v_farm, NULL, NULL, NULL, r_k3)));

    -- ============================================== L. duplicate prevention
    r_l := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, 'INV-L1', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 2, 10)), 0, NULL, 0, NULL, NULL, v_req, 'tester');
    SELECT COUNT(*) INTO v_n FROM poultryrawmaterialpurchases WHERE farmid = v_farm;
    f := f + pg_temp.chk('L1. same request id returns the same receipt', r_l::text,
            sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, 'INV-L1', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 2, 10)), 0, NULL, 0, NULL, NULL, v_req, 'tester')::text);
    f := f + pg_temp.chk('L2. ... and creates no second lot', v_n::text,
            (SELECT COUNT(*)::text FROM poultryrawmaterialpurchases WHERE farmid = v_farm));
    BEGIN
        PERFORM sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, '  inv-l1 ', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 2, 10)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
        f := f + pg_temp.chk('L3. same invoice ref (case/space) refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.chk_like('L3. same invoice ref (case/space) refused', '%already received as RCV-%', SQLERRM);
    END;
    v_rid := sppoultrypurchasereceipt_post(v_farm, v_sup2, NULL, v_d, 'INV-L1', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 1, 10)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
    f := f + pg_temp.chk('L4. same ref from a DIFFERENT supplier is fine', 'true', (v_rid IS NOT NULL)::text);
    -- after reversing A, INV-A1 may be received again
    v_rid := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, 'INV-A1', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 1, 10)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
    f := f + pg_temp.chk('L5. a reversed invoice can be received again', 'true', (v_rid IS NOT NULL)::text);

    SELECT rl.poultryrawmaterialpurchaseid INTO v_lot FROM poultrypurchasereceiptlines rl WHERE rl.poultrypurchasereceiptid = r_l;
    BEGIN
        UPDATE poultryrawmaterialpurchases SET quantity = 99 WHERE poultryrawmaterialpurchaseid = v_lot;
        f := f + pg_temp.chk('L6. a receipt lot cannot be edited directly', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.chk_like('L6. a receipt lot cannot be edited directly', '%belongs to purchase receipt RCV-%', SQLERRM);
    END;
    BEGIN
        PERFORM sppoultryrawmaterialpurchase_update(v_lot, v_farm, 'ZZ Feed Mill Ltd', v_sup, v_d, 2, 15, 30, NULL, NULL, 'Credit', 0, NULL, NULL);
        f := f + pg_temp.chk('L7. ... nor through the Raw Materials update', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.chk_like('L7. ... nor through the Raw Materials update', '%belongs to purchase receipt%', SQLERRM);
    END;
    BEGIN
        PERFORM sppoultryrawmaterialpurchase_delete(v_lot, v_farm);
        f := f + pg_temp.chk('L8. ... nor deleted', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.chk_like('L8. ... nor deleted', '%foreign key%', SQLERRM);
    END;
    UPDATE poultryrawmaterialpurchases SET remainingquantity = remainingquantity, amountpaid = amountpaid
    WHERE  poultryrawmaterialpurchaseid = v_lot;
    f := f + pg_temp.chk('L9. draws/payments may still update the lot', 'ok', 'ok');

    -- ================================================================ M. validation
    BEGIN
        PERFORM sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, (v_today + 1)::timestamp, NULL, NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 1, 10)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
        f := f + pg_temp.chk('M1. future date refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('M1. future date refused', '%future%', SQLERRM);
    END;
    BEGIN
        PERFORM sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, NULL, NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 1, 10)), 0, NULL, 11, 'Cash', v_acct, NULL, 'tester');
        f := f + pg_temp.chk('M2. overpayment refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('M2. overpayment refused', '%more than the purchase total%', SQLERRM);
    END;
    BEGIN
        PERFORM sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, NULL, NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 1, 10)), 0, NULL, 5, 'Cash', NULL, NULL, 'tester');
        f := f + pg_temp.chk('M3. payment without cash account refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('M3. payment without cash account refused', '%cash account%', SQLERRM);
    END;
    BEGIN
        PERFORM sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, NULL, NULL, NULL,
              '[]'::jsonb, 0, NULL, 0, NULL, NULL, NULL, 'tester');
        f := f + pg_temp.chk('M4. empty receipt refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('M4. empty receipt refused', '%at least one item%', SQLERRM);
    END;
    BEGIN
        PERFORM sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, NULL, (v_d - interval '2 days')::date, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 1, 10)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
        f := f + pg_temp.chk('M5. due before purchase refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('M5. due before purchase refused', '%due date%', SQLERRM);
    END;
    BEGIN
        PERFORM sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, NULL, NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 0, 10)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
        f := f + pg_temp.chk('M6. zero quantity refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('M6. zero quantity refused', '%quantity%', SQLERRM);
    END;
    SELECT COUNT(*) INTO v_n FROM poultrypurchasereceipts WHERE farmid = v_farm;
    BEGIN
        PERFORM sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, 'INV-OD', NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 10, 100)), 0, NULL, 1000, 'Cash', v_acct2, NULL, 'tester');
        f := f + pg_temp.chk('M7. overdraft refused (existing payment guard)', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('M7. overdraft refused (existing payment guard)', '%overdraw%', SQLERRM);
    END;
    f := f + pg_temp.chk('M8. ... and left no half-received receipt behind', v_n::text,
            (SELECT COUNT(*)::text FROM poultrypurchasereceipts WHERE farmid = v_farm));
    v_rid := sppoultrypurchasereceipt_post(v_farm, NULL, 'ZZ Brand New Supplier', v_d, NULL, NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 1, 10)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
    f := f + pg_temp.chk('M9. a typed supplier name is resolved to a record', 'ZZ Brand New Supplier',
            (SELECT s.name FROM poultrypurchasereceipts r JOIN supplier s ON s.supplierid = r.supplierid WHERE r.poultrypurchasereceiptid = v_rid));
    v_rid := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, NULL, v_today + 5, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 1, 10)), 0, NULL, 10, 'Cash', v_acct, NULL, 'tester');
    f := f + pg_temp.chk('M10. fully paid drops the due date', NULL,
            (SELECT duedate::text FROM poultrypurchasereceipts WHERE poultrypurchasereceiptid = v_rid));
    v_rid := sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, NULL, NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 2, 50, 'kg', 25)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
    f := f + pg_temp.chk('M11. bags convert to production units (2 bags x 25 kg)', '50.000',
            (SELECT productionquantity::numeric(14,3)::text FROM sppoultrypurchasereceipt_getlines(v_farm, v_rid)));

    -- ======================================================= N. company isolation
    BEGIN
        PERFORM sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, NULL, NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_other, 1, 10)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
        f := f + pg_temp.chk('N1. another company''s item refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('N1. another company''s item refused', '%does not belong%', SQLERRM);
    END;
    BEGIN
        PERFORM sppoultrypurchasereceipt_post(v_farm, v_osup, NULL, v_d, NULL, NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 1, 10)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
        f := f + pg_temp.chk('N2. another company''s supplier refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('N2. another company''s supplier refused', '%does not belong%', SQLERRM);
    END;
    BEGIN
        PERFORM sppoultrypurchasereceipt_post(v_farm, v_sup, NULL, v_d, NULL, NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_ewp, 1, 10)), 0, NULL, 10, 'Cash', v_oacct, NULL, 'tester');
        f := f + pg_temp.chk('N3. another company''s cash account refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('N3. another company''s cash account refused', '%does not belong%', SQLERRM);
    END;
    f := f + pg_temp.chk('N4. other company sees none of these receipts', '0',
            (SELECT COUNT(*)::text FROM sppoultrypurchasereceipt_getall(v_other)));
    f := f + pg_temp.chk('N5. ... nor their lines', '0',
            (SELECT COUNT(*)::text FROM sppoultrypurchasereceipt_getlines(v_other, r_b)));
    BEGIN
        PERFORM sppoultrypurchasereceipt_reverse(v_other, r_b, 'not mine', 'tester');
        f := f + pg_temp.chk('N6. cannot reverse another company''s receipt', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('N6. cannot reverse another company''s receipt', '%not found%', SQLERRM);
    END;
    INSERT INTO farms (id, farmid, name, email, type) VALUES (gen_random_uuid()::text, v_other, 'ZZ Water Co', 'zz@example.com', 'Water');
    BEGIN
        PERFORM sppoultrypurchasereceipt_post(v_other, v_osup, NULL, v_d, NULL, NULL, NULL,
              jsonb_build_array(pg_temp.ln(i_other, 1, 10)), 0, NULL, 0, NULL, NULL, NULL, 'tester');
        f := f + pg_temp.chk('N7. a Water company cannot use it', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('N7. a Water company cannot use it', '%only available for Poultry%', SQLERRM);
    END;

    -- ================================================================ O. permissions
    IF to_regclass('public.iampermissions') IS NOT NULL THEN
        f := f + pg_temp.chk('O1. three catalog keys', '3',
                (SELECT COUNT(*)::text FROM iampermissions WHERE permissionkey LIKE 'poultry.purchase-receipts.%'));
        f := f + pg_temp.chk('O2. approve (reverse) flagged dangerous', 'true',
                (SELECT isdangerous::text FROM iampermissions WHERE permissionkey = 'poultry.purchase-receipts.approve'));
        f := f + pg_temp.chk('O3. every role that can buy raw materials can receive', 'true',
                (NOT EXISTS (SELECT 1 FROM iamrolepermissions rp WHERE rp.permissionkey = 'poultry.raw-materials.create'
                              AND NOT EXISTS (SELECT 1 FROM iamrolepermissions r2 WHERE r2.roleid = rp.roleid
                                              AND r2.permissionkey = 'poultry.purchase-receipts.create')))::text);
    END IF;

    IF f > 0 THEN
        RAISE EXCEPTION 'poultry-receive-purchase: % check(s) FAILED', f;
    END IF;
    RAISE NOTICE 'poultry-receive-purchase: all checks passed';
END $t$;

ROLLBACK;

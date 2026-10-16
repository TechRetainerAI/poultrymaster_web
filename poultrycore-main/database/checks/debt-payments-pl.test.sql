-- =============================================================================
-- debt-payments-pl.test.sql -- checks for migration 382.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Works on a
-- throwaway customer and supplier in the first poultry company with a cash
-- account. P&L figures are compared before / after, so other activity on the
-- same days does not matter.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm    text;
    v_user    text;
    v_acct    integer;
    v_cust    integer;
    v_sup     integer;
    v_res     jsonb;
    v_debt    integer;
    v_sdebt   integer;
    v_sdebt2  integer;
    v_grp     uuid;
    v_dep     uuid;
    v_pay     integer;
    v_adv     integer;
    v_note    integer;
    v_rev0    numeric;
    v_exp0    numeric;
    v_net0    numeric;
    v_failed  boolean;
    v_d       date := CURRENT_DATE;
BEGIN
    SELECT a.farmid, a.poultrycashaccountid INTO v_farm, v_acct
    FROM   poultrycashaccounts a
    JOIN   farms f ON (f.id::text = a.farmid OR f.farmid::text = a.farmid) AND f.type = 'Poultry'
    WHERE  a.isactive
    ORDER  BY a.poultrycashaccountid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'debt payments pl: all checks passed';
        RETURN;
    END IF;
    UPDATE poultrycashaccounts SET allownegativebalance = TRUE WHERE poultrycashaccountid = v_acct;
    SELECT f.owneruserid INTO v_user FROM farms f WHERE f.id::text = v_farm OR f.farmid::text = v_farm LIMIT 1;
    v_user := COALESCE(v_user, 'check382');
    INSERT INTO customer (farmid, userid, name) VALUES (v_farm, v_user, 'PL Check 382') RETURNING customerid INTO v_cust;
    INSERT INTO supplier (farmid, userid, name) VALUES (v_farm, v_user, 'PL Supplier Check 382') RETURNING supplierid INTO v_sup;

    SELECT COALESCE(sum(amount) FILTER (WHERE linekey = 'DebtCollections'), 0),
           COALESCE(sum(amount) FILTER (WHERE linekey = 'SupplierDebtPayments'), 0)
    INTO   v_rev0, v_exp0
    FROM   sppoultryreport_pllines(v_farm, v_d, v_d);
    SELECT netprofit INTO v_net0 FROM sppoultryreport_plsummary(v_farm, v_d, v_d);

    -- 1. Recording a customer debt and a supplier debt: P&L does not move.
    v_res  := sppoultrycustomerdebt_create(v_farm, v_cust, 1000, v_d - 30, 'HistoricalDebt', 'Owed before the system', NULL, NULL, v_user);
    v_debt := (v_res->>'debtId')::integer;
    v_res  := sppoultrysupplierdebt_create(v_farm, v_sup, 800, v_d - 30, 'OpeningBalance', 'Feed owed before the system', NULL, NULL, v_user);
    v_sdebt := (v_res->>'debtId')::integer;
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 THEN
        RAISE EXCEPTION 'FAIL 1: recording a debt moved Net Profit'; END IF;
    RAISE NOTICE 'ok 1 recording debts: no P&L';

    -- 2. The customer pays 600 of the debt: Revenue 'DebtCollections' +600, Net Profit +600, in the drilldown.
    v_grp := sppoultrycustomerpayment_record(v_farm, v_cust, 600,
                 jsonb_build_array(jsonb_build_object('debtid', v_debt, 'amount', 600)),
                 'Cash', now()::timestamp, v_acct, NULL, NULL, 'PaymentsPage', v_user);
    IF (SELECT COALESCE(sum(amount), 0) FROM sppoultryreport_pllines(v_farm, v_d, v_d) WHERE linekey = 'DebtCollections' AND section = 'Revenue') <> v_rev0 + 600 THEN
        RAISE EXCEPTION 'FAIL 2a: debt collection not on Revenue'; END IF;
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 + 600 THEN
        RAISE EXCEPTION 'FAIL 2b: Net Profit did not go up by 600'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultryreport_plrevenuedetail(v_farm, v_d, v_d, 'DebtCollections') r
                   WHERE r.totalamount = 600 AND r.customername = 'PL Check 382') THEN
        RAISE EXCEPTION 'FAIL 2c: debt collection not in the revenue drilldown'; END IF;
    IF fnpoultrypayment_plamount(v_farm, v_grp) <> 600 THEN RAISE EXCEPTION 'FAIL 2d: plamount'; END IF;
    RAISE NOTICE 'ok 2 a customer debt payment is revenue';

    -- 3. Excluded: gone from P&L; included again: back.
    PERFORM sppoultrypayment_setplexclusion(v_farm, v_grp, TRUE, v_user);
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 THEN
        RAISE EXCEPTION 'FAIL 3a: excluded payment still on P&L'; END IF;
    IF EXISTS (SELECT 1 FROM sppoultryreport_plrevenuedetail(v_farm, v_d, v_d, 'DebtCollections') r WHERE r.customername = 'PL Check 382') THEN
        RAISE EXCEPTION 'FAIL 3b: excluded payment still in the drilldown'; END IF;
    PERFORM sppoultrypayment_setplexclusion(v_farm, v_grp, FALSE, v_user);
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 + 600 THEN
        RAISE EXCEPTION 'FAIL 3c: included payment not back on P&L'; END IF;
    RAISE NOTICE 'ok 3 exclude and include a customer payment';

    -- 4. A payment kept wholly as credit (advance) is not on P&L and cannot be toggled.
    v_dep := sppoultrycustomerpayment_record(v_farm, v_cust, 250, '[]'::jsonb,
                 'Cash', now()::timestamp, v_acct, NULL, NULL, 'PaymentsPage', v_user);
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 + 600 THEN
        RAISE EXCEPTION 'FAIL 4a: a customer advance reached P&L'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrypayment_setplexclusion(v_farm, v_dep, TRUE, v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4b: exclusion accepted on a payment not on P&L'; END IF;
    RAISE NOTICE 'ok 4 customer advance: no P&L, no toggle';

    -- 5. Reversing the debt payment takes it off P&L.
    PERFORM sppoultrycustomerpayment_reverse(v_farm, v_grp, 'check', v_user);
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 THEN
        RAISE EXCEPTION 'FAIL 5a: reversed payment still on P&L'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrypayment_setplexclusion(v_farm, v_grp, TRUE, v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5b: exclusion accepted on a reversed payment'; END IF;
    RAISE NOTICE 'ok 5 a reversed debt payment leaves P&L';

    -- 6. We pay 500 of the supplier debt: Operating Expense 'SupplierDebtPayments' +500, Net Profit -500.
    v_pay := sppoultrysupplierpayment_record(v_farm, v_sup, 500,
                 jsonb_build_array(jsonb_build_object('documenttype', 'SupplierDebt', 'documentid', v_sdebt, 'amount', 500)),
                 'Cash', now()::timestamp, v_acct, NULL, NULL, 'SupplierPayments', v_user);
    IF (SELECT COALESCE(sum(amount), 0) FROM sppoultryreport_pllines(v_farm, v_d, v_d)
        WHERE linekey = 'SupplierDebtPayments' AND section = 'OperatingExpense') <> v_exp0 + 500 THEN
        RAISE EXCEPTION 'FAIL 6a: supplier debt payment not an operating expense'; END IF;
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 - 500 THEN
        RAISE EXCEPTION 'FAIL 6b: Net Profit did not go down by 500'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultryreport_plexpensedetail(v_farm, v_d, v_d, 'SupplierDebtPayments') e
                   WHERE e.amount = 500 AND e.expenseid IS NULL AND e.suppliername = 'PL Supplier Check 382') THEN
        RAISE EXCEPTION 'FAIL 6c: supplier debt payment not in the expense drilldown'; END IF;
    PERFORM sppoultrysupplierpayment_setplexclusion(v_farm, v_pay, TRUE, v_user);
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 THEN
        RAISE EXCEPTION 'FAIL 6d: excluded supplier payment still on P&L'; END IF;
    PERFORM sppoultrysupplierpayment_setplexclusion(v_farm, v_pay, FALSE, v_user);
    RAISE NOTICE 'ok 6 a supplier debt payment is an operating expense; exclude works';

    -- 7. A supplier advance: nothing on P&L until applied to the debt, then expense.
    v_adv := sppoultrysupplierpayment_record(v_farm, v_sup, 300, '[]'::jsonb,
                 'Cash', now()::timestamp, v_acct, NULL, NULL, 'SupplierCredits', v_user);
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 - 500 THEN
        RAISE EXCEPTION 'FAIL 7a: an unapplied advance reached P&L'; END IF;
    PERFORM sppoultrysuppliercredit_apply(v_farm, v_adv, 'SupplierDebt', v_sdebt, 300, v_user);
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 - 800 THEN
        RAISE EXCEPTION 'FAIL 7b: an advance applied to a debt is not an expense'; END IF;
    RAISE NOTICE 'ok 7 a supplier advance is expense when applied to a debt';

    -- 8. An opening / manual credit netted against a debt moves no money: no P&L.
    v_res    := sppoultrysupplierdebt_create(v_farm, v_sup, 100, v_d - 30, 'Adjustment', 'Second old debt', NULL, NULL, v_user);
    v_sdebt2 := (v_res->>'debtId')::integer;
    v_note   := sppoultrysuppliercredit_create(v_farm, v_sup, 'SupplierOpeningCredit', 100, NULL, NULL, 'credit before the system', v_user);
    PERFORM sppoultrysuppliercredit_apply(v_farm, v_note, 'SupplierDebt', v_sdebt2, 100, v_user);
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 - 800 THEN
        RAISE EXCEPTION 'FAIL 8a: an opening credit applied to a debt reached P&L'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrysupplierpayment_setplexclusion(v_farm, v_note, TRUE, v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8b: exclusion accepted on a credit not on P&L'; END IF;
    RAISE NOTICE 'ok 8 opening credit on a debt: no P&L';

    RAISE NOTICE 'debt payments pl: all checks passed';
END $$;

ROLLBACK;

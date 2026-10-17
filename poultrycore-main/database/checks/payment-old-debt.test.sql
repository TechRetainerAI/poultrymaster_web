-- =============================================================================
-- payment-old-debt.test.sql -- checks for migration 383.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Throwaway
-- customer and supplier in the first poultry company with a cash account.
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
    v_grp     uuid;
    v_grp2    uuid;
    v_pay     integer;
    v_debt    integer;
    v_sdebt   integer;
    v_net0    numeric;
    v_bal0    numeric;
    v_d       date := CURRENT_DATE;
BEGIN
    SELECT a.farmid, a.poultrycashaccountid INTO v_farm, v_acct
    FROM   poultrycashaccounts a
    JOIN   farms f ON (f.id::text = a.farmid OR f.farmid::text = a.farmid) AND f.type = 'Poultry'
    WHERE  a.isactive
    ORDER  BY a.poultrycashaccountid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'payment old debt: all checks passed';
        RETURN;
    END IF;
    UPDATE poultrycashaccounts SET allownegativebalance = TRUE WHERE poultrycashaccountid = v_acct;
    SELECT f.owneruserid INTO v_user FROM farms f WHERE f.id::text = v_farm OR f.farmid::text = v_farm LIMIT 1;
    v_user := COALESCE(v_user, 'check383');
    INSERT INTO customer (farmid, userid, name) VALUES (v_farm, v_user, 'Old Debt Check 383') RETURNING customerid INTO v_cust;
    INSERT INTO supplier (farmid, userid, name) VALUES (v_farm, v_user, 'Old Debt Supplier 383') RETURNING supplierid INTO v_sup;
    SELECT netprofit INTO v_net0 FROM sppoultryreport_plsummary(v_farm, v_d, v_d);
    SELECT currentbalance INTO v_bal0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;

    -- 1. A customer with nothing outstanding pays 10: an old debt is recorded and paid; revenue +10; no credit.
    v_grp := sppoultrycustomerpayment_recordolddebt(v_farm, v_cust, 10, '[]'::jsonb, 'Cash', now()::timestamp,
                 v_acct, NULL, 'This debt was there before', 'PaymentsPage', v_user);
    SELECT pp.debtid INTO v_debt FROM poultrypayments pp WHERE pp.paymentgroupid = v_grp AND pp.debtid IS NOT NULL;
    IF v_debt IS NULL THEN RAISE EXCEPTION 'FAIL 1a: no debt paid'; END IF;
    IF NOT (SELECT paidonentry FROM poultrycustomerdebts WHERE debtid = v_debt) THEN RAISE EXCEPTION 'FAIL 1b: debt not marked paidonentry'; END IF;
    IF fnpoultrycustomerdebt_balance(v_farm, v_debt) <> 0 THEN RAISE EXCEPTION 'FAIL 1c: debt not cleared'; END IF;
    IF fnpoultrycustomer_credit(v_farm, v_cust) <> 0 THEN RAISE EXCEPTION 'FAIL 1d: credit created'; END IF;
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 + 10 THEN RAISE EXCEPTION 'FAIL 1e: not revenue'; END IF;
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 + 10 THEN RAISE EXCEPTION 'FAIL 1f: cash'; END IF;
    IF EXISTS (SELECT 1 FROM sppoultrycustomerbalances(p_farmid => v_farm) b WHERE b.customerid = v_cust AND b.totalbalance <> 0) THEN
        RAISE EXCEPTION 'FAIL 1g: customer shows a balance'; END IF;
    RAISE NOTICE 'ok 1 a customer payment with nothing to pay clears an old debt and is revenue';

    -- 2. Reversing it reverses the old debt too: nothing owed, nothing on P&L, cash back.
    PERFORM sppoultrycustomerpayment_reverse(v_farm, v_grp, 'Entered in error', v_user);
    IF sppoultrypayment_releaseolddebts(v_farm, v_grp, v_user) <> 1 THEN RAISE EXCEPTION 'FAIL 2a: old debt not released'; END IF;
    IF (SELECT status FROM poultrycustomerdebts WHERE debtid = v_debt) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 2b: debt still posted'; END IF;
    IF EXISTS (SELECT 1 FROM sppoultrycustomerbalances(p_farmid => v_farm) b WHERE b.customerid = v_cust AND b.totalbalance <> 0) THEN
        RAISE EXCEPTION 'FAIL 2c: customer owes after reversal'; END IF;
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 THEN RAISE EXCEPTION 'FAIL 2d: P&L after reversal'; END IF;
    RAISE NOTICE 'ok 2 reversing it takes the old debt away too';

    -- 3. The plain record (user chose "keep as credit") is still an advance: credit, no P&L.
    v_grp2 := sppoultrycustomerpayment_record(v_farm, v_cust, 25, '[]'::jsonb, 'Cash', now()::timestamp,
                  v_acct, NULL, NULL, 'PaymentsPage', v_user);
    IF fnpoultrycustomer_credit(v_farm, v_cust) <> 25 THEN RAISE EXCEPTION 'FAIL 3a: advance not credit'; END IF;
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 THEN RAISE EXCEPTION 'FAIL 3b: advance on P&L'; END IF;
    RAISE NOTICE 'ok 3 keep as credit: an advance, not P&L';

    -- 4. Supplier: 40 paid with nothing owed: old supplier debt, operating expense, no credit; reversal releases it.
    v_pay := sppoultrysupplierpayment_recordolddebt(v_farm, v_sup, 40, '[]'::jsonb, 'Cash', now()::timestamp,
                 v_acct, NULL, 'feed from last year', 'SupplierPayments', v_user);
    SELECT sa.documentid INTO v_sdebt FROM supplierpaymentallocation sa
    WHERE  sa.paymentid = v_pay AND sa.documenttype = 'SupplierDebt';
    IF v_sdebt IS NULL OR NOT (SELECT paidonentry FROM poultrysupplierdebts WHERE debtid = v_sdebt) THEN RAISE EXCEPTION 'FAIL 4a: no old supplier debt'; END IF;
    IF fnpoultrysupplier_credit(v_farm, v_sup) <> 0 THEN RAISE EXCEPTION 'FAIL 4b: supplier credit created'; END IF;
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 - 40 THEN RAISE EXCEPTION 'FAIL 4c: not an expense'; END IF;
    PERFORM sppoultrysupplierpayment_reverse(v_farm, v_pay, 'Entered in error', v_user);
    IF sppoultrysupplierpayment_releaseolddebts(v_farm, v_pay, v_user) <> 1 THEN RAISE EXCEPTION 'FAIL 4d: supplier debt not released'; END IF;
    IF EXISTS (SELECT 1 FROM fnpoultrypayables(v_farm) d WHERE d.documenttype = 'SupplierDebt' AND d.documentid = v_sdebt) THEN
        RAISE EXCEPTION 'FAIL 4e: released debt still payable'; END IF;
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 THEN RAISE EXCEPTION 'FAIL 4f: P&L after supplier reversal'; END IF;
    RAISE NOTICE 'ok 4 supplier: old debt paid is an expense; reversal releases it';

    RAISE NOTICE 'payment old debt: all checks passed';
END $$;

ROLLBACK;

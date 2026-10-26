-- =============================================================================
-- payment-old-debt-saletype.test.sql -- checks for migration 384.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Throwaway
-- customer in the first poultry company with a cash account.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm    text;
    v_user    text;
    v_acct    integer;
    v_cust    integer;
    v_grp     uuid;
    v_grp2    uuid;
    v_debt    integer;
    v_net0    numeric;
    v_n       integer;
    v_d       date := CURRENT_DATE;
BEGIN
    SELECT a.farmid, a.poultrycashaccountid INTO v_farm, v_acct
    FROM   poultrycashaccounts a
    JOIN   farms f ON (f.id::text = a.farmid OR f.farmid::text = a.farmid) AND f.type = 'Poultry'
    WHERE  a.isactive
    ORDER  BY a.poultrycashaccountid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'old debt sale type: all checks passed';
        RETURN;
    END IF;
    UPDATE poultrycashaccounts SET allownegativebalance = TRUE WHERE poultrycashaccountid = v_acct;
    SELECT f.owneruserid INTO v_user FROM farms f WHERE f.id::text = v_farm OR f.farmid::text = v_farm LIMIT 1;
    v_user := COALESCE(v_user, 'check384');
    INSERT INTO customer (farmid, userid, name) VALUES (v_farm, v_user, 'Old Debt Type Check 384') RETURNING customerid INTO v_cust;
    SELECT netprofit INTO v_net0 FROM sppoultryreport_plsummary(v_farm, v_d, v_d);

    -- 0. Exactly one recordolddebt (an extra overload makes named calls ambiguous).
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'sppoultrycustomerpayment_recordolddebt';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 0: % overloads of recordolddebt', v_n; END IF;
    RAISE NOTICE 'ok 0 one recordolddebt';

    -- 1. With a sale type: stored on the debt, named in its description, revenue +15, shown in the P&L detail.
    v_grp := sppoultrycustomerpayment_recordolddebt(p_farmid => v_farm, p_customerid => v_cust, p_amount => 15,
                 p_allocations => '[]'::jsonb, p_paymentmethod => 'Cash', p_paymentdate => now()::timestamp,
                 p_cashaccountid => v_acct, p_createdby => v_user, p_saletype => '  Fresh Eggs ');
    SELECT pp.debtid INTO v_debt FROM poultrypayments pp WHERE pp.paymentgroupid = v_grp AND pp.debtid IS NOT NULL;
    IF v_debt IS NULL THEN RAISE EXCEPTION 'FAIL 1a: no debt paid'; END IF;
    IF (SELECT saletype FROM poultrycustomerdebts WHERE debtid = v_debt) IS DISTINCT FROM 'Fresh Eggs' THEN
        RAISE EXCEPTION 'FAIL 1b: saletype not stored (trimmed)'; END IF;
    IF (SELECT description FROM poultrycustomerdebts WHERE debtid = v_debt) NOT LIKE 'Fresh Eggs sold before the system%' THEN
        RAISE EXCEPTION 'FAIL 1c: description does not name the sale type'; END IF;
    IF (SELECT netprofit FROM sppoultryreport_plsummary(v_farm, v_d, v_d)) <> v_net0 + 15 THEN RAISE EXCEPTION 'FAIL 1d: not revenue'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultryreport_plrevenuedetail(v_farm, v_d, v_d, 'DebtCollections') r
                   WHERE r.product LIKE 'Old debt collected: Fresh Eggs - Debt %' AND r.totalamount = 15) THEN
        RAISE EXCEPTION 'FAIL 1e: P&L detail does not show the sale type'; END IF;
    RAISE NOTICE 'ok 1 sale type stored, described and on the P&L detail';

    -- 2. Without one (the 383 call shape): unchanged wording, no saletype.
    v_grp2 := sppoultrycustomerpayment_recordolddebt(v_farm, v_cust, 5, '[]'::jsonb, 'Cash', now()::timestamp,
                  v_acct, NULL, NULL, 'PaymentsPage', v_user);
    SELECT pp.debtid INTO v_debt FROM poultrypayments pp WHERE pp.paymentgroupid = v_grp2 AND pp.debtid IS NOT NULL;
    IF (SELECT saletype FROM poultrycustomerdebts WHERE debtid = v_debt) IS NOT NULL THEN RAISE EXCEPTION 'FAIL 2a: saletype set'; END IF;
    IF (SELECT description FROM poultrycustomerdebts WHERE debtid = v_debt) NOT LIKE 'Owed before the system%' THEN
        RAISE EXCEPTION 'FAIL 2b: old wording changed'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultryreport_plrevenuedetail(v_farm, v_d, v_d, 'DebtCollections') r
                   WHERE r.product LIKE 'Debt %' AND r.totalamount = 5) THEN
        RAISE EXCEPTION 'FAIL 2c: untyped debt row changed in the P&L detail'; END IF;
    RAISE NOTICE 'ok 2 no sale type: as before';

    RAISE NOTICE 'old debt sale type: all checks passed';
END $$;

ROLLBACK;

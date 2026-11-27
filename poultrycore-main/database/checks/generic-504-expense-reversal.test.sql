-- 504_Enock_GenericExpenseReversal -- approved Generic expenses are final and
-- reversed; paid expenses with a supplier make an ExpenseEntry Supplier Payment;
-- Cash Flow shows approved cash only. Self-contained: BEGIN ... ROLLBACK.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.mk_exp(p_farm text, p_sup integer, p_acct integer, p_amount numeric, p_method text, p_paid numeric)
RETURNS integer LANGUAGE sql AS $$
    SELECT spgenericexpense_insert(p_farm, (now() AT TIME ZONE 'utc')::timestamp,
        (SELECT c.genericexpensecategoryid FROM genericexpensecategories c WHERE c.farmid = p_farm ORDER BY 1 LIMIT 1),
        p_sup, '504 check expense', p_amount, NULL, p_method, p_acct, NULL, NULL, NULL, NULL, '504-check', p_paid, NULL);
$$;

CREATE OR REPLACE FUNCTION pg_temp.must_fail(p_sql text, p_like text, p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM ILIKE '%' || p_like || '%' THEN RETURN; END IF;
        RAISE EXCEPTION 'FAIL %: refused with the wrong message: %', p_label, SQLERRM;
    END;
    RAISE EXCEPTION 'FAIL %: was accepted', p_label;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.cf(p_farm text, p_src text, p_id integer) RETURNS numeric LANGUAGE sql AS $$
    SELECT COALESCE(SUM(r.amount), 0) FROM spgenericcashflow_rows(p_farm, NULL, NULL) r WHERE r.rowsource = p_src AND r.sourceid = p_id
$$;

DO $$
DECLARE
    v_farm text; v_acct integer; v_sup integer; v_x integer; v_pay integer; v_pre jsonb; v_rev integer; v_rev2 integer;
    v_cash0 numeric; v_n integer; v_credit integer;
BEGIN
    SELECT e.farmid INTO v_farm FROM genericexpenses e
    WHERE EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = e.farmid)
    GROUP BY e.farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT a.genericcashaccountid INTO v_acct FROM genericcashaccounts a WHERE a.farmid = v_farm ORDER BY 1 LIMIT 1;
    UPDATE genericcashaccounts SET currentbalance = currentbalance + 100000 WHERE genericcashaccountid = v_acct;
    INSERT INTO genericsuppliers (farmid, suppliername, currentbalance) VALUES (v_farm, '504 check supplier', 0) RETURNING genericsupplierid INTO v_sup;

    -- ---------------------------------------------------------------- 1
    v_x := pg_temp.mk_exp(v_farm, NULL, v_acct, 30, 'Cash', NULL);
    IF pg_temp.cf(v_farm, 'Expense', v_x) <> 0 THEN RAISE EXCEPTION 'FAIL 504.1: a DRAFT expense is on Cash Flow'; END IF;
    PERFORM spgenericexpense_approve(v_x, v_farm, '504-check');
    IF pg_temp.cf(v_farm, 'Expense', v_x) <> -30 THEN RAISE EXCEPTION 'FAIL 504.1: approved expense not on Cash Flow (%)', pg_temp.cf(v_farm, 'Expense', v_x); END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericexpense_update(%s, %L, NULL, NULL, NULL, 'x', 31, NULL, 'Cash', %s)$q$, v_x, v_farm, v_acct),
        'cannot be edited', '504.1 edit an approved expense');
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericexpense_delete(%s, %L, 'x', '504-check')$q$, v_x, v_farm), 'Reverse it instead', '504.1 delete an approved expense');
    RAISE NOTICE 'ok 504.1 drafts are not on Cash Flow; approved ones are; an approved expense cannot be edited or deleted';

    -- ---------------------------------------------------------------- 2
    -- no supplier: refund only; refund = its own Cash Flow row on the day
    v_pre := spgenericexpense_reversalpreview(v_farm, v_x);
    IF (v_pre->'payments'->0->'allowed') <> '["Refund"]'::jsonb THEN RAISE EXCEPTION 'FAIL 504.2: no-supplier not refund-only: %', v_pre->'payments'; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericexpense_reverse(%L, %s, 'Wrong amount', NULL, '{"entry":"KeepAsCredit"}'::jsonb)$q$, v_farm, v_x),
        'no supplier', '504.2 keep credit without a supplier');
    SELECT currentbalance INTO v_cash0 FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    v_rev := spgenericexpense_reverse(v_farm, v_x, 'Wrong amount', NULL, '{}'::jsonb, v_pre->>'fingerprint', '504-idem', '504-check');
    IF (SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct) <> v_cash0 + 30 THEN RAISE EXCEPTION 'FAIL 504.2: cash not back'; END IF;
    IF pg_temp.cf(v_farm, 'Expense', v_x) + pg_temp.cf(v_farm, 'ExpenseRefund', v_x) <> 0 OR pg_temp.cf(v_farm, 'ExpenseRefund', v_x) <> 30 THEN
        RAISE EXCEPTION 'FAIL 504.2: Cash Flow does not show expense -30 and refund +30'; END IF;
    IF NOT EXISTS (SELECT 1 FROM genericexpenses WHERE genericexpenseid = v_x AND status = 'Cancelled' AND expensereversalid = v_rev AND NOT isdeleted) THEN
        RAISE EXCEPTION 'FAIL 504.2: expense not marked reversed'; END IF;
    IF EXISTS (SELECT 1 FROM fngenericpnl_lines(v_farm, current_date - 1, current_date + 1) l WHERE l.keytype = 'Expense' AND l.keyid = v_x) THEN
        RAISE EXCEPTION 'FAIL 504.2: the reversed expense is still on P&L'; END IF;
    v_rev2 := spgenericexpense_reverse(v_farm, v_x, 'Wrong amount', NULL, '{}'::jsonb, NULL, '504-idem', '504-check');
    IF v_rev2 <> v_rev THEN RAISE EXCEPTION 'FAIL 504.2: repeated click made another reversal'; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericexpense_reverse(%L, %s, 'Wrong amount', NULL)$q$, v_farm, v_x), 'already been reversed', '504.2 twice');
    PERFORM pg_temp.must_fail(format($q$UPDATE genericexpenses SET notes = 'x' WHERE genericexpenseid = %s$q$, v_x), 'cannot be changed', '504.2 locked');
    RAISE NOTICE 'ok 504.2 refund: cash back, Cash Flow shows the expense and the refund, off P&L, locked, repeat-safe';

    -- ---------------------------------------------------------------- 3
    -- paid with a supplier: an ExpenseEntry Supplier Payment carries the cash, counted once
    SELECT currentbalance INTO v_cash0 FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    v_x := pg_temp.mk_exp(v_farm, v_sup, v_acct, 56, 'Bank', NULL);
    PERFORM spgenericexpense_approve(v_x, v_farm, '504-check');
    SELECT sa.paymentid INTO v_pay FROM supplierpaymentallocation sa JOIN genericsupplierpayments sp ON sp.genericsupplierpaymentid = sa.paymentid
    WHERE sa.documenttype = 'Expense' AND sa.documentid = v_x AND sa.status = 'Posted' AND sp.sourcetype = 'ExpenseEntry' AND sp.amount = 56;
    IF v_pay IS NULL THEN RAISE EXCEPTION 'FAIL 504.3: no ExpenseEntry supplier payment'; END IF;
    IF (SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct) <> v_cash0 - 56 THEN RAISE EXCEPTION 'FAIL 504.3: cash not 56 out once'; END IF;
    IF (SELECT currentbalance FROM genericsuppliers WHERE genericsupplierid = v_sup) <> 0 THEN RAISE EXCEPTION 'FAIL 504.3: supplier owed something'; END IF;
    IF pg_temp.cf(v_farm, 'Expense', v_x) <> 0 OR pg_temp.cf(v_farm, 'SupplierPayment', v_pay) <> -56 THEN
        RAISE EXCEPTION 'FAIL 504.3: Cash Flow should show the 56 once, on the payment (expense %, payment %)', pg_temp.cf(v_farm, 'Expense', v_x), pg_temp.cf(v_farm, 'SupplierPayment', v_pay); END IF;
    IF (SELECT LEAST(COALESCE(amountpaid, amount), amount) FROM genericexpenses WHERE genericexpenseid = v_x) <> 56 THEN RAISE EXCEPTION 'FAIL 504.3: expense not paid'; END IF;
    -- reverse, supplier refunded: the payment is reversed and the cash comes back
    v_pre := spgenericexpense_reversalpreview(v_farm, v_x);
    IF (v_pre->'payments'->0->>'key') <> 'sp:' || v_pay OR (v_pre->'payments'->0->'allowed') <> '["KeepAsCredit","Refund"]'::jsonb THEN
        RAISE EXCEPTION 'FAIL 504.3: preview lines %', v_pre->'payments'; END IF;
    PERFORM spgenericexpense_reverse(v_farm, v_x, 'Wrong supplier', NULL, jsonb_build_object('sp:' || v_pay, 'Refund'), NULL, NULL, '504-check');
    IF (SELECT status FROM genericsupplierpayments WHERE genericsupplierpaymentid = v_pay) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 504.3: payment not reversed'; END IF;
    IF (SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct) <> v_cash0 THEN RAISE EXCEPTION 'FAIL 504.3: cash not back'; END IF;
    IF (SELECT currentbalance FROM genericsuppliers WHERE genericsupplierid = v_sup) <> 0 THEN RAISE EXCEPTION 'FAIL 504.3: supplier balance not 0'; END IF;
    RAISE NOTICE 'ok 504.3 paid with a supplier = ExpenseEntry payment, 56 counted once; reversing with refund reverses the payment';

    -- ---------------------------------------------------------------- 4
    -- part paid (40 of 100) kept as credit; on credit (owed) cleared
    v_x := pg_temp.mk_exp(v_farm, v_sup, v_acct, 100, 'Cash', 40);
    PERFORM spgenericexpense_approve(v_x, v_farm, '504-check');
    IF (SELECT currentbalance FROM genericsuppliers WHERE genericsupplierid = v_sup) <> 60 THEN RAISE EXCEPTION 'FAIL 504.4: supplier should be owed 60'; END IF;
    SELECT sa.paymentid INTO v_pay FROM supplierpaymentallocation sa WHERE sa.documenttype = 'Expense' AND sa.documentid = v_x AND sa.status = 'Posted';
    PERFORM spgenericexpense_reverse(v_farm, v_x, 'Duplicate entry', NULL, '{}'::jsonb, NULL, NULL, '504-check');
    IF fngenericsupplierpayment_unapplied(v_farm, v_pay) <> 40 THEN RAISE EXCEPTION 'FAIL 504.4: the 40 is not supplier credit'; END IF;
    IF (SELECT currentbalance FROM genericsuppliers WHERE genericsupplierid = v_sup) <> 0 THEN RAISE EXCEPTION 'FAIL 504.4: the 60 owed not cleared'; END IF;
    v_x := pg_temp.mk_exp(v_farm, v_sup, NULL, 25, 'Credit', NULL);
    PERFORM spgenericexpense_approve(v_x, v_farm, '504-check');
    IF pg_temp.cf(v_farm, 'Expense', v_x) <> 0 THEN RAISE EXCEPTION 'FAIL 504.4: an unpaid credit expense is on Cash Flow'; END IF;
    v_pre := spgenericexpense_reversalpreview(v_farm, v_x);
    IF jsonb_array_length(v_pre->'payments') <> 0 THEN RAISE EXCEPTION 'FAIL 504.4: credit expense offered money lines'; END IF;
    PERFORM spgenericexpense_reverse(v_farm, v_x, 'Duplicate entry', NULL, '{}'::jsonb, NULL, NULL, '504-check');
    IF (SELECT currentbalance FROM genericsuppliers WHERE genericsupplierid = v_sup) <> 0 THEN RAISE EXCEPTION 'FAIL 504.4: credit expense owed not cleared'; END IF;
    RAISE NOTICE 'ok 504.4 part paid kept as credit, rest owed cleared; credit expense not on Cash Flow and cleared on reversal';

    -- ---------------------------------------------------------------- 5
    -- approved before 504 (paid straight from the account, supplier on it): keep as credit
    v_x := pg_temp.mk_exp(v_farm, NULL, v_acct, 20, 'Cash', NULL);
    PERFORM spgenericexpense_approve(v_x, v_farm, '504-check');
    UPDATE genericexpenses SET genericsupplierid = v_sup WHERE genericexpenseid = v_x;
    v_pre := spgenericexpense_reversalpreview(v_farm, v_x);
    IF (v_pre->'payments'->0->>'key') <> 'entry' OR (v_pre->'payments'->0->'allowed') <> '["KeepAsCredit","Refund"]'::jsonb THEN
        RAISE EXCEPTION 'FAIL 504.5: legacy entry line %', v_pre->'payments'; END IF;
    PERFORM spgenericexpense_reverse(v_farm, v_x, 'Wrong item', NULL, '{}'::jsonb, NULL, NULL, '504-check');
    SELECT genericsupplierpaymentid INTO v_credit FROM genericsupplierpayments WHERE farmid = v_farm AND sourcetype = 'ExpenseReversalCredit' AND genericsupplierid = v_sup;
    IF v_credit IS NULL OR fngenericsupplierpayment_unapplied(v_farm, v_credit) <> 20 THEN RAISE EXCEPTION 'FAIL 504.5: no 20 credit row'; END IF;
    IF pg_temp.cf(v_farm, 'SupplierPayment', v_credit) <> 0 THEN RAISE EXCEPTION 'FAIL 504.5: the credit row is on Cash Flow'; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericsupplierpayment_reverse(%L, %s, 'x', '504-check')$q$, v_farm, v_credit), 'reversed purchase or expense', '504.5 reverse kept credit');
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericexpense_reverse(%L, %s, 'Wrong item', NULL)$q$, v_farm, v_x), 'already been reversed', '504.5 twice');
    RAISE NOTICE 'ok 504.5 an expense paid straight from the account can be kept as credit (no cash, not on Cash Flow, cannot be erased)';

    -- ---------------------------------------------------------------- 6
    v_x := pg_temp.mk_exp(v_farm, NULL, v_acct, 5, 'Cash', NULL);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(spgenericexpense_reversalpreview(v_farm, v_x)->'blockers') b WHERE b->>'code' = 'Draft') THEN
        RAISE EXCEPTION 'FAIL 504.6: a draft can be reversed'; END IF;
    PERFORM spgenericexpense_update(v_x, v_farm, NULL, NULL, NULL, 'edited draft', 6, NULL, 'Cash', v_acct);
    PERFORM spgenericexpense_approve(v_x, v_farm, '504-check');
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericexpense_reverse(%L, %s, 'Wrong amount', NULL, '{}'::jsonb, 'stale')$q$, v_farm, v_x), 'changed after', '504.6 stale');
    RAISE NOTICE 'ok 504.6 drafts are edited, not reversed; a stale preview is refused';

    RAISE NOTICE 'generic 504: all checks passed';
END $$;

ROLLBACK;

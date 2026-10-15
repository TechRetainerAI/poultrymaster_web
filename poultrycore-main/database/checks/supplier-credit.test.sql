-- =============================================================================
-- supplier-credit.test.sql -- checks for migration 370.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Works on a
-- throwaway supplier in the first poultry company (uuid farm id) that has a
-- cash account allowing a negative balance or holding enough cash.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm    text;
    v_user    text;
    v_acct    integer;
    v_sup     integer;
    v_adv     integer;
    v_over    integer;
    v_note    integer;
    v_bill    integer;
    v_debt    integer;
    v_debt2   integer;
    v_debt3   integer;
    v_app     integer;
    v_ref     integer;
    v_res     jsonb;
    v_bal0    numeric;
    v_n       integer;
    v_x       numeric;
    v_failed  boolean;
    v_from    timestamp := (CURRENT_DATE - 2)::timestamp;
    v_to      timestamp := (CURRENT_DATE + 2)::timestamp;
BEGIN
    SELECT a.farmid, a.poultrycashaccountid INTO v_farm, v_acct
    FROM   poultrycashaccounts a
    JOIN   farms f ON (f.id::text = a.farmid OR f.farmid::text = a.farmid) AND f.type = 'Poultry'
    WHERE  a.isactive AND a.farmid ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ORDER  BY a.poultrycashaccountid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'supplier credit: all checks passed';
        RETURN;
    END IF;
    -- Room to pay, whatever the account holds.
    UPDATE poultrycashaccounts SET allownegativebalance = TRUE WHERE poultrycashaccountid = v_acct;
    SELECT f.owneruserid INTO v_user FROM farms f WHERE f.id::text = v_farm OR f.farmid::text = v_farm LIMIT 1;
    v_user := COALESCE(v_user, 'check370');
    INSERT INTO supplier (farmid, userid, name) VALUES (v_farm, v_user, 'Supplier Check 370')
    RETURNING supplierid INTO v_sup;

    -- 1. Pay an advance of 1,000: cash out, credit, on Cash Flow; no purchase, no expense.
    SELECT currentbalance INTO v_bal0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrysupplierpayment_record(v_farm, v_sup, 1000, '[]'::jsonb, 'Cash', now()::timestamp, NULL, NULL, NULL, 'SupplierCredits', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1a: advance without a cash account accepted'; END IF;
    v_adv := sppoultrysupplierpayment_record(v_farm, v_sup, 1000, '[]'::jsonb, 'Cash', now()::timestamp, v_acct, 'ADV-1', 'maize next month', 'SupplierCredits', v_user);
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 - 1000 THEN
        RAISE EXCEPTION 'FAIL 1b: cash did not go down by 1,000'; END IF;
    IF fnpoultrysupplier_credit(v_farm, v_sup) <> 1000 THEN RAISE EXCEPTION 'FAIL 1c: credit %', fnpoultrysupplier_credit(v_farm, v_sup); END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycashflow_rows(v_farm, v_from, v_to) r WHERE r.rowsource = 'SupplierAdvance' AND r.sourceid = v_adv AND r.amount = -1000) THEN
        RAISE EXCEPTION 'FAIL 1d: advance not Money Out on Cash Flow'; END IF;
    IF EXISTS (SELECT 1 FROM expense e WHERE e.description LIKE 'Supplier payment #' || v_adv || ' %') THEN
        RAISE EXCEPTION 'FAIL 1e: an advance booked an expense'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrysuppliercredit_events(v_farm, v_sup) e WHERE e.poultrysupplierpaymentid = v_adv
                   AND e.source = 'Supplier advance' AND e.available = 1000) THEN
        RAISE EXCEPTION 'FAIL 1f: advance not a credit event'; END IF;
    RAISE NOTICE 'ok 1 an advance is cash out and supplier credit, nothing else';

    -- 2. Apply 400 of it to an unpaid bill: bill paid down, no new cash, Cash Flow still 1,000 on the advance day.
    INSERT INTO expense (expensedate, category, description, amount, amountpaid, paymentmethod, createddate, userid, farmid, supplierid)
    VALUES (now()::timestamp, 'Feed', 'Check 370 bill', 600, 0, 'Credit', now()::timestamp, v_user, v_farm::uuid, v_sup)
    RETURNING expenseid INTO v_bill;
    SELECT currentbalance INTO v_bal0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_app := sppoultrysuppliercredit_apply(v_farm, v_adv, 'Expense', v_bill, 400, v_user);
    IF (SELECT d.balance FROM fnpoultrypayables(v_farm) d WHERE d.documenttype = 'Expense' AND d.documentid = v_bill) <> 200 THEN
        RAISE EXCEPTION 'FAIL 2a: bill not paid down to 200'; END IF;
    IF fnpoultrysupplier_credit(v_farm, v_sup) <> 600 THEN RAISE EXCEPTION 'FAIL 2b: credit not 600'; END IF;
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 THEN
        RAISE EXCEPTION 'FAIL 2c: applying credit moved cash'; END IF;
    SELECT COALESCE(sum(r.amount), 0) INTO v_x FROM sppoultrycashflow_rows(v_farm, v_from, v_to) r
    WHERE  (r.rowsource = 'SupplierAdvance' AND r.sourceid = v_adv)
       OR  (r.rowsource = 'ExpensePayment' AND r.sourceid = v_bill)
       OR  (r.rowsource = 'Expense' AND r.sourceid = v_bill);
    IF v_x <> -1000 THEN RAISE EXCEPTION 'FAIL 2d: Cash Flow for the advance and its use is % (want -1000)', v_x; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrysuppliercredit_apply(v_farm, v_adv, 'Expense', v_bill, 300, v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2e: more than owed applied'; END IF;
    RAISE NOTICE 'ok 2 credit applied to a bill: no new cash, Cash Flow unchanged';

    -- 3. A used advance cannot be reversed; unapply, then it can, and the cash comes back.
    v_failed := FALSE;
    BEGIN PERFORM sppoultrysupplierpayment_reverse(v_farm, v_adv, 'x', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3a: used advance reversed'; END IF;
    PERFORM sppoultrysuppliercredit_unapply(v_farm, v_app, 'applied to the wrong bill', v_user);
    IF (SELECT d.balance FROM fnpoultrypayables(v_farm) d WHERE d.documenttype = 'Expense' AND d.documentid = v_bill) <> 600 THEN
        RAISE EXCEPTION 'FAIL 3b: bill not owed again'; END IF;
    IF fnpoultrysupplier_credit(v_farm, v_sup) <> 1000 THEN RAISE EXCEPTION 'FAIL 3c: credit not restored'; END IF;
    RAISE NOTICE 'ok 3 unapplying restores the bill and the credit';

    -- 4. Supplier refund out of the advance, and its reversal.
    SELECT currentbalance INTO v_bal0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_ref := sppoultrysupplierrefund_record(v_farm, v_adv, 250, v_acct, 'Cash', NULL, 'unused part returned', v_user);
    IF fnpoultrysupplier_credit(v_farm, v_sup) <> 750 THEN RAISE EXCEPTION 'FAIL 4a: credit after refund'; END IF;
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 + 250 THEN
        RAISE EXCEPTION 'FAIL 4b: refund cash not in'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycashflow_rows(v_farm, v_from, v_to) r WHERE r.rowsource = 'SupplierRefund' AND r.sourceid = v_ref AND r.amount = 250) THEN
        RAISE EXCEPTION 'FAIL 4c: refund not Money In'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrysupplierpayment_reverse(v_farm, v_adv, 'x', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4d: refunded advance reversed'; END IF;
    PERFORM sppoultrysupplierrefund_reverse(v_farm, v_ref, 'entered by mistake', v_user);
    IF fnpoultrysupplier_credit(v_farm, v_sup) <> 1000 THEN RAISE EXCEPTION 'FAIL 4e: credit after refund reversal'; END IF;
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 THEN
        RAISE EXCEPTION 'FAIL 4f: refund reversal cash'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycashflow_rows(v_farm, v_from, v_to) r WHERE r.rowsource = 'SupplierRefundReversal' AND r.sourceid = v_ref AND r.amount = -250) THEN
        RAISE EXCEPTION 'FAIL 4g: refund reversal not Money Out'; END IF;
    RAISE NOTICE 'ok 4 supplier refund and its reversal';

    -- 5. Reverse the unused advance: cash back, credit gone, gone from Cash Flow.
    SELECT currentbalance INTO v_bal0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    PERFORM sppoultrysuppliercredit_reverse(v_farm, v_adv, 'paid twice', v_user);
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 + 1000 THEN
        RAISE EXCEPTION 'FAIL 5a: cash not back'; END IF;
    IF fnpoultrysupplier_credit(v_farm, v_sup) <> 0 THEN RAISE EXCEPTION 'FAIL 5b: credit left'; END IF;
    RAISE NOTICE 'ok 5 an unused advance reverses';

    -- 6. Supplier debt: owed without a purchase; an overpayment of it leaves credit.
    v_res := sppoultrysupplierdebt_create(v_farm, v_sup, 500, CURRENT_DATE - 5, 'OpeningBalance', 'Maize owed before the system', 'Old book', NULL, v_user);
    v_debt := (v_res->>'debtId')::integer;
    IF NOT EXISTS (SELECT 1 FROM sppoultrysupplierbalances(p_farmid => v_farm) b WHERE b.supplierid = v_sup AND b.totalbalance = 1100) THEN
        RAISE EXCEPTION 'FAIL 6a: supplier balance (bill 600 + debt 500) not 1,100'; END IF;
    SELECT currentbalance INTO v_bal0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_over := sppoultrysupplierpayment_record(v_farm, v_sup, 700,
                  jsonb_build_array(jsonb_build_object('documenttype', 'SupplierDebt', 'documentid', v_debt, 'amount', 500)),
                  'Cash', now()::timestamp, v_acct, NULL, NULL, 'SupplierBalances', v_user);
    IF (SELECT d.balance FROM fnpoultrypayables(v_farm) d WHERE d.documenttype = 'SupplierDebt' AND d.documentid = v_debt) <> 0 THEN
        RAISE EXCEPTION 'FAIL 6b: debt not paid'; END IF;
    IF fnpoultrysupplier_credit(v_farm, v_sup) <> 200 THEN RAISE EXCEPTION 'FAIL 6c: overpayment credit %', fnpoultrysupplier_credit(v_farm, v_sup); END IF;
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 - 700 THEN
        RAISE EXCEPTION 'FAIL 6d: cash not down 700 once'; END IF;
    SELECT COALESCE(sum(r.amount), 0) INTO v_x FROM sppoultrycashflow_rows(v_farm, v_from, v_to) r
    WHERE  (r.rowsource = 'SupplierAdvance' AND r.sourceid = v_over) OR (r.rowsource = 'SupplierDebtPayment' AND r.sourceid = v_debt);
    IF v_x <> -700 THEN RAISE EXCEPTION 'FAIL 6e: Cash Flow for the overpayment is %', v_x; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrysuppliercredit_events(v_farm, v_sup) e WHERE e.poultrysupplierpaymentid = v_over AND e.source = 'Overpayment' AND e.available = 200) THEN
        RAISE EXCEPTION 'FAIL 6f: overpayment not a credit event'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrysupplierdebt_reverse(v_farm, v_debt, 'x', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6g: a paid debt reversed'; END IF;
    RAISE NOTICE 'ok 6 supplier debt owed and paid; the overpayment is credit';

    -- 7. A credit note: credit with no cash; applied to a debt; reversed only from Supplier Credits.
    SELECT currentbalance INTO v_bal0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_note := sppoultrysuppliercredit_create(v_farm, v_sup, 'SupplierCreditNote', 300, NULL, 'CN-9', 'short delivery', v_user);
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 THEN RAISE EXCEPTION 'FAIL 7a: credit note moved cash'; END IF;
    IF EXISTS (SELECT 1 FROM sppoultrycashflow_rows(v_farm, v_from, v_to) r WHERE r.sourceid = v_note AND r.rowsource LIKE 'Supplier%') THEN
        RAISE EXCEPTION 'FAIL 7b: credit note on Cash Flow'; END IF;
    IF fnpoultrysupplier_credit(v_farm, v_sup) <> 500 THEN RAISE EXCEPTION 'FAIL 7c: credit with note %', fnpoultrysupplier_credit(v_farm, v_sup); END IF;
    v_res := sppoultrysupplierdebt_create(v_farm, v_sup, 300, CURRENT_DATE, 'Adjustment', 'Price correction owed', NULL, NULL, v_user);
    v_debt2 := (v_res->>'debtId')::integer;
    PERFORM sppoultrysuppliercredit_apply(v_farm, v_note, 'SupplierDebt', v_debt2, 300, v_user);
    IF (SELECT d.balance FROM fnpoultrypayables(v_farm) d WHERE d.documenttype = 'SupplierDebt' AND d.documentid = v_debt2) <> 0 THEN
        RAISE EXCEPTION 'FAIL 7d: credit note did not pay the debt'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrysupplierpayment_reverse(v_farm, v_note, 'x', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7e: credit note reversed as a payment'; END IF;
    -- A credit note used on a bill is not money out either.
    v_note := sppoultrysuppliercredit_create(v_farm, v_sup, 'SupplierCreditNote', 100, NULL, 'CN-10', 'damaged bags', v_user);
    v_app := sppoultrysuppliercredit_apply(v_farm, v_note, 'Expense', v_bill, 100, v_user);
    IF EXISTS (SELECT 1 FROM sppoultrycashflow_rows(v_farm, v_from, v_to) r WHERE r.rowsource = 'ExpensePayment' AND r.sourcerowid = v_app) THEN
        RAISE EXCEPTION 'FAIL 7f: a credit note applied to a bill shows as money out'; END IF;
    IF (SELECT d.balance FROM fnpoultrypayables(v_farm) d WHERE d.documenttype = 'Expense' AND d.documentid = v_bill) <> 500 THEN
        RAISE EXCEPTION 'FAIL 7g: credit note did not pay the bill down'; END IF;
    RAISE NOTICE 'ok 7 a credit note is credit with no cash';

    -- 8. Reversing the overpaid payment: the debt is owed again, its credit gone.
    PERFORM sppoultrysupplierpayment_reverse(v_farm, v_over, 'check', v_user);
    IF (SELECT d.balance FROM fnpoultrypayables(v_farm) d WHERE d.documenttype = 'SupplierDebt' AND d.documentid = v_debt) <> 500 THEN
        RAISE EXCEPTION 'FAIL 8a: debt not owed again'; END IF;
    IF fnpoultrysupplier_credit(v_farm, v_sup) <> 0 THEN RAISE EXCEPTION 'FAIL 8b: credit left %', fnpoultrysupplier_credit(v_farm, v_sup); END IF;
    RAISE NOTICE 'ok 8 reversing an overpayment reopens what it paid';

    -- 9. An unpaid debt reverses; the summary lists credit; statement includes the debt.
    v_res := sppoultrysupplierdebt_create(v_farm, v_sup, 90, CURRENT_DATE, 'Other', 'Entered twice', NULL, NULL, v_user);
    v_debt3 := (v_res->>'debtId')::integer;
    PERFORM sppoultrysupplierdebt_reverse(v_farm, v_debt3, 'entered twice', v_user);
    IF EXISTS (SELECT 1 FROM fnpoultrypayables(v_farm) d WHERE d.documenttype = 'SupplierDebt' AND d.documentid = v_debt3) THEN
        RAISE EXCEPTION 'FAIL 9a: reversed debt still payable'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrysupplierstatement(v_farm, v_sup) s WHERE s.reference LIKE 'SD-%') THEN
        RAISE EXCEPTION 'FAIL 9b: statement has no supplier debt'; END IF;
    RAISE NOTICE 'ok 9 debt reversal; statement shows debts';

    RAISE NOTICE 'supplier credit: all checks passed';
END $$;

ROLLBACK;

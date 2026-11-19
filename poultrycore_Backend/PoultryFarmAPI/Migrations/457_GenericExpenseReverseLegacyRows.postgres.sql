-- 457_GenericExpenseReverseLegacyRows
-- Report 40 Part 13. Editing or deleting an approved Generic expense first
-- reverses its postings (spgenericexpense__post with p_sign = -1). An expense
-- saved before 448 (e.g. "Bank", nothing paid, no cash account, no supplier)
-- never posted anything, but the reversal still tried to take back a supplier
-- debt and failed: "Supplier on the expense does not exist or belongs to
-- another company." The reversal now skips a part the row has no account or
-- supplier for. Posting (p_sign = +1) is unchanged.

CREATE OR REPLACE FUNCTION public.spgenericexpense__post(
    p_id integer, p_farmid text, p_sign integer, p_by text)
RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
    e        record;
    v_now    timestamp := (now() AT TIME ZONE 'utc');
    v_paid   numeric(14,2);
    v_owed   numeric(14,2);
    v_cat    text;
    v_desc   text;
    v_cash   numeric(14,2);
    v_neg    boolean;
    v_sup    numeric(14,2);
BEGIN
    SELECT * INTO e FROM genericexpenses x WHERE x.genericexpenseid = p_id AND x.farmid = p_farmid;
    v_paid := CASE WHEN e.paymentmethod = 'Credit' THEN 0
                   ELSE LEAST(COALESCE(e.amountpaid, e.amount), e.amount) END;
    v_owed := e.amount - v_paid;
    SELECT c.name INTO v_cat FROM genericexpensecategories c
    WHERE  c.genericexpensecategoryid = e.genericexpensecategoryid;
    v_desc := COALESCE(NULLIF(btrim(e.description), ''), 'Expense: ' || COALESCE(v_cat, '?'));
    IF p_sign < 0 THEN v_desc := 'Reversal of expense #' || p_id || ': ' || v_desc; END IF;

    -- 457: undoing only takes back what was posted. A row saved before 448 can
    -- carry no cash account or no supplier, so nothing was posted there.
    IF p_sign < 0 AND e.genericcashaccountid IS NULL THEN v_paid := 0; END IF;
    IF p_sign < 0 AND e.genericsupplierid IS NULL THEN v_owed := 0; END IF;

    IF v_paid > 0 THEN
        SELECT ca.currentbalance, ca.allownegativebalance INTO v_cash, v_neg
        FROM   genericcashaccounts ca
        WHERE  ca.genericcashaccountid = e.genericcashaccountid AND ca.farmid = p_farmid
        FOR UPDATE;
        IF v_cash IS NULL THEN
            RAISE EXCEPTION 'Cash account on the expense does not exist or belongs to another company.';
        END IF;
        IF p_sign > 0 AND v_cash - v_paid < 0 AND v_neg = FALSE THEN
            RAISE EXCEPTION 'Not enough money in the cash account: it has %, this expense pays % from it.', v_cash, v_paid;
        END IF;
        INSERT INTO genericcashtransactions
            (farmid, genericcashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, e.genericcashaccountid,
             CASE WHEN p_sign > 0 THEN e.expensedate ELSE v_now END,
             CASE WHEN p_sign > 0 THEN 'CashOut' ELSE 'CashIn' END,
             'Expense', p_id, -p_sign * v_paid, v_cash - p_sign * v_paid, v_desc, p_by, p_by, v_now);
        UPDATE genericcashaccounts
        SET    currentbalance = v_cash - p_sign * v_paid, updatedat = v_now
        WHERE  genericcashaccountid = e.genericcashaccountid AND farmid = p_farmid;
    END IF;

    IF v_owed > 0 THEN
        SELECT COALESCE(s.currentbalance, 0) INTO v_sup FROM genericsuppliers s
        WHERE  s.genericsupplierid = e.genericsupplierid AND s.farmid = p_farmid
        FOR UPDATE;
        IF v_sup IS NULL THEN
            RAISE EXCEPTION 'Supplier on the expense does not exist or belongs to another company.';
        END IF;
        INSERT INTO genericsupplierledger
            (farmid, genericsupplierid, transactiondate, transactiontype, expenseid,
             debitamount, creditamount, balanceaftertransaction, description, createdby)
        VALUES
            (p_farmid, e.genericsupplierid,
             CASE WHEN p_sign > 0 THEN e.expensedate ELSE v_now END,
             CASE WHEN p_sign > 0 THEN 'ExpenseCredit' ELSE 'ExpenseReversal' END, p_id,
             CASE WHEN p_sign > 0 THEN 0 ELSE v_owed END,
             CASE WHEN p_sign > 0 THEN v_owed ELSE 0 END,
             GREATEST(v_sup + p_sign * v_owed, 0), v_desc, p_by);
        UPDATE genericsuppliers
        SET    currentbalance = GREATEST(v_sup + p_sign * v_owed, 0), updatedat = v_now
        WHERE  genericsupplierid = e.genericsupplierid AND farmid = p_farmid;
    END IF;
END
$fn$;


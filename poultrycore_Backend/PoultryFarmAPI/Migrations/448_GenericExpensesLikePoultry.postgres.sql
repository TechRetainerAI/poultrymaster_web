-- =============================================================================
-- 448_GenericExpensesLikePoultry.postgres.sql
--
-- Generic Expenses brought up to the Poultry Expenses page (Report 40), keeping
-- Generic's own Draft -> Approve step.
--
--  1. PAYMENT STATUS, as on Poultry: Paid / Partly paid / Not paid, plus a due
--     date. Stored the 248 way: amountpaid NULL = paid in full, 0 = not paid
--     (payment method 'Credit'), a number = partly paid. Approving now posts:
--       * the part paid now  -> a CashOut from the chosen cash account;
--       * the part still owed -> the supplier ledger (ExpenseCredit) and the
--         supplier's balance, so it appears on Supplier Balances.
--     Before this, a Credit expense kept amountpaid NULL ("paid in full"), so
--     it never showed on Supplier Balances although the ledger said it was owed.
--  2. EDIT (spgenericexpense_update). Draft / Rejected: everything, and a
--     Rejected one goes back to Draft. Approved: date, category, description,
--     paid to, notes, due date freely; a change to the money (amount, method,
--     account, supplier, amount paid) undoes the approval's postings and posts
--     them again -- refused once any supplier payment is applied to it.
--  3. DELETE (spgenericexpense_delete). Draft / Rejected: removed. Approved:
--     its cash goes back to the account (CashIn "Reversal of expense #n") and
--     the owed part comes off the supplier, then it is marked Cancelled and
--     removed. Refused once any supplier payment is applied to it.
--     Expenses made by another document (sourcetype set: internal use, staff
--     payments, recurring, ...) are changed there, never here.
--  4. READERS. getall/getbyid also return amountpaid, duedate, paymentstatus,
--     sourcetype, paymentsapplied. fngenericpayables only counts Approved expenses. Cash Flow's
--     expense arm only counts Approved ones (Draft and Rejected moved no money).
--
-- Deploy order: this migration, then the Farm API, then the web app.
-- Idempotent.
-- =============================================================================


-- ------------------------------------------------------------ backfill -----
-- An approved Credit expense of its own (not another document's shadow) with
-- nothing paid is owed in full. None on dev today; kept for other databases.
UPDATE genericexpenses e
SET    amountpaid = 0
WHERE  e.paymentmethod = 'Credit' AND e.status = 'Approved'
  AND  e.sourcetype IS NULL AND e.amountpaid IS NULL
  AND  COALESCE(e.isdeleted, FALSE) = FALSE
  AND  NOT EXISTS (SELECT 1 FROM supplierpaymentallocation sa
                   WHERE sa.module = 'generic' AND sa.documenttype = 'Expense'
                     AND sa.documentid = e.genericexpenseid AND sa.status = 'Posted');

-- ------------------------------------------------------------- readers -----
DROP FUNCTION IF EXISTS public.spgenericexpense_getall(text, text, timestamp without time zone, timestamp without time zone);
CREATE FUNCTION public.spgenericexpense_getall(
    p_farmid text, p_status text DEFAULT NULL,
    p_fromdate timestamp DEFAULT NULL, p_todate timestamp DEFAULT NULL)
RETURNS TABLE(genericexpenseid integer, farmid text, expensedate timestamp, genericexpensecategoryid integer,
              categoryname text, genericsupplierid integer, suppliername text, description text, amount numeric,
              paidto text, paymentmethod text, genericcashaccountid integer, cashaccountname text, receipturl text,
              branchid integer, staffid integer, status text, notes text, createdby text, approvedby text,
              approvedat timestamp, rejectionreason text, createdat timestamp, updatedat timestamp,
              amountpaid numeric, duedate date, paymentstatus text, sourcetype text,
              paymentsapplied numeric)
LANGUAGE plpgsql STABLE
AS $fn$
BEGIN
    RETURN QUERY
    SELECT e.genericexpenseid, e.farmid::text, e.expensedate,
           e.genericexpensecategoryid, c.name::text,
           e.genericsupplierid, s.suppliername::text,
           e.description::text, e.amount, e.paidto::text, e.paymentmethod::text,
           e.genericcashaccountid, ca.accountname::text, e.receipturl::text, e.branchid, e.staffid,
           e.status::text, e.notes::text, e.createdby::text, e.approvedby::text, e.approvedat,
           e.rejectionreason::text, e.createdat, e.updatedat,
           -- resolved: NULL means paid in full (248)
           COALESCE(e.amountpaid, e.amount), e.duedate, e.paymentstatus, e.sourcetype,
           -- what supplier payments have applied (money is locked while > 0)
           COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                     WHERE sa.farmid = e.farmid AND sa.module = 'generic' AND sa.documenttype = 'Expense'
                       AND sa.documentid = e.genericexpenseid AND sa.status = 'Posted'), 0)::numeric
    FROM   genericexpenses e
    INNER  JOIN genericexpensecategories c ON c.genericexpensecategoryid = e.genericexpensecategoryid
    LEFT   JOIN genericsuppliers s ON s.genericsupplierid = e.genericsupplierid
    LEFT   JOIN genericcashaccounts ca ON ca.genericcashaccountid = e.genericcashaccountid
    WHERE  e.farmid = p_farmid AND e.isdeleted = FALSE
       AND (p_status   IS NULL OR e.status = p_status)
       AND (p_fromdate IS NULL OR e.expensedate >= p_fromdate)
       AND (p_todate   IS NULL OR e.expensedate <= p_todate)
    ORDER  BY e.expensedate DESC, e.genericexpenseid DESC;
END
$fn$;

DROP FUNCTION IF EXISTS public.spgenericexpense_getbyid(integer, text);
CREATE FUNCTION public.spgenericexpense_getbyid(p_genericexpenseid integer, p_farmid text)
RETURNS TABLE(genericexpenseid integer, farmid text, expensedate timestamp, genericexpensecategoryid integer,
              categoryname text, genericsupplierid integer, suppliername text, description text, amount numeric,
              paidto text, paymentmethod text, genericcashaccountid integer, cashaccountname text, receipturl text,
              branchid integer, staffid integer, status text, notes text, createdby text, approvedby text,
              approvedat timestamp, rejectionreason text, createdat timestamp, updatedat timestamp,
              amountpaid numeric, duedate date, paymentstatus text, sourcetype text,
              paymentsapplied numeric)
LANGUAGE sql STABLE
AS $fn$
    SELECT g.* FROM public.spgenericexpense_getall(p_farmid) g
    WHERE  g.genericexpenseid = p_genericexpenseid;
$fn$;

-- The expense arm of the payables: Approved only (a Draft owes nothing yet).
CREATE OR REPLACE FUNCTION public.fngenericpayables(p_farmid text)
 RETURNS TABLE(documenttype text, documentid integer, supplierid integer, docdate date, label text, reference text, totalcost numeric, amountpaid numeric, balance numeric, cashaccountid integer, duedate date)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT 'Purchase'::text, p.genericpurchaseid, p.genericsupplierid,
           p.purchasedate::date,
           COALESCE(NULLIF(btrim(p.notes), ''), 'Purchase')::text,
           ('P' || p.genericpurchaseid::text)::text,
           COALESCE(p.totalamount, 0)::numeric(14,2),
           COALESCE(p.amountpaid, 0)::numeric(14,2),
           GREATEST(COALESCE(p.totalamount, 0) - COALESCE(p.amountpaid, 0), 0)::numeric(14,2),
           p.genericcashaccountid,
           NULL::date
    FROM   genericpurchases p
    WHERE  p.farmid = p_farmid
      AND  COALESCE(p.isdeleted, FALSE) = FALSE
      AND  p.genericsupplierid IS NOT NULL
      AND  COALESCE(p.status, '') <> 'Cancelled'

    UNION ALL

    SELECT 'Expense'::text, e.genericexpenseid, e.genericsupplierid,
           e.expensedate::date,
           COALESCE(NULLIF(btrim(e.description), ''), 'Expense')::text,
           ('E' || e.genericexpenseid::text)::text,
           COALESCE(e.amount, 0)::numeric(14,2),
           COALESCE(e.amountpaid, e.amount)::numeric(14,2),
           GREATEST(COALESCE(e.amount, 0) - COALESCE(e.amountpaid, e.amount), 0)::numeric(14,2),
           e.genericcashaccountid,
           e.duedate
    FROM   genericexpenses e
    WHERE  e.farmid = p_farmid
      AND  COALESCE(e.isdeleted, FALSE) = FALSE
      AND  e.genericsupplierid IS NOT NULL
      AND  e.sourcetype IS NULL
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
      AND  e.status = 'Approved';
$function$;

-- ------------------------------------------------- money postings (shared) -----
-- p_sign +1 posts what an approved expense moves; -1 takes it back. Reads the
-- row as it is now, so call -1 BEFORE changing it and +1 AFTER.
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

-- Shared checks for insert and update. Returns the normalised method, account
-- and amount paid (NULL = paid in full).
CREATE OR REPLACE FUNCTION public.fngenericexpense_normalise(
    p_farmid text, p_amount numeric, p_paymentmethod text, p_cashaccountid integer,
    p_supplierid integer, p_amountpaid numeric,
    OUT o_method text, OUT o_cashaccountid integer, OUT o_amountpaid numeric)
LANGUAGE plpgsql STABLE
AS $fn$
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than zero.';
    END IF;
    o_method := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
    o_cashaccountid := p_cashaccountid;
    o_amountpaid := p_amountpaid;
    IF o_amountpaid IS NOT NULL AND o_amountpaid < 0 THEN
        RAISE EXCEPTION 'Amount paid cannot be negative.';
    END IF;
    IF o_amountpaid IS NOT NULL AND o_amountpaid >= p_amount THEN o_amountpaid := NULL; END IF;
    -- Nothing paid is a Credit expense, whatever method was picked.
    IF o_method = 'Credit' OR o_amountpaid = 0 THEN
        o_method := 'Credit'; o_amountpaid := 0; o_cashaccountid := NULL;
    END IF;
    IF o_method = 'Credit' AND p_supplierid IS NULL THEN
        RAISE EXCEPTION 'Select the supplier this expense is owed to.';
    END IF;
    IF o_amountpaid IS NOT NULL AND o_amountpaid > 0 AND p_supplierid IS NULL THEN
        RAISE EXCEPTION 'Select the supplier the rest of this expense is owed to.';
    END IF;
    IF o_method <> 'Credit' AND o_cashaccountid IS NULL THEN
        RAISE EXCEPTION 'Select the cash account this expense is paid from.';
    END IF;
    IF p_supplierid IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM genericsuppliers s WHERE s.genericsupplierid = p_supplierid AND s.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;
    IF o_cashaccountid IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM genericcashaccounts ca WHERE ca.genericcashaccountid = o_cashaccountid AND ca.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
    END IF;
END
$fn$;

-- ------------------------------------------------------------- insert -----
DROP FUNCTION IF EXISTS public.spgenericexpense_insert(text, timestamp without time zone, integer, integer, text, numeric, text, text, integer, text, integer, integer, text, text);
CREATE OR REPLACE FUNCTION public.spgenericexpense_insert(
    p_farmid text, p_expensedate timestamp DEFAULT NULL, p_genericexpensecategoryid integer DEFAULT NULL,
    p_genericsupplierid integer DEFAULT NULL, p_description text DEFAULT NULL, p_amount numeric DEFAULT NULL,
    p_paidto text DEFAULT NULL, p_paymentmethod text DEFAULT NULL, p_genericcashaccountid integer DEFAULT NULL,
    p_receipturl text DEFAULT NULL, p_branchid integer DEFAULT NULL, p_staffid integer DEFAULT NULL,
    p_notes text DEFAULT NULL, p_createdby text DEFAULT NULL,
    p_amountpaid numeric DEFAULT NULL, p_duedate date DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $fn$
DECLARE
    n record;
    v_newid integer;
BEGIN
    SELECT * INTO n FROM public.fngenericexpense_normalise(p_farmid, p_amount, p_paymentmethod,
        p_genericcashaccountid, p_genericsupplierid, p_amountpaid);
    INSERT INTO genericexpenses (
        farmid, expensedate, genericexpensecategoryid, genericsupplierid, description, amount, paidto,
        paymentmethod, genericcashaccountid, receipturl, branchid, staffid, status, notes, createdby,
        amountpaid, duedate)
    VALUES (
        p_farmid, COALESCE(p_expensedate, (now() AT TIME ZONE 'utc')), p_genericexpensecategoryid, p_genericsupplierid,
        p_description, p_amount, p_paidto, n.o_method, n.o_cashaccountid, p_receipturl, p_branchid, p_staffid,
        'Draft', p_notes, p_createdby,
        n.o_amountpaid, CASE WHEN n.o_amountpaid IS NULL THEN NULL ELSE p_duedate END)
    RETURNING genericexpenses.genericexpenseid INTO v_newid;
    RETURN v_newid;
END
$fn$;

-- ------------------------------------------------------------ approve -----
CREATE OR REPLACE FUNCTION public.spgenericexpense_approve(
    p_genericexpenseid integer, p_farmid text, p_approvedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_status text;
BEGIN
    SELECT e.status INTO v_status FROM genericexpenses e
    WHERE  e.genericexpenseid = p_genericexpenseid AND e.farmid = p_farmid AND e.isdeleted = FALSE
    FOR UPDATE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Expense % not found.', p_genericexpenseid;
    END IF;
    IF v_status = 'Approved' THEN RETURN; END IF;   -- idempotent
    IF v_status NOT IN ('Draft', 'Submitted') THEN
        RAISE EXCEPTION 'Expense cannot be approved from status %.', v_status;
    END IF;
    -- A Credit expense is owed in full (248's NULL would read as paid).
    UPDATE genericexpenses e
    SET    status = 'Approved', approvedby = p_approvedby,
           approvedat = (now() AT TIME ZONE 'utc'), updatedat = (now() AT TIME ZONE 'utc'),
           amountpaid = CASE WHEN e.paymentmethod = 'Credit' THEN 0 ELSE e.amountpaid END
    WHERE  e.genericexpenseid = p_genericexpenseid AND e.farmid = p_farmid;
    PERFORM public.spgenericexpense__post(p_genericexpenseid, p_farmid, 1, p_approvedby);
END
$fn$;

-- ------------------------------------------------------------- update -----
CREATE OR REPLACE FUNCTION public.spgenericexpense_update(
    p_genericexpenseid integer, p_farmid text, p_expensedate timestamp, p_genericexpensecategoryid integer,
    p_genericsupplierid integer, p_description text, p_amount numeric, p_paidto text, p_paymentmethod text,
    p_genericcashaccountid integer, p_receipturl text DEFAULT NULL, p_notes text DEFAULT NULL,
    p_amountpaid numeric DEFAULT NULL, p_duedate date DEFAULT NULL, p_updatedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
    e record;
    n record;
    v_now timestamp := (now() AT TIME ZONE 'utc');
    v_paidon boolean;        -- a supplier payment is applied to it
    v_money_changed boolean := FALSE;
BEGIN
    SELECT * INTO e FROM genericexpenses x
    WHERE  x.genericexpenseid = p_genericexpenseid AND x.farmid = p_farmid AND x.isdeleted = FALSE
    FOR UPDATE;
    IF e.genericexpenseid IS NULL THEN
        RAISE EXCEPTION 'Expense % not found.', p_genericexpenseid;
    END IF;
    IF e.sourcetype IS NOT NULL THEN
        RAISE EXCEPTION 'This expense was made by % -- change it there.', e.sourcetype;
    END IF;
    IF e.status NOT IN ('Draft', 'Submitted', 'Rejected', 'Approved') THEN
        RAISE EXCEPTION 'A % expense cannot be edited.', e.status;
    END IF;
    v_paidon := EXISTS (SELECT 1 FROM supplierpaymentallocation sa
                        WHERE sa.farmid = p_farmid AND sa.module = 'generic' AND sa.documenttype = 'Expense'
                          AND sa.documentid = p_genericexpenseid AND sa.status = 'Posted');

    IF e.status = 'Approved' AND v_paidon THEN
        -- Money is locked once a payment is applied: keep it, change the rest.
        UPDATE genericexpenses x
        SET    expensedate = COALESCE(p_expensedate, x.expensedate),
               genericexpensecategoryid = COALESCE(p_genericexpensecategoryid, x.genericexpensecategoryid),
               description = p_description, paidto = p_paidto,
               receipturl = COALESCE(p_receipturl, x.receipturl), notes = p_notes,
               duedate = CASE WHEN COALESCE(x.amountpaid, x.amount) >= x.amount THEN x.duedate ELSE p_duedate END,
               updatedat = v_now
        WHERE  x.genericexpenseid = p_genericexpenseid AND x.farmid = p_farmid;
        RETURN;
    END IF;

    SELECT * INTO n FROM public.fngenericexpense_normalise(p_farmid, p_amount, p_paymentmethod,
        p_genericcashaccountid, p_genericsupplierid, p_amountpaid);

    IF e.status = 'Approved' THEN
        v_money_changed := e.amount IS DISTINCT FROM p_amount
            OR e.paymentmethod IS DISTINCT FROM n.o_method
            OR e.genericcashaccountid IS DISTINCT FROM n.o_cashaccountid
            OR e.genericsupplierid IS DISTINCT FROM p_genericsupplierid
            OR COALESCE(e.amountpaid, e.amount) IS DISTINCT FROM COALESCE(n.o_amountpaid, p_amount);
        IF v_money_changed THEN
            PERFORM public.spgenericexpense__post(p_genericexpenseid, p_farmid, -1, p_updatedby);
        END IF;
    END IF;

    UPDATE genericexpenses x
    SET    expensedate = COALESCE(p_expensedate, x.expensedate),
           genericexpensecategoryid = COALESCE(p_genericexpensecategoryid, x.genericexpensecategoryid),
           genericsupplierid = p_genericsupplierid,
           description = p_description, amount = p_amount, paidto = p_paidto,
           paymentmethod = n.o_method, genericcashaccountid = n.o_cashaccountid,
           receipturl = COALESCE(p_receipturl, x.receipturl), notes = p_notes,
           amountpaid = n.o_amountpaid,
           duedate = CASE WHEN n.o_amountpaid IS NULL THEN NULL ELSE p_duedate END,
           status = CASE WHEN x.status = 'Rejected' THEN 'Draft' ELSE x.status END,
           rejectionreason = CASE WHEN x.status = 'Rejected' THEN NULL ELSE x.rejectionreason END,
           updatedat = v_now
    WHERE  x.genericexpenseid = p_genericexpenseid AND x.farmid = p_farmid;

    IF v_money_changed THEN
        PERFORM public.spgenericexpense__post(p_genericexpenseid, p_farmid, 1, p_updatedby);
    END IF;
END
$fn$;

-- ------------------------------------------------------------- delete -----
CREATE OR REPLACE FUNCTION public.spgenericexpense_delete(
    p_genericexpenseid integer, p_farmid text, p_reason text DEFAULT NULL, p_deletedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
    e record;
BEGIN
    SELECT * INTO e FROM genericexpenses x
    WHERE  x.genericexpenseid = p_genericexpenseid AND x.farmid = p_farmid AND x.isdeleted = FALSE
    FOR UPDATE;
    IF e.genericexpenseid IS NULL THEN
        RAISE EXCEPTION 'Expense % not found.', p_genericexpenseid;
    END IF;
    IF e.sourcetype IS NOT NULL THEN
        RAISE EXCEPTION 'This expense was made by % -- reverse it there.', e.sourcetype;
    END IF;
    IF e.status = 'Approved' THEN
        IF EXISTS (SELECT 1 FROM supplierpaymentallocation sa
                   WHERE sa.farmid = p_farmid AND sa.module = 'generic' AND sa.documenttype = 'Expense'
                     AND sa.documentid = p_genericexpenseid AND sa.status = 'Posted') THEN
            RAISE EXCEPTION 'A supplier payment is applied to this expense. Reverse that payment on Supplier Payments first.';
        END IF;
        PERFORM public.spgenericexpense__post(p_genericexpenseid, p_farmid, -1, p_deletedby);
    END IF;
    UPDATE genericexpenses x
    SET    isdeleted = TRUE,
           status = CASE WHEN x.status = 'Approved' THEN 'Cancelled' ELSE x.status END,
           rejectionreason = COALESCE(NULLIF(btrim(p_reason), ''), x.rejectionreason),
           updatedat = (now() AT TIME ZONE 'utc')
    WHERE  x.genericexpenseid = p_genericexpenseid AND x.farmid = p_farmid;
END
$fn$;

-- ------------------------------------------------ Cash Flow expense arm -----
-- Unchanged except one line: only Approved expenses (Draft / Rejected /
-- Cancelled moved no money).
CREATE OR REPLACE FUNCTION public.spgenericcashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, createdat timestamp without time zone)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);
    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);
BEGIN
    -- ---- 1. customer receipts ---------------------------------------------------
    -- Money received from customers against sales/invoices.
    RETURN QUERY
    SELECT 'Receipt'::text,
           FALSE,
           p.genericcustomerpaymentid,
           p.genericcashaccountid,
           NULL::text,
           p.paymentdate::timestamp,
           'CashIn'::text,
           'CustomerPayment'::text,
           p.genericcustomerpaymentid,
           FALSE,
           COALESCE(p.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(p.notes), ''),
               NULLIF(btrim(p.referenceno), ''),
               'Customer payment #' || p.genericcustomerpaymentid::text
           )::text,
           'OperatingIn'::text,
           p.createdat::timestamp
    FROM   genericcustomerpayments p
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) > 0
      AND  COALESCE(p.status, 'Posted') <> 'Reversed'
      AND  p.paymentdate::timestamp >= v_from
      AND  p.paymentdate::timestamp <= v_to;

    -- ---- 2. sale residuals (part paid at counter) -------------------------------
    -- A sale entered as already paid or partially paid. The residual is the
    -- amount paid that did NOT create a genericcustomerpayments row.
    RETURN QUERY
    SELECT 'SaleResidual'::text,
           FALSE,
           s.genericsaleid,
           s.genericcashaccountid,
           NULL::text,
           s.saledate::timestamp,
           'CashIn'::text,
           'Sale'::text,
           s.genericsaleid,
           FALSE,
           v.residual,
           ('Sale #' || s.genericsaleid::text ||
            COALESCE(' - ' || NULLIF(btrim(c.customername), ''), ''))::text,
           'OperatingIn'::text,
           s.createdat::timestamp
    FROM   genericsales s
    LEFT   JOIN genericcustomers c ON c.genericcustomerid = s.genericcustomerid
    CROSS  JOIN LATERAL (
        SELECT ROUND(
                   CASE WHEN COALESCE(s.paymentstatus, '') = 'Paid'
                        THEN COALESCE(s.totalamount, 0)
                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),
                                   COALESCE(s.totalamount, 0))
                   END
                 - COALESCE((SELECT SUM(pp.amount)
                             FROM   genericcustomerpayments pp
                             WHERE  pp.linkedsaleid = s.genericsaleid
                               AND  lower(pp.farmid::text) = lower(p_farmid)
                               AND  COALESCE(pp.status, 'Posted') <> 'Reversed'), 0)
               , 2) AS residual
    ) v
    WHERE  lower(s.farmid::text) = lower(p_farmid)
      AND  COALESCE(s.isdeleted, FALSE) = FALSE
      AND  v.residual > 0
      AND  s.saledate::timestamp >= v_from
      AND  s.saledate::timestamp <= v_to;

    -- ---- 3. expenses (all operational spending) ---------------------------------
    -- Every kind of spending: supplier payments, staff payments, recurring,
    -- purchases, etc. all INSERT INTO genericexpenses. NonCash (internal use)
    -- is excluded — that records stock leaving without money moving.
    RETURN QUERY
    SELECT 'Expense'::text,
           FALSE,
           e.genericexpenseid,
           e.genericcashaccountid,
           NULL::text,
           e.expensedate::timestamp,
           'CashOut'::text,
           'Expense'::text,
           e.genericexpenseid,
           FALSE,
           -COALESCE(e.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(e.description), ''), 'Expense')::text,
           'OperatingOut'::text,
           e.createdat::timestamp
    FROM   genericexpenses e
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(e.amount, 0) > 0
      AND  COALESCE(e.isdeleted, FALSE) = FALSE
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
      AND  COALESCE(e.status, 'Approved') = 'Approved'   -- 448
      AND  e.expensedate::timestamp >= v_from
      AND  e.expensedate::timestamp <= v_to;

    -- ---- 4. payroll (only paid runs WITHOUT a linked expense) --------------------
    -- If payroll creates a linked expense, the expense leg already counts it.
    -- Only add standalone paid payroll runs that have no genericexpenseid.
    IF to_regclass('public.genericpayrollruns') IS NOT NULL THEN
        RETURN QUERY EXECUTE format($sql$
            SELECT 'Payroll'::text,
                   FALSE,
                   pr.genericpayrollrunid,
                   pr.genericcashaccountid,
                   NULL::text,
                   COALESCE(pr.paidat, pr.createdat)::timestamp,
                   'CashOut'::text,
                   'Payroll'::text,
                   pr.genericpayrollrunid,
                   FALSE,
                   -COALESCE(pr.totalnetpay, 0)::numeric,
                   COALESCE(
                       NULLIF(btrim(pr.notes), ''),
                       'Payroll ' || to_char(pr.periodstart, 'DD Mon') || ' - ' || to_char(pr.periodend, 'DD Mon YYYY')
                   )::text,
                   'OperatingOut'::text,
                   pr.createdat::timestamp
            FROM   genericpayrollruns pr
            WHERE  lower(pr.farmid::text) = lower($1)
              AND  pr.status = 'Paid'
              AND  COALESCE(pr.totalnetpay, 0) > 0
              AND  COALESCE(pr.isdeleted, FALSE) = FALSE
              AND  NOT EXISTS (
                       SELECT 1 FROM genericexpenses e
                       WHERE  e.sourcetype = 'Payroll'
                         AND  e.sourceid = pr.genericpayrollrunid
                         AND  lower(e.farmid::text) = lower($1)
                         AND  COALESCE(e.isdeleted, FALSE) = FALSE
                   )
              AND  COALESCE(pr.paidat, pr.createdat)::timestamp >= $2
              AND  COALESCE(pr.paidat, pr.createdat)::timestamp <= $3
        $sql$)
        USING p_farmid, v_from, v_to;
    END IF;

    -- ---- 5. owner contributions (financing in) ----------------------------------
    RETURN QUERY
    SELECT 'OwnerContribution'::text,
           FALSE,
           oc.genericownerentryid,
           oc.genericcashaccountid,
           NULL::text,
           oc.entrydate::timestamp,
           'CashIn'::text,
           'OwnerInjection'::text,
           oc.genericownerentryid,
           FALSE,
           COALESCE(oc.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(oc.notes), ''),
               'Owner contribution' || COALESCE(' - ' || NULLIF(btrim(oc.ownername), ''), '')
           )::text,
           'FinancingIn'::text,
           oc.createdat::timestamp
    FROM   genericownercontributiondraws oc
    WHERE  lower(oc.farmid::text) = lower(p_farmid)
      AND  oc.entrytype = 'Contribution'
      AND  oc.status = 'Posted'
      AND  COALESCE(oc.amount, 0) > 0
      AND  oc.entrydate::timestamp >= v_from
      AND  oc.entrydate::timestamp <= v_to;

    -- ---- 6. owner draws (financing out) -----------------------------------------
    RETURN QUERY
    SELECT 'OwnerDraw'::text,
           FALSE,
           oc.genericownerentryid,
           oc.genericcashaccountid,
           NULL::text,
           oc.entrydate::timestamp,
           'CashOut'::text,
           'Withdrawal'::text,
           oc.genericownerentryid,
           FALSE,
           -COALESCE(oc.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(oc.notes), ''),
               'Owner draw' || COALESCE(' - ' || NULLIF(btrim(oc.ownername), ''), '')
           )::text,
           'FinancingOut'::text,
           oc.createdat::timestamp
    FROM   genericownercontributiondraws oc
    WHERE  lower(oc.farmid::text) = lower(p_farmid)
      AND  oc.entrytype = 'Draw'
      AND  oc.status = 'Posted'
      AND  COALESCE(oc.amount, 0) > 0
      AND  oc.entrydate::timestamp >= v_from
      AND  oc.entrydate::timestamp <= v_to;

    -- ---- 7. loans received (financing in) ---------------------------------------
    IF to_regclass('public."GenericLoans"') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'LoanReceived'::text,
               FALSE,
               l."GenericLoanId",
               l."GenericCashAccountId",
               NULL::text,
               COALESCE(l."LoanDate", l."CreatedAt")::timestamp,
               'CashIn'::text,
               'LoanReceived'::text,
               l."GenericLoanId",
               FALSE,
               COALESCE(l."AmountReceived", 0)::numeric,
               COALESCE(
                   NULLIF(btrim(l."Notes"), ''),
                   'Loan from ' || COALESCE(NULLIF(btrim(l."LenderName"), ''), 'unknown lender')
               )::text,
               'FinancingIn'::text,
               l."CreatedAt"::timestamp
        FROM   "GenericLoans" l
        WHERE  l."FarmId" = p_farmid
          AND  l."Status" IN ('Active', 'Paid')
          AND  COALESCE(l."AmountReceived", 0) > 0
          AND  COALESCE(l."LoanDate", l."CreatedAt")::timestamp >= v_from
          AND  COALESCE(l."LoanDate", l."CreatedAt")::timestamp <= v_to;
    END IF;

    -- ---- 8. loan repayments (financing out) -------------------------------------
    IF to_regclass('public."GenericLoanPayments"') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'LoanRepayment'::text,
               FALSE,
               lp."GenericLoanPaymentId",
               lp."GenericCashAccountId",
               NULL::text,
               lp."PaymentDate"::timestamp,
               'CashOut'::text,
               'LoanRepayment'::text,
               lp."GenericLoanPaymentId",
               FALSE,
               -COALESCE(lp."TotalPayment", 0)::numeric,
               COALESCE(
                   NULLIF(btrim(lp."Notes"), ''),
                   'Loan repayment #' || lp."GenericLoanPaymentId"::text
               )::text,
               'FinancingOut'::text,
               lp."CreatedAt"::timestamp
        FROM   "GenericLoanPayments" lp
        WHERE  lp."FarmId" = p_farmid
          AND  COALESCE(lp."IsReversed", FALSE) = FALSE
          AND  COALESCE(lp."TotalPayment", 0) > 0
          AND  lp."PaymentDate"::timestamp >= v_from
          AND  lp."PaymentDate"::timestamp <= v_to;
    END IF;

    -- ---- 9. legacy cash adjustments (shared table) ------------------------------
    -- The cashadjustment table is used by all rails for capital events before
    -- dedicated owner-money and loan tables existed. Include any that belong
    -- to this farm.
    IF to_regclass('public.cashadjustment') IS NOT NULL OR
       to_regclass('public.cashadjustments') IS NOT NULL THEN

        RETURN QUERY EXECUTE format($sql$
            SELECT 'Adjustment'::text,
                   FALSE,
                   ca.adjustmentid,
                   NULL::integer,
                   NULL::text,
                   ca.adjustmentdate,
                   CASE WHEN ca.amount >= 0 THEN 'CashIn' ELSE 'CashOut' END::text,
                   COALESCE(NULLIF(btrim(ca.adjustmenttype), ''), 'Adjustment')::text,
                   ca.adjustmentid,
                   FALSE,
                   ca.amount::numeric,
                   COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text,
                   CASE WHEN ca.amount >= 0 THEN 'FinancingIn' ELSE 'FinancingOut' END::text,
                   NULL::timestamp
            FROM   %s ca
            WHERE  lower(ca.farmid::text) = lower($1)
              AND  ca.amount <> 0
              AND  ca.adjustmentdate >= $2
              AND  ca.adjustmentdate <= $3
        $sql$, COALESCE(to_regclass('public.cashadjustment')::text,
                        to_regclass('public.cashadjustments')::text))
        USING p_farmid, v_from, v_to;
    END IF;
END;
$function$;


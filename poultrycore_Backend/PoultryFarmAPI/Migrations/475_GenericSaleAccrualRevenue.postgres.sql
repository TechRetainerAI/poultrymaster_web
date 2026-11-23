-- =============================================================================
-- 475_GenericSaleAccrualRevenue.postgres.sql
--
-- Move Generic sales from cash-basis to accrual-basis revenue recognition,
-- and unify the payment path so the initial payment at sale time creates the
-- same GenericCustomerPayment record as a later payment.
--
-- Before
-- ------
--   Sale approve wrote CashIn directly + SaleDebit for Balance only.
--   Customer Payments page did not show the initial payment.
--   Financial Activity conflated revenue with cash receipt.
--
-- After
-- -----
--   Sale approve:
--     1. Marks approved, writes inventory.
--     2. SaleDebit for FULL TotalAmount (accrual revenue).
--     3. Auto-creates GenericCustomerPayment for AmountPaid (if > 0),
--        immediately approved → CashIn + PaymentCredit ledger.
--     4. Credit auto-apply (from 473) reduces the net balance.
--
--   Financial Activity:
--     Sale event  = revenue = TotalAmount (what was earned).
--     Payment event = money in (what was collected). No revenue on payment.
--
--   Net customer balance:
--     SaleDebit(TotalAmount) - PaymentCredit(AmountPaid) - CreditApplied
--     = Balance - CreditApplied. Same as before.
--
--   Cash Flow:
--     Receipt from auto-created payment. SaleResidual stays for backward
--     compatibility (old sales without linked payments).
--
-- Double-entry protection
-- -----------------------
--   Idempotent: re-approving an already-Approved sale is a no-op.
--   The auto-created payment uses LinkedSaleId so duplicates are caught.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- =============================================================================
-- 1. Rewrite spgenericsale_approve — accrual revenue + auto-create payment
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spgenericsale_approve(
    p_genericsaleid integer,
    p_farmid text,
    p_approvedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_customerid integer;
    v_cashaccountid integer;
    v_amountpaid numeric;
    v_balance numeric;
    v_totalamount numeric;
    v_saledate timestamp;
    v_receiptnumber text;
    v_paymentmethod text;
    v_cashnewbalance numeric := NULL;
    v_cashallowneg boolean;
    v_cashcurrent numeric;
    v_customernewbalance numeric;
    v_customerbalance numeric;
    v_creditavailable numeric;
    v_creditapply numeric;
    v_netbalance numeric;
    v_paymentid integer;
    v_now timestamp := (now() at time zone 'utc');
BEGIN
    -- Idempotent
    IF EXISTS (SELECT 1 FROM genericsales s
               WHERE s.genericsaleid = p_genericsaleid AND s.farmid = p_farmid
                 AND s.status = 'Approved') THEN
        RETURN;
    END IF;

    SELECT s.status, s.genericcustomerid, s.genericcashaccountid,
           s.amountpaid, s.balance, s.totalamount, s.saledate,
           s.receiptnumber, s.paymentmethod
    INTO   v_status, v_customerid, v_cashaccountid,
           v_amountpaid, v_balance, v_totalamount, v_saledate,
           v_receiptnumber, v_paymentmethod
    FROM   genericsales s
    WHERE  s.genericsaleid = p_genericsaleid AND s.farmid = p_farmid
       AND s.isdeleted = FALSE
    LIMIT 1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Sale % not found.', p_genericsaleid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Sale cannot be approved from status %.', v_status;
    END IF;
    IF (v_amountpaid > 0 AND v_cashaccountid IS NULL) THEN
        RAISE EXCEPTION 'AmountPaid is greater than zero but no GenericCashAccountId is set.';
    END IF;
    -- A sale with any outstanding balance needs a customer for the receivable
    IF (v_balance > 0 AND v_customerid IS NULL) THEN
        RAISE EXCEPTION 'Sale has an unpaid balance but no customer is attached (credit sales require a customer).';
    END IF;

    -- Stock pre-flight
    IF EXISTS (
        SELECT 1
        FROM   genericsaleitems i
        INNER  JOIN genericproducts p
            ON p.genericproductid = i.genericproductid AND p.farmid = p_farmid
        WHERE  i.genericsaleid = p_genericsaleid
           AND i.itemtype = 'Product'
           AND p.trackinventory = TRUE
           AND p.currentstock - i.quantity < 0
    ) THEN
        RAISE EXCEPTION 'Insufficient stock for one or more products on this sale.';
    END IF;

    -- Cash pre-flight (for the auto-payment)
    IF (v_amountpaid > 0) THEN
        SELECT ca.allownegativebalance, ca.currentbalance
        INTO   v_cashallowneg, v_cashcurrent
        FROM   genericcashaccounts ca
        WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid
        LIMIT 1;

        IF v_cashcurrent IS NULL THEN
            RAISE EXCEPTION 'Cash account on the sale does not exist or belongs to another farm.';
        END IF;
        v_cashnewbalance := v_cashcurrent + v_amountpaid;
    END IF;

    -- =========================================================================
    -- Credit auto-apply check (from 473)
    -- =========================================================================
    v_creditapply := 0;
    IF (v_balance > 0 AND v_customerid IS NOT NULL) THEN
        SELECT c.currentbalance INTO v_customerbalance
        FROM   genericcustomers c
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

        IF v_customerbalance IS NOT NULL AND v_customerbalance < 0 THEN
            v_creditavailable := ABS(v_customerbalance);
            v_creditapply := LEAST(v_creditavailable, v_balance);
        END IF;
    END IF;

    -- =========================================================================
    -- TRANSACTION BODY
    -- =========================================================================

    -- 1. Mark sale approved
    UPDATE genericsales s
    SET    status = 'Approved', approvedby = p_approvedby,
           approvedat = v_now, updatedat = v_now
    WHERE  s.genericsaleid = p_genericsaleid AND s.farmid = p_farmid;

    -- 2. Inventory: SaleOut movements + decrement product stock
    INSERT INTO genericstockmovements (
        farmid, genericproductid, movementdate, movementtype, quantity,
        unitcost, unitsellingprice, totalcostvalue, referencetype, referenceid,
        reason, createdby, approvedby, approvedat
    )
    SELECT p_farmid, i.genericproductid, v_saledate, 'SaleOut', -i.quantity,
           p.costprice, i.unitprice, p.costprice * i.quantity, 'Sale', p_genericsaleid,
           'Sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
           p_approvedby, p_approvedby, v_now
    FROM   genericsaleitems i
    INNER  JOIN genericproducts p
        ON p.genericproductid = i.genericproductid AND p.farmid = p_farmid
    WHERE  i.genericsaleid = p_genericsaleid
       AND i.itemtype = 'Product'
       AND p.trackinventory = TRUE;

    UPDATE genericproducts p
    SET    currentstock = p.currentstock - x.qty,
           updatedat    = v_now
    FROM   (SELECT i.genericproductid, SUM(i.quantity) AS qty
            FROM   genericsaleitems i
            WHERE  i.genericsaleid = p_genericsaleid AND i.farmid = p_farmid
              AND  i.itemtype = 'Product'
            GROUP  BY i.genericproductid) x
    WHERE  x.genericproductid = p.genericproductid
       AND p.trackinventory = TRUE
       AND p.farmid = p_farmid;

    -- 3. Customer side: SaleDebit for FULL TotalAmount (accrual revenue).
    --    The payment will create a PaymentCredit to offset the paid portion.
    IF (v_customerid IS NOT NULL AND v_totalamount > 0) THEN
        SELECT c.currentbalance INTO v_customerbalance
        FROM   genericcustomers c
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

        v_customernewbalance := v_customerbalance + v_totalamount;

        INSERT INTO genericcustomerledger (
            farmid, genericcustomerid, transactiondate, transactiontype,
            saleid, debitamount, creditamount, balanceaftertransaction,
            description, createdby
        )
        VALUES (
            p_farmid, v_customerid, v_saledate, 'SaleDebit',
            p_genericsaleid, v_totalamount, 0, v_customernewbalance,
            'Sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby
        );

        UPDATE genericcustomers c
        SET    currentbalance = v_customernewbalance, updatedat = v_now
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;
    END IF;

    -- 4. Auto-create customer payment for AmountPaid (unified payment path).
    --    This creates the same GenericCustomerPayment row that a later payment
    --    would, so Customer Payments page shows all payments uniformly.
    IF (v_amountpaid > 0) THEN
        -- Insert as Draft then immediately approve (reuses the same ledger pattern)
        INSERT INTO genericcustomerpayments (
            farmid, genericcustomerid, paymentdate, amount, paymentmethod,
            genericcashaccountid, linkedsaleid, status, notes, createdby,
            paymentgroupid
        )
        VALUES (
            p_farmid,
            COALESCE(v_customerid, 0),  -- walk-in sales may not have a customer
            v_saledate,
            v_amountpaid,
            COALESCE(v_paymentmethod, 'Cash'),
            v_cashaccountid,
            p_genericsaleid,
            'Approved',   -- skip Draft for the auto-payment
            'Payment on sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby,
            gen_random_uuid()
        )
        RETURNING genericcustomerpaymentid INTO v_paymentid;

        -- Customer ledger: PaymentCredit (reduces the receivable)
        IF (v_customerid IS NOT NULL) THEN
            SELECT c.currentbalance INTO v_customerbalance
            FROM   genericcustomers c
            WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

            v_customernewbalance := v_customerbalance - v_amountpaid;

            INSERT INTO genericcustomerledger (
                farmid, genericcustomerid, transactiondate, transactiontype,
                paymentid, debitamount, creditamount, balanceaftertransaction,
                description, createdby
            )
            VALUES (
                p_farmid, v_customerid, v_saledate, 'PaymentCredit',
                v_paymentid, 0, v_amountpaid, v_customernewbalance,
                'Payment on sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
                p_approvedby
            );

            UPDATE genericcustomers c
            SET    currentbalance = v_customernewbalance, updatedat = v_now
            WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;
        END IF;

        -- Cash side: CashIn
        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, balanceaftertransaction, description,
            createdby, approvedby, approvedat
        )
        VALUES (
            p_farmid, v_cashaccountid, v_saledate, 'CashIn',
            'CustomerPayment', v_paymentid, v_amountpaid, v_cashnewbalance,
            'Payment on sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby, p_approvedby, v_now
        );

        UPDATE genericcashaccounts ca
        SET    currentbalance = v_cashnewbalance, updatedat = v_now
        WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid;
    END IF;

    -- 5. Credit auto-apply (from 473)
    IF (v_creditapply > 0 AND v_customerid IS NOT NULL) THEN
        SELECT c.currentbalance INTO v_customerbalance
        FROM   genericcustomers c
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

        v_customernewbalance := v_customerbalance + v_creditapply;

        INSERT INTO genericcustomerledger (
            farmid, genericcustomerid, transactiondate, transactiontype,
            saleid, debitamount, creditamount, balanceaftertransaction,
            description, createdby
        )
        VALUES (
            p_farmid, v_customerid, v_saledate, 'CreditApplied',
            p_genericsaleid, v_creditapply, 0, v_customernewbalance,
            'Credit applied to sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby
        );

        UPDATE genericcustomers c
        SET    currentbalance = v_customernewbalance, updatedat = v_now
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

        INSERT INTO genericcustomercreditapplications (
            farmid, genericcustomerid, genericsaleid, amountapplied,
            applicationdate, description, createdby
        )
        VALUES (
            p_farmid, v_customerid, p_genericsaleid, v_creditapply,
            v_saledate,
            'Auto-applied credit to sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby
        );

        -- Update sale to reflect the credit
        UPDATE genericsales s
        SET    amountpaid    = s.amountpaid + v_creditapply,
               balance       = GREATEST(s.balance - v_creditapply, 0),
               paymentstatus = CASE
                   WHEN (s.amountpaid + v_creditapply) >= s.totalamount THEN 'Paid'
                   WHEN (s.amountpaid + v_creditapply) > 0 THEN 'Partial'
                   ELSE s.paymentstatus
               END,
               updatedat     = v_now
        WHERE  s.genericsaleid = p_genericsaleid AND s.farmid = p_farmid;
    END IF;
END
$function$;

-- =============================================================================
-- 2. Rewrite fngenericfa_events — accrual revenue from sales
-- =============================================================================
-- Revenue is now recognized when the sale is approved (= TotalAmount),
-- NOT when cash is received. Payments are cash events only (money in).
-- =============================================================================

DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('fngenericfa_events', 'fngenericfa_positions',
                            'spgenericfinancialactivity_get', 'spgenericfinancialactivity_summary')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

CREATE FUNCTION public.fngenericfa_events(p_farmid text, p_from date, p_to date)
RETURNS TABLE(eventkey text, businessdate date, occurredat timestamp, createdat timestamp, activitytype text, type text,
              category text, description text, sourcetype text, sourceid int, sourcenumber text, moneyin numeric,
              moneyout numeric, revenue numeric, expense numeric, profitimpact numeric, iscash boolean,
              isnoncash boolean, istransfer boolean, cashaccountid int, partyname text, plline text, status text)
LANGUAGE sql STABLE AS $function$
    WITH legs AS (
        -- ---- cash: exactly the rows Generic Cash Flow sums ----------------------
        SELECT d.rowsource || ':' || d.sourcerowid AS k, d.transactiondate::date AS dt, d.createdat AS ca,
               d.rowsource AS st, d.sourcerowid AS sid, d.category AS cat, d.description AS descr,
               GREATEST(d.amount, 0) AS mi, GREATEST(-d.amount, 0) AS mo, 0::numeric AS rev, 0::numeric AS exp,
               d.cashaccountid AS acc, FALSE AS trf, 1 AS pri, NULL::text AS pl, NULL::text AS party, 'Posted'::text AS stat
        FROM   public.spgenericcashflow_detail(p_farmid, p_from::timestamp, (p_to + 1)::timestamp - interval '1 microsecond') d
        UNION ALL
        -- ---- ACCRUAL REVENUE: recognized at sale approval (475) -----------------
        -- Full TotalAmount as revenue, regardless of how much cash was collected.
        SELECT 'SaleRevenue:' || s.genericsaleid, s.saledate::date, s.createdat::timestamp,
               'SaleRevenue', s.genericsaleid, 'Sales',
               'Sale #' || s.genericsaleid || COALESCE(' - ' || NULLIF(btrim(c.customername), ''), ''),
               0, 0, COALESCE(s.totalamount, 0), 0, NULL::int, FALSE, 2, 'Sales Revenue',
               c.customername, s.status
        FROM   genericsales s
        LEFT   JOIN genericcustomers c ON c.genericcustomerid = s.genericcustomerid
        WHERE  lower(s.farmid::text) = lower(p_farmid)
          AND  s.status = 'Approved'
          AND  COALESCE(s.isdeleted, FALSE) = FALSE
          AND  s.saledate::date BETWEEN p_from AND p_to
        UNION ALL
        -- ---- expense legs (approved, non-deleted, non-NonCash) -------------------
        SELECT 'Expense:' || e.genericexpenseid, e.expensedate::date, e.createdat::timestamp,
               'Expense', e.genericexpenseid,
               COALESCE(NULLIF(btrim(ec.name), ''), 'Uncategorised'),
               COALESCE(NULLIF(btrim(e.description), ''), 'Expense'),
               0, 0, 0, e.amount, NULL, FALSE, 2,
               COALESCE(NULLIF(btrim(ec.name), ''), 'Uncategorised'),
               COALESCE(sup.suppliername, NULL), e.status
        FROM   genericexpenses e
        LEFT   JOIN genericexpensecategories ec ON ec.genericexpensecategoryid = e.genericexpensecategoryid
        LEFT   JOIN genericsuppliers sup ON sup.genericsupplierid = e.genericsupplierid
        WHERE  lower(e.farmid::text) = lower(p_farmid) AND COALESCE(e.amount, 0) > 0
          AND  COALESCE(e.isdeleted, FALSE) = FALSE
          AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
          AND  e.expensedate::date BETWEEN p_from AND p_to
        UNION ALL
        -- ---- loan interest and fees as expense ----------------------------------
        SELECT 'LoanRepayment:' || lp."GenericLoanPaymentId", lp."PaymentDate"::date, lp."CreatedAt"::timestamp,
               'LoanRepayment', lp."GenericLoanPaymentId", 'Loan repayments', 'Loan interest and fees',
               0, 0, 0, COALESCE(lp."InterestAmount", 0) + COALESCE(lp."FeeAmount", 0), NULL, FALSE, 2,
               'Loan Interest', NULL, CASE WHEN lp."IsReversed" THEN 'Reversed' ELSE 'Posted' END
        FROM   "GenericLoanPayments" lp
        WHERE  lp."FarmId" = p_farmid AND COALESCE(lp."IsReversed", FALSE) = FALSE
          AND  (COALESCE(lp."InterestAmount", 0) > 0 OR COALESCE(lp."FeeAmount", 0) > 0)
          AND  lp."PaymentDate"::date BETWEEN p_from AND p_to
        UNION ALL
        -- ---- internal transfers (no money enters or leaves) ---------------------
        SELECT 'CashTransfer:' || t.genericcashtransferid, t.transferdate::date, t.createdat::timestamp,
               'CashTransfer', t.genericcashtransferid, 'Transfers',
               'Transfer #' || t.genericcashtransferid,
               0, 0, 0, 0, t.fromgenericcashaccountid, TRUE, 3, NULL, NULL, t.status
        FROM   genericcashtransfers t
        WHERE  lower(t.farmid::text) = lower(p_farmid) AND t.status = 'Approved'
          AND  t.transferdate::date BETWEEN p_from AND p_to
    ), ev AS (
        SELECT l.k,
               MIN(l.dt) AS dt, MIN(l.ca) AS ca,
               (ARRAY_AGG(l.st ORDER BY l.pri))[1] AS st, (ARRAY_AGG(l.sid ORDER BY l.pri))[1] AS sid,
               (ARRAY_AGG(l.cat ORDER BY l.pri))[1] AS cat, (ARRAY_AGG(l.descr ORDER BY l.pri))[1] AS descr,
               SUM(l.mi) AS mi, SUM(l.mo) AS mo, SUM(l.rev) AS rev, SUM(l.exp) AS exp,
               MAX(l.acc) AS acc, BOOL_OR(l.trf) AS trf,
               (ARRAY_AGG(l.pl ORDER BY l.pl IS NULL, l.pri))[1] AS pl,
               (ARRAY_AGG(l.party ORDER BY l.party IS NULL, l.pri))[1] AS party,
               (ARRAY_AGG(l.stat ORDER BY l.pri DESC))[1] AS stat,
               BOOL_OR(l.pri = 1) AS hascash
        FROM   legs l GROUP BY l.k
    )
    SELECT e.k, e.dt, e.dt::timestamp, e.ca,
           CASE WHEN e.trf THEN 'Transfer'
                WHEN e.st LIKE 'OwnerContribution%' OR e.st LIKE 'OwnerDraw%' THEN 'Owner'
                WHEN e.st LIKE 'LoanReceived%' OR e.st LIKE 'LoanRepayment%' THEN 'Financing'
                WHEN e.st = 'Adjustment' THEN 'Financing'
                WHEN e.st = 'CashTransfer' THEN 'Transfer'
                ELSE 'Operating' END,
           CASE e.st
               WHEN 'Receipt' THEN 'Payment received'
               WHEN 'SaleResidual' THEN 'Sale payment'
               WHEN 'SaleRevenue' THEN 'Sale'
               WHEN 'Expense' THEN 'Expense'
               WHEN 'Payroll' THEN 'Payroll'
               WHEN 'OwnerContribution' THEN 'Owner contribution'
               WHEN 'OwnerDraw' THEN 'Owner draw'
               WHEN 'LoanReceived' THEN 'Loan received'
               WHEN 'LoanRepayment' THEN 'Loan repayment'
               WHEN 'CashTransfer' THEN 'Transfer'
               WHEN 'Adjustment' THEN 'Cash adjustment'
               WHEN 'PurchasePayment' THEN 'Purchase payment'
               WHEN 'SupplierPayment' THEN 'Supplier payment'
               ELSE COALESCE(e.st, 'Other') END,
           COALESCE(e.cat, 'Other'), e.descr, e.st, e.sid, e.st || ' #' || COALESCE(e.sid::text, ''),
           ROUND(e.mi, 2), ROUND(e.mo, 2), ROUND(e.rev, 2), ROUND(e.exp, 2), ROUND(e.rev - e.exp, 2),
           e.hascash AND (e.mi <> 0 OR e.mo <> 0),
           NOT (e.hascash AND (e.mi <> 0 OR e.mo <> 0)) AND NOT e.trf,
           e.trf, e.acc, e.party, e.pl, e.stat
    FROM   ev e;
$function$;

-- Recreate dependent functions
CREATE FUNCTION public.spgenericfinancialactivity_get(p_farmid text, p_from date, p_to date)
RETURNS TABLE(eventkey text, businessdate date, occurredat timestamp, createdat timestamp, activitytype text, type text,
              category text, description text, sourcetype text, sourceid int, sourcenumber text, moneyin numeric,
              moneyout numeric, revenue numeric, expense numeric, profitimpact numeric, runningcash numeric,
              iscash boolean, isnoncash boolean, istransfer boolean, cashaccountid int, cashaccountname text,
              partyname text, plline text, status text)
LANGUAGE sql STABLE AS $function$
    WITH opening AS (
        SELECT COALESCE(s.openingbalance, 0) AS bal
        FROM   public.spgenericcashflow_summary(p_farmid, p_from::timestamp, (p_to + 1)::timestamp - interval '1 microsecond') s
    )
    SELECT e.eventkey, e.businessdate, e.occurredat, e.createdat, e.activitytype, e.type, e.category, e.description,
           e.sourcetype, e.sourceid, e.sourcenumber, e.moneyin, e.moneyout, e.revenue, e.expense, e.profitimpact,
           ROUND((SELECT bal FROM opening)
                 + SUM(e.moneyin - e.moneyout) OVER (ORDER BY e.businessdate, e.createdat NULLS FIRST, e.eventkey
                                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2),
           e.iscash, e.isnoncash, e.istransfer, e.cashaccountid, a.accountname::text, e.partyname, e.plline, e.status
    FROM   public.fngenericfa_events(p_farmid, p_from, p_to) e
    LEFT   JOIN genericcashaccounts a ON a.genericcashaccountid = e.cashaccountid
    ORDER  BY e.businessdate, e.createdat NULLS FIRST, e.eventkey;
$function$;

CREATE FUNCTION public.spgenericfinancialactivity_summary(p_farmid text, p_from date, p_to date)
RETURNS TABLE(moneyin numeric, moneyout numeric, netcashflow numeric, openingcash numeric, closingcash numeric,
              revenue numeric, expense numeric, netprofit numeric, eventcount int, cashevents int, noncashevents int)
LANGUAGE sql STABLE AS $function$
    WITH cf AS (
        SELECT * FROM public.spgenericcashflow_summary(p_farmid, p_from::timestamp, (p_to + 1)::timestamp - interval '1 microsecond')
    ), ev AS (
        SELECT COALESCE(SUM(e.revenue), 0) AS rev, COALESCE(SUM(e.expense), 0) AS exp, COUNT(*) AS n,
               COUNT(*) FILTER (WHERE e.iscash) AS ncash, COUNT(*) FILTER (WHERE e.isnoncash) AS nnon
        FROM   public.fngenericfa_events(p_farmid, p_from, p_to) e
    )
    SELECT ROUND(cf.moneyin, 2), ROUND(cf.moneyout, 2), ROUND(cf.netcashflow, 2), ROUND(cf.openingbalance, 2),
           ROUND(cf.cashathand, 2), ROUND(ev.rev, 2), ROUND(ev.exp, 2), ROUND(ev.rev - ev.exp, 2),
           ev.n::int, ev.ncash::int, ev.nnon::int
    FROM   cf CROSS JOIN ev;
$function$;

CREATE FUNCTION public.fngenericfa_positions(p_farmid text, p_from date, p_to date)
RETURNS TABLE(eventkey text, positiontype text, positionname text, increaseamount numeric, decreaseamount numeric,
              explanation text)
LANGUAGE sql STABLE AS $function$
    WITH e AS (SELECT * FROM public.spgenericfinancialactivity_get(p_farmid, p_from, p_to))
    -- cash
    SELECT e.eventkey, 'Cash', COALESCE(e.cashaccountname, 'Cash'), e.moneyin, e.moneyout,
           CASE WHEN e.moneyin > 0 THEN 'Money received into this account.' ELSE 'Money paid out of this account.' END
    FROM   e WHERE e.iscash
    UNION ALL
    -- transfers
    SELECT e.eventkey, 'Cash', a.accountname::text,
           CASE WHEN a.genericcashaccountid = t.togenericcashaccountid THEN t.amount ELSE 0 END,
           CASE WHEN a.genericcashaccountid = t.fromgenericcashaccountid THEN t.amount ELSE 0 END,
           'Moved between the business''s own accounts; no money entered or left.'
    FROM   e JOIN genericcashtransfers t ON e.sourcetype = 'CashTransfer' AND t.genericcashtransferid = e.sourceid
    JOIN   genericcashaccounts a ON a.genericcashaccountid IN (t.fromgenericcashaccountid, t.togenericcashaccountid)
    UNION ALL
    -- customer receivable: sale creates it, payment reduces it
    SELECT e.eventkey, 'CustomerReceivable', COALESCE(e.partyname, 'Customers'), e.revenue, 0,
           'Revenue recognized; customer owes the full sale amount.'
    FROM   e WHERE e.sourcetype = 'SaleRevenue' AND e.revenue > 0
    UNION ALL
    SELECT e.eventkey, 'CustomerReceivable', COALESCE(e.partyname, 'Customers'), 0, e.moneyin,
           'Customer payment reduced what they owe.'
    FROM   e WHERE e.sourcetype IN ('Receipt', 'SaleResidual') AND e.moneyin > 0
    UNION ALL
    -- supplier payable from expenses
    SELECT e.eventkey, 'SupplierPayable', COALESCE(e.partyname, 'Supplier'), e.expense, 0,
           'An approved expense owed to the supplier.'
    FROM   e JOIN genericexpenses x ON e.sourcetype = 'Expense' AND x.genericexpenseid = e.sourceid
    WHERE  x.genericsupplierid IS NOT NULL AND COALESCE(x.amountpaid, 0) < x.amount
    UNION ALL
    -- supplier payable from purchases / supplier payments (474)
    SELECT e.eventkey, 'SupplierPayable', COALESCE(e.partyname, 'Supplier'), 0, e.moneyout,
           'Purchase or supplier payment reduced what is owed.'
    FROM   e WHERE e.sourcetype IN ('Purchase', 'SupplierPayment') AND e.moneyout > 0
    UNION ALL
    -- financing: loans
    SELECT e.eventkey, 'LoanLiability', 'Loans', e.moneyin, e.moneyout,
           'Borrowed money: owed back, so it is not income.'
    FROM   e WHERE e.sourcetype = 'LoanReceived'
    UNION ALL
    SELECT e.eventkey, 'LoanLiability', 'Loans', 0, GREATEST(e.moneyout - e.expense, 0),
           'The principal repaid lowers the debt; interest and fees are the cost.'
    FROM   e WHERE e.sourcetype = 'LoanRepayment'
    UNION ALL
    -- owner capital
    SELECT e.eventkey, 'OwnerCapital', 'Owner', e.moneyin, e.moneyout, 'Owner money is never income or expense.'
    FROM   e WHERE e.sourcetype IN ('OwnerContribution', 'OwnerDraw');
$function$;

COMMIT;

-- Verification
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname IN ('fngenericfa_events', 'fngenericfa_positions',
                'spgenericfinancialactivity_get', 'spgenericfinancialactivity_summary')) <> 4 THEN
        RAISE EXCEPTION '475 verification failed: FA functions missing';
    END IF;
    RAISE NOTICE '475: All functions verified.';
END $$;

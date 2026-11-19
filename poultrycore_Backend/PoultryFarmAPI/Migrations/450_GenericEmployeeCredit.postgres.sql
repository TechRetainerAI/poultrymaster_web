-- =============================================================================
-- 450_GenericEmployeeCredit.postgres.sql   (Report 40, Part 4)
--
-- Poultry 441 for Generic: money the business is KEEPING FOR A MEMBER OF STAFF
-- (a liability) -- the mirror of genericemployeeloans (staff owes us).
--
--   PayrollSaving   +credit  wage already on P&L (payroll gross)   cash no
--                   (posted by the payroll "Keep as employee credit" line --
--                    Report 40 Part 5; the column is here, the writer is there)
--   WagesOwed       +credit  P&L yes (NonCash 'Payroll' expense)   cash no
--   OpeningBalance  +credit  P&L no  (earned before the books)     cash no
--   Deposit         +credit  P&L no  (her own money)               cash IN
--   Payout          -credit  P&L no                                cash OUT
--
-- Append-only: the balance is SUM of Posted rows (Payout negative). A mistake
-- is reversed (status Reversed, plus a cash reversal for Deposit/Payout), never
-- deleted. Reversing money that was added is refused when it has already been
-- paid out. Cash Flow shows a reversed Deposit/Payout twice: the original on its
-- date and the reversal on the day it was reversed.
--
-- Generic's P&L (GenericProfitLoss.cs) counts payroll at GROSS when a run is
-- paid, so a payroll saving needs no extra expense row (unlike Poultry 441).
--
-- Deploy order: this migration, then the Farm API, then the web app. Idempotent.
-- =============================================================================

-- ------------------------------------------------------------ 1. the ledger --
CREATE TABLE IF NOT EXISTS genericemployeecredits (
    genericemployeecreditid  serial PRIMARY KEY,
    farmid                   varchar(450) NOT NULL,
    genericstaffid           integer NOT NULL REFERENCES genericstaff (genericstaffid),
    entrytype   text NOT NULL
                CHECK (entrytype IN ('PayrollSaving', 'WagesOwed', 'OpeningBalance', 'Deposit', 'Payout')),
    amount      numeric(14,2) NOT NULL CHECK (amount > 0),
    entrydate   date NOT NULL,
    genericcashaccountid  integer NULL REFERENCES genericcashaccounts (genericcashaccountid),
    paymentmethod         text NULL,
    expenseid             integer NULL,          -- WagesOwed: the NonCash payroll expense
    genericpayrollrunid   integer NULL,          -- PayrollSaving: where it came from (no FK on purpose)
    genericpayrollitemid  integer NULL,
    reference   text NULL,
    description text NULL,
    status      text NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),
    createdby   text NULL,
    createdat   timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby  text NULL,
    reversedat  timestamp NULL,
    reversalreason text NULL,
    CONSTRAINT ck_genericemployeecredits_cash
        CHECK ((entrytype IN ('Deposit', 'Payout') AND genericcashaccountid IS NOT NULL)
            OR (entrytype NOT IN ('Deposit', 'Payout') AND genericcashaccountid IS NULL)),
    CONSTRAINT ck_genericemployeecredits_payroll
        CHECK ((entrytype = 'PayrollSaving') = (genericpayrollrunid IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS ix_genericemployeecredits_staff ON genericemployeecredits (farmid, genericstaffid, status);
CREATE INDEX IF NOT EXISTS ix_genericemployeecredits_run ON genericemployeecredits (genericpayrollrunid) WHERE genericpayrollrunid IS NOT NULL;

-- ------------------------------------------------------------- 2. balance ----
CREATE OR REPLACE FUNCTION public.fngenericemployeecredit_balance(p_farmid text, p_genericstaffid integer)
RETURNS numeric LANGUAGE sql STABLE AS $function$
    SELECT COALESCE(SUM(CASE WHEN c.entrytype = 'Payout' THEN -c.amount ELSE c.amount END), 0)::numeric(14,2)
    FROM   genericemployeecredits c
    WHERE  c.farmid = p_farmid AND c.genericstaffid = p_genericstaffid AND c.status = 'Posted';
$function$;

-- The company's "Payroll" expense category (created once if missing).
CREATE OR REPLACE FUNCTION public.fngenericexpensecategory_payroll(p_farmid text)
RETURNS integer LANGUAGE plpgsql AS $function$
DECLARE v_id integer;
BEGIN
    SELECT c.genericexpensecategoryid INTO v_id FROM genericexpensecategories c
    WHERE  c.farmid = p_farmid AND lower(btrim(c.name)) = 'payroll'
    ORDER  BY c.genericexpensecategoryid LIMIT 1;
    IF v_id IS NULL THEN
        v_id := public.spgenericexpensecategory_insert(p_farmid, 'Payroll', 'Wages and salaries', TRUE);
    END IF;
    RETURN v_id;
END;
$function$;

-- --------------------------------------------- 3. add (opening, deposit, owed)
CREATE OR REPLACE FUNCTION public.spgenericemployeecredit_add(
    p_farmid text, p_genericstaffid integer, p_entrytype text, p_amount numeric,
    p_entrydate date DEFAULT NULL, p_genericcashaccountid integer DEFAULT NULL,
    p_paymentmethod text DEFAULT NULL, p_reference text DEFAULT NULL,
    p_description text DEFAULT NULL, p_createdby text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $function$
DECLARE
    v_type  text := NULLIF(btrim(p_entrytype), '');
    v_date  date := COALESCE(p_entrydate, ((now() at time zone 'utc'))::date);
    v_staff text;
    v_id    integer;
    v_expid integer;
    v_desc  text;
BEGIN
    IF v_type IS NULL OR v_type NOT IN ('OpeningBalance', 'Deposit', 'WagesOwed') THEN
        RAISE EXCEPTION 'Credit can be added as an opening balance, money handed in, or wages owed. Payroll savings are added by paying payroll.';
    END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'The amount must be more than zero.';
    END IF;
    SELECT btrim(s.firstname || ' ' || s.lastname) INTO v_staff FROM genericstaff s
    WHERE  s.genericstaffid = p_genericstaffid AND s.farmid = p_farmid AND NOT COALESCE(s.isdeleted, FALSE);
    IF v_staff IS NULL THEN RAISE EXCEPTION 'Staff member not found on this company.'; END IF;
    IF v_type = 'Deposit' AND p_genericcashaccountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account the money went into.';
    END IF;
    v_desc := COALESCE(NULLIF(btrim(p_description), ''),
                       CASE v_type WHEN 'OpeningBalance' THEN 'Opening employee credit'
                                   WHEN 'Deposit' THEN 'Money handed in to keep'
                                   ELSE 'Wages kept as employee credit' END);
    INSERT INTO genericemployeecredits
        (farmid, genericstaffid, entrytype, amount, entrydate, genericcashaccountid, paymentmethod,
         reference, description, createdby)
    VALUES (p_farmid, p_genericstaffid, v_type, round(p_amount, 2), v_date,
            CASE WHEN v_type = 'Deposit' THEN p_genericcashaccountid END,
            CASE WHEN v_type = 'Deposit' THEN NULLIF(btrim(p_paymentmethod), '') END,
            NULLIF(btrim(p_reference), ''), v_desc, p_createdby)
    RETURNING genericemployeecreditid INTO v_id;

    IF v_type = 'Deposit' THEN
        PERFORM public.fngenericcash_move(p_farmid, p_genericcashaccountid, round(p_amount, 2), v_date::timestamp,
            'EmployeeCreditDeposit', v_id, 'Employee credit: money from ' || v_staff, p_createdby);
    ELSIF v_type = 'WagesOwed' THEN
        -- Earned today and not paid: a payroll cost with no cash. NonCash, so Cash
        -- Flow and Supplier Balances skip it while the P&L counts it.
        INSERT INTO genericexpenses
            (farmid, expensedate, genericexpensecategoryid, description, amount, paymentmethod, status,
             sourcetype, sourceid, createdby, approvedby, approvedat, isdeleted)
        VALUES (p_farmid, v_date::timestamp, public.fngenericexpensecategory_payroll(p_farmid),
                left(v_staff || ' - ' || v_desc, 500), round(p_amount, 2), 'NonCash', 'Approved',
                'EmployeeCreditWages', v_id, p_createdby, p_createdby, (now() at time zone 'utc'), FALSE)
        RETURNING genericexpenseid INTO v_expid;
        UPDATE genericemployeecredits SET expenseid = v_expid WHERE genericemployeecreditid = v_id;
    END IF;
    RETURN v_id;
END;
$function$;

-- ------------------------------------------------------------- 4. pay out ----
CREATE OR REPLACE FUNCTION public.spgenericemployeecredit_payout(
    p_farmid text, p_genericstaffid integer, p_amount numeric, p_genericcashaccountid integer,
    p_entrydate date DEFAULT NULL, p_paymentmethod text DEFAULT NULL, p_reference text DEFAULT NULL,
    p_description text DEFAULT NULL, p_createdby text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $function$
DECLARE
    v_date  date := COALESCE(p_entrydate, ((now() at time zone 'utc'))::date);
    v_staff text;
    v_bal   numeric;
    v_id    integer;
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN RAISE EXCEPTION 'The amount must be more than zero.'; END IF;
    IF p_genericcashaccountid IS NULL THEN RAISE EXCEPTION 'Choose the cash account the money is paid from.'; END IF;
    SELECT btrim(s.firstname || ' ' || s.lastname) INTO v_staff FROM genericstaff s
    WHERE  s.genericstaffid = p_genericstaffid AND s.farmid = p_farmid FOR UPDATE;
    IF v_staff IS NULL THEN RAISE EXCEPTION 'Staff member not found on this company.'; END IF;
    v_bal := public.fngenericemployeecredit_balance(p_farmid, p_genericstaffid);
    IF round(p_amount, 2) > v_bal THEN
        RAISE EXCEPTION 'The business is only holding % for %.', v_bal, v_staff;
    END IF;
    INSERT INTO genericemployeecredits
        (farmid, genericstaffid, entrytype, amount, entrydate, genericcashaccountid, paymentmethod,
         reference, description, createdby)
    VALUES (p_farmid, p_genericstaffid, 'Payout', round(p_amount, 2), v_date, p_genericcashaccountid,
            NULLIF(btrim(p_paymentmethod), ''), NULLIF(btrim(p_reference), ''),
            COALESCE(NULLIF(btrim(p_description), ''), 'Employee credit paid out'), p_createdby)
    RETURNING genericemployeecreditid INTO v_id;
    PERFORM public.fngenericcash_move(p_farmid, p_genericcashaccountid, -round(p_amount, 2), v_date::timestamp,
        'EmployeeCreditPayout', v_id, 'Employee credit paid to ' || v_staff, p_createdby, TRUE);
    RETURN v_id;
END;
$function$;

-- ------------------------------------------------------------- 5. reverse ----
CREATE OR REPLACE FUNCTION public.fngenericemployeecredit_reverserow(p_farmid text, p_id integer, p_reason text, p_by text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    v_c     genericemployeecredits%ROWTYPE;
    v_staff text;
    v_bal   numeric;
BEGIN
    SELECT * INTO v_c FROM genericemployeecredits WHERE genericemployeecreditid = p_id AND farmid = p_farmid FOR UPDATE;
    IF v_c.genericemployeecreditid IS NULL THEN RAISE EXCEPTION 'Employee credit entry not found on this company.'; END IF;
    IF v_c.status <> 'Posted' THEN RAISE EXCEPTION 'This entry has already been reversed.'; END IF;
    SELECT btrim(s.firstname || ' ' || s.lastname) INTO v_staff FROM genericstaff s
    WHERE  s.genericstaffid = v_c.genericstaffid FOR UPDATE;
    IF v_c.entrytype <> 'Payout' THEN
        v_bal := public.fngenericemployeecredit_balance(p_farmid, v_c.genericstaffid);
        IF v_bal - v_c.amount < 0 THEN
            RAISE EXCEPTION 'Only % of %''s credit is left -- the rest has been paid out. Reverse the payout first.', v_bal, v_staff;
        END IF;
    END IF;
    IF v_c.entrytype IN ('Deposit', 'Payout') THEN
        PERFORM public.fngenericcash_move(p_farmid, v_c.genericcashaccountid,
            CASE WHEN v_c.entrytype = 'Deposit' THEN -v_c.amount ELSE v_c.amount END,
            (now() at time zone 'utc'), 'EmployeeCreditReversal', v_c.genericemployeecreditid,
            'Reversal: employee credit ' || lower(v_c.entrytype) || ' for ' || v_staff, p_by);
    END IF;
    IF v_c.entrytype = 'WagesOwed' AND v_c.expenseid IS NOT NULL THEN
        UPDATE genericexpenses SET isdeleted = TRUE, status = 'Cancelled', updatedat = (now() at time zone 'utc')
        WHERE  genericexpenseid = v_c.expenseid AND farmid = p_farmid;
    END IF;
    UPDATE genericemployeecredits
    SET    status = 'Reversed', reversedby = p_by, reversedat = (now() at time zone 'utc'),
           reversalreason = NULLIF(btrim(p_reason), '')
    WHERE  genericemployeecreditid = p_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericemployeecredit_reverse(
    p_farmid text, p_genericemployeecreditid integer, p_reason text, p_reversedby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE v_type text;
BEGIN
    IF NULLIF(btrim(p_reason), '') IS NULL THEN RAISE EXCEPTION 'Give a reason for the reversal.'; END IF;
    SELECT entrytype INTO v_type FROM genericemployeecredits
    WHERE  genericemployeecreditid = p_genericemployeecreditid AND farmid = p_farmid;
    IF v_type = 'PayrollSaving' THEN
        RAISE EXCEPTION 'This credit came from payroll. Reopen that payroll to take it back.';
    END IF;
    PERFORM public.fngenericemployeecredit_reverserow(p_farmid, p_genericemployeecreditid, p_reason, p_reversedby);
END;
$function$;

-- ------------------------------------------------------------- 6. readers ----
CREATE OR REPLACE FUNCTION public.spgenericemployeecredit_balances(p_farmid text)
RETURNS TABLE(genericstaffid integer, staffname text, staffrole text, isactive boolean,
              balance numeric, totalin numeric, totalpaidout numeric, lastentrydate date, entrycount integer)
LANGUAGE sql STABLE AS $function$
    SELECT s.genericstaffid, btrim(s.firstname || ' ' || s.lastname)::text, s.role::text,
           COALESCE(s.isactive, TRUE) AND NOT COALESCE(s.isdeleted, FALSE),
           COALESCE(SUM(CASE WHEN c.entrytype = 'Payout' THEN -c.amount ELSE c.amount END)
                    FILTER (WHERE c.status = 'Posted'), 0)::numeric(14,2),
           COALESCE(SUM(c.amount) FILTER (WHERE c.status = 'Posted' AND c.entrytype <> 'Payout'), 0)::numeric(14,2),
           COALESCE(SUM(c.amount) FILTER (WHERE c.status = 'Posted' AND c.entrytype = 'Payout'), 0)::numeric(14,2),
           MAX(c.entrydate), COUNT(c.genericemployeecreditid)::int
    FROM   genericstaff s
    JOIN   genericemployeecredits c ON c.genericstaffid = s.genericstaffid AND c.farmid = p_farmid
    WHERE  s.farmid = p_farmid
    GROUP  BY s.genericstaffid, s.firstname, s.lastname, s.role, s.isactive, s.isdeleted
    ORDER  BY 5 DESC, 2;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericemployeecredit_getall(p_farmid text, p_genericstaffid integer DEFAULT NULL)
RETURNS TABLE(genericemployeecreditid integer, genericstaffid integer, staffname text,
              entrytype text, amount numeric, signedamount numeric, runningbalance numeric,
              entrydate date, genericcashaccountid integer, accountname text,
              paymentmethod text, reference text, description text,
              genericpayrollrunid integer, payrollperiod text, expenseid integer,
              status text, createdby text, createdat timestamp,
              reversedby text, reversedat timestamp, reversalreason text)
LANGUAGE sql STABLE AS $function$
    SELECT c.genericemployeecreditid, c.genericstaffid, btrim(s.firstname || ' ' || s.lastname)::text,
           c.entrytype, c.amount,
           (CASE WHEN c.entrytype = 'Payout' THEN -c.amount ELSE c.amount END)::numeric(14,2),
           SUM(CASE WHEN c.status <> 'Posted' THEN 0 WHEN c.entrytype = 'Payout' THEN -c.amount ELSE c.amount END)
               OVER (PARTITION BY c.genericstaffid ORDER BY c.entrydate, c.createdat, c.genericemployeecreditid)::numeric(14,2),
           c.entrydate, c.genericcashaccountid, a.accountname::text, c.paymentmethod, c.reference, c.description,
           c.genericpayrollrunid,
           CASE WHEN r.genericpayrollrunid IS NOT NULL
                THEN to_char(r.periodstart, 'YYYY-MM-DD') || ' to ' || to_char(r.periodend, 'YYYY-MM-DD') END,
           c.expenseid, c.status, c.createdby, c.createdat, c.reversedby, c.reversedat, c.reversalreason
    FROM   genericemployeecredits c
    JOIN   genericstaff s ON s.genericstaffid = c.genericstaffid
    LEFT   JOIN genericcashaccounts a ON a.genericcashaccountid = c.genericcashaccountid
    LEFT   JOIN genericpayrollruns r ON r.genericpayrollrunid = c.genericpayrollrunid
    WHERE  c.farmid = p_farmid AND (p_genericstaffid IS NULL OR c.genericstaffid = p_genericstaffid)
    ORDER  BY c.entrydate DESC, c.createdat DESC, c.genericemployeecreditid DESC;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericemployeecredit_total(p_farmid text)
RETURNS TABLE(totalheld numeric, staffcount integer) LANGUAGE sql STABLE AS $function$
    SELECT COALESCE(SUM(b.balance), 0)::numeric(14,2), COUNT(*) FILTER (WHERE b.balance > 0)::int
    FROM   public.spgenericemployeecredit_balances(p_farmid) b;
$function$;

-- ------------------------------------------- 7. Cash Flow (449 body + 450) --
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
           -- 449: the part paid from supplier credit left with the advance
           -(COALESCE(e.amount, 0)
             - COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                         WHERE sa.module = 'generic' AND sa.documenttype = 'Expense'
                           AND sa.documentid = e.genericexpenseid AND sa.status = 'Posted'
                           AND sa.fromcredit), 0))::numeric,
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

    -- ---- 449a. supplier advances (the part of a payment not applied) -----------
    RETURN QUERY
    SELECT 'SupplierAdvance'::text,
           FALSE,
           sp.genericsupplierpaymentid,
           sp.genericcashaccountid,
           NULL::text,
           sp.paymentdate::timestamp,
           'CashOut'::text,
           'SupplierPayment'::text,
           sp.genericsupplierpaymentid,
           FALSE,
           -(sp.amount - COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                                   WHERE sa.farmid = sp.farmid AND sa.module = 'generic'
                                     AND sa.paymentid = sp.genericsupplierpaymentid
                                     AND sa.status = 'Posted' AND NOT sa.fromcredit), 0))::numeric,
           ('Supplier advance SP-' || lpad(sp.genericsupplierpaymentid::text, 5, '0'))::text,
           'OperatingOut'::text,
           sp.createdat::timestamp
    FROM   genericsupplierpayments sp
    WHERE  lower(sp.farmid::text) = lower(p_farmid)
      AND  public.fngenericsupplierpayment_isposted(sp.status, sp.sourcetype)
      AND  NOT public.fngenericsupplier_iscreditkind(sp.sourcetype)
      AND  sp.genericcashaccountid IS NOT NULL
      AND  sp.paymentdate::timestamp >= v_from
      AND  sp.paymentdate::timestamp <= v_to
      AND  sp.amount - COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                                 WHERE sa.farmid = sp.farmid AND sa.module = 'generic'
                                   AND sa.paymentid = sp.genericsupplierpaymentid
                                   AND sa.status = 'Posted' AND NOT sa.fromcredit), 0) > 0;

    -- ---- 449b. supplier refunds (money back from a supplier) -------------------
    RETURN QUERY
    SELECT 'SupplierRefund'::text,
           FALSE,
           r.refundid,
           r.genericcashaccountid,
           NULL::text,
           r.refunddate::timestamp,
           'CashIn'::text,
           'GenericSupplierRefund'::text,
           r.refundid,
           FALSE,
           r.amount::numeric,
           ('Supplier refund ' || r.refundnumber)::text,
           'OperatingIn'::text,
           r.createdat::timestamp
    FROM   genericsupplierrefunds r
    WHERE  lower(r.farmid::text) = lower(p_farmid)
      AND  r.status = 'Posted'
      AND  r.refunddate::timestamp >= v_from
      AND  r.refunddate::timestamp <= v_to;

    -- ---- 450. employee credit: money handed in (in), paid out (out), and the
    -- reversal of either on the day it was reversed ---------------------------
    RETURN QUERY
    SELECT 'EmployeeCredit'::text, FALSE, c.genericemployeecreditid, c.genericcashaccountid, NULL::text,
           CASE WHEN c.entrydate = c.createdat::date THEN c.createdat ELSE c.entrydate::timestamp END,
           CASE WHEN c.entrytype = 'Deposit' THEN 'CashIn' ELSE 'CashOut' END::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'EmployeeCreditDeposit' ELSE 'EmployeeCreditPayout' END::text,
           c.genericemployeecreditid, FALSE,
           (CASE WHEN c.entrytype = 'Deposit' THEN c.amount ELSE -c.amount END)::numeric,
           (CASE WHEN c.entrytype = 'Deposit' THEN 'Employee credit: money from ' ELSE 'Employee credit paid to ' END
             || btrim(s.firstname || ' ' || s.lastname))::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'OperatingIn' ELSE 'OperatingOut' END::text,
           c.createdat
    FROM   genericemployeecredits c JOIN genericstaff s ON s.genericstaffid = c.genericstaffid
    WHERE  lower(c.farmid::text) = lower(p_farmid) AND c.entrytype IN ('Deposit', 'Payout')
      AND  CASE WHEN c.entrydate = c.createdat::date THEN c.createdat ELSE c.entrydate::timestamp END BETWEEN v_from AND v_to;

    RETURN QUERY
    SELECT 'EmployeeCreditReversal'::text, FALSE, c.genericemployeecreditid, c.genericcashaccountid, NULL::text,
           c.reversedat,
           CASE WHEN c.entrytype = 'Deposit' THEN 'CashOut' ELSE 'CashIn' END::text,
           'EmployeeCreditReversal'::text, c.genericemployeecreditid, FALSE,
           (CASE WHEN c.entrytype = 'Deposit' THEN -c.amount ELSE c.amount END)::numeric,
           ('Reversal: employee credit ' || lower(c.entrytype) || ' for ' || btrim(s.firstname || ' ' || s.lastname))::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'OperatingOut' ELSE 'OperatingIn' END::text,
           c.reversedat
    FROM   genericemployeecredits c JOIN genericstaff s ON s.genericstaffid = c.genericstaffid
    WHERE  lower(c.farmid::text) = lower(p_farmid) AND c.entrytype IN ('Deposit', 'Payout')
      AND  c.status = 'Reversed' AND c.reversedat IS NOT NULL AND c.reversedat BETWEEN v_from AND v_to;

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

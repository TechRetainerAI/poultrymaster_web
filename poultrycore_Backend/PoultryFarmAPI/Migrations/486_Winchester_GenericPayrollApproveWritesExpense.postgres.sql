-- =============================================================================
-- 486_Winchester_GenericPayrollApproveWritesExpense.postgres.sql
--
-- Problem: approving a Generic payroll run put nothing on the Expenses page.
-- Poultry's approve has always written the run's linked expense (category
-- Payroll, matched by SourceType/SourceId), plus top-ups for the wages that
-- went to advances (309) and to employee credit (441). Unapprove, cancel and
-- delete take them away again. Migration 451 left that out for Generic on
-- purpose, because Generic's reports counted payroll from the run itself.
--
-- This migration gives Generic the same behaviour, fitted to Generic:
--
--   * On approve (and re-approve) the run's expense rows are written:
--       - "Payroll <period>"                       net pay
--       - "... - advances repaid from wages"       loan / advance deductions
--       - "... - wages kept as employee credit"    EmployeeCredit deductions
--       - "... - other deductions"                 the rest of gross pay
--     so the rows add up to the run's GROSS pay (what Generic P&L counted
--     before this migration, unchanged).
--   * sourcetype = 'GenericPayrollRun', sourceid = the run. That is the marker
--     Generic P&L (GenericProfitLoss.cs) and spgenericreport_pnl_breakdown
--     already look for: when the linked expense exists they stop counting the
--     run separately, so wages are never counted twice.
--   * paymentmethod = 'NonCash' (paymentstatus, a generated column, follows). In Generic the money leaves
--     the cash account when the run is MARKED PAID (spgenericpayrollrun_markpaid
--     writes the CashOut). So Cash Flow, Financial Activity and the Daily
--     Closing keep reading the payment, not the expense, and nothing about cash
--     changes. Supplier payables skip rows with a sourcetype.
--   * Category "Payroll" is created for the business when it is missing.
--   * The Expenses page refuses to edit or delete rows with a sourcetype
--     ("This expense was made by ... -- change it there"); the run owns them.
--   * Reopen and cancel (both go through fngenericpayrollrun_reversepostings)
--     remove the rows. Delete is only allowed on runs that are not approved,
--     so it never finds any.
--   * Daily Closing: these rows are excluded from "expenses for the day", the
--     same way internal use is, because they moved no cash that day.
--   * Run details (rs5) now return the linked expense, as Poultry's do.
--   * Backfill: every Approved or Paid run that has no rows yet gets them.
--
-- Functions are changed by patching their LIVE body (pg_get_functiondef), so
-- nothing another migration added to them is lost. Each patch is checked and
-- is skipped when it is already applied, so this file can run twice.
-- No BEGIN/COMMIT (RunMigration wraps the file).
-- =============================================================================

-- ------------------------------------------------- 1. the Payroll category --
CREATE OR REPLACE FUNCTION public.spgenericexpensecategory_ensurepayroll(p_farmid text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id integer;
BEGIN
    SELECT c.genericexpensecategoryid INTO v_id
    FROM   genericexpensecategories c
    WHERE  c.farmid = p_farmid AND lower(btrim(c.name)) = 'payroll' AND COALESCE(c.isdeleted, FALSE) = FALSE
    ORDER  BY c.genericexpensecategoryid
    LIMIT  1;

    IF v_id IS NULL THEN
        INSERT INTO genericexpensecategories (farmid, name, description)
        VALUES (p_farmid, 'Payroll', 'Wages from approved payroll runs. Written by the payroll run.')
        RETURNING genericexpensecategoryid INTO v_id;
    END IF;

    RETURN v_id;
END;
$function$;

-- ------------------------------------- 2. write / remove a run's expenses --
-- Replaces whatever rows the run already has, so re-approving after a reopen
-- (with different lines) leaves exactly one set.
CREATE OR REPLACE FUNCTION public.fngenericpayrollrun_postexpenses(
    p_genericpayrollrunid integer, p_farmid text, p_by text DEFAULT NULL::text,
    p_expdate date DEFAULT NULL::date, p_desc text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_run     record;
    v_cat     integer;
    v_date    timestamp;
    v_desc    text;
    v_net     numeric(14,2);
    v_loans   numeric(14,2);
    v_credit  numeric(14,2);
    v_other   numeric(14,2);
    v_now     timestamp := (now() at time zone 'utc');
BEGIN
    SELECT r.* INTO v_run
    FROM   genericpayrollruns r
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payroll run not found for this business.';
    END IF;

    v_date := COALESCE(p_expdate, v_run.paydate, (v_run.approvedat)::date, v_now::date)::timestamp;
    v_desc := COALESCE(p_desc, concat('Payroll ', to_char(v_run.periodstart, 'YYYY-MM-DD'), ' to ',
                                      to_char(v_run.periodend, 'YYYY-MM-DD')));

    SELECT COALESCE(SUM(d.amount) FILTER (WHERE d.deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment')), 0),
           COALESCE(SUM(d.amount) FILTER (WHERE d.deductiontype = 'EmployeeCredit'), 0)
    INTO   v_loans, v_credit
    FROM   genericpayrollitemdeductions d
    WHERE  d.genericpayrollrunid = p_genericpayrollrunid AND d.farmid = p_farmid;

    v_net   := GREATEST(COALESCE(v_run.totalnetpay, 0), 0);
    v_other := GREATEST(COALESCE(v_run.totalgrosspay, 0) - v_net - v_loans - v_credit, 0);

    DELETE FROM genericexpenses e
    WHERE  e.farmid = p_farmid AND e.sourcetype = 'GenericPayrollRun' AND e.sourceid = p_genericpayrollrunid;

    v_cat := public.spgenericexpensecategory_ensurepayroll(p_farmid);

    -- The net row is written even at 0, so the run always has its linked expense
    -- (and P&L never falls back to counting the run as well).
    INSERT INTO genericexpenses
        (farmid, expensedate, genericexpensecategoryid, description, amount, paidto,
         paymentmethod, status, notes, createdby, approvedby, approvedat, createdat,
         isdeleted, sourcetype, sourceid, amountpaid, periodstart, periodend)
    SELECT p_farmid, v_date, v_cat, x.descr, x.amount, 'Staff',
           'NonCash', 'Approved', 'Written by payroll run #' || p_genericpayrollrunid,
           p_by, p_by, v_now, v_now,
           FALSE, 'GenericPayrollRun', p_genericpayrollrunid, x.amount,
           v_run.periodstart, v_run.periodend
    FROM (VALUES
            (1, v_desc,                                       v_net),
            (2, v_desc || ' - advances repaid from wages',    v_loans),
            (3, v_desc || ' - wages kept as employee credit', v_credit),
            (4, v_desc || ' - other deductions',              v_other)
         ) AS x(ord, descr, amount)
    WHERE x.ord = 1 OR x.amount > 0
    ORDER BY x.ord;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fngenericpayrollrun_removeexpenses(p_genericpayrollrunid integer, p_farmid text)
RETURNS void
LANGUAGE sql
AS $function$
    DELETE FROM genericexpenses e
    WHERE  e.farmid = p_farmid AND e.sourcetype = 'GenericPayrollRun' AND e.sourceid = p_genericpayrollrunid;
$function$;

-- --------------------------------------------- 3. patch the live functions --
DO $patch$
DECLARE
    v_def text;
    v_new text;
    v_old text;
    v_rep text;
BEGIN
    -- 3a. approve: write the expenses once the loan / credit postings are done.
    v_def := pg_get_functiondef('public.spgenericpayrollrun_approve(integer,text,text)'::regprocedure);
    IF position('fngenericpayrollrun_postexpenses' IN v_def) = 0 THEN
        v_old := '    -- Other deductions post nothing but should not stay ''Draft'' on an approved run.';
        IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
            RAISE EXCEPTION '486: spgenericpayrollrun_approve is not the expected shape (marker missing).';
        END IF;
        v_rep := '    -- 486: the run''s linked expenses (net pay + top-ups = gross), like Poultry.' || chr(10) ||
                 '    PERFORM public.fngenericpayrollrun_postexpenses(p_genericpayrollrunid, p_farmid, p_approvedby, v_expdate, v_desc);' || chr(10) || chr(10) ||
                 v_old;
        v_new := replace(v_def, v_old, v_rep);
        v_new := replace(v_new,
            '    -- No expense row: Generic P&L counts the run''s gross pay once it is Paid.',
            '    -- 486: the kept wages are also written as a Payroll expense top-up (see below).');
        EXECUTE v_new;
    END IF;

    -- 3b. reopen / cancel: take the expenses away with the other postings.
    v_def := pg_get_functiondef('public.fngenericpayrollrun_reversepostings(integer,text,text,text,text)'::regprocedure);
    IF position('fngenericpayrollrun_removeexpenses' IN v_def) = 0 THEN
        v_old := '    -- Other deductions posted nothing; make them editable again too.';
        IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
            RAISE EXCEPTION '486: fngenericpayrollrun_reversepostings is not the expected shape (marker missing).';
        END IF;
        v_rep := '    -- 486: the run''s linked expenses go with it.' || chr(10) ||
                 '    PERFORM public.fngenericpayrollrun_removeexpenses(p_genericpayrollrunid, p_farmid);' || chr(10) || chr(10) ||
                 v_old;
        EXECUTE replace(v_def, v_old, v_rep);
    END IF;

    -- 3c. daily closing: these rows moved no cash that day.
    v_def := pg_get_functiondef('public.spgenericdailyclosing_submit(integer,text,numeric,text,text,text)'::regprocedure);
    IF position('''GenericPayrollRun''' IN v_def) = 0 THEN
        v_old := 'COALESCE(e.sourcetype, '''') <> ''GenericInternalUsage'' AND e.farmid = p_farmid';
        IF position(v_old IN v_def) = 0 THEN
            RAISE EXCEPTION '486: spgenericdailyclosing_submit is not the expected shape (marker missing).';
        END IF;
        EXECUTE replace(v_def, v_old,
            'COALESCE(e.sourcetype, '''') NOT IN (''GenericInternalUsage'', ''GenericPayrollRun'') AND e.farmid = p_farmid');
    END IF;
END
$patch$;

-- ------------------------------------------- 4. run details: linked expense --
-- Same columns as before (and as Poultry's rs5); the net-pay row.
CREATE OR REPLACE FUNCTION public.spgenericpayrollrun_getdetailswithytd_rs5(p_genericpayrollrunid integer, p_farmid text)
 RETURNS TABLE(expenseid integer, farmid text, expensedate timestamp without time zone, category text, description text, amount numeric, paymentmethod text, sourcetype text, sourceid integer, createddate timestamp without time zone)
 LANGUAGE sql
AS $function$
    SELECT e.genericexpenseid, e.farmid::text, e.expensedate, c.name::text, e.description::text,
           e.amount, e.paymentmethod::text, e.sourcetype, e.sourceid, e.createdat
    FROM   genericexpenses e
    LEFT   JOIN genericexpensecategories c ON c.genericexpensecategoryid = e.genericexpensecategoryid
    WHERE  e.farmid = p_farmid AND e.sourcetype = 'GenericPayrollRun'
      AND  e.sourceid = p_genericpayrollrunid AND e.isdeleted = FALSE
    ORDER  BY e.genericexpenseid
    LIMIT  1;
$function$;

-- --------------------------------------------------------------- 5. backfill --
DO $backfill$
DECLARE
    v_r record;
BEGIN
    FOR v_r IN
        SELECT r.genericpayrollrunid, r.farmid, r.approvedby
        FROM   genericpayrollruns r
        WHERE  r.status IN ('Approved', 'Paid') AND COALESCE(r.isdeleted, FALSE) = FALSE
          AND  NOT EXISTS (SELECT 1 FROM genericexpenses e
                           WHERE e.farmid = r.farmid AND e.sourcetype = 'GenericPayrollRun'
                             AND e.sourceid = r.genericpayrollrunid)
    LOOP
        PERFORM public.fngenericpayrollrun_postexpenses(v_r.genericpayrollrunid, v_r.farmid, v_r.approvedby);
    END LOOP;
END
$backfill$;

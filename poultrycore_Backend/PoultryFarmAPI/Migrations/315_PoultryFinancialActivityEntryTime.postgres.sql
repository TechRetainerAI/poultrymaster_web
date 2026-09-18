-- =============================================================================
-- 315_PoultryFinancialActivityEntryTime.postgres.sql
--
-- Purpose
-- -------
-- Make every row on Financial Activity able to say WHEN it was entered.
--
-- THE SYMPTOM
-- ===========
-- Most rows showed a date and no time. On one company, 15 of 18:
--
--     Sale                          6 rows    no time
--     PoultryRawMaterialPurchase    4 rows    no time
--     Cash In                       3 rows    no time
--     MainFlockBatch                1 row     no time
--     OwnerInjection                1 row     no time
--     CashTransfer                  1 row     11:58
--     CustomerPayment               2 rows    12:45
--
-- THE CAUSE
-- =========
-- `occurredat` is each source's BUSINESS DATE. A business date entered as a day
-- is stored at midnight, so only the sources whose business-date column happens
-- to record a clock time -- cash transactions -- ever had one to show. The page
-- then suppresses a 00:00 rather than printing a midnight nobody recorded,
-- which is right, and leaves the row with no time at all, which is the gap.
--
-- THE FIX, AND WHY IT IS A NEW COLUMN RATHER THAN A BETTER occurredat
-- ===================================================================
-- The house rule, stated twice by the owner: a date and a time are not
-- replacements for one another. PRESERVE the business date, ADD the entry time.
-- So this adds `createdat` beside `occurredat` and changes neither the value nor
-- the meaning of anything that already existed.
--
-- There is a harder reason too. `occurredat` ORDERS this report -- it is in the
-- window that computes Running Cash, and in the array_agg that picks which leg
-- an event takes its metadata from. Folding an entry time into it would reorder
-- rows and therefore CHANGE A FINANCIAL FIGURE. Every ordering below is
-- byte-for-byte what it was.
--
-- WHERE EACH LEG'S TIME COMES FROM
-- ================================
--   A  cash        r.createdat      sppoultrycashflow_rows already returns it
--                                   (302) -- it was simply never carried through
--   B  revenue     sale.createddate joined back from the revenue line
--   C  expense     expense.createddate            "
--   D  transfers   t.createdat
--   E  payroll     r.createdat      the employee-loan leg (305-312)
--
-- The two P&L line functions carry the business date but not the entry time, and
-- widening THEM would change what the P&L report itself reads. The source row is
-- one join away in both cases, so the join goes here where the need is.
--
-- BUILT FROM THE LIVE FUNCTION, NOT FROM 290
-- ==========================================
-- The deployed `fnpoultryfa_events` has FIVE legs; the repo's 290 has four. The
-- fifth is the employee-loan repayment leg from migrations 305-312, which live
-- on `origin/Gyimah` and are applied to this database but exist in no file on
-- this branch. Rebuilding from 290 would have silently deleted a leg that is
-- carrying real payroll events. This file is the deployed body plus one column.
--
-- EFFECT ON TODAY'S NUMBERS: none. One added column; every existing column, row
-- and ordering is unchanged, and the check file asserts that row by row.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- Both gain a column, so both are dropped BY NAME and rebuilt: a RETURNS TABLE
-- cannot be widened by CREATE OR REPLACE, and dropping by a guessed signature
-- drops nothing and leaves an ambiguous overload behind it.
DO $drop$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure::text AS sig
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('fnpoultryfa_events', 'sppoultryfinancialactivity_get')
    LOOP
        -- No CASCADE. Nothing hard-depends on these (checked: 0 views), and if
        -- something ever does, the drop should FAIL loudly rather than quietly
        -- take the dependant with it.
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
        RAISE NOTICE '315: dropped %', r.sig;
    END LOOP;
END
$drop$;

CREATE OR REPLACE FUNCTION public.fnpoultryfa_events(p_farmid text, p_from date, p_to date)
 RETURNS TABLE(eventkey text, businessdate date, occurredat timestamp without time zone, createdat timestamp without time zone, activitytype text, type text, category text, description text, sourcetype text, sourceid integer, sourcenumber text, moneyin numeric, moneyout numeric, revenue numeric, expense numeric, profitimpact numeric, iscash boolean, isnoncash boolean, istransfer boolean, cashaccountid integer, partyname text, plline text, status text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH legs AS (
        -- ---- leg A: cash -----------------------------------------------------
        -- sppoultrycashflow_rows is the authority. It already resolves receipts
        -- against sale residuals, expense-at-entry against later supplier
        -- payments, drops reversed rows and excludes NonCash. Re-deriving any of
        -- that here is how the two reports would start disagreeing.
        SELECT CASE r.sourcetype
                   WHEN 'CustomerPayment'   THEN 'CustomerPayment:' || r.sourcerowid
                   WHEN 'Sale'              THEN 'Sale:'            || r.sourceid
                   WHEN 'Expense'           THEN 'Expense:'         || r.sourceid
                   WHEN 'ExpensePayment'    THEN 'SupplierPayment:' || r.sourcerowid
                   WHEN 'OwnerContribution' THEN 'OwnerMoney:'      || r.sourcerowid
                   WHEN 'OwnerDraw'         THEN 'OwnerMoney:'      || r.sourcerowid
                   WHEN 'LoanReceived'      THEN 'Loan:'            || r.sourceid
                   WHEN 'LoanRepayment'     THEN 'LoanPayment:'     || r.sourcerowid
                   ELSE 'Cash:' || r.rowsource || ':' || r.sourcerowid
               END                                        AS eventkey,
               2                                          AS metapri,
               r.transactiondate::date                    AS businessdate,
               r.transactiondate                          AS occurredat,
               r.createdat                                AS createdat,
               CASE r.sourcetype
                   WHEN 'ExpensePayment' THEN 'SupplierPayment'
                   WHEN 'LoanRepayment'  THEN 'LoanPayment'
                   ELSE r.sourcetype
               END                                        AS src,
               NULL::text                                 AS costtype,
               r.description                              AS description,
               r.sourceid                                 AS sourceid,
               NULL::text                                 AS sourcenumber,
               GREATEST(r.amount, 0)                      AS moneyin,
               GREATEST(-r.amount, 0)                     AS moneyout,
               0::numeric                                 AS revenue,
               0::numeric                                 AS expense,
               FALSE                                      AS istransfer,
               r.cashaccountid                            AS cashaccountid,
               NULL::text                                 AS partyname,
               NULL::text                                 AS plline,
               'Posted'::text                             AS status
        FROM   public.sppoultrycashflow_rows(
                   p_farmid,
                   p_from::timestamp,
                   ((p_to + 1)::timestamp - interval '1 microsecond')) r
        WHERE  r.amount <> 0

        UNION ALL

        -- ---- leg B: revenue --------------------------------------------------
        -- Recognised when the SALE happened, not when it was paid. A credit sale
        -- is revenue today with no cash; a collection months later is cash with
        -- no revenue. Both are the point of this report.
        SELECT 'Sale:' || v.saleid,
               1,
               v.saledate::date,
               v.saledate,
               sc.createddate,
               'Sale',
               NULL::text,
               ('Sale #' || v.saleid ||
                COALESCE(' - ' || NULLIF(btrim(v.customername), ''), '') ||
                COALESCE(' (' || NULLIF(btrim(v.product), '') || ')', '')),
               v.saleid,
               ('#' || v.saleid)::text,
               0::numeric,
               0::numeric,
               COALESCE(v.totalamount, 0),
               0::numeric,
               FALSE,
               NULL::integer,
               NULLIF(btrim(v.customername), ''),
               v.revenueline,
               'Posted'::text
        FROM   public.fnpoultrypl_revenuelines(p_farmid, p_from, p_to) v
        -- The line function carries the business date but not the entry
        -- time, and widening it would change the P&L's own reads. The sale
        -- row is one join away and knows when it was typed.
        LEFT   JOIN sale sc ON sc.saleid = v.saleid

        UNION ALL

        -- ---- leg C: expense --------------------------------------------------
        -- The expense table is this database's single P&L expense ledger:
        -- consumption recognition, depreciation, loan interest, payroll and
        -- internal use all post there, already classified by 272's functions.
        --
        -- EXCLUDED rows are still emitted, at zero. A capital asset and a
        -- deferred inventory purchase move cash and must appear as events, and
        -- this leg is the only one that knows what kind of event they are -- but
        -- neither is an expense, so the amount is zeroed rather than the row
        -- dropped. That is exactly the "cash moved, profit did not" case.
        SELECT CASE WHEN e.sourcetype = 'LoanPayment'
                    THEN 'LoanPayment:' || e.sourceid
                    ELSE 'Expense:'     || e.expenseid
               END,
               -- The cash leg names a loan repayment better than its interest
               -- line does, so it wins the wording for that one event only.
               CASE WHEN e.sourcetype = 'LoanPayment' THEN 3 ELSE 1 END,
               e.expensedate::date,
               e.expensedate,
               ec.createddate,
               COALESCE(NULLIF(btrim(e.sourcetype), ''), 'Expense'),
               e.costtype,
               COALESCE(NULLIF(btrim(e.description), ''), e.category),
               e.expenseid,
               NULL::text,
               0::numeric,
               0::numeric,
               0::numeric,
               CASE WHEN e.plsection = 'Excluded' THEN 0::numeric ELSE COALESCE(e.amount, 0) END,
               FALSE,
               NULL::integer,
               NULLIF(btrim(e.suppliername), ''),
               e.plline,
               'Posted'::text
        FROM   public.fnpoultrypl_expenselines(p_farmid, p_from, p_to) e
        LEFT   JOIN expense ec ON ec.expenseid = e.expenseid

        UNION ALL

        -- ---- leg D: internal transfers --------------------------------------
        -- Neither in nor out at company level: the farm's own money changed
        -- pocket. Carried so the timeline is complete and so the account legs
        -- can be shown in the position detail, with both cash columns at zero so
        -- it cannot inflate Money In / Money Out. Cash Flow omits transfers for
        -- the same reason, which is what keeps the two Net Cash Flows equal.
        SELECT 'CashTransfer:' || t.poultrycashtransferid,
               1,
               t.transferdate::date,
               t.transferdate,
               t.createdat,
               'CashTransfer',
               NULL::text,
               COALESCE(NULLIF(btrim(t.notes), ''),
                        'Transfer ' || COALESCE(fa.accountname, 'account') ||
                        ' to ' || COALESCE(ta.accountname, 'account')),
               t.poultrycashtransferid,
               NULLIF(btrim(t.transfernumber), ''),
               0::numeric,
               0::numeric,
               0::numeric,
               0::numeric,
               TRUE,
               t.frompoultrycashaccountid,
               NULL::text,
               NULL::text,
               t.status::text
        FROM   poultrycashtransfers t
        LEFT   JOIN poultrycashaccounts fa ON fa.poultrycashaccountid = t.frompoultrycashaccountid
        LEFT   JOIN poultrycashaccounts ta ON ta.poultrycashaccountid = t.topoultrycashaccountid
        WHERE  t.farmid = p_farmid
          -- 'Approved' is the only status in which the money has actually moved.
          -- The workflow is Draft -> Approved -> Reversed (252); a Draft has not
          -- moved anything and a Reversed one has been put back.
          AND  t.status = 'Approved'
          AND  t.transferdate >= p_from::timestamp
          AND  t.transferdate <  (p_to + 1)::timestamp
        UNION ALL
        -- ---- leg E: advance repaid through payroll (305/306/309) ------------
        -- The event with NO money in it.
        --
        -- 100 withheld from a 2,200 wage settles 100 of what the worker owes.
        -- The farm paid out 2,100, so no cash moved for this -- and putting a
        -- Money In of 100 here would invent a receipt and inflate the period
        -- (spec section 65). Both cash columns are zero, exactly as leg D does
        -- for internal transfers, and for the same reason: the timeline should
        -- be complete without the totals being wrong.
        --
        -- It is carried so the POSITION can be: Financial Activity is where an
        -- owner asks "why did what the staff owe us go down this month", and
        -- without this leg the receivable would move with nothing to point at.
        -- It cannot duplicate the payroll cash event, because the payroll
        -- expense and its cash row are a different eventkey entirely.
        SELECT 'EmployeeLoanPayrollRepayment:' || r.poultryemployeeloanrepaymentid,
               1,
               r.repaymentdate::date,
               r.repaymentdate,
               r.createdat,
               'EmployeeLoanPayrollRepayment',
               NULL::text,
               ('Advance repayment from ' || btrim(s.firstname || ' ' || s.lastname) ||
                ' withheld from payroll ' ||
                COALESCE(to_char(pr.periodstart, 'YYYY-MM-DD') || ' to ' ||
                         to_char(pr.periodend, 'YYYY-MM-DD'),
                         COALESCE(r.poultrypayrollrunid::text, ''))),
               r.poultryemployeeloanid,
               NULLIF(btrim(l.loannumber), ''),
               0::numeric,
               0::numeric,
               0::numeric,
               0::numeric,
               FALSE,
               NULL::integer,
               btrim(s.firstname || ' ' || s.lastname),
               NULL::text,
               'Posted'::text
        FROM   poultryemployeeloanrepayments r
        JOIN   poultryemployeeloans l ON l.poultryemployeeloanid = r.poultryemployeeloanid
        JOIN   poultrystaff s ON s.poultrystaffid = r.poultrystaffid
        LEFT   JOIN poultrypayrollruns pr ON pr.poultrypayrollrunid = r.poultrypayrollrunid
        WHERE  r.farmid = p_farmid
          AND  r.status = 'Posted'
          AND  r.sourcetype = 'Payroll'
          AND  r.repaymentdate >= p_from::timestamp
          AND  r.repaymentdate <  (p_to + 1)::timestamp
    ),
    merged AS (
        SELECT l.eventkey,
               -- Metadata comes from ONE leg, the one that knows most about this
               -- kind of event, rather than being coalesced field by field from
               -- several -- which is how a row ends up with one leg's date and
               -- another leg's description.
               (array_agg(l.businessdate ORDER BY l.metapri, l.occurredat))[1] AS businessdate,
               (array_agg(l.occurredat   ORDER BY l.metapri, l.occurredat))[1] AS occurredat,
               -- FILTERed, unlike its neighbours: an event can span legs and
               -- the highest-priority one is not guaranteed to carry an entry
               -- time. Taking [1] unfiltered would throw away a time another
               -- leg had, which is the whole bug this migration fixes.
               (array_agg(l.createdat    ORDER BY l.metapri, l.occurredat)
                  FILTER (WHERE l.createdat IS NOT NULL))[1]                   AS createdat,
               (array_agg(l.src          ORDER BY l.metapri, l.occurredat))[1] AS src,
               (array_agg(l.costtype     ORDER BY l.metapri, l.occurredat))[1] AS costtype,
               (array_agg(l.description  ORDER BY l.metapri, l.occurredat))[1] AS description,
               (array_agg(l.sourceid     ORDER BY l.metapri, l.occurredat))[1] AS sourceid,
               (array_agg(l.sourcenumber ORDER BY l.metapri, l.occurredat))[1] AS sourcenumber,
               (array_agg(l.plline       ORDER BY l.metapri, l.occurredat))[1] AS plline,
               (array_agg(l.status       ORDER BY l.metapri, l.occurredat))[1] AS status,
               MAX(l.cashaccountid)                                            AS cashaccountid,
               MAX(l.partyname)                                                AS partyname,
               BOOL_OR(l.istransfer)                                           AS istransfer,
               ROUND(SUM(l.moneyin),  2)                                       AS moneyin,
               ROUND(SUM(l.moneyout), 2)                                       AS moneyout,
               ROUND(SUM(l.revenue),  2)                                       AS revenue,
               ROUND(SUM(l.expense),  2)                                       AS expense
        FROM   legs l
        GROUP  BY l.eventkey
    )
    SELECT m.eventkey,
           m.businessdate,
           m.occurredat,
           m.createdat,
           public.fnpoultryfa_activitytype(m.src, m.costtype),
           public.fnpoultryfa_type(m.src, m.costtype),
           public.fnpoultryfa_category(m.src, m.costtype),
           m.description,
           m.src,
           m.sourceid,
           m.sourcenumber,
           m.moneyin,
           m.moneyout,
           m.revenue,
           m.expense,
           -- Profit is what was RECOGNISED, never what moved. Adding money in or
           -- out here is the single mistake this whole report exists to prevent.
           ROUND(m.revenue - m.expense, 2),
           (m.moneyin + m.moneyout) > 0,
           (m.moneyin + m.moneyout) = 0 AND (m.revenue + m.expense) > 0,
           m.istransfer,
           m.cashaccountid,
           m.partyname,
           m.plline,
           m.status
    FROM   merged m
    -- An event with nothing on any leg is not an event.
    WHERE  m.moneyin <> 0 OR m.moneyout <> 0 OR m.revenue <> 0 OR m.expense <> 0
        OR m.istransfer;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryfinancialactivity_get(p_farmid text, p_from date, p_to date)
 RETURNS TABLE(eventkey text, businessdate date, occurredat timestamp without time zone, createdat timestamp without time zone, activitytype text, type text, category text, description text, sourcetype text, sourceid integer, sourcenumber text, moneyin numeric, moneyout numeric, revenue numeric, expense numeric, profitimpact numeric, runningcash numeric, iscash boolean, isnoncash boolean, istransfer boolean, cashaccountid integer, cashaccountname text, partyname text, plline text, status text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH opening AS (
        SELECT COALESCE(s.openingbalance, 0) AS bal
        FROM   public.sppoultrycashflow_summary(
                   p_farmid, p_from::timestamp,
                   ((p_to + 1)::timestamp - interval '1 microsecond')) s
    )
    SELECT e.eventkey, e.businessdate, e.occurredat, e.createdat, e.activitytype, e.type,
           e.category, e.description, e.sourcetype, e.sourceid, e.sourcenumber,
           e.moneyin, e.moneyout, e.revenue, e.expense, e.profitimpact,
           ROUND((SELECT bal FROM opening)
                 + SUM(e.moneyin - e.moneyout) OVER (ORDER BY e.businessdate, e.occurredat, e.eventkey
                                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2),
           e.iscash, e.isnoncash, e.istransfer,
           e.cashaccountid, a.accountname::text, e.partyname, e.plline, e.status
    FROM   public.fnpoultryfa_events(p_farmid, p_from, p_to) e
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = e.cashaccountid
    ORDER  BY e.businessdate, e.occurredat, e.eventkey;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'both functions exist (2 expected)' AS check,
       CASE WHEN COUNT(*) = 2 THEN 'OK' ELSE 'MISSING (' || COUNT(*) || ')' END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('fnpoultryfa_events', 'sppoultryfinancialactivity_get')

UNION ALL
-- The fifth leg is still there. If this says MISSING, a payroll leg has been
-- deleted and the employee-loan events have vanished from the report.
SELECT 'the payroll repayment leg survived',
       CASE WHEN COUNT(*) = 1 THEN 'OK' ELSE 'LEG LOST' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'fnpoultryfa_events'
  AND  pg_get_functiondef(p.oid) LIKE '%poultryemployeeloanrepayments%'

UNION ALL
-- And both reads expose the new column.
SELECT 'createdat is returned by both',
       CASE WHEN COUNT(*) = 2 THEN 'OK' ELSE 'MISSING (' || COUNT(*) || ')' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('fnpoultryfa_events', 'sppoultryfinancialactivity_get')
  AND  pg_get_function_result(p.oid) LIKE '%createdat%';

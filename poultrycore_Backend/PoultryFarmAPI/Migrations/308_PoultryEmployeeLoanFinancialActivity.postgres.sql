-- =============================================================================
-- 308_PoultryEmployeeLoanFinancialActivity.postgres.sql
--
-- Purpose
-- -------
-- Teach Financial Activity what an employee advance IS, and give it somewhere
-- to say so: the Employee Loan Receivable.
--
-- WHAT THIS FILE HAD TO DO, AND WHAT IT TURNED OUT NOT TO
-- =======================================================
-- Less than expected, and that is the interesting part. fnpoultryfa_events
-- builds its cash legs FROM sppoultrycashflow_rows, and passes an unrecognised
-- sourcetype straight through:
--
--     CASE r.sourcetype ... ELSE r.sourcetype END AS src
--
-- So the moment 307 added arm 8 to the cash flow, the disbursement and the
-- manual repayment were ALREADY events here. They were simply being classified
-- by the ELSE branches of the three classifier functions, which call an unknown
-- source an 'Expense' in an 'Operating Expense' category -- precisely what
-- sections 20 and 25 forbid. Lending money is not an expense, and getting it
-- back is not revenue.
--
-- So the work is three things:
--   1. classifier branches, so the rows are named for what they are;
--   2. one new leg for the payroll repayment, which has no cash row and would
--      otherwise never appear at all;
--   3. the Employee Loan Receivable position -- the actual answer to "what did
--      this do to what the business owns".
--
-- THE POSITION IS AN ASSET, AND ITS OWN ONE
-- =========================================
-- Section 63: an employee advance is NOT a customer receivable. A customer
-- receivable is money owed for something sold; this is money lent. They are
-- collected differently and mean different things, and an owner reading
-- "Receivables" should not find the storeman's advance inside it. Hence a
-- positiontype of its own: EmployeeLoanReceivable.
--
-- THE RECEIVABLE AND THE CASH ARE DIFFERENT NUMBERS
-- -------------------------------------------------
-- An advance of 2,000 with 200 interest hands over 2,000 of cash and creates
-- 2,200 of receivable. The company-loan arm already draws the same distinction
-- in the other direction (originalprincipal vs amountreceived), so this is the
-- house pattern rather than a new idea.
--
-- WHY THE BODIES BELOW ARE THE LIVE ONES
-- --------------------------------------
-- fnpoultryfa_events and fnpoultryfa_positions were taken with
-- pg_get_functiondef on 2026-09-17. This repo never held them at all, so
-- re-emitting a guessed body would silently drop whatever it did not know
-- about. Each is verbatim apart from the additions this file exists to make: a
-- diff against the dump shows exactly those and nothing else.
--
-- Idempotent. Safe to run more than once.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Name the three new sources.
--
-- Without these an advance reads as 'Expense / Operating Expense', which is the
-- one classification the spec rules out by name.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryfa_type(p_source text, p_costtype text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE p_source
        WHEN 'Sale'                          THEN 'Sale'
        WHEN 'CustomerPayment'               THEN 'Customer Payment'
        WHEN 'SupplierPayment'               THEN 'Supplier Payment'
        WHEN 'LoanReceived'                  THEN 'Loan Received'
        WHEN 'LoanPayment'                   THEN 'Loan Repayment'
        WHEN 'OwnerContribution'             THEN 'Owner Contribution'
        WHEN 'OwnerDraw'                     THEN 'Owner Draw'
        WHEN 'CashTransfer'                  THEN 'Cash Transfer'
        WHEN 'AssetDepreciation'             THEN 'Depreciation'
        WHEN 'CapitalAsset'                  THEN 'Capital Investment'
        WHEN 'CapitalAssetCost'              THEN 'Capital Investment'
        WHEN 'PoultryFeedConsumption'        THEN 'Feed Consumption'
        WHEN 'PoultryMedicationConsumption'  THEN 'Medication Consumption'
        WHEN 'PoultryInternalUsage'          THEN 'Internal Use'
        WHEN 'PoultryRawMaterialPurchase'    THEN 'Inventory Purchase'
        WHEN 'MainFlockBatch'                THEN 'Flock Purchase'
        WHEN 'Payroll'                       THEN 'Payroll'
        WHEN 'Adjustment'                    THEN 'Cash Adjustment'
        -- 305/307/308. Named for what they are to the BUSINESS rather than for
        -- the table they came from: an owner reads this column.
        WHEN 'EmployeeLoanDisbursement'      THEN 'Employee Advance'
        WHEN 'EmployeeLoanRepayment'         THEN 'Advance Repaid'
        WHEN 'EmployeeLoanPayrollRepayment'  THEN 'Advance Repaid from Wages'
        ELSE CASE WHEN COALESCE(p_costtype,'') = 'CapitalAsset' THEN 'Capital Investment'
                  ELSE 'Expense' END
    END;
$function$;

CREATE OR REPLACE FUNCTION public.fnpoultryfa_category(p_source text, p_costtype text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE p_source
        WHEN 'Sale'                          THEN 'Sales'
        WHEN 'CustomerPayment'               THEN 'Customer Collections'
        WHEN 'SupplierPayment'               THEN 'Supplier Payment'
        WHEN 'LoanReceived'                  THEN 'Financing'
        WHEN 'LoanPayment'                   THEN 'Financing Cost'
        WHEN 'OwnerContribution'             THEN 'Owner Capital'
        WHEN 'OwnerDraw'                     THEN 'Owner Capital'
        WHEN 'CashTransfer'                  THEN 'Internal Transfer'
        WHEN 'AssetDepreciation'             THEN 'Depreciation'
        WHEN 'CapitalAsset'                  THEN 'Capital Investment'
        WHEN 'CapitalAssetCost'              THEN 'Capital Investment'
        WHEN 'PoultryFeedConsumption'        THEN 'Cost Recognition'
        WHEN 'PoultryMedicationConsumption'  THEN 'Cost Recognition'
        WHEN 'PoultryInternalUsage'          THEN 'Internal Use'
        WHEN 'PoultryRawMaterialPurchase'    THEN 'Inventory Purchase'
        WHEN 'MainFlockBatch'                THEN 'Inventory Purchase'
        WHEN 'Payroll'                       THEN 'Payroll'
        WHEN 'Adjustment'                    THEN 'Adjustment'
        -- One category for all three, so filtering by it tells the whole story
        -- of an advance: out, back in cash, and back through the wage.
        WHEN 'EmployeeLoanDisbursement'      THEN 'Employee Advance'
        WHEN 'EmployeeLoanRepayment'         THEN 'Employee Advance'
        WHEN 'EmployeeLoanPayrollRepayment'  THEN 'Employee Advance'
        ELSE CASE WHEN COALESCE(p_costtype,'') = 'CapitalAsset' THEN 'Capital Investment'
                  ELSE 'Operating Expense' END
    END;
$function$;

CREATE OR REPLACE FUNCTION public.fnpoultryfa_activitytype(p_source text, p_costtype text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_source IN ('LoanReceived', 'LoanPayment', 'Adjustment')        THEN 'Financing'
        WHEN p_source IN ('OwnerContribution', 'OwnerDraw')                   THEN 'Owner'
        -- Its own activity, deliberately not Financing. Financing here means
        -- money the BUSINESS raised; lending to a worker runs the other way,
        -- and filing it under Financing would put an advance and a bank loan in
        -- the same bucket. Not Operating either -- that is where the classifier
        -- puts costs, and an advance is not a cost.
        WHEN p_source IN ('EmployeeLoanDisbursement', 'EmployeeLoanRepayment',
                          'EmployeeLoanPayrollRepayment')                     THEN 'EmployeeLoan'
        WHEN p_source IN ('CapitalAsset', 'CapitalAssetCost', 'AssetDepreciation')
             OR COALESCE(p_costtype,'') = 'CapitalAsset'                      THEN 'Capital'
        WHEN p_source IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption',
                          'PoultryInternalUsage', 'PoultryRawMaterialPurchase',
                          'MainFlockBatch')                                   THEN 'Inventory'
        WHEN p_source = 'CashTransfer'                                        THEN 'Transfer'
        ELSE 'Operating'
    END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. fnpoultryfa_events, re-emitted with leg E.
--
-- Verbatim from the live database with ONE addition: the payroll-repayment leg,
-- carrying zero in both cash columns.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryfa_events(p_farmid text, p_from date, p_to date)
 RETURNS TABLE(eventkey text, businessdate date, occurredat timestamp without time zone, activitytype text, type text, category text, description text, sourcetype text, sourceid integer, sourcenumber text, moneyin numeric, moneyout numeric, revenue numeric, expense numeric, profitimpact numeric, iscash boolean, isnoncash boolean, istransfer boolean, cashaccountid integer, partyname text, plline text, status text)
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

-- -----------------------------------------------------------------------------
-- 3. fnpoultryfa_positions, re-emitted with the Employee Loan Receivable.
--
-- Verbatim from the live database with THREE additions: the advance going out,
-- and the two ways it comes back.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryfa_positions(p_farmid text, p_from date, p_to date)
 RETURNS TABLE(eventkey text, positiontype text, positionname text, increaseamount numeric, decreaseamount numeric, explanation text)
 LANGUAGE sql
 STABLE
AS $function$
    -- Loan received: the debt the farm took on. The LIABILITY is the principal;
    -- the CASH was amountreceived, which is smaller when the lender withheld a
    -- fee. Two different numbers on purpose.
    SELECT 'Loan:' || l.poultryloanid,
           'LoanLiability',
           l.lendername::text,
           l.originalprincipal::numeric, 0::numeric,
           'Outstanding loan increased'
    FROM   poultryloans l
    WHERE  l.farmid = p_farmid
      AND  l.status NOT IN ('Cancelled', 'Reversed', 'Draft')
      AND  l.loandate >= p_from AND l.loandate <= p_to

    UNION ALL
    -- Loan repayment: only the PRINCIPAL reduces the debt. Interest and fees are
    -- the cost of borrowing and are already the expense leg of the same row.
    SELECT 'LoanPayment:' || p.poultryloanpaymentid,
           'LoanLiability',
           l.lendername::text,
           0::numeric, p.principalamount::numeric,
           'Outstanding loan reduced'
    FROM   poultryloanpayments p
    JOIN   poultryloans l ON l.poultryloanid = p.poultryloanid
    WHERE  p.farmid = p_farmid AND p.status = 'Posted'
      AND  p.principalamount > 0
      AND  p.paymentdate >= p_from::timestamp AND p.paymentdate < (p_to + 1)::timestamp

    UNION ALL
    SELECT 'OwnerMoney:' || o.poultryownermoneyid,
           'OwnerCapital',
           COALESCE(NULLIF(btrim(o.ownername), ''), 'Owner'),
           CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE 0 END::numeric,
           CASE WHEN o.transactiontype = 'Contribution' THEN 0 ELSE o.amount END::numeric,
           CASE WHEN o.transactiontype = 'Contribution'
                THEN 'Owner funding increased' ELSE 'Owner funding reduced' END
    FROM   poultryownermoney o
    WHERE  o.farmid = p_farmid AND o.status = 'Posted'
      AND  o.transactiondate >= p_from::timestamp AND o.transactiondate < (p_to + 1)::timestamp

    UNION ALL
    -- A collection settles a debt the customer already owed. No revenue: that
    -- was recognised when the sale happened.
    SELECT 'CustomerPayment:' || pp.poultrypaymentid,
           'CustomerReceivable',
           COALESCE(NULLIF(btrim(s.customername), ''), 'Customer'),
           0::numeric, pp.amount::numeric,
           'Customer debt reduced'
    FROM   poultrypayments pp
    LEFT   JOIN sale s ON s.saleid = pp.saleid
    WHERE  lower(pp.farmid::text) = lower(p_farmid)
      AND  COALESCE(pp.status, 'Posted') = 'Posted'
      AND  pp.amount <> 0
      AND  pp.paymentdate >= p_from::timestamp AND pp.paymentdate < (p_to + 1)::timestamp

    UNION ALL
    -- The unpaid part of a sale is money the customer now owes.
    SELECT 'Sale:' || s.saleid,
           'CustomerReceivable',
           COALESCE(NULLIF(btrim(s.customername), ''), 'Customer'),
           v.owed, 0::numeric,
           'Customer now owes this amount'
    FROM   sale s
    CROSS  JOIN LATERAL (
        SELECT ROUND(COALESCE(s.totalamount, 0)
                     - CASE WHEN COALESCE(s.paid, false) THEN COALESCE(s.totalamount, 0)
                            ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),
                                       COALESCE(s.totalamount, 0)) END, 2) AS owed
    ) v
    WHERE  lower(s.farmid::text) = lower(p_farmid)
      AND  v.owed > 0
      AND  s.saledate >= p_from AND s.saledate <= p_to

    UNION ALL
    -- The unpaid part of a bill is money the farm now owes its supplier.
    SELECT 'Expense:' || e.expenseid,
           'SupplierPayable',
           COALESCE(NULLIF(btrim(s.name), ''), 'Supplier'),
           v.owed, 0::numeric,
           'Supplier is owed this amount'
    FROM   expense e
    LEFT   JOIN supplier s ON s.supplierid = e.supplierid
    CROSS  JOIN LATERAL (
        SELECT ROUND(GREATEST(COALESCE(e.amount, 0) - COALESCE(e.amountpaid, e.amount), 0), 2) AS owed
    ) v
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  v.owed > 0
      AND  e.expensedate >= p_from AND e.expensedate < (p_to + 1)

    UNION ALL
    -- Paying a supplier settles that debt. It is not a second expense.
    SELECT 'SupplierPayment:' || sa.allocationid,
           'SupplierPayable',
           COALESCE(NULLIF(btrim(s.name), ''), 'Supplier'),
           0::numeric, sa.amountapplied::numeric,
           'Supplier debt reduced'
    FROM   supplierpaymentallocation sa
    JOIN   poultrysupplierpayments sp
           ON sp.poultrysupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sa.farmid = p_farmid AND sa.module = 'poultry'
      AND  sa.status = 'Posted' AND sp.status = 'Posted' AND sa.amountapplied <> 0
      AND  sp.paymentdate >= p_from::timestamp AND sp.paymentdate < (p_to + 1)::timestamp

    UNION ALL
    -- Stock bought, and stock consumed. Which of the two an item does at
    -- purchase is the farm's cost-recognition setting (261-268); this reads the
    -- classification rather than re-deciding it.
    SELECT 'Expense:' || e.expenseid,
           CASE WHEN e.costtype = 'CapitalAsset' THEN 'CapitalAsset'
                WHEN e.sourcetype = 'AssetDepreciation' THEN 'AccumulatedDepreciation'
                ELSE 'Inventory' END,
           CASE WHEN e.costtype = 'CapitalAsset' THEN COALESCE(NULLIF(btrim(e.description),''), 'Capital asset')
                WHEN e.sourcetype = 'AssetDepreciation' THEN COALESCE(NULLIF(btrim(e.description),''), 'Depreciation')
                ELSE COALESCE(NULLIF(btrim(e.category), ''), 'Inventory') END,
           CASE WHEN e.sourcetype IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption',
                                      'PoultryInternalUsage')
                THEN 0 ELSE COALESCE(e.amount, 0) END::numeric,
           CASE WHEN e.sourcetype IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption',
                                      'PoultryInternalUsage')
                THEN COALESCE(e.amount, 0) ELSE 0 END::numeric,
           CASE WHEN e.costtype = 'CapitalAsset'            THEN 'Capital asset acquired'
                WHEN e.sourcetype = 'AssetDepreciation'     THEN 'Asset book value reduced'
                WHEN e.sourcetype = 'PoultryFeedConsumption' THEN 'Feed stock consumed'
                WHEN e.sourcetype = 'PoultryMedicationConsumption' THEN 'Medication stock consumed'
                WHEN e.sourcetype = 'PoultryInternalUsage'  THEN 'Stock taken for internal use'
                ELSE 'Inventory value increased' END
    FROM   public.fnpoultrypl_expenselines(p_farmid, p_from, p_to) e
    WHERE  e.costtype = 'CapitalAsset'
       OR  e.sourcetype IN ('AssetDepreciation', 'PoultryFeedConsumption',
                            'PoultryMedicationConsumption', 'PoultryInternalUsage',
                            'PoultryRawMaterialPurchase', 'MainFlockBatch')

    UNION ALL
    -- Both legs of a transfer, which is the whole explanation of why the event
    -- shows no Money In and no Money Out: the money is still the farm's.
    SELECT 'CashTransfer:' || t.poultrycashtransferid,
           'Cash', COALESCE(fa.accountname::text, 'From account'),
           0::numeric, t.amount::numeric, 'Money left this account'
    FROM   poultrycashtransfers t
    LEFT   JOIN poultrycashaccounts fa ON fa.poultrycashaccountid = t.frompoultrycashaccountid
    WHERE  t.farmid = p_farmid AND t.status = 'Approved'
      AND  t.transferdate >= p_from::timestamp AND t.transferdate < (p_to + 1)::timestamp

    UNION ALL
    SELECT 'CashTransfer:' || t.poultrycashtransferid,
           'Cash', COALESCE(ta.accountname::text, 'To account'),
           t.amount::numeric, 0::numeric, 'Money arrived in this account'
    FROM   poultrycashtransfers t
    LEFT   JOIN poultrycashaccounts ta ON ta.poultrycashaccountid = t.topoultrycashaccountid
    WHERE  t.farmid = p_farmid AND t.status = 'Approved'
      AND  t.transferdate >= p_from::timestamp AND t.transferdate < (p_to + 1)::timestamp

    UNION ALL
    -- Employee advance handed over: the worker now owes the farm. The
    -- RECEIVABLE is everything repayable; the CASH that left was the principal
    -- only. Two different numbers on purpose, exactly as the loan arm above
    -- distinguishes originalprincipal from amountreceived -- interest is owed
    -- from day one and was never money that left the building.
    SELECT 'Cash:EmployeeLoan:' || l.poultryemployeeloanid,
           'EmployeeLoanReceivable',
           btrim(s.firstname || ' ' || s.lastname)::text,
           l.totalrepayable::numeric, 0::numeric,
           CASE WHEN l.interestamount > 0
                THEN 'Advance to staff, including interest owed'
                ELSE 'Advance to staff' END
    FROM   poultryemployeeloans l
    JOIN   poultrystaff s ON s.poultrystaffid = l.poultrystaffid
    WHERE  l.farmid = p_farmid
      AND  l.status NOT IN ('Draft', 'Cancelled', 'Reversed')
      AND  l.poultrycashaccountid IS NOT NULL
      -- The same date expression the cash arm uses, so the position lands on
      -- the event rather than beside it.
      AND  (CASE WHEN l.disbursementdate = l.createdat::date THEN l.createdat
                 ELSE l.disbursementdate::timestamp END) >= p_from::timestamp
      AND  (CASE WHEN l.disbursementdate = l.createdat::date THEN l.createdat
                 ELSE l.disbursementdate::timestamp END) <  (p_to + 1)::timestamp

    UNION ALL
    -- Repaid in cash. The WHOLE repayment reduces what is owed: unlike a
    -- company loan, where only principal touches the debt and interest is the
    -- cost of borrowing, here the interest was part of the receivable from the
    -- start, so recovering it reduces the receivable too.
    SELECT 'Cash:EmployeeLoanRepayment:' || r.poultryemployeeloanrepaymentid,
           'EmployeeLoanReceivable',
           btrim(s.firstname || ' ' || s.lastname)::text,
           0::numeric, r.amount::numeric,
           'Advance repaid by staff'
    FROM   poultryemployeeloanrepayments r
    JOIN   poultrystaff s ON s.poultrystaffid = r.poultrystaffid
    WHERE  r.farmid = p_farmid
      AND  r.status = 'Posted'
      AND  r.sourcetype <> 'Payroll'
      AND  r.repaymentdate >= p_from::timestamp
      AND  r.repaymentdate <  (p_to + 1)::timestamp

    UNION ALL
    -- Repaid by payroll deduction. Same reduction, no cash -- this is the
    -- position that leg E of fnpoultryfa_events exists to carry.
    SELECT 'EmployeeLoanPayrollRepayment:' || r.poultryemployeeloanrepaymentid,
           'EmployeeLoanReceivable',
           btrim(s.firstname || ' ' || s.lastname)::text,
           0::numeric, r.amount::numeric,
           'Advance repaid from wages'
    FROM   poultryemployeeloanrepayments r
    JOIN   poultrystaff s ON s.poultrystaffid = r.poultrystaffid
    WHERE  r.farmid = p_farmid
      AND  r.status = 'Posted'
      AND  r.sourcetype = 'Payroll'
      AND  r.repaymentdate >= p_from::timestamp
      AND  r.repaymentdate <  (p_to + 1)::timestamp;
$function$;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
DO $checks$
DECLARE
    v_bad  integer;
    v_body text;
BEGIN
    IF public.fnpoultryfa_type('EmployeeLoanDisbursement') <> 'Employee Advance'
       OR public.fnpoultryfa_category('EmployeeLoanDisbursement') <> 'Employee Advance'
       OR public.fnpoultryfa_activitytype('EmployeeLoanDisbursement') <> 'EmployeeLoan' THEN
        RAISE EXCEPTION '308: an employee advance is still classified as an expense.';
    END IF;
    IF public.fnpoultryfa_activitytype('EmployeeLoanPayrollRepayment') <> 'EmployeeLoan' THEN
        RAISE EXCEPTION '308: the payroll-repayment source is not classified.';
    END IF;

    -- Leg E and the position arms must be reachable, or the receivable moves
    -- with nothing on the timeline to explain it.
    SELECT pg_get_functiondef(p.oid) INTO v_body
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'fnpoultryfa_events' LIMIT 1;
    IF v_body IS NULL OR position('EmployeeLoanPayrollRepayment' in v_body) = 0 THEN
        RAISE EXCEPTION '308: fnpoultryfa_events has no payroll-repayment leg.';
    END IF;

    SELECT pg_get_functiondef(p.oid) INTO v_body
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'fnpoultryfa_positions' LIMIT 1;
    IF v_body IS NULL OR position('EmployeeLoanReceivable' in v_body) = 0 THEN
        RAISE EXCEPTION '308: fnpoultryfa_positions has no Employee Loan Receivable.';
    END IF;

    -- An advance must never reach the P&L. Asserted against real rows rather
    -- than trusted: no expense may point at one.
    SELECT COUNT(*) INTO v_bad
    FROM   expense e
    WHERE  e.sourcetype IN ('EmployeeLoan', 'EmployeeLoanDisbursement');
    IF v_bad > 0 THEN
        RAISE EXCEPTION
            '308: % expense row(s) point at an employee advance. Lending is not an expense.', v_bad;
    END IF;

    RAISE NOTICE
        '308_PoultryEmployeeLoanFinancialActivity: 3 classifiers, leg E, receivable position, verified.';
END
$checks$;

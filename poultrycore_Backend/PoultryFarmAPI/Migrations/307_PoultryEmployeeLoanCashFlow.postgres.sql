-- =============================================================================
-- 307_PoultryEmployeeLoanCashFlow.postgres.sql
--
-- Purpose
-- -------
-- Put employee advances on the Cash Flow report -- and keep payroll deductions
-- OFF it.
--
-- WHAT GOES ON, AND WHAT MUST NOT
-- ===============================
--   disbursement        real money left the account        -> Money Out
--   manual repayment    real money arrived                 -> Money In
--   payroll deduction   NOTHING MOVED                      -> nothing at all
--
-- The third line is the whole reason this file needs a comment. When 100 is
-- withheld from a 2,200 wage, the farm pays out 2,100. There is no second
-- event in which the worker hands 100 back, so reporting one would invent cash
-- the business never received and inflate every Money In total that period
-- (spec section 67). 305 already made that unrepresentable -- a payroll
-- repayment carries no cash account -- and the arm below filters on source
-- anyway, so it is wrong in two independent places before it can happen once.
--
-- WHY THIS IS ITS OWN FUNCTION RATHER THAN TWO MORE ARMS INLINE
-- ============================================================
-- sppoultrycashflow_rows is one 600-line plpgsql body with eight RETURN QUERY
-- arms, and the house convention is that each migration re-emits the whole
-- thing. That convention has a trap: the version in this repo is a
-- pg_get_functiondef dump taken when 302 was written, and this codebase has
-- already been bitten once by a live function body that had moved ahead of the
-- copy in git (see the loans cash-adjustment arm). Re-emitting a stale body
-- would silently DELETE whatever arms have been added since -- on a live
-- financial report, for every past period.
--
-- So the new arms live here, in a function of their own, with the exact 14
-- column shape sppoultrycashflow_rows returns. Splicing them in is then a
-- single line -- arm 8 -- appended to the end of that function.
--
-- AND THE BODY RE-EMITTED BELOW IS THE LIVE ONE, NOT THE COPY IN THIS REPO.
-- It was taken with pg_get_functiondef on 2026-09-17 and diffed against
-- migration 302's copy first: the two were identical apart from how Postgres
-- spells `timestamp without time zone` and a trailing semicolon. So nothing
-- had drifted this time -- but the check is the reason that is a FACT here
-- rather than a hope, and the next person to touch this function should do
-- the same before re-emitting it.
--
-- The verification block at the bottom still refuses to let this migration
-- pass unless the arm is actually reachable, so "applied 307 but the splice
-- did not take" cannot happen quietly -- it fails loudly, which is the only
-- acceptable failure mode for a report about money.
--
-- SIGN CONVENTION
-- ---------------
-- Copied from arms 5 and 6, not invented: money in is a POSITIVE amount with
-- transactiontype 'CashIn', money out is NEGATIVE with 'CashOut'. Getting this
-- backwards would not error -- it would just quietly report an advance as
-- income.
--
-- Idempotent. Safe to run more than once.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sppoultryemployeeloan_cashflowrows(
    p_farmid   text,
    p_fromdate timestamp without time zone DEFAULT NULL,
    p_todate   timestamp without time zone DEFAULT NULL
) RETURNS TABLE(
    rowsource text,
    offledger boolean,
    sourcerowid integer,
    cashaccountid integer,
    accountname text,
    transactiondate timestamp without time zone,
    transactiontype text,
    sourcetype text,
    sourceid integer,
    istransfer boolean,
    amount numeric,
    description text,
    flowgroup text,
    createdat timestamp
)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_from timestamp := COALESCE(p_fromdate, '1900-01-01'::timestamp);
    v_to   timestamp := COALESCE(p_todate,   '9999-12-31'::timestamp);
BEGIN
    -- ---- A. advances handed over --------------------------------------------
    -- The PRINCIPAL, not the total repayable: interest is something the worker
    -- will owe, not money that left the building. 305 posts exactly this
    -- amount to the cash account, so the report and the balance agree.
    --
    -- Dated by the same rule as the loans arm (256): an advance dated TODAY
    -- carries the moment it was recorded, so it sorts with the rest of today's
    -- entries; a back-dated one keeps midnight, because nobody knows what time
    -- last Tuesday's handover happened.
    RETURN QUERY
    SELECT 'EmployeeLoan'::text,
           FALSE,
           l.poultryemployeeloanid,
           l.poultrycashaccountid,
           a.accountname::text,
           CASE WHEN l.disbursementdate = l.createdat::date THEN l.createdat
                ELSE l.disbursementdate::timestamp END,
           'CashOut'::text,
           'EmployeeLoanDisbursement'::text,
           l.poultryemployeeloanid,
           FALSE,
           -l.principalamount::numeric,
           ('Employee advance to ' || btrim(s.firstname || ' ' || s.lastname) ||
            ' - ' || COALESCE(l.loannumber, l.poultryemployeeloanid::text))::text,
           'EmployeeLoanOut'::text,
           l.createdat
    FROM   poultryemployeeloans l
    JOIN   poultrystaff s ON s.poultrystaffid = l.poultrystaffid
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = l.poultrycashaccountid
    WHERE  l.farmid = p_farmid
      -- A Draft was never handed over, and a Cancelled or Reversed one has had
      -- its cash put back. Same exclusion the loans arm uses, so the two
      -- receivable-shaped features behave alike.
      AND  l.status NOT IN ('Draft', 'Cancelled', 'Reversed')
      AND  l.poultrycashaccountid IS NOT NULL
      AND  CASE WHEN l.disbursementdate = l.createdat::date THEN l.createdat
                ELSE l.disbursementdate::timestamp END BETWEEN v_from AND v_to;

    -- ---- B. repayments that actually moved money ----------------------------
    -- sourcetype <> 'Payroll' IS THE POINT OF THIS FILE. A payroll deduction
    -- reduces the receivable without any money arriving; the wage paid out was
    -- already net. Including it here would report cash the farm never got.
    --
    -- Belt and braces: 305's ck_..._repayments_cash forbids a payroll repayment
    -- from carrying a cash account at all, so even without this filter there
    -- would be no account to report it against -- but a filter that states the
    -- rule is worth more than one that relies on a constraint three files away.
    RETURN QUERY
    SELECT 'EmployeeLoanRepayment'::text,
           FALSE,
           r.poultryemployeeloanrepaymentid,
           r.poultrycashaccountid,
           a.accountname::text,
           r.repaymentdate,
           'CashIn'::text,
           'EmployeeLoanRepayment'::text,
           r.poultryemployeeloanid,
           FALSE,
           r.amount::numeric,
           ('Advance repayment from ' || btrim(s.firstname || ' ' || s.lastname) ||
            ' - ' || COALESCE(l.loannumber, r.poultryemployeeloanid::text))::text,
           'EmployeeLoanIn'::text,
           r.createdat
    FROM   poultryemployeeloanrepayments r
    JOIN   poultryemployeeloans l ON l.poultryemployeeloanid = r.poultryemployeeloanid
    JOIN   poultrystaff s ON s.poultrystaffid = r.poultrystaffid
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = r.poultrycashaccountid
    WHERE  r.farmid = p_farmid
      AND  r.status = 'Posted'
      AND  r.sourcetype <> 'Payroll'
      AND  r.poultrycashaccountid IS NOT NULL
      AND  r.repaymentdate BETWEEN v_from AND v_to;
END;
$function$;

COMMENT ON FUNCTION public.sppoultryemployeeloan_cashflowrows(text, timestamp, timestamp) IS
    'The employee-advance arms of the poultry Cash Flow report, kept separate '
    'so splicing them into sppoultrycashflow_rows is one line rather than a '
    're-emission of a 600-line body this repo may hold a stale copy of. '
    'Payroll deductions are excluded: no money moved.';

-- -----------------------------------------------------------------------------
-- The splice: sppoultrycashflow_rows, re-emitted with arm 8.
--
-- Verbatim from the live database, blank lines and all, with ONE edit: the
-- RETURN QUERY for arm 8 before the final END. Reading the diff of this file
-- against the dump should show exactly that and nothing else.
--
-- If you are re-emitting this function in a later migration, take the body
-- from pg_get_functiondef again rather than from here, and keep arm 8.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, createdat timestamp without time zone)
 LANGUAGE plpgsql
 STABLE
AS $function$

DECLARE

    v_tbl  text;
    v_createdcol text;               -- 302: 'ca.createddate' or NULL

    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);

    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);

BEGIN

    -- ---- 1. customer receipts, dated when the money arrived -----------------

    -- This is the leg that makes it a CASH flow rather than a sales report. A

    -- January sale part-paid in August belongs in August, and poultrypayments is

    -- the only place that date exists (145_PoultryPayments.sql:36).

    RETURN QUERY

    SELECT 'Receipt'::text,

           FALSE,

           p.poultrypaymentid,

           NULL::integer,

           NULL::text,

           p.paymentdate,

           'CashIn'::text,

           'CustomerPayment'::text,

           p.saleid,

           FALSE,

           COALESCE(p.amount, 0)::numeric,

           COALESCE(NULLIF(btrim(p.note), ''),

                    NULLIF(btrim(p.reference), ''),

                    'Payment for sale #' || p.saleid::text)::text,

           'OperatingIn'::text

           , p.createddate   -- 302: the entry time
    FROM   poultrypayments p

    WHERE  lower(p.farmid::text) = lower(p_farmid)

      AND  COALESCE(p.amount, 0) <> 0

      -- A REVERSED payment is money that came back. 222/227 added this column and

      -- flip it on reversal rather than deleting the row, so without this filter

      -- the report counts a refunded receipt as income for ever.

      AND  COALESCE(p.status, 'Posted') = 'Posted' 

      AND  p.paymentdate >= v_from

      AND  p.paymentdate <= v_to;



    -- ---- 2. the part paid at the counter -----------------------------------

    -- Not every receipt becomes a payment row: a sale entered as already paid

    -- sets amountpaid directly. Counting the difference here picks those up

    -- without double counting the ones that DID create a row.

    --

    -- `paid` is honoured ahead of amountpaid because older rows were marked paid

    -- without amountpaid ever being populated -- the same rule CashController

    -- applies. Without it, historic cash sales vanish from the report.

    RETURN QUERY

    SELECT 'SaleResidual'::text,

           FALSE,

           s.saleid,

           s.poultrycashaccountid,

           NULL::text,

           -- sale.saledate is DATE while this function returns TIMESTAMP, so the

           -- cast is load-bearing: without it Postgres refuses the whole

           -- function with "structure of query does not match function result

           -- type". The live 235 carries this; the copy of 235 in this repo does

           -- NOT, so anyone reproducing that file inherits the fault.

           s.saledate::timestamp,

           'CashIn'::text,

           'Sale'::text,

           s.saleid,

           FALSE,

           v.residual,

           ('Sale #' || s.saleid::text ||

            COALESCE(' - ' || NULLIF(btrim(s.customername), ''), ''))::text,

           'OperatingIn'::text

           , s.createddate   -- 302: the entry time
    FROM   sale s

    CROSS  JOIN LATERAL (

        SELECT ROUND(

                   CASE WHEN COALESCE(s.paid, false)

                        THEN COALESCE(s.totalamount, 0)

                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),

                                   COALESCE(s.totalamount, 0))

                   END

                 - COALESCE((SELECT SUM(pp.amount)

                             FROM   poultrypayments pp

                             WHERE  pp.saleid = s.saleid

                               AND  lower(pp.farmid::text) = lower(p_farmid)

                               -- Same reason: a reversed payment never covered

                               -- anything, so it must not reduce the residual.

                               AND  COALESCE(pp.status, 'Posted') = 'Posted'), 0)

               , 2) AS residual

    ) v

    WHERE  lower(s.farmid::text) = lower(p_farmid)

      -- Only a POSITIVE residual. A negative one means the payment rows already

      -- exceed what the sale records as paid, which is a data inconsistency; it

      -- is surfaced by this file's verification query rather than quietly

      -- subtracted from the day's income.

      AND  v.residual > 0

      AND  s.saledate >= v_from

      AND  s.saledate <= v_to;



    -- ---- 3. money paid out when the expense was recorded --------------------

    -- Every kind of spending, because every module writes here. NonCash is still

    -- the only category-level exclusion: internal use posts it to record stock

    -- leaving without any money moving (migration 216).

    --

    -- What changed from 235 is the AMOUNT. It was e.amount -- the full bill.

    -- It is now what was actually paid at entry: the expense's resolved

    -- amountpaid, less anything a supplier payment has since covered (which the

    -- next arm reports on its own, later, date).

    --

    -- amountpaid IS NULL means paid in full, so a legacy row resolves straight

    -- back to e.amount and this arm returns exactly what 235 returned.

    RETURN QUERY

    SELECT 'Expense'::text,

           FALSE,

           e.expenseid,

           e.poultrycashaccountid,

           NULL::text,

           e.expensedate,

           'CashOut'::text,

           'Expense'::text,

           e.expenseid,

           FALSE,

           -v.paidatentry,

           COALESCE(NULLIF(btrim(e.description), ''), e.category)::text,

           'OperatingOut'::text

           , e.createddate   -- 302: the entry time
    FROM   expense e

    CROSS  JOIN LATERAL (

        SELECT GREATEST(

                   COALESCE(e.amountpaid, e.amount)

                 - COALESCE((SELECT SUM(sa.amountapplied)

                             FROM   supplierpaymentallocation sa

                             WHERE  sa.farmid = p_farmid

                               AND  sa.module = 'poultry'

                               AND  sa.status = 'Posted'

                               AND  sa.documenttype = 'Expense'

                               AND  sa.documentid = e.expenseid), 0)

               , 0)::numeric AS paidatentry

    ) v

    WHERE  lower(e.farmid::text) = lower(p_farmid)

      AND  v.paidatentry > 0

      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'

      AND  e.expensedate >= v_from

      AND  e.expensedate <= v_to;



    -- ---- 3b. money paid out later, against a bill already recorded ----------

    -- A supplier payment settling an unpaid expense. It belongs to the day the

    -- money moved, not the day the bill was entered -- the same principle arm 1

    -- applies to customer receipts.

    --

    -- sourceid is the EXPENSE id so the row still drills through to the bill it

    -- paid (and so _detail's category join finds it); sourcerowid is the

    -- allocation id, which is what makes each row unique.

    --

    -- Only documenttype='Expense'. A payment against a raw-material purchase or

    -- a flock batch books its own expense row dated the payment date (224:414)

    -- and is already counted by arm 3; adding it here would double it.

    RETURN QUERY

    SELECT 'ExpensePayment'::text,

           FALSE,

           sa.allocationid,

           sp.poultrycashaccountid,

           NULL::text,

           sp.paymentdate,

           'CashOut'::text,

           'ExpensePayment'::text,

           sa.documentid,

           FALSE,

           -sa.amountapplied::numeric,

           ('Payment for expense #' || sa.documentid::text ||

            COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,

           'OperatingOut'::text

           , sa.createdat   -- 302: the entry time
    FROM   supplierpaymentallocation sa

    JOIN   poultrysupplierpayments sp

           ON  sp.poultrysupplierpaymentid = sa.paymentid

           AND sp.farmid = sa.farmid

    LEFT   JOIN supplier s

           ON  s.supplierid = sp.supplierid AND s.farmid = sp.farmid

    WHERE  sa.farmid = p_farmid

      AND  sa.module = 'poultry'

      AND  sa.status = 'Posted'

      AND  sa.documenttype = 'Expense'

      AND  sp.status = 'Posted'

      AND  sa.amountapplied <> 0

      AND  sp.paymentdate >= v_from

      AND  sp.paymentdate <= v_to;



    -- ---- 4. owner money (253) ----------------------------------------------

    -- Contributions and draws recorded through the Owner Money module.

    -- FINANCING, not operating: the owner funded the business or took funding

    -- back. Never revenue, never expense.

    --

    -- Reversed records are dropped entirely rather than netted to zero with a

    -- second row -- a contribution that was put in and taken back out is not

    -- funding, and showing both legs would put money the business never kept

    -- into Money In and Money Out.

    --

    -- Placed ABOVE the legacy capital arm on purpose: that arm RETURNs early

    -- when cashadjustment is absent, so anything below it is skipped on a farm

    -- with no capital records.

    RETURN QUERY

    SELECT 'OwnerMoney'::text,

           FALSE,

           o.poultryownermoneyid,

           o.poultrycashaccountid,

           a.accountname::text,

           o.transactiondate,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'CashIn' ELSE 'CashOut' END::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END::text,

           o.poultryownermoneyid,

           FALSE,

           -- Stored positive; the sign is applied here, once.

           (CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE -o.amount END)::numeric,

           COALESCE(NULLIF(btrim(o.notes), ''),

                    NULLIF(btrim(o.ownername), ''),

                    CASE WHEN o.transactiontype = 'Contribution'

                         THEN 'Owner contribution' ELSE 'Owner draw' END)::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'FinancingIn' ELSE 'FinancingOut' END::text

           , o.createdat   -- 302: the entry time
    FROM   poultryownermoney o

    LEFT   JOIN poultrycashaccounts a

           ON a.poultrycashaccountid = o.poultrycashaccountid

    WHERE  o.farmid = p_farmid

      AND  o.status = 'Posted'
      -- 296. A record backfilled from a Cash Flow adjustment has NO cash
      -- row of its own: the ADJUSTMENT is still the cash event, and the
      -- legacy adjustment arm below already reports it. Without this the
      -- same money is counted twice -- the trap 292 hit for loans.
      AND  o.sourceadjustmentid IS NULL

      AND  o.transactiondate >= v_from

      AND  o.transactiondate <= v_to;



    -- ---- 5. loans received (254) -------------------------------------------

    -- Borrowed money arriving. FINANCING: the business received it, it did not

    -- earn it, so it is money in and never revenue.

    --

    -- The AMOUNT RECEIVED, not the principal. A lender that withholds a fee

    -- pays out less than it lends, and only what arrived is cash in.

    RETURN QUERY

    SELECT 'Loan'::text,

           FALSE,

           l.poultryloanid,

           l.poultrycashaccountid,

           a.accountname::text,

           -- 256. loandate is a DATE, so this was always midnight and a loan

           -- recorded this afternoon sorted below everything else recorded

           -- today. Same rule as lib/utils/date-key.entryTimestamp: a loan

           -- dated TODAY carries the moment it was actually recorded, and a

           -- back-dated one keeps midnight, because nobody knows what time last

           -- Tuesday's disbursement landed.

           CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                ELSE l.loandate::timestamp END,

           'CashIn'::text,

           'LoanReceived'::text,

           l.poultryloanid,

           FALSE,

           l.amountreceived::numeric,

           ('Loan received from ' || l.lendername)::text,

           'FinancingIn'::text

           , l.createdat   -- 302: the entry time
    FROM   poultryloans l

    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = l.poultrycashaccountid

    WHERE  l.farmid = p_farmid

      AND  l.amountreceived > 0

      -- 292. A loan converted from a Cash Flow adjustment has NO cash row of

      -- its own: the ADJUSTMENT is the cash event, and arm 8 below already

      -- reports it. Without this the same borrowing is money-in twice -- which

      -- is precisely what the stage check caught.

      AND  l.sourceadjustmentid IS NULL

      AND  l.status NOT IN ('Cancelled', 'Reversed', 'Draft')

      AND  l.loandate::timestamp >= v_from

      AND  l.loandate::timestamp <= v_to;



    -- ---- 6. loan repayments (254) ------------------------------------------

    -- The FULL payment leaves the account, so the full payment is money out --

    -- principal, interest and fees together.

    --

    -- This does NOT double count the interest and fee expenses those payments

    -- create: they are written paymentmethod = 'NonCash', and arm 3 above skips

    -- NonCash. The P&L reads the expense table directly and still counts them,

    -- which is the whole point -- cash out is 12,500, cost is 2,500.

    RETURN QUERY

    SELECT 'LoanPayment'::text,

           FALSE,

           p.poultryloanpaymentid,

           p.poultrycashaccountid,

           a.accountname::text,

           p.paymentdate,

           'CashOut'::text,

           'LoanRepayment'::text,

           p.poultryloanid,

           FALSE,

           -p.totalamount::numeric,

           ('Loan repayment to ' || l.lendername)::text,

           'FinancingOut'::text

           , p.createdat   -- 302: the entry time
    FROM   poultryloanpayments p

    JOIN   poultryloans l ON l.poultryloanid = p.poultryloanid

    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = p.poultrycashaccountid

    WHERE  p.farmid = p_farmid

      AND  p.status = 'Posted'

      AND  p.paymentdate >= v_from

      AND  p.paymentdate <= v_to;



    -- ---- 7. capital in and out (legacy cash adjustments) --------------------

    -- Owner injections, loans received, withdrawals. Financing, not operating:

    -- money the business received or returned rather than earned or spent.

    --

    -- MUST STAY LAST: it RETURNs early when the table is absent, and anything

    -- below it would be silently skipped on a farm without capital records.

    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,

                      to_regclass('public.cashadjustments')::text);



    -- 302: only reference the creation column if the resolved table has one.
    SELECT CASE WHEN EXISTS (
               SELECT 1 FROM information_schema.columns c
               WHERE  c.table_schema = 'public'
                 AND  c.table_name = replace(v_tbl, 'public.', '')
                 AND  c.column_name = 'createddate')
           THEN 'ca.createddate' ELSE 'NULL::timestamp' END
      INTO v_createdcol;

    IF v_tbl IS NULL THEN

        RETURN;                     -- no capital records; the four legs stand

    END IF;



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

               ca.amount::numeric,     -- already signed

               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text,

               CASE WHEN ca.amount >= 0 THEN 'FinancingIn' ELSE 'FinancingOut' END::text,
               %s                       -- 302: the entry time

        FROM   %s ca

        WHERE  lower(ca.farmid::text) = lower($1)

          AND  ca.amount <> 0

          AND  ca.adjustmentdate >= $2

          AND  ca.adjustmentdate <= $3

    $sql$, v_createdcol, v_tbl)

    USING p_farmid, v_from, v_to;

    -- ---- 8. employee advances (305/307) ------------------------------------

    -- Disbursements out, manual repayments in, payroll deductions NOWHERE:

    -- a deduction moves no money, so it is not a cash event. The arms live in

    -- their own function, so this body is touched once and never again.

    RETURN QUERY

    SELECT * FROM public.sppoultryemployeeloan_cashflowrows(p_farmid, v_from, v_to);


END;

$function$;
-- -----------------------------------------------------------------------------
-- Verification.
--
-- The second check is the important one. This file on its own changes nothing
-- a user can see -- the arms only reach the report once sppoultrycashflow_rows
-- calls them. Passing silently would leave everyone believing employee
-- advances are on Cash Flow when they are not, and the first person to notice
-- would be whoever reconciled a bank statement against a report that was short
-- by every advance the farm had issued.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_body    text;
    v_leaked  integer;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'sppoultryemployeeloan_cashflowrows') THEN
        RAISE EXCEPTION '307: sppoultryemployeeloan_cashflowrows was not created.';
    END IF;

    -- No payroll repayment may ever surface as cash. Asserted against real
    -- rows rather than trusted from the filter above.
    SELECT COUNT(*) INTO v_leaked
    FROM   poultryemployeeloanrepayments r
    WHERE  r.sourcetype = 'Payroll'
      AND  (r.poultrycashaccountid IS NOT NULL OR r.poultrycashtransactionid IS NOT NULL);

    IF v_leaked > 0 THEN
        RAISE EXCEPTION
            '307: % payroll repayment(s) carry a cash account or a cash row. A payroll deduction moves no money.',
            v_leaked;
    END IF;

    SELECT pg_get_functiondef(p.oid) INTO v_body
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'sppoultrycashflow_rows'
    LIMIT  1;

    IF v_body IS NULL THEN
        RAISE EXCEPTION '307: sppoultrycashflow_rows does not exist on this database.';
    END IF;

    IF position('sppoultryemployeeloan_cashflowrows' in v_body) = 0 THEN
        RAISE EXCEPTION
            E'307: the arms exist but nothing calls them, so employee advances are NOT on Cash Flow yet.\n'
            'Add this as the last statement of sppoultrycashflow_rows, before its final END:\n'
            '    RETURN QUERY SELECT * FROM public.sppoultryemployeeloan_cashflowrows(p_farmid, v_from, v_to);\n'
            'Re-emit that function from its CURRENT body (pg_get_functiondef), not from the copy in this repo.';
    END IF;

    RAISE NOTICE '307_PoultryEmployeeLoanCashFlow: arms created and spliced, verified.';
END $$;

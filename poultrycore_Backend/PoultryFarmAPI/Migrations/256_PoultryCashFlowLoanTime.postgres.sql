-- =============================================================================
-- 256_PoultryCashFlowLoanTime.postgres.sql
--
-- Purpose
-- -------
-- A loan received today sorted below everything else received today.
--
-- Cash Flow lists newest first, on the full timestamp. Every other arm supplies
-- a real one -- a customer receipt, an expense and an owner-money record all
-- carry the moment they were entered. The loan arm did not: poultryloans.loandate
-- is a DATE column, so 254 cast it to a timestamp and got midnight, every time.
-- A loan recorded at four in the afternoon therefore appeared beneath the day's
-- other rows rather than on top of them.
--
-- THE RULE, AND WHY IT IS NOT "JUST USE createdat"
-- ------------------------------------------------
-- A loan dated TODAY takes the moment it was recorded. A loan dated any other
-- day keeps midnight.
--
-- Using createdat unconditionally would move a back-dated loan to whenever
-- somebody got round to typing it in -- a loan taken out last Tuesday and
-- entered this morning would sort into today, above rows that really did happen
-- after it. The date the money moved is what a cash flow is about; the
-- recording time only breaks ties within the day it belongs to.
--
-- This is exactly the rule lib/utils/date-key.entryTimestamp applies on the
-- frontend for every date-picker field, written once more in SQL because a DATE
-- column has nowhere to keep the time the frontend would have sent.
--
-- WHAT THIS DOES NOT FIX
-- ----------------------
-- Rows already stored at midnight stay at midnight -- there is no time to
-- recover, and inventing one would be worse than the tie. Only loans recorded
-- from now on, on the day they are dated, gain a real time.
--
-- EFFECT ON TODAY'S NUMBERS: none. One expression in one arm, changing the TIME
-- OF DAY a loan row reports -- never its date, its amount, its sign or its
-- grouping. Money in, money out and net cash flow are identical.
--
-- Order: after 255.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- Reproduced from the LIVE definition of sppoultrycashflow_rows, which already
-- carries 253's owner-money arm and 254's two loan arms. The ONLY change is the
-- transactiondate expression in the loans-received arm.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_tbl  text;
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
    FROM   poultryownermoney o
    LEFT   JOIN poultrycashaccounts a
           ON a.poultrycashaccountid = o.poultrycashaccountid
    WHERE  o.farmid = p_farmid
      AND  o.status = 'Posted'
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
    FROM   poultryloans l
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = l.poultrycashaccountid
    WHERE  l.farmid = p_farmid
      AND  l.amountreceived > 0
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
               CASE WHEN ca.amount >= 0 THEN 'FinancingIn' ELSE 'FinancingOut' END::text
        FROM   %s ca
        WHERE  lower(ca.farmid::text) = lower($1)
          AND  ca.amount <> 0
          AND  ca.adjustmentdate >= $2
          AND  ca.adjustmentdate <= $3
    $sql$, v_tbl)
    USING p_farmid, v_from, v_to;
END;
$function$;

COMMIT;

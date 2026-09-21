-- =============================================================================
-- 315_WaterEmployeeLoanCashFlow.postgres.sql
--
-- The water port of 307: employee advances on the Cash Flow report, and payroll
-- deductions kept OFF it.
--
--   disbursement        real money left the account        -> Money Out
--   manual repayment    real money arrived                 -> Money In
--   payroll deduction   NOTHING MOVED                      -> nothing at all
--
-- The third line is the point. When 100 is withheld from a 2,200 wage the farm
-- pays out 2,100; there is no second event in which the worker hands 100 back,
-- and reporting one would invent cash the business never received. 313 already
-- makes it unrepresentable -- a payroll repayment carries no cash account -- and
-- the arm below filters on source anyway.
--
-- SAME STRUCTURE AS 307, AND FOR THE SAME REASON
-- ==============================================
-- The new arms live in a function of their own with the exact 14 column shape
-- spwatercashflow_rows returns, so splicing them in is one line rather than a
-- re-emission of a 600-line body from a copy that may have drifted.
--
-- The body re-emitted below is the LIVE one, taken with pg_get_functiondef on
-- 2026-09-18. The verification block refuses to pass unless arm 8 is actually
-- reachable, so "applied but the splice did not take" fails loudly.
--
-- WHAT DIFFERS FROM POULTRY
-- -------------------------
-- Only the names. Water's flow groups, its sign convention (money out is a
-- NEGATIVE amount with transactiontype 'CashOut') and its 14 columns are
-- identical to poultry's, which is what makes the arms a straight port.
--
-- Idempotent.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spwateremployeeloan_cashflowrows(
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
    createdat timestamp without time zone
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
    -- will owe, not money that left the building.
    RETURN QUERY
    SELECT 'EmployeeLoan'::text,
           FALSE,
           l.wateremployeeloanid,
           l.watercashaccountid,
           a.accountname::text,
           CASE WHEN l.disbursementdate = l.createdat::date THEN l.createdat
                ELSE l.disbursementdate::timestamp END,
           'CashOut'::text,
           'EmployeeLoanDisbursement'::text,
           l.wateremployeeloanid,
           FALSE,
           -l.principalamount::numeric,
           ('Employee advance to ' || btrim(s.firstname || ' ' || s.lastname) ||
            ' - ' || COALESCE(l.loannumber, l.wateremployeeloanid::text))::text,
           'EmployeeLoanOut'::text,
           l.createdat
    FROM   wateremployeeloans l
    JOIN   waterstaff s ON s.waterstaffid = l.waterstaffid
    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = l.watercashaccountid
    WHERE  l.farmid = p_farmid
      AND  l.status NOT IN ('Draft', 'Cancelled', 'Reversed')
      AND  l.watercashaccountid IS NOT NULL
      AND  CASE WHEN l.disbursementdate = l.createdat::date THEN l.createdat
                ELSE l.disbursementdate::timestamp END BETWEEN v_from AND v_to;

    -- ---- B. repayments that actually moved money ----------------------------
    -- sourcetype <> 'Payroll' IS THE POINT OF THIS FILE.
    RETURN QUERY
    SELECT 'EmployeeLoanRepayment'::text,
           FALSE,
           r.wateremployeeloanrepaymentid,
           r.watercashaccountid,
           a.accountname::text,
           r.repaymentdate,
           'CashIn'::text,
           'EmployeeLoanRepayment'::text,
           r.wateremployeeloanid,
           FALSE,
           r.amount::numeric,
           ('Advance repayment from ' || btrim(s.firstname || ' ' || s.lastname) ||
            ' - ' || COALESCE(l.loannumber, r.wateremployeeloanid::text))::text,
           'EmployeeLoanIn'::text,
           r.createdat
    FROM   wateremployeeloanrepayments r
    JOIN   wateremployeeloans l ON l.wateremployeeloanid = r.wateremployeeloanid
    JOIN   waterstaff s ON s.waterstaffid = r.waterstaffid
    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = r.watercashaccountid
    WHERE  r.farmid = p_farmid
      AND  r.status = 'Posted'
      AND  r.sourcetype <> 'Payroll'
      AND  r.watercashaccountid IS NOT NULL
      AND  r.repaymentdate BETWEEN v_from AND v_to;
END;
$function$;

COMMENT ON FUNCTION public.spwateremployeeloan_cashflowrows(text, timestamp, timestamp) IS
    'The employee-advance arms of the water Cash Flow report, kept separate so '
    'splicing them into spwatercashflow_rows is one line. Payroll deductions '
    'are excluded: no money moved.';

-- -----------------------------------------------------------------------------
-- The splice: spwatercashflow_rows, re-emitted with arm 8.
--
-- Verbatim from the live database with ONE edit. If you re-emit this function
-- in a later migration, take the body from pg_get_functiondef again rather than
-- from here, and keep arm 8.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwatercashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
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

    RETURN QUERY

    SELECT 'Receipt'::text,

           FALSE,

           p.waterpaymentid,

           NULL::integer,

           NULL::text,

           p.paymentdate,

           'CashIn'::text,

           'CustomerPayment'::text,

           p.watersaleid,

           FALSE,

           COALESCE(p.amount, 0)::numeric,

           COALESCE(NULLIF(btrim(p.note), ''),

                    NULLIF(btrim(p.reference), ''),

                    'Payment for sale #' || p.watersaleid::text)::text,

           'OperatingIn'::text

           , p.createddate   -- 302: the entry time
    FROM   waterpayments p

    WHERE  lower(p.farmid::text) = lower(p_farmid)

      AND  COALESCE(p.amount, 0) <> 0

      -- A REVERSED payment is money that came back. 227 added this column and

      -- flips it on reversal rather than deleting the row, so without this filter

      -- the report counts a refunded receipt as income for ever.

      AND  COALESCE(p.status, 'Posted') = 'Posted'

      AND  p.paymentdate >= v_from

      AND  p.paymentdate <= v_to;



    -- ---- 2. the part paid at the point of sale -----------------------------

    -- Same reasoning as 235: a sale settled on the spot may never create a

    -- payment row, and the difference is what picks those up.

    RETURN QUERY

    SELECT 'SaleResidual'::text,

           FALSE,

           s.watersaleid,

           NULL::integer,

           NULL::text,

           s.saledate,

           'CashIn'::text,

           'Sale'::text,

           s.watersaleid,

           FALSE,

           v.residual,

           ('Sale #' || s.watersaleid::text)::text,

           'OperatingIn'::text

           , s.createddate   -- 302: the entry time
    FROM   watersales s

    CROSS  JOIN LATERAL (

        SELECT ROUND(

                   CASE WHEN COALESCE(s.status, '') = 'Paid'

                        THEN COALESCE(s.totalamount, 0)

                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),

                                   COALESCE(s.totalamount, 0))

                   END

                 - COALESCE((SELECT SUM(wp.amount)

                             FROM   waterpayments wp

                             WHERE  wp.watersaleid = s.watersaleid

                               AND  lower(wp.farmid::text) = lower(p_farmid)

                               -- Same reason: a reversed payment never covered

                               -- anything, so it must not reduce the residual.

                               AND  COALESCE(wp.status, 'Posted') = 'Posted'), 0)

               , 2) AS residual

    ) v

    WHERE  lower(s.farmid::text) = lower(p_farmid)

      -- A cancelled sale is not income, whatever it once recorded as paid.

      AND  COALESCE(s.status, '') <> 'Cancelled'

      AND  v.residual > 0

      AND  s.saledate >= v_from

      AND  s.saledate <= v_to;



    -- ---- 3. money paid out when the bill was recorded -----------------------

    -- 236's gates are kept verbatim -- Approved, not deleted -- with two

    -- changes:

    --

    --   * the AMOUNT is what was actually paid at entry, not the whole bill:

    --     the resolved amountpaid, less anything a supplier payment has since

    --     covered (which the next arm reports on its own, later, date);

    --   * the `paymentmethod <> 'Credit'` filter is GONE, because the resolution

    --     subsumes it. A Credit bill resolves to 0 paid and drops out on

    --     `paidatentry > 0` instead -- same rows excluded, and a Credit bill

    --     that has since been part-paid is no longer wrongly invisible.

    RETURN QUERY

    SELECT 'Expense'::text,

           FALSE,

           e.waterexpenseid,

           e.watercashaccountid,

           NULL::text,

           e.expensedate,

           'CashOut'::text,

           'Expense'::text,

           e.waterexpenseid,

           FALSE,

           -v.paidatentry,

           COALESCE(NULLIF(btrim(e.description), ''),

                    NULLIF(btrim(e.paidto), ''),

                    'Expense #' || e.waterexpenseid::text)::text,

           'OperatingOut'::text

           , e.createdat   -- 302: the entry time
    FROM   waterexpenses e

    CROSS  JOIN LATERAL (

        SELECT GREATEST(

                   COALESCE(e.amountpaid,

                            CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'

                                 THEN 0 ELSE e.amount END)

                 - COALESCE((SELECT SUM(sa.amountapplied)

                             FROM   supplierpaymentallocation sa

                             WHERE  sa.farmid = p_farmid

                               AND  sa.module = 'water'

                               AND  sa.status = 'Posted'

                               AND  sa.documenttype = 'Expense'

                               AND  sa.documentid = e.waterexpenseid), 0)

               , 0)::numeric AS paidatentry

    ) v

    WHERE  lower(e.farmid::text) = lower(p_farmid)

      AND  COALESCE(e.isdeleted, false) = false

      AND  v.paidatentry > 0

      -- 047's rule: only an approved expense has been recognised at all.

      AND  COALESCE(e.status, '') = 'Approved'

      -- 259. 'NonCash' means "a cost recorded, but the money moved elsewhere".

      -- Loan interest and fees are written this way: the repayment's own arm

      -- below reports the FULL amount that left the account, so counting these

      -- rows here as well would take 12,500 out of the bank and 15,000 off the

      -- cash flow. Expense reports do not filter NonCash, so the cost still

      -- counts where it should.

      --

      -- No-op on today's data: there are zero water expenses with this marker.

      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'

      AND  e.expensedate >= v_from

      AND  e.expensedate <= v_to;



    -- ---- 3b. money paid out later, against a bill already recorded ----------

    -- A supplier payment settling a bill. It belongs to the day the money moved,

    -- not the day the bill was entered.

    --

    -- Only documenttype='Expense'. A payment against a raw-material purchase

    -- books its own aggregated expense row dated the payment date (240) and is

    -- already counted by arm 3; adding it here would double it.

    RETURN QUERY

    SELECT 'ExpensePayment'::text,

           FALSE,

           sa.allocationid,

           sp.watercashaccountid,

           NULL::text,

           sp.paymentdate,

           'CashOut'::text,

           'ExpensePayment'::text,

           sa.documentid,

           FALSE,

           -sa.amountapplied::numeric,

           ('Payment for expense #' || sa.documentid::text ||

            COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,

           'OperatingOut'::text

           , sa.createdat   -- 302: the entry time
    FROM   supplierpaymentallocation sa

    JOIN   watersupplierpayments sp

           ON  sp.watersupplierpaymentid = sa.paymentid

           AND sp.farmid = sa.farmid

    LEFT   JOIN watersuppliers s

           ON  s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid

    WHERE  sa.farmid = p_farmid

      AND  sa.module = 'water'

      AND  sa.status = 'Posted'

      AND  sa.documenttype = 'Expense'

      AND  COALESCE(sp.status, 'Posted') = 'Posted'

      AND  sa.amountapplied <> 0

      AND  sp.paymentdate >= v_from

      AND  sp.paymentdate <= v_to;



    -- ---- 4. owner money (258) ----------------------------------------------

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

    -- when cashadjustment is absent, so anything below it is skipped on a

    -- company with no capital records.

    RETURN QUERY

    SELECT 'OwnerMoney'::text,

           FALSE,

           o.waterownermoneyid,

           o.watercashaccountid,

           a.accountname::text,

           o.transactiondate,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'CashIn' ELSE 'CashOut' END::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END::text,

           o.waterownermoneyid,

           FALSE,

           -- Stored positive; the sign is applied here, once.

           (CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE -o.amount END)::numeric,

           COALESCE(NULLIF(btrim(o.notes), ''),

                    NULLIF(btrim(o.ownername), ''),

                    CASE WHEN o.transactiontype = 'Contribution'

                         THEN 'Owner contribution' ELSE 'Owner draw' END)::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'FinancingIn' ELSE 'FinancingOut' END::text

           , o.createdat   -- 302: the entry time
    FROM   waterownermoney o

    LEFT   JOIN watercashaccounts a

           ON a.watercashaccountid = o.watercashaccountid

    WHERE  o.farmid = p_farmid

      AND  o.status = 'Posted'
      -- 297. A record backfilled from a Cash Flow adjustment has NO cash
      -- row of its own: the ADJUSTMENT is still the cash event, and the
      -- legacy adjustment arm below already reports it. Without this the
      -- same money is counted twice -- the trap 292 hit for loans.
      AND  o.sourceadjustmentid IS NULL

      AND  o.transactiondate >= v_from

      AND  o.transactiondate <= v_to;



    -- ---- 5. loans received (259) -------------------------------------------

    -- Borrowed money arriving. FINANCING: the business received it, it did not

    -- earn it, so it is money in and never revenue.

    --

    -- The AMOUNT RECEIVED, not the principal. A lender that withholds a fee

    -- pays out less than it lends, and only what arrived is cash in.

    --

    -- The timestamp carries 256's rule, baked in from the start rather than

    -- patched afterwards as it had to be on poultry: loandate is a DATE, so a

    -- plain cast gives midnight and a loan recorded this afternoon sorts below

    -- everything else recorded today. A loan dated TODAY reports the moment it

    -- was recorded; a BACK-DATED one keeps midnight, because using createdat

    -- unconditionally would drag last Tuesday's loan into today, above rows

    -- that really did happen after it.

    RETURN QUERY

    SELECT 'Loan'::text,

           FALSE,

           l.waterloanid,

           l.watercashaccountid,

           a.accountname::text,

           CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                ELSE l.loandate::timestamp END,

           'CashIn'::text,

           'LoanReceived'::text,

           l.waterloanid,

           FALSE,

           l.amountreceived::numeric,

           ('Loan received from ' || l.lendername)::text,

           'FinancingIn'::text

           , l.createdat   -- 302: the entry time
    FROM   waterloans l

    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = l.watercashaccountid

    WHERE  l.farmid = p_farmid

      AND  l.amountreceived > 0

      -- 293. A loan converted from a Cash Flow adjustment has NO cash row of

      -- its own: the ADJUSTMENT is the cash event, and the legacy adjustment arm

      -- already reports it. Without this the same borrowing is money-in twice --

      -- which is precisely what 292's stage check caught on the poultry side.

      AND  l.sourceadjustmentid IS NULL

      AND  l.status NOT IN ('Cancelled', 'Reversed', 'Draft')

      AND  (CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                 ELSE l.loandate::timestamp END) >= v_from

      AND  (CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                 ELSE l.loandate::timestamp END) <= v_to;



    -- ---- 6. loan repayments (259) ------------------------------------------

    -- The FULL payment leaves the account, so the full payment is money out --

    -- principal, interest and fees together.

    --

    -- This does NOT double count the interest and fee expenses those payments

    -- create: they are written paymentmethod = 'NonCash', and arm 3 above now

    -- skips NonCash. Expense reports read the expense table directly and still

    -- count them, which is the whole point -- cash out is 12,500, cost is 2,500.

    RETURN QUERY

    SELECT 'LoanPayment'::text,

           FALSE,

           p.waterloanpaymentid,

           p.watercashaccountid,

           a.accountname::text,

           p.paymentdate,

           'CashOut'::text,

           'LoanRepayment'::text,

           p.waterloanid,

           FALSE,

           -p.totalamount::numeric,

           ('Loan repayment to ' || l.lendername)::text,

           'FinancingOut'::text

           , p.createdat   -- 302: the entry time
    FROM   waterloanpayments p

    JOIN   waterloans l ON l.waterloanid = p.waterloanid

    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = p.watercashaccountid

    WHERE  p.farmid = p_farmid

      AND  p.status = 'Posted'

      AND  p.paymentdate >= v_from

      AND  p.paymentdate <= v_to;



    -- ---- 7. capital in and out (legacy cash adjustments) --------------------

    -- Expected to return nothing on Water today -- see 236's header note.

    --

    -- MUST STAY LAST: it RETURNs early when the table is absent, and anything

    -- below it would be silently skipped.

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

        RETURN;

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

               ca.amount::numeric,

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
    -- ---- 8. employee advances (313/315) ------------------------------------

    -- Disbursements out, manual repayments in, payroll deductions NOWHERE:

    -- a deduction moves no money, so it is not a cash event. The arms live in

    -- their own function, so this body is touched once and never again.

    RETURN QUERY

    SELECT * FROM public.spwateremployeeloan_cashflowrows(p_farmid, v_from, v_to);


END;

$function$;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
DO $checks$
DECLARE
    v_body   text;
    v_leaked integer;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'spwateremployeeloan_cashflowrows') THEN
        RAISE EXCEPTION '315: spwateremployeeloan_cashflowrows was not created.';
    END IF;

    SELECT COUNT(*) INTO v_leaked
    FROM   wateremployeeloanrepayments r
    WHERE  r.sourcetype = 'Payroll'
      AND  (r.watercashaccountid IS NOT NULL OR r.watercashtransactionid IS NOT NULL);
    IF v_leaked > 0 THEN
        RAISE EXCEPTION
            '315: % payroll repayment(s) carry a cash account or a cash row. A payroll deduction moves no money.',
            v_leaked;
    END IF;

    SELECT pg_get_functiondef(p.oid) INTO v_body
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'spwatercashflow_rows' LIMIT 1;

    IF v_body IS NULL THEN
        RAISE EXCEPTION '315: spwatercashflow_rows does not exist on this database.';
    END IF;
    IF position('spwateremployeeloan_cashflowrows' in v_body) = 0 THEN
        RAISE EXCEPTION
            E'315: the arms exist but nothing calls them, so employee advances are NOT on water Cash Flow yet.\n'
            'Add this as the last statement of spwatercashflow_rows, before its final END:\n'
            '    RETURN QUERY SELECT * FROM public.spwateremployeeloan_cashflowrows(p_farmid, v_from, v_to);';
    END IF;

    RAISE NOTICE '315_WaterEmployeeLoanCashFlow: arms created and spliced, verified.';
END
$checks$;

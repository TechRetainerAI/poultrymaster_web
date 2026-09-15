-- =============================================================================
-- 293_WaterLoanFromCashAdjustment.postgres.sql
--
-- Purpose
-- -------
-- Let a borrowing that was recorded on the Cash Flow page become a REAL loan --
-- so it can be repaid.
--
-- 291 made those adjustments visible on the Loans page and counted them as debt.
-- Its header named the dead end it was creating, and this file is the way out:
--
--   "A cash adjustment has no repayment mechanism ... its outstanding balance
--    CANNOT BE REDUCED FROM THIS PAGE."
--
-- THE HARD PART IS NOT CREATING THE LOAN. IT IS NOT MOVING THE CASH.
-- ===================================================================
-- Trace what each side already does to the ledger, because the obvious
-- implementations all get this wrong:
--
--   the adjustment   spwatercashflow_rows reads it as FinancingIn/FinancingOut
--                    with offledger = FALSE and cashaccountid = NULL. So it
--                    COUNTS as company cash, but belongs to no cash account and
--                    has never touched watercashaccounts.currentbalance.
--
--   spwaterloan_create   writes its own 'LoanReceived' row into
--                    watercashtransactions and ADDS to a cash account's
--                    balance, whenever amountreceived > 0.
--
-- So the three tempting designs each break something:
--
--   create the loan and keep the adjustment   -> the same money is counted
--                                                twice in Cash Flow, and 291
--                                                counts the debt twice too.
--   create the loan and delete the adjustment -> cash flow loses the
--                                                adjustment's FinancingIn and
--                                                gains the loan's cash row. Net
--                                                zero at company level, but a
--                                                cash ACCOUNT balance rises by
--                                                money it never received --
--                                                the adjustment was attached to
--                                                no account. A reconciled
--                                                account silently stops
--                                                matching the drawer.
--   create the loan with no cash and delete   -> cash flow simply LOSES the
--                                                money. It really did arrive.
--
-- WHAT THIS FILE DOES INSTEAD
-- ===========================
-- The loan is created with NO CASH LEG AT ALL, and the adjustment is LEFT
-- EXACTLY WHERE IT IS. The adjustment goes on being the cash event -- it always
-- was -- and the loan becomes the DEBT record standing beside it. The two are
-- linked by waterloans.sourceadjustmentid, and 291's legacy read skips any
-- adjustment that has been converted, so the debt is counted once.
--
-- Net effect on every number in the system: NOTHING MOVES. Not cash flow, not a
-- cash account balance, not the P&L, not what the company owes. The only thing
-- that changes is that the debt now has a lender, a schedule if you want one,
-- and a repayment path.
--
-- That is why this migration can be checked the same way every other one today
-- has been: "No change to any measured total."
--
-- WHAT CANNOT BE CONVERTED, AND WHY IT RAISES RATHER THAN GUESSES
-- ===============================================================
--   not 'LoanReceived'   an owner injection or a correction is not a borrowing.
--   amount <= 0          waterloans has CHECK (originalprincipal > 0), and a
--                        negative LoanReceived is a CORRECTION to an
--                        over-stated borrowing (291's header). A correction is
--                        not a loan; converting one would invent a debt.
--   already converted    enforced by a unique index, not just a check, so two
--                        people clicking at once cannot both win.
--   no lender name       waterloans.lendername is NOT NULL, and the whole
--                        point of converting is to say who lent the money.
--                        Defaulting it to 'Unknown' would put a fiction in the
--                        loan book.
--
-- THE ONE THING THIS DOES NOT PREVENT
-- ===================================
-- The Cash page still owns the adjustment and can still edit or delete it after
-- conversion. Do that and the cash event and the debt record disagree: the loan
-- keeps the old amount. Nothing in the database can stop it without taking
-- ownership of a table shared with the Cash page, which is a bigger change than
-- this is. The conversion stamps the adjustment id and the amount on the loan's
-- notes so the divergence is at least discoverable.
--
-- Order: after 292.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Refuse to run out of order.
-- -----------------------------------------------------------------------------
DO $guard$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public' AND p.proname = 'fnwaterloan_legacy'
    ) THEN
        RAISE EXCEPTION '293 requires 291 (fnwaterloan_legacy is missing).';
    END IF;
END
$guard$;

-- -----------------------------------------------------------------------------
-- 1. The link.
--
-- On the LOAN, not on the adjustment. cashadjustment is shared with the Cash
-- page and with every other module -- poultry and water both read the same
-- table, discriminated by farmid -- so adding a column there would be a change
-- to somebody else's furniture. The loan is ours.
-- -----------------------------------------------------------------------------
ALTER TABLE waterloans
    ADD COLUMN IF NOT EXISTS sourceadjustmentid integer NULL;

COMMENT ON COLUMN waterloans.sourceadjustmentid IS
    'The cashadjustment this loan was converted from (292). When set, the cash '
    'for this borrowing is the ADJUSTMENT, not a loan cash row -- which is why '
    'such a loan has no watercashtransactionid. 290''s legacy read skips a '
    'converted adjustment so the debt is counted once.';

-- One loan per adjustment, enforced rather than hoped for: two people clicking
-- Convert at the same moment must not both succeed.
CREATE UNIQUE INDEX IF NOT EXISTS ux_waterloans_sourceadjustment
    ON waterloans (sourceadjustmentid)
    WHERE sourceadjustmentid IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 2. The legacy read learns to skip a converted adjustment.
--
-- Reproduced from 291 with one clause added. Without it the borrowing would
-- appear twice on the Loans page the moment it was converted -- once as the
-- adjustment, once as the loan -- and the debt would double.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwaterloan_legacy(p_farmid text)
RETURNS TABLE(
    adjustmentid integer,
    loandate     date,
    amount       numeric,
    description  text,
    createdby    text,
    createdat    timestamp
)
LANGUAGE plpgsql STABLE
AS $function$
DECLARE
    v_tbl text;
BEGIN
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    IF v_tbl IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY EXECUTE format($sql$
        SELECT ca.adjustmentid,
               ca.adjustmentdate::date,
               ca.amount::numeric,
               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text,
               ca.userid::text,
               ca.createddate::timestamp
        FROM   %s ca
        WHERE  lower(ca.farmid::text) = lower($1)
          AND  ca.adjustmenttype = 'LoanReceived'
          AND  ca.amount <> 0
          -- 293. Converted ones are represented by their loan now.
          AND  NOT EXISTS (SELECT 1 FROM waterloans l
                           WHERE l.sourceadjustmentid = ca.adjustmentid)
    $sql$, v_tbl)
    USING p_farmid;
END;
$function$;

COMMENT ON FUNCTION public.fnwaterloan_legacy(text) IS
    'Borrowings recorded on the Cash / Cash Flow pages as LoanReceived '
    'adjustments, shaped for the loan book. Amount is SIGNED so a negative '
    'correction nets off. Excludes any adjustment already converted to a real '
    'loan by 293. Read-only: the Cash page owns these rows.';

-- -----------------------------------------------------------------------------
-- 3. The conversion.
--
-- Deliberately NOT a call to spwaterloan_create. That function writes a cash
-- row and moves an account balance, which is exactly what must not happen here
-- -- the money already arrived, and it arrived as the adjustment. This inserts
-- the loan row directly and leaves the ledger alone.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterloan_fromadjustment(
    p_farmid          text,
    p_adjustmentid    integer,
    p_lendername      text,
    p_lendertype      text    DEFAULT 'Other',
    p_accountnumber   text    DEFAULT NULL,
    p_interestrate    numeric DEFAULT NULL,
    p_interesttype    text    DEFAULT NULL,
    p_termmonths      integer DEFAULT NULL,
    p_paymentfrequency text   DEFAULT NULL,
    p_enddate         date    DEFAULT NULL,
    p_nextpaymentdate date    DEFAULT NULL,
    p_notes           text    DEFAULT NULL,
    p_createdby       text    DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_tbl    text;
    v_date   date;
    v_amount numeric(14,2);
    v_desc   text;
    v_id     integer;
BEGIN
    IF COALESCE(btrim(p_lendername), '') = '' THEN
        RAISE EXCEPTION 'Who lent the money? A loan needs a lender.';
    END IF;

    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    IF v_tbl IS NULL THEN
        RAISE EXCEPTION 'There are no cash adjustments on this database to convert.';
    END IF;

    EXECUTE format($sql$
        SELECT ca.adjustmentdate::date, ca.amount::numeric(14,2),
               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text
        FROM   %s ca
        WHERE  ca.adjustmentid = $1
          AND  lower(ca.farmid::text) = lower($2)
          AND  ca.adjustmenttype = 'LoanReceived'
    $sql$, v_tbl)
    INTO v_date, v_amount, v_desc
    USING p_adjustmentid, p_farmid;

    IF v_date IS NULL THEN
        RAISE EXCEPTION 'Cash adjustment % is not a "Loan received" entry for this company.',
              p_adjustmentid;
    END IF;

    -- A negative LoanReceived is a CORRECTION to an over-stated borrowing, not
    -- a debt. waterloans would reject it anyway (originalprincipal > 0); this
    -- says why instead of surfacing a constraint name.
    IF v_amount <= 0 THEN
        RAISE EXCEPTION
          'Cash adjustment % is for %, which is a correction rather than a borrowing. '
          'Corrections cannot become loans -- they reduce one.', p_adjustmentid, v_amount;
    END IF;

    IF EXISTS (SELECT 1 FROM waterloans l WHERE l.sourceadjustmentid = p_adjustmentid) THEN
        RAISE EXCEPTION 'Cash adjustment % has already been made into a loan.', p_adjustmentid;
    END IF;

    -- No cash row, no balance change. The adjustment IS the cash event.
    -- watercashaccountid and watercashtransactionid are left NULL for the
    -- same reason: there is no loan cash movement to point at.
    INSERT INTO waterloans (
        farmid, lendername, lendertype, accountnumber, loandate,
        originalprincipal, amountreceived,
        interestrate, interesttype, termmonths, paymentfrequency,
        startdate, enddate, nextpaymentdate,
        outstandingprincipal, status, notes, createdby, sourceadjustmentid)
    VALUES (
        p_farmid, btrim(p_lendername), COALESCE(p_lendertype, 'Other'),
        NULLIF(btrim(p_accountnumber), ''), v_date,
        v_amount, v_amount,
        p_interestrate, p_interesttype, p_termmonths, p_paymentfrequency,
        v_date, p_enddate, p_nextpaymentdate,
        v_amount, 'Active',
        -- The trail, so a later divergence between the adjustment and the loan
        -- is discoverable rather than mysterious. See the header.
        btrim(COALESCE(NULLIF(btrim(p_notes), '') || chr(10), '')
              || 'Converted from Cash Flow adjustment #' || p_adjustmentid::text
              || ' (' || v_amount::text || ') on '
              || to_char((now() at time zone 'utc'), 'YYYY-MM-DD')
              || COALESCE('. Original note: ' || NULLIF(v_desc, ''), '')),
        p_createdby, p_adjustmentid)
    RETURNING waterloanid INTO v_id;

    UPDATE waterloans
    SET    loannumber = 'LN-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  waterloanid = v_id;

    RETURN v_id;
END;
$function$;

COMMENT ON FUNCTION public.spwaterloan_fromadjustment(text, integer, text, text, text, numeric, text, integer, text, date, date, text, text) IS
    'Turn a Cash Flow "Loan received" adjustment into a real, repayable loan. '
    'Writes NO cash row and moves NO balance -- the adjustment remains the cash '
    'event, and this is the debt record beside it. Refuses a non-LoanReceived '
    'row, a negative amount (that is a correction) and a second conversion.';

-- -----------------------------------------------------------------------------
-- 3b. Cash Flow must not count the same money twice.
--
-- The loans arm of spwatercashflow_rows reads waterloans directly on
-- `amountreceived > 0` -- it does NOT look for a cash transaction. So a
-- converted loan, which deliberately has no cash row, was still reported as
-- money in, ON TOP of the adjustment that actually carried it. The stage check
-- caught it as "cash flow unmoved expect 0.00 got 4000.00".
--
-- Reproduced from the LIVE definition with ONE predicate added, marked 293.
-- Every other arm -- receipts, counter sales, expenses, transfers, owner money,
-- repayments, the legacy adjustments -- is byte for byte what it was.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwatercashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
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
    FROM   waterownermoney o
    LEFT   JOIN watercashaccounts a
           ON a.watercashaccountid = o.watercashaccountid
    WHERE  o.farmid = p_farmid
      AND  o.status = 'Posted'
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

-- -----------------------------------------------------------------------------
-- 4. Grants.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.fnwaterloan_legacy(text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spwaterloan_fromadjustment(
            text, integer, text, text, text, numeric, text, integer, text, date, date, text, text)
            TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'the link column exists' AS check,
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_name = 'waterloans' AND column_name = 'sourceadjustmentid')
            THEN 'OK' ELSE 'MISSING' END AS result

UNION ALL
SELECT 'one loan per adjustment is enforced',
       CASE WHEN EXISTS (SELECT 1 FROM pg_indexes
                         WHERE indexname = 'ux_waterloans_sourceadjustment')
            THEN 'OK' ELSE 'MISSING' END

UNION ALL
SELECT 'the legacy read skips converted rows',
       CASE WHEN position('sourceadjustmentid' in pg_get_functiondef(p.oid)) > 0
            THEN 'OK' ELSE 'NOT WIRED' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'fnwaterloan_legacy'

UNION ALL
SELECT 'cash flow skips converted loans',
       CASE WHEN position('sourceadjustmentid' in pg_get_functiondef(p.oid)) > 0
            THEN 'OK' ELSE 'NOT WIRED -- the money would be counted twice' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'spwatercashflow_rows'

UNION ALL
-- Nothing has been converted yet, so nothing can have changed.
SELECT 'no loan is converted yet',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   waterloans WHERE sourceadjustmentid IS NOT NULL;

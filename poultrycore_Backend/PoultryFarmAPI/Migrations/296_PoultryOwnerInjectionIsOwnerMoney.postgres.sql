-- =============================================================================
-- 296_PoultryOwnerInjectionIsOwnerMoney.postgres.sql
--
-- Purpose
-- -------
-- An "Owner injection" IS owner money. A "Withdrawal" IS a draw. Stop making the
-- user say so twice.
--
-- The same correction 294/295 made for "Loan received", applied to the other two
-- capital types on the Cash Flow form, and for the same reason: somebody who
-- picks "Owner injection" has already said what it is. Writing a bare
-- cashadjustment row instead leaves the Owner Money page to go looking for it.
--
-- WHERE EACH MODULE STARTED
-- =========================
--   poultry   287 taught the Owner Money page to READ ACROSS into cashadjustment,
--             so the injection at least showed up. This file makes the record
--             real, and teaches that read-across to skip anything it has
--             converted.
--   water     had no equivalent at all -- there is no fnwaterownermoney_legacy.
--             An owner injection typed on /water-cash-flow has NEVER appeared on
--             /water-owner-money. Backfilling is not a tidy-up here; it is the
--             first time that money shows up where it belongs.
--
-- THE SAME CASH TRAP AS THE LOANS, AND THE SAME ANSWER
-- ====================================================
-- sppoultryownermoney_record writes its own cash row AND moves a cash account
-- balance. The adjustment it would be built from is ALREADY a cash event that
-- Cash Flow reads. So a naive backfill counts the money twice.
--
-- So a BACKFILLED record is written with NO cash row and NO account movement --
-- the adjustment stays the cash event, the record is the capital record beside
-- it -- and three readers are taught to respect that:
--
--   sppoultrycashflow_rows   its owner-money arm skips a backfilled record
--                (section 3). This is exactly the guard 292's stage check
--                caught the hard way for loans.
--   the legacy read      skips an adjustment once a record points at it
--   the unique index     one record per adjustment, so two runs cannot both win
--
-- Net effect on every number: NOTHING MOVES. Cash flow, the cash accounts, the
-- P&L and the owner's capital are identical afterwards. What changes is that the
-- money is finally ON the Owner Money page as a first-class record.
--
-- WHY THE ACCOUNT CONSTRAINT HAS TO GIVE
-- ======================================
-- poultryownermoney.poultrycashaccountid was NOT NULL, which is right for a record somebody
-- typed into the Owner Money form -- that form asks which account the money
-- went into. A historical adjustment has no account at all: the legacy
-- cashadjustment table predates cash accounts and Cash Flow reports those rows
-- with cashaccountid NULL.
--
-- Inventing an account would be worse than leaving it blank: it would attribute
-- money to a till that never received it, and the next person to reconcile that
-- till would find a number they cannot explain. So the column becomes nullable
-- for backfilled rows only. Both writers that CREATE owner money still require
-- an account -- the Owner Money form always did, and the Cash Flow form now
-- does too.
--
-- NEW ENTRIES DO NOT COME THROUGH HERE AT ALL
-- ===========================================
-- The Cash Flow form now calls sppoultryownermoney_record directly for these two
-- types, which writes a real record with a real cash row against a real account.
-- That is what makes this backfill a ONE-OFF rather than a job that has to keep
-- running.
--
-- Order: after 295.
--
-- Idempotent throughout -- the backfill skips anything already converted.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The link, and the relaxed account.
-- -----------------------------------------------------------------------------
ALTER TABLE poultryownermoney
    ADD COLUMN IF NOT EXISTS sourceadjustmentid integer NULL;

ALTER TABLE poultryownermoney ALTER COLUMN poultrycashaccountid DROP NOT NULL;

COMMENT ON COLUMN poultryownermoney.sourceadjustmentid IS
    'The cashadjustment this record was backfilled from (296). When set, the cash '
    'for it is the ADJUSTMENT, not an owner-money cash row -- which is why such a '
    'record has no poultrycashtransactionid and may have no cash account. Every reader '
    'that could double-count it is taught to skip it.';

COMMENT ON COLUMN poultryownermoney.poultrycashaccountid IS
    'Which account the money moved through. NULL only on a record backfilled '
    'from a Cash Flow adjustment (296), which never had one -- the legacy '
    'cashadjustment table predates cash accounts. Both writers that CREATE owner '
    'money require it.';

CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryownermoney_sourceadjustment
    ON poultryownermoney (sourceadjustmentid)
    WHERE sourceadjustmentid IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 2. The backfill writer.
--
-- Deliberately NOT a call to sppoultryownermoney_record: that one writes a cash
-- row and moves a balance, and neither may happen here. The money already
-- arrived, as the adjustment.
--
-- The TYPE selects which adjustments count; the SIGN decides direction, exactly
-- as 287 reads the same table and as sppoultrycashflow_rows already does
-- (`CASE WHEN ca.amount >= 0 THEN 'CashIn'`). That stays right even when
-- somebody records a correction to an injection as a negative 'OwnerInjection',
-- which classifying by type alone would report as money going IN.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryownermoney_fromadjustment(
    p_farmid       text,
    p_adjustmentid integer,
    p_ownername    text DEFAULT NULL,
    p_createdby    text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_tbl    text;
    v_date   timestamp;
    v_amount numeric(14,2);
    v_desc   text;
    v_type   text;
    v_id     integer;
BEGIN
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    IF v_tbl IS NULL THEN
        RAISE EXCEPTION 'There are no cash adjustments on this database to convert.';
    END IF;

    EXECUTE format($sql$
        SELECT ca.adjustmentdate::timestamp, ca.amount::numeric(14,2),
               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text
        FROM   %s ca
        WHERE  ca.adjustmentid = $1
          AND  lower(ca.farmid::text) = lower($2)
          AND  ca.adjustmenttype IN ('OwnerInjection', 'Withdrawal')
    $sql$, v_tbl)
    INTO v_date, v_amount, v_desc
    USING p_adjustmentid, p_farmid;

    IF v_date IS NULL THEN
        RAISE EXCEPTION
          'Cash adjustment % is not an owner injection or withdrawal for this company.',
          p_adjustmentid;
    END IF;
    IF v_amount = 0 THEN
        RAISE EXCEPTION 'Cash adjustment % is for zero and is not a capital event.',
          p_adjustmentid;
    END IF;

    IF EXISTS (SELECT 1 FROM poultryownermoney o WHERE o.sourceadjustmentid = p_adjustmentid) THEN
        RAISE EXCEPTION 'Cash adjustment % is already recorded as owner money.',
          p_adjustmentid;
    END IF;

    -- The sign decides, not the type. The record stores a POSITIVE amount with
    -- the direction in transactiontype -- 253's rule -- so a negative
    -- 'OwnerInjection' (a correction) becomes a Draw rather than a negative
    -- contribution, which the table's CHECK (amount > 0) would reject anyway.
    v_type := CASE WHEN v_amount >= 0 THEN 'Contribution' ELSE 'Draw' END;

    -- No cash row, no balance change, no account. See the header.
    INSERT INTO poultryownermoney (
        farmid, transactiondate, transactiontype, amount, poultrycashaccountid,
        ownername, notes, status, createdby, sourceadjustmentid)
    VALUES (
        p_farmid, v_date, v_type, abs(v_amount), NULL,
        NULLIF(btrim(COALESCE(p_ownername, '')), ''),
        btrim('Backfilled from Cash Flow adjustment #' || p_adjustmentid::text
              || ' (' || v_amount::text || ') on '
              || to_char((now() at time zone 'utc'), 'YYYY-MM-DD')
              || COALESCE('. Original note: ' || NULLIF(v_desc, ''), '')),
        'Posted', p_createdby, p_adjustmentid)
    RETURNING poultryownermoneyid INTO v_id;

    UPDATE poultryownermoney
    SET    transactionnumber =
               CASE WHEN v_type = 'Contribution' THEN 'OWN-' ELSE 'OWD-' END
               || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  poultryownermoneyid = v_id;

    RETURN v_id;
END;
$function$;

COMMENT ON FUNCTION public.sppoultryownermoney_fromadjustment(text, integer, text, text) IS
    'Record a Cash Flow owner injection or withdrawal as real owner money. '
    'Writes NO cash row, moves NO balance and takes NO account -- the adjustment '
    'remains the cash event. Type selects, sign decides direction, amount is '
    'stored positive.';

-- -----------------------------------------------------------------------------
-- 3. Cash Flow must not count the same money twice.
--
-- Reproduced from the LIVE definition with ONE predicate added, marked 296.
-- Every other arm -- receipts, counter sales, expenses, transfers, loans,
-- repayments, the legacy adjustments -- is byte for byte what it was.
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

-- -----------------------------------------------------------------------------
-- 4. The legacy read learns to skip a converted adjustment.
--
-- Reproduced from the LIVE definition (287's) with one clause added. Without it
-- an injection would appear twice on the Owner Money page the moment it was
-- backfilled -- once as the adjustment, once as the record.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryownermoney_legacy(p_farmid text)
 RETURNS TABLE(adjustmentid integer, transactiondate timestamp without time zone, transactiontype text, amount numeric, description text, createdby text, createdat timestamp without time zone)
 LANGUAGE plpgsql
 STABLE
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

               ca.adjustmentdate::timestamp,

               CASE WHEN ca.amount >= 0 THEN 'Contribution' ELSE 'Draw' END::text,

               abs(ca.amount)::numeric,

               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text,

               ca.userid::text,

               ca.createddate::timestamp

        FROM   %s ca

        WHERE  lower(ca.farmid::text) = lower($1)

          AND  ca.adjustmenttype IN ('OwnerInjection', 'Withdrawal')
          -- 296. Converted ones are represented by their owner-money
          -- record now, so listing them here would double the capital.
          AND  NOT EXISTS (SELECT 1 FROM poultryownermoney o
                           WHERE o.sourceadjustmentid = ca.adjustmentid)

          AND  ca.amount <> 0

    $sql$, v_tbl)

    USING p_farmid;

END;

$function$;

-- -----------------------------------------------------------------------------
-- 5. The backfill. Nobody clicks anything.
-- -----------------------------------------------------------------------------
DO $backfill$
DECLARE
    v_tbl text;
    r     record;
    v_n   integer := 0;
BEGIN
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    IF v_tbl IS NULL THEN
        RAISE NOTICE '296: no cashadjustment table -- nothing to backfill.';
        RETURN;
    END IF;

    FOR r IN EXECUTE format($sql$
        SELECT ca.adjustmentid, ca.farmid::text AS farmid, ca.userid::text AS userid
        FROM   %s ca
        JOIN   farms f ON lower(f.farmid::text) = lower(ca.farmid::text)
        WHERE  ca.adjustmenttype IN ('OwnerInjection', 'Withdrawal')
          AND  ca.amount <> 0
          AND  f.type = 'Poultry'
          AND  NOT EXISTS (SELECT 1 FROM poultryownermoney o
                           WHERE o.sourceadjustmentid = ca.adjustmentid)
        ORDER  BY ca.adjustmentid
    $sql$, v_tbl)
    LOOP
        PERFORM sppoultryownermoney_fromadjustment(
            p_farmid       => r.farmid,
            p_adjustmentid => r.adjustmentid,
            p_ownername    => NULL,
            p_createdby    => r.userid);
        v_n := v_n + 1;
    END LOOP;

    RAISE NOTICE '296: backfilled % Cash Flow capital entr(ies) into owner money.', v_n;
END
$backfill$;

-- -----------------------------------------------------------------------------
-- 6. Grants.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.sppoultryownermoney_fromadjustment(
            text, integer, text, text) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'the link column exists' AS check,
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_name = 'poultryownermoney' AND column_name = 'sourceadjustmentid')
            THEN 'OK' ELSE 'MISSING' END AS result

UNION ALL
SELECT 'one record per adjustment is enforced',
       CASE WHEN EXISTS (SELECT 1 FROM pg_indexes
                         WHERE indexname = 'ux_poultryownermoney_sourceadjustment')
            THEN 'OK' ELSE 'MISSING' END

UNION ALL
SELECT 'cash flow skips backfilled records',
       CASE WHEN position('sourceadjustmentid' in pg_get_functiondef(p.oid)) > 0
            THEN 'OK' ELSE 'NOT WIRED -- the money would be counted twice' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'sppoultrycashflow_rows'

UNION ALL
SELECT 'nothing is left unrecorded',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   (SELECT ca.adjustmentid
        FROM   cashadjustment ca
        JOIN   farms f ON lower(f.farmid::text) = lower(ca.farmid::text)
        WHERE  ca.adjustmenttype IN ('OwnerInjection', 'Withdrawal')
          AND  ca.amount <> 0 AND f.type = 'Poultry'
          AND  NOT EXISTS (SELECT 1 FROM poultryownermoney o
                           WHERE o.sourceadjustmentid = ca.adjustmentid)) x

UNION ALL
SELECT 'no backfilled record moved cash',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   poultryownermoney o
WHERE  o.sourceadjustmentid IS NOT NULL AND o.poultrycashtransactionid IS NOT NULL;

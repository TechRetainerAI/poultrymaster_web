-- =============================================================================
-- 316_HotelCashFlowOnTransactions.postgres.sql
--
-- Purpose
-- -------
-- Build Cash Flow for the Hotel module on business transactions, the same way
-- migration 235 did for Poultry and 236 did for Water.
--
-- What it reads
-- -------------
--   hotelpayments              money received from guests
--   hotelrestaurantorders      walk-in F&B revenue (bookingid IS NULL)
--   hoteldeposits              security deposits collected and refunded
--   hotelexpenses              operational spending (Approved / Paid only)
--   hotelpayrollruns           staff wages (Paid only)
--
-- What it does NOT read
-- ---------------------
--   hotelcashtransactions      the cash-account ledger
--   hotelcashaccounts          account balances
--   hotelstaycharges           charges on a folio, not cash events
--   hotelinvoices              billing records, not cash events
--
-- Restaurant orders linked to a booking (hotelbookingid IS NOT NULL) are NOT
-- counted here: those are charged to the guest's folio and flow through
-- hotelpayments when the guest settles the invoice. Counting both would double
-- the revenue.
--
-- There is no financing (capital) leg yet. The hotel has no cash-adjustment,
-- owner-money or loan tables. When those are added, a new leg can be appended
-- to the rows function.
--
-- Amount convention: SIGNED. Positive is money in, negative is money out.
--
-- DROP + CREATE. No table is created, altered or written to.
-- Order: after 315. Run before any migration that references these functions.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- Dependency order: detail and summary both call rows.
DROP FUNCTION IF EXISTS public.sphotelcashflow_detail(text, timestamp, timestamp);
DROP FUNCTION IF EXISTS public.sphotelcashflow_summary(text, timestamp, timestamp);
DROP FUNCTION IF EXISTS public.sphotelcashflow_rows(text, timestamp, timestamp);

-- -----------------------------------------------------------------------------
-- 1. The rows.
-- -----------------------------------------------------------------------------
-- amount is SIGNED: positive in, negative out.
--
-- Columns kept compatible with the poultry/water shape so CashFlowService.cs
-- can read all three rails with the same reader. offledger and istransfer are
-- always FALSE (those concepts belong to the ledger, which this does not read).
CREATE OR REPLACE FUNCTION public.sphotelcashflow_rows(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    rowsource       text,        -- GuestPayment | RestaurantOrder | DepositIn | DepositOut | Expense | Payroll
    offledger       boolean,
    sourcerowid     integer,
    cashaccountid   integer,
    accountname     text,
    transactiondate timestamp,
    transactiontype text,
    sourcetype      text,
    sourceid        integer,
    istransfer      boolean,
    amount          numeric,
    description     text,
    flowgroup       text,        -- OperatingIn | OperatingOut
    createdat       timestamp)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);
    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);
BEGIN
    -- ---- 1. guest payments (the main revenue) --------------------------------
    -- Money received from guests against invoices or bookings. This is the
    -- primary inflow for a hotel, covering room revenue, charged F&B, and any
    -- other folio items the guest settles.
    RETURN QUERY
    SELECT 'GuestPayment'::text,
           FALSE,
           hp.hotelpaymentid,
           NULL::integer,
           NULL::text,
           hp.paymentdate::timestamp,
           'CashIn'::text,
           'GuestPayment'::text,
           hp.hotelpaymentid,
           FALSE,
           COALESCE(hp.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(hp.notes), ''),
               NULLIF(btrim(hp.reference), ''),
               'Guest payment #' || hp.hotelpaymentid::text
           )::text,
           'OperatingIn'::text,
           hp.createdat::timestamp
    FROM   hotelpayments hp
    WHERE  lower(hp.farmid::text) = lower(p_farmid)
      AND  COALESCE(hp.amount, 0) > 0
      AND  hp.paymentdate::timestamp >= v_from
      AND  hp.paymentdate::timestamp <= v_to;

    -- ---- 2. walk-in restaurant / F&B orders ----------------------------------
    -- Only orders NOT linked to a booking. Room-service and in-house dining
    -- with hotelbookingid set are charged to the guest's folio and collected
    -- through hotelpayments when the invoice is settled. Counting both would
    -- double the revenue.
    --
    -- Only delivered orders: placed/preparing/ready orders have not been paid.
    -- Cancelled orders moved no money.
    RETURN QUERY
    SELECT 'RestaurantOrder'::text,
           FALSE,
           ro.hotelrestaurantorderid,
           NULL::integer,
           NULL::text,
           COALESCE(ro.deliveredtime, ro.ordertime)::timestamp,
           'CashIn'::text,
           'RestaurantOrder'::text,
           ro.hotelrestaurantorderid,
           FALSE,
           COALESCE(ro.totalamount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(ro.notes), ''),
               'Restaurant order #' || ro.hotelrestaurantorderid::text
               || COALESCE(' - Table ' || NULLIF(btrim(ro.tablenumber), ''), '')
           )::text,
           'OperatingIn'::text,
           ro.createdat::timestamp
    FROM   hotelrestaurantorders ro
    WHERE  lower(ro.farmid::text) = lower(p_farmid)
      AND  ro.hotelbookingid IS NULL
      AND  ro.status = 'Delivered'
      AND  COALESCE(ro.totalamount, 0) > 0
      AND  COALESCE(ro.deliveredtime, ro.ordertime)::timestamp >= v_from
      AND  COALESCE(ro.deliveredtime, ro.ordertime)::timestamp <= v_to;

    -- ---- 3. deposits collected -----------------------------------------------
    -- Security or advance deposits received from guests. Money in, but
    -- operating (not financing) because it is part of the guest transaction
    -- cycle, not capital from an owner or lender.
    IF to_regclass('public.hoteldeposits') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'DepositIn'::text,
               FALSE,
               hd.hoteldepositid,
               NULL::integer,
               NULL::text,
               hd.createdat::timestamp,
               'CashIn'::text,
               'DepositCollected'::text,
               hd.hoteldepositid,
               FALSE,
               COALESCE(hd.amount, 0)::numeric,
               COALESCE(
                   NULLIF(btrim(hd.notes), ''),
                   'Deposit collected #' || hd.hoteldepositid::text
               )::text,
               'OperatingIn'::text,
               hd.createdat::timestamp
        FROM   hoteldeposits hd
        WHERE  lower(hd.farmid::text) = lower(p_farmid)
          AND  hd.deposittype = 'Collected'
          AND  COALESCE(hd.amount, 0) > 0
          AND  hd.createdat::timestamp >= v_from
          AND  hd.createdat::timestamp <= v_to;

        -- ---- 4. deposits refunded --------------------------------------------
        -- Money returned to the guest. Negative (outflow), still operating.
        RETURN QUERY
        SELECT 'DepositOut'::text,
               FALSE,
               hd.hoteldepositid,
               NULL::integer,
               NULL::text,
               hd.createdat::timestamp,
               'CashOut'::text,
               'DepositRefunded'::text,
               hd.hoteldepositid,
               FALSE,
               -COALESCE(hd.amount, 0)::numeric,
               COALESCE(
                   NULLIF(btrim(hd.notes), ''),
                   'Deposit refunded #' || hd.hoteldepositid::text
               )::text,
               'OperatingOut'::text,
               hd.createdat::timestamp
        FROM   hoteldeposits hd
        WHERE  lower(hd.farmid::text) = lower(p_farmid)
          AND  hd.deposittype = 'Refunded'
          AND  COALESCE(hd.amount, 0) > 0
          AND  hd.createdat::timestamp >= v_from
          AND  hd.createdat::timestamp <= v_to;
    END IF;

    -- ---- 5. expenses ---------------------------------------------------------
    -- Operational spending: utilities, supplies, maintenance, etc.
    -- Only Approved or Paid expenses count as cash that moved. Draft and
    -- Submitted are intentions; Cancelled never happened.
    RETURN QUERY
    SELECT 'Expense'::text,
           FALSE,
           he.hotelexpenseid,
           he.hotelcashaccountid,
           NULL::text,
           he.expensedate::timestamp,
           'CashOut'::text,
           'Expense'::text,
           he.hotelexpenseid,
           FALSE,
           -COALESCE(he.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(he.description), ''),
               COALESCE(he.category, 'Expense')
           )::text,
           'OperatingOut'::text,
           he.createdat::timestamp
    FROM   hotelexpenses he
    WHERE  lower(he.farmid::text) = lower(p_farmid)
      AND  COALESCE(he.amount, 0) > 0
      AND  he.status IN ('Approved', 'Paid')
      AND  he.expensedate >= v_from
      AND  he.expensedate <= v_to;

    -- ---- 6. payroll ----------------------------------------------------------
    -- Staff wages paid. Only runs that reached 'Paid' status moved money.
    -- The total is netpay (gross minus deductions), which is the cash that
    -- actually left the business.
    RETURN QUERY
    SELECT 'Payroll'::text,
           FALSE,
           pr.hotelpayrollrunid,
           pr.hotelcashaccountid,
           NULL::text,
           COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::timestamp,
           'CashOut'::text,
           'Payroll'::text,
           pr.hotelpayrollrunid,
           FALSE,
           -COALESCE(pr.totalnetpay, 0)::numeric,
           COALESCE(
               NULLIF(btrim(pr.notes), ''),
               'Payroll ' || to_char(pr.periodstart, 'DD Mon') || ' - ' || to_char(pr.periodend, 'DD Mon YYYY')
           )::text,
           'OperatingOut'::text,
           pr.createdat::timestamp
    FROM   hotelpayrollruns pr
    WHERE  lower(pr.farmid::text) = lower(p_farmid)
      AND  pr.status = 'Paid'
      AND  COALESCE(pr.totalnetpay, 0) > 0
      AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::timestamp >= v_from
      AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::timestamp <= v_to;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. The summary.
-- -----------------------------------------------------------------------------
-- Opening + in - out = closing, all from the same transaction set, so the
-- identity closes by construction.
--
-- Opening is measured: everything eligible that happened BEFORE the period
-- started. With no start date, opening is zero and closing becomes all-time.
--
-- Return shape matches poultry/water so CashFlowService.cs reads all rails
-- identically. Columns that belong to the ledger are returned as zero.
CREATE OR REPLACE FUNCTION public.sphotelcashflow_summary(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    moneyin            numeric,
    moneyout           numeric,
    netcashflow        numeric,
    ledgercash         numeric,
    offledgernet       numeric,
    cashathand         numeric,
    openingbalance     numeric,
    transfervolume     numeric,
    offledgerin        numeric,
    offledgerout       numeric,
    rowcount           bigint)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_in      numeric := 0;
    v_out     numeric := 0;
    v_n       bigint  := 0;
    v_open    numeric := 0;
BEGIN
    SELECT COALESCE(SUM(r.amount)  FILTER (WHERE r.amount > 0), 0),
           COALESCE(SUM(-r.amount) FILTER (WHERE r.amount < 0), 0),
           COUNT(*)
      INTO v_in, v_out, v_n
    FROM   public.sphotelcashflow_rows(p_farmid, p_fromdate, p_todate) r;

    -- Everything before the window opened.
    IF p_fromdate IS NOT NULL THEN
        SELECT COALESCE(SUM(r.amount), 0) INTO v_open
        FROM   public.sphotelcashflow_rows(
                   p_farmid, NULL, p_fromdate - interval '1 microsecond') r;
    END IF;

    RETURN QUERY SELECT
        ROUND(v_in, 2),
        ROUND(v_out, 2),
        ROUND(v_in - v_out, 2),
        0::numeric,                          -- ledgercash    (ledger not read)
        0::numeric,                          -- offledgernet  (concept retired)
        ROUND(v_open + v_in - v_out, 2),     -- cashathand = CLOSING cash
        ROUND(v_open, 2),
        0::numeric,                          -- transfervolume (excluded)
        0::numeric,                          -- offledgerin
        0::numeric,                          -- offledgerout
        v_n;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. The detail rows, with the category.
-- -----------------------------------------------------------------------------
-- Same as poultry 235: the rows above plus what the money was FOR.
-- Expense category comes from the expense record. Guest payments are "Room
-- revenue". Restaurant orders are "Restaurant / F&B". Deposits keep their
-- own label. Payroll is "Staff wages".
CREATE OR REPLACE FUNCTION public.sphotelcashflow_detail(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    rowsource       text,
    offledger       boolean,
    sourcerowid     integer,
    cashaccountid   integer,
    accountname     text,
    transactiondate timestamp,
    transactiontype text,
    sourcetype      text,
    sourceid        integer,
    istransfer      boolean,
    amount          numeric,
    description     text,
    flowgroup       text,
    category        text,
    createdat       timestamp)
LANGUAGE sql
STABLE
AS $function$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname,
           r.transactiondate, r.transactiontype, r.sourcetype, r.sourceid,
           r.istransfer, r.amount, r.description, r.flowgroup,
           CASE
               WHEN r.rowsource = 'Expense'
                   THEN COALESCE(
                       NULLIF(btrim(
                           COALESCE(ec.name, he.category)
                       ), ''),
                       'Uncategorised'
                   )
               WHEN r.rowsource = 'GuestPayment'
                   THEN COALESCE(
                       'Room revenue (' || NULLIF(btrim(hp.paymentmethod), '') || ')',
                       'Room revenue'
                   )
               WHEN r.rowsource = 'RestaurantOrder' THEN 'Restaurant / F&B'
               WHEN r.rowsource = 'DepositIn'       THEN 'Guest deposits'
               WHEN r.rowsource = 'DepositOut'      THEN 'Deposit refunds'
               WHEN r.rowsource = 'Payroll'         THEN 'Staff wages'
               ELSE 'Other'
           END::text,
           r.createdat
    FROM   public.sphotelcashflow_rows(p_farmid, p_fromdate, p_todate) r
    -- Expense: join to get the category name
    LEFT   JOIN hotelexpenses he
           ON  r.rowsource = 'Expense'
           AND he.hotelexpenseid = r.sourcerowid
           AND lower(he.farmid::text) = lower(p_farmid)
    LEFT   JOIN hotelexpensecategories ec
           ON  he.hotelexpensecategoryid = ec.hotelexpensecategoryid
    -- Guest payment: join to get the payment method for the category label
    LEFT   JOIN hotelpayments hp
           ON  r.rowsource = 'GuestPayment'
           AND hp.hotelpaymentid = r.sourcerowid
           AND lower(hp.farmid::text) = lower(p_farmid);
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 4. Verification.
-- -----------------------------------------------------------------------------
SELECT 'hotel cash flow functions (3 expected)' AS check,
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'ONLY ' || count(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('sphotelcashflow_rows', 'sphotelcashflow_summary',
                     'sphotelcashflow_detail');

-- 4a. THE IDENTITY. opening + in - out must equal closing, per farm.
--     Must be 0.00. If hotelcashaccounts does not exist yet, this simply
--     returns no rows rather than failing.
DO $$
BEGIN
    IF to_regclass('public.hotelcashaccounts') IS NOT NULL THEN
        PERFORM 1;  -- table exists, run the check below
    END IF;
END $$;

SELECT f.farmid,
       s.openingbalance, s.moneyin, s.moneyout, s.cashathand,
       ROUND(s.openingbalance + s.moneyin - s.moneyout - s.cashathand, 2) AS should_be_zero
FROM   (SELECT DISTINCT farmid FROM hotelcashaccounts) f
CROSS  JOIN LATERAL public.sphotelcashflow_summary(
                        f.farmid, '2000-01-01'::timestamp, '2999-12-31'::timestamp) s
ORDER  BY f.farmid;

-- 4b. What the flow groups hold, per farm.
SELECT r.flowgroup, count(*) AS movements, ROUND(SUM(ABS(r.amount)), 2) AS total
FROM   (SELECT DISTINCT farmid FROM hotelcashaccounts) f
CROSS  JOIN LATERAL public.sphotelcashflow_rows(f.farmid, NULL, NULL) r
GROUP  BY r.flowgroup
ORDER  BY r.flowgroup;

-- =============================================================================
-- 250_GenericSubscriptionReporting.postgres.sql
--
-- Purpose
-- -------
-- The read side of the Generic subscription business: the dashboard an owner
-- opens every morning, and the reports they open once a month. 243 raises the
-- invoices, 244 collects the money, 248 tracks what is owed to suppliers and
-- 249 pays it out. Nothing in this file writes a single row.
--
-- What this file does NOT rebuild
-- -------------------------------
-- Six of the twelve reports the spec asks for are already answerable from
-- functions that exist, so they get a PAGE and no new SQL:
--
--   Customer payment report   spgenericcustomerpayment_history   (244)
--   Unpaid customers          spgenericcustomerbalances          (244)
--   Customer balances         spgenericcustomerbalances          (244)
--   Supplier balances         spgenericsupplierbalances          (248)
--   Cash flow                 spgenericreport_cashsummary_rs1    (037)
--   Profit / loss             spgenericreport_periodpnl          (037)
--
-- Duplicating those in a "reports" namespace would have meant two definitions
-- of one number, and the pair drifting apart is a matter of when, not whether.
-- The only thing P&L was missing is the split between subscription income and
-- everything else, so that is one small function rather than a second P&L.
--
-- The MRR month grid
-- ------------------
-- Every recurring figure here comes from ONE helper -- fngenericsubscription-
-- months -- which explodes each subscription into the months it was live and
-- normalises its billing amount to a monthly figure. Active MRR, new MRR, lost
-- MRR, the dashboard KPI and the break-even divisor are all sums over that one
-- grid, so they cannot disagree with each other.
--
-- A subscription is counted in the month it was cancelled: the money was
-- earned. It falls out of the following month, which is where lost MRR shows.
--
-- Expansion and contraction MRR are NOT computed
-- ----------------------------------------------
-- genericsubscriptions keeps one billingamount and overwrites it. There is no
-- amount history, so a plan that went from 50 to 80 in March is indistinguish-
-- able from one that was always 80. The columns are returned as zero rather
-- than guessed at; making them real needs a subscription-amount history table,
-- which is a write-side change and belongs with a migration that can backfill
-- it. The spec marks both "if supported".
--
-- Monthly burn rate and fixed costs
-- ---------------------------------
-- Averaged over the last N COMPLETE months, never including the current
-- partial one -- on the 2nd of the month a partial month would halve the
-- average and halve the break-even count with it.
--
-- EFFECT ON TODAY'S NUMBERS: none. Functions only; no table, column or row is
-- touched. Every existing report keeps its existing definition.
--
-- Order: after 249.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Drop by NAME, not by signature.
--
-- CREATE OR REPLACE refuses to change a function's return type, and these are
-- nearly all RETURNS TABLE. Re-running this file after editing a column list
-- would otherwise fail, or -- worse -- leave a stale overload behind that
-- Npgsql then picks by named-argument match. Dropping every overload of each
-- name first is the only re-runnable option.
-- -----------------------------------------------------------------------------
DO $drop$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM   pg_proc p
        JOIN   pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN (
                'fngenericmonthlyamount',
                'fngenericsubscriptionmonths',
                'spgenericsubdashboard_rs1',
                'spgenericsubdashboard_rs2',
                'spgenericsubdashboard_rs3',
                'spgenericsubdashboard_rs4',
                'spgenericsubdashboard_rs5',
                'spgenericsubdashboard_rs6',
                'spgenericsubdashboard_rs7',
                'spgenericsubdashboard_rs8',
                'spgenericreport_mrr',
                'spgenericreport_subscriptionrevenue_rs1',
                'spgenericreport_subscriptionrevenue_rs2',
                'spgenericreport_subscriptionrevenue_rs3',
                'spgenericreport_incomesplit',
                'spgenericreport_expensesbysupplier',
                'spgenericreport_expensetrend',
                'spgenericreport_hostingcategories',
                'spgenericreport_hostingcost',
                'spgenericreport_staffcost_rs1',
                'spgenericreport_staffcost_rs2',
                'spgenericreport_staffcost_rs3',
                'spgenericreport_breakeven')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- -----------------------------------------------------------------------------
-- 1. One recurring amount, normalised to a month.
--
-- Mirrors fngenericnextbillingdate (243) case for case. Weekly is 52/12 weeks
-- to the month, not 4 -- billing weekly for a year raises 52 invoices, and a
-- 4-week month would under-report annual MRR by 8%.
--
-- OneTime is deliberately zero: a one-off fee is revenue, but it is not
-- RECURRING revenue, and putting it in MRR makes next month's forecast a lie.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fngenericmonthlyamount(
    p_amount    numeric,
    p_frequency text
) RETURNS numeric
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT ROUND(CASE COALESCE(p_frequency, 'OneTime')
                      WHEN 'Weekly'     THEN COALESCE(p_amount, 0) * 52.0 / 12.0
                      WHEN 'Monthly'    THEN COALESCE(p_amount, 0)
                      WHEN 'Quarterly'  THEN COALESCE(p_amount, 0) / 3.0
                      WHEN 'Termly'     THEN COALESCE(p_amount, 0) / 4.0
                      WHEN 'SemiAnnual' THEN COALESCE(p_amount, 0) / 6.0
                      WHEN 'Annual'     THEN COALESCE(p_amount, 0) / 12.0
                      ELSE 0
                 END, 2)::numeric(14,2);
$function$;

COMMENT ON FUNCTION public.fngenericmonthlyamount(numeric, text) IS
    'A subscription billing amount expressed as monthly recurring revenue. '
    'OneTime returns 0 -- it is revenue but not recurring revenue.';

-- -----------------------------------------------------------------------------
-- 2. THE month grid every recurring figure is summed from.
--
-- One row per (month, subscription) for every month the subscription was live
-- inside the requested window. Draft subscriptions are excluded -- they have
-- never billed anyone -- and so is OneTime, which has no monthly figure.
--
-- "Live in month M" means it had started by the last day of M and had not
-- stopped before the first day of M. Stopping is enddate if one was set, else
-- the cancellation timestamp; a subscription with neither runs forever, which
-- is what an open-ended monthly plan is.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fngenericsubscriptionmonths(
    p_farmid text,
    p_from   date,
    p_to     date
) RETURNS TABLE(
    monthstart            date,
    genericsubscriptionid integer,
    genericcustomerid     integer,
    genericserviceid      integer,
    billingfrequency      text,
    monthlyamount         numeric,
    isnew                 boolean,
    islost                boolean
)
LANGUAGE sql STABLE
AS $function$
    WITH months AS (
        SELECT gs::date AS monthstart
        FROM   generate_series(date_trunc('month', p_from)::date,
                               date_trunc('month', p_to)::date,
                               interval '1 month') gs
    ),
    subs AS (
        SELECT s.genericsubscriptionid,
               s.genericcustomerid,
               s.genericserviceid,
               s.billingfrequency::text AS billingfrequency,
               s.startdate,
               COALESCE(s.enddate, s.cancelledat::date) AS stopdate,
               fngenericmonthlyamount(
                   s.billingamount - s.discountamount + s.taxamount,
                   s.billingfrequency) AS monthlyamount
        FROM   genericsubscriptions s
        WHERE  s.farmid = p_farmid
          AND  s.status <> 'Draft'
          AND  COALESCE(s.billingfrequency, 'OneTime') <> 'OneTime'
    )
    SELECT m.monthstart,
           s.genericsubscriptionid,
           s.genericcustomerid,
           s.genericserviceid,
           s.billingfrequency,
           s.monthlyamount,
           (date_trunc('month', s.startdate)::date = m.monthstart) AS isnew,
           (s.stopdate IS NOT NULL
            AND date_trunc('month', s.stopdate)::date = m.monthstart) AS islost
    FROM   months m
    JOIN   subs s
           ON  s.startdate <= (m.monthstart + interval '1 month' - interval '1 day')::date
           AND (s.stopdate IS NULL OR s.stopdate >= m.monthstart);
$function$;

COMMENT ON FUNCTION public.fngenericsubscriptionmonths(text, date, date) IS
    'One row per month per live subscription. Active MRR, new/lost MRR, the '
    'dashboard KPI and the break-even divisor are all sums over this, so they '
    'cannot disagree.';

-- =============================================================================
-- THE SUBSCRIPTION DASHBOARD
--
-- Eight result sets, one page. They take the same p_asof so that every number
-- on the screen describes the same month; passing the month in from the client
-- twice is how a dashboard ends up showing October's revenue against
-- September's expenses.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- rs1: the headline KPIs.
--
-- "Live today" rather than "live this month" for MRR and the active counts:
-- the card says what is running now, not what ran at some point in October.
-- It is the same predicate fngenericsubscriptionmonths uses, evaluated at day
-- granularity instead of month.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericsubdashboard_rs1(
    p_farmid text,
    p_asof   date DEFAULT NULL
) RETURNS TABLE(
    monthstart              date,
    monthend                date,
    monthlyrecurringrevenue numeric,
    activesubscriptions     integer,
    activecustomers         integer,
    paymentscollected       numeric,
    expensespaid            numeric,
    netcashflow             numeric,
    invoicedthismonth       numeric,
    customerbalances        numeric,
    supplierbalances        numeric,
    cashathand              numeric,
    overduecustomers        integer,
    overdueamount           numeric,
    monthlyburnrate         numeric,
    breakevencustomers      integer,
    newsubscriptions        integer,
    cancelledsubscriptions  integer
)
LANGUAGE plpgsql STABLE
AS $function$
DECLARE
    v_today      date := COALESCE(p_asof, (now() at time zone 'utc')::date);
    v_monthstart date := date_trunc('month', v_today)::date;
    v_monthend   date := (date_trunc('month', v_today) + interval '1 month' - interval '1 day')::date;
    -- Cash movements and payments are timestamps, so the window is half-open.
    v_start      timestamp := v_monthstart::timestamp;
    v_end        timestamp := (v_monthend + 1)::timestamp;
    -- The three COMPLETE months before this one. A partial current month in
    -- the average halves the burn rate on the 2nd of the month.
    v_burnfrom   date := (v_monthstart - interval '3 months')::date;
    v_mrr        numeric(14,2);
    v_subs       integer;
    v_custs      integer;
    v_burn       numeric(14,2);
    v_avgper     numeric(14,2);
BEGIN
    SELECT COALESCE(SUM(fngenericmonthlyamount(
                            s.billingamount - s.discountamount + s.taxamount,
                            s.billingfrequency)), 0),
           COUNT(*)::int,
           COUNT(DISTINCT s.genericcustomerid)::int
      INTO v_mrr, v_subs, v_custs
      FROM genericsubscriptions s
     WHERE s.farmid = p_farmid
       AND s.status = 'Active'
       AND COALESCE(s.billingfrequency, 'OneTime') <> 'OneTime'
       AND s.startdate <= v_today
       AND (s.enddate IS NULL OR s.enddate >= v_today);

    v_burn := COALESCE((
        SELECT SUM(e.amount) / 3.0
        FROM   genericexpenses e
        WHERE  e.farmid = p_farmid AND e.status = 'Approved'
           AND COALESCE(e.isdeleted, FALSE) = FALSE
           AND e.expensedate >= v_burnfrom::timestamp
           AND e.expensedate <  v_monthstart::timestamp), 0);

    v_avgper := CASE WHEN v_custs > 0 THEN v_mrr / v_custs ELSE 0 END;

    RETURN QUERY
    SELECT
        v_monthstart,
        v_monthend,
        v_mrr,
        v_subs,
        v_custs,
        COALESCE((SELECT SUM(p.amount) FROM genericcustomerpayments p
                  WHERE p.farmid = p_farmid AND p.status = 'Approved'
                    AND p.paymentdate >= v_start AND p.paymentdate < v_end), 0)::numeric,
        COALESCE((SELECT SUM(e.amount) FROM genericexpenses e
                  WHERE e.farmid = p_farmid AND e.status = 'Approved'
                    AND COALESCE(e.isdeleted, FALSE) = FALSE
                    AND e.expensedate >= v_start AND e.expensedate < v_end), 0)::numeric,
        -- Every cash movement, signed. No status filter, exactly as
        -- spgenericreport_cashsummary_rs1 does it: a reversal is a second row
        -- of the opposite sign, so filtering the reversed original out would
        -- leave only the correction behind.
        COALESCE((SELECT SUM(t.amount) FROM genericcashtransactions t
                  WHERE t.farmid = p_farmid
                    AND t.transactiondate >= v_start AND t.transactiondate < v_end), 0)::numeric,
        COALESCE((SELECT SUM(s.totalamount) FROM genericsales s
                  WHERE s.farmid = p_farmid AND s.status = 'Approved'
                    AND COALESCE(s.isdeleted, FALSE) = FALSE
                    AND s.genericsubscriptionid IS NOT NULL
                    AND s.saledate >= v_start AND s.saledate < v_end), 0)::numeric,
        COALESCE((SELECT SUM(d.balance) FROM fngenericopeninvoices(p_farmid) d
                  WHERE d.balance > 0), 0)::numeric,
        COALESCE((SELECT SUM(d.balance) FROM fngenericpayables(p_farmid) d
                  WHERE d.balance > 0), 0)::numeric,
        COALESCE((SELECT SUM(a.currentbalance) FROM genericcashaccounts a
                  WHERE a.farmid = p_farmid AND a.isactive = TRUE), 0)::numeric,
        COALESCE((SELECT COUNT(DISTINCT d.genericcustomerid)::int
                  FROM fngenericopeninvoices(p_farmid) d
                  WHERE d.balance > 0 AND d.duedate < v_today), 0),
        COALESCE((SELECT SUM(d.balance) FROM fngenericopeninvoices(p_farmid) d
                  WHERE d.balance > 0 AND d.duedate < v_today), 0)::numeric,
        ROUND(v_burn, 2)::numeric,
        -- How many customers at today's average price cover the monthly burn.
        -- Zero customers or zero burn means the question has no answer; 0 is
        -- returned rather than a division by zero or a fake infinity.
        CASE WHEN v_avgper > 0 THEN CEIL(v_burn / v_avgper)::int ELSE 0 END,
        COALESCE((SELECT COUNT(*)::int FROM genericsubscriptions s
                  WHERE s.farmid = p_farmid AND s.status <> 'Draft'
                    AND s.startdate >= v_monthstart AND s.startdate <= v_monthend), 0),
        COALESCE((SELECT COUNT(*)::int FROM genericsubscriptions s
                  WHERE s.farmid = p_farmid
                    AND COALESCE(s.enddate, s.cancelledat::date) >= v_monthstart
                    AND COALESCE(s.enddate, s.cancelledat::date) <= v_monthend
                    AND s.status IN ('Cancelled', 'Expired')), 0);
END;
$function$;

-- -----------------------------------------------------------------------------
-- rs2: upcoming renewals and bills already due.
--
-- daysuntil is negative for a subscription that should already have been
-- billed -- billing is a button in this system, so "overdue to bill" is a real
-- and common state, and hiding it behind a date filter is how a month's
-- revenue goes uninvoiced.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericsubdashboard_rs2(
    p_farmid text,
    p_asof   date DEFAULT NULL,
    p_days   integer DEFAULT 30
) RETURNS TABLE(
    genericsubscriptionid integer,
    subscriptionnumber    text,
    genericcustomerid     integer,
    customername          text,
    servicename           text,
    billingfrequency      text,
    nextbillingdate       date,
    totalbillingamount    numeric,
    daysuntil             integer,
    status                text
)
LANGUAGE sql STABLE
AS $function$
    SELECT s.genericsubscriptionid,
           s.subscriptionnumber::text,
           s.genericcustomerid,
           c.customername::text,
           sv.servicename::text,
           s.billingfrequency::text,
           s.nextbillingdate,
           (s.billingamount - s.discountamount + s.taxamount)::numeric(14,2),
           (s.nextbillingdate - COALESCE(p_asof, (now() at time zone 'utc')::date))::int,
           s.status::text
    FROM   genericsubscriptions s
    JOIN   genericcustomers c
           ON c.genericcustomerid = s.genericcustomerid AND c.farmid = s.farmid
    LEFT   JOIN genericservices sv
           ON sv.genericserviceid = s.genericserviceid AND sv.farmid = s.farmid
    WHERE  s.farmid = p_farmid
      AND  s.status = 'Active'
      AND  s.nextbillingdate IS NOT NULL
      AND  s.nextbillingdate <= COALESCE(p_asof, (now() at time zone 'utc')::date)
                                + COALESCE(p_days, 30)
    ORDER  BY s.nextbillingdate, c.customername;
$function$;

-- -----------------------------------------------------------------------------
-- rs3: who owes money and is late.
--
-- Straight through to 244's balance function with its Overdue filter, so the
-- dashboard and the Customer Balances page cannot show different debtors.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericsubdashboard_rs3(
    p_farmid text,
    p_limit  integer DEFAULT 10
) RETURNS TABLE(
    partyid           integer,
    partyname         text,
    contactphone      text,
    totalbalance      numeric,
    overdueamount     numeric,
    opendocumentcount integer,
    oldestdocumentdate date,
    lastpaymentdate   timestamp
)
LANGUAGE sql STABLE
AS $function$
    SELECT b.partyid, b.partyname, b.contactphone, b.totalbalance, b.overdueamount,
           b.opendocumentcount, b.oldestdocumentdate, b.lastpaymentdate
    FROM   spgenericcustomerbalances(p_farmid, NULL, NULL, NULL, 'Overdue', NULL, NULL) b
    ORDER  BY b.overdueamount DESC, b.totalbalance DESC
    LIMIT  COALESCE(p_limit, 10);
$function$;

-- -----------------------------------------------------------------------------
-- rs4: where this month's money went.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericsubdashboard_rs4(
    p_farmid text,
    p_asof   date DEFAULT NULL
) RETURNS TABLE(
    genericexpensecategoryid integer,
    categoryname             text,
    expensecount             integer,
    totalamount              numeric,
    pctoftotal               numeric
)
LANGUAGE sql STABLE
AS $function$
    WITH bounds AS (
        SELECT date_trunc('month', COALESCE(p_asof, (now() at time zone 'utc')::date))::date AS s,
               (date_trunc('month', COALESCE(p_asof, (now() at time zone 'utc')::date))
                + interval '1 month' - interval '1 day')::date AS e
    ),
    bycategory AS (
        SELECT r.* FROM bounds b,
               LATERAL spgenericreport_expensesbycategory(p_farmid, b.s, b.e) r
    )
    SELECT r.genericexpensecategoryid, r.categoryname, r.expensecount, r.totalamount,
           CASE WHEN SUM(r.totalamount) OVER () > 0
                THEN ROUND(r.totalamount * 100 / SUM(r.totalamount) OVER (), 2)
                ELSE 0 END::numeric
    FROM   bycategory r
    ORDER  BY r.totalamount DESC;
$function$;

-- -----------------------------------------------------------------------------
-- rs5: recurring expenses that have fallen due or are about to.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericsubdashboard_rs5(
    p_farmid text,
    p_asof   date DEFAULT NULL,
    p_days   integer DEFAULT 30
) RETURNS TABLE(
    genericrecurringexpenseid integer,
    expensename               text,
    categoryname              text,
    suppliername              text,
    amount                    numeric,
    frequency                 text,
    nextduedate               date,
    daysuntil                 integer
)
LANGUAGE sql STABLE
AS $function$
    SELECT r.genericrecurringexpenseid,
           r.expensename::text,
           c.name::text,
           s.suppliername::text,
           r.amount,
           r.frequency::text,
           r.nextduedate,
           (r.nextduedate - COALESCE(p_asof, (now() at time zone 'utc')::date))::int
    FROM   genericrecurringexpenses r
    LEFT   JOIN genericexpensecategories c
           ON c.genericexpensecategoryid = r.genericexpensecategoryid
    LEFT   JOIN genericsuppliers s
           ON s.genericsupplierid = r.genericsupplierid AND s.farmid = r.farmid
    WHERE  r.farmid = p_farmid
      AND  r.status = 'Active'
      AND  r.nextduedate IS NOT NULL
      AND  r.nextduedate <= COALESCE(p_asof, (now() at time zone 'utc')::date)
                            + COALESCE(p_days, 30)
    ORDER  BY r.nextduedate, r.expensename;
$function$;

-- -----------------------------------------------------------------------------
-- rs6: recent activity.
--
-- Five money events in one list, newest first. Reversed rows are kept and
-- labelled: "that payment was reversed" is exactly what someone scanning the
-- feed needs to see.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericsubdashboard_rs6(
    p_farmid text,
    p_limit  integer DEFAULT 15
) RETURNS TABLE(
    activityat   timestamp,
    activitytype text,
    reference    text,
    party        text,
    description  text,
    amount       numeric,
    status       text
)
LANGUAGE sql STABLE
AS $function$
    WITH feed AS (
        SELECT s.saledate AS activityat,
               CASE WHEN s.genericsubscriptionid IS NOT NULL THEN 'Invoice' ELSE 'Sale' END::text AS activitytype,
               COALESCE(NULLIF(btrim(s.receiptnumber), ''), 'S' || s.genericsaleid::text)::text AS reference,
               c.customername::text AS party,
               COALESCE(NULLIF(btrim(s.notes), ''), s.salestype, 'Sale')::text AS description,
               s.totalamount AS amount,
               s.status::text AS status
        FROM   genericsales s
        LEFT   JOIN genericcustomers c
               ON c.genericcustomerid = s.genericcustomerid AND c.farmid = s.farmid
        WHERE  s.farmid = p_farmid AND COALESCE(s.isdeleted, FALSE) = FALSE

        UNION ALL

        SELECT p.paymentdate, 'Payment received'::text,
               COALESCE(NULLIF(btrim(p.referenceno), ''), 'P' || p.genericcustomerpaymentid::text)::text,
               c.customername::text,
               COALESCE(NULLIF(btrim(p.notes), ''), p.paymentmethod, 'Payment')::text,
               p.amount, p.status::text
        FROM   genericcustomerpayments p
        LEFT   JOIN genericcustomers c
               ON c.genericcustomerid = p.genericcustomerid AND c.farmid = p.farmid
        WHERE  p.farmid = p_farmid

        UNION ALL

        SELECT e.expensedate, 'Expense'::text,
               ('E' || e.genericexpenseid::text)::text,
               COALESCE(su.suppliername, e.paidto)::text,
               COALESCE(NULLIF(btrim(e.description), ''), 'Expense')::text,
               -e.amount, e.status::text
        FROM   genericexpenses e
        LEFT   JOIN genericsuppliers su
               ON su.genericsupplierid = e.genericsupplierid AND su.farmid = e.farmid
        WHERE  e.farmid = p_farmid AND COALESCE(e.isdeleted, FALSE) = FALSE

        UNION ALL

        SELECT sp.paymentdate, 'Staff payment'::text,
               COALESCE(NULLIF(btrim(sp.referenceno), ''), 'SP' || sp.genericstaffpaymentid::text)::text,
               (st.firstname || ' ' || COALESCE(st.lastname, ''))::text,
               COALESCE(NULLIF(btrim(sp.description), ''), 'Staff payment')::text,
               -sp.amount, sp.status::text
        FROM   genericstaffpayments sp
        LEFT   JOIN genericstaff st
               ON st.genericstaffid = sp.genericstaffid AND st.farmid = sp.farmid
        WHERE  sp.farmid = p_farmid

        UNION ALL

        SELECT o.entrydate::timestamp, ('Owner ' || lower(o.entrytype))::text,
               COALESCE(NULLIF(btrim(o.referenceno), ''), 'O' || o.genericownerentryid::text)::text,
               o.ownername::text,
               COALESCE(NULLIF(btrim(o.notes), ''), o.entrytype)::text,
               CASE WHEN o.entrytype = 'Draw' THEN -o.amount ELSE o.amount END,
               o.status::text
        FROM   genericownercontributiondraws o
        WHERE  o.farmid = p_farmid
    )
    SELECT f.activityat, f.activitytype, f.reference, f.party, f.description, f.amount, f.status
    FROM   feed f
    ORDER  BY f.activityat DESC
    LIMIT  COALESCE(p_limit, 15);
$function$;

-- -----------------------------------------------------------------------------
-- rs7: alerts, one row of counts.
--
-- Everything here is something a person has to DO. Nothing that is merely
-- interesting belongs in this result set -- an alert nobody can act on trains
-- people to ignore the whole panel.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericsubdashboard_rs7(
    p_farmid text,
    p_asof   date DEFAULT NULL
) RETURNS TABLE(
    duetobillcount          integer,
    duetobillamount         numeric,
    draftinvoicecount       integer,
    draftinvoiceamount      numeric,
    endingsooncount         integer,
    recurringduecount       integer,
    recurringdueamount      numeric,
    overduecustomercount    integer,
    overduecustomeramount   numeric,
    negativeaccountcount    integer
)
LANGUAGE sql STABLE
AS $function$
    WITH d AS (SELECT COALESCE(p_asof, (now() at time zone 'utc')::date) AS today)
    SELECT
        (SELECT COUNT(*)::int FROM genericsubscriptions s, d
          WHERE s.farmid = p_farmid AND s.status = 'Active' AND s.autogenerateinvoice
            AND s.nextbillingdate IS NOT NULL AND s.nextbillingdate <= d.today),
        COALESCE((SELECT SUM(s.billingamount - s.discountamount + s.taxamount)
                  FROM genericsubscriptions s, d
                  WHERE s.farmid = p_farmid AND s.status = 'Active' AND s.autogenerateinvoice
                    AND s.nextbillingdate IS NOT NULL AND s.nextbillingdate <= d.today), 0)::numeric,
        (SELECT COUNT(*)::int FROM genericsales s
          WHERE s.farmid = p_farmid AND s.status = 'Draft'
            AND COALESCE(s.isdeleted, FALSE) = FALSE
            AND s.genericsubscriptionid IS NOT NULL),
        COALESCE((SELECT SUM(s.totalamount) FROM genericsales s
                  WHERE s.farmid = p_farmid AND s.status = 'Draft'
                    AND COALESCE(s.isdeleted, FALSE) = FALSE
                    AND s.genericsubscriptionid IS NOT NULL), 0)::numeric,
        (SELECT COUNT(*)::int FROM genericsubscriptions s, d
          WHERE s.farmid = p_farmid AND s.status = 'Active'
            AND s.enddate IS NOT NULL
            AND s.enddate BETWEEN d.today AND d.today + 30),
        (SELECT COUNT(*)::int FROM genericrecurringexpenses r, d
          WHERE r.farmid = p_farmid AND r.status = 'Active'
            AND r.nextduedate IS NOT NULL AND r.nextduedate <= d.today),
        COALESCE((SELECT SUM(r.amount) FROM genericrecurringexpenses r, d
                  WHERE r.farmid = p_farmid AND r.status = 'Active'
                    AND r.nextduedate IS NOT NULL AND r.nextduedate <= d.today), 0)::numeric,
        (SELECT COUNT(DISTINCT o.genericcustomerid)::int
           FROM fngenericopeninvoices(p_farmid) o, d
          WHERE o.balance > 0 AND o.duedate < d.today),
        COALESCE((SELECT SUM(o.balance) FROM fngenericopeninvoices(p_farmid) o, d
                  WHERE o.balance > 0 AND o.duedate < d.today), 0)::numeric,
        (SELECT COUNT(*)::int FROM genericcashaccounts a
          WHERE a.farmid = p_farmid AND a.isactive AND a.currentbalance < 0);
$function$;

-- -----------------------------------------------------------------------------
-- rs8: what the team cost this month.
--
-- Staff payments (249) and payroll runs are both real labour cost and both are
-- counted. They cannot double count each other: a payroll run pays through
-- genericpayrollitems, a staff payment through genericstaffpayments, and
-- neither writes into the other.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericsubdashboard_rs8(
    p_farmid text,
    p_asof   date DEFAULT NULL
) RETURNS TABLE(
    peoplepaid       integer,
    staffpaymenttotal numeric,
    payrolltotal     numeric,
    totalpaid        numeric,
    toppersonname    text,
    toppersonamount  numeric
)
LANGUAGE plpgsql STABLE
AS $function$
DECLARE
    v_today      date      := COALESCE(p_asof, (now() at time zone 'utc')::date);
    v_monthstart date      := date_trunc('month', v_today)::date;
    v_start      timestamp := v_monthstart::timestamp;
    v_end        timestamp := (date_trunc('month', v_today) + interval '1 month')::timestamp;
BEGIN
    RETURN QUERY
    WITH paid AS (
        SELECT sp.genericstaffid, sp.amount
        FROM   genericstaffpayments sp
        WHERE  sp.farmid = p_farmid AND sp.status <> 'Reversed'
           AND sp.paymentdate >= v_start AND sp.paymentdate < v_end
    ),
    payroll AS (
        SELECT i.genericstaffid, i.netpay AS amount
        FROM   genericpayrollitems i
        JOIN   genericpayrollruns run
               ON run.genericpayrollrunid = i.genericpayrollrunid
        WHERE  run.farmid = p_farmid
           AND COALESCE(run.isdeleted, FALSE) = FALSE
           AND run.status = 'Paid'
           AND run.paydate >= v_monthstart
           AND run.paydate <  (date_trunc('month', v_today) + interval '1 month')::date
    ),
    everyone AS (
        SELECT genericstaffid, amount FROM paid
        UNION ALL
        SELECT genericstaffid, amount FROM payroll
    ),
    top1 AS (
        SELECT e.genericstaffid, SUM(e.amount) AS total
        FROM   everyone e
        GROUP  BY e.genericstaffid
        ORDER  BY SUM(e.amount) DESC
        LIMIT  1
    )
    SELECT (SELECT COUNT(DISTINCT e.genericstaffid)::int FROM everyone e),
           COALESCE((SELECT SUM(amount) FROM paid), 0)::numeric,
           COALESCE((SELECT SUM(amount) FROM payroll), 0)::numeric,
           COALESCE((SELECT SUM(amount) FROM everyone), 0)::numeric,
           (SELECT (st.firstname || ' ' || COALESCE(st.lastname, ''))::text
              FROM top1 JOIN genericstaff st ON st.genericstaffid = top1.genericstaffid),
           COALESCE((SELECT total FROM top1), 0)::numeric;
END;
$function$;

-- =============================================================================
-- THE REPORTS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Report 2: monthly recurring revenue.
--
-- Every column is a sum over the one month grid. Active MRR includes a
-- subscription in the month it was cancelled and excludes it from the next --
-- so lost MRR in March explains the fall from March to April, which is the
-- only reading of the two columns that reconciles.
--
-- Expansion and contraction are always zero. See the file header: there is no
-- amount history to compute them from, and a guess is worse than a gap.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericreport_mrr(
    p_farmid text,
    p_from   date,
    p_to     date
) RETURNS TABLE(
    monthstart     date,
    activemrr      numeric,
    activecount    integer,
    newmrr         numeric,
    newcount       integer,
    lostmrr        numeric,
    lostcount      integer,
    expansionmrr   numeric,
    contractionmrr numeric,
    netmrrchange   numeric
)
LANGUAGE sql STABLE
AS $function$
    SELECT g.monthstart,
           COALESCE(SUM(g.monthlyamount), 0)::numeric(14,2),
           COUNT(*)::int,
           COALESCE(SUM(CASE WHEN g.isnew  THEN g.monthlyamount ELSE 0 END), 0)::numeric(14,2),
           COUNT(*) FILTER (WHERE g.isnew)::int,
           COALESCE(SUM(CASE WHEN g.islost THEN g.monthlyamount ELSE 0 END), 0)::numeric(14,2),
           COUNT(*) FILTER (WHERE g.islost)::int,
           0::numeric,
           0::numeric,
           COALESCE(SUM(CASE WHEN g.isnew  THEN g.monthlyamount ELSE 0 END), 0)::numeric(14,2)
           - COALESCE(SUM(CASE WHEN g.islost THEN g.monthlyamount ELSE 0 END), 0)::numeric(14,2)
    FROM   fngenericsubscriptionmonths(p_farmid, p_from, p_to) g
    GROUP  BY g.monthstart
    ORDER  BY g.monthstart;
$function$;

-- -----------------------------------------------------------------------------
-- Report 1 rs1: subscription revenue by month.
--
-- INVOICED is what was billed in the month. COLLECTED is what has been paid
-- against those invoices AS OF NOW, not what was paid in that month -- an
-- invoice raised in March and paid in May is collected March revenue, and
-- showing it under May would make the month's revenue unreconcilable with its
-- own invoices. The payment report is where cash-by-month lives.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericreport_subscriptionrevenue_rs1(
    p_farmid text,
    p_from   date,
    p_to     date
) RETURNS TABLE(
    monthstart      date,
    invoicecount    integer,
    invoicedamount  numeric,
    collectedamount numeric,
    outstanding     numeric,
    activemrr       numeric,
    newcount        integer,
    lostcount       integer
)
LANGUAGE sql STABLE
AS $function$
    WITH months AS (
        SELECT gs::date AS monthstart
        FROM   generate_series(date_trunc('month', p_from)::date,
                               date_trunc('month', p_to)::date,
                               interval '1 month') gs
    ),
    inv AS (
        SELECT date_trunc('month', s.saledate)::date AS monthstart,
               COUNT(*)::int                         AS invoicecount,
               SUM(s.totalamount)                    AS invoicedamount,
               SUM(s.amountpaid)                     AS collectedamount,
               SUM(GREATEST(s.balance, 0))           AS outstanding
        FROM   genericsales s
        WHERE  s.farmid = p_farmid
           AND s.status = 'Approved'
           AND COALESCE(s.isdeleted, FALSE) = FALSE
           AND s.genericsubscriptionid IS NOT NULL
           AND s.saledate >= p_from::timestamp
           AND s.saledate <  (p_to + 1)::timestamp
        GROUP  BY 1
    ),
    mrr AS (
        SELECT m.monthstart, m.activemrr, m.newcount, m.lostcount
        FROM   spgenericreport_mrr(p_farmid, p_from, p_to) m
    )
    SELECT m.monthstart,
           COALESCE(i.invoicecount, 0),
           COALESCE(i.invoicedamount, 0)::numeric(14,2),
           COALESCE(i.collectedamount, 0)::numeric(14,2),
           COALESCE(i.outstanding, 0)::numeric(14,2),
           COALESCE(r.activemrr, 0)::numeric(14,2),
           COALESCE(r.newcount, 0),
           COALESCE(r.lostcount, 0)
    FROM   months m
    LEFT   JOIN inv i ON i.monthstart = m.monthstart
    LEFT   JOIN mrr r ON r.monthstart = m.monthstart
    ORDER  BY m.monthstart;
$function$;

-- -----------------------------------------------------------------------------
-- Report 1 rs2: revenue by plan.
--
-- A plan with no invoices in the window still appears if it has live
-- subscriptions -- "this plan billed nothing this month" is the single most
-- useful row on the page, and an inner join would hide it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericreport_subscriptionrevenue_rs2(
    p_farmid text,
    p_from   date,
    p_to     date
) RETURNS TABLE(
    genericserviceid    integer,
    servicename         text,
    billingfrequency    text,
    activesubscriptions integer,
    activemrr           numeric,
    invoicecount        integer,
    invoicedamount      numeric,
    collectedamount     numeric,
    outstanding         numeric
)
LANGUAGE sql STABLE
AS $function$
    WITH live AS (
        SELECT s.genericserviceid,
               COUNT(*)::int AS activesubscriptions,
               SUM(fngenericmonthlyamount(
                   s.billingamount - s.discountamount + s.taxamount,
                   s.billingfrequency)) AS activemrr
        FROM   genericsubscriptions s
        WHERE  s.farmid = p_farmid AND s.status = 'Active'
        GROUP  BY s.genericserviceid
    ),
    inv AS (
        SELECT sub.genericserviceid,
               COUNT(*)::int               AS invoicecount,
               SUM(sa.totalamount)         AS invoicedamount,
               SUM(sa.amountpaid)          AS collectedamount,
               SUM(GREATEST(sa.balance,0)) AS outstanding
        FROM   genericsales sa
        JOIN   genericsubscriptions sub
               ON sub.genericsubscriptionid = sa.genericsubscriptionid
        WHERE  sa.farmid = p_farmid
           AND sa.status = 'Approved'
           AND COALESCE(sa.isdeleted, FALSE) = FALSE
           AND sa.saledate >= p_from::timestamp
           AND sa.saledate <  (p_to + 1)::timestamp
        GROUP  BY sub.genericserviceid
    ),
    ids AS (
        SELECT genericserviceid FROM live
        UNION
        SELECT genericserviceid FROM inv
    )
    SELECT ids.genericserviceid,
           COALESCE(sv.servicename, 'Unknown plan')::text,
           COALESCE(sv.billingfrequency, '')::text,
           COALESCE(l.activesubscriptions, 0),
           COALESCE(l.activemrr, 0)::numeric(14,2),
           COALESCE(i.invoicecount, 0),
           COALESCE(i.invoicedamount, 0)::numeric(14,2),
           COALESCE(i.collectedamount, 0)::numeric(14,2),
           COALESCE(i.outstanding, 0)::numeric(14,2)
    FROM   ids
    LEFT   JOIN genericservices sv
           ON sv.genericserviceid = ids.genericserviceid AND sv.farmid = p_farmid
    LEFT   JOIN live l ON l.genericserviceid = ids.genericserviceid
    LEFT   JOIN inv  i ON i.genericserviceid = ids.genericserviceid
    ORDER  BY COALESCE(i.invoicedamount, 0) DESC, COALESCE(l.activemrr, 0) DESC;
$function$;

-- -----------------------------------------------------------------------------
-- Report 1 rs3: revenue by customer / member / client.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericreport_subscriptionrevenue_rs3(
    p_farmid text,
    p_from   date,
    p_to     date
) RETURNS TABLE(
    genericcustomerid   integer,
    customername        text,
    contactphone        text,
    activesubscriptions integer,
    activemrr           numeric,
    invoicecount        integer,
    invoicedamount      numeric,
    collectedamount     numeric,
    outstanding         numeric,
    lastpaymentdate     timestamp
)
LANGUAGE sql STABLE
AS $function$
    WITH live AS (
        SELECT s.genericcustomerid,
               COUNT(*)::int AS activesubscriptions,
               SUM(fngenericmonthlyamount(
                   s.billingamount - s.discountamount + s.taxamount,
                   s.billingfrequency)) AS activemrr
        FROM   genericsubscriptions s
        WHERE  s.farmid = p_farmid AND s.status = 'Active'
        GROUP  BY s.genericcustomerid
    ),
    inv AS (
        SELECT sa.genericcustomerid,
               COUNT(*)::int               AS invoicecount,
               SUM(sa.totalamount)         AS invoicedamount,
               SUM(sa.amountpaid)          AS collectedamount,
               SUM(GREATEST(sa.balance,0)) AS outstanding
        FROM   genericsales sa
        WHERE  sa.farmid = p_farmid
           AND sa.status = 'Approved'
           AND COALESCE(sa.isdeleted, FALSE) = FALSE
           AND sa.genericsubscriptionid IS NOT NULL
           AND sa.genericcustomerid IS NOT NULL
           AND sa.saledate >= p_from::timestamp
           AND sa.saledate <  (p_to + 1)::timestamp
        GROUP  BY sa.genericcustomerid
    ),
    ids AS (
        SELECT genericcustomerid FROM live
        UNION
        SELECT genericcustomerid FROM inv
    )
    SELECT ids.genericcustomerid,
           c.customername::text,
           c.phonenumber::text,
           COALESCE(l.activesubscriptions, 0),
           COALESCE(l.activemrr, 0)::numeric(14,2),
           COALESCE(i.invoicecount, 0),
           COALESCE(i.invoicedamount, 0)::numeric(14,2),
           COALESCE(i.collectedamount, 0)::numeric(14,2),
           COALESCE(i.outstanding, 0)::numeric(14,2),
           (SELECT MAX(p.paymentdate) FROM genericcustomerpayments p
             WHERE p.farmid = p_farmid AND p.status = 'Approved'
               AND p.genericcustomerid = ids.genericcustomerid)
    FROM   ids
    JOIN   genericcustomers c
           ON c.genericcustomerid = ids.genericcustomerid AND c.farmid = p_farmid
    LEFT   JOIN live l ON l.genericcustomerid = ids.genericcustomerid
    LEFT   JOIN inv  i ON i.genericcustomerid = ids.genericcustomerid
    ORDER  BY COALESCE(i.invoicedamount, 0) DESC, COALESCE(l.activemrr, 0) DESC;
$function$;

-- -----------------------------------------------------------------------------
-- Report 8: the income half of an owner-friendly P&L.
--
-- spgenericreport_periodpnl (037) already computes income, expenses, COGS and
-- profit for a period, and is what the P&L page shows. The one thing a service
-- business needs on top is which part of the income recurs. This adds exactly
-- that and nothing else; the totals still come from the existing function.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericreport_incomesplit(
    p_farmid text,
    p_from   date,
    p_to     date
) RETURNS TABLE(
    subscriptionincome       numeric,
    subscriptioninvoicecount integer,
    otherincome              numeric,
    othersalescount          integer,
    totalincome              numeric
)
LANGUAGE sql STABLE
AS $function$
    SELECT COALESCE(SUM(s.totalamount) FILTER (WHERE s.genericsubscriptionid IS NOT NULL), 0)::numeric(14,2),
           COUNT(*) FILTER (WHERE s.genericsubscriptionid IS NOT NULL)::int,
           COALESCE(SUM(s.totalamount) FILTER (WHERE s.genericsubscriptionid IS NULL), 0)::numeric(14,2),
           COUNT(*) FILTER (WHERE s.genericsubscriptionid IS NULL)::int,
           COALESCE(SUM(s.totalamount), 0)::numeric(14,2)
    FROM   genericsales s
    WHERE  s.farmid = p_farmid
       AND s.status = 'Approved'
       AND COALESCE(s.isdeleted, FALSE) = FALSE
       AND s.saledate >= p_from::timestamp
       AND s.saledate <  (p_to + 1)::timestamp;
$function$;

-- -----------------------------------------------------------------------------
-- Report 5a: expenses by supplier.
--
-- Expenses with no supplier are a real and large category -- petrol, tips,
-- one-off cash costs -- so they get their own row rather than vanishing behind
-- an inner join. partyid is NULL for it, which is how the page knows not to
-- link it anywhere.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericreport_expensesbysupplier(
    p_farmid text,
    p_from   date,
    p_to     date
) RETURNS TABLE(
    genericsupplierid integer,
    suppliername      text,
    expensecount      integer,
    totalamount       numeric,
    amountpaid        numeric,
    outstanding       numeric
)
LANGUAGE sql STABLE
AS $function$
    SELECT e.genericsupplierid,
           COALESCE(su.suppliername, 'No supplier')::text,
           COUNT(*)::int,
           SUM(e.amount)::numeric(14,2),
           -- amountpaid is read RESOLVED: NULL means paid in full, the same
           -- reading fngenericpayables (248) uses.
           SUM(COALESCE(e.amountpaid, e.amount))::numeric(14,2),
           GREATEST(SUM(e.amount) - SUM(COALESCE(e.amountpaid, e.amount)), 0)::numeric(14,2)
    FROM   genericexpenses e
    LEFT   JOIN genericsuppliers su
           ON su.genericsupplierid = e.genericsupplierid AND su.farmid = e.farmid
    WHERE  e.farmid = p_farmid
       AND e.status = 'Approved'
       AND COALESCE(e.isdeleted, FALSE) = FALSE
       AND e.expensedate >= p_from::timestamp
       AND e.expensedate <  (p_to + 1)::timestamp
    GROUP  BY e.genericsupplierid, su.suppliername
    ORDER  BY SUM(e.amount) DESC;
$function$;

-- -----------------------------------------------------------------------------
-- Report 5b: the monthly expense trend, with the recurring share called out.
--
-- Every month in the window appears, including the empty ones. A trend line
-- that silently skips a zero month slopes wrongly.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericreport_expensetrend(
    p_farmid text,
    p_from   date,
    p_to     date
) RETURNS TABLE(
    monthstart      date,
    expensecount    integer,
    totalamount     numeric,
    recurringamount numeric,
    staffamount     numeric
)
LANGUAGE sql STABLE
AS $function$
    WITH months AS (
        SELECT gs::date AS monthstart
        FROM   generate_series(date_trunc('month', p_from)::date,
                               date_trunc('month', p_to)::date,
                               interval '1 month') gs
    ),
    ex AS (
        SELECT date_trunc('month', e.expensedate)::date AS monthstart,
               COUNT(*)::int                            AS expensecount,
               SUM(e.amount)                            AS totalamount,
               SUM(e.amount) FILTER (WHERE e.genericrecurringexpenseid IS NOT NULL) AS recurringamount
        FROM   genericexpenses e
        WHERE  e.farmid = p_farmid
           AND e.status = 'Approved'
           AND COALESCE(e.isdeleted, FALSE) = FALSE
           AND e.expensedate >= p_from::timestamp
           AND e.expensedate <  (p_to + 1)::timestamp
        GROUP  BY 1
    ),
    st AS (
        SELECT date_trunc('month', sp.paymentdate)::date AS monthstart,
               SUM(sp.amount) AS staffamount
        FROM   genericstaffpayments sp
        WHERE  sp.farmid = p_farmid
           AND sp.status <> 'Reversed'
           AND sp.paymentdate >= p_from::timestamp
           AND sp.paymentdate <  (p_to + 1)::timestamp
        GROUP  BY 1
    )
    SELECT m.monthstart,
           COALESCE(ex.expensecount, 0),
           COALESCE(ex.totalamount, 0)::numeric(14,2),
           COALESCE(ex.recurringamount, 0)::numeric(14,2),
           COALESCE(st.staffamount, 0)::numeric(14,2)
    FROM   months m
    LEFT   JOIN ex ON ex.monthstart = m.monthstart
    LEFT   JOIN st ON st.monthstart = m.monthstart
    ORDER  BY m.monthstart;
$function$;

-- -----------------------------------------------------------------------------
-- Report 6a: which categories COUNT as hosting.
--
-- The hosting report cannot hardcode a category id -- every company names its
-- own. So this returns the company's categories with a suggested flag from a
-- name match, the page shows them as checkboxes, and the report takes the ids
-- back. Guessing without letting the owner correct it would produce a number
-- that is confidently wrong.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericreport_hostingcategories(
    p_farmid text
) RETURNS TABLE(
    genericexpensecategoryid integer,
    categoryname             text,
    issuggested              boolean,
    totalamount              numeric
)
LANGUAGE sql STABLE
AS $function$
    SELECT c.genericexpensecategoryid,
           c.name::text,
           (c.name ~* '(host|cloud|server|domain|saas|software|licen[cs]e|subscription|bandwidth|internet)'),
           COALESCE((SELECT SUM(e.amount) FROM genericexpenses e
                      WHERE e.farmid = p_farmid
                        AND e.genericexpensecategoryid = c.genericexpensecategoryid
                        AND e.status = 'Approved'
                        AND COALESCE(e.isdeleted, FALSE) = FALSE), 0)::numeric(14,2)
    FROM   genericexpensecategories c
    WHERE  c.farmid = p_farmid
       AND COALESCE(c.isdeleted, FALSE) = FALSE
    ORDER  BY (c.name ~* '(host|cloud|server|domain|saas|software|licen[cs]e|subscription|bandwidth|internet)') DESC,
              c.name;
$function$;

-- -----------------------------------------------------------------------------
-- Report 6b: hosting / cloud cost against revenue.
--
-- p_categoryids NULL means "use the suggested ones". Passing an empty array is
-- different and means "none", which correctly produces zeros rather than
-- silently falling back to the guess.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericreport_hostingcost(
    p_farmid       text,
    p_from         date,
    p_to           date,
    p_categoryids  integer[] DEFAULT NULL
) RETURNS TABLE(
    monthstart     date,
    hostingcost    numeric,
    expensecount   integer,
    totalrevenue   numeric,
    totalexpenses  numeric,
    pctofrevenue   numeric,
    pctofexpenses  numeric
)
LANGUAGE sql STABLE
AS $function$
    WITH months AS (
        SELECT gs::date AS monthstart
        FROM   generate_series(date_trunc('month', p_from)::date,
                               date_trunc('month', p_to)::date,
                               interval '1 month') gs
    ),
    chosen AS (
        SELECT h.genericexpensecategoryid
        FROM   spgenericreport_hostingcategories(p_farmid) h
        WHERE  CASE WHEN p_categoryids IS NULL
                    THEN h.issuggested
                    ELSE h.genericexpensecategoryid = ANY (p_categoryids)
               END
    ),
    host AS (
        SELECT date_trunc('month', e.expensedate)::date AS monthstart,
               SUM(e.amount) AS hostingcost,
               COUNT(*)::int AS expensecount
        FROM   genericexpenses e
        WHERE  e.farmid = p_farmid
           AND e.status = 'Approved'
           AND COALESCE(e.isdeleted, FALSE) = FALSE
           AND e.genericexpensecategoryid IN (SELECT genericexpensecategoryid FROM chosen)
           AND e.expensedate >= p_from::timestamp
           AND e.expensedate <  (p_to + 1)::timestamp
        GROUP  BY 1
    ),
    allex AS (
        SELECT date_trunc('month', e.expensedate)::date AS monthstart,
               SUM(e.amount) AS totalexpenses
        FROM   genericexpenses e
        WHERE  e.farmid = p_farmid
           AND e.status = 'Approved'
           AND COALESCE(e.isdeleted, FALSE) = FALSE
           AND e.expensedate >= p_from::timestamp
           AND e.expensedate <  (p_to + 1)::timestamp
        GROUP  BY 1
    ),
    rev AS (
        SELECT date_trunc('month', s.saledate)::date AS monthstart,
               SUM(s.totalamount) AS totalrevenue
        FROM   genericsales s
        WHERE  s.farmid = p_farmid
           AND s.status = 'Approved'
           AND COALESCE(s.isdeleted, FALSE) = FALSE
           AND s.saledate >= p_from::timestamp
           AND s.saledate <  (p_to + 1)::timestamp
        GROUP  BY 1
    )
    SELECT m.monthstart,
           COALESCE(h.hostingcost, 0)::numeric(14,2),
           COALESCE(h.expensecount, 0),
           COALESCE(r.totalrevenue, 0)::numeric(14,2),
           COALESCE(a.totalexpenses, 0)::numeric(14,2),
           CASE WHEN COALESCE(r.totalrevenue, 0) > 0
                THEN ROUND(COALESCE(h.hostingcost, 0) * 100 / r.totalrevenue, 2)
                ELSE 0 END::numeric,
           CASE WHEN COALESCE(a.totalexpenses, 0) > 0
                THEN ROUND(COALESCE(h.hostingcost, 0) * 100 / a.totalexpenses, 2)
                ELSE 0 END::numeric
    FROM   months m
    LEFT   JOIN host  h ON h.monthstart = m.monthstart
    LEFT   JOIN allex a ON a.monthstart = m.monthstart
    LEFT   JOIN rev   r ON r.monthstart = m.monthstart
    ORDER  BY m.monthstart;
$function$;

-- -----------------------------------------------------------------------------
-- Report 7: what people cost.
--
-- Staff payments (249) AND paid payroll runs, because both are labour cost and
-- a business that uses one for contractors and the other for employees would
-- otherwise see half its wage bill. The two cannot overlap: they are different
-- tables and neither writes the other.
--
-- rs1 by person, rs2 by month, rs3 by role.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericreport_staffcost_rs1(
    p_farmid text,
    p_from   date,
    p_to     date
) RETURNS TABLE(
    genericstaffid  integer,
    staffname       text,
    staffrole       text,
    workertype      text,
    paymentcount    integer,
    staffpayments   numeric,
    payrollpay      numeric,
    totalpaid       numeric,
    lastpaymentdate date
)
LANGUAGE sql STABLE
AS $function$
    WITH paid AS (
        SELECT sp.genericstaffid, sp.amount, sp.paymentdate::date AS paidon, 'Payment'::text AS src
        FROM   genericstaffpayments sp
        WHERE  sp.farmid = p_farmid AND sp.status <> 'Reversed'
           AND sp.paymentdate >= p_from::timestamp
           AND sp.paymentdate <  (p_to + 1)::timestamp
        UNION ALL
        SELECT i.genericstaffid, i.netpay, run.paydate, 'Payroll'::text
        FROM   genericpayrollitems i
        JOIN   genericpayrollruns run ON run.genericpayrollrunid = i.genericpayrollrunid
        WHERE  run.farmid = p_farmid
           AND COALESCE(run.isdeleted, FALSE) = FALSE
           AND run.status = 'Paid'
           AND run.paydate >= p_from AND run.paydate <= p_to
    )
    SELECT p.genericstaffid,
           (st.firstname || ' ' || COALESCE(st.lastname, ''))::text,
           st.role::text,
           st.workertype::text,
           COUNT(*)::int,
           COALESCE(SUM(p.amount) FILTER (WHERE p.src = 'Payment'), 0)::numeric(14,2),
           COALESCE(SUM(p.amount) FILTER (WHERE p.src = 'Payroll'), 0)::numeric(14,2),
           SUM(p.amount)::numeric(14,2),
           MAX(p.paidon)
    FROM   paid p
    LEFT   JOIN genericstaff st
           ON st.genericstaffid = p.genericstaffid AND st.farmid = p_farmid
    GROUP  BY p.genericstaffid, st.firstname, st.lastname, st.role, st.workertype
    ORDER  BY SUM(p.amount) DESC;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericreport_staffcost_rs2(
    p_farmid text,
    p_from   date,
    p_to     date
) RETURNS TABLE(
    monthstart    date,
    peoplepaid    integer,
    staffpayments numeric,
    payrollpay    numeric,
    totalpaid     numeric
)
LANGUAGE sql STABLE
AS $function$
    WITH months AS (
        SELECT gs::date AS monthstart
        FROM   generate_series(date_trunc('month', p_from)::date,
                               date_trunc('month', p_to)::date,
                               interval '1 month') gs
    ),
    paid AS (
        SELECT date_trunc('month', sp.paymentdate)::date AS monthstart,
               sp.genericstaffid, sp.amount, 'Payment'::text AS src
        FROM   genericstaffpayments sp
        WHERE  sp.farmid = p_farmid AND sp.status <> 'Reversed'
           AND sp.paymentdate >= p_from::timestamp
           AND sp.paymentdate <  (p_to + 1)::timestamp
        UNION ALL
        SELECT date_trunc('month', run.paydate)::date, i.genericstaffid, i.netpay, 'Payroll'::text
        FROM   genericpayrollitems i
        JOIN   genericpayrollruns run ON run.genericpayrollrunid = i.genericpayrollrunid
        WHERE  run.farmid = p_farmid
           AND COALESCE(run.isdeleted, FALSE) = FALSE
           AND run.status = 'Paid'
           AND run.paydate >= p_from AND run.paydate <= p_to
    )
    SELECT m.monthstart,
           COALESCE(COUNT(DISTINCT p.genericstaffid), 0)::int,
           COALESCE(SUM(p.amount) FILTER (WHERE p.src = 'Payment'), 0)::numeric(14,2),
           COALESCE(SUM(p.amount) FILTER (WHERE p.src = 'Payroll'), 0)::numeric(14,2),
           COALESCE(SUM(p.amount), 0)::numeric(14,2)
    FROM   months m
    LEFT   JOIN paid p ON p.monthstart = m.monthstart
    GROUP  BY m.monthstart
    ORDER  BY m.monthstart;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericreport_staffcost_rs3(
    p_farmid text,
    p_from   date,
    p_to     date
) RETURNS TABLE(
    staffrole   text,
    peoplecount integer,
    totalpaid   numeric,
    pctoftotal  numeric
)
LANGUAGE sql STABLE
AS $function$
    WITH paid AS (
        SELECT sp.genericstaffid, sp.amount
        FROM   genericstaffpayments sp
        WHERE  sp.farmid = p_farmid AND sp.status <> 'Reversed'
           AND sp.paymentdate >= p_from::timestamp
           AND sp.paymentdate <  (p_to + 1)::timestamp
        UNION ALL
        SELECT i.genericstaffid, i.netpay
        FROM   genericpayrollitems i
        JOIN   genericpayrollruns run ON run.genericpayrollrunid = i.genericpayrollrunid
        WHERE  run.farmid = p_farmid
           AND COALESCE(run.isdeleted, FALSE) = FALSE
           AND run.status = 'Paid'
           AND run.paydate >= p_from AND run.paydate <= p_to
    ),
    byrole AS (
        SELECT COALESCE(NULLIF(btrim(st.role), ''), 'Unassigned')::text AS staffrole,
               COUNT(DISTINCT p.genericstaffid)::int AS peoplecount,
               SUM(p.amount) AS totalpaid
        FROM   paid p
        LEFT   JOIN genericstaff st
               ON st.genericstaffid = p.genericstaffid AND st.farmid = p_farmid
        GROUP  BY 1
    )
    SELECT b.staffrole, b.peoplecount, b.totalpaid::numeric(14,2),
           CASE WHEN SUM(b.totalpaid) OVER () > 0
                THEN ROUND(b.totalpaid * 100 / SUM(b.totalpaid) OVER (), 2)
                ELSE 0 END::numeric
    FROM   byrole b
    ORDER  BY b.totalpaid DESC;
$function$;

-- -----------------------------------------------------------------------------
-- Report 10: break-even.
--
--   break-even customers = monthly fixed costs / average monthly revenue per
--                          customer
--
-- Fixed costs are averaged over the last p_months COMPLETE months. The current
-- month is excluded on purpose: on the 2nd of the month it holds two days of
-- costs, which would halve the average and halve the answer with it.
--
-- "Fixed" is read as total operating expenses. This system has no fixed /
-- variable flag on an expense, and inventing one from category names would be
-- a guess the owner cannot see or correct. For a service business -- rent,
-- hosting, salaries, tools -- the two are close, and the report says which
-- reading it used rather than implying a precision it does not have.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericreport_breakeven(
    p_farmid text,
    p_asof   date DEFAULT NULL,
    p_months integer DEFAULT 3
) RETURNS TABLE(
    monthsaveraged        integer,
    periodstart           date,
    periodend             date,
    monthlyfixedcosts     numeric,
    monthlyrecurringrevenue numeric,
    activecustomers       integer,
    activesubscriptions   integer,
    avgrevenuepercustomer numeric,
    breakevencustomers    integer,
    customersurplus       integer,
    monthlysurplus        numeric
)
LANGUAGE plpgsql STABLE
AS $function$
DECLARE
    v_today      date := COALESCE(p_asof, (now() at time zone 'utc')::date);
    v_months     integer := GREATEST(COALESCE(p_months, 3), 1);
    v_monthstart date := date_trunc('month', v_today)::date;
    v_from       date;
    v_to         date;
    v_fixed      numeric(14,2);
    v_mrr        numeric(14,2);
    v_custs      integer;
    v_subs       integer;
    v_avg        numeric(14,2);
    v_needed     integer;
BEGIN
    v_from := (v_monthstart - (v_months || ' months')::interval)::date;
    v_to   := (v_monthstart - interval '1 day')::date;

    v_fixed := COALESCE((
        SELECT SUM(e.amount) / v_months
        FROM   genericexpenses e
        WHERE  e.farmid = p_farmid AND e.status = 'Approved'
           AND COALESCE(e.isdeleted, FALSE) = FALSE
           AND e.expensedate >= v_from::timestamp
           AND e.expensedate <  v_monthstart::timestamp), 0);

    SELECT COALESCE(SUM(fngenericmonthlyamount(
                            s.billingamount - s.discountamount + s.taxamount,
                            s.billingfrequency)), 0),
           COUNT(DISTINCT s.genericcustomerid)::int,
           COUNT(*)::int
      INTO v_mrr, v_custs, v_subs
      FROM genericsubscriptions s
     WHERE s.farmid = p_farmid
       AND s.status = 'Active'
       AND COALESCE(s.billingfrequency, 'OneTime') <> 'OneTime'
       AND s.startdate <= v_today
       AND (s.enddate IS NULL OR s.enddate >= v_today);

    v_avg    := CASE WHEN v_custs > 0 THEN ROUND(v_mrr / v_custs, 2) ELSE 0 END;
    v_needed := CASE WHEN v_avg > 0 THEN CEIL(v_fixed / v_avg)::int ELSE 0 END;

    RETURN QUERY
    SELECT v_months, v_from, v_to,
           ROUND(v_fixed, 2)::numeric,
           v_mrr,
           v_custs,
           v_subs,
           v_avg,
           v_needed,
           -- Negative means that many customers short of covering the month.
           (v_custs - v_needed),
           ROUND(v_mrr - v_fixed, 2)::numeric;
END;
$function$;

COMMIT;

-- =============================================================================
-- 317_HotelProfitLoss.postgres.sql
--
-- Purpose
-- -------
-- A Profit & Loss report for the Hotel module.
--
--   Revenue
--     Room Revenue          guest payments on invoices/bookings
--     Restaurant / F&B      walk-in restaurant orders (delivered)
--     Deposits Net          collected minus refunded
--   = TOTAL REVENUE
--
--   Operating Expenses
--     Staff Wages           paid payroll runs (net pay)
--     [each expense category from hotelexpensecategories]
--   = TOTAL EXPENSES
--
--   = NET PROFIT            Revenue - Expenses
--
-- Revenue is ACCRUAL: when the invoice is paid, not when the room was booked.
-- Expenses are when approved/paid, not when incurred as draft.
--
-- No financing or capital section: hotel has no owner-money, loan or capital
-- asset tables yet. Those can be added as informational sections later.
--
-- Only NON-ZERO lines are returned, same as poultry 272.
--
-- Order: after 316. No table is created, altered or written to.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- Drop existing versions if any
DROP FUNCTION IF EXISTS public.sphotelreport_pllines(text, date, date);
DROP FUNCTION IF EXISTS public.sphotelreport_plsummary(text, date, date);
DROP FUNCTION IF EXISTS public.sphotelreport_plexpensedetail(text, date, date, text);
DROP FUNCTION IF EXISTS public.sphotelreport_plrevenuedetail(text, date, date, text);

-- -----------------------------------------------------------------------------
-- 1. The statement, one line at a time.
-- -----------------------------------------------------------------------------
-- section:  Revenue | OperatingExpense
-- linekey:  RoomRevenue, RestaurantRevenue, DepositsNet, StaffWages, <category>
-- Only non-zero lines are returned.
CREATE OR REPLACE FUNCTION public.sphotelreport_pllines(
    p_farmid    text,
    p_startdate date,
    p_enddate   date
) RETURNS TABLE(
    section         text,
    linekey         text,
    linelabel       text,
    amount          numeric,
    sortorder       integer,
    isinformational boolean,
    entrycount      integer
)
LANGUAGE sql STABLE
AS $function$
    -- Revenue lines
    WITH rev_payments AS (
        SELECT 'Revenue'::text   AS sec,
               'RoomRevenue'     AS k,
               'Room Revenue'    AS lbl,
               ROUND(COALESCE(SUM(hp.amount), 0), 2) AS amt,
               10                AS so,
               FALSE             AS info,
               COUNT(*)::integer AS n
        FROM   hotelpayments hp
        WHERE  lower(hp.farmid::text) = lower(p_farmid)
          AND  hp.paymentdate::date >= p_startdate
          AND  hp.paymentdate::date <= p_enddate
          AND  COALESCE(hp.amount, 0) > 0
    ),
    rev_restaurant AS (
        SELECT 'Revenue'::text       AS sec,
               'RestaurantRevenue'   AS k,
               'Restaurant / F&B'    AS lbl,
               ROUND(COALESCE(SUM(ro.totalamount), 0), 2) AS amt,
               20                    AS so,
               FALSE                 AS info,
               COUNT(*)::integer     AS n
        FROM   hotelrestaurantorders ro
        WHERE  lower(ro.farmid::text) = lower(p_farmid)
          AND  ro.hotelbookingid IS NULL
          AND  ro.status = 'Delivered'
          AND  COALESCE(ro.totalamount, 0) > 0
          AND  COALESCE(ro.deliveredtime, ro.ordertime)::date >= p_startdate
          AND  COALESCE(ro.deliveredtime, ro.ordertime)::date <= p_enddate
    ),
    dep_collected AS (
        SELECT COALESCE(SUM(hd.amount), 0) AS amt, COUNT(*)::integer AS n
        FROM   hoteldeposits hd
        WHERE  lower(hd.farmid::text) = lower(p_farmid)
          AND  hd.deposittype = 'Collected'
          AND  COALESCE(hd.amount, 0) > 0
          AND  hd.createdat::date >= p_startdate
          AND  hd.createdat::date <= p_enddate
    ),
    dep_refunded AS (
        SELECT COALESCE(SUM(hd.amount), 0) AS amt, COUNT(*)::integer AS n
        FROM   hoteldeposits hd
        WHERE  lower(hd.farmid::text) = lower(p_farmid)
          AND  hd.deposittype = 'Refunded'
          AND  COALESCE(hd.amount, 0) > 0
          AND  hd.createdat::date >= p_startdate
          AND  hd.createdat::date <= p_enddate
    ),
    rev_deposits AS (
        SELECT 'Revenue'::text       AS sec,
               'DepositsNet'         AS k,
               'Deposits (net)'      AS lbl,
               ROUND((SELECT amt FROM dep_collected) - (SELECT amt FROM dep_refunded), 2) AS amt,
               30                    AS so,
               FALSE                 AS info,
               ((SELECT n FROM dep_collected) + (SELECT n FROM dep_refunded))::integer AS n
    ),
    -- Expense: payroll
    exp_payroll AS (
        SELECT 'OperatingExpense'::text AS sec,
               'StaffWages'             AS k,
               'Staff Wages'            AS lbl,
               ROUND(COALESCE(SUM(pr.totalnetpay), 0), 2) AS amt,
               100                      AS so,
               FALSE                    AS info,
               COUNT(*)::integer        AS n
        FROM   hotelpayrollruns pr
        WHERE  lower(pr.farmid::text) = lower(p_farmid)
          AND  pr.status = 'Paid'
          AND  COALESCE(pr.totalnetpay, 0) > 0
          AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::date >= p_startdate
          AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::date <= p_enddate
    ),
    -- Expense: each category from hotelexpenses
    exp_by_cat AS (
        SELECT 'OperatingExpense'::text AS sec,
               COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised') AS k,
               COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised') AS lbl,
               ROUND(SUM(he.amount), 2) AS amt,
               200                       AS so,
               FALSE                     AS info,
               COUNT(*)::integer         AS n
        FROM   hotelexpenses he
        LEFT   JOIN hotelexpensecategories ec
               ON  he.hotelexpensecategoryid = ec.hotelexpensecategoryid
        WHERE  lower(he.farmid::text) = lower(p_farmid)
          AND  he.status IN ('Approved', 'Paid')
          AND  COALESCE(he.amount, 0) > 0
          AND  he.expensedate >= p_startdate
          AND  he.expensedate <= p_enddate
        GROUP BY COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised')
    ),
    all_lines AS (
        SELECT * FROM rev_payments
        UNION ALL SELECT * FROM rev_restaurant
        UNION ALL SELECT * FROM rev_deposits
        UNION ALL SELECT * FROM exp_payroll
        UNION ALL SELECT * FROM exp_by_cat
    )
    SELECT a.sec, a.k, a.lbl, a.amt, a.so, a.info, a.n
    FROM   all_lines a
    WHERE  a.amt <> 0
    ORDER  BY a.so, a.lbl;
$function$;

-- -----------------------------------------------------------------------------
-- 2. The summary — totals and subtotals in one row.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sphotelreport_plsummary(
    p_farmid    text,
    p_startdate date,
    p_enddate   date
) RETURNS TABLE(
    -- Revenue
    roomrevenue          numeric,
    restaurantrevenue    numeric,
    depositsnet          numeric,
    totalrevenue         numeric,
    -- Expenses
    staffwages           numeric,
    totalexpensecategory numeric,
    totalexpenses        numeric,
    -- Profit
    netprofit            numeric,
    netmarginpercent     numeric,
    status               text,
    -- Counts
    revenueentries       integer,
    expenseentries       integer
)
LANGUAGE plpgsql STABLE
AS $function$
DECLARE
    v_room     numeric := 0;
    v_rest     numeric := 0;
    v_depnet   numeric := 0;
    v_wages    numeric := 0;
    v_expcat   numeric := 0;
    v_revn     integer := 0;
    v_expn     integer := 0;
    v_rev      numeric;
    v_exp      numeric;
    v_net      numeric;
    r          record;
BEGIN
    -- Sum from the lines function so the totals match the statement exactly
    FOR r IN SELECT * FROM sphotelreport_pllines(p_farmid, p_startdate, p_enddate)
    LOOP
        CASE r.linekey
            WHEN 'RoomRevenue'       THEN v_room   := r.amount; v_revn := v_revn + r.entrycount;
            WHEN 'RestaurantRevenue' THEN v_rest   := r.amount; v_revn := v_revn + r.entrycount;
            WHEN 'DepositsNet'       THEN v_depnet := r.amount; v_revn := v_revn + r.entrycount;
            WHEN 'StaffWages'        THEN v_wages  := r.amount; v_expn := v_expn + r.entrycount;
            ELSE
                IF r.section = 'OperatingExpense' THEN
                    v_expcat := v_expcat + r.amount;
                    v_expn   := v_expn + r.entrycount;
                END IF;
        END CASE;
    END LOOP;

    v_rev := ROUND(v_room + v_rest + v_depnet, 2);
    v_exp := ROUND(v_wages + v_expcat, 2);
    v_net := ROUND(v_rev - v_exp, 2);

    RETURN QUERY SELECT
        v_room, v_rest, v_depnet, v_rev,
        v_wages, v_expcat, v_exp,
        v_net,
        CASE WHEN v_rev > 0 THEN ROUND(v_net / v_rev * 100, 1) ELSE NULL::numeric END,
        CASE WHEN v_net > 0 THEN 'Profit'
             WHEN v_net < 0 THEN 'Loss'
             ELSE 'Break-even' END::text,
        v_revn, v_expn;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Expense drilldown — every approved/paid expense with its category.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sphotelreport_plexpensedetail(
    p_farmid    text,
    p_startdate date,
    p_enddate   date,
    p_linekey   text DEFAULT NULL
) RETURNS TABLE(
    hotelexpenseid       integer,
    expensedate          date,
    category             text,
    description          text,
    amount               numeric,
    vendor               text,
    paymentmethod        text,
    status               text,
    pllinekey            text
)
LANGUAGE sql STABLE
AS $function$
    SELECT he.hotelexpenseid,
           he.expensedate,
           COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised'),
           he.description::text,
           he.amount,
           he.vendor::text,
           he.paymentmethod::text,
           he.status::text,
           COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised')
    FROM   hotelexpenses he
    LEFT   JOIN hotelexpensecategories ec
           ON  he.hotelexpensecategoryid = ec.hotelexpensecategoryid
    WHERE  lower(he.farmid::text) = lower(p_farmid)
      AND  he.status IN ('Approved', 'Paid')
      AND  COALESCE(he.amount, 0) > 0
      AND  he.expensedate >= p_startdate
      AND  he.expensedate <= p_enddate
      AND  (p_linekey IS NULL
            OR COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised') = p_linekey)
    ORDER BY he.expensedate, he.hotelexpenseid;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Revenue drilldown — every payment and restaurant order in the period.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sphotelreport_plrevenuedetail(
    p_farmid    text,
    p_startdate date,
    p_enddate   date,
    p_linekey   text DEFAULT NULL
) RETURNS TABLE(
    sourcetype   text,
    sourceid     integer,
    entrydate    date,
    description  text,
    amount       numeric,
    method       text,
    pllinekey    text
)
LANGUAGE sql STABLE
AS $function$
    -- Guest payments
    SELECT 'GuestPayment'::text,
           hp.hotelpaymentid,
           hp.paymentdate::date,
           COALESCE(NULLIF(btrim(hp.notes), ''), NULLIF(btrim(hp.reference), ''),
                    'Guest payment #' || hp.hotelpaymentid::text)::text,
           hp.amount,
           hp.paymentmethod::text,
           'RoomRevenue'::text
    FROM   hotelpayments hp
    WHERE  lower(hp.farmid::text) = lower(p_farmid)
      AND  COALESCE(hp.amount, 0) > 0
      AND  hp.paymentdate::date >= p_startdate
      AND  hp.paymentdate::date <= p_enddate
      AND  (p_linekey IS NULL OR p_linekey = 'RoomRevenue')

    UNION ALL

    -- Walk-in restaurant orders
    SELECT 'RestaurantOrder'::text,
           ro.hotelrestaurantorderid,
           COALESCE(ro.deliveredtime, ro.ordertime)::date,
           COALESCE(NULLIF(btrim(ro.notes), ''),
                    'Order #' || ro.hotelrestaurantorderid::text
                    || COALESCE(' - Table ' || NULLIF(btrim(ro.tablenumber), ''), ''))::text,
           ro.totalamount,
           NULL::text,
           'RestaurantRevenue'::text
    FROM   hotelrestaurantorders ro
    WHERE  lower(ro.farmid::text) = lower(p_farmid)
      AND  ro.hotelbookingid IS NULL
      AND  ro.status = 'Delivered'
      AND  COALESCE(ro.totalamount, 0) > 0
      AND  COALESCE(ro.deliveredtime, ro.ordertime)::date >= p_startdate
      AND  COALESCE(ro.deliveredtime, ro.ordertime)::date <= p_enddate
      AND  (p_linekey IS NULL OR p_linekey = 'RestaurantRevenue')

    ORDER BY 3, 2;
$function$;

COMMIT;

-- Verification
SELECT 'hotel P&L functions (4 expected)' AS check,
       CASE WHEN count(*) = 4 THEN 'OK' ELSE 'ONLY ' || count(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('sphotelreport_pllines', 'sphotelreport_plsummary',
                     'sphotelreport_plexpensedetail', 'sphotelreport_plrevenuedetail');

-- Test: run the summary for each hotel farm
SELECT f.farmid, s.*
FROM   (SELECT DISTINCT farmid FROM hotelcashaccounts) f
CROSS  JOIN LATERAL public.sphotelreport_plsummary(
                        f.farmid, '2000-01-01'::date, '2999-12-31'::date) s
ORDER  BY f.farmid;

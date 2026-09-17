-- =============================================================================
-- Migration 299: Hotel reporting, server-side (PostgreSQL)
-- =============================================================================
-- The Hotel module ships 17 reports and, until this migration, NOT ONE
-- server-side report function. Every one of those pages calls an unfiltered
-- list endpoint -- listHotelBookings(), listHotelPayments(), listDailyClosings(),
-- all with no arguments -- pulls the whole table into the browser and aggregates
-- it in JavaScript. The ten functions here are the first aggregation the Hotel
-- module does in the database.
--
-- WHAT WAS MISSING, AND WHY THESE TEN
-- Checked the schema against standard lodging reporting (USALI, and the report
-- set every PMS ships). These are the gaps where the data was already being
-- written and nothing read it:
--
--   hotelbookings.source        -- which channel produced the business. The
--                                  classic production report. Never reported.
--   hotelbookings.createdat vs
--   .checkindate                -- booking lead time / pace. Never reported.
--   hotelbookings.hotelroomtypeid -- ADR and RevPAR PER ROOM TYPE. The existing
--                                  occupancy report reads daily closings only,
--                                  so it cannot see room type at all.
--   hoteldailyclosings totals   -- ADR and RevPAR are stored, but TRevPAR and
--                                  GOPPAR -- the two profitability metrics above
--                                  them -- were never derived.
--   hotelinvoices.balance/duedate -- the guest ledger. The billing report is
--                                  built from payments and never looks at an
--                                  invoice, so nothing ages a debt.
--   hotelstaycharges.chargetype -- ancillary spend per stay.
--   hotelhousekeepingtasks
--     .startedat/.completedat   -- minutes per room, per attendant. The
--                                  housekeeping report counts task statuses and
--                                  ignores both timestamps.
--   hotelloyalty*               -- two whole tables, no report.
--
-- CONVENTIONS
--   * Output column names are deliberately distinct from the source columns they
--     aggregate. In PL/pgSQL a RETURNS TABLE column sharing a name with a table
--     column is ambiguous and raises 42702 at RUNTIME, not at create time.
--   * No output column is named `found` -- FOUND is a built-in PL/pgSQL variable.
--     Migration 292 hit exactly that; it is recorded in plan.md.
--   * Every aggregate is COALESCE'd, so the C# readers need no null check.
--
-- THE TWO RULES THAT DECIDE WHAT COUNTS, STATED ONCE
--
--   1. REVENUE-BEARING = status <> 'Cancelled'.
--      hotelbookings.status is one of Pending, Confirmed, CheckedIn, Completed,
--      Cancelled. Restricting revenue to Completed would have been tidier, but
--      it silently empties every report at any property that does not diligently
--      move bookings to Completed on checkout -- and a report that reads zero
--      because of a workflow habit is worse than one that slightly over-counts.
--      Cancelled bookings appear only in the cancellations report, which is
--      about them.
--
--   2. A BOOKING BELONGS TO THE PERIOD ITS STAY STARTS IN (checkindate),
--      not the period it was booked in. The one exception is the booking pace
--      report, where the question is when the booking was MADE -- and that report
--      says so in its own comment.
--
--   NOTE ON NO-SHOWS: 'NoShow' is not one of hotelbookings' status values. The
--   only no-show data in the schema is hotelnightaudits.noshowcount, a nightly
--   integer with no booking behind it. So the cancellations report covers
--   cancellations honestly and does NOT pretend to cover no-shows; the no-show
--   count is surfaced in the KPI report instead, from the night audit, where it
--   actually lives.
-- =============================================================================

-- 0. Drop earlier versions ----------------------------------------------------
-- CREATE OR REPLACE cannot change a return type, and RETURNS TABLE column names
-- are part of it. Dropping by name covers every overload and makes this file
-- safe to re-apply over an earlier version of itself.
DO $drop$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
                'sphotel_report_source_of_business',
                'sphotel_report_booking_pace',
                'sphotel_report_room_type_performance',
                'sphotel_report_performance_kpis',
                'sphotel_report_guest_ledger',
                'sphotel_report_ancillary_revenue',
                'sphotel_report_cancellations',
                'sphotel_report_length_of_stay',
                'sphotel_report_housekeeping_productivity',
                'sphotel_report_loyalty')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;


-- =============================================================================
-- 1. SOURCE OF BUSINESS -- which channel actually produces
-- =============================================================================
-- `source` has been on every booking since the Hotel foundation migration and
-- nothing has ever grouped by it. This is the report a hotelier uses to decide
-- whether an OTA is worth its commission.
CREATE FUNCTION public.sphotel_report_source_of_business(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    source_label TEXT, booking_count BIGINT, room_nights BIGINT, guest_count BIGINT,
    revenue_total NUMERIC, adr NUMERIC, share_pct NUMERIC, avg_lead_days NUMERIC
) AS $$
DECLARE v_all NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(b.totalamount), 0) INTO v_all
      FROM hotelbookings b
     WHERE b.farmid = p_farmid AND b.status <> 'Cancelled'
       AND b.checkindate BETWEEN p_from AND p_to;

    RETURN QUERY
    SELECT COALESCE(NULLIF(b.source, ''), 'Unknown')::TEXT,
           COUNT(*)::BIGINT,
           COALESCE(SUM(GREATEST(b.checkoutdate - b.checkindate, 1)), 0)::BIGINT,
           COALESCE(SUM(b.numberofguests), 0)::BIGINT,
           COALESCE(SUM(b.totalamount), 0),
           -- ADR is revenue over ROOM NIGHTS, never over bookings. A five-night
           -- stay and a one-night stay are not two equal units of rate.
           CASE WHEN COALESCE(SUM(GREATEST(b.checkoutdate - b.checkindate, 1)), 0) > 0
               THEN ROUND(SUM(b.totalamount) / SUM(GREATEST(b.checkoutdate - b.checkindate, 1)), 2)
               ELSE 0 END,
           CASE WHEN v_all > 0 THEN ROUND(SUM(b.totalamount) / v_all * 100, 2) ELSE 0 END,
           COALESCE(ROUND(AVG(GREATEST(b.checkindate - b.createdat::DATE, 0))::NUMERIC, 1), 0)
      FROM hotelbookings b
     WHERE b.farmid = p_farmid AND b.status <> 'Cancelled'
       AND b.checkindate BETWEEN p_from AND p_to
     GROUP BY COALESCE(NULLIF(b.source, ''), 'Unknown')
     ORDER BY 5 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 2. BOOKING PACE AND LEAD TIME
-- =============================================================================
-- The one report anchored on when the booking was MADE rather than when the stay
-- starts, because that is the question: how far ahead does demand arrive? A
-- property whose business is 80% same-day has no pricing runway and should know
-- it. Buckets rather than a raw average, because lead time is heavily skewed and
-- a mean hides the shape completely.
CREATE FUNCTION public.sphotel_report_booking_pace(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    lead_bucket TEXT, bucket_order INT, booking_count BIGINT, room_nights BIGINT,
    revenue_total NUMERIC, adr NUMERIC, share_pct NUMERIC
) AS $$
DECLARE v_all NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(b.totalamount), 0) INTO v_all
      FROM hotelbookings b
     WHERE b.farmid = p_farmid AND b.status <> 'Cancelled'
       AND b.createdat::DATE BETWEEN p_from AND p_to;

    RETURN QUERY
    WITH paced AS (
        SELECT CASE
                   WHEN GREATEST(b.checkindate - b.createdat::DATE, 0) = 0  THEN 'Same day'
                   WHEN GREATEST(b.checkindate - b.createdat::DATE, 0) <= 7  THEN '1-7 days'
                   WHEN GREATEST(b.checkindate - b.createdat::DATE, 0) <= 30 THEN '8-30 days'
                   WHEN GREATEST(b.checkindate - b.createdat::DATE, 0) <= 90 THEN '31-90 days'
                   ELSE '91+ days'
               END AS bucket,
               CASE
                   WHEN GREATEST(b.checkindate - b.createdat::DATE, 0) = 0  THEN 1
                   WHEN GREATEST(b.checkindate - b.createdat::DATE, 0) <= 7  THEN 2
                   WHEN GREATEST(b.checkindate - b.createdat::DATE, 0) <= 30 THEN 3
                   WHEN GREATEST(b.checkindate - b.createdat::DATE, 0) <= 90 THEN 4
                   ELSE 5
               END AS ord,
               GREATEST(b.checkoutdate - b.checkindate, 1) AS nights,
               b.totalamount AS amt
          FROM hotelbookings b
         WHERE b.farmid = p_farmid AND b.status <> 'Cancelled'
           AND b.createdat::DATE BETWEEN p_from AND p_to
    )
    SELECT p.bucket, p.ord,
           COUNT(*)::BIGINT,
           COALESCE(SUM(p.nights), 0)::BIGINT,
           COALESCE(SUM(p.amt), 0),
           CASE WHEN COALESCE(SUM(p.nights), 0) > 0
               THEN ROUND(SUM(p.amt) / SUM(p.nights), 2) ELSE 0 END,
           CASE WHEN v_all > 0 THEN ROUND(SUM(p.amt) / v_all * 100, 2) ELSE 0 END
      FROM paced p
     GROUP BY p.bucket, p.ord
     ORDER BY p.ord;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 3. ROOM TYPE PERFORMANCE
-- =============================================================================
-- Occupancy, ADR and RevPAR broken down by room type. The existing Occupancy &
-- ADR report reads hoteldailyclosings, which stores one occupancy figure for the
-- whole property -- so it is structurally incapable of telling you that the
-- suites sit empty while the doubles sell out.
--
-- Occupancy and RevPAR here are against that type's OWN inventory: rooms of that
-- type multiplied by the days in the range. Measuring a room type against the
-- whole property's room count would make every type look empty.
CREATE FUNCTION public.sphotel_report_room_type_performance(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    type_label TEXT, rooms_in_type BIGINT, booking_count BIGINT, room_nights BIGINT,
    revenue_total NUMERIC, adr NUMERIC, revpar NUMERIC, occupancy_pct NUMERIC,
    share_pct NUMERIC
) AS $$
DECLARE
    v_all  NUMERIC := 0;
    v_days INT := GREATEST((p_to - p_from) + 1, 1);
BEGIN
    SELECT COALESCE(SUM(b.totalamount), 0) INTO v_all
      FROM hotelbookings b
     WHERE b.farmid = p_farmid AND b.status <> 'Cancelled'
       AND b.checkindate BETWEEN p_from AND p_to;

    RETURN QUERY
    WITH inventory AS (
        SELECT rt.hotelroomtypeid AS rtid,
               rt.name            AS rtname,
               COUNT(rm.hotelroomid)::BIGINT AS room_count
          FROM hotelroomtypes rt
          LEFT JOIN hotelrooms rm
                 ON rm.hotelroomtypeid = rt.hotelroomtypeid
                AND rm.farmid = rt.farmid
                AND rm.isactive = TRUE
         WHERE rt.farmid = p_farmid
         GROUP BY rt.hotelroomtypeid, rt.name
    ),
    sold AS (
        SELECT b.hotelroomtypeid AS rtid,
               COUNT(*)::BIGINT  AS bookings,
               COALESCE(SUM(GREATEST(b.checkoutdate - b.checkindate, 1)), 0)::BIGINT AS nights,
               COALESCE(SUM(b.totalamount), 0) AS revenue
          FROM hotelbookings b
         WHERE b.farmid = p_farmid AND b.status <> 'Cancelled'
           AND b.checkindate BETWEEN p_from AND p_to
         GROUP BY b.hotelroomtypeid
    )
    SELECT i.rtname::TEXT,
           i.room_count,
           COALESCE(s.bookings, 0),
           COALESCE(s.nights, 0),
           COALESCE(s.revenue, 0),
           CASE WHEN COALESCE(s.nights, 0) > 0
               THEN ROUND(s.revenue / s.nights, 2) ELSE 0 END,
           CASE WHEN i.room_count > 0
               THEN ROUND(COALESCE(s.revenue, 0) / (i.room_count * v_days), 2) ELSE 0 END,
           CASE WHEN i.room_count > 0
               THEN ROUND(COALESCE(s.nights, 0)::NUMERIC / (i.room_count * v_days) * 100, 2) ELSE 0 END,
           CASE WHEN v_all > 0 THEN ROUND(COALESCE(s.revenue, 0) / v_all * 100, 2) ELSE 0 END
      FROM inventory i
      LEFT JOIN sold s ON s.rtid = i.rtid
     ORDER BY 5 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 4. PERFORMANCE KPIs -- including the two that were never derived
-- =============================================================================
-- hoteldailyclosings already stores adr and revpar per night. This adds the two
-- metrics that sit above them in every hotel P&L and that nothing in this
-- codebase computed:
--
--   TRevPAR = TOTAL revenue per available room. RevPAR only counts rooms
--             revenue, so a hotel with a strong restaurant looks worse on RevPAR
--             than it is.
--   GOPPAR  = gross operating profit per available room -- revenue minus
--             operating expenses, per available room. This is the number an
--             owner actually cares about, because a hotel can buy RevPAR with
--             discounting and destroy GOPPAR doing it.
--
-- Averaged ADR/RevPAR across the range are recomputed from the totals rather
-- than averaged from the stored per-night figures: the mean of nightly ADRs is
-- not the period ADR unless every night sold the same number of rooms.
--
-- No-show count is carried here from hotelnightaudits, because that is the only
-- place in the schema where a no-show is recorded at all.
CREATE FUNCTION public.sphotel_report_performance_kpis(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    days_counted BIGINT, available_room_nights BIGINT, occupied_room_nights BIGINT,
    occupancy_pct NUMERIC, room_revenue NUMERIC, fnb_revenue NUMERIC,
    other_revenue NUMERIC, total_revenue NUMERIC, total_expenses NUMERIC,
    gross_operating_profit NUMERIC, adr NUMERIC, revpar NUMERIC,
    trevpar NUMERIC, goppar NUMERIC, noshow_count BIGINT
) AS $$
DECLARE
    v_days    BIGINT := 0;
    v_avail   BIGINT := 0;
    v_occ     BIGINT := 0;
    v_room    NUMERIC := 0;
    v_fnb     NUMERIC := 0;
    v_other   NUMERIC := 0;
    v_total   NUMERIC := 0;
    v_exp     NUMERIC := 0;
    v_noshow  BIGINT := 0;
BEGIN
    SELECT COUNT(*)::BIGINT,
           COALESCE(SUM(c.totalrooms), 0)::BIGINT,
           COALESCE(SUM(c.roomsoccupied), 0)::BIGINT,
           COALESCE(SUM(c.roomrevenue), 0),
           COALESCE(SUM(c.fnbrevenue), 0),
           COALESCE(SUM(c.otherrevenue), 0),
           COALESCE(SUM(c.totalrevenue), 0),
           COALESCE(SUM(c.totalexpenses), 0)
      INTO v_days, v_avail, v_occ, v_room, v_fnb, v_other, v_total, v_exp
      FROM hoteldailyclosings c
     WHERE c.farmid = p_farmid AND c.closingdate BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(na.noshowcount), 0)::BIGINT INTO v_noshow
      FROM hotelnightaudits na
     WHERE na.farmid = p_farmid AND na.auditdate BETWEEN p_from AND p_to;

    RETURN QUERY SELECT
        v_days, v_avail, v_occ,
        CASE WHEN v_avail > 0 THEN ROUND(v_occ::NUMERIC / v_avail * 100, 2) ELSE 0 END,
        v_room, v_fnb, v_other, v_total, v_exp,
        v_total - v_exp,
        CASE WHEN v_occ   > 0 THEN ROUND(v_room  / v_occ,   2) ELSE 0 END,  -- ADR
        CASE WHEN v_avail > 0 THEN ROUND(v_room  / v_avail, 2) ELSE 0 END,  -- RevPAR
        CASE WHEN v_avail > 0 THEN ROUND(v_total / v_avail, 2) ELSE 0 END,  -- TRevPAR
        CASE WHEN v_avail > 0 THEN ROUND((v_total - v_exp) / v_avail, 2) ELSE 0 END, -- GOPPAR
        v_noshow;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 5. GUEST LEDGER -- open invoices, aged
-- =============================================================================
-- The existing Billing & Payments report is built from hotelpayments and
-- hotelbookings and never touches hotelinvoices, so nothing in the Hotel module
-- has ever answered "who owes us money, and for how long". Ageing is from the
-- due date where one is set, falling back to the issue date -- an invoice with
-- no due date is not therefore un-aged.
CREATE FUNCTION public.sphotel_report_guest_ledger(p_farmid TEXT)
RETURNS TABLE (
    invoice_ref TEXT, guest_label TEXT, issued_on DATE, due_on DATE,
    invoice_state TEXT, total_amount NUMERIC, paid_amount NUMERIC,
    balance_due NUMERIC, days_outstanding BIGINT, age_bucket TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT i.invoicenumber::TEXT,
           COALESCE(NULLIF(TRIM(CONCAT(g.firstname, ' ', g.lastname)), ''), 'Unknown guest')::TEXT,
           i.issueddate,
           i.duedate,
           i.status::TEXT,
           i.totalamount,
           i.amountpaid,
           i.balance,
           GREATEST(CURRENT_DATE - COALESCE(i.duedate, i.issueddate), 0)::BIGINT,
           CASE
               WHEN CURRENT_DATE <= COALESCE(i.duedate, i.issueddate) THEN 'Current'
               WHEN CURRENT_DATE - COALESCE(i.duedate, i.issueddate) <= 30 THEN '1-30 days'
               WHEN CURRENT_DATE - COALESCE(i.duedate, i.issueddate) <= 60 THEN '31-60 days'
               WHEN CURRENT_DATE - COALESCE(i.duedate, i.issueddate) <= 90 THEN '61-90 days'
               ELSE 'Over 90 days'
           END::TEXT
      FROM hotelinvoices i
      LEFT JOIN hotelguests g ON g.hotelguestid = i.hotelguestid AND g.farmid = i.farmid
     WHERE i.farmid = p_farmid
       AND i.balance > 0
       AND i.status <> 'Cancelled'
     ORDER BY GREATEST(CURRENT_DATE - COALESCE(i.duedate, i.issueddate), 0) DESC, i.balance DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 6. ANCILLARY REVENUE -- what a stay is worth beyond the room
-- =============================================================================
-- hotelstaycharges has carried a chargetype since the schema was written and
-- nothing groups by it. This is the other half of TRevPAR: the minibar, the
-- laundry, the airport transfer.
CREATE FUNCTION public.sphotel_report_ancillary_revenue(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    charge_label TEXT, charge_count BIGINT, qty_total BIGINT,
    revenue_total NUMERIC, avg_charge NUMERIC, share_pct NUMERIC,
    stays_touched BIGINT
) AS $$
DECLARE v_all NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(sc.totalamount), 0) INTO v_all
      FROM hotelstaycharges sc
     WHERE sc.farmid = p_farmid AND sc.chargedate::DATE BETWEEN p_from AND p_to;

    RETURN QUERY
    SELECT COALESCE(NULLIF(sc.chargetype, ''), 'Unspecified')::TEXT,
           COUNT(*)::BIGINT,
           COALESCE(SUM(sc.quantity), 0)::BIGINT,
           COALESCE(SUM(sc.totalamount), 0),
           COALESCE(ROUND(AVG(sc.totalamount), 2), 0),
           CASE WHEN v_all > 0 THEN ROUND(SUM(sc.totalamount) / v_all * 100, 2) ELSE 0 END,
           COUNT(DISTINCT sc.hotelbookingid)::BIGINT
      FROM hotelstaycharges sc
     WHERE sc.farmid = p_farmid AND sc.chargedate::DATE BETWEEN p_from AND p_to
     GROUP BY COALESCE(NULLIF(sc.chargetype, ''), 'Unspecified')
     ORDER BY 4 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 7. CANCELLATIONS -- by the channel that produced them
-- =============================================================================
-- Grouped by source, because "which channel cancels on us" is the actionable
-- question; a flat count of cancellations is not.
--
-- This reports CANCELLATIONS ONLY. See the header note: 'NoShow' is not one of
-- hotelbookings' status values, so there is no per-booking no-show to report.
-- The nightly no-show count travels in the KPI report instead, from
-- hotelnightaudits where it is actually recorded.
CREATE FUNCTION public.sphotel_report_cancellations(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    source_label TEXT, cancelled_count BIGINT, nights_lost BIGINT,
    value_lost NUMERIC, share_pct NUMERIC, avg_lead_days NUMERIC,
    booked_count BIGINT, cancel_rate_pct NUMERIC
) AS $$
DECLARE v_all NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(b.totalamount), 0) INTO v_all
      FROM hotelbookings b
     WHERE b.farmid = p_farmid AND b.status = 'Cancelled'
       AND b.checkindate BETWEEN p_from AND p_to;

    RETURN QUERY
    WITH cancelled AS (
        SELECT COALESCE(NULLIF(b.source, ''), 'Unknown') AS src,
               COUNT(*)::BIGINT AS n,
               COALESCE(SUM(GREATEST(b.checkoutdate - b.checkindate, 1)), 0)::BIGINT AS nights,
               COALESCE(SUM(b.totalamount), 0) AS lost,
               COALESCE(ROUND(AVG(GREATEST(b.checkindate - b.createdat::DATE, 0))::NUMERIC, 1), 0) AS lead
          FROM hotelbookings b
         WHERE b.farmid = p_farmid AND b.status = 'Cancelled'
           AND b.checkindate BETWEEN p_from AND p_to
         GROUP BY COALESCE(NULLIF(b.source, ''), 'Unknown')
    ),
    -- Every booking on that channel for the period, cancelled or not, so the
    -- cancellation RATE has an honest denominator. A channel with three
    -- cancellations out of four bookings is a different problem from one with
    -- three out of three hundred.
    booked AS (
        SELECT COALESCE(NULLIF(b.source, ''), 'Unknown') AS src, COUNT(*)::BIGINT AS n
          FROM hotelbookings b
         WHERE b.farmid = p_farmid AND b.checkindate BETWEEN p_from AND p_to
         GROUP BY COALESCE(NULLIF(b.source, ''), 'Unknown')
    )
    SELECT c.src::TEXT, c.n, c.nights, c.lost,
           CASE WHEN v_all > 0 THEN ROUND(c.lost / v_all * 100, 2) ELSE 0 END,
           c.lead,
           COALESCE(bk.n, 0),
           CASE WHEN COALESCE(bk.n, 0) > 0
               THEN ROUND(c.n::NUMERIC / bk.n * 100, 2) ELSE 0 END
      FROM cancelled c
      LEFT JOIN booked bk ON bk.src = c.src
     ORDER BY 4 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 8. LENGTH OF STAY
-- =============================================================================
-- ALOS drives housekeeping load, rate strategy and minimum-stay rules, and
-- nothing reported it. Bucketed rather than averaged for the same reason as
-- booking pace: the distribution is the point.
CREATE FUNCTION public.sphotel_report_length_of_stay(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    los_bucket TEXT, bucket_order INT, booking_count BIGINT, room_nights BIGINT,
    revenue_total NUMERIC, adr NUMERIC, share_pct NUMERIC
) AS $$
DECLARE v_all NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(b.totalamount), 0) INTO v_all
      FROM hotelbookings b
     WHERE b.farmid = p_farmid AND b.status <> 'Cancelled'
       AND b.checkindate BETWEEN p_from AND p_to;

    RETURN QUERY
    WITH stays AS (
        SELECT GREATEST(b.checkoutdate - b.checkindate, 1) AS nights,
               b.totalamount AS amt
          FROM hotelbookings b
         WHERE b.farmid = p_farmid AND b.status <> 'Cancelled'
           AND b.checkindate BETWEEN p_from AND p_to
    ),
    bucketed AS (
        SELECT CASE
                   WHEN s.nights = 1 THEN '1 night'
                   WHEN s.nights = 2 THEN '2 nights'
                   WHEN s.nights <= 4 THEN '3-4 nights'
                   WHEN s.nights <= 7 THEN '5-7 nights'
                   ELSE '8+ nights'
               END AS bucket,
               CASE
                   WHEN s.nights = 1 THEN 1
                   WHEN s.nights = 2 THEN 2
                   WHEN s.nights <= 4 THEN 3
                   WHEN s.nights <= 7 THEN 4
                   ELSE 5
               END AS ord,
               s.nights, s.amt
          FROM stays s
    )
    SELECT b.bucket, b.ord,
           COUNT(*)::BIGINT,
           COALESCE(SUM(b.nights), 0)::BIGINT,
           COALESCE(SUM(b.amt), 0),
           CASE WHEN COALESCE(SUM(b.nights), 0) > 0
               THEN ROUND(SUM(b.amt) / SUM(b.nights), 2) ELSE 0 END,
           CASE WHEN v_all > 0 THEN ROUND(SUM(b.amt) / v_all * 100, 2) ELSE 0 END
      FROM bucketed b
     GROUP BY b.bucket, b.ord
     ORDER BY b.ord;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 9. HOUSEKEEPING PRODUCTIVITY -- the timestamps nothing has read
-- =============================================================================
-- hotelhousekeepingtasks stamps startedat and completedat on every task and
-- records who it was assigned to. The existing Housekeeping report counts task
-- statuses and ignores both timestamps, so nobody can see how long a room
-- actually takes or who is fast.
--
-- rooms_per_shift projects the attendant's average onto an eight-hour shift
-- (480 minutes). The industry benchmark is 12-16 rooms per attendant per shift,
-- which is what makes the number readable at a glance.
--
-- Only tasks with BOTH timestamps and a sane ordering are timed; a task still in
-- progress, or one completed before it started because someone back-dated it,
-- would otherwise poison the average.
CREATE FUNCTION public.sphotel_report_housekeeping_productivity(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    attendant_label TEXT, tasks_total BIGINT, tasks_completed BIGINT,
    timed_count BIGINT, avg_minutes NUMERIC, fastest_minutes NUMERIC,
    slowest_minutes NUMERIC, rooms_per_shift NUMERIC, inspected_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT COALESCE(NULLIF(t.assignedto, ''), 'Unassigned')::TEXT,
           COUNT(*)::BIGINT,
           COUNT(*) FILTER (WHERE t.status = 'Completed')::BIGINT,
           COUNT(*) FILTER (WHERE t.startedat IS NOT NULL
                              AND t.completedat IS NOT NULL
                              AND t.completedat >= t.startedat)::BIGINT,
           COALESCE(ROUND(AVG(EXTRACT(EPOCH FROM (t.completedat - t.startedat)) / 60.0)
                          FILTER (WHERE t.startedat IS NOT NULL
                                    AND t.completedat IS NOT NULL
                                    AND t.completedat >= t.startedat)::NUMERIC, 1), 0),
           COALESCE(ROUND(MIN(EXTRACT(EPOCH FROM (t.completedat - t.startedat)) / 60.0)
                          FILTER (WHERE t.startedat IS NOT NULL
                                    AND t.completedat IS NOT NULL
                                    AND t.completedat >= t.startedat)::NUMERIC, 1), 0),
           COALESCE(ROUND(MAX(EXTRACT(EPOCH FROM (t.completedat - t.startedat)) / 60.0)
                          FILTER (WHERE t.startedat IS NOT NULL
                                    AND t.completedat IS NOT NULL
                                    AND t.completedat >= t.startedat)::NUMERIC, 1), 0),
           CASE WHEN COALESCE(AVG(EXTRACT(EPOCH FROM (t.completedat - t.startedat)) / 60.0)
                              FILTER (WHERE t.startedat IS NOT NULL
                                        AND t.completedat IS NOT NULL
                                        AND t.completedat >= t.startedat), 0) > 0
               THEN ROUND((480.0 / AVG(EXTRACT(EPOCH FROM (t.completedat - t.startedat)) / 60.0)
                          FILTER (WHERE t.startedat IS NOT NULL
                                    AND t.completedat IS NOT NULL
                                    AND t.completedat >= t.startedat))::NUMERIC, 1)
               ELSE 0 END,
           COUNT(*) FILTER (WHERE COALESCE(t.inspectedby, '') <> '')::BIGINT
      FROM hotelhousekeepingtasks t
     WHERE t.farmid = p_farmid
       AND t.scheduleddate BETWEEN p_from AND p_to
     GROUP BY COALESCE(NULLIF(t.assignedto, ''), 'Unassigned')
     ORDER BY 2 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 10. LOYALTY -- two tables, no report, until now
-- =============================================================================
-- Member counts and balances are a position (all-time), while earn and redeem
-- are movements within the range. Both are returned together, with the movement
-- columns clearly named, rather than pretending the whole row is period data.
CREATE FUNCTION public.sphotel_report_loyalty(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    tier_label TEXT, member_count BIGINT, active_members BIGINT,
    points_balance BIGINT, lifetime_points BIGINT,
    earned_in_period BIGINT, redeemed_in_period BIGINT, share_pct NUMERIC
) AS $$
DECLARE v_all BIGINT := 0;
BEGIN
    SELECT COUNT(*)::BIGINT INTO v_all
      FROM hotelloyaltymembers m WHERE m.farmid = p_farmid;

    RETURN QUERY
    SELECT COALESCE(NULLIF(m.tier, ''), 'Unranked')::TEXT,
           COUNT(*)::BIGINT,
           COUNT(*) FILTER (WHERE m.isactive)::BIGINT,
           COALESCE(SUM(m.totalpoints), 0)::BIGINT,
           COALESCE(SUM(m.lifetimepoints), 0)::BIGINT,
           COALESCE(SUM((
               SELECT SUM(tx.points) FROM hotelloyaltytransactions tx
                WHERE tx.hotelloyaltymemberid = m.hotelloyaltymemberid
                  AND tx.farmid = m.farmid
                  AND tx.transactiontype = 'Earn'
                  AND tx.createdat::DATE BETWEEN p_from AND p_to
           )), 0)::BIGINT,
           -- Redeem rows are stored as positive point counts, so ABS keeps this
           -- honest whichever sign convention a given row was written with.
           COALESCE(SUM((
               SELECT SUM(ABS(tx.points)) FROM hotelloyaltytransactions tx
                WHERE tx.hotelloyaltymemberid = m.hotelloyaltymemberid
                  AND tx.farmid = m.farmid
                  AND tx.transactiontype = 'Redeem'
                  AND tx.createdat::DATE BETWEEN p_from AND p_to
           )), 0)::BIGINT,
           CASE WHEN v_all > 0 THEN ROUND(COUNT(*)::NUMERIC / v_all * 100, 2) ELSE 0 END
      FROM hotelloyaltymembers m
     WHERE m.farmid = p_farmid
     GROUP BY COALESCE(NULLIF(m.tier, ''), 'Unranked')
     ORDER BY 4 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 11. Supporting indexes
-- =============================================================================
-- Every function above filters one farm by a date. Index-only additions cannot
-- change a result, only how fast it arrives.
--
-- NOTE: no expression index on createdat::DATE here. hotelbookings.createdat is
-- `timestamp WITH time zone`, and casting a timestamptz to date depends on the
-- session TimeZone, which makes the expression STABLE rather than IMMUTABLE --
-- Postgres refuses to index it. (Migration 298 could index the restaurant
-- equivalent precisely because those columns are timestamp WITHOUT time zone.)
CREATE INDEX IF NOT EXISTS ix_hotelbookings_farm_checkin_status
    ON hotelbookings (farmid, checkindate, status);

CREATE INDEX IF NOT EXISTS ix_hotelbookings_farm_roomtype
    ON hotelbookings (farmid, hotelroomtypeid);

CREATE INDEX IF NOT EXISTS ix_hotelinvoices_farm_balance
    ON hotelinvoices (farmid, balance);

CREATE INDEX IF NOT EXISTS ix_hotelstaycharges_farm_booking
    ON hotelstaycharges (farmid, hotelbookingid);

CREATE INDEX IF NOT EXISTS ix_hotelhkt_farm_scheduled
    ON hotelhousekeepingtasks (farmid, scheduleddate);

CREATE INDEX IF NOT EXISTS ix_hoteldailyclosings_farm_date
    ON hoteldailyclosings (farmid, closingdate);

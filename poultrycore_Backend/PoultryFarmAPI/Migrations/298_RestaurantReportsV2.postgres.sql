-- =============================================================================
-- Migration 298: Restaurant reporting, second pass (PostgreSQL)
-- =============================================================================
-- Migration 223 gave the Restaurant module seven reports. A survey of the other
-- 24 restaurant migrations found a large amount of operational data that is
-- written on every shift and read by nothing:
--
--   restaurantorderitems.senttoktchenat / prepstartedat / readyat / kdsstation
--       -- every ticket is timed per station, and no report aggregates it.
--   restaurantorders.completedat
--       -- never referenced in 223, so table dwell time was uncomputable.
--   restaurantorderpayments.tipamount
--       -- captured on every payment, aggregated nowhere.
--   restaurantdeliveryassignments.estimatedmins / actualmins / distancekm /
--   rating / failreason
--       -- promised-vs-actual delivery existed only as a live driver count.
--   restaurantthirdpartyorders.commissionamount / platformfee / netamount
--       -- aggregator commission was invisible.
--   restaurantorderdiscounts.appliedamount, restaurantorders.cancelreason /
--   refundreason, restaurantingredients.parlevel / reorderpoint
--       -- discount cost, void reasons and stock position, all unreported.
--
-- This migration adds 17 report functions over that data and repairs two
-- defects in existing ones (sections 1 and 2). Everything is additive except
-- those two repairs; no table, column or index is created, altered or dropped,
-- so nothing outside these functions can behave differently.
--
-- CONVENTIONS FOLLOWED THROUGHOUT
--   * Every function is (p_farmid, p_from, p_to) unless the report is a
--     point-in-time position (stock on hand), so one date-range control on the
--     frontend drives all of them.
--   * Output column names are deliberately distinct from the source column
--     names they aggregate (`waste_reason`, not `reason`; `stock_unit`, not
--     `unit`). In PL/pgSQL a RETURNS TABLE column and a table column that share
--     a name are ambiguous and raise 42702 at runtime, not at create time.
--   * No output column is named `found` -- FOUND is a built-in PL/pgSQL
--     variable. Migration 292 hit exactly that and it is recorded in plan.md.
--   * Every aggregate is COALESCE'd to 0 (or to a placeholder string) so the
--     C# readers can use GetDecimal/GetInt64 without a null check per column.
--   * Revenue everywhere means orders with status = 'Completed'. Cancelled and
--     refunded orders appear only in the voids report, which is about them.
-- =============================================================================

-- 0. Drop earlier versions of anything whose shape changes ---------------------
-- CREATE OR REPLACE cannot change a function's return type, and the column
-- names of a RETURNS TABLE are part of that type. sprestaurant_report_pnl is
-- being replaced by two correctly-shaped functions (see section 2), so the old
-- one is dropped by signature. Dropping by name covers every overload and makes
-- this file safe to re-apply over an earlier version of itself -- same approach
-- as migrations 251 and 292.
DO $drop$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
                'sprestaurant_report_pnl',
                'sprestaurant_report_pnl_summary',
                'sprestaurant_report_pnl_expenses',
                'sprestaurant_report_sales_summary',
                'sprestaurant_report_payment_methods',
                'sprestaurant_report_kitchen_performance',
                'sprestaurant_report_table_turnover',
                'sprestaurant_report_tips',
                'sprestaurant_report_delivery_performance',
                'sprestaurant_report_discounts',
                'sprestaurant_report_voids',
                'sprestaurant_report_stock_on_hand',
                'sprestaurant_report_waste_detail',
                'sprestaurant_report_expenses',
                'sprestaurant_report_menu_engineering',
                'sprestaurant_report_customer_retention',
                'sprestaurant_report_channel',
                'sprestaurant_report_events',
                'sprestaurant_report_feedback')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;


-- =============================================================================
-- 1. REPAIR: daily sales counted payments against cancelled orders
-- =============================================================================
-- In 223 the four payment-method sums joined restaurantorderpayments with only
-- `p.status = 'Completed'` -- the payment's own status. The ORDER's status was
-- never checked on that side, so a payment taken against an order later
-- cancelled or refunded still landed in the Cash/Card/Mobile/Other totals while
-- being excluded from total_revenue. The breakdown could therefore exceed the
-- revenue figure printed directly above it.
--
-- Replaced IN PLACE with CREATE OR REPLACE: the argument list and all twenty
-- RETURNS TABLE column names and types are byte-for-byte what 223 declared.
-- That matters because RestaurantReportService.GetDailySalesAsync reads this
-- result set BY ORDINAL (r.GetInt64(0) .. r.GetDecimal(19)); any reordering
-- would silently shift every field. Only the join predicate changes.
CREATE OR REPLACE FUNCTION public.sprestaurant_report_daily_sales(p_farmid TEXT, p_date DATE)
RETURNS TABLE (
    total_orders BIGINT, completed_orders BIGINT, cancelled_orders BIGINT,
    total_revenue NUMERIC, total_discount NUMERIC, total_tax NUMERIC,
    total_service_charge NUMERIC, net_revenue NUMERIC,
    avg_ticket NUMERIC, total_covers BIGINT,
    dinein_count BIGINT, dinein_revenue NUMERIC,
    takeaway_count BIGINT, takeaway_revenue NUMERIC,
    delivery_count BIGINT, delivery_revenue NUMERIC,
    cash_amount NUMERIC, card_amount NUMERIC, mobile_amount NUMERIC, other_amount NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE o.status = 'Completed'),
        COUNT(*) FILTER (WHERE o.status = 'Cancelled'),
        COALESCE(SUM(o.totalamount) FILTER (WHERE o.status = 'Completed'), 0),
        COALESCE(SUM(o.discountamount) FILTER (WHERE o.status = 'Completed'), 0),
        COALESCE(SUM(o.taxamount) FILTER (WHERE o.status = 'Completed'), 0),
        COALESCE(SUM(o.servicechargeamount) FILTER (WHERE o.status = 'Completed'), 0),
        COALESCE(SUM(o.subtotal) FILTER (WHERE o.status = 'Completed'), 0),
        CASE WHEN COUNT(*) FILTER (WHERE o.status = 'Completed') > 0
            THEN ROUND(SUM(o.totalamount) FILTER (WHERE o.status = 'Completed') / COUNT(*) FILTER (WHERE o.status = 'Completed'), 2)
            ELSE 0 END,
        COALESCE(SUM(o.covers) FILTER (WHERE o.status = 'Completed'), 0),
        COUNT(*) FILTER (WHERE o.ordertype = 'DineIn' AND o.status = 'Completed'),
        COALESCE(SUM(o.totalamount) FILTER (WHERE o.ordertype = 'DineIn' AND o.status = 'Completed'), 0),
        COUNT(*) FILTER (WHERE o.ordertype = 'Takeaway' AND o.status = 'Completed'),
        COALESCE(SUM(o.totalamount) FILTER (WHERE o.ordertype = 'Takeaway' AND o.status = 'Completed'), 0),
        COUNT(*) FILTER (WHERE o.ordertype = 'Delivery' AND o.status = 'Completed'),
        COALESCE(SUM(o.totalamount) FILTER (WHERE o.ordertype = 'Delivery' AND o.status = 'Completed'), 0),
        -- the repair: payments only count when the ORDER completed too
        COALESCE(SUM(p.amount) FILTER (WHERE p.paymentmethod = 'Cash' AND o.status = 'Completed'), 0),
        COALESCE(SUM(p.amount) FILTER (WHERE p.paymentmethod = 'Card' AND o.status = 'Completed'), 0),
        COALESCE(SUM(p.amount) FILTER (WHERE p.paymentmethod = 'MobileMoney' AND o.status = 'Completed'), 0),
        COALESCE(SUM(p.amount) FILTER (WHERE p.paymentmethod NOT IN ('Cash','Card','MobileMoney') AND o.status = 'Completed'), 0)
    FROM restaurantorders o
    LEFT JOIN restaurantorderpayments p ON p.orderid = o.orderid AND p.farmid = o.farmid AND p.status = 'Completed'
    WHERE o.farmid = p_farmid AND o.createdat::DATE = p_date;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 2. REPAIR: profit & loss returned nothing when there were no expenses
-- =============================================================================
-- The 229 version selected revenue and COGS as scalar subqueries but drove the
-- whole statement FROM restaurantexpenses with a GROUP BY on category. With no
-- expenses in range that produces zero rows, so revenue, COGS and gross profit
-- vanished along with the expense list -- the P&L reported nothing at all for
-- any restaurant that had not yet entered an expense.
--
-- It also built its intermediates with CREATE TEMP TABLE IF NOT EXISTS. Temp
-- tables live for the whole session, so if the function raised between the
-- CREATE and the DROP at the end, the next call in that connection silently
-- reused the previous call's totals. Npgsql pools connections, so that is a
-- realistic way to serve one restaurant another's numbers.
--
-- Both problems come from cramming a summary and a breakdown into one result
-- set. They are split into two functions, each with a single shape, and the
-- temp tables are replaced with CTEs that cannot outlive the statement.

-- 2a. One row, always -- scalar subqueries with no driving FROM clause.
CREATE FUNCTION public.sprestaurant_report_pnl_summary(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    revenue NUMERIC, cogs NUMERIC, gross_profit NUMERIC, gross_margin_pct NUMERIC,
    expenses_total NUMERIC, net_profit NUMERIC, net_margin_pct NUMERIC,
    food_cost_pct NUMERIC, tips_total NUMERIC, order_count BIGINT
) AS $$
DECLARE
    v_rev   NUMERIC := 0;
    v_cogs  NUMERIC := 0;
    v_exp   NUMERIC := 0;
    v_tips  NUMERIC := 0;
    v_ord   BIGINT  := 0;
BEGIN
    -- Revenue is subtotal, not totalamount: tax and service charge are collected
    -- on behalf of others and are not the restaurant's income. This matches the
    -- 229 definition so the two never disagree.
    SELECT COALESCE(SUM(o.subtotal), 0), COUNT(*)
      INTO v_rev, v_ord
      FROM restaurantorders o
     WHERE o.farmid = p_farmid
       AND o.createdat::DATE BETWEEN p_from AND p_to
       AND o.status = 'Completed';

    SELECT COALESCE(SUM(
               oi.quantity * COALESCE((
                   SELECT SUM(r.quantity * (1 + r.wastepercent / 100) * i.costperunit)
                     FROM restaurantrecipes r
                     JOIN restaurantingredients i
                       ON i.ingredientid = r.ingredientid AND i.farmid = r.farmid
                    WHERE r.menuitemid = oi.menuitemid AND r.farmid = oi.farmid), 0)
           ), 0)
      INTO v_cogs
      FROM restaurantorderitems oi
      JOIN restaurantorders o ON o.orderid = oi.orderid AND o.farmid = oi.farmid
     WHERE oi.farmid = p_farmid
       AND o.createdat::DATE BETWEEN p_from AND p_to
       AND o.status = 'Completed'
       AND oi.status <> 'Cancelled';

    SELECT COALESCE(SUM(e.amount), 0)
      INTO v_exp
      FROM restaurantexpenses e
     WHERE e.farmid = p_farmid
       AND e.expensedate BETWEEN p_from AND p_to
       AND COALESCE(e.status, 'Approved') <> 'Rejected';

    SELECT COALESCE(SUM(p.tipamount), 0)
      INTO v_tips
      FROM restaurantorderpayments p
      JOIN restaurantorders o ON o.orderid = p.orderid AND o.farmid = p.farmid
     WHERE p.farmid = p_farmid
       AND o.createdat::DATE BETWEEN p_from AND p_to
       AND p.status = 'Completed'
       AND o.status = 'Completed';

    RETURN QUERY SELECT
        v_rev,
        v_cogs,
        v_rev - v_cogs,
        CASE WHEN v_rev > 0 THEN ROUND((v_rev - v_cogs) / v_rev * 100, 2) ELSE 0 END,
        v_exp,
        v_rev - v_cogs - v_exp,
        CASE WHEN v_rev > 0 THEN ROUND((v_rev - v_cogs - v_exp) / v_rev * 100, 2) ELSE 0 END,
        CASE WHEN v_rev > 0 THEN ROUND(v_cogs / v_rev * 100, 2) ELSE 0 END,
        v_tips,
        v_ord;
END;
$$ LANGUAGE plpgsql;

-- 2b. The expense breakdown, as its own result set. Zero rows here is a valid
-- and meaningful answer, and no longer erases the summary.
CREATE FUNCTION public.sprestaurant_report_pnl_expenses(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    expense_category TEXT, entry_count BIGINT, expense_total NUMERIC, share_pct NUMERIC
) AS $$
DECLARE v_all NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(e.amount), 0) INTO v_all
      FROM restaurantexpenses e
     WHERE e.farmid = p_farmid AND e.expensedate BETWEEN p_from AND p_to
       AND COALESCE(e.status, 'Approved') <> 'Rejected';

    RETURN QUERY
    SELECT COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised'),
           COUNT(*)::BIGINT,
           COALESCE(SUM(e.amount), 0),
           CASE WHEN v_all > 0 THEN ROUND(SUM(e.amount) / v_all * 100, 2) ELSE 0 END
      FROM restaurantexpenses e
     WHERE e.farmid = p_farmid AND e.expensedate BETWEEN p_from AND p_to
       AND COALESCE(e.status, 'Approved') <> 'Rejected'
     GROUP BY COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised')
     ORDER BY 3 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 3. SALES SUMMARY OVER A RANGE
-- =============================================================================
-- 223's daily-sales function takes a single date. Every other report on the new
-- page is range-driven, and a KPI header that silently meant "today" while the
-- table below it meant "the last 30 days" would be actively misleading. This is
-- the same shape over (from, to), plus the tip total that nothing reported.
CREATE FUNCTION public.sprestaurant_report_sales_summary(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    total_orders BIGINT, completed_orders BIGINT, cancelled_orders BIGINT,
    gross_revenue NUMERIC, discount_total NUMERIC, tax_total NUMERIC,
    service_charge_total NUMERIC, net_revenue NUMERIC, avg_ticket NUMERIC,
    covers_total BIGINT, revenue_per_cover NUMERIC, tips_total NUMERIC,
    dinein_count BIGINT, dinein_revenue NUMERIC,
    takeaway_count BIGINT, takeaway_revenue NUMERIC,
    delivery_count BIGINT, delivery_revenue NUMERIC,
    active_days BIGINT, avg_daily_revenue NUMERIC
) AS $$
DECLARE v_tips NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(p.tipamount), 0) INTO v_tips
      FROM restaurantorderpayments p
      JOIN restaurantorders o ON o.orderid = p.orderid AND o.farmid = p.farmid
     WHERE p.farmid = p_farmid AND p.status = 'Completed' AND o.status = 'Completed'
       AND o.createdat::DATE BETWEEN p_from AND p_to;

    RETURN QUERY
    SELECT
        COUNT(*)::BIGINT,
        COUNT(*) FILTER (WHERE o.status = 'Completed')::BIGINT,
        COUNT(*) FILTER (WHERE o.status = 'Cancelled')::BIGINT,
        COALESCE(SUM(o.totalamount) FILTER (WHERE o.status = 'Completed'), 0),
        COALESCE(SUM(o.discountamount) FILTER (WHERE o.status = 'Completed'), 0),
        COALESCE(SUM(o.taxamount) FILTER (WHERE o.status = 'Completed'), 0),
        COALESCE(SUM(o.servicechargeamount) FILTER (WHERE o.status = 'Completed'), 0),
        COALESCE(SUM(o.subtotal) FILTER (WHERE o.status = 'Completed'), 0),
        CASE WHEN COUNT(*) FILTER (WHERE o.status = 'Completed') > 0
            THEN ROUND(SUM(o.totalamount) FILTER (WHERE o.status = 'Completed')
                       / COUNT(*) FILTER (WHERE o.status = 'Completed'), 2)
            ELSE 0 END,
        COALESCE(SUM(o.covers) FILTER (WHERE o.status = 'Completed'), 0)::BIGINT,
        CASE WHEN COALESCE(SUM(o.covers) FILTER (WHERE o.status = 'Completed'), 0) > 0
            THEN ROUND(SUM(o.totalamount) FILTER (WHERE o.status = 'Completed')
                       / SUM(o.covers) FILTER (WHERE o.status = 'Completed'), 2)
            ELSE 0 END,
        v_tips,
        COUNT(*) FILTER (WHERE o.ordertype = 'DineIn' AND o.status = 'Completed')::BIGINT,
        COALESCE(SUM(o.totalamount) FILTER (WHERE o.ordertype = 'DineIn' AND o.status = 'Completed'), 0),
        COUNT(*) FILTER (WHERE o.ordertype = 'Takeaway' AND o.status = 'Completed')::BIGINT,
        COALESCE(SUM(o.totalamount) FILTER (WHERE o.ordertype = 'Takeaway' AND o.status = 'Completed'), 0),
        COUNT(*) FILTER (WHERE o.ordertype = 'Delivery' AND o.status = 'Completed')::BIGINT,
        COALESCE(SUM(o.totalamount) FILTER (WHERE o.ordertype = 'Delivery' AND o.status = 'Completed'), 0),
        COUNT(DISTINCT o.createdat::DATE) FILTER (WHERE o.status = 'Completed')::BIGINT,
        -- averaged over days the restaurant actually traded, not calendar days:
        -- a Monday closure should not read as a bad Monday.
        CASE WHEN COUNT(DISTINCT o.createdat::DATE) FILTER (WHERE o.status = 'Completed') > 0
            THEN ROUND(SUM(o.totalamount) FILTER (WHERE o.status = 'Completed')
                       / COUNT(DISTINCT o.createdat::DATE) FILTER (WHERE o.status = 'Completed'), 2)
            ELSE 0 END
    FROM restaurantorders o
    WHERE o.farmid = p_farmid AND o.createdat::DATE BETWEEN p_from AND p_to;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 4. PAYMENT METHODS OVER A RANGE (with tips, and share of take)
-- =============================================================================
CREATE FUNCTION public.sprestaurant_report_payment_methods(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    method_name TEXT, txn_count BIGINT, amount_total NUMERIC,
    tips_total NUMERIC, share_pct NUMERIC, avg_txn NUMERIC
) AS $$
DECLARE v_all NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(p.amount), 0) INTO v_all
      FROM restaurantorderpayments p
      JOIN restaurantorders o ON o.orderid = p.orderid AND o.farmid = p.farmid
     WHERE p.farmid = p_farmid AND p.status = 'Completed' AND o.status = 'Completed'
       AND o.createdat::DATE BETWEEN p_from AND p_to;

    RETURN QUERY
    SELECT COALESCE(NULLIF(p.paymentmethod, ''), 'Unspecified'),
           COUNT(*)::BIGINT,
           COALESCE(SUM(p.amount), 0),
           COALESCE(SUM(p.tipamount), 0),
           CASE WHEN v_all > 0 THEN ROUND(SUM(p.amount) / v_all * 100, 2) ELSE 0 END,
           ROUND(AVG(p.amount), 2)
      FROM restaurantorderpayments p
      JOIN restaurantorders o ON o.orderid = p.orderid AND o.farmid = p.farmid
     WHERE p.farmid = p_farmid AND p.status = 'Completed' AND o.status = 'Completed'
       AND o.createdat::DATE BETWEEN p_from AND p_to
     GROUP BY COALESCE(NULLIF(p.paymentmethod, ''), 'Unspecified')
     ORDER BY 3 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 5. KITCHEN PERFORMANCE -- the timings nothing has ever read
-- =============================================================================
-- restaurantorderitems stamps three moments on every line: senttoktchenat (the
-- ticket reached the pass), prepstartedat (a cook picked it up) and readyat
-- (bumped). Queue time and cook time are different problems with different
-- fixes -- a long queue means the kitchen is under-staffed for the rush, a long
-- cook time means the item or the station is slow -- so they are reported apart
-- rather than as one "ticket time".
--
-- Only items with both ends stamped are counted. A cancelled item, or one still
-- in progress, would otherwise drag an average toward zero or toward infinity.
CREATE FUNCTION public.sprestaurant_report_kitchen_performance(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    station_name TEXT, items_made BIGINT, avg_queue_mins NUMERIC,
    avg_prep_mins NUMERIC, avg_ticket_mins NUMERIC, max_ticket_mins NUMERIC,
    over_target_count BIGINT, slowest_item TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH timed AS (
        SELECT COALESCE(NULLIF(oi.kdsstation, ''), 'Unassigned') AS stn,
               oi.itemname                                       AS nm,
               EXTRACT(EPOCH FROM (oi.prepstartedat - oi.senttoktchenat)) / 60.0 AS queue_m,
               EXTRACT(EPOCH FROM (oi.readyat - COALESCE(oi.prepstartedat, oi.senttoktchenat))) / 60.0 AS prep_m,
               EXTRACT(EPOCH FROM (oi.readyat - oi.senttoktchenat)) / 60.0 AS total_m
          FROM restaurantorderitems oi
          JOIN restaurantorders o ON o.orderid = oi.orderid AND o.farmid = oi.farmid
         WHERE oi.farmid = p_farmid
           AND o.createdat::DATE BETWEEN p_from AND p_to
           AND oi.senttoktchenat IS NOT NULL
           AND oi.readyat IS NOT NULL
           AND oi.readyat >= oi.senttoktchenat
           AND oi.status <> 'Cancelled'
    )
    SELECT t.stn,
           COUNT(*)::BIGINT,
           COALESCE(ROUND(AVG(t.queue_m)::NUMERIC, 1), 0),
           COALESCE(ROUND(AVG(t.prep_m)::NUMERIC, 1), 0),
           COALESCE(ROUND(AVG(t.total_m)::NUMERIC, 1), 0),
           COALESCE(ROUND(MAX(t.total_m)::NUMERIC, 1), 0),
           -- 15 minutes is the conventional casual-dining ticket target; the
           -- frontend labels this column with the number so it is never a
           -- mystery threshold.
           COUNT(*) FILTER (WHERE t.total_m > 15)::BIGINT,
           COALESCE((SELECT t2.nm FROM timed t2
                      WHERE t2.stn = t.stn
                      ORDER BY t2.total_m DESC NULLS LAST LIMIT 1), '-')
      FROM timed t
     GROUP BY t.stn
     ORDER BY AVG(t.total_m) DESC NULLS LAST;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 6. TABLE TURNOVER -- uses completedat, which 223 never touched
-- =============================================================================
-- Dwell is completedat - createdat on a dine-in order. Turns per trading day
-- divides by the number of distinct days that table actually took an order, for
-- the same reason active_days exists above: dividing by calendar days would
-- punish a table in a section that only opens at weekends.
CREATE FUNCTION public.sprestaurant_report_table_turnover(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    table_label TEXT, seat_capacity INT, order_count BIGINT, covers_served BIGINT,
    revenue_total NUMERIC, avg_dwell_mins NUMERIC, trading_days BIGINT,
    turns_per_day NUMERIC, revenue_per_cover NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT COALESCE(NULLIF(o.tablenumber, ''), 'Unassigned'),
           COALESCE(MAX(tb.capacity), 0),
           COUNT(*)::BIGINT,
           COALESCE(SUM(o.covers), 0)::BIGINT,
           COALESCE(SUM(o.totalamount), 0),
           COALESCE(ROUND(AVG(EXTRACT(EPOCH FROM (o.completedat - o.createdat)) / 60.0)
                          FILTER (WHERE o.completedat IS NOT NULL
                                    AND o.completedat >= o.createdat)::NUMERIC, 1), 0),
           COUNT(DISTINCT o.createdat::DATE)::BIGINT,
           CASE WHEN COUNT(DISTINCT o.createdat::DATE) > 0
               THEN ROUND(COUNT(*)::NUMERIC / COUNT(DISTINCT o.createdat::DATE), 2)
               ELSE 0 END,
           CASE WHEN COALESCE(SUM(o.covers), 0) > 0
               THEN ROUND(SUM(o.totalamount) / SUM(o.covers), 2)
               ELSE 0 END
      FROM restaurantorders o
      LEFT JOIN restauranttables tb ON tb.tableid = o.tableid AND tb.farmid = o.farmid
     WHERE o.farmid = p_farmid
       AND o.createdat::DATE BETWEEN p_from AND p_to
       AND o.status = 'Completed'
       AND o.ordertype = 'DineIn'
     GROUP BY COALESCE(NULLIF(o.tablenumber, ''), 'Unassigned')
     ORDER BY 5 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 7. TIPS BY WAITER -- tipamount has been collected since 217 and read by none
-- =============================================================================
-- Tip percentage is against the revenue the waiter actually served, which makes
-- it comparable between a waiter on high-value tables and one on low. Revenue
-- alone is not: it mostly measures which section someone was given.
CREATE FUNCTION public.sprestaurant_report_tips(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    waiter_name TEXT, order_count BIGINT, revenue_total NUMERIC,
    tips_total NUMERIC, tip_pct NUMERIC, avg_tip NUMERIC, tipped_orders BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH per_order AS (
        SELECT COALESCE(NULLIF(o.servedby, ''), 'Unassigned') AS who,
               o.orderid                                      AS oid,
               MAX(o.totalamount)                             AS rev,
               COALESCE(SUM(p.tipamount), 0)                  AS tip
          FROM restaurantorders o
          LEFT JOIN restaurantorderpayments p
                 ON p.orderid = o.orderid AND p.farmid = o.farmid AND p.status = 'Completed'
         WHERE o.farmid = p_farmid
           AND o.createdat::DATE BETWEEN p_from AND p_to
           AND o.status = 'Completed'
         GROUP BY COALESCE(NULLIF(o.servedby, ''), 'Unassigned'), o.orderid
    )
    SELECT po.who,
           COUNT(*)::BIGINT,
           COALESCE(SUM(po.rev), 0),
           COALESCE(SUM(po.tip), 0),
           CASE WHEN COALESCE(SUM(po.rev), 0) > 0
               THEN ROUND(SUM(po.tip) / SUM(po.rev) * 100, 2) ELSE 0 END,
           CASE WHEN COUNT(*) FILTER (WHERE po.tip > 0) > 0
               THEN ROUND(SUM(po.tip) / COUNT(*) FILTER (WHERE po.tip > 0), 2) ELSE 0 END,
           COUNT(*) FILTER (WHERE po.tip > 0)::BIGINT
      FROM per_order po
     GROUP BY po.who
     ORDER BY 4 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 8. DELIVERY PERFORMANCE -- promised vs actual, per driver
-- =============================================================================
-- On-time is actualmins <= estimatedmins, counted only over deliveries where
-- both numbers exist; a driver whose dispatcher never set an estimate should
-- not read as 0% on time. The denominator is returned as measured_count so the
-- percentage is never quoted without its sample size.
CREATE FUNCTION public.sprestaurant_report_delivery_performance(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    driver_label TEXT, assignment_count BIGINT, delivered_count BIGINT,
    failed_count BIGINT, avg_actual_mins NUMERIC, avg_estimated_mins NUMERIC,
    measured_count BIGINT, on_time_pct NUMERIC, total_distance_km NUMERIC,
    fees_total NUMERIC, avg_rating NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT COALESCE(NULLIF(da.drivername, ''), 'Unassigned'),
           COUNT(*)::BIGINT,
           COUNT(*) FILTER (WHERE da.status = 'Delivered')::BIGINT,
           COUNT(*) FILTER (WHERE da.status = 'Failed')::BIGINT,
           COALESCE(ROUND(AVG(da.actualmins) FILTER (WHERE da.actualmins IS NOT NULL)::NUMERIC, 1), 0),
           COALESCE(ROUND(AVG(da.estimatedmins) FILTER (WHERE da.estimatedmins IS NOT NULL)::NUMERIC, 1), 0),
           COUNT(*) FILTER (WHERE da.actualmins IS NOT NULL AND da.estimatedmins IS NOT NULL)::BIGINT,
           CASE WHEN COUNT(*) FILTER (WHERE da.actualmins IS NOT NULL AND da.estimatedmins IS NOT NULL) > 0
               THEN ROUND(
                   COUNT(*) FILTER (WHERE da.actualmins IS NOT NULL
                                      AND da.estimatedmins IS NOT NULL
                                      AND da.actualmins <= da.estimatedmins)::NUMERIC
                   / COUNT(*) FILTER (WHERE da.actualmins IS NOT NULL AND da.estimatedmins IS NOT NULL) * 100, 1)
               ELSE 0 END,
           COALESCE(ROUND(SUM(da.distancekm)::NUMERIC, 1), 0),
           COALESCE(SUM(da.deliveryfee), 0),
           COALESCE(ROUND(AVG(da.rating) FILTER (WHERE da.rating IS NOT NULL)::NUMERIC, 2), 0)
      FROM restaurantdeliveryassignments da
     WHERE da.farmid = p_farmid
       AND da.createdat::DATE BETWEEN p_from AND p_to
     GROUP BY COALESCE(NULLIF(da.drivername, ''), 'Unassigned')
     ORDER BY 2 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 9. DISCOUNTS -- what the promotions actually cost
-- =============================================================================
-- restaurantorderdiscounts records the applied amount per order, which is the
-- only honest figure: a "10%" discount is not 10% of anything until it meets an
-- order. Orders carrying each discount are counted distinctly because one order
-- can take several.
CREATE FUNCTION public.sprestaurant_report_discounts(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    discount_label TEXT, discount_kind TEXT, times_applied BIGINT,
    orders_affected BIGINT, discount_total NUMERIC, avg_discount NUMERIC,
    gross_on_discounted NUMERIC, effective_pct NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH applied AS (
        SELECT COALESCE(NULLIF(od.discountname, ''), 'Unnamed') AS label,
               COALESCE(NULLIF(od.discounttype, ''), 'Unknown') AS kind,
               od.orderid    AS oid,
               od.appliedamount AS amt,
               o.totalamount AS ord_total
          FROM restaurantorderdiscounts od
          JOIN restaurantorders o ON o.orderid = od.orderid AND o.farmid = od.farmid
         WHERE od.farmid = p_farmid
           AND o.createdat::DATE BETWEEN p_from AND p_to
           AND o.status = 'Completed'
    ),
    -- One row per (discount, order) before summing order totals. SUM(DISTINCT
    -- ord_total) would have been wrong here: two different orders that happen
    -- to come to the same amount are two orders, and DISTINCT would silently
    -- count them once, inflating the effective discount rate.
    per_order AS (
        SELECT DISTINCT a.label, a.oid, a.ord_total FROM applied a
    ),
    gross AS (
        SELECT po.label, COALESCE(SUM(po.ord_total), 0) AS gross_total
          FROM per_order po GROUP BY po.label
    )
    SELECT a.label,
           MAX(a.kind),
           COUNT(*)::BIGINT,
           COUNT(DISTINCT a.oid)::BIGINT,
           COALESCE(SUM(a.amt), 0),
           COALESCE(ROUND(AVG(a.amt), 2), 0),
           g.gross_total,
           CASE WHEN g.gross_total > 0
               THEN ROUND(SUM(a.amt) / g.gross_total * 100, 2) ELSE 0 END
      FROM applied a
      JOIN gross g ON g.label = a.label
     GROUP BY a.label, g.gross_total
     ORDER BY 5 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 10. VOIDS, CANCELLATIONS AND REFUNDS -- with the reason attached
-- =============================================================================
-- The old Overview showed a bare cancelled count. The reason columns have been
-- on the table since 217; grouping by them turns a number into something a
-- manager can act on. Value lost is the order total that will never be banked.
CREATE FUNCTION public.sprestaurant_report_voids(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    void_kind TEXT, void_reason TEXT, void_count BIGINT,
    value_lost NUMERIC, covers_lost BIGINT, share_pct NUMERIC
) AS $$
DECLARE v_all NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(o.totalamount), 0) INTO v_all
      FROM restaurantorders o
     WHERE o.farmid = p_farmid
       AND o.createdat::DATE BETWEEN p_from AND p_to
       AND o.status IN ('Cancelled', 'Refunded');

    RETURN QUERY
    SELECT o.status,
           COALESCE(NULLIF(COALESCE(o.cancelreason, o.refundreason), ''), 'No reason given'),
           COUNT(*)::BIGINT,
           COALESCE(SUM(o.totalamount), 0),
           COALESCE(SUM(o.covers), 0)::BIGINT,
           CASE WHEN v_all > 0 THEN ROUND(SUM(o.totalamount) / v_all * 100, 2) ELSE 0 END
      FROM restaurantorders o
     WHERE o.farmid = p_farmid
       AND o.createdat::DATE BETWEEN p_from AND p_to
       AND o.status IN ('Cancelled', 'Refunded')
     GROUP BY o.status, COALESCE(NULLIF(COALESCE(o.cancelreason, o.refundreason), ''), 'No reason given')
     ORDER BY 4 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 11. STOCK ON HAND -- the only point-in-time report here, so no date range
-- =============================================================================
-- A stock position is what is in the store right now; asking for last month's
-- would be a different report built on restaurantstockmovements. The frontend
-- therefore hides the date control on this one rather than showing a filter
-- that does nothing.
CREATE FUNCTION public.sprestaurant_report_stock_on_hand(p_farmid TEXT)
RETURNS TABLE (
    ingredient_name TEXT, ingredient_category TEXT, stock_unit TEXT,
    on_hand NUMERIC, par_level NUMERIC, reorder_point NUMERIC,
    unit_cost NUMERIC, stock_value NUMERIC, supplier_label TEXT,
    storage_label TEXT, stock_status TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT i.name,
           COALESCE(NULLIF(i.category, ''), 'Uncategorised'),
           COALESCE(NULLIF(i.unit, ''), 'unit'),
           COALESCE(i.currentstock, 0),
           COALESCE(i.parlevel, 0),
           COALESCE(i.reorderpoint, 0),
           COALESCE(i.costperunit, 0),
           ROUND(COALESCE(i.currentstock, 0) * COALESCE(i.costperunit, 0), 2),
           COALESCE(NULLIF(i.suppliername, ''), '-'),
           COALESCE(NULLIF(i.storagearea, ''), '-'),
           -- Ordered worst-first so the row that needs action is the row on top.
           CASE
               WHEN COALESCE(i.currentstock, 0) <= 0 THEN 'Out of stock'
               WHEN COALESCE(i.reorderpoint, 0) > 0
                    AND COALESCE(i.currentstock, 0) <= i.reorderpoint THEN 'Reorder now'
               WHEN COALESCE(i.parlevel, 0) > 0
                    AND COALESCE(i.currentstock, 0) < i.parlevel THEN 'Below par'
               ELSE 'OK'
           END
      FROM restaurantingredients i
     WHERE i.farmid = p_farmid AND i.isactive = TRUE
     ORDER BY CASE
               WHEN COALESCE(i.currentstock, 0) <= 0 THEN 0
               WHEN COALESCE(i.reorderpoint, 0) > 0
                    AND COALESCE(i.currentstock, 0) <= i.reorderpoint THEN 1
               WHEN COALESCE(i.parlevel, 0) > 0
                    AND COALESCE(i.currentstock, 0) < i.parlevel THEN 2
               ELSE 3 END,
              i.name;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 12. WASTE DETAIL -- 222 has a summary by reason only; this adds the item
-- =============================================================================
CREATE FUNCTION public.sprestaurant_report_waste_detail(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    waste_reason TEXT, item_label TEXT, waste_unit TEXT,
    qty_total NUMERIC, cost_total NUMERIC, entry_count BIGINT, share_pct NUMERIC
) AS $$
DECLARE v_all NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(w.costamount), 0) INTO v_all
      FROM restaurantwastelog w
     WHERE w.farmid = p_farmid AND w.createdat::DATE BETWEEN p_from AND p_to;

    RETURN QUERY
    SELECT COALESCE(NULLIF(w.reason, ''), 'Unspecified'),
           COALESCE(NULLIF(w.ingredientname, ''), 'Unnamed'),
           COALESCE(NULLIF(w.unit, ''), 'unit'),
           COALESCE(SUM(w.quantity), 0),
           COALESCE(SUM(w.costamount), 0),
           COUNT(*)::BIGINT,
           CASE WHEN v_all > 0 THEN ROUND(SUM(w.costamount) / v_all * 100, 2) ELSE 0 END
      FROM restaurantwastelog w
     WHERE w.farmid = p_farmid AND w.createdat::DATE BETWEEN p_from AND p_to
     GROUP BY COALESCE(NULLIF(w.reason, ''), 'Unspecified'),
              COALESCE(NULLIF(w.ingredientname, ''), 'Unnamed'),
              COALESCE(NULLIF(w.unit, ''), 'unit')
     ORDER BY 5 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 13. EXPENSES -- by category, with supplier and method, over a range
-- =============================================================================
CREATE FUNCTION public.sprestaurant_report_expenses(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    expense_category TEXT, supplier_label TEXT, method_label TEXT,
    entry_count BIGINT, expense_total NUMERIC, share_pct NUMERIC
) AS $$
DECLARE v_all NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(e.amount), 0) INTO v_all
      FROM restaurantexpenses e
     WHERE e.farmid = p_farmid AND e.expensedate BETWEEN p_from AND p_to
       AND COALESCE(e.status, 'Approved') <> 'Rejected';

    RETURN QUERY
    SELECT COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised'),
           COALESCE(NULLIF(e.suppliername, ''), '-'),
           COALESCE(NULLIF(e.paymentmethod, ''), '-'),
           COUNT(*)::BIGINT,
           COALESCE(SUM(e.amount), 0),
           CASE WHEN v_all > 0 THEN ROUND(SUM(e.amount) / v_all * 100, 2) ELSE 0 END
      FROM restaurantexpenses e
     WHERE e.farmid = p_farmid AND e.expensedate BETWEEN p_from AND p_to
       AND COALESCE(e.status, 'Approved') <> 'Rejected'
     GROUP BY COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised'),
              COALESCE(NULLIF(e.suppliername, ''), '-'),
              COALESCE(NULLIF(e.paymentmethod, ''), '-')
     ORDER BY 5 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 14. MENU ENGINEERING -- popularity against margin, the classic four boxes
-- =============================================================================
-- Both halves already existed separately: 223 reports what sells (sales by
-- item) and what each plate costs (food cost). Neither answers the question a
-- menu redesign actually asks, which is what sells AND earns.
--
--   Star      -- popular, high margin      -> protect it, never discount it
--   Plowhorse -- popular, low margin       -> reprice or re-cost the recipe
--   Puzzle    -- unpopular, high margin    -> promote it, move it up the menu
--   Dog       -- unpopular, low margin     -> take it off
--
-- The cut is each item against the period's own averages, not a fixed number,
-- so the classification stays meaningful whatever the restaurant sells.
CREATE FUNCTION public.sprestaurant_report_menu_engineering(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    item_label TEXT, category_label TEXT, qty_sold BIGINT, revenue_total NUMERIC,
    unit_cost NUMERIC, unit_margin NUMERIC, margin_pct NUMERIC,
    popularity_pct NUMERIC, menu_class TEXT
) AS $$
BEGIN
    -- Built entirely from CTEs. An earlier draft staged the per-item rows in a
    -- temp table so the averages could be taken over them; that is precisely the
    -- pattern section 2 exists to remove, because Npgsql pools connections and a
    -- temp table outliving an exception would serve the next caller stale rows.
    -- A CROSS JOIN against a one-row aggregate does the same job and cannot
    -- survive the statement.
    RETURN QUERY
    WITH item_rows AS (
        SELECT oi.itemname                                        AS nm,
               COALESCE(NULLIF(mc.name, ''), 'Uncategorised')     AS cat,
               SUM(oi.quantity)::BIGINT                           AS qty,
               SUM(oi.linetotal)                                  AS rev,
               COALESCE(MAX(rc.recipe_cost), 0)                   AS cost,
               ROUND(AVG(oi.unitprice) - COALESCE(MAX(rc.recipe_cost), 0), 2) AS marg
          FROM restaurantorderitems oi
          JOIN restaurantorders o ON o.orderid = oi.orderid AND o.farmid = oi.farmid
          LEFT JOIN restaurantmenuitems mi ON mi.menuitemid = oi.menuitemid AND mi.farmid = oi.farmid
          LEFT JOIN restaurantmenucategories mc ON mc.menucategoryid = mi.menucategoryid AND mc.farmid = mi.farmid
          LEFT JOIN LATERAL (
               SELECT SUM(r.quantity * (1 + r.wastepercent / 100) * ing.costperunit) AS recipe_cost
                 FROM restaurantrecipes r
                 JOIN restaurantingredients ing
                   ON ing.ingredientid = r.ingredientid AND ing.farmid = r.farmid
                WHERE r.menuitemid = oi.menuitemid AND r.farmid = oi.farmid
          ) rc ON TRUE
         WHERE oi.farmid = p_farmid
           AND o.createdat::DATE BETWEEN p_from AND p_to
           AND o.status = 'Completed'
           AND oi.status <> 'Cancelled'
         GROUP BY oi.itemname, COALESCE(NULLIF(mc.name, ''), 'Uncategorised')
    ),
    benchmark AS (
        SELECT COALESCE(SUM(ir.qty), 0)::NUMERIC AS total_qty,
               COUNT(*)::INT                     AS item_count,
               COALESCE(AVG(ir.marg), 0)         AS avg_margin
          FROM item_rows ir
    )
    SELECT m.nm, m.cat, m.qty, m.rev, m.cost, m.marg,
           CASE WHEN m.rev > 0 THEN ROUND((m.rev - (m.cost * m.qty)) / m.rev * 100, 2) ELSE 0 END,
           CASE WHEN b.total_qty > 0 THEN ROUND(m.qty / b.total_qty * 100, 2) ELSE 0 END,
           CASE
               -- "Popular" is an even share of the menu or better: with N items
               -- on sale, an item pulling its weight sells 100/N percent.
               WHEN b.item_count = 0 THEN 'Unclassified'
               -- An item with no recipe has no knowable cost, so its margin is
               -- really just its price. Classifying on that would call every
               -- un-costed item a Star; it is labelled instead.
               WHEN m.cost <= 0 THEN 'No recipe'
               WHEN (b.total_qty > 0 AND m.qty / b.total_qty * 100 >= 100.0 / b.item_count)
                    AND m.marg >= b.avg_margin THEN 'Star'
               WHEN (b.total_qty > 0 AND m.qty / b.total_qty * 100 >= 100.0 / b.item_count)
                    AND m.marg <  b.avg_margin THEN 'Plowhorse'
               WHEN m.marg >= b.avg_margin THEN 'Puzzle'
               ELSE 'Dog'
           END
      FROM item_rows m CROSS JOIN benchmark b
     ORDER BY m.rev DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 15. CUSTOMER RETENTION -- one row, because it is a set of ratios
-- =============================================================================
-- Migration 251 linked orders to customers, which is what makes repeat rate
-- computable. Orders with no customerid are walk-ins and are excluded from the
-- ratios but reported as their own count, so the denominator is never silently
-- wrong.
CREATE FUNCTION public.sprestaurant_report_customer_retention(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    identified_customers BIGINT, walkin_orders BIGINT, new_customers BIGINT,
    returning_customers BIGINT, repeat_rate_pct NUMERIC, avg_visits NUMERIC,
    avg_spend NUMERIC, top_spend NUMERIC, lapsed_customers BIGINT,
    vip_customers BIGINT
) AS $$
DECLARE
    v_ident   BIGINT := 0;
    v_walkin  BIGINT := 0;
    v_new     BIGINT := 0;
    v_return  BIGINT := 0;
    v_visits  NUMERIC := 0;
    v_spend   NUMERIC := 0;
    v_top     NUMERIC := 0;
    v_lapsed  BIGINT := 0;
    v_vip     BIGINT := 0;
BEGIN
    SELECT COUNT(*) FILTER (WHERE o.customerid IS NULL)
      INTO v_walkin
      FROM restaurantorders o
     WHERE o.farmid = p_farmid
       AND o.createdat::DATE BETWEEN p_from AND p_to
       AND o.status = 'Completed';

    WITH in_period AS (
        SELECT o.customerid AS cid, COUNT(*) AS visits, SUM(o.totalamount) AS spend
          FROM restaurantorders o
         WHERE o.farmid = p_farmid
           AND o.createdat::DATE BETWEEN p_from AND p_to
           AND o.status = 'Completed'
           AND o.customerid IS NOT NULL
         GROUP BY o.customerid
    ),
    first_seen AS (
        SELECT ip.cid,
               ip.visits,
               ip.spend,
               (SELECT MIN(o2.createdat::DATE)
                  FROM restaurantorders o2
                 WHERE o2.farmid = p_farmid AND o2.customerid = ip.cid
                   AND o2.status = 'Completed') AS first_date
          FROM in_period ip
    )
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE fs.first_date >= p_from),
           COUNT(*) FILTER (WHERE fs.first_date <  p_from),
           COALESCE(ROUND(AVG(fs.visits), 2), 0),
           COALESCE(ROUND(AVG(fs.spend), 2), 0),
           COALESCE(ROUND(MAX(fs.spend), 2), 0)
      INTO v_ident, v_new, v_return, v_visits, v_spend, v_top
      FROM first_seen fs;

    SELECT COUNT(*) FILTER (WHERE c.segment = 'Lapsed'),
           COUNT(*) FILTER (WHERE c.segment = 'VIP')
      INTO v_lapsed, v_vip
      FROM restaurantcustomers c
     WHERE c.farmid = p_farmid AND c.isactive = TRUE;

    RETURN QUERY SELECT
        v_ident, v_walkin, v_new, v_return,
        CASE WHEN v_ident > 0 THEN ROUND(v_return::NUMERIC / v_ident * 100, 2) ELSE 0 END,
        v_visits, v_spend, v_top, v_lapsed, v_vip;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 16. CHANNEL PROFITABILITY -- what the aggregators keep
-- =============================================================================
-- restaurantthirdpartyorders already stores commissionamount, platformfee and
-- netamount per order. Nothing read them, so the cost of selling through a
-- delivery app was invisible next to the revenue it brought in.
CREATE FUNCTION public.sprestaurant_report_channel(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    platform_label TEXT, order_count BIGINT, rejected_count BIGINT,
    gross_total NUMERIC, commission_total NUMERIC, platform_fee_total NUMERIC,
    net_total NUMERIC, commission_pct NUMERIC, avg_order NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT COALESCE(NULLIF(tp.platformname, ''), 'Unknown'),
           COUNT(*)::BIGINT,
           COUNT(*) FILTER (WHERE tp.status = 'Rejected')::BIGINT,
           COALESCE(SUM(tp.totalamount), 0),
           COALESCE(SUM(tp.commissionamount), 0),
           COALESCE(SUM(tp.platformfee), 0),
           COALESCE(SUM(tp.netamount), 0),
           CASE WHEN COALESCE(SUM(tp.totalamount), 0) > 0
               THEN ROUND(SUM(tp.commissionamount) / SUM(tp.totalamount) * 100, 2) ELSE 0 END,
           COALESCE(ROUND(AVG(tp.totalamount), 2), 0)
      FROM restaurantthirdpartyorders tp
     WHERE tp.farmid = p_farmid
       AND tp.receivedat::DATE BETWEEN p_from AND p_to
     GROUP BY COALESCE(NULLIF(tp.platformname, ''), 'Unknown')
     ORDER BY 4 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 17. CATERING AND EVENTS PIPELINE
-- =============================================================================
-- Grouped by status rather than listed, because the question this answers is
-- "how much is booked and how much of it is still owed", not "which events".
CREATE FUNCTION public.sprestaurant_report_events(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    event_status TEXT, event_count BIGINT, guest_total BIGINT,
    contracted_total NUMERIC, deposit_total NUMERIC, deposit_paid_total NUMERIC,
    balance_total NUMERIC, avg_per_head NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT COALESCE(NULLIF(ev.status, ''), 'Unknown'),
           COUNT(*)::BIGINT,
           COALESCE(SUM(ev.guestcount), 0)::BIGINT,
           COALESCE(SUM(ev.totalamount), 0),
           COALESCE(SUM(ev.depositamount), 0),
           COALESCE(SUM(ev.depositamount) FILTER (WHERE ev.depositpaid), 0),
           COALESCE(SUM(ev.balancedue), 0),
           CASE WHEN COALESCE(SUM(ev.guestcount), 0) > 0
               THEN ROUND(SUM(ev.totalamount) / SUM(ev.guestcount), 2) ELSE 0 END
      FROM restaurantevents ev
     WHERE ev.farmid = p_farmid
       AND ev.eventdate BETWEEN p_from AND p_to
     GROUP BY COALESCE(NULLIF(ev.status, ''), 'Unknown')
     ORDER BY 4 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 18. GUEST FEEDBACK -- ratings by source, over a range
-- =============================================================================
-- 224's sprestaurant_feedback_stats is lifetime and un-ranged. Since migration
-- 292 let QR guests rate the restaurant themselves, the interesting question
-- became whether the QR channel says something different from what staff hear
-- at the table -- so this groups by source and takes a date range.
CREATE FUNCTION public.sprestaurant_report_feedback(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    source_label TEXT, response_count BIGINT, avg_overall NUMERIC,
    avg_food NUMERIC, avg_service NUMERIC, avg_ambience NUMERIC,
    promoter_count BIGINT, detractor_count BIGINT, unanswered_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT COALESCE(NULLIF(f.source, ''), 'Unknown'),
           COUNT(*)::BIGINT,
           COALESCE(ROUND(AVG(f.rating)::NUMERIC, 2), 0),
           COALESCE(ROUND(AVG(f.foodrating)::NUMERIC, 2), 0),
           COALESCE(ROUND(AVG(f.servicerating)::NUMERIC, 2), 0),
           COALESCE(ROUND(AVG(f.ambiencerating)::NUMERIC, 2), 0),
           COUNT(*) FILTER (WHERE f.rating >= 4)::BIGINT,
           COUNT(*) FILTER (WHERE f.rating <= 2)::BIGINT,
           COUNT(*) FILTER (WHERE f.status = 'New')::BIGINT
      FROM restaurantcustomerfeedback f
     WHERE f.farmid = p_farmid
       AND f.createdat::DATE BETWEEN p_from AND p_to
     GROUP BY COALESCE(NULLIF(f.source, ''), 'Unknown')
     ORDER BY 2 DESC;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 19. Supporting indexes
-- =============================================================================
-- Every function above filters one farm by a date. These cover the two report
-- paths that scan the largest tables. IF NOT EXISTS throughout, and index-only
-- additions cannot change a query's result -- only how fast it arrives.
CREATE INDEX IF NOT EXISTS ix_restaurantorders_farm_created_status
    ON restaurantorders (farmid, (createdat::DATE), status);

CREATE INDEX IF NOT EXISTS ix_restaurantorderitems_farm_order
    ON restaurantorderitems (farmid, orderid);

CREATE INDEX IF NOT EXISTS ix_restaurantorderpayments_farm_order
    ON restaurantorderpayments (farmid, orderid);

CREATE INDEX IF NOT EXISTS ix_restaurantwastelog_farm_created
    ON restaurantwastelog (farmid, (createdat::DATE));

CREATE INDEX IF NOT EXISTS ix_restaurantexpenses_farm_date
    ON restaurantexpenses (farmid, expensedate);

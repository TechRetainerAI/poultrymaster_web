-- Migration 223: Restaurant Management System — Reporting & BI Analytics
-- Applied: 2026-08-30
-- Phase R8: Sales reports, food cost, revenue analysis, KPI alerts

-- =============================================================================
-- 1. KPI ALERT RULES
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantkpialerts (
    kpialertid           SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    name                 TEXT NOT NULL,
    metric               TEXT NOT NULL,            -- FoodCostPercent, LaborCostPercent, AvgTicket, DailySales, WastePercent
    operator             TEXT NOT NULL DEFAULT '>', -- >, <, >=, <=, =
    threshold            NUMERIC(12,2) NOT NULL,
    isenabled            BOOLEAN DEFAULT TRUE,
    lastchecked          TIMESTAMP,
    lasttriggered        TIMESTAMP,
    createdat            TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantkpialerts_farm ON restaurantkpialerts(farmid);

-- =============================================================================
-- STORED PROCEDURES: REPORTING
-- =============================================================================

-- Daily sales summary
CREATE OR REPLACE FUNCTION sprestaurant_report_daily_sales(p_farmid TEXT, p_date DATE)
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
        COALESCE(SUM(p.amount) FILTER (WHERE p.paymentmethod = 'Cash'), 0),
        COALESCE(SUM(p.amount) FILTER (WHERE p.paymentmethod = 'Card'), 0),
        COALESCE(SUM(p.amount) FILTER (WHERE p.paymentmethod = 'MobileMoney'), 0),
        COALESCE(SUM(p.amount) FILTER (WHERE p.paymentmethod NOT IN ('Cash','Card','MobileMoney')), 0)
    FROM restaurantorders o
    LEFT JOIN restaurantorderpayments p ON p.orderid = o.orderid AND p.farmid = o.farmid AND p.status = 'Completed'
    WHERE o.farmid = p_farmid AND o.createdat::DATE = p_date;
END;
$$ LANGUAGE plpgsql;

-- Sales by menu item (top sellers)
CREATE OR REPLACE FUNCTION sprestaurant_report_sales_by_item(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    menuitemid INT, itemname TEXT, quantity_sold BIGINT,
    total_revenue NUMERIC, avg_price NUMERIC, order_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT oi.menuitemid, oi.itemname, SUM(oi.quantity)::BIGINT,
           SUM(oi.linetotal), ROUND(AVG(oi.unitprice), 2),
           COUNT(DISTINCT oi.orderid)::BIGINT
    FROM restaurantorderitems oi
    JOIN restaurantorders o ON o.orderid = oi.orderid AND o.farmid = oi.farmid
    WHERE oi.farmid = p_farmid AND o.status = 'Completed'
      AND o.createdat::DATE BETWEEN p_from AND p_to
      AND oi.status != 'Cancelled'
    GROUP BY oi.menuitemid, oi.itemname
    ORDER BY SUM(oi.linetotal) DESC;
END;
$$ LANGUAGE plpgsql;

-- Sales by category
CREATE OR REPLACE FUNCTION sprestaurant_report_sales_by_category(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    categoryname TEXT, item_count BIGINT, quantity_sold BIGINT, total_revenue NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT COALESCE(mc.name, 'Uncategorized'), COUNT(DISTINCT oi.menuitemid)::BIGINT,
           SUM(oi.quantity)::BIGINT, SUM(oi.linetotal)
    FROM restaurantorderitems oi
    JOIN restaurantorders o ON o.orderid = oi.orderid AND o.farmid = oi.farmid
    LEFT JOIN restaurantmenuitems mi ON mi.menuitemid = oi.menuitemid AND mi.farmid = oi.farmid
    LEFT JOIN restaurantmenucategories mc ON mc.menucategoryid = mi.menucategoryid AND mc.farmid = mi.farmid
    WHERE oi.farmid = p_farmid AND o.status = 'Completed'
      AND o.createdat::DATE BETWEEN p_from AND p_to AND oi.status != 'Cancelled'
    GROUP BY mc.name ORDER BY total_revenue DESC;
END;
$$ LANGUAGE plpgsql;

-- Sales by hour (peak hours)
CREATE OR REPLACE FUNCTION sprestaurant_report_sales_by_hour(p_farmid TEXT, p_date DATE)
RETURNS TABLE (hour_of_day INT, order_count BIGINT, total_revenue NUMERIC, avg_ticket NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT EXTRACT(HOUR FROM o.createdat)::INT, COUNT(*)::BIGINT,
           SUM(o.totalamount), ROUND(AVG(o.totalamount), 2)
    FROM restaurantorders o
    WHERE o.farmid = p_farmid AND o.createdat::DATE = p_date AND o.status = 'Completed'
    GROUP BY EXTRACT(HOUR FROM o.createdat) ORDER BY 1;
END;
$$ LANGUAGE plpgsql;

-- Revenue trend (daily for a date range)
CREATE OR REPLACE FUNCTION sprestaurant_report_revenue_trend(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (report_date DATE, order_count BIGINT, total_revenue NUMERIC, avg_ticket NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT o.createdat::DATE, COUNT(*)::BIGINT,
           SUM(o.totalamount), ROUND(AVG(o.totalamount), 2)
    FROM restaurantorders o
    WHERE o.farmid = p_farmid AND o.createdat::DATE BETWEEN p_from AND p_to AND o.status = 'Completed'
    GROUP BY o.createdat::DATE ORDER BY 1;
END;
$$ LANGUAGE plpgsql;

-- Food cost report (per menu item with recipe cost)
CREATE OR REPLACE FUNCTION sprestaurant_report_food_cost(p_farmid TEXT)
RETURNS TABLE (
    menuitemid INT, itemname TEXT, sellingprice NUMERIC, recipecost NUMERIC,
    foodcostpercent NUMERIC, margin NUMERIC, categoryname TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT mi.menuitemid, mi.name, mi.price,
           COALESCE(SUM(ROUND(r.quantity * (1 + r.wastepercent / 100) * i.costperunit, 4)), 0) AS recipecost,
           CASE WHEN mi.price > 0 THEN
               ROUND(COALESCE(SUM(ROUND(r.quantity * (1 + r.wastepercent / 100) * i.costperunit, 4)), 0) / mi.price * 100, 2)
           ELSE 0 END AS foodcostpercent,
           mi.price - COALESCE(SUM(ROUND(r.quantity * (1 + r.wastepercent / 100) * i.costperunit, 4)), 0) AS margin,
           COALESCE(mc.name, 'Uncategorized')
    FROM restaurantmenuitems mi
    LEFT JOIN restaurantrecipes r ON r.menuitemid = mi.menuitemid AND r.farmid = mi.farmid
    LEFT JOIN restaurantingredients i ON i.ingredientid = r.ingredientid AND i.farmid = r.farmid
    LEFT JOIN restaurantmenucategories mc ON mc.menucategoryid = mi.menucategoryid AND mc.farmid = mi.farmid
    WHERE mi.farmid = p_farmid AND mi.isactive = TRUE
    GROUP BY mi.menuitemid, mi.name, mi.price, mc.name
    ORDER BY foodcostpercent DESC;
END;
$$ LANGUAGE plpgsql;

-- Server/waiter performance
CREATE OR REPLACE FUNCTION sprestaurant_report_server_performance(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    servedby TEXT, order_count BIGINT, total_revenue NUMERIC,
    avg_ticket NUMERIC, total_covers BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT COALESCE(o.servedby, 'Unassigned'), COUNT(*)::BIGINT,
           SUM(o.totalamount), ROUND(AVG(o.totalamount), 2), SUM(o.covers)::BIGINT
    FROM restaurantorders o
    WHERE o.farmid = p_farmid AND o.createdat::DATE BETWEEN p_from AND p_to AND o.status = 'Completed'
    GROUP BY o.servedby ORDER BY total_revenue DESC;
END;
$$ LANGUAGE plpgsql;

-- KPI alerts CRUD
CREATE OR REPLACE FUNCTION sprestaurant_kpialert_list(p_farmid TEXT)
RETURNS TABLE (
    kpialertid INT, farmid TEXT, name TEXT, metric TEXT, operator TEXT,
    threshold NUMERIC, isenabled BOOLEAN, lastchecked TIMESTAMP,
    lasttriggered TIMESTAMP, createdat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY SELECT a.* FROM restaurantkpialerts a WHERE a.farmid = p_farmid ORDER BY a.name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_kpialert_insert(
    p_farmid TEXT, p_name TEXT, p_metric TEXT, p_operator TEXT, p_threshold NUMERIC, p_isenabled BOOLEAN
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantkpialerts (farmid, name, metric, operator, threshold, isenabled)
    VALUES (p_farmid, p_name, p_metric, p_operator, p_threshold, p_isenabled) RETURNING kpialertid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_kpialert_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantkpialerts WHERE kpialertid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

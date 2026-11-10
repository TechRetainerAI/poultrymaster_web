-- 410: Generic Delivery Report — aggregate delivery data by driver, product,
-- route, and status for performance tracking.

-- Driver performance summary
CREATE OR REPLACE FUNCTION spgenericdelivery_driver_report(
    p_farmid TEXT,
    p_fromdate DATE DEFAULT NULL,
    p_todate DATE DEFAULT NULL,
    p_drivername TEXT DEFAULT NULL
)
RETURNS TABLE (
    "DriverName"        TEXT,
    "TotalDeliveries"   BIGINT,
    "TotalLoaded"       NUMERIC,
    "TotalSold"         NUMERIC,
    "TotalReturned"     NUMERIC,
    "TotalDamaged"      NUMERIC,
    "TotalShort"        NUMERIC,
    "TotalSales"        NUMERIC,
    "TotalCashCollected" NUMERIC,
    "TotalCreditSales"  NUMERIC,
    "TotalExpenses"     NUMERIC,
    "DeliveryRate"      NUMERIC,
    "LoadedDeliveries"  BIGINT,
    "InTransitDeliveries" BIGINT,
    "DeliveredDeliveries" BIGINT,
    "ReconciledDeliveries" BIGINT,
    "CancelledDeliveries" BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(d."DriverName", 'Unassigned') AS "DriverName",
        COUNT(*)::BIGINT AS "TotalDeliveries",
        COALESCE(SUM(d."QuantityLoaded"), 0) AS "TotalLoaded",
        COALESCE(SUM(d."QuantitySold"), 0) AS "TotalSold",
        COALESCE(SUM(d."QuantityReturned"), 0) AS "TotalReturned",
        COALESCE(SUM(d."QuantityDamaged"), 0) AS "TotalDamaged",
        COALESCE(SUM(d."QuantityShort"), 0) AS "TotalShort",
        COALESCE(SUM(d."TotalSales"), 0) AS "TotalSales",
        COALESCE(SUM(d."CashCollected"), 0) AS "TotalCashCollected",
        COALESCE(SUM(d."CreditSales"), 0) AS "TotalCreditSales",
        COALESCE(SUM(d."DeliveryExpenses"), 0) AS "TotalExpenses",
        CASE WHEN SUM(d."QuantityLoaded") > 0
            THEN ROUND(SUM(d."QuantitySold") / SUM(d."QuantityLoaded") * 100, 1)
            ELSE 0 END AS "DeliveryRate",
        COUNT(*) FILTER (WHERE d."Status" = 'Loaded')::BIGINT AS "LoadedDeliveries",
        COUNT(*) FILTER (WHERE d."Status" = 'InTransit')::BIGINT AS "InTransitDeliveries",
        COUNT(*) FILTER (WHERE d."Status" = 'Delivered')::BIGINT AS "DeliveredDeliveries",
        COUNT(*) FILTER (WHERE d."Status" = 'Reconciled')::BIGINT AS "ReconciledDeliveries",
        COUNT(*) FILTER (WHERE d."Status" = 'Cancelled')::BIGINT AS "CancelledDeliveries"
    FROM genericdeliveries d
    WHERE d."FarmId" = p_farmid
      AND (p_fromdate IS NULL OR d."DeliveryDate" >= p_fromdate)
      AND (p_todate IS NULL OR d."DeliveryDate" <= p_todate + INTERVAL '1 day')
      AND (p_drivername IS NULL OR d."DriverName" = p_drivername)
    GROUP BY COALESCE(d."DriverName", 'Unassigned')
    ORDER BY "TotalSales" DESC;
END;
$$ LANGUAGE plpgsql;

-- Product delivery summary
CREATE OR REPLACE FUNCTION spgenericdelivery_product_report(
    p_farmid TEXT,
    p_fromdate DATE DEFAULT NULL,
    p_todate DATE DEFAULT NULL
)
RETURNS TABLE (
    "ProductName"       TEXT,
    "TotalDeliveries"   BIGINT,
    "TotalLoaded"       NUMERIC,
    "TotalSold"         NUMERIC,
    "TotalReturned"     NUMERIC,
    "TotalDamaged"      NUMERIC,
    "TotalShort"        NUMERIC,
    "TotalSales"        NUMERIC,
    "SellThroughRate"   NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(d."ProductName", 'Unknown') AS "ProductName",
        COUNT(*)::BIGINT AS "TotalDeliveries",
        COALESCE(SUM(d."QuantityLoaded"), 0) AS "TotalLoaded",
        COALESCE(SUM(d."QuantitySold"), 0) AS "TotalSold",
        COALESCE(SUM(d."QuantityReturned"), 0) AS "TotalReturned",
        COALESCE(SUM(d."QuantityDamaged"), 0) AS "TotalDamaged",
        COALESCE(SUM(d."QuantityShort"), 0) AS "TotalShort",
        COALESCE(SUM(d."TotalSales"), 0) AS "TotalSales",
        CASE WHEN SUM(d."QuantityLoaded") > 0
            THEN ROUND(SUM(d."QuantitySold") / SUM(d."QuantityLoaded") * 100, 1)
            ELSE 0 END AS "SellThroughRate"
    FROM genericdeliveries d
    WHERE d."FarmId" = p_farmid
      AND d."Status" IN ('Reconciled', 'Delivered')
      AND (p_fromdate IS NULL OR d."DeliveryDate" >= p_fromdate)
      AND (p_todate IS NULL OR d."DeliveryDate" <= p_todate + INTERVAL '1 day')
    GROUP BY COALESCE(d."ProductName", 'Unknown')
    ORDER BY "TotalSales" DESC;
END;
$$ LANGUAGE plpgsql;

-- Route performance summary
CREATE OR REPLACE FUNCTION spgenericdelivery_route_report(
    p_farmid TEXT,
    p_fromdate DATE DEFAULT NULL,
    p_todate DATE DEFAULT NULL
)
RETURNS TABLE (
    "Route"             TEXT,
    "TotalDeliveries"   BIGINT,
    "TotalLoaded"       NUMERIC,
    "TotalSold"         NUMERIC,
    "TotalSales"        NUMERIC,
    "TotalExpenses"     NUMERIC,
    "NetRevenue"        NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(d."Route", 'No route') AS "Route",
        COUNT(*)::BIGINT AS "TotalDeliveries",
        COALESCE(SUM(d."QuantityLoaded"), 0) AS "TotalLoaded",
        COALESCE(SUM(d."QuantitySold"), 0) AS "TotalSold",
        COALESCE(SUM(d."TotalSales"), 0) AS "TotalSales",
        COALESCE(SUM(d."DeliveryExpenses"), 0) AS "TotalExpenses",
        COALESCE(SUM(d."TotalSales"), 0) - COALESCE(SUM(d."DeliveryExpenses"), 0) AS "NetRevenue"
    FROM genericdeliveries d
    WHERE d."FarmId" = p_farmid
      AND d."Status" = 'Reconciled'
      AND (p_fromdate IS NULL OR d."DeliveryDate" >= p_fromdate)
      AND (p_todate IS NULL OR d."DeliveryDate" <= p_todate + INTERVAL '1 day')
    GROUP BY COALESCE(d."Route", 'No route')
    ORDER BY "TotalSales" DESC;
END;
$$ LANGUAGE plpgsql;

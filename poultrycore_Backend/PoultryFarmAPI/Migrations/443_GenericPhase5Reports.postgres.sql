-- =============================================================================
-- Migration 443: Phase 5 — Reporting, Reconciliation & Production Readiness
--
-- 1. Inventory Balance Report — per-item movement breakdown for a period
-- 2. Internal Inventory Consumption Report — posted internal use detail
-- 3. Inventory Reconciliation — validates opening + in - out = closing
-- 4. Restock Forecast — uses ALL consumption sources (sales + internal + production)
--
-- Idempotent: CREATE OR REPLACE on all functions.
-- =============================================================================

-- =========================================================================
-- 1. Inventory Balance Report
--    Shows opening, purchases, sales, production, internal use, other,
--    and closing quantity + value for each tracked item in a period.
-- =========================================================================

CREATE OR REPLACE FUNCTION spgenericreport_inventorybalance(
    p_farmid TEXT,
    p_from   DATE,
    p_to     DATE
)
RETURNS TABLE(
    "GenericProductId"    INT,
    "ProductName"         TEXT,
    "CategoryName"        TEXT,
    "Purpose"             TEXT,
    "UnitOfMeasure"       TEXT,
    "OpeningQty"          NUMERIC,
    "PurchasesQty"        NUMERIC,
    "ProductionInQty"     NUMERIC,
    "ReturnsInQty"        NUMERIC,
    "SalesQty"            NUMERIC,
    "InternalUseQty"      NUMERIC,
    "ProductionOutQty"    NUMERIC,
    "DamageQty"           NUMERIC,
    "AdjustmentQty"       NUMERIC,
    "OtherQty"            NUMERIC,
    "ClosingQty"          NUMERIC,
    "UnitCost"            NUMERIC,
    "InventoryValue"      NUMERIC
) LANGUAGE sql STABLE AS $fn$
    WITH movements AS (
        SELECT
            m.genericproductid,
            -- Opening = all movements BEFORE the period start
            SUM(m.quantity) FILTER (WHERE m.movementdate < p_from::timestamp) AS opening,
            -- Period movements by type
            SUM(m.quantity) FILTER (WHERE m.movementdate >= p_from::timestamp AND m.movementdate < (p_to + 1)::timestamp AND m.movementtype = 'PurchaseIn') AS purchases,
            SUM(m.quantity) FILTER (WHERE m.movementdate >= p_from::timestamp AND m.movementdate < (p_to + 1)::timestamp AND m.movementtype = 'Production') AS prod_in,
            SUM(m.quantity) FILTER (WHERE m.movementdate >= p_from::timestamp AND m.movementdate < (p_to + 1)::timestamp AND m.movementtype = 'ReturnIn') AS returns_in,
            SUM(ABS(m.quantity)) FILTER (WHERE m.movementdate >= p_from::timestamp AND m.movementdate < (p_to + 1)::timestamp AND m.movementtype = 'SaleOut') AS sales,
            SUM(ABS(m.quantity)) FILTER (WHERE m.movementdate >= p_from::timestamp AND m.movementdate < (p_to + 1)::timestamp AND m.movementtype = 'InternalUseOut') AS internal_use,
            SUM(ABS(m.quantity)) FILTER (WHERE m.movementdate >= p_from::timestamp AND m.movementdate < (p_to + 1)::timestamp AND m.movementtype IN ('DamageOut','ExpiredOut')) AS damage,
            SUM(m.quantity) FILTER (WHERE m.movementdate >= p_from::timestamp AND m.movementdate < (p_to + 1)::timestamp AND m.movementtype IN ('AdjustmentIn','AdjustmentOut')) AS adjustment,
            SUM(m.quantity) FILTER (WHERE m.movementdate >= p_from::timestamp AND m.movementdate < (p_to + 1)::timestamp AND m.movementtype IN ('TransferIn','TransferOut','Reversal','OpeningStock')) AS other
        FROM genericstockmovements m
        WHERE m.farmid = p_farmid
        GROUP BY m.genericproductid
    )
    SELECT
        p.genericproductid,
        p.productname::TEXT,
        c.name::TEXT,
        CASE
          WHEN p.cansell AND p.canuseinproduction AND p.canuseinternally THEN 'Sale · Production · Internal'
          WHEN p.cansell AND p.canuseinproduction THEN 'Sale · Production'
          WHEN p.cansell AND p.canuseinternally THEN 'Sale · Internal'
          WHEN p.canuseinproduction AND p.canuseinternally THEN 'Production · Internal'
          WHEN p.cansell THEN 'Sale'
          WHEN p.canuseinproduction THEN 'Production'
          WHEN p.canuseinternally THEN 'Internal Use'
          ELSE 'Sale'
        END::TEXT,
        p.unitofmeasure::TEXT,
        COALESCE(mv.opening, 0),
        COALESCE(mv.purchases, 0),
        COALESCE(mv.prod_in, 0),
        COALESCE(mv.returns_in, 0),
        COALESCE(mv.sales, 0),
        COALESCE(mv.internal_use, 0),
        0::NUMERIC,  -- production consumption out (not tracked separately yet)
        COALESCE(mv.damage, 0),
        COALESCE(mv.adjustment, 0),
        COALESCE(mv.other, 0),
        -- Closing = opening + all period movements (using raw signed quantities)
        COALESCE(mv.opening, 0) + COALESCE(mv.purchases, 0) + COALESCE(mv.prod_in, 0) + COALESCE(mv.returns_in, 0)
          - COALESCE(mv.sales, 0) - COALESCE(mv.internal_use, 0) - COALESCE(mv.damage, 0)
          + COALESCE(mv.adjustment, 0) + COALESCE(mv.other, 0),
        p.costprice,
        (COALESCE(mv.opening, 0) + COALESCE(mv.purchases, 0) + COALESCE(mv.prod_in, 0) + COALESCE(mv.returns_in, 0)
          - COALESCE(mv.sales, 0) - COALESCE(mv.internal_use, 0) - COALESCE(mv.damage, 0)
          + COALESCE(mv.adjustment, 0) + COALESCE(mv.other, 0)) * p.costprice
    FROM genericproducts p
    LEFT JOIN genericproductcategories c ON c.genericproductcategoryid = p.genericproductcategoryid
    LEFT JOIN movements mv ON mv.genericproductid = p.genericproductid
    WHERE p.farmid = p_farmid
      AND p.trackinventory = TRUE
      AND p.isdeleted = FALSE
    ORDER BY p.productname;
$fn$;

-- =========================================================================
-- 2. Internal Inventory Consumption Report
--    Detail rows from posted internal use records with cost data.
-- =========================================================================

CREATE OR REPLACE FUNCTION spgenericreport_internalconsumption(
    p_farmid   TEXT,
    p_from     DATE DEFAULT NULL,
    p_to       DATE DEFAULT NULL,
    p_category TEXT DEFAULT NULL
)
RETURNS TABLE(
    "UsageDate"           TIMESTAMP,
    "GenericProductId"    INT,
    "ProductName"         TEXT,
    "CategoryName"        TEXT,
    "QuantityUsed"        NUMERIC,
    "UnitOfMeasure"       TEXT,
    "UnitCost"            NUMERIC,
    "TotalCost"           NUMERIC,
    "ExpenseCategory"     TEXT,
    "Reason"              TEXT,
    "ReferenceNumber"     TEXT,
    "RecordedBy"          TEXT,
    "Status"              TEXT,
    "GenericInternalUsageId" INT
) LANGUAGE sql STABLE AS $fn$
    SELECT
        h.usagedate,
        i.genericproductid,
        p.productname::TEXT,
        pc.name::TEXT,
        i.stockquantity,
        COALESCE(i.entryunit, p.unitofmeasure)::TEXT,
        i.unitcost,
        i.totalcost,
        h.category::TEXT,
        h.reason::TEXT,
        h.referenceno::TEXT,
        h.createdby::TEXT,
        h.status::TEXT,
        h.genericinternalusageid
    FROM genericinternalusage h
    INNER JOIN genericinternalusageitems i ON i.genericinternalusageid = h.genericinternalusageid
    INNER JOIN genericproducts p ON p.genericproductid = i.genericproductid AND p.farmid = h.farmid
    LEFT JOIN genericproductcategories pc ON pc.genericproductcategoryid = p.genericproductcategoryid
    WHERE h.farmid = p_farmid
      AND h.status = 'Posted'
      AND (p_from IS NULL OR h.usagedate >= p_from::timestamp)
      AND (p_to IS NULL OR h.usagedate < (p_to + 1)::timestamp)
      AND (p_category IS NULL OR h.category = p_category)
    ORDER BY h.usagedate DESC, h.genericinternalusageid DESC;
$fn$;

-- Consumption summary metrics
CREATE OR REPLACE FUNCTION spgenericreport_consumptionsummary(
    p_farmid   TEXT,
    p_from     DATE DEFAULT NULL,
    p_to       DATE DEFAULT NULL
)
RETURNS TABLE(
    "TotalConsumptionCost"   NUMERIC,
    "TotalItemsConsumed"     INT,
    "TotalRecords"           INT,
    "TopItemName"            TEXT,
    "TopItemCost"            NUMERIC,
    "CategoryBreakdown"      JSONB
) LANGUAGE plpgsql STABLE AS $fn$
DECLARE
    v_total_cost NUMERIC := 0;
    v_total_items INT := 0;
    v_total_records INT := 0;
    v_top_name TEXT := '';
    v_top_cost NUMERIC := 0;
    v_cats JSONB := '[]'::JSONB;
BEGIN
    -- Totals
    SELECT COALESCE(SUM(i.totalcost), 0), COUNT(DISTINCT i.genericproductid), COUNT(DISTINCT h.genericinternalusageid)
    INTO v_total_cost, v_total_items, v_total_records
    FROM genericinternalusage h
    INNER JOIN genericinternalusageitems i ON i.genericinternalusageid = h.genericinternalusageid
    WHERE h.farmid = p_farmid AND h.status = 'Posted'
      AND (p_from IS NULL OR h.usagedate >= p_from::timestamp)
      AND (p_to IS NULL OR h.usagedate < (p_to + 1)::timestamp);

    -- Top consumed item
    SELECT p.productname, COALESCE(SUM(i.totalcost), 0)
    INTO v_top_name, v_top_cost
    FROM genericinternalusage h
    INNER JOIN genericinternalusageitems i ON i.genericinternalusageid = h.genericinternalusageid
    INNER JOIN genericproducts p ON p.genericproductid = i.genericproductid AND p.farmid = h.farmid
    WHERE h.farmid = p_farmid AND h.status = 'Posted'
      AND (p_from IS NULL OR h.usagedate >= p_from::timestamp)
      AND (p_to IS NULL OR h.usagedate < (p_to + 1)::timestamp)
    GROUP BY p.productname ORDER BY SUM(i.totalcost) DESC LIMIT 1;

    -- Category breakdown
    SELECT COALESCE(jsonb_agg(row_to_json(r)), '[]'::JSONB)
    INTO v_cats
    FROM (
        SELECT h.category, COALESCE(SUM(i.totalcost), 0) AS total_cost, COUNT(*) AS record_count
        FROM genericinternalusage h
        INNER JOIN genericinternalusageitems i ON i.genericinternalusageid = h.genericinternalusageid
        WHERE h.farmid = p_farmid AND h.status = 'Posted'
          AND (p_from IS NULL OR h.usagedate >= p_from::timestamp)
          AND (p_to IS NULL OR h.usagedate < (p_to + 1)::timestamp)
        GROUP BY h.category ORDER BY SUM(i.totalcost) DESC
    ) r;

    RETURN QUERY SELECT v_total_cost, v_total_items, v_total_records, v_top_name, v_top_cost, v_cats;
END;
$fn$;

-- =========================================================================
-- 3. Inventory Reconciliation
--    Validates that opening + movements = closing for every tracked item.
-- =========================================================================

CREATE OR REPLACE FUNCTION spgenericreport_inventoryreconciliation(
    p_farmid TEXT
)
RETURNS TABLE(
    "GenericProductId"   INT,
    "ProductName"        TEXT,
    "LedgerTotal"        NUMERIC,
    "CachedStock"        NUMERIC,
    "Drift"              NUMERIC,
    "IsReconciled"       BOOLEAN
) LANGUAGE sql STABLE AS $fn$
    SELECT
        p.genericproductid,
        p.productname::TEXT,
        COALESCE(SUM(m.quantity), 0) AS ledger_total,
        p.currentstock,
        p.currentstock - COALESCE(SUM(m.quantity), 0) AS drift,
        ABS(p.currentstock - COALESCE(SUM(m.quantity), 0)) < 0.001
    FROM genericproducts p
    LEFT JOIN genericstockmovements m ON m.genericproductid = p.genericproductid AND m.farmid = p.farmid
    WHERE p.farmid = p_farmid
      AND p.trackinventory = TRUE
      AND p.isdeleted = FALSE
    GROUP BY p.genericproductid, p.productname, p.currentstock
    ORDER BY ABS(p.currentstock - COALESCE(SUM(m.quantity), 0)) DESC, p.productname;
$fn$;

-- =========================================================================
-- 4. Restock Forecast
--    Uses ALL consumption sources: sales + internal use + production + damage.
--    Calculates avg daily consumption and days until stockout.
-- =========================================================================

CREATE OR REPLACE FUNCTION spgenericreport_restockforecast(
    p_farmid     TEXT,
    p_lookback   INT DEFAULT 30  -- days of history to base forecast on
)
RETURNS TABLE(
    "GenericProductId"      INT,
    "ProductName"           TEXT,
    "CurrentStock"          NUMERIC,
    "MinimumStockAlert"     NUMERIC,
    "UnitOfMeasure"         TEXT,
    "AvgDailySales"         NUMERIC,
    "AvgDailyInternalUse"   NUMERIC,
    "AvgDailyProduction"    NUMERIC,
    "AvgDailyOtherOut"      NUMERIC,
    "AvgDailyTotalOut"      NUMERIC,
    "DaysUntilStockout"     NUMERIC,
    "DaysUntilReorderPoint" NUMERIC,
    "SuggestedReorderQty"   NUMERIC,
    "UrgencyLevel"          TEXT
) LANGUAGE sql STABLE AS $fn$
    WITH consumption AS (
        SELECT
            m.genericproductid,
            -- Average daily consumption by type (using absolute values for outflows)
            COALESCE(SUM(ABS(m.quantity)) FILTER (WHERE m.movementtype = 'SaleOut'), 0) / GREATEST(p_lookback, 1) AS avg_sales,
            COALESCE(SUM(ABS(m.quantity)) FILTER (WHERE m.movementtype = 'InternalUseOut'), 0) / GREATEST(p_lookback, 1) AS avg_iu,
            COALESCE(SUM(ABS(m.quantity)) FILTER (WHERE m.movementtype IN ('DamageOut','ExpiredOut')), 0) / GREATEST(p_lookback, 1) AS avg_other
        FROM genericstockmovements m
        WHERE m.farmid = p_farmid
          AND m.movementdate >= (NOW() - (p_lookback || ' days')::interval)
          AND m.quantity < 0
        GROUP BY m.genericproductid
    )
    SELECT
        p.genericproductid,
        p.productname::TEXT,
        p.currentstock,
        p.minimumstockalert,
        p.unitofmeasure::TEXT,
        ROUND(COALESCE(c.avg_sales, 0), 4),
        ROUND(COALESCE(c.avg_iu, 0), 4),
        0::NUMERIC,  -- production consumption not tracked as outflow in current model
        ROUND(COALESCE(c.avg_other, 0), 4),
        ROUND(COALESCE(c.avg_sales, 0) + COALESCE(c.avg_iu, 0) + COALESCE(c.avg_other, 0), 4) AS total_out,
        -- Days until stockout
        CASE WHEN (COALESCE(c.avg_sales, 0) + COALESCE(c.avg_iu, 0) + COALESCE(c.avg_other, 0)) > 0
             THEN ROUND(p.currentstock / (COALESCE(c.avg_sales, 0) + COALESCE(c.avg_iu, 0) + COALESCE(c.avg_other, 0)), 1)
             ELSE 9999 END,
        -- Days until reorder point
        CASE WHEN (COALESCE(c.avg_sales, 0) + COALESCE(c.avg_iu, 0) + COALESCE(c.avg_other, 0)) > 0
             THEN ROUND((p.currentstock - p.minimumstockalert) / (COALESCE(c.avg_sales, 0) + COALESCE(c.avg_iu, 0) + COALESCE(c.avg_other, 0)), 1)
             ELSE 9999 END,
        -- Suggested reorder (enough for 30 days above reorder point)
        GREATEST(
            ROUND((COALESCE(c.avg_sales, 0) + COALESCE(c.avg_iu, 0) + COALESCE(c.avg_other, 0)) * 30 + p.minimumstockalert - p.currentstock, 0),
            0
        ),
        -- Urgency
        CASE
            WHEN p.currentstock <= 0 THEN 'Critical'
            WHEN p.currentstock <= p.minimumstockalert THEN 'Urgent'
            WHEN (COALESCE(c.avg_sales, 0) + COALESCE(c.avg_iu, 0) + COALESCE(c.avg_other, 0)) > 0
                 AND p.currentstock / (COALESCE(c.avg_sales, 0) + COALESCE(c.avg_iu, 0) + COALESCE(c.avg_other, 0)) <= 7 THEN 'Warning'
            ELSE 'OK'
        END::TEXT
    FROM genericproducts p
    LEFT JOIN consumption c ON c.genericproductid = p.genericproductid
    WHERE p.farmid = p_farmid
      AND p.trackinventory = TRUE
      AND p.isdeleted = FALSE
      AND p.isactive = TRUE
    ORDER BY
        CASE
            WHEN p.currentstock <= 0 THEN 0
            WHEN p.currentstock <= p.minimumstockalert THEN 1
            ELSE 2
        END,
        p.productname;
$fn$;

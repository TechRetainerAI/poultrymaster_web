-- =============================================================================
-- 176_WaterRawMaterialRecalcStock.sql
-- Recalculate Water raw-material / supply CurrentQuantity from the source ledgers.
--
-- Mirrors the Poultry recalc (175). Water CurrentQuantity is a stored running
-- total kept in PRODUCTION units (migration 146). If it drifts, recompute it the
-- same way the live SPs maintain it:
--
--   CurrentQuantity = SUM(purchase.Quantity * unitsPerPurchaseUnit)   -- 146: production units
--                   - SUM(usage.QuantityUsed)
--   (floored at 0)
--
-- Water has no manual-adjustment ledger, so there is no adjustments term.
-- Additive + idempotent (CREATE OR ALTER). Grants EXECUTE to `Techretainer`.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_RecalculateStock
    @FarmId                 NVARCHAR(450),
    @WaterRawMaterialItemId INT = NULL     -- NULL = every raw-material item for the company
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Expected AS (
        SELECT i.WaterRawMaterialItemId,
               i.CurrentQuantity AS OldQuantity,
               CAST(
                   ISNULL((SELECT SUM(p.Quantity * ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1))
                           FROM   dbo.WaterRawMaterialPurchases p
                           WHERE  p.WaterRawMaterialItemId = i.WaterRawMaterialItemId AND p.FarmId = i.FarmId), 0)
                 - ISNULL((SELECT SUM(u.QuantityUsed)
                           FROM   dbo.WaterRawMaterialUsage u
                           WHERE  u.WaterRawMaterialItemId = i.WaterRawMaterialItemId AND u.FarmId = i.FarmId), 0)
               AS DECIMAL(14,3)) AS RawExpected
        FROM   dbo.WaterRawMaterialItems i
        WHERE  i.FarmId = @FarmId
          AND  (@WaterRawMaterialItemId IS NULL OR i.WaterRawMaterialItemId = @WaterRawMaterialItemId)
    )
    SELECT WaterRawMaterialItemId,
           OldQuantity,
           CASE WHEN RawExpected < 0 THEN 0 ELSE RawExpected END AS NewQuantity
    INTO   #calc
    FROM   Expected;

    UPDATE i
    SET    CurrentQuantity = c.NewQuantity, UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.WaterRawMaterialItems i
    INNER JOIN #calc c ON c.WaterRawMaterialItemId = i.WaterRawMaterialItemId
    WHERE  i.FarmId = @FarmId AND i.CurrentQuantity <> c.NewQuantity;

    -- Report every item, changed first, with the before/after delta.
    SELECT c.WaterRawMaterialItemId,
           i.ItemName,
           i.Category,
           i.UnitOfMeasure,
           c.OldQuantity,
           c.NewQuantity,
           CAST(c.NewQuantity - c.OldQuantity AS DECIMAL(14,3)) AS Delta
    FROM   #calc c
    INNER JOIN dbo.WaterRawMaterialItems i ON i.WaterRawMaterialItemId = c.WaterRawMaterialItemId
    ORDER  BY (CASE WHEN c.OldQuantity <> c.NewQuantity THEN 0 ELSE 1 END), i.ItemName;

    DROP TABLE #calc;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_RecalculateStock TO [Techretainer];
    PRINT '176: granted EXECUTE on spWaterRawMaterialItem_RecalculateStock to Techretainer.';
END
GO

PRINT '176_WaterRawMaterialRecalcStock.sql complete.';
GO

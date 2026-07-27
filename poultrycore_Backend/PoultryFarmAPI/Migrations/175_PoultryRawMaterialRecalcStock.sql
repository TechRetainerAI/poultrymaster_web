-- =============================================================================
-- 175_PoultryRawMaterialRecalcStock.sql
-- Recalculate raw-material / supply CurrentQuantity from the source ledgers.
--
-- CurrentQuantity is a stored running total. If it ever drifts (a bad edit, a
-- pre-157 purchase counted in purchase units, a manual DB change), this recomputes
-- it from the ground truth, mirroring exactly how the live SPs maintain it:
--
--   CurrentQuantity = SUM(purchase.Quantity * unitsPerPurchaseUnit)   -- 157: production units
--                   - SUM(usage.QuantityUsed)
--                   + SUM(adjustment.Quantity)                        -- 174: signed
--   (floored at 0)
--
-- Additive + idempotent (CREATE OR ALTER). Grants EXECUTE to `Techretainer`.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialItem_RecalculateStock
    @FarmId                   NVARCHAR(450),
    @PoultryRawMaterialItemId INT = NULL     -- NULL = every raw-material item for the company
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Expected AS (
        SELECT i.PoultryRawMaterialItemId,
               i.CurrentQuantity AS OldQuantity,
               CAST(
                   ISNULL((SELECT SUM(p.Quantity * ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1))
                           FROM   dbo.PoultryRawMaterialPurchases p
                           WHERE  p.PoultryRawMaterialItemId = i.PoultryRawMaterialItemId AND p.FarmId = i.FarmId), 0)
                 - ISNULL((SELECT SUM(u.QuantityUsed)
                           FROM   dbo.PoultryRawMaterialUsage u
                           WHERE  u.PoultryRawMaterialItemId = i.PoultryRawMaterialItemId AND u.FarmId = i.FarmId), 0)
                 + ISNULL((SELECT SUM(a.Quantity)
                           FROM   dbo.PoultryRawMaterialAdjustments a
                           WHERE  a.PoultryRawMaterialItemId = i.PoultryRawMaterialItemId AND a.FarmId = i.FarmId), 0)
               AS DECIMAL(14,3)) AS RawExpected
        FROM   dbo.PoultryRawMaterialItems i
        WHERE  i.FarmId = @FarmId
          AND  (@PoultryRawMaterialItemId IS NULL OR i.PoultryRawMaterialItemId = @PoultryRawMaterialItemId)
    )
    SELECT PoultryRawMaterialItemId,
           OldQuantity,
           CASE WHEN RawExpected < 0 THEN 0 ELSE RawExpected END AS NewQuantity
    INTO   #calc
    FROM   Expected;

    UPDATE i
    SET    CurrentQuantity = c.NewQuantity, UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialItems i
    INNER JOIN #calc c ON c.PoultryRawMaterialItemId = i.PoultryRawMaterialItemId
    WHERE  i.FarmId = @FarmId AND i.CurrentQuantity <> c.NewQuantity;

    -- Report every item, changed first, with the before/after delta.
    SELECT c.PoultryRawMaterialItemId,
           i.ItemName,
           i.Category,
           i.UnitOfMeasure,
           c.OldQuantity,
           c.NewQuantity,
           CAST(c.NewQuantity - c.OldQuantity AS DECIMAL(14,3)) AS Delta
    FROM   #calc c
    INNER JOIN dbo.PoultryRawMaterialItems i ON i.PoultryRawMaterialItemId = c.PoultryRawMaterialItemId
    ORDER  BY (CASE WHEN c.OldQuantity <> c.NewQuantity THEN 0 ELSE 1 END), i.ItemName;

    DROP TABLE #calc;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_RecalculateStock TO [Techretainer];
    PRINT '175: granted EXECUTE on spPoultryRawMaterialItem_RecalculateStock to Techretainer.';
END
GO

PRINT '175_PoultryRawMaterialRecalcStock.sql complete.';
GO

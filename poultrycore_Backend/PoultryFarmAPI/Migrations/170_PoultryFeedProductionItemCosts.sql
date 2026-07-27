-- =============================================================================
-- Migration 170: Feed Production — batch-form item picker (with latest cost)
-- =============================================================================
-- A single read the New Feed Production Batch form uses to populate its finished
-- feed + ingredient dropdowns: every active feed-related raw-material item with
-- its current stock and latest known per-production-unit cost. The latest cost
-- is an ESTIMATE for the cost preview; the authoritative inventory cost is drawn
-- from FIFO/LIFO/HIFO lots at post time. Read-only. Idempotent.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProduction_GetBatchItems
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.PoultryRawMaterialItemId,
           i.ItemName,
           i.Category,
           i.UnitOfMeasure,
           i.CurrentQuantity,
           i.IsActive,
           CAST(ISNULL((
               SELECT TOP 1 CASE WHEN ISNULL(p.ProductionUnitsPerPurchaseUnit,0) > 0
                                 THEN p.TotalCost / NULLIF(p.Quantity * p.ProductionUnitsPerPurchaseUnit,0)
                                 ELSE p.UnitCost END
               FROM dbo.PoultryRawMaterialPurchases p
               WHERE p.PoultryRawMaterialItemId = i.PoultryRawMaterialItemId AND p.FarmId = @FarmId
               ORDER BY p.PurchaseDate DESC, p.PoultryRawMaterialPurchaseId DESC
           ), 0) AS DECIMAL(18,4)) AS LatestUnitCost
    FROM   dbo.PoultryRawMaterialItems i
    WHERE  i.FarmId = @FarmId
      AND  i.IsActive = 1
      AND  i.Category LIKE '%Feed%'   -- FinishedFeed + FeedIngredient
    ORDER  BY i.Category, i.ItemName;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spPoultryFeedProduction_GetBatchItems TO [Techretainer];
GO

PRINT '170_PoultryFeedProductionItemCosts.sql complete.';
GO

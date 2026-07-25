-- =============================================================================
-- Migration 173: Feed Production — reports
-- =============================================================================
-- Read-only reporting SPs over POSTED feed production batches:
--   * spPoultryFeedProductionReport_IngredientUsage — per-ingredient quantity
--     used, cost, and number of batches (drives the Ingredient Usage report).
--   * spPoultryFeedProductionReport_Traceability — links produced-feed stock
--     lots to the flock production records that later consumed them, via the
--     usage-batch ledger (SourceFeedProductionBatchId -> produced lot -> draws).
-- The Feed Production summary and Feed Cost trend are served from the existing
-- batch GetAll (filtered to Posted) on the client. Idempotent.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProductionReport_IngredientUsage
    @FarmId NVARCHAR(450), @FromDate DATETIME2 = NULL, @ToDate DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT l.IngredientItemId,
           i.ItemName        AS IngredientName,
           i.UnitOfMeasure   AS UnitOfMeasure,
           CAST(SUM(l.QuantityUsed) AS DECIMAL(18,3)) AS TotalQuantityUsed,
           CAST(SUM(l.TotalCost)    AS DECIMAL(18,2)) AS TotalCost,
           CAST(SUM(CASE WHEN l.SourceType = 'FromInventory' THEN l.QuantityUsed
                         WHEN l.SourceType = 'MixedSource'   THEN ISNULL(l.InventoryQuantityUsed,0)
                         ELSE 0 END) AS DECIMAL(18,3)) AS FromInventoryQuantity,
           CAST(SUM(CASE WHEN l.SourceType = 'BoughtDuringProduction' THEN l.QuantityUsed
                         WHEN l.SourceType = 'MixedSource'            THEN ISNULL(l.PurchasedQuantityUsed,0)
                         ELSE 0 END) AS DECIMAL(18,3)) AS PurchasedQuantity,
           COUNT(DISTINCT b.PoultryFeedProductionBatchId) AS BatchCount
    FROM   dbo.PoultryFeedProductionBatchLines l
    INNER  JOIN dbo.PoultryFeedProductionBatches b ON b.PoultryFeedProductionBatchId = l.PoultryFeedProductionBatchId
    INNER  JOIN dbo.PoultryRawMaterialItems i ON i.PoultryRawMaterialItemId = l.IngredientItemId
    WHERE  b.FarmId = @FarmId AND b.Status = 'Posted'
      AND  (@FromDate IS NULL OR b.ProductionDate >= @FromDate)
      AND  (@ToDate   IS NULL OR b.ProductionDate < DATEADD(DAY, 1, @ToDate))
    GROUP  BY l.IngredientItemId, i.ItemName, i.UnitOfMeasure
    ORDER  BY TotalCost DESC;
END
GO

-- Traceability: which flock production records consumed each produced feed batch.
-- Produced lot (SourceFeedProductionBatchId) -> usage-batch draws -> usage rows
-- -> ProductionRecords (flock). Rows only appear once produced feed is used.
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProductionReport_Traceability
    @FarmId NVARCHAR(450), @PoultryFeedProductionBatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT b.PoultryFeedProductionBatchId, b.BatchNumber, b.FinishedFeedItemId,
           fi.ItemName AS FinishedFeedName,
           u.PoultryRawMaterialUsageId,
           u.ProductionRecordId,
           u.QuantityUsed,
           ub.QuantityDrawn,
           ub.UnitCostAtDraw,
           u.UsedDate
    FROM   dbo.PoultryFeedProductionBatches b
    INNER  JOIN dbo.PoultryRawMaterialItems fi ON fi.PoultryRawMaterialItemId = b.FinishedFeedItemId
    INNER  JOIN dbo.PoultryRawMaterialPurchases p ON p.SourceFeedProductionBatchId = b.PoultryFeedProductionBatchId AND p.PoultryRawMaterialItemId = b.FinishedFeedItemId
    INNER  JOIN dbo.PoultryRawMaterialUsageBatch ub ON ub.PoultryRawMaterialPurchaseId = p.PoultryRawMaterialPurchaseId
    INNER  JOIN dbo.PoultryRawMaterialUsage u ON u.PoultryRawMaterialUsageId = ub.PoultryRawMaterialUsageId
    WHERE  b.FarmId = @FarmId AND b.PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId
    ORDER  BY u.UsedDate DESC;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryFeedProductionReport_IngredientUsage TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryFeedProductionReport_Traceability    TO [Techretainer];
    PRINT '173: granted EXECUTE on feed production report SPs to Techretainer.';
END
GO

PRINT '173_PoultryFeedProductionReports.sql complete.';
GO

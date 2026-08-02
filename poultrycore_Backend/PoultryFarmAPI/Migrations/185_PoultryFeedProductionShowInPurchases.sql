-- =============================================================================
-- Migration 185: Feed Production lots appear in the raw-material purchase history
-- =============================================================================
-- Posting a batch already writes stock lots into dbo.PoultryRawMaterialPurchases:
--
--   * the produced finished feed  — SupplierName 'Feed Production',
--     PaymentMethod 'Production', costed at the batch's cost/unit
--   * one lot per ingredient bought during production (legacy batches only —
--     those are now bought through Record Purchase instead)
--
-- Both carry SourceFeedProductionBatchId, and migration 171 hid them from the
-- purchases ledger on the grounds that "Record Purchase" didn't create them.
-- That left the farmer with no sight of stock the system had brought in, so
-- they are now returned like any other lot, tagged so the UI can tell them
-- apart and keep them read-only:
--
--   FeedProductionBatchNumber — the batch that created the lot (NULL otherwise)
--   FeedProductionRole        — 'Produced' for the finished feed the batch made,
--                               'Purchased' for an ingredient it bought,
--                               NULL for an ordinary purchase
--
-- Read-only change: no schema, no data, no posting behaviour. The lots were
-- always there and always counted towards stock; only the ledger's filter moves.
-- Idempotent. Safe to re-run.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Body as migration 171 minus the "SourceFeedProductionBatchId IS NULL" filter,
-- plus the two descriptive columns. Everything else — the derived Balance,
-- ProductionQuantity and ProductionUnitCost, the date range, the ordering —
-- is unchanged, so existing callers see exactly what they saw before plus the
-- previously hidden rows.
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialPurchase_GetAll
    @FarmId NVARCHAR(450), @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.*,
           i.ItemName, i.Category, i.UnitOfMeasure,
           CAST(p.TotalCost - p.AmountPaid AS DECIMAL(14,2)) AS Balance,
           CAST(p.Quantity * ISNULL(p.ProductionUnitsPerPurchaseUnit, 1) AS DECIMAL(18,3)) AS ProductionQuantity,
           CAST(CASE WHEN ISNULL(p.ProductionUnitsPerPurchaseUnit, 0) > 0
                     THEN p.TotalCost / NULLIF(p.Quantity * p.ProductionUnitsPerPurchaseUnit, 0)
                     ELSE NULL END AS DECIMAL(18,4)) AS ProductionUnitCost,
           b.BatchNumber AS FeedProductionBatchNumber,
           CASE WHEN b.PoultryFeedProductionBatchId IS NULL THEN NULL
                WHEN b.FinishedFeedItemId = p.PoultryRawMaterialItemId THEN 'Produced'
                ELSE 'Purchased' END AS FeedProductionRole
    FROM   dbo.PoultryRawMaterialPurchases p
    INNER  JOIN dbo.PoultryRawMaterialItems i ON i.PoultryRawMaterialItemId = p.PoultryRawMaterialItemId
    LEFT   JOIN dbo.PoultryFeedProductionBatches b
           ON b.PoultryFeedProductionBatchId = p.SourceFeedProductionBatchId
    WHERE  p.FarmId = @FarmId
       AND (@FromDate IS NULL OR CAST(p.PurchaseDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(p.PurchaseDate AS DATE) <= @ToDate)
    ORDER  BY p.PurchaseDate DESC, p.PoultryRawMaterialPurchaseId DESC;
END
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'Techretainer')
BEGIN
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_GetAll TO [Techretainer];
    PRINT '185: granted EXECUTE on spPoultryRawMaterialPurchase_GetAll to Techretainer.';
END
GO

PRINT '185_PoultryFeedProductionShowInPurchases.sql complete.';
GO

-- =============================================================================
-- Migration 186: label feed-production draws in the raw-material usage history
-- =============================================================================
-- Posting a batch writes one dbo.PoultryRawMaterialUsage row per ingredient it
-- consumes, stamped with PoultryFeedProductionBatchId (migration 171). Unlike
-- the purchase lots, these were never filtered out — they have always shown in
-- Usage History. What they lacked was any sign of where they came from: a row
-- reading "Maize 250" gave no clue whether a flock ate it or a feed batch did.
--
-- The list now carries the batch alongside each draw:
--
--   FeedProductionBatchNumber — the batch that consumed it (NULL otherwise)
--   FeedProductionFeedName    — the finished feed that batch produced
--
-- The column PoultryFeedProductionBatchId already comes through on u.*, so the
-- UI can link the row straight to its batch.
--
-- Read-only change: no schema, no data, no posting behaviour. Idempotent.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Body as migration 123 plus the batch join. Filters, ordering and every
-- existing column are unchanged, so callers see exactly what they saw before.
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialUsage_GetHistory
    @FarmId NVARCHAR(450),
    @PoultryRawMaterialItemId INT = NULL,
    @FromDate DATE = NULL,
    @ToDate   DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.*, i.ItemName, i.UnitOfMeasure,
           b.BatchNumber AS FeedProductionBatchNumber,
           fi.ItemName   AS FeedProductionFeedName
    FROM   dbo.PoultryRawMaterialUsage u
    INNER  JOIN dbo.PoultryRawMaterialItems i ON i.PoultryRawMaterialItemId = u.PoultryRawMaterialItemId
    LEFT   JOIN dbo.PoultryFeedProductionBatches b
           ON b.PoultryFeedProductionBatchId = u.PoultryFeedProductionBatchId
    LEFT   JOIN dbo.PoultryRawMaterialItems fi
           ON fi.PoultryRawMaterialItemId = b.FinishedFeedItemId
    WHERE  u.FarmId = @FarmId
       AND (@PoultryRawMaterialItemId IS NULL OR u.PoultryRawMaterialItemId = @PoultryRawMaterialItemId)
       AND (@FromDate IS NULL OR CAST(u.UsedDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(u.UsedDate AS DATE) <= @ToDate)
    ORDER  BY u.UsedDate DESC, u.PoultryRawMaterialUsageId DESC;
END
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'Techretainer')
BEGIN
    GRANT EXECUTE ON dbo.spPoultryRawMaterialUsage_GetHistory TO [Techretainer];
    PRINT '186: granted EXECUTE on spPoultryRawMaterialUsage_GetHistory to Techretainer.';
END
GO

PRINT '186_PoultryFeedProductionUsageHistory.sql complete.';
GO

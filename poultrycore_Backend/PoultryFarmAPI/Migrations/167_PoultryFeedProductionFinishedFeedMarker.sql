-- =============================================================================
-- Migration 167: Feed Production — Phase 1 foundation (finished-feed marker)
-- =============================================================================
-- Adds the FinishedFeed item type to the poultry raw-material inventory model.
-- 'FinishedFeed' is a new Category value for dbo.PoultryRawMaterialItems (the
-- Category column is free-text/convention-enforced, so NO schema change is
-- needed for the category itself — the UI now offers it). Produced finished feed
-- is stocked as a PoultryRawMaterialItems row so it flows into the existing
-- flock feed-consumption path (ProductionRecords multi-feed), exactly like a
-- bought ingredient.
--
-- What this migration DOES change: the Feed Production posting engine (a later
-- slice) will (a) insert a produced stock lot into dbo.PoultryRawMaterialPurchases
-- for the finished feed at the computed cost/unit, and (b) insert short-lived
-- "bought during production" ingredient lots. Both need to be distinguishable
-- from ordinary purchases — so the purchase ledger can exclude them, reports can
-- separate produced vs bought stock, and reversal can find and remove them.
-- This migration adds that marker column ONLY. All batch/formula tables and the
-- posting/reversal SPs land in later, self-contained slices.
--
-- Additive + idempotent (column guard). Safe to re-run.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Marks a purchase row that was created by the Feed Production posting engine
-- rather than by a real "Record Purchase". Non-NULL => produced/consumed lot
-- belonging to the given feed-production batch. NULL => an ordinary purchase.
IF COL_LENGTH('dbo.PoultryRawMaterialPurchases', 'SourceFeedProductionBatchId') IS NULL
    ALTER TABLE dbo.PoultryRawMaterialPurchases ADD SourceFeedProductionBatchId INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PoultryRMPurchases_FeedProductionBatch'
               AND object_id = OBJECT_ID('dbo.PoultryRawMaterialPurchases'))
    CREATE INDEX IX_PoultryRMPurchases_FeedProductionBatch
        ON dbo.PoultryRawMaterialPurchases (SourceFeedProductionBatchId)
        WHERE SourceFeedProductionBatchId IS NOT NULL;
GO

PRINT '167_PoultryFeedProductionFinishedFeedMarker.sql complete.';
GO

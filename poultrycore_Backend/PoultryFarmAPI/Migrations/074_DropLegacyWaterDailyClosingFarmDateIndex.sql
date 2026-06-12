-- =============================================================================
-- Migration 074: Drop legacy unfiltered unique index on WaterDailyClosings
-- =============================================================================
-- Self-test of migration 073 revealed a SECOND blocker for the
-- Reopen → Resubmit flow:
--
--   Msg 2601: Cannot insert duplicate key row in object
--     'dbo.WaterDailyClosings' with unique index 'UX_WaterDailyClosings_FarmDate'.
--
-- Background:
--   * Migration 043 (line 182) created `UX_WaterDailyClosings_FarmDate` as a
--     plain UNIQUE INDEX on (FarmId, ClosingDate) — no filter.
--   * Migration 068 (line 202) added a NEW filtered unique index
--     `UX_WaterDailyClosings_ActivePerFarmDate` that filters on `IsActive = 1`.
--   * Migration 068 was supposed to make multiple-rows-per-date possible
--     (one active, plus reopened/superseded history rows). The filtered
--     index does that. But the old unfiltered index was never dropped, so
--     it still rejected the new Draft inserted after a Reopen.
--
-- This migration drops the legacy index. Existence-checked so it's a
-- no-op on databases that have already had it dropped manually.
--
-- After this + migration 073 (which fixes the SP's EXISTS check), the
-- Reopen → Resubmit flow round-trips end-to-end: smoke-test on
-- PoultryMasterDev confirmed the previously-blocked Insert succeeds.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_WaterDailyClosings_FarmDate'
      AND object_id = OBJECT_ID(N'dbo.WaterDailyClosings')
)
BEGIN
    DROP INDEX UX_WaterDailyClosings_FarmDate ON dbo.WaterDailyClosings;
    PRINT '074: dropped legacy UX_WaterDailyClosings_FarmDate.';
END
ELSE
BEGIN
    PRINT '074: UX_WaterDailyClosings_FarmDate already absent — no-op.';
END
GO

-- Sanity: the filtered uniqueness from migration 068 should still be present.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_WaterDailyClosings_ActivePerFarmDate'
      AND object_id = OBJECT_ID(N'dbo.WaterDailyClosings')
)
BEGIN
    RAISERROR('Expected filtered index UX_WaterDailyClosings_ActivePerFarmDate to exist (created by migration 068). Aborting.', 16, 1);
END
GO

PRINT '074_DropLegacyWaterDailyClosingFarmDateIndex.sql complete.';
GO

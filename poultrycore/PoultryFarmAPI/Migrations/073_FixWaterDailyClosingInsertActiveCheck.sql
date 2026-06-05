-- =============================================================================
-- Migration 073: Fix spWaterDailyClosing_Insert "already exists" guard
-- =============================================================================
-- James (2026-05-30): "when we reopen a particular closing, it does not allow
-- resubmission of the closing".
--
-- Root cause: migration 044 line 337 guarded on ANY existing row for
-- (FarmId, ClosingDate):
--   IF EXISTS (SELECT 1 FROM dbo.WaterDailyClosings WHERE FarmId=@FarmId AND ClosingDate=@ClosingDate)
--   BEGIN RAISERROR('A closing already exists for that date.', 16, 1); RETURN; END
--
-- But migration 068 changed the uniqueness model:
--   * Added IsActive column.
--   * Reopen flips Status='Reopened', IsActive=0 (preserved for audit).
--   * The unique index UX_WaterDailyClosings_ActivePerFarmDate is FILTERED on
--     IsActive=1, so the DB schema allows multiple historical rows per
--     (FarmId, ClosingDate) as long as only one has IsActive=1.
--
-- The Insert SP wasn't updated to match. Result: after Reopen the old row
-- has IsActive=0 but the SP still finds it via the unfiltered EXISTS check
-- and rejects the new Draft. Resubmit therefore always fails.
--
-- This migration:
--   1. Republishes spWaterDailyClosing_Insert with the corrected guard
--      (filters on IsActive = 1).
--   2. Leaves the rest of the SP byte-for-byte identical to migration 044.
--
-- Idempotent: CREATE OR ALTER.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_Insert
    @FarmId            NVARCHAR(450),
    @ClosingDate       DATE,
    @ActualCashCounted DECIMAL(14,2) = 0,
    @ManagerNotes      NVARCHAR(2000) = NULL,
    @DifferenceReason  NVARCHAR(500)  = NULL,
    @CreatedBy         NVARCHAR(450)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Only block if there's an ACTIVE closing for this date. Migration 068
    -- introduced IsActive so reopened/superseded rows can coexist as history.
    IF EXISTS (
        SELECT 1 FROM dbo.WaterDailyClosings
        WHERE FarmId      = @FarmId
          AND ClosingDate = @ClosingDate
          AND IsActive    = 1
    )
    BEGIN
        RAISERROR('An active closing already exists for that date. Reopen it before submitting a new one.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.WaterDailyClosings (
        FarmId, ClosingDate, ActualCashCounted, ManagerNotes, DifferenceReason,
        Status, CreatedBy
    )
    VALUES (
        @FarmId, @ClosingDate, @ActualCashCounted, @ManagerNotes, @DifferenceReason,
        'Draft', @CreatedBy
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

PRINT '073_FixWaterDailyClosingInsertActiveCheck.sql complete.';
GO

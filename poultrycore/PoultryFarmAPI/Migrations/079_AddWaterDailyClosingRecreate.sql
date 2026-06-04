-- =============================================================================
-- Migration 079: spWaterDailyClosing_Recreate — one-shot Reopen-then-Insert
--                for a given closing date, with audit link to the predecessor
-- =============================================================================
-- "Three Prompts In one powerful please implement all.txt" §7.
--
-- The existing flow (migrations 044, 068, 073, 074) already supports each
-- step individually:
--
--   spWaterDailyClosing_Reopen           — flips active row to Reopened/IsActive=0
--   spWaterDailyClosing_Insert           — inserts a fresh Draft (uniqueness on
--                                          (FarmId, ClosingDate) WHERE IsActive=1)
--   spWaterDailyClosing_Submit           — recalculates aggregates from current
--                                          sales/production/expenses/etc. and
--                                          flips Status to Submitted
--   spWaterDailyClosing_LinkSuperseded   — sets old row's SupersededByClosingId
--                                          to the new row's id (audit chain)
--
-- This migration wires those into a single SP so the "Recreate Closing" button
-- on a Reopened row needs exactly one call:
--
--   EXEC spWaterDailyClosing_Recreate
--        @FarmId, @ClosingDate, @PredecessorClosingId, @CreatedBy,
--        @ActualCashCounted, @ManagerNotes, @DifferenceReason
--
-- The SP:
--   1. Validates the predecessor exists, IsActive=0, and matches @ClosingDate
--      (catches stale UI sending mismatched ids).
--   2. Inserts a new Draft for the same date. Aggregation fields stay at 0 — the
--      live-aggregation path in spWaterDailyClosing_GetById (migration 058)
--      surfaces current totals when Status='Draft', so the user sees up-to-date
--      sales/production/expense numbers in the recalculate dialog without us
--      needing to recompute server-side.
--   3. Sets the predecessor's SupersededByClosingId to the new row's id.
--   4. Returns the new WaterDailyClosingId for the frontend to navigate to.
--
-- The frontend submits the recalculated draft via the existing
-- spWaterDailyClosing_Submit path, which writes the final aggregates.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_Recreate
    @FarmId               NVARCHAR(450),
    @ClosingDate          DATE,
    @PredecessorClosingId INT,
    @CreatedBy            NVARCHAR(450) = NULL,
    @ActualCashCounted    DECIMAL(14,2) = 0,
    @ManagerNotes         NVARCHAR(2000) = NULL,
    @DifferenceReason     NVARCHAR(500)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Validate predecessor.
    DECLARE @PredStatus NVARCHAR(20), @PredActive BIT, @PredDate DATE;
    SELECT @PredStatus = Status,
           @PredActive = IsActive,
           @PredDate   = ClosingDate
    FROM   dbo.WaterDailyClosings
    WHERE  WaterDailyClosingId = @PredecessorClosingId
      AND  FarmId              = @FarmId;

    IF @PredStatus IS NULL
    BEGIN
        RAISERROR('Predecessor closing not found.', 16, 1);
        RETURN;
    END

    IF @PredActive = 1
    BEGIN
        RAISERROR('Predecessor closing is still active. Reopen it before recreating.', 16, 1);
        RETURN;
    END

    IF @PredDate <> @ClosingDate
    BEGIN
        RAISERROR('Predecessor closing date does not match @ClosingDate.', 16, 1);
        RETURN;
    END

    -- There must be no other ACTIVE closing for the same (FarmId, ClosingDate).
    IF EXISTS (
        SELECT 1 FROM dbo.WaterDailyClosings
        WHERE FarmId = @FarmId AND ClosingDate = @ClosingDate AND IsActive = 1
    )
    BEGIN
        RAISERROR('An active closing already exists for that date. Reopen it first.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    -- Insert the fresh Draft. Aggregation fields default to 0; the GetById SP
    -- (migration 058) substitutes live totals while Status='Draft' so the user
    -- sees current numbers in the recalculate review screen.
    INSERT INTO dbo.WaterDailyClosings (
        FarmId, ClosingDate, ActualCashCounted, ManagerNotes, DifferenceReason,
        Status, CreatedBy
    )
    VALUES (
        @FarmId, @ClosingDate, @ActualCashCounted, @ManagerNotes, @DifferenceReason,
        'Draft', @CreatedBy
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    -- Link the predecessor to the new row.
    UPDATE dbo.WaterDailyClosings
    SET    SupersededByClosingId = @NewId,
           UpdatedAt             = SYSUTCDATETIME()
    WHERE  WaterDailyClosingId   = @PredecessorClosingId
      AND  FarmId                = @FarmId;

    COMMIT TRANSACTION;

    SELECT @NewId AS WaterDailyClosingId;
END
GO

-- Grants (idempotent — same pattern as migrations 069/072/075/076)
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'PoultryAppRole' AND type = N'R')
    GRANT EXECUTE ON dbo.spWaterDailyClosing_Recreate TO PoultryAppRole;
GO
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'Techretainer')
    GRANT EXECUTE ON dbo.spWaterDailyClosing_Recreate TO Techretainer;
GO

PRINT '079_AddWaterDailyClosingRecreate.sql complete.';
GO

-- =============================================================================
-- Migration 062: WaterDailyClosing — Delete + Notes update
-- =============================================================================
-- The daily closing page had no way to undo a Draft or fix a manager-notes
-- typo on a Rejected closing. Users complained they were stuck with a Draft
-- they couldn't remove. This adds:
--   * spWaterDailyClosing_Delete       — hard-delete a Draft or Rejected closing
--   * spWaterDailyClosing_UpdateNotes  — edit managerNotes on Draft/Rejected
--                                        (closingDate is the natural key — not
--                                        editable; create a new closing for a
--                                        different date instead)
--
-- Business rules enforced in the SPs (defensive — frontend also gates):
--   * Submitted / Approved closings are immutable. Both SPs are no-ops for
--     those statuses. Caller can detect via the returned row count.
--   * FarmId filter prevents cross-tenant deletes if the API ever forwards
--     an attacker-supplied id.
--
-- Idempotent: CREATE OR ALTER. Safe to rerun.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_Delete
    @WaterDailyClosingId INT,
    @FarmId              NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DELETE FROM dbo.WaterDailyClosings
    WHERE  WaterDailyClosingId = @WaterDailyClosingId
       AND FarmId              = @FarmId
       AND [Status]            IN (N'Draft', N'Rejected');

    -- Returned to caller so the C# layer can distinguish "deleted" vs
    -- "blocked by business rule (not Draft/Rejected)".
    SELECT @@ROWCOUNT AS RowsDeleted;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_UpdateNotes
    @WaterDailyClosingId INT,
    @FarmId              NVARCHAR(450),
    @ManagerNotes        NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    UPDATE  dbo.WaterDailyClosings
    SET     ManagerNotes = @ManagerNotes,
            UpdatedAt    = SYSUTCDATETIME()
    WHERE   WaterDailyClosingId = @WaterDailyClosingId
       AND  FarmId              = @FarmId
       AND  [Status]            IN (N'Draft', N'Rejected');

    SELECT @@ROWCOUNT AS RowsUpdated;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterDailyClosing_Delete      TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterDailyClosing_UpdateNotes TO [Techretainer];
    PRINT '062: granted EXECUTE on spWaterDailyClosing_Delete + _UpdateNotes to Techretainer.';
END
GO

PRINT '062_AddWaterDailyClosingEditDelete.sql complete.';
GO

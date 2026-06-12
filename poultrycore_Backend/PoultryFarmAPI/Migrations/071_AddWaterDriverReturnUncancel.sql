-- =============================================================================
-- Migration 071: Add spWaterDriverReturn_Uncancel
-- =============================================================================
-- James (2026-05-30) requested an "Uncancel" path so a return cancelled in
-- error can be brought back to Draft and then re-reconciled. Mirrors the
-- existing spWaterDriverReturn_Cancel SP shape (migration 041) — same params,
-- inverse status guard.
--
-- Why this is safe:
--   * spWaterDriverReturn_Cancel only flips Draft → Cancelled, never touches
--     stock or cash txns (Draft returns haven't been approved, so no derived
--     rows exist). The inverse Cancelled → Draft is symmetrical: no
--     compensating restoration is required.
--   * RAISERROR if the row isn't Cancelled, so accidental double-uncancel
--     against an Approved row is rejected loudly instead of silently
--     re-routing through unexpected state.
--
-- Idempotent: CREATE OR ALTER. Grant block matches sibling migrations.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_Uncancel
    @WaterDriverReturnId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterDriverReturns
       SET Status    = 'Draft',
           UpdatedAt = SYSUTCDATETIME()
     WHERE WaterDriverReturnId = @WaterDriverReturnId
       AND FarmId              = @FarmId
       AND Status              = 'Cancelled';
    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Only Cancelled returns can be uncancelled.', 16, 1);
        RETURN;
    END
END
GO

-- EXECUTE grant — matches the loop pattern in migrations 042 / 048 / 064.
IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterDriverReturn_Uncancel TO PoultryAppRole;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterDriverReturn_Uncancel TO [Techretainer];
END
GO

PRINT '071_AddWaterDriverReturnUncancel.sql complete.';
GO

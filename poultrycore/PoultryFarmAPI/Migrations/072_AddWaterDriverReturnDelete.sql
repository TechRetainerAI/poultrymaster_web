-- =============================================================================
-- Migration 072: Add spWaterDriverReturn_Delete
-- =============================================================================
-- James (2026-05-30) asked for admin-only delete of Cancelled returns so the
-- Returns tab doesn't accumulate dead rows. Hard-deletes the header plus all
-- linked rows in reverse FK order so we don't leave orphans.
--
-- Guard: only Cancelled returns can be deleted. Approved or Draft rows are
-- rejected — those have to be reversed/cancelled first. The frontend also
-- gates the button behind permissions.isAdmin, but defence-in-depth: a
-- hand-crafted curl from an authenticated non-admin still gets rejected by
-- the SP's status check.
--
-- Cancel SP (migration 041, line 564) flips Draft → Cancelled, never touches
-- stock/cash txns. So Cancelled returns have NO derived ledger rows to
-- compensate — the delete is purely about wiping the audit trace of the
-- return itself + its items/customer-sales/expenses inputs.
--
-- Idempotent: CREATE OR ALTER, plus existence check on the status guard.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_Delete
    @WaterDriverReturnId INT,
    @FarmId              NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Pre-flight: row must exist for this farm AND be Cancelled.
    IF NOT EXISTS (
        SELECT 1 FROM dbo.WaterDriverReturns
        WHERE WaterDriverReturnId = @WaterDriverReturnId
          AND FarmId              = @FarmId
          AND Status              = 'Cancelled'
    )
    BEGIN
        RAISERROR('Only Cancelled returns can be deleted, and the row must belong to the active farm.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    -- Delete in reverse FK order.
    -- 1) Customer-sale items (nested under WaterDriverReturnCustomerSales)
    IF OBJECT_ID(N'dbo.WaterDriverReturnCustomerSaleItems', N'U') IS NOT NULL
    BEGIN
        DELETE i
          FROM dbo.WaterDriverReturnCustomerSaleItems i
          JOIN dbo.WaterDriverReturnCustomerSales s
            ON s.WaterDriverReturnCustomerSaleId = i.WaterDriverReturnCustomerSaleId
         WHERE s.WaterDriverReturnId = @WaterDriverReturnId;
    END

    -- 2) Customer sales rows
    IF OBJECT_ID(N'dbo.WaterDriverReturnCustomerSales', N'U') IS NOT NULL
        DELETE FROM dbo.WaterDriverReturnCustomerSales
         WHERE WaterDriverReturnId = @WaterDriverReturnId;

    -- 3) Delivery expenses recorded with the return
    IF OBJECT_ID(N'dbo.WaterDeliveryExpenses', N'U') IS NOT NULL
        DELETE FROM dbo.WaterDeliveryExpenses
         WHERE WaterDriverReturnId = @WaterDriverReturnId;

    -- 4) Per-product reconciliation rows
    IF OBJECT_ID(N'dbo.WaterDriverReturnItems', N'U') IS NOT NULL
        DELETE FROM dbo.WaterDriverReturnItems
         WHERE WaterDriverReturnId = @WaterDriverReturnId;

    -- 5) Header (last so the FK chain is clean)
    DELETE FROM dbo.WaterDriverReturns
     WHERE WaterDriverReturnId = @WaterDriverReturnId
       AND FarmId              = @FarmId
       AND Status              = 'Cancelled';

    COMMIT TRANSACTION;
END
GO

-- EXECUTE grants — match the pattern in migrations 042 / 048 / 064 / 071.
IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterDriverReturn_Delete TO PoultryAppRole;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterDriverReturn_Delete TO [Techretainer];
END
GO

PRINT '072_AddWaterDriverReturnDelete.sql complete.';
GO

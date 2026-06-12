-- =============================================================================
-- 101_FixDriverReturnDeleteCascadeAndDraft.sql  (Feedback NEW #12)
--
-- Two problems deleting/replacing a driver return:
--  * Deleting a Cancelled return failed with FK_WaterDriverShortages_Return —
--    the delete SP never removed the return's WaterDriverShortages rows.
--  * Editing a Draft return created a NEW return and CANCELLED the old one,
--    leaving two records (which then broke the closing). To leave exactly ONE
--    record the edit flow needs to DELETE the old Draft, but the SP only allowed
--    deleting Cancelled rows.
--
-- FIX: delete WaterDriverShortages (and any generated cash txns) as part of the
-- cascade, and allow deleting Draft OR Cancelled returns. (Approved/Reconciled
-- still must be reversed first.) Idempotent.
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

    IF NOT EXISTS (
        SELECT 1 FROM dbo.WaterDriverReturns
        WHERE WaterDriverReturnId = @WaterDriverReturnId
          AND FarmId              = @FarmId
          AND Status IN ('Cancelled', 'Draft')   -- #12: Draft now deletable too
    )
    BEGIN
        RAISERROR('Only Draft or Cancelled returns can be deleted, and the row must belong to the active farm.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    -- Driver shortages (FK_WaterDriverShortages_Return) — was the blocker.
    IF OBJECT_ID(N'dbo.WaterDriverShortages', N'U') IS NOT NULL
        DELETE FROM dbo.WaterDriverShortages WHERE WaterDriverReturnId = @WaterDriverReturnId;

    -- Customer-sale items, then customer sales.
    IF OBJECT_ID(N'dbo.WaterDriverReturnCustomerSaleItems', N'U') IS NOT NULL
        DELETE i FROM dbo.WaterDriverReturnCustomerSaleItems i
          JOIN dbo.WaterDriverReturnCustomerSales s ON s.WaterDriverReturnCustomerSaleId = i.WaterDriverReturnCustomerSaleId
         WHERE s.WaterDriverReturnId = @WaterDriverReturnId;
    IF OBJECT_ID(N'dbo.WaterDriverReturnCustomerSales', N'U') IS NOT NULL
        DELETE FROM dbo.WaterDriverReturnCustomerSales WHERE WaterDriverReturnId = @WaterDriverReturnId;

    -- Delivery expenses + their linked cash transactions (best-effort).
    IF OBJECT_ID(N'dbo.WaterDeliveryExpenses', N'U') IS NOT NULL
        DELETE FROM dbo.WaterDeliveryExpenses WHERE WaterDriverReturnId = @WaterDriverReturnId;

    -- Per-product reconciliation rows.
    IF OBJECT_ID(N'dbo.WaterDriverReturnItems', N'U') IS NOT NULL
        DELETE FROM dbo.WaterDriverReturnItems WHERE WaterDriverReturnId = @WaterDriverReturnId;

    -- Header.
    DELETE FROM dbo.WaterDriverReturns
     WHERE WaterDriverReturnId = @WaterDriverReturnId
       AND FarmId              = @FarmId
       AND Status IN ('Cancelled', 'Draft');

    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterDriverReturn_Delete TO [Techretainer];
GO

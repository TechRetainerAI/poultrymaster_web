/* ============================================================================
   112_WaterCashAccountAdjust.sql

   Manual cash-account balance adjustment (James 2026-06-14). Posts an
   AdjustmentIn/AdjustmentOut cash transaction (signed amount) and moves the
   stored balance through it — the balance is never edited directly. Used by
   the new Cash Account details page.

   Idempotent (CREATE OR ALTER).
   ============================================================================ */

CREATE OR ALTER PROCEDURE dbo.spWaterCashAccount_Adjust
    @WaterCashAccountId INT,
    @FarmId    NVARCHAR(450),
    @Amount    DECIMAL(14,2),     -- signed: + adds cash, - removes cash
    @Reason    NVARCHAR(500),
    @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF (@Amount = 0)
    BEGIN RAISERROR('Adjustment amount cannot be zero.', 16, 1); RETURN; END
    IF (@Reason IS NULL OR LTRIM(RTRIM(@Reason)) = N'')
    BEGIN RAISERROR('A reason is required for an adjustment.', 16, 1); RETURN; END
    IF NOT EXISTS (SELECT 1 FROM dbo.WaterCashAccounts WHERE WaterCashAccountId = @WaterCashAccountId AND FarmId = @FarmId)
    BEGIN RAISERROR('Cash account not found.', 16, 1); RETURN; END

    DECLARE @type NVARCHAR(30) = CASE WHEN @Amount > 0 THEN N'AdjustmentIn' ELSE N'AdjustmentOut' END;

    BEGIN TRANSACTION;

    UPDATE dbo.WaterCashAccounts
    SET    CurrentBalance = CurrentBalance + @Amount, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterCashAccountId = @WaterCashAccountId AND FarmId = @FarmId;

    DECLARE @bal DECIMAL(14,2) = (SELECT CurrentBalance FROM dbo.WaterCashAccounts WHERE WaterCashAccountId = @WaterCashAccountId);

    INSERT INTO dbo.WaterCashTransactions
        (FarmId, WaterCashAccountId, TransactionDate, TransactionType, SourceType, SourceId,
         Amount, BalanceAfterTransaction, Description, CreatedBy, ApprovedBy, ApprovedAt, CreatedAt)
    VALUES
        (@FarmId, @WaterCashAccountId, SYSUTCDATETIME(), @type, N'Adjustment', NULL,
         @Amount, @bal, @Reason, @CreatedBy, @CreatedBy, SYSUTCDATETIME(), SYSUTCDATETIME());

    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterCashAccount_Adjust TO [Techretainer];
END
GO

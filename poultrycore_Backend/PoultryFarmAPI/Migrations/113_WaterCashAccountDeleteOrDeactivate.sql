/* ============================================================================
   113_WaterCashAccountDeleteOrDeactivate.sql

   Let users remove a cash account (James 2026-06-14). An account that was
   created by mistake and has NO history is permanently deleted; an account
   that is referenced anywhere (transactions, transfers, expenses, maintenance,
   payroll) is deactivated instead (IsActive = 0) so its history stays intact.

   Returns a single row: Outcome = 'deleted' | 'deactivated'. Idempotent.
   ============================================================================ */

CREATE OR ALTER PROCEDURE dbo.spWaterCashAccount_Delete
    @WaterCashAccountId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.WaterCashAccounts WHERE WaterCashAccountId = @WaterCashAccountId AND FarmId = @FarmId)
    BEGIN RAISERROR('Cash account not found.', 16, 1); RETURN; END

    DECLARE @referenced BIT = 0;
    IF EXISTS (SELECT 1 FROM dbo.WaterCashTransactions WHERE WaterCashAccountId = @WaterCashAccountId)
        OR EXISTS (SELECT 1 FROM dbo.WaterCashTransfers WHERE FromWaterCashAccountId = @WaterCashAccountId OR ToWaterCashAccountId = @WaterCashAccountId)
        OR EXISTS (SELECT 1 FROM dbo.WaterExpenses WHERE WaterCashAccountId = @WaterCashAccountId)
        OR EXISTS (SELECT 1 FROM dbo.WaterMaintenanceLogs WHERE WaterCashAccountId = @WaterCashAccountId)
        OR EXISTS (SELECT 1 FROM dbo.WaterPayrollRuns WHERE WaterCashAccountId = @WaterCashAccountId)
        SET @referenced = 1;

    IF (@referenced = 1)
    BEGIN
        UPDATE dbo.WaterCashAccounts SET IsActive = 0, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterCashAccountId = @WaterCashAccountId AND FarmId = @FarmId;
        SELECT CAST('deactivated' AS NVARCHAR(20)) AS Outcome;
    END
    ELSE
    BEGIN
        DELETE FROM dbo.WaterCashAccounts
        WHERE  WaterCashAccountId = @WaterCashAccountId AND FarmId = @FarmId;
        SELECT CAST('deleted' AS NVARCHAR(20)) AS Outcome;
    END
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterCashAccount_Delete TO [Techretainer];
GO

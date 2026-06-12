-- =============================================================================
-- Migration 077: SupplierId on WaterExpenses + surface SupplierName + Source*
--                in spWaterExpense_GetAll / GetById, accept @SupplierId in Insert
-- =============================================================================
-- See "Three Prompts In one powerful please implement all.txt" §2, §10
-- and Prompt 2 (Populate Clickable Source Links).
--
-- What this migration does
--   1. Adds SupplierId INT NULL to dbo.WaterExpenses with a FK + index.
--   2. Rewrites spWaterExpense_GetAll and spWaterExpense_GetById to LEFT JOIN
--      WaterSuppliers (alias 'SupplierName') and to project the SourceType/
--      SourceId columns added in migration 075. This is what powers the
--      "Paid To" column and the clickable Source link on the Expenses page.
--   3. Rewrites spWaterExpense_Insert to accept @SupplierId so manual entries
--      from the Expenses form can pick a supplier. The auto-creation paths
--      (RM purchase via 078, Payroll via 075) pass SupplierId through too.
--
-- Backwards compatibility
--   * The freetext PaidTo column is preserved. Callers that don't know about
--     suppliers keep working — PaidTo is still set/returned.
--   * Display rule (enforced frontend-side): prefer SupplierName when present,
--     otherwise fall back to PaidTo. Reports use the same precedence.
--   * The FK is NOT cascade — a soft-deleted supplier still leaves the
--     historical expense's SupplierId intact for audit. The list SP joins
--     using LEFT JOIN so a deleted supplier just shows null SupplierName and
--     the UI falls back to PaidTo.
--
-- Idempotent: ADD COLUMN is COL_LENGTH-guarded; CREATE OR ALTER is idempotent.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Schema additions
-- -----------------------------------------------------------------------------
IF COL_LENGTH(N'dbo.WaterExpenses', N'SupplierId') IS NULL
    ALTER TABLE dbo.WaterExpenses ADD SupplierId INT NULL;
GO

-- FK is a soft reference: ON DELETE NO ACTION because suppliers are soft-deleted.
IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = N'FK_WaterExpenses_Supplier'
      AND parent_object_id = OBJECT_ID(N'dbo.WaterExpenses')
)
    ALTER TABLE dbo.WaterExpenses
        ADD CONSTRAINT FK_WaterExpenses_Supplier
            FOREIGN KEY (SupplierId) REFERENCES dbo.WaterSuppliers(WaterSupplierId);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_WaterExpenses_Supplier'
      AND object_id = OBJECT_ID(N'dbo.WaterExpenses')
)
    CREATE INDEX IX_WaterExpenses_Supplier ON dbo.WaterExpenses (SupplierId)
        WHERE SupplierId IS NOT NULL;
GO

-- -----------------------------------------------------------------------------
-- 2. spWaterExpense_GetAll — adds SupplierId, SupplierName, SourceType, SourceId
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterExpense_GetAll
    @FarmId     NVARCHAR(450),
    @Status     NVARCHAR(20)  = NULL,
    @FromDate   DATETIME2     = NULL,
    @ToDate     DATETIME2     = NULL,
    @SupplierId INT           = NULL,
    @SourceType NVARCHAR(40)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT e.WaterExpenseId, e.FarmId, e.ExpenseDate,
           e.WaterExpenseCategoryId, c.Name AS CategoryName,
           e.Description, e.Amount, e.PaidTo, e.PaymentMethod,
           e.WaterCashAccountId, ca.AccountName AS CashAccountName,
           e.ReceiptUrl,
           e.LinkedWaterVehicleId, e.LinkedWaterMachineId, e.LinkedWaterProductionBatchId,
           e.Status, e.Notes,
           e.SupplierId,
           s.SupplierName AS SupplierName,
           e.SourceType, e.SourceId,
           e.CreatedBy, e.ApprovedBy, e.ApprovedAt,
           e.CreatedAt, e.UpdatedAt
    FROM   dbo.WaterExpenses e
    INNER  JOIN dbo.WaterExpenseCategories c ON c.WaterExpenseCategoryId = e.WaterExpenseCategoryId
    LEFT   JOIN dbo.WaterCashAccounts ca     ON ca.WaterCashAccountId   = e.WaterCashAccountId
    LEFT   JOIN dbo.WaterSuppliers s         ON s.WaterSupplierId       = e.SupplierId
    WHERE  e.FarmId = @FarmId AND e.IsDeleted = 0
       AND (@Status     IS NULL OR e.Status     = @Status)
       AND (@FromDate   IS NULL OR e.ExpenseDate >= @FromDate)
       AND (@ToDate     IS NULL OR e.ExpenseDate <= @ToDate)
       AND (@SupplierId IS NULL OR e.SupplierId  = @SupplierId)
       AND (@SourceType IS NULL OR e.SourceType  = @SourceType)
    ORDER  BY e.ExpenseDate DESC, e.WaterExpenseId DESC;
END
GO

-- -----------------------------------------------------------------------------
-- 3. spWaterExpense_GetById — same projection
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterExpense_GetById
    @WaterExpenseId INT,
    @FarmId         NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT e.WaterExpenseId, e.FarmId, e.ExpenseDate,
           e.WaterExpenseCategoryId, c.Name AS CategoryName,
           e.Description, e.Amount, e.PaidTo, e.PaymentMethod,
           e.WaterCashAccountId, ca.AccountName AS CashAccountName,
           e.ReceiptUrl,
           e.LinkedWaterVehicleId, e.LinkedWaterMachineId, e.LinkedWaterProductionBatchId,
           e.Status, e.Notes,
           e.SupplierId,
           s.SupplierName AS SupplierName,
           e.SourceType, e.SourceId,
           e.CreatedBy, e.ApprovedBy, e.ApprovedAt,
           e.CreatedAt, e.UpdatedAt
    FROM   dbo.WaterExpenses e
    INNER  JOIN dbo.WaterExpenseCategories c ON c.WaterExpenseCategoryId = e.WaterExpenseCategoryId
    LEFT   JOIN dbo.WaterCashAccounts ca     ON ca.WaterCashAccountId   = e.WaterCashAccountId
    LEFT   JOIN dbo.WaterSuppliers s         ON s.WaterSupplierId       = e.SupplierId
    WHERE  e.WaterExpenseId = @WaterExpenseId AND e.FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- 4. spWaterExpense_Insert — accept @SupplierId. PaidTo still freetext.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterExpense_Insert
    @FarmId                       NVARCHAR(450),
    @ExpenseDate                  DATETIME2     = NULL,
    @WaterExpenseCategoryId       INT,
    @Description                  NVARCHAR(500) = NULL,
    @Amount                       DECIMAL(14,2),
    @PaidTo                       NVARCHAR(200) = NULL,
    @PaymentMethod                NVARCHAR(20)  = 'Cash',
    @WaterCashAccountId           INT           = NULL,
    @ReceiptUrl                   NVARCHAR(500) = NULL,
    @LinkedWaterVehicleId         INT           = NULL,
    @LinkedWaterMachineId         INT           = NULL,
    @LinkedWaterProductionBatchId INT           = NULL,
    @Notes                        NVARCHAR(1000)= NULL,
    @CreatedBy                    NVARCHAR(450) = NULL,
    @SupplierId                   INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@Amount <= 0) BEGIN RAISERROR('Expense amount must be greater than zero.', 16, 1); RETURN; END
    IF (@PaymentMethod <> 'Credit' AND @WaterCashAccountId IS NULL)
    BEGIN RAISERROR('Cash account is required for non-credit expenses.', 16, 1); RETURN; END

    INSERT INTO dbo.WaterExpenses (
        FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount, PaidTo,
        PaymentMethod, WaterCashAccountId, ReceiptUrl,
        LinkedWaterVehicleId, LinkedWaterMachineId, LinkedWaterProductionBatchId,
        Status, Notes, CreatedBy, SupplierId
    )
    VALUES (
        @FarmId, ISNULL(@ExpenseDate, SYSUTCDATETIME()), @WaterExpenseCategoryId, @Description, @Amount, @PaidTo,
        @PaymentMethod, @WaterCashAccountId, @ReceiptUrl,
        @LinkedWaterVehicleId, @LinkedWaterMachineId, @LinkedWaterProductionBatchId,
        'Draft', @Notes, @CreatedBy, @SupplierId
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

PRINT '077_AddSupplierIdToWaterExpenses.sql complete.';
GO

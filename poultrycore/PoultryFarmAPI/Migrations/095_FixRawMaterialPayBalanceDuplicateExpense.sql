-- =============================================================================
-- 095_FixRawMaterialPayBalanceDuplicateExpense.sql  (Feedback #21)
--
-- BUG: recording a balance payment on a raw-material purchase always failed —
-- both for partial and full amounts. Root cause: spWaterRawMaterialPurchase_
-- PayBalance (mig 091) tried to INSERT a NEW WaterExpenses row keyed by
-- (FarmId, SourceType='RawMaterialPurchase', SourceId), but the filtered unique
-- index UX_WaterExpenses_FarmSource_Active already holds the purchase's original
-- auto-created expense, so the insert hit a duplicate-key (Msg 2601) every time.
--
-- FIX: a purchase has ONE linked expense whose Amount mirrors the total amount
-- paid (feedback #11.2). A balance payment therefore UPDATES that expense's
-- Amount to the new running total (AmountPaid) and posts an incremental cash-out
-- for just the delta paid now (cash transactions have no source-unique index, so
-- each payment keeps its own ledger row).
--
-- Idempotent (CREATE OR ALTER).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_PayBalance
    @WaterRawMaterialPurchaseId INT,
    @FarmId                     NVARCHAR(450),
    @Amount                     DECIMAL(14,2),
    @PaymentMethod              NVARCHAR(30)  = NULL,
    @PaymentDate                DATETIME2     = NULL,
    @CreatedBy                  NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ItemId INT, @Total DECIMAL(14,2), @Paid DECIMAL(14,2),
            @SupplierName NVARCHAR(200), @SupplierId INT, @ItemName NVARCHAR(150);

    SELECT @ItemId       = p.WaterRawMaterialItemId,
           @Total        = p.TotalCost,
           @Paid         = p.AmountPaid,
           @SupplierName = p.SupplierName,
           @SupplierId   = p.SupplierId,
           @ItemName     = i.ItemName
    FROM   dbo.WaterRawMaterialPurchases p
    LEFT   JOIN dbo.WaterRawMaterialItems i ON i.WaterRawMaterialItemId = p.WaterRawMaterialItemId
    WHERE  p.WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND p.FarmId = @FarmId;

    IF (@ItemId IS NULL) BEGIN RAISERROR('Purchase not found for this company.', 16, 1); RETURN; END

    DECLARE @Outstanding DECIMAL(14,2) = @Total - @Paid;
    IF (@Outstanding <= 0) BEGIN RAISERROR('This purchase has no outstanding balance.', 16, 1); RETURN; END
    IF (@Amount IS NULL OR @Amount <= 0) BEGIN RAISERROR('Payment amount must be greater than 0.', 16, 1); RETURN; END
    IF (@Amount > @Outstanding) SET @Amount = @Outstanding;  -- never overpay

    DECLARE @NewPaid DECIMAL(14,2) = @Paid + @Amount;

    DECLARE @CashAccountId INT;
    SELECT TOP 1 @CashAccountId = WaterCashAccountId
    FROM   dbo.WaterCashAccounts
    WHERE  FarmId = @FarmId AND IsActive = 1
    ORDER  BY WaterCashAccountId;

    DECLARE @EffectivePaymentMethod NVARCHAR(30) =
        CASE WHEN @PaymentMethod IN ('Cash','MoMo','Bank','Card','Mixed') THEN @PaymentMethod ELSE 'Cash' END;

    BEGIN TRANSACTION;

    UPDATE dbo.WaterRawMaterialPurchases
    SET    AmountPaid = @NewPaid,
           UpdatedAt  = SYSUTCDATETIME()
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    -- The purchase's single linked expense mirrors total amount paid.
    DECLARE @ExpenseId INT;
    SELECT @ExpenseId = WaterExpenseId
    FROM   dbo.WaterExpenses
    WHERE  FarmId = @FarmId AND SourceType = N'RawMaterialPurchase'
           AND SourceId = @WaterRawMaterialPurchaseId AND IsDeleted = 0;

    IF (@ExpenseId IS NOT NULL)
    BEGIN
        UPDATE dbo.WaterExpenses
        SET    Amount        = @NewPaid,
               Status        = 'Approved',
               ApprovedBy    = ISNULL(ApprovedBy, @CreatedBy),
               ApprovedAt    = ISNULL(ApprovedAt, SYSUTCDATETIME()),
               PaymentMethod = @EffectivePaymentMethod
        WHERE  WaterExpenseId = @ExpenseId;
    END
    ELSE
    BEGIN
        -- No linked expense yet (older purchase): create it for the total paid.
        DECLARE @CatId INT;
        EXEC dbo.spWaterExpenseCategory_EnsureRawMaterialPurchase @FarmId = @FarmId;
        SELECT @CatId = WaterExpenseCategoryId FROM dbo.WaterExpenseCategories
        WHERE  FarmId = @FarmId AND Name = N'Raw Materials / Inventory Purchase';

        INSERT INTO dbo.WaterExpenses
            (FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount, PaidTo,
             PaymentMethod, WaterCashAccountId, LinkedWaterProductionBatchId,
             Status, Notes, CreatedBy, ApprovedBy, ApprovedAt, SupplierId, SourceType, SourceId)
        VALUES
            (@FarmId, ISNULL(@PaymentDate, SYSUTCDATETIME()), @CatId,
             CONCAT(N'Raw material purchase #', @WaterRawMaterialPurchaseId, N': ',
                    ISNULL(@ItemName, N'item #' + CAST(@ItemId AS NVARCHAR(20)))),
             @NewPaid, @SupplierName, @EffectivePaymentMethod, @CashAccountId, NULL,
             'Approved', N'Auto-created from raw material purchase.', @CreatedBy, @CreatedBy,
             SYSUTCDATETIME(), @SupplierId, N'RawMaterialPurchase', @WaterRawMaterialPurchaseId);

        SET @ExpenseId = CAST(SCOPE_IDENTITY() AS INT);
    END

    -- Incremental cash-out for just the amount paid now.
    IF (@CashAccountId IS NOT NULL)
    BEGIN
        INSERT INTO dbo.WaterCashTransactions (
            FarmId, WaterCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @CashAccountId, ISNULL(@PaymentDate, SYSUTCDATETIME()), 'CashOut',
            'Expense', @ExpenseId, -@Amount,
            CONCAT(N'Balance payment — raw material purchase #', @WaterRawMaterialPurchaseId),
            @CreatedBy, @CreatedBy, SYSUTCDATETIME()
        );

        UPDATE dbo.WaterCashAccounts
        SET    CurrentBalance = CurrentBalance - @Amount, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterCashAccountId = @CashAccountId;
    END

    COMMIT TRANSACTION;

    SELECT CAST(TotalCost - AmountPaid AS DECIMAL(14,2)) AS Balance
    FROM   dbo.WaterRawMaterialPurchases
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_PayBalance TO [Techretainer];
GO
IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_PayBalance TO PoultryAppRole;
GO

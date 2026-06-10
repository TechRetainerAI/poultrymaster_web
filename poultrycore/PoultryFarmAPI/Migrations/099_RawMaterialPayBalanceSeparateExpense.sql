-- =============================================================================
-- 099_RawMaterialPayBalanceSeparateExpense.sql  (Feedback NEW #3)
--
-- The operator wants each balance payment to appear as its OWN entry on the
-- Expenses page (with a description showing it is a balance payment on top of
-- the original purchase) — not folded into the original purchase expense.
--
-- Migration 095 UPDATED the single linked expense (to dodge the filtered unique
-- index UX_WaterExpenses_FarmSource_Active on (FarmId,SourceType,SourceId) WHERE
-- SourceType IS NOT NULL). This version instead INSERTS a NEW expense for the
-- balance payment with SourceType = NULL — which the filtered index ignores, so
-- any number of balance payments can each be their own row.
--
-- Still: increments AmountPaid, posts the incremental cash-out, returns the new
-- outstanding balance. Idempotent.
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
    IF (@Amount > @Outstanding) SET @Amount = @Outstanding;

    DECLARE @NewPaid DECIMAL(14,2) = @Paid + @Amount;
    DECLARE @NewBalance DECIMAL(14,2) = @Total - @NewPaid;

    EXEC dbo.spWaterExpenseCategory_EnsureRawMaterialPurchase @FarmId = @FarmId;
    DECLARE @CatId INT;
    SELECT @CatId = WaterExpenseCategoryId FROM dbo.WaterExpenseCategories
    WHERE  FarmId = @FarmId AND Name = N'Raw Materials / Inventory Purchase';

    DECLARE @CashAccountId INT;
    SELECT TOP 1 @CashAccountId = WaterCashAccountId FROM dbo.WaterCashAccounts
    WHERE  FarmId = @FarmId AND IsActive = 1 ORDER BY WaterCashAccountId;

    DECLARE @EffectivePaymentMethod NVARCHAR(30) =
        CASE WHEN @PaymentMethod IN ('Cash','MoMo','Bank','Card','Mixed') THEN @PaymentMethod ELSE 'Cash' END;

    BEGIN TRANSACTION;

    UPDATE dbo.WaterRawMaterialPurchases
    SET    AmountPaid = @NewPaid, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    -- NEW separate expense for THIS balance payment (SourceType NULL => exempt
    -- from the per-source unique index, so multiple payments are allowed).
    DECLARE @ExpenseId INT = NULL;
    IF (@CatId IS NOT NULL)
    BEGIN
        INSERT INTO dbo.WaterExpenses
            (FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount, PaidTo,
             PaymentMethod, WaterCashAccountId, LinkedWaterProductionBatchId,
             Status, Notes, CreatedBy, ApprovedBy, ApprovedAt, SupplierId, SourceType, SourceId)
        VALUES
            (@FarmId, ISNULL(@PaymentDate, SYSUTCDATETIME()), @CatId,
             CONCAT(N'Balance payment for raw material purchase #', @WaterRawMaterialPurchaseId,
                    N' (', ISNULL(@ItemName, N'item #' + CAST(@ItemId AS NVARCHAR(20))), N'): paid ',
                    CAST(@Amount AS NVARCHAR(30)), N', remaining balance ', CAST(@NewBalance AS NVARCHAR(30))),
             @Amount, @SupplierName, @EffectivePaymentMethod, @CashAccountId, NULL,
             'Approved', N'Balance payment on top of the original raw material purchase.',
             @CreatedBy, @CreatedBy, SYSUTCDATETIME(), @SupplierId, NULL, NULL);

        SET @ExpenseId = CAST(SCOPE_IDENTITY() AS INT);

        IF (@CashAccountId IS NOT NULL)
        BEGIN
            INSERT INTO dbo.WaterCashTransactions (
                FarmId, WaterCashAccountId, TransactionDate, TransactionType,
                SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt)
            VALUES (
                @FarmId, @CashAccountId, ISNULL(@PaymentDate, SYSUTCDATETIME()), 'CashOut',
                'Expense', @ExpenseId, -@Amount,
                CONCAT(N'Balance payment — raw material purchase #', @WaterRawMaterialPurchaseId),
                @CreatedBy, @CreatedBy, SYSUTCDATETIME());

            UPDATE dbo.WaterCashAccounts
            SET    CurrentBalance = CurrentBalance - @Amount, UpdatedAt = SYSUTCDATETIME()
            WHERE  WaterCashAccountId = @CashAccountId;
        END
    END

    COMMIT TRANSACTION;

    SELECT @NewBalance AS Balance;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_PayBalance TO [Techretainer];
GO
IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_PayBalance TO PoultryAppRole;
GO

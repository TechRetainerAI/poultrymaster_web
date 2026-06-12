-- =============================================================================
-- 091_AddRawMaterialPurchasePayBalance.sql
--
-- Feedback #11, Problem 3: "How do you pay the balance, and how are balance
-- payments recorded as expenses when they get paid?"
--
-- Adds spWaterRawMaterialPurchase_PayBalance: records a follow-up payment against
-- an existing raw-material purchase that still has an outstanding balance
-- (TotalCost - AmountPaid > 0). It:
--   * caps the payment at the outstanding balance,
--   * increases the purchase's AmountPaid,
--   * posts a NEW Approved expense (Raw Materials / Inventory Purchase) for the
--     amount paid — so each real cash outflow shows on the Expense page,
--   * posts the matching cash-out + decrements the cash account (unless Credit),
--   * returns the new outstanding Balance.
--
-- Mirrors the cash/expense logic of spWaterRawMaterialPurchase_Insert (mig 090)
-- so balance payments behave exactly like the initial part-payment.
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

    EXEC dbo.spWaterExpenseCategory_EnsureRawMaterialPurchase @FarmId = @FarmId;
    DECLARE @CatId INT;
    SELECT @CatId = WaterExpenseCategoryId
    FROM   dbo.WaterExpenseCategories
    WHERE  FarmId = @FarmId AND Name = N'Raw Materials / Inventory Purchase';

    DECLARE @CashAccountId INT;
    SELECT TOP 1 @CashAccountId = WaterCashAccountId
    FROM   dbo.WaterCashAccounts
    WHERE  FarmId = @FarmId AND IsActive = 1
    ORDER  BY WaterCashAccountId;

    DECLARE @EffectivePaymentMethod NVARCHAR(30) =
        CASE
            WHEN @PaymentMethod IN ('Cash','MoMo','Bank','Card','Mixed') THEN @PaymentMethod
            WHEN @CashAccountId IS NULL THEN 'Cash'
            ELSE 'Cash'
        END;

    BEGIN TRANSACTION;

    UPDATE dbo.WaterRawMaterialPurchases
    SET    AmountPaid = AmountPaid + @Amount,
           UpdatedAt  = SYSUTCDATETIME()
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    DECLARE @ExpenseId INT = NULL;
    IF (@CatId IS NOT NULL)
    BEGIN
        INSERT INTO dbo.WaterExpenses
            (FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount, PaidTo,
             PaymentMethod, WaterCashAccountId, LinkedWaterProductionBatchId,
             Status, Notes, CreatedBy, ApprovedBy, ApprovedAt,
             SupplierId, SourceType, SourceId)
        VALUES
            (@FarmId, ISNULL(@PaymentDate, SYSUTCDATETIME()), @CatId,
             CONCAT(N'Balance payment for raw material purchase #', @WaterRawMaterialPurchaseId,
                    N': ', ISNULL(@ItemName, N'item #' + CAST(@ItemId AS NVARCHAR(20)))),
             @Amount, @SupplierName,
             @EffectivePaymentMethod, @CashAccountId, NULL,
             'Approved',
             N'Auto-created from raw material purchase balance payment.',
             @CreatedBy, @CreatedBy, SYSUTCDATETIME(),
             @SupplierId, N'RawMaterialPurchase', @WaterRawMaterialPurchaseId);

        SET @ExpenseId = CAST(SCOPE_IDENTITY() AS INT);

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
    END

    COMMIT TRANSACTION;

    -- New outstanding balance for the caller.
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

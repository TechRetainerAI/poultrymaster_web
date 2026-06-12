-- =============================================================================
-- 090_RawMaterialPurchaseExpenseUsesAmountPaid.sql
--
-- Fix (feedback #11, Problem 2): when a raw-material purchase is recorded with a
-- part payment, the linked expense + cash-out posted the FULL @TotalCost instead
-- of the @AmountPaid. So the Expense page and cash balance were overstated — it
-- looked like the whole cost was paid even when only part was.
--
-- Correct (cash-basis, as requested): the auto-created expense and the cash
-- withdrawal must reflect only what was actually paid (@AmountPaid). The unpaid
-- remainder stays as the purchase Balance (TotalCost - AmountPaid, computed
-- column + migration 087) — a payable, not an expense yet. Balance payments are
-- recorded later (see the pay-balance flow) and post their own expense.
--
-- Only change vs migration 078: the expense Amount, the cash transaction amount,
-- the cash-balance decrement, and the guard now use @AmountPaid (was @TotalCost).
-- Everything else (supplier resolution, category, inventory bump, linkage) is
-- identical. Idempotent (CREATE OR ALTER).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_Insert
    @FarmId                NVARCHAR(450),
    @WaterRawMaterialItemId INT,
    @SupplierName          NVARCHAR(200) = NULL,
    @PurchaseDate          DATETIME2     = NULL,
    @Quantity              DECIMAL(14,3),
    @UnitCost              DECIMAL(14,2),
    @PaymentMethod         NVARCHAR(30)  = NULL,
    @AmountPaid            DECIMAL(14,2) = 0,
    @ReceiptUrl            NVARCHAR(500) = NULL,
    @ReceivedByStaffId     INT           = NULL,
    @Notes                 NVARCHAR(500) = NULL,
    @CreatedBy             NVARCHAR(450) = NULL,
    @SupplierId            INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@Quantity <= 0) BEGIN RAISERROR('Quantity must be > 0.', 16, 1); RETURN; END
    IF (@UnitCost < 0)  BEGIN RAISERROR('UnitCost cannot be negative.', 16, 1); RETURN; END

    DECLARE @TotalCost DECIMAL(14,2) = CAST(@Quantity AS DECIMAL(14,2)) * @UnitCost;
    -- Never let the recorded payment exceed the cost.
    IF (@AmountPaid IS NULL) SET @AmountPaid = 0;
    IF (@AmountPaid > @TotalCost) SET @AmountPaid = @TotalCost;

    DECLARE @ItemName NVARCHAR(150);
    SELECT @ItemName = ItemName FROM dbo.WaterRawMaterialItems
    WHERE  WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;

    -- If a SupplierId was supplied but no freetext name, derive the name so
    -- legacy PaidTo / SupplierName columns stay populated.
    IF (@SupplierId IS NOT NULL AND (@SupplierName IS NULL OR @SupplierName = N''))
        SELECT @SupplierName = SupplierName FROM dbo.WaterSuppliers
        WHERE  WaterSupplierId = @SupplierId AND FarmId = @FarmId;

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
            WHEN @PaymentMethod IN ('Cash','MoMo','Bank','Card','Credit','Mixed')
                THEN @PaymentMethod
            WHEN @CashAccountId IS NULL THEN 'Credit'
            ELSE 'Cash'
        END;

    BEGIN TRANSACTION;

    INSERT INTO dbo.WaterRawMaterialPurchases (
        FarmId, WaterRawMaterialItemId, SupplierName, PurchaseDate, Quantity, UnitCost,
        PaymentMethod, AmountPaid, ReceiptUrl, ReceivedByStaffId, Notes, CreatedBy,
        SupplierId
    )
    VALUES (
        @FarmId, @WaterRawMaterialItemId, @SupplierName,
        ISNULL(@PurchaseDate, SYSUTCDATETIME()), @Quantity, @UnitCost,
        @EffectivePaymentMethod, @AmountPaid, @ReceiptUrl, @ReceivedByStaffId, @Notes, @CreatedBy,
        @SupplierId
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    UPDATE dbo.WaterRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity + @Quantity, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;

    -- Auto-create the linked Approved expense for ONLY the amount actually paid.
    -- The unpaid remainder (Balance) is a payable, recorded when it is paid.
    DECLARE @ExpenseId INT = NULL;
    IF (@CatId IS NOT NULL AND @AmountPaid > 0)
    BEGIN
        INSERT INTO dbo.WaterExpenses
            (FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount, PaidTo,
             PaymentMethod, WaterCashAccountId, LinkedWaterProductionBatchId,
             Status, Notes, CreatedBy, ApprovedBy, ApprovedAt,
             SupplierId, SourceType, SourceId)
        VALUES
            (@FarmId, ISNULL(@PurchaseDate, SYSUTCDATETIME()), @CatId,
             CONCAT(N'Raw material purchase: ', ISNULL(@ItemName, N'item #' + CAST(@WaterRawMaterialItemId AS NVARCHAR(20))),
                    N' (', CAST(@Quantity AS NVARCHAR(30)), N' units)',
                    CASE WHEN @AmountPaid < @TotalCost
                         THEN CONCAT(N' — part payment of ', CAST(@AmountPaid AS NVARCHAR(30)),
                                     N' of ', CAST(@TotalCost AS NVARCHAR(30)))
                         ELSE N'' END),
             @AmountPaid, @SupplierName,
             @EffectivePaymentMethod,
             CASE WHEN @EffectivePaymentMethod = 'Credit' THEN NULL ELSE @CashAccountId END,
             NULL,
             'Approved',
             N'Auto-created from raw material purchase.',
             @CreatedBy, @CreatedBy, SYSUTCDATETIME(),
             @SupplierId, N'RawMaterialPurchase', @NewId);

        SET @ExpenseId = CAST(SCOPE_IDENTITY() AS INT);

        IF (@EffectivePaymentMethod <> 'Credit' AND @CashAccountId IS NOT NULL)
        BEGIN
            INSERT INTO dbo.WaterCashTransactions (
                FarmId, WaterCashAccountId, TransactionDate, TransactionType,
                SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
            )
            VALUES (
                @FarmId, @CashAccountId, ISNULL(@PurchaseDate, SYSUTCDATETIME()), 'CashOut',
                'Expense', @ExpenseId, -@AmountPaid,
                CONCAT(N'Raw material purchase #', @NewId),
                @CreatedBy, @CreatedBy, SYSUTCDATETIME()
            );

            UPDATE dbo.WaterCashAccounts
            SET    CurrentBalance = CurrentBalance - @AmountPaid,
                   UpdatedAt = SYSUTCDATETIME()
            WHERE  WaterCashAccountId = @CashAccountId;
        END

        UPDATE dbo.WaterRawMaterialPurchases
        SET    LinkedWaterExpenseId = @ExpenseId
        WHERE  WaterRawMaterialPurchaseId = @NewId;
    END

    COMMIT TRANSACTION;

    SELECT @NewId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Insert TO [Techretainer];
GO
IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Insert TO PoultryAppRole;
GO

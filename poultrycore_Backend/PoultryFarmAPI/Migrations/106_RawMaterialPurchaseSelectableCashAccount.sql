/* ============================================================================
   106_RawMaterialPurchaseSelectableCashAccount.sql

   Lets the operator choose WHICH cash account a raw-material purchase payment
   leaves from (same as the Expenses form), instead of the SP silently using
   the first active account.

   - spWaterRawMaterialPurchase_Insert: new @WaterCashAccountId param. When set
     (and the account is active for the farm) the auto-created expense + cash-out
     post against THAT account; otherwise it falls back to the first active
     account exactly as before (so existing callers are unaffected).
   - spWaterRawMaterialPurchase_Update: same param; re-points the linked expense
     to the chosen account for label consistency.

   Idempotent (CREATE OR ALTER). Based on migration 098.
   ============================================================================ */

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
    @SupplierId            INT           = NULL,
    @TotalCost             DECIMAL(14,2) = NULL,  -- exact entered total; NULL => Qty*UnitCost
    @WaterCashAccountId    INT           = NULL   -- caller-chosen account; NULL => first active
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@Quantity <= 0) BEGIN RAISERROR('Quantity must be > 0.', 16, 1); RETURN; END
    IF (@UnitCost < 0)  BEGIN RAISERROR('UnitCost cannot be negative.', 16, 1); RETURN; END

    IF (@TotalCost IS NULL OR @TotalCost <= 0)
        SET @TotalCost = CAST(@Quantity AS DECIMAL(14,2)) * @UnitCost;

    IF (@AmountPaid IS NULL) SET @AmountPaid = 0;
    IF (@AmountPaid > @TotalCost) SET @AmountPaid = @TotalCost;

    DECLARE @ItemName NVARCHAR(150);
    SELECT @ItemName = ItemName FROM dbo.WaterRawMaterialItems
    WHERE  WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;

    IF (@SupplierId IS NOT NULL AND (@SupplierName IS NULL OR @SupplierName = N''))
        SELECT @SupplierName = SupplierName FROM dbo.WaterSuppliers
        WHERE  WaterSupplierId = @SupplierId AND FarmId = @FarmId;

    EXEC dbo.spWaterExpenseCategory_EnsureRawMaterialPurchase @FarmId = @FarmId;
    DECLARE @CatId INT;
    SELECT @CatId = WaterExpenseCategoryId FROM dbo.WaterExpenseCategories
    WHERE  FarmId = @FarmId AND Name = N'Raw Materials / Inventory Purchase';

    -- #2: honor the caller-chosen account when given (and valid for this farm);
    -- otherwise fall back to the first active account (legacy behavior).
    DECLARE @CashAccountId INT;
    IF (@WaterCashAccountId IS NOT NULL)
        SELECT @CashAccountId = WaterCashAccountId FROM dbo.WaterCashAccounts
        WHERE  WaterCashAccountId = @WaterCashAccountId AND FarmId = @FarmId AND IsActive = 1;
    IF (@CashAccountId IS NULL)
        SELECT TOP 1 @CashAccountId = WaterCashAccountId FROM dbo.WaterCashAccounts
        WHERE  FarmId = @FarmId AND IsActive = 1 ORDER BY WaterCashAccountId;

    DECLARE @EffectivePaymentMethod NVARCHAR(30) =
        CASE WHEN @PaymentMethod IN ('Cash','MoMo','Bank','Card','Credit','Mixed') THEN @PaymentMethod
             WHEN @CashAccountId IS NULL THEN 'Credit' ELSE 'Cash' END;

    BEGIN TRANSACTION;

    INSERT INTO dbo.WaterRawMaterialPurchases (
        FarmId, WaterRawMaterialItemId, SupplierName, PurchaseDate, Quantity, UnitCost, TotalCost,
        PaymentMethod, AmountPaid, ReceiptUrl, ReceivedByStaffId, Notes, CreatedBy, SupplierId
    )
    VALUES (
        @FarmId, @WaterRawMaterialItemId, @SupplierName,
        ISNULL(@PurchaseDate, SYSUTCDATETIME()), @Quantity, @UnitCost, @TotalCost,
        @EffectivePaymentMethod, @AmountPaid, @ReceiptUrl, @ReceivedByStaffId, @Notes, @CreatedBy, @SupplierId
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    UPDATE dbo.WaterRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity + @Quantity, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;

    DECLARE @ExpenseId INT = NULL;
    IF (@CatId IS NOT NULL AND @AmountPaid > 0)
    BEGIN
        INSERT INTO dbo.WaterExpenses
            (FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount, PaidTo,
             PaymentMethod, WaterCashAccountId, LinkedWaterProductionBatchId,
             Status, Notes, CreatedBy, ApprovedBy, ApprovedAt, SupplierId, SourceType, SourceId)
        VALUES
            (@FarmId, ISNULL(@PurchaseDate, SYSUTCDATETIME()), @CatId,
             CONCAT(N'Raw material purchase: ', ISNULL(@ItemName, N'item #' + CAST(@WaterRawMaterialItemId AS NVARCHAR(20))),
                    N' (', CAST(@Quantity AS NVARCHAR(30)), N' units)',
                    CASE WHEN @AmountPaid < @TotalCost
                         THEN CONCAT(N' — part payment of ', CAST(@AmountPaid AS NVARCHAR(30)), N' of ', CAST(@TotalCost AS NVARCHAR(30)))
                         ELSE N'' END),
             @AmountPaid, @SupplierName, @EffectivePaymentMethod,
             CASE WHEN @EffectivePaymentMethod = 'Credit' THEN NULL ELSE @CashAccountId END, NULL,
             'Approved', N'Auto-created from raw material purchase.',
             @CreatedBy, @CreatedBy, SYSUTCDATETIME(), @SupplierId, N'RawMaterialPurchase', @NewId);

        SET @ExpenseId = CAST(SCOPE_IDENTITY() AS INT);

        IF (@EffectivePaymentMethod <> 'Credit' AND @CashAccountId IS NOT NULL)
        BEGIN
            INSERT INTO dbo.WaterCashTransactions (
                FarmId, WaterCashAccountId, TransactionDate, TransactionType,
                SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt)
            VALUES (
                @FarmId, @CashAccountId, ISNULL(@PurchaseDate, SYSUTCDATETIME()), 'CashOut',
                'Expense', @ExpenseId, -@AmountPaid,
                CONCAT(N'Raw material purchase #', @NewId), @CreatedBy, @CreatedBy, SYSUTCDATETIME());

            UPDATE dbo.WaterCashAccounts
            SET    CurrentBalance = CurrentBalance - @AmountPaid, UpdatedAt = SYSUTCDATETIME()
            WHERE  WaterCashAccountId = @CashAccountId;
        END

        UPDATE dbo.WaterRawMaterialPurchases SET LinkedWaterExpenseId = @ExpenseId
        WHERE  WaterRawMaterialPurchaseId = @NewId;
    END

    COMMIT TRANSACTION;
    SELECT @NewId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_Update
    @WaterRawMaterialPurchaseId INT,
    @FarmId        NVARCHAR(450),
    @SupplierName  NVARCHAR(200) = NULL,
    @PurchaseDate  DATETIME2     = NULL,
    @Quantity      DECIMAL(14,3),
    @UnitCost      DECIMAL(14,2),
    @PaymentMethod NVARCHAR(30)  = NULL,
    @AmountPaid    DECIMAL(14,2) = 0,
    @ReceiptUrl    NVARCHAR(500) = NULL,
    @Notes         NVARCHAR(500) = NULL,
    @SupplierId    INT           = NULL,
    @TotalCost     DECIMAL(14,2) = NULL,
    @WaterCashAccountId INT      = NULL   -- re-points the linked expense's account
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@Quantity <= 0) BEGIN RAISERROR('Quantity must be > 0.', 16, 1); RETURN; END
    IF (@UnitCost < 0)  BEGIN RAISERROR('UnitCost cannot be negative.', 16, 1); RETURN; END

    IF (@TotalCost IS NULL OR @TotalCost <= 0)
        SET @TotalCost = CAST(@Quantity AS DECIMAL(14,2)) * @UnitCost;

    DECLARE @OldQty DECIMAL(14,3), @ItemId INT, @LinkedExpenseId INT;
    SELECT @OldQty = Quantity, @ItemId = WaterRawMaterialItemId, @LinkedExpenseId = LinkedWaterExpenseId
    FROM   dbo.WaterRawMaterialPurchases
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @OldQty IS NULL BEGIN RAISERROR('Purchase %d not found.', 16, 1, @WaterRawMaterialPurchaseId); RETURN; END

    DECLARE @Delta DECIMAL(14,3) = @Quantity - @OldQty;
    IF (@Delta < 0)
    BEGIN
        DECLARE @CurrentStock DECIMAL(14,3) = (
            SELECT CurrentQuantity FROM dbo.WaterRawMaterialItems
            WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId);
        IF (@CurrentStock + @Delta < 0)
        BEGIN
            DECLARE @Msg1 NVARCHAR(400) = CONCAT(N'Cannot reduce quantity: only ',
                CONVERT(NVARCHAR(40), @CurrentStock), N' units of this item remain in stock. Reverse usages first.');
            RAISERROR(@Msg1, 16, 1); RETURN;
        END
    END

    IF (@SupplierId IS NOT NULL AND (@SupplierName IS NULL OR @SupplierName = N''))
        SELECT @SupplierName = SupplierName FROM dbo.WaterSuppliers
        WHERE  WaterSupplierId = @SupplierId AND FarmId = @FarmId;

    -- Resolve a valid chosen account (active, same farm); only for non-credit.
    DECLARE @UpdCashAccountId INT = NULL;
    IF (@WaterCashAccountId IS NOT NULL AND @PaymentMethod <> 'Credit')
        SELECT @UpdCashAccountId = WaterCashAccountId FROM dbo.WaterCashAccounts
        WHERE  WaterCashAccountId = @WaterCashAccountId AND FarmId = @FarmId AND IsActive = 1;

    BEGIN TRANSACTION;

    UPDATE dbo.WaterRawMaterialPurchases
    SET    SupplierName  = @SupplierName,
           SupplierId    = @SupplierId,
           PurchaseDate  = ISNULL(@PurchaseDate, PurchaseDate),
           Quantity      = @Quantity,
           UnitCost      = @UnitCost,
           TotalCost     = @TotalCost,
           PaymentMethod = @PaymentMethod,
           AmountPaid    = @AmountPaid,
           ReceiptUrl    = @ReceiptUrl,
           Notes         = @Notes,
           UpdatedAt     = SYSUTCDATETIME()
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    IF (@Delta <> 0)
        UPDATE dbo.WaterRawMaterialItems
        SET    CurrentQuantity = CurrentQuantity + @Delta, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId;

    IF (@LinkedExpenseId IS NOT NULL)
        UPDATE dbo.WaterExpenses
        SET    Amount    = @AmountPaid,      -- expense reflects amount paid (feedback #11.2)
               PaidTo    = @SupplierName,
               SupplierId= @SupplierId,
               -- Re-point to the chosen account only when one was explicitly passed.
               WaterCashAccountId = CASE WHEN @WaterCashAccountId IS NOT NULL THEN @UpdCashAccountId ELSE WaterCashAccountId END,
               UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterExpenseId = @LinkedExpenseId AND FarmId = @FarmId
          AND  IsDeleted = 0 AND Status IN ('Draft','Submitted','Approved');

    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Insert TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Update TO [Techretainer];
END
GO

-- =============================================================================
-- Migration 190: keep water purchase lots correct through Insert/Update/Delete
-- =============================================================================
-- Migration 187 turned water purchases into lots (RemainingQuantity) and 188
-- made production draw from them. This closes the loop on the purchase side:
--
--   * Insert — a new purchase now starts as a FULL lot. Without this it would
--     take the column default of 0 and be undrawable, so anything bought after
--     187 could never be consumed by a production batch.
--   * Update — refuses to re-quantify a lot an approved batch has drawn from,
--     and otherwise keeps the lot balance in step with the new quantity.
--   * Delete — refuses to remove a lot an approved batch has drawn from, which
--     would strand its draw records against a purchase that no longer exists.
--
-- Bodies as migration 147, with those changes only. Requires 187.
-- Idempotent (CREATE OR ALTER). Safe to re-run.
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
    @SupplierId            INT           = NULL,
    @TotalCost             DECIMAL(14,2) = NULL,
    @WaterCashAccountId    INT           = NULL,
    @ProductionUnit                 NVARCHAR(30)  = NULL,
    @ProductionUnitsPerPurchaseUnit DECIMAL(18,8) = NULL
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

    -- Production-level quantity added to stock (146).
    DECLARE @ProdQty DECIMAL(18,4) = @Quantity * ISNULL(NULLIF(@ProductionUnitsPerPurchaseUnit, 0), 1);

    -- 190: a new purchase is a full lot. RemainingQuantity is in PURCHASE units,
    -- matching Quantity, and is what production draws against.

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
        PaymentMethod, AmountPaid, ReceiptUrl, ReceivedByStaffId, Notes, CreatedBy, SupplierId,
        ProductionUnit, ProductionUnitsPerPurchaseUnit, RemainingQuantity
    )
    VALUES (
        @FarmId, @WaterRawMaterialItemId, @SupplierName,
        ISNULL(@PurchaseDate, SYSUTCDATETIME()), @Quantity, @UnitCost, @TotalCost,
        @EffectivePaymentMethod, @AmountPaid, @ReceiptUrl, @ReceivedByStaffId, @Notes, @CreatedBy, @SupplierId,
        @ProductionUnit, @ProductionUnitsPerPurchaseUnit, @Quantity
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    UPDATE dbo.WaterRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity + @ProdQty, UpdatedAt = SYSUTCDATETIME()   -- 147: production-level qty
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
                         THEN CONCAT(N' - part payment of ', CAST(@AmountPaid AS NVARCHAR(30)), N' of ', CAST(@TotalCost AS NVARCHAR(30)))
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
    @WaterCashAccountId INT      = NULL,
    @ProductionUnit                 NVARCHAR(30)  = NULL,
    @ProductionUnitsPerPurchaseUnit DECIMAL(18,8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 190: a lot that an approved production batch has already drawn from can't
    -- be re-quantified underneath it — the draw records and remaining balances
    -- would stop agreeing. Reopen that batch first.
    IF EXISTS (SELECT 1 FROM dbo.WaterRawMaterialUsageBatch
               WHERE WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId)
    BEGIN
        RAISERROR('This purchase batch has already been drawn from by an approved production batch. Reopen that batch first.', 16, 1);
        RETURN;
    END

    IF (@Quantity <= 0) BEGIN RAISERROR('Quantity must be > 0.', 16, 1); RETURN; END
    IF (@UnitCost < 0)  BEGIN RAISERROR('UnitCost cannot be negative.', 16, 1); RETURN; END

    IF (@TotalCost IS NULL OR @TotalCost <= 0)
        SET @TotalCost = CAST(@Quantity AS DECIMAL(14,2)) * @UnitCost;

    DECLARE @OldQty DECIMAL(14,3), @ItemId INT, @LinkedExpenseId INT, @OldMult DECIMAL(18,8);
    SELECT @OldQty = Quantity, @ItemId = WaterRawMaterialItemId, @LinkedExpenseId = LinkedWaterExpenseId,
           @OldMult = ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1)
    FROM   dbo.WaterRawMaterialPurchases
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @OldQty IS NULL BEGIN RAISERROR('Purchase %d not found.', 16, 1, @WaterRawMaterialPurchaseId); RETURN; END

    -- 147: stock delta measured in PRODUCTION units (new prod qty - old prod qty).
    DECLARE @NewMult DECIMAL(18,8) = ISNULL(NULLIF(@ProductionUnitsPerPurchaseUnit, 0), 1);
    DECLARE @Delta DECIMAL(18,4) = (@Quantity * @NewMult) - (@OldQty * @OldMult);
    IF (@Delta < 0)
    BEGIN
        DECLARE @CurrentStock DECIMAL(18,4) = (
            SELECT CurrentQuantity FROM dbo.WaterRawMaterialItems
            WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId);
        IF (@CurrentStock + @Delta < 0)
        BEGIN
            DECLARE @Msg1 NVARCHAR(400) = CONCAT(N'Cannot reduce quantity: only ',
                CONVERT(NVARCHAR(40), @CurrentStock), N' production units of this item remain in stock. Reverse usages first.');
            RAISERROR(@Msg1, 16, 1); RETURN;
        END
    END

    IF (@SupplierId IS NOT NULL AND (@SupplierName IS NULL OR @SupplierName = N''))
        SELECT @SupplierName = SupplierName FROM dbo.WaterSuppliers
        WHERE  WaterSupplierId = @SupplierId AND FarmId = @FarmId;

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
           ProductionUnit = @ProductionUnit,
           ProductionUnitsPerPurchaseUnit = @ProductionUnitsPerPurchaseUnit,
           UpdatedAt     = SYSUTCDATETIME(),
           RemainingQuantity = @Quantity
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    IF (@Delta <> 0)
        UPDATE dbo.WaterRawMaterialItems
        SET    CurrentQuantity = CurrentQuantity + @Delta, UpdatedAt = SYSUTCDATETIME()   -- 147: production-level delta
        WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId;

    IF (@LinkedExpenseId IS NOT NULL)
        UPDATE dbo.WaterExpenses
        SET    Amount    = @AmountPaid,
               PaidTo    = @SupplierName,
               SupplierId= @SupplierId,
               ExpenseDate = ISNULL(@PurchaseDate, ExpenseDate),   -- 144
               WaterCashAccountId = CASE WHEN @WaterCashAccountId IS NOT NULL THEN @UpdCashAccountId ELSE WaterCashAccountId END,
               UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterExpenseId = @LinkedExpenseId AND FarmId = @FarmId
          AND  IsDeleted = 0 AND Status IN ('Draft','Submitted','Approved');

    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_Delete
    @WaterRawMaterialPurchaseId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 190: see the Update guard. Deleting a drawn lot would strand its
    -- WaterRawMaterialUsageBatch rows against a purchase that no longer exists.
    IF EXISTS (SELECT 1 FROM dbo.WaterRawMaterialUsageBatch
               WHERE WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId)
    BEGIN
        RAISERROR('This purchase batch has already been drawn from by an approved production batch. Reopen that batch first.', 16, 1);
        RETURN;
    END

    DECLARE @Qty DECIMAL(14,3), @ItemId INT, @LinkedExpenseId INT, @Mult DECIMAL(18,8);
    SELECT @Qty = Quantity, @ItemId = WaterRawMaterialItemId, @LinkedExpenseId = LinkedWaterExpenseId,
           @Mult = ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1)
    FROM   dbo.WaterRawMaterialPurchases
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @Qty IS NULL
    BEGIN RAISERROR('Purchase %d not found.', 16, 1, @WaterRawMaterialPurchaseId); RETURN; END

    DECLARE @ProdQty DECIMAL(18,4) = @Qty * @Mult;   -- 147
    DECLARE @CurrentStock DECIMAL(18,4) = (
        SELECT CurrentQuantity FROM dbo.WaterRawMaterialItems
        WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId);

    IF (@CurrentStock < @ProdQty)
    BEGIN
        DECLARE @Msg2 NVARCHAR(400) = CONCAT(
            N'Cannot delete: only ', CONVERT(NVARCHAR(40), @CurrentStock),
            N' production units remain in stock but this purchase added ',
            CONVERT(NVARCHAR(40), @ProdQty),
            N'. Reverse usages first.');
        RAISERROR(@Msg2, 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    IF @LinkedExpenseId IS NOT NULL
    BEGIN
        EXEC dbo.spWaterRawMaterialPurchase_CancelLinkedExpense
            @WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId,
            @FarmId = @FarmId,
            @CancelledBy = NULL;
    END

    UPDATE dbo.WaterRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity - @ProdQty,   -- 147: production-level qty
           UpdatedAt       = SYSUTCDATETIME()
    WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId;

    DELETE FROM dbo.WaterRawMaterialPurchases
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Insert TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Update TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Delete TO PoultryAppRole;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Insert TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Update TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Delete TO [Techretainer];
    PRINT '190: granted EXECUTE on spWaterRawMaterialPurchase_Insert/Update/Delete to Techretainer.';
END
GO

-- Any purchase created between 187 and this migration landed with a 0 balance.
-- Nothing has drawn from those (production would have refused), so refill them.
UPDATE p
SET    p.RemainingQuantity = p.Quantity
FROM   dbo.WaterRawMaterialPurchases p
WHERE  p.RemainingQuantity = 0
  AND  p.Quantity > 0
  AND  NOT EXISTS (SELECT 1 FROM dbo.WaterRawMaterialUsageBatch ub
                   WHERE ub.WaterRawMaterialPurchaseId = p.WaterRawMaterialPurchaseId);
GO

PRINT '190_WaterRawMaterialPurchaseLotMaintenance.sql complete.';
GO

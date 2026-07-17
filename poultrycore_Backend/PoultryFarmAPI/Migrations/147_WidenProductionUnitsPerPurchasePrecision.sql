-- =============================================================================
-- Migration 147: widen ProductionUnitsPerPurchaseUnit to DECIMAL(18,8)
-- =============================================================================
-- Entering a whole production-level quantity (e.g. 54) showed 54.0001 and stored
-- slightly-off stock. Root cause: the units-per-purchase ratio (prodQty / qty)
-- was capped at DECIMAL(14,4); multiplying it back by qty reintroduced a visible
-- error. Widening the column + every SP param/var that carries the ratio to
-- DECIMAL(18,8) makes qty x ratio round back cleanly (stock rounds to 54.000).
-- SP bodies are identical to migration 146 with only the ratio precision widened.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER TABLE dbo.WaterRawMaterialPurchases   ALTER COLUMN ProductionUnitsPerPurchaseUnit DECIMAL(18,8) NULL;
GO
ALTER TABLE dbo.PoultryRawMaterialPurchases ALTER COLUMN ProductionUnitsPerPurchaseUnit DECIMAL(18,8) NULL;
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
        ProductionUnit, ProductionUnitsPerPurchaseUnit
    )
    VALUES (
        @FarmId, @WaterRawMaterialItemId, @SupplierName,
        ISNULL(@PurchaseDate, SYSUTCDATETIME()), @Quantity, @UnitCost, @TotalCost,
        @EffectivePaymentMethod, @AmountPaid, @ReceiptUrl, @ReceivedByStaffId, @Notes, @CreatedBy, @SupplierId,
        @ProductionUnit, @ProductionUnitsPerPurchaseUnit
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

/* =====================================================================
   WATER — Update  (production-level delta + expense date sync from 144)
   ===================================================================== */
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
           UpdatedAt     = SYSUTCDATETIME()
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

/* =====================================================================
   WATER — Delete  (reverse production-level qty)
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_Delete
    @WaterRawMaterialPurchaseId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

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

/* =====================================================================
   POULTRY — Insert
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialPurchase_Insert
    @FarmId                  NVARCHAR(450),
    @PoultryRawMaterialItemId INT,
    @SupplierName            NVARCHAR(200) = NULL,
    @SupplierId              INT           = NULL,
    @PurchaseDate            DATETIME2     = NULL,
    @Quantity                DECIMAL(14,3),
    @UnitCost                DECIMAL(14,2),
    @TotalCost               DECIMAL(14,2) = NULL,
    @ProductionUnit                 NVARCHAR(30)  = NULL,
    @ProductionUnitsPerPurchaseUnit DECIMAL(18,8) = NULL,
    @PaymentMethod           NVARCHAR(30)  = NULL,
    @AmountPaid              DECIMAL(14,2) = 0,
    @ReceiptUrl              NVARCHAR(500) = NULL,
    @Notes                   NVARCHAR(500) = NULL,
    @CreatedBy               NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@Quantity <= 0) BEGIN RAISERROR('Quantity must be > 0.', 16, 1); RETURN; END
    IF (@UnitCost < 0)  BEGIN RAISERROR('UnitCost cannot be negative.', 16, 1); RETURN; END
    IF (@TotalCost IS NULL OR @TotalCost <= 0) SET @TotalCost = CAST(@Quantity AS DECIMAL(14,2)) * @UnitCost;
    IF (@AmountPaid IS NULL) SET @AmountPaid = 0;
    IF (@AmountPaid > @TotalCost) SET @AmountPaid = @TotalCost;

    -- Production-level quantity added to stock (146).
    DECLARE @ProdQty DECIMAL(18,4) = @Quantity * ISNULL(NULLIF(@ProductionUnitsPerPurchaseUnit, 0), 1);

    DECLARE @ItemName NVARCHAR(150), @Unit NVARCHAR(30);
    SELECT @ItemName = ItemName, @Unit = UnitOfMeasure FROM dbo.PoultryRawMaterialItems
    WHERE  PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId;

    BEGIN TRANSACTION;

    INSERT INTO dbo.PoultryRawMaterialPurchases (
        FarmId, PoultryRawMaterialItemId, SupplierName, SupplierId, PurchaseDate,
        Quantity, UnitCost, TotalCost, ProductionUnit, ProductionUnitsPerPurchaseUnit,
        PaymentMethod, AmountPaid, ReceiptUrl, Notes, CreatedBy)
    VALUES (
        @FarmId, @PoultryRawMaterialItemId, @SupplierName, @SupplierId, ISNULL(@PurchaseDate, SYSUTCDATETIME()),
        @Quantity, @UnitCost, @TotalCost, @ProductionUnit, @ProductionUnitsPerPurchaseUnit,
        @PaymentMethod, @AmountPaid, @ReceiptUrl, @Notes, @CreatedBy);

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    UPDATE dbo.PoultryRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity + @ProdQty, UpdatedAt = SYSUTCDATETIME()   -- 147: production-level qty
    WHERE  PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId;

    DECLARE @Gid UNIQUEIDENTIFIER = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER);
    IF (@Gid IS NOT NULL AND @CreatedBy IS NOT NULL AND @AmountPaid > 0)
    BEGIN
        INSERT INTO dbo.Expense (ExpenseDate, Category, Description, Amount, PaymentMethod, Supplier, FlockId, CreatedDate, UserId, FarmId, SourceType, SourceId)
        VALUES (ISNULL(@PurchaseDate, SYSUTCDATETIME()), N'Raw Materials / Inventory Purchase',
                CONCAT(N'Raw material purchase: ', ISNULL(@ItemName, N'item'), N' (', CAST(@Quantity AS NVARCHAR(30)), N' ', ISNULL(@Unit, N''), N')'),
                @AmountPaid, ISNULL(@PaymentMethod, N'Cash'), @SupplierName, NULL, SYSUTCDATETIME(), @CreatedBy, @Gid,
                N'PoultryRawMaterialPurchase', @NewId);
    END

    COMMIT TRANSACTION;
    SELECT @NewId;
END
GO

/* =====================================================================
   POULTRY — Update  (production-level delta + expense date sync from 144)
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialPurchase_Update
    @PoultryRawMaterialPurchaseId INT,
    @FarmId         NVARCHAR(450),
    @SupplierName   NVARCHAR(200) = NULL,
    @SupplierId     INT           = NULL,
    @PurchaseDate   DATETIME2     = NULL,
    @Quantity       DECIMAL(14,3),
    @UnitCost       DECIMAL(14,2),
    @TotalCost      DECIMAL(14,2) = NULL,
    @ProductionUnit                 NVARCHAR(30)  = NULL,
    @ProductionUnitsPerPurchaseUnit DECIMAL(18,8) = NULL,
    @PaymentMethod  NVARCHAR(30)  = NULL,
    @AmountPaid     DECIMAL(14,2) = 0,
    @ReceiptUrl     NVARCHAR(500) = NULL,
    @Notes          NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@Quantity <= 0) BEGIN RAISERROR('Quantity must be > 0.', 16, 1); RETURN; END
    IF (@UnitCost < 0)  BEGIN RAISERROR('UnitCost cannot be negative.', 16, 1); RETURN; END
    IF (@TotalCost IS NULL OR @TotalCost <= 0) SET @TotalCost = CAST(@Quantity AS DECIMAL(14,2)) * @UnitCost;

    DECLARE @OldQty DECIMAL(14,3), @ItemId INT, @OldMult DECIMAL(18,8);
    SELECT @OldQty = Quantity, @ItemId = PoultryRawMaterialItemId,
           @OldMult = ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1)
    FROM   dbo.PoultryRawMaterialPurchases
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;
    IF @OldQty IS NULL BEGIN RAISERROR('Purchase %d not found.', 16, 1, @PoultryRawMaterialPurchaseId); RETURN; END

    -- 147: stock delta measured in PRODUCTION units.
    DECLARE @NewMult DECIMAL(18,8) = ISNULL(NULLIF(@ProductionUnitsPerPurchaseUnit, 0), 1);
    DECLARE @Delta DECIMAL(18,4) = (@Quantity * @NewMult) - (@OldQty * @OldMult);
    IF (@Delta < 0)
    BEGIN
        DECLARE @CurrentStock DECIMAL(18,4) = (SELECT CurrentQuantity FROM dbo.PoultryRawMaterialItems WHERE PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId);
        IF (@CurrentStock + @Delta < 0) BEGIN RAISERROR('Cannot reduce quantity below current stock.', 16, 1); RETURN; END
    END

    BEGIN TRANSACTION;

    UPDATE dbo.PoultryRawMaterialPurchases
    SET    SupplierName = @SupplierName, SupplierId = @SupplierId, PurchaseDate = ISNULL(@PurchaseDate, PurchaseDate),
           Quantity = @Quantity, UnitCost = @UnitCost, TotalCost = @TotalCost,
           ProductionUnit = @ProductionUnit, ProductionUnitsPerPurchaseUnit = @ProductionUnitsPerPurchaseUnit,
           PaymentMethod = @PaymentMethod, AmountPaid = @AmountPaid, ReceiptUrl = @ReceiptUrl, Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    IF (@Delta <> 0)
        UPDATE dbo.PoultryRawMaterialItems SET CurrentQuantity = CurrentQuantity + @Delta, UpdatedAt = SYSUTCDATETIME()   -- 147: production-level delta
        WHERE  PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId;

    -- Keep the initial linked expense (lowest ExpenseId for this source) in sync; do not duplicate.
    DECLARE @Gid UNIQUEIDENTIFIER = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER);
    IF (@Gid IS NOT NULL)
        UPDATE dbo.Expense SET Amount = @AmountPaid, Supplier = @SupplierName, PaymentMethod = ISNULL(@PaymentMethod, PaymentMethod),
               ExpenseDate = ISNULL(@PurchaseDate, ExpenseDate)   -- 144
        WHERE  ExpenseId = (SELECT MIN(ExpenseId) FROM dbo.Expense WHERE FarmId = @Gid AND SourceType = N'PoultryRawMaterialPurchase' AND SourceId = @PoultryRawMaterialPurchaseId);

    COMMIT TRANSACTION;
END
GO

/* =====================================================================
   POULTRY — Delete  (reverse production-level qty)
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialPurchase_Delete
    @PoultryRawMaterialPurchaseId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Qty DECIMAL(14,3), @ItemId INT, @Mult DECIMAL(18,8);
    SELECT @Qty = Quantity, @ItemId = PoultryRawMaterialItemId,
           @Mult = ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1)
    FROM   dbo.PoultryRawMaterialPurchases WHERE PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;
    IF @Qty IS NULL BEGIN RAISERROR('Purchase %d not found.', 16, 1, @PoultryRawMaterialPurchaseId); RETURN; END

    DECLARE @ProdQty DECIMAL(18,4) = @Qty * @Mult;   -- 147

    BEGIN TRANSACTION;
    DECLARE @Gid UNIQUEIDENTIFIER = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER);
    IF (@Gid IS NOT NULL)
        DELETE FROM dbo.Expense WHERE FarmId = @Gid AND SourceType = N'PoultryRawMaterialPurchase' AND SourceId = @PoultryRawMaterialPurchaseId;

    DELETE FROM dbo.PoultryRawMaterialPurchases WHERE PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    UPDATE dbo.PoultryRawMaterialItems
    SET    CurrentQuantity = CASE WHEN CurrentQuantity - @ProdQty < 0 THEN 0 ELSE CurrentQuantity - @ProdQty END, UpdatedAt = SYSUTCDATETIME()   -- 147
    WHERE  PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Insert   TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Update   TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Delete   TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Insert TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Update TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Delete TO [Techretainer];
END
GO

PRINT '147_WidenProductionUnitsPerPurchasePrecision.sql complete.';
GO

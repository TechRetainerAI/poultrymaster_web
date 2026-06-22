/* ============================================================================
   116_RawMaterialPurchaseProductionConversion.sql

   Brings back (and PERSISTS) the production-unit conversion on a raw-material
   purchase, removed in ed4c89d "Testing-feedback batch" (per tester feedback).

   You buy in a PURCHASE unit (e.g. Roll/Bag) but consume in a PRODUCTION unit
   (e.g. Sachet). Storing the conversion lets us compute and keep the cost per
   production unit, so production costing can use it later.

   New columns on WaterRawMaterialPurchases:
     ProductionUnit                 NVARCHAR(30)  NULL  -- e.g. 'Sachet'
     ProductionUnitsPerPurchaseUnit DECIMAL(14,4) NULL  -- e.g. 4000 sachets / roll

   - _Insert / _Update: accept + store the two fields (additive; existing callers
     that pass nothing are unaffected).
   - _GetAll: returns the stored fields (via p.*) PLUS two derived, read-only
     helpers: ProductionQuantity (= Quantity * units-per) and ProductionUnitCost
     (= TotalCost / ProductionQuantity).

   Idempotent (CREATE OR ALTER + guarded ALTER TABLE). Insert/Update bodies are
   migration 106 verbatim plus the two new fields.
   ============================================================================ */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---- 1. Columns (additive, guarded) ------------------------------------- */
IF COL_LENGTH('dbo.WaterRawMaterialPurchases', 'ProductionUnit') IS NULL
    ALTER TABLE dbo.WaterRawMaterialPurchases ADD ProductionUnit NVARCHAR(30) NULL;
GO
IF COL_LENGTH('dbo.WaterRawMaterialPurchases', 'ProductionUnitsPerPurchaseUnit') IS NULL
    ALTER TABLE dbo.WaterRawMaterialPurchases ADD ProductionUnitsPerPurchaseUnit DECIMAL(14,4) NULL;
GO

/* ---- 2. Insert ----------------------------------------------------------- */
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
    @WaterCashAccountId    INT           = NULL,  -- caller-chosen account; NULL => first active
    @ProductionUnit                 NVARCHAR(30)  = NULL,
    @ProductionUnitsPerPurchaseUnit DECIMAL(14,4) = NULL
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

/* ---- 3. Update ----------------------------------------------------------- */
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
    @ProductionUnitsPerPurchaseUnit DECIMAL(14,4) = NULL
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
        SET    CurrentQuantity = CurrentQuantity + @Delta, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId;

    IF (@LinkedExpenseId IS NOT NULL)
        UPDATE dbo.WaterExpenses
        SET    Amount    = @AmountPaid,
               PaidTo    = @SupplierName,
               SupplierId= @SupplierId,
               WaterCashAccountId = CASE WHEN @WaterCashAccountId IS NOT NULL THEN @UpdCashAccountId ELSE WaterCashAccountId END,
               UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterExpenseId = @LinkedExpenseId AND FarmId = @FarmId
          AND  IsDeleted = 0 AND Status IN ('Draft','Submitted','Approved');

    COMMIT TRANSACTION;
END
GO

/* ---- 4. GetAll (adds derived production qty + per-unit cost) ------------- */
CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_GetAll
    @FarmId NVARCHAR(450), @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.*,
           i.ItemName,
           i.Category,
           i.UnitOfMeasure,
           CAST(p.TotalCost - p.AmountPaid AS DECIMAL(14,2)) AS Balance,
           CAST(p.Quantity * ISNULL(p.ProductionUnitsPerPurchaseUnit, 1) AS DECIMAL(18,3)) AS ProductionQuantity,
           CAST(CASE WHEN ISNULL(p.ProductionUnitsPerPurchaseUnit, 0) > 0
                     THEN p.TotalCost / NULLIF(p.Quantity * p.ProductionUnitsPerPurchaseUnit, 0)
                     ELSE NULL END AS DECIMAL(18,4)) AS ProductionUnitCost
    FROM   dbo.WaterRawMaterialPurchases p
    INNER  JOIN dbo.WaterRawMaterialItems i ON i.WaterRawMaterialItemId = p.WaterRawMaterialItemId
    WHERE  p.FarmId = @FarmId
       AND (@FromDate IS NULL OR CAST(p.PurchaseDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(p.PurchaseDate AS DATE) <= @ToDate)
    ORDER  BY p.PurchaseDate DESC, p.WaterRawMaterialPurchaseId DESC;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Insert TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Update TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_GetAll TO [Techretainer];
END
GO

PRINT '116_RawMaterialPurchaseProductionConversion.sql complete.';
GO

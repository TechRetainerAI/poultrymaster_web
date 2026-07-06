-- =============================================================================
-- Migration 144: purchase edit must also update the linked expense's DATE
-- =============================================================================
-- Bug (James): create a raw-material purchase with the wrong date, then edit the
-- purchase to the correct date — the Expenses page entry keeps the ORIGINAL date.
-- The purchase Update SPs re-sync the linked expense's amount/supplier/cash, but
-- never its ExpenseDate. Add ExpenseDate = ISNULL(@PurchaseDate, ExpenseDate) to
-- both the Water and Poultry raw-material purchase Update SPs. Full-body
-- CREATE OR ALTER (copied from migrations 116 / 130) with only that line added.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---- Water ---------------------------------------------------------------- */
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
               ExpenseDate = ISNULL(@PurchaseDate, ExpenseDate),   -- 144: keep the expense date in sync with the purchase
               WaterCashAccountId = CASE WHEN @WaterCashAccountId IS NOT NULL THEN @UpdCashAccountId ELSE WaterCashAccountId END,
               UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterExpenseId = @LinkedExpenseId AND FarmId = @FarmId
          AND  IsDeleted = 0 AND Status IN ('Draft','Submitted','Approved');

    COMMIT TRANSACTION;
END
GO

/* ---- Poultry -------------------------------------------------------------- */
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
    @ProductionUnitsPerPurchaseUnit DECIMAL(14,4) = NULL,
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

    DECLARE @OldQty DECIMAL(14,3), @ItemId INT;
    SELECT @OldQty = Quantity, @ItemId = PoultryRawMaterialItemId
    FROM   dbo.PoultryRawMaterialPurchases
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;
    IF @OldQty IS NULL BEGIN RAISERROR('Purchase %d not found.', 16, 1, @PoultryRawMaterialPurchaseId); RETURN; END

    DECLARE @Delta DECIMAL(14,3) = @Quantity - @OldQty;
    IF (@Delta < 0)
    BEGIN
        DECLARE @CurrentStock DECIMAL(14,3) = (SELECT CurrentQuantity FROM dbo.PoultryRawMaterialItems WHERE PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId);
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
        UPDATE dbo.PoultryRawMaterialItems SET CurrentQuantity = CurrentQuantity + @Delta, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId;

    -- Keep the initial linked expense (lowest ExpenseId for this source) in sync; do not duplicate.
    DECLARE @Gid UNIQUEIDENTIFIER = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER);
    IF (@Gid IS NOT NULL)
        UPDATE dbo.Expense SET Amount = @AmountPaid, Supplier = @SupplierName, PaymentMethod = ISNULL(@PaymentMethod, PaymentMethod),
               ExpenseDate = ISNULL(@PurchaseDate, ExpenseDate)   -- 144: keep the expense date in sync with the purchase
        WHERE  ExpenseId = (SELECT MIN(ExpenseId) FROM dbo.Expense WHERE FarmId = @Gid AND SourceType = N'PoultryRawMaterialPurchase' AND SourceId = @PoultryRawMaterialPurchaseId);

    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Update TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Update TO [Techretainer];
END
GO

PRINT '144_RawMaterialPurchaseUpdateSyncsExpenseDate.sql complete.';
GO

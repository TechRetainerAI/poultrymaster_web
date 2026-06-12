/* =============================================================================
   060_AddWaterRawMaterialPurchaseUpdateDelete.sql

   James reported the Raw Materials page has no way to edit or delete recorded
   purchases. Add the missing SPs.

   Purchases were intentionally write-once when first built because each one
   increments WaterRawMaterialItems.CurrentQuantity. Any update or delete has
   to reverse that delta on the parent item — and refuse if the reversal would
   push CurrentQuantity below zero (would mean some of the purchased stock
   has already been used in production).

   Item is fixed once recorded — to move the purchase to a different item,
   delete + recreate.
   ============================================================================= */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_Update
    @WaterRawMaterialPurchaseId INT,
    @FarmId NVARCHAR(450),
    @SupplierName NVARCHAR(200) = NULL,
    @PurchaseDate DATETIME2 = NULL,
    @Quantity DECIMAL(14,3),
    @UnitCost DECIMAL(14,2),
    @PaymentMethod NVARCHAR(30) = NULL,
    @AmountPaid DECIMAL(14,2) = 0,
    @ReceiptUrl NVARCHAR(500) = NULL,
    @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@Quantity <= 0) BEGIN RAISERROR('Quantity must be > 0.', 16, 1); RETURN; END
    IF (@UnitCost < 0)  BEGIN RAISERROR('UnitCost cannot be negative.', 16, 1); RETURN; END

    DECLARE @OldQty DECIMAL(14,3), @ItemId INT;
    SELECT @OldQty = Quantity, @ItemId = WaterRawMaterialItemId
    FROM   dbo.WaterRawMaterialPurchases
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @OldQty IS NULL
    BEGIN RAISERROR('Purchase %d not found.', 16, 1, @WaterRawMaterialPurchaseId); RETURN; END

    DECLARE @Delta DECIMAL(14,3) = @Quantity - @OldQty;

    /* If reducing quantity, refuse when current stock can't absorb the
       reduction (means some has already been consumed by usage). */
    IF (@Delta < 0)
    BEGIN
        DECLARE @CurrentStock DECIMAL(14,3) = (
            SELECT CurrentQuantity FROM dbo.WaterRawMaterialItems
            WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId);

        IF (@CurrentStock + @Delta < 0)
        BEGIN
            DECLARE @Msg1 NVARCHAR(400) = CONCAT(
                N'Cannot reduce quantity: only ',
                CONVERT(NVARCHAR(40), @CurrentStock),
                N' units of this item remain in stock. Reverse usages first.');
            RAISERROR(@Msg1, 16, 1);
            RETURN;
        END
    END

    BEGIN TRANSACTION;

    UPDATE dbo.WaterRawMaterialPurchases
    SET    SupplierName  = @SupplierName,
           PurchaseDate  = ISNULL(@PurchaseDate, PurchaseDate),
           Quantity      = @Quantity,
           UnitCost      = @UnitCost,
           PaymentMethod = @PaymentMethod,
           AmountPaid    = @AmountPaid,
           ReceiptUrl    = @ReceiptUrl,
           Notes         = @Notes,
           UpdatedAt     = SYSUTCDATETIME()
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    IF (@Delta <> 0)
    BEGIN
        UPDATE dbo.WaterRawMaterialItems
        SET    CurrentQuantity = CurrentQuantity + @Delta,
               UpdatedAt       = SYSUTCDATETIME()
        WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId;
    END

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

    DECLARE @Qty DECIMAL(14,3), @ItemId INT;
    SELECT @Qty = Quantity, @ItemId = WaterRawMaterialItemId
    FROM   dbo.WaterRawMaterialPurchases
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @Qty IS NULL
    BEGIN RAISERROR('Purchase %d not found.', 16, 1, @WaterRawMaterialPurchaseId); RETURN; END

    DECLARE @CurrentStock DECIMAL(14,3) = (
        SELECT CurrentQuantity FROM dbo.WaterRawMaterialItems
        WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId);

    IF (@CurrentStock < @Qty)
    BEGIN
        DECLARE @Msg2 NVARCHAR(400) = CONCAT(
            N'Cannot delete: only ', CONVERT(NVARCHAR(40), @CurrentStock),
            N' units remain in stock but this purchase added ',
            CONVERT(NVARCHAR(40), @Qty),
            N'. Reverse usages first.');
        RAISERROR(@Msg2, 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    UPDATE dbo.WaterRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity - @Qty,
           UpdatedAt       = SYSUTCDATETIME()
    WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId;

    DELETE FROM dbo.WaterRawMaterialPurchases
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'PoultryAppRole' AND type = 'R')
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Update TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Delete TO PoultryAppRole;
END
GO

PRINT '060_AddWaterRawMaterialPurchaseUpdateDelete.sql complete.';
GO

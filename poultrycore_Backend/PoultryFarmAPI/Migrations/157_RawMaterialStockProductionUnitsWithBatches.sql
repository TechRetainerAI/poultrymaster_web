-- =============================================================================
-- Migration 157: raw-material stock (CurrentQuantity) moves in PRODUCTION units
--                on top of Gyimah's batch-costing (153)
-- =============================================================================
-- Bug (James, still): recording a purchase increases stock by the PURCHASE
-- quantity, not the production-level quantity. Migration 153 (batch costing)
-- reverted the production-unit behaviour. This layers it back on WITHOUT
-- breaking batch costing:
--   * CurrentQuantity (displayed stock, consumed in production units by 156) now
--     moves by @Quantity x units-per-purchase on Insert/Update/Delete.
--   * RemainingQuantity stays in PURCHASE units (batch FIFO/LIFO/HIFO draws are
--     unchanged; 156 converts them to production units when consuming).
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

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
    @ProductionUnitsPerPurchaseUnit DECIMAL(14,4) = NULL,
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

    DECLARE @Mult DECIMAL(18,8) = ISNULL(NULLIF(@ProductionUnitsPerPurchaseUnit, 0), 1);   -- 157

    BEGIN TRANSACTION;

    INSERT INTO dbo.PoultryRawMaterialPurchases (
        FarmId, PoultryRawMaterialItemId, SupplierName, SupplierId, PurchaseDate,
        Quantity, UnitCost, TotalCost, ProductionUnit, ProductionUnitsPerPurchaseUnit,
        PaymentMethod, AmountPaid, ReceiptUrl, Notes, CreatedBy, RemainingQuantity
    )
    VALUES (
        @FarmId, @PoultryRawMaterialItemId, @SupplierName, @SupplierId, ISNULL(@PurchaseDate, SYSUTCDATETIME()),
        @Quantity, @UnitCost, @TotalCost, @ProductionUnit, @ProductionUnitsPerPurchaseUnit,
        @PaymentMethod, @AmountPaid, @ReceiptUrl, @Notes, @CreatedBy, @Quantity   -- RemainingQuantity in PURCHASE units
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    UPDATE dbo.PoultryRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity + (@Quantity * @Mult), UpdatedAt = SYSUTCDATETIME()   -- 157: production units
    WHERE  PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
    SELECT @NewId;
END
GO

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

    DECLARE @OldQty DECIMAL(14,3), @OldRemaining DECIMAL(14,3), @ItemId INT, @OldMult DECIMAL(18,8);
    SELECT @OldQty = Quantity, @OldRemaining = RemainingQuantity, @ItemId = PoultryRawMaterialItemId,
           @OldMult = ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1)
    FROM   dbo.PoultryRawMaterialPurchases
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @OldQty IS NULL BEGIN RAISERROR('Purchase %d not found.', 16, 1, @PoultryRawMaterialPurchaseId); RETURN; END

    -- Cannot reduce the (purchase-unit) quantity below what's already been drawn.
    DECLARE @AlreadyDrawn DECIMAL(14,3) = @OldQty - ISNULL(@OldRemaining, @OldQty);
    IF (@Quantity < @AlreadyDrawn)
    BEGIN
        DECLARE @Msg2 NVARCHAR(400) = CONCAT(N'Cannot reduce quantity below ', CONVERT(NVARCHAR(40), @AlreadyDrawn), N' — that much has already been used from this batch.');
        RAISERROR(@Msg2, 16, 1); RETURN;
    END

    -- Stock delta in PRODUCTION units (157).
    DECLARE @NewMult DECIMAL(18,8) = ISNULL(NULLIF(@ProductionUnitsPerPurchaseUnit, 0), 1);
    DECLARE @DeltaProd DECIMAL(18,4) = (@Quantity * @NewMult) - (@OldQty * @OldMult);
    IF (@DeltaProd < 0)
    BEGIN
        DECLARE @CurrentStock DECIMAL(18,4) = (SELECT CurrentQuantity FROM dbo.PoultryRawMaterialItems WHERE PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId);
        IF (@CurrentStock + @DeltaProd < 0)
        BEGIN
            DECLARE @Msg NVARCHAR(400) = CONCAT(N'Cannot reduce quantity: only ', CONVERT(NVARCHAR(40), @CurrentStock), N' production units remain in stock.');
            RAISERROR(@Msg, 16, 1); RETURN;
        END
    END

    BEGIN TRANSACTION;

    UPDATE dbo.PoultryRawMaterialPurchases
    SET    SupplierName = @SupplierName, SupplierId = @SupplierId,
           PurchaseDate = ISNULL(@PurchaseDate, PurchaseDate),
           Quantity = @Quantity, UnitCost = @UnitCost, TotalCost = @TotalCost,
           ProductionUnit = @ProductionUnit, ProductionUnitsPerPurchaseUnit = @ProductionUnitsPerPurchaseUnit,
           PaymentMethod = @PaymentMethod, AmountPaid = @AmountPaid,
           ReceiptUrl = @ReceiptUrl, Notes = @Notes, UpdatedAt = SYSUTCDATETIME(),
           RemainingQuantity = @Quantity - @AlreadyDrawn   -- PURCHASE units, unchanged
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    IF (@DeltaProd <> 0)
        UPDATE dbo.PoultryRawMaterialItems
        SET    CurrentQuantity = CurrentQuantity + @DeltaProd, UpdatedAt = SYSUTCDATETIME()   -- 157: production-level delta
        WHERE  PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialPurchase_Delete
    @PoultryRawMaterialPurchaseId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.PoultryRawMaterialUsageBatch WHERE PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId)
    BEGIN
        RAISERROR('Cannot delete: this purchase batch has already been drawn from by a production/medication record. Delete or edit those records first.', 16, 1);
        RETURN;
    END

    DECLARE @Qty DECIMAL(14,3), @ItemId INT, @Mult DECIMAL(18,8);
    SELECT @Qty = Quantity, @ItemId = PoultryRawMaterialItemId,
           @Mult = ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1)
    FROM   dbo.PoultryRawMaterialPurchases
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @Qty IS NULL BEGIN RAISERROR('Purchase %d not found.', 16, 1, @PoultryRawMaterialPurchaseId); RETURN; END

    DECLARE @ProdQty DECIMAL(18,4) = @Qty * @Mult;   -- 157

    BEGIN TRANSACTION;
    DELETE FROM dbo.PoultryRawMaterialPurchases
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    UPDATE dbo.PoultryRawMaterialItems
    SET    CurrentQuantity = CASE WHEN CurrentQuantity - @ProdQty < 0 THEN 0 ELSE CurrentQuantity - @ProdQty END,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Insert TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Update TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Delete TO [Techretainer];
END
GO

PRINT '157_RawMaterialStockProductionUnitsWithBatches.sql complete.';
GO

-- =============================================================================
-- Migration 130: Poultry raw-material purchase auto-creates a linked Expense
-- =============================================================================
-- Doc section 1. The existing poultry expense table is dbo.Expense
-- (FarmId UNIQUEIDENTIFIER, UserId NOT NULL, freetext Category). Poultry farmIds
-- are GUID strings, so we CAST the NVARCHAR farmId to uniqueidentifier.
--
--   * Add SourceType/SourceId to dbo.Expense (guarded) for source linking.
--   * Redefine spPoultryRawMaterialPurchase_Insert/Update/Delete/PayBalance to
--     keep a linked expense in sync (Amount = amount actually paid).
-- Guards: only touch Expense when a userId is supplied and farmId is a valid GUID,
-- so a purchase never fails just because expense linking can't run.
-- Idempotent (guarded ALTER + CREATE OR ALTER).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.Expense', 'SourceType') IS NULL
    ALTER TABLE dbo.Expense ADD SourceType NVARCHAR(40) NULL;
GO
IF COL_LENGTH('dbo.Expense', 'SourceId') IS NULL
    ALTER TABLE dbo.Expense ADD SourceId INT NULL;
GO

DECLARE @cat NVARCHAR(100) = N'Raw Materials / Inventory Purchase';
GO

-- ---- Insert: purchase + stock increment + linked expense --------------------
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
    SET    CurrentQuantity = CurrentQuantity + @Quantity, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId;

    -- Linked expense (actual cash out). Guard on userId + valid GUID farmId.
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

-- ---- Update: adjust stock delta + sync linked expense amount -----------------
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
        UPDATE dbo.Expense SET Amount = @AmountPaid, Supplier = @SupplierName, PaymentMethod = ISNULL(@PaymentMethod, PaymentMethod)
        WHERE  ExpenseId = (SELECT MIN(ExpenseId) FROM dbo.Expense WHERE FarmId = @Gid AND SourceType = N'PoultryRawMaterialPurchase' AND SourceId = @PoultryRawMaterialPurchaseId);

    COMMIT TRANSACTION;
END
GO

-- ---- Delete: reverse stock + remove linked expenses -------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialPurchase_Delete
    @PoultryRawMaterialPurchaseId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Qty DECIMAL(14,3), @ItemId INT;
    SELECT @Qty = Quantity, @ItemId = PoultryRawMaterialItemId
    FROM   dbo.PoultryRawMaterialPurchases WHERE PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;
    IF @Qty IS NULL BEGIN RAISERROR('Purchase %d not found.', 16, 1, @PoultryRawMaterialPurchaseId); RETURN; END

    BEGIN TRANSACTION;
    DECLARE @Gid UNIQUEIDENTIFIER = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER);
    IF (@Gid IS NOT NULL)
        DELETE FROM dbo.Expense WHERE FarmId = @Gid AND SourceType = N'PoultryRawMaterialPurchase' AND SourceId = @PoultryRawMaterialPurchaseId;

    DELETE FROM dbo.PoultryRawMaterialPurchases WHERE PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    UPDATE dbo.PoultryRawMaterialItems
    SET    CurrentQuantity = CASE WHEN CurrentQuantity - @Qty < 0 THEN 0 ELSE CurrentQuantity - @Qty END, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

-- ---- PayBalance: increase paid + post an additional expense ------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialPurchase_PayBalance
    @PoultryRawMaterialPurchaseId INT,
    @FarmId        NVARCHAR(450),
    @Amount        DECIMAL(14,2),
    @PaymentMethod NVARCHAR(30)  = NULL,
    @PaymentDate   DATETIME2     = NULL,
    @CreatedBy     NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Total DECIMAL(14,2), @Paid DECIMAL(14,2), @ItemId INT, @SupplierName NVARCHAR(200);
    SELECT @Total = TotalCost, @Paid = AmountPaid, @ItemId = PoultryRawMaterialItemId, @SupplierName = SupplierName
    FROM   dbo.PoultryRawMaterialPurchases WHERE PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @Total IS NULL BEGIN RAISERROR('Purchase not found for this company.', 16, 1); RETURN; END
    DECLARE @Outstanding DECIMAL(14,2) = @Total - @Paid;
    IF (@Outstanding <= 0) BEGIN RAISERROR('This purchase has no outstanding balance.', 16, 1); RETURN; END
    IF (@Amount IS NULL OR @Amount <= 0) BEGIN RAISERROR('Payment amount must be greater than 0.', 16, 1); RETURN; END
    IF (@Amount > @Outstanding) SET @Amount = @Outstanding;

    DECLARE @ItemName NVARCHAR(150);
    SELECT @ItemName = ItemName FROM dbo.PoultryRawMaterialItems WHERE PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId;

    BEGIN TRANSACTION;
    UPDATE dbo.PoultryRawMaterialPurchases SET AmountPaid = AmountPaid + @Amount, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    DECLARE @Gid UNIQUEIDENTIFIER = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER);
    IF (@Gid IS NOT NULL AND @CreatedBy IS NOT NULL)
        INSERT INTO dbo.Expense (ExpenseDate, Category, Description, Amount, PaymentMethod, Supplier, FlockId, CreatedDate, UserId, FarmId, SourceType, SourceId)
        VALUES (ISNULL(@PaymentDate, SYSUTCDATETIME()), N'Raw Materials / Inventory Purchase',
                CONCAT(N'Balance payment for raw material purchase #', @PoultryRawMaterialPurchaseId, N': ', ISNULL(@ItemName, N'item')),
                @Amount, ISNULL(@PaymentMethod, N'Cash'), @SupplierName, NULL, SYSUTCDATETIME(), @CreatedBy, @Gid,
                N'PoultryRawMaterialPurchase', @PoultryRawMaterialPurchaseId);
    COMMIT TRANSACTION;

    SELECT CAST(TotalCost - AmountPaid AS DECIMAL(14,2)) AS Balance
    FROM   dbo.PoultryRawMaterialPurchases WHERE PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Insert     TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Update     TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Delete     TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_PayBalance TO [Techretainer];
    PRINT '130: granted EXECUTE to Techretainer.';
END
GO

PRINT '130_PoultryRawMaterialPurchaseExpenseLink.sql complete.';
GO

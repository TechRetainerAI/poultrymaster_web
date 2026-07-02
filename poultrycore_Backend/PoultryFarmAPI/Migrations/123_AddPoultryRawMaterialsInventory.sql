-- =============================================================================
-- Migration 123: Poultry Company — Raw Materials + Inventory (slice 1)
-- =============================================================================
-- Mirrors the Water raw-materials suite (migrations 043 / 116) for the POULTRY
-- company type. Fully ADDITIVE: new Poultry* tables + spPoultry* procedures only.
-- Does NOT touch any existing poultry table, SP, or the Water schema.
--
-- Tables:
--   * PoultryRawMaterialItems       — catalog (feed inputs, packaging, meds, supplies)
--   * PoultryRawMaterialPurchases   — buying raw materials (increases stock) + costing
--   * PoultryRawMaterialUsage       — consumption (decreases stock + variance); batch
--                                     link is added in a later slice
--
-- Payment is tracked on the purchase (AmountPaid / Balance). A separate cash/
-- expense ledger posting is intentionally NOT done in this slice to keep the
-- Poultry inventory self-contained; it can be wired to poultry financials later.
-- Idempotent (object guards + CREATE OR ALTER). Grants EXECUTE to the app login.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. PoultryRawMaterialItems — the catalog
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryRawMaterialItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryRawMaterialItems (
        PoultryRawMaterialItemId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450) NOT NULL,
        ItemName                 NVARCHAR(150) NOT NULL,
        Category                 NVARCHAR(40)  NOT NULL,   -- 'FeedIngredient' | 'Packaging' | 'Medication' | 'Vaccine' | 'Bedding' | 'Disinfectant' | 'SparePart' | 'Fuel' | 'Other'
        UnitOfMeasure            NVARCHAR(30)  NULL,        -- 'kg' | 'bag' | 'litre' | 'pc' | etc.
        MinimumStockAlert        DECIMAL(14,3) NOT NULL CONSTRAINT DF_PoultryRawMaterialItems_Min DEFAULT (0),
        CurrentQuantity          DECIMAL(14,3) NOT NULL CONSTRAINT DF_PoultryRawMaterialItems_Curr DEFAULT (0),
        IsActive                 BIT           NOT NULL CONSTRAINT DF_PoultryRawMaterialItems_IsActive DEFAULT (1),
        Notes                    NVARCHAR(500) NULL,
        CreatedAt                DATETIME2     NOT NULL CONSTRAINT DF_PoultryRawMaterialItems_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                DATETIME2     NULL,
        CONSTRAINT UQ_PoultryRawMaterialItems_Farm_Name UNIQUE (FarmId, ItemName)
    );
    CREATE INDEX IX_PoultryRawMaterialItems_FarmId ON dbo.PoultryRawMaterialItems (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 2. PoultryRawMaterialPurchases — buying raw materials (+ production costing)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryRawMaterialPurchases', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryRawMaterialPurchases (
        PoultryRawMaterialPurchaseId   INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                         NVARCHAR(450) NOT NULL,
        PoultryRawMaterialItemId       INT           NOT NULL,
        SupplierName                   NVARCHAR(200) NULL,
        SupplierId                     INT           NULL,   -- optional link to shared Suppliers; no hard FK (keep additive)
        PurchaseDate                   DATETIME2     NOT NULL CONSTRAINT DF_PoultryRMPurchases_Date DEFAULT (SYSUTCDATETIME()),
        Quantity                       DECIMAL(14,3) NOT NULL,
        UnitCost                       DECIMAL(14,2) NOT NULL,
        TotalCost                      DECIMAL(14,2) NOT NULL,   -- exact entered total (defaults to Qty*UnitCost)
        ProductionUnit                 NVARCHAR(30)  NULL,       -- e.g. 'kg' consumed in production
        ProductionUnitsPerPurchaseUnit DECIMAL(14,4) NULL,       -- e.g. 50 kg per bag
        PaymentMethod                  NVARCHAR(30)  NULL,       -- 'Cash' | 'MoMo' | 'Bank' | 'Card' | 'Credit'
        AmountPaid                     DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryRMPurchases_Paid DEFAULT (0),
        ReceiptUrl                     NVARCHAR(500) NULL,
        Notes                          NVARCHAR(500) NULL,
        CreatedBy                      NVARCHAR(450) NULL,
        CreatedAt                      DATETIME2     NOT NULL CONSTRAINT DF_PoultryRMPurchases_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                      DATETIME2     NULL,
        CONSTRAINT FK_PoultryRMPurchases_Item FOREIGN KEY (PoultryRawMaterialItemId) REFERENCES dbo.PoultryRawMaterialItems (PoultryRawMaterialItemId)
    );
    CREATE INDEX IX_PoultryRMPurchases_FarmId ON dbo.PoultryRawMaterialPurchases (FarmId);
    CREATE INDEX IX_PoultryRMPurchases_Item   ON dbo.PoultryRawMaterialPurchases (PoultryRawMaterialItemId);
    CREATE INDEX IX_PoultryRMPurchases_Date   ON dbo.PoultryRawMaterialPurchases (PurchaseDate);
END
GO

-- -----------------------------------------------------------------------------
-- 3. PoultryRawMaterialUsage — consumption (batch link added in a later slice)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryRawMaterialUsage', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryRawMaterialUsage (
        PoultryRawMaterialUsageId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                     NVARCHAR(450) NOT NULL,
        PoultryRawMaterialItemId   INT           NOT NULL,
        PoultryProductionBatchId   INT           NULL,   -- FK added when batches slice lands
        UsedDate                   DATETIME2     NOT NULL CONSTRAINT DF_PoultryRMUsage_Date DEFAULT (SYSUTCDATETIME()),
        QuantityUsed               DECIMAL(14,3) NOT NULL,
        ExpectedQuantityUsed       DECIMAL(14,3) NULL,
        Variance                   AS (QuantityUsed - ISNULL(ExpectedQuantityUsed, QuantityUsed)) PERSISTED,
        VarianceReason             NVARCHAR(500) NULL,
        UsedByStaffId              INT           NULL,
        Notes                      NVARCHAR(500) NULL,
        CreatedBy                  NVARCHAR(450) NULL,
        CreatedAt                  DATETIME2     NOT NULL CONSTRAINT DF_PoultryRMUsage_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_PoultryRMUsage_Item FOREIGN KEY (PoultryRawMaterialItemId) REFERENCES dbo.PoultryRawMaterialItems (PoultryRawMaterialItemId)
    );
    CREATE INDEX IX_PoultryRMUsage_FarmId ON dbo.PoultryRawMaterialUsage (FarmId);
    CREATE INDEX IX_PoultryRMUsage_Item   ON dbo.PoultryRawMaterialUsage (PoultryRawMaterialItemId);
    CREATE INDEX IX_PoultryRMUsage_Batch  ON dbo.PoultryRawMaterialUsage (PoultryProductionBatchId);
END
GO

-- =============================================================================
-- Stored procedures
-- =============================================================================

-- ---- Items ------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialItem_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.*,
           CAST(CASE WHEN i.CurrentQuantity <= i.MinimumStockAlert THEN 1 ELSE 0 END AS BIT) AS IsLowStock
    FROM   dbo.PoultryRawMaterialItems i
    WHERE  i.FarmId = @FarmId
    ORDER  BY i.IsActive DESC, i.ItemName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialItem_Insert
    @FarmId           NVARCHAR(450),
    @ItemName         NVARCHAR(150),
    @Category         NVARCHAR(40),
    @UnitOfMeasure    NVARCHAR(30)  = NULL,
    @MinimumStockAlert DECIMAL(14,3) = 0,
    @Notes            NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.PoultryRawMaterialItems (FarmId, ItemName, Category, UnitOfMeasure, MinimumStockAlert, Notes)
    VALUES (@FarmId, @ItemName, @Category, @UnitOfMeasure, ISNULL(@MinimumStockAlert, 0), @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialItem_Update
    @PoultryRawMaterialItemId INT,
    @FarmId           NVARCHAR(450),
    @ItemName         NVARCHAR(150),
    @Category         NVARCHAR(40),
    @UnitOfMeasure    NVARCHAR(30)  = NULL,
    @MinimumStockAlert DECIMAL(14,3) = 0,
    @IsActive         BIT           = 1,
    @Notes            NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryRawMaterialItems
    SET    ItemName = @ItemName, Category = @Category, UnitOfMeasure = @UnitOfMeasure,
           MinimumStockAlert = ISNULL(@MinimumStockAlert, 0), IsActive = ISNULL(@IsActive, 1),
           Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialItem_Delete
    @PoultryRawMaterialItemId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM dbo.PoultryRawMaterialPurchases WHERE PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId)
       OR EXISTS (SELECT 1 FROM dbo.PoultryRawMaterialUsage WHERE PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId)
    BEGIN
        -- Has history: soft-delete (deactivate) instead of hard delete.
        UPDATE dbo.PoultryRawMaterialItems SET IsActive = 0, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId;
        RETURN;
    END
    DELETE FROM dbo.PoultryRawMaterialItems
    WHERE  PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId;
END
GO

-- ---- Purchases --------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialPurchase_GetAll
    @FarmId NVARCHAR(450), @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.*,
           i.ItemName, i.Category, i.UnitOfMeasure,
           CAST(p.TotalCost - p.AmountPaid AS DECIMAL(14,2)) AS Balance,
           CAST(p.Quantity * ISNULL(p.ProductionUnitsPerPurchaseUnit, 1) AS DECIMAL(18,3)) AS ProductionQuantity,
           CAST(CASE WHEN ISNULL(p.ProductionUnitsPerPurchaseUnit, 0) > 0
                     THEN p.TotalCost / NULLIF(p.Quantity * p.ProductionUnitsPerPurchaseUnit, 0)
                     ELSE NULL END AS DECIMAL(18,4)) AS ProductionUnitCost
    FROM   dbo.PoultryRawMaterialPurchases p
    INNER  JOIN dbo.PoultryRawMaterialItems i ON i.PoultryRawMaterialItemId = p.PoultryRawMaterialItemId
    WHERE  p.FarmId = @FarmId
       AND (@FromDate IS NULL OR CAST(p.PurchaseDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(p.PurchaseDate AS DATE) <= @ToDate)
    ORDER  BY p.PurchaseDate DESC, p.PoultryRawMaterialPurchaseId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialPurchase_Insert
    @FarmId                  NVARCHAR(450),
    @PoultryRawMaterialItemId INT,
    @SupplierName            NVARCHAR(200) = NULL,
    @SupplierId              INT           = NULL,
    @PurchaseDate            DATETIME2     = NULL,
    @Quantity                DECIMAL(14,3),
    @UnitCost                DECIMAL(14,2),
    @TotalCost               DECIMAL(14,2) = NULL,  -- exact total; NULL => Qty*UnitCost
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

    BEGIN TRANSACTION;

    INSERT INTO dbo.PoultryRawMaterialPurchases (
        FarmId, PoultryRawMaterialItemId, SupplierName, SupplierId, PurchaseDate,
        Quantity, UnitCost, TotalCost, ProductionUnit, ProductionUnitsPerPurchaseUnit,
        PaymentMethod, AmountPaid, ReceiptUrl, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @PoultryRawMaterialItemId, @SupplierName, @SupplierId, ISNULL(@PurchaseDate, SYSUTCDATETIME()),
        @Quantity, @UnitCost, @TotalCost, @ProductionUnit, @ProductionUnitsPerPurchaseUnit,
        @PaymentMethod, @AmountPaid, @ReceiptUrl, @Notes, @CreatedBy
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    UPDATE dbo.PoultryRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity + @Quantity, UpdatedAt = SYSUTCDATETIME()
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

    DECLARE @OldQty DECIMAL(14,3), @ItemId INT;
    SELECT @OldQty = Quantity, @ItemId = PoultryRawMaterialItemId
    FROM   dbo.PoultryRawMaterialPurchases
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @OldQty IS NULL BEGIN RAISERROR('Purchase %d not found.', 16, 1, @PoultryRawMaterialPurchaseId); RETURN; END

    DECLARE @Delta DECIMAL(14,3) = @Quantity - @OldQty;
    IF (@Delta < 0)
    BEGIN
        DECLARE @CurrentStock DECIMAL(14,3) = (SELECT CurrentQuantity FROM dbo.PoultryRawMaterialItems WHERE PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId);
        IF (@CurrentStock + @Delta < 0)
        BEGIN
            DECLARE @Msg NVARCHAR(400) = CONCAT(N'Cannot reduce quantity: only ', CONVERT(NVARCHAR(40), @CurrentStock), N' units remain in stock.');
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
           ReceiptUrl = @ReceiptUrl, Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    IF (@Delta <> 0)
        UPDATE dbo.PoultryRawMaterialItems
        SET    CurrentQuantity = CurrentQuantity + @Delta, UpdatedAt = SYSUTCDATETIME()
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

    DECLARE @Qty DECIMAL(14,3), @ItemId INT;
    SELECT @Qty = Quantity, @ItemId = PoultryRawMaterialItemId
    FROM   dbo.PoultryRawMaterialPurchases
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @Qty IS NULL BEGIN RAISERROR('Purchase %d not found.', 16, 1, @PoultryRawMaterialPurchaseId); RETURN; END

    BEGIN TRANSACTION;
    DELETE FROM dbo.PoultryRawMaterialPurchases
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    UPDATE dbo.PoultryRawMaterialItems
    SET    CurrentQuantity = CASE WHEN CurrentQuantity - @Qty < 0 THEN 0 ELSE CurrentQuantity - @Qty END,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

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

    DECLARE @Total DECIMAL(14,2), @Paid DECIMAL(14,2);
    SELECT @Total = TotalCost, @Paid = AmountPaid
    FROM   dbo.PoultryRawMaterialPurchases
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @Total IS NULL BEGIN RAISERROR('Purchase not found for this company.', 16, 1); RETURN; END
    DECLARE @Outstanding DECIMAL(14,2) = @Total - @Paid;
    IF (@Outstanding <= 0) BEGIN RAISERROR('This purchase has no outstanding balance.', 16, 1); RETURN; END
    IF (@Amount IS NULL OR @Amount <= 0) BEGIN RAISERROR('Payment amount must be greater than 0.', 16, 1); RETURN; END
    IF (@Amount > @Outstanding) SET @Amount = @Outstanding;

    UPDATE dbo.PoultryRawMaterialPurchases
    SET    AmountPaid = AmountPaid + @Amount, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    SELECT CAST(TotalCost - AmountPaid AS DECIMAL(14,2)) AS Balance
    FROM   dbo.PoultryRawMaterialPurchases
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;
END
GO

-- ---- Usage history ----------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialUsage_GetHistory
    @FarmId NVARCHAR(450),
    @PoultryRawMaterialItemId INT = NULL,
    @FromDate DATE = NULL,
    @ToDate   DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.*, i.ItemName, i.UnitOfMeasure
    FROM   dbo.PoultryRawMaterialUsage u
    INNER  JOIN dbo.PoultryRawMaterialItems i ON i.PoultryRawMaterialItemId = u.PoultryRawMaterialItemId
    WHERE  u.FarmId = @FarmId
       AND (@PoultryRawMaterialItemId IS NULL OR u.PoultryRawMaterialItemId = @PoultryRawMaterialItemId)
       AND (@FromDate IS NULL OR CAST(u.UsedDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(u.UsedDate AS DATE) <= @ToDate)
    ORDER  BY u.UsedDate DESC, u.PoultryRawMaterialUsageId DESC;
END
GO

-- =============================================================================
-- Grants to the application login (matches ConnectionStrings__PoultryConn user)
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_GetAll      TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_Insert      TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_Update      TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_Delete      TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_GetAll  TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Insert  TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Update  TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Delete  TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_PayBalance TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialUsage_GetHistory TO [Techretainer];
    PRINT '123: granted EXECUTE on spPoultryRawMaterial* to Techretainer.';
END
GO

PRINT '123_AddPoultryRawMaterialsInventory.sql complete.';
GO

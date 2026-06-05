-- =============================================================================
-- Migration 030: Products, Services, and Inventory schema for Generic Company
-- =============================================================================
-- Builds on Migration 028 (Generic Company foundation). Adds the catalog
-- (products + services) and the inventory layer (stock movements + stock
-- adjustments) for any Generic Company.
--
-- Run order:
--   1. 028_AddGenericCompanyFoundation.sql
--   2. 029_AddGenericCompanyStoredProcedures.sql
--   3. This file (Phase 2 schema).
--   4. 031_AddGenericInventoryStoredProcedures.sql
--
-- Safety:
--   * Idempotent (IF NOT EXISTS / COL_LENGTH).
--   * Additive only.
--
-- Design notes:
--   * GenericStockMovements is the single source of truth for "what's on
--     hand". Quantity is SIGNED: positive for inflow (purchase, return,
--     opening, transfer-in, adjustment-up), negative for outflow (sale,
--     damage, expired, internal-use, transfer-out, adjustment-down).
--     SUM(Quantity) WHERE ProductId = X is the live stock.
--   * GenericProducts.CurrentStock is a denormalised cache for fast
--     dashboard reads, kept in sync by the SPs. Reconciliation is provided
--     in 031.
--   * InventoryLocationId is nullable everywhere so we don't need a
--     Branches/Locations table yet. The branches phase will populate it.
--   * StockAdjustments uses an approval workflow (Draft → Submitted →
--     Approved/Rejected) per the spec. The approve SP is transactional:
--     it writes the matching StockMovement AND updates Product.CurrentStock
--     in one transaction.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. GenericProductCategories (per-FarmId)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericProductCategories', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericProductCategories (
        GenericProductCategoryId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                    NVARCHAR(450) NOT NULL,
        Name                      NVARCHAR(100) NOT NULL,
        Description               NVARCHAR(500) NULL,
        IsActive                  BIT           NOT NULL CONSTRAINT DF_GenericProductCategories_IsActive DEFAULT (1),
        IsDeleted                 BIT           NOT NULL CONSTRAINT DF_GenericProductCategories_IsDeleted DEFAULT (0),
        CreatedAt                 DATETIME2     NOT NULL CONSTRAINT DF_GenericProductCategories_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                 DATETIME2     NULL,
        CONSTRAINT UQ_GenericProductCategories_Farm_Name UNIQUE (FarmId, Name)
    );

    CREATE INDEX IX_GenericProductCategories_FarmId ON dbo.GenericProductCategories (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 2. GenericProducts (per-FarmId)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericProducts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericProducts (
        GenericProductId            INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                      NVARCHAR(450)  NOT NULL,
        GenericProductCategoryId    INT            NULL,
        ProductName                 NVARCHAR(200)  NOT NULL,
        SKU                         NVARCHAR(60)   NULL,
        Barcode                     NVARCHAR(60)   NULL,
        UnitOfMeasure               NVARCHAR(30)   NULL,        -- e.g. piece, kg, litre, pack
        CostPrice                   DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericProducts_CostPrice DEFAULT (0),
        SellingPrice                DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericProducts_SellingPrice DEFAULT (0),
        WholesalePrice              DECIMAL(14,2)  NULL,
        RetailPrice                 DECIMAL(14,2)  NULL,
        OpeningStock                DECIMAL(14,3)  NOT NULL CONSTRAINT DF_GenericProducts_OpeningStock DEFAULT (0),
        CurrentStock                DECIMAL(14,3)  NOT NULL CONSTRAINT DF_GenericProducts_CurrentStock DEFAULT (0),
        MinimumStockAlert           DECIMAL(14,3)  NOT NULL CONSTRAINT DF_GenericProducts_MinStock DEFAULT (0),
        TrackInventory              BIT            NOT NULL CONSTRAINT DF_GenericProducts_TrackInventory DEFAULT (1),
        SupplierId                  INT            NULL,            -- generic supplier FK in phase 3
        IsActive                    BIT            NOT NULL CONSTRAINT DF_GenericProducts_IsActive DEFAULT (1),
        IsDeleted                   BIT            NOT NULL CONSTRAINT DF_GenericProducts_IsDeleted DEFAULT (0),
        Notes                       NVARCHAR(1000) NULL,
        CreatedAt                   DATETIME2      NOT NULL CONSTRAINT DF_GenericProducts_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                   DATETIME2      NULL,
        CONSTRAINT FK_GenericProducts_Category
            FOREIGN KEY (GenericProductCategoryId) REFERENCES dbo.GenericProductCategories (GenericProductCategoryId)
    );

    CREATE INDEX IX_GenericProducts_FarmId   ON dbo.GenericProducts (FarmId);
    CREATE INDEX IX_GenericProducts_Category ON dbo.GenericProducts (GenericProductCategoryId);
    CREATE INDEX IX_GenericProducts_SKU      ON dbo.GenericProducts (FarmId, SKU);
END
GO

-- -----------------------------------------------------------------------------
-- 3. GenericServiceCategories (per-FarmId)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericServiceCategories', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericServiceCategories (
        GenericServiceCategoryId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                    NVARCHAR(450) NOT NULL,
        Name                      NVARCHAR(100) NOT NULL,
        Description               NVARCHAR(500) NULL,
        IsActive                  BIT           NOT NULL CONSTRAINT DF_GenericServiceCategories_IsActive DEFAULT (1),
        IsDeleted                 BIT           NOT NULL CONSTRAINT DF_GenericServiceCategories_IsDeleted DEFAULT (0),
        CreatedAt                 DATETIME2     NOT NULL CONSTRAINT DF_GenericServiceCategories_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                 DATETIME2     NULL,
        CONSTRAINT UQ_GenericServiceCategories_Farm_Name UNIQUE (FarmId, Name)
    );

    CREATE INDEX IX_GenericServiceCategories_FarmId ON dbo.GenericServiceCategories (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 4. GenericServices (per-FarmId)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericServices', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericServices (
        GenericServiceId           INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                     NVARCHAR(450)  NOT NULL,
        GenericServiceCategoryId   INT            NULL,
        ServiceName                NVARCHAR(200)  NOT NULL,
        DefaultPrice               DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericServices_DefaultPrice DEFAULT (0),
        EstimatedCost              DECIMAL(14,2)  NULL,
        DurationMinutes            INT            NULL,
        AssignedStaffId            INT            NULL,         -- generic staff FK in phase 4
        IsActive                   BIT            NOT NULL CONSTRAINT DF_GenericServices_IsActive DEFAULT (1),
        IsDeleted                  BIT            NOT NULL CONSTRAINT DF_GenericServices_IsDeleted DEFAULT (0),
        Notes                      NVARCHAR(1000) NULL,
        CreatedAt                  DATETIME2      NOT NULL CONSTRAINT DF_GenericServices_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                  DATETIME2      NULL,
        CONSTRAINT FK_GenericServices_Category
            FOREIGN KEY (GenericServiceCategoryId) REFERENCES dbo.GenericServiceCategories (GenericServiceCategoryId)
    );

    CREATE INDEX IX_GenericServices_FarmId   ON dbo.GenericServices (FarmId);
    CREATE INDEX IX_GenericServices_Category ON dbo.GenericServices (GenericServiceCategoryId);
END
GO

-- -----------------------------------------------------------------------------
-- 5. GenericStockMovements (signed quantities; source of truth for stock)
-- -----------------------------------------------------------------------------
-- MovementType allowed values (validated at the application layer):
--   OpeningStock, PurchaseIn, SaleOut, ReturnIn, DamageOut, ExpiredOut,
--   InternalUseOut, AdjustmentIn, AdjustmentOut, TransferIn, TransferOut.
--
-- Quantity is signed:
--   * positive for *In types and AdjustmentIn / OpeningStock / ReturnIn
--   * negative for *Out types (SaleOut, DamageOut, ExpiredOut,
--     InternalUseOut, AdjustmentOut, TransferOut).
--
-- The signed convention lets us do SUM(Quantity) for stock-on-hand without
-- a CASE statement on every read.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericStockMovements', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericStockMovements (
        GenericStockMovementId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450) NOT NULL,
        GenericProductId        INT           NOT NULL,
        InventoryLocationId     INT           NULL,       -- branches phase
        MovementDate            DATETIME2     NOT NULL CONSTRAINT DF_GenericStockMovements_Date DEFAULT (SYSUTCDATETIME()),
        MovementType            NVARCHAR(30)  NOT NULL,
        Quantity                DECIMAL(14,3) NOT NULL,   -- signed
        UnitCost                DECIMAL(14,2) NULL,
        UnitSellingPrice        DECIMAL(14,2) NULL,
        TotalCostValue          DECIMAL(14,2) NULL,
        ReferenceType           NVARCHAR(60)  NULL,       -- 'Purchase' | 'Sale' | 'Adjustment' | 'Transfer' | 'Opening' | ...
        ReferenceId             INT           NULL,       -- id in the referenced table
        Reason                  NVARCHAR(500) NULL,
        CreatedBy               NVARCHAR(450) NULL,
        ApprovedBy              NVARCHAR(450) NULL,
        ApprovedAt              DATETIME2     NULL,
        Notes                   NVARCHAR(500) NULL,
        CreatedAt               DATETIME2     NOT NULL CONSTRAINT DF_GenericStockMovements_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_GenericStockMovements_Product
            FOREIGN KEY (GenericProductId) REFERENCES dbo.GenericProducts (GenericProductId)
    );

    CREATE INDEX IX_GenericStockMovements_FarmId    ON dbo.GenericStockMovements (FarmId);
    CREATE INDEX IX_GenericStockMovements_Product   ON dbo.GenericStockMovements (GenericProductId);
    CREATE INDEX IX_GenericStockMovements_Date      ON dbo.GenericStockMovements (MovementDate);
    CREATE INDEX IX_GenericStockMovements_Reference ON dbo.GenericStockMovements (ReferenceType, ReferenceId);
END
GO

-- -----------------------------------------------------------------------------
-- 6. GenericStockAdjustments (approval workflow)
-- -----------------------------------------------------------------------------
-- Status values (validated at app layer): Draft, Submitted, Approved, Rejected.
-- Quantity is the absolute magnitude (always positive). The sign is derived
-- from AdjustmentType (Increase/Decrease).
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericStockAdjustments', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericStockAdjustments (
        GenericStockAdjustmentId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                    NVARCHAR(450)  NOT NULL,
        GenericProductId          INT            NOT NULL,
        InventoryLocationId       INT            NULL,
        AdjustmentDate            DATETIME2      NOT NULL CONSTRAINT DF_GenericStockAdjustments_Date DEFAULT (SYSUTCDATETIME()),
        AdjustmentType            NVARCHAR(10)   NOT NULL,   -- 'Increase' | 'Decrease'
        Quantity                  DECIMAL(14,3)  NOT NULL,   -- positive magnitude
        Reason                    NVARCHAR(500)  NOT NULL,   -- required by spec
        Status                    NVARCHAR(20)   NOT NULL CONSTRAINT DF_GenericStockAdjustments_Status DEFAULT ('Draft'),
        RequestedBy               NVARCHAR(450)  NULL,
        ApprovedBy                NVARCHAR(450)  NULL,
        ApprovedAt                DATETIME2      NULL,
        RejectionReason           NVARCHAR(500)  NULL,
        Notes                     NVARCHAR(1000) NULL,
        CreatedAt                 DATETIME2      NOT NULL CONSTRAINT DF_GenericStockAdjustments_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                 DATETIME2      NULL,
        CONSTRAINT FK_GenericStockAdjustments_Product
            FOREIGN KEY (GenericProductId) REFERENCES dbo.GenericProducts (GenericProductId)
    );

    CREATE INDEX IX_GenericStockAdjustments_FarmId  ON dbo.GenericStockAdjustments (FarmId);
    CREATE INDEX IX_GenericStockAdjustments_Product ON dbo.GenericStockAdjustments (GenericProductId);
    CREATE INDEX IX_GenericStockAdjustments_Status  ON dbo.GenericStockAdjustments (Status);
END
GO

PRINT '030_AddGenericProductsServicesInventory.sql complete.';
GO

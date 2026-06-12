-- =============================================================================
-- Migration 043: Water Company — Raw Materials + Daily Closing + Loss Records
-- =============================================================================
-- Phase W3 schema. Idempotent + additive.
--
-- Tables:
--   * WaterRawMaterialItems       — packaging rolls, sachet film, chemicals, etc.
--   * WaterRawMaterialPurchases   — buying raw materials (increases stock)
--   * WaterRawMaterialUsage       — using raw materials in production (decreases stock + tracks variance)
--   * WaterLossRecords            — burst sachets, damages, bad debts, missing stock
--   * WaterDailyClosings          — owner's end-of-day snapshot (auto-aggregated)
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. WaterRawMaterialItems — the catalog
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterRawMaterialItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterRawMaterialItems (
        WaterRawMaterialItemId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450) NOT NULL,
        ItemName                NVARCHAR(150) NOT NULL,
        Category                NVARCHAR(40)  NOT NULL,         -- 'PackagingRoll' | 'SachetFilm' | 'OuterBag' | 'Chemical' | 'Filter' | 'UVLamp' | 'SparePart' | 'Fuel' | 'CleaningSupply' | 'Other'
        UnitOfMeasure           NVARCHAR(30)  NULL,              -- 'kg' | 'roll' | 'litre' | 'pack' | etc.
        MinimumStockAlert       DECIMAL(14,3) NOT NULL CONSTRAINT DF_WaterRawMaterialItems_Min DEFAULT (0),
        CurrentQuantity         DECIMAL(14,3) NOT NULL CONSTRAINT DF_WaterRawMaterialItems_Curr DEFAULT (0),
        IsActive                BIT           NOT NULL CONSTRAINT DF_WaterRawMaterialItems_IsActive DEFAULT (1),
        Notes                   NVARCHAR(500) NULL,
        CreatedAt               DATETIME2     NOT NULL CONSTRAINT DF_WaterRawMaterialItems_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt               DATETIME2     NULL,
        CONSTRAINT UQ_WaterRawMaterialItems_Farm_Name UNIQUE (FarmId, ItemName)
    );
    CREATE INDEX IX_WaterRawMaterialItems_FarmId ON dbo.WaterRawMaterialItems (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 2. WaterRawMaterialPurchases — buying raw materials
-- -----------------------------------------------------------------------------
-- On insert (no approval workflow for these — keep it simple), CurrentQuantity
-- on the raw material item is incremented.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterRawMaterialPurchases', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterRawMaterialPurchases (
        WaterRawMaterialPurchaseId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                      NVARCHAR(450) NOT NULL,
        WaterRawMaterialItemId      INT           NOT NULL,
        SupplierName                NVARCHAR(200) NULL,
        PurchaseDate                DATETIME2     NOT NULL CONSTRAINT DF_WaterRawMaterialPurchases_Date DEFAULT (SYSUTCDATETIME()),
        Quantity                    DECIMAL(14,3) NOT NULL,
        UnitCost                    DECIMAL(14,2) NOT NULL,
        TotalCost                   AS (Quantity * UnitCost) PERSISTED,
        PaymentMethod               NVARCHAR(30)  NULL,              -- 'Cash' | 'MoMo' | 'Bank' | 'Credit'
        AmountPaid                  DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterRawMaterialPurchases_Paid DEFAULT (0),
        ReceiptUrl                  NVARCHAR(500) NULL,
        ReceivedByStaffId           INT           NULL,
        Notes                       NVARCHAR(500) NULL,
        CreatedBy                   NVARCHAR(450) NULL,
        CreatedAt                   DATETIME2     NOT NULL CONSTRAINT DF_WaterRawMaterialPurchases_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                   DATETIME2     NULL,
        CONSTRAINT FK_WaterRawMaterialPurchases_Item FOREIGN KEY (WaterRawMaterialItemId) REFERENCES dbo.WaterRawMaterialItems (WaterRawMaterialItemId)
    );
    CREATE INDEX IX_WaterRawMaterialPurchases_FarmId ON dbo.WaterRawMaterialPurchases (FarmId);
    CREATE INDEX IX_WaterRawMaterialPurchases_Item   ON dbo.WaterRawMaterialPurchases (WaterRawMaterialItemId);
    CREATE INDEX IX_WaterRawMaterialPurchases_Date   ON dbo.WaterRawMaterialPurchases (PurchaseDate);
END
GO

-- -----------------------------------------------------------------------------
-- 3. WaterRawMaterialUsage — using raw materials in production
-- -----------------------------------------------------------------------------
-- Quantity actually used vs expected, with variance computed.
-- Optionally linked to a production batch.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterRawMaterialUsage', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterRawMaterialUsage (
        WaterRawMaterialUsageId    INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                     NVARCHAR(450) NOT NULL,
        WaterRawMaterialItemId     INT           NOT NULL,
        WaterProductionBatchId     INT           NULL,
        UsedDate                   DATETIME2     NOT NULL CONSTRAINT DF_WaterRawMaterialUsage_Date DEFAULT (SYSUTCDATETIME()),
        QuantityUsed               DECIMAL(14,3) NOT NULL,
        ExpectedQuantityUsed       DECIMAL(14,3) NULL,
        Variance                   AS (QuantityUsed - ISNULL(ExpectedQuantityUsed, QuantityUsed)) PERSISTED,
        VarianceReason             NVARCHAR(500) NULL,
        UsedByStaffId              INT           NULL,
        Notes                      NVARCHAR(500) NULL,
        CreatedBy                  NVARCHAR(450) NULL,
        CreatedAt                  DATETIME2     NOT NULL CONSTRAINT DF_WaterRawMaterialUsage_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                  DATETIME2     NULL,
        CONSTRAINT FK_WaterRawMaterialUsage_Item  FOREIGN KEY (WaterRawMaterialItemId)  REFERENCES dbo.WaterRawMaterialItems (WaterRawMaterialItemId),
        CONSTRAINT FK_WaterRawMaterialUsage_Batch FOREIGN KEY (WaterProductionBatchId) REFERENCES dbo.WaterProductionBatches (WaterProductionBatchId)
    );
    CREATE INDEX IX_WaterRawMaterialUsage_FarmId ON dbo.WaterRawMaterialUsage (FarmId);
    CREATE INDEX IX_WaterRawMaterialUsage_Item   ON dbo.WaterRawMaterialUsage (WaterRawMaterialItemId);
    CREATE INDEX IX_WaterRawMaterialUsage_Batch  ON dbo.WaterRawMaterialUsage (WaterProductionBatchId);
END
GO

-- -----------------------------------------------------------------------------
-- 4. WaterLossRecords — burst sachets, damages, missing stock, bad debt, etc.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterLossRecords', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterLossRecords (
        WaterLossRecordId       INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450) NOT NULL,
        LossDate                DATETIME2     NOT NULL CONSTRAINT DF_WaterLossRecords_Date DEFAULT (SYSUTCDATETIME()),
        LossType                NVARCHAR(40)  NOT NULL,         -- 'BurstSachets' | 'DamagedBags' | 'ReturnedBags' | 'MachineWaste' | 'PackagingWaste' | 'DriverShortage' | 'MissingStock' | 'BadDebt' | 'Other'
        WaterProductId          INT           NULL,
        QuantityBags            DECIMAL(14,3) NULL,
        QuantitySachets         DECIMAL(14,3) NULL,
        EstimatedValue          DECIMAL(14,2) NULL,
        ResponsibleStaffId      INT           NULL,
        Reason                  NVARCHAR(500) NULL,
        Status                  NVARCHAR(20)  NOT NULL CONSTRAINT DF_WaterLossRecords_Status DEFAULT ('Pending'),
        ApprovedBy              NVARCHAR(450) NULL,
        Notes                   NVARCHAR(500) NULL,
        CreatedBy               NVARCHAR(450) NULL,
        CreatedAt               DATETIME2     NOT NULL CONSTRAINT DF_WaterLossRecords_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt               DATETIME2     NULL
    );
    CREATE INDEX IX_WaterLossRecords_FarmId ON dbo.WaterLossRecords (FarmId);
    CREATE INDEX IX_WaterLossRecords_Date   ON dbo.WaterLossRecords (LossDate);
    CREATE INDEX IX_WaterLossRecords_Type   ON dbo.WaterLossRecords (LossType);
END
GO

-- -----------------------------------------------------------------------------
-- 5. WaterDailyClosings — auto-aggregated end-of-day snapshot
-- -----------------------------------------------------------------------------
-- The owner closes the day; the Submit SP aggregates everything from the
-- immutable tables for that date. Owner enters only ActualCashCounted +
-- ManagerNotes.
--
-- Workflow: Draft → Submitted (auto-aggregates) → Approved | Rejected
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterDailyClosings', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDailyClosings (
        WaterDailyClosingId        INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                     NVARCHAR(450) NOT NULL,
        ClosingDate                DATE          NOT NULL,
        OpeningStockBags           DECIMAL(14,3) NOT NULL CONSTRAINT DF_WaterDailyClosings_OpStock DEFAULT (0),
        BagsProduced               DECIMAL(14,3) NOT NULL CONSTRAINT DF_WaterDailyClosings_Produced DEFAULT (0),
        BagsSold                   DECIMAL(14,3) NOT NULL CONSTRAINT DF_WaterDailyClosings_Sold DEFAULT (0),
        BagsReturned               DECIMAL(14,3) NOT NULL CONSTRAINT DF_WaterDailyClosings_Returned DEFAULT (0),
        BagsDamaged                DECIMAL(14,3) NOT NULL CONSTRAINT DF_WaterDailyClosings_Damaged DEFAULT (0),
        ClosingStockBags           DECIMAL(14,3) NOT NULL CONSTRAINT DF_WaterDailyClosings_ClStock DEFAULT (0),
        TotalIncome                DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDailyClosings_Income DEFAULT (0),
        TotalExpenses              DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDailyClosings_Expenses DEFAULT (0),
        TotalProductionCost        DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDailyClosings_ProdCost DEFAULT (0),
        CashAtHand                 DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDailyClosings_Cash DEFAULT (0),
        ActualCashCounted          DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDailyClosings_ActCash DEFAULT (0),
        CashDifference             DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDailyClosings_CashDiff DEFAULT (0),
        CreditSales                DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDailyClosings_Credit DEFAULT (0),
        CustomerCollections        DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDailyClosings_Coll DEFAULT (0),
        DriverShortagesTotal       DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDailyClosings_Shortages DEFAULT (0),
        ManagerNotes               NVARCHAR(2000) NULL,
        DifferenceReason           NVARCHAR(500)  NULL,
        Status                     NVARCHAR(20)   NOT NULL CONSTRAINT DF_WaterDailyClosings_Status DEFAULT ('Draft'),
        CreatedBy                  NVARCHAR(450)  NULL,
        SubmittedBy                NVARCHAR(450)  NULL,
        SubmittedAt                DATETIME2      NULL,
        ApprovedBy                 NVARCHAR(450)  NULL,
        ApprovedAt                 DATETIME2      NULL,
        RejectionReason            NVARCHAR(500)  NULL,
        CreatedAt                  DATETIME2      NOT NULL CONSTRAINT DF_WaterDailyClosings_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                  DATETIME2      NULL
    );
    CREATE INDEX IX_WaterDailyClosings_FarmId ON dbo.WaterDailyClosings (FarmId);
    CREATE INDEX IX_WaterDailyClosings_Date   ON dbo.WaterDailyClosings (ClosingDate);
    CREATE INDEX IX_WaterDailyClosings_Status ON dbo.WaterDailyClosings (Status);

    CREATE UNIQUE INDEX UX_WaterDailyClosings_FarmDate
        ON dbo.WaterDailyClosings (FarmId, ClosingDate);
END
GO

PRINT '043_AddWaterRawMaterialsDailyClosing.sql complete.';
GO

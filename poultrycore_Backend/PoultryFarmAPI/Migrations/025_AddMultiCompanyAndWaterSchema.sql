-- =============================================================================
-- Migration 003: Multi-company support + Water company module schema
-- =============================================================================
-- Run order:
--   1. This file (schema) on whichever DB you target (local dev OR prod).
--   2. 004_AddMultiCompanyAndWaterStoredProcedures.sql for the SPs the
--      .NET services call.
--
-- Safety:
--   * All statements are idempotent (IF NOT EXISTS / COL_LENGTH checks).
--   * Additive only. No data is dropped or rewritten.
--   * Default Farms.Type to 'Poultry' so existing rows behave as before.
--
-- New concepts introduced:
--   * Farms.Type            -> 'Poultry' | 'Water' (extensible string)
--   * Farms.OwnerUserId     -> the user who created the farm (= the admin)
--   * UserFarms             -> join table letting one user belong to many farms
--   * Water* tables         -> independent module, all keyed by FarmId
-- =============================================================================

SET NOCOUNT ON;
-- Required for the computed column on dbo.WaterSaleItems (LineTotal PERSISTED).
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Extend Farms table with Type + OwnerUserId
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.Farms', 'U') IS NULL
BEGIN
    PRINT 'Farms table does not exist yet. Creating minimal Farms table.';
    CREATE TABLE dbo.Farms (
        FarmId       NVARCHAR(450)  NOT NULL PRIMARY KEY,
        Name         NVARCHAR(255)  NOT NULL,
        Email        NVARCHAR(255)  NULL,
        Type         NVARCHAR(50)   NOT NULL CONSTRAINT DF_Farms_Type DEFAULT ('Poultry'),
        PhoneNumber  NVARCHAR(50)   NULL,
        OwnerUserId  NVARCHAR(450)  NULL,
        CreatedAt    DATETIME2      NOT NULL CONSTRAINT DF_Farms_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt    DATETIME2      NULL
    );
END
ELSE
BEGIN
    IF COL_LENGTH('dbo.Farms', 'Type') IS NULL
    BEGIN
        PRINT 'Adding Farms.Type';
        ALTER TABLE dbo.Farms ADD Type NVARCHAR(50) NOT NULL CONSTRAINT DF_Farms_Type DEFAULT ('Poultry') WITH VALUES;
    END

    IF COL_LENGTH('dbo.Farms', 'OwnerUserId') IS NULL
    BEGIN
        PRINT 'Adding Farms.OwnerUserId';
        ALTER TABLE dbo.Farms ADD OwnerUserId NVARCHAR(450) NULL;
    END

    IF COL_LENGTH('dbo.Farms', 'UpdatedAt') IS NULL
    BEGIN
        PRINT 'Adding Farms.UpdatedAt';
        ALTER TABLE dbo.Farms ADD UpdatedAt DATETIME2 NULL;
    END
END
GO

-- Helpful index on Farms.OwnerUserId for "list-my-companies" lookups.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Farms_OwnerUserId' AND object_id = OBJECT_ID('dbo.Farms'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_Farms_OwnerUserId ON dbo.Farms (OwnerUserId);
END
GO

-- -----------------------------------------------------------------------------
-- 2. UserFarms join table  (one user <-> many farms with a role)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.UserFarms', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserFarms (
        UserId     NVARCHAR(450) NOT NULL,
        FarmId     NVARCHAR(450) NOT NULL,
        Role       NVARCHAR(50)  NOT NULL CONSTRAINT DF_UserFarms_Role DEFAULT ('Admin'),
        CreatedAt  DATETIME2     NOT NULL CONSTRAINT DF_UserFarms_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_UserFarms PRIMARY KEY (UserId, FarmId)
    );

    CREATE INDEX IX_UserFarms_FarmId ON dbo.UserFarms (FarmId);
END
GO

-- Backfill: for every existing AspNetUsers row that has a FarmId, ensure a
-- UserFarms row exists so they don't lose access after the migration.
-- Only runs if AspNetUsers exists (i.e. running against the login DB or a
-- combined DB; safe to skip on farm-only DBs).
IF OBJECT_ID('dbo.AspNetUsers', 'U') IS NOT NULL
BEGIN
    INSERT INTO dbo.UserFarms (UserId, FarmId, Role)
    SELECT u.Id, u.FarmId,
           CASE WHEN u.IsStaff = 1 THEN 'Staff' ELSE 'Admin' END
    FROM   dbo.AspNetUsers u
    WHERE  u.FarmId IS NOT NULL AND u.FarmId <> ''
    AND    NOT EXISTS (
              SELECT 1 FROM dbo.UserFarms uf
              WHERE  uf.UserId = u.Id AND uf.FarmId = u.FarmId
           );
    PRINT CONCAT('Backfilled UserFarms rows: ', @@ROWCOUNT);
END
GO

-- Backfill Farms.OwnerUserId from whoever created the farm (the non-staff
-- user attached to it). Only runs if AspNetUsers is present.
IF OBJECT_ID('dbo.AspNetUsers', 'U') IS NOT NULL
BEGIN
    UPDATE f
    SET f.OwnerUserId = u.Id
    FROM dbo.Farms f
    JOIN dbo.AspNetUsers u ON u.FarmId = f.FarmId AND u.IsStaff = 0
    WHERE f.OwnerUserId IS NULL;
    PRINT CONCAT('Backfilled Farms.OwnerUserId rows: ', @@ROWCOUNT);
END
GO

-- -----------------------------------------------------------------------------
-- 3. Water module tables (all scoped by FarmId)
-- -----------------------------------------------------------------------------

-- 3a. Products (sachets / bottles / dispensers / etc.)
IF OBJECT_ID('dbo.WaterProducts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterProducts (
        WaterProductId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId          NVARCHAR(450) NOT NULL,
        Name            NVARCHAR(150) NOT NULL,
        Sku             NVARCHAR(60)  NULL,
        SizeMl          INT           NULL,          -- e.g. 500, 750, 1500
        Unit            NVARCHAR(30)  NULL,          -- 'sachet','bottle','dispenser','gallon'
        UnitPrice       DECIMAL(12,2) NOT NULL CONSTRAINT DF_WaterProducts_UnitPrice DEFAULT (0),
        IsActive        BIT           NOT NULL CONSTRAINT DF_WaterProducts_IsActive DEFAULT (1),
        Notes           NVARCHAR(500) NULL,
        CreatedDate     DATETIME2     NOT NULL CONSTRAINT DF_WaterProducts_CreatedDate DEFAULT (SYSUTCDATETIME()),
        UpdatedDate     DATETIME2     NULL
    );

    CREATE INDEX IX_WaterProducts_FarmId ON dbo.WaterProducts (FarmId);
END
GO

-- 3b. Customers (separate from poultry-side customers)
IF OBJECT_ID('dbo.WaterCustomers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterCustomers (
        WaterCustomerId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId           NVARCHAR(450) NOT NULL,
        Name             NVARCHAR(150) NOT NULL,
        ContactPhone     NVARCHAR(50)  NULL,
        ContactEmail     NVARCHAR(150) NULL,
        Address          NVARCHAR(300) NULL,
        City             NVARCHAR(100) NULL,
        Notes            NVARCHAR(500) NULL,
        CreatedDate      DATETIME2     NOT NULL CONSTRAINT DF_WaterCustomers_CreatedDate DEFAULT (SYSUTCDATETIME()),
        UpdatedDate      DATETIME2     NULL
    );

    CREATE INDEX IX_WaterCustomers_FarmId ON dbo.WaterCustomers (FarmId);
END
GO

-- 3c. Stock transactions (single source of truth for "what's on hand")
-- Quantity is signed: +ve for restock/adjustment-up, -ve for sale/adjustment-down.
-- "Stock on hand" = SUM(Quantity) WHERE WaterProductId = X.
IF OBJECT_ID('dbo.WaterStockTransactions', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterStockTransactions (
        StockTxnId      INT IDENTITY(1,1) PRIMARY KEY,
        FarmId          NVARCHAR(450) NOT NULL,
        WaterProductId  INT           NOT NULL,
        TxnType         NVARCHAR(30)  NOT NULL,         -- 'Restock' | 'Adjust' | 'Sale' | 'Return'
        Quantity        INT           NOT NULL,         -- signed
        UnitCost        DECIMAL(12,2) NULL,             -- nullable: only restocks track cost
        RelatedSaleId   INT           NULL,             -- if TxnType='Sale', the WaterSales row
        Note            NVARCHAR(300) NULL,
        CreatedDate     DATETIME2     NOT NULL CONSTRAINT DF_WaterStockTxn_CreatedDate DEFAULT (SYSUTCDATETIME()),
        CreatedBy       NVARCHAR(450) NULL,
        CONSTRAINT FK_WaterStockTxn_Product FOREIGN KEY (WaterProductId)
            REFERENCES dbo.WaterProducts (WaterProductId)
    );

    CREATE INDEX IX_WaterStockTxn_FarmId       ON dbo.WaterStockTransactions (FarmId);
    CREATE INDEX IX_WaterStockTxn_ProductId    ON dbo.WaterStockTransactions (WaterProductId);
    CREATE INDEX IX_WaterStockTxn_CreatedDate  ON dbo.WaterStockTransactions (CreatedDate);
END
GO

-- 3d. Sales (header)
IF OBJECT_ID('dbo.WaterSales', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterSales (
        WaterSaleId      INT IDENTITY(1,1) PRIMARY KEY,
        FarmId           NVARCHAR(450) NOT NULL,
        WaterCustomerId  INT           NULL,             -- nullable: walk-in/cash sale
        SaleDate         DATETIME2     NOT NULL CONSTRAINT DF_WaterSales_SaleDate DEFAULT (SYSUTCDATETIME()),
        TotalAmount      DECIMAL(12,2) NOT NULL CONSTRAINT DF_WaterSales_TotalAmount DEFAULT (0),
        AmountPaid       DECIMAL(12,2) NOT NULL CONSTRAINT DF_WaterSales_AmountPaid DEFAULT (0),
        Status           NVARCHAR(30)  NOT NULL CONSTRAINT DF_WaterSales_Status DEFAULT ('Pending'),
                                                                                -- 'Pending' | 'Paid' | 'PartiallyPaid' | 'Cancelled'
        Notes            NVARCHAR(500) NULL,
        CreatedDate      DATETIME2     NOT NULL CONSTRAINT DF_WaterSales_CreatedDate DEFAULT (SYSUTCDATETIME()),
        CreatedBy        NVARCHAR(450) NULL,
        UpdatedDate      DATETIME2     NULL,
        CONSTRAINT FK_WaterSales_Customer FOREIGN KEY (WaterCustomerId)
            REFERENCES dbo.WaterCustomers (WaterCustomerId)
    );

    CREATE INDEX IX_WaterSales_FarmId    ON dbo.WaterSales (FarmId);
    CREATE INDEX IX_WaterSales_SaleDate  ON dbo.WaterSales (SaleDate);
    CREATE INDEX IX_WaterSales_Status    ON dbo.WaterSales (Status);
END
GO

-- 3e. Sale line items
IF OBJECT_ID('dbo.WaterSaleItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterSaleItems (
        WaterSaleItemId  INT IDENTITY(1,1) PRIMARY KEY,
        WaterSaleId      INT           NOT NULL,
        WaterProductId   INT           NOT NULL,
        Quantity         INT           NOT NULL,
        UnitPrice        DECIMAL(12,2) NOT NULL,
        LineTotal        AS (Quantity * UnitPrice) PERSISTED,
        CONSTRAINT FK_WaterSaleItems_Sale    FOREIGN KEY (WaterSaleId)
            REFERENCES dbo.WaterSales (WaterSaleId) ON DELETE CASCADE,
        CONSTRAINT FK_WaterSaleItems_Product FOREIGN KEY (WaterProductId)
            REFERENCES dbo.WaterProducts (WaterProductId)
    );

    CREATE INDEX IX_WaterSaleItems_SaleId    ON dbo.WaterSaleItems (WaterSaleId);
    CREATE INDEX IX_WaterSaleItems_ProductId ON dbo.WaterSaleItems (WaterProductId);
END
GO

-- 3f. Payments against sales
IF OBJECT_ID('dbo.WaterPayments', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterPayments (
        WaterPaymentId   INT IDENTITY(1,1) PRIMARY KEY,
        FarmId           NVARCHAR(450) NOT NULL,
        WaterSaleId      INT           NOT NULL,
        Amount           DECIMAL(12,2) NOT NULL,
        PaymentMethod    NVARCHAR(40)  NULL,              -- 'Cash','Mobile Money','Bank','Cheque'
        PaymentDate      DATETIME2     NOT NULL CONSTRAINT DF_WaterPayments_PaymentDate DEFAULT (SYSUTCDATETIME()),
        Reference        NVARCHAR(120) NULL,
        Note             NVARCHAR(300) NULL,
        CreatedDate      DATETIME2     NOT NULL CONSTRAINT DF_WaterPayments_CreatedDate DEFAULT (SYSUTCDATETIME()),
        CreatedBy        NVARCHAR(450) NULL,
        CONSTRAINT FK_WaterPayments_Sale FOREIGN KEY (WaterSaleId)
            REFERENCES dbo.WaterSales (WaterSaleId)
    );

    CREATE INDEX IX_WaterPayments_FarmId      ON dbo.WaterPayments (FarmId);
    CREATE INDEX IX_WaterPayments_WaterSaleId ON dbo.WaterPayments (WaterSaleId);
END
GO

PRINT '003_AddMultiCompanyAndWaterSchema.sql complete.';
GO

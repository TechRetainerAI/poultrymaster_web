-- =============================================================================
-- Migration 028: Generic Company foundation schema
-- =============================================================================
-- Adds the foundation tables for the new "Generic Company" CompanyType so one
-- owner can run a restaurant, hotel, shop, salon, pharmacy or any other small
-- business under the same platform that already supports Poultry and Water.
--
-- Run order:
--   1. This file (schema).
--   2. 029_AddGenericCompanyStoredProcedures.sql for the SPs the .NET services
--      call.
--
-- Safety:
--   * All statements are idempotent (IF NOT EXISTS / COL_LENGTH checks).
--   * Additive only. No existing rows are dropped or rewritten.
--   * Does NOT alter Farms / UserFarms; "Generic" piggy-backs on the existing
--     Farms.Type column. The string check is enforced at the application layer
--     to stay consistent with how 'Poultry' and 'Water' are handled today.
--
-- New concepts introduced:
--   * BusinessCategories        -> platform-wide lookup (Restaurant, Hotel, ...)
--   * GenericCompanyProfiles    -> per-Farm profile rows (1:1 with Farms where
--                                   Farms.Type = 'Generic')
--   * GenericExpenseCategories  -> per-Farm expense category seed (also reusable
--                                   by Poultry/Water if they want)
--   * GenericCashAccounts       -> per-Farm cash/bank/MoMo accounts
--   * GenericCustomerTypes      -> per-Farm customer type seed
--   * GenericSupplierTypes      -> per-Farm supplier type seed
--   * GenericPaymentMethods     -> per-Farm payment method seed
--
-- All per-Farm tables are scoped by FarmId so they never leak across companies.
-- Later phases (Sales, Inventory, etc.) will reuse these foundation tables.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. BusinessCategories (platform-wide lookup, not FarmId-scoped)
-- -----------------------------------------------------------------------------
-- Keep this as a global lookup so the UI can show the same dropdown to every
-- owner. Owners do NOT edit this table; only platform admins do.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.BusinessCategories', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.BusinessCategories (
        BusinessCategoryId  INT IDENTITY(1,1) PRIMARY KEY,
        Name                NVARCHAR(100) NOT NULL,
        Description         NVARCHAR(500) NULL,
        SortOrder           INT           NOT NULL CONSTRAINT DF_BusinessCategories_SortOrder DEFAULT (100),
        IsActive            BIT           NOT NULL CONSTRAINT DF_BusinessCategories_IsActive DEFAULT (1),
        CreatedAt           DATETIME2     NOT NULL CONSTRAINT DF_BusinessCategories_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt           DATETIME2     NULL,
        CONSTRAINT UQ_BusinessCategories_Name UNIQUE (Name)
    );
END
GO

-- Seed default business categories (idempotent: only inserts missing rows).
;WITH seed (Name, SortOrder, Description) AS (
    SELECT 'Restaurant',          10,  'Restaurants, food vendors, chop bars, takeaway'           UNION ALL
    SELECT 'Hotel / Guest House', 20,  'Hotels, guest houses, hostels, short-let rentals'         UNION ALL
    SELECT 'Retail Shop',         30,  'General retail shops'                                     UNION ALL
    SELECT 'Supermarket',         40,  'Supermarkets and mini-marts'                              UNION ALL
    SELECT 'Provision Store',     50,  'Provision stores, kiosks, container shops'                UNION ALL
    SELECT 'Boutique / Clothing', 60,  'Boutiques, clothing, shoes, fashion accessories'          UNION ALL
    SELECT 'Salon / Barber Shop', 70,  'Hair salons, barbering shops, nail/beauty studios'        UNION ALL
    SELECT 'Pharmacy',            80,  'Pharmacies, chemical shops, OTC drug stores'              UNION ALL
    SELECT 'Hardware Store',      90,  'Hardware, building materials, plumbing, electrical'       UNION ALL
    SELECT 'Transport Business',  100, 'Trotros, taxis, ride-hail, haulage, charter'              UNION ALL
    SELECT 'School',              110, 'Schools, daycare, training centres'                       UNION ALL
    SELECT 'Services Business',   120, 'General services, consulting, repair, cleaning'           UNION ALL
    SELECT 'Manufacturing',       130, 'Small factories, food processing, bakeries'               UNION ALL
    SELECT 'General Trading',     140, 'Buying-and-selling traders without a fixed category'      UNION ALL
    SELECT 'Other',               999, 'Anything else'
)
INSERT INTO dbo.BusinessCategories (Name, SortOrder, Description)
SELECT s.Name, s.SortOrder, s.Description
FROM   seed s
WHERE  NOT EXISTS (SELECT 1 FROM dbo.BusinessCategories b WHERE b.Name = s.Name);
GO

-- -----------------------------------------------------------------------------
-- 2. GenericCompanyProfiles (one row per Farms where Type='Generic')
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericCompanyProfiles', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericCompanyProfiles (
        GenericCompanyProfileId    INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                     NVARCHAR(450)  NOT NULL,
        BusinessCategoryId         INT            NULL,
        BusinessCategoryNameSnapshot NVARCHAR(100) NULL,   -- captured at create so renames don't break audits
        BusinessDescription        NVARCHAR(500)  NULL,
        DefaultCurrency            NVARCHAR(10)   NOT NULL CONSTRAINT DF_GenericCompanyProfiles_Currency DEFAULT ('GHC'),
        OpeningCashBalance         DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericCompanyProfiles_Opening DEFAULT (0),
        BusinessStartDate          DATE           NULL,
        MainLocation               NVARCHAR(255)  NULL,
        OwnerName                  NVARCHAR(150)  NULL,
        PhoneNumber                NVARCHAR(50)   NULL,
        Notes                      NVARCHAR(1000) NULL,
        CreatedAt                  DATETIME2      NOT NULL CONSTRAINT DF_GenericCompanyProfiles_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                  DATETIME2      NULL,
        CONSTRAINT UQ_GenericCompanyProfiles_FarmId UNIQUE (FarmId),
        CONSTRAINT FK_GenericCompanyProfiles_BusinessCategory
            FOREIGN KEY (BusinessCategoryId) REFERENCES dbo.BusinessCategories (BusinessCategoryId)
    );

    CREATE INDEX IX_GenericCompanyProfiles_FarmId ON dbo.GenericCompanyProfiles (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 3. GenericExpenseCategories (per-FarmId)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericExpenseCategories', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericExpenseCategories (
        GenericExpenseCategoryId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                    NVARCHAR(450) NOT NULL,
        Name                      NVARCHAR(100) NOT NULL,
        Description               NVARCHAR(500) NULL,
        IsActive                  BIT           NOT NULL CONSTRAINT DF_GenericExpenseCategories_IsActive DEFAULT (1),
        IsDeleted                 BIT           NOT NULL CONSTRAINT DF_GenericExpenseCategories_IsDeleted DEFAULT (0),
        CreatedAt                 DATETIME2     NOT NULL CONSTRAINT DF_GenericExpenseCategories_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                 DATETIME2     NULL,
        CONSTRAINT UQ_GenericExpenseCategories_Farm_Name UNIQUE (FarmId, Name)
    );

    CREATE INDEX IX_GenericExpenseCategories_FarmId ON dbo.GenericExpenseCategories (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 4. GenericCashAccounts (per-FarmId)
-- -----------------------------------------------------------------------------
-- AccountType values are validated in code; kept as NVARCHAR for flexibility.
-- Allowed: 'MainCashBox','PettyCash','OwnerCash','MoMoWallet','BankAccount',
--          'StaffCash','BranchCash','Other'
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericCashAccounts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericCashAccounts (
        GenericCashAccountId    INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450)  NOT NULL,
        AccountName             NVARCHAR(150)  NOT NULL,
        AccountType             NVARCHAR(40)   NOT NULL,
        OpeningBalance          DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericCashAccounts_Opening DEFAULT (0),
        CurrentBalance          DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericCashAccounts_Current DEFAULT (0),
        AllowNegativeBalance    BIT            NOT NULL CONSTRAINT DF_GenericCashAccounts_AllowNeg DEFAULT (0),
        IsActive                BIT            NOT NULL CONSTRAINT DF_GenericCashAccounts_IsActive DEFAULT (1),
        Notes                   NVARCHAR(500)  NULL,
        CreatedAt               DATETIME2      NOT NULL CONSTRAINT DF_GenericCashAccounts_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt               DATETIME2      NULL,
        CONSTRAINT UQ_GenericCashAccounts_Farm_Name UNIQUE (FarmId, AccountName)
    );

    CREATE INDEX IX_GenericCashAccounts_FarmId ON dbo.GenericCashAccounts (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 5. GenericCustomerTypes (per-FarmId seed)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericCustomerTypes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericCustomerTypes (
        GenericCustomerTypeId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                 NVARCHAR(450) NOT NULL,
        Name                   NVARCHAR(60)  NOT NULL,
        IsActive               BIT           NOT NULL CONSTRAINT DF_GenericCustomerTypes_IsActive DEFAULT (1),
        CreatedAt              DATETIME2     NOT NULL CONSTRAINT DF_GenericCustomerTypes_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt              DATETIME2     NULL,
        CONSTRAINT UQ_GenericCustomerTypes_Farm_Name UNIQUE (FarmId, Name)
    );

    CREATE INDEX IX_GenericCustomerTypes_FarmId ON dbo.GenericCustomerTypes (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 6. GenericSupplierTypes (per-FarmId seed)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericSupplierTypes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericSupplierTypes (
        GenericSupplierTypeId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                 NVARCHAR(450) NOT NULL,
        Name                   NVARCHAR(60)  NOT NULL,
        IsActive               BIT           NOT NULL CONSTRAINT DF_GenericSupplierTypes_IsActive DEFAULT (1),
        CreatedAt              DATETIME2     NOT NULL CONSTRAINT DF_GenericSupplierTypes_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt              DATETIME2     NULL,
        CONSTRAINT UQ_GenericSupplierTypes_Farm_Name UNIQUE (FarmId, Name)
    );

    CREATE INDEX IX_GenericSupplierTypes_FarmId ON dbo.GenericSupplierTypes (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 7. GenericPaymentMethods (per-FarmId seed)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericPaymentMethods', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericPaymentMethods (
        GenericPaymentMethodId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450) NOT NULL,
        Name                    NVARCHAR(40)  NOT NULL,
        IsActive                BIT           NOT NULL CONSTRAINT DF_GenericPaymentMethods_IsActive DEFAULT (1),
        CreatedAt               DATETIME2     NOT NULL CONSTRAINT DF_GenericPaymentMethods_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt               DATETIME2     NULL,
        CONSTRAINT UQ_GenericPaymentMethods_Farm_Name UNIQUE (FarmId, Name)
    );

    CREATE INDEX IX_GenericPaymentMethods_FarmId ON dbo.GenericPaymentMethods (FarmId);
END
GO

PRINT '028_AddGenericCompanyFoundation.sql complete.';
GO

-- =============================================================================
-- Migration 138: Poultry Company — Driver Distribution schema
-- =============================================================================
-- Full-fidelity port of the Water driver / distribution subsystem to Poultry
-- (mirrors water migrations 040 + 064 + the column-adds from 083/093).
--
-- Vocabulary: water's "bag / sachet" becomes poultry's "crate / eggs-per-crate".
--   BagsLoaded -> CratesLoaded, SachetsPerBag -> EggsPerCrate,
--   CommissionPerBag -> CommissionPerCrate, CapacityBags -> CapacityCrates,
--   ExpectedBagsSold -> ExpectedCratesSold,
--   ExpectedSellingPricePerBag -> ExpectedSellingPricePerCrate.
--
-- The workflow this enables:
--   1. Load a vehicle with N crates for a driver/route (Draft -> Loaded writes
--      a 'Delivery Load' PoultryStockTransaction on approval).
--   2. Driver sells on a route, returns leftover crates + cash collected.
--   3. Driver return is recorded against the loading.
--   4. On approval: reconcile crates (sold + returned + damaged + missing =
--      loaded), materialize sales/expenses/cash into the poultry ledgers, log
--      any shortage, and write a 'Delivery Return' stock movement.
--
-- Coexists with the simpler flat PoultryDeliveries module (migration 133) —
-- these are separate tables. All tables scoped by FarmId. Idempotent + additive.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. PoultryDrivers — drivers and delivery riders
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryDrivers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryDrivers (
        PoultryDriverId      INT IDENTITY(1,1) PRIMARY KEY,
        FarmId               NVARCHAR(450) NOT NULL,
        DriverName           NVARCHAR(150) NOT NULL,
        PhoneNumber          NVARCHAR(50)  NULL,
        LicenseNumber        NVARCHAR(60)  NULL,
        DefaultVehicleId     INT           NULL,
        DefaultRouteId       INT           NULL,
        BasePay              DECIMAL(14,2) NULL,
        CommissionPerCrate   DECIMAL(14,2) NULL,
        IsActive             BIT           NOT NULL CONSTRAINT DF_PoultryDrivers_IsActive DEFAULT (1),
        EmployeeUserId       NVARCHAR(450) NULL,
        Notes                NVARCHAR(500) NULL,
        CreatedAt            DATETIME2     NOT NULL CONSTRAINT DF_PoultryDrivers_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt            DATETIME2     NULL
    );
    CREATE INDEX IX_PoultryDrivers_FarmId ON dbo.PoultryDrivers (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 2. PoultryVehicles
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryVehicles', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryVehicles (
        PoultryVehicleId     INT IDENTITY(1,1) PRIMARY KEY,
        FarmId               NVARCHAR(450) NOT NULL,
        VehicleName          NVARCHAR(150) NOT NULL,
        VehicleType          NVARCHAR(30)  NULL,        -- 'Truck' | 'Van' | 'Tricycle' | 'Motorbike' | 'Pickup' | 'Other'
        RegistrationNumber   NVARCHAR(60)  NULL,
        DefaultDriverId      INT           NULL,
        CapacityCrates       INT           NULL,
        FuelType             NVARCHAR(30)  NULL,
        Status               NVARCHAR(30)  NOT NULL CONSTRAINT DF_PoultryVehicles_Status DEFAULT ('Active'),
        Notes                NVARCHAR(500) NULL,
        CreatedAt            DATETIME2     NOT NULL CONSTRAINT DF_PoultryVehicles_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt            DATETIME2     NULL
    );
    CREATE INDEX IX_PoultryVehicles_FarmId ON dbo.PoultryVehicles (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 3. PoultryRoutes
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryRoutes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryRoutes (
        PoultryRouteId           INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450) NOT NULL,
        RouteName                NVARCHAR(150) NOT NULL,
        AreaCovered              NVARCHAR(500) NULL,
        DefaultDriverId          INT           NULL,
        DefaultVehicleId         INT           NULL,
        ExpectedCustomers        INT           NULL,
        ExpectedCratesSold       INT           NULL,
        Notes                    NVARCHAR(500) NULL,
        IsActive                 BIT           NOT NULL CONSTRAINT DF_PoultryRoutes_IsActive DEFAULT (1),
        CreatedAt                DATETIME2     NOT NULL CONSTRAINT DF_PoultryRoutes_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                DATETIME2     NULL
    );
    CREATE INDEX IX_PoultryRoutes_FarmId ON dbo.PoultryRoutes (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 4. PoultryVehicleLoadings — the "load Van 1 with 300 crates" event
-- -----------------------------------------------------------------------------
-- Workflow: Draft -> Loaded (writes 'Delivery Load' -qty stock txn) ->
-- Reconciled (after driver return) -> Cancelled.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryVehicleLoadings', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryVehicleLoadings (
        PoultryVehicleLoadingId      INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                       NVARCHAR(450) NOT NULL,
        LoadDate                     DATETIME2     NOT NULL CONSTRAINT DF_PoultryVehicleLoadings_Date DEFAULT (SYSUTCDATETIME()),
        PoultryVehicleId             INT           NOT NULL,
        PoultryDriverId              INT           NULL,
        AssistantStaffId             INT           NULL,
        PoultryRouteId               INT           NULL,
        PoultryProductId             INT           NOT NULL,
        CratesLoaded                 INT           NOT NULL,
        EggsPerCrate                 INT           NOT NULL CONSTRAINT DF_PoultryVehicleLoadings_EPC DEFAULT (30),
        ExpectedSellingPricePerCrate DECIMAL(14,2) NOT NULL,
        ExpectedCash                 AS (CAST(CratesLoaded AS DECIMAL(14,2)) * ExpectedSellingPricePerCrate) PERSISTED,
        OpeningCashWithDriver        DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryVehicleLoadings_OpeningCash DEFAULT (0),
        LoadedByStaffId              INT           NULL,
        Status                       NVARCHAR(20)  NOT NULL CONSTRAINT DF_PoultryVehicleLoadings_Status DEFAULT ('Draft'),
        Notes                        NVARCHAR(500) NULL,
        CreatedBy                    NVARCHAR(450) NULL,
        ApprovedBy                   NVARCHAR(450) NULL,
        ApprovedAt                   DATETIME2     NULL,
        CreatedAt                    DATETIME2     NOT NULL CONSTRAINT DF_PoultryVehicleLoadings_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                    DATETIME2     NULL,
        IsDeleted                    BIT           NOT NULL CONSTRAINT DF_PoultryVehicleLoadings_IsDeleted DEFAULT (0),
        CONSTRAINT FK_PoultryVehicleLoadings_Vehicle FOREIGN KEY (PoultryVehicleId) REFERENCES dbo.PoultryVehicles (PoultryVehicleId),
        CONSTRAINT FK_PoultryVehicleLoadings_Product FOREIGN KEY (PoultryProductId) REFERENCES dbo.PoultryProducts (PoultryProductId),
        CONSTRAINT FK_PoultryVehicleLoadings_Driver  FOREIGN KEY (PoultryDriverId)  REFERENCES dbo.PoultryDrivers (PoultryDriverId),
        CONSTRAINT FK_PoultryVehicleLoadings_Route   FOREIGN KEY (PoultryRouteId)   REFERENCES dbo.PoultryRoutes (PoultryRouteId)
    );
    CREATE INDEX IX_PoultryVehicleLoadings_FarmId  ON dbo.PoultryVehicleLoadings (FarmId);
    CREATE INDEX IX_PoultryVehicleLoadings_Date    ON dbo.PoultryVehicleLoadings (LoadDate);
    CREATE INDEX IX_PoultryVehicleLoadings_Status  ON dbo.PoultryVehicleLoadings (Status);
    CREATE INDEX IX_PoultryVehicleLoadings_Vehicle ON dbo.PoultryVehicleLoadings (PoultryVehicleId);
    CREATE INDEX IX_PoultryVehicleLoadings_Driver  ON dbo.PoultryVehicleLoadings (PoultryDriverId);
END
GO

-- -----------------------------------------------------------------------------
-- 5. PoultryVehicleLoadingItems — multi-product loadings
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryVehicleLoadingItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryVehicleLoadingItems (
        PoultryVehicleLoadingItemId INT IDENTITY(1,1) PRIMARY KEY,
        PoultryVehicleLoadingId     INT           NOT NULL,
        PoultryProductId            INT           NOT NULL,
        CratesLoaded                INT           NOT NULL,
        EggsPerCrate                INT           NOT NULL CONSTRAINT DF_PoultryVehicleLoadingItems_EPC DEFAULT (30),
        UnitPrice                   DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryVehicleLoadingItems_UP DEFAULT (0),
        ExpectedAmount              AS (CAST(CratesLoaded AS DECIMAL(14,2)) * UnitPrice) PERSISTED,
        Notes                       NVARCHAR(300) NULL,
        CreatedAt                   DATETIME2     NOT NULL CONSTRAINT DF_PoultryVehicleLoadingItems_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                   DATETIME2     NULL,
        CONSTRAINT FK_PoultryVehicleLoadingItems_Loading FOREIGN KEY (PoultryVehicleLoadingId)
            REFERENCES dbo.PoultryVehicleLoadings (PoultryVehicleLoadingId) ON DELETE CASCADE,
        CONSTRAINT FK_PoultryVehicleLoadingItems_Product FOREIGN KEY (PoultryProductId)
            REFERENCES dbo.PoultryProducts (PoultryProductId)
    );
    CREATE INDEX IX_PoultryVehicleLoadingItems_Loading ON dbo.PoultryVehicleLoadingItems (PoultryVehicleLoadingId);
    CREATE INDEX IX_PoultryVehicleLoadingItems_Product ON dbo.PoultryVehicleLoadingItems (PoultryProductId);
END
GO

-- -----------------------------------------------------------------------------
-- 6. PoultryDriverReturns — what the driver brought back
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryDriverReturns', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryDriverReturns (
        PoultryDriverReturnId      INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                     NVARCHAR(450) NOT NULL,
        PoultryVehicleLoadingId    INT           NOT NULL,
        ReturnDate                 DATETIME2     NOT NULL CONSTRAINT DF_PoultryDriverReturns_Date DEFAULT (SYSUTCDATETIME()),
        CratesSold                 INT           NOT NULL,
        CratesReturned             INT           NOT NULL,
        CratesDamaged              INT           NOT NULL CONSTRAINT DF_PoultryDriverReturns_Damaged DEFAULT (0),
        MissingCrates              INT           NOT NULL CONSTRAINT DF_PoultryDriverReturns_Missing DEFAULT (0),
        CashCollected              DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryDriverReturns_Cash DEFAULT (0),
        MoMoCollected              DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryDriverReturns_MoMo DEFAULT (0),
        BankCollected              DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryDriverReturns_Bank DEFAULT (0),
        CreditSalesAmount          DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryDriverReturns_Credit DEFAULT (0),
        TotalAccountedFor          AS (CashCollected + MoMoCollected + BankCollected + CreditSalesAmount) PERSISTED,
        CashReturnedByDriver       DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryDriverReturns_CashReturned DEFAULT (0),
        ApprovedDeliveryExpenses   DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryDriverReturns_ApprovedExp DEFAULT (0),
        ShortageAmount             DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryDriverReturns_Shortage DEFAULT (0),
        OverageAmount              DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryDriverReturns_Overage DEFAULT (0),
        SalesPostingMode           NVARCHAR(20)  NOT NULL CONSTRAINT DF_PoultryDriverReturns_PostingMode DEFAULT ('Detailed'), -- Detailed | OneCustomer | Summary
        PrimaryCustomerId          INT           NULL,
        LinkedCashAdjId            INT           NULL,        -- dbo.CashAdjustment row created on approve (for reversal)
        ReconciledByStaffId        INT           NULL,
        Status                     NVARCHAR(20)  NOT NULL CONSTRAINT DF_PoultryDriverReturns_Status DEFAULT ('Draft'),
        Notes                      NVARCHAR(1000) NULL,
        CreatedBy                  NVARCHAR(450) NULL,
        ApprovedBy                 NVARCHAR(450) NULL,
        ApprovedAt                 DATETIME2     NULL,
        CreatedAt                  DATETIME2     NOT NULL CONSTRAINT DF_PoultryDriverReturns_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                  DATETIME2     NULL,
        CONSTRAINT FK_PoultryDriverReturns_Loading FOREIGN KEY (PoultryVehicleLoadingId) REFERENCES dbo.PoultryVehicleLoadings (PoultryVehicleLoadingId)
    );
    CREATE INDEX IX_PoultryDriverReturns_FarmId  ON dbo.PoultryDriverReturns (FarmId);
    CREATE INDEX IX_PoultryDriverReturns_Loading ON dbo.PoultryDriverReturns (PoultryVehicleLoadingId);
    CREATE INDEX IX_PoultryDriverReturns_Date    ON dbo.PoultryDriverReturns (ReturnDate);
    CREATE INDEX IX_PoultryDriverReturns_Status  ON dbo.PoultryDriverReturns (Status);
END
GO

-- -----------------------------------------------------------------------------
-- 7. PoultryDriverReturnItems — per-product reconciliation
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryDriverReturnItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryDriverReturnItems (
        PoultryDriverReturnItemId INT IDENTITY(1,1) PRIMARY KEY,
        PoultryDriverReturnId     INT           NOT NULL,
        PoultryProductId          INT           NOT NULL,
        CratesLoaded              INT           NOT NULL,    -- snapshotted from loading at insert time
        CratesSold                INT           NOT NULL CONSTRAINT DF_PoultryDriverReturnItems_Sold DEFAULT (0),
        CratesReturned            INT           NOT NULL CONSTRAINT DF_PoultryDriverReturnItems_Returned DEFAULT (0),
        CratesDamaged             INT           NOT NULL CONSTRAINT DF_PoultryDriverReturnItems_Damaged DEFAULT (0),
        UnitPrice                 DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryDriverReturnItems_UP DEFAULT (0),
        ExpectedSales             AS (CAST(CratesSold AS DECIMAL(14,2)) * UnitPrice) PERSISTED,
        Notes                     NVARCHAR(300) NULL,
        CreatedAt                 DATETIME2     NOT NULL CONSTRAINT DF_PoultryDriverReturnItems_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                 DATETIME2     NULL,
        CONSTRAINT FK_PoultryDriverReturnItems_Return  FOREIGN KEY (PoultryDriverReturnId)
            REFERENCES dbo.PoultryDriverReturns (PoultryDriverReturnId) ON DELETE CASCADE,
        CONSTRAINT FK_PoultryDriverReturnItems_Product FOREIGN KEY (PoultryProductId)
            REFERENCES dbo.PoultryProducts (PoultryProductId)
    );
    CREATE INDEX IX_PoultryDriverReturnItems_Return  ON dbo.PoultryDriverReturnItems (PoultryDriverReturnId);
    CREATE INDEX IX_PoultryDriverReturnItems_Product ON dbo.PoultryDriverReturnItems (PoultryProductId);
END
GO

-- -----------------------------------------------------------------------------
-- 8. Customer breakdown — shop-level sales within a return
-- -----------------------------------------------------------------------------
-- CustomerId is a loose (un-constrained) reference to the generic Customers
-- table; CustomerLabel is the free-text fallback for walk-ins and the name
-- copied onto the materialized Sale row. GeneratedSaleId links to dbo.Sale
-- once the parent return is Approved.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryDriverReturnCustomerSales', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryDriverReturnCustomerSales (
        PoultryDriverReturnCustomerSaleId INT IDENTITY(1,1) PRIMARY KEY,
        PoultryDriverReturnId             INT           NOT NULL,
        CustomerId                        INT           NULL,    -- loose ref to generic Customers; nullable walk-in
        CustomerLabel                     NVARCHAR(150) NULL,
        TotalAmount                       DECIMAL(14,2) NOT NULL CONSTRAINT DF_PDRCS_Total DEFAULT (0),
        CashPaid                          DECIMAL(14,2) NOT NULL CONSTRAINT DF_PDRCS_Cash DEFAULT (0),
        MoMoPaid                          DECIMAL(14,2) NOT NULL CONSTRAINT DF_PDRCS_MoMo DEFAULT (0),
        BankPaid                          DECIMAL(14,2) NOT NULL CONSTRAINT DF_PDRCS_Bank DEFAULT (0),
        CreditAmount                      DECIMAL(14,2) NOT NULL CONSTRAINT DF_PDRCS_Credit DEFAULT (0),
        Notes                             NVARCHAR(500) NULL,
        GeneratedSaleId                   INT           NULL,
        CreatedAt                         DATETIME2     NOT NULL CONSTRAINT DF_PDRCS_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                         DATETIME2     NULL,
        CONSTRAINT FK_PDRCS_Return FOREIGN KEY (PoultryDriverReturnId) REFERENCES dbo.PoultryDriverReturns (PoultryDriverReturnId) ON DELETE CASCADE
    );
    CREATE INDEX IX_PDRCS_Return   ON dbo.PoultryDriverReturnCustomerSales (PoultryDriverReturnId);
    CREATE INDEX IX_PDRCS_Customer ON dbo.PoultryDriverReturnCustomerSales (CustomerId);
END
GO

IF OBJECT_ID('dbo.PoultryDriverReturnCustomerSaleItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryDriverReturnCustomerSaleItems (
        PoultryDriverReturnCustomerSaleItemId INT IDENTITY(1,1) PRIMARY KEY,
        PoultryDriverReturnCustomerSaleId     INT           NOT NULL,
        PoultryProductId                      INT           NOT NULL,
        Quantity                              INT           NOT NULL,
        UnitPrice                             DECIMAL(14,2) NOT NULL,
        LineTotal                             AS (CAST(Quantity AS DECIMAL(14,2)) * UnitPrice) PERSISTED,
        CreatedAt                             DATETIME2     NOT NULL CONSTRAINT DF_PDRCSI_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_PDRCSI_Sale    FOREIGN KEY (PoultryDriverReturnCustomerSaleId) REFERENCES dbo.PoultryDriverReturnCustomerSales (PoultryDriverReturnCustomerSaleId) ON DELETE CASCADE,
        CONSTRAINT FK_PDRCSI_Product FOREIGN KEY (PoultryProductId)                  REFERENCES dbo.PoultryProducts (PoultryProductId)
    );
    CREATE INDEX IX_PDRCSI_Sale ON dbo.PoultryDriverReturnCustomerSaleItems (PoultryDriverReturnCustomerSaleId);
END
GO

-- -----------------------------------------------------------------------------
-- 9. Delivery expenses
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryDriverDeliveryExpenses', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryDriverDeliveryExpenses (
        PoultryDriverDeliveryExpenseId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                         NVARCHAR(450) NOT NULL,
        PoultryDriverReturnId          INT           NULL,
        PoultryVehicleLoadingId        INT           NULL,
        ExpenseCategory                NVARCHAR(40)  NOT NULL,    -- 'Fuel' | 'LoadingBoys' | 'Toll' | 'Repair' | 'PhoneCredit' | 'ChopMoney' | 'Other'
        Amount                         DECIMAL(14,2) NOT NULL,
        Description                    NVARCHAR(500) NULL,
        IsApproved                     BIT           NOT NULL CONSTRAINT DF_PDDE_IsApproved DEFAULT (1),
        LinkedExpenseId                INT           NULL,        -- dbo.Expense row created on approve
        Notes                          NVARCHAR(500) NULL,
        CreatedBy                      NVARCHAR(450) NULL,
        CreatedAt                      DATETIME2     NOT NULL CONSTRAINT DF_PDDE_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                      DATETIME2     NULL,
        CONSTRAINT FK_PDDE_Return  FOREIGN KEY (PoultryDriverReturnId)   REFERENCES dbo.PoultryDriverReturns (PoultryDriverReturnId) ON DELETE CASCADE,
        CONSTRAINT FK_PDDE_Loading FOREIGN KEY (PoultryVehicleLoadingId) REFERENCES dbo.PoultryVehicleLoadings (PoultryVehicleLoadingId)
    );
    CREATE INDEX IX_PDDE_FarmId  ON dbo.PoultryDriverDeliveryExpenses (FarmId);
    CREATE INDEX IX_PDDE_Return  ON dbo.PoultryDriverDeliveryExpenses (PoultryDriverReturnId);
    CREATE INDEX IX_PDDE_Loading ON dbo.PoultryDriverDeliveryExpenses (PoultryVehicleLoadingId);
END
GO

-- -----------------------------------------------------------------------------
-- 10. PoultryDriverShortages — auto-created on approval when ShortageAmount > 0
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryDriverShortages', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryDriverShortages (
        PoultryDriverShortageId    INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                     NVARCHAR(450) NOT NULL,
        PoultryDriverId            INT           NULL,
        PoultryVehicleLoadingId    INT           NULL,
        PoultryDriverReturnId      INT           NOT NULL,
        ShortageDate               DATETIME2     NOT NULL CONSTRAINT DF_PoultryDriverShortages_Date DEFAULT (SYSUTCDATETIME()),
        ExpectedAmount             DECIMAL(14,2) NOT NULL,
        ActualAmount               DECIMAL(14,2) NOT NULL,
        ShortageAmount             DECIMAL(14,2) NOT NULL,
        Reason                     NVARCHAR(500) NULL,
        Status                     NVARCHAR(20)  NOT NULL CONSTRAINT DF_PoultryDriverShortages_Status DEFAULT ('Pending'), -- Pending | Approved | Deducted | Waived
        ApprovedBy                 NVARCHAR(450) NULL,
        Notes                      NVARCHAR(500) NULL,
        CreatedAt                  DATETIME2     NOT NULL CONSTRAINT DF_PoultryDriverShortages_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                  DATETIME2     NULL,
        CONSTRAINT FK_PoultryDriverShortages_Return FOREIGN KEY (PoultryDriverReturnId) REFERENCES dbo.PoultryDriverReturns (PoultryDriverReturnId)
    );
    CREATE INDEX IX_PoultryDriverShortages_FarmId ON dbo.PoultryDriverShortages (FarmId);
    CREATE INDEX IX_PoultryDriverShortages_Driver ON dbo.PoultryDriverShortages (PoultryDriverId);
    CREATE INDEX IX_PoultryDriverShortages_Status ON dbo.PoultryDriverShortages (Status);
END
GO

PRINT '138_AddPoultryDriverDistributionSchema.sql complete.';
GO

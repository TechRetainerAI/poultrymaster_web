-- =============================================================================
-- Migration 040: Water Company — Distribution schema
-- =============================================================================
-- Phase W2: WaterVehicles, WaterRoutes, WaterDrivers, WaterVehicleLoadings,
-- WaterDriverReturns, WaterDriverShortages.
--
-- The big workflow this enables:
--   1. Load a vehicle with N bags for a driver/route (creates a Loaded record,
--      writes a LoadOut stock movement on approval).
--   2. Driver goes out, sells some, returns the rest + cash/MoMo collected.
--   3. Driver return is recorded against the loading.
--   4. On approval of the return: reconcile bags (sold + returned + damaged
--      = loaded), compute expected vs actual cash, log any shortage, write
--      a LoadReturnIn stock movement for the unsold bags.
--
-- All tables scoped by FarmId. Idempotent + additive.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. WaterDrivers — drivers and motorking riders
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterDrivers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDrivers (
        WaterDriverId        INT IDENTITY(1,1) PRIMARY KEY,
        FarmId               NVARCHAR(450) NOT NULL,
        DriverName           NVARCHAR(150) NOT NULL,
        PhoneNumber          NVARCHAR(50)  NULL,
        LicenseNumber        NVARCHAR(60)  NULL,
        DefaultVehicleId     INT           NULL,
        DefaultRouteId       INT           NULL,
        BasePay              DECIMAL(14,2) NULL,
        CommissionPerBag     DECIMAL(14,2) NULL,
        IsActive             BIT           NOT NULL CONSTRAINT DF_WaterDrivers_IsActive DEFAULT (1),
        Notes                NVARCHAR(500) NULL,
        CreatedAt            DATETIME2     NOT NULL CONSTRAINT DF_WaterDrivers_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt            DATETIME2     NULL
    );
    CREATE INDEX IX_WaterDrivers_FarmId ON dbo.WaterDrivers (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 2. WaterVehicles
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterVehicles', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterVehicles (
        WaterVehicleId       INT IDENTITY(1,1) PRIMARY KEY,
        FarmId               NVARCHAR(450) NOT NULL,
        VehicleName          NVARCHAR(150) NOT NULL,
        VehicleType          NVARCHAR(30)  NULL,        -- 'Truck' | 'MotorKing' | 'Tricycle' | 'Van' | 'Motorbike' | 'Other'
        RegistrationNumber   NVARCHAR(60)  NULL,
        DefaultDriverId      INT           NULL,
        CapacityBags         INT           NULL,
        FuelType             NVARCHAR(30)  NULL,
        Status               NVARCHAR(30)  NOT NULL CONSTRAINT DF_WaterVehicles_Status DEFAULT ('Active'),
        Notes                NVARCHAR(500) NULL,
        CreatedAt            DATETIME2     NOT NULL CONSTRAINT DF_WaterVehicles_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt            DATETIME2     NULL
    );
    CREATE INDEX IX_WaterVehicles_FarmId ON dbo.WaterVehicles (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 3. WaterRoutes
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterRoutes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterRoutes (
        WaterRouteId             INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450) NOT NULL,
        RouteName                NVARCHAR(150) NOT NULL,
        AreaCovered              NVARCHAR(500) NULL,
        DefaultDriverId          INT           NULL,
        DefaultVehicleId         INT           NULL,
        ExpectedCustomers        INT           NULL,
        ExpectedBagsSold         INT           NULL,
        Notes                    NVARCHAR(500) NULL,
        IsActive                 BIT           NOT NULL CONSTRAINT DF_WaterRoutes_IsActive DEFAULT (1),
        CreatedAt                DATETIME2     NOT NULL CONSTRAINT DF_WaterRoutes_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                DATETIME2     NULL
    );
    CREATE INDEX IX_WaterRoutes_FarmId ON dbo.WaterRoutes (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 4. WaterVehicleLoadings — the "load Truck 1 with 1200 bags" event
-- -----------------------------------------------------------------------------
-- Workflow: Draft → Loaded (writes -LoadOut stock txn) → Reconciled (after
-- driver return) → Cancelled.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterVehicleLoadings', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterVehicleLoadings (
        WaterVehicleLoadingId      INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                     NVARCHAR(450) NOT NULL,
        LoadDate                   DATETIME2     NOT NULL CONSTRAINT DF_WaterVehicleLoadings_Date DEFAULT (SYSUTCDATETIME()),
        WaterVehicleId             INT           NOT NULL,
        WaterDriverId              INT           NULL,
        AssistantStaffId           INT           NULL,
        WaterRouteId               INT           NULL,
        WaterProductId             INT           NOT NULL,
        BagsLoaded                 INT           NOT NULL,
        SachetsPerBag              INT           NOT NULL CONSTRAINT DF_WaterVehicleLoadings_SPB DEFAULT (30),
        ExpectedSellingPricePerBag DECIMAL(14,2) NOT NULL,
        ExpectedCash               AS (CAST(BagsLoaded AS DECIMAL(14,2)) * ExpectedSellingPricePerBag) PERSISTED,
        OpeningCashWithDriver      DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterVehicleLoadings_OpeningCash DEFAULT (0),
        LoadedByStaffId            INT           NULL,
        Status                     NVARCHAR(20)  NOT NULL CONSTRAINT DF_WaterVehicleLoadings_Status DEFAULT ('Draft'),
        Notes                      NVARCHAR(500) NULL,
        CreatedBy                  NVARCHAR(450) NULL,
        ApprovedBy                 NVARCHAR(450) NULL,
        ApprovedAt                 DATETIME2     NULL,
        CreatedAt                  DATETIME2     NOT NULL CONSTRAINT DF_WaterVehicleLoadings_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                  DATETIME2     NULL,
        IsDeleted                  BIT           NOT NULL CONSTRAINT DF_WaterVehicleLoadings_IsDeleted DEFAULT (0),
        CONSTRAINT FK_WaterVehicleLoadings_Vehicle FOREIGN KEY (WaterVehicleId) REFERENCES dbo.WaterVehicles (WaterVehicleId),
        CONSTRAINT FK_WaterVehicleLoadings_Product FOREIGN KEY (WaterProductId) REFERENCES dbo.WaterProducts (WaterProductId),
        CONSTRAINT FK_WaterVehicleLoadings_Driver  FOREIGN KEY (WaterDriverId)  REFERENCES dbo.WaterDrivers (WaterDriverId),
        CONSTRAINT FK_WaterVehicleLoadings_Route   FOREIGN KEY (WaterRouteId)   REFERENCES dbo.WaterRoutes (WaterRouteId)
    );
    CREATE INDEX IX_WaterVehicleLoadings_FarmId  ON dbo.WaterVehicleLoadings (FarmId);
    CREATE INDEX IX_WaterVehicleLoadings_Date    ON dbo.WaterVehicleLoadings (LoadDate);
    CREATE INDEX IX_WaterVehicleLoadings_Status  ON dbo.WaterVehicleLoadings (Status);
    CREATE INDEX IX_WaterVehicleLoadings_Vehicle ON dbo.WaterVehicleLoadings (WaterVehicleId);
    CREATE INDEX IX_WaterVehicleLoadings_Driver  ON dbo.WaterVehicleLoadings (WaterDriverId);
END
GO

-- -----------------------------------------------------------------------------
-- 5. WaterDriverReturns — what the driver brought back
-- -----------------------------------------------------------------------------
-- On approval (Status='Approved'):
--   * BagsLoaded must equal BagsSold + BagsReturned + BagsDamaged (+ MissingBags).
--   * Insert LoadReturnIn stock txn for BagsReturned (back to warehouse).
--   * Compute ShortageAmount = ExpectedCash - TotalAccountedFor (when > 0).
--   * Compute OverageAmount  = TotalAccountedFor - ExpectedCash (when > 0).
--   * If ShortageAmount > 0 → insert WaterDriverShortages row.
--   * Parent loading's Status → 'Reconciled'.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterDriverReturns', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDriverReturns (
        WaterDriverReturnId        INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                     NVARCHAR(450) NOT NULL,
        WaterVehicleLoadingId      INT           NOT NULL,
        ReturnDate                 DATETIME2     NOT NULL CONSTRAINT DF_WaterDriverReturns_Date DEFAULT (SYSUTCDATETIME()),
        BagsSold                   INT           NOT NULL,
        BagsReturned               INT           NOT NULL,
        BagsDamaged                INT           NOT NULL CONSTRAINT DF_WaterDriverReturns_Damaged DEFAULT (0),
        MissingBags                INT           NOT NULL CONSTRAINT DF_WaterDriverReturns_Missing DEFAULT (0),
        CashCollected              DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDriverReturns_Cash DEFAULT (0),
        MoMoCollected              DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDriverReturns_MoMo DEFAULT (0),
        BankCollected              DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDriverReturns_Bank DEFAULT (0),
        CreditSalesAmount          DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDriverReturns_Credit DEFAULT (0),
        TotalAccountedFor          AS (CashCollected + MoMoCollected + BankCollected + CreditSalesAmount) PERSISTED,
        ShortageAmount             DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDriverReturns_Shortage DEFAULT (0),
        OverageAmount              DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDriverReturns_Overage DEFAULT (0),
        ReconciledByStaffId        INT           NULL,
        Status                     NVARCHAR(20)  NOT NULL CONSTRAINT DF_WaterDriverReturns_Status DEFAULT ('Draft'),
        Notes                      NVARCHAR(1000) NULL,
        CreatedBy                  NVARCHAR(450) NULL,
        ApprovedBy                 NVARCHAR(450) NULL,
        ApprovedAt                 DATETIME2     NULL,
        CreatedAt                  DATETIME2     NOT NULL CONSTRAINT DF_WaterDriverReturns_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                  DATETIME2     NULL,
        CONSTRAINT FK_WaterDriverReturns_Loading FOREIGN KEY (WaterVehicleLoadingId) REFERENCES dbo.WaterVehicleLoadings (WaterVehicleLoadingId)
    );
    CREATE INDEX IX_WaterDriverReturns_FarmId    ON dbo.WaterDriverReturns (FarmId);
    CREATE INDEX IX_WaterDriverReturns_Loading   ON dbo.WaterDriverReturns (WaterVehicleLoadingId);
    CREATE INDEX IX_WaterDriverReturns_Date      ON dbo.WaterDriverReturns (ReturnDate);
    CREATE INDEX IX_WaterDriverReturns_Status    ON dbo.WaterDriverReturns (Status);
END
GO

-- -----------------------------------------------------------------------------
-- 6. WaterDriverShortages — auto-created on approval when ShortageAmount > 0
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterDriverShortages', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDriverShortages (
        WaterDriverShortageId      INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                     NVARCHAR(450) NOT NULL,
        WaterDriverId              INT           NULL,
        WaterVehicleLoadingId      INT           NULL,
        WaterDriverReturnId        INT           NOT NULL,
        ShortageDate               DATETIME2     NOT NULL CONSTRAINT DF_WaterDriverShortages_Date DEFAULT (SYSUTCDATETIME()),
        ExpectedAmount             DECIMAL(14,2) NOT NULL,
        ActualAmount               DECIMAL(14,2) NOT NULL,
        ShortageAmount             DECIMAL(14,2) NOT NULL,
        Reason                     NVARCHAR(500) NULL,
        Status                     NVARCHAR(20)  NOT NULL CONSTRAINT DF_WaterDriverShortages_Status DEFAULT ('Pending'),
        ApprovedBy                 NVARCHAR(450) NULL,
        Notes                      NVARCHAR(500) NULL,
        CreatedAt                  DATETIME2     NOT NULL CONSTRAINT DF_WaterDriverShortages_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                  DATETIME2     NULL,
        CONSTRAINT FK_WaterDriverShortages_Return FOREIGN KEY (WaterDriverReturnId) REFERENCES dbo.WaterDriverReturns (WaterDriverReturnId)
    );
    CREATE INDEX IX_WaterDriverShortages_FarmId ON dbo.WaterDriverShortages (FarmId);
    CREATE INDEX IX_WaterDriverShortages_Driver ON dbo.WaterDriverShortages (WaterDriverId);
    CREATE INDEX IX_WaterDriverShortages_Status ON dbo.WaterDriverShortages (Status);
END
GO

PRINT '040_AddWaterDistributionSchema.sql complete.';
GO

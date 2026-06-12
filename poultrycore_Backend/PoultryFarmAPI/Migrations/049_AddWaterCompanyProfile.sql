-- =============================================================================
-- Migration 049: Water Company profile (setup metadata) — W5
-- =============================================================================
-- Fills Water spec §1 (Setup) and mirrors the GenericCompanyProfiles design
-- from migration 028. One profile row per FarmId, created when the owner runs
-- the Water setup flow. The profile is non-blocking — endpoints that only
-- need Type='Water' continue to work without it — but the dashboard,
-- receipts, and exports surface fields from here when present.
--
-- Schema: brand, business sub-type (Sachet / Bottled / Both), production site,
-- water source type, default currency (GHC), default bag→sachet conversion
-- (30), owner contact details.
--
-- The matching setup SP also calls spWaterFinance_SeedDefaults (from 048) so
-- one POST sets up everything a brand-new Water Company needs.
--
-- Run order: 047 → 048 → 049 (this file).
-- Idempotent (IF OBJECT_ID), additive only.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. WaterCompanyProfiles  (one row per FarmId)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterCompanyProfiles', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterCompanyProfiles (
        WaterCompanyProfileId    INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450)  NOT NULL,
        BrandName                NVARCHAR(150)  NULL,
        BusinessType             NVARCHAR(30)   NOT NULL CONSTRAINT DF_WaterCompanyProfiles_BizType  DEFAULT ('Sachet'),   -- Sachet | Bottled | Both
        ProductionSiteAddress    NVARCHAR(500)  NULL,
        MainLocation             NVARCHAR(255)  NULL,
        WaterSourceType          NVARCHAR(30)   NOT NULL CONSTRAINT DF_WaterCompanyProfiles_Source   DEFAULT ('Borehole'), -- Borehole | GhanaWater | Tanker | Mixed
        DefaultCurrency          NVARCHAR(10)   NOT NULL CONSTRAINT DF_WaterCompanyProfiles_Currency DEFAULT ('GHC'),
        DefaultBagSachetCount    INT            NOT NULL CONSTRAINT DF_WaterCompanyProfiles_BagCount DEFAULT (30),
        OwnerName                NVARCHAR(150)  NULL,
        PhoneNumber              NVARCHAR(50)   NULL,
        Notes                    NVARCHAR(1000) NULL,
        CreatedAt                DATETIME2      NOT NULL CONSTRAINT DF_WaterCompanyProfiles_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                DATETIME2      NULL,
        CONSTRAINT UQ_WaterCompanyProfiles_FarmId UNIQUE (FarmId)
    );

    CREATE INDEX IX_WaterCompanyProfiles_FarmId ON dbo.WaterCompanyProfiles (FarmId);
END
GO

-- =============================================================================
-- Stored procedures
-- =============================================================================

-- Get profile (or NULL row count if not set up yet).
CREATE OR ALTER PROCEDURE dbo.spWaterCompany_GetProfile
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT WaterCompanyProfileId, FarmId, BrandName, BusinessType,
           ProductionSiteAddress, MainLocation, WaterSourceType,
           DefaultCurrency, DefaultBagSachetCount, OwnerName, PhoneNumber, Notes,
           CreatedAt, UpdatedAt
    FROM   dbo.WaterCompanyProfiles
    WHERE  FarmId = @FarmId;
END
GO

-- Setup: validates the farm exists and Type='Water', creates the profile (idempotent —
-- if a profile row already exists for this farm, the values are updated instead),
-- and runs the finance defaults seed (categories + cash accounts) from migration 048.
CREATE OR ALTER PROCEDURE dbo.spWaterCompany_Setup
    @FarmId                  NVARCHAR(450),
    @BrandName               NVARCHAR(150)  = NULL,
    @BusinessType            NVARCHAR(30)   = 'Sachet',
    @ProductionSiteAddress   NVARCHAR(500)  = NULL,
    @MainLocation            NVARCHAR(255)  = NULL,
    @WaterSourceType         NVARCHAR(30)   = 'Borehole',
    @DefaultCurrency         NVARCHAR(10)   = 'GHC',
    @DefaultBagSachetCount   INT            = 30,
    @OwnerName               NVARCHAR(150)  = NULL,
    @PhoneNumber             NVARCHAR(50)   = NULL,
    @Notes                   NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 1. Farm must exist and be Type='Water'.
    IF NOT EXISTS (SELECT 1 FROM dbo.Farms WHERE FarmId = @FarmId)
    BEGIN
        RAISERROR('Farm %s does not exist.', 16, 1, @FarmId);
        RETURN;
    END
    DECLARE @FarmType NVARCHAR(50);
    SELECT @FarmType = Type FROM dbo.Farms WHERE FarmId = @FarmId;
    IF (@FarmType IS NULL OR @FarmType <> 'Water')
    BEGIN
        RAISERROR('Farm %s is not a Water company (Type=%s).', 16, 1, @FarmId, @FarmType);
        RETURN;
    END

    -- 2. Validate the enums.
    IF @BusinessType   NOT IN ('Sachet', 'Bottled', 'Both')
    BEGIN RAISERROR('BusinessType must be Sachet, Bottled, or Both.', 16, 1); RETURN; END
    IF @WaterSourceType NOT IN ('Borehole', 'GhanaWater', 'Tanker', 'Mixed')
    BEGIN RAISERROR('WaterSourceType must be Borehole, GhanaWater, Tanker, or Mixed.', 16, 1); RETURN; END
    IF @DefaultBagSachetCount < 1
    BEGIN RAISERROR('DefaultBagSachetCount must be at least 1.', 16, 1); RETURN; END

    BEGIN TRANSACTION;

    -- 3. Upsert the profile.
    IF EXISTS (SELECT 1 FROM dbo.WaterCompanyProfiles WHERE FarmId = @FarmId)
    BEGIN
        UPDATE dbo.WaterCompanyProfiles
        SET    BrandName             = @BrandName,
               BusinessType          = @BusinessType,
               ProductionSiteAddress = @ProductionSiteAddress,
               MainLocation          = @MainLocation,
               WaterSourceType       = @WaterSourceType,
               DefaultCurrency       = ISNULL(@DefaultCurrency, 'GHC'),
               DefaultBagSachetCount = ISNULL(@DefaultBagSachetCount, 30),
               OwnerName             = @OwnerName,
               PhoneNumber           = @PhoneNumber,
               Notes                 = @Notes,
               UpdatedAt             = SYSUTCDATETIME()
        WHERE  FarmId = @FarmId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.WaterCompanyProfiles (
            FarmId, BrandName, BusinessType, ProductionSiteAddress, MainLocation,
            WaterSourceType, DefaultCurrency, DefaultBagSachetCount,
            OwnerName, PhoneNumber, Notes
        )
        VALUES (
            @FarmId, @BrandName, @BusinessType, @ProductionSiteAddress, @MainLocation,
            @WaterSourceType, ISNULL(@DefaultCurrency, 'GHC'), ISNULL(@DefaultBagSachetCount, 30),
            @OwnerName, @PhoneNumber, @Notes
        );
    END

    -- 4. Run the finance defaults (idempotent; safe on re-run).
    EXEC dbo.spWaterFinance_SeedDefaults @FarmId = @FarmId;

    COMMIT TRANSACTION;

    -- 5. Return the resulting profile + seed verification numbers.
    SELECT WaterCompanyProfileId, FarmId, BrandName, BusinessType,
           ProductionSiteAddress, MainLocation, WaterSourceType,
           DefaultCurrency, DefaultBagSachetCount, OwnerName, PhoneNumber, Notes,
           CreatedAt, UpdatedAt
    FROM   dbo.WaterCompanyProfiles
    WHERE  FarmId = @FarmId;
END
GO

-- Update profile only (no finance seed, no farm-type check beyond company scope).
CREATE OR ALTER PROCEDURE dbo.spWaterCompany_UpdateProfile
    @FarmId                  NVARCHAR(450),
    @BrandName               NVARCHAR(150)  = NULL,
    @BusinessType            NVARCHAR(30)   = NULL,
    @ProductionSiteAddress   NVARCHAR(500)  = NULL,
    @MainLocation            NVARCHAR(255)  = NULL,
    @WaterSourceType         NVARCHAR(30)   = NULL,
    @DefaultCurrency         NVARCHAR(10)   = NULL,
    @DefaultBagSachetCount   INT            = NULL,
    @OwnerName               NVARCHAR(150)  = NULL,
    @PhoneNumber             NVARCHAR(50)   = NULL,
    @Notes                   NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.WaterCompanyProfiles WHERE FarmId = @FarmId)
    BEGIN
        RAISERROR('Water Company profile not set up for farm %s. Call spWaterCompany_Setup first.', 16, 1, @FarmId);
        RETURN;
    END

    UPDATE dbo.WaterCompanyProfiles
    SET    BrandName             = ISNULL(@BrandName, BrandName),
           BusinessType          = ISNULL(@BusinessType, BusinessType),
           ProductionSiteAddress = ISNULL(@ProductionSiteAddress, ProductionSiteAddress),
           MainLocation          = ISNULL(@MainLocation, MainLocation),
           WaterSourceType       = ISNULL(@WaterSourceType, WaterSourceType),
           DefaultCurrency       = ISNULL(@DefaultCurrency, DefaultCurrency),
           DefaultBagSachetCount = ISNULL(@DefaultBagSachetCount, DefaultBagSachetCount),
           OwnerName             = ISNULL(@OwnerName, OwnerName),
           PhoneNumber           = ISNULL(@PhoneNumber, PhoneNumber),
           Notes                 = ISNULL(@Notes, Notes),
           UpdatedAt             = SYSUTCDATETIME()
    WHERE  FarmId = @FarmId;

    SELECT WaterCompanyProfileId, FarmId, BrandName, BusinessType,
           ProductionSiteAddress, MainLocation, WaterSourceType,
           DefaultCurrency, DefaultBagSachetCount, OwnerName, PhoneNumber, Notes,
           CreatedAt, UpdatedAt
    FROM   dbo.WaterCompanyProfiles
    WHERE  FarmId = @FarmId;
END
GO

-- EXECUTE grants for the runtime user (same loop as migration 042/048).
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterCompany_GetProfile     TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterCompany_Setup          TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterCompany_UpdateProfile  TO [Techretainer];
    PRINT '049: granted EXECUTE on spWaterCompany_* to Techretainer.';
END
GO

PRINT '049_AddWaterCompanyProfile.sql complete.';
GO

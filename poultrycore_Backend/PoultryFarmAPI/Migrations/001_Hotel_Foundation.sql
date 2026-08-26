-- =============================================================================
-- Migration 001: Hotel Management System - Foundation Schema
-- =============================================================================
-- Run order:
--   1. This file (schema) on your target DB.
--   2. 001_Hotel_Foundation_SPs.sql for the stored procedures.
--
-- Safety:
--   * All statements are idempotent (IF NOT EXISTS / COL_LENGTH checks).
--   * Additive only. No data is dropped or rewritten.
--
-- New tables:
--   * HotelProfiles        - Hotel profile (1:1 with Farms)
--   * HotelRoomTypes       - Room categories (Single, Double, Suite, etc.)
--   * HotelFloors          - Floor definitions
--   * HotelRooms           - Room inventory with status tracking
--   * HotelAmenities       - Amenity catalog
--   * HotelRoomAmenities   - Room-amenity join table
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- HotelProfiles — one per farm (company), stores hotel-specific metadata
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.HotelProfiles', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HotelProfiles (
        HotelProfileId      INT IDENTITY(1,1) PRIMARY KEY,
        FarmId               NVARCHAR(450) NOT NULL,
        HotelName            NVARCHAR(200) NOT NULL,
        Address              NVARCHAR(500) NULL,
        City                 NVARCHAR(100) NULL,
        Country              NVARCHAR(100) NULL,
        Phone                NVARCHAR(50)  NULL,
        Email                NVARCHAR(200) NULL,
        StarRating           INT           NULL,
        CheckInTime          NVARCHAR(10)  NOT NULL CONSTRAINT DF_HotelProfiles_CheckInTime DEFAULT ('14:00'),
        CheckOutTime         NVARCHAR(10)  NOT NULL CONSTRAINT DF_HotelProfiles_CheckOutTime DEFAULT ('12:00'),
        DefaultCurrency      NVARCHAR(10)  NOT NULL CONSTRAINT DF_HotelProfiles_Currency DEFAULT ('GHS'),
        TaxRate              DECIMAL(5,2)  NOT NULL CONSTRAINT DF_HotelProfiles_TaxRate DEFAULT (0),
        ServiceChargeRate    DECIMAL(5,2)  NOT NULL CONSTRAINT DF_HotelProfiles_ServiceCharge DEFAULT (0),
        TimeZone             NVARCHAR(50)  NULL,
        LogoUrl              NVARCHAR(500) NULL,
        Description          NVARCHAR(MAX) NULL,
        CreatedAt            DATETIME2     NOT NULL CONSTRAINT DF_HotelProfiles_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt            DATETIME2     NULL
    );
    CREATE UNIQUE INDEX UX_HotelProfiles_FarmId ON dbo.HotelProfiles (FarmId);
END
GO

-- ---------------------------------------------------------------------------
-- HotelRoomTypes — room categories (Single, Double, Twin, Suite, etc.)
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.HotelRoomTypes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HotelRoomTypes (
        HotelRoomTypeId     INT IDENTITY(1,1) PRIMARY KEY,
        FarmId              NVARCHAR(450) NOT NULL,
        Name                NVARCHAR(100) NOT NULL,
        Description         NVARCHAR(500) NULL,
        BaseRate            DECIMAL(12,2) NOT NULL CONSTRAINT DF_HotelRoomTypes_BaseRate DEFAULT (0),
        MaxOccupancy        INT           NOT NULL CONSTRAINT DF_HotelRoomTypes_MaxOccupancy DEFAULT (2),
        BedType             NVARCHAR(50)  NULL,
        ImageUrl            NVARCHAR(500) NULL,
        IsActive            BIT           NOT NULL CONSTRAINT DF_HotelRoomTypes_IsActive DEFAULT (1),
        SortOrder           INT           NOT NULL CONSTRAINT DF_HotelRoomTypes_SortOrder DEFAULT (0),
        CreatedAt           DATETIME2     NOT NULL CONSTRAINT DF_HotelRoomTypes_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt           DATETIME2     NULL
    );
    CREATE INDEX IX_HotelRoomTypes_FarmId ON dbo.HotelRoomTypes (FarmId);
END
GO

-- ---------------------------------------------------------------------------
-- HotelFloors — floor definitions per hotel
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.HotelFloors', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HotelFloors (
        HotelFloorId        INT IDENTITY(1,1) PRIMARY KEY,
        FarmId              NVARCHAR(450) NOT NULL,
        FloorNumber         INT           NOT NULL,
        Name                NVARCHAR(100) NOT NULL,
        IsActive            BIT           NOT NULL CONSTRAINT DF_HotelFloors_IsActive DEFAULT (1),
        SortOrder           INT           NOT NULL CONSTRAINT DF_HotelFloors_SortOrder DEFAULT (0),
        CreatedAt           DATETIME2     NOT NULL CONSTRAINT DF_HotelFloors_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt           DATETIME2     NULL
    );
    CREATE INDEX IX_HotelFloors_FarmId ON dbo.HotelFloors (FarmId);
END
GO

-- ---------------------------------------------------------------------------
-- HotelRooms — room inventory with status tracking
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.HotelRooms', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HotelRooms (
        HotelRoomId         INT IDENTITY(1,1) PRIMARY KEY,
        FarmId              NVARCHAR(450) NOT NULL,
        RoomNumber          NVARCHAR(20)  NOT NULL,
        HotelRoomTypeId     INT           NOT NULL,
        HotelFloorId        INT           NULL,
        Status              NVARCHAR(30)  NOT NULL CONSTRAINT DF_HotelRooms_Status DEFAULT ('Available'),
        Description         NVARCHAR(500) NULL,
        IsActive            BIT           NOT NULL CONSTRAINT DF_HotelRooms_IsActive DEFAULT (1),
        CreatedAt           DATETIME2     NOT NULL CONSTRAINT DF_HotelRooms_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt           DATETIME2     NULL,

        CONSTRAINT FK_HotelRooms_RoomType FOREIGN KEY (HotelRoomTypeId)
            REFERENCES dbo.HotelRoomTypes (HotelRoomTypeId),
        CONSTRAINT FK_HotelRooms_Floor FOREIGN KEY (HotelFloorId)
            REFERENCES dbo.HotelFloors (HotelFloorId),
        CONSTRAINT CK_HotelRooms_Status CHECK (Status IN ('Available', 'Occupied', 'Maintenance', 'Reserved', 'Cleaning'))
    );
    CREATE INDEX IX_HotelRooms_FarmId ON dbo.HotelRooms (FarmId);
    CREATE UNIQUE INDEX UX_HotelRooms_Number ON dbo.HotelRooms (FarmId, RoomNumber);
END
GO

-- ---------------------------------------------------------------------------
-- HotelAmenities — amenity catalog (WiFi, AC, TV, minibar, etc.)
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.HotelAmenities', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HotelAmenities (
        HotelAmenityId      INT IDENTITY(1,1) PRIMARY KEY,
        FarmId              NVARCHAR(450) NOT NULL,
        Name                NVARCHAR(100) NOT NULL,
        Category            NVARCHAR(50)  NULL,
        Icon                NVARCHAR(50)  NULL,
        IsActive            BIT           NOT NULL CONSTRAINT DF_HotelAmenities_IsActive DEFAULT (1),
        CreatedAt           DATETIME2     NOT NULL CONSTRAINT DF_HotelAmenities_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt           DATETIME2     NULL
    );
    CREATE INDEX IX_HotelAmenities_FarmId ON dbo.HotelAmenities (FarmId);
END
GO

-- ---------------------------------------------------------------------------
-- HotelRoomAmenities — many-to-many join table
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.HotelRoomAmenities', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HotelRoomAmenities (
        HotelRoomId         INT NOT NULL,
        HotelAmenityId      INT NOT NULL,
        FarmId              NVARCHAR(450) NOT NULL,

        CONSTRAINT PK_HotelRoomAmenities PRIMARY KEY (HotelRoomId, HotelAmenityId),
        CONSTRAINT FK_HotelRoomAmenities_Room FOREIGN KEY (HotelRoomId)
            REFERENCES dbo.HotelRooms (HotelRoomId),
        CONSTRAINT FK_HotelRoomAmenities_Amenity FOREIGN KEY (HotelAmenityId)
            REFERENCES dbo.HotelAmenities (HotelAmenityId)
    );
    CREATE INDEX IX_HotelRoomAmenities_FarmId ON dbo.HotelRoomAmenities (FarmId);
END
GO

PRINT 'Migration 001_Hotel_Foundation.sql completed successfully.';
GO

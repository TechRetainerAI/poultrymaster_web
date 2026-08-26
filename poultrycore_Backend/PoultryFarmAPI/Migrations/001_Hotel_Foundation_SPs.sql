-- =============================================================================
-- Migration 001: Hotel Management System - Foundation Stored Procedures
-- =============================================================================
-- Depends on: 001_Hotel_Foundation.sql (schema)
-- All SPs are idempotent (CREATE OR ALTER).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ===========================================================================
-- HOTEL PROFILES
-- ===========================================================================

CREATE OR ALTER PROCEDURE spHotel_Profile_Get
    @FarmId NVARCHAR(450)
AS
BEGIN
    SELECT * FROM dbo.HotelProfiles WHERE FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Profile_Upsert
    @FarmId             NVARCHAR(450),
    @HotelName          NVARCHAR(200),
    @Address            NVARCHAR(500)  = NULL,
    @City               NVARCHAR(100)  = NULL,
    @Country            NVARCHAR(100)  = NULL,
    @Phone              NVARCHAR(50)   = NULL,
    @Email              NVARCHAR(200)  = NULL,
    @StarRating         INT            = NULL,
    @CheckInTime        NVARCHAR(10)   = '14:00',
    @CheckOutTime       NVARCHAR(10)   = '12:00',
    @DefaultCurrency    NVARCHAR(10)   = 'GHS',
    @TaxRate            DECIMAL(5,2)   = 0,
    @ServiceChargeRate  DECIMAL(5,2)   = 0,
    @TimeZone           NVARCHAR(50)   = NULL,
    @LogoUrl            NVARCHAR(500)  = NULL,
    @Description        NVARCHAR(MAX)  = NULL
AS
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.HotelProfiles WHERE FarmId = @FarmId)
    BEGIN
        UPDATE dbo.HotelProfiles SET
            HotelName         = @HotelName,
            Address           = @Address,
            City              = @City,
            Country           = @Country,
            Phone             = @Phone,
            Email             = @Email,
            StarRating        = @StarRating,
            CheckInTime       = @CheckInTime,
            CheckOutTime      = @CheckOutTime,
            DefaultCurrency   = @DefaultCurrency,
            TaxRate           = @TaxRate,
            ServiceChargeRate = @ServiceChargeRate,
            TimeZone          = @TimeZone,
            LogoUrl           = @LogoUrl,
            Description       = @Description,
            UpdatedAt         = SYSUTCDATETIME()
        WHERE FarmId = @FarmId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.HotelProfiles (FarmId, HotelName, Address, City, Country, Phone, Email, StarRating, CheckInTime, CheckOutTime, DefaultCurrency, TaxRate, ServiceChargeRate, TimeZone, LogoUrl, Description)
        VALUES (@FarmId, @HotelName, @Address, @City, @Country, @Phone, @Email, @StarRating, @CheckInTime, @CheckOutTime, @DefaultCurrency, @TaxRate, @ServiceChargeRate, @TimeZone, @LogoUrl, @Description);
    END

    SELECT * FROM dbo.HotelProfiles WHERE FarmId = @FarmId;
END
GO

-- ===========================================================================
-- ROOM TYPES
-- ===========================================================================

CREATE OR ALTER PROCEDURE spHotel_RoomType_List
    @FarmId NVARCHAR(450)
AS
BEGIN
    SELECT * FROM dbo.HotelRoomTypes WHERE FarmId = @FarmId ORDER BY SortOrder, Name;
END
GO

CREATE OR ALTER PROCEDURE spHotel_RoomType_Get
    @HotelRoomTypeId INT,
    @FarmId          NVARCHAR(450)
AS
BEGIN
    SELECT * FROM dbo.HotelRoomTypes WHERE HotelRoomTypeId = @HotelRoomTypeId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_RoomType_Insert
    @FarmId         NVARCHAR(450),
    @Name           NVARCHAR(100),
    @Description    NVARCHAR(500)  = NULL,
    @BaseRate       DECIMAL(12,2)  = 0,
    @MaxOccupancy   INT            = 2,
    @BedType        NVARCHAR(50)   = NULL,
    @ImageUrl       NVARCHAR(500)  = NULL,
    @IsActive       BIT            = 1,
    @SortOrder      INT            = 0
AS
BEGIN
    INSERT INTO dbo.HotelRoomTypes (FarmId, Name, Description, BaseRate, MaxOccupancy, BedType, ImageUrl, IsActive, SortOrder)
    VALUES (@FarmId, @Name, @Description, @BaseRate, @MaxOccupancy, @BedType, @ImageUrl, @IsActive, @SortOrder);

    SELECT SCOPE_IDENTITY() AS HotelRoomTypeId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_RoomType_Update
    @HotelRoomTypeId INT,
    @FarmId          NVARCHAR(450),
    @Name            NVARCHAR(100),
    @Description     NVARCHAR(500)  = NULL,
    @BaseRate        DECIMAL(12,2)  = 0,
    @MaxOccupancy    INT            = 2,
    @BedType         NVARCHAR(50)   = NULL,
    @ImageUrl        NVARCHAR(500)  = NULL,
    @IsActive        BIT            = 1,
    @SortOrder       INT            = 0
AS
BEGIN
    UPDATE dbo.HotelRoomTypes SET
        Name         = @Name,
        Description  = @Description,
        BaseRate     = @BaseRate,
        MaxOccupancy = @MaxOccupancy,
        BedType      = @BedType,
        ImageUrl     = @ImageUrl,
        IsActive     = @IsActive,
        SortOrder    = @SortOrder,
        UpdatedAt    = SYSUTCDATETIME()
    WHERE HotelRoomTypeId = @HotelRoomTypeId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_RoomType_Delete
    @HotelRoomTypeId INT,
    @FarmId          NVARCHAR(450)
AS
BEGIN
    DELETE FROM dbo.HotelRoomTypes WHERE HotelRoomTypeId = @HotelRoomTypeId AND FarmId = @FarmId;
END
GO

-- ===========================================================================
-- FLOORS
-- ===========================================================================

CREATE OR ALTER PROCEDURE spHotel_Floor_List
    @FarmId NVARCHAR(450)
AS
BEGIN
    SELECT * FROM dbo.HotelFloors WHERE FarmId = @FarmId ORDER BY SortOrder, FloorNumber;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Floor_Insert
    @FarmId      NVARCHAR(450),
    @FloorNumber INT,
    @Name        NVARCHAR(100),
    @IsActive    BIT = 1,
    @SortOrder   INT = 0
AS
BEGIN
    INSERT INTO dbo.HotelFloors (FarmId, FloorNumber, Name, IsActive, SortOrder)
    VALUES (@FarmId, @FloorNumber, @Name, @IsActive, @SortOrder);

    SELECT SCOPE_IDENTITY() AS HotelFloorId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Floor_Update
    @HotelFloorId INT,
    @FarmId       NVARCHAR(450),
    @FloorNumber  INT,
    @Name         NVARCHAR(100),
    @IsActive     BIT = 1,
    @SortOrder    INT = 0
AS
BEGIN
    UPDATE dbo.HotelFloors SET
        FloorNumber = @FloorNumber,
        Name        = @Name,
        IsActive    = @IsActive,
        SortOrder   = @SortOrder,
        UpdatedAt   = SYSUTCDATETIME()
    WHERE HotelFloorId = @HotelFloorId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Floor_Delete
    @HotelFloorId INT,
    @FarmId       NVARCHAR(450)
AS
BEGIN
    DELETE FROM dbo.HotelFloors WHERE HotelFloorId = @HotelFloorId AND FarmId = @FarmId;
END
GO

-- ===========================================================================
-- ROOMS
-- ===========================================================================

CREATE OR ALTER PROCEDURE spHotel_Room_List
    @FarmId NVARCHAR(450)
AS
BEGIN
    SELECT r.*, rt.Name AS RoomTypeName, rt.BaseRate, rt.MaxOccupancy, rt.BedType,
           f.FloorNumber, f.Name AS FloorName
    FROM dbo.HotelRooms r
    INNER JOIN dbo.HotelRoomTypes rt ON r.HotelRoomTypeId = rt.HotelRoomTypeId
    LEFT JOIN dbo.HotelFloors f ON r.HotelFloorId = f.HotelFloorId
    WHERE r.FarmId = @FarmId
    ORDER BY f.SortOrder, f.FloorNumber, r.RoomNumber;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Room_Get
    @HotelRoomId INT,
    @FarmId      NVARCHAR(450)
AS
BEGIN
    SELECT r.*, rt.Name AS RoomTypeName, rt.BaseRate, rt.MaxOccupancy, rt.BedType,
           f.FloorNumber, f.Name AS FloorName
    FROM dbo.HotelRooms r
    INNER JOIN dbo.HotelRoomTypes rt ON r.HotelRoomTypeId = rt.HotelRoomTypeId
    LEFT JOIN dbo.HotelFloors f ON r.HotelFloorId = f.HotelFloorId
    WHERE r.HotelRoomId = @HotelRoomId AND r.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Room_Insert
    @FarmId          NVARCHAR(450),
    @RoomNumber      NVARCHAR(20),
    @HotelRoomTypeId INT,
    @HotelFloorId    INT           = NULL,
    @Status          NVARCHAR(30)  = 'Available',
    @Description     NVARCHAR(500) = NULL,
    @IsActive        BIT           = 1
AS
BEGIN
    INSERT INTO dbo.HotelRooms (FarmId, RoomNumber, HotelRoomTypeId, HotelFloorId, Status, Description, IsActive)
    VALUES (@FarmId, @RoomNumber, @HotelRoomTypeId, @HotelFloorId, @Status, @Description, @IsActive);

    SELECT SCOPE_IDENTITY() AS HotelRoomId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Room_Update
    @HotelRoomId     INT,
    @FarmId          NVARCHAR(450),
    @RoomNumber      NVARCHAR(20),
    @HotelRoomTypeId INT,
    @HotelFloorId    INT           = NULL,
    @Description     NVARCHAR(500) = NULL,
    @IsActive        BIT           = 1
AS
BEGIN
    UPDATE dbo.HotelRooms SET
        RoomNumber      = @RoomNumber,
        HotelRoomTypeId = @HotelRoomTypeId,
        HotelFloorId    = @HotelFloorId,
        Description     = @Description,
        IsActive        = @IsActive,
        UpdatedAt       = SYSUTCDATETIME()
    WHERE HotelRoomId = @HotelRoomId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Room_UpdateStatus
    @HotelRoomId INT,
    @FarmId      NVARCHAR(450),
    @Status      NVARCHAR(30)
AS
BEGIN
    UPDATE dbo.HotelRooms SET
        Status    = @Status,
        UpdatedAt = SYSUTCDATETIME()
    WHERE HotelRoomId = @HotelRoomId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Room_Delete
    @HotelRoomId INT,
    @FarmId      NVARCHAR(450)
AS
BEGIN
    DELETE FROM dbo.HotelRoomAmenities WHERE HotelRoomId = @HotelRoomId AND FarmId = @FarmId;
    DELETE FROM dbo.HotelRooms WHERE HotelRoomId = @HotelRoomId AND FarmId = @FarmId;
END
GO

-- Room status summary for dashboard
CREATE OR ALTER PROCEDURE spHotel_Room_StatusSummary
    @FarmId NVARCHAR(450)
AS
BEGIN
    SELECT Status, COUNT(*) AS RoomCount
    FROM dbo.HotelRooms
    WHERE FarmId = @FarmId AND IsActive = 1
    GROUP BY Status;
END
GO

-- ===========================================================================
-- AMENITIES
-- ===========================================================================

CREATE OR ALTER PROCEDURE spHotel_Amenity_List
    @FarmId NVARCHAR(450)
AS
BEGIN
    SELECT * FROM dbo.HotelAmenities WHERE FarmId = @FarmId ORDER BY Category, Name;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Amenity_Insert
    @FarmId   NVARCHAR(450),
    @Name     NVARCHAR(100),
    @Category NVARCHAR(50)  = NULL,
    @Icon     NVARCHAR(50)  = NULL,
    @IsActive BIT           = 1
AS
BEGIN
    INSERT INTO dbo.HotelAmenities (FarmId, Name, Category, Icon, IsActive)
    VALUES (@FarmId, @Name, @Category, @Icon, @IsActive);

    SELECT SCOPE_IDENTITY() AS HotelAmenityId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Amenity_Update
    @HotelAmenityId INT,
    @FarmId         NVARCHAR(450),
    @Name           NVARCHAR(100),
    @Category       NVARCHAR(50)  = NULL,
    @Icon           NVARCHAR(50)  = NULL,
    @IsActive       BIT           = 1
AS
BEGIN
    UPDATE dbo.HotelAmenities SET
        Name      = @Name,
        Category  = @Category,
        Icon      = @Icon,
        IsActive  = @IsActive,
        UpdatedAt = SYSUTCDATETIME()
    WHERE HotelAmenityId = @HotelAmenityId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Amenity_Delete
    @HotelAmenityId INT,
    @FarmId         NVARCHAR(450)
AS
BEGIN
    DELETE FROM dbo.HotelRoomAmenities WHERE HotelAmenityId = @HotelAmenityId AND FarmId = @FarmId;
    DELETE FROM dbo.HotelAmenities WHERE HotelAmenityId = @HotelAmenityId AND FarmId = @FarmId;
END
GO

-- ===========================================================================
-- ROOM AMENITIES (join table)
-- ===========================================================================

CREATE OR ALTER PROCEDURE spHotel_RoomAmenity_ListByRoom
    @HotelRoomId INT,
    @FarmId      NVARCHAR(450)
AS
BEGIN
    SELECT ra.*, a.Name, a.Category, a.Icon
    FROM dbo.HotelRoomAmenities ra
    INNER JOIN dbo.HotelAmenities a ON ra.HotelAmenityId = a.HotelAmenityId
    WHERE ra.HotelRoomId = @HotelRoomId AND ra.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_RoomAmenity_Set
    @HotelRoomId   INT,
    @HotelAmenityId INT,
    @FarmId        NVARCHAR(450)
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.HotelRoomAmenities WHERE HotelRoomId = @HotelRoomId AND HotelAmenityId = @HotelAmenityId)
    BEGIN
        INSERT INTO dbo.HotelRoomAmenities (HotelRoomId, HotelAmenityId, FarmId)
        VALUES (@HotelRoomId, @HotelAmenityId, @FarmId);
    END
END
GO

CREATE OR ALTER PROCEDURE spHotel_RoomAmenity_Remove
    @HotelRoomId    INT,
    @HotelAmenityId INT,
    @FarmId         NVARCHAR(450)
AS
BEGIN
    DELETE FROM dbo.HotelRoomAmenities
    WHERE HotelRoomId = @HotelRoomId AND HotelAmenityId = @HotelAmenityId AND FarmId = @FarmId;
END
GO

PRINT 'Migration 001_Hotel_Foundation_SPs.sql completed successfully.';
GO

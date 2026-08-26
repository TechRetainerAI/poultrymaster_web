-- =============================================================================
-- Migration 002: Hotel Guests & Bookings Schema
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.HotelGuests', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HotelGuests (
        HotelGuestId       INT IDENTITY(1,1) PRIMARY KEY,
        FarmId             NVARCHAR(450) NOT NULL,
        FirstName          NVARCHAR(100) NOT NULL,
        LastName           NVARCHAR(100) NOT NULL,
        Email              NVARCHAR(200) NULL,
        Phone              NVARCHAR(50)  NULL,
        IdType             NVARCHAR(50)  NULL,
        IdNumber           NVARCHAR(100) NULL,
        Nationality        NVARCHAR(100) NULL,
        Address            NVARCHAR(500) NULL,
        DateOfBirth        DATE          NULL,
        Notes              NVARCHAR(MAX) NULL,
        IsVIP              BIT           NOT NULL CONSTRAINT DF_HotelGuests_IsVIP DEFAULT (0),
        TotalStays         INT           NOT NULL CONSTRAINT DF_HotelGuests_TotalStays DEFAULT (0),
        LastStayDate       DATE          NULL,
        CreatedAt          DATETIME2     NOT NULL CONSTRAINT DF_HotelGuests_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt          DATETIME2     NULL
    );
    CREATE INDEX IX_HotelGuests_FarmId ON dbo.HotelGuests (FarmId);
    CREATE INDEX IX_HotelGuests_Name ON dbo.HotelGuests (FarmId, LastName, FirstName);
END
GO

IF OBJECT_ID('dbo.HotelBookings', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HotelBookings (
        HotelBookingId     INT IDENTITY(1,1) PRIMARY KEY,
        FarmId             NVARCHAR(450) NOT NULL,
        BookingRef         NVARCHAR(30)  NOT NULL,
        HotelGuestId       INT           NOT NULL,
        HotelRoomId        INT           NULL,
        HotelRoomTypeId    INT           NOT NULL,
        CheckInDate        DATE          NOT NULL,
        CheckOutDate       DATE          NOT NULL,
        NumberOfGuests     INT           NOT NULL CONSTRAINT DF_HotelBookings_Guests DEFAULT (1),
        Adults             INT           NOT NULL CONSTRAINT DF_HotelBookings_Adults DEFAULT (1),
        Children           INT           NOT NULL CONSTRAINT DF_HotelBookings_Children DEFAULT (0),
        NightlyRate        DECIMAL(12,2) NOT NULL,
        TotalAmount        DECIMAL(12,2) NOT NULL,
        Status             NVARCHAR(30)  NOT NULL CONSTRAINT DF_HotelBookings_Status DEFAULT ('Confirmed'),
        Source             NVARCHAR(30)  NOT NULL CONSTRAINT DF_HotelBookings_Source DEFAULT ('WalkIn'),
        SpecialRequests    NVARCHAR(MAX) NULL,
        CreatedBy          NVARCHAR(450) NULL,
        CreatedAt          DATETIME2     NOT NULL CONSTRAINT DF_HotelBookings_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt          DATETIME2     NULL,

        CONSTRAINT FK_HotelBookings_Guest FOREIGN KEY (HotelGuestId) REFERENCES dbo.HotelGuests (HotelGuestId),
        CONSTRAINT FK_HotelBookings_Room FOREIGN KEY (HotelRoomId) REFERENCES dbo.HotelRooms (HotelRoomId),
        CONSTRAINT FK_HotelBookings_RoomType FOREIGN KEY (HotelRoomTypeId) REFERENCES dbo.HotelRoomTypes (HotelRoomTypeId),
        CONSTRAINT CK_HotelBookings_Status CHECK (Status IN ('Confirmed','CheckedIn','CheckedOut','Cancelled','NoShow')),
        CONSTRAINT CK_HotelBookings_Source CHECK (Source IN ('WalkIn','Phone','Online','Agent'))
    );
    CREATE UNIQUE INDEX UX_HotelBookings_Ref ON dbo.HotelBookings (FarmId, BookingRef);
    CREATE INDEX IX_HotelBookings_FarmId ON dbo.HotelBookings (FarmId);
    CREATE INDEX IX_HotelBookings_Dates ON dbo.HotelBookings (FarmId, CheckInDate, CheckOutDate);
END
GO

IF OBJECT_ID('dbo.HotelBookingGuests', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HotelBookingGuests (
        HotelBookingId     INT NOT NULL,
        HotelGuestId       INT NOT NULL,
        FarmId             NVARCHAR(450) NOT NULL,
        IsPrimary          BIT NOT NULL CONSTRAINT DF_HotelBookingGuests_Primary DEFAULT (0),

        CONSTRAINT PK_HotelBookingGuests PRIMARY KEY (HotelBookingId, HotelGuestId),
        CONSTRAINT FK_HotelBookingGuests_Booking FOREIGN KEY (HotelBookingId) REFERENCES dbo.HotelBookings (HotelBookingId),
        CONSTRAINT FK_HotelBookingGuests_Guest FOREIGN KEY (HotelGuestId) REFERENCES dbo.HotelGuests (HotelGuestId)
    );
END
GO

PRINT 'Migration 002_Hotel_Guests_Bookings.sql completed successfully.';
GO

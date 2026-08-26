-- =============================================================================
-- Migration 002: Hotel Guests & Bookings Stored Procedures
-- =============================================================================
SET NOCOUNT ON; SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;
GO

-- GUESTS
CREATE OR ALTER PROCEDURE spHotel_Guest_List @FarmId NVARCHAR(450)
AS BEGIN SELECT * FROM dbo.HotelGuests WHERE FarmId = @FarmId ORDER BY LastName, FirstName; END
GO

CREATE OR ALTER PROCEDURE spHotel_Guest_Get @HotelGuestId INT, @FarmId NVARCHAR(450)
AS BEGIN SELECT * FROM dbo.HotelGuests WHERE HotelGuestId = @HotelGuestId AND FarmId = @FarmId; END
GO

CREATE OR ALTER PROCEDURE spHotel_Guest_Search @FarmId NVARCHAR(450), @Query NVARCHAR(200)
AS BEGIN
    SELECT * FROM dbo.HotelGuests
    WHERE FarmId = @FarmId AND (FirstName LIKE '%' + @Query + '%' OR LastName LIKE '%' + @Query + '%' OR Email LIKE '%' + @Query + '%' OR Phone LIKE '%' + @Query + '%')
    ORDER BY LastName, FirstName;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Guest_Insert
    @FarmId NVARCHAR(450), @FirstName NVARCHAR(100), @LastName NVARCHAR(100),
    @Email NVARCHAR(200) = NULL, @Phone NVARCHAR(50) = NULL, @IdType NVARCHAR(50) = NULL,
    @IdNumber NVARCHAR(100) = NULL, @Nationality NVARCHAR(100) = NULL, @Address NVARCHAR(500) = NULL,
    @DateOfBirth DATE = NULL, @Notes NVARCHAR(MAX) = NULL, @IsVIP BIT = 0
AS BEGIN
    INSERT INTO dbo.HotelGuests (FarmId, FirstName, LastName, Email, Phone, IdType, IdNumber, Nationality, Address, DateOfBirth, Notes, IsVIP)
    VALUES (@FarmId, @FirstName, @LastName, @Email, @Phone, @IdType, @IdNumber, @Nationality, @Address, @DateOfBirth, @Notes, @IsVIP);
    SELECT SCOPE_IDENTITY() AS HotelGuestId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Guest_Update
    @HotelGuestId INT, @FarmId NVARCHAR(450), @FirstName NVARCHAR(100), @LastName NVARCHAR(100),
    @Email NVARCHAR(200) = NULL, @Phone NVARCHAR(50) = NULL, @IdType NVARCHAR(50) = NULL,
    @IdNumber NVARCHAR(100) = NULL, @Nationality NVARCHAR(100) = NULL, @Address NVARCHAR(500) = NULL,
    @DateOfBirth DATE = NULL, @Notes NVARCHAR(MAX) = NULL, @IsVIP BIT = 0
AS BEGIN
    UPDATE dbo.HotelGuests SET FirstName=@FirstName, LastName=@LastName, Email=@Email, Phone=@Phone,
        IdType=@IdType, IdNumber=@IdNumber, Nationality=@Nationality, Address=@Address,
        DateOfBirth=@DateOfBirth, Notes=@Notes, IsVIP=@IsVIP, UpdatedAt=SYSUTCDATETIME()
    WHERE HotelGuestId = @HotelGuestId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Guest_Delete @HotelGuestId INT, @FarmId NVARCHAR(450)
AS BEGIN DELETE FROM dbo.HotelGuests WHERE HotelGuestId = @HotelGuestId AND FarmId = @FarmId; END
GO

-- BOOKINGS
CREATE OR ALTER PROCEDURE spHotel_Booking_List @FarmId NVARCHAR(450)
AS BEGIN
    SELECT b.*, g.FirstName AS GuestFirstName, g.LastName AS GuestLastName, g.Phone AS GuestPhone,
           r.RoomNumber, rt.Name AS RoomTypeName
    FROM dbo.HotelBookings b
    INNER JOIN dbo.HotelGuests g ON b.HotelGuestId = g.HotelGuestId
    LEFT JOIN dbo.HotelRooms r ON b.HotelRoomId = r.HotelRoomId
    INNER JOIN dbo.HotelRoomTypes rt ON b.HotelRoomTypeId = rt.HotelRoomTypeId
    WHERE b.FarmId = @FarmId ORDER BY b.CheckInDate DESC;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Booking_Get @HotelBookingId INT, @FarmId NVARCHAR(450)
AS BEGIN
    SELECT b.*, g.FirstName AS GuestFirstName, g.LastName AS GuestLastName, g.Phone AS GuestPhone, g.Email AS GuestEmail,
           r.RoomNumber, rt.Name AS RoomTypeName
    FROM dbo.HotelBookings b
    INNER JOIN dbo.HotelGuests g ON b.HotelGuestId = g.HotelGuestId
    LEFT JOIN dbo.HotelRooms r ON b.HotelRoomId = r.HotelRoomId
    INNER JOIN dbo.HotelRoomTypes rt ON b.HotelRoomTypeId = rt.HotelRoomTypeId
    WHERE b.HotelBookingId = @HotelBookingId AND b.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Booking_Insert
    @FarmId NVARCHAR(450), @BookingRef NVARCHAR(30), @HotelGuestId INT, @HotelRoomId INT = NULL,
    @HotelRoomTypeId INT, @CheckInDate DATE, @CheckOutDate DATE, @NumberOfGuests INT = 1,
    @Adults INT = 1, @Children INT = 0, @NightlyRate DECIMAL(12,2), @TotalAmount DECIMAL(12,2),
    @Status NVARCHAR(30) = 'Confirmed', @Source NVARCHAR(30) = 'WalkIn',
    @SpecialRequests NVARCHAR(MAX) = NULL, @CreatedBy NVARCHAR(450) = NULL
AS BEGIN
    INSERT INTO dbo.HotelBookings (FarmId, BookingRef, HotelGuestId, HotelRoomId, HotelRoomTypeId, CheckInDate, CheckOutDate, NumberOfGuests, Adults, Children, NightlyRate, TotalAmount, Status, Source, SpecialRequests, CreatedBy)
    VALUES (@FarmId, @BookingRef, @HotelGuestId, @HotelRoomId, @HotelRoomTypeId, @CheckInDate, @CheckOutDate, @NumberOfGuests, @Adults, @Children, @NightlyRate, @TotalAmount, @Status, @Source, @SpecialRequests, @CreatedBy);
    SELECT SCOPE_IDENTITY() AS HotelBookingId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Booking_Update
    @HotelBookingId INT, @FarmId NVARCHAR(450), @HotelRoomId INT = NULL,
    @HotelRoomTypeId INT, @CheckInDate DATE, @CheckOutDate DATE, @NumberOfGuests INT = 1,
    @Adults INT = 1, @Children INT = 0, @NightlyRate DECIMAL(12,2), @TotalAmount DECIMAL(12,2),
    @Source NVARCHAR(30) = 'WalkIn', @SpecialRequests NVARCHAR(MAX) = NULL
AS BEGIN
    UPDATE dbo.HotelBookings SET HotelRoomId=@HotelRoomId, HotelRoomTypeId=@HotelRoomTypeId,
        CheckInDate=@CheckInDate, CheckOutDate=@CheckOutDate, NumberOfGuests=@NumberOfGuests,
        Adults=@Adults, Children=@Children, NightlyRate=@NightlyRate, TotalAmount=@TotalAmount,
        Source=@Source, SpecialRequests=@SpecialRequests, UpdatedAt=SYSUTCDATETIME()
    WHERE HotelBookingId = @HotelBookingId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Booking_UpdateStatus @HotelBookingId INT, @FarmId NVARCHAR(450), @Status NVARCHAR(30)
AS BEGIN
    UPDATE dbo.HotelBookings SET Status = @Status, UpdatedAt = SYSUTCDATETIME()
    WHERE HotelBookingId = @HotelBookingId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Booking_Cancel @HotelBookingId INT, @FarmId NVARCHAR(450)
AS BEGIN
    UPDATE dbo.HotelBookings SET Status = 'Cancelled', UpdatedAt = SYSUTCDATETIME()
    WHERE HotelBookingId = @HotelBookingId AND FarmId = @FarmId;
    -- Release room if assigned
    UPDATE r SET r.Status = 'Available', r.UpdatedAt = SYSUTCDATETIME()
    FROM dbo.HotelRooms r INNER JOIN dbo.HotelBookings b ON r.HotelRoomId = b.HotelRoomId
    WHERE b.HotelBookingId = @HotelBookingId AND b.FarmId = @FarmId AND r.Status = 'Reserved';
END
GO

CREATE OR ALTER PROCEDURE spHotel_Booking_TodayArrivals @FarmId NVARCHAR(450)
AS BEGIN
    SELECT b.*, g.FirstName AS GuestFirstName, g.LastName AS GuestLastName, g.Phone AS GuestPhone,
           r.RoomNumber, rt.Name AS RoomTypeName
    FROM dbo.HotelBookings b
    INNER JOIN dbo.HotelGuests g ON b.HotelGuestId = g.HotelGuestId
    LEFT JOIN dbo.HotelRooms r ON b.HotelRoomId = r.HotelRoomId
    INNER JOIN dbo.HotelRoomTypes rt ON b.HotelRoomTypeId = rt.HotelRoomTypeId
    WHERE b.FarmId = @FarmId AND b.CheckInDate = CAST(GETUTCDATE() AS DATE) AND b.Status = 'Confirmed';
END
GO

CREATE OR ALTER PROCEDURE spHotel_Booking_TodayDepartures @FarmId NVARCHAR(450)
AS BEGIN
    SELECT b.*, g.FirstName AS GuestFirstName, g.LastName AS GuestLastName, g.Phone AS GuestPhone,
           r.RoomNumber, rt.Name AS RoomTypeName
    FROM dbo.HotelBookings b
    INNER JOIN dbo.HotelGuests g ON b.HotelGuestId = g.HotelGuestId
    LEFT JOIN dbo.HotelRooms r ON b.HotelRoomId = r.HotelRoomId
    INNER JOIN dbo.HotelRoomTypes rt ON b.HotelRoomTypeId = rt.HotelRoomTypeId
    WHERE b.FarmId = @FarmId AND b.CheckOutDate = CAST(GETUTCDATE() AS DATE) AND b.Status = 'CheckedIn';
END
GO

PRINT 'Migration 002_Hotel_Guests_Bookings_SPs.sql completed successfully.';
GO

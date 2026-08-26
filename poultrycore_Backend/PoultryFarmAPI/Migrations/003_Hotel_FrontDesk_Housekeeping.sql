-- =============================================================================
-- Migration 003: Check-in/Check-out & Housekeeping
-- =============================================================================
SET NOCOUNT ON; SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.HotelCheckIns', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HotelCheckIns (
        HotelCheckInId     INT IDENTITY(1,1) PRIMARY KEY,
        FarmId             NVARCHAR(450) NOT NULL,
        HotelBookingId     INT NOT NULL,
        HotelRoomId        INT NOT NULL,
        HotelGuestId       INT NOT NULL,
        CheckInTime        DATETIME2 NOT NULL CONSTRAINT DF_HotelCheckIns_Time DEFAULT (SYSUTCDATETIME()),
        KeyCardNumber      NVARCHAR(50) NULL,
        DepositAmount      DECIMAL(12,2) NOT NULL CONSTRAINT DF_HotelCheckIns_Deposit DEFAULT (0),
        DepositMethod      NVARCHAR(30) NULL,
        Notes              NVARCHAR(MAX) NULL,
        CheckedInBy        NVARCHAR(450) NULL,
        CreatedAt          DATETIME2 NOT NULL CONSTRAINT DF_HotelCheckIns_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_HotelCheckIns_Booking FOREIGN KEY (HotelBookingId) REFERENCES dbo.HotelBookings (HotelBookingId),
        CONSTRAINT FK_HotelCheckIns_Room FOREIGN KEY (HotelRoomId) REFERENCES dbo.HotelRooms (HotelRoomId)
    );
    CREATE INDEX IX_HotelCheckIns_FarmId ON dbo.HotelCheckIns (FarmId);
END
GO

IF OBJECT_ID('dbo.HotelCheckOuts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HotelCheckOuts (
        HotelCheckOutId    INT IDENTITY(1,1) PRIMARY KEY,
        FarmId             NVARCHAR(450) NOT NULL,
        HotelBookingId     INT NOT NULL,
        HotelRoomId        INT NOT NULL,
        CheckOutTime       DATETIME2 NOT NULL CONSTRAINT DF_HotelCheckOuts_Time DEFAULT (SYSUTCDATETIME()),
        FinalBillAmount    DECIMAL(12,2) NOT NULL CONSTRAINT DF_HotelCheckOuts_Bill DEFAULT (0),
        LateFee            DECIMAL(12,2) NOT NULL CONSTRAINT DF_HotelCheckOuts_Late DEFAULT (0),
        DamageCharges      DECIMAL(12,2) NOT NULL CONSTRAINT DF_HotelCheckOuts_Damage DEFAULT (0),
        KeyReturned        BIT NOT NULL CONSTRAINT DF_HotelCheckOuts_Key DEFAULT (1),
        Notes              NVARCHAR(MAX) NULL,
        CheckedOutBy       NVARCHAR(450) NULL,
        CreatedAt          DATETIME2 NOT NULL CONSTRAINT DF_HotelCheckOuts_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_HotelCheckOuts_Booking FOREIGN KEY (HotelBookingId) REFERENCES dbo.HotelBookings (HotelBookingId),
        CONSTRAINT FK_HotelCheckOuts_Room FOREIGN KEY (HotelRoomId) REFERENCES dbo.HotelRooms (HotelRoomId)
    );
    CREATE INDEX IX_HotelCheckOuts_FarmId ON dbo.HotelCheckOuts (FarmId);
END
GO

IF OBJECT_ID('dbo.HotelHousekeepingTasks', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HotelHousekeepingTasks (
        HotelHousekeepingTaskId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId              NVARCHAR(450) NOT NULL,
        HotelRoomId         INT NOT NULL,
        TaskType            NVARCHAR(30) NOT NULL CONSTRAINT DF_HHT_Type DEFAULT ('Cleaning'),
        Priority            NVARCHAR(20) NOT NULL CONSTRAINT DF_HHT_Priority DEFAULT ('Normal'),
        Status              NVARCHAR(20) NOT NULL CONSTRAINT DF_HHT_Status DEFAULT ('Pending'),
        AssignedTo          NVARCHAR(200) NULL,
        ScheduledDate       DATE NOT NULL CONSTRAINT DF_HHT_Date DEFAULT (CAST(GETUTCDATE() AS DATE)),
        StartedAt           DATETIME2 NULL,
        CompletedAt         DATETIME2 NULL,
        InspectedBy         NVARCHAR(200) NULL,
        InspectionNotes     NVARCHAR(MAX) NULL,
        Notes               NVARCHAR(MAX) NULL,
        CreatedAt           DATETIME2 NOT NULL CONSTRAINT DF_HHT_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt           DATETIME2 NULL,
        CONSTRAINT FK_HHT_Room FOREIGN KEY (HotelRoomId) REFERENCES dbo.HotelRooms (HotelRoomId),
        CONSTRAINT CK_HHT_TaskType CHECK (TaskType IN ('Cleaning','DeepClean','Inspection','TurnDown','Laundry')),
        CONSTRAINT CK_HHT_Priority CHECK (Priority IN ('Low','Normal','High','Urgent')),
        CONSTRAINT CK_HHT_Status CHECK (Status IN ('Pending','InProgress','Completed','Inspected','Failed'))
    );
    CREATE INDEX IX_HHT_FarmId ON dbo.HotelHousekeepingTasks (FarmId);
END
GO

-- SPs for check-in (atomic: updates booking + room status)
CREATE OR ALTER PROCEDURE spHotel_CheckIn_Process
    @FarmId NVARCHAR(450), @HotelBookingId INT, @HotelRoomId INT,
    @KeyCardNumber NVARCHAR(50) = NULL, @DepositAmount DECIMAL(12,2) = 0,
    @DepositMethod NVARCHAR(30) = NULL, @Notes NVARCHAR(MAX) = NULL
AS BEGIN
    BEGIN TRANSACTION;
    DECLARE @GuestId INT; SELECT @GuestId = HotelGuestId FROM dbo.HotelBookings WHERE HotelBookingId = @HotelBookingId AND FarmId = @FarmId;
    INSERT INTO dbo.HotelCheckIns (FarmId, HotelBookingId, HotelRoomId, HotelGuestId, KeyCardNumber, DepositAmount, DepositMethod, Notes)
    VALUES (@FarmId, @HotelBookingId, @HotelRoomId, @GuestId, @KeyCardNumber, @DepositAmount, @DepositMethod, @Notes);
    UPDATE dbo.HotelBookings SET Status = 'CheckedIn', HotelRoomId = @HotelRoomId, UpdatedAt = SYSUTCDATETIME() WHERE HotelBookingId = @HotelBookingId AND FarmId = @FarmId;
    UPDATE dbo.HotelRooms SET Status = 'Occupied', UpdatedAt = SYSUTCDATETIME() WHERE HotelRoomId = @HotelRoomId AND FarmId = @FarmId;
    UPDATE dbo.HotelGuests SET TotalStays = TotalStays + 1, LastStayDate = CAST(GETUTCDATE() AS DATE), UpdatedAt = SYSUTCDATETIME() WHERE HotelGuestId = @GuestId AND FarmId = @FarmId;
    COMMIT;
    SELECT * FROM dbo.HotelCheckIns WHERE HotelBookingId = @HotelBookingId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_CheckOut_Process
    @FarmId NVARCHAR(450), @HotelBookingId INT, @HotelRoomId INT,
    @LateFee DECIMAL(12,2) = 0, @DamageCharges DECIMAL(12,2) = 0,
    @KeyReturned BIT = 1, @Notes NVARCHAR(MAX) = NULL
AS BEGIN
    BEGIN TRANSACTION;
    DECLARE @Bill DECIMAL(12,2); SELECT @Bill = TotalAmount FROM dbo.HotelBookings WHERE HotelBookingId = @HotelBookingId;
    INSERT INTO dbo.HotelCheckOuts (FarmId, HotelBookingId, HotelRoomId, FinalBillAmount, LateFee, DamageCharges, KeyReturned, Notes)
    VALUES (@FarmId, @HotelBookingId, @HotelRoomId, @Bill + @LateFee + @DamageCharges, @LateFee, @DamageCharges, @KeyReturned, @Notes);
    UPDATE dbo.HotelBookings SET Status = 'CheckedOut', UpdatedAt = SYSUTCDATETIME() WHERE HotelBookingId = @HotelBookingId AND FarmId = @FarmId;
    UPDATE dbo.HotelRooms SET Status = 'Cleaning', UpdatedAt = SYSUTCDATETIME() WHERE HotelRoomId = @HotelRoomId AND FarmId = @FarmId;
    INSERT INTO dbo.HotelHousekeepingTasks (FarmId, HotelRoomId, TaskType, Priority) VALUES (@FarmId, @HotelRoomId, 'Cleaning', 'High');
    COMMIT;
    SELECT * FROM dbo.HotelCheckOuts WHERE HotelBookingId = @HotelBookingId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Housekeeping_List @FarmId NVARCHAR(450)
AS BEGIN
    SELECT t.*, r.RoomNumber FROM dbo.HotelHousekeepingTasks t
    INNER JOIN dbo.HotelRooms r ON t.HotelRoomId = r.HotelRoomId
    WHERE t.FarmId = @FarmId ORDER BY CASE t.Priority WHEN 'Urgent' THEN 1 WHEN 'High' THEN 2 WHEN 'Normal' THEN 3 ELSE 4 END, t.ScheduledDate;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Housekeeping_Insert
    @FarmId NVARCHAR(450), @HotelRoomId INT, @TaskType NVARCHAR(30) = 'Cleaning',
    @Priority NVARCHAR(20) = 'Normal', @AssignedTo NVARCHAR(200) = NULL,
    @ScheduledDate DATE = NULL, @Notes NVARCHAR(MAX) = NULL
AS BEGIN
    INSERT INTO dbo.HotelHousekeepingTasks (FarmId, HotelRoomId, TaskType, Priority, AssignedTo, ScheduledDate, Notes)
    VALUES (@FarmId, @HotelRoomId, @TaskType, @Priority, @AssignedTo, ISNULL(@ScheduledDate, CAST(GETUTCDATE() AS DATE)), @Notes);
    SELECT SCOPE_IDENTITY() AS HotelHousekeepingTaskId;
END
GO

CREATE OR ALTER PROCEDURE spHotel_Housekeeping_UpdateStatus
    @HotelHousekeepingTaskId INT, @FarmId NVARCHAR(450), @Status NVARCHAR(20)
AS BEGIN
    UPDATE dbo.HotelHousekeepingTasks SET Status = @Status, UpdatedAt = SYSUTCDATETIME(),
        StartedAt = CASE WHEN @Status = 'InProgress' AND StartedAt IS NULL THEN SYSUTCDATETIME() ELSE StartedAt END,
        CompletedAt = CASE WHEN @Status IN ('Completed','Inspected') THEN SYSUTCDATETIME() ELSE CompletedAt END
    WHERE HotelHousekeepingTaskId = @HotelHousekeepingTaskId AND FarmId = @FarmId;
    -- If completed/inspected, set room back to Available
    IF @Status IN ('Completed','Inspected')
    BEGIN
        DECLARE @RoomId INT; SELECT @RoomId = HotelRoomId FROM dbo.HotelHousekeepingTasks WHERE HotelHousekeepingTaskId = @HotelHousekeepingTaskId;
        UPDATE dbo.HotelRooms SET Status = 'Available', UpdatedAt = SYSUTCDATETIME() WHERE HotelRoomId = @RoomId AND Status = 'Cleaning' AND FarmId = @FarmId;
    END
END
GO

PRINT 'Migration 003 completed successfully.';
GO

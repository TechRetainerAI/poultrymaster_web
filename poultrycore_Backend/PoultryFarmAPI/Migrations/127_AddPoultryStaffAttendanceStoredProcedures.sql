-- =============================================================================
-- Migration 127: Poultry Staff + Attendance stored procedures (port of mig 051).
-- Idempotent (CREATE OR ALTER). Ends with a GRANT EXECUTE loop.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- PoultryStaff
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryStaff_GetAll
    @FarmId NVARCHAR(450),
    @Role   NVARCHAR(40) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PoultryStaffId, FarmId, FirstName, LastName, PhoneNumber, Email,
           Role, SalaryType, BasePay, CommissionRate,
           IsActive, IsDeleted, Notes, CreatedAt, UpdatedAt
    FROM   dbo.PoultryStaff
    WHERE  FarmId = @FarmId AND IsDeleted = 0
       AND (@Role IS NULL OR Role = @Role)
    ORDER  BY IsActive DESC, LastName, FirstName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryStaff_GetById
    @PoultryStaffId INT,
    @FarmId         NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PoultryStaffId, FarmId, FirstName, LastName, PhoneNumber, Email,
           Role, SalaryType, BasePay, CommissionRate,
           IsActive, IsDeleted, Notes, CreatedAt, UpdatedAt
    FROM   dbo.PoultryStaff
    WHERE  PoultryStaffId = @PoultryStaffId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryStaff_Insert
    @FarmId         NVARCHAR(450),
    @FirstName      NVARCHAR(100),
    @LastName       NVARCHAR(100),
    @PhoneNumber    NVARCHAR(50)  = NULL,
    @Email          NVARCHAR(200) = NULL,
    @Role           NVARCHAR(40)  = 'Other',
    @SalaryType     NVARCHAR(20)  = 'Monthly',
    @BasePay        DECIMAL(14,2) = 0,
    @CommissionRate DECIMAL(9,4)  = NULL,
    @IsActive       BIT           = 1,
    @Notes          NVARCHAR(1000)= NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@BasePay < 0) BEGIN RAISERROR('BasePay cannot be negative.', 16, 1); RETURN; END

    INSERT INTO dbo.PoultryStaff (
        FarmId, FirstName, LastName, PhoneNumber, Email, Role, SalaryType,
        BasePay, CommissionRate, IsActive, Notes
    )
    VALUES (
        @FarmId, @FirstName, @LastName, @PhoneNumber, @Email, @Role, @SalaryType,
        @BasePay, @CommissionRate, @IsActive, @Notes
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryStaff_Update
    @PoultryStaffId INT,
    @FarmId         NVARCHAR(450),
    @FirstName      NVARCHAR(100),
    @LastName       NVARCHAR(100),
    @PhoneNumber    NVARCHAR(50)  = NULL,
    @Email          NVARCHAR(200) = NULL,
    @Role           NVARCHAR(40),
    @SalaryType     NVARCHAR(20),
    @BasePay        DECIMAL(14,2),
    @CommissionRate DECIMAL(9,4)  = NULL,
    @IsActive       BIT,
    @Notes          NVARCHAR(1000)= NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryStaff
    SET    FirstName      = @FirstName,
           LastName       = @LastName,
           PhoneNumber    = @PhoneNumber,
           Email          = @Email,
           Role           = @Role,
           SalaryType     = @SalaryType,
           BasePay        = @BasePay,
           CommissionRate = @CommissionRate,
           IsActive       = @IsActive,
           Notes          = @Notes,
           UpdatedAt      = SYSUTCDATETIME()
    WHERE  PoultryStaffId = @PoultryStaffId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryStaff_Delete
    @PoultryStaffId INT,
    @FarmId         NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    -- Always soft-delete; attendance + payroll history references this row.
    UPDATE dbo.PoultryStaff
    SET    IsDeleted = 1, IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryStaffId = @PoultryStaffId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- PoultryStaffAttendance
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryStaffAttendance_GetAll
    @FarmId         NVARCHAR(450),
    @PoultryStaffId INT  = NULL,
    @FromDate       DATE = NULL,
    @ToDate         DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.PoultryStaffAttendanceId, a.FarmId, a.PoultryStaffId,
           s.FirstName + ' ' + s.LastName AS StaffName,
           a.AttendanceDate, a.ClockIn, a.ClockOut, a.Shift, a.Status, a.Notes,
           a.CreatedBy, a.CreatedAt
    FROM   dbo.PoultryStaffAttendance a
    INNER  JOIN dbo.PoultryStaff s ON s.PoultryStaffId = a.PoultryStaffId
    WHERE  a.FarmId = @FarmId
       AND (@PoultryStaffId IS NULL OR a.PoultryStaffId = @PoultryStaffId)
       AND (@FromDate       IS NULL OR a.AttendanceDate >= @FromDate)
       AND (@ToDate         IS NULL OR a.AttendanceDate <= @ToDate)
    ORDER  BY a.AttendanceDate DESC, a.PoultryStaffAttendanceId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryStaffAttendance_Upsert
    @FarmId         NVARCHAR(450),
    @PoultryStaffId INT,
    @AttendanceDate DATE,
    @Shift          NVARCHAR(30)  = NULL,
    @ClockIn        DATETIME2     = NULL,
    @ClockOut       DATETIME2     = NULL,
    @Status         NVARCHAR(20)  = 'Present',
    @Notes          NVARCHAR(500) = NULL,
    @CreatedBy      NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Status NOT IN ('Present', 'Absent', 'Late', 'HalfDay', 'OffDay')
    BEGIN RAISERROR('Attendance Status must be Present, Absent, Late, HalfDay, or OffDay.', 16, 1); RETURN; END

    UPDATE dbo.PoultryStaffAttendance
    SET    ClockIn  = @ClockIn,
           ClockOut = @ClockOut,
           Status   = @Status,
           Notes    = @Notes
    WHERE  PoultryStaffId = @PoultryStaffId AND AttendanceDate = @AttendanceDate
       AND ISNULL(Shift, '') = ISNULL(@Shift, '');

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO dbo.PoultryStaffAttendance (
            FarmId, PoultryStaffId, AttendanceDate, ClockIn, ClockOut, Shift, Status, Notes, CreatedBy
        )
        VALUES (
            @FarmId, @PoultryStaffId, @AttendanceDate, @ClockIn, @ClockOut, @Shift, @Status, @Notes, @CreatedBy
        );
    END

    SELECT PoultryStaffAttendanceId, FarmId, PoultryStaffId, AttendanceDate, ClockIn, ClockOut,
           Shift, Status, Notes, CreatedBy, CreatedAt
    FROM   dbo.PoultryStaffAttendance
    WHERE  PoultryStaffId = @PoultryStaffId AND AttendanceDate = @AttendanceDate
       AND ISNULL(Shift, '') = ISNULL(@Shift, '');
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryStaffAttendance_Delete
    @PoultryStaffAttendanceId INT,
    @FarmId                   NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.PoultryStaffAttendance
    WHERE  PoultryStaffAttendanceId = @PoultryStaffAttendanceId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- GRANT EXECUTE to the runtime login
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    DECLARE @procName SYSNAME;
    DECLARE proc_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.procedures
        WHERE name LIKE 'spPoultryStaff%';
    OPEN proc_cursor;
    FETCH NEXT FROM proc_cursor INTO @procName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @grantSql NVARCHAR(MAX) =
            N'GRANT EXECUTE ON [dbo].' + QUOTENAME(@procName) + N' TO [Techretainer];';
        EXEC sp_executesql @grantSql;
        FETCH NEXT FROM proc_cursor INTO @procName;
    END;
    CLOSE proc_cursor;
    DEALLOCATE proc_cursor;
    PRINT '127: granted EXECUTE on spPoultryStaff* to Techretainer.';
END
GO

PRINT '127_AddPoultryStaffAttendanceStoredProcedures: complete.';
GO

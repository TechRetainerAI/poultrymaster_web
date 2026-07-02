-- =============================================================================
-- Migration 126: Poultry Staff + Attendance tables (port of Water mig 050).
-- =============================================================================
-- Staff master for the poultry payroll feature. FarmId NVARCHAR(450) (matches
-- Farms.Id). Poultry-specific roles (app-layer enum); the water vehicle/route
-- assignments are dropped as they don't apply to poultry. Idempotent.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- 1. PoultryStaff --------------------------------------------------------------
-- Role (app-layer enum): FarmManager, Supervisor, FarmHand, VaccinatorHealth,
--   FeedMillOperator, EggCollector, Salesperson, Accountant, Cleaner, Security,
--   Driver, Other.
-- SalaryType: Daily, Weekly, Monthly, Commission, Mixed.
IF OBJECT_ID('dbo.PoultryStaff', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryStaff (
        PoultryStaffId   INT IDENTITY(1,1) PRIMARY KEY,
        FarmId           NVARCHAR(450)  NOT NULL,
        FirstName        NVARCHAR(100)  NOT NULL,
        LastName         NVARCHAR(100)  NOT NULL,
        PhoneNumber      NVARCHAR(50)   NULL,
        Email            NVARCHAR(200)  NULL,
        Role             NVARCHAR(40)   NOT NULL CONSTRAINT DF_PoultryStaff_Role       DEFAULT ('Other'),
        SalaryType       NVARCHAR(20)   NOT NULL CONSTRAINT DF_PoultryStaff_SalaryType DEFAULT ('Monthly'),
        BasePay          DECIMAL(14,2)  NOT NULL CONSTRAINT DF_PoultryStaff_BasePay    DEFAULT (0),
        CommissionRate   DECIMAL(9,4)   NULL,
        IsActive         BIT            NOT NULL CONSTRAINT DF_PoultryStaff_IsActive    DEFAULT (1),
        IsDeleted        BIT            NOT NULL CONSTRAINT DF_PoultryStaff_IsDeleted   DEFAULT (0),
        Notes            NVARCHAR(1000) NULL,
        CreatedAt        DATETIME2      NOT NULL CONSTRAINT DF_PoultryStaff_CreatedAt   DEFAULT (SYSUTCDATETIME()),
        UpdatedAt        DATETIME2      NULL
    );
    CREATE INDEX IX_PoultryStaff_FarmId ON dbo.PoultryStaff (FarmId);
    CREATE INDEX IX_PoultryStaff_Role   ON dbo.PoultryStaff (FarmId, Role);
    PRINT '126: created dbo.PoultryStaff';
END
GO

-- 2. PoultryStaffAttendance (one row per staff per day per shift) --------------
-- Status (app-layer enum): Present, Absent, Late, HalfDay, OffDay.
IF OBJECT_ID('dbo.PoultryStaffAttendance', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryStaffAttendance (
        PoultryStaffAttendanceId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450)  NOT NULL,
        PoultryStaffId           INT            NOT NULL,
        AttendanceDate           DATE           NOT NULL,
        ClockIn                  DATETIME2      NULL,
        ClockOut                 DATETIME2      NULL,
        Shift                    NVARCHAR(30)   NULL,
        Status                   NVARCHAR(20)   NOT NULL CONSTRAINT DF_PoultryStaffAttendance_Status DEFAULT ('Present'),
        Notes                    NVARCHAR(500)  NULL,
        CreatedBy                NVARCHAR(450)  NULL,
        CreatedAt                DATETIME2      NOT NULL CONSTRAINT DF_PoultryStaffAttendance_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_PoultryStaffAttendance_Staff
            FOREIGN KEY (PoultryStaffId) REFERENCES dbo.PoultryStaff (PoultryStaffId),
        CONSTRAINT UQ_PoultryStaffAttendance_Staff_Date_Shift UNIQUE (PoultryStaffId, AttendanceDate, Shift)
    );
    CREATE INDEX IX_PoultryStaffAttendance_FarmId ON dbo.PoultryStaffAttendance (FarmId);
    CREATE INDEX IX_PoultryStaffAttendance_Date   ON dbo.PoultryStaffAttendance (AttendanceDate);
    CREATE INDEX IX_PoultryStaffAttendance_Staff  ON dbo.PoultryStaffAttendance (PoultryStaffId, AttendanceDate);
    PRINT '126: created dbo.PoultryStaffAttendance';
END
GO

PRINT '126_AddPoultryStaffAttendanceTables: complete.';
GO

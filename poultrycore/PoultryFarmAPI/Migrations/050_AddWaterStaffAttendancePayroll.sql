-- =============================================================================
-- Migration 050: Water Company Staff + Attendance + Payroll schema — W6
-- =============================================================================
-- Fills Water spec §8 (Staff/Attendance/Payroll). Same FarmId-scoped pattern
-- as the rest of the Water module, mirrors the structure described in the
-- spec (Role enum, SalaryType enum, commission options).
--
-- Why separate tables instead of reusing dbo.Staff (poultry): the spec calls
-- out water-company-specific roles (MachineOperator, Loader, MotorKingRider,
-- etc.) and commission rules that don't apply to poultry. Cleaner to keep
-- them isolated than to bloat the shared table with company-type CASEs.
--
-- Run order: 047 → 048 → 049 → 050 (this file) → 051 (SPs).
-- Idempotent (IF OBJECT_ID), additive only.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. WaterStaff
-- -----------------------------------------------------------------------------
-- Role (app-layer enum): MachineOperator, PackagingWorker, Loader, Driver,
--   MotorKingRider, Salesperson, FactoryManager, Accountant, Cleaner,
--   Security, Other.
-- SalaryType: Daily, Weekly, Monthly, Commission, Mixed.
-- AssignedWaterVehicleId / AssignedWaterRouteId let us pivot reports by route
-- and link driver returns to the right staff. Both are optional.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterStaff', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterStaff (
        WaterStaffId            INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450)  NOT NULL,
        FirstName               NVARCHAR(100)  NOT NULL,
        LastName                NVARCHAR(100)  NOT NULL,
        PhoneNumber             NVARCHAR(50)   NULL,
        Email                   NVARCHAR(200)  NULL,
        Role                    NVARCHAR(40)   NOT NULL CONSTRAINT DF_WaterStaff_Role        DEFAULT ('Other'),
        SalaryType              NVARCHAR(20)   NOT NULL CONSTRAINT DF_WaterStaff_SalaryType  DEFAULT ('Monthly'),
        BasePay                 DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterStaff_BasePay     DEFAULT (0),
        CommissionRate          DECIMAL(9,4)   NULL,                     -- e.g. 0.05 for 5%, or absolute GHC per bag
        AssignedWaterVehicleId  INT            NULL,                     -- FK soft (vehicle may be deactivated)
        AssignedWaterRouteId    INT            NULL,                     -- FK soft
        IsActive                BIT            NOT NULL CONSTRAINT DF_WaterStaff_IsActive    DEFAULT (1),
        IsDeleted               BIT            NOT NULL CONSTRAINT DF_WaterStaff_IsDeleted   DEFAULT (0),
        Notes                   NVARCHAR(1000) NULL,
        CreatedAt               DATETIME2      NOT NULL CONSTRAINT DF_WaterStaff_CreatedAt   DEFAULT (SYSUTCDATETIME()),
        UpdatedAt               DATETIME2      NULL
    );

    CREATE INDEX IX_WaterStaff_FarmId   ON dbo.WaterStaff (FarmId);
    CREATE INDEX IX_WaterStaff_Role     ON dbo.WaterStaff (FarmId, Role);
    CREATE INDEX IX_WaterStaff_Vehicle  ON dbo.WaterStaff (AssignedWaterVehicleId);
    CREATE INDEX IX_WaterStaff_Route    ON dbo.WaterStaff (AssignedWaterRouteId);
END
GO

-- -----------------------------------------------------------------------------
-- 2. WaterStaffAttendance (one row per staff per day per shift)
-- -----------------------------------------------------------------------------
-- Status (app-layer enum): Present, Absent, Late, HalfDay, OffDay.
-- Shift: free-form ('Morning', 'Afternoon', 'Night', 'FullDay', etc.).
-- Date column kept as DATE (not DATETIME2) so per-day uniqueness is trivial.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterStaffAttendance', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterStaffAttendance (
        WaterStaffAttendanceId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450)  NOT NULL,
        WaterStaffId            INT            NOT NULL,
        AttendanceDate          DATE           NOT NULL,
        ClockIn                 DATETIME2      NULL,
        ClockOut                DATETIME2      NULL,
        Shift                   NVARCHAR(30)   NULL,
        Status                  NVARCHAR(20)   NOT NULL CONSTRAINT DF_WaterStaffAttendance_Status DEFAULT ('Present'),
        Notes                   NVARCHAR(500)  NULL,
        CreatedBy               NVARCHAR(450)  NULL,
        CreatedAt               DATETIME2      NOT NULL CONSTRAINT DF_WaterStaffAttendance_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_WaterStaffAttendance_Staff
            FOREIGN KEY (WaterStaffId) REFERENCES dbo.WaterStaff (WaterStaffId),
        -- One row per staff per day per shift (or no-shift NULL).
        CONSTRAINT UQ_WaterStaffAttendance_Staff_Date_Shift UNIQUE (WaterStaffId, AttendanceDate, Shift)
    );

    CREATE INDEX IX_WaterStaffAttendance_FarmId ON dbo.WaterStaffAttendance (FarmId);
    CREATE INDEX IX_WaterStaffAttendance_Date   ON dbo.WaterStaffAttendance (AttendanceDate);
    CREATE INDEX IX_WaterStaffAttendance_Staff  ON dbo.WaterStaffAttendance (WaterStaffId, AttendanceDate);
END
GO

-- -----------------------------------------------------------------------------
-- 3. WaterPayrollRuns (one per pay period)
-- -----------------------------------------------------------------------------
-- Status: Draft → Approved → Paid | Cancelled.
-- Totals are denormalised cache rolled up from WaterPayrollItems on submit.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterPayrollRuns', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterPayrollRuns (
        WaterPayrollRunId       INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450)  NOT NULL,
        PeriodStart             DATE           NOT NULL,
        PeriodEnd               DATE           NOT NULL,
        PayDate                 DATE           NULL,
        TotalGrossPay           DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterPayrollRuns_Gross DEFAULT (0),
        TotalDeductions         DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterPayrollRuns_Ded   DEFAULT (0),
        TotalNetPay             DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterPayrollRuns_Net   DEFAULT (0),
        Status                  NVARCHAR(20)   NOT NULL CONSTRAINT DF_WaterPayrollRuns_Status DEFAULT ('Draft'),
        WaterCashAccountId      INT            NULL,                     -- which account paid net pay
        Notes                   NVARCHAR(1000) NULL,
        CreatedBy               NVARCHAR(450)  NULL,
        ApprovedBy              NVARCHAR(450)  NULL,
        ApprovedAt              DATETIME2      NULL,
        PaidBy                  NVARCHAR(450)  NULL,
        PaidAt                  DATETIME2      NULL,
        IsDeleted               BIT            NOT NULL CONSTRAINT DF_WaterPayrollRuns_IsDeleted DEFAULT (0),
        CreatedAt               DATETIME2      NOT NULL CONSTRAINT DF_WaterPayrollRuns_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt               DATETIME2      NULL,
        CONSTRAINT CK_WaterPayrollRuns_Period CHECK (PeriodStart <= PeriodEnd)
    );

    CREATE INDEX IX_WaterPayrollRuns_FarmId ON dbo.WaterPayrollRuns (FarmId);
    CREATE INDEX IX_WaterPayrollRuns_Period ON dbo.WaterPayrollRuns (FarmId, PeriodStart, PeriodEnd);
    CREATE INDEX IX_WaterPayrollRuns_Status ON dbo.WaterPayrollRuns (Status);
END
GO

-- -----------------------------------------------------------------------------
-- 4. WaterPayrollItems (one per staff per run)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterPayrollItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterPayrollItems (
        WaterPayrollItemId      INT IDENTITY(1,1) PRIMARY KEY,
        WaterPayrollRunId       INT            NOT NULL,
        WaterStaffId            INT            NOT NULL,
        BasicPay                DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterPayrollItems_BasicPay  DEFAULT (0),
        DailyWage               DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterPayrollItems_DailyWage DEFAULT (0),
        Commission              DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterPayrollItems_Commission DEFAULT (0),
        Bonus                   DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterPayrollItems_Bonus     DEFAULT (0),
        Deductions              DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterPayrollItems_Deduct    DEFAULT (0),
        NetPay                  AS (BasicPay + DailyWage + Commission + Bonus - Deductions) PERSISTED,
        PaymentMethod           NVARCHAR(20)   NULL,                     -- Cash | MoMo | Bank
        Notes                   NVARCHAR(500)  NULL,
        CreatedAt               DATETIME2      NOT NULL CONSTRAINT DF_WaterPayrollItems_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_WaterPayrollItems_Run   FOREIGN KEY (WaterPayrollRunId) REFERENCES dbo.WaterPayrollRuns (WaterPayrollRunId),
        CONSTRAINT FK_WaterPayrollItems_Staff FOREIGN KEY (WaterStaffId)      REFERENCES dbo.WaterStaff       (WaterStaffId),
        CONSTRAINT UQ_WaterPayrollItems_Run_Staff UNIQUE (WaterPayrollRunId, WaterStaffId)
    );

    CREATE INDEX IX_WaterPayrollItems_Run   ON dbo.WaterPayrollItems (WaterPayrollRunId);
    CREATE INDEX IX_WaterPayrollItems_Staff ON dbo.WaterPayrollItems (WaterStaffId);
END
GO

PRINT '050_AddWaterStaffAttendancePayroll.sql complete.';
GO

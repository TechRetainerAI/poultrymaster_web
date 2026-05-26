-- =============================================================================
-- Migration 055: Generic Company Staff + Attendance + Payroll schema
-- =============================================================================
-- Fills Generic spec §13 (Staff), §14 (Payroll). FarmId-scoped same as the
-- rest of the Generic module. Mirrors the Water W6 shape (migrations 050/051)
-- so the C# patterns can be copy-paste-tweaked; differences from Water:
--
--   * Role enum follows Generic spec (Owner/Manager/Accountant/Cashier/
--     Salesperson/InventoryOfficer/Cleaner/Security/Driver/ServiceProvider/
--     Other) — no Water-specific MachineOperator/MotorKingRider/etc.
--   * No AssignedWaterVehicleId/RouteId; instead an optional BranchId
--     (spec §15 — Branches module not yet built but the column lives here
--     so Staff doesn't need a future-schema migration when Branches lands).
--   * Cash debit on pay uses BalanceAfterTransaction passed in by caller
--     (Generic cash-tx convention; differs from Water where the SP
--     computes the new balance inline).
--
-- Run order: 053 → 054 → 055 (this file) → 056 (SPs).
-- Idempotent (IF OBJECT_ID), additive only.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. GenericStaff
-- -----------------------------------------------------------------------------
-- Role (app-layer enum): Owner, Manager, Accountant, Cashier, Salesperson,
--   InventoryOfficer, Cleaner, Security, Driver, ServiceProvider, Other.
-- SalaryType: Daily, Weekly, Monthly, Commission, Mixed.
-- CommissionRate: decimal — interpretation is app-layer (e.g. 0.05 = 5% of
--   sale total, or absolute GHC per unit). Keep generic.
-- BranchId is nullable forward-compat for the Branches module (spec §15).
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericStaff', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericStaff (
        GenericStaffId          INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450)  NOT NULL,
        FirstName               NVARCHAR(100)  NOT NULL,
        LastName                NVARCHAR(100)  NOT NULL,
        PhoneNumber             NVARCHAR(50)   NULL,
        Email                   NVARCHAR(200)  NULL,
        Role                    NVARCHAR(40)   NOT NULL CONSTRAINT DF_GenericStaff_Role       DEFAULT ('Other'),
        SalaryType              NVARCHAR(20)   NOT NULL CONSTRAINT DF_GenericStaff_SalaryType DEFAULT ('Monthly'),
        BasePay                 DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericStaff_BasePay    DEFAULT (0),
        CommissionRate          DECIMAL(9,4)   NULL,
        BranchId                INT            NULL,  -- forward-compat with spec §15
        IsActive                BIT            NOT NULL CONSTRAINT DF_GenericStaff_IsActive   DEFAULT (1),
        IsDeleted               BIT            NOT NULL CONSTRAINT DF_GenericStaff_IsDeleted  DEFAULT (0),
        Notes                   NVARCHAR(1000) NULL,
        CreatedAt               DATETIME2      NOT NULL CONSTRAINT DF_GenericStaff_CreatedAt  DEFAULT (SYSUTCDATETIME()),
        UpdatedAt               DATETIME2      NULL
    );

    CREATE INDEX IX_GenericStaff_FarmId   ON dbo.GenericStaff (FarmId);
    CREATE INDEX IX_GenericStaff_Role     ON dbo.GenericStaff (FarmId, Role);
    CREATE INDEX IX_GenericStaff_Branch   ON dbo.GenericStaff (BranchId);
END
GO

-- -----------------------------------------------------------------------------
-- 2. GenericStaffAttendance (one row per staff per day per shift)
-- -----------------------------------------------------------------------------
-- Status (app-layer enum): Present, Absent, Late, HalfDay, OffDay.
-- Shift: free-form ('Morning', 'Afternoon', 'Night', 'FullDay', etc.).
-- AttendanceDate is DATE (not DATETIME2) so per-day uniqueness is trivial.
-- Unique constraint includes Shift so two shifts per day are allowed.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericStaffAttendance', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericStaffAttendance (
        GenericStaffAttendanceId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450)  NOT NULL,
        GenericStaffId           INT            NOT NULL,
        AttendanceDate           DATE           NOT NULL,
        ClockIn                  DATETIME2      NULL,
        ClockOut                 DATETIME2      NULL,
        Shift                    NVARCHAR(30)   NULL,
        Status                   NVARCHAR(20)   NOT NULL CONSTRAINT DF_GenericStaffAttendance_Status DEFAULT ('Present'),
        Notes                    NVARCHAR(500)  NULL,
        CreatedBy                NVARCHAR(450)  NULL,
        CreatedAt                DATETIME2      NOT NULL CONSTRAINT DF_GenericStaffAttendance_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_GenericStaffAttendance_Staff
            FOREIGN KEY (GenericStaffId) REFERENCES dbo.GenericStaff (GenericStaffId),
        CONSTRAINT UQ_GenericStaffAttendance_Staff_Date_Shift
            UNIQUE (GenericStaffId, AttendanceDate, Shift)
    );

    CREATE INDEX IX_GenericStaffAttendance_FarmId ON dbo.GenericStaffAttendance (FarmId);
    CREATE INDEX IX_GenericStaffAttendance_Date   ON dbo.GenericStaffAttendance (AttendanceDate);
    CREATE INDEX IX_GenericStaffAttendance_Staff  ON dbo.GenericStaffAttendance (GenericStaffId, AttendanceDate);
END
GO

-- -----------------------------------------------------------------------------
-- 3. GenericPayrollRuns (one per pay period)
-- -----------------------------------------------------------------------------
-- Status: Draft → Approved → Paid | Cancelled.
-- Totals are denormalised cache rolled up from GenericPayrollItems on item
-- upsert/delete and on mark-paid.
-- GenericCashAccountId set on the run is the account that's debited when
-- MarkPaid fires.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericPayrollRuns', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericPayrollRuns (
        GenericPayrollRunId     INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450)  NOT NULL,
        PeriodStart             DATE           NOT NULL,
        PeriodEnd               DATE           NOT NULL,
        PayDate                 DATE           NULL,
        TotalGrossPay           DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPayrollRuns_Gross DEFAULT (0),
        TotalDeductions         DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPayrollRuns_Ded   DEFAULT (0),
        TotalNetPay             DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPayrollRuns_Net   DEFAULT (0),
        Status                  NVARCHAR(20)   NOT NULL CONSTRAINT DF_GenericPayrollRuns_Status DEFAULT ('Draft'),
        GenericCashAccountId    INT            NULL,
        Notes                   NVARCHAR(1000) NULL,
        CreatedBy               NVARCHAR(450)  NULL,
        ApprovedBy              NVARCHAR(450)  NULL,
        ApprovedAt              DATETIME2      NULL,
        PaidBy                  NVARCHAR(450)  NULL,
        PaidAt                  DATETIME2      NULL,
        IsDeleted               BIT            NOT NULL CONSTRAINT DF_GenericPayrollRuns_IsDeleted DEFAULT (0),
        CreatedAt               DATETIME2      NOT NULL CONSTRAINT DF_GenericPayrollRuns_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt               DATETIME2      NULL,
        CONSTRAINT CK_GenericPayrollRuns_Period CHECK (PeriodStart <= PeriodEnd)
    );

    CREATE INDEX IX_GenericPayrollRuns_FarmId ON dbo.GenericPayrollRuns (FarmId);
    CREATE INDEX IX_GenericPayrollRuns_Period ON dbo.GenericPayrollRuns (FarmId, PeriodStart, PeriodEnd);
    CREATE INDEX IX_GenericPayrollRuns_Status ON dbo.GenericPayrollRuns (Status);
END
GO

-- -----------------------------------------------------------------------------
-- 4. GenericPayrollItems (one row per staff per run)
-- -----------------------------------------------------------------------------
-- NetPay is a PERSISTED computed column so the C# upsert never has to
-- recalculate it; SUM(NetPay) over the run rolls totals safely.
-- One row per (Run, Staff) is enforced.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericPayrollItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericPayrollItems (
        GenericPayrollItemId    INT IDENTITY(1,1) PRIMARY KEY,
        GenericPayrollRunId     INT            NOT NULL,
        GenericStaffId          INT            NOT NULL,
        BasicPay                DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPayrollItems_BasicPay   DEFAULT (0),
        DailyWage               DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPayrollItems_DailyWage  DEFAULT (0),
        Commission              DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPayrollItems_Commission DEFAULT (0),
        Bonus                   DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPayrollItems_Bonus      DEFAULT (0),
        Deductions              DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPayrollItems_Deduct     DEFAULT (0),
        NetPay                  AS (BasicPay + DailyWage + Commission + Bonus - Deductions) PERSISTED,
        PaymentMethod           NVARCHAR(20)   NULL,   -- Cash | MoMo | Bank | Card
        Notes                   NVARCHAR(500)  NULL,
        CreatedAt               DATETIME2      NOT NULL CONSTRAINT DF_GenericPayrollItems_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_GenericPayrollItems_Run   FOREIGN KEY (GenericPayrollRunId) REFERENCES dbo.GenericPayrollRuns (GenericPayrollRunId),
        CONSTRAINT FK_GenericPayrollItems_Staff FOREIGN KEY (GenericStaffId)      REFERENCES dbo.GenericStaff       (GenericStaffId),
        CONSTRAINT UQ_GenericPayrollItems_Run_Staff UNIQUE (GenericPayrollRunId, GenericStaffId)
    );

    CREATE INDEX IX_GenericPayrollItems_Run   ON dbo.GenericPayrollItems (GenericPayrollRunId);
    CREATE INDEX IX_GenericPayrollItems_Staff ON dbo.GenericPayrollItems (GenericStaffId);
END
GO

PRINT '055_AddGenericStaffPayroll.sql complete.';
GO

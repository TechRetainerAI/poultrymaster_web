-- =============================================================================
-- Migration 130: Poultry Payroll tables (port of Water mig 050 + audit 080).
-- =============================================================================
-- One run per pay period; one item per staff per run (computed NetPay). Audit
-- columns for the Unapprove/Reapprove cycle are included up-front. Idempotent.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- 1. PoultryPayrollRuns --------------------------------------------------------
IF OBJECT_ID('dbo.PoultryPayrollRuns', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryPayrollRuns (
        PoultryPayrollRunId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId               NVARCHAR(450)  NOT NULL,
        PeriodStart          DATE           NOT NULL,
        PeriodEnd            DATE           NOT NULL,
        PayDate              DATE           NULL,
        TotalGrossPay        DECIMAL(14,2)  NOT NULL CONSTRAINT DF_PoultryPayrollRuns_Gross DEFAULT (0),
        TotalDeductions      DECIMAL(14,2)  NOT NULL CONSTRAINT DF_PoultryPayrollRuns_Ded   DEFAULT (0),
        TotalNetPay          DECIMAL(14,2)  NOT NULL CONSTRAINT DF_PoultryPayrollRuns_Net   DEFAULT (0),
        Status               NVARCHAR(20)   NOT NULL CONSTRAINT DF_PoultryPayrollRuns_Status DEFAULT ('Draft'),
        PoultryCashAccountId INT            NULL,
        Notes                NVARCHAR(1000) NULL,
        CreatedBy            NVARCHAR(450)  NULL,
        ApprovedBy           NVARCHAR(450)  NULL,
        ApprovedAt           DATETIME2      NULL,
        PaidBy               NVARCHAR(450)  NULL,
        PaidAt               DATETIME2      NULL,
        ReopenedBy           NVARCHAR(450)  NULL,
        ReopenedAt           DATETIME2      NULL,
        ReopenReason         NVARCHAR(500)  NULL,
        ReapprovedBy         NVARCHAR(450)  NULL,
        ReapprovedAt         DATETIME2      NULL,
        IsDeleted            BIT            NOT NULL CONSTRAINT DF_PoultryPayrollRuns_IsDeleted DEFAULT (0),
        CreatedAt            DATETIME2      NOT NULL CONSTRAINT DF_PoultryPayrollRuns_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt            DATETIME2      NULL,
        CONSTRAINT CK_PoultryPayrollRuns_Period CHECK (PeriodStart <= PeriodEnd)
    );
    CREATE INDEX IX_PoultryPayrollRuns_FarmId ON dbo.PoultryPayrollRuns (FarmId);
    CREATE INDEX IX_PoultryPayrollRuns_Period ON dbo.PoultryPayrollRuns (FarmId, PeriodStart, PeriodEnd);
    CREATE INDEX IX_PoultryPayrollRuns_Status ON dbo.PoultryPayrollRuns (Status);
    PRINT '130: created dbo.PoultryPayrollRuns';
END
GO

-- 2. PoultryPayrollItems (one per staff per run) -------------------------------
IF OBJECT_ID('dbo.PoultryPayrollItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryPayrollItems (
        PoultryPayrollItemId INT IDENTITY(1,1) PRIMARY KEY,
        PoultryPayrollRunId  INT            NOT NULL,
        PoultryStaffId       INT            NOT NULL,
        BasicPay             DECIMAL(14,2)  NOT NULL CONSTRAINT DF_PoultryPayrollItems_BasicPay  DEFAULT (0),
        DailyWage            DECIMAL(14,2)  NOT NULL CONSTRAINT DF_PoultryPayrollItems_DailyWage DEFAULT (0),
        Commission           DECIMAL(14,2)  NOT NULL CONSTRAINT DF_PoultryPayrollItems_Commission DEFAULT (0),
        Bonus                DECIMAL(14,2)  NOT NULL CONSTRAINT DF_PoultryPayrollItems_Bonus     DEFAULT (0),
        Deductions           DECIMAL(14,2)  NOT NULL CONSTRAINT DF_PoultryPayrollItems_Deduct    DEFAULT (0),
        NetPay               AS (BasicPay + DailyWage + Commission + Bonus - Deductions) PERSISTED,
        PaymentMethod        NVARCHAR(20)   NULL,
        Notes                NVARCHAR(500)  NULL,
        CreatedAt            DATETIME2      NOT NULL CONSTRAINT DF_PoultryPayrollItems_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_PoultryPayrollItems_Run   FOREIGN KEY (PoultryPayrollRunId) REFERENCES dbo.PoultryPayrollRuns (PoultryPayrollRunId),
        CONSTRAINT FK_PoultryPayrollItems_Staff FOREIGN KEY (PoultryStaffId)      REFERENCES dbo.PoultryStaff       (PoultryStaffId),
        CONSTRAINT UQ_PoultryPayrollItems_Run_Staff UNIQUE (PoultryPayrollRunId, PoultryStaffId)
    );
    CREATE INDEX IX_PoultryPayrollItems_Run   ON dbo.PoultryPayrollItems (PoultryPayrollRunId);
    CREATE INDEX IX_PoultryPayrollItems_Staff ON dbo.PoultryPayrollItems (PoultryStaffId);
    PRINT '130: created dbo.PoultryPayrollItems';
END
GO

PRINT '130_AddPoultryPayrollTables: complete.';
GO

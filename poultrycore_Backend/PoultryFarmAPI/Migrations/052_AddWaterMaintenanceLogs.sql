-- =============================================================================
-- Migration 052: Water Company maintenance logs — W7
-- =============================================================================
-- Fills Water spec §11. One table + CRUD SPs + a "due alerts" SP that joins
-- WaterMachines / WaterVehicles / WaterBoreholes on their NextMaintenanceDate
-- and surfaces what's overdue or due soon. Generator is supported as a
-- standalone asset (AssetType='Generator') with no FK — generators aren't
-- modelled as their own table yet.
--
-- Status workflow: Open → InProgress → Completed (or Cancelled).
-- When a maintenance log is Completed and RepairCost > 0 and a cash account
-- is supplied, we ALSO book a CashOut so the spend lands in the same P&L
-- as the rest of the expense module. Same transactional pattern as
-- WaterExpense_Approve.
--
-- Idempotent. Run after 051.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- Table
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterMaintenanceLogs', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterMaintenanceLogs (
        WaterMaintenanceLogId   INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450)  NOT NULL,
        AssetType               NVARCHAR(20)   NOT NULL,   -- Machine | Vehicle | Borehole | Generator | Other
        AssetId                 INT            NULL,       -- soft FK to asset table by AssetType; NULL for Generator/Other
        AssetLabel              NVARCHAR(200)  NULL,       -- free-form label for Generator/Other or denormalised cache
        IssueDate               DATETIME2      NOT NULL CONSTRAINT DF_WaterMaintenanceLogs_IssueDate DEFAULT (SYSUTCDATETIME()),
        IssueDescription        NVARCHAR(1000) NOT NULL,
        ReportedByWaterStaffId  INT            NULL,
        TechnicianName          NVARCHAR(150)  NULL,
        RepairCost              DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterMaintenanceLogs_RepairCost DEFAULT (0),
        PartsReplaced           NVARCHAR(1000) NULL,
        DowntimeHours           DECIMAL(7,2)   NULL,
        Status                  NVARCHAR(20)   NOT NULL CONSTRAINT DF_WaterMaintenanceLogs_Status DEFAULT ('Open'),
        CompletedDate           DATETIME2      NULL,
        -- Cash impact (filled when Completed via spWaterMaintenanceLog_Complete).
        WaterCashAccountId      INT            NULL,
        CashTransactionWritten  BIT            NOT NULL CONSTRAINT DF_WaterMaintenanceLogs_TxWritten DEFAULT (0),
        Notes                   NVARCHAR(1000) NULL,
        IsDeleted               BIT            NOT NULL CONSTRAINT DF_WaterMaintenanceLogs_IsDeleted DEFAULT (0),
        CreatedBy               NVARCHAR(450)  NULL,
        CreatedAt               DATETIME2      NOT NULL CONSTRAINT DF_WaterMaintenanceLogs_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt               DATETIME2      NULL
    );

    CREATE INDEX IX_WaterMaintenanceLogs_FarmId   ON dbo.WaterMaintenanceLogs (FarmId);
    CREATE INDEX IX_WaterMaintenanceLogs_Asset    ON dbo.WaterMaintenanceLogs (AssetType, AssetId);
    CREATE INDEX IX_WaterMaintenanceLogs_Status   ON dbo.WaterMaintenanceLogs (Status);
    CREATE INDEX IX_WaterMaintenanceLogs_IssueDate ON dbo.WaterMaintenanceLogs (IssueDate);
END
GO

-- =============================================================================
-- CRUD SPs
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterMaintenanceLog_GetAll
    @FarmId    NVARCHAR(450),
    @Status    NVARCHAR(20) = NULL,
    @AssetType NVARCHAR(20) = NULL,
    @FromDate  DATETIME2    = NULL,
    @ToDate    DATETIME2    = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT m.WaterMaintenanceLogId, m.FarmId, m.AssetType, m.AssetId, m.AssetLabel,
           m.IssueDate, m.IssueDescription, m.ReportedByWaterStaffId,
           m.TechnicianName, m.RepairCost, m.PartsReplaced, m.DowntimeHours,
           m.Status, m.CompletedDate,
           m.WaterCashAccountId, ca.AccountName AS CashAccountName,
           m.CashTransactionWritten,
           m.Notes, m.CreatedBy, m.CreatedAt, m.UpdatedAt
    FROM   dbo.WaterMaintenanceLogs m
    LEFT   JOIN dbo.WaterCashAccounts ca ON ca.WaterCashAccountId = m.WaterCashAccountId
    WHERE  m.FarmId = @FarmId AND m.IsDeleted = 0
       AND (@Status    IS NULL OR m.Status    = @Status)
       AND (@AssetType IS NULL OR m.AssetType = @AssetType)
       AND (@FromDate  IS NULL OR m.IssueDate >= @FromDate)
       AND (@ToDate    IS NULL OR m.IssueDate <= @ToDate)
    ORDER  BY m.IssueDate DESC, m.WaterMaintenanceLogId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterMaintenanceLog_GetById
    @WaterMaintenanceLogId INT,
    @FarmId                NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT m.WaterMaintenanceLogId, m.FarmId, m.AssetType, m.AssetId, m.AssetLabel,
           m.IssueDate, m.IssueDescription, m.ReportedByWaterStaffId,
           m.TechnicianName, m.RepairCost, m.PartsReplaced, m.DowntimeHours,
           m.Status, m.CompletedDate,
           m.WaterCashAccountId, ca.AccountName AS CashAccountName,
           m.CashTransactionWritten,
           m.Notes, m.CreatedBy, m.CreatedAt, m.UpdatedAt
    FROM   dbo.WaterMaintenanceLogs m
    LEFT   JOIN dbo.WaterCashAccounts ca ON ca.WaterCashAccountId = m.WaterCashAccountId
    WHERE  m.WaterMaintenanceLogId = @WaterMaintenanceLogId AND m.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterMaintenanceLog_Insert
    @FarmId                  NVARCHAR(450),
    @AssetType               NVARCHAR(20),
    @AssetId                 INT            = NULL,
    @AssetLabel              NVARCHAR(200)  = NULL,
    @IssueDate               DATETIME2      = NULL,
    @IssueDescription        NVARCHAR(1000),
    @ReportedByWaterStaffId  INT            = NULL,
    @TechnicianName          NVARCHAR(150)  = NULL,
    @RepairCost              DECIMAL(14,2)  = 0,
    @PartsReplaced           NVARCHAR(1000) = NULL,
    @DowntimeHours           DECIMAL(7,2)   = NULL,
    @Notes                   NVARCHAR(1000) = NULL,
    @CreatedBy               NVARCHAR(450)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AssetType NOT IN ('Machine','Vehicle','Borehole','Generator','Other')
    BEGIN RAISERROR('AssetType must be Machine, Vehicle, Borehole, Generator, or Other.', 16, 1); RETURN; END

    INSERT INTO dbo.WaterMaintenanceLogs (
        FarmId, AssetType, AssetId, AssetLabel, IssueDate, IssueDescription,
        ReportedByWaterStaffId, TechnicianName, RepairCost, PartsReplaced,
        DowntimeHours, Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @AssetType, @AssetId, @AssetLabel, ISNULL(@IssueDate, SYSUTCDATETIME()), @IssueDescription,
        @ReportedByWaterStaffId, @TechnicianName, @RepairCost, @PartsReplaced,
        @DowntimeHours, 'Open', @Notes, @CreatedBy
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

-- Update is allowed only on Open/InProgress rows; Completed rows are
-- immutable except via the Reopen SP (which is intentionally not provided here).
CREATE OR ALTER PROCEDURE dbo.spWaterMaintenanceLog_Update
    @WaterMaintenanceLogId   INT,
    @FarmId                  NVARCHAR(450),
    @AssetType               NVARCHAR(20),
    @AssetId                 INT            = NULL,
    @AssetLabel              NVARCHAR(200)  = NULL,
    @IssueDescription        NVARCHAR(1000),
    @ReportedByWaterStaffId  INT            = NULL,
    @TechnicianName          NVARCHAR(150)  = NULL,
    @RepairCost              DECIMAL(14,2),
    @PartsReplaced           NVARCHAR(1000) = NULL,
    @DowntimeHours           DECIMAL(7,2)   = NULL,
    @Status                  NVARCHAR(20),       -- Open | InProgress
    @Notes                   NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Status NOT IN ('Open', 'InProgress')
    BEGIN RAISERROR('Update only supports Status=Open or InProgress. Use Complete/Cancel SPs to finalize.', 16, 1); RETURN; END

    UPDATE dbo.WaterMaintenanceLogs
    SET    AssetType              = @AssetType,
           AssetId                = @AssetId,
           AssetLabel             = @AssetLabel,
           IssueDescription       = @IssueDescription,
           ReportedByWaterStaffId = @ReportedByWaterStaffId,
           TechnicianName         = @TechnicianName,
           RepairCost             = @RepairCost,
           PartsReplaced          = @PartsReplaced,
           DowntimeHours          = @DowntimeHours,
           Status                 = @Status,
           Notes                  = @Notes,
           UpdatedAt              = SYSUTCDATETIME()
    WHERE  WaterMaintenanceLogId = @WaterMaintenanceLogId AND FarmId = @FarmId
       AND Status IN ('Open', 'InProgress');

    IF @@ROWCOUNT = 0
    BEGIN RAISERROR('Maintenance log cannot be updated (not found or already finalized).', 16, 1); RETURN; END
END
GO

-- Complete: marks Completed, optionally writes the CashOut for repair cost.
-- Idempotent — completing an already-Completed row is a no-op (won't double-book).
CREATE OR ALTER PROCEDURE dbo.spWaterMaintenanceLog_Complete
    @WaterMaintenanceLogId INT,
    @FarmId                NVARCHAR(450),
    @CompletedBy           NVARCHAR(450) = NULL,
    @CompletedDate         DATETIME2     = NULL,
    @WaterCashAccountId    INT           = NULL    -- if provided AND RepairCost > 0, book CashOut
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @Cost DECIMAL(14,2),
            @TxWritten BIT, @Desc NVARCHAR(1000), @AssetType NVARCHAR(20), @AssetLabel NVARCHAR(200);
    SELECT @Status = Status, @Cost = RepairCost, @TxWritten = CashTransactionWritten,
           @Desc = IssueDescription, @AssetType = AssetType, @AssetLabel = AssetLabel
    FROM   dbo.WaterMaintenanceLogs
    WHERE  WaterMaintenanceLogId = @WaterMaintenanceLogId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL BEGIN RAISERROR('Maintenance log not found.', 16, 1); RETURN; END
    IF @Status = 'Completed' AND @TxWritten = 1 RETURN;   -- idempotent
    IF @Status NOT IN ('Open', 'InProgress', 'Completed')
    BEGIN RAISERROR('Maintenance log cannot be completed from status %s.', 16, 1, @Status); RETURN; END

    BEGIN TRANSACTION;

    UPDATE dbo.WaterMaintenanceLogs
    SET    Status        = 'Completed',
           CompletedDate = ISNULL(@CompletedDate, SYSUTCDATETIME()),
           WaterCashAccountId = ISNULL(@WaterCashAccountId, WaterCashAccountId),
           UpdatedAt     = SYSUTCDATETIME()
    WHERE  WaterMaintenanceLogId = @WaterMaintenanceLogId AND FarmId = @FarmId;

    -- Book the cash impact only if (a) account supplied, (b) cost > 0, (c) not already written.
    IF (@WaterCashAccountId IS NOT NULL AND @Cost > 0 AND @TxWritten = 0)
    BEGIN
        DECLARE @AllowNeg BIT, @Bal DECIMAL(14,2);
        SELECT @AllowNeg = AllowNegativeBalance, @Bal = CurrentBalance
        FROM   dbo.WaterCashAccounts WHERE WaterCashAccountId = @WaterCashAccountId;
        IF (@AllowNeg = 0 AND (@Bal - @Cost) < 0)
        BEGIN RAISERROR('Cash account would go negative; maintenance complete rejected.', 16, 1); RETURN; END

        DECLARE @TxDesc NVARCHAR(500) =
            LEFT(CONCAT('Maintenance (', @AssetType, ISNULL(' #' + CAST(@AssetLabel AS NVARCHAR(50)), ''), '): ', @Desc), 500);

        INSERT INTO dbo.WaterCashTransactions (
            FarmId, WaterCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @WaterCashAccountId, SYSUTCDATETIME(), 'CashOut',
            'Maintenance', @WaterMaintenanceLogId, -@Cost, @TxDesc,
            @CompletedBy, @CompletedBy, SYSUTCDATETIME()
        );

        UPDATE dbo.WaterCashAccounts SET CurrentBalance = CurrentBalance - @Cost, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterCashAccountId = @WaterCashAccountId;

        UPDATE dbo.WaterMaintenanceLogs SET CashTransactionWritten = 1
        WHERE  WaterMaintenanceLogId = @WaterMaintenanceLogId;
    END

    COMMIT TRANSACTION;

    SELECT WaterMaintenanceLogId, Status, CompletedDate, CashTransactionWritten
    FROM   dbo.WaterMaintenanceLogs WHERE WaterMaintenanceLogId = @WaterMaintenanceLogId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterMaintenanceLog_Delete
    @WaterMaintenanceLogId INT,
    @FarmId                NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    -- Soft only — log keeps the audit trail intact even when "deleted".
    UPDATE dbo.WaterMaintenanceLogs
    SET    IsDeleted = 1, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterMaintenanceLogId = @WaterMaintenanceLogId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- Dashboard alerts SP — what's due / overdue?
-- =============================================================================
-- Returns rows: AssetType, AssetId, AssetLabel, NextDueDate, DaysUntilDue,
-- Severity ('Overdue' | 'DueSoon' | 'Upcoming'). DueSoon is within 7 days.
-- Used by the Water dashboard's "Maintenance alerts" section.
CREATE OR ALTER PROCEDURE dbo.spWaterMaintenanceLog_DueAlerts
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);

    WITH AssetsDue AS (
        SELECT 'Machine'  AS AssetType, m.WaterMachineId  AS AssetId, m.MachineName  AS AssetLabel, m.NextMaintenanceDate AS NextDueDate
        FROM   dbo.WaterMachines  m  WHERE m.FarmId = @FarmId AND m.NextMaintenanceDate IS NOT NULL
        UNION ALL
        SELECT 'Vehicle'  AS AssetType, v.WaterVehicleId AS AssetId, v.VehicleName  AS AssetLabel,
               CAST(NULL AS DATETIME2) AS NextDueDate   -- vehicles don't track next-maint date yet; placeholder for parity
        FROM   dbo.WaterVehicles v WHERE 1 = 0
        UNION ALL
        SELECT 'Borehole' AS AssetType, b.WaterBoreholeId AS AssetId, b.BoreholeName AS AssetLabel, b.NextMaintenanceDate AS NextDueDate
        FROM   dbo.WaterBoreholes b WHERE b.FarmId = @FarmId AND b.NextMaintenanceDate IS NOT NULL
    )
    SELECT a.AssetType, a.AssetId, a.AssetLabel,
           CAST(a.NextDueDate AS DATE) AS NextDueDate,
           DATEDIFF(DAY, @Today, a.NextDueDate) AS DaysUntilDue,
           CASE
             WHEN DATEDIFF(DAY, @Today, a.NextDueDate) <  0 THEN 'Overdue'
             WHEN DATEDIFF(DAY, @Today, a.NextDueDate) <= 7 THEN 'DueSoon'
             ELSE 'Upcoming'
           END AS Severity
    FROM   AssetsDue a
    WHERE  a.NextDueDate IS NOT NULL
      AND  DATEDIFF(DAY, @Today, a.NextDueDate) <= 30   -- only the next 30-day window + any overdue
    ORDER  BY DaysUntilDue ASC;
END
GO

-- =============================================================================
-- Grants
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    DECLARE @procName SYSNAME;
    DECLARE proc_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.procedures WHERE name LIKE 'spWaterMaintenanceLog%';
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
    PRINT '052: granted EXECUTE on water maintenance log SPs to Techretainer.';
END
GO

PRINT '052_AddWaterMaintenanceLogs.sql complete.';
GO

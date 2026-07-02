-- =============================================================================
-- Migration 131: Poultry Payroll stored procedures (port of Water 051/075/080/082).
-- =============================================================================
-- Approval semantics: Draft -> Approved -> Paid; Cancel from Draft/Approved;
-- Unapprove (Approved/Paid -> Reopened); Reapprove (Reopened -> Approved).
--
-- Integration (adapted for poultry):
--   * Approve  upserts a linked row in dbo.Expense (Category 'Payroll',
--     SourceType 'Payroll', SourceId = run id) so payroll flows into the P&L /
--     Expense reports. dbo.Expense.FarmId is UNIQUEIDENTIFIER, so we convert
--     with TRY_CONVERT.
--   * MarkPaid posts ONE CashOut PoultryCashTransaction for TotalNetPay against
--     the run's PoultryCashAccountId and decrements the balance.
--   * Cancel / Unapprove reverse the cash (restore balance + remove tx) and
--     HARD delete the linked expense (the expense reports don't filter a
--     soft-delete flag, so a hard delete keeps them correct).
--
-- Idempotent (CREATE OR ALTER). Ends with a GRANT EXECUTE loop.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryPayrollRun_GetAll
    @FarmId NVARCHAR(450),
    @Status NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.PoultryPayrollRunId, r.FarmId, r.PeriodStart, r.PeriodEnd, r.PayDate,
           r.TotalGrossPay, r.TotalDeductions, r.TotalNetPay, r.Status,
           r.PoultryCashAccountId, ca.AccountName AS CashAccountName,
           r.Notes, r.CreatedBy, r.ApprovedBy, r.ApprovedAt, r.PaidBy, r.PaidAt,
           r.ReopenedBy, r.ReopenedAt, r.ReopenReason, r.ReapprovedBy, r.ReapprovedAt,
           r.CreatedAt, r.UpdatedAt
    FROM   dbo.PoultryPayrollRuns r
    LEFT   JOIN dbo.PoultryCashAccounts ca ON ca.PoultryCashAccountId = r.PoultryCashAccountId
    WHERE  r.FarmId = @FarmId AND r.IsDeleted = 0
       AND (@Status IS NULL OR r.Status = @Status)
    ORDER  BY r.PeriodStart DESC, r.PoultryPayrollRunId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryPayrollRun_GetById
    @PoultryPayrollRunId INT,
    @FarmId              NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.PoultryPayrollRunId, r.FarmId, r.PeriodStart, r.PeriodEnd, r.PayDate,
           r.TotalGrossPay, r.TotalDeductions, r.TotalNetPay, r.Status,
           r.PoultryCashAccountId, ca.AccountName AS CashAccountName,
           r.Notes, r.CreatedBy, r.ApprovedBy, r.ApprovedAt, r.PaidBy, r.PaidAt,
           r.ReopenedBy, r.ReopenedAt, r.ReopenReason, r.ReapprovedBy, r.ReapprovedAt,
           r.CreatedAt, r.UpdatedAt
    FROM   dbo.PoultryPayrollRuns r
    LEFT   JOIN dbo.PoultryCashAccounts ca ON ca.PoultryCashAccountId = r.PoultryCashAccountId
    WHERE  r.PoultryPayrollRunId = @PoultryPayrollRunId AND r.FarmId = @FarmId;

    SELECT i.PoultryPayrollItemId, i.PoultryPayrollRunId, i.PoultryStaffId,
           s.FirstName + ' ' + s.LastName AS StaffName, s.Role AS StaffRole,
           i.BasicPay, i.DailyWage, i.Commission, i.Bonus, i.Deductions, i.NetPay,
           i.PaymentMethod, i.Notes, i.CreatedAt
    FROM   dbo.PoultryPayrollItems i
    INNER  JOIN dbo.PoultryStaff s ON s.PoultryStaffId = i.PoultryStaffId
    WHERE  i.PoultryPayrollRunId = @PoultryPayrollRunId
    ORDER  BY s.LastName, s.FirstName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryPayrollRun_Insert
    @FarmId               NVARCHAR(450),
    @PeriodStart          DATE,
    @PeriodEnd            DATE,
    @PayDate              DATE          = NULL,
    @PoultryCashAccountId INT           = NULL,
    @Notes                NVARCHAR(1000)= NULL,
    @CreatedBy            NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@PeriodStart > @PeriodEnd)
    BEGIN RAISERROR('PeriodStart cannot be after PeriodEnd.', 16, 1); RETURN; END

    INSERT INTO dbo.PoultryPayrollRuns (
        FarmId, PeriodStart, PeriodEnd, PayDate, PoultryCashAccountId, Status, Notes, CreatedBy
    )
    VALUES (@FarmId, @PeriodStart, @PeriodEnd, @PayDate, @PoultryCashAccountId, 'Draft', @Notes, @CreatedBy);

    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryPayrollItem_Upsert
    @PoultryPayrollRunId INT,
    @FarmId              NVARCHAR(450),
    @PoultryStaffId      INT,
    @BasicPay            DECIMAL(14,2) = 0,
    @DailyWage           DECIMAL(14,2) = 0,
    @Commission          DECIMAL(14,2) = 0,
    @Bonus               DECIMAL(14,2) = 0,
    @Deductions          DECIMAL(14,2) = 0,
    @PaymentMethod       NVARCHAR(20)  = NULL,
    @Notes               NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RunStatus NVARCHAR(20);
    SELECT @RunStatus = Status FROM dbo.PoultryPayrollRuns
    WHERE  PoultryPayrollRunId = @PoultryPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;
    IF @RunStatus IS NULL BEGIN RAISERROR('Payroll run not found for this farm.', 16, 1); RETURN; END
    IF @RunStatus <> 'Draft' BEGIN RAISERROR('Payroll run is %s; only Draft can be modified.', 16, 1, @RunStatus); RETURN; END

    IF NOT EXISTS (SELECT 1 FROM dbo.PoultryStaff WHERE PoultryStaffId = @PoultryStaffId AND FarmId = @FarmId)
    BEGIN RAISERROR('Staff %d not found on this farm.', 16, 1, @PoultryStaffId); RETURN; END

    IF (@BasicPay < 0 OR @DailyWage < 0 OR @Commission < 0 OR @Bonus < 0 OR @Deductions < 0)
    BEGIN RAISERROR('Pay components cannot be negative.', 16, 1); RETURN; END

    IF ((@BasicPay + @DailyWage + @Commission + @Bonus - @Deductions) < 0)
    BEGIN RAISERROR('NetPay cannot be negative.', 16, 1); RETURN; END

    BEGIN TRANSACTION;

    UPDATE dbo.PoultryPayrollItems
    SET    BasicPay = @BasicPay, DailyWage = @DailyWage, Commission = @Commission,
           Bonus = @Bonus, Deductions = @Deductions,
           PaymentMethod = @PaymentMethod, Notes = @Notes
    WHERE  PoultryPayrollRunId = @PoultryPayrollRunId AND PoultryStaffId = @PoultryStaffId;

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO dbo.PoultryPayrollItems (
            PoultryPayrollRunId, PoultryStaffId, BasicPay, DailyWage, Commission, Bonus, Deductions, PaymentMethod, Notes
        )
        VALUES (
            @PoultryPayrollRunId, @PoultryStaffId, @BasicPay, @DailyWage, @Commission, @Bonus, @Deductions, @PaymentMethod, @Notes
        );
    END

    UPDATE r
    SET    TotalGrossPay   = tot.GrossPay,
           TotalDeductions = tot.Deductions,
           TotalNetPay     = tot.NetPay,
           UpdatedAt       = SYSUTCDATETIME()
    FROM   dbo.PoultryPayrollRuns r
    CROSS  APPLY (
        SELECT  ISNULL(SUM(BasicPay + DailyWage + Commission + Bonus), 0) AS GrossPay,
                ISNULL(SUM(Deductions), 0)                                 AS Deductions,
                ISNULL(SUM(NetPay), 0)                                     AS NetPay
        FROM    dbo.PoultryPayrollItems
        WHERE   PoultryPayrollRunId = @PoultryPayrollRunId
    ) tot
    WHERE  r.PoultryPayrollRunId = @PoultryPayrollRunId;

    COMMIT TRANSACTION;

    SELECT PoultryPayrollItemId, PoultryPayrollRunId, PoultryStaffId,
           BasicPay, DailyWage, Commission, Bonus, Deductions, NetPay,
           PaymentMethod, Notes, CreatedAt
    FROM   dbo.PoultryPayrollItems
    WHERE  PoultryPayrollRunId = @PoultryPayrollRunId AND PoultryStaffId = @PoultryStaffId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryPayrollItem_Delete
    @PoultryPayrollItemId INT,
    @FarmId               NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RunId INT, @RunStatus NVARCHAR(20);
    SELECT @RunId = i.PoultryPayrollRunId, @RunStatus = r.Status
    FROM   dbo.PoultryPayrollItems i
    INNER  JOIN dbo.PoultryPayrollRuns r ON r.PoultryPayrollRunId = i.PoultryPayrollRunId
    WHERE  i.PoultryPayrollItemId = @PoultryPayrollItemId AND r.FarmId = @FarmId;

    IF @RunId IS NULL BEGIN RAISERROR('Payroll item not found on this farm.', 16, 1); RETURN; END
    IF @RunStatus <> 'Draft' BEGIN RAISERROR('Payroll run is %s; only Draft can be modified.', 16, 1, @RunStatus); RETURN; END

    BEGIN TRANSACTION;

    DELETE FROM dbo.PoultryPayrollItems WHERE PoultryPayrollItemId = @PoultryPayrollItemId;

    UPDATE r
    SET    TotalGrossPay   = tot.GrossPay,
           TotalDeductions = tot.Deductions,
           TotalNetPay     = tot.NetPay,
           UpdatedAt       = SYSUTCDATETIME()
    FROM   dbo.PoultryPayrollRuns r
    CROSS  APPLY (
        SELECT  ISNULL(SUM(BasicPay + DailyWage + Commission + Bonus), 0) AS GrossPay,
                ISNULL(SUM(Deductions), 0)                                 AS Deductions,
                ISNULL(SUM(NetPay), 0)                                     AS NetPay
        FROM    dbo.PoultryPayrollItems
        WHERE   PoultryPayrollRunId = @RunId
    ) tot
    WHERE  r.PoultryPayrollRunId = @RunId;

    COMMIT TRANSACTION;
END
GO

-- Approve (Draft or Reopened -> Approved) + upsert linked dbo.Expense.
CREATE OR ALTER PROCEDURE dbo.spPoultryPayrollRun_Approve
    @PoultryPayrollRunId INT,
    @FarmId              NVARCHAR(450),
    @ApprovedBy          NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @PeriodStart DATE, @PeriodEnd DATE, @PayDate DATE, @Net DECIMAL(14,2);
    SELECT @Status = Status, @PeriodStart = PeriodStart, @PeriodEnd = PeriodEnd,
           @PayDate = PayDate, @Net = TotalNetPay
    FROM   dbo.PoultryPayrollRuns
    WHERE  PoultryPayrollRunId = @PoultryPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL BEGIN RAISERROR('Payroll run not found for this farm.', 16, 1); RETURN; END
    IF @Status NOT IN ('Draft', 'Reopened')
    BEGIN RAISERROR('Payroll run is %s; only Draft or Reopened can be approved.', 16, 1, @Status); RETURN; END

    DECLARE @FarmGuid UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, @FarmId);
    DECLARE @ExpDate  DATE = ISNULL(@PayDate, CAST(SYSUTCDATETIME() AS DATE));
    DECLARE @Desc NVARCHAR(500) = CONCAT(N'Payroll ',
        CONVERT(varchar(10), @PeriodStart, 120), N' to ', CONVERT(varchar(10), @PeriodEnd, 120));

    BEGIN TRANSACTION;

    IF @Status = 'Reopened'
        UPDATE dbo.PoultryPayrollRuns
        SET    Status = 'Approved', ReapprovedBy = @ApprovedBy, ReapprovedAt = SYSUTCDATETIME(),
               UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryPayrollRunId = @PoultryPayrollRunId AND FarmId = @FarmId;
    ELSE
        UPDATE dbo.PoultryPayrollRuns
        SET    Status = 'Approved', ApprovedBy = @ApprovedBy, ApprovedAt = SYSUTCDATETIME(),
               UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryPayrollRunId = @PoultryPayrollRunId AND FarmId = @FarmId;

    -- Upsert the linked expense (matched by SourceType/SourceId).
    IF EXISTS (SELECT 1 FROM dbo.Expense WHERE SourceType = 'Payroll' AND SourceId = @PoultryPayrollRunId)
        UPDATE dbo.Expense
        SET    Amount = @Net, ExpenseDate = @ExpDate, Description = @Desc, Category = 'Payroll'
        WHERE  SourceType = 'Payroll' AND SourceId = @PoultryPayrollRunId AND FarmId = @FarmGuid;
    ELSE
        INSERT INTO dbo.Expense (ExpenseDate, Category, Description, Amount, PaymentMethod, FlockId, UserId, FarmId, SourceType, SourceId)
        VALUES (@ExpDate, 'Payroll', @Desc, @Net, 'Cash', NULL, ISNULL(@ApprovedBy, ''), @FarmGuid, 'Payroll', @PoultryPayrollRunId);

    COMMIT TRANSACTION;
END
GO

-- MarkPaid (Approved -> Paid) + one CashOut against the run's cash account.
CREATE OR ALTER PROCEDURE dbo.spPoultryPayrollRun_MarkPaid
    @PoultryPayrollRunId INT,
    @FarmId              NVARCHAR(450),
    @PaidBy              NVARCHAR(450) = NULL,
    @PayDate             DATE          = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @Net DECIMAL(14,2), @AcctId INT;
    SELECT @Status = Status, @Net = TotalNetPay, @AcctId = PoultryCashAccountId
    FROM   dbo.PoultryPayrollRuns
    WHERE  PoultryPayrollRunId = @PoultryPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL BEGIN RAISERROR('Payroll run not found for this farm.', 16, 1); RETURN; END
    IF @Status <> 'Approved' BEGIN RAISERROR('Payroll run is %s; only Approved can be marked paid.', 16, 1, @Status); RETURN; END

    BEGIN TRANSACTION;

    UPDATE dbo.PoultryPayrollRuns
    SET    Status = 'Paid', PaidBy = @PaidBy, PaidAt = SYSUTCDATETIME(),
           PayDate = ISNULL(@PayDate, ISNULL(PayDate, CAST(SYSUTCDATETIME() AS DATE))),
           UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryPayrollRunId = @PoultryPayrollRunId AND FarmId = @FarmId;

    IF (@AcctId IS NOT NULL AND @Net > 0)
    BEGIN
        UPDATE dbo.PoultryCashAccounts
        SET    CurrentBalance = CurrentBalance - @Net, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryCashAccountId = @AcctId AND FarmId = @FarmId;

        DECLARE @bal DECIMAL(14,2) = (SELECT CurrentBalance FROM dbo.PoultryCashAccounts WHERE PoultryCashAccountId = @AcctId);

        INSERT INTO dbo.PoultryCashTransactions
            (FarmId, PoultryCashAccountId, TransactionDate, TransactionType, SourceType, SourceId,
             Amount, BalanceAfterTransaction, Description, CreatedBy, ApprovedBy, ApprovedAt)
        VALUES
            (@FarmId, @AcctId, SYSUTCDATETIME(), 'CashOut', 'Payroll', @PoultryPayrollRunId,
             -@Net, @bal, 'Payroll net pay', @PaidBy, @PaidBy, SYSUTCDATETIME());
    END

    COMMIT TRANSACTION;
END
GO

-- Cancel (Draft/Approved -> Cancelled) + remove linked expense.
CREATE OR ALTER PROCEDURE dbo.spPoultryPayrollRun_Cancel
    @PoultryPayrollRunId INT,
    @FarmId              NVARCHAR(450),
    @CancelledBy         NVARCHAR(450) = NULL,
    @Reason              NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.PoultryPayrollRuns
    WHERE  PoultryPayrollRunId = @PoultryPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL BEGIN RAISERROR('Payroll run not found for this farm.', 16, 1); RETURN; END
    IF @Status NOT IN ('Draft', 'Approved')
    BEGIN RAISERROR('Payroll run is %s; only Draft or Approved can be cancelled.', 16, 1, @Status); RETURN; END

    DECLARE @FarmGuid UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, @FarmId);

    BEGIN TRANSACTION;

    DELETE FROM dbo.Expense WHERE SourceType = 'Payroll' AND SourceId = @PoultryPayrollRunId AND FarmId = @FarmGuid;

    UPDATE dbo.PoultryPayrollRuns
    SET    Status = 'Cancelled',
           Notes  = LTRIM(RTRIM(ISNULL(Notes, '') + CASE WHEN @Reason IS NULL THEN '' ELSE CHAR(10) + N'Cancelled: ' + @Reason END)),
           UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryPayrollRunId = @PoultryPayrollRunId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

-- Unapprove (Approved/Paid -> Reopened) + reverse cash + remove linked expense.
CREATE OR ALTER PROCEDURE dbo.spPoultryPayrollRun_Unapprove
    @PoultryPayrollRunId INT,
    @FarmId              NVARCHAR(450),
    @ReopenedBy          NVARCHAR(450) = NULL,
    @Reason              NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.PoultryPayrollRuns
    WHERE  PoultryPayrollRunId = @PoultryPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL BEGIN RAISERROR('Payroll run not found for this farm.', 16, 1); RETURN; END
    IF @Status NOT IN ('Approved', 'Paid')
    BEGIN RAISERROR('Payroll run is %s; only Approved or Paid can be reopened.', 16, 1, @Status); RETURN; END

    DECLARE @FarmGuid UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, @FarmId);

    BEGIN TRANSACTION;

    -- Reverse any payroll cash transactions for this run (restore balances).
    UPDATE a
    SET    a.CurrentBalance = a.CurrentBalance - t.Net, a.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryCashAccounts a
    INNER  JOIN (
        SELECT PoultryCashAccountId, SUM(Amount) AS Net
        FROM   dbo.PoultryCashTransactions
        WHERE  SourceType = 'Payroll' AND SourceId = @PoultryPayrollRunId AND FarmId = @FarmId
        GROUP  BY PoultryCashAccountId
    ) t ON t.PoultryCashAccountId = a.PoultryCashAccountId
    WHERE  a.FarmId = @FarmId;

    DELETE FROM dbo.PoultryCashTransactions
    WHERE  SourceType = 'Payroll' AND SourceId = @PoultryPayrollRunId AND FarmId = @FarmId;

    -- Remove the linked expense.
    DELETE FROM dbo.Expense WHERE SourceType = 'Payroll' AND SourceId = @PoultryPayrollRunId AND FarmId = @FarmGuid;

    UPDATE dbo.PoultryPayrollRuns
    SET    Status = 'Reopened', ReopenedBy = @ReopenedBy, ReopenedAt = SYSUTCDATETIME(),
           ReopenReason = @Reason, PaidBy = NULL, PaidAt = NULL, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryPayrollRunId = @PoultryPayrollRunId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

-- Hard delete a Draft / Reopened / Cancelled run (+ items + any lingering links).
CREATE OR ALTER PROCEDURE dbo.spPoultryPayrollRun_Delete
    @PoultryPayrollRunId INT,
    @FarmId              NVARCHAR(450),
    @DeletedBy           NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.PoultryPayrollRuns
    WHERE  PoultryPayrollRunId = @PoultryPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL BEGIN RAISERROR('Payroll run not found for this farm.', 16, 1); RETURN; END
    IF @Status NOT IN ('Draft', 'Reopened', 'Cancelled')
    BEGIN RAISERROR('Payroll run is %s; approve/paid runs must be reopened before deletion.', 16, 1, @Status); RETURN; END

    DECLARE @FarmGuid UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, @FarmId);

    BEGIN TRANSACTION;

    DELETE FROM dbo.Expense WHERE SourceType = 'Payroll' AND SourceId = @PoultryPayrollRunId AND FarmId = @FarmGuid;

    UPDATE a
    SET    a.CurrentBalance = a.CurrentBalance - t.Net, a.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryCashAccounts a
    INNER  JOIN (
        SELECT PoultryCashAccountId, SUM(Amount) AS Net
        FROM   dbo.PoultryCashTransactions
        WHERE  SourceType = 'Payroll' AND SourceId = @PoultryPayrollRunId AND FarmId = @FarmId
        GROUP  BY PoultryCashAccountId
    ) t ON t.PoultryCashAccountId = a.PoultryCashAccountId
    WHERE  a.FarmId = @FarmId;

    DELETE FROM dbo.PoultryCashTransactions
    WHERE  SourceType = 'Payroll' AND SourceId = @PoultryPayrollRunId AND FarmId = @FarmId;

    DELETE FROM dbo.PoultryPayrollItems WHERE PoultryPayrollRunId = @PoultryPayrollRunId;
    DELETE FROM dbo.PoultryPayrollRuns  WHERE PoultryPayrollRunId = @PoultryPayrollRunId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

-- Full details for the run details page (5 result sets: run, items, YTD totals,
-- YTD by staff, linked expense).
CREATE OR ALTER PROCEDURE dbo.spPoultryPayrollRun_GetDetailsWithYtd
    @PoultryPayrollRunId INT,
    @FarmId              NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Year INT = (SELECT YEAR(PeriodEnd) FROM dbo.PoultryPayrollRuns
                         WHERE PoultryPayrollRunId = @PoultryPayrollRunId AND FarmId = @FarmId);

    -- Set 1: run header
    SELECT r.PoultryPayrollRunId, r.FarmId, r.PeriodStart, r.PeriodEnd, r.PayDate,
           r.TotalGrossPay, r.TotalDeductions, r.TotalNetPay, r.Status,
           r.PoultryCashAccountId, ca.AccountName AS CashAccountName,
           r.Notes, r.CreatedBy, r.ApprovedBy, r.ApprovedAt, r.PaidBy, r.PaidAt,
           r.ReopenedBy, r.ReopenedAt, r.ReopenReason, r.ReapprovedBy, r.ReapprovedAt,
           r.CreatedAt, r.UpdatedAt
    FROM   dbo.PoultryPayrollRuns r
    LEFT   JOIN dbo.PoultryCashAccounts ca ON ca.PoultryCashAccountId = r.PoultryCashAccountId
    WHERE  r.PoultryPayrollRunId = @PoultryPayrollRunId AND r.FarmId = @FarmId;

    -- Set 2: items
    SELECT i.PoultryPayrollItemId, i.PoultryPayrollRunId, i.PoultryStaffId,
           s.FirstName + ' ' + s.LastName AS StaffName, s.Role AS StaffRole,
           i.BasicPay, i.DailyWage, i.Commission, i.Bonus, i.Deductions, i.NetPay,
           i.PaymentMethod, i.Notes, i.CreatedAt
    FROM   dbo.PoultryPayrollItems i
    INNER  JOIN dbo.PoultryStaff s ON s.PoultryStaffId = i.PoultryStaffId
    WHERE  i.PoultryPayrollRunId = @PoultryPayrollRunId
    ORDER  BY s.LastName, s.FirstName;

    -- Set 3: YTD totals (Paid runs in the run's year)
    SELECT
        @Year AS [Year],
        ISNULL(SUM(r.TotalGrossPay), 0)   AS YtdGrossPaid,
        ISNULL(SUM(r.TotalDeductions), 0) AS YtdDeductions,
        ISNULL(SUM(r.TotalNetPay), 0)     AS YtdNetPaid,
        COUNT(*)                          AS TotalPayrollRuns,
        ISNULL((
            SELECT COUNT(DISTINCT i2.PoultryStaffId)
            FROM   dbo.PoultryPayrollItems i2
            INNER  JOIN dbo.PoultryPayrollRuns r2 ON r2.PoultryPayrollRunId = i2.PoultryPayrollRunId
            WHERE  r2.FarmId = @FarmId AND r2.Status = 'Paid' AND r2.IsDeleted = 0 AND YEAR(r2.PeriodEnd) = @Year
        ), 0) AS TotalStaffPaid
    FROM   dbo.PoultryPayrollRuns r
    WHERE  r.FarmId = @FarmId AND r.Status = 'Paid' AND r.IsDeleted = 0 AND YEAR(r.PeriodEnd) = @Year;

    -- Set 4: per-staff YTD
    SELECT i.PoultryStaffId,
           MAX(s.FirstName + ' ' + s.LastName) AS StaffName,
           MAX(s.Role)                          AS StaffRole,
           SUM(i.BasicPay)    AS YtdBasic,
           SUM(i.DailyWage)   AS YtdDaily,
           SUM(i.Commission)  AS YtdCommission,
           SUM(i.Bonus)       AS YtdBonus,
           SUM(i.Deductions)  AS YtdDeductions,
           SUM(i.BasicPay + i.DailyWage + i.Commission + i.Bonus) AS YtdGross,
           SUM(i.NetPay)      AS YtdNet
    FROM   dbo.PoultryPayrollItems i
    INNER  JOIN dbo.PoultryPayrollRuns r ON r.PoultryPayrollRunId = i.PoultryPayrollRunId
    INNER  JOIN dbo.PoultryStaff s ON s.PoultryStaffId = i.PoultryStaffId
    WHERE  r.FarmId = @FarmId AND r.Status = 'Paid' AND r.IsDeleted = 0 AND YEAR(r.PeriodEnd) = @Year
    GROUP  BY i.PoultryStaffId
    ORDER  BY StaffName;

    -- Set 5: linked expense (0 or 1)
    SELECT TOP 1 e.ExpenseId, e.FarmId, e.ExpenseDate, e.Category, e.Description,
           e.Amount, e.PaymentMethod, e.SourceType, e.SourceId, e.CreatedDate
    FROM   dbo.Expense e
    WHERE  e.SourceType = 'Payroll' AND e.SourceId = @PoultryPayrollRunId
       AND e.FarmId = TRY_CONVERT(UNIQUEIDENTIFIER, @FarmId);
END
GO

-- =============================================================================
-- GRANT EXECUTE to the runtime login
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    DECLARE @procName SYSNAME;
    DECLARE proc_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.procedures WHERE name LIKE 'spPoultryPayroll%';
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
    PRINT '131: granted EXECUTE on spPoultryPayroll* to Techretainer.';
END
GO

PRINT '131_AddPoultryPayrollStoredProcedures: complete.';
GO

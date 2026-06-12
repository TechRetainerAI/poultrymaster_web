-- =============================================================================
-- Migration 056: Stored procedures for Generic Staff + Attendance + Payroll
-- =============================================================================
-- Pairs with 055.
--
-- Approval semantics (payroll):
--   Draft → Approved → Paid
--   Cancel allowed from Draft, Approved, or Paid (Paid cancel reverses cash).
--   MarkPaid writes ONE GenericCashTransactions row (CashOut, signed -NetPay)
--   for TotalNetPay against the run's GenericCashAccountId, and decrements
--   the account's CurrentBalance — all in one transaction. Per-item CashOuts
--   would be noisier than helpful for a small business; the audit trail
--   ties back via SourceType='Payroll' + SourceId=GenericPayrollRunId.
--
-- Cash-balance convention is different from Water: Generic cash transactions
-- need BalanceAfterTransaction passed in, so we compute it inline before
-- the insert (Bal - NetPay).
--
-- Idempotent. Run after 055.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- GenericStaff
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericStaff_GetAll
    @FarmId NVARCHAR(450),
    @Role   NVARCHAR(40) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericStaffId, FarmId, FirstName, LastName, PhoneNumber, Email,
           Role, SalaryType, BasePay, CommissionRate, BranchId,
           IsActive, IsDeleted, Notes, CreatedAt, UpdatedAt
    FROM   dbo.GenericStaff
    WHERE  FarmId = @FarmId AND IsDeleted = 0
       AND (@Role IS NULL OR Role = @Role)
    ORDER  BY IsActive DESC, LastName, FirstName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericStaff_GetById
    @GenericStaffId INT,
    @FarmId         NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericStaffId, FarmId, FirstName, LastName, PhoneNumber, Email,
           Role, SalaryType, BasePay, CommissionRate, BranchId,
           IsActive, IsDeleted, Notes, CreatedAt, UpdatedAt
    FROM   dbo.GenericStaff
    WHERE  GenericStaffId = @GenericStaffId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericStaff_Insert
    @FarmId         NVARCHAR(450),
    @FirstName      NVARCHAR(100),
    @LastName       NVARCHAR(100),
    @PhoneNumber    NVARCHAR(50)  = NULL,
    @Email          NVARCHAR(200) = NULL,
    @Role           NVARCHAR(40)  = 'Other',
    @SalaryType     NVARCHAR(20)  = 'Monthly',
    @BasePay        DECIMAL(14,2) = 0,
    @CommissionRate DECIMAL(9,4)  = NULL,
    @BranchId       INT           = NULL,
    @IsActive       BIT           = 1,
    @Notes          NVARCHAR(1000)= NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@BasePay < 0) BEGIN RAISERROR('BasePay cannot be negative.', 16, 1); RETURN; END
    IF (@CommissionRate IS NOT NULL AND @CommissionRate < 0)
    BEGIN RAISERROR('CommissionRate cannot be negative.', 16, 1); RETURN; END

    INSERT INTO dbo.GenericStaff (
        FarmId, FirstName, LastName, PhoneNumber, Email, Role, SalaryType,
        BasePay, CommissionRate, BranchId, IsActive, Notes
    )
    VALUES (
        @FarmId, @FirstName, @LastName, @PhoneNumber, @Email, @Role, @SalaryType,
        @BasePay, @CommissionRate, @BranchId, @IsActive, @Notes
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericStaff_Update
    @GenericStaffId INT,
    @FarmId         NVARCHAR(450),
    @FirstName      NVARCHAR(100),
    @LastName       NVARCHAR(100),
    @PhoneNumber    NVARCHAR(50)  = NULL,
    @Email          NVARCHAR(200) = NULL,
    @Role           NVARCHAR(40),
    @SalaryType     NVARCHAR(20),
    @BasePay        DECIMAL(14,2),
    @CommissionRate DECIMAL(9,4)  = NULL,
    @BranchId       INT           = NULL,
    @IsActive       BIT,
    @Notes          NVARCHAR(1000)= NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@BasePay < 0) BEGIN RAISERROR('BasePay cannot be negative.', 16, 1); RETURN; END

    UPDATE dbo.GenericStaff
    SET    FirstName      = @FirstName,
           LastName       = @LastName,
           PhoneNumber    = @PhoneNumber,
           Email          = @Email,
           Role           = @Role,
           SalaryType     = @SalaryType,
           BasePay        = @BasePay,
           CommissionRate = @CommissionRate,
           BranchId       = @BranchId,
           IsActive       = @IsActive,
           Notes          = @Notes,
           UpdatedAt      = SYSUTCDATETIME()
    WHERE  GenericStaffId = @GenericStaffId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericStaff_Delete
    @GenericStaffId INT,
    @FarmId         NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    -- Soft-delete only: attendance + payroll history references this row.
    UPDATE dbo.GenericStaff
    SET    IsDeleted = 1, IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericStaffId = @GenericStaffId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- GenericStaffAttendance
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericStaffAttendance_GetAll
    @FarmId         NVARCHAR(450),
    @GenericStaffId INT  = NULL,
    @FromDate       DATE = NULL,
    @ToDate         DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.GenericStaffAttendanceId, a.FarmId, a.GenericStaffId,
           s.FirstName + ' ' + s.LastName AS StaffName, s.Role AS StaffRole,
           a.AttendanceDate, a.ClockIn, a.ClockOut, a.Shift, a.Status, a.Notes,
           a.CreatedBy, a.CreatedAt
    FROM   dbo.GenericStaffAttendance a
    INNER  JOIN dbo.GenericStaff s ON s.GenericStaffId = a.GenericStaffId
    WHERE  a.FarmId = @FarmId
       AND (@GenericStaffId IS NULL OR a.GenericStaffId = @GenericStaffId)
       AND (@FromDate       IS NULL OR a.AttendanceDate >= @FromDate)
       AND (@ToDate         IS NULL OR a.AttendanceDate <= @ToDate)
    ORDER  BY a.AttendanceDate DESC, a.GenericStaffAttendanceId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericStaffAttendance_Upsert
    @FarmId         NVARCHAR(450),
    @GenericStaffId INT,
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

    -- Belongs to farm?
    IF NOT EXISTS (
        SELECT 1 FROM dbo.GenericStaff
        WHERE  GenericStaffId = @GenericStaffId AND FarmId = @FarmId AND IsDeleted = 0
    )
    BEGIN RAISERROR('Staff %d not found on this farm.', 16, 1, @GenericStaffId); RETURN; END

    UPDATE dbo.GenericStaffAttendance
    SET    ClockIn  = @ClockIn,
           ClockOut = @ClockOut,
           Status   = @Status,
           Notes    = @Notes
    WHERE  GenericStaffId = @GenericStaffId AND AttendanceDate = @AttendanceDate
       AND ISNULL(Shift, '') = ISNULL(@Shift, '');

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO dbo.GenericStaffAttendance (
            FarmId, GenericStaffId, AttendanceDate, ClockIn, ClockOut,
            Shift, Status, Notes, CreatedBy
        )
        VALUES (
            @FarmId, @GenericStaffId, @AttendanceDate, @ClockIn, @ClockOut,
            @Shift, @Status, @Notes, @CreatedBy
        );
    END

    SELECT GenericStaffAttendanceId, FarmId, GenericStaffId, AttendanceDate,
           ClockIn, ClockOut, Shift, Status, Notes, CreatedBy, CreatedAt
    FROM   dbo.GenericStaffAttendance
    WHERE  GenericStaffId = @GenericStaffId AND AttendanceDate = @AttendanceDate
       AND ISNULL(Shift, '') = ISNULL(@Shift, '');
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericStaffAttendance_Delete
    @GenericStaffAttendanceId INT,
    @FarmId                   NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.GenericStaffAttendance
    WHERE  GenericStaffAttendanceId = @GenericStaffAttendanceId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- GenericPayrollRun
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericPayrollRun_GetAll
    @FarmId NVARCHAR(450),
    @Status NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.GenericPayrollRunId, r.FarmId, r.PeriodStart, r.PeriodEnd, r.PayDate,
           r.TotalGrossPay, r.TotalDeductions, r.TotalNetPay, r.Status,
           r.GenericCashAccountId, ca.AccountName AS CashAccountName,
           r.Notes, r.CreatedBy, r.ApprovedBy, r.ApprovedAt, r.PaidBy, r.PaidAt,
           r.CreatedAt, r.UpdatedAt
    FROM   dbo.GenericPayrollRuns r
    LEFT   JOIN dbo.GenericCashAccounts ca ON ca.GenericCashAccountId = r.GenericCashAccountId
    WHERE  r.FarmId = @FarmId AND r.IsDeleted = 0
       AND (@Status IS NULL OR r.Status = @Status)
    ORDER  BY r.PeriodStart DESC, r.GenericPayrollRunId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericPayrollRun_GetById
    @GenericPayrollRunId INT,
    @FarmId              NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.GenericPayrollRunId, r.FarmId, r.PeriodStart, r.PeriodEnd, r.PayDate,
           r.TotalGrossPay, r.TotalDeductions, r.TotalNetPay, r.Status,
           r.GenericCashAccountId, ca.AccountName AS CashAccountName,
           r.Notes, r.CreatedBy, r.ApprovedBy, r.ApprovedAt, r.PaidBy, r.PaidAt,
           r.CreatedAt, r.UpdatedAt
    FROM   dbo.GenericPayrollRuns r
    LEFT   JOIN dbo.GenericCashAccounts ca ON ca.GenericCashAccountId = r.GenericCashAccountId
    WHERE  r.GenericPayrollRunId = @GenericPayrollRunId AND r.FarmId = @FarmId;

    -- Items
    SELECT i.GenericPayrollItemId, i.GenericPayrollRunId, i.GenericStaffId,
           s.FirstName + ' ' + s.LastName AS StaffName, s.Role AS StaffRole,
           i.BasicPay, i.DailyWage, i.Commission, i.Bonus, i.Deductions, i.NetPay,
           i.PaymentMethod, i.Notes, i.CreatedAt
    FROM   dbo.GenericPayrollItems i
    INNER  JOIN dbo.GenericStaff s ON s.GenericStaffId = i.GenericStaffId
    WHERE  i.GenericPayrollRunId = @GenericPayrollRunId
    ORDER  BY s.LastName, s.FirstName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericPayrollRun_Insert
    @FarmId               NVARCHAR(450),
    @PeriodStart          DATE,
    @PeriodEnd            DATE,
    @PayDate              DATE          = NULL,
    @GenericCashAccountId INT           = NULL,
    @Notes                NVARCHAR(1000)= NULL,
    @CreatedBy            NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@PeriodStart > @PeriodEnd)
    BEGIN RAISERROR('PeriodStart cannot be after PeriodEnd.', 16, 1); RETURN; END

    -- If a cash account is named, it must belong to the same farm.
    IF (@GenericCashAccountId IS NOT NULL AND
        NOT EXISTS (SELECT 1 FROM dbo.GenericCashAccounts
                    WHERE GenericCashAccountId = @GenericCashAccountId AND FarmId = @FarmId))
    BEGIN RAISERROR('GenericCashAccountId not found on this farm.', 16, 1); RETURN; END

    INSERT INTO dbo.GenericPayrollRuns (
        FarmId, PeriodStart, PeriodEnd, PayDate, GenericCashAccountId,
        Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @PeriodStart, @PeriodEnd, @PayDate, @GenericCashAccountId,
        'Draft', @Notes, @CreatedBy
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericPayrollRun_Update
    @GenericPayrollRunId  INT,
    @FarmId               NVARCHAR(450),
    @PeriodStart          DATE,
    @PeriodEnd            DATE,
    @PayDate              DATE          = NULL,
    @GenericCashAccountId INT           = NULL,
    @Notes                NVARCHAR(1000)= NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.GenericPayrollRuns
    WHERE  GenericPayrollRunId = @GenericPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;
    IF @Status IS NULL BEGIN RAISERROR('Payroll run not found.', 16, 1); RETURN; END
    IF @Status <> 'Draft' BEGIN RAISERROR('Payroll run is %s; only Draft can be edited.', 16, 1, @Status); RETURN; END
    IF (@PeriodStart > @PeriodEnd)
    BEGIN RAISERROR('PeriodStart cannot be after PeriodEnd.', 16, 1); RETURN; END

    UPDATE dbo.GenericPayrollRuns
    SET    PeriodStart          = @PeriodStart,
           PeriodEnd            = @PeriodEnd,
           PayDate              = @PayDate,
           GenericCashAccountId = @GenericCashAccountId,
           Notes                = @Notes,
           UpdatedAt            = SYSUTCDATETIME()
    WHERE  GenericPayrollRunId = @GenericPayrollRunId AND FarmId = @FarmId;
END
GO

-- Adds (or replaces) one staff member's line on a payroll run while it's
-- still Draft. NetPay is a computed column on the table so we don't pass it.
CREATE OR ALTER PROCEDURE dbo.spGenericPayrollItem_Upsert
    @GenericPayrollRunId INT,
    @FarmId              NVARCHAR(450),
    @GenericStaffId      INT,
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

    -- Both run and staff must belong to FarmId.
    DECLARE @RunStatus NVARCHAR(20);
    SELECT @RunStatus = Status FROM dbo.GenericPayrollRuns
    WHERE  GenericPayrollRunId = @GenericPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;
    IF @RunStatus IS NULL BEGIN RAISERROR('Payroll run not found for this farm.', 16, 1); RETURN; END
    IF @RunStatus <> 'Draft' BEGIN RAISERROR('Payroll run is %s; only Draft can be modified.', 16, 1, @RunStatus); RETURN; END

    IF NOT EXISTS (SELECT 1 FROM dbo.GenericStaff WHERE GenericStaffId = @GenericStaffId AND FarmId = @FarmId AND IsDeleted = 0)
    BEGIN RAISERROR('Staff %d not found on this farm.', 16, 1, @GenericStaffId); RETURN; END

    IF (@BasicPay < 0 OR @DailyWage < 0 OR @Commission < 0 OR @Bonus < 0 OR @Deductions < 0)
    BEGIN RAISERROR('Pay components cannot be negative.', 16, 1); RETURN; END

    DECLARE @ProvisionalNetPay DECIMAL(14,2) = @BasicPay + @DailyWage + @Commission + @Bonus - @Deductions;
    IF (@ProvisionalNetPay < 0)
    BEGIN RAISERROR('NetPay cannot be negative.', 16, 1); RETURN; END

    BEGIN TRANSACTION;

    UPDATE dbo.GenericPayrollItems
    SET    BasicPay = @BasicPay, DailyWage = @DailyWage, Commission = @Commission,
           Bonus = @Bonus, Deductions = @Deductions,
           PaymentMethod = @PaymentMethod, Notes = @Notes
    WHERE  GenericPayrollRunId = @GenericPayrollRunId AND GenericStaffId = @GenericStaffId;

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO dbo.GenericPayrollItems (
            GenericPayrollRunId, GenericStaffId, BasicPay, DailyWage,
            Commission, Bonus, Deductions, PaymentMethod, Notes
        )
        VALUES (
            @GenericPayrollRunId, @GenericStaffId, @BasicPay, @DailyWage,
            @Commission, @Bonus, @Deductions, @PaymentMethod, @Notes
        );
    END

    -- Roll up totals onto the run.
    UPDATE r
    SET    TotalGrossPay   = tot.GrossPay,
           TotalDeductions = tot.Deductions,
           TotalNetPay     = tot.NetPay,
           UpdatedAt       = SYSUTCDATETIME()
    FROM   dbo.GenericPayrollRuns r
    CROSS  APPLY (
        SELECT ISNULL(SUM(BasicPay + DailyWage + Commission + Bonus), 0) AS GrossPay,
               ISNULL(SUM(Deductions), 0)                                 AS Deductions,
               ISNULL(SUM(NetPay), 0)                                     AS NetPay
        FROM   dbo.GenericPayrollItems
        WHERE  GenericPayrollRunId = @GenericPayrollRunId
    ) tot
    WHERE  r.GenericPayrollRunId = @GenericPayrollRunId;

    COMMIT TRANSACTION;

    SELECT GenericPayrollItemId, GenericPayrollRunId, GenericStaffId,
           BasicPay, DailyWage, Commission, Bonus, Deductions, NetPay,
           PaymentMethod, Notes, CreatedAt
    FROM   dbo.GenericPayrollItems
    WHERE  GenericPayrollRunId = @GenericPayrollRunId AND GenericStaffId = @GenericStaffId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericPayrollItem_Delete
    @GenericPayrollItemId INT,
    @FarmId               NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RunId INT, @RunStatus NVARCHAR(20);
    SELECT @RunId = i.GenericPayrollRunId, @RunStatus = r.Status
    FROM   dbo.GenericPayrollItems i
    INNER  JOIN dbo.GenericPayrollRuns r ON r.GenericPayrollRunId = i.GenericPayrollRunId
    WHERE  i.GenericPayrollItemId = @GenericPayrollItemId AND r.FarmId = @FarmId;

    IF @RunId IS NULL BEGIN RAISERROR('Payroll item not found on this farm.', 16, 1); RETURN; END
    IF @RunStatus <> 'Draft' BEGIN RAISERROR('Payroll run is %s; only Draft can be modified.', 16, 1, @RunStatus); RETURN; END

    BEGIN TRANSACTION;

    DELETE FROM dbo.GenericPayrollItems WHERE GenericPayrollItemId = @GenericPayrollItemId;

    UPDATE r
    SET    TotalGrossPay   = tot.GrossPay,
           TotalDeductions = tot.Deductions,
           TotalNetPay     = tot.NetPay,
           UpdatedAt       = SYSUTCDATETIME()
    FROM   dbo.GenericPayrollRuns r
    CROSS  APPLY (
        SELECT ISNULL(SUM(BasicPay + DailyWage + Commission + Bonus), 0) AS GrossPay,
               ISNULL(SUM(Deductions), 0)                                 AS Deductions,
               ISNULL(SUM(NetPay), 0)                                     AS NetPay
        FROM   dbo.GenericPayrollItems
        WHERE  GenericPayrollRunId = @RunId
    ) tot
    WHERE  r.GenericPayrollRunId = @RunId;

    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericPayrollRun_Approve
    @GenericPayrollRunId INT,
    @FarmId              NVARCHAR(450),
    @ApprovedBy          NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Status NVARCHAR(20), @NetPay DECIMAL(14,2), @ItemCount INT;
    SELECT @Status = Status, @NetPay = TotalNetPay
    FROM   dbo.GenericPayrollRuns
    WHERE  GenericPayrollRunId = @GenericPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL BEGIN RAISERROR('Payroll run not found.', 16, 1); RETURN; END
    IF @Status <> 'Draft' BEGIN RAISERROR('Payroll cannot be approved (status=%s).', 16, 1, @Status); RETURN; END

    SELECT @ItemCount = COUNT(*) FROM dbo.GenericPayrollItems WHERE GenericPayrollRunId = @GenericPayrollRunId;
    IF @ItemCount = 0 BEGIN RAISERROR('Payroll run has no items; cannot approve an empty run.', 16, 1); RETURN; END

    UPDATE dbo.GenericPayrollRuns
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericPayrollRunId = @GenericPayrollRunId AND FarmId = @FarmId AND Status = 'Draft';

    SELECT GenericPayrollRunId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.GenericPayrollRuns WHERE GenericPayrollRunId = @GenericPayrollRunId AND FarmId = @FarmId;
END
GO

-- Mark paid: writes ONE CashOut for the run total. The cash account must be
-- set on the run before this is called (validation gate below).
CREATE OR ALTER PROCEDURE dbo.spGenericPayrollRun_MarkPaid
    @GenericPayrollRunId INT,
    @FarmId              NVARCHAR(450),
    @PaidBy              NVARCHAR(450) = NULL,
    @PayDate             DATE          = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @CashAccountId INT, @NetPay DECIMAL(14,2), @Notes NVARCHAR(1000);
    SELECT @Status = Status, @CashAccountId = GenericCashAccountId,
           @NetPay = TotalNetPay, @Notes = Notes
    FROM   dbo.GenericPayrollRuns
    WHERE  GenericPayrollRunId = @GenericPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL BEGIN RAISERROR('Payroll run not found.', 16, 1); RETURN; END
    IF @Status <> 'Approved' BEGIN RAISERROR('Payroll must be Approved before it can be marked Paid (current=%s).', 16, 1, @Status); RETURN; END
    IF @CashAccountId IS NULL BEGIN RAISERROR('Payroll has no GenericCashAccountId set; cannot pay.', 16, 1); RETURN; END
    IF @NetPay <= 0 BEGIN RAISERROR('Payroll TotalNetPay is zero; nothing to pay.', 16, 1); RETURN; END

    DECLARE @AllowNeg BIT, @Bal DECIMAL(14,2);
    SELECT @AllowNeg = AllowNegativeBalance, @Bal = CurrentBalance
    FROM   dbo.GenericCashAccounts
    WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;

    IF @Bal IS NULL BEGIN RAISERROR('GenericCashAccountId not found on this farm.', 16, 1); RETURN; END

    DECLARE @NewBalance DECIMAL(14,2) = @Bal - @NetPay;
    IF (@AllowNeg = 0 AND @NewBalance < 0)
    BEGIN RAISERROR('Cash account would go negative; payroll pay rejected.', 16, 1); RETURN; END

    BEGIN TRANSACTION;

    UPDATE dbo.GenericPayrollRuns
    SET    Status    = 'Paid',
           PaidBy    = @PaidBy,
           PaidAt    = SYSUTCDATETIME(),
           PayDate   = ISNULL(@PayDate, PayDate),
           UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericPayrollRunId = @GenericPayrollRunId AND FarmId = @FarmId;

    INSERT INTO dbo.GenericCashTransactions (
        FarmId, GenericCashAccountId, TransactionDate, TransactionType,
        SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
        CreatedBy, ApprovedBy, ApprovedAt
    )
    VALUES (
        @FarmId, @CashAccountId, SYSUTCDATETIME(), 'CashOut',
        'Payroll', @GenericPayrollRunId, -@NetPay, @NewBalance,
        ISNULL('Payroll: ' + LEFT(ISNULL(@Notes, ''), 200), 'Payroll'),
        @PaidBy, @PaidBy, SYSUTCDATETIME()
    );

    UPDATE dbo.GenericCashAccounts
    SET    CurrentBalance = @NewBalance, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT GenericPayrollRunId, Status, PaidBy, PaidAt, TotalNetPay
    FROM   dbo.GenericPayrollRuns WHERE GenericPayrollRunId = @GenericPayrollRunId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericPayrollRun_Cancel
    @GenericPayrollRunId INT,
    @FarmId              NVARCHAR(450),
    @CancelledBy         NVARCHAR(450) = NULL,
    @Reason              NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @CashAccountId INT, @NetPay DECIMAL(14,2);
    SELECT @Status = Status, @CashAccountId = GenericCashAccountId, @NetPay = TotalNetPay
    FROM   dbo.GenericPayrollRuns
    WHERE  GenericPayrollRunId = @GenericPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL BEGIN RAISERROR('Payroll run not found.', 16, 1); RETURN; END
    IF @Status = 'Cancelled' RETURN;

    IF @Status = 'Paid'
    BEGIN
        -- Reverse the cash impact (Adjustment +NetPay) before flipping status.
        IF (@CashAccountId IS NOT NULL AND @NetPay > 0)
        BEGIN
            DECLARE @Bal DECIMAL(14,2);
            SELECT @Bal = CurrentBalance FROM dbo.GenericCashAccounts
            WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;
            IF @Bal IS NULL BEGIN RAISERROR('Cash account not found on this farm.', 16, 1); RETURN; END
            DECLARE @NewBalance DECIMAL(14,2) = @Bal + @NetPay;

            BEGIN TRANSACTION;

            INSERT INTO dbo.GenericCashTransactions (
                FarmId, GenericCashAccountId, TransactionDate, TransactionType,
                SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
                CreatedBy, ApprovedBy, ApprovedAt
            )
            VALUES (
                @FarmId, @CashAccountId, SYSUTCDATETIME(), 'Adjustment',
                'Payroll', @GenericPayrollRunId, @NetPay, @NewBalance,
                'Payroll cancelled — reversal',
                @CancelledBy, @CancelledBy, SYSUTCDATETIME()
            );

            UPDATE dbo.GenericCashAccounts
            SET    CurrentBalance = @NewBalance, UpdatedAt = SYSUTCDATETIME()
            WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;

            UPDATE dbo.GenericPayrollRuns
            SET    Status    = 'Cancelled',
                   Notes     = CASE WHEN @Reason IS NULL THEN Notes
                                    ELSE LEFT(ISNULL(Notes,'') + CHAR(10) + 'Cancelled: ' + @Reason, 1000) END,
                   UpdatedAt = SYSUTCDATETIME()
            WHERE  GenericPayrollRunId = @GenericPayrollRunId AND FarmId = @FarmId;

            COMMIT TRANSACTION;
            RETURN;
        END
    END

    -- Draft or Approved (or Paid with no cash to reverse): just flip status.
    UPDATE dbo.GenericPayrollRuns
    SET    Status    = 'Cancelled',
           Notes     = CASE WHEN @Reason IS NULL THEN Notes
                            ELSE LEFT(ISNULL(Notes,'') + CHAR(10) + 'Cancelled: ' + @Reason, 1000) END,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericPayrollRunId = @GenericPayrollRunId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- Grants
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    DECLARE @procName SYSNAME;
    DECLARE proc_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.procedures
        WHERE name LIKE 'spGenericStaff%'
           OR name LIKE 'spGenericPayroll%';
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
    PRINT '056: granted EXECUTE on generic staff + payroll SPs to Techretainer.';
END
GO

PRINT '056_AddGenericStaffPayrollStoredProcedures.sql complete.';
GO

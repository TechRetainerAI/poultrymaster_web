-- =============================================================================
-- Migration 051: Stored procedures for Staff + Attendance + Payroll — W6
-- =============================================================================
-- Pairs with 050.
--
-- Approval semantics (payroll):
--   Draft → Approved → Paid
--   Cancel allowed from Draft or Approved.
--   "Paid" is the moment cash leaves the building. spWaterPayrollRun_MarkPaid
--   writes ONE WaterCashTransactions CashOut for TotalNetPay against the run's
--   WaterCashAccountId, and decrements the account's CurrentBalance — all in
--   one transaction. Per-item CashOuts would be noisier than helpful for a
--   small business; the audit trail still ties back via SourceType='Payroll'.
--
-- Idempotent. Run after 050.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- WaterStaff
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterStaff_GetAll
    @FarmId NVARCHAR(450),
    @Role   NVARCHAR(40) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT WaterStaffId, FarmId, FirstName, LastName, PhoneNumber, Email,
           Role, SalaryType, BasePay, CommissionRate,
           AssignedWaterVehicleId, AssignedWaterRouteId,
           IsActive, IsDeleted, Notes, CreatedAt, UpdatedAt
    FROM   dbo.WaterStaff
    WHERE  FarmId = @FarmId AND IsDeleted = 0
       AND (@Role IS NULL OR Role = @Role)
    ORDER  BY IsActive DESC, LastName, FirstName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterStaff_GetById
    @WaterStaffId INT,
    @FarmId       NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT WaterStaffId, FarmId, FirstName, LastName, PhoneNumber, Email,
           Role, SalaryType, BasePay, CommissionRate,
           AssignedWaterVehicleId, AssignedWaterRouteId,
           IsActive, IsDeleted, Notes, CreatedAt, UpdatedAt
    FROM   dbo.WaterStaff
    WHERE  WaterStaffId = @WaterStaffId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterStaff_Insert
    @FarmId                  NVARCHAR(450),
    @FirstName               NVARCHAR(100),
    @LastName                NVARCHAR(100),
    @PhoneNumber             NVARCHAR(50)  = NULL,
    @Email                   NVARCHAR(200) = NULL,
    @Role                    NVARCHAR(40)  = 'Other',
    @SalaryType              NVARCHAR(20)  = 'Monthly',
    @BasePay                 DECIMAL(14,2) = 0,
    @CommissionRate          DECIMAL(9,4)  = NULL,
    @AssignedWaterVehicleId  INT           = NULL,
    @AssignedWaterRouteId    INT           = NULL,
    @IsActive                BIT           = 1,
    @Notes                   NVARCHAR(1000)= NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@BasePay < 0) BEGIN RAISERROR('BasePay cannot be negative.', 16, 1); RETURN; END

    INSERT INTO dbo.WaterStaff (
        FarmId, FirstName, LastName, PhoneNumber, Email, Role, SalaryType,
        BasePay, CommissionRate, AssignedWaterVehicleId, AssignedWaterRouteId,
        IsActive, Notes
    )
    VALUES (
        @FarmId, @FirstName, @LastName, @PhoneNumber, @Email, @Role, @SalaryType,
        @BasePay, @CommissionRate, @AssignedWaterVehicleId, @AssignedWaterRouteId,
        @IsActive, @Notes
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterStaff_Update
    @WaterStaffId            INT,
    @FarmId                  NVARCHAR(450),
    @FirstName               NVARCHAR(100),
    @LastName                NVARCHAR(100),
    @PhoneNumber             NVARCHAR(50)  = NULL,
    @Email                   NVARCHAR(200) = NULL,
    @Role                    NVARCHAR(40),
    @SalaryType              NVARCHAR(20),
    @BasePay                 DECIMAL(14,2),
    @CommissionRate          DECIMAL(9,4)  = NULL,
    @AssignedWaterVehicleId  INT           = NULL,
    @AssignedWaterRouteId    INT           = NULL,
    @IsActive                BIT,
    @Notes                   NVARCHAR(1000)= NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterStaff
    SET    FirstName              = @FirstName,
           LastName               = @LastName,
           PhoneNumber            = @PhoneNumber,
           Email                  = @Email,
           Role                   = @Role,
           SalaryType             = @SalaryType,
           BasePay                = @BasePay,
           CommissionRate         = @CommissionRate,
           AssignedWaterVehicleId = @AssignedWaterVehicleId,
           AssignedWaterRouteId   = @AssignedWaterRouteId,
           IsActive               = @IsActive,
           Notes                  = @Notes,
           UpdatedAt              = SYSUTCDATETIME()
    WHERE  WaterStaffId = @WaterStaffId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterStaff_Delete
    @WaterStaffId INT,
    @FarmId       NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    -- Always soft-delete; attendance + payroll history references this row.
    UPDATE dbo.WaterStaff
    SET    IsDeleted = 1, IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterStaffId = @WaterStaffId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- WaterStaffAttendance
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterStaffAttendance_GetAll
    @FarmId       NVARCHAR(450),
    @WaterStaffId INT  = NULL,
    @FromDate     DATE = NULL,
    @ToDate       DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.WaterStaffAttendanceId, a.FarmId, a.WaterStaffId,
           s.FirstName + ' ' + s.LastName AS StaffName,
           a.AttendanceDate, a.ClockIn, a.ClockOut, a.Shift, a.Status, a.Notes,
           a.CreatedBy, a.CreatedAt
    FROM   dbo.WaterStaffAttendance a
    INNER  JOIN dbo.WaterStaff s ON s.WaterStaffId = a.WaterStaffId
    WHERE  a.FarmId = @FarmId
       AND (@WaterStaffId IS NULL OR a.WaterStaffId = @WaterStaffId)
       AND (@FromDate     IS NULL OR a.AttendanceDate >= @FromDate)
       AND (@ToDate       IS NULL OR a.AttendanceDate <= @ToDate)
    ORDER  BY a.AttendanceDate DESC, a.WaterStaffAttendanceId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterStaffAttendance_Upsert
    @FarmId         NVARCHAR(450),
    @WaterStaffId   INT,
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

    UPDATE dbo.WaterStaffAttendance
    SET    ClockIn  = @ClockIn,
           ClockOut = @ClockOut,
           Status   = @Status,
           Notes    = @Notes
    WHERE  WaterStaffId = @WaterStaffId AND AttendanceDate = @AttendanceDate
       AND ISNULL(Shift, '') = ISNULL(@Shift, '');

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO dbo.WaterStaffAttendance (
            FarmId, WaterStaffId, AttendanceDate, ClockIn, ClockOut, Shift, Status, Notes, CreatedBy
        )
        VALUES (
            @FarmId, @WaterStaffId, @AttendanceDate, @ClockIn, @ClockOut, @Shift, @Status, @Notes, @CreatedBy
        );
    END

    SELECT WaterStaffAttendanceId, FarmId, WaterStaffId, AttendanceDate, ClockIn, ClockOut,
           Shift, Status, Notes, CreatedBy, CreatedAt
    FROM   dbo.WaterStaffAttendance
    WHERE  WaterStaffId = @WaterStaffId AND AttendanceDate = @AttendanceDate
       AND ISNULL(Shift, '') = ISNULL(@Shift, '');
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterStaffAttendance_Delete
    @WaterStaffAttendanceId INT,
    @FarmId                 NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.WaterStaffAttendance
    WHERE  WaterStaffAttendanceId = @WaterStaffAttendanceId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- WaterPayrollRun
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterPayrollRun_GetAll
    @FarmId NVARCHAR(450),
    @Status NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.WaterPayrollRunId, r.FarmId, r.PeriodStart, r.PeriodEnd, r.PayDate,
           r.TotalGrossPay, r.TotalDeductions, r.TotalNetPay, r.Status,
           r.WaterCashAccountId, ca.AccountName AS CashAccountName,
           r.Notes, r.CreatedBy, r.ApprovedBy, r.ApprovedAt, r.PaidBy, r.PaidAt,
           r.CreatedAt, r.UpdatedAt
    FROM   dbo.WaterPayrollRuns r
    LEFT   JOIN dbo.WaterCashAccounts ca ON ca.WaterCashAccountId = r.WaterCashAccountId
    WHERE  r.FarmId = @FarmId AND r.IsDeleted = 0
       AND (@Status IS NULL OR r.Status = @Status)
    ORDER  BY r.PeriodStart DESC, r.WaterPayrollRunId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterPayrollRun_GetById
    @WaterPayrollRunId INT,
    @FarmId            NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.WaterPayrollRunId, r.FarmId, r.PeriodStart, r.PeriodEnd, r.PayDate,
           r.TotalGrossPay, r.TotalDeductions, r.TotalNetPay, r.Status,
           r.WaterCashAccountId, ca.AccountName AS CashAccountName,
           r.Notes, r.CreatedBy, r.ApprovedBy, r.ApprovedAt, r.PaidBy, r.PaidAt,
           r.CreatedAt, r.UpdatedAt
    FROM   dbo.WaterPayrollRuns r
    LEFT   JOIN dbo.WaterCashAccounts ca ON ca.WaterCashAccountId = r.WaterCashAccountId
    WHERE  r.WaterPayrollRunId = @WaterPayrollRunId AND r.FarmId = @FarmId;

    -- Items
    SELECT i.WaterPayrollItemId, i.WaterPayrollRunId, i.WaterStaffId,
           s.FirstName + ' ' + s.LastName AS StaffName, s.Role AS StaffRole,
           i.BasicPay, i.DailyWage, i.Commission, i.Bonus, i.Deductions, i.NetPay,
           i.PaymentMethod, i.Notes, i.CreatedAt
    FROM   dbo.WaterPayrollItems i
    INNER  JOIN dbo.WaterStaff s ON s.WaterStaffId = i.WaterStaffId
    WHERE  i.WaterPayrollRunId = @WaterPayrollRunId
    ORDER  BY s.LastName, s.FirstName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterPayrollRun_Insert
    @FarmId             NVARCHAR(450),
    @PeriodStart        DATE,
    @PeriodEnd          DATE,
    @PayDate            DATE          = NULL,
    @WaterCashAccountId INT           = NULL,
    @Notes              NVARCHAR(1000)= NULL,
    @CreatedBy          NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@PeriodStart > @PeriodEnd)
    BEGIN RAISERROR('PeriodStart cannot be after PeriodEnd.', 16, 1); RETURN; END

    INSERT INTO dbo.WaterPayrollRuns (
        FarmId, PeriodStart, PeriodEnd, PayDate, WaterCashAccountId, Status, Notes, CreatedBy
    )
    VALUES (@FarmId, @PeriodStart, @PeriodEnd, @PayDate, @WaterCashAccountId, 'Draft', @Notes, @CreatedBy);

    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

-- Adds (or replaces) one staff member's line on a payroll run while it's
-- still Draft. NetPay is a computed column on the table so we don't pass it.
CREATE OR ALTER PROCEDURE dbo.spWaterPayrollItem_Upsert
    @WaterPayrollRunId INT,
    @FarmId            NVARCHAR(450),
    @WaterStaffId      INT,
    @BasicPay          DECIMAL(14,2) = 0,
    @DailyWage         DECIMAL(14,2) = 0,
    @Commission        DECIMAL(14,2) = 0,
    @Bonus             DECIMAL(14,2) = 0,
    @Deductions        DECIMAL(14,2) = 0,
    @PaymentMethod     NVARCHAR(20)  = NULL,
    @Notes             NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Both run and staff must belong to FarmId.
    DECLARE @RunStatus NVARCHAR(20);
    SELECT @RunStatus = Status FROM dbo.WaterPayrollRuns
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;
    IF @RunStatus IS NULL BEGIN RAISERROR('Payroll run not found for this farm.', 16, 1); RETURN; END
    IF @RunStatus <> 'Draft' BEGIN RAISERROR('Payroll run is %s; only Draft can be modified.', 16, 1, @RunStatus); RETURN; END

    IF NOT EXISTS (SELECT 1 FROM dbo.WaterStaff WHERE WaterStaffId = @WaterStaffId AND FarmId = @FarmId)
    BEGIN RAISERROR('Staff %d not found on this farm.', 16, 1, @WaterStaffId); RETURN; END

    IF (@BasicPay   < 0 OR @DailyWage < 0 OR @Commission < 0 OR @Bonus < 0 OR @Deductions < 0)
    BEGIN RAISERROR('Pay components cannot be negative.', 16, 1); RETURN; END

    DECLARE @ProvisionalNetPay DECIMAL(14,2) = @BasicPay + @DailyWage + @Commission + @Bonus - @Deductions;
    IF (@ProvisionalNetPay < 0)
    BEGIN RAISERROR('NetPay cannot be negative.', 16, 1); RETURN; END

    BEGIN TRANSACTION;

    UPDATE dbo.WaterPayrollItems
    SET    BasicPay = @BasicPay, DailyWage = @DailyWage, Commission = @Commission,
           Bonus = @Bonus, Deductions = @Deductions,
           PaymentMethod = @PaymentMethod, Notes = @Notes
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND WaterStaffId = @WaterStaffId;

    IF @@ROWCOUNT = 0
    BEGIN
        INSERT INTO dbo.WaterPayrollItems (
            WaterPayrollRunId, WaterStaffId, BasicPay, DailyWage, Commission, Bonus, Deductions, PaymentMethod, Notes
        )
        VALUES (
            @WaterPayrollRunId, @WaterStaffId, @BasicPay, @DailyWage, @Commission, @Bonus, @Deductions, @PaymentMethod, @Notes
        );
    END

    -- Roll up totals onto the run.
    UPDATE r
    SET    TotalGrossPay   = tot.GrossPay,
           TotalDeductions = tot.Deductions,
           TotalNetPay     = tot.NetPay,
           UpdatedAt       = SYSUTCDATETIME()
    FROM   dbo.WaterPayrollRuns r
    CROSS  APPLY (
        SELECT  ISNULL(SUM(BasicPay + DailyWage + Commission + Bonus), 0) AS GrossPay,
                ISNULL(SUM(Deductions), 0)                                 AS Deductions,
                ISNULL(SUM(NetPay), 0)                                     AS NetPay
        FROM    dbo.WaterPayrollItems
        WHERE   WaterPayrollRunId = @WaterPayrollRunId
    ) tot
    WHERE  r.WaterPayrollRunId = @WaterPayrollRunId;

    COMMIT TRANSACTION;

    SELECT WaterPayrollItemId, WaterPayrollRunId, WaterStaffId,
           BasicPay, DailyWage, Commission, Bonus, Deductions, NetPay,
           PaymentMethod, Notes, CreatedAt
    FROM   dbo.WaterPayrollItems
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND WaterStaffId = @WaterStaffId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterPayrollItem_Delete
    @WaterPayrollItemId INT,
    @FarmId             NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RunId INT, @RunStatus NVARCHAR(20);
    SELECT @RunId = i.WaterPayrollRunId, @RunStatus = r.Status
    FROM   dbo.WaterPayrollItems i
    INNER  JOIN dbo.WaterPayrollRuns r ON r.WaterPayrollRunId = i.WaterPayrollRunId
    WHERE  i.WaterPayrollItemId = @WaterPayrollItemId AND r.FarmId = @FarmId;

    IF @RunId IS NULL BEGIN RAISERROR('Payroll item not found on this farm.', 16, 1); RETURN; END
    IF @RunStatus <> 'Draft' BEGIN RAISERROR('Payroll run is %s; only Draft can be modified.', 16, 1, @RunStatus); RETURN; END

    BEGIN TRANSACTION;

    DELETE FROM dbo.WaterPayrollItems WHERE WaterPayrollItemId = @WaterPayrollItemId;

    UPDATE r
    SET    TotalGrossPay   = tot.GrossPay,
           TotalDeductions = tot.Deductions,
           TotalNetPay     = tot.NetPay,
           UpdatedAt       = SYSUTCDATETIME()
    FROM   dbo.WaterPayrollRuns r
    CROSS  APPLY (
        SELECT  ISNULL(SUM(BasicPay + DailyWage + Commission + Bonus), 0) AS GrossPay,
                ISNULL(SUM(Deductions), 0)                                 AS Deductions,
                ISNULL(SUM(NetPay), 0)                                     AS NetPay
        FROM    dbo.WaterPayrollItems
        WHERE   WaterPayrollRunId = @RunId
    ) tot
    WHERE  r.WaterPayrollRunId = @RunId;

    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterPayrollRun_Approve
    @WaterPayrollRunId INT,
    @FarmId            NVARCHAR(450),
    @ApprovedBy        NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterPayrollRuns
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId AND Status = 'Draft';

    IF @@ROWCOUNT = 0 BEGIN RAISERROR('Payroll cannot be approved (not Draft or not found).', 16, 1); RETURN; END

    SELECT WaterPayrollRunId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.WaterPayrollRuns WHERE WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId;
END
GO

-- Mark paid: writes ONE CashOut for the run total. The cash account must be
-- set on the run before this is called (validation gate below).
CREATE OR ALTER PROCEDURE dbo.spWaterPayrollRun_MarkPaid
    @WaterPayrollRunId INT,
    @FarmId            NVARCHAR(450),
    @PaidBy            NVARCHAR(450) = NULL,
    @PayDate           DATE          = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @CashAccountId INT, @NetPay DECIMAL(14,2), @Notes NVARCHAR(1000);
    SELECT @Status = Status, @CashAccountId = WaterCashAccountId, @NetPay = TotalNetPay, @Notes = Notes
    FROM   dbo.WaterPayrollRuns
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL BEGIN RAISERROR('Payroll run not found.', 16, 1); RETURN; END
    IF @Status <> 'Approved' BEGIN RAISERROR('Payroll must be Approved before it can be marked Paid (current=%s).', 16, 1, @Status); RETURN; END
    IF @CashAccountId IS NULL BEGIN RAISERROR('Payroll has no WaterCashAccountId set; cannot pay.', 16, 1); RETURN; END
    IF @NetPay <= 0 BEGIN RAISERROR('Payroll TotalNetPay is zero; nothing to pay.', 16, 1); RETURN; END

    -- Negative-balance gate.
    DECLARE @AllowNeg BIT, @Bal DECIMAL(14,2);
    SELECT @AllowNeg = AllowNegativeBalance, @Bal = CurrentBalance
    FROM   dbo.WaterCashAccounts WHERE WaterCashAccountId = @CashAccountId;
    IF (@AllowNeg = 0 AND (@Bal - @NetPay) < 0)
    BEGIN RAISERROR('Cash account would go negative; payroll pay rejected.', 16, 1); RETURN; END

    BEGIN TRANSACTION;

    UPDATE dbo.WaterPayrollRuns
    SET    Status   = 'Paid',
           PaidBy   = @PaidBy,
           PaidAt   = SYSUTCDATETIME(),
           PayDate  = ISNULL(@PayDate, PayDate),
           UpdatedAt= SYSUTCDATETIME()
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId;

    INSERT INTO dbo.WaterCashTransactions (
        FarmId, WaterCashAccountId, TransactionDate, TransactionType,
        SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
    )
    VALUES (
        @FarmId, @CashAccountId, SYSUTCDATETIME(), 'CashOut',
        'Payroll', @WaterPayrollRunId, -@NetPay, ISNULL('Payroll: ' + LEFT(ISNULL(@Notes, ''), 200), 'Payroll'),
        @PaidBy, @PaidBy, SYSUTCDATETIME()
    );

    UPDATE dbo.WaterCashAccounts SET CurrentBalance = CurrentBalance - @NetPay, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterCashAccountId = @CashAccountId;

    COMMIT TRANSACTION;

    SELECT WaterPayrollRunId, Status, PaidBy, PaidAt, TotalNetPay
    FROM   dbo.WaterPayrollRuns WHERE WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterPayrollRun_Cancel
    @WaterPayrollRunId INT,
    @FarmId            NVARCHAR(450),
    @CancelledBy       NVARCHAR(450) = NULL,
    @Reason            NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @CashAccountId INT, @NetPay DECIMAL(14,2);
    SELECT @Status = Status, @CashAccountId = WaterCashAccountId, @NetPay = TotalNetPay
    FROM   dbo.WaterPayrollRuns
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL BEGIN RAISERROR('Payroll run not found.', 16, 1); RETURN; END
    IF @Status = 'Cancelled' RETURN;
    IF @Status = 'Paid'
    BEGIN
        -- Reverse the cash impact when cancelling a Paid run.
        IF (@CashAccountId IS NOT NULL AND @NetPay > 0)
        BEGIN
            BEGIN TRANSACTION;

            INSERT INTO dbo.WaterCashTransactions (
                FarmId, WaterCashAccountId, TransactionDate, TransactionType,
                SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
            )
            VALUES (
                @FarmId, @CashAccountId, SYSUTCDATETIME(), 'Adjustment',
                'Payroll', @WaterPayrollRunId, @NetPay, 'Payroll cancelled — reversal',
                @CancelledBy, @CancelledBy, SYSUTCDATETIME()
            );

            UPDATE dbo.WaterCashAccounts SET CurrentBalance = CurrentBalance + @NetPay, UpdatedAt = SYSUTCDATETIME()
            WHERE  WaterCashAccountId = @CashAccountId;

            UPDATE dbo.WaterPayrollRuns
            SET    Status = 'Cancelled',
                   Notes  = CASE WHEN @Reason IS NULL THEN Notes ELSE LEFT(ISNULL(Notes,'') + CHAR(10) + 'Cancelled: ' + @Reason, 1000) END,
                   UpdatedAt = SYSUTCDATETIME()
            WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId;

            COMMIT TRANSACTION;
            RETURN;
        END
    END

    -- Draft or Approved: just flip status.
    UPDATE dbo.WaterPayrollRuns
    SET    Status = 'Cancelled',
           Notes  = CASE WHEN @Reason IS NULL THEN Notes ELSE LEFT(ISNULL(Notes,'') + CHAR(10) + 'Cancelled: ' + @Reason, 1000) END,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId;
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
        WHERE name LIKE 'spWaterStaff%'
           OR name LIKE 'spWaterPayroll%';
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
    PRINT '051: granted EXECUTE on water staff + payroll SPs to Techretainer.';
END
GO

PRINT '051_AddWaterStaffPayrollStoredProcedures.sql complete.';
GO

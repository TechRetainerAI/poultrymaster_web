-- =============================================================================
-- Migration 080: Payroll Unapprove / Delete + Reopen audit cols + Reapprove
-- =============================================================================
-- "Three Prompts In one powerful please implement all.txt" Prompt 3.
--
-- After this migration the Payroll page can support the full status-gated
-- action set:
--
--   Draft / Reopened       → Edit / Approve (= reapprove if from Reopened) / Delete
--   Approved / Paid        → Unapprove (= flip back to Reopened, reverse linked expense)
--
-- Schema additions on dbo.WaterPayrollRuns
--   ReopenedBy / ReopenedAt / ReopenReason  — set by _Unapprove
--   ReapprovedBy / ReapprovedAt             — set by _Approve when prior status was Reopened
--
-- SPs
--   spWaterPayrollRun_Unapprove  — Approved/Paid → Reopened
--                                  * Reverses the linked WaterExpense (IsDeleted=1,
--                                    Status='Cancelled') so the filtered unique
--                                    index frees up for a fresh active row on
--                                    reapproval — mirrors the _Cancel SP from 075.
--                                  * If Status was Paid, reverses the cash
--                                    transaction and refunds the cash account
--                                    balance, exactly like _Cancel does.
--                                  * Records ReopenedBy / At / Reason.
--   spWaterPayrollRun_Delete     — Draft/Pending/Reopened → row removed.
--                                  * Rejects if Status IN ('Approved','Paid')
--                                    or if there's any non-cancelled linked
--                                    expense pointing at this run.
--                                  * Drops WaterPayrollItems first (no cascade
--                                    on FK_WaterPayrollItems_Run).
--   spWaterPayrollRun_Approve    — rewritten to accept Status IN ('Draft','Reopened').
--                                  When reapproving (prior was Reopened) it records
--                                  ReapprovedBy / ReapprovedAt instead of the
--                                  initial ApprovedBy / At (those stay as the
--                                  first-approval audit trail).
--                                  Linked-expense upsert is unchanged from 075.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Schema additions
-- -----------------------------------------------------------------------------
IF COL_LENGTH(N'dbo.WaterPayrollRuns', N'ReopenedBy') IS NULL
    ALTER TABLE dbo.WaterPayrollRuns ADD ReopenedBy NVARCHAR(450) NULL;
GO
IF COL_LENGTH(N'dbo.WaterPayrollRuns', N'ReopenedAt') IS NULL
    ALTER TABLE dbo.WaterPayrollRuns ADD ReopenedAt DATETIME2 NULL;
GO
IF COL_LENGTH(N'dbo.WaterPayrollRuns', N'ReopenReason') IS NULL
    ALTER TABLE dbo.WaterPayrollRuns ADD ReopenReason NVARCHAR(500) NULL;
GO
IF COL_LENGTH(N'dbo.WaterPayrollRuns', N'ReapprovedBy') IS NULL
    ALTER TABLE dbo.WaterPayrollRuns ADD ReapprovedBy NVARCHAR(450) NULL;
GO
IF COL_LENGTH(N'dbo.WaterPayrollRuns', N'ReapprovedAt') IS NULL
    ALTER TABLE dbo.WaterPayrollRuns ADD ReapprovedAt DATETIME2 NULL;
GO

-- -----------------------------------------------------------------------------
-- 2. spWaterPayrollRun_Approve — accept Draft OR Reopened; record reapproval
--    Replaces the body from migration 075. The linked-expense upsert logic is
--    unchanged so this stays drop-in for the existing Approve endpoint.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterPayrollRun_Approve
    @WaterPayrollRunId INT,
    @FarmId            NVARCHAR(450),
    @ApprovedBy        NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @PriorStatus NVARCHAR(20);
    SELECT @PriorStatus = Status FROM dbo.WaterPayrollRuns
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @PriorStatus IS NULL
    BEGIN RAISERROR('Payroll run not found.', 16, 1); RETURN; END
    IF @PriorStatus NOT IN (N'Draft', N'Reopened')
    BEGIN RAISERROR('Payroll cannot be approved (current=%s).', 16, 1, @PriorStatus); RETURN; END

    BEGIN TRANSACTION;

    IF @PriorStatus = N'Reopened'
    BEGIN
        -- Reapproval: preserve the original ApprovedBy/At; record Reapproved*.
        UPDATE dbo.WaterPayrollRuns
        SET    Status        = N'Approved',
               ReapprovedBy  = @ApprovedBy,
               ReapprovedAt  = SYSUTCDATETIME(),
               UpdatedAt     = SYSUTCDATETIME()
        WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId;
    END
    ELSE  -- Draft
    BEGIN
        UPDATE dbo.WaterPayrollRuns
        SET    Status     = N'Approved',
               ApprovedBy = @ApprovedBy,
               ApprovedAt = SYSUTCDATETIME(),
               UpdatedAt  = SYSUTCDATETIME()
        WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId;
    END

    -- Linked-expense upsert (unchanged from migration 075).
    DECLARE @NetPay DECIMAL(14,2), @PeriodStart DATE, @PeriodEnd DATE,
            @PayDate DATE, @CashAccountId INT, @Notes NVARCHAR(1000);
    SELECT @NetPay        = TotalNetPay,
           @PeriodStart   = PeriodStart,
           @PeriodEnd     = PeriodEnd,
           @PayDate       = PayDate,
           @CashAccountId = WaterCashAccountId,
           @Notes         = Notes
    FROM   dbo.WaterPayrollRuns
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId;

    DECLARE @CatId INT;
    SELECT TOP (1) @CatId = WaterExpenseCategoryId
    FROM   dbo.WaterExpenseCategories
    WHERE  FarmId = @FarmId
      AND  Name IN (N'Payroll', N'Salaries', N'Wages')
      AND  IsActive = 1
    ORDER BY CASE Name WHEN N'Payroll' THEN 1 WHEN N'Salaries' THEN 2 ELSE 3 END;

    IF @CatId IS NULL
    BEGIN
        INSERT INTO dbo.WaterExpenseCategories (FarmId, Name, IsActive)
        VALUES (@FarmId, N'Payroll', 1);
        SET @CatId = SCOPE_IDENTITY();
    END

    DECLARE @ExpenseDate DATETIME2 = ISNULL(CAST(@PayDate AS DATETIME2), SYSUTCDATETIME());
    DECLARE @Description NVARCHAR(500) = CONCAT(
        N'Payroll for ',
        CONVERT(NVARCHAR(10), @PeriodStart, 23),
        N' to ',
        CONVERT(NVARCHAR(10), @PeriodEnd, 23),
        N' (run #', @WaterPayrollRunId, N')'
    );

    IF EXISTS (
        SELECT 1 FROM dbo.WaterExpenses
        WHERE FarmId = @FarmId AND SourceType = N'Payroll'
          AND SourceId = @WaterPayrollRunId AND IsDeleted = 0
    )
    BEGIN
        UPDATE dbo.WaterExpenses
        SET    Amount        = @NetPay,
               ExpenseDate   = @ExpenseDate,
               Description   = @Description,
               WaterExpenseCategoryId = @CatId,
               WaterCashAccountId = @CashAccountId,
               Status        = N'Approved',
               ApprovedBy    = @ApprovedBy,
               ApprovedAt    = SYSUTCDATETIME(),
               UpdatedAt     = SYSUTCDATETIME()
        WHERE  FarmId = @FarmId AND SourceType = N'Payroll'
          AND  SourceId = @WaterPayrollRunId AND IsDeleted = 0;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.WaterExpenses (
            FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount,
            PaymentMethod, WaterCashAccountId, Status,
            SourceType, SourceId,
            CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @ExpenseDate, @CatId, @Description, @NetPay,
            CASE WHEN @CashAccountId IS NULL THEN N'Credit' ELSE N'Cash' END,
            @CashAccountId, N'Approved',
            N'Payroll', @WaterPayrollRunId,
            @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
        );
    END

    COMMIT TRANSACTION;

    SELECT WaterPayrollRunId, Status, ApprovedBy, ApprovedAt, ReapprovedBy, ReapprovedAt
    FROM   dbo.WaterPayrollRuns
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- 3. spWaterPayrollRun_Unapprove — flip Approved/Paid → Reopened
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterPayrollRun_Unapprove
    @WaterPayrollRunId INT,
    @FarmId            NVARCHAR(450),
    @ReopenedBy        NVARCHAR(450) = NULL,
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
    IF @Status NOT IN (N'Approved', N'Paid')
    BEGIN RAISERROR('Payroll can only be reopened from Approved or Paid (current=%s).', 16, 1, @Status); RETURN; END

    BEGIN TRANSACTION;

    -- If currently Paid, reverse the cash transaction + refund the cash account.
    IF @Status = N'Paid' AND @CashAccountId IS NOT NULL AND @NetPay > 0
    BEGIN
        INSERT INTO dbo.WaterCashTransactions (
            FarmId, WaterCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @CashAccountId, SYSUTCDATETIME(), 'Adjustment',
            'Payroll', @WaterPayrollRunId, @NetPay,
            CONCAT(N'Payroll reopened — reversal', CASE WHEN @Reason IS NULL THEN N'' ELSE N': ' + @Reason END),
            @ReopenedBy, @ReopenedBy, SYSUTCDATETIME()
        );
        UPDATE dbo.WaterCashAccounts
        SET    CurrentBalance = CurrentBalance + @NetPay, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterCashAccountId = @CashAccountId;
    END

    -- Flip the run to Reopened. Audit cols set; Paid* stays as historical
    -- record of the prior approval/payment cycle.
    UPDATE dbo.WaterPayrollRuns
    SET    Status       = N'Reopened',
           ReopenedBy   = @ReopenedBy,
           ReopenedAt   = SYSUTCDATETIME(),
           ReopenReason = @Reason,
           UpdatedAt    = SYSUTCDATETIME()
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId;

    -- Reverse the linked expense — IsDeleted=1 so the filtered unique index
    -- frees up for a fresh active row when the run is reapproved later.
    UPDATE dbo.WaterExpenses
    SET    Status    = N'Cancelled',
           IsDeleted = 1,
           Notes     = LEFT(ISNULL(Notes, N'') + CHAR(10) + N'Payroll reopened'
                            + CASE WHEN @Reason IS NULL THEN N'' ELSE N': ' + @Reason END, 1000),
           UpdatedAt = SYSUTCDATETIME()
    WHERE  FarmId = @FarmId AND SourceType = N'Payroll'
      AND  SourceId = @WaterPayrollRunId AND IsDeleted = 0;

    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- 4. spWaterPayrollRun_Delete — only Draft/Pending/Reopened with no active expense
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterPayrollRun_Delete
    @WaterPayrollRunId INT,
    @FarmId            NVARCHAR(450),
    @DeletedBy         NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.WaterPayrollRuns
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL BEGIN RAISERROR('Payroll run not found.', 16, 1); RETURN; END
    IF @Status NOT IN (N'Draft', N'Pending', N'Reopened')
    BEGIN RAISERROR('Payroll cannot be deleted while %s. Unapprove first.', 16, 1, @Status); RETURN; END

    -- Refuse if there's still an active linked expense — Unapprove should have
    -- cancelled it. Belt-and-braces against orphaned cash impact.
    IF EXISTS (
        SELECT 1 FROM dbo.WaterExpenses
        WHERE FarmId = @FarmId AND SourceType = N'Payroll'
          AND SourceId = @WaterPayrollRunId AND IsDeleted = 0
    )
    BEGIN RAISERROR('Payroll has an active linked expense. Unapprove first.', 16, 1); RETURN; END

    BEGIN TRANSACTION;

    DELETE FROM dbo.WaterPayrollItems
    WHERE  WaterPayrollRunId = @WaterPayrollRunId;

    DELETE FROM dbo.WaterPayrollRuns
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- 5. Grants
-- -----------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'PoultryAppRole' AND type = N'R')
BEGIN
    GRANT EXECUTE ON dbo.spWaterPayrollRun_Approve   TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterPayrollRun_Unapprove TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterPayrollRun_Delete    TO PoultryAppRole;
END
GO
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'Techretainer')
BEGIN
    GRANT EXECUTE ON dbo.spWaterPayrollRun_Approve   TO Techretainer;
    GRANT EXECUTE ON dbo.spWaterPayrollRun_Unapprove TO Techretainer;
    GRANT EXECUTE ON dbo.spWaterPayrollRun_Delete    TO Techretainer;
END
GO

PRINT '080_AddWaterPayrollUnapproveDeleteAndAudit.sql complete.';
GO

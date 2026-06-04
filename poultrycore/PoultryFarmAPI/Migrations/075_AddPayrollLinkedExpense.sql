-- =============================================================================
-- Migration 075: Approved/Paid payroll creates one linked Expense row
-- =============================================================================
-- James (2026-05-30) — see Migrations/ompal/Payroll entry should create report
-- entry.txt for the full spec. Implements all 14 requirements.
--
-- Summary
--   * Draft/Pending payroll → no expense (existing default; no change needed).
--   * Approved or Paid       → one linked WaterExpense for the run TOTAL.
--   * Cancelled              → linked expense is hard-cancelled (IsDeleted=1, Status='Cancelled')
--                              so it disappears from active Expenses + reports.
--   * Reapprove (if a cancelled run is somehow re-approved later) — handled by
--     the UPSERT (filtered unique index + IF EXISTS guard in the SP).
--
-- Schema
--   1. WaterExpenses gets two columns:
--        SourceType NVARCHAR(40) NULL  -- 'Payroll' for these, NULL for hand-entered
--        SourceId   INT          NULL  -- WaterPayrollRunId when SourceType='Payroll'
--   2. Filtered UNIQUE index on (FarmId, SourceType, SourceId) WHERE
--      SourceType IS NOT NULL AND IsDeleted = 0 — guarantees at most ONE active
--      linked expense per payroll run. A cancelled (IsDeleted=1) one is allowed
--      so a re-approval can insert a fresh active row alongside the history.
--
-- Lazy seed
--   The Payroll category is ensured per FarmId on first use (SPs check + insert
--   if missing). Avoids needing a global data migration; new farms automatically
--   get the category the first time someone approves payroll.
--
-- Reapproval behaviour
--   Approve SP first looks for an existing active linked expense. If present,
--   update it; otherwise insert. Same for MarkPaid (which refines PaymentMethod
--   + ExpenseDate). The filtered unique index enforces the "at most one active"
--   invariant on top of the SP logic.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Schema additions on dbo.WaterExpenses
-- -----------------------------------------------------------------------------
IF COL_LENGTH(N'dbo.WaterExpenses', N'SourceType') IS NULL
    ALTER TABLE dbo.WaterExpenses ADD SourceType NVARCHAR(40) NULL;
GO
IF COL_LENGTH(N'dbo.WaterExpenses', N'SourceId') IS NULL
    ALTER TABLE dbo.WaterExpenses ADD SourceId INT NULL;
GO

-- Filtered unique index: at most one active linked expense per (farm, source).
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_WaterExpenses_FarmSource_Active'
      AND object_id = OBJECT_ID(N'dbo.WaterExpenses')
)
BEGIN
    CREATE UNIQUE INDEX UX_WaterExpenses_FarmSource_Active
        ON dbo.WaterExpenses (FarmId, SourceType, SourceId)
        WHERE SourceType IS NOT NULL AND IsDeleted = 0;
END
GO

-- -----------------------------------------------------------------------------
-- 2. spWaterPayrollRun_Approve — flip to Approved AND upsert linked expense
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterPayrollRun_Approve
    @WaterPayrollRunId INT,
    @FarmId            NVARCHAR(450),
    @ApprovedBy        NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    -- A) Approve the run.
    UPDATE dbo.WaterPayrollRuns
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId AND Status = 'Draft';

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR('Payroll cannot be approved (not Draft or not found).', 16, 1);
        RETURN;
    END

    -- B) Compute / source the values for the linked expense.
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

    -- C) Ensure a Payroll expense category exists for this farm; lazy-seed.
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

    -- D) Upsert the linked expense (one per Payroll run).
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
               Status        = 'Approved',
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

    SELECT WaterPayrollRunId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.WaterPayrollRuns WHERE WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- 3. spWaterPayrollRun_MarkPaid — set Paid AND refine the linked expense
--    (PaymentMethod + ExpenseDate become concrete once paid)
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterPayrollRun_MarkPaid
    @WaterPayrollRunId INT,
    @FarmId            NVARCHAR(450),
    @PaidBy            NVARCHAR(450) = NULL,
    @PayDate           DATE          = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @CashAccountId INT, @NetPay DECIMAL(14,2),
            @Notes NVARCHAR(1000), @PeriodStart DATE, @PeriodEnd DATE;
    SELECT @Status = Status, @CashAccountId = WaterCashAccountId,
           @NetPay = TotalNetPay, @Notes = Notes,
           @PeriodStart = PeriodStart, @PeriodEnd = PeriodEnd
    FROM   dbo.WaterPayrollRuns
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL BEGIN RAISERROR('Payroll run not found.', 16, 1); RETURN; END
    IF @Status <> 'Approved' BEGIN RAISERROR('Payroll must be Approved before it can be marked Paid (current=%s).', 16, 1, @Status); RETURN; END
    IF @CashAccountId IS NULL BEGIN RAISERROR('Payroll has no WaterCashAccountId set; cannot pay.', 16, 1); RETURN; END
    IF @NetPay <= 0 BEGIN RAISERROR('Payroll TotalNetPay is zero; nothing to pay.', 16, 1); RETURN; END

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

    -- Cash transaction (unchanged from migration 051).
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

    -- Refine the linked expense — the Approve SP already inserted it; here we
    -- update PaymentMethod (now we know it's real cash out of @CashAccountId)
    -- and ExpenseDate (now we have a real PayDate).
    DECLARE @ExpenseDate DATETIME2 = CAST(ISNULL(@PayDate, CONVERT(DATE, SYSUTCDATETIME())) AS DATETIME2);

    IF EXISTS (
        SELECT 1 FROM dbo.WaterExpenses
        WHERE FarmId = @FarmId AND SourceType = N'Payroll'
          AND SourceId = @WaterPayrollRunId AND IsDeleted = 0
    )
    BEGIN
        UPDATE dbo.WaterExpenses
        SET    PaymentMethod      = N'Cash',
               WaterCashAccountId = @CashAccountId,
               ExpenseDate        = @ExpenseDate,
               Status             = N'Approved',
               UpdatedAt          = SYSUTCDATETIME()
        WHERE  FarmId = @FarmId AND SourceType = N'Payroll'
          AND  SourceId = @WaterPayrollRunId AND IsDeleted = 0;
    END
    ELSE
    BEGIN
        -- Defensive fallback: if for some reason there's no linked expense yet
        -- (e.g. legacy Approved run from before this migration), create one.
        DECLARE @CatId INT;
        SELECT TOP (1) @CatId = WaterExpenseCategoryId
        FROM   dbo.WaterExpenseCategories
        WHERE  FarmId = @FarmId AND IsActive = 1
          AND  Name IN (N'Payroll', N'Salaries', N'Wages')
        ORDER BY CASE Name WHEN N'Payroll' THEN 1 WHEN N'Salaries' THEN 2 ELSE 3 END;
        IF @CatId IS NULL
        BEGIN
            INSERT INTO dbo.WaterExpenseCategories (FarmId, Name, IsActive)
            VALUES (@FarmId, N'Payroll', 1);
            SET @CatId = SCOPE_IDENTITY();
        END

        INSERT INTO dbo.WaterExpenses (
            FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount,
            PaymentMethod, WaterCashAccountId, Status,
            SourceType, SourceId,
            CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @ExpenseDate, @CatId,
            CONCAT(N'Payroll for ', CONVERT(NVARCHAR(10), @PeriodStart, 23),
                   N' to ',         CONVERT(NVARCHAR(10), @PeriodEnd, 23),
                   N' (run #', @WaterPayrollRunId, N')'),
            @NetPay, N'Cash', @CashAccountId, N'Approved',
            N'Payroll', @WaterPayrollRunId,
            @PaidBy, @PaidBy, SYSUTCDATETIME()
        );
    END

    COMMIT TRANSACTION;

    SELECT WaterPayrollRunId, Status, PaidBy, PaidAt, TotalNetPay
    FROM   dbo.WaterPayrollRuns WHERE WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- 4. spWaterPayrollRun_Cancel — cancel run + linked expense atomically
-- -----------------------------------------------------------------------------
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

    BEGIN TRANSACTION;

    IF @Status = 'Paid'
    BEGIN
        IF (@CashAccountId IS NOT NULL AND @NetPay > 0)
        BEGIN
            INSERT INTO dbo.WaterCashTransactions (
                FarmId, WaterCashAccountId, TransactionDate, TransactionType,
                SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
            )
            VALUES (
                @FarmId, @CashAccountId, SYSUTCDATETIME(), 'Adjustment',
                'Payroll', @WaterPayrollRunId, @NetPay, 'Payroll cancelled — reversal',
                @CancelledBy, @CancelledBy, SYSUTCDATETIME()
            );

            UPDATE dbo.WaterCashAccounts
            SET    CurrentBalance = CurrentBalance + @NetPay, UpdatedAt = SYSUTCDATETIME()
            WHERE  WaterCashAccountId = @CashAccountId;
        END
    END

    UPDATE dbo.WaterPayrollRuns
    SET    Status    = 'Cancelled',
           Notes     = CASE WHEN @Reason IS NULL THEN Notes
                           ELSE LEFT(ISNULL(Notes,'') + CHAR(10) + 'Cancelled: ' + @Reason, 1000) END,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId;

    -- Cancel the linked Expense row (if any). Hard-cancel: IsDeleted=1 +
    -- Status='Cancelled' so it drops out of the active Expenses page AND the
    -- filtered unique index frees up for a future re-approval.
    UPDATE dbo.WaterExpenses
    SET    Status    = N'Cancelled',
           IsDeleted = 1,
           Notes     = CASE WHEN @Reason IS NULL THEN Notes
                           ELSE LEFT(ISNULL(Notes,'') + CHAR(10) + 'Payroll cancelled: ' + @Reason, 1000) END,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  FarmId = @FarmId AND SourceType = N'Payroll'
      AND  SourceId = @WaterPayrollRunId AND IsDeleted = 0;

    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- 5. EXECUTE grants (idempotent — matches migrations 051/064/071/072)
-- -----------------------------------------------------------------------------
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterPayrollRun_Approve  TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterPayrollRun_MarkPaid TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterPayrollRun_Cancel   TO [Techretainer];
END
GO
IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterPayrollRun_Approve  TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterPayrollRun_MarkPaid TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterPayrollRun_Cancel   TO PoultryAppRole;
END
GO

PRINT '075_AddPayrollLinkedExpense.sql complete.';
GO

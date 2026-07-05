-- =============================================================================
-- Migration 132: pay a poultry expense from a cash account (like the Water side).
-- =============================================================================
-- Adds dbo.Expense.PoultryCashAccountId and a sync SP that posts / reverses a
-- CashOut on the chosen PoultryCashAccount (SourceType='Expense', SourceId=
-- ExpenseId). The read SPs are updated to return the new column so the edit
-- form can prefill. Idempotent.
--
-- dbo.Expense.FarmId is UNIQUEIDENTIFIER; the cash tables use NVARCHAR(450).
-- The sync SP takes @FarmId NVARCHAR(450) (the original string from the service)
-- so cash rows scope correctly, and converts for the dbo.Expense update.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.Expense', 'PoultryCashAccountId') IS NULL
BEGIN
    ALTER TABLE dbo.Expense ADD PoultryCashAccountId INT NULL;
    PRINT '132: added dbo.Expense.PoultryCashAccountId';
END
GO

-- ---- read SPs now expose PoultryCashAccountId --------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spExpense_GetAll]
    @FarmId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        e.ExpenseId, e.ExpenseDate, e.Category, e.Description, e.Amount, e.PaymentMethod,
        Supplier = e.Supplier, e.FlockId, e.CreatedDate, e.FarmId, e.UserId,
        e.PoultryCashAccountId,
        CAST(CASE WHEN e.AttachmentImage IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS HasAttachmentImage
    FROM dbo.Expense e
    WHERE e.FarmId = @FarmId
    ORDER BY e.CreatedDate DESC;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spExpense_GetById]
    @ExpenseId INT,
    @FarmId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        e.ExpenseId, e.ExpenseDate, e.Category, e.Description, e.Amount, e.PaymentMethod,
        Supplier = e.Supplier, e.FlockId, e.CreatedDate, e.FarmId, e.UserId,
        e.PoultryCashAccountId,
        CAST(CASE WHEN e.AttachmentImage IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS HasAttachmentImage
    FROM dbo.Expense e
    WHERE e.ExpenseId = @ExpenseId AND e.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spExpense_GetByFlock]
    @FlockId INT,
    @FarmId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        e.ExpenseId, e.ExpenseDate, e.Category, e.Description, e.Amount, e.PaymentMethod,
        Supplier = e.Supplier, e.FlockId, e.CreatedDate, e.FarmId, e.UserId,
        e.PoultryCashAccountId,
        CAST(CASE WHEN e.AttachmentImage IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS HasAttachmentImage
    FROM dbo.Expense e
    WHERE e.FlockId = @FlockId AND e.FarmId = @FarmId
    ORDER BY e.CreatedDate DESC;
END
GO

-- ---- post / reverse the expense's cash-out ----------------------------------
-- Idempotent per expense: always reverses the existing Expense cash tx first,
-- then (if an account + positive amount is given) posts a fresh CashOut. Called
-- on create, update and delete (delete passes a NULL account = reverse only).
CREATE OR ALTER PROCEDURE dbo.spPoultryExpenseCash_Sync
    @FarmId               NVARCHAR(450),
    @ExpenseId            INT,
    @PoultryCashAccountId INT           = NULL,
    @Amount               DECIMAL(14,2) = 0,
    @Description          NVARCHAR(500) = NULL,
    @CreatedBy            NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FarmGuid UNIQUEIDENTIFIER = TRY_CONVERT(UNIQUEIDENTIFIER, @FarmId);

    BEGIN TRANSACTION;

    -- Reverse any existing expense cash tx (restore balances, then delete them).
    UPDATE a
    SET    a.CurrentBalance = a.CurrentBalance - t.Net, a.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryCashAccounts a
    INNER  JOIN (
        SELECT PoultryCashAccountId, SUM(Amount) AS Net
        FROM   dbo.PoultryCashTransactions
        WHERE  SourceType = 'Expense' AND SourceId = @ExpenseId AND FarmId = @FarmId
        GROUP  BY PoultryCashAccountId
    ) t ON t.PoultryCashAccountId = a.PoultryCashAccountId
    WHERE  a.FarmId = @FarmId;

    DELETE FROM dbo.PoultryCashTransactions
    WHERE  SourceType = 'Expense' AND SourceId = @ExpenseId AND FarmId = @FarmId;

    -- Record the chosen account on the expense row.
    UPDATE dbo.Expense SET PoultryCashAccountId = @PoultryCashAccountId
    WHERE  ExpenseId = @ExpenseId AND FarmId = @FarmGuid;

    -- Post the fresh cash-out.
    IF (@PoultryCashAccountId IS NOT NULL AND @Amount > 0
        AND EXISTS (SELECT 1 FROM dbo.PoultryCashAccounts WHERE PoultryCashAccountId = @PoultryCashAccountId AND FarmId = @FarmId))
    BEGIN
        UPDATE dbo.PoultryCashAccounts
        SET    CurrentBalance = CurrentBalance - @Amount, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryCashAccountId = @PoultryCashAccountId AND FarmId = @FarmId;

        DECLARE @bal DECIMAL(14,2) = (SELECT CurrentBalance FROM dbo.PoultryCashAccounts WHERE PoultryCashAccountId = @PoultryCashAccountId);

        INSERT INTO dbo.PoultryCashTransactions
            (FarmId, PoultryCashAccountId, TransactionDate, TransactionType, SourceType, SourceId,
             Amount, BalanceAfterTransaction, Description, CreatedBy, ApprovedBy, ApprovedAt)
        VALUES
            (@FarmId, @PoultryCashAccountId, SYSUTCDATETIME(), 'CashOut', 'Expense', @ExpenseId,
             -@Amount, @bal, ISNULL(@Description, N'Expense payment'), @CreatedBy, @CreatedBy, SYSUTCDATETIME());
    END

    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryExpenseCash_Sync TO [Techretainer];
    GRANT EXECUTE ON dbo.spExpense_GetAll  TO [Techretainer];
    GRANT EXECUTE ON dbo.spExpense_GetById TO [Techretainer];
    GRANT EXECUTE ON dbo.spExpense_GetByFlock TO [Techretainer];
END
GO

PRINT '132_ExpenseCashAccountLink: complete.';
GO

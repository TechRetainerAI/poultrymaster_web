-- =============================================================================
-- Migration 137: receive a poultry sale into a cash account (mirror of mig 132).
-- =============================================================================
-- Adds dbo.Sale.PoultryCashAccountId and a sync SP that posts / reverses a
-- CashIn on the chosen PoultryCashAccount (SourceType='Sale', SourceId=SaleId).
-- The read SPs are updated to return the new column so the edit form can
-- prefill. Idempotent.
--
-- Unlike expenses, a sale carries a Paid flag: cash only actually arrives when
-- the sale is paid, so the sync only posts a CashIn when @Paid = 1. An unpaid
-- sale still records the chosen account (for when it is later marked paid) but
-- moves no money. The reverse-then-repost shape keeps it correct across edits
-- (e.g. a paid sale later flipped to unpaid removes its CashIn).
--
-- dbo.Sale.FarmId is NVARCHAR (matches PoultryCashAccounts.FarmId), so no GUID
-- conversion is needed here.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.Sale', 'PoultryCashAccountId') IS NULL
BEGIN
    ALTER TABLE dbo.Sale ADD PoultryCashAccountId INT NULL;
    PRINT '137: added dbo.Sale.PoultryCashAccountId';
END
GO

-- ---- read SPs now expose PoultryCashAccountId --------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spSale_GetById]
    @SaleId INT,
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        SaleId, UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount,
        PaymentMethod, CustomerName, FlockId, SaleDescription, ISNULL(Paid, 1) AS Paid,
        Size, PoultryCashAccountId,
        CreatedDate
    FROM [dbo].[Sale]
    WHERE SaleId = @SaleId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSale_GetAll]
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        SaleId, UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount,
        PaymentMethod, CustomerName, FlockId, SaleDescription, ISNULL(Paid, 1) AS Paid,
        Size, PoultryCashAccountId,
        CreatedDate
    FROM [dbo].[Sale]
    WHERE FarmId = @FarmId
    ORDER BY SaleDate DESC, CreatedDate DESC;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSale_GetByFlock]
    @FlockId INT,
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        SaleId, UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount,
        PaymentMethod, CustomerName, FlockId, SaleDescription, ISNULL(Paid, 1) AS Paid,
        Size, PoultryCashAccountId,
        CreatedDate
    FROM [dbo].[Sale]
    WHERE FarmId = @FarmId AND FlockId = @FlockId
    ORDER BY SaleDate DESC, CreatedDate DESC;
END
GO

-- ---- post / reverse the sale's cash-in --------------------------------------
-- Idempotent per sale: always reverses the existing Sale cash tx first, then
-- (if an account + positive amount is given AND the sale is paid) posts a fresh
-- CashIn. Called on create, update and delete (delete passes a NULL account =
-- reverse only).
CREATE OR ALTER PROCEDURE dbo.spPoultrySaleCash_Sync
    @FarmId               NVARCHAR(450),
    @SaleId               INT,
    @PoultryCashAccountId INT           = NULL,
    @Amount               DECIMAL(14,2) = 0,
    @Paid                 BIT           = 1,
    @Description          NVARCHAR(500) = NULL,
    @CreatedBy            NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    -- Reverse any existing sale cash tx (restore balances, then delete them).
    UPDATE a
    SET    a.CurrentBalance = a.CurrentBalance - t.Net, a.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryCashAccounts a
    INNER  JOIN (
        SELECT PoultryCashAccountId, SUM(Amount) AS Net
        FROM   dbo.PoultryCashTransactions
        WHERE  SourceType = 'Sale' AND SourceId = @SaleId AND FarmId = @FarmId
        GROUP  BY PoultryCashAccountId
    ) t ON t.PoultryCashAccountId = a.PoultryCashAccountId
    WHERE  a.FarmId = @FarmId;

    DELETE FROM dbo.PoultryCashTransactions
    WHERE  SourceType = 'Sale' AND SourceId = @SaleId AND FarmId = @FarmId;

    -- Record the chosen account on the sale row.
    UPDATE dbo.Sale SET PoultryCashAccountId = @PoultryCashAccountId
    WHERE  SaleId = @SaleId AND FarmId = @FarmId;

    -- Post the fresh cash-in (only when the sale is actually paid).
    IF (@PoultryCashAccountId IS NOT NULL AND @Amount > 0 AND ISNULL(@Paid, 1) = 1
        AND EXISTS (SELECT 1 FROM dbo.PoultryCashAccounts WHERE PoultryCashAccountId = @PoultryCashAccountId AND FarmId = @FarmId))
    BEGIN
        UPDATE dbo.PoultryCashAccounts
        SET    CurrentBalance = CurrentBalance + @Amount, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryCashAccountId = @PoultryCashAccountId AND FarmId = @FarmId;

        DECLARE @bal DECIMAL(14,2) = (SELECT CurrentBalance FROM dbo.PoultryCashAccounts WHERE PoultryCashAccountId = @PoultryCashAccountId);

        INSERT INTO dbo.PoultryCashTransactions
            (FarmId, PoultryCashAccountId, TransactionDate, TransactionType, SourceType, SourceId,
             Amount, BalanceAfterTransaction, Description, CreatedBy, ApprovedBy, ApprovedAt)
        VALUES
            (@FarmId, @PoultryCashAccountId, SYSUTCDATETIME(), 'CashIn', 'Sale', @SaleId,
             @Amount, @bal, ISNULL(@Description, N'Sale receipt'), @CreatedBy, @CreatedBy, SYSUTCDATETIME());
    END

    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultrySaleCash_Sync TO [Techretainer];
    GRANT EXECUTE ON dbo.spSale_GetAll     TO [Techretainer];
    GRANT EXECUTE ON dbo.spSale_GetById    TO [Techretainer];
    GRANT EXECUTE ON dbo.spSale_GetByFlock TO [Techretainer];
END
GO

PRINT '137_SaleCashAccountLink: complete.';
GO

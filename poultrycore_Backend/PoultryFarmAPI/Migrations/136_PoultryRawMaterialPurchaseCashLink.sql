-- =============================================================================
-- Migration 136: pay a poultry raw-material purchase from a cash account.
-- =============================================================================
-- Adds dbo.PoultryRawMaterialPurchases.PoultryCashAccountId and a sync SP that
-- posts / reverses ONE CashOut on the chosen PoultryCashAccount for the amount
-- paid so far (SourceType='RawMaterialPurchase', SourceId=purchase id). The
-- service calls the sync after Insert/Update/PayBalance and after Delete
-- (reverse-only). Cash is keyed to the PURCHASE (not the linked expense) so it
-- stays self-contained and never double-counts the linked dbo.Expense row.
--
-- GetAll uses SELECT p.* so the new column is returned automatically. Idempotent.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.PoultryRawMaterialPurchases', 'PoultryCashAccountId') IS NULL
BEGIN
    ALTER TABLE dbo.PoultryRawMaterialPurchases ADD PoultryCashAccountId INT NULL;
    PRINT '136: added dbo.PoultryRawMaterialPurchases.PoultryCashAccountId';
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialPurchaseCash_Sync
    @FarmId                       NVARCHAR(450),
    @PoultryRawMaterialPurchaseId INT,
    @PoultryCashAccountId         INT           = NULL,
    @SetAccount                   BIT           = 1,   -- 1: store the account on the row; 0: keep existing (paybalance/delete)
    @CreatedBy                    NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    IF (@SetAccount = 1)
        UPDATE dbo.PoultryRawMaterialPurchases
        SET    PoultryCashAccountId = @PoultryCashAccountId, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    -- Reverse any existing purchase cash tx (restore balances, then delete them).
    UPDATE a
    SET    a.CurrentBalance = a.CurrentBalance - t.Net, a.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryCashAccounts a
    INNER  JOIN (
        SELECT PoultryCashAccountId, SUM(Amount) AS Net
        FROM   dbo.PoultryCashTransactions
        WHERE  SourceType = 'RawMaterialPurchase' AND SourceId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId
        GROUP  BY PoultryCashAccountId
    ) t ON t.PoultryCashAccountId = a.PoultryCashAccountId
    WHERE  a.FarmId = @FarmId;

    DELETE FROM dbo.PoultryCashTransactions
    WHERE  SourceType = 'RawMaterialPurchase' AND SourceId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    -- Repost from the current row state (skipped if the row is gone, e.g. delete).
    DECLARE @Acct INT, @Amt DECIMAL(14,2), @Item NVARCHAR(150);
    SELECT @Acct = p.PoultryCashAccountId, @Amt = p.AmountPaid, @Item = i.ItemName
    FROM   dbo.PoultryRawMaterialPurchases p
    LEFT   JOIN dbo.PoultryRawMaterialItems i ON i.PoultryRawMaterialItemId = p.PoultryRawMaterialItemId
    WHERE  p.PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND p.FarmId = @FarmId;

    IF (@Acct IS NOT NULL AND @Amt > 0
        AND EXISTS (SELECT 1 FROM dbo.PoultryCashAccounts WHERE PoultryCashAccountId = @Acct AND FarmId = @FarmId))
    BEGIN
        UPDATE dbo.PoultryCashAccounts
        SET    CurrentBalance = CurrentBalance - @Amt, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryCashAccountId = @Acct AND FarmId = @FarmId;

        DECLARE @bal DECIMAL(14,2) = (SELECT CurrentBalance FROM dbo.PoultryCashAccounts WHERE PoultryCashAccountId = @Acct);

        INSERT INTO dbo.PoultryCashTransactions
            (FarmId, PoultryCashAccountId, TransactionDate, TransactionType, SourceType, SourceId,
             Amount, BalanceAfterTransaction, Description, CreatedBy, ApprovedBy, ApprovedAt)
        VALUES
            (@FarmId, @Acct, SYSUTCDATETIME(), 'CashOut', 'RawMaterialPurchase', @PoultryRawMaterialPurchaseId,
             -@Amt, @bal, CONCAT(N'Raw material purchase: ', ISNULL(@Item, N'item')), @CreatedBy, @CreatedBy, SYSUTCDATETIME());
    END

    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchaseCash_Sync TO [Techretainer];
END
GO

PRINT '136_PoultryRawMaterialPurchaseCashLink: complete.';
GO

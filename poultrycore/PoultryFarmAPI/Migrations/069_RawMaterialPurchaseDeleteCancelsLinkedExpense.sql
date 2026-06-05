/* =============================================================================
   069_RawMaterialPurchaseDeleteCancelsLinkedExpense.sql

   Prompt 2 Part 2 §1 — when a Raw Material Purchase is deleted, the linked
   WaterExpenses row (auto-created by spWaterRawMaterialPurchase_Insert in
   migration 068) must also be cancelled so the books reconcile.

   This migration:
     1. Rewrites spWaterRawMaterialPurchase_Delete to call
        spWaterRawMaterialPurchase_CancelLinkedExpense first, in the same
        transaction as the stock + row reversal.
     2. Grants EXECUTE on both the Delete SP and the helper to the runtime
        login `Techretainer` so the Farm API can call them at runtime (this
        was the missing GRANT that caused a permission error in dev).

   Idempotent: CREATE OR ALTER + IF EXISTS GRANT.
   ============================================================================= */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_Delete
    @WaterRawMaterialPurchaseId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Qty DECIMAL(14,3), @ItemId INT, @LinkedExpenseId INT;
    SELECT @Qty = Quantity, @ItemId = WaterRawMaterialItemId, @LinkedExpenseId = LinkedWaterExpenseId
    FROM   dbo.WaterRawMaterialPurchases
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @Qty IS NULL
    BEGIN RAISERROR('Purchase %d not found.', 16, 1, @WaterRawMaterialPurchaseId); RETURN; END

    DECLARE @CurrentStock DECIMAL(14,3) = (
        SELECT CurrentQuantity FROM dbo.WaterRawMaterialItems
        WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId);

    IF (@CurrentStock < @Qty)
    BEGIN
        DECLARE @Msg2 NVARCHAR(400) = CONCAT(
            N'Cannot delete: only ', CONVERT(NVARCHAR(40), @CurrentStock),
            N' units remain in stock but this purchase added ',
            CONVERT(NVARCHAR(40), @Qty),
            N'. Reverse usages first.');
        RAISERROR(@Msg2, 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    -- Cancel the linked expense (cash impact reversed) in the same txn.
    IF @LinkedExpenseId IS NOT NULL
    BEGIN
        EXEC dbo.spWaterRawMaterialPurchase_CancelLinkedExpense
            @WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId,
            @FarmId = @FarmId,
            @CancelledBy = NULL;
    END

    UPDATE dbo.WaterRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity - @Qty,
           UpdatedAt       = SYSUTCDATETIME()
    WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId;

    DELETE FROM dbo.WaterRawMaterialPurchases
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

-- Grant exec on the helper + Delete SP to BOTH the legacy app role AND the
-- runtime login. The role grant was missed for the helper in 068.
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'PoultryAppRole' AND type = 'R')
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Delete             TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_CancelLinkedExpense TO PoultryAppRole;
END
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'Techretainer')
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Delete             TO Techretainer;
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_CancelLinkedExpense TO Techretainer;
END
GO

PRINT '069_RawMaterialPurchaseDeleteCancelsLinkedExpense.sql complete.';
GO

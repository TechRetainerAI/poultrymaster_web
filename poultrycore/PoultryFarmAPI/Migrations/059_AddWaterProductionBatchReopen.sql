/* =============================================================================
   059_AddWaterProductionBatchReopen.sql

   James reported he can't fix a production batch after Approve. The original
   design intentionally locks Approved batches because spWaterProductionBatch_Approve
   posts a Restock stock txn — editing bags or costs after that would corrupt
   inventory.

   This migration adds a safe undo path: spWaterProductionBatch_Reopen reverses
   the stock movement, flips Status back to Draft, and clears the Approved
   fields so the existing edit UI takes over.

   Refuses to run if some of the produced bags have already been sold or
   adjusted out — otherwise stock would go negative and the books would lie.
   ============================================================================= */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProductionBatch_Reopen
    @WaterProductionBatchId INT,
    @FarmId                 NVARCHAR(450),
    @ReopenedBy             NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status       NVARCHAR(20),
            @ProductId    INT,
            @BagsProduced INT,
            @DamagedBags  INT,
            @BatchNo      NVARCHAR(60);

    SELECT @Status       = Status,
           @ProductId    = WaterProductId,
           @BagsProduced = BagsProduced,
           @DamagedBags  = DamagedBags,
           @BatchNo      = BatchNumber
    FROM   dbo.WaterProductionBatches
    WHERE  WaterProductionBatchId = @WaterProductionBatchId
       AND FarmId = @FarmId
       AND IsDeleted = 0;

    IF @Status IS NULL
    BEGIN RAISERROR('Production batch %d not found.', 16, 1, @WaterProductionBatchId); RETURN; END
    IF @Status <> 'Approved'
    BEGIN RAISERROR('Only Approved batches can be reopened. Current status: %s.', 16, 1, @Status); RETURN; END

    DECLARE @GoodBags INT = @BagsProduced - ISNULL(@DamagedBags, 0);
    IF (@GoodBags < 0) SET @GoodBags = 0;

    /* Safety check: refuse if reversing the +GoodBags Restock would push
       current stock for this product below zero. That means some of these
       bags have already been sold or adjusted out, so we can't unring the
       bell — the user should cancel those sales first.

       Quantity in WaterStockTransactions is signed: Restock/+, Sale/-, etc. */
    DECLARE @CurrentStock INT = ISNULL((
        SELECT SUM(Quantity) FROM dbo.WaterStockTransactions
        WHERE FarmId = @FarmId AND WaterProductId = @ProductId
    ), 0);

    IF @GoodBags > 0 AND @CurrentStock < @GoodBags
    BEGIN
        RAISERROR('Cannot reopen: only %d bags of this product remain in stock, but the batch added %d. Cancel related sales or adjust stock first.',
                  16, 1, @CurrentStock, @GoodBags);
        RETURN;
    END

    BEGIN TRANSACTION;

    /* Reverse the stock movement Approve created. Use 'Adjust' with a
       negative quantity so the audit trail makes the reversal obvious. */
    IF (@GoodBags > 0)
    BEGIN
        INSERT INTO dbo.WaterStockTransactions
            (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
        VALUES
            (@FarmId, @ProductId, 'Adjust', -@GoodBags, NULL, NULL,
             CONCAT('Reopen production batch ', @BatchNo), @ReopenedBy);
    END

    UPDATE dbo.WaterProductionBatches
    SET    Status      = 'Draft',
           ApprovedBy  = NULL,
           ApprovedAt  = NULL,
           UpdatedAt   = SYSUTCDATETIME()
    WHERE  WaterProductionBatchId = @WaterProductionBatchId
       AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT WaterProductionBatchId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.WaterProductionBatches
    WHERE  WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;
END
GO

/* Grant execute to the application login if it exists. The role naming
   follows the pattern used in 045_GrantExecuteOnWaterPhase3Sps.sql. */
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'PoultryAppRole' AND type = 'R')
BEGIN
    GRANT EXECUTE ON dbo.spWaterProductionBatch_Reopen TO PoultryAppRole;
END
GO

PRINT '059_AddWaterProductionBatchReopen.sql complete.';
GO

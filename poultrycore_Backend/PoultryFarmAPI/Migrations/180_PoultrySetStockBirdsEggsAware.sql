-- =============================================================================
-- 180_PoultrySetStockBirdsEggsAware.sql
-- Fix "Set to actual count" for poultry Birds & Eggs.
--
-- spPoultryProduct_GetAll (migration 150) does NOT show plain ledger sums for the
-- two special finished products:
--   * Birds stock = birds LEFT across flocks (ProductionRecords / flock qty) —
--     ledger-independent. A stock transaction cannot move it, so setting a bird
--     count here is rejected (correct it in the flock / production records).
--   * Eggs  stock = (produced - broken from ProductionRecords) + NON-production
--     ledger moves. A manual 'Adjustment' IS counted, so a stock-take works — but
--     the "current" must be computed the same way (179 wrongly summed ALL ledger
--     rows, including Production, giving a wrong delta).
-- Every other finished good stays a plain ledger sum.
--
-- This redefines spPoultryProduct_SetStock to compute the current the same way
-- migration 150 displays it. Idempotent (CREATE OR ALTER). Grants to Techretainer.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_SetStock
    @FarmId           NVARCHAR(450),
    @PoultryProductId INT,
    @TargetQuantity   DECIMAL(18,3),
    @Note             NVARCHAR(500) = NULL,
    @CreatedBy        NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IsBird BIT = 0, @IsEgg BIT = 0;
    SELECT @IsBird = CASE WHEN (ISNULL(IsBirdProduct,0) = 1 OR Name = N'Birds') THEN 1 ELSE 0 END,
           @IsEgg  = CASE WHEN (ISNULL(IsRawEggProduct,0) = 1 OR Name IN (N'Eggs', N'Chicken Eggs')) THEN 1 ELSE 0 END
    FROM   dbo.PoultryProducts
    WHERE  PoultryProductId = @PoultryProductId AND FarmId = @FarmId;

    IF @@ROWCOUNT = 0
    BEGIN RAISERROR('Product not found for this company.', 16, 1); RETURN; END

    IF @IsBird = 1
    BEGIN
        RAISERROR('Bird stock is worked out from the birds left in your flocks, so it cannot be set here. Correct it in the flock / production records (record mortality, or edit the flock).', 16, 1);
        RETURN;
    END

    -- Current stock exactly as spPoultryProduct_GetAll (migration 150) shows it.
    DECLARE @current DECIMAL(18,3);
    IF @IsEgg = 1
        SET @current =
              ISNULL((SELECT SUM(ISNULL(TotalProduction,0)) - SUM(ISNULL(BrokenEggs,0))
                      FROM dbo.ProductionRecords WHERE FarmId = @FarmId), 0)
            + ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                      WHERE t.PoultryProductId = @PoultryProductId AND t.FarmId = @FarmId
                        AND t.TxnType <> N'Production'), 0);
    ELSE
        SET @current = ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions
                               WHERE PoultryProductId = @PoultryProductId AND FarmId = @FarmId), 0);

    DECLARE @delta DECIMAL(18,3) = @TargetQuantity - @current;

    IF @delta <> 0
        INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, Note, CreatedBy)
        VALUES (@FarmId, @PoultryProductId, 'Adjustment', @delta, ISNULL(@Note, 'Stock-take correction'), @CreatedBy);

    -- Return the recomputed displayed stock (should equal @TargetQuantity).
    IF @IsEgg = 1
        SELECT ISNULL((SELECT SUM(ISNULL(TotalProduction,0)) - SUM(ISNULL(BrokenEggs,0))
                       FROM dbo.ProductionRecords WHERE FarmId = @FarmId), 0)
             + ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                       WHERE t.PoultryProductId = @PoultryProductId AND t.FarmId = @FarmId
                         AND t.TxnType <> N'Production'), 0) AS CurrentStock;
    ELSE
        SELECT ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions
                       WHERE PoultryProductId = @PoultryProductId AND FarmId = @FarmId), 0) AS CurrentStock;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryProduct_SetStock TO [Techretainer];
    PRINT '180: granted EXECUTE on spPoultryProduct_SetStock to Techretainer.';
END
GO

PRINT '180_PoultrySetStockBirdsEggsAware.sql complete.';
GO

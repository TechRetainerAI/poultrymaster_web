-- =============================================================================
-- Migration 150: finished stock for Birds & Eggs reflects what's actually LEFT
-- =============================================================================
-- Bug (James): the inventory's Bird/Egg stock started at 0 and only ever got
-- reduced (mortality, sales), so it went negative — it never counted the birds
-- already placed or the eggs already produced. Reconcile the two special
-- finished products to the same source of truth the Production Log / Closing
-- Report use (migration 143):
--   * Birds stock = SUM of birds LEFT across active+arrived flocks (latest
--     NoOfBirdsLeft per flock, default = placed qty, clamped [0, placed]).
--   * Eggs  stock = eggs produced - broken (ProductionRecords) + net of NON-
--     production egg stock moves (sales/adjustments). Ledger 'Production' rows
--     are excluded so under-posted ledger production can't drag it negative and
--     ProductionRecords isn't double-counted.
-- Every other finished good keeps the plain stock-ledger sum.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    -- The canonical bird / egg finished products for this farm.
    DECLARE @BirdId INT, @EggId INT;
    SELECT TOP 1 @BirdId = PoultryProductId FROM dbo.PoultryProducts
    WHERE FarmId = @FarmId AND (IsBirdProduct = 1 OR Name = N'Birds')
    ORDER BY IsBirdProduct DESC, PoultryProductId;
    SELECT TOP 1 @EggId = PoultryProductId FROM dbo.PoultryProducts
    WHERE FarmId = @FarmId AND (IsRawEggProduct = 1 OR Name IN (N'Eggs', N'Chicken Eggs'))
    ORDER BY IsRawEggProduct DESC, PoultryProductId;

    -- Birds left = latest NoOfBirdsLeft per active+arrived flock (default placed
    -- qty), clamped to [0, placed]. Mirrors migration 143 / the Production Log.
    DECLARE @BirdsLeft DECIMAL(18,3) = ISNULL((
        SELECT SUM(CASE
                     WHEN lr.NoOfBirdsLeft IS NULL          THEN f.Quantity
                     WHEN lr.NoOfBirdsLeft < 0              THEN 0
                     WHEN lr.NoOfBirdsLeft > f.Quantity     THEN f.Quantity
                     ELSE lr.NoOfBirdsLeft
                   END)
        FROM   dbo.Flock f
        OUTER  APPLY (
            SELECT TOP 1 pr.NoOfBirdsLeft
            FROM   dbo.ProductionRecords pr
            WHERE  pr.FarmId = @FarmId AND pr.FlockId = f.FlockId
            ORDER  BY pr.[Date] DESC
        ) lr
        WHERE  f.FarmId = @FarmId AND f.Active = 1 AND f.HasArrived = 1 AND ISNULL(f.IsDeleted,0) = 0), 0);

    -- Eggs produced - broken, from the log the farm actually uses.
    DECLARE @EggsProducedNet DECIMAL(18,3) = ISNULL((
        SELECT SUM(ISNULL(TotalProduction,0)) - SUM(ISNULL(BrokenEggs,0))
        FROM   dbo.ProductionRecords WHERE FarmId = @FarmId), 0);

    SELECT p.*,
        CAST(
            CASE
                WHEN @BirdId IS NOT NULL AND p.PoultryProductId = @BirdId THEN @BirdsLeft
                WHEN @EggId  IS NOT NULL AND p.PoultryProductId = @EggId  THEN
                    @EggsProducedNet
                    + ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                              WHERE t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId
                                AND t.TxnType <> N'Production'), 0)
                ELSE ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                             WHERE t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId), 0)
            END AS DECIMAL(18,3)) AS StockOnHand
    FROM   dbo.PoultryProducts p
    WHERE  p.FarmId = @FarmId
    ORDER  BY p.IsActive DESC, p.Name;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spPoultryProduct_GetAll TO [Techretainer];
GO

PRINT '150_PoultryFinishedStockReconcileBirdsEggs.sql complete.';
GO

-- =============================================================================
-- 182_ReconcileStockMatchDisplay.sql
-- Make "Recalculate product stock" (reconcile) show the SAME current stock the
-- inventory table displays, and a sensible in/out breakdown.
--
-- 178 summed the raw ledger, which is wrong for the special products:
--   * Poultry Birds  — stock = birds LEFT across flocks (migration 150).
--   * Poultry Eggs   — stock = (produced - broken) + non-production ledger (150).
--   * Water (sachet) — displayed stock = SUM(Quantity) (migration 092), not the
--                      base-unit sum 178 used.
-- Every other finished good stays a plain ledger sum. In - Out = Current for all.
--
-- Read-only. Idempotent (CREATE OR ALTER). Grants to Techretainer.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_ReconcileStock
    @FarmId           NVARCHAR(450),
    @PoultryProductId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BirdId INT, @EggId INT;
    SELECT TOP 1 @BirdId = PoultryProductId FROM dbo.PoultryProducts
    WHERE FarmId = @FarmId AND (ISNULL(IsBirdProduct,0) = 1 OR Name = N'Birds')
    ORDER BY IsBirdProduct DESC, PoultryProductId;
    SELECT TOP 1 @EggId = PoultryProductId FROM dbo.PoultryProducts
    WHERE FarmId = @FarmId AND (ISNULL(IsRawEggProduct,0) = 1 OR Name IN (N'Eggs', N'Chicken Eggs'))
    ORDER BY IsRawEggProduct DESC, PoultryProductId;

    -- Bird figures (flock-based, mirrors migration 150).
    DECLARE @BirdsPlaced DECIMAL(18,3) = ISNULL((
        SELECT SUM(f.Quantity) FROM dbo.Flock f
        WHERE f.FarmId = @FarmId AND f.Active = 1 AND f.HasArrived = 1 AND ISNULL(f.IsDeleted,0) = 0), 0);
    DECLARE @BirdsLeft DECIMAL(18,3) = ISNULL((
        SELECT SUM(CASE WHEN lr.NoOfBirdsLeft IS NULL      THEN f.Quantity
                        WHEN lr.NoOfBirdsLeft < 0          THEN 0
                        WHEN lr.NoOfBirdsLeft > f.Quantity THEN f.Quantity
                        ELSE lr.NoOfBirdsLeft END)
        FROM dbo.Flock f
        OUTER APPLY (SELECT TOP 1 pr.NoOfBirdsLeft FROM dbo.ProductionRecords pr
                     WHERE pr.FarmId = @FarmId AND pr.FlockId = f.FlockId ORDER BY pr.[Date] DESC) lr
        WHERE f.FarmId = @FarmId AND f.Active = 1 AND f.HasArrived = 1 AND ISNULL(f.IsDeleted,0) = 0), 0);

    -- Egg figures (Production Records).
    DECLARE @EggProduced DECIMAL(18,3) = ISNULL((SELECT SUM(ISNULL(TotalProduction,0)) FROM dbo.ProductionRecords WHERE FarmId = @FarmId), 0);
    DECLARE @EggBroken   DECIMAL(18,3) = ISNULL((SELECT SUM(ISNULL(BrokenEggs,0))      FROM dbo.ProductionRecords WHERE FarmId = @FarmId), 0);

    SELECT p.PoultryProductId,
           p.Name,
           CAST(CASE
                WHEN p.PoultryProductId = @BirdId THEN @BirdsPlaced
                WHEN p.PoultryProductId = @EggId  THEN @EggProduced
                     + ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                               WHERE t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId AND t.TxnType <> N'Production' AND t.Quantity > 0), 0)
                ELSE ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                             WHERE t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId AND t.Quantity > 0), 0)
           END AS DECIMAL(18,3)) AS StockIn,
           CAST(CASE
                WHEN p.PoultryProductId = @BirdId THEN @BirdsPlaced - @BirdsLeft
                WHEN p.PoultryProductId = @EggId  THEN @EggBroken
                     + ISNULL((SELECT SUM(-t.Quantity) FROM dbo.PoultryStockTransactions t
                               WHERE t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId AND t.TxnType <> N'Production' AND t.Quantity < 0), 0)
                ELSE ISNULL((SELECT SUM(-t.Quantity) FROM dbo.PoultryStockTransactions t
                             WHERE t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId AND t.Quantity < 0), 0)
           END AS DECIMAL(18,3)) AS StockOut,
           CAST(CASE
                WHEN p.PoultryProductId = @BirdId THEN @BirdsLeft
                WHEN p.PoultryProductId = @EggId  THEN (@EggProduced - @EggBroken)
                     + ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                               WHERE t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId AND t.TxnType <> N'Production'), 0)
                ELSE ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                             WHERE t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId), 0)
           END AS DECIMAL(18,3)) AS CurrentStock
    FROM   dbo.PoultryProducts p
    WHERE  p.FarmId = @FarmId AND (@PoultryProductId IS NULL OR p.PoultryProductId = @PoultryProductId)
    ORDER  BY p.Name;
END
GO

-- Water: match the displayed stock = SUM(Quantity) (migration 092), not base units.
CREATE OR ALTER PROCEDURE dbo.spWaterProduct_ReconcileStock
    @FarmId         NVARCHAR(450),
    @WaterProductId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.WaterProductId,
           p.Name,
           CAST(ISNULL(SUM(CASE WHEN st.Quantity > 0 THEN st.Quantity ELSE 0 END), 0) AS DECIMAL(18,3)) AS StockIn,
           CAST(ISNULL(SUM(CASE WHEN st.Quantity < 0 THEN -st.Quantity ELSE 0 END), 0) AS DECIMAL(18,3)) AS StockOut,
           CAST(ISNULL(SUM(CAST(st.Quantity AS DECIMAL(18,3))), 0) AS DECIMAL(18,3)) AS CurrentStock
    FROM   dbo.WaterProducts p
    LEFT JOIN dbo.WaterStockTransactions st
           ON st.WaterProductId = p.WaterProductId AND st.FarmId = p.FarmId
    WHERE  p.FarmId = @FarmId AND (@WaterProductId IS NULL OR p.WaterProductId = @WaterProductId)
    GROUP  BY p.WaterProductId, p.Name
    ORDER  BY p.Name;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryProduct_ReconcileStock TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterProduct_ReconcileStock   TO [Techretainer];
    PRINT '182: granted EXECUTE on reconcile SPs to Techretainer.';
END
GO

PRINT '182_ReconcileStockMatchDisplay.sql complete.';
GO

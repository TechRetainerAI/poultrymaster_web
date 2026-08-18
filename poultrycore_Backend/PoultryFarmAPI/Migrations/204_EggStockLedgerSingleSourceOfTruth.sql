-- =============================================================================
-- 204_EggStockLedgerSingleSourceOfTruth.sql
--
-- Problem
-- -------
-- /poultry-inventory's "In stock" for Eggs never matched /egg-tracker's "Eggs on
-- hand". Three separate causes:
--
--   1. Different saleable definition. Migration 198 made "saleable" mean
--      TotalProduction - Broken - Meaty - Soft - Lost and fixed the ledger writer
--      (spPoultryEggStock_SyncForProduction), but it never touched the three
--      procs that DISPLAY stock. spPoultryProduct_GetAll (150),
--      _SetStock (180) and _ReconcileStock (182) all kept re-deriving eggs from
--      ProductionRecords as TotalProduction - Broken, so inventory overstated by
--      SUM(Meaty + Soft + Lost).
--
--   2. Different outflow source. Inventory netted PoultryStockTransactions;
--      the Egg Tracker netted the Sale table plus EggInventoryAdjustment. Neither
--      saw the other's rows, so driver load-outs and manual stock entries moved
--      one screen and not the other.
--
--   3. Duplicate raw-egg products on a farm. The "which product is the egg" pick
--      is TOP 1, so a second IsRawEggProduct row stranded its stock on a separate
--      line that the egg formula never applied to.
--
-- Why eggs were special in the first place
-- ----------------------------------------
-- Migration 150 re-derived eggs from ProductionRecords because the ledger was
-- incomplete: production predating the ledger feature, and egg sales predating
-- migration 139, had no rows at all, so a plain SUM went negative. That is a data
-- gap, not a reason for a second formula.
--
-- Fix
-- ---
-- Close the data gap, then delete the special case. Eggs become an ordinary
-- ledger-backed finished good; only Birds keep a derived figure (flocks).
--
--   1. Merge duplicate raw-egg products into the canonical one.
--   2. Backfill every missing 'Production' row at the migration-198 definition.
--   3. Backfill every missing egg 'Sale' row (migration 139's convention).
--   4. spPoultryProduct_GetAll / _SetStock / _ReconcileStock: eggs = ledger sum.
--
-- Backfill scope is farms that ALREADY have a raw-egg product, so no farm
-- silently gains egg tracking it never had. Farms with egg production but no egg
-- product are left alone and must be onboarded deliberately.
--
-- Everything inserted is tagged CreatedBy = 'migration-204', so the data half is
-- reversible with a single DELETE. Idempotent: the backfills are delta-based and
-- converge; re-running is a no-op.
--
-- The frontend half lives in lib/utils/egg-ledger.ts (buildEggStockLedger now
-- takes the ledger's non-production moves) and app/egg-tracker/page.tsx.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 0. Canonical egg product per farm — the same TOP 1 rule every egg proc uses.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#EggFarm') IS NOT NULL DROP TABLE #EggFarm;
CREATE TABLE #EggFarm (FarmId NVARCHAR(450) PRIMARY KEY, EggId INT NOT NULL);

INSERT INTO #EggFarm (FarmId, EggId)
SELECT x.FarmId, x.PoultryProductId
FROM (
    SELECT p.FarmId, p.PoultryProductId,
           ROW_NUMBER() OVER (PARTITION BY p.FarmId
                              ORDER BY ISNULL(p.IsRawEggProduct,0) DESC, p.PoultryProductId) AS rn
    FROM   dbo.PoultryProducts p
    WHERE  ISNULL(p.IsRawEggProduct,0) = 1 OR p.Name IN (N'Eggs', N'Chicken Eggs')
) x
WHERE x.rn = 1;
GO

-- -----------------------------------------------------------------------------
-- 1. Merge duplicate raw-egg products into the canonical one.
-- -----------------------------------------------------------------------------
UPDATE t
SET    t.PoultryProductId = e.EggId
FROM   dbo.PoultryStockTransactions t
JOIN   #EggFarm e ON e.FarmId = t.FarmId
JOIN   dbo.PoultryProducts d ON d.PoultryProductId = t.PoultryProductId AND d.FarmId = t.FarmId
WHERE  d.PoultryProductId <> e.EggId
  AND  (ISNULL(d.IsRawEggProduct,0) = 1 OR d.Name IN (N'Eggs', N'Chicken Eggs'));

UPDATE d
SET    d.IsRawEggProduct = 0,
       d.IsActive        = 0,
       d.Notes           = ISNULL(NULLIF(d.Notes, N''), N'') + N' [merged into egg product by migration-204]',
       d.UpdatedDate     = SYSUTCDATETIME()
FROM   dbo.PoultryProducts d
JOIN   #EggFarm e ON e.FarmId = d.FarmId
WHERE  d.PoultryProductId <> e.EggId
  AND  (ISNULL(d.IsRawEggProduct,0) = 1 OR d.Name IN (N'Eggs', N'Chicken Eggs'));
GO

-- -----------------------------------------------------------------------------
-- 2. Backfill missing 'Production' rows at the migration-198 definition.
-- -----------------------------------------------------------------------------
INSERT INTO dbo.PoultryStockTransactions
       (FarmId, PoultryProductId, TxnType, Quantity, UnitCost, RelatedId, Note, CreatedDate, CreatedBy)
SELECT pr.FarmId, e.EggId, N'Production', d.Delta, NULL, pr.Id,
       N'Egg production (backfill)', CAST(pr.[Date] AS DATETIME2), N'migration-204'
FROM   dbo.ProductionRecords pr
JOIN   #EggFarm e ON e.FarmId = pr.FarmId
CROSS  APPLY (
    SELECT CAST(
             CASE WHEN ISNULL(pr.TotalProduction,0) - ISNULL(pr.BrokenEggs,0) - ISNULL(pr.MeatyEggs,0)
                       - ISNULL(pr.SoftEggs,0) - ISNULL(pr.LostEggs,0) < 0
                  THEN 0
                  ELSE ISNULL(pr.TotalProduction,0) - ISNULL(pr.BrokenEggs,0) - ISNULL(pr.MeatyEggs,0)
                       - ISNULL(pr.SoftEggs,0) - ISNULL(pr.LostEggs,0)
             END AS DECIMAL(18,3))
           - ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                     WHERE t.FarmId = pr.FarmId AND t.TxnType = N'Production' AND t.RelatedId = pr.Id), 0) AS Delta
) d
WHERE  d.Delta <> 0;
GO

-- -----------------------------------------------------------------------------
-- 3. Backfill missing egg 'Sale' rows (migration 139's convention).
-- -----------------------------------------------------------------------------
INSERT INTO dbo.PoultryStockTransactions
       (FarmId, PoultryProductId, TxnType, Quantity, UnitCost, RelatedId, Note, CreatedDate, CreatedBy)
SELECT s.FarmId, e.EggId, N'Sale', d.Delta, NULL, s.SaleId,
       N'Egg sale (backfill)', CAST(s.SaleDate AS DATETIME2), N'migration-204'
FROM   dbo.Sale s
JOIN   #EggFarm e ON e.FarmId = s.FarmId
CROSS  APPLY (
    SELECT -CAST(CASE WHEN ISNULL(s.Quantity,0) < 0 THEN 0 ELSE ISNULL(s.Quantity,0) END AS DECIMAL(18,3))
           - ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                     WHERE t.FarmId = s.FarmId AND t.TxnType = N'Sale' AND t.RelatedId = s.SaleId), 0) AS Delta
) d
WHERE  s.Product LIKE N'%egg%' AND d.Delta <> 0;
GO

DROP TABLE #EggFarm;
GO

-- -----------------------------------------------------------------------------
-- 4. Display procs: eggs are now an ordinary ledger-backed product.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    -- Birds are the only finished product whose stock is NOT the ledger: they are
    -- derived from the birds left in the flocks (migration 143 / the Production
    -- Log). Eggs used to be special too (migration 150) because the ledger was
    -- incomplete; this migration backfilled it, so they follow the ledger now and
    -- therefore agree with the Egg Tracker's "Eggs on hand".
    DECLARE @BirdId INT;
    SELECT TOP 1 @BirdId = PoultryProductId FROM dbo.PoultryProducts
    WHERE FarmId = @FarmId AND (IsBirdProduct = 1 OR Name = N'Birds')
    ORDER BY IsBirdProduct DESC, PoultryProductId;

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

    SELECT p.*,
        CAST(
            CASE
                WHEN @BirdId IS NOT NULL AND p.PoultryProductId = @BirdId THEN @BirdsLeft
                ELSE ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                             WHERE t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId), 0)
            END AS DECIMAL(18,3)) AS StockOnHand
    FROM   dbo.PoultryProducts p
    WHERE  p.FarmId = @FarmId
    ORDER  BY p.IsActive DESC, p.Name;
END
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

    DECLARE @IsBird BIT = 0;
    SELECT @IsBird = CASE WHEN ISNULL(p.IsBirdProduct,0) = 1 OR p.Name = N'Birds' THEN 1 ELSE 0 END
    FROM   dbo.PoultryProducts p
    WHERE  p.PoultryProductId = @PoultryProductId AND p.FarmId = @FarmId;

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR (N'Product not found for this company.', 16, 1);
        RETURN;
    END

    IF @IsBird = 1
    BEGIN
        RAISERROR (N'Bird stock is worked out from the birds left in your flocks, so it cannot be set here. Correct it in the flock / production records (record mortality, or edit the flock).', 16, 1);
        RETURN;
    END

    -- Current stock exactly as spPoultryProduct_GetAll shows it: the ledger sum
    -- (eggs included, now that the egg ledger is complete).
    DECLARE @Current DECIMAL(18,3) = ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                                             WHERE t.PoultryProductId = @PoultryProductId AND t.FarmId = @FarmId), 0);
    DECLARE @Delta DECIMAL(18,3) = @TargetQuantity - @Current;

    IF (@Delta <> 0)
        INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, Note, CreatedBy)
        VALUES (@FarmId, @PoultryProductId, N'Adjustment', @Delta, ISNULL(@Note, N'Stock-take correction'), @CreatedBy);

    SELECT ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                   WHERE t.PoultryProductId = @PoultryProductId AND t.FarmId = @FarmId), 0) AS CurrentStock;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_ReconcileStock
    @FarmId NVARCHAR(450), @PoultryProductId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BirdId INT;
    SELECT TOP 1 @BirdId = PoultryProductId FROM dbo.PoultryProducts
    WHERE FarmId = @FarmId AND (ISNULL(IsBirdProduct,0) = 1 OR Name = N'Birds')
    ORDER BY IsBirdProduct DESC, PoultryProductId;

    DECLARE @BirdsPlaced DECIMAL(18,3) = ISNULL((
        SELECT SUM(f.Quantity) FROM dbo.Flock f
        WHERE f.FarmId = @FarmId AND f.Active = 1 AND f.HasArrived = 1 AND ISNULL(f.IsDeleted,0) = 0), 0);

    DECLARE @BirdsLeft DECIMAL(18,3) = ISNULL((
        SELECT SUM(CASE WHEN lr.NoOfBirdsLeft IS NULL      THEN f.Quantity
                        WHEN lr.NoOfBirdsLeft < 0          THEN 0
                        WHEN lr.NoOfBirdsLeft > f.Quantity THEN f.Quantity
                        ELSE lr.NoOfBirdsLeft END)
        FROM dbo.Flock f
        OUTER APPLY (
            SELECT TOP 1 pr.NoOfBirdsLeft FROM dbo.ProductionRecords pr
            WHERE pr.FarmId = @FarmId AND pr.FlockId = f.FlockId
            ORDER BY pr.[Date] DESC
        ) lr
        WHERE f.FarmId = @FarmId AND f.Active = 1 AND f.HasArrived = 1 AND ISNULL(f.IsDeleted,0) = 0), 0);

    -- Eggs reconcile from the ledger like every other product.
    SELECT p.PoultryProductId,
           p.Name,
           CAST(CASE WHEN p.PoultryProductId = @BirdId THEN @BirdsPlaced
                     ELSE ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                                  WHERE t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId
                                    AND t.Quantity > 0), 0)
                END AS DECIMAL(18,3)) AS StockIn,
           CAST(CASE WHEN p.PoultryProductId = @BirdId THEN @BirdsPlaced - @BirdsLeft
                     ELSE ISNULL((SELECT SUM(-t.Quantity) FROM dbo.PoultryStockTransactions t
                                  WHERE t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId
                                    AND t.Quantity < 0), 0)
                END AS DECIMAL(18,3)) AS StockOut,
           CAST(CASE WHEN p.PoultryProductId = @BirdId THEN @BirdsLeft
                     ELSE ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                                  WHERE t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId), 0)
                END AS DECIMAL(18,3)) AS CurrentStock
    FROM   dbo.PoultryProducts p
    WHERE  p.FarmId = @FarmId AND (@PoultryProductId IS NULL OR p.PoultryProductId = @PoultryProductId)
    ORDER  BY p.Name;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryProduct_GetAll         TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProduct_SetStock       TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProduct_ReconcileStock TO [Techretainer];
END
GO

PRINT N'204_EggStockLedgerSingleSourceOfTruth.sql complete.';
GO

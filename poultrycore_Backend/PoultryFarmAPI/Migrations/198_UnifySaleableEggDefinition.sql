-- =============================================================================
-- 198_UnifySaleableEggDefinition.sql
--
-- Problem
-- -------
-- "Saleable eggs on hand" was computed four different ways:
--   1. /egg-tracker ledger (client-side)      : total - broken
--   2. spEggProduction_Insert  -> egg stock   : total - broken
--   3. spProductionRecord_Insert -> egg stock : total - broken - lost
--   4. spPoultryReport_EggStockBalance (124)  : total - broken - meaty - soft - lost
-- so the Egg Tracker, the poultry egg stock and the Egg Stock Balance report all
-- disagreed for the same farm, and the egg stock table itself was inconsistent
-- depending on which entry path created the record.
--
-- Decision: definition (4) wins - an egg is saleable only if it is not broken,
-- meaty, soft-shelled or lost. This matches the Egg Stock Balance report and the
-- weekly report's "Egg loss" figure, so no report changes are needed.
--
-- What this migration does
-- ------------------------
-- 1. Enforces the definition CENTRALLY in spPoultryEggStock_SyncForProduction.
--    Every writer (spEggProduction_Insert/_Update, spProductionRecord_Insert/
--    _Update, and batch posting via spProductionRecord_Insert) funnels through
--    this proc, so callers no longer need to agree - the proc recomputes the
--    authoritative figure from the stored row and ignores the caller's number.
--    This deliberately avoids re-issuing the two large *_Insert procs.
-- 2. Exposes MeatyEggs / SoftEggs / LostEggs on the spEggProduction_Get* procs
--    so the Egg Tracker can see (and deduct) them.
-- 3. Backfills existing egg stock so historical rows move to the new definition.
--
-- Idempotent: CREATE OR ALTER throughout; the backfill is delta-based and
-- converges (re-running it is a no-op).
-- =============================================================================

SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Central definition. Body as migration 179 (append-only delta reversal),
--    plus the authoritative recompute.
--
--    @GoodEggs is now advisory: when it is non-zero we override it with the
--    figure derived from the ProductionRecords row. When it is zero we honour it
--    verbatim, because zero is the reversal/delete signal used by
--    spProductionRecord_Delete and spEggProduction_Delete - recomputing there
--    would resurrect stock for a record that is being withdrawn.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryEggStock_SyncForProduction
    @FarmId NVARCHAR(450), @ProductionId INT, @GoodEggs INT, @UnitCost DECIMAL(14,4) = NULL, @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Authoritative saleable count: collected picks less every non-saleable
    -- category. Floored at 0 so an over-recorded loss cannot post negative
    -- production. Falls back to the caller's value if the row has gone.
    DECLARE @Target INT = ISNULL(@GoodEggs, 0);
    IF (@Target <> 0)
    BEGIN
        DECLARE @Calc INT = (
            SELECT CASE WHEN x.Saleable < 0 THEN 0 ELSE x.Saleable END
            FROM (
                SELECT ISNULL(TotalProduction, 0)
                     - ISNULL(BrokenEggs, 0)
                     - ISNULL(MeatyEggs, 0)
                     - ISNULL(SoftEggs, 0)
                     - ISNULL(LostEggs, 0) AS Saleable
                FROM dbo.ProductionRecords
                WHERE Id = @ProductionId AND FarmId = @FarmId
            ) x);
        IF (@Calc IS NOT NULL) SET @Target = @Calc;
    END

    DECLARE @Net DECIMAL(14,3) = ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions
        WHERE FarmId = @FarmId AND TxnType = 'Production' AND RelatedId = @ProductionId), 0);
    DECLARE @Delta DECIMAL(14,3) = @Target - @Net;
    IF (@Delta = 0) RETURN;

    DECLARE @egg INT;
    SELECT TOP 1 @egg = PoultryProductId FROM dbo.PoultryProducts
    WHERE  FarmId = @FarmId AND (IsRawEggProduct = 1 OR Name IN (N'Eggs', N'Chicken Eggs'))
    ORDER  BY IsRawEggProduct DESC, PoultryProductId;
    IF @egg IS NULL
    BEGIN
        INSERT INTO dbo.PoultryProducts (FarmId, Name, Unit, UnitPrice, ProductType, IsRawEggProduct, RequiresRecipeSetup)
        VALUES (@FarmId, N'Eggs', N'Crate', 0, 'FinishedGood', 1, 0);
        SET @egg = CAST(SCOPE_IDENTITY() AS INT);
    END

    -- Note keys off the CALLER's intent (@GoodEggs), not @Target: a production
    -- whose eggs were all broken legitimately targets 0 without being a reversal.
    INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, UnitCost, RelatedId, Note, CreatedBy)
    VALUES (@FarmId, @egg, 'Production', @Delta, @UnitCost, @ProductionId,
            CASE WHEN ISNULL(@GoodEggs,0) = 0 THEN N'Reversal of egg production' ELSE N'Egg production' END, @CreatedBy);
END
GO

-- -----------------------------------------------------------------------------
-- 2. Egg-production reads: surface the three loss columns the Egg Tracker needs.
--    Bodies as migration 155_EggProductionFourthPick, plus MeatyEggs/SoftEggs/
--    LostEggs. TotalProduction stays the recomputed pick sum (unchanged) - the
--    client subtracts the losses so the ledger can show them as separate lines.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spEggProduction_GetById]
    @ProductionId INT,
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        Id AS ProductionId,
        ISNULL(FlockId, 0) AS FlockId,
        [Date] AS ProductionDate,
        ISNULL(EggCount, TotalProduction) AS EggCount,
        Production9AM,
        Production12PM,
        Production4PM,
        ISNULL(Production4thPick, 0) AS Production4thPick,
        BrokenEggs,
        ISNULL(MeatyEggs, 0) AS MeatyEggs,
        ISNULL(SoftEggs, 0)  AS SoftEggs,
        ISNULL(LostEggs, 0)  AS LostEggs,
        Notes,
        EggGrade,
        ISNULL(UserId, CreatedBy) AS UserId,
        FarmId
    FROM [dbo].[ProductionRecords]
    WHERE Id = @ProductionId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spEggProduction_GetAll]
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        Id AS ProductionId,
        ISNULL(FlockId, 0) AS FlockId,
        [Date] AS ProductionDate,
        ISNULL(EggCount, TotalProduction) AS EggCount,
        Production9AM,
        Production12PM,
        Production4PM,
        ISNULL(Production4thPick, 0) AS Production4thPick,
        ISNULL(Production9AM, 0) + ISNULL(Production12PM, 0) + ISNULL(Production4PM, 0) + ISNULL(Production4thPick, 0) AS TotalProduction,
        BrokenEggs,
        ISNULL(MeatyEggs, 0) AS MeatyEggs,
        ISNULL(SoftEggs, 0)  AS SoftEggs,
        ISNULL(LostEggs, 0)  AS LostEggs,
        Notes,
        EggGrade,
        ISNULL(UserId, CreatedBy) AS UserId,
        FarmId
    FROM [dbo].[ProductionRecords]
    WHERE FarmId = @FarmId
    ORDER BY [Date] DESC, CreatedAt DESC;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spEggProduction_GetByFlock]
    @FlockId INT,
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        Id AS ProductionId,
        ISNULL(FlockId, 0) AS FlockId,
        [Date] AS ProductionDate,
        ISNULL(EggCount, TotalProduction) AS EggCount,
        Production9AM,
        Production12PM,
        Production4PM,
        ISNULL(Production4thPick, 0) AS Production4thPick,
        ISNULL(Production9AM, 0) + ISNULL(Production12PM, 0) + ISNULL(Production4PM, 0) + ISNULL(Production4thPick, 0) AS TotalProduction,
        BrokenEggs,
        ISNULL(MeatyEggs, 0) AS MeatyEggs,
        ISNULL(SoftEggs, 0)  AS SoftEggs,
        ISNULL(LostEggs, 0)  AS LostEggs,
        Notes,
        EggGrade,
        FarmId
    FROM [dbo].[ProductionRecords]
    WHERE FarmId = @FarmId AND FlockId = @FlockId
    ORDER BY [Date] DESC, CreatedAt DESC;
END
GO

-- -----------------------------------------------------------------------------
-- 3. Backfill: move already-posted egg stock onto the new definition.
--
--    Without this, step 1 only affects records saved from now on - every
--    historical record keeps the stock it posted under the old (broken-only or
--    broken+lost) rule. Only records whose saleable figure actually moved are
--    touched, and only where meaty/soft/lost were genuinely recorded.
--
--    Records already fully reversed (net 0 with no live row) are skipped, since
--    they are absent from ProductionRecords.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.ProductionRecords','U') IS NOT NULL
   AND OBJECT_ID('dbo.PoultryStockTransactions','U') IS NOT NULL
   AND OBJECT_ID('dbo.PoultryProducts','U') IS NOT NULL
BEGIN
    DECLARE @Id INT, @Farm NVARCHAR(450), @Fixed INT = 0;

    DECLARE backfill CURSOR LOCAL FAST_FORWARD FOR
        SELECT pr.Id, pr.FarmId
        FROM dbo.ProductionRecords pr
        WHERE (ISNULL(pr.MeatyEggs,0) + ISNULL(pr.SoftEggs,0) + ISNULL(pr.LostEggs,0)) > 0
          AND EXISTS (SELECT 1 FROM dbo.PoultryStockTransactions t
                      WHERE t.FarmId = pr.FarmId AND t.TxnType = 'Production' AND t.RelatedId = pr.Id)
        ORDER BY pr.Id;

    OPEN backfill;
    FETCH NEXT FROM backfill INTO @Id, @Farm;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Pass a non-zero advisory value so the proc takes the recompute branch
        -- rather than reading it as a reversal; the real figure comes from the row.
        EXEC dbo.spPoultryEggStock_SyncForProduction
             @FarmId = @Farm, @ProductionId = @Id, @GoodEggs = 1,
             @UnitCost = NULL, @CreatedBy = N'migration-198';
        SET @Fixed = @Fixed + 1;
        FETCH NEXT FROM backfill INTO @Id, @Farm;
    END
    CLOSE backfill; DEALLOCATE backfill;

    PRINT CONCAT(N'198: egg stock realigned for ', @Fixed, N' production record(s) carrying meaty/soft/lost eggs.');
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryEggStock_SyncForProduction TO [Techretainer];
    GRANT EXECUTE ON dbo.spEggProduction_GetById             TO [Techretainer];
    GRANT EXECUTE ON dbo.spEggProduction_GetAll              TO [Techretainer];
    GRANT EXECUTE ON dbo.spEggProduction_GetByFlock          TO [Techretainer];
    PRINT N'198: granted EXECUTE to Techretainer.';
END
GO

PRINT N'198_UnifySaleableEggDefinition.sql complete.';
GO

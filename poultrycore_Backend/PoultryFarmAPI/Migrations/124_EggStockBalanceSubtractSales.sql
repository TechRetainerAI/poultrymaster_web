-- =============================================================================
-- Migration 124: Egg Stock Balance must subtract egg sales.
-- =============================================================================
-- Additive, read-only, idempotent (CREATE OR ALTER). Bug fix: the egg stock
-- balance never deducted sold eggs (it assumed egg sales posted an
-- EggInventoryAdjustment, but the Sale flow does not create one), so selling
-- eggs left the on-hand balance unchanged.
--
-- Egg sales are stored on dbo.Sale with Quantity in EGGS (the sales form enters
-- crates × 30 + loose and saves the piece count) and Product containing "egg".
-- We now return the sold-egg quantity both before the range (reduces opening)
-- and within the range (reduces current), so the service can net them out.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryReport_EggStockBalance
    @FarmId     NVARCHAR(450),
    @StartDate  DATE,
    @EndDate    DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        -- Opening saleable eggs produced before the range
        ISNULL((SELECT SUM(CAST(TotalProduction AS BIGINT)
                           - CAST(ISNULL(BrokenEggs,0)+ISNULL(MeatyEggs,0)+ISNULL(SoftEggs,0)+ISNULL(LostEggs,0) AS BIGINT))
                FROM dbo.ProductionRecords
                WHERE FarmId=@FarmId AND [Date] < @StartDate),0) AS OpeningProducedSaleable,
        ISNULL((SELECT SUM(EggDelta) FROM dbo.EggInventoryAdjustment
                WHERE FarmId=@FarmId AND AdjustmentDate < @StartDate),0) AS OpeningAdjustments,
        -- Eggs sold before the range (reduces opening on-hand)
        ISNULL((SELECT SUM(CAST(Quantity AS BIGINT)) FROM dbo.Sale
                WHERE FarmId=@FarmId AND Product LIKE N'%egg%' AND SaleDate < @StartDate),0) AS OpeningSales,
        ISNULL((SELECT SUM(CAST(TotalProduction AS BIGINT)) FROM dbo.ProductionRecords
                WHERE FarmId=@FarmId AND [Date]>=@StartDate AND [Date]<=@EndDate),0) AS ProductionAdded,
        ISNULL((SELECT SUM(CAST(ISNULL(BrokenEggs,0)+ISNULL(MeatyEggs,0)+ISNULL(SoftEggs,0)+ISNULL(LostEggs,0) AS BIGINT))
                FROM dbo.ProductionRecords
                WHERE FarmId=@FarmId AND [Date]>=@StartDate AND [Date]<=@EndDate),0) AS BrokenInRange,
        ISNULL((SELECT SUM(EggDelta) FROM dbo.EggInventoryAdjustment
                WHERE FarmId=@FarmId AND AdjustmentDate>=@StartDate AND AdjustmentDate<DATEADD(DAY,1,@EndDate)),0) AS AdjustmentsInRange,
        -- Eggs sold within the range (reduces current on-hand)
        ISNULL((SELECT SUM(CAST(Quantity AS BIGINT)) FROM dbo.Sale
                WHERE FarmId=@FarmId AND Product LIKE N'%egg%' AND SaleDate>=@StartDate AND SaleDate<DATEADD(DAY,1,@EndDate)),0) AS SalesInRange;
END
GO

-- =============================================================================
-- GRANT EXECUTE on every spPoultryReport_* to the runtime login [Techretainer]
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    DECLARE @procName SYSNAME;
    DECLARE proc_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.procedures WHERE name LIKE 'spPoultryReport_%';
    OPEN proc_cursor;
    FETCH NEXT FROM proc_cursor INTO @procName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @grantSql NVARCHAR(MAX) =
            N'GRANT EXECUTE ON [dbo].' + QUOTENAME(@procName) + N' TO [Techretainer];';
        EXEC sp_executesql @grantSql;
        FETCH NEXT FROM proc_cursor INTO @procName;
    END;
    CLOSE proc_cursor;
    DEALLOCATE proc_cursor;
    PRINT '124: granted EXECUTE on spPoultryReport_* to Techretainer.';
END
GO

PRINT '124_EggStockBalanceSubtractSales: complete.';
GO

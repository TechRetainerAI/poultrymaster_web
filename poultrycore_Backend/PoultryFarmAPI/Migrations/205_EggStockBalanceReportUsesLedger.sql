-- =============================================================================
-- 205_EggStockBalanceReportUsesLedger.sql
--
-- Problem
-- -------
-- Migration 204 made PoultryStockTransactions the single source of truth for egg
-- stock, so /poultry-inventory and /egg-tracker finally agreed. The Egg Stock
-- Balance report was the last figure still disagreeing: it took adjustments ONLY
-- from EggInventoryAdjustment, so it never saw the stock-ledger moves — driver
-- load-outs, deliveries, restocks, and the Set stock / Reconcile corrections made
-- from /poultry-inventory.
--
-- Measured before this migration (full history):
--   farm b55bf33e : report 22,137  vs  inventory / tracker 45,331
--   farm 7b95dafa : report 19,889  vs  inventory / tracker 19,589
--
-- Fix
-- ---
-- Return the egg product's non-production, non-sale ledger movements as two new
-- columns, split either side of the range, so the service can net them in.
-- Production and Sale ledger rows are deliberately EXCLUDED: the report already
-- counts those from ProductionRecords and Sale, and including them would
-- double-count.
--
-- Date basis: production and sales are ranged on their business date; ledger
-- moves are ranged on CreatedDate, the only date those rows carry.
--
-- The service half (PoultryAdvancedReportService.GetEggStockBalanceAsync) also
-- changes shape so the row ties out arithmetically:
--   Opening + Produced − Sold − Losses/adj. = Current
-- where Produced is now the GROSS collected count and Losses/adj. is
-- (broken + meaty + soft + lost) − net adjustments. Previously Produced was net
-- of losses while the losses column repeated them, so the row never added up.
--
-- Read-only and idempotent (CREATE OR ALTER).
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
                WHERE FarmId=@FarmId AND Product LIKE N'%egg%' AND SaleDate>=@StartDate AND SaleDate<DATEADD(DAY,1,@EndDate)),0) AS SalesInRange,
        -- Stock-ledger moves on the egg product that are neither production nor a
        -- sale (migration 204 made this ledger the source of truth for egg stock).
        ISNULL((SELECT SUM(CAST(t.Quantity AS BIGINT))
                FROM dbo.PoultryStockTransactions t
                JOIN dbo.PoultryProducts p ON p.PoultryProductId = t.PoultryProductId
                WHERE t.FarmId=@FarmId
                  AND (ISNULL(p.IsRawEggProduct,0)=1 OR p.Name IN (N'Eggs',N'Chicken Eggs'))
                  AND t.TxnType NOT IN (N'Production', N'Sale')
                  AND t.CreatedDate < @StartDate),0) AS OpeningStockMoves,
        ISNULL((SELECT SUM(CAST(t.Quantity AS BIGINT))
                FROM dbo.PoultryStockTransactions t
                JOIN dbo.PoultryProducts p ON p.PoultryProductId = t.PoultryProductId
                WHERE t.FarmId=@FarmId
                  AND (ISNULL(p.IsRawEggProduct,0)=1 OR p.Name IN (N'Eggs',N'Chicken Eggs'))
                  AND t.TxnType NOT IN (N'Production', N'Sale')
                  AND t.CreatedDate >= @StartDate AND t.CreatedDate < DATEADD(DAY,1,@EndDate)),0) AS StockMovesInRange;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spPoultryReport_EggStockBalance TO [Techretainer];
GO

PRINT N'205_EggStockBalanceReportUsesLedger.sql complete.';
GO

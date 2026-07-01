-- =============================================================================
-- Migration 123: split per-flock revenue into Egg / Bird / Other.
-- =============================================================================
-- Additive, read-only, idempotent (CREATE OR ALTER). Updates
-- spPoultryReport_ProfitLossByFlock so it splits each flock's sales revenue by
-- the sale's free-text Product (egg / bird / other) — the same buckets the
-- company-wide P&L uses — so the by-flock report can show a revenue breakdown.
-- Only the `rev` CTE and three new SELECT columns change; costs/eggs/filters are
-- untouched. Ends with the standard GRANT loop.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryReport_ProfitLossByFlock
    @FarmId               NVARCHAR(450),
    @StartDate            DATE,
    @EndDate              DATE,
    @FlockId              INT = NULL,
    @IncludeClosedFlocks  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH rev AS (
        SELECT FlockId,
            SUM(CASE WHEN Product LIKE N'%egg%' THEN TotalAmount ELSE 0 END) AS EggRevenue,
            SUM(CASE WHEN Product NOT LIKE N'%egg%' AND (
                     Product LIKE N'%bird%'  OR Product LIKE N'%layer%'  OR Product LIKE N'%broiler%'
                  OR Product LIKE N'%cockerel%' OR Product LIKE N'%chick%' OR Product LIKE N'%cock%'
                  OR Product LIKE N'%hen%'   OR Product LIKE N'%spent%'  OR Product LIKE N'%pullet%'
                  OR Product LIKE N'%fowl%'  OR Product LIKE N'%culled%')
                THEN TotalAmount ELSE 0 END) AS BirdRevenue,
            SUM(TotalAmount) AS Revenue
        FROM dbo.Sale
        WHERE FarmId=@FarmId AND SaleDate>=@StartDate AND SaleDate<DATEADD(DAY,1,@EndDate)
        GROUP BY FlockId
    ),
    eggs AS (
        SELECT FlockId, SUM(CAST(TotalProduction AS BIGINT)) AS Eggs
        FROM dbo.ProductionRecords
        WHERE FarmId=@FarmId AND [Date]>=@StartDate AND [Date]<=@EndDate
        GROUP BY FlockId
    ),
    cost AS (
        SELECT FlockId,
            SUM(CASE WHEN Category LIKE N'%feed%' THEN Amount ELSE 0 END) AS FeedCost,
            SUM(CASE WHEN Category LIKE N'%medic%' OR Category LIKE N'%vaccin%' OR Category LIKE N'%drug%' OR Category LIKE N'%health%' THEN Amount ELSE 0 END) AS MedCost,
            SUM(CASE WHEN Category LIKE N'%labo%' OR Category LIKE N'%salary%' OR Category LIKE N'%wage%' OR Category LIKE N'%payroll%' THEN Amount ELSE 0 END) AS LaborCost,
            SUM(CASE WHEN Category LIKE N'%feed%' OR Category LIKE N'%medic%' OR Category LIKE N'%vaccin%' OR Category LIKE N'%drug%' OR Category LIKE N'%health%' OR Category LIKE N'%labo%' OR Category LIKE N'%salary%' OR Category LIKE N'%wage%' OR Category LIKE N'%payroll%' THEN 0 ELSE Amount END) AS OtherCost
        FROM dbo.Expense
        WHERE FarmId=TRY_CONVERT(UNIQUEIDENTIFIER,@FarmId) AND ExpenseDate>=@StartDate AND ExpenseDate<DATEADD(DAY,1,@EndDate)
        GROUP BY FlockId
    )
    SELECT
        f.FlockId,
        f.Name                       AS FlockName,
        ISNULL(f.Quantity,0)         AS BirdsPlaced,
        ISNULL(rev.EggRevenue,0)                                                     AS EggRevenue,
        ISNULL(rev.BirdRevenue,0)                                                    AS BirdSalesRevenue,
        ISNULL(rev.Revenue,0) - ISNULL(rev.EggRevenue,0) - ISNULL(rev.BirdRevenue,0) AS OtherRevenue,
        ISNULL(rev.Revenue,0)        AS TotalRevenue,
        ISNULL(eggs.Eggs,0)          AS EggsProduced,
        ISNULL(cost.FeedCost,0)      AS FeedCost,
        ISNULL(cost.MedCost,0)       AS MedicineVaccineCost,
        ISNULL(cost.LaborCost,0)     AS LaborCost,
        ISNULL(cost.OtherCost,0)     AS OtherExpenses,
        CAST(ISNULL(f.Active,1) AS BIT) AS Active
    FROM dbo.Flock f
    LEFT JOIN rev  ON rev.FlockId  = f.FlockId
    LEFT JOIN eggs ON eggs.FlockId = f.FlockId
    LEFT JOIN cost ON cost.FlockId = f.FlockId
    WHERE f.FarmId = @FarmId
      AND (@FlockId IS NULL OR f.FlockId = @FlockId)
      AND (@IncludeClosedFlocks = 1 OR ISNULL(f.Active,1) = 1)
    ORDER BY f.Name;
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
    PRINT '123: granted EXECUTE on spPoultryReport_* to Techretainer.';
END
GO

PRINT '123_ProfitLossByFlockRevenueSplit: complete.';
GO

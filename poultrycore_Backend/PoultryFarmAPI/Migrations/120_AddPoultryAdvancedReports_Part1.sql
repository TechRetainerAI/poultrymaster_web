-- =============================================================================
-- Migration 120: Advanced Poultry Reports — Part 1 (reports 1-10)
-- =============================================================================
-- Brand-new, ADDITIVE stored procedures that power 20 new poultry-only reports
-- served under /api/poultry/reports/*. They are READ-ONLY and only SELECT from
-- existing poultry source tables — nothing here alters data or touches the
-- existing poultry / water / generic report procedures.
--
-- Each proc returns DETAIL ROWS; the C# service computes summary cards and
-- derived percentages (so the SQL stays simple and the maths lives in one
-- reusable place). spPoultryReport_FarmSummary additionally returns a second
-- result set with farm-wide totals.
--
-- FarmId note: dbo.Expense.FarmId is UNIQUEIDENTIFIER; every other poultry
-- table stores FarmId as NVARCHAR. We therefore compare Expense with
-- TRY_CONVERT(UNIQUEIDENTIFIER, @FarmId) and the rest with the raw NVARCHAR.
--
-- GRANT EXECUTE to [Techretainer] is in Part 2 (covers spPoultryReport_%).
-- Idempotent: CREATE OR ALTER, safe to re-run.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- 1. Farm Summary  (per-flock rows + farm-wide totals)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_FarmSummary
    @FarmId               NVARCHAR(450),
    @StartDate            DATE,
    @EndDate              DATE,
    @FlockId              INT = NULL,
    @IncludeClosedFlocks  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH pr AS (
        SELECT FlockId,
               SUM(CAST(TotalProduction AS BIGINT)) AS Eggs,
               SUM(CAST(ISNULL(BrokenEggs,0)+ISNULL(MeatyEggs,0)+ISNULL(SoftEggs,0)+ISNULL(LostEggs,0) AS BIGINT)) AS Broken,
               SUM(CAST(FeedKg AS DECIMAL(18,2))) AS Feed,
               SUM(Mortality) AS Deaths,
               SUM(CAST(NoOfBirdsLeft AS BIGINT)) AS BirdDays
        FROM dbo.ProductionRecords
        WHERE FarmId = @FarmId AND [Date] >= @StartDate AND [Date] <= @EndDate
        GROUP BY FlockId
    ),
    sa AS (
        SELECT FlockId, SUM(TotalAmount) AS Revenue,
               SUM(CASE WHEN ISNULL(Paid,1)=1 THEN TotalAmount ELSE 0 END) AS Paid
        FROM dbo.Sale
        WHERE FarmId = @FarmId AND SaleDate >= @StartDate AND SaleDate < DATEADD(DAY,1,@EndDate)
        GROUP BY FlockId
    ),
    ex AS (
        SELECT FlockId, SUM(Amount) AS Expenses
        FROM dbo.Expense
        WHERE FarmId = TRY_CONVERT(UNIQUEIDENTIFIER,@FarmId)
          AND ExpenseDate >= @StartDate AND ExpenseDate < DATEADD(DAY,1,@EndDate)
        GROUP BY FlockId
    ),
    lb AS (
        SELECT FlockId, NoOfBirdsLeft AS CurrentBirds,
               ROW_NUMBER() OVER (PARTITION BY FlockId ORDER BY [Date] DESC, Id DESC) AS rn
        FROM dbo.ProductionRecords
        WHERE FarmId = @FarmId AND [Date] <= @EndDate
    )
    SELECT
        f.FlockId,
        f.Name                                   AS FlockName,
        ISNULL(f.Quantity,0)                     AS StartingBirds,
        ISNULL(lb.CurrentBirds, ISNULL(f.Quantity,0)) AS CurrentBirds,
        ISNULL(pr.Eggs,0)                        AS EggsProduced,
        ISNULL(pr.Broken,0)                      AS BrokenRejectedEggs,
        ISNULL(pr.BirdDays,0)                    AS BirdDays,
        ISNULL(pr.Feed,0)                        AS FeedConsumedKg,
        ISNULL(pr.Deaths,0)                      AS Deaths,
        ISNULL(sa.Revenue,0)                     AS SalesRevenue,
        ISNULL(ex.Expenses,0)                    AS ExpensesAllocated,
        CAST(ISNULL(f.Active,1) AS BIT)          AS Active
    FROM dbo.Flock f
    LEFT JOIN pr ON pr.FlockId = f.FlockId
    LEFT JOIN sa ON sa.FlockId = f.FlockId
    LEFT JOIN ex ON ex.FlockId = f.FlockId
    LEFT JOIN lb ON lb.FlockId = f.FlockId AND lb.rn = 1
    WHERE f.FarmId = @FarmId
      AND (@FlockId IS NULL OR f.FlockId = @FlockId)
      AND (@IncludeClosedFlocks = 1 OR ISNULL(f.Active,1) = 1)
    ORDER BY f.Name;

    -- Farm-wide totals (includes records with no FlockId, and all sales/expenses)
    SELECT
        (SELECT ISNULL(SUM(CAST(TotalProduction AS BIGINT)),0) FROM dbo.ProductionRecords
            WHERE FarmId=@FarmId AND [Date]>=@StartDate AND [Date]<=@EndDate
              AND (@FlockId IS NULL OR FlockId=@FlockId)) AS TotalEggs,
        (SELECT ISNULL(SUM(CAST(ISNULL(BrokenEggs,0)+ISNULL(MeatyEggs,0)+ISNULL(SoftEggs,0)+ISNULL(LostEggs,0) AS BIGINT)),0)
            FROM dbo.ProductionRecords
            WHERE FarmId=@FarmId AND [Date]>=@StartDate AND [Date]<=@EndDate
              AND (@FlockId IS NULL OR FlockId=@FlockId)) AS BrokenRejectedEggs,
        (SELECT ISNULL(SUM(Mortality),0) FROM dbo.ProductionRecords
            WHERE FarmId=@FarmId AND [Date]>=@StartDate AND [Date]<=@EndDate
              AND (@FlockId IS NULL OR FlockId=@FlockId)) AS Deaths,
        (SELECT ISNULL(SUM(CAST(FeedKg AS DECIMAL(18,2))),0) FROM dbo.ProductionRecords
            WHERE FarmId=@FarmId AND [Date]>=@StartDate AND [Date]<=@EndDate
              AND (@FlockId IS NULL OR FlockId=@FlockId)) AS FeedConsumedKg,
        (SELECT ISNULL(SUM(TotalAmount),0) FROM dbo.Sale
            WHERE FarmId=@FarmId AND SaleDate>=@StartDate AND SaleDate<DATEADD(DAY,1,@EndDate)
              AND (@FlockId IS NULL OR FlockId=@FlockId)) AS SalesRevenue,
        (SELECT ISNULL(SUM(CASE WHEN ISNULL(Paid,1)=1 THEN TotalAmount ELSE 0 END),0) FROM dbo.Sale
            WHERE FarmId=@FarmId AND SaleDate>=@StartDate AND SaleDate<DATEADD(DAY,1,@EndDate)
              AND (@FlockId IS NULL OR FlockId=@FlockId)) AS CashCollected,
        (SELECT ISNULL(SUM(CASE WHEN ISNULL(Paid,1)=0 THEN TotalAmount ELSE 0 END),0) FROM dbo.Sale
            WHERE FarmId=@FarmId AND SaleDate>=@StartDate AND SaleDate<DATEADD(DAY,1,@EndDate)
              AND (@FlockId IS NULL OR FlockId=@FlockId)) AS CustomerReceivables,
        (SELECT ISNULL(SUM(Amount),0) FROM dbo.Expense
            WHERE FarmId=TRY_CONVERT(UNIQUEIDENTIFIER,@FarmId)
              AND ExpenseDate>=@StartDate AND ExpenseDate<DATEADD(DAY,1,@EndDate)
              AND (@FlockId IS NULL OR FlockId=@FlockId)) AS Expenses,
        (SELECT COUNT(*) FROM dbo.Flock WHERE FarmId=@FarmId AND ISNULL(Active,1)=1
              AND (@FlockId IS NULL OR FlockId=@FlockId)) AS ActiveFlocks;
END
GO

-- =============================================================================
-- 2. Daily Egg Production  (per date + flock)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_DailyEggProduction
    @FarmId     NVARCHAR(450),
    @StartDate  DATE,
    @EndDate    DATE,
    @FlockId    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        pr.[Date]                                          AS [Date],
        pr.FlockId                                         AS FlockId,
        ISNULL(f.Name, N'Unassigned')                      AS FlockName,
        MAX(pr.AgeInWeeks)                                 AS AgeInWeeks,
        SUM(pr.Production9AM)                               AS MorningEggs,
        SUM(pr.Production12PM)                              AS MiddayEggs,
        SUM(pr.Production4PM)                               AS EveningEggs,
        SUM(CAST(pr.TotalProduction AS BIGINT))            AS TotalEggs,
        SUM(CAST(ISNULL(pr.BrokenEggs,0)+ISNULL(pr.MeatyEggs,0)+ISNULL(pr.SoftEggs,0)+ISNULL(pr.LostEggs,0) AS BIGINT)) AS BrokenEggs,
        SUM(CAST(pr.NoOfBirdsLeft AS BIGINT))              AS BirdCount,
        MAX(pr.Notes)                                      AS Notes
    FROM dbo.ProductionRecords pr
    LEFT JOIN dbo.Flock f ON f.FlockId = pr.FlockId AND f.FarmId = pr.FarmId
    WHERE pr.FarmId = @FarmId AND pr.[Date] >= @StartDate AND pr.[Date] <= @EndDate
      AND (@FlockId IS NULL OR pr.FlockId = @FlockId)
    GROUP BY pr.[Date], pr.FlockId, f.Name
    ORDER BY pr.[Date] DESC, f.Name;
END
GO

-- =============================================================================
-- 3. Flock Production Summary  (per flock)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_FlockProductionSummary
    @FarmId               NVARCHAR(450),
    @StartDate            DATE,
    @EndDate              DATE,
    @FlockId              INT = NULL,
    @IncludeClosedFlocks  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH daily AS (
        SELECT FlockId, [Date],
               SUM(CAST(TotalProduction AS BIGINT)) AS DayEggs,
               SUM(CAST(NoOfBirdsLeft AS BIGINT))   AS DayBirds
        FROM dbo.ProductionRecords
        WHERE FarmId=@FarmId AND [Date]>=@StartDate AND [Date]<=@EndDate
        GROUP BY FlockId, [Date]
    ),
    agg AS (
        SELECT FlockId,
               SUM(DayEggs)  AS Eggs,
               MAX(DayEggs)  AS PeakDaily,
               COUNT(*)      AS Days,
               SUM(DayBirds) AS BirdDays
        FROM daily GROUP BY FlockId
    ),
    loss AS (
        SELECT FlockId,
               SUM(CAST(ISNULL(BrokenEggs,0)+ISNULL(MeatyEggs,0)+ISNULL(SoftEggs,0)+ISNULL(LostEggs,0) AS BIGINT)) AS Broken,
               SUM(CAST(FeedKg AS DECIMAL(18,2))) AS Feed,
               SUM(Mortality) AS Deaths
        FROM dbo.ProductionRecords
        WHERE FarmId=@FarmId AND [Date]>=@StartDate AND [Date]<=@EndDate
        GROUP BY FlockId
    ),
    lb AS (
        SELECT FlockId, NoOfBirdsLeft AS CurrentBirds,
               ROW_NUMBER() OVER (PARTITION BY FlockId ORDER BY [Date] DESC, Id DESC) AS rn
        FROM dbo.ProductionRecords
        WHERE FarmId=@FarmId AND [Date]<=@EndDate
    )
    SELECT
        f.FlockId,
        f.Name                                       AS FlockName,
        DATEDIFF(WEEK, f.StartDate, @EndDate)        AS FlockAgeWeeks,
        ISNULL(f.Quantity,0)                         AS BirdsPlaced,
        ISNULL(lb.CurrentBirds, ISNULL(f.Quantity,0)) AS CurrentBirds,
        ISNULL(agg.Eggs,0)                           AS TotalEggs,
        ISNULL(agg.PeakDaily,0)                      AS PeakDailyEggs,
        ISNULL(agg.Days,0)                           AS ProductionDays,
        ISNULL(agg.BirdDays,0)                       AS BirdDays,
        ISNULL(loss.Broken,0)                        AS BrokenEggs,
        ISNULL(loss.Feed,0)                          AS FeedConsumedKg,
        ISNULL(loss.Deaths,0)                        AS Deaths,
        CAST(ISNULL(f.Active,1) AS BIT)              AS Active
    FROM dbo.Flock f
    LEFT JOIN agg  ON agg.FlockId  = f.FlockId
    LEFT JOIN loss ON loss.FlockId = f.FlockId
    LEFT JOIN lb   ON lb.FlockId   = f.FlockId AND lb.rn = 1
    WHERE f.FarmId = @FarmId
      AND (@FlockId IS NULL OR f.FlockId = @FlockId)
      AND (@IncludeClosedFlocks = 1 OR ISNULL(f.Active,1) = 1)
    ORDER BY f.Name;
END
GO

-- =============================================================================
-- 4. Hen-Day Production  (per date + flock)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_HenDayProduction
    @FarmId     NVARCHAR(450),
    @StartDate  DATE,
    @EndDate    DATE,
    @FlockId    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        pr.[Date]                                AS [Date],
        pr.FlockId                               AS FlockId,
        ISNULL(f.Name, N'Unassigned')            AS FlockName,
        SUM(CAST(pr.NoOfBirdsLeft AS BIGINT))    AS LiveBirds,
        SUM(CAST(pr.TotalProduction AS BIGINT))  AS EggsProduced
    FROM dbo.ProductionRecords pr
    LEFT JOIN dbo.Flock f ON f.FlockId = pr.FlockId AND f.FarmId = pr.FarmId
    WHERE pr.FarmId = @FarmId AND pr.[Date] >= @StartDate AND pr.[Date] <= @EndDate
      AND (@FlockId IS NULL OR pr.FlockId = @FlockId)
    GROUP BY pr.[Date], pr.FlockId, f.Name
    ORDER BY pr.[Date] DESC, f.Name;
END
GO

-- =============================================================================
-- 5. Mortality  (per date + flock; ordered ASC per flock for cumulative calc)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_Mortality
    @FarmId     NVARCHAR(450),
    @StartDate  DATE,
    @EndDate    DATE,
    @FlockId    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        pr.[Date]                       AS [Date],
        pr.FlockId                      AS FlockId,
        ISNULL(f.Name, N'Unassigned')   AS FlockName,
        SUM(pr.NoOfBirds)               AS OpeningBirds,
        SUM(pr.Mortality)               AS Deaths,
        SUM(pr.NoOfBirdsLeft)           AS ClosingBirds,
        ISNULL(f.Quantity,0)            AS BirdsPlaced,
        MAX(pr.Notes)                   AS Notes
    FROM dbo.ProductionRecords pr
    LEFT JOIN dbo.Flock f ON f.FlockId = pr.FlockId AND f.FarmId = pr.FarmId
    WHERE pr.FarmId = @FarmId AND pr.[Date] >= @StartDate AND pr.[Date] <= @EndDate
      AND (@FlockId IS NULL OR pr.FlockId = @FlockId)
    GROUP BY pr.[Date], pr.FlockId, f.Name, f.Quantity
    ORDER BY pr.FlockId, pr.[Date];
END
GO

-- =============================================================================
-- 6. Birds on Hand  (per flock; point-in-time up to @EndDate)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_BirdsOnHand
    @FarmId               NVARCHAR(450),
    @EndDate              DATE,
    @FlockId              INT = NULL,
    @IncludeClosedFlocks  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        f.FlockId,
        f.Name                          AS FlockName,
        ISNULL(f.Quantity,0)            AS BirdsPlaced,
        ISNULL((SELECT SUM(pr.Mortality) FROM dbo.ProductionRecords pr
                WHERE pr.FarmId=f.FarmId AND pr.FlockId=f.FlockId AND pr.[Date]<=@EndDate),0) AS Deaths,
        (SELECT TOP 1 pr.NoOfBirdsLeft FROM dbo.ProductionRecords pr
            WHERE pr.FarmId=f.FarmId AND pr.FlockId=f.FlockId AND pr.[Date]<=@EndDate
            ORDER BY pr.[Date] DESC, pr.Id DESC) AS CurrentRecordedBirds
    FROM dbo.Flock f
    WHERE f.FarmId = @FarmId
      AND (@FlockId IS NULL OR f.FlockId = @FlockId)
      AND (@IncludeClosedFlocks = 1 OR ISNULL(f.Active,1) = 1)
    ORDER BY f.Name;
END
GO

-- =============================================================================
-- 7. Feed Usage  (per feed-usage record: date + flock + feed type)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_FeedUsage
    @FarmId     NVARCHAR(450),
    @StartDate  DATE,
    @EndDate    DATE,
    @FlockId    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        fu.UsageDate                          AS [Date],
        fu.FlockId                            AS FlockId,
        ISNULL(f.Name, N'Unassigned')         AS FlockName,
        fu.FeedType                           AS FeedType,
        SUM(CAST(fu.QuantityKg AS DECIMAL(18,2))) AS FeedConsumedKg,
        (SELECT SUM(CAST(pr.NoOfBirdsLeft AS BIGINT)) FROM dbo.ProductionRecords pr
            WHERE pr.FarmId=@FarmId AND pr.FlockId=fu.FlockId AND pr.[Date]=fu.UsageDate) AS LiveBirds,
        (SELECT SUM(CAST(pr.TotalProduction AS BIGINT)) FROM dbo.ProductionRecords pr
            WHERE pr.FarmId=@FarmId AND pr.FlockId=fu.FlockId AND pr.[Date]=fu.UsageDate) AS EggsProduced
    FROM dbo.FeedUsage fu
    LEFT JOIN dbo.Flock f ON f.FlockId = fu.FlockId AND f.FarmId = fu.FarmId
    WHERE fu.FarmId = @FarmId AND fu.UsageDate >= @StartDate AND fu.UsageDate <= @EndDate
      AND (@FlockId IS NULL OR fu.FlockId = @FlockId)
    GROUP BY fu.UsageDate, fu.FlockId, fu.FeedType, f.Name
    ORDER BY fu.UsageDate DESC, f.Name;
END
GO

-- =============================================================================
-- 8. Feed Inventory Balance  (per feed type — feed issued; combined stock in
--    summary, since per-item feed purchases are not itemised by type)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_FeedInventoryBalance
    @FarmId     NVARCHAR(450),
    @StartDate  DATE,
    @EndDate    DATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Per feed-type issued (consumption) within range.
    SELECT
        fu.FeedType                               AS FeedItem,
        SUM(CAST(fu.QuantityKg AS DECIMAL(18,2))) AS IssuedKg
    FROM dbo.FeedUsage fu
    WHERE fu.FarmId = @FarmId AND fu.UsageDate >= @StartDate AND fu.UsageDate <= @EndDate
    GROUP BY fu.FeedType
    ORDER BY fu.FeedType;

    -- Combined farm feed position (all-time up to @EndDate).
    SELECT
        ISNULL((SELECT SUM(CAST(FeedDeltaKg AS DECIMAL(18,4))) FROM dbo.FeedInventoryAdjustment
                WHERE FarmId=@FarmId AND AdjustmentDate < DATEADD(DAY,1,@EndDate)),0) AS NetAdjustmentsKg,
        ISNULL((SELECT SUM(CAST(QuantityKg AS DECIMAL(18,2))) FROM dbo.FeedUsage
                WHERE FarmId=@FarmId AND UsageDate <= @EndDate),0)                    AS TotalIssuedAllTimeKg,
        ISNULL((SELECT SUM(CAST(QuantityKg AS DECIMAL(18,2))) FROM dbo.FeedUsage
                WHERE FarmId=@FarmId AND UsageDate >= DATEADD(DAY,-29,@EndDate) AND UsageDate <= @EndDate),0) AS Last30IssuedKg;
END
GO

-- =============================================================================
-- 9. Feed Cost Per Egg  (per flock; feed cost approximated from Expense rows
--    in the "Feed" category allocated to the flock)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_FeedCostPerEgg
    @FarmId               NVARCHAR(450),
    @StartDate            DATE,
    @EndDate              DATE,
    @FlockId              INT = NULL,
    @IncludeClosedFlocks  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH pr AS (
        SELECT FlockId,
               SUM(CAST(TotalProduction AS BIGINT)) AS Eggs,
               SUM(CAST(FeedKg AS DECIMAL(18,2)))   AS Feed,
               SUM(CAST(NoOfBirdsLeft AS BIGINT))   AS BirdDays
        FROM dbo.ProductionRecords
        WHERE FarmId=@FarmId AND [Date]>=@StartDate AND [Date]<=@EndDate
        GROUP BY FlockId
    ),
    fc AS (
        SELECT FlockId, SUM(Amount) AS FeedCost
        FROM dbo.Expense
        WHERE FarmId = TRY_CONVERT(UNIQUEIDENTIFIER,@FarmId)
          AND ExpenseDate >= @StartDate AND ExpenseDate < DATEADD(DAY,1,@EndDate)
          AND Category LIKE N'%Feed%'
        GROUP BY FlockId
    )
    SELECT
        f.FlockId,
        f.Name                       AS FlockName,
        ISNULL(pr.Feed,0)            AS FeedConsumedKg,
        ISNULL(pr.Eggs,0)            AS EggsProduced,
        ISNULL(pr.BirdDays,0)        AS BirdDays,
        fc.FeedCost                  AS FeedCost
    FROM dbo.Flock f
    LEFT JOIN pr ON pr.FlockId = f.FlockId
    LEFT JOIN fc ON fc.FlockId = f.FlockId
    WHERE f.FarmId = @FarmId
      AND (@FlockId IS NULL OR f.FlockId = @FlockId)
      AND (@IncludeClosedFlocks = 1 OR ISNULL(f.Active,1) = 1)
    ORDER BY f.Name;
END
GO

-- =============================================================================
-- 10. Egg Stock Balance  (combined egg position; grade-level not separately
--     tracked through sales, so reported as one consolidated balance)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_EggStockBalance
    @FarmId     NVARCHAR(450),
    @StartDate  DATE,
    @EndDate    DATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Opening (before range), production added (in range), adjustments, and
    -- the all-time balance up to @EndDate.
    SELECT
        -- Opening saleable eggs produced before the range
        ISNULL((SELECT SUM(CAST(TotalProduction AS BIGINT)
                           - CAST(ISNULL(BrokenEggs,0)+ISNULL(MeatyEggs,0)+ISNULL(SoftEggs,0)+ISNULL(LostEggs,0) AS BIGINT))
                FROM dbo.ProductionRecords
                WHERE FarmId=@FarmId AND [Date] < @StartDate),0) AS OpeningProducedSaleable,
        ISNULL((SELECT SUM(EggDelta) FROM dbo.EggInventoryAdjustment
                WHERE FarmId=@FarmId AND AdjustmentDate < @StartDate),0) AS OpeningAdjustments,
        ISNULL((SELECT SUM(CAST(TotalProduction AS BIGINT)) FROM dbo.ProductionRecords
                WHERE FarmId=@FarmId AND [Date]>=@StartDate AND [Date]<=@EndDate),0) AS ProductionAdded,
        ISNULL((SELECT SUM(CAST(ISNULL(BrokenEggs,0)+ISNULL(MeatyEggs,0)+ISNULL(SoftEggs,0)+ISNULL(LostEggs,0) AS BIGINT))
                FROM dbo.ProductionRecords
                WHERE FarmId=@FarmId AND [Date]>=@StartDate AND [Date]<=@EndDate),0) AS BrokenInRange,
        ISNULL((SELECT SUM(EggDelta) FROM dbo.EggInventoryAdjustment
                WHERE FarmId=@FarmId AND AdjustmentDate>=@StartDate AND AdjustmentDate<DATEADD(DAY,1,@EndDate)),0) AS AdjustmentsInRange;
END
GO

PRINT '120_AddPoultryAdvancedReports_Part1: complete (reports 1-10).';
GO

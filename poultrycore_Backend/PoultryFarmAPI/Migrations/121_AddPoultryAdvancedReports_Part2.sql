-- =============================================================================
-- Migration 121: Advanced Poultry Reports — Part 2 (reports 11-20) + GRANTs
-- =============================================================================
-- Run AFTER 120_AddPoultryAdvancedReports_Part1.sql. Same rules: additive,
-- read-only, idempotent (CREATE OR ALTER). Ends by granting EXECUTE on every
-- spPoultryReport_* procedure to the runtime login [Techretainer].
--
-- Cost classification: poultry expenses are categorised by free-text Category.
-- We bucket them with LIKE rules (Feed / Medicine+Vaccine / Labour / Other) so
-- per-flock P&L and cost-per-egg can attribute costs without inventing data.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- 11. Egg Sales  (per sale)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_EggSales
    @FarmId        NVARCHAR(450),
    @StartDate     DATE,
    @EndDate       DATE,
    @FlockId       INT = NULL,
    @CustomerName  NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        CAST(s.SaleDate AS DATE)     AS [Date],
        s.SaleId                     AS SaleId,
        s.CustomerName               AS Customer,
        s.Product                    AS Product,
        s.Size                       AS Size,
        s.Quantity                   AS QuantitySold,
        s.UnitPrice                  AS UnitPrice,
        s.TotalAmount                AS TotalAmount,
        CAST(ISNULL(s.Paid,1) AS BIT) AS Paid,
        s.PaymentMethod              AS PaymentMethod,
        s.FlockId                    AS FlockId
    FROM dbo.Sale s
    WHERE s.FarmId = @FarmId
      AND s.SaleDate >= @StartDate AND s.SaleDate < DATEADD(DAY,1,@EndDate)
      AND (@FlockId IS NULL OR s.FlockId = @FlockId)
      AND (@CustomerName IS NULL OR s.CustomerName = @CustomerName)
    ORDER BY s.SaleDate DESC, s.SaleId DESC;
END
GO

-- =============================================================================
-- 12. Customer Balance  (per customer name, all-time up to @EndDate)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_CustomerBalance
    @FarmId        NVARCHAR(450),
    @EndDate       DATE,
    @CustomerName  NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        s.CustomerName                                                   AS Customer,
        SUM(s.TotalAmount)                                               AS TotalSales,
        SUM(CASE WHEN ISNULL(s.Paid,1)=1 THEN s.TotalAmount ELSE 0 END)  AS TotalPaid,
        MAX(s.SaleDate)                                                  AS LastSaleDate
    FROM dbo.Sale s
    WHERE s.FarmId = @FarmId
      AND s.SaleDate < DATEADD(DAY,1,@EndDate)
      AND s.CustomerName IS NOT NULL AND LTRIM(RTRIM(s.CustomerName)) <> N''
      AND (@CustomerName IS NULL OR s.CustomerName = @CustomerName)
    GROUP BY s.CustomerName
    ORDER BY (SUM(s.TotalAmount) - SUM(CASE WHEN ISNULL(s.Paid,1)=1 THEN s.TotalAmount ELSE 0 END)) DESC;
END
GO

-- =============================================================================
-- 13. Expense Summary  (per expense)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_ExpenseSummary
    @FarmId     NVARCHAR(450),
    @StartDate  DATE,
    @EndDate    DATE,
    @FlockId    INT = NULL,
    @Supplier   NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        CAST(e.ExpenseDate AS DATE)  AS [Date],
        e.ExpenseId                  AS ExpenseId,
        e.Category                   AS Category,
        e.Description                AS Description,
        e.Supplier                   AS Supplier,
        e.Amount                     AS Amount,
        e.PaymentMethod              AS PaymentMethod,
        e.FlockId                    AS FlockId,
        f.Name                       AS FlockName,
        e.UserId                     AS CreatedBy
    FROM dbo.Expense e
    LEFT JOIN dbo.Flock f ON f.FlockId = e.FlockId AND f.FarmId = @FarmId
    WHERE e.FarmId = TRY_CONVERT(UNIQUEIDENTIFIER,@FarmId)
      AND e.ExpenseDate >= @StartDate AND e.ExpenseDate < DATEADD(DAY,1,@EndDate)
      AND (@FlockId IS NULL OR e.FlockId = @FlockId)
      AND (@Supplier IS NULL OR e.Supplier = @Supplier)
    ORDER BY e.ExpenseDate DESC, e.ExpenseId DESC;
END
GO

-- =============================================================================
-- 14. Cash Movement  (sales-in as inflow, expenses as outflow)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_CashMovement
    @FarmId     NVARCHAR(450),
    @StartDate  DATE,
    @EndDate    DATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Opening cash = paid sales minus expenses BEFORE the range (best-effort,
    -- since poultry has no dedicated cash-account ledger).
    SELECT
        ISNULL((SELECT SUM(CASE WHEN ISNULL(Paid,1)=1 THEN TotalAmount ELSE 0 END) FROM dbo.Sale
                WHERE FarmId=@FarmId AND SaleDate < @StartDate),0)
        - ISNULL((SELECT SUM(Amount) FROM dbo.Expense
                WHERE FarmId=TRY_CONVERT(UNIQUEIDENTIFIER,@FarmId) AND ExpenseDate < @StartDate),0)
        AS OpeningCashBalance;

    -- Movement rows within the range.
    SELECT x.[Date], x.SourceType, x.Reference, x.Description, x.Inflow, x.Outflow, x.CreatedBy
    FROM (
        SELECT CAST(s.SaleDate AS DATE) AS [Date], N'Sales receipt' AS SourceType,
               CONCAT(N'Sale #', s.SaleId) AS Reference, s.Product AS Description,
               CASE WHEN ISNULL(s.Paid,1)=1 THEN s.TotalAmount ELSE 0 END AS Inflow,
               CAST(0 AS DECIMAL(18,2)) AS Outflow, s.UserId AS CreatedBy,
               s.SaleDate AS SortDate, 0 AS SortKind, s.SaleId AS SortId
        FROM dbo.Sale s
        WHERE s.FarmId=@FarmId AND s.SaleDate>=@StartDate AND s.SaleDate<DATEADD(DAY,1,@EndDate)
        UNION ALL
        SELECT CAST(e.ExpenseDate AS DATE), e.Category,
               CONCAT(N'Expense #', e.ExpenseId), e.Description,
               CAST(0 AS DECIMAL(18,2)), e.Amount, e.UserId,
               e.ExpenseDate, 1, e.ExpenseId
        FROM dbo.Expense e
        WHERE e.FarmId=TRY_CONVERT(UNIQUEIDENTIFIER,@FarmId)
          AND e.ExpenseDate>=@StartDate AND e.ExpenseDate<DATEADD(DAY,1,@EndDate)
    ) x
    ORDER BY x.SortDate, x.SortKind, x.SortId;
END
GO

-- =============================================================================
-- 15. Profit & Loss by Flock  (per flock; costs bucketed from Expense Category)
-- =============================================================================
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
        SELECT FlockId, SUM(TotalAmount) AS Revenue
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
-- 16. Cost Per Egg  (per flock; allocated cost / eggs)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_CostPerEgg
    @FarmId               NVARCHAR(450),
    @StartDate            DATE,
    @EndDate              DATE,
    @FlockId              INT = NULL,
    @IncludeClosedFlocks  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH eggs AS (
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
            SUM(Amount) AS TotalCost
        FROM dbo.Expense
        WHERE FarmId=TRY_CONVERT(UNIQUEIDENTIFIER,@FarmId) AND ExpenseDate>=@StartDate AND ExpenseDate<DATEADD(DAY,1,@EndDate)
        GROUP BY FlockId
    ),
    avgprice AS (
        SELECT FlockId, CASE WHEN SUM(Quantity)=0 THEN NULL ELSE SUM(TotalAmount)/NULLIF(SUM(Quantity),0) END AS AvgUnitPrice
        FROM dbo.Sale
        WHERE FarmId=@FarmId AND SaleDate>=@StartDate AND SaleDate<DATEADD(DAY,1,@EndDate)
        GROUP BY FlockId
    )
    SELECT
        f.FlockId,
        f.Name                       AS FlockName,
        ISNULL(eggs.Eggs,0)          AS EggsProduced,
        ISNULL(cost.FeedCost,0)      AS FeedCost,
        ISNULL(cost.MedCost,0)       AS MedicineVaccineCost,
        ISNULL(cost.LaborCost,0)     AS LaborCost,
        ISNULL(cost.TotalCost,0)     AS TotalAllocatedCost,
        avgprice.AvgUnitPrice        AS SellingPricePerUnit
    FROM dbo.Flock f
    LEFT JOIN eggs     ON eggs.FlockId     = f.FlockId
    LEFT JOIN cost     ON cost.FlockId     = f.FlockId
    LEFT JOIN avgprice ON avgprice.FlockId = f.FlockId
    WHERE f.FarmId = @FarmId
      AND (@FlockId IS NULL OR f.FlockId = @FlockId)
      AND (@IncludeClosedFlocks = 1 OR ISNULL(f.Active,1) = 1)
    ORDER BY f.Name;
END
GO

-- =============================================================================
-- 17. Vaccination Schedule  (recorded vaccinations from HealthRecord)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_VaccinationSchedule
    @FarmId     NVARCHAR(450),
    @StartDate  DATE,
    @EndDate    DATE,
    @FlockId    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        h.FlockId                    AS FlockId,
        ISNULL(f.Name, N'Unassigned') AS FlockName,
        h.Vaccination                AS Vaccine,
        CAST(h.RecordDate AS DATE)   AS ActualDate,
        h.UserId                     AS AdministeredBy,
        h.Notes                      AS Notes
    FROM dbo.HealthRecord h
    LEFT JOIN dbo.Flock f ON f.FlockId = h.FlockId AND f.FarmId = @FarmId
    WHERE h.FarmId = @FarmId
      AND h.RecordDate >= @StartDate AND h.RecordDate < DATEADD(DAY,1,@EndDate)
      AND h.Vaccination IS NOT NULL AND LTRIM(RTRIM(h.Vaccination)) <> N''
      AND (@FlockId IS NULL OR h.FlockId = @FlockId)
    ORDER BY h.RecordDate DESC, f.Name;
END
GO

-- =============================================================================
-- 18. Medicine Usage  (HealthRecord.Medication + ProductionRecords.Medication)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_MedicineUsage
    @FarmId     NVARCHAR(450),
    @StartDate  DATE,
    @EndDate    DATE,
    @FlockId    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT x.[Date], x.FlockId, ISNULL(f.Name, N'Unassigned') AS FlockName,
           x.Medicine, x.Notes, x.CreatedBy
    FROM (
        SELECT CAST(h.RecordDate AS DATE) AS [Date], h.FlockId AS FlockId,
               h.Medication AS Medicine, h.Notes AS Notes, h.UserId AS CreatedBy
        FROM dbo.HealthRecord h
        WHERE h.FarmId=@FarmId AND h.RecordDate>=@StartDate AND h.RecordDate<DATEADD(DAY,1,@EndDate)
          AND h.Medication IS NOT NULL AND LTRIM(RTRIM(h.Medication))<>N''
          AND (@FlockId IS NULL OR h.FlockId=@FlockId)
        UNION ALL
        SELECT pr.[Date], pr.FlockId, pr.Medication, pr.Notes, pr.UserId
        FROM dbo.ProductionRecords pr
        WHERE pr.FarmId=@FarmId AND pr.[Date]>=@StartDate AND pr.[Date]<=@EndDate
          AND pr.Medication IS NOT NULL AND LTRIM(RTRIM(pr.Medication))<>N''
          AND (@FlockId IS NULL OR pr.FlockId=@FlockId)
    ) x
    LEFT JOIN dbo.Flock f ON f.FlockId = x.FlockId AND f.FarmId = @FarmId
    ORDER BY x.[Date] DESC, f.Name;
END
GO

-- =============================================================================
-- 19. Missing Daily Records  (active flocks x dates; incomplete rows + summary)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_MissingDailyRecords
    @FarmId     NVARCHAR(450),
    @StartDate  DATE,
    @EndDate    DATE,
    @FlockId    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH d AS (
        SELECT @StartDate AS dt
        UNION ALL
        SELECT DATEADD(DAY,1,dt) FROM d WHERE dt < @EndDate
    ),
    fl AS (
        SELECT FlockId, Name, StartDate
        FROM dbo.Flock
        WHERE FarmId=@FarmId AND ISNULL(Active,1)=1
          AND (@FlockId IS NULL OR FlockId=@FlockId)
          AND StartDate <= @EndDate
    ),
    grid AS (
        SELECT d.dt AS [Date], fl.FlockId, fl.Name AS FlockName,
            CAST(CASE WHEN EXISTS(SELECT 1 FROM dbo.ProductionRecords pr WHERE pr.FarmId=@FarmId AND pr.FlockId=fl.FlockId AND pr.[Date]=d.dt) THEN 1 ELSE 0 END AS BIT) AS HasProductionRecord,
            CAST(CASE WHEN EXISTS(SELECT 1 FROM dbo.FeedUsage fu WHERE fu.FarmId=@FarmId AND fu.FlockId=fl.FlockId AND fu.UsageDate=d.dt)
                          OR EXISTS(SELECT 1 FROM dbo.ProductionRecords pr WHERE pr.FarmId=@FarmId AND pr.FlockId=fl.FlockId AND pr.[Date]=d.dt AND pr.FeedKg>0)
                      THEN 1 ELSE 0 END AS BIT) AS HasFeedUsage,
            CAST(CASE WHEN EXISTS(SELECT 1 FROM dbo.ProductionRecords pr WHERE pr.FarmId=@FarmId AND pr.FlockId=fl.FlockId AND pr.[Date]=d.dt) THEN 1 ELSE 0 END AS BIT) AS HasMortalityUpdate,
            CAST(CASE WHEN EXISTS(SELECT 1 FROM dbo.HealthRecord h WHERE h.FarmId=@FarmId AND h.FlockId=fl.FlockId AND CAST(h.RecordDate AS DATE)=d.dt) THEN 1 ELSE 0 END AS BIT) AS HasHealthNote
        FROM d CROSS JOIN fl
        WHERE d.dt >= fl.StartDate
    )
    SELECT [Date], FlockId, FlockName, HasProductionRecord, HasFeedUsage, HasMortalityUpdate, HasHealthNote
    FROM grid
    WHERE HasProductionRecord = 0 OR HasFeedUsage = 0
    ORDER BY [Date] DESC, FlockName
    OPTION (MAXRECURSION 0);

    -- Summary counts.
    ;WITH d AS (
        SELECT @StartDate AS dt
        UNION ALL
        SELECT DATEADD(DAY,1,dt) FROM d WHERE dt < @EndDate
    ),
    fl AS (
        SELECT FlockId, StartDate FROM dbo.Flock
        WHERE FarmId=@FarmId AND ISNULL(Active,1)=1
          AND (@FlockId IS NULL OR FlockId=@FlockId) AND StartDate <= @EndDate
    ),
    grid AS (
        SELECT
            CASE WHEN EXISTS(SELECT 1 FROM dbo.ProductionRecords pr WHERE pr.FarmId=@FarmId AND pr.FlockId=fl.FlockId AND pr.[Date]=d.dt) THEN 1 ELSE 0 END AS HasProd,
            CASE WHEN EXISTS(SELECT 1 FROM dbo.FeedUsage fu WHERE fu.FarmId=@FarmId AND fu.FlockId=fl.FlockId AND fu.UsageDate=d.dt)
                      OR EXISTS(SELECT 1 FROM dbo.ProductionRecords pr WHERE pr.FarmId=@FarmId AND pr.FlockId=fl.FlockId AND pr.[Date]=d.dt AND pr.FeedKg>0) THEN 1 ELSE 0 END AS HasFeed,
            CASE WHEN EXISTS(SELECT 1 FROM dbo.HealthRecord h WHERE h.FarmId=@FarmId AND h.FlockId=fl.FlockId AND CAST(h.RecordDate AS DATE)=d.dt) THEN 1 ELSE 0 END AS HasHealth
        FROM d CROSS JOIN fl
        WHERE d.dt >= fl.StartDate
    )
    SELECT
        (SELECT COUNT(*) FROM fl) AS ActiveFlocks,
        SUM(CASE WHEN HasProd=0 THEN 1 ELSE 0 END)  AS MissingProductionRecords,
        SUM(CASE WHEN HasFeed=0 THEN 1 ELSE 0 END)  AS MissingFeedRecords,
        SUM(CASE WHEN HasHealth=0 THEN 1 ELSE 0 END) AS MissingHealthRecords,
        SUM(CASE WHEN HasProd=1 AND HasFeed=1 THEN 1 ELSE 0 END) AS CompleteFlockDays
    FROM grid
    OPTION (MAXRECURSION 0);
END
GO

-- =============================================================================
-- 20. End-of-Flock  (per flock lifecycle, all-time up to @EndDate)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_EndOfFlock
    @FarmId               NVARCHAR(450),
    @EndDate              DATE,
    @FlockId              INT = NULL,
    @IncludeActiveFlocks  BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH daily AS (
        SELECT FlockId, [Date], SUM(CAST(TotalProduction AS BIGINT)) AS DayEggs
        FROM dbo.ProductionRecords
        WHERE FarmId=@FarmId AND [Date]<=@EndDate
        GROUP BY FlockId, [Date]
    ),
    pk AS (
        SELECT FlockId, MAX(DayEggs) AS PeakDaily, COUNT(*) AS Days, SUM(DayEggs) AS Eggs
        FROM daily GROUP BY FlockId
    ),
    pr AS (
        SELECT FlockId,
               SUM(CAST(ISNULL(BrokenEggs,0)+ISNULL(MeatyEggs,0)+ISNULL(SoftEggs,0)+ISNULL(LostEggs,0) AS BIGINT)) AS Broken,
               SUM(CAST(FeedKg AS DECIMAL(18,2))) AS Feed,
               SUM(Mortality) AS Deaths,
               SUM(CAST(NoOfBirdsLeft AS BIGINT)) AS BirdDays
        FROM dbo.ProductionRecords
        WHERE FarmId=@FarmId AND [Date]<=@EndDate
        GROUP BY FlockId
    ),
    lb AS (
        SELECT FlockId, NoOfBirdsLeft AS CurrentBirds, [Date] AS LastDate,
               ROW_NUMBER() OVER (PARTITION BY FlockId ORDER BY [Date] DESC, Id DESC) AS rn
        FROM dbo.ProductionRecords
        WHERE FarmId=@FarmId AND [Date]<=@EndDate
    ),
    rev AS (
        SELECT FlockId, SUM(TotalAmount) AS Revenue
        FROM dbo.Sale WHERE FarmId=@FarmId AND SaleDate<DATEADD(DAY,1,@EndDate)
        GROUP BY FlockId
    ),
    cost AS (
        SELECT FlockId,
            SUM(CASE WHEN Category LIKE N'%feed%' THEN Amount ELSE 0 END) AS FeedCost,
            SUM(CASE WHEN Category LIKE N'%medic%' OR Category LIKE N'%vaccin%' OR Category LIKE N'%drug%' OR Category LIKE N'%health%' THEN Amount ELSE 0 END) AS MedCost,
            SUM(CASE WHEN Category LIKE N'%labo%' OR Category LIKE N'%salary%' OR Category LIKE N'%wage%' OR Category LIKE N'%payroll%' THEN Amount ELSE 0 END) AS LaborCost,
            SUM(CASE WHEN Category LIKE N'%feed%' OR Category LIKE N'%medic%' OR Category LIKE N'%vaccin%' OR Category LIKE N'%drug%' OR Category LIKE N'%health%' OR Category LIKE N'%labo%' OR Category LIKE N'%salary%' OR Category LIKE N'%wage%' OR Category LIKE N'%payroll%' THEN 0 ELSE Amount END) AS OtherCost
        FROM dbo.Expense
        WHERE FarmId=TRY_CONVERT(UNIQUEIDENTIFIER,@FarmId) AND ExpenseDate<DATEADD(DAY,1,@EndDate)
        GROUP BY FlockId
    )
    SELECT
        f.FlockId,
        f.Name                       AS FlockName,
        f.StartDate                  AS PlacementDate,
        DATEDIFF(WEEK, f.StartDate, @EndDate) AS FlockAgeWeeks,
        ISNULL(f.Quantity,0)         AS BirdsPlaced,
        ISNULL(pr.Deaths,0)          AS TotalDeaths,
        ISNULL(lb.CurrentBirds, ISNULL(f.Quantity,0)) AS FinalBirdsRemaining,
        ISNULL(pk.Eggs,0)            AS TotalEggsProduced,
        ISNULL(pr.Broken,0)          AS BrokenRejectedEggs,
        ISNULL(pk.PeakDaily,0)       AS PeakProductionDay,
        ISNULL(pk.Days,0)            AS ProductionDays,
        ISNULL(pr.BirdDays,0)        AS BirdDays,
        ISNULL(pr.Feed,0)            AS TotalFeedConsumedKg,
        ISNULL(cost.FeedCost,0)      AS FeedCost,
        ISNULL(cost.MedCost,0)       AS MedicineVaccineCost,
        ISNULL(cost.LaborCost,0)     AS LaborCost,
        ISNULL(cost.OtherCost,0)     AS OtherCost,
        ISNULL(rev.Revenue,0)        AS TotalRevenue,
        CAST(ISNULL(f.Active,1) AS BIT) AS Active
    FROM dbo.Flock f
    LEFT JOIN pk   ON pk.FlockId   = f.FlockId
    LEFT JOIN pr   ON pr.FlockId   = f.FlockId
    LEFT JOIN lb   ON lb.FlockId   = f.FlockId AND lb.rn = 1
    LEFT JOIN rev  ON rev.FlockId  = f.FlockId
    LEFT JOIN cost ON cost.FlockId = f.FlockId
    WHERE f.FarmId = @FarmId
      AND (@FlockId IS NULL OR f.FlockId = @FlockId)
      AND (@IncludeActiveFlocks = 1 OR ISNULL(f.Active,1) = 0)
    ORDER BY f.Name;
END
GO

-- =============================================================================
-- GRANT EXECUTE on every spPoultryReport_* to the runtime login [Techretainer]
-- (the app login has EXECUTE-only access; it cannot SELECT base tables directly)
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
    PRINT '121: granted EXECUTE on spPoultryReport_* to Techretainer.';
END
GO

PRINT '121_AddPoultryAdvancedReports_Part2: complete (reports 11-20 + grants).';
GO

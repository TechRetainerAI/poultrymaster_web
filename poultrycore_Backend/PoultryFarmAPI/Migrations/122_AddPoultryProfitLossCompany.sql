-- =============================================================================
-- Migration 122: Company-wide Profit & Loss report (Profitability group).
-- =============================================================================
-- Additive, read-only, idempotent (CREATE OR ALTER). Adds ONE new procedure,
-- spPoultryReport_ProfitLoss, which aggregates ALL sales and ALL expenses for a
-- farm over a date range (not attributed per flock — that is the existing
-- spPoultryReport_ProfitLossByFlock). Revenue is split into Egg / Bird / Other
-- by the sale's free-text Product; expenses into Feed / Medicine+Vaccine /
-- Labour / Other by the free-text Category, using the same LIKE buckets as the
-- per-flock P&L so the two reports reconcile.
--
-- NOTE: dbo.Sale.FarmId is NVARCHAR; dbo.Expense.FarmId is UNIQUEIDENTIFIER
-- (matches every other spPoultryReport_* procedure).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryReport_ProfitLoss
    @FarmId     NVARCHAR(450),
    @StartDate  DATE,
    @EndDate    DATE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH rev AS (
        SELECT
            SUM(CASE WHEN Product LIKE N'%egg%' THEN TotalAmount ELSE 0 END) AS EggRevenue,
            SUM(CASE WHEN Product NOT LIKE N'%egg%' AND (
                     Product LIKE N'%bird%'  OR Product LIKE N'%layer%'  OR Product LIKE N'%broiler%'
                  OR Product LIKE N'%cockerel%' OR Product LIKE N'%chick%' OR Product LIKE N'%cock%'
                  OR Product LIKE N'%hen%'   OR Product LIKE N'%spent%'  OR Product LIKE N'%pullet%'
                  OR Product LIKE N'%fowl%'  OR Product LIKE N'%culled%')
                THEN TotalAmount ELSE 0 END) AS BirdRevenue,
            SUM(TotalAmount) AS TotalRevenue
        FROM dbo.Sale
        WHERE FarmId = @FarmId
          AND SaleDate >= @StartDate AND SaleDate < DATEADD(DAY,1,@EndDate)
    ),
    cost AS (
        SELECT
            SUM(CASE WHEN Category LIKE N'%feed%' THEN Amount ELSE 0 END) AS FeedCost,
            SUM(CASE WHEN Category LIKE N'%medic%' OR Category LIKE N'%vaccin%' OR Category LIKE N'%drug%' OR Category LIKE N'%health%' THEN Amount ELSE 0 END) AS MedCost,
            SUM(CASE WHEN Category LIKE N'%labo%' OR Category LIKE N'%salary%' OR Category LIKE N'%wage%' OR Category LIKE N'%payroll%' THEN Amount ELSE 0 END) AS LaborCost,
            SUM(CASE WHEN Category LIKE N'%feed%' OR Category LIKE N'%medic%' OR Category LIKE N'%vaccin%' OR Category LIKE N'%drug%' OR Category LIKE N'%health%' OR Category LIKE N'%labo%' OR Category LIKE N'%salary%' OR Category LIKE N'%wage%' OR Category LIKE N'%payroll%' THEN 0 ELSE Amount END) AS OtherCost,
            SUM(Amount) AS TotalExpenses
        FROM dbo.Expense
        WHERE FarmId = TRY_CONVERT(UNIQUEIDENTIFIER, @FarmId)
          AND ExpenseDate >= @StartDate AND ExpenseDate < DATEADD(DAY,1,@EndDate)
    )
    SELECT
        ISNULL(rev.EggRevenue,0)                                                                 AS EggRevenue,
        ISNULL(rev.BirdRevenue,0)                                                                AS BirdSalesRevenue,
        ISNULL(rev.TotalRevenue,0) - ISNULL(rev.EggRevenue,0) - ISNULL(rev.BirdRevenue,0)        AS OtherRevenue,
        ISNULL(rev.TotalRevenue,0)                                                               AS TotalRevenue,
        ISNULL(cost.FeedCost,0)                                                                  AS FeedCost,
        ISNULL(cost.MedCost,0)                                                                   AS MedicineVaccineCost,
        ISNULL(cost.LaborCost,0)                                                                 AS LaborCost,
        ISNULL(cost.OtherCost,0)                                                                 AS OtherExpenses,
        ISNULL(cost.TotalExpenses,0)                                                             AS TotalExpenses
    FROM rev CROSS JOIN cost;
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
    PRINT '122: granted EXECUTE on spPoultryReport_* to Techretainer.';
END
GO

PRINT '122_AddPoultryProfitLossCompany: complete (company-wide P&L).';
GO

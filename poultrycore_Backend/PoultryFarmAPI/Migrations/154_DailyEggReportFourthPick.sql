-- =============================================================================
-- Migration 154: Daily Egg Production report — expose the 4th pick
-- =============================================================================
-- The daily egg production report showed per-collection columns (1st/2nd/3rd
-- pick, formerly 9am/12pm/4pm). Add the 4th pick so the report matches the rest
-- of the app. TotalEggs already uses SUM(TotalProduction), which includes the
-- 4th pick (migration 152), so totals are unchanged by this — only the extra
-- per-pick column is added. Re-created verbatim from migration 120 with the new
-- SUM column. Idempotent (CREATE OR ALTER).
-- =============================================================================
IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000, N'Select your application database (not master). Aborting.', 1;
END
GO

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

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
        SUM(ISNULL(pr.Production4thPick,0))                AS FourthPickEggs,
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

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spPoultryReport_DailyEggProduction TO [Techretainer];
GO

PRINT N'154_DailyEggReportFourthPick.sql complete.';
GO

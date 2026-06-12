-- =============================================
-- Verify production deaths (mortality) vs app totals
-- Run in SSMS on your APPLICATION database (same as PoultryConn), NOT master.
--
-- Deaths = Mortality column (same value). App "Total Deaths": SUM(ProductionRecords.Mortality)
-- for rows whose FlockId belongs to flocks that are Active = 1 and StartDate (date) <= today.
--
-- Set @FarmId to your farm GUID (same as other verify scripts).
-- =============================================

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000,
        N'Select your application database in SSMS (not master), then run again.',
        1;
END
GO

DECLARE @FarmId NVARCHAR(450) = N'YOUR-FARM-GUID-HERE';

IF OBJECT_ID(N'dbo.ProductionRecords', N'U') IS NULL
BEGIN
    RAISERROR(N'dbo.ProductionRecords not found.', 16, 1);
    RETURN;
END

IF OBJECT_ID(N'dbo.Flock', N'U') IS NULL
BEGIN
    RAISERROR(N'dbo.Flock not found.', 16, 1);
    RETURN;
END

DECLARE @TodayDate DATE = CAST(GETDATE() AS DATE);

-- 1) All production mortality for this farm (every row — matches older "all flocks" UI if you still see that)
SELECT
    @FarmId AS FarmId,
    COUNT(*) AS ProductionRowCount,
    SUM(ISNULL(pr.Mortality, 0)) AS TotalMortality_AllRows_AllFlocks
FROM dbo.ProductionRecords pr
WHERE pr.FarmId = @FarmId;

-- 2) Same scope as current app: only flocks that are active and start date has passed
SELECT
    @FarmId AS FarmId,
    COUNT(*) AS ProductionRowCount_EligibleFlocksOnly,
    SUM(ISNULL(pr.Mortality, 0)) AS TotalMortality_EligibleFlocksOnly
FROM dbo.ProductionRecords pr
INNER JOIN dbo.Flock f
    ON f.FlockId = pr.FlockId
   AND f.FarmId = pr.FarmId
WHERE pr.FarmId = @FarmId
  AND ISNULL(f.Active, 1) = 1
  AND CAST(f.StartDate AS DATE) <= @TodayDate;

-- 3) Rows with NULL FlockId still carry mortality but are excluded from (2)
SELECT
    @FarmId AS FarmId,
    COUNT(*) AS RowsWithNullFlockId,
    SUM(ISNULL(pr.Mortality, 0)) AS Mortality_OnNullFlockRows
FROM dbo.ProductionRecords pr
WHERE pr.FarmId = @FarmId
  AND pr.FlockId IS NULL;

-- 4) Per-flock mortality (eligible flocks only) — use to audit 2,599 etc.
SELECT
    pr.FlockId,
    MAX(f.Name) AS FlockName,
    COUNT(*) AS LogRows,
    SUM(ISNULL(pr.Mortality, 0)) AS SumMortality
FROM dbo.ProductionRecords pr
INNER JOIN dbo.Flock f
    ON f.FlockId = pr.FlockId
   AND f.FarmId = pr.FarmId
WHERE pr.FarmId = @FarmId
  AND ISNULL(f.Active, 1) = 1
  AND CAST(f.StartDate AS DATE) <= @TodayDate
GROUP BY pr.FlockId
ORDER BY SumMortality DESC, pr.FlockId;

-- 5) Inactive or future-start flocks: mortality that (2) excludes
SELECT
    @FarmId AS FarmId,
    COUNT(*) AS ProductionRowCount,
    SUM(ISNULL(pr.Mortality, 0)) AS TotalMortality_InactiveOrNotStartedFlocks
FROM dbo.ProductionRecords pr
INNER JOIN dbo.Flock f
    ON f.FlockId = pr.FlockId
   AND f.FarmId = pr.FarmId
WHERE pr.FarmId = @FarmId
  AND NOT (
      ISNULL(f.Active, 1) = 1
      AND CAST(f.StartDate AS DATE) <= @TodayDate
  );

-- 6) Orphan production rows: FlockId set but no dbo.Flock row for (FlockId + same FarmId).
--    These are counted in (1) but not in (2)–(5). Explains 2599 vs 211 when (5) is zero.
SELECT
    @FarmId AS FarmId,
    COUNT(*) AS OrphanRowCount,
    SUM(ISNULL(pr.Mortality, 0)) AS Mortality_OnOrphanRows
FROM dbo.ProductionRecords pr
LEFT JOIN dbo.Flock f
    ON f.FlockId = pr.FlockId
   AND f.FarmId = pr.FarmId
WHERE pr.FarmId = @FarmId
  AND pr.FlockId IS NOT NULL
  AND f.FlockId IS NULL;

-- 7) Sample orphan rows (fix FlockId or restore flock; or delete bad history)
SELECT TOP (50)
    pr.Id,
    pr.Date,
    pr.FlockId,
    pr.Mortality,
    pr.FarmId AS ProductionFarmId
FROM dbo.ProductionRecords pr
LEFT JOIN dbo.Flock f
    ON f.FlockId = pr.FlockId
   AND f.FarmId = pr.FarmId
WHERE pr.FarmId = @FarmId
  AND pr.FlockId IS NOT NULL
  AND f.FlockId IS NULL
ORDER BY pr.Date DESC, pr.Id DESC;

-- 8) REAL DEATH DATA — every production log with Mortality > 0 (export this grid to Excel if needed)
SELECT
    pr.Id AS ProductionRecordId,
    pr.Date AS LogDate,
    pr.FlockId,
    fm.Name AS FlockName_ThisFarm,
    fb.Name AS FlockName_AnyFarm,
    fb.FarmId AS FlockRowFarmId,
    CASE
        WHEN pr.FlockId IS NULL THEN N'NO_FLOCK_ID'
        WHEN fm.FlockId IS NULL AND fb.FlockId IS NOT NULL THEN N'WRONG_FARM_OR_PR_FARM_MISMATCH'
        WHEN fm.FlockId IS NULL THEN N'ORPHAN_FLOCK_DELETED_OR_BAD_ID'
        WHEN ISNULL(fm.Active, 1) <> 1 OR CAST(fm.StartDate AS DATE) > @TodayDate THEN N'FLOCK_INACTIVE_OR_NOT_STARTED'
        ELSE N'ELIGIBLE'
    END AS DeathRowCategory,
    pr.Mortality AS DeathsThisEntry,
    pr.NoOfBirds,
    pr.NoOfBirdsLeft,
    pr.TotalProduction,
    pr.Medication,
    pr.Notes
FROM dbo.ProductionRecords pr
LEFT JOIN dbo.Flock fm
    ON fm.FlockId = pr.FlockId
   AND fm.FarmId = pr.FarmId
LEFT JOIN dbo.Flock fb
    ON fb.FlockId = pr.FlockId
WHERE pr.FarmId = @FarmId
  AND ISNULL(pr.Mortality, 0) > 0
ORDER BY pr.Date DESC, pr.Id DESC;

-- 9) Same register but zero deaths included (full audit trail); remove WHERE on Mortality to use as full log export
--    Uncomment to run:
/*
SELECT pr.Id, pr.Date, pr.FlockId, pr.Mortality, pr.NoOfBirds, pr.NoOfBirdsLeft
FROM dbo.ProductionRecords pr
WHERE pr.FarmId = @FarmId
ORDER BY pr.Date DESC, pr.Id DESC;
*/

PRINT N'Done. Result (8) is the line-by-line death register. Compare (2) with the app card.';

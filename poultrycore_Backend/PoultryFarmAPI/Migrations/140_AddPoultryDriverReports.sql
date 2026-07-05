-- =============================================================================
-- Migration 140: Poultry Driver reports
-- =============================================================================
-- Two reporting SPs mirroring the water driver reports:
--   * spPoultryReport_DriverReconciliation — per-driver accountability roll-up
--     (crates loaded/sold/returned/lost, expected vs accounted revenue,
--      shortages, delivery-run count) over a date range.
--   * spPoultryDriverCollection — detail-by-product + totals-by-driver for the
--     driver collection report (optional @PoultryDriverId filter).
--
-- Closing / P&L integration is AUTOMATIC: the driver module posts into
-- dbo.Sale / dbo.Expense / dbo.CashAdjustment / dbo.PoultryProductionLoss
-- (see migration 139), which the poultry daily-closing and P&L already read.
-- Idempotent (CREATE OR ALTER).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Per-driver accountability over a date range (based on approved returns).
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_DriverReconciliation
    @FarmId NVARCHAR(450), @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        d.PoultryDriverId,
        d.DriverName,
        COUNT(DISTINCT r.PoultryDriverReturnId)              AS DeliveryRuns,
        ISNULL(SUM(l.CratesLoaded), 0)                       AS TotalCratesLoaded,
        ISNULL(SUM(r.CratesSold), 0)                         AS TotalCratesSold,
        ISNULL(SUM(r.CratesReturned), 0)                     AS TotalCratesReturned,
        ISNULL(SUM(r.CratesDamaged + r.MissingCrates), 0)    AS TotalCratesLost,
        ISNULL(SUM(l.ExpectedCash), 0)                       AS ExpectedRevenue,
        ISNULL(SUM(r.TotalAccountedFor), 0)                  AS AccountedRevenue,
        ISNULL(SUM(r.ShortageAmount), 0)                     AS TotalShortage,
        ISNULL(SUM(r.OverageAmount), 0)                      AS TotalOverage
    FROM   dbo.PoultryDriverReturns r
    INNER  JOIN dbo.PoultryVehicleLoadings l ON l.PoultryVehicleLoadingId = r.PoultryVehicleLoadingId
    LEFT   JOIN dbo.PoultryDrivers d ON d.PoultryDriverId = l.PoultryDriverId
    WHERE  r.FarmId = @FarmId AND r.Status = 'Approved'
       AND (@FromDate IS NULL OR CAST(r.ReturnDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(r.ReturnDate AS DATE) <= @ToDate)
    GROUP  BY d.PoultryDriverId, d.DriverName
    ORDER  BY d.DriverName;
END
GO

-- Driver collection report: detail-by-product + totals-by-driver.
CREATE OR ALTER PROCEDURE dbo.spPoultryDriverCollection
    @FarmId NVARCHAR(450), @FromDate DATE = NULL, @ToDate DATE = NULL, @PoultryDriverId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Result 1: detail rows (one per return-item, or the return header when no items).
    ;WITH detail AS (
        SELECT
            l.PoultryDriverId,
            r.PoultryDriverReturnId,
            CAST(r.ReturnDate AS DATE) AS ReturnDate,
            p.Name                     AS ProductName,
            ri.CratesLoaded, ri.CratesSold, ri.CratesReturned, ri.CratesDamaged,
            ri.ExpectedSales           AS ExpectedAmount
        FROM   dbo.PoultryDriverReturns r
        INNER  JOIN dbo.PoultryVehicleLoadings l ON l.PoultryVehicleLoadingId = r.PoultryVehicleLoadingId
        INNER  JOIN dbo.PoultryDriverReturnItems ri ON ri.PoultryDriverReturnId = r.PoultryDriverReturnId
        INNER  JOIN dbo.PoultryProducts p ON p.PoultryProductId = ri.PoultryProductId
        WHERE  r.FarmId = @FarmId AND r.Status = 'Approved'
        UNION ALL
        SELECT
            l.PoultryDriverId,
            r.PoultryDriverReturnId,
            CAST(r.ReturnDate AS DATE) AS ReturnDate,
            p.Name                     AS ProductName,
            r.CratesSold + r.CratesReturned + r.CratesDamaged + r.MissingCrates AS CratesLoaded,
            r.CratesSold, r.CratesReturned, r.CratesDamaged,
            CAST(r.CratesSold * l.ExpectedSellingPricePerCrate AS DECIMAL(14,2)) AS ExpectedAmount
        FROM   dbo.PoultryDriverReturns r
        INNER  JOIN dbo.PoultryVehicleLoadings l ON l.PoultryVehicleLoadingId = r.PoultryVehicleLoadingId
        INNER  JOIN dbo.PoultryProducts p ON p.PoultryProductId = l.PoultryProductId
        WHERE  r.FarmId = @FarmId AND r.Status = 'Approved'
          AND  NOT EXISTS (SELECT 1 FROM dbo.PoultryDriverReturnItems ri WHERE ri.PoultryDriverReturnId = r.PoultryDriverReturnId)
    )
    SELECT d.PoultryDriverId, dr.DriverName, d.PoultryDriverReturnId, d.ReturnDate, d.ProductName,
           d.CratesLoaded, d.CratesSold, d.CratesReturned, d.CratesDamaged, d.ExpectedAmount
    FROM   detail d
    LEFT   JOIN dbo.PoultryDrivers dr ON dr.PoultryDriverId = d.PoultryDriverId
    WHERE  (@PoultryDriverId IS NULL OR d.PoultryDriverId = @PoultryDriverId)
       AND (@FromDate IS NULL OR d.ReturnDate >= @FromDate)
       AND (@ToDate   IS NULL OR d.ReturnDate <= @ToDate)
    ORDER  BY dr.DriverName, d.ReturnDate, d.PoultryDriverReturnId;

    -- Result 2: totals by driver.
    SELECT
        l.PoultryDriverId,
        dr.DriverName,
        COUNT(DISTINCT r.PoultryDriverReturnId)           AS DeliveryRuns,
        ISNULL(SUM(l.CratesLoaded), 0)                    AS TotalCratesLoaded,
        ISNULL(SUM(r.CratesSold), 0)                      AS TotalCratesSold,
        ISNULL(SUM(r.CratesReturned), 0)                  AS TotalCratesReturned,
        ISNULL(SUM(r.CratesDamaged + r.MissingCrates), 0) AS TotalCratesLost,
        ISNULL(SUM(l.ExpectedCash), 0)                    AS TotalExpected,
        ISNULL(SUM(r.TotalAccountedFor), 0)               AS TotalCollected,
        ISNULL(SUM(r.ShortageAmount), 0)                  AS TotalShortage
    FROM   dbo.PoultryDriverReturns r
    INNER  JOIN dbo.PoultryVehicleLoadings l ON l.PoultryVehicleLoadingId = r.PoultryVehicleLoadingId
    LEFT   JOIN dbo.PoultryDrivers dr ON dr.PoultryDriverId = l.PoultryDriverId
    WHERE  r.FarmId = @FarmId AND r.Status = 'Approved'
       AND (@PoultryDriverId IS NULL OR l.PoultryDriverId = @PoultryDriverId)
       AND (@FromDate IS NULL OR CAST(r.ReturnDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(r.ReturnDate AS DATE) <= @ToDate)
    GROUP  BY l.PoultryDriverId, dr.DriverName
    ORDER  BY dr.DriverName;
END
GO

PRINT '140_AddPoultryDriverReports.sql complete.';
GO

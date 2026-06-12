/* =============================================================================
   066_AddWaterDriverCollectionReport.sql

   Prompt 2 item #16: Driver Collection Report — owner-facing aggregation that
   surfaces driver accountability over a date range. Joins WaterVehicleLoadings
   (header + items) with WaterDriverReturns (header + items) so the report
   works for both legacy single-product and new multi-product runs.

   Two result sets:
     1. Per-driver per-product summary (the main report).
     2. Per-driver totals (for the page's top-of-list summary cards).
   ============================================================================= */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterReport_DriverCollection
    @FarmId        NVARCHAR(450),
    @FromDate      DATE,
    @ToDate        DATE,
    @WaterDriverId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- =========================================================================
    -- Result set 1: per-driver per-product rows.
    --
    -- Loaded comes from WaterVehicleLoadingItems (or the loading header for
    -- legacy single-product runs). Sold/returned/damaged + sales come from
    -- WaterDriverReturnItems (or the return header for legacy runs).
    -- =========================================================================
    ;WITH loaded AS (
        -- Multi-item loadings (migration 064 onward).
        SELECT l.FarmId, l.WaterDriverId, l.WaterVehicleId, l.WaterRouteId,
               li.WaterProductId, li.BagsLoaded, li.UnitPrice,
               l.LoadDate, l.WaterVehicleLoadingId
        FROM   dbo.WaterVehicleLoadingItems li
        INNER JOIN dbo.WaterVehicleLoadings l ON l.WaterVehicleLoadingId = li.WaterVehicleLoadingId
        WHERE  l.FarmId = @FarmId
          AND  l.IsDeleted = 0
          AND  CAST(l.LoadDate AS DATE) BETWEEN @FromDate AND @ToDate
          AND  (@WaterDriverId IS NULL OR l.WaterDriverId = @WaterDriverId)

        UNION ALL

        -- Legacy single-product loadings (pre-migration 064).
        SELECT l.FarmId, l.WaterDriverId, l.WaterVehicleId, l.WaterRouteId,
               l.WaterProductId, l.BagsLoaded, l.ExpectedSellingPricePerBag,
               l.LoadDate, l.WaterVehicleLoadingId
        FROM   dbo.WaterVehicleLoadings l
        WHERE  l.FarmId = @FarmId
          AND  l.IsDeleted = 0
          AND  CAST(l.LoadDate AS DATE) BETWEEN @FromDate AND @ToDate
          AND  (@WaterDriverId IS NULL OR l.WaterDriverId = @WaterDriverId)
          AND  NOT EXISTS (SELECT 1 FROM dbo.WaterVehicleLoadingItems li2
                            WHERE  li2.WaterVehicleLoadingId = l.WaterVehicleLoadingId)
    ),
    sold AS (
        -- Multi-item returns.
        SELECT r.WaterVehicleLoadingId, ri.WaterProductId,
               ri.BagsSold, ri.BagsReturned, ri.BagsDamaged,
               ri.UnitPrice AS ReturnUnitPrice,
               r.CashCollected, r.MoMoCollected, r.BankCollected,
               r.CreditSalesAmount, r.ShortageAmount, r.OverageAmount
        FROM   dbo.WaterDriverReturnItems ri
        INNER JOIN dbo.WaterDriverReturns r ON r.WaterDriverReturnId = ri.WaterDriverReturnId
        WHERE  r.FarmId = @FarmId
          AND  r.Status = 'Approved'

        UNION ALL

        -- Legacy single-product returns.
        SELECT r.WaterVehicleLoadingId, l.WaterProductId,
               r.BagsSold, r.BagsReturned, r.BagsDamaged,
               l.ExpectedSellingPricePerBag AS ReturnUnitPrice,
               r.CashCollected, r.MoMoCollected, r.BankCollected,
               r.CreditSalesAmount, r.ShortageAmount, r.OverageAmount
        FROM   dbo.WaterDriverReturns r
        INNER JOIN dbo.WaterVehicleLoadings l ON l.WaterVehicleLoadingId = r.WaterVehicleLoadingId
        WHERE  r.FarmId = @FarmId
          AND  r.Status = 'Approved'
          AND  NOT EXISTS (SELECT 1 FROM dbo.WaterDriverReturnItems ri2
                            WHERE  ri2.WaterDriverReturnId = r.WaterDriverReturnId)
    )
    SELECT  loaded.WaterDriverId,
            d.DriverName,
            loaded.WaterProductId,
            p.Name        AS ProductName,
            SUM(loaded.BagsLoaded)        AS BagsLoaded,
            SUM(ISNULL(sold.BagsSold, 0))     AS BagsSold,
            SUM(ISNULL(sold.BagsReturned, 0)) AS BagsReturned,
            SUM(ISNULL(sold.BagsDamaged, 0))  AS BagsDamaged,
            -- Expected = bags loaded × unit price at load time (cleanest contract).
            SUM(CAST(loaded.BagsLoaded AS DECIMAL(14,2)) * loaded.UnitPrice) AS ExpectedCash,
            -- Sales = bags sold × unit price at return time (may differ if the
            -- driver discounted; we honor the return-time price).
            SUM(CAST(ISNULL(sold.BagsSold, 0) AS DECIMAL(14,2)) * ISNULL(sold.ReturnUnitPrice, loaded.UnitPrice)) AS SalesValue
    FROM    loaded
    LEFT JOIN sold ON sold.WaterVehicleLoadingId = loaded.WaterVehicleLoadingId
                  AND sold.WaterProductId        = loaded.WaterProductId
    LEFT JOIN dbo.WaterDrivers  d ON d.WaterDriverId = loaded.WaterDriverId
    LEFT JOIN dbo.WaterProducts p ON p.WaterProductId = loaded.WaterProductId
    GROUP BY loaded.WaterDriverId, d.DriverName, loaded.WaterProductId, p.Name
    ORDER BY d.DriverName, p.Name;

    -- =========================================================================
    -- Result set 2: per-driver totals (cash + shortage roll-up, distinct trips).
    -- =========================================================================
    SELECT  l.WaterDriverId,
            d.DriverName,
            COUNT(DISTINCT l.WaterVehicleLoadingId) AS DeliveryRuns,
            COUNT(DISTINCT CASE WHEN l.Status = 'Reconciled' THEN l.WaterVehicleLoadingId END) AS ReconciledRuns,
            ISNULL(SUM(CASE WHEN r.Status = 'Approved' THEN r.CashCollected      END), 0) AS CashCollected,
            ISNULL(SUM(CASE WHEN r.Status = 'Approved' THEN r.MoMoCollected      END), 0) AS MoMoCollected,
            ISNULL(SUM(CASE WHEN r.Status = 'Approved' THEN r.BankCollected      END), 0) AS BankCollected,
            ISNULL(SUM(CASE WHEN r.Status = 'Approved' THEN r.CreditSalesAmount  END), 0) AS CreditSales,
            ISNULL(SUM(CASE WHEN r.Status = 'Approved' THEN r.ShortageAmount     END), 0) AS Shortage,
            ISNULL(SUM(CASE WHEN r.Status = 'Approved' THEN r.OverageAmount      END), 0) AS Overage
    FROM    dbo.WaterVehicleLoadings l
    LEFT JOIN dbo.WaterDriverReturns r ON r.WaterVehicleLoadingId = l.WaterVehicleLoadingId
    LEFT JOIN dbo.WaterDrivers d ON d.WaterDriverId = l.WaterDriverId
    WHERE   l.FarmId = @FarmId
      AND   l.IsDeleted = 0
      AND   CAST(l.LoadDate AS DATE) BETWEEN @FromDate AND @ToDate
      AND   (@WaterDriverId IS NULL OR l.WaterDriverId = @WaterDriverId)
    GROUP BY l.WaterDriverId, d.DriverName
    ORDER BY d.DriverName;
END
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'PoultryAppRole' AND type = 'R')
BEGIN
    GRANT EXECUTE ON dbo.spWaterReport_DriverCollection TO PoultryAppRole;
END
GO

PRINT '066_AddWaterDriverCollectionReport.sql complete.';
GO

-- =============================================================================
-- Migration 057: Water Company dashboard intelligence SPs
-- =============================================================================
-- Owner-intelligence dashboard cards (Water gap #7 from the forensic audit).
-- Two new aggregation SPs feed the new "where did my money go?" + "top customer"
-- tiles. Other intelligence cards (best/worst route, profit-per-bag) reuse the
-- existing spWaterReport_RouteProfitability + spWaterReport_PeriodPnL
-- (PeriodPnL already returns AvgProfitPerBag).
--
-- Column names verified against:
--   * migration 025 (WaterCustomers, WaterSales)
--   * migration 047 (WaterExpenseCategories, WaterExpenses)
--
-- All FarmId-scoped, idempotent (CREATE OR ALTER).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- spWaterReport_ExpenseByCategory
-- -----------------------------------------------------------------------------
-- Sums APPROVED expenses per category over a date range. Returns rows sorted
-- by TotalAmount DESC. Frontend uses the top N (~5) to render the "where did
-- my money go?" breakdown and computes the percentage share itself.
--
-- Only Status='Approved' is included — draft/submitted/rejected don't move
-- cash and shouldn't drive owner decisions.
--
-- Note: WaterExpenseCategories.Name is the column (not 'CategoryName').
-- HAVING SUM > 0 hides empty categories so the pie chart isn't full of zeros.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterReport_ExpenseByCategory
    @FarmId   NVARCHAR(450),
    @FromDate DATE,
    @ToDate   DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Start DATETIME2 = CAST(@FromDate AS DATETIME2);
    DECLARE @End   DATETIME2 = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME2));

    SELECT  c.WaterExpenseCategoryId,
            c.Name                          AS CategoryName,
            COUNT(e.WaterExpenseId)          AS ExpenseCount,
            ISNULL(SUM(e.Amount), 0)         AS TotalAmount
    FROM    dbo.WaterExpenseCategories c
    LEFT    JOIN dbo.WaterExpenses e
                  ON  e.WaterExpenseCategoryId = c.WaterExpenseCategoryId
                 AND  e.FarmId       = @FarmId
                 AND  e.IsDeleted    = 0
                 AND  e.Status       = 'Approved'
                 AND  e.ExpenseDate >= @Start
                 AND  e.ExpenseDate <  @End
    WHERE   c.FarmId    = @FarmId
       AND  c.IsDeleted = 0
    GROUP   BY c.WaterExpenseCategoryId, c.Name
    HAVING  ISNULL(SUM(e.Amount), 0) > 0
    ORDER   BY TotalAmount DESC, c.Name;
END
GO

-- -----------------------------------------------------------------------------
-- spWaterReport_TopCustomers
-- -----------------------------------------------------------------------------
-- Per-customer aggregate for a period: SalesCount, TotalSales, TotalPaid,
-- OutstandingBalance. Ordered by TotalSales DESC. Frontend can resort the
-- result set client-side to show "top by debt" without a second round-trip.
--
-- Cancelled sales are excluded ("Cancelled" or 'Cancelled' depending on
-- which Status value lives in WaterSales — migration 025 default is
-- 'Pending' | 'Paid' | 'PartiallyPaid' | 'Cancelled', so use 'Cancelled').
--
-- Note: WaterCustomers.Name (not 'CustomerName') and .ContactPhone
-- (not 'PhoneNumber'). No CustomerType column on this table.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterReport_TopCustomers
    @FarmId   NVARCHAR(450),
    @FromDate DATE,
    @ToDate   DATE,
    @TopN     INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Start DATETIME2 = CAST(@FromDate AS DATETIME2);
    DECLARE @End   DATETIME2 = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME2));

    IF (@TopN IS NULL OR @TopN <= 0) SET @TopN = 10;

    SELECT TOP (@TopN)
            c.WaterCustomerId,
            c.Name                                                   AS CustomerName,
            c.ContactPhone                                           AS PhoneNumber,
            COUNT(s.WaterSaleId)                                     AS SalesCount,
            ISNULL(SUM(s.TotalAmount), 0)                            AS TotalSales,
            ISNULL(SUM(s.AmountPaid), 0)                             AS TotalPaid,
            ISNULL(SUM(s.TotalAmount - s.AmountPaid), 0)             AS OutstandingBalance
    FROM    dbo.WaterCustomers c
    INNER   JOIN dbo.WaterSales s
                  ON  s.WaterCustomerId = c.WaterCustomerId
                 AND  s.FarmId   = @FarmId
                 AND  s.Status  <> 'Cancelled'
                 AND  s.SaleDate >= @Start AND s.SaleDate < @End
    WHERE   c.FarmId = @FarmId
    GROUP   BY c.WaterCustomerId, c.Name, c.ContactPhone
    ORDER   BY TotalSales DESC;
END
GO

-- =============================================================================
-- Grants
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON [dbo].[spWaterReport_ExpenseByCategory] TO [Techretainer];
    GRANT EXECUTE ON [dbo].[spWaterReport_TopCustomers]      TO [Techretainer];
    PRINT '057: granted EXECUTE on water dashboard intelligence SPs to Techretainer.';
END
GO

PRINT '057_AddWaterDashboardIntelligenceSps.sql complete.';
GO

-- 197_PoultryEggSalesUnpaidAccuracy.sql
--
-- Fixes the "Total unpaid" figure on the Poultry Egg Sales report (and the same
-- flaw on Customer Balance).
--
-- 1. PARTIAL PAYMENTS WERE IGNORED.
--    Migration 145 added dbo.Sale.AmountPaid + dbo.PoultryPayments so a sale can
--    be part-paid: it sets AmountPaid = sum(payments) and leaves Paid = 0 until
--    the balance clears. The report SPs predate 145 and only ever returned the
--    Paid bit, so the API treated every not-fully-paid sale as 100% outstanding.
--    A GHC 1,000 sale with GHC 600 already received was reported as GHC 1,000
--    unpaid. Total unpaid was overstated by the sum of all part-payments.
--
--    Both SPs now compute paid-to-date as:
--        CASE WHEN Paid = 1 THEN TotalAmount ELSE ISNULL(AmountPaid, 0) END
--    The Paid=1 branch matters: spSale_Insert (migration 139) does NOT populate
--    AmountPaid, so a newly-created fully-paid sale sits at Paid=1/AmountPaid=0.
--    Reading AmountPaid alone would report every new paid sale as unpaid.
--
-- 2. THE "EGG SALES" REPORT WAS NOT LIMITED TO EGG SALES.
--    dbo.Sale holds every poultry sale — the sales screen offers Fresh Eggs,
--    Chicken, Manure and Other — and migrations 122/123 already split the table
--    into egg vs bird revenue. spPoultryReport_EggSales had no product filter,
--    so bird and manure sales inflated its revenue, quantity and unpaid totals.
--    It now filters on Product LIKE '%egg%' — the same test the sales UI uses
--    (isEggsProduct) and the same one migrations 122/123 use for egg revenue.
--    A second result set reports what was excluded so the omission is visible
--    on the report rather than silent.

SET NOCOUNT ON;
GO

-- ---------------------------------------------------------------------------
-- Guard: AmountPaid arrived in 145. Add it where that migration hasn't run so
-- the procedures below always resolve. Idempotent, mirrors 145.
-- ---------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.Sale', N'U') IS NOT NULL AND COL_LENGTH(N'dbo.Sale', N'AmountPaid') IS NULL
BEGIN
    ALTER TABLE dbo.Sale ADD AmountPaid DECIMAL(14,2) NOT NULL CONSTRAINT DF_Sale_AmountPaid DEFAULT (0);
    PRINT N'197: added dbo.Sale.AmountPaid';
END
GO

-- A fully paid sale is paid in full (same backfill as 145; harmless to repeat).
IF OBJECT_ID(N'dbo.Sale', N'U') IS NOT NULL
    UPDATE dbo.Sale SET AmountPaid = TotalAmount
    WHERE ISNULL(Paid, 1) = 1 AND ISNULL(AmountPaid, 0) = 0;
GO

-- ---------------------------------------------------------------------------
-- 11. Egg Sales — egg products only, part-payments honoured.
-- ---------------------------------------------------------------------------
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
        -- Paid to date. See the header note on why Paid=1 short-circuits.
        CASE WHEN ISNULL(s.Paid,1) = 1 THEN s.TotalAmount
             ELSE ISNULL(s.AmountPaid, 0) END AS AmountPaid,
        s.PaymentMethod              AS PaymentMethod,
        s.FlockId                    AS FlockId
    FROM dbo.Sale s
    WHERE s.FarmId = @FarmId
      AND s.SaleDate >= @StartDate AND s.SaleDate < DATEADD(DAY,1,@EndDate)
      AND (@FlockId IS NULL OR s.FlockId = @FlockId)
      AND (@CustomerName IS NULL OR s.CustomerName = @CustomerName)
      AND ISNULL(s.Product, N'') LIKE N'%egg%'
    ORDER BY s.SaleDate DESC, s.SaleId DESC;

    -- Result set 2: the non-egg sales this report deliberately leaves out, so
    -- the API can say so on the report instead of quietly dropping them.
    SELECT
        COUNT(*)                        AS ExcludedCount,
        ISNULL(SUM(s.TotalAmount), 0)   AS ExcludedAmount
    FROM dbo.Sale s
    WHERE s.FarmId = @FarmId
      AND s.SaleDate >= @StartDate AND s.SaleDate < DATEADD(DAY,1,@EndDate)
      AND (@FlockId IS NULL OR s.FlockId = @FlockId)
      AND (@CustomerName IS NULL OR s.CustomerName = @CustomerName)
      AND ISNULL(s.Product, N'') NOT LIKE N'%egg%';
END
GO

-- ---------------------------------------------------------------------------
-- 12. Customer Balance — same part-payment fix. Note this SP is deliberately
--     all-time (no @StartDate): receivables are everything outstanding up to
--     @EndDate, unlike the period-scoped Egg Sales report.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryReport_CustomerBalance
    @FarmId        NVARCHAR(450),
    @EndDate       DATE,
    @CustomerName  NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        s.CustomerName                    AS Customer,
        SUM(s.TotalAmount)                AS TotalSales,
        SUM(CASE WHEN ISNULL(s.Paid,1) = 1 THEN s.TotalAmount
                 ELSE ISNULL(s.AmountPaid, 0) END) AS TotalPaid,
        MAX(s.SaleDate)                   AS LastSaleDate
    FROM dbo.Sale s
    WHERE s.FarmId = @FarmId
      AND s.SaleDate < DATEADD(DAY,1,@EndDate)
      AND s.CustomerName IS NOT NULL AND LTRIM(RTRIM(s.CustomerName)) <> N''
      AND (@CustomerName IS NULL OR s.CustomerName = @CustomerName)
    GROUP BY s.CustomerName
    ORDER BY (SUM(s.TotalAmount)
              - SUM(CASE WHEN ISNULL(s.Paid,1) = 1 THEN s.TotalAmount
                         ELSE ISNULL(s.AmountPaid, 0) END)) DESC;
END
GO

PRINT N'197: Egg Sales / Customer Balance now honour partial payments; Egg Sales is egg-products only.';
GO

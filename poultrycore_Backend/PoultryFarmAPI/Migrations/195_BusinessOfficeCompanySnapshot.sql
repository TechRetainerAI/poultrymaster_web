-- =============================================================================
-- Migration 195: today's numbers for the Business Office company cards
-- =============================================================================
-- /business-office lists every company the user belongs to, and each card shows
-- four metric tiles ("Production today", "Bags in stock", ...). Those tiles were
-- never wired to anything — the page rendered a literal em dash in each one, so
-- every company looked empty regardless of how much activity it had.
--
-- This is the query behind them: one row of four numbers for one company, picked
-- by company type. The page calls it once per card, in parallel.
--
-- WHY ONE SP AND NOT THE EXISTING DASHBOARD SPs
--   spWaterDashboard_Summary / spDashboard_GetSummary answer a different
--   question (a whole dashboard, one company, the ACTIVE one). The card needs
--   four cheap numbers for a company the user has not switched into, and the
--   Business Office shows several at once. Reusing them would mean 3-5 list
--   endpoints per card.
--
-- METRIC DEFINITIONS — these mirror what each company's own pages already show,
-- so a card and the dashboard behind it agree:
--
--   Water    ProductionToday  bags produced in batches dated @Today, excluding
--                             cancelled and deleted ones. Draft batches count:
--                             the bags exist whether or not approval has posted.
--            BagsInStock      SUM(WaterStockTransactions.Quantity) — the signed
--                             running stock, same figure spWaterDashboard_Summary
--                             calls TotalStockOnHand.
--            DriverReturns    how many driver returns were recorded today, i.e.
--                             how many drivers have reported back. A count, not
--                             a quantity — bags returned is a reconciliation
--                             detail, not a "did the round close" signal.
--            SalesToday       non-cancelled WaterSales dated today.
--
--   Poultry  EggsToday        SUM(ProductionRecords.TotalProduction) for @Today.
--            FeedStockKg      the feed ledger's balance: feed inventory IN,
--                             minus recorded usage, plus manual adjustments.
--                             Mirrors buildFeedStockLedger in
--                             lib/utils/feed-ledger.ts, unit conversion included
--                             — see the comment on that branch below.
--            MortalityToday   SUM(ProductionRecords.Mortality) for @Today.
--            SalesToday       SUM(Sale.TotalAmount) for @Today (table is
--                             dbo.Sale, singular — see migration 005).
--
--   Generic  SalesToday       non-cancelled, non-deleted GenericSales today.
--            ExpensesToday    APPROVED GenericExpenses today. Drafts are a
--                             request, not money out.
--            LowStockCount    stock-tracked active products at or below their
--                             minimum alert level.
--            CustomerDebt     SUM of positive GenericCustomers.CurrentBalance.
--
-- A company type only ever touches its own tables. That matters beyond tidiness:
-- prod skips migrations 025+ (see database/schema-sync/RUNBOOK.md), so the Water
-- and Generic tables do not exist there. SQL Server resolves names at execution,
-- not at CREATE, so the branches below stay dormant and this SP installs and
-- runs fine on a poultry-only database.
--
-- Read-only. One new SP, no schema, no data.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- @Today is the CALLER's date. The browser sends its own local day so a card
-- says "today" the way the person reading it means it; omitted, it falls back to
-- the server's UTC date, which is what the other dashboard SPs assume.
--
-- Every branch returns the same four columns. Unused metrics come back NULL, and
-- the card renders NULL as the em dash it used to hard-code — so a company type
-- with no snapshot support degrades to today's behaviour instead of showing 0,
-- which would read as "nothing happened".
CREATE OR ALTER PROCEDURE dbo.spBusinessOffice_CompanySnapshot
    @FarmId      NVARCHAR(450),
    @CompanyType NVARCHAR(30),
    @Today       DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF (@Today IS NULL) SET @Today = CAST(SYSUTCDATETIME() AS DATE);

    IF (@CompanyType = 'Water')
    BEGIN
        SELECT
            Metric1 = CAST(ISNULL((
                SELECT SUM(b.BagsProduced) FROM dbo.WaterProductionBatches b
                WHERE  b.FarmId = @FarmId AND b.IsDeleted = 0
                  AND  b.Status <> 'Cancelled' AND b.ProductionDate = @Today), 0) AS DECIMAL(18,2)),
            Metric2 = CAST(ISNULL((
                SELECT SUM(t.Quantity) FROM dbo.WaterStockTransactions t
                WHERE  t.FarmId = @FarmId), 0) AS DECIMAL(18,2)),
            Metric3 = CAST((
                SELECT COUNT(*) FROM dbo.WaterDriverReturns r
                WHERE  r.FarmId = @FarmId AND CAST(r.ReturnDate AS DATE) = @Today) AS DECIMAL(18,2)),
            Metric4 = CAST(ISNULL((
                SELECT SUM(s.TotalAmount) FROM dbo.WaterSales s
                WHERE  s.FarmId = @FarmId AND s.Status <> 'Cancelled'
                  AND  CAST(s.SaleDate AS DATE) = @Today), 0) AS DECIMAL(18,2));
        RETURN;
    END

    IF (@CompanyType = 'Poultry')
    BEGIN
        -- Feed stock, kg. The ledger this mirrors treats an inventory row's
        -- CURRENT quantity as the "in" side and subtracts usage from it, which
        -- is the definition the Feed tracker page has always shown; reproducing
        -- it (rather than a truer purchases-minus-usage) is what keeps the card
        -- and that page in agreement.
        --
        -- Units follow supplyQuantityToKg: tonnes scale up, grams scale down,
        -- kg and anything unrecognised pass through as-is. LIKE is collation-
        -- driven and case-insensitive on the default collation, matching the
        -- lowercase compare the TypeScript does. Order matters — 'kg' contains
        -- 'g', so kg has to be settled before the gram test.
        DECLARE @FeedIn DECIMAL(18,4) = ISNULL((
            SELECT SUM(CASE
                        WHEN LOWER(LTRIM(RTRIM(ISNULL(i.UnitOfMeasure, '')))) LIKE '%ton%' THEN i.QuantityInStock * 1000
                        WHEN LOWER(LTRIM(RTRIM(ISNULL(i.UnitOfMeasure, '')))) IN ('kg', 'kgs')
                          OR LOWER(LTRIM(RTRIM(ISNULL(i.UnitOfMeasure, '')))) LIKE '%kilogram%' THEN i.QuantityInStock
                        WHEN LOWER(LTRIM(RTRIM(ISNULL(i.UnitOfMeasure, '')))) LIKE '%g%' THEN i.QuantityInStock / 1000.0
                        ELSE i.QuantityInStock
                       END)
            FROM   dbo.InventoryItem i
            WHERE  i.FarmId = @FarmId
              AND  LOWER(LTRIM(RTRIM(ISNULL(i.Category, '')))) LIKE '%feed%'
              AND  i.QuantityInStock > 0), 0);

        DECLARE @FeedOut DECIMAL(18,4) = ISNULL((
            SELECT SUM(u.QuantityKg) FROM dbo.FeedUsage u
            WHERE  u.FarmId = @FarmId AND u.QuantityKg > 0), 0);

        DECLARE @FeedAdj DECIMAL(18,4) = ISNULL((
            SELECT SUM(a.FeedDeltaKg) FROM dbo.FeedInventoryAdjustment a
            WHERE  a.FarmId = @FarmId), 0);

        SELECT
            Metric1 = CAST(ISNULL((
                SELECT SUM(p.TotalProduction) FROM dbo.ProductionRecords p
                WHERE  p.FarmId = @FarmId AND p.[Date] = @Today), 0) AS DECIMAL(18,2)),
            Metric2 = CAST(@FeedIn - @FeedOut + @FeedAdj AS DECIMAL(18,2)),
            Metric3 = CAST(ISNULL((
                SELECT SUM(p.Mortality) FROM dbo.ProductionRecords p
                WHERE  p.FarmId = @FarmId AND p.[Date] = @Today), 0) AS DECIMAL(18,2)),
            Metric4 = CAST(ISNULL((
                SELECT SUM(s.TotalAmount) FROM dbo.[Sale] s
                WHERE  s.FarmId = @FarmId AND CAST(s.SaleDate AS DATE) = @Today), 0) AS DECIMAL(18,2));
        RETURN;
    END

    IF (@CompanyType = 'Generic')
    BEGIN
        SELECT
            Metric1 = CAST(ISNULL((
                SELECT SUM(s.TotalAmount) FROM dbo.GenericSales s
                WHERE  s.FarmId = @FarmId AND s.IsDeleted = 0 AND s.Status <> 'Cancelled'
                  AND  CAST(s.SaleDate AS DATE) = @Today), 0) AS DECIMAL(18,2)),
            Metric2 = CAST(ISNULL((
                SELECT SUM(e.Amount) FROM dbo.GenericExpenses e
                WHERE  e.FarmId = @FarmId AND e.IsDeleted = 0 AND e.Status = 'Approved'
                  AND  CAST(e.ExpenseDate AS DATE) = @Today), 0) AS DECIMAL(18,2)),
            Metric3 = CAST((
                SELECT COUNT(*) FROM dbo.GenericProducts p
                WHERE  p.FarmId = @FarmId AND p.IsDeleted = 0 AND p.IsActive = 1
                  AND  p.TrackInventory = 1 AND p.CurrentStock <= p.MinimumStockAlert) AS DECIMAL(18,2)),
            Metric4 = CAST(ISNULL((
                SELECT SUM(c.CurrentBalance) FROM dbo.GenericCustomers c
                WHERE  c.FarmId = @FarmId AND c.IsDeleted = 0 AND c.CurrentBalance > 0), 0) AS DECIMAL(18,2));
        RETURN;
    END

    -- Unknown type: a shaped row of NULLs, so the caller renders dashes rather
    -- than erroring on a missing result set.
    SELECT Metric1 = CAST(NULL AS DECIMAL(18,2)),
           Metric2 = CAST(NULL AS DECIMAL(18,2)),
           Metric3 = CAST(NULL AS DECIMAL(18,2)),
           Metric4 = CAST(NULL AS DECIMAL(18,2));
END
GO

IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
    GRANT EXECUTE ON dbo.spBusinessOffice_CompanySnapshot TO PoultryAppRole;
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spBusinessOffice_CompanySnapshot TO [Techretainer];
    PRINT '195: granted EXECUTE on spBusinessOffice_CompanySnapshot to Techretainer.';
END
GO

PRINT '195_BusinessOfficeCompanySnapshot.sql complete.';
GO

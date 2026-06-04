-- =============================================================================
-- Migration 081: spWaterReport_SupplierActivity — per-supplier rollup
-- =============================================================================
-- "Three Prompts In one powerful please implement all.txt" §10 (Supplier Report)
-- and §11 (final expected behavior — "Suppliers can be created and managed
-- from Setup and from a full Suppliers page" + "Reports include supplier ...
-- data where relevant").
--
-- Returns one row per active supplier for a given farm + date range:
--   SupplierName, SupplierType, ContactPerson, Phone, Email
--   TotalPurchaseAmount  — sum of WaterRawMaterialPurchases.Quantity * UnitCost
--                          for purchases keyed to this SupplierId
--   PurchaseCount        — count of those purchases
--   LastPurchaseDate     — MAX(PurchaseDate)
--   TotalExpenseAmount   — sum of WaterExpenses.Amount for expenses keyed to
--                          this SupplierId where IsDeleted=0 AND Status IN
--                          ('Approved','Paid','Submitted') so cancelled rows
--                          don't pollute the rollup
--   ExpenseCount         — count of those expenses
--   LastExpenseDate      — MAX(ExpenseDate)
--   OutstandingBalance   — for purchases on credit: sum of
--                          (TotalCost - AmountPaid) where (TotalCost > AmountPaid)
--
-- @FromDate / @ToDate are nullable so the caller can pull lifetime or windowed
-- activity. The aggregations live inline so the SP stays self-contained — no
-- intermediate tables, no temp tables. Sub-100 lines, idempotent.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterReport_SupplierActivity
    @FarmId   NVARCHAR(450),
    @FromDate DATE = NULL,
    @ToDate   DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.WaterSupplierId,
        s.SupplierName,
        s.SupplierType,
        s.ContactPerson,
        s.Phone,
        s.Email,
        ISNULL(p.TotalPurchaseAmount, 0) AS TotalPurchaseAmount,
        ISNULL(p.PurchaseCount,       0) AS PurchaseCount,
        p.LastPurchaseDate,
        ISNULL(e.TotalExpenseAmount, 0)  AS TotalExpenseAmount,
        ISNULL(e.ExpenseCount,       0)  AS ExpenseCount,
        e.LastExpenseDate,
        ISNULL(p.OutstandingBalance, 0)  AS OutstandingBalance
    FROM dbo.WaterSuppliers s
    OUTER APPLY (
        SELECT
            SUM(CAST(rp.Quantity AS DECIMAL(14,2)) * rp.UnitCost) AS TotalPurchaseAmount,
            COUNT(*)         AS PurchaseCount,
            MAX(rp.PurchaseDate) AS LastPurchaseDate,
            SUM(
                CASE
                    WHEN (CAST(rp.Quantity AS DECIMAL(14,2)) * rp.UnitCost) > ISNULL(rp.AmountPaid, 0)
                    THEN (CAST(rp.Quantity AS DECIMAL(14,2)) * rp.UnitCost) - ISNULL(rp.AmountPaid, 0)
                    ELSE 0
                END
            ) AS OutstandingBalance
        FROM dbo.WaterRawMaterialPurchases rp
        WHERE rp.FarmId     = s.FarmId
          AND rp.SupplierId = s.WaterSupplierId
          AND (@FromDate IS NULL OR CAST(rp.PurchaseDate AS DATE) >= @FromDate)
          AND (@ToDate   IS NULL OR CAST(rp.PurchaseDate AS DATE) <= @ToDate)
    ) p
    OUTER APPLY (
        SELECT
            SUM(we.Amount)         AS TotalExpenseAmount,
            COUNT(*)               AS ExpenseCount,
            MAX(we.ExpenseDate)    AS LastExpenseDate
        FROM dbo.WaterExpenses we
        WHERE we.FarmId     = s.FarmId
          AND we.SupplierId = s.WaterSupplierId
          AND we.IsDeleted  = 0
          AND we.Status IN (N'Submitted', N'Approved', N'Paid')
          AND (@FromDate IS NULL OR CAST(we.ExpenseDate AS DATE) >= @FromDate)
          AND (@ToDate   IS NULL OR CAST(we.ExpenseDate AS DATE) <= @ToDate)
    ) e
    WHERE s.FarmId    = @FarmId
      AND s.IsDeleted = 0
    ORDER BY s.SupplierName;
END
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'PoultryAppRole' AND type = N'R')
    GRANT EXECUTE ON dbo.spWaterReport_SupplierActivity TO PoultryAppRole;
GO
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'Techretainer')
    GRANT EXECUTE ON dbo.spWaterReport_SupplierActivity TO Techretainer;
GO

PRINT '081_AddWaterSupplierActivityReport.sql complete.';
GO

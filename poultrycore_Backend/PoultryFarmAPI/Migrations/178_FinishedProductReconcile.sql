-- =============================================================================
-- 178_FinishedProductReconcile.sql
-- Finished-product stock reconciliation (Poultry + Water).
--
-- Finished-product stock is NOT stored — it is computed live as the SUM of the
-- product's stock-transaction ledger (Poultry: migration 124; Water: 084). So it
-- cannot "drift" and there is nothing to overwrite. These read-only SPs recompute
-- each finished product's stock straight from the ledger and break it down into
-- total IN (produced / added) vs total OUT (sold / removed), so an owner can
-- reconcile a finished good and see exactly how its current stock was reached.
--
-- Read-only (no UPDATE). Additive + idempotent. Grants EXECUTE to `Techretainer`.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---- Poultry finished products (Birds, Eggs, …) -----------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_ReconcileStock
    @FarmId           NVARCHAR(450),
    @PoultryProductId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.PoultryProductId,
           p.Name,
           CAST(ISNULL(SUM(CASE WHEN t.Quantity > 0 THEN t.Quantity ELSE 0 END), 0) AS DECIMAL(18,3)) AS StockIn,
           CAST(ISNULL(SUM(CASE WHEN t.Quantity < 0 THEN -t.Quantity ELSE 0 END), 0) AS DECIMAL(18,3)) AS StockOut,
           CAST(ISNULL(SUM(t.Quantity), 0) AS DECIMAL(18,3)) AS CurrentStock
    FROM   dbo.PoultryProducts p
    LEFT JOIN dbo.PoultryStockTransactions t
           ON t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId
    WHERE  p.FarmId = @FarmId
      AND  (@PoultryProductId IS NULL OR p.PoultryProductId = @PoultryProductId)
    GROUP  BY p.PoultryProductId, p.Name
    ORDER  BY p.Name;
END
GO

-- ---- Water finished products (Sachet Water, Bottled, …) ----------------------
-- Uses ISNULL(BaseQuantity, Quantity) so sachet products (tracked in base units)
-- reconcile against the same figure the inventory list displays (migration 084).
CREATE OR ALTER PROCEDURE dbo.spWaterProduct_ReconcileStock
    @FarmId         NVARCHAR(450),
    @WaterProductId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.WaterProductId,
           p.Name,
           CAST(ISNULL(SUM(CASE WHEN ISNULL(st.BaseQuantity, st.Quantity) > 0 THEN ISNULL(st.BaseQuantity, st.Quantity) ELSE 0 END), 0) AS DECIMAL(18,3)) AS StockIn,
           CAST(ISNULL(SUM(CASE WHEN ISNULL(st.BaseQuantity, st.Quantity) < 0 THEN -ISNULL(st.BaseQuantity, st.Quantity) ELSE 0 END), 0) AS DECIMAL(18,3)) AS StockOut,
           CAST(ISNULL(SUM(ISNULL(st.BaseQuantity, st.Quantity)), 0) AS DECIMAL(18,3)) AS CurrentStock
    FROM   dbo.WaterProducts p
    LEFT JOIN dbo.WaterStockTransactions st
           ON st.WaterProductId = p.WaterProductId AND st.FarmId = p.FarmId
    WHERE  p.FarmId = @FarmId
      AND  (@WaterProductId IS NULL OR p.WaterProductId = @WaterProductId)
    GROUP  BY p.WaterProductId, p.Name
    ORDER  BY p.Name;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryProduct_ReconcileStock TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterProduct_ReconcileStock   TO [Techretainer];
    PRINT '178: granted EXECUTE on finished-product reconcile SPs to Techretainer.';
END
GO

PRINT '178_FinishedProductReconcile.sql complete.';
GO

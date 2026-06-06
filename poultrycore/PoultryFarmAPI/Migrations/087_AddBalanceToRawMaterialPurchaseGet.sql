-- =============================================================================
-- Migration 087: Surface (TotalCost - AmountPaid) AS Balance on the raw
--               material purchase list endpoint.
-- =============================================================================
-- Bug (report 3 / 2026-06-05): "Part payment was made during the purchase of
-- raw materials and supplies, but the balance shows as Gh0.00, which should
-- reflect the amount we still need to pay."
--
-- Root cause: spWaterRawMaterialPurchase_GetAll (migration 044) returns
-- `SELECT p.*` and the WaterRawMaterialPurchases table never stored a Balance
-- column (just AmountPaid + a computed TotalCost). The C# model + the frontend
-- list both read a Balance field that was never being populated, so every row
-- rendered Gh0.00 in the Balance column regardless of payment state.
--
-- Fix: ALTER the SP to include `(p.TotalCost - p.AmountPaid) AS Balance`. The
-- C# WaterRawMaterialPurchaseService.Read() consumes the column defensively
-- (HasCol guard), so the API stays backward-compatible if this migration
-- hasn't been applied yet.
--
-- Safety:
--   * CREATE OR ALTER — idempotent.
--   * Additive change: no column drop, no row mutation.
--   * Body matches the latest deployed version (044 only — no later migration
--     altered this SP) verbatim except for the Balance projection.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_GetAll
    @FarmId NVARCHAR(450), @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.*,
           i.ItemName,
           i.Category,
           i.UnitOfMeasure,
           CAST(p.TotalCost - p.AmountPaid AS DECIMAL(14,2)) AS Balance
    FROM   dbo.WaterRawMaterialPurchases p
    INNER  JOIN dbo.WaterRawMaterialItems i ON i.WaterRawMaterialItemId = p.WaterRawMaterialItemId
    WHERE  p.FarmId = @FarmId
       AND (@FromDate IS NULL OR CAST(p.PurchaseDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(p.PurchaseDate AS DATE) <= @ToDate)
    ORDER  BY p.PurchaseDate DESC, p.WaterRawMaterialPurchaseId DESC;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_GetAll TO [Techretainer];
    PRINT '087: granted EXECUTE on dbo.spWaterRawMaterialPurchase_GetAll to Techretainer.';
END
GO

PRINT '087_AddBalanceToRawMaterialPurchaseGet.sql complete.';
GO

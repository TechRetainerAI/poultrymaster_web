-- =============================================================================
-- Migration 191: expose the open purchase lots so the batch form can show the draw
-- =============================================================================
-- Recording a production batch, the operator types "1,500 metres of sachet film"
-- and until now saw one blended unit cost taken from the latest purchase. What
-- actually happens at approval is a walk down the item's open lots in its
-- FIFO/LIFO/HIFO order, and the price is whatever that walk paid — which is not
-- the latest purchase price unless there happens to be only one lot.
--
-- This returns those lots so /water-production-batches can show the real split
-- as the quantity is typed:
--
--   Lot A  5 Jan   1,000 m @ 2.00/m   GHS 2,000
--   Lot B  20 Jan    500 m @ 2.50/m   GHS 1,250
--   -------------------------------------------
--   1,500 m                           GHS 3,250   (2.1667/m)
--
-- It also gives the form the DRAWABLE quantity — the sum of what's left in the
-- lots — which is the number approval actually checks against. That differs from
-- WaterRawMaterialItems.CurrentQuantity whenever stock arrived by manual
-- adjustment: on hand, but with no purchase lot behind it. The form has been
-- warning against CurrentQuantity, so it could look content while approval was
-- about to refuse.
--
-- Read-only: one new SP, no schema, no behaviour change. Requires 187.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Open lots for one item, or every raw-material item on the farm when the id is
-- omitted (the batch form loads the lot for all of them in one call).
--
-- Rows come back in the order the item's own policy would consume them, so the
-- client can walk them straight down the list without re-sorting. Ties break on
-- id, matching spWaterRawMaterialItem_ConsumeBatches exactly — if the two ever
-- disagree the preview would show a different price from the one charged.
CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_GetOpenLots
    @FarmId NVARCHAR(450),
    @WaterRawMaterialItemId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.WaterRawMaterialPurchaseId,
           p.WaterRawMaterialItemId,
           i.ItemName,
           i.UsageMethod,
           p.PurchaseDate,
           p.SupplierName,
           -- What's left, in PURCHASE units, and the same figure converted to the
           -- PRODUCTION units the batch is typed in.
           p.RemainingQuantity,
           ProductionUnitsPerPurchaseUnit = ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1),
           RemainingProductionQuantity = CAST(p.RemainingQuantity * ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1) AS DECIMAL(18,4)),
           -- Cost per purchase unit as bought, and per production unit as consumed.
           p.UnitCost,
           ProductionUnitCost = CAST(p.UnitCost / ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1) AS DECIMAL(18,4))
    FROM   dbo.WaterRawMaterialPurchases p
    INNER  JOIN dbo.WaterRawMaterialItems i
           ON i.WaterRawMaterialItemId = p.WaterRawMaterialItemId
    WHERE  p.FarmId = @FarmId
      AND  p.RemainingQuantity > 0
      AND  (@WaterRawMaterialItemId IS NULL OR p.WaterRawMaterialItemId = @WaterRawMaterialItemId)
    ORDER  BY p.WaterRawMaterialItemId,
              CASE WHEN i.UsageMethod = 'FIFO' THEN p.PurchaseDate END ASC,
              CASE WHEN i.UsageMethod = 'LIFO' THEN p.PurchaseDate END DESC,
              CASE WHEN i.UsageMethod = 'HIFO' THEN p.UnitCost END DESC,
              p.WaterRawMaterialPurchaseId ASC;
END
GO

IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_GetOpenLots TO PoultryAppRole;
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_GetOpenLots TO [Techretainer];
    PRINT '191: granted EXECUTE on spWaterRawMaterialItem_GetOpenLots to Techretainer.';
END
GO

PRINT '191_WaterRawMaterialOpenLots.sql complete.';
GO

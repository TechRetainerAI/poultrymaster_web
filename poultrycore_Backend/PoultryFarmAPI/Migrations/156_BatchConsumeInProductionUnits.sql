-- =============================================================================
-- Migration 156: batch consumption works in PRODUCTION units
-- =============================================================================
-- Bug (James): an item shows "25,000 in stock" (production units, e.g. Litres)
-- but consuming 10,000 is rejected as "only 550 available" — because the batch
-- costing (153) walked RemainingQuantity in PURCHASE units and compared it to a
-- quantity entered in PRODUCTION units, with no conversion. A batch of 250
-- purchase units at 100 units-per-purchase is 25,000 production units, but was
-- counted as 250.
--
-- Fix: spPoultryRawMaterialItem_ConsumeBatches now walks each batch's
-- availability in PRODUCTION units (RemainingQuantity x units-per-purchase),
-- draws the requested production quantity, decrements each batch by the
-- purchase-unit equivalent (prod / units-per-purchase), and returns the cost per
-- PRODUCTION unit. Also backfill CurrentQuantity = SUM(remaining x units) so the
-- displayed stock matches what can actually be consumed.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialItem_ConsumeBatches
    @FarmId NVARCHAR(450),
    @ItemId INT,
    @UsageId INT,
    @NeededQty DECIMAL(14,3),                 -- in PRODUCTION units (the item's stock unit)
    @ComputedUnitCost DECIMAL(14,4) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @ComputedUnitCost = NULL;
    IF (@NeededQty IS NULL OR @NeededQty <= 0) RETURN;

    DECLARE @UsageMethod NVARCHAR(10) = ISNULL((
        SELECT UsageMethod FROM dbo.PoultryRawMaterialItems
        WHERE PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId), 'FIFO');

    -- ProdDrawn = production units taken from the batch; PurchaseDrawn = the
    -- purchase-unit equivalent that decrements RemainingQuantity; UnitCost is
    -- per PURCHASE unit; Mult = production units per purchase unit.
    DECLARE @Draws TABLE (PurchaseId INT, ProdDrawn DECIMAL(18,4), PurchaseDrawn DECIMAL(18,4), UnitCost DECIMAL(14,2), Mult DECIMAL(18,8));

    ;WITH Ordered AS (
        SELECT PoultryRawMaterialPurchaseId, RemainingQuantity, UnitCost,
               Mult      = ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1),
               AvailProd = RemainingQuantity * ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1),
               RunningTotal = SUM(RemainingQuantity * ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1)) OVER (
                   ORDER BY
                       CASE WHEN @UsageMethod = 'FIFO' THEN PurchaseDate END ASC,
                       CASE WHEN @UsageMethod = 'LIFO' THEN PurchaseDate END DESC,
                       CASE WHEN @UsageMethod = 'HIFO' THEN UnitCost END DESC,
                       PoultryRawMaterialPurchaseId ASC
                   ROWS UNBOUNDED PRECEDING)
        FROM   dbo.PoultryRawMaterialPurchases WITH (UPDLOCK, ROWLOCK)
        WHERE  PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId AND RemainingQuantity > 0
    )
    INSERT INTO @Draws (PurchaseId, ProdDrawn, PurchaseDrawn, UnitCost, Mult)
    SELECT PoultryRawMaterialPurchaseId,
           ProdTake     = CASE WHEN RunningTotal <= @NeededQty THEN AvailProd ELSE @NeededQty - (RunningTotal - AvailProd) END,
           PurchaseTake = (CASE WHEN RunningTotal <= @NeededQty THEN AvailProd ELSE @NeededQty - (RunningTotal - AvailProd) END) / Mult,
           UnitCost, Mult
    FROM   Ordered
    WHERE  RunningTotal - AvailProd < @NeededQty;

    DECLARE @TotalDrawn DECIMAL(18,4) = (SELECT ISNULL(SUM(ProdDrawn), 0) FROM @Draws);
    IF (@TotalDrawn + 0.0005 < @NeededQty)
    BEGIN
        DECLARE @ItemName NVARCHAR(150) = (SELECT ItemName FROM dbo.PoultryRawMaterialItems WHERE PoultryRawMaterialItemId = @ItemId);
        DECLARE @Msg NVARCHAR(400) = CONCAT(
            N'Not enough tracked batch stock for "', ISNULL(@ItemName, N'item'), N'": need ',
            CONVERT(NVARCHAR(30), @NeededQty), N', only ', CONVERT(NVARCHAR(30), @TotalDrawn),
            N' available across purchase batches.');
        RAISERROR(@Msg, 16, 1);
        RETURN;
    END

    UPDATE p
    SET    p.RemainingQuantity = p.RemainingQuantity - d.PurchaseDrawn, p.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialPurchases p
    JOIN   @Draws d ON d.PurchaseId = p.PoultryRawMaterialPurchaseId;

    -- Store production units drawn + cost per PRODUCTION unit.
    INSERT INTO dbo.PoultryRawMaterialUsageBatch (PoultryRawMaterialUsageId, PoultryRawMaterialPurchaseId, QuantityDrawn, UnitCostAtDraw)
    SELECT @UsageId, PurchaseId, ProdDrawn, CAST(UnitCost / Mult AS DECIMAL(14,2))
    FROM   @Draws WHERE ProdDrawn > 0;

    -- Cost per PRODUCTION unit = total purchase-cost drawn / total production units drawn.
    SELECT @ComputedUnitCost = SUM(PurchaseDrawn * UnitCost) / NULLIF(SUM(ProdDrawn), 0) FROM @Draws;
END
GO

-- Backfill: CurrentQuantity = production units on hand = SUM(remaining x units).
-- Makes the displayed stock consistent with what batch consumption allows.
UPDATE i
SET    i.CurrentQuantity = x.ProdOnHand, i.UpdatedAt = SYSUTCDATETIME()
FROM   dbo.PoultryRawMaterialItems i
CROSS  APPLY (
    SELECT ProdOnHand = ISNULL(SUM(p.RemainingQuantity * ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit,0),1)), 0)
    FROM   dbo.PoultryRawMaterialPurchases p
    WHERE  p.PoultryRawMaterialItemId = i.PoultryRawMaterialItemId AND p.FarmId = i.FarmId
) x;
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_ConsumeBatches TO [Techretainer];
GO

PRINT '156_BatchConsumeInProductionUnits.sql complete.';
GO

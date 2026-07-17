-- =============================================================================
-- Migration 159: store UsageBatch draws in PURCHASE units (reversal correctness)
-- =============================================================================
-- Migration 156 made ConsumeBatches work in production units, but stored
-- PoultryRawMaterialUsageBatch.QuantityDrawn in PRODUCTION units. Gyimah's sync
-- reversal (158) restores each lot with RemainingQuantity += SUM(QuantityDrawn),
-- and RemainingQuantity is in PURCHASE units — so a production-unit QuantityDrawn
-- would over-restore the lot on edit. Store the PURCHASE-unit draw (and per-
-- purchase UnitCostAtDraw) instead; the returned @ComputedUnitCost stays per
-- PRODUCTION unit. Everything else is identical to 156.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialItem_ConsumeBatches
    @FarmId NVARCHAR(450),
    @ItemId INT,
    @UsageId INT,
    @NeededQty DECIMAL(14,3),                 -- in PRODUCTION units
    @ComputedUnitCost DECIMAL(14,4) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @ComputedUnitCost = NULL;
    IF (@NeededQty IS NULL OR @NeededQty <= 0) RETURN;

    DECLARE @UsageMethod NVARCHAR(10) = ISNULL((
        SELECT UsageMethod FROM dbo.PoultryRawMaterialItems
        WHERE PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId), 'FIFO');

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

    -- Store the PURCHASE-unit draw + per-purchase cost, so 158's reversal
    -- (RemainingQuantity += SUM(QuantityDrawn)) restores lots correctly.
    INSERT INTO dbo.PoultryRawMaterialUsageBatch (PoultryRawMaterialUsageId, PoultryRawMaterialPurchaseId, QuantityDrawn, UnitCostAtDraw)
    SELECT @UsageId, PurchaseId, PurchaseDrawn, CAST(UnitCost AS DECIMAL(14,2))
    FROM   @Draws WHERE ProdDrawn > 0;

    -- Cost per PRODUCTION unit = total purchase-cost drawn / total production units drawn.
    SELECT @ComputedUnitCost = SUM(PurchaseDrawn * UnitCost) / NULLIF(SUM(ProdDrawn), 0) FROM @Draws;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_ConsumeBatches TO [Techretainer];
GO

PRINT '159_BatchConsumeUsageInPurchaseUnits.sql complete.';
GO

-- =============================================================================
-- Migration 193: make LIFO actually consume last-in-first-out
-- =============================================================================
-- SYMPTOM
--   On /water-production-batches an item set to LIFO drew its lots in FIFO
--   order — oldest lot first, oldest price. HIFO and FIFO behaved correctly.
--
-- CAUSE
--   Migrations 188 (spWaterRawMaterialItem_ConsumeBatches) and 191
--   (spWaterRawMaterialItem_GetOpenLots) both order the lots as:
--
--       CASE WHEN method = 'FIFO' THEN PurchaseDate END ASC,
--       CASE WHEN method = 'LIFO' THEN PurchaseDate END DESC,
--       CASE WHEN method = 'HIFO' THEN UnitCost     END DESC,
--       WaterRawMaterialPurchaseId ASC          -- always ascending
--
--   WaterRawMaterialPurchases.PurchaseDate is DATETIME2, but the purchase form
--   posts a date only, so every lot bought on the same day carries the identical
--   midnight timestamp. Under LIFO the date key then ties across all of them and
--   the last key decides — id ASC, i.e. the oldest purchase first. That is FIFO.
--   HIFO was unaffected because it sorts on UnitCost, which usually differs.
--
-- FIX
--   Break ties in the direction the policy implies: LIFO falls back to
--   PurchaseId DESC (newest row entered = last in), FIFO/HIFO keep id ASC. Two
--   lots bought the same day now consume newest-first under LIFO.
--
--   Both procedures get the same clause — the client-side preview in
--   lib/water-lot-draw.ts walks whatever order GetOpenLots returns, so if the
--   two ever disagree the form would quote a price approval wouldn't charge.
--
-- Ordering only. No schema, no data change, nothing to backfill; already-approved
-- batches keep the lots and costs they were charged. Requires 187, 188, 191.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. The draw engine — body as migration 188 with the tie-break corrected.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_ConsumeBatches
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
        SELECT UsageMethod FROM dbo.WaterRawMaterialItems
        WHERE WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId), 'FIFO');

    DECLARE @Draws TABLE (PurchaseId INT, ProdDrawn DECIMAL(18,4), PurchaseDrawn DECIMAL(18,4), UnitCost DECIMAL(14,2), Mult DECIMAL(18,8));

    ;WITH Ordered AS (
        SELECT WaterRawMaterialPurchaseId, RemainingQuantity, UnitCost,
               Mult      = ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1),
               AvailProd = RemainingQuantity * ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1),
               RunningTotal = SUM(RemainingQuantity * ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1)) OVER (
                   ORDER BY
                       CASE WHEN @UsageMethod = 'FIFO' THEN PurchaseDate END ASC,
                       CASE WHEN @UsageMethod = 'LIFO' THEN PurchaseDate END DESC,
                       CASE WHEN @UsageMethod = 'HIFO' THEN UnitCost END DESC,
                       -- Same-day lots tie on the date; under LIFO the later row
                       -- is the later purchase, so it must go first.
                       CASE WHEN @UsageMethod = 'LIFO' THEN WaterRawMaterialPurchaseId END DESC,
                       WaterRawMaterialPurchaseId ASC
                   ROWS UNBOUNDED PRECEDING)
        FROM   dbo.WaterRawMaterialPurchases WITH (UPDLOCK, ROWLOCK)
        WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId AND RemainingQuantity > 0
    )
    INSERT INTO @Draws (PurchaseId, ProdDrawn, PurchaseDrawn, UnitCost, Mult)
    SELECT WaterRawMaterialPurchaseId,
           ProdTake     = CASE WHEN RunningTotal <= @NeededQty THEN AvailProd ELSE @NeededQty - (RunningTotal - AvailProd) END,
           PurchaseTake = (CASE WHEN RunningTotal <= @NeededQty THEN AvailProd ELSE @NeededQty - (RunningTotal - AvailProd) END) / Mult,
           UnitCost, Mult
    FROM   Ordered
    WHERE  RunningTotal - AvailProd < @NeededQty;

    DECLARE @TotalDrawn DECIMAL(18,4) = (SELECT ISNULL(SUM(ProdDrawn), 0) FROM @Draws);
    IF (@TotalDrawn + 0.0005 < @NeededQty)
    BEGIN
        DECLARE @ItemName NVARCHAR(150) = (SELECT ItemName FROM dbo.WaterRawMaterialItems WHERE WaterRawMaterialItemId = @ItemId);
        DECLARE @Msg NVARCHAR(400) = CONCAT(
            N'Not enough tracked batch stock for "', ISNULL(@ItemName, N'item'), N'": need ',
            CONVERT(NVARCHAR(30), @NeededQty), N', only ', CONVERT(NVARCHAR(30), @TotalDrawn),
            N' available across purchase batches.');
        RAISERROR(@Msg, 16, 1);
        RETURN;
    END

    UPDATE p
    SET    p.RemainingQuantity = p.RemainingQuantity - d.PurchaseDrawn, p.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.WaterRawMaterialPurchases p
    JOIN   @Draws d ON d.PurchaseId = p.WaterRawMaterialPurchaseId;

    -- Stored in PURCHASE units + per-purchase cost, so a reopen restores each
    -- lot with a plain `RemainingQuantity += SUM(QuantityDrawn)`.
    INSERT INTO dbo.WaterRawMaterialUsageBatch (WaterRawMaterialUsageId, WaterRawMaterialPurchaseId, QuantityDrawn, UnitCostAtDraw)
    SELECT @UsageId, PurchaseId, PurchaseDrawn, CAST(UnitCost AS DECIMAL(14,2))
    FROM   @Draws WHERE ProdDrawn > 0;

    -- Cost per PRODUCTION unit = total purchase-cost drawn / production units drawn.
    SELECT @ComputedUnitCost = SUM(PurchaseDrawn * UnitCost) / NULLIF(SUM(ProdDrawn), 0) FROM @Draws;
END
GO

-- -----------------------------------------------------------------------------
-- 2. The preview feed — body as migration 191 with the same tie-break.
-- -----------------------------------------------------------------------------
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
              -- Must match spWaterRawMaterialItem_ConsumeBatches exactly.
              CASE WHEN i.UsageMethod = 'LIFO' THEN p.WaterRawMaterialPurchaseId END DESC,
              p.WaterRawMaterialPurchaseId ASC;
END
GO

IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_ConsumeBatches TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_GetOpenLots     TO PoultryAppRole;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_ConsumeBatches TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_GetOpenLots     TO [Techretainer];
    PRINT '193: granted EXECUTE on the two water lot SPs to Techretainer.';
END
GO

PRINT '193_WaterRawMaterialLifoTieBreak.sql complete.';
GO

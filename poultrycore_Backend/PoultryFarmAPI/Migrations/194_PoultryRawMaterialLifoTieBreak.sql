-- =============================================================================
-- Migration 194: make LIFO actually consume last-in-first-out (poultry side)
-- =============================================================================
-- Same defect migration 193 fixed for water, in the poultry draw engine.
--
-- CAUSE
--   spPoultryRawMaterialItem_ConsumeBatches (last defined in migration 159)
--   orders the lots as:
--
--       CASE WHEN method = 'FIFO' THEN PurchaseDate END ASC,
--       CASE WHEN method = 'LIFO' THEN PurchaseDate END DESC,
--       CASE WHEN method = 'HIFO' THEN UnitCost     END DESC,
--       PoultryRawMaterialPurchaseId ASC        -- always ascending
--
--   PoultryRawMaterialPurchases.PurchaseDate is DATETIME2 (migration 123), but
--   the purchase dialog posts a date only, so lots bought on the same day all
--   carry the identical midnight timestamp. Under LIFO the date key ties across
--   them and the last key decides — id ASC, the oldest purchase first. That is
--   FIFO. HIFO escaped it by sorting on UnitCost, which usually differs.
--
-- FIX
--   Break ties in the direction the policy implies: LIFO falls back to
--   PurchaseId DESC (newest row = last in), FIFO/HIFO keep id ASC.
--
--   This is the only lot walk on the poultry side — production records and feed
--   production posting (171) both draw through this SP — so one procedure covers
--   every consumer. The client-side preview in lib/utils/raw-material-costing.ts
--   does its own sort and was corrected to match.
--
-- Body as migration 159 with the tie-break added. Ordering only: no schema, no
-- data change, and past usage keeps the lots and costs it was charged.
-- Requires 159.
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
                       -- Same-day lots tie on the date; under LIFO the later row
                       -- is the later purchase, so it must go first.
                       CASE WHEN @UsageMethod = 'LIFO' THEN PoultryRawMaterialPurchaseId END DESC,
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

IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_ConsumeBatches TO PoultryAppRole;
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_ConsumeBatches TO [Techretainer];
    PRINT '194: granted EXECUTE on spPoultryRawMaterialItem_ConsumeBatches to Techretainer.';
END
GO

PRINT '194_PoultryRawMaterialLifoTieBreak.sql complete.';
GO

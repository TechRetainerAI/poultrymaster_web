-- =============================================================================
-- 183_WaterRecipeProductionUnitCost.sql
-- Water production batch: raw-material unit price must be the PRODUCTION-level
-- unit cost, not the purchase-level unit cost.
--
-- Bug (James): spWaterProductionRecipe_GetByProduct (migration 063) filled the
-- recipe item's LatestUnitCost with the latest purchase's p.UnitCost — the cost
-- per PURCHASE unit (e.g. per roll). But a batch consumes materials in PRODUCTION
-- units (the item's UnitOfMeasure), so the money maths (qty x unitCost) was wrong.
--
-- Production-level unit cost = purchase UnitCost / ProductionUnitsPerPurchaseUnit
-- (units per purchase unit; NULL/0 => 1). This matches the "Production-level unit
-- cost (auto)" shown on the purchase dialog. Only this SP changes.
--
-- Idempotent (CREATE OR ALTER). Grants preserved.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProductionRecipe_GetByProduct
    @FarmId         NVARCHAR(450),
    @WaterProductId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Recipe header (0 or 1 row).
    SELECT TOP 1 r.*
    FROM   dbo.WaterProductionRecipes r
    WHERE  r.FarmId = @FarmId
       AND r.WaterProductId = @WaterProductId
       AND r.IsActive = 1
    ORDER BY r.IsDefault DESC, r.WaterProductionRecipeId DESC;

    -- Items, joined with material name / unit / stock. LatestUnitCost is now the
    -- PRODUCTION-level unit cost from the most recent purchase (per production
    -- unit), so the batch's qty x unitCost is money-correct.
    SELECT  ri.WaterProductionRecipeItemId,
            ri.WaterProductionRecipeId,
            ri.WaterRawMaterialItemId,
            mi.ItemName             AS RawMaterialName,
            mi.UnitOfMeasure        AS RawMaterialUnit,
            mi.CurrentQuantity      AS RawMaterialStock,
            ri.QuantityPerOutputUnit,
            ri.OutputUnit,
            ri.WasteAllowancePercent,
            ri.IsOptional,
            ri.DisplayOrder,
            ri.Notes,
            -- Production-level unit cost from the latest purchase:
            --   purchase UnitCost / production-units-per-purchase-unit.
            (SELECT TOP 1 p.UnitCost / ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1)
             FROM   dbo.WaterRawMaterialPurchases p
             WHERE  p.WaterRawMaterialItemId = ri.WaterRawMaterialItemId
               AND  p.FarmId = @FarmId
             ORDER  BY p.PurchaseDate DESC, p.WaterRawMaterialPurchaseId DESC) AS LatestUnitCost,
            ri.CreatedAt,
            ri.UpdatedAt
    FROM    dbo.WaterProductionRecipeItems ri
    JOIN    dbo.WaterProductionRecipes      r  ON r.WaterProductionRecipeId = ri.WaterProductionRecipeId
    JOIN    dbo.WaterRawMaterialItems       mi ON mi.WaterRawMaterialItemId = ri.WaterRawMaterialItemId
    WHERE   r.FarmId = @FarmId
      AND   r.WaterProductId = @WaterProductId
      AND   r.IsActive = 1
    ORDER  BY ri.DisplayOrder, ri.WaterProductionRecipeItemId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterProductionRecipe_GetByProduct TO PoultryAppRole;
GO
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterProductionRecipe_GetByProduct TO [Techretainer];
GO

PRINT '183_WaterRecipeProductionUnitCost.sql complete.';
GO

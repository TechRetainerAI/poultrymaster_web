-- =============================================================================
-- Migration 187: Water raw materials — FIFO/LIFO/HIFO lots (substrate only)
-- =============================================================================
-- Parity with the Poultry lot costing introduced in migration 153, so a water
-- production batch draws its raw materials from real purchase lots at their real
-- price instead of whatever unit cost the client happened to send.
--
-- This migration lays the substrate ONLY — nothing consumes it yet, so applying
-- it changes no behaviour:
--
--   1. WaterRawMaterialItems.UsageMethod  — 'FIFO' | 'LIFO' | 'HIFO' (default FIFO)
--   2. WaterRawMaterialPurchases.RemainingQuantity — turns each purchase into a
--      lot with a balance, backfilled and reconciled against today's on-hand
--   3. WaterRawMaterialUsageBatch — links a usage row to the lot(s) it drew from
--
-- Migration 188 adds the consume engine and rewires approve/reopen.
--
-- UNITS — the trap that cost Poultry two follow-up migrations (156, then 159):
--   * Purchases.Quantity and RemainingQuantity are in PURCHASE units (e.g. rolls)
--   * Items.CurrentQuantity and Usage.QuantityUsed are in PRODUCTION units
--   * the bridge is ProductionUnitsPerPurchaseUnit (NULL/0 => 1)
-- RemainingQuantity is therefore kept in PURCHASE units here, matching Quantity,
-- and the engine converts. Migration 176's recalc already uses the same bridge.
--
-- ADJUSTMENTS — water has a manual adjustment ledger (177) that poultry's 153
-- predated. An adjustment moves CurrentQuantity with no purchase behind it, so
-- it creates no lot. The backfill below accounts for adjustments when working
-- out how much of the purchase history has already been consumed; the standing
-- consequence (stock added by adjustment isn't drawable, because there is no lot
-- to draw it from) matches Poultry and is surfaced in the UI, not hidden here.
--
-- Idempotent. Additive. Safe to re-run — the backfill is guarded on the column
-- still being nullable, so it runs exactly once.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. WaterRawMaterialItems.UsageMethod — the per-item consumption policy.
-- -----------------------------------------------------------------------------
IF COL_LENGTH('dbo.WaterRawMaterialItems', 'UsageMethod') IS NULL
BEGIN
    ALTER TABLE dbo.WaterRawMaterialItems
        ADD UsageMethod NVARCHAR(10) NOT NULL
            CONSTRAINT DF_WaterRawMaterialItems_UsageMethod DEFAULT ('FIFO');
    PRINT '187: added WaterRawMaterialItems.UsageMethod.';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_WaterRawMaterialItems_UsageMethod')
BEGIN
    ALTER TABLE dbo.WaterRawMaterialItems
        ADD CONSTRAINT CK_WaterRawMaterialItems_UsageMethod CHECK (UsageMethod IN ('FIFO','LIFO','HIFO'));
    PRINT '187: added CK_WaterRawMaterialItems_UsageMethod.';
END
GO

-- -----------------------------------------------------------------------------
-- 2. WaterRawMaterialPurchases.RemainingQuantity — purchases become lots.
-- -----------------------------------------------------------------------------
-- Added nullable in its own batch: a statement later in the SAME batch that
-- reads the column compiles against the pre-ALTER schema and fails with
-- "Invalid column name" even though the ALTER ran immediately before it.
IF COL_LENGTH('dbo.WaterRawMaterialPurchases', 'RemainingQuantity') IS NULL
BEGIN
    ALTER TABLE dbo.WaterRawMaterialPurchases ADD RemainingQuantity DECIMAL(14,3) NULL;
    PRINT '187: added WaterRawMaterialPurchases.RemainingQuantity.';
END
GO

-- First-run backfill + reconciliation. Guarded on the column still being
-- nullable, so re-running this file never re-drains live lots.
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.WaterRawMaterialPurchases')
      AND name = 'RemainingQuantity' AND is_nullable = 1
)
BEGIN
    PRINT '187: backfilling RemainingQuantity...';

    -- Every lot starts full.
    UPDATE dbo.WaterRawMaterialPurchases
    SET    RemainingQuantity = Quantity
    WHERE  RemainingQuantity IS NULL;

    -- Then draw down the history that has already been consumed, so the lots
    -- reconcile with the CurrentQuantity each item carries today.
    --
    --   consumed (production units) = purchased + adjustments - on hand
    --
    -- Adjustments are included because they moved CurrentQuantity without a lot:
    -- leaving them out would make the drawdown think that much stock is still
    -- sitting in lots. A negative result (on hand exceeds what the ledgers
    -- explain) draws nothing down.
    ;WITH Consumed AS (
        SELECT i.WaterRawMaterialItemId,
               i.FarmId,
               ToDraw = CAST(
                     ISNULL((SELECT SUM(p.Quantity * ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1))
                             FROM   dbo.WaterRawMaterialPurchases p
                             WHERE  p.WaterRawMaterialItemId = i.WaterRawMaterialItemId AND p.FarmId = i.FarmId), 0)
                   + ISNULL((SELECT SUM(a.Quantity)
                             FROM   dbo.WaterRawMaterialAdjustments a
                             WHERE  a.WaterRawMaterialItemId = i.WaterRawMaterialItemId AND a.FarmId = i.FarmId), 0)
                   - i.CurrentQuantity
               AS DECIMAL(18,4))
        FROM   dbo.WaterRawMaterialItems i
    )
    SELECT WaterRawMaterialItemId, FarmId,
           ToDraw = CASE WHEN ToDraw < 0 THEN 0 ELSE ToDraw END
    INTO   #drawdown
    FROM   Consumed
    WHERE  ToDraw > 0;

    -- Oldest lot first (FIFO) — the only defensible reading of history we have,
    -- since nothing recorded which lot each past usage actually came from.
    ;WITH Ordered AS (
        SELECT p.WaterRawMaterialPurchaseId,
               p.WaterRawMaterialItemId,
               p.Quantity,
               Mult      = ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1),
               AvailProd = p.Quantity * ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1),
               RunningTotal = SUM(p.Quantity * ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1)) OVER (
                                  PARTITION BY p.WaterRawMaterialItemId
                                  ORDER BY p.PurchaseDate ASC, p.WaterRawMaterialPurchaseId ASC
                                  ROWS UNBOUNDED PRECEDING)
        FROM   dbo.WaterRawMaterialPurchases p
        JOIN   #drawdown d ON d.WaterRawMaterialItemId = p.WaterRawMaterialItemId AND d.FarmId = p.FarmId
    )
    UPDATE p
    SET    p.RemainingQuantity =
               CASE
                   -- Lot sits entirely inside the consumed span — fully drawn.
                   WHEN o.RunningTotal <= d.ToDraw THEN 0
                   -- Consumption stops inside this lot — leave the remainder.
                   WHEN o.RunningTotal - o.AvailProd < d.ToDraw
                        THEN CAST((o.RunningTotal - d.ToDraw) / o.Mult AS DECIMAL(14,3))
                   -- Lot is entirely after the consumed span — untouched.
                   ELSE p.RemainingQuantity
               END
    FROM   dbo.WaterRawMaterialPurchases p
    JOIN   Ordered  o ON o.WaterRawMaterialPurchaseId = p.WaterRawMaterialPurchaseId
    JOIN   #drawdown d ON d.WaterRawMaterialItemId = p.WaterRawMaterialItemId AND d.FarmId = p.FarmId;

    DROP TABLE #drawdown;

    ALTER TABLE dbo.WaterRawMaterialPurchases
        ALTER COLUMN RemainingQuantity DECIMAL(14,3) NOT NULL;

    PRINT '187: RemainingQuantity backfilled and set NOT NULL.';
END
GO

-- New purchases start full. Kept as a default rather than pushed into every
-- insert path, so a purchase recorded by any route becomes a usable lot.
IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_WaterRMPurchase_Remaining')
BEGIN
    ALTER TABLE dbo.WaterRawMaterialPurchases
        ADD CONSTRAINT DF_WaterRMPurchase_Remaining DEFAULT (0) FOR RemainingQuantity;
    PRINT '187: added DF_WaterRMPurchase_Remaining.';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_WaterRMPurchase_ItemRemaining')
BEGIN
    CREATE INDEX IX_WaterRMPurchase_ItemRemaining
        ON dbo.WaterRawMaterialPurchases (WaterRawMaterialItemId, FarmId)
        INCLUDE (RemainingQuantity, UnitCost, PurchaseDate, ProductionUnitsPerPurchaseUnit);
    PRINT '187: added IX_WaterRMPurchase_ItemRemaining.';
END
GO

-- -----------------------------------------------------------------------------
-- 3. WaterRawMaterialUsageBatch — which lot(s) a usage row drew from.
-- -----------------------------------------------------------------------------
-- QuantityDrawn is in PURCHASE units, matching RemainingQuantity, so a reversal
-- can restore a lot with a plain `RemainingQuantity += SUM(QuantityDrawn)`.
-- Poultry stored these in production units at first (156) and had to undo it
-- (159) precisely because that made reversal wrong.
IF OBJECT_ID('dbo.WaterRawMaterialUsageBatch', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterRawMaterialUsageBatch (
        WaterRawMaterialUsageBatchId INT IDENTITY(1,1) PRIMARY KEY,
        WaterRawMaterialUsageId      INT           NOT NULL,
        WaterRawMaterialPurchaseId   INT           NOT NULL,
        QuantityDrawn                DECIMAL(14,3) NOT NULL,   -- PURCHASE units
        UnitCostAtDraw               DECIMAL(14,2) NOT NULL,   -- per PURCHASE unit
        CreatedAt                    DATETIME2     NOT NULL
            CONSTRAINT DF_WaterRMUsageBatch_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_WaterRMUsageBatch_Usage FOREIGN KEY (WaterRawMaterialUsageId)
            REFERENCES dbo.WaterRawMaterialUsage (WaterRawMaterialUsageId) ON DELETE CASCADE,
        CONSTRAINT FK_WaterRMUsageBatch_Purchase FOREIGN KEY (WaterRawMaterialPurchaseId)
            REFERENCES dbo.WaterRawMaterialPurchases (WaterRawMaterialPurchaseId)
    );
    CREATE INDEX IX_WaterRMUsageBatch_Usage    ON dbo.WaterRawMaterialUsageBatch (WaterRawMaterialUsageId);
    CREATE INDEX IX_WaterRMUsageBatch_Purchase ON dbo.WaterRawMaterialUsageBatch (WaterRawMaterialPurchaseId);
    PRINT '187: created WaterRawMaterialUsageBatch.';
END
GO

-- -----------------------------------------------------------------------------
-- 4. Verification report — run this after applying and eyeball the deltas.
--    Every item should show LotStockProd <= CurrentQuantity, with the gap being
--    stock that arrived by adjustment (and so has no lot to draw from).
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_LotReconciliation
    @FarmId NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.FarmId,
           i.WaterRawMaterialItemId,
           i.ItemName,
           i.UnitOfMeasure,
           i.UsageMethod,
           i.CurrentQuantity,
           LotStockProd = ISNULL((SELECT SUM(p.RemainingQuantity * ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1))
                                  FROM   dbo.WaterRawMaterialPurchases p
                                  WHERE  p.WaterRawMaterialItemId = i.WaterRawMaterialItemId AND p.FarmId = i.FarmId), 0),
           AdjustedIn   = ISNULL((SELECT SUM(a.Quantity)
                                  FROM   dbo.WaterRawMaterialAdjustments a
                                  WHERE  a.WaterRawMaterialItemId = i.WaterRawMaterialItemId AND a.FarmId = i.FarmId), 0),
           OpenLots     = ISNULL((SELECT COUNT(*)
                                  FROM   dbo.WaterRawMaterialPurchases p
                                  WHERE  p.WaterRawMaterialItemId = i.WaterRawMaterialItemId AND p.FarmId = i.FarmId
                                    AND  p.RemainingQuantity > 0), 0)
    FROM   dbo.WaterRawMaterialItems i
    WHERE  (@FarmId IS NULL OR i.FarmId = @FarmId)
    ORDER  BY i.FarmId, i.ItemName;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_LotReconciliation TO [Techretainer];
    PRINT '187: granted EXECUTE on spWaterRawMaterialItem_LotReconciliation to Techretainer.';
END
GO

PRINT '187_WaterRawMaterialLotCosting.sql complete.';
GO

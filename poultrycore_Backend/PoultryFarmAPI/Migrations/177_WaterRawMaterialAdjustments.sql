-- =============================================================================
-- 177_WaterRawMaterialAdjustments.sql
-- Manual stock adjustments for Water raw materials & supplies (parity with the
-- Poultry adjustment ledger, migration 174).
--
-- Lets owners increase/decrease a raw material or supply directly from the Water
-- "New stock entry" popup, without a purchase (no Expense posting) or production
-- usage (no variance). Side-effect-free: only the item's CurrentQuantity moves.
--
-- IMPORTANT: this also re-defines spWaterRawMaterialItem_RecalculateStock (176)
-- to ADD the adjustments term, so recalculating no longer wipes adjustments.
--
-- Additive + idempotent. Grants EXECUTE to `Techretainer`.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Ledger table
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterRawMaterialAdjustments', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterRawMaterialAdjustments (
        WaterRawMaterialAdjustmentId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                       NVARCHAR(450) NOT NULL,
        WaterRawMaterialItemId       INT           NOT NULL,
        AdjustedDate                 DATETIME2     NOT NULL CONSTRAINT DF_WaterRMAdj_Date      DEFAULT (SYSUTCDATETIME()),
        Quantity                     DECIMAL(14,3) NOT NULL,   -- signed delta: + increase, - decrease
        UnitCost                     DECIMAL(14,2) NULL,       -- optional valuation
        MovementType                 NVARCHAR(30)  NULL,       -- display label
        Note                         NVARCHAR(500) NULL,
        CreatedBy                    NVARCHAR(450) NULL,
        CreatedAt                    DATETIME2     NOT NULL CONSTRAINT DF_WaterRMAdj_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_WaterRMAdj_Item FOREIGN KEY (WaterRawMaterialItemId) REFERENCES dbo.WaterRawMaterialItems (WaterRawMaterialItemId)
    );
    CREATE INDEX IX_WaterRMAdj_FarmId ON dbo.WaterRawMaterialAdjustments (FarmId);
    CREATE INDEX IX_WaterRMAdj_Item   ON dbo.WaterRawMaterialAdjustments (WaterRawMaterialItemId);
    CREATE INDEX IX_WaterRMAdj_Date   ON dbo.WaterRawMaterialAdjustments (AdjustedDate);
END
GO

-- -----------------------------------------------------------------------------
-- 2. Apply an adjustment: record it + move CurrentQuantity (floored at 0).
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_Adjust
    @FarmId                 NVARCHAR(450),
    @WaterRawMaterialItemId INT,
    @Quantity               DECIMAL(14,3),        -- signed delta
    @UnitCost               DECIMAL(14,2) = NULL,
    @MovementType           NVARCHAR(30)  = NULL,
    @Note                   NVARCHAR(500) = NULL,
    @CreatedBy              NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.WaterRawMaterialItems
                   WHERE WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId)
    BEGIN
        RAISERROR('Raw material item not found for this company.', 16, 1);
        RETURN;
    END

    IF @Quantity = 0
    BEGIN
        RAISERROR('Adjustment quantity cannot be zero.', 16, 1);
        RETURN;
    END

    BEGIN TRAN;

        INSERT INTO dbo.WaterRawMaterialAdjustments
            (FarmId, WaterRawMaterialItemId, Quantity, UnitCost, MovementType, Note, CreatedBy)
        VALUES
            (@FarmId, @WaterRawMaterialItemId, @Quantity, @UnitCost, @MovementType, @Note, @CreatedBy);

        DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

        UPDATE dbo.WaterRawMaterialItems
        SET    CurrentQuantity = CASE WHEN CurrentQuantity + @Quantity < 0 THEN 0 ELSE CurrentQuantity + @Quantity END,
               UpdatedAt       = SYSUTCDATETIME()
        WHERE  WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;

    COMMIT;

    SELECT @NewId AS WaterRawMaterialAdjustmentId,
           (SELECT CurrentQuantity FROM dbo.WaterRawMaterialItems
            WHERE WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId) AS CurrentQuantity;
END
GO

-- -----------------------------------------------------------------------------
-- 3. List adjustments (for the Water raw-materials Usage History tab).
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialAdjustment_GetAll
    @FarmId   NVARCHAR(450),
    @FromDate DATETIME2 = NULL,
    @ToDate   DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.WaterRawMaterialAdjustmentId,
           a.FarmId,
           a.WaterRawMaterialItemId,
           i.ItemName,
           i.Category,
           i.UnitOfMeasure,
           a.AdjustedDate,
           a.Quantity,
           a.UnitCost,
           a.MovementType,
           a.Note,
           a.CreatedBy,
           a.CreatedAt
    FROM   dbo.WaterRawMaterialAdjustments a
    INNER JOIN dbo.WaterRawMaterialItems i
            ON i.WaterRawMaterialItemId = a.WaterRawMaterialItemId
    WHERE  a.FarmId = @FarmId
      AND  (@FromDate IS NULL OR a.AdjustedDate >= @FromDate)
      AND  (@ToDate   IS NULL OR a.AdjustedDate <  DATEADD(DAY, 1, @ToDate))
    ORDER  BY a.AdjustedDate DESC, a.WaterRawMaterialAdjustmentId DESC;
END
GO

-- -----------------------------------------------------------------------------
-- 4. Recalculate — now includes the adjustments term (supersedes 176).
--      CurrentQuantity = SUM(purchase prod units) - SUM(usage) + SUM(adjustments)
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_RecalculateStock
    @FarmId                 NVARCHAR(450),
    @WaterRawMaterialItemId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Expected AS (
        SELECT i.WaterRawMaterialItemId,
               i.CurrentQuantity AS OldQuantity,
               CAST(
                   ISNULL((SELECT SUM(p.Quantity * ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1))
                           FROM   dbo.WaterRawMaterialPurchases p
                           WHERE  p.WaterRawMaterialItemId = i.WaterRawMaterialItemId AND p.FarmId = i.FarmId), 0)
                 - ISNULL((SELECT SUM(u.QuantityUsed)
                           FROM   dbo.WaterRawMaterialUsage u
                           WHERE  u.WaterRawMaterialItemId = i.WaterRawMaterialItemId AND u.FarmId = i.FarmId), 0)
                 + ISNULL((SELECT SUM(a.Quantity)
                           FROM   dbo.WaterRawMaterialAdjustments a
                           WHERE  a.WaterRawMaterialItemId = i.WaterRawMaterialItemId AND a.FarmId = i.FarmId), 0)
               AS DECIMAL(14,3)) AS RawExpected
        FROM   dbo.WaterRawMaterialItems i
        WHERE  i.FarmId = @FarmId
          AND  (@WaterRawMaterialItemId IS NULL OR i.WaterRawMaterialItemId = @WaterRawMaterialItemId)
    )
    SELECT WaterRawMaterialItemId,
           OldQuantity,
           CASE WHEN RawExpected < 0 THEN 0 ELSE RawExpected END AS NewQuantity
    INTO   #calc
    FROM   Expected;

    UPDATE i
    SET    CurrentQuantity = c.NewQuantity, UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.WaterRawMaterialItems i
    INNER JOIN #calc c ON c.WaterRawMaterialItemId = i.WaterRawMaterialItemId
    WHERE  i.FarmId = @FarmId AND i.CurrentQuantity <> c.NewQuantity;

    SELECT c.WaterRawMaterialItemId,
           i.ItemName,
           i.Category,
           i.UnitOfMeasure,
           c.OldQuantity,
           c.NewQuantity,
           CAST(c.NewQuantity - c.OldQuantity AS DECIMAL(14,3)) AS Delta
    FROM   #calc c
    INNER JOIN dbo.WaterRawMaterialItems i ON i.WaterRawMaterialItemId = c.WaterRawMaterialItemId
    ORDER  BY (CASE WHEN c.OldQuantity <> c.NewQuantity THEN 0 ELSE 1 END), i.ItemName;

    DROP TABLE #calc;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_Adjust             TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterRawMaterialAdjustment_GetAll       TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_RecalculateStock   TO [Techretainer];
    PRINT '177: granted EXECUTE on water adjustment + recalc SPs to Techretainer.';
END
GO

PRINT '177_WaterRawMaterialAdjustments.sql complete.';
GO

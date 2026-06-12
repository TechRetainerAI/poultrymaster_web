/* =============================================================================
   063_AddWaterProductionRecipesAndUsage.sql

   Prompt 1: "Product Details Page + Production Batch Raw Materials Usage".

   Goal: let each finished water product carry a Production Recipe (bill of
   materials) that lists the raw materials normally needed to produce one
   "output unit" (e.g. one bag of sachet water). When a production batch is
   recorded the recipe auto-populates an expected-vs-actual usage table; on
   approval, stock is moved both ways:
     +  Finished goods Restock (already in 039)
     -  Raw materials decrement against WaterRawMaterialItems.CurrentQuantity

   Schema design notes
   --------------------
   * Recipes link a finished WaterProductId to recipe items.
   * Recipe items reference dbo.WaterRawMaterialItems (the existing raw-material
     catalog used by the Raw Materials page). The prompt suggests "raw materials
     are products with ProductType=RawMaterial or PackagingMaterial", but the
     existing data model keeps raw-materials in their own table — we go with
     that to avoid a destructive data migration. A ProductType column is still
     added to WaterProducts so the UI can hide raw-material-ish entries from
     sales pickers and only offer recipes for FinishedGood products.
   * Actual usage rows reuse dbo.WaterRawMaterialUsage (created in 043) — we
     just add UnitCost + TotalCost so the batch can roll up raw-material cost.
   * Approve+Reopen are upgraded to also move raw-material stock.

   Idempotent: every block guards on sys.columns / sys.procedures / OBJECT_ID.
   ============================================================================= */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. WaterProducts.ProductType
-- -----------------------------------------------------------------------------
-- Existing rows default to 'FinishedGood' so legacy data keeps appearing in
-- Sales pickers. Values: FinishedGood | RawMaterial | PackagingMaterial | Other.
IF COL_LENGTH('dbo.WaterProducts', 'ProductType') IS NULL
BEGIN
    PRINT 'Adding WaterProducts.ProductType';
    ALTER TABLE dbo.WaterProducts
        ADD ProductType NVARCHAR(30) NOT NULL
            CONSTRAINT DF_WaterProducts_ProductType DEFAULT ('FinishedGood') WITH VALUES;
END
GO

-- -----------------------------------------------------------------------------
-- 2. WaterProductionRecipes — one (default) recipe per finished product
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterProductionRecipes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterProductionRecipes (
        WaterProductionRecipeId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450) NOT NULL,
        WaterProductId          INT           NOT NULL,
        RecipeName              NVARCHAR(150) NOT NULL CONSTRAINT DF_WaterProductionRecipes_Name DEFAULT ('Default'),
        IsDefault               BIT           NOT NULL CONSTRAINT DF_WaterProductionRecipes_IsDefault DEFAULT (1),
        IsActive                BIT           NOT NULL CONSTRAINT DF_WaterProductionRecipes_IsActive DEFAULT (1),
        Notes                   NVARCHAR(500) NULL,
        CreatedBy               NVARCHAR(450) NULL,
        CreatedAt               DATETIME2     NOT NULL CONSTRAINT DF_WaterProductionRecipes_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedBy               NVARCHAR(450) NULL,
        UpdatedAt               DATETIME2     NULL,
        CONSTRAINT FK_WaterProductionRecipes_Product FOREIGN KEY (WaterProductId)
            REFERENCES dbo.WaterProducts (WaterProductId)
    );
    CREATE INDEX IX_WaterProductionRecipes_FarmId    ON dbo.WaterProductionRecipes (FarmId);
    CREATE INDEX IX_WaterProductionRecipes_ProductId ON dbo.WaterProductionRecipes (WaterProductId);
    -- Enforce a single default recipe per product per farm.
    CREATE UNIQUE INDEX UX_WaterProductionRecipes_DefaultPerProduct
        ON dbo.WaterProductionRecipes (FarmId, WaterProductId)
        WHERE IsDefault = 1 AND IsActive = 1;
END
GO

-- -----------------------------------------------------------------------------
-- 3. WaterProductionRecipeItems — one row per raw material in the recipe
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterProductionRecipeItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterProductionRecipeItems (
        WaterProductionRecipeItemId INT IDENTITY(1,1) PRIMARY KEY,
        WaterProductionRecipeId     INT           NOT NULL,
        WaterRawMaterialItemId      INT           NOT NULL,
        -- How much of this raw material is needed PER ONE OUTPUT UNIT (typically
        -- one bag of finished product). E.g. 0.01 rolls / bag.
        QuantityPerOutputUnit       DECIMAL(14,4) NOT NULL CONSTRAINT DF_WaterProductionRecipeItems_QtyPer DEFAULT (0),
        OutputUnit                  NVARCHAR(30)  NOT NULL CONSTRAINT DF_WaterProductionRecipeItems_Output DEFAULT ('bag'),
        WasteAllowancePercent       DECIMAL(6,3)  NOT NULL CONSTRAINT DF_WaterProductionRecipeItems_Waste DEFAULT (0),
        IsOptional                  BIT           NOT NULL CONSTRAINT DF_WaterProductionRecipeItems_IsOpt DEFAULT (0),
        DisplayOrder                INT           NOT NULL CONSTRAINT DF_WaterProductionRecipeItems_Order DEFAULT (0),
        Notes                       NVARCHAR(300) NULL,
        CreatedAt                   DATETIME2     NOT NULL CONSTRAINT DF_WaterProductionRecipeItems_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                   DATETIME2     NULL,
        CONSTRAINT FK_WaterProductionRecipeItems_Recipe FOREIGN KEY (WaterProductionRecipeId)
            REFERENCES dbo.WaterProductionRecipes (WaterProductionRecipeId) ON DELETE CASCADE,
        CONSTRAINT FK_WaterProductionRecipeItems_Material FOREIGN KEY (WaterRawMaterialItemId)
            REFERENCES dbo.WaterRawMaterialItems (WaterRawMaterialItemId)
    );
    CREATE INDEX IX_WaterProductionRecipeItems_Recipe   ON dbo.WaterProductionRecipeItems (WaterProductionRecipeId);
    CREATE INDEX IX_WaterProductionRecipeItems_Material ON dbo.WaterProductionRecipeItems (WaterRawMaterialItemId);
END
GO

-- -----------------------------------------------------------------------------
-- 4. WaterRawMaterialUsage: cost columns for batch roll-up
-- -----------------------------------------------------------------------------
-- The table was created in 043 with QuantityUsed / ExpectedQuantityUsed but no
-- cost. Add UnitCost (the buying price applied for this usage event) and a
-- computed TotalCost so the production batch can sum raw-material cost.
IF COL_LENGTH('dbo.WaterRawMaterialUsage', 'UnitCost') IS NULL
BEGIN
    PRINT 'Adding WaterRawMaterialUsage.UnitCost';
    ALTER TABLE dbo.WaterRawMaterialUsage
        ADD UnitCost DECIMAL(14,4) NULL;
END
GO

IF COL_LENGTH('dbo.WaterRawMaterialUsage', 'TotalCost') IS NULL
BEGIN
    PRINT 'Adding WaterRawMaterialUsage.TotalCost (computed)';
    ALTER TABLE dbo.WaterRawMaterialUsage
        ADD TotalCost AS (QuantityUsed * ISNULL(UnitCost, 0)) PERSISTED;
END
GO

-- -----------------------------------------------------------------------------
-- 5. WaterProductionBatches.RawMaterialCost
-- -----------------------------------------------------------------------------
-- Denormalized total of raw-material cost for this batch. Populated by the
-- Insert / Update SPs after writing usage rows. Frontends sum
-- TotalProductionCost (= electricity+fuel+labor+other) + RawMaterialCost
-- to display the all-in total — we don't redefine the existing PERSISTED
-- computed column to avoid breaking dependent views and reports.
IF COL_LENGTH('dbo.WaterProductionBatches', 'RawMaterialCost') IS NULL
BEGIN
    PRINT 'Adding WaterProductionBatches.RawMaterialCost';
    ALTER TABLE dbo.WaterProductionBatches
        ADD RawMaterialCost DECIMAL(14,2) NOT NULL
            CONSTRAINT DF_WaterProductionBatches_RawMaterialCost DEFAULT (0) WITH VALUES;
END
GO

-- =============================================================================
-- 6. Recipe SPs
-- =============================================================================

-- Returns the active default recipe + items for a finished product. Empty list
-- when no recipe exists yet — caller treats that as "user hasn't set one up".
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

    -- Items, with the joined material name / unit / latest known cost so the
    -- UI can show "expected qty / unit / available stock / estimated cost"
    -- without a second round-trip.
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
            -- Best-effort latest unit cost from the most recent purchase. NULL
            -- when this material has never been purchased.
            (SELECT TOP 1 p.UnitCost
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

-- Upsert the (default) recipe for a finished product and replace its items.
-- Items come in as a JSON array so we can do everything in one SP call:
-- [{ "waterRawMaterialItemId": 7, "quantityPerOutputUnit": 0.01,
--    "outputUnit": "bag", "wasteAllowancePercent": 0,
--    "isOptional": false, "displayOrder": 0, "notes": null }, ... ]
CREATE OR ALTER PROCEDURE dbo.spWaterProductionRecipe_Upsert
    @FarmId         NVARCHAR(450),
    @WaterProductId INT,
    @RecipeName     NVARCHAR(150)  = N'Default',
    @Notes          NVARCHAR(500)  = NULL,
    @ItemsJson      NVARCHAR(MAX)  = NULL,
    @UpdatedBy      NVARCHAR(450)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @RecipeId INT;

    SELECT TOP 1 @RecipeId = WaterProductionRecipeId
    FROM   dbo.WaterProductionRecipes
    WHERE  FarmId = @FarmId AND WaterProductId = @WaterProductId AND IsActive = 1
    ORDER  BY IsDefault DESC, WaterProductionRecipeId DESC;

    IF @RecipeId IS NULL
    BEGIN
        INSERT INTO dbo.WaterProductionRecipes
            (FarmId, WaterProductId, RecipeName, IsDefault, IsActive, Notes, CreatedBy, UpdatedBy)
        VALUES
            (@FarmId, @WaterProductId, @RecipeName, 1, 1, @Notes, @UpdatedBy, @UpdatedBy);

        SET @RecipeId = CAST(SCOPE_IDENTITY() AS INT);
    END
    ELSE
    BEGIN
        UPDATE dbo.WaterProductionRecipes
        SET    RecipeName = @RecipeName,
               Notes      = @Notes,
               UpdatedBy  = @UpdatedBy,
               UpdatedAt  = SYSUTCDATETIME()
        WHERE  WaterProductionRecipeId = @RecipeId;

        DELETE FROM dbo.WaterProductionRecipeItems
        WHERE  WaterProductionRecipeId = @RecipeId;
    END

    IF @ItemsJson IS NOT NULL AND LEN(@ItemsJson) > 2
    BEGIN
        INSERT INTO dbo.WaterProductionRecipeItems
            (WaterProductionRecipeId, WaterRawMaterialItemId, QuantityPerOutputUnit,
             OutputUnit, WasteAllowancePercent, IsOptional, DisplayOrder, Notes)
        SELECT
            @RecipeId,
            j.WaterRawMaterialItemId,
            ISNULL(j.QuantityPerOutputUnit, 0),
            ISNULL(NULLIF(j.OutputUnit, N''), N'bag'),
            ISNULL(j.WasteAllowancePercent, 0),
            ISNULL(j.IsOptional, 0),
            ISNULL(j.DisplayOrder, 0),
            j.Notes
        FROM OPENJSON(@ItemsJson)
        WITH (
            WaterRawMaterialItemId INT             '$.waterRawMaterialItemId',
            QuantityPerOutputUnit  DECIMAL(14,4)   '$.quantityPerOutputUnit',
            OutputUnit             NVARCHAR(30)    '$.outputUnit',
            WasteAllowancePercent  DECIMAL(6,3)    '$.wasteAllowancePercent',
            IsOptional             BIT             '$.isOptional',
            DisplayOrder           INT             '$.displayOrder',
            Notes                  NVARCHAR(300)   '$.notes'
        ) j
        WHERE j.WaterRawMaterialItemId IS NOT NULL;
    END

    COMMIT TRANSACTION;

    SELECT @RecipeId AS WaterProductionRecipeId;
END
GO

-- Soft delete (mark inactive); caller deletes via API but we keep history
-- because production batches may have already referenced this recipe.
CREATE OR ALTER PROCEDURE dbo.spWaterProductionRecipe_Delete
    @FarmId                  NVARCHAR(450),
    @WaterProductionRecipeId INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterProductionRecipes
    SET    IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterProductionRecipeId = @WaterProductionRecipeId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- 7. Usage SPs (read-only) — Raw Materials "Usage history" tab and batch detail
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialUsage_GetByBatch
    @FarmId                 NVARCHAR(450),
    @WaterProductionBatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  u.WaterRawMaterialUsageId,
            u.FarmId,
            u.WaterRawMaterialItemId,
            mi.ItemName        AS ItemName,
            mi.UnitOfMeasure   AS UnitOfMeasure,
            mi.CurrentQuantity AS CurrentStock,
            u.WaterProductionBatchId,
            b.BatchNumber      AS BatchNumber,
            p.Name             AS FinishedProductName,
            u.UsedDate,
            u.QuantityUsed,
            u.ExpectedQuantityUsed,
            u.Variance,
            u.VarianceReason,
            u.UnitCost,
            u.TotalCost,
            u.UsedByStaffId,
            u.Notes,
            u.CreatedAt
    FROM    dbo.WaterRawMaterialUsage u
    JOIN    dbo.WaterRawMaterialItems mi ON mi.WaterRawMaterialItemId = u.WaterRawMaterialItemId
    LEFT JOIN dbo.WaterProductionBatches b ON b.WaterProductionBatchId = u.WaterProductionBatchId
    LEFT JOIN dbo.WaterProducts p          ON p.WaterProductId = b.WaterProductId
    WHERE   u.FarmId = @FarmId
      AND   u.WaterProductionBatchId = @WaterProductionBatchId
    ORDER  BY mi.ItemName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialUsage_GetHistory
    @FarmId                 NVARCHAR(450),
    @WaterRawMaterialItemId INT          = NULL,
    @FromDate               DATE         = NULL,
    @ToDate                 DATE         = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  u.WaterRawMaterialUsageId,
            u.FarmId,
            u.WaterRawMaterialItemId,
            mi.ItemName        AS ItemName,
            mi.UnitOfMeasure   AS UnitOfMeasure,
            u.WaterProductionBatchId,
            b.BatchNumber      AS BatchNumber,
            p.Name             AS FinishedProductName,
            u.UsedDate,
            u.QuantityUsed,
            u.ExpectedQuantityUsed,
            u.Variance,
            u.UnitCost,
            u.TotalCost,
            u.Notes,
            u.CreatedAt
    FROM    dbo.WaterRawMaterialUsage u
    JOIN    dbo.WaterRawMaterialItems mi ON mi.WaterRawMaterialItemId = u.WaterRawMaterialItemId
    LEFT JOIN dbo.WaterProductionBatches b ON b.WaterProductionBatchId = u.WaterProductionBatchId
    LEFT JOIN dbo.WaterProducts p          ON p.WaterProductId = b.WaterProductId
    WHERE   u.FarmId = @FarmId
      AND   (@WaterRawMaterialItemId IS NULL OR u.WaterRawMaterialItemId = @WaterRawMaterialItemId)
      AND   (@FromDate IS NULL OR u.UsedDate >= @FromDate)
      AND   (@ToDate   IS NULL OR u.UsedDate <  DATEADD(day, 1, @ToDate))
    ORDER  BY u.UsedDate DESC, u.WaterRawMaterialUsageId DESC;
END
GO

-- =============================================================================
-- 8. Production batch SPs — drop-in replacements that now accept a usage payload
-- =============================================================================
-- These supersede the bodies defined in 039 + 059. Approve also moves raw
-- material stock; Reopen reverses it. The legacy POST/PUT signatures (no
-- @MaterialsUsedJson) still work because the param is optional.

CREATE OR ALTER PROCEDURE dbo.spWaterProductionBatch_Insert
    @FarmId                   NVARCHAR(450),
    @BatchNumber              NVARCHAR(60),
    @ProductionDate           DATE,
    @Shift                    NVARCHAR(20)  = 'FullDay',
    @WaterMachineId           INT           = NULL,
    @WaterBoreholeId          INT           = NULL,
    @OperatorStaffId          INT           = NULL,
    @StartTime                DATETIME2     = NULL,
    @EndTime                  DATETIME2     = NULL,
    @WaterProductId           INT,
    @BagsProduced             INT           = 0,
    @SachetsPerBag            INT           = 30,
    @LooseSachetsProduced     INT           = 0,
    @RejectedSachets          INT           = 0,
    @DamagedBags              INT           = 0,
    @PackagingRollsUsed       INT           = 0,
    @EstimatedWaterUsedLitres INT           = NULL,
    @ElectricityCost          DECIMAL(14,2) = 0,
    @FuelCost                 DECIMAL(14,2) = 0,
    @LaborCost                DECIMAL(14,2) = 0,
    @OtherProductionCost      DECIMAL(14,2) = 0,
    @QualityStatus            NVARCHAR(20)  = 'Pending',
    @QualityPHLevel           DECIMAL(5,2)  = NULL,
    @QualityChlorinePpm       DECIMAL(8,4)  = NULL,
    @QualityTurbidity         DECIMAL(8,4)  = NULL,
    @QualityTDS               INT           = NULL,
    @QualityNotes             NVARCHAR(500) = NULL,
    @Notes                    NVARCHAR(1000) = NULL,
    @CreatedBy                NVARCHAR(450) = NULL,
    -- New: actual raw materials consumed for this batch (Draft, not yet
    -- decremented from inventory). JSON array of:
    --   { "waterRawMaterialItemId": 7,
    --     "quantityUsed": 1.0,
    --     "expectedQuantityUsed": 1.0,
    --     "unitCost": 10.0,
    --     "varianceReason": null,
    --     "notes": null }
    @MaterialsUsedJson        NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@BagsProduced < 0)
    BEGIN RAISERROR('BagsProduced cannot be negative.', 16, 1); RETURN; END
    IF (@SachetsPerBag <= 0) SET @SachetsPerBag = 30;
    IF (@DamagedBags < 0 OR @DamagedBags > @BagsProduced)
    BEGIN RAISERROR('DamagedBags must be between 0 and BagsProduced.', 16, 1); RETURN; END

    BEGIN TRANSACTION;

    INSERT INTO dbo.WaterProductionBatches (
        FarmId, BatchNumber, ProductionDate, Shift, WaterMachineId, WaterBoreholeId,
        OperatorStaffId, StartTime, EndTime, WaterProductId, BagsProduced, SachetsPerBag,
        LooseSachetsProduced, RejectedSachets, DamagedBags, PackagingRollsUsed,
        EstimatedWaterUsedLitres, ElectricityCost, FuelCost, LaborCost, OtherProductionCost,
        QualityStatus, QualityPHLevel, QualityChlorinePpm, QualityTurbidity, QualityTDS,
        QualityNotes, Notes, Status, CreatedBy
    )
    VALUES (
        @FarmId, @BatchNumber, @ProductionDate, @Shift, @WaterMachineId, @WaterBoreholeId,
        @OperatorStaffId, @StartTime, @EndTime, @WaterProductId, @BagsProduced, @SachetsPerBag,
        @LooseSachetsProduced, @RejectedSachets, @DamagedBags, @PackagingRollsUsed,
        @EstimatedWaterUsedLitres, @ElectricityCost, @FuelCost, @LaborCost, @OtherProductionCost,
        @QualityStatus, @QualityPHLevel, @QualityChlorinePpm, @QualityTurbidity, @QualityTDS,
        @QualityNotes, @Notes, 'Draft', @CreatedBy
    );

    DECLARE @BatchId INT = CAST(SCOPE_IDENTITY() AS INT);

    IF @MaterialsUsedJson IS NOT NULL AND LEN(@MaterialsUsedJson) > 2
    BEGIN
        INSERT INTO dbo.WaterRawMaterialUsage
            (FarmId, WaterRawMaterialItemId, WaterProductionBatchId, UsedDate,
             QuantityUsed, ExpectedQuantityUsed, UnitCost, VarianceReason, Notes, CreatedBy)
        SELECT
            @FarmId,
            j.WaterRawMaterialItemId,
            @BatchId,
            ISNULL(j.UsedDate, CAST(@ProductionDate AS DATETIME2)),
            ISNULL(j.QuantityUsed, 0),
            j.ExpectedQuantityUsed,
            j.UnitCost,
            j.VarianceReason,
            j.Notes,
            @CreatedBy
        FROM OPENJSON(@MaterialsUsedJson)
        WITH (
            WaterRawMaterialItemId INT             '$.waterRawMaterialItemId',
            QuantityUsed           DECIMAL(14,3)   '$.quantityUsed',
            ExpectedQuantityUsed   DECIMAL(14,3)   '$.expectedQuantityUsed',
            UnitCost               DECIMAL(14,4)   '$.unitCost',
            VarianceReason         NVARCHAR(500)   '$.varianceReason',
            Notes                  NVARCHAR(500)   '$.notes',
            UsedDate               DATETIME2       '$.usedDate'
        ) j
        WHERE j.WaterRawMaterialItemId IS NOT NULL;

        -- Roll the raw-material cost up onto the batch.
        UPDATE b
        SET    b.RawMaterialCost = ISNULL((
                   SELECT SUM(u.TotalCost)
                   FROM   dbo.WaterRawMaterialUsage u
                   WHERE  u.WaterProductionBatchId = @BatchId), 0)
        FROM   dbo.WaterProductionBatches b
        WHERE  b.WaterProductionBatchId = @BatchId;
    END

    COMMIT TRANSACTION;

    SELECT @BatchId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProductionBatch_Update
    @WaterProductionBatchId   INT,
    @FarmId                   NVARCHAR(450),
    @BatchNumber              NVARCHAR(60),
    @ProductionDate           DATE,
    @Shift                    NVARCHAR(20),
    @WaterMachineId           INT           = NULL,
    @WaterBoreholeId          INT           = NULL,
    @OperatorStaffId          INT           = NULL,
    @StartTime                DATETIME2     = NULL,
    @EndTime                  DATETIME2     = NULL,
    @WaterProductId           INT,
    @BagsProduced             INT,
    @SachetsPerBag            INT,
    @LooseSachetsProduced     INT,
    @RejectedSachets          INT,
    @DamagedBags              INT,
    @PackagingRollsUsed       INT,
    @EstimatedWaterUsedLitres INT           = NULL,
    @ElectricityCost          DECIMAL(14,2),
    @FuelCost                 DECIMAL(14,2),
    @LaborCost                DECIMAL(14,2),
    @OtherProductionCost      DECIMAL(14,2),
    @QualityStatus            NVARCHAR(20),
    @QualityPHLevel           DECIMAL(5,2)  = NULL,
    @QualityChlorinePpm       DECIMAL(8,4)  = NULL,
    @QualityTurbidity         DECIMAL(8,4)  = NULL,
    @QualityTDS               INT           = NULL,
    @QualityNotes             NVARCHAR(500) = NULL,
    @Notes                    NVARCHAR(1000) = NULL,
    @MaterialsUsedJson        NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.WaterProductionBatches
               WHERE WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        RAISERROR('Cannot edit an Approved production batch. Reopen it first.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    UPDATE dbo.WaterProductionBatches
    SET BatchNumber = @BatchNumber, ProductionDate = @ProductionDate, Shift = @Shift,
        WaterMachineId = @WaterMachineId, WaterBoreholeId = @WaterBoreholeId,
        OperatorStaffId = @OperatorStaffId, StartTime = @StartTime, EndTime = @EndTime,
        WaterProductId = @WaterProductId, BagsProduced = @BagsProduced,
        SachetsPerBag = @SachetsPerBag, LooseSachetsProduced = @LooseSachetsProduced,
        RejectedSachets = @RejectedSachets, DamagedBags = @DamagedBags,
        PackagingRollsUsed = @PackagingRollsUsed,
        EstimatedWaterUsedLitres = @EstimatedWaterUsedLitres,
        ElectricityCost = @ElectricityCost, FuelCost = @FuelCost,
        LaborCost = @LaborCost, OtherProductionCost = @OtherProductionCost,
        QualityStatus = @QualityStatus, QualityPHLevel = @QualityPHLevel,
        QualityChlorinePpm = @QualityChlorinePpm, QualityTurbidity = @QualityTurbidity,
        QualityTDS = @QualityTDS, QualityNotes = @QualityNotes, Notes = @Notes,
        UpdatedAt = SYSUTCDATETIME()
    WHERE WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;

    -- Replace usage rows when a payload is supplied. NULL payload means
    -- "leave usage rows alone" (legacy behavior).
    IF @MaterialsUsedJson IS NOT NULL
    BEGIN
        DELETE FROM dbo.WaterRawMaterialUsage
        WHERE  FarmId = @FarmId AND WaterProductionBatchId = @WaterProductionBatchId;

        IF LEN(@MaterialsUsedJson) > 2
        BEGIN
            INSERT INTO dbo.WaterRawMaterialUsage
                (FarmId, WaterRawMaterialItemId, WaterProductionBatchId, UsedDate,
                 QuantityUsed, ExpectedQuantityUsed, UnitCost, VarianceReason, Notes)
            SELECT
                @FarmId,
                j.WaterRawMaterialItemId,
                @WaterProductionBatchId,
                ISNULL(j.UsedDate, CAST(@ProductionDate AS DATETIME2)),
                ISNULL(j.QuantityUsed, 0),
                j.ExpectedQuantityUsed,
                j.UnitCost,
                j.VarianceReason,
                j.Notes
            FROM OPENJSON(@MaterialsUsedJson)
            WITH (
                WaterRawMaterialItemId INT             '$.waterRawMaterialItemId',
                QuantityUsed           DECIMAL(14,3)   '$.quantityUsed',
                ExpectedQuantityUsed   DECIMAL(14,3)   '$.expectedQuantityUsed',
                UnitCost               DECIMAL(14,4)   '$.unitCost',
                VarianceReason         NVARCHAR(500)   '$.varianceReason',
                Notes                  NVARCHAR(500)   '$.notes',
                UsedDate               DATETIME2       '$.usedDate'
            ) j
            WHERE j.WaterRawMaterialItemId IS NOT NULL;
        END

        UPDATE b
        SET    b.RawMaterialCost = ISNULL((
                   SELECT SUM(u.TotalCost)
                   FROM   dbo.WaterRawMaterialUsage u
                   WHERE  u.WaterProductionBatchId = @WaterProductionBatchId), 0)
        FROM   dbo.WaterProductionBatches b
        WHERE  b.WaterProductionBatchId = @WaterProductionBatchId;
    END

    COMMIT TRANSACTION;
END
GO

-- Approve: write Restock for finished goods (existing behavior) AND decrement
-- raw materials. Refuses if any required material would go negative.
CREATE OR ALTER PROCEDURE dbo.spWaterProductionBatch_Approve
    @WaterProductionBatchId INT,
    @FarmId                 NVARCHAR(450),
    @ApprovedBy             NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.WaterProductionBatches
               WHERE WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT WaterProductionBatchId, Status, ApprovedBy, ApprovedAt
        FROM dbo.WaterProductionBatches
        WHERE WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @Status       NVARCHAR(20),
            @ProductId    INT,
            @BagsProduced INT,
            @DamagedBags  INT,
            @TotalCost    DECIMAL(14,2),
            @RawMatCost   DECIMAL(14,2),
            @BatchNo      NVARCHAR(60);

    SELECT @Status = Status, @ProductId = WaterProductId,
           @BagsProduced = BagsProduced, @DamagedBags = DamagedBags,
           @TotalCost = TotalProductionCost,
           @RawMatCost = ISNULL(RawMaterialCost, 0),
           @BatchNo = BatchNumber
    FROM   dbo.WaterProductionBatches
    WHERE  WaterProductionBatchId = @WaterProductionBatchId
       AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL
    BEGIN RAISERROR('Production batch %d not found.', 16, 1, @WaterProductionBatchId); RETURN; END
    IF @Status <> 'Draft'
    BEGIN RAISERROR('Production batch cannot be approved from status %s.', 16, 1, @Status); RETURN; END

    -- Pre-check raw material availability. Fail fast with a readable message
    -- before we touch any rows.
    DECLARE @ShortName NVARCHAR(150), @ShortHave DECIMAL(14,3), @ShortNeed DECIMAL(14,3);
    SELECT TOP 1
           @ShortName = mi.ItemName,
           @ShortHave = mi.CurrentQuantity,
           @ShortNeed = u.QuantityUsed
    FROM   dbo.WaterRawMaterialUsage u
    JOIN   dbo.WaterRawMaterialItems mi ON mi.WaterRawMaterialItemId = u.WaterRawMaterialItemId
    WHERE  u.FarmId = @FarmId
      AND  u.WaterProductionBatchId = @WaterProductionBatchId
      AND  u.QuantityUsed > mi.CurrentQuantity;

    IF @ShortName IS NOT NULL
    BEGIN
        DECLARE @msg NVARCHAR(400) = CONCAT(
            'Not enough stock of "', @ShortName, '". Available: ',
            CAST(@ShortHave AS NVARCHAR(30)), ', needed: ',
            CAST(@ShortNeed AS NVARCHAR(30)),
            '. Record a purchase or reduce the actual quantity used.'
        );
        RAISERROR(N'%s', 16, 1, @msg);
        RETURN;
    END

    DECLARE @GoodBags INT = @BagsProduced - ISNULL(@DamagedBags, 0);
    IF (@GoodBags < 0) SET @GoodBags = 0;

    DECLARE @AllInCost DECIMAL(14,2) = @TotalCost + @RawMatCost;
    DECLARE @CostPerBag DECIMAL(14,2) =
        CASE WHEN @GoodBags > 0 THEN @AllInCost / @GoodBags ELSE 0 END;

    BEGIN TRANSACTION;

    UPDATE dbo.WaterProductionBatches
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;

    IF (@GoodBags > 0)
    BEGIN
        INSERT INTO dbo.WaterStockTransactions (
            FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId,
            Note, CreatedBy
        )
        VALUES (
            @FarmId, @ProductId, 'Restock', @GoodBags, @CostPerBag, NULL,
            CONCAT('Production batch ', @BatchNo), @ApprovedBy
        );
    END

    -- Decrement raw materials. Each usage row reduces CurrentQuantity by
    -- QuantityUsed. We already verified availability above.
    UPDATE mi
    SET    mi.CurrentQuantity = mi.CurrentQuantity - u.QuantityUsed,
           mi.UpdatedAt       = SYSUTCDATETIME()
    FROM   dbo.WaterRawMaterialItems mi
    JOIN   dbo.WaterRawMaterialUsage u ON u.WaterRawMaterialItemId = mi.WaterRawMaterialItemId
    WHERE  u.FarmId = @FarmId
      AND  u.WaterProductionBatchId = @WaterProductionBatchId;

    COMMIT TRANSACTION;

    SELECT WaterProductionBatchId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.WaterProductionBatches
    WHERE  WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;
END
GO

-- Reopen: reverse Approve. Add back the raw-material quantities, write a
-- negative Adjust for the finished goods. Block when the finished bags are
-- already sold.
CREATE OR ALTER PROCEDURE dbo.spWaterProductionBatch_Reopen
    @WaterProductionBatchId INT,
    @FarmId                 NVARCHAR(450),
    @ReopenedBy             NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status       NVARCHAR(20),
            @ProductId    INT,
            @BagsProduced INT,
            @DamagedBags  INT,
            @BatchNo      NVARCHAR(60);

    SELECT @Status       = Status,
           @ProductId    = WaterProductId,
           @BagsProduced = BagsProduced,
           @DamagedBags  = DamagedBags,
           @BatchNo      = BatchNumber
    FROM   dbo.WaterProductionBatches
    WHERE  WaterProductionBatchId = @WaterProductionBatchId
       AND FarmId = @FarmId
       AND IsDeleted = 0;

    IF @Status IS NULL
    BEGIN RAISERROR('Production batch %d not found.', 16, 1, @WaterProductionBatchId); RETURN; END
    IF @Status <> 'Approved'
    BEGIN RAISERROR('Only Approved batches can be reopened. Current status: %s.', 16, 1, @Status); RETURN; END

    DECLARE @GoodBags INT = @BagsProduced - ISNULL(@DamagedBags, 0);
    IF (@GoodBags < 0) SET @GoodBags = 0;

    DECLARE @CurrentStock INT = ISNULL((
        SELECT SUM(Quantity) FROM dbo.WaterStockTransactions
        WHERE FarmId = @FarmId AND WaterProductId = @ProductId
    ), 0);

    IF @GoodBags > 0 AND @CurrentStock < @GoodBags
    BEGIN
        RAISERROR('Cannot reopen: only %d bags of this product remain in stock, but the batch added %d. Cancel related sales or adjust stock first.',
                  16, 1, @CurrentStock, @GoodBags);
        RETURN;
    END

    BEGIN TRANSACTION;

    IF (@GoodBags > 0)
    BEGIN
        INSERT INTO dbo.WaterStockTransactions
            (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
        VALUES
            (@FarmId, @ProductId, 'Adjust', -@GoodBags, NULL, NULL,
             CONCAT('Reopen production batch ', @BatchNo), @ReopenedBy);
    END

    -- Restore raw material quantities consumed at approve time.
    UPDATE mi
    SET    mi.CurrentQuantity = mi.CurrentQuantity + u.QuantityUsed,
           mi.UpdatedAt       = SYSUTCDATETIME()
    FROM   dbo.WaterRawMaterialItems mi
    JOIN   dbo.WaterRawMaterialUsage u ON u.WaterRawMaterialItemId = mi.WaterRawMaterialItemId
    WHERE  u.FarmId = @FarmId
      AND  u.WaterProductionBatchId = @WaterProductionBatchId;

    UPDATE dbo.WaterProductionBatches
    SET    Status      = 'Draft',
           ApprovedBy  = NULL,
           ApprovedAt  = NULL,
           UpdatedAt   = SYSUTCDATETIME()
    WHERE  WaterProductionBatchId = @WaterProductionBatchId
       AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT WaterProductionBatchId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.WaterProductionBatches
    WHERE  WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- 9. WaterProduct SPs — add ProductType to Insert/Update + return it
-- =============================================================================
-- These supersede the bodies created in 026. Backward compatible: the new
-- @ProductType parameter has a default of 'FinishedGood', so older callers
-- (e.g. the legacy ASP.NET MVC site) still work without code changes.

CREATE OR ALTER PROCEDURE dbo.spWaterProduct_Insert
    @FarmId      NVARCHAR(450),
    @Name        NVARCHAR(150),
    @Sku         NVARCHAR(60)  = NULL,
    @SizeMl      INT           = NULL,
    @Unit        NVARCHAR(30)  = NULL,
    @UnitPrice   DECIMAL(12,2),
    @IsActive    BIT           = 1,
    @ProductType NVARCHAR(30)  = 'FinishedGood',
    @Notes       NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterProducts (FarmId, Name, Sku, SizeMl, Unit, UnitPrice, IsActive, ProductType, Notes)
    VALUES (@FarmId, @Name, @Sku, @SizeMl, @Unit, @UnitPrice, @IsActive, @ProductType, @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProduct_Update
    @WaterProductId INT,
    @FarmId         NVARCHAR(450),
    @Name           NVARCHAR(150),
    @Sku            NVARCHAR(60)  = NULL,
    @SizeMl         INT           = NULL,
    @Unit           NVARCHAR(30)  = NULL,
    @UnitPrice      DECIMAL(12,2),
    @IsActive       BIT,
    @ProductType    NVARCHAR(30)  = 'FinishedGood',
    @Notes          NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterProducts
    SET Name = @Name, Sku = @Sku, SizeMl = @SizeMl, Unit = @Unit,
        UnitPrice = @UnitPrice, IsActive = @IsActive, ProductType = @ProductType,
        Notes = @Notes, UpdatedDate = SYSUTCDATETIME()
    WHERE WaterProductId = @WaterProductId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProduct_GetById
    @WaterProductId INT,
    @FarmId         NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.WaterProductId, p.FarmId, p.Name, p.Sku, p.SizeMl, p.Unit,
           p.UnitPrice, p.IsActive, p.ProductType, p.Notes,
           p.CreatedDate, p.UpdatedDate,
           ISNULL((SELECT SUM(Quantity) FROM dbo.WaterStockTransactions
                   WHERE  WaterProductId = p.WaterProductId), 0) AS StockOnHand
    FROM dbo.WaterProducts p
    WHERE p.WaterProductId = @WaterProductId AND p.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProduct_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.WaterProductId, p.FarmId, p.Name, p.Sku, p.SizeMl, p.Unit,
           p.UnitPrice, p.IsActive, p.ProductType, p.Notes,
           p.CreatedDate, p.UpdatedDate,
           ISNULL((SELECT SUM(Quantity) FROM dbo.WaterStockTransactions
                   WHERE  WaterProductId = p.WaterProductId), 0) AS StockOnHand
    FROM dbo.WaterProducts p
    WHERE p.FarmId = @FarmId
    ORDER BY p.IsActive DESC, p.Name;
END
GO

-- =============================================================================
-- 10. Grant execute to the app role (mirrors 045 / 059)
-- =============================================================================
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'PoultryAppRole' AND type = 'R')
BEGIN
    GRANT EXECUTE ON dbo.spWaterProductionRecipe_GetByProduct   TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterProductionRecipe_Upsert         TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterProductionRecipe_Delete         TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterRawMaterialUsage_GetByBatch     TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterRawMaterialUsage_GetHistory     TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterProductionBatch_Insert          TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterProductionBatch_Update          TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterProductionBatch_Approve         TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterProductionBatch_Reopen          TO PoultryAppRole;
END
GO

PRINT '063_AddWaterProductionRecipesAndUsage.sql complete.';
GO

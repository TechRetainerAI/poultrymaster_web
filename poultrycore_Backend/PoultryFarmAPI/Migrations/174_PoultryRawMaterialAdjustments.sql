-- =============================================================================
-- 174_PoultryRawMaterialAdjustments.sql
-- Manual stock adjustments for raw materials & supplies.
--
-- Raw-material CurrentQuantity previously changed only via purchases (which post
-- to Expense) and production usage (which carries variance logic). Neither fits a
-- plain "correct the count" adjustment from the Stock Movements page. This adds a
-- dedicated, side-effect-free adjustment ledger so owners can increase/decrease a
-- raw material or supply directly without touching financials or usage variance.
--
-- Additive + idempotent. Grants EXECUTE to the app login `Techretainer`.
-- =============================================================================
SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Ledger table
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryRawMaterialAdjustments', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryRawMaterialAdjustments (
        PoultryRawMaterialAdjustmentId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                         NVARCHAR(450) NOT NULL,
        PoultryRawMaterialItemId       INT           NOT NULL,
        AdjustedDate                   DATETIME2     NOT NULL CONSTRAINT DF_PoultryRMAdj_Date      DEFAULT (SYSUTCDATETIME()),
        Quantity                       DECIMAL(14,3) NOT NULL,   -- signed delta: + increase, - decrease
        UnitCost                       DECIMAL(14,2) NULL,       -- optional valuation
        MovementType                   NVARCHAR(30)  NULL,       -- display label: 'Increase' | 'Adjustment' | 'Decrease' | 'Damage/Loss'
        Note                           NVARCHAR(500) NULL,
        CreatedBy                      NVARCHAR(450) NULL,
        CreatedAt                      DATETIME2     NOT NULL CONSTRAINT DF_PoultryRMAdj_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_PoultryRMAdj_Item FOREIGN KEY (PoultryRawMaterialItemId) REFERENCES dbo.PoultryRawMaterialItems (PoultryRawMaterialItemId)
    );
    CREATE INDEX IX_PoultryRMAdj_FarmId ON dbo.PoultryRawMaterialAdjustments (FarmId);
    CREATE INDEX IX_PoultryRMAdj_Item   ON dbo.PoultryRawMaterialAdjustments (PoultryRawMaterialItemId);
    CREATE INDEX IX_PoultryRMAdj_Date   ON dbo.PoultryRawMaterialAdjustments (AdjustedDate);
END
GO

-- -----------------------------------------------------------------------------
-- 2. Apply an adjustment: record it + move CurrentQuantity (floored at 0).
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialItem_Adjust
    @FarmId                   NVARCHAR(450),
    @PoultryRawMaterialItemId INT,
    @Quantity                 DECIMAL(14,3),        -- signed delta
    @UnitCost                 DECIMAL(14,2) = NULL,
    @MovementType             NVARCHAR(30)  = NULL,
    @Note                     NVARCHAR(500) = NULL,
    @CreatedBy                NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.PoultryRawMaterialItems
                   WHERE PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId)
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

        INSERT INTO dbo.PoultryRawMaterialAdjustments
            (FarmId, PoultryRawMaterialItemId, Quantity, UnitCost, MovementType, Note, CreatedBy)
        VALUES
            (@FarmId, @PoultryRawMaterialItemId, @Quantity, @UnitCost, @MovementType, @Note, @CreatedBy);

        DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

        UPDATE dbo.PoultryRawMaterialItems
        SET    CurrentQuantity = CASE WHEN CurrentQuantity + @Quantity < 0 THEN 0 ELSE CurrentQuantity + @Quantity END,
               UpdatedAt       = SYSUTCDATETIME()
        WHERE  PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId;

    COMMIT;

    SELECT @NewId AS PoultryRawMaterialAdjustmentId,
           (SELECT CurrentQuantity FROM dbo.PoultryRawMaterialItems
            WHERE PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId) AS CurrentQuantity;
END
GO

-- -----------------------------------------------------------------------------
-- 3. List adjustments (for the Stock Movements page).
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialAdjustment_GetAll
    @FarmId   NVARCHAR(450),
    @FromDate DATETIME2 = NULL,
    @ToDate   DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.PoultryRawMaterialAdjustmentId,
           a.FarmId,
           a.PoultryRawMaterialItemId,
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
    FROM   dbo.PoultryRawMaterialAdjustments a
    INNER JOIN dbo.PoultryRawMaterialItems i
            ON i.PoultryRawMaterialItemId = a.PoultryRawMaterialItemId
    WHERE  a.FarmId = @FarmId
      AND  (@FromDate IS NULL OR a.AdjustedDate >= @FromDate)
      AND  (@ToDate   IS NULL OR a.AdjustedDate <  DATEADD(DAY, 1, @ToDate))
    ORDER  BY a.AdjustedDate DESC, a.PoultryRawMaterialAdjustmentId DESC;
END
GO

-- -----------------------------------------------------------------------------
-- 4. Grant EXECUTE to the app login.
-- -----------------------------------------------------------------------------
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_Adjust        TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialAdjustment_GetAll  TO [Techretainer];
    PRINT '174: granted EXECUTE on raw-material adjustment SPs to Techretainer.';
END
GO

PRINT '174_PoultryRawMaterialAdjustments.sql complete.';
GO

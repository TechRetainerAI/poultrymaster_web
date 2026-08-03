-- =============================================================================
-- 179_FinishedProductSetStock.sql
-- "Set to actual count" for finished products (Poultry + Water).
--
-- Finished-product stock is the live SUM of its stock-transaction ledger, so it
-- can't be edited directly. To CORRECT it to a physical count, we write one
-- Adjust transaction for the difference (target - current). The displayed stock
-- (= SUM of transaction Quantity, migration 092/124) then equals the count.
--
-- Additive + idempotent (CREATE OR ALTER). Grants EXECUTE to `Techretainer`.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---- Poultry (Birds, Eggs, …) — Quantity is DECIMAL ------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_SetStock
    @FarmId           NVARCHAR(450),
    @PoultryProductId INT,
    @TargetQuantity   DECIMAL(18,3),
    @Note             NVARCHAR(500) = NULL,
    @CreatedBy        NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.PoultryProducts WHERE PoultryProductId = @PoultryProductId AND FarmId = @FarmId)
    BEGIN RAISERROR('Product not found for this company.', 16, 1); RETURN; END

    DECLARE @current DECIMAL(18,3) = ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions
                                             WHERE PoultryProductId = @PoultryProductId AND FarmId = @FarmId), 0);
    DECLARE @delta DECIMAL(18,3) = @TargetQuantity - @current;

    IF @delta <> 0
        INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, Note, CreatedBy)
        VALUES (@FarmId, @PoultryProductId, 'Adjustment', @delta, ISNULL(@Note, 'Stock-take correction'), @CreatedBy);

    SELECT ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions
                   WHERE PoultryProductId = @PoultryProductId AND FarmId = @FarmId), 0) AS CurrentStock;
END
GO

-- ---- Water (Sachet Water, Bottled, …) — Quantity is INT --------------------
CREATE OR ALTER PROCEDURE dbo.spWaterProduct_SetStock
    @FarmId         NVARCHAR(450),
    @WaterProductId INT,
    @TargetQuantity DECIMAL(18,3),
    @Note           NVARCHAR(500) = NULL,
    @CreatedBy      NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.WaterProducts WHERE WaterProductId = @WaterProductId AND FarmId = @FarmId)
    BEGIN RAISERROR('Product not found for this company.', 16, 1); RETURN; END

    DECLARE @current DECIMAL(18,3) = ISNULL((SELECT SUM(CAST(Quantity AS DECIMAL(18,3))) FROM dbo.WaterStockTransactions
                                             WHERE WaterProductId = @WaterProductId AND FarmId = @FarmId), 0);
    -- WaterStockTransactions.Quantity is INT (bags) — round the correction.
    DECLARE @delta INT = CAST(ROUND(@TargetQuantity - @current, 0) AS INT);

    IF @delta <> 0
        INSERT INTO dbo.WaterStockTransactions (FarmId, WaterProductId, TxnType, Quantity, Note, CreatedBy, CreatedDate)
        VALUES (@FarmId, @WaterProductId, 'Adjust', @delta, ISNULL(@Note, 'Stock-take correction'), @CreatedBy, SYSUTCDATETIME());

    SELECT ISNULL((SELECT SUM(CAST(Quantity AS DECIMAL(18,3))) FROM dbo.WaterStockTransactions
                   WHERE WaterProductId = @WaterProductId AND FarmId = @FarmId), 0) AS CurrentStock;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryProduct_SetStock TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterProduct_SetStock   TO [Techretainer];
    PRINT '179: granted EXECUTE on finished-product set-stock SPs to Techretainer.';
END
GO

PRINT '179_FinishedProductSetStock.sql complete.';
GO

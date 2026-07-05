-- =============================================================================
-- Migration 139: Egg SALES reduce egg inventory + write a stock movement
-- =============================================================================
-- Doc 1 §5/§8. Production already increases egg stock (migration 136) and bird
-- sales already decrease bird stock (134), but EGG sales did nothing — the egg
-- inventory never dropped and no stock movement was recorded. This wires
-- spSale_Insert/_Update/_Delete to a new helper that posts a negative 'Sale'
-- PoultryStockTransactions row against the egg finished-product for egg sales
-- (product name contains "egg"), reducing egg stock by the quantity sold.
-- Idempotent: the helper removes any prior 'Sale' txn for the sale before
-- reinserting, so edits re-sync and deletes reverse. Also re-syncs bird stock in
-- spSale_Update (previously only Insert/Delete touched bird stock).
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Helper: post/replace the egg-sale stock movement for a sale (negative qty).
CREATE OR ALTER PROCEDURE dbo.spPoultryEggStock_SyncForSale
    @FarmId NVARCHAR(450), @SaleId INT, @QtySold DECIMAL(18,3), @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- Idempotent: drop any prior egg-sale movement for this sale.
    DELETE FROM dbo.PoultryStockTransactions
    WHERE FarmId = @FarmId AND TxnType = 'Sale' AND RelatedId = @SaleId;

    IF (ISNULL(@QtySold,0) <= 0) RETURN;

    DECLARE @egg INT;
    SELECT TOP 1 @egg = PoultryProductId FROM dbo.PoultryProducts
    WHERE  FarmId = @FarmId AND (IsRawEggProduct = 1 OR Name IN (N'Eggs', N'Chicken Eggs'))
    ORDER  BY IsRawEggProduct DESC, PoultryProductId;
    IF @egg IS NULL
    BEGIN
        INSERT INTO dbo.PoultryProducts (FarmId, Name, Unit, UnitPrice, ProductType, IsRawEggProduct, RequiresRecipeSetup)
        VALUES (@FarmId, N'Eggs', N'Crate', 0, 'FinishedGood', 1, 0);
        SET @egg = CAST(SCOPE_IDENTITY() AS INT);
    END

    INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, UnitCost, RelatedId, Note, CreatedBy)
    VALUES (@FarmId, @egg, 'Sale', -CAST(@QtySold AS DECIMAL(14,3)), NULL, @SaleId, N'Egg sale', @CreatedBy);
END
GO
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'Techretainer')
    GRANT EXECUTE ON dbo.spPoultryEggStock_SyncForSale TO [Techretainer];
GO

-- ---------------------------------------------------------------------------
-- spSale_Insert — bird sale (existing) + egg sale (new).
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spSale_Insert]
    @UserId NVARCHAR(100), @FarmId NVARCHAR(100), @SaleDate DATETIME2, @Product NVARCHAR(200), @Quantity DECIMAL(18,2),
    @UnitPrice DECIMAL(18,2), @TotalAmount DECIMAL(18,2), @PaymentMethod NVARCHAR(100) = NULL, @CustomerName NVARCHAR(200) = NULL,
    @FlockId INT = NULL, @SaleDescription NVARCHAR(MAX) = NULL, @Paid BIT = 1, @Size NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    INSERT INTO [dbo].[Sale] (UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount, PaymentMethod, CustomerName, FlockId, SaleDescription, Paid, Size, CreatedDate)
    VALUES (@UserId, @FarmId, @SaleDate, @Product, @Quantity, @UnitPrice, @TotalAmount, @PaymentMethod, @CustomerName, @FlockId, @SaleDescription, ISNULL(@Paid,1), @Size, SYSUTCDATETIME());
    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    DECLARE @p NVARCHAR(200) = LOWER(ISNULL(@Product, N''));
    -- Bird sale: bird-like product, not eggs.
    IF (@p = N'birds' OR @p LIKE N'%bird%' OR @p LIKE N'%chick%' OR @p LIKE N'%cockerel%') AND @p NOT LIKE N'%egg%' AND ISNULL(@Quantity,0) > 0
    BEGIN
        DECLARE @bq DECIMAL(14,3) = -CAST(@Quantity AS DECIMAL(14,3));
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Sale', @bq, @NewId, N'Bird sale', @UserId;
    END
    -- Egg sale: product mentions eggs -> reduce egg finished-product stock.
    ELSE IF (@p LIKE N'%egg%') AND ISNULL(@Quantity,0) > 0
    BEGIN
        EXEC dbo.spPoultryEggStock_SyncForSale @FarmId, @NewId, @Quantity, @UserId;
    END
    COMMIT TRANSACTION;
    SELECT @NewId AS NewId;
END
GO

-- ---------------------------------------------------------------------------
-- spSale_Update — re-sync egg + bird stock on edit (idempotent).
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spSale_Update]
    @UserId NVARCHAR(100), @FarmId NVARCHAR(100), @SaleId INT, @SaleDate DATETIME2, @Product NVARCHAR(200),
    @Quantity DECIMAL(18,2), @UnitPrice DECIMAL(18,2), @TotalAmount DECIMAL(18,2), @PaymentMethod NVARCHAR(100) = NULL,
    @CustomerName NVARCHAR(200) = NULL, @FlockId INT = NULL, @SaleDescription NVARCHAR(MAX) = NULL, @Paid BIT = 1, @Size NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    UPDATE [dbo].[Sale]
    SET SaleDate=@SaleDate, Product=@Product, Quantity=@Quantity, UnitPrice=@UnitPrice, TotalAmount=@TotalAmount,
        PaymentMethod=@PaymentMethod, CustomerName=@CustomerName, FlockId=@FlockId, SaleDescription=@SaleDescription,
        Paid=ISNULL(@Paid,1), Size=@Size
    WHERE SaleId=@SaleId AND FarmId=@FarmId;

    DECLARE @p NVARCHAR(200) = LOWER(ISNULL(@Product, N''));
    DECLARE @isBird BIT = CASE WHEN (@p = N'birds' OR @p LIKE N'%bird%' OR @p LIKE N'%chick%' OR @p LIKE N'%cockerel%') AND @p NOT LIKE N'%egg%' THEN 1 ELSE 0 END;
    DECLARE @isEgg  BIT = CASE WHEN @p LIKE N'%egg%' THEN 1 ELSE 0 END;

    -- Bird: apply if bird-like, else 0 removes any prior bird-sale movement.
    DECLARE @bq DECIMAL(14,3) = CASE WHEN @isBird = 1 THEN -CAST(ISNULL(@Quantity,0) AS DECIMAL(14,3)) ELSE 0 END;
    EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Sale', @bq, @SaleId, N'Bird sale', @UserId;

    -- Egg: apply if egg, else 0 removes any prior egg-sale movement.
    DECLARE @eq DECIMAL(18,3) = CASE WHEN @isEgg = 1 THEN CAST(ISNULL(@Quantity,0) AS DECIMAL(18,3)) ELSE 0 END;
    EXEC dbo.spPoultryEggStock_SyncForSale @FarmId, @SaleId, @eq, @UserId;

    COMMIT TRANSACTION;
END
GO

-- ---------------------------------------------------------------------------
-- spSale_Delete — reverse bird (existing) + egg (new) stock movements.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spSale_Delete]
    @FarmId VARCHAR(450), @UserId VARCHAR(450), @SaleId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Sale', 0, @SaleId, NULL, @UserId;
    EXEC dbo.spPoultryEggStock_SyncForSale @FarmId, @SaleId, 0, @UserId;
    DELETE FROM [dbo].[Sale] WHERE SaleId = @SaleId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

PRINT 'Migration 139 applied: egg sales now reduce egg inventory + write a stock movement.';
GO

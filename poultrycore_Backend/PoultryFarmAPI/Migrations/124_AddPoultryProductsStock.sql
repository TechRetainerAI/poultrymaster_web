-- =============================================================================
-- Migration 124: Poultry Company — Finished Products + Stock Transactions (slice 2)
-- =============================================================================
-- Mirrors the Water product/stock model for the POULTRY company type. Additive.
--   * PoultryProducts            — finished goods (dressed birds, packaged eggs, etc.)
--   * PoultryStockTransactions   — immutable in/out history; stock-on-hand = SUM(quantity)
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.PoultryProducts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryProducts (
        PoultryProductId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId           NVARCHAR(450) NOT NULL,
        Name             NVARCHAR(150) NOT NULL,
        Sku              NVARCHAR(60)  NULL,
        Unit             NVARCHAR(30)  NULL,
        UnitPrice        DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryProducts_Price DEFAULT (0),
        ProductType      NVARCHAR(30)  NOT NULL CONSTRAINT DF_PoultryProducts_Type DEFAULT ('FinishedGood'),  -- FinishedGood | RawMaterial | PackagingMaterial | Other
        IsActive         BIT           NOT NULL CONSTRAINT DF_PoultryProducts_IsActive DEFAULT (1),
        Notes            NVARCHAR(500) NULL,
        CreatedDate      DATETIME2     NOT NULL CONSTRAINT DF_PoultryProducts_Created DEFAULT (SYSUTCDATETIME()),
        UpdatedDate      DATETIME2     NULL,
        CONSTRAINT UQ_PoultryProducts_Farm_Name UNIQUE (FarmId, Name)
    );
    CREATE INDEX IX_PoultryProducts_FarmId ON dbo.PoultryProducts (FarmId);
END
GO

IF OBJECT_ID('dbo.PoultryStockTransactions', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryStockTransactions (
        PoultryStockTransactionId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId           NVARCHAR(450) NOT NULL,
        PoultryProductId INT           NOT NULL,
        TxnType          NVARCHAR(20)  NOT NULL,   -- Restock | Adjust | Sale | Return | Production
        Quantity         DECIMAL(14,3) NOT NULL,   -- signed (+in / -out)
        UnitCost         DECIMAL(14,2) NULL,
        RelatedId        INT           NULL,        -- sale/batch id, etc.
        Note             NVARCHAR(500) NULL,
        CreatedDate      DATETIME2     NOT NULL CONSTRAINT DF_PoultryStockTxn_Created DEFAULT (SYSUTCDATETIME()),
        CreatedBy        NVARCHAR(450) NULL,
        CONSTRAINT FK_PoultryStockTxn_Product FOREIGN KEY (PoultryProductId) REFERENCES dbo.PoultryProducts (PoultryProductId)
    );
    CREATE INDEX IX_PoultryStockTxn_FarmId  ON dbo.PoultryStockTransactions (FarmId);
    CREATE INDEX IX_PoultryStockTxn_Product ON dbo.PoultryStockTransactions (PoultryProductId);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.*,
           CAST(ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                        WHERE t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId), 0) AS DECIMAL(18,3)) AS StockOnHand
    FROM   dbo.PoultryProducts p
    WHERE  p.FarmId = @FarmId
    ORDER  BY p.IsActive DESC, p.Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_Insert
    @FarmId NVARCHAR(450), @Name NVARCHAR(150), @Sku NVARCHAR(60) = NULL,
    @Unit NVARCHAR(30) = NULL, @UnitPrice DECIMAL(14,2) = 0,
    @ProductType NVARCHAR(30) = 'FinishedGood', @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.PoultryProducts (FarmId, Name, Sku, Unit, UnitPrice, ProductType, Notes)
    VALUES (@FarmId, @Name, @Sku, @Unit, ISNULL(@UnitPrice,0), ISNULL(@ProductType,'FinishedGood'), @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_Update
    @PoultryProductId INT, @FarmId NVARCHAR(450), @Name NVARCHAR(150), @Sku NVARCHAR(60) = NULL,
    @Unit NVARCHAR(30) = NULL, @UnitPrice DECIMAL(14,2) = 0, @ProductType NVARCHAR(30) = 'FinishedGood',
    @IsActive BIT = 1, @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryProducts
    SET    Name = @Name, Sku = @Sku, Unit = @Unit, UnitPrice = ISNULL(@UnitPrice,0),
           ProductType = ISNULL(@ProductType,'FinishedGood'), IsActive = ISNULL(@IsActive,1),
           Notes = @Notes, UpdatedDate = SYSUTCDATETIME()
    WHERE  PoultryProductId = @PoultryProductId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_Delete
    @PoultryProductId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM dbo.PoultryStockTransactions WHERE PoultryProductId = @PoultryProductId AND FarmId = @FarmId)
    BEGIN
        UPDATE dbo.PoultryProducts SET IsActive = 0, UpdatedDate = SYSUTCDATETIME()
        WHERE  PoultryProductId = @PoultryProductId AND FarmId = @FarmId;
        RETURN;
    END
    DELETE FROM dbo.PoultryProducts WHERE PoultryProductId = @PoultryProductId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryStock_AddTransaction
    @FarmId NVARCHAR(450), @PoultryProductId INT, @TxnType NVARCHAR(20),
    @Quantity DECIMAL(14,3), @UnitCost DECIMAL(14,2) = NULL, @RelatedId INT = NULL,
    @Note NVARCHAR(500) = NULL, @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, UnitCost, RelatedId, Note, CreatedBy)
    VALUES (@FarmId, @PoultryProductId, @TxnType, @Quantity, @UnitCost, @RelatedId, @Note, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryStock_GetTransactions
    @FarmId NVARCHAR(450), @PoultryProductId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.*, p.Name AS ProductName
    FROM   dbo.PoultryStockTransactions t
    INNER  JOIN dbo.PoultryProducts p ON p.PoultryProductId = t.PoultryProductId
    WHERE  t.FarmId = @FarmId
       AND (@PoultryProductId IS NULL OR t.PoultryProductId = @PoultryProductId)
    ORDER  BY t.CreatedDate DESC, t.PoultryStockTransactionId DESC;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryProduct_GetAll        TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProduct_Insert        TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProduct_Update        TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProduct_Delete        TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryStock_AddTransaction  TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryStock_GetTransactions TO [Techretainer];
    PRINT '124: granted EXECUTE on spPoultryProduct/Stock to Techretainer.';
END
GO

PRINT '124_AddPoultryProductsStock.sql complete.';
GO

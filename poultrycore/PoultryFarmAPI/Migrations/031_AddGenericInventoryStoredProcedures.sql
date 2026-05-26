-- =============================================================================
-- Migration 031: Stored procedures for Products / Services / Inventory
-- =============================================================================
-- Run AFTER 030_AddGenericProductsServicesInventory.sql.
--
-- Procs covered:
--   * GenericProductCategory: GetAll, Insert, Update, Delete (soft).
--   * GenericProduct:         GetAll, GetById, Insert (writes OpeningStock
--                              movement if TrackInventory=1), Update, Delete
--                              (soft), GetLowStock, Reconcile (rebuilds
--                              CurrentStock from SUM(StockMovements)).
--   * GenericServiceCategory: GetAll, Insert, Update, Delete (soft).
--   * GenericService:         GetAll, GetById, Insert, Update, Delete (soft).
--   * GenericStockMovement:   GetAllForProduct, GetByFarm, InsertManual.
--   * GenericStockAdjustment: GetAll, GetById, Insert (Draft), Submit,
--                              Approve (writes movement + updates Product
--                              .CurrentStock atomically), Reject.
--
-- Approval semantics:
--   * Insert lands as Draft.
--   * Submit moves Draft → Submitted.
--   * Approve moves Submitted → Approved AND writes the matching
--     GenericStockMovements row AND updates Product.CurrentStock — all in
--     one transaction. Approving an already-approved row is a no-op (idempotent
--     against transient retries).
--   * Reject moves Submitted → Rejected. No inventory impact.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- GenericProductCategory
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericProductCategory_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericProductCategoryId, FarmId, Name, Description, IsActive, IsDeleted,
           CreatedAt, UpdatedAt
    FROM   dbo.GenericProductCategories
    WHERE  FarmId = @FarmId AND IsDeleted = 0
    ORDER  BY IsActive DESC, Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericProductCategory_Insert
    @FarmId       NVARCHAR(450),
    @Name         NVARCHAR(100),
    @Description  NVARCHAR(500) = NULL,
    @IsActive     BIT           = 1
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.GenericProductCategories (FarmId, Name, Description, IsActive)
    VALUES (@FarmId, @Name, @Description, @IsActive);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericProductCategory_Update
    @GenericProductCategoryId INT,
    @FarmId                   NVARCHAR(450),
    @Name                     NVARCHAR(100),
    @Description              NVARCHAR(500) = NULL,
    @IsActive                 BIT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericProductCategories
    SET    Name = @Name, Description = @Description, IsActive = @IsActive,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericProductCategoryId = @GenericProductCategoryId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericProductCategory_Delete
    @GenericProductCategoryId INT,
    @FarmId                   NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericProductCategories
    SET    IsDeleted = 1, IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericProductCategoryId = @GenericProductCategoryId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- GenericProduct
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericProduct_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.GenericProductId, p.FarmId, p.GenericProductCategoryId, c.Name AS CategoryName,
           p.ProductName, p.SKU, p.Barcode, p.UnitOfMeasure,
           p.CostPrice, p.SellingPrice, p.WholesalePrice, p.RetailPrice,
           p.OpeningStock, p.CurrentStock, p.MinimumStockAlert, p.TrackInventory,
           p.SupplierId, p.IsActive, p.IsDeleted, p.Notes,
           p.CreatedAt, p.UpdatedAt
    FROM   dbo.GenericProducts p
    LEFT   JOIN dbo.GenericProductCategories c ON c.GenericProductCategoryId = p.GenericProductCategoryId
    WHERE  p.FarmId = @FarmId AND p.IsDeleted = 0
    ORDER  BY p.IsActive DESC, p.ProductName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericProduct_GetById
    @GenericProductId INT,
    @FarmId           NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.GenericProductId, p.FarmId, p.GenericProductCategoryId, c.Name AS CategoryName,
           p.ProductName, p.SKU, p.Barcode, p.UnitOfMeasure,
           p.CostPrice, p.SellingPrice, p.WholesalePrice, p.RetailPrice,
           p.OpeningStock, p.CurrentStock, p.MinimumStockAlert, p.TrackInventory,
           p.SupplierId, p.IsActive, p.IsDeleted, p.Notes,
           p.CreatedAt, p.UpdatedAt
    FROM   dbo.GenericProducts p
    LEFT   JOIN dbo.GenericProductCategories c ON c.GenericProductCategoryId = p.GenericProductCategoryId
    WHERE  p.GenericProductId = @GenericProductId AND p.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericProduct_Insert
    @FarmId                    NVARCHAR(450),
    @GenericProductCategoryId  INT            = NULL,
    @ProductName               NVARCHAR(200),
    @SKU                       NVARCHAR(60)   = NULL,
    @Barcode                   NVARCHAR(60)   = NULL,
    @UnitOfMeasure             NVARCHAR(30)   = NULL,
    @CostPrice                 DECIMAL(14,2)  = 0,
    @SellingPrice              DECIMAL(14,2)  = 0,
    @WholesalePrice            DECIMAL(14,2)  = NULL,
    @RetailPrice               DECIMAL(14,2)  = NULL,
    @OpeningStock              DECIMAL(14,3)  = 0,
    @MinimumStockAlert         DECIMAL(14,3)  = 0,
    @TrackInventory            BIT            = 1,
    @SupplierId                INT            = NULL,
    @IsActive                  BIT            = 1,
    @Notes                     NVARCHAR(1000) = NULL,
    @CreatedBy                 NVARCHAR(450)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    INSERT INTO dbo.GenericProducts (
        FarmId, GenericProductCategoryId, ProductName, SKU, Barcode, UnitOfMeasure,
        CostPrice, SellingPrice, WholesalePrice, RetailPrice,
        OpeningStock, CurrentStock, MinimumStockAlert, TrackInventory,
        SupplierId, IsActive, Notes
    )
    VALUES (
        @FarmId, @GenericProductCategoryId, @ProductName, @SKU, @Barcode, @UnitOfMeasure,
        @CostPrice, @SellingPrice, @WholesalePrice, @RetailPrice,
        @OpeningStock,
        CASE WHEN @TrackInventory = 1 THEN @OpeningStock ELSE 0 END,
        @MinimumStockAlert, @TrackInventory,
        @SupplierId, @IsActive, @Notes
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    -- Seed the opening-stock movement so SUM(Movements) matches CurrentStock
    -- from day one. Skip for services-style (TrackInventory = 0) or zero
    -- opening stock.
    IF (@TrackInventory = 1 AND @OpeningStock <> 0)
    BEGIN
        INSERT INTO dbo.GenericStockMovements (
            FarmId, GenericProductId, MovementDate, MovementType, Quantity,
            UnitCost, TotalCostValue, ReferenceType, Reason, CreatedBy
        )
        VALUES (
            @FarmId, @NewId, SYSUTCDATETIME(), 'OpeningStock', @OpeningStock,
            @CostPrice, @CostPrice * @OpeningStock, 'Opening', 'Opening stock seed', @CreatedBy
        );
    END

    COMMIT TRANSACTION;

    SELECT @NewId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericProduct_Update
    @GenericProductId          INT,
    @FarmId                    NVARCHAR(450),
    @GenericProductCategoryId  INT            = NULL,
    @ProductName               NVARCHAR(200),
    @SKU                       NVARCHAR(60)   = NULL,
    @Barcode                   NVARCHAR(60)   = NULL,
    @UnitOfMeasure             NVARCHAR(30)   = NULL,
    @CostPrice                 DECIMAL(14,2),
    @SellingPrice              DECIMAL(14,2),
    @WholesalePrice            DECIMAL(14,2)  = NULL,
    @RetailPrice               DECIMAL(14,2)  = NULL,
    @MinimumStockAlert         DECIMAL(14,3),
    @TrackInventory            BIT,
    @SupplierId                INT            = NULL,
    @IsActive                  BIT,
    @Notes                     NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- OpeningStock and CurrentStock are NOT updateable here. CurrentStock is
    -- only changed via stock movements / adjustments. OpeningStock can only
    -- be set at create-time.
    UPDATE dbo.GenericProducts
    SET    GenericProductCategoryId = @GenericProductCategoryId,
           ProductName       = @ProductName,
           SKU               = @SKU,
           Barcode           = @Barcode,
           UnitOfMeasure     = @UnitOfMeasure,
           CostPrice         = @CostPrice,
           SellingPrice      = @SellingPrice,
           WholesalePrice    = @WholesalePrice,
           RetailPrice       = @RetailPrice,
           MinimumStockAlert = @MinimumStockAlert,
           TrackInventory    = @TrackInventory,
           SupplierId        = @SupplierId,
           IsActive          = @IsActive,
           Notes             = @Notes,
           UpdatedAt         = SYSUTCDATETIME()
    WHERE  GenericProductId = @GenericProductId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericProduct_Delete
    @GenericProductId INT,
    @FarmId           NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    -- Always soft-delete; movements/adjustments reference this row.
    UPDATE dbo.GenericProducts
    SET    IsDeleted = 1, IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericProductId = @GenericProductId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericProduct_GetLowStock
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.GenericProductId, p.FarmId, p.ProductName, p.SKU, p.UnitOfMeasure,
           p.CurrentStock, p.MinimumStockAlert,
           (p.MinimumStockAlert - p.CurrentStock) AS Shortfall
    FROM   dbo.GenericProducts p
    WHERE  p.FarmId = @FarmId
       AND p.IsActive = 1
       AND p.IsDeleted = 0
       AND p.TrackInventory = 1
       AND p.CurrentStock <= p.MinimumStockAlert
    ORDER  BY Shortfall DESC, p.ProductName;
END
GO

-- Recalculates CurrentStock from SUM(StockMovements). Use this if something
-- went wrong and the denormalised cache drifted from the source-of-truth.
CREATE OR ALTER PROCEDURE dbo.spGenericProduct_ReconcileStock
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE p
    SET    CurrentStock = ISNULL(m.TotalQty, 0),
           UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.GenericProducts p
    LEFT   JOIN (
              SELECT GenericProductId, SUM(Quantity) AS TotalQty
              FROM   dbo.GenericStockMovements
              WHERE  FarmId = @FarmId
              GROUP  BY GenericProductId
           ) m ON m.GenericProductId = p.GenericProductId
    WHERE  p.FarmId = @FarmId AND p.TrackInventory = 1;
END
GO

-- =============================================================================
-- GenericServiceCategory
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericServiceCategory_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericServiceCategoryId, FarmId, Name, Description, IsActive, IsDeleted,
           CreatedAt, UpdatedAt
    FROM   dbo.GenericServiceCategories
    WHERE  FarmId = @FarmId AND IsDeleted = 0
    ORDER  BY IsActive DESC, Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericServiceCategory_Insert
    @FarmId       NVARCHAR(450),
    @Name         NVARCHAR(100),
    @Description  NVARCHAR(500) = NULL,
    @IsActive     BIT           = 1
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.GenericServiceCategories (FarmId, Name, Description, IsActive)
    VALUES (@FarmId, @Name, @Description, @IsActive);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericServiceCategory_Update
    @GenericServiceCategoryId INT,
    @FarmId                   NVARCHAR(450),
    @Name                     NVARCHAR(100),
    @Description              NVARCHAR(500) = NULL,
    @IsActive                 BIT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericServiceCategories
    SET    Name = @Name, Description = @Description, IsActive = @IsActive,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericServiceCategoryId = @GenericServiceCategoryId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericServiceCategory_Delete
    @GenericServiceCategoryId INT,
    @FarmId                   NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericServiceCategories
    SET    IsDeleted = 1, IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericServiceCategoryId = @GenericServiceCategoryId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- GenericService
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericService_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.GenericServiceId, s.FarmId, s.GenericServiceCategoryId, c.Name AS CategoryName,
           s.ServiceName, s.DefaultPrice, s.EstimatedCost, s.DurationMinutes,
           s.AssignedStaffId, s.IsActive, s.IsDeleted, s.Notes,
           s.CreatedAt, s.UpdatedAt
    FROM   dbo.GenericServices s
    LEFT   JOIN dbo.GenericServiceCategories c ON c.GenericServiceCategoryId = s.GenericServiceCategoryId
    WHERE  s.FarmId = @FarmId AND s.IsDeleted = 0
    ORDER  BY s.IsActive DESC, s.ServiceName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericService_GetById
    @GenericServiceId INT,
    @FarmId           NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.GenericServiceId, s.FarmId, s.GenericServiceCategoryId, c.Name AS CategoryName,
           s.ServiceName, s.DefaultPrice, s.EstimatedCost, s.DurationMinutes,
           s.AssignedStaffId, s.IsActive, s.IsDeleted, s.Notes,
           s.CreatedAt, s.UpdatedAt
    FROM   dbo.GenericServices s
    LEFT   JOIN dbo.GenericServiceCategories c ON c.GenericServiceCategoryId = s.GenericServiceCategoryId
    WHERE  s.GenericServiceId = @GenericServiceId AND s.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericService_Insert
    @FarmId                    NVARCHAR(450),
    @GenericServiceCategoryId  INT            = NULL,
    @ServiceName               NVARCHAR(200),
    @DefaultPrice              DECIMAL(14,2)  = 0,
    @EstimatedCost             DECIMAL(14,2)  = NULL,
    @DurationMinutes           INT            = NULL,
    @AssignedStaffId           INT            = NULL,
    @IsActive                  BIT            = 1,
    @Notes                     NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.GenericServices (
        FarmId, GenericServiceCategoryId, ServiceName, DefaultPrice,
        EstimatedCost, DurationMinutes, AssignedStaffId, IsActive, Notes
    )
    VALUES (
        @FarmId, @GenericServiceCategoryId, @ServiceName, @DefaultPrice,
        @EstimatedCost, @DurationMinutes, @AssignedStaffId, @IsActive, @Notes
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericService_Update
    @GenericServiceId          INT,
    @FarmId                    NVARCHAR(450),
    @GenericServiceCategoryId  INT            = NULL,
    @ServiceName               NVARCHAR(200),
    @DefaultPrice              DECIMAL(14,2),
    @EstimatedCost             DECIMAL(14,2)  = NULL,
    @DurationMinutes           INT            = NULL,
    @AssignedStaffId           INT            = NULL,
    @IsActive                  BIT,
    @Notes                     NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericServices
    SET    GenericServiceCategoryId = @GenericServiceCategoryId,
           ServiceName       = @ServiceName,
           DefaultPrice      = @DefaultPrice,
           EstimatedCost     = @EstimatedCost,
           DurationMinutes   = @DurationMinutes,
           AssignedStaffId   = @AssignedStaffId,
           IsActive          = @IsActive,
           Notes             = @Notes,
           UpdatedAt         = SYSUTCDATETIME()
    WHERE  GenericServiceId = @GenericServiceId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericService_Delete
    @GenericServiceId INT,
    @FarmId           NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericServices
    SET    IsDeleted = 1, IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericServiceId = @GenericServiceId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- GenericStockMovement
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericStockMovement_GetAllForProduct
    @GenericProductId INT,
    @FarmId           NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT m.GenericStockMovementId, m.FarmId, m.GenericProductId, m.InventoryLocationId,
           m.MovementDate, m.MovementType, m.Quantity, m.UnitCost, m.UnitSellingPrice,
           m.TotalCostValue, m.ReferenceType, m.ReferenceId, m.Reason,
           m.CreatedBy, m.ApprovedBy, m.ApprovedAt, m.Notes, m.CreatedAt
    FROM   dbo.GenericStockMovements m
    WHERE  m.FarmId = @FarmId AND m.GenericProductId = @GenericProductId
    ORDER  BY m.MovementDate DESC, m.GenericStockMovementId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericStockMovement_GetByFarm
    @FarmId    NVARCHAR(450),
    @FromDate  DATETIME2 = NULL,
    @ToDate    DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT m.GenericStockMovementId, m.FarmId, m.GenericProductId, p.ProductName,
           m.InventoryLocationId, m.MovementDate, m.MovementType, m.Quantity,
           m.UnitCost, m.UnitSellingPrice, m.TotalCostValue,
           m.ReferenceType, m.ReferenceId, m.Reason,
           m.CreatedBy, m.ApprovedBy, m.ApprovedAt, m.Notes, m.CreatedAt
    FROM   dbo.GenericStockMovements m
    INNER  JOIN dbo.GenericProducts p ON p.GenericProductId = m.GenericProductId
    WHERE  m.FarmId = @FarmId
       AND (@FromDate IS NULL OR m.MovementDate >= @FromDate)
       AND (@ToDate   IS NULL OR m.MovementDate <= @ToDate)
    ORDER  BY m.MovementDate DESC, m.GenericStockMovementId DESC;
END
GO

-- =============================================================================
-- GenericStockAdjustment
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericStockAdjustment_GetAll
    @FarmId  NVARCHAR(450),
    @Status  NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.GenericStockAdjustmentId, a.FarmId, a.GenericProductId, p.ProductName,
           a.InventoryLocationId, a.AdjustmentDate, a.AdjustmentType, a.Quantity,
           a.Reason, a.Status, a.RequestedBy, a.ApprovedBy, a.ApprovedAt,
           a.RejectionReason, a.Notes, a.CreatedAt, a.UpdatedAt
    FROM   dbo.GenericStockAdjustments a
    INNER  JOIN dbo.GenericProducts p ON p.GenericProductId = a.GenericProductId
    WHERE  a.FarmId = @FarmId
       AND (@Status IS NULL OR a.Status = @Status)
    ORDER  BY a.AdjustmentDate DESC, a.GenericStockAdjustmentId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericStockAdjustment_GetById
    @GenericStockAdjustmentId INT,
    @FarmId                   NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.GenericStockAdjustmentId, a.FarmId, a.GenericProductId, p.ProductName,
           a.InventoryLocationId, a.AdjustmentDate, a.AdjustmentType, a.Quantity,
           a.Reason, a.Status, a.RequestedBy, a.ApprovedBy, a.ApprovedAt,
           a.RejectionReason, a.Notes, a.CreatedAt, a.UpdatedAt
    FROM   dbo.GenericStockAdjustments a
    INNER  JOIN dbo.GenericProducts p ON p.GenericProductId = a.GenericProductId
    WHERE  a.GenericStockAdjustmentId = @GenericStockAdjustmentId AND a.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericStockAdjustment_Insert
    @FarmId            NVARCHAR(450),
    @GenericProductId  INT,
    @AdjustmentType    NVARCHAR(10),     -- 'Increase' | 'Decrease'
    @Quantity          DECIMAL(14,3),    -- positive magnitude
    @Reason            NVARCHAR(500),
    @AdjustmentDate    DATETIME2     = NULL,
    @Notes             NVARCHAR(1000) = NULL,
    @RequestedBy       NVARCHAR(450)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF (@AdjustmentType NOT IN ('Increase', 'Decrease'))
    BEGIN
        RAISERROR('AdjustmentType must be Increase or Decrease.', 16, 1);
        RETURN;
    END
    IF (@Quantity <= 0)
    BEGIN
        RAISERROR('Quantity must be greater than zero.', 16, 1);
        RETURN;
    END
    IF (@Reason IS NULL OR LTRIM(RTRIM(@Reason)) = '')
    BEGIN
        RAISERROR('Reason is required for a stock adjustment.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.GenericStockAdjustments (
        FarmId, GenericProductId, AdjustmentDate, AdjustmentType, Quantity,
        Reason, Status, RequestedBy, Notes
    )
    VALUES (
        @FarmId, @GenericProductId, ISNULL(@AdjustmentDate, SYSUTCDATETIME()),
        @AdjustmentType, @Quantity, @Reason, 'Draft', @RequestedBy, @Notes
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericStockAdjustment_Submit
    @GenericStockAdjustmentId INT,
    @FarmId                   NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericStockAdjustments
    SET    Status = 'Submitted', UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericStockAdjustmentId = @GenericStockAdjustmentId
       AND FarmId = @FarmId
       AND Status = 'Draft';

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Stock adjustment cannot be submitted (not found or not in Draft).', 16, 1);
        RETURN;
    END
END
GO

-- Approve is the meaty one. Atomic: state change + StockMovement insert +
-- Product.CurrentStock update.
CREATE OR ALTER PROCEDURE dbo.spGenericStockAdjustment_Approve
    @GenericStockAdjustmentId INT,
    @FarmId                   NVARCHAR(450),
    @ApprovedBy               NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Idempotency: if it's already Approved, return the row without doing
    -- anything (callers may retry on transient errors).
    IF EXISTS (
        SELECT 1 FROM dbo.GenericStockAdjustments
        WHERE  GenericStockAdjustmentId = @GenericStockAdjustmentId
           AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT GenericStockAdjustmentId, Status, ApprovedBy, ApprovedAt
        FROM   dbo.GenericStockAdjustments
        WHERE  GenericStockAdjustmentId = @GenericStockAdjustmentId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @ProductId      INT,
            @AdjustmentType NVARCHAR(10),
            @QtyMagnitude   DECIMAL(14,3),
            @Reason         NVARCHAR(500),
            @LocationId     INT,
            @Date           DATETIME2,
            @Status         NVARCHAR(20),
            @TrackInventory BIT,
            @CostPrice      DECIMAL(14,2);

    SELECT @ProductId      = a.GenericProductId,
           @AdjustmentType = a.AdjustmentType,
           @QtyMagnitude   = a.Quantity,
           @Reason         = a.Reason,
           @LocationId     = a.InventoryLocationId,
           @Date           = a.AdjustmentDate,
           @Status         = a.Status,
           @TrackInventory = p.TrackInventory,
           @CostPrice      = p.CostPrice
    FROM   dbo.GenericStockAdjustments a
    INNER  JOIN dbo.GenericProducts p ON p.GenericProductId = a.GenericProductId
    WHERE  a.GenericStockAdjustmentId = @GenericStockAdjustmentId AND a.FarmId = @FarmId;

    IF @ProductId IS NULL
    BEGIN
        RAISERROR('Stock adjustment %d not found.', 16, 1, @GenericStockAdjustmentId);
        RETURN;
    END

    IF @Status NOT IN ('Draft', 'Submitted')
    BEGIN
        RAISERROR('Stock adjustment cannot be approved from status %s.', 16, 1, @Status);
        RETURN;
    END

    IF @TrackInventory = 0
    BEGIN
        RAISERROR('Cannot adjust stock on a product where TrackInventory = 0.', 16, 1);
        RETURN;
    END

    DECLARE @SignedQty   DECIMAL(14,3) = CASE WHEN @AdjustmentType = 'Increase' THEN  @QtyMagnitude
                                                                                ELSE -@QtyMagnitude END;
    DECLARE @MovementType NVARCHAR(30) = CASE WHEN @AdjustmentType = 'Increase' THEN 'AdjustmentIn'
                                                                                ELSE 'AdjustmentOut' END;

    BEGIN TRANSACTION;

    UPDATE dbo.GenericStockAdjustments
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericStockAdjustmentId = @GenericStockAdjustmentId AND FarmId = @FarmId;

    INSERT INTO dbo.GenericStockMovements (
        FarmId, GenericProductId, InventoryLocationId, MovementDate, MovementType,
        Quantity, UnitCost, TotalCostValue, ReferenceType, ReferenceId, Reason,
        CreatedBy, ApprovedBy, ApprovedAt
    )
    VALUES (
        @FarmId, @ProductId, @LocationId, @Date, @MovementType,
        @SignedQty, @CostPrice, @CostPrice * ABS(@SignedQty), 'Adjustment',
        @GenericStockAdjustmentId, @Reason,
        @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
    );

    UPDATE dbo.GenericProducts
    SET    CurrentStock = CurrentStock + @SignedQty,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericProductId = @ProductId AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT GenericStockAdjustmentId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.GenericStockAdjustments
    WHERE  GenericStockAdjustmentId = @GenericStockAdjustmentId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericStockAdjustment_Reject
    @GenericStockAdjustmentId INT,
    @FarmId                   NVARCHAR(450),
    @RejectionReason          NVARCHAR(500),
    @ApprovedBy               NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.GenericStockAdjustments
    SET    Status = 'Rejected', RejectionReason = @RejectionReason,
           ApprovedBy = @ApprovedBy, ApprovedAt = SYSUTCDATETIME(),
           UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericStockAdjustmentId = @GenericStockAdjustmentId
       AND FarmId = @FarmId
       AND Status IN ('Draft', 'Submitted');

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Stock adjustment cannot be rejected (not found or already finalized).', 16, 1);
        RETURN;
    END
END
GO

PRINT '031_AddGenericInventoryStoredProcedures.sql complete.';
GO

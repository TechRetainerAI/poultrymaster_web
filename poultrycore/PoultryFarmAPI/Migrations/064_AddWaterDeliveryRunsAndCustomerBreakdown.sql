/* =============================================================================
   064_AddWaterDeliveryRunsAndCustomerBreakdown.sql

   Prompt 2: "Delivery Enhancement Logic - Driver Assignment, Customer
   Breakdown, Sales/Payments Integration."

   This migration grows the existing single-product VehicleLoading / DriverReturn
   pair into a multi-product Delivery Run with optional per-customer breakdown
   that feeds the existing Sales + Payments tables. It preserves every legacy
   call so older clients keep working.

   Net additions:
     * WaterVehicleLoadingItems       -- multi-product loadings
     * WaterDriverReturnItems         -- per-product reconciliation
     * WaterDriverReturnCustomerSales -- breakdown by shop / customer
     * WaterDriverReturnCustomerSaleItems
     * WaterDriverReturnCustomerSalePayments
     * WaterDeliveryExpenses          -- fuel, toll, loading boys, etc.
     * WaterSales: SourceType / SourceId / WaterDriverId / WaterVehicleId / WaterRouteId
     * WaterPayments: WaterCustomerId / SourceType / SourceId
     * WaterDriverReturns: CashReturnedByDriver, ApprovedDeliveryExpenses,
                           NetCashShortToBank (denormalized)

   SP behavior changes:
     * spWaterVehicleLoading_Insert / _Approve gain @ItemsJson. When the JSON
       is present, the SP populates WaterVehicleLoadingItems and moves stock
       per item (LoadOut). The single-product columns on the loading header
       are still written so existing reports keep showing something sane.
     * spWaterDriverReturn_Insert / _Approve gain @ItemsJson, @CustomerSalesJson,
       @ExpensesJson. On approve:
         - per-item LoadReturnIn writes for returned bags
         - one WaterSale + N WaterSaleItems + M WaterPayments per customer
           breakdown row (SourceType='DeliveryRun', SourceId=DriverReturnId)
         - WaterDeliveryExpenses rows persisted
       Customer breakdown writes DO NOT decrement stock again — stock already
       left on LoadOut.

   Idempotent: every block guards on sys.columns / sys.objects.
   ============================================================================= */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- 1. New columns on existing tables
-- =============================================================================

-- WaterSales: traceability back to a delivery run + customer ledger plumbing.
IF COL_LENGTH('dbo.WaterSales', 'SourceType') IS NULL
BEGIN
    PRINT 'Adding WaterSales.SourceType';
    ALTER TABLE dbo.WaterSales ADD SourceType NVARCHAR(40) NULL;
END
GO
IF COL_LENGTH('dbo.WaterSales', 'SourceId') IS NULL
BEGIN
    PRINT 'Adding WaterSales.SourceId';
    ALTER TABLE dbo.WaterSales ADD SourceId INT NULL;
END
GO
IF COL_LENGTH('dbo.WaterSales', 'WaterDriverId') IS NULL
BEGIN
    PRINT 'Adding WaterSales.WaterDriverId';
    ALTER TABLE dbo.WaterSales ADD WaterDriverId INT NULL;
END
GO
IF COL_LENGTH('dbo.WaterSales', 'WaterVehicleId') IS NULL
BEGIN
    PRINT 'Adding WaterSales.WaterVehicleId';
    ALTER TABLE dbo.WaterSales ADD WaterVehicleId INT NULL;
END
GO
IF COL_LENGTH('dbo.WaterSales', 'WaterRouteId') IS NULL
BEGIN
    PRINT 'Adding WaterSales.WaterRouteId';
    ALTER TABLE dbo.WaterSales ADD WaterRouteId INT NULL;
END
GO

-- WaterPayments: customer + source for the new flow.
IF COL_LENGTH('dbo.WaterPayments', 'WaterCustomerId') IS NULL
BEGIN
    PRINT 'Adding WaterPayments.WaterCustomerId';
    ALTER TABLE dbo.WaterPayments ADD WaterCustomerId INT NULL;
END
GO
IF COL_LENGTH('dbo.WaterPayments', 'SourceType') IS NULL
BEGIN
    PRINT 'Adding WaterPayments.SourceType';
    ALTER TABLE dbo.WaterPayments ADD SourceType NVARCHAR(40) NULL;
END
GO
IF COL_LENGTH('dbo.WaterPayments', 'SourceId') IS NULL
BEGIN
    PRINT 'Adding WaterPayments.SourceId';
    ALTER TABLE dbo.WaterPayments ADD SourceId INT NULL;
END
GO

-- WaterDriverReturns: opening-cash reconciliation extras.
IF COL_LENGTH('dbo.WaterDriverReturns', 'CashReturnedByDriver') IS NULL
BEGIN
    PRINT 'Adding WaterDriverReturns.CashReturnedByDriver';
    ALTER TABLE dbo.WaterDriverReturns
        ADD CashReturnedByDriver DECIMAL(14,2) NOT NULL
            CONSTRAINT DF_WaterDriverReturns_CashReturned DEFAULT (0) WITH VALUES;
END
GO
IF COL_LENGTH('dbo.WaterDriverReturns', 'ApprovedDeliveryExpenses') IS NULL
BEGIN
    PRINT 'Adding WaterDriverReturns.ApprovedDeliveryExpenses';
    ALTER TABLE dbo.WaterDriverReturns
        ADD ApprovedDeliveryExpenses DECIMAL(14,2) NOT NULL
            CONSTRAINT DF_WaterDriverReturns_ApprovedExp DEFAULT (0) WITH VALUES;
END
GO

-- =============================================================================
-- 2. WaterVehicleLoadingItems — multi-product header/detail
-- =============================================================================
IF OBJECT_ID('dbo.WaterVehicleLoadingItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterVehicleLoadingItems (
        WaterVehicleLoadingItemId INT IDENTITY(1,1) PRIMARY KEY,
        WaterVehicleLoadingId     INT           NOT NULL,
        WaterProductId            INT           NOT NULL,
        BagsLoaded                INT           NOT NULL,
        SachetsPerBag             INT           NOT NULL CONSTRAINT DF_WaterVehicleLoadingItems_SPB DEFAULT (30),
        UnitPrice                 DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterVehicleLoadingItems_UP DEFAULT (0),
        -- ExpectedAmount = BagsLoaded * UnitPrice. PERSISTED so reports can
        -- group on it without recomputing.
        ExpectedAmount            AS (CAST(BagsLoaded AS DECIMAL(14,2)) * UnitPrice) PERSISTED,
        Notes                     NVARCHAR(300) NULL,
        CreatedAt                 DATETIME2     NOT NULL CONSTRAINT DF_WaterVehicleLoadingItems_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                 DATETIME2     NULL,
        CONSTRAINT FK_WaterVehicleLoadingItems_Loading FOREIGN KEY (WaterVehicleLoadingId)
            REFERENCES dbo.WaterVehicleLoadings (WaterVehicleLoadingId) ON DELETE CASCADE,
        CONSTRAINT FK_WaterVehicleLoadingItems_Product FOREIGN KEY (WaterProductId)
            REFERENCES dbo.WaterProducts (WaterProductId)
    );
    CREATE INDEX IX_WaterVehicleLoadingItems_Loading ON dbo.WaterVehicleLoadingItems (WaterVehicleLoadingId);
    CREATE INDEX IX_WaterVehicleLoadingItems_Product ON dbo.WaterVehicleLoadingItems (WaterProductId);
END
GO

-- =============================================================================
-- 3. WaterDriverReturnItems — per-product reconciliation
-- =============================================================================
IF OBJECT_ID('dbo.WaterDriverReturnItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDriverReturnItems (
        WaterDriverReturnItemId INT IDENTITY(1,1) PRIMARY KEY,
        WaterDriverReturnId     INT           NOT NULL,
        WaterProductId          INT           NOT NULL,
        BagsLoaded              INT           NOT NULL,    -- snapshotted from loading at insert time
        BagsSold                INT           NOT NULL CONSTRAINT DF_WaterDriverReturnItems_Sold DEFAULT (0),
        BagsReturned            INT           NOT NULL CONSTRAINT DF_WaterDriverReturnItems_Returned DEFAULT (0),
        BagsDamaged             INT           NOT NULL CONSTRAINT DF_WaterDriverReturnItems_Damaged DEFAULT (0),
        UnitPrice               DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterDriverReturnItems_UP DEFAULT (0),
        -- ExpectedSales = BagsSold * UnitPrice. Cheaper than recomputing in
        -- the reports.
        ExpectedSales           AS (CAST(BagsSold AS DECIMAL(14,2)) * UnitPrice) PERSISTED,
        Notes                   NVARCHAR(300) NULL,
        CreatedAt               DATETIME2     NOT NULL CONSTRAINT DF_WaterDriverReturnItems_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt               DATETIME2     NULL,
        CONSTRAINT FK_WaterDriverReturnItems_Return  FOREIGN KEY (WaterDriverReturnId)
            REFERENCES dbo.WaterDriverReturns (WaterDriverReturnId) ON DELETE CASCADE,
        CONSTRAINT FK_WaterDriverReturnItems_Product FOREIGN KEY (WaterProductId)
            REFERENCES dbo.WaterProducts (WaterProductId)
    );
    CREATE INDEX IX_WaterDriverReturnItems_Return  ON dbo.WaterDriverReturnItems (WaterDriverReturnId);
    CREATE INDEX IX_WaterDriverReturnItems_Product ON dbo.WaterDriverReturnItems (WaterProductId);
END
GO

-- =============================================================================
-- 4. Customer breakdown — shop-level sales within a return
-- =============================================================================
IF OBJECT_ID('dbo.WaterDriverReturnCustomerSales', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDriverReturnCustomerSales (
        WaterDriverReturnCustomerSaleId INT IDENTITY(1,1) PRIMARY KEY,
        WaterDriverReturnId             INT           NOT NULL,
        WaterCustomerId                 INT           NULL,    -- nullable: walk-in
        CustomerLabel                   NVARCHAR(150) NULL,    -- free-text fallback for walk-ins
        TotalAmount                     DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDRCS_Total DEFAULT (0),
        CashPaid                        DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDRCS_Cash DEFAULT (0),
        MoMoPaid                        DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDRCS_MoMo DEFAULT (0),
        BankPaid                        DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDRCS_Bank DEFAULT (0),
        CreditAmount                    DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDRCS_Credit DEFAULT (0),
        Notes                           NVARCHAR(500) NULL,
        -- Once the parent return is Approved, the SP fills these so the UI
        -- can deep-link to the materialized sale.
        GeneratedWaterSaleId            INT           NULL,
        CreatedAt                       DATETIME2     NOT NULL CONSTRAINT DF_WDRCS_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                       DATETIME2     NULL,
        CONSTRAINT FK_WDRCS_Return   FOREIGN KEY (WaterDriverReturnId) REFERENCES dbo.WaterDriverReturns (WaterDriverReturnId) ON DELETE CASCADE,
        CONSTRAINT FK_WDRCS_Customer FOREIGN KEY (WaterCustomerId)     REFERENCES dbo.WaterCustomers (WaterCustomerId)
    );
    CREATE INDEX IX_WDRCS_Return   ON dbo.WaterDriverReturnCustomerSales (WaterDriverReturnId);
    CREATE INDEX IX_WDRCS_Customer ON dbo.WaterDriverReturnCustomerSales (WaterCustomerId);
END
GO

IF OBJECT_ID('dbo.WaterDriverReturnCustomerSaleItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDriverReturnCustomerSaleItems (
        WaterDriverReturnCustomerSaleItemId INT IDENTITY(1,1) PRIMARY KEY,
        WaterDriverReturnCustomerSaleId     INT           NOT NULL,
        WaterProductId                      INT           NOT NULL,
        Quantity                            INT           NOT NULL,
        UnitPrice                           DECIMAL(14,2) NOT NULL,
        LineTotal                           AS (CAST(Quantity AS DECIMAL(14,2)) * UnitPrice) PERSISTED,
        CreatedAt                           DATETIME2     NOT NULL CONSTRAINT DF_WDRCSI_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_WDRCSI_Sale    FOREIGN KEY (WaterDriverReturnCustomerSaleId) REFERENCES dbo.WaterDriverReturnCustomerSales (WaterDriverReturnCustomerSaleId) ON DELETE CASCADE,
        CONSTRAINT FK_WDRCSI_Product FOREIGN KEY (WaterProductId)                  REFERENCES dbo.WaterProducts (WaterProductId)
    );
    CREATE INDEX IX_WDRCSI_Sale ON dbo.WaterDriverReturnCustomerSaleItems (WaterDriverReturnCustomerSaleId);
END
GO

-- =============================================================================
-- 5. Delivery expenses
-- =============================================================================
IF OBJECT_ID('dbo.WaterDeliveryExpenses', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDeliveryExpenses (
        WaterDeliveryExpenseId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                 NVARCHAR(450) NOT NULL,
        WaterDriverReturnId    INT           NULL,
        WaterVehicleLoadingId  INT           NULL,
        ExpenseCategory        NVARCHAR(40)  NOT NULL,    -- 'Fuel' | 'LoadingBoys' | 'Toll' | 'Repair' | 'PhoneCredit' | 'Other'
        Amount                 DECIMAL(14,2) NOT NULL,
        Description            NVARCHAR(500) NULL,
        IsApproved             BIT           NOT NULL CONSTRAINT DF_WDE_IsApproved DEFAULT (1),
        Notes                  NVARCHAR(500) NULL,
        CreatedBy              NVARCHAR(450) NULL,
        CreatedAt              DATETIME2     NOT NULL CONSTRAINT DF_WDE_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt              DATETIME2     NULL,
        CONSTRAINT FK_WDE_Return  FOREIGN KEY (WaterDriverReturnId)   REFERENCES dbo.WaterDriverReturns (WaterDriverReturnId) ON DELETE CASCADE,
        CONSTRAINT FK_WDE_Loading FOREIGN KEY (WaterVehicleLoadingId) REFERENCES dbo.WaterVehicleLoadings (WaterVehicleLoadingId)
    );
    CREATE INDEX IX_WDE_FarmId  ON dbo.WaterDeliveryExpenses (FarmId);
    CREATE INDEX IX_WDE_Return  ON dbo.WaterDeliveryExpenses (WaterDriverReturnId);
    CREATE INDEX IX_WDE_Loading ON dbo.WaterDeliveryExpenses (WaterVehicleLoadingId);
END
GO

-- =============================================================================
-- 6. WaterVehicleLoading SPs — accept items JSON; legacy params still honored.
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterVehicleLoading_Insert
    @FarmId NVARCHAR(450),
    @LoadDate DATETIME2 = NULL,
    @WaterVehicleId INT, @WaterDriverId INT = NULL,
    @AssistantStaffId INT = NULL, @WaterRouteId INT = NULL,
    @WaterProductId INT = NULL,                       -- legacy: now optional when @ItemsJson is provided
    @BagsLoaded INT = NULL,
    @SachetsPerBag INT = 30,
    @ExpectedSellingPricePerBag DECIMAL(14,2) = NULL,
    @OpeningCashWithDriver DECIMAL(14,2) = 0,
    @LoadedByStaffId INT = NULL,
    @Notes NVARCHAR(500) = NULL,
    @CreatedBy NVARCHAR(450) = NULL,
    -- New: multi-product payload. JSON array of
    --   { "waterProductId": 1, "bagsLoaded": 650, "unitPrice": 30,
    --     "sachetsPerBag": 30, "notes": null }
    @ItemsJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Parse / decide which path we're on. If items are supplied use them as
    -- the source of truth; the legacy singular columns get the first item's
    -- values so existing reports keep returning something sensible.
    DECLARE @HasItems BIT = CASE WHEN @ItemsJson IS NOT NULL AND LEN(@ItemsJson) > 2 THEN 1 ELSE 0 END;

    IF @HasItems = 0
    BEGIN
        IF @WaterProductId IS NULL OR @BagsLoaded IS NULL OR @ExpectedSellingPricePerBag IS NULL
        BEGIN
            RAISERROR('Either provide @ItemsJson or all of @WaterProductId / @BagsLoaded / @ExpectedSellingPricePerBag.', 16, 1);
            RETURN;
        END
        IF (@BagsLoaded <= 0)
        BEGIN RAISERROR('BagsLoaded must be greater than zero.', 16, 1); RETURN; END
    END

    BEGIN TRANSACTION;

    -- Header. When items present, snapshot the first item's product/price/qty
    -- so the singular columns remain non-null (FK constraint on WaterProductId).
    DECLARE @HeaderProductId INT     = @WaterProductId,
            @HeaderBagsLoaded INT    = @BagsLoaded,
            @HeaderPrice DECIMAL(14,2) = @ExpectedSellingPricePerBag,
            @HeaderSachetsPerBag INT = @SachetsPerBag;

    IF @HasItems = 1
    BEGIN
        SELECT TOP 1
            @HeaderProductId     = WaterProductId,
            @HeaderBagsLoaded    = BagsLoaded,
            @HeaderPrice         = UnitPrice,
            @HeaderSachetsPerBag = ISNULL(SachetsPerBag, 30)
        FROM OPENJSON(@ItemsJson)
        WITH (
            WaterProductId  INT             '$.waterProductId',
            BagsLoaded      INT             '$.bagsLoaded',
            UnitPrice       DECIMAL(14,2)   '$.unitPrice',
            SachetsPerBag   INT             '$.sachetsPerBag'
        );
        -- Sum across items so the header's BagsLoaded reflects the whole run.
        SELECT @HeaderBagsLoaded = ISNULL(SUM(BagsLoaded), 0)
        FROM OPENJSON(@ItemsJson)
        WITH ( BagsLoaded INT '$.bagsLoaded' );
    END

    INSERT INTO dbo.WaterVehicleLoadings (
        FarmId, LoadDate, WaterVehicleId, WaterDriverId, AssistantStaffId, WaterRouteId,
        WaterProductId, BagsLoaded, SachetsPerBag, ExpectedSellingPricePerBag,
        OpeningCashWithDriver, LoadedByStaffId, Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, ISNULL(@LoadDate, SYSUTCDATETIME()), @WaterVehicleId, @WaterDriverId,
        @AssistantStaffId, @WaterRouteId, @HeaderProductId, @HeaderBagsLoaded,
        @HeaderSachetsPerBag, @HeaderPrice, @OpeningCashWithDriver, @LoadedByStaffId,
        'Draft', @Notes, @CreatedBy
    );
    DECLARE @LoadingId INT = CAST(SCOPE_IDENTITY() AS INT);

    IF @HasItems = 1
    BEGIN
        INSERT INTO dbo.WaterVehicleLoadingItems
            (WaterVehicleLoadingId, WaterProductId, BagsLoaded, SachetsPerBag, UnitPrice, Notes)
        SELECT @LoadingId, j.WaterProductId, ISNULL(j.BagsLoaded, 0),
               ISNULL(j.SachetsPerBag, 30), ISNULL(j.UnitPrice, 0), j.Notes
        FROM OPENJSON(@ItemsJson)
        WITH (
            WaterProductId  INT             '$.waterProductId',
            BagsLoaded      INT             '$.bagsLoaded',
            SachetsPerBag   INT             '$.sachetsPerBag',
            UnitPrice       DECIMAL(14,2)   '$.unitPrice',
            Notes           NVARCHAR(300)   '$.notes'
        ) j
        WHERE j.WaterProductId IS NOT NULL AND ISNULL(j.BagsLoaded, 0) > 0;
    END
    ELSE
    BEGIN
        -- Synthesize a single item row from the legacy params so downstream
        -- code can treat every loading as multi-item.
        INSERT INTO dbo.WaterVehicleLoadingItems
            (WaterVehicleLoadingId, WaterProductId, BagsLoaded, SachetsPerBag, UnitPrice)
        VALUES (@LoadingId, @WaterProductId, @BagsLoaded, @SachetsPerBag, @ExpectedSellingPricePerBag);
    END

    COMMIT TRANSACTION;

    SELECT @LoadingId;
END
GO

-- Approve loading: move stock per item (each LoadOut row is one product).
CREATE OR ALTER PROCEDURE dbo.spWaterVehicleLoading_Approve
    @WaterVehicleLoadingId INT, @FarmId NVARCHAR(450),
    @ApprovedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Idempotent: already loaded?
    IF EXISTS (SELECT 1 FROM dbo.WaterVehicleLoadings
               WHERE WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId
                 AND Status IN ('Loaded', 'Reconciled'))
    BEGIN
        SELECT WaterVehicleLoadingId, Status, ApprovedBy, ApprovedAt
        FROM dbo.WaterVehicleLoadings
        WHERE WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @Status NVARCHAR(20), @VehicleId INT;
    SELECT @Status = Status, @VehicleId = WaterVehicleId
    FROM   dbo.WaterVehicleLoadings
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL
    BEGIN RAISERROR('Loading %d not found.', 16, 1, @WaterVehicleLoadingId); RETURN; END
    IF @Status <> 'Draft'
    BEGIN RAISERROR('Loading cannot be approved from status %s.', 16, 1, @Status); RETURN; END

    -- Pre-flight per-item stock check.
    DECLARE @ShortName NVARCHAR(150), @ShortHave INT, @ShortNeed INT;
    SELECT TOP 1
           @ShortName = p.Name,
           @ShortHave = ISNULL(s.OnHand, 0),
           @ShortNeed = li.BagsLoaded
    FROM   dbo.WaterVehicleLoadingItems li
    JOIN   dbo.WaterProducts p ON p.WaterProductId = li.WaterProductId
    OUTER APPLY (
        SELECT SUM(Quantity) AS OnHand
        FROM   dbo.WaterStockTransactions
        WHERE  FarmId = @FarmId AND WaterProductId = li.WaterProductId
    ) s
    WHERE  li.WaterVehicleLoadingId = @WaterVehicleLoadingId
      AND  ISNULL(s.OnHand, 0) < li.BagsLoaded;

    IF @ShortName IS NOT NULL
    BEGIN
        DECLARE @msg NVARCHAR(400) = CONCAT(
            'Insufficient warehouse stock for ', @ShortName, ': on hand=',
            CAST(@ShortHave AS NVARCHAR(20)), ', trying to load ',
            CAST(@ShortNeed AS NVARCHAR(20)), '.'
        );
        RAISERROR(N'%s', 16, 1, @msg);
        RETURN;
    END

    BEGIN TRANSACTION;

    UPDATE dbo.WaterVehicleLoadings
    SET    Status = 'Loaded', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;

    INSERT INTO dbo.WaterStockTransactions
        (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
    SELECT @FarmId, li.WaterProductId, 'LoadOut', -li.BagsLoaded, NULL, NULL,
           CONCAT('Vehicle loading #', @WaterVehicleLoadingId, ', vehicle ', @VehicleId),
           @ApprovedBy
    FROM   dbo.WaterVehicleLoadingItems li
    WHERE  li.WaterVehicleLoadingId = @WaterVehicleLoadingId AND li.BagsLoaded > 0;

    COMMIT TRANSACTION;

    SELECT WaterVehicleLoadingId, Status, ApprovedBy, ApprovedAt
    FROM dbo.WaterVehicleLoadings
    WHERE WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- 7. Read SPs for the new sub-tables
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterVehicleLoading_GetItems
    @WaterVehicleLoadingId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  li.WaterVehicleLoadingItemId,
            li.WaterVehicleLoadingId,
            li.WaterProductId,
            p.Name AS ProductName,
            p.Unit AS ProductUnit,
            li.BagsLoaded,
            li.SachetsPerBag,
            li.UnitPrice,
            li.ExpectedAmount,
            li.Notes,
            li.CreatedAt,
            li.UpdatedAt
    FROM    dbo.WaterVehicleLoadingItems li
    INNER  JOIN dbo.WaterVehicleLoadings l ON l.WaterVehicleLoadingId = li.WaterVehicleLoadingId
    INNER  JOIN dbo.WaterProducts        p ON p.WaterProductId       = li.WaterProductId
    WHERE   li.WaterVehicleLoadingId = @WaterVehicleLoadingId
      AND   l.FarmId = @FarmId
    ORDER BY li.WaterVehicleLoadingItemId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_GetItems
    @WaterDriverReturnId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  ri.WaterDriverReturnItemId,
            ri.WaterDriverReturnId,
            ri.WaterProductId,
            p.Name AS ProductName,
            ri.BagsLoaded,
            ri.BagsSold,
            ri.BagsReturned,
            ri.BagsDamaged,
            ri.UnitPrice,
            ri.ExpectedSales,
            ri.Notes,
            ri.CreatedAt,
            ri.UpdatedAt
    FROM    dbo.WaterDriverReturnItems ri
    INNER  JOIN dbo.WaterDriverReturns r ON r.WaterDriverReturnId = ri.WaterDriverReturnId
    INNER  JOIN dbo.WaterProducts      p ON p.WaterProductId      = ri.WaterProductId
    WHERE   ri.WaterDriverReturnId = @WaterDriverReturnId
      AND   r.FarmId = @FarmId
    ORDER BY ri.WaterDriverReturnItemId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_GetCustomerSales
    @WaterDriverReturnId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    -- Sale headers + customer name.
    SELECT  cs.WaterDriverReturnCustomerSaleId,
            cs.WaterDriverReturnId,
            cs.WaterCustomerId,
            c.Name           AS CustomerName,
            cs.CustomerLabel,
            cs.TotalAmount,
            cs.CashPaid, cs.MoMoPaid, cs.BankPaid, cs.CreditAmount,
            cs.GeneratedWaterSaleId,
            cs.Notes,
            cs.CreatedAt, cs.UpdatedAt
    FROM    dbo.WaterDriverReturnCustomerSales cs
    INNER  JOIN dbo.WaterDriverReturns r ON r.WaterDriverReturnId = cs.WaterDriverReturnId
    LEFT   JOIN dbo.WaterCustomers     c ON c.WaterCustomerId     = cs.WaterCustomerId
    WHERE   cs.WaterDriverReturnId = @WaterDriverReturnId
      AND   r.FarmId = @FarmId
    ORDER BY cs.WaterDriverReturnCustomerSaleId;

    -- Items per sale.
    SELECT  csi.WaterDriverReturnCustomerSaleItemId,
            csi.WaterDriverReturnCustomerSaleId,
            csi.WaterProductId,
            p.Name AS ProductName,
            csi.Quantity, csi.UnitPrice, csi.LineTotal
    FROM    dbo.WaterDriverReturnCustomerSaleItems csi
    INNER  JOIN dbo.WaterDriverReturnCustomerSales cs ON cs.WaterDriverReturnCustomerSaleId = csi.WaterDriverReturnCustomerSaleId
    INNER  JOIN dbo.WaterDriverReturns             r  ON r.WaterDriverReturnId             = cs.WaterDriverReturnId
    INNER  JOIN dbo.WaterProducts                  p  ON p.WaterProductId                  = csi.WaterProductId
    WHERE   cs.WaterDriverReturnId = @WaterDriverReturnId
      AND   r.FarmId = @FarmId
    ORDER BY csi.WaterDriverReturnCustomerSaleItemId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDeliveryExpense_GetByReturn
    @WaterDriverReturnId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT *
    FROM   dbo.WaterDeliveryExpenses
    WHERE  WaterDriverReturnId = @WaterDriverReturnId
      AND  FarmId = @FarmId
    ORDER BY WaterDeliveryExpenseId;
END
GO

-- =============================================================================
-- 8. WaterDriverReturn SPs — accept items + customer breakdown + expenses
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_Insert
    @FarmId NVARCHAR(450),
    @WaterVehicleLoadingId INT,
    @ReturnDate DATETIME2 = NULL,
    @BagsSold INT,
    @BagsReturned INT,
    @BagsDamaged INT = 0,
    @MissingBags INT = 0,
    @CashCollected DECIMAL(14,2) = 0,
    @MoMoCollected DECIMAL(14,2) = 0,
    @BankCollected DECIMAL(14,2) = 0,
    @CreditSalesAmount DECIMAL(14,2) = 0,
    @CashReturnedByDriver DECIMAL(14,2) = 0,
    @ApprovedDeliveryExpenses DECIMAL(14,2) = 0,
    @ReconciledByStaffId INT = NULL,
    @Notes NVARCHAR(1000) = NULL,
    @CreatedBy NVARCHAR(450) = NULL,
    -- New: per-product reconciliation.
    --   [{ "waterProductId":1, "bagsSold":600, "bagsReturned":45,
    --      "bagsDamaged":5, "unitPrice":30, "notes":null }]
    @ItemsJson NVARCHAR(MAX) = NULL,
    -- New: customer breakdown.
    --   [{ "waterCustomerId":7, "customerLabel":null, "cashPaid":2000,
    --      "moMoPaid":500, "bankPaid":0, "creditAmount":500, "notes":null,
    --      "items":[{"waterProductId":1,"quantity":100,"unitPrice":30}, ...] }]
    @CustomerSalesJson NVARCHAR(MAX) = NULL,
    -- New: delivery expenses.
    --   [{ "expenseCategory":"Fuel", "amount":50, "description":null,
    --      "isApproved":true, "notes":null }]
    @ExpensesJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @BagsLoaded INT;
    SELECT @BagsLoaded = BagsLoaded FROM dbo.WaterVehicleLoadings
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;
    IF @BagsLoaded IS NULL
    BEGIN RAISERROR('Loading %d not found.', 16, 1, @WaterVehicleLoadingId); RETURN; END

    IF (@BagsSold + @BagsReturned + @BagsDamaged + @MissingBags) <> @BagsLoaded
    BEGIN
        RAISERROR('Bag accounting does not balance: %d sold + %d returned + %d damaged + %d missing != %d loaded.',
                  16, 1, @BagsSold, @BagsReturned, @BagsDamaged, @MissingBags, @BagsLoaded);
        RETURN;
    END

    BEGIN TRANSACTION;

    INSERT INTO dbo.WaterDriverReturns (
        FarmId, WaterVehicleLoadingId, ReturnDate, BagsSold, BagsReturned, BagsDamaged,
        MissingBags, CashCollected, MoMoCollected, BankCollected, CreditSalesAmount,
        CashReturnedByDriver, ApprovedDeliveryExpenses,
        ReconciledByStaffId, Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @WaterVehicleLoadingId, ISNULL(@ReturnDate, SYSUTCDATETIME()),
        @BagsSold, @BagsReturned, @BagsDamaged, @MissingBags,
        @CashCollected, @MoMoCollected, @BankCollected, @CreditSalesAmount,
        @CashReturnedByDriver, @ApprovedDeliveryExpenses,
        @ReconciledByStaffId, 'Draft', @Notes, @CreatedBy
    );
    DECLARE @ReturnId INT = CAST(SCOPE_IDENTITY() AS INT);

    -- Per-product reconciliation rows.
    IF @ItemsJson IS NOT NULL AND LEN(@ItemsJson) > 2
    BEGIN
        ;WITH src AS (
            SELECT j.WaterProductId, j.BagsSold, j.BagsReturned, j.BagsDamaged, j.UnitPrice, j.Notes
            FROM OPENJSON(@ItemsJson)
            WITH (
                WaterProductId  INT             '$.waterProductId',
                BagsSold        INT             '$.bagsSold',
                BagsReturned    INT             '$.bagsReturned',
                BagsDamaged     INT             '$.bagsDamaged',
                UnitPrice       DECIMAL(14,2)   '$.unitPrice',
                Notes           NVARCHAR(300)   '$.notes'
            ) j
        )
        INSERT INTO dbo.WaterDriverReturnItems
            (WaterDriverReturnId, WaterProductId, BagsLoaded, BagsSold, BagsReturned, BagsDamaged, UnitPrice, Notes)
        SELECT  @ReturnId,
                src.WaterProductId,
                ISNULL(li.BagsLoaded, 0),
                ISNULL(src.BagsSold, 0),
                ISNULL(src.BagsReturned, 0),
                ISNULL(src.BagsDamaged, 0),
                ISNULL(src.UnitPrice, li.UnitPrice),
                src.Notes
        FROM    src
        LEFT JOIN dbo.WaterVehicleLoadingItems li
               ON li.WaterVehicleLoadingId = @WaterVehicleLoadingId
              AND li.WaterProductId        = src.WaterProductId
        WHERE   src.WaterProductId IS NOT NULL;
    END

    -- Customer breakdown rows + items.
    IF @CustomerSalesJson IS NOT NULL AND LEN(@CustomerSalesJson) > 2
    BEGIN
        DECLARE @cs TABLE (
            Idx INT IDENTITY(1,1) PRIMARY KEY,
            NewId INT NULL,
            WaterCustomerId INT NULL,
            CustomerLabel   NVARCHAR(150),
            CashPaid        DECIMAL(14,2),
            MoMoPaid        DECIMAL(14,2),
            BankPaid        DECIMAL(14,2),
            CreditAmount    DECIMAL(14,2),
            Notes           NVARCHAR(500),
            ItemsJson       NVARCHAR(MAX)
        );

        INSERT INTO @cs (WaterCustomerId, CustomerLabel, CashPaid, MoMoPaid, BankPaid, CreditAmount, Notes, ItemsJson)
        SELECT j.WaterCustomerId, j.CustomerLabel,
               ISNULL(j.CashPaid, 0), ISNULL(j.MoMoPaid, 0),
               ISNULL(j.BankPaid, 0), ISNULL(j.CreditAmount, 0),
               j.Notes, j.ItemsJson
        FROM OPENJSON(@CustomerSalesJson)
        WITH (
            WaterCustomerId INT             '$.waterCustomerId',
            CustomerLabel   NVARCHAR(150)   '$.customerLabel',
            CashPaid        DECIMAL(14,2)   '$.cashPaid',
            MoMoPaid        DECIMAL(14,2)   '$.moMoPaid',
            BankPaid        DECIMAL(14,2)   '$.bankPaid',
            CreditAmount    DECIMAL(14,2)   '$.creditAmount',
            Notes           NVARCHAR(500)   '$.notes',
            ItemsJson       NVARCHAR(MAX)   '$.items' AS JSON
        ) j;

        -- Rename locals with @row prefix to avoid collisions with the SP's
        -- own @Notes / @ItemsJson parameters (SQL Server is case-insensitive
        -- about variable names).
        DECLARE @rowIdx INT = 1, @rowMax INT = (SELECT MAX(Idx) FROM @cs);
        DECLARE @rowCust INT, @rowLabel NVARCHAR(150),
                @rowCash DECIMAL(14,2), @rowMomo DECIMAL(14,2),
                @rowBank DECIMAL(14,2), @rowCredit DECIMAL(14,2),
                @rowNotes NVARCHAR(500), @rowItemsJson NVARCHAR(MAX),
                @rowTotalAmt DECIMAL(14,2), @newSaleId INT;

        WHILE @rowIdx <= @rowMax
        BEGIN
            SELECT @rowCust = WaterCustomerId, @rowLabel = CustomerLabel,
                   @rowCash = CashPaid, @rowMomo = MoMoPaid, @rowBank = BankPaid,
                   @rowCredit = CreditAmount, @rowNotes = Notes, @rowItemsJson = ItemsJson
            FROM   @cs WHERE Idx = @rowIdx;

            SET @rowTotalAmt = 0;
            IF @rowItemsJson IS NOT NULL AND LEN(@rowItemsJson) > 2
            BEGIN
                SELECT @rowTotalAmt = ISNULL(SUM(CAST(ji.Quantity AS DECIMAL(14,2)) * ji.UnitPrice), 0)
                FROM OPENJSON(@rowItemsJson)
                WITH (
                    WaterProductId  INT             '$.waterProductId',
                    Quantity        INT             '$.quantity',
                    UnitPrice       DECIMAL(14,2)   '$.unitPrice'
                ) ji;
            END

            INSERT INTO dbo.WaterDriverReturnCustomerSales
                (WaterDriverReturnId, WaterCustomerId, CustomerLabel,
                 TotalAmount, CashPaid, MoMoPaid, BankPaid, CreditAmount, Notes)
            VALUES (@ReturnId, @rowCust, @rowLabel, @rowTotalAmt,
                    @rowCash, @rowMomo, @rowBank, @rowCredit, @rowNotes);

            SET @newSaleId = CAST(SCOPE_IDENTITY() AS INT);
            UPDATE @cs SET NewId = @newSaleId WHERE Idx = @rowIdx;

            IF @rowItemsJson IS NOT NULL AND LEN(@rowItemsJson) > 2
            BEGIN
                INSERT INTO dbo.WaterDriverReturnCustomerSaleItems
                    (WaterDriverReturnCustomerSaleId, WaterProductId, Quantity, UnitPrice)
                SELECT @newSaleId, ji.WaterProductId, ji.Quantity, ji.UnitPrice
                FROM OPENJSON(@rowItemsJson)
                WITH (
                    WaterProductId  INT             '$.waterProductId',
                    Quantity        INT             '$.quantity',
                    UnitPrice       DECIMAL(14,2)   '$.unitPrice'
                ) ji
                WHERE ji.WaterProductId IS NOT NULL AND ji.Quantity > 0;
            END

            SET @rowIdx = @rowIdx + 1;
        END
    END

    -- Delivery expenses.
    IF @ExpensesJson IS NOT NULL AND LEN(@ExpensesJson) > 2
    BEGIN
        INSERT INTO dbo.WaterDeliveryExpenses
            (FarmId, WaterDriverReturnId, WaterVehicleLoadingId, ExpenseCategory,
             Amount, Description, IsApproved, Notes, CreatedBy)
        SELECT @FarmId, @ReturnId, @WaterVehicleLoadingId,
               ISNULL(NULLIF(j.ExpenseCategory, N''), N'Other'),
               ISNULL(j.Amount, 0), j.Description,
               ISNULL(j.IsApproved, 1), j.Notes, @CreatedBy
        FROM OPENJSON(@ExpensesJson)
        WITH (
            ExpenseCategory NVARCHAR(40)    '$.expenseCategory',
            Amount          DECIMAL(14,2)   '$.amount',
            Description     NVARCHAR(500)   '$.description',
            IsApproved      BIT             '$.isApproved',
            Notes           NVARCHAR(500)   '$.notes'
        ) j;
    END

    COMMIT TRANSACTION;

    SELECT @ReturnId;
END
GO

-- Approve return: per-item LoadReturnIn writes; materialize customer-sale rows
-- into WaterSales + WaterSaleItems + WaterPayments; update customer outstanding
-- balance via the existing trigger-free model.
CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_Approve
    @WaterDriverReturnId INT, @FarmId NVARCHAR(450),
    @ApprovedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.WaterDriverReturns
               WHERE WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT WaterDriverReturnId, Status, ApprovedBy, ApprovedAt
        FROM dbo.WaterDriverReturns
        WHERE WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @Status NVARCHAR(20), @LoadingId INT,
            @BagsSold INT, @BagsReturned INT, @BagsDamaged INT,
            @CashCollected DECIMAL(14,2), @MoMoCollected DECIMAL(14,2),
            @BankCollected DECIMAL(14,2), @CreditSalesAmount DECIMAL(14,2);

    SELECT @Status = Status, @LoadingId = WaterVehicleLoadingId,
           @BagsSold = BagsSold, @BagsReturned = BagsReturned, @BagsDamaged = BagsDamaged,
           @CashCollected = CashCollected, @MoMoCollected = MoMoCollected,
           @BankCollected = BankCollected, @CreditSalesAmount = CreditSalesAmount
    FROM   dbo.WaterDriverReturns
    WHERE  WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;

    IF @Status IS NULL
    BEGIN RAISERROR('Driver return %d not found.', 16, 1, @WaterDriverReturnId); RETURN; END
    IF @Status <> 'Draft'
    BEGIN RAISERROR('Driver return cannot be approved from status %s.', 16, 1, @Status); RETURN; END

    DECLARE @ProductId INT, @ExpectedPricePerBag DECIMAL(14,2),
            @DriverId INT, @VehicleId INT, @RouteId INT;
    SELECT @ProductId = WaterProductId, @ExpectedPricePerBag = ExpectedSellingPricePerBag,
           @DriverId = WaterDriverId, @VehicleId = WaterVehicleId, @RouteId = WaterRouteId
    FROM   dbo.WaterVehicleLoadings WHERE WaterVehicleLoadingId = @LoadingId AND FarmId = @FarmId;

    -- Expected cash: prefer per-item rows when present (multi-product), else
    -- fall back to legacy bagsSold * headerPrice.
    DECLARE @ExpectedCash DECIMAL(14,2);
    SELECT @ExpectedCash = ISNULL(SUM(ri.ExpectedSales), 0)
    FROM   dbo.WaterDriverReturnItems ri
    WHERE  ri.WaterDriverReturnId = @WaterDriverReturnId;
    IF @ExpectedCash = 0
        SET @ExpectedCash = CAST(@BagsSold AS DECIMAL(14,2)) * @ExpectedPricePerBag;

    DECLARE @TotalAccounted DECIMAL(14,2) = @CashCollected + @MoMoCollected + @BankCollected + @CreditSalesAmount;
    DECLARE @Shortage DECIMAL(14,2) = CASE WHEN @ExpectedCash > @TotalAccounted THEN @ExpectedCash - @TotalAccounted ELSE 0 END;
    DECLARE @Overage  DECIMAL(14,2) = CASE WHEN @TotalAccounted > @ExpectedCash THEN @TotalAccounted - @ExpectedCash ELSE 0 END;

    BEGIN TRANSACTION;

    UPDATE dbo.WaterDriverReturns
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME(),
           ShortageAmount = @Shortage, OverageAmount = @Overage
    WHERE  WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;

    UPDATE dbo.WaterVehicleLoadings
    SET    Status = 'Reconciled', UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterVehicleLoadingId = @LoadingId AND FarmId = @FarmId;

    -- Per-product LoadReturnIn movements. Multi-item branch when present, else
    -- fall back to the legacy single-product return.
    IF EXISTS (SELECT 1 FROM dbo.WaterDriverReturnItems WHERE WaterDriverReturnId = @WaterDriverReturnId)
    BEGIN
        INSERT INTO dbo.WaterStockTransactions
            (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
        SELECT @FarmId, ri.WaterProductId, 'LoadReturnIn', ri.BagsReturned, NULL, NULL,
               CONCAT('Driver return #', @WaterDriverReturnId, ' for loading #', @LoadingId),
               @ApprovedBy
        FROM   dbo.WaterDriverReturnItems ri
        WHERE  ri.WaterDriverReturnId = @WaterDriverReturnId
          AND  ri.BagsReturned > 0;
    END
    ELSE IF (@BagsReturned > 0)
    BEGIN
        INSERT INTO dbo.WaterStockTransactions
            (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
        VALUES (
            @FarmId, @ProductId, 'LoadReturnIn', @BagsReturned, NULL, NULL,
            CONCAT('Driver return #', @WaterDriverReturnId, ' for loading #', @LoadingId),
            @ApprovedBy
        );
    END

    -- Materialize customer breakdown into WaterSales/Items/Payments.
    -- Stock has ALREADY moved on LoadOut, so we don't write Sale stock txns
    -- here (avoiding double-decrement).
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT cs.WaterDriverReturnCustomerSaleId,
               cs.WaterCustomerId, cs.TotalAmount,
               cs.CashPaid, cs.MoMoPaid, cs.BankPaid, cs.CreditAmount,
               cs.Notes
        FROM   dbo.WaterDriverReturnCustomerSales cs
        WHERE  cs.WaterDriverReturnId = @WaterDriverReturnId;

    DECLARE @csId INT, @custId INT, @tot DECIMAL(14,2),
            @cash DECIMAL(14,2), @momo DECIMAL(14,2), @bank DECIMAL(14,2),
            @credit DECIMAL(14,2), @csNotes NVARCHAR(500);

    OPEN cur;
    FETCH NEXT FROM cur INTO @csId, @custId, @tot, @cash, @momo, @bank, @credit, @csNotes;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @paid DECIMAL(14,2) = @cash + @momo + @bank;
        DECLARE @balance DECIMAL(14,2) = @tot - @paid;
        DECLARE @saleStatus NVARCHAR(30) =
            CASE WHEN @balance <= 0 THEN 'Paid'
                 WHEN @paid > 0     THEN 'PartiallyPaid'
                 ELSE 'Pending' END;

        INSERT INTO dbo.WaterSales
            (FarmId, WaterCustomerId, SaleDate, TotalAmount, AmountPaid, Status, Notes,
             CreatedBy, SourceType, SourceId, WaterDriverId, WaterVehicleId, WaterRouteId)
        VALUES
            (@FarmId, @custId, SYSUTCDATETIME(), @tot, @paid, @saleStatus, @csNotes,
             @ApprovedBy, 'DeliveryRun', @WaterDriverReturnId, @DriverId, @VehicleId, @RouteId);

        DECLARE @saleId INT = CAST(SCOPE_IDENTITY() AS INT);

        INSERT INTO dbo.WaterSaleItems (WaterSaleId, WaterProductId, Quantity, UnitPrice)
        SELECT @saleId, csi.WaterProductId, csi.Quantity, csi.UnitPrice
        FROM   dbo.WaterDriverReturnCustomerSaleItems csi
        WHERE  csi.WaterDriverReturnCustomerSaleId = @csId;

        -- One payment row per non-zero method.
        IF (@cash > 0)
            INSERT INTO dbo.WaterPayments
                (FarmId, WaterSaleId, Amount, PaymentMethod, PaymentDate, Reference, Note,
                 CreatedBy, WaterCustomerId, SourceType, SourceId)
            VALUES
                (@FarmId, @saleId, @cash, 'Cash', SYSUTCDATETIME(),
                 CONCAT('DR#', @WaterDriverReturnId), NULL,
                 @ApprovedBy, @custId, 'DeliveryRun', @WaterDriverReturnId);

        IF (@momo > 0)
            INSERT INTO dbo.WaterPayments
                (FarmId, WaterSaleId, Amount, PaymentMethod, PaymentDate, Reference, Note,
                 CreatedBy, WaterCustomerId, SourceType, SourceId)
            VALUES
                (@FarmId, @saleId, @momo, 'Mobile Money', SYSUTCDATETIME(),
                 CONCAT('DR#', @WaterDriverReturnId), NULL,
                 @ApprovedBy, @custId, 'DeliveryRun', @WaterDriverReturnId);

        IF (@bank > 0)
            INSERT INTO dbo.WaterPayments
                (FarmId, WaterSaleId, Amount, PaymentMethod, PaymentDate, Reference, Note,
                 CreatedBy, WaterCustomerId, SourceType, SourceId)
            VALUES
                (@FarmId, @saleId, @bank, 'Bank', SYSUTCDATETIME(),
                 CONCAT('DR#', @WaterDriverReturnId), NULL,
                 @ApprovedBy, @custId, 'DeliveryRun', @WaterDriverReturnId);

        UPDATE dbo.WaterDriverReturnCustomerSales
        SET    GeneratedWaterSaleId = @saleId, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterDriverReturnCustomerSaleId = @csId;

        FETCH NEXT FROM cur INTO @csId, @custId, @tot, @cash, @momo, @bank, @credit, @csNotes;
    END
    CLOSE cur;
    DEALLOCATE cur;

    -- Shortage row (legacy behaviour).
    IF (@Shortage > 0)
    BEGIN
        INSERT INTO dbo.WaterDriverShortages (
            FarmId, WaterDriverId, WaterVehicleLoadingId, WaterDriverReturnId,
            ShortageDate, ExpectedAmount, ActualAmount, ShortageAmount,
            Reason, Status, Notes
        )
        VALUES (
            @FarmId, @DriverId, @LoadingId, @WaterDriverReturnId,
            SYSUTCDATETIME(), @ExpectedCash, @TotalAccounted, @Shortage,
            NULL, 'Pending', NULL
        );
    END

    COMMIT TRANSACTION;

    SELECT WaterDriverReturnId, Status, ApprovedBy, ApprovedAt,
           ShortageAmount, OverageAmount
    FROM dbo.WaterDriverReturns
    WHERE WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- 9. Grants
-- =============================================================================
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'PoultryAppRole' AND type = 'R')
BEGIN
    GRANT EXECUTE ON dbo.spWaterVehicleLoading_Insert     TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterVehicleLoading_Approve    TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterVehicleLoading_GetItems   TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterDriverReturn_Insert       TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterDriverReturn_Approve      TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterDriverReturn_GetItems     TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterDriverReturn_GetCustomerSales TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterDeliveryExpense_GetByReturn   TO PoultryAppRole;
END
GO

PRINT '064_AddWaterDeliveryRunsAndCustomerBreakdown.sql complete.';
GO

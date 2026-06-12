-- =============================================================================
-- Migration 041: Water Company — Distribution stored procedures
-- =============================================================================
-- Phase W2 SPs. Run AFTER 040_AddWaterDistributionSchema.sql.
--
-- Two big atomic ones:
--   * spWaterVehicleLoading_Approve — Draft → Loaded, writes LoadOut stock txn
--     for -BagsLoaded.
--   * spWaterDriverReturn_Approve — Draft → Approved:
--       1. Validate BagsSold + BagsReturned + BagsDamaged + MissingBags = BagsLoaded
--       2. Compute Expected vs Actual cash, store ShortageAmount/OverageAmount
--       3. Write LoadReturnIn stock txn for +BagsReturned
--       4. If ShortageAmount > 0 → insert WaterDriverShortages row
--       5. Parent loading status → 'Reconciled'
--     Idempotent if already Approved.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- WaterDriver CRUD
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterDriver_GetAll @FarmId NVARCHAR(450) AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.WaterDrivers WHERE FarmId = @FarmId
    ORDER BY IsActive DESC, DriverName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDriver_GetById @WaterDriverId INT, @FarmId NVARCHAR(450) AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.WaterDrivers WHERE WaterDriverId = @WaterDriverId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDriver_Insert
    @FarmId NVARCHAR(450), @DriverName NVARCHAR(150),
    @PhoneNumber NVARCHAR(50) = NULL, @LicenseNumber NVARCHAR(60) = NULL,
    @DefaultVehicleId INT = NULL, @DefaultRouteId INT = NULL,
    @BasePay DECIMAL(14,2) = NULL, @CommissionPerBag DECIMAL(14,2) = NULL,
    @IsActive BIT = 1, @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterDrivers (FarmId, DriverName, PhoneNumber, LicenseNumber,
        DefaultVehicleId, DefaultRouteId, BasePay, CommissionPerBag, IsActive, Notes)
    VALUES (@FarmId, @DriverName, @PhoneNumber, @LicenseNumber,
        @DefaultVehicleId, @DefaultRouteId, @BasePay, @CommissionPerBag, @IsActive, @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDriver_Update
    @WaterDriverId INT, @FarmId NVARCHAR(450), @DriverName NVARCHAR(150),
    @PhoneNumber NVARCHAR(50) = NULL, @LicenseNumber NVARCHAR(60) = NULL,
    @DefaultVehicleId INT = NULL, @DefaultRouteId INT = NULL,
    @BasePay DECIMAL(14,2) = NULL, @CommissionPerBag DECIMAL(14,2) = NULL,
    @IsActive BIT, @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterDrivers
    SET DriverName = @DriverName, PhoneNumber = @PhoneNumber, LicenseNumber = @LicenseNumber,
        DefaultVehicleId = @DefaultVehicleId, DefaultRouteId = @DefaultRouteId,
        BasePay = @BasePay, CommissionPerBag = @CommissionPerBag,
        IsActive = @IsActive, Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE WaterDriverId = @WaterDriverId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDriver_Delete @WaterDriverId INT, @FarmId NVARCHAR(450) AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterDrivers SET IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE WaterDriverId = @WaterDriverId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- WaterVehicle CRUD
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterVehicle_GetAll @FarmId NVARCHAR(450) AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.*, d.DriverName AS DefaultDriverName
    FROM dbo.WaterVehicles v
    LEFT JOIN dbo.WaterDrivers d ON d.WaterDriverId = v.DefaultDriverId
    WHERE v.FarmId = @FarmId
    ORDER BY (CASE WHEN v.Status = 'Active' THEN 0 ELSE 1 END), v.VehicleName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterVehicle_GetById @WaterVehicleId INT, @FarmId NVARCHAR(450) AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.*, d.DriverName AS DefaultDriverName
    FROM dbo.WaterVehicles v
    LEFT JOIN dbo.WaterDrivers d ON d.WaterDriverId = v.DefaultDriverId
    WHERE v.WaterVehicleId = @WaterVehicleId AND v.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterVehicle_Insert
    @FarmId NVARCHAR(450), @VehicleName NVARCHAR(150),
    @VehicleType NVARCHAR(30) = NULL, @RegistrationNumber NVARCHAR(60) = NULL,
    @DefaultDriverId INT = NULL, @CapacityBags INT = NULL,
    @FuelType NVARCHAR(30) = NULL, @Status NVARCHAR(30) = 'Active',
    @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterVehicles (FarmId, VehicleName, VehicleType, RegistrationNumber,
        DefaultDriverId, CapacityBags, FuelType, Status, Notes)
    VALUES (@FarmId, @VehicleName, @VehicleType, @RegistrationNumber,
        @DefaultDriverId, @CapacityBags, @FuelType, @Status, @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterVehicle_Update
    @WaterVehicleId INT, @FarmId NVARCHAR(450), @VehicleName NVARCHAR(150),
    @VehicleType NVARCHAR(30) = NULL, @RegistrationNumber NVARCHAR(60) = NULL,
    @DefaultDriverId INT = NULL, @CapacityBags INT = NULL,
    @FuelType NVARCHAR(30) = NULL, @Status NVARCHAR(30),
    @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterVehicles
    SET VehicleName = @VehicleName, VehicleType = @VehicleType, RegistrationNumber = @RegistrationNumber,
        DefaultDriverId = @DefaultDriverId, CapacityBags = @CapacityBags,
        FuelType = @FuelType, Status = @Status, Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE WaterVehicleId = @WaterVehicleId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterVehicle_Delete @WaterVehicleId INT, @FarmId NVARCHAR(450) AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterVehicles SET Status = 'Inactive', UpdatedAt = SYSUTCDATETIME()
    WHERE WaterVehicleId = @WaterVehicleId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- WaterRoute CRUD
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterRoute_GetAll @FarmId NVARCHAR(450) AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.*, d.DriverName AS DefaultDriverName, v.VehicleName AS DefaultVehicleName
    FROM dbo.WaterRoutes r
    LEFT JOIN dbo.WaterDrivers d  ON d.WaterDriverId = r.DefaultDriverId
    LEFT JOIN dbo.WaterVehicles v ON v.WaterVehicleId = r.DefaultVehicleId
    WHERE r.FarmId = @FarmId
    ORDER BY r.IsActive DESC, r.RouteName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRoute_GetById @WaterRouteId INT, @FarmId NVARCHAR(450) AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.*, d.DriverName AS DefaultDriverName, v.VehicleName AS DefaultVehicleName
    FROM dbo.WaterRoutes r
    LEFT JOIN dbo.WaterDrivers d  ON d.WaterDriverId = r.DefaultDriverId
    LEFT JOIN dbo.WaterVehicles v ON v.WaterVehicleId = r.DefaultVehicleId
    WHERE r.WaterRouteId = @WaterRouteId AND r.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRoute_Insert
    @FarmId NVARCHAR(450), @RouteName NVARCHAR(150),
    @AreaCovered NVARCHAR(500) = NULL,
    @DefaultDriverId INT = NULL, @DefaultVehicleId INT = NULL,
    @ExpectedCustomers INT = NULL, @ExpectedBagsSold INT = NULL,
    @Notes NVARCHAR(500) = NULL, @IsActive BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterRoutes (FarmId, RouteName, AreaCovered, DefaultDriverId, DefaultVehicleId,
        ExpectedCustomers, ExpectedBagsSold, Notes, IsActive)
    VALUES (@FarmId, @RouteName, @AreaCovered, @DefaultDriverId, @DefaultVehicleId,
        @ExpectedCustomers, @ExpectedBagsSold, @Notes, @IsActive);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRoute_Update
    @WaterRouteId INT, @FarmId NVARCHAR(450), @RouteName NVARCHAR(150),
    @AreaCovered NVARCHAR(500) = NULL,
    @DefaultDriverId INT = NULL, @DefaultVehicleId INT = NULL,
    @ExpectedCustomers INT = NULL, @ExpectedBagsSold INT = NULL,
    @Notes NVARCHAR(500) = NULL, @IsActive BIT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterRoutes
    SET RouteName = @RouteName, AreaCovered = @AreaCovered,
        DefaultDriverId = @DefaultDriverId, DefaultVehicleId = @DefaultVehicleId,
        ExpectedCustomers = @ExpectedCustomers, ExpectedBagsSold = @ExpectedBagsSold,
        Notes = @Notes, IsActive = @IsActive, UpdatedAt = SYSUTCDATETIME()
    WHERE WaterRouteId = @WaterRouteId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRoute_Delete @WaterRouteId INT, @FarmId NVARCHAR(450) AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterRoutes SET IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE WaterRouteId = @WaterRouteId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- WaterVehicleLoading
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterVehicleLoading_GetAll
    @FarmId NVARCHAR(450),
    @Status NVARCHAR(20) = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT l.*, v.VehicleName, d.DriverName, r.RouteName, p.Name AS ProductName
    FROM   dbo.WaterVehicleLoadings l
    INNER  JOIN dbo.WaterVehicles v ON v.WaterVehicleId = l.WaterVehicleId
    LEFT   JOIN dbo.WaterDrivers  d ON d.WaterDriverId  = l.WaterDriverId
    LEFT   JOIN dbo.WaterRoutes   r ON r.WaterRouteId   = l.WaterRouteId
    INNER  JOIN dbo.WaterProducts p ON p.WaterProductId = l.WaterProductId
    WHERE  l.FarmId = @FarmId AND l.IsDeleted = 0
       AND (@Status   IS NULL OR l.Status = @Status)
       AND (@FromDate IS NULL OR CAST(l.LoadDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(l.LoadDate AS DATE) <= @ToDate)
    ORDER  BY l.LoadDate DESC, l.WaterVehicleLoadingId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterVehicleLoading_GetById
    @WaterVehicleLoadingId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT l.*, v.VehicleName, d.DriverName, r.RouteName, p.Name AS ProductName
    FROM   dbo.WaterVehicleLoadings l
    INNER  JOIN dbo.WaterVehicles v ON v.WaterVehicleId = l.WaterVehicleId
    LEFT   JOIN dbo.WaterDrivers  d ON d.WaterDriverId  = l.WaterDriverId
    LEFT   JOIN dbo.WaterRoutes   r ON r.WaterRouteId   = l.WaterRouteId
    INNER  JOIN dbo.WaterProducts p ON p.WaterProductId = l.WaterProductId
    WHERE  l.WaterVehicleLoadingId = @WaterVehicleLoadingId AND l.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterVehicleLoading_Insert
    @FarmId NVARCHAR(450),
    @LoadDate DATETIME2 = NULL,
    @WaterVehicleId INT, @WaterDriverId INT = NULL,
    @AssistantStaffId INT = NULL, @WaterRouteId INT = NULL,
    @WaterProductId INT, @BagsLoaded INT,
    @SachetsPerBag INT = 30,
    @ExpectedSellingPricePerBag DECIMAL(14,2),
    @OpeningCashWithDriver DECIMAL(14,2) = 0,
    @LoadedByStaffId INT = NULL,
    @Notes NVARCHAR(500) = NULL,
    @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@BagsLoaded <= 0)
    BEGIN RAISERROR('BagsLoaded must be greater than zero.', 16, 1); RETURN; END

    INSERT INTO dbo.WaterVehicleLoadings (
        FarmId, LoadDate, WaterVehicleId, WaterDriverId, AssistantStaffId, WaterRouteId,
        WaterProductId, BagsLoaded, SachetsPerBag, ExpectedSellingPricePerBag,
        OpeningCashWithDriver, LoadedByStaffId, Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, ISNULL(@LoadDate, SYSUTCDATETIME()), @WaterVehicleId, @WaterDriverId,
        @AssistantStaffId, @WaterRouteId, @WaterProductId, @BagsLoaded, @SachetsPerBag,
        @ExpectedSellingPricePerBag, @OpeningCashWithDriver, @LoadedByStaffId,
        'Draft', @Notes, @CreatedBy
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

-- Approve loading: Draft → Loaded, write LoadOut stock txn (-BagsLoaded).
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

    DECLARE @Status NVARCHAR(20), @ProductId INT, @BagsLoaded INT, @VehicleId INT;
    SELECT @Status = Status, @ProductId = WaterProductId, @BagsLoaded = BagsLoaded, @VehicleId = WaterVehicleId
    FROM   dbo.WaterVehicleLoadings
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL
    BEGIN RAISERROR('Loading %d not found.', 16, 1, @WaterVehicleLoadingId); RETURN; END
    IF @Status <> 'Draft'
    BEGIN RAISERROR('Loading cannot be approved from status %s.', 16, 1, @Status); RETURN; END

    -- Pre-flight: enough stock on hand?
    DECLARE @OnHand INT = ISNULL((
        SELECT SUM(Quantity) FROM dbo.WaterStockTransactions
        WHERE FarmId = @FarmId AND WaterProductId = @ProductId
    ), 0);
    IF (@OnHand - @BagsLoaded < 0)
    BEGIN
        RAISERROR('Insufficient warehouse stock: on hand=%d, trying to load %d.', 16, 1, @OnHand, @BagsLoaded);
        RETURN;
    END

    BEGIN TRANSACTION;

    UPDATE dbo.WaterVehicleLoadings
    SET    Status = 'Loaded', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;

    INSERT INTO dbo.WaterStockTransactions (
        FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy
    )
    VALUES (
        @FarmId, @ProductId, 'LoadOut', -@BagsLoaded, NULL, NULL,
        CONCAT('Vehicle loading #', @WaterVehicleLoadingId, ', vehicle ', @VehicleId),
        @ApprovedBy
    );

    COMMIT TRANSACTION;

    SELECT WaterVehicleLoadingId, Status, ApprovedBy, ApprovedAt
    FROM dbo.WaterVehicleLoadings
    WHERE WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterVehicleLoading_Cancel
    @WaterVehicleLoadingId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterVehicleLoadings
    SET    IsDeleted = 1, Status = 'Cancelled', UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId AND Status = 'Draft';
    IF @@ROWCOUNT = 0
    BEGIN RAISERROR('Only Draft loadings can be cancelled.', 16, 1); RETURN; END
END
GO

-- =============================================================================
-- WaterDriverReturn — the reconciliation centrepiece
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_GetAll
    @FarmId NVARCHAR(450),
    @Status NVARCHAR(20) = NULL,
    @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT dr.*, l.WaterVehicleId, l.WaterDriverId, l.WaterRouteId,
           l.BagsLoaded AS LoadingBagsLoaded, l.ExpectedCash AS LoadingExpectedCash,
           v.VehicleName, d.DriverName, r.RouteName
    FROM   dbo.WaterDriverReturns dr
    INNER  JOIN dbo.WaterVehicleLoadings l ON l.WaterVehicleLoadingId = dr.WaterVehicleLoadingId
    INNER  JOIN dbo.WaterVehicles  v ON v.WaterVehicleId = l.WaterVehicleId
    LEFT   JOIN dbo.WaterDrivers   d ON d.WaterDriverId  = l.WaterDriverId
    LEFT   JOIN dbo.WaterRoutes    r ON r.WaterRouteId   = l.WaterRouteId
    WHERE  dr.FarmId = @FarmId
       AND (@Status   IS NULL OR dr.Status = @Status)
       AND (@FromDate IS NULL OR CAST(dr.ReturnDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(dr.ReturnDate AS DATE) <= @ToDate)
    ORDER  BY dr.ReturnDate DESC, dr.WaterDriverReturnId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_GetById
    @WaterDriverReturnId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT dr.*, l.WaterVehicleId, l.WaterDriverId, l.WaterRouteId,
           l.BagsLoaded AS LoadingBagsLoaded, l.ExpectedCash AS LoadingExpectedCash,
           l.ExpectedSellingPricePerBag,
           v.VehicleName, d.DriverName, r.RouteName
    FROM   dbo.WaterDriverReturns dr
    INNER  JOIN dbo.WaterVehicleLoadings l ON l.WaterVehicleLoadingId = dr.WaterVehicleLoadingId
    INNER  JOIN dbo.WaterVehicles  v ON v.WaterVehicleId = l.WaterVehicleId
    LEFT   JOIN dbo.WaterDrivers   d ON d.WaterDriverId  = l.WaterDriverId
    LEFT   JOIN dbo.WaterRoutes    r ON r.WaterRouteId   = l.WaterRouteId
    WHERE  dr.WaterDriverReturnId = @WaterDriverReturnId AND dr.FarmId = @FarmId;
END
GO

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
    @ReconciledByStaffId INT = NULL,
    @Notes NVARCHAR(1000) = NULL,
    @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Reconciliation: total bags must equal what was loaded.
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

    INSERT INTO dbo.WaterDriverReturns (
        FarmId, WaterVehicleLoadingId, ReturnDate, BagsSold, BagsReturned, BagsDamaged,
        MissingBags, CashCollected, MoMoCollected, BankCollected, CreditSalesAmount,
        ReconciledByStaffId, Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @WaterVehicleLoadingId, ISNULL(@ReturnDate, SYSUTCDATETIME()),
        @BagsSold, @BagsReturned, @BagsDamaged, @MissingBags,
        @CashCollected, @MoMoCollected, @BankCollected, @CreditSalesAmount,
        @ReconciledByStaffId, 'Draft', @Notes, @CreatedBy
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

-- THE BIG ONE — atomic driver-return reconciliation.
CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_Approve
    @WaterDriverReturnId INT, @FarmId NVARCHAR(450),
    @ApprovedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Idempotent
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

    -- Loading details
    DECLARE @ProductId INT, @ExpectedPricePerBag DECIMAL(14,2), @DriverId INT;
    SELECT @ProductId = WaterProductId, @ExpectedPricePerBag = ExpectedSellingPricePerBag,
           @DriverId = WaterDriverId
    FROM   dbo.WaterVehicleLoadings WHERE WaterVehicleLoadingId = @LoadingId AND FarmId = @FarmId;

    DECLARE @ExpectedCash DECIMAL(14,2) = CAST(@BagsSold AS DECIMAL(14,2)) * @ExpectedPricePerBag;
    DECLARE @TotalAccounted DECIMAL(14,2) = @CashCollected + @MoMoCollected + @BankCollected + @CreditSalesAmount;
    DECLARE @Shortage DECIMAL(14,2) = CASE WHEN @ExpectedCash > @TotalAccounted THEN @ExpectedCash - @TotalAccounted ELSE 0 END;
    DECLARE @Overage  DECIMAL(14,2) = CASE WHEN @TotalAccounted > @ExpectedCash THEN @TotalAccounted - @ExpectedCash ELSE 0 END;

    BEGIN TRANSACTION;

    -- 1. Mark return approved + record shortage/overage on the return row.
    UPDATE dbo.WaterDriverReturns
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME(),
           ShortageAmount = @Shortage, OverageAmount = @Overage
    WHERE  WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;

    -- 2. Mark loading reconciled.
    UPDATE dbo.WaterVehicleLoadings
    SET    Status = 'Reconciled', UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterVehicleLoadingId = @LoadingId AND FarmId = @FarmId;

    -- 3. Stock back: write LoadReturnIn for the returned bags (positive).
    IF (@BagsReturned > 0)
    BEGIN
        INSERT INTO dbo.WaterStockTransactions (
            FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy
        )
        VALUES (
            @FarmId, @ProductId, 'LoadReturnIn', @BagsReturned, NULL, NULL,
            CONCAT('Driver return #', @WaterDriverReturnId, ' for loading #', @LoadingId),
            @ApprovedBy
        );
    END

    -- 4. If any shortage, insert into WaterDriverShortages for follow-up.
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

CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_Cancel
    @WaterDriverReturnId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterDriverReturns SET Status = 'Cancelled', UpdatedAt = SYSUTCDATETIME()
    WHERE WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId AND Status = 'Draft';
    IF @@ROWCOUNT = 0
    BEGIN RAISERROR('Only Draft returns can be cancelled.', 16, 1); RETURN; END
END
GO

-- =============================================================================
-- WaterDriverShortage management (read + resolve)
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterDriverShortage_GetAll
    @FarmId NVARCHAR(450), @Status NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.*, d.DriverName
    FROM   dbo.WaterDriverShortages s
    LEFT   JOIN dbo.WaterDrivers d ON d.WaterDriverId = s.WaterDriverId
    WHERE  s.FarmId = @FarmId
       AND (@Status IS NULL OR s.Status = @Status)
    ORDER  BY s.ShortageDate DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDriverShortage_Resolve
    @WaterDriverShortageId INT, @FarmId NVARCHAR(450),
    @NewStatus NVARCHAR(20),  -- 'Approved' | 'Deducted' | 'Waived' | 'Pending'
    @Reason NVARCHAR(500) = NULL, @ApprovedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @NewStatus NOT IN ('Pending', 'Approved', 'Deducted', 'Waived')
    BEGIN RAISERROR('Invalid status %s.', 16, 1, @NewStatus); RETURN; END

    UPDATE dbo.WaterDriverShortages
    SET    Status = @NewStatus, Reason = COALESCE(@Reason, Reason),
           ApprovedBy = @ApprovedBy, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterDriverShortageId = @WaterDriverShortageId AND FarmId = @FarmId;
END
GO

PRINT '041_AddWaterDistributionStoredProcedures.sql complete.';
GO

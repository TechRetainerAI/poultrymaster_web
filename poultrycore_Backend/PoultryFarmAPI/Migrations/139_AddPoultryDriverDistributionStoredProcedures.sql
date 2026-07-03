-- =============================================================================
-- Migration 139: Poultry Driver Distribution — stored procedures
-- =============================================================================
-- Full-fidelity port of the water driver SPs, adapted to POST INTO THE POULTRY
-- LEDGERS (the same ones the flat spPoultryDelivery_Reconcile uses, migration
-- 133), so the driver module flows into poultry daily-closing / P&L for free:
--     sold          -> dbo.Sale
--     delivery exp   -> dbo.Expense
--     cash collected -> dbo.CashAdjustment ('In')
--     damaged+missing-> dbo.PoultryProductionLoss
--     stock          -> dbo.PoultryStockTransactions ('Driver Load Out' /
--                       'Driver Return In')
--
-- Money/stock rows are traceable for reversal:
--   * Sale        via PoultryDriverReturnCustomerSales.GeneratedSaleId
--   * Expense     via PoultryDriverDeliveryExpenses.LinkedExpenseId
--   * CashAdjust  via PoultryDriverReturns.LinkedCashAdjId
--   * Stock       via PoultryStockTransactions.RelatedId + TxnType
--   * Loss        via SourceType='PoultryDriverReturn' + SourceId
--
-- Idempotent (CREATE OR ALTER). Poultry generic Sale is single-line, so each
-- customer-breakdown row materializes ONE summary Sale (per-product detail is
-- retained in PoultryDriverReturnCustomerSaleItems for the module's reports).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- #############################################################################
-- MASTERS: Drivers
-- #############################################################################

CREATE OR ALTER PROCEDURE dbo.spPoultryDriver_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.PoultryDrivers WHERE FarmId = @FarmId ORDER BY DriverName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDriver_GetById
    @PoultryDriverId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.PoultryDrivers WHERE PoultryDriverId = @PoultryDriverId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDriver_Insert
    @FarmId NVARCHAR(450), @DriverName NVARCHAR(150), @PhoneNumber NVARCHAR(50) = NULL,
    @LicenseNumber NVARCHAR(60) = NULL, @DefaultVehicleId INT = NULL, @DefaultRouteId INT = NULL,
    @BasePay DECIMAL(14,2) = NULL, @CommissionPerCrate DECIMAL(14,2) = NULL,
    @IsActive BIT = 1, @EmployeeUserId NVARCHAR(450) = NULL, @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.PoultryDrivers
        (FarmId, DriverName, PhoneNumber, LicenseNumber, DefaultVehicleId, DefaultRouteId,
         BasePay, CommissionPerCrate, IsActive, EmployeeUserId, Notes)
    VALUES
        (@FarmId, @DriverName, @PhoneNumber, @LicenseNumber, @DefaultVehicleId, @DefaultRouteId,
         @BasePay, @CommissionPerCrate, @IsActive, @EmployeeUserId, @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDriver_Update
    @PoultryDriverId INT, @FarmId NVARCHAR(450), @DriverName NVARCHAR(150), @PhoneNumber NVARCHAR(50) = NULL,
    @LicenseNumber NVARCHAR(60) = NULL, @DefaultVehicleId INT = NULL, @DefaultRouteId INT = NULL,
    @BasePay DECIMAL(14,2) = NULL, @CommissionPerCrate DECIMAL(14,2) = NULL,
    @IsActive BIT = 1, @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryDrivers
    SET DriverName = @DriverName, PhoneNumber = @PhoneNumber, LicenseNumber = @LicenseNumber,
        DefaultVehicleId = @DefaultVehicleId, DefaultRouteId = @DefaultRouteId,
        BasePay = @BasePay, CommissionPerCrate = @CommissionPerCrate, IsActive = @IsActive,
        Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryDriverId = @PoultryDriverId AND FarmId = @FarmId;
    SELECT @@ROWCOUNT;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDriver_Delete
    @PoultryDriverId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.PoultryDrivers WHERE PoultryDriverId = @PoultryDriverId AND FarmId = @FarmId;
    SELECT @@ROWCOUNT;
END
GO

-- List for farm: drivers plus (if linked) the employee's email/name.
CREATE OR ALTER PROCEDURE dbo.spPoultryDriver_ListForFarm
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.*,
           u.Email    AS EmployeeEmail,
           u.UserName AS EmployeeUserName
    FROM   dbo.PoultryDrivers d
    LEFT   JOIN dbo.AspNetUsers u ON u.Id = d.EmployeeUserId
    WHERE  d.FarmId = @FarmId
    ORDER  BY d.DriverName;
END
GO

-- Make an employee a driver (idempotent upsert keyed on FarmId+EmployeeUserId).
CREATE OR ALTER PROCEDURE dbo.spPoultryDriver_UpsertForEmployee
    @FarmId NVARCHAR(450), @EmployeeUserId NVARCHAR(450),
    @DriverName NVARCHAR(150) = NULL, @PhoneNumber NVARCHAR(50) = NULL,
    @LicenseNumber NVARCHAR(60) = NULL, @BasePay DECIMAL(14,2) = NULL,
    @CommissionPerCrate DECIMAL(14,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Name NVARCHAR(150) = @DriverName;
    IF @Name IS NULL
        SELECT @Name = ISNULL(NULLIF(u.UserName, N''), u.Email)
        FROM dbo.AspNetUsers u WHERE u.Id = @EmployeeUserId;
    IF @Name IS NULL SET @Name = N'Driver';

    DECLARE @Id INT;
    SELECT @Id = PoultryDriverId FROM dbo.PoultryDrivers
    WHERE FarmId = @FarmId AND EmployeeUserId = @EmployeeUserId;

    IF @Id IS NULL
    BEGIN
        INSERT INTO dbo.PoultryDrivers
            (FarmId, DriverName, PhoneNumber, LicenseNumber, BasePay, CommissionPerCrate, IsActive, EmployeeUserId)
        VALUES
            (@FarmId, @Name, @PhoneNumber, @LicenseNumber, @BasePay, @CommissionPerCrate, 1, @EmployeeUserId);
        SET @Id = CAST(SCOPE_IDENTITY() AS INT);
    END
    ELSE
    BEGIN
        UPDATE dbo.PoultryDrivers
        SET DriverName = @Name, PhoneNumber = ISNULL(@PhoneNumber, PhoneNumber),
            LicenseNumber = ISNULL(@LicenseNumber, LicenseNumber),
            BasePay = ISNULL(@BasePay, BasePay), CommissionPerCrate = ISNULL(@CommissionPerCrate, CommissionPerCrate),
            IsActive = 1, UpdatedAt = SYSUTCDATETIME()
        WHERE PoultryDriverId = @Id;
    END

    -- Record the job role (reuse the farm-scoped EmployeeJobRoles table if present).
    IF OBJECT_ID('dbo.EmployeeJobRoles', 'U') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.EmployeeJobRoles
                       WHERE FarmId = @FarmId AND EmployeeUserId = @EmployeeUserId AND Role = 'Driver')
        INSERT INTO dbo.EmployeeJobRoles (EmployeeUserId, FarmId, Role)
        VALUES (@EmployeeUserId, @FarmId, 'Driver');

    SELECT * FROM dbo.PoultryDrivers WHERE PoultryDriverId = @Id;
END
GO

-- #############################################################################
-- MASTERS: Vehicles
-- #############################################################################

CREATE OR ALTER PROCEDURE dbo.spPoultryVehicle_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN SET NOCOUNT ON; SELECT * FROM dbo.PoultryVehicles WHERE FarmId = @FarmId ORDER BY VehicleName; END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryVehicle_GetById
    @PoultryVehicleId INT, @FarmId NVARCHAR(450)
AS
BEGIN SET NOCOUNT ON; SELECT * FROM dbo.PoultryVehicles WHERE PoultryVehicleId = @PoultryVehicleId AND FarmId = @FarmId; END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryVehicle_Insert
    @FarmId NVARCHAR(450), @VehicleName NVARCHAR(150), @VehicleType NVARCHAR(30) = NULL,
    @RegistrationNumber NVARCHAR(60) = NULL, @DefaultDriverId INT = NULL, @CapacityCrates INT = NULL,
    @FuelType NVARCHAR(30) = NULL, @Status NVARCHAR(30) = 'Active', @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.PoultryVehicles
        (FarmId, VehicleName, VehicleType, RegistrationNumber, DefaultDriverId, CapacityCrates, FuelType, Status, Notes)
    VALUES
        (@FarmId, @VehicleName, @VehicleType, @RegistrationNumber, @DefaultDriverId, @CapacityCrates, @FuelType, @Status, @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryVehicle_Update
    @PoultryVehicleId INT, @FarmId NVARCHAR(450), @VehicleName NVARCHAR(150), @VehicleType NVARCHAR(30) = NULL,
    @RegistrationNumber NVARCHAR(60) = NULL, @DefaultDriverId INT = NULL, @CapacityCrates INT = NULL,
    @FuelType NVARCHAR(30) = NULL, @Status NVARCHAR(30) = 'Active', @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryVehicles
    SET VehicleName = @VehicleName, VehicleType = @VehicleType, RegistrationNumber = @RegistrationNumber,
        DefaultDriverId = @DefaultDriverId, CapacityCrates = @CapacityCrates, FuelType = @FuelType,
        Status = @Status, Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryVehicleId = @PoultryVehicleId AND FarmId = @FarmId;
    SELECT @@ROWCOUNT;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryVehicle_Delete
    @PoultryVehicleId INT, @FarmId NVARCHAR(450)
AS
BEGIN SET NOCOUNT ON; DELETE FROM dbo.PoultryVehicles WHERE PoultryVehicleId = @PoultryVehicleId AND FarmId = @FarmId; SELECT @@ROWCOUNT; END
GO

-- #############################################################################
-- MASTERS: Routes
-- #############################################################################

CREATE OR ALTER PROCEDURE dbo.spPoultryRoute_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN SET NOCOUNT ON; SELECT * FROM dbo.PoultryRoutes WHERE FarmId = @FarmId ORDER BY RouteName; END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRoute_GetById
    @PoultryRouteId INT, @FarmId NVARCHAR(450)
AS
BEGIN SET NOCOUNT ON; SELECT * FROM dbo.PoultryRoutes WHERE PoultryRouteId = @PoultryRouteId AND FarmId = @FarmId; END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRoute_Insert
    @FarmId NVARCHAR(450), @RouteName NVARCHAR(150), @AreaCovered NVARCHAR(500) = NULL,
    @DefaultDriverId INT = NULL, @DefaultVehicleId INT = NULL, @ExpectedCustomers INT = NULL,
    @ExpectedCratesSold INT = NULL, @IsActive BIT = 1, @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.PoultryRoutes
        (FarmId, RouteName, AreaCovered, DefaultDriverId, DefaultVehicleId, ExpectedCustomers, ExpectedCratesSold, IsActive, Notes)
    VALUES
        (@FarmId, @RouteName, @AreaCovered, @DefaultDriverId, @DefaultVehicleId, @ExpectedCustomers, @ExpectedCratesSold, @IsActive, @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRoute_Update
    @PoultryRouteId INT, @FarmId NVARCHAR(450), @RouteName NVARCHAR(150), @AreaCovered NVARCHAR(500) = NULL,
    @DefaultDriverId INT = NULL, @DefaultVehicleId INT = NULL, @ExpectedCustomers INT = NULL,
    @ExpectedCratesSold INT = NULL, @IsActive BIT = 1, @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryRoutes
    SET RouteName = @RouteName, AreaCovered = @AreaCovered, DefaultDriverId = @DefaultDriverId,
        DefaultVehicleId = @DefaultVehicleId, ExpectedCustomers = @ExpectedCustomers,
        ExpectedCratesSold = @ExpectedCratesSold, IsActive = @IsActive, Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryRouteId = @PoultryRouteId AND FarmId = @FarmId;
    SELECT @@ROWCOUNT;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRoute_Delete
    @PoultryRouteId INT, @FarmId NVARCHAR(450)
AS
BEGIN SET NOCOUNT ON; DELETE FROM dbo.PoultryRoutes WHERE PoultryRouteId = @PoultryRouteId AND FarmId = @FarmId; SELECT @@ROWCOUNT; END
GO

-- #############################################################################
-- VEHICLE LOADINGS
-- #############################################################################

CREATE OR ALTER PROCEDURE dbo.spPoultryVehicleLoading_GetAll
    @FarmId NVARCHAR(450), @Status NVARCHAR(20) = NULL, @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT l.*,
           v.VehicleName, v.RegistrationNumber,
           d.DriverName,
           r.RouteName,
           p.Name AS ProductName
    FROM   dbo.PoultryVehicleLoadings l
    LEFT   JOIN dbo.PoultryVehicles v ON v.PoultryVehicleId = l.PoultryVehicleId
    LEFT   JOIN dbo.PoultryDrivers  d ON d.PoultryDriverId  = l.PoultryDriverId
    LEFT   JOIN dbo.PoultryRoutes   r ON r.PoultryRouteId   = l.PoultryRouteId
    LEFT   JOIN dbo.PoultryProducts p ON p.PoultryProductId = l.PoultryProductId
    WHERE  l.FarmId = @FarmId AND l.IsDeleted = 0
       AND (@Status  IS NULL OR l.Status = @Status)
       AND (@FromDate IS NULL OR CAST(l.LoadDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(l.LoadDate AS DATE) <= @ToDate)
    ORDER  BY l.LoadDate DESC, l.PoultryVehicleLoadingId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryVehicleLoading_GetById
    @PoultryVehicleLoadingId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT l.*, v.VehicleName, d.DriverName, r.RouteName, p.Name AS ProductName
    FROM   dbo.PoultryVehicleLoadings l
    LEFT   JOIN dbo.PoultryVehicles v ON v.PoultryVehicleId = l.PoultryVehicleId
    LEFT   JOIN dbo.PoultryDrivers  d ON d.PoultryDriverId  = l.PoultryDriverId
    LEFT   JOIN dbo.PoultryRoutes   r ON r.PoultryRouteId   = l.PoultryRouteId
    LEFT   JOIN dbo.PoultryProducts p ON p.PoultryProductId = l.PoultryProductId
    WHERE  l.PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND l.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryVehicleLoading_GetItems
    @PoultryVehicleLoadingId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  li.PoultryVehicleLoadingItemId, li.PoultryVehicleLoadingId, li.PoultryProductId,
            p.Name AS ProductName, p.Unit AS ProductUnit,
            li.CratesLoaded, li.EggsPerCrate, li.UnitPrice, li.ExpectedAmount, li.Notes,
            li.CreatedAt, li.UpdatedAt
    FROM    dbo.PoultryVehicleLoadingItems li
    INNER  JOIN dbo.PoultryVehicleLoadings l ON l.PoultryVehicleLoadingId = li.PoultryVehicleLoadingId
    INNER  JOIN dbo.PoultryProducts        p ON p.PoultryProductId        = li.PoultryProductId
    WHERE   li.PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND l.FarmId = @FarmId
    ORDER BY li.PoultryVehicleLoadingItemId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryVehicleLoading_Insert
    @FarmId NVARCHAR(450), @LoadDate DATETIME2 = NULL,
    @PoultryVehicleId INT, @PoultryDriverId INT = NULL,
    @AssistantStaffId INT = NULL, @PoultryRouteId INT = NULL,
    @PoultryProductId INT = NULL, @CratesLoaded INT = NULL, @EggsPerCrate INT = 30,
    @ExpectedSellingPricePerCrate DECIMAL(14,2) = NULL, @OpeningCashWithDriver DECIMAL(14,2) = 0,
    @LoadedByStaffId INT = NULL, @Notes NVARCHAR(500) = NULL, @CreatedBy NVARCHAR(450) = NULL,
    -- JSON: [{ "poultryProductId":1, "cratesLoaded":300, "unitPrice":30, "eggsPerCrate":30, "notes":null }]
    @ItemsJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @HasItems BIT = CASE WHEN @ItemsJson IS NOT NULL AND LEN(@ItemsJson) > 2 THEN 1 ELSE 0 END;

    IF @HasItems = 0
    BEGIN
        IF @PoultryProductId IS NULL OR @CratesLoaded IS NULL OR @ExpectedSellingPricePerCrate IS NULL
        BEGIN RAISERROR('Either provide @ItemsJson or all of @PoultryProductId / @CratesLoaded / @ExpectedSellingPricePerCrate.', 16, 1); RETURN; END
        IF (@CratesLoaded <= 0) BEGIN RAISERROR('CratesLoaded must be greater than zero.', 16, 1); RETURN; END
    END

    BEGIN TRANSACTION;

    DECLARE @HeaderProductId INT      = @PoultryProductId,
            @HeaderCrates INT         = @CratesLoaded,
            @HeaderPrice DECIMAL(14,2) = @ExpectedSellingPricePerCrate,
            @HeaderEggsPerCrate INT   = @EggsPerCrate;

    IF @HasItems = 1
    BEGIN
        SELECT TOP 1
            @HeaderProductId    = PoultryProductId,
            @HeaderPrice        = UnitPrice,
            @HeaderEggsPerCrate = ISNULL(EggsPerCrate, 30)
        FROM OPENJSON(@ItemsJson)
        WITH ( PoultryProductId INT '$.poultryProductId', UnitPrice DECIMAL(14,2) '$.unitPrice', EggsPerCrate INT '$.eggsPerCrate' );

        SELECT @HeaderCrates = ISNULL(SUM(CratesLoaded), 0)
        FROM OPENJSON(@ItemsJson) WITH ( CratesLoaded INT '$.cratesLoaded' );
    END

    INSERT INTO dbo.PoultryVehicleLoadings (
        FarmId, LoadDate, PoultryVehicleId, PoultryDriverId, AssistantStaffId, PoultryRouteId,
        PoultryProductId, CratesLoaded, EggsPerCrate, ExpectedSellingPricePerCrate,
        OpeningCashWithDriver, LoadedByStaffId, Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, ISNULL(@LoadDate, SYSUTCDATETIME()), @PoultryVehicleId, @PoultryDriverId,
        @AssistantStaffId, @PoultryRouteId, @HeaderProductId, @HeaderCrates,
        @HeaderEggsPerCrate, @HeaderPrice, @OpeningCashWithDriver, @LoadedByStaffId,
        'Draft', @Notes, @CreatedBy
    );
    DECLARE @LoadingId INT = CAST(SCOPE_IDENTITY() AS INT);

    IF @HasItems = 1
    BEGIN
        INSERT INTO dbo.PoultryVehicleLoadingItems
            (PoultryVehicleLoadingId, PoultryProductId, CratesLoaded, EggsPerCrate, UnitPrice, Notes)
        SELECT @LoadingId, j.PoultryProductId, ISNULL(j.CratesLoaded, 0),
               ISNULL(j.EggsPerCrate, 30), ISNULL(j.UnitPrice, 0), j.Notes
        FROM OPENJSON(@ItemsJson)
        WITH (
            PoultryProductId INT '$.poultryProductId', CratesLoaded INT '$.cratesLoaded',
            EggsPerCrate INT '$.eggsPerCrate', UnitPrice DECIMAL(14,2) '$.unitPrice', Notes NVARCHAR(300) '$.notes'
        ) j
        WHERE j.PoultryProductId IS NOT NULL AND ISNULL(j.CratesLoaded, 0) > 0;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.PoultryVehicleLoadingItems
            (PoultryVehicleLoadingId, PoultryProductId, CratesLoaded, EggsPerCrate, UnitPrice)
        VALUES (@LoadingId, @PoultryProductId, @CratesLoaded, @EggsPerCrate, @ExpectedSellingPricePerCrate);
    END

    COMMIT TRANSACTION;
    SELECT @LoadingId;
END
GO

-- Approve loading: Draft -> Loaded; write one 'Driver Load Out' stock txn per item.
CREATE OR ALTER PROCEDURE dbo.spPoultryVehicleLoading_Approve
    @PoultryVehicleLoadingId INT, @FarmId NVARCHAR(450), @ApprovedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.PoultryVehicleLoadings
               WHERE PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND FarmId = @FarmId
                 AND Status IN ('Loaded', 'Reconciled'))
    BEGIN
        SELECT PoultryVehicleLoadingId, Status, ApprovedBy, ApprovedAt
        FROM dbo.PoultryVehicleLoadings
        WHERE PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @Status NVARCHAR(20), @VehicleId INT;
    SELECT @Status = Status, @VehicleId = PoultryVehicleId
    FROM   dbo.PoultryVehicleLoadings
    WHERE  PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL BEGIN RAISERROR('Loading %d not found.', 16, 1, @PoultryVehicleLoadingId); RETURN; END
    IF @Status <> 'Draft' BEGIN RAISERROR('Loading cannot be approved from status %s.', 16, 1, @Status); RETURN; END

    -- Per-item stock pre-flight.
    DECLARE @ShortName NVARCHAR(150), @ShortHave DECIMAL(14,3), @ShortNeed INT;
    SELECT TOP 1
           @ShortName = p.Name, @ShortHave = ISNULL(s.OnHand, 0), @ShortNeed = li.CratesLoaded
    FROM   dbo.PoultryVehicleLoadingItems li
    JOIN   dbo.PoultryProducts p ON p.PoultryProductId = li.PoultryProductId
    OUTER APPLY (
        SELECT SUM(Quantity) AS OnHand FROM dbo.PoultryStockTransactions
        WHERE FarmId = @FarmId AND PoultryProductId = li.PoultryProductId
    ) s
    WHERE  li.PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND ISNULL(s.OnHand, 0) < li.CratesLoaded;

    IF @ShortName IS NOT NULL
    BEGIN
        DECLARE @msg NVARCHAR(400) = CONCAT('Insufficient stock for ', @ShortName, ': on hand=',
            CAST(@ShortHave AS NVARCHAR(20)), ', trying to load ', CAST(@ShortNeed AS NVARCHAR(20)), '.');
        RAISERROR(N'%s', 16, 1, @msg);
        RETURN;
    END

    BEGIN TRANSACTION;

    UPDATE dbo.PoultryVehicleLoadings
    SET Status = 'Loaded', ApprovedBy = @ApprovedBy, ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND FarmId = @FarmId;

    INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, UnitCost, RelatedId, Note, CreatedBy)
    SELECT @FarmId, li.PoultryProductId, 'Driver Load Out', -li.CratesLoaded, li.UnitPrice, @PoultryVehicleLoadingId,
           CONCAT('Vehicle loading #', @PoultryVehicleLoadingId), @ApprovedBy
    FROM   dbo.PoultryVehicleLoadingItems li
    WHERE  li.PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND li.CratesLoaded > 0;

    COMMIT TRANSACTION;

    SELECT PoultryVehicleLoadingId, Status, ApprovedBy, ApprovedAt
    FROM dbo.PoultryVehicleLoadings WHERE PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND FarmId = @FarmId;
END
GO

-- Cancel / Void a Draft or Loaded loading (no return yet): restore stock, mark Cancelled.
CREATE OR ALTER PROCEDURE dbo.spPoultryVehicleLoading_Cancel
    @PoultryVehicleLoadingId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.PoultryVehicleLoadings
    WHERE PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND FarmId = @FarmId AND IsDeleted = 0;
    IF @Status IS NULL BEGIN RAISERROR('Loading not found.', 16, 1); RETURN; END
    IF @Status = 'Reconciled' BEGIN RAISERROR('Reconciled loading cannot be cancelled; reverse the driver return first.', 16, 1); RETURN; END

    BEGIN TRANSACTION;
    -- Undo the LoadOut stock if it was approved.
    DELETE FROM dbo.PoultryStockTransactions
    WHERE FarmId = @FarmId AND TxnType = 'Driver Load Out' AND RelatedId = @PoultryVehicleLoadingId;

    UPDATE dbo.PoultryVehicleLoadings SET Status = 'Cancelled', UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
    SELECT @PoultryVehicleLoadingId, 'Cancelled';
END
GO

-- Void = soft-delete a loading (also restores stock). Only when no active return.
CREATE OR ALTER PROCEDURE dbo.spPoultryVehicleLoading_Void
    @PoultryVehicleLoadingId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF EXISTS (SELECT 1 FROM dbo.PoultryDriverReturns
               WHERE PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND FarmId = @FarmId AND Status <> 'Cancelled')
    BEGIN RAISERROR('Cannot void: an active driver return exists. Cancel/reverse it first.', 16, 1); RETURN; END

    BEGIN TRANSACTION;
    DELETE FROM dbo.PoultryStockTransactions
    WHERE FarmId = @FarmId AND TxnType = 'Driver Load Out' AND RelatedId = @PoultryVehicleLoadingId;
    UPDATE dbo.PoultryVehicleLoadings SET IsDeleted = 1, Status = 'Cancelled', UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
    SELECT @PoultryVehicleLoadingId, 'Voided';
END
GO

-- Reload: clone a Cancelled/Loaded loading back to a fresh Draft (re-open for edit).
CREATE OR ALTER PROCEDURE dbo.spPoultryVehicleLoading_Reload
    @PoultryVehicleLoadingId INT, @FarmId NVARCHAR(450), @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.PoultryVehicleLoadings
    WHERE PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND FarmId = @FarmId;
    IF @Status IS NULL BEGIN RAISERROR('Loading not found.', 16, 1); RETURN; END

    BEGIN TRANSACTION;
    INSERT INTO dbo.PoultryVehicleLoadings (
        FarmId, LoadDate, PoultryVehicleId, PoultryDriverId, AssistantStaffId, PoultryRouteId,
        PoultryProductId, CratesLoaded, EggsPerCrate, ExpectedSellingPricePerCrate,
        OpeningCashWithDriver, LoadedByStaffId, Status, Notes, CreatedBy)
    SELECT FarmId, SYSUTCDATETIME(), PoultryVehicleId, PoultryDriverId, AssistantStaffId, PoultryRouteId,
           PoultryProductId, CratesLoaded, EggsPerCrate, ExpectedSellingPricePerCrate,
           OpeningCashWithDriver, LoadedByStaffId, 'Draft', Notes, @CreatedBy
    FROM   dbo.PoultryVehicleLoadings WHERE PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND FarmId = @FarmId;
    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    INSERT INTO dbo.PoultryVehicleLoadingItems (PoultryVehicleLoadingId, PoultryProductId, CratesLoaded, EggsPerCrate, UnitPrice, Notes)
    SELECT @NewId, PoultryProductId, CratesLoaded, EggsPerCrate, UnitPrice, Notes
    FROM   dbo.PoultryVehicleLoadingItems WHERE PoultryVehicleLoadingId = @PoultryVehicleLoadingId;
    COMMIT TRANSACTION;
    SELECT @NewId;
END
GO

-- #############################################################################
-- DRIVER RETURNS
-- #############################################################################

CREATE OR ALTER PROCEDURE dbo.spPoultryDriverReturn_GetAll
    @FarmId NVARCHAR(450), @Status NVARCHAR(20) = NULL, @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.*,
           l.PoultryVehicleId, l.PoultryDriverId, l.PoultryRouteId, l.CratesLoaded AS LoadingCratesLoaded,
           l.ExpectedCash AS LoadingExpectedCash,
           v.VehicleName, d.DriverName, rt.RouteName
    FROM   dbo.PoultryDriverReturns r
    INNER  JOIN dbo.PoultryVehicleLoadings l ON l.PoultryVehicleLoadingId = r.PoultryVehicleLoadingId
    LEFT   JOIN dbo.PoultryVehicles v ON v.PoultryVehicleId = l.PoultryVehicleId
    LEFT   JOIN dbo.PoultryDrivers  d ON d.PoultryDriverId  = l.PoultryDriverId
    LEFT   JOIN dbo.PoultryRoutes   rt ON rt.PoultryRouteId = l.PoultryRouteId
    WHERE  r.FarmId = @FarmId
       AND (@Status  IS NULL OR r.Status = @Status)
       AND (@FromDate IS NULL OR CAST(r.ReturnDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(r.ReturnDate AS DATE) <= @ToDate)
    ORDER  BY r.ReturnDate DESC, r.PoultryDriverReturnId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDriverReturn_GetById
    @PoultryDriverReturnId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.*, l.PoultryVehicleId, l.PoultryDriverId, l.PoultryRouteId, l.CratesLoaded AS LoadingCratesLoaded,
           l.ExpectedCash AS LoadingExpectedCash, v.VehicleName, d.DriverName, rt.RouteName
    FROM   dbo.PoultryDriverReturns r
    INNER  JOIN dbo.PoultryVehicleLoadings l ON l.PoultryVehicleLoadingId = r.PoultryVehicleLoadingId
    LEFT   JOIN dbo.PoultryVehicles v ON v.PoultryVehicleId = l.PoultryVehicleId
    LEFT   JOIN dbo.PoultryDrivers  d ON d.PoultryDriverId  = l.PoultryDriverId
    LEFT   JOIN dbo.PoultryRoutes   rt ON rt.PoultryRouteId = l.PoultryRouteId
    WHERE  r.PoultryDriverReturnId = @PoultryDriverReturnId AND r.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDriverReturn_GetItems
    @PoultryDriverReturnId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  ri.PoultryDriverReturnItemId, ri.PoultryDriverReturnId, ri.PoultryProductId,
            p.Name AS ProductName, ri.CratesLoaded, ri.CratesSold, ri.CratesReturned, ri.CratesDamaged,
            ri.UnitPrice, ri.ExpectedSales, ri.Notes, ri.CreatedAt, ri.UpdatedAt
    FROM    dbo.PoultryDriverReturnItems ri
    INNER  JOIN dbo.PoultryDriverReturns r ON r.PoultryDriverReturnId = ri.PoultryDriverReturnId
    INNER  JOIN dbo.PoultryProducts      p ON p.PoultryProductId      = ri.PoultryProductId
    WHERE   ri.PoultryDriverReturnId = @PoultryDriverReturnId AND r.FarmId = @FarmId
    ORDER BY ri.PoultryDriverReturnItemId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDriverReturn_GetCustomerSales
    @PoultryDriverReturnId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  cs.PoultryDriverReturnCustomerSaleId, cs.PoultryDriverReturnId, cs.CustomerId,
            cs.CustomerLabel, cs.TotalAmount, cs.CashPaid, cs.MoMoPaid, cs.BankPaid, cs.CreditAmount,
            cs.GeneratedSaleId, cs.Notes, cs.CreatedAt, cs.UpdatedAt
    FROM    dbo.PoultryDriverReturnCustomerSales cs
    INNER  JOIN dbo.PoultryDriverReturns r ON r.PoultryDriverReturnId = cs.PoultryDriverReturnId
    WHERE   cs.PoultryDriverReturnId = @PoultryDriverReturnId AND r.FarmId = @FarmId
    ORDER BY cs.PoultryDriverReturnCustomerSaleId;

    SELECT  csi.PoultryDriverReturnCustomerSaleItemId, csi.PoultryDriverReturnCustomerSaleId,
            csi.PoultryProductId, p.Name AS ProductName, csi.Quantity, csi.UnitPrice, csi.LineTotal
    FROM    dbo.PoultryDriverReturnCustomerSaleItems csi
    INNER  JOIN dbo.PoultryDriverReturnCustomerSales cs ON cs.PoultryDriverReturnCustomerSaleId = csi.PoultryDriverReturnCustomerSaleId
    INNER  JOIN dbo.PoultryDriverReturns             r  ON r.PoultryDriverReturnId              = cs.PoultryDriverReturnId
    INNER  JOIN dbo.PoultryProducts                  p  ON p.PoultryProductId                   = csi.PoultryProductId
    WHERE   cs.PoultryDriverReturnId = @PoultryDriverReturnId AND r.FarmId = @FarmId
    ORDER BY csi.PoultryDriverReturnCustomerSaleItemId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDriverReturn_Insert
    @FarmId NVARCHAR(450), @PoultryVehicleLoadingId INT, @ReturnDate DATETIME2 = NULL,
    @CratesSold INT, @CratesReturned INT, @CratesDamaged INT = 0, @MissingCrates INT = 0,
    @CashCollected DECIMAL(14,2) = 0, @MoMoCollected DECIMAL(14,2) = 0, @BankCollected DECIMAL(14,2) = 0,
    @CreditSalesAmount DECIMAL(14,2) = 0, @CashReturnedByDriver DECIMAL(14,2) = 0,
    @ApprovedDeliveryExpenses DECIMAL(14,2) = 0, @SalesPostingMode NVARCHAR(20) = 'Detailed',
    @PrimaryCustomerId INT = NULL, @ReconciledByStaffId INT = NULL,
    @Notes NVARCHAR(1000) = NULL, @CreatedBy NVARCHAR(450) = NULL,
    @ItemsJson NVARCHAR(MAX) = NULL, @CustomerSalesJson NVARCHAR(MAX) = NULL, @ExpensesJson NVARCHAR(MAX) = NULL,
    @NewReturnId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CratesLoaded INT;
    SELECT @CratesLoaded = CratesLoaded FROM dbo.PoultryVehicleLoadings
    WHERE  PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND FarmId = @FarmId;
    IF @CratesLoaded IS NULL BEGIN RAISERROR('Loading %d not found.', 16, 1, @PoultryVehicleLoadingId); RETURN; END

    IF (@CratesSold + @CratesReturned + @CratesDamaged + @MissingCrates) <> @CratesLoaded
    BEGIN
        RAISERROR('Crate accounting does not balance: %d sold + %d returned + %d damaged + %d missing != %d loaded.',
                  16, 1, @CratesSold, @CratesReturned, @CratesDamaged, @MissingCrates, @CratesLoaded);
        RETURN;
    END

    -- Guard: only one open (non-cancelled) return per loading.
    IF EXISTS (SELECT 1 FROM dbo.PoultryDriverReturns
               WHERE PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND FarmId = @FarmId AND Status <> 'Cancelled')
    BEGIN RAISERROR('An open driver return already exists for this loading.', 16, 1); RETURN; END

    BEGIN TRANSACTION;

    INSERT INTO dbo.PoultryDriverReturns (
        FarmId, PoultryVehicleLoadingId, ReturnDate, CratesSold, CratesReturned, CratesDamaged,
        MissingCrates, CashCollected, MoMoCollected, BankCollected, CreditSalesAmount,
        CashReturnedByDriver, ApprovedDeliveryExpenses, SalesPostingMode, PrimaryCustomerId,
        ReconciledByStaffId, Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @PoultryVehicleLoadingId, ISNULL(@ReturnDate, SYSUTCDATETIME()),
        @CratesSold, @CratesReturned, @CratesDamaged, @MissingCrates,
        @CashCollected, @MoMoCollected, @BankCollected, @CreditSalesAmount,
        @CashReturnedByDriver, @ApprovedDeliveryExpenses, ISNULL(@SalesPostingMode, 'Detailed'), @PrimaryCustomerId,
        @ReconciledByStaffId, 'Draft', @Notes, @CreatedBy
    );
    DECLARE @ReturnId INT = CAST(SCOPE_IDENTITY() AS INT);
    SET @NewReturnId = @ReturnId;

    -- Per-product reconciliation rows.
    IF @ItemsJson IS NOT NULL AND LEN(@ItemsJson) > 2
    BEGIN
        INSERT INTO dbo.PoultryDriverReturnItems
            (PoultryDriverReturnId, PoultryProductId, CratesLoaded, CratesSold, CratesReturned, CratesDamaged, UnitPrice, Notes)
        SELECT  @ReturnId, src.PoultryProductId, ISNULL(li.CratesLoaded, 0),
                ISNULL(src.CratesSold, 0), ISNULL(src.CratesReturned, 0), ISNULL(src.CratesDamaged, 0),
                ISNULL(src.UnitPrice, li.UnitPrice), src.Notes
        FROM (
            SELECT j.PoultryProductId, j.CratesSold, j.CratesReturned, j.CratesDamaged, j.UnitPrice, j.Notes
            FROM OPENJSON(@ItemsJson)
            WITH ( PoultryProductId INT '$.poultryProductId', CratesSold INT '$.cratesSold',
                   CratesReturned INT '$.cratesReturned', CratesDamaged INT '$.cratesDamaged',
                   UnitPrice DECIMAL(14,2) '$.unitPrice', Notes NVARCHAR(300) '$.notes' ) j
        ) src
        LEFT JOIN dbo.PoultryVehicleLoadingItems li
               ON li.PoultryVehicleLoadingId = @PoultryVehicleLoadingId AND li.PoultryProductId = src.PoultryProductId
        WHERE src.PoultryProductId IS NOT NULL;
    END

    -- Customer breakdown rows + items.
    IF @CustomerSalesJson IS NOT NULL AND LEN(@CustomerSalesJson) > 2
    BEGIN
        DECLARE @cs TABLE (
            Idx INT IDENTITY(1,1) PRIMARY KEY, CustomerId INT NULL, CustomerLabel NVARCHAR(150),
            CashPaid DECIMAL(14,2), MoMoPaid DECIMAL(14,2), BankPaid DECIMAL(14,2),
            CreditAmount DECIMAL(14,2), Notes NVARCHAR(500), ItemsJson NVARCHAR(MAX) );

        INSERT INTO @cs (CustomerId, CustomerLabel, CashPaid, MoMoPaid, BankPaid, CreditAmount, Notes, ItemsJson)
        SELECT j.CustomerId, j.CustomerLabel, ISNULL(j.CashPaid,0), ISNULL(j.MoMoPaid,0),
               ISNULL(j.BankPaid,0), ISNULL(j.CreditAmount,0), j.Notes, j.ItemsJson
        FROM OPENJSON(@CustomerSalesJson)
        WITH ( CustomerId INT '$.customerId', CustomerLabel NVARCHAR(150) '$.customerLabel',
               CashPaid DECIMAL(14,2) '$.cashPaid', MoMoPaid DECIMAL(14,2) '$.moMoPaid',
               BankPaid DECIMAL(14,2) '$.bankPaid', CreditAmount DECIMAL(14,2) '$.creditAmount',
               Notes NVARCHAR(500) '$.notes', ItemsJson NVARCHAR(MAX) '$.items' AS JSON ) j;

        DECLARE @rowIdx INT = 1, @rowMax INT = (SELECT MAX(Idx) FROM @cs);
        DECLARE @rowCust INT, @rowLabel NVARCHAR(150), @rowCash DECIMAL(14,2), @rowMomo DECIMAL(14,2),
                @rowBank DECIMAL(14,2), @rowCredit DECIMAL(14,2), @rowNotes NVARCHAR(500),
                @rowItemsJson NVARCHAR(MAX), @rowTotalAmt DECIMAL(14,2), @newCsId INT;

        WHILE @rowIdx <= @rowMax
        BEGIN
            SELECT @rowCust = CustomerId, @rowLabel = CustomerLabel, @rowCash = CashPaid, @rowMomo = MoMoPaid,
                   @rowBank = BankPaid, @rowCredit = CreditAmount, @rowNotes = Notes, @rowItemsJson = ItemsJson
            FROM @cs WHERE Idx = @rowIdx;

            SET @rowTotalAmt = 0;
            IF @rowItemsJson IS NOT NULL AND LEN(@rowItemsJson) > 2
                SELECT @rowTotalAmt = ISNULL(SUM(CAST(ji.Quantity AS DECIMAL(14,2)) * ji.UnitPrice), 0)
                FROM OPENJSON(@rowItemsJson)
                WITH ( PoultryProductId INT '$.poultryProductId', Quantity INT '$.quantity', UnitPrice DECIMAL(14,2) '$.unitPrice' ) ji;
            IF @rowTotalAmt = 0 SET @rowTotalAmt = @rowCash + @rowMomo + @rowBank + @rowCredit;

            INSERT INTO dbo.PoultryDriverReturnCustomerSales
                (PoultryDriverReturnId, CustomerId, CustomerLabel, TotalAmount, CashPaid, MoMoPaid, BankPaid, CreditAmount, Notes)
            VALUES (@ReturnId, @rowCust, @rowLabel, @rowTotalAmt, @rowCash, @rowMomo, @rowBank, @rowCredit, @rowNotes);
            SET @newCsId = CAST(SCOPE_IDENTITY() AS INT);

            IF @rowItemsJson IS NOT NULL AND LEN(@rowItemsJson) > 2
                INSERT INTO dbo.PoultryDriverReturnCustomerSaleItems
                    (PoultryDriverReturnCustomerSaleId, PoultryProductId, Quantity, UnitPrice)
                SELECT @newCsId, ji.PoultryProductId, ji.Quantity, ji.UnitPrice
                FROM OPENJSON(@rowItemsJson)
                WITH ( PoultryProductId INT '$.poultryProductId', Quantity INT '$.quantity', UnitPrice DECIMAL(14,2) '$.unitPrice' ) ji
                WHERE ji.PoultryProductId IS NOT NULL AND ji.Quantity > 0;

            SET @rowIdx = @rowIdx + 1;
        END
    END

    -- Delivery expenses (staged; posted to dbo.Expense on approve).
    IF @ExpensesJson IS NOT NULL AND LEN(@ExpensesJson) > 2
        INSERT INTO dbo.PoultryDriverDeliveryExpenses
            (FarmId, PoultryDriverReturnId, PoultryVehicleLoadingId, ExpenseCategory, Amount, Description, IsApproved, Notes, CreatedBy)
        SELECT @FarmId, @ReturnId, @PoultryVehicleLoadingId, ISNULL(NULLIF(j.ExpenseCategory, N''), N'Other'),
               ISNULL(j.Amount, 0), j.Description, ISNULL(j.IsApproved, 1), j.Notes, @CreatedBy
        FROM OPENJSON(@ExpensesJson)
        WITH ( ExpenseCategory NVARCHAR(40) '$.expenseCategory', Amount DECIMAL(14,2) '$.amount',
               Description NVARCHAR(500) '$.description', IsApproved BIT '$.isApproved', Notes NVARCHAR(500) '$.notes' ) j;

    COMMIT TRANSACTION;
    SELECT @ReturnId;
END
GO

-- Approve a Draft return: reconcile crates + post into the poultry ledgers.
CREATE OR ALTER PROCEDURE dbo.spPoultryDriverReturn_Approve
    @PoultryDriverReturnId INT, @FarmId NVARCHAR(450), @ApprovedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.PoultryDriverReturns
               WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT PoultryDriverReturnId, Status, ApprovedBy, ApprovedAt
        FROM dbo.PoultryDriverReturns WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @Status NVARCHAR(20), @LoadingId INT, @CratesSold INT, @CratesReturned INT, @CratesDamaged INT,
            @MissingCrates INT, @CashCollected DECIMAL(14,2), @MoMoCollected DECIMAL(14,2),
            @BankCollected DECIMAL(14,2), @CreditSalesAmount DECIMAL(14,2), @PostingMode NVARCHAR(20),
            @ReturnDate DATETIME2;
    SELECT @Status = Status, @LoadingId = PoultryVehicleLoadingId, @CratesSold = CratesSold,
           @CratesReturned = CratesReturned, @CratesDamaged = CratesDamaged, @MissingCrates = MissingCrates,
           @CashCollected = CashCollected, @MoMoCollected = MoMoCollected, @BankCollected = BankCollected,
           @CreditSalesAmount = CreditSalesAmount, @PostingMode = SalesPostingMode, @ReturnDate = ReturnDate
    FROM dbo.PoultryDriverReturns WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId;

    IF @Status IS NULL BEGIN RAISERROR('Driver return %d not found.', 16, 1, @PoultryDriverReturnId); RETURN; END
    IF @Status <> 'Draft' BEGIN RAISERROR('Driver return cannot be approved from status %s.', 16, 1, @Status); RETURN; END

    DECLARE @ProductId INT, @PricePerCrate DECIMAL(14,2), @DriverId INT;
    SELECT @ProductId = PoultryProductId, @PricePerCrate = ExpectedSellingPricePerCrate, @DriverId = PoultryDriverId
    FROM dbo.PoultryVehicleLoadings WHERE PoultryVehicleLoadingId = @LoadingId AND FarmId = @FarmId;

    -- Expected cash: per-item sum when present, else CratesSold * headerPrice.
    DECLARE @ExpectedCash DECIMAL(14,2);
    SELECT @ExpectedCash = ISNULL(SUM(ri.ExpectedSales), 0) FROM dbo.PoultryDriverReturnItems ri
    WHERE ri.PoultryDriverReturnId = @PoultryDriverReturnId;
    IF @ExpectedCash = 0 SET @ExpectedCash = CAST(@CratesSold AS DECIMAL(14,2)) * @PricePerCrate;

    DECLARE @TotalAccounted DECIMAL(14,2) = @CashCollected + @MoMoCollected + @BankCollected + @CreditSalesAmount;
    DECLARE @Shortage DECIMAL(14,2) = CASE WHEN @ExpectedCash > @TotalAccounted THEN @ExpectedCash - @TotalAccounted ELSE 0 END;
    DECLARE @Overage  DECIMAL(14,2) = CASE WHEN @TotalAccounted > @ExpectedCash THEN @TotalAccounted - @ExpectedCash ELSE 0 END;

    DECLARE @user NVARCHAR(450) = ISNULL(@ApprovedBy, N'system');
    DECLARE @gid UNIQUEIDENTIFIER = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER);
    DECLARE @DateD DATE = CAST(ISNULL(@ReturnDate, SYSUTCDATETIME()) AS DATE);

    BEGIN TRANSACTION;

    UPDATE dbo.PoultryDriverReturns
    SET Status = 'Approved', ApprovedBy = @ApprovedBy, ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME(),
        ShortageAmount = @Shortage, OverageAmount = @Overage
    WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId;

    UPDATE dbo.PoultryVehicleLoadings SET Status = 'Reconciled', UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryVehicleLoadingId = @LoadingId AND FarmId = @FarmId;

    -- (a) Returned crates back into stock ('Driver Return In').
    IF EXISTS (SELECT 1 FROM dbo.PoultryDriverReturnItems WHERE PoultryDriverReturnId = @PoultryDriverReturnId)
        INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, UnitCost, RelatedId, Note, CreatedBy)
        SELECT @FarmId, ri.PoultryProductId, 'Driver Return In', ri.CratesReturned, ri.UnitPrice, @PoultryDriverReturnId,
               CONCAT('Driver return #', @PoultryDriverReturnId, ' for loading #', @LoadingId), @user
        FROM dbo.PoultryDriverReturnItems ri
        WHERE ri.PoultryDriverReturnId = @PoultryDriverReturnId AND ri.CratesReturned > 0;
    ELSE IF (@CratesReturned > 0)
        INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, UnitCost, RelatedId, Note, CreatedBy)
        VALUES (@FarmId, @ProductId, 'Driver Return In', @CratesReturned, @PricePerCrate, @PoultryDriverReturnId,
                CONCAT('Driver return #', @PoultryDriverReturnId, ' for loading #', @LoadingId), @user);

    -- (b) Damaged + missing crates -> production loss (eggs already out at load).
    DECLARE @LostCrates INT = ISNULL(@CratesDamaged, 0) + ISNULL(@MissingCrates, 0);
    IF (@LostCrates > 0)
        INSERT INTO dbo.PoultryProductionLoss (FarmId, SourceType, SourceId, LossDate, PoultryProductId, QuantityLost, EstimatedValue, Reason)
        VALUES (@FarmId, 'PoultryDriverReturn', @PoultryDriverReturnId, ISNULL(@ReturnDate, SYSUTCDATETIME()), @ProductId,
                @LostCrates, CAST(@LostCrates * @PricePerCrate AS DECIMAL(14,2)), N'Driver return damaged/missing crates');

    -- (c) Sales. If no customer breakdown rows, synthesize a single aggregate row
    --     so every generated Sale is trackable via GeneratedSaleId.
    IF NOT EXISTS (SELECT 1 FROM dbo.PoultryDriverReturnCustomerSales WHERE PoultryDriverReturnId = @PoultryDriverReturnId)
       AND (@CratesSold > 0 OR @ExpectedCash > 0)
    BEGIN
        INSERT INTO dbo.PoultryDriverReturnCustomerSales
            (PoultryDriverReturnId, CustomerId, CustomerLabel, TotalAmount, CashPaid, MoMoPaid, BankPaid, CreditAmount, Notes)
        VALUES (@PoultryDriverReturnId, NULL, N'Delivery Sale', @ExpectedCash,
                @CashCollected, @MoMoCollected, @BankCollected, @CreditSalesAmount, N'Auto summary');
    END

    -- Materialize one dbo.Sale per customer-breakdown row (poultry Sale is single-line).
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT cs.PoultryDriverReturnCustomerSaleId, cs.CustomerLabel, cs.TotalAmount,
               cs.CashPaid, cs.MoMoPaid, cs.BankPaid, cs.CreditAmount
        FROM dbo.PoultryDriverReturnCustomerSales cs
        WHERE cs.PoultryDriverReturnId = @PoultryDriverReturnId;
    DECLARE @csId INT, @csLabel NVARCHAR(150), @tot DECIMAL(14,2),
            @cash DECIMAL(14,2), @momo DECIMAL(14,2), @bank DECIMAL(14,2), @credit DECIMAL(14,2);

    OPEN cur;
    FETCH NEXT FROM cur INTO @csId, @csLabel, @tot, @cash, @momo, @bank, @credit;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @qty DECIMAL(14,3) = ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryDriverReturnCustomerSaleItems
                                             WHERE PoultryDriverReturnCustomerSaleId = @csId), 0);
        IF (@qty = 0) SET @qty = CASE WHEN @PricePerCrate > 0 THEN @tot / @PricePerCrate ELSE @CratesSold END;
        DECLARE @up DECIMAL(14,2) = CASE WHEN @qty > 0 THEN CAST(@tot / @qty AS DECIMAL(14,2)) ELSE @PricePerCrate END;
        DECLARE @method NVARCHAR(30) = CASE WHEN @momo >= @cash AND @momo >= @bank AND @momo > 0 THEN N'Mobile Money'
                                            WHEN @bank >= @cash AND @bank > 0 THEN N'Bank' ELSE N'Cash' END;

        INSERT INTO dbo.Sale (UserId, SaleDate, Product, Quantity, UnitPrice, TotalAmount, PaymentMethod, CustomerName, SaleDescription, FarmId, CreatedBy, Paid)
        VALUES (@user, @DateD, N'Eggs', @qty, @up, CAST(@tot AS DECIMAL(18,2)), @method,
                ISNULL(@csLabel, N'Delivery Sale'), CONCAT(N'Driver return #', @PoultryDriverReturnId), @FarmId, @user,
                CASE WHEN @credit > 0 THEN 0 ELSE 1 END);
        DECLARE @saleId INT = CAST(SCOPE_IDENTITY() AS INT);

        UPDATE dbo.PoultryDriverReturnCustomerSales SET GeneratedSaleId = @saleId, UpdatedAt = SYSUTCDATETIME()
        WHERE PoultryDriverReturnCustomerSaleId = @csId;

        FETCH NEXT FROM cur INTO @csId, @csLabel, @tot, @cash, @momo, @bank, @credit;
    END
    CLOSE cur; DEALLOCATE cur;

    -- (d) Delivery expenses -> dbo.Expense (one per approved staged row).
    IF @gid IS NOT NULL
    BEGIN
        DECLARE ecur CURSOR LOCAL FAST_FORWARD FOR
            SELECT PoultryDriverDeliveryExpenseId, ExpenseCategory, Amount, Description
            FROM dbo.PoultryDriverDeliveryExpenses
            WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND IsApproved = 1 AND LinkedExpenseId IS NULL AND Amount > 0;
        DECLARE @deId INT, @cat NVARCHAR(40), @amt DECIMAL(14,2), @edesc NVARCHAR(500);
        OPEN ecur;
        FETCH NEXT FROM ecur INTO @deId, @cat, @amt, @edesc;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            INSERT INTO dbo.Expense (ExpenseDate, Category, Description, Amount, PaymentMethod, Supplier, FlockId, CreatedDate, UserId, FarmId, SourceType, SourceId)
            VALUES (ISNULL(@ReturnDate, SYSUTCDATETIME()), N'Delivery Expense',
                    CONCAT(N'Driver return #', @PoultryDriverReturnId, N' - ', @cat, CASE WHEN @edesc IS NULL THEN N'' ELSE CONCAT(N' (', @edesc, N')') END),
                    @amt, N'Cash', NULL, NULL, SYSUTCDATETIME(), @user, @gid, N'PoultryDriverReturn', @PoultryDriverReturnId);
            UPDATE dbo.PoultryDriverDeliveryExpenses SET LinkedExpenseId = CAST(SCOPE_IDENTITY() AS INT), UpdatedAt = SYSUTCDATETIME()
            WHERE PoultryDriverDeliveryExpenseId = @deId;
            FETCH NEXT FROM ecur INTO @deId, @cat, @amt, @edesc;
        END
        CLOSE ecur; DEALLOCATE ecur;
    END

    -- (e) Cash physically collected -> CashAdjustment ('In').
    DECLARE @CashIn DECIMAL(14,2) = ISNULL(@CashCollected,0) + ISNULL(@MoMoCollected,0) + ISNULL(@BankCollected,0);
    IF (@CashIn > 0)
    BEGIN
        INSERT INTO dbo.CashAdjustment (UserId, FarmId, AdjustmentDate, AdjustmentType, Amount, Description, CreatedDate)
        VALUES (@user, @FarmId, ISNULL(@ReturnDate, SYSUTCDATETIME()), N'In', @CashIn,
                CONCAT(N'Driver return #', @PoultryDriverReturnId, N' cash collected'), SYSUTCDATETIME());
        UPDATE dbo.PoultryDriverReturns SET LinkedCashAdjId = CAST(SCOPE_IDENTITY() AS INT)
        WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId;
    END

    -- (f) Shortage row.
    IF (@Shortage > 0)
        INSERT INTO dbo.PoultryDriverShortages
            (FarmId, PoultryDriverId, PoultryVehicleLoadingId, PoultryDriverReturnId, ShortageDate, ExpectedAmount, ActualAmount, ShortageAmount, Status)
        VALUES (@FarmId, @DriverId, @LoadingId, @PoultryDriverReturnId, SYSUTCDATETIME(), @ExpectedCash, @TotalAccounted, @Shortage, 'Pending');

    COMMIT TRANSACTION;

    SELECT PoultryDriverReturnId, Status, ApprovedBy, ApprovedAt, ShortageAmount, OverageAmount
    FROM dbo.PoultryDriverReturns WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId;
END
GO

-- Insert + approve in one call.
CREATE OR ALTER PROCEDURE dbo.spPoultryDriverReturn_ApproveReconcile
    @FarmId NVARCHAR(450), @PoultryVehicleLoadingId INT, @ReturnDate DATETIME2 = NULL,
    @CratesSold INT, @CratesReturned INT, @CratesDamaged INT = 0, @MissingCrates INT = 0,
    @CashCollected DECIMAL(14,2) = 0, @MoMoCollected DECIMAL(14,2) = 0, @BankCollected DECIMAL(14,2) = 0,
    @CreditSalesAmount DECIMAL(14,2) = 0, @CashReturnedByDriver DECIMAL(14,2) = 0,
    @ApprovedDeliveryExpenses DECIMAL(14,2) = 0, @SalesPostingMode NVARCHAR(20) = 'Detailed',
    @PrimaryCustomerId INT = NULL, @ReconciledByStaffId INT = NULL,
    @Notes NVARCHAR(1000) = NULL, @CreatedBy NVARCHAR(450) = NULL,
    @ItemsJson NVARCHAR(MAX) = NULL, @CustomerSalesJson NVARCHAR(MAX) = NULL, @ExpensesJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @rid INT;
    EXEC dbo.spPoultryDriverReturn_Insert
        @FarmId=@FarmId, @PoultryVehicleLoadingId=@PoultryVehicleLoadingId, @ReturnDate=@ReturnDate,
        @CratesSold=@CratesSold, @CratesReturned=@CratesReturned, @CratesDamaged=@CratesDamaged, @MissingCrates=@MissingCrates,
        @CashCollected=@CashCollected, @MoMoCollected=@MoMoCollected, @BankCollected=@BankCollected,
        @CreditSalesAmount=@CreditSalesAmount, @CashReturnedByDriver=@CashReturnedByDriver,
        @ApprovedDeliveryExpenses=@ApprovedDeliveryExpenses, @SalesPostingMode=@SalesPostingMode,
        @PrimaryCustomerId=@PrimaryCustomerId, @ReconciledByStaffId=@ReconciledByStaffId,
        @Notes=@Notes, @CreatedBy=@CreatedBy, @ItemsJson=@ItemsJson, @CustomerSalesJson=@CustomerSalesJson,
        @ExpensesJson=@ExpensesJson, @NewReturnId=@rid OUTPUT;

    EXEC dbo.spPoultryDriverReturn_Approve @PoultryDriverReturnId=@rid, @FarmId=@FarmId, @ApprovedBy=@CreatedBy;
END
GO

-- Reverse an Approved return: unwind all postings; back to Draft / loading Loaded.
CREATE OR ALTER PROCEDURE dbo.spPoultryDriverReturn_Reverse
    @PoultryDriverReturnId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Status NVARCHAR(20), @LoadingId INT, @CashId INT;
    SELECT @Status = Status, @LoadingId = PoultryVehicleLoadingId, @CashId = LinkedCashAdjId
    FROM dbo.PoultryDriverReturns WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId;
    IF @Status IS NULL BEGIN RAISERROR('Driver return not found.', 16, 1); RETURN; END
    IF @Status <> 'Approved' BEGIN RAISERROR('Only an Approved driver return can be reversed.', 16, 1); RETURN; END

    DECLARE @gid UNIQUEIDENTIFIER = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER);
    BEGIN TRANSACTION;

    -- Sales
    DELETE s FROM dbo.Sale s
    INNER JOIN dbo.PoultryDriverReturnCustomerSales cs ON cs.GeneratedSaleId = s.SaleId
    WHERE cs.PoultryDriverReturnId = @PoultryDriverReturnId AND s.FarmId = @FarmId;
    UPDATE dbo.PoultryDriverReturnCustomerSales SET GeneratedSaleId = NULL, UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryDriverReturnId = @PoultryDriverReturnId;
    -- Drop any auto-synthesized summary row so re-approve regenerates cleanly.
    DELETE FROM dbo.PoultryDriverReturnCustomerSales
    WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND CustomerLabel = N'Delivery Sale' AND Notes = N'Auto summary';

    -- Expenses
    IF @gid IS NOT NULL
        DELETE e FROM dbo.Expense e
        INNER JOIN dbo.PoultryDriverDeliveryExpenses de ON de.LinkedExpenseId = e.ExpenseId
        WHERE de.PoultryDriverReturnId = @PoultryDriverReturnId AND e.FarmId = @gid;
    UPDATE dbo.PoultryDriverDeliveryExpenses SET LinkedExpenseId = NULL, UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryDriverReturnId = @PoultryDriverReturnId;

    -- Cash
    IF @CashId IS NOT NULL DELETE FROM dbo.CashAdjustment WHERE AdjustmentId = @CashId AND FarmId = @FarmId;

    -- Stock + loss
    DELETE FROM dbo.PoultryStockTransactions WHERE FarmId = @FarmId AND TxnType = 'Driver Return In' AND RelatedId = @PoultryDriverReturnId;
    DELETE FROM dbo.PoultryProductionLoss WHERE FarmId = @FarmId AND SourceType = 'PoultryDriverReturn' AND SourceId = @PoultryDriverReturnId;

    -- Shortage
    DELETE FROM dbo.PoultryDriverShortages WHERE FarmId = @FarmId AND PoultryDriverReturnId = @PoultryDriverReturnId;

    UPDATE dbo.PoultryDriverReturns
    SET Status = 'Draft', ShortageAmount = 0, OverageAmount = 0, LinkedCashAdjId = NULL,
        ApprovedBy = NULL, ApprovedAt = NULL, UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId;

    UPDATE dbo.PoultryVehicleLoadings SET Status = 'Loaded', UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryVehicleLoadingId = @LoadingId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
    SELECT @PoultryDriverReturnId, 'Draft';
END
GO

-- Cancel a Draft return (no postings yet).
CREATE OR ALTER PROCEDURE dbo.spPoultryDriverReturn_Cancel
    @PoultryDriverReturnId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.PoultryDriverReturns WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId;
    IF @Status IS NULL BEGIN RAISERROR('Driver return not found.', 16, 1); RETURN; END
    IF @Status = 'Approved' BEGIN RAISERROR('Reverse an Approved return before cancelling.', 16, 1); RETURN; END
    UPDATE dbo.PoultryDriverReturns SET Status = 'Cancelled', UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId;
    SELECT @PoultryDriverReturnId, 'Cancelled';
END
GO

-- Uncancel a Cancelled return back to Draft.
CREATE OR ALTER PROCEDURE dbo.spPoultryDriverReturn_Uncancel
    @PoultryDriverReturnId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Status NVARCHAR(20), @LoadingId INT;
    SELECT @Status = Status, @LoadingId = PoultryVehicleLoadingId
    FROM dbo.PoultryDriverReturns WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId;
    IF @Status IS NULL BEGIN RAISERROR('Driver return not found.', 16, 1); RETURN; END
    IF @Status <> 'Cancelled' BEGIN RAISERROR('Only a Cancelled return can be uncancelled.', 16, 1); RETURN; END
    IF EXISTS (SELECT 1 FROM dbo.PoultryDriverReturns
               WHERE PoultryVehicleLoadingId = @LoadingId AND FarmId = @FarmId AND Status <> 'Cancelled' AND PoultryDriverReturnId <> @PoultryDriverReturnId)
    BEGIN RAISERROR('Another open return exists for this loading.', 16, 1); RETURN; END
    UPDATE dbo.PoultryDriverReturns SET Status = 'Draft', UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId;
    SELECT @PoultryDriverReturnId, 'Draft';
END
GO

-- Hard-delete a Cancelled return (cascades items/customer-sales/expenses via FKs).
CREATE OR ALTER PROCEDURE dbo.spPoultryDriverReturn_Delete
    @PoultryDriverReturnId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.PoultryDriverReturns WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId;
    IF @Status IS NULL BEGIN RAISERROR('Driver return not found.', 16, 1); RETURN; END
    IF @Status = 'Approved' BEGIN RAISERROR('Reverse an Approved return before deleting.', 16, 1); RETURN; END
    DELETE FROM dbo.PoultryDriverReturns WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId;
    SELECT @@ROWCOUNT;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDriverReturn_UpdatePostingMode
    @PoultryDriverReturnId INT, @FarmId NVARCHAR(450), @SalesPostingMode NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryDriverReturns SET SalesPostingMode = @SalesPostingMode, UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId AND Status = 'Draft';
    SELECT @@ROWCOUNT;
END
GO

-- #############################################################################
-- DELIVERY EXPENSES (read)
-- #############################################################################

CREATE OR ALTER PROCEDURE dbo.spPoultryDriverDeliveryExpense_GetByReturn
    @PoultryDriverReturnId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.PoultryDriverDeliveryExpenses
    WHERE PoultryDriverReturnId = @PoultryDriverReturnId AND FarmId = @FarmId
    ORDER BY PoultryDriverDeliveryExpenseId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDriverDeliveryExpense_ListAll
    @FarmId NVARCHAR(450), @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT de.*, r.ReturnDate, l.PoultryDriverId, d.DriverName
    FROM   dbo.PoultryDriverDeliveryExpenses de
    LEFT   JOIN dbo.PoultryDriverReturns   r ON r.PoultryDriverReturnId  = de.PoultryDriverReturnId
    LEFT   JOIN dbo.PoultryVehicleLoadings l ON l.PoultryVehicleLoadingId = de.PoultryVehicleLoadingId
    LEFT   JOIN dbo.PoultryDrivers         d ON d.PoultryDriverId         = l.PoultryDriverId
    WHERE  de.FarmId = @FarmId
       AND (@FromDate IS NULL OR CAST(de.CreatedAt AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(de.CreatedAt AS DATE) <= @ToDate)
    ORDER  BY de.PoultryDriverDeliveryExpenseId DESC;
END
GO

-- #############################################################################
-- SHORTAGES
-- #############################################################################

CREATE OR ALTER PROCEDURE dbo.spPoultryDriverShortage_GetAll
    @FarmId NVARCHAR(450), @Status NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.*, d.DriverName
    FROM   dbo.PoultryDriverShortages s
    LEFT   JOIN dbo.PoultryDrivers d ON d.PoultryDriverId = s.PoultryDriverId
    WHERE  s.FarmId = @FarmId AND (@Status IS NULL OR s.Status = @Status)
    ORDER  BY s.ShortageDate DESC, s.PoultryDriverShortageId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDriverShortage_Resolve
    @PoultryDriverShortageId INT, @FarmId NVARCHAR(450), @Status NVARCHAR(20), @ApprovedBy NVARCHAR(450) = NULL, @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryDriverShortages
    SET Status = @Status, ApprovedBy = @ApprovedBy, Notes = ISNULL(@Notes, Notes), UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryDriverShortageId = @PoultryDriverShortageId AND FarmId = @FarmId;
    SELECT @@ROWCOUNT;
END
GO

PRINT '139_AddPoultryDriverDistributionStoredProcedures.sql complete.';
GO

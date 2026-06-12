-- =============================================================================
-- 094_WaterDriverUpsertForEmployee.sql  (Feedback #18, Phase 1 — ADDITIVE)
--
-- One-transaction "make this employee a driver": assigns the Driver (or
-- MotorKingRider) job role to an existing employee AND upserts the linked
-- WaterDrivers profile (license, default vehicle/route, pay) keyed by
-- EmployeeUserId. The DriverName is always derived from AspNetUsers so a driver
-- can never drift from its employee record (feedback #18: "a driver must never
-- exist independently of an Employee record").
--
-- Idempotent / additive. Existing spWaterDriver_Insert is left intact for the
-- legacy standalone path; this SP is the merged path.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDriver_UpsertForEmployee
    @FarmId           NVARCHAR(450),
    @EmployeeUserId   NVARCHAR(450),
    @Role             NVARCHAR(40)  = N'Driver',   -- Driver | MotorKingRider
    @LicenseNumber    NVARCHAR(100) = NULL,
    @DefaultVehicleId INT           = NULL,
    @DefaultRouteId   INT           = NULL,
    @BasePay          DECIMAL(14,2) = NULL,
    @CommissionPerBag DECIMAL(14,2) = NULL,
    @Notes            NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Name NVARCHAR(200);
    SELECT @Name = LTRIM(RTRIM(CONCAT(FirstName, N' ', LastName)))
    FROM   dbo.AspNetUsers WHERE Id = @EmployeeUserId;
    IF (@Name IS NULL) BEGIN RAISERROR('Employee not found.', 16, 1); RETURN; END
    IF (@Role NOT IN (N'Driver', N'MotorKingRider')) SET @Role = N'Driver';

    BEGIN TRANSACTION;

    -- 1. Ensure the job role is assigned (idempotent).
    IF NOT EXISTS (SELECT 1 FROM dbo.EmployeeJobRoles
                   WHERE EmployeeUserId = @EmployeeUserId AND FarmId = @FarmId AND Role = @Role)
        INSERT INTO dbo.EmployeeJobRoles (EmployeeUserId, FarmId, Role)
        VALUES (@EmployeeUserId, @FarmId, @Role);

    -- 2. Upsert the WaterDrivers profile linked to this employee.
    IF EXISTS (SELECT 1 FROM dbo.WaterDrivers WHERE FarmId = @FarmId AND EmployeeUserId = @EmployeeUserId)
    BEGIN
        UPDATE dbo.WaterDrivers
        SET    DriverName       = @Name,
               PhoneNumber      = (SELECT PhoneNumber FROM dbo.AspNetUsers WHERE Id = @EmployeeUserId),
               LicenseNumber    = @LicenseNumber,
               DefaultVehicleId = @DefaultVehicleId,
               DefaultRouteId   = @DefaultRouteId,
               BasePay          = @BasePay,
               CommissionPerBag = @CommissionPerBag,
               IsActive         = 1,
               Notes            = @Notes,
               UpdatedAt        = SYSUTCDATETIME()
        WHERE  FarmId = @FarmId AND EmployeeUserId = @EmployeeUserId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.WaterDrivers
            (FarmId, DriverName, PhoneNumber, LicenseNumber, DefaultVehicleId, DefaultRouteId,
             BasePay, CommissionPerBag, IsActive, Notes, EmployeeUserId)
        VALUES
            (@FarmId, @Name, (SELECT PhoneNumber FROM dbo.AspNetUsers WHERE Id = @EmployeeUserId),
             @LicenseNumber, @DefaultVehicleId, @DefaultRouteId, @BasePay, @CommissionPerBag, 1, @Notes, @EmployeeUserId);
    END

    COMMIT TRANSACTION;

    SELECT TOP 1 WaterDriverId, FarmId, DriverName, PhoneNumber, LicenseNumber,
                 DefaultVehicleId, DefaultRouteId, BasePay, CommissionPerBag, IsActive, Notes, EmployeeUserId
    FROM   dbo.WaterDrivers WHERE FarmId = @FarmId AND EmployeeUserId = @EmployeeUserId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterDriver_UpsertForEmployee TO [Techretainer];
GO
IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterDriver_UpsertForEmployee TO PoultryAppRole;
GO

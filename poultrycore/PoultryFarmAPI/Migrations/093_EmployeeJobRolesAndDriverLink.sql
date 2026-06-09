-- =============================================================================
-- 093_EmployeeJobRolesAndDriverLink.sql   (Feedback #18, Phase 1 — ADDITIVE)
--
-- Foundation for merging Staff into the Employee record and sourcing Drivers
-- from Employees. Nothing existing is altered destructively:
--   * New table dbo.EmployeeJobRoles — multiple job roles per employee per farm
--     (Driver, MotorKingRider, MachineOperator, Salesperson, …). App-level
--     Identity roles (Admin/Staff) are untouched; these are *job* roles.
--   * dbo.WaterDrivers gets a nullable EmployeeUserId so a driver row can be
--     linked to its AspNetUsers employee. Existing standalone drivers keep
--     working (EmployeeUserId stays NULL) so the Drivers page is backward
--     compatible during the transition.
--   * SPs to set/get an employee's job roles and to list a farm's drivers as
--     "employees whose roles include Driver/MotorKingRider" UNIONed with any
--     legacy standalone WaterDrivers rows.
--
-- Idempotent. Safe to run repeatedly. All objects dbo-owned so ownership
-- chaining covers the runtime login (Techretainer / PoultryAppRole).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.EmployeeJobRoles','U') IS NULL
BEGIN
    CREATE TABLE dbo.EmployeeJobRoles (
        EmployeeJobRoleId INT IDENTITY(1,1) PRIMARY KEY,
        EmployeeUserId    NVARCHAR(450) NOT NULL,
        FarmId            NVARCHAR(450) NOT NULL,
        Role              NVARCHAR(40)  NOT NULL,
        CreatedAt         DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
    );
    CREATE UNIQUE INDEX UX_EmployeeJobRoles_User_Farm_Role
        ON dbo.EmployeeJobRoles (EmployeeUserId, FarmId, Role);
END
GO

IF COL_LENGTH('dbo.WaterDrivers','EmployeeUserId') IS NULL
    ALTER TABLE dbo.WaterDrivers ADD EmployeeUserId NVARCHAR(450) NULL;
GO

-- Replace the full set of job roles for an employee in a farm (CSV input).
CREATE OR ALTER PROCEDURE dbo.spEmployeeJobRole_Set
    @EmployeeUserId NVARCHAR(450),
    @FarmId         NVARCHAR(450),
    @RolesCsv       NVARCHAR(MAX) = NULL   -- comma-separated, e.g. 'Driver,Salesperson'
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRAN;
    DELETE FROM dbo.EmployeeJobRoles WHERE EmployeeUserId = @EmployeeUserId AND FarmId = @FarmId;
    IF (@RolesCsv IS NOT NULL AND LTRIM(RTRIM(@RolesCsv)) <> N'')
        INSERT INTO dbo.EmployeeJobRoles (EmployeeUserId, FarmId, Role)
        SELECT DISTINCT @EmployeeUserId, @FarmId, LTRIM(RTRIM(value))
        FROM   STRING_SPLIT(@RolesCsv, ',')
        WHERE  LTRIM(RTRIM(value)) <> N'';
    COMMIT TRAN;
END
GO

CREATE OR ALTER PROCEDURE dbo.spEmployeeJobRole_GetByEmployee
    @EmployeeUserId NVARCHAR(450),
    @FarmId         NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Role FROM dbo.EmployeeJobRoles
    WHERE  EmployeeUserId = @EmployeeUserId AND FarmId = @FarmId
    ORDER  BY Role;
END
GO

-- Drivers for a farm = employees whose job roles include Driver / MotorKingRider,
-- joined to their (optional) WaterDrivers profile — UNIONed with any legacy
-- standalone WaterDrivers rows not yet linked to an employee.
CREATE OR ALTER PROCEDURE dbo.spWaterDriver_ListForFarm
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        d.WaterDriverId,
        d.FarmId,
        COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(u.FirstName, N' ', u.LastName))), N''), d.DriverName) AS DriverName,
        COALESCE(d.PhoneNumber, u.PhoneNumber) AS PhoneNumber,
        d.LicenseNumber,
        d.DefaultVehicleId,
        d.DefaultRouteId,
        d.BasePay,
        d.CommissionPerBag,
        d.IsActive,
        d.Notes,
        d.EmployeeUserId
    FROM dbo.WaterDrivers d
    LEFT JOIN dbo.AspNetUsers u ON u.Id = d.EmployeeUserId
    WHERE d.FarmId = @FarmId AND d.IsActive = 1

    UNION ALL

    -- Employees with a Driver/MotorKingRider role who don't yet have a
    -- WaterDrivers profile row (so newly-roled employees still appear).
    SELECT
        CAST(0 AS INT)                AS WaterDriverId,
        r.FarmId,
        LTRIM(RTRIM(CONCAT(u.FirstName, N' ', u.LastName))) AS DriverName,
        u.PhoneNumber,
        CAST(NULL AS NVARCHAR(100))   AS LicenseNumber,
        CAST(NULL AS INT)             AS DefaultVehicleId,
        CAST(NULL AS INT)             AS DefaultRouteId,
        CAST(NULL AS DECIMAL(14,2))   AS BasePay,
        CAST(NULL AS DECIMAL(14,2))   AS CommissionPerBag,
        CAST(1 AS BIT)                AS IsActive,
        CAST(NULL AS NVARCHAR(500))   AS Notes,
        r.EmployeeUserId
    FROM dbo.EmployeeJobRoles r
    JOIN dbo.AspNetUsers u ON u.Id = r.EmployeeUserId
    WHERE r.FarmId = @FarmId
      AND r.Role IN (N'Driver', N'MotorKingRider')
      AND NOT EXISTS (
          SELECT 1 FROM dbo.WaterDrivers d
          WHERE d.FarmId = r.FarmId AND d.EmployeeUserId = r.EmployeeUserId
      );
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spEmployeeJobRole_Set           TO [Techretainer];
    GRANT EXECUTE ON dbo.spEmployeeJobRole_GetByEmployee TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterDriver_ListForFarm       TO [Techretainer];
    GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.EmployeeJobRoles TO [Techretainer];
    PRINT '093: granted to Techretainer.';
END
GO
IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spEmployeeJobRole_Set           TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spEmployeeJobRole_GetByEmployee TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterDriver_ListForFarm       TO PoultryAppRole;
    GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.EmployeeJobRoles TO PoultryAppRole;
END
GO

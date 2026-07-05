-- =============================================================================
-- Migration 141: Poultry driver — inherit phone (and name) from the employee
-- =============================================================================
-- Fix: creating a driver from an employee left PhoneNumber blank on the driver
-- record (it only showed after a manual edit). spPoultryDriver_UpsertForEmployee
-- now falls back to dbo.AspNetUsers.PhoneNumber when the caller doesn't supply
-- a phone, so both the "new employee & driver" and "assign existing employee"
-- flows populate the driver's phone automatically.
--
-- Idempotent (CREATE OR ALTER). Safe to re-run.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDriver_UpsertForEmployee
    @FarmId NVARCHAR(450), @EmployeeUserId NVARCHAR(450),
    @DriverName NVARCHAR(150) = NULL, @PhoneNumber NVARCHAR(50) = NULL,
    @LicenseNumber NVARCHAR(60) = NULL, @BasePay DECIMAL(14,2) = NULL,
    @CommissionPerCrate DECIMAL(14,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Pull name + phone off the linked employee once.
    DECLARE @Name NVARCHAR(150) = @DriverName, @Phone NVARCHAR(50) = @PhoneNumber;
    IF @Name IS NULL OR @Phone IS NULL
        SELECT @Name  = ISNULL(@Name, ISNULL(NULLIF(u.UserName, N''), u.Email)),
               @Phone = ISNULL(@Phone, u.PhoneNumber)
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
            (@FarmId, @Name, @Phone, @LicenseNumber, @BasePay, @CommissionPerCrate, 1, @EmployeeUserId);
        SET @Id = CAST(SCOPE_IDENTITY() AS INT);
    END
    ELSE
    BEGIN
        UPDATE dbo.PoultryDrivers
        SET DriverName = @Name,
            PhoneNumber = ISNULL(@Phone, PhoneNumber),
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

PRINT '141_PoultryDriverPhoneFromEmployee.sql complete.';
GO

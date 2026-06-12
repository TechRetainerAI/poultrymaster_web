-- =============================================================================
-- Hotfix 027: Align spCompany_* with the real Farms schema in PoultryMasterDev
-- =============================================================================
-- The Farms table in this DB has Id (NVARCHAR(450), PK) as the actual FarmId
-- the rest of the app uses, plus a vestigial FarmId column that defaults to '0'.
-- The original procs (in migration 026) targeted FarmId; this hotfix rewrites
-- them to use Id and also handles NOT NULL Email by defaulting to ''.
-- Idempotent (CREATE OR ALTER).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spCompany_Create
    @FarmId       NVARCHAR(450),       -- maps to Farms.Id
    @Name         NVARCHAR(255),
    @Type         NVARCHAR(50),
    @OwnerUserId  NVARCHAR(450),
    @Email        NVARCHAR(255) = NULL,
    @PhoneNumber  NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Farms.Email is NOT NULL in this DB. Default to '' when caller omits it.
    DECLARE @safeEmail NVARCHAR(255) = ISNULL(@Email, '');

    INSERT INTO dbo.Farms (Id, Name, Email, PhoneNumber, Type, OwnerUserId, CreatedAt, DateCreated)
    VALUES (@FarmId, @Name, @safeEmail, @PhoneNumber, @Type, @OwnerUserId, SYSUTCDATETIME(), SYSUTCDATETIME());

    -- Owner is automatically a member with Admin role.
    IF NOT EXISTS (SELECT 1 FROM dbo.UserFarms WHERE UserId = @OwnerUserId AND FarmId = @FarmId)
    BEGIN
        INSERT INTO dbo.UserFarms (UserId, FarmId, Role)
        VALUES (@OwnerUserId, @FarmId, 'Admin');
    END

    SELECT f.Id AS FarmId, f.Name, f.Type, f.OwnerUserId, f.Email, f.PhoneNumber,
           f.CreatedAt, f.UpdatedAt
    FROM dbo.Farms f
    WHERE f.Id = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spCompany_GetByUserId
    @UserId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT f.Id AS FarmId, f.Name, f.Type, f.OwnerUserId, f.Email, f.PhoneNumber,
           f.CreatedAt, f.UpdatedAt, uf.Role
    FROM   dbo.Farms f
    INNER JOIN dbo.UserFarms uf ON uf.FarmId = f.Id
    WHERE  uf.UserId = @UserId
    ORDER  BY f.Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.spCompany_GetById
    @FarmId NVARCHAR(450),
    @UserId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1 f.Id AS FarmId, f.Name, f.Type, f.OwnerUserId, f.Email, f.PhoneNumber,
                 f.CreatedAt, f.UpdatedAt, uf.Role
    FROM   dbo.Farms f
    INNER JOIN dbo.UserFarms uf ON uf.FarmId = f.Id
    WHERE  f.Id = @FarmId AND uf.UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spCompany_Update
    @FarmId       NVARCHAR(450),
    @Name         NVARCHAR(255),
    @Email        NVARCHAR(255) = NULL,
    @PhoneNumber  NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Farms
    SET    Name        = @Name,
           Email       = ISNULL(@Email, Email),  -- keep existing if NULL
           PhoneNumber = @PhoneNumber,
           UpdatedAt   = SYSUTCDATETIME()
    WHERE  Id = @FarmId;
END
GO

-- Re-run UserFarms backfill correctly now that we know Farms.Id is the key.
-- (Previous migration 025 joined Farms.FarmId='0' which never matched any user.)
INSERT INTO dbo.UserFarms (UserId, FarmId, Role)
SELECT u.Id, u.FarmId,
       CASE WHEN u.IsStaff = 1 THEN 'Staff' ELSE 'Admin' END
FROM   dbo.AspNetUsers u
WHERE  u.FarmId IS NOT NULL AND u.FarmId <> ''
AND    EXISTS (SELECT 1 FROM dbo.Farms f WHERE f.Id = u.FarmId)
AND    NOT EXISTS (
          SELECT 1 FROM dbo.UserFarms uf
          WHERE  uf.UserId = u.Id AND uf.FarmId = u.FarmId
       );
PRINT CONCAT('Re-backfilled UserFarms rows: ', @@ROWCOUNT);
GO

-- Re-run OwnerUserId backfill correctly using Farms.Id.
UPDATE f
SET f.OwnerUserId = u.Id
FROM dbo.Farms f
JOIN dbo.AspNetUsers u ON u.FarmId = f.Id AND u.IsStaff = 0
WHERE f.OwnerUserId IS NULL;
PRINT CONCAT('Backfilled Farms.OwnerUserId rows: ', @@ROWCOUNT);
GO

PRINT 'Hotfix 027 complete.';
GO

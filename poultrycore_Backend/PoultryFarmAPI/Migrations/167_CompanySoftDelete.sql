-- =============================================================================
-- Migration 167: soft-delete a company (Business Office → delete company)
-- =============================================================================
-- Owners can remove a company from their Business Office. Soft delete: the farm
-- is flagged IsDeleted=1 and unlinked from all members (UserFarms), so it
-- disappears from the app, but its operational data stays in the DB and can be
-- restored by clearing the flag. The company's own tables are untouched.
--
-- Also hides deleted companies from the two read SPs used by /Companies.
-- Idempotent (COL_LENGTH guard + CREATE OR ALTER).
-- =============================================================================
SET NOCOUNT ON; SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.Farms','IsDeleted') IS NULL
    ALTER TABLE dbo.Farms ADD IsDeleted BIT NOT NULL CONSTRAINT DF_Farms_IsDeleted DEFAULT (0);
GO

-- Soft-delete: only the OWNER may delete, and only their own company. Flags the
-- farm and removes every membership link. Returns 1 on success, 0 if the caller
-- isn't the owner (or the farm doesn't exist / is already deleted).
CREATE OR ALTER PROCEDURE dbo.spCompany_Delete
    @FarmId NVARCHAR(450),
    @UserId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Farms
                   WHERE FarmId = @FarmId AND OwnerUserId = @UserId AND IsDeleted = 0)
    BEGIN
        SELECT CAST(0 AS INT) AS Deleted;   -- not owner / not found / already gone
        RETURN;
    END

    BEGIN TRANSACTION;
        UPDATE dbo.Farms
        SET    IsDeleted = 1, UpdatedAt = SYSUTCDATETIME()
        WHERE  FarmId = @FarmId;

        -- Unlink every member so it drops off everyone's company list.
        DELETE FROM dbo.UserFarms WHERE FarmId = @FarmId;

        -- Anyone currently "sitting in" the deleted company gets a neutral
        -- active company; the app then routes them to the Business Office.
        UPDATE dbo.AspNetUsers SET FarmId = NULL WHERE FarmId = @FarmId;
    COMMIT TRANSACTION;

    SELECT CAST(1 AS INT) AS Deleted;
END
GO

-- Hide deleted companies from the list + single-get read paths.
CREATE OR ALTER PROCEDURE dbo.spCompany_GetByUserId
    @UserId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.FarmId, f.Name, f.Type, f.OwnerUserId, f.Email, f.PhoneNumber,
           f.CreatedAt, f.UpdatedAt, uf.Role
    FROM   dbo.Farms f
    INNER  JOIN dbo.UserFarms uf ON uf.FarmId = f.FarmId
    WHERE  uf.UserId = @UserId AND f.IsDeleted = 0
    UNION
    SELECT f.FarmId, f.Name, f.Type, f.OwnerUserId, f.Email, f.PhoneNumber,
           f.CreatedAt, f.UpdatedAt, 'Admin' AS Role
    FROM   dbo.Farms f
    WHERE  f.OwnerUserId = @UserId AND f.IsDeleted = 0
      AND  NOT EXISTS (SELECT 1 FROM dbo.UserFarms uf2 WHERE uf2.FarmId = f.FarmId AND uf2.UserId = @UserId)
    ORDER  BY Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.spCompany_GetById
    @FarmId NVARCHAR(450),
    @UserId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP 1 f.FarmId, f.Name, f.Type, f.OwnerUserId, f.Email, f.PhoneNumber,
           f.CreatedAt, f.UpdatedAt, uf.Role
    FROM   dbo.Farms f
    INNER JOIN dbo.UserFarms uf ON uf.FarmId = f.FarmId
    WHERE  f.FarmId = @FarmId AND uf.UserId = @UserId AND f.IsDeleted = 0;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spCompany_Delete       TO [Techretainer];
    GRANT EXECUTE ON dbo.spCompany_GetByUserId  TO [Techretainer];
    GRANT EXECUTE ON dbo.spCompany_GetById      TO [Techretainer];
END
GO

PRINT '167_CompanySoftDelete.sql complete.';
GO

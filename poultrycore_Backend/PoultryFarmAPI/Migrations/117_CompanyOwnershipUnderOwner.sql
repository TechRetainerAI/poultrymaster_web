/* ============================================================================
   117_CompanyOwnershipUnderOwner.sql

   Fix: "An owner added an admin staff. The admin created a new company, but the
   OWNER did not see it." (Prompt 1 — Organization / Company Access model.)

   Root cause:
     - spCompany_Create stamped Farms.OwnerUserId = the CREATING user and added
       only that user to UserFarms.
     - spCompany_GetByUserId lists companies only where UserFarms.UserId = you.
     => A company created by an admin staff is invisible to the real owner.

   This is the surgical, low-risk fix using the EXISTING model (Farms.OwnerUserId
   + UserFarms) — no schema changes, no payroll/driver/staff refactor.

   1. spCompany_Create: resolve the real owner. If the creating user is staff
      (IsStaff=1), the company belongs to that staff's organization OWNER (their
      primary farm's OwnerUserId), not the staff member. Both the owner AND the
      creator get a UserFarms membership so both see the company.
   2. spCompany_GetByUserId: an owner ALWAYS sees every company they own
      (UNION on Farms.OwnerUserId), even if a membership row is missing.
   3. Backfill existing data:
      a. Re-point companies whose on-paper owner is a STAFF user to that staff's
         organization owner.
      b. Ensure every farm's owner has an admin UserFarms membership (additive).

   AspNetUsers, Farms and UserFarms all live in the same database, so the SP can
   resolve the owner directly. Idempotent (CREATE OR ALTER + guarded data fix).
   ============================================================================ */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---- 1. Create company under the resolved organization owner ------------- */
CREATE OR ALTER PROCEDURE dbo.spCompany_Create
    @FarmId       NVARCHAR(450),
    @Name         NVARCHAR(255),
    @Type         NVARCHAR(50),
    @OwnerUserId  NVARCHAR(450),   -- the CREATING user (from the JWT)
    @Email        NVARCHAR(255) = NULL,
    @PhoneNumber  NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @safeEmail NVARCHAR(255) = ISNULL(@Email, '');

    -- Resolve the real organization owner. If the creator is staff (an admin
    -- added by an owner), the company must belong to that owner's account.
    DECLARE @ResolvedOwner NVARCHAR(450) = @OwnerUserId;
    IF OBJECT_ID('dbo.AspNetUsers') IS NOT NULL
    BEGIN
        DECLARE @IsStaff BIT = NULL, @CreatorFarmId NVARCHAR(450) = NULL;
        SELECT @IsStaff = IsStaff, @CreatorFarmId = FarmId
        FROM   dbo.AspNetUsers WHERE Id = @OwnerUserId;

        IF (@IsStaff = 1 AND @CreatorFarmId IS NOT NULL AND @CreatorFarmId <> '')
        BEGIN
            DECLARE @FarmOwner NVARCHAR(450) = NULL;
            SELECT @FarmOwner = OwnerUserId FROM dbo.Farms WHERE FarmId = @CreatorFarmId;
            IF (@FarmOwner IS NOT NULL AND @FarmOwner <> '')
                SET @ResolvedOwner = @FarmOwner;
        END
    END

    BEGIN TRANSACTION;

    INSERT INTO dbo.Farms (Id, FarmId, Name, Email, PhoneNumber, Type, OwnerUserId, CreatedAt, DateCreated)
    VALUES (
        LOWER(CAST(NEWID() AS NVARCHAR(450))),
        @FarmId, @Name, @safeEmail, @PhoneNumber, @Type, @ResolvedOwner,
        SYSUTCDATETIME(), SYSUTCDATETIME()
    );

    -- Owner membership => company appears in the owner's switcher.
    IF NOT EXISTS (SELECT 1 FROM dbo.UserFarms WHERE UserId = @ResolvedOwner AND FarmId = @FarmId)
        INSERT INTO dbo.UserFarms (UserId, FarmId, Role) VALUES (@ResolvedOwner, @FarmId, 'Admin');

    -- Creator keeps access too (when different from the owner).
    IF (@OwnerUserId <> @ResolvedOwner
        AND NOT EXISTS (SELECT 1 FROM dbo.UserFarms WHERE UserId = @OwnerUserId AND FarmId = @FarmId))
        INSERT INTO dbo.UserFarms (UserId, FarmId, Role) VALUES (@OwnerUserId, @FarmId, 'Admin');

    COMMIT TRANSACTION;

    SELECT f.FarmId, f.Name, f.Type, f.OwnerUserId, f.Email, f.PhoneNumber,
           f.CreatedAt, f.UpdatedAt, 'Admin' AS Role
    FROM   dbo.Farms f
    WHERE  f.FarmId = @FarmId;
END
GO

/* ---- 2. List: membership OR ownership ------------------------------------ */
CREATE OR ALTER PROCEDURE dbo.spCompany_GetByUserId
    @UserId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.FarmId, f.Name, f.Type, f.OwnerUserId, f.Email, f.PhoneNumber,
           f.CreatedAt, f.UpdatedAt, uf.Role
    FROM   dbo.Farms f
    INNER  JOIN dbo.UserFarms uf ON uf.FarmId = f.FarmId
    WHERE  uf.UserId = @UserId
    UNION
    -- An owner always sees every company they own, even without a membership row.
    SELECT f.FarmId, f.Name, f.Type, f.OwnerUserId, f.Email, f.PhoneNumber,
           f.CreatedAt, f.UpdatedAt, 'Admin' AS Role
    FROM   dbo.Farms f
    WHERE  f.OwnerUserId = @UserId
      AND  NOT EXISTS (SELECT 1 FROM dbo.UserFarms uf2 WHERE uf2.FarmId = f.FarmId AND uf2.UserId = @UserId)
    ORDER  BY Name;
END
GO

/* ---- 3. Backfill existing data ------------------------------------------- */
IF OBJECT_ID('dbo.AspNetUsers') IS NOT NULL
BEGIN
    -- 3a. Re-point companies whose on-paper owner is a STAFF user to that
    --     staff's organization owner.
    UPDATE f
    SET    f.OwnerUserId = fo.OwnerUserId
    FROM   dbo.Farms f
    JOIN   dbo.AspNetUsers u ON u.Id = f.OwnerUserId AND u.IsStaff = 1
    JOIN   dbo.Farms fo ON fo.FarmId = u.FarmId
    WHERE  fo.OwnerUserId IS NOT NULL AND fo.OwnerUserId <> '' AND fo.OwnerUserId <> f.OwnerUserId;
END
GO

-- 3b. Ensure every farm's owner has an admin membership (additive — never removes access).
INSERT INTO dbo.UserFarms (UserId, FarmId, Role)
SELECT f.OwnerUserId, f.FarmId, 'Admin'
FROM   dbo.Farms f
WHERE  f.OwnerUserId IS NOT NULL AND f.OwnerUserId <> ''
  AND  NOT EXISTS (SELECT 1 FROM dbo.UserFarms uf WHERE uf.FarmId = f.FarmId AND uf.UserId = f.OwnerUserId);
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spCompany_Create     TO [Techretainer];
    GRANT EXECUTE ON dbo.spCompany_GetByUserId TO [Techretainer];
END
GO

PRINT '117_CompanyOwnershipUnderOwner.sql complete.';
GO

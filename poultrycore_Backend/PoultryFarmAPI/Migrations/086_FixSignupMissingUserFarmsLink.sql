-- =============================================================================
-- Migration 086: Fix sp_CreateFarm missing UserFarms link + backfill orphans
-- =============================================================================
-- Test-report bug (Issue 2): "In the companies tab, it shows that we have no
-- company, but we do have a company. Then we created a poultry farm, which
-- resulted in the deletion of the water company we had."
--
-- Root cause: sp_CreateFarm (the signup path — see migration 053 §4) inserts
-- a row into dbo.Farms but does NOT create a corresponding dbo.UserFarms
-- link. /Companies/mine joins UserFarms → Farms (spCompany_GetByUserId from
-- migration 054), so a brand-new user's signup farm is invisible to the
-- companies UI even though AspNetUsers.FarmId points at a real Farms row.
--
-- When the user later creates a poultry farm via POST /api/Companies
-- (spCompany_Create from 054), that SP *does* insert into UserFarms — so
-- the new poultry company appears. From the test team's perspective:
--   before: 0 companies
--   after:  1 poultry company  ← looks like the water "got deleted"
-- The water row was never deleted; it was never linked.
--
-- This migration:
--   1. CREATE OR ALTERs sp_CreateFarm to also insert a UserFarms row in the
--      same transaction (idempotent guard for re-runs / future schema bumps).
--      We derive the UserId from AspNetUsers.FarmId = @FarmId (the signup
--      flow has already stamped AspNetUsers.FarmId via the auth pipeline).
--   2. Backfills UserFarms links for every AspNetUsers row whose FarmId
--      points at a real Farms row but has no matching UserFarms row. Heals
--      every existing affected account in one shot.
--
-- Safety:
--   * Idempotent. Step 1 uses CREATE OR ALTER; step 2 guards with NOT EXISTS.
--   * Step 2 only inserts links the data clearly implies (AspNetUsers.FarmId
--     already names the farm). It does NOT touch existing UserFarms rows or
--     delete anything.
--   * Role defaults to 'Admin' — the signup-created farm is owned by its
--     signup user, same as spCompany_Create does for explicitly-created
--     companies.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Fix sp_CreateFarm so signups create the UserFarms membership too.
-- -----------------------------------------------------------------------------
-- We pull the @OwnerUserId from AspNetUsers (which the auth pipeline has
-- already stamped with FarmId before this SP runs in some signup paths) and
-- fall back to inserting only the Farms row when no matching user exists yet
-- (rare race; the step-2 backfill or a future signup pass picks it up).
CREATE OR ALTER PROCEDURE dbo.sp_CreateFarm
    @FarmId      NVARCHAR(450),
    @Name        NVARCHAR(256),
    @Type        NVARCHAR(256),
    @Email       NVARCHAR(256),
    @PhoneNumber NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    INSERT INTO dbo.Farms (Id, FarmId, Name, Email, PhoneNumber, Type, CreatedAt, DateCreated)
    VALUES (
        LOWER(CAST(NEWID() AS NVARCHAR(450))),
        @FarmId,
        @Name,
        @Email,
        @PhoneNumber,
        @Type,
        SYSUTCDATETIME(),
        SYSUTCDATETIME()
    );

    -- Issue 2 fix: link the signup user as Admin so /Companies/mine returns
    -- the farm they just signed up for. Pick the user whose AspNetUsers.FarmId
    -- equals the new @FarmId. (For Email-keyed signup flows this resolves to
    -- the right account because the auth pipeline writes FarmId to the user
    -- row before calling this SP.)
    DECLARE @OwnerUserId NVARCHAR(450) = (
        SELECT TOP 1 u.Id
        FROM   dbo.AspNetUsers u
        WHERE  u.FarmId = @FarmId
           OR (u.Email IS NOT NULL AND u.Email = @Email)
        ORDER BY CASE WHEN u.FarmId = @FarmId THEN 0 ELSE 1 END
    );

    IF @OwnerUserId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.UserFarms WHERE UserId = @OwnerUserId AND FarmId = @FarmId)
    BEGIN
        INSERT INTO dbo.UserFarms (UserId, FarmId, Role)
        VALUES (@OwnerUserId, @FarmId, 'Admin');

        -- Stamp ownership on the Farms row too so spCompany_GetByUserId can
        -- still surface it if the UserFarms row is ever cleaned up.
        UPDATE dbo.Farms
        SET    OwnerUserId = @OwnerUserId,
               UpdatedAt   = SYSUTCDATETIME()
        WHERE  FarmId = @FarmId
          AND  (OwnerUserId IS NULL OR OwnerUserId = '');
    END

    COMMIT TRANSACTION;

    -- Same shape as the 053 version so the C# layer's rows-affected check
    -- keeps working unchanged.
    SELECT Id, FarmId, Name, Email, PhoneNumber, Type, CreatedAt
    FROM   dbo.Farms
    WHERE  FarmId = @FarmId
      AND  Name   = @Name
      AND  Email  = @Email;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.sp_CreateFarm TO [Techretainer];
    PRINT '086: granted EXECUTE on dbo.sp_CreateFarm to Techretainer.';
END
GO

-- -----------------------------------------------------------------------------
-- 2. Backfill UserFarms links for users whose AspNetUsers.FarmId points at a
--    real Farms row but who have no UserFarms membership. This is the heal
--    for every existing affected account.
-- -----------------------------------------------------------------------------
DECLARE @backfilled INT;

INSERT INTO dbo.UserFarms (UserId, FarmId, Role)
SELECT u.Id, u.FarmId, 'Admin'
FROM   dbo.AspNetUsers u
INNER  JOIN dbo.Farms f ON f.FarmId = u.FarmId
WHERE  u.FarmId IS NOT NULL
  AND  LTRIM(RTRIM(u.FarmId)) <> ''
  AND  NOT EXISTS (
       SELECT 1 FROM dbo.UserFarms uf
       WHERE  uf.UserId = u.Id AND uf.FarmId = u.FarmId
  );

SET @backfilled = @@ROWCOUNT;
PRINT CONCAT('086: backfilled ', @backfilled, ' missing UserFarms link(s) for existing signups.');

-- Also stamp Farms.OwnerUserId where it's missing so the company tile shows
-- the correct ownership badge.
UPDATE f
SET    f.OwnerUserId = u.Id,
       f.UpdatedAt   = SYSUTCDATETIME()
FROM   dbo.Farms f
INNER  JOIN dbo.AspNetUsers u ON u.FarmId = f.FarmId
WHERE  (f.OwnerUserId IS NULL OR f.OwnerUserId = '');

PRINT CONCAT('086: stamped OwnerUserId on ', @@ROWCOUNT, ' previously-anonymous Farms row(s).');
GO

-- -----------------------------------------------------------------------------
-- 3. Verification — should print 0 after this migration runs cleanly.
-- -----------------------------------------------------------------------------
DECLARE @stillOrphan INT = (
    SELECT COUNT(*) FROM dbo.AspNetUsers u
    INNER  JOIN dbo.Farms f ON f.FarmId = u.FarmId
    WHERE  u.FarmId IS NOT NULL
      AND  LTRIM(RTRIM(u.FarmId)) <> ''
      AND  NOT EXISTS (
           SELECT 1 FROM dbo.UserFarms uf
           WHERE  uf.UserId = u.Id AND uf.FarmId = u.FarmId
      )
);

PRINT CONCAT('086: users still missing a UserFarms link to their signup farm: ', @stillOrphan);
GO

PRINT '086_FixSignupMissingUserFarmsLink.sql complete.';
GO

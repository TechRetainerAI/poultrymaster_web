-- =============================================================================
-- Migration 046: Backfill orphan FarmId references
-- =============================================================================
-- Some AspNetUsers and UserFarms rows reference FarmIds that no longer exist
-- in dbo.Farms (rows deleted, or users created via an old registration flow
-- that never inserted a Farms row). Every Generic Company / Water / Poultry
-- endpoint that does `EnsureFarm(farmId)` returns 404 for these users, which
-- the v0/Vercel proxy in front of the Next.js app then converts to 500 — see
-- the recent /api/proxy/generic-company/.../products and /inventory/adjustments
-- regression.
--
-- This migration:
--   1. INSERTs a dbo.Farms row for every orphan FarmId referenced by
--      dbo.AspNetUsers, derived from the user's UserName and Id.
--   2. INSERTs a dbo.Farms row for every orphan FarmId referenced by
--      dbo.UserFarms (in case a user-farm membership exists without an
--      AspNetUsers row pointing at the same farm).
--   3. Defaults Type='Poultry' (matches migration 025 default). To convert
--      one of these farms to a Generic Company, run the follow-up snippet
--      at the bottom of this file (NOT auto-executed).
--
-- Safety:
--   * Idempotent — uses NOT EXISTS so re-running inserts nothing the second
--     time.
--   * Additive only — no existing rows are modified.
--   * No drops, no schema changes.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

DECLARE @inserted INT = 0;

-- 1. Backfill from AspNetUsers
;WITH OrphanUsers AS (
    SELECT u.Id           AS UserId,
           u.UserName     AS UserName,
           u.Email        AS Email,
           u.FarmId       AS FarmId
    FROM   dbo.AspNetUsers u
    WHERE  u.FarmId IS NOT NULL
       AND LTRIM(RTRIM(u.FarmId)) <> ''
       AND NOT EXISTS (SELECT 1 FROM dbo.Farms f WHERE f.FarmId = u.FarmId)
)
INSERT INTO dbo.Farms (Id, FarmId, Name, Email, Type, OwnerUserId, CreatedAt, DateCreated)
SELECT LOWER(CAST(NEWID() AS NVARCHAR(450))) AS Id,
       FarmId,
       LEFT(ISNULL(NULLIF(LTRIM(RTRIM(UserName)), ''), 'Farm ' + LEFT(FarmId, 8)), 100) AS Name,
       ISNULL(NULLIF(LTRIM(RTRIM(Email)), ''), 'unknown+' + LEFT(FarmId, 8) + '@placeholder.local') AS Email,
       'Poultry' AS Type,
       UserId,
       SYSUTCDATETIME(),
       SYSUTCDATETIME()
FROM   OrphanUsers;

SET @inserted = @@ROWCOUNT;
PRINT CONCAT('046: backfilled ', @inserted, ' Farms row(s) from AspNetUsers orphans.');

-- 2. Backfill from UserFarms (covers memberships without an AspNetUsers.FarmId
-- match). Uses the FIRST owning user we can find for Name, falls back to a
-- generic label.
;WITH OrphanUserFarms AS (
    SELECT DISTINCT uf.FarmId AS FarmId
    FROM   dbo.UserFarms uf
    WHERE  uf.FarmId IS NOT NULL
       AND LTRIM(RTRIM(uf.FarmId)) <> ''
       AND NOT EXISTS (SELECT 1 FROM dbo.Farms f WHERE f.FarmId = uf.FarmId)
)
INSERT INTO dbo.Farms (Id, FarmId, Name, Email, Type, OwnerUserId, CreatedAt, DateCreated)
SELECT LOWER(CAST(NEWID() AS NVARCHAR(450))) AS Id,
       o.FarmId,
       LEFT('Farm ' + LEFT(o.FarmId, 8), 100) AS Name,
       'unknown+' + LEFT(o.FarmId, 8) + '@placeholder.local' AS Email,
       'Poultry' AS Type,
       (SELECT TOP 1 uf2.UserId FROM dbo.UserFarms uf2 WHERE uf2.FarmId = o.FarmId ORDER BY uf2.UserId) AS OwnerUserId,
       SYSUTCDATETIME(),
       SYSUTCDATETIME()
FROM   OrphanUserFarms o;

SET @inserted = @@ROWCOUNT;
PRINT CONCAT('046: backfilled ', @inserted, ' Farms row(s) from UserFarms orphans.');

-- 3. Verification
DECLARE @remainingUsers   INT = (SELECT COUNT(*) FROM dbo.AspNetUsers u
                                  WHERE u.FarmId IS NOT NULL AND LTRIM(RTRIM(u.FarmId)) <> ''
                                    AND NOT EXISTS (SELECT 1 FROM dbo.Farms f WHERE f.FarmId = u.FarmId));
DECLARE @remainingMembers INT = (SELECT COUNT(*) FROM dbo.UserFarms uf
                                  WHERE NOT EXISTS (SELECT 1 FROM dbo.Farms f WHERE f.FarmId = uf.FarmId));

PRINT CONCAT('046: remaining orphan AspNetUsers.FarmId: ', @remainingUsers);
PRINT CONCAT('046: remaining orphan UserFarms.FarmId:   ', @remainingMembers);

GO

PRINT '046_BackfillOrphanFarmIds.sql complete.';
GO

-- =============================================================================
-- Optional follow-up: convert a specific backfilled farm to a Generic Company.
-- Not auto-executed. Run only after the owner has gone through Generic Setup
-- in the UI (or knows they want this farm to be Generic).
--
--   UPDATE dbo.Farms
--   SET    Type      = 'Generic',
--          UpdatedAt = SYSUTCDATETIME()
--   WHERE  FarmId = '<farm-id-here>';
--
-- Then call spGenericCompany_Setup to seed the profile + default lookups.
-- =============================================================================

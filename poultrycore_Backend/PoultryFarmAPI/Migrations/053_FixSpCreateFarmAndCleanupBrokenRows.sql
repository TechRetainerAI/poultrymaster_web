-- =============================================================================
-- Migration 053: Fix sp_CreateFarm column-mix-up + clean up broken Farms rows
-- =============================================================================
-- Root cause of the orphan-FarmId bug we've been firefighting since the start
-- of this session:
--
--   The original sp_CreateFarm (in the Login API's database tooling) was:
--     INSERT INTO Farms (Id, Name, Email, PhoneNumber, Type)
--     VALUES (@FarmId, @Name, @Email, @PhoneNumber, @Type);
--
--   It puts the *FarmId GUID* into the wrong column — Farms.Id (which is the
--   EF identity column) — and leaves Farms.FarmId (the business key the rest
--   of the platform looks up by) to its DEFAULT value of '0'. So:
--     * AspNetUsers.FarmId        = '<GUID>'  ← correct, set during signup
--     * Farms.Id                  = '<GUID>'  ← in the wrong column
--     * Farms.FarmId              = '0'       ← falls back to the default
--
--   Every farmId-scoped endpoint then does:
--     SELECT Type FROM Farms WHERE FarmId = '<GUID>'   -- finds 0 rows → 404
--
--   Migration 046 backfilled orphan AspNetUsers.FarmId references by inserting
--   NEW Farms rows with the GUID in the right column. That fixed the symptom
--   for users who existed at the time, but didn't fix sp_CreateFarm — so every
--   new signup since then created another broken row. By 2026-05-24 there are
--   29 broken rows.
--
-- This migration:
--   1. Rebinds the misplaced rows: for each Farms row where Id looks like a
--      GUID, FarmId='0', AND an AspNetUsers.FarmId references that GUID,
--      swap the columns — FarmId := Id, Id := a fresh NEWID. This makes the
--      SP-created row the canonical one (it has the real Name + Type the user
--      picked at signup).
--   2. Removes the 046-created backfill rows that point to the same FarmIds
--      (they're now duplicates with worse data — Name=UserName, Type='Poultry'
--      regardless of what the user picked).
--   3. Replaces sp_CreateFarm with a version that populates BOTH columns
--      correctly so the next signup doesn't recreate the problem.
--
-- Safety:
--   * No uniqueness on Farms.FarmId so step 1 won't collide.
--   * Step 2 only deletes rows whose Name = the matching AspNetUsers.UserName
--     and Type='Poultry' (the 046 backfill fingerprint). The data referenced
--     by FarmId (WaterExpenses, GenericProducts, etc.) keeps resolving
--     because the SP row now has the right FarmId.
--   * Idempotent: re-running finds nothing to swap (no rows match the
--     misplaced-GUID pattern anymore) and CREATE OR ALTER is safe.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Capture the misplaced rows before we modify them (lets step 2 dedup safely)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#MisplacedFarms') IS NOT NULL DROP TABLE #MisplacedFarms;

SELECT  f.Id AS OldId,
        f.Id AS RealFarmId,        -- the value currently in Id is the real GUID
        f.Name,
        f.Type
INTO    #MisplacedFarms
FROM    dbo.Farms f
WHERE   f.FarmId = '0'
   AND  f.Id LIKE '________-____-____-____-____________'
   AND  EXISTS (
       SELECT 1 FROM dbo.AspNetUsers u WHERE u.FarmId = f.Id
   );

DECLARE @misplacedCount INT = @@ROWCOUNT;
PRINT CONCAT('053: identified ', @misplacedCount, ' misplaced Farms row(s) to fix.');

-- -----------------------------------------------------------------------------
-- 2. Swap columns on each misplaced row: FarmId := Id, Id := a fresh NEWID
-- -----------------------------------------------------------------------------
UPDATE  f
SET     f.FarmId    = m.RealFarmId,
        f.Id        = LOWER(CAST(NEWID() AS NVARCHAR(450))),
        f.UpdatedAt = SYSUTCDATETIME()
FROM    dbo.Farms f
INNER   JOIN #MisplacedFarms m ON m.OldId = f.Id
WHERE   f.FarmId = '0';   -- belt + braces, don't touch anything we didn't intend

PRINT CONCAT('053: rebound ', @@ROWCOUNT, ' Farms row(s) (FarmId := Id, Id := NEWID()).');

-- -----------------------------------------------------------------------------
-- 3. Delete the migration-046 backfill duplicates
-- -----------------------------------------------------------------------------
-- 046 inserted rows with Type='Poultry' and Name=AspNetUsers.UserName (or
-- 'Farm <prefix>') for any orphan AspNetUsers.FarmId. The SP-created row we
-- just fixed has the real Name + the user-picked Type, so the 046 row is
-- now strictly worse data and a duplicate. Drop it.
DELETE  bf
FROM    dbo.Farms bf
INNER   JOIN #MisplacedFarms m ON m.RealFarmId = bf.FarmId
WHERE   bf.Type = 'Poultry'
   AND  bf.Id <> (SELECT TOP 1 f.Id FROM dbo.Farms f WHERE f.FarmId = m.RealFarmId AND f.Name = m.Name)
   AND  bf.Name IN (
       SELECT u.UserName FROM dbo.AspNetUsers u WHERE u.FarmId = m.RealFarmId
   );

PRINT CONCAT('053: deleted ', @@ROWCOUNT, ' duplicate 046-backfill row(s).');

DROP TABLE #MisplacedFarms;
GO

-- -----------------------------------------------------------------------------
-- 4. Fix sp_CreateFarm so future signups land in the correct columns.
-- -----------------------------------------------------------------------------
-- Both columns are NOT NULL on dbo.Farms. The original SP relied on the
-- DEFAULT '0' on FarmId to satisfy the constraint, which is exactly what
-- created the orphan situation.
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

    -- Two columns to populate:
    --   Id      — EF Identity (was being misused as a FarmId carrier; now gets a fresh GUID)
    --   FarmId  — the business key every farmId-scoped endpoint looks up by
    INSERT INTO dbo.Farms (Id, FarmId, Name, Email, PhoneNumber, Type, CreatedAt, DateCreated)
    VALUES (
        LOWER(CAST(NEWID() AS NVARCHAR(450))),    -- Id
        @FarmId,                                  -- FarmId (was the bug)
        @Name,
        @Email,
        @PhoneNumber,
        @Type,
        SYSUTCDATETIME(),
        SYSUTCDATETIME()
    );

    -- Return the row so the Login API can verify rows-affected > 0 instead of
    -- relying on "no exception thrown" as a success signal.
    SELECT Id, FarmId, Name, Email, PhoneNumber, Type, CreatedAt
    FROM   dbo.Farms
    WHERE  FarmId = @FarmId
       AND Name   = @Name
       AND Email  = @Email;
END
GO

-- Grant EXECUTE to the Login API runtime user. Idempotent.
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.sp_CreateFarm TO [Techretainer];
    PRINT '053: granted EXECUTE on dbo.sp_CreateFarm to Techretainer.';
END
GO

-- -----------------------------------------------------------------------------
-- 5. Verification
-- -----------------------------------------------------------------------------
DECLARE @remainingMisplaced INT = (
    SELECT COUNT(*) FROM dbo.Farms f
    WHERE f.FarmId = '0' AND f.Id LIKE '________-____-____-____-____________'
      AND EXISTS (SELECT 1 FROM dbo.AspNetUsers u WHERE u.FarmId = f.Id)
);
DECLARE @remainingOrphanUsers INT = (
    SELECT COUNT(*) FROM dbo.AspNetUsers u
    WHERE u.FarmId IS NOT NULL AND LTRIM(RTRIM(u.FarmId)) <> ''
      AND NOT EXISTS (SELECT 1 FROM dbo.Farms f WHERE f.FarmId = u.FarmId)
);

PRINT CONCAT('053: remaining misplaced (Id has GUID, FarmId=''0''): ', @remainingMisplaced);
PRINT CONCAT('053: remaining AspNetUsers orphans:                 ', @remainingOrphanUsers);
GO

PRINT '053_FixSpCreateFarmAndCleanupBrokenRows.sql complete.';
GO

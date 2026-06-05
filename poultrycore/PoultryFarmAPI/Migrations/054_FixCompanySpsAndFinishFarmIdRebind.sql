-- =============================================================================
-- Migration 054: spCompany_* family — join + WHERE on Farms.FarmId
-- =============================================================================
-- Migration 053 fixed sp_CreateFarm (Login API signup path) and rebound 24
-- Farms rows so that FarmId — not Id — is the business key. But the
-- Login API's spCompany_* family still treats Farms.Id as the company
-- identifier (see "@FarmId maps to Farms.Id" comment in the original
-- spCompany_Create). After 053 finished swapping columns, every farm
-- *except* the 5 that 053 couldn't match to AspNetUsers became invisible
-- to /Companies/mine (Profowusu sees only Tech Retainer instead of all
-- three of their memberships) and to the company switcher in the UI.
--
-- This migration:
--   1. Rebinds the 5 remaining Farms rows where Id is still a GUID and
--      FarmId='0' (053 missed them because no AspNetUsers.FarmId pointed
--      at them — admin-created or pre-multi-company-era farms).
--   2. CREATE OR ALTERs spCompany_GetByUserId, _GetById, _Create, _Update
--      so they all use FarmId as the business key.
--   3. Cleans up the bbffc4a1 duplicate (one row from the 053 dedup gap
--      where the original SP-created row's Name didn't match the
--      AspNetUsers.UserName the 046 backfill keyed on).
--
-- Side-effect: UserFarms.FarmId stays pointing at the same GUIDs through
-- the swap (the GUID just moves from f.Id to f.FarmId), so the correct
-- join (uf.FarmId = f.FarmId) now resolves every membership. Verified
-- before this migration: 36/41 memberships already resolved via FarmId,
-- 5 only via the buggy Id join — after step 1 below, all 41 resolve via
-- FarmId.
--
-- Idempotent. Run after 053. No risk to data referenced by FarmId from
-- the W4–W7 finance tables (they key on FarmId which doesn't change).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Rebind the 5 remaining Farms rows where Id has the GUID and FarmId='0'.
--    Same swap as 053 but without the "must match an AspNetUsers" gate so we
--    catch the admin-created rows too.
-- -----------------------------------------------------------------------------
DECLARE @rebound INT;

;WITH MisplacedFarms AS (
    SELECT f.Id AS OldId
    FROM   dbo.Farms f
    WHERE  f.FarmId = '0'
       AND f.Id LIKE '________-____-____-____-____________'
)
UPDATE  f
SET     f.FarmId    = f.Id,
        f.Id        = LOWER(CAST(NEWID() AS NVARCHAR(450))),
        f.UpdatedAt = SYSUTCDATETIME()
FROM    dbo.Farms f
INNER   JOIN MisplacedFarms m ON m.OldId = f.Id
WHERE   f.FarmId = '0';

SET @rebound = @@ROWCOUNT;
PRINT CONCAT('054: rebound ', @rebound, ' remaining Farms row(s) (FarmId := Id, Id := NEWID()).');

-- -----------------------------------------------------------------------------
-- 2. Clean up duplicates that the 053 dedup didn't catch — pick the one with
--    the real signup name (Profowusu user's bbffc4a1 has duplicates: a
--    backfill "Profowusu" row and the original "Fiifi Farm" row).
-- -----------------------------------------------------------------------------
;WITH RankedFarms AS (
    SELECT f.Id, f.FarmId, f.Name, f.Type, f.CreatedAt,
           -- Keep the SIGNUP row when available (matches a Generic/Water Type
           -- and was created earliest — sp_CreateFarm's first call wins).
           -- Falls back to "the one not named after the username" so we keep
           -- the real farm name over the 046 backfill placeholder.
           ROW_NUMBER() OVER (
             PARTITION BY f.FarmId
             ORDER BY  CASE WHEN f.Type IN ('Generic', 'Water') THEN 0 ELSE 1 END,
                       CASE WHEN f.Name IN (SELECT u.UserName FROM dbo.AspNetUsers u WHERE u.FarmId = f.FarmId) THEN 1 ELSE 0 END,
                       f.CreatedAt
           ) AS rnk
    FROM   dbo.Farms f
    WHERE  EXISTS (
       SELECT 1 FROM dbo.Farms f2 WHERE f2.FarmId = f.FarmId GROUP BY f2.FarmId HAVING COUNT(*) > 1
    )
)
DELETE FROM dbo.Farms
WHERE Id IN (SELECT Id FROM RankedFarms WHERE rnk > 1);

PRINT CONCAT('054: deleted ', @@ROWCOUNT, ' duplicate Farms row(s).');

-- -----------------------------------------------------------------------------
-- 3. Fix spCompany_GetByUserId — used by /Companies/mine, drives the company
--    switcher dropdown. Join on FarmId, return FarmId.
-- -----------------------------------------------------------------------------
GO
CREATE OR ALTER PROCEDURE dbo.spCompany_GetByUserId
    @UserId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    -- Bug fix (2026-05-24): old version did `uf.FarmId = f.Id` which broke
    -- after migration 053 stopped storing the FarmId GUID in f.Id.
    SELECT f.FarmId, f.Name, f.Type, f.OwnerUserId, f.Email, f.PhoneNumber,
           f.CreatedAt, f.UpdatedAt, uf.Role
    FROM   dbo.Farms f
    INNER JOIN dbo.UserFarms uf ON uf.FarmId = f.FarmId
    WHERE  uf.UserId = @UserId
    ORDER  BY f.Name;
END
GO

-- -----------------------------------------------------------------------------
-- 4. Fix spCompany_GetById — used by /Companies/{id} GET endpoint.
-- -----------------------------------------------------------------------------
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
    WHERE  f.FarmId = @FarmId AND uf.UserId = @UserId;
END
GO

-- -----------------------------------------------------------------------------
-- 5. Fix spCompany_Create — POST /Companies (creating an additional company
--    for a logged-in user). Has to insert into BOTH columns now: a fresh
--    Id, and the caller-supplied FarmId in the FarmId column. Also makes the
--    UserFarms link by the same FarmId.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spCompany_Create
    @FarmId       NVARCHAR(450),
    @Name         NVARCHAR(255),
    @Type         NVARCHAR(50),
    @OwnerUserId  NVARCHAR(450),
    @Email        NVARCHAR(255) = NULL,
    @PhoneNumber  NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @safeEmail NVARCHAR(255) = ISNULL(@Email, '');

    BEGIN TRANSACTION;

    INSERT INTO dbo.Farms (Id, FarmId, Name, Email, PhoneNumber, Type, OwnerUserId, CreatedAt, DateCreated)
    VALUES (
        LOWER(CAST(NEWID() AS NVARCHAR(450))),    -- Id (EF identity)
        @FarmId,                                  -- FarmId (business key)
        @Name, @safeEmail, @PhoneNumber, @Type, @OwnerUserId,
        SYSUTCDATETIME(), SYSUTCDATETIME()
    );

    IF NOT EXISTS (SELECT 1 FROM dbo.UserFarms WHERE UserId = @OwnerUserId AND FarmId = @FarmId)
        INSERT INTO dbo.UserFarms (UserId, FarmId, Role)
        VALUES (@OwnerUserId, @FarmId, 'Admin');

    COMMIT TRANSACTION;

    -- Return the row so the C# layer can verify rows-affected > 0 (same
    -- pattern as sp_CreateFarm post-053).
    SELECT f.FarmId, f.Name, f.Type, f.OwnerUserId, f.Email, f.PhoneNumber,
           f.CreatedAt, f.UpdatedAt, 'Admin' AS Role
    FROM   dbo.Farms f
    WHERE  f.FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- 6. Fix spCompany_Update — PUT /Companies/{id}.
-- -----------------------------------------------------------------------------
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
           Email       = ISNULL(@Email, Email),
           PhoneNumber = @PhoneNumber,
           UpdatedAt   = SYSUTCDATETIME()
    WHERE  FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- 7. Grants
-- -----------------------------------------------------------------------------
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spCompany_GetByUserId TO [Techretainer];
    GRANT EXECUTE ON dbo.spCompany_GetById     TO [Techretainer];
    GRANT EXECUTE ON dbo.spCompany_Create      TO [Techretainer];
    GRANT EXECUTE ON dbo.spCompany_Update      TO [Techretainer];
    PRINT '054: granted EXECUTE on spCompany_* to Techretainer.';
END
GO

-- -----------------------------------------------------------------------------
-- 8. Verification
-- -----------------------------------------------------------------------------
DECLARE @misplaced INT = (SELECT COUNT(*) FROM dbo.Farms WHERE FarmId = '0' AND Id LIKE '________-____-____-____-____________');
DECLARE @byIdWorks INT = (SELECT COUNT(*) FROM dbo.UserFarms uf INNER JOIN dbo.Farms f ON f.Id = uf.FarmId);
DECLARE @byFarmIdWorks INT = (SELECT COUNT(*) FROM dbo.UserFarms uf INNER JOIN dbo.Farms f ON f.FarmId = uf.FarmId);
DECLARE @dupFarmIds INT = (SELECT COUNT(*) FROM (SELECT FarmId FROM dbo.Farms GROUP BY FarmId HAVING COUNT(*) > 1) d);

PRINT CONCAT('054: remaining_misplaced (FarmId=0 with GUID-shaped Id): ', @misplaced);
PRINT CONCAT('054: memberships_resolving_via_buggy_Id_join:           ', @byIdWorks);
PRINT CONCAT('054: memberships_resolving_via_correct_FarmId_join:     ', @byFarmIdWorks);
PRINT CONCAT('054: duplicate_FarmIds:                                 ', @dupFarmIds);
GO

PRINT '054_FixCompanySpsAndFinishFarmIdRebind.sql complete.';
GO

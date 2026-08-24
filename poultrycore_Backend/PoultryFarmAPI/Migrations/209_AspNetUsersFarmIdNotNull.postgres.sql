-- 209 — Restore the NOT NULL / DEFAULT '' contract on aspnetusers.farmid,
--        recovering each row's real farm where one can still be proven.
--
-- NOTE: this migration was applied to the live database on 2026-08-20 but the
-- file was never committed. Restored here so a database rebuilt from the
-- migration set matches production, and so migration 210 -- which references
-- 209 by number in its header -- is not describing a step that does not exist.
-- Re-running is a no-op.
--
-- WHY
-- ApplicationUser.FarmId is a non-nullable CLR string (Models/ApplicationUser.cs),
-- and the SQL Server schema matched it:
--     FarmId NVARCHAR(450) NOT NULL CONSTRAINT DF_AspNetUsers_FarmId DEFAULT (N'')
-- The PostgreSQL port dropped the NOT NULL and the default, and left a bogus `0`
-- default on a varchar column. Seven rows subsequently held NULL.
--
-- Any EF query that materialized one of those rows -- e.g. the email-exists and
-- org-code-taken lookups in UserManagement.CreateUserWithTokenAsync -- threw
-- "Column 'farmid' is null." from Npgsql, which signup surfaced to the user as
-- "An unexpected error occurred". Registration could not complete at all.
--
-- BACKFILL STRATEGY
-- Blanking every NULL to '' would fix the crash but silently unlink users who
-- still have a provable farm. So recover in order of evidence strength, and fall
-- back to '' only when nothing survives:
--   1. userfarms      — the authoritative membership table. Earliest row wins;
--                       that is the farm the user was first attached to.
--   2. iamuserroles   — IAM role grants are farm-scoped and outlived the port for
--                       some staff whose userfarms rows did not.
--   3. ''             — no evidence anywhere. Matches what the app itself writes
--                       for a user with no company (CreateUserWithTokenAsync:
--                       farmId = hasCompany ? Guid... : string.Empty).
--
-- Only farmids that still exist in `farms` are accepted, so this cannot recreate
-- the orphan-FarmId problem migration 046 cleaned up.
--
-- Idempotent: re-running is a no-op once farmid is NOT NULL.

BEGIN;

-- 1. Recover from userfarms (earliest membership).
UPDATE aspnetusers u
SET farmid = src.farmid
FROM (
    SELECT DISTINCT ON (uf.userid) uf.userid, uf.farmid
    FROM userfarms uf
    JOIN farms f ON f.farmid = uf.farmid
    ORDER BY uf.userid, uf.createdat, uf.farmid
) src
WHERE u.id = src.userid
  AND u.farmid IS NULL;

-- 2. Recover from farm-scoped IAM role grants.
UPDATE aspnetusers u
SET farmid = src.farmid
FROM (
    SELECT DISTINCT ON (ur.userid) ur.userid, ur.farmid
    FROM iamuserroles ur
    JOIN farms f ON f.farmid = ur.farmid
    WHERE ur.farmid IS NOT NULL
    ORDER BY ur.userid, ur.farmid
) src
WHERE u.id = src.userid
  AND u.farmid IS NULL;

-- 3. Nothing left to recover — use the app's own "no company" sentinel.
UPDATE aspnetusers SET farmid = '' WHERE farmid IS NULL;

-- 4. Replace the meaningless `0` default with the '' the CLR model assumes.
ALTER TABLE aspnetusers ALTER COLUMN farmid DROP DEFAULT;
ALTER TABLE aspnetusers ALTER COLUMN farmid SET DEFAULT '';

-- 5. Re-establish the invariant so this cannot recur.
ALTER TABLE aspnetusers ALTER COLUMN farmid SET NOT NULL;

COMMIT;

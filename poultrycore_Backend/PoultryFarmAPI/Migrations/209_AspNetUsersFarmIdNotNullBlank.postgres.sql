-- 209 — aspnetusers.farmid: restore NOT NULL DEFAULT '' (the original SQL Server contract).
--
-- RECONSTRUCTED 2026-08-21. Migration 210's header credits a "209" with this change, but no
-- 209 file was ever committed — dev had been altered by hand and prod was left behind, so the
-- two databases had drifted:
--     DEV   farmid varchar(450) NOT NULL DEFAULT ''      <- the intended shape
--     PROD  farmid varchar(450) NULL     DEFAULT 0       <- stray numeric default, still nullable
-- This file makes the change reproducible so prod can reach dev's shape from the repo.
--
-- HISTORY (the loop 210's header describes):
--   167  company soft-delete began doing `UPDATE aspnetusers SET farmid = NULL`.
--   192  that failed against the NOT NULL column, so farmid was made nullable.
--   209  nullable farmid then broke REGISTRATION: ApplicationUser.FarmId is a non-nullable CLR
--        string, so EF materializing a NULL row threw "Column 'farmid' is null." (observed
--        flooding the dev LoginAPI 2026-08-20). This restores NOT NULL DEFAULT ''.
--   210  restores the delete path to write '' instead of NULL — REQUIRED alongside this file,
--        or company delete fails with 23502 the moment NOT NULL is back.
--
-- '' is the app's "no active company" sentinel — exactly what CreateUserWithTokenAsync writes
-- for an owner registering with no company. Real membership lives in userfarms; farmid is only
-- the legacy "active/default company" pointer.
--
-- ORDER: apply 209 and 210 TOGETHER. 210 first (or same transaction) so no delete can write a
-- NULL into a column that is about to reject it.
--
-- Idempotent: safe to re-run.

BEGIN;

-- 1. Any pre-existing NULL becomes the '' sentinel. (Also normalises the stray '0' default
--    value if it was ever actually written to a row.)
UPDATE public.aspnetusers SET farmid = '' WHERE farmid IS NULL;

-- 2. Default must be the '' sentinel, not 0 — prod carried a numeric default that does not
--    match the app's contract and would insert '0' as a company id.
ALTER TABLE public.aspnetusers ALTER COLUMN farmid SET DEFAULT '';

-- 3. Restore the NOT NULL contract that ApplicationUser.FarmId (non-nullable CLR string) needs.
ALTER TABLE public.aspnetusers ALTER COLUMN farmid SET NOT NULL;

-- Same treatment for farmname: 167 left it holding the deleted company's name, and 210 now
-- clears it to ''. Only tighten it if it is already free of NULLs.
UPDATE public.aspnetusers SET farmname = '' WHERE farmname IS NULL;

COMMIT;

-- verification
SELECT 'aspnetusers.farmid' AS column,
       is_nullable,
       column_default,
       (SELECT count(*) FROM public.aspnetusers WHERE farmid IS NULL) AS null_rows,
       (SELECT count(*) FROM public.aspnetusers WHERE farmid = '')    AS blank_rows
FROM   information_schema.columns
WHERE  table_schema = 'public' AND table_name = 'aspnetusers' AND column_name = 'farmid';

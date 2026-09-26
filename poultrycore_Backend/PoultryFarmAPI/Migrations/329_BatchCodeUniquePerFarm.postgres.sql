-- =============================================================================
-- 329_BatchCodeUniquePerFarm.postgres.sql
--
-- Purpose
-- -------
-- Make a batch code unique WITHIN A COMPANY instead of across the whole
-- database.
--
-- WHAT HAPPENS TODAY
-- ==================
-- public.mainflockbatch carries
--
--     CREATE UNIQUE INDEX uq__mainfloc__b22ada8e7de1efe9 ON mainflockbatch (batchcode)
--
-- on batchcode ALONE. The name is the giveaway: that is SQL Server's
-- auto-generated constraint name, carried over verbatim by the Postgres port.
-- Nothing chose it deliberately.
--
-- The effect is a cross-tenant collision. One company naming a batch "B1"
-- permanently prevents every other company in the database from using "B1".
-- Twelve farms currently hold 32 batches with 32 distinct codes -- not because
-- they agreed on a numbering scheme, but because this index has been quietly
-- refusing the duplicates all along.
--
-- It surfaced through Initial Farm Setup, which validates duplicate codes
-- correctly -- per farm, as it should -- so the row passes validation and then
-- fails at the insert with
--
--     23505: duplicate key value violates unique constraint
--            "uq__mainfloc__b22ada8e7de1efe9"
--
-- naming a row belonging to a company the user cannot see and has no way to
-- rename. There is no action the user can take to resolve it.
--
-- WHY lower() AND COLLAPSED WHITESPACE
-- ====================================
-- So the index agrees with the validator rather than merely overlapping with
-- it. FarmSetupValidator.DuplicateKey is
--
--     Whitespace.Replace(raw.Trim(), " ").ToLowerInvariant()
--
-- If the index were on the raw column, "B1" and "b1" would be one batch to the
-- validator and two to the database: the validator would reject a legitimate
-- rename while the database happily stored the pair. A backstop that disagrees
-- with the gate it is backing is worse than no backstop, because the
-- disagreement only shows up as a 23505 nobody can act on -- which is exactly
-- the failure this migration exists to remove.
--
-- farmid is lowered for the same reason poultryfarmsetup and
-- poultryfarmsetupdraft lower it: a farm id differing only in case is the same
-- company.
--
-- Both functions are IMMUTABLE, so the expression is indexable.
--
-- REJECTED: keeping the global index and having the wizard suggest a free code.
-- That treats another company's data as a constraint on this one's naming, and
-- the suggestion would have to be recomputed against rows the caller is not
-- permitted to read.
--
-- Idempotent. Safe to run more than once.
-- EFFECT ON TODAY'S NUMBERS: none. No row changes; this only widens what is
-- permitted. Every existing code already satisfies the new index.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Refuse to proceed if the data would not survive the new index.
--
--    Globally distinct codes do NOT imply this is safe: "B1" and "b1" are
--    distinct raw strings and could already sit in one farm, and they collapse
--    to the same key here. Check rather than assume.
-- -----------------------------------------------------------------------------
DO $pre$
DECLARE
    v_clash text;
BEGIN
    SELECT string_agg(format('farm %s code %L (%s rows)', farmid, sample, n), '; ')
    INTO   v_clash
    FROM (
        SELECT lower(farmid) AS farmid,
               min(batchcode) AS sample,
               count(*) AS n
        FROM   public.mainflockbatch
        GROUP  BY lower(farmid),
                  lower(regexp_replace(btrim(batchcode), '\s+', ' ', 'g'))
        HAVING count(*) > 1
    ) d;

    IF v_clash IS NOT NULL THEN
        RAISE EXCEPTION
            '329: cannot scope batch codes per farm -- these already collide under the new key: %',
            v_clash;
    END IF;
END
$pre$;

-- -----------------------------------------------------------------------------
-- 2. Add the per-farm index BEFORE dropping the global one, so the table is
--    never briefly unprotected.
-- -----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS ux_mainflockbatch_farm_batchcode
    ON public.mainflockbatch (
        lower(farmid),
        lower(regexp_replace(btrim(batchcode), '\s+', ' ', 'g'))
    );

COMMENT ON INDEX public.ux_mainflockbatch_farm_batchcode IS
    'A batch code identifies a batch within ONE company. Normalised to match '
    'FarmSetupValidator.DuplicateKey (trim, collapse whitespace, lowercase) so '
    'the validator and the database agree on what a duplicate is. Replaced the '
    'global index on batchcode alone in migration 329.';

-- -----------------------------------------------------------------------------
-- 3. Drop the carried-over global index.
--
--    It may be an INDEX or a CONSTRAINT depending on how the port landed, and
--    the auto-generated name is not guaranteed to be identical on every
--    database -- so find it by shape rather than hardcoding the name.
-- -----------------------------------------------------------------------------
DO $drop$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT i.relname AS idxname,
               con.conname AS conname
        FROM   pg_index idx
        JOIN   pg_class i  ON i.oid = idx.indexrelid
        JOIN   pg_class t  ON t.oid = idx.indrelid
        JOIN   pg_namespace n ON n.oid = t.relnamespace
        LEFT   JOIN pg_constraint con
               ON con.conindid = idx.indexrelid AND con.contype IN ('u', 'p')
        WHERE  n.nspname = 'public'
          AND  t.relname = 'mainflockbatch'
          AND  idx.indisunique
          AND  NOT idx.indisprimary
          AND  idx.indnatts = 1
          -- the single indexed attribute is the plain batchcode column
          AND  idx.indkey[0] = (SELECT a.attnum FROM pg_attribute a
                                WHERE a.attrelid = t.oid AND a.attname = 'batchcode')
    LOOP
        IF r.conname IS NOT NULL THEN
            EXECUTE format('ALTER TABLE public.mainflockbatch DROP CONSTRAINT %I', r.conname);
            RAISE NOTICE '329: dropped global unique constraint %', r.conname;
        ELSE
            EXECUTE format('DROP INDEX public.%I', r.idxname);
            RAISE NOTICE '329: dropped global unique index %', r.idxname;
        END IF;
    END LOOP;
END
$drop$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 4. Verification. Runs after COMMIT so a failure here does not undo the
--    migration -- it tells you the migration is wrong, which is different.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_farm_a text := '__329_selftest_a__';
    v_farm_b text := '__329_selftest_b__';
    v_ok     boolean;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class WHERE relname = 'ux_mainflockbatch_farm_batchcode')
    THEN
        RAISE EXCEPTION '329: the per-farm index was not created.';
    END IF;

    -- The global index must be gone, or nothing has actually changed.
    IF EXISTS (
        SELECT 1
        FROM   pg_index idx
        JOIN   pg_class i ON i.oid = idx.indexrelid
        JOIN   pg_class t ON t.oid = idx.indrelid
        WHERE  t.relname = 'mainflockbatch'
          AND  idx.indisunique AND NOT idx.indisprimary AND idx.indnatts = 1
          AND  idx.indkey[0] = (SELECT a.attnum FROM pg_attribute a
                                WHERE a.attrelid = t.oid AND a.attname = 'batchcode'))
    THEN
        RAISE EXCEPTION '329: the global unique index on batchcode is still present.';
    END IF;

    -- Two companies may now use the same code. This is the whole point.
    INSERT INTO public.mainflockbatch (userid, farmid, batchcode, batchname, breed,
                                       numberofbirds, startdate, status)
    VALUES ('__329__', v_farm_a, 'B1', 'selftest a', 'x', 1, now(), 'Active'),
           ('__329__', v_farm_b, 'B1', 'selftest b', 'x', 1, now(), 'Active');

    -- ...but one company may not use it twice, in any casing.
    BEGIN
        INSERT INTO public.mainflockbatch (userid, farmid, batchcode, batchname, breed,
                                           numberofbirds, startdate, status)
        VALUES ('__329__', v_farm_a, '  b1 ', 'selftest dup', 'x', 1, now(), 'Active');
        v_ok := false;
    EXCEPTION WHEN unique_violation THEN
        v_ok := true;
    END;

    DELETE FROM public.mainflockbatch WHERE userid = '__329__';

    IF NOT v_ok THEN
        RAISE EXCEPTION
            '329: a farm was allowed two batches whose codes differ only by case or spacing.';
    END IF;

    RAISE NOTICE '329_BatchCodeUniquePerFarm: batch codes are now unique per company, verified.';
END $$;

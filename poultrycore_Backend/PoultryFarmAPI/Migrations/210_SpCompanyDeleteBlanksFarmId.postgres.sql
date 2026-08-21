-- 210 — Company soft-delete must blank aspnetusers.farmid, not NULL it.
--
-- HISTORY (this closes a loop that has flipped twice):
--   167  company soft-delete began doing `UPDATE aspnetusers SET farmid = NULL`
--        to move a member off the company they were sitting in.
--   192  that failed against the original NOT NULL column, so farmid was made
--        nullable to let the delete through.
--   209  nullable farmid then broke REGISTRATION: ApplicationUser.FarmId is a
--        non-nullable CLR string, so EF materializing a NULL row threw
--        "Column 'farmid' is null." and signup died. 209 restored NOT NULL
--        DEFAULT '' (the original SQL Server contract) and backfilled.
--   210  which brought 167's delete back as 23502. Fixed here at the real
--        source: the delete writes '' instead of NULL.
--
-- '' is already the app's "no active company" sentinel — it is exactly what
-- CreateUserWithTokenAsync writes for an owner who registers with no company —
-- so the app's own routing to the Business Office is unchanged. Having NULL and
-- '' both mean "no company" was the underlying inconsistency; everything now
-- uses ''. Real membership lives in userfarms regardless; farmid is only the
-- legacy "active/default company" pointer.
--
-- Also clears farmname, which 167 left holding the deleted company's name — the
-- account would otherwise keep a stale company name in its profile and its
-- "FarmName" JWT claim while pointing at no company at all.
--
-- Idempotent: CREATE OR REPLACE, signature unchanged.

CREATE OR REPLACE FUNCTION public.spcompany_delete(p_farmid text, p_userid text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM farms f
                   WHERE f.farmid = p_farmid AND f.owneruserid = p_userid AND f.isdeleted = FALSE) THEN
        RETURN 0;   -- not owner / not found / already gone
    END IF;

    UPDATE farms f
    SET    isdeleted = TRUE, updatedat = (now() at time zone 'utc')
    WHERE  f.farmid = p_farmid;

    -- Unlink every member so it drops off everyone's company list.
    DELETE FROM userfarms uf WHERE uf.farmid = p_farmid;

    -- Anyone currently "sitting in" the deleted company gets a neutral active
    -- company; the app then routes them to the Business Office. '' (not NULL) —
    -- see the header note.
    UPDATE aspnetusers u
    SET    farmid = '', farmname = ''
    WHERE  u.farmid = p_farmid;

    RETURN 1;
END;
$function$;

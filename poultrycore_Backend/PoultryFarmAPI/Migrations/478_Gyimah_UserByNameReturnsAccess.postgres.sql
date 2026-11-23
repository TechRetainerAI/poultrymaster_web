-- 478: The profile lookup returns the user's access too.
--
-- sp_getuserbyname (Login API, GET UserProfile/findByUserName) returned only
-- name, email and password columns. The web app calls it on every page load
-- to refresh the signed-in user's permissions, got isStaff=false and
-- featurePermissions=null back, and wiped the permissions login had stored.
-- Every staff member was then treated as staff with nothing ticked: Customer
-- Payments said "You do not have permission", and the menu hid what they had
-- been given.
--
-- The function now also returns isstaff, isadmin, farmid, farmname, admintitle,
-- permissions, featurepermissions and customerid. UserProfileDAL.MapReaderToUser
-- already reads these when present, so the Login API needs no code change.
-- The return type changes, so the function is dropped first. Safe to re-run.

BEGIN;

DROP FUNCTION IF EXISTS public.sp_getuserbyname(text);

CREATE FUNCTION public.sp_getuserbyname(p_normalizedusername text)
 RETURNS TABLE(id text, username text, normalizedusername text, email text, passwordhash text,
               firstname text, lastname text, phonenumber text, issubscriber boolean,
               isstaff boolean, isadmin boolean, farmid text, farmname text, admintitle text,
               permissions text, featurepermissions text, customerid text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        u.id::text,
        u.username::text,
        u.normalizedusername::text,
        u.email::text,
        u.passwordhash::text,
        u.firstname::text,
        u.lastname::text,
        u.phonenumber::text,
        u.issubscriber,
        COALESCE(u.isstaff, false),
        COALESCE(u.isadmin, false),
        u.farmid::text,
        u.farmname::text,
        u.admintitle::text,
        u.permissions,
        u.featurepermissions,
        u.customerid::text
    FROM aspnetusers u
    WHERE u.normalizedusername = p_normalizedusername;
END;
$function$;

COMMIT;

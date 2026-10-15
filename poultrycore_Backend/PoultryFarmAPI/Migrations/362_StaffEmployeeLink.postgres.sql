-- =============================================================================
-- 362_StaffEmployeeLink.postgres.sql
--
-- Purpose
-- -------
-- Let one person be BOTH an Employee (a login: aspnetusers, Employees page)
-- and a Staff member (a payroll record: the company type's staff table,
-- Staff page), and show them on both pages.
--
--   Employee -> staff   The Employees page opens the Staff page's New staff
--                       form prefilled from the login; the saved staff row is
--                       linked to it.
--   Staff -> employee   The Staff page opens Add Employee prefilled from the
--                       staff row; the new login is linked back to it.
--
-- THE LINK
-- --------
-- A nullable staff.userid -> aspnetusers.id, one column per staff table.
-- hotelstaff already has it (238: its create makes a login from the email);
-- this adds it to poultrystaff, waterstaff, genericstaff and restaurantstaff.
-- No FK: aspnetusers belongs to the Login API, and an employee deleted there
-- must not cascade into payroll history. Readers join aspnetusers, so a link
-- to a deleted login simply stops showing.
--
-- One login is at most one live staff row per company (partial unique index;
-- a soft-deleted staff row frees the login to be linked again).
--
-- The link is set through spstaff_linkuser only. The staff tables' own
-- insert / update SPs are untouched (their live bodies are not in the repo),
-- so editing a staff row never clears it.
--
-- WHICH TABLE
-- -----------
-- Picked from farms.type for the company. Staff farmid is not consistently
-- farms.id or farms.farmid across company types, so the farm is matched on
-- either.
-- =============================================================================

BEGIN;

ALTER TABLE public.poultrystaff    ADD COLUMN IF NOT EXISTS userid varchar(450) NULL;
ALTER TABLE public.waterstaff      ADD COLUMN IF NOT EXISTS userid varchar(450) NULL;
ALTER TABLE public.genericstaff    ADD COLUMN IF NOT EXISTS userid varchar(450) NULL;
ALTER TABLE public.restaurantstaff ADD COLUMN IF NOT EXISTS userid varchar(450) NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrystaff_userid
    ON public.poultrystaff (farmid, userid) WHERE userid IS NOT NULL AND NOT isdeleted;
CREATE UNIQUE INDEX IF NOT EXISTS ux_waterstaff_userid
    ON public.waterstaff (farmid, userid) WHERE userid IS NOT NULL AND NOT isdeleted;
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericstaff_userid
    ON public.genericstaff (farmid, userid) WHERE userid IS NOT NULL AND NOT isdeleted;
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantstaff_userid
    ON public.restaurantstaff (farmid, userid) WHERE userid IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelstaff_userid
    ON public.hotelstaff (farmid, userid) WHERE userid IS NOT NULL;


-- -----------------------------------------------------------------------------
-- fnstaff_table: the company's staff table, its id column and whether it soft
-- deletes. NULL table = the company type has no staff table.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnstaff_table(p_farmid text)
RETURNS TABLE (tablename text, idcolumn text, softdelete boolean)
LANGUAGE sql STABLE AS $$
    SELECT t.tablename, t.idcolumn, t.softdelete
      FROM (SELECT f.type
              FROM public.farms f
             WHERE f.id = p_farmid OR f.farmid = p_farmid
             ORDER BY (f.id = p_farmid) DESC
             LIMIT 1) ft
      JOIN (VALUES ('Poultry',    'poultrystaff',    'poultrystaffid',    true),
                   ('Water',      'waterstaff',      'waterstaffid',      true),
                   ('Generic',    'genericstaff',    'genericstaffid',    true),
                   ('Hotel',      'hotelstaff',      'hotelstaffid',      false),
                   ('Restaurant', 'restaurantstaff', 'restaurantstaffid', false))
           AS t(type, tablename, idcolumn, softdelete)
        ON t.type = ft.type
$$;


-- -----------------------------------------------------------------------------
-- fnstaff_userlinks: every live staff row of the company that is linked to an
-- existing login. Both pages read this to badge the other side.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnstaff_userlinks(p_farmid text)
RETURNS TABLE (staffid integer, userid text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_t record;
BEGIN
    SELECT * INTO v_t FROM public.fnstaff_table(p_farmid);
    IF v_t.tablename IS NULL THEN RETURN; END IF;

    RETURN QUERY EXECUTE format(
        'SELECT s.%1$I, s.userid::text
           FROM public.%2$I s
           JOIN public.aspnetusers u ON u.id = s.userid
          WHERE s.farmid = $1 AND s.userid IS NOT NULL %3$s',
        v_t.idcolumn, v_t.tablename,
        CASE WHEN v_t.softdelete THEN 'AND NOT s.isdeleted' ELSE '' END)
    USING p_farmid;
END;
$$;


-- -----------------------------------------------------------------------------
-- spstaff_linkuser: link a staff row to a login (p_userid NULL = unlink).
-- The login must be an employee of this company and not already linked to
-- another live staff row here.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spstaff_linkuser(p_farmid text, p_staffid integer, p_userid text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_t     record;
    v_live  text;
    v_other integer;
    v_n     integer;
BEGIN
    SELECT * INTO v_t FROM public.fnstaff_table(p_farmid);
    IF v_t.tablename IS NULL THEN
        RAISE EXCEPTION 'This company type has no staff records.' USING ERRCODE = 'P0001';
    END IF;
    v_live := CASE WHEN v_t.softdelete THEN 'AND NOT isdeleted' ELSE '' END;

    IF p_userid IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.aspnetusers u
             WHERE u.id = p_userid AND u.isstaff
               AND (u.farmid = p_farmid
                    OR EXISTS (SELECT 1 FROM public.userfarms uf
                                WHERE uf.userid = u.id AND uf.farmid = p_farmid))
        ) THEN
            RAISE EXCEPTION 'That employee does not belong to this company.' USING ERRCODE = 'P0001';
        END IF;

        EXECUTE format('SELECT %1$I FROM public.%2$I WHERE farmid = $1 AND userid = $2 AND %1$I <> $3 %3$s LIMIT 1',
                       v_t.idcolumn, v_t.tablename, v_live)
           INTO v_other USING p_farmid, p_userid, p_staffid;
        IF v_other IS NOT NULL THEN
            RAISE EXCEPTION 'That employee is already linked to another staff member.' USING ERRCODE = 'P0001';
        END IF;
    END IF;

    EXECUTE format('UPDATE public.%2$I SET userid = $3 WHERE farmid = $1 AND %1$I = $2 %3$s',
                   v_t.idcolumn, v_t.tablename, v_live)
       USING p_farmid, p_staffid, p_userid;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n = 0 THEN
        RAISE EXCEPTION 'Staff member not found.' USING ERRCODE = 'P0002';
    END IF;
END;
$$;

COMMIT;

-- 500: Projects & Contracts -- the project TEAM.
--
-- Which staff work on which project. A staff member can be on several projects
-- at once. The team is a plain list: it posts nothing, moves no money and
-- changes no total. It exists so pages about PEOPLE (Employee Credit, Employee
-- Loans & Advances) can be narrowed to "the staff working on this project".
--
-- 1. genericprojectteam -- one row per (project, staff). Removing someone keeps
--    the row with isactive = FALSE, so the record of who was on it stays.
-- 2. spgenericproject_team(farm, project)           -> the members
--    spgenericproject_saveteam(farm, project, members, by) -> replace-all
--    spgenericproject_teamofstaff(farm)              -> staff -> their projects
--
-- Nothing here touches a Poultry, Water, Hotel, Restaurant or Livestock table.

BEGIN;

CREATE TABLE IF NOT EXISTS genericprojectteam (
    genericprojectteamid serial PRIMARY KEY,
    farmid            text          NOT NULL,
    genericprojectid  integer       NOT NULL REFERENCES genericprojects (genericprojectid),
    genericstaffid    integer       NOT NULL REFERENCES genericstaff (genericstaffid),
    role              text          NULL,
    startdate         date          NULL,
    enddate           date          NULL,
    isactive          boolean       NOT NULL DEFAULT TRUE,
    createdby         text          NULL,
    createdat         timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby         text          NULL,
    updatedat         timestamp     NULL,
    CHECK (enddate IS NULL OR startdate IS NULL OR enddate >= startdate)
);
-- One row per (project, staff): re-adding someone reactivates their row.
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericprojectteam_member
    ON genericprojectteam (genericprojectid, genericstaffid);
CREATE INDEX IF NOT EXISTS ix_genericprojectteam_staff
    ON genericprojectteam (farmid, genericstaffid) WHERE isactive;

CREATE OR REPLACE FUNCTION public.spgenericproject_team(p_farmid text, p_projectid integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
BEGIN
    PERFORM fngenericproject_require(p_farmid, p_projectid);
    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'staffId', t.genericstaffid,
            'name', btrim(concat_ws(' ', s.firstname, s.lastname)),
            'role', t.role, 'startDate', t.startdate, 'endDate', t.enddate)
            ORDER BY btrim(concat_ws(' ', s.firstname, s.lastname)), t.genericstaffid)
        FROM genericprojectteam t
        JOIN genericstaff s ON s.genericstaffid = t.genericstaffid
        WHERE t.genericprojectid = p_projectid AND t.farmid = p_farmid AND t.isactive), '[]'::jsonb);
END
$f$;

-- p_members: [{staffId, role?, startDate?, endDate?}]. Replace-all: anyone not
-- in the list is made inactive. Returns the saved team.
CREATE OR REPLACE FUNCTION public.spgenericproject_saveteam(
    p_farmid text, p_projectid integer, p_members jsonb, p_by text)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    m       jsonb;
    v_staff integer;
    v_ids   integer[] := '{}';
BEGIN
    PERFORM fngenericproject_assertenabled(p_farmid);
    PERFORM fngenericproject_require(p_farmid, p_projectid);
    IF p_members IS NULL OR jsonb_typeof(p_members) <> 'array' THEN
        RAISE EXCEPTION 'The team must be a list of staff.' USING ERRCODE = 'P0001';
    END IF;

    FOR m IN SELECT * FROM jsonb_array_elements(p_members) LOOP
        v_staff := NULLIF(m->>'staffId', '')::int;
        IF v_staff IS NULL THEN
            RAISE EXCEPTION 'Each team member needs a staff member.' USING ERRCODE = 'P0001';
        END IF;
        IF v_staff = ANY (v_ids) THEN
            RAISE EXCEPTION 'A staff member is listed twice.' USING ERRCODE = 'P0001';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM genericstaff WHERE farmid = p_farmid AND genericstaffid = v_staff) THEN
            RAISE EXCEPTION 'That staff member was not found in this company.' USING ERRCODE = 'P0001';
        END IF;
        IF NULLIF(m->>'startDate', '') IS NOT NULL AND NULLIF(m->>'endDate', '') IS NOT NULL
           AND (m->>'endDate')::date < (m->>'startDate')::date THEN
            RAISE EXCEPTION 'A team member cannot leave before they join.' USING ERRCODE = 'P0001';
        END IF;
        v_ids := v_ids || v_staff;

        INSERT INTO genericprojectteam (farmid, genericprojectid, genericstaffid, role, startdate, enddate, isactive, createdby)
        VALUES (p_farmid, p_projectid, v_staff, NULLIF(btrim(m->>'role'), ''),
                NULLIF(m->>'startDate', '')::date, NULLIF(m->>'endDate', '')::date, TRUE, p_by)
        ON CONFLICT (genericprojectid, genericstaffid) DO UPDATE SET
            role = EXCLUDED.role, startdate = EXCLUDED.startdate, enddate = EXCLUDED.enddate,
            isactive = TRUE, updatedby = p_by, updatedat = (now() at time zone 'utc');
    END LOOP;

    UPDATE genericprojectteam SET isactive = FALSE, updatedby = p_by, updatedat = (now() at time zone 'utc')
     WHERE genericprojectid = p_projectid AND farmid = p_farmid AND isactive
       AND NOT (genericstaffid = ANY (v_ids));

    RETURN spgenericproject_team(p_farmid, p_projectid);
END
$f$;

-- For the people pages' filter: every staff member on at least one active
-- team, with their projects. Archived projects are left out.
CREATE OR REPLACE FUNCTION public.spgenericproject_teamofstaff(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('staffId', x.genericstaffid, 'projects', x.projects)), '[]'::jsonb)
    FROM (
        SELECT t.genericstaffid,
               jsonb_agg(jsonb_build_object('projectId', p.genericprojectid,
                                            'label', p.projectnumber || ' — ' || p.name)
                         ORDER BY p.projectnumber) AS projects
        FROM genericprojectteam t
        JOIN genericprojects p ON p.genericprojectid = t.genericprojectid
        WHERE t.farmid = p_farmid AND t.isactive AND p.status <> 'Archived'
        GROUP BY t.genericstaffid
    ) x;
$f$;

COMMIT;

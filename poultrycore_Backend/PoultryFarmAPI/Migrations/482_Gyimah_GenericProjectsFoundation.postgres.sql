-- 482: Projects & Contracts for Generic companies -- foundation.
--
-- Projects & Contracts is an optional module inside the Generic company type.
-- It is NOT a company type and NOT a second set of books: a project is a label
-- that existing Generic transactions can be attributed to (see 483). One
-- company, many projects, shared transactions, separate visibility.
--
-- This migration:
-- 1. genericmodulesettings.enableprojects -- the company-level switch. Off by
--    default. Turning it off hides the module and refuses NEW project
--    attribution; it never deletes a project or unlinks a transaction.
--    spgenericmodulesettings_get/_upsert are rebuilt with the extra column.
--    The upsert's new parameter defaults to NULL = "keep what is stored", so
--    every existing caller (incl. spgenericbusinesstemplate_apply) leaves the
--    switch alone.
-- 2. genericprojects -- the register. One table for Projects and Contracts
--    (kind). Only a name is required; everything else is added later.
--    Internal number PRJ-0001... is given automatically (advisory lock); the
--    external / government contract number is a separate optional field.
-- 3. genericprojectstatushistory -- every status the project has had.
-- 4. Functions (jsonb, camelCase, refusals ERRCODE P0001 in plain English):
--    spgenericproject_save, _get, _list, _setstatus, _archive, _options,
--    fngenericproject_assertenabled, fngenericproject_require.
-- 5. IAM catalog keys generic.projects.*, generic.project-financials.*,
--    generic.project-budgets.*, generic.project-milestones.*,
--    generic.project-allocations.*, generic.project-reservations.*.
--    Granted to the roles/users that hold the nearest existing Generic key.
--
-- Nothing here reads or writes a Poultry, Water, Hotel, Restaurant or
-- Livestock table.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Module switch
-- ---------------------------------------------------------------------------
ALTER TABLE genericmodulesettings
    ADD COLUMN IF NOT EXISTS enableprojects boolean NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN genericmodulesettings.enableprojects IS
    '482: Projects & Contracts module. Off = hidden, history kept, no new project attribution.';

DROP FUNCTION IF EXISTS public.spgenericmodulesettings_get(text);
CREATE FUNCTION public.spgenericmodulesettings_get(p_farmid text)
RETURNS TABLE(
    farmid                  text,
    enableproducts          boolean,
    enableinventory         boolean,
    enablestockadjustments  boolean,
    enableinternaluse       boolean,
    enablepurchases         boolean,
    enablesubscriptions     boolean,
    enableinvoices          boolean,
    enablecustomerbalances  boolean,
    enablestaffpayments     boolean,
    enablecashaccounts      boolean,
    enablerecurringexpenses boolean,
    enablesupplierbalances  boolean,
    enableprojects          boolean
)
LANGUAGE sql STABLE
AS $function$
    SELECT s.farmid::text, s.enableproducts, s.enableinventory, s.enablestockadjustments,
           s.enableinternaluse, s.enablepurchases, s.enablesubscriptions, s.enableinvoices,
           s.enablecustomerbalances, s.enablestaffpayments, s.enablecashaccounts,
           s.enablerecurringexpenses, s.enablesupplierbalances, s.enableprojects
    FROM   genericmodulesettings s
    WHERE  s.farmid = p_farmid
    UNION ALL
    SELECT p_farmid, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, TRUE, TRUE,
           TRUE, TRUE, FALSE
    WHERE  NOT EXISTS (SELECT 1 FROM genericmodulesettings s2 WHERE s2.farmid = p_farmid)
    LIMIT  1;
$function$;

DROP FUNCTION IF EXISTS public.spgenericmodulesettings_upsert(
    text, boolean, boolean, boolean, boolean, boolean, boolean, boolean, boolean,
    boolean, boolean, boolean, boolean);
CREATE FUNCTION public.spgenericmodulesettings_upsert(
    p_farmid                  text,
    p_enableproducts          boolean,
    p_enableinventory         boolean,
    p_enablestockadjustments  boolean,
    p_enableinternaluse       boolean,
    p_enablepurchases         boolean,
    p_enablesubscriptions     boolean,
    p_enableinvoices          boolean,
    p_enablecustomerbalances  boolean,
    p_enablestaffpayments     boolean,
    p_enablecashaccounts      boolean,
    p_enablerecurringexpenses boolean DEFAULT TRUE,
    p_enablesupplierbalances  boolean DEFAULT TRUE,
    -- 482: NULL = keep the stored value (or FALSE for a new row), so callers
    -- that predate the Projects module never switch it on or off.
    p_enableprojects          boolean DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO genericmodulesettings (
        farmid, enableproducts, enableinventory, enablestockadjustments,
        enableinternaluse, enablepurchases, enablesubscriptions, enableinvoices,
        enablecustomerbalances, enablestaffpayments, enablecashaccounts,
        enablerecurringexpenses, enablesupplierbalances, enableprojects, updatedat)
    VALUES (
        p_farmid, p_enableproducts, p_enableinventory, p_enablestockadjustments,
        p_enableinternaluse, p_enablepurchases, p_enablesubscriptions, p_enableinvoices,
        p_enablecustomerbalances, p_enablestaffpayments, p_enablecashaccounts,
        COALESCE(p_enablerecurringexpenses, TRUE), COALESCE(p_enablesupplierbalances, TRUE),
        COALESCE(p_enableprojects, FALSE),
        (now() at time zone 'utc'))
    ON CONFLICT (farmid) DO UPDATE
    SET enableproducts          = EXCLUDED.enableproducts,
        enableinventory         = EXCLUDED.enableinventory,
        enablestockadjustments  = EXCLUDED.enablestockadjustments,
        enableinternaluse       = EXCLUDED.enableinternaluse,
        enablepurchases         = EXCLUDED.enablepurchases,
        enablesubscriptions     = EXCLUDED.enablesubscriptions,
        enableinvoices          = EXCLUDED.enableinvoices,
        enablecustomerbalances  = EXCLUDED.enablecustomerbalances,
        enablestaffpayments     = EXCLUDED.enablestaffpayments,
        enablecashaccounts      = EXCLUDED.enablecashaccounts,
        enablerecurringexpenses = EXCLUDED.enablerecurringexpenses,
        enablesupplierbalances  = EXCLUDED.enablesupplierbalances,
        enableprojects          = COALESCE(p_enableprojects, genericmodulesettings.enableprojects),
        updatedat               = EXCLUDED.updatedat;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Register
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericprojects (
    genericprojectid          serial PRIMARY KEY,
    farmid                    text          NOT NULL,
    projectnumber             text          NOT NULL,          -- PRJ-0001, internal
    name                      text          NOT NULL,
    kind                      text          NOT NULL DEFAULT 'Project'
                                            CHECK (kind IN ('Project', 'Contract')),
    status                    text          NOT NULL DEFAULT 'Active'
                                            CHECK (status IN ('Draft', 'Planned', 'Active', 'OnHold',
                                                              'Completed', 'Cancelled', 'Archived')),
    genericcustomerid         integer       NULL,
    description               text          NULL,
    startdate                 date          NULL,
    expectedenddate           date          NULL,
    actualenddate             date          NULL,
    managerstaffid            integer       NULL,               -- genericstaff
    notes                     text          NULL,
    -- Contract information
    externalcontractnumber    text          NULL,               -- e.g. the government's number
    contractreference         text          NULL,
    contractingorganization   text          NULL,
    awarddate                 date          NULL,
    awardvalue                numeric(18,2) NULL CHECK (awardvalue IS NULL OR awardvalue >= 0),
    -- Financial planning (plans, never posted anywhere)
    approvedbudget            numeric(18,2) NULL CHECK (approvedbudget IS NULL OR approvedbudget >= 0),
    estimateddirectcost       numeric(18,2) NULL CHECK (estimateddirectcost IS NULL OR estimateddirectcost >= 0),
    estimatedoverhead         numeric(18,2) NULL CHECK (estimatedoverhead IS NULL OR estimatedoverhead >= 0),
    workingcapitalneeded      numeric(18,2) NULL CHECK (workingcapitalneeded IS NULL OR workingcapitalneeded >= 0),
    -- Optional organisation
    category                  text          NULL,
    location                  text          NULL,
    statusbeforearchive       text          NULL,
    createdby                 text          NULL,
    createdat                 timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby                 text          NULL,
    updatedat                 timestamp     NULL,
    archivedat                timestamp     NULL,
    archivedby                text          NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_genericprojects_number
    ON genericprojects (farmid, lower(projectnumber));
CREATE INDEX IF NOT EXISTS ix_genericprojects_farm_status
    ON genericprojects (farmid, status);
CREATE INDEX IF NOT EXISTS ix_genericprojects_farm_customer
    ON genericprojects (farmid, genericcustomerid) WHERE genericcustomerid IS NOT NULL;

CREATE TABLE IF NOT EXISTS genericprojectstatushistory (
    genericprojectstatushistoryid serial PRIMARY KEY,
    farmid           text      NOT NULL,
    genericprojectid integer   NOT NULL REFERENCES genericprojects (genericprojectid),
    fromstatus       text      NULL,
    tostatus         text      NOT NULL,
    note             text      NULL,
    changedby        text      NULL,
    changedat        timestamp NOT NULL DEFAULT (now() at time zone 'utc')
);
CREATE INDEX IF NOT EXISTS ix_genericprojectstatushistory_project
    ON genericprojectstatushistory (genericprojectid, changedat);

-- ---------------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fngenericproject_enabled(p_farmid text)
 RETURNS boolean LANGUAGE sql STABLE AS $f$
    SELECT COALESCE((SELECT enableprojects FROM genericmodulesettings WHERE farmid = p_farmid), FALSE);
$f$;

CREATE OR REPLACE FUNCTION public.fngenericproject_assertenabled(p_farmid text)
 RETURNS void LANGUAGE plpgsql STABLE AS $f$
BEGIN
    IF NOT fngenericproject_enabled(p_farmid) THEN
        RAISE EXCEPTION 'Projects & Contracts is switched off for this company. Turn it on in Business Features to use it.'
            USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- The project must exist and belong to this company. Never trust an id sent
-- from the browser without this.
CREATE OR REPLACE FUNCTION public.fngenericproject_require(p_farmid text, p_projectid integer)
 RETURNS genericprojects LANGUAGE plpgsql STABLE AS $f$
DECLARE r genericprojects;
BEGIN
    SELECT * INTO r FROM genericprojects WHERE genericprojectid = p_projectid AND farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That project or contract was not found in this company.' USING ERRCODE = 'P0001';
    END IF;
    RETURN r;
END
$f$;

CREATE OR REPLACE FUNCTION public.fngenericproject_nextnumber(p_farmid text)
 RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v_n integer;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('genericproject_number:' || p_farmid));
    SELECT COALESCE(MAX(NULLIF(substring(projectnumber FROM '^PRJ-(\d+)$'), '')::int), 0) + 1
      INTO v_n FROM genericprojects WHERE farmid = p_farmid;
    RETURN 'PRJ-' || lpad(v_n::text, 4, '0');
END
$f$;

CREATE OR REPLACE FUNCTION public.fngenericproject_json(p genericprojects)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'projectId', p.genericprojectid,
        'projectNumber', p.projectnumber,
        'name', p.name,
        'label', p.projectnumber || ' — ' || p.name,
        'kind', p.kind,
        'status', p.status,
        'customerId', p.genericcustomerid,
        'customerName', (SELECT c.customername FROM genericcustomers c
                         WHERE c.farmid = p.farmid AND c.genericcustomerid = p.genericcustomerid),
        'description', p.description,
        'startDate', p.startdate,
        'expectedEndDate', p.expectedenddate,
        'actualEndDate', p.actualenddate,
        'managerStaffId', p.managerstaffid,
        'managerName', (SELECT btrim(concat_ws(' ', s.firstname, s.lastname)) FROM genericstaff s
                        WHERE s.farmid = p.farmid AND s.genericstaffid = p.managerstaffid),
        'notes', p.notes,
        'externalContractNumber', p.externalcontractnumber,
        'contractReference', p.contractreference,
        'contractingOrganization', p.contractingorganization,
        'awardDate', p.awarddate,
        'awardValue', p.awardvalue,
        'approvedBudget', p.approvedbudget,
        'estimatedDirectCost', p.estimateddirectcost,
        'estimatedOverhead', p.estimatedoverhead,
        'expectedProfit', CASE WHEN p.awardvalue IS NULL THEN NULL
                               ELSE p.awardvalue - COALESCE(p.estimateddirectcost, 0) - COALESCE(p.estimatedoverhead, 0) END,
        'expectedMarginPercent', CASE WHEN COALESCE(p.awardvalue, 0) = 0 THEN NULL
                               ELSE round((p.awardvalue - COALESCE(p.estimateddirectcost, 0) - COALESCE(p.estimatedoverhead, 0))
                                          * 100 / p.awardvalue, 1) END,
        'workingCapitalNeeded', p.workingcapitalneeded,
        'category', p.category,
        'location', p.location,
        'createdBy', p.createdby,
        'createdAt', p.createdat,
        'updatedAt', p.updatedat,
        'archivedAt', p.archivedat);
$f$;

-- ---------------------------------------------------------------------------
-- 4. Save / get / list / status / archive / options
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericproject_save(p_farmid text, p_project jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id       integer := NULLIF(p_project->>'projectId', '')::int;
    v_name     text    := btrim(COALESCE(p_project->>'name', ''));
    v_kind     text    := COALESCE(NULLIF(btrim(p_project->>'kind'), ''), 'Project');
    v_status   text    := NULLIF(btrim(p_project->>'status'), '');
    v_customer integer := NULLIF(p_project->>'customerId', '')::int;
    v_manager  integer := NULLIF(p_project->>'managerStaffId', '')::int;
    v_ext      text    := NULLIF(btrim(p_project->>'externalContractNumber'), '');
    v_start    date    := NULLIF(p_project->>'startDate', '')::date;
    v_expend   date    := NULLIF(p_project->>'expectedEndDate', '')::date;
    v_actend   date    := NULLIF(p_project->>'actualEndDate', '')::date;
    v_old      genericprojects;
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Give the project or contract a name.' USING ERRCODE = 'P0001';
    END IF;
    IF v_kind NOT IN ('Project', 'Contract') THEN
        RAISE EXCEPTION 'Choose Project or Contract.' USING ERRCODE = 'P0001';
    END IF;
    IF v_status IS NOT NULL AND v_status NOT IN ('Draft', 'Planned', 'Active', 'OnHold', 'Completed', 'Cancelled') THEN
        RAISE EXCEPTION 'That status is not one of Draft, Planned, Active, On hold, Completed or Cancelled.' USING ERRCODE = 'P0001';
    END IF;
    IF v_customer IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM genericcustomers WHERE farmid = p_farmid AND genericcustomerid = v_customer) THEN
        RAISE EXCEPTION 'That customer was not found in this company.' USING ERRCODE = 'P0001';
    END IF;
    IF v_manager IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM genericstaff WHERE farmid = p_farmid AND genericstaffid = v_manager) THEN
        RAISE EXCEPTION 'That staff member was not found in this company.' USING ERRCODE = 'P0001';
    END IF;
    IF v_start IS NOT NULL AND v_expend IS NOT NULL AND v_expend < v_start THEN
        RAISE EXCEPTION 'The expected completion date is before the start date.' USING ERRCODE = 'P0001';
    END IF;
    IF v_start IS NOT NULL AND v_actend IS NOT NULL AND v_actend < v_start THEN
        RAISE EXCEPTION 'The actual completion date is before the start date.' USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE((p_project->>'awardValue')::numeric, 0) < 0
       OR COALESCE((p_project->>'approvedBudget')::numeric, 0) < 0
       OR COALESCE((p_project->>'estimatedDirectCost')::numeric, 0) < 0
       OR COALESCE((p_project->>'estimatedOverhead')::numeric, 0) < 0
       OR COALESCE((p_project->>'workingCapitalNeeded')::numeric, 0) < 0 THEN
        RAISE EXCEPTION 'Amounts cannot be negative.' USING ERRCODE = 'P0001';
    END IF;
    IF v_ext IS NOT NULL AND EXISTS (
        SELECT 1 FROM genericprojects WHERE farmid = p_farmid
          AND lower(externalcontractnumber) = lower(v_ext) AND genericprojectid IS DISTINCT FROM v_id) THEN
        RAISE EXCEPTION 'Another project already uses contract number "%".', v_ext USING ERRCODE = 'P0001';
    END IF;

    IF v_id IS NULL THEN
        PERFORM fngenericproject_assertenabled(p_farmid);
        INSERT INTO genericprojects (
            farmid, projectnumber, name, kind, status, genericcustomerid, description,
            startdate, expectedenddate, actualenddate, managerstaffid, notes,
            externalcontractnumber, contractreference, contractingorganization, awarddate, awardvalue,
            approvedbudget, estimateddirectcost, estimatedoverhead, workingcapitalneeded,
            category, location, createdby)
        VALUES (
            p_farmid, fngenericproject_nextnumber(p_farmid), v_name, v_kind, COALESCE(v_status, 'Active'),
            v_customer, NULLIF(btrim(p_project->>'description'), ''),
            v_start, v_expend, v_actend, v_manager, NULLIF(btrim(p_project->>'notes'), ''),
            v_ext, NULLIF(btrim(p_project->>'contractReference'), ''),
            NULLIF(btrim(p_project->>'contractingOrganization'), ''),
            NULLIF(p_project->>'awardDate', '')::date, NULLIF(p_project->>'awardValue', '')::numeric,
            NULLIF(p_project->>'approvedBudget', '')::numeric, NULLIF(p_project->>'estimatedDirectCost', '')::numeric,
            NULLIF(p_project->>'estimatedOverhead', '')::numeric, NULLIF(p_project->>'workingCapitalNeeded', '')::numeric,
            NULLIF(btrim(p_project->>'category'), ''), NULLIF(btrim(p_project->>'location'), ''), p_by)
        RETURNING genericprojectid INTO v_id;

        INSERT INTO genericprojectstatushistory (farmid, genericprojectid, fromstatus, tostatus, note, changedby)
        VALUES (p_farmid, v_id, NULL, COALESCE(v_status, 'Active'), 'Created', p_by);
    ELSE
        v_old := fngenericproject_require(p_farmid, v_id);
        IF v_old.status = 'Archived' THEN
            RAISE EXCEPTION 'This project is archived. Restore it before editing.' USING ERRCODE = 'P0001';
        END IF;
        UPDATE genericprojects SET
            name = v_name, kind = v_kind, genericcustomerid = v_customer,
            description = NULLIF(btrim(p_project->>'description'), ''),
            startdate = v_start, expectedenddate = v_expend, actualenddate = v_actend,
            managerstaffid = v_manager, notes = NULLIF(btrim(p_project->>'notes'), ''),
            externalcontractnumber = v_ext,
            contractreference = NULLIF(btrim(p_project->>'contractReference'), ''),
            contractingorganization = NULLIF(btrim(p_project->>'contractingOrganization'), ''),
            awarddate = NULLIF(p_project->>'awardDate', '')::date,
            awardvalue = NULLIF(p_project->>'awardValue', '')::numeric,
            approvedbudget = NULLIF(p_project->>'approvedBudget', '')::numeric,
            estimateddirectcost = NULLIF(p_project->>'estimatedDirectCost', '')::numeric,
            estimatedoverhead = NULLIF(p_project->>'estimatedOverhead', '')::numeric,
            workingcapitalneeded = NULLIF(p_project->>'workingCapitalNeeded', '')::numeric,
            category = NULLIF(btrim(p_project->>'category'), ''),
            location = NULLIF(btrim(p_project->>'location'), ''),
            updatedby = p_by, updatedat = (now() at time zone 'utc')
        WHERE genericprojectid = v_id AND farmid = p_farmid;

        IF v_status IS NOT NULL AND v_status <> v_old.status THEN
            PERFORM spgenericproject_setstatus(p_farmid, v_id, v_status, NULL, p_by);
        END IF;
    END IF;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.spgenericproject_setstatus(
    p_farmid text, p_projectid integer, p_status text, p_note text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_old genericprojects;
BEGIN
    v_old := fngenericproject_require(p_farmid, p_projectid);
    IF p_status NOT IN ('Draft', 'Planned', 'Active', 'OnHold', 'Completed', 'Cancelled') THEN
        RAISE EXCEPTION 'That status is not one of Draft, Planned, Active, On hold, Completed or Cancelled.' USING ERRCODE = 'P0001';
    END IF;
    IF v_old.status = 'Archived' THEN
        RAISE EXCEPTION 'This project is archived. Restore it before changing its status.' USING ERRCODE = 'P0001';
    END IF;
    IF v_old.status = p_status THEN RETURN; END IF;

    UPDATE genericprojects SET status = p_status,
           actualenddate = CASE WHEN p_status = 'Completed' AND actualenddate IS NULL
                                THEN (now() at time zone 'utc')::date ELSE actualenddate END,
           updatedby = p_by, updatedat = (now() at time zone 'utc')
    WHERE genericprojectid = p_projectid AND farmid = p_farmid;

    INSERT INTO genericprojectstatushistory (farmid, genericprojectid, fromstatus, tostatus, note, changedby)
    VALUES (p_farmid, p_projectid, v_old.status, p_status, NULLIF(btrim(p_note), ''), p_by);
END
$f$;

-- Archive hides a project from pickers and the default list. Nothing linked to
-- it changes; restore puts back the status it had.
CREATE OR REPLACE FUNCTION public.spgenericproject_archive(
    p_farmid text, p_projectid integer, p_archive boolean, p_note text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_old genericprojects; v_to text;
BEGIN
    v_old := fngenericproject_require(p_farmid, p_projectid);
    IF p_archive THEN
        IF v_old.status = 'Archived' THEN RETURN; END IF;
        v_to := 'Archived';
        UPDATE genericprojects SET status = 'Archived', statusbeforearchive = v_old.status,
               archivedat = (now() at time zone 'utc'), archivedby = p_by,
               updatedby = p_by, updatedat = (now() at time zone 'utc')
        WHERE genericprojectid = p_projectid AND farmid = p_farmid;
    ELSE
        IF v_old.status <> 'Archived' THEN RETURN; END IF;
        v_to := COALESCE(v_old.statusbeforearchive, 'Completed');
        UPDATE genericprojects SET status = v_to, statusbeforearchive = NULL,
               archivedat = NULL, archivedby = NULL,
               updatedby = p_by, updatedat = (now() at time zone 'utc')
        WHERE genericprojectid = p_projectid AND farmid = p_farmid;
    END IF;
    INSERT INTO genericprojectstatushistory (farmid, genericprojectid, fromstatus, tostatus, note, changedby)
    VALUES (p_farmid, p_projectid, v_old.status, v_to,
            COALESCE(NULLIF(btrim(p_note), ''), CASE WHEN p_archive THEN 'Archived' ELSE 'Restored' END), p_by);
END
$f$;

CREATE OR REPLACE FUNCTION public.spgenericproject_get(p_farmid text, p_projectid integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE r genericprojects;
BEGIN
    r := fngenericproject_require(p_farmid, p_projectid);
    RETURN fngenericproject_json(r) || jsonb_build_object(
        'statusHistory', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'fromStatus', h.fromstatus, 'toStatus', h.tostatus, 'note', h.note,
                       'changedBy', h.changedby, 'changedAt', h.changedat)
                   ORDER BY h.changedat DESC, h.genericprojectstatushistoryid DESC)
            FROM genericprojectstatushistory h WHERE h.genericprojectid = r.genericprojectid), '[]'::jsonb));
END
$f$;

-- p_filter: {search, status ("" = all but Archived, "All", or one status), kind,
--            customerId, page (1-based), pageSize (default 25, max 200)}
CREATE OR REPLACE FUNCTION public.spgenericproject_list(p_farmid text, p_filter jsonb)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE
    v_search   text    := NULLIF(btrim(COALESCE(p_filter->>'search', '')), '');
    v_status   text    := NULLIF(btrim(COALESCE(p_filter->>'status', '')), '');
    v_kind     text    := NULLIF(btrim(COALESCE(p_filter->>'kind', '')), '');
    v_customer integer := NULLIF(p_filter->>'customerId', '')::int;
    v_size     integer := LEAST(GREATEST(COALESCE(NULLIF(p_filter->>'pageSize', '')::int, 25), 1), 200);
    v_page     integer := GREATEST(COALESCE(NULLIF(p_filter->>'page', '')::int, 1), 1);
    v_total    integer;
    v_rows     jsonb;
BEGIN
    WITH f AS (
        SELECT p.* FROM genericprojects p
        WHERE p.farmid = p_farmid
          AND (v_status = 'All' OR (v_status IS NULL AND p.status <> 'Archived') OR p.status = v_status)
          AND (v_kind IS NULL OR p.kind = v_kind)
          AND (v_customer IS NULL OR p.genericcustomerid = v_customer)
          AND (v_search IS NULL OR p.name ILIKE '%' || v_search || '%'
               OR p.projectnumber ILIKE '%' || v_search || '%'
               OR p.externalcontractnumber ILIKE '%' || v_search || '%'
               OR p.contractingorganization ILIKE '%' || v_search || '%'
               OR p.category ILIKE '%' || v_search || '%')
    )
    SELECT (SELECT count(*) FROM f),
           COALESCE((SELECT jsonb_agg(fngenericproject_json(x) ORDER BY x.createdat DESC, x.genericprojectid DESC)
                     FROM (SELECT * FROM f ORDER BY createdat DESC, genericprojectid DESC
                           LIMIT v_size OFFSET (v_page - 1) * v_size) x), '[]'::jsonb)
      INTO v_total, v_rows;

    RETURN jsonb_build_object('items', v_rows, 'total', v_total, 'page', v_page, 'pageSize', v_size,
                              'enabled', fngenericproject_enabled(p_farmid));
END
$f$;

-- For pickers: projects a transaction may be attributed to. Draft, Planned,
-- Active and On hold by default; p_includeclosed adds Completed/Cancelled (for
-- report filters and historical linking). Archived never.
CREATE OR REPLACE FUNCTION public.spgenericproject_options(p_farmid text, p_includeclosed boolean)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'projectId', p.genericprojectid, 'projectNumber', p.projectnumber, 'name', p.name,
               'label', p.projectnumber || ' — ' || p.name, 'kind', p.kind, 'status', p.status,
               'customerId', p.genericcustomerid)
           ORDER BY p.projectnumber), '[]'::jsonb)
    FROM genericprojects p
    WHERE p.farmid = p_farmid AND p.status <> 'Archived'
      AND (COALESCE(p_includeclosed, FALSE) OR p.status IN ('Draft', 'Planned', 'Active', 'OnHold'));
$f$;

-- ---------------------------------------------------------------------------
-- 5. IAM catalog
-- ---------------------------------------------------------------------------
DO $iam$
DECLARE
    v_added_keys  integer := 0;
    v_added_roles integer := 0;
    v_added_users integer := 0;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '482: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'generic.' || k.resource || '.' || a.action, 'generic', k.resource, a.action,
           'Projects & Contracts', k.label, k.descr, 'Generic',
           a.action IN ('delete') OR (k.resource = 'project-allocations' AND a.action = 'edit'),
           k.sortorder
    FROM (VALUES
        ('projects', 'Projects & Contracts',
         'The project and contract register. Delete means archive; nothing is ever removed.', 200,
         ARRAY['view', 'create', 'edit', 'delete']),
        ('project-financials', 'Project Financials',
         'Each project''s P&L, cash flow, balances, comparison and transaction history.', 201,
         ARRAY['view', 'export']),
        ('project-budgets', 'Project Budgets', 'Setting and changing project budgets.', 202,
         ARRAY['view', 'create', 'edit', 'delete']),
        ('project-milestones', 'Project Milestones', 'Project milestones and progress.', 203,
         ARRAY['view', 'create', 'edit', 'delete']),
        ('project-allocations', 'Project Assignment',
         'Assigning transactions to projects (create), and changing or removing an assignment '
         || 'already made, including linking older transactions (edit).', 204,
         ARRAY['view', 'create', 'edit']),
        ('project-reservations', 'Project Stock Reservations',
         'Reserving company stock for a project, releasing it and moving it between projects.', 205,
         ARRAY['view', 'create'])
    ) AS k(resource, label, descr, sortorder, actions)
    CROSS JOIN LATERAL unnest(k.actions) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;
    GET DIAGNOSTICS v_added_keys = ROW_COUNT;

    -- Each new key goes to whoever holds its nearest existing Generic twin.
    CREATE TEMP TABLE _482_map (old_key text, new_key text) ON COMMIT DROP;
    INSERT INTO _482_map VALUES
        ('generic.reports.view',      'generic.projects.view'),
        ('generic.expenses.create',   'generic.projects.create'),
        ('generic.expenses.edit',     'generic.projects.edit'),
        ('generic.expenses.delete',   'generic.projects.delete'),
        ('generic.reports.view',      'generic.project-financials.view'),
        ('generic.reports.export',    'generic.project-financials.export'),
        ('generic.reports.view',      'generic.project-budgets.view'),
        ('generic.expenses.edit',     'generic.project-budgets.create'),
        ('generic.expenses.edit',     'generic.project-budgets.edit'),
        ('generic.expenses.delete',   'generic.project-budgets.delete'),
        ('generic.reports.view',      'generic.project-milestones.view'),
        ('generic.expenses.create',   'generic.project-milestones.create'),
        ('generic.expenses.edit',     'generic.project-milestones.edit'),
        ('generic.expenses.delete',   'generic.project-milestones.delete'),
        ('generic.expenses.view',     'generic.project-allocations.view'),
        ('generic.expenses.create',   'generic.project-allocations.create'),
        ('generic.expenses.approve',  'generic.project-allocations.edit'),
        ('generic.inventory.view',    'generic.project-reservations.view'),
        ('generic.inventory.edit',    'generic.project-reservations.create');

    IF to_regclass('public.iamrolepermissions') IS NOT NULL THEN
        INSERT INTO iamrolepermissions (roleid, permissionkey)
        SELECT DISTINCT rp.roleid, m.new_key
        FROM   iamrolepermissions rp JOIN _482_map m ON m.old_key = rp.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
        UNION
        SELECT r.roleid, p.permissionkey
        FROM   iamroles r CROSS JOIN iampermissions p
        WHERE  r.rolekey IN ('sys-owner', 'sys-company-admin', 'sys-org-admin')
          AND  p.module = 'generic' AND p.permissiongroup = 'Projects & Contracts'
        ON CONFLICT (roleid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_added_roles = ROW_COUNT;
    END IF;

    -- Farm-scoped and carrying an effect; copied verbatim so a Deny stays a Deny.
    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        INSERT INTO iamuserpermissions (userid, farmid, permissionkey, effect, reason, grantedby, grantedat)
        SELECT DISTINCT ON (up.userid, up.farmid, m.new_key)
               up.userid, up.farmid, m.new_key, up.effect,
               'Carried over from ' || up.permissionkey || ' by migration 482',
               up.grantedby, (now() at time zone 'utc')
        FROM   iamuserpermissions up
        JOIN   _482_map m ON m.old_key = up.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
          AND  (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
        ORDER BY up.userid, up.farmid, m.new_key, (up.effect = 'Deny') DESC
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_added_users = ROW_COUNT;
    END IF;

    RAISE NOTICE '482: % catalog key(s), % role grant(s), % user grant(s) added.',
        v_added_keys, v_added_roles, v_added_users;
END;
$iam$;

COMMIT;

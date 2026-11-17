-- 419: Payroll templates -- set the payroll up once, use it every period.
--
-- Until now every payroll run started empty and each staff line was typed in
-- again. A TEMPLATE holds the standard payroll: which staff, their basic pay,
-- daily wage, commission, bonus, fixed deductions and payment method, plus the
-- pay frequency and the cash account it is paid from.
--
--   poultrypayrolltemplates          one row per template (e.g. "Monthly staff")
--   poultrypayrolltemplatelines      one row per staff member on it
--   poultrypayrollruns.poultrypayrolltemplateid   which template a run came from
--
--   sppoultrypayrolltemplate_getall(farm, includeinactive)
--   sppoultrypayrolltemplate_getlines(farm, templateid)
--   sppoultrypayrolltemplate_save(farm, id|null, name, frequency, cashaccount, notes, lines jsonb, by)
--   sppoultrypayrolltemplate_setactive(farm, id, active, by)        archive / restore
--   sppoultrypayrolltemplate_createrun(farm, id, start, end, paydate, cashaccount, notes, by)
--
-- Editing a template changes FUTURE runs only: a run copies the lines when it is
-- created (through the existing sppoultrypayrollrun_insert / _item_upsert), so
-- a Draft run can still be adjusted for the month, and approved/paid runs never
-- change. Templates are archived, not deleted. Staff who are inactive or
-- removed are skipped when a run is created. A template cannot make two live
-- runs for overlapping periods.
--
-- Idempotent: IF NOT EXISTS / CREATE OR REPLACE.

CREATE TABLE IF NOT EXISTS public.poultrypayrolltemplates (
    poultrypayrolltemplateid serial PRIMARY KEY,
    farmid               text      NOT NULL,
    name                 text      NOT NULL,
    frequency            text      NOT NULL DEFAULT 'Monthly'
                         CHECK (frequency IN ('Monthly', 'Fortnightly', 'Weekly')),
    poultrycashaccountid integer,
    notes                text,
    isactive             boolean   NOT NULL DEFAULT true,
    createdby            text,
    createdat            timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updatedby            text,
    updatedat            timestamp
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrypayrolltemplates_name
    ON public.poultrypayrolltemplates (lower(farmid), lower(btrim(name)));

CREATE TABLE IF NOT EXISTS public.poultrypayrolltemplatelines (
    poultrypayrolltemplatelineid serial PRIMARY KEY,
    poultrypayrolltemplateid integer NOT NULL
                             REFERENCES public.poultrypayrolltemplates (poultrypayrolltemplateid) ON DELETE CASCADE,
    poultrystaffid  integer       NOT NULL,
    basicpay        numeric(14,2) NOT NULL DEFAULT 0 CHECK (basicpay   >= 0),
    dailywage       numeric(14,2) NOT NULL DEFAULT 0 CHECK (dailywage  >= 0),
    commission      numeric(14,2) NOT NULL DEFAULT 0 CHECK (commission >= 0),
    bonus           numeric(14,2) NOT NULL DEFAULT 0 CHECK (bonus      >= 0),
    deductions      numeric(14,2) NOT NULL DEFAULT 0 CHECK (deductions >= 0),
    paymentmethod   text,
    notes           text,
    sortorder       integer       NOT NULL DEFAULT 0,
    UNIQUE (poultrypayrolltemplateid, poultrystaffid)
);

ALTER TABLE public.poultrypayrollruns ADD COLUMN IF NOT EXISTS poultrypayrolltemplateid integer;


CREATE OR REPLACE FUNCTION public.sppoultrypayrolltemplate_getall(p_farmid text, p_includeinactive boolean DEFAULT false)
 RETURNS TABLE(poultrypayrolltemplateid integer, name text, frequency text, poultrycashaccountid integer,
               cashaccountname text, notes text, isactive boolean, linecount integer, staffinactivecount integer,
               totalgross numeric, totaldeductions numeric, totalnet numeric,
               runcount integer, lastperiodstart date, lastperiodend date,
               createdby text, createdat timestamp, updatedby text, updatedat timestamp)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT t.poultrypayrolltemplateid, t.name, t.frequency, t.poultrycashaccountid,
           a.accountname::text, t.notes, t.isactive,
           COALESCE(l.cnt, 0)::int, COALESCE(l.inactive, 0)::int,
           COALESCE(l.gross, 0)::numeric(14,2), COALESCE(l.ded, 0)::numeric(14,2),
           (COALESCE(l.gross, 0) - COALESCE(l.ded, 0))::numeric(14,2),
           COALESCE(r.cnt, 0)::int, r.laststart, r.lastend,
           t.createdby, t.createdat, t.updatedby, t.updatedat
    FROM   poultrypayrolltemplates t
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = t.poultrycashaccountid
    LEFT   JOIN LATERAL (
               SELECT count(*) AS cnt,
                      count(*) FILTER (WHERE NOT COALESCE(st.isactive, false) OR COALESCE(st.isdeleted, false)) AS inactive,
                      SUM(tl.basicpay + tl.dailywage + tl.commission + tl.bonus) AS gross,
                      SUM(tl.deductions) AS ded
               FROM   poultrypayrolltemplatelines tl
               LEFT   JOIN poultrystaff st ON st.poultrystaffid = tl.poultrystaffid
               WHERE  tl.poultrypayrolltemplateid = t.poultrypayrolltemplateid) l ON TRUE
    LEFT   JOIN LATERAL (
               SELECT count(*) AS cnt, max(pr.periodstart)::date AS laststart, max(pr.periodend)::date AS lastend
               FROM   poultrypayrollruns pr
               WHERE  pr.poultrypayrolltemplateid = t.poultrypayrolltemplateid
                 AND  pr.farmid = p_farmid AND NOT pr.isdeleted AND pr.status <> 'Cancelled') r ON TRUE
    WHERE  t.farmid = p_farmid AND (p_includeinactive OR t.isactive)
    ORDER  BY t.isactive DESC, lower(t.name);
$function$;


CREATE OR REPLACE FUNCTION public.sppoultrypayrolltemplate_getlines(p_farmid text, p_templateid integer)
 RETURNS TABLE(poultrypayrolltemplatelineid integer, poultrypayrolltemplateid integer, poultrystaffid integer,
               staffname text, staffrole text, staffisactive boolean,
               basicpay numeric, dailywage numeric, commission numeric, bonus numeric, deductions numeric,
               netpay numeric, paymentmethod text, notes text, sortorder integer)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT tl.poultrypayrolltemplatelineid, tl.poultrypayrolltemplateid, tl.poultrystaffid,
           btrim(COALESCE(st.firstname, '') || ' ' || COALESCE(st.lastname, ''))::text,
           st.role::text,
           (COALESCE(st.isactive, false) AND NOT COALESCE(st.isdeleted, false)),
           tl.basicpay, tl.dailywage, tl.commission, tl.bonus, tl.deductions,
           (tl.basicpay + tl.dailywage + tl.commission + tl.bonus - tl.deductions)::numeric(14,2),
           tl.paymentmethod, tl.notes, tl.sortorder
    FROM   poultrypayrolltemplatelines tl
    JOIN   poultrypayrolltemplates t ON t.poultrypayrolltemplateid = tl.poultrypayrolltemplateid
    LEFT   JOIN poultrystaff st ON st.poultrystaffid = tl.poultrystaffid
    WHERE  t.farmid = p_farmid AND t.poultrypayrolltemplateid = p_templateid
    ORDER  BY tl.sortorder, lower(COALESCE(st.firstname, '')), tl.poultrypayrolltemplatelineid;
$function$;


-- p_lines: [{ "poultryStaffId": 1, "basicPay": 900, "dailyWage": 0, "commission": 0,
--             "bonus": 0, "deductions": 50, "paymentMethod": "MoMo", "notes": null }, ...]
-- The template's lines are REPLACED by p_lines.
CREATE OR REPLACE FUNCTION public.sppoultrypayrolltemplate_save(
    p_farmid text, p_templateid integer, p_name text, p_frequency text,
    p_poultrycashaccountid integer, p_notes text, p_lines jsonb, p_by text DEFAULT NULL)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id   integer;
    v_name text := btrim(COALESCE(p_name, ''));
    l      record;
    v_i    integer := 0;
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Give the template a name.';
    END IF;
    IF COALESCE(p_frequency, '') NOT IN ('Monthly', 'Fortnightly', 'Weekly') THEN
        RAISE EXCEPTION 'Pay frequency must be Monthly, Fortnightly or Weekly.';
    END IF;
    IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
        RAISE EXCEPTION 'Add at least one staff member to the template.';
    END IF;
    IF p_poultrycashaccountid IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = p_poultrycashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account not found for this farm.';
    END IF;
    IF EXISTS (SELECT 1 FROM poultrypayrolltemplates t
               WHERE lower(t.farmid) = lower(p_farmid) AND lower(btrim(t.name)) = lower(v_name)
                 AND t.poultrypayrolltemplateid IS DISTINCT FROM p_templateid) THEN
        RAISE EXCEPTION 'A payroll template called "%" already exists.', v_name;
    END IF;

    IF p_templateid IS NULL THEN
        INSERT INTO poultrypayrolltemplates (farmid, name, frequency, poultrycashaccountid, notes, createdby)
        VALUES (p_farmid, v_name, p_frequency, p_poultrycashaccountid, NULLIF(btrim(COALESCE(p_notes, '')), ''), p_by)
        RETURNING poultrypayrolltemplateid INTO v_id;
    ELSE
        UPDATE poultrypayrolltemplates t
        SET    name = v_name, frequency = p_frequency, poultrycashaccountid = p_poultrycashaccountid,
               notes = NULLIF(btrim(COALESCE(p_notes, '')), ''), updatedby = p_by,
               updatedat = (now() AT TIME ZONE 'utc')
        WHERE  t.poultrypayrolltemplateid = p_templateid AND t.farmid = p_farmid
        RETURNING t.poultrypayrolltemplateid INTO v_id;
        IF v_id IS NULL THEN
            RAISE EXCEPTION 'Payroll template not found for this farm.';
        END IF;
        DELETE FROM poultrypayrolltemplatelines tl WHERE tl.poultrypayrolltemplateid = v_id;
    END IF;

    FOR l IN SELECT (x->>'poultryStaffId')::int                 AS staffid,
                    COALESCE((x->>'basicPay')::numeric, 0)     AS basicpay,
                    COALESCE((x->>'dailyWage')::numeric, 0)    AS dailywage,
                    COALESCE((x->>'commission')::numeric, 0)   AS commission,
                    COALESCE((x->>'bonus')::numeric, 0)        AS bonus,
                    COALESCE((x->>'deductions')::numeric, 0)   AS deductions,
                    NULLIF(btrim(COALESCE(x->>'paymentMethod', '')), '') AS paymentmethod,
                    NULLIF(btrim(COALESCE(x->>'notes', '')), '')         AS notes
             FROM   jsonb_array_elements(p_lines) x LOOP
        v_i := v_i + 1;
        IF l.staffid IS NULL OR NOT EXISTS (
            SELECT 1 FROM poultrystaff st WHERE st.poultrystaffid = l.staffid AND st.farmid = p_farmid
              AND NOT COALESCE(st.isdeleted, false)) THEN
            RAISE EXCEPTION 'Line %: pick a staff member from this farm.', v_i;
        END IF;
        IF l.basicpay < 0 OR l.dailywage < 0 OR l.commission < 0 OR l.bonus < 0 OR l.deductions < 0 THEN
            RAISE EXCEPTION 'Line %: pay amounts cannot be negative.', v_i;
        END IF;
        IF l.basicpay + l.dailywage + l.commission + l.bonus - l.deductions < 0 THEN
            RAISE EXCEPTION 'Line %: deductions are more than the pay.', v_i;
        END IF;
        IF EXISTS (SELECT 1 FROM poultrypayrolltemplatelines tl
                   WHERE tl.poultrypayrolltemplateid = v_id AND tl.poultrystaffid = l.staffid) THEN
            RAISE EXCEPTION 'Line %: that staff member is already on this template.', v_i;
        END IF;
        INSERT INTO poultrypayrolltemplatelines
            (poultrypayrolltemplateid, poultrystaffid, basicpay, dailywage, commission, bonus, deductions,
             paymentmethod, notes, sortorder)
        VALUES (v_id, l.staffid, l.basicpay, l.dailywage, l.commission, l.bonus, l.deductions,
                l.paymentmethod, l.notes, v_i);
    END LOOP;

    RETURN v_id;
END $function$;


CREATE OR REPLACE FUNCTION public.sppoultrypayrolltemplate_setactive(
    p_farmid text, p_templateid integer, p_active boolean, p_by text DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE poultrypayrolltemplates t
    SET    isactive = p_active, updatedby = p_by, updatedat = (now() AT TIME ZONE 'utc')
    WHERE  t.poultrypayrolltemplateid = p_templateid AND t.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payroll template not found for this farm.';
    END IF;
END $function$;


-- Creates a Draft run with one line per (active) staff member on the template.
-- p_poultrycashaccountid NULL = use the template's account.
CREATE OR REPLACE FUNCTION public.sppoultrypayrolltemplate_createrun(
    p_farmid text, p_templateid integer, p_periodstart date, p_periodend date,
    p_paydate date DEFAULT NULL, p_poultrycashaccountid integer DEFAULT NULL,
    p_notes text DEFAULT NULL, p_by text DEFAULT NULL)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_t      record;
    v_runid  integer;
    v_clash  record;
    l        record;
    v_lines  integer := 0;
BEGIN
    SELECT t.* INTO v_t FROM poultrypayrolltemplates t
    WHERE  t.poultrypayrolltemplateid = p_templateid AND t.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payroll template not found for this farm.';
    END IF;
    IF NOT v_t.isactive THEN
        RAISE EXCEPTION 'Template "%" is archived. Restore it before using it.', v_t.name;
    END IF;
    IF p_periodstart IS NULL OR p_periodend IS NULL THEN
        RAISE EXCEPTION 'Pick the period start and end.';
    END IF;

    SELECT pr.periodstart, pr.periodend, pr.status INTO v_clash
    FROM   poultrypayrollruns pr
    WHERE  pr.farmid = p_farmid AND pr.poultrypayrolltemplateid = p_templateid
      AND  NOT pr.isdeleted AND pr.status <> 'Cancelled'
      AND  pr.periodstart::date <= p_periodend AND pr.periodend::date >= p_periodstart
    LIMIT  1;
    IF FOUND THEN
        RAISE EXCEPTION 'Template "%" already has a % run for % to %. Pick a period after it.',
            v_t.name, v_clash.status, to_char(v_clash.periodstart, 'YYYY-MM-DD'), to_char(v_clash.periodend, 'YYYY-MM-DD');
    END IF;

    v_runid := public.sppoultrypayrollrun_insert(
        p_farmid, p_periodstart, p_periodend, p_paydate,
        COALESCE(p_poultrycashaccountid, v_t.poultrycashaccountid),
        COALESCE(NULLIF(btrim(COALESCE(p_notes, '')), ''), 'From template: ' || v_t.name),
        p_by);

    UPDATE poultrypayrollruns pr SET poultrypayrolltemplateid = p_templateid
    WHERE  pr.poultrypayrollrunid = v_runid;

    FOR l IN SELECT tl.* FROM poultrypayrolltemplatelines tl
             JOIN poultrystaff st ON st.poultrystaffid = tl.poultrystaffid AND st.farmid = p_farmid
             WHERE tl.poultrypayrolltemplateid = p_templateid
               AND COALESCE(st.isactive, false) AND NOT COALESCE(st.isdeleted, false)
             ORDER BY tl.sortorder LOOP
        PERFORM public.sppoultrypayrollitem_upsert(
            v_runid, p_farmid, l.poultrystaffid, l.basicpay, l.dailywage, l.commission,
            l.bonus, l.deductions, l.paymentmethod, l.notes);
        v_lines := v_lines + 1;
    END LOOP;

    IF v_lines = 0 THEN
        RAISE EXCEPTION 'Template "%" has no active staff on it.', v_t.name;
    END IF;

    RETURN v_runid;
END $function$;

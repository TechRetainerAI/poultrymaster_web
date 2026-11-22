-- 460: Livestock health, vaccination plans, treatment campaigns, feed
--      formulas & mixing, feeding many groups at once, days of supply, alerts.
--
-- Needs 458 and 459.
--
-- 1. Health records (livestockhealthrecords) -- the poultry Health page: an
--    observation, illness, treatment, vaccination, deworming or vet visit on a
--    group or one tagged animal. One may use a stock item (a vaccine, a
--    dewormer); that is a stock usage tagged sourcetype 'HealthRecord' and the
--    group, like every other use of stock.
--
-- 2. Vaccination plans (livestockvaccineplans / steps). A suggested plan per
--    species is seeded (farmid NULL, read-only); a farm can copy one and change
--    it, and chooses per species which plan its groups follow. A step is due
--    at an AGE (days since birth/hatch); a group's age is its age at start
--    (groups.ageatstartdays, 458) plus days since it started. A repeating step
--    is due again N days after it was last given. Giving it is a health
--    record of kind 'Vaccination' carrying the step.
--
-- 3. Treatment campaigns (poultry 339 for livestock): one medicine for several
--    groups over several days. Each day posted is stock usage per group
--    (sourcetype 'TreatmentDay'); a day can be reversed. Withdrawal: no meat,
--    milk or eggs sold from a group until N days after its last dose.
--
-- 4. Feed formulas and mixing (poultry feed formulas / feed production): a
--    formula turns ingredients into a finished feed. A mixing run uses the
--    ingredients (sourcetype 'FeedRun') and puts the feed into stock
--    ('Produced') at what the ingredients cost plus any other cost.
--
-- 5. Feeding many groups at once (poultry Distribute Feed): one feed, one
--    date, a quantity per group -- each becomes a feed line on that group's
--    daily record (made if the day has none), through splivestockproduction_save,
--    so it is no different from typing it on the record.
--
-- 6. Days of supply: each feed's average daily use over the last 14 days and
--    when it runs out.
--
-- 7. Alerts: derived, not stored -- high deaths, eggs or milk falling, groups
--    with no record, stock low or running out, births due, vaccinations
--    overdue, groups under a withdrawal period. Worded plainly.
--
-- 8. IAM mirrors: health <- health, vaccination <- health, treatments <-
--    medication, feed-formulas <- feed-formulas, feed-production <-
--    feed-production, alerts <- flocks.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Health records
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockvaccineplans (
    planid       serial PRIMARY KEY,
    farmid       text,                                -- NULL = a suggested plan everyone sees
    speciescode  text NOT NULL REFERENCES livestockspecies(speciescode),
    name         text NOT NULL,
    notes        text,
    copiedfrom   integer REFERENCES livestockvaccineplans(planid),
    isdeleted    boolean NOT NULL DEFAULT FALSE,
    createdat    timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby    text
);
CREATE UNIQUE INDEX IF NOT EXISTS uxlivestockvaccineplans_system
    ON livestockvaccineplans (speciescode, name) WHERE farmid IS NULL;

CREATE TABLE IF NOT EXISTS livestockvaccineplansteps (
    stepid       serial PRIMARY KEY,
    planid       integer NOT NULL REFERENCES livestockvaccineplans(planid),
    name         text NOT NULL,                       -- "PPR vaccine"
    kind         text NOT NULL DEFAULT 'Vaccination' CHECK (kind IN ('Vaccination', 'Deworming', 'Treatment')),
    dayofage     integer NOT NULL CHECK (dayofage >= 0),
    repeatdays   integer CHECK (repeatdays IS NULL OR repeatdays > 0),
    method       text,                                -- "Injection", "Drinking water", "Eye drop"
    notes        text,
    sortorder    integer NOT NULL DEFAULT 0
);

-- Which plan a farm's groups of a species follow. No row = the suggested plan.
CREATE TABLE IF NOT EXISTS livestockfarmvaccineplans (
    farmid       text NOT NULL,
    speciescode  text NOT NULL REFERENCES livestockspecies(speciescode),
    planid       integer REFERENCES livestockvaccineplans(planid),   -- NULL = no plan
    PRIMARY KEY (farmid, speciescode)
);

CREATE TABLE IF NOT EXISTS livestockhealthrecords (
    healthid     serial PRIMARY KEY,
    farmid       text NOT NULL,
    groupid      integer NOT NULL REFERENCES livestockgroups(groupid),
    animalid     integer REFERENCES livestockanimals(animalid),
    recorddate   date NOT NULL,
    kind         text NOT NULL CHECK (kind IN ('Observation', 'Illness', 'Treatment', 'Vaccination', 'Deworming', 'VetVisit')),
    affected     integer CHECK (affected IS NULL OR affected > 0),
    signs        text,
    diagnosis    text,
    action       text,
    vetname      text,
    itemid       integer REFERENCES livestockitems(itemid),
    quantity     numeric(14,3) CHECK (quantity IS NULL OR quantity > 0),
    stepid       integer REFERENCES livestockvaccineplansteps(stepid),
    status       text NOT NULL DEFAULT 'Resolved' CHECK (status IN ('Open', 'Resolved')),
    resolveddate date,
    notes        text,
    isdeleted    boolean NOT NULL DEFAULT FALSE,
    createdat    timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby    text,
    updatedat    timestamp,
    updatedby    text
);
CREATE INDEX IF NOT EXISTS ixlivestockhealthrecords_group ON livestockhealthrecords (groupid, recorddate) WHERE NOT isdeleted;
CREATE INDEX IF NOT EXISTS ixlivestockhealthrecords_step ON livestockhealthrecords (groupid, stepid) WHERE NOT isdeleted AND stepid IS NOT NULL;

CREATE OR REPLACE FUNCTION public.fnlivestock_healthjson(p_id integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'healthId', h.healthid, 'groupId', h.groupid, 'groupName', g.name, 'speciesName', s.name,
        'animalId', h.animalid, 'tagNumber', a.tagnumber, 'date', h.recorddate, 'kind', h.kind, 'affected', h.affected,
        'signs', h.signs, 'diagnosis', h.diagnosis, 'action', h.action, 'vetName', h.vetname,
        'itemId', h.itemid, 'itemName', i.name, 'unit', i.unit, 'quantity', h.quantity,
        'cost', (SELECT -SUM(m.totalcost) FROM livestockstockmovements m
                 WHERE m.sourcetype = 'HealthRecord' AND m.sourceid = h.healthid AND m.reversedat IS NULL),
        'stepId', h.stepid, 'stepName', st.name, 'status', h.status, 'resolvedDate', h.resolveddate, 'notes', h.notes,
        'createdBy', h.createdby)
    FROM livestockhealthrecords h
    JOIN livestockgroups g ON g.groupid = h.groupid
    JOIN livestockspecies s ON s.speciescode = g.speciescode
    LEFT JOIN livestockanimals a ON a.animalid = h.animalid
    LEFT JOIN livestockitems i ON i.itemid = h.itemid
    LEFT JOIN livestockvaccineplansteps st ON st.stepid = h.stepid
    WHERE h.healthid = p_id;
$f$;

-- p_filter: {groupId, animalId, kind, status, from, to}
CREATE OR REPLACE FUNCTION public.splivestockhealth_list(p_farmid text, p_filter jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(fnlivestock_healthjson(h.healthid) ORDER BY h.recorddate DESC, h.healthid DESC), '[]'::jsonb)
    FROM livestockhealthrecords h
    WHERE h.farmid = p_farmid AND NOT h.isdeleted
      AND (NULLIF(p_filter->>'groupId', '') IS NULL OR h.groupid = (p_filter->>'groupId')::int)
      AND (NULLIF(p_filter->>'animalId', '') IS NULL OR h.animalid = (p_filter->>'animalId')::int)
      AND (NULLIF(p_filter->>'kind', '') IS NULL OR h.kind = p_filter->>'kind')
      AND (NULLIF(p_filter->>'status', '') IS NULL OR h.status = p_filter->>'status')
      AND (NULLIF(p_filter->>'from', '') IS NULL OR h.recorddate >= (p_filter->>'from')::date)
      AND (NULLIF(p_filter->>'to', '') IS NULL OR h.recorddate <= (p_filter->>'to')::date);
$f$;

CREATE OR REPLACE FUNCTION public.splivestockhealth_save(p_farmid text, p_h jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id     integer := NULLIF(p_h->>'healthId', '')::int;
    v_gid    integer := NULLIF(p_h->>'groupId', '')::int;
    v_aid    integer := NULLIF(p_h->>'animalId', '')::int;
    v_date   date    := NULLIF(p_h->>'date', '')::date;
    v_kind   text    := COALESCE(NULLIF(p_h->>'kind', ''), 'Observation');
    v_item   integer := NULLIF(p_h->>'itemId', '')::int;
    v_qty    numeric := NULLIF(p_h->>'quantity', '')::numeric;
    v_step   integer := NULLIF(p_h->>'stepId', '')::int;
    v_status text    := COALESCE(NULLIF(p_h->>'status', ''), CASE WHEN v_kind = 'Illness' THEN 'Open' ELSE 'Resolved' END);
    v_aff    integer := NULLIF(p_h->>'affected', '')::int;
    v_g      livestockgroups%ROWTYPE;
    v_it     livestockitems%ROWTYPE;
BEGIN
    IF v_id IS NOT NULL THEN
        SELECT groupid INTO v_gid FROM livestockhealthrecords WHERE healthid = v_id AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
        IF v_gid IS NULL THEN
            RAISE EXCEPTION 'That health record was not found.' USING ERRCODE = 'P0001';
        END IF;
    END IF;
    IF v_aid IS NOT NULL THEN
        SELECT groupid INTO v_gid FROM livestockanimals WHERE animalid = v_aid AND farmid = p_farmid AND NOT isdeleted;
        IF v_gid IS NULL THEN
            RAISE EXCEPTION 'That animal was not found.' USING ERRCODE = 'P0001';
        END IF;
        v_aff := 1;
    END IF;
    SELECT * INTO v_g FROM livestockgroups WHERE groupid = v_gid AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Choose the group.' USING ERRCODE = 'P0001';
    END IF;
    IF v_kind NOT IN ('Observation', 'Illness', 'Treatment', 'Vaccination', 'Deworming', 'VetVisit') THEN
        RAISE EXCEPTION 'Unknown kind of health record "%".', v_kind USING ERRCODE = 'P0001';
    END IF;
    IF v_date IS NULL OR v_date > (now() at time zone 'utc')::date + 1 OR v_date < v_g.startdate THEN
        RAISE EXCEPTION 'Enter a date between the group''s start and today.' USING ERRCODE = 'P0001';
    END IF;
    IF v_aff IS NOT NULL AND v_aff > GREATEST(fnlivestock_groupheadasof(v_gid, v_date), 1) THEN
        RAISE EXCEPTION '% had only % animal(s) that day.', v_g.name, fnlivestock_groupheadasof(v_gid, v_date) USING ERRCODE = 'P0001';
    END IF;
    IF v_status NOT IN ('Open', 'Resolved') THEN
        RAISE EXCEPTION 'Unknown status "%".', v_status USING ERRCODE = 'P0001';
    END IF;
    IF (v_item IS NULL) <> (v_qty IS NULL) THEN
        RAISE EXCEPTION 'Choose the medicine and how much was used, or neither.' USING ERRCODE = 'P0001';
    END IF;
    IF v_item IS NOT NULL THEN
        SELECT * INTO v_it FROM livestockitems WHERE itemid = v_item AND farmid = p_farmid AND NOT isdeleted;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That stock item was not found.' USING ERRCODE = 'P0001';
        END IF;
        IF v_it.category NOT IN ('Medication', 'Vaccine', 'Supply', 'Other') THEN
            RAISE EXCEPTION '% is % and is used on daily records.', v_it.name, lower(v_it.category) USING ERRCODE = 'P0001';
        END IF;
        IF v_it.speciescode IS NOT NULL AND v_it.speciescode <> v_g.speciescode THEN
            RAISE EXCEPTION '% is for another kind of animal.', v_it.name USING ERRCODE = 'P0001';
        END IF;
    END IF;
    IF v_step IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM livestockvaccineplansteps st JOIN livestockvaccineplans p ON p.planid = st.planid
        WHERE st.stepid = v_step AND p.speciescode = v_g.speciescode AND (p.farmid IS NULL OR p.farmid = p_farmid)) THEN
        RAISE EXCEPTION 'That plan step is for another kind of animal.' USING ERRCODE = 'P0001';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO livestockhealthrecords (farmid, groupid, animalid, recorddate, kind, affected, signs, diagnosis, action,
            vetname, itemid, quantity, stepid, status, resolveddate, notes, createdby)
        VALUES (p_farmid, v_gid, v_aid, v_date, v_kind, v_aff, NULLIF(btrim(p_h->>'signs'), ''), NULLIF(btrim(p_h->>'diagnosis'), ''),
            NULLIF(btrim(p_h->>'action'), ''), NULLIF(btrim(p_h->>'vetName'), ''), v_item, v_qty, v_step, v_status,
            CASE WHEN v_status = 'Resolved' AND v_kind = 'Illness' THEN COALESCE(NULLIF(p_h->>'resolvedDate', '')::date, v_date) END,
            NULLIF(btrim(p_h->>'notes'), ''), p_by)
        RETURNING healthid INTO v_id;
    ELSE
        PERFORM fnlivestock_reversesource('HealthRecord', v_id, p_by, 'Health record edited');
        UPDATE livestockhealthrecords SET animalid = v_aid, recorddate = v_date, kind = v_kind, affected = v_aff,
            signs = NULLIF(btrim(p_h->>'signs'), ''), diagnosis = NULLIF(btrim(p_h->>'diagnosis'), ''),
            action = NULLIF(btrim(p_h->>'action'), ''), vetname = NULLIF(btrim(p_h->>'vetName'), ''),
            itemid = v_item, quantity = v_qty, stepid = v_step, status = v_status,
            resolveddate = CASE WHEN v_status = 'Resolved' AND v_kind = 'Illness'
                                THEN COALESCE(NULLIF(p_h->>'resolvedDate', '')::date, resolveddate, (now() at time zone 'utc')::date) END,
            notes = NULLIF(btrim(p_h->>'notes'), ''), updatedat = (now() at time zone 'utc'), updatedby = p_by
        WHERE healthid = v_id;
    END IF;
    IF v_item IS NOT NULL THEN
        PERFORM splivestockstock_post(p_farmid, v_item, v_date, 'Usage', -v_qty, NULL, p_by,
            v_g.name || ' ' || lower(v_kind), 'HealthRecord', v_id, v_gid);
    END IF;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockhealth_delete(p_farmid text, p_id integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    UPDATE livestockhealthrecords SET isdeleted = TRUE, updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE healthid = p_id AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That health record was not found.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM fnlivestock_reversesource('HealthRecord', p_id, p_by, 'Health record deleted');
END
$f$;

-- ---------------------------------------------------------------------------
-- 2. Vaccination plans -- suggested plans
-- ---------------------------------------------------------------------------
DO $seed$
DECLARE v_plan integer; r record;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('duck',        'Suggested duck plan'),
        ('guinea_fowl', 'Suggested guinea fowl plan'),
        ('turkey',      'Suggested turkey plan'),
        ('quail',       'Suggested quail plan'),
        ('goose',       'Suggested goose plan'),
        ('rabbit',      'Suggested rabbit plan'),
        ('grasscutter', 'Suggested grasscutter plan'),
        ('goat',        'Suggested goat plan'),
        ('sheep',       'Suggested sheep plan'),
        ('pig',         'Suggested pig plan'),
        ('cattle',      'Suggested cattle plan')) AS t(code, name)
    LOOP
        CONTINUE WHEN EXISTS (SELECT 1 FROM livestockvaccineplans WHERE farmid IS NULL AND speciescode = r.code AND name = r.name);
        INSERT INTO livestockvaccineplans (farmid, speciescode, name, notes)
        VALUES (NULL, r.code, r.name, 'A common starting plan. Check it with your vet and copy it to change it.')
        RETURNING planid INTO v_plan;
        INSERT INTO livestockvaccineplansteps (planid, name, kind, dayofage, repeatdays, method, sortorder)
        SELECT v_plan, s.name, s.kind, s.day, s.rep, s.method, s.ord FROM (VALUES
            -- code, step, kind, day of age, repeat every, method, order
            ('duck', 'Duck viral hepatitis', 'Vaccination', 1, NULL::int, 'Injection', 1),
            ('duck', 'Duck plague', 'Vaccination', 21, 180, 'Injection', 2),
            ('duck', 'Deworming', 'Deworming', 42, 90, 'Drinking water', 3),
            ('guinea_fowl', 'Newcastle (Lasota)', 'Vaccination', 14, NULL, 'Drinking water', 1),
            ('guinea_fowl', 'Newcastle booster', 'Vaccination', 35, NULL, 'Drinking water', 2),
            ('guinea_fowl', 'Fowl pox', 'Vaccination', 56, NULL, 'Wing web', 3),
            ('guinea_fowl', 'Newcastle (Komarov)', 'Vaccination', 84, 120, 'Injection', 4),
            ('turkey', 'Newcastle', 'Vaccination', 7, NULL, 'Eye drop', 1),
            ('turkey', 'Newcastle booster', 'Vaccination', 28, 90, 'Drinking water', 2),
            ('turkey', 'Fowl pox', 'Vaccination', 56, NULL, 'Wing web', 3),
            ('turkey', 'Deworming', 'Deworming', 56, 90, 'Drinking water', 4),
            ('quail', 'Newcastle', 'Vaccination', 14, NULL, 'Drinking water', 1),
            ('quail', 'Newcastle booster', 'Vaccination', 35, 90, 'Drinking water', 2),
            ('goose', 'Goose parvovirus', 'Vaccination', 1, NULL, 'Injection', 1),
            ('goose', 'Duck plague', 'Vaccination', 28, 180, 'Injection', 2),
            ('goose', 'Deworming', 'Deworming', 42, 90, 'Drinking water', 3),
            ('rabbit', 'Coccidiosis prevention', 'Treatment', 35, NULL, 'Drinking water', 1),
            ('rabbit', 'Deworming', 'Deworming', 42, 90, 'Oral', 2),
            ('rabbit', 'Rabbit haemorrhagic disease (RHD)', 'Vaccination', 70, 365, 'Injection', 3),
            ('grasscutter', 'Deworming', 'Deworming', 60, 90, 'Oral', 1),
            ('goat', 'Clostridial (CDT)', 'Vaccination', 56, NULL, 'Injection', 1),
            ('goat', 'Clostridial (CDT) booster', 'Vaccination', 84, 365, 'Injection', 2),
            ('goat', 'Peste des petits ruminants (PPR)', 'Vaccination', 90, 365, 'Injection', 3),
            ('goat', 'Deworming', 'Deworming', 60, 90, 'Oral', 4),
            ('sheep', 'Clostridial (CDT)', 'Vaccination', 56, NULL, 'Injection', 1),
            ('sheep', 'Clostridial (CDT) booster', 'Vaccination', 84, 365, 'Injection', 2),
            ('sheep', 'Peste des petits ruminants (PPR)', 'Vaccination', 90, 365, 'Injection', 3),
            ('sheep', 'Deworming', 'Deworming', 60, 90, 'Oral', 4),
            ('pig', 'Iron injection', 'Treatment', 3, NULL, 'Injection', 1),
            ('pig', 'Deworming', 'Deworming', 42, 90, 'Oral', 2),
            ('pig', 'Erysipelas', 'Vaccination', 70, 180, 'Injection', 3),
            ('cattle', 'Deworming', 'Deworming', 90, 120, 'Oral', 1),
            ('cattle', 'Blackleg', 'Vaccination', 120, 365, 'Injection', 2),
            ('cattle', 'Anthrax', 'Vaccination', 180, 365, 'Injection', 3),
            ('cattle', 'Contagious bovine pleuropneumonia (CBPP)', 'Vaccination', 180, 365, 'Injection', 4)
        ) AS s(code, name, kind, day, rep, method, ord)
        WHERE s.code = r.code;
    END LOOP;
END
$seed$;

CREATE OR REPLACE FUNCTION public.fnlivestock_planjson(p_planid integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'planId', p.planid, 'speciesCode', p.speciescode, 'speciesName', s.name, 'name', p.name, 'notes', p.notes,
        'isSuggested', p.farmid IS NULL, 'copiedFrom', p.copiedfrom,
        'steps', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                      'stepId', st.stepid, 'name', st.name, 'kind', st.kind, 'dayOfAge', st.dayofage,
                      'repeatDays', st.repeatdays, 'method', st.method, 'notes', st.notes)
                      ORDER BY st.dayofage, st.sortorder, st.stepid), '[]'::jsonb)
                  FROM livestockvaccineplansteps st WHERE st.planid = p.planid))
    FROM livestockvaccineplans p JOIN livestockspecies s ON s.speciescode = p.speciescode
    WHERE p.planid = p_planid;
$f$;

-- The plan a farm's groups of a species follow (NULL = none).
CREATE OR REPLACE FUNCTION public.fnlivestock_planfor(p_farmid text, p_species text)
 RETURNS integer LANGUAGE sql STABLE AS $f$
    SELECT CASE WHEN fp.farmid IS NOT NULL THEN fp.planid
                ELSE (SELECT planid FROM livestockvaccineplans WHERE farmid IS NULL AND speciescode = p_species
                      AND NOT isdeleted ORDER BY planid LIMIT 1) END
    FROM (SELECT 1) x
    LEFT JOIN livestockfarmvaccineplans fp ON fp.farmid = p_farmid AND fp.speciescode = p_species;
$f$;

-- Every plan the farm can see, for the species it keeps, and which is in use.
CREATE OR REPLACE FUNCTION public.splivestockplan_list(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(fnlivestock_planjson(p.planid) || jsonb_build_object(
               'inUse', fnlivestock_planfor(p_farmid, p.speciescode) = p.planid)
           ORDER BY s.sortorder, p.farmid NULLS FIRST, p.planid), '[]'::jsonb)
    FROM livestockvaccineplans p
    JOIN livestockspecies s ON s.speciescode = p.speciescode
    JOIN livestockfarmspecies fs ON fs.farmid = p_farmid AND fs.speciescode = p.speciescode
    WHERE NOT p.isdeleted AND (p.farmid IS NULL OR p.farmid = p_farmid);
$f$;

-- Save a farm plan: {planId?, speciesCode, name, notes, steps:[{name, kind, dayOfAge, repeatDays, method, notes}]}.
-- Steps already given to a group are kept (their history points at them);
-- others are replaced.
CREATE OR REPLACE FUNCTION public.splivestockplan_save(p_farmid text, p_plan jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id   integer := NULLIF(p_plan->>'planId', '')::int;
    v_sp   text    := NULLIF(p_plan->>'speciesCode', '');
    v_name text    := btrim(COALESCE(p_plan->>'name', ''));
    v_s    jsonb;
    v_i    integer := 0;
    v_keep integer[] := '{}';
    v_stepid integer;
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Give the plan a name.' USING ERRCODE = 'P0001';
    END IF;
    IF v_id IS NOT NULL THEN
        SELECT speciescode INTO v_sp FROM livestockvaccineplans WHERE planid = v_id AND farmid = p_farmid AND NOT isdeleted;
        IF v_sp IS NULL THEN
            RAISE EXCEPTION 'Only your own plans can be changed. Copy a suggested plan to change it.' USING ERRCODE = 'P0001';
        END IF;
        UPDATE livestockvaccineplans SET name = v_name, notes = NULLIF(btrim(p_plan->>'notes'), '') WHERE planid = v_id;
    ELSE
        PERFORM fnlivestock_requirespecies(p_farmid, v_sp);
        INSERT INTO livestockvaccineplans (farmid, speciescode, name, notes, copiedfrom, createdby)
        VALUES (p_farmid, v_sp, v_name, NULLIF(btrim(p_plan->>'notes'), ''), NULLIF(p_plan->>'copiedFrom', '')::int, p_by)
        RETURNING planid INTO v_id;
    END IF;

    FOR v_s IN SELECT * FROM jsonb_array_elements(COALESCE(p_plan->'steps', '[]'::jsonb)) LOOP
        v_i := v_i + 1;
        IF btrim(COALESCE(v_s->>'name', '')) = '' THEN
            RAISE EXCEPTION 'Step % has no name.', v_i USING ERRCODE = 'P0001';
        END IF;
        IF NULLIF(v_s->>'dayOfAge', '') IS NULL OR (v_s->>'dayOfAge')::int < 0 THEN
            RAISE EXCEPTION 'Step "%" needs the age in days.', v_s->>'name' USING ERRCODE = 'P0001';
        END IF;
        IF NULLIF(v_s->>'repeatDays', '')::int <= 0 THEN
            RAISE EXCEPTION 'Step "%": repeat every must be at least one day.', v_s->>'name' USING ERRCODE = 'P0001';
        END IF;
        v_stepid := NULLIF(v_s->>'stepId', '')::int;
        IF v_stepid IS NOT NULL AND EXISTS (SELECT 1 FROM livestockvaccineplansteps WHERE stepid = v_stepid AND planid = v_id) THEN
            UPDATE livestockvaccineplansteps SET name = btrim(v_s->>'name'), kind = COALESCE(NULLIF(v_s->>'kind', ''), 'Vaccination'),
                dayofage = (v_s->>'dayOfAge')::int, repeatdays = NULLIF(v_s->>'repeatDays', '')::int,
                method = NULLIF(btrim(v_s->>'method'), ''), notes = NULLIF(btrim(v_s->>'notes'), ''), sortorder = v_i
            WHERE stepid = v_stepid;
        ELSE
            INSERT INTO livestockvaccineplansteps (planid, name, kind, dayofage, repeatdays, method, notes, sortorder)
            VALUES (v_id, btrim(v_s->>'name'), COALESCE(NULLIF(v_s->>'kind', ''), 'Vaccination'), (v_s->>'dayOfAge')::int,
                    NULLIF(v_s->>'repeatDays', '')::int, NULLIF(btrim(v_s->>'method'), ''), NULLIF(btrim(v_s->>'notes'), ''), v_i)
            RETURNING stepid INTO v_stepid;
        END IF;
        v_keep := v_keep || v_stepid;
    END LOOP;
    -- Steps left out: removed unless a group was already given them.
    IF EXISTS (SELECT 1 FROM livestockvaccineplansteps st WHERE st.planid = v_id AND NOT (st.stepid = ANY (v_keep))
               AND EXISTS (SELECT 1 FROM livestockhealthrecords h WHERE h.stepid = st.stepid AND NOT h.isdeleted)) THEN
        RAISE EXCEPTION 'A step you removed has already been given to a group. Keep it, or delete those health records first.'
            USING ERRCODE = 'P0001';
    END IF;
    DELETE FROM livestockvaccineplansteps WHERE planid = v_id AND NOT (stepid = ANY (v_keep));
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockplan_copy(p_farmid text, p_planid integer, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_src livestockvaccineplans%ROWTYPE; v_id integer;
BEGIN
    SELECT * INTO v_src FROM livestockvaccineplans WHERE planid = p_planid AND NOT isdeleted AND (farmid IS NULL OR farmid = p_farmid);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That plan was not found.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM fnlivestock_requirespecies(p_farmid, v_src.speciescode);
    INSERT INTO livestockvaccineplans (farmid, speciescode, name, notes, copiedfrom, createdby)
    VALUES (p_farmid, v_src.speciescode, 'My ' || lower(regexp_replace(v_src.name, '^Suggested ', '')), v_src.notes, p_planid, p_by)
    RETURNING planid INTO v_id;
    INSERT INTO livestockvaccineplansteps (planid, name, kind, dayofage, repeatdays, method, notes, sortorder)
    SELECT v_id, name, kind, dayofage, repeatdays, method, notes, sortorder FROM livestockvaccineplansteps WHERE planid = p_planid;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockplan_delete(p_farmid text, p_planid integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    IF EXISTS (SELECT 1 FROM livestockfarmvaccineplans WHERE farmid = p_farmid AND planid = p_planid) THEN
        RAISE EXCEPTION 'Your groups follow this plan. Choose another plan for them first.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockvaccineplans SET isdeleted = TRUE WHERE planid = p_planid AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Only your own plans can be deleted.' USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- Which plan a species' groups follow; p_planid NULL = no plan.
CREATE OR REPLACE FUNCTION public.splivestockplan_use(p_farmid text, p_species text, p_planid integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    PERFORM fnlivestock_requirespecies(p_farmid, p_species);
    IF p_planid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM livestockvaccineplans WHERE planid = p_planid AND NOT isdeleted
            AND speciescode = p_species AND (farmid IS NULL OR farmid = p_farmid)) THEN
        RAISE EXCEPTION 'That plan is not for this kind of animal.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO livestockfarmvaccineplans (farmid, speciescode, planid) VALUES (p_farmid, p_species, p_planid)
    ON CONFLICT (farmid, speciescode) DO UPDATE SET planid = EXCLUDED.planid;
END
$f$;

-- What is due: for every active group, each plan step's next due date.
--   age on a date = ageatstartdays + (date - startdate)
--   first due     = startdate + (dayofage - ageatstartdays)
-- A one-off step already past when the group started is not listed (too old
-- for it on arrival). A repeating one is due again repeatdays after it was
-- last given; never given and already past at start = due on the start date.
CREATE OR REPLACE FUNCTION public.splivestockvaccination_due(p_farmid text, p_horizondays integer DEFAULT 60, p_groupid integer DEFAULT NULL)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH today AS (SELECT (now() at time zone 'utc')::date AS td),
    gs AS (
        SELECT g.*, COALESCE(g.ageatstartdays, 0) AS age0, fnlivestock_planfor(p_farmid, g.speciescode) AS planid
        FROM livestockgroups g
        WHERE g.farmid = p_farmid AND NOT g.isdeleted AND g.status = 'Active'
          AND (p_groupid IS NULL OR g.groupid = p_groupid) AND fnlivestock_grouphead(g.groupid) > 0
    ),
    st AS (
        SELECT gs.groupid, gs.name AS groupname, gs.speciescode, gs.startdate, gs.age0, s.*,
               gs.startdate + (s.dayofage - gs.age0) AS firstdue,
               (SELECT max(h.recorddate) FROM livestockhealthrecords h
                WHERE h.groupid = gs.groupid AND h.stepid = s.stepid AND NOT h.isdeleted AND h.animalid IS NULL) AS lastgiven
        FROM gs JOIN livestockvaccineplansteps s ON s.planid = gs.planid
    ),
    d AS (
        SELECT st.*,
               CASE WHEN st.lastgiven IS NOT NULL THEN
                        CASE WHEN st.repeatdays IS NULL THEN NULL ELSE st.lastgiven + st.repeatdays END
                    WHEN st.firstdue >= st.startdate THEN st.firstdue
                    WHEN st.repeatdays IS NOT NULL THEN st.startdate
                    ELSE NULL END AS due
        FROM st
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'groupId', d.groupid, 'groupName', d.groupname, 'speciesCode', d.speciescode,
        'stepId', d.stepid, 'name', d.name, 'kind', d.kind, 'method', d.method, 'dayOfAge', d.dayofage,
        'repeatDays', d.repeatdays, 'due', d.due, 'lastGiven', d.lastgiven,
        'ageOnDue', d.age0 + (d.due - d.startdate),
        'daysToDue', d.due - (SELECT td FROM today),
        'status', CASE WHEN d.due < (SELECT td FROM today) THEN 'Overdue'
                       WHEN d.due <= (SELECT td FROM today) + 7 THEN 'DueSoon' ELSE 'Upcoming' END
    ) ORDER BY d.due, d.groupname, d.dayofage), '[]'::jsonb)
    FROM d
    WHERE d.due IS NOT NULL AND d.due <= (SELECT td FROM today) + p_horizondays;
$f$;

-- ---------------------------------------------------------------------------
-- 3. Treatment campaigns
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestocktreatments (
    treatmentid        serial PRIMARY KEY,
    farmid             text NOT NULL,
    name               text NOT NULL,
    itemid             integer NOT NULL REFERENCES livestockitems(itemid),
    reason             text,
    startdate          date NOT NULL,
    enddate            date NOT NULL,
    dosequantity       numeric(14,4) NOT NULL CHECK (dosequantity > 0),
    dosebasis          text NOT NULL CHECK (dosebasis IN ('PerAnimal', 'Per100Animals', 'PerGroup')),
    meatwithdrawaldays integer CHECK (meatwithdrawaldays IS NULL OR meatwithdrawaldays >= 0),
    milkwithdrawaldays integer CHECK (milkwithdrawaldays IS NULL OR milkwithdrawaldays >= 0),
    eggwithdrawaldays  integer CHECK (eggwithdrawaldays IS NULL OR eggwithdrawaldays >= 0),
    status             text NOT NULL DEFAULT 'Open' CHECK (status IN ('Open', 'Completed', 'Cancelled')),
    notes              text,
    createdat          timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby          text,
    closedat           timestamp,
    closedby           text,
    cancelreason       text,
    CHECK (enddate >= startdate)
);
CREATE TABLE IF NOT EXISTS livestocktreatmentgroups (
    treatmentid integer NOT NULL REFERENCES livestocktreatments(treatmentid),
    groupid     integer NOT NULL REFERENCES livestockgroups(groupid),
    PRIMARY KEY (treatmentid, groupid)
);
CREATE TABLE IF NOT EXISTS livestocktreatmentdays (
    dayid         serial PRIMARY KEY,
    treatmentid   integer NOT NULL REFERENCES livestocktreatments(treatmentid),
    treatdate     date NOT NULL,
    notes         text,
    postedat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    postedby      text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text
);
CREATE UNIQUE INDEX IF NOT EXISTS uxlivestocktreatmentdays_day
    ON livestocktreatmentdays (treatmentid, treatdate) WHERE reversedat IS NULL;
CREATE TABLE IF NOT EXISTS livestocktreatmentdaylines (
    lineid          serial PRIMARY KEY,
    dayid           integer NOT NULL REFERENCES livestocktreatmentdays(dayid),
    groupid         integer NOT NULL REFERENCES livestockgroups(groupid),
    head            integer NOT NULL,
    quantity        numeric(14,3) NOT NULL CHECK (quantity > 0),
    stockmovementid integer REFERENCES livestockstockmovements(movementid)
);

-- Suggested quantity for a group from the dose.
CREATE OR REPLACE FUNCTION public.fnlivestock_dose(p_basis text, p_dose numeric, p_head integer)
 RETURNS numeric LANGUAGE sql IMMUTABLE AS $f$
    SELECT round(CASE p_basis WHEN 'PerAnimal' THEN p_dose * p_head
                              WHEN 'Per100Animals' THEN p_dose * p_head / 100.0
                              ELSE p_dose END, 3);
$f$;

-- The last day each group was dosed, and when its withdrawal ends.
CREATE OR REPLACE FUNCTION public.splivestockwithdrawals(p_farmid text, p_groupid integer DEFAULT NULL)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.until DESC), '[]'::jsonb) FROM (
        SELECT jsonb_build_object('groupId', l.groupid, 'groupName', g.name, 'treatmentId', t.treatmentid,
                   'treatmentName', t.name, 'itemName', i.name, 'lastDose', max(d.treatdate),
                   'meatUntil', max(d.treatdate) + t.meatwithdrawaldays, 'milkUntil', max(d.treatdate) + t.milkwithdrawaldays,
                   'eggsUntil', max(d.treatdate) + t.eggwithdrawaldays) AS j,
               max(d.treatdate) + GREATEST(COALESCE(t.meatwithdrawaldays, 0), COALESCE(t.milkwithdrawaldays, 0), COALESCE(t.eggwithdrawaldays, 0)) AS until
        FROM livestocktreatmentdaylines l
        JOIN livestocktreatmentdays d ON d.dayid = l.dayid AND d.reversedat IS NULL
        JOIN livestocktreatments t ON t.treatmentid = d.treatmentid AND t.farmid = p_farmid
        JOIN livestockgroups g ON g.groupid = l.groupid
        JOIN livestockitems i ON i.itemid = t.itemid
        WHERE (p_groupid IS NULL OR l.groupid = p_groupid)
        GROUP BY l.groupid, g.name, t.treatmentid, t.name, i.name, t.meatwithdrawaldays, t.milkwithdrawaldays, t.eggwithdrawaldays
    ) x
    WHERE x.until >= (now() at time zone 'utc')::date;
$f$;

CREATE OR REPLACE FUNCTION public.fnlivestock_treatmentjson(p_id integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'treatmentId', t.treatmentid, 'name', t.name, 'itemId', t.itemid, 'itemName', i.name, 'unit', i.unit,
        'reason', t.reason, 'startDate', t.startdate, 'endDate', t.enddate, 'doseQuantity', t.dosequantity,
        'doseBasis', t.dosebasis, 'meatWithdrawalDays', t.meatwithdrawaldays, 'milkWithdrawalDays', t.milkwithdrawaldays,
        'eggWithdrawalDays', t.eggwithdrawaldays, 'lifecycle', t.status, 'notes', t.notes,
        'status', CASE WHEN t.status <> 'Open' THEN t.status
                       WHEN (now() at time zone 'utc')::date < t.startdate THEN 'Scheduled' ELSE 'InProgress' END,
        'groups', (SELECT COALESCE(jsonb_agg(jsonb_build_object('groupId', g.groupid, 'name', g.name,
                        'head', fnlivestock_grouphead(g.groupid), 'status', g.status,
                        'suggested', fnlivestock_dose(t.dosebasis, t.dosequantity, fnlivestock_grouphead(g.groupid)))
                        ORDER BY g.name), '[]'::jsonb)
                   FROM livestocktreatmentgroups tg JOIN livestockgroups g ON g.groupid = tg.groupid
                   WHERE tg.treatmentid = t.treatmentid),
        'postedDays', (SELECT count(*) FROM livestocktreatmentdays d WHERE d.treatmentid = t.treatmentid AND d.reversedat IS NULL),
        'plannedDays', t.enddate - t.startdate + 1,
        'totalQuantity', (SELECT COALESCE(SUM(l.quantity), 0) FROM livestocktreatmentdaylines l
                          JOIN livestocktreatmentdays d ON d.dayid = l.dayid AND d.reversedat IS NULL WHERE d.treatmentid = t.treatmentid),
        'totalCost', (SELECT COALESCE(-SUM(m.totalcost), 0) FROM livestockstockmovements m
                      JOIN livestocktreatmentdays d ON m.sourcetype = 'TreatmentDay' AND m.sourceid = d.dayid
                      WHERE d.treatmentid = t.treatmentid AND m.reversedat IS NULL),
        'days', (SELECT COALESCE(jsonb_agg(jsonb_build_object('dayId', d.dayid, 'date', d.treatdate, 'notes', d.notes,
                        'postedBy', d.postedby, 'reversedAt', d.reversedat, 'reverseReason', d.reversereason,
                        'lines', (SELECT COALESCE(jsonb_agg(jsonb_build_object('groupId', l.groupid, 'groupName', g.name,
                                     'head', l.head, 'quantity', l.quantity)), '[]'::jsonb)
                                  FROM livestocktreatmentdaylines l JOIN livestockgroups g ON g.groupid = l.groupid WHERE l.dayid = d.dayid))
                        ORDER BY d.treatdate DESC, d.dayid DESC), '[]'::jsonb)
                 FROM livestocktreatmentdays d WHERE d.treatmentid = t.treatmentid),
        'createdBy', t.createdby, 'cancelReason', t.cancelreason)
    FROM livestocktreatments t JOIN livestockitems i ON i.itemid = t.itemid
    WHERE t.treatmentid = p_id;
$f$;

CREATE OR REPLACE FUNCTION public.splivestocktreatment_list(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(fnlivestock_treatmentjson(t.treatmentid) ORDER BY (t.status = 'Open') DESC, t.startdate DESC), '[]'::jsonb)
    FROM livestocktreatments t WHERE t.farmid = p_farmid;
$f$;

CREATE OR REPLACE FUNCTION public.splivestocktreatment_get(p_farmid text, p_id integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM livestocktreatments WHERE treatmentid = p_id AND farmid = p_farmid) THEN
        RAISE EXCEPTION 'That treatment was not found.' USING ERRCODE = 'P0001';
    END IF;
    RETURN fnlivestock_treatmentjson(p_id);
END
$f$;

-- {name, itemId, reason, startDate, endDate, doseQuantity, doseBasis,
--  meatWithdrawalDays, milkWithdrawalDays, eggWithdrawalDays, notes, groupIds:[]}
CREATE OR REPLACE FUNCTION public.splivestocktreatment_create(p_farmid text, p_t jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_item  livestockitems%ROWTYPE;
    v_start date := NULLIF(p_t->>'startDate', '')::date;
    v_end   date := NULLIF(p_t->>'endDate', '')::date;
    v_id    integer;
    v_gid   integer;
    v_g     livestockgroups%ROWTYPE;
BEGIN
    IF btrim(COALESCE(p_t->>'name', '')) = '' THEN
        RAISE EXCEPTION 'Give the treatment a name.' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO v_item FROM livestockitems WHERE itemid = NULLIF(p_t->>'itemId', '')::int AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND OR v_item.category NOT IN ('Medication', 'Vaccine') THEN
        RAISE EXCEPTION 'Choose the medicine or vaccine.' USING ERRCODE = 'P0001';
    END IF;
    IF v_start IS NULL OR v_end IS NULL OR v_end < v_start THEN
        RAISE EXCEPTION 'Enter a start date and an end date on or after it.' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(p_t->>'doseQuantity', '')::numeric IS NULL OR (p_t->>'doseQuantity')::numeric <= 0
       OR COALESCE(p_t->>'doseBasis', '') NOT IN ('PerAnimal', 'Per100Animals', 'PerGroup') THEN
        RAISE EXCEPTION 'Enter the dose: an amount and what it is per (per animal, per 100 animals or per group).' USING ERRCODE = 'P0001';
    END IF;
    IF jsonb_array_length(COALESCE(p_t->'groupIds', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'Choose at least one group.' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO livestocktreatments (farmid, name, itemid, reason, startdate, enddate, dosequantity, dosebasis,
        meatwithdrawaldays, milkwithdrawaldays, eggwithdrawaldays, notes, createdby)
    VALUES (p_farmid, btrim(p_t->>'name'), v_item.itemid, NULLIF(btrim(p_t->>'reason'), ''), v_start, v_end,
        (p_t->>'doseQuantity')::numeric, p_t->>'doseBasis', NULLIF(p_t->>'meatWithdrawalDays', '')::int,
        NULLIF(p_t->>'milkWithdrawalDays', '')::int, NULLIF(p_t->>'eggWithdrawalDays', '')::int,
        NULLIF(btrim(p_t->>'notes'), ''), p_by)
    RETURNING treatmentid INTO v_id;

    FOR v_gid IN SELECT DISTINCT (e #>> '{}')::int FROM jsonb_array_elements(p_t->'groupIds') e LOOP
        SELECT * INTO v_g FROM livestockgroups WHERE groupid = v_gid AND farmid = p_farmid AND NOT isdeleted;
        IF NOT FOUND OR v_g.status <> 'Active' THEN
            RAISE EXCEPTION 'Every group must be an active group of this farm.' USING ERRCODE = 'P0001';
        END IF;
        IF v_item.speciescode IS NOT NULL AND v_item.speciescode <> v_g.speciescode THEN
            RAISE EXCEPTION '% is for another kind of animal than %.', v_item.name, v_g.name USING ERRCODE = 'P0001';
        END IF;
        INSERT INTO livestocktreatmentgroups (treatmentid, groupid) VALUES (v_id, v_gid);
    END LOOP;
    RETURN v_id;
END
$f$;

-- Post a day. p_lines [{groupId, quantity}]: groups left out or with no
-- quantity get the dose for their head that day; quantity 0 = skipped today.
CREATE OR REPLACE FUNCTION public.splivestocktreatment_postday(p_farmid text, p_id integer, p_date date,
    p_lines jsonb, p_notes text, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_t    livestocktreatments%ROWTYPE;
    v_day  integer;
    v_g    record;
    v_qty  numeric;
    v_head integer;
    v_mid  integer;
    v_any  boolean := FALSE;
BEGIN
    SELECT * INTO v_t FROM livestocktreatments WHERE treatmentid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That treatment was not found.' USING ERRCODE = 'P0001';
    END IF;
    IF v_t.status <> 'Open' THEN
        RAISE EXCEPTION 'This treatment is %.', lower(v_t.status) USING ERRCODE = 'P0001';
    END IF;
    IF p_date IS NULL OR p_date < v_t.startdate OR p_date > v_t.enddate THEN
        RAISE EXCEPTION 'The day must be between % and %.', to_char(v_t.startdate, 'DD Mon'), to_char(v_t.enddate, 'DD Mon YYYY')
            USING ERRCODE = 'P0001';
    END IF;
    IF p_date > (now() at time zone 'utc')::date + 1 THEN
        RAISE EXCEPTION 'A day in the future cannot be recorded yet.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM livestocktreatmentdays WHERE treatmentid = p_id AND treatdate = p_date AND reversedat IS NULL) THEN
        RAISE EXCEPTION '% is already recorded for this treatment.', to_char(p_date, 'DD Mon YYYY') USING ERRCODE = 'P0010';
    END IF;

    INSERT INTO livestocktreatmentdays (treatmentid, treatdate, notes, postedby)
    VALUES (p_id, p_date, NULLIF(btrim(p_notes), ''), p_by) RETURNING dayid INTO v_day;

    FOR v_g IN SELECT g.* FROM livestocktreatmentgroups tg JOIN livestockgroups g ON g.groupid = tg.groupid
               WHERE tg.treatmentid = p_id ORDER BY g.groupid LOOP
        v_head := fnlivestock_groupheadasof(v_g.groupid, p_date);
        SELECT NULLIF(e->>'quantity', '')::numeric INTO v_qty FROM jsonb_array_elements(COALESCE(p_lines, '[]'::jsonb)) e
        WHERE (e->>'groupId')::int = v_g.groupid;
        IF NOT FOUND OR v_qty IS NULL THEN
            v_qty := fnlivestock_dose(v_t.dosebasis, v_t.dosequantity, v_head);
        END IF;
        CONTINUE WHEN v_qty <= 0 OR v_head <= 0 OR v_g.status <> 'Active' OR p_date < v_g.startdate;
        v_mid := splivestockstock_post(p_farmid, v_t.itemid, p_date, 'Usage', -v_qty, NULL, p_by,
                     v_t.name || ' · ' || v_g.name, 'TreatmentDay', v_day, v_g.groupid);
        INSERT INTO livestocktreatmentdaylines (dayid, groupid, head, quantity, stockmovementid)
        VALUES (v_day, v_g.groupid, v_head, v_qty, v_mid);
        v_any := TRUE;
    END LOOP;
    IF NOT v_any THEN
        RAISE EXCEPTION 'No group was dosed that day.' USING ERRCODE = 'P0001';
    END IF;
    RETURN v_day;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestocktreatment_reverseday(p_farmid text, p_dayid integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_d livestocktreatmentdays%ROWTYPE;
BEGIN
    SELECT d.* INTO v_d FROM livestocktreatmentdays d JOIN livestocktreatments t ON t.treatmentid = d.treatmentid
    WHERE d.dayid = p_dayid AND t.farmid = p_farmid FOR UPDATE OF d;
    IF NOT FOUND OR v_d.reversedat IS NOT NULL THEN
        RAISE EXCEPTION 'That day was not found or is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestocktreatmentdays SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
    WHERE dayid = p_dayid;
    PERFORM fnlivestock_reversesource('TreatmentDay', p_dayid, p_by, btrim(p_reason));
END
$f$;

-- p_action: 'Complete' or 'Cancel' (a cancel needs a reason).
CREATE OR REPLACE FUNCTION public.splivestocktreatment_close(p_farmid text, p_id integer, p_action text, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    IF p_action NOT IN ('Complete', 'Cancel') THEN
        RAISE EXCEPTION 'Unknown action.' USING ERRCODE = 'P0001';
    END IF;
    IF p_action = 'Cancel' AND NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why the treatment is cancelled.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestocktreatments SET status = CASE p_action WHEN 'Complete' THEN 'Completed' ELSE 'Cancelled' END,
        cancelreason = CASE WHEN p_action = 'Cancel' THEN btrim(p_reason) END,
        closedat = (now() at time zone 'utc'), closedby = p_by
    WHERE treatmentid = p_id AND farmid = p_farmid AND status = 'Open';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That treatment is not open.' USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- ---------------------------------------------------------------------------
-- 4. Feed formulas and mixing
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockfeedformulas (
    formulaid     serial PRIMARY KEY,
    farmid        text NOT NULL,
    name          text NOT NULL,
    outputitemid  integer NOT NULL REFERENCES livestockitems(itemid),
    batchquantity numeric(14,3) NOT NULL CHECK (batchquantity > 0),   -- in the output item's unit
    speciescode   text REFERENCES livestockspecies(speciescode),
    notes         text,
    isactive      boolean NOT NULL DEFAULT TRUE,
    isdeleted     boolean NOT NULL DEFAULT FALSE,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text
);
CREATE UNIQUE INDEX IF NOT EXISTS uxlivestockfeedformulas_name ON livestockfeedformulas (farmid, lower(btrim(name))) WHERE NOT isdeleted;
CREATE TABLE IF NOT EXISTS livestockfeedformulalines (
    lineid    serial PRIMARY KEY,
    formulaid integer NOT NULL REFERENCES livestockfeedformulas(formulaid),
    itemid    integer NOT NULL REFERENCES livestockitems(itemid),
    quantity  numeric(14,3) NOT NULL CHECK (quantity > 0)              -- per batch, in the ingredient's unit
);
CREATE TABLE IF NOT EXISTS livestockfeedruns (
    runid          serial PRIMARY KEY,
    farmid         text NOT NULL,
    formulaid      integer NOT NULL REFERENCES livestockfeedformulas(formulaid),
    rundate        date NOT NULL,
    batches        numeric(10,3) NOT NULL CHECK (batches > 0),
    outputquantity numeric(14,3) NOT NULL CHECK (outputquantity > 0),
    othercost      numeric(14,2) NOT NULL DEFAULT 0 CHECK (othercost >= 0),   -- milling, labour, transport
    notes          text,
    createdat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby      text,
    reversedat     timestamp,
    reversedby     text,
    reversereason  text
);

CREATE OR REPLACE FUNCTION public.fnlivestock_formulajson(p_id integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'formulaId', f.formulaid, 'name', f.name, 'outputItemId', f.outputitemid, 'outputItemName', o.name,
        'outputUnit', o.unit, 'batchQuantity', f.batchquantity, 'speciesCode', f.speciescode, 'notes', f.notes,
        'isActive', f.isactive,
        'lines', (SELECT COALESCE(jsonb_agg(jsonb_build_object('itemId', l.itemid, 'itemName', i.name, 'unit', i.unit,
                       'quantity', l.quantity, 'stock', fnlivestock_itemstock(i.itemid), 'avgCost', fnlivestock_itemavgcost(i.itemid))
                       ORDER BY l.quantity DESC), '[]'::jsonb)
                  FROM livestockfeedformulalines l JOIN livestockitems i ON i.itemid = l.itemid WHERE l.formulaid = f.formulaid),
        -- What one batch costs at today's average costs.
        'batchCost', (SELECT round(SUM(l.quantity * COALESCE(fnlivestock_itemavgcost(l.itemid), 0)), 2)
                      FROM livestockfeedformulalines l WHERE l.formulaid = f.formulaid),
        -- How many whole batches the ingredients in stock allow.
        'batchesPossible', (SELECT floor(MIN(fnlivestock_itemstock(l.itemid) / l.quantity))
                            FROM livestockfeedformulalines l WHERE l.formulaid = f.formulaid))
    FROM livestockfeedformulas f JOIN livestockitems o ON o.itemid = f.outputitemid
    WHERE f.formulaid = p_id;
$f$;

CREATE OR REPLACE FUNCTION public.splivestockformula_list(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(fnlivestock_formulajson(f.formulaid) ORDER BY f.isactive DESC, lower(f.name)), '[]'::jsonb)
    FROM livestockfeedformulas f WHERE f.farmid = p_farmid AND NOT f.isdeleted;
$f$;

-- {formulaId?, name, outputItemId, batchQuantity, speciesCode, notes, isActive, lines:[{itemId, quantity}]}
CREATE OR REPLACE FUNCTION public.splivestockformula_save(p_farmid text, p_f jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id   integer := NULLIF(p_f->>'formulaId', '')::int;
    v_name text    := btrim(COALESCE(p_f->>'name', ''));
    v_out  livestockitems%ROWTYPE;
    v_l    jsonb;
    v_it   livestockitems%ROWTYPE;
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Give the formula a name.' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO v_out FROM livestockitems WHERE itemid = NULLIF(p_f->>'outputItemId', '')::int AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND OR v_out.category <> 'Feed' THEN
        RAISE EXCEPTION 'Choose the feed this formula makes (a stock item of kind Feed).' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(p_f->>'batchQuantity', '')::numeric IS NULL OR (p_f->>'batchQuantity')::numeric <= 0 THEN
        RAISE EXCEPTION 'Enter how much one batch makes.' USING ERRCODE = 'P0001';
    END IF;
    IF jsonb_array_length(COALESCE(p_f->'lines', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'Add the ingredients.' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(p_f->>'speciesCode', '') IS NOT NULL THEN PERFORM fnlivestock_requirespecies(p_farmid, p_f->>'speciesCode'); END IF;
    IF EXISTS (SELECT 1 FROM livestockfeedformulas WHERE farmid = p_farmid AND NOT isdeleted
               AND lower(btrim(name)) = lower(v_name) AND formulaid IS DISTINCT FROM v_id) THEN
        RAISE EXCEPTION 'You already have a formula called "%".', v_name USING ERRCODE = 'P0001';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO livestockfeedformulas (farmid, name, outputitemid, batchquantity, speciescode, notes, createdby)
        VALUES (p_farmid, v_name, v_out.itemid, (p_f->>'batchQuantity')::numeric, NULLIF(p_f->>'speciesCode', ''),
                NULLIF(btrim(p_f->>'notes'), ''), p_by) RETURNING formulaid INTO v_id;
    ELSE
        UPDATE livestockfeedformulas SET name = v_name, outputitemid = v_out.itemid, batchquantity = (p_f->>'batchQuantity')::numeric,
            speciescode = NULLIF(p_f->>'speciesCode', ''), notes = NULLIF(btrim(p_f->>'notes'), ''),
            isactive = COALESCE((p_f->>'isActive')::boolean, isactive)
        WHERE formulaid = v_id AND farmid = p_farmid AND NOT isdeleted;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That formula was not found.' USING ERRCODE = 'P0001';
        END IF;
        DELETE FROM livestockfeedformulalines WHERE formulaid = v_id;
    END IF;
    FOR v_l IN SELECT * FROM jsonb_array_elements(p_f->'lines') LOOP
        SELECT * INTO v_it FROM livestockitems WHERE itemid = NULLIF(v_l->>'itemId', '')::int AND farmid = p_farmid AND NOT isdeleted;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Choose the item on every ingredient line.' USING ERRCODE = 'P0001';
        END IF;
        IF v_it.itemid = v_out.itemid THEN
            RAISE EXCEPTION 'A feed cannot be an ingredient of itself.' USING ERRCODE = 'P0001';
        END IF;
        IF v_it.category NOT IN ('Ingredient', 'Feed', 'Medication', 'Other') THEN
            RAISE EXCEPTION '% cannot go into feed.', v_it.name USING ERRCODE = 'P0001';
        END IF;
        IF NULLIF(v_l->>'quantity', '')::numeric IS NULL OR (v_l->>'quantity')::numeric <= 0 THEN
            RAISE EXCEPTION 'Enter how much % goes into one batch.', v_it.name USING ERRCODE = 'P0001';
        END IF;
        IF EXISTS (SELECT 1 FROM livestockfeedformulalines WHERE formulaid = v_id AND itemid = v_it.itemid) THEN
            RAISE EXCEPTION '% is listed twice.', v_it.name USING ERRCODE = 'P0001';
        END IF;
        INSERT INTO livestockfeedformulalines (formulaid, itemid, quantity) VALUES (v_id, v_it.itemid, (v_l->>'quantity')::numeric);
    END LOOP;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockformula_delete(p_farmid text, p_id integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    IF EXISTS (SELECT 1 FROM livestockfeedruns WHERE formulaid = p_id AND reversedat IS NULL) THEN
        RAISE EXCEPTION 'Feed has been mixed with this formula. Mark it unused instead.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockfeedformulas SET isdeleted = TRUE WHERE formulaid = p_id AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That formula was not found.' USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- Mix p_batches batches. Output defaults to batches x batch quantity (a
-- different actual yield may be entered). All or nothing.
CREATE OR REPLACE FUNCTION public.splivestockfeedrun_post(p_farmid text, p_formulaid integer, p_date date, p_batches numeric,
    p_outputquantity numeric, p_othercost numeric, p_notes text, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_f    livestockfeedformulas%ROWTYPE;
    v_run  integer;
    v_l    record;
    v_cost numeric := 0;
    v_mid  integer;
    v_out  numeric;
BEGIN
    SELECT * INTO v_f FROM livestockfeedformulas WHERE formulaid = p_formulaid AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND OR NOT v_f.isactive THEN
        RAISE EXCEPTION 'Choose a formula in use.' USING ERRCODE = 'P0001';
    END IF;
    IF p_batches IS NULL OR p_batches <= 0 THEN
        RAISE EXCEPTION 'Enter how many batches were mixed.' USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(p_othercost, 0) < 0 THEN
        RAISE EXCEPTION 'Other costs cannot be negative.' USING ERRCODE = 'P0001';
    END IF;
    v_out := COALESCE(NULLIF(p_outputquantity, 0), round(v_f.batchquantity * p_batches, 3));
    IF v_out <= 0 THEN
        RAISE EXCEPTION 'Enter how much feed came out.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO livestockfeedruns (farmid, formulaid, rundate, batches, outputquantity, othercost, notes, createdby)
    VALUES (p_farmid, p_formulaid, p_date, p_batches, v_out, COALESCE(p_othercost, 0), NULLIF(btrim(p_notes), ''), p_by)
    RETURNING runid INTO v_run;
    FOR v_l IN SELECT l.*, i.name FROM livestockfeedformulalines l JOIN livestockitems i ON i.itemid = l.itemid WHERE l.formulaid = p_formulaid LOOP
        v_mid := splivestockstock_post(p_farmid, v_l.itemid, p_date, 'Usage', -round(v_l.quantity * p_batches, 3), NULL, p_by,
                     'Mixed into ' || v_f.name, 'FeedRun', v_run);
        v_cost := v_cost - (SELECT totalcost FROM livestockstockmovements WHERE movementid = v_mid);
    END LOOP;
    v_cost := v_cost + COALESCE(p_othercost, 0);
    PERFORM splivestockstock_post(p_farmid, v_f.outputitemid, p_date, 'Produced', v_out, v_cost / v_out, p_by,
        'Mixed: ' || trim_scale(p_batches) || ' batch(es) of ' || v_f.name, 'FeedRun', v_run);
    RETURN v_run;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockfeedrun_list(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'runId', r.runid, 'formulaId', r.formulaid, 'formulaName', f.name, 'date', r.rundate, 'batches', r.batches,
        'outputQuantity', r.outputquantity, 'outputItemName', o.name, 'outputUnit', o.unit, 'otherCost', r.othercost,
        'totalCost', (SELECT totalcost FROM livestockstockmovements m WHERE m.sourcetype = 'FeedRun' AND m.sourceid = r.runid
                      AND m.movementtype = 'Produced' ORDER BY m.movementid DESC LIMIT 1),
        'unitCost', (SELECT unitcost FROM livestockstockmovements m WHERE m.sourcetype = 'FeedRun' AND m.sourceid = r.runid
                      AND m.movementtype = 'Produced' ORDER BY m.movementid DESC LIMIT 1),
        'notes', r.notes, 'createdBy', r.createdby, 'reversedAt', r.reversedat, 'reverseReason', r.reversereason)
        ORDER BY r.rundate DESC, r.runid DESC), '[]'::jsonb)
    FROM livestockfeedruns r JOIN livestockfeedformulas f ON f.formulaid = r.formulaid JOIN livestockitems o ON o.itemid = f.outputitemid
    WHERE r.farmid = p_farmid;
$f$;

CREATE OR REPLACE FUNCTION public.splivestockfeedrun_reverse(p_farmid text, p_runid integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_r livestockfeedruns%ROWTYPE; v_f livestockfeedformulas%ROWTYPE;
BEGIN
    SELECT * INTO v_r FROM livestockfeedruns WHERE runid = p_runid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND OR v_r.reversedat IS NOT NULL THEN
        RAISE EXCEPTION 'That mixing run was not found or is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO v_f FROM livestockfeedformulas WHERE formulaid = v_r.formulaid;
    IF fnlivestock_itemstock(v_f.outputitemid) < v_r.outputquantity THEN
        RAISE EXCEPTION 'Some of this feed has already been used, so the mixing cannot be reversed.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockfeedruns SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
    WHERE runid = p_runid;
    PERFORM fnlivestock_reversesource('FeedRun', p_runid, p_by, btrim(p_reason));
END
$f$;

-- ---------------------------------------------------------------------------
-- 5. Feeding many groups at once
-- ---------------------------------------------------------------------------
-- p_lines [{groupId, quantity}]. Each adds a feed line to that group's record
-- for the day (merging into an existing line of the same feed).
CREATE OR REPLACE FUNCTION public.splivestockfeed_distribute(p_farmid text, p_date date, p_itemid integer, p_lines jsonb, p_by text)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    v_l     jsonb;
    v_gid   integer;
    v_qty   numeric;
    v_rid   integer;
    v_rec   jsonb;
    v_feed  jsonb;
    v_meds  jsonb;
    v_done  jsonb := '[]'::jsonb;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM livestockitems WHERE itemid = p_itemid AND farmid = p_farmid AND category = 'Feed' AND NOT isdeleted) THEN
        RAISE EXCEPTION 'Choose the feed.' USING ERRCODE = 'P0001';
    END IF;
    FOR v_l IN SELECT * FROM jsonb_array_elements(COALESCE(p_lines, '[]'::jsonb)) LOOP
        v_gid := NULLIF(v_l->>'groupId', '')::int;
        v_qty := NULLIF(v_l->>'quantity', '')::numeric;
        CONTINUE WHEN v_qty IS NULL OR v_qty = 0;
        IF v_qty < 0 THEN
            RAISE EXCEPTION 'Quantities cannot be negative.' USING ERRCODE = 'P0001';
        END IF;
        SELECT recordid INTO v_rid FROM livestockproductionrecords WHERE groupid = v_gid AND recorddate = p_date AND NOT isdeleted;
        IF v_rid IS NULL THEN
            v_rid := splivestockproduction_save(p_farmid, jsonb_build_object('groupId', v_gid, 'date', p_date,
                        'feedLines', jsonb_build_array(jsonb_build_object('itemId', p_itemid, 'quantity', v_qty))), p_by);
        ELSE
            v_rec := fnlivestock_recordjson(v_rid);
            SELECT COALESCE(jsonb_agg(jsonb_build_object('itemId', l->'itemId', 'quantity', l->'quantity', 'notes', l->'notes')), '[]'::jsonb)
                INTO v_meds FROM jsonb_array_elements(v_rec->'lines') l WHERE l->>'lineType' = 'Medication';
            SELECT COALESCE(jsonb_agg(jsonb_build_object('itemId', x.itemid, 'quantity', x.qty)), '[]'::jsonb) INTO v_feed
            FROM (SELECT (l->>'itemId')::int AS itemid, SUM((l->>'quantity')::numeric) AS qty
                  FROM (SELECT l FROM jsonb_array_elements(v_rec->'lines') l WHERE l->>'lineType' = 'Feed'
                        UNION ALL SELECT jsonb_build_object('itemId', p_itemid, 'quantity', v_qty)) s(l)
                  GROUP BY 1) x;
            PERFORM splivestockproduction_save(p_farmid, (v_rec - 'lines') || jsonb_build_object(
                'feedLines', v_feed, 'medicationLines', v_meds), p_by);
        END IF;
        v_done := v_done || jsonb_build_object('groupId', v_gid, 'recordId', v_rid, 'quantity', v_qty);
    END LOOP;
    IF jsonb_array_length(v_done) = 0 THEN
        RAISE EXCEPTION 'Enter a quantity for at least one group.' USING ERRCODE = 'P0001';
    END IF;
    RETURN v_done;
END
$f$;

-- ---------------------------------------------------------------------------
-- 6. Days of supply
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.splivestock_daysofsupply(p_farmid text, p_window integer DEFAULT 14)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH u AS (
        SELECT i.itemid, i.name, i.category, i.unit, fnlivestock_itemstock(i.itemid) AS stock,
               (SELECT COALESCE(-SUM(m.quantity), 0) FROM livestockstockmovements m
                WHERE m.itemid = i.itemid AND m.reversedat IS NULL AND m.movementtype = 'Usage'
                  AND m.movementdate > (now() at time zone 'utc')::date - p_window) / p_window::numeric AS perday
        FROM livestockitems i
        WHERE i.farmid = p_farmid AND NOT i.isdeleted AND i.isactive AND i.category IN ('Feed', 'Ingredient')
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'itemId', u.itemid, 'name', u.name, 'category', u.category, 'unit', u.unit, 'stock', u.stock,
        'usedPerDay', round(u.perday, 3),
        'daysLeft', CASE WHEN u.perday > 0 THEN floor(u.stock / u.perday) END,
        'runsOutOn', CASE WHEN u.perday > 0 THEN (now() at time zone 'utc')::date + floor(u.stock / u.perday)::int END)
        ORDER BY CASE WHEN u.perday > 0 THEN u.stock / u.perday END NULLS LAST, u.name), '[]'::jsonb)
    FROM u;
$f$;

-- ---------------------------------------------------------------------------
-- 7. Alerts
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.splivestock_alerts(p_farmid text)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE
    v_today date := (now() at time zone 'utc')::date;
    v_out   jsonb := '[]'::jsonb;
    r       record;
BEGIN
    -- High deaths: the last two days against the group's own normal.
    FOR r IN
        SELECT g.groupid, g.name, x.recorddate, x.deaths, x.head,
               (SELECT AVG(p.deaths) FROM livestockproductionrecords p WHERE p.groupid = g.groupid AND NOT p.isdeleted
                AND p.recorddate BETWEEN x.recorddate - 15 AND x.recorddate - 1) AS normal
        FROM livestockgroups g
        JOIN LATERAL (SELECT p.recorddate, p.deaths, fnlivestock_groupheadasof(g.groupid, p.recorddate - 1) AS head
                      FROM livestockproductionrecords p WHERE p.groupid = g.groupid AND NOT p.isdeleted
                        AND p.recorddate >= v_today - 1 ORDER BY p.recorddate DESC LIMIT 1) x ON TRUE
        WHERE g.farmid = p_farmid AND g.status = 'Active' AND NOT g.isdeleted
    LOOP
        IF r.deaths >= 2 AND (r.deaths >= 3 * COALESCE(r.normal, 0) + 1 OR (r.head > 0 AND r.deaths::numeric / r.head >= 0.02)) THEN
            v_out := v_out || jsonb_build_object('severity', 'High', 'kind', 'Deaths', 'groupId', r.groupid,
                'title', r.name || ': ' || r.deaths || ' died',
                'message', CASE WHEN r.normal IS NOT NULL THEN 'Usually about ' || round(r.normal, 1) || ' a day.' ELSE 'Check the group today.' END,
                'href', '/livestock-groups/' || r.groupid, 'date', r.recorddate);
        END IF;
    END LOOP;

    -- Eggs or milk falling: the latest record below 80% of the 7 before it.
    FOR r IN
        SELECT g.groupid, g.name, s.produceseggs, s.producesmilk, x.*
        FROM livestockgroups g JOIN livestockspecies s ON s.speciescode = g.speciescode
        JOIN LATERAL (SELECT p.recorddate, p.eggscollected, p.milklitres,
                (SELECT AVG(q.eggscollected) FROM (SELECT eggscollected FROM livestockproductionrecords q
                    WHERE q.groupid = g.groupid AND NOT q.isdeleted AND q.recorddate < p.recorddate AND q.eggscollected IS NOT NULL
                    ORDER BY q.recorddate DESC LIMIT 7) q HAVING count(*) >= 3) AS eggnormal,
                (SELECT AVG(q.milklitres) FROM (SELECT milklitres FROM livestockproductionrecords q
                    WHERE q.groupid = g.groupid AND NOT q.isdeleted AND q.recorddate < p.recorddate AND q.milklitres IS NOT NULL
                    ORDER BY q.recorddate DESC LIMIT 7) q HAVING count(*) >= 3) AS milknormal
              FROM livestockproductionrecords p WHERE p.groupid = g.groupid AND NOT p.isdeleted AND p.recorddate >= v_today - 2
              ORDER BY p.recorddate DESC LIMIT 1) x ON TRUE
        WHERE g.farmid = p_farmid AND g.status = 'Active' AND NOT g.isdeleted AND (s.produceseggs OR s.producesmilk)
    LOOP
        IF r.eggscollected IS NOT NULL AND r.eggnormal > 0 AND r.eggscollected < 0.8 * r.eggnormal THEN
            v_out := v_out || jsonb_build_object('severity', 'Medium', 'kind', 'Eggs', 'groupId', r.groupid,
                'title', r.name || ': eggs down to ' || r.eggscollected,
                'message', 'Usually about ' || round(r.eggnormal) || ' a day.', 'href', '/livestock-groups/' || r.groupid, 'date', r.recorddate);
        END IF;
        IF r.milklitres IS NOT NULL AND r.milknormal > 0 AND r.milklitres < 0.8 * r.milknormal THEN
            v_out := v_out || jsonb_build_object('severity', 'Medium', 'kind', 'Milk', 'groupId', r.groupid,
                'title', r.name || ': milk down to ' || trim_scale(r.milklitres) || ' L',
                'message', 'Usually about ' || round(r.milknormal, 1) || ' L a day.', 'href', '/livestock-groups/' || r.groupid, 'date', r.recorddate);
        END IF;
    END LOOP;

    -- No record for two days or more.
    FOR r IN
        SELECT g.groupid, g.name, (SELECT max(p.recorddate) FROM livestockproductionrecords p WHERE p.groupid = g.groupid AND NOT p.isdeleted) AS last
        FROM livestockgroups g
        WHERE g.farmid = p_farmid AND g.status = 'Active' AND NOT g.isdeleted AND fnlivestock_grouphead(g.groupid) > 0
          AND g.startdate <= v_today - 2
    LOOP
        IF r.last IS NULL OR r.last <= v_today - 2 THEN
            v_out := v_out || jsonb_build_object('severity', 'Medium', 'kind', 'MissingRecords', 'groupId', r.groupid,
                'title', r.name || ': no daily record ' || CASE WHEN r.last IS NULL THEN 'yet' ELSE 'since ' || to_char(r.last, 'DD Mon') END,
                'message', 'Record its deaths, produce and feed.', 'href', '/livestock-production-records/new?groupId=' || r.groupid,
                'date', r.last);
        END IF;
    END LOOP;

    -- Stock low, or running out within a week.
    FOR r IN SELECT i.itemid, i.name, i.unit, fnlivestock_itemstock(i.itemid) AS stock, i.minimumstock
             FROM livestockitems i WHERE i.farmid = p_farmid AND i.isactive AND NOT i.isdeleted
               AND i.minimumstock IS NOT NULL AND fnlivestock_itemstock(i.itemid) <= i.minimumstock
    LOOP
        v_out := v_out || jsonb_build_object('severity', 'Medium', 'kind', 'LowStock', 'itemId', r.itemid,
            'title', r.name || ' is low: ' || trim_scale(r.stock) || ' ' || r.unit || ' left',
            'message', 'You asked to be told at ' || trim_scale(r.minimumstock) || ' ' || r.unit || '.', 'href', '/livestock-items/' || r.itemid);
    END LOOP;
    FOR r IN SELECT (e->>'itemId')::int AS itemid, e->>'name' AS name, (e->>'daysLeft')::int AS days
             FROM jsonb_array_elements(splivestock_daysofsupply(p_farmid)) e
             WHERE (e->>'daysLeft')::int < 7
    LOOP
        v_out := v_out || jsonb_build_object('severity', CASE WHEN r.days <= 2 THEN 'High' ELSE 'Medium' END, 'kind', 'RunningOut',
            'itemId', r.itemid, 'title', r.name || ' runs out in about ' || r.days || ' day(s)',
            'message', 'At the rate it has been used over the last two weeks.', 'href', '/livestock-feed-supply');
    END LOOP;

    -- Births due within a week or overdue.
    FOR r IN SELECT x.value AS e FROM jsonb_array_elements(splivestockbreeding_due(p_farmid)) x WHERE (x.value->>'daysToDue')::int <= 7
    LOOP
        v_out := v_out || jsonb_build_object('severity', CASE WHEN (r.e->>'daysToDue')::int < 0 THEN 'Medium' ELSE 'Info' END,
            'kind', 'BirthDue', 'title', 'Tag ' || (r.e->>'damTag') || ': ' || lower(COALESCE(r.e->>'birthTerm', 'birth')) ||
                CASE WHEN (r.e->>'daysToDue')::int < 0 THEN ' overdue' WHEN (r.e->>'daysToDue')::int = 0 THEN ' due today'
                     ELSE ' due in ' || (r.e->>'daysToDue') || ' day(s)' END,
            'message', 'Mated ' || to_char((r.e->>'date')::date, 'DD Mon') || '.', 'href', '/livestock-breeding');
    END LOOP;

    -- Vaccinations overdue or due within 3 days.
    FOR r IN SELECT x.value AS e FROM jsonb_array_elements(splivestockvaccination_due(p_farmid, 3)) x
    LOOP
        v_out := v_out || jsonb_build_object('severity', CASE WHEN r.e->>'status' = 'Overdue' THEN 'Medium' ELSE 'Info' END,
            'kind', 'Vaccination', 'groupId', (r.e->>'groupId')::int,
            'title', (r.e->>'groupName') || ': ' || (r.e->>'name') ||
                CASE WHEN r.e->>'status' = 'Overdue' THEN ' overdue' ELSE ' due ' || to_char((r.e->>'due')::date, 'DD Mon') END,
            'message', 'Give it and mark it done on the vaccination page.', 'href', '/livestock-vaccinations');
    END LOOP;

    -- Under a withdrawal period.
    FOR r IN SELECT x.value AS e FROM jsonb_array_elements(splivestockwithdrawals(p_farmid)) x
    LOOP
        v_out := v_out || jsonb_build_object('severity', 'Info', 'kind', 'Withdrawal', 'groupId', (r.e->>'groupId')::int,
            'title', (r.e->>'groupName') || ': do not sell ' ||
                concat_ws(', ', CASE WHEN (r.e->>'meatUntil')::date >= v_today THEN 'meat until ' || to_char((r.e->>'meatUntil')::date, 'DD Mon') END,
                                CASE WHEN (r.e->>'milkUntil')::date >= v_today THEN 'milk until ' || to_char((r.e->>'milkUntil')::date, 'DD Mon') END,
                                CASE WHEN (r.e->>'eggsUntil')::date >= v_today THEN 'eggs until ' || to_char((r.e->>'eggsUntil')::date, 'DD Mon') END),
            'message', 'Treated with ' || (r.e->>'itemName') || ' (' || (r.e->>'treatmentName') || ').',
            'href', '/livestock-treatments/' || (r.e->>'treatmentId'));
    END LOOP;

    RETURN (SELECT COALESCE(jsonb_agg(a ORDER BY CASE a->>'severity' WHEN 'High' THEN 0 WHEN 'Medium' THEN 1 ELSE 2 END), '[]'::jsonb)
            FROM jsonb_array_elements(v_out) a);
END
$f$;

-- ---------------------------------------------------------------------------
-- 8. IAM
-- ---------------------------------------------------------------------------
DO $iam$
DECLARE v integer := 0;
BEGIN
    v := v + splivestock_iammirror('health', 'health', 'Health', 'Health Records',
            'Illness, treatment, vaccination and vet visits on groups and animals.', 40);
    v := v + splivestock_iammirror('vaccination', 'health', 'Health', 'Vaccination Plans',
            'Vaccination and deworming plans, and what is due.', 41);
    v := v + splivestock_iammirror('treatments', 'medication', 'Health', 'Treatment Campaigns',
            'One medicine for several groups over several days; withdrawal periods.', 42);
    v := v + splivestock_iammirror('feed-formulas', 'feed-formulas', 'Feed & Stock', 'Feed Formulas',
            'Recipes that turn ingredients into feed.', 31);
    v := v + splivestock_iammirror('feed-production', 'feed-production', 'Feed & Stock', 'Feed Mixing',
            'Mixing feed: ingredients out, finished feed in.', 32);
    v := v + splivestock_iammirror('alerts', 'flocks', 'Animals', 'Alerts',
            'Deaths, falling produce, missing records, stock and health reminders.', 15);
    RAISE NOTICE '460: % livestock permission key(s) added.', v;
END
$iam$;

COMMIT;

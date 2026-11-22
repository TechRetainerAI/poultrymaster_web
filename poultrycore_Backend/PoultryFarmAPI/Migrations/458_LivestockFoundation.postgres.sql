-- 458: Livestock foundation -- species, pens, intake batches, groups, tagged
--      animals and the head ledger.
--
-- Livestock is the sixth company type (farms.type = 'Livestock'): the poultry
-- module tree cloned for ducks, guinea fowl, turkeys, quail, geese, rabbits,
-- grasscutters, goats, sheep, pigs and cattle. Its own tables (livestock*) and
-- functions (splivestock*); nothing here reads or writes a poultry table.
--
-- 1. livestockspecies -- a fixed catalogue, one row per species. Every label a
--    page shows (Hutch / Kraal, Kindling / Calving, Kits / Calves) and every
--    species-gated page (eggs, milk, breeding) comes from here. A page never
--    hardcodes a species.
-- 2. livestockfarmspecies -- which species a farm keeps.
-- 3. livestockpens -- the poultry "house" (pen / hutch / sty / kraal / paddock).
-- 4. livestockbatches -- an intake: animals bought or brought in together. Like
--    a poultry flock batch, it is divided into groups.
-- 5. livestockgroups -- the poultry "flock": animals kept and recorded together.
-- 6. livestockanimals -- the optional tagged register (tag, sex, dam, sire).
--    Every animal belongs to a group; a group may hold untagged head too.
-- 7. livestockheadmovements -- THE head count. A group's head is the sum of its
--    unreversed movements, and nothing else. Poultry's bird count grew a
--    quantity column, then a position function, then a ledger and a check
--    function to keep them agreeing (319, 413, 437, 438); here there is one
--    source from the start. Movements are never deleted -- a mistake is
--    reversed (reversedat), so the history stays readable.
-- 8. IAM: livestock.<resource>.<action> keys, each granted to exactly the roles
--    and users that hold its poultry twin (houses -> pens, flocks -> groups ...).
--
-- Every function returns jsonb with camelCase keys, ready for the web app, and
-- refuses with a plain-English message (ERRCODE P0001).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Species catalogue
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockspecies (
    speciescode     text PRIMARY KEY,
    name            text NOT NULL,          -- "Goats"
    singular        text NOT NULL,          -- "Goat"
    category        text NOT NULL CHECK (category IN ('Bird', 'SmallMammal', 'Ruminant', 'Large')),
    produceseggs    boolean NOT NULL DEFAULT FALSE,
    producesmilk    boolean NOT NULL DEFAULT FALSE,
    breedsonfarm    boolean NOT NULL DEFAULT FALSE,  -- mated and born on the farm (births, litters)
    defaulttracking text NOT NULL CHECK (defaulttracking IN ('Group', 'Individual')),
    penterm         text NOT NULL,          -- "Hutch"
    groupterm       text NOT NULL,          -- "Herd"
    birthterm       text,                   -- "Kidding"
    youngterm       text,                   -- "Kids"
    gestationdays   integer,                -- incubation days for birds
    weaningdays     integer,
    sortorder       integer NOT NULL DEFAULT 0
);

INSERT INTO livestockspecies
    (speciescode, name, singular, category, produceseggs, producesmilk, breedsonfarm, defaulttracking,
     penterm, groupterm, birthterm, youngterm, gestationdays, weaningdays, sortorder)
VALUES
    ('duck',        'Ducks',        'Duck',        'Bird',        TRUE,  FALSE, FALSE, 'Group',      'House',  'Flock', 'Hatching',  'Ducklings', 28,  NULL, 10),
    ('guinea_fowl', 'Guinea fowl',  'Guinea fowl', 'Bird',        TRUE,  FALSE, FALSE, 'Group',      'House',  'Flock', 'Hatching',  'Keets',     26,  NULL, 20),
    ('turkey',      'Turkeys',      'Turkey',      'Bird',        TRUE,  FALSE, FALSE, 'Group',      'House',  'Flock', 'Hatching',  'Poults',    28,  NULL, 30),
    ('quail',       'Quail',        'Quail',       'Bird',        TRUE,  FALSE, FALSE, 'Group',      'Cage',   'Flock', 'Hatching',  'Chicks',    17,  NULL, 40),
    ('goose',       'Geese',        'Goose',       'Bird',        TRUE,  FALSE, FALSE, 'Group',      'House',  'Flock', 'Hatching',  'Goslings',  30,  NULL, 50),
    ('rabbit',      'Rabbits',      'Rabbit',      'SmallMammal', FALSE, FALSE, TRUE,  'Group',      'Hutch',  'Group', 'Kindling',  'Kits',      31,  35,   60),
    ('grasscutter', 'Grasscutters', 'Grasscutter', 'SmallMammal', FALSE, FALSE, TRUE,  'Group',      'Cage',   'Group', 'Littering', 'Pups',      152, 40,   70),
    ('goat',        'Goats',        'Goat',        'Ruminant',    FALSE, TRUE,  TRUE,  'Individual', 'Pen',    'Herd',  'Kidding',   'Kids',      150, 90,   80),
    ('sheep',       'Sheep',        'Sheep',       'Ruminant',    FALSE, TRUE,  TRUE,  'Individual', 'Pen',    'Flock', 'Lambing',   'Lambs',     147, 90,   90),
    ('pig',         'Pigs',         'Pig',         'Large',       FALSE, FALSE, TRUE,  'Individual', 'Sty',    'Group', 'Farrowing', 'Piglets',   114, 28,  100),
    ('cattle',      'Cattle',       'Cow',         'Large',       FALSE, TRUE,  TRUE,  'Individual', 'Kraal',  'Herd',  'Calving',   'Calves',    283, 210, 110)
ON CONFLICT (speciescode) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. The species a farm keeps
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockfarmspecies (
    farmid      text NOT NULL,
    speciescode text NOT NULL REFERENCES livestockspecies(speciescode),
    enabledat   timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    enabledby   text,
    PRIMARY KEY (farmid, speciescode)
);

-- ---------------------------------------------------------------------------
-- 3. Pens
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockpens (
    penid       serial PRIMARY KEY,
    farmid      text NOT NULL,
    name        text NOT NULL,
    speciescode text REFERENCES livestockspecies(speciescode),  -- NULL = any species
    capacity    integer CHECK (capacity IS NULL OR capacity >= 0),
    location    text,
    notes       text,
    isactive    boolean NOT NULL DEFAULT TRUE,
    isdeleted   boolean NOT NULL DEFAULT FALSE,
    createdat   timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby   text,
    updatedat   timestamp,
    updatedby   text
);
CREATE UNIQUE INDEX IF NOT EXISTS uxlivestockpens_name
    ON livestockpens (farmid, lower(btrim(name))) WHERE NOT isdeleted;

-- ---------------------------------------------------------------------------
-- 4. Intake batches
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockbatches (
    batchid      serial PRIMARY KEY,
    farmid       text NOT NULL,
    batchcode    text NOT NULL,
    speciescode  text NOT NULL REFERENCES livestockspecies(speciescode),
    breed        text,
    quantity     integer NOT NULL CHECK (quantity > 0),
    intakedate   date NOT NULL,
    source       text NOT NULL DEFAULT 'Purchased' CHECK (source IN ('Purchased', 'Gift', 'Transfer', 'Other')),
    supplierid   integer,
    costperhead  numeric(18,2) CHECK (costperhead IS NULL OR costperhead >= 0),
    totalcost    numeric(18,2) CHECK (totalcost IS NULL OR totalcost >= 0),
    ageatintake  text,          -- "8 weeks", "Point of lay", "Weaners"
    notes        text,
    isdeleted    boolean NOT NULL DEFAULT FALSE,
    createdat    timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby    text,
    updatedat    timestamp,
    updatedby    text
);
CREATE UNIQUE INDEX IF NOT EXISTS uxlivestockbatches_code
    ON livestockbatches (farmid, lower(batchcode)) WHERE NOT isdeleted;

-- ---------------------------------------------------------------------------
-- 5. Groups
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockgroups (
    groupid      serial PRIMARY KEY,
    farmid       text NOT NULL,
    speciescode  text NOT NULL REFERENCES livestockspecies(speciescode),
    name         text NOT NULL,
    penid        integer REFERENCES livestockpens(penid),
    batchid      integer REFERENCES livestockbatches(batchid),
    breed        text,
    purpose      text NOT NULL DEFAULT 'Meat' CHECK (purpose IN ('Meat', 'Eggs', 'Milk', 'Breeding', 'Mixed')),
    startdate    date NOT NULL,
    ageatstartdays integer CHECK (ageatstartdays IS NULL OR ageatstartdays >= 0),  -- how old the animals were on startdate
    status       text NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Closed')),
    closeddate   date,
    closereason  text,
    notes        text,
    isdeleted    boolean NOT NULL DEFAULT FALSE,
    createdat    timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby    text,
    updatedat    timestamp,
    updatedby    text
);
CREATE UNIQUE INDEX IF NOT EXISTS uxlivestockgroups_name
    ON livestockgroups (farmid, lower(btrim(name))) WHERE NOT isdeleted;
CREATE INDEX IF NOT EXISTS ixlivestockgroups_farm ON livestockgroups (farmid, status) WHERE NOT isdeleted;

-- ---------------------------------------------------------------------------
-- 6. Tagged animals
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockanimals (
    animalid      serial PRIMARY KEY,
    farmid        text NOT NULL,
    groupid       integer NOT NULL REFERENCES livestockgroups(groupid),
    speciescode   text NOT NULL REFERENCES livestockspecies(speciescode),
    tagnumber     text NOT NULL,
    name          text,
    sex           text NOT NULL DEFAULT 'Unknown' CHECK (sex IN ('Female', 'Male', 'Unknown')),
    breed         text,
    birthdate     date,
    damid         integer REFERENCES livestockanimals(animalid),
    sireid        integer REFERENCES livestockanimals(animalid),
    source        text NOT NULL DEFAULT 'OnFarm' CHECK (source IN ('OnFarm', 'Purchased', 'BornOnFarm', 'Other')),
    acquireddate  date,
    purchasecost  numeric(18,2) CHECK (purchasecost IS NULL OR purchasecost >= 0),
    status        text NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Sold', 'Dead', 'Culled')),
    statusdate    date,
    statusnotes   text,
    notes         text,
    isdeleted     boolean NOT NULL DEFAULT FALSE,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    updatedat     timestamp,
    updatedby     text,
    CHECK (damid IS NULL OR damid <> animalid),
    CHECK (sireid IS NULL OR sireid <> animalid)
);
CREATE UNIQUE INDEX IF NOT EXISTS uxlivestockanimals_tag
    ON livestockanimals (farmid, lower(btrim(tagnumber))) WHERE NOT isdeleted;
CREATE INDEX IF NOT EXISTS ixlivestockanimals_group ON livestockanimals (groupid) WHERE NOT isdeleted;

-- ---------------------------------------------------------------------------
-- 7. The head ledger
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockheadmovements (
    movementid    serial PRIMARY KEY,
    farmid        text NOT NULL,
    groupid       integer NOT NULL REFERENCES livestockgroups(groupid),
    movementdate  date NOT NULL,
    movementtype  text NOT NULL CHECK (movementtype IN
                    ('Opening', 'Intake', 'Birth', 'TransferIn', 'Death', 'Cull', 'Sale', 'TransferOut', 'Correction')),
    quantity      integer NOT NULL CHECK (quantity <> 0),   -- signed: + into the group, - out of it
    batchid       integer REFERENCES livestockbatches(batchid),
    animalid      integer REFERENCES livestockanimals(animalid),
    pairedmovementid integer REFERENCES livestockheadmovements(movementid),  -- the other half of a transfer
    sourcetype    text,       -- 'ProductionRecord', 'Sale', 'BirthEvent' ... (later steps)
    sourceid      integer,
    notes         text,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text,
    CHECK (
        (movementtype IN ('Opening', 'Intake', 'Birth', 'TransferIn') AND quantity > 0) OR
        (movementtype IN ('Death', 'Cull', 'Sale', 'TransferOut') AND quantity < 0) OR
        movementtype = 'Correction'
    )
);
CREATE INDEX IF NOT EXISTS ixlivestockheadmovements_group
    ON livestockheadmovements (groupid, movementdate) WHERE reversedat IS NULL;
CREATE INDEX IF NOT EXISTS ixlivestockheadmovements_batch
    ON livestockheadmovements (batchid) WHERE reversedat IS NULL AND batchid IS NOT NULL;

-- A group's live head. The only definition.
CREATE OR REPLACE FUNCTION public.fnlivestock_grouphead(p_groupid integer)
 RETURNS integer LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(SUM(quantity), 0)::int FROM livestockheadmovements
    WHERE groupid = p_groupid AND reversedat IS NULL;
$f$;

-- Head at the end of a date.
CREATE OR REPLACE FUNCTION public.fnlivestock_groupheadasof(p_groupid integer, p_date date)
 RETURNS integer LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(SUM(quantity), 0)::int FROM livestockheadmovements
    WHERE groupid = p_groupid AND reversedat IS NULL AND movementdate <= p_date;
$f$;

-- Head a batch has already put into groups.
CREATE OR REPLACE FUNCTION public.fnlivestock_batchallocated(p_batchid integer)
 RETURNS integer LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(SUM(quantity), 0)::int FROM livestockheadmovements
    WHERE batchid = p_batchid AND movementtype = 'Intake' AND reversedat IS NULL;
$f$;

-- Posts one movement and refuses one that would leave the group below zero
-- head, or below the number of its tagged animals still alive.
CREATE OR REPLACE FUNCTION public.splivestockhead_post(
    p_farmid text, p_groupid integer, p_date date, p_type text, p_quantity integer,
    p_by text, p_notes text DEFAULT NULL, p_batchid integer DEFAULT NULL, p_animalid integer DEFAULT NULL,
    p_sourcetype text DEFAULT NULL, p_sourceid integer DEFAULT NULL)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_group  livestockgroups%ROWTYPE;
    v_after  integer;
    v_tagged integer;
    v_id     integer;
BEGIN
    SELECT * INTO v_group FROM livestockgroups
    WHERE groupid = p_groupid AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That group was not found.' USING ERRCODE = 'P0001';
    END IF;
    IF p_quantity IS NULL OR p_quantity = 0 THEN
        RAISE EXCEPTION 'Enter how many animals.' USING ERRCODE = 'P0001';
    END IF;
    IF p_date IS NULL THEN
        RAISE EXCEPTION 'Enter the date.' USING ERRCODE = 'P0001';
    END IF;
    IF p_date > (now() at time zone 'utc')::date + 1 THEN
        RAISE EXCEPTION 'The date cannot be in the future.' USING ERRCODE = 'P0001';
    END IF;
    IF p_date < v_group.startdate THEN
        RAISE EXCEPTION 'The date is before % started (%).', v_group.name, to_char(v_group.startdate, 'DD Mon YYYY')
            USING ERRCODE = 'P0001';
    END IF;

    v_after := fnlivestock_grouphead(p_groupid) + p_quantity;
    IF v_after < 0 THEN
        RAISE EXCEPTION '% has only % animal(s); it cannot lose %.',
            v_group.name, v_after - p_quantity, -p_quantity USING ERRCODE = 'P0001';
    END IF;
    SELECT count(*) INTO v_tagged FROM livestockanimals
    WHERE groupid = p_groupid AND status = 'Active' AND NOT isdeleted
      AND (p_animalid IS NULL OR animalid <> p_animalid);
    IF p_quantity < 0 AND p_animalid IS NULL AND v_after < v_tagged THEN
        RAISE EXCEPTION '% has % tagged animal(s) still alive, so its head cannot go below that. Record the loss on the animal itself.',
            v_group.name, v_tagged USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO livestockheadmovements
        (farmid, groupid, movementdate, movementtype, quantity, batchid, animalid, sourcetype, sourceid, notes, createdby)
    VALUES (p_farmid, p_groupid, p_date, p_type, p_quantity, p_batchid, p_animalid, p_sourcetype, p_sourceid,
            NULLIF(btrim(p_notes), ''), p_by)
    RETURNING movementid INTO v_id;
    RETURN v_id;
END
$f$;

-- ---------------------------------------------------------------------------
-- Species: list (with what the farm keeps) and set
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.splivestockspecies_list(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'speciesCode', s.speciescode, 'name', s.name, 'singular', s.singular, 'category', s.category,
        'producesEggs', s.produceseggs, 'producesMilk', s.producesmilk, 'breedsOnFarm', s.breedsonfarm,
        'defaultTracking', s.defaulttracking, 'penTerm', s.penterm, 'groupTerm', s.groupterm,
        'birthTerm', s.birthterm, 'youngTerm', s.youngterm,
        'gestationDays', s.gestationdays, 'weaningDays', s.weaningdays,
        'enabled', fs.speciescode IS NOT NULL,
        'activeGroups', (SELECT count(*) FROM livestockgroups g
                         WHERE g.farmid = p_farmid AND g.speciescode = s.speciescode
                           AND g.status = 'Active' AND NOT g.isdeleted),
        'head', (SELECT COALESCE(SUM(fnlivestock_grouphead(g.groupid)), 0) FROM livestockgroups g
                 WHERE g.farmid = p_farmid AND g.speciescode = s.speciescode AND NOT g.isdeleted)
    ) ORDER BY s.sortorder), '[]'::jsonb)
    FROM livestockspecies s
    LEFT JOIN livestockfarmspecies fs ON fs.speciescode = s.speciescode AND fs.farmid = p_farmid;
$f$;

-- The full set of species the farm keeps. A species with active groups cannot
-- be switched off -- its pages would vanish while it still has animals.
CREATE OR REPLACE FUNCTION public.splivestockspecies_set(p_farmid text, p_codes text[], p_by text)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    v_bad   text;
    v_kept  text;
BEGIN
    IF p_codes IS NULL OR cardinality(p_codes) = 0 THEN
        RAISE EXCEPTION 'Choose at least one kind of animal.' USING ERRCODE = 'P0001';
    END IF;
    SELECT string_agg(c, ', ') INTO v_bad FROM unnest(p_codes) c
    WHERE NOT EXISTS (SELECT 1 FROM livestockspecies s WHERE s.speciescode = c);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Unknown animal type: %.', v_bad USING ERRCODE = 'P0001';
    END IF;
    SELECT string_agg(DISTINCT s.name, ', ') INTO v_kept
    FROM livestockgroups g JOIN livestockspecies s ON s.speciescode = g.speciescode
    WHERE g.farmid = p_farmid AND g.status = 'Active' AND NOT g.isdeleted
      AND NOT (g.speciescode = ANY (p_codes));
    IF v_kept IS NOT NULL THEN
        RAISE EXCEPTION 'You still have active groups of %. Close them before removing that animal.', v_kept
            USING ERRCODE = 'P0001';
    END IF;

    DELETE FROM livestockfarmspecies WHERE farmid = p_farmid AND NOT (speciescode = ANY (p_codes));
    INSERT INTO livestockfarmspecies (farmid, speciescode, enabledby)
    SELECT p_farmid, c, p_by FROM unnest(p_codes) c
    ON CONFLICT (farmid, speciescode) DO NOTHING;
    RETURN splivestockspecies_list(p_farmid);
END
$f$;

-- A species must be kept by the farm before anything of it is recorded.
CREATE OR REPLACE FUNCTION public.fnlivestock_requirespecies(p_farmid text, p_code text)
 RETURNS void LANGUAGE plpgsql STABLE AS $f$
BEGIN
    IF p_code IS NULL OR btrim(p_code) = '' THEN
        RAISE EXCEPTION 'Choose the kind of animal.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM livestockfarmspecies WHERE farmid = p_farmid AND speciescode = p_code) THEN
        RAISE EXCEPTION 'Your farm does not keep % yet. Add it under Setup > Animals kept first.',
            COALESCE((SELECT name FROM livestockspecies WHERE speciescode = p_code), p_code) USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- ---------------------------------------------------------------------------
-- Pens
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.splivestockpen_list(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'penId', p.penid, 'name', p.name, 'speciesCode', p.speciescode, 'speciesName', s.name,
        'capacity', p.capacity, 'location', p.location, 'notes', p.notes, 'isActive', p.isactive,
        'activeGroups', (SELECT count(*) FROM livestockgroups g WHERE g.penid = p.penid AND g.status = 'Active' AND NOT g.isdeleted),
        'head', (SELECT COALESCE(SUM(fnlivestock_grouphead(g.groupid)), 0) FROM livestockgroups g
                 WHERE g.penid = p.penid AND g.status = 'Active' AND NOT g.isdeleted)
    ) ORDER BY lower(p.name)), '[]'::jsonb)
    FROM livestockpens p LEFT JOIN livestockspecies s ON s.speciescode = p.speciescode
    WHERE p.farmid = p_farmid AND NOT p.isdeleted;
$f$;

-- Insert (no penId) or update. Over capacity is a warning on the page, not a
-- refusal here -- the same rule poultry houses ended up with.
CREATE OR REPLACE FUNCTION public.splivestockpen_save(p_farmid text, p_pen jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id      integer := NULLIF(p_pen->>'penId', '')::int;
    v_name    text    := btrim(COALESCE(p_pen->>'name', ''));
    v_species text    := NULLIF(btrim(COALESCE(p_pen->>'speciesCode', '')), '');
    v_cap     integer := NULLIF(p_pen->>'capacity', '')::int;
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Give the pen a name.' USING ERRCODE = 'P0001';
    END IF;
    IF v_cap IS NOT NULL AND v_cap < 0 THEN
        RAISE EXCEPTION 'Capacity cannot be negative.' USING ERRCODE = 'P0001';
    END IF;
    IF v_species IS NOT NULL THEN PERFORM fnlivestock_requirespecies(p_farmid, v_species); END IF;
    IF EXISTS (SELECT 1 FROM livestockpens WHERE farmid = p_farmid AND NOT isdeleted
               AND lower(btrim(name)) = lower(v_name) AND penid IS DISTINCT FROM v_id) THEN
        RAISE EXCEPTION 'You already have a pen called "%".', v_name USING ERRCODE = 'P0001';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO livestockpens (farmid, name, speciescode, capacity, location, notes, isactive, createdby)
        VALUES (p_farmid, v_name, v_species, v_cap, NULLIF(btrim(p_pen->>'location'), ''),
                NULLIF(btrim(p_pen->>'notes'), ''), COALESCE((p_pen->>'isActive')::boolean, TRUE), p_by)
        RETURNING penid INTO v_id;
    ELSE
        IF v_species IS NOT NULL AND EXISTS (
            SELECT 1 FROM livestockgroups WHERE penid = v_id AND status = 'Active' AND NOT isdeleted
              AND speciescode <> v_species) THEN
            RAISE EXCEPTION 'This pen holds groups of another kind of animal, so it cannot be limited to one kind.'
                USING ERRCODE = 'P0001';
        END IF;
        IF COALESCE((p_pen->>'isActive')::boolean, TRUE) = FALSE AND EXISTS (
            SELECT 1 FROM livestockgroups WHERE penid = v_id AND status = 'Active' AND NOT isdeleted) THEN
            RAISE EXCEPTION 'Move the active groups out of this pen before marking it unused.' USING ERRCODE = 'P0001';
        END IF;
        UPDATE livestockpens SET
            name = v_name, speciescode = v_species, capacity = v_cap,
            location = NULLIF(btrim(p_pen->>'location'), ''), notes = NULLIF(btrim(p_pen->>'notes'), ''),
            isactive = COALESCE((p_pen->>'isActive')::boolean, TRUE),
            updatedat = (now() at time zone 'utc'), updatedby = p_by
        WHERE penid = v_id AND farmid = p_farmid AND NOT isdeleted;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That pen was not found.' USING ERRCODE = 'P0001';
        END IF;
    END IF;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockpen_delete(p_farmid text, p_penid integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    IF EXISTS (SELECT 1 FROM livestockgroups WHERE penid = p_penid AND NOT isdeleted) THEN
        RAISE EXCEPTION 'Groups have been kept in this pen, so it cannot be deleted. Mark it unused instead.'
            USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockpens SET isdeleted = TRUE, updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE penid = p_penid AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That pen was not found.' USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- ---------------------------------------------------------------------------
-- Intake batches
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.splivestockbatch_list(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.intakedate DESC, x.batchid DESC), '[]'::jsonb) FROM (
        SELECT b.batchid, b.intakedate, jsonb_build_object(
            'batchId', b.batchid, 'batchCode', b.batchcode, 'speciesCode', b.speciescode, 'speciesName', s.name,
            'breed', b.breed, 'quantity', b.quantity, 'intakeDate', b.intakedate, 'source', b.source,
            'supplierId', b.supplierid, 'costPerHead', b.costperhead, 'totalCost', b.totalcost,
            'ageAtIntake', b.ageatintake, 'notes', b.notes,
            'allocated', fnlivestock_batchallocated(b.batchid),
            'unallocated', b.quantity - fnlivestock_batchallocated(b.batchid),
            'groups', (SELECT COALESCE(jsonb_agg(jsonb_build_object('groupId', g.groupid, 'name', g.name)
                                                ORDER BY g.groupid), '[]'::jsonb)
                       FROM livestockgroups g WHERE g.batchid = b.batchid AND NOT g.isdeleted)
        ) AS j
        FROM livestockbatches b JOIN livestockspecies s ON s.speciescode = b.speciescode
        WHERE b.farmid = p_farmid AND NOT b.isdeleted
    ) x;
$f$;

CREATE OR REPLACE FUNCTION public.splivestockbatch_save(p_farmid text, p_batch jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id       integer := NULLIF(p_batch->>'batchId', '')::int;
    v_species  text    := NULLIF(btrim(COALESCE(p_batch->>'speciesCode', '')), '');
    v_qty      integer := NULLIF(p_batch->>'quantity', '')::int;
    v_date     date    := NULLIF(p_batch->>'intakeDate', '')::date;
    v_code     text    := NULLIF(btrim(COALESCE(p_batch->>'batchCode', '')), '');
    v_cph      numeric := NULLIF(p_batch->>'costPerHead', '')::numeric;
    v_total    numeric := NULLIF(p_batch->>'totalCost', '')::numeric;
    v_old      livestockbatches%ROWTYPE;
    v_alloc    integer;
BEGIN
    PERFORM fnlivestock_requirespecies(p_farmid, v_species);
    IF v_qty IS NULL OR v_qty <= 0 THEN
        RAISE EXCEPTION 'Enter how many animals came in.' USING ERRCODE = 'P0001';
    END IF;
    IF v_date IS NULL THEN
        RAISE EXCEPTION 'Enter the date they came in.' USING ERRCODE = 'P0001';
    END IF;
    IF v_date > (now() at time zone 'utc')::date + 1 THEN
        RAISE EXCEPTION 'The intake date cannot be in the future.' USING ERRCODE = 'P0001';
    END IF;
    IF (v_cph IS NOT NULL AND v_cph < 0) OR (v_total IS NOT NULL AND v_total < 0) THEN
        RAISE EXCEPTION 'Costs cannot be negative.' USING ERRCODE = 'P0001';
    END IF;
    -- Either figure fills the other.
    IF v_total IS NULL AND v_cph IS NOT NULL THEN v_total := round(v_cph * v_qty, 2); END IF;
    IF v_cph IS NULL AND v_total IS NOT NULL THEN v_cph := round(v_total / v_qty, 2); END IF;

    IF v_id IS NULL THEN
        IF v_code IS NULL THEN
            v_code := 'LB-' || lpad((SELECT count(*) + 1 FROM livestockbatches WHERE farmid = p_farmid)::text, 4, '0');
            WHILE EXISTS (SELECT 1 FROM livestockbatches WHERE farmid = p_farmid AND NOT isdeleted AND lower(batchcode) = lower(v_code)) LOOP
                v_code := v_code || 'A';
            END LOOP;
        ELSIF EXISTS (SELECT 1 FROM livestockbatches WHERE farmid = p_farmid AND NOT isdeleted AND lower(batchcode) = lower(v_code)) THEN
            RAISE EXCEPTION 'Batch code "%" is already used.', v_code USING ERRCODE = 'P0001';
        END IF;
        INSERT INTO livestockbatches (farmid, batchcode, speciescode, breed, quantity, intakedate, source, supplierid,
                                      costperhead, totalcost, ageatintake, notes, createdby)
        VALUES (p_farmid, v_code, v_species, NULLIF(btrim(p_batch->>'breed'), ''), v_qty, v_date,
                COALESCE(NULLIF(p_batch->>'source', ''), 'Purchased'), NULLIF(p_batch->>'supplierId', '')::int,
                v_cph, v_total, NULLIF(btrim(p_batch->>'ageAtIntake'), ''), NULLIF(btrim(p_batch->>'notes'), ''), p_by)
        RETURNING batchid INTO v_id;
    ELSE
        SELECT * INTO v_old FROM livestockbatches WHERE batchid = v_id AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That batch was not found.' USING ERRCODE = 'P0001';
        END IF;
        v_alloc := fnlivestock_batchallocated(v_id);
        IF v_qty < v_alloc THEN
            RAISE EXCEPTION '% animal(s) from this batch are already in groups, so it cannot be fewer than that.', v_alloc
                USING ERRCODE = 'P0001';
        END IF;
        IF v_species <> v_old.speciescode AND v_alloc > 0 THEN
            RAISE EXCEPTION 'This batch is already in groups, so its kind of animal cannot change.' USING ERRCODE = 'P0001';
        END IF;
        IF v_date > COALESCE((SELECT min(movementdate) FROM livestockheadmovements
                              WHERE batchid = v_id AND reversedat IS NULL), v_date) THEN
            RAISE EXCEPTION 'Groups from this batch start before that date.' USING ERRCODE = 'P0001';
        END IF;
        IF v_code IS NOT NULL AND lower(v_code) <> lower(v_old.batchcode) AND EXISTS (
            SELECT 1 FROM livestockbatches WHERE farmid = p_farmid AND NOT isdeleted AND lower(batchcode) = lower(v_code)) THEN
            RAISE EXCEPTION 'Batch code "%" is already used.', v_code USING ERRCODE = 'P0001';
        END IF;
        UPDATE livestockbatches SET
            batchcode = COALESCE(v_code, batchcode), speciescode = v_species,
            breed = NULLIF(btrim(p_batch->>'breed'), ''), quantity = v_qty, intakedate = v_date,
            source = COALESCE(NULLIF(p_batch->>'source', ''), source), supplierid = NULLIF(p_batch->>'supplierId', '')::int,
            costperhead = v_cph, totalcost = v_total, ageatintake = NULLIF(btrim(p_batch->>'ageAtIntake'), ''),
            notes = NULLIF(btrim(p_batch->>'notes'), ''), updatedat = (now() at time zone 'utc'), updatedby = p_by
        WHERE batchid = v_id;
    END IF;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockbatch_delete(p_farmid text, p_batchid integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    IF EXISTS (SELECT 1 FROM livestockgroups WHERE batchid = p_batchid AND NOT isdeleted) THEN
        RAISE EXCEPTION 'This batch has been divided into groups. Delete those groups first.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockbatches SET isdeleted = TRUE, updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE batchid = p_batchid AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That batch was not found.' USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- ---------------------------------------------------------------------------
-- Groups
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnlivestock_groupjson(p_groupid integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'groupId', g.groupid, 'name', g.name, 'speciesCode', g.speciescode, 'speciesName', s.name,
        'groupTerm', s.groupterm, 'penId', g.penid, 'penName', p.name, 'penCapacity', p.capacity,
        'batchId', g.batchid, 'batchCode', b.batchcode, 'breed', g.breed, 'purpose', g.purpose,
        'startDate', g.startdate, 'ageAtStartDays', g.ageatstartdays,
        'status', g.status, 'closedDate', g.closeddate, 'closeReason', g.closereason,
        'notes', g.notes,
        'head', fnlivestock_grouphead(g.groupid),
        'placed', (SELECT COALESCE(SUM(m.quantity), 0) FROM livestockheadmovements m
                   WHERE m.groupid = g.groupid AND m.reversedat IS NULL AND m.movementtype IN ('Opening', 'Intake')),
        'deaths', (SELECT COALESCE(-SUM(m.quantity), 0) FROM livestockheadmovements m
                   WHERE m.groupid = g.groupid AND m.reversedat IS NULL AND m.movementtype = 'Death'),
        'tagged', (SELECT count(*) FROM livestockanimals a WHERE a.groupid = g.groupid AND a.status = 'Active' AND NOT a.isdeleted),
        'ageDays', (now() at time zone 'utc')::date - g.startdate)
    FROM livestockgroups g
    JOIN livestockspecies s ON s.speciescode = g.speciescode
    LEFT JOIN livestockpens p ON p.penid = g.penid
    LEFT JOIN livestockbatches b ON b.batchid = g.batchid
    WHERE g.groupid = p_groupid;
$f$;

CREATE OR REPLACE FUNCTION public.splivestockgroup_list(p_farmid text, p_includeclosed boolean DEFAULT FALSE)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(fnlivestock_groupjson(g.groupid) ORDER BY (g.status = 'Active') DESC, lower(g.name)), '[]'::jsonb)
    FROM livestockgroups g
    WHERE g.farmid = p_farmid AND NOT g.isdeleted AND (p_includeclosed OR g.status = 'Active');
$f$;

CREATE OR REPLACE FUNCTION public.splivestockgroup_get(p_farmid text, p_groupid integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE v jsonb;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM livestockgroups WHERE groupid = p_groupid AND farmid = p_farmid AND NOT isdeleted) THEN
        RAISE EXCEPTION 'That group was not found.' USING ERRCODE = 'P0001';
    END IF;
    v := fnlivestock_groupjson(p_groupid);
    RETURN v || jsonb_build_object(
        'movements', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'movementId', m.movementid, 'date', m.movementdate, 'type', m.movementtype, 'quantity', m.quantity,
                'batchCode', b.batchcode, 'animalId', m.animalid, 'tagNumber', a.tagnumber,
                'sourceType', m.sourcetype, 'sourceId', m.sourceid, 'notes', m.notes,
                'createdBy', m.createdby, 'createdAt', m.createdat,
                'reversedAt', m.reversedat, 'reverseReason', m.reversereason
            ) ORDER BY m.movementdate DESC, m.movementid DESC), '[]'::jsonb)
            FROM livestockheadmovements m
            LEFT JOIN livestockbatches b ON b.batchid = m.batchid
            LEFT JOIN livestockanimals a ON a.animalid = m.animalid
            WHERE m.groupid = p_groupid));
END
$f$;

-- Create or edit a group.
--
-- Create needs where its animals come from:
--   source = 'Batch'   -- batchId + quantity, out of that batch's unallocated head.
--   source = 'Opening' -- quantity alive on startDate: animals already on the
--                         farm before the company started recording (poultry's
--                         Opening Farm Position, without a separate wizard).
--   source = 'Empty'   -- no head yet; animals are added by tagging, births or
--                         a transfer.
-- Edit changes the description only (name, pen, breed, purpose, notes, start
-- date while nothing is dated before it). Head changes are movements.
CREATE OR REPLACE FUNCTION public.splivestockgroup_save(p_farmid text, p_group jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id      integer := NULLIF(p_group->>'groupId', '')::int;
    v_name    text    := btrim(COALESCE(p_group->>'name', ''));
    v_species text    := NULLIF(btrim(COALESCE(p_group->>'speciesCode', '')), '');
    v_penid   integer := NULLIF(p_group->>'penId', '')::int;
    v_start   date    := NULLIF(p_group->>'startDate', '')::date;
    v_purpose text    := COALESCE(NULLIF(p_group->>'purpose', ''), 'Meat');
    v_source  text    := COALESCE(NULLIF(p_group->>'source', ''), 'Empty');
    v_qty     integer := NULLIF(p_group->>'quantity', '')::int;
    v_batchid integer := NULLIF(p_group->>'batchId', '')::int;
    v_batch   livestockbatches%ROWTYPE;
    v_pen     livestockpens%ROWTYPE;
    v_old     livestockgroups%ROWTYPE;
    v_free    integer;
    v_first   date;
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Give the group a name.' USING ERRCODE = 'P0001';
    END IF;
    IF v_start IS NULL THEN
        RAISE EXCEPTION 'Enter the start date.' USING ERRCODE = 'P0001';
    END IF;
    IF v_start > (now() at time zone 'utc')::date + 1 THEN
        RAISE EXCEPTION 'The start date cannot be in the future.' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(p_group->>'ageAtStartDays', '')::int < 0 THEN
        RAISE EXCEPTION 'Age cannot be negative.' USING ERRCODE = 'P0001';
    END IF;
    IF v_purpose NOT IN ('Meat', 'Eggs', 'Milk', 'Breeding', 'Mixed') THEN
        RAISE EXCEPTION 'Unknown purpose "%".', v_purpose USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM livestockgroups WHERE farmid = p_farmid AND NOT isdeleted
               AND lower(btrim(name)) = lower(v_name) AND groupid IS DISTINCT FROM v_id) THEN
        RAISE EXCEPTION 'You already have a group called "%".', v_name USING ERRCODE = 'P0001';
    END IF;

    IF v_id IS NOT NULL THEN
        SELECT * INTO v_old FROM livestockgroups WHERE groupid = v_id AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That group was not found.' USING ERRCODE = 'P0001';
        END IF;
        v_species := v_old.speciescode;   -- a group never changes kind
    END IF;
    PERFORM fnlivestock_requirespecies(p_farmid, v_species);

    IF v_penid IS NOT NULL THEN
        SELECT * INTO v_pen FROM livestockpens WHERE penid = v_penid AND farmid = p_farmid AND NOT isdeleted;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That pen was not found.' USING ERRCODE = 'P0001';
        END IF;
        IF NOT v_pen.isactive THEN
            RAISE EXCEPTION '% is marked unused. Choose another pen or mark it in use.', v_pen.name USING ERRCODE = 'P0001';
        END IF;
        IF v_pen.speciescode IS NOT NULL AND v_pen.speciescode <> v_species THEN
            RAISE EXCEPTION '% is kept for %.', v_pen.name,
                (SELECT name FROM livestockspecies WHERE speciescode = v_pen.speciescode) USING ERRCODE = 'P0001';
        END IF;
    END IF;

    IF v_id IS NOT NULL THEN
        SELECT min(movementdate) INTO v_first FROM livestockheadmovements WHERE groupid = v_id AND reversedat IS NULL;
        IF v_first IS NOT NULL AND v_start > v_first THEN
            RAISE EXCEPTION 'This group has animals recorded from %, so it cannot start later than that.',
                to_char(v_first, 'DD Mon YYYY') USING ERRCODE = 'P0001';
        END IF;
        UPDATE livestockgroups SET
            name = v_name, penid = v_penid, breed = NULLIF(btrim(p_group->>'breed'), ''), purpose = v_purpose,
            startdate = v_start, ageatstartdays = NULLIF(p_group->>'ageAtStartDays', '')::int,
            notes = NULLIF(btrim(p_group->>'notes'), ''),
            updatedat = (now() at time zone 'utc'), updatedby = p_by
        WHERE groupid = v_id;
        RETURN v_id;
    END IF;

    -- Create.
    IF v_source NOT IN ('Batch', 'Opening', 'Empty') THEN
        RAISE EXCEPTION 'Unknown source "%".', v_source USING ERRCODE = 'P0001';
    END IF;
    IF v_source IN ('Batch', 'Opening') AND (v_qty IS NULL OR v_qty <= 0) THEN
        RAISE EXCEPTION 'Enter how many animals go into the group.' USING ERRCODE = 'P0001';
    END IF;
    IF v_source = 'Batch' THEN
        SELECT * INTO v_batch FROM livestockbatches WHERE batchid = v_batchid AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Choose the batch the animals come from.' USING ERRCODE = 'P0001';
        END IF;
        IF v_batch.speciescode <> v_species THEN
            RAISE EXCEPTION 'Batch % is %, not %.', v_batch.batchcode,
                (SELECT lower(name) FROM livestockspecies WHERE speciescode = v_batch.speciescode),
                (SELECT lower(name) FROM livestockspecies WHERE speciescode = v_species) USING ERRCODE = 'P0001';
        END IF;
        IF v_start < v_batch.intakedate THEN
            RAISE EXCEPTION 'Batch % came in on %, so the group cannot start before that.', v_batch.batchcode,
                to_char(v_batch.intakedate, 'DD Mon YYYY') USING ERRCODE = 'P0001';
        END IF;
        v_free := v_batch.quantity - fnlivestock_batchallocated(v_batchid);
        IF v_qty > v_free THEN
            RAISE EXCEPTION 'Batch % has only % animal(s) not yet in a group.', v_batch.batchcode, v_free USING ERRCODE = 'P0001';
        END IF;
    ELSE
        v_batchid := NULL;
    END IF;

    INSERT INTO livestockgroups (farmid, speciescode, name, penid, batchid, breed, purpose, startdate, ageatstartdays, notes, createdby)
    VALUES (p_farmid, v_species, v_name, v_penid, v_batchid,
            COALESCE(NULLIF(btrim(p_group->>'breed'), ''), v_batch.breed), v_purpose, v_start,
            NULLIF(p_group->>'ageAtStartDays', '')::int, NULLIF(btrim(p_group->>'notes'), ''), p_by)
    RETURNING groupid INTO v_id;

    IF v_source = 'Batch' THEN
        PERFORM splivestockhead_post(p_farmid, v_id, v_start, 'Intake', v_qty, p_by,
                                     'From batch ' || v_batch.batchcode, v_batchid);
    ELSIF v_source = 'Opening' THEN
        PERFORM splivestockhead_post(p_farmid, v_id, v_start, 'Opening', v_qty, p_by,
                                     'Already on the farm when recording started');
    END IF;
    RETURN v_id;
END
$f$;

-- Divide one batch into several groups in one go (poultry's Divide Into Flocks).
-- p_groups: [{name, penId, quantity, purpose, notes}]; all or nothing.
CREATE OR REPLACE FUNCTION public.splivestockbatch_divide(p_farmid text, p_batchid integer, p_startdate date,
                                                         p_groups jsonb, p_by text)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    v_batch livestockbatches%ROWTYPE;
    v_g     jsonb;
    v_ids   integer[] := '{}';
    v_total integer;
    v_free  integer;
BEGIN
    SELECT * INTO v_batch FROM livestockbatches WHERE batchid = p_batchid AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That batch was not found.' USING ERRCODE = 'P0001';
    END IF;
    IF p_groups IS NULL OR jsonb_array_length(p_groups) = 0 THEN
        RAISE EXCEPTION 'Add at least one group.' USING ERRCODE = 'P0001';
    END IF;
    SELECT COALESCE(SUM(NULLIF(e->>'quantity', '')::int), 0) INTO v_total FROM jsonb_array_elements(p_groups) e;
    v_free := v_batch.quantity - fnlivestock_batchallocated(p_batchid);
    IF v_total > v_free THEN
        RAISE EXCEPTION 'These groups add up to % animal(s), but batch % has only % not yet in a group.',
            v_total, v_batch.batchcode, v_free USING ERRCODE = 'P0001';
    END IF;
    FOR v_g IN SELECT * FROM jsonb_array_elements(p_groups) LOOP
        v_ids := v_ids || splivestockgroup_save(p_farmid, v_g || jsonb_build_object(
            'speciesCode', v_batch.speciescode, 'source', 'Batch', 'batchId', p_batchid,
            'startDate', COALESCE(p_startdate, v_batch.intakedate)), p_by);
    END LOOP;
    RETURN to_jsonb(v_ids);
END
$f$;

-- Close a group whose animals are all gone.
CREATE OR REPLACE FUNCTION public.splivestockgroup_close(p_farmid text, p_groupid integer, p_date date,
                                                        p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_g livestockgroups%ROWTYPE; v_head integer;
BEGIN
    SELECT * INTO v_g FROM livestockgroups WHERE groupid = p_groupid AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That group was not found.' USING ERRCODE = 'P0001';
    END IF;
    IF v_g.status = 'Closed' THEN
        RAISE EXCEPTION '% is already closed.', v_g.name USING ERRCODE = 'P0001';
    END IF;
    v_head := fnlivestock_grouphead(p_groupid);
    IF v_head > 0 THEN
        RAISE EXCEPTION '% still has % animal(s). Record where they went (sold, died, moved) before closing it.',
            v_g.name, v_head USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(p_date, (now() at time zone 'utc')::date) < v_g.startdate THEN
        RAISE EXCEPTION 'The closing date is before the group started.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockgroups SET status = 'Closed', closeddate = COALESCE(p_date, (now() at time zone 'utc')::date),
        closereason = NULLIF(btrim(p_reason), ''), updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE groupid = p_groupid;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockgroup_reopen(p_farmid text, p_groupid integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    UPDATE livestockgroups SET status = 'Active', closeddate = NULL, closereason = NULL,
        updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE groupid = p_groupid AND farmid = p_farmid AND NOT isdeleted AND status = 'Closed';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That group is not closed.' USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- Delete a group made by mistake: only while the only things recorded on it
-- are the head it was created with. Its movements are reversed, not removed.
CREATE OR REPLACE FUNCTION public.splivestockgroup_delete(p_farmid text, p_groupid integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_g livestockgroups%ROWTYPE;
BEGIN
    SELECT * INTO v_g FROM livestockgroups WHERE groupid = p_groupid AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That group was not found.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM livestockanimals WHERE groupid = p_groupid AND NOT isdeleted) THEN
        RAISE EXCEPTION '% has tagged animals. Move or delete them first.', v_g.name USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM livestockheadmovements WHERE groupid = p_groupid AND reversedat IS NULL
               AND movementtype NOT IN ('Opening', 'Intake')) THEN
        RAISE EXCEPTION 'Deaths, sales or other changes are recorded on %, so it cannot be deleted. Close it instead.',
            v_g.name USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockheadmovements SET reversedat = (now() at time zone 'utc'), reversedby = p_by,
        reversereason = 'Group deleted'
    WHERE groupid = p_groupid AND reversedat IS NULL;
    UPDATE livestockgroups SET isdeleted = TRUE, updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE groupid = p_groupid;
END
$f$;

-- A manual head change on a group: a count correction, a death or cull
-- without a production record, or moving head to another group of the same
-- kind (p_togroupid). Later steps post deaths from production records and
-- sales from the sale itself; this is for everything else.
CREATE OR REPLACE FUNCTION public.splivestockhead_adjust(p_farmid text, p_groupid integer, p_date date,
    p_type text, p_quantity integer, p_notes text, p_by text, p_togroupid integer DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    v_from livestockgroups%ROWTYPE;
    v_to   livestockgroups%ROWTYPE;
    v_out  integer;
    v_in   integer;
BEGIN
    IF p_type NOT IN ('Death', 'Cull', 'Correction', 'Transfer') THEN
        RAISE EXCEPTION 'Unknown change "%".', p_type USING ERRCODE = 'P0001';
    END IF;
    IF p_quantity IS NULL OR p_quantity = 0 THEN
        RAISE EXCEPTION 'Enter how many animals.' USING ERRCODE = 'P0001';
    END IF;
    IF p_type IN ('Death', 'Cull', 'Transfer') AND p_quantity < 0 THEN
        RAISE EXCEPTION 'Enter the number of animals as a positive number.' USING ERRCODE = 'P0001';
    END IF;
    IF p_type = 'Correction' AND NULLIF(btrim(p_notes), '') IS NULL THEN
        RAISE EXCEPTION 'Say why the count is being corrected.' USING ERRCODE = 'P0001';
    END IF;

    IF p_type <> 'Transfer' THEN
        v_out := splivestockhead_post(p_farmid, p_groupid, p_date, p_type,
                    CASE WHEN p_type = 'Correction' THEN p_quantity ELSE -p_quantity END, p_by, p_notes);
        RETURN jsonb_build_object('movementId', v_out, 'head', fnlivestock_grouphead(p_groupid));
    END IF;

    SELECT * INTO v_from FROM livestockgroups WHERE groupid = p_groupid AND farmid = p_farmid AND NOT isdeleted;
    SELECT * INTO v_to   FROM livestockgroups WHERE groupid = p_togroupid AND farmid = p_farmid AND NOT isdeleted;
    IF v_to.groupid IS NULL THEN
        RAISE EXCEPTION 'Choose the group the animals move to.' USING ERRCODE = 'P0001';
    END IF;
    IF v_to.groupid = v_from.groupid THEN
        RAISE EXCEPTION 'Choose a different group to move them to.' USING ERRCODE = 'P0001';
    END IF;
    IF v_to.speciescode <> v_from.speciescode THEN
        RAISE EXCEPTION 'Animals can only move to a group of the same kind.' USING ERRCODE = 'P0001';
    END IF;
    IF v_to.status <> 'Active' THEN
        RAISE EXCEPTION '% is closed.', v_to.name USING ERRCODE = 'P0001';
    END IF;
    v_out := splivestockhead_post(p_farmid, p_groupid, p_date, 'TransferOut', -p_quantity, p_by,
                                  COALESCE(NULLIF(btrim(p_notes), ''), 'Moved to ' || v_to.name));
    v_in  := splivestockhead_post(p_farmid, p_togroupid, p_date, 'TransferIn', p_quantity, p_by,
                                  COALESCE(NULLIF(btrim(p_notes), ''), 'Moved from ' || v_from.name));
    UPDATE livestockheadmovements SET pairedmovementid = v_in WHERE movementid = v_out;
    UPDATE livestockheadmovements SET pairedmovementid = v_out WHERE movementid = v_in;
    RETURN jsonb_build_object('movementId', v_out, 'head', fnlivestock_grouphead(p_groupid),
                              'toHead', fnlivestock_grouphead(p_togroupid));
END
$f$;

-- Reverse a manual movement (and the other half of a transfer). Movements made
-- by something else -- a group's creation, an animal, later a production
-- record or a sale -- are undone there, not here.
CREATE OR REPLACE FUNCTION public.splivestockhead_reverse(p_farmid text, p_movementid integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_m livestockheadmovements%ROWTYPE; v_ids integer[];
BEGIN
    SELECT * INTO v_m FROM livestockheadmovements WHERE movementid = p_movementid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That change was not found.' USING ERRCODE = 'P0001';
    END IF;
    IF v_m.reversedat IS NOT NULL THEN
        RAISE EXCEPTION 'That change is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF v_m.movementtype IN ('Opening', 'Intake') OR v_m.animalid IS NOT NULL OR v_m.sourcetype IS NOT NULL THEN
        RAISE EXCEPTION 'This change was made by another record. Undo it there.' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    v_ids := ARRAY[v_m.movementid] || CASE WHEN v_m.pairedmovementid IS NULL THEN '{}'::int[] ELSE ARRAY[v_m.pairedmovementid] END;
    -- Reversing must not leave either group below zero.
    IF EXISTS (
        SELECT 1 FROM livestockheadmovements m
        WHERE m.movementid = ANY (v_ids) AND m.quantity > 0
          AND fnlivestock_grouphead(m.groupid) - m.quantity < 0) THEN
        RAISE EXCEPTION 'Reversing this would leave a group with fewer than zero animals.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockheadmovements SET reversedat = (now() at time zone 'utc'), reversedby = p_by,
        reversereason = btrim(p_reason)
    WHERE movementid = ANY (v_ids);
END
$f$;

-- ---------------------------------------------------------------------------
-- Tagged animals
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnlivestock_animaljson(p_animalid integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'animalId', a.animalid, 'tagNumber', a.tagnumber, 'name', a.name, 'sex', a.sex, 'breed', a.breed,
        'speciesCode', a.speciescode, 'speciesName', s.singular, 'groupId', a.groupid, 'groupName', g.name,
        'penName', p.name, 'birthDate', a.birthdate,
        'ageDays', CASE WHEN a.birthdate IS NULL THEN NULL ELSE (now() at time zone 'utc')::date - a.birthdate END,
        'damId', a.damid, 'damTag', d.tagnumber, 'sireId', a.sireid, 'sireTag', si.tagnumber,
        'source', a.source, 'acquiredDate', a.acquireddate, 'purchaseCost', a.purchasecost,
        'status', a.status, 'statusDate', a.statusdate, 'statusNotes', a.statusnotes, 'notes', a.notes)
    FROM livestockanimals a
    JOIN livestockspecies s ON s.speciescode = a.speciescode
    JOIN livestockgroups g ON g.groupid = a.groupid
    LEFT JOIN livestockpens p ON p.penid = g.penid
    LEFT JOIN livestockanimals d ON d.animalid = a.damid
    LEFT JOIN livestockanimals si ON si.animalid = a.sireid
    WHERE a.animalid = p_animalid;
$f$;

-- p_filter: {groupId, speciesCode, status ('Active' default, 'All'), search}
CREATE OR REPLACE FUNCTION public.splivestockanimal_list(p_farmid text, p_filter jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(fnlivestock_animaljson(a.animalid) ORDER BY lower(a.tagnumber)), '[]'::jsonb)
    FROM livestockanimals a
    WHERE a.farmid = p_farmid AND NOT a.isdeleted
      AND (NULLIF(p_filter->>'groupId', '') IS NULL OR a.groupid = (p_filter->>'groupId')::int)
      AND (NULLIF(p_filter->>'speciesCode', '') IS NULL OR a.speciescode = p_filter->>'speciesCode')
      AND (COALESCE(NULLIF(p_filter->>'status', ''), 'Active') = 'All' OR a.status = COALESCE(NULLIF(p_filter->>'status', ''), 'Active'))
      AND (NULLIF(btrim(p_filter->>'search'), '') IS NULL
           OR a.tagnumber ILIKE '%' || btrim(p_filter->>'search') || '%'
           OR a.name ILIKE '%' || btrim(p_filter->>'search') || '%');
$f$;

CREATE OR REPLACE FUNCTION public.splivestockanimal_get(p_farmid text, p_animalid integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM livestockanimals WHERE animalid = p_animalid AND farmid = p_farmid AND NOT isdeleted) THEN
        RAISE EXCEPTION 'That animal was not found.' USING ERRCODE = 'P0001';
    END IF;
    RETURN fnlivestock_animaljson(p_animalid) || jsonb_build_object(
        'offspring', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                          'animalId', o.animalid, 'tagNumber', o.tagnumber, 'sex', o.sex,
                          'birthDate', o.birthdate, 'status', o.status) ORDER BY o.birthdate NULLS LAST, o.tagnumber), '[]'::jsonb)
                      FROM livestockanimals o WHERE (o.damid = p_animalid OR o.sireid = p_animalid) AND NOT o.isdeleted),
        'movements', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                          'movementId', m.movementid, 'date', m.movementdate, 'type', m.movementtype,
                          'groupName', g.name, 'quantity', m.quantity, 'notes', m.notes, 'reversedAt', m.reversedat)
                          ORDER BY m.movementdate DESC, m.movementid DESC), '[]'::jsonb)
                      FROM livestockheadmovements m JOIN livestockgroups g ON g.groupid = m.groupid
                      WHERE m.animalid = p_animalid));
END
$f$;

-- Register or edit a tagged animal.
--
-- On register, addsToHead says whether the animal is NEW to the group:
--   true  -- bought, born, brought in: the group's head goes up by one
--            (Intake or Birth movement).
--   false -- tagging an animal already counted in the group's head: nothing
--            moves, and the group must have an untagged animal to tag.
CREATE OR REPLACE FUNCTION public.splivestockanimal_save(p_farmid text, p_animal jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id      integer := NULLIF(p_animal->>'animalId', '')::int;
    v_tag     text    := btrim(COALESCE(p_animal->>'tagNumber', ''));
    v_groupid integer := NULLIF(p_animal->>'groupId', '')::int;
    v_sex     text    := COALESCE(NULLIF(p_animal->>'sex', ''), 'Unknown');
    v_birth   date    := NULLIF(p_animal->>'birthDate', '')::date;
    v_damid   integer := NULLIF(p_animal->>'damId', '')::int;
    v_sireid  integer := NULLIF(p_animal->>'sireId', '')::int;
    v_source  text    := COALESCE(NULLIF(p_animal->>'source', ''), 'OnFarm');
    v_acq     date    := NULLIF(p_animal->>'acquiredDate', '')::date;
    v_adds    boolean := COALESCE((p_animal->>'addsToHead')::boolean, FALSE);
    v_cost    numeric := NULLIF(p_animal->>'purchaseCost', '')::numeric;
    v_g       livestockgroups%ROWTYPE;
    v_old     livestockanimals%ROWTYPE;
    v_parent  livestockanimals%ROWTYPE;
    v_tagged  integer;
    v_date    date;
BEGIN
    IF v_tag = '' THEN
        RAISE EXCEPTION 'Enter the tag number.' USING ERRCODE = 'P0001';
    END IF;
    IF v_sex NOT IN ('Female', 'Male', 'Unknown') THEN
        RAISE EXCEPTION 'Unknown sex "%".', v_sex USING ERRCODE = 'P0001';
    END IF;
    IF v_source NOT IN ('OnFarm', 'Purchased', 'BornOnFarm', 'Other') THEN
        RAISE EXCEPTION 'Unknown source "%".', v_source USING ERRCODE = 'P0001';
    END IF;
    IF v_birth IS NOT NULL AND v_birth > (now() at time zone 'utc')::date THEN
        RAISE EXCEPTION 'The birth date cannot be in the future.' USING ERRCODE = 'P0001';
    END IF;
    IF v_cost IS NOT NULL AND v_cost < 0 THEN
        RAISE EXCEPTION 'The cost cannot be negative.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM livestockanimals WHERE farmid = p_farmid AND NOT isdeleted
               AND lower(btrim(tagnumber)) = lower(v_tag) AND animalid IS DISTINCT FROM v_id) THEN
        RAISE EXCEPTION 'Tag % is already used by another animal.', v_tag USING ERRCODE = 'P0001';
    END IF;

    IF v_id IS NOT NULL THEN
        SELECT * INTO v_old FROM livestockanimals WHERE animalid = v_id AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That animal was not found.' USING ERRCODE = 'P0001';
        END IF;
        v_groupid := v_old.groupid;   -- moving group is its own action
    END IF;

    SELECT * INTO v_g FROM livestockgroups WHERE groupid = v_groupid AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Choose the group the animal belongs to.' USING ERRCODE = 'P0001';
    END IF;

    -- Parents: same kind, right sex, older than the animal.
    FOREACH v_damid IN ARRAY ARRAY[v_damid, v_sireid] LOOP
        CONTINUE WHEN v_damid IS NULL;
        SELECT * INTO v_parent FROM livestockanimals WHERE animalid = v_damid AND farmid = p_farmid AND NOT isdeleted;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'A parent was not found.' USING ERRCODE = 'P0001';
        END IF;
        IF v_parent.speciescode <> v_g.speciescode THEN
            RAISE EXCEPTION 'Parent % is a different kind of animal.', v_parent.tagnumber USING ERRCODE = 'P0001';
        END IF;
        IF v_id IS NOT NULL AND v_parent.animalid = v_id THEN
            RAISE EXCEPTION 'An animal cannot be its own parent.' USING ERRCODE = 'P0001';
        END IF;
        IF v_birth IS NOT NULL AND v_parent.birthdate IS NOT NULL AND v_parent.birthdate >= v_birth THEN
            RAISE EXCEPTION 'Parent % was born after this animal.', v_parent.tagnumber USING ERRCODE = 'P0001';
        END IF;
    END LOOP;
    v_damid := NULLIF(p_animal->>'damId', '')::int;
    IF v_damid IS NOT NULL AND (SELECT sex FROM livestockanimals WHERE animalid = v_damid) = 'Male' THEN
        RAISE EXCEPTION 'The mother must be a female.' USING ERRCODE = 'P0001';
    END IF;
    IF v_sireid IS NOT NULL AND (SELECT sex FROM livestockanimals WHERE animalid = v_sireid) = 'Female' THEN
        RAISE EXCEPTION 'The father must be a male.' USING ERRCODE = 'P0001';
    END IF;

    IF v_id IS NOT NULL THEN
        UPDATE livestockanimals SET
            tagnumber = v_tag, name = NULLIF(btrim(p_animal->>'name'), ''), sex = v_sex,
            breed = NULLIF(btrim(p_animal->>'breed'), ''), birthdate = v_birth, damid = v_damid, sireid = v_sireid,
            source = v_source, acquireddate = v_acq, purchasecost = v_cost,
            notes = NULLIF(btrim(p_animal->>'notes'), ''), updatedat = (now() at time zone 'utc'), updatedby = p_by
        WHERE animalid = v_id;
        RETURN v_id;
    END IF;

    IF v_g.status <> 'Active' THEN
        RAISE EXCEPTION '% is closed.', v_g.name USING ERRCODE = 'P0001';
    END IF;
    IF NOT v_adds THEN
        SELECT count(*) INTO v_tagged FROM livestockanimals WHERE groupid = v_groupid AND status = 'Active' AND NOT isdeleted;
        IF v_tagged >= fnlivestock_grouphead(v_groupid) THEN
            RAISE EXCEPTION 'Every animal in % is already tagged (% head). If this animal is new to the group, say so.',
                v_g.name, fnlivestock_grouphead(v_groupid) USING ERRCODE = 'P0001';
        END IF;
    END IF;

    INSERT INTO livestockanimals (farmid, groupid, speciescode, tagnumber, name, sex, breed, birthdate, damid, sireid,
                                  source, acquireddate, purchasecost, notes, createdby)
    VALUES (p_farmid, v_groupid, v_g.speciescode, v_tag, NULLIF(btrim(p_animal->>'name'), ''), v_sex,
            COALESCE(NULLIF(btrim(p_animal->>'breed'), ''), v_g.breed), v_birth, v_damid, v_sireid, v_source, v_acq,
            v_cost, NULLIF(btrim(p_animal->>'notes'), ''), p_by)
    RETURNING animalid INTO v_id;

    IF v_adds THEN
        v_date := COALESCE(CASE WHEN v_source = 'BornOnFarm' THEN v_birth END, v_acq, (now() at time zone 'utc')::date);
        IF v_date < v_g.startdate THEN v_date := v_g.startdate; END IF;
        PERFORM splivestockhead_post(p_farmid, v_groupid, v_date,
                                     CASE WHEN v_source = 'BornOnFarm' THEN 'Birth' ELSE 'Intake' END, 1, p_by,
                                     'Tag ' || v_tag, NULL, v_id);
    END IF;
    RETURN v_id;
END
$f$;

-- An animal leaves: Sold, Dead or Culled -- the group loses one head. Setting
-- it back to Active reverses that movement.
CREATE OR REPLACE FUNCTION public.splivestockanimal_setstatus(p_farmid text, p_animalid integer, p_status text,
                                                             p_date date, p_notes text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_a livestockanimals%ROWTYPE; v_type text;
BEGIN
    SELECT * INTO v_a FROM livestockanimals WHERE animalid = p_animalid AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That animal was not found.' USING ERRCODE = 'P0001';
    END IF;
    IF p_status NOT IN ('Active', 'Sold', 'Dead', 'Culled') THEN
        RAISE EXCEPTION 'Unknown status "%".', p_status USING ERRCODE = 'P0001';
    END IF;
    IF p_status = v_a.status THEN
        RETURN;
    END IF;

    IF p_status = 'Active' THEN
        -- Back from the dead (a mistake): undo the leaving movement.
        UPDATE livestockheadmovements SET reversedat = (now() at time zone 'utc'), reversedby = p_by,
            reversereason = COALESCE(NULLIF(btrim(p_notes), ''), 'Animal set back to active')
        WHERE animalid = p_animalid AND reversedat IS NULL AND movementtype IN ('Death', 'Sale', 'Cull');
        UPDATE livestockanimals SET status = 'Active', statusdate = NULL, statusnotes = NULL,
            updatedat = (now() at time zone 'utc'), updatedby = p_by
        WHERE animalid = p_animalid;
        RETURN;
    END IF;

    IF v_a.status <> 'Active' THEN
        RAISE EXCEPTION 'Tag % is already marked %. Set it back to active first.', v_a.tagnumber, lower(v_a.status)
            USING ERRCODE = 'P0001';
    END IF;
    v_type := CASE p_status WHEN 'Sold' THEN 'Sale' WHEN 'Dead' THEN 'Death' ELSE 'Cull' END;
    PERFORM splivestockhead_post(p_farmid, v_a.groupid, COALESCE(p_date, (now() at time zone 'utc')::date), v_type, -1,
                                 p_by, COALESCE(NULLIF(btrim(p_notes), ''), 'Tag ' || v_a.tagnumber), NULL, p_animalid);
    UPDATE livestockanimals SET status = p_status, statusdate = COALESCE(p_date, (now() at time zone 'utc')::date),
        statusnotes = NULLIF(btrim(p_notes), ''), updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE animalid = p_animalid;
END
$f$;

-- Move a tagged animal to another group of the same kind (head moves with it).
CREATE OR REPLACE FUNCTION public.splivestockanimal_move(p_farmid text, p_animalid integer, p_togroupid integer,
                                                        p_date date, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_a livestockanimals%ROWTYPE; v_to livestockgroups%ROWTYPE; v_out integer; v_in integer;
BEGIN
    SELECT * INTO v_a FROM livestockanimals WHERE animalid = p_animalid AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That animal was not found.' USING ERRCODE = 'P0001';
    END IF;
    IF v_a.status <> 'Active' THEN
        RAISE EXCEPTION 'Only an active animal can be moved.' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO v_to FROM livestockgroups WHERE groupid = p_togroupid AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND OR v_to.groupid = v_a.groupid THEN
        RAISE EXCEPTION 'Choose a different group to move it to.' USING ERRCODE = 'P0001';
    END IF;
    IF v_to.speciescode <> v_a.speciescode THEN
        RAISE EXCEPTION 'An animal can only move to a group of the same kind.' USING ERRCODE = 'P0001';
    END IF;
    IF v_to.status <> 'Active' THEN
        RAISE EXCEPTION '% is closed.', v_to.name USING ERRCODE = 'P0001';
    END IF;
    v_out := splivestockhead_post(p_farmid, v_a.groupid, COALESCE(p_date, (now() at time zone 'utc')::date), 'TransferOut', -1,
                                  p_by, 'Tag ' || v_a.tagnumber || ' moved to ' || v_to.name, NULL, p_animalid);
    v_in  := splivestockhead_post(p_farmid, p_togroupid, COALESCE(p_date, (now() at time zone 'utc')::date), 'TransferIn', 1,
                                  p_by, 'Tag ' || v_a.tagnumber, NULL, p_animalid);
    UPDATE livestockheadmovements SET pairedmovementid = v_in WHERE movementid = v_out;
    UPDATE livestockheadmovements SET pairedmovementid = v_out WHERE movementid = v_in;
    UPDATE livestockanimals SET groupid = p_togroupid, updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE animalid = p_animalid;
END
$f$;

-- Delete a tag entered by mistake. If registering it added a head, that is
-- reversed too; an animal with offspring or a history stays (mark it instead).
CREATE OR REPLACE FUNCTION public.splivestockanimal_delete(p_farmid text, p_animalid integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_a livestockanimals%ROWTYPE;
BEGIN
    SELECT * INTO v_a FROM livestockanimals WHERE animalid = p_animalid AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That animal was not found.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM livestockanimals WHERE (damid = p_animalid OR sireid = p_animalid) AND NOT isdeleted) THEN
        RAISE EXCEPTION 'Tag % is recorded as a parent, so it cannot be deleted.', v_a.tagnumber USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM livestockheadmovements WHERE animalid = p_animalid AND reversedat IS NULL
               AND movementtype NOT IN ('Intake', 'Birth')) THEN
        RAISE EXCEPTION 'Tag % has a history (moved, sold or died), so it cannot be deleted.', v_a.tagnumber
            USING ERRCODE = 'P0001';
    END IF;
    IF fnlivestock_grouphead(v_a.groupid) - COALESCE((SELECT SUM(quantity) FROM livestockheadmovements
            WHERE animalid = p_animalid AND reversedat IS NULL), 0) < 0 THEN
        RAISE EXCEPTION 'Deleting this tag would leave its group below zero.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockheadmovements SET reversedat = (now() at time zone 'utc'), reversedby = p_by,
        reversereason = 'Tag deleted'
    WHERE animalid = p_animalid AND reversedat IS NULL;
    UPDATE livestockanimals SET isdeleted = TRUE, updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE animalid = p_animalid;
END
$f$;

-- ---------------------------------------------------------------------------
-- Dashboard: animals on the farm, by species.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.splivestock_overview(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'speciesKept', (SELECT count(*) FROM livestockfarmspecies WHERE farmid = p_farmid),
        'activeGroups', (SELECT count(*) FROM livestockgroups WHERE farmid = p_farmid AND status = 'Active' AND NOT isdeleted),
        'pens', (SELECT count(*) FROM livestockpens WHERE farmid = p_farmid AND isactive AND NOT isdeleted),
        'head', (SELECT COALESCE(SUM(fnlivestock_grouphead(groupid)), 0) FROM livestockgroups WHERE farmid = p_farmid AND NOT isdeleted),
        'tagged', (SELECT count(*) FROM livestockanimals WHERE farmid = p_farmid AND status = 'Active' AND NOT isdeleted),
        'deathsLast30', (SELECT COALESCE(-SUM(m.quantity), 0) FROM livestockheadmovements m
                         WHERE m.farmid = p_farmid AND m.reversedat IS NULL AND m.movementtype = 'Death'
                           AND m.movementdate > (now() at time zone 'utc')::date - 30),
        'unallocatedBatches', (SELECT count(*) FROM livestockbatches b WHERE b.farmid = p_farmid AND NOT b.isdeleted
                               AND b.quantity > fnlivestock_batchallocated(b.batchid)),
        'species', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                        'speciesCode', s.speciescode, 'name', s.name, 'groupTerm', s.groupterm,
                        'groups', (SELECT count(*) FROM livestockgroups g WHERE g.farmid = p_farmid
                                   AND g.speciescode = s.speciescode AND g.status = 'Active' AND NOT g.isdeleted),
                        'head', (SELECT COALESCE(SUM(fnlivestock_grouphead(g.groupid)), 0) FROM livestockgroups g
                                 WHERE g.farmid = p_farmid AND g.speciescode = s.speciescode AND NOT g.isdeleted),
                        'tagged', (SELECT count(*) FROM livestockanimals a WHERE a.farmid = p_farmid
                                   AND a.speciescode = s.speciescode AND a.status = 'Active' AND NOT a.isdeleted)
                    ) ORDER BY s.sortorder), '[]'::jsonb)
                    FROM livestockspecies s JOIN livestockfarmspecies fs ON fs.speciescode = s.speciescode
                    WHERE fs.farmid = p_farmid));
$f$;

-- ---------------------------------------------------------------------------
-- 8. IAM: each livestock resource mirrors a poultry twin.
--
-- splivestock_iammirror is kept (not dropped) so every later livestock
-- migration seeds its resources the same way.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.splivestock_iammirror(p_resource text, p_twin text, p_group text,
                                                       p_label text, p_description text, p_sortorder integer)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_added integer := 0;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RETURN 0;
    END IF;
    -- Matched on the KEY (poultry.<twin>.<action>), not the resource column:
    -- some poultry rows store their resource as 'poultry.cash-transfers'.
    INSERT INTO iampermissions (permissionkey, module, resource, action, permissiongroup, resourcelabel,
                                description, companytype, isdangerous, sortorder)
    SELECT 'livestock.' || p_resource || '.' || split_part(t.permissionkey, '.', 3), 'livestock', p_resource,
           split_part(t.permissionkey, '.', 3), p_group, p_label, p_description, 'Livestock', t.isdangerous, p_sortorder
    FROM iampermissions t
    WHERE t.permissionkey LIKE 'poultry.' || p_twin || '.%'
      AND split_part(t.permissionkey, '.', 4) = ''          -- exactly three parts
    ON CONFLICT (permissionkey) DO NOTHING;
    GET DIAGNOSTICS v_added = ROW_COUNT;

    IF to_regclass('public.iamrolepermissions') IS NOT NULL THEN
        INSERT INTO iamrolepermissions (roleid, permissionkey)
        SELECT rp.roleid, 'livestock.' || p_resource || '.' || split_part(rp.permissionkey, '.', 3)
        FROM iamrolepermissions rp
        WHERE rp.permissionkey LIKE 'poultry.' || p_twin || '.%'
          AND EXISTS (SELECT 1 FROM iampermissions p
                      WHERE p.permissionkey = 'livestock.' || p_resource || '.' || split_part(rp.permissionkey, '.', 3))
        ON CONFLICT (roleid, permissionkey) DO NOTHING;
    END IF;

    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        INSERT INTO iamuserpermissions (userid, farmid, permissionkey, effect, reason, grantedby, grantedat)
        SELECT up.userid, up.farmid, 'livestock.' || p_resource || '.' || split_part(up.permissionkey, '.', 3),
               up.effect, 'Carried over from ' || up.permissionkey, up.grantedby, (now() at time zone 'utc')
        FROM iamuserpermissions up
        WHERE up.permissionkey LIKE 'poultry.' || p_twin || '.%'
          AND (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
          AND EXISTS (SELECT 1 FROM iampermissions p
                      WHERE p.permissionkey = 'livestock.' || p_resource || '.' || split_part(up.permissionkey, '.', 3))
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;
    END IF;
    RETURN v_added;
END
$f$;

DO $iam$
DECLARE v integer := 0;
BEGIN
    v := v + splivestock_iammirror('pens',    'houses',        'Animals', 'Pens',
            'Pens, hutches, sties and kraals the animals are kept in.', 11);
    v := v + splivestock_iammirror('groups',  'flocks',        'Animals', 'Animal Groups',
            'Groups of animals kept and recorded together, and changes to their head count.', 10);
    v := v + splivestock_iammirror('batches', 'flock-batches', 'Animals', 'Intake Batches',
            'Animals bought or brought in together, and dividing them into groups.', 12);
    v := v + splivestock_iammirror('animals', 'flocks',        'Animals', 'Animal Register',
            'Tagged animals: tag, sex, parents, and when one is sold, dies or moves.', 13);
    -- Which species the farm keeps is company setup; it follows poultry's
    -- houses (admins and setup roles).
    v := v + splivestock_iammirror('species', 'houses',        'Animals', 'Animals Kept',
            'Which kinds of animal the farm keeps.', 9);
    RAISE NOTICE '458: % livestock permission key(s) added.', v;
END
$iam$;

COMMIT;

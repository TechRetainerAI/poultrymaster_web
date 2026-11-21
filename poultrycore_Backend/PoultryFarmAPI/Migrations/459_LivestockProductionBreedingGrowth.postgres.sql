-- 459: Livestock daily production, stock items, breeding & births, weigh-ins.
--
-- Needs 458.
--
-- 1. Stock items and their ledger (livestockitems, livestockstockmovements).
--    Feed, medication, vaccines and supplies. Like the head count, an item's
--    quantity and value are the sums of its unreversed movements -- there is
--    no quantity column to drift. Cost is perpetual weighted average: a usage
--    is costed at the item's stock value / stock quantity at that moment.
--    (Poultry draws lots FIFO; average gives the same totals over a stock
--    cycle with one rule instead of a lot table.) Stock comes in here as an
--    opening balance or a manual "stock in"; purchases from suppliers arrive
--    with the purchasing step and post into the same ledger.
--
-- 2. Daily production records (livestockproductionrecords + feed and
--    medication lines). One per group per day. A record's deaths and culls
--    are head movements, its feed and medication lines are stock movements,
--    all tagged sourcetype 'ProductionRecord'. Editing a record reverses
--    everything it posted and posts it again; deleting reverses it. Eggs are
--    allowed only for egg-laying species, milk only for milked ones.
--
-- 3. Breeding (livestockbreedingevents): mating, pregnancy check, birth,
--    weaning, loss of pregnancy. A birth adds its live young to a group as a
--    'Birth' head movement; weaning can move them to another group. A mating
--    stays "due" until the dam gives birth, is checked empty or loses it.
--
-- 4. Weigh-ins (livestockweighins): a group's (or one animal's) average
--    weight on a date, the base of daily gain and feed conversion.
--
-- 5. IAM: livestock.items <- poultry.raw-materials, livestock.stock <-
--    poultry.stock, livestock.production-records <- poultry.production-records,
--    livestock.breeding <- poultry.flocks, livestock.weigh-ins <-
--    poultry.production-records.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Stock items
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockitems (
    itemid        serial PRIMARY KEY,
    farmid        text NOT NULL,
    name          text NOT NULL,
    category      text NOT NULL CHECK (category IN ('Feed', 'Ingredient', 'Medication', 'Vaccine', 'Supply', 'Produce', 'Other')),
    unit          text NOT NULL DEFAULT 'kg',      -- what quantities are counted in: kg, bag, bottle, dose
    kgperunit     numeric(12,3) CHECK (kgperunit IS NULL OR kgperunit > 0),   -- feed only: for feed conversion
    minimumstock  numeric(14,3) CHECK (minimumstock IS NULL OR minimumstock >= 0),
    speciescode   text REFERENCES livestockspecies(speciescode),          -- NULL = any animal
    notes         text,
    isactive      boolean NOT NULL DEFAULT TRUE,
    isdeleted     boolean NOT NULL DEFAULT FALSE,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    updatedat     timestamp,
    updatedby     text
);
CREATE UNIQUE INDEX IF NOT EXISTS uxlivestockitems_name
    ON livestockitems (farmid, lower(btrim(name))) WHERE NOT isdeleted;

CREATE TABLE IF NOT EXISTS livestockstockmovements (
    movementid    serial PRIMARY KEY,
    farmid        text NOT NULL,
    itemid        integer NOT NULL REFERENCES livestockitems(itemid),
    movementdate  date NOT NULL,
    movementtype  text NOT NULL CHECK (movementtype IN ('Opening', 'StockIn', 'Purchase', 'Usage', 'Adjustment', 'Produced', 'Loss')),
    lossreason    text CHECK (lossreason IS NULL OR lossreason IN ('Spoiled', 'Expired', 'Spilled', 'Stolen', 'Damaged', 'Other')),
    quantity      numeric(14,3) NOT NULL CHECK (quantity <> 0),   -- signed
    unitcost      numeric(14,4),
    totalcost     numeric(14,2) NOT NULL DEFAULT 0,               -- signed like quantity
    groupid       integer REFERENCES livestockgroups(groupid),  -- usage: the group it went to
    sourcetype    text,
    sourceid      integer,
    notes         text,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text,
    CHECK ((movementtype IN ('Opening', 'StockIn', 'Purchase', 'Produced') AND quantity > 0) OR
           (movementtype IN ('Usage', 'Loss') AND quantity < 0) OR movementtype = 'Adjustment')
);
CREATE INDEX IF NOT EXISTS ixlivestockstockmovements_item
    ON livestockstockmovements (itemid, movementdate) WHERE reversedat IS NULL;
CREATE INDEX IF NOT EXISTS ixlivestockstockmovements_source
    ON livestockstockmovements (sourcetype, sourceid) WHERE reversedat IS NULL;
CREATE INDEX IF NOT EXISTS ixlivestockstockmovements_group
    ON livestockstockmovements (groupid, movementdate) WHERE reversedat IS NULL AND groupid IS NOT NULL;

CREATE OR REPLACE FUNCTION public.fnlivestock_itemstock(p_itemid integer)
 RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(SUM(quantity), 0) FROM livestockstockmovements WHERE itemid = p_itemid AND reversedat IS NULL;
$f$;

CREATE OR REPLACE FUNCTION public.fnlivestock_itemvalue(p_itemid integer)
 RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(SUM(totalcost), 0) FROM livestockstockmovements WHERE itemid = p_itemid AND reversedat IS NULL;
$f$;

-- Average cost of what is in stock now (NULL when there is none).
CREATE OR REPLACE FUNCTION public.fnlivestock_itemavgcost(p_itemid integer)
 RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT CASE WHEN fnlivestock_itemstock(p_itemid) > 0
                THEN round(fnlivestock_itemvalue(p_itemid) / fnlivestock_itemstock(p_itemid), 4) END;
$f$;

-- Posts one stock movement. Stock coming in needs its unit cost (it may be 0);
-- stock going out is costed at the average and refused beyond what is there.
CREATE OR REPLACE FUNCTION public.splivestockstock_post(
    p_farmid text, p_itemid integer, p_date date, p_type text, p_quantity numeric,
    p_unitcost numeric, p_by text, p_notes text DEFAULT NULL,
    p_sourcetype text DEFAULT NULL, p_sourceid integer DEFAULT NULL, p_groupid integer DEFAULT NULL)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_item  livestockitems%ROWTYPE;
    v_stock numeric;
    v_value numeric;
    v_cost  numeric;
    v_total numeric;
    v_id    integer;
BEGIN
    SELECT * INTO v_item FROM livestockitems WHERE itemid = p_itemid AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That stock item was not found.' USING ERRCODE = 'P0001';
    END IF;
    IF p_quantity IS NULL OR p_quantity = 0 THEN
        RAISE EXCEPTION 'Enter a quantity for %.', v_item.name USING ERRCODE = 'P0001';
    END IF;
    IF p_date IS NULL OR p_date > (now() at time zone 'utc')::date + 1 THEN
        RAISE EXCEPTION 'Enter a date that is not in the future.' USING ERRCODE = 'P0001';
    END IF;

    v_stock := fnlivestock_itemstock(p_itemid);
    v_value := fnlivestock_itemvalue(p_itemid);
    IF p_quantity > 0 THEN
        IF p_unitcost IS NULL OR p_unitcost < 0 THEN
            RAISE EXCEPTION 'Enter what each % of % cost (0 if it was free).', v_item.unit, v_item.name USING ERRCODE = 'P0001';
        END IF;
        v_cost  := p_unitcost;
        v_total := round(p_quantity * p_unitcost, 2);
    ELSE
        IF v_stock + p_quantity < 0 THEN
            RAISE EXCEPTION '%: only % in stock, % needed.',
                v_item.name, trim_scale(v_stock), trim_scale(-p_quantity)
                USING ERRCODE = 'LV003';
        END IF;
        -- Average cost; the last unit out takes whatever value is left, so
        -- rounding never leaves value behind on an empty item.
        v_cost  := CASE WHEN v_stock > 0 THEN v_value / v_stock ELSE 0 END;
        v_total := CASE WHEN v_stock + p_quantity = 0 THEN -v_value ELSE round(p_quantity * v_cost, 2) END;
    END IF;

    INSERT INTO livestockstockmovements (farmid, itemid, movementdate, movementtype, quantity, unitcost, totalcost,
                                         groupid, sourcetype, sourceid, notes, createdby)
    VALUES (p_farmid, p_itemid, p_date, p_type, p_quantity, round(v_cost, 4), v_total,
            p_groupid, p_sourcetype, p_sourceid, NULLIF(btrim(p_notes), ''), p_by)
    RETURNING movementid INTO v_id;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.fnlivestock_itemjson(p_itemid integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'itemId', i.itemid, 'name', i.name, 'category', i.category, 'unit', i.unit, 'kgPerUnit', i.kgperunit,
        'minimumStock', i.minimumstock, 'speciesCode', i.speciescode, 'speciesName', s.name,
        'notes', i.notes, 'isActive', i.isactive,
        'stock', fnlivestock_itemstock(i.itemid), 'value', fnlivestock_itemvalue(i.itemid),
        'avgCost', fnlivestock_itemavgcost(i.itemid),
        'isLow', i.minimumstock IS NOT NULL AND fnlivestock_itemstock(i.itemid) <= i.minimumstock,
        'hasMovements', EXISTS (SELECT 1 FROM livestockstockmovements m WHERE m.itemid = i.itemid))
    FROM livestockitems i LEFT JOIN livestockspecies s ON s.speciescode = i.speciescode
    WHERE i.itemid = p_itemid;
$f$;

-- p_category: NULL = all; 'Health' = Medication + Vaccine.
CREATE OR REPLACE FUNCTION public.splivestockitem_list(p_farmid text, p_category text DEFAULT NULL, p_includeinactive boolean DEFAULT FALSE)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(fnlivestock_itemjson(i.itemid) ORDER BY i.category, lower(i.name)), '[]'::jsonb)
    FROM livestockitems i
    WHERE i.farmid = p_farmid AND NOT i.isdeleted AND (p_includeinactive OR i.isactive)
      AND (p_category IS NULL OR i.category = p_category
           OR (p_category = 'Health' AND i.category IN ('Medication', 'Vaccine')));
$f$;

CREATE OR REPLACE FUNCTION public.splivestockitem_get(p_farmid text, p_itemid integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM livestockitems WHERE itemid = p_itemid AND farmid = p_farmid AND NOT isdeleted) THEN
        RAISE EXCEPTION 'That stock item was not found.' USING ERRCODE = 'P0001';
    END IF;
    RETURN fnlivestock_itemjson(p_itemid) || jsonb_build_object('movements', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'movementId', m.movementid, 'date', m.movementdate, 'type', m.movementtype, 'quantity', m.quantity,
            'unitCost', m.unitcost, 'totalCost', m.totalcost, 'sourceType', m.sourcetype, 'sourceId', m.sourceid,
            'groupName', g.name, 'notes', m.notes, 'createdBy', m.createdby,
            'reversedAt', m.reversedat, 'reverseReason', m.reversereason)
            ORDER BY m.movementdate DESC, m.movementid DESC), '[]'::jsonb)
        FROM livestockstockmovements m
        LEFT JOIN livestockgroups g ON g.groupid = m.groupid
        WHERE m.itemid = p_itemid));
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockitem_save(p_farmid text, p_item jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id    integer := NULLIF(p_item->>'itemId', '')::int;
    v_name  text    := btrim(COALESCE(p_item->>'name', ''));
    v_cat   text    := COALESCE(NULLIF(p_item->>'category', ''), 'Feed');
    v_unit  text    := COALESCE(NULLIF(btrim(p_item->>'unit'), ''), 'kg');
    v_kg    numeric := NULLIF(p_item->>'kgPerUnit', '')::numeric;
    v_min   numeric := NULLIF(p_item->>'minimumStock', '')::numeric;
    v_sp    text    := NULLIF(btrim(COALESCE(p_item->>'speciesCode', '')), '');
    v_old   livestockitems%ROWTYPE;
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Give the item a name.' USING ERRCODE = 'P0001';
    END IF;
    IF v_cat NOT IN ('Feed', 'Ingredient', 'Medication', 'Vaccine', 'Supply', 'Produce', 'Other') THEN
        RAISE EXCEPTION 'Unknown category "%".', v_cat USING ERRCODE = 'P0001';
    END IF;
    IF lower(v_unit) = 'kg' THEN v_kg := 1; END IF;
    IF v_sp IS NOT NULL THEN PERFORM fnlivestock_requirespecies(p_farmid, v_sp); END IF;
    IF EXISTS (SELECT 1 FROM livestockitems WHERE farmid = p_farmid AND NOT isdeleted
               AND lower(btrim(name)) = lower(v_name) AND itemid IS DISTINCT FROM v_id) THEN
        RAISE EXCEPTION 'You already have an item called "%".', v_name USING ERRCODE = 'P0001';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO livestockitems (farmid, name, category, unit, kgperunit, minimumstock, speciescode, notes, createdby)
        VALUES (p_farmid, v_name, v_cat, v_unit, v_kg, v_min, v_sp, NULLIF(btrim(p_item->>'notes'), ''), p_by)
        RETURNING itemid INTO v_id;
        -- Opening stock in the same save.
        IF NULLIF(p_item->>'openingQuantity', '')::numeric > 0 THEN
            PERFORM splivestockstock_post(p_farmid, v_id,
                COALESCE(NULLIF(p_item->>'openingDate', '')::date, (now() at time zone 'utc')::date), 'Opening',
                (p_item->>'openingQuantity')::numeric, COALESCE(NULLIF(p_item->>'openingUnitCost', '')::numeric, 0),
                p_by, 'Opening stock');
        END IF;
        RETURN v_id;
    END IF;

    SELECT * INTO v_old FROM livestockitems WHERE itemid = v_id AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That stock item was not found.' USING ERRCODE = 'P0001';
    END IF;
    IF (v_unit <> v_old.unit OR v_cat <> v_old.category) AND fnlivestock_itemstock(v_id) <> 0 THEN
        RAISE EXCEPTION '% has stock, so its unit and category cannot change. Use the stock up or adjust it to zero first.',
            v_old.name USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockitems SET name = v_name, category = v_cat, unit = v_unit, kgperunit = v_kg, minimumstock = v_min,
        speciescode = v_sp, notes = NULLIF(btrim(p_item->>'notes'), ''),
        isactive = COALESCE((p_item->>'isActive')::boolean, isactive),
        updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE itemid = v_id;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockitem_delete(p_farmid text, p_itemid integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    IF EXISTS (SELECT 1 FROM livestockstockmovements WHERE itemid = p_itemid AND reversedat IS NULL) THEN
        RAISE EXCEPTION 'This item has stock history, so it cannot be deleted. Mark it unused instead.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockitems SET isdeleted = TRUE, updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE itemid = p_itemid AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That stock item was not found.' USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- Manual stock change: 'StockIn' (with its cost) or 'Adjustment' (a count
-- correction, either way, with a reason; a positive one needs a cost too).
CREATE OR REPLACE FUNCTION public.splivestockstock_adjust(p_farmid text, p_itemid integer, p_date date, p_type text,
    p_quantity numeric, p_unitcost numeric, p_notes text, p_by text)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_id integer;
BEGIN
    IF p_type NOT IN ('StockIn', 'Adjustment') THEN
        RAISE EXCEPTION 'Unknown stock change "%".', p_type USING ERRCODE = 'P0001';
    END IF;
    IF p_type = 'StockIn' AND COALESCE(p_quantity, 0) <= 0 THEN
        RAISE EXCEPTION 'Enter how much came in.' USING ERRCODE = 'P0001';
    END IF;
    IF p_type = 'Adjustment' AND NULLIF(btrim(p_notes), '') IS NULL THEN
        RAISE EXCEPTION 'Say why the stock is being corrected.' USING ERRCODE = 'P0001';
    END IF;
    v_id := splivestockstock_post(p_farmid, p_itemid, p_date, p_type, p_quantity, p_unitcost, p_by, p_notes);
    RETURN fnlivestock_itemjson(p_itemid) || jsonb_build_object('movementId', v_id);
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockstock_reverse(p_farmid text, p_movementid integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_m livestockstockmovements%ROWTYPE;
BEGIN
    SELECT * INTO v_m FROM livestockstockmovements WHERE movementid = p_movementid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That stock change was not found.' USING ERRCODE = 'P0001';
    END IF;
    IF v_m.reversedat IS NOT NULL THEN
        RAISE EXCEPTION 'That stock change is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF v_m.sourcetype IS NOT NULL THEN
        RAISE EXCEPTION 'This stock change was made by another record. Undo it there.' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF v_m.quantity > 0 AND fnlivestock_itemstock(v_m.itemid) - v_m.quantity < 0 THEN
        RAISE EXCEPTION 'Some of this stock has already been used, so it cannot be reversed. Correct the count instead.'
            USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockstockmovements SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
    WHERE movementid = p_movementid;
END
$f$;

-- ---------------------------------------------------------------------------
-- 2. Daily production records
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockproductionrecords (
    recordid      serial PRIMARY KEY,
    farmid        text NOT NULL,
    groupid       integer NOT NULL REFERENCES livestockgroups(groupid),
    recorddate    date NOT NULL,
    deaths        integer NOT NULL DEFAULT 0 CHECK (deaths >= 0),
    deathcause    text,
    culls         integer NOT NULL DEFAULT 0 CHECK (culls >= 0),
    eggscollected integer CHECK (eggscollected IS NULL OR eggscollected >= 0),
    eggsbroken    integer CHECK (eggsbroken IS NULL OR eggsbroken >= 0),
    milklitres    numeric(12,2) CHECK (milklitres IS NULL OR milklitres >= 0),
    waterlitres   numeric(12,2) CHECK (waterlitres IS NULL OR waterlitres >= 0),
    notes         text,
    isdeleted     boolean NOT NULL DEFAULT FALSE,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    updatedat     timestamp,
    updatedby     text,
    CHECK (eggsbroken IS NULL OR eggscollected IS NULL OR eggsbroken <= eggscollected)
);
-- One record per group per day (poultry's P0010 rule).
CREATE UNIQUE INDEX IF NOT EXISTS uxlivestockproductionrecords_day
    ON livestockproductionrecords (groupid, recorddate) WHERE NOT isdeleted;
CREATE INDEX IF NOT EXISTS ixlivestockproductionrecords_farm
    ON livestockproductionrecords (farmid, recorddate) WHERE NOT isdeleted;

CREATE TABLE IF NOT EXISTS livestockproductionlines (
    lineid          serial PRIMARY KEY,
    recordid        integer NOT NULL REFERENCES livestockproductionrecords(recordid),
    linetype        text NOT NULL CHECK (linetype IN ('Feed', 'Medication')),
    itemid          integer NOT NULL REFERENCES livestockitems(itemid),
    quantity        numeric(14,3) NOT NULL CHECK (quantity > 0),
    unitcost        numeric(14,4),
    totalcost       numeric(14,2),
    stockmovementid integer REFERENCES livestockstockmovements(movementid),
    notes           text,
    isreversed      boolean NOT NULL DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS ixlivestockproductionlines_record ON livestockproductionlines (recordid) WHERE NOT isreversed;

-- The farm's produce item for a species' eggs or milk ("Duck eggs", "Goat
-- milk"), made the first time it is needed. Eggs and milk from daily records
-- go into it ('Produced', at no cost -- what producing them cost is the feed
-- and medicine, already counted) and sales take them out.
CREATE OR REPLACE FUNCTION public.fnlivestock_produceitem(p_farmid text, p_species text, p_kind text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_id integer; v_name text;
BEGIN
    SELECT CASE p_kind WHEN 'Eggs' THEN singular || ' eggs' ELSE singular || ' milk' END INTO v_name
    FROM livestockspecies WHERE speciescode = p_species;
    SELECT itemid INTO v_id FROM livestockitems
    WHERE farmid = p_farmid AND NOT isdeleted AND category = 'Produce' AND speciescode = p_species
      AND unit = CASE p_kind WHEN 'Eggs' THEN 'egg' ELSE 'litre' END
    ORDER BY itemid LIMIT 1;
    IF v_id IS NULL THEN
        -- A farm item already holding the name (made by hand) is not reused
        -- for produce; the produce item gets a distinct name.
        IF EXISTS (SELECT 1 FROM livestockitems WHERE farmid = p_farmid AND NOT isdeleted AND lower(btrim(name)) = lower(v_name)) THEN
            v_name := v_name || ' (produced)';
        END IF;
        INSERT INTO livestockitems (farmid, name, category, unit, speciescode, notes, createdby)
        VALUES (p_farmid, v_name, 'Produce', CASE p_kind WHEN 'Eggs' THEN 'egg' ELSE 'litre' END, p_species,
                'Filled from daily records; emptied by sales.', 'system')
        RETURNING itemid INTO v_id;
    END IF;
    RETURN v_id;
END
$f$;

-- Produce stock must never go below zero: editing a record down after its
-- eggs or milk were sold is refused.
CREATE OR REPLACE FUNCTION public.fnlivestock_checkproduce(p_farmid text, p_species text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE r record;
BEGIN
    FOR r IN SELECT i.itemid, i.name, i.unit FROM livestockitems i
             WHERE i.farmid = p_farmid AND i.category = 'Produce' AND i.speciescode = p_species AND NOT i.isdeleted LOOP
        IF fnlivestock_itemstock(r.itemid) < 0 THEN
            RAISE EXCEPTION 'More % have been sold than this change would leave recorded (% % short). Correct the sale first.',
                lower(r.name), trim_scale(-fnlivestock_itemstock(r.itemid)), r.unit USING ERRCODE = 'P0001';
        END IF;
    END LOOP;
END
$f$;

-- Undo everything a source posted (head and stock).
CREATE OR REPLACE FUNCTION public.fnlivestock_reversesource(p_sourcetype text, p_sourceid integer, p_by text, p_reason text)
 RETURNS void LANGUAGE sql AS $f$
    UPDATE livestockheadmovements SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = p_reason
    WHERE sourcetype = p_sourcetype AND sourceid = p_sourceid AND reversedat IS NULL;
    UPDATE livestockstockmovements SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = p_reason
    WHERE sourcetype = p_sourcetype AND sourceid = p_sourceid AND reversedat IS NULL;
$f$;

CREATE OR REPLACE FUNCTION public.fnlivestock_recordjson(p_recordid integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'recordId', r.recordid, 'groupId', r.groupid, 'groupName', g.name, 'speciesCode', g.speciescode,
        'speciesName', s.name, 'date', r.recorddate, 'deaths', r.deaths, 'deathCause', r.deathcause, 'culls', r.culls,
        'eggsCollected', r.eggscollected, 'eggsBroken', r.eggsbroken, 'milkLitres', r.milklitres,
        'waterLitres', r.waterlitres, 'notes', r.notes,
        'headEndOfDay', fnlivestock_groupheadasof(r.groupid, r.recorddate),
        'feedQuantity', (SELECT COALESCE(SUM(l.quantity), 0) FROM livestockproductionlines l
                         WHERE l.recordid = r.recordid AND l.linetype = 'Feed' AND NOT l.isreversed),
        'feedKg', (SELECT SUM(l.quantity * i.kgperunit) FROM livestockproductionlines l JOIN livestockitems i ON i.itemid = l.itemid
                   WHERE l.recordid = r.recordid AND l.linetype = 'Feed' AND NOT l.isreversed),
        'feedCost', (SELECT COALESCE(SUM(l.totalcost), 0) FROM livestockproductionlines l
                     WHERE l.recordid = r.recordid AND l.linetype = 'Feed' AND NOT l.isreversed),
        'medicationCost', (SELECT COALESCE(SUM(l.totalcost), 0) FROM livestockproductionlines l
                           WHERE l.recordid = r.recordid AND l.linetype = 'Medication' AND NOT l.isreversed),
        'lines', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                      'lineId', l.lineid, 'lineType', l.linetype, 'itemId', l.itemid, 'itemName', i.name, 'unit', i.unit,
                      'quantity', l.quantity, 'unitCost', l.unitcost, 'totalCost', l.totalcost, 'notes', l.notes)
                      ORDER BY l.linetype, l.lineid), '[]'::jsonb)
                  FROM livestockproductionlines l JOIN livestockitems i ON i.itemid = l.itemid
                  WHERE l.recordid = r.recordid AND NOT l.isreversed),
        'createdBy', r.createdby, 'createdAt', r.createdat, 'updatedBy', r.updatedby, 'updatedAt', r.updatedat)
    FROM livestockproductionrecords r
    JOIN livestockgroups g ON g.groupid = r.groupid
    JOIN livestockspecies s ON s.speciescode = g.speciescode
    WHERE r.recordid = p_recordid;
$f$;

-- p_filter: {groupId, speciesCode, from, to}
CREATE OR REPLACE FUNCTION public.splivestockproduction_list(p_farmid text, p_filter jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(fnlivestock_recordjson(r.recordid) ORDER BY r.recorddate DESC, g.name), '[]'::jsonb)
    FROM livestockproductionrecords r JOIN livestockgroups g ON g.groupid = r.groupid
    WHERE r.farmid = p_farmid AND NOT r.isdeleted
      AND (NULLIF(p_filter->>'groupId', '') IS NULL OR r.groupid = (p_filter->>'groupId')::int)
      AND (NULLIF(p_filter->>'speciesCode', '') IS NULL OR g.speciescode = p_filter->>'speciesCode')
      AND (NULLIF(p_filter->>'from', '') IS NULL OR r.recorddate >= (p_filter->>'from')::date)
      AND (NULLIF(p_filter->>'to', '') IS NULL OR r.recorddate <= (p_filter->>'to')::date);
$f$;

CREATE OR REPLACE FUNCTION public.splivestockproduction_get(p_farmid text, p_recordid integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM livestockproductionrecords WHERE recordid = p_recordid AND farmid = p_farmid AND NOT isdeleted) THEN
        RAISE EXCEPTION 'That production record was not found.' USING ERRCODE = 'P0001';
    END IF;
    RETURN fnlivestock_recordjson(p_recordid);
END
$f$;

-- Create or edit a day's record. Body:
--   { recordId?, groupId, date, deaths, deathCause, culls, eggsCollected,
--     eggsBroken, milkLitres, waterLitres, notes,
--     feedLines: [{itemId, quantity, notes}], medicationLines: [{itemId, quantity, notes}] }
-- On edit everything the record posted is reversed and posted again, all in
-- this one transaction, so a refusal leaves the old record exactly as it was.
CREATE OR REPLACE FUNCTION public.splivestockproduction_save(p_farmid text, p_record jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id      integer := NULLIF(p_record->>'recordId', '')::int;
    v_groupid integer := NULLIF(p_record->>'groupId', '')::int;
    v_date    date    := NULLIF(p_record->>'date', '')::date;
    v_deaths  integer := COALESCE(NULLIF(p_record->>'deaths', '')::int, 0);
    v_culls   integer := COALESCE(NULLIF(p_record->>'culls', '')::int, 0);
    v_eggs    integer := NULLIF(p_record->>'eggsCollected', '')::int;
    v_broken  integer := NULLIF(p_record->>'eggsBroken', '')::int;
    v_milk    numeric := NULLIF(p_record->>'milkLitres', '')::numeric;
    v_water   numeric := NULLIF(p_record->>'waterLitres', '')::numeric;
    v_g       livestockgroups%ROWTYPE;
    v_sp      livestockspecies%ROWTYPE;
    v_old     livestockproductionrecords%ROWTYPE;
    v_line    jsonb;
    v_kind    text;
    v_item    livestockitems%ROWTYPE;
    v_qty     numeric;
    v_mid     integer;
    v_m       livestockstockmovements%ROWTYPE;
BEGIN
    IF v_id IS NOT NULL THEN
        SELECT * INTO v_old FROM livestockproductionrecords WHERE recordid = v_id AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That production record was not found.' USING ERRCODE = 'P0001';
        END IF;
        v_groupid := v_old.groupid;   -- a record never moves to another group
    END IF;

    SELECT * INTO v_g FROM livestockgroups WHERE groupid = v_groupid AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Choose the group this record is for.' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO v_sp FROM livestockspecies WHERE speciescode = v_g.speciescode;
    IF v_date IS NULL THEN
        RAISE EXCEPTION 'Enter the date.' USING ERRCODE = 'P0001';
    END IF;
    IF v_date > (now() at time zone 'utc')::date + 1 THEN
        RAISE EXCEPTION 'The date cannot be in the future.' USING ERRCODE = 'P0001';
    END IF;
    IF v_date < v_g.startdate THEN
        RAISE EXCEPTION '% started on %, so there is nothing to record before that.', v_g.name,
            to_char(v_g.startdate, 'DD Mon YYYY') USING ERRCODE = 'P0001';
    END IF;
    IF v_g.status = 'Closed' AND v_date > v_g.closeddate THEN
        RAISE EXCEPTION '% was closed on %.', v_g.name, to_char(v_g.closeddate, 'DD Mon YYYY') USING ERRCODE = 'P0001';
    END IF;
    IF v_id IS NULL AND v_g.status = 'Closed' THEN
        RAISE EXCEPTION '% is closed. Reopen it to add records.', v_g.name USING ERRCODE = 'P0001';
    END IF;
    IF v_deaths < 0 OR v_culls < 0 THEN
        RAISE EXCEPTION 'Deaths and culls cannot be negative.' USING ERRCODE = 'P0001';
    END IF;
    IF (v_eggs IS NOT NULL OR v_broken IS NOT NULL) AND NOT v_sp.produceseggs THEN
        RAISE EXCEPTION '% do not lay eggs.', v_sp.name USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(v_broken, 0) > COALESCE(v_eggs, 0) THEN
        RAISE EXCEPTION 'More eggs broken than collected.' USING ERRCODE = 'P0001';
    END IF;
    IF v_milk IS NOT NULL AND NOT v_sp.producesmilk THEN
        RAISE EXCEPTION '% are not milked.', v_sp.name USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM livestockproductionrecords WHERE groupid = v_groupid AND recorddate = v_date
               AND NOT isdeleted AND recordid IS DISTINCT FROM v_id) THEN
        RAISE EXCEPTION '% already has a record for %. Open it and change that one.', v_g.name,
            to_char(v_date, 'DD Mon YYYY') USING ERRCODE = 'P0010';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO livestockproductionrecords (farmid, groupid, recorddate, deaths, deathcause, culls, eggscollected,
                                                eggsbroken, milklitres, waterlitres, notes, createdby)
        VALUES (p_farmid, v_groupid, v_date, v_deaths, NULLIF(btrim(p_record->>'deathCause'), ''), v_culls, v_eggs,
                v_broken, v_milk, v_water, NULLIF(btrim(p_record->>'notes'), ''), p_by)
        RETURNING recordid INTO v_id;
    ELSE
        PERFORM fnlivestock_reversesource('ProductionRecord', v_id, p_by, 'Record edited');
        UPDATE livestockproductionlines SET isreversed = TRUE WHERE recordid = v_id AND NOT isreversed;
        UPDATE livestockproductionrecords SET recorddate = v_date, deaths = v_deaths,
            deathcause = NULLIF(btrim(p_record->>'deathCause'), ''), culls = v_culls, eggscollected = v_eggs,
            eggsbroken = v_broken, milklitres = v_milk, waterlitres = v_water, notes = NULLIF(btrim(p_record->>'notes'), ''),
            updatedat = (now() at time zone 'utc'), updatedby = p_by
        WHERE recordid = v_id;
    END IF;

    IF v_deaths > 0 THEN
        PERFORM splivestockhead_post(p_farmid, v_groupid, v_date, 'Death', -v_deaths, p_by,
            COALESCE(NULLIF(btrim(p_record->>'deathCause'), ''), 'Daily record'), NULL, NULL, 'ProductionRecord', v_id);
    END IF;
    IF v_culls > 0 THEN
        PERFORM splivestockhead_post(p_farmid, v_groupid, v_date, 'Cull', -v_culls, p_by,
            'Daily record', NULL, NULL, 'ProductionRecord', v_id);
    END IF;

    FOR v_kind, v_line IN
        SELECT 'Feed', e FROM jsonb_array_elements(COALESCE(p_record->'feedLines', '[]'::jsonb)) e
        UNION ALL
        SELECT 'Medication', e FROM jsonb_array_elements(COALESCE(p_record->'medicationLines', '[]'::jsonb)) e
    LOOP
        v_qty := NULLIF(v_line->>'quantity', '')::numeric;
        CONTINUE WHEN v_qty IS NULL AND NULLIF(v_line->>'itemId', '') IS NULL;   -- an empty row
        SELECT * INTO v_item FROM livestockitems WHERE itemid = NULLIF(v_line->>'itemId', '')::int
            AND farmid = p_farmid AND NOT isdeleted;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Choose the % item on every line.', lower(v_kind) USING ERRCODE = 'P0001';
        END IF;
        IF v_kind = 'Feed' AND v_item.category <> 'Feed' THEN
            RAISE EXCEPTION '% is not feed.', v_item.name USING ERRCODE = 'P0001';
        END IF;
        IF v_kind = 'Medication' AND v_item.category NOT IN ('Medication', 'Vaccine') THEN
            RAISE EXCEPTION '% is not a medication or vaccine.', v_item.name USING ERRCODE = 'P0001';
        END IF;
        IF v_item.speciescode IS NOT NULL AND v_item.speciescode <> v_g.speciescode THEN
            RAISE EXCEPTION '% is for %.', v_item.name,
                lower((SELECT name FROM livestockspecies WHERE speciescode = v_item.speciescode)) USING ERRCODE = 'P0001';
        END IF;
        IF v_qty IS NULL OR v_qty <= 0 THEN
            RAISE EXCEPTION 'Enter how much % was used.', v_item.name USING ERRCODE = 'P0001';
        END IF;
        v_mid := splivestockstock_post(p_farmid, v_item.itemid, v_date, 'Usage', -v_qty, NULL, p_by,
                                       v_g.name || ' daily record', 'ProductionRecord', v_id, v_groupid);
        SELECT * INTO v_m FROM livestockstockmovements WHERE movementid = v_mid;
        INSERT INTO livestockproductionlines (recordid, linetype, itemid, quantity, unitcost, totalcost, stockmovementid, notes)
        VALUES (v_id, v_kind, v_item.itemid, v_qty, v_m.unitcost, -v_m.totalcost, v_mid, NULLIF(btrim(v_line->>'notes'), ''));
    END LOOP;

    -- Eggs (less broken) and milk go into the farm's produce stock.
    IF COALESCE(v_eggs, 0) - COALESCE(v_broken, 0) > 0 THEN
        PERFORM splivestockstock_post(p_farmid, fnlivestock_produceitem(p_farmid, v_g.speciescode, 'Eggs'), v_date, 'Produced',
            v_eggs - COALESCE(v_broken, 0), 0, p_by, v_g.name || ' daily record', 'ProductionRecord', v_id, v_groupid);
    END IF;
    IF COALESCE(v_milk, 0) > 0 THEN
        PERFORM splivestockstock_post(p_farmid, fnlivestock_produceitem(p_farmid, v_g.speciescode, 'Milk'), v_date, 'Produced',
            v_milk, 0, p_by, v_g.name || ' daily record', 'ProductionRecord', v_id, v_groupid);
    END IF;
    PERFORM fnlivestock_checkproduce(p_farmid, v_g.speciescode);

    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockproduction_delete(p_farmid text, p_recordid integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_r livestockproductionrecords%ROWTYPE;
BEGIN
    SELECT * INTO v_r FROM livestockproductionrecords WHERE recordid = p_recordid AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That production record was not found.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM fnlivestock_reversesource('ProductionRecord', p_recordid, p_by, 'Record deleted');
    UPDATE livestockproductionlines SET isreversed = TRUE WHERE recordid = p_recordid AND NOT isreversed;
    PERFORM fnlivestock_checkproduce(p_farmid, (SELECT speciescode FROM livestockgroups WHERE groupid = v_r.groupid));
    UPDATE livestockproductionrecords SET isdeleted = TRUE, updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE recordid = p_recordid;
END
$f$;

-- What the record form needs for a group and date: the group, its head on
-- the day before, whether a record exists, and the species' outputs.
CREATE OR REPLACE FUNCTION public.splivestockproduction_form(p_farmid text, p_groupid integer, p_date date)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE v_g livestockgroups%ROWTYPE; v_sp livestockspecies%ROWTYPE; v_existing integer;
BEGIN
    SELECT * INTO v_g FROM livestockgroups WHERE groupid = p_groupid AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That group was not found.' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO v_sp FROM livestockspecies WHERE speciescode = v_g.speciescode;
    SELECT recordid INTO v_existing FROM livestockproductionrecords
    WHERE groupid = p_groupid AND recorddate = p_date AND NOT isdeleted;
    RETURN jsonb_build_object(
        'groupId', v_g.groupid, 'groupName', v_g.name, 'speciesCode', v_g.speciescode, 'speciesName', v_sp.name,
        'producesEggs', v_sp.produceseggs, 'producesMilk', v_sp.producesmilk,
        'startDate', v_g.startdate, 'status', v_g.status,
        'headStartOfDay', fnlivestock_groupheadasof(p_groupid, p_date - 1),
        'headNow', fnlivestock_grouphead(p_groupid),
        'existingRecordId', v_existing,
        'lastRecord', (SELECT fnlivestock_recordjson(r.recordid) FROM livestockproductionrecords r
                       WHERE r.groupid = p_groupid AND NOT r.isdeleted AND r.recorddate < p_date
                       ORDER BY r.recorddate DESC LIMIT 1));
END
$f$;

-- ---------------------------------------------------------------------------
-- 3. Breeding
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockbreedingevents (
    eventid       serial PRIMARY KEY,
    farmid        text NOT NULL,
    eventtype     text NOT NULL CHECK (eventtype IN ('Mating', 'PregnancyCheck', 'Birth', 'Weaning', 'Loss')),
    eventdate     date NOT NULL,
    speciescode   text NOT NULL REFERENCES livestockspecies(speciescode),
    damid         integer REFERENCES livestockanimals(animalid),
    sireid        integer REFERENCES livestockanimals(animalid),
    groupid       integer REFERENCES livestockgroups(groupid),        -- where the young are (birth) / come from (weaning)
    togroupid     integer REFERENCES livestockgroups(groupid),        -- weaning: where they move to
    method        text CHECK (method IS NULL OR method IN ('Natural', 'AI')),
    result        text CHECK (result IS NULL OR result IN ('Pregnant', 'NotPregnant')),
    bornalive     integer CHECK (bornalive IS NULL OR bornalive >= 0),
    borndead      integer CHECK (borndead IS NULL OR borndead >= 0),
    weanedcount   integer CHECK (weanedcount IS NULL OR weanedcount >= 0),
    notes         text,
    isdeleted     boolean NOT NULL DEFAULT FALSE,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    updatedat     timestamp,
    updatedby     text
);
CREATE INDEX IF NOT EXISTS ixlivestockbreedingevents_farm ON livestockbreedingevents (farmid, eventdate) WHERE NOT isdeleted;
CREATE INDEX IF NOT EXISTS ixlivestockbreedingevents_dam ON livestockbreedingevents (damid, eventdate) WHERE NOT isdeleted;

CREATE OR REPLACE FUNCTION public.fnlivestock_breedingjson(p_eventid integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'eventId', e.eventid, 'eventType', e.eventtype, 'date', e.eventdate, 'speciesCode', e.speciescode,
        'speciesName', s.name, 'birthTerm', s.birthterm, 'youngTerm', s.youngterm,
        'damId', e.damid, 'damTag', d.tagnumber, 'sireId', e.sireid, 'sireTag', si.tagnumber,
        'groupId', e.groupid, 'groupName', g.name, 'toGroupId', e.togroupid, 'toGroupName', tg.name,
        'method', e.method, 'result', e.result, 'bornAlive', e.bornalive, 'bornDead', e.borndead,
        'weanedCount', e.weanedcount, 'notes', e.notes,
        'expectedBirth', CASE WHEN e.eventtype = 'Mating' AND s.gestationdays IS NOT NULL
                              THEN e.eventdate + s.gestationdays END,
        'createdBy', e.createdby)
    FROM livestockbreedingevents e
    JOIN livestockspecies s ON s.speciescode = e.speciescode
    LEFT JOIN livestockanimals d ON d.animalid = e.damid
    LEFT JOIN livestockanimals si ON si.animalid = e.sireid
    LEFT JOIN livestockgroups g ON g.groupid = e.groupid
    LEFT JOIN livestockgroups tg ON tg.groupid = e.togroupid
    WHERE e.eventid = p_eventid;
$f$;

-- p_filter: {damId, groupId, speciesCode, eventType, from, to}
CREATE OR REPLACE FUNCTION public.splivestockbreeding_list(p_farmid text, p_filter jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(fnlivestock_breedingjson(e.eventid) ORDER BY e.eventdate DESC, e.eventid DESC), '[]'::jsonb)
    FROM livestockbreedingevents e
    WHERE e.farmid = p_farmid AND NOT e.isdeleted
      AND (NULLIF(p_filter->>'damId', '') IS NULL OR e.damid = (p_filter->>'damId')::int OR e.sireid = (p_filter->>'damId')::int)
      AND (NULLIF(p_filter->>'groupId', '') IS NULL OR e.groupid = (p_filter->>'groupId')::int OR e.togroupid = (p_filter->>'groupId')::int)
      AND (NULLIF(p_filter->>'speciesCode', '') IS NULL OR e.speciescode = p_filter->>'speciesCode')
      AND (NULLIF(p_filter->>'eventType', '') IS NULL OR e.eventtype = p_filter->>'eventType')
      AND (NULLIF(p_filter->>'from', '') IS NULL OR e.eventdate >= (p_filter->>'from')::date)
      AND (NULLIF(p_filter->>'to', '') IS NULL OR e.eventdate <= (p_filter->>'to')::date);
$f$;

-- Females mated and not yet resolved: no birth, empty check or loss for that
-- dam after the mating. Sorted by when they are due.
CREATE OR REPLACE FUNCTION public.splivestockbreeding_due(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.due NULLS LAST), '[]'::jsonb) FROM (
        SELECT fnlivestock_breedingjson(m.eventid) || jsonb_build_object(
                   'pregnancyConfirmed', EXISTS (SELECT 1 FROM livestockbreedingevents c WHERE c.damid = m.damid
                        AND NOT c.isdeleted AND c.eventtype = 'PregnancyCheck' AND c.result = 'Pregnant' AND c.eventdate >= m.eventdate),
                   'daysToDue', (m.eventdate + s.gestationdays) - (now() at time zone 'utc')::date) AS j,
               m.eventdate + s.gestationdays AS due
        FROM livestockbreedingevents m
        JOIN livestockspecies s ON s.speciescode = m.speciescode
        JOIN livestockanimals d ON d.animalid = m.damid AND d.status = 'Active' AND NOT d.isdeleted
        WHERE m.farmid = p_farmid AND NOT m.isdeleted AND m.eventtype = 'Mating'
          -- the latest mating of that dam
          AND NOT EXISTS (SELECT 1 FROM livestockbreedingevents m2 WHERE m2.damid = m.damid AND NOT m2.isdeleted
                          AND m2.eventtype = 'Mating' AND (m2.eventdate, m2.eventid) > (m.eventdate, m.eventid))
          AND NOT EXISTS (SELECT 1 FROM livestockbreedingevents r WHERE r.damid = m.damid AND NOT r.isdeleted
                          AND r.eventdate >= m.eventdate
                          AND (r.eventtype IN ('Birth', 'Loss') OR (r.eventtype = 'PregnancyCheck' AND r.result = 'NotPregnant')))
    ) x;
$f$;

-- Create or edit a breeding event. A birth's live young are a 'Birth' head
-- movement into groupId; a weaning with toGroupId moves weanedCount from
-- groupId to toGroupId. Editing reverses what the event posted and posts again.
CREATE OR REPLACE FUNCTION public.splivestockbreeding_save(p_farmid text, p_event jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id     integer := NULLIF(p_event->>'eventId', '')::int;
    v_type   text    := NULLIF(p_event->>'eventType', '');
    v_date   date    := NULLIF(p_event->>'date', '')::date;
    v_damid  integer := NULLIF(p_event->>'damId', '')::int;
    v_sireid integer := NULLIF(p_event->>'sireId', '')::int;
    v_gid    integer := NULLIF(p_event->>'groupId', '')::int;
    v_toid   integer := NULLIF(p_event->>'toGroupId', '')::int;
    v_alive  integer := NULLIF(p_event->>'bornAlive', '')::int;
    v_dead   integer := NULLIF(p_event->>'bornDead', '')::int;
    v_weaned integer := NULLIF(p_event->>'weanedCount', '')::int;
    v_result text    := NULLIF(p_event->>'result', '');
    v_old    livestockbreedingevents%ROWTYPE;
    v_dam    livestockanimals%ROWTYPE;
    v_sire   livestockanimals%ROWTYPE;
    v_g      livestockgroups%ROWTYPE;
    v_to     livestockgroups%ROWTYPE;
    v_sp     livestockspecies%ROWTYPE;
    v_species text;
    v_out    integer;
    v_in     integer;
BEGIN
    IF v_id IS NOT NULL THEN
        SELECT * INTO v_old FROM livestockbreedingevents WHERE eventid = v_id AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That breeding record was not found.' USING ERRCODE = 'P0001';
        END IF;
        v_type := v_old.eventtype;
    END IF;
    IF v_type NOT IN ('Mating', 'PregnancyCheck', 'Birth', 'Weaning', 'Loss') OR v_type IS NULL THEN
        RAISE EXCEPTION 'Choose what happened.' USING ERRCODE = 'P0001';
    END IF;
    IF v_date IS NULL OR v_date > (now() at time zone 'utc')::date + 1 THEN
        RAISE EXCEPTION 'Enter a date that is not in the future.' USING ERRCODE = 'P0001';
    END IF;

    -- The dam: required for mating, checks and losses; optional for a birth or
    -- weaning recorded on a group of untagged animals (rabbits in a colony).
    IF v_damid IS NOT NULL THEN
        SELECT * INTO v_dam FROM livestockanimals WHERE animalid = v_damid AND farmid = p_farmid AND NOT isdeleted;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'The mother was not found.' USING ERRCODE = 'P0001';
        END IF;
        IF v_dam.sex = 'Male' THEN
            RAISE EXCEPTION 'Tag % is a male.', v_dam.tagnumber USING ERRCODE = 'P0001';
        END IF;
        IF v_dam.birthdate IS NOT NULL AND v_date < v_dam.birthdate THEN
            RAISE EXCEPTION 'Tag % was not born yet on that date.', v_dam.tagnumber USING ERRCODE = 'P0001';
        END IF;
        v_species := v_dam.speciescode;
    ELSIF v_type IN ('Mating', 'PregnancyCheck', 'Loss') THEN
        RAISE EXCEPTION 'Choose the female.' USING ERRCODE = 'P0001';
    END IF;
    IF v_sireid IS NOT NULL THEN
        SELECT * INTO v_sire FROM livestockanimals WHERE animalid = v_sireid AND farmid = p_farmid AND NOT isdeleted;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'The male was not found.' USING ERRCODE = 'P0001';
        END IF;
        IF v_sire.sex = 'Female' THEN
            RAISE EXCEPTION 'Tag % is a female.', v_sire.tagnumber USING ERRCODE = 'P0001';
        END IF;
        IF v_species IS NOT NULL AND v_sire.speciescode <> v_species THEN
            RAISE EXCEPTION 'The male and female are different kinds of animal.' USING ERRCODE = 'P0001';
        END IF;
        v_species := COALESCE(v_species, v_sire.speciescode);
    END IF;

    IF v_type IN ('Birth', 'Weaning') THEN
        SELECT * INTO v_g FROM livestockgroups WHERE groupid = v_gid AND farmid = p_farmid AND NOT isdeleted;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Choose the group the young %.', CASE WHEN v_type = 'Birth' THEN 'go into' ELSE 'are in' END
                USING ERRCODE = 'P0001';
        END IF;
        IF v_species IS NOT NULL AND v_g.speciescode <> v_species THEN
            RAISE EXCEPTION '% is a group of another kind of animal.', v_g.name USING ERRCODE = 'P0001';
        END IF;
        v_species := v_g.speciescode;
    ELSE
        v_gid := NULL; v_toid := NULL;
    END IF;

    SELECT * INTO v_sp FROM livestockspecies WHERE speciescode = v_species;
    IF NOT v_sp.breedsonfarm THEN
        RAISE EXCEPTION 'Breeding is not recorded for %.', lower(v_sp.name) USING ERRCODE = 'P0001';
    END IF;

    IF v_type = 'PregnancyCheck' AND v_result IS NULL THEN
        RAISE EXCEPTION 'Say whether she is pregnant.' USING ERRCODE = 'P0001';
    END IF;
    IF v_type = 'Birth' AND COALESCE(v_alive, 0) + COALESCE(v_dead, 0) = 0 THEN
        RAISE EXCEPTION 'Enter how many were born.' USING ERRCODE = 'P0001';
    END IF;
    IF v_type = 'Weaning' AND COALESCE(v_weaned, 0) <= 0 THEN
        RAISE EXCEPTION 'Enter how many were weaned.' USING ERRCODE = 'P0001';
    END IF;
    IF v_type = 'Weaning' AND v_toid IS NOT NULL THEN
        SELECT * INTO v_to FROM livestockgroups WHERE groupid = v_toid AND farmid = p_farmid AND NOT isdeleted;
        IF NOT FOUND OR v_to.groupid = v_gid OR v_to.speciescode <> v_species OR v_to.status <> 'Active' THEN
            RAISE EXCEPTION 'Choose another active group of the same kind to move them to.' USING ERRCODE = 'P0001';
        END IF;
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO livestockbreedingevents (farmid, eventtype, eventdate, speciescode, damid, sireid, groupid, togroupid,
            method, result, bornalive, borndead, weanedcount, notes, createdby)
        VALUES (p_farmid, v_type, v_date, v_species, v_damid, v_sireid, v_gid, v_toid,
            CASE WHEN v_type = 'Mating' THEN COALESCE(NULLIF(p_event->>'method', ''), 'Natural') END,
            CASE WHEN v_type = 'PregnancyCheck' THEN v_result END,
            CASE WHEN v_type = 'Birth' THEN COALESCE(v_alive, 0) END, CASE WHEN v_type = 'Birth' THEN COALESCE(v_dead, 0) END,
            CASE WHEN v_type = 'Weaning' THEN v_weaned END, NULLIF(btrim(p_event->>'notes'), ''), p_by)
        RETURNING eventid INTO v_id;
    ELSE
        PERFORM fnlivestock_reversesource('BreedingEvent', v_id, p_by, 'Breeding record edited');
        UPDATE livestockbreedingevents SET eventdate = v_date, speciescode = v_species, damid = v_damid, sireid = v_sireid,
            groupid = v_gid, togroupid = v_toid,
            method = CASE WHEN v_type = 'Mating' THEN COALESCE(NULLIF(p_event->>'method', ''), 'Natural') END,
            result = CASE WHEN v_type = 'PregnancyCheck' THEN v_result END,
            bornalive = CASE WHEN v_type = 'Birth' THEN COALESCE(v_alive, 0) END,
            borndead = CASE WHEN v_type = 'Birth' THEN COALESCE(v_dead, 0) END,
            weanedcount = CASE WHEN v_type = 'Weaning' THEN v_weaned END,
            notes = NULLIF(btrim(p_event->>'notes'), ''), updatedat = (now() at time zone 'utc'), updatedby = p_by
        WHERE eventid = v_id;
    END IF;

    IF v_type = 'Birth' AND COALESCE(v_alive, 0) > 0 THEN
        IF v_g.status <> 'Active' THEN
            RAISE EXCEPTION '% is closed. Choose an active group for the young.', v_g.name USING ERRCODE = 'P0001';
        END IF;
        PERFORM splivestockhead_post(p_farmid, v_gid, GREATEST(v_date, v_g.startdate), 'Birth', v_alive, p_by,
            COALESCE(v_sp.birthterm, 'Birth') || COALESCE(' of tag ' || v_dam.tagnumber, ''), NULL, NULL, 'BreedingEvent', v_id);
    ELSIF v_type = 'Weaning' AND v_toid IS NOT NULL THEN
        v_out := splivestockhead_post(p_farmid, v_gid, v_date, 'TransferOut', -v_weaned, p_by,
            'Weaned to ' || v_to.name, NULL, NULL, 'BreedingEvent', v_id);
        v_in  := splivestockhead_post(p_farmid, v_toid, v_date, 'TransferIn', v_weaned, p_by,
            'Weaned from ' || v_g.name, NULL, NULL, 'BreedingEvent', v_id);
        UPDATE livestockheadmovements SET pairedmovementid = v_in WHERE movementid = v_out;
        UPDATE livestockheadmovements SET pairedmovementid = v_out WHERE movementid = v_in;
    END IF;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockbreeding_delete(p_farmid text, p_eventid integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_e livestockbreedingevents%ROWTYPE;
BEGIN
    SELECT * INTO v_e FROM livestockbreedingevents WHERE eventid = p_eventid AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That breeding record was not found.' USING ERRCODE = 'P0001';
    END IF;
    -- Removing a birth takes its young back out of the group: refuse if that
    -- would leave the group below zero (some already sold, died or moved).
    IF EXISTS (SELECT 1 FROM livestockheadmovements m WHERE m.sourcetype = 'BreedingEvent' AND m.sourceid = p_eventid
               AND m.reversedat IS NULL AND m.quantity > 0 AND fnlivestock_grouphead(m.groupid) - m.quantity < 0) THEN
        RAISE EXCEPTION 'Some of these young are no longer in the group, so this cannot be deleted. Correct the count instead.'
            USING ERRCODE = 'P0001';
    END IF;
    PERFORM fnlivestock_reversesource('BreedingEvent', p_eventid, p_by, 'Breeding record deleted');
    UPDATE livestockbreedingevents SET isdeleted = TRUE, updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE eventid = p_eventid;
END
$f$;

-- ---------------------------------------------------------------------------
-- 4. Weigh-ins
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockweighins (
    weighinid     serial PRIMARY KEY,
    farmid        text NOT NULL,
    groupid       integer NOT NULL REFERENCES livestockgroups(groupid),
    animalid      integer REFERENCES livestockanimals(animalid),   -- NULL = a sample of the group
    weighdate     date NOT NULL,
    samplesize    integer CHECK (samplesize IS NULL OR samplesize > 0),
    avgweightkg   numeric(10,3) NOT NULL CHECK (avgweightkg > 0),
    notes         text,
    isdeleted     boolean NOT NULL DEFAULT FALSE,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text
);
CREATE INDEX IF NOT EXISTS ixlivestockweighins_group ON livestockweighins (groupid, weighdate) WHERE NOT isdeleted;

CREATE OR REPLACE FUNCTION public.splivestockweighin_save(p_farmid text, p_w jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id   integer := NULLIF(p_w->>'weighInId', '')::int;
    v_gid  integer := NULLIF(p_w->>'groupId', '')::int;
    v_aid  integer := NULLIF(p_w->>'animalId', '')::int;
    v_date date    := NULLIF(p_w->>'date', '')::date;
    v_kg   numeric := NULLIF(p_w->>'avgWeightKg', '')::numeric;
    v_n    integer := NULLIF(p_w->>'sampleSize', '')::int;
    v_g    livestockgroups%ROWTYPE;
BEGIN
    IF v_aid IS NOT NULL THEN
        SELECT groupid INTO v_gid FROM livestockanimals WHERE animalid = v_aid AND farmid = p_farmid AND NOT isdeleted;
        IF v_gid IS NULL THEN
            RAISE EXCEPTION 'That animal was not found.' USING ERRCODE = 'P0001';
        END IF;
        v_n := 1;
    END IF;
    SELECT * INTO v_g FROM livestockgroups WHERE groupid = v_gid AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Choose the group that was weighed.' USING ERRCODE = 'P0001';
    END IF;
    IF v_date IS NULL OR v_date > (now() at time zone 'utc')::date + 1 OR v_date < v_g.startdate THEN
        RAISE EXCEPTION 'Enter a date between the group''s start and today.' USING ERRCODE = 'P0001';
    END IF;
    IF v_kg IS NULL OR v_kg <= 0 THEN
        RAISE EXCEPTION 'Enter the average weight in kg.' USING ERRCODE = 'P0001';
    END IF;
    IF v_n IS NOT NULL AND v_n <= 0 THEN
        RAISE EXCEPTION 'The number weighed must be at least one.' USING ERRCODE = 'P0001';
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO livestockweighins (farmid, groupid, animalid, weighdate, samplesize, avgweightkg, notes, createdby)
        VALUES (p_farmid, v_gid, v_aid, v_date, v_n, v_kg, NULLIF(btrim(p_w->>'notes'), ''), p_by)
        RETURNING weighinid INTO v_id;
    ELSE
        UPDATE livestockweighins SET weighdate = v_date, samplesize = v_n, avgweightkg = v_kg, notes = NULLIF(btrim(p_w->>'notes'), '')
        WHERE weighinid = v_id AND farmid = p_farmid AND NOT isdeleted;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That weigh-in was not found.' USING ERRCODE = 'P0001';
        END IF;
    END IF;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockweighin_delete(p_farmid text, p_weighinid integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    UPDATE livestockweighins SET isdeleted = TRUE WHERE weighinid = p_weighinid AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That weigh-in was not found.' USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- A group's growth: each group weigh-in (animal weigh-ins listed apart) with
-- the gain since the previous one, daily gain, the feed eaten between them
-- (kg, from feed lines whose item has a kg size) and feed conversion
-- (feed kg / kg gained by the whole group, using the head on each date).
CREATE OR REPLACE FUNCTION public.splivestockgrowth(p_farmid text, p_groupid integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE v_rows jsonb;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM livestockgroups WHERE groupid = p_groupid AND farmid = p_farmid AND NOT isdeleted) THEN
        RAISE EXCEPTION 'That group was not found.' USING ERRCODE = 'P0001';
    END IF;
    WITH w AS (
        SELECT wi.*, lag(wi.weighdate) OVER (ORDER BY wi.weighdate, wi.weighinid) AS prevdate,
                     lag(wi.avgweightkg) OVER (ORDER BY wi.weighdate, wi.weighinid) AS prevkg
        FROM livestockweighins wi
        WHERE wi.groupid = p_groupid AND wi.animalid IS NULL AND NOT wi.isdeleted
    ), f AS (
        SELECT w.*,
               fnlivestock_groupheadasof(p_groupid, w.weighdate) AS head,
               fnlivestock_groupheadasof(p_groupid, w.prevdate) AS prevhead,
               (SELECT SUM(l.quantity * i.kgperunit) FROM livestockproductionlines l
                  JOIN livestockproductionrecords r ON r.recordid = l.recordid AND NOT r.isdeleted
                  JOIN livestockitems i ON i.itemid = l.itemid
                WHERE r.groupid = p_groupid AND l.linetype = 'Feed' AND NOT l.isreversed
                  AND r.recorddate > w.prevdate AND r.recorddate <= w.weighdate) AS feedkg
        FROM w
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'weighInId', f.weighinid, 'date', f.weighdate, 'sampleSize', f.samplesize, 'avgWeightKg', f.avgweightkg,
        'head', f.head, 'notes', f.notes,
        'gainKg', CASE WHEN f.prevkg IS NOT NULL THEN round(f.avgweightkg - f.prevkg, 3) END,
        'days', CASE WHEN f.prevdate IS NOT NULL THEN f.weighdate - f.prevdate END,
        'dailyGainG', CASE WHEN f.prevdate IS NOT NULL AND f.weighdate > f.prevdate
                           THEN round((f.avgweightkg - f.prevkg) * 1000 / (f.weighdate - f.prevdate), 1) END,
        'feedKg', round(f.feedkg, 2),
        'fcr', CASE WHEN f.feedkg IS NOT NULL AND f.prevkg IS NOT NULL
                         AND (f.avgweightkg * f.head - f.prevkg * f.prevhead) > 0
                    THEN round(f.feedkg / (f.avgweightkg * f.head - f.prevkg * f.prevhead), 2) END
    ) ORDER BY f.weighdate DESC, f.weighinid DESC), '[]'::jsonb) INTO v_rows FROM f;

    RETURN jsonb_build_object(
        'groupId', p_groupid,
        'weighIns', v_rows,
        'animalWeighIns', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'weighInId', wi.weighinid, 'date', wi.weighdate, 'animalId', wi.animalid, 'tagNumber', a.tagnumber,
                'avgWeightKg', wi.avgweightkg, 'notes', wi.notes) ORDER BY wi.weighdate DESC), '[]'::jsonb)
            FROM livestockweighins wi JOIN livestockanimals a ON a.animalid = wi.animalid
            WHERE wi.groupid = p_groupid AND NOT wi.isdeleted),
        'feedKgTotal', (SELECT round(SUM(l.quantity * i.kgperunit), 2) FROM livestockproductionlines l
                  JOIN livestockproductionrecords r ON r.recordid = l.recordid AND NOT r.isdeleted
                  JOIN livestockitems i ON i.itemid = l.itemid
                WHERE r.groupid = p_groupid AND l.linetype = 'Feed' AND NOT l.isreversed),
        'feedWithoutKg', EXISTS (SELECT 1 FROM livestockproductionlines l
                  JOIN livestockproductionrecords r ON r.recordid = l.recordid AND NOT r.isdeleted
                  JOIN livestockitems i ON i.itemid = l.itemid
                WHERE r.groupid = p_groupid AND l.linetype = 'Feed' AND NOT l.isreversed AND i.kgperunit IS NULL));
END
$f$;

-- An animal's weights over time.
CREATE OR REPLACE FUNCTION public.splivestockweighin_animal(p_farmid text, p_animalid integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('weighInId', wi.weighinid, 'date', wi.weighdate,
        'avgWeightKg', wi.avgweightkg, 'notes', wi.notes) ORDER BY wi.weighdate DESC), '[]'::jsonb)
    FROM livestockweighins wi WHERE wi.farmid = p_farmid AND wi.animalid = p_animalid AND NOT wi.isdeleted;
$f$;

-- ---------------------------------------------------------------------------
-- 5. IAM
-- ---------------------------------------------------------------------------
DO $iam$
DECLARE v integer := 0;
BEGIN
    v := v + splivestock_iammirror('items', 'raw-materials', 'Feed & Stock', 'Stock Items',
            'Feed, medication, vaccines and supplies kept in stock.', 34);
    v := v + splivestock_iammirror('stock', 'stock', 'Feed & Stock', 'Stock',
            'Stock levels, adding stock and correcting counts.', 51);
    v := v + splivestock_iammirror('production-records', 'production-records', 'Production', 'Daily Records',
            'Each group''s day: deaths, culls, eggs, milk, and the feed and medication used.', 23);
    v := v + splivestock_iammirror('breeding', 'flocks', 'Animals', 'Breeding & Births',
            'Matings, pregnancy checks, births and weaning.', 14);
    v := v + splivestock_iammirror('weigh-ins', 'production-records', 'Production', 'Weigh-ins',
            'Weighing groups and animals; daily gain and feed conversion.', 24);
    RAISE NOTICE '459: % livestock permission key(s) added.', v;
END
$iam$;

COMMIT;

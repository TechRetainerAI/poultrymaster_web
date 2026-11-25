-- 494: Livestock -- feed collected from the forest / bush (forage), and grazing.
--
-- Farms cut grass, leaves and cassava tops in the forest and carry them back
-- (cut-and-carry), or drive the animals out to graze. Until now stock could
-- only come in through a purchase (469), so neither could be recorded.
--
-- 1. Forage items. A Feed item can be marked "collected, not bought"
--    (livestockitems.isforage). It stays category 'Feed', so daily-record feed
--    lines, Distribute Feed, feed reports, days of supply and the P&L "feed"
--    line all count it with no change.
--
-- 2. Collect feed. splivestockforage_collect puts a forage item into stock
--    as a new movement type 'Collected' (the third way stock comes in without
--    a purchase, after 'Produced' eggs/milk and mixed feed). An optional
--    collecting cost (transport, fuel, a cutter's wage, a permit) is paid from
--    a cash account (category 'Feed collection') and becomes the forage's cost,
--    so the P&L counts it once -- when the forage is fed -- exactly like bought
--    feed. Reversing undoes the stock and the money together, and is refused
--    once some of it has been fed (as for a purchase).
--    The Expenses list (471) shows paid collections as "Bought" rows.
--
-- 3. Grazing on the daily record: grazed (yes/no), hours out and where.
--    Nothing goes into stock -- grazing cannot be weighed.
--    fnlivestock_recordjson returns the three fields under the same names the
--    save reads, so Distribute Feed (which saves a record back from its JSON)
--    keeps them.
--
-- Function bodies are the live versions with only the parts named changed.
-- Safe to re-run.

BEGIN;

-- ---------------------------------------------------------------------------
-- Columns, movement type, collections table
-- ---------------------------------------------------------------------------
ALTER TABLE livestockitems ADD COLUMN IF NOT EXISTS isforage boolean NOT NULL DEFAULT FALSE;

ALTER TABLE livestockstockmovements DROP CONSTRAINT IF EXISTS livestockstockmovements_movementtype_check;
ALTER TABLE livestockstockmovements ADD CONSTRAINT livestockstockmovements_movementtype_check
    CHECK (movementtype IN ('Opening', 'StockIn', 'Purchase', 'Usage', 'Adjustment', 'Produced', 'Loss', 'Collected'));
ALTER TABLE livestockstockmovements DROP CONSTRAINT IF EXISTS livestockstockmovements_check;
ALTER TABLE livestockstockmovements ADD CONSTRAINT livestockstockmovements_check
    CHECK ((movementtype IN ('Opening', 'StockIn', 'Purchase', 'Produced', 'Collected') AND quantity > 0) OR
           (movementtype IN ('Usage', 'Loss') AND quantity < 0) OR movementtype = 'Adjustment');

ALTER TABLE livestockproductionrecords ADD COLUMN IF NOT EXISTS grazed boolean NOT NULL DEFAULT FALSE;
ALTER TABLE livestockproductionrecords ADD COLUMN IF NOT EXISTS grazinghours numeric(4,1);
ALTER TABLE livestockproductionrecords ADD COLUMN IF NOT EXISTS grazingplace text;
ALTER TABLE livestockproductionrecords DROP CONSTRAINT IF EXISTS livestockproductionrecords_grazinghours_check;
ALTER TABLE livestockproductionrecords ADD CONSTRAINT livestockproductionrecords_grazinghours_check
    CHECK (grazinghours IS NULL OR (grazed AND grazinghours > 0 AND grazinghours <= 24));

CREATE TABLE IF NOT EXISTS livestockforagecollections (
    collectionid   serial PRIMARY KEY,
    farmid         text NOT NULL,
    itemid         integer NOT NULL REFERENCES livestockitems(itemid),
    collectiondate date NOT NULL,
    quantity       numeric(14,3) NOT NULL CHECK (quantity > 0),
    place          text,                   -- where it was cut: "Afram forest"
    collectedby    text,                   -- who went
    cost           numeric(14,2) NOT NULL DEFAULT 0 CHECK (cost >= 0),
    accountid      integer REFERENCES livestockcashaccounts(accountid),
    notes          text,
    createdat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby      text,
    reversedat     timestamp,
    reversedby     text,
    reversereason  text,
    CHECK (cost = 0 OR accountid IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS ixlivestockforagecollections_farm
    ON livestockforagecollections (farmid, collectiondate);

DROP TRIGGER IF EXISTS trglivestockforagecollections_closedday ON livestockforagecollections;
CREATE TRIGGER trglivestockforagecollections_closedday BEFORE INSERT OR UPDATE ON livestockforagecollections
    FOR EACH ROW EXECUTE FUNCTION trglivestock_closedday('collectiondate');

-- ---------------------------------------------------------------------------
-- Items: isForage
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnlivestock_itemjson(p_itemid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    SELECT jsonb_build_object(
        'itemId', i.itemid, 'name', i.name, 'category', i.category, 'unit', i.unit, 'kgPerUnit', i.kgperunit,
        'minimumStock', i.minimumstock, 'speciesCode', i.speciescode, 'speciesName', s.name,
        'notes', i.notes, 'isActive', i.isactive, 'isForage', i.isforage,
        'stock', fnlivestock_itemstock(i.itemid), 'value', fnlivestock_itemvalue(i.itemid),
        'avgCost', fnlivestock_itemavgcost(i.itemid),
        'isLow', i.minimumstock IS NOT NULL AND fnlivestock_itemstock(i.itemid) <= i.minimumstock,
        'hasMovements', EXISTS (SELECT 1 FROM livestockstockmovements m WHERE m.itemid = i.itemid))
    FROM livestockitems i LEFT JOIN livestockspecies s ON s.speciescode = i.speciescode
    WHERE i.itemid = p_itemid;
$function$;

-- The 469 body; isForage added (Feed items only).
CREATE OR REPLACE FUNCTION public.splivestockitem_save(p_farmid text, p_item jsonb, p_by text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id    integer := NULLIF(p_item->>'itemId', '')::int;
    v_name  text    := btrim(COALESCE(p_item->>'name', ''));
    v_cat   text    := COALESCE(NULLIF(p_item->>'category', ''), 'Feed');
    v_unit  text    := COALESCE(NULLIF(btrim(p_item->>'unit'), ''), 'kg');
    v_kg    numeric := NULLIF(p_item->>'kgPerUnit', '')::numeric;
    v_min   numeric := NULLIF(p_item->>'minimumStock', '')::numeric;
    v_sp    text    := NULLIF(btrim(COALESCE(p_item->>'speciesCode', '')), '');
    v_forage boolean := COALESCE(NULLIF(p_item->>'isForage', '')::boolean, FALSE);
    v_old   livestockitems%ROWTYPE;
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Give the item a name.' USING ERRCODE = 'P0001';
    END IF;
    IF v_cat NOT IN ('Feed', 'Ingredient', 'Medication', 'Vaccine', 'Supply', 'Produce', 'Other') THEN
        RAISE EXCEPTION 'Unknown category "%".', v_cat USING ERRCODE = 'P0001';
    END IF;
    IF v_cat <> 'Feed' THEN v_forage := FALSE; END IF;   -- only feed is collected
    IF lower(v_unit) = 'kg' THEN v_kg := 1; END IF;
    IF v_sp IS NOT NULL THEN PERFORM fnlivestock_requirespecies(p_farmid, v_sp); END IF;
    IF EXISTS (SELECT 1 FROM livestockitems WHERE farmid = p_farmid AND NOT isdeleted
               AND lower(btrim(name)) = lower(v_name) AND itemid IS DISTINCT FROM v_id) THEN
        RAISE EXCEPTION 'You already have an item called "%".', v_name USING ERRCODE = 'P0001';
    END IF;

    IF v_id IS NULL THEN
        -- The item only. Its stock comes in through a purchase (469), or for
        -- forage through Collect feed (494).
        INSERT INTO livestockitems (farmid, name, category, unit, kgperunit, minimumstock, speciescode, notes, isforage, createdby)
        VALUES (p_farmid, v_name, v_cat, v_unit, v_kg, v_min, v_sp, NULLIF(btrim(p_item->>'notes'), ''), v_forage, p_by)
        RETURNING itemid INTO v_id;
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
        isforage = CASE WHEN p_item ? 'isForage' OR v_cat <> 'Feed' THEN v_forage ELSE isforage END,
        updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE itemid = v_id;
    RETURN v_id;
END
$function$;

-- ---------------------------------------------------------------------------
-- Collect feed
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnlivestock_foragejson(p_id integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'collectionId', c.collectionid, 'itemId', c.itemid, 'itemName', i.name, 'unit', i.unit,
        'date', c.collectiondate, 'quantity', c.quantity,
        'kg', CASE WHEN i.kgperunit IS NOT NULL THEN round(c.quantity * i.kgperunit, 1) END,
        'place', c.place, 'collectedBy', c.collectedby, 'cost', c.cost,
        'costPerUnit', CASE WHEN c.cost > 0 THEN round(c.cost / c.quantity, 4) ELSE 0 END,
        'accountId', c.accountid, 'accountName', a.name, 'notes', c.notes,
        'createdBy', c.createdby, 'createdAt', c.createdat,
        'reversedAt', c.reversedat, 'reversedBy', c.reversedby, 'reverseReason', c.reversereason)
    FROM livestockforagecollections c
    JOIN livestockitems i ON i.itemid = c.itemid
    LEFT JOIN livestockcashaccounts a ON a.accountid = c.accountid
    WHERE c.collectionid = p_id;
$f$;

-- p_c: { itemId, date, quantity, place, collectedBy, cost, accountId, notes }
CREATE OR REPLACE FUNCTION public.splivestockforage_collect(p_farmid text, p_c jsonb, p_by text)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    v_item  livestockitems%ROWTYPE;
    v_date  date    := NULLIF(p_c->>'date', '')::date;
    v_qty   numeric := NULLIF(p_c->>'quantity', '')::numeric;
    v_cost  numeric := round(COALESCE(NULLIF(p_c->>'cost', '')::numeric, 0), 2);
    v_acct  integer := NULLIF(p_c->>'accountId', '')::int;
    v_id    integer;
BEGIN
    SELECT * INTO v_item FROM livestockitems
    WHERE itemid = NULLIF(p_c->>'itemId', '')::int AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Choose the feed that was collected.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT v_item.isforage OR v_item.category <> 'Feed' THEN
        RAISE EXCEPTION '% is bought, not collected. Mark it as collected feed (forage) on the item first, or use Record purchase.',
            v_item.name USING ERRCODE = 'P0001';
    END IF;
    IF NOT v_item.isactive THEN
        RAISE EXCEPTION '% is marked as not in use.', v_item.name USING ERRCODE = 'P0001';
    END IF;
    IF v_date IS NULL THEN
        RAISE EXCEPTION 'Enter the date it was collected.' USING ERRCODE = 'P0001';
    END IF;
    IF v_qty IS NULL OR v_qty <= 0 THEN
        RAISE EXCEPTION 'Enter how much % was brought back.', v_item.name USING ERRCODE = 'P0001';
    END IF;
    IF v_cost < 0 THEN
        RAISE EXCEPTION 'The cost of collecting cannot be negative.' USING ERRCODE = 'P0001';
    END IF;
    IF v_cost > 0 AND v_acct IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account the collecting cost was paid from.' USING ERRCODE = 'P0001';
    END IF;
    IF v_cost = 0 THEN v_acct := NULL; END IF;

    INSERT INTO livestockforagecollections (farmid, itemid, collectiondate, quantity, place, collectedby, cost, accountid, notes, createdby)
    VALUES (p_farmid, v_item.itemid, v_date, v_qty, NULLIF(btrim(p_c->>'place'), ''), NULLIF(btrim(p_c->>'collectedBy'), ''),
            v_cost, v_acct, NULLIF(btrim(p_c->>'notes'), ''), p_by)
    RETURNING collectionid INTO v_id;

    -- Into stock at what collecting it cost (0 when it cost nothing).
    PERFORM splivestockstock_post(p_farmid, v_item.itemid, v_date, 'Collected', v_qty, v_cost / v_qty, p_by,
        'Collected' || COALESCE(' at ' || NULLIF(btrim(p_c->>'place'), ''), ''), 'ForageCollection', v_id);

    IF v_cost > 0 THEN
        PERFORM splivestockcash_post(p_farmid, v_acct, v_date, -v_cost, 'Feed collection',
            'Collecting ' || v_item.name || ' · ' || trim_scale(v_qty) || ' ' || v_item.unit
                || COALESCE(' (' || NULLIF(btrim(p_c->>'place'), '') || ')', ''),
            p_by, 'ForageCollection', v_id);
    END IF;

    RETURN fnlivestock_foragejson(v_id);
END
$f$;

-- p_filter: { from, to, itemId, includeReversed }
CREATE OR REPLACE FUNCTION public.splivestockforage_list(p_farmid text, p_filter jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(fnlivestock_foragejson(c.collectionid) ORDER BY c.collectiondate DESC, c.collectionid DESC), '[]'::jsonb)
    FROM livestockforagecollections c
    WHERE c.farmid = p_farmid
      AND (COALESCE((p_filter->>'includeReversed')::boolean, TRUE) OR c.reversedat IS NULL)
      AND (NULLIF(p_filter->>'from', '') IS NULL OR c.collectiondate >= (p_filter->>'from')::date)
      AND (NULLIF(p_filter->>'to', '') IS NULL OR c.collectiondate <= (p_filter->>'to')::date)
      AND (NULLIF(p_filter->>'itemId', '') IS NULL OR c.itemid = (p_filter->>'itemId')::int);
$f$;

CREATE OR REPLACE FUNCTION public.splivestockforage_reverse(p_farmid text, p_id integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_c livestockforagecollections%ROWTYPE; v_name text;
BEGIN
    SELECT * INTO v_c FROM livestockforagecollections WHERE collectionid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND OR v_c.reversedat IS NOT NULL THEN
        RAISE EXCEPTION 'That collection was not found or is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    SELECT name INTO v_name FROM livestockitems WHERE itemid = v_c.itemid FOR UPDATE;
    -- Refused once any of the item has gone out since this came in: stock is
    -- valued at the average, so taking this lot back out at its own cost
    -- after some was fed would leave the item with a wrong (even negative) value.
    IF fnlivestock_itemstock(v_c.itemid) < v_c.quantity
       OR EXISTS (SELECT 1 FROM livestockstockmovements m
                  WHERE m.itemid = v_c.itemid AND m.reversedat IS NULL AND m.quantity < 0
                    AND m.movementid > (SELECT s.movementid FROM livestockstockmovements s
                                        WHERE s.sourcetype = 'ForageCollection' AND s.sourceid = p_id
                                        ORDER BY s.movementid LIMIT 1)) THEN
        RAISE EXCEPTION 'Some of this % has already been fed or written off, so it cannot be reversed. Correct the count instead.',
            v_name USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockforagecollections SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
    WHERE collectionid = p_id;
    UPDATE livestockstockmovements SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
    WHERE sourcetype = 'ForageCollection' AND sourceid = p_id AND reversedat IS NULL;
    PERFORM fnlivestock_reversecash('ForageCollection', p_id, p_by, btrim(p_reason));
END
$f$;

-- ---------------------------------------------------------------------------
-- Daily record: grazing
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnlivestock_recordjson(p_recordid integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    SELECT jsonb_build_object(
        'recordId', r.recordid, 'groupId', r.groupid, 'groupName', g.name, 'speciesCode', g.speciescode,
        'speciesName', s.name, 'date', r.recorddate, 'deaths', r.deaths, 'deathCause', r.deathcause, 'culls', r.culls,
        'eggsCollected', r.eggscollected, 'eggsBroken', r.eggsbroken, 'milkLitres', r.milklitres,
        'waterLitres', r.waterlitres, 'notes', r.notes,
        'grazed', r.grazed, 'grazingHours', r.grazinghours, 'grazingPlace', r.grazingplace,
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
$function$;

-- The live body; grazed / grazingHours / grazingPlace read and stored.
CREATE OR REPLACE FUNCTION public.splivestockproduction_save(p_farmid text, p_record jsonb, p_by text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
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
    v_grazed  boolean := COALESCE(NULLIF(p_record->>'grazed', '')::boolean, FALSE);
    v_ghours  numeric := NULLIF(p_record->>'grazingHours', '')::numeric;
    v_gplace  text    := NULLIF(btrim(COALESCE(p_record->>'grazingPlace', '')), '');
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
    -- 494: grazing. Hours and place only mean something when they went out.
    IF NOT v_grazed THEN
        v_ghours := NULL; v_gplace := NULL;
    ELSIF v_ghours IS NOT NULL AND (v_ghours <= 0 OR v_ghours > 24) THEN
        RAISE EXCEPTION 'Grazing hours must be between 0 and 24.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM livestockproductionrecords WHERE groupid = v_groupid AND recorddate = v_date
               AND NOT isdeleted AND recordid IS DISTINCT FROM v_id) THEN
        RAISE EXCEPTION '% already has a record for %. Open it and change that one.', v_g.name,
            to_char(v_date, 'DD Mon YYYY') USING ERRCODE = 'P0010';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO livestockproductionrecords (farmid, groupid, recorddate, deaths, deathcause, culls, eggscollected,
                                                eggsbroken, milklitres, waterlitres, notes, grazed, grazinghours, grazingplace, createdby)
        VALUES (p_farmid, v_groupid, v_date, v_deaths, NULLIF(btrim(p_record->>'deathCause'), ''), v_culls, v_eggs,
                v_broken, v_milk, v_water, NULLIF(btrim(p_record->>'notes'), ''), v_grazed, v_ghours, v_gplace, p_by)
        RETURNING recordid INTO v_id;
    ELSE
        PERFORM fnlivestock_reversesource('ProductionRecord', v_id, p_by, 'Record edited');
        UPDATE livestockproductionlines SET isreversed = TRUE WHERE recordid = v_id AND NOT isreversed;
        UPDATE livestockproductionrecords SET recorddate = v_date, deaths = v_deaths,
            deathcause = NULLIF(btrim(p_record->>'deathCause'), ''), culls = v_culls, eggscollected = v_eggs,
            eggsbroken = v_broken, milklitres = v_milk, waterlitres = v_water, notes = NULLIF(btrim(p_record->>'notes'), ''),
            grazed = v_grazed, grazinghours = v_ghours, grazingplace = v_gplace,
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
$function$;

-- ---------------------------------------------------------------------------
-- Expenses list (471): paid collections are "Bought" rows. The live body with
-- branch 10 added.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.splivestockexpense_list(p_farmid text, p_filter jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH prm AS (
        SELECT NULLIF(p_filter->>'from', '')::date AS dfrom,
               NULLIF(p_filter->>'to', '')::date   AS dto
    ),
    pur AS (   -- purchases with what has been paid on them
        SELECT p.*, fnlivestock_purchasepaid(p.purchaseid) AS paid, s.name AS suppliername
        FROM livestockpurchases p LEFT JOIN supplier s ON s.supplierid = p.supplierid
        WHERE p.farmid = p_farmid
    ),
    x AS (
        -- 1. Typed-in expenses, paid from a cash account.
        SELECT 'Paid' AS source, 'Spent' AS costkind, e.expenseid AS id, e.expenseid AS sourceid, e.expensedate AS d,
               e.category, e.description, e.amount, e.groupid, a.name AS accountname, e.paidto AS payee, e.reference,
               NULL::int AS purchaseid, NULL::numeric AS paid, NULL::numeric AS owed, 'Paid' AS paystatus,
               e.createdby, e.reversedat, e.reversereason
        FROM livestockexpenses e JOIN livestockcashaccounts a ON a.accountid = e.accountid
        WHERE e.farmid = p_farmid

        UNION ALL
        -- 2. Purchase lines: stock, animals and bills. Paid / owed is the
        --    purchase's, shared out over its lines by value.
        SELECT CASE l.linetype WHEN 'Expense' THEN 'Bill' ELSE 'Purchase' END,
               CASE l.linetype WHEN 'Expense' THEN 'Spent' ELSE 'Bought' END,
               l.lineid, p.purchaseid, p.purchasedate,
               CASE l.linetype WHEN 'Item' THEN i.category WHEN 'Animals' THEN 'Animals' ELSE l.expensecategory END,
               CASE l.linetype
                    WHEN 'Item' THEN i.name || ' · ' || trim(to_char(l.quantity, 'FM999999990.###')) || COALESCE(' ' || i.unit, '')
                    WHEN 'Animals' THEN COALESCE(sp.name, 'Animals') || ' · ' || trim(to_char(l.quantity, 'FM999999990')) || ' head'
                         || COALESCE(' (' || b.batchcode || ')', '')
                    ELSE l.description END,
               l.linetotal,
               CASE l.linetype WHEN 'Expense' THEN l.groupid END,
               NULL, p.suppliername, p.reference, p.purchaseid,
               round(CASE WHEN p.total > 0 THEN p.paid * l.linetotal / p.total ELSE 0 END, 2),
               CASE WHEN p.reversedat IS NULL THEN round(CASE WHEN p.total > 0 THEN (p.total - p.paid) * l.linetotal / p.total ELSE 0 END, 2) ELSE 0 END,
               CASE WHEN p.reversedat IS NOT NULL THEN 'Reversed' WHEN p.paid >= p.total THEN 'Paid'
                    WHEN p.paid > 0 THEN 'PartPaid' ELSE 'Unpaid' END,
               p.createdby, p.reversedat, p.reversereason
        FROM livestockpurchaselines l JOIN pur p ON p.purchaseid = l.purchaseid
        LEFT JOIN livestockitems i ON i.itemid = l.itemid
        LEFT JOIN livestockbatches b ON b.batchid = l.batchid
        LEFT JOIN livestockspecies sp ON sp.speciescode = b.speciescode

        UNION ALL
        -- 3. Animals bought and entered on the batch itself, not through a
        --    purchase (no payment recorded for them).
        SELECT 'Batch', 'Bought', b.batchid, b.batchid, b.intakedate, 'Animals',
               COALESCE(sp.name, 'Animals') || ' · ' || b.quantity || ' head (' || b.batchcode || ')',
               COALESCE(b.totalcost, b.costperhead * b.quantity), NULL, NULL, s.name, b.batchcode, NULL,
               NULL, NULL, 'NotRecorded', b.createdby, NULL::timestamp, NULL
        FROM livestockbatches b LEFT JOIN livestockspecies sp ON sp.speciescode = b.speciescode
        LEFT JOIN supplier s ON s.supplierid = b.supplierid
        WHERE b.farmid = p_farmid AND b.purchaseid IS NULL AND NOT COALESCE(b.isdeleted, FALSE)
          AND COALESCE(b.totalcost, b.costperhead * b.quantity, 0) > 0

        UNION ALL
        -- 4. Tagged animals bought one by one (a price, no batch).
        SELECT 'Animal', 'Bought', a.animalid, a.animalid, COALESCE(a.acquireddate, a.createdat::date), 'Animals',
               COALESCE(sp.name, 'Animal') || ' · ' || COALESCE(a.tagnumber, a.name, '#' || a.animalid),
               a.purchasecost, a.groupid, NULL, NULL, NULL, NULL,
               NULL, NULL, 'NotRecorded', a.createdby, NULL::timestamp, NULL
        FROM livestockanimals a LEFT JOIN livestockspecies sp ON sp.speciescode = a.speciescode
        WHERE a.farmid = p_farmid AND NOT a.isdeleted AND COALESCE(a.purchasecost, 0) > 0
          AND EXISTS (SELECT 1 FROM livestockheadmovements m WHERE m.animalid = a.animalid AND m.movementtype = 'Intake'
                      AND m.reversedat IS NULL AND m.batchid IS NULL)

        UNION ALL
        -- 5. Stock used on daily records, treatments and health records: one
        --    row per record and kind of stock. Already bought -- not a new bill.
        SELECT 'StockUsed', 'Used', min(m.movementid), m.sourceid, m.movementdate, i.category,
               CASE m.sourcetype WHEN 'ProductionRecord' THEN 'Daily record' WHEN 'TreatmentDay' THEN 'Treatment'
                    ELSE 'Health record' END || ': ' || string_agg(DISTINCT i.name, ', '),
               -SUM(m.totalcost), m.groupid, NULL, NULL, m.sourcetype, NULL,
               NULL, NULL, NULL, min(m.createdby), NULL::timestamp, NULL
        FROM livestockstockmovements m JOIN livestockitems i ON i.itemid = m.itemid
        WHERE m.farmid = p_farmid AND m.reversedat IS NULL AND m.movementtype = 'Usage'
          AND m.sourcetype IN ('ProductionRecord', 'TreatmentDay', 'HealthRecord')
        GROUP BY m.sourcetype, m.sourceid, m.movementdate, m.groupid, i.category
        HAVING -SUM(m.totalcost) > 0

        UNION ALL
        -- 6. Stock lost (spoiled, expired, stolen ...).
        SELECT 'StockLost', 'Used', m.movementid, m.movementid, m.movementdate, i.category,
               i.name || ' lost' || COALESCE(' (' || m.lossreason || ')', '') || COALESCE(': ' || m.notes, ''),
               -m.totalcost, m.groupid, NULL, NULL, NULL, NULL,
               NULL, NULL, NULL, m.createdby, NULL::timestamp, NULL
        FROM livestockstockmovements m JOIN livestockitems i ON i.itemid = m.itemid
        WHERE m.farmid = p_farmid AND m.reversedat IS NULL AND m.movementtype = 'Loss' AND m.totalcost < 0

        UNION ALL
        -- 7. Pay runs: gross pay of everyone on the run.
        SELECT 'PayRun', 'Spent', r.runid, r.runid, r.paydate, 'Staff pay',
               'Pay run ' || to_char(r.periodstart, 'DD Mon') || ' – ' || to_char(r.periodend, 'DD Mon YYYY')
                   || ' · ' || count(l.lineid) || ' staff',
               SUM(l.gross), NULL, a.name, NULL, NULL, NULL,
               NULL, NULL, 'Paid', r.createdby, r.reversedat, r.reversereason
        FROM livestockpayruns r JOIN livestockpaylines l ON l.runid = r.runid
        JOIN livestockcashaccounts a ON a.accountid = r.accountid
        WHERE r.farmid = p_farmid
        GROUP BY r.runid, a.name
        HAVING SUM(l.gross) > 0

        UNION ALL
        -- 8. Loan interest (the principal is paying back, not a cost).
        SELECT 'LoanInterest', 'Spent', r.repaymentid, lo.loanid, r.repaydate, 'Loan interest',
               'Interest to ' || lo.lender, r.interest, NULL, a.name, lo.lender, NULL, NULL,
               NULL, NULL, 'Paid', r.createdby, r.reversedat, r.reversereason
        FROM livestockloanrepayments r JOIN livestockloans lo ON lo.loanid = r.loanid
        JOIN livestockcashaccounts a ON a.accountid = r.accountid
        WHERE lo.farmid = p_farmid AND r.interest > 0

        UNION ALL
        -- 9. Depreciation, one row per asset per month (to the chosen end date,
        --    never past today). No money moves.
        SELECT 'Depreciation', 'NonCash', ast.assetid, ast.assetid, mo.mend, 'Depreciation',
               ast.name || ' · ' || to_char(mo.mstart, 'Mon YYYY'),
               fnlivestock_depreciation(ast.assetid, mo.mstart, mo.mend), NULL, NULL, NULL, NULL, NULL,
               NULL, NULL, NULL, ast.createdby, NULL::timestamp, NULL
        FROM livestockassets ast CROSS JOIN prm
        CROSS JOIN LATERAL (
            SELECT GREATEST(gs::date, ast.acquireddate, COALESCE(prm.dfrom, ast.acquireddate)) AS mstart,
                   LEAST((gs + interval '1 month - 1 day')::date, COALESCE(prm.dto, current_date), current_date) AS mend
            FROM generate_series(date_trunc('month', GREATEST(ast.acquireddate, COALESCE(prm.dfrom, ast.acquireddate))),
                                 date_trunc('month', LEAST(COALESCE(prm.dto, current_date), current_date)),
                                 interval '1 month') gs
        ) mo
        WHERE ast.farmid = p_farmid AND ast.reversedat IS NULL AND ast.usefulmonths IS NOT NULL AND mo.mend >= mo.mstart

        UNION ALL
        -- 10. (494) Feed collected from the forest with a collecting cost, paid
        --     from a cash account. The forage went into stock at that cost.
        SELECT 'ForageCollection', 'Bought', c.collectionid, c.collectionid, c.collectiondate, 'Feed',
               'Collected ' || i.name || ' · ' || trim(to_char(c.quantity, 'FM999999990.###')) || COALESCE(' ' || i.unit, '')
                   || COALESCE(' (' || c.place || ')', ''),
               c.cost, NULL, a.name, c.collectedby, NULL, NULL,
               NULL, NULL, CASE WHEN c.reversedat IS NOT NULL THEN 'Reversed' ELSE 'Paid' END,
               c.createdby, c.reversedat, c.reversereason
        FROM livestockforagecollections c JOIN livestockitems i ON i.itemid = c.itemid
        LEFT JOIN livestockcashaccounts a ON a.accountid = c.accountid
        WHERE c.farmid = p_farmid AND c.cost > 0
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'source', x.source, 'costKind', x.costkind, 'id', x.id, 'sourceId', x.sourceid, 'date', x.d,
        'category', x.category, 'description', x.description, 'amount', x.amount,
        'groupId', x.groupid, 'groupName', g.name, 'accountName', x.accountname, 'payee', x.payee, 'reference', x.reference,
        'purchaseId', x.purchaseid, 'paid', x.paid, 'owed', x.owed, 'payStatus', x.paystatus,
        'createdBy', x.createdby, 'reversedAt', x.reversedat, 'reverseReason', x.reversereason)
        ORDER BY x.d DESC, x.source, x.id DESC), '[]'::jsonb)
    FROM x CROSS JOIN prm LEFT JOIN livestockgroups g ON g.groupid = x.groupid
    WHERE x.amount > 0
      AND (prm.dfrom IS NULL OR x.d >= prm.dfrom)
      AND (prm.dto IS NULL OR x.d <= prm.dto)
      AND (NULLIF(p_filter->>'category', '') IS NULL OR x.category = p_filter->>'category')
      AND (NULLIF(p_filter->>'costKind', '') IS NULL OR x.costkind = p_filter->>'costKind')
      AND (NULLIF(p_filter->>'groupId', '') IS NULL OR x.groupid = (p_filter->>'groupId')::int);
$function$;

COMMIT;

-- 464: Livestock daily closing, missing records, delivery.
--
-- Needs 458-463.
--
-- 1. Daily closing (poultry 333 for livestock). A day is closed after its
--    summary has been checked: groups, deaths, produce, feed, sales and money
--    per account. Problems found (a group with no daily record, an account
--    below zero, a delivery still out) must be acknowledged with a note to
--    close anyway. A closed day can be reopened, with a reason.
--
--    The LOCK is a trigger on the three ledgers every change goes through --
--    head (livestockheadmovements), stock (livestockstockmovements) and cash
--    (livestockcashtransactions). Nothing dated on a closed day can be added
--    or reversed until the day is reopened. One rule in one place, so no
--    function can forget it.
--
-- 2. Missing records (poultry 332): days each active group has no daily record.
--
-- 3. Delivery: drivers, vehicles (registration unique per farm, the 397 rule),
--    routes; a delivery takes sales out with a driver, and the driver's return
--    hands in what was collected -- each amount is a customer payment against
--    its sale. The driver report shows what each driver collected and what is
--    still with them.
--
-- 4. IAM: daily-closing, drivers, vehicles, routes, deliveries, driver-returns.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Daily closing
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockdailyclosings (
    closingid     serial PRIMARY KEY,
    farmid        text NOT NULL,
    closedate     date NOT NULL,
    status        text NOT NULL DEFAULT 'Closed' CHECK (status IN ('Closed', 'Reopened')),
    summary       jsonb NOT NULL,          -- the day as it was when closed
    acknowledged  jsonb,                   -- the problems closed over, if any
    notes         text,
    closedat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    closedby      text,
    reopenedat    timestamp,
    reopenedby    text,
    reopenreason  text
);
CREATE UNIQUE INDEX IF NOT EXISTS uxlivestockdailyclosings_day ON livestockdailyclosings (farmid, closedate) WHERE status = 'Closed';

CREATE OR REPLACE FUNCTION public.fnlivestock_dayisclosed(p_farmid text, p_date date)
 RETURNS boolean LANGUAGE sql STABLE AS $f$
    SELECT EXISTS (SELECT 1 FROM livestockdailyclosings WHERE farmid = p_farmid AND closedate = p_date AND status = 'Closed');
$f$;

-- The lock.
CREATE OR REPLACE FUNCTION public.trglivestock_closedday()
 RETURNS trigger LANGUAGE plpgsql AS $f$
DECLARE v_date date;
BEGIN
    -- The date column is the trigger's argument (txdate on cash, movementdate
    -- on the ledgers, recorddate on records). An edit is checked against the
    -- day it came from as well as the day it goes to.
    v_date := (to_jsonb(NEW) ->> TG_ARGV[0])::date;
    IF fnlivestock_dayisclosed(NEW.farmid, v_date) THEN
        RAISE EXCEPTION '% is closed. Reopen the day to change it.', to_char(v_date, 'DD Mon YYYY') USING ERRCODE = 'LV006';
    END IF;
    IF TG_OP = 'UPDATE' THEN
        v_date := (to_jsonb(OLD) ->> TG_ARGV[0])::date;
        IF fnlivestock_dayisclosed(OLD.farmid, v_date) THEN
            RAISE EXCEPTION '% is closed. Reopen the day to change it.', to_char(v_date, 'DD Mon YYYY') USING ERRCODE = 'LV006';
        END IF;
    END IF;
    RETURN NEW;
END
$f$;

DROP TRIGGER IF EXISTS trglivestockheadmovements_closedday ON livestockheadmovements;
CREATE TRIGGER trglivestockheadmovements_closedday BEFORE INSERT OR UPDATE ON livestockheadmovements
    FOR EACH ROW EXECUTE FUNCTION trglivestock_closedday('movementdate');
DROP TRIGGER IF EXISTS trglivestockstockmovements_closedday ON livestockstockmovements;
CREATE TRIGGER trglivestockstockmovements_closedday BEFORE INSERT OR UPDATE ON livestockstockmovements
    FOR EACH ROW EXECUTE FUNCTION trglivestock_closedday('movementdate');
DROP TRIGGER IF EXISTS trglivestockcashtransactions_closedday ON livestockcashtransactions;
CREATE TRIGGER trglivestockcashtransactions_closedday BEFORE INSERT OR UPDATE ON livestockcashtransactions
    FOR EACH ROW EXECUTE FUNCTION trglivestock_closedday('txdate');
-- Daily records and health records are part of the day too, even when they
-- move no animals, stock or money.
DROP TRIGGER IF EXISTS trglivestockproductionrecords_closedday ON livestockproductionrecords;
CREATE TRIGGER trglivestockproductionrecords_closedday BEFORE INSERT OR UPDATE ON livestockproductionrecords
    FOR EACH ROW EXECUTE FUNCTION trglivestock_closedday('recorddate');
DROP TRIGGER IF EXISTS trglivestockhealthrecords_closedday ON livestockhealthrecords;
CREATE TRIGGER trglivestockhealthrecords_closedday BEFORE INSERT OR UPDATE ON livestockhealthrecords
    FOR EACH ROW EXECUTE FUNCTION trglivestock_closedday('recorddate');

-- ---------------------------------------------------------------------------
-- 2. Missing records
-- ---------------------------------------------------------------------------
-- Days in [from, to] each active group (with animals) has no daily record.
CREATE OR REPLACE FUNCTION public.splivestock_missingdays(p_farmid text, p_from date, p_to date)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.cnt DESC, x.name), '[]'::jsonb) FROM (
        SELECT g.name, count(*) AS cnt, jsonb_build_object('groupId', g.groupid, 'name', g.name, 'speciesName', s.name,
                   'missing', count(*), 'days', jsonb_agg(d.day ORDER BY d.day DESC),
                   'lastRecord', (SELECT max(recorddate) FROM livestockproductionrecords r WHERE r.groupid = g.groupid AND NOT r.isdeleted)) AS j
        FROM livestockgroups g
        JOIN livestockspecies s ON s.speciescode = g.speciescode
        CROSS JOIN LATERAL generate_series(GREATEST(p_from, g.startdate), LEAST(p_to, COALESCE(g.closeddate, p_to)), interval '1 day') AS d(day)
        WHERE g.farmid = p_farmid AND NOT g.isdeleted
          AND fnlivestock_groupheadasof(g.groupid, d.day::date) > 0
          AND NOT EXISTS (SELECT 1 FROM livestockproductionrecords r WHERE r.groupid = g.groupid AND r.recorddate = d.day::date AND NOT r.isdeleted)
        GROUP BY g.groupid, g.name, s.name
    ) x;
$f$;

-- ---------------------------------------------------------------------------
-- 3. Delivery (tables first: the day summary looks at deliveries still out)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockdrivers (
    driverid  serial PRIMARY KEY,
    farmid    text NOT NULL,
    name      text NOT NULL,
    phone     text,
    licence   text,
    isactive  boolean NOT NULL DEFAULT TRUE,
    notes     text,
    createdat timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby text
);
CREATE TABLE IF NOT EXISTS livestockvehicles (
    vehicleid    serial PRIMARY KEY,
    farmid       text NOT NULL,
    registration text NOT NULL,
    description  text,                  -- "Kia truck", "motorbike"
    capacity     text,
    isactive     boolean NOT NULL DEFAULT TRUE,
    notes        text,
    createdat    timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby    text
);
CREATE UNIQUE INDEX IF NOT EXISTS uxlivestockvehicles_reg
    ON livestockvehicles (farmid, upper(regexp_replace(registration, '[^A-Za-z0-9]', '', 'g')));
CREATE TABLE IF NOT EXISTS livestockroutes (
    routeid     serial PRIMARY KEY,
    farmid      text NOT NULL,
    name        text NOT NULL,
    description text,
    isactive    boolean NOT NULL DEFAULT TRUE,
    createdat   timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby   text
);
CREATE TABLE IF NOT EXISTS livestockdeliveries (
    deliveryid    serial PRIMARY KEY,
    farmid        text NOT NULL,
    deliverydate  date NOT NULL,
    driverid      integer NOT NULL REFERENCES livestockdrivers(driverid),
    vehicleid     integer REFERENCES livestockvehicles(vehicleid),
    routeid       integer REFERENCES livestockroutes(routeid),
    status        text NOT NULL DEFAULT 'Out' CHECK (status IN ('Out', 'Returned', 'Cancelled')),
    expected      numeric(14,2) NOT NULL DEFAULT 0,   -- owed on its sales when it went out
    collected     numeric(14,2),
    returnaccountid integer REFERENCES livestockcashaccounts(accountid),
    notes         text,
    returnnotes   text,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    returnedat    timestamp,
    returnedby    text
);
CREATE TABLE IF NOT EXISTS livestockdeliverysales (
    deliveryid integer NOT NULL REFERENCES livestockdeliveries(deliveryid),
    saleid     integer NOT NULL REFERENCES livestocksales(saleid),
    paymentid  integer REFERENCES livestockcustomerpayments(paymentid),   -- what the driver collected on it
    collected  numeric(14,2),
    PRIMARY KEY (deliveryid, saleid)
);

-- ---------------------------------------------------------------------------
-- 1b. The day's summary, the problems on it, closing and reopening
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.splivestockday_summary(p_farmid text, p_date date)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE v_groups jsonb; v_money jsonb; v_problems jsonb := '[]'::jsonb; v_c livestockdailyclosings%ROWTYPE; r record;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'groupId', g.groupid, 'name', g.name, 'speciesName', s.name, 'producesEggs', s.produceseggs, 'producesMilk', s.producesmilk,
            'headStart', fnlivestock_groupheadasof(g.groupid, p_date - 1), 'headEnd', fnlivestock_groupheadasof(g.groupid, p_date),
            'deaths', COALESCE((SELECT -SUM(quantity) FROM livestockheadmovements m WHERE m.groupid = g.groupid AND m.reversedat IS NULL AND m.movementdate = p_date AND m.movementtype = 'Death'), 0),
            'culls', COALESCE((SELECT -SUM(quantity) FROM livestockheadmovements m WHERE m.groupid = g.groupid AND m.reversedat IS NULL AND m.movementdate = p_date AND m.movementtype = 'Cull'), 0),
            'sold', COALESCE((SELECT -SUM(quantity) FROM livestockheadmovements m WHERE m.groupid = g.groupid AND m.reversedat IS NULL AND m.movementdate = p_date AND m.movementtype = 'Sale'), 0),
            'born', COALESCE((SELECT SUM(quantity) FROM livestockheadmovements m WHERE m.groupid = g.groupid AND m.reversedat IS NULL AND m.movementdate = p_date AND m.movementtype = 'Birth'), 0),
            'recordId', pr.recordid, 'eggs', pr.eggscollected, 'milk', pr.milklitres,
            'feedCost', (SELECT COALESCE(-SUM(totalcost), 0) FROM livestockstockmovements sm JOIN livestockitems i ON i.itemid = sm.itemid
                         WHERE sm.groupid = g.groupid AND sm.reversedat IS NULL AND sm.movementdate = p_date AND sm.movementtype = 'Usage' AND i.category = 'Feed'))
            ORDER BY s.sortorder, lower(g.name)), '[]'::jsonb)
    INTO v_groups
    FROM livestockgroups g JOIN livestockspecies s ON s.speciescode = g.speciescode
    LEFT JOIN livestockproductionrecords pr ON pr.groupid = g.groupid AND pr.recorddate = p_date AND NOT pr.isdeleted
    WHERE g.farmid = p_farmid AND NOT g.isdeleted AND g.startdate <= p_date AND (g.closeddate IS NULL OR g.closeddate >= p_date)
      AND (fnlivestock_groupheadasof(g.groupid, p_date - 1) > 0 OR fnlivestock_groupheadasof(g.groupid, p_date) > 0);

    SELECT COALESCE(jsonb_agg(jsonb_build_object('accountId', a.accountid, 'name', a.name,
            'opening', CASE WHEN a.openingdate >= p_date THEN a.openingbalance ELSE fnlivestock_cashbalanceasof(a.accountid, p_date - 1) END,
            'moneyIn', COALESCE((SELECT SUM(amount) FROM livestockcashtransactions t WHERE t.accountid = a.accountid AND t.reversedat IS NULL AND t.txdate = p_date AND t.amount > 0), 0),
            'moneyOut', COALESCE((SELECT -SUM(amount) FROM livestockcashtransactions t WHERE t.accountid = a.accountid AND t.reversedat IS NULL AND t.txdate = p_date AND t.amount < 0), 0),
            'closing', fnlivestock_cashbalanceasof(a.accountid, p_date)) ORDER BY a.name), '[]'::jsonb)
    INTO v_money
    FROM livestockcashaccounts a WHERE a.farmid = p_farmid AND a.isactive AND a.openingdate <= p_date;

    -- Problems to deal with (or acknowledge) before closing.
    FOR r IN SELECT e->>'name' AS name FROM jsonb_array_elements(v_groups) e WHERE e->>'recordId' IS NULL LOOP
        v_problems := v_problems || jsonb_build_object('kind', 'MissingRecord', 'message', r.name || ' has no daily record for the day.');
    END LOOP;
    FOR r IN SELECT e->>'name' AS name, (e->>'closing')::numeric AS bal FROM jsonb_array_elements(v_money) e WHERE (e->>'closing')::numeric < 0 LOOP
        v_problems := v_problems || jsonb_build_object('kind', 'NegativeCash', 'message', r.name || ' is below zero (' || to_char(r.bal, 'FM999,999,990.00') || ').');
    END LOOP;
    FOR r IN SELECT d.deliveryid, dr.name FROM livestockdeliveries d JOIN livestockdrivers dr ON dr.driverid = d.driverid
             WHERE d.farmid = p_farmid AND d.status = 'Out' AND d.deliverydate <= p_date LOOP
        v_problems := v_problems || jsonb_build_object('kind', 'DeliveryOut', 'message', r.name || '''s delivery ' || r.deliveryid || ' has not been returned.');
    END LOOP;

    SELECT * INTO v_c FROM livestockdailyclosings WHERE farmid = p_farmid AND closedate = p_date ORDER BY closingid DESC LIMIT 1;

    RETURN jsonb_build_object(
        'date', p_date,
        'isClosed', v_c.status = 'Closed',
        'closing', CASE WHEN v_c.closingid IS NULL THEN NULL ELSE jsonb_build_object('status', v_c.status, 'closedBy', v_c.closedby,
                       'closedAt', v_c.closedat, 'notes', v_c.notes, 'acknowledged', v_c.acknowledged, 'reopenedBy', v_c.reopenedby,
                       'reopenedAt', v_c.reopenedat, 'reopenReason', v_c.reopenreason) END,
        'groups', v_groups,
        'totals', jsonb_build_object(
            'head', (SELECT COALESCE(SUM((e->>'headEnd')::int), 0) FROM jsonb_array_elements(v_groups) e),
            'deaths', (SELECT COALESCE(SUM((e->>'deaths')::int), 0) FROM jsonb_array_elements(v_groups) e),
            'eggs', (SELECT SUM((e->>'eggs')::int) FROM jsonb_array_elements(v_groups) e),
            'milk', (SELECT SUM((e->>'milk')::numeric) FROM jsonb_array_elements(v_groups) e),
            'feedCost', (SELECT COALESCE(SUM((e->>'feedCost')::numeric), 0) FROM jsonb_array_elements(v_groups) e),
            'sales', (SELECT COALESCE(SUM(total), 0) FROM livestocksales WHERE farmid = p_farmid AND saledate = p_date AND reversedat IS NULL),
            'salesCount', (SELECT count(*) FROM livestocksales WHERE farmid = p_farmid AND saledate = p_date AND reversedat IS NULL),
            'expenses', (SELECT COALESCE(SUM(amount), 0) FROM livestockexpenses WHERE farmid = p_farmid AND expensedate = p_date AND reversedat IS NULL),
            'moneyIn', (SELECT COALESCE(SUM((e->>'moneyIn')::numeric), 0) FROM jsonb_array_elements(v_money) e),
            'moneyOut', (SELECT COALESCE(SUM((e->>'moneyOut')::numeric), 0) FROM jsonb_array_elements(v_money) e)),
        'money', v_money,
        'problems', v_problems);
END
$f$;

-- Close a day. With problems on it, p_acknowledge must be true and a note given.
CREATE OR REPLACE FUNCTION public.splivestockday_close(p_farmid text, p_date date, p_acknowledge boolean, p_notes text, p_by text)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_s jsonb;
BEGIN
    IF p_date IS NULL OR p_date > (now() at time zone 'utc')::date THEN
        RAISE EXCEPTION 'A day can be closed once it has happened.' USING ERRCODE = 'P0001';
    END IF;
    IF fnlivestock_dayisclosed(p_farmid, p_date) THEN
        RAISE EXCEPTION '% is already closed.', to_char(p_date, 'DD Mon YYYY') USING ERRCODE = 'P0001';
    END IF;
    v_s := splivestockday_summary(p_farmid, p_date);
    IF jsonb_array_length(v_s->'problems') > 0 AND NOT COALESCE(p_acknowledge, FALSE) THEN
        RAISE EXCEPTION 'The day has % problem(s): %', jsonb_array_length(v_s->'problems'),
            (SELECT string_agg(e->>'message', ' ') FROM jsonb_array_elements(v_s->'problems') e) USING ERRCODE = 'LV007';
    END IF;
    IF jsonb_array_length(v_s->'problems') > 0 AND NULLIF(btrim(p_notes), '') IS NULL THEN
        RAISE EXCEPTION 'Say why the day is being closed with these problems.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO livestockdailyclosings (farmid, closedate, summary, acknowledged, notes, closedby)
    VALUES (p_farmid, p_date, v_s - 'closing' - 'isClosed', CASE WHEN jsonb_array_length(v_s->'problems') > 0 THEN v_s->'problems' END,
            NULLIF(btrim(p_notes), ''), p_by);
    RETURN splivestockday_summary(p_farmid, p_date);
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockday_reopen(p_farmid text, p_date date, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why the day is being reopened.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockdailyclosings SET status = 'Reopened', reopenedat = (now() at time zone 'utc'), reopenedby = p_by, reopenreason = btrim(p_reason)
    WHERE farmid = p_farmid AND closedate = p_date AND status = 'Closed';
    IF NOT FOUND THEN
        RAISE EXCEPTION '% is not closed.', to_char(p_date, 'DD Mon YYYY') USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- The last 60 days: which are closed, open, or reopened.
CREATE OR REPLACE FUNCTION public.splivestockday_list(p_farmid text, p_days integer DEFAULT 60)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('date', d.day::date,
            'status', COALESCE((SELECT c.status FROM livestockdailyclosings c WHERE c.farmid = p_farmid AND c.closedate = d.day::date
                                ORDER BY c.closingid DESC LIMIT 1), 'Open'),
            'closedBy', (SELECT c.closedby FROM livestockdailyclosings c WHERE c.farmid = p_farmid AND c.closedate = d.day::date AND c.status = 'Closed'),
            'hadProblems', EXISTS (SELECT 1 FROM livestockdailyclosings c WHERE c.farmid = p_farmid AND c.closedate = d.day::date
                                   AND c.status = 'Closed' AND c.acknowledged IS NOT NULL))
           ORDER BY d.day DESC), '[]'::jsonb)
    FROM generate_series((now() at time zone 'utc')::date - (p_days - 1), (now() at time zone 'utc')::date, interval '1 day') d(day);
$f$;

-- ---------------------------------------------------------------------------
-- 3b. Delivery functions
-- ---------------------------------------------------------------------------
-- p_kind: Driver | Vehicle | Route.
CREATE OR REPLACE FUNCTION public.splivestockfleet_list(p_farmid text, p_kind text, p_includeinactive boolean DEFAULT FALSE)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
BEGIN
    IF p_kind = 'Driver' THEN
        RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', driverid, 'name', name, 'phone', phone, 'licence', licence,
                'isActive', isactive, 'notes', notes) ORDER BY isactive DESC, lower(name)), '[]'::jsonb)
                FROM livestockdrivers WHERE farmid = p_farmid AND (p_includeinactive OR isactive));
    ELSIF p_kind = 'Vehicle' THEN
        RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', vehicleid, 'name', registration, 'registration', registration,
                'description', description, 'capacity', capacity, 'isActive', isactive, 'notes', notes) ORDER BY isactive DESC, registration), '[]'::jsonb)
                FROM livestockvehicles WHERE farmid = p_farmid AND (p_includeinactive OR isactive));
    ELSIF p_kind = 'Route' THEN
        RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', routeid, 'name', name, 'description', description,
                'isActive', isactive) ORDER BY isactive DESC, lower(name)), '[]'::jsonb)
                FROM livestockroutes WHERE farmid = p_farmid AND (p_includeinactive OR isactive));
    END IF;
    RAISE EXCEPTION 'Unknown kind.' USING ERRCODE = 'P0001';
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockfleet_save(p_farmid text, p_kind text, p_x jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_id integer := NULLIF(p_x->>'id', '')::int; v_name text := btrim(COALESCE(p_x->>'name', p_x->>'registration', ''));
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Enter the %.', CASE p_kind WHEN 'Vehicle' THEN 'registration number' ELSE 'name' END USING ERRCODE = 'P0001';
    END IF;
    IF p_kind = 'Driver' THEN
        IF v_id IS NULL THEN
            INSERT INTO livestockdrivers (farmid, name, phone, licence, notes, createdby)
            VALUES (p_farmid, v_name, NULLIF(btrim(p_x->>'phone'), ''), NULLIF(btrim(p_x->>'licence'), ''), NULLIF(btrim(p_x->>'notes'), ''), p_by)
            RETURNING driverid INTO v_id;
        ELSE
            IF COALESCE((p_x->>'isActive')::boolean, TRUE) = FALSE AND EXISTS (SELECT 1 FROM livestockdeliveries WHERE driverid = v_id AND status = 'Out') THEN
                RAISE EXCEPTION 'This driver has a delivery still out.' USING ERRCODE = 'P0001';
            END IF;
            UPDATE livestockdrivers SET name = v_name, phone = NULLIF(btrim(p_x->>'phone'), ''), licence = NULLIF(btrim(p_x->>'licence'), ''),
                notes = NULLIF(btrim(p_x->>'notes'), ''), isactive = COALESCE((p_x->>'isActive')::boolean, isactive)
            WHERE driverid = v_id AND farmid = p_farmid;
        END IF;
    ELSIF p_kind = 'Vehicle' THEN
        IF EXISTS (SELECT 1 FROM livestockvehicles WHERE farmid = p_farmid AND vehicleid IS DISTINCT FROM v_id
                   AND upper(regexp_replace(registration, '[^A-Za-z0-9]', '', 'g')) = upper(regexp_replace(v_name, '[^A-Za-z0-9]', '', 'g'))) THEN
            RAISE EXCEPTION 'A vehicle with registration % is already recorded.', v_name USING ERRCODE = 'P0001';
        END IF;
        IF v_id IS NULL THEN
            INSERT INTO livestockvehicles (farmid, registration, description, capacity, notes, createdby)
            VALUES (p_farmid, upper(v_name), NULLIF(btrim(p_x->>'description'), ''), NULLIF(btrim(p_x->>'capacity'), ''), NULLIF(btrim(p_x->>'notes'), ''), p_by)
            RETURNING vehicleid INTO v_id;
        ELSE
            UPDATE livestockvehicles SET registration = upper(v_name), description = NULLIF(btrim(p_x->>'description'), ''),
                capacity = NULLIF(btrim(p_x->>'capacity'), ''), notes = NULLIF(btrim(p_x->>'notes'), ''),
                isactive = COALESCE((p_x->>'isActive')::boolean, isactive)
            WHERE vehicleid = v_id AND farmid = p_farmid;
        END IF;
    ELSIF p_kind = 'Route' THEN
        IF v_id IS NULL THEN
            INSERT INTO livestockroutes (farmid, name, description, createdby) VALUES (p_farmid, v_name, NULLIF(btrim(p_x->>'description'), ''), p_by)
            RETURNING routeid INTO v_id;
        ELSE
            UPDATE livestockroutes SET name = v_name, description = NULLIF(btrim(p_x->>'description'), ''),
                isactive = COALESCE((p_x->>'isActive')::boolean, isactive)
            WHERE routeid = v_id AND farmid = p_farmid;
        END IF;
    ELSE
        RAISE EXCEPTION 'Unknown kind.' USING ERRCODE = 'P0001';
    END IF;
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'Not found.' USING ERRCODE = 'P0001';
    END IF;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.fnlivestock_deliveryjson(p_id integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'deliveryId', d.deliveryid, 'date', d.deliverydate, 'driverId', d.driverid, 'driverName', dr.name,
        'vehicleId', d.vehicleid, 'vehicle', v.registration, 'routeId', d.routeid, 'routeName', ro.name,
        'status', d.status, 'expected', d.expected, 'collected', d.collected,
        'shortage', CASE WHEN d.status = 'Returned' THEN d.expected - COALESCE(d.collected, 0) END,
        'returnAccountName', a.name, 'notes', d.notes, 'returnNotes', d.returnnotes,
        'createdBy', d.createdby, 'returnedAt', d.returnedat, 'returnedBy', d.returnedby,
        'sales', (SELECT COALESCE(jsonb_agg(jsonb_build_object('saleId', s.saleid, 'customerName', c.name, 'customerPhone', c.contactphone,
                     'total', s.total, 'owedNow', CASE WHEN s.reversedat IS NULL THEN s.total - fnlivestock_salepaid(s.saleid) ELSE 0 END,
                     'collected', ds.collected, 'reversed', s.reversedat IS NOT NULL) ORDER BY s.saleid), '[]'::jsonb)
                  FROM livestockdeliverysales ds JOIN livestocksales s ON s.saleid = ds.saleid LEFT JOIN customer c ON c.customerid = s.customerid
                  WHERE ds.deliveryid = d.deliveryid))
    FROM livestockdeliveries d JOIN livestockdrivers dr ON dr.driverid = d.driverid
    LEFT JOIN livestockvehicles v ON v.vehicleid = d.vehicleid LEFT JOIN livestockroutes ro ON ro.routeid = d.routeid
    LEFT JOIN livestockcashaccounts a ON a.accountid = d.returnaccountid
    WHERE d.deliveryid = p_id;
$f$;

-- p_filter: {status, driverId, from, to}
CREATE OR REPLACE FUNCTION public.splivestockdelivery_list(p_farmid text, p_filter jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(fnlivestock_deliveryjson(d.deliveryid) ORDER BY (d.status = 'Out') DESC, d.deliverydate DESC, d.deliveryid DESC), '[]'::jsonb)
    FROM livestockdeliveries d
    WHERE d.farmid = p_farmid
      AND (NULLIF(p_filter->>'status', '') IS NULL OR d.status = p_filter->>'status')
      AND (NULLIF(p_filter->>'driverId', '') IS NULL OR d.driverid = (p_filter->>'driverId')::int)
      AND (NULLIF(p_filter->>'from', '') IS NULL OR d.deliverydate >= (p_filter->>'from')::date)
      AND (NULLIF(p_filter->>'to', '') IS NULL OR d.deliverydate <= (p_filter->>'to')::date);
$f$;

-- Unpaid sales not on a delivery that is still out: what a driver can take.
CREATE OR REPLACE FUNCTION public.splivestockdelivery_options(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('saleId', s.saleid, 'date', s.saledate, 'customerName', c.name, 'customerPhone', c.contactphone,
              'total', s.total, 'owed', s.total - fnlivestock_salepaid(s.saleid)) ORDER BY s.saledate, s.saleid), '[]'::jsonb)
    FROM livestocksales s LEFT JOIN customer c ON c.customerid = s.customerid
    WHERE s.farmid = p_farmid AND s.reversedat IS NULL AND s.customerid IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM livestockdeliverysales ds JOIN livestockdeliveries d ON d.deliveryid = ds.deliveryid
                      WHERE ds.saleid = s.saleid AND d.status = 'Out')
      AND (s.saledate >= (now() at time zone 'utc')::date - 14 OR s.total - fnlivestock_salepaid(s.saleid) > 0);
$f$;

-- Send out: {date, driverId, vehicleId, routeId, notes, saleIds:[]}
CREATE OR REPLACE FUNCTION public.splivestockdelivery_post(p_farmid text, p_d jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_id integer; v_sale integer; v_expected numeric := 0;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM livestockdrivers WHERE driverid = NULLIF(p_d->>'driverId', '')::int AND farmid = p_farmid AND isactive) THEN
        RAISE EXCEPTION 'Choose the driver.' USING ERRCODE = 'P0001';
    END IF;
    IF jsonb_array_length(COALESCE(p_d->'saleIds', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'Choose the sales going out.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO livestockdeliveries (farmid, deliverydate, driverid, vehicleid, routeid, notes, createdby)
    VALUES (p_farmid, COALESCE(NULLIF(p_d->>'date', '')::date, (now() at time zone 'utc')::date), (p_d->>'driverId')::int,
            NULLIF(p_d->>'vehicleId', '')::int, NULLIF(p_d->>'routeId', '')::int, NULLIF(btrim(p_d->>'notes'), ''), p_by)
    RETURNING deliveryid INTO v_id;
    FOR v_sale IN SELECT DISTINCT (e #>> '{}')::int FROM jsonb_array_elements(p_d->'saleIds') e LOOP
        IF NOT EXISTS (SELECT 1 FROM livestocksales WHERE saleid = v_sale AND farmid = p_farmid AND reversedat IS NULL) THEN
            RAISE EXCEPTION 'A sale on the delivery was not found.' USING ERRCODE = 'P0001';
        END IF;
        IF EXISTS (SELECT 1 FROM livestockdeliverysales ds JOIN livestockdeliveries d ON d.deliveryid = ds.deliveryid
                   WHERE ds.saleid = v_sale AND d.status = 'Out' AND d.deliveryid <> v_id) THEN
            RAISE EXCEPTION 'Sale % is already out on another delivery.', v_sale USING ERRCODE = 'P0001';
        END IF;
        INSERT INTO livestockdeliverysales (deliveryid, saleid) VALUES (v_id, v_sale);
        v_expected := v_expected + (SELECT total - fnlivestock_salepaid(saleid) FROM livestocksales WHERE saleid = v_sale);
    END LOOP;
    UPDATE livestockdeliveries SET expected = v_expected WHERE deliveryid = v_id;
    RETURN v_id;
END
$f$;

-- Driver comes back: {accountId, notes, collections:[{saleId, amount}]}.
-- Each amount is a customer payment against its sale, into the account.
CREATE OR REPLACE FUNCTION public.splivestockdelivery_return(p_farmid text, p_id integer, p_r jsonb, p_by text)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_d livestockdeliveries%ROWTYPE; v_c jsonb; v_sale integer; v_amt numeric; v_total numeric := 0; v_pay integer; v_cust integer; v_dt date;
BEGIN
    SELECT * INTO v_d FROM livestockdeliveries WHERE deliveryid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND OR v_d.status <> 'Out' THEN
        RAISE EXCEPTION 'That delivery is not out.' USING ERRCODE = 'P0001';
    END IF;
    v_dt := (now() at time zone 'utc')::date;
    FOR v_c IN SELECT * FROM jsonb_array_elements(COALESCE(p_r->'collections', '[]'::jsonb)) LOOP
        v_sale := NULLIF(v_c->>'saleId', '')::int;
        v_amt := COALESCE(NULLIF(v_c->>'amount', '')::numeric, 0);
        CONTINUE WHEN v_amt = 0;
        IF v_amt < 0 THEN
            RAISE EXCEPTION 'Collected amounts cannot be negative.' USING ERRCODE = 'P0001';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM livestockdeliverysales WHERE deliveryid = p_id AND saleid = v_sale) THEN
            RAISE EXCEPTION 'Sale % was not on this delivery.', v_sale USING ERRCODE = 'P0001';
        END IF;
        SELECT customerid INTO v_cust FROM livestocksales WHERE saleid = v_sale;
        v_pay := splivestockcustomerpayment_core(p_farmid, v_cust, v_dt, v_amt, NULLIF(p_r->>'accountId', '')::int,
                    'Delivery ' || p_id, 'Collected by driver', p_by, v_sale, FALSE);
        UPDATE livestockdeliverysales SET paymentid = v_pay, collected = v_amt WHERE deliveryid = p_id AND saleid = v_sale;
        v_total := v_total + v_amt;
    END LOOP;
    IF v_total > 0 AND NULLIF(p_r->>'accountId', '') IS NULL THEN
        RAISE EXCEPTION 'Choose the account the driver''s money went into.' USING ERRCODE = 'P0001';
    END IF;
    IF v_total < v_d.expected AND NULLIF(btrim(p_r->>'notes'), '') IS NULL THEN
        RAISE EXCEPTION 'The driver brought back % of the % expected. Say what happened to the rest.',
            to_char(v_total, 'FM999,999,990.00'), to_char(v_d.expected, 'FM999,999,990.00') USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockdeliveries SET status = 'Returned', collected = v_total, returnaccountid = NULLIF(p_r->>'accountId', '')::int,
        returnnotes = NULLIF(btrim(p_r->>'notes'), ''), returnedat = (now() at time zone 'utc'), returnedby = p_by
    WHERE deliveryid = p_id;
    RETURN fnlivestock_deliveryjson(p_id);
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockdelivery_cancel(p_farmid text, p_id integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    UPDATE livestockdeliveries SET status = 'Cancelled', returnedat = (now() at time zone 'utc'), returnedby = p_by
    WHERE deliveryid = p_id AND farmid = p_farmid AND status = 'Out';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Only a delivery still out can be cancelled.' USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- Per driver over a period: deliveries, expected, collected, short.
CREATE OR REPLACE FUNCTION public.splivestockdriver_report(p_farmid text, p_from date, p_to date)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('driverId', x.driverid, 'name', x.name, 'deliveries', x.deliveries,
            'stillOut', x.stillout, 'expected', x.expected, 'collected', x.collected, 'short', x.short) ORDER BY x.name), '[]'::jsonb)
    FROM (
        SELECT dr.driverid, dr.name,
               count(d.deliveryid) AS deliveries,
               count(d.deliveryid) FILTER (WHERE d.status = 'Out') AS stillout,
               COALESCE(SUM(d.expected) FILTER (WHERE d.status = 'Returned'), 0) AS expected,
               COALESCE(SUM(d.collected) FILTER (WHERE d.status = 'Returned'), 0) AS collected,
               COALESCE(SUM(d.expected - COALESCE(d.collected, 0)) FILTER (WHERE d.status = 'Returned'), 0) AS short
        FROM livestockdrivers dr
        LEFT JOIN livestockdeliveries d ON d.driverid = dr.driverid AND d.deliverydate BETWEEN p_from AND p_to AND d.status <> 'Cancelled'
        WHERE dr.farmid = p_farmid
        GROUP BY dr.driverid, dr.name
    ) x;
$f$;

-- ---------------------------------------------------------------------------
-- 4. IAM
-- ---------------------------------------------------------------------------
DO $iam$
DECLARE v integer := 0;
BEGIN
    v := v + splivestock_iammirror('daily-closing', 'daily-closing', 'Finance', 'Daily Closing', 'Checking and closing each day; reopening a closed day.', 82);
    v := v + splivestock_iammirror('drivers', 'drivers', 'Logistics', 'Drivers', 'Drivers who deliver.', 100);
    v := v + splivestock_iammirror('vehicles', 'vehicles', 'Logistics', 'Vehicles', 'Delivery vehicles.', 101);
    v := v + splivestock_iammirror('routes', 'routes', 'Logistics', 'Routes', 'Delivery routes.', 102);
    v := v + splivestock_iammirror('deliveries', 'deliveries', 'Logistics', 'Deliveries', 'Sending sales out with a driver.', 103);
    v := v + splivestock_iammirror('driver-returns', 'driver-returns', 'Logistics', 'Driver Returns', 'Taking in what a driver collected.', 104);
    RAISE NOTICE '464: % livestock permission key(s) added.', v;
END
$iam$;

COMMIT;

-- 473: Livestock sales get their number automatically.
--
-- splivestocksale_post no longer takes a typed receipt number. Each sale is
-- numbered per farm, LS-0001, LS-0002, ... (like purchases, LP-0001, in 470),
-- kept in livestocksales.reference. Reversed sales keep their number, so a
-- number is never handed out twice. An advisory lock per farm stops two saves
-- at the same moment taking the same number. The number also goes on the
-- customer payment taken with the sale, as the typed reference did.
--
-- Body is the live splivestocksale_post with only the reference changed.
-- Sales saved before 473 get a number, oldest first. Safe to re-run.

BEGIN;

CREATE OR REPLACE FUNCTION public.fnlivestock_nextsalenumber(p_farmid text)
 RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
    v_n integer;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('livestocksale:' || p_farmid));
    SELECT COALESCE(max(substring(reference FROM '^LS-(\d+)$')::int), 0) + 1 INTO v_n
      FROM livestocksales WHERE farmid = p_farmid;
    RETURN 'LS-' || lpad(v_n::text, 4, '0');
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestocksale_post(p_farmid text, p_s jsonb, p_by text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_date   date    := NULLIF(p_s->>'date', '')::date;
    v_cust   integer := NULLIF(p_s->>'customerId', '')::int;
    v_recv   numeric := COALESCE(NULLIF(p_s->>'amountReceived', '')::numeric, 0);
    v_over   text    := NULLIF(btrim(COALESCE(p_s->>'overrideWithdrawal', '')), '');
    v_id     integer;
    v_l      jsonb;
    v_qty    numeric;
    v_price  numeric;
    v_total  numeric := 0;
    v_g      livestockgroups%ROWTYPE;
    v_a      livestockanimals%ROWTYPE;
    v_it     livestockitems%ROWTYPE;
    v_mid    integer;
    v_cost   numeric;
    v_until  date;
    v_cname  text;
    v_ref    text;
BEGIN
    IF v_date IS NULL OR v_date > (now() at time zone 'utc')::date + 1 THEN
        RAISE EXCEPTION 'Enter the sale date (not in the future).' USING ERRCODE = 'P0001';
    END IF;
    IF v_cust IS NOT NULL THEN
        SELECT name INTO v_cname FROM customer WHERE customerid = v_cust AND farmid = p_farmid;
        IF v_cname IS NULL THEN
            RAISE EXCEPTION 'That customer was not found.' USING ERRCODE = 'P0001';
        END IF;
    END IF;
    IF jsonb_array_length(COALESCE(p_s->'lines', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'Add what was sold.' USING ERRCODE = 'P0001';
    END IF;
    IF v_recv < 0 THEN
        RAISE EXCEPTION 'The amount received cannot be negative.' USING ERRCODE = 'P0001';
    END IF;

    -- The sale number is the system's, never typed (473).
    v_ref := fnlivestock_nextsalenumber(p_farmid);

    INSERT INTO livestocksales (farmid, customerid, saledate, reference, duedate, total, notes, withdrawaloverride, createdby)
    VALUES (p_farmid, v_cust, v_date, v_ref, NULLIF(p_s->>'dueDate', '')::date, 0,
            NULLIF(btrim(p_s->>'notes'), ''), v_over, p_by)
    RETURNING saleid INTO v_id;

    FOR v_l IN SELECT * FROM jsonb_array_elements(p_s->'lines') LOOP
        v_price := NULLIF(v_l->>'unitPrice', '')::numeric;
        IF v_price IS NULL OR v_price < 0 THEN
            RAISE EXCEPTION 'Enter the price on every line.' USING ERRCODE = 'P0001';
        END IF;
        CASE COALESCE(v_l->>'lineType', '')
        WHEN 'Animals' THEN
            v_qty := NULLIF(v_l->>'quantity', '')::numeric;
            SELECT * INTO v_g FROM livestockgroups WHERE groupid = NULLIF(v_l->>'groupId', '')::int AND farmid = p_farmid AND NOT isdeleted;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Choose the group the animals came from.' USING ERRCODE = 'P0001';
            END IF;
            IF v_qty IS NULL OR v_qty <= 0 OR v_qty <> trunc(v_qty) THEN
                RAISE EXCEPTION 'Enter how many animals from % (a whole number).', v_g.name USING ERRCODE = 'P0001';
            END IF;
            v_until := (SELECT max((w->>'meatUntil')::date) FROM jsonb_array_elements(splivestockwithdrawals(p_farmid, v_g.groupid)) w);
            IF v_until IS NOT NULL AND v_until >= v_date AND v_over IS NULL THEN
                RAISE EXCEPTION '% is under a medicine withdrawal period until %. Its animals should not be sold for meat before then.',
                    v_g.name, to_char(v_until, 'DD Mon YYYY') USING ERRCODE = 'LV005';
            END IF;
            -- Untagged animals only: tagged ones are sold one by one so their record closes.
            PERFORM splivestockhead_post(p_farmid, v_g.groupid, v_date, 'Sale', -v_qty::int, p_by,
                'Sold' || COALESCE(' to ' || v_cname, ''), NULL, NULL, 'Sale', v_id);
            INSERT INTO livestocksalelines (saleid, linetype, groupid, quantity, unitprice, linetotal, weightkg)
            VALUES (v_id, 'Animals', v_g.groupid, v_qty, v_price, round(v_qty * v_price, 2), NULLIF(v_l->>'weightKg', '')::numeric);
            v_total := v_total + round(v_qty * v_price, 2);
        WHEN 'Tagged' THEN
            SELECT * INTO v_a FROM livestockanimals WHERE animalid = NULLIF(v_l->>'animalId', '')::int AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Choose the animal sold.' USING ERRCODE = 'P0001';
            END IF;
            IF v_a.status <> 'Active' THEN
                RAISE EXCEPTION 'Tag % is already marked %.', v_a.tagnumber, lower(v_a.status) USING ERRCODE = 'P0001';
            END IF;
            v_until := (SELECT max((w->>'meatUntil')::date) FROM jsonb_array_elements(splivestockwithdrawals(p_farmid, v_a.groupid)) w);
            IF v_until IS NOT NULL AND v_until >= v_date AND v_over IS NULL THEN
                RAISE EXCEPTION 'Tag % is under a medicine withdrawal period until %.', v_a.tagnumber, to_char(v_until, 'DD Mon YYYY')
                    USING ERRCODE = 'LV005';
            END IF;
            PERFORM splivestockhead_post(p_farmid, v_a.groupid, v_date, 'Sale', -1, p_by,
                'Tag ' || v_a.tagnumber || ' sold' || COALESCE(' to ' || v_cname, ''), NULL, v_a.animalid, 'Sale', v_id);
            UPDATE livestockanimals SET status = 'Sold', statusdate = v_date, statusnotes = 'Sale ' || v_id,
                updatedat = (now() at time zone 'utc'), updatedby = p_by
            WHERE animalid = v_a.animalid;
            INSERT INTO livestocksalelines (saleid, linetype, groupid, animalid, quantity, unitprice, linetotal, weightkg)
            VALUES (v_id, 'Tagged', v_a.groupid, v_a.animalid, 1, v_price, round(v_price, 2), NULLIF(v_l->>'weightKg', '')::numeric);
            v_total := v_total + round(v_price, 2);
        WHEN 'Product' THEN
            v_qty := NULLIF(v_l->>'quantity', '')::numeric;
            SELECT * INTO v_it FROM livestockitems WHERE itemid = NULLIF(v_l->>'itemId', '')::int AND farmid = p_farmid AND NOT isdeleted;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Choose what was sold.' USING ERRCODE = 'P0001';
            END IF;
            IF v_qty IS NULL OR v_qty <= 0 THEN
                RAISE EXCEPTION 'Enter how much % was sold.', v_it.name USING ERRCODE = 'P0001';
            END IF;
            v_mid := splivestockstock_post(p_farmid, v_it.itemid, v_date, 'Usage', -v_qty, NULL, p_by,
                'Sold' || COALESCE(' to ' || v_cname, ''), 'Sale', v_id);
            v_cost := -(SELECT totalcost FROM livestockstockmovements WHERE movementid = v_mid);
            INSERT INTO livestocksalelines (saleid, linetype, itemid, quantity, unitprice, linetotal, costtotal)
            VALUES (v_id, 'Product', v_it.itemid, v_qty, v_price, round(v_qty * v_price, 2), v_cost);
            v_total := v_total + round(v_qty * v_price, 2);
        ELSE
            RAISE EXCEPTION 'Unknown line type "%".', v_l->>'lineType' USING ERRCODE = 'P0001';
        END CASE;
    END LOOP;
    UPDATE livestocksales SET total = v_total WHERE saleid = v_id;

    IF v_recv > v_total THEN
        RAISE EXCEPTION 'More is received (%) than the sale comes to (%).', v_recv, v_total USING ERRCODE = 'P0001';
    END IF;
    IF v_cust IS NULL AND v_recv < v_total THEN
        RAISE EXCEPTION 'A sale with no customer must be paid in full at the time. Choose the customer to sell on credit.' USING ERRCODE = 'P0001';
    END IF;
    IF v_recv > 0 THEN
        PERFORM splivestockcustomerpayment_core(p_farmid, v_cust, v_date, v_recv, NULLIF(p_s->>'accountId', '')::int,
            v_ref, 'Paid with the sale', p_by, v_id, TRUE);
    END IF;
    RETURN v_id;
END
$function$;

-- Sales saved before 473 without a number get one, oldest first.
DO $b$
DECLARE r record;
BEGIN
    FOR r IN SELECT saleid, farmid FROM livestocksales
              WHERE NULLIF(btrim(reference), '') IS NULL ORDER BY farmid, saledate, saleid LOOP
        UPDATE livestocksales SET reference = fnlivestock_nextsalenumber(r.farmid) WHERE saleid = r.saleid;
    END LOOP;
END $b$;

COMMIT;

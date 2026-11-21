-- 470: Livestock purchases get their invoice number automatically.
--
-- splivestockpurchase_post no longer takes a typed reference. Each purchase
-- is numbered per farm, LP-0001, LP-0002, ... (the same shape as intake
-- batches, LB-0001), kept in livestockpurchases.reference. Reversed purchases
-- keep their number, so a number is never handed out twice. An advisory lock
-- per farm stops two saves at the same moment taking the same number.
--
-- The number also goes on the animal batch note and the supplier payment, as
-- the typed reference did. Body is the live 461 version with only the
-- reference changed. Safe to re-run.

BEGIN;

CREATE OR REPLACE FUNCTION public.fnlivestock_nextpurchasenumber(p_farmid text)
 RETURNS text LANGUAGE plpgsql AS $f$
DECLARE
    v_n   integer;
    v_ref text;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('livestockpurchase:' || p_farmid));
    SELECT COALESCE(max(substring(reference FROM '^LP-(\d+)$')::int), 0) + 1 INTO v_n
      FROM livestockpurchases WHERE farmid = p_farmid;
    v_ref := 'LP-' || lpad(v_n::text, 4, '0');
    RETURN v_ref;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockpurchase_post(p_farmid text, p_p jsonb, p_by text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_date  date    := NULLIF(p_p->>'date', '')::date;
    v_sup   integer := NULLIF(p_p->>'supplierId', '')::int;
    v_paid  numeric := COALESCE(NULLIF(p_p->>'amountPaid', '')::numeric, 0);
    v_id    integer;
    v_l     jsonb;
    v_qty   numeric;
    v_cost  numeric;
    v_total numeric := 0;
    v_item  livestockitems%ROWTYPE;
    v_batch integer;
    v_supname text;
    v_ref   text;
BEGIN
    IF v_date IS NULL OR v_date > (now() at time zone 'utc')::date + 1 THEN
        RAISE EXCEPTION 'Enter the purchase date (not in the future).' USING ERRCODE = 'P0001';
    END IF;
    IF v_sup IS NOT NULL THEN
        SELECT name INTO v_supname FROM supplier WHERE supplierid = v_sup AND farmid = p_farmid;
        IF v_supname IS NULL THEN
            RAISE EXCEPTION 'That supplier was not found.' USING ERRCODE = 'P0001';
        END IF;
    END IF;
    IF jsonb_array_length(COALESCE(p_p->'lines', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'Add what was bought.' USING ERRCODE = 'P0001';
    END IF;
    IF v_paid < 0 THEN
        RAISE EXCEPTION 'The amount paid cannot be negative.' USING ERRCODE = 'P0001';
    END IF;

    -- The invoice number is the system's, never typed (470).
    v_ref := fnlivestock_nextpurchasenumber(p_farmid);

    INSERT INTO livestockpurchases (farmid, supplierid, purchasedate, reference, duedate, total, notes, createdby)
    VALUES (p_farmid, v_sup, v_date, v_ref, NULLIF(p_p->>'dueDate', '')::date, 0,
            NULLIF(btrim(p_p->>'notes'), ''), p_by)
    RETURNING purchaseid INTO v_id;

    FOR v_l IN SELECT * FROM jsonb_array_elements(p_p->'lines') LOOP
        v_qty  := NULLIF(v_l->>'quantity', '')::numeric;
        v_cost := NULLIF(v_l->>'unitCost', '')::numeric;
        IF v_qty IS NULL OR v_qty <= 0 THEN
            RAISE EXCEPTION 'Enter a quantity on every line.' USING ERRCODE = 'P0001';
        END IF;
        IF v_cost IS NULL OR v_cost < 0 THEN
            RAISE EXCEPTION 'Enter the price on every line (0 if free).' USING ERRCODE = 'P0001';
        END IF;
        IF COALESCE(v_l->>'lineType', 'Item') = 'Item' THEN
            SELECT * INTO v_item FROM livestockitems WHERE itemid = NULLIF(v_l->>'itemId', '')::int AND farmid = p_farmid AND NOT isdeleted;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Choose the item on every line.' USING ERRCODE = 'P0001';
            END IF;
            PERFORM splivestockstock_post(p_farmid, v_item.itemid, v_date, 'Purchase', v_qty, v_cost, p_by,
                'Bought' || COALESCE(' from ' || v_supname, ''), 'Purchase', v_id);
            INSERT INTO livestockpurchaselines (purchaseid, linetype, itemid, quantity, unitcost, linetotal)
            VALUES (v_id, 'Item', v_item.itemid, v_qty, v_cost, round(v_qty * v_cost, 2));
        ELSIF v_l->>'lineType' = 'Animals' THEN
            IF v_qty <> trunc(v_qty) THEN
                RAISE EXCEPTION 'Animals are counted in whole numbers.' USING ERRCODE = 'P0001';
            END IF;
            v_batch := splivestockbatch_save(p_farmid, jsonb_build_object(
                'speciesCode', v_l->>'speciesCode', 'quantity', v_qty::int, 'intakeDate', v_date, 'source', 'Purchased',
                'supplierId', v_sup, 'costPerHead', v_cost, 'breed', v_l->>'breed', 'ageAtIntake', v_l->>'ageAtIntake',
                'notes', 'Purchase ' || v_ref), p_by);
            UPDATE livestockbatches SET purchaseid = v_id WHERE batchid = v_batch;
            INSERT INTO livestockpurchaselines (purchaseid, linetype, batchid, quantity, unitcost, linetotal)
            VALUES (v_id, 'Animals', v_batch, v_qty, v_cost, round(v_qty * v_cost, 2));
        ELSIF v_l->>'lineType' = 'Expense' THEN
            IF NOT fnlivestock_isexpensecategory(v_l->>'expenseCategory') THEN
                RAISE EXCEPTION 'Choose what the bill was for.' USING ERRCODE = 'P0001';
            END IF;
            IF NULLIF(v_l->>'groupId', '') IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM livestockgroups WHERE groupid = (v_l->>'groupId')::int AND farmid = p_farmid AND NOT isdeleted) THEN
                RAISE EXCEPTION 'That group was not found.' USING ERRCODE = 'P0001';
            END IF;
            INSERT INTO livestockpurchaselines (purchaseid, linetype, expensecategory, description, groupid, quantity, unitcost, linetotal)
            VALUES (v_id, 'Expense', v_l->>'expenseCategory', NULLIF(btrim(v_l->>'description'), ''), NULLIF(v_l->>'groupId', '')::int,
                    v_qty, v_cost, round(v_qty * v_cost, 2));
        ELSE
            RAISE EXCEPTION 'Unknown line type "%".', v_l->>'lineType' USING ERRCODE = 'P0001';
        END IF;
        v_total := v_total + round(v_qty * v_cost, 2);
    END LOOP;
    UPDATE livestockpurchases SET total = v_total WHERE purchaseid = v_id;

    IF v_paid > v_total THEN
        RAISE EXCEPTION 'More is paid (%) than the purchase comes to (%).', v_paid, v_total USING ERRCODE = 'P0001';
    END IF;
    IF v_sup IS NULL AND v_paid < v_total THEN
        RAISE EXCEPTION 'A purchase with no supplier must be paid in full at the time.' USING ERRCODE = 'P0001';
    END IF;
    IF v_paid > 0 THEN
        PERFORM splivestocksupplierpayment_core(p_farmid, v_sup, v_date, v_paid, NULLIF(p_p->>'accountId', '')::int,
            v_ref, 'Paid with the purchase', p_by, v_id, TRUE);
    END IF;
    RETURN v_id;
END
$function$;

-- Purchases saved before 470 without a number get one, oldest first.
DO $b$
DECLARE r record;
BEGIN
    FOR r IN SELECT purchaseid, farmid FROM livestockpurchases
              WHERE NULLIF(btrim(reference), '') IS NULL ORDER BY farmid, purchasedate, purchaseid LOOP
        UPDATE livestockpurchases SET reference = fnlivestock_nextpurchasenumber(r.farmid) WHERE purchaseid = r.purchaseid;
    END LOOP;
END $b$;

COMMIT;

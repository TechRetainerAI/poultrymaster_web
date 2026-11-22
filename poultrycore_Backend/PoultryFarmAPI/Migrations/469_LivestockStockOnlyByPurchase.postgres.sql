-- 469: Livestock stock comes in only through a purchase.
--
-- As on the poultry side, adding a stock item creates the item and nothing
-- else; stock arrives through a purchase (splivestockpurchase_post), which
-- also records the money leaving a cash account. Two back doors are closed:
--
--   splivestockitem_save   -- no longer posts 'Opening' stock on create
--                             (openingQuantity is ignored).
--   splivestockstock_adjust -- 'StockIn' is refused; only an 'Adjustment'
--                             (a count correction with a reason) remains.
--
-- Old 'Opening' / 'StockIn' movements stay as they are (none are live on dev
-- after Rabbit Feed's mistaken opening stock was reversed on 2026-11-21).
-- Both bodies are the live 459 versions with only those parts changed.
-- Safe to re-run.

BEGIN;

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
        -- The item only. Its stock comes in through a purchase (469).
        INSERT INTO livestockitems (farmid, name, category, unit, kgperunit, minimumstock, speciescode, notes, createdby)
        VALUES (p_farmid, v_name, v_cat, v_unit, v_kg, v_min, v_sp, NULLIF(btrim(p_item->>'notes'), ''), p_by)
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
        updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE itemid = v_id;
    RETURN v_id;
END
$function$;

CREATE OR REPLACE FUNCTION public.splivestockstock_adjust(p_farmid text, p_itemid integer, p_date date, p_type text,
    p_quantity numeric, p_unitcost numeric, p_notes text, p_by text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_id integer;
BEGIN
    IF p_type = 'StockIn' THEN
        RAISE EXCEPTION 'Stock comes in through a purchase. Use Record purchase.' USING ERRCODE = 'P0001';
    END IF;
    IF p_type IS DISTINCT FROM 'Adjustment' THEN
        RAISE EXCEPTION 'Unknown stock change "%".', p_type USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(btrim(p_notes), '') IS NULL THEN
        RAISE EXCEPTION 'Say why the stock is being corrected.' USING ERRCODE = 'P0001';
    END IF;
    v_id := splivestockstock_post(p_farmid, p_itemid, p_date, p_type, p_quantity, p_unitcost, p_by, p_notes);
    RETURN fnlivestock_itemjson(p_itemid) || jsonb_build_object('movementId', v_id);
END
$function$;

COMMIT;

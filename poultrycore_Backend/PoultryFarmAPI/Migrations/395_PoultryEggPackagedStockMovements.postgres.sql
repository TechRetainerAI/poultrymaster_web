-- =============================================================================
-- 395: Egg packaging, phase 3 -- stock movements in Boxes, Crates and Pieces.
-- Needs 393.
--
-- New Stock Movement can take an egg quantity as boxes + crates + pieces. It
-- is still ONE movement of individual eggs: 1 box + 2 crates + 5 pcs at 14
-- crates/box posts exactly +485 eggs through the existing
-- sppoultrymanualmovement_post (373), with all of its rules (batch -> flock,
-- effective date, reason, stock never below zero, reversal).
--
--   1. poultrymanualstockmovements keeps what the movement was ENTERED as and
--      the conversion of that day (NULL on every other movement).
--   2. sppoultrymanualmovement_postpackaged: converts with THIS company's
--      packaging (never the browser's), refuses boxes when they are off and
--      anything but an egg class (Broken Eggs / Dead Birds / birds / others
--      stay in their own units), then calls sppoultrymanualmovement_post with
--      the egg count and records the packaging on the movement.
--   3. sppoultrymanualmovement_list returns the packaging (trailing columns).
--
-- Reversal needs no change: it negates the movement's stored egg quantity,
-- so a later box-size change cannot make it restore a different number.
--
-- Idempotent: safe to run twice.
-- =============================================================================

DO $pre$
BEGIN
    IF to_regprocedure('public.fnpoultry_eggpieces(integer,integer,integer,integer,integer)') IS NULL THEN
        RAISE EXCEPTION '395 needs 393 (egg packaging) first.';
    END IF;
END;
$pre$;

-- -----------------------------------------------------------------------------
-- 1. Columns
-- -----------------------------------------------------------------------------
ALTER TABLE public.poultrymanualstockmovements ADD COLUMN IF NOT EXISTS qtyboxes integer NULL;
ALTER TABLE public.poultrymanualstockmovements ADD COLUMN IF NOT EXISTS qtycrates integer NULL;
ALTER TABLE public.poultrymanualstockmovements ADD COLUMN IF NOT EXISTS qtypieces integer NULL;
ALTER TABLE public.poultrymanualstockmovements ADD COLUMN IF NOT EXISTS eggspercrate integer NULL;
ALTER TABLE public.poultrymanualstockmovements ADD COLUMN IF NOT EXISTS cratesperbox integer NULL;

DO $c$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_poultrymanualstockmovements_packaging') THEN
        ALTER TABLE public.poultrymanualstockmovements ADD CONSTRAINT ck_poultrymanualstockmovements_packaging CHECK (
            COALESCE(qtyboxes, 0) >= 0 AND COALESCE(qtycrates, 0) >= 0 AND COALESCE(qtypieces, 0) >= 0
            AND (eggspercrate IS NULL OR eggspercrate >= 1)
            AND (COALESCE(qtyboxes, 0) = 0 OR cratesperbox >= 1));
    END IF;
END;
$c$;

-- -----------------------------------------------------------------------------
-- 2. Post a movement entered as packaging
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrymanualmovement_postpackaged(
    p_farmid text, p_poultryproductid integer, p_movementtype text,
    p_boxes integer, p_crates integer, p_pieces integer,
    p_unitcost numeric, p_batchid integer, p_flockid integer, p_effectivedate date,
    p_reason text, p_note text, p_requestkey text, p_by text)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_pk   record;
    v_cpb  integer;
    v_eggs bigint;
    v_key  text := COALESCE(NULLIF(btrim(COALESCE(p_requestkey, '')), ''), 'pkg-' || md5(random()::text || clock_timestamp()::text));
    v_res  jsonb;
    v_id   integer;
BEGIN
    IF p_poultryproductid IS NULL OR NOT EXISTS (
        SELECT 1 FROM poultryproducts p WHERE p.poultryproductid = p_poultryproductid AND p.farmid = p_farmid) THEN
        RAISE EXCEPTION 'That item does not belong to this company.';
    END IF;
    -- Only intact eggs are counted in boxes and crates. Broken Eggs, Dead
    -- Birds, birds and other products keep their own units.
    IF NOT public.fnpoultryproduct_isegg(p_poultryproductid) THEN
        RAISE EXCEPTION 'Only egg stock can be entered in boxes, crates and pieces.';
    END IF;

    SELECT * INTO v_pk FROM public.fnpoultry_eggpackaging(p_farmid);
    IF COALESCE(p_boxes, 0) > 0 AND NOT v_pk.enableboxes THEN
        RAISE EXCEPTION 'Boxes are not turned on for this company. Enter crates and pieces, or turn boxes on in Egg Sorting > Sizes & settings.';
    END IF;
    v_cpb  := CASE WHEN v_pk.enableboxes THEN v_pk.cratesperbox END;
    v_eggs := public.fnpoultry_eggpieces(COALESCE(p_boxes, 0), COALESCE(p_crates, 0), COALESCE(p_pieces, 0), v_pk.eggspercrate, v_cpb);
    IF v_eggs <= 0 THEN
        RAISE EXCEPTION 'Enter at least one box, crate or egg.';
    END IF;

    v_res := public.sppoultrymanualmovement_post(
        p_farmid => p_farmid, p_poultryproductid => p_poultryproductid, p_rawmaterialitemid => NULL,
        p_movementtype => p_movementtype, p_quantity => v_eggs::numeric, p_unitcost => p_unitcost,
        p_batchid => p_batchid, p_flockid => p_flockid, p_effectivedate => p_effectivedate,
        p_reason => p_reason, p_disposition => NULL, p_note => p_note, p_requestkey => v_key, p_by => p_by);

    -- The movement just posted (or the one a repeated key returned): keep how
    -- it was entered. A repeat finds its packaging already there.
    SELECT m.movementid INTO v_id FROM poultrymanualstockmovements m
    WHERE  m.farmid = p_farmid AND m.requestkey = v_key;
    UPDATE poultrymanualstockmovements m
    SET    qtyboxes = COALESCE(p_boxes, 0), qtycrates = COALESCE(p_crates, 0), qtypieces = COALESCE(p_pieces, 0),
           eggspercrate = v_pk.eggspercrate, cratesperbox = v_cpb
    WHERE  m.movementid = v_id AND m.qtycrates IS NULL;

    RETURN v_res || jsonb_build_object(
        'eggs', v_eggs,
        'packaging', public.fnpoultry_eggqtytext(v_eggs, v_pk.eggspercrate, v_cpb, 'BoxesCratesPieces'));
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. The list carries the packaging (trailing columns; RETURNS TABLE changes)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultrymanualmovement_list(text);
CREATE FUNCTION public.sppoultrymanualmovement_list(p_farmid text)
 RETURNS TABLE(movementid integer, movementno text, itemkind text, poultryproductid integer, rawmaterialitemid integer, itemname text, movementtype text, quantity numeric, unitcost numeric, batchid integer, batchcode text, flockid integer, flockname text, effectivedate date, reason text, disposition text, convertedtobroken boolean, note text, itembefore numeric, itemafter numeric, birdadjustmentid integer, rawadjustmentid integer, status text, createdby text, createdat timestamp without time zone, reversedat timestamp without time zone, reversedby text, reversalreason text,
               qtyboxes integer, qtycrates integer, qtypieces integer, eggspercrate integer, cratesperbox integer)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT m.movementid, m.movementno, m.itemkind, m.poultryproductid, m.rawmaterialitemid, m.itemname, m.movementtype,
           m.quantity, m.unitcost, m.batchid, b.batchcode::text, m.flockid, f.name::text, m.effectivedate, m.reason,
           m.disposition, m.convertedtobroken, m.note, m.itembefore, m.itemafter, m.birdadjustmentid, m.rawadjustmentid,
           m.status, m.createdby, m.createdat, m.reversedat, m.reversedby, m.reversalreason,
           m.qtyboxes, m.qtycrates, m.qtypieces, m.eggspercrate, m.cratesperbox
    FROM   poultrymanualstockmovements m
    LEFT   JOIN mainflockbatch b ON b.batchid = m.batchid
    LEFT   JOIN flock f ON f.flockid = m.flockid
    WHERE  m.farmid = p_farmid
    ORDER  BY m.effectivedate DESC, m.movementid DESC;
$function$;

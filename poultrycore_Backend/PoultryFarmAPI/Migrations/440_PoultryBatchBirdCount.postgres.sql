-- 440: Batch bird count -- set every flock of a batch to its counted birds in one save.
--
-- Farms count their pens (Front Room1 861, Room2 1,054 ...) and then had to
-- enter one Stock Movement per flock (Decrease / Stock Count Correction / 50).
-- sppoultrymanualmovement_bulkbirdcount takes the batch, the date and one
-- counted figure per flock, works out each flock's change (counted - birds
-- now) and posts it through sppoultrymanualmovement_post -- the very call a
-- single "New movement" makes -- so each flock gets its own MSM movement,
-- bird adjustment and stock row, and each can be reversed on its own.
--
-- All or nothing: the flocks are posted in one transaction, so one refused
-- flock (closed, would go below 0, ...) saves none of them.
-- Stale guard: the page sends the birds it showed; if a flock changed since
-- (a production record, another count), the save is refused, not doubled.
-- A flock whose count matches is skipped (no zero movement).

BEGIN;

CREATE OR REPLACE FUNCTION public.sppoultrymanualmovement_bulkbirdcount(
    p_farmid        text,
    p_batchid       integer,
    p_effectivedate date,
    p_lines         jsonb,        -- [{ "flockId": 1, "countedBirds": 861, "currentBirds": 900 }]
    p_note          text DEFAULT NULL,
    p_requestkey    text DEFAULT NULL,
    p_by            text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_key      text := NULLIF(btrim(COALESCE(p_requestkey, '')), '');
    v_note     text := NULLIF(btrim(COALESCE(p_note, '')), '');
    v_birds    integer;
    v_batch    record;
    v_line     jsonb;
    v_flockid  integer;
    v_counted  numeric;
    v_shown    numeric;
    v_flock    record;
    v_now      integer;
    v_change   integer;
    v_res      jsonb;
    v_out      jsonb := '[]'::jsonb;
    v_before   integer := 0;
    v_after    integer := 0;
    v_posted   integer := 0;
    v_seen     integer[] := ARRAY[]::integer[];
BEGIN
    -- The same save sent twice (double click, retry) returns what it posted.
    IF v_key IS NOT NULL AND EXISTS (
        SELECT 1 FROM poultrymanualstockmovements m
        WHERE  m.farmid = p_farmid AND m.requestkey LIKE v_key || ':%') THEN
        RETURN jsonb_build_object('repeated', TRUE, 'movements',
            (SELECT COALESCE(jsonb_agg(jsonb_build_object('flockId', m.flockid, 'movementNo', m.movementno,
                                                           'change', m.quantity) ORDER BY m.movementid), '[]'::jsonb)
             FROM poultrymanualstockmovements m
             WHERE m.farmid = p_farmid AND m.requestkey LIKE v_key || ':%'));
    END IF;

    SELECT b.batchid, b.batchcode INTO v_batch FROM mainflockbatch b
    WHERE  b.batchid = p_batchid AND b.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Choose the batch.' USING ERRCODE = 'P0001';
    END IF;
    IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
        RAISE EXCEPTION 'Enter the counted birds for at least one flock.' USING ERRCODE = 'P0001';
    END IF;

    -- The farm's Birds item (the one a single bird movement posts against).
    SELECT p.poultryproductid INTO v_birds FROM poultryproducts p
    WHERE  p.farmid = p_farmid AND (COALESCE(p.isbirdproduct, FALSE) OR p.name = 'Birds') AND p.systemrole IS NULL
    ORDER  BY p.isbirdproduct DESC NULLS LAST, p.poultryproductid LIMIT 1;
    IF v_birds IS NULL THEN
        RAISE EXCEPTION 'This company has no Birds item yet.' USING ERRCODE = 'P0001';
    END IF;

    -- One count at a time per farm, so two people cannot both apply a change.
    PERFORM pg_advisory_xact_lock(hashtext('poultry-msm:' || p_farmid));

    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
        v_flockid := NULLIF(v_line->>'flockId', '')::integer;
        v_counted := NULLIF(v_line->>'countedBirds', '')::numeric;
        v_shown   := NULLIF(v_line->>'currentBirds', '')::numeric;
        CONTINUE WHEN v_counted IS NULL;            -- a flock left blank is not counted

        IF v_flockid IS NULL THEN
            RAISE EXCEPTION 'Every counted line needs its flock.' USING ERRCODE = 'P0001';
        END IF;
        IF v_flockid = ANY (v_seen) THEN
            RAISE EXCEPTION 'A flock is listed twice.' USING ERRCODE = 'P0001';
        END IF;
        v_seen := v_seen || v_flockid;

        SELECT f.flockid, f.name::text AS name, f.batchid INTO v_flock FROM flock f
        WHERE  f.flockid = v_flockid AND f.farmid = p_farmid AND NOT f.isdeleted;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That flock does not belong to this company.' USING ERRCODE = 'P0001';
        END IF;
        IF v_flock.batchid IS DISTINCT FROM p_batchid THEN
            RAISE EXCEPTION 'Flock "%" is not part of batch %.', v_flock.name, v_batch.batchcode USING ERRCODE = 'P0001';
        END IF;
        IF v_counted < 0 OR v_counted <> trunc(v_counted) THEN
            RAISE EXCEPTION 'Flock "%": the counted birds must be a whole number, 0 or more.', v_flock.name USING ERRCODE = 'P0001';
        END IF;

        SELECT bp.currentlivebirds INTO v_now FROM fnflock_birdposition(p_farmid, v_flockid) bp;
        v_now := COALESCE(v_now, 0);
        IF v_shown IS NOT NULL AND v_shown <> v_now THEN
            RAISE EXCEPTION 'Flock "%" now has % birds, not % as shown. Reload and enter the count again.',
                  v_flock.name, v_now, trim_scale(v_shown) USING ERRCODE = 'P0001';
        END IF;

        v_change := v_counted::integer - v_now;
        v_before := v_before + v_now;
        v_after  := v_after + v_counted::integer;

        IF v_change <> 0 THEN
            v_res := sppoultrymanualmovement_post(
                p_farmid => p_farmid, p_poultryproductid => v_birds, p_rawmaterialitemid => NULL,
                p_movementtype => CASE WHEN v_change > 0 THEN 'Increase' ELSE 'Decrease' END,
                p_quantity => abs(v_change), p_unitcost => NULL, p_batchid => p_batchid, p_flockid => v_flockid,
                p_effectivedate => p_effectivedate, p_reason => 'Stock Count Correction', p_disposition => NULL,
                p_note => concat_ws(' - ', 'Batch bird count: ' || v_counted::integer || ' counted, was ' || v_now, v_note),
                p_requestkey => CASE WHEN v_key IS NOT NULL THEN v_key || ':' || v_flockid END,
                p_by => p_by, p_scope => 'Flock');
            v_posted := v_posted + 1;
        ELSE
            v_res := NULL;
        END IF;

        v_out := v_out || jsonb_build_object(
            'flockId', v_flockid, 'flockName', v_flock.name, 'before', v_now,
            'counted', v_counted::integer, 'change', v_change, 'movementNo', v_res->>'movementNo');
    END LOOP;

    IF v_posted = 0 THEN
        RAISE EXCEPTION 'Every count matches the birds now, so there is nothing to adjust.' USING ERRCODE = 'P0001';
    END IF;

    RETURN jsonb_build_object(
        'repeated', FALSE, 'batchId', p_batchid, 'posted', v_posted,
        'totalBefore', v_before, 'totalAfter', v_after, 'movements', v_out,
        'farmLiveBirds', fnpoultry_farmlivebirds(p_farmid));
END
$function$;

COMMIT;

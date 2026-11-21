-- 468: Tag several animals at once.
--
-- splivestockanimal_savemany registers a list of tagged animals into ONE group
-- in one go. Every row goes through splivestockanimal_save (458), so the rules
-- are exactly the single-tag rules: unique tag, right parents, and -- when the
-- animals are already counted in the group -- no more tags than untagged head.
--
-- All or nothing: one bad row and no tag is saved. The error names the tag so
-- the farmer knows which row to fix.
--
-- p_animals: { groupId, addsToHead, source, acquiredDate, purchaseCost,
--              animals: [ { tagNumber, name, sex, breed, birthDate, notes }, ... ] }
-- The shared fields apply to every row; a row's own value wins where it has one.
-- Returns the new animal ids in row order.
-- Safe to re-run.

BEGIN;

CREATE OR REPLACE FUNCTION public.splivestockanimal_savemany(p_farmid text, p_animals jsonb, p_by text)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    v_rows   jsonb := COALESCE(p_animals->'animals', '[]'::jsonb);
    v_shared jsonb := p_animals - 'animals' - 'animalId';
    v_row    jsonb;
    v_tag    text;
    v_ids    jsonb := '[]'::jsonb;
    v_dup    text;
BEGIN
    IF jsonb_typeof(v_rows) <> 'array' OR jsonb_array_length(v_rows) = 0 THEN
        RAISE EXCEPTION 'Add at least one tag.' USING ERRCODE = 'P0001';
    END IF;
    IF jsonb_array_length(v_rows) > 500 THEN
        RAISE EXCEPTION 'Tag at most 500 animals at a time.' USING ERRCODE = 'P0001';
    END IF;

    -- The same tag twice in the list.
    SELECT min(btrim(r->>'tagNumber')) INTO v_dup
      FROM jsonb_array_elements(v_rows) r
     WHERE btrim(COALESCE(r->>'tagNumber', '')) <> ''
     GROUP BY lower(btrim(r->>'tagNumber'))
    HAVING count(*) > 1
     LIMIT 1;
    IF v_dup IS NOT NULL THEN
        RAISE EXCEPTION 'Tag % is in the list more than once.', v_dup USING ERRCODE = 'P0001';
    END IF;

    FOR v_row IN SELECT value FROM jsonb_array_elements(v_rows) LOOP
        v_tag := btrim(COALESCE(v_row->>'tagNumber', ''));
        BEGIN
            v_ids := v_ids || to_jsonb(public.splivestockanimal_save(
                p_farmid,
                v_shared || jsonb_strip_nulls(v_row - 'animalId' - 'groupId' - 'addsToHead'),
                p_by));
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            IF v_tag = '' OR position(lower(v_tag) IN lower(SQLERRM)) > 0 THEN RAISE; END IF;
            RAISE EXCEPTION 'Tag %: %', v_tag, SQLERRM USING ERRCODE = 'P0001';
        END;
    END LOOP;
    RETURN v_ids;
END
$f$;

COMMIT;

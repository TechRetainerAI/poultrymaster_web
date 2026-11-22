-- 472: Tag several animals -- a parent can be another animal in the same list.
--
-- When a whole herd is tagged for the first time, the mothers and fathers are
-- being tagged in the same sitting as their young. A row may now name its
-- parent by tag with damTag / sireTag instead of damId / sireId, pointing at
-- another row of the same list. Parents are saved first, then the rows that
-- point at them, so every row still goes through splivestockanimal_save (458)
-- with a real damId / sireId and keeps all its checks (same kind, right sex,
-- born before the young one).
--
-- Still all or nothing. A damTag / sireTag that is not in the list, or rows
-- that are each other's parents, are refused with the tag named.
-- Returns the new animal ids in the order the rows were sent.
-- Replaces the 468 function. Safe to re-run.

BEGIN;

CREATE OR REPLACE FUNCTION public.splivestockanimal_savemany(p_farmid text, p_animals jsonb, p_by text)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    v_rows    jsonb := COALESCE(p_animals->'animals', '[]'::jsonb);
    v_shared  jsonb := p_animals - 'animals' - 'animalId';
    v_n       integer;
    v_row     jsonb;
    v_tag     text;
    v_dup     text;
    v_ref     text;
    v_tags    text[] := '{}';                 -- lower(tag) of every row, by position
    v_ids     integer[];                      -- new ids, by position (NULL = not saved yet)
    v_byTag   jsonb := '{}'::jsonb;           -- lower(tag) -> new id
    v_damTag  text;
    v_sireTag text;
    v_progress boolean;
    i         integer;
BEGIN
    IF jsonb_typeof(v_rows) <> 'array' OR jsonb_array_length(v_rows) = 0 THEN
        RAISE EXCEPTION 'Add at least one tag.' USING ERRCODE = 'P0001';
    END IF;
    v_n := jsonb_array_length(v_rows);
    IF v_n > 500 THEN
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

    FOR i IN 0 .. v_n - 1 LOOP
        v_tags := v_tags || lower(btrim(COALESCE(v_rows->i->>'tagNumber', '')));
    END LOOP;
    v_ids := array_fill(NULL::integer, ARRAY[v_n]);

    -- Every parent named by tag must be another row of this list.
    FOR i IN 0 .. v_n - 1 LOOP
        v_tag := btrim(COALESCE(v_rows->i->>'tagNumber', ''));
        FOREACH v_ref IN ARRAY ARRAY[NULLIF(btrim(v_rows->i->>'damTag'), ''), NULLIF(btrim(v_rows->i->>'sireTag'), '')] LOOP
            CONTINUE WHEN v_ref IS NULL;
            IF lower(v_ref) = lower(v_tag) THEN
                RAISE EXCEPTION 'Tag %: an animal cannot be its own parent.', v_tag USING ERRCODE = 'P0001';
            END IF;
            IF NOT lower(v_ref) = ANY (v_tags) THEN
                RAISE EXCEPTION 'Tag %: parent % is not in this list.', v_tag, v_ref USING ERRCODE = 'P0001';
            END IF;
        END LOOP;
    END LOOP;

    -- Save in passes: a row is saved once the rows it names as parents are.
    LOOP
        v_progress := FALSE;
        FOR i IN 0 .. v_n - 1 LOOP
            CONTINUE WHEN v_ids[i + 1] IS NOT NULL;
            v_row     := v_rows->i;
            v_tag     := btrim(COALESCE(v_row->>'tagNumber', ''));
            v_damTag  := lower(NULLIF(btrim(v_row->>'damTag'), ''));
            v_sireTag := lower(NULLIF(btrim(v_row->>'sireTag'), ''));
            CONTINUE WHEN (v_damTag IS NOT NULL AND NOT v_byTag ? v_damTag)
                       OR (v_sireTag IS NOT NULL AND NOT v_byTag ? v_sireTag);

            v_row := v_row - 'animalId' - 'groupId' - 'addsToHead' - 'damTag' - 'sireTag';
            IF v_damTag IS NOT NULL THEN v_row := v_row || jsonb_build_object('damId', (v_byTag->>v_damTag)::int); END IF;
            IF v_sireTag IS NOT NULL THEN v_row := v_row || jsonb_build_object('sireId', (v_byTag->>v_sireTag)::int); END IF;

            BEGIN
                v_ids[i + 1] := public.splivestockanimal_save(p_farmid, v_shared || jsonb_strip_nulls(v_row), p_by);
            EXCEPTION WHEN SQLSTATE 'P0001' THEN
                IF v_tag = '' OR position(lower(v_tag) IN lower(SQLERRM)) > 0 THEN RAISE; END IF;
                RAISE EXCEPTION 'Tag %: %', v_tag, SQLERRM USING ERRCODE = 'P0001';
            END;
            IF v_tag <> '' THEN v_byTag := v_byTag || jsonb_build_object(lower(v_tag), v_ids[i + 1]); END IF;
            v_progress := TRUE;
        END LOOP;
        EXIT WHEN array_position(v_ids, NULL) IS NULL;
        IF NOT v_progress THEN
            SELECT btrim(v_rows->(p - 1)->>'tagNumber') INTO v_tag
              FROM generate_subscripts(v_ids, 1) p WHERE v_ids[p] IS NULL LIMIT 1;
            RAISE EXCEPTION 'Tag %: its mother or father is also its own young in this list.', v_tag USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    RETURN to_jsonb(v_ids);
END
$f$;

COMMIT;

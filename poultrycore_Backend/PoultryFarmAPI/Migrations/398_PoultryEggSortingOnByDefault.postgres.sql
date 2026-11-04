-- 398: Egg sorting is ON by default (2026-11-03).
--
-- Until now a farm that had never touched the setting read as OFF. From here a
-- farm that has not chosen reads as ON:
--   * no settings row at all                       -> on (the getter's fallback)
--   * a row created by saving packaging first      -> on (packaging_save used to
--     insert FALSE, which silently turned sorting off for that farm)
--   * a save that leaves the switch unspecified    -> on
--
-- What does NOT change: a farm that has a row keeps its value. On dev the
-- three farms that read OFF today each switched it on and later off
-- themselves (poultryeggsortingaudit), so that choice is respected.
--
-- Egg sizes: turning sorting on normally seeds the default sizes
-- (sppoultryeggsizes_ensure). A farm that is on by default gets them the first
-- time it opens Egg Sorting, its settings page, or New Sale -- each of those
-- loads classes with ensure = enableEggSorting / true.
--
-- Daily Closing's "unsorted eggs" rule defaults to Warning, so farms that
-- never sort will now see that warning (not a block) while eggs sit unsorted.
--
-- The four functions are rewritten from their LIVE definitions, not from older
-- migration files, so nothing else in their bodies moves. Each replacement must
-- match exactly once or the migration stops. Idempotent: a re-run finds the
-- already-replaced text and skips it.

ALTER TABLE poultryeggsortingsettings ALTER COLUMN enableeggsorting SET DEFAULT TRUE;

DO $mig$
DECLARE
    edits text[][] := ARRAY[
        -- function, old text, new text
        ARRAY['sppoultryeggsortingsettings_get',
              'COALESCE(s.enableeggsorting, FALSE)',
              'COALESCE(s.enableeggsorting, TRUE)'],
        ARRAY['sppoultryeggsortingsettings_save',
              'COALESCE(p_enableeggsorting, FALSE)',
              'COALESCE(p_enableeggsorting, TRUE)'],
        ARRAY['sppoultryeggsortingsettings_set',
              'COALESCE(p_enableeggsorting, FALSE)',
              'COALESCE(p_enableeggsorting, TRUE)'],
        ARRAY['sppoultryeggpackaging_save',
              'VALUES (p_farmid, FALSE, ''Warning'', 30,',
              'VALUES (p_farmid, TRUE, ''Warning'', 30,']
    ];
    i      int;
    v_def  text;
    v_new  text;
    v_hits int;
BEGIN
    FOR i IN 1 .. array_length(edits, 1) LOOP
        SELECT pg_get_functiondef(p.oid) INTO v_def
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public' AND p.proname = edits[i][1];

        IF v_def IS NULL THEN
            RAISE EXCEPTION '398: function % not found.', edits[i][1];
        END IF;

        IF position(edits[i][2] IN v_def) = 0 THEN
            IF position(edits[i][3] IN v_def) > 0 THEN
                RAISE NOTICE '398: % already on by default, skipped.', edits[i][1];
                CONTINUE;
            END IF;
            RAISE EXCEPTION '398: % does not contain the expected text: %', edits[i][1], edits[i][2];
        END IF;

        v_hits := (length(v_def) - length(replace(v_def, edits[i][2], ''))) / length(edits[i][2]);
        v_new  := replace(v_def, edits[i][2], edits[i][3]);
        EXECUTE v_new;
        RAISE NOTICE '398: % updated (% place(s)).', edits[i][1], v_hits;
    END LOOP;
END
$mig$;

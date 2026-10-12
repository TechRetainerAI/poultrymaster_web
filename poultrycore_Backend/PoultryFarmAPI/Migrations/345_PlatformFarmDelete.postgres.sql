-- 345: platform_delete_farm — full purge of one farm for the admin portal.
--
-- Deletes the farm's rows from EVERY public table that has a farmid column,
-- then the farms row itself. Order-independent: runs up to 12 passes, skipping
-- tables whose children still hold rows (foreign_key_violation) until the
-- graph drains. Identity tables (aspnet*) are never touched — org-wide
-- employee accounts may span several farms (Business Office), so only their
-- userfarms links go. Runs in the caller's transaction: all or nothing.

CREATE OR REPLACE FUNCTION platform_delete_farm(p_farmid uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_name text;
    v_tbl record;
    v_deleted bigint;
    v_total bigint := 0;
    v_tables int := 0;
    v_pass int;
    v_blocked int;
BEGIN
    SELECT farmname INTO v_name FROM farms WHERE farmid = p_farmid;
    IF v_name IS NULL THEN
        RAISE EXCEPTION 'Farm % does not exist', p_farmid USING ERRCODE = 'no_data_found';
    END IF;

    CREATE TEMP TABLE IF NOT EXISTS _farm_purge (tbl text PRIMARY KEY, done boolean DEFAULT false) ON COMMIT DROP;
    DELETE FROM _farm_purge;

    INSERT INTO _farm_purge (tbl)
    SELECT c.table_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
    WHERE c.table_schema = 'public'
      AND lower(c.column_name) = 'farmid'
      AND lower(c.table_name) <> 'farms'
      AND lower(c.table_name) NOT LIKE 'aspnet%';

    FOR v_pass IN 1..12 LOOP
        v_blocked := 0;
        FOR v_tbl IN SELECT tbl FROM _farm_purge WHERE NOT done LOOP
            BEGIN
                EXECUTE format('DELETE FROM %I WHERE farmid = $1', v_tbl.tbl) USING p_farmid;
                GET DIAGNOSTICS v_deleted = ROW_COUNT;
                UPDATE _farm_purge SET done = true WHERE tbl = v_tbl.tbl;
                IF v_deleted > 0 THEN
                    v_total := v_total + v_deleted;
                    v_tables := v_tables + 1;
                END IF;
            EXCEPTION WHEN foreign_key_violation THEN
                v_blocked := v_blocked + 1;  -- a child table still holds rows; retry next pass
            END;
        END LOOP;
        EXIT WHEN v_blocked = 0;
    END LOOP;

    IF EXISTS (SELECT 1 FROM _farm_purge WHERE NOT done) THEN
        RAISE EXCEPTION 'Farm purge for % could not drain tables: %', p_farmid,
            (SELECT string_agg(tbl, ', ') FROM _farm_purge WHERE NOT done);
    END IF;

    DELETE FROM farms WHERE farmid = p_farmid;

    RETURN format('Deleted farm "%s": %s rows across %s tables (plus the farm itself).',
                  v_name, v_total, v_tables);
END;
$$;

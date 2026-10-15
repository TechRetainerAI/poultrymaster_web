-- =============================================================================
-- daily-closing-history-figures.test.sql -- checks for migration 365.
--
-- Read-only and ROLLED BACK: safe to run bare (psql -f).
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    r       record;
    v_rows  integer := 0;
    v_ws    jsonb;
BEGIN
    FOR r IN SELECT DISTINCT c.farmid FROM poultrydailyclosings c LOOP
        -- 1. Every row has figures.
        IF EXISTS (SELECT 1 FROM public.sppoultrydailyclosing_history(r.farmid) h
                   WHERE h.revenue IS NULL OR h.salescount IS NULL OR h.netcashflow IS NULL) THEN
            RAISE EXCEPTION 'FAIL % has a history row without figures', r.farmid;
        END IF;
        v_rows := v_rows + (SELECT count(*) FROM public.sppoultrydailyclosing_history(r.farmid));
    END LOOP;
    RAISE NOTICE 'ok 1 every history row has figures (% rows)', v_rows;

    -- 2. A closed day reads its snapshot; any other day reads the live workspace.
    FOR r IN
        SELECT c.farmid, c.closingdate, c.status, c.closingsnapshot, h.islive, h.revenue, h.creditsales
        FROM   poultrydailyclosings c
        JOIN   LATERAL public.sppoultrydailyclosing_history(c.farmid, c.closingdate, c.closingdate) h ON TRUE
    LOOP
        IF r.status = 'Approved' AND r.closingsnapshot IS NOT NULL THEN
            v_ws := r.closingsnapshot;
            IF r.islive THEN RAISE EXCEPTION 'FAIL closed day % % read live', r.farmid, r.closingdate; END IF;
        ELSE
            v_ws := public.sppoultrydailyclosing_workspace(r.farmid, r.closingdate);
            IF NOT r.islive THEN RAISE EXCEPTION 'FAIL open day % % not live', r.farmid, r.closingdate; END IF;
        END IF;
        IF r.revenue IS DISTINCT FROM (v_ws->'sales'->>'revenue')::numeric
           OR r.creditsales IS DISTINCT FROM (v_ws->'sales'->>'creditSales')::numeric THEN
            RAISE EXCEPTION 'FAIL figures differ for % %', r.farmid, r.closingdate;
        END IF;
    END LOOP;
    RAISE NOTICE 'ok 2 closed days as closed, other days live';

    RAISE NOTICE 'daily closing history figures: all checks passed';
END $$;

ROLLBACK;

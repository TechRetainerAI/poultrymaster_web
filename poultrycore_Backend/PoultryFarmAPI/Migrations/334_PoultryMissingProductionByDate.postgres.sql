-- =============================================================================
-- 334_PoultryMissingProductionByDate.postgres.sql
--
-- Purpose
-- -------
-- Every (date, flock) with no production record in a recent window, for the
-- WHOLE farm -- the "By date" view on Farm Completeness. When nobody entered
-- anything on the 12th, eight flocks are missing that same day, and the fix is
-- one Batch Production Entry for the 12th, not eight single forms. Grouping
-- these rows by date is what lets the page offer exactly that.
--
-- Depends on 332. Eligibility and expected-from are NOT re-derived here: each
-- flock's row from sppoultryactivity_productioncompleteness supplies both, so
-- this, the per-flock list (sppoultryactivity_flockmissingdates) and the
-- headline count can never disagree about which days a flock owed.
--
-- Days already in an unposted batch entry are returned with that batch, so the
-- page can say "post batch #44" instead of offering a second entry.
--
-- Read-only. Idempotent. Safe to run more than once.
-- EFFECT ON TODAY'S NUMBERS: none.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

DROP FUNCTION IF EXISTS public.sppoultryactivity_missingproductionbydate(text, date, integer, timestamptz);

CREATE FUNCTION public.sppoultryactivity_missingproductionbydate(
    p_farmid       text,
    p_businessdate date        DEFAULT NULL,
    p_days         integer     DEFAULT 30,
    p_asof         timestamptz DEFAULT now())
RETURNS TABLE(
    businessdate         date,
    missingdate          date,
    flockid              integer,
    flockname            text,
    batchname            text,
    housename            text,
    pendingbatchrecordid integer,
    pendingbatchstatus   text)
LANGUAGE plpgsql
STABLE
AS $function$
#variable_conflict use_column
DECLARE
    v_days integer := LEAST(GREATEST(COALESCE(p_days, 30), 1), 366);
BEGIN
    RETURN QUERY
    WITH f AS (
        -- Raises for a future business date; returns only eligible flocks.
        SELECT * FROM public.sppoultryactivity_productioncompleteness(p_farmid, p_businessdate, p_asof)
    )
    SELECT f.businessdate, g.d::date, f.flockid, f.flockname, f.batchname, f.housename,
           pend.id, pend.status::text
    FROM   f
    CROSS  JOIN LATERAL generate_series(GREATEST(f.expectedfrom, f.businessdate - (v_days - 1)),
                                        f.businessdate, interval '1 day') g(d)
    LEFT   JOIN LATERAL (
        SELECT r.id, r.status
        FROM   productionbatchrecords r
        JOIN   productionbatchincludedflocks i ON i.productionbatchrecordid = r.id
        WHERE  r.farmid = p_farmid
          AND  r.productiondate = g.d::date
          AND  i.flockid = f.flockid
          AND  r.status IN ('Draft', 'PendingAllocation', 'Allocated')
        ORDER  BY r.id DESC
        LIMIT  1
    ) pend ON TRUE
    WHERE  NOT EXISTS (SELECT 1 FROM productionrecords pr
                       WHERE pr.farmid = p_farmid AND pr.flockid = f.flockid AND pr.date = g.d::date)
    ORDER  BY g.d DESC, f.batchname NULLS LAST, f.housename NULLS LAST, f.flockname, f.flockid;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification. Fixtures are rolled back by the sentinel at the end.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    a      text := '__334_selftest_a__';
    b      text := '__334_selftest_b__';
    t_day  timestamptz := '2026-03-10 10:00:00+00';   -- 23:00 on the 10th in Auckland
    d      date := date '2026-03-10';
    v_created timestamp := timestamp '2026-01-01 08:00';
    f1 integer; f2 integer; f3 integer; fb integer; v_pbr integer;
    v_n integer;
BEGIN
    BEGIN
        INSERT INTO farms (id, farmid, name, email, type, timezoneid)
        VALUES (a, a, 'Selftest A', 'a@selftest.invalid', 'Poultry', 'Pacific/Auckland'),
               (b, b, 'Selftest B', 'b@selftest.invalid', 'Poultry', 'Pacific/Auckland');

        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__334__', a, 'F1', d - 30, 'Brown', 100, TRUE, TRUE, -334, v_created) RETURNING flockid INTO f1;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__334__', a, 'F2', d - 30, 'Brown', 100, TRUE, TRUE, -334, v_created) RETURNING flockid INTO f2;
        -- Started only two days ago: owes nothing before d-2.
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__334__', a, 'F3', d - 2, 'Brown', 100, TRUE, TRUE, -334, v_created) RETURNING flockid INTO f3;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__334__', b, 'B1', d - 30, 'Brown', 100, TRUE, TRUE, -334, v_created) RETURNING flockid INTO fb;

        -- F1 recorded on d-1 only; F2 recorded on d only.
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
                                       noofbirdsleft, feedkg, production9am, production12pm, production4pm,
                                       totalproduction, flockid, sourcetype, createdat)
        VALUES (a, '__334__', '__334__', 10, 70, d - 1, 100, 0, 100, 0, 1, 1, 1, 3, f1, 'ManualSingleFlock', now()),
               (a, '__334__', '__334__', 10, 70, d,     100, 0, 100, 0, 1, 1, 1, 3, f2, 'ManualSingleFlock', now());

        -- F3's d-2 is sitting in an unposted batch.
        INSERT INTO productionbatchrecords (farmid, batchselectiontype, productiondate, status)
        VALUES (a, 'CustomBatch', d - 2, 'PendingAllocation') RETURNING id INTO v_pbr;
        INSERT INTO productionbatchincludedflocks (productionbatchrecordid, flockid, flockname)
        VALUES (v_pbr, f3, 'F3');

        -- 3-day window (d-2 .. d):
        --   d   : F1, F3            (F2 recorded)
        --   d-1 : F2, F3            (F1 recorded)
        --   d-2 : F1, F2, F3 (F3 in batch)
        SELECT count(*) INTO v_n FROM public.sppoultryactivity_missingproductionbydate(a, NULL, 3, t_day);
        IF v_n <> 7 THEN
            RAISE EXCEPTION '334: expected 7 missing (date, flock) pairs, got %.', v_n;
        END IF;
        IF (SELECT array_agg(x.flockid ORDER BY x.flockname) FROM public.sppoultryactivity_missingproductionbydate(a, NULL, 3, t_day) x
            WHERE x.missingdate = d) <> ARRAY[f1, f3] THEN
            RAISE EXCEPTION '334: wrong flocks missing on the business date.';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.sppoultryactivity_missingproductionbydate(a, NULL, 3, t_day) x
                       WHERE x.missingdate = d - 2 AND x.flockid = f3 AND x.pendingbatchrecordid = v_pbr) THEN
            RAISE EXCEPTION '334: the unposted batch was not reported on its date.';
        END IF;
        -- F3 started on d-2, so a wider window adds nothing for it.
        IF (SELECT count(*) FROM public.sppoultryactivity_missingproductionbydate(a, NULL, 30, t_day) x WHERE x.flockid = f3) <> 3 THEN
            RAISE EXCEPTION '334: listed days before a flock started.';
        END IF;
        -- Agrees with the per-flock list (332) for every flock.
        IF EXISTS (
            SELECT x.missingdate FROM public.sppoultryactivity_missingproductionbydate(a, NULL, 30, t_day) x WHERE x.flockid = f1
            EXCEPT
            SELECT y.missingdate FROM public.sppoultryactivity_flockmissingdates(a, f1, NULL, 30, t_day) y) THEN
            RAISE EXCEPTION '334: disagrees with sppoultryactivity_flockmissingdates.';
        END IF;
        -- Company isolation.
        IF EXISTS (SELECT 1 FROM public.sppoultryactivity_missingproductionbydate(a, NULL, 30, t_day) x WHERE x.flockid = fb) THEN
            RAISE EXCEPTION '334: another company''s flock was listed.';
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '__334_ok__';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;
    END;

    RAISE NOTICE '334_PoultryMissingProductionByDate: 1 function, verified (window, batch-pending, start date, agreement with 332, isolation).';
END $$;

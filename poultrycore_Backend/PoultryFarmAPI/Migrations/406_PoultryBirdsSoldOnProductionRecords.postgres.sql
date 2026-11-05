-- =============================================================================
-- 406_PoultryBirdsSoldOnProductionRecords.postgres.sql      (requires 352)
--
-- Purpose
-- -------
-- Selling birds did not reach the production record. A flock of 100 sold 70,
-- and the next production record still opened with 100: the form starts from
-- the last record's birds left, and birds left is only birds - mortality.
-- Laying % and every reader of noofbirdsleft (flock list, dashboard, birds on
-- hand, closeout, per-bird feed) kept counting the sold birds.
--
-- Only fnflock_birdposition (352) took sales off, and it took off EVERY bird
-- sale ever, on the assumption that no record reflects any. So a record that
-- simply opened with 30 would have been read as 30 - 70 = -40.
--
-- THE MARKER
-- ----------
-- productionrecords.birdssoldreflected = how many of the flock's sold birds
-- (posted bird sales dated on or before the record) this record's count
-- already allows for.
--   * Worked out on insert from the count itself: a count exactly equal to the
--     previous birds left was carried forward and inherits the previous marker;
--     any other count (the web form, batch production and the mobile app now
--     open at last birds left - birds sold since; or a hand count) reflects
--     every sale up to its day. So every insert path is right, old clients too.
--   * The web form also says so explicitly (spproductionrecord_setbirdssoldreflected
--     via the API); an explicit value wins.
--   * NULL on every record before this migration = 0 = what they mean today.
--
-- fnflock_birdposition now takes off only the sales the latest record does
-- not already allow for:
--     current live = last birds left - (birds sold - marker) - culled - transferred
-- For every existing flock the marker is 0, so its figure is unchanged.
-- A reversed sale drops "birds sold" below the marker and gives the birds back.
--
-- fnflock_birdsondate(farm, flock, date) is the one definition of what a new
-- record for that day should open with. The API serves it to the form.
--
-- Deploy order: this migration, then the API, then the web app. The API probes
-- for the setter (like the 4th-pick one) and the form falls back to the old
-- carry-forward when the reader endpoint is missing, so any order is safe.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

-- The position below is 352's body plus the marker. If the live function has
-- since been changed by something not in this repo, stop rather than
-- overwrite it -- re-base this migration on pg_get_functiondef() first.
DO $$
DECLARE v_def text;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'fnflock_birdposition';
    IF v_def IS NULL THEN
        RAISE EXCEPTION '406: fnflock_birdposition is missing -- apply 352 first.';
    END IF;
    IF v_def NOT LIKE '%birdssoldreflected%' AND (
           v_def NOT LIKE '%GREATEST(COALESCE(lr.c_left, f.c_quantity), 0) - s.c_sold - d.c_culled - d.c_transferred%'
        OR v_def NOT LIKE '%flockcloseoutdispositions%') THEN
        RAISE EXCEPTION '406: the live fnflock_birdposition is not the 352 body this migration replaces. Re-base it first.';
    END IF;
END $$;

ALTER TABLE public.productionrecords ADD COLUMN IF NOT EXISTS birdssoldreflected integer;

-- ---- Birds sold out of a flock, posted, dated on or before a day --------------
CREATE OR REPLACE FUNCTION public.fnflock_birdssoldto(p_farmid text, p_flockid integer, p_date date)
RETURNS integer
LANGUAGE sql
STABLE
AS $function$
    SELECT COALESCE(ROUND(SUM(sa.quantity)), 0)::int
    FROM   sale sa
    WHERE  sa.status = 'Posted' AND sa.farmid = p_farmid AND sa.flockid = p_flockid
      AND  fnpoultrysale_isbirdsale(sa.product)
      AND  (p_date IS NULL OR sa.saledate::date <= p_date);
$function$;

-- ---- Set the marker on insert, from the count itself -------------------------
-- A count EXACTLY equal to the previous birds left (or, for a flock's first
-- record, its placed quantity) was carried forward: it allows for no new
-- sales, so it inherits the previous marker. Any other count was recomputed or
-- counted, and a real count already reflects every sale up to its day, so it
-- takes all of them. This makes every insert path right -- the web form, batch
-- posting, feed-only records, the mobile app, and older versions of each --
-- without any of them having to say anything. An explicit value (the API's
-- setter) wins.
CREATE OR REPLACE FUNCTION public.trg_productionrecords_birdssoldreflected()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_found boolean;
    v_base  integer;
    v_refl  integer;
BEGIN
    IF NEW.birdssoldreflected IS NULL AND NEW.flockid IS NOT NULL THEN
        SELECT TRUE, COALESCE(r.noofbirdsleft, 0), COALESCE(r.birdssoldreflected, 0)
        INTO   v_found, v_base, v_refl
        FROM   productionrecords r
        WHERE  r.farmid = NEW.farmid AND r.flockid = NEW.flockid AND r.date <= NEW.date
        ORDER  BY r.date DESC, r.id DESC
        LIMIT  1;
        IF NOT COALESCE(v_found, FALSE) THEN
            SELECT COALESCE(f.quantity, 0) INTO v_base FROM flock f WHERE f.flockid = NEW.flockid AND f.farmid = NEW.farmid;
            v_refl := 0;
        END IF;

        IF COALESCE(NEW.noofbirds, 0) = COALESCE(v_base, 0) THEN
            NEW.birdssoldreflected := v_refl;
        ELSE
            NEW.birdssoldreflected := public.fnflock_birdssoldto(NEW.farmid, NEW.flockid, NEW.date::date);
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS tr_productionrecords_birdssoldreflected ON public.productionrecords;
CREATE TRIGGER tr_productionrecords_birdssoldreflected
    BEFORE INSERT ON public.productionrecords
    FOR EACH ROW EXECUTE FUNCTION public.trg_productionrecords_birdssoldreflected();

-- ---- The form says how many sold birds its count took off --------------------
CREATE OR REPLACE FUNCTION public.spproductionrecord_setbirdssoldreflected(p_recordid integer, p_farmid text, p_birdssoldreflected integer)
RETURNS void
LANGUAGE sql
AS $function$
    UPDATE productionrecords
    SET    birdssoldreflected = GREATEST(COALESCE(p_birdssoldreflected, 0), 0)
    WHERE  id = p_recordid AND farmid = p_farmid;
$function$;

-- ---- What a new record for a flock-day should open with ----------------------
DROP FUNCTION IF EXISTS public.fnflock_birdsondate(text, integer, date, integer);
CREATE FUNCTION public.fnflock_birdsondate(p_farmid text, p_flockid integer, p_date date, p_excluderecordid integer DEFAULT NULL)
RETURNS TABLE (
    previousrecordid   integer,
    previousrecorddate date,
    previousbirdsleft  integer,
    previousreflected  integer,
    birdssoldtodate    integer,
    birdssoldsince     integer,
    birds              integer
)
LANGUAGE sql
STABLE
AS $function$
    WITH prev AS (
        SELECT r.id, r.date::date AS d, COALESCE(r.noofbirdsleft, 0) AS left_, COALESCE(r.birdssoldreflected, 0) AS refl
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.flockid = p_flockid AND r.date < p_date
          AND  (p_excluderecordid IS NULL OR r.id <> p_excluderecordid)
        ORDER  BY r.date DESC, r.id DESC
        LIMIT  1
    ),
    base AS (
        SELECT (SELECT id FROM prev) AS id,
               (SELECT d FROM prev) AS d,
               COALESCE((SELECT left_ FROM prev),
                        (SELECT COALESCE(f.quantity, 0) FROM flock f WHERE f.farmid = p_farmid AND f.flockid = p_flockid)) AS left_,
               COALESCE((SELECT refl FROM prev), 0) AS refl,
               public.fnflock_birdssoldto(p_farmid, p_flockid, p_date) AS sold
    )
    SELECT b.id, b.d, b.left_, b.refl, b.sold, b.sold - b.refl, GREATEST(b.left_ - (b.sold - b.refl), 0)
    FROM   base b;
$function$;

-- ---- The bird position: only the sales the latest record does not allow for --
-- Body as 352, with the marker read off the latest record and used in the
-- current-live sum. Signature unchanged.
CREATE OR REPLACE FUNCTION public.fnflock_birdposition(p_farmid text, p_flockid integer)
 RETURNS TABLE(flockid integer, hasopeningposition boolean, historyknown boolean, originallyplaced integer, openingmortality integer, openingsold integer, openingculled integer, openingtransferred integer, openingother integer, openinglivebirds integer, recordedmortality integer, productionrecordcount integer, lastcountedbirds integer, lastcountdate date, correction integer, birdssold integer, birdsculled integer, birdstransferred integer, currentlivebirds integer)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    WITH f AS (
        SELECT fl.flockid AS c_flockid, COALESCE(fl.quantity, 0) AS c_quantity
        FROM   flock fl
        WHERE  fl.farmid = p_farmid AND fl.flockid = p_flockid
    ),
    o AS (
        SELECT op.*
        FROM   poultryopeningflockposition op
        WHERE  op.farmid = p_farmid AND op.flockid = p_flockid
        ORDER  BY op.openingpositionid DESC
        LIMIT  1
    ),
    pr AS (
        SELECT COALESCE(SUM(COALESCE(r.mortality, 0)), 0)::int AS c_mort,
               COUNT(*)::int                                    AS c_n
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.flockid = p_flockid
    ),
    lr AS (
        SELECT r.noofbirdsleft AS c_left, r.date AS c_date, COALESCE(r.birdssoldreflected, 0) AS c_refl
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.flockid = p_flockid
        ORDER  BY r.date DESC, r.id DESC
        LIMIT  1
    ),
    s AS (
        SELECT COALESCE(ROUND(SUM(sa.quantity)), 0)::int AS c_sold
        FROM   sale sa
        WHERE  sa.status = 'Posted' AND sa.farmid = p_farmid AND sa.flockid = p_flockid
          AND  fnpoultrysale_isbirdsale(sa.product)
    ),
    d AS (
        SELECT COALESCE(SUM(x.quantity) FILTER (WHERE x.disposition = 'Cull'), 0)::int     AS c_culled,
               COALESCE(SUM(x.quantity) FILTER (WHERE x.disposition = 'Transfer'), 0)::int AS c_transferred
        FROM   flockcloseoutdispositions x
        JOIN   flockcloseouts c ON c.closeoutid = x.closeoutid
        WHERE  x.farmid = p_farmid AND x.flockid = p_flockid
          AND  x.reversedat IS NULL AND c.reopenedat IS NULL
    )
    SELECT
        f.c_flockid,
        (o.openingpositionid IS NOT NULL),
        COALESCE(o.historyknown, TRUE),
        COALESCE(o.originallyplaced, f.c_quantity),
        COALESCE(o.historicalmortality, 0),
        COALESCE(o.historicalsold, 0),
        COALESCE(o.historicalculled, 0),
        COALESCE(o.historicaltransferred, 0),
        COALESCE(o.otheradjustment, 0),
        f.c_quantity,
        pr.c_mort,
        pr.c_n,
        GREATEST(COALESCE(lr.c_left, f.c_quantity), 0),
        lr.c_date,
        CASE WHEN lr.c_date IS NULL THEN 0
             ELSE GREATEST(COALESCE(lr.c_left, f.c_quantity), 0) - (f.c_quantity - pr.c_mort)
        END,
        s.c_sold,
        d.c_culled,
        d.c_transferred,
        GREATEST(COALESCE(lr.c_left, f.c_quantity), 0) - (s.c_sold - COALESCE(lr.c_refl, 0)) - d.c_culled - d.c_transferred
    FROM   f
    CROSS  JOIN pr
    CROSS  JOIN s
    CROSS  JOIN d
    LEFT   JOIN o  ON TRUE
    LEFT   JOIN lr ON TRUE;
END
$function$;

-- ---- Self-test (read only) ----------------------------------------------------
-- Runs against the first poultry flock that has a production record: the
-- position must be unchanged by this migration while every marker is 0/NULL.
DO $$
DECLARE
    v_farm text; v_flock int; v_live int; v_expect int;
BEGIN
    SELECT r.farmid, r.flockid INTO v_farm, v_flock
    FROM   productionrecords r WHERE r.flockid IS NOT NULL AND r.birdssoldreflected IS NULL
    ORDER  BY r.id LIMIT 1;
    IF v_farm IS NULL THEN RETURN; END IF;

    SELECT bp.currentlivebirds INTO v_live FROM public.fnflock_birdposition(v_farm, v_flock) bp;
    SELECT bp.lastcountedbirds - bp.birdssold - bp.birdsculled - bp.birdstransferred INTO v_expect
    FROM public.fnflock_birdposition(v_farm, v_flock) bp;
    IF v_live IS DISTINCT FROM v_expect THEN
        RAISE EXCEPTION '406: an unmarked flock''s live birds changed (% vs %).', v_live, v_expect;
    END IF;
    PERFORM * FROM public.fnflock_birdsondate(v_farm, v_flock, current_date);
END $$;

COMMIT;

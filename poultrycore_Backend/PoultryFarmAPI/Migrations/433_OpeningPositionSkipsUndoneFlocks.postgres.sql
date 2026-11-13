-- 433_OpeningPositionSkipsUndoneFlocks.postgres.sql
--
-- THE BUG
-- -------
-- Undoing an Initial Farm Setup (416/417) deletes its flocks through
-- sppoultryflock_delete, which is a SOFT delete (flock.isdeleted = TRUE). The
-- flock's opening history row in poultryopeningflockposition stays, and nothing
-- that summarises the opening position looked at isdeleted. So after an undo
-- and a redo, the "Opening Farm Position" section on /poultry-farm-setup
-- counted every flock twice -- once for the undone setup, once for the redo --
-- and listed duplicate rows ("B6 - Pen 10" twice).
--
-- Seen on Dev Test Farm: 7 live flocks (9,000 placed, 300 reduction) plus 4
-- undone ones (4,000 placed, 140 reduction) showed as 13,000 / 440.
--
-- The "Initial Farm Setup Completed" card above it had the same fault in a
-- different place: its bird figures are running totals in poultryfarmsetup,
-- added to on every completion (sppoultryfarmsetup_complete) and never taken
-- off by an undo (the reverse lowers the batch/house/flock COUNTS only).
--
-- THE FIX
-- -------
-- 1. sppoultryopeningposition_getall reads only rows whose flock still exists
--    and is not deleted. An undone flock's history is cancelled with it.
-- 2. sppoultryfarmsetup_get works its three bird figures out from those same
--    rows instead of the stored running totals, so the card and the list under
--    it can never disagree again. The stored columns are left as they are (the
--    completion still writes them); they are simply no longer what is shown.
--
-- Both are read-only changes: no row is changed or deleted, which is also why
-- it corrects farms that were undone BEFORE this migration with no repair step.
--
-- Idempotent: CREATE OR REPLACE with unchanged signatures.

BEGIN;

CREATE OR REPLACE FUNCTION public.sppoultryopeningposition_getall(p_farmid text)
 RETURNS TABLE(openingpositionid integer, farmid text, flockid integer, flockname text, batchid integer, houseid integer, effectivebusinessdate date, originallyplaced integer, openinglivebirds integer, historicalmortality integer, historicalsold integer, historicalculled integer, historicaltransferred integer, otheradjustment integer, historyknown boolean, startdateestimated boolean, source text, notes text, createdby text, createdat timestamp without time zone)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT o.openingpositionid,
           o.farmid::text,
           o.flockid,
           f.name::text,
           f.batchid,
           f.houseid,
           o.effectivebusinessdate,
           o.originallyplaced,
           o.openinglivebirds,
           o.historicalmortality,
           o.historicalsold,
           o.historicalculled,
           o.historicaltransferred,
           o.otheradjustment,
           o.historyknown,
           o.startdateestimated,
           o.source::text,
           o.notes::text,
           o.createdby::text,
           o.createdat
    FROM   public.poultryopeningflockposition o
    -- 433: an INNER join and the isdeleted test. A flock removed by a setup
    -- undo (or deleted any other way) takes its opening history with it;
    -- counting it again was what doubled the figures after a redo.
    -- The join still carries farmid: a flock id colliding across companies
    -- must not read another company's flock.
    JOIN   public.flock f
           ON f.flockid = o.flockid AND f.farmid = o.farmid
    WHERE  o.farmid = p_farmid
      AND  NOT COALESCE(f.isdeleted, FALSE)
    ORDER  BY f.name NULLS LAST, o.openingpositionid;
END
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryfarmsetup_get(p_farmid text)
 RETURNS TABLE(farmsetupid integer, farmid text, setupmode text, completedbusinessdate date, completedat timestamp without time zone, completedby text, batchcount integer, housecount integer, flockcount integer, originallyplaced integer, openinglivebirds integer, historicalreduction integer, notes text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.farmsetupid, s.farmid::text, s.setupmode::text, s.completedbusinessdate,
           s.completedat, s.completedby::text, s.batchcount, s.housecount, s.flockcount,
           -- 433: the same live rows the Opening Farm Position list shows, so
           -- the card and the list always agree and an undo is reflected.
           COALESCE(p.placed, 0)::integer,
           COALESCE(p.live, 0)::integer,
           COALESCE(p.reduction, 0)::integer,
           s.notes::text
    FROM   public.poultryfarmsetup s
    LEFT   JOIN LATERAL (
        SELECT SUM(g.originallyplaced)                      AS placed,
               SUM(g.openinglivebirds)                      AS live,
               SUM(g.originallyplaced - g.openinglivebirds) AS reduction
        FROM   public.sppoultryopeningposition_getall(s.farmid::text) g
    ) p ON TRUE
    WHERE  lower(s.farmid) = lower(p_farmid);
END
$function$;

-- Self-test: no deleted flock is returned, and the card equals the list.
DO $$
DECLARE
    v_bad integer;
BEGIN
    SELECT count(*) INTO v_bad
    FROM   public.poultryfarmsetup s
    CROSS  JOIN LATERAL public.sppoultryopeningposition_getall(s.farmid::text) g
    JOIN   public.flock f ON f.flockid = g.flockid AND f.farmid = g.farmid
    WHERE  COALESCE(f.isdeleted, FALSE);
    IF v_bad > 0 THEN
        RAISE EXCEPTION '433 self-test: % deleted flock row(s) still returned.', v_bad;
    END IF;

    SELECT count(*) INTO v_bad
    FROM   public.poultryfarmsetup s
    CROSS  JOIN LATERAL public.sppoultryfarmsetup_get(s.farmid::text) c
    CROSS  JOIN LATERAL (
        SELECT COALESCE(SUM(g.originallyplaced), 0) AS placed,
               COALESCE(SUM(g.openinglivebirds), 0) AS live
        FROM   public.sppoultryopeningposition_getall(s.farmid::text) g) l
    WHERE  c.originallyplaced <> l.placed OR c.openinglivebirds <> l.live;
    IF v_bad > 0 THEN
        RAISE EXCEPTION '433 self-test: % farm(s) where the card and the list disagree.', v_bad;
    END IF;

    RAISE NOTICE '433_OpeningPositionSkipsUndoneFlocks: 2 functions replaced, self-test passed.';
END
$$;

COMMIT;

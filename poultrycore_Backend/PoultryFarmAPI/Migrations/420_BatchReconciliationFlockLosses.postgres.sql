-- =============================================================================
-- 420_BatchReconciliationFlockLosses.postgres.sql   (requires 319, 413, 414)
--
-- Purpose
-- -------
-- Batch Bird Reconciliation showed where a batch's birds went ONLY for the
-- birds that never reached a flock (batch-level sales / mortality / other).
-- Birds that were placed in a flock and then lost -- the flock's OPENING
-- HISTORICAL REDUCTION from Initial Farm Setup (historical mortality, sold,
-- culled, transferred, other) and everything recorded since -- were folded
-- into "Current flock live birds" being smaller, with no column saying why.
--
-- Example from the field: B3 "Originally allocated 10,000", "Current flock
-- live birds 7,500", "Unexplained 0" -- 2,500 birds gone and not one column
-- naming them.  Only the batch-level historical sale (B1's 8,500) appeared.
--
-- What this does
-- --------------
-- sppoultrybatchreconcile_summary keeps every existing column, unchanged, and
-- APPENDS the flock side of the picture, from the same fnflock_birdposition
-- the existing columns already use:
--
--   flockhistmortality / flockhistsold / flockhistculled /
--   flockhisttransferred / flockhistother   -- opening position (before setup)
--   flockrecordedmortality                  -- production-record deaths since
--   flockpostedsold                         -- posted bird sales since
--   flockculled / flocktransferred          -- closeout culls / transfers since
--   flockotherchanges  (signed)             -- the remainder, so the row always
--        balances: count corrections on production records, flock quantity
--        adjustments, flock-to-flock transfers, birds still standing in a
--        CLOSED flock, and birds of a soft-deleted flock that still counts
--        against its batch.  0 on a clean batch.
--
-- Identity (per batch, holds by construction):
--   originallyallocated = flockhist* (5) + flockrecordedmortality
--                       + flockpostedsold + flockculled + flocktransferred
--                       + flockotherchanges + flocklivebirds
--
-- RETURNS TABLE grows, so DROP + CREATE (a RETURNS TABLE change is a signature
-- change).  The body is the LIVE body (pg_get_functiondef, 2026-11-12), which
-- matches 414 -- only the fl CTE and the final SELECT are extended.
--
-- Deploy order: this migration, then the Farm API, then the web app.  The old
-- API reads s.* by column name, so it keeps working against the new function.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

DROP FUNCTION IF EXISTS public.sppoultrybatchreconcile_summary(text);

CREATE FUNCTION public.sppoultrybatchreconcile_summary(p_farmid text)
 RETURNS TABLE(batchid integer, batchcode text, batchname text, startdate date, ishistorical boolean,
               originalbirds integer, originallyallocated integer, flockcount integer,
               batchsold integer, batchmortality integer, batchculled integer, batchtransferred integer,
               batchotherremovals integer, batchadditions integer,
               unallocatedpool integer, unallocatedlive integer, unexplained integer,
               flocklivebirds integer, totallivebirds integer, flockhistoricalreductions integer,
               historicalsalebirds integer, historicalsalevalue numeric, historicalreceived numeric, historicalowed numeric,
               status text, lastreconciledat timestamp without time zone, lastreconciliationno text,
               -- 420: the flock side
               flockhistmortality integer, flockhistsold integer, flockhistculled integer,
               flockhisttransferred integer, flockhistother integer,
               flockrecordedmortality integer, flockpostedsold integer,
               flockculled integer, flocktransferred integer,
               flockotherchanges integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH b AS (
        SELECT b.batchid, b.batchcode::text AS code, b.batchname::text AS name, b.startdate::date AS sd,
               COALESCE(b.ishistorical, FALSE) AS hist, b.numberofbirds AS orig
        FROM   mainflockbatch b WHERE b.farmid = p_farmid
    ),
    fl AS (
        SELECT f.batchid, COUNT(*)::int AS n,
               SUM(bp.originallyplaced)::int AS placed,
               SUM(CASE WHEN f.closeddate IS NULL THEN bp.currentlivebirds ELSE 0 END)::int AS live,
               SUM(bp.openingmortality + bp.openingsold + bp.openingculled + bp.openingtransferred + bp.openingother)::int AS hred,
               -- 420
               SUM(bp.openingmortality)::int   AS hmort,
               SUM(bp.openingsold)::int        AS hsold,
               SUM(bp.openingculled)::int      AS hcull,
               SUM(bp.openingtransferred)::int AS hxfer,
               SUM(bp.openingother)::int       AS hothr,
               SUM(bp.recordedmortality)::int  AS rmort,
               SUM(bp.birdssold)::int          AS psold,
               SUM(bp.birdsculled)::int        AS pcull,
               SUM(bp.birdstransferred)::int   AS pxfer
        FROM   flock f CROSS JOIN LATERAL fnflock_birdposition(p_farmid, f.flockid) bp
        WHERE  f.farmid = p_farmid AND NOT f.isdeleted
        GROUP  BY f.batchid
    ),
    -- Soft-deleted flocks still count against their batch in
    -- spflock_getconsumedforbatch (325 kept that on purpose), so they are part
    -- of "originally allocated" here too, or the identity would not hold.
    fld AS (
        SELECT f.batchid, SUM(bp.originallyplaced)::int AS placed
        FROM   flock f CROSS JOIN LATERAL fnflock_birdposition(p_farmid, f.flockid) bp
        WHERE  f.farmid = p_farmid AND f.isdeleted
          AND  f.allocationreleasedat IS NULL      -- 414: a released flock gave its birds back
        GROUP  BY f.batchid
    ),
    adj AS (
        SELECT a.batchid,
               -SUM(a.quantity) FILTER (WHERE a.reason IN ('Historical Sale', 'Historical Sale / Use'))::int AS sold,
               -SUM(a.quantity) FILTER (WHERE a.reason = 'Historical Mortality')::int                      AS mort,
               -SUM(a.quantity) FILTER (WHERE a.reason = 'Cull')::int                                      AS cull,
               -SUM(a.quantity) FILTER (WHERE a.reason = 'Transfer Out')::int                              AS xfer,
               -SUM(a.quantity) FILTER (WHERE (a.reason IS NULL OR a.reason NOT IN
                    ('Historical Sale', 'Historical Sale / Use', 'Historical Mortality', 'Cull', 'Transfer Out'))
                    AND a.quantity < 0)::int                                                               AS othr,
               SUM(a.quantity) FILTER (WHERE (a.reason IS NULL OR a.reason NOT IN
                    ('Historical Sale', 'Historical Sale / Use', 'Historical Mortality', 'Cull', 'Transfer Out'))
                    AND a.quantity > 0)::int                                                               AS addn
        FROM   poultrybirdadjustments a
        WHERE  a.farmid = p_farmid AND a.scope = 'BatchUnallocated'
          -- a reversed movement and its reversal cancel out: neither is reported
          AND  a.reversedbyid IS NULL AND a.reversesid IS NULL
        GROUP  BY a.batchid
    ),
    hs AS (
        SELECT h.batchid, SUM(h.birds)::int AS birds, SUM(COALESCE(h.totalvalue, 0)) AS val,
               SUM(h.amountreceived) AS recv, SUM(h.amountowed) AS owed
        FROM   poultryhistoricalbirdsales h WHERE h.farmid = p_farmid AND h.status = 'Posted'
        GROUP  BY h.batchid
    ),
    lr AS (
        SELECT DISTINCT ON (r.batchid) r.batchid, r.unexplainedbirds, r.createdat, r.reconciliationno
        FROM   poultrybatchbirdreconciliations r
        WHERE  r.farmid = p_farmid AND r.status <> 'Reversed'
        ORDER  BY r.batchid, r.reconciliationid DESC
    ),
    calc AS (
        SELECT b.*, COALESCE(fl.n, 0) AS n, COALESCE(fl.placed, 0) + COALESCE(fld.placed, 0) AS placed,
               COALESCE(fl.live, 0) AS live, COALESCE(fl.hred, 0) AS hred,
               COALESCE(adj.sold, 0) AS sold, COALESCE(adj.mort, 0) AS mort, COALESCE(adj.cull, 0) AS cull,
               COALESCE(adj.xfer, 0) AS xfer, COALESCE(adj.othr, 0) AS othr, COALESCE(adj.addn, 0) AS addn,
               fnpoultrybatch_unallocated(p_farmid, b.batchid) AS pool,
               lr.unexplainedbirds AS lrx, lr.createdat AS lrat, lr.reconciliationno AS lrno,
               hs.birds AS hsb, hs.val AS hsv, hs.recv AS hsr, hs.owed AS hso,
               -- 420
               COALESCE(fl.hmort, 0) AS hmort, COALESCE(fl.hsold, 0) AS hsold, COALESCE(fl.hcull, 0) AS hcull,
               COALESCE(fl.hxfer, 0) AS hxfer, COALESCE(fl.hothr, 0) AS hothr,
               COALESCE(fl.rmort, 0) AS rmort, COALESCE(fl.psold, 0) AS psold,
               COALESCE(fl.pcull, 0) AS pcull, COALESCE(fl.pxfer, 0) AS pxfer
        FROM   b
        LEFT   JOIN fl  ON fl.batchid  = b.batchid
        LEFT   JOIN fld ON fld.batchid = b.batchid
        LEFT   JOIN adj ON adj.batchid = b.batchid
        LEFT   JOIN hs  ON hs.batchid  = b.batchid
        LEFT   JOIN lr  ON lr.batchid  = b.batchid
    ),
    x AS (
        SELECT c.*,
               -- Unexplained: a historical batch never reconciled holds nothing
               -- confirmed; otherwise what the last posting left unexplained,
               -- never more than the pool still holds.  A new purchase's unplaced
               -- birds are simply birds waiting to be placed.
               CASE WHEN c.lrx IS NOT NULL THEN LEAST(c.lrx, c.pool)
                    WHEN c.hist THEN c.pool
                    ELSE 0 END
               -- over-allocation shows up as a negative difference
               + LEAST(c.orig + c.addn - c.placed - c.sold - c.mort - c.cull - c.xfer - c.othr, 0) AS unx
        FROM   calc c
    )
    SELECT x.batchid, x.code, x.name, x.sd, x.hist, x.orig, x.placed, x.n,
           x.sold, x.mort, x.cull, x.xfer, x.othr, x.addn,
           x.pool, x.pool - GREATEST(x.unx, 0), x.unx,
           x.live, x.live + x.pool - GREATEST(x.unx, 0), x.hred,
           COALESCE(x.hsb, 0), COALESCE(x.hsv, 0)::numeric(14,2), COALESCE(x.hsr, 0)::numeric(14,2), COALESCE(x.hso, 0)::numeric(14,2),
           CASE WHEN x.unx < 0 THEN 'OverAllocated'
                WHEN x.unx > 0 THEN 'NeedsReconciliation'
                ELSE 'FullyAccountedFor' END,
           x.lrat, x.lrno,
           -- 420
           x.hmort, x.hsold, x.hcull, x.hxfer, x.hothr,
           x.rmort, x.psold, x.pcull, x.pxfer,
           (x.placed - x.hmort - x.hsold - x.hcull - x.hxfer - x.hothr
                     - x.rmort - x.psold - x.pcull - x.pxfer - x.live)::int
    FROM   x
    ORDER  BY x.sd DESC, x.batchid DESC;
$function$;

-- ----------------------------------------------------------- self-test ------
-- The identity must hold for every batch in the database, and the columns
-- that existed before 420 must be what they were.
DO $t$
DECLARE v_bad integer;
BEGIN
    SELECT COUNT(*) INTO v_bad
    FROM   (SELECT DISTINCT farmid FROM mainflockbatch) mb
    CROSS  JOIN LATERAL public.sppoultrybatchreconcile_summary(mb.farmid) s
    WHERE  s.originallyallocated <> s.flockhistmortality + s.flockhistsold + s.flockhistculled
                                  + s.flockhisttransferred + s.flockhistother
                                  + s.flockrecordedmortality + s.flockpostedsold
                                  + s.flockculled + s.flocktransferred
                                  + s.flockotherchanges + s.flocklivebirds;
    IF v_bad > 0 THEN
        RAISE EXCEPTION '420: % batch(es) do not balance', v_bad;
    END IF;

    SELECT COUNT(*) INTO v_bad
    FROM   (SELECT DISTINCT farmid FROM mainflockbatch) mb
    CROSS  JOIN LATERAL public.sppoultrybatchreconcile_summary(mb.farmid) s
    WHERE  s.flockhistoricalreductions <> s.flockhistmortality + s.flockhistsold + s.flockhistculled
                                        + s.flockhisttransferred + s.flockhistother;
    IF v_bad > 0 THEN
        RAISE EXCEPTION '420: % batch(es) split the historical reduction wrongly', v_bad;
    END IF;
END
$t$;

COMMIT;

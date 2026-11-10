-- =============================================================================
-- 404_PoultryDailyClosingEggsDisposed.postgres.sql
--
-- Purpose
-- -------
-- Daily Closing showed damaged (broken) eggs but not how many eggs were
-- DISPOSED of that day. Customers asked for the total.
--
-- Eggs disposed on a day = the Broken Eggs stock that left by disposal that
-- day, from the one stock ledger (poultrystocktransactions):
--   'Broken Egg Disposal'  disposed at once on a production record (372/390)
--   'Disposal'             disposed later from the Broken Eggs tracker (373)
--   ...net of corrections: a production record edited down, or a manual
--   disposal reversed, posts the opposite row with the same txntype, so the
--   signed sum is already net (a reversal counts on the day it is reversed).
-- The same txntypes fnpoultry_byproductledger classifies as 'Disposed' (375),
-- limited to the BrokenEggs byproduct (Dead Birds disposals are not eggs).
--
-- What changes
--   1. fnpoultry_eggsdisposed(farm, date)            -- the one definition.
--   2. sppoultrydailyclosing_workspace (the wrapper, 343) -- adds
--      production.eggsDisposed. Patched in place (text replace of one anchor)
--      so whatever the live wrapper body is, it is kept.
--   3. sppoultrydailyclosing_history (365) -- appends eggsdisposed. A day
--      closed before this migration has no eggsDisposed in its snapshot; it
--      falls back to the ledger figure for that day.
--
-- Deploy order: this migration, then the API, then the web app. The API reads
-- the new history column only when it is there, so it can go out first too.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

-- ------------------------------------------------------------ 1. the figure --
CREATE OR REPLACE FUNCTION public.fnpoultry_eggsdisposed(p_farmid text, p_date date)
RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(-SUM(t.quantity), 0)::numeric(18,3)
    FROM   poultrystocktransactions t
    JOIN   poultryproducts p ON p.poultryproductid = t.poultryproductid AND p.farmid = t.farmid
    WHERE  t.farmid = p_farmid
      AND  p.systemrole = 'BrokenEggs'
      AND  t.txntype IN ('Broken Egg Disposal', 'Disposal')
      AND  COALESCE(t.effectivedate, t.createddate::date) = p_date;
$f$;

-- ------------------------------------------------ 2. the workspace wrapper --
DO $patch$
DECLARE
    v_oid    oid := to_regprocedure('public.sppoultrydailyclosing_workspace(text,date,timestamp with time zone)');
    v_def    text;
    v_anchor text := '    SELECT g.enableeggsorting, g.closingpolicy INTO v_on, v_policy';
    v_new    text := E'    -- 404: eggs disposed that day (Broken Eggs disposals, net).\n'
                  || E'    v_ws := jsonb_set(v_ws, ''{production,eggsDisposed}'',\n'
                  || E'        to_jsonb(public.fnpoultry_eggsdisposed(p_farmid, (v_ws->>''businessDate'')::date)), TRUE);\n';
    v_n      integer;
BEGIN
    IF v_oid IS NULL THEN
        RAISE EXCEPTION '404: sppoultrydailyclosing_workspace(text,date,timestamptz) not found (needs 343)';
    END IF;
    v_def := replace(pg_get_functiondef(v_oid), chr(13), '');
    IF position('404: eggs disposed' IN v_def) > 0 THEN
        RAISE NOTICE '404: workspace already patched, skipped';
        RETURN;
    END IF;
    v_n := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
    IF v_n <> 1 THEN
        RAISE EXCEPTION '404: anchor found % times in sppoultrydailyclosing_workspace, expected 1', v_n;
    END IF;
    EXECUTE replace(v_def, v_anchor, v_new || v_anchor);
    RAISE NOTICE '404: patched sppoultrydailyclosing_workspace';
END
$patch$;

-- --------------------------------------------------------- 3. the history --
DROP FUNCTION IF EXISTS public.sppoultrydailyclosing_history(text, date, date);
CREATE FUNCTION public.sppoultrydailyclosing_history(p_farmid text, p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL)
RETURNS TABLE(
    poultrydailyclosingid integer, closingdate date, status text, closedatutc timestamptz, closedby text,
    closeversion integer, warningsatclose integer, reopencount integer,
    lastreopenedatutc timestamptz, lastreopenreason text,
    revenue numeric, moneyin numeric, moneyout numeric, netcashflow numeric,
    eggsproduced numeric, missingflocks integer, hassnapshot boolean,
    -- 365
    islive boolean, salescount integer, cashsales numeric, creditsales numeric,
    paymentsreceived numeric, expenses numeric, openingcash numeric, closingcash numeric,
    cashdifference numeric, eggsdamaged numeric, mortality numeric, feedkg numeric,
    blockingcount integer, warningcount integer,
    -- 404
    eggsdisposed numeric)
LANGUAGE sql
STABLE
AS $function$
    SELECT c.poultrydailyclosingid, c.closingdate, c.status::text, c.closedatutc, c.closedby,
           c.closeversion, c.warningsatclose,
           (SELECT count(*)::int FROM poultrydailyclosingevents e
            WHERE e.poultrydailyclosingid = c.poultrydailyclosingid AND e.eventtype = 'Reopened'),
           c.lastreopenedatutc, c.lastreopenreason,
           (w.ws->'sales'->>'revenue')::numeric,
           (w.ws->'cash'->>'moneyIn')::numeric,
           (w.ws->'cash'->>'moneyOut')::numeric,
           (w.ws->'cash'->>'netCashFlow')::numeric,
           (w.ws->'production'->>'eggsProduced')::numeric,
           (w.ws->'production'->>'missingFlocks')::int,
           c.closingsnapshot IS NOT NULL,
           w.islive,
           (w.ws->'sales'->>'count')::int,
           (w.ws->'sales'->>'cashSales')::numeric,
           (w.ws->'sales'->>'creditSales')::numeric,
           (w.ws->'sales'->>'paymentsReceived')::numeric,
           (w.ws->'expenses'->>'total')::numeric,
           (w.ws->'cash'->>'openingCash')::numeric,
           (w.ws->'cash'->>'closingCash')::numeric,
           (w.ws->'cash'->>'difference')::numeric,
           (w.ws->'production'->>'eggsDamaged')::numeric,
           (w.ws->'production'->>'mortality')::numeric,
           (w.ws->'production'->>'feedKg')::numeric,
           (w.ws->'counts'->>'blocking')::int,
           (w.ws->'counts'->>'warning')::int,
           -- 404: a snapshot taken before 404 has no eggsDisposed: the ledger's.
           COALESCE((w.ws->'production'->>'eggsDisposed')::numeric,
                    public.fnpoultry_eggsdisposed(c.farmid, c.closingdate))
    FROM   poultrydailyclosings c
    CROSS  JOIN LATERAL (
        SELECT NOT (c.status = 'Approved' AND c.closingsnapshot IS NOT NULL) AS islive,
               CASE WHEN c.status = 'Approved' AND c.closingsnapshot IS NOT NULL
                    THEN c.closingsnapshot
                    ELSE public.sppoultrydailyclosing_workspace(c.farmid, c.closingdate)
               END AS ws
    ) w
    WHERE  c.farmid = p_farmid
      AND (p_fromdate IS NULL OR c.closingdate >= p_fromdate)
      AND (p_todate   IS NULL OR c.closingdate <= p_todate)
    ORDER  BY c.closingdate DESC;
$function$;

COMMIT;

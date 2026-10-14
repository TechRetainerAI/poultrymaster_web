-- =============================================================================
-- 365_PoultryDailyClosingHistoryFigures.postgres.sql
--
-- Purpose
-- -------
-- The Previous closings list showed little more than a date and a status: its
-- figures came only from the closing snapshot, which exists for a day that was
-- CLOSED (Approved). A Draft, Submitted or reopened day -- most rows -- showed
-- "—" everywhere, so users had to open every day to see anything.
--
-- Now every row carries the day's figures:
--   Closed (Approved, with a snapshot)  the figures AS CLOSED (unchanged).
--   Any other day                       the figures NOW, from the same
--                                       workspace the Day tab shows
--                                       (islive = true).
-- and more of them: sales count, cash / credit sales, payments received,
-- expenses, opening / closing cash, cash difference, damaged eggs, mortality,
-- feed, blocking / warning counts.
--
-- The new columns are APPENDED, so the old API (SELECT * , read by name) keeps
-- working. Deploy order: this migration, then the API, then the web app.
-- =============================================================================
BEGIN;

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
    blockingcount integer, warningcount integer)
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
           (w.ws->'counts'->>'warning')::int
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

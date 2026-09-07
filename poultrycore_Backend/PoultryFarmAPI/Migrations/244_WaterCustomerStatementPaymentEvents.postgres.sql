-- =============================================================================
-- 244  Water: the statement shows the payment the customer made
-- =============================================================================
-- The water port of 242. The statement's payment leg reads waterpayments row by
-- row, and that table holds one row per SALE -- so a customer who settles three
-- invoices with one transfer gets three credits on their statement against a
-- payment they made once.
--
-- The payment leg is now grouped by paymentgroupid: one credit line per payment
-- event, carrying its number (243), how many sales it settled and where it was
-- taken. The line is the payment; the allocation behind it is a drilldown.
--
-- NEW COLUMNS: paymentgroupid, allocationcount, sourcetype. saleid is NULL on a
-- payment covering several sales -- there is no single sale to name -- which is
-- also why the ordering below spells out how ties break.
--
-- Requires 243 (paymentnumber). Apply before deploying the API build.
--
-- HOW TO RUN
--   1. Dry run (default):
--        psql "<conn>" -f 244_WaterCustomerStatementPaymentEvents.postgres.sql
--   2. For real:
--        psql "<conn>" -v apply=true -f 244_...sql
-- =============================================================================

\set ON_ERROR_STOP on

\if :{?apply}
\else
  \set apply false
\endif

BEGIN;

DROP FUNCTION IF EXISTS public.spwatercustomerstatement(text, integer, date, date);

CREATE FUNCTION public.spwatercustomerstatement(
    p_farmid text, p_customerid integer,
    p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
RETURNS TABLE(
    entrydate       date,
    entrytype       text,
    reference       text,
    description     text,
    debit           numeric,
    credit          numeric,
    runningbalance  numeric,
    saleid          integer,
    sortkey         integer,
    paymentgroupid  uuid,
    allocationcount integer,
    sourcetype      text)
LANGUAGE sql
STABLE
AS $function$
    WITH lines AS (
        -- Opening balance: what was owed before the window opened. p_from NULL
        -- means "the whole history", and a whole-history statement has nothing
        -- before it -- so the opening MUST be zero. The usual
        -- `p_from IS NULL OR ...` idiom here would instead match every sale ever
        -- and count the entire ledger twice.
        SELECT CASE WHEN p_from IS NULL THEN NULL::date ELSE p_from END AS entrydate,
               'OpeningBalance'::text  AS entrytype,
               NULL::text              AS reference,
               'Opening balance'::text AS description,
               CASE WHEN p_from IS NULL THEN 0::numeric(14,2) ELSE COALESCE((
                   SELECT SUM(GREATEST(s.totalamount - s.amountpaid, 0))
                   FROM   watersales s
                   WHERE  s.farmid = p_farmid AND s.watercustomerid = p_customerid
                     AND  COALESCE(s.status, '') <> 'Cancelled'
                     AND  s.saledate::date < p_from), 0)::numeric(14,2) END AS debit,
               0::numeric(14,2) AS credit,
               NULL::integer    AS saleid,
               0                AS sortkey,
               0                AS pin,
               NULL::uuid       AS paymentgroupid,
               NULL::integer    AS allocationcount,
               NULL::text       AS sourcetype

        UNION ALL

        SELECT s.saledate::date, 'Sale'::text,
               ('W' || s.watersaleid::text)::text,
               COALESCE(NULLIF(btrim(s.notes), ''), 'Water sale')::text,
               s.totalamount::numeric(14,2), 0::numeric(14,2),
               s.watersaleid, 1, 1,
               NULL::uuid, NULL::integer, 'Sale'::text
        FROM   watersales s
        WHERE  s.farmid = p_farmid AND s.watercustomerid = p_customerid
          AND  COALESCE(s.status, '') <> 'Cancelled'
          AND  (p_from IS NULL OR s.saledate::date >= p_from)
          AND  (p_to   IS NULL OR s.saledate::date <= p_to)

        UNION ALL

        -- Money the sale records as received with no payment row behind it --
        -- a sale entered as already paid. Without this the statement shows the
        -- debit and never the receipt, and its closing figure disagrees with
        -- the balances page. Only the POSITIVE remainder: a negative one means
        -- the payment rows exceed what the sale says it received, which is a
        -- data problem to surface, not to quietly subtract.
        SELECT s.saledate::date, 'Payment'::text,
               ('W' || s.watersaleid::text)::text,
               'Paid at point of sale'::text,
               0::numeric(14,2), v.residual,
               s.watersaleid, 2, 1,
               NULL::uuid, 1, 'Counter'::text
        FROM   watersales s
        CROSS  JOIN LATERAL (
            SELECT ROUND(GREATEST(COALESCE(s.amountpaid, 0), 0)
                       - COALESCE((SELECT SUM(p2.amount) FROM waterpayments p2
                                   WHERE p2.watersaleid = s.watersaleid
                                     AND p2.farmid = s.farmid
                                     AND COALESCE(p2.status, 'Posted') = 'Posted'), 0), 2) AS residual
        ) v
        WHERE  s.farmid = p_farmid AND s.watercustomerid = p_customerid
          AND  COALESCE(s.status, '') <> 'Cancelled'
          AND  v.residual > 0
          AND  (p_from IS NULL OR s.saledate::date >= p_from)
          AND  (p_to   IS NULL OR s.saledate::date <= p_to)

        UNION ALL

        -- ONE LINE PER PAYMENT EVENT.
        SELECT MIN(p.paymentdate)::date, 'Payment'::text,
               COALESCE(MIN(p.paymentnumber),
                        NULLIF(btrim(MIN(p.reference)), ''),
                        'PMT' || MIN(p.waterpaymentid)::text)::text,
               ('Payment'
                || COALESCE(' — ' || NULLIF(btrim(MIN(p.paymentmethod)), ''), '')
                || CASE WHEN COUNT(DISTINCT p.watersaleid) > 1
                        THEN ' across ' || COUNT(DISTINCT p.watersaleid)::text || ' sales'
                        ELSE ' (sale W' || MIN(p.watersaleid)::text || ')'
                   END)::text,
               0::numeric(14,2), SUM(p.amount)::numeric(14,2),
               CASE WHEN COUNT(DISTINCT p.watersaleid) = 1 THEN MIN(p.watersaleid) END,
               2, 1,
               p.paymentgroupid,
               COUNT(DISTINCT p.waterpaymentid)::integer,
               MIN(p.sourcetype)::text
        FROM   waterpayments p
        WHERE  p.farmid = p_farmid AND p.watercustomerid = p_customerid
          AND  COALESCE(p.status, 'Posted') = 'Posted'
          -- A CANCELLED SALE'S PAYMENTS DO NOT CREDIT THE CUSTOMER. The debit
          -- leg above has always excluded cancelled sales; this leg did not, so
          -- their credits survived and drove the balance down -- one customer
          -- read as being OWED 13,414 because 17 payments against cancelled
          -- sales stayed on their statement. That is the whole of the drift
          -- between this statement and the balances page.
          --
          -- Written as NOT EXISTS-cancelled rather than EXISTS-not-cancelled on
          -- purpose: a payment whose sale row is missing entirely keeps showing,
          -- exactly as it does today. Only cancellation is being filtered.
          AND  NOT EXISTS (SELECT 1 FROM watersales s
                           WHERE s.watersaleid = p.watersaleid
                             AND s.farmid = p.farmid
                             AND COALESCE(s.status, '') = 'Cancelled')
          AND  (p_from IS NULL OR p.paymentdate::date >= p_from)
          AND  (p_to   IS NULL OR p.paymentdate::date <= p_to)
        GROUP  BY p.paymentgroupid
    ),
    ordered AS (
        -- `reference` is the final tiebreaker now that two payments on one day
        -- can both have a null saleid.
        SELECT l.*,
               ROW_NUMBER() OVER (
                   ORDER BY l.pin, l.entrydate NULLS FIRST, l.sortkey,
                            l.saleid NULLS FIRST, l.reference) AS rn
        FROM   lines l
    )
    SELECT o.entrydate, o.entrytype, o.reference, o.description,
           o.debit, o.credit,
           SUM(o.debit - o.credit) OVER (ORDER BY o.rn
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::numeric(14,2),
           o.saleid, o.sortkey, o.paymentgroupid, o.allocationcount, o.sourcetype
    FROM   ordered o
    ORDER  BY o.rn;
$function$;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== A statement, end to end ================================================'
SELECT entrydate, entrytype, reference, description, debit, credit, runningbalance,
       allocationcount, sourcetype
FROM   spwatercustomerstatement(
        (SELECT p.farmid::text FROM waterpayments p
         WHERE p.watercustomerid IS NOT NULL
         GROUP BY p.farmid::text, p.watercustomerid ORDER BY count(*) DESC LIMIT 1),
        (SELECT p.watercustomerid FROM waterpayments p
         WHERE p.watercustomerid IS NOT NULL
         GROUP BY p.farmid::text, p.watercustomerid ORDER BY count(*) DESC LIMIT 1))
LIMIT 20;

\echo ''
\echo '--- Any payment across several sales is ONE line ---------------------------'
SELECT st.reference, st.description, st.credit, st.allocationcount, st.saleid
FROM  (SELECT p.farmid::text AS farmid, p.watercustomerid AS cid
       FROM   waterpayments p
       WHERE  p.paymentgroupid IS NOT NULL AND p.watercustomerid IS NOT NULL
       GROUP  BY 1, 2, p.paymentgroupid
       HAVING count(*) > 1) g
CROSS  JOIN LATERAL spwatercustomerstatement(g.farmid, g.cid) st
WHERE  st.allocationcount > 1;

\echo ''
\echo '--- Closing balance vs the sales it is derived from ------------------------'
-- Two independent derivations of one number. Closing is SUM(debit) - SUM(credit)
-- rather than the last row, so the check does not depend on row order.
WITH farm AS (
    SELECT s.farmid::text AS farmid
    FROM   watersales s
    WHERE  s.watercustomerid IS NOT NULL
    GROUP  BY 1 ORDER BY count(*) DESC LIMIT 1
), owed AS (
    SELECT f.farmid, s.watercustomerid AS cid,
           SUM(GREATEST(COALESCE(s.totalamount, 0) - COALESCE(s.amountpaid, 0), 0))::numeric(14,2) AS balance
    FROM   farm f
    JOIN   watersales s ON s.farmid::text = f.farmid AND s.watercustomerid IS NOT NULL
    WHERE  COALESCE(s.status, '') <> 'Cancelled'
    GROUP  BY f.farmid, s.watercustomerid
)
SELECT o.cid,
       o.balance  AS from_sales,
       st.closing AS from_statement,
       CASE WHEN o.balance = st.closing THEN 'OK' ELSE '*** DRIFT ***' END AS verdict
FROM   owed o
CROSS  JOIN LATERAL (
    SELECT COALESCE(SUM(x.debit) - SUM(x.credit), 0)::numeric(14,2) AS closing
    FROM   spwatercustomerstatement(o.farmid, o.cid) x
) st
ORDER  BY 4 DESC, 1;

\if :apply
    COMMIT;
    \echo ''
    \echo '>>> COMMITTED. Deploy the API build that reads the new columns next.'
\else
    ROLLBACK;
    \echo ''
    \echo '>>> DRY RUN -- rolled back.'
    \echo '>>> Re-run with  -v apply=true  to write it.'
\endif

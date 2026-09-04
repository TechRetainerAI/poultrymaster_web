-- =============================================================================
-- 241  The one-sale payment carries its allocation on the row
-- =============================================================================
-- Most payments settle exactly one sale, and for those the interesting numbers
-- -- which sale, what it was worth, and the balance the payment moved it from
-- and to -- are one allocation row away. The Payments Received page wants them
-- on the main row (no expanding to read a single line), and was getting them by
-- fetching the allocation for every single-sale payment on the page: one small
-- request per row, twenty-odd per page.
--
-- The grouped history already knows how many sales a payment covers, so it can
-- answer the one-sale case itself. When allocationcount = 1 the five fields are
-- filled in; when a payment spans several sales they are NULL, which is exactly
-- the "—" the page prints before you expand it.
--
-- NOTE ON saletotal. The allocation row snapshots the BALANCE either side of
-- the payment but not the sale's total, so the total is read live from `sale`.
-- That is the right trade: the balances are the values that would be wrong if
-- recomputed later, and they are the ones that were captured. A sale whose
-- total is edited afterwards will show its current total beside a historical
-- balance -- rare, and better than inventing a snapshot that was never taken.
--
-- Supersedes the version in 240 (which added paymentnumber); this file carries
-- that column forward, so 241 alone is enough on a database that has 240.
--
-- HOW TO RUN
--   1. Dry run (default):
--        psql "<conn>" -f 241_PoultryPaymentHistoryInlineAllocation.postgres.sql
--   2. For real:
--        psql "<conn>" -v apply=true -f 241_...sql
--
--   Requires 240 (paymentnumber). Apply before deploying the API build that
--   reads the new columns; an older build ignores them.
-- =============================================================================

\set ON_ERROR_STOP on

\if :{?apply}
\else
  \set apply false
\endif

BEGIN;

DROP FUNCTION IF EXISTS public.sppoultrycustomerpayment_history(text, integer, integer, date, date);

CREATE FUNCTION public.sppoultrycustomerpayment_history(
    p_farmid text,
    p_customerid integer DEFAULT NULL::integer,
    p_saleid integer DEFAULT NULL::integer,
    p_from date DEFAULT NULL::date,
    p_to date DEFAULT NULL::date)
RETURNS TABLE(
    paymentgroupid  uuid,
    paymentnumber   text,
    customerid      integer,
    customername    text,
    paymentdate     timestamp without time zone,
    totalamount     numeric,
    paymentmethod   text,
    reference       text,
    note            text,
    sourcetype      text,
    status          text,
    allocationcount integer,
    poultrycashaccountid integer,
    createdby       text,
    reversedby      text,
    reversedat      timestamp without time zone,
    reversalreason  text,
    -- Filled in only for a payment that settled ONE sale.
    saleid          integer,
    saletotal       numeric,
    balancebefore   numeric,
    amountapplied   numeric,
    balanceafter    numeric)
LANGUAGE sql
STABLE
AS $function$
    SELECT pp.paymentgroupid,
           MIN(pp.paymentnumber)::text,
           MIN(pp.customerid),
           MIN(c.name)::text,
           MIN(pp.paymentdate),
           SUM(pp.amount)::numeric(14,2),
           MIN(pp.paymentmethod)::text,
           MIN(pp.reference)::text,
           MIN(pp.note)::text,
           MIN(pp.sourcetype)::text,
           MIN(COALESCE(pp.status, 'Posted'))::text,
           -- DISTINCT on the payment row, not COUNT(*): the joins below are
           -- 1:1 today, and this stays right if one of them ever is not.
           COUNT(DISTINCT pp.poultrypaymentid)::integer,
           MIN(pp.poultrycashaccountid),
           MIN(pp.createdby)::text,
           MIN(pp.reversedby)::text,
           MIN(pp.reversedat),
           MIN(pp.reversalreason)::text,
           -- One sale, or nothing. A payment across several sales has no single
           -- "balance before" to report, and saying so with NULL is what lets
           -- the page print "—" without guessing.
           CASE WHEN COUNT(DISTINCT pp.poultrypaymentid) = 1 THEN MIN(pp.saleid) END,
           CASE WHEN COUNT(DISTINCT pp.poultrypaymentid) = 1 THEN MIN(s.totalamount)::numeric(14,2) END,
           CASE WHEN COUNT(DISTINCT pp.poultrypaymentid) = 1 THEN MIN(ca.salebalancebefore)::numeric(14,2) END,
           CASE WHEN COUNT(DISTINCT pp.poultrypaymentid) = 1 THEN MIN(ca.amountapplied)::numeric(14,2) END,
           CASE WHEN COUNT(DISTINCT pp.poultrypaymentid) = 1 THEN MIN(ca.salebalanceafter)::numeric(14,2) END
    FROM   poultrypayments pp
    LEFT   JOIN customer c ON c.customerid = pp.customerid AND c.farmid = pp.farmid
    LEFT   JOIN sale s     ON s.saleid = pp.saleid AND s.farmid = pp.farmid
    -- Payments taken before 222 have no allocation row; those columns come back
    -- NULL and the page falls back to what it can show.
    LEFT   JOIN customerpaymentallocation ca
           ON  ca.module = 'poultry'
           AND ca.paymentid = pp.poultrypaymentid
           AND ca.farmid = pp.farmid
    WHERE  pp.farmid = p_farmid
      AND  (p_customerid IS NULL OR pp.customerid = p_customerid)
      AND  (p_from IS NULL OR pp.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR pp.paymentdate::date <= p_to)
      AND  (p_saleid IS NULL OR EXISTS (
              SELECT 1 FROM poultrypayments p2
              WHERE p2.paymentgroupid = pp.paymentgroupid AND p2.saleid = p_saleid))
    GROUP  BY pp.paymentgroupid
    ORDER  BY MIN(pp.paymentdate) DESC;
$function$;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== One-sale payments must carry their allocation, multi-sale must not ====='
SELECT CASE WHEN allocationcount = 1 THEN 'one sale' ELSE 'several sales' END AS kind,
       count(*)                                  AS payments,
       count(saleid)                             AS with_saleid,
       count(balancebefore)                      AS with_balances,
       CASE
           WHEN allocationcount = 1 AND count(*) <> count(saleid)
               THEN 'check: some one-sale payments have no allocation row (pre-222)'
           WHEN allocationcount > 1 AND count(saleid) > 0
               THEN '*** a multi-sale payment reported a single sale ***'
           ELSE 'OK'
       END AS verdict
FROM   sppoultrycustomerpayment_history(
         (SELECT pp.farmid::text FROM poultrypayments pp
          GROUP BY pp.farmid::text ORDER BY count(*) DESC LIMIT 1))
GROUP  BY CASE WHEN allocationcount = 1 THEN 'one sale' ELSE 'several sales' END,
          allocationcount
ORDER  BY 1;

\echo ''
\echo '--- What the row will now show without expanding ---------------------------'
SELECT paymentnumber, customername, totalamount, allocationcount,
       saleid, saletotal, balancebefore, amountapplied, balanceafter
FROM   sppoultrycustomerpayment_history(
         (SELECT pp.farmid::text FROM poultrypayments pp
          GROUP BY pp.farmid::text ORDER BY count(*) DESC LIMIT 1))
LIMIT  10;

\echo ''
\echo '--- The inline numbers must agree with the allocation table ----------------'
SELECT count(*) AS disagreements
FROM   sppoultrycustomerpayment_history(
         (SELECT pp.farmid::text FROM poultrypayments pp
          GROUP BY pp.farmid::text ORDER BY count(*) DESC LIMIT 1)) h
JOIN   poultrypayments pp ON pp.paymentgroupid = h.paymentgroupid
JOIN   customerpaymentallocation ca
       ON ca.module = 'poultry' AND ca.paymentid = pp.poultrypaymentid
WHERE  h.allocationcount = 1
  AND  (h.balancebefore IS DISTINCT FROM ca.salebalancebefore
     OR h.balanceafter  IS DISTINCT FROM ca.salebalanceafter
     OR h.amountapplied IS DISTINCT FROM ca.amountapplied);

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

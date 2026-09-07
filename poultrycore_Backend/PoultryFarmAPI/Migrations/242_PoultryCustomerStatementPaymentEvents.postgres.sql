-- =============================================================================
-- 242  The statement shows the payment the customer made
-- =============================================================================
-- Same fault as the Payments Received page had, in the last place it survives.
-- The statement's payment leg reads poultrypayments row by row, and that table
-- holds one row per SALE -- so comfort's single GHC 4,820 appears on her
-- statement as two credits of GHC 2,000 and GHC 2,820, against a payment she
-- only made once. The running balance is right; the story is wrong, and a
-- statement IS the story.
--
-- The payment leg is now grouped by paymentgroupid: one credit line per payment
-- event, carrying its number (PAY-0004), how many sales it settled and where it
-- was taken. The line is the payment; the allocation behind it is a drilldown,
-- which is what section 27 of the spec asks for.
--
-- WHAT IS UNCHANGED. Sales are still the debits, the counter-paid leg still
-- covers sales settled without a payment row, the opening balance still works
-- the way 223 built it, and the running balance is still a window over the same
-- ordering -- so a statement's closing figure cannot drift from the balances
-- page. Reversed payments are still excluded.
--
-- NEW COLUMNS. paymentgroupid, allocationcount and sourcetype, so the dialog
-- can expand a multi-sale payment and print a Source column. saleid is now NULL
-- on a payment that covers several sales -- there is no single sale to name --
-- which is also what makes the ordering below explicit about ties.
--
-- HOW TO RUN
--   1. Dry run (default):
--        psql "<conn>" -f 242_PoultryCustomerStatementPaymentEvents.postgres.sql
--   2. For real:
--        psql "<conn>" -v apply=true -f 242_...sql
--
--   Requires 240 (paymentnumber). Apply before deploying the API build that
--   reads the new columns.
-- =============================================================================

\set ON_ERROR_STOP on

\if :{?apply}
\else
  \set apply false
\endif

BEGIN;

DROP FUNCTION IF EXISTS public.sppoultrycustomerstatement(text, integer, date, date);

CREATE FUNCTION public.sppoultrycustomerstatement(
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
        -- Opening balance: what was owed before the window opened.
        --
        -- p_from NULL means "the whole history", and a whole-history statement
        -- has nothing before it -- so the opening MUST be zero. Reusing the
        -- usual `p_from IS NULL OR ...` idiom here would instead match every
        -- sale ever and count the entire ledger twice.
        SELECT CASE WHEN p_from IS NULL THEN NULL::date ELSE p_from END AS entrydate,
               'OpeningBalance'::text  AS entrytype,
               NULL::text              AS reference,
               'Opening balance'::text AS description,
               CASE WHEN p_from IS NULL THEN 0::numeric(14,2) ELSE COALESCE((
                   SELECT SUM(fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid))
                   FROM   sale s
                   WHERE  s.farmid = p_farmid AND s.customerid = p_customerid
                     AND  s.saledate < p_from), 0)::numeric(14,2) END AS debit,
               0::numeric(14,2)        AS credit,
               NULL::integer           AS saleid,
               0                       AS sortkey,
               0                       AS pin,
               NULL::uuid              AS paymentgroupid,
               NULL::integer           AS allocationcount,
               NULL::text              AS sourcetype

        UNION ALL

        SELECT s.saledate, 'Sale'::text,
               ('S' || s.saleid::text)::text,
               COALESCE(NULLIF(btrim(s.saledescription), ''), s.product)::text,
               s.totalamount::numeric(14,2), 0::numeric(14,2), s.saleid, 1, 1,
               NULL::uuid, NULL::integer, 'Sale'::text
        FROM   sale s
        WHERE  s.farmid = p_farmid AND s.customerid = p_customerid
          AND  (p_from IS NULL OR s.saledate >= p_from)
          AND  (p_to   IS NULL OR s.saledate <= p_to)

        UNION ALL

        -- Settled at the counter: no payment row exists, so without this the
        -- statement would show the debit and never the receipt.
        SELECT s.saledate, 'Payment'::text,
               ('S' || s.saleid::text)::text,
               'Paid at point of sale'::text,
               0::numeric(14,2), s.totalamount::numeric(14,2), s.saleid, 2, 1,
               NULL::uuid, 1, 'Counter'::text
        FROM   sale s
        WHERE  s.farmid = p_farmid AND s.customerid = p_customerid
          AND  COALESCE(s.paid, TRUE)
          AND  (p_from IS NULL OR s.saledate >= p_from)
          AND  (p_to   IS NULL OR s.saledate <= p_to)
          AND  NOT EXISTS (SELECT 1 FROM poultrypayments pp
                           WHERE pp.saleid = s.saleid AND pp.farmid = s.farmid
                             AND COALESCE(pp.status, 'Posted') = 'Posted')

        UNION ALL

        -- ONE LINE PER PAYMENT EVENT. Grouped, not row by row: the customer
        -- made one payment and the statement says so, whether it settled one
        -- sale or five.
        SELECT MIN(pp.paymentdate)::date, 'Payment'::text,
               COALESCE(MIN(pp.paymentnumber),
                        NULLIF(btrim(MIN(pp.reference)), ''),
                        'S' || MIN(pp.saleid)::text)::text,
               ('Payment received'
                || COALESCE(' (' || NULLIF(btrim(MIN(pp.paymentmethod)), '') || ')', '')
                || CASE WHEN COUNT(DISTINCT pp.saleid) > 1
                        THEN ' across ' || COUNT(DISTINCT pp.saleid)::text || ' sales'
                        ELSE ' against sale S' || MIN(pp.saleid)::text
                   END)::text,
               0::numeric(14,2), SUM(pp.amount)::numeric(14,2),
               -- Null on a payment that covers several sales: there is no one
               -- sale to point at, and the drilldown is what answers that.
               CASE WHEN COUNT(DISTINCT pp.saleid) = 1 THEN MIN(pp.saleid) END,
               2, 1,
               pp.paymentgroupid,
               COUNT(DISTINCT pp.poultrypaymentid)::integer,
               MIN(pp.sourcetype)::text
        FROM   poultrypayments pp
        WHERE  pp.farmid = p_farmid AND pp.customerid = p_customerid
          AND  COALESCE(pp.status, 'Posted') = 'Posted'
          AND  (p_from IS NULL OR pp.paymentdate::date >= p_from)
          AND  (p_to   IS NULL OR pp.paymentdate::date <= p_to)
        GROUP  BY pp.paymentgroupid
    )
    -- Chronological, with the opening pinned to the top and a same-day sale
    -- printed before the payment that settles it (sortkey 1 before 2).
    --
    -- The window's ORDER BY and the statement's ORDER BY are the same list on
    -- purpose: a running balance computed in one order and displayed in another
    -- is a statement that does not add up. `reference` is the final tiebreaker
    -- now that two payments on one day can both have a null saleid.
    SELECT l.entrydate, l.entrytype, l.reference, l.description, l.debit, l.credit,
           SUM(l.debit - l.credit) OVER (
               ORDER BY l.pin, l.entrydate, l.sortkey, l.saleid NULLS FIRST, l.reference
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::numeric(14,2),
           l.saleid, l.sortkey, l.paymentgroupid, l.allocationcount, l.sourcetype
    FROM   lines l
    WHERE  l.entrytype <> 'OpeningBalance' OR l.debit <> 0
    ORDER  BY l.pin, l.entrydate, l.sortkey, l.saleid NULLS FIRST, l.reference;
$function$;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
-- The customer with the most payment rows, which is where a grouped payment
-- would show up if one exists.
\echo ''
\echo '=== A statement, end to end ================================================'
SELECT entrydate, entrytype, reference, description, debit, credit, runningbalance,
       allocationcount, sourcetype
FROM   sppoultrycustomerstatement(
        (SELECT pp.farmid::text FROM poultrypayments pp
         WHERE pp.customerid IS NOT NULL
         GROUP BY pp.farmid::text, pp.customerid ORDER BY count(*) DESC LIMIT 1),
        (SELECT pp.customerid FROM poultrypayments pp
         WHERE pp.customerid IS NOT NULL
         GROUP BY pp.farmid::text, pp.customerid ORDER BY count(*) DESC LIMIT 1))
LIMIT 20;

\echo ''
\echo '--- A payment across several sales is ONE line -----------------------------'
SELECT st.reference, st.description, st.credit, st.allocationcount, st.saleid
FROM  (SELECT pp.farmid::text AS farmid, pp.customerid
       FROM   poultrypayments pp
       WHERE  pp.paymentgroupid IS NOT NULL AND pp.customerid IS NOT NULL
       GROUP  BY 1, 2, pp.paymentgroupid
       HAVING count(*) > 1) g
CROSS  JOIN LATERAL sppoultrycustomerstatement(g.farmid, g.customerid) st
WHERE  st.allocationcount > 1;

\echo ''
\echo '--- Closing balance vs the sales it is derived from ------------------------'
-- Two independent derivations of one number, which is the reason this feature
-- exists. The statement walks debits and credits; fnpoultrysalebalance is what
-- the balances page totals per sale. They must agree for every customer.
--
-- Closing is taken as SUM(debit) - SUM(credit) rather than by reading the last
-- row, so the check does not depend on the order rows come back in. Every
-- customer with any sale is checked, settled ones included -- a statement that
-- nets to zero is exactly as much a claim as one that does not.
WITH farm AS (
    SELECT s.farmid::text AS farmid
    FROM   sale s
    WHERE  s.customerid IS NOT NULL
    GROUP  BY 1 ORDER BY count(*) DESC LIMIT 1
), owed AS (
    SELECT f.farmid, s.customerid,
           SUM(fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid))::numeric(14,2) AS balance
    FROM   farm f
    JOIN   sale s ON s.farmid::text = f.farmid AND s.customerid IS NOT NULL
    GROUP  BY f.farmid, s.customerid
)
SELECT o.customerid,
       o.balance   AS from_sales,
       st.closing  AS from_statement,
       CASE WHEN o.balance = st.closing THEN 'OK' ELSE '*** DRIFT ***' END AS verdict
FROM   owed o
CROSS  JOIN LATERAL (
    SELECT COALESCE(SUM(x.debit) - SUM(x.credit), 0)::numeric(14,2) AS closing
    FROM   sppoultrycustomerstatement(o.farmid, o.customerid) x
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

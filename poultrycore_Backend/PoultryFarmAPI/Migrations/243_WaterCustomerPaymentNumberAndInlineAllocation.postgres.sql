-- =============================================================================
-- 243  Water: PAY-0001, and the one-sale payment on the row
-- =============================================================================
-- The water port of 240 and 241, which poultry already runs. One file, because
-- both change spwatercustomerpayment_history and there is no sense dropping and
-- recreating it twice.
--
--   * PAY-0001 per company, in the order payments were made. Assigned by a
--     BEFORE INSERT trigger so every write path gets one and none can forget;
--     the first row of a payment group allocates the number and the rest of the
--     group reuse it, because they are one payment.
--
--   * The payment that settled exactly ONE sale carries that sale, its total
--     and the balance either side of the payment on the row itself, so the
--     Payments Received page shows them without expanding and without a request
--     per row. NULL when the payment covers several sales -- there is no single
--     balance to report, which is what the "—" on screen means.
--
-- NOT PORTED, deliberately: migration 239's cash split. Water customer payments
-- post no cash at all and never have (227's header: water cash arrives through
-- driver returns and daily closing, so a CashIn here would double-count). There
-- is nothing to split.
--
-- HOW TO RUN
--   1. Dry run (default):
--        psql "<conn>" -f 243_WaterCustomerPaymentNumberAndInlineAllocation.postgres.sql
--   2. For real:
--        psql "<conn>" -v apply=true -f 243_...sql
--
--   Apply before deploying the API build that reads the new columns; an older
--   build ignores them.
-- =============================================================================

\set ON_ERROR_STOP on

\if :{?apply}
\else
  \set apply false
\endif

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The column and the counter.
-- -----------------------------------------------------------------------------
ALTER TABLE waterpayments ADD COLUMN IF NOT EXISTS paymentnumber text NULL;

CREATE INDEX IF NOT EXISTS ix_waterpayments_number
    ON waterpayments (farmid, paymentnumber);

CREATE TABLE IF NOT EXISTS waterpaymentnumber (
    farmid     text    PRIMARY KEY,
    lastnumber integer NOT NULL DEFAULT 0
);

-- The UPSERT is the lock: two tills taking payments at the same moment contend
-- on the company's row and are served one after the other.
CREATE OR REPLACE FUNCTION public.fnwaterpaymentnumber_next(p_farmid text)
RETURNS text
LANGUAGE plpgsql
AS $function$
DECLARE
    v_n integer;
BEGIN
    INSERT INTO waterpaymentnumber (farmid, lastnumber)
    VALUES (p_farmid, 1)
    ON CONFLICT (farmid) DO UPDATE
        SET lastnumber = waterpaymentnumber.lastnumber + 1
    RETURNING lastnumber INTO v_n;

    -- Four digits is the floor, not the ceiling.
    RETURN 'PAY-' || lpad(v_n::text, 4, '0');
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. Assign it on the way in.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trgfnwaterpayment_number()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_existing text;
BEGIN
    IF NULLIF(btrim(COALESCE(NEW.paymentnumber, '')), '') IS NOT NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.paymentgroupid IS NOT NULL THEN
        SELECT p.paymentnumber INTO v_existing
        FROM   waterpayments p
        WHERE  p.paymentgroupid = NEW.paymentgroupid
          AND  p.farmid = NEW.farmid
          AND  p.paymentnumber IS NOT NULL
        LIMIT  1;
    END IF;

    NEW.paymentnumber := COALESCE(v_existing, fnwaterpaymentnumber_next(NEW.farmid::text));
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_waterpayment_number ON waterpayments;
CREATE TRIGGER trg_waterpayment_number
    BEFORE INSERT ON waterpayments
    FOR EACH ROW EXECUTE FUNCTION public.trgfnwaterpayment_number();

-- -----------------------------------------------------------------------------
-- 3. Number the payments already taken.
-- -----------------------------------------------------------------------------
-- Chronological per company, so PAY-0001 is that company's first payment.
WITH ordered AS (
    SELECT p.farmid,
           p.paymentgroupid,
           MIN(p.paymentdate)    AS firstdate,
           MIN(p.waterpaymentid) AS firstid
    FROM   waterpayments p
    WHERE  p.paymentgroupid IS NOT NULL
      AND  p.paymentnumber IS NULL
    GROUP  BY p.farmid, p.paymentgroupid
), numbered AS (
    SELECT farmid, paymentgroupid,
           row_number() OVER (PARTITION BY farmid ORDER BY firstdate, firstid) AS n
    FROM   ordered
)
UPDATE waterpayments p
SET    paymentnumber = 'PAY-' || lpad(n.n::text, 4, '0')
FROM   numbered n
WHERE  p.paymentgroupid = n.paymentgroupid
  AND  p.farmid = n.farmid
  AND  p.paymentnumber IS NULL;

-- A row with no group is its own payment; it still deserves a number.
UPDATE waterpayments p
SET    paymentnumber = fnwaterpaymentnumber_next(p.farmid::text)
WHERE  p.paymentnumber IS NULL;

-- Point the counter at the highest number issued, or the next payment reuses
-- one. Only the PAY-#### shape counts toward the watermark.
INSERT INTO waterpaymentnumber (farmid, lastnumber)
SELECT p.farmid::text,
       MAX(NULLIF(regexp_replace(p.paymentnumber, '^PAY-', ''), '')::integer)
FROM   waterpayments p
WHERE  p.paymentnumber ~ '^PAY-[0-9]+$'
GROUP  BY p.farmid::text
ON CONFLICT (farmid) DO UPDATE
    SET lastnumber = GREATEST(waterpaymentnumber.lastnumber, EXCLUDED.lastnumber);

-- -----------------------------------------------------------------------------
-- 4. The history, with the number and the one-sale allocation.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spwatercustomerpayment_history(text, integer, integer, date, date);

CREATE FUNCTION public.spwatercustomerpayment_history(
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
    watercashaccountid integer,
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
    SELECT p.paymentgroupid,
           MIN(p.paymentnumber)::text,
           MIN(p.watercustomerid),
           MIN(c.name)::text,
           MIN(p.paymentdate),
           SUM(p.amount)::numeric(14,2),
           MIN(p.paymentmethod)::text,
           MIN(p.reference)::text,
           MIN(p.note)::text,
           MIN(p.sourcetype)::text,
           MIN(COALESCE(p.status, 'Posted'))::text,
           -- DISTINCT on the payment row, not COUNT(*): the joins below are 1:1
           -- today, and this stays right if one of them ever is not.
           COUNT(DISTINCT p.waterpaymentid)::integer,
           MIN(p.watercashaccountid),
           MIN(p.createdby)::text,
           MIN(p.reversedby)::text,
           MIN(p.reversedat),
           MIN(p.reversalreason)::text,
           CASE WHEN COUNT(DISTINCT p.waterpaymentid) = 1 THEN MIN(p.watersaleid) END,
           CASE WHEN COUNT(DISTINCT p.waterpaymentid) = 1 THEN MIN(s.totalamount)::numeric(14,2) END,
           CASE WHEN COUNT(DISTINCT p.waterpaymentid) = 1 THEN MIN(ca.salebalancebefore)::numeric(14,2) END,
           CASE WHEN COUNT(DISTINCT p.waterpaymentid) = 1 THEN MIN(ca.amountapplied)::numeric(14,2) END,
           CASE WHEN COUNT(DISTINCT p.waterpaymentid) = 1 THEN MIN(ca.salebalanceafter)::numeric(14,2) END
    FROM   waterpayments p
    LEFT   JOIN watercustomers c ON c.watercustomerid = p.watercustomerid AND c.farmid = p.farmid
    LEFT   JOIN watersales s     ON s.watersaleid = p.watersaleid AND s.farmid = p.farmid
    -- Payments taken before 227 have no allocation row; those columns come back
    -- NULL and the page falls back to what it can show.
    LEFT   JOIN customerpaymentallocation ca
           ON  ca.module = 'water'
           AND ca.paymentid = p.waterpaymentid
           AND ca.farmid = p.farmid
    WHERE  p.farmid = p_farmid
      AND  (p_customerid IS NULL OR p.watercustomerid = p_customerid)
      AND  (p_from IS NULL OR p.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR p.paymentdate::date <= p_to)
      AND  (p_saleid IS NULL OR EXISTS (
              SELECT 1 FROM waterpayments p2
              WHERE p2.paymentgroupid = p.paymentgroupid AND p2.watersaleid = p_saleid))
    GROUP  BY p.paymentgroupid
    ORDER  BY MIN(p.paymentdate) DESC;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Verification.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== Numbers issued ========================================================='
SELECT p.farmid::text          AS farmid,
       count(DISTINCT p.paymentgroupid) AS payments,
       count(DISTINCT p.paymentnumber)  AS numbers,
       min(p.paymentnumber)    AS first,
       max(p.paymentnumber)    AS last,
       CASE WHEN count(DISTINCT p.paymentgroupid) = count(DISTINCT p.paymentnumber)
            THEN 'OK' ELSE '*** ONE NUMBER PER PAYMENT VIOLATED ***' END AS verdict
FROM   waterpayments p
GROUP  BY p.farmid::text
ORDER  BY 1;

\echo ''
\echo '--- Unnumbered rows, and numbers spanning two payments (both must be 0) ----'
SELECT (SELECT count(*) FROM waterpayments WHERE paymentnumber IS NULL) AS unnumbered,
       (SELECT count(*) FROM (
            SELECT p.farmid, p.paymentnumber
            FROM   waterpayments p
            WHERE  p.paymentgroupid IS NOT NULL
            GROUP  BY 1, 2
            HAVING count(DISTINCT p.paymentgroupid) > 1) x) AS shared_numbers;

\echo ''
\echo '--- One-sale payments carry their allocation, multi-sale do not ------------'
SELECT CASE WHEN allocationcount = 1 THEN 'one sale' ELSE 'several sales' END AS kind,
       count(*)             AS payments,
       count(saleid)        AS with_saleid,
       count(balancebefore) AS with_balances
FROM   spwatercustomerpayment_history(
         (SELECT p.farmid::text FROM waterpayments p
          GROUP BY p.farmid::text ORDER BY count(*) DESC LIMIT 1))
GROUP  BY 1
ORDER  BY 1;

\echo ''
\echo '--- What the page will show (10 most recent) -------------------------------'
SELECT paymentnumber, customername, totalamount, allocationcount,
       saleid, saletotal, balancebefore, balanceafter, status
FROM   spwatercustomerpayment_history(
         (SELECT p.farmid::text FROM waterpayments p
          GROUP BY p.farmid::text ORDER BY count(*) DESC LIMIT 1))
LIMIT  10;

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

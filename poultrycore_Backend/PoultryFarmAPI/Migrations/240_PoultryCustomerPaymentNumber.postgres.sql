-- =============================================================================
-- 240  PAY-0001: a real number for a customer payment
-- =============================================================================
-- A payment event is a paymentgroupid -- a uuid. That is a fine key and a
-- terrible thing to say out loud. "Which payment?" "The one ending 4f2a" is not
-- how anyone discusses money, and the Payments Received page was reduced to
-- printing the first eight characters of it.
--
-- This gives every payment a number: PAY-0001, per company, in the order the
-- payments were made.
--
-- WHERE THE NUMBER LIVES. On poultrypayments, alongside the group id -- every
-- row of one group carries the same number, because they are one payment. The
-- alternative, a table of payment events, is the bigger refactor this codebase
-- deliberately did not do in 223: the GROUP is the payment, and the number is
-- an attribute of the group.
--
-- HOW IT IS ASSIGNED. A BEFORE INSERT trigger, not a change to
-- sppoultrycustomerpayment_record. Every path that writes a payment row --
-- sale entry, bulk payment, the 238 backfill, anything added later -- goes
-- through the trigger and cannot forget. The first row of a group allocates the
-- number; the rest of the group find it and reuse it.
--
-- The counter is a row per company, incremented with an UPSERT that returns the
-- new value, so two people taking payments at the same time cannot be handed
-- the same number -- the second waits on the first's row lock.
--
-- HOW TO RUN
--   1. Dry run (default), prints the numbering it would assign, rolls back:
--        psql "<conn>" -f 240_PoultryCustomerPaymentNumber.postgres.sql
--   2. For real:
--        psql "<conn>" -v apply=true -f 240_PoultryCustomerPaymentNumber.postgres.sql
--
--   Apply this BEFORE deploying the API build that reads `paymentnumber`, or
--   the reader asks for a column that is not there yet. The other order is
--   safe: the column is ignored by an older build.
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
ALTER TABLE poultrypayments ADD COLUMN IF NOT EXISTS paymentnumber text NULL;

CREATE INDEX IF NOT EXISTS ix_poultrypayments_number
    ON poultrypayments (farmid, paymentnumber);

CREATE TABLE IF NOT EXISTS poultrypaymentnumber (
    farmid     text    PRIMARY KEY,
    lastnumber integer NOT NULL DEFAULT 0
);

-- -----------------------------------------------------------------------------
-- 2. Allocate the next number for a company.
-- -----------------------------------------------------------------------------
-- The UPSERT is the lock: two concurrent callers contend on the company's row
-- and are served one after the other, so the sequence has no duplicates and no
-- gaps of its own making.
CREATE OR REPLACE FUNCTION public.fnpoultrypaymentnumber_next(p_farmid text)
RETURNS text
LANGUAGE plpgsql
AS $function$
DECLARE
    v_n integer;
BEGIN
    INSERT INTO poultrypaymentnumber (farmid, lastnumber)
    VALUES (p_farmid, 1)
    ON CONFLICT (farmid) DO UPDATE
        SET lastnumber = poultrypaymentnumber.lastnumber + 1
    RETURNING lastnumber INTO v_n;

    -- Four digits is the floor, not the ceiling: PAY-10000 follows PAY-9999
    -- rather than wrapping or truncating.
    RETURN 'PAY-' || lpad(v_n::text, 4, '0');
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Assign it on the way in.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trgfnpoultrypayment_number()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_existing text;
BEGIN
    IF NULLIF(btrim(COALESCE(NEW.paymentnumber, '')), '') IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- One payment, one number: the rest of the group reuse what the first row
    -- of it was given.
    IF NEW.paymentgroupid IS NOT NULL THEN
        SELECT pp.paymentnumber INTO v_existing
        FROM   poultrypayments pp
        WHERE  pp.paymentgroupid = NEW.paymentgroupid
          AND  pp.farmid = NEW.farmid
          AND  pp.paymentnumber IS NOT NULL
        LIMIT  1;
    END IF;

    NEW.paymentnumber := COALESCE(v_existing, fnpoultrypaymentnumber_next(NEW.farmid::text));
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_poultrypayment_number ON poultrypayments;
CREATE TRIGGER trg_poultrypayment_number
    BEFORE INSERT ON poultrypayments
    FOR EACH ROW EXECUTE FUNCTION public.trgfnpoultrypayment_number();

-- -----------------------------------------------------------------------------
-- 4. Number the payments already taken.
-- -----------------------------------------------------------------------------
-- Chronological per company, so PAY-0001 is genuinely that company's first
-- payment and the numbers read in the order the money arrived. Ties break on
-- the payment id, which is the order they were written.
WITH ordered AS (
    SELECT pp.farmid,
           pp.paymentgroupid,
           MIN(pp.paymentdate)      AS firstdate,
           MIN(pp.poultrypaymentid) AS firstid
    FROM   poultrypayments pp
    WHERE  pp.paymentgroupid IS NOT NULL
      AND  pp.paymentnumber IS NULL
    GROUP  BY pp.farmid, pp.paymentgroupid
), numbered AS (
    SELECT farmid, paymentgroupid,
           row_number() OVER (PARTITION BY farmid ORDER BY firstdate, firstid) AS n
    FROM   ordered
)
UPDATE poultrypayments pp
SET    paymentnumber = 'PAY-' || lpad(n.n::text, 4, '0')
FROM   numbered n
WHERE  pp.paymentgroupid = n.paymentgroupid
  AND  pp.farmid = n.farmid
  AND  pp.paymentnumber IS NULL;

-- A row with no group at all is its own payment; it still deserves a number.
UPDATE poultrypayments pp
SET    paymentnumber = fnpoultrypaymentnumber_next(pp.farmid::text)
WHERE  pp.paymentnumber IS NULL;

-- Point the counter at the highest number handed out, or the next payment
-- reuses one. Only the PAY-#### shape is considered: anything else was not
-- issued by this scheme and must not raise the watermark.
INSERT INTO poultrypaymentnumber (farmid, lastnumber)
SELECT pp.farmid::text,
       MAX(NULLIF(regexp_replace(pp.paymentnumber, '^PAY-', ''), '')::integer)
FROM   poultrypayments pp
WHERE  pp.paymentnumber ~ '^PAY-[0-9]+$'
GROUP  BY pp.farmid::text
ON CONFLICT (farmid) DO UPDATE
    SET lastnumber = GREATEST(poultrypaymentnumber.lastnumber, EXCLUDED.lastnumber);

-- -----------------------------------------------------------------------------
-- 5. Hand it to the reader.
-- -----------------------------------------------------------------------------
-- The return type gains a column, which CREATE OR REPLACE cannot do -- the
-- function has to go first. The C# reads by column name, so the new column is
-- invisible to a build that has not learned about it yet.
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
    reversalreason  text)
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
           COUNT(*)::integer,
           MIN(pp.poultrycashaccountid),
           MIN(pp.createdby)::text,
           MIN(pp.reversedby)::text,
           MIN(pp.reversedat),
           MIN(pp.reversalreason)::text
    FROM   poultrypayments pp
    LEFT   JOIN customer c ON c.customerid = pp.customerid AND c.farmid = pp.farmid
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
-- 6. Verification.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== Numbers issued ========================================================='
SELECT pp.farmid::text          AS farmid,
       count(DISTINCT pp.paymentgroupid) AS payments,
       count(DISTINCT pp.paymentnumber)  AS numbers,
       min(pp.paymentnumber)    AS first,
       max(pp.paymentnumber)    AS last,
       CASE WHEN count(DISTINCT pp.paymentgroupid) = count(DISTINCT pp.paymentnumber)
            THEN 'OK' ELSE '*** ONE NUMBER PER PAYMENT VIOLATED ***' END AS verdict
FROM   poultrypayments pp
GROUP  BY pp.farmid::text
ORDER  BY 1;

\echo ''
\echo '--- Unnumbered rows (must be 0) --------------------------------------------'
SELECT count(*) AS unnumbered FROM poultrypayments WHERE paymentnumber IS NULL;

\echo ''
\echo '--- A number must never span two payments ----------------------------------'
SELECT pp.farmid::text AS farmid, pp.paymentnumber, count(DISTINCT pp.paymentgroupid) AS payments
FROM   poultrypayments pp
WHERE  pp.paymentgroupid IS NOT NULL
GROUP  BY 1, 2
HAVING count(DISTINCT pp.paymentgroupid) > 1;

\echo ''
\echo '--- The counter sits at or above the highest number issued -----------------'
SELECT n.farmid, n.lastnumber,
       (SELECT MAX(NULLIF(regexp_replace(pp.paymentnumber, '^PAY-', ''), '')::integer)
        FROM   poultrypayments pp
        WHERE  pp.farmid::text = n.farmid AND pp.paymentnumber ~ '^PAY-[0-9]+$') AS highest_issued
FROM   poultrypaymentnumber n
ORDER  BY n.farmid;

\echo ''
\echo '--- What the page will show (10 most recent) -------------------------------'
SELECT paymentnumber, customername, totalamount, allocationcount, sourcetype, status
FROM   sppoultrycustomerpayment_history(
         (SELECT pp.farmid::text FROM poultrypayments pp
          GROUP BY pp.farmid::text ORDER BY count(*) DESC LIMIT 1))
LIMIT  10;

\if :apply
    COMMIT;
    \echo ''
    \echo '>>> COMMITTED. Deploy the API build that reads `paymentnumber` next.'
\else
    ROLLBACK;
    \echo ''
    \echo '>>> DRY RUN -- rolled back.'
    \echo '>>> Re-run with  -v apply=true  to write it.'
\endif

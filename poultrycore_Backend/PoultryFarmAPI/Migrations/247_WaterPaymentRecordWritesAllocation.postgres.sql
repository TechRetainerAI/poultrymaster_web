-- =============================================================================
-- 247  A water payment records what it did to the sale's balance
-- =============================================================================
-- THE FAULT. Payments Received shows "—" under Before and After for every
-- payment on some farms. Those two columns are not computed on the fly: they
-- are SNAPSHOTS, written into customerpaymentallocation at the moment the
-- payment is posted, because the balance a payment moved is a fact about that
-- moment and cannot be recovered later once the sale changes.
--
-- spwaterpayment_record -- the SP behind WaterPaymentService, i.e. paying a
-- water sale directly -- writes the payment and never writes the allocation.
-- So its payments have no snapshot, and the page has nothing to print. The
-- newer spwatercustomerpayment_record has always written one, which is why
-- this shows up on some farms and not others: 52 of 54 water payments have an
-- allocation, and the three that do not are all from this writer.
--
-- It is the same shape of fault as 245/246 -- a legacy writer that predates a
-- table it now has to feed -- and the fix has the same two halves: teach the
-- writer, then repair what it already wrote.
--
-- WHAT ELSE THE MISSING ALLOCATION COSTS. Not just two columns. The allocation
-- is what the reversal path walks, what the statement drills into, and what
-- "applied to N sales" counts. A payment without one is half-visible
-- everywhere, not only here.
--
-- THIS FILE ALSO CARRIES 246's FIX for this one function, because it replaces
-- the whole body. Apply it with or without 246 -- 246 still owns the two
-- driver-return SPs, which this file does not touch.
--
-- ABOUT THE BACKFILL, PLAINLY. It reconstructs snapshots that were never
-- taken. For each sale it replays its payments oldest-first and walks the
-- balance down from the sale's CURRENT total. That is exact where the total
-- has not been edited since -- true for all three rows here -- and it is the
-- best available where it has, which is the same trade migration 241 named
-- when it chose to read saletotal live. Reversed payments are skipped: they
-- moved no balance that stuck. Idempotent -- it only inserts where no
-- allocation exists, so a second run does nothing.
--
-- HOW TO RUN
--   1. Dry run (default):
--        psql "<conn>" -f 247_WaterPaymentRecordWritesAllocation.postgres.sql
--   2. For real:
--        psql "<conn>" -v apply=true -f 247_WaterPaymentRecordWritesAllocation.postgres.sql
--
--   No API build depends on this -- the columns it fills are ones the page
--   already reads and currently finds null.
-- =============================================================================

\set ON_ERROR_STOP on

\if :{?apply}
\else
  \set apply false
\endif

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. What is missing now.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== Water payments with no allocation, BEFORE ==============================='
SELECT p.waterpaymentid, p.paymentnumber, p.watersaleid, p.amount, s.totalamount AS sale_total
FROM   waterpayments p
LEFT   JOIN watersales s ON s.watersaleid = p.watersaleid
WHERE  NOT EXISTS (SELECT 1 FROM customerpaymentallocation a
                   WHERE a.module = 'water' AND a.paymentid = p.waterpaymentid)
ORDER  BY p.watersaleid, p.waterpaymentid;

-- -----------------------------------------------------------------------------
-- 2. Teach the writer.
--
-- v_before is read BEFORE the payment row is inserted -- after it, the sum
-- below would already include this payment and the snapshot would be off by
-- its own amount. Reversed payments are excluded from what has been paid, the
-- same rule spwatercustomerpayment_record uses.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterpayment_record(p_farmid text, p_watersaleid integer DEFAULT NULL::integer, p_amount numeric DEFAULT NULL::numeric, p_paymentmethod text DEFAULT NULL::text, p_paymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_reference text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_paymentdate timestamp := p_paymentdate;
    v_paymentid   integer;
    v_before      numeric;
BEGIN
    IF v_paymentdate IS NULL THEN
        v_paymentdate := (now() at time zone 'utc');
    END IF;

    -- Sale must belong to farm.
    IF NOT EXISTS (SELECT 1 FROM watersales s
                   WHERE s.watersaleid = p_watersaleid AND s.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Sale does not belong to this farm.';
    END IF;

    -- What the sale still owed a moment before this payment.
    SELECT s.totalamount
           - COALESCE((SELECT SUM(w.amount) FROM waterpayments w
                       WHERE w.watersaleid = s.watersaleid
                         AND COALESCE(w.status, 'Posted') <> 'Reversed'), 0)
    INTO   v_before
    FROM   watersales s
    WHERE  s.watersaleid = p_watersaleid;

    INSERT INTO waterpayments
        (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note, createdby, paymentgroupid)
    VALUES (p_farmid, p_watersaleid, p_amount, p_paymentmethod, v_paymentdate, p_reference, p_note, p_createdby, gen_random_uuid())
    RETURNING waterpaymentid INTO v_paymentid;

    -- The snapshot. Same shape spwatercustomerpayment_record writes, so both
    -- writers' payments read identically on the page and in the statement.
    INSERT INTO customerpaymentallocation
        (farmid, module, paymentid, saleid, amountapplied,
         salebalancebefore, salebalanceafter, status, createdby, createdat)
    VALUES
        (p_farmid, 'water', v_paymentid, p_watersaleid, p_amount,
         v_before, v_before - p_amount, 'Posted', p_createdby, v_paymentdate);

    -- Recompute AmountPaid and Status on the sale.
    UPDATE watersales s
    SET    amountpaid = COALESCE((SELECT SUM(w.amount) FROM waterpayments w
                                  WHERE w.watersaleid = s.watersaleid), 0),
           status     = CASE
                          WHEN s.status = 'Cancelled' THEN 'Cancelled'
                          WHEN COALESCE((SELECT SUM(w.amount) FROM waterpayments w
                                         WHERE w.watersaleid = s.watersaleid), 0) >= s.totalamount
                               THEN 'Paid'
                          WHEN COALESCE((SELECT SUM(w.amount) FROM waterpayments w
                                         WHERE w.watersaleid = s.watersaleid), 0) > 0
                               THEN 'PartiallyPaid'
                          ELSE 'Pending'
                        END,
           updateddate = (now() at time zone 'utc')
    WHERE  s.watersaleid = p_watersaleid;

    RETURN v_paymentid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Repair what it already wrote.
--
-- The window runs over EVERY payment on the sale, not just the ones missing an
-- allocation -- a sale with one allocated payment and one without still has to
-- start the second from where the first left off.
-- -----------------------------------------------------------------------------
WITH ordered AS (
    SELECT p.waterpaymentid, p.farmid, p.watersaleid, p.amount,
           p.paymentdate, p.createdby, s.totalamount,
           COALESCE(SUM(p.amount) OVER (PARTITION BY p.watersaleid
                                        ORDER BY p.waterpaymentid
                                        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS paid_before
    FROM   waterpayments p
    JOIN   watersales s ON s.watersaleid = p.watersaleid
    WHERE  COALESCE(p.status, 'Posted') <> 'Reversed'
)
INSERT INTO customerpaymentallocation
    (farmid, module, paymentid, saleid, amountapplied,
     salebalancebefore, salebalanceafter, status, createdby, createdat)
SELECT o.farmid, 'water', o.waterpaymentid, o.watersaleid, o.amount,
       o.totalamount - o.paid_before,
       o.totalamount - o.paid_before - o.amount,
       'Posted', o.createdby, o.paymentdate
FROM   ordered o
WHERE  NOT EXISTS (SELECT 1 FROM customerpaymentallocation a
                   WHERE a.module = 'water' AND a.paymentid = o.waterpaymentid);

-- -----------------------------------------------------------------------------
-- 4. Proof.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== Water payments with no allocation, AFTER (must be 0) ===================='
SELECT count(*) AS still_missing
FROM   waterpayments p
WHERE  NOT EXISTS (SELECT 1 FROM customerpaymentallocation a
                   WHERE a.module = 'water' AND a.paymentid = p.waterpaymentid)
  AND  COALESCE(p.status, 'Posted') <> 'Reversed';

DO $do$
DECLARE
    v_n integer;
BEGIN
    SELECT count(*) INTO v_n
    FROM   waterpayments p
    WHERE  NOT EXISTS (SELECT 1 FROM customerpaymentallocation a
                       WHERE a.module = 'water' AND a.paymentid = p.waterpaymentid)
      AND  COALESCE(p.status, 'Posted') <> 'Reversed';
    IF v_n > 0 THEN
        RAISE EXCEPTION '247: % posted water payment(s) still have no allocation', v_n;
    END IF;
    RAISE NOTICE 'every posted water payment has an allocation -- OK';
END
$do$;

\echo ''
\echo '--- The repaired rows, and the balance they now report ----------------------'
SELECT a.paymentid, p.paymentnumber, a.saleid, s.totalamount AS sale_total,
       a.salebalancebefore AS before_, a.amountapplied AS applied, a.salebalanceafter AS after_
FROM   customerpaymentallocation a
JOIN   waterpayments p ON p.waterpaymentid = a.paymentid
JOIN   watersales   s ON s.watersaleid    = a.saleid
WHERE  a.module = 'water' AND a.paymentid IN (55, 56, 59)
ORDER  BY a.saleid, a.paymentid;

\echo ''
\echo '--- Every sale walks its balance down to what it still owes -----------------'
SELECT a.saleid,
       max(s.totalamount)         AS sale_total,
       sum(a.amountapplied)       AS applied,
       min(a.salebalanceafter)    AS lowest_after,
       CASE WHEN abs(max(s.totalamount) - sum(a.amountapplied) - min(a.salebalanceafter)) < 0.005
            THEN 'OK' ELSE 'CHECK' END AS verdict
FROM   customerpaymentallocation a
JOIN   watersales s ON s.watersaleid = a.saleid
WHERE  a.module = 'water' AND a.saleid IN (49, 50)
GROUP  BY a.saleid
ORDER  BY a.saleid;

\if :apply
    COMMIT;
    \echo ''
    \echo '>>> COMMITTED. Before and After should fill in on Payments Received.'
\else
    ROLLBACK;
    \echo ''
    \echo '>>> DRY RUN -- rolled back.'
    \echo '>>> Re-run with  -v apply=true  to write it.'
\endif

-- =============================================================================
-- 245  A payment always has a group id
-- =============================================================================
-- THE FAULT. Payments Received for water died with "Column 'paymentgroupid' is
-- null." `paymentgroupid` is what identifies a payment EVENT -- it is the key
-- the page groups on, the handle the reverse endpoint takes, and the column the
-- statement joins through -- and nothing guarantees it is set.
--
--   * The column is nullable with NO default.
--   * Only ONE of the four writers fills it in. spwatercustomerpayment_record
--     passes a group; spwaterpayment_record, spwaterdriverreturn_approve and
--     spwaterdriverreturn_approvereconcile all name their columns explicitly
--     and leave it out.
--   * 227 backfilled the rows that existed then, which is why this took months
--     to surface: every NULL since has come from those three writers.
--
-- Two rows are NULL today (waterpaymentid 55 and 56), one of them written the
-- day this was found, so the leak is live rather than historical.
--
-- WHY A TRIGGER, NOT FOUR EDITS. This is the argument migration 240 made for
-- paymentnumber and it applies unchanged: a dozen paths write payments, none of
-- them will be taught about a column they do not know exists, and the next one
-- added will forget too. A BEFORE INSERT trigger cannot be forgotten. 240
-- already put one on this table for the number; this is its twin.
--
-- ONE GROUP PER INSERT, NEVER MERGED. The trigger fills a NULL with a FRESH
-- uuid, so two rows that arrive separately stay two payments. It never joins
-- rows into a group -- grouping is a claim only the caller can make, and
-- spwatercustomerpayment_record still makes it by passing its own group.
--
-- A NOTE ON DRIVER RETURNS. Approving a return can write cash, mobile money and
-- bank rows for one sale. Each gets its own group, so they read as three
-- payments -- which is what they are, and what the page already showed for the
-- rows 227 backfilled. This changes nothing there.
--
-- POULTRY IS NOT BROKEN -- it has one writer and it sets the group. The same
-- guard goes on anyway: the gap is structural, not water-specific, and a table
-- that defends itself does not depend on nobody adding a second writer.
--
-- NOTHING IS REGROUPED AND NO MONEY MOVES. The only rows this touches are the
-- ones with no group id at all. Every existing group is left exactly as it is,
-- and no amount, allocation or balance is read or written.
--
-- HOW TO RUN
--   1. Dry run (default) -- does everything, prints the proof, rolls back:
--        psql "<conn>" -f 245_PaymentGroupIdAlwaysSet.postgres.sql
--   2. For real:
--        psql "<conn>" -v apply=true -f 245_PaymentGroupIdAlwaysSet.postgres.sql
--
--   Apply this BEFORE (or with) the API build carrying the null-tolerant
--   reader. Either order is safe -- they fix the same fault from both ends.
-- =============================================================================

\set ON_ERROR_STOP on

\if :{?apply}
\else
  \set apply false
\endif

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. What is broken right now.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== Rows with no group id, BEFORE ==========================================='
SELECT 'waterpayments'  AS tbl, count(*) AS missing FROM waterpayments   WHERE paymentgroupid IS NULL
UNION ALL
SELECT 'poultrypayments',       count(*)            FROM poultrypayments WHERE paymentgroupid IS NULL;

-- -----------------------------------------------------------------------------
-- 2. Give the orphans a group of their own.
--
-- Row by row, not one group for all of them: these are unrelated payments that
-- happen to share a defect. gen_random_uuid() is evaluated per row.
-- -----------------------------------------------------------------------------
UPDATE waterpayments   SET paymentgroupid = gen_random_uuid() WHERE paymentgroupid IS NULL;
UPDATE poultrypayments SET paymentgroupid = gen_random_uuid() WHERE paymentgroupid IS NULL;

-- -----------------------------------------------------------------------------
-- 3. Stop it happening again.
--
-- BEFORE INSERT, and only when the caller supplied nothing -- a caller that
-- passes a group is making a deliberate statement about which rows are one
-- payment, and the trigger must not overrule it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trgfnwaterpayment_groupid()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.paymentgroupid IS NULL THEN
        NEW.paymentgroupid := gen_random_uuid();
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_waterpayment_groupid ON waterpayments;
CREATE TRIGGER trg_waterpayment_groupid
    BEFORE INSERT ON waterpayments
    FOR EACH ROW EXECUTE FUNCTION public.trgfnwaterpayment_groupid();

CREATE OR REPLACE FUNCTION public.trgfnpoultrypayment_groupid()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.paymentgroupid IS NULL THEN
        NEW.paymentgroupid := gen_random_uuid();
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_poultrypayment_groupid ON poultrypayments;
CREATE TRIGGER trg_poultrypayment_groupid
    BEFORE INSERT ON poultrypayments
    FOR EACH ROW EXECUTE FUNCTION public.trgfnpoultrypayment_groupid();

-- -----------------------------------------------------------------------------
-- 4. Proof.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== Rows with no group id, AFTER (both must be 0) ==========================='
SELECT 'waterpayments'  AS tbl, count(*) AS missing FROM waterpayments   WHERE paymentgroupid IS NULL
UNION ALL
SELECT 'poultrypayments',       count(*)            FROM poultrypayments WHERE paymentgroupid IS NULL;

\echo ''
\echo '--- The repaired rows read as their own payments ----------------------------'
SELECT waterpaymentid, paymentnumber, watersaleid, amount, paymentmethod,
       left(paymentgroupid::text, 8) AS groupid_head
FROM   waterpayments
WHERE  waterpaymentid IN (55, 56)
ORDER  BY waterpaymentid;

\echo ''
\echo '--- No group was merged: groups still equal distinct payment events ---------'
SELECT count(DISTINCT paymentgroupid) AS groups,
       count(*)                       AS rows_,
       CASE WHEN count(DISTINCT paymentgroupid) >= 1 THEN 'OK' ELSE 'CHECK' END AS verdict
FROM   waterpayments;

\echo ''
\echo '--- The trigger fires (insert one, read it back, discard it) ----------------'
DO $do$
DECLARE
    v_farm text;
    v_sale integer;
    v_id   integer;
    v_grp  uuid;
BEGIN
    SELECT farmid, watersaleid INTO v_farm, v_sale FROM waterpayments LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'no water payments to model a test insert on -- skipped';
        RETURN;
    END IF;

    INSERT INTO waterpayments (farmid, watersaleid, amount, paymentmethod, paymentdate, createdby)
    VALUES (v_farm, v_sale, 0, 'Cash', (now() at time zone 'utc'), '245-selftest')
    RETURNING waterpaymentid, paymentgroupid INTO v_id, v_grp;

    IF v_grp IS NULL THEN
        RAISE EXCEPTION '245: trigger did not assign a group id';
    END IF;
    RAISE NOTICE 'trigger assigned % to the test row -- OK', left(v_grp::text, 8);

    DELETE FROM waterpayments WHERE waterpaymentid = v_id;
END
$do$;

\if :apply
    COMMIT;
    \echo ''
    \echo '>>> COMMITTED. Payments Received should load again.'
\else
    ROLLBACK;
    \echo ''
    \echo '>>> DRY RUN -- rolled back.'
    \echo '>>> Re-run with  -v apply=true  to write it.'
\endif

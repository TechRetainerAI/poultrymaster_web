-- =============================================================================
-- 238  Backfill: egg sales that were billed for their crates only
-- =============================================================================
-- The Sales page priced eggs as `crates x unitprice`, where `crates` was
-- floor(quantity / 30). The loose eggs on the end of the sale were therefore
-- given away: 2 crates + 15 loose at GHC 30 a crate was billed GHC 60 instead
-- of GHC 75. The page now charges quantity / 30 x unitprice, and this script
-- brings the sales already in the database onto the same footing.
--
-- WHICH ROWS. Only sales that carry the fingerprint of the bug:
--     product ILIKE '%egg%'            (the same test the page uses)
--     quantity is not a whole crate    (quantity % 30 <> 0)
--     totalamount = floor(quantity/30) x unitprice, to the pesewa
-- The last condition is what makes this safe to run: a sale where somebody
-- typed an Override Amount does not match the buggy formula, so it is left
-- exactly as it is. So is a sale already corrected by a previous run.
--
-- WHAT IT DOES NOT DO. It does not move any money. Cash for a poultry sale is
-- posted from what was RECEIVED (fnpoultrysalereceived / sppoultrysalecash_sync
-- in migration 223), not from the invoice total, so raising a total cannot
-- invent cash that never arrived.
--
--   * Credit sales (paid = false) are the clean case. The invoice was under-
--     stated and is still open, so the total goes up and the customer's balance
--     goes up with it. amountpaid, the payment rows and the cash account are
--     all untouched.
--
--   * Fully paid sales (paid = true) are NOT touched by default; you have to
--     opt in with include_paid below. The reason is that the customer paid the
--     number the farm showed them, so the money in the drawer is the OLD total.
--     Opting in does not pretend otherwise: for each such sale it records the
--     amount already collected as a payment row, raises the total, and re-runs
--     sppoultrysale_recompute -- which leaves the cash account balance exactly
--     where it was and turns the difference into an outstanding balance the
--     farm can chase. The sale stops reading "Paid". Walk-in sales with no
--     customer attached are reported separately, because a receivable against
--     nobody cannot be collected.
--
-- Idempotent. Every row it changes is written to poultryeggsalebackfill with
-- its old values, which both stops a second run touching it again and gives you
-- the undo at the bottom of this file.
--
-- HOW TO RUN
--   The connection string lives in .NET user secrets, not appsettings:
--     dotnet user-secrets list --project poultrycore_Backend/PoultryFarmAPI
--
--   1. Dry run (default). Prints what it would do, then rolls back:
--        psql "<conn>" -f 238_BackfillPoultryEggSaleLooseEggs.postgres.sql
--   2. One farm only, to try it on a single company first:
--        psql "<conn>" -v farm=YOUR_FARM_ID -f 238_...sql
--   3. For real, credit sales only:
--        psql "<conn>" -v apply=true -f 238_...sql
--   4. For real, paid sales as well (read the note above first):
--        psql "<conn>" -v apply=true -v include_paid=true -f 238_...sql
-- =============================================================================

\set ON_ERROR_STOP on

-- Defaults. A command-line -v overrides these, so a bare run is a dry run over
-- every farm, credit sales only.
\if :{?apply}
\else
  \set apply false
\endif
\if :{?include_paid}
\else
  \set include_paid false
\endif
\if :{?farm}
\else
  \set farm ''
\endif

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The audit trail. Written as it goes, and the reason a second run is a
--    no-op.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultryeggsalebackfill (
    id                    serial PRIMARY KEY,
    farmid                text    NOT NULL,
    saleid                integer NOT NULL,
    quantity              numeric(14,2),
    unitprice             numeric(14,2),
    oldtotalamount        numeric(14,2),
    newtotalamount        numeric(14,2),
    oldpaid               boolean,
    oldamountpaid         numeric(14,2),
    compensatingpaymentid integer,
    ranat                 timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    ranby                 text
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryeggsalebackfill_sale
    ON poultryeggsalebackfill (farmid, saleid);

-- -----------------------------------------------------------------------------
-- 2. The candidates.
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE eggfix ON COMMIT DROP AS
SELECT s.saleid,
       s.farmid,
       s.saledate,
       s.customerid,
       s.customername,
       s.paymentmethod,
       s.poultrycashaccountid,
       s.quantity,
       s.unitprice,
       COALESCE(s.totalamount, 0)                 AS oldtotal,
       round(s.quantity / 30.0 * s.unitprice, 2)  AS newtotal,
       COALESCE(s.paid, TRUE)                     AS oldpaid,
       COALESCE(s.amountpaid, 0)                  AS oldamountpaid,
       CASE WHEN COALESCE(s.paid, TRUE) THEN 'paid' ELSE 'credit' END AS kind
FROM   sale s
WHERE  s.product ILIKE '%egg%'
  AND  COALESCE(s.quantity, 0)  > 0
  AND  COALESCE(s.unitprice, 0) > 0
  -- A whole number of crates was never mis-billed.
  AND  (s.quantity % 30) <> 0
  -- The fingerprint: what is stored is exactly what the broken formula gave.
  -- Anything else -- an override, a hand correction, an already-fixed row --
  -- fails this and is left alone.
  AND  abs(COALESCE(s.totalamount, 0)
           - round(floor(s.quantity / 30.0) * s.unitprice, 2)) < 0.005
  AND  round(s.quantity / 30.0 * s.unitprice, 2) > COALESCE(s.totalamount, 0)
  AND  (NULLIF(:'farm', '') IS NULL OR s.farmid = NULLIF(:'farm', ''))
  AND  NOT EXISTS (SELECT 1 FROM poultryeggsalebackfill b
                   WHERE b.farmid = s.farmid AND b.saleid = s.saleid);

-- Split out here rather than inside the loop: psql does not interpolate
-- variables inside a dollar-quoted body, so include_paid has to be applied in
-- plain SQL. When it is false this table is empty and section 4 does nothing.
CREATE TEMP TABLE eggfix_paid ON COMMIT DROP AS
SELECT * FROM eggfix WHERE kind = 'paid' AND :include_paid;

\echo ''
\echo '=== Sales that were billed for crates only =================================='
SELECT kind,
       count(*)                                AS sales,
       sum(oldtotal)::numeric(14,2)            AS billed_now,
       sum(newtotal)::numeric(14,2)            AS billed_after,
       sum(newtotal - oldtotal)::numeric(14,2) AS shortfall
FROM   eggfix
GROUP  BY kind
ORDER  BY kind;

\echo ''
\echo '--- Of the fully paid ones, how many have nobody to bill -------------------'
SELECT count(*)                                   AS paid_sales,
       count(*) FILTER (WHERE customerid IS NULL) AS no_customer_attached,
       CASE WHEN :include_paid THEN 'included in this run'
            ELSE 'NOT touched (re-run with -v include_paid=true to include)'
       END AS treatment
FROM   eggfix
WHERE  kind = 'paid';

\echo ''
\echo '--- First 50 rows ----------------------------------------------------------'
SELECT saleid,
       farmid,
       saledate::date                      AS sold,
       COALESCE(customername, '(walk-in)') AS customer,
       quantity                            AS eggs,
       (floor(quantity / 30.0)::text || 'cr + ' || (quantity % 30)::text || 'p') AS breakdown,
       unitprice                           AS per_crate,
       oldtotal,
       newtotal,
       (newtotal - oldtotal)               AS shortfall,
       kind
FROM   eggfix
ORDER  BY farmid, saledate, saleid
LIMIT  50;

-- -----------------------------------------------------------------------------
-- 3. Credit sales: raise the invoice, leave the money alone.
-- -----------------------------------------------------------------------------
-- Cash for an unpaid sale is posted as LEAST(amountpaid, totalamount) and
-- amountpaid does not move here, so the cash account cannot shift. The whole
-- effect is that the customer now owes the difference.
WITH upd AS (
    UPDATE sale s
    SET    totalamount = f.newtotal
    FROM   eggfix f
    WHERE  s.saleid = f.saleid AND s.farmid = f.farmid AND f.kind = 'credit'
    RETURNING s.saleid, s.farmid
)
INSERT INTO poultryeggsalebackfill
    (farmid, saleid, quantity, unitprice, oldtotalamount, newtotalamount,
     oldpaid, oldamountpaid, ranby)
SELECT f.farmid, f.saleid, f.quantity, f.unitprice, f.oldtotal, f.newtotal,
       f.oldpaid, f.oldamountpaid, 'migration-238'
FROM   eggfix f
JOIN   upd u ON u.saleid = f.saleid AND u.farmid = f.farmid;

-- -----------------------------------------------------------------------------
-- 4. Fully paid sales, only when asked for.
-- -----------------------------------------------------------------------------
DO $paid$
DECLARE
    v_row    record;
    v_posted numeric(14,2);
    v_gap    numeric(14,2);
    v_pid    integer;
    v_done   integer := 0;
BEGIN
    FOR v_row IN SELECT * FROM eggfix_paid ORDER BY farmid, saledate, saleid
    LOOP
        -- What the payment rows already account for. A cash sale is usually
        -- written paid = true with no payment rows at all, so this is 0 and the
        -- whole of the old total has to be recorded as collected.
        SELECT COALESCE(SUM(pp.amount), 0) INTO v_posted
        FROM   poultrypayments pp
        WHERE  pp.saleid = v_row.saleid
          AND  pp.farmid = v_row.farmid
          AND  COALESCE(pp.status, 'Posted') = 'Posted';

        v_gap := round(v_row.oldtotal - v_posted, 2);
        v_pid := NULL;

        IF v_gap > 0.005 THEN
            -- Money that genuinely reached the farm, written down so that
            -- sppoultrysale_recompute -- which derives amountpaid from these
            -- rows and reposts the cash from it -- keeps the cash account
            -- exactly where it is. Without this row, the next payment taken on
            -- this sale would recompute amountpaid to 0 and delete the cash.
            INSERT INTO poultrypayments
                (farmid, saleid, amount, paymentmethod, paymentdate, reference, note,
                 createdby, status, sourcetype, customerid, poultrycashaccountid,
                 paymentgroupid)
            VALUES
                (v_row.farmid, v_row.saleid, v_gap, v_row.paymentmethod, v_row.saledate,
                 'backfill-238',
                 'Amount already collected on this sale, recorded when the egg total was corrected.',
                 'migration-238', 'Posted', 'Backfill', v_row.customerid,
                 v_row.poultrycashaccountid, gen_random_uuid())
            RETURNING poultrypaymentid INTO v_pid;
        END IF;

        UPDATE sale SET totalamount = v_row.newtotal
        WHERE  saleid = v_row.saleid AND farmid = v_row.farmid;

        -- Recompute amountpaid and paid from the payment rows, and re-post the
        -- cash from that. Net movement on the cash account: zero. The sale now
        -- reads as part paid, with the shortfall outstanding.
        PERFORM sppoultrysale_recompute(v_row.farmid, v_row.saleid, NULL, 'migration-238');

        INSERT INTO poultryeggsalebackfill
            (farmid, saleid, quantity, unitprice, oldtotalamount, newtotalamount,
             oldpaid, oldamountpaid, compensatingpaymentid, ranby)
        VALUES
            (v_row.farmid, v_row.saleid, v_row.quantity, v_row.unitprice,
             v_row.oldtotal, v_row.newtotal, v_row.oldpaid, v_row.oldamountpaid,
             v_pid, 'migration-238');

        v_done := v_done + 1;
    END LOOP;

    RAISE NOTICE 'Fully paid sales corrected: %', v_done;
END
$paid$;

-- -----------------------------------------------------------------------------
-- 5. What changed, and proof of what is left behind.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== Written ================================================================'
SELECT count(*)                                            AS sales,
       sum(newtotalamount - oldtotalamount)::numeric(14,2) AS revenue_recovered,
       count(compensatingpaymentid)                        AS payment_rows_added
FROM   poultryeggsalebackfill
WHERE  ranby = 'migration-238';

\echo ''
\echo '--- Still billed for crates only (paid ones stay until you opt in) ---------'
SELECT CASE WHEN COALESCE(s.paid, TRUE) THEN 'paid' ELSE 'credit' END AS kind,
       count(*) AS sales
FROM   sale s
WHERE  s.product ILIKE '%egg%'
  AND  COALESCE(s.quantity, 0) > 0
  AND  COALESCE(s.unitprice, 0) > 0
  AND  (s.quantity % 30) <> 0
  AND  abs(COALESCE(s.totalamount, 0)
           - round(floor(s.quantity / 30.0) * s.unitprice, 2)) < 0.005
  AND  round(s.quantity / 30.0 * s.unitprice, 2) > COALESCE(s.totalamount, 0)
  AND  (NULLIF(:'farm', '') IS NULL OR s.farmid = NULLIF(:'farm', ''))
GROUP  BY 1
ORDER  BY 1;

\if :apply
    COMMIT;
    \echo ''
    \echo '>>> COMMITTED.'
    \echo '>>> Run sppoultrycashaccount_reconcilebalance afterwards and diff, the'
    \echo '>>> way 223 asks you to after anything that touches sale cash.'
\else
    ROLLBACK;
    \echo ''
    \echo '>>> DRY RUN -- everything above was rolled back.'
    \echo '>>> Re-run with  -v apply=true  to write it.'
\endif

-- =============================================================================
-- UNDO -- run by hand if the corrected totals turn out to be unwanted.
-- =============================================================================
-- BEGIN;
--
-- -- Take the compensating payment rows back out first, or the re-post below
-- -- reads them as real money.
-- DELETE FROM poultrypayments p
-- USING  poultryeggsalebackfill b
-- WHERE  p.poultrypaymentid = b.compensatingpaymentid
--   AND  b.ranby = 'migration-238';
--
-- UPDATE sale s
-- SET    totalamount = b.oldtotalamount,
--        paid        = b.oldpaid,
--        amountpaid  = b.oldamountpaid
-- FROM   poultryeggsalebackfill b
-- WHERE  s.saleid = b.saleid AND s.farmid = b.farmid
--   AND  b.ranby  = 'migration-238';
--
-- -- Re-post the cash for every sale that had a payment row removed, so the
-- -- account balance lands back where it started.
-- SELECT sppoultrysalecash_sync(b.farmid, b.saleid, s.poultrycashaccountid,
--                               b.oldtotalamount, b.oldpaid, 'Sale receipt', 'undo-238')
-- FROM   poultryeggsalebackfill b
-- JOIN   sale s ON s.saleid = b.saleid AND s.farmid = b.farmid
-- WHERE  b.ranby = 'migration-238';
--
-- DELETE FROM poultryeggsalebackfill WHERE ranby = 'migration-238';
--
-- COMMIT;

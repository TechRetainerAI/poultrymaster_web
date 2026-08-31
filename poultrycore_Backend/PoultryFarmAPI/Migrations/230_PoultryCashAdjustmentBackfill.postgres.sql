-- =============================================================================
-- 230_PoultryCashAdjustmentBackfill.postgres.sql
--
-- Purpose
-- -------
-- The old /cash page recorded manual cash adjustments -- Opening Balance, Owner
-- Injection, Loan Received, Withdrawal, Correction -- through
-- POST /api/Cash/Adjustment into a standalone `cashadjustments` table. Those rows
-- never touched poultrycashtransactions: that endpoint is account-less and
-- predates the cash-account ledger entirely (see CashController.cs, which merges
-- adjustments + sales + expenses in memory rather than reading a ledger).
--
-- The Cash Flow page reads the cash-account ledger. Without this migration every
-- historical adjustment would silently vanish from the page and Calculated Cash
-- at Hand would disagree with the figure the old page had been showing for
-- months -- with no visible reason for the gap.
--
-- This copies each adjustment into the ledger against the farm's default cash
-- account, so the history survives the switch and the two numbers reconcile.
--
-- Why a distinct sourcetype
-- -------------------------
-- 'LegacyAdjustment', not 'Adjustment'. Three reasons:
--
--   1. Idempotence. sppoultrycashaccount_adjust writes sourcetype 'Adjustment'
--      with sourceid NULL (129:148), so there is no key to test against. Pairing
--      a distinct sourcetype with sourceid = adjustmentid gives an exact NOT
--      EXISTS guard, and this migration can be re-run safely.
--   2. Reversibility. One DELETE on that sourcetype undoes the whole backfill.
--   3. Honesty on screen. These rows came from a different system with no cash
--      account of their own; the account below is an attribution, not a fact.
--      The Cash Flow breakdown can label them accordingly instead of implying
--      someone chose that account at the time.
--
-- Which account receives them
-- ---------------------------
-- The farm's oldest active FarmCashBox, else its oldest active account of any
-- type. Farms with NO cash account at all cannot receive the backfill; the run
-- RAISES A WARNING naming the count and value rather than skipping quietly,
-- because on those farms the old page's cash-at-hand and the new page's will
-- legitimately differ until someone creates an account and re-runs this.
--
-- Amounts are already signed
-- --------------------------
-- The old UI negated withdrawals before saving
-- (app/cash/page.tsx: amount = type === "Withdrawal" ? -abs : abs), so
-- cashadjustments.amount carries the sign the ledger wants. Do not re-derive it
-- from adjustmenttype -- 'Correction' can legitimately be either direction.
--
-- Runs AFTER 229, which fixes the business-date problem for the syncs. These rows
-- carry adjustmentdate and were never affected by that.
--
-- Idempotent: guarded INSERT ... WHERE NOT EXISTS, and a balance rebuild that is
-- itself a recompute rather than an increment.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1 + 2. Copy each adjustment into the ledger, if the table is even there.
-- -----------------------------------------------------------------------------
-- All of this lives inside one DO block using dynamic SQL, and that is not
-- stylistic. A plain `INSERT ... FROM cashadjustment` resolves the relation when
-- the statement is PARSED, so on a database without that table the whole file
-- dies with "relation does not exist" no matter what a preceding guard printed.
-- Only EXECUTE defers the lookup to run time, which is what lets the guard
-- actually guard.
--
-- The name is checked both ways on purpose. The source of record is T-SQL
-- `dbo.CashAdjustment` -- SINGULAR (see 132_PoultryClosingReport.sql:73 and
-- Models/CashAdjustmentModel.cs) -- but the T-SQL-to-Postgres conversion was
-- done outside this repo and the rest of the schema is inconsistent about
-- pluralisation, so both spellings are tried rather than assumed.
--
-- The account is resolved per farm by the LATERAL: oldest active FarmCashBox
-- first, then any oldest active account. Farms that match neither drop out of
-- the join and are reported below.
--
-- balanceaftertransaction is left NULL on purpose. It is a point-in-time snapshot
-- and these rows are being inserted out of order, years after the fact -- writing
-- a computed value would be inventing a balance that never existed. The ledger
-- read does not depend on it, and section 4 rebuilds currentbalance from SUM.
DO $backfill$
DECLARE
    v_tbl     text;
    v_copied  integer := 0;
    v_skipped bigint  := 0;
    v_net     numeric := 0;
BEGIN
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);

    IF v_tbl IS NULL THEN
        RAISE NOTICE '230: no cashadjustment table on this database -- nothing to backfill.';
        RAISE NOTICE '230: that is fine. It means this company never used the old '
                     'account-less /cash adjustment dialog, so no history is lost.';
        RETURN;
    END IF;

    RAISE NOTICE '230: backfilling from %', v_tbl;

    EXECUTE format($sql$
        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype,
             sourcetype, sourceid, amount, balanceaftertransaction, description,
             createdby, approvedby, approvedat, createdat)
        SELECT ca.farmid::text,
               acct.poultrycashaccountid,
               ca.adjustmentdate,
               CASE WHEN ca.amount >= 0 THEN 'AdjustmentIn' ELSE 'AdjustmentOut' END,
               'LegacyAdjustment',
               ca.adjustmentid,
               ca.amount,
               NULL,
               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype),
               ca.userid,
               ca.userid,
               ca.createddate,
               ca.createddate
        FROM   %s ca
        JOIN   LATERAL (
                   SELECT a.poultrycashaccountid
                   FROM   poultrycashaccounts a
                   WHERE  lower(a.farmid) = lower(ca.farmid::text)
                     AND  a.isactive
                   ORDER  BY (a.accounttype = 'FarmCashBox') DESC, a.poultrycashaccountid
                   LIMIT  1
               ) acct ON TRUE
        WHERE  ca.amount <> 0
          AND  NOT EXISTS (
                   SELECT 1 FROM poultrycashtransactions t
                   WHERE  t.sourcetype = 'LegacyAdjustment'
                     AND  t.sourceid   = ca.adjustmentid
                     AND  lower(t.farmid) = lower(ca.farmid::text)
               )
    $sql$, v_tbl);

    GET DIAGNOSTICS v_copied = ROW_COUNT;
    RAISE NOTICE '230: copied % legacy adjustment(s) into the ledger.', v_copied;

    -- Farms with no cash account at all cannot receive theirs. Not an error, but
    -- an action item: create an account there and re-run this file. Until then
    -- their Cash Flow page understates cash at hand by exactly this much.
    EXECUTE format($sql$
        SELECT count(*), COALESCE(SUM(ca.amount), 0)
        FROM   %s ca
        WHERE  ca.amount <> 0
          AND  NOT EXISTS (SELECT 1 FROM poultrycashaccounts a
                           WHERE lower(a.farmid) = lower(ca.farmid::text) AND a.isactive)
    $sql$, v_tbl) INTO v_skipped, v_net;

    IF v_skipped > 0 THEN
        RAISE WARNING '230: % adjustment(s) worth % could NOT be migrated -- those farms '
                      'have no active cash account. Create one and re-run this file.',
                      v_skipped, v_net;
    END IF;
END;
$backfill$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 4. Rebuild the cached balances.
-- -----------------------------------------------------------------------------
-- currentbalance is a denormalised cache maintained by hand in every posting SP,
-- and this migration inserted rows behind its back. sppoultrycashaccount_reconcilebalance
-- recomputes it from openingbalance + SUM(amount), so it is safe to run twice and
-- correct whether or not the backfill above inserted anything on that farm.
-- Deliberately unconditional: it is a recompute, so running it on a database
-- with no legacy adjustments at all costs nothing and can only heal drift.
DO $rebuild$
DECLARE r record;
BEGIN
    FOR r IN SELECT DISTINCT farmid FROM poultrycashaccounts LOOP
        PERFORM sppoultrycashaccount_reconcilebalance(r.farmid);
    END LOOP;
END;
$rebuild$;

-- -----------------------------------------------------------------------------
-- 5. Verification.
-- -----------------------------------------------------------------------------
-- The source-table counts are raised as notices from inside a DO block for the
-- same reason the backfill is: a plain SELECT against a table that may not exist
-- fails at parse time and takes the rest of the file with it.
DO $verify$
DECLARE
    v_tbl    text;
    v_source bigint;
    v_copied bigint;
BEGIN
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);

    SELECT count(*) INTO v_copied
    FROM   poultrycashtransactions WHERE sourcetype = 'LegacyAdjustment';

    IF v_tbl IS NULL THEN
        RAISE NOTICE '230 CHECK: no source table; % legacy row(s) already in the ledger.', v_copied;
        RETURN;
    END IF;

    EXECUTE format('SELECT count(*) FROM %s WHERE amount <> 0', v_tbl) INTO v_source;
    RAISE NOTICE '230 CHECK: % adjustment(s) in %, % now in the ledger, % outstanding.',
                 v_source, v_tbl, v_copied, v_source - v_copied;
END;
$verify$;

-- These read only tables that certainly exist, so they stay as plain queries.
SELECT 'copied into the ledger' AS check, count(*)::text AS result
FROM   poultrycashtransactions WHERE sourcetype = 'LegacyAdjustment'
UNION ALL
SELECT 'net value copied',
       COALESCE(SUM(amount), 0)::text
FROM   poultrycashtransactions WHERE sourcetype = 'LegacyAdjustment'
UNION ALL
-- After section 4 the cache must equal the ledger everywhere. A failure here
-- means the rebuild did not run, not that the backfill was wrong.
SELECT 'cache matches ledger',
       CASE WHEN NOT EXISTS (
              SELECT 1 FROM poultrycashaccounts a
              WHERE  a.currentbalance <> a.openingbalance
                   + COALESCE((SELECT SUM(t.amount) FROM poultrycashtransactions t
                               WHERE t.poultrycashaccountid = a.poultrycashaccountid
                                 AND t.farmid = a.farmid), 0))
            THEN 'OK' ELSE 'DRIFT PRESENT' END;

-- Per-farm before/after. Run this on a copy and keep the output: it is the
-- explanation for anyone who notices cash at hand moved on the day this shipped.
SELECT a.farmid,
       SUM(a.currentbalance) AS cash_at_hand_now,
       COALESCE((SELECT SUM(t.amount) FROM poultrycashtransactions t
                 WHERE t.farmid = a.farmid AND t.sourcetype = 'LegacyAdjustment'), 0)
           AS of_which_backfilled
FROM   poultrycashaccounts a
GROUP  BY a.farmid
ORDER  BY a.farmid;

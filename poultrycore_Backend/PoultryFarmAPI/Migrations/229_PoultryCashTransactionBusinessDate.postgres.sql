-- =============================================================================
-- 229_PoultryCashTransactionBusinessDate.postgres.sql
--
-- Purpose
-- -------
-- poultrycashtransactions.transactiondate is the moment the row was WRITTEN, not
-- the date the money moved. Every cash-sync function stamps
-- (now() at time zone 'utc') and none of them accepts a date:
--
--     sppoultrysalecash_sync                 223_PoultryCustomerBalances:165
--     sppoultryrawmaterialpurchasecash_sync  224_PoultrySupplierBalances:172
--     sppoultrysupplierpaymentcash_sync      224_PoultrySupplierBalances:460
--     sppoultryexpensecash_sync              (live body not in this repo)
--
-- Worse, all four are REVERSE-THEN-REPOST: they delete the rows for a source and
-- insert fresh ones. So a January sale that takes a second payment in August has
-- its entire cash-in deleted and re-stamped to August.
--
-- The consequence is that any date-ranged total over this ledger reports money
-- RECORDED in the range, not money RECEIVED in it -- and the same query returns
-- different answers before and after somebody edits an old sale. That makes a
-- cash-flow page impossible to trust, which is why this lands before it.
--
-- Why a helper instead of adding a date parameter
-- -----------------------------------------------
-- The obvious fix is p_transactiondate on each sync. It was rejected:
--
--   1. sppoultryexpensecash_sync's live Postgres body IS NOT IN THIS REPO. Only
--      the T-SQL original survives (132_ExpenseCashAccountLink.sql:80). Adding a
--      parameter to a plpgsql function means DROP + CREATE -- i.e. reproducing a
--      body nobody here can read.
--   2. The T-SQL is NOT a safe stand-in. Migration 223 deliberately rewrote the
--      sale sync (see its header note 4: it used to post only when paid = true;
--      it now posts cumulative amountpaid). The T-SQL and the live functions have
--      provably diverged, so porting 132 forward would silently revert whatever
--      the live expense sync has learned since.
--   3. Migrations 222 and 223 already set the precedent for exactly this
--      situation: NEW FUNCTIONS ONLY, ZERO DROPS.
--
-- So instead: one additive helper that re-stamps the rows a sync just wrote. The
-- caller knows the business date; it calls the sync, then calls this. On a later
-- edit the sync deletes and reposts, the caller re-stamps, and the row is correct
-- again -- idempotent by construction rather than by a guard.
--
-- Two syncs do not use the helper, for opposite reasons:
--
--   sppoultrysupplierpaymentcash_sync has no C# caller at all -- the record and
--   reverse SPs PERFORM it from inside SQL (224:448, 224:582). But its body IS
--   in this repo AND it already reads the payment row, so section 2 below just
--   adds paymentdate to that SELECT. Same signature, plain CREATE OR REPLACE.
--
--   sppoultryrawmaterialpurchasecash_sync likewise reads its own purchase row,
--   so PoultryInventoryServices passes the date as a subquery on purchasedate
--   rather than threading it down from the caller.
--
-- What is NOT re-dated
-- --------------------
-- approvedat and createdat stay as posting facts -- they answer "when did this
-- enter the system", which is a real and different question.
--
-- Adjustment, LegacyAdjustment, Transfer and ReconciliationAdjustment rows are
-- left alone everywhere in this migration. For those the posting date IS the
-- business date: someone counted a drawer, moved money between accounts, or
-- corrected a balance at that moment. Re-dating them would invent history.
--
-- Idempotent: CREATE OR REPLACE, and a backfill that only ever moves a row onto
-- its source document's date.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The helper.
-- -----------------------------------------------------------------------------
-- Returns the number of rows re-stamped, so a caller that wants to assert can.
-- Deliberately narrow: it only ever writes transactiondate, only for one source
-- document, and only within one farm.
CREATE OR REPLACE FUNCTION public.sppoultrycashtransaction_setbusinessdate(
    p_farmid       text,
    p_sourcetype   text,
    p_sourceid     integer,
    p_businessdate timestamp)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_n integer := 0;
BEGIN
    IF p_businessdate IS NULL OR p_sourceid IS NULL OR p_sourcetype IS NULL THEN
        RETURN 0;
    END IF;

    -- Never re-date the source types whose posting moment IS the business event.
    IF p_sourcetype IN ('Adjustment', 'LegacyAdjustment', 'Transfer',
                        'ReconciliationAdjustment') THEN
        RETURN 0;
    END IF;

    UPDATE poultrycashtransactions
    SET    transactiondate = p_businessdate
    WHERE  farmid     = p_farmid
      AND  sourcetype = p_sourcetype
      AND  sourceid   = p_sourceid
      AND  transactiondate IS DISTINCT FROM p_businessdate;

    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. Supplier payment cash: stamp paymentdate at the source.
-- -----------------------------------------------------------------------------
-- This one does NOT go through the helper, because it is not called from C# --
-- sppoultrysupplierpayment_record (224:448) and _reverse (224:582) both PERFORM
-- it from inside SQL, so there is no caller to re-stamp afterwards.
--
-- It does not need the helper either. Unlike the sale and expense syncs, this
-- function already SELECTs the payment row (224:487) to find the account and
-- amount, so paymentdate comes along for free. Adding it to that SELECT means a
-- plain CREATE OR REPLACE: same signature, no DROP, no parameter change, and the
-- two calling SPs are untouched.
--
-- Body reproduced verbatim from 224:460-515 with three changes, marked below.
CREATE OR REPLACE FUNCTION public.sppoultrysupplierpaymentcash_sync(
    p_farmid text, p_paymentid integer, p_createdby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_acct   integer;
    v_amt    numeric(14,2);
    v_status text;
    v_name   text;
    v_bal    numeric(14,2);
    v_date   timestamp;          -- 229: added
BEGIN
    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - t.net, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT ct.poultrycashaccountid, SUM(ct.amount) AS net
        FROM   poultrycashtransactions ct
        WHERE  ct.sourcetype = 'PoultrySupplierPayment' AND ct.sourceid = p_paymentid
          AND  ct.farmid = p_farmid
        GROUP  BY ct.poultrycashaccountid
    ) t
    WHERE  t.poultrycashaccountid = a.poultrycashaccountid AND a.farmid = p_farmid;

    DELETE FROM poultrycashtransactions ct
    WHERE  ct.sourcetype = 'PoultrySupplierPayment' AND ct.sourceid = p_paymentid
      AND  ct.farmid = p_farmid;

    SELECT sp.poultrycashaccountid, sp.totalamount, sp.status, s.name, sp.paymentdate
    INTO   v_acct, v_amt, v_status, v_name, v_date          -- 229: + paymentdate
    FROM   poultrysupplierpayments sp
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.poultrysupplierpaymentid = p_paymentid AND sp.farmid = p_farmid
    LIMIT  1;

    IF (v_acct IS NOT NULL AND COALESCE(v_amt, 0) > 0 AND COALESCE(v_status, 'Posted') = 'Posted'
        AND EXISTS (SELECT 1 FROM poultrycashaccounts a
                    WHERE a.poultrycashaccountid = v_acct AND a.farmid = p_farmid)) THEN

        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance - v_amt, updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = v_acct AND a.farmid = p_farmid;

        SELECT a.currentbalance INTO v_bal
        FROM   poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct LIMIT 1;

        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
        VALUES
            -- 229: transactiondate was (now() at time zone 'utc'). approvedat
            -- stays as now() -- that one IS a posting fact.
            (p_farmid, v_acct, COALESCE(v_date, (now() at time zone 'utc')),
             'CashOut', 'PoultrySupplierPayment',
             p_paymentid, -v_amt, v_bal,
             'Supplier payment: ' || COALESCE(v_name, 'supplier'), p_createdby, p_createdby,
             (now() at time zone 'utc'));
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Backfill existing rows onto their document's date.
-- -----------------------------------------------------------------------------
-- One statement per source type, each joining the cash row to the document that
-- created it. Rows whose document has since been deleted keep their posting date
-- -- there is nothing better to give them, and they are reported in section 4.
--
-- MIND THE FARMID CAST. poultrycashtransactions.farmid is text (047/128 declare
-- NVARCHAR(450)), but sale.farmid and expense.farmid are the older uuid-shaped
-- column -- which is why 223_PoultryCustomerBalances:371 selects s.farmid::text
-- and why fnpoultrydailyclosing_livetotals has to sniff the parameter with a
-- guid regex (see 216's header, line 44). Joining them raw would either raise a
-- type error or, worse, match nothing and report a clean run having changed
-- zero rows. lower(...::text) on both sides is deliberate: it survives whichever
-- type each column actually is, and whichever case the guid was stored in.
UPDATE poultrycashtransactions t
SET    transactiondate = s.saledate
FROM   sale s
WHERE  t.sourcetype = 'Sale'
  AND  t.sourceid   = s.saleid
  AND  lower(t.farmid) = lower(s.farmid::text)
  AND  s.saledate IS NOT NULL
  AND  t.transactiondate IS DISTINCT FROM s.saledate;

UPDATE poultrycashtransactions t
SET    transactiondate = e.expensedate
FROM   expense e
WHERE  t.sourcetype = 'Expense'
  AND  t.sourceid   = e.expenseid
  AND  lower(t.farmid) = lower(e.farmid::text)
  AND  e.expensedate IS NOT NULL
  AND  t.transactiondate IS DISTINCT FROM e.expensedate;

UPDATE poultrycashtransactions t
SET    transactiondate = pu.purchasedate
FROM   poultryrawmaterialpurchases pu
WHERE  t.sourcetype = 'RawMaterialPurchase'
  AND  t.sourceid   = pu.poultryrawmaterialpurchaseid
  AND  lower(t.farmid) = lower(pu.farmid::text)
  AND  pu.purchasedate IS NOT NULL
  AND  t.transactiondate IS DISTINCT FROM pu.purchasedate;

UPDATE poultrycashtransactions t
SET    transactiondate = sp.paymentdate
FROM   poultrysupplierpayments sp
WHERE  t.sourcetype = 'PoultrySupplierPayment'
  AND  t.sourceid   = sp.poultrysupplierpaymentid
  AND  lower(t.farmid) = lower(sp.farmid::text)
  AND  sp.paymentdate IS NOT NULL
  AND  t.transactiondate IS DISTINCT FROM sp.paymentdate;

COMMIT;

-- -----------------------------------------------------------------------------
-- 4. Verification.
-- -----------------------------------------------------------------------------
SELECT 'helper function' AS check,
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public'
                AND p.proname = 'sppoultrycashtransaction_setbusinessdate')
            THEN 'OK' ELSE 'MISSING' END AS result
UNION ALL
-- After the backfill every linked row should sit on its document's date. A
-- non-zero count here means the join found no document, not that the update
-- failed -- section 4 lists them.
SELECT 'sale rows still off-date',
       count(*)::text
FROM   poultrycashtransactions t
JOIN   sale s ON s.saleid = t.sourceid AND lower(s.farmid::text) = lower(t.farmid)
WHERE  t.sourcetype = 'Sale' AND s.saledate IS NOT NULL
  AND  t.transactiondate IS DISTINCT FROM s.saledate
UNION ALL
SELECT 'expense rows still off-date',
       count(*)::text
FROM   poultrycashtransactions t
JOIN   expense e ON e.expenseid = t.sourceid AND lower(e.farmid::text) = lower(t.farmid)
WHERE  t.sourcetype = 'Expense' AND e.expensedate IS NOT NULL
  AND  t.transactiondate IS DISTINCT FROM e.expensedate
UNION ALL
-- The join above returning zero MATCHES (rather than zero mismatches) would also
-- read as "OK", so count the linked rows too. A zero here on a farm that has
-- sales means the farmid cast is still wrong, not that the data is clean.
SELECT 'sale rows linked (sanity: should be > 0 if any sales posted cash)',
       count(*)::text
FROM   poultrycashtransactions t
JOIN   sale s ON s.saleid = t.sourceid AND lower(s.farmid::text) = lower(t.farmid)
WHERE  t.sourcetype = 'Sale';

-- Orphans: cash rows whose source document no longer exists. They keep their
-- posting date. Expected to be small; a large number means something deletes
-- documents without re-syncing their cash.
SELECT t.sourcetype, count(*) AS orphaned_rows
FROM   poultrycashtransactions t
WHERE  t.sourcetype = 'Sale'
  AND  NOT EXISTS (SELECT 1 FROM sale s
                   WHERE s.saleid = t.sourceid AND lower(s.farmid::text) = lower(t.farmid))
GROUP  BY t.sourcetype
UNION ALL
SELECT t.sourcetype, count(*)
FROM   poultrycashtransactions t
WHERE  t.sourcetype = 'Expense'
  AND  NOT EXISTS (SELECT 1 FROM expense e
                   WHERE e.expenseid = t.sourceid AND lower(e.farmid::text) = lower(t.farmid))
GROUP  BY t.sourcetype;

-- How far the ledger moved, per farm and month. Run this BEFORE and AFTER on a
-- copy: it is the evidence that a period total changed meaning, and by how much.
SELECT farmid,
       to_char(transactiondate, 'YYYY-MM') AS month,
       count(*) AS rows,
       SUM(amount) FILTER (WHERE amount > 0) AS money_in,
       SUM(-amount) FILTER (WHERE amount < 0) AS money_out
FROM   poultrycashtransactions
WHERE  sourcetype NOT IN ('Adjustment', 'LegacyAdjustment', 'Transfer',
                          'ReconciliationAdjustment')
GROUP  BY farmid, to_char(transactiondate, 'YYYY-MM')
ORDER  BY farmid, month;

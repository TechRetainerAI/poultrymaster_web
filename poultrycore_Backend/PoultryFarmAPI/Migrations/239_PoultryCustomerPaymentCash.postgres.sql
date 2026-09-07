-- =============================================================================
-- 239  One cash transaction per real customer payment
-- =============================================================================
-- THE PROBLEM. Cash for a sale is posted per SALE: sppoultrysalecash_sync (223)
-- keeps exactly one collapsed 'Sale' row per sale, holding whatever that sale
-- has received. So a customer who hands over GHC 4,820 against two sales sees
-- TWO cash transactions -- GHC 2,000 and GHC 2,820 -- and neither of them is
-- the payment that was actually made. The cash account is right to the pesewa;
-- the story it tells is wrong.
--
-- THE RULE, and it is already the rule elsewhere. Migration 235 built Cash Flow
-- on exactly this split: money that came through a payment row is a Receipt,
-- and what is left over on the sale -- a sale written as already paid, with no
-- payment row behind it -- is a SaleResidual. This file applies that same split
-- to the cash-accounts ledger, so the ledger and the cash-flow report finally
-- describe the same events:
--
--   * one 'CustomerPayment' row per payment GROUP (paymentgroupid), for the
--     full amount the customer handed over, dated when they handed it over;
--   * the 'Sale' row keeps only the residual -- what the sale records as
--     received minus what its payment rows account for. For a walk-in cash
--     sale that is still the whole amount, exactly as today.
--
-- Because residual + payments = received, the account balances do not move.
-- The verification at the bottom proves that rather than asserting it.
--
-- WHAT IS NOT CHANGED. Cash Flow (235) reads poultrypayments and sale directly,
-- not this ledger, so it is unaffected. Reversal keeps working through the same
-- syncs: a reversed payment has no Posted rows left, so its cash row is removed
-- and the sale's residual grows back by the same amount.
--
-- Idempotent: every sync is delete-then-repost, so running this twice lands on
-- the same rows.
--
-- HOW TO RUN
--   1. Dry run (default) -- does everything, prints the proof, rolls back:
--        psql "<conn>" -f 239_PoultryCustomerPaymentCash.postgres.sql
--   2. For real:
--        psql "<conn>" -v apply=true -f 239_PoultryCustomerPaymentCash.postgres.sql
--
--   Then, as 223 asks after anything that touches sale cash, run
--   sppoultrycashaccount_reconcilebalance and diff.
-- =============================================================================

\set ON_ERROR_STOP on

\if :{?apply}
\else
  \set apply false
\endif

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Before: the numbers the end of this file has to reproduce.
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE cash_before ON COMMIT DROP AS
SELECT a.farmid,
       SUM(a.currentbalance)::numeric(14,2) AS balance,
       (SELECT COALESCE(SUM(ct.amount), 0)::numeric(14,2)
        FROM   poultrycashtransactions ct
        WHERE  ct.farmid = a.farmid AND ct.sourcetype IN ('Sale', 'CustomerPayment')) AS sale_cash
FROM   poultrycashaccounts a
GROUP  BY a.farmid;

-- -----------------------------------------------------------------------------
-- 1. The payment group on the cash row.
-- -----------------------------------------------------------------------------
-- sourceid is an integer and a payment group is a uuid, so the group needs its
-- own column. sourceid still carries the group's first poultrypaymentid, so
-- anything that joins cash rows to a payment by id keeps working.
ALTER TABLE poultrycashtransactions
    ADD COLUMN IF NOT EXISTS paymentgroupid uuid NULL;

CREATE INDEX IF NOT EXISTS ix_poultrycashtransactions_paymentgroup
    ON poultrycashtransactions (farmid, paymentgroupid);

-- -----------------------------------------------------------------------------
-- 2. Which account a payment group posts to.
-- -----------------------------------------------------------------------------
-- Older payment rows predate the cash-account link and carry NULL, so fall back
-- to the sale's account. Returning NULL is meaningful: it says this group has
-- nowhere to post, and section 4 then leaves its money in the sale residual
-- rather than dropping it out of the ledger.
CREATE OR REPLACE FUNCTION public.fnpoultrypaymentgroupaccount(
    p_farmid text, p_paymentgroupid uuid)
RETURNS integer
LANGUAGE sql
STABLE
AS $function$
    SELECT a.poultrycashaccountid
    FROM   poultrycashaccounts a
    WHERE  a.farmid = p_farmid
      AND  a.poultrycashaccountid = (
            SELECT COALESCE(MIN(pp.poultrycashaccountid), MIN(s.poultrycashaccountid))
            FROM   poultrypayments pp
            LEFT   JOIN sale s ON s.saleid = pp.saleid AND s.farmid = pp.farmid
            WHERE  pp.paymentgroupid = p_paymentgroupid
              AND  pp.farmid = p_farmid
              AND  COALESCE(pp.status, 'Posted') = 'Posted')
    LIMIT  1;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Cash for one payment event.
-- -----------------------------------------------------------------------------
-- Delete-then-repost, the same shape as sppoultrysalecash_sync, so a reversal
-- or an edit is just another call and there is never more than one cash row per
-- payment group.
CREATE OR REPLACE FUNCTION public.sppoultrycustomerpaymentcash_sync(
    p_farmid text, p_paymentgroupid uuid, p_createdby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_acct   integer;
    v_amount numeric(14,2);
    v_date   timestamp;
    v_srcid  integer;
    v_name   text;
    v_bal    numeric(14,2);
BEGIN
    -- Reverse and remove whatever this group posted before.
    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - t.net, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT ct.poultrycashaccountid, SUM(ct.amount) AS net
        FROM   poultrycashtransactions ct
        WHERE  ct.sourcetype = 'CustomerPayment'
          AND  ct.paymentgroupid = p_paymentgroupid
          AND  ct.farmid = p_farmid
        GROUP  BY ct.poultrycashaccountid
    ) t
    WHERE  t.poultrycashaccountid = a.poultrycashaccountid
      AND  a.farmid = p_farmid;

    DELETE FROM poultrycashtransactions ct
    WHERE  ct.sourcetype = 'CustomerPayment'
      AND  ct.paymentgroupid = p_paymentgroupid
      AND  ct.farmid = p_farmid;

    -- What the customer actually handed over: the whole group, Posted rows only.
    SELECT COALESCE(SUM(pp.amount), 0)::numeric(14,2),
           MIN(pp.paymentdate),
           MIN(pp.poultrypaymentid),
           MIN(c.name)::text
    INTO   v_amount, v_date, v_srcid, v_name
    FROM   poultrypayments pp
    LEFT   JOIN customer c ON c.customerid = pp.customerid AND c.farmid = pp.farmid
    WHERE  pp.paymentgroupid = p_paymentgroupid
      AND  pp.farmid = p_farmid
      AND  COALESCE(pp.status, 'Posted') = 'Posted';

    IF COALESCE(v_amount, 0) <= 0 THEN RETURN; END IF;

    v_acct := fnpoultrypaymentgroupaccount(p_farmid, p_paymentgroupid);
    IF v_acct IS NULL THEN RETURN; END IF;

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance + v_amount, updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycashaccountid = v_acct AND a.farmid = p_farmid;

    SELECT a.currentbalance INTO v_bal
    FROM   poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct LIMIT 1;

    -- Dated when the money arrived, not when the sale was written. 229 treats
    -- transactiondate as the business date, and for a payment that date is the
    -- payment's own -- which is the whole point of separating the two.
    INSERT INTO poultrycashtransactions
        (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
         paymentgroupid, amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
    VALUES
        (p_farmid, v_acct, COALESCE(v_date, (now() at time zone 'utc')), 'CashIn',
         'CustomerPayment', v_srcid, p_paymentgroupid, v_amount, v_bal,
         'Customer payment' || COALESCE(' from ' || NULLIF(btrim(v_name), ''), ''),
         p_createdby, p_createdby, (now() at time zone 'utc'));
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. The sale's cash row keeps only the residual.
-- -----------------------------------------------------------------------------
-- Replaces 223's version. Same signature and same callers -- SaleService still
-- calls it on insert and update -- but what it posts is now
--
--     received  -  what the payment rows already put in the ledger
--
-- which is 235's SaleResidual to the letter. A walk-in cash sale has no payment
-- rows, so its residual is the whole amount and nothing about it changes. A
-- sale settled by payments posts nothing here; its money is on the payment row.
--
-- Payments whose group has no cash account resolve to nothing in section 3, so
-- they are NOT subtracted -- their money stays on the sale row instead of
-- disappearing from the ledger.
CREATE OR REPLACE FUNCTION public.sppoultrysalecash_sync(
    p_farmid text, p_saleid integer, p_poultrycashaccountid integer DEFAULT NULL::integer,
    p_amount numeric DEFAULT 0, p_paid boolean DEFAULT true,
    p_description text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_bal      numeric(14,2);
    v_received numeric(14,2);
    v_onpay    numeric(14,2);
    v_post     numeric(14,2);
BEGIN
    -- Reverse any existing sale cash tx (restore balances, then delete them).
    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - t.net, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT ct.poultrycashaccountid, SUM(ct.amount) AS net
        FROM   poultrycashtransactions ct
        WHERE  ct.sourcetype = 'Sale' AND ct.sourceid = p_saleid AND ct.farmid = p_farmid
        GROUP  BY ct.poultrycashaccountid
    ) t
    WHERE  t.poultrycashaccountid = a.poultrycashaccountid
      AND  a.farmid = p_farmid;

    DELETE FROM poultrycashtransactions ct
    WHERE  ct.sourcetype = 'Sale' AND ct.sourceid = p_saleid AND ct.farmid = p_farmid;

    -- Record the chosen account on the sale row.
    UPDATE sale s SET poultrycashaccountid = p_poultrycashaccountid
    WHERE  s.saleid = p_saleid AND s.farmid = p_farmid;

    -- How much money has reached the farm for this sale, unchanged from 223.
    IF COALESCE(p_paid, TRUE) THEN
        v_received := COALESCE(p_amount, 0);
    ELSE
        SELECT COALESCE(s.amountpaid, 0) INTO v_received
        FROM   sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid LIMIT 1;
        IF COALESCE(p_amount, 0) > 0 THEN
            v_received := LEAST(COALESCE(v_received, 0), p_amount);
        END IF;
    END IF;

    -- ...and how much of it the payment ledger has already accounted for.
    SELECT COALESCE(SUM(pp.amount), 0)::numeric(14,2) INTO v_onpay
    FROM   poultrypayments pp
    WHERE  pp.saleid = p_saleid
      AND  pp.farmid = p_farmid
      AND  COALESCE(pp.status, 'Posted') = 'Posted'
      AND  fnpoultrypaymentgroupaccount(p_farmid, pp.paymentgroupid) IS NOT NULL;

    v_post := GREATEST(ROUND(COALESCE(v_received, 0) - COALESCE(v_onpay, 0), 2), 0);

    IF (p_poultrycashaccountid IS NOT NULL AND v_post > 0
        AND EXISTS (SELECT 1 FROM poultrycashaccounts a
                    WHERE a.poultrycashaccountid = p_poultrycashaccountid AND a.farmid = p_farmid)) THEN

        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance + v_post, updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = p_poultrycashaccountid AND a.farmid = p_farmid;

        SELECT a.currentbalance INTO v_bal
        FROM   poultrycashaccounts a WHERE a.poultrycashaccountid = p_poultrycashaccountid LIMIT 1;

        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, p_poultrycashaccountid, (now() at time zone 'utc'), 'CashIn', 'Sale', p_saleid,
             v_post, v_bal, COALESCE(p_description, 'Sale receipt'), p_createdby, p_createdby,
             (now() at time zone 'utc'));
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Recompute now syncs both halves.
-- -----------------------------------------------------------------------------
-- Replaces 223's version, adding the payment-group sync. Every path that moves
-- payment money -- recording a payment, a bulk payment, a reversal -- ends in
-- this function for each affected sale, so hooking it here covers all of them
-- without rewriting sppoultrycustomerpayment_record or _reverse.
--
-- A group spanning two sales is synced once per sale; the sync is
-- delete-then-repost, so the second call lands on the same single row.
CREATE OR REPLACE FUNCTION public.sppoultrysale_recompute(
    p_farmid text, p_saleid integer,
    p_cashaccountid integer DEFAULT NULL::integer, p_createdby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_total   numeric(14,2);
    v_acct    integer;
    v_sum     numeric(14,2);
    v_newpaid boolean;
    v_group   uuid;
BEGIN
    SELECT s.totalamount, s.poultrycashaccountid INTO v_total, v_acct
    FROM   sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid LIMIT 1;

    IF v_total IS NULL THEN RETURN; END IF;

    v_sum := COALESCE((SELECT SUM(pp.amount) FROM poultrypayments pp
                       WHERE pp.saleid = p_saleid AND pp.farmid = p_farmid
                         AND COALESCE(pp.status, 'Posted') = 'Posted'), 0);
    v_newpaid := COALESCE(v_sum >= v_total, FALSE);

    UPDATE sale s SET amountpaid = v_sum, paid = v_newpaid
    WHERE  s.saleid = p_saleid AND s.farmid = p_farmid;

    -- The payment events first, so the residual below is computed against a
    -- ledger that already holds them.
    FOR v_group IN
        SELECT DISTINCT pp.paymentgroupid
        FROM   poultrypayments pp
        WHERE  pp.saleid = p_saleid AND pp.farmid = p_farmid
          AND  pp.paymentgroupid IS NOT NULL
    LOOP
        PERFORM sppoultrycustomerpaymentcash_sync(p_farmid, v_group, p_createdby);
    END LOOP;

    PERFORM sppoultrysalecash_sync(p_farmid, p_saleid, COALESCE(p_cashaccountid, v_acct),
                                   v_total, v_newpaid, 'Sale payment', p_createdby);
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Backfill: move the history onto the new shape.
-- -----------------------------------------------------------------------------
-- Payment groups first, then the sales they touch, so each sale's residual is
-- calculated against a ledger that already holds its payments. Balances are
-- adjusted by both syncs and must net to zero -- section 7 checks that.
DO $backfill$
DECLARE
    v_group  record;
    v_sale   record;
    v_groups integer := 0;
    v_sales  integer := 0;
BEGIN
    FOR v_group IN
        SELECT DISTINCT pp.farmid, pp.paymentgroupid
        FROM   poultrypayments pp
        WHERE  pp.paymentgroupid IS NOT NULL
    LOOP
        PERFORM sppoultrycustomerpaymentcash_sync(v_group.farmid, v_group.paymentgroupid, 'migration-239');
        v_groups := v_groups + 1;
    END LOOP;

    FOR v_sale IN
        SELECT DISTINCT s.farmid::text AS farmid, s.saleid, s.poultrycashaccountid,
               s.totalamount, COALESCE(s.paid, TRUE) AS paid
        FROM   sale s
        WHERE  EXISTS (SELECT 1 FROM poultrypayments pp
                       WHERE pp.saleid = s.saleid AND pp.farmid = s.farmid)
    LOOP
        PERFORM sppoultrysalecash_sync(v_sale.farmid, v_sale.saleid, v_sale.poultrycashaccountid,
                                       v_sale.totalamount, v_sale.paid, 'Sale receipt', 'migration-239');
        v_sales := v_sales + 1;
    END LOOP;

    RAISE NOTICE 'Payment groups posted: %.  Sales re-synced: %.', v_groups, v_sales;
END
$backfill$;

-- -----------------------------------------------------------------------------
-- 7. Verification.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== Balances must not have moved ==========================================='
SELECT b.farmid,
       b.balance                       AS balance_before,
       n.balance                       AS balance_after,
       (n.balance - b.balance)         AS drift,
       CASE WHEN n.balance = b.balance THEN 'OK' ELSE '*** DRIFT ***' END AS verdict
FROM   cash_before b
JOIN  (SELECT a.farmid, SUM(a.currentbalance)::numeric(14,2) AS balance
       FROM   poultrycashaccounts a GROUP BY a.farmid) n ON n.farmid = b.farmid
WHERE  n.balance <> b.balance OR b.balance <> 0
ORDER  BY b.farmid;

\echo ''
\echo '--- Sale + payment cash still sums to the same total -----------------------'
SELECT b.farmid,
       b.sale_cash AS before,
       (SELECT COALESCE(SUM(ct.amount), 0)::numeric(14,2)
        FROM   poultrycashtransactions ct
        WHERE  ct.farmid = b.farmid AND ct.sourcetype IN ('Sale', 'CustomerPayment')) AS after,
       CASE WHEN b.sale_cash = (SELECT COALESCE(SUM(ct.amount), 0)::numeric(14,2)
                                FROM   poultrycashtransactions ct
                                WHERE  ct.farmid = b.farmid
                                  AND  ct.sourcetype IN ('Sale', 'CustomerPayment'))
            THEN 'OK' ELSE '*** DRIFT ***' END AS verdict
FROM   cash_before b
ORDER  BY b.farmid;

\echo ''
\echo '--- One cash row per payment group, and how the ledger now splits ----------'
SELECT sourcetype,
       count(*)                          AS rows,
       count(DISTINCT paymentgroupid)    AS groups,
       SUM(amount)::numeric(14,2)        AS total
FROM   poultrycashtransactions
WHERE  sourcetype IN ('Sale', 'CustomerPayment')
GROUP  BY sourcetype
ORDER  BY sourcetype;

\echo ''
\echo '--- Payments with nowhere to post (their money stays on the sale row) ------'
SELECT count(DISTINCT pp.paymentgroupid) AS groups_without_cash_account
FROM   poultrypayments pp
WHERE  pp.paymentgroupid IS NOT NULL
  AND  COALESCE(pp.status, 'Posted') = 'Posted'
  AND  fnpoultrypaymentgroupaccount(pp.farmid, pp.paymentgroupid) IS NULL;

\if :apply
    COMMIT;
    \echo ''
    \echo '>>> COMMITTED.'
    \echo '>>> Now run sppoultrycashaccount_reconcilebalance and diff.'
\else
    ROLLBACK;
    \echo ''
    \echo '>>> DRY RUN -- rolled back, including the new columns and functions.'
    \echo '>>> Re-run with  -v apply=true  to write it.'
\endif

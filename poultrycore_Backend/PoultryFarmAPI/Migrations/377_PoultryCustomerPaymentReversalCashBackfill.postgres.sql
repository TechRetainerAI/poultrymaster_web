-- =============================================================================
-- 377_PoultryCustomerPaymentReversalCashBackfill.postgres.sql   (requires 351)
--
-- Purpose
-- -------
-- A reversed customer payment keeps its Money In and has a separate Money Out
-- for the reversal. 351 built that: sppoultrycustomerpaymentcash_sync posts
-- 'CustomerPayment' (CashIn, payment day) and 'CustomerPaymentReversal'
-- (CashOut, reversal day), and Cash Flow arms 1 / 1b show both. Nothing in the
-- live code deletes a reversed receipt.
--
-- But payments reversed BEFORE that sync existed lost both rows from the cash
-- book (Cash Flow still showed them -- it reads the payments). This backfill
-- re-runs the sync for every reversed payment group with cash and no cash book
-- rows. A fully reversed group nets to zero, so balances do not move.
--
-- The same rule as 376 for supplier payments. Data only: no function changes.
-- =============================================================================
BEGIN;

DO $$
DECLARE
    v_r record;
    v_n integer := 0;
BEGIN
    FOR v_r IN
        SELECT g.farmid, g.paymentgroupid
        FROM  (SELECT p.farmid, p.paymentgroupid,
                      SUM(p.amount) AS amt,
                      bool_and(p.status = 'Reversed') AS allreversed
               FROM   poultrypayments p
               WHERE  p.paymentgroupid IS NOT NULL
                 AND  COALESCE(p.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote')
               GROUP  BY p.farmid, p.paymentgroupid) g
        WHERE  g.allreversed AND g.amt > 0
          AND  fnpoultrypaymentgroupaccount_any(g.farmid, g.paymentgroupid) IS NOT NULL
          AND  NOT EXISTS (SELECT 1 FROM poultrycashtransactions ct
                           WHERE ct.farmid = g.farmid AND ct.paymentgroupid = g.paymentgroupid
                             AND ct.sourcetype IN ('CustomerPayment', 'CustomerPaymentReversal'))
        ORDER  BY g.farmid, g.paymentgroupid
    LOOP
        PERFORM sppoultrycustomerpaymentcash_sync(v_r.farmid, v_r.paymentgroupid, 'migration377');
        v_n := v_n + 1;
    END LOOP;
    RAISE NOTICE '377: % reversed customer payment(s) given their cash book rows back', v_n;
END
$$;

COMMIT;

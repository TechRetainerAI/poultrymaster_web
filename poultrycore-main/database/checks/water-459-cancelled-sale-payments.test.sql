-- =============================================================================
-- Checks for 459 (payments left Posted on cancelled Water sales).
-- SELF-ROLLING-BACK, read-only.  Prints 'water 459: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $t$
DECLARE v_n integer; v_amt numeric;
BEGIN
    -- 1. no money is counted on a sale that is not a sale
    SELECT COUNT(*), COALESCE(SUM(p.amount), 0) INTO v_n, v_amt
    FROM   waterpayments p JOIN watersales s ON s.watersaleid = p.watersaleid AND s.farmid = p.farmid
    WHERE  s.status = 'Cancelled' AND COALESCE(p.status, 'Posted') = 'Posted'
      AND  NOT fnwater_iscreditkind(p.sourcetype)
      -- a 458 reversal that KEPT the money as credit leaves its payment Posted on purpose
      AND  NOT EXISTS (SELECT 1 FROM watersalereversalpayments rp
                       WHERE rp.paymentgroupid = p.paymentgroupid AND rp.action = 'KeepAsCredit');
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 1: % payment(s), %, still Posted on cancelled sales', v_n, v_amt; END IF;
    RAISE NOTICE 'ok 1 no Posted payment on a cancelled sale';

    -- 2. every reversed payment nets to zero on Cash Flow (receipt + reversal)
    SELECT COUNT(*) INTO v_n
    FROM   waterpayments p
    WHERE  p.status = 'Reversed' AND p.reversedat IS NOT NULL AND NOT fnwater_isnocashcredit(p.sourcetype)
      AND  COALESCE((SELECT SUM(r.amount) FROM spwatercashflow_rows(p.farmid, NULL, NULL) r
                     WHERE r.rowsource IN ('Receipt', 'ReceiptReversal') AND r.sourcerowid = p.waterpaymentid), 0) <> 0;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 2: % reversed payment(s) do not net to zero on Cash Flow', v_n; END IF;
    RAISE NOTICE 'ok 2 reversed payments net to zero on Cash Flow';

    RAISE NOTICE 'water 459: all checks passed';
END
$t$;

ROLLBACK;

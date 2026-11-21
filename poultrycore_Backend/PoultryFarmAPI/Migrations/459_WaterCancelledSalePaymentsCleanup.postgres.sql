-- =============================================================================
-- 459  Water: payments still Posted on sales cancelled before 458   (requires 458)
-- =============================================================================
--
-- Before 458, two paths cancelled a Water sale and left its payments Posted:
--   * spwaterdriverreturn_reverse cancelled the delivery sales of a reversed
--     driver return and only wrote "[Reversed ...]" into their payments' note;
--   * spwatersale_cancel put the stock back and left the payments alone.
-- Those payments are still on Cash Flow as money received (and their
-- allocations still Posted), although the sale they paid no longer exists as a
-- sale. Dev on 2026-11-20: 22 payments, 81,386, on 15 sales of 3 companies.
--
-- WHAT THIS DOES
-- Each such payment is REVERSED exactly as 458 now does it -- status Reversed,
-- with its allocations -- dated when its sale was cancelled (the sale's
-- updateddate; never before the payment itself). Cash Flow, being append-only
-- since 458, keeps the receipt on its own day and shows the reversal on the
-- cancel day, so each period reads what really happened.
--
-- WHAT IT DOES NOT DO
--   * Touch a sale reversed by 458 (salereversalid set): those are right.
--   * Touch credit rows (Deposit / Overpayment / ...): applied credit was
--     already released by the cancel.
--   * Delete anything.
--
-- Idempotent: a second run finds nothing Posted to reverse.
-- Dry-run with database/apply-water-cancelled-sale-payments.ps1.
-- =============================================================================

BEGIN;

DO $m$
DECLARE
    v_alloc integer;
    v_pay   integer;
    v_amt   numeric(14,2);
BEGIN
    CREATE TEMP TABLE _w459 ON COMMIT DROP AS
    SELECT p.waterpaymentid, p.farmid, p.amount,
           GREATEST(COALESCE(s.updateddate, p.paymentdate), p.paymentdate) AS reversedat,
           CASE WHEN COALESCE(s.sourcetype, '') = 'DeliveryRun'
                THEN 'Driver return #' || COALESCE(s.sourceid::text, '?') || ' was reversed before 458 (459 cleanup)'
                ELSE 'Sale #' || s.watersaleid || ' was cancelled before 458 (459 cleanup)' END AS reason
    FROM   waterpayments p
    JOIN   watersales s ON s.watersaleid = p.watersaleid AND s.farmid = p.farmid
    WHERE  s.status = 'Cancelled'
      AND  s.salereversalid IS NULL
      AND  COALESCE(p.status, 'Posted') = 'Posted'
      AND  NOT public.fnwater_iscreditkind(p.sourcetype);

    UPDATE customerpaymentallocation ca
    SET    status = 'Reversed', reversedby = 'migration 459', reversedat = x.reversedat, reversalreason = x.reason
    FROM   _w459 x
    WHERE  ca.farmid = x.farmid AND ca.module = 'water' AND ca.paymentid = x.waterpaymentid
      AND  ca.status = 'Posted';
    GET DIAGNOSTICS v_alloc = ROW_COUNT;

    UPDATE waterpayments p
    SET    status = 'Reversed', reversedby = 'migration 459', reversedat = x.reversedat, reversalreason = x.reason
    FROM   _w459 x
    WHERE  p.waterpaymentid = x.waterpaymentid AND p.farmid = x.farmid;
    GET DIAGNOSTICS v_pay = ROW_COUNT;

    SELECT COALESCE(SUM(amount), 0) INTO v_amt FROM _w459;
    RAISE NOTICE '459: % payment(s) reversed (%), % allocation(s).', v_pay, v_amt, v_alloc;
END
$m$;

COMMIT;

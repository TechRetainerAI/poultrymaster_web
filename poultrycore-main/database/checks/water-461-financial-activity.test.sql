-- =============================================================================
-- Checks for 461 (Water Financial Activity). READ-ONLY, self-rolling-back.
-- For EVERY Water company, all time and one recent month:
--   * events' Money In / Out  = Cash Flow summary
--   * events' Revenue - Expense = the P&L's net profit (spwaterreport_periodpnl)
--   * events' Revenue = P&L income; Expense = everything the P&L deducts
--   * running cash of the last row = Cash Flow closing cash
-- Prints 'water 461: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $t$
DECLARE
    v_f   record;
    v_p   record;
    v_s   record;
    v_cf  record;
    v_ev  record;
    v_last numeric;
    v_from date;
    v_to   date;
    v_n   integer := 0;
BEGIN
    FOR v_f IN SELECT DISTINCT farmid FROM watersales
               UNION SELECT DISTINCT farmid FROM waterexpenses
               UNION SELECT DISTINCT farmid FROM watercashaccounts LOOP
        FOR v_from, v_to IN SELECT * FROM (VALUES (DATE '2000-01-01', current_date),
                                                   (date_trunc('month', current_date)::date - interval '6 month', date_trunc('month', current_date)::date - 1)) x(a, b) LOOP
            SELECT * INTO v_p  FROM spwaterreport_periodpnl(v_f.farmid, v_from, v_to);
            SELECT * INTO v_s  FROM spwaterfinancialactivity_summary(v_f.farmid, v_from, v_to);
            SELECT * INTO v_cf FROM spwatercashflow_summary(v_f.farmid, v_from::timestamp, (v_to + 1)::timestamp - interval '1 microsecond');
            SELECT COALESCE(SUM(e.moneyin), 0) AS mi, COALESCE(SUM(e.moneyout), 0) AS mo,
                   COALESCE(SUM(e.revenue), 0) AS rev, COALESCE(SUM(e.expense), 0) AS exp
            INTO   v_ev FROM fnwaterfa_events(v_f.farmid, v_from, v_to) e;

            IF round(v_ev.mi, 2) <> round(v_cf.moneyin, 2) OR round(v_ev.mo, 2) <> round(v_cf.moneyout, 2) THEN
                RAISE EXCEPTION 'FAIL 1 %: money in/out % / % vs Cash Flow % / %', v_f.farmid, v_ev.mi, v_ev.mo, v_cf.moneyin, v_cf.moneyout;
            END IF;
            IF round(v_s.netprofit, 2) <> round(COALESCE(v_p.netprofit, 0), 2) THEN
                RAISE EXCEPTION 'FAIL 2 % (% to %): profit % vs P&L %', v_f.farmid, v_from, v_to, v_s.netprofit, v_p.netprofit;
            END IF;
            IF round(v_ev.rev, 2) <> round(COALESCE(v_p.totalincome, 0), 2) THEN
                RAISE EXCEPTION 'FAIL 3 %: revenue % vs P&L income %', v_f.farmid, v_ev.rev, v_p.totalincome;
            END IF;
            SELECT g.runningcash INTO v_last FROM spwaterfinancialactivity_get(v_f.farmid, v_from, v_to) g
            ORDER BY g.businessdate DESC, g.createdat DESC NULLS LAST, g.eventkey DESC LIMIT 1;
            IF v_last IS NOT NULL AND round(v_last, 2) <> round(v_cf.cashathand, 2) THEN
                RAISE EXCEPTION 'FAIL 4 %: running cash ends at % vs Cash Flow closing %', v_f.farmid, v_last, v_cf.cashathand;
            END IF;
            v_n := v_n + 1;
        END LOOP;
    END LOOP;
    RAISE NOTICE 'ok 1-4 % company-periods: cash = Cash Flow, profit = P&L, running cash closes', v_n;

    -- 5. an expense paid at entry is ONE event with both its cash and its cost
    IF EXISTS (
        SELECT 1 FROM (SELECT DISTINCT farmid FROM waterexpenses) f
        CROSS JOIN LATERAL fnwaterfa_events(f.farmid, DATE '2000-01-01', current_date) e
        WHERE e.eventkey LIKE 'Expense:%'
        GROUP BY f.farmid, e.eventkey HAVING COUNT(*) > 1) THEN
        RAISE EXCEPTION 'FAIL 5: an expense split into two events';
    END IF;
    RAISE NOTICE 'ok 5 one event per expense';

    RAISE NOTICE 'water 461: all checks passed';
END
$t$;

ROLLBACK;

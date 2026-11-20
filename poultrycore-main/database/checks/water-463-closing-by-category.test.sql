-- =============================================================================
-- Checks for 463 (Water Closing by Category). READ-ONLY, self-rolling-back.
-- For EVERY Water company, all time and one recent window:
--   * the report runs
--   * NetProfit / TotalRevenue = the P&L (spwaterreport_periodpnl)
--   * MoneyIn / MoneyOut / ClosingCash = Cash Flow
--   * GoodBags = BagsProduced - BagsDamagedInProduction
-- Prints 'water 463: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $t$
DECLARE
    v_f record; v_r jsonb; v_p record; v_c record; v_from date; v_to date; v_n integer := 0;
BEGIN
    FOR v_f IN SELECT DISTINCT farmid FROM watersales
               UNION SELECT DISTINCT farmid FROM waterproductionbatches
               UNION SELECT DISTINCT farmid FROM watercashaccounts LOOP
        FOR v_from, v_to IN SELECT * FROM (VALUES (DATE '2000-01-01', current_date),
                                                   ((current_date - 90), current_date - 1)) x(a, b) LOOP
            v_r := spwaterclosingreport_get(v_f.farmid, v_from, v_to);
            SELECT * INTO v_p FROM spwaterreport_periodpnl(v_f.farmid, v_from, v_to);
            SELECT * INTO v_c FROM spwatercashflow_summary(v_f.farmid, v_from::timestamp, (v_to + 1)::timestamp - interval '1 microsecond');
            IF round((v_r->>'NetProfit')::numeric, 2) <> round(COALESCE(v_p.netprofit, 0), 2) THEN
                RAISE EXCEPTION 'FAIL 1 %: net profit % vs P&L %', v_f.farmid, v_r->>'NetProfit', v_p.netprofit;
            END IF;
            IF round((v_r->>'TotalRevenue')::numeric, 2) <> round(COALESCE(v_p.totalincome, 0), 2) THEN
                RAISE EXCEPTION 'FAIL 2 %: revenue % vs P&L %', v_f.farmid, v_r->>'TotalRevenue', v_p.totalincome;
            END IF;
            IF round((v_r->>'MoneyIn')::numeric, 2) <> round(v_c.moneyin, 2)
               OR round((v_r->>'MoneyOut')::numeric, 2) <> round(v_c.moneyout, 2)
               OR round((v_r->>'ClosingCash')::numeric, 2) <> round(v_c.cashathand, 2) THEN
                RAISE EXCEPTION 'FAIL 3 %: cash differs from Cash Flow', v_f.farmid;
            END IF;
            IF (v_r->>'GoodBags')::numeric <> (v_r->>'BagsProduced')::numeric - (v_r->>'BagsDamagedInProduction')::numeric THEN
                RAISE EXCEPTION 'FAIL 4 %: good bags', v_f.farmid;
            END IF;
            v_n := v_n + 1;
        END LOOP;
    END LOOP;
    RAISE NOTICE 'ok 1-4 % company-periods agree with P&L and Cash Flow', v_n;
    RAISE NOTICE 'water 463: all checks passed';
END
$t$;

ROLLBACK;

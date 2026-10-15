-- =============================================================================
-- daily-closing-part-paid.test.sql -- checks for migration 364.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f), and the apply
-- script also runs it inside its own rolled-back dry run. Compares Daily
-- Closing with the Sales page balance for every poultry company and day that
-- has sales.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    r        record;
    v_ws     jsonb;
    v_lt     record;
    v_owed   numeric;
    v_rev    numeric;
    v_days   integer := 0;
BEGIN
    -- 1. For today, Credit sales = the Sales page balance of today's sales,
    --    on both readers, for every company that sold today or recently.
    FOR r IN
        SELECT s.farmid, s.saledate::date AS d
        FROM   sale s
        WHERE  s.status = 'Posted' AND s.saledate::date >= CURRENT_DATE - 30
        GROUP  BY s.farmid, s.saledate::date
    LOOP
        v_days := v_days + 1;
        v_ws := public.sppoultrydailyclosing_workspace_core(r.farmid, r.d);
        SELECT * INTO v_lt FROM public.fnpoultrydailyclosing_livetotals(r.farmid, r.d);

        SELECT COALESCE(sum(public.fnpoultrysale_owedasof(r.farmid, s.saleid, r.d)), 0),
               COALESCE(sum(s.totalamount), 0)
        INTO   v_owed, v_rev
        FROM   sale s
        WHERE  s.status = 'Posted' AND s.farmid = r.farmid AND s.saledate::date = r.d;

        IF (v_ws->'sales'->>'creditSales')::numeric IS DISTINCT FROM v_owed THEN
            RAISE EXCEPTION 'FAIL workspace credit % % : % vs %', r.farmid, r.d, v_ws->'sales'->>'creditSales', v_owed;
        END IF;
        IF (v_ws->'sales'->>'cashSales')::numeric + v_owed IS DISTINCT FROM v_rev THEN
            RAISE EXCEPTION 'FAIL workspace cash + credit <> revenue % %', r.farmid, r.d;
        END IF;
        IF v_lt.creditsales IS DISTINCT FROM v_owed::numeric(18,2) THEN
            RAISE EXCEPTION 'FAIL livetotals credit % % : % vs %', r.farmid, r.d, v_lt.creditsales, v_owed;
        END IF;
    END LOOP;
    RAISE NOTICE 'ok 1 credit sales = amount still owed (% company-days)', v_days;

    -- 2. A sale owed nothing now is owed nothing today, and never more than its total.
    IF EXISTS (SELECT 1 FROM sale s WHERE s.status = 'Posted'
               AND (public.fnpoultrysale_owedasof(s.farmid, s.saleid, s.saledate::date) > s.totalamount
                    OR public.fnpoultrysale_owedasof(s.farmid, s.saleid, CURRENT_DATE + 1)
                       <> public.fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid))) THEN
        RAISE EXCEPTION 'FAIL owedasof out of range';
    END IF;
    RAISE NOTICE 'ok 2 owed-as-of agrees with the Sales page balance today';

    -- 3. Payments received excludes money paid at a same-day sale.
    IF EXISTS (
        SELECT 1
        FROM   (SELECT s.farmid, s.saledate::date AS d FROM sale s
                WHERE s.status = 'Posted' AND s.saledate::date >= CURRENT_DATE - 30
                GROUP BY 1, 2) x
        WHERE  (public.sppoultrydailyclosing_workspace_core(x.farmid, x.d)->'sales'->>'paymentsReceived')::numeric
               <> COALESCE((SELECT sum(pp.amount) FROM poultrypayments pp
                            WHERE pp.farmid = x.farmid AND COALESCE(pp.status, 'Posted') = 'Posted'
                              AND COALESCE(pp.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote')
                              AND pp.paymentdate::date = x.d
                              AND NOT EXISTS (SELECT 1 FROM sale s2 WHERE s2.saleid = pp.saleid
                                              AND s2.status = 'Posted' AND s2.saledate::date = x.d)), 0)) THEN
        RAISE EXCEPTION 'FAIL payments received still counts same-day sale payments';
    END IF;
    RAISE NOTICE 'ok 3 payments received = collections on earlier sales and deposits';

    RAISE NOTICE 'daily closing part-paid: all checks passed';
END $$;

ROLLBACK;

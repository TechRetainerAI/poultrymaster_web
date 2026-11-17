-- =============================================================================
-- Checks for 431 (Water P&L: Internal Use is not an expense -- its cost is
-- already in raw materials + production). SELF-ROLLING-BACK, fixtures dated
-- 2001 in a real Water company; figures are DELTAS.
-- Prints 'water 431: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $t$
DECLARE
    v_farm text; v_cat integer; v_iu integer; v_ord integer;
    d1 date := DATE '2001-06-10';
    b_exp numeric; b_net numeric; v_n numeric; v_m numeric;
BEGIN
    SELECT a.farmid INTO v_farm FROM watercashaccounts a ORDER BY a.watercashaccountid LIMIT 1;
    SELECT totalexpenses, netprofit INTO b_exp, b_net FROM spwaterreport_periodpnl(v_farm, d1, d1);
    v_cat := public.spwaterexpensecategory_ensureinternaluse(v_farm);

    -- an Internal Use expense exactly as spwaterinternalusage_post writes it, and an ordinary one
    INSERT INTO waterexpenses (farmid, expensedate, waterexpensecategoryid, description, amount, paymentmethod,
                               watercashaccountid, status, notes, createdby, approvedby, approvedat, sourcetype, sourceid)
    VALUES (v_farm, d1::timestamp, v_cat, 'Internal use: __w431', 70, 'Credit', NULL, 'Approved',
            'Non-cash: stock consumed internally (__w431).', '__w431', '__w431', now(), 'WaterInternalUsage', -431001)
    RETURNING waterexpenseid INTO v_iu;
    INSERT INTO waterexpenses (farmid, expensedate, waterexpensecategoryid, description, amount, paymentmethod,
                               watercashaccountid, status, notes, createdby, approvedby, approvedat)
    VALUES (v_farm, d1::timestamp, v_cat, '__w431 ordinary', 30, 'Cash', NULL, 'Approved', NULL, '__w431', '__w431', now())
    RETURNING waterexpenseid INTO v_ord;

    -- 1. only the ordinary expense reaches the P&L
    SELECT totalexpenses - b_exp, netprofit - b_net INTO v_n, v_m FROM spwaterreport_periodpnl(v_farm, d1, d1);
    IF v_n <> 30 THEN RAISE EXCEPTION 'FAIL 1a: expenses +% (want +30 -- Internal Use counted)', v_n; END IF;
    IF v_m <> -30 THEN RAISE EXCEPTION 'FAIL 1b: profit %', v_m; END IF;
    RAISE NOTICE 'ok 1 Internal Use is not a P&L expense; an ordinary expense still is';

    -- 2. lines and drill-down agree with periodpnl, and neither shows the Internal Use row
    SELECT COALESCE(SUM(l.amount), 0) INTO v_n FROM spwaterreport_pllines(v_farm, d1, d1) l
    WHERE  l.section IN ('OperatingExpense', 'OtherCost');
    SELECT COALESCE(SUM(d.amount), 0) INTO v_m FROM spwaterreport_plexpensedetail(v_farm, d1, d1, NULL) d;
    IF v_n <> (SELECT totalexpenses FROM spwaterreport_periodpnl(v_farm, d1, d1)) OR v_m <> v_n THEN
        RAISE EXCEPTION 'FAIL 2a: lines % detail % periodpnl %', v_n, v_m, (SELECT totalexpenses FROM spwaterreport_periodpnl(v_farm, d1, d1));
    END IF;
    IF EXISTS (SELECT 1 FROM spwaterreport_plexpensedetail(v_farm, d1, d1, NULL) d WHERE d.detail ILIKE '%__w431%' AND d.amount = 70) THEN
        RAISE EXCEPTION 'FAIL 2b: Internal Use row in the drill-down';
    END IF;
    RAISE NOTICE 'ok 2 lines and drill-down equal periodpnl, without Internal Use';

    -- 3. the row itself is untouched (Expenses page + Internal Use page still show the cost)
    IF NOT EXISTS (SELECT 1 FROM waterexpenses WHERE waterexpenseid = v_iu AND status = 'Approved' AND amount = 70) THEN
        RAISE EXCEPTION 'FAIL 3: the Internal Use expense row changed';
    END IF;
    RAISE NOTICE 'ok 3 the Internal Use expense row is kept';

    RAISE NOTICE 'water 431: all checks passed';
END
$t$;

ROLLBACK;

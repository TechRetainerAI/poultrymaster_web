-- =============================================================================
-- Checks for 429 (Water P&L: raw materials = cash, on the payment date).
-- SELF-ROLLING-BACK, fixtures in a real Water company, dated 2001; every figure
-- is a DELTA against the same window measured before the fixtures.
-- Prints 'water 429: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $t$
DECLARE
    v_farm text; v_acct integer; v_supp integer; v_item integer;
    v_pc integer; v_pe integer; v_pa integer; v_pn integer; v_pd integer;
    v_pay integer; v_adv integer; v_cn integer;
    d1 date := DATE '2001-05-10'; d2 date := DATE '2001-05-15';
    w0 date := DATE '2001-01-01'; w1 date := current_date + 1;
    b_all numeric; b_d1 numeric; b_d2 numeric; b_exp numeric; b_net numeric;
    b_cl1 numeric; b_cl2 numeric;
    v_n numeric; v_m numeric;
BEGIN
    SELECT a.farmid INTO v_farm FROM watercashaccounts a ORDER BY a.watercashaccountid LIMIT 1;

    -- before
    SELECT rawmaterialcost, totalexpenses, netprofit INTO b_all, b_exp, b_net FROM spwaterreport_periodpnl(v_farm, w0, w1);
    SELECT rawmaterialcost INTO b_d1 FROM spwaterreport_periodpnl(v_farm, d1, d1);
    SELECT rawmaterialcost INTO b_d2 FROM spwaterreport_periodpnl(v_farm, d2, d2);
    SELECT rawmaterialspendtoday INTO b_cl1 FROM fnwaterdailyclosing_livetotals(v_farm, d1);
    SELECT rawmaterialspendtoday INTO b_cl2 FROM fnwaterdailyclosing_livetotals(v_farm, d2);

    INSERT INTO watercashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, isactive)
    VALUES (v_farm, '__w429_account', 'Cash', 10000, 10000, TRUE) RETURNING watercashaccountid INTO v_acct;
    v_supp := spwatersupplier_insert(v_farm, '__w429_supplier', NULL, NULL, NULL, NULL, NULL, NULL, '__w429');
    v_item := spwaterrawmaterialitem_insert(v_farm, '__w429_item', 'PackagingRoll', 'kg', 0, 0, TRUE, NULL, 'kg', 'FIFO');

    -- purchases on d1: on credit 300, paid at entry 100, on credit 200 (advance), on credit 50 (credit note), deferred paid 80
    v_pc := spwaterrawmaterialpurchase_insert(v_farm, v_item, '__w429_supplier', d1::timestamp, 10, 30, 'Credit', 0,
                                              NULL, NULL, NULL, '__w429', v_supp, 300, NULL, 'kg', 1);
    v_pe := spwaterrawmaterialpurchase_insert(v_farm, v_item, '__w429_supplier', d1::timestamp, 10, 10, 'Cash', 100,
                                              NULL, NULL, NULL, '__w429', v_supp, 100, NULL, 'kg', 1);
    v_pa := spwaterrawmaterialpurchase_insert(v_farm, v_item, '__w429_supplier', d1::timestamp, 10, 20, 'Credit', 0,
                                              NULL, NULL, NULL, '__w429', v_supp, 200, NULL, 'kg', 1);
    v_pn := spwaterrawmaterialpurchase_insert(v_farm, v_item, '__w429_supplier', d1::timestamp, 10, 5, 'Credit', 0,
                                              NULL, NULL, NULL, '__w429', v_supp, 50, NULL, 'kg', 1);
    v_pd := spwaterrawmaterialpurchase_insert(v_farm, v_item, '__w429_supplier', d1::timestamp, 10, 8, 'Cash', 80,
                                              NULL, NULL, NULL, '__w429', v_supp, 80, NULL, 'kg', 1);
    -- a deferred lot reaches P&L when used, never when paid
    UPDATE waterrawmaterialpurchases SET costrecognitionmethod = 'EXPENSE_WHEN_CONSUMED' WHERE waterrawmaterialpurchaseid = v_pd;

    -- 1. on d1 only what was paid at entry counts
    IF (SELECT rawmaterialcost FROM spwaterreport_periodpnl(v_farm, d1, d1)) - b_d1 <> 100 THEN
        RAISE EXCEPTION 'FAIL 1: d1 raw materials +% (want +100)', (SELECT rawmaterialcost FROM spwaterreport_periodpnl(v_farm, d1, d1)) - b_d1;
    END IF;
    RAISE NOTICE 'ok 1 paid at entry counts on the purchase date; credit and deferred lots do not';

    -- 2. the credit purchase is paid on d2: it counts ONCE, on d2
    v_pay := spwatersupplierpayment_record(v_farm, v_supp, 300,
                 jsonb_build_array(jsonb_build_object('documenttype', 'RawMaterialPurchase', 'documentid', v_pc, 'amount', 300)),
                 'Cash', d2 + time '09:00', v_acct, NULL, NULL, 'SupplierBalances', '__w429');
    v_n := (SELECT rawmaterialcost FROM spwaterreport_periodpnl(v_farm, d2, d2)) - b_d2;
    IF v_n <> 300 THEN RAISE EXCEPTION 'FAIL 2a: d2 raw materials +% (want +300)', v_n; END IF;
    IF (SELECT rawmaterialcost FROM spwaterreport_periodpnl(v_farm, d1, d1)) - b_d1 <> 100 THEN RAISE EXCEPTION 'FAIL 2b: d1 moved'; END IF;
    SELECT rawmaterialcost - b_all, totalexpenses - b_exp INTO v_n, v_m FROM spwaterreport_periodpnl(v_farm, w0, w1);
    IF v_n <> 400 THEN RAISE EXCEPTION 'FAIL 2c: window raw materials +% (want +400)', v_n; END IF;
    IF v_m <> 0 THEN RAISE EXCEPTION 'FAIL 2d: operating expenses +% -- the payment expense is counted again', v_m; END IF;
    RAISE NOTICE 'ok 2 a purchase paid later counts once, on the payment date';

    -- 3. an advance applied later counts on the day applied (the advance itself is not a raw material)
    v_adv := spwatersupplierpayment_record(v_farm, v_supp, 200, '[]'::jsonb, 'Cash', d1 + time '10:00', v_acct, NULL, NULL, 'SupplierBalances', '__w429');
    IF (SELECT rawmaterialcost FROM spwaterreport_periodpnl(v_farm, d1, d1)) - b_d1 <> 100 THEN RAISE EXCEPTION 'FAIL 3a: an unapplied advance counted'; END IF;
    PERFORM spwatersuppliercredit_apply(v_farm, v_adv, 'RawMaterialPurchase', v_pa, 200, '__w429');
    v_n := (SELECT rawmaterialcost FROM spwaterreport_periodpnl(v_farm, w0, w1)) - b_all;
    IF v_n <> 600 THEN RAISE EXCEPTION 'FAIL 3b: window raw materials +% (want +600)', v_n; END IF;
    IF (SELECT rawmaterialcost FROM spwaterreport_periodpnl(v_farm, d1, d1)) - b_d1 <> 100 THEN RAISE EXCEPTION 'FAIL 3c: applied advance dated to the advance'; END IF;
    RAISE NOTICE 'ok 3 applied advance counts when applied';

    -- 4. a credit note applied moved no money: never a raw material
    v_cn := spwatersuppliercredit_create(v_farm, v_supp, 'SupplierCreditNote', 50, d1 + time '12:00', NULL, 'damaged rolls', '__w429');
    PERFORM spwatersuppliercredit_apply(v_farm, v_cn, 'RawMaterialPurchase', v_pn, 50, '__w429');
    v_n := (SELECT rawmaterialcost FROM spwaterreport_periodpnl(v_farm, w0, w1)) - b_all;
    IF v_n <> 600 THEN RAISE EXCEPTION 'FAIL 4: credit note counted (window +%)', v_n; END IF;
    RAISE NOTICE 'ok 4 a credit note is never a raw material';

    -- 5. the itemisation matches the authority (lines, drill-down)
    SELECT COALESCE(SUM(l.amount), 0) INTO v_n FROM spwaterreport_pllines(v_farm, w0, w1) l WHERE l.linekey = 'RawMaterials';
    SELECT COALESCE(SUM(r.amount), 0) INTO v_m FROM spwaterreport_pldirectcostdetail(v_farm, w0, w1, 'RawMaterials') r;
    IF v_n <> (SELECT rawmaterialcost FROM spwaterreport_periodpnl(v_farm, w0, w1)) OR v_m <> v_n THEN
        RAISE EXCEPTION 'FAIL 5: lines % detail % periodpnl %', v_n, v_m, (SELECT rawmaterialcost FROM spwaterreport_periodpnl(v_farm, w0, w1));
    END IF;
    SELECT COALESCE(SUM(r.amount), 0) INTO v_n FROM spwaterreport_pldirectcostdetail(v_farm, d2, d2, 'RawMaterials') r
    WHERE  r.reference = 'Purchase #' || v_pc;
    IF v_n <> 300 THEN RAISE EXCEPTION 'FAIL 5b: d2 drill-down shows % for the paid purchase', v_n; END IF;
    RAISE NOTICE 'ok 5 lines and drill-down equal periodpnl';

    -- 6. daily closing: the day's cash on raw materials
    v_n := (SELECT rawmaterialspendtoday FROM fnwaterdailyclosing_livetotals(v_farm, d1)) - b_cl1;
    IF v_n <> 180 THEN RAISE EXCEPTION 'FAIL 6a: d1 closing raw spend +% (want +180: 100 + deferred 80)', v_n; END IF;
    v_n := (SELECT rawmaterialspendtoday FROM fnwaterdailyclosing_livetotals(v_farm, d2)) - b_cl2;
    IF v_n <> 300 THEN RAISE EXCEPTION 'FAIL 6b: d2 closing raw spend +% (want +300)', v_n; END IF;
    RAISE NOTICE 'ok 6 daily closing raw spend is the cash of the day';

    -- 7. reversing the payment takes it back out
    PERFORM spwatersupplierpayment_reverse(v_farm, v_pay, 'test', '__w429');
    v_n := (SELECT rawmaterialcost FROM spwaterreport_periodpnl(v_farm, d2, d2)) - b_d2;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 7: reversed payment still +% on d2', v_n; END IF;
    RAISE NOTICE 'ok 7 a reversed payment no longer counts';

    RAISE NOTICE 'water 429: all checks passed';
END
$t$;

ROLLBACK;

-- Self-test for migration 336 (Hotel Financial Activity). Always ends by
-- raising; "SELFTEST PASSED" is success.
--
-- A probe hotel with guest payments (one voided), a cash expense, a credit
-- expense owed to a supplier, a supply purchase expensed when consumed and its
-- internal use, owner money, a loan with a repayment carrying interest, and a
-- transfer. Financial Activity must agree with Cash Flow (Money In / Out) and
-- with the P&L (Revenue / Expense / Net Profit) for the same period, and every
-- event must name the positions it moved.
DO $$
DECLARE
    f text := '__probe336__';
    v_main int; v_bank int; v_guest int; v_rt int; v_b int; v_p1 int; v_p2 int; v_supp int; v_e1 int; v_e2 int;
    v_item int; v_pur int; v_iu int; v_loan int; v_from date := CURRENT_DATE - 30; v_to date := CURRENT_DATE;
    s record; cf record; pl record; v_n numeric; v_checks int := 0;
BEGIN
    INSERT INTO hotelcashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance)
    VALUES (f, 'Main', 'Cash', 5000, 5000) RETURNING hotelcashaccountid INTO v_main;
    INSERT INTO hotelcashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance)
    VALUES (f, 'Bank', 'Bank', 0, 0) RETURNING hotelcashaccountid INTO v_bank;
    INSERT INTO hotelguests (farmid, firstname, lastname) VALUES (f, 'Ama', 'Owusu') RETURNING hotelguestid INTO v_guest;
    INSERT INTO hotelroomtypes (farmid, name) VALUES (f, 'Std') RETURNING hotelroomtypeid INTO v_rt;
    INSERT INTO hotelbookings (farmid, bookingref, hotelguestid, hotelroomtypeid, checkindate, checkoutdate, nightlyrate, totalamount, status)
    VALUES (f, 'P336', v_guest, v_rt, v_to - 3, v_to - 1, 150, 300, 'CheckedOut') RETURNING hotelbookingid INTO v_b;
    v_supp := sphotelsupplier_insert(f, 'Linen Co', 'ProductSupplier', NULL, NULL, NULL, NULL, 0, 0, NULL, 'probe');

    v_p1 := sphotelpayment_record(f, v_b, 200, 'Cash', NULL, NULL, NULL, v_main, 'probe');
    v_p2 := sphotelpayment_record(f, v_b, 50, 'Card', NULL, NULL, NULL, v_main, 'probe');
    PERFORM sphotelpayment_void(f, v_p2, 'declined', 'probe');
    INSERT INTO hotelexpenses (farmid, category, description, amount, expensedate, paymentmethod, hotelcashaccountid, status)
    VALUES (f, 'Utilities', 'Power', 120, v_to - 2, 'Cash', v_main, 'Draft') RETURNING hotelexpenseid INTO v_e1;
    PERFORM sphotelexpense_approve(f, v_e1, 'probe');
    INSERT INTO hotelexpenses (farmid, category, description, amount, expensedate, paymentmethod, status, hotelsupplierid)
    VALUES (f, 'Linen', 'Sheets', 80, v_to - 2, 'Credit', 'Draft', v_supp) RETURNING hotelexpenseid INTO v_e2;
    PERFORM sphotelexpense_approve(f, v_e2, 'probe');
    INSERT INTO hotelinventoryitems (farmid, name, category, unit, stockonhand, reorderlevel, unitcost)
    VALUES (f, 'Soap', 'Toiletries', 'bar', 0, 5, 0) RETURNING hotelinventoryitemid INTO v_item;
    PERFORM sphotelsupply_costmode_set(f, 'Toiletries', 'EXPENSE_WHEN_CONSUMED', 'probe');
    v_pur := sphotelsupplypurchase_create(f, v_item, 100, 100, v_to - 2, v_supp, NULL, 'Cash', 60, v_main, NULL, NULL, 'probe');
    v_iu := sphotelinternalusage_insert(f, v_to - 1, 'RoomAmenities', NULL, NULL, NULL, NULL,
              json_build_array(json_build_object('itemId', v_item, 'entryQuantity', 25))::text, 'probe');
    PERFORM sphotelinternalusage_post(v_iu, f, 'probe');
    PERFORM sphotelownermoney_record(f, 'Contribution', 1000, v_main, (v_to - 5)::timestamp);
    v_loan := sphotelloan_create(f, 'Good Bank', 2000, v_to - 5, 2000, v_main);
    PERFORM sphotelloanpayment_record(f, v_loan, v_main, 300, 20, 5, 0, (v_to - 1)::timestamp);
    PERFORM sphotelcashtransfer_record(f, v_main, v_bank, 500, (v_to - 1)::timestamp);

    -- ── 1. Cash side = Cash Flow ───────────────────────────────────────────
    SELECT * INTO s FROM sphotelfinancialactivity_summary(f, v_from, v_to);
    SELECT * INTO cf FROM sphotelcashflow_summary(f, v_from::timestamp, (v_to + 1)::timestamp - interval '1 microsecond');
    IF s.moneyin <> ROUND(cf.moneyin, 2) OR s.moneyout <> ROUND(cf.moneyout, 2) OR s.closingcash <> ROUND(cf.cashathand, 2) THEN
        RAISE EXCEPTION 'FAIL 1a: summary % vs cash flow %', row_to_json(s), row_to_json(cf); END IF;
    SELECT COALESCE(SUM(moneyin - moneyout), 0) INTO v_n FROM sphotelfinancialactivity_get(f, v_from, v_to);
    IF v_n <> s.netcashflow OR s.netcashflow <> ROUND(cf.netcashflow, 2) THEN RAISE EXCEPTION 'FAIL 1b: rows net %', v_n; END IF;
    -- Hotel Cash Flow's closing cash is the flows (accounts' opening balances are
    -- not flows): 200 + 50 - 50 - 120 - 60 + 1000 + 2000 - 325 = 2695; the
    -- transfer is internal.
    IF (SELECT runningcash FROM sphotelfinancialactivity_get(f, v_from, v_to) ORDER BY businessdate DESC, createdat DESC NULLS LAST, eventkey DESC LIMIT 1) <> 2695
       OR s.closingcash <> 2695 THEN
        RAISE EXCEPTION 'FAIL 1c: closing cash %', s.closingcash; END IF;
    v_checks := v_checks + 3;

    -- ── 2. Profit side = P&L ───────────────────────────────────────────────
    SELECT * INTO pl FROM sphotelreport_plsummary(f, v_from, v_to);
    IF s.revenue <> pl.totalrevenue OR s.expense <> ROUND(pl.totalexpenses + pl.totalothercosts, 2) OR s.netprofit <> pl.netprofit THEN
        RAISE EXCEPTION 'FAIL 2a: FA % vs P&L %', row_to_json(s), row_to_json(pl); END IF;
    -- room revenue 200 (the void is out); expenses 120 + 80 + supplies used 25; interest+fees 25
    IF s.revenue <> 200 OR s.expense <> 250 OR s.netprofit <> -50 THEN RAISE EXCEPTION 'FAIL 2b: figures %', row_to_json(s); END IF;
    v_checks := v_checks + 2;

    -- ── 3. One row per event; transfers internal; activity types ───────────
    IF (SELECT count(*) FROM sphotelfinancialactivity_get(f, v_from, v_to) WHERE eventkey = 'Expense:' || v_e1) <> 1
       OR (SELECT moneyout FROM sphotelfinancialactivity_get(f, v_from, v_to) WHERE eventkey = 'Expense:' || v_e1) <> 120
       OR (SELECT expense FROM sphotelfinancialactivity_get(f, v_from, v_to) WHERE eventkey = 'Expense:' || v_e1) <> 120 THEN
        RAISE EXCEPTION 'FAIL 3a: expense event not merged'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sphotelfinancialactivity_get(f, v_from, v_to)
                   WHERE activitytype = 'Transfer' AND istransfer AND moneyin = 0 AND moneyout = 0) THEN
        RAISE EXCEPTION 'FAIL 3b: transfer row'; END IF;
    IF (SELECT activitytype FROM sphotelfinancialactivity_get(f, v_from, v_to) WHERE sourcetype = 'OwnerMoney') <> 'Owner'
       OR (SELECT activitytype FROM sphotelfinancialactivity_get(f, v_from, v_to) WHERE sourcetype = 'FinancingLoan') <> 'Financing'
       OR (SELECT activitytype FROM sphotelfinancialactivity_get(f, v_from, v_to) WHERE sourcetype = 'SupplyUse') <> 'Inventory'
       OR (SELECT isnoncash FROM sphotelfinancialactivity_get(f, v_from, v_to) WHERE sourcetype = 'SupplyUse') IS NOT TRUE THEN
        RAISE EXCEPTION 'FAIL 3c: activity types'; END IF;
    v_checks := v_checks + 3;

    -- ── 4. Positions ───────────────────────────────────────────────────────
    IF (SELECT SUM(increaseamount) FROM fnhotelfa_positions(f, v_from, v_to) WHERE positiontype = 'SupplierPayable') <> 120
       OR (SELECT SUM(increaseamount - decreaseamount) FROM fnhotelfa_positions(f, v_from, v_to) WHERE positiontype = 'Inventory') <> 75
       OR (SELECT SUM(increaseamount - decreaseamount) FROM fnhotelfa_positions(f, v_from, v_to) WHERE positiontype = 'LoanLiability') <> 1700
       OR (SELECT SUM(increaseamount) FROM fnhotelfa_positions(f, v_from, v_to) WHERE positiontype = 'OwnerCapital') <> 1000
       OR (SELECT SUM(decreaseamount - increaseamount) FROM fnhotelfa_positions(f, v_from, v_to) WHERE positiontype = 'CustomerReceivable') <> 200
       OR (SELECT count(*) FROM fnhotelfa_positions(f, v_from, v_to) WHERE positiontype = 'Cash' AND positionname = 'Bank') <> 1 THEN
        RAISE EXCEPTION 'FAIL 4a: positions'; END IF;
    v_checks := v_checks + 1;

    RAISE EXCEPTION 'SELFTEST PASSED (% checks)', v_checks;
END $$;

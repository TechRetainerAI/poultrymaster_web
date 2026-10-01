-- Self-test for migration 332 (Hotel Sales, Payments, Customer/Supplier Balances).
-- Run after 332; it always ends by raising so everything rolls back.
-- "SELFTEST PASSED" in the error is the success signal.
--
-- The story: a guest owes on two stays and pays 300 across both; a corporate
-- account with a 400 opening balance is billed a 150 stay, pays 500 (opening +
-- stay), then that payment is reversed; an old-style Draft is approved and
-- allocated. A supplier is owed a 200 Credit expense and 700 of a 1,000 asset
-- (300 paid now); a 500 payment settles part, is reversed, and a Draft is
-- approved. Every step checks balances, ledgers, allocations, Cash Flow = ledger
-- and the P&L.
DO $$
DECLARE
    f text := '__probe332__';
    v_main int; v_guest int; v_guest2 int; v_rt int;
    v_b1 int; v_b2 int; v_b3 int; v_b4 int;
    v_cust int; v_supp int;
    v_g1 uuid; v_g2 uuid; v_g3 uuid;
    v_e1 int; v_e2 int; v_asset int; v_cost int; v_cost2 int;
    v_sp int; v_sp2 int; v_cp int;
    v_n numeric; v_n2 numeric; v_i int;
    v_failed boolean; v_checks int := 0;
    r record;
    v_today date := CURRENT_DATE;
BEGIN
    INSERT INTO hotelcashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance)
    VALUES (f, 'Main', 'Cash', 5000, 5000) RETURNING hotelcashaccountid INTO v_main;
    INSERT INTO hotelguests (farmid, firstname, lastname) VALUES (f, 'Ama', 'Mensah') RETURNING hotelguestid INTO v_guest;
    INSERT INTO hotelguests (farmid, firstname, lastname) VALUES (f, 'Kofi', 'Boateng') RETURNING hotelguestid INTO v_guest2;
    INSERT INTO hotelroomtypes (farmid, name) VALUES (f, 'Std') RETURNING hotelroomtypeid INTO v_rt;
    INSERT INTO hotelbookings (farmid, bookingref, hotelguestid, hotelroomtypeid, checkindate, checkoutdate, nightlyrate, totalamount, status)
    VALUES (f, 'P332-1', v_guest, v_rt, v_today - 10, v_today - 8, 100, 200, 'CheckedOut') RETURNING hotelbookingid INTO v_b1;
    INSERT INTO hotelstaycharges (farmid, hotelbookingid, chargetype, description, quantity, unitprice, totalamount)
    VALUES (f, v_b1, 'Minibar', 'Drinks', 1, 50, 50);
    INSERT INTO hotelbookings (farmid, bookingref, hotelguestid, hotelroomtypeid, checkindate, checkoutdate, nightlyrate, totalamount, status)
    VALUES (f, 'P332-2', v_guest, v_rt, v_today, v_today + 1, 100, 100, 'CheckedIn') RETURNING hotelbookingid INTO v_b2;
    INSERT INTO hotelbookings (farmid, bookingref, hotelguestid, hotelroomtypeid, checkindate, checkoutdate, nightlyrate, totalamount, status)
    VALUES (f, 'P332-3', v_guest, v_rt, v_today + 5, v_today + 8, 100, 300, 'Confirmed') RETURNING hotelbookingid INTO v_b3;
    INSERT INTO hotelbookings (farmid, bookingref, hotelguestid, hotelroomtypeid, checkindate, checkoutdate, nightlyrate, totalamount, status)
    VALUES (f, 'P332-4', v_guest2, v_rt, v_today - 20, v_today - 19, 150, 150, 'CheckedOut') RETURNING hotelbookingid INTO v_b4;
    v_cust := sphotelcustomer_insert(f, 'Acme Ltd', 'Corporate', NULL, NULL, NULL, NULL, 30, 0, 400, NULL, 'probe');
    v_supp := sphotelsupplier_insert(f, 'Linen Co', 'ProductSupplier', NULL, NULL, NULL, NULL, 14, 0, NULL, 'probe');

    -- ── 1. Documents and Customer Balances ─────────────────────────────────
    SELECT * INTO r FROM sphotelcustomerbalances(f) WHERE partyid = v_guest;
    IF r.totalbalance <> 350 OR r.opendocumentcount <> 2 THEN RAISE EXCEPTION 'FAIL 1a: guest balance %', row_to_json(r); END IF;
    SELECT * INTO r FROM sphotelcustomerbalances(f) WHERE partyid = -v_cust;
    IF r.totalbalance <> 400 OR r.partyname <> 'Acme Ltd' THEN RAISE EXCEPTION 'FAIL 1b: account balance %', row_to_json(r); END IF;
    IF EXISTS (SELECT 1 FROM sphotelcustomeropendocs(f, v_guest) WHERE documentid = v_b3) THEN
        RAISE EXCEPTION 'FAIL 1c: a future reservation is owed on'; END IF;
    IF (SELECT count(*) FROM sphotelsale_list(f) WHERE documenttype = 'Stay') <> 4 THEN
        RAISE EXCEPTION 'FAIL 1d: sales list stays'; END IF;
    v_checks := v_checks + 4;

    -- ── 2. One payment across two stays ────────────────────────────────────
    v_g1 := sphotelcustomerpayment_record(f, v_guest, 300,
            jsonb_build_array(jsonb_build_object('documenttype', 'Stay', 'documentid', v_b1, 'amount', 250),
                              jsonb_build_object('documenttype', 'Stay', 'documentid', v_b2, 'amount', 50)),
            'Cash', NULL, v_main, 'R-1', NULL, 'CustomerBalances', 'probe');
    IF (SELECT count(*) FROM hotelpayments WHERE farmid = f AND paymentgroupid = v_g1 AND status = 'Posted') <> 2 THEN
        RAISE EXCEPTION 'FAIL 2a: money rows'; END IF;
    IF (SELECT count(*) FROM customerpaymentallocation ca JOIN hotelpayments hp ON hp.hotelpaymentid = ca.paymentid
        WHERE ca.module = 'hotel' AND hp.paymentgroupid = v_g1 AND ca.status = 'Posted') <> 2 THEN
        RAISE EXCEPTION 'FAIL 2b: allocations'; END IF;
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 5300 THEN
        RAISE EXCEPTION 'FAIL 2c: main after payment'; END IF;
    IF (SELECT totalbalance FROM sphotelcustomerbalances(f) WHERE partyid = v_guest) <> 50 THEN
        RAISE EXCEPTION 'FAIL 2d: guest balance after payment'; END IF;
    SELECT * INTO r FROM sphotelcustomerpayment_history(f, v_guest) WHERE paymentid = v_g1::text;
    IF r.totalamount <> 300 OR r.allocationcount <> 2 OR r.status <> 'Posted' THEN RAISE EXCEPTION 'FAIL 2e: history %', row_to_json(r); END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelcustomerpayment_record(f, v_guest, 60, jsonb_build_array(jsonb_build_object('documenttype','Stay','documentid',v_b2,'amount',60)),
                  'Cash', NULL, v_main); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2f: overpayment accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelcustomerpayment_record(f, v_guest, 40, jsonb_build_array(jsonb_build_object('documenttype','Stay','documentid',v_b2,'amount',30)),
                  'Cash', NULL, v_main); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2g: allocations not adding up accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelcustomerpayment_record(f, v_guest2, 10, jsonb_build_array(jsonb_build_object('documenttype','Stay','documentid',v_b2,'amount',10)),
                  'Cash', NULL, v_main); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2h: another guest''s stay accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelpayment_record(f, v_b2, 51, 'Cash'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2i: Billing-page overpayment accepted'; END IF;
    v_checks := v_checks + 9;

    -- ── 3. Bill a stay to the corporate account ────────────────────────────
    v_failed := FALSE;
    BEGIN PERFORM sphotelsale_billto(f, v_b2, v_cust, 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3a: in-house stay billed to account'; END IF;
    PERFORM sphotelsale_billto(f, v_b4, v_cust, 'probe');
    IF (SELECT currentbalance FROM hotelcustomers WHERE hotelcustomerid = v_cust) <> 550
       OR NOT EXISTS (SELECT 1 FROM hotelcustomerledger WHERE hotelcustomerid = v_cust AND transactiontype = 'InvoiceCredit' AND creditamount = 150) THEN
        RAISE EXCEPTION 'FAIL 3b: account ledger after billing'; END IF;
    IF (SELECT totalbalance FROM sphotelcustomerbalances(f) WHERE partyid = -v_cust) <> 550
       OR EXISTS (SELECT 1 FROM sphotelcustomerbalances(f) WHERE partyid = v_guest2) THEN
        RAISE EXCEPTION 'FAIL 3c: stay did not move to the account'; END IF;
    v_checks := v_checks + 3;

    -- ── 4. Corporate payment: opening balance + the billed stay ────────────
    v_g2 := sphotelcustomerpayment_record(f, -v_cust, 500,
            jsonb_build_array(jsonb_build_object('documenttype', 'OpeningBalance', 'documentid', v_cust, 'amount', 400),
                              jsonb_build_object('documenttype', 'Stay', 'documentid', v_b4, 'amount', 100)),
            'Bank Transfer', NULL, v_main, 'ACME-1', NULL, 'CustomerBalances', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 5800 THEN
        RAISE EXCEPTION 'FAIL 4a: main after corporate payment'; END IF;
    IF (SELECT currentbalance FROM hotelcustomers WHERE hotelcustomerid = v_cust) <> 50
       OR (SELECT totalbalance FROM sphotelcustomerbalances(f) WHERE partyid = -v_cust) <> 50 THEN
        RAISE EXCEPTION 'FAIL 4b: ledger and balances disagree after corporate payment'; END IF;
    IF (SELECT count(*) FROM sphotelcustomerpayment_allocations(f, v_g2)) <> 2 THEN RAISE EXCEPTION 'FAIL 4c: allocations'; END IF;
    IF (SELECT count(*) FROM hotelcashtransactions t JOIN hotelcustomerpayments cp ON cp.hotelcustomerpaymentid = t.sourceid
        WHERE t.farmid = f AND t.sourcetype = 'CustomerPayment' AND cp.paymentgroupid = v_g2 AND t.amount = 400) <> 1 THEN
        RAISE EXCEPTION 'FAIL 4d: opening-balance ledger row'; END IF;
    v_checks := v_checks + 4;

    -- ── 5. Reverse the corporate payment (reason required, once) ───────────
    v_failed := FALSE;
    BEGIN PERFORM sphotelcustomerpayment_reverse(f, v_g2, '  ', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5a: reversal without a reason'; END IF;
    IF sphotelcustomerpayment_reverse(f, v_g2, 'bounced transfer', 'probe') <> 2 THEN RAISE EXCEPTION 'FAIL 5b: reversal count'; END IF;
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 5300 THEN
        RAISE EXCEPTION 'FAIL 5c: main after reversal'; END IF;
    IF (SELECT currentbalance FROM hotelcustomers WHERE hotelcustomerid = v_cust) <> 550
       OR (SELECT totalbalance FROM sphotelcustomerbalances(f) WHERE partyid = -v_cust) <> 550 THEN
        RAISE EXCEPTION 'FAIL 5d: balance after reversal'; END IF;
    IF (SELECT status FROM sphotelcustomerpayment_history(f) WHERE paymentid = v_g2::text) <> 'Reversed' THEN
        RAISE EXCEPTION 'FAIL 5e: history status'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelcustomerpayment_reverse(f, v_g2, 'again', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5f: reversed twice'; END IF;
    v_checks := v_checks + 6;

    -- ── 6. Old-style Draft approved: allocated oldest first, no double cash ─
    v_cp := sphotelcustomerpayment_insert(f, v_cust, 120, 'Cash', v_main, 'OLD-1', NULL, NULL, NULL, 'probe');
    PERFORM sphotelcustomerpayment_approve(v_cp, f, 'probe');
    SELECT * INTO r FROM hotelcustomerpayments WHERE hotelcustomerpaymentid = v_cp;
    IF r.status <> 'Approved' OR r.appliedgroupid IS NULL OR r.cashtransactionid IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL 6a: draft row %', row_to_json(r); END IF;
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 5420
       OR (SELECT currentbalance FROM hotelcustomers WHERE hotelcustomerid = v_cust) <> 430 THEN
        RAISE EXCEPTION 'FAIL 6b: approve moved money wrongly'; END IF;
    -- oldest first: the stay (20 days ago) before the opening balance (today)
    IF NOT EXISTS (SELECT 1 FROM hotelpayments WHERE paymentgroupid = r.appliedgroupid AND hotelbookingid = v_b4 AND amount = 120) THEN
        RAISE EXCEPTION 'FAIL 6c: not applied to the oldest document'; END IF;
    v_checks := v_checks + 3;

    -- ── 7. Supplier payables ───────────────────────────────────────────────
    INSERT INTO hotelexpenses (farmid, category, description, amount, expensedate, paymentmethod, status, hotelsupplierid)
    VALUES (f, 'Linen', 'Towels', 200, v_today - 3, 'Credit', 'Draft', v_supp) RETURNING hotelexpenseid INTO v_e1;
    INSERT INTO hotelexpenses (farmid, category, description, amount, expensedate, paymentmethod, hotelcashaccountid, status, hotelsupplierid)
    VALUES (f, 'Linen', 'Sheets', 80, v_today - 2, 'Cash', v_main, 'Draft', v_supp) RETURNING hotelexpenseid INTO v_e2;
    PERFORM sphotelexpense_approve(f, v_e1, 'probe');
    PERFORM sphotelexpense_approve(f, v_e2, 'probe');
    v_asset := sphotelcapitalasset_createpaid(f, 'Laundry machine', NULL, v_today - 1, v_today - 1, 0, 60, 1000,
                                              NULL, NULL, NULL, NULL, 'probe', v_supp, v_main, 300, v_today + 30);
    SELECT hotelcapitalassetcostid INTO v_cost FROM hotelcapitalassetcosts WHERE hotelcapitalassetid = v_asset;
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 5420 - 80 - 300 THEN
        RAISE EXCEPTION 'FAIL 7a: main after expense and asset paid now'; END IF;
    IF (SELECT totalbalance FROM sphotelsupplierbalances(f) WHERE partyid = v_supp) <> 900
       OR (SELECT currentbalance FROM hotelsuppliers WHERE hotelsupplierid = v_supp) <> 900 THEN
        RAISE EXCEPTION 'FAIL 7b: supplier owed %', (SELECT row_to_json(x) FROM sphotelsupplierbalances(f) x LIMIT 1); END IF;
    IF (SELECT count(*) FROM sphotelsupplieropenpurchases(f, v_supp)) <> 2 THEN RAISE EXCEPTION 'FAIL 7c: open purchases'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelcapitalasset_createpaid(f, 'X', NULL, v_today, v_today, 0, 60, 100, NULL, NULL, NULL, NULL, 'probe',
                  NULL, v_main, 50, NULL); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7d: unpaid part with no supplier accepted'; END IF;
    v_checks := v_checks + 4;

    -- ── 8. Supplier payment, guards, reversal ──────────────────────────────
    v_sp := sphotelsupplierpayment_record(f, v_supp, 500,
            jsonb_build_array(jsonb_build_object('documenttype', 'Expense', 'documentid', v_e1, 'amount', 200),
                              jsonb_build_object('documenttype', 'AssetCost', 'documentid', v_cost, 'amount', 300)),
            'Bank Transfer', NULL, v_main, 'SP-1', NULL, 'SupplierBalances', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 4540
       OR (SELECT currentbalance FROM hotelsuppliers WHERE hotelsupplierid = v_supp) <> 400
       OR (SELECT totalbalance FROM sphotelsupplierbalances(f) WHERE partyid = v_supp) <> 400 THEN
        RAISE EXCEPTION 'FAIL 8a: after supplier payment'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelexpense_cancel(f, v_e1, 'x', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8b: paid expense cancelled'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelcapitalasset_reversecost(v_cost, v_asset, f, 'x', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8c: paid asset cost reversed'; END IF;
    IF (SELECT allocationcount FROM sphotelsupplierpayment_history(f) WHERE paymentid = v_sp::text) <> 2 THEN
        RAISE EXCEPTION 'FAIL 8d: history'; END IF;
    PERFORM sphotelsupplierpayment_reverse(f, v_sp, 'wrong supplier', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 5040
       OR (SELECT currentbalance FROM hotelsuppliers WHERE hotelsupplierid = v_supp) <> 900
       OR (SELECT totalbalance FROM sphotelsupplierbalances(f) WHERE partyid = v_supp) <> 900 THEN
        RAISE EXCEPTION 'FAIL 8e: after supplier reversal'; END IF;
    -- old-style Draft approved: oldest first (the expense, 3 days ago)
    v_sp2 := sphotelsupplierpayment_insert(f, v_supp, 150, 'Cash', v_main, 'OLD-S', NULL, NULL, NULL, 'probe');
    PERFORM sphotelsupplierpayment_approve(v_sp2, f, 'probe');
    IF fnhotel_allocated(f, 'Expense', v_e1) <> 150
       OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 4890 THEN
        RAISE EXCEPTION 'FAIL 8f: draft approve'; END IF;
    v_cost2 := sphotelcapitalasset_addcostpaid(v_asset, f, 50, 'Installation', v_today, 'probe', v_supp, NULL, 0, NULL);
    PERFORM sphotelcapitalasset_reversecost(v_cost2, v_asset, f, 'not needed', 'probe');
    IF (SELECT currentbalance FROM hotelsuppliers WHERE hotelsupplierid = v_supp) <> 750
       OR (SELECT totalbalance FROM sphotelsupplierbalances(f) WHERE partyid = v_supp) <> 750 THEN
        RAISE EXCEPTION 'FAIL 8g: added-then-reversed credit cost'; END IF;
    v_checks := v_checks + 7;

    -- ── 9. Cash Flow = ledger; P&L; audit ──────────────────────────────────
    SELECT COALESCE(SUM(amount), 0) INTO v_n FROM sphotelcashflow_rows(f, NULL, NULL);
    SELECT COALESCE(SUM(CASE WHEN txntype = 'Credit' THEN amount ELSE -amount END), 0) INTO v_n2
    FROM hotelcashtransactions WHERE farmid = f;
    IF v_n <> v_n2 OR v_n2 <> -110 THEN RAISE EXCEPTION 'FAIL 9a: cash flow % vs ledger %', v_n, v_n2; END IF;
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 5000 + v_n2 THEN
        RAISE EXCEPTION 'FAIL 9b: account vs ledger'; END IF;
    IF (SELECT count(*) FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource IN ('CustomerPaymentReversal', 'SupplierPaymentReversal')) <> 2
       OR (SELECT count(*) FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource = 'CustomerPayment') <> 1 THEN
        RAISE EXCEPTION 'FAIL 9c: reversal / customer payment arms'; END IF;
    IF EXISTS (SELECT 1 FROM sphotelcashflow_detail(f, NULL, NULL) WHERE category = 'Other') THEN
        RAISE EXCEPTION 'FAIL 9d: unclassified cash flow row'; END IF;
    SELECT * INTO r FROM sphotelreport_plsummary(f, v_today - 60, v_today + 1);
    SELECT COALESCE(SUM(amount), 0) INTO v_n FROM hotelpayments WHERE farmid = f AND status = 'Posted';
    IF r.roomrevenue <> v_n OR r.roomrevenue <> 420 THEN RAISE EXCEPTION 'FAIL 9e: room revenue % vs %', r.roomrevenue, v_n; END IF;
    IF r.totalexpenses <> 280 THEN RAISE EXCEPTION 'FAIL 9f: expenses (accrual) %', r.totalexpenses; END IF;
    IF EXISTS (SELECT 1 FROM sphotelbalanceaudit(f)) THEN RAISE EXCEPTION 'FAIL 9g: balance audit not empty'; END IF;
    IF (SELECT count(*) FROM sphotelcustomerstatement(f, -v_cust)) < 3 OR (SELECT count(*) FROM sphotelsupplierstatement(f, v_supp)) < 3 THEN
        RAISE EXCEPTION 'FAIL 9h: statements'; END IF;
    v_checks := v_checks + 8;

    RAISE EXCEPTION 'SELFTEST PASSED (% checks)', v_checks;
END $$;

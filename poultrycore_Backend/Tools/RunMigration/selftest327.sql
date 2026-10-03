-- Self-test for migration 327 (Hotel money foundations). Append to the
-- migration and run, or run on its own after 327; it always ends by raising so
-- everything rolls back. "SELFTEST PASSED" in the error is the success signal.
--
-- The story: a guest stays 3 nights at 100 (bill 300), pays 120 at the desk,
-- then 180 by card that turns out to be a mistake and is voided. The kitchen
-- sells a walk-in 80 (cancelled) and 40 (kept), and charges 40 to the room
-- (cancelled). Expenses: 200 from Main (cancelled after approval), 50 on credit,
-- 30 with no account (old style). A deposit of 100 is taken and 40 refunded.
-- A corporate customer pays 70, a supplier is paid 60. A 1,200 asset
-- depreciates 100 a month for three months. We check every balance, the
-- ledger, the invoice, Cash Flow against the ledger, and the P&L.
DO $$
DECLARE
    f        text := '__probe327__';
    v_main   int;  v_fd int; v_pos int; v_expacct int;
    v_guest  int;  v_rt int; v_room int;
    v_b1     int;  v_b2 int; v_b3 int;
    v_menu   int;  v_menu_other int;
    v_p1     int;  v_p2 int; v_p3 int;
    v_inv    int;  v_inv2 int;
    v_e1     int;  v_e2 int; v_e3 int;
    v_o1     int;  v_o2 int; v_o3 int;
    v_d1     int;
    v_cust   int;  v_cp int;
    v_supp   int;  v_sp int;
    v_asset  int;
    v_id     int;  v_id2 int;
    v_n      numeric; v_n2 numeric; v_i int;
    v_checks int := 0;
    v_failed boolean;
    r        record;
    v_today  date := CURRENT_DATE;
BEGIN
    INSERT INTO hotelcashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance)
    VALUES (f, 'Main Cash', 'Cash', 5000, 5000) RETURNING hotelcashaccountid INTO v_main;
    INSERT INTO hotelguests (farmid, firstname, lastname) VALUES (f, 'Esi', 'Owusu') RETURNING hotelguestid INTO v_guest;
    INSERT INTO hotelroomtypes (farmid, name) VALUES (f, 'Standard') RETURNING hotelroomtypeid INTO v_rt;
    INSERT INTO hotelrooms (farmid, roomnumber, hotelroomtypeid) VALUES (f, '101', v_rt) RETURNING hotelroomid INTO v_room;
    INSERT INTO hotelbookings (farmid, bookingref, hotelguestid, hotelroomid, hotelroomtypeid, checkindate, checkoutdate, nightlyrate, totalamount, status)
    VALUES (f, 'P327-1', v_guest, v_room, v_rt, v_today - 1, v_today + 2, 100, 300, 'CheckedIn') RETURNING hotelbookingid INTO v_b1;
    INSERT INTO hotelbookings (farmid, bookingref, hotelguestid, hotelroomtypeid, checkindate, checkoutdate, nightlyrate, totalamount, status)
    VALUES (f, 'P327-2', v_guest, v_rt, v_today, v_today + 1, 50, 50, 'CheckedIn') RETURNING hotelbookingid INTO v_b2;
    INSERT INTO hotelbookings (farmid, bookingref, hotelguestid, hotelroomtypeid, checkindate, checkoutdate, nightlyrate, totalamount, status)
    VALUES (f, 'P327-3', v_guest, v_rt, v_today - 5, v_today - 3, 50, 100, 'CheckedOut') RETURNING hotelbookingid INTO v_b3;
    INSERT INTO hotelmenuitems (farmid, name, category, price) VALUES (f, 'Jollof', 'Mains', 40) RETURNING hotelmenuitemid INTO v_menu;
    INSERT INTO hotelmenuitems (farmid, name, category, price) VALUES ('__probe327_other__', 'Theirs', 'Mains', 1) RETURNING hotelmenuitemid INTO v_menu_other;

    -- ── 1. Guest payment, no account: Front Desk account, one ledger row ─────
    v_p1 := sphotelpayment_record(f, v_b1, 120, 'Cash', NULL, NULL, NULL, NULL, 'probe');
    SELECT hotelcashaccountid INTO v_fd FROM hotelcashaccounts WHERE farmid = f AND purpose = 'FrontDesk';
    IF v_fd IS NULL OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_fd) <> 120 THEN
        RAISE EXCEPTION 'FAIL 1a: front desk account %', v_fd; END IF;
    SELECT * INTO r FROM hotelpayments WHERE hotelpaymentid = v_p1;
    IF r.status <> 'Posted' OR r.cashtransactionid IS NULL OR r.hotelcashaccountid <> v_fd OR r.hotelinvoiceid IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL 1b: payment row %', row_to_json(r); END IF;
    IF (SELECT count(*) FROM hotelcashtransactions WHERE farmid = f AND sourcetype = 'Payment' AND sourceid = v_p1
          AND txntype = 'Credit' AND amount = 120) <> 1 THEN RAISE EXCEPTION 'FAIL 1c: payment ledger row'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelpayment_record(f, v_b1, 0, 'Cash'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1d: zero payment accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelpayment_record('__probe327_other__', v_b1, 10, 'Cash'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1e: payment on another company''s booking accepted'; END IF;
    v_checks := v_checks + 5;

    -- ── 2. Invoice priced from the whole bill; takes the unapplied payment ──
    v_inv := sphotelinvoice_generate(f, v_b1, 'probe');
    SELECT * INTO r FROM hotelinvoices WHERE hotelinvoiceid = v_inv;
    IF r.subtotal <> 300 OR r.totalamount <> 300 OR r.amountpaid <> 120 OR r.balance <> 180 OR r.status <> 'PartiallyPaid' THEN
        RAISE EXCEPTION 'FAIL 2a: invoice %', row_to_json(r); END IF;
    IF (SELECT hotelinvoiceid FROM hotelpayments WHERE hotelpaymentid = v_p1) IS DISTINCT FROM v_inv THEN
        RAISE EXCEPTION 'FAIL 2b: earlier payment not applied to the invoice'; END IF;
    IF sphotelinvoice_generate(f, v_b1, 'probe') <> v_inv
       OR (SELECT count(*) FROM hotelinvoices WHERE farmid = f AND hotelbookingid = v_b1) <> 1 THEN
        RAISE EXCEPTION 'FAIL 2c: generating again made a second invoice'; END IF;
    v_checks := v_checks + 3;

    -- ── 3. Card payment into Main settles the invoice; void puts it back ────
    v_p2 := sphotelpayment_record(f, v_b1, 180, 'Card', 'CARD-1', NULL, NULL, v_main, 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 5180 THEN
        RAISE EXCEPTION 'FAIL 3a: main after card payment'; END IF;
    SELECT * INTO r FROM hotelinvoices WHERE hotelinvoiceid = v_inv;
    IF r.amountpaid <> 300 OR r.balance <> 0 OR r.status <> 'Paid' THEN RAISE EXCEPTION 'FAIL 3b: invoice after full payment %', row_to_json(r); END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelpayment_void(f, v_p2, '  ', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3c: void without a reason accepted'; END IF;
    PERFORM sphotelpayment_void(f, v_p2, 'card declined', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 5000 THEN
        RAISE EXCEPTION 'FAIL 3d: main after void'; END IF;
    IF NOT EXISTS (SELECT 1 FROM hotelcashtransactions WHERE farmid = f AND sourcetype = 'PaymentReversal'
                   AND sourceid = v_p2 AND txntype = 'Debit' AND amount = 180 AND hotelcashaccountid = v_main) THEN
        RAISE EXCEPTION 'FAIL 3e: no reversal ledger row'; END IF;
    IF (SELECT count(*) FROM hotelcashtransactions WHERE farmid = f AND sourceid = v_p2 AND sourcetype = 'Payment') <> 1 THEN
        RAISE EXCEPTION 'FAIL 3f: the original ledger row was touched'; END IF;
    SELECT * INTO r FROM hotelinvoices WHERE hotelinvoiceid = v_inv;
    IF r.amountpaid <> 120 OR r.balance <> 180 OR r.status <> 'PartiallyPaid' THEN RAISE EXCEPTION 'FAIL 3g: invoice after void %', row_to_json(r); END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelpayment_void(f, v_p2, 'again', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3h: voided twice'; END IF;
    v_checks := v_checks + 8;

    -- ── 4. Ambiguous invoices: two open invoices, the payment is not guessed ─
    INSERT INTO hotelinvoices (farmid, hotelbookingid, hotelguestid, invoicenumber, subtotal, totalamount, balance, status)
    VALUES (f, v_b2, v_guest, 'DUP', 50, 50, 50, 'Issued'), (f, v_b2, v_guest, 'DUP', 50, 50, 50, 'Issued');
    v_p3 := sphotelpayment_record(f, v_b2, 10, 'Cash', NULL, NULL, NULL, v_main, 'probe');
    IF (SELECT hotelinvoiceid FROM hotelpayments WHERE hotelpaymentid = v_p3) IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL 4a: payment applied to one of two invoices'; END IF;
    SELECT min(hotelinvoiceid) INTO v_inv2 FROM hotelinvoices WHERE farmid = f AND hotelbookingid = v_b2;
    v_failed := FALSE;
    BEGIN PERFORM sphotelpayment_record(f, v_b1, 5, 'Cash', NULL, NULL, v_inv2); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4b: payment applied to another booking''s invoice'; END IF;
    PERFORM sphotelpayment_void(f, v_p3, 'probe cleanup', 'probe');  -- back to 5000 in Main
    v_checks := v_checks + 2;

    -- ── 5. Idempotent posting ───────────────────────────────────────────────
    v_id  := fnhotelcash_postonce(f, v_main, 'Credit', 7, 'probe', NULL, 'ProbeOnce', 1, 'probe');
    v_id2 := fnhotelcash_postonce(f, v_main, 'Credit', 7, 'probe', NULL, 'ProbeOnce', 1, 'probe');
    IF v_id <> v_id2 OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 5007 THEN
        RAISE EXCEPTION 'FAIL 5a: second post of the same document moved money'; END IF;
    v_failed := FALSE;
    BEGIN INSERT INTO hotelcashtransactions (farmid, hotelcashaccountid, txntype, amount, balanceafter, sourcetype, sourceid)
          VALUES (f, v_main, 'Credit', 1, 0, 'ProbeOnce', 1);
    EXCEPTION WHEN unique_violation THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5b: unique index missing'; END IF;
    PERFORM fnhotelcash_reverse(f, v_id, 'ProbeOnceReversal', 'probe', 'probe');   -- Main back to 5000
    v_checks := v_checks + 2;

    -- ── 6. Expenses ─────────────────────────────────────────────────────────
    INSERT INTO hotelexpenses (farmid, category, description, amount, paymentmethod, hotelcashaccountid)
    VALUES (f, 'Utilities', 'Power', 200, 'Cash', v_main) RETURNING hotelexpenseid INTO v_e1;
    PERFORM sphotelexpense_approve(f, v_e1, 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 4800 THEN
        RAISE EXCEPTION 'FAIL 6a: expense did not leave its own account'; END IF;
    IF EXISTS (SELECT 1 FROM hotelcashaccounts WHERE farmid = f AND purpose = 'Expenses') THEN
        RAISE EXCEPTION 'FAIL 6b: expense went to the Expenses account instead of its own'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelexpense_approve(f, v_e1, 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6c: approved twice'; END IF;
    PERFORM sphotelexpense_cancel(f, v_e1, 'duplicate bill', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 5000 THEN
        RAISE EXCEPTION 'FAIL 6d: cancel did not bring the money back'; END IF;
    IF NOT EXISTS (SELECT 1 FROM hotelcashtransactions WHERE farmid = f AND sourcetype = 'ExpenseReversal' AND sourceid = v_e1 AND txntype = 'Credit') THEN
        RAISE EXCEPTION 'FAIL 6e: no expense reversal row'; END IF;
    INSERT INTO hotelexpenses (farmid, category, description, amount, paymentmethod)
    VALUES (f, 'Supplies', 'On account', 50, 'Credit') RETURNING hotelexpenseid INTO v_e2;
    PERFORM sphotelexpense_approve(f, v_e2, 'probe');
    IF (SELECT cashtransactionid FROM hotelexpenses WHERE hotelexpenseid = v_e2) IS NOT NULL
       OR EXISTS (SELECT 1 FROM hotelcashtransactions WHERE farmid = f AND sourcetype = 'Expense' AND sourceid = v_e2) THEN
        RAISE EXCEPTION 'FAIL 6f: a credit expense moved cash'; END IF;
    INSERT INTO hotelexpenses (farmid, category, description, amount, paymentmethod)
    VALUES (f, 'Supplies', 'Old style, no account', 30, 'Cash') RETURNING hotelexpenseid INTO v_e3;
    PERFORM sphotelexpense_approve(f, v_e3, 'probe');
    SELECT hotelcashaccountid INTO v_expacct FROM hotelcashaccounts WHERE farmid = f AND purpose = 'Expenses';
    IF v_expacct IS NULL OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_expacct) <> -30 THEN
        RAISE EXCEPTION 'FAIL 6g: no-account expense fallback'; END IF;
    v_checks := v_checks + 7;

    -- ── 7. Restaurant orders ────────────────────────────────────────────────
    v_o1 := sphotelrestaurantorder_create(f, 'T1', 'Kojo', NULL, NULL,
              jsonb_build_array(jsonb_build_object('menuItemId', v_menu, 'quantity', 2, 'unitPrice', 40)), FALSE, 'Cash', NULL, 'probe');
    SELECT hotelcashaccountid INTO v_pos FROM hotelcashaccounts WHERE farmid = f AND purpose = 'POS';
    IF v_pos IS NULL OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_pos) <> 80 THEN
        RAISE EXCEPTION 'FAIL 7a: walk-in order POS cash'; END IF;
    SELECT * INTO r FROM hotelrestaurantorders WHERE hotelrestaurantorderid = v_o1;
    IF r.settlement <> 'Paid' OR r.totalamount <> 80 OR r.cashtransactionid IS NULL THEN RAISE EXCEPTION 'FAIL 7b: order %', row_to_json(r); END IF;
    IF (SELECT count(*) FROM hotelrestaurantorderitems WHERE hotelrestaurantorderid = v_o1) <> 1 THEN RAISE EXCEPTION 'FAIL 7c: order lines'; END IF;

    v_o2 := sphotelrestaurantorder_create(f, NULL, NULL, v_b1, v_room,
              jsonb_build_array(jsonb_build_object('menuItemId', v_menu, 'quantity', 1, 'unitPrice', 40)), TRUE, NULL, NULL, 'probe');
    IF EXISTS (SELECT 1 FROM hotelcashtransactions WHERE farmid = f AND sourcetype = 'Order' AND sourceid = v_o2) THEN
        RAISE EXCEPTION 'FAIL 7d: room-charged order moved cash'; END IF;
    IF (SELECT count(*) FROM hotelstaycharges WHERE farmid = f AND sourcetype = 'RestaurantOrder' AND sourceid = v_o2
          AND hotelbookingid = v_b1 AND totalamount = 40 AND chargetype = 'Restaurant') <> 1 THEN
        RAISE EXCEPTION 'FAIL 7e: room charge not on the folio'; END IF;
    IF fnhotelbooking_billtotal(f, v_b1) <> 340 THEN RAISE EXCEPTION 'FAIL 7f: bill total %', fnhotelbooking_billtotal(f, v_b1); END IF;
    PERFORM sphotelinvoice_generate(f, v_b1, 'probe');
    SELECT * INTO r FROM hotelinvoices WHERE hotelinvoiceid = v_inv;
    IF r.totalamount <> 340 OR r.balance <> 220 THEN RAISE EXCEPTION 'FAIL 7g: invoice after room charge %', row_to_json(r); END IF;

    PERFORM sphotelrestaurantorder_setstatus(f, v_o2, 'Cancelled', 'probe');
    IF fnhotelbooking_billtotal(f, v_b1) <> 300 THEN RAISE EXCEPTION 'FAIL 7h: cancelled room charge still on the bill'; END IF;
    IF (SELECT count(*) FROM hotelstaycharges WHERE farmid = f AND sourceid = v_o2) <> 2 THEN
        RAISE EXCEPTION 'FAIL 7i: the folio charge was deleted instead of offset'; END IF;
    PERFORM sphotelrestaurantorder_setstatus(f, v_o1, 'Served', 'probe');
    PERFORM sphotelrestaurantorder_setstatus(f, v_o1, 'Cancelled', 'probe');
    PERFORM sphotelrestaurantorder_setstatus(f, v_o1, 'Cancelled', 'probe');   -- repeat is harmless
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_pos) <> 0 THEN
        RAISE EXCEPTION 'FAIL 7j: cancelled paid order still in POS'; END IF;
    IF (SELECT count(*) FROM hotelcashtransactions WHERE farmid = f AND sourcetype = 'OrderReversal' AND sourceid = v_o1) <> 1 THEN
        RAISE EXCEPTION 'FAIL 7k: order reversal rows'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelrestaurantorder_setstatus(f, v_o1, 'Served', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7l: cancelled order reopened'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelrestaurantorder_create(f, NULL, NULL, v_b3, NULL,
              jsonb_build_array(jsonb_build_object('menuItemId', v_menu, 'quantity', 1, 'unitPrice', 40)), TRUE);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7m: charged to a checked-out booking'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelrestaurantorder_create(f, NULL, NULL, NULL, NULL,
              jsonb_build_array(jsonb_build_object('menuItemId', v_menu_other, 'quantity', 1, 'unitPrice', 1)), FALSE);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7n: another company''s menu item accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelrestaurantorder_create(f, NULL, NULL, NULL, NULL,
              jsonb_build_array(jsonb_build_object('menuItemId', v_menu, 'quantity', 1, 'unitPrice', 40)), TRUE);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7o: charge to room with no booking accepted'; END IF;
    -- a second walk-in order, kept: 40 into Main
    v_o3 := sphotelrestaurantorder_create(f, 'T2', NULL, NULL, NULL,
              jsonb_build_array(jsonb_build_object('menuItemId', v_menu, 'quantity', 1, 'unitPrice', 40)), FALSE, 'MobileMoney', v_main, 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 5040 THEN
        RAISE EXCEPTION 'FAIL 7p: order into the chosen account'; END IF;
    v_checks := v_checks + 16;

    -- ── 8. Deposits ─────────────────────────────────────────────────────────
    v_d1 := sphoteldeposit_record(f, v_b1, v_guest, 'Collected', 100, 'Cash', NULL, NULL, 'probe');
    v_failed := FALSE;
    BEGIN PERFORM sphoteldeposit_record(f, v_b1, v_guest, 'Refunded', 150); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8a: refund above the deposit held'; END IF;
    PERFORM sphoteldeposit_record(f, v_b1, v_guest, 'Refunded', 40, 'Cash', NULL, NULL, 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_fd) <> 180 THEN
        RAISE EXCEPTION 'FAIL 8b: front desk after deposits % (want 120 + 100 - 40)',
            (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_fd); END IF;
    v_checks := v_checks + 2;

    -- ── 9. Customer and supplier payments through the one path ──────────────
    v_cust := sphotelcustomer_insert(f, 'Acme Ltd', 'Corporate', NULL, NULL, NULL, NULL, 30, 0, 500, NULL, 'probe');
    v_cp := sphotelcustomerpayment_insert(f, v_cust, 70, 'Cash', NULL, 'CP-1', NULL, now(), NULL, 'probe');
    PERFORM sphotelcustomerpayment_approve(v_cp, f, 'probe');
    PERFORM sphotelcustomerpayment_approve(v_cp, f, 'probe');   -- idempotent
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_fd) <> 250 THEN
        RAISE EXCEPTION 'FAIL 9a: customer payment cash'; END IF;
    IF (SELECT currentbalance FROM hotelcustomers WHERE hotelcustomerid = v_cust) <> 430 THEN
        RAISE EXCEPTION 'FAIL 9b: customer balance'; END IF;
    IF (SELECT cashtransactionid FROM hotelcustomerpayments WHERE hotelcustomerpaymentid = v_cp) IS NULL THEN
        RAISE EXCEPTION 'FAIL 9c: customer payment not linked to its ledger row'; END IF;
    INSERT INTO hotelsuppliers (farmid, suppliername, openingbalance, currentbalance) VALUES (f, 'Linen Co', 300, 300)
    RETURNING hotelsupplierid INTO v_supp;
    v_sp := sphotelsupplierpayment_insert(f, v_supp, 60, 'Cash', v_main, 'SP-1', NULL, now(), NULL, 'probe');
    PERFORM sphotelsupplierpayment_approve(v_sp, f, 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 4980 THEN
        RAISE EXCEPTION 'FAIL 9d: supplier payment cash'; END IF;
    IF (SELECT currentbalance FROM hotelsuppliers WHERE hotelsupplierid = v_supp) <> 240 THEN
        RAISE EXCEPTION 'FAIL 9e: supplier balance'; END IF;
    v_checks := v_checks + 5;

    -- ── 10. An asset and three months of depreciation ───────────────────────
    v_asset := sphotelcapitalasset_create(f, 'Generator', NULL, v_today - 40, (date_trunc('month', v_today) - interval '3 months')::date,
                                          0, 12, 1200, NULL, NULL, NULL, NULL, 'probe');
    PERFORM sphotelcapitalasset_activate(v_asset, f);
    PERFORM sphotelassetdepreciation_generate(f, (date_trunc('month', v_today) - interval '1 day')::date, v_asset, 'probe');
    IF (SELECT count(*) FROM hotelassetdepreciation WHERE hotelcapitalassetid = v_asset AND status = 'Posted') <> 3 THEN
        RAISE EXCEPTION 'FAIL 10a: depreciation entries %', (SELECT count(*) FROM hotelassetdepreciation WHERE hotelcapitalassetid = v_asset); END IF;
    v_checks := v_checks + 1;

    -- ── 11. Every account = opening + its ledger (the cache is honest) ──────
    IF EXISTS (SELECT 1 FROM hotelcashaccounts a
               WHERE a.farmid = f
                 AND a.currentbalance <> a.openingbalance + COALESCE((SELECT SUM(CASE WHEN t.txntype = 'Credit' THEN t.amount ELSE -t.amount END)
                                                                     FROM hotelcashtransactions t WHERE t.hotelcashaccountid = a.hotelcashaccountid), 0)) THEN
        RAISE EXCEPTION 'FAIL 11a: an account balance disagrees with its ledger'; END IF;
    v_checks := v_checks + 1;

    -- ── 12. Cash Flow tells the same story as the ledger ────────────────────
    SELECT COALESCE(SUM(CASE WHEN txntype = 'Credit' THEN amount ELSE -amount END), 0) INTO v_n
    FROM   hotelcashtransactions WHERE farmid = f;
    SELECT COALESCE(SUM(amount), 0) INTO v_n2
    FROM   sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource <> 'CapitalAsset';
    -- ledger: 120 - 30 + 40 + 60 + 70 - 60 = 200
    IF v_n <> 200 OR v_n2 <> v_n THEN RAISE EXCEPTION 'FAIL 12a: ledger % vs cash flow %', v_n, v_n2; END IF;
    IF (SELECT SUM(amount) FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource = 'GuestPaymentVoid') <> -190 THEN
        RAISE EXCEPTION 'FAIL 12b: void rows'; END IF;
    IF (SELECT SUM(amount) FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource IN ('RestaurantOrder', 'RestaurantOrderReversal')) <> 40
       OR EXISTS (SELECT 1 FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource = 'RestaurantOrder' AND sourceid = v_o2) THEN
        RAISE EXCEPTION 'FAIL 12c: restaurant rows'; END IF;
    IF EXISTS (SELECT 1 FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource = 'Expense' AND sourceid = v_e2) THEN
        RAISE EXCEPTION 'FAIL 12d: a credit expense is in Cash Flow'; END IF;
    IF (SELECT SUM(amount) FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource IN ('Expense', 'ExpenseReversal') AND sourceid = v_e1) <> 0 THEN
        RAISE EXCEPTION 'FAIL 12e: cancelled expense does not net to zero'; END IF;
    IF (SELECT amount FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource = 'CustomerPayment') <> 70
       OR (SELECT flowgroup FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource = 'CustomerPayment') <> 'OperatingIn' THEN
        RAISE EXCEPTION 'FAIL 12f: customer payment arm'; END IF;
    IF (SELECT amount FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource = 'SupplierPayment') <> -60 THEN
        RAISE EXCEPTION 'FAIL 12g: supplier payment arm'; END IF;
    IF (SELECT amount FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource = 'CapitalAsset') <> -1200
       OR (SELECT flowgroup FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource = 'CapitalAsset') <> 'OperatingOut' THEN
        RAISE EXCEPTION 'FAIL 12h: capital asset arm'; END IF;
    SELECT * INTO r FROM sphotelcashflow_summary(f, NULL, NULL);
    IF r.netcashflow <> -1000 OR r.cashathand <> -1000 THEN RAISE EXCEPTION 'FAIL 12i: summary %', row_to_json(r); END IF;
    IF (SELECT count(*) FROM sphotelcashflow_detail(f, NULL, NULL)) <> (SELECT count(*) FROM sphotelcashflow_rows(f, NULL, NULL))
       OR EXISTS (SELECT 1 FROM sphotelcashflow_detail(f, NULL, NULL) WHERE category = 'Other') THEN
        RAISE EXCEPTION 'FAIL 12j: detail rows or an unclassified category'; END IF;
    IF (SELECT category FROM sphotelcashflow_detail(f, NULL, NULL) WHERE rowsource = 'ExpenseReversal') <> 'Utilities' THEN
        RAISE EXCEPTION 'FAIL 12k: expense reversal category'; END IF;
    v_checks := v_checks + 11;

    -- ── 13. P&L ─────────────────────────────────────────────────────────────
    SELECT * INTO r FROM sphotelreport_plsummary(f, (v_today - interval '1 year')::date, v_today + 1);
    -- revenue: room 120 (the voided 180 and 10 are out) + restaurant 40; the
    -- 60 of deposits held is NOT revenue. expenses 30 + 50; depreciation 300.
    IF r.roomrevenue <> 120 OR r.restaurantrevenue <> 40 OR r.totalrevenue <> 160 THEN
        RAISE EXCEPTION 'FAIL 13a: revenue %', row_to_json(r); END IF;
    IF r.depositsnet <> 60 THEN RAISE EXCEPTION 'FAIL 13b: deposits held %', r.depositsnet; END IF;
    IF r.totalexpenses <> 80 OR r.depreciation <> 300 OR r.totalothercosts <> 300 THEN
        RAISE EXCEPTION 'FAIL 13c: costs %', row_to_json(r); END IF;
    IF r.netprofit <> -220 OR r.status <> 'Loss' THEN RAISE EXCEPTION 'FAIL 13d: net %', row_to_json(r); END IF;
    IF NOT EXISTS (SELECT 1 FROM sphotelreport_pllines(f, (v_today - interval '1 year')::date, v_today + 1)
                   WHERE section = 'OtherCost' AND linekey = 'Depreciation' AND amount = 300 AND entrycount = 3)
       OR EXISTS (SELECT 1 FROM sphotelreport_pllines(f, (v_today - interval '1 year')::date, v_today + 1) WHERE linekey = 'DepositsNet') THEN
        RAISE EXCEPTION 'FAIL 13e: lines'; END IF;
    SELECT COALESCE(SUM(amount), 0), count(*) INTO v_n, v_i
    FROM   sphotelreport_plexpensedetail(f, (v_today - interval '1 year')::date, v_today + 1, 'Depreciation');
    IF v_n <> 300 OR v_i <> 3 THEN RAISE EXCEPTION 'FAIL 13f: depreciation drilldown % / %', v_n, v_i; END IF;
    IF EXISTS (SELECT 1 FROM sphotelreport_plexpensedetail(f, (v_today - interval '1 year')::date, v_today + 1, NULL) WHERE pllinekey = 'Depreciation') THEN
        RAISE EXCEPTION 'FAIL 13g: depreciation leaked into the all-expenses drilldown'; END IF;
    IF (SELECT SUM(amount) FROM sphotelreport_plrevenuedetail(f, (v_today - interval '1 year')::date, v_today + 1, NULL)) <> r.totalrevenue THEN
        RAISE EXCEPTION 'FAIL 13h: revenue drilldown disagrees with the total'; END IF;
    v_checks := v_checks + 8;

    -- ── 14. Tenant isolation of the posting path ────────────────────────────
    v_failed := FALSE;
    BEGIN PERFORM fnhotelcash_postonce('__probe327_other__', v_main, 'Credit', 1, 'x', NULL, 'Probe', 2, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 14a: posted into another company''s account'; END IF;
    v_checks := v_checks + 1;

    RAISE EXCEPTION 'SELFTEST PASSED (% checks)', v_checks;
END $$;

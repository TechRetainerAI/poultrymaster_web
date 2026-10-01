-- Self-test for migration 331 (Hotel Owner Money, Loans, Cash Transfers,
-- Reconciliation, cash adjustments, the Cash Account feed). Append to the
-- migration and run, or run on its own after 331; it always ends by raising so
-- everything rolls back. "SELFTEST PASSED" in the error is the success signal.
--
-- The story: Main Cash opens at 1,000 and the Bank at 0. The owner puts in 500
-- and takes out 200 (reversed). A bank lends 10,000 but pays out 9,800; two
-- repayments (one reversed); a small loan is cancelled; another is paid off and
-- the payoff reversed. Money moves Bank -> Main (reversed) and Main -> Bank.
-- Two adjustments, one reversed. Main is counted 30 short (then reversed) and
-- counted again balanced. We check every balance, the ledger, Cash Flow against
-- the ledger, transfer volume and the P&L's cost of borrowing.
DO $$
DECLARE
    f        text := '__probe331__';
    g        text := '__probe331_other__';
    v_main   int;  v_bank int; v_other int;
    v_om1    int;  v_om2 int;
    v_l1     int;  v_l2 int; v_l3 int;
    v_p1     int;  v_p2 int; v_p3 int;
    v_t1     int;  v_t2 int;
    v_c1     int;  v_c2 int;
    v_a1     int;  v_a2 int;
    v_id     int;
    v_n      numeric; v_n2 numeric; v_i int;
    v_checks int := 0;
    v_failed boolean;
    r        record;
    v_today  date := CURRENT_DATE;
BEGIN
    INSERT INTO hotelcashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance)
    VALUES (f, 'Main Cash', 'FrontDeskCash', 1000, 1000) RETURNING hotelcashaccountid INTO v_main;
    INSERT INTO hotelcashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance)
    VALUES (f, 'Bank', 'Bank', 0, 0) RETURNING hotelcashaccountid INTO v_bank;
    INSERT INTO hotelcashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance)
    VALUES (g, 'Theirs', 'Cash', 100, 100) RETURNING hotelcashaccountid INTO v_other;

    IF (SELECT allownegativebalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) THEN
        RAISE EXCEPTION 'FAIL 0a: new account allows negative by default'; END IF;
    v_checks := v_checks + 1;

    -- ── 1. Owner money ──────────────────────────────────────────────────────
    v_om1 := sphotelownermoney_record(f, 'Contribution', 500, v_main, NULL, 'Cash', 'Ama', 'REF1', NULL, 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 1500 THEN
        RAISE EXCEPTION 'FAIL 1a: contribution balance'; END IF;
    IF (SELECT count(*) FROM hotelcashtransactions WHERE farmid = f AND sourcetype = 'OwnerMoney' AND sourceid = v_om1
          AND txntype = 'Credit' AND amount = 500) <> 1 THEN RAISE EXCEPTION 'FAIL 1b: contribution ledger row'; END IF;
    IF (SELECT transactionnumber FROM hotelownermoney WHERE hotelownermoneyid = v_om1) NOT LIKE 'OWN-%' THEN
        RAISE EXCEPTION 'FAIL 1c: contribution number'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelownermoney_record(f, 'Draw', 2000, v_main); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1d: overdrawing draw accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelownermoney_record(f, 'Gift', 10, v_main); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1e: unknown owner money type accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelownermoney_record(f, 'Contribution', 10, v_other); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1f: another company''s account accepted'; END IF;
    v_om2 := sphotelownermoney_record(f, 'Draw', 200, v_main, NULL, 'Cash', 'Ama', NULL, 'school fees', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 1300 THEN
        RAISE EXCEPTION 'FAIL 1g: draw balance'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelownermoney_reverse(f, v_om2, '  ', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1h: reversal without reason accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelownermoney_reverse(g, v_om2, 'not yours', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1i: another company reversed our owner money'; END IF;
    PERFORM sphotelownermoney_reverse(f, v_om2, 'typed twice', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 1500 THEN
        RAISE EXCEPTION 'FAIL 1j: draw reversal balance'; END IF;
    IF (SELECT count(*) FROM hotelcashtransactions WHERE farmid = f AND sourceid = v_om2
          AND sourcetype IN ('OwnerMoney', 'OwnerMoneyReversal')) <> 2 THEN
        RAISE EXCEPTION 'FAIL 1k: draw + reversal should be two ledger rows'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelownermoney_reverse(f, v_om2, 'again', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1l: reversed twice'; END IF;
    SELECT * INTO r FROM sphotelownermoney_summary(f, NULL, NULL);
    IF r.totalcontributions <> 500 OR r.totaldraws <> 0 OR r.netfunding <> 500 OR r.contributioncount <> 1 OR r.drawcount <> 0 THEN
        RAISE EXCEPTION 'FAIL 1m: summary %', row_to_json(r); END IF;
    IF (SELECT count(*) FROM sphotelownermoney_list(f, NULL, NULL, NULL, NULL)) <> 2
       OR (SELECT count(*) FROM sphotelownermoney_list(f, 'Draw', NULL, NULL, 'Reversed')) <> 1 THEN
        RAISE EXCEPTION 'FAIL 1n: list filters'; END IF;
    v_checks := v_checks + 14;

    -- ── 2. Loans ────────────────────────────────────────────────────────────
    v_failed := FALSE;
    BEGIN PERFORM sphotelloan_create(f, 'GCB', 100, v_today, 150, v_bank); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2a: received above principal accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelloan_create(f, 'GCB', 100, v_today, 50, NULL); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2b: money received into no account accepted'; END IF;
    v_l1 := sphotelloan_create(f, 'GCB Bank', 10000, v_today, 9800, v_bank, 'Bank', 'ACC-9', NULL, 18, 'ReducingBalance', 12, 'Monthly', NULL, v_today + 30, NULL, 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_bank) <> 9800 THEN
        RAISE EXCEPTION 'FAIL 2c: amount received'; END IF;
    SELECT * INTO r FROM hotelloans WHERE hotelloanid = v_l1;
    IF r.outstandingprincipal <> 10000 OR r.status <> 'Active' OR r.loannumber NOT LIKE 'LN-%' OR r.cashtransactionid IS NULL THEN
        RAISE EXCEPTION 'FAIL 2d: loan row %', row_to_json(r); END IF;
    -- repayment: 1,000 principal + 200 interest + 50 fees = ONE cash row of 1,250
    v_p1 := sphotelloanpayment_record(f, v_l1, v_bank, 1000, 200, 50, 0, NULL, 'BankTransfer', 'R1', NULL, NULL, 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_bank) <> 8550 THEN
        RAISE EXCEPTION 'FAIL 2e: repayment cash'; END IF;
    IF (SELECT count(*) FROM hotelcashtransactions WHERE farmid = f AND sourcetype = 'LoanPayment' AND sourceid = v_p1) <> 1
       OR (SELECT amount FROM hotelcashtransactions WHERE farmid = f AND sourcetype = 'LoanPayment' AND sourceid = v_p1) <> 1250 THEN
        RAISE EXCEPTION 'FAIL 2f: repayment must be ONE cash row for the total'; END IF;
    IF EXISTS (SELECT 1 FROM hotelexpenses WHERE farmid = f) THEN
        RAISE EXCEPTION 'FAIL 2g: a repayment wrote an expense'; END IF;
    SELECT * INTO r FROM hotelloans WHERE hotelloanid = v_l1;
    IF r.outstandingprincipal <> 9000 OR r.totalprincipalrepaid <> 1000 OR r.totalinterestpaid <> 200 OR r.totalfeespaid <> 50 THEN
        RAISE EXCEPTION 'FAIL 2h: loan totals %', row_to_json(r); END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelloanpayment_record(f, v_l1, v_bank, 9001, 0, 0, 0); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2i: principal above outstanding accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelloanpayment_record(f, v_l1, v_bank, 0, 100000, 0, 0); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2j: overdrawing repayment accepted'; END IF;
    v_p2 := sphotelloanpayment_record(f, v_l1, v_bank, 500, 100, 0, 0, NULL, NULL, NULL, NULL, NULL, 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_bank) <> 7950 THEN
        RAISE EXCEPTION 'FAIL 2k: second repayment'; END IF;
    PERFORM sphotelloanpayment_reverse(f, v_p2, 'wrong loan', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_bank) <> 8550
       OR (SELECT outstandingprincipal FROM hotelloans WHERE hotelloanid = v_l1) <> 9000
       OR (SELECT totalinterestpaid FROM hotelloans WHERE hotelloanid = v_l1) <> 200 THEN
        RAISE EXCEPTION 'FAIL 2l: repayment reversal'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelloanpayment_reverse(f, v_p2, 'again', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2m: repayment reversed twice'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelloan_cancel(f, v_l1, 'changed mind', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2n: loan with repayments cancelled'; END IF;
    -- a small loan into Main, cancelled: the money goes back
    v_l2 := sphotelloan_create(f, 'Uncle Kofi', 300, v_today, 300, v_main, 'FamilyFriend', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 1800 THEN
        RAISE EXCEPTION 'FAIL 2o: small loan received'; END IF;
    PERFORM sphotelloan_cancel(f, v_l2, 'never happened', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 1500
       OR (SELECT status FROM hotelloans WHERE hotelloanid = v_l2) <> 'Cancelled'
       OR NOT EXISTS (SELECT 1 FROM hotelcashtransactions WHERE farmid = f AND sourcetype = 'LoanReceivedReversal' AND sourceid = v_l2) THEN
        RAISE EXCEPTION 'FAIL 2p: loan cancel'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelloanpayment_record(f, v_l2, v_main, 10, 0, 0, 0); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2q: cancelled loan repaid'; END IF;
    -- a loan with no money received, paid off and the payoff reversed
    v_l3 := sphotelloan_create(f, 'Supplier credit', 100, v_today, 0, NULL, 'Supplier', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'probe');
    IF (SELECT cashtransactionid FROM hotelloans WHERE hotelloanid = v_l3) IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL 2r: a loan with nothing received moved cash'; END IF;
    v_p3 := sphotelloanpayment_record(f, v_l3, v_main, 100, 0, 0, 0, NULL, NULL, NULL, NULL, NULL, 'probe');
    IF (SELECT status FROM hotelloans WHERE hotelloanid = v_l3) <> 'PaidOff'
       OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 1400 THEN
        RAISE EXCEPTION 'FAIL 2s: payoff'; END IF;
    PERFORM sphotelloanpayment_reverse(f, v_p3, 'bounced', 'probe');
    IF (SELECT status FROM hotelloans WHERE hotelloanid = v_l3) <> 'Active'
       OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 1500 THEN
        RAISE EXCEPTION 'FAIL 2t: payoff reversal'; END IF;
    SELECT * INTO r FROM sphotelloan_summary(f);
    IF r.activeloans <> 2 OR r.totalborrowed <> 10100 OR r.totalreceived <> 9800 OR r.outstandingprincipal <> 9100
       OR r.totalprincipalrepaid <> 1000 OR r.totalinterestpaid <> 200 OR r.totalfeespaid <> 50 THEN
        RAISE EXCEPTION 'FAIL 2u: loan summary %', row_to_json(r); END IF;
    IF (SELECT count(*) FROM sphotelloanpayment_list(f, v_l1)) <> 2 OR (SELECT count(*) FROM sphotelloan_list(f, 'Cancelled')) <> 1 THEN
        RAISE EXCEPTION 'FAIL 2v: loan lists'; END IF;
    v_checks := v_checks + 22;

    -- ── 3. Cash transfers ───────────────────────────────────────────────────
    v_failed := FALSE;
    BEGIN PERFORM sphotelcashtransfer_record(f, v_main, v_main, 10); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3a: transfer to the same account accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelcashtransfer_record(f, v_main, v_bank, 999999); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3b: overdrawing transfer accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelcashtransfer_record(f, v_main, v_other, 10); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3c: transfer into another company''s account accepted'; END IF;
    v_t1 := sphotelcashtransfer_record(f, v_bank, v_main, 1000, NULL, 'DEP-1', 'Bank withdrawal', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_bank) <> 7550
       OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 2500 THEN
        RAISE EXCEPTION 'FAIL 3d: transfer legs'; END IF;
    IF (SELECT count(*) FROM hotelcashtransactions WHERE farmid = f AND sourceid = v_t1 AND sourcetype IN ('TransferOut', 'TransferIn')) <> 2 THEN
        RAISE EXCEPTION 'FAIL 3e: transfer should be exactly two ledger rows'; END IF;
    PERFORM sphotelcashtransfer_reverse(f, v_t1, 'wrong direction', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_bank) <> 8550
       OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 1500
       OR (SELECT status FROM hotelcashtransfers WHERE hotelcashtransferid = v_t1) <> 'Reversed'
       OR (SELECT count(*) FROM hotelcashtransactions WHERE farmid = f AND sourceid = v_t1 AND sourcetype LIKE 'Transfer%') <> 4 THEN
        RAISE EXCEPTION 'FAIL 3f: transfer reversal'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelcashtransfer_reverse(f, v_t1, 'again', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3g: transfer reversed twice'; END IF;
    v_t2 := sphotelcashtransfer_record(f, v_main, v_bank, 100, NULL, NULL, 'Bank deposit', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 1400 THEN
        RAISE EXCEPTION 'FAIL 3h: second transfer'; END IF;
    -- the destination cannot give back money it no longer holds
    PERFORM sphotelcashadjustment_record(f, v_bank, -8650, 'Other: probe drain', 'probe');
    v_failed := FALSE;
    BEGIN PERFORM sphotelcashtransfer_reverse(f, v_t2, 'probe', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3i: reversal overdrew the destination'; END IF;
    SELECT hotelcashadjustmentid INTO v_id FROM hotelcashadjustments WHERE farmid = f AND reason = 'Other: probe drain';
    PERFORM sphotelcashadjustment_reverse(f, v_id, 'probe drain undone', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_bank) <> 8650 THEN
        RAISE EXCEPTION 'FAIL 3j: bank after drain undone %', (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_bank); END IF;
    v_checks := v_checks + 10;

    -- ── 4. Cash adjustments ────────────────────────────────────────────────
    v_a1 := sphotelcashadjustment_record(f, v_main, 40, 'Unrecorded income', 'probe');
    v_a2 := sphotelcashadjustment_record(f, v_bank, -20, 'Bank charge', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 1440
       OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_bank) <> 8630 THEN
        RAISE EXCEPTION 'FAIL 4a: adjustments'; END IF;
    PERFORM sphotelcashadjustment_reverse(f, v_a2, 'charge refunded', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_bank) <> 8650 THEN
        RAISE EXCEPTION 'FAIL 4b: adjustment reversal'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelcashadjustment_record(f, v_main, 0, 'Other'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4c: zero adjustment accepted'; END IF;
    v_checks := v_checks + 3;

    -- ── 5. Reconciliation ──────────────────────────────────────────────────
    -- a stale cache (the hand-set balances on dev) must not reach the counter
    UPDATE hotelcashaccounts SET currentbalance = currentbalance + 50 WHERE hotelcashaccountid = v_main;
    SELECT * INTO r FROM sphotelcashaccount_countstatus(f) WHERE hotelcashaccountid = v_main;
    IF r.ledgerbalance <> 1440 OR r.cachedrift <> 50 OR r.lastreconciledat IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL 5a: count status %', row_to_json(r); END IF;
    v_c1 := sphotelcashrecon_insert(f, v_main, NULL, 1400, 'Cash shortage', NULL, 'probe');
    v_failed := FALSE;
    BEGIN PERFORM sphotelcashrecon_insert(f, v_main, NULL, 1, NULL, NULL, 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5b: second open draft accepted'; END IF;
    PERFORM sphotelcashrecon_update(f, v_c1, NULL, 1410, 'Cash shortage', 'recounted');
    SELECT * INTO r FROM hotelcashreconciliations WHERE hotelcashreconciliationid = v_c1;
    IF r.status <> 'Draft' OR r.systembalance <> 1440 OR r.difference <> -30 OR r.referenceno NOT LIKE 'CC-%' THEN
        RAISE EXCEPTION 'FAIL 5c: draft %', row_to_json(r); END IF;
    IF EXISTS (SELECT 1 FROM hotelcashtransactions WHERE farmid = f AND sourcetype = 'ReconciliationAdjustment') THEN
        RAISE EXCEPTION 'FAIL 5d: a draft moved money'; END IF;
    v_id := sphotelcashrecon_post(f, v_c1, 'probe');
    IF v_id IS NULL OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 1410 THEN
        RAISE EXCEPTION 'FAIL 5e: posted count balance %', (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main); END IF;
    IF (SELECT txntype || amount::text FROM hotelcashtransactions WHERE hotelcashtxnid = v_id) <> 'Debit30.00' THEN
        RAISE EXCEPTION 'FAIL 5f: adjustment row'; END IF;
    IF sphotelcashrecon_post(f, v_c1, 'probe') <> v_id THEN RAISE EXCEPTION 'FAIL 5g: posting twice moved money'; END IF;
    IF (SELECT lastreconciledbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 1410 THEN
        RAISE EXCEPTION 'FAIL 5h: last reconciled'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelcashrecon_delete(f, v_c1); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5i: posted count deleted'; END IF;
    PERFORM sphotelcashrecon_reverse(f, v_c1, 'Miscounted', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 1440
       OR (SELECT lastreconciledat FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) IS NOT NULL
       OR (SELECT status FROM hotelcashreconciliations WHERE hotelcashreconciliationid = v_c1) <> 'Reversed' THEN
        RAISE EXCEPTION 'FAIL 5j: count reversal'; END IF;
    -- a balanced count moves nothing; a draft can be discarded
    v_c2 := sphotelcashrecon_insert(f, v_main, NULL, 1440, NULL, NULL, 'probe');
    IF sphotelcashrecon_post(f, v_c2, 'probe') IS NOT NULL THEN RAISE EXCEPTION 'FAIL 5k: balanced count posted money'; END IF;
    v_id := sphotelcashrecon_insert(f, v_bank, NULL, 1, NULL, NULL, 'probe');
    PERFORM sphotelcashrecon_delete(f, v_id);
    IF EXISTS (SELECT 1 FROM hotelcashreconciliations WHERE hotelcashreconciliationid = v_id) THEN
        RAISE EXCEPTION 'FAIL 5l: draft not discarded'; END IF;
    IF (SELECT count(*) FROM sphotelcashrecon_list(f, v_main)) <> 2 THEN RAISE EXCEPTION 'FAIL 5m: recon list'; END IF;
    v_checks := v_checks + 13;

    -- ── 6. Recalculate and the account edit ────────────────────────────────
    UPDATE hotelcashaccounts SET currentbalance = 9999 WHERE hotelcashaccountid = v_bank;
    -- (called first: a subquery in the same IF would read the pre-update snapshot)
    v_i := sphotelcashaccount_recalculate(f);
    IF v_i <> 1
       OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_bank) <> 8650 THEN
        RAISE EXCEPTION 'FAIL 6a: recalculate'; END IF;
    IF EXISTS (SELECT 1 FROM hotelcashtransactions WHERE farmid = f AND sourcetype ILIKE '%recalc%') THEN
        RAISE EXCEPTION 'FAIL 6b: recalculate wrote a ledger row'; END IF;
    PERFORM sphotelcashaccount_update(f, v_main, 'Front Desk Cash', 'FrontDeskCash', TRUE, TRUE, 'till', 'FrontDesk');
    SELECT * INTO r FROM hotelcashaccounts WHERE hotelcashaccountid = v_main;
    IF r.accountname <> 'Front Desk Cash' OR NOT r.allownegativebalance OR r.purpose <> 'FrontDesk' OR r.currentbalance <> 1440 THEN
        RAISE EXCEPTION 'FAIL 6c: account edit %', row_to_json(r); END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelcashaccount_update(g, v_main, 'x', NULL, NULL, NULL, NULL); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6d: another company edited our account'; END IF;
    v_checks := v_checks + 4;

    -- ── 7. Every account = opening + its ledger ─────────────────────────────
    IF EXISTS (SELECT 1 FROM hotelcashaccounts a
               WHERE a.farmid IN (f, g)
                 AND a.currentbalance <> a.openingbalance + COALESCE((SELECT SUM(CASE WHEN t.txntype = 'Credit' THEN t.amount ELSE -t.amount END)
                                                                     FROM hotelcashtransactions t WHERE t.hotelcashaccountid = a.hotelcashaccountid), 0)) THEN
        RAISE EXCEPTION 'FAIL 7a: an account balance disagrees with its ledger'; END IF;
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_other) <> 100 THEN
        RAISE EXCEPTION 'FAIL 7b: another company''s account moved'; END IF;
    v_checks := v_checks + 2;

    -- ── 8. Cash Flow tells the same story as the ledger ─────────────────────
    SELECT COALESCE(SUM(CASE WHEN txntype = 'Credit' THEN amount ELSE -amount END), 0) INTO v_n
    FROM   hotelcashtransactions WHERE farmid = f;
    SELECT COALESCE(SUM(amount), 0) INTO v_n2
    FROM   sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource <> 'CapitalAsset';
    -- 500 contributed + 9,800 borrowed - 1,250 repaid + 40 adjusted = 9,090
    IF v_n <> 9090 OR v_n2 <> v_n THEN RAISE EXCEPTION 'FAIL 8a: ledger % vs cash flow %', v_n, v_n2; END IF;
    IF EXISTS (SELECT 1 FROM sphotelcashflow_rows(f, NULL, NULL) WHERE sourcetype LIKE 'Transfer%' OR description LIKE 'Transfer %') THEN
        RAISE EXCEPTION 'FAIL 8b: a transfer reached Cash Flow'; END IF;
    IF (SELECT SUM(amount) FROM sphotelcashflow_rows(f, NULL, NULL) WHERE flowgroup = 'FinancingIn') <> 500 + 200 + 9800 + 300 + 600 + 100
       OR (SELECT SUM(amount) FROM sphotelcashflow_rows(f, NULL, NULL) WHERE flowgroup = 'FinancingOut') <> -(200 + 300 + 1250 + 600 + 100) THEN
        RAISE EXCEPTION 'FAIL 8c: financing groups'; END IF;
    IF (SELECT amount FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource = 'FinancingLoanPayment' AND sourcerowid = v_p1) <> -1250 THEN
        RAISE EXCEPTION 'FAIL 8d: repayment must be the total on Cash Flow'; END IF;
    IF (SELECT SUM(amount) FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource IN ('ReconciliationAdjustment', 'ReconciliationReversal')) <> 0
       OR EXISTS (SELECT 1 FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource LIKE 'Reconciliation%' AND flowgroup NOT LIKE 'Operating%') THEN
        RAISE EXCEPTION 'FAIL 8e: reconciliation rows'; END IF;
    IF (SELECT count(*) FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource = 'CashAdjustment') <> 3 THEN
        RAISE EXCEPTION 'FAIL 8f: adjustment rows'; END IF;
    IF EXISTS (SELECT 1 FROM sphotelcashflow_detail(f, NULL, NULL) WHERE category = 'Other')
       OR (SELECT count(*) FROM sphotelcashflow_detail(f, NULL, NULL)) <> (SELECT count(*) FROM sphotelcashflow_rows(f, NULL, NULL)) THEN
        RAISE EXCEPTION 'FAIL 8g: detail rows or an unclassified category'; END IF;
    IF (SELECT SUM(amount) FROM sphotelcashflow_detail(f, NULL, NULL) WHERE category = 'OwnerDraw') <> 0
       OR (SELECT SUM(amount) FROM sphotelcashflow_detail(f, NULL, NULL) WHERE category = 'OwnerContribution') <> 500
       OR (SELECT SUM(amount) FROM sphotelcashflow_detail(f, NULL, NULL) WHERE category = 'LoanRepayment') <> -1250 THEN
        RAISE EXCEPTION 'FAIL 8h: categories'; END IF;
    SELECT * INTO r FROM sphotelcashflow_summary(f, NULL, NULL);
    IF r.netcashflow <> 9090 OR r.transfervolume <> 100 THEN RAISE EXCEPTION 'FAIL 8i: summary %', row_to_json(r); END IF;
    v_checks := v_checks + 9;

    -- ── 9. P&L: only the cost of borrowing ──────────────────────────────────
    SELECT * INTO r FROM sphotelreport_plsummary(f, (v_today - interval '1 year')::date, v_today + 1);
    IF r.totalrevenue <> 0 OR r.totalexpenses <> 0 THEN
        RAISE EXCEPTION 'FAIL 9a: owner money / loans reached revenue or expenses %', row_to_json(r); END IF;
    IF r.totalothercosts <> 250 OR r.netprofit <> -250 THEN RAISE EXCEPTION 'FAIL 9b: cost of borrowing %', row_to_json(r); END IF;
    IF NOT EXISTS (SELECT 1 FROM sphotelreport_pllines(f, (v_today - interval '1 year')::date, v_today + 1)
                   WHERE section = 'OtherCost' AND linekey = 'LoanInterest' AND lineLabel = 'Loan Interest' AND amount = 200 AND entrycount = 1)
       OR NOT EXISTS (SELECT 1 FROM sphotelreport_pllines(f, (v_today - interval '1 year')::date, v_today + 1)
                   WHERE section = 'OtherCost' AND linekey = 'LoanFees' AND amount = 50) THEN
        RAISE EXCEPTION 'FAIL 9c: P&L lines'; END IF;
    SELECT COALESCE(SUM(amount), 0), count(*) INTO v_n, v_i
    FROM   sphotelreport_plexpensedetail(f, (v_today - interval '1 year')::date, v_today + 1, 'LoanInterest');
    IF v_n <> 200 OR v_i <> 1 THEN RAISE EXCEPTION 'FAIL 9d: interest drilldown % / %', v_n, v_i; END IF;
    IF EXISTS (SELECT 1 FROM sphotelreport_plexpensedetail(f, (v_today - interval '1 year')::date, v_today + 1, NULL)) THEN
        RAISE EXCEPTION 'FAIL 9e: loan rows leaked into the all-expenses drilldown'; END IF;
    v_checks := v_checks + 5;

    RAISE EXCEPTION 'SELFTEST PASSED (% checks)', v_checks;
END $$;

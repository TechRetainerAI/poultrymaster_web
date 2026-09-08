-- Behavioural checks for migration 252: reversing a poultry cash transfer.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y", then negative
-- cases that must each be blocked. Run inside a transaction you ROLL BACK; it
-- creates cash accounts and transfers.
--
--   psql ... -X -c "BEGIN;" -f poultry-cash-transfer-reversal.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 252
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- The claims this file tests:
--   1. A transfer still moves money exactly as it did before, and now carries a
--      number, a reference and the ids of the two legs it wrote.
--   2. **A reversal puts both accounts back and leaves all four ledger rows
--      standing.** Nothing is deleted and no balance is edited directly.
--   3. **Neither the transfer nor its reversal moves company-wide cash flow.**
--      This is the whole point of an internal transfer, and it is asserted
--      against the live cash-flow summary, not against a re-implementation of
--      it in this file.
--   4. The negative-balance guard FLIPS on reversal: approving checks the
--      source, reversing checks the destination, because that is the account
--      the money leaves the second time.
--   5. A transfer can no longer name another farm's cash account.

DO $t$
DECLARE
    v_farm  text := '7b95dafa-758f-4461-891d-f612131978fd';   -- Dev Test Farm (Poultry)
    -- A DIFFERENT poultry farm, for the ownership check. Never written to.
    v_other text := 'b55bf33e-a5ba-4d9b-a287-1dea39a84f13';   -- Sky Farm

    v_from integer; v_to integer; v_otheracct integer;
    v_xfer integer; v_xfer2 integer;
    v_in0 numeric; v_out0 numeric; v_net0 numeric;
    v_in1 numeric; v_out1 numeric; v_net1 numeric;
    v_in2 numeric; v_out2 numeric; v_net2 numeric;
    v_num text;
BEGIN
    -- =====================================================================
    -- Setup. Two accounts, neither allowed to go negative.
    -- =====================================================================
    INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance,
                                     currentbalance, allownegativebalance, isactive)
    VALUES (v_farm, 'ZZ Transfer Source', 'BankAccount', 10000, 10000, FALSE, TRUE)
    RETURNING poultrycashaccountid INTO v_from;

    INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance,
                                     currentbalance, allownegativebalance, isactive)
    VALUES (v_farm, 'ZZ Transfer Destination', 'MoMoWallet', 0, 0, FALSE, TRUE)
    RETURNING poultrycashaccountid INTO v_to;

    SELECT poultrycashaccountid INTO v_otheracct
    FROM   poultrycashaccounts WHERE farmid = v_other ORDER BY 1 LIMIT 1;

    -- Company-wide cash flow BEFORE any transfer exists. Seeding accounts moves
    -- cash at hand, but must not have moved money in or money out.
    SELECT s.moneyin, s.moneyout, s.netcashflow INTO v_in0, v_out0, v_net0
    FROM   sppoultrycashflow_summary(v_farm, NULL, NULL) s;

    -- =====================================================================
    -- A. Recording a transfer.
    -- =====================================================================
    v_xfer := sppoultrycashtransfer_insert(
        p_farmid                   => v_farm,
        p_frompoultrycashaccountid => v_from,
        p_topoultrycashaccountid   => v_to,
        p_amount                   => 2500,
        p_transferdate             => (now() at time zone 'utc'),
        p_notes                    => 'ZZ test transfer',
        p_createdby                => 'ZZ tester',
        p_referencenumber          => 'MOMO-778899');

    SELECT transfernumber INTO v_num FROM poultrycashtransfers WHERE poultrycashtransferid = v_xfer;

    RAISE NOTICE 'A1. starts as a draft       expect    Draft  got %',
        (SELECT status FROM poultrycashtransfers WHERE poultrycashtransferid = v_xfer);
    -- TRF-YYYY-0001 style, stamped from the identity after insert.
    RAISE NOTICE 'A2. it has a number         expect        t  got %',
        (v_num LIKE 'TRF-%' AND v_num LIKE ('%' || lpad(v_xfer::text, 4, '0')));
    RAISE NOTICE 'A3. reference kept          expect MOMO-778899  got %',
        (SELECT referencenumber FROM poultrycashtransfers WHERE poultrycashtransferid = v_xfer);
    -- A draft has moved nothing.
    RAISE NOTICE 'A4. draft moved no money    expect 10000.00  got %',
        (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_from);

    -- =====================================================================
    -- B. Approving it.
    -- =====================================================================
    PERFORM sppoultrycashtransfer_approve(v_xfer, v_farm, 'ZZ tester');

    RAISE NOTICE 'B1. source is down          expect  7500.00  got %',
        (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_from);
    RAISE NOTICE 'B2. destination is up       expect  2500.00  got %',
        (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_to);
    RAISE NOTICE 'B3. two ledger rows         expect        2  got %',
        (SELECT COUNT(*) FROM poultrycashtransactions
          WHERE farmid = v_farm AND sourcetype = 'Transfer' AND sourceid = v_xfer);
    -- The legs are stamped on the transfer, so the link is one lookup.
    RAISE NOTICE 'B4. out leg recorded        expect        t  got %',
        (SELECT outgoingcashtransactionid IS NOT NULL FROM poultrycashtransfers
          WHERE poultrycashtransferid = v_xfer);
    RAISE NOTICE 'B5. in leg recorded         expect        t  got %',
        (SELECT incomingcashtransactionid IS NOT NULL FROM poultrycashtransfers
          WHERE poultrycashtransferid = v_xfer);
    RAISE NOTICE 'B6. and they are the legs   expect        t  got %',
        (SELECT t.outgoingcashtransactionid <> t.incomingcashtransactionid
           AND (SELECT amount FROM poultrycashtransactions WHERE poultrycashtransactionid = t.outgoingcashtransactionid) < 0
           AND (SELECT amount FROM poultrycashtransactions WHERE poultrycashtransactionid = t.incomingcashtransactionid) > 0
         FROM poultrycashtransfers t WHERE t.poultrycashtransferid = v_xfer);

    -- THE claim. Money moved between two boxes; the company neither received
    -- nor spent anything.
    SELECT s.moneyin, s.moneyout, s.netcashflow INTO v_in1, v_out1, v_net1
    FROM   sppoultrycashflow_summary(v_farm, NULL, NULL) s;
    RAISE NOTICE 'B7. money in unmoved        expect        t  got %', (v_in1 = v_in0);
    RAISE NOTICE 'B8. money out unmoved       expect        t  got %', (v_out1 = v_out0);
    RAISE NOTICE 'B9. net cash flow unmoved   expect        t  got %', (v_net1 = v_net0);
    -- Poultry cash flow (235) reads business documents, not the cash ledger, so
    -- a transfer cannot reach it at all. Pinned here: if the ledger arm is ever
    -- restored without the transfer exclusion, this line fails loudly.
    RAISE NOTICE 'B10. no transfer row at all expect        0  got %',
        (SELECT COUNT(*) FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r
          WHERE r.sourcetype = 'Transfer');

    -- =====================================================================
    -- C. Reversing it.
    -- =====================================================================
    PERFORM sppoultrycashtransfer_reverse(v_xfer, v_farm, 'Wrong account picked', 'ZZ tester');

    RAISE NOTICE 'C1. marked reversed         expect Reversed  got %',
        (SELECT status FROM poultrycashtransfers WHERE poultrycashtransferid = v_xfer);
    RAISE NOTICE 'C2. reason stored           expect        t  got %',
        (SELECT reversalreason = 'Wrong account picked' FROM poultrycashtransfers
          WHERE poultrycashtransferid = v_xfer);
    RAISE NOTICE 'C3. source restored         expect 10000.00  got %',
        (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_from);
    RAISE NOTICE 'C4. destination restored    expect     0.00  got %',
        (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_to);
    -- Append-only: the original two rows are still there, with two more beside
    -- them. What happened, happened.
    RAISE NOTICE 'C5. four ledger rows now    expect        4  got %',
        (SELECT COUNT(*) FROM poultrycashtransactions
          WHERE farmid = v_farm AND sourcetype = 'Transfer' AND sourceid = v_xfer);
    RAISE NOTICE 'C6. originals untouched     expect        2  got %',
        (SELECT COUNT(*) FROM poultrycashtransactions
          WHERE farmid = v_farm AND sourceid = v_xfer
            AND transactiontype IN ('TransferOut', 'TransferIn'));
    RAISE NOTICE 'C7. two reversal rows       expect        2  got %',
        (SELECT COUNT(*) FROM poultrycashtransactions
          WHERE farmid = v_farm AND sourceid = v_xfer
            AND transactiontype IN ('TransferReversalOut', 'TransferReversalIn'));
    -- The reversal legs are internal too. If they were written as ordinary
    -- CashIn/CashOut, undoing a transfer would invent money the business never
    -- received and never spent.
    RAISE NOTICE 'C8. reversal legs internal  expect        4  got %',
        (SELECT COUNT(*) FROM poultrycashtransactions
          WHERE farmid = v_farm AND sourceid = v_xfer AND sourcetype = 'Transfer');
    RAISE NOTICE 'C9. the four legs net zero  expect     0.00  got %',
        (SELECT COALESCE(SUM(amount), 0) FROM poultrycashtransactions
          WHERE farmid = v_farm AND sourcetype = 'Transfer' AND sourceid = v_xfer);

    SELECT s.moneyin, s.moneyout, s.netcashflow INTO v_in2, v_out2, v_net2
    FROM   sppoultrycashflow_summary(v_farm, NULL, NULL) s;
    RAISE NOTICE 'C10. money in still unmoved expect        t  got %', (v_in2 = v_in0);
    RAISE NOTICE 'C11. money out still unmovedexpect        t  got %', (v_out2 = v_out0);
    RAISE NOTICE 'C12. net still unmoved      expect        t  got %', (v_net2 = v_net0);

    -- =====================================================================
    -- D. The guard flips to the destination.
    -- =====================================================================
    -- Move 1,000 across, then spend it from the destination. The money is no
    -- longer there to give back, and the account may not go negative.
    v_xfer2 := sppoultrycashtransfer_insert(
        p_farmid => v_farm, p_frompoultrycashaccountid => v_from,
        p_topoultrycashaccountid => v_to, p_amount => 1000,
        p_transferdate => (now() at time zone 'utc'), p_createdby => 'ZZ tester');
    PERFORM sppoultrycashtransfer_approve(v_xfer2, v_farm, 'ZZ tester');

    UPDATE poultrycashaccounts SET currentbalance = 200 WHERE poultrycashaccountid = v_to;

    BEGIN
        PERFORM sppoultrycashtransfer_reverse(v_xfer2, v_farm, 'Should be blocked', 'ZZ tester');
        RAISE NOTICE 'D1. overdrawing reversal    <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'D1. overdrawing reversal    blocked: %', SQLERRM;
    END;
    -- And nothing moved on the way past.
    RAISE NOTICE 'D2. destination untouched   expect   200.00  got %',
        (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_to);
    RAISE NOTICE 'D3. transfer still approved expect Approved  got %',
        (SELECT status FROM poultrycashtransfers WHERE poultrycashtransferid = v_xfer2);
END
$t$;

-- =============================================================================
-- Negative cases. Each must be BLOCKED.
-- =============================================================================
DO $n$
DECLARE
    v_farm  text := '7b95dafa-758f-4461-891d-f612131978fd';
    v_other text := 'b55bf33e-a5ba-4d9b-a287-1dea39a84f13';
    v_from integer; v_to integer; v_otheracct integer; v_draft integer; v_done integer;
BEGIN
    SELECT poultrycashaccountid INTO v_from FROM poultrycashaccounts
     WHERE farmid = v_farm AND accountname = 'ZZ Transfer Source';
    SELECT poultrycashaccountid INTO v_to FROM poultrycashaccounts
     WHERE farmid = v_farm AND accountname = 'ZZ Transfer Destination';
    SELECT poultrycashaccountid INTO v_otheracct FROM poultrycashaccounts
     WHERE farmid = v_other ORDER BY 1 LIMIT 1;

    -- Another company's account. Before 252 this went straight through, and the
    -- money landed in a farm the caller had no claim to.
    BEGIN
        PERFORM sppoultrycashtransfer_insert(
            p_farmid => v_farm, p_frompoultrycashaccountid => v_from,
            p_topoultrycashaccountid => v_otheracct, p_amount => 100,
            p_createdby => 'ZZ tester');
        RAISE NOTICE 'N1. another farm''s account  <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N1. another farm''s account  blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM sppoultrycashtransfer_insert(
            p_farmid => v_farm, p_frompoultrycashaccountid => v_from,
            p_topoultrycashaccountid => v_from, p_amount => 100, p_createdby => 'ZZ tester');
        RAISE NOTICE 'N2. same account both ends  <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N2. same account both ends  blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM sppoultrycashtransfer_insert(
            p_farmid => v_farm, p_frompoultrycashaccountid => v_from,
            p_topoultrycashaccountid => v_to, p_amount => 0, p_createdby => 'ZZ tester');
        RAISE NOTICE 'N3. zero amount             <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N3. zero amount             blocked: %', SQLERRM;
    END;

    -- A draft moved no money, so there is nothing to put back. Cancel is the
    -- verb for a draft; reverse is the verb for a posting.
    v_draft := sppoultrycashtransfer_insert(
        p_farmid => v_farm, p_frompoultrycashaccountid => v_from,
        p_topoultrycashaccountid => v_to, p_amount => 50, p_createdby => 'ZZ tester');
    BEGIN
        PERFORM sppoultrycashtransfer_reverse(v_draft, v_farm, 'Nothing to undo', 'ZZ tester');
        RAISE NOTICE 'N4. reversing a draft       <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N4. reversing a draft       blocked: %', SQLERRM;
    END;

    -- Reversing twice would double the correction and hand the source account
    -- money the business never had.
    v_done := sppoultrycashtransfer_insert(
        p_farmid => v_farm, p_frompoultrycashaccountid => v_from,
        p_topoultrycashaccountid => v_to, p_amount => 75, p_createdby => 'ZZ tester');
    PERFORM sppoultrycashtransfer_approve(v_done, v_farm, 'ZZ tester');
    PERFORM sppoultrycashtransfer_reverse(v_done, v_farm, 'First reversal', 'ZZ tester');
    BEGIN
        PERFORM sppoultrycashtransfer_reverse(v_done, v_farm, 'Second reversal', 'ZZ tester');
        RAISE NOTICE 'N5. reversing twice         <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N5. reversing twice         blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM sppoultrycashtransfer_reverse(v_done, v_farm, '   ', 'ZZ tester');
        RAISE NOTICE 'N6. reversal with no reason <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N6. reversal with no reason blocked: %', SQLERRM;
    END;
END
$n$;

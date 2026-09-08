-- Behavioural checks for migration 258: water owner money.
--
-- The water twin of poultry-owner-money.test.sql, claim for claim.
-- One DO $t$ block, a NOTICE per check reading "expect X got Y", then negative
-- cases that must each be blocked. Run inside a transaction you ROLL BACK; it
-- creates a cash account and records contributions and draws.
--
--   psql ... -X -c "BEGIN;" -f water-owner-money.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 258
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- The farm is looked up rather than hard-coded, and the lookup insists on
-- farms.type = 'Water': watercashaccounts also holds rows for a Generic company
-- built on the water rail, and the oldest account in the table is one of those.
--
-- The claims this file tests:
--   1. **A contribution is not revenue and a draw is not an expense.** Neither
--      writes a sale, an expense, a customer payment or a supplier payment.
--   2. **Exactly ONE cash row per record.** The classic failure is a module and
--      a shadow expense both posting cash for the same event.
--   3. Cash Flow SEES it -- money in for a contribution, money out for a draw --
--      because 258 gave the reader an arm. This is the gap 236 wrote down and
--      left: water cash flow ignores the cash ledger, so without that arm the
--      money would move and the page would never mention it.
--   4. A reversal restores the account AND removes the record from cash flow
--      entirely, rather than showing both legs.
--   5. The overdraw guard applies to a draw, and flips to the reversal of a
--      contribution.

DO $t$
DECLARE
    v_farm text;
    v_acct integer;

    v_in0 numeric; v_out0 numeric; v_net0 numeric;
    v_in1 numeric; v_out1 numeric;
    v_in2 numeric; v_out2 numeric;
    v_in3 numeric; v_out3 numeric;

    v_sales0 integer; v_exp0 integer; v_pay0 integer; v_sup0 integer;
    v_contrib integer; v_draw integer;
    v_num text;
BEGIN
    SELECT a.farmid INTO v_farm
    FROM   watercashaccounts a
    JOIN   farms f ON f.farmid = a.farmid AND f.type = 'Water'
    GROUP  BY a.farmid
    ORDER  BY MIN(a.watercashaccountid)
    LIMIT  1;

    IF v_farm IS NULL THEN
        RAISE EXCEPTION 'No water company with cash accounts; cannot run these checks.';
    END IF;
    RAISE NOTICE '   using water farm %', v_farm;

    -- =====================================================================
    -- Setup.
    -- =====================================================================
    INSERT INTO watercashaccounts (farmid, accountname, accounttype, openingbalance,
                                   currentbalance, allownegativebalance, isactive)
    VALUES (v_farm, 'ZZ Owner Money Bank', 'BankAccount', 1000, 1000, FALSE, TRUE)
    RETURNING watercashaccountid INTO v_acct;

    SELECT s.moneyin, s.moneyout, s.netcashflow INTO v_in0, v_out0, v_net0
    FROM   spwatercashflow_summary(v_farm, NULL, NULL) s;

    -- What the rest of the business looks like before the owner touches it.
    SELECT COUNT(*) INTO v_sales0 FROM watersales            WHERE farmid = v_farm;
    SELECT COUNT(*) INTO v_exp0   FROM waterexpenses         WHERE farmid = v_farm;
    SELECT COUNT(*) INTO v_pay0   FROM waterpayments         WHERE farmid = v_farm;
    SELECT COUNT(*) INTO v_sup0   FROM watersupplierpayments WHERE farmid = v_farm;

    -- =====================================================================
    -- A. A contribution.
    -- =====================================================================
    v_contrib := spwaterownermoney_record(
        p_farmid             => v_farm,
        p_transactiontype    => 'Contribution',
        p_amount             => 20000,
        p_watercashaccountid => v_acct,
        p_transactiondate    => (now() at time zone 'utc'),
        p_paymentmethod      => 'BankTransfer',
        p_ownername          => 'ZZ Owner',
        p_referencenumber    => 'CAP-001',
        p_notes              => 'ZZ capital injection',
        p_createdby          => 'ZZ tester');

    SELECT transactionnumber INTO v_num FROM waterownermoney WHERE waterownermoneyid = v_contrib;

    RAISE NOTICE 'A1. cash account is up      expect 21000.00  got %',
        (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct);
    -- ONE row. Not two, not one plus a shadow expense.
    RAISE NOTICE 'A2. exactly one cash row    expect        1  got %',
        (SELECT COUNT(*) FROM watercashtransactions
          WHERE farmid = v_farm AND sourcetype = 'OwnerMoney' AND sourceid = v_contrib);
    RAISE NOTICE 'A3. and it is money IN      expect 20000.00  got %',
        (SELECT amount FROM watercashtransactions
          WHERE farmid = v_farm AND sourcetype = 'OwnerMoney' AND sourceid = v_contrib);
    RAISE NOTICE 'A4. numbered OWN-           expect        t  got %', (v_num LIKE 'OWN-%');
    RAISE NOTICE 'A5. amount stored positive  expect 20000.00  got %',
        (SELECT amount FROM waterownermoney WHERE waterownermoneyid = v_contrib);
    RAISE NOTICE 'A6. the cash row is linked  expect        t  got %',
        (SELECT watercashtransactionid IS NOT NULL FROM waterownermoney
          WHERE waterownermoneyid = v_contrib);

    -- THE claim: funding, not trading.
    RAISE NOTICE 'A7. no sale was created     expect        t  got %',
        ((SELECT COUNT(*) FROM watersales WHERE farmid = v_farm) = v_sales0);
    RAISE NOTICE 'A8. no expense was created  expect        t  got %',
        ((SELECT COUNT(*) FROM waterexpenses WHERE farmid = v_farm) = v_exp0);
    RAISE NOTICE 'A9. no payment was created  expect        t  got %',
        ((SELECT COUNT(*) FROM waterpayments WHERE farmid = v_farm) = v_pay0);
    RAISE NOTICE 'A9b. no supplier payment    expect        t  got %',
        ((SELECT COUNT(*) FROM watersupplierpayments WHERE farmid = v_farm) = v_sup0);

    -- And Cash Flow can see it, which it could not before 258 gave it an arm.
    SELECT s.moneyin, s.moneyout INTO v_in1, v_out1
    FROM   spwatercashflow_summary(v_farm, NULL, NULL) s;
    RAISE NOTICE 'A10. money in rose by it    expect 20000.00  got %', (v_in1 - v_in0);
    RAISE NOTICE 'A11. money out unmoved      expect        t  got %', (v_out1 = v_out0);
    RAISE NOTICE 'A12. filed as financing     expect FinancingIn  got %',
        (SELECT r.flowgroup FROM spwatercashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'OwnerMoney' AND r.sourcerowid = v_contrib);

    -- =====================================================================
    -- B. A draw.
    -- =====================================================================
    v_draw := spwaterownermoney_record(
        p_farmid             => v_farm,
        p_transactiontype    => 'Draw',
        p_amount             => 5000,
        p_watercashaccountid => v_acct,
        p_transactiondate    => (now() at time zone 'utc'),
        p_paymentmethod      => 'Cash',
        p_ownername          => 'ZZ Owner',
        p_createdby          => 'ZZ tester');

    RAISE NOTICE 'B1. cash account is down    expect 16000.00  got %',
        (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct);
    RAISE NOTICE 'B2. one cash row, negative  expect -5000.00  got %',
        (SELECT amount FROM watercashtransactions
          WHERE farmid = v_farm AND sourcetype = 'OwnerMoney' AND sourceid = v_draw);
    RAISE NOTICE 'B3. numbered OWD-           expect        t  got %',
        (SELECT transactionnumber LIKE 'OWD-%' FROM waterownermoney WHERE waterownermoneyid = v_draw);
    -- A draw is money leaving, but it is NOT an operating expense.
    RAISE NOTICE 'B4. still no expense        expect        t  got %',
        ((SELECT COUNT(*) FROM waterexpenses WHERE farmid = v_farm) = v_exp0);

    SELECT s.moneyin, s.moneyout INTO v_in2, v_out2
    FROM   spwatercashflow_summary(v_farm, NULL, NULL) s;
    RAISE NOTICE 'B5. money out rose by it    expect  5000.00  got %', (v_out2 - v_out1);
    RAISE NOTICE 'B6. money in unmoved        expect        t  got %', (v_in2 = v_in1);
    RAISE NOTICE 'B7. filed as financing out  expect FinancingOut  got %',
        (SELECT r.flowgroup FROM spwatercashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'OwnerMoney' AND r.sourcerowid = v_draw);

    -- The five cards on the page.
    RAISE NOTICE 'B8. total contributions     expect 20000.00  got %',
        (SELECT totalcontributions FROM spwaterownermoney_summary(v_farm));
    RAISE NOTICE 'B9. total draws             expect  5000.00  got %',
        (SELECT totaldraws FROM spwaterownermoney_summary(v_farm));
    RAISE NOTICE 'B10. net owner funding      expect 15000.00  got %',
        (SELECT netfunding FROM spwaterownermoney_summary(v_farm));

    -- =====================================================================
    -- C. Reversing the draw.
    -- =====================================================================
    PERFORM spwaterownermoney_reverse(v_draw, v_farm, 'Recorded against the wrong account', 'ZZ tester');

    RAISE NOTICE 'C1. marked reversed         expect Reversed  got %',
        (SELECT status FROM waterownermoney WHERE waterownermoneyid = v_draw);
    RAISE NOTICE 'C2. cash put back           expect 21000.00  got %',
        (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct);
    -- Append-only: the original row stays and a second row sits beside it.
    RAISE NOTICE 'C3. two rows for the draw   expect        2  got %',
        (SELECT COUNT(*) FROM watercashtransactions
          WHERE farmid = v_farm AND sourcetype = 'OwnerMoney' AND sourceid = v_draw);
    RAISE NOTICE 'C4. and they net to zero    expect     0.00  got %',
        (SELECT COALESCE(SUM(amount), 0) FROM watercashtransactions
          WHERE farmid = v_farm AND sourcetype = 'OwnerMoney' AND sourceid = v_draw);

    -- A draw that was made and unmade is not money that left. Cash Flow drops
    -- the record entirely rather than showing both legs.
    SELECT s.moneyin, s.moneyout INTO v_in3, v_out3
    FROM   spwatercashflow_summary(v_farm, NULL, NULL) s;
    RAISE NOTICE 'C5. money out is back       expect        t  got %', (v_out3 = v_out1);
    RAISE NOTICE 'C6. money in still the same expect        t  got %', (v_in3 = v_in1);
    RAISE NOTICE 'C7. gone from the rows      expect        0  got %',
        (SELECT COUNT(*) FROM spwatercashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'OwnerMoney' AND r.sourcerowid = v_draw);
    RAISE NOTICE 'C8. and out of the totals   expect     0.00  got %',
        (SELECT totaldraws FROM spwaterownermoney_summary(v_farm));
    RAISE NOTICE 'C9. net funding is the rest expect 20000.00  got %',
        (SELECT netfunding FROM spwaterownermoney_summary(v_farm));
END
$t$;

-- =============================================================================
-- Negative cases. Each must be BLOCKED.
-- =============================================================================
DO $n$
DECLARE
    v_farm  text;
    v_other text;
    v_acct integer; v_otheracct integer; v_small integer; v_id integer;
BEGIN
    SELECT farmid, watercashaccountid INTO v_farm, v_acct
    FROM   watercashaccounts WHERE accountname = 'ZZ Owner Money Bank' LIMIT 1;

    SELECT a.farmid INTO v_other
    FROM   watercashaccounts a
    JOIN   farms f ON f.farmid = a.farmid AND f.type = 'Water'
    WHERE  a.farmid <> v_farm
    GROUP  BY a.farmid
    ORDER  BY MIN(a.watercashaccountid)
    LIMIT  1;
    SELECT watercashaccountid INTO v_otheracct
    FROM   watercashaccounts WHERE farmid = v_other ORDER BY 1 LIMIT 1;

    BEGIN
        PERFORM spwaterownermoney_record(
            p_farmid => v_farm, p_transactiontype => 'Donation', p_amount => 100,
            p_watercashaccountid => v_acct);
        RAISE NOTICE 'N1. an invented type       <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N1. an invented type       blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spwaterownermoney_record(
            p_farmid => v_farm, p_transactiontype => 'Contribution', p_amount => 0,
            p_watercashaccountid => v_acct);
        RAISE NOTICE 'N2. a zero amount          <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N2. a zero amount          blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spwaterownermoney_record(
            p_farmid => v_farm, p_transactiontype => 'Contribution', p_amount => -100,
            p_watercashaccountid => v_acct);
        RAISE NOTICE 'N3. a negative amount      <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N3. a negative amount      blocked: %', SQLERRM;
    END;

    -- Another company's cash account.
    BEGIN
        PERFORM spwaterownermoney_record(
            p_farmid => v_farm, p_transactiontype => 'Contribution', p_amount => 100,
            p_watercashaccountid => v_otheracct);
        RAISE NOTICE 'N4. another farm''s account <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N4. another farm''s account blocked: %', SQLERRM;
    END;

    -- A draw bigger than the account holds, on an account that may not go
    -- negative.
    INSERT INTO watercashaccounts (farmid, accountname, accounttype, openingbalance,
                                   currentbalance, allownegativebalance, isactive)
    VALUES (v_farm, 'ZZ Owner Money Small', 'PettyCash', 100, 100, FALSE, TRUE)
    RETURNING watercashaccountid INTO v_small;

    BEGIN
        PERFORM spwaterownermoney_record(
            p_farmid => v_farm, p_transactiontype => 'Draw', p_amount => 500,
            p_watercashaccountid => v_small);
        RAISE NOTICE 'N5. drawing more than held <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N5. drawing more than held blocked: %', SQLERRM;
    END;

    -- Reversing a contribution the account has since spent: the money is not
    -- there to give back.
    v_id := spwaterownermoney_record(
        p_farmid => v_farm, p_transactiontype => 'Contribution', p_amount => 400,
        p_watercashaccountid => v_small, p_createdby => 'ZZ tester');
    UPDATE watercashaccounts SET currentbalance = 50 WHERE watercashaccountid = v_small;
    BEGIN
        PERFORM spwaterownermoney_reverse(v_id, v_farm, 'Should be blocked', 'ZZ tester');
        RAISE NOTICE 'N6. reversing spent money  <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N6. reversing spent money  blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spwaterownermoney_reverse(v_id, v_farm, '  ', 'ZZ tester');
        RAISE NOTICE 'N7. reversal with no reason <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N7. reversal with no reason blocked: %', SQLERRM;
    END;

    -- Reversing twice.
    UPDATE watercashaccounts SET currentbalance = 1000 WHERE watercashaccountid = v_small;
    PERFORM spwaterownermoney_reverse(v_id, v_farm, 'First reversal', 'ZZ tester');
    BEGIN
        PERFORM spwaterownermoney_reverse(v_id, v_farm, 'Second reversal', 'ZZ tester');
        RAISE NOTICE 'N8. reversing twice        <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N8. reversing twice        blocked: %', SQLERRM;
    END;
END
$n$;

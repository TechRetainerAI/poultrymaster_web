-- Behavioural checks for migration 254: poultry loans and repayments.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y", then negative
-- cases that must each be blocked. Run inside a transaction you ROLL BACK; it
-- creates a cash account, a loan and repayments.
--
--   psql ... -X -c "BEGIN;" -f poultry-loans.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 254
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- The scenario is the spec's own worked example:
--
--   Loan principal              100,000
--   Fee withheld by the lender    2,000
--   Cash actually received       98,000
--   Repayment  principal 10,000 + interest 2,000 + fee 500 = 12,500
--
-- The claims this file tests, in order of how badly they would hurt:
--
--   1. **Cash moves ONCE, for the total.** 12,500 leaves the account, not
--      12,500 + 2,000 + 500. Counted as rows AND as a balance.
--   2. **Principal repayment is not an expense.** Expenses rise by 2,500, not
--      by 12,500 -- the P&L must not think repaying a debt made the farm poorer.
--   3. **Cash flow shows the FULL 12,500 out**, because that is what left the
--      bank, while the P&L shows 2,500 of cost. Both, at once, from one event.
--   4. **No supplier payment, no supplier balance.** A lender is not a supplier.
--   5. Loan received is money in and never revenue.
--   6. Reversal puts all of it back and leaves every original row standing.

DO $t$
DECLARE
    v_farm text := '7b95dafa-758f-4461-891d-f612131978fd';   -- Dev Test Farm (Poultry)
    v_acct integer;
    v_loan integer;
    v_pay  integer;
    v_pay2 integer;

    v_in0 numeric; v_out0 numeric;
    v_in1 numeric; v_out1 numeric;
    v_in2 numeric; v_out2 numeric;
    v_in3 numeric; v_out3 numeric;

    v_exp0   numeric; v_exp1 numeric; v_exp2 numeric;
    v_sales0 integer; v_supalloc0 integer; v_suppay0 integer;
    v_cashrows integer;
BEGIN
    -- =====================================================================
    -- Setup.
    -- =====================================================================
    INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance,
                                     currentbalance, allownegativebalance, isactive)
    VALUES (v_farm, 'ZZ Loan Bank', 'BankAccount', 0, 0, FALSE, TRUE)
    RETURNING poultrycashaccountid INTO v_acct;

    SELECT s.moneyin, s.moneyout INTO v_in0, v_out0
    FROM   sppoultrycashflow_summary(v_farm, NULL, NULL) s;

    -- The P&L's own expense total, which is what must move by 2,500 and not by
    -- 12,500. Read from the report, not re-derived here.
    SELECT COALESCE(totalexpenses, 0) INTO v_exp0
    FROM   sppoultryreport_profitloss(v_farm, '2000-01-01'::date, '2099-12-31'::date);

    SELECT COUNT(*) INTO v_sales0 FROM sale WHERE farmid = v_farm;
    SELECT COUNT(*) INTO v_supalloc0 FROM supplierpaymentallocation
     WHERE farmid = v_farm AND module = 'poultry';
    -- The poultry supplier payments live in their own table; only the
    -- allocation table is shared and module-scoped.
    SELECT COUNT(*) INTO v_suppay0 FROM poultrysupplierpayments WHERE farmid = v_farm;

    -- =====================================================================
    -- A. Taking the loan. 100,000 borrowed, 98,000 received.
    -- =====================================================================
    v_loan := sppoultryloan_create(
        p_farmid               => v_farm,
        p_lendername           => 'ZZ Rural Bank',
        p_originalprincipal    => 100000,
        p_startdate            => CURRENT_DATE - 30,
        p_amountreceived       => 98000,
        p_poultrycashaccountid => v_acct,
        p_lendertype           => 'Bank',
        p_interestrate         => 24,
        p_interesttype         => 'ReducingBalance',
        p_termmonths           => 12,
        p_paymentfrequency     => 'Monthly',
        p_nextpaymentdate      => CURRENT_DATE + 5,
        p_notes                => 'ZZ test loan',
        p_createdby            => 'ZZ tester');

    RAISE NOTICE 'A1. cash in is what ARRIVED expect 98000.00  got %',
        (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct);
    -- The debt is what was BORROWED, not what arrived.
    RAISE NOTICE 'A2. the debt is the PRINCIPAL expect 100000.00  got %',
        (SELECT outstandingprincipal FROM poultryloans WHERE poultryloanid = v_loan);
    RAISE NOTICE 'A3. one disbursement row    expect        1  got %',
        (SELECT COUNT(*) FROM poultrycashtransactions
          WHERE farmid = v_farm AND sourcetype = 'Loan' AND sourceid = v_loan);
    RAISE NOTICE 'A4. numbered LN-            expect        t  got %',
        (SELECT loannumber LIKE 'LN-%' FROM poultryloans WHERE poultryloanid = v_loan);
    RAISE NOTICE 'A5. status is Active        expect   Active  got %',
        (SELECT status FROM poultryloans WHERE poultryloanid = v_loan);

    -- Borrowing is not earning.
    RAISE NOTICE 'A6. no sale was created     expect        t  got %',
        ((SELECT COUNT(*) FROM sale WHERE farmid = v_farm) = v_sales0);
    SELECT s.moneyin, s.moneyout INTO v_in1, v_out1
    FROM   sppoultrycashflow_summary(v_farm, NULL, NULL) s;
    RAISE NOTICE 'A7. money in rose by 98000  expect 98000.00  got %', (v_in1 - v_in0);
    RAISE NOTICE 'A8. filed as financing in   expect FinancingIn  got %',
        (SELECT r.flowgroup FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'Loan' AND r.sourcerowid = v_loan);
    -- The 2,000 the lender kept is NOT silently expensed.
    SELECT COALESCE(totalexpenses, 0) INTO v_exp1
    FROM   sppoultryreport_profitloss(v_farm, '2000-01-01'::date, '2099-12-31'::date);
    RAISE NOTICE 'A9. withheld fee not guessed expect       t  got %', (v_exp1 = v_exp0);

    -- =====================================================================
    -- B. The repayment: 10,000 + 2,000 + 500 = 12,500.
    -- =====================================================================
    SELECT COUNT(*) INTO v_cashrows FROM poultrycashtransactions WHERE farmid = v_farm;

    v_pay := sppoultryloanpayment_record(
        p_farmid               => v_farm,
        p_poultryloanid        => v_loan,
        p_poultrycashaccountid => v_acct,
        p_principalamount      => 10000,
        p_interestamount       => 2000,
        p_feeamount            => 500,
        p_paymentdate          => (now() at time zone 'utc'),
        p_paymentmethod        => 'BankTransfer',
        p_nextpaymentdate      => CURRENT_DATE + 35,
        p_createdby            => 'ZZ tester');

    RAISE NOTICE 'B1. total is the sum        expect 12500.00  got %',
        (SELECT totalamount FROM poultryloanpayments WHERE poultryloanpaymentid = v_pay);

    -- **THE** check. One row, for the total.
    RAISE NOTICE 'B2. ONE cash row for it     expect        1  got %',
        (SELECT COUNT(*) FROM poultrycashtransactions
          WHERE farmid = v_farm AND sourcetype = 'LoanPayment' AND sourceid = v_pay);
    RAISE NOTICE 'B3. and it is the TOTAL     expect -12500.00  got %',
        (SELECT amount FROM poultrycashtransactions
          WHERE farmid = v_farm AND sourcetype = 'LoanPayment' AND sourceid = v_pay);
    -- Only one new cash row exists at all: the expense rows added none.
    RAISE NOTICE 'B4. exactly one row added   expect        1  got %',
        ((SELECT COUNT(*) FROM poultrycashtransactions WHERE farmid = v_farm) - v_cashrows);
    RAISE NOTICE 'B5. account down by 12500   expect 85500.00  got %',
        (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct);

    -- The debt.
    RAISE NOTICE 'B6. principal 10000 lower   expect 90000.00  got %',
        (SELECT outstandingprincipal FROM poultryloans WHERE poultryloanid = v_loan);
    RAISE NOTICE 'B7. repaid total tracked    expect 10000.00  got %',
        (SELECT totalprincipalrepaid FROM poultryloans WHERE poultryloanid = v_loan);
    RAISE NOTICE 'B8. interest paid tracked   expect  2000.00  got %',
        (SELECT totalinterestpaid FROM poultryloans WHERE poultryloanid = v_loan);
    RAISE NOTICE 'B9. fees paid tracked       expect   500.00  got %',
        (SELECT totalfeespaid FROM poultryloans WHERE poultryloanid = v_loan);

    -- **THE OTHER** check. Cost is 2,500 -- not 12,500.
    SELECT COALESCE(totalexpenses, 0) INTO v_exp2
    FROM   sppoultryreport_profitloss(v_farm, '2000-01-01'::date, '2099-12-31'::date);
    RAISE NOTICE 'B10. P&L cost is 2500       expect  2500.00  got %', (v_exp2 - v_exp1);
    RAISE NOTICE 'B11. two expense rows       expect        2  got %',
        (SELECT COUNT(*) FROM expense
          WHERE farmid::text = v_farm AND sourcetype = 'LoanPayment' AND sourceid = v_pay);
    RAISE NOTICE 'B12. both are NonCash       expect        2  got %',
        (SELECT COUNT(*) FROM expense
          WHERE farmid::text = v_farm AND sourcetype = 'LoanPayment' AND sourceid = v_pay
            AND paymentmethod = 'NonCash');

    -- Cash flow: the FULL amount out, once.
    SELECT s.moneyin, s.moneyout INTO v_in2, v_out2
    FROM   sppoultrycashflow_summary(v_farm, NULL, NULL) s;
    RAISE NOTICE 'B13. money out is 12500     expect 12500.00  got %', (v_out2 - v_out1);
    RAISE NOTICE 'B14. one cash-flow row      expect        1  got %',
        (SELECT COUNT(*) FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'LoanPayment' AND r.sourcerowid = v_pay);
    -- The NonCash expenses must not appear in the expense arm as well.
    RAISE NOTICE 'B15. expenses not doubled   expect        0  got %',
        (SELECT COUNT(*) FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'Expense'
            AND r.sourcerowid IN (SELECT expenseid FROM expense
                                   WHERE farmid::text = v_farm AND sourcetype = 'LoanPayment'));

    -- A lender is not a supplier.
    RAISE NOTICE 'B16. no supplier payment    expect        t  got %',
        ((SELECT COUNT(*) FROM poultrysupplierpayments WHERE farmid = v_farm) = v_suppay0);
    RAISE NOTICE 'B17. no allocation either   expect        t  got %',
        ((SELECT COUNT(*) FROM supplierpaymentallocation
           WHERE farmid = v_farm AND module = 'poultry') = v_supalloc0);
    -- And the interest never becomes something owed to a creditor.
    RAISE NOTICE 'B18. not on payables        expect        0  got %',
        (SELECT COUNT(*) FROM fnpoultrypayables(v_farm) d
          WHERE d.documenttype = 'Expense'
            AND d.documentid IN (SELECT expenseid FROM expense
                                  WHERE farmid::text = v_farm AND sourcetype = 'LoanPayment'));

    -- =====================================================================
    -- C. Paying the rest off.
    -- =====================================================================
    -- Staging, not a claim: the account holds 85,500 after the first repayment,
    -- and the farm has to have earned the rest from somewhere before it can pay
    -- off 90,000. The guard that refuses an overdrawing repayment is exercised
    -- deliberately in N-cases below.
    UPDATE poultrycashaccounts SET currentbalance = currentbalance + 100000
    WHERE  poultrycashaccountid = v_acct;

    v_pay2 := sppoultryloanpayment_record(
        p_farmid               => v_farm,
        p_poultryloanid        => v_loan,
        p_poultrycashaccountid => v_acct,
        p_principalamount      => 90000,
        p_paymentdate          => (now() at time zone 'utc'),
        p_createdby            => 'ZZ tester');

    RAISE NOTICE 'C1. nothing left owing      expect     0.00  got %',
        (SELECT outstandingprincipal FROM poultryloans WHERE poultryloanid = v_loan);
    -- Decided by what is OUTSTANDING, not by comparing paid against principal:
    -- 100,000 of principal plus 2,500 of cost was paid, which is not 100,000.
    RAISE NOTICE 'C2. status is PaidOff       expect  PaidOff  got %',
        (SELECT status FROM poultryloans WHERE poultryloanid = v_loan);
    RAISE NOTICE 'C3. paid-off date stamped   expect        t  got %',
        (SELECT paidoffdate IS NOT NULL FROM poultryloans WHERE poultryloanid = v_loan);
    -- A principal-only payment creates no expense at all.
    RAISE NOTICE 'C4. no expense for it       expect        0  got %',
        (SELECT COUNT(*) FROM expense
          WHERE farmid::text = v_farm AND sourcetype = 'LoanPayment' AND sourceid = v_pay2);

    -- =====================================================================
    -- D. Reversing the first repayment.
    -- =====================================================================
    PERFORM sppoultryloanpayment_reverse(v_pay, v_farm, 'Recorded twice by mistake', 'ZZ tester');

    RAISE NOTICE 'D1. marked reversed         expect Reversed  got %',
        (SELECT status FROM poultryloanpayments WHERE poultryloanpaymentid = v_pay);
    RAISE NOTICE 'D2. debt is back up         expect 10000.00  got %',
        (SELECT outstandingprincipal FROM poultryloans WHERE poultryloanid = v_loan);
    -- A loan that was paid off is live again.
    RAISE NOTICE 'D3. loan is Active again    expect   Active  got %',
        (SELECT status FROM poultryloans WHERE poultryloanid = v_loan);
    RAISE NOTICE 'D4. paid-off date cleared   expect        t  got %',
        (SELECT paidoffdate IS NULL FROM poultryloans WHERE poultryloanid = v_loan);
    RAISE NOTICE 'D5. interest total undone   expect     0.00  got %',
        (SELECT totalinterestpaid FROM poultryloans WHERE poultryloanid = v_loan);

    -- Append-only: original rows stay, opposite rows appear.
    RAISE NOTICE 'D6. two cash rows for it    expect        2  got %',
        (SELECT COUNT(*) FROM poultrycashtransactions
          WHERE farmid = v_farm AND sourcetype = 'LoanPayment' AND sourceid = v_pay);
    RAISE NOTICE 'D7. and they net to zero    expect     0.00  got %',
        (SELECT COALESCE(SUM(amount), 0) FROM poultrycashtransactions
          WHERE farmid = v_farm AND sourcetype = 'LoanPayment' AND sourceid = v_pay);
    -- The cost is cancelled by compensating rows, not by deletion.
    RAISE NOTICE 'D8. original expenses kept  expect        2  got %',
        (SELECT COUNT(*) FROM expense
          WHERE farmid::text = v_farm AND sourcetype = 'LoanPayment' AND sourceid = v_pay);
    RAISE NOTICE 'D9. two cancelling rows     expect        2  got %',
        (SELECT COUNT(*) FROM expense
          WHERE farmid::text = v_farm AND sourcetype = 'LoanPaymentReversal' AND sourceid = v_pay);
    RAISE NOTICE 'D10. cost back where it was expect        t  got %',
        ((SELECT COALESCE(totalexpenses, 0)
            FROM sppoultryreport_profitloss(v_farm, '2000-01-01'::date, '2099-12-31'::date)) = v_exp1);

    -- Cash flow drops the reversed payment entirely.
    SELECT s.moneyin, s.moneyout INTO v_in3, v_out3
    FROM   sppoultrycashflow_summary(v_farm, NULL, NULL) s;
    RAISE NOTICE 'D11. its 12500 is gone      expect        0  got %',
        (SELECT COUNT(*) FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'LoanPayment' AND r.sourcerowid = v_pay);
    -- Only the 90,000 payoff remains as money out from this loan.
    RAISE NOTICE 'D12. money out is the rest  expect 90000.00  got %', (v_out3 - v_out1);
END
$t$;

-- =============================================================================
-- Negative cases. Each must be BLOCKED.
-- =============================================================================
DO $n$
DECLARE
    v_farm  text := '7b95dafa-758f-4461-891d-f612131978fd';
    v_other text := 'b55bf33e-a5ba-4d9b-a287-1dea39a84f13';
    v_acct integer; v_otheracct integer; v_loan integer; v_pay integer; v_draft integer;
BEGIN
    SELECT poultrycashaccountid INTO v_acct FROM poultrycashaccounts
     WHERE farmid = v_farm AND accountname = 'ZZ Loan Bank';
    SELECT poultrycashaccountid INTO v_otheracct FROM poultrycashaccounts
     WHERE farmid = v_other ORDER BY 1 LIMIT 1;
    SELECT poultryloanid INTO v_loan FROM poultryloans
     WHERE farmid = v_farm AND lendername = 'ZZ Rural Bank';

    -- Receiving more than was borrowed is a slip, not a loan.
    BEGIN
        PERFORM sppoultryloan_create(
            p_farmid => v_farm, p_lendername => 'ZZ Bad', p_originalprincipal => 1000,
            p_startdate => CURRENT_DATE, p_amountreceived => 5000,
            p_poultrycashaccountid => v_acct);
        RAISE NOTICE 'N1. received > principal   <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N1. received > principal   blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM sppoultryloan_create(
            p_farmid => v_farm, p_lendername => '  ', p_originalprincipal => 1000,
            p_startdate => CURRENT_DATE);
        RAISE NOTICE 'N2. a loan with no lender  <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N2. a loan with no lender  blocked: %', SQLERRM;
    END;

    -- Money must land somewhere real.
    BEGIN
        PERFORM sppoultryloan_create(
            p_farmid => v_farm, p_lendername => 'ZZ Bad', p_originalprincipal => 1000,
            p_startdate => CURRENT_DATE, p_amountreceived => 1000,
            p_poultrycashaccountid => v_otheracct);
        RAISE NOTICE 'N3. another farm''s account <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N3. another farm''s account blocked: %', SQLERRM;
    END;

    -- Repaying more principal than is owed would make the lender a debtor.
    BEGIN
        PERFORM sppoultryloanpayment_record(
            p_farmid => v_farm, p_poultryloanid => v_loan, p_poultrycashaccountid => v_acct,
            p_principalamount => 999999);
        RAISE NOTICE 'N4. principal over the debt <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N4. principal over the debt blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM sppoultryloanpayment_record(
            p_farmid => v_farm, p_poultryloanid => v_loan, p_poultrycashaccountid => v_acct,
            p_principalamount => 0, p_interestamount => 0, p_feeamount => 0);
        RAISE NOTICE 'N5. a repayment of nothing <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N5. a repayment of nothing blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM sppoultryloanpayment_record(
            p_farmid => v_farm, p_poultryloanid => v_loan, p_poultrycashaccountid => v_acct,
            p_principalamount => 100, p_interestamount => -50);
        RAISE NOTICE 'N6. a negative part        <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N6. a negative part        blocked: %', SQLERRM;
    END;

    -- A draft loan has not been taken out yet.
    v_draft := sppoultryloan_create(
        p_farmid => v_farm, p_lendername => 'ZZ Draft Lender', p_originalprincipal => 5000,
        p_startdate => CURRENT_DATE, p_status => 'Draft', p_createdby => 'ZZ tester');
    BEGIN
        PERFORM sppoultryloanpayment_record(
            p_farmid => v_farm, p_poultryloanid => v_draft, p_poultrycashaccountid => v_acct,
            p_principalamount => 100);
        RAISE NOTICE 'N7. repaying a draft loan  <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N7. repaying a draft loan  blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM sppoultryloanpayment_reverse(
            (SELECT poultryloanpaymentid FROM poultryloanpayments
              WHERE farmid = v_farm AND status = 'Posted' ORDER BY 1 LIMIT 1),
            v_farm, '  ', 'ZZ tester');
        RAISE NOTICE 'N8. reversal with no reason <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N8. reversal with no reason blocked: %', SQLERRM;
    END;

    -- Cancelling a loan that has been partly repaid would orphan the payments.
    BEGIN
        PERFORM sppoultryloan_cancel(v_loan, v_farm, 'Should be blocked', 'ZZ tester');
        RAISE NOTICE 'N9. cancelling a repaid loan <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N9. cancelling a repaid loan blocked: %', SQLERRM;
    END;

    -- A repayment bigger than the account holds. The farm cannot pay what it
    -- does not have, and this account may not go negative.
    UPDATE poultrycashaccounts SET currentbalance = 100 WHERE poultrycashaccountid = v_acct;
    BEGIN
        PERFORM sppoultryloanpayment_record(
            p_farmid => v_farm, p_poultryloanid => v_loan, p_poultrycashaccountid => v_acct,
            p_principalamount => 5000);
        RAISE NOTICE 'N10. repaying more than held <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N10. repaying more than held blocked: %', SQLERRM;
    END;
END
$n$;

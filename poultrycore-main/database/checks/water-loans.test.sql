-- Behavioural checks for migration 259: water loans and repayments.
--
-- The water twin of poultry-loans.test.sql, claim for claim.
-- One DO $t$ block, a NOTICE per check reading "expect X got Y", then negative
-- cases that must each be blocked. Run inside a transaction you ROLL BACK; it
-- creates a cash account, a loan and repayments.
--
--   psql ... -X -c "BEGIN;" -f water-loans.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 259
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- The farm is looked up rather than hard-coded, and the lookup insists on
-- farms.type = 'Water': watercashaccounts also holds rows for a Generic company
-- built on the water rail, and the oldest account in the table is one of those.
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
--      by 12,500 -- the P&L must not think repaying a debt made the company
--      poorer.
--   3. **Cash flow shows the FULL 12,500 out**, because that is what left the
--      bank, while the P&L shows 2,500 of cost. Both, at once, from one event.
--      This is the claim the new NonCash clause on the expense arm exists for.
--   4. **No supplier payment, no supplier balance.** A lender is not a supplier.
--   5. Loan received is money in and never revenue.
--   6. Reversal puts all of it back and leaves every original row standing.
--
-- WHY THE COST ROWS HAVE FOUR SOURCETYPES AND NOT TWO
-- ---------------------------------------------------
-- waterexpenses has a unique index on (farmid, sourcetype, sourceid) that
-- poultry has no equivalent of -- one auto-written expense per source document.
-- So interest and fee cannot share 'LoanPayment'; they carry
-- LoanPaymentInterest / LoanPaymentFee, and their cancellations carry
-- LoanPaymentInterestReversal / LoanPaymentFeeReversal. B11 and D9 count them
-- by name so the split is pinned, not just the total.

DO $t$
DECLARE
    v_farm text;
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
    VALUES (v_farm, 'ZZ Loan Bank', 'BankAccount', 0, 0, FALSE, TRUE)
    RETURNING watercashaccountid INTO v_acct;

    SELECT s.moneyin, s.moneyout INTO v_in0, v_out0
    FROM   spwatercashflow_summary(v_farm, NULL, NULL) s;

    -- The P&L's own expense total, which is what must move by 2,500 and not by
    -- 12,500. Read from the report, not re-derived here.
    SELECT COALESCE(totalexpenses, 0) INTO v_exp0
    FROM   spwaterreport_periodpnl(v_farm, '2000-01-01'::date, '2099-12-31'::date);

    SELECT COUNT(*) INTO v_sales0 FROM watersales WHERE farmid = v_farm;
    SELECT COUNT(*) INTO v_supalloc0 FROM supplierpaymentallocation
     WHERE farmid = v_farm AND module = 'water';
    SELECT COUNT(*) INTO v_suppay0 FROM watersupplierpayments WHERE farmid = v_farm;

    -- =====================================================================
    -- A. Taking the loan. 100,000 borrowed, 98,000 received.
    -- =====================================================================
    v_loan := spwaterloan_create(
        p_farmid             => v_farm,
        p_lendername         => 'ZZ Rural Bank',
        p_originalprincipal  => 100000,
        p_startdate          => CURRENT_DATE - 30,
        p_amountreceived     => 98000,
        p_watercashaccountid => v_acct,
        p_lendertype         => 'Bank',
        p_interestrate       => 24,
        p_interesttype       => 'ReducingBalance',
        p_termmonths         => 12,
        p_paymentfrequency   => 'Monthly',
        p_loandate           => CURRENT_DATE - 30,
        p_nextpaymentdate    => CURRENT_DATE + 5,
        p_notes              => 'ZZ test loan',
        p_createdby          => 'ZZ tester');

    RAISE NOTICE 'A1. cash in is what ARRIVED expect 98000.00  got %',
        (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct);
    -- The debt is what was BORROWED, not what arrived.
    RAISE NOTICE 'A2. the debt is the PRINCIPAL expect 100000.00  got %',
        (SELECT outstandingprincipal FROM waterloans WHERE waterloanid = v_loan);
    RAISE NOTICE 'A3. one disbursement row    expect        1  got %',
        (SELECT COUNT(*) FROM watercashtransactions
          WHERE farmid = v_farm AND sourcetype = 'Loan' AND sourceid = v_loan);
    RAISE NOTICE 'A4. numbered LN-            expect        t  got %',
        (SELECT loannumber LIKE 'LN-%' FROM waterloans WHERE waterloanid = v_loan);
    RAISE NOTICE 'A5. status is Active        expect   Active  got %',
        (SELECT status FROM waterloans WHERE waterloanid = v_loan);

    -- Borrowing is not earning.
    RAISE NOTICE 'A6. no sale was created     expect        t  got %',
        ((SELECT COUNT(*) FROM watersales WHERE farmid = v_farm) = v_sales0);
    SELECT s.moneyin, s.moneyout INTO v_in1, v_out1
    FROM   spwatercashflow_summary(v_farm, NULL, NULL) s;
    RAISE NOTICE 'A7. money in rose by 98000  expect 98000.00  got %', (v_in1 - v_in0);
    RAISE NOTICE 'A8. filed as financing in   expect FinancingIn  got %',
        (SELECT r.flowgroup FROM spwatercashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'Loan' AND r.sourcerowid = v_loan);
    -- The 2,000 the lender kept is NOT silently expensed.
    SELECT COALESCE(totalexpenses, 0) INTO v_exp1
    FROM   spwaterreport_periodpnl(v_farm, '2000-01-01'::date, '2099-12-31'::date);
    RAISE NOTICE 'A9. withheld fee not guessed expect       t  got %', (v_exp1 = v_exp0);
    -- A BACK-DATED loan keeps midnight; 259 bakes in 256's rule from the start.
    RAISE NOTICE 'A10. back-dated is midnight expect        t  got %',
        (SELECT r.transactiondate = date_trunc('day', r.transactiondate)
           FROM spwatercashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'Loan' AND r.sourcerowid = v_loan);

    -- =====================================================================
    -- B. The repayment: 10,000 + 2,000 + 500 = 12,500.
    -- =====================================================================
    SELECT COUNT(*) INTO v_cashrows FROM watercashtransactions WHERE farmid = v_farm;

    v_pay := spwaterloanpayment_record(
        p_farmid             => v_farm,
        p_waterloanid        => v_loan,
        p_watercashaccountid => v_acct,
        p_principalamount    => 10000,
        p_interestamount     => 2000,
        p_feeamount          => 500,
        p_paymentdate        => (now() at time zone 'utc'),
        p_paymentmethod      => 'BankTransfer',
        p_nextpaymentdate    => CURRENT_DATE + 35,
        p_createdby          => 'ZZ tester');

    RAISE NOTICE 'B1. total is the sum        expect 12500.00  got %',
        (SELECT totalamount FROM waterloanpayments WHERE waterloanpaymentid = v_pay);

    -- **THE** check. One row, for the total.
    RAISE NOTICE 'B2. ONE cash row for it     expect        1  got %',
        (SELECT COUNT(*) FROM watercashtransactions
          WHERE farmid = v_farm AND sourcetype = 'LoanPayment' AND sourceid = v_pay);
    RAISE NOTICE 'B3. and it is the TOTAL     expect -12500.00  got %',
        (SELECT amount FROM watercashtransactions
          WHERE farmid = v_farm AND sourcetype = 'LoanPayment' AND sourceid = v_pay);
    -- Only one new cash row exists at all: the expense rows added none.
    RAISE NOTICE 'B4. exactly one row added   expect        1  got %',
        ((SELECT COUNT(*) FROM watercashtransactions WHERE farmid = v_farm) - v_cashrows);
    RAISE NOTICE 'B5. account down by 12500   expect 85500.00  got %',
        (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct);

    -- The debt.
    RAISE NOTICE 'B6. principal 10000 lower   expect 90000.00  got %',
        (SELECT outstandingprincipal FROM waterloans WHERE waterloanid = v_loan);
    RAISE NOTICE 'B7. repaid total tracked    expect 10000.00  got %',
        (SELECT totalprincipalrepaid FROM waterloans WHERE waterloanid = v_loan);
    RAISE NOTICE 'B8. interest paid tracked   expect  2000.00  got %',
        (SELECT totalinterestpaid FROM waterloans WHERE waterloanid = v_loan);
    RAISE NOTICE 'B9. fees paid tracked       expect   500.00  got %',
        (SELECT totalfeespaid FROM waterloans WHERE waterloanid = v_loan);

    -- **THE OTHER** check. Cost is 2,500 -- not 12,500.
    SELECT COALESCE(totalexpenses, 0) INTO v_exp2
    FROM   spwaterreport_periodpnl(v_farm, '2000-01-01'::date, '2099-12-31'::date);
    RAISE NOTICE 'B10. P&L cost is 2500       expect  2500.00  got %', (v_exp2 - v_exp1);
    RAISE NOTICE 'B11. two expense rows       expect        2  got %',
        (SELECT COUNT(*) FROM waterexpenses
          WHERE farmid = v_farm AND sourceid = v_pay
            AND sourcetype IN ('LoanPaymentInterest', 'LoanPaymentFee'));
    RAISE NOTICE 'B12. both are NonCash       expect        2  got %',
        (SELECT COUNT(*) FROM waterexpenses
          WHERE farmid = v_farm AND sourceid = v_pay
            AND sourcetype IN ('LoanPaymentInterest', 'LoanPaymentFee')
            AND paymentmethod = 'NonCash');
    -- The categories were created on demand, because waterexpensecategoryid is
    -- NOT NULL and categories are per-company.
    RAISE NOTICE 'B13. categories exist       expect        2  got %',
        (SELECT COUNT(*) FROM waterexpensecategories
          WHERE farmid = v_farm AND name IN ('Interest Expense', 'Loan Fee'));

    -- Cash flow: the FULL amount out, once.
    SELECT s.moneyin, s.moneyout INTO v_in2, v_out2
    FROM   spwatercashflow_summary(v_farm, NULL, NULL) s;
    RAISE NOTICE 'B14. money out is 12500     expect 12500.00  got %', (v_out2 - v_out1);
    RAISE NOTICE 'B15. one cash-flow row      expect        1  got %',
        (SELECT COUNT(*) FROM spwatercashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'LoanPayment' AND r.sourcerowid = v_pay);
    -- The NonCash expenses must not appear in the expense arm as well. This is
    -- the clause 259 added; without it money out would be 15,000.
    RAISE NOTICE 'B16. expenses not doubled   expect        0  got %',
        (SELECT COUNT(*) FROM spwatercashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'Expense'
            AND r.sourcerowid IN (SELECT waterexpenseid FROM waterexpenses
                                   WHERE farmid = v_farm
                                     AND sourcetype LIKE 'LoanPayment%'));

    -- A lender is not a supplier.
    RAISE NOTICE 'B17. no supplier payment    expect        t  got %',
        ((SELECT COUNT(*) FROM watersupplierpayments WHERE farmid = v_farm) = v_suppay0);
    RAISE NOTICE 'B18. no allocation either   expect        t  got %',
        ((SELECT COUNT(*) FROM supplierpaymentallocation
           WHERE farmid = v_farm AND module = 'water') = v_supalloc0);
    -- And the interest never becomes something owed to a creditor.
    RAISE NOTICE 'B19. not on payables        expect        0  got %',
        (SELECT COUNT(*) FROM fnwaterpayables(v_farm) d
          WHERE d.documenttype = 'Expense'
            AND d.documentid IN (SELECT waterexpenseid FROM waterexpenses
                                  WHERE farmid = v_farm
                                    AND sourcetype LIKE 'LoanPayment%'));

    -- =====================================================================
    -- C. Paying the rest off.
    -- =====================================================================
    -- Staging, not a claim: the account holds 85,500 after the first repayment,
    -- and the company has to have earned the rest from somewhere before it can
    -- pay off 90,000. The guard that refuses an overdrawing repayment is
    -- exercised deliberately in N-cases below.
    UPDATE watercashaccounts SET currentbalance = currentbalance + 100000
    WHERE  watercashaccountid = v_acct;

    v_pay2 := spwaterloanpayment_record(
        p_farmid             => v_farm,
        p_waterloanid        => v_loan,
        p_watercashaccountid => v_acct,
        p_principalamount    => 90000,
        p_paymentdate        => (now() at time zone 'utc'),
        p_createdby          => 'ZZ tester');

    RAISE NOTICE 'C1. nothing left owing      expect     0.00  got %',
        (SELECT outstandingprincipal FROM waterloans WHERE waterloanid = v_loan);
    -- Decided by what is OUTSTANDING, not by comparing paid against principal:
    -- 100,000 of principal plus 2,500 of cost was paid, which is not 100,000.
    RAISE NOTICE 'C2. status is PaidOff       expect  PaidOff  got %',
        (SELECT status FROM waterloans WHERE waterloanid = v_loan);
    RAISE NOTICE 'C3. paid-off date stamped   expect        t  got %',
        (SELECT paidoffdate IS NOT NULL FROM waterloans WHERE waterloanid = v_loan);
    -- A principal-only payment creates no expense at all.
    RAISE NOTICE 'C4. no expense for it       expect        0  got %',
        (SELECT COUNT(*) FROM waterexpenses
          WHERE farmid = v_farm AND sourceid = v_pay2
            AND sourcetype IN ('LoanPaymentInterest', 'LoanPaymentFee'));

    -- =====================================================================
    -- D. Reversing the first repayment.
    -- =====================================================================
    PERFORM spwaterloanpayment_reverse(v_pay, v_farm, 'Recorded twice by mistake', 'ZZ tester');

    RAISE NOTICE 'D1. marked reversed         expect Reversed  got %',
        (SELECT status FROM waterloanpayments WHERE waterloanpaymentid = v_pay);
    RAISE NOTICE 'D2. debt is back up         expect 10000.00  got %',
        (SELECT outstandingprincipal FROM waterloans WHERE waterloanid = v_loan);
    -- A loan that was paid off is live again.
    RAISE NOTICE 'D3. loan is Active again    expect   Active  got %',
        (SELECT status FROM waterloans WHERE waterloanid = v_loan);
    RAISE NOTICE 'D4. paid-off date cleared   expect        t  got %',
        (SELECT paidoffdate IS NULL FROM waterloans WHERE waterloanid = v_loan);
    RAISE NOTICE 'D5. interest total undone   expect     0.00  got %',
        (SELECT totalinterestpaid FROM waterloans WHERE waterloanid = v_loan);

    -- Append-only: original rows stay, opposite rows appear.
    RAISE NOTICE 'D6. two cash rows for it    expect        2  got %',
        (SELECT COUNT(*) FROM watercashtransactions
          WHERE farmid = v_farm AND sourcetype = 'LoanPayment' AND sourceid = v_pay);
    RAISE NOTICE 'D7. and they net to zero    expect     0.00  got %',
        (SELECT COALESCE(SUM(amount), 0) FROM watercashtransactions
          WHERE farmid = v_farm AND sourcetype = 'LoanPayment' AND sourceid = v_pay);
    -- The cost is cancelled by compensating rows, not by deletion.
    RAISE NOTICE 'D8. original expenses kept  expect        2  got %',
        (SELECT COUNT(*) FROM waterexpenses
          WHERE farmid = v_farm AND sourceid = v_pay
            AND sourcetype IN ('LoanPaymentInterest', 'LoanPaymentFee'));
    RAISE NOTICE 'D9. two cancelling rows     expect        2  got %',
        (SELECT COUNT(*) FROM waterexpenses
          WHERE farmid = v_farm AND sourceid = v_pay
            AND sourcetype IN ('LoanPaymentInterestReversal', 'LoanPaymentFeeReversal'));
    RAISE NOTICE 'D10. cost back where it was expect        t  got %',
        ((SELECT COALESCE(totalexpenses, 0)
            FROM spwaterreport_periodpnl(v_farm, '2000-01-01'::date, '2099-12-31'::date)) = v_exp1);

    -- Cash flow drops the reversed payment entirely.
    SELECT s.moneyin, s.moneyout INTO v_in3, v_out3
    FROM   spwatercashflow_summary(v_farm, NULL, NULL) s;
    RAISE NOTICE 'D11. its 12500 is gone      expect        0  got %',
        (SELECT COUNT(*) FROM spwatercashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'LoanPayment' AND r.sourcerowid = v_pay);
    -- Only the 90,000 payoff remains as money out from this loan.
    RAISE NOTICE 'D12. money out is the rest  expect 90000.00  got %', (v_out3 - v_out1);
    -- And the compensating expense rows did not sneak into cash out either.
    RAISE NOTICE 'D13. reversal rows not cash expect        0  got %',
        (SELECT COUNT(*) FROM spwatercashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'Expense'
            AND r.sourcerowid IN (SELECT waterexpenseid FROM waterexpenses
                                   WHERE farmid = v_farm
                                     AND sourcetype LIKE 'LoanPayment%Reversal'));
END
$t$;

-- =============================================================================
-- Negative cases. Each must be BLOCKED.
-- =============================================================================
DO $n$
DECLARE
    v_farm  text;
    v_other text;
    v_acct integer; v_otheracct integer; v_loan integer; v_draft integer;
BEGIN
    SELECT farmid, watercashaccountid INTO v_farm, v_acct
    FROM   watercashaccounts WHERE accountname = 'ZZ Loan Bank' LIMIT 1;

    SELECT a.farmid INTO v_other
    FROM   watercashaccounts a
    JOIN   farms f ON f.farmid = a.farmid AND f.type = 'Water'
    WHERE  a.farmid <> v_farm
    GROUP  BY a.farmid
    ORDER  BY MIN(a.watercashaccountid)
    LIMIT  1;
    SELECT watercashaccountid INTO v_otheracct
    FROM   watercashaccounts WHERE farmid = v_other ORDER BY 1 LIMIT 1;

    SELECT waterloanid INTO v_loan FROM waterloans
     WHERE farmid = v_farm AND lendername = 'ZZ Rural Bank';

    -- Receiving more than was borrowed is a slip, not a loan.
    BEGIN
        PERFORM spwaterloan_create(
            p_farmid => v_farm, p_lendername => 'ZZ Bad', p_originalprincipal => 1000,
            p_startdate => CURRENT_DATE, p_amountreceived => 5000,
            p_watercashaccountid => v_acct);
        RAISE NOTICE 'N1. received > principal   <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N1. received > principal   blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spwaterloan_create(
            p_farmid => v_farm, p_lendername => '  ', p_originalprincipal => 1000,
            p_startdate => CURRENT_DATE);
        RAISE NOTICE 'N2. a loan with no lender  <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N2. a loan with no lender  blocked: %', SQLERRM;
    END;

    -- Money must land somewhere real.
    BEGIN
        PERFORM spwaterloan_create(
            p_farmid => v_farm, p_lendername => 'ZZ Bad', p_originalprincipal => 1000,
            p_startdate => CURRENT_DATE, p_amountreceived => 1000,
            p_watercashaccountid => v_otheracct);
        RAISE NOTICE 'N3. another farm''s account <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N3. another farm''s account blocked: %', SQLERRM;
    END;

    -- Repaying more principal than is owed would make the lender a debtor.
    BEGIN
        PERFORM spwaterloanpayment_record(
            p_farmid => v_farm, p_waterloanid => v_loan, p_watercashaccountid => v_acct,
            p_principalamount => 999999);
        RAISE NOTICE 'N4. principal over the debt <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N4. principal over the debt blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spwaterloanpayment_record(
            p_farmid => v_farm, p_waterloanid => v_loan, p_watercashaccountid => v_acct,
            p_principalamount => 0, p_interestamount => 0, p_feeamount => 0);
        RAISE NOTICE 'N5. a repayment of nothing <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N5. a repayment of nothing blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spwaterloanpayment_record(
            p_farmid => v_farm, p_waterloanid => v_loan, p_watercashaccountid => v_acct,
            p_principalamount => 100, p_interestamount => -50);
        RAISE NOTICE 'N6. a negative part        <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N6. a negative part        blocked: %', SQLERRM;
    END;

    -- A draft loan has not been taken out yet.
    v_draft := spwaterloan_create(
        p_farmid => v_farm, p_lendername => 'ZZ Draft Lender', p_originalprincipal => 5000,
        p_startdate => CURRENT_DATE, p_status => 'Draft', p_createdby => 'ZZ tester');
    BEGIN
        PERFORM spwaterloanpayment_record(
            p_farmid => v_farm, p_waterloanid => v_draft, p_watercashaccountid => v_acct,
            p_principalamount => 100);
        RAISE NOTICE 'N7. repaying a draft loan  <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N7. repaying a draft loan  blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spwaterloanpayment_reverse(
            (SELECT waterloanpaymentid FROM waterloanpayments
              WHERE farmid = v_farm AND status = 'Posted' ORDER BY 1 LIMIT 1),
            v_farm, '  ', 'ZZ tester');
        RAISE NOTICE 'N8. reversal with no reason <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N8. reversal with no reason blocked: %', SQLERRM;
    END;

    -- Cancelling a loan that has been partly repaid would orphan the payments.
    BEGIN
        PERFORM spwaterloan_cancel(v_loan, v_farm, 'Should be blocked', 'ZZ tester');
        RAISE NOTICE 'N9. cancelling a repaid loan <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N9. cancelling a repaid loan blocked: %', SQLERRM;
    END;

    -- A repayment bigger than the account holds. The company cannot pay what it
    -- does not have, and this account may not go negative.
    UPDATE watercashaccounts SET currentbalance = 100 WHERE watercashaccountid = v_acct;
    BEGIN
        PERFORM spwaterloanpayment_record(
            p_farmid => v_farm, p_waterloanid => v_loan, p_watercashaccountid => v_acct,
            p_principalamount => 5000);
        RAISE NOTICE 'N10. repaying more than held <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N10. repaying more than held blocked: %', SQLERRM;
    END;
END
$n$;

-- Behavioural checks for migration 293: converting a Cash Flow borrowing into a
-- real, repayable loan.
--
-- Run inside a transaction you ROLL BACK; it writes adjustments and loans.
--
--   psql ... -X -c "BEGIN;" -f water-loan-from-cash-adjustment.test.sql -c "ROLLBACK;"
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **Converting moves no money.** Not cash flow, not a cash account balance, not
-- what the company owes. Section B measures all three across the conversion and
-- is the reason this migration is safe to run on a live company.
--
-- The rest:
--   A. The conversion produces a real loan carrying the adjustment's date,
--      amount and a lender the user supplied.
--   C. The debt is counted ONCE afterwards -- the adjustment stops appearing as
--      a legacy row the moment its loan exists.
--   D. It is now REPAYABLE, which is the entire point, and repaying it behaves
--      like any other loan.
--   E. What must be refused: a non-LoanReceived row, a negative amount (that is
--      a correction, not a borrowing), a second conversion, and a blank lender.

DO $t$
DECLARE
    v_farm    text;
    v_user    text;
    v_tbl     text;
    v_acct    integer;
    v_adj     integer;
    v_neg     integer;
    v_owner   integer;
    v_loanid  integer;
    v_cash0   numeric;
    v_flow0   numeric;
    v_owed0   numeric;
    v_r       record;
    v_n       integer;
BEGIN
    -- Prefer a company whose cash account can actually FUND the test repayment
    -- in section D -- that repayment is the entire point of the migration.
    -- Merely having an account is not enough: the repayment SP refuses to take
    -- an account below zero, and several dev companies sit in overdraft.
    SELECT f.farmid INTO v_farm
    FROM   farms f
    WHERE  f.type = 'Water'
    ORDER  BY (EXISTS (SELECT 1 FROM watercashaccounts a
                       WHERE a.farmid = f.farmid AND a.isactive = TRUE
                         AND (a.currentbalance >= 1050 OR a.allownegativebalance))) DESC,
              f.farmid
    LIMIT  1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No water company to test against.'; END IF;
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    IF v_tbl IS NULL THEN RAISE EXCEPTION 'No cashadjustment table on this environment.'; END IF;
    RAISE NOTICE '   using water company %', v_farm;

    EXECUTE format('SELECT ca.userid::text FROM %s ca LIMIT 1', v_tbl) INTO v_user;
    v_user := COALESCE(v_user, 'ZZ tester');

    SELECT a.watercashaccountid INTO v_acct FROM watercashaccounts a
    WHERE a.farmid = v_farm AND a.isactive = TRUE
      AND (a.currentbalance >= 1050 OR a.allownegativebalance)
    ORDER BY a.watercashaccountid LIMIT 1;

    EXECUTE format($sql$
        INSERT INTO %s (farmid, userid, adjustmentdate, adjustmenttype, amount, description, createddate)
        VALUES ($1, $2, CURRENT_DATE, 'LoanReceived', 4000, 'ZZ 293 borrowed from cousin', now())
        RETURNING adjustmentid
    $sql$, v_tbl) INTO v_adj USING v_farm, v_user;

    -- =====================================================================
    -- B (measured first). EVERY number that must not move.
    -- =====================================================================
    SELECT COALESCE(SUM(a.currentbalance), 0)::numeric(14,2) INTO v_cash0
    FROM   watercashaccounts a WHERE a.farmid = v_farm;
    SELECT COALESCE(SUM(r.amount), 0)::numeric(14,2) INTO v_flow0
    FROM   spwatercashflow_rows(v_farm) r;
    SELECT outstandingprincipal INTO v_owed0 FROM spwaterloan_summary(v_farm);

    RAISE NOTICE '   before: cash accounts %, cash flow net %, owed %', v_cash0, v_flow0, v_owed0;

    -- =====================================================================
    -- A. THE CONVERSION.
    -- =====================================================================
    v_loanid := spwaterloan_fromadjustment(
        p_farmid => v_farm, p_adjustmentid => v_adj,
        p_lendername => 'ZZ Cousin Kofi', p_lendertype => 'FamilyFriend',
        p_interestrate => 5, p_interesttype => 'Simple',
        p_createdby => 'ZZ tester');

    SELECT * INTO v_r FROM spwaterloan_getall(v_farm, 'All') r
    WHERE r.source = 'Loan' AND r.sourceid = v_loanid;

    RAISE NOTICE 'A1. a real loan now exists    expect     Loan  got %', v_r.source;
    RAISE NOTICE 'A2. with the adjustment amount expect  4000.00  got %', v_r.originalprincipal;
    RAISE NOTICE 'A3. all of it still owed      expect  4000.00  got %', v_r.outstandingprincipal;
    RAISE NOTICE 'A4. and a lender at last      expect ZZ Cousin Kofi  got %', v_r.lendername;
    RAISE NOTICE 'A5. it has a real loan id     expect        t  got %', (v_r.waterloanid > 0);
    RAISE NOTICE 'A6. linked back to the adjustment expect        t  got %',
        ((SELECT l.sourceadjustmentid FROM waterloans l WHERE l.waterloanid = v_loanid) = v_adj);
    -- No loan cash row: the adjustment is still the cash event.
    RAISE NOTICE 'A7. and NO loan cash row      expect        t  got %',
        ((SELECT l.watercashtransactionid FROM waterloans l WHERE l.waterloanid = v_loanid) IS NULL);
    RAISE NOTICE 'A8. the trail is in the notes expect        t  got %',
        (v_r.notes LIKE '%adjustment #' || v_adj::text || '%');

    -- =====================================================================
    -- B. NOTHING MOVED. The claim this migration lives or dies on.
    -- =====================================================================
    RAISE NOTICE 'B1. cash accounts unmoved     expect     0.00  got %',
        ((SELECT COALESCE(SUM(a.currentbalance), 0)::numeric(14,2) FROM watercashaccounts a WHERE a.farmid = v_farm) - v_cash0);
    RAISE NOTICE 'B2. cash flow unmoved         expect     0.00  got %',
        ((SELECT COALESCE(SUM(r.amount), 0)::numeric(14,2) FROM spwatercashflow_rows(v_farm) r) - v_flow0);
    RAISE NOTICE 'B3. and the debt is unmoved   expect     0.00  got %',
        ((SELECT outstandingprincipal FROM spwaterloan_summary(v_farm)) - v_owed0);

    -- =====================================================================
    -- C. COUNTED ONCE. The adjustment stops being a legacy row.
    -- =====================================================================
    RAISE NOTICE 'C1. no longer a legacy row    expect        0  got %',
        (SELECT COUNT(*) FROM fnwaterloan_legacy(v_farm) g WHERE g.adjustmentid = v_adj);
    RAISE NOTICE 'C2. and appears exactly once  expect        1  got %',
        (SELECT COUNT(*) FROM spwaterloan_getall(v_farm, 'All') r
         WHERE r.originalprincipal = 4000.00 AND r.notes LIKE '%ZZ 293 borrowed from cousin%');
    -- It is still a cash event on the Cash Flow page, exactly as before.
    RAISE NOTICE 'C3. still in cash flow        expect        1  got %',
        (SELECT COUNT(*) FROM spwatercashflow_rows(v_farm) r
         WHERE r.sourcetype = 'LoanReceived' AND r.sourceid = v_adj);

    -- =====================================================================
    -- D. IT IS REPAYABLE. The entire point of the exercise.
    -- =====================================================================
    IF v_acct IS NULL THEN
        RAISE NOTICE 'D0. no cash account on this company -- repayment not exercised';
    ELSE
        PERFORM spwaterloanpayment_record(
            p_farmid => v_farm, p_waterloanid => v_loanid,
            p_principalamount => 1000, p_interestamount => 50, p_feeamount => 0,
            p_otheramount => 0, p_watercashaccountid => v_acct,
            p_paymentdate => (now() at time zone 'utc'),
            p_paymentmethod => 'Cash', p_referencenumber => NULL,
            p_notes => 'ZZ 293 first repayment', p_createdby => 'ZZ tester');

        RAISE NOTICE 'D1. the debt came down       expect  3000.00  got %',
            (SELECT l.outstandingprincipal FROM waterloans l WHERE l.waterloanid = v_loanid);
        RAISE NOTICE 'D2. principal repaid recorded expect  1000.00  got %',
            (SELECT l.totalprincipalrepaid FROM waterloans l WHERE l.waterloanid = v_loanid);
        RAISE NOTICE 'D3. interest recorded as cost expect    50.00  got %',
            (SELECT l.totalinterestpaid FROM waterloans l WHERE l.waterloanid = v_loanid);
        RAISE NOTICE 'D4. and the cash went out    expect -1050.00  got %',
            ((SELECT COALESCE(SUM(a.currentbalance), 0)::numeric(14,2) FROM watercashaccounts a WHERE a.farmid = v_farm) - v_cash0);
    END IF;

    RAISE NOTICE '--- 293 conversion checks done. ---';
END
$t$;

-- =============================================================================
-- E. WHAT MUST BE REFUSED. Separate block: each failure aborts its own
--    subtransaction.
-- =============================================================================
DO $e$
DECLARE
    v_farm text;
    v_user text;
    v_tbl  text;
    v_neg  integer;
    v_own  integer;
    v_good integer;
    v_id   integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    EXECUTE format('SELECT ca.userid::text FROM %s ca LIMIT 1', v_tbl) INTO v_user;
    v_user := COALESCE(v_user, 'ZZ tester');

    EXECUTE format($sql$
        INSERT INTO %s (farmid, userid, adjustmentdate, adjustmenttype, amount, description, createddate)
        VALUES ($1, $2, CURRENT_DATE, 'LoanReceived', -1500, 'ZZ 293 correction', now())
        RETURNING adjustmentid
    $sql$, v_tbl) INTO v_neg USING v_farm, v_user;

    EXECUTE format($sql$
        INSERT INTO %s (farmid, userid, adjustmentdate, adjustmenttype, amount, description, createddate)
        VALUES ($1, $2, CURRENT_DATE, 'OwnerInjection', 3000, 'ZZ 293 owner money', now())
        RETURNING adjustmentid
    $sql$, v_tbl) INTO v_own USING v_farm, v_user;

    EXECUTE format($sql$
        INSERT INTO %s (farmid, userid, adjustmentdate, adjustmenttype, amount, description, createddate)
        VALUES ($1, $2, CURRENT_DATE, 'LoanReceived', 2200, 'ZZ 293 convert twice', now())
        RETURNING adjustmentid
    $sql$, v_tbl) INTO v_good USING v_farm, v_user;

    BEGIN
        PERFORM spwaterloan_fromadjustment(v_farm, v_neg, 'ZZ Lender');
        RAISE NOTICE 'E1. a correction is refused  expect blocked  got ALLOWED -- WRONG';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'E1. a correction is refused  expect blocked  got blocked';
    END;

    BEGIN
        PERFORM spwaterloan_fromadjustment(v_farm, v_own, 'ZZ Lender');
        RAISE NOTICE 'E2. owner money is refused   expect blocked  got ALLOWED -- WRONG';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'E2. owner money is refused   expect blocked  got blocked';
    END;

    BEGIN
        PERFORM spwaterloan_fromadjustment(v_farm, v_good, '   ');
        RAISE NOTICE 'E3. a blank lender is refused expect blocked  got ALLOWED -- WRONG';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'E3. a blank lender is refused expect blocked  got blocked';
    END;

    -- And the double-conversion guard, which is an INDEX rather than a check,
    -- so it holds even against two people clicking at the same moment.
    v_id := spwaterloan_fromadjustment(v_farm, v_good, 'ZZ Lender');
    RAISE NOTICE 'E4. the first conversion works expect        t  got %', (v_id > 0);
    BEGIN
        PERFORM spwaterloan_fromadjustment(v_farm, v_good, 'ZZ Lender Again');
        RAISE NOTICE 'E5. the second is refused    expect blocked  got ALLOWED -- WRONG';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'E5. the second is refused    expect blocked  got blocked';
    END;

    RAISE NOTICE '--- 293 refusal checks done. ROLL BACK this transaction. ---';
END
$e$;

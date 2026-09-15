-- Behavioural checks for migration 256: a loan received today sorts by when it
-- was recorded, not to midnight.
--
-- Run inside a transaction you ROLL BACK; it creates a cash account and loans.
--
--   psql ... -X -c "BEGIN;" -f poultry-cashflow-loan-time.test.sql -c "ROLLBACK;"
--
-- The claims:
--   1. A loan dated TODAY reports the moment it was recorded, so it sorts to
--      the top of a newest-first cash flow instead of under everything else
--      recorded today.
--   2. A BACK-DATED loan still reports midnight on the day it is dated. Using
--      the recording time unconditionally would drag last Tuesday's loan into
--      today, above rows that really did happen after it.
--   3. Only the time of day moved. The date, the amount, the sign and the
--      grouping are untouched, and so are money in, money out and net.

DO $t$
DECLARE
    v_farm text := '7b95dafa-758f-4461-891d-f612131978fd';   -- Dev Test Farm (Poultry)
    v_acct integer;
    v_today   integer;
    v_backdated integer;

    v_in0 numeric; v_out0 numeric; v_net0 numeric;
    v_in1 numeric; v_out1 numeric; v_net1 numeric;

    v_ts_today  timestamp;
    v_ts_back   timestamp;
    v_created   timestamp;
BEGIN
    INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance,
                                     currentbalance, allownegativebalance, isactive)
    VALUES (v_farm, 'ZZ Loan Time Bank', 'BankAccount', 0, 0, FALSE, TRUE)
    RETURNING poultrycashaccountid INTO v_acct;

    SELECT s.moneyin, s.moneyout, s.netcashflow INTO v_in0, v_out0, v_net0
    FROM   sppoultrycashflow_summary(v_farm, NULL, NULL) s;

    -- =====================================================================
    -- A. A loan taken out today.
    -- =====================================================================
    v_today := sppoultryloan_create(
        p_farmid => v_farm, p_lendername => 'ZZ Today Lender',
        p_originalprincipal => 5000, p_startdate => CURRENT_DATE,
        p_loandate => CURRENT_DATE, p_amountreceived => 5000,
        p_poultrycashaccountid => v_acct, p_createdby => 'ZZ tester');

    SELECT l.createdat INTO v_created FROM poultryloans l WHERE l.poultryloanid = v_today;
    SELECT r.transactiondate INTO v_ts_today
    FROM   sppoultrycashflow_rows(v_farm, NULL, NULL) r
    WHERE  r.rowsource = 'Loan' AND r.sourcerowid = v_today;

    -- The whole point: not midnight.
    RAISE NOTICE 'A1. today is NOT midnight   expect        t  got %',
        (v_ts_today <> date_trunc('day', v_ts_today));
    RAISE NOTICE 'A2. it is the moment kept   expect        t  got %', (v_ts_today = v_created);
    -- Still filed on the right DAY, which is what the report is about.
    RAISE NOTICE 'A3. still dated today       expect        t  got %',
        (v_ts_today::date = CURRENT_DATE);

    -- =====================================================================
    -- B. A loan taken out last week and typed in now.
    -- =====================================================================
    v_backdated := sppoultryloan_create(
        p_farmid => v_farm, p_lendername => 'ZZ Backdated Lender',
        p_originalprincipal => 3000, p_startdate => CURRENT_DATE - 7,
        p_loandate => CURRENT_DATE - 7, p_amountreceived => 3000,
        p_poultrycashaccountid => v_acct, p_createdby => 'ZZ tester');

    SELECT r.transactiondate INTO v_ts_back
    FROM   sppoultrycashflow_rows(v_farm, NULL, NULL) r
    WHERE  r.rowsource = 'Loan' AND r.sourcerowid = v_backdated;

    -- Midnight on the day it belongs to, NOT the moment it was typed in: using
    -- the recording time here would drag it into today, above rows that really
    -- did happen after it.
    RAISE NOTICE 'B1. back-dated is midnight  expect        t  got %',
        (v_ts_back = date_trunc('day', v_ts_back));
    RAISE NOTICE 'B2. and dated a week ago    expect        t  got %',
        (v_ts_back::date = CURRENT_DATE - 7);
    RAISE NOTICE 'B3. NOT dragged into today  expect        t  got %',
        (v_ts_back::date <> CURRENT_DATE);

    -- =====================================================================
    -- C. Newest first actually works now.
    -- =====================================================================
    -- Today's loan sorts above the back-dated one, and above midnight today.
    RAISE NOTICE 'C1. today sorts above older expect        t  got %', (v_ts_today > v_ts_back);
    RAISE NOTICE 'C2. and above todays start  expect        t  got %',
        (v_ts_today > CURRENT_DATE::timestamp);

    -- =====================================================================
    -- D. Only the clock moved.
    -- =====================================================================
    SELECT s.moneyin, s.moneyout, s.netcashflow INTO v_in1, v_out1, v_net1
    FROM   sppoultrycashflow_summary(v_farm, NULL, NULL) s;
    -- The two loans brought in 8,000 between them; nothing else changed.
    RAISE NOTICE 'D1. money in is the loans   expect  8000.00  got %', (v_in1 - v_in0);
    RAISE NOTICE 'D2. money out unmoved       expect        t  got %', (v_out1 = v_out0);
    RAISE NOTICE 'D3. net moved by the same   expect  8000.00  got %', (v_net1 - v_net0);
    -- Amount, sign and grouping are what they always were.
    RAISE NOTICE 'D4. amount is what arrived  expect  5000.00  got %',
        (SELECT r.amount FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'Loan' AND r.sourcerowid = v_today);
    RAISE NOTICE 'D5. still financing in      expect FinancingIn  got %',
        (SELECT r.flowgroup FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'Loan' AND r.sourcerowid = v_today);
    RAISE NOTICE 'D6. still one row per loan  expect        2  got %',
        (SELECT COUNT(*) FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r
          WHERE r.rowsource = 'Loan' AND r.sourcerowid IN (v_today, v_backdated));
END
$t$;

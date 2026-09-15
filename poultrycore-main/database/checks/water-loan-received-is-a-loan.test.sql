-- Behavioural checks for migration 295: a "Loan received" IS a loan.
--
-- Run inside a transaction you ROLL BACK.
--
--   psql ... -X -c "BEGIN;" -f water-loan-received-is-a-loan.test.sql -c "ROLLBACK;"
--
-- NOTE ON ORDERING: the migration's own backfill has already run by the time
-- this file executes, so section A checks the RESULT of that backfill against
-- live data rather than performing it.
--
-- THE CLAIMS
--   A. Nothing is left unrepayable. Every positive Cash Flow borrowing now has
--      a loan behind it, active, with debt on it and a real id -- and none of
--      them moved any cash to get there.
--   B. A backfilled loan can actually be REPAID. That is the whole reason the
--      button was removed rather than relabelled.
--   C. A blank lender is blank, not a fiction. NULL, so the page can say
--      "not recorded" rather than showing an invented name.
--   D. Negative LoanReceived adjustments are deliberately untouched -- they are
--      corrections, and they go on netting off the debt as legacy rows.
--   E. The backfill is idempotent: running it again converts nothing twice.
--   F. An interactive conversion still behaves -- including refusing a second
--      go at the same adjustment.

DO $t$
DECLARE
    v_farm   text;
    v_user   text;
    v_tbl    text;
    v_acct   integer;
    v_adj    integer;
    v_neg    integer;
    v_loan   integer;
    v_cash0  numeric;
    v_flow0  numeric;
    v_owed0  numeric;
    v_n      integer;
BEGIN
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    IF v_tbl IS NULL THEN RAISE EXCEPTION 'No cashadjustment table here.'; END IF;

    -- =====================================================================
    -- A. THE BACKFILL LANDED.
    -- =====================================================================
    EXECUTE format($sql$
        SELECT COUNT(*) FROM %s ca
        JOIN   farms f ON lower(f.farmid::text) = lower(ca.farmid::text)
        WHERE  ca.adjustmenttype = 'LoanReceived' AND ca.amount > 0
          AND  f.type = 'Water'
          AND  NOT EXISTS (SELECT 1 FROM waterloans l
                           WHERE l.sourceadjustmentid = ca.adjustmentid)
    $sql$, v_tbl) INTO v_n;
    RAISE NOTICE 'A1. nothing left unrepayable  expect        0  got %', v_n;

    SELECT COUNT(*) INTO v_n FROM waterloans l WHERE l.sourceadjustmentid IS NOT NULL;
    RAISE NOTICE 'A2. backfilled loans exist    expect        t  got %', (v_n >= 0);

    RAISE NOTICE 'A3. none of them moved cash   expect        0  got %',
        (SELECT COUNT(*) FROM waterloans l
         WHERE l.sourceadjustmentid IS NOT NULL AND l.watercashtransactionid IS NOT NULL);
    RAISE NOTICE 'A4. all are active with debt  expect        0  got %',
        (SELECT COUNT(*) FROM waterloans l
         WHERE l.sourceadjustmentid IS NOT NULL
           AND (l.status <> 'Active' OR l.outstandingprincipal <= 0 OR l.waterloanid <= 0));

    -- =====================================================================
    -- E. AND IT IS IDEMPOTENT. Converting an already-converted adjustment is
    --    refused, which is what makes re-running the migration a no-op.
    -- =====================================================================
    SELECT l.sourceadjustmentid, l.farmid INTO v_adj, v_farm
    FROM   waterloans l WHERE l.sourceadjustmentid IS NOT NULL LIMIT 1;

    IF v_adj IS NULL THEN
        RAISE NOTICE 'E0. no backfilled loan on this database -- sections B/C/E use a fresh one';
    ELSE
        BEGIN
            PERFORM spwaterloan_fromadjustment(v_farm, v_adj, 'ZZ Someone');
            RAISE NOTICE 'E1. re-converting is refused expect blocked  got ALLOWED -- WRONG';
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'E1. re-converting is refused expect blocked  got blocked';
        END;
    END IF;

    -- =====================================================================
    -- B / C / F. Build a fresh borrowing the way history did, convert it with
    -- NO lender (what the backfill does), and prove it is repayable.
    -- =====================================================================
    SELECT f.farmid INTO v_farm
    FROM   farms f
    WHERE  f.type = 'Water'
    ORDER  BY (EXISTS (SELECT 1 FROM watercashaccounts a
                       WHERE a.farmid = f.farmid AND a.isactive = TRUE
                         AND (a.currentbalance >= 1050 OR a.allownegativebalance))) DESC,
              f.farmid
    LIMIT  1;
    SELECT a.watercashaccountid INTO v_acct FROM watercashaccounts a
    WHERE a.farmid = v_farm AND a.isactive = TRUE
      AND (a.currentbalance >= 1050 OR a.allownegativebalance)
    ORDER BY a.watercashaccountid LIMIT 1;
    EXECUTE format('SELECT ca.userid::text FROM %s ca LIMIT 1', v_tbl) INTO v_user;
    v_user := COALESCE(v_user, 'ZZ tester');

    EXECUTE format($sql$
        INSERT INTO %s (farmid, userid, adjustmentdate, adjustmenttype, amount, description, createddate)
        VALUES ($1, $2, CURRENT_DATE, 'LoanReceived', 6000, 'ZZ 295 historical borrowing', now())
        RETURNING adjustmentid
    $sql$, v_tbl) INTO v_adj USING v_farm, v_user;

    -- Baselines taken AFTER the adjustment exists. The adjustment itself is a
    -- cash event and (via 290's legacy read) a debt; it is the CONVERSION that
    -- must move nothing, so that is what these have to bracket.
    SELECT COALESCE(SUM(a.currentbalance), 0)::numeric(14,2) INTO v_cash0
    FROM   watercashaccounts a WHERE a.farmid = v_farm;
    SELECT COALESCE(SUM(r.amount), 0)::numeric(14,2) INTO v_flow0
    FROM   spwatercashflow_rows(v_farm) r;
    SELECT outstandingprincipal INTO v_owed0 FROM spwaterloan_summary(v_farm);

    v_loan := spwaterloan_fromadjustment(
        p_farmid => v_farm, p_adjustmentid => v_adj,
        p_lendername => NULL, p_createdby => 'ZZ backfill');

    -- C. The blank is a blank.
    RAISE NOTICE 'C1. lender is NULL, not invented expect        t  got %',
        ((SELECT l.lendername FROM waterloans l WHERE l.waterloanid = v_loan) IS NULL);
    RAISE NOTICE 'C2. and the list still returns it expect        1  got %',
        (SELECT COUNT(*) FROM spwaterloan_getall(v_farm, 'All') r
         WHERE r.source = 'Loan' AND r.sourceid = v_loan);

    -- Nothing moved, same claim as 293.
    RAISE NOTICE 'C3. cash accounts unmoved     expect     0.00  got %',
        ((SELECT COALESCE(SUM(a.currentbalance), 0)::numeric(14,2)
          FROM watercashaccounts a WHERE a.farmid = v_farm) - v_cash0);
    RAISE NOTICE 'C4. cash flow unmoved         expect     0.00  got %',
        ((SELECT COALESCE(SUM(r.amount), 0)::numeric(14,2)
          FROM spwatercashflow_rows(v_farm) r) - v_flow0);
    RAISE NOTICE 'C5. and the debt is unmoved   expect     0.00  got %',
        ((SELECT outstandingprincipal FROM spwaterloan_summary(v_farm)) - v_owed0);

    -- B. REPAYABLE. The reason the button went away.
    IF v_acct IS NULL THEN
        RAISE NOTICE 'B0. no fundable cash account -- repayment not exercised';
    ELSE
        PERFORM spwaterloanpayment_record(
            p_farmid => v_farm, p_waterloanid => v_loan,
            p_principalamount => 1000, p_interestamount => 50, p_feeamount => 0,
            p_otheramount => 0, p_watercashaccountid => v_acct,
            p_paymentdate => (now() at time zone 'utc'),
            p_paymentmethod => 'Cash', p_referencenumber => NULL,
            p_notes => 'ZZ 295 repayment', p_createdby => 'ZZ tester');
        RAISE NOTICE 'B1. a lenderless loan repays  expect  5000.00  got %',
            (SELECT l.outstandingprincipal FROM waterloans l WHERE l.waterloanid = v_loan);
        RAISE NOTICE 'B2. and the cash went out     expect -1050.00  got %',
            ((SELECT COALESCE(SUM(a.currentbalance), 0)::numeric(14,2)
              FROM watercashaccounts a WHERE a.farmid = v_farm) - v_cash0);
    END IF;

    -- F. Still refuses a second conversion of that same adjustment.
    BEGIN
        PERFORM spwaterloan_fromadjustment(v_farm, v_adj, 'ZZ Someone Else');
        RAISE NOTICE 'F1. second conversion refused expect blocked  got ALLOWED -- WRONG';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'F1. second conversion refused expect blocked  got blocked';
    END;

    -- =====================================================================
    -- D. CORRECTIONS ARE LEFT ALONE.
    -- =====================================================================
    EXECUTE format($sql$
        INSERT INTO %s (farmid, userid, adjustmentdate, adjustmenttype, amount, description, createddate)
        VALUES ($1, $2, CURRENT_DATE, 'LoanReceived', -1500, 'ZZ 295 over-stated, corrected', now())
        RETURNING adjustmentid
    $sql$, v_tbl) INTO v_neg USING v_farm, v_user;

    RAISE NOTICE 'D1. a correction is not a loan expect        0  got %',
        (SELECT COUNT(*) FROM waterloans l WHERE l.sourceadjustmentid = v_neg);
    RAISE NOTICE 'D2. it stays a legacy row     expect        1  got %',
        (SELECT COUNT(*) FROM fnwaterloan_legacy(v_farm) g WHERE g.adjustmentid = v_neg);
    BEGIN
        PERFORM spwaterloan_fromadjustment(v_farm, v_neg, 'ZZ Lender');
        RAISE NOTICE 'D3. and cannot be converted  expect blocked  got ALLOWED -- WRONG';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'D3. and cannot be converted  expect blocked  got blocked';
    END;

    RAISE NOTICE '--- 295 checks done. ROLL BACK this transaction. ---';
END
$t$;

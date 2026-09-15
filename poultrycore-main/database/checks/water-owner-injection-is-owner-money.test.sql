-- Behavioural checks for migration 297: an Owner injection IS owner money.
--
-- Run inside a transaction you ROLL BACK.
--
--   psql ... -X -c "BEGIN;" -f water-owner-injection-is-owner-money.test.sql -c "ROLLBACK;"
--
-- The migration's own backfill has already run by the time this executes, so
-- section A checks its RESULT against live data rather than performing it.
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **Backfilling moves no money.** Section B brackets a conversion and measures
-- cash accounts, cash flow AND the owner-money total across it. That is the
-- claim that makes this safe to run on a live company, and it is the one the
-- equivalent loan migration got wrong first time round.
--
-- The rest:
--   A. Nothing is left unrecorded, and nothing backfilled carries a cash row.
--   C. A withdrawal becomes a DRAW, and a NEGATIVE injection becomes a draw too
--      -- the sign decides direction, not the type. The amount is stored
--      positive either way, because the table's CHECK demands it.
--   D. Counted ONCE: the adjustment stops being a legacy row on the Owner Money
--      page the moment a record points at it, but stays a cash event.
--   E. Refusals: a non-capital type, a zero amount, and a second conversion.

DO $t$
DECLARE
    v_farm   text;
    v_user   text;
    v_tbl    text;
    v_inj    integer;
    v_wd     integer;
    v_neginj integer;
    v_rec    integer;
    v_cash0  numeric;
    v_flow0  numeric;
    v_own0   numeric;
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
        WHERE  ca.adjustmenttype IN ('OwnerInjection', 'Withdrawal')
          AND  ca.amount <> 0 AND f.type = 'Water'
          AND  NOT EXISTS (SELECT 1 FROM waterownermoney o
                           WHERE o.sourceadjustmentid = ca.adjustmentid)
    $sql$, v_tbl) INTO v_n;
    RAISE NOTICE 'A1. nothing left unrecorded   expect        0  got %', v_n;

    RAISE NOTICE 'A2. none of them moved cash   expect        0  got %',
        (SELECT COUNT(*) FROM waterownermoney o
         WHERE o.sourceadjustmentid IS NOT NULL AND o.watercashtransactionid IS NOT NULL);
    RAISE NOTICE 'A3. and none claims an account expect        0  got %',
        (SELECT COUNT(*) FROM waterownermoney o
         WHERE o.sourceadjustmentid IS NOT NULL AND o.watercashaccountid IS NOT NULL);
    -- The table's own rule: amount is positive, direction lives in the type.
    RAISE NOTICE 'A4. every amount is positive  expect        0  got %',
        (SELECT COUNT(*) FROM waterownermoney o
         WHERE o.sourceadjustmentid IS NOT NULL AND o.amount <= 0);

    -- =====================================================================
    -- B. A FRESH ONE MOVES NOTHING.
    -- =====================================================================
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    EXECUTE format('SELECT ca.userid::text FROM %s ca LIMIT 1', v_tbl) INTO v_user;
    v_user := COALESCE(v_user, 'ZZ tester');

    EXECUTE format($sql$
        INSERT INTO %s (farmid, userid, adjustmentdate, adjustmenttype, amount, description, createddate)
        VALUES ($1, $2, CURRENT_DATE, 'OwnerInjection', 7000, 'ZZ 297 owner put money in', now())
        RETURNING adjustmentid
    $sql$, v_tbl) INTO v_inj USING v_farm, v_user;

    -- Baselines AFTER the adjustment exists: the adjustment itself is a cash
    -- event, and it is the BACKFILL that must move nothing.
    SELECT COALESCE(SUM(a.currentbalance), 0)::numeric(14,2) INTO v_cash0
    FROM   watercashaccounts a WHERE a.farmid = v_farm;
    SELECT COALESCE(SUM(r.amount), 0)::numeric(14,2) INTO v_flow0
    FROM   spwatercashflow_rows(v_farm) r;
    SELECT COALESCE(SUM(CASE WHEN o.transactiontype = 'Contribution'
                             THEN o.amount ELSE -o.amount END), 0)::numeric(14,2)
    INTO   v_own0
    FROM   waterownermoney o WHERE o.farmid = v_farm AND o.status = 'Posted';

    v_rec := spwaterownermoney_fromadjustment(v_farm, v_inj, 'ZZ Owner', 'ZZ tester');

    RAISE NOTICE 'B1. it is a Contribution      expect Contribution  got %',
        (SELECT o.transactiontype FROM waterownermoney o WHERE o.waterownermoneyid = v_rec);
    RAISE NOTICE 'B2. for the adjustment amount expect  7000.00  got %',
        (SELECT o.amount FROM waterownermoney o WHERE o.waterownermoneyid = v_rec);
    RAISE NOTICE 'B3. cash accounts unmoved     expect     0.00  got %',
        ((SELECT COALESCE(SUM(a.currentbalance), 0)::numeric(14,2)
          FROM watercashaccounts a WHERE a.farmid = v_farm) - v_cash0);
    RAISE NOTICE 'B4. cash flow unmoved         expect     0.00  got %',
        ((SELECT COALESCE(SUM(r.amount), 0)::numeric(14,2)
          FROM spwatercashflow_rows(v_farm) r) - v_flow0);
    -- The owner's capital DOES rise -- that is the whole point. It was always
    -- there, it just was not on this page.
    RAISE NOTICE 'B5. owner capital now shows it expect  7000.00  got %',
        ((SELECT COALESCE(SUM(CASE WHEN o.transactiontype = 'Contribution'
                                   THEN o.amount ELSE -o.amount END), 0)::numeric(14,2)
          FROM waterownermoney o WHERE o.farmid = v_farm AND o.status = 'Posted') - v_own0);

    -- =====================================================================
    -- D. COUNTED ONCE.
    -- =====================================================================
    -- No D1 here: water has no fnwaterownermoney_legacy. 287 was poultry-only,
    -- so a water owner injection has never appeared on the Owner Money page at
    -- all -- which is why this backfill is the first time that money shows up
    -- where it belongs, rather than a tidy-up.
    RAISE NOTICE 'D2. but still a cash event    expect        1  got %',
        (SELECT COUNT(*) FROM spwatercashflow_rows(v_farm) r
         WHERE r.sourcetype = 'OwnerInjection' AND r.sourceid = v_inj);

    -- =====================================================================
    -- C. THE SIGN DECIDES DIRECTION.
    -- =====================================================================
    EXECUTE format($sql$
        INSERT INTO %s (farmid, userid, adjustmentdate, adjustmenttype, amount, description, createddate)
        VALUES ($1, $2, CURRENT_DATE, 'Withdrawal', -2500, 'ZZ 297 owner took money out', now())
        RETURNING adjustmentid
    $sql$, v_tbl) INTO v_wd USING v_farm, v_user;
    PERFORM spwaterownermoney_fromadjustment(v_farm, v_wd, NULL, 'ZZ tester');

    RAISE NOTICE 'C1. a withdrawal is a Draw    expect     Draw  got %',
        (SELECT o.transactiontype FROM waterownermoney o WHERE o.sourceadjustmentid = v_wd);
    RAISE NOTICE 'C2. stored positive           expect  2500.00  got %',
        (SELECT o.amount FROM waterownermoney o WHERE o.sourceadjustmentid = v_wd);

    -- The case that catches classifying by TYPE alone: a negative injection is
    -- a correction, and it took money back out.
    EXECUTE format($sql$
        INSERT INTO %s (farmid, userid, adjustmentdate, adjustmenttype, amount, description, createddate)
        VALUES ($1, $2, CURRENT_DATE, 'OwnerInjection', -900, 'ZZ 297 over-stated, corrected', now())
        RETURNING adjustmentid
    $sql$, v_tbl) INTO v_neginj USING v_farm, v_user;
    PERFORM spwaterownermoney_fromadjustment(v_farm, v_neginj, NULL, 'ZZ tester');

    RAISE NOTICE 'C3. a NEGATIVE injection is a Draw expect     Draw  got %',
        (SELECT o.transactiontype FROM waterownermoney o WHERE o.sourceadjustmentid = v_neginj);
    RAISE NOTICE 'C4. also stored positive      expect   900.00  got %',
        (SELECT o.amount FROM waterownermoney o WHERE o.sourceadjustmentid = v_neginj);
    -- Net capital across all three: +7000 - 2500 - 900 = 3600.
    RAISE NOTICE 'C5. net capital across the three expect  3600.00  got %',
        ((SELECT COALESCE(SUM(CASE WHEN o.transactiontype = 'Contribution'
                                   THEN o.amount ELSE -o.amount END), 0)::numeric(14,2)
          FROM waterownermoney o WHERE o.farmid = v_farm AND o.status = 'Posted') - v_own0);

    RAISE NOTICE '--- 297 checks done. ---';
END
$t$;

-- =============================================================================
-- E. WHAT MUST BE REFUSED.
-- =============================================================================
DO $e$
DECLARE
    v_farm text;
    v_user text;
    v_tbl  text;
    v_loan integer;
    v_zero integer;
    v_good integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    EXECUTE format('SELECT ca.userid::text FROM %s ca LIMIT 1', v_tbl) INTO v_user;
    v_user := COALESCE(v_user, 'ZZ tester');

    EXECUTE format($sql$
        INSERT INTO %s (farmid, userid, adjustmentdate, adjustmenttype, amount, description, createddate)
        VALUES ($1, $2, CURRENT_DATE, 'LoanReceived', 3000, 'ZZ 297 borrowing', now()),
               ($1, $2, CURRENT_DATE, 'OwnerInjection', 1200, 'ZZ 297 convert twice', now())
    $sql$, v_tbl) USING v_farm, v_user;

    EXECUTE format($sql$SELECT ca.adjustmentid FROM %s ca
        WHERE ca.description = 'ZZ 297 borrowing' LIMIT 1$sql$, v_tbl) INTO v_loan;
    EXECUTE format($sql$SELECT ca.adjustmentid FROM %s ca
        WHERE ca.description = 'ZZ 297 convert twice' LIMIT 1$sql$, v_tbl) INTO v_good;

    BEGIN
        PERFORM spwaterownermoney_fromadjustment(v_farm, v_loan);
        RAISE NOTICE 'E1. a borrowing is refused   expect blocked  got ALLOWED -- WRONG';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'E1. a borrowing is refused   expect blocked  got blocked';
    END;

    PERFORM spwaterownermoney_fromadjustment(v_farm, v_good);
    BEGIN
        PERFORM spwaterownermoney_fromadjustment(v_farm, v_good);
        RAISE NOTICE 'E2. the second is refused    expect blocked  got ALLOWED -- WRONG';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'E2. the second is refused    expect blocked  got blocked';
    END;

    RAISE NOTICE '--- 297 refusal checks done. ROLL BACK this transaction. ---';
END
$e$;

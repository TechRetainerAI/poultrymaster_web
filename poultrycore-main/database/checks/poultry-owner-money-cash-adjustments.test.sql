-- Behavioural checks for migration 287: Owner Money reads the Cash page's
-- owner injections.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it writes cash adjustments and owner money.
--
--   psql ... -X -c "BEGIN;" -f poultry-owner-money-cash-adjustments.test.sql -c "ROLLBACK;"
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **An injection recorded on the Cash page appears on Owner Money, and is
-- counted exactly once everywhere.** The failure this file is really guarding
-- against is double counting: Cash Flow already reads cashadjustment, so if 287
-- had copied those rows into poultryownermoney instead of reading across, the
-- same 20,000 would appear twice in the financing section. Section C asserts
-- Cash Flow did not move at all.
--
-- The rest:
--   1. Only OwnerInjection and Withdrawal count. LoanReceived belongs to the
--      Loans module, OpeningBalance is a starting position and Correction is a
--      bookkeeping fix -- none of them is owner funding.
--   2. The SIGN decides the direction, not the type, matching how
--      sppoultrycashflow_rows already reads the same table.
--   3. Legacy rows are marked so the page can hide Reverse, and they never
--      collide with a real owner-money id.
--   4. The list and the cards agree about the legacy set.
--   5. Filters -- type, status and date -- apply to legacy rows too.

DO $t$
DECLARE
    v_farm   text;
    v_acct   integer;
    v_own    integer;
    v_flow0  numeric;
    v_flow1  numeric;
    v_r      record;
    v_id     integer;
BEGIN
    -- A farm WITH an active cash account is preferred, so section D can record a
    -- real owner-money row and prove the two sources sit side by side. Falling
    -- back to any poultry farm keeps the rest of the file runnable on a database
    -- where no farm has one.
    SELECT f.farmid INTO v_farm
    FROM   farms f
    WHERE  f.type = 'Poultry'
      AND  f.farmid ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ORDER  BY EXISTS (SELECT 1 FROM poultrycashaccounts a
                       WHERE a.farmid = f.farmid AND a.isactive) DESC,
              f.farmid
    LIMIT  1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No uuid-shaped poultry company to test against.'; END IF;
    RAISE NOTICE '   using poultry farm %', v_farm;

    -- Clear the decks so the counts below are about what this file writes.
    DELETE FROM cashadjustment WHERE lower(farmid::text) = lower(v_farm);
    DELETE FROM poultryownermoney WHERE farmid = v_farm;

    -- What Cash Flow says before anything is recorded.
    SELECT COALESCE(SUM(r.amount), 0) INTO v_flow0
    FROM   sppoultrycashflow_rows(v_farm, NULL, NULL) r;

    -- =====================================================================
    -- A. THE CLAIM. An injection typed on the Cash page reaches Owner Money.
    -- =====================================================================
    INSERT INTO cashadjustment (userid, farmid, adjustmentdate, adjustmenttype, amount, description, createddate)
    VALUES ('ZZ tester', v_farm, (now() at time zone 'utc'), 'OwnerInjection', 20000, 'ZZ owner put in 20k', (now() at time zone 'utc'))
    RETURNING adjustmentid INTO v_id;

    RAISE NOTICE 'A1. the injection is listed  expect        1  got %',
        (SELECT COUNT(*)::integer FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, NULL)
          WHERE source = 'CashAdjustment');
    RAISE NOTICE 'A2. as a contribution       expect Contribution  got %',
        (SELECT transactiontype FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, NULL)
          WHERE source = 'CashAdjustment');
    RAISE NOTICE 'A3. for the right amount    expect 20000.00  got %',
        (SELECT amount FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, NULL)
          WHERE source = 'CashAdjustment');
    RAISE NOTICE 'A4. and the cards count it  expect 20000.00  got %',
        (SELECT totalcontributions FROM sppoultryownermoney_summary(v_farm, NULL, NULL));
    RAISE NOTICE 'A5. net funding follows     expect 20000.00  got %',
        (SELECT netfunding FROM sppoultryownermoney_summary(v_farm, NULL, NULL));
    -- The page needs to know it cannot reverse this one.
    RAISE NOTICE 'A6. marked as from the Cash page expect CashAdjustment  got %',
        (SELECT source FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, NULL)
          WHERE sourceid = v_id);
    -- 0, never the adjustment id: the two id spaces overlap and the page keys on
    -- this column.
    RAISE NOTICE 'A7. carries no owner-money id expect        0  got %',
        (SELECT poultryownermoneyid FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, NULL)
          WHERE source = 'CashAdjustment');
    RAISE NOTICE 'A8. the cards say how many are legacy expect        1  got %',
        (SELECT legacycount FROM sppoultryownermoney_summary(v_farm, NULL, NULL));

    -- =====================================================================
    -- B. Only the two owner types count.
    -- =====================================================================
    INSERT INTO cashadjustment (userid, farmid, adjustmentdate, adjustmenttype, amount, description, createddate)
    VALUES ('ZZ tester', v_farm, (now() at time zone 'utc'), 'LoanReceived',   50000, 'ZZ borrowed',    (now() at time zone 'utc')),
           ('ZZ tester', v_farm, (now() at time zone 'utc'), 'OpeningBalance', 90000, 'ZZ opening',     (now() at time zone 'utc')),
           ('ZZ tester', v_farm, (now() at time zone 'utc'), 'Correction',       300, 'ZZ fix',         (now() at time zone 'utc'));

    -- Still just the one injection: borrowed money is the Loans module's, an
    -- opening balance is a starting position, a correction is bookkeeping.
    RAISE NOTICE 'B1. loan/opening/correction ignored expect        1  got %',
        (SELECT COUNT(*)::integer FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, NULL)
          WHERE source = 'CashAdjustment');
    RAISE NOTICE 'B2. and the total is unchanged expect 20000.00  got %',
        (SELECT totalcontributions FROM sppoultryownermoney_summary(v_farm, NULL, NULL));

    -- A withdrawal is an owner draw, and the SIGN says which way it went.
    INSERT INTO cashadjustment (userid, farmid, adjustmentdate, adjustmenttype, amount, description, createddate)
    VALUES ('ZZ tester', v_farm, (now() at time zone 'utc'), 'Withdrawal', -5000, 'ZZ owner took out', (now() at time zone 'utc'));

    RAISE NOTICE 'B3. a withdrawal is a draw  expect     Draw  got %',
        (SELECT transactiontype FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, NULL)
          WHERE notes = 'ZZ owner took out');
    -- Stored positive with the direction in the type, exactly as 253 stores its
    -- own rows -- a signed amount AND a type is two sources of truth.
    RAISE NOTICE 'B4. amount is positive      expect  5000.00  got %',
        (SELECT amount FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, NULL)
          WHERE notes = 'ZZ owner took out');
    RAISE NOTICE 'B5. draws total             expect  5000.00  got %',
        (SELECT totaldraws FROM sppoultryownermoney_summary(v_farm, NULL, NULL));
    RAISE NOTICE 'B6. net funding is the difference expect 15000.00  got %',
        (SELECT netfunding FROM sppoultryownermoney_summary(v_farm, NULL, NULL));

    -- A negative OwnerInjection is a correction to one, and the sign must win.
    -- Classifying by type alone would report this as money going IN.
    INSERT INTO cashadjustment (userid, farmid, adjustmentdate, adjustmenttype, amount, description, createddate)
    VALUES ('ZZ tester', v_farm, (now() at time zone 'utc'), 'OwnerInjection', -2000, 'ZZ injection reversed', (now() at time zone 'utc'));
    RAISE NOTICE 'B7. a negative injection is a draw expect     Draw  got %',
        (SELECT transactiontype FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, NULL)
          WHERE notes = 'ZZ injection reversed');
    RAISE NOTICE 'B8. and net funding drops   expect 13000.00  got %',
        (SELECT netfunding FROM sppoultryownermoney_summary(v_farm, NULL, NULL));

    -- =====================================================================
    -- C. CASH FLOW DID NOT MOVE. The double-counting guard.
    -- =====================================================================
    -- 287 reads across; it copies nothing. Cash Flow reads cashadjustment
    -- itself, so if the rows had been duplicated into poultryownermoney they
    -- would now be counted twice in the financing section.
    RAISE NOTICE 'C1. nothing copied into the capital record expect        0  got %',
        (SELECT COUNT(*)::integer FROM poultryownermoney WHERE farmid = v_farm);
    RAISE NOTICE 'C2. each adjustment appears once in Cash Flow expect        0  got %',
        (SELECT COUNT(*)::integer FROM (
            SELECT r.sourceid, COUNT(*) AS n
            FROM   sppoultrycashflow_rows(v_farm, NULL, NULL) r
            WHERE  r.sourcetype = 'Adjustment'
            GROUP  BY r.sourceid HAVING COUNT(*) > 1) d);

    -- =====================================================================
    -- D. A real owner-money record still behaves exactly as before.
    -- =====================================================================
    SELECT a.poultrycashaccountid INTO v_acct
    FROM   poultrycashaccounts a WHERE a.farmid = v_farm AND a.isactive ORDER BY 1 LIMIT 1;

    IF v_acct IS NULL THEN
        RAISE NOTICE 'D. skipped: this company has no active cash account';
    ELSE
        -- Named arguments: the positional list is eleven long and easy to slip a
        -- NULL in, which would silently land the creator in p_notes.
        v_own := sppoultryownermoney_record(
                     p_farmid               => v_farm,
                     p_transactiontype      => 'Contribution',
                     p_amount               => 7000,
                     p_poultrycashaccountid => v_acct,
                     p_createdby            => 'ZZ tester');
        RAISE NOTICE 'D1. the real record is listed too expect        1  got %',
            (SELECT COUNT(*)::integer FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, NULL)
              WHERE source = 'OwnerMoney');
        RAISE NOTICE 'D2. and keeps its own id   expect        t  got %',
            (SELECT poultryownermoneyid = sourceid FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, NULL)
              WHERE source = 'OwnerMoney');
        RAISE NOTICE 'D3. both sources are counted together expect 27000.00  got %',
            (SELECT totalcontributions FROM sppoultryownermoney_summary(v_farm, NULL, NULL));
    END IF;

    -- =====================================================================
    -- E. Filters reach the legacy rows too.
    -- =====================================================================
    RAISE NOTICE 'E1. type filter applies    expect        2  got %',
        (SELECT COUNT(*)::integer FROM sppoultryownermoney_getall(v_farm, 'Draw', NULL, NULL, NULL));
    -- A cashadjustment has no reversal state, so filtering to Reversed must
    -- return none of them.
    RAISE NOTICE 'E2. Reversed excludes legacy rows expect        0  got %',
        (SELECT COUNT(*)::integer FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, 'Reversed')
          WHERE source = 'CashAdjustment');
    -- Three legacy rows reach the page: the 20,000 injection, the 5,000
    -- withdrawal and the -2,000 correction. The loan, opening balance and
    -- correction adjustments are not owner money and never appear.
    RAISE NOTICE 'E3. Posted includes them   expect        3  got %',
        (SELECT COUNT(*)::integer FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, 'Posted')
          WHERE source = 'CashAdjustment');
    -- Dated before everything written here.
    RAISE NOTICE 'E4. date filter applies    expect        0  got %',
        (SELECT COUNT(*)::integer FROM sppoultryownermoney_getall(
            v_farm, NULL, NULL, (CURRENT_DATE - 30)::date, NULL)
          WHERE source = 'CashAdjustment');

    -- =====================================================================
    -- F. The list and the cards agree.
    -- =====================================================================
    SELECT * INTO v_r FROM sppoultryownermoney_summary(v_farm, NULL, NULL);
    RAISE NOTICE 'F1. legacy count matches the list expect        t  got %',
        (v_r.legacycount = (SELECT COUNT(*)::int FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, NULL)
                             WHERE source = 'CashAdjustment'));
    RAISE NOTICE 'F2. legacy net is stated separately expect 13000.00  got %', v_r.legacynet;
END
$t$;

-- =============================================================================
-- Negative cases. Each must be BLOCKED.
-- =============================================================================
DO $n$
DECLARE
    v_farm text;
    v_id   integer;
BEGIN
    -- The SAME farm the block above used, or this looks at a company with no
    -- legacy rows and skips the one case it exists to test.
    SELECT f.farmid INTO v_farm
    FROM   farms f WHERE f.type = 'Poultry'
      AND  f.farmid ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ORDER  BY EXISTS (SELECT 1 FROM poultrycashaccounts a
                       WHERE a.farmid = f.farmid AND a.isactive) DESC,
              f.farmid
    LIMIT  1;

    SELECT sourceid INTO v_id FROM sppoultryownermoney_getall(v_farm, NULL, NULL, NULL, NULL)
     WHERE source = 'CashAdjustment' LIMIT 1;

    -- A legacy row is the Cash page's to edit or delete. Reversing it from here
    -- would write a cash row that page knows nothing about. The id is not an
    -- owner-money id at all, so the reversal must not find anything to act on.
    IF v_id IS NULL THEN
        RAISE NOTICE 'N1. reversing a Cash-page row skipped: no legacy rows';
    ELSE
        BEGIN
            PERFORM sppoultryownermoney_reverse(
                        p_poultryownermoneyid => v_id,
                        p_farmid              => v_farm,
                        p_reason              => 'ZZ should not work',
                        p_reversedby          => 'ZZ tester');
            RAISE NOTICE 'N1. reversing a Cash-page row <-- BUG, allowed';
        EXCEPTION WHEN others THEN
            RAISE NOTICE 'N1. reversing a Cash-page row blocked: %', SQLERRM;
        END;
    END IF;
END
$n$;

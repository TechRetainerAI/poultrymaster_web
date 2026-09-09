-- Behavioural checks for migration 284: water asset depreciation.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates a cash account, assets and charges.
--
--   psql ... -X -c "BEGIN;" -f water-asset-depreciation.test.sql -c "ROLLBACK;"
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **Depreciation changes profit and moves no money.** Section B charges a month
-- and asserts the four things that have to be simultaneously true: the P&L cost
-- went up, the cash account did not move, no cash transaction was written, and
-- nobody is owed anything. Any one of those failing means depreciation has
-- turned into a bill, and a bill is the one thing it must never be.
--
-- The rest:
--   1. Generate is idempotent. Pressing it twice charges nothing the second
--      time -- 283's unique index is the guarantee, not the caller's care.
--   2. The preview and the button agree. _due must promise exactly what
--      _generate then does, or the number an owner approved is not the number
--      they got.
--   3. The schedule is exactly usefullifemonths long and lands EXACTLY on the
--      depreciable amount, rounding remainder included. This is the check that
--      catches an asset depreciating over four months on a three-month life.
--   4. Book value never falls below residual value.
--   5. Reversal is append-only and reopens a FullyDepreciated asset.
--   6. A reversed month is NOT reopened to the generator, or the reverse button
--      would undo itself on the next run.
--   7. Draft, Disposed and Reversed assets are never charged.

DO $t$
DECLARE
    v_farm  text;
    v_acct  integer;
    v_a12   integer;   -- 12,000 over 12 months, in service a year ago
    v_a3    integer;   -- 1,000 over 3 months -- the rounding case
    v_draft integer;   -- no life, never charged
    v_bal0  numeric; v_bal1 numeric;
    v_pl0   numeric; v_pl1 numeric;
    v_due   record;
    v_gen   record;
    v_r     record;
    v_entry integer;
BEGIN
    SELECT f.farmid INTO v_farm
    FROM   farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No water company to test against.'; END IF;
    RAISE NOTICE '   using water company %', v_farm;

    INSERT INTO watercashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, isactive)
    VALUES (v_farm, 'ZZ Depreciation Account', 'Bank', 500000, 500000, TRUE)
    RETURNING watercashaccountid INTO v_acct;

    -- 12,000 over 12 months = a clean 1,000 a month, in service 12 months ago.
    v_a12 := spwatercapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Filler Machine',
        p_acquisitiondate  => (CURRENT_DATE - interval '12 months')::date,
        p_inservicedate    => (CURRENT_DATE - interval '12 months')::date,
        p_amount => 12000, p_residualvalue => 0, p_usefullifemonths => 12,
        p_paymentmethod => 'Cash', p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    -- 1,000 over 3 months = 333.33 a month, and 3 x 333.33 is 999.99. The final
    -- month has to absorb the pesewa or the asset never finishes.
    v_a3 := spwatercapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ UV Lamp',
        p_acquisitiondate  => (CURRENT_DATE - interval '6 months')::date,
        p_inservicedate    => (CURRENT_DATE - interval '6 months')::date,
        p_amount => 1000, p_residualvalue => 0, p_usefullifemonths => 3,
        p_paymentmethod => 'Cash', p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    -- No life set: a half-drilled borehole is never charged.
    v_draft := spwatercapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Half Borehole',
        p_acquisitiondate => CURRENT_DATE, p_amount => 50000,
        p_paymentmethod => 'Cash', p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    -- =====================================================================
    -- A. The preview promises what the button delivers.
    -- =====================================================================
    SELECT * INTO v_due FROM spwaterassetdepreciation_due(v_farm, CURRENT_DATE)
     WHERE watercapitalassetid = v_a12;
    RAISE NOTICE 'A1. 12 months are due      expect       12  got %', v_due.monthsdue;
    RAISE NOTICE 'A2. worth 12000            expect 12000.00  got %', v_due.amountdue;
    RAISE NOTICE 'A3. monthly is 1000        expect  1000.00  got %', v_due.monthlydepreciation;
    -- A Draft asset must not appear in the preview at all.
    RAISE NOTICE 'A4. the draft is not due   expect        f  got %',
        EXISTS (SELECT 1 FROM spwaterassetdepreciation_due(v_farm, CURRENT_DATE)
                 WHERE watercapitalassetid = v_draft);

    -- =====================================================================
    -- B. THE CLAIM. Charging changes profit and moves no money.
    -- =====================================================================
    SELECT currentbalance INTO v_bal0 FROM watercashaccounts WHERE watercashaccountid = v_acct;
    SELECT COALESCE(SUM(r.amount), 0) INTO v_pl0 FROM fnwaterexpenserows(v_farm) r
     WHERE r.plline = 'Depreciation';

    SELECT * INTO v_gen FROM spwaterassetdepreciation_generate(v_farm, CURRENT_DATE, v_a12, 'ZZ tester');

    SELECT currentbalance INTO v_bal1 FROM watercashaccounts WHERE watercashaccountid = v_acct;
    SELECT COALESCE(SUM(r.amount), 0) INTO v_pl1 FROM fnwaterexpenserows(v_farm) r
     WHERE r.plline = 'Depreciation';

    RAISE NOTICE 'B1. generate matched the preview expect 12000.00  got %', v_gen.totalamount;
    RAISE NOTICE 'B2. profit was charged     expect 12000.00  got %', (v_pl1 - v_pl0);
    RAISE NOTICE 'B3. cash did NOT move      expect     0.00  got %', (v_bal0 - v_bal1);
    RAISE NOTICE 'B4. no cash transaction    expect        0  got %',
        (SELECT COUNT(*)::integer FROM watercashtransactions t
          WHERE t.farmid = v_farm AND t.sourcetype = 'AssetDepreciation');
    RAISE NOTICE 'B5. nobody is owed         expect        0  got %',
        (SELECT COUNT(*)::integer FROM fnwaterpayables(v_farm) p
          JOIN waterexpenses e ON e.waterexpenseid = p.documentid
         WHERE p.documenttype = 'Expense' AND e.sourcetype = 'AssetDepreciation');
    -- The NonCash marker is what every other reader keys off.
    RAISE NOTICE 'B6. marked NonCash         expect  NonCash  got %',
        (SELECT r.paymentmethod FROM fnwaterexpenserows(v_farm) r
          WHERE r.sourcetype = 'AssetDepreciation' LIMIT 1);
    RAISE NOTICE 'B7. classified NonCashExpense expect NonCashExpense  got %',
        (SELECT r.financialcosttype FROM fnwaterexpenserows(v_farm) r
          WHERE r.sourcetype = 'AssetDepreciation' LIMIT 1);
    -- Depreciation belongs under Other Costs, NOT above Gross Profit.
    RAISE NOTICE 'B8. sits in OtherCost      expect OtherCost  got %',
        (SELECT r.plsection FROM fnwaterexpenserows(v_farm) r
          WHERE r.sourcetype = 'AssetDepreciation' LIMIT 1);

    -- =====================================================================
    -- C. Generate is idempotent.
    -- =====================================================================
    SELECT * INTO v_gen FROM spwaterassetdepreciation_generate(v_farm, CURRENT_DATE, v_a12, 'ZZ tester');
    RAISE NOTICE 'C1. a second run charges nothing expect     0.00  got %', v_gen.totalamount;
    RAISE NOTICE 'C2. and creates no entries expect        0  got %', v_gen.entriescreated;
    RAISE NOTICE 'C3. still exactly 12 rows  expect       12  got %',
        (SELECT COUNT(*)::integer FROM waterassetdepreciation
          WHERE watercapitalassetid = v_a12 AND sourcetype = 'Scheduled');

    -- =====================================================================
    -- D. The life is a bound, and the last month absorbs the rounding.
    -- =====================================================================
    PERFORM spwaterassetdepreciation_generate(v_farm, CURRENT_DATE, v_a3, 'ZZ tester');

    RAISE NOTICE 'D1. exactly 3 charges      expect        3  got %',
        (SELECT COUNT(*)::integer FROM waterassetdepreciation
          WHERE watercapitalassetid = v_a3 AND sourcetype = 'Scheduled');
    -- 333.33 + 333.33 + 333.34. Anything else leaves the asset unfinishable.
    RAISE NOTICE 'D2. and they total exactly 1000 expect  1000.00  got %',
        fnwatercapitalasset_accumulated(v_a3);

    SELECT * INTO v_r FROM fnwatercapitalasset_financials(v_a3);
    RAISE NOTICE 'D3. nothing left to charge expect     0.00  got %', v_r.remainingdepreciable;
    RAISE NOTICE 'D4. fully depreciated      expect        t  got %', v_r.isfullydepreciated;
    RAISE NOTICE 'D5. status followed        expect FullyDepreciated  got %',
        (SELECT status FROM watercapitalassets WHERE watercapitalassetid = v_a3);
    -- Six months have passed on a three-month life; the bound must have held.
    RAISE NOTICE 'D6. no fourth month appeared expect        0  got %',
        (SELECT COUNT(*)::integer FROM spwaterassetdepreciation_due(v_farm, CURRENT_DATE)
          WHERE watercapitalassetid = v_a3);

    -- =====================================================================
    -- E. Book value never falls below residual value.
    -- =====================================================================
    SELECT * INTO v_r FROM fnwatercapitalasset_financials(v_a12);
    RAISE NOTICE 'E1. book value at the floor expect     0.00  got %', v_r.currentbookvalue;
    RAISE NOTICE 'E2. and never below it    expect        t  got %',
        (SELECT BOOL_AND(f.currentbookvalue >= f.residualvalue)
           FROM watercapitalassets a
           CROSS JOIN LATERAL fnwatercapitalasset_financials(a.watercapitalassetid) f
          WHERE a.farmid = v_farm);

    -- =====================================================================
    -- F. Reversal is append-only and reopens the asset.
    -- =====================================================================
    SELECT waterassetdepreciationid INTO v_entry FROM waterassetdepreciation
     WHERE watercapitalassetid = v_a12 AND sourcetype = 'Scheduled'
     ORDER BY periodstart DESC LIMIT 1;

    SELECT currentbalance INTO v_bal0 FROM watercashaccounts WHERE watercashaccountid = v_acct;
    PERFORM spwaterassetdepreciation_reverse(v_farm, v_entry, 'Charged in error', 'ZZ tester');
    SELECT currentbalance INTO v_bal1 FROM watercashaccounts WHERE watercashaccountid = v_acct;

    RAISE NOTICE 'F1. the original is kept   expect Reversed  got %',
        (SELECT status FROM waterassetdepreciation WHERE waterassetdepreciationid = v_entry);
    RAISE NOTICE 'F2. an opposite row appeared expect        1  got %',
        (SELECT COUNT(*)::integer FROM waterassetdepreciation
          WHERE reversalofid = v_entry AND amount < 0);
    RAISE NOTICE 'F3. accumulated fell by 1000 expect 11000.00  got %',
        fnwatercapitalasset_accumulated(v_a12);
    -- Reversing depreciation does not put money back in the bank either.
    RAISE NOTICE 'F4. cash still did not move expect     0.00  got %', (v_bal1 - v_bal0);
    RAISE NOTICE 'F5. the asset reopened     expect   Active  got %',
        (SELECT status FROM watercapitalassets WHERE watercapitalassetid = v_a12);

    -- =====================================================================
    -- G. A reversed month is NOT reopened to the generator.
    -- =====================================================================
    -- If it were, the next Generate would silently put the charge straight back
    -- and the reverse button would do nothing at all.
    SELECT * INTO v_gen FROM spwaterassetdepreciation_generate(v_farm, CURRENT_DATE, v_a12, 'ZZ tester');
    RAISE NOTICE 'G1. generate did not re-charge it expect     0.00  got %', v_gen.totalamount;
    RAISE NOTICE 'G2. accumulated is unchanged expect 11000.00  got %',
        fnwatercapitalasset_accumulated(v_a12);

    -- The way back is an explicit adjustment, labelled as a human decision.
    PERFORM spwaterassetdepreciation_adjust(v_farm, v_a12,
        (CURRENT_DATE - interval '1 month')::date, 1000, 'Re-charging after review', 'ZZ tester');
    RAISE NOTICE 'G3. an adjustment restores it expect 12000.00  got %',
        fnwatercapitalasset_accumulated(v_a12);
    RAISE NOTICE 'G4. and is labelled Manual expect ManualAdjustment  got %',
        (SELECT sourcetype FROM waterassetdepreciation
          WHERE watercapitalassetid = v_a12 ORDER BY waterassetdepreciationid DESC LIMIT 1);

    -- =====================================================================
    -- H. Draft assets are never charged.
    -- =====================================================================
    RAISE NOTICE 'H1. the draft has no charges expect        0  got %',
        (SELECT COUNT(*)::integer FROM waterassetdepreciation WHERE watercapitalassetid = v_draft);
    RAISE NOTICE 'H2. and its book value is its cost expect 50000.00  got %',
        (SELECT currentbookvalue FROM fnwatercapitalasset_financials(v_draft));

    -- =====================================================================
    -- I. The history reads like a statement.
    -- =====================================================================
    RAISE NOTICE 'I1. running book value never rises above cost expect        t  got %',
        (SELECT BOOL_AND(h.bookvalueafter <= h.originalcost)
           FROM spwaterassetdepreciation_getall(v_farm, v_a12, NULL, NULL) h);
END
$t$;

-- =============================================================================
-- Negative cases. Each must be BLOCKED.
-- =============================================================================
DO $n$
DECLARE
    v_farm  text;
    v_a12   integer;
    v_a3    integer;
    v_draft integer;
    v_entry integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    SELECT watercapitalassetid INTO v_a12   FROM watercapitalassets WHERE farmid = v_farm AND assetname = 'ZZ Filler Machine';
    SELECT watercapitalassetid INTO v_a3    FROM watercapitalassets WHERE farmid = v_farm AND assetname = 'ZZ UV Lamp';
    SELECT watercapitalassetid INTO v_draft FROM watercapitalassets WHERE farmid = v_farm AND assetname = 'ZZ Half Borehole';

    -- Adding cost after depreciation has run would invalidate every month
    -- already charged.
    BEGIN
        PERFORM spwatercapitalassetcost_add(v_farm, v_a12, CURRENT_DATE, 'Extra', 'Materials', 500,
                                            NULL, 'Cash', NULL, NULL, NULL, NULL, 'ZZ tester');
        RAISE NOTICE 'N1. cost added after depreciation <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N1. cost added after depreciation blocked: %', SQLERRM;
    END;

    -- Changing the useful life retroactively, likewise.
    BEGIN
        PERFORM spwatercapitalasset_update(
            v_farm, v_a12, 'ZZ Filler Machine', NULL, NULL, NULL, NULL, NULL,
            CURRENT_DATE, 60, 0, TRUE, 'ZZ tester');
        RAISE NOTICE 'N2. life changed after depreciation <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N2. life changed after depreciation blocked: %', SQLERRM;
    END;

    -- Reversing the asset while its depreciation stands would strand the ledger.
    BEGIN
        PERFORM spwatercapitalasset_reverse(v_farm, v_a12, 'Nope', 'ZZ tester');
        RAISE NOTICE 'N3. asset reversed under depreciation <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N3. asset reversed under depreciation blocked: %', SQLERRM;
    END;

    -- Adjusting past what the asset has left would push book value through the
    -- residual floor.
    BEGIN
        PERFORM spwaterassetdepreciation_adjust(v_farm, v_a3, CURRENT_DATE, 5000,
                                                'Too much', 'ZZ tester');
        RAISE NOTICE 'N4. adjusting past the floor <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N4. adjusting past the floor blocked: %', SQLERRM;
    END;

    -- Depreciating something that is not in service.
    BEGIN
        PERFORM spwaterassetdepreciation_adjust(v_farm, v_draft, CURRENT_DATE, 100,
                                                'Draft', 'ZZ tester');
        RAISE NOTICE 'N5. adjusting a Draft asset <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N5. adjusting a Draft asset blocked: %', SQLERRM;
    END;

    -- No reason means no audit trail.
    SELECT waterassetdepreciationid INTO v_entry FROM waterassetdepreciation
     WHERE watercapitalassetid = v_a3 AND sourcetype = 'Scheduled' ORDER BY periodstart LIMIT 1;
    BEGIN
        PERFORM spwaterassetdepreciation_reverse(v_farm, v_entry, '  ', 'ZZ tester');
        RAISE NOTICE 'N6. a reversal with no reason <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N6. a reversal with no reason blocked: %', SQLERRM;
    END;

    -- Reversing the same charge twice would double-credit it.
    BEGIN
        PERFORM spwaterassetdepreciation_reverse(v_farm, v_entry, 'Once', 'ZZ tester');
        PERFORM spwaterassetdepreciation_reverse(v_farm, v_entry, 'Twice', 'ZZ tester');
        RAISE NOTICE 'N7. reversing the same charge twice <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N7. reversing the same charge twice blocked: %', SQLERRM;
    END;

    -- A reversal row is not itself reversible.
    BEGIN
        PERFORM spwaterassetdepreciation_reverse(v_farm,
            (SELECT waterassetdepreciationid FROM waterassetdepreciation
              WHERE reversalofid = v_entry LIMIT 1),
            'Reversing a reversal', 'ZZ tester');
        RAISE NOTICE 'N8. reversing a reversal   <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N8. reversing a reversal   blocked: %', SQLERRM;
    END;

    -- The unique index is the real guarantee, not the caller's care: a direct
    -- write cannot charge the same month twice.
    BEGIN
        INSERT INTO waterassetdepreciation
            (farmid, watercapitalassetid, periodstart, periodend, depreciationdate,
             amount, sourcetype, status)
        SELECT v_farm, v_a12, d.periodstart, d.periodend, d.depreciationdate,
               d.amount, 'Scheduled', 'Posted'
        FROM   waterassetdepreciation d
        WHERE  d.watercapitalassetid = v_a12 AND d.sourcetype = 'Scheduled'
        LIMIT  1;
        RAISE NOTICE 'N9. a duplicate scheduled month <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N9. a duplicate scheduled month blocked: %', SQLERRM;
    END;
END
$n$;

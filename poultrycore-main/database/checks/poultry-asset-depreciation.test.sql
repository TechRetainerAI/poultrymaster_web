-- Behavioural checks for migration 271: straight-line depreciation.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates assets and posts depreciation.
--
--   psql ... -X -c "BEGIN;" -f poultry-asset-depreciation.test.sql -c "ROLLBACK;"
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **Depreciation is an expense that moves no money.** Section B charges 2,000
-- and asserts, in the same breath, that the cash account did not move, no cash
-- transaction was written, no supplier was created and no payable opened -- and
-- that the 2,000 IS in Profit & Loss. Every one of those five has to hold at
-- once, or the number is wrong somewhere.
--
-- The rest:
--   1. §81's example to the cedi: 120,000 over 60 months is 2,000 a month, and
--      book value goes to 118,000.
--   2. Generating twice charges nothing the second time.
--   3. The LAST month takes what is left, not the rounded monthly figure, so
--      accumulated lands exactly on the depreciable amount and the asset can
--      actually finish.
--   4. Book value never falls below residual value.
--   5. §82's reversal: the original is kept, an opposite row appears, book value
--      comes back, and cash is still untouched.
--   6. A Draft asset -- one not yet in service -- is not charged at all.

DO $t$
DECLARE
    v_farm text;
    v_uuid uuid;
    v_acct integer;
    v_mixer integer; v_draft integer; v_odd integer;
    v_bal0 numeric; v_bal1 numeric;
    v_cash0 integer;
    v_r record;
    v_g record;
    v_entry integer;
    v_pl0 numeric; v_pl1 numeric;
BEGIN
    SELECT f.farmid INTO v_farm
    FROM   farms f
    WHERE  f.type = 'Poultry'
      AND  f.farmid ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ORDER  BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No uuid-shaped poultry company to test against.'; END IF;
    v_uuid := v_farm::uuid;
    RAISE NOTICE '   using poultry farm %', v_farm;

    v_acct := sppoultrycashaccount_insert(v_farm, 'ZZ Depreciation Account', 'Bank', 500000, TRUE, NULL);

    -- =====================================================================
    -- A. §81 -- a feed mixer, in service six months ago.
    -- =====================================================================
    v_mixer := sppoultrycapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ D Feed Mixer',
        p_acquisitiondate => (CURRENT_DATE - interval '6 months')::date,
        p_inservicedate   => (CURRENT_DATE - interval '6 months')::date,
        p_amount => 120000, p_residualvalue => 0, p_usefullifemonths => 60,
        p_paymentmethod => 'Cash', p_amountpaid => 120000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    SELECT * INTO v_r FROM fnpoultrycapitalasset_financials(v_mixer);
    RAISE NOTICE 'A1. depreciable amount     expect 120000.00  got %', v_r.depreciableamount;
    RAISE NOTICE 'A2. monthly charge         expect 2000.00  got %', v_r.monthlydepreciation;
    RAISE NOTICE 'A3. nothing charged yet    expect 0.00  got %', v_r.accumulateddepreciation;

    -- Seven months due: the month it went into service, plus the six since.
    SELECT * INTO v_g FROM sppoultryassetdepreciation_due(v_farm) d
    WHERE  d.poultrycapitalassetid = v_mixer;
    RAISE NOTICE 'A4. months due             expect 7  got %', v_g.monthsdue;
    RAISE NOTICE 'A5. amount due             expect 14000.00  got %', v_g.amountdue;

    -- =====================================================================
    -- B. THE CLAIM. One month charged, and no money moved.
    -- =====================================================================
    SELECT a.currentbalance INTO v_bal0 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    SELECT COUNT(*)::integer INTO v_cash0 FROM poultrycashtransactions t WHERE t.farmid = v_farm;

    -- Charge only the in-service month, so the arithmetic is one clean 2,000.
    SELECT * INTO v_g FROM sppoultryassetdepreciation_generate(
        v_farm, (CURRENT_DATE - interval '6 months')::date, v_mixer, 'ZZ tester');
    RAISE NOTICE 'B1. one month charged      expect 1  got %', v_g.entriescreated;
    RAISE NOTICE 'B2. of                     expect 2000.00  got %', v_g.totalamount;

    SELECT * INTO v_r FROM fnpoultrycapitalasset_financials(v_mixer);
    RAISE NOTICE 'B3. accumulated            expect 2000.00  got %', v_r.accumulateddepreciation;
    RAISE NOTICE 'B4. book value             expect 118000.00  got %', v_r.currentbookvalue;

    -- The five things that must all be true at once.
    SELECT a.currentbalance INTO v_bal1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    RAISE NOTICE 'B5. cash did not move      expect 0.00  got %', (v_bal0 - v_bal1);
    RAISE NOTICE 'B6. no cash transaction    expect %  got %',
        v_cash0, (SELECT COUNT(*)::integer FROM poultrycashtransactions t WHERE t.farmid = v_farm);
    RAISE NOTICE 'B7. no supplier            expect <NULL>  got %',
        COALESCE((SELECT e.supplierid::text FROM expense e
                   WHERE e.sourcetype = 'AssetDepreciation' AND e.farmid = v_uuid LIMIT 1), '<NULL>');
    RAISE NOTICE 'B8. nothing is owed        expect NonCash  got %',
        (SELECT e.paymentstatus FROM expense e
          WHERE e.sourcetype = 'AssetDepreciation' AND e.farmid = v_uuid LIMIT 1);
    -- ...and it IS an expense.
    RAISE NOTICE 'B9. but it IS in profit    expect 2000.00  got %',
        (SELECT COALESCE(SUM(e.amount), 0) FROM expense e
          WHERE e.sourcetype = 'AssetDepreciation' AND e.farmid = v_uuid);
    RAISE NOTICE 'B10. on the Depreciation line expect Depreciation  got %',
        (SELECT e.plline FROM fnpoultryexpenserows(v_uuid) e
          WHERE e.sourcetype = 'AssetDepreciation' LIMIT 1);
    RAISE NOTICE 'B11. below Operating Profit expect OtherCost  got %',
        (SELECT e.plsection FROM fnpoultryexpenserows(v_uuid) e
          WHERE e.sourcetype = 'AssetDepreciation' LIMIT 1);

    -- =====================================================================
    -- C. Generating twice charges nothing the second time.
    -- =====================================================================
    SELECT * INTO v_g FROM sppoultryassetdepreciation_generate(
        v_farm, (CURRENT_DATE - interval '6 months')::date, v_mixer, 'ZZ tester');
    RAISE NOTICE 'C1. second run creates     expect 0  got %', v_g.entriescreated;
    RAISE NOTICE 'C2. accumulated unchanged  expect 2000.00  got %',
        fnpoultrycapitalasset_accumulated(v_mixer);

    -- Catching up to today charges the six months in between, and no more.
    SELECT * INTO v_g FROM sppoultryassetdepreciation_generate(v_farm, NULL, v_mixer, 'ZZ tester');
    RAISE NOTICE 'C3. catch-up charges       expect 6  got %', v_g.entriescreated;
    RAISE NOTICE 'C4. accumulated now        expect 14000.00  got %',
        fnpoultrycapitalasset_accumulated(v_mixer);
    RAISE NOTICE 'C5. nothing is due now     expect 0  got %',
        (SELECT COUNT(*)::integer FROM sppoultryassetdepreciation_due(v_farm) d
          WHERE d.poultrycapitalassetid = v_mixer);

    -- =====================================================================
    -- D. An asset that finishes, to the cedi.
    -- =====================================================================
    -- 1,000 over 3 months is 333.33 a month. Three of those is 999.99, so the
    -- last month has to take 333.34 or the asset never finishes.
    v_odd := sppoultrycapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ D Awkward Asset',
        p_acquisitiondate => (CURRENT_DATE - interval '5 months')::date,
        p_inservicedate   => (CURRENT_DATE - interval '5 months')::date,
        p_amount => 1000, p_residualvalue => 0, p_usefullifemonths => 3,
        p_paymentmethod => 'Cash', p_amountpaid => 1000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    RAISE NOTICE 'D1. rounded monthly        expect 333.33  got %',
        (SELECT f.monthlydepreciation FROM fnpoultrycapitalasset_financials(v_odd) f);

    SELECT * INTO v_g FROM sppoultryassetdepreciation_generate(v_farm, NULL, v_odd, 'ZZ tester');
    RAISE NOTICE 'D2. exactly three months   expect 3  got %', v_g.entriescreated;
    -- The whole point: 333.33 + 333.33 + 333.34.
    RAISE NOTICE 'D3. and they total exactly expect 1000.00  got %',
        fnpoultrycapitalasset_accumulated(v_odd);
    RAISE NOTICE 'D4. book value is zero     expect 0.00  got %',
        (SELECT f.currentbookvalue FROM fnpoultrycapitalasset_financials(v_odd) f);
    RAISE NOTICE 'D5. and it is finished     expect FullyDepreciated  got %',
        (SELECT a.status FROM poultrycapitalassets a WHERE a.poultrycapitalassetid = v_odd);
    -- Two months past its life, and it is still not charged again.
    SELECT * INTO v_g FROM sppoultryassetdepreciation_generate(v_farm, NULL, v_odd, 'ZZ tester');
    RAISE NOTICE 'D6. no charge past its life expect 0  got %', v_g.entriescreated;

    -- =====================================================================
    -- E. Book value never falls below residual value.
    -- =====================================================================
    DECLARE
        v_res integer;
    BEGIN
        v_res := sppoultrycapitalasset_create(
            p_farmid => v_farm, p_assetname => 'ZZ D Truck With Resale Value',
            p_acquisitiondate => (CURRENT_DATE - interval '10 months')::date,
            p_inservicedate   => (CURRENT_DATE - interval '10 months')::date,
            p_amount => 10000, p_residualvalue => 4000, p_usefullifemonths => 2,
            p_paymentmethod => 'Cash', p_amountpaid => 10000,
            p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

        RAISE NOTICE 'E1. only 6000 depreciates  expect 6000.00  got %',
            (SELECT f.depreciableamount FROM fnpoultrycapitalasset_financials(v_res) f);
        PERFORM sppoultryassetdepreciation_generate(v_farm, NULL, v_res, 'ZZ tester');
        RAISE NOTICE 'E2. accumulated stops at   expect 6000.00  got %',
            fnpoultrycapitalasset_accumulated(v_res);
        -- Not zero. The farm still expects to sell the truck for 4,000.
        RAISE NOTICE 'E3. book value floors at   expect 4000.00  got %',
            (SELECT f.currentbookvalue FROM fnpoultrycapitalasset_financials(v_res) f);
    END;

    -- =====================================================================
    -- F. A Draft asset is not charged at all.
    -- =====================================================================
    v_draft := sppoultrycapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ D Half Built House',
        p_acquisitiondate => (CURRENT_DATE - interval '3 months')::date,
        p_amount => 300000, p_paymentmethod => 'Cash', p_amountpaid => 300000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    SELECT * INTO v_g FROM sppoultryassetdepreciation_generate(v_farm, NULL, v_draft, 'ZZ tester');
    RAISE NOTICE 'F1. a Draft is not charged expect 0  got %', COALESCE(v_g.entriescreated, 0);
    RAISE NOTICE 'F2. and owes nothing yet   expect 0.00  got %',
        fnpoultrycapitalasset_accumulated(v_draft);
    RAISE NOTICE 'F3. it is still Draft      expect Draft  got %',
        (SELECT a.status FROM poultrycapitalassets a WHERE a.poultrycapitalassetid = v_draft);

    -- =====================================================================
    -- G. §82 -- reversal.
    -- =====================================================================
    SELECT d.poultryassetdepreciationid INTO v_entry
    FROM   poultryassetdepreciation d
    WHERE  d.poultrycapitalassetid = v_mixer AND d.sourcetype = 'Scheduled'
    ORDER  BY d.periodstart DESC LIMIT 1;

    SELECT a.currentbalance INTO v_bal0 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    SELECT COALESCE(SUM(e.amount), 0) INTO v_pl0 FROM expense e
    WHERE  e.farmid = v_uuid AND e.sourcetype = 'AssetDepreciation';

    PERFORM sppoultryassetdepreciation_reverse(v_farm, v_entry, 'Wrong in-service month', 'ZZ tester');

    RAISE NOTICE 'G1. the original is kept   expect Reversed  got %',
        (SELECT d.status FROM poultryassetdepreciation d WHERE d.poultryassetdepreciationid = v_entry);
    RAISE NOTICE 'G2. and an opposite row appears expect -2000.00  got %',
        (SELECT d.amount FROM poultryassetdepreciation d WHERE d.reversalofid = v_entry);
    RAISE NOTICE 'G3. accumulated falls to   expect 12000.00  got %',
        fnpoultrycapitalasset_accumulated(v_mixer);
    RAISE NOTICE 'G4. book value comes back  expect 108000.00  got %',
        (SELECT f.currentbookvalue FROM fnpoultrycapitalasset_financials(v_mixer) f);

    SELECT COALESCE(SUM(e.amount), 0) INTO v_pl1 FROM expense e
    WHERE  e.farmid = v_uuid AND e.sourcetype = 'AssetDepreciation';
    RAISE NOTICE 'G5. and P&L falls by       expect -2000.00  got %', (v_pl1 - v_pl0);

    SELECT a.currentbalance INTO v_bal1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    RAISE NOTICE 'G6. cash still untouched   expect 0.00  got %', (v_bal1 - v_bal0);

    -- Both rows survive. That is what append-only means.
    RAISE NOTICE 'G7. both rows are there    expect 2  got %',
        (SELECT COUNT(*)::integer FROM poultryassetdepreciation d
          WHERE d.poultrycapitalassetid = v_mixer AND d.periodstart =
                (SELECT p.periodstart FROM poultryassetdepreciation p WHERE p.poultryassetdepreciationid = v_entry));

    BEGIN
        PERFORM sppoultryassetdepreciation_reverse(v_farm, v_entry, 'again', 'ZZ tester');
        RAISE NOTICE 'G8. reversing twice        <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'G8. reversing twice        blocked: %', left(SQLERRM, 60);
    END;

    BEGIN
        PERFORM sppoultryassetdepreciation_reverse(v_farm, v_entry, '', 'ZZ tester');
        RAISE NOTICE 'G9. reversal with no reason <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'G9. reversal with no reason blocked: %', left(SQLERRM, 60);
    END;

    -- A reversal does NOT reopen the month to the generator, and that is the
    -- point: if it did, the next "Generate due depreciation" would put the
    -- charge straight back and the reverse button would do nothing.
    SELECT * INTO v_g FROM sppoultryassetdepreciation_generate(v_farm, NULL, v_mixer, 'ZZ tester');
    RAISE NOTICE 'G10. generate leaves it alone expect 0  got %', v_g.entriescreated;
    RAISE NOTICE 'G11. still                 expect 12000.00  got %',
        fnpoultrycapitalasset_accumulated(v_mixer);

    -- The correction is posted deliberately instead, as an adjustment.
    PERFORM sppoultryassetdepreciation_adjust(
        v_farm, v_mixer,
        (SELECT d.periodstart FROM poultryassetdepreciation d WHERE d.poultryassetdepreciationid = v_entry),
        2000, 'Re-posting the corrected charge', 'ZZ tester');
    RAISE NOTICE 'G12. and now it is back to expect 14000.00  got %',
        fnpoultrycapitalasset_accumulated(v_mixer);
    RAISE NOTICE 'G13. labelled as a decision expect ManualAdjustment  got %',
        (SELECT d.sourcetype FROM poultryassetdepreciation d
          WHERE d.poultrycapitalassetid = v_mixer AND d.sourcetype = 'ManualAdjustment' LIMIT 1);

    -- An adjustment cannot charge more than the asset has left to give.
    BEGIN
        PERFORM sppoultryassetdepreciation_adjust(v_farm, v_mixer, CURRENT_DATE, 999999,
                                                  'too much', 'ZZ tester');
        RAISE NOTICE 'G14. over-adjusting        <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'G14. over-adjusting        blocked: %', left(SQLERRM, 60);
    END;

    -- =====================================================================
    -- H. §58 -- the asset's financial fields are locked once it is charged.
    -- =====================================================================
    BEGIN
        PERFORM sppoultrycapitalasset_update(
            p_farmid => v_farm, p_assetid => v_mixer, p_assetname => NULL,
            p_inservicedate => CURRENT_DATE, p_usefullifemonths => 24,
            p_residualvalue => 0, p_setfinancials => TRUE, p_updatedby => 'ZZ tester');
        RAISE NOTICE 'H1. changing a charged life <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'H1. changing a charged life blocked: %', left(SQLERRM, 60);
    END;

    -- Renaming it is always fine. Locking the name too would be pointless
    -- friction: nothing in the ledger depends on it.
    PERFORM sppoultrycapitalasset_update(
        p_farmid => v_farm, p_assetid => v_mixer, p_assetname => 'ZZ D Feed Mixer (Shed 2)',
        p_location => 'Shed 2', p_updatedby => 'ZZ tester');
    RAISE NOTICE 'H2. but renaming is fine   expect ZZ D Feed Mixer (Shed 2)  got %',
        (SELECT a.assetname FROM poultrycapitalassets a WHERE a.poultrycapitalassetid = v_mixer);

    BEGIN
        PERFORM sppoultrycapitalassetcost_add(v_farm, v_mixer, CURRENT_DATE, 'ZZ late cost', NULL,
                                              5000, NULL, NULL, 'Cash', 5000, NULL, v_acct, NULL, 'ZZ tester');
        RAISE NOTICE 'H3. cost after depreciation <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'H3. cost after depreciation blocked: %', left(SQLERRM, 60);
    END;

    BEGIN
        PERFORM sppoultrycapitalasset_reverse(v_farm, v_mixer, 'should be blocked', 'ZZ tester');
        RAISE NOTICE 'H4. reversing a charged asset <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'H4. reversing a charged asset blocked: %', left(SQLERRM, 60);
    END;

    -- =====================================================================
    -- I. The history reads like a statement.
    -- =====================================================================
    -- Seven scheduled, one reversal, one adjustment.
    RAISE NOTICE 'I1. entries for the mixer  expect 9  got %',
        (SELECT COUNT(*)::integer FROM sppoultryassetdepreciation_getall(v_farm, v_mixer));
    RAISE NOTICE 'I2. the ledger sums to     expect 14000.00  got %',
        (SELECT COALESCE(SUM(h.amount), 0) FROM sppoultryassetdepreciation_getall(v_farm, v_mixer) h);
    -- And the drilldown total is the P&L line: the two cannot disagree because
    -- they are the same rows.
    RAISE NOTICE 'I3. and equals the expenses expect %  got %',
        (SELECT COALESCE(SUM(e.amount), 0) FROM expense e
          WHERE e.farmid = v_uuid AND e.sourcetype = 'AssetDepreciation'
            AND e.poultrycapitalassetid = v_mixer),
        (SELECT COALESCE(SUM(h.amount), 0) FROM sppoultryassetdepreciation_getall(v_farm, v_mixer) h);
END
$t$;

-- Behavioural checks for migration 313: cost composition and correction.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates a supplier, a cash account and assets.
--
--   psql ... -X -c "BEGIN;" -f poultry-asset-cost-composition.test.sql -c "ROLLBACK;"
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **A number that was typed wrong can be put right without lying about it.**
-- Section D records a 130,000 acquisition that should have been 13,000, corrects
-- it, and asserts all six things at once: the original acquisition now reads
-- 13,000, the total follows it, the 117,000 that never left the farm is back in
-- the account, the bill says 13,000, there is still exactly ONE expense behind
-- the asset, and the correction is on the record with its reason.
--
-- Before 313 the only offered fix was "Add cost", which would have made the
-- register say 143,000.
--
-- The rest:
--   A. acquisition + additional = total, for every shape of asset, always.
--   B. Adding a cost moves ONLY the additional half.
--   C. An asset BUILT from nothing has an acquisition cost of zero, and a
--      correction is refused on it -- there is nothing there to correct.
--   D. The claim above.
--   E. Correcting AFTER depreciation leaves every posted month exactly as
--      posted and only changes what is still to come.
--   F. Reversing ONE added cost: the row is kept, the total drops, the cash
--      comes back, and the expense is gone.
--   G. The guards refuse rather than corrupt.
--   H. Company scoping: another company's id cannot reach this asset.

DO $t$
DECLARE
    v_farm  text;
    v_uuid  uuid;
    v_other text;
    v_supp  integer;
    v_acct  integer;
    v_cages integer; v_built integer; v_typo integer; v_dep integer;
    v_cost  integer;
    v_bal0  numeric; v_bal1 numeric;
    v_acc   numeric;
    v_n     integer;
    v_txt   text;
    v_r     record;
BEGIN
    SELECT f.farmid INTO v_farm
    FROM   farms f
    WHERE  f.type = 'Poultry'
      AND  f.farmid ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ORDER  BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No uuid-shaped poultry company to test against.'; END IF;
    v_uuid := v_farm::uuid;
    RAISE NOTICE '   using poultry farm %', v_farm;

    v_supp := spsupplier_insert('ZZ tester', v_farm, 'ZZ Cage Works Ltd', NULL, NULL, NULL, NULL);
    v_acct := sppoultrycashaccount_insert(v_farm, 'ZZ Composition Account', 'Bank', 2000000, TRUE, NULL);

    -- =====================================================================
    -- A. The identity, on every asset that already exists on this database.
    --
    -- First, because if it ever fails every screen downstream is lying, and
    -- because it must hold for HISTORICAL rows this migration never touched.
    -- =====================================================================
    SELECT COUNT(*)::integer INTO v_n
    FROM   poultrycapitalassets a
    WHERE  ROUND(fnpoultrycapitalasset_acquisitioncost(a.poultrycapitalassetid)
               + fnpoultrycapitalasset_additionalcost(a.poultrycapitalassetid), 2)
        <> ROUND(fnpoultrycapitalasset_originalcost(a.poultrycapitalassetid), 2);
    RAISE NOTICE 'A1. assets where the halves do not add to the whole  expect 0  got %', COALESCE(v_n, -1);

    -- =====================================================================
    -- B. A plain acquisition, then a cost added to it.
    -- =====================================================================
    v_cages := sppoultrycapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Cages',
        p_acquisitiondate => CURRENT_DATE, p_amount => 100000,
        p_residualvalue => 0, p_usefullifemonths => 96,
        p_paymentmethod => 'Cash', p_amountpaid => 100000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    SELECT g.acquisitioncost, g.additionalcost, g.totalcapitalizedcost, g.originalcost INTO v_r
    FROM   sppoultrycapitalasset_getall(v_farm) g WHERE g.poultrycapitalassetid = v_cages;
    RAISE NOTICE 'B1. original acquisition   expect 100000.00  got %', COALESCE(v_r.acquisitioncost, -1);
    RAISE NOTICE 'B2. additional costs       expect 0.00  got %',      COALESCE(v_r.additionalcost, -1);
    RAISE NOTICE 'B3. total capitalised      expect 100000.00  got %', COALESCE(v_r.totalcapitalizedcost, -1);
    -- The old field must keep meaning exactly what it meant, for callers written
    -- against 270. It is the TOTAL, and it always was.
    RAISE NOTICE 'B4. originalcost is still the total  expect 100000.00  got %', COALESCE(v_r.originalcost, -1);

    -- The acquisition leads the cost history, which is §13's whole point: the
    -- purchase is part of the cost story, not a separate thing above it.
    SELECT c.sourcetype INTO v_txt
    FROM   sppoultrycapitalassetcost_getall(v_farm, v_cages) c
    ORDER  BY c.costdate, c.poultrycapitalassetcostid LIMIT 1;
    RAISE NOTICE 'B5. first row in the history  expect Acquisition  got %', COALESCE(v_txt, 'NULL');

    PERFORM sppoultrycapitalassetcost_add(
        p_farmid => v_farm, p_assetid => v_cages, p_costdate => CURRENT_DATE,
        p_description => 'ZZ installation', p_costcategory => 'Installation',
        p_amount => 20000, p_paymentmethod => 'Cash', p_amountpaid => 20000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    SELECT g.acquisitioncost, g.additionalcost, g.totalcapitalizedcost INTO v_r
    FROM   sppoultrycapitalasset_getall(v_farm) g WHERE g.poultrycapitalassetid = v_cages;
    RAISE NOTICE 'B6. acquisition UNMOVED    expect 100000.00  got %', COALESCE(v_r.acquisitioncost, -1);
    RAISE NOTICE 'B7. additional costs       expect 20000.00  got %',  COALESCE(v_r.additionalcost, -1);
    RAISE NOTICE 'B8. total capitalised      expect 120000.00  got %', COALESCE(v_r.totalcapitalizedcost, -1);
    RAISE NOTICE 'B9. cost history rows      expect 2  got %',
        (SELECT COUNT(*)::integer FROM sppoultrycapitalassetcost_getall(v_farm, v_cages) c
          WHERE c.status = 'Posted');

    -- The added cost carries its payment detail through to the history, which is
    -- the whole of Problem B: an Add cost that cannot be read back.
    SELECT c.paymentmethod, c.cashaccountname, c.paymentstatus INTO v_r
    FROM   sppoultrycapitalassetcost_getall(v_farm, v_cages) c
    WHERE  c.sourcetype = 'AdditionalCost';
    RAISE NOTICE 'B10. how it was paid       expect Cash  got %', COALESCE(v_r.paymentmethod, 'NULL');
    RAISE NOTICE 'B11. which account         expect ZZ Composition Account  got %',
        COALESCE(v_r.cashaccountname, 'NULL');

    -- =====================================================================
    -- C. An asset BUILT from nothing has no acquisition to correct.
    -- =====================================================================
    v_built := sppoultrycapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ House Under Construction',
        p_acquisitiondate => CURRENT_DATE, p_amount => NULL, p_createdby => 'ZZ tester');
    PERFORM sppoultrycapitalassetcost_add(
        p_farmid => v_farm, p_assetid => v_built, p_costdate => CURRENT_DATE,
        p_description => 'ZZ cement', p_costcategory => 'Materials', p_amount => 5000,
        p_paymentmethod => 'Cash', p_amountpaid => 5000, p_cashaccountid => v_acct,
        p_createdby => 'ZZ tester');

    SELECT g.acquisitioncost, g.additionalcost, g.totalcapitalizedcost INTO v_r
    FROM   sppoultrycapitalasset_getall(v_farm) g WHERE g.poultrycapitalassetid = v_built;
    RAISE NOTICE 'C1. built: acquisition     expect 0.00  got %',    COALESCE(v_r.acquisitioncost, -1);
    RAISE NOTICE 'C2. built: additional      expect 5000.00  got %', COALESCE(v_r.additionalcost, -1);
    RAISE NOTICE 'C3. built: total           expect 5000.00  got %', COALESCE(v_r.totalcapitalizedcost, -1);

    BEGIN
        PERFORM sppoultrycapitalasset_correctoriginalcost(
            v_farm, v_built, 9000, CURRENT_DATE, 'ZZ nothing to correct', 'ZZ tester');
        RAISE NOTICE 'C4. correcting a built asset  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'C4. correcting a built asset  expect REFUSED  got REFUSED (%)', left(SQLERRM, 45);
    END;

    -- =====================================================================
    -- D. THE CLAIM. 130,000 typed where the invoice said 13,000.
    -- =====================================================================
    SELECT a.currentbalance INTO v_bal0 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;

    v_typo := sppoultrycapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Mistyped Generator',
        p_acquisitiondate => CURRENT_DATE, p_amount => 130000,
        p_residualvalue => 0, p_usefullifemonths => 84,
        p_paymentmethod => 'Cash', p_amountpaid => 130000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    SELECT a.currentbalance INTO v_bal1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    RAISE NOTICE 'D0. cash out as recorded   expect 130000.00  got %', COALESCE(v_bal0 - v_bal1, -1);

    PERFORM sppoultrycapitalasset_correctoriginalcost(
        v_farm, v_typo, 13000, CURRENT_DATE,
        'Original invoice amount was entered incorrectly', 'ZZ tester');

    SELECT g.acquisitioncost, g.additionalcost, g.totalcapitalizedcost, g.currentbookvalue INTO v_r
    FROM   sppoultrycapitalasset_getall(v_farm) g WHERE g.poultrycapitalassetid = v_typo;
    RAISE NOTICE 'D1. original acquisition   expect 13000.00  got %', COALESCE(v_r.acquisitioncost, -1);
    RAISE NOTICE 'D2. and nothing was added  expect 0.00  got %',     COALESCE(v_r.additionalcost, -1);
    RAISE NOTICE 'D3. total follows it       expect 13000.00  got %', COALESCE(v_r.totalcapitalizedcost, -1);
    RAISE NOTICE 'D4. book value follows too expect 13000.00  got %', COALESCE(v_r.currentbookvalue, -1);

    -- The 117,000 that never actually left the farm is back.
    SELECT a.currentbalance INTO v_bal1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    RAISE NOTICE 'D5. net cash out is now    expect 13000.00  got %', COALESCE(v_bal0 - v_bal1, -1);

    -- ONE expense, not two. This is §54's "no duplicate cash movement, no
    -- duplicate supplier payment, no duplicate expense" in a single count.
    RAISE NOTICE 'D6. expenses behind the asset  expect 1  got %',
        (SELECT COUNT(*)::integer FROM expense e
          WHERE e.farmid = v_uuid AND e.poultrycapitalassetid = v_typo);
    RAISE NOTICE 'D7. and the bill now says  expect 13000.00  got %',
        (SELECT COALESCE(MAX(e.amount), -1) FROM expense e
          WHERE e.farmid = v_uuid AND e.poultrycapitalassetid = v_typo);
    -- Still capital, still out of profit. A correction must not reclassify it.
    RAISE NOTICE 'D8. still excluded from profit  expect Excluded  got %',
        (SELECT COALESCE(MAX(e.plsection), 'NULL') FROM fnpoultryexpenserows(v_uuid) e
          WHERE e.poultrycapitalassetid = v_typo);

    -- The record of WHY, which is the difference between a correction and a
    -- silent overwrite.
    SELECT c.amount, c.description, c.costcategory, c.createdby INTO v_r
    FROM   sppoultrycapitalassetcost_getall(v_farm, v_typo) c
    WHERE  c.sourcetype = 'OriginalCostCorrection';
    RAISE NOTICE 'D9. the correction row     expect -117000.00  got %', COALESCE(v_r.amount, -1);
    RAISE NOTICE 'D10. carries its reason    expect Original invoice...  got %',
        COALESCE(left(v_r.description, 24), 'NULL');
    RAISE NOTICE 'D11. and who made it       expect ZZ tester  got %', COALESCE(v_r.createdby, 'NULL');
    -- Two rows in the history, not one edited row: the 130,000 is still visible.
    RAISE NOTICE 'D12. history keeps both    expect 2  got %',
        (SELECT COUNT(*)::integer FROM sppoultrycapitalassetcost_getall(v_farm, v_typo) c
          WHERE c.status = 'Posted');

    -- =====================================================================
    -- E. Correcting AFTER depreciation has been posted.
    --
    -- The rule: months already charged stay exactly as charged. Only what is
    -- still to come follows the corrected cost.
    -- =====================================================================
    v_dep := sppoultrycapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Depreciating Truck',
        p_acquisitiondate => (CURRENT_DATE - interval '2 months')::date,
        p_inservicedate   => (CURRENT_DATE - interval '2 months')::date,
        p_amount => 120000, p_residualvalue => 0, p_usefullifemonths => 120,
        p_paymentmethod => 'Cash', p_amountpaid => 120000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    PERFORM sppoultryassetdepreciation_generate(v_farm, CURRENT_DATE, v_dep, 'ZZ tester');

    SELECT COUNT(*)::integer, COALESCE(SUM(d.amount), 0) INTO v_n, v_acc
    FROM   poultryassetdepreciation d WHERE d.poultrycapitalassetid = v_dep;
    RAISE NOTICE 'E1. months charged         expect 3  got %', COALESCE(v_n, -1);
    RAISE NOTICE 'E2. at 1000.00 a month     expect 3000.00  got %', COALESCE(v_acc, -1);

    PERFORM sppoultrycapitalasset_correctoriginalcost(
        v_farm, v_dep, 60000, CURRENT_DATE, 'ZZ invoice was half that', 'ZZ tester');

    -- Nothing posted has moved. Not the count, not the sum, not one row.
    SELECT COUNT(*)::integer, COALESCE(SUM(d.amount), 0) INTO v_n, v_acc
    FROM   poultryassetdepreciation d WHERE d.poultrycapitalassetid = v_dep;
    RAISE NOTICE 'E3. posted months UNCHANGED  expect 3  got %', COALESCE(v_n, -1);
    RAISE NOTICE 'E4. posted amount UNCHANGED  expect 3000.00  got %', COALESCE(v_acc, -1);
    RAISE NOTICE 'E5. and none was deleted    expect 3  got %',
        (SELECT COUNT(*)::integer FROM expense e
          WHERE e.farmid = v_uuid AND e.sourcetype = 'AssetDepreciation'
            AND e.poultrycapitalassetid = v_dep);

    -- Forwards, the schedule follows the corrected cost on its own.
    SELECT g.totalcapitalizedcost, g.monthlydepreciation, g.accumulateddepreciation,
           g.currentbookvalue, g.remainingdepreciable INTO v_r
    FROM   sppoultrycapitalasset_getall(v_farm) g WHERE g.poultrycapitalassetid = v_dep;
    RAISE NOTICE 'E6. cost is now            expect 60000.00  got %', COALESCE(v_r.totalcapitalizedcost, -1);
    RAISE NOTICE 'E7. future months halve    expect 500.00  got %',   COALESCE(v_r.monthlydepreciation, -1);
    RAISE NOTICE 'E8. accumulated stands     expect 3000.00  got %',  COALESCE(v_r.accumulateddepreciation, -1);
    -- §64's identity: total - accumulated = book value.
    RAISE NOTICE 'E9. book value = cost - dep  expect 57000.00  got %', COALESCE(v_r.currentbookvalue, -1);
    RAISE NOTICE 'E10. still to charge       expect 57000.00  got %',  COALESCE(v_r.remainingdepreciable, -1);

    -- =====================================================================
    -- F. Reversing ONE added cost.
    -- =====================================================================
    SELECT a.currentbalance INTO v_bal0 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;

    SELECT c.poultrycapitalassetcostid INTO v_cost
    FROM   sppoultrycapitalassetcost_getall(v_farm, v_cages) c
    WHERE  c.sourcetype = 'AdditionalCost' AND c.status = 'Posted';

    PERFORM sppoultrycapitalassetcost_reverse(
        v_farm, v_cost, 'ZZ entered against the wrong investment', 'ZZ tester', v_cages);

    SELECT g.acquisitioncost, g.additionalcost, g.totalcapitalizedcost INTO v_r
    FROM   sppoultrycapitalasset_getall(v_farm) g WHERE g.poultrycapitalassetid = v_cages;
    RAISE NOTICE 'F1. net additional cost    expect 0.00  got %',      COALESCE(v_r.additionalcost, -1);
    RAISE NOTICE 'F2. acquisition untouched  expect 100000.00  got %', COALESCE(v_r.acquisitioncost, -1);
    RAISE NOTICE 'F3. total back to          expect 100000.00  got %', COALESCE(v_r.totalcapitalizedcost, -1);

    -- The row is KEPT, with its reason. §68: no hard-deleting financial history.
    SELECT c.status, c.reversalreason, c.reversedby INTO v_r
    FROM   sppoultrycapitalassetcost_getall(v_farm, v_cages) c
    WHERE  c.poultrycapitalassetcostid = v_cost;
    RAISE NOTICE 'F4. the row is kept        expect Reversed  got %', COALESCE(v_r.status, 'GONE');
    RAISE NOTICE 'F5. with its reason        expect ZZ entered aga...  got %',
        COALESCE(left(v_r.reversalreason, 17), 'NULL');

    SELECT a.currentbalance INTO v_bal1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    RAISE NOTICE 'F6. the 20000 came back    expect 20000.00  got %', COALESCE(v_bal1 - v_bal0, -1);
    RAISE NOTICE 'F7. its expense is gone    expect 1  got %',
        (SELECT COUNT(*)::integer FROM expense e
          WHERE e.farmid = v_uuid AND e.poultrycapitalassetid = v_cages);

    -- =====================================================================
    -- G. The guards refuse rather than corrupt.
    -- =====================================================================
    BEGIN
        PERFORM sppoultrycapitalasset_correctoriginalcost(v_farm, v_cages, 90000, CURRENT_DATE, '', 'ZZ tester');
        RAISE NOTICE 'G1. correction with no reason  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G1. correction with no reason  expect REFUSED  got REFUSED';
    END;

    BEGIN
        PERFORM sppoultrycapitalasset_correctoriginalcost(v_farm, v_cages, 100000, CURRENT_DATE, 'ZZ same', 'ZZ tester');
        RAISE NOTICE 'G2. correcting to the same amount  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G2. correcting to the same amount  expect REFUSED  got REFUSED';
    END;

    BEGIN
        PERFORM sppoultrycapitalasset_correctoriginalcost(v_farm, v_cages, -5, CURRENT_DATE, 'ZZ negative', 'ZZ tester');
        RAISE NOTICE 'G3. correcting to a negative  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G3. correcting to a negative  expect REFUSED  got REFUSED';
    END;

    -- Book value may never fall below residual value, so neither may the cost.
    PERFORM sppoultrycapitalasset_update(
        p_farmid => v_farm, p_assetid => v_cages, p_assetname => 'ZZ Cages',
        p_inservicedate => CURRENT_DATE, p_usefullifemonths => 96,
        p_residualvalue => 50000, p_setfinancials => TRUE, p_updatedby => 'ZZ tester');
    BEGIN
        PERFORM sppoultrycapitalasset_correctoriginalcost(v_farm, v_cages, 10000, CURRENT_DATE, 'ZZ under residual', 'ZZ tester');
        RAISE NOTICE 'G4. cost below residual value  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G4. cost below residual value  expect REFUSED  got REFUSED';
    END;

    -- The acquisition is not an "additional cost" and is not reversed this way.
    SELECT c.poultrycapitalassetcostid INTO v_cost
    FROM   sppoultrycapitalassetcost_getall(v_farm, v_cages) c WHERE c.sourcetype = 'Acquisition';
    BEGIN
        PERFORM sppoultrycapitalassetcost_reverse(v_farm, v_cost, 'ZZ nope', 'ZZ tester', v_cages);
        RAISE NOTICE 'G5. reversing the acquisition  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G5. reversing the acquisition  expect REFUSED  got REFUSED';
    END;

    -- Nor is a correction. Correct it again instead.
    SELECT c.poultrycapitalassetcostid INTO v_cost
    FROM   sppoultrycapitalassetcost_getall(v_farm, v_typo) c
    WHERE  c.sourcetype = 'OriginalCostCorrection';
    BEGIN
        PERFORM sppoultrycapitalassetcost_reverse(v_farm, v_cost, 'ZZ nope', 'ZZ tester', v_typo);
        RAISE NOTICE 'G6. reversing a correction  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G6. reversing a correction  expect REFUSED  got REFUSED';
    END;

    -- 270's existing refusal, still in force: costs are frozen once a month has
    -- been charged. 313 must not have loosened it.
    BEGIN
        PERFORM sppoultrycapitalassetcost_add(
            p_farmid => v_farm, p_assetid => v_dep, p_costdate => CURRENT_DATE,
            p_description => 'ZZ late cost', p_costcategory => 'Improvement',
            p_amount => 1000, p_paymentmethod => 'Cash', p_amountpaid => 1000,
            p_cashaccountid => v_acct, p_createdby => 'ZZ tester');
        RAISE NOTICE 'G7. adding cost after depreciation  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G7. adding cost after depreciation  expect REFUSED  got REFUSED';
    END;

    -- And a cost may not be reversed through another asset's id.
    SELECT c.poultrycapitalassetcostid INTO v_cost
    FROM   sppoultrycapitalassetcost_getall(v_farm, v_built) c WHERE c.status = 'Posted' LIMIT 1;
    BEGIN
        PERFORM sppoultrycapitalassetcost_reverse(v_farm, v_cost, 'ZZ wrong asset', 'ZZ tester', v_cages);
        RAISE NOTICE 'G8. reversing through the wrong asset  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G8. reversing through the wrong asset  expect REFUSED  got REFUSED';
    END;

    -- =====================================================================
    -- H. Company scoping. Never trust the id in the request.
    -- =====================================================================
    SELECT f.farmid INTO v_other FROM farms f WHERE f.farmid <> v_farm ORDER BY f.farmid LIMIT 1;
    IF v_other IS NOT NULL THEN
        BEGIN
            PERFORM sppoultrycapitalasset_correctoriginalcost(
                v_other, v_cages, 90000, CURRENT_DATE, 'ZZ other company', 'ZZ tester');
            RAISE NOTICE 'H1. correcting another company''s asset  expect REFUSED  got ALLOWED';
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'H1. correcting another company''s asset  expect REFUSED  got REFUSED';
        END;
        RAISE NOTICE 'H2. and it is untouched    expect 100000.00  got %',
            COALESCE(fnpoultrycapitalasset_acquisitioncost(v_cages), -1);
    ELSE
        RAISE NOTICE 'H1. no second company on this database -- scoping not exercised';
        RAISE NOTICE 'H2. no second company on this database -- scoping not exercised';
    END IF;

    -- =====================================================================
    -- I. And the identity still holds, over everything this file created.
    -- =====================================================================
    SELECT COUNT(*)::integer INTO v_n
    FROM   poultrycapitalassets a
    WHERE  ROUND(fnpoultrycapitalasset_acquisitioncost(a.poultrycapitalassetid)
               + fnpoultrycapitalasset_additionalcost(a.poultrycapitalassetid), 2)
        <> ROUND(fnpoultrycapitalasset_originalcost(a.poultrycapitalassetid), 2);
    RAISE NOTICE 'I1. halves still add to the whole  expect 0  got %', COALESCE(v_n, -1);

    RAISE NOTICE '--- 57 numbered assertions expected above (A1-I1). Each guard prints exactly';
    RAISE NOTICE '--- one of its two branches. A blank "got" is a FAILURE, not a pass. ---';
END;
$t$;

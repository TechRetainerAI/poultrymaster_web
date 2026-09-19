-- Behavioural checks for migration 314: cost composition and correction.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates a supplier, a cash account and assets.
--
--   psql ... -X -c "BEGIN;" -f water-asset-cost-composition.test.sql -c "ROLLBACK;"
--
-- The poultry mirror of this file is poultry-asset-cost-composition.test.sql and
-- the claims are the same. What differs, and what section D therefore checks
-- differently, is the MONEY LEG: water's cash ledger is append-only, so a
-- correction that reduces what was paid hands the difference back with its own
-- CashIn rather than by rewriting the transaction that took it. D5 checks the
-- balance; D5b checks that the original CashOut is still there to be read.
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **A number that was typed wrong can be put right without lying about it.**
--
-- The sections: A the identity, B acquisition vs additional, C an asset built
-- from nothing, D the claim, E correcting after depreciation, F reversing one
-- added cost, G the guards, H company scoping, I the identity again.

DO $t$
DECLARE
    v_farm  text;
    v_other text;
    v_supp  integer;
    v_acct  integer;
    v_tank integer; v_built integer; v_typo integer; v_dep integer;
    v_cost  integer;
    v_bal0  numeric; v_bal1 numeric;
    v_acc   numeric;
    v_n     integer;
    v_txt   text;
    v_r     record;
BEGIN
    SELECT f.farmid INTO v_farm
    FROM   farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No water company to test against.'; END IF;
    RAISE NOTICE '   using water company %', v_farm;

    INSERT INTO watersuppliers (farmid, suppliername, isactive, isdeleted)
    VALUES (v_farm, 'ZZ Tank Works Ltd', TRUE, FALSE)
    RETURNING watersupplierid INTO v_supp;

    INSERT INTO watercashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, isactive)
    VALUES (v_farm, 'ZZ Composition Account', 'Bank', 2000000, 2000000, TRUE)
    RETURNING watercashaccountid INTO v_acct;

    -- =====================================================================
    -- A. The identity, on every asset that already exists on this database.
    -- =====================================================================
    SELECT COUNT(*)::integer INTO v_n
    FROM   watercapitalassets a
    WHERE  ROUND(fnwatercapitalasset_acquisitioncost(a.watercapitalassetid)
               + fnwatercapitalasset_additionalcost(a.watercapitalassetid), 2)
        <> ROUND(fnwatercapitalasset_originalcost(a.watercapitalassetid), 2);
    RAISE NOTICE 'A1. assets where the halves do not add to the whole  expect 0  got %', COALESCE(v_n, -1);

    -- =====================================================================
    -- B. A plain acquisition, then a cost added to it.
    -- =====================================================================
    v_tank := spwatercapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Storage Tank',
        p_acquisitiondate => CURRENT_DATE, p_amount => 100000,
        p_residualvalue => 0, p_usefullifemonths => 96,
        p_paymentmethod => 'Cash', p_amountpaid => 100000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    SELECT g.acquisitioncost, g.additionalcost, g.totalcapitalizedcost, g.originalcost INTO v_r
    FROM   spwatercapitalasset_getall(v_farm) g WHERE g.watercapitalassetid = v_tank;
    RAISE NOTICE 'B1. original acquisition   expect 100000.00  got %', COALESCE(v_r.acquisitioncost, -1);
    RAISE NOTICE 'B2. additional costs       expect 0.00  got %',      COALESCE(v_r.additionalcost, -1);
    RAISE NOTICE 'B3. total capitalised      expect 100000.00  got %', COALESCE(v_r.totalcapitalizedcost, -1);
    -- The old field must keep meaning exactly what it meant, for callers written
    -- against 283. It is the TOTAL, and it always was.
    RAISE NOTICE 'B4. originalcost is still the total  expect 100000.00  got %', COALESCE(v_r.originalcost, -1);

    SELECT c.sourcetype INTO v_txt
    FROM   spwatercapitalassetcost_getall(v_farm, v_tank) c
    ORDER  BY c.costdate, c.watercapitalassetcostid LIMIT 1;
    RAISE NOTICE 'B5. first row in the history  expect Acquisition  got %', COALESCE(v_txt, 'NULL');

    PERFORM spwatercapitalassetcost_add(
        p_farmid => v_farm, p_assetid => v_tank, p_costdate => CURRENT_DATE,
        p_description => 'ZZ installation', p_costcategory => 'Installation',
        p_amount => 20000, p_paymentmethod => 'Cash', p_amountpaid => 20000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    SELECT g.acquisitioncost, g.additionalcost, g.totalcapitalizedcost INTO v_r
    FROM   spwatercapitalasset_getall(v_farm) g WHERE g.watercapitalassetid = v_tank;
    RAISE NOTICE 'B6. acquisition UNMOVED    expect 100000.00  got %', COALESCE(v_r.acquisitioncost, -1);
    RAISE NOTICE 'B7. additional costs       expect 20000.00  got %',  COALESCE(v_r.additionalcost, -1);
    RAISE NOTICE 'B8. total capitalised      expect 120000.00  got %', COALESCE(v_r.totalcapitalizedcost, -1);
    RAISE NOTICE 'B9. cost history rows      expect 2  got %',
        (SELECT COUNT(*)::integer FROM spwatercapitalassetcost_getall(v_farm, v_tank) c
          WHERE c.status = 'Posted');

    SELECT c.paymentmethod, c.cashaccountname, c.paymentstatus INTO v_r
    FROM   spwatercapitalassetcost_getall(v_farm, v_tank) c
    WHERE  c.sourcetype = 'AdditionalCost';
    RAISE NOTICE 'B10. how it was paid       expect Cash  got %', COALESCE(v_r.paymentmethod, 'NULL');
    RAISE NOTICE 'B11. which account         expect ZZ Composition Account  got %',
        COALESCE(v_r.cashaccountname, 'NULL');

    -- =====================================================================
    -- C. An asset BUILT from nothing has no acquisition to correct.
    -- =====================================================================
    v_built := spwatercapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Borehole Under Drilling',
        p_acquisitiondate => CURRENT_DATE, p_amount => NULL, p_createdby => 'ZZ tester');
    PERFORM spwatercapitalassetcost_add(
        p_farmid => v_farm, p_assetid => v_built, p_costdate => CURRENT_DATE,
        p_description => 'ZZ casing', p_costcategory => 'Materials', p_amount => 5000,
        p_paymentmethod => 'Cash', p_amountpaid => 5000, p_cashaccountid => v_acct,
        p_createdby => 'ZZ tester');

    SELECT g.acquisitioncost, g.additionalcost, g.totalcapitalizedcost INTO v_r
    FROM   spwatercapitalasset_getall(v_farm) g WHERE g.watercapitalassetid = v_built;
    RAISE NOTICE 'C1. built: acquisition     expect 0.00  got %',    COALESCE(v_r.acquisitioncost, -1);
    RAISE NOTICE 'C2. built: additional      expect 5000.00  got %', COALESCE(v_r.additionalcost, -1);
    RAISE NOTICE 'C3. built: total           expect 5000.00  got %', COALESCE(v_r.totalcapitalizedcost, -1);

    BEGIN
        PERFORM spwatercapitalasset_correctoriginalcost(
            v_farm, v_built, 9000, CURRENT_DATE, 'ZZ nothing to correct', 'ZZ tester');
        RAISE NOTICE 'C4. correcting a built asset  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'C4. correcting a built asset  expect REFUSED  got REFUSED (%)', left(SQLERRM, 45);
    END;

    -- =====================================================================
    -- D. THE CLAIM. 130,000 typed where the invoice said 13,000.
    -- =====================================================================
    SELECT a.currentbalance INTO v_bal0 FROM watercashaccounts a WHERE a.watercashaccountid = v_acct;

    v_typo := spwatercapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Mistyped Sachet Machine',
        p_acquisitiondate => CURRENT_DATE, p_amount => 130000,
        p_residualvalue => 0, p_usefullifemonths => 84,
        p_paymentmethod => 'Cash', p_amountpaid => 130000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    SELECT a.currentbalance INTO v_bal1 FROM watercashaccounts a WHERE a.watercashaccountid = v_acct;
    RAISE NOTICE 'D0. cash out as recorded   expect 130000.00  got %', COALESCE(v_bal0 - v_bal1, -1);

    PERFORM spwatercapitalasset_correctoriginalcost(
        v_farm, v_typo, 13000, CURRENT_DATE,
        'Original invoice amount was entered incorrectly', 'ZZ tester');

    SELECT g.acquisitioncost, g.additionalcost, g.totalcapitalizedcost, g.currentbookvalue INTO v_r
    FROM   spwatercapitalasset_getall(v_farm) g WHERE g.watercapitalassetid = v_typo;
    RAISE NOTICE 'D1. original acquisition   expect 13000.00  got %', COALESCE(v_r.acquisitioncost, -1);
    RAISE NOTICE 'D2. and nothing was added  expect 0.00  got %',     COALESCE(v_r.additionalcost, -1);
    RAISE NOTICE 'D3. total follows it       expect 13000.00  got %', COALESCE(v_r.totalcapitalizedcost, -1);
    RAISE NOTICE 'D4. book value follows too expect 13000.00  got %', COALESCE(v_r.currentbookvalue, -1);

    SELECT a.currentbalance INTO v_bal1 FROM watercashaccounts a WHERE a.watercashaccountid = v_acct;
    RAISE NOTICE 'D5. net cash out is now    expect 13000.00  got %', COALESCE(v_bal0 - v_bal1, -1);

    -- Water's ledger is append-only, so the correction did NOT rewrite the
    -- transaction that took the money: both legs are still readable.
    SELECT COUNT(*)::integer INTO v_n
    FROM   watercashtransactions t
    WHERE  t.farmid = v_farm AND t.sourcetype = 'Expense'
      AND  t.sourceid = (SELECT c.waterexpenseid FROM watercapitalassetcosts c
                          WHERE c.watercapitalassetid = v_typo AND c.sourcetype = 'Acquisition');
    RAISE NOTICE 'D5b. both cash legs kept   expect 2  got %', COALESCE(v_n, -1);

    -- ONE expense, not two: no duplicate cash movement, no duplicate supplier
    -- payment, no duplicate expense.
    RAISE NOTICE 'D6. expenses behind the asset  expect 1  got %',
        (SELECT COUNT(*)::integer FROM waterexpenses e
          WHERE e.farmid = v_farm AND e.watercapitalassetid = v_typo
            AND COALESCE(e.isdeleted, FALSE) = FALSE);
    RAISE NOTICE 'D7. and the bill now says  expect 13000.00  got %',
        (SELECT COALESCE(MAX(e.amount), -1) FROM waterexpenses e
          WHERE e.farmid = v_farm AND e.watercapitalassetid = v_typo
            AND COALESCE(e.isdeleted, FALSE) = FALSE);
    RAISE NOTICE 'D8. still excluded from profit  expect 0.00  got %',
        (SELECT COALESCE(SUM(r.amount), 0)::numeric(14,2) FROM fnwaterexpenserows(v_farm) r
          WHERE r.watercapitalassetid = v_typo AND r.plsection <> 'Excluded');

    SELECT c.amount, c.description, c.costcategory, c.createdby INTO v_r
    FROM   spwatercapitalassetcost_getall(v_farm, v_typo) c
    WHERE  c.sourcetype = 'OriginalCostCorrection';
    RAISE NOTICE 'D9. the correction row     expect -117000.00  got %', COALESCE(v_r.amount, -1);
    RAISE NOTICE 'D10. carries its reason    expect Original invoice...  got %',
        COALESCE(left(v_r.description, 24), 'NULL');
    RAISE NOTICE 'D11. and who made it       expect ZZ tester  got %', COALESCE(v_r.createdby, 'NULL');
    RAISE NOTICE 'D12. history keeps both    expect 2  got %',
        (SELECT COUNT(*)::integer FROM spwatercapitalassetcost_getall(v_farm, v_typo) c
          WHERE c.status = 'Posted');

    -- =====================================================================
    -- E. Correcting AFTER depreciation has been posted.
    -- =====================================================================
    v_dep := spwatercapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Depreciating Truck',
        p_acquisitiondate => (CURRENT_DATE - interval '2 months')::date,
        p_inservicedate   => (CURRENT_DATE - interval '2 months')::date,
        p_amount => 120000, p_residualvalue => 0, p_usefullifemonths => 120,
        p_paymentmethod => 'Cash', p_amountpaid => 120000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    PERFORM spwaterassetdepreciation_generate(v_farm, CURRENT_DATE, v_dep, 'ZZ tester');

    SELECT COUNT(*)::integer, COALESCE(SUM(d.amount), 0) INTO v_n, v_acc
    FROM   waterassetdepreciation d WHERE d.watercapitalassetid = v_dep;
    RAISE NOTICE 'E1. months charged         expect 3  got %', COALESCE(v_n, -1);
    RAISE NOTICE 'E2. at 1000.00 a month     expect 3000.00  got %', COALESCE(v_acc, -1);

    PERFORM spwatercapitalasset_correctoriginalcost(
        v_farm, v_dep, 60000, CURRENT_DATE, 'ZZ invoice was half that', 'ZZ tester');

    SELECT COUNT(*)::integer, COALESCE(SUM(d.amount), 0) INTO v_n, v_acc
    FROM   waterassetdepreciation d WHERE d.watercapitalassetid = v_dep;
    RAISE NOTICE 'E3. posted months UNCHANGED  expect 3  got %', COALESCE(v_n, -1);
    RAISE NOTICE 'E4. posted amount UNCHANGED  expect 3000.00  got %', COALESCE(v_acc, -1);
    RAISE NOTICE 'E5. and none was deleted    expect 3  got %',
        (SELECT COUNT(*)::integer FROM waterexpenses e
          WHERE e.farmid = v_farm AND e.sourcetype = 'AssetDepreciation'
            AND e.watercapitalassetid = v_dep AND COALESCE(e.isdeleted, FALSE) = FALSE);

    SELECT g.totalcapitalizedcost, g.monthlydepreciation, g.accumulateddepreciation,
           g.currentbookvalue, g.remainingdepreciable INTO v_r
    FROM   spwatercapitalasset_getall(v_farm) g WHERE g.watercapitalassetid = v_dep;
    RAISE NOTICE 'E6. cost is now            expect 60000.00  got %', COALESCE(v_r.totalcapitalizedcost, -1);
    RAISE NOTICE 'E7. future months halve    expect 500.00  got %',   COALESCE(v_r.monthlydepreciation, -1);
    RAISE NOTICE 'E8. accumulated stands     expect 3000.00  got %',  COALESCE(v_r.accumulateddepreciation, -1);
    RAISE NOTICE 'E9. book value = cost - dep  expect 57000.00  got %', COALESCE(v_r.currentbookvalue, -1);
    RAISE NOTICE 'E10. still to charge       expect 57000.00  got %',  COALESCE(v_r.remainingdepreciable, -1);

    -- =====================================================================
    -- F. Reversing ONE added cost.
    -- =====================================================================
    SELECT a.currentbalance INTO v_bal0 FROM watercashaccounts a WHERE a.watercashaccountid = v_acct;

    SELECT c.watercapitalassetcostid INTO v_cost
    FROM   spwatercapitalassetcost_getall(v_farm, v_tank) c
    WHERE  c.sourcetype = 'AdditionalCost' AND c.status = 'Posted';

    PERFORM spwatercapitalassetcost_reverse(
        v_farm, v_cost, 'ZZ entered against the wrong asset', 'ZZ tester', v_tank);

    SELECT g.acquisitioncost, g.additionalcost, g.totalcapitalizedcost INTO v_r
    FROM   spwatercapitalasset_getall(v_farm) g WHERE g.watercapitalassetid = v_tank;
    RAISE NOTICE 'F1. net additional cost    expect 0.00  got %',      COALESCE(v_r.additionalcost, -1);
    RAISE NOTICE 'F2. acquisition untouched  expect 100000.00  got %', COALESCE(v_r.acquisitioncost, -1);
    RAISE NOTICE 'F3. total back to          expect 100000.00  got %', COALESCE(v_r.totalcapitalizedcost, -1);

    SELECT c.status, c.reversalreason, c.reversedby INTO v_r
    FROM   spwatercapitalassetcost_getall(v_farm, v_tank) c
    WHERE  c.watercapitalassetcostid = v_cost;
    RAISE NOTICE 'F4. the row is kept        expect Reversed  got %', COALESCE(v_r.status, 'GONE');
    RAISE NOTICE 'F5. with its reason        expect ZZ entered aga...  got %',
        COALESCE(left(v_r.reversalreason, 17), 'NULL');

    SELECT a.currentbalance INTO v_bal1 FROM watercashaccounts a WHERE a.watercashaccountid = v_acct;
    RAISE NOTICE 'F6. the 20000 came back    expect 20000.00  got %', COALESCE(v_bal1 - v_bal0, -1);
    -- Soft delete, water's convention: the row stays, flagged.
    RAISE NOTICE 'F7. its expense is withdrawn  expect 1  got %',
        (SELECT COUNT(*)::integer FROM waterexpenses e
          WHERE e.farmid = v_farm AND e.watercapitalassetid = v_tank
            AND COALESCE(e.isdeleted, FALSE) = FALSE);

    -- =====================================================================
    -- G. The guards refuse rather than corrupt.
    -- =====================================================================
    BEGIN
        PERFORM spwatercapitalasset_correctoriginalcost(v_farm, v_tank, 90000, CURRENT_DATE, '', 'ZZ tester');
        RAISE NOTICE 'G1. correction with no reason  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G1. correction with no reason  expect REFUSED  got REFUSED';
    END;

    BEGIN
        PERFORM spwatercapitalasset_correctoriginalcost(v_farm, v_tank, 100000, CURRENT_DATE, 'ZZ same', 'ZZ tester');
        RAISE NOTICE 'G2. correcting to the same amount  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G2. correcting to the same amount  expect REFUSED  got REFUSED';
    END;

    BEGIN
        PERFORM spwatercapitalasset_correctoriginalcost(v_farm, v_tank, -5, CURRENT_DATE, 'ZZ negative', 'ZZ tester');
        RAISE NOTICE 'G3. correcting to a negative  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G3. correcting to a negative  expect REFUSED  got REFUSED';
    END;

    PERFORM spwatercapitalasset_update(
        p_farmid => v_farm, p_assetid => v_tank, p_assetname => 'ZZ Storage Tank',
        p_inservicedate => CURRENT_DATE, p_usefullifemonths => 96,
        p_residualvalue => 50000, p_setfinancials => TRUE, p_updatedby => 'ZZ tester');
    BEGIN
        PERFORM spwatercapitalasset_correctoriginalcost(v_farm, v_tank, 10000, CURRENT_DATE, 'ZZ under residual', 'ZZ tester');
        RAISE NOTICE 'G4. cost below residual value  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G4. cost below residual value  expect REFUSED  got REFUSED';
    END;

    SELECT c.watercapitalassetcostid INTO v_cost
    FROM   spwatercapitalassetcost_getall(v_farm, v_tank) c WHERE c.sourcetype = 'Acquisition';
    BEGIN
        PERFORM spwatercapitalassetcost_reverse(v_farm, v_cost, 'ZZ nope', 'ZZ tester', v_tank);
        RAISE NOTICE 'G5. reversing the acquisition  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G5. reversing the acquisition  expect REFUSED  got REFUSED';
    END;

    SELECT c.watercapitalassetcostid INTO v_cost
    FROM   spwatercapitalassetcost_getall(v_farm, v_typo) c
    WHERE  c.sourcetype = 'OriginalCostCorrection';
    BEGIN
        PERFORM spwatercapitalassetcost_reverse(v_farm, v_cost, 'ZZ nope', 'ZZ tester', v_typo);
        RAISE NOTICE 'G6. reversing a correction  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G6. reversing a correction  expect REFUSED  got REFUSED';
    END;

    -- 283's existing refusal, still in force: costs are frozen once a month has
    -- been charged. 314 must not have loosened it.
    BEGIN
        PERFORM spwatercapitalassetcost_add(
            p_farmid => v_farm, p_assetid => v_dep, p_costdate => CURRENT_DATE,
            p_description => 'ZZ late cost', p_costcategory => 'Improvement',
            p_amount => 1000, p_paymentmethod => 'Cash', p_amountpaid => 1000,
            p_cashaccountid => v_acct, p_createdby => 'ZZ tester');
        RAISE NOTICE 'G7. adding cost after depreciation  expect REFUSED  got ALLOWED';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'G7. adding cost after depreciation  expect REFUSED  got REFUSED';
    END;

    SELECT c.watercapitalassetcostid INTO v_cost
    FROM   spwatercapitalassetcost_getall(v_farm, v_built) c WHERE c.status = 'Posted' LIMIT 1;
    BEGIN
        PERFORM spwatercapitalassetcost_reverse(v_farm, v_cost, 'ZZ wrong asset', 'ZZ tester', v_tank);
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
            PERFORM spwatercapitalasset_correctoriginalcost(
                v_other, v_tank, 90000, CURRENT_DATE, 'ZZ other company', 'ZZ tester');
            RAISE NOTICE 'H1. correcting another company''s asset  expect REFUSED  got ALLOWED';
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'H1. correcting another company''s asset  expect REFUSED  got REFUSED';
        END;
        RAISE NOTICE 'H2. and it is untouched    expect 100000.00  got %',
            COALESCE(fnwatercapitalasset_acquisitioncost(v_tank), -1);
    ELSE
        RAISE NOTICE 'H1. no second company on this database -- scoping not exercised';
        RAISE NOTICE 'H2. no second company on this database -- scoping not exercised';
    END IF;

    -- =====================================================================
    -- I. And the identity still holds, over everything this file created.
    -- =====================================================================
    SELECT COUNT(*)::integer INTO v_n
    FROM   watercapitalassets a
    WHERE  ROUND(fnwatercapitalasset_acquisitioncost(a.watercapitalassetid)
               + fnwatercapitalasset_additionalcost(a.watercapitalassetid), 2)
        <> ROUND(fnwatercapitalasset_originalcost(a.watercapitalassetid), 2);
    RAISE NOTICE 'I1. halves still add to the whole  expect 0  got %', COALESCE(v_n, -1);

    RAISE NOTICE '--- 58 numbered assertions expected above (A1-I1). Each guard prints exactly';
    RAISE NOTICE '--- one of its two branches. A blank "got" is a FAILURE, not a pass. ---';
END;
$t$;

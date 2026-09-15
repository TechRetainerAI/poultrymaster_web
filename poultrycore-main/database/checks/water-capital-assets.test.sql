-- Behavioural checks for migration 283: the water Asset Register.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates suppliers, cash accounts and assets.
--
--   psql ... -X -c "BEGIN;" -f water-capital-assets.test.sql -c "ROLLBACK;"
--
-- Suppliers and cash accounts are inserted DIRECTLY rather than through their
-- SPs, for the reason 274's checks give: the live Postgres bodies of the water
-- writers are not in this repo, so calling them would couple these checks to
-- signatures this workstream has not read. The column lists come from 047 and
-- 076. The whole block is rolled back.
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **A borehole does not make the company look bankrupt.** Section B buys one for
-- 600,000 on credit, pays 100,000, and asserts all four numbers at once: the
-- asset is worth 600,000, cash fell by 100,000, the supplier is owed 500,000,
-- and the amount charged against profit is ZERO. Today the same purchase would
-- land 600,000 in Operating Expenses and turn a profitable month into a
-- catastrophic loss.
--
-- Section B2 is the water-specific half of that claim and the one poultry has no
-- equivalent for: 240 excluded every expense carrying a sourcetype from
-- fnwaterpayables, so before 283 widened that filter the 500,000 would have been
-- owed to a supplier the system could not show. The check asserts the debt is
-- actually visible, and B7 asserts the recursion 240 was guarding against did
-- not come back with it.
--
-- The rest:
--   1. A cash purchase moves cash and nothing else.
--   2. Paying the supplier later adds NO new cost -- the acquisition is not
--      charged twice.
--   3. An asset is BUILT: original cost is the sum of its cost rows, so drilling
--      plus pump plus casing plus wiring is one asset, not four expenses.
--   4. The guards refuse rather than corrupt: no reversal once a supplier has
--      been paid, no cost added once depreciation has run, no residual value
--      above the cost, no in-service date before acquisition.
--   5. Reversal with nothing downstream hands the cash back and keeps the row.
--   6. Disposal proceeds are CASH IN and are not revenue.

DO $t$
DECLARE
    v_farm  text;
    v_supp  integer;
    v_acct  integer;
    v_cat   integer;
    v_pump integer; v_hole integer; v_build integer; v_gen integer;
    v_bal0 numeric; v_bal1 numeric;
    v_exp  integer;
    v_r    record;
BEGIN
    SELECT f.farmid INTO v_farm
    FROM   farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No water company to test against.'; END IF;
    RAISE NOTICE '   using water company %', v_farm;

    INSERT INTO watersuppliers (farmid, suppliername, isactive, isdeleted)
    VALUES (v_farm, 'ZZ Drillers Ltd', TRUE, FALSE)
    RETURNING watersupplierid INTO v_supp;

    INSERT INTO watercashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, isactive)
    VALUES (v_farm, 'ZZ Asset Account', 'Bank', 2000000, 2000000, TRUE)
    RETURNING watercashaccountid INTO v_acct;

    -- =====================================================================
    -- A. Categories seed themselves, once.
    -- =====================================================================
    RAISE NOTICE 'A1. categories seeded      expect 15  got %',
        (SELECT COUNT(*)::integer FROM spwaterassetcategory_getall(v_farm));
    -- Reading twice must not double them: the register calls this on every load.
    PERFORM spwaterassetcategory_getall(v_farm);
    RAISE NOTICE 'A2. and only once          expect 15  got %',
        (SELECT COUNT(*)::integer FROM spwaterassetcategory_getall(v_farm));
    -- The list is water's, not poultry's.
    RAISE NOTICE 'A3. boreholes are in it    expect        t  got %',
        EXISTS (SELECT 1 FROM spwaterassetcategory_getall(v_farm)
                 WHERE categoryname = 'Boreholes / Water Source');
    RAISE NOTICE 'A4. no poultry houses      expect        f  got %',
        EXISTS (SELECT 1 FROM spwaterassetcategory_getall(v_farm)
                 WHERE categoryname ILIKE '%poultry%');

    SELECT waterassetcategoryid INTO v_cat FROM spwaterassetcategory_getall(v_farm)
     WHERE categoryname = 'Boreholes / Water Source';

    -- =====================================================================
    -- B. THE CLAIM. A borehole on credit, part paid.
    -- =====================================================================
    SELECT currentbalance INTO v_bal0 FROM watercashaccounts WHERE watercashaccountid = v_acct;

    v_hole := spwatercapitalasset_create(
        p_farmid           => v_farm,
        p_assetname        => 'ZZ Borehole 1',
        p_assetcategoryid  => v_cat,
        p_acquisitiondate  => CURRENT_DATE,
        p_inservicedate    => CURRENT_DATE,
        p_amount           => 600000,
        p_residualvalue    => 0,
        p_usefullifemonths => 240,
        p_supplierid       => v_supp,
        p_paymentmethod    => 'Credit',
        p_amountpaid       => 100000,
        p_cashaccountid    => v_acct,
        p_createdby        => 'ZZ tester');

    SELECT * INTO v_r FROM spwatercapitalasset_getall(v_farm)
     WHERE watercapitalassetid = v_hole;

    RAISE NOTICE 'B1. the asset is worth it  expect 600000.00  got %', v_r.originalcost;

    -- The water-specific half. Before 283 this expense carried a sourcetype and
    -- fnwaterpayables would have hidden the debt entirely.
    RAISE NOTICE 'B2. the supplier is owed   expect 500000.00  got %',
        (SELECT COALESCE(SUM(p.balance), 0)::numeric(14,2) FROM fnwaterpayables(v_farm) p
          WHERE p.documenttype = 'Expense' AND p.supplierid = v_supp);

    SELECT currentbalance INTO v_bal1 FROM watercashaccounts WHERE watercashaccountid = v_acct;
    RAISE NOTICE 'B3. cash fell by the paid part expect 100000.00  got %', (v_bal0 - v_bal1);

    -- The point of the entire workstream: none of it is a cost of this period.
    RAISE NOTICE 'B4. charged against profit expect     0.00  got %',
        (SELECT COALESCE(SUM(r.amount), 0)::numeric(14,2) FROM fnwaterexpenserows(v_farm) r
          WHERE r.watercapitalassetid = v_hole AND r.plsection <> 'Excluded');
    RAISE NOTICE 'B5. and it is classified capital expect CapitalAsset  got %',
        (SELECT r.financialcosttype FROM fnwaterexpenserows(v_farm) r
          WHERE r.watercapitalassetid = v_hole LIMIT 1);
    RAISE NOTICE 'B6. the expense names the asset expect ZZ Borehole 1  got %',
        (SELECT r.capitalassetname FROM fnwaterexpenserows(v_farm) r
          WHERE r.watercapitalassetid = v_hole LIMIT 1);

    -- 240's anti-recursion rule must still hold for everything it was written
    -- for: a supplier-payment shadow row is still NOT a payable.
    RAISE NOTICE 'B7. payment shadows still hidden expect        0  got %',
        (SELECT COUNT(*)::integer FROM fnwaterpayables(v_farm) p
          JOIN waterexpenses e ON e.waterexpenseid = p.documentid
         WHERE p.documenttype = 'Expense'
           AND e.sourcetype = 'WaterSupplierPayment');

    -- Book value at the start of life is the whole cost.
    RAISE NOTICE 'B8. book value = cost      expect 600000.00  got %', v_r.currentbookvalue;
    RAISE NOTICE 'B9. status is Active       expect   Active  got %', v_r.status;
    RAISE NOTICE 'B10. monthly charge        expect  2500.00  got %', v_r.monthlydepreciation;

    -- =====================================================================
    -- C. A cash purchase moves cash and nothing else.
    -- =====================================================================
    SELECT currentbalance INTO v_bal0 FROM watercashaccounts WHERE watercashaccountid = v_acct;

    v_gen := spwatercapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Generator',
        p_acquisitiondate => CURRENT_DATE, p_inservicedate => CURRENT_DATE,
        p_amount => 80000, p_usefullifemonths => 84,
        p_paymentmethod => 'Cash', p_cashaccountid => v_acct,
        p_createdby => 'ZZ tester');

    SELECT currentbalance INTO v_bal1 FROM watercashaccounts WHERE watercashaccountid = v_acct;
    RAISE NOTICE 'C1. cash fell by the whole cost expect 80000.00  got %', (v_bal0 - v_bal1);
    -- No supplier means nothing is owed.
    RAISE NOTICE 'C2. nothing is owed on it  expect        0  got %',
        (SELECT COUNT(*)::integer FROM fnwaterpayables(v_farm) p
          JOIN waterexpenses e ON e.waterexpenseid = p.documentid
         WHERE p.documenttype = 'Expense' AND e.watercapitalassetid = v_gen);
    -- Water's ledger is signed: an outflow is negative.
    RAISE NOTICE 'C3. the cash row is negative expect        t  got %',
        (SELECT SUM(t.amount) < 0 FROM watercashtransactions t
          WHERE t.farmid = v_farm AND t.sourcetype = 'Expense'
            AND t.sourceid IN (SELECT waterexpenseid FROM waterexpenses
                                WHERE watercapitalassetid = v_gen));

    -- =====================================================================
    -- D. An asset is BUILT. Cost is the sum of its rows.
    -- =====================================================================
    v_build := spwatercapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Treatment Plant',
        p_acquisitiondate => CURRENT_DATE, p_createdby => 'ZZ tester');

    RAISE NOTICE 'D1. starts Draft at zero   expect    Draft  got %',
        (SELECT status FROM spwatercapitalasset_getall(v_farm) WHERE watercapitalassetid = v_build);
    RAISE NOTICE 'D2. and costs nothing yet  expect     0.00  got %',
        fnwatercapitalasset_originalcost(v_build);

    PERFORM spwatercapitalassetcost_add(v_farm, v_build, CURRENT_DATE, 'Tanks',    'Materials', 40000,
                                        NULL, 'Cash', NULL, NULL, v_acct, NULL, 'ZZ tester');
    PERFORM spwatercapitalassetcost_add(v_farm, v_build, CURRENT_DATE, 'Filters',  'Materials', 25000,
                                        NULL, 'Cash', NULL, NULL, v_acct, NULL, 'ZZ tester');
    PERFORM spwatercapitalassetcost_add(v_farm, v_build, CURRENT_DATE, 'Plumbing', 'Labour',    15000,
                                        NULL, 'Cash', NULL, NULL, v_acct, NULL, 'ZZ tester');

    RAISE NOTICE 'D3. cost is the sum        expect 80000.00  got %',
        fnwatercapitalasset_originalcost(v_build);
    RAISE NOTICE 'D4. three cost rows        expect        3  got %',
        (SELECT COUNT(*)::integer FROM spwatercapitalassetcost_getall(v_farm, v_build));
    -- D4b/D4c pin the bug the first run of this file found. waterexpenses has a
    -- unique index on (farmid, sourcetype, sourceid) WHERE sourcetype IS NOT
    -- NULL AND isdeleted = false. Keying every capitalised cost on the ASSET id
    -- let the first cost through and rejected the second, which broke the whole
    -- construction workflow. Each cost now keys on its own cost-row id.
    RAISE NOTICE 'D4b. each cost has its own expense expect        3  got %',
        (SELECT COUNT(DISTINCT e.sourceid)::integer FROM waterexpenses e
          WHERE e.watercapitalassetid = v_build
            AND e.sourcetype = 'CapitalAssetCost'
            AND COALESCE(e.isdeleted, FALSE) = FALSE);
    -- And each expense points back at the cost row that owns it.
    RAISE NOTICE 'D4c. sourceid names the cost row expect        0  got %',
        (SELECT COUNT(*)::integer FROM waterexpenses e
          WHERE e.watercapitalassetid = v_build
            AND e.sourcetype = 'CapitalAssetCost'
            AND COALESCE(e.isdeleted, FALSE) = FALSE
            AND NOT EXISTS (SELECT 1 FROM watercapitalassetcosts c
                            WHERE c.watercapitalassetcostid = e.sourceid
                              AND c.waterexpenseid = e.waterexpenseid));
    -- Three costs, one asset -- and none of the three is a cost of the period.
    RAISE NOTICE 'D5. still nothing in profit expect     0.00  got %',
        (SELECT COALESCE(SUM(r.amount), 0)::numeric(14,2) FROM fnwaterexpenserows(v_farm) r
          WHERE r.watercapitalassetid = v_build AND r.plsection <> 'Excluded');
    -- Setting a life and a date is what commissions it.
    PERFORM spwatercapitalasset_update(
        v_farm, v_build, 'ZZ Treatment Plant', NULL, NULL, NULL, NULL, NULL,
        CURRENT_DATE, 120, 0, TRUE, 'ZZ tester');
    RAISE NOTICE 'D6. commissioning makes it Active expect   Active  got %',
        (SELECT status FROM spwatercapitalasset_getall(v_farm) WHERE watercapitalassetid = v_build);

    -- =====================================================================
    -- E. Reversal hands the cash back and keeps the row.
    -- =====================================================================
    v_pump := spwatercapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Spare Pump',
        p_acquisitiondate => CURRENT_DATE, p_amount => 5000,
        p_paymentmethod => 'Cash', p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    SELECT currentbalance INTO v_bal0 FROM watercashaccounts WHERE watercashaccountid = v_acct;
    PERFORM spwatercapitalasset_reverse(v_farm, v_pump, 'Entered twice', 'ZZ tester');
    SELECT currentbalance INTO v_bal1 FROM watercashaccounts WHERE watercashaccountid = v_acct;

    RAISE NOTICE 'E1. cash came back         expect  5000.00  got %', (v_bal1 - v_bal0);
    RAISE NOTICE 'E2. the asset is kept, Reversed expect Reversed  got %',
        (SELECT status FROM watercapitalassets WHERE watercapitalassetid = v_pump);
    -- Soft-deleted, not hard-deleted: water keeps the row and filters it.
    RAISE NOTICE 'E3. its expense is gone from reads expect        0  got %',
        (SELECT COUNT(*)::integer FROM fnwaterexpenserows(v_farm) r
          WHERE r.watercapitalassetid = v_pump);
    RAISE NOTICE 'E4. but the row still exists expect        t  got %',
        EXISTS (SELECT 1 FROM waterexpenses WHERE watercapitalassetid = v_pump);
    RAISE NOTICE 'E5. and it owes nobody     expect        0  got %',
        (SELECT COUNT(*)::integer FROM fnwaterpayables(v_farm) p
          JOIN waterexpenses e ON e.waterexpenseid = p.documentid
         WHERE e.watercapitalassetid = v_pump);

    -- =====================================================================
    -- F. Disposal proceeds are CASH IN and are not revenue.
    -- =====================================================================
    SELECT currentbalance INTO v_bal0 FROM watercashaccounts WHERE watercashaccountid = v_acct;
    PERFORM spwatercapitalasset_dispose(v_farm, v_gen, CURRENT_DATE, 30000, v_acct,
                                        'Sold to a neighbour', 'ZZ tester');
    SELECT currentbalance INTO v_bal1 FROM watercashaccounts WHERE watercashaccountid = v_acct;

    RAISE NOTICE 'F1. proceeds reached cash  expect 30000.00  got %', (v_bal1 - v_bal0);
    RAISE NOTICE 'F2. status is Disposed     expect Disposed  got %',
        (SELECT status FROM spwatercapitalasset_getall(v_farm) WHERE watercapitalassetid = v_gen);
    -- Selling a machine is not trading income.
    RAISE NOTICE 'F3. no sale was created    expect        0  got %',
        (SELECT COUNT(*)::integer FROM watercashtransactions t
          WHERE t.farmid = v_farm AND t.sourcetype = 'AssetDisposal' AND t.sourceid = v_gen
            AND t.transactiontype <> 'CashIn');

    -- =====================================================================
    -- G. The summary adds up.
    -- =====================================================================
    SELECT * INTO v_r FROM spwatercapitalasset_summary(v_farm, NULL, NULL);
    RAISE NOTICE 'G1. reversed assets excluded expect        f  got %',
        EXISTS (SELECT 1 FROM spwatercapitalasset_getall(v_farm) a
                 WHERE a.watercapitalassetid = v_pump AND v_r.totalassets = 0);
    RAISE NOTICE 'G2. book value = cost - depreciation expect        t  got %',
        (v_r.currentbookvalue = v_r.totalassetcost - v_r.accumulateddepreciation);
END
$t$;

-- =============================================================================
-- Negative cases. Each must be BLOCKED.
-- =============================================================================
DO $n$
DECLARE
    v_farm  text;
    v_other text;
    v_acct  integer;
    v_asset integer;
    v_cat   integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;

    SELECT watercashaccountid INTO v_acct FROM watercashaccounts
     WHERE farmid = v_farm AND accountname = 'ZZ Asset Account';

    SELECT watercapitalassetid INTO v_asset FROM watercapitalassets
     WHERE farmid = v_farm AND assetname = 'ZZ Borehole 1';

    BEGIN
        PERFORM spwatercapitalasset_create(
            p_farmid => v_farm, p_assetname => '', p_amount => 100, p_createdby => 'ZZ tester');
        RAISE NOTICE 'N1. an unnamed asset       <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N1. an unnamed asset       blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spwatercapitalasset_create(
            p_farmid => v_farm, p_assetname => 'ZZ Bad', p_amount => -5, p_createdby => 'ZZ tester');
        RAISE NOTICE 'N2. a negative cost        <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N2. a negative cost        blocked: %', SQLERRM;
    END;

    -- In service before it was acquired.
    BEGIN
        PERFORM spwatercapitalasset_create(
            p_farmid => v_farm, p_assetname => 'ZZ Early',
            p_acquisitiondate => CURRENT_DATE,
            p_inservicedate => CURRENT_DATE - 30, p_createdby => 'ZZ tester');
        RAISE NOTICE 'N3. in service before acquired <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N3. in service before acquired blocked: %', SQLERRM;
    END;

    -- Residual above the cost would make depreciation negative.
    BEGIN
        PERFORM spwatercapitalasset_update(
            v_farm, v_asset, 'ZZ Borehole 1', NULL, NULL, NULL, NULL, NULL,
            CURRENT_DATE, 240, 900000, TRUE, 'ZZ tester');
        RAISE NOTICE 'N4. residual above cost    <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N4. residual above cost    blocked: %', SQLERRM;
    END;

    -- A category from another company must not be attachable.
    SELECT f.farmid INTO v_other FROM farms f
     WHERE f.type = 'Water' AND f.farmid <> v_farm ORDER BY f.farmid LIMIT 1;
    IF v_other IS NULL THEN
        RAISE NOTICE 'N5. a category from elsewhere skipped: only one water company exists';
    ELSE
        PERFORM spwaterassetcategory_getall(v_other);
        SELECT waterassetcategoryid INTO v_cat FROM waterassetcategories
         WHERE farmid = v_other ORDER BY waterassetcategoryid LIMIT 1;
        BEGIN
            PERFORM spwatercapitalasset_create(
                p_farmid => v_farm, p_assetname => 'ZZ Cross', p_assetcategoryid => v_cat,
                p_createdby => 'ZZ tester');
            RAISE NOTICE 'N5. a category from elsewhere <-- BUG, allowed';
        EXCEPTION WHEN others THEN
            RAISE NOTICE 'N5. a category from elsewhere blocked: %', SQLERRM;
        END;
    END IF;

    -- A supplier from another company, likewise.
    BEGIN
        PERFORM spwatercapitalasset_create(
            p_farmid => v_farm, p_assetname => 'ZZ BadSupp', p_amount => 10,
            p_supplierid => -1, p_createdby => 'ZZ tester');
        RAISE NOTICE 'N6. an unknown supplier    <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N6. an unknown supplier    blocked: %', SQLERRM;
    END;

    -- Reversal once a supplier payment exists would strand the payment.
    -- Simulated by writing the allocation the payment rail would have written.
    BEGIN
        INSERT INTO supplierpaymentallocation
            (farmid, module, paymentid, documenttype, documentid, amountapplied, status)
        SELECT v_farm, 'water', 999999, 'Expense', c.waterexpenseid, 1, 'Posted'
        FROM   watercapitalassetcosts c
        WHERE  c.watercapitalassetid = v_asset AND c.status = 'Posted'
        LIMIT  1;

        PERFORM spwatercapitalasset_reverse(v_farm, v_asset, 'Changed my mind', 'ZZ tester');
        RAISE NOTICE 'N7. reversal after a payment <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N7. reversal after a payment blocked: %', SQLERRM;
    END;

    -- A reversal with no reason leaves no audit trail.
    BEGIN
        PERFORM spwatercapitalasset_reverse(v_farm, v_asset, '   ', 'ZZ tester');
        RAISE NOTICE 'N8. a reversal with no reason <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N8. a reversal with no reason blocked: %', SQLERRM;
    END;

    -- Proceeds with nowhere to put them.
    BEGIN
        PERFORM spwatercapitalasset_dispose(v_farm, v_asset, CURRENT_DATE, 500, NULL,
                                            NULL, 'ZZ tester');
        RAISE NOTICE 'N9. proceeds with no account <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N9. proceeds with no account blocked: %', SQLERRM;
    END;

    -- Paying more than the asset cost.
    BEGIN
        PERFORM spwatercapitalasset_create(
            p_farmid => v_farm, p_assetname => 'ZZ Overpaid', p_amount => 100,
            p_paymentmethod => 'Cash', p_amountpaid => 500, p_cashaccountid => v_acct,
            p_createdby => 'ZZ tester');
        RAISE NOTICE 'N10. paying more than it cost <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N10. paying more than it cost blocked: %', SQLERRM;
    END;

    -- The table refuses a zero-value cost row, so a direct write cannot get
    -- round the SP.
    BEGIN
        INSERT INTO watercapitalassetcosts
            (farmid, watercapitalassetid, costdate, amount, sourcetype)
        VALUES (v_farm, v_asset, CURRENT_DATE, 0, 'AdditionalCost');
        RAISE NOTICE 'N11. a zero-value cost row <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N11. a zero-value cost row blocked: %', SQLERRM;
    END;
END
$n$;

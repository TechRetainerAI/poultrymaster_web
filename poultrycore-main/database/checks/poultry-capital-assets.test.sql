-- Behavioural checks for migration 270: the Asset Register.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates suppliers, cash accounts and assets.
--
--   psql ... -X -c "BEGIN;" -f poultry-capital-assets.test.sql -c "ROLLBACK;"
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **A poultry house does not make the farm look bankrupt.** Section B buys one
-- for 600,000 on credit, pays 100,000, and asserts all four numbers at once:
-- the asset is worth 600,000, cash fell by 100,000, the supplier is owed
-- 500,000, and the amount charged against profit is ZERO. Today the same
-- purchase would land 600,000 in Operating Expenses and turn a profitable month
-- into a catastrophic loss.
--
-- The rest:
--   1. A cash purchase (§79) moves cash and nothing else.
--   2. Paying the supplier later adds NO new cost -- the acquisition is not
--      charged twice.
--   3. An asset is BUILT: original cost is the sum of its cost rows, so cement
--      plus wood plus labour plus roofing is one asset, not four expenses.
--   4. The guards refuse rather than corrupt: no reversal once a supplier has
--      been paid, no cost added once depreciation has run, no residual value
--      above the cost, no in-service date before acquisition.
--   5. Reversal with nothing downstream hands the cash back and keeps the row.
--   6. Disposal proceeds are CASH IN and are not revenue.

DO $t$
DECLARE
    v_farm text;
    v_uuid uuid;
    v_supp integer;
    v_acct integer;
    v_cat  integer;
    v_mixer integer; v_house integer; v_build integer; v_gen integer;
    v_bal0 numeric; v_bal1 numeric;
    v_exp integer;
    v_r record;
BEGIN
    SELECT f.farmid INTO v_farm
    FROM   farms f
    WHERE  f.type = 'Poultry'
      AND  f.farmid ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ORDER  BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No uuid-shaped poultry company to test against.'; END IF;
    v_uuid := v_farm::uuid;
    RAISE NOTICE '   using poultry farm %', v_farm;

    v_supp := spsupplier_insert('ZZ tester', v_farm, 'ZZ Builders Ltd', NULL, NULL, NULL, NULL);
    v_acct := sppoultrycashaccount_insert(v_farm, 'ZZ Asset Account', 'Bank', 2000000, TRUE, NULL);

    -- =====================================================================
    -- A. Categories seed themselves, once.
    -- =====================================================================
    RAISE NOTICE 'A1. categories seeded      expect 13  got %',
        (SELECT COUNT(*)::integer FROM sppoultryassetcategory_getall(v_farm));
    -- Reading twice must not double them: the register calls this on every load.
    PERFORM sppoultryassetcategory_getall(v_farm);
    RAISE NOTICE 'A2. and only once          expect 13  got %',
        (SELECT COUNT(*)::integer FROM poultryassetcategories c WHERE c.farmid = v_farm);

    SELECT g.poultryassetcategoryid INTO v_cat
    FROM   sppoultryassetcategory_getall(v_farm) g WHERE g.categoryname = 'Feed Equipment';
    RAISE NOTICE 'A3. a default life is offered expect 84  got %',
        (SELECT g.defaultusefullifemonths FROM sppoultryassetcategory_getall(v_farm) g
          WHERE g.poultryassetcategoryid = v_cat);

    -- =====================================================================
    -- B. §79 -- a feed mixer bought for cash.
    -- =====================================================================
    SELECT a.currentbalance INTO v_bal0 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;

    v_mixer := sppoultrycapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Feed Mixer',
        p_assetcategoryid => v_cat, p_acquisitiondate => CURRENT_DATE,
        p_inservicedate => CURRENT_DATE, p_amount => 120000,
        p_residualvalue => 0, p_usefullifemonths => 60,
        p_paymentmethod => 'Cash', p_amountpaid => 120000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    SELECT * INTO v_r FROM sppoultrycapitalasset_getall(v_farm) g
    WHERE  g.poultrycapitalassetid = v_mixer;
    RAISE NOTICE 'B1. asset cost             expect 120000.00  got %', v_r.originalcost;
    RAISE NOTICE 'B2. book value untouched   expect 120000.00  got %', v_r.currentbookvalue;
    RAISE NOTICE 'B3. monthly depreciation   expect 2000.00  got %', v_r.monthlydepreciation;
    RAISE NOTICE 'B4. in service, so Active  expect Active  got %', v_r.status;
    RAISE NOTICE 'B5. it has a number        expect AST-  got %', left(v_r.assetnumber, 4);

    SELECT a.currentbalance INTO v_bal1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    RAISE NOTICE 'B6. cash fell by 120000    expect 120000.00  got %', (v_bal0 - v_bal1);

    -- The expense row exists -- that is how the cash moved -- and it is EXCLUDED
    -- from profit. Both halves matter: without the row there is no cash, and
    -- without the exclusion the farm reports a 120,000 loss.
    SELECT e.financialcosttype, e.plsection, e.amount INTO v_r
    FROM   fnpoultryexpenserows(v_uuid) e WHERE e.poultrycapitalassetid = v_mixer;
    RAISE NOTICE 'B7. classified capital     expect CapitalAsset  got %', v_r.financialcosttype;
    RAISE NOTICE 'B8. excluded from profit   expect Excluded  got %', v_r.plsection;

    -- =====================================================================
    -- C. THE CLAIM. §80 -- a poultry house on credit, all four numbers.
    -- =====================================================================
    SELECT a.currentbalance INTO v_bal0 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;

    v_house := sppoultrycapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Poultry House 4',
        p_acquisitiondate => CURRENT_DATE, p_amount => 600000,
        p_residualvalue => 0, p_usefullifemonths => 120,
        p_supplier => 'ZZ Builders Ltd', p_supplierid => v_supp,
        p_paymentmethod => 'Cash', p_amountpaid => 100000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    RAISE NOTICE 'C1. the asset is worth     expect 600000.00  got %',
        fnpoultrycapitalasset_originalcost(v_house);

    SELECT a.currentbalance INTO v_bal1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    RAISE NOTICE 'C2. cash out is only       expect 100000.00  got %', (v_bal0 - v_bal1);

    SELECT e.balance, e.paymentstatus, e.plsection INTO v_r
    FROM   fnpoultryexpenserows(v_uuid) e WHERE e.poultrycapitalassetid = v_house;
    RAISE NOTICE 'C3. the supplier is owed   expect 500000.00  got %', v_r.balance;
    RAISE NOTICE 'C4. and the bill says so   expect PartiallyPaid  got %', v_r.paymentstatus;
    -- The number this whole phase exists for.
    RAISE NOTICE 'C5. charged against profit expect Excluded  got %', v_r.plsection;

    -- Not in service yet -- a house with no in-service date is not earning.
    RAISE NOTICE 'C6. no service date, Draft expect Draft  got %',
        (SELECT g.status FROM sppoultrycapitalasset_getall(v_farm) g WHERE g.poultrycapitalassetid = v_house);

    -- =====================================================================
    -- D. Paying the supplier later adds NO new cost.
    -- =====================================================================
    SELECT c.expenseid INTO v_exp FROM poultrycapitalassetcosts c
    WHERE  c.poultrycapitalassetid = v_house AND c.status = 'Posted' LIMIT 1;

    PERFORM sppoultrysupplierpayment_record(
        v_farm, v_supp, 200000,
        jsonb_build_array(jsonb_build_object('documenttype', 'Expense', 'documentid', v_exp, 'amount', 200000)),
        'Cash', (now() at time zone 'utc'), v_acct, NULL, 'ZZ part payment',
        'SupplierPaymentsPage', 'ZZ tester');

    RAISE NOTICE 'D1. still worth            expect 600000.00  got %',
        fnpoultrycapitalasset_originalcost(v_house);
    RAISE NOTICE 'D2. owed drops to          expect 300000.00  got %',
        (SELECT e.balance FROM fnpoultryexpenserows(v_uuid) e WHERE e.poultrycapitalassetid = v_house);
    -- One cost row, one expense row. Paying did not create a second of either.
    RAISE NOTICE 'D3. still one cost row     expect 1  got %',
        (SELECT COUNT(*)::integer FROM poultrycapitalassetcosts c
          WHERE c.poultrycapitalassetid = v_house AND c.status = 'Posted');
    RAISE NOTICE 'D4. and one expense row    expect 1  got %',
        (SELECT COUNT(*)::integer FROM expense e WHERE e.poultrycapitalassetid = v_house);

    -- =====================================================================
    -- E. §12 -- an asset that is BUILT, not bought.
    -- =====================================================================
    v_build := sppoultrycapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ New House Under Construction',
        p_acquisitiondate => CURRENT_DATE, p_createdby => 'ZZ tester');

    RAISE NOTICE 'E1. starts at nothing      expect 0.00  got %',
        fnpoultrycapitalasset_originalcost(v_build);
    RAISE NOTICE 'E2. and is a Draft         expect Draft  got %',
        (SELECT g.status FROM sppoultrycapitalasset_getall(v_farm) g WHERE g.poultrycapitalassetid = v_build);

    PERFORM sppoultrycapitalassetcost_add(v_farm, v_build, CURRENT_DATE, 'Cement', 'Materials',
                                          100000, NULL, NULL, 'Cash', 100000, NULL, v_acct, NULL, 'ZZ tester');
    PERFORM sppoultrycapitalassetcost_add(v_farm, v_build, CURRENT_DATE, 'Wood', 'Materials',
                                          80000, NULL, NULL, 'Cash', 80000, NULL, v_acct, NULL, 'ZZ tester');
    PERFORM sppoultrycapitalassetcost_add(v_farm, v_build, CURRENT_DATE, 'Labour', 'Labour',
                                          120000, NULL, NULL, 'Cash', 120000, NULL, v_acct, NULL, 'ZZ tester');
    PERFORM sppoultrycapitalassetcost_add(v_farm, v_build, CURRENT_DATE, 'Roofing', 'Materials',
                                          150000, NULL, NULL, 'Cash', 150000, NULL, v_acct, NULL, 'ZZ tester');
    PERFORM sppoultrycapitalassetcost_add(v_farm, v_build, CURRENT_DATE, 'Electrical', 'Materials',
                                          50000, NULL, NULL, 'Cash', 50000, NULL, v_acct, NULL, 'ZZ tester');

    -- The brief's own example, to the cedi.
    RAISE NOTICE 'E3. five costs, one asset  expect 500000.00  got %',
        fnpoultrycapitalasset_originalcost(v_build);
    RAISE NOTICE 'E4. and five cost rows     expect 5  got %',
        (SELECT COUNT(*)::integer FROM poultrycapitalassetcosts c
          WHERE c.poultrycapitalassetid = v_build AND c.status = 'Posted');
    -- Not one cedi of that reached profit.
    RAISE NOTICE 'E5. none of it is profit   expect 0  got %',
        (SELECT COUNT(*)::integer FROM fnpoultryexpenserows(v_uuid) e
          WHERE e.poultrycapitalassetid = v_build AND e.plsection <> 'Excluded');

    -- Put it into service; now it depreciates.
    PERFORM sppoultrycapitalasset_update(
        p_farmid => v_farm, p_assetid => v_build, p_assetname => NULL,
        p_inservicedate => CURRENT_DATE, p_usefullifemonths => 120,
        p_residualvalue => 0, p_setfinancials => TRUE, p_updatedby => 'ZZ tester');

    SELECT * INTO v_r FROM sppoultrycapitalasset_getall(v_farm) g WHERE g.poultrycapitalassetid = v_build;
    RAISE NOTICE 'E6. in service, so Active  expect Active  got %', v_r.status;
    RAISE NOTICE 'E7. 500000 over 120 months expect 4166.67  got %', v_r.monthlydepreciation;

    -- =====================================================================
    -- F. The guards refuse rather than corrupt.
    -- =====================================================================
    BEGIN
        PERFORM sppoultrycapitalasset_create(
            p_farmid => v_farm, p_assetname => 'ZZ Bad Dates',
            p_acquisitiondate => CURRENT_DATE,
            p_inservicedate => CURRENT_DATE - 30, p_amount => 1000,
            p_createdby => 'ZZ tester');
        RAISE NOTICE 'F1. in service too early  <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'F1. in service too early  blocked: %', left(SQLERRM, 60);
    END;

    BEGIN
        PERFORM sppoultrycapitalasset_update(
            p_farmid => v_farm, p_assetid => v_mixer, p_assetname => NULL,
            p_inservicedate => CURRENT_DATE, p_usefullifemonths => 60,
            p_residualvalue => 999999, p_setfinancials => TRUE, p_updatedby => 'ZZ tester');
        RAISE NOTICE 'F2. residual above cost   <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'F2. residual above cost   blocked: %', left(SQLERRM, 60);
    END;

    -- A supplier payment stands against the house, so its acquisition cannot be
    -- unwound: the payment would be left pointing at a bill that no longer
    -- exists, and Supplier Balances would never reconcile again.
    BEGIN
        PERFORM sppoultrycapitalasset_reverse(v_farm, v_house, 'should be blocked', 'ZZ tester');
        RAISE NOTICE 'F3. reversing a paid asset <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'F3. reversing a paid asset blocked: %', left(SQLERRM, 60);
    END;

    BEGIN
        PERFORM sppoultrycapitalasset_reverse(v_farm, v_mixer, '', 'ZZ tester');
        RAISE NOTICE 'F4. reversal with no reason <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'F4. reversal with no reason blocked: %', left(SQLERRM, 60);
    END;

    -- =====================================================================
    -- G. Reversal, when nothing downstream depends on it.
    -- =====================================================================
    v_gen := sppoultrycapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ Generator',
        p_acquisitiondate => CURRENT_DATE, p_amount => 80000,
        p_paymentmethod => 'Cash', p_amountpaid => 80000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    SELECT a.currentbalance INTO v_bal0 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    PERFORM sppoultrycapitalasset_reverse(v_farm, v_gen, 'Recorded on the wrong company', 'ZZ tester');
    SELECT a.currentbalance INTO v_bal1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;

    RAISE NOTICE 'G1. the cash comes back    expect 80000.00  got %', (v_bal1 - v_bal0);
    RAISE NOTICE 'G2. the asset is Reversed  expect Reversed  got %',
        (SELECT a.status FROM poultrycapitalassets a WHERE a.poultrycapitalassetid = v_gen);
    -- The row is KEPT with its reason. Deleting it would erase the fact that
    -- somebody once recorded an 80,000 generator here.
    RAISE NOTICE 'G3. and says why           expect Recorded on the wrong company  got %',
        (SELECT a.reversalreason FROM poultrycapitalassets a WHERE a.poultrycapitalassetid = v_gen);
    RAISE NOTICE 'G4. its cost is gone       expect 0.00  got %',
        fnpoultrycapitalasset_originalcost(v_gen);
    RAISE NOTICE 'G5. and the expense with it expect 0  got %',
        (SELECT COUNT(*)::integer FROM expense e WHERE e.poultrycapitalassetid = v_gen);

    BEGIN
        PERFORM sppoultrycapitalassetcost_add(v_farm, v_gen, CURRENT_DATE, 'ZZ', NULL, 100,
                                              NULL, NULL, 'Cash', 100, NULL, v_acct, NULL, 'ZZ tester');
        RAISE NOTICE 'G6. cost on reversed asset <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'G6. cost on reversed asset blocked: %', left(SQLERRM, 60);
    END;

    -- =====================================================================
    -- H. Disposal proceeds are CASH, not revenue.
    -- =====================================================================
    SELECT a.currentbalance INTO v_bal0 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    PERFORM sppoultrycapitalasset_dispose(v_farm, v_mixer, CURRENT_DATE, 25000, v_acct,
                                          'Sold to a neighbouring farm', 'ZZ tester');
    SELECT a.currentbalance INTO v_bal1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;

    RAISE NOTICE 'H1. proceeds reach cash    expect 25000.00  got %', (v_bal1 - v_bal0);
    RAISE NOTICE 'H2. the asset is Disposed  expect Disposed  got %',
        (SELECT a.status FROM poultrycapitalassets a WHERE a.poultrycapitalassetid = v_mixer);
    -- Selling a mixer is not trading income. Nothing was written to `sale`.
    RAISE NOTICE 'H3. and it is not a sale   expect 0  got %',
        (SELECT COUNT(*)::integer FROM sale s WHERE s.farmid = v_farm AND s.product ILIKE '%ZZ Feed Mixer%');

    -- =====================================================================
    -- I. The register's own totals.
    -- =====================================================================
    SELECT * INTO v_r FROM sppoultrycapitalasset_summary(v_farm);
    -- Mixer 120,000 + house 600,000 + build 500,000. The reversed generator is
    -- not there, which is what "Reversed" has to mean.
    RAISE NOTICE 'I1. total asset cost       expect 1220000.00  got %', v_r.totalassetcost;
    RAISE NOTICE 'I2. nothing depreciated yet expect 0.00  got %', v_r.accumulateddepreciation;
    RAISE NOTICE 'I3. so book value equals it expect 1220000.00  got %', v_r.currentbookvalue;
    RAISE NOTICE 'I4. three live assets      expect 3  got %', v_r.totalassets;
END
$t$;

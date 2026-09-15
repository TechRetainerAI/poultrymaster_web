-- Behavioural checks for migration 269: what KIND of cost is this, and which
-- Profit & Loss line does it belong on.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates items, purchases and expenses.
--
--   psql ... -X -c "BEGIN;" -f poultry-financial-cost-type.test.sql -c "ROLLBACK;"
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **A feed purchase is reported as Feed Cost.** Today it is not: 72 raw-material
-- purchases carry the category "Raw Materials / Inventory Purchase", which
-- matches none of the P&L keywords, so every one of them falls into "Other".
-- Section B buys maize and asserts the line is Feed -- resolved from the ITEM,
-- through Phase 1's own category grouping, so the report and the cost-recognition
-- settings cannot disagree about what feed is.
--
-- The rest:
--   1. Stored classification beats everything; source beats keyword; keyword is
--      last and still works, because a farm's hand-typed history depends on it.
--   2. Loan interest and loan fees are FINANCING, not operating -- they sit
--      below Operating Profit, not in it.
--   3. Phase 2's consumption recognition is an OPERATING cost, not a
--      NonCashExpense. Both are non-cash; only one belongs beside depreciation.
--   4. CapitalAsset and InventoryPurchase resolve to Excluded, so nothing can
--      quietly reach profit through them.
--   5. The expense form refuses to create a capital cost, because a capital cost
--      with no asset behind it is money that leaves both sides of the report.
--   6. An unclassified write behaves exactly as it does today.

DO $t$
DECLARE
    v_farm text;
    v_uuid uuid;
    v_feedItem integer; v_medItem integer; v_packItem integer;
    v_feedLot integer;  v_medLot integer;  v_packLot integer;
    v_exp integer;
    v_line text;
BEGIN
    SELECT f.farmid INTO v_farm
    FROM   farms f
    WHERE  f.type = 'Poultry'
      AND  f.farmid ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ORDER  BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No uuid-shaped poultry company to test against.'; END IF;
    v_uuid := v_farm::uuid;
    RAISE NOTICE '   using poultry farm %', v_farm;

    -- =====================================================================
    -- A. What kind of cost is this?
    -- =====================================================================
    RAISE NOTICE 'A1. stored wins            expect CapitalAsset  got %',
        fnpoultryexpense_costtype('CapitalAsset', 'PoultryRawMaterialPurchase', 'Feed', 'Cash');
    RAISE NOTICE 'A2. depreciation source    expect NonCashExpense  got %',
        fnpoultryexpense_costtype(NULL, 'AssetDepreciation', 'Depreciation', 'NonCash');
    RAISE NOTICE 'A3. loan payment source    expect FinancingExpense  got %',
        fnpoultryexpense_costtype(NULL, 'LoanPayment', 'Interest Expense', 'NonCash');
    RAISE NOTICE 'A4. an ordinary bill       expect OperatingExpense  got %',
        fnpoultryexpense_costtype(NULL, NULL, 'Utilities', 'Cash');
    -- Phase 2's consumption recognition is non-cash and is NOT NonCashExpense.
    -- Calling it that would file feed beside depreciation, below Operating
    -- Profit, where no farmer would ever look for it.
    RAISE NOTICE 'A5. feed consumption       expect OperatingExpense  got %',
        fnpoultryexpense_costtype(NULL, 'PoultryFeedConsumption', 'Feed Cost', 'NonCash');

    -- =====================================================================
    -- B. THE CLAIM. A feed purchase reads as Feed, not as Other.
    -- =====================================================================
    v_feedItem := sppoultryrawmaterialitem_insert(v_farm, 'ZZ C Maize', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'kg', 'EXPENSE_WHEN_PURCHASED');
    v_medItem  := sppoultryrawmaterialitem_insert(v_farm, 'ZZ C Antibiotic', 'Medication', 'ml', 0, NULL, 'FIFO', 'ml', 'EXPENSE_WHEN_PURCHASED');
    v_packItem := sppoultryrawmaterialitem_insert(v_farm, 'ZZ C Crates', 'Packaging', 'pcs', 0, NULL, 'FIFO', 'pcs', 'EXPENSE_WHEN_PURCHASED');

    v_feedLot := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_feedItem,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 100, p_unitcost => 10, p_totalcost => 1000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 1000, p_createdby => 'ZZ tester');
    v_medLot := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_medItem,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 100, p_unitcost => 5, p_totalcost => 500,
        p_productionunit => 'ml', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 500, p_createdby => 'ZZ tester');
    v_packLot := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_packItem,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 100, p_unitcost => 2, p_totalcost => 200,
        p_productionunit => 'pcs', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 200, p_createdby => 'ZZ tester');

    -- All three rows carry the SAME category words. Only the item differs, which
    -- is the whole point: the words cannot tell these three apart and the item
    -- can.
    RAISE NOTICE 'B0. one category, 3 items  expect 1  got %',
        (SELECT COUNT(DISTINCT e.category) FROM expense e
          WHERE e.sourcetype = 'PoultryRawMaterialPurchase'
            AND e.sourceid IN (v_feedLot, v_medLot, v_packLot));

    SELECT e.plline INTO v_line FROM fnpoultryexpenserows(v_uuid) e
    WHERE  e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = v_feedLot;
    RAISE NOTICE 'B1. maize is Feed          expect Feed  got %', v_line;

    SELECT e.plline INTO v_line FROM fnpoultryexpenserows(v_uuid) e
    WHERE  e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = v_medLot;
    RAISE NOTICE 'B2. antibiotic is Medication expect Medication  got %', v_line;

    -- Packaging is neither, and Phase 1 says so: its category group is
    -- Unconfigured, which is exactly why a farm can defer feed without
    -- accidentally deferring its egg crates.
    SELECT e.plline INTO v_line FROM fnpoultryexpenserows(v_uuid) e
    WHERE  e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = v_packLot;
    RAISE NOTICE 'B3. crates are supplies    expect ProductionSupplies  got %', v_line;

    SELECT e.plsection INTO v_line FROM fnpoultryexpenserows(v_uuid) e
    WHERE  e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = v_feedLot;
    RAISE NOTICE 'B4. and it is a direct cost expect DirectCost  got %', v_line;

    RAISE NOTICE 'B5. label for the screen   expect Feed Cost  got %',
        fnpoultryexpense_pllinelabel('Feed');
    RAISE NOTICE 'B6. source is traceable    expect Raw material purchase  got %',
        (SELECT e.sourcelabel FROM fnpoultryexpenserows(v_uuid) e
          WHERE e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = v_feedLot);

    -- =====================================================================
    -- C. Financing sits below Operating Profit, not in it.
    -- =====================================================================
    RAISE NOTICE 'C1. interest               expect LoanInterest  got %',
        fnpoultryexpense_plline('FinancingExpense', 'LoanPayment', 'Interest Expense', NULL);
    RAISE NOTICE 'C2. fee                    expect LoanFees  got %',
        fnpoultryexpense_plline('FinancingExpense', 'LoanPayment', 'Loan Fee', NULL);
    RAISE NOTICE 'C3. both are Other Costs   expect OtherCost  got %',
        fnpoultryexpense_plsection(fnpoultryexpense_plline('FinancingExpense', 'LoanPayment', 'Interest Expense', NULL));
    RAISE NOTICE 'C4. depreciation too       expect OtherCost  got %',
        fnpoultryexpense_plsection(fnpoultryexpense_plline('NonCashExpense', 'AssetDepreciation', 'Depreciation', NULL));

    -- =====================================================================
    -- D. Nothing reaches profit through a capital or inventory classification.
    -- =====================================================================
    RAISE NOTICE 'D1. capital is excluded    expect Excluded  got %',
        fnpoultryexpense_plline('CapitalAsset', 'CapitalAsset', 'Buildings', NULL);
    RAISE NOTICE 'D2. inventory is excluded  expect Excluded  got %',
        fnpoultryexpense_plline('InventoryPurchase', 'PoultryRawMaterialPurchase', 'Feed', 'FeedIngredient');
    RAISE NOTICE 'D3. and the section says so expect Excluded  got %',
        fnpoultryexpense_plsection('Excluded');

    -- =====================================================================
    -- E. Keyword still works, for the three years of typed categories.
    -- =====================================================================
    RAISE NOTICE 'E1. Utilities              expect Utilities  got %',
        fnpoultryexpense_plline('OperatingExpense', NULL, 'Utilities', NULL);
    RAISE NOTICE 'E2. Labor is Payroll       expect Payroll  got %',
        fnpoultryexpense_plline('OperatingExpense', NULL, 'Labor', NULL);
    -- Direct labour has to be NAMED to be counted as direct. Guessing would move
    -- real money between Gross Profit and Operating Profit.
    RAISE NOTICE 'E3. Direct Labour is direct expect DirectLabour  got %',
        fnpoultryexpense_plline('OperatingExpense', NULL, 'Direct Labour', NULL);
    RAISE NOTICE 'E4. Veterinary is medication expect Medication  got %',
        fnpoultryexpense_plline('OperatingExpense', NULL, 'Veterinary', NULL);
    RAISE NOTICE 'E5. Flock / Bird Purchase  expect FlockCost  got %',
        fnpoultryexpense_plline('OperatingExpense', NULL, 'Flock / Bird Purchase', NULL);
    RAISE NOTICE 'E6. an unknown word        expect OtherOperating  got %',
        fnpoultryexpense_plline('OperatingExpense', NULL, 'Sundry', NULL);

    -- =====================================================================
    -- F. The expense form cannot create a capital cost.
    -- =====================================================================
    BEGIN
        PERFORM spexpense_insert(
            (now() at time zone 'utc'), 'Buildings', 'ZZ should be blocked', 5000, 'Cash',
            NULL, NULL, 'ZZ tester', v_uuid, NULL, NULL, NULL, 5000, NULL, NULL, 'CapitalAsset');
        RAISE NOTICE 'F1. capital from expenses  <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'F1. capital from expenses  blocked: %', left(SQLERRM, 60);
    END;

    -- =====================================================================
    -- G. An unclassified write behaves exactly as it does today.
    -- =====================================================================
    v_exp := spexpense_insert(
        (now() at time zone 'utc'), 'Utilities', 'ZZ electricity', 400, 'Cash',
        NULL, NULL, 'ZZ tester', v_uuid);
    RAISE NOTICE 'G1. classification unstated expect <NULL>  got %',
        COALESCE((SELECT e.financialcosttype::text FROM expense e WHERE e.expenseid = v_exp), '<NULL>');
    RAISE NOTICE 'G2. but it still resolves  expect OperatingExpense  got %',
        (SELECT e.financialcosttype FROM fnpoultryexpenserows(v_uuid) e WHERE e.expenseid = v_exp);
    RAISE NOTICE 'G3. and reads as legacy    expect f  got %',
        (SELECT e.costtypeisstored FROM fnpoultryexpenserows(v_uuid) e WHERE e.expenseid = v_exp);
    RAISE NOTICE 'G4. on the Utilities line  expect Utilities  got %',
        (SELECT e.plline FROM fnpoultryexpenserows(v_uuid) e WHERE e.expenseid = v_exp);

    -- A stated one is stored and says so.
    v_exp := spexpense_insert(
        (now() at time zone 'utc'), 'Sundry', 'ZZ stated', 100, 'Cash',
        NULL, NULL, 'ZZ tester', v_uuid, NULL, NULL, NULL, 100, NULL, NULL, 'OperatingExpense');
    RAISE NOTICE 'G5. stated is stored       expect t  got %',
        (SELECT e.costtypeisstored FROM fnpoultryexpenserows(v_uuid) e WHERE e.expenseid = v_exp);

    -- =====================================================================
    -- H. Revenue lines.
    -- =====================================================================
    RAISE NOTICE 'H1. Fresh Eggs             expect EggSales  got %', fnpoultrysale_revenueline('Fresh Eggs');
    RAISE NOTICE 'H2. Chicken                expect BirdSales  got %', fnpoultrysale_revenueline('Chicken');
    RAISE NOTICE 'H3. Manure                 expect ManureSales  got %', fnpoultrysale_revenueline('Manure');
    RAISE NOTICE 'H4. Layer Mash             expect FeedSales  got %', fnpoultrysale_revenueline('Layer Mash');
    RAISE NOTICE 'H5. anything else          expect OtherRevenue  got %', fnpoultrysale_revenueline('Consultancy');
    -- Egg wins over bird: "egg" is checked first, so a sale of "Egg Chicks"
    -- counts once, on one line, and the lines still sum to total revenue.
    RAISE NOTICE 'H6. no double counting     expect EggSales  got %', fnpoultrysale_revenueline('Egg Chicks');

    -- =====================================================================
    -- I. Nothing that already existed moved.
    -- =====================================================================
    RAISE NOTICE 'I1. every row classifies   expect 0  got %',
        (SELECT COUNT(*) FROM fnpoultryexpenserows(v_uuid) e WHERE e.plline IS NULL);
    RAISE NOTICE 'I2. nothing excluded yet   expect 0  got %',
        (SELECT COUNT(*) FROM fnpoultryexpenserows(v_uuid) e
          WHERE e.plsection = 'Excluded' AND e.description NOT LIKE 'ZZ %');
    RAISE NOTICE 'I3. read count = row count expect %  got %',
        (SELECT COUNT(*) FROM expense e WHERE e.farmid = v_uuid),
        (SELECT COUNT(*) FROM fnpoultryexpenserows(v_uuid));
END
$t$;

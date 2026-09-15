-- Behavioural checks for migration 282: what KIND of cost a water expense is.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK.
--
--   psql ... -X -c "BEGIN;" -f water-financial-cost-type.test.sql -c "ROLLBACK;"
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **No existing row changes meaning.** 282 backfills nothing and rewrites
-- nothing; every legacy expense is classified at READ time, and section A
-- asserts that the answer it gets is the answer it has always had --
-- OperatingExpense, on an operating line, below Gross Profit. A company's
-- history must not change shape because a migration ran.
--
-- The rest:
--   1. Structure beats keywords. A raw-material purchase is placed by its ITEM's
--      category through 274's resolver, not by the words in its description --
--      which is what stops packaging being filed as "Other".
--   2. The stored value wins over everything, and is the only thing that can.
--   3. Excluded really is excluded: capital and inventory purchases reach no
--      profit line at all.
--   4. The two axes are independent -- a deferred purchase is still an
--      InventoryPurchase, and depreciation is non-cash without being a direct
--      cost.
--   5. Every line has a label and a section, including one nobody has invented.

DO $t$
DECLARE
    v_farm  text;
    v_cat   integer;
    v_item  integer;
    v_pack  integer;
    v_r     record;
BEGIN
    SELECT f.farmid INTO v_farm
    FROM   farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No water company to test against.'; END IF;
    RAISE NOTICE '   using water company %', v_farm;

    -- =====================================================================
    -- A. THE CLAIM. Nothing existing changed meaning.
    -- =====================================================================
    RAISE NOTICE 'A1. nothing was backfilled expect        0  got %',
        (SELECT COUNT(*)::integer FROM waterexpenses WHERE financialcosttype IS NOT NULL);

    -- A plain legacy bill: no stored type, no sourcetype.
    RAISE NOTICE 'A2. a plain bill is operating expect OperatingExpense  got %',
        fnwaterexpense_costtype(NULL, NULL, 'Electricity', 'Cash');
    RAISE NOTICE 'A3. and sits below Gross Profit expect OperatingExpense  got %',
        fnwaterexpense_plsection(fnwaterexpense_plline('OperatingExpense', NULL, 'Electricity', NULL));
    -- Every row that exists today still reads as an ordinary operating cost.
    RAISE NOTICE 'A4. no legacy row moved off operating expect        0  got %',
        (SELECT COUNT(*)::integer FROM fnwaterexpenserows(v_farm) r
          WHERE r.sourcetype IS NULL AND r.financialcosttype <> 'OperatingExpense');

    -- =====================================================================
    -- B. Structure beats keywords.
    -- =====================================================================
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Sachet Film', 'SachetFilm', 'Roll', 'Roll', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_item;

    -- The item says Packaging even though the CATEGORY TEXT says nothing of the
    -- sort. This is the case that was landing in "Other" before 282.
    RAISE NOTICE 'B1. the item decides the line expect Packaging  got %',
        fnwaterexpense_plline('OperatingExpense', 'RawMaterialPurchase',
                              'Raw Materials / Inventory Purchase', 'SachetFilm');
    RAISE NOTICE 'B2. and that is a direct cost expect DirectCost  got %',
        fnwaterexpense_plsection(
            fnwaterexpense_plline('OperatingExpense', 'RawMaterialPurchase',
                                  'Raw Materials / Inventory Purchase', 'SachetFilm'));
    -- A chemical goes to Treatment, through the same 274 resolver.
    RAISE NOTICE 'B3. a chemical is Treatment expect Treatment  got %',
        fnwaterexpense_plline('OperatingExpense', 'RawMaterialPurchase', 'Raw Materials', 'Chemical');
    -- An UNCONFIGURED category is production supplies, not packaging: 274 and
    -- 282 must agree about what packaging means.
    RAISE NOTICE 'B4. an unconfigured item is supplies expect ProductionSupplies  got %',
        fnwaterexpense_plline('OperatingExpense', 'RawMaterialPurchase', 'Raw Materials', 'Fuel');
    RAISE NOTICE 'B5. 274 and 282 agree on packaging expect        t  got %',
        (fnwatercostrecognition_categorygroup('SachetFilm') = 'Packaging'
         AND fnwaterexpense_plline('OperatingExpense', NULL, 'x', 'SachetFilm') = 'Packaging');

    -- =====================================================================
    -- C. The stored value wins, and only it can.
    -- =====================================================================
    RAISE NOTICE 'C1. stored beats the source expect CapitalAsset  got %',
        fnwaterexpense_costtype('CapitalAsset', 'Payroll', 'Wages', 'Cash');
    RAISE NOTICE 'C2. an empty stored value is ignored expect OperatingExpense  got %',
        fnwaterexpense_costtype('', NULL, 'Anything', 'Cash');
    -- Nothing keyword-based can produce a cost type. That is the whole design.
    RAISE NOTICE 'C3. "capital" in the text proves nothing expect OperatingExpense  got %',
        fnwaterexpense_costtype(NULL, NULL, 'Capital repairs to the plant', 'Cash');

    -- =====================================================================
    -- D. The sources that do decide.
    -- =====================================================================
    RAISE NOTICE 'D1. depreciation is non-cash expect NonCashExpense  got %',
        fnwaterexpense_costtype(NULL, 'AssetDepreciation', 'Depreciation', 'NonCash');
    RAISE NOTICE 'D2. loan interest is financing expect FinancingExpense  got %',
        fnwaterexpense_costtype(NULL, 'LoanPaymentInterest', 'Loan interest', 'Cash');
    RAISE NOTICE 'D3. loan fees too          expect FinancingExpense  got %',
        fnwaterexpense_costtype(NULL, 'LoanPaymentFee', 'Loan fees', 'Cash');
    -- 259 writes reversal legs as their own sourcetypes; they must classify the
    -- same way or a reversal would land on a different P&L line from the charge
    -- it cancels.
    RAISE NOTICE 'D4. and their reversals    expect FinancingExpense  got %',
        fnwaterexpense_costtype(NULL, 'LoanPaymentInterestReversal', 'Reversal', 'Cash');
    RAISE NOTICE 'D5. a capital acquisition  expect CapitalAsset  got %',
        fnwaterexpense_costtype(NULL, 'CapitalAsset', 'Borehole', 'Cash');

    -- =====================================================================
    -- E. Excluded really is excluded.
    -- =====================================================================
    RAISE NOTICE 'E1. capital reaches no line expect Excluded  got %',
        fnwaterexpense_plline('CapitalAsset', 'CapitalAsset', 'Capital Assets', NULL);
    RAISE NOTICE 'E2. nor does an inventory purchase expect Excluded  got %',
        fnwaterexpense_plline('InventoryPurchase', 'RawMaterialPurchase', 'Raw Materials', 'SachetFilm');
    RAISE NOTICE 'E3. and Excluded is its own band expect Excluded  got %',
        fnwaterexpense_plsection('Excluded');
    -- An item category must NOT rescue a capital row back onto a profit line.
    RAISE NOTICE 'E4. capital wins over the item expect Excluded  got %',
        fnwaterexpense_plline('CapitalAsset', 'RawMaterialPurchase', 'x', 'SachetFilm');

    -- =====================================================================
    -- F. The two axes are independent.
    -- =====================================================================
    -- A deferred purchase is still an InventoryPurchase; 274's method says WHEN,
    -- 282's type says WHAT KIND, and neither answers the other's question.
    RAISE NOTICE 'F1. deferred is still inventory expect        t  got %',
        (fnwatercostrecognition_expenseatconsumption('EXPENSE_WHEN_CONSUMED')
         AND fnwaterexpense_plline('InventoryPurchase', NULL, 'x', 'SachetFilm') = 'Excluded');
    -- Depreciation is non-cash but NOT a direct cost: it must not sit beside
    -- packaging above Gross Profit.
    RAISE NOTICE 'F2. depreciation is not direct expect OtherCost  got %',
        fnwaterexpense_plsection(fnwaterexpense_plline('NonCashExpense', 'AssetDepreciation', 'Depreciation', NULL));

    -- =====================================================================
    -- G. Electricity: operating unless named. See 282's header.
    -- =====================================================================
    RAISE NOTICE 'G1. plain electricity is operating expect Utilities  got %',
        fnwaterexpense_plline('OperatingExpense', NULL, 'Electricity', NULL);
    RAISE NOTICE 'G2. and below Gross Profit expect OperatingExpense  got %',
        fnwaterexpense_plsection(fnwaterexpense_plline('OperatingExpense', NULL, 'Electricity', NULL));
    RAISE NOTICE 'G3. named production power is direct expect ProductionUtilities  got %',
        fnwaterexpense_plline('OperatingExpense', NULL, 'Production Power', NULL);
    RAISE NOTICE 'G4. and above it           expect DirectCost  got %',
        fnwaterexpense_plsection(fnwaterexpense_plline('OperatingExpense', NULL, 'Plant Electricity', NULL));

    -- =====================================================================
    -- H. Revenue lines. Dispenser must beat bottle.
    -- =====================================================================
    RAISE NOTICE 'H1. sachets                expect SachetSales  got %',
        fnwatersale_revenueline('Pure Water Sachet 500ml');
    RAISE NOTICE 'H2. bottles                expect BottleSales  got %',
        fnwatersale_revenueline('750ml Bottle');
    -- A "19L bottle" is a dispenser sale; the bottle test must not swallow it.
    RAISE NOTICE 'H3. a 19L bottle is a dispenser expect DispenserSales  got %',
        fnwatersale_revenueline('19L Bottle');
    RAISE NOTICE 'H4. anything else          expect OtherRevenue  got %',
        fnwatersale_revenueline('Delivery charge');

    -- =====================================================================
    -- I. Every line has a label and a band.
    -- =====================================================================
    -- Six lines ARE their own label -- "Rent" really is just "Rent" -- so
    -- `label = key` cannot tell a deliberate one-word label from a line that
    -- quietly fell through the CASE into the ELSE. Two checks instead: no label
    -- is empty, and the self-labelled set is exactly the six expected.
    RAISE NOTICE 'I1. no line is unlabelled  expect        0  got %',
        (SELECT COUNT(*)::integer FROM (VALUES
            ('Packaging'),('Treatment'),('DirectLabour'),('ProductionSupplies'),
            ('ProductionUtilities'),('OtherDirect'),('Payroll'),('Utilities'),
            ('Transport'),('RepairsMaintenance'),('Rent'),('Marketing'),
            ('Insurance'),('Security'),('ProfessionalServices'),('LicencesPermits'),
            ('Communications'),('Administration'),('OtherOperating'),
            ('Depreciation'),('LoanInterest'),('LoanFees'),('OtherFinancing')
         ) AS l(line)
         WHERE COALESCE(fnwaterexpense_pllinelabel(l.line), '') = '');
    -- If a NEW line is added to fnwaterexpense_plline and nobody gives it a
    -- label, it lands here and this check fails -- which is the point.
    RAISE NOTICE 'I1b. self-labelled lines are the expected six expect        t  got %',
        (SELECT COALESCE(array_agg(l.line ORDER BY l.line), ARRAY[]::text[])
                = ARRAY['Depreciation','Insurance','Marketing','Rent','Security','Utilities']
         FROM (VALUES
            ('Packaging'),('Treatment'),('DirectLabour'),('ProductionSupplies'),
            ('ProductionUtilities'),('OtherDirect'),('Payroll'),('Utilities'),
            ('Transport'),('RepairsMaintenance'),('Rent'),('Marketing'),
            ('Insurance'),('Security'),('ProfessionalServices'),('LicencesPermits'),
            ('Communications'),('Administration'),('OtherOperating'),
            ('Depreciation'),('LoanInterest'),('LoanFees'),('OtherFinancing')
         ) AS l(line)
         WHERE fnwaterexpense_pllinelabel(l.line) = l.line);
    -- A line nobody has invented still gets a band rather than a NULL.
    RAISE NOTICE 'I2. an unknown line still banded expect OperatingExpense  got %',
        fnwaterexpense_plsection('ZZ Invented');

    -- =====================================================================
    -- J. The read surface carries it all.
    -- =====================================================================
    RAISE NOTICE 'J1. every row has a cost type expect        0  got %',
        (SELECT COUNT(*)::integer FROM fnwaterexpenserows(v_farm) r
          WHERE COALESCE(r.financialcosttype, '') = '');
    RAISE NOTICE 'J2. every row has a section expect        0  got %',
        (SELECT COUNT(*)::integer FROM fnwaterexpenserows(v_farm) r
          WHERE COALESCE(r.plsection, '') = '');
    -- costtypeisstored says whether a human stated it or the resolver worked it
    -- out, so a screen can show "derived" honestly.
    RAISE NOTICE 'J3. nothing claims to be stored expect        0  got %',
        (SELECT COUNT(*)::integer FROM fnwaterexpenserows(v_farm) r WHERE r.costtypeisstored);
    RAISE NOTICE 'J4. the read agrees with the resolver expect        0  got %',
        (SELECT COUNT(*)::integer FROM fnwaterexpenserows(v_farm) r
          WHERE r.plsection <> fnwaterexpense_plsection(r.plline));

    -- 282 must not have disturbed the poultry side it was copied from.
    RAISE NOTICE 'J5. poultry column untouched expect        t  got %',
        EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'expense' AND column_name = 'financialcosttype');
END
$t$;

-- =============================================================================
-- Negative cases. Each must be BLOCKED.
-- =============================================================================
DO $n$
DECLARE
    v_farm text;
    v_exp  integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;

    SELECT waterexpenseid INTO v_exp FROM waterexpenses
     WHERE farmid = v_farm AND COALESCE(isdeleted, FALSE) = FALSE
     ORDER BY waterexpenseid LIMIT 1;

    IF v_exp IS NULL THEN
        RAISE NOTICE 'N1-N3. skipped: this company has no expense rows';
        RETURN;
    END IF;

    BEGIN
        PERFORM spwaterexpense_setcosttype(v_farm, v_exp, 'SOMETIMES');
        RAISE NOTICE 'N1. an invented cost type  <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N1. an invented cost type  blocked: %', SQLERRM;
    END;

    -- A capital cost with no asset behind it would leave profit AND never be
    -- depreciated: the money would vanish from both sides of the report.
    BEGIN
        PERFORM spwaterexpense_setcosttype(v_farm, v_exp, 'CapitalAsset');
        RAISE NOTICE 'N2. a plain bill stamped capital <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N2. a plain bill stamped capital blocked: %', SQLERRM;
    END;

    -- The table refuses it too, so a direct write cannot get round the SP.
    BEGIN
        UPDATE waterexpenses SET financialcosttype = 'MAYBE' WHERE waterexpenseid = v_exp;
        RAISE NOTICE 'N3. a direct bad write     <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N3. a direct bad write     blocked: %', SQLERRM;
    END;

    -- An expense from another company must not be reclassifiable.
    BEGIN
        PERFORM spwaterexpense_setcosttype('ZZ-not-a-company', v_exp, 'OperatingExpense');
        RAISE NOTICE 'N4. a cross-company write  <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N4. a cross-company write  blocked: %', SQLERRM;
    END;
END
$n$;

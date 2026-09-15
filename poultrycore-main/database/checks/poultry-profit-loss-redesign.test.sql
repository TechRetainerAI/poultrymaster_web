-- Behavioural checks for migration 272: the Profit & Loss redesign.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates sales, expenses, an asset, a loan and
-- owner money.
--
--   psql ... -X -c "BEGIN;" -f poultry-profit-loss-redesign.test.sql -c "ROLLBACK;"
--
-- EVERYTHING IS DATED 2015. The report window is 2015 only, the farm has no
-- 2015 history, and section A asserts that before anything is written. That is
-- what lets every figure below be an exact number rather than a delta.
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **A 500,000 poultry house does not turn a 35,000 profit into a 465,000 loss.**
-- Section E is §90 of the brief, built end to end: revenue 100,000, operating
-- costs 60,000, an asset bought for 500,000, one month of depreciation at 5,000.
-- Net Profit must read 35,000. Under today's report the same month reads
-- -465,000 and the owner is told the business is failing.
--
-- The rest:
--   1. The three formulas hold, exactly: Gross = Revenue - Direct;
--      Operating = Gross - Operating Expenses; Net = Operating - Other Costs.
--   2. Owner contributions and draws move cash and NOT profit (§86, §87).
--   3. A loan repayment charges interest and fees to profit and the PRINCIPAL
--      to nothing (§89) -- the single most common way a P&L is read wrongly.
--   4. An expense on credit is a cost the day it is incurred, not the day it is
--      paid (§91), and paying it later adds nothing.
--   5. §84: consumption-based feed reports what was EATEN, not what was bought.
--   6. §85: a period holding both an expense-at-purchase medication layer and an
--      expense-at-consumption one reports the sum, once.
--   7. §93: every drilldown totals to the line above it.

DO $t$
DECLARE
    v_farm text;
    v_uuid uuid;
    v_acct integer; v_supp integer;
    v_from date := DATE '2015-01-01';
    v_to   date := DATE '2015-12-31';
    v_s record;
    v_asset integer; v_loan integer;
    v_item integer; v_med integer; v_medc integer;
    v_lot integer; v_rec integer;
    v_exp integer;
    v_bal0 numeric; v_bal1 numeric;
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
    -- A. 2015 is empty. Every number below is therefore absolute.
    -- =====================================================================
    SELECT * INTO v_s FROM sppoultryreport_plsummary(v_farm, v_from, v_to);
    RAISE NOTICE 'A1. no revenue in 2015     expect 0.00  got %', v_s.totalrevenue;
    RAISE NOTICE 'A2. no costs in 2015       expect 0.00  got %',
        (v_s.totaldirectcosts + v_s.totaloperatingexpenses + v_s.totalothercosts);
    RAISE NOTICE 'A3. no margin on nothing   expect <NULL>  got %',
        COALESCE(v_s.grossmarginpercent::text, '<NULL>');
    RAISE NOTICE 'A4. and it is break-even   expect Break-even  got %', v_s.status;

    v_acct := sppoultrycashaccount_insert(v_farm, 'ZZ PL Account', 'Bank', 3000000, TRUE, NULL);
    v_supp := spsupplier_insert('ZZ tester', v_farm, 'ZZ PL Supplier', NULL, NULL, NULL, NULL);

    -- =====================================================================
    -- B. Revenue is SALES. Cash in is not revenue.
    -- =====================================================================
    PERFORM spsale_insert('ZZ tester', v_farm, TIMESTAMP '2015-03-05', 'Fresh Eggs',
                          100, 700, 70000, 'Cash', 'ZZ Customer', NULL, NULL, TRUE, NULL, NULL);
    PERFORM spsale_insert('ZZ tester', v_farm, TIMESTAMP '2015-03-06', 'Spent Layers',
                          50, 400, 20000, 'Cash', 'ZZ Customer', NULL, NULL, TRUE, NULL, NULL);
    PERFORM spsale_insert('ZZ tester', v_farm, TIMESTAMP '2015-03-07', 'Manure',
                          10, 1000, 10000, 'Cash', 'ZZ Customer', NULL, NULL, TRUE, NULL, NULL);

    -- 150,000 of owner money and 100,000 of borrowing, both in the same month.
    PERFORM sppoultryownermoney_record(v_farm, 'Contribution', 150000, v_acct,
                                       TIMESTAMP '2015-03-10', 'Cash', NULL, 'ZZ Owner',
                                       NULL, NULL, 'ZZ tester');
    PERFORM sppoultryownermoney_record(v_farm, 'Draw', 20000, v_acct,
                                       TIMESTAMP '2015-03-11', 'Cash', NULL, 'ZZ Owner',
                                       NULL, NULL, 'ZZ tester');

    v_loan := sppoultryloan_create(v_farm, 'ZZ Bank', 100000, DATE '2015-03-01', 100000, v_acct,
                                   'Bank', NULL, DATE '2015-03-01', 24, 'Simple', 24, 'Monthly',
                                   NULL, NULL, 'Active', NULL, 'ZZ tester');

    SELECT * INTO v_s FROM sppoultryreport_plsummary(v_farm, v_from, v_to);
    -- 250,000 reached the bank this month and NONE of it is revenue.
    RAISE NOTICE 'B1. revenue is sales only  expect 100000.00  got %', v_s.totalrevenue;
    RAISE NOTICE 'B2. eggs                   expect 70000.00  got %', v_s.eggsales;
    RAISE NOTICE 'B3. birds                  expect 20000.00  got %', v_s.birdsales;
    RAISE NOTICE 'B4. manure                 expect 10000.00  got %', v_s.manuresales;
    -- §86, §87, §88: informational, and outside every total.
    RAISE NOTICE 'B5. owner contributions    expect 150000.00  got %', v_s.ownercontributions;
    RAISE NOTICE 'B6. owner draws            expect 20000.00  got %', v_s.ownerdraws;
    RAISE NOTICE 'B7. net owner funding      expect 130000.00  got %', v_s.netownerfunding;
    RAISE NOTICE 'B8. loans received         expect 100000.00  got %', v_s.loansreceived;
    RAISE NOTICE 'B9. and the draw is not a cost expect 0.00  got %', v_s.totaloperatingexpenses;

    -- =====================================================================
    -- C. §91 -- an expense on credit is a cost when incurred, not when paid.
    -- =====================================================================
    SELECT a.currentbalance INTO v_bal0 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    v_exp := spexpense_insert(TIMESTAMP '2015-04-02', 'Utilities', 'ZZ electricity bill',
                              20000, 'Credit', 'ZZ PL Supplier', NULL, 'ZZ tester', v_uuid,
                              NULL, NULL, v_supp, 0, DATE '2015-05-02', NULL);

    SELECT * INTO v_s FROM sppoultryreport_plsummary(v_farm, v_from, v_to);
    RAISE NOTICE 'C1. the cost is recognised expect 20000.00  got %', v_s.utilities;
    SELECT a.currentbalance INTO v_bal1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    RAISE NOTICE 'C2. and no cash moved      expect 0.00  got %', (v_bal0 - v_bal1);
    RAISE NOTICE 'C3. the supplier is owed   expect 20000.00  got %',
        (SELECT e.balance FROM fnpoultryexpenserows(v_uuid) e WHERE e.expenseid = v_exp);

    -- Paying it later moves cash and adds NO new cost.
    PERFORM sppoultrysupplierpayment_record(
        v_farm, v_supp, 20000,
        jsonb_build_array(jsonb_build_object('documenttype', 'Expense', 'documentid', v_exp, 'amount', 20000)),
        'Cash', TIMESTAMP '2015-05-02', v_acct, NULL, 'ZZ settling the bill',
        'SupplierPaymentsPage', 'ZZ tester');

    SELECT * INTO v_s FROM sppoultryreport_plsummary(v_farm, v_from, v_to);
    RAISE NOTICE 'C4. still the same cost    expect 20000.00  got %', v_s.utilities;
    SELECT a.currentbalance INTO v_bal1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct;
    RAISE NOTICE 'C5. and now the cash moved expect 20000.00  got %', (v_bal0 - v_bal1);

    -- =====================================================================
    -- D. §89 -- a loan repayment. Interest and fees are costs; principal is not.
    -- =====================================================================
    PERFORM sppoultryloanpayment_record(v_farm, v_loan, v_acct,
                                        10000, 2000, 500, 0,
                                        TIMESTAMP '2015-06-01', 'Cash', NULL, NULL, NULL, 'ZZ tester');

    SELECT * INTO v_s FROM sppoultryreport_plsummary(v_farm, v_from, v_to);
    RAISE NOTICE 'D1. interest is a cost     expect 2000.00  got %', v_s.loaninterest;
    RAISE NOTICE 'D2. the fee is a cost      expect 500.00  got %', v_s.loanfees;
    RAISE NOTICE 'D3. together               expect 2500.00  got %', v_s.totalothercosts;
    -- THE line that is most often got wrong. Repaying what you borrowed is not
    -- an expense; it is giving back money that was never income.
    RAISE NOTICE 'D4. principal repaid       expect 10000.00  got %', v_s.loanprincipalrepaid;
    RAISE NOTICE 'D5. and it is NOT a cost   expect 2500.00  got %', v_s.totalothercosts;
    RAISE NOTICE 'D6. net borrowing          expect 90000.00  got %', v_s.netborrowing;

    -- =====================================================================
    -- E. THE CLAIM. §90 -- a capital purchase must not distort profit.
    -- =====================================================================
    -- Bring operating expenses to 60,000 exactly: 20,000 of utilities so far,
    -- plus 40,000 of transport.
    PERFORM spexpense_insert(TIMESTAMP '2015-07-01', 'Transport', 'ZZ haulage',
                             40000, 'Cash', NULL, NULL, 'ZZ tester', v_uuid,
                             NULL, NULL, NULL, 40000, NULL, v_acct);

    v_asset := sppoultrycapitalasset_create(
        p_farmid => v_farm, p_assetname => 'ZZ PL Poultry House',
        p_acquisitiondate => DATE '2015-08-01', p_inservicedate => DATE '2015-08-01',
        p_amount => 500000, p_residualvalue => 0, p_usefullifemonths => 100,
        p_paymentmethod => 'Cash', p_amountpaid => 500000,
        p_cashaccountid => v_acct, p_createdby => 'ZZ tester');

    -- One month of depreciation: 500,000 over 100 months.
    PERFORM sppoultryassetdepreciation_generate(v_farm, DATE '2015-08-01', v_asset, 'ZZ tester');

    SELECT * INTO v_s FROM sppoultryreport_plsummary(v_farm, v_from, v_to);
    RAISE NOTICE 'E1. revenue                expect 100000.00  got %', v_s.totalrevenue;
    RAISE NOTICE 'E2. operating expenses     expect 60000.00  got %', v_s.totaloperatingexpenses;
    RAISE NOTICE 'E3. depreciation           expect 5000.00  got %', v_s.depreciation;
    -- 2,500 of financing + 5,000 of depreciation.
    RAISE NOTICE 'E4. other costs            expect 7500.00  got %', v_s.totalothercosts;
    RAISE NOTICE 'E5. operating profit       expect 40000.00  got %', v_s.operatingprofit;
    -- The number. Not -465,000.
    RAISE NOTICE 'E6. NET PROFIT             expect 32500.00  got %', v_s.netprofit;
    RAISE NOTICE 'E7. and it is a profit     expect Profit  got %', v_s.status;
    -- The 500,000 is not gone. It is an investment, reported as one.
    RAISE NOTICE 'E8. capital investments    expect 500000.00  got %', v_s.totalcapitalinvestments;
    RAISE NOTICE 'E9. but not an expense     expect 60000.00  got %', v_s.totaloperatingexpenses;

    -- =====================================================================
    -- F. The three formulas, exactly.
    -- =====================================================================
    RAISE NOTICE 'F1. Gross = Rev - Direct   expect %  got %',
        (v_s.totalrevenue - v_s.totaldirectcosts), v_s.grossprofit;
    RAISE NOTICE 'F2. Operating = Gross - Op expect %  got %',
        (v_s.grossprofit - v_s.totaloperatingexpenses), v_s.operatingprofit;
    RAISE NOTICE 'F3. Net = Operating - Other expect %  got %',
        (v_s.operatingprofit - v_s.totalothercosts), v_s.netprofit;
    -- None of the informational figures is in any of them.
    RAISE NOTICE 'F4. financing is outside   expect 32500.00  got %',
        (v_s.totalrevenue - v_s.totaldirectcosts - v_s.totaloperatingexpenses - v_s.totalothercosts);
    RAISE NOTICE 'F5. gross margin %%         expect 100.0  got %', v_s.grossmarginpercent;

    -- =====================================================================
    -- G. §83 -- feed expensed at purchase is counted once.
    -- =====================================================================
    DELETE FROM poultryfinancialsettings WHERE farmid = v_farm;
    PERFORM sppoultryfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');

    v_item := sppoultryrawmaterialitem_insert(v_farm, 'ZZ PL Maize', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'kg');
    v_lot := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_item,
        p_suppliername => 'ZZ PL Supplier', p_purchasedate => TIMESTAMP '2015-09-01',
        p_quantity => 3000, p_unitcost => 10, p_totalcost => 30000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 30000, p_createdby => 'ZZ tester');

    SELECT * INTO v_s FROM sppoultryreport_plsummary(v_farm, v_from, v_to);
    -- The whole point of 269: this is Feed Cost, not "Other".
    RAISE NOTICE 'G1. the purchase IS feed   expect 30000.00  got %', v_s.feedcost;

    -- Eating it adds nothing: the cost was taken at the purchase.
    INSERT INTO productionrecords
        (farmid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
         noofbirdsleft, feedkg, production9am, production12pm, production4pm,
         totalproduction, sourcetype)
    VALUES (v_farm, 'ZZ tester', 20, 140, DATE '2015-09-15', 100, 0, 100, 0, 0, 0, 0, 0,
            'ManualSingleFlock')
    RETURNING id INTO v_rec;
    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_rec, p_createdby => 'ZZ tester',
        p_feedsjson => ('[{"itemId":' || v_item::text || ',"qty":1000}]'));

    SELECT * INTO v_s FROM sppoultryreport_plsummary(v_farm, v_from, v_to);
    RAISE NOTICE 'G2. eating it adds nothing expect 30000.00  got %', v_s.feedcost;

    -- =====================================================================
    -- H. §84 -- feed expensed at consumption reports what was EATEN.
    -- =====================================================================
    DELETE FROM poultryfinancialsettings WHERE farmid = v_farm;
    PERFORM sppoultryfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');

    DECLARE
        v_item2 integer; v_lot2 integer; v_rec2 integer; v_feedbefore numeric;
    BEGIN
        v_feedbefore := v_s.feedcost;
        v_item2 := sppoultryrawmaterialitem_insert(v_farm, 'ZZ PL Soya', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'kg');
        v_lot2 := sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_item2,
            p_suppliername => 'ZZ PL Supplier', p_purchasedate => TIMESTAMP '2015-10-01',
            p_quantity => 3000, p_unitcost => 30, p_totalcost => 90000,
            p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 90000, p_createdby => 'ZZ tester');

        SELECT * INTO v_s FROM sppoultryreport_plsummary(v_farm, v_from, v_to);
        -- 90,000 left the bank and NOT ONE CEDI reached profit.
        RAISE NOTICE 'H1. buying it costs nothing expect %  got %', v_feedbefore, v_s.feedcost;

        INSERT INTO productionrecords
            (farmid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
             noofbirdsleft, feedkg, production9am, production12pm, production4pm,
             totalproduction, sourcetype)
        VALUES (v_farm, 'ZZ tester', 20, 140, DATE '2015-10-20', 100, 0, 100, 0, 0, 0, 0, 0,
                'ManualSingleFlock')
        RETURNING id INTO v_rec2;
        PERFORM sppoultryproductionrawmaterialsync(
            p_farmid => v_farm, p_productionid => v_rec2, p_createdby => 'ZZ tester',
            p_feedsjson => ('[{"itemId":' || v_item2::text || ',"qty":1000}]'));

        SELECT * INTO v_s FROM sppoultryreport_plsummary(v_farm, v_from, v_to);
        -- 1,000 kg at 30. Thirty thousand, not ninety.
        RAISE NOTICE 'H2. eating 1000kg costs   expect %  got %',
            (v_feedbefore + 30000), v_s.feedcost;
    END;

    -- =====================================================================
    -- I. §85 -- a mixed medication period sums, once.
    -- =====================================================================
    DECLARE
        v_medbefore numeric;
    BEGIN
        -- Layer one: bought under expense-at-purchase, so 10,000 is recognised now.
        v_med := sppoultryrawmaterialitem_insert(v_farm, 'ZZ PL Old Antibiotic', 'Medication', 'ml', 0, NULL, 'FIFO', 'ml',
                                                 'EXPENSE_WHEN_PURCHASED');
        PERFORM sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_med,
            p_suppliername => 'ZZ PL Supplier', p_purchasedate => TIMESTAMP '2015-11-01',
            p_quantity => 1000, p_unitcost => 10, p_totalcost => 10000,
            p_productionunit => 'ml', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 10000, p_createdby => 'ZZ tester');

        SELECT * INTO v_s FROM sppoultryreport_plsummary(v_farm, v_from, v_to);
        RAISE NOTICE 'I1. the old layer         expect 10000.00  got %', v_s.medicationcost;

        -- Layer two: deferred, and 5,000 of it is used.
        v_medc := sppoultryrawmaterialitem_insert(v_farm, 'ZZ PL New Antibiotic', 'Medication', 'ml', 0, NULL, 'FIFO', 'ml',
                                                  'EXPENSE_WHEN_CONSUMED');
        PERFORM sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_medc,
            p_suppliername => 'ZZ PL Supplier', p_purchasedate => TIMESTAMP '2015-11-02',
            p_quantity => 1000, p_unitcost => 50, p_totalcost => 50000,
            p_productionunit => 'ml', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 50000, p_createdby => 'ZZ tester');

        DECLARE v_rec3 integer;
        BEGIN
            INSERT INTO productionrecords
                (farmid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
                 noofbirdsleft, feedkg, production9am, production12pm, production4pm,
                 totalproduction, sourcetype)
            VALUES (v_farm, 'ZZ tester', 20, 140, DATE '2015-11-20', 100, 0, 100, 0, 0, 0, 0, 0,
                    'ManualSingleFlock')
            RETURNING id INTO v_rec3;
            PERFORM sppoultryproductionrawmaterialsync(
                p_farmid => v_farm, p_productionid => v_rec3, p_createdby => 'ZZ tester',
                p_medicationsjson => ('[{"itemId":' || v_medc::text || ',"qty":100}]'));
        END;

        SELECT * INTO v_s FROM sppoultryreport_plsummary(v_farm, v_from, v_to);
        -- 10,000 purchased + 5,000 consumed. Fifteen thousand, and the 50,000
        -- purchase is nowhere in it.
        RAISE NOTICE 'I2. both layers, once     expect 15000.00  got %', v_s.medicationcost;
    END;

    -- =====================================================================
    -- J. §93 -- every drilldown totals to its line.
    -- =====================================================================
    RAISE NOTICE 'J1. feed drilldown         expect %  got %', v_s.feedcost,
        (SELECT COALESCE(SUM(d.amount), 0) FROM sppoultryreport_plexpensedetail(v_farm, v_from, v_to, 'Feed') d);
    RAISE NOTICE 'J2. medication drilldown   expect %  got %', v_s.medicationcost,
        (SELECT COALESCE(SUM(d.amount), 0) FROM sppoultryreport_plexpensedetail(v_farm, v_from, v_to, 'Medication') d);
    RAISE NOTICE 'J3. depreciation drilldown expect %  got %', v_s.depreciation,
        (SELECT COALESCE(SUM(d.amount), 0) FROM sppoultryreport_pldepreciationdetail(v_farm, v_from, v_to) d);
    RAISE NOTICE 'J4. egg revenue drilldown  expect %  got %', v_s.eggsales,
        (SELECT COALESCE(SUM(d.totalamount), 0) FROM sppoultryreport_plrevenuedetail(v_farm, v_from, v_to, 'EggSales') d);
    RAISE NOTICE 'J5. capital drilldown      expect %  got %', v_s.totalcapitalinvestments,
        (SELECT COALESCE(SUM(d.amount), 0) FROM sppoultryreport_plcapitaldetail(v_farm, v_from, v_to) d);
    RAISE NOTICE 'J6. interest drilldown     expect %  got %', v_s.loaninterest,
        (SELECT COALESCE(SUM(d.amount), 0) FROM sppoultryreport_plfinancingdetail(v_farm, v_from, v_to, 'LoanInterest') d);
    RAISE NOTICE 'J7. owner draws drilldown  expect %  got %', v_s.ownerdraws,
        (SELECT COALESCE(SUM(d.amount), 0) FROM sppoultryreport_plfinancingdetail(v_farm, v_from, v_to, 'OwnerDraws') d);
    RAISE NOTICE 'J8. and the inventory view expect %  got %', v_s.feedcost,
        (SELECT COALESCE(SUM(d.amount), 0) FROM sppoultryreport_plinventorydetail(v_farm, v_from, v_to, 'Feed') d);

    -- The statement and the cards are the same numbers.
    RAISE NOTICE 'J9. statement direct total expect %  got %', v_s.totaldirectcosts,
        (SELECT COALESCE(SUM(l.amount), 0) FROM sppoultryreport_pllines(v_farm, v_from, v_to) l
          WHERE l.section = 'DirectCost');
    RAISE NOTICE 'J10. and nothing informational is in profit expect 0  got %',
        (SELECT COUNT(*)::integer FROM sppoultryreport_pllines(v_farm, v_from, v_to) l
          WHERE l.isinformational AND l.section IN ('Revenue', 'DirectCost', 'OperatingExpense', 'OtherCost'));

    -- =====================================================================
    -- K. The recognition summary the report prints at the top.
    -- =====================================================================
    RAISE NOTICE 'K1. feed setting           expect EXPENSE_WHEN_CONSUMED  got %', v_s.feedrecognitionmethod;
    RAISE NOTICE 'K2. medication setting     expect EXPENSE_WHEN_PURCHASED  got %', v_s.medicationrecognitionmethod;
    RAISE NOTICE 'K3. overrides are in use   expect t  got %', v_s.hasitemoverrides;
    -- How much of this report is inference rather than stated classification.
    RAISE NOTICE 'K4. legacy rows are counted expect t  got %', (v_s.legacyexpenses > 0);
    RAISE NOTICE 'K5. and stated ones too    expect t  got %', (v_s.classifiedexpenses > 0);

    -- =====================================================================
    -- L. The nine-column report still agrees with the new one.
    -- =====================================================================
    DECLARE
        v_old record;
    BEGIN
        SELECT * INTO v_old FROM sppoultryreport_profitloss(v_farm, v_from, v_to);
        RAISE NOTICE 'L1. same revenue           expect %  got %', v_s.totalrevenue, v_old.totalrevenue;
        RAISE NOTICE 'L2. same feed cost         expect %  got %', v_s.feedcost, v_old.feedcost;
        RAISE NOTICE 'L3. same medication        expect %  got %', v_s.medicationcost, v_old.medicinevaccinecost;
        -- Total expenses is direct + operating + other, and excludes the asset.
        RAISE NOTICE 'L4. same total expenses    expect %  got %',
            (v_s.totaldirectcosts + v_s.totaloperatingexpenses + v_s.totalothercosts),
            v_old.totalexpenses;
    END;
END
$t$;

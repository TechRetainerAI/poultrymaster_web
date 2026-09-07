-- Behavioural checks for migration 250: the Generic subscription dashboard and
-- the reports.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates customers, plans, subscriptions,
-- invoices, expenses, staff and a payroll run.
--
--   psql ... -X -c "BEGIN;" -f generic-subscription-reporting.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 250
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- The farm is Saas, which has no sales, no expenses and no subscriptions of its
-- own, so every farm-wide total below is entirely the seed's doing. The two
-- figures that could still be contaminated -- cash at hand and net cash flow --
-- are checked against an independent expression rather than a constant.
--
-- The claims this file tests:
--   1. MRR is normalised per frequency, and OneTime and Draft never count.
--   2. Active / new / lost MRR reconcile: a subscription counts in the month it
--      was cancelled and not in the next.
--   3. The dashboard KPIs agree with the reports they summarise.
--   4. Burn rate and break-even exclude the current PARTIAL month.
--   5. A draft invoice is not revenue, and is an alert instead.
--   6. Labour cost counts staff payments AND paid payroll, and does not double
--      count either.
--
-- Note on the seed: invoices are given amountpaid directly and a payment row is
-- inserted alongside, rather than driving spgenericcustomerpayment_record. The
-- allocation machinery is 244's, and 244's own check file tests it; this file
-- is about what the read side reports, so it seeds the end state directly.

DO $t$
DECLARE
    v_farm text := '056af97f-2099-481c-b5ac-3af20e3ef2b2';   -- Saas (Generic)

    v_m0   date := date_trunc('month', CURRENT_DATE)::date;              -- this month
    v_m1   date := (date_trunc('month', CURRENT_DATE) - interval '1 month')::date;
    v_m2   date := (date_trunc('month', CURRENT_DATE) - interval '2 months')::date;
    v_m3   date := (date_trunc('month', CURRENT_DATE) - interval '3 months')::date;
    -- Anything dated "early this month" has to stay in the PAST, or a run on
    -- the 1st asserts on payments that have not happened yet.
    v_now  date := LEAST(date_trunc('month', CURRENT_DATE)::date + 2, CURRENT_DATE);

    v_cust1 integer; v_cust2 integer;
    v_sup   integer; v_acct integer;
    v_cathost integer; v_catrent integer;
    v_plan1 integer; v_plan2 integer;
    v_sub1  integer; v_sub2 integer; v_sub3 integer; v_sub4 integer; v_sub5 integer;
    v_inv1  integer; v_inv2 integer; v_invdraft integer; v_sale integer;
    v_staff integer; v_run integer;

    v_n integer; v_a numeric; v_b numeric; v_c numeric;
BEGIN
    -- =====================================================================
    -- Setup.
    -- =====================================================================
    INSERT INTO genericcustomers (farmid, customername, paymenttermsdays, isactive, isdeleted)
    VALUES (v_farm, 'ZZ Alpha Ltd', 0, TRUE, FALSE) RETURNING genericcustomerid INTO v_cust1;
    INSERT INTO genericcustomers (farmid, customername, paymenttermsdays, isactive, isdeleted)
    VALUES (v_farm, 'ZZ Beta Ltd', 0, TRUE, FALSE) RETURNING genericcustomerid INTO v_cust2;

    INSERT INTO genericsuppliers (farmid, suppliername, paymenttermsdays, isactive, isdeleted)
    VALUES (v_farm, 'ZZ Cloud Provider', 0, TRUE, FALSE) RETURNING genericsupplierid INTO v_sup;

    -- "Cloud Hosting" matches the suggestion regex; "Office Rent" must not.
    INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted)
    VALUES (v_farm, 'ZZ Cloud Hosting', TRUE, FALSE) RETURNING genericexpensecategoryid INTO v_cathost;
    INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted)
    VALUES (v_farm, 'ZZ Office Rent', TRUE, FALSE) RETURNING genericexpensecategoryid INTO v_catrent;

    INSERT INTO genericcashaccounts (farmid, accountname, accounttype, openingbalance,
                                     currentbalance, allownegativebalance, isactive)
    VALUES (v_farm, 'ZZ Test Bank', 'Bank', 0, 0, FALSE, TRUE)
    RETURNING genericcashaccountid INTO v_acct;

    INSERT INTO genericservices (farmid, servicename, defaultprice, isactive, isdeleted,
                                 plantype, billingfrequency)
    VALUES (v_farm, 'ZZ Pro Plan', 300, TRUE, FALSE, 'Subscription', 'Monthly')
    RETURNING genericserviceid INTO v_plan1;
    INSERT INTO genericservices (farmid, servicename, defaultprice, isactive, isdeleted,
                                 plantype, billingfrequency)
    VALUES (v_farm, 'ZZ Annual Plan', 1200, TRUE, FALSE, 'Subscription', 'Annual')
    RETURNING genericserviceid INTO v_plan2;

    -- sub1: monthly 300, live since two months ago, five days late to bill.
    INSERT INTO genericsubscriptions (farmid, genericcustomerid, genericserviceid, startdate,
                                      billingfrequency, billingamount, nextbillingdate,
                                      autogenerateinvoice, status)
    VALUES (v_farm, v_cust1, v_plan1, v_m2, 'Monthly', 300, CURRENT_DATE - 5, TRUE, 'Active')
    RETURNING genericsubscriptionid INTO v_sub1;

    -- sub2: annual 1200 = 100 a month, started this month.
    INSERT INTO genericsubscriptions (farmid, genericcustomerid, genericserviceid, startdate,
                                      billingfrequency, billingamount, nextbillingdate,
                                      autogenerateinvoice, status)
    VALUES (v_farm, v_cust2, v_plan2, v_m0, 'Annual', 1200, CURRENT_DATE + 10, TRUE, 'Active')
    RETURNING genericsubscriptionid INTO v_sub2;

    -- sub3: monthly 500, ran from three months ago, cancelled mid last month.
    INSERT INTO genericsubscriptions (farmid, genericcustomerid, genericserviceid, startdate,
                                      enddate, billingfrequency, billingamount,
                                      autogenerateinvoice, status, cancelledat, cancellationreason)
    VALUES (v_farm, v_cust2, v_plan1, v_m3, v_m1 + 14, 'Monthly', 500, FALSE, 'Cancelled',
            (v_m1 + 14)::timestamp, 'ZZ test')
    RETURNING genericsubscriptionid INTO v_sub3;

    -- sub4: a one-off fee. Revenue, but NOT recurring revenue.
    INSERT INTO genericsubscriptions (farmid, genericcustomerid, genericserviceid, startdate,
                                      billingfrequency, billingamount, autogenerateinvoice, status)
    VALUES (v_farm, v_cust1, v_plan1, v_m2, 'OneTime', 999, FALSE, 'Active')
    RETURNING genericsubscriptionid INTO v_sub4;

    -- sub5: never activated.
    INSERT INTO genericsubscriptions (farmid, genericcustomerid, genericserviceid, startdate,
                                      billingfrequency, billingamount, autogenerateinvoice, status)
    VALUES (v_farm, v_cust1, v_plan1, v_m0, 'Monthly', 700, TRUE, 'Draft')
    RETURNING genericsubscriptionid INTO v_sub5;

    -- Invoices: two approved, one draft. Plus one ordinary sale.
    INSERT INTO genericsales (farmid, saledate, genericcustomerid, genericsubscriptionid,
                              billingperiodstart, billingperiodend, duedate,
                              subtotalamount, totalamount, amountpaid, balance,
                              paymentstatus, status, isdeleted, salestype)
    VALUES (v_farm, (v_m2 + 2)::timestamp, v_cust1, v_sub1, v_m2, v_m2 + 30, v_m2 + 30,
            300, 300, 300, 0, 'Paid', 'Approved', FALSE, 'Invoice')
    RETURNING genericsaleid INTO v_inv1;

    INSERT INTO genericsales (farmid, saledate, genericcustomerid, genericsubscriptionid,
                              billingperiodstart, billingperiodend, duedate,
                              subtotalamount, totalamount, amountpaid, balance,
                              paymentstatus, status, isdeleted, salestype)
    VALUES (v_farm, (v_m1 + 2)::timestamp, v_cust1, v_sub1, v_m1, v_m1 + 30, CURRENT_DATE - 10,
            300, 300, 100, 200, 'Partial', 'Approved', FALSE, 'Invoice')
    RETURNING genericsaleid INTO v_inv2;

    INSERT INTO genericsales (farmid, saledate, genericcustomerid, genericsubscriptionid,
                              billingperiodstart, billingperiodend, duedate,
                              subtotalamount, totalamount, amountpaid, balance,
                              paymentstatus, status, isdeleted, salestype)
    VALUES (v_farm, v_now::timestamp, v_cust1, v_sub1, v_m0, v_m0 + 30, v_m0 + 30,
            300, 300, 0, 300, 'Unpaid', 'Draft', FALSE, 'Invoice')
    RETURNING genericsaleid INTO v_invdraft;

    INSERT INTO genericsales (farmid, saledate, genericcustomerid,
                              subtotalamount, totalamount, amountpaid, balance,
                              paymentstatus, status, isdeleted, salestype)
    VALUES (v_farm, v_now::timestamp, v_cust2, 250, 250, 250, 0,
            'Paid', 'Approved', FALSE, 'Counter')
    RETURNING genericsaleid INTO v_sale;

    INSERT INTO genericcustomerpayments (farmid, genericcustomerid, paymentdate, amount,
                                         paymentmethod, genericcashaccountid, status)
    VALUES (v_farm, v_cust1, v_now::timestamp, 400, 'Cash', v_acct, 'Approved');

    -- Expenses: 600 hosting + 300 rent in each of the three COMPLETE months
    -- before this one, so the burn rate is exactly 900. The current month's 600
    -- must not touch it.
    INSERT INTO genericexpenses (farmid, expensedate, genericexpensecategoryid, genericsupplierid,
                                 description, amount, paymentmethod, amountpaid, status, isdeleted)
    SELECT v_farm, (m + 3)::timestamp, v_cathost, v_sup, 'ZZ hosting', 600, 'Bank', 600, 'Approved', FALSE
    FROM   (VALUES (v_m3), (v_m2), (v_m1)) AS t(m);

    INSERT INTO genericexpenses (farmid, expensedate, genericexpensecategoryid,
                                 description, amount, paymentmethod, amountpaid, status, isdeleted)
    SELECT v_farm, (m + 3)::timestamp, v_catrent, 'ZZ rent', 300, 'Cash', 300, 'Approved', FALSE
    FROM   (VALUES (v_m3), (v_m2), (v_m1)) AS t(m);

    -- This month's hosting bill is UNPAID, so it is also a payable.
    INSERT INTO genericexpenses (farmid, expensedate, genericexpensecategoryid, genericsupplierid,
                                 description, amount, paymentmethod, amountpaid, duedate,
                                 status, isdeleted)
    VALUES (v_farm, v_now::timestamp, v_cathost, v_sup, 'ZZ hosting', 600, 'Bank', 0,
            CURRENT_DATE + 5, 'Approved', FALSE);

    INSERT INTO genericstaff (farmid, firstname, lastname, role, isactive, isdeleted, workertype)
    VALUES (v_farm, 'ZZ', 'Developer', 'Engineer', TRUE, FALSE, 'Contractor')
    RETURNING genericstaffid INTO v_staff;

    INSERT INTO genericstaffpayments (farmid, genericstaffid, paymentdate, amount,
                                      paymentmethod, genericcashaccountid, status)
    VALUES (v_farm, v_staff, v_now::timestamp, 400, 'Bank', v_acct, 'Posted');

    -- Paid on the 3rd of this month for last month's work. The pay DATE is what
    -- the reports window on, so it has to be in the past or the checks below
    -- would be asserting on a payment that has not happened yet.
    INSERT INTO genericpayrollruns (farmid, periodstart, periodend, paydate, totalnetpay,
                                    status, isdeleted)
    VALUES (v_farm, v_m1, v_m1 + 27, v_now, 250, 'Paid', FALSE)
    RETURNING genericpayrollrunid INTO v_run;

    -- netpay is a GENERATED column: basic + wage + commission + bonus - deductions.
    INSERT INTO genericpayrollitems (genericpayrollrunid, genericstaffid, basicpay)
    VALUES (v_run, v_staff, 250);

    -- =====================================================================
    -- A. One amount, normalised to a month.
    -- =====================================================================
    RAISE NOTICE 'A1. monthly 300            expect   300.00  got %', fngenericmonthlyamount(300, 'Monthly');
    RAISE NOTICE 'A2. annual 1200            expect   100.00  got %', fngenericmonthlyamount(1200, 'Annual');
    RAISE NOTICE 'A3. quarterly 300          expect   100.00  got %', fngenericmonthlyamount(300, 'Quarterly');
    RAISE NOTICE 'A4. termly 400             expect   100.00  got %', fngenericmonthlyamount(400, 'Termly');
    RAISE NOTICE 'A5. semiannual 600         expect   100.00  got %', fngenericmonthlyamount(600, 'SemiAnnual');
    -- 52 weeks a year, not 4 a month: 100 * 52 / 12.
    RAISE NOTICE 'A6. weekly 100             expect   433.33  got %', fngenericmonthlyamount(100, 'Weekly');
    RAISE NOTICE 'A7. one-time 999           expect     0.00  got %', fngenericmonthlyamount(999, 'OneTime');
    RAISE NOTICE 'A8. unknown frequency      expect     0.00  got %', fngenericmonthlyamount(999, 'Fortnightly');

    -- =====================================================================
    -- B. The month grid. OneTime and Draft are not on it at all.
    -- =====================================================================
    RAISE NOTICE 'B1. one-time not on grid   expect        0  got %',
        (SELECT COUNT(*) FROM fngenericsubscriptionmonths(v_farm, v_m3, v_m0) g
          WHERE g.genericsubscriptionid = v_sub4);
    RAISE NOTICE 'B2. draft not on grid      expect        0  got %',
        (SELECT COUNT(*) FROM fngenericsubscriptionmonths(v_farm, v_m3, v_m0) g
          WHERE g.genericsubscriptionid = v_sub5);
    -- sub1 started two months ago and is still live: three months.
    RAISE NOTICE 'B3. sub1 spans 3 months    expect        3  got %',
        (SELECT COUNT(*) FROM fngenericsubscriptionmonths(v_farm, v_m3, v_m0) g
          WHERE g.genericsubscriptionid = v_sub1);
    -- sub3 ran from three months ago to the middle of last month: three months,
    -- INCLUDING the month it was cancelled in.
    RAISE NOTICE 'B4. sub3 spans 3 months    expect        3  got %',
        (SELECT COUNT(*) FROM fngenericsubscriptionmonths(v_farm, v_m3, v_m0) g
          WHERE g.genericsubscriptionid = v_sub3);
    RAISE NOTICE 'B5. sub3 gone this month   expect        0  got %',
        (SELECT COUNT(*) FROM fngenericsubscriptionmonths(v_farm, v_m0, v_m0) g
          WHERE g.genericsubscriptionid = v_sub3);

    -- =====================================================================
    -- C. Active / new / lost MRR reconcile month to month.
    -- =====================================================================
    RAISE NOTICE 'C1. MRR 3 months ago       expect   500.00  got %',
        (SELECT activemrr FROM spgenericreport_mrr(v_farm, v_m3, v_m0) WHERE monthstart = v_m3);
    RAISE NOTICE 'C2. MRR 2 months ago       expect   800.00  got %',
        (SELECT activemrr FROM spgenericreport_mrr(v_farm, v_m3, v_m0) WHERE monthstart = v_m2);
    RAISE NOTICE 'C3. new MRR 2 months ago   expect   300.00  got %',
        (SELECT newmrr FROM spgenericreport_mrr(v_farm, v_m3, v_m0) WHERE monthstart = v_m2);
    RAISE NOTICE 'C4. MRR last month         expect   800.00  got %',
        (SELECT activemrr FROM spgenericreport_mrr(v_farm, v_m3, v_m0) WHERE monthstart = v_m1);
    RAISE NOTICE 'C5. lost MRR last month    expect   500.00  got %',
        (SELECT lostmrr FROM spgenericreport_mrr(v_farm, v_m3, v_m0) WHERE monthstart = v_m1);
    -- 800 last month, minus the 500 lost, plus 100 of new annual plan = 400.
    RAISE NOTICE 'C6. MRR this month         expect   400.00  got %',
        (SELECT activemrr FROM spgenericreport_mrr(v_farm, v_m3, v_m0) WHERE monthstart = v_m0);
    RAISE NOTICE 'C7. new MRR this month     expect   100.00  got %',
        (SELECT newmrr FROM spgenericreport_mrr(v_farm, v_m3, v_m0) WHERE monthstart = v_m0);
    -- Last month's active, less what it lost, plus this month's new, IS this
    -- month's active. If this line fails the two columns are telling different
    -- stories.
    SELECT activemrr INTO v_a FROM spgenericreport_mrr(v_farm, v_m3, v_m0) WHERE monthstart = v_m1;
    SELECT lostmrr   INTO v_b FROM spgenericreport_mrr(v_farm, v_m3, v_m0) WHERE monthstart = v_m1;
    SELECT newmrr    INTO v_c FROM spgenericreport_mrr(v_farm, v_m3, v_m0) WHERE monthstart = v_m0;
    RAISE NOTICE 'C8. it reconciles          expect   400.00  got %', (v_a - v_b + v_c);
    RAISE NOTICE 'C9. expansion not guessed  expect     0.00  got %',
        (SELECT expansionmrr FROM spgenericreport_mrr(v_farm, v_m3, v_m0) WHERE monthstart = v_m0);

    -- =====================================================================
    -- D. The dashboard KPIs.
    -- =====================================================================
    RAISE NOTICE 'D1. dashboard MRR          expect   400.00  got %',
        (SELECT monthlyrecurringrevenue FROM spgenericsubdashboard_rs1(v_farm));
    RAISE NOTICE 'D2. active subscriptions   expect        2  got %',
        (SELECT activesubscriptions FROM spgenericsubdashboard_rs1(v_farm));
    RAISE NOTICE 'D3. active customers       expect        2  got %',
        (SELECT activecustomers FROM spgenericsubdashboard_rs1(v_farm));
    RAISE NOTICE 'D4. collected this month   expect   400.00  got %',
        (SELECT paymentscollected FROM spgenericsubdashboard_rs1(v_farm));
    RAISE NOTICE 'D5. expenses this month    expect   600.00  got %',
        (SELECT expensespaid FROM spgenericsubdashboard_rs1(v_farm));
    -- The draft invoice is not revenue.
    RAISE NOTICE 'D6. invoiced this month    expect     0.00  got %',
        (SELECT invoicedthismonth FROM spgenericsubdashboard_rs1(v_farm));
    RAISE NOTICE 'D7. customer balances      expect   200.00  got %',
        (SELECT customerbalances FROM spgenericsubdashboard_rs1(v_farm));
    RAISE NOTICE 'D8. supplier balances      expect   600.00  got %',
        (SELECT supplierbalances FROM spgenericsubdashboard_rs1(v_farm));
    RAISE NOTICE 'D9. overdue customers      expect        1  got %',
        (SELECT overduecustomers FROM spgenericsubdashboard_rs1(v_farm));
    RAISE NOTICE 'D10. overdue amount        expect   200.00  got %',
        (SELECT overdueamount FROM spgenericsubdashboard_rs1(v_farm));
    -- 2700 over three COMPLETE months. This month's 600 is not in it.
    RAISE NOTICE 'D11. burn rate             expect   900.00  got %',
        (SELECT monthlyburnrate FROM spgenericsubdashboard_rs1(v_farm));
    -- 900 burn / (400 MRR / 2 customers) = 4.5, rounded up.
    RAISE NOTICE 'D12. break-even customers  expect        5  got %',
        (SELECT breakevencustomers FROM spgenericsubdashboard_rs1(v_farm));
    RAISE NOTICE 'D13. new subs this month   expect        1  got %',
        (SELECT newsubscriptions FROM spgenericsubdashboard_rs1(v_farm));
    RAISE NOTICE 'D14. cancelled this month  expect        0  got %',
        (SELECT cancelledsubscriptions FROM spgenericsubdashboard_rs1(v_farm));
    RAISE NOTICE 'D15. cancelled LAST month  expect        1  got %',
        (SELECT cancelledsubscriptions FROM spgenericsubdashboard_rs1(v_farm, v_m1 + 20));
    -- Cash at hand and net cash flow are farm-wide and this farm may hold cash
    -- from elsewhere, so they are checked against their own definition rather
    -- than a constant.
    RAISE NOTICE 'D16. cash at hand agrees   expect        t  got %',
        (SELECT d.cashathand = (SELECT COALESCE(SUM(a.currentbalance), 0)
                                  FROM genericcashaccounts a
                                 WHERE a.farmid = v_farm AND a.isactive)
           FROM spgenericsubdashboard_rs1(v_farm) d);

    -- =====================================================================
    -- E. Renewals, overdue debtors, alerts.
    -- =====================================================================
    -- sub1 was due five days ago: it is on the list, with a NEGATIVE daysuntil.
    RAISE NOTICE 'E1. sub1 is late to bill   expect       -5  got %',
        (SELECT daysuntil FROM spgenericsubdashboard_rs2(v_farm)
          WHERE genericsubscriptionid = v_sub1);
    RAISE NOTICE 'E2. sub2 renews in 10      expect       10  got %',
        (SELECT daysuntil FROM spgenericsubdashboard_rs2(v_farm)
          WHERE genericsubscriptionid = v_sub2);
    RAISE NOTICE 'E3. cancelled sub excluded expect        0  got %',
        (SELECT COUNT(*) FROM spgenericsubdashboard_rs2(v_farm)
          WHERE genericsubscriptionid = v_sub3);
    RAISE NOTICE 'E4. one overdue debtor     expect        1  got %',
        (SELECT COUNT(*) FROM spgenericsubdashboard_rs3(v_farm));
    RAISE NOTICE 'E5. and it is Alpha, 200   expect   200.00  got %',
        (SELECT overdueamount FROM spgenericsubdashboard_rs3(v_farm) WHERE partyid = v_cust1);
    RAISE NOTICE 'E6. alerts: due to bill    expect        1  got %',
        (SELECT duetobillcount FROM spgenericsubdashboard_rs7(v_farm));
    RAISE NOTICE 'E7. alerts: draft invoice  expect        1  got %',
        (SELECT draftinvoicecount FROM spgenericsubdashboard_rs7(v_farm));
    RAISE NOTICE 'E8. alerts: draft amount   expect   300.00  got %',
        (SELECT draftinvoiceamount FROM spgenericsubdashboard_rs7(v_farm));
    RAISE NOTICE 'E9. alerts: overdue amount expect   200.00  got %',
        (SELECT overduecustomeramount FROM spgenericsubdashboard_rs7(v_farm));
    -- The dashboard cannot disagree with the balances page it summarises.
    RAISE NOTICE 'E10. alerts match KPI      expect        t  got %',
        ((SELECT overduecustomeramount FROM spgenericsubdashboard_rs7(v_farm))
         = (SELECT overdueamount FROM spgenericsubdashboard_rs1(v_farm)));

    -- =====================================================================
    -- F. Subscription revenue.
    -- =====================================================================
    RAISE NOTICE 'F1. invoiced 2 months ago  expect   300.00  got %',
        (SELECT invoicedamount FROM spgenericreport_subscriptionrevenue_rs1(v_farm, v_m3, v_m0)
          WHERE monthstart = v_m2);
    RAISE NOTICE 'F2. collected on it        expect   300.00  got %',
        (SELECT collectedamount FROM spgenericreport_subscriptionrevenue_rs1(v_farm, v_m3, v_m0)
          WHERE monthstart = v_m2);
    RAISE NOTICE 'F3. outstanding last month expect   200.00  got %',
        (SELECT outstanding FROM spgenericreport_subscriptionrevenue_rs1(v_farm, v_m3, v_m0)
          WHERE monthstart = v_m1);
    -- The draft invoice is not revenue here either.
    RAISE NOTICE 'F4. invoiced this month    expect     0.00  got %',
        (SELECT invoicedamount FROM spgenericreport_subscriptionrevenue_rs1(v_farm, v_m3, v_m0)
          WHERE monthstart = v_m0);
    -- Every month appears, including the empty one three months back.
    RAISE NOTICE 'F5. four month rows        expect        4  got %',
        (SELECT COUNT(*) FROM spgenericreport_subscriptionrevenue_rs1(v_farm, v_m3, v_m0));
    RAISE NOTICE 'F6. Pro plan invoiced      expect   600.00  got %',
        (SELECT invoicedamount FROM spgenericreport_subscriptionrevenue_rs2(v_farm, v_m3, v_m0)
          WHERE genericserviceid = v_plan1);
    -- The annual plan billed nothing yet but still has to appear: that row is
    -- the whole point of the report.
    RAISE NOTICE 'F7. Annual plan listed     expect   100.00  got %',
        (SELECT activemrr FROM spgenericreport_subscriptionrevenue_rs2(v_farm, v_m3, v_m0)
          WHERE genericserviceid = v_plan2);
    RAISE NOTICE 'F8. Alpha invoiced         expect   600.00  got %',
        (SELECT invoicedamount FROM spgenericreport_subscriptionrevenue_rs3(v_farm, v_m3, v_m0)
          WHERE genericcustomerid = v_cust1);
    RAISE NOTICE 'F9. Alpha still owes       expect   200.00  got %',
        (SELECT outstanding FROM spgenericreport_subscriptionrevenue_rs3(v_farm, v_m3, v_m0)
          WHERE genericcustomerid = v_cust1);

    -- =====================================================================
    -- G. The income split, and that it still adds up to the P&L.
    -- =====================================================================
    RAISE NOTICE 'G1. subscription income    expect   600.00  got %',
        (SELECT subscriptionincome FROM spgenericreport_incomesplit(v_farm, v_m3, CURRENT_DATE));
    RAISE NOTICE 'G2. other income           expect   250.00  got %',
        (SELECT otherincome FROM spgenericreport_incomesplit(v_farm, v_m3, CURRENT_DATE));
    -- The split must equal what the existing P&L reports as income, or the
    -- page shows two different revenues.
    RAISE NOTICE 'G3. split = P&L income     expect        t  got %',
        ((SELECT totalincome FROM spgenericreport_incomesplit(v_farm, v_m3, CURRENT_DATE))
         = (SELECT totalincome FROM spgenericreport_periodpnl(v_farm, v_m3, CURRENT_DATE)));

    -- =====================================================================
    -- H. Expenses by supplier and the trend.
    -- =====================================================================
    RAISE NOTICE 'H1. cloud provider total   expect  2400.00  got %',
        (SELECT totalamount FROM spgenericreport_expensesbysupplier(v_farm, v_m3, CURRENT_DATE)
          WHERE genericsupplierid = v_sup);
    RAISE NOTICE 'H2. and 600 unpaid         expect   600.00  got %',
        (SELECT outstanding FROM spgenericreport_expensesbysupplier(v_farm, v_m3, CURRENT_DATE)
          WHERE genericsupplierid = v_sup);
    -- Rent has no supplier and must still be reported.
    RAISE NOTICE 'H3. no-supplier row        expect   900.00  got %',
        (SELECT totalamount FROM spgenericreport_expensesbysupplier(v_farm, v_m3, CURRENT_DATE)
          WHERE genericsupplierid IS NULL);
    RAISE NOTICE 'H4. trend last month       expect   900.00  got %',
        (SELECT totalamount FROM spgenericreport_expensetrend(v_farm, v_m3, CURRENT_DATE)
          WHERE monthstart = v_m1);
    RAISE NOTICE 'H5. trend staff this month expect   400.00  got %',
        (SELECT staffamount FROM spgenericreport_expensetrend(v_farm, v_m3, CURRENT_DATE)
          WHERE monthstart = v_m0);

    -- =====================================================================
    -- I. Hosting cost.
    -- =====================================================================
    RAISE NOTICE 'I1. hosting suggested      expect        t  got %',
        (SELECT issuggested FROM spgenericreport_hostingcategories(v_farm)
          WHERE genericexpensecategoryid = v_cathost);
    RAISE NOTICE 'I2. rent NOT suggested     expect        f  got %',
        (SELECT issuggested FROM spgenericreport_hostingcategories(v_farm)
          WHERE genericexpensecategoryid = v_catrent);
    RAISE NOTICE 'I3. hosting last month     expect   600.00  got %',
        (SELECT hostingcost FROM spgenericreport_hostingcost(v_farm, v_m3, CURRENT_DATE)
          WHERE monthstart = v_m1);
    -- 600 of 900 spent last month.
    RAISE NOTICE 'I4. share of expenses      expect    66.67  got %',
        (SELECT pctofexpenses FROM spgenericreport_hostingcost(v_farm, v_m3, CURRENT_DATE)
          WHERE monthstart = v_m1);
    -- An explicit empty selection means none, NOT "fall back to the guess".
    RAISE NOTICE 'I5. explicit none is none  expect     0.00  got %',
        (SELECT hostingcost FROM spgenericreport_hostingcost(v_farm, v_m3, CURRENT_DATE, ARRAY[]::integer[])
          WHERE monthstart = v_m1);
    RAISE NOTICE 'I6. rent chosen by hand    expect   300.00  got %',
        (SELECT hostingcost FROM spgenericreport_hostingcost(v_farm, v_m3, CURRENT_DATE, ARRAY[v_catrent])
          WHERE monthstart = v_m1);

    -- =====================================================================
    -- J. Labour cost: payments AND payroll, counted once each.
    -- =====================================================================
    RAISE NOTICE 'J1. staff payments         expect   400.00  got %',
        (SELECT staffpayments FROM spgenericreport_staffcost_rs1(v_farm, v_m0, CURRENT_DATE)
          WHERE genericstaffid = v_staff);
    RAISE NOTICE 'J2. payroll                expect   250.00  got %',
        (SELECT payrollpay FROM spgenericreport_staffcost_rs1(v_farm, v_m0, CURRENT_DATE)
          WHERE genericstaffid = v_staff);
    RAISE NOTICE 'J3. total is the sum       expect   650.00  got %',
        (SELECT totalpaid FROM spgenericreport_staffcost_rs1(v_farm, v_m0, CURRENT_DATE)
          WHERE genericstaffid = v_staff);
    RAISE NOTICE 'J4. one person paid        expect        1  got %',
        (SELECT peoplepaid FROM spgenericreport_staffcost_rs2(v_farm, v_m0, CURRENT_DATE)
          WHERE monthstart = v_m0);
    RAISE NOTICE 'J5. all of it is Engineer  expect   100.00  got %',
        (SELECT pctoftotal FROM spgenericreport_staffcost_rs3(v_farm, v_m0, CURRENT_DATE)
          WHERE staffrole = 'Engineer');
    RAISE NOTICE 'J6. dashboard agrees       expect   650.00  got %',
        (SELECT totalpaid FROM spgenericsubdashboard_rs8(v_farm));

    -- =====================================================================
    -- K. Break-even.
    -- =====================================================================
    RAISE NOTICE 'K1. fixed costs a month    expect   900.00  got %',
        (SELECT monthlyfixedcosts FROM spgenericreport_breakeven(v_farm));
    RAISE NOTICE 'K2. average per customer   expect   200.00  got %',
        (SELECT avgrevenuepercustomer FROM spgenericreport_breakeven(v_farm));
    RAISE NOTICE 'K3. customers needed       expect        5  got %',
        (SELECT breakevencustomers FROM spgenericreport_breakeven(v_farm));
    RAISE NOTICE 'K4. three short           expect       -3  got %',
        (SELECT customersurplus FROM spgenericreport_breakeven(v_farm));
    RAISE NOTICE 'K5. monthly shortfall      expect  -500.00  got %',
        (SELECT monthlysurplus FROM spgenericreport_breakeven(v_farm));
    -- The window it averaged ENDS on the last day of last month. If this ever
    -- reaches into the current month the answer silently halves.
    RAISE NOTICE 'K6. window ends last month expect        t  got %',
        (SELECT periodend = (v_m0 - 1) FROM spgenericreport_breakeven(v_farm));
    RAISE NOTICE 'K7. dashboard agrees       expect        t  got %',
        ((SELECT breakevencustomers FROM spgenericreport_breakeven(v_farm))
         = (SELECT breakevencustomers FROM spgenericsubdashboard_rs1(v_farm)));

    -- =====================================================================
    -- L. Recent activity and the expense breakdown.
    -- =====================================================================
    RAISE NOTICE 'L1. activity feed has rows expect        t  got %',
        (SELECT COUNT(*) > 0 FROM spgenericsubdashboard_rs6(v_farm));
    -- An expense reads as money OUT: negative.
    RAISE NOTICE 'L2. an expense is negative expect     t  got %',
        (SELECT MIN(amount) < 0 FROM spgenericsubdashboard_rs6(v_farm, 100));
    RAISE NOTICE 'L3. hosting is this months expect   600.00  got %',
        (SELECT totalamount FROM spgenericsubdashboard_rs4(v_farm)
          WHERE genericexpensecategoryid = v_cathost);
    RAISE NOTICE 'L4. and it is 100 pct      expect   100.00  got %',
        (SELECT pctoftotal FROM spgenericsubdashboard_rs4(v_farm)
          WHERE genericexpensecategoryid = v_cathost);
END
$t$;

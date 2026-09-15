-- =============================================================================
-- 272_PoultryProfitLossRedesign.postgres.sql
--
-- Purpose
-- -------
-- Phase 3, part 4: a Profit & Loss report that answers the question an owner is
-- actually asking -- did the business make money from its operations this month?
--
-- FROM THREE NUMBERS TO FOUR
-- ==========================
-- Today the report is Revenue, Total Expenses, Net Profit. Everything a farm
-- spends is one undifferentiated pile, so there is no way to tell a bad month
-- from a month with a new poultry house in it.
--
--   Revenue
--   - Direct Production Costs      feed, medication, flock, production supplies
--   = GROSS PROFIT                 is the farming itself profitable?
--   - Operating Expenses           payroll, utilities, transport, admin
--   = OPERATING PROFIT             is the BUSINESS profitable?
--   - Depreciation & Financing     the cost of the assets and of the borrowing
--   = NET PROFIT                   what is actually left
--
-- and, beside it and never inside it:
--
--   FINANCING & OWNER ACTIVITY     owner money in and out, loans in and out
--   CAPITAL INVESTMENTS            what was bought that will last
--
-- WHAT MOVES AND WHAT DOES NOT
-- ============================
-- Total expenses do NOT move. Nothing existing is reclassified out of profit --
-- no farm has a capital asset or a deferred inventory purchase yet, so the set
-- of rows that count is byte-for-byte the set that counts today.
--
-- What moves is WHERE they land. 73 raw-material purchases stop falling into
-- "Other" and appear as Feed Cost and Medication, because 269 can now ask the
-- item instead of the description. That is the whole point of the exercise and
-- it is a correction, not a change of policy.
--
-- WHY TWO FUNCTIONS AND NOT ONE
-- =============================
--   ..._plsummary   one row: the totals and the subtotals, for the KPI cards
--   ..._pllines     one row per line: for the statement and its drilldowns
--
-- One function returning forty columns would have to be edited every time a
-- farm invents a category. A line list does not, and it is also what makes each
-- figure clickable: the drilldown asks for the same line key the statement
-- printed, so a drilldown can never disagree with the number above it.
--
-- ONLY NON-ZERO LINES ARE RETURNED
-- ================================
-- A farm with no marketing spend gets no Marketing row rather than a row of
-- zeros. §38 asks for "Other" to be broken down, not for twenty empty lines to
-- be shown; the sections still carry their own totals from the summary.
--
-- THE LEGACY NOTE IS NOW HONEST
-- =============================
-- The old warning said "expenses by category keyword; anything unrecognised
-- falls under Other". The summary now returns legacyexpenses -- how many rows in
-- the period carry no stated classification -- so the report can say precisely
-- how much of itself is inference rather than claiming all of it is.
--
-- WHAT THIS FILE IS NOT
-- =====================
-- It is not a change to Cash Flow. sppoultrycashflow_* is untouched: capital
-- payments, inventory payments, owner draws and loan principal all still move
-- cash exactly as they do today, and that is the whole reason profit and cash
-- are allowed to differ.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The one place that decides what belongs in a period's profit.
--
-- Every function below reads this, so the summary, the statement, the drilldowns
-- and the exports cannot each grow their own idea of "an expense".
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrypl_expenselines(
    p_farmid text, p_startdate date, p_enddate date
) RETURNS TABLE(expenseid integer, expensedate timestamp without time zone,
                category text, description text, amount numeric,
                supplierid integer, suppliername text, sourcetype text, sourceid integer,
                paymentmethod text, paymentstatus text, amountpaid numeric,
                costtype text, plline text, plsection text,
                poultrycapitalassetid integer, islegacy boolean)
LANGUAGE sql STABLE
AS $function$
    SELECT e.expenseid, e.expensedate, e.category::text, e.description::text,
           e.amount::numeric(14,2), e.supplierid, s.name::text,
           e.sourcetype::text, e.sourceid, e.paymentmethod::text,
           e.paymentstatus::text, COALESCE(e.amountpaid, e.amount)::numeric(14,2),
           c.costtype, l.line, fnpoultryexpense_plsection(l.line),
           e.poultrycapitalassetid,
           (COALESCE(e.financialcosttype, '') = '')
    FROM   expense e
    LEFT   JOIN supplier s ON s.supplierid = e.supplierid
    CROSS  JOIN LATERAL (SELECT fnpoultryexpense_costtype(
                                    e.financialcosttype::text, e.sourcetype::text,
                                    e.category::text, e.paymentmethod::text) AS costtype) c
    CROSS  JOIN LATERAL (SELECT fnpoultryexpense_plline(
                                    c.costtype, e.sourcetype::text, e.category::text,
                                    fnpoultryexpense_itemcategory(e.sourcetype::text, e.sourceid)) AS line) l
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  e.expensedate >= p_startdate
      AND  e.expensedate < (p_enddate + 1);
$function$;

COMMENT ON FUNCTION public.fnpoultrypl_expenselines(text, date, date) IS
    'Every expense row in a period with its cost type, P&L line and section '
    'resolved. The single source the P&L report and all its drilldowns read.';

-- The same for revenue.
CREATE OR REPLACE FUNCTION public.fnpoultrypl_revenuelines(
    p_farmid text, p_startdate date, p_enddate date
) RETURNS TABLE(saleid integer, saledate timestamp without time zone, product text,
                customername text, quantity numeric, unitprice numeric,
                totalamount numeric, amountpaid numeric, paymentmethod text,
                revenueline text)
LANGUAGE sql STABLE
AS $function$
    -- Revenue is SALES, not cash in. Owner contributions, loans received and
    -- transfers between the farm's own accounts all raise the bank balance and
    -- none of them is money the business earned, so none of them is here.
    SELECT sa.saleid, sa.saledate, sa.product::text, sa.customername::text,
           sa.quantity, sa.unitprice, sa.totalamount::numeric(14,2),
           COALESCE(sa.amountpaid, sa.totalamount)::numeric(14,2),
           sa.paymentmethod::text,
           fnpoultrysale_revenueline(sa.product::text)
    FROM   sale sa
    WHERE  sa.farmid = p_farmid
      AND  sa.saledate >= p_startdate
      AND  sa.saledate < (p_enddate + 1);
$function$;

-- -----------------------------------------------------------------------------
-- 2. The statement, one line at a time.
--
-- sortorder carries the printing order so the caller never has to know it, and
-- the section keys are the same four bands fnpoultryexpense_plsection returns
-- plus the two informational ones that are deliberately outside profit.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryreport_pllines(
    p_farmid text, p_startdate date, p_enddate date
) RETURNS TABLE(section text, linekey text, linelabel text, amount numeric,
                sortorder integer, isinformational boolean, entrycount integer)
LANGUAGE sql STABLE
AS $function$
    WITH rev AS (
        SELECT r.revenueline AS k, SUM(r.totalamount) AS amt, COUNT(*)::integer AS n
        FROM   fnpoultrypl_revenuelines(p_farmid, p_startdate, p_enddate) r
        GROUP  BY r.revenueline
    ),
    exp AS (
        SELECT e.plsection AS sec, e.plline AS k, SUM(e.amount) AS amt, COUNT(*)::integer AS n
        FROM   fnpoultrypl_expenselines(p_farmid, p_startdate, p_enddate) e
        WHERE  e.plsection <> 'Excluded'
        GROUP  BY e.plsection, e.plline
    ),
    -- Informational. Cash moved and profit did not.
    fin AS (
        SELECT 'OwnerContributions' AS k,
               COALESCE(SUM(o.amount), 0) AS amt, COUNT(*)::integer AS n
        FROM   poultryownermoney o
        WHERE  o.farmid = p_farmid AND o.status = 'Posted'
          AND  o.transactiontype = 'Contribution'
          AND  o.transactiondate >= p_startdate AND o.transactiondate < (p_enddate + 1)
        UNION ALL
        SELECT 'OwnerDraws', COALESCE(SUM(o.amount), 0), COUNT(*)::integer
        FROM   poultryownermoney o
        WHERE  o.farmid = p_farmid AND o.status = 'Posted'
          AND  o.transactiontype = 'Draw'
          AND  o.transactiondate >= p_startdate AND o.transactiondate < (p_enddate + 1)
        UNION ALL
        SELECT 'LoansReceived', COALESCE(SUM(l.amountreceived), 0), COUNT(*)::integer
        FROM   poultryloans l
        WHERE  l.farmid = p_farmid AND l.status NOT IN ('Reversed', 'Cancelled', 'Draft')
          AND  l.loandate >= p_startdate AND l.loandate < (p_enddate + 1)
        UNION ALL
        SELECT 'LoanPrincipalRepaid', COALESCE(SUM(pm.principalamount), 0), COUNT(*)::integer
        FROM   poultryloanpayments pm
        WHERE  pm.farmid = p_farmid AND pm.status = 'Posted'
          AND  pm.paymentdate >= p_startdate AND pm.paymentdate < (p_enddate + 1)
    ),
    cap AS (
        SELECT COALESCE(cat.categoryname, 'Other Assets')::text AS k,
               SUM(cc.amount) AS amt, COUNT(*)::integer AS n
        FROM   poultrycapitalassetcosts cc
        JOIN   poultrycapitalassets a ON a.poultrycapitalassetid = cc.poultrycapitalassetid
        LEFT   JOIN poultryassetcategories cat ON cat.poultryassetcategoryid = a.poultryassetcategoryid
        WHERE  cc.farmid = p_farmid AND cc.status = 'Posted'
          AND  cc.costdate >= p_startdate AND cc.costdate <= p_enddate
        GROUP  BY COALESCE(cat.categoryname, 'Other Assets')
    )
    SELECT 'Revenue', rev.k, fnpoultrysale_revenuelabel(rev.k), rev.amt::numeric(14,2),
           CASE rev.k WHEN 'EggSales' THEN 1 WHEN 'BirdSales' THEN 2
                      WHEN 'ManureSales' THEN 3 WHEN 'FeedSales' THEN 4 ELSE 5 END,
           FALSE, rev.n
    FROM   rev WHERE rev.amt <> 0
    UNION ALL
    SELECT exp.sec, exp.k, fnpoultryexpense_pllinelabel(exp.k), exp.amt::numeric(14,2),
           CASE exp.k
                WHEN 'Feed' THEN 11 WHEN 'Medication' THEN 12 WHEN 'DirectLabour' THEN 13
                WHEN 'ProductionSupplies' THEN 14 WHEN 'FlockCost' THEN 15 WHEN 'OtherDirect' THEN 16
                WHEN 'Payroll' THEN 21 WHEN 'Utilities' THEN 22 WHEN 'Transport' THEN 23
                WHEN 'RepairsMaintenance' THEN 24 WHEN 'Rent' THEN 25 WHEN 'Marketing' THEN 26
                WHEN 'Insurance' THEN 27 WHEN 'Security' THEN 28 WHEN 'ProfessionalServices' THEN 29
                WHEN 'Communications' THEN 30 WHEN 'Administration' THEN 31 WHEN 'OtherOperating' THEN 32
                WHEN 'Depreciation' THEN 41 WHEN 'LoanInterest' THEN 42
                WHEN 'LoanFees' THEN 43 WHEN 'OtherFinancing' THEN 44
                ELSE 99 END,
           FALSE, exp.n
    FROM   exp WHERE exp.amt <> 0
    UNION ALL
    SELECT 'Financing', fin.k,
           CASE fin.k WHEN 'OwnerContributions' THEN 'Owner Contributions'
                      WHEN 'OwnerDraws' THEN 'Owner Draws'
                      WHEN 'LoansReceived' THEN 'Loans Received'
                      ELSE 'Loan Principal Repaid' END,
           fin.amt::numeric(14,2),
           CASE fin.k WHEN 'OwnerContributions' THEN 51 WHEN 'OwnerDraws' THEN 52
                      WHEN 'LoansReceived' THEN 53 ELSE 54 END,
           TRUE, fin.n
    FROM   fin WHERE fin.amt <> 0
    UNION ALL
    SELECT 'CapitalInvestment', cap.k, cap.k, cap.amt::numeric(14,2), 61, TRUE, cap.n
    FROM   cap WHERE cap.amt <> 0
    ORDER  BY 5, 2;
$function$;

COMMENT ON FUNCTION public.sppoultryreport_pllines(text, date, date) IS
    'The P&L statement, one line per figure. Sections Revenue / DirectCost / '
    'OperatingExpense / OtherCost are profit; Financing and CapitalInvestment '
    'are informational and never enter a total.';

-- -----------------------------------------------------------------------------
-- 3. The summary.
--
-- Every subtotal is derived from the same line list, so a card and the statement
-- under it cannot disagree.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryreport_plsummary(
    p_farmid text, p_startdate date, p_enddate date
) RETURNS TABLE(
    startdate date, enddate date,
    eggsales numeric, birdsales numeric, manuresales numeric, feedsales numeric,
    otherrevenue numeric, totalrevenue numeric,
    feedcost numeric, medicationcost numeric, directlabour numeric,
    productionsupplies numeric, flockcost numeric, otherdirectcosts numeric,
    totaldirectcosts numeric,
    grossprofit numeric, grossmarginpercent numeric,
    payroll numeric, utilities numeric, transport numeric, repairsmaintenance numeric,
    administration numeric, marketing numeric, otheroperatingexpenses numeric,
    totaloperatingexpenses numeric,
    operatingprofit numeric, operatingmarginpercent numeric,
    depreciation numeric, loaninterest numeric, loanfees numeric,
    otherfinancingcosts numeric, totalothercosts numeric,
    netprofit numeric, netmarginpercent numeric, status text,
    ownercontributions numeric, ownerdraws numeric, netownerfunding numeric,
    loansreceived numeric, loanprincipalrepaid numeric, netborrowing numeric,
    totalcapitalinvestments numeric,
    feedrecognitionmethod text, medicationrecognitionmethod text,
    hasitemoverrides boolean, recognitionconfigured boolean,
    legacyexpenses integer, classifiedexpenses integer)
LANGUAGE sql STABLE
AS $function$
    WITH lines AS (
        SELECT * FROM sppoultryreport_pllines(p_farmid, p_startdate, p_enddate)
    ),
    agg AS (
        SELECT
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'EggSales'), 0)     AS eggsales,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'BirdSales'), 0)    AS birdsales,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'ManureSales'), 0)  AS manuresales,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'FeedSales'), 0)    AS feedsales,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'OtherRevenue'), 0) AS otherrevenue,
            COALESCE(SUM(amount) FILTER (WHERE section = 'Revenue'), 0)      AS totalrevenue,

            COALESCE(SUM(amount) FILTER (WHERE linekey = 'Feed'), 0)               AS feedcost,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'Medication'), 0)         AS medicationcost,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'DirectLabour'), 0)       AS directlabour,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'ProductionSupplies'), 0) AS productionsupplies,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'FlockCost'), 0)          AS flockcost,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'OtherDirect'), 0)        AS otherdirectcosts,
            COALESCE(SUM(amount) FILTER (WHERE section = 'DirectCost'), 0)         AS totaldirectcosts,

            COALESCE(SUM(amount) FILTER (WHERE linekey = 'Payroll'), 0)            AS payroll,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'Utilities'), 0)          AS utilities,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'Transport'), 0)          AS transport,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'RepairsMaintenance'), 0) AS repairsmaintenance,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'Administration'), 0)     AS administration,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'Marketing'), 0)          AS marketing,
            -- Everything operating that is not one of the six named lines. Kept
            -- as one figure HERE and broken out line by line in
            -- sppoultryreport_pllines, which is what §38 asks for: no
            -- undifferentiated "Other" that cannot be opened.
            COALESCE(SUM(amount) FILTER (WHERE section = 'OperatingExpense'
                     AND linekey NOT IN ('Payroll', 'Utilities', 'Transport',
                                         'RepairsMaintenance', 'Administration', 'Marketing')), 0)
                                                                                   AS otheroperating,
            COALESCE(SUM(amount) FILTER (WHERE section = 'OperatingExpense'), 0)   AS totaloperating,

            COALESCE(SUM(amount) FILTER (WHERE linekey = 'Depreciation'), 0)       AS depreciation,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'LoanInterest'), 0)       AS loaninterest,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'LoanFees'), 0)           AS loanfees,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'OtherFinancing'), 0)     AS otherfinancing,
            COALESCE(SUM(amount) FILTER (WHERE section = 'OtherCost'), 0)          AS totalother,

            COALESCE(SUM(amount) FILTER (WHERE linekey = 'OwnerContributions'), 0)  AS ownercontrib,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'OwnerDraws'), 0)          AS ownerdraws,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'LoansReceived'), 0)       AS loansreceived,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'LoanPrincipalRepaid'), 0) AS principalrepaid,
            COALESCE(SUM(amount) FILTER (WHERE section = 'CapitalInvestment'), 0)   AS capital
        FROM lines
    ),
    calc AS (
        SELECT a.*,
               (a.totalrevenue - a.totaldirectcosts)                                    AS grossprofit,
               (a.totalrevenue - a.totaldirectcosts - a.totaloperating)                 AS operatingprofit,
               (a.totalrevenue - a.totaldirectcosts - a.totaloperating - a.totalother)  AS netprofit
        FROM agg a
    ),
    cls AS (
        SELECT COUNT(*) FILTER (WHERE e.islegacy)::integer     AS legacycount,
               COUNT(*) FILTER (WHERE NOT e.islegacy)::integer AS statedcount
        FROM   fnpoultrypl_expenselines(p_farmid, p_startdate, p_enddate) e
    )
    SELECT p_startdate, p_enddate,
           c.eggsales::numeric(14,2), c.birdsales::numeric(14,2),
           c.manuresales::numeric(14,2), c.feedsales::numeric(14,2),
           c.otherrevenue::numeric(14,2), c.totalrevenue::numeric(14,2),
           c.feedcost::numeric(14,2), c.medicationcost::numeric(14,2),
           c.directlabour::numeric(14,2), c.productionsupplies::numeric(14,2),
           c.flockcost::numeric(14,2), c.otherdirectcosts::numeric(14,2),
           c.totaldirectcosts::numeric(14,2),
           c.grossprofit::numeric(14,2),
           -- Zero revenue is not a 0% margin: there is no meaningful percentage
           -- of nothing, so it comes back NULL rather than a misleading zero.
           CASE WHEN c.totalrevenue = 0 THEN NULL
                ELSE ROUND(c.grossprofit / c.totalrevenue * 100, 1) END,
           c.payroll::numeric(14,2), c.utilities::numeric(14,2),
           c.transport::numeric(14,2), c.repairsmaintenance::numeric(14,2),
           c.administration::numeric(14,2), c.marketing::numeric(14,2),
           c.otheroperating::numeric(14,2), c.totaloperating::numeric(14,2),
           c.operatingprofit::numeric(14,2),
           CASE WHEN c.totalrevenue = 0 THEN NULL
                ELSE ROUND(c.operatingprofit / c.totalrevenue * 100, 1) END,
           c.depreciation::numeric(14,2), c.loaninterest::numeric(14,2),
           c.loanfees::numeric(14,2), c.otherfinancing::numeric(14,2),
           c.totalother::numeric(14,2),
           c.netprofit::numeric(14,2),
           CASE WHEN c.totalrevenue = 0 THEN NULL
                ELSE ROUND(c.netprofit / c.totalrevenue * 100, 1) END,
           CASE WHEN c.netprofit > 0 THEN 'Profit'
                WHEN c.netprofit < 0 THEN 'Loss' ELSE 'Break-even' END,
           -- Informational. None of the four is in any total above.
           c.ownercontrib::numeric(14,2), c.ownerdraws::numeric(14,2),
           (c.ownercontrib - c.ownerdraws)::numeric(14,2),
           c.loansreceived::numeric(14,2), c.principalrepaid::numeric(14,2),
           (c.loansreceived - c.principalrepaid)::numeric(14,2),
           c.capital::numeric(14,2),
           fs.feedcostrecognitionmethod, fs.medicationcostrecognitionmethod,
           EXISTS (SELECT 1 FROM poultryrawmaterialitems i
                    WHERE i.farmid = p_farmid AND i.costrecognitionoverride IS NOT NULL),
           fs.isconfigured,
           cl.legacycount, cl.statedcount
    FROM   calc c
    CROSS  JOIN cls cl
    CROSS  JOIN LATERAL sppoultryfinancialsettings_get(p_farmid) fs;
$function$;

COMMENT ON FUNCTION public.sppoultryreport_plsummary(text, date, date) IS
    'The P&L cards and every subtotal, derived from sppoultryreport_pllines so a '
    'card can never disagree with the statement under it.';

-- -----------------------------------------------------------------------------
-- 4. Drilldowns. Each one totals to the line above it, because each one reads
--    the same function the line was built from.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryreport_plexpensedetail(
    p_farmid text, p_startdate date, p_enddate date, p_linekey text
) RETURNS TABLE(expenseid integer, expensedate timestamp without time zone,
                category text, description text, amount numeric,
                suppliername text, sourcetype text, sourcelabel text,
                paymentmethod text, paymentstatus text, costtype text,
                plline text, pllinelabel text,
                poultrycapitalassetid integer, islegacy boolean)
LANGUAGE sql STABLE
AS $function$
    SELECT e.expenseid, e.expensedate, e.category, e.description, e.amount,
           e.suppliername, e.sourcetype, fnpoultryexpense_sourcelabel(e.sourcetype),
           e.paymentmethod, e.paymentstatus, e.costtype,
           e.plline, fnpoultryexpense_pllinelabel(e.plline),
           e.poultrycapitalassetid, e.islegacy
    FROM   fnpoultrypl_expenselines(p_farmid, p_startdate, p_enddate) e
    WHERE  (p_linekey IS NULL OR e.plline = p_linekey)
      AND  e.plsection <> 'Excluded'
    ORDER  BY e.expensedate DESC, e.expenseid DESC;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryreport_plrevenuedetail(
    p_farmid text, p_startdate date, p_enddate date, p_linekey text
) RETURNS TABLE(saleid integer, saledate timestamp without time zone, product text,
                customername text, quantity numeric, unitprice numeric,
                totalamount numeric, amountpaid numeric, paymentmethod text,
                revenueline text, revenuelabel text)
LANGUAGE sql STABLE
AS $function$
    SELECT r.saleid, r.saledate, r.product, r.customername, r.quantity, r.unitprice,
           r.totalamount, r.amountpaid, r.paymentmethod,
           r.revenueline, fnpoultrysale_revenuelabel(r.revenueline)
    FROM   fnpoultrypl_revenuelines(p_farmid, p_startdate, p_enddate) r
    WHERE  (p_linekey IS NULL OR r.revenueline = p_linekey)
    ORDER  BY r.saledate DESC, r.saleid DESC;
$function$;

-- Feed and medication have a richer drilldown than a list of expense rows,
-- because the SAME line can be fed by two different recognitions: a purchase
-- under expense-at-purchase and a consumption under expense-at-consumption. A
-- period spanning a settings change legitimately contains both, and the
-- recognition column is what stops that reading as double counting.
CREATE OR REPLACE FUNCTION public.sppoultryreport_plinventorydetail(
    p_farmid text, p_startdate date, p_enddate date, p_linekey text
) RETURNS TABLE(expenseid integer, expensedate timestamp without time zone,
                itemname text, itemcategory text, description text,
                amount numeric, sourcetype text, sourcelabel text,
                recognition text, sourceid integer,
                quantity numeric, unitofmeasure text, costlayers integer)
LANGUAGE sql STABLE
AS $function$
    SELECT e.expenseid, e.expensedate,
           pi.itemname::text,
           fnpoultryexpense_itemcategory(e.sourcetype, e.sourceid),
           e.description, e.amount, e.sourcetype,
           fnpoultryexpense_sourcelabel(e.sourcetype),
           -- The column that stops a mixed period reading as double counting.
           -- A period spanning a settings change legitimately contains BOTH a
           -- purchase recognised at purchase and a consumption recognised at
           -- consumption, and they are different stock.
           CASE WHEN e.sourcetype IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption')
                     THEN 'Expense when consumed'
                WHEN e.sourcetype = 'PoultryRawMaterialPurchase'
                     THEN 'Expense when purchased'
                ELSE 'Recorded directly' END,
           e.sourceid,
           p.quantity, pi.unitofmeasure::text,
           -- How many purchase lots the consumption drew from. Null for a
           -- purchase row, which is one lot by definition.
           CASE WHEN e.sourcetype IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption')
                THEN (SELECT COUNT(*)::integer
                        FROM poultryrawmaterialusagebatch b
                        JOIN poultryrawmaterialusage u
                          ON u.poultryrawmaterialusageid = b.poultryrawmaterialusageid
                       WHERE u.productionrecordid = e.sourceid AND u.farmid = p_farmid)
                ELSE NULL END
    FROM   fnpoultrypl_expenselines(p_farmid, p_startdate, p_enddate) e
    LEFT   JOIN poultryrawmaterialpurchases p
           ON  p.poultryrawmaterialpurchaseid = e.sourceid
           AND e.sourcetype = 'PoultryRawMaterialPurchase'
    LEFT   JOIN poultryrawmaterialitems pi ON pi.poultryrawmaterialitemid = p.poultryrawmaterialitemid
    WHERE  e.plline = p_linekey AND e.plsection = 'DirectCost'
    ORDER  BY e.expensedate DESC, e.expenseid DESC;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryreport_pldepreciationdetail(
    p_farmid text, p_startdate date, p_enddate date
) RETURNS TABLE(poultryassetdepreciationid integer, poultrycapitalassetid integer,
                assetnumber text, assetname text, categoryname text,
                periodstart date, periodend date, amount numeric,
                originalcost numeric, monthlydepreciation numeric,
                accumulateddepreciation numeric, currentbookvalue numeric,
                sourcetype text, status text)
LANGUAGE sql STABLE
AS $function$
    SELECT d.poultryassetdepreciationid, d.poultrycapitalassetid,
           a.assetnumber::text, a.assetname::text, c.categoryname::text,
           d.periodstart, d.periodend, d.amount,
           f.originalcost, f.monthlydepreciation,
           f.accumulateddepreciation, f.currentbookvalue,
           d.sourcetype::text, d.status::text
    FROM   poultryassetdepreciation d
    JOIN   poultrycapitalassets a ON a.poultrycapitalassetid = d.poultrycapitalassetid
    LEFT   JOIN poultryassetcategories c ON c.poultryassetcategoryid = a.poultryassetcategoryid
    CROSS  JOIN LATERAL fnpoultrycapitalasset_financials(a.poultrycapitalassetid) f
    WHERE  d.farmid = p_farmid
      AND  d.depreciationdate >= p_startdate AND d.depreciationdate <= p_enddate
    ORDER  BY d.depreciationdate DESC, d.poultryassetdepreciationid DESC;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryreport_plfinancingdetail(
    p_farmid text, p_startdate date, p_enddate date, p_linekey text DEFAULT NULL
) RETURNS TABLE(linekey text, entrydate date, reference text, party text,
                description text, amount numeric, entryid integer)
LANGUAGE sql STABLE
AS $function$
    -- Interest and fees. The PRINCIPAL is deliberately not here: repaying what
    -- was borrowed is not a cost, and showing it beside the interest is exactly
    -- the mistake this section exists to prevent.
    SELECT 'LoanInterest', pm.paymentdate::date, pm.paymentnumber::text, l.lendername::text,
           'Interest on loan ' || l.loannumber, pm.interestamount, pm.poultryloanpaymentid
    FROM   poultryloanpayments pm
    JOIN   poultryloans l ON l.poultryloanid = pm.poultryloanid
    WHERE  pm.farmid = p_farmid AND pm.status = 'Posted' AND pm.interestamount > 0
      AND  pm.paymentdate >= p_startdate AND pm.paymentdate < (p_enddate + 1)
      AND  (p_linekey IS NULL OR p_linekey = 'LoanInterest')
    UNION ALL
    SELECT 'LoanFees', pm.paymentdate::date, pm.paymentnumber::text, l.lendername::text,
           'Fee on loan ' || l.loannumber, pm.feeamount, pm.poultryloanpaymentid
    FROM   poultryloanpayments pm
    JOIN   poultryloans l ON l.poultryloanid = pm.poultryloanid
    WHERE  pm.farmid = p_farmid AND pm.status = 'Posted' AND pm.feeamount > 0
      AND  pm.paymentdate >= p_startdate AND pm.paymentdate < (p_enddate + 1)
      AND  (p_linekey IS NULL OR p_linekey = 'LoanFees')
    UNION ALL
    SELECT 'Owner' || o.transactiontype || 's',
           o.transactiondate::date, o.transactionnumber::text, o.ownername::text,
           COALESCE(o.notes, 'Owner ' || lower(o.transactiontype)), o.amount, o.poultryownermoneyid
    FROM   poultryownermoney o
    WHERE  o.farmid = p_farmid AND o.status = 'Posted'
      AND  o.transactiondate >= p_startdate AND o.transactiondate < (p_enddate + 1)
      AND  (p_linekey IS NULL OR p_linekey = 'Owner' || o.transactiontype || 's')
    UNION ALL
    SELECT 'LoansReceived', l.loandate::date, l.loannumber::text, l.lendername::text,
           'Loan received', l.amountreceived, l.poultryloanid
    FROM   poultryloans l
    WHERE  l.farmid = p_farmid AND l.status NOT IN ('Reversed', 'Cancelled', 'Draft')
      AND  l.loandate >= p_startdate AND l.loandate < (p_enddate + 1)
      AND  (p_linekey IS NULL OR p_linekey = 'LoansReceived')
    UNION ALL
    SELECT 'LoanPrincipalRepaid', pm.paymentdate::date, pm.paymentnumber::text, l.lendername::text,
           'Principal on loan ' || l.loannumber, pm.principalamount, pm.poultryloanpaymentid
    FROM   poultryloanpayments pm
    JOIN   poultryloans l ON l.poultryloanid = pm.poultryloanid
    WHERE  pm.farmid = p_farmid AND pm.status = 'Posted' AND pm.principalamount > 0
      AND  pm.paymentdate >= p_startdate AND pm.paymentdate < (p_enddate + 1)
      AND  (p_linekey IS NULL OR p_linekey = 'LoanPrincipalRepaid')
    ORDER  BY 2 DESC, 1;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryreport_plcapitaldetail(
    p_farmid text, p_startdate date, p_enddate date
) RETURNS TABLE(poultrycapitalassetcostid integer, poultrycapitalassetid integer,
                assetnumber text, assetname text, categoryname text,
                costdate date, description text, costcategory text, amount numeric,
                suppliername text, expenseid integer, assetstatus text,
                originalcost numeric, currentbookvalue numeric)
LANGUAGE sql STABLE
AS $function$
    SELECT cc.poultrycapitalassetcostid, cc.poultrycapitalassetid,
           a.assetnumber::text, a.assetname::text,
           COALESCE(cat.categoryname, 'Other Assets')::text,
           cc.costdate, cc.description::text, cc.costcategory::text, cc.amount,
           s.name::text, cc.expenseid, a.status::text,
           f.originalcost, f.currentbookvalue
    FROM   poultrycapitalassetcosts cc
    JOIN   poultrycapitalassets a ON a.poultrycapitalassetid = cc.poultrycapitalassetid
    LEFT   JOIN poultryassetcategories cat ON cat.poultryassetcategoryid = a.poultryassetcategoryid
    LEFT   JOIN supplier s ON s.supplierid = cc.supplierid
    CROSS  JOIN LATERAL fnpoultrycapitalasset_financials(a.poultrycapitalassetid) f
    WHERE  cc.farmid = p_farmid AND cc.status = 'Posted'
      AND  cc.costdate >= p_startdate AND cc.costdate <= p_enddate
    ORDER  BY cc.costdate DESC, cc.poultrycapitalassetcostid DESC;
$function$;

-- -----------------------------------------------------------------------------
-- 5. The existing report, rebuilt on the new classification.
--
-- Reproduced with its EXACT nine-column shape, because the dashboard, the
-- per-flock report and the exports all read it and none of them should have to
-- change on the same day. What changes is only where a cedi lands:
--
--   feedcost   now includes raw-material FEED purchases, resolved from the item
--   medicine   the same for medication
--   labor      unchanged
--   other      correspondingly smaller
--   total      UNCHANGED -- nothing is excluded that was not excluded before
--
-- Capital and deferred-inventory rows are excluded from the total, which is the
-- one behavioural change. No farm has such a row today, so today's totals do not
-- move; the exclusion is what keeps them from moving wrongly tomorrow.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryreport_profitloss(p_farmid text, p_startdate date, p_enddate date)
 RETURNS TABLE(eggrevenue numeric, birdsalesrevenue numeric, otherrevenue numeric, totalrevenue numeric,
               feedcost numeric, medicinevaccinecost numeric, laborcost numeric,
               otherexpenses numeric, totalexpenses numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH rev AS (
        SELECT COALESCE(SUM(r.totalamount) FILTER (WHERE r.revenueline = 'EggSales'), 0)  AS egg,
               COALESCE(SUM(r.totalamount) FILTER (WHERE r.revenueline = 'BirdSales'), 0) AS bird,
               COALESCE(SUM(r.totalamount), 0)                                            AS tot
        FROM   fnpoultrypl_revenuelines(p_farmid, p_startdate, p_enddate) r
    ),
    cost AS (
        SELECT COALESCE(SUM(e.amount) FILTER (WHERE e.plline = 'Feed'), 0)         AS feed,
               COALESCE(SUM(e.amount) FILTER (WHERE e.plline = 'Medication'), 0)   AS med,
               COALESCE(SUM(e.amount) FILTER (WHERE e.plline IN ('Payroll', 'DirectLabour')), 0) AS labour,
               COALESCE(SUM(e.amount) FILTER (WHERE e.plline NOT IN
                            ('Feed', 'Medication', 'Payroll', 'DirectLabour')), 0)  AS other,
               COALESCE(SUM(e.amount), 0)                                          AS tot
        FROM   fnpoultrypl_expenselines(p_farmid, p_startdate, p_enddate) e
        WHERE  e.plsection <> 'Excluded'
    )
    SELECT rev.egg::numeric(14,2),
           rev.bird::numeric(14,2),
           (rev.tot - rev.egg - rev.bird)::numeric(14,2),
           rev.tot::numeric(14,2),
           cost.feed::numeric(14,2),
           cost.med::numeric(14,2),
           cost.labour::numeric(14,2),
           cost.other::numeric(14,2),
           cost.tot::numeric(14,2)
    FROM   rev CROSS JOIN cost;
$function$;

COMMENT ON FUNCTION public.sppoultryreport_profitloss(text, date, date) IS
    'The nine-column company P&L, since 272 built on the structured '
    'classification rather than on category keywords. Same shape, same total, '
    'costs on the right lines.';


-- -----------------------------------------------------------------------------
-- 6. A Phase 2 defect this report makes visible: consumption was dated NOW.
--
-- sppoultryproductionrawmaterialsync recognised feed and medication with
-- now(), not with the date of the production record. Nothing before this
-- migration could see the difference -- the old report grouped by category, not
-- by anything that cared which month a cost belonged to.
--
-- It matters now. A farm that enters Friday's records on Monday, or catches up a
-- week at the end of the week, would have every one of those feed costs land in
-- the month the typing happened rather than the month the birds ate. §61 is
-- explicit that the selected period governs, and a September report that omits
-- September's feed because it was keyed in October is simply wrong.
--
-- Both functions below are reproduced from their LIVE definitions. The ONLY
-- change is the date: every line of costing, allocation, reversal and restore is
-- byte for byte what it was.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryconsumption_unrecognise(
    p_farmid     text,
    p_sourcetype text,
    p_sourceid   integer,
    p_category   text,
    p_reason     text,
    p_createdby  text
) RETURNS numeric
LANGUAGE plpgsql
AS $function$
DECLARE
    v_gid  uuid;
    v_net  numeric(14,2);
    v_date timestamp;
BEGIN
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;
    IF v_gid IS NULL THEN RETURN 0; END IF;

    -- 272. Dated with the rows it is cancelling, so the compensation lands in
    -- the same period as the charge. A reversal that fell into the next month
    -- would leave one month overstated and the next understated, and both
    -- reports would be wrong while the pair still netted to zero.
    SELECT COALESCE(SUM(e.amount), 0)::numeric(14,2), MAX(e.expensedate)
      INTO v_net, v_date
    FROM   expense e
    WHERE  e.farmid = v_gid AND e.sourcetype = p_sourcetype AND e.sourceid = p_sourceid;

    IF COALESCE(v_net, 0) = 0 THEN
        RETURN 0;
    END IF;

    INSERT INTO expense
        (expensedate, category, description, amount, paymentmethod, supplier, flockid,
         createddate, userid, farmid, sourcetype, sourceid, amountpaid)
    VALUES
        (COALESCE(v_date, (now() at time zone 'utc')), p_category, p_reason,
         -v_net, 'NonCash', NULL, NULL,
         (now() at time zone 'utc'), p_createdby, v_gid,
         p_sourcetype, p_sourceid, -v_net);

    RETURN v_net;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryproductionrawmaterialsync(p_farmid text, p_productionid integer, p_feeditemid integer DEFAULT NULL::integer, p_feedqty numeric DEFAULT NULL::numeric, p_meditemid integer DEFAULT NULL::integer, p_medqty numeric DEFAULT NULL::numeric, p_createdby text DEFAULT NULL::text, p_medicationsjson text DEFAULT NULL::text, p_feedsjson text DEFAULT NULL::text, OUT computedfeedunitcost numeric, OUT computedtotalfeedcost numeric, OUT computedmedicationunitcost numeric, OUT computedtotalmedicationcost numeric)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_recdate timestamp;          -- 272: the date the CONSUMPTION happened
    v_ispurereversal boolean;
    v_feedtotalcost  numeric := 0;
    v_feedtotalqty   numeric := 0;
    v_appliedanyfeed boolean := FALSE;
    v_medtotalcost   numeric := 0;
    v_medtotalqty    numeric := 0;
    v_appliedanymed  boolean := FALSE;
    v_usageid        integer;
    v_lineunitcost   numeric;
    v_linetotal      numeric;
    v_linename       text;
    -- 266. What each draw actually deferred, and the running totals that become
    -- the two consumption expenses.
    v_linedeferred   numeric(14,2);
    v_feeddeferred   numeric(14,2) := 0;
    v_meddeferred    numeric(14,2) := 0;
    v_rec            record;
BEGIN
    -- 272. Recognition is dated to the PRODUCTION RECORD, not to the moment
    -- the row happens to be saved. A farm entering Monday what the birds ate
    -- on Friday must not have Friday's feed cost land in the wrong month --
    -- and the P&L is now period-accurate enough for that to be visible.
    SELECT pr.date::timestamp INTO v_recdate
    FROM   productionrecords pr
    WHERE  pr.id = p_productionid AND pr.farmid = p_farmid;
    v_recdate := COALESCE(v_recdate, (now() at time zone 'utc'));

    computedfeedunitcost := NULL; computedtotalfeedcost := NULL;
    computedmedicationunitcost := NULL; computedtotalmedicationcost := NULL;

    -- Build the feed / medication lines to (re)apply up-front so we can tell a PURE
    -- REVERSAL (nothing to re-apply - the delete path) from a re-apply (insert/edit).
    DROP TABLE IF EXISTS tmp_prms_feedlines;
    CREATE TEMP TABLE tmp_prms_feedlines (seq integer, itemid integer, qty numeric) ON COMMIT DROP;
    IF (p_feedsjson IS NOT NULL AND length(p_feedsjson) > 0) THEN
        INSERT INTO tmp_prms_feedlines (seq, itemid, qty)
        SELECT row_number() OVER (ORDER BY x.ord), x.itemid, x.qty
        FROM (SELECT (e.value->>'itemId')::integer AS itemid,
                     (e.value->>'qty')::numeric(14,3) AS qty,
                     e.ord
              FROM jsonb_array_elements(p_feedsjson::jsonb) WITH ORDINALITY AS e(value, ord)) x
        WHERE x.itemid IS NOT NULL AND COALESCE(x.qty, 0) > 0;
    ELSIF (p_feeditemid IS NOT NULL AND COALESCE(p_feedqty, 0) > 0) THEN
        INSERT INTO tmp_prms_feedlines (seq, itemid, qty) VALUES (1, p_feeditemid, p_feedqty);
    END IF;

    DROP TABLE IF EXISTS tmp_prms_medlines;
    CREATE TEMP TABLE tmp_prms_medlines (seq integer, itemid integer, qty numeric) ON COMMIT DROP;
    IF (p_medicationsjson IS NOT NULL AND length(p_medicationsjson) > 0) THEN
        INSERT INTO tmp_prms_medlines (seq, itemid, qty)
        SELECT row_number() OVER (ORDER BY x.ord), x.itemid, x.qty
        FROM (SELECT (e.value->>'itemId')::integer AS itemid,
                     (e.value->>'qty')::numeric(14,3) AS qty,
                     e.ord
              FROM jsonb_array_elements(p_medicationsjson::jsonb) WITH ORDINALITY AS e(value, ord)) x
        WHERE x.itemid IS NOT NULL AND COALESCE(x.qty, 0) > 0;
    ELSIF (p_meditemid IS NOT NULL AND COALESCE(p_medqty, 0) > 0) THEN
        INSERT INTO tmp_prms_medlines (seq, itemid, qty) VALUES (1, p_meditemid, p_medqty);
    END IF;

    v_ispurereversal := (NOT EXISTS (SELECT 1 FROM tmp_prms_feedlines)
                         AND NOT EXISTS (SELECT 1 FROM tmp_prms_medlines));

    -- 266. Whatever this record has recognised so far is about to stop being
    -- true -- the lines are being restored and, on an edit, rewritten. Give it
    -- back FIRST, with one opposite row, before anything else moves. Doing it
    -- here rather than at the end means a failure part-way through cannot leave
    -- an expense standing for stock that was handed back.
    PERFORM sppoultryconsumption_unrecognise(
        p_farmid, 'PoultryFeedConsumption', p_productionid, 'Feed Cost',
        'Reversal of feed consumption (record #' || p_productionid::text || ')', p_createdby);
    PERFORM sppoultryconsumption_unrecognise(
        p_farmid, 'PoultryMedicationConsumption', p_productionid, 'Medication',
        'Reversal of medication consumption (record #' || p_productionid::text || ')', p_createdby);

    -- 1. Reverse this record's still-live consumption. Restore the drawn lots +
    --    CurrentQuantity (scoped to non-reversed rows so a later edit never
    --    double-restores).
    DROP TABLE IF EXISTS tmp_prms_restore;
    CREATE TEMP TABLE tmp_prms_restore ON COMMIT DROP AS
    SELECT u.poultryrawmaterialitemid AS itemid, SUM(u.quantityused) AS qty
    FROM poultryrawmaterialusage u
    WHERE u.farmid = p_farmid AND u.productionrecordid = p_productionid AND u.isreversed = FALSE
    GROUP BY u.poultryrawmaterialitemid;

    UPDATE poultryrawmaterialpurchases p
    SET remainingquantity = p.remainingquantity + bb.qty,
        -- 266. The deferred cost comes back with the stock, from the exact
        -- allocations that took it. Without this the same stock could be
        -- consumed twice and only be expensed once.
        --
        -- LEAST caps it at what the lot started with: restoring more deferred
        -- cost than a lot ever had would create money, and the check constraint
        -- from 264 would refuse the row anyway.
        deferredremainingcost = LEAST(p.deferredremainingcost + bb.deferred, p.deferredtotalcost),
        updatedat = (now() at time zone 'utc')
    FROM (
        SELECT b.poultryrawmaterialpurchaseid AS purchaseid, SUM(b.quantitydrawn) AS qty,
               SUM(b.deferredcostdrawn) AS deferred
        FROM poultryrawmaterialusagebatch b
        JOIN poultryrawmaterialusage u ON u.poultryrawmaterialusageid = b.poultryrawmaterialusageid
        WHERE u.farmid = p_farmid AND u.productionrecordid = p_productionid AND u.isreversed = FALSE
        GROUP BY b.poultryrawmaterialpurchaseid
    ) bb
    WHERE bb.purchaseid = p.poultryrawmaterialpurchaseid;

    UPDATE poultryrawmaterialitems it
    SET currentquantity = it.currentquantity + r.qty,
        updatedat = (now() at time zone 'utc')
    FROM tmp_prms_restore r
    WHERE r.itemid = it.poultryrawmaterialitemid AND it.farmid = p_farmid;

    IF v_ispurereversal THEN
        -- KEEP the original usage rows (append-only ledger); flag them reversed so
        -- they drop out of the next restore aggregate.
        UPDATE poultryrawmaterialusage u
        SET isreversed = TRUE, reversedat = (now() at time zone 'utc')
        WHERE u.farmid = p_farmid AND u.productionrecordid = p_productionid AND u.isreversed = FALSE;

        -- Compensating IN adjustment per item - the visible opposite entry, and it
        -- keeps recalc (purchases - usage + adjustments) consistent with the restore.
        INSERT INTO poultryrawmaterialadjustments (farmid, poultryrawmaterialitemid, adjusteddate, quantity, movementtype, note, createdby)
        SELECT p_farmid, r.itemid, (now() at time zone 'utc'), r.qty, 'ProductionReversal',
               'Reversal of production consumption (record #' || p_productionid::text || ')', p_createdby
        FROM tmp_prms_restore r WHERE r.qty <> 0;
    ELSE
        -- Re-apply (insert/edit): physically remove the current live usage rows;
        -- the loops below rewrite them. Reversed rows (if any) are left untouched.
        DELETE FROM poultryrawmaterialusage u
        WHERE u.farmid = p_farmid AND u.productionrecordid = p_productionid AND u.isreversed = FALSE;
    END IF;

    -- Costing detail is current-state (not a stock ledger) - keep replacing it.
    DELETE FROM productionrecordfeeds f
    WHERE f.farmid = p_farmid AND f.productionrecordid = p_productionid;

    DELETE FROM productionrecordmedications m
    WHERE m.farmid = p_farmid AND m.productionrecordid = p_productionid;

    -- 2. Apply feed consumption from the lines built above.
    FOR v_rec IN SELECT fl.itemid, fl.qty FROM tmp_prms_feedlines fl ORDER BY fl.seq LOOP
        IF (v_rec.itemid IS NOT NULL AND v_rec.qty > 0) THEN
            v_lineunitcost := NULL;
            INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, productionrecordid, quantityused, notes, createdby)
            VALUES (p_farmid, v_rec.itemid, p_productionid, v_rec.qty, 'Feed used in production', p_createdby)
            RETURNING poultryrawmaterialusageid INTO v_usageid;

            v_lineunitcost := sppoultryrawmaterialitem_consumebatches(p_farmid, v_rec.itemid, v_usageid, v_rec.qty);

            -- 266. Read the deferred share the engine has just recorded, per
            -- lot. A draw that crossed an old expensed lot and a new deferred
            -- one contributes only the second.
            v_linedeferred := COALESCE((
                SELECT SUM(b.deferredcostdrawn) FROM poultryrawmaterialusagebatch b
                WHERE  b.poultryrawmaterialusageid = v_usageid), 0);
            v_feeddeferred := v_feeddeferred + v_linedeferred;

            UPDATE poultryrawmaterialitems it
            SET currentquantity = it.currentquantity - v_rec.qty,
                updatedat = (now() at time zone 'utc')
            WHERE it.poultryrawmaterialitemid = v_rec.itemid AND it.farmid = p_farmid;

            SELECT it.itemname INTO v_linename FROM poultryrawmaterialitems it
            WHERE it.poultryrawmaterialitemid = v_rec.itemid AND it.farmid = p_farmid;
            v_linetotal := (COALESCE(v_lineunitcost, 0) * v_rec.qty)::numeric(14,2);

            INSERT INTO productionrecordfeeds (farmid, productionrecordid, poultryrawmaterialitemid, itemname, quantityconsumed, unitcost, totalcost)
            VALUES (p_farmid, p_productionid, v_rec.itemid, v_linename, v_rec.qty, COALESCE(v_lineunitcost, 0), v_linetotal);

            v_feedtotalcost := v_feedtotalcost + v_linetotal;
            v_feedtotalqty  := v_feedtotalqty + v_rec.qty;
            v_appliedanyfeed := TRUE;
        END IF;
    END LOOP;

    IF v_appliedanyfeed THEN
        computedfeedunitcost := CASE WHEN v_feedtotalqty > 0 THEN v_feedtotalcost / v_feedtotalqty ELSE NULL END;
        computedtotalfeedcost := v_feedtotalcost;
    END IF;

    -- 3. Apply medication consumption from the lines built above.
    FOR v_rec IN SELECT ml.itemid, ml.qty FROM tmp_prms_medlines ml ORDER BY ml.seq LOOP
        IF (v_rec.itemid IS NOT NULL AND v_rec.qty > 0) THEN
            v_lineunitcost := NULL;
            INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, productionrecordid, quantityused, notes, createdby)
            VALUES (p_farmid, v_rec.itemid, p_productionid, v_rec.qty, 'Medication used in production', p_createdby)
            RETURNING poultryrawmaterialusageid INTO v_usageid;

            v_lineunitcost := sppoultryrawmaterialitem_consumebatches(p_farmid, v_rec.itemid, v_usageid, v_rec.qty);

            v_linedeferred := COALESCE((
                SELECT SUM(b.deferredcostdrawn) FROM poultryrawmaterialusagebatch b
                WHERE  b.poultryrawmaterialusageid = v_usageid), 0);
            v_meddeferred := v_meddeferred + v_linedeferred;

            UPDATE poultryrawmaterialitems it
            SET currentquantity = it.currentquantity - v_rec.qty,
                updatedat = (now() at time zone 'utc')
            WHERE it.poultryrawmaterialitemid = v_rec.itemid AND it.farmid = p_farmid;

            SELECT it.itemname INTO v_linename FROM poultryrawmaterialitems it
            WHERE it.poultryrawmaterialitemid = v_rec.itemid AND it.farmid = p_farmid;
            v_linetotal := (COALESCE(v_lineunitcost, 0) * v_rec.qty)::numeric(14,2);

            INSERT INTO productionrecordmedications (farmid, productionrecordid, poultryrawmaterialitemid, itemname, quantityconsumed, unitcost, totalcost)
            VALUES (p_farmid, p_productionid, v_rec.itemid, v_linename, v_rec.qty, COALESCE(v_lineunitcost, 0), v_linetotal);

            v_medtotalcost := v_medtotalcost + v_linetotal;
            v_medtotalqty  := v_medtotalqty + v_rec.qty;
            v_appliedanymed := TRUE;
        END IF;
    END LOOP;

    IF v_appliedanymed THEN
        computedmedicationunitcost := CASE WHEN v_medtotalqty > 0 THEN v_medtotalcost / v_medtotalqty ELSE NULL END;
        computedtotalmedicationcost := v_medtotalcost;
    END IF;

    -- 266. And finally the P&L. One expense per kind, for the deferred share
    -- only -- both are zero, and nothing is written at all, on a farm that
    -- expenses at purchase.
    --
    -- After the loops on purpose: the totals are only known once every line has
    -- drawn, and writing per line would scatter a single event across the
    -- expense list.
    PERFORM sppoultryconsumption_recognise(
        p_farmid, 'PoultryFeedConsumption', p_productionid, 'Feed Cost',
        v_feeddeferred, v_recdate,
        'Feed consumed (production record #' || p_productionid::text || ')', p_createdby);

    PERFORM sppoultryconsumption_recognise(
        p_farmid, 'PoultryMedicationConsumption', p_productionid, 'Medication',
        v_meddeferred, v_recdate,
        'Medication consumed (production record #' || p_productionid::text || ')', p_createdby);
END;
$function$;

-- -----------------------------------------------------------------------------
-- Post-conditions.
--
-- The FIRST is the one that matters: total expenses per farm must be identical
-- to the old keyword sum, because nothing existing has been excluded from
-- profit. If this ever prints a difference, a farm's history has moved.
-- -----------------------------------------------------------------------------
SELECT 'total expenses unchanged for every farm' AS check,
       COUNT(*) FILTER (WHERE ABS(f.oldtotal - f.newtotal) > 0.005) AS should_be_zero,
       COUNT(*) AS farms
FROM  (SELECT fa.farmid,
              (SELECT COALESCE(SUM(e.amount), 0) FROM expense e
                WHERE lower(e.farmid::text) = lower(fa.farmid)) AS oldtotal,
              (SELECT p.totalexpenses
                 FROM sppoultryreport_profitloss(fa.farmid, '2000-01-01'::date, '2099-12-31'::date) p)
              AS newtotal
       FROM   farms fa WHERE fa.type = 'Poultry') f;

SELECT 'feed cost is no longer hidden in Other' AS check,
       ROUND(SUM(p.feedcost), 2) AS feed_now,
       ROUND(SUM(p.otherexpenses), 2) AS other_now
FROM   farms fa
CROSS  JOIN LATERAL sppoultryreport_profitloss(fa.farmid, '2000-01-01'::date, '2099-12-31'::date) p
WHERE  fa.type = 'Poultry';

SELECT 'the statement and the cards agree' AS check, COUNT(*) AS should_be_zero
FROM   farms fa
CROSS  JOIN LATERAL sppoultryreport_plsummary(fa.farmid, '2000-01-01'::date, '2099-12-31'::date) s
WHERE  fa.type = 'Poultry'
  AND  ABS(s.grossprofit - (s.totalrevenue - s.totaldirectcosts)) > 0.005;

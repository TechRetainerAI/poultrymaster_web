-- =============================================================================
-- 316_WaterProfitLossAnalysis.postgres.sql
--
-- Purpose
-- -------
-- Give the water Profit & Loss the analytical layer the poultry one has: a
-- sectioned statement, entry counts, and a drilldown behind every figure.
--
-- THE ONE DECISION EVERYTHING ELSE FOLLOWS
-- ========================================
-- spwaterreport_periodpnl STAYS THE AUTHORITY. Not one reported figure moves.
--
-- The poultry P&L (272) is built on the classification model: accrual, driven by
-- fnpoultryexpense_costtype / _plline / _plsection and the cost-recognition
-- settings. The water P&L is not. It is an older, deliberately different mix:
--
--     income          storefront SALES plus driver-return COLLECTIONS
--     raw materials   waterrawmaterialpurchases.amountpaid -- cash, not accrual
--     production      waterproductionbatches.totalproductioncost
--     expenses        approved waterexpenses, plus delivery expenses
--     losses          production losses plus driver cash shortages
--
-- Rebuilding water on the poultry model would have RESTATED water's net profit
-- -- on the dev database, a 123,063.58 figure computed from five sources that
-- the classification model does not read the same way. Changing what a company
-- reports as profit is a business decision, not a reporting one, and it is not
-- this file's to make.
--
-- So every line below is derived from THE SAME ROWS, WITH THE SAME FILTERS AND
-- THE SAME DATE BOUNDS, that spwaterreport_periodpnl already sums. The statement
-- is that function's arithmetic, itemised. The check file asserts it: each
-- section must total exactly the component it sits under, or the build fails.
--
-- WHERE THE DATE BOUNDS COME FROM, AND WHY THEY LOOK INCONSISTENT
-- ==============================================================
-- They are copied, not chosen. periodpnl uses a half-open timestamp window for
-- sales, returns, purchases, expenses and losses -- but compares production
-- batches on DATE, inclusive at both ends. Two different shapes in one function.
-- Tidying that here would silently change a total, so it is reproduced exactly
-- and flagged instead.
--
-- Two other things are reproduced deliberately because periodpnl does them:
--   * waterproductionlosses is read with NO isdeleted and NO status filter.
--   * waterrawmaterialpurchases is read with no status filter either.
-- Both look like oversights. Neither is this file's to fix -- a reconciliation
-- layer that quietly disagreed with the thing it reconciles to would be worse
-- than the oversight.
--
-- WHAT IS GENUINELY NEW, AND SAFE
-- ===============================
-- Financing and CapitalInvestment are INFORMATIONAL sections: owner money, loans
-- and capital purchases. They are never inside a profit total -- periodpnl has
-- never counted them and still does not -- so adding them cannot move a figure.
-- They are here because "the cash moved and the profit did not" is the question
-- an owner asks immediately after reading a P&L.
--
-- ONE FLAW THIS MAKES VISIBLE
-- ===========================
-- periodpnl counts EVERY approved water expense except RawMaterialPurchase --
-- including one classified CapitalAsset by 282. A borehole bought through the
-- asset register therefore lands in water's operating expenses, where the
-- poultry P&L would exclude it. The statement reproduces that (it must), and
-- spwaterreport_plsummary returns `capitalinexpenses` so a screen can say so
-- out loud. Fixing it is a separate, deliberate migration.
--
-- EFFECT ON TODAY'S NUMBERS: none. New read-only functions; nothing is written.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The statement, one line at a time.
--
-- Sections: Revenue / DirectCost / OperatingExpense / OtherCost / Loss are the
-- profit bands, and together they ARE periodpnl. Financing and CapitalInvestment
-- are informational and never enter a total.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterreport_pllines(
    p_farmid text, p_startdate date, p_enddate date
) RETURNS TABLE(section text, linekey text, linelabel text, amount numeric,
                sortorder integer, isinformational boolean, entrycount integer)
LANGUAGE sql STABLE
AS $function$
    -- periodpnl's own window, copied: half-open on the timestamp columns.
    WITH bounds AS (
        SELECT p_startdate::timestamp                              AS s,
               p_enddate::timestamp + make_interval(days => 1)     AS e
    ),
    -- ---- Revenue -----------------------------------------------------------
    rev AS (
        SELECT 'StorefrontSales'::text AS k, 'Storefront sales'::text AS lbl,
               COALESCE(SUM(s.totalamount), 0) AS amt, COUNT(*)::integer AS n, 1 AS ord
        FROM   watersales s, bounds b
        WHERE  s.farmid = p_farmid AND s.status NOT IN ('Cancelled')
          AND  COALESCE(s.sourcetype, '') <> 'DeliveryRun'
          AND  s.saledate >= b.s AND s.saledate < b.e
        UNION ALL
        -- Collections, not sales. periodpnl takes the driver's money rather than
        -- the DeliveryRun sale rows so the two cannot double-count, and the
        -- drilldown shows the returns for the same reason.
        SELECT 'DeliveryCollections', 'Delivery-run collections',
               COALESCE(SUM(dr.cashcollected + dr.momocollected
                          + dr.bankcollected + dr.creditsalesamount), 0),
               COUNT(*)::integer, 2
        FROM   waterdriverreturns dr, bounds b
        WHERE  dr.farmid = p_farmid AND dr.status IN ('Draft', 'Approved')
          AND  dr.returndate >= b.s AND dr.returndate < b.e
    ),
    -- ---- Direct cost -------------------------------------------------------
    direct AS (
        SELECT 'RawMaterials'::text AS k, 'Raw materials (paid)'::text AS lbl,
               COALESCE(SUM(p.amountpaid), 0) AS amt, COUNT(*)::integer AS n, 11 AS ord
        FROM   waterrawmaterialpurchases p, bounds b
        WHERE  p.farmid = p_farmid
          AND  p.purchasedate >= b.s AND p.purchasedate < b.e
        UNION ALL
        -- DATE comparison, inclusive both ends. periodpnl's own shape; see header.
        SELECT 'ProductionCost', 'Production cost',
               COALESCE(SUM(pb.totalproductioncost), 0), COUNT(*)::integer, 12
        FROM   waterproductionbatches pb
        WHERE  pb.farmid = p_farmid AND pb.isdeleted = FALSE AND pb.status = 'Approved'
          AND  pb.productiondate >= p_startdate AND pb.productiondate <= p_enddate
    ),
    -- ---- Operating / other cost -------------------------------------------
    -- The general expense pool periodpnl counts, itemised by 282's own P&L line
    -- so the P&L, the Expenses page and Financial Activity agree on the wording.
    exp AS (
        SELECT fnwaterexpense_plsection(l.line) AS sec,
               l.line                           AS k,
               fnwaterexpense_pllinelabel(l.line) AS lbl,
               COALESCE(SUM(e.amount), 0)       AS amt,
               COUNT(*)::integer                AS n
        FROM   waterexpenses e
        INNER  JOIN waterexpensecategories ec ON ec.waterexpensecategoryid = e.waterexpensecategoryid,
               bounds b
        -- Same four arguments fnwaterexpenserows passes, including the category
        -- NAME and the item category. Anything less and a legacy row lands on a
        -- different line here than it does on the Expenses page.
        CROSS  JOIN LATERAL (SELECT fnwaterexpense_costtype(
                                        e.financialcosttype::text, e.sourcetype::text,
                                        ec.name::text, e.paymentmethod::text) AS ct) c
        CROSS  JOIN LATERAL (SELECT fnwaterexpense_plline(
                                        c.ct, e.sourcetype::text, ec.name::text,
                                        fnwaterexpense_itemcategory(e.sourcetype::text, e.sourceid)) AS line) l
        WHERE  e.farmid = p_farmid
          AND  COALESCE(e.isdeleted, FALSE) = FALSE AND e.status = 'Approved'
          AND  COALESCE(e.sourcetype, '') <> 'RawMaterialPurchase'
          AND  e.expensedate >= b.s AND e.expensedate < b.e
        GROUP  BY 1, 2, 3
    ),
    deliv AS (
        SELECT 'DeliveryExpenses'::text AS k, 'Delivery expenses'::text AS lbl,
               COALESCE(SUM(de.amount), 0) AS amt, COUNT(*)::integer AS n
        FROM   waterdeliveryexpenses de
        JOIN   waterdriverreturns dr ON dr.waterdriverreturnid = de.waterdriverreturnid, bounds b
        WHERE  dr.farmid = p_farmid AND dr.status IN ('Draft', 'Approved')
          AND  de.isapproved = TRUE
          AND  dr.returndate >= b.s AND dr.returndate < b.e
    ),
    -- ---- Losses ------------------------------------------------------------
    loss AS (
        SELECT 'ProductionLosses'::text AS k, 'Production losses'::text AS lbl,
               COALESCE(SUM(pl.totalvalue), 0) AS amt, COUNT(*)::integer AS n, 61 AS ord
        FROM   waterproductionlosses pl, bounds b
        WHERE  pl.farmid = p_farmid
          AND  pl.lossdate >= b.s AND pl.lossdate < b.e
        UNION ALL
        SELECT 'DriverShortages', 'Driver cash shortages',
               COALESCE(SUM(dr.shortageamount), 0), COUNT(*) FILTER (WHERE dr.shortageamount <> 0)::integer, 62
        FROM   waterdriverreturns dr, bounds b
        WHERE  dr.farmid = p_farmid AND dr.status IN ('Draft', 'Approved')
          AND  dr.returndate >= b.s AND dr.returndate < b.e
    ),
    -- ---- Informational: cash moved, profit did not -------------------------
    fin AS (
        SELECT 'OwnerContributions'::text AS k, 'Owner Contributions'::text AS lbl,
               COALESCE(SUM(o.amount), 0) AS amt, COUNT(*)::integer AS n, 71 AS ord
        FROM   waterownermoney o, bounds b
        WHERE  o.farmid = p_farmid AND o.status = 'Posted'
          AND  o.transactiontype = 'Contribution'
          AND  o.transactiondate >= b.s AND o.transactiondate < b.e
        UNION ALL
        SELECT 'OwnerDraws', 'Owner Draws', COALESCE(SUM(o.amount), 0), COUNT(*)::integer, 72
        FROM   waterownermoney o, bounds b
        WHERE  o.farmid = p_farmid AND o.status = 'Posted'
          AND  o.transactiontype = 'Draw'
          AND  o.transactiondate >= b.s AND o.transactiondate < b.e
        UNION ALL
        SELECT 'LoansReceived', 'Loans Received', COALESCE(SUM(l.amountreceived), 0), COUNT(*)::integer, 73
        FROM   waterloans l, bounds b
        WHERE  l.farmid = p_farmid AND l.status NOT IN ('Reversed', 'Cancelled', 'Draft')
          AND  l.loandate >= b.s AND l.loandate < b.e
        UNION ALL
        SELECT 'LoanPrincipalRepaid', 'Loan Principal Repaid',
               COALESCE(SUM(pm.principalamount), 0), COUNT(*)::integer, 74
        FROM   waterloanpayments pm, bounds b
        WHERE  pm.farmid = p_farmid AND pm.status = 'Posted'
          AND  pm.paymentdate >= b.s AND pm.paymentdate < b.e
    ),
    cap AS (
        SELECT COALESCE(cat.categoryname, 'Other Assets')::text AS k,
               COALESCE(SUM(cc.amount), 0) AS amt, COUNT(*)::integer AS n
        FROM   watercapitalassetcosts cc
        JOIN   watercapitalassets a ON a.watercapitalassetid = cc.watercapitalassetid
        LEFT   JOIN waterassetcategories cat ON cat.waterassetcategoryid = a.waterassetcategoryid
        WHERE  cc.farmid = p_farmid AND cc.status = 'Posted'
          AND  cc.costdate >= p_startdate AND cc.costdate <= p_enddate
        GROUP  BY COALESCE(cat.categoryname, 'Other Assets')
    )
    SELECT 'Revenue', rev.k, rev.lbl, rev.amt::numeric(14,2), rev.ord, FALSE, rev.n
    FROM   rev WHERE rev.amt <> 0 OR rev.n > 0
    UNION ALL
    SELECT 'DirectCost', direct.k, direct.lbl, direct.amt::numeric(14,2), direct.ord, FALSE, direct.n
    FROM   direct WHERE direct.amt <> 0 OR direct.n > 0
    UNION ALL
    -- 282's own section decides which band an expense line sits in, so a
    -- depreciation or loan-interest row drops below Operating Profit rather
    -- than inflating it. Both bands together still equal periodpnl's
    -- totalexpenses, which is what keeps the statement reconciled.
    SELECT exp.sec, exp.k, exp.lbl, exp.amt::numeric(14,2),
           CASE exp.sec WHEN 'OperatingExpense' THEN 30 ELSE 50 END
             + CASE exp.k WHEN 'Payroll' THEN 1 WHEN 'Utilities' THEN 2
                          WHEN 'Transport' THEN 3 WHEN 'RepairsMaintenance' THEN 4
                          WHEN 'Depreciation' THEN 1 WHEN 'LoanInterest' THEN 2
                          WHEN 'LoanFees' THEN 3 ELSE 9 END,
           FALSE, exp.n
    FROM   exp WHERE exp.amt <> 0
    UNION ALL
    SELECT 'OperatingExpense', deliv.k, deliv.lbl, deliv.amt::numeric(14,2), 40, FALSE, deliv.n
    FROM   deliv WHERE deliv.amt <> 0 OR deliv.n > 0
    UNION ALL
    SELECT 'Loss', loss.k, loss.lbl, loss.amt::numeric(14,2), loss.ord, FALSE, loss.n
    FROM   loss WHERE loss.amt <> 0
    UNION ALL
    SELECT 'Financing', fin.k, fin.lbl, fin.amt::numeric(14,2), fin.ord, TRUE, fin.n
    FROM   fin WHERE fin.amt <> 0
    UNION ALL
    SELECT 'CapitalInvestment', cap.k, cap.k, cap.amt::numeric(14,2), 81, TRUE, cap.n
    FROM   cap WHERE cap.amt <> 0
    ORDER  BY 5, 2;
$function$;

COMMENT ON FUNCTION public.spwaterreport_pllines(text, date, date) IS
    'The water P&L statement, one line per figure, itemising exactly what '
    'spwaterreport_periodpnl sums. Revenue/DirectCost/OperatingExpense/OtherCost/'
    'Loss are profit; Financing and CapitalInvestment are informational.';

-- -----------------------------------------------------------------------------
-- 2. The summary.
--
-- periodpnl's own figures, unchanged, with the informational totals and the
-- two data-quality flags a screen needs in order to explain itself.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterreport_plsummary(
    p_farmid text, p_startdate date, p_enddate date
) RETURNS TABLE(
    startdate date, enddate date,
    storefrontsales numeric, deliverycollections numeric, totalrevenue numeric,
    rawmaterials numeric, productioncost numeric, totaldirectcosts numeric,
    grossprofit numeric, grossmarginpercent numeric,
    totaloperatingexpenses numeric, totalothercosts numeric,
    operatingprofit numeric, operatingmarginpercent numeric,
    productionlosses numeric, drivershortages numeric, totallosses numeric,
    netprofit numeric, netmarginpercent numeric,
    ownercontributions numeric, ownerdraws numeric, netownerfunding numeric,
    loansreceived numeric, loanprincipalrepaid numeric, netborrowing numeric,
    totalcapitalinvestments numeric,
    bagsproduced integer, bagssold integer, avgprofitperbag numeric,
    capitalinexpenses numeric, entrycount integer)
LANGUAGE sql STABLE
AS $function$
    WITH lines AS (SELECT * FROM spwaterreport_pllines(p_farmid, p_startdate, p_enddate)),
         base  AS (SELECT * FROM spwaterreport_periodpnl(p_farmid, p_startdate, p_enddate)),
         agg   AS (
        SELECT
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'StorefrontSales'), 0)     AS storefront,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'DeliveryCollections'), 0) AS deliveries,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'RawMaterials'), 0)        AS rawmat,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'ProductionCost'), 0)      AS prodcost,
            COALESCE(SUM(amount) FILTER (WHERE section = 'OperatingExpense'), 0)    AS opex,
            COALESCE(SUM(amount) FILTER (WHERE section = 'OtherCost'), 0)           AS othercost,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'ProductionLosses'), 0)    AS prodloss,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'DriverShortages'), 0)     AS shortages,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'OwnerContributions'), 0)  AS owncontrib,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'OwnerDraws'), 0)          AS owndraws,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'LoansReceived'), 0)       AS loansin,
            COALESCE(SUM(amount) FILTER (WHERE linekey = 'LoanPrincipalRepaid'), 0) AS loansout,
            COALESCE(SUM(amount) FILTER (WHERE section = 'CapitalInvestment'), 0)   AS capital,
            -- The flaw named in the header: capital purchases sitting inside the
            -- expense pool. Zero on a company that has never bought one.
            COALESCE(SUM(amount) FILTER (WHERE linekey IN ('CapitalAsset', 'CapitalAssetCost')), 0)
                                                                                    AS capinexp,
            COALESCE(SUM(entrycount) FILTER (WHERE NOT isinformational), 0)::integer AS n
        FROM lines)
    SELECT p_startdate, p_enddate,
           a.storefront::numeric(14,2), a.deliveries::numeric(14,2), b.totalincome,
           a.rawmat::numeric(14,2), a.prodcost::numeric(14,2),
           (b.rawmaterialcost + b.productioncost)::numeric(14,2),
           (b.totalincome - b.rawmaterialcost - b.productioncost)::numeric(14,2),
           CASE WHEN b.totalincome > 0
                THEN ROUND((b.totalincome - b.rawmaterialcost - b.productioncost)
                           / b.totalincome * 100, 2) ELSE 0 END,
           a.opex::numeric(14,2), a.othercost::numeric(14,2),
           (b.totalincome - b.rawmaterialcost - b.productioncost - b.totalexpenses)::numeric(14,2),
           CASE WHEN b.totalincome > 0
                THEN ROUND((b.totalincome - b.rawmaterialcost - b.productioncost - b.totalexpenses)
                           / b.totalincome * 100, 2) ELSE 0 END,
           a.prodloss::numeric(14,2), a.shortages::numeric(14,2), b.totallosses,
           -- periodpnl's own net profit, untouched. This is the number the
           -- company has been reading, and this file does not get to change it.
           b.netprofit, b.profitmarginpct,
           a.owncontrib::numeric(14,2), a.owndraws::numeric(14,2),
           (a.owncontrib - a.owndraws)::numeric(14,2),
           a.loansin::numeric(14,2), a.loansout::numeric(14,2),
           (a.loansin - a.loansout)::numeric(14,2),
           a.capital::numeric(14,2),
           b.bagsproduced, b.bagssold, b.avgprofitperbag,
           a.capinexp::numeric(14,2), a.n
    FROM   agg a CROSS JOIN base b;
$function$;

COMMENT ON FUNCTION public.spwaterreport_plsummary(text, date, date) IS
    'The water P&L headline figures. Revenue, direct cost, losses and NET PROFIT '
    'are spwaterreport_periodpnl''s own and are not recomputed here; the section '
    'subtotals and the informational figures come from spwaterreport_pllines.';

-- -----------------------------------------------------------------------------
-- 3. Drilldowns. Each one totals to the line above it, because each one reads
--    the same rows with the same filters that line was summed from.
-- -----------------------------------------------------------------------------

-- Revenue: storefront sales, or the driver returns behind the collections.
CREATE OR REPLACE FUNCTION public.spwaterreport_plrevenuedetail(
    p_farmid text, p_startdate date, p_enddate date, p_linekey text DEFAULT NULL
) RETURNS TABLE(entrydate timestamp without time zone, reference text, party text,
                detail text, amount numeric)
LANGUAGE sql STABLE
AS $function$
    SELECT s.saledate, ('Sale #' || s.watersaleid)::text,
           COALESCE(c.name, 'Walk-in')::text,
           COALESCE(NULLIF(btrim(s.notes), ''), s.status)::text,
           s.totalamount::numeric(14,2)
    FROM   watersales s
    LEFT   JOIN watercustomers c ON c.watercustomerid = s.watercustomerid
    WHERE  s.farmid = p_farmid AND s.status NOT IN ('Cancelled')
      AND  COALESCE(s.sourcetype, '') <> 'DeliveryRun'
      AND  s.saledate >= p_startdate::timestamp
      AND  s.saledate <  p_enddate::timestamp + make_interval(days => 1)
      AND  (p_linekey IS NULL OR p_linekey = 'StorefrontSales')
    UNION ALL
    SELECT dr.returndate, ('Return #' || dr.waterdriverreturnid)::text,
           'Driver return'::text,
           (dr.bagssold::text || ' bag(s) sold')::text,
           (dr.cashcollected + dr.momocollected + dr.bankcollected + dr.creditsalesamount)::numeric(14,2)
    FROM   waterdriverreturns dr
    WHERE  dr.farmid = p_farmid AND dr.status IN ('Draft', 'Approved')
      AND  dr.returndate >= p_startdate::timestamp
      AND  dr.returndate <  p_enddate::timestamp + make_interval(days => 1)
      AND  (p_linekey IS NULL OR p_linekey = 'DeliveryCollections')
    ORDER  BY 1 DESC, 2;
$function$;

-- Direct cost: raw material purchases, or production batches.
CREATE OR REPLACE FUNCTION public.spwaterreport_pldirectcostdetail(
    p_farmid text, p_startdate date, p_enddate date, p_linekey text DEFAULT NULL
) RETURNS TABLE(entrydate timestamp without time zone, reference text, party text,
                detail text, amount numeric)
LANGUAGE sql STABLE
AS $function$
    -- amountpaid, not totalcost: periodpnl counts raw materials on a CASH basis
    -- and a drilldown that showed the invoice value would not add up to its line.
    SELECT p.purchasedate, ('Purchase #' || p.waterrawmaterialpurchaseid)::text,
           COALESCE(NULLIF(btrim(p.suppliername), ''), 'Supplier')::text,
           COALESCE(i.itemname, 'Raw material')::text,
           COALESCE(p.amountpaid, 0)::numeric(14,2)
    FROM   waterrawmaterialpurchases p
    LEFT   JOIN waterrawmaterialitems i ON i.waterrawmaterialitemid = p.waterrawmaterialitemid
    WHERE  p.farmid = p_farmid
      AND  p.purchasedate >= p_startdate::timestamp
      AND  p.purchasedate <  p_enddate::timestamp + make_interval(days => 1)
      AND  (p_linekey IS NULL OR p_linekey = 'RawMaterials')
    UNION ALL
    SELECT pb.productiondate::timestamp, COALESCE(NULLIF(btrim(pb.batchnumber), ''),
           'Batch #' || pb.waterproductionbatchid)::text,
           'Production'::text,
           (pb.bagsproduced::text || ' bag(s)')::text,
           COALESCE(pb.totalproductioncost, 0)::numeric(14,2)
    FROM   waterproductionbatches pb
    WHERE  pb.farmid = p_farmid AND pb.isdeleted = FALSE AND pb.status = 'Approved'
      AND  pb.productiondate >= p_startdate AND pb.productiondate <= p_enddate
      AND  (p_linekey IS NULL OR p_linekey = 'ProductionCost')
    ORDER  BY 1 DESC, 2;
$function$;

-- Operating / other cost: the general expense pool, plus delivery expenses.
CREATE OR REPLACE FUNCTION public.spwaterreport_plexpensedetail(
    p_farmid text, p_startdate date, p_enddate date, p_linekey text DEFAULT NULL
) RETURNS TABLE(entrydate timestamp without time zone, reference text, party text,
                detail text, amount numeric)
LANGUAGE sql STABLE
AS $function$
    SELECT e.expensedate, ('Expense #' || e.waterexpenseid)::text,
           COALESCE(NULLIF(btrim(e.paidto), ''), 'Not recorded')::text,
           COALESCE(NULLIF(btrim(e.description), ''), 'Expense')::text,
           e.amount::numeric(14,2)
    FROM   waterexpenses e
    INNER  JOIN waterexpensecategories ec ON ec.waterexpensecategoryid = e.waterexpensecategoryid
    CROSS  JOIN LATERAL (SELECT fnwaterexpense_costtype(
                                    e.financialcosttype::text, e.sourcetype::text,
                                    ec.name::text, e.paymentmethod::text) AS ct) c
    CROSS  JOIN LATERAL (SELECT fnwaterexpense_plline(
                                    c.ct, e.sourcetype::text, ec.name::text,
                                    fnwaterexpense_itemcategory(e.sourcetype::text, e.sourceid)) AS line) l
    WHERE  e.farmid = p_farmid
      AND  COALESCE(e.isdeleted, FALSE) = FALSE AND e.status = 'Approved'
      AND  COALESCE(e.sourcetype, '') <> 'RawMaterialPurchase'
      AND  e.expensedate >= p_startdate::timestamp
      AND  e.expensedate <  p_enddate::timestamp + make_interval(days => 1)
      AND  (p_linekey IS NULL OR l.line = p_linekey)
    UNION ALL
    SELECT dr.returndate, ('Delivery expense #' || de.waterdeliveryexpenseid)::text,
           COALESCE(NULLIF(btrim(de.expensecategory), ''), 'Delivery')::text,
           COALESCE(NULLIF(btrim(de.description), ''), 'Delivery expense')::text,
           de.amount::numeric(14,2)
    FROM   waterdeliveryexpenses de
    JOIN   waterdriverreturns dr ON dr.waterdriverreturnid = de.waterdriverreturnid
    WHERE  dr.farmid = p_farmid AND dr.status IN ('Draft', 'Approved')
      AND  de.isapproved = TRUE
      AND  dr.returndate >= p_startdate::timestamp
      AND  dr.returndate <  p_enddate::timestamp + make_interval(days => 1)
      AND  (p_linekey IS NULL OR p_linekey = 'DeliveryExpenses')
    ORDER  BY 1 DESC, 2;
$function$;

-- Losses: damaged or rejected stock, and driver cash shortages.
CREATE OR REPLACE FUNCTION public.spwaterreport_pllossdetail(
    p_farmid text, p_startdate date, p_enddate date, p_linekey text DEFAULT NULL
) RETURNS TABLE(entrydate timestamp without time zone, reference text, party text,
                detail text, amount numeric)
LANGUAGE sql STABLE
AS $function$
    -- No isdeleted or status filter: periodpnl has none, and this must agree
    -- with it rather than with what the filter probably ought to be.
    SELECT pl.lossdate, ('Loss #' || pl.waterproductionlossid)::text,
           COALESCE(NULLIF(btrim(pl.losstype), ''), 'Loss')::text,
           COALESCE(NULLIF(btrim(pl.reason), ''), 'Not recorded')::text,
           COALESCE(pl.totalvalue, 0)::numeric(14,2)
    FROM   waterproductionlosses pl
    WHERE  pl.farmid = p_farmid
      AND  pl.lossdate >= p_startdate::timestamp
      AND  pl.lossdate <  p_enddate::timestamp + make_interval(days => 1)
      AND  (p_linekey IS NULL OR p_linekey = 'ProductionLosses')
    UNION ALL
    SELECT dr.returndate, ('Return #' || dr.waterdriverreturnid)::text,
           'Driver shortage'::text,
           (dr.bagssold::text || ' bag(s) sold, short by')::text,
           dr.shortageamount::numeric(14,2)
    FROM   waterdriverreturns dr
    WHERE  dr.farmid = p_farmid AND dr.status IN ('Draft', 'Approved')
      AND  dr.shortageamount <> 0
      AND  dr.returndate >= p_startdate::timestamp
      AND  dr.returndate <  p_enddate::timestamp + make_interval(days => 1)
      AND  (p_linekey IS NULL OR p_linekey = 'DriverShortages')
    ORDER  BY 1 DESC, 2;
$function$;

-- Financing: owner money and borrowing. Never in profit.
CREATE OR REPLACE FUNCTION public.spwaterreport_plfinancingdetail(
    p_farmid text, p_startdate date, p_enddate date, p_linekey text DEFAULT NULL
) RETURNS TABLE(entrydate timestamp without time zone, reference text, party text,
                detail text, amount numeric)
LANGUAGE sql STABLE
AS $function$
    SELECT o.transactiondate, COALESCE(NULLIF(btrim(o.transactionnumber), ''),
           'Owner #' || o.waterownermoneyid)::text,
           COALESCE(NULLIF(btrim(o.ownername), ''), 'Owner')::text,
           o.transactiontype::text, o.amount::numeric(14,2)
    FROM   waterownermoney o
    WHERE  o.farmid = p_farmid AND o.status = 'Posted'
      AND  o.transactiondate >= p_startdate::timestamp
      AND  o.transactiondate <  p_enddate::timestamp + make_interval(days => 1)
      AND  (p_linekey IS NULL
            OR (p_linekey = 'OwnerContributions' AND o.transactiontype = 'Contribution')
            OR (p_linekey = 'OwnerDraws'         AND o.transactiontype = 'Draw'))
    UNION ALL
    SELECT l.loandate, COALESCE(NULLIF(btrim(l.loannumber), ''), 'Loan #' || l.waterloanid)::text,
           COALESCE(NULLIF(btrim(l.lendername), ''), 'Lender')::text,
           'Loan received'::text, l.amountreceived::numeric(14,2)
    FROM   waterloans l
    WHERE  l.farmid = p_farmid AND l.status NOT IN ('Reversed', 'Cancelled', 'Draft')
      AND  l.loandate >= p_startdate::timestamp
      AND  l.loandate <  p_enddate::timestamp + make_interval(days => 1)
      AND  (p_linekey IS NULL OR p_linekey = 'LoansReceived')
    UNION ALL
    SELECT pm.paymentdate, COALESCE(NULLIF(btrim(pm.paymentnumber), ''),
           'Payment #' || pm.waterloanpaymentid)::text,
           COALESCE(NULLIF(btrim(l.lendername), ''), 'Lender')::text,
           'Principal repaid'::text, pm.principalamount::numeric(14,2)
    FROM   waterloanpayments pm
    LEFT   JOIN waterloans l ON l.waterloanid = pm.waterloanid
    WHERE  pm.farmid = p_farmid AND pm.status = 'Posted'
      AND  pm.paymentdate >= p_startdate::timestamp
      AND  pm.paymentdate <  p_enddate::timestamp + make_interval(days => 1)
      AND  (p_linekey IS NULL OR p_linekey = 'LoanPrincipalRepaid')
    ORDER  BY 1 DESC, 2;
$function$;

-- Capital: what was capitalised into the asset register. Never in profit.
CREATE OR REPLACE FUNCTION public.spwaterreport_plcapitaldetail(
    p_farmid text, p_startdate date, p_enddate date, p_linekey text DEFAULT NULL
) RETURNS TABLE(entrydate timestamp without time zone, reference text, party text,
                detail text, amount numeric)
LANGUAGE sql STABLE
AS $function$
    SELECT cc.costdate::timestamp,
           COALESCE(NULLIF(btrim(a.assetnumber), ''), 'Asset #' || a.watercapitalassetid)::text,
           COALESCE(NULLIF(btrim(s.suppliername), ''), 'Not recorded')::text,
           (a.assetname || COALESCE(' — ' || NULLIF(btrim(cc.description), ''), ''))::text,
           cc.amount::numeric(14,2)
    FROM   watercapitalassetcosts cc
    JOIN   watercapitalassets a ON a.watercapitalassetid = cc.watercapitalassetid
    LEFT   JOIN waterassetcategories cat ON cat.waterassetcategoryid = a.waterassetcategoryid
    LEFT   JOIN watersuppliers s ON s.watersupplierid = cc.supplierid
    WHERE  cc.farmid = p_farmid AND cc.status = 'Posted'
      AND  cc.costdate >= p_startdate AND cc.costdate <= p_enddate
      AND  (p_linekey IS NULL OR COALESCE(cat.categoryname, 'Other Assets') = p_linekey)
    ORDER  BY 1 DESC, 2;
$function$;

-- Depreciation posted against the water asset register, for the OtherCost line.
CREATE OR REPLACE FUNCTION public.spwaterreport_pldepreciationdetail(
    p_farmid text, p_startdate date, p_enddate date
) RETURNS TABLE(entrydate timestamp without time zone, reference text, party text,
                detail text, amount numeric)
LANGUAGE sql STABLE
AS $function$
    SELECT d.depreciationdate::timestamp,
           COALESCE(NULLIF(btrim(a.assetnumber), ''), 'Asset #' || a.watercapitalassetid)::text,
           COALESCE(cat.categoryname, 'Uncategorised')::text,
           (a.assetname || ' (' || to_char(d.periodstart, 'Mon YYYY') || ')')::text,
           d.amount::numeric(14,2)
    FROM   waterassetdepreciation d
    JOIN   watercapitalassets a ON a.watercapitalassetid = d.watercapitalassetid
    LEFT   JOIN waterassetcategories cat ON cat.waterassetcategoryid = a.waterassetcategoryid
    WHERE  d.farmid = p_farmid
      AND  d.depreciationdate >= p_startdate AND d.depreciationdate <= p_enddate
    ORDER  BY 1 DESC, 2;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'the eight new routines exist (8 expected)' AS check,
       CASE WHEN COUNT(*) = 8 THEN 'OK' ELSE 'MISSING (' || COUNT(*) || ')' END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spwaterreport_pllines', 'spwaterreport_plsummary',
                     'spwaterreport_plrevenuedetail', 'spwaterreport_pldirectcostdetail',
                     'spwaterreport_plexpensedetail', 'spwaterreport_pllossdetail',
                     'spwaterreport_plfinancingdetail', 'spwaterreport_plcapitaldetail')

UNION ALL
-- periodpnl is untouched. If this ever fails, the authority has been moved.
SELECT 'spwaterreport_periodpnl still exists and is unchanged in shape',
       CASE WHEN COUNT(*) = 1 THEN 'OK' ELSE 'CHANGED' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'spwaterreport_periodpnl'
  AND  pg_get_function_result(p.oid) LIKE '%netprofit numeric%';

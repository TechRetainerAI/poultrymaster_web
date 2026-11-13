-- =============================================================================
-- 429_WaterPLRawMaterialsCashOnPaymentDate.postgres.sql   (requires 423-428)
--
-- Purpose
-- -------
-- Water's P&L counted raw materials twice (user decision 2026-11-12: "cash, on
-- the payment date"):
--
--  * periodpnl's raw materials were SUM(purchase.amountpaid) dated by the
--    PURCHASE date -- and a supplier payment that later paid a credit purchase
--    ALSO wrote a 'WaterSupplierPayment' expense row, counted again in operating
--    expenses on the PAYMENT date.
--  * a deferred lot (EXPENSE_WHEN_CONSUMED) was counted when paid AND when used
--    (its consumption expense rows).
--
-- The rule now, one function for every reader (fnwaterpl_rawmaterialrows):
--   paid at entry        what was paid when the purchase was entered
--                        (amountpaid less every allocation onto it), on the
--                        purchase date
--   paid later           a supplier payment's share for the purchase, on the
--                        payment date
--   credit applied       an advance / overpayment applied to the purchase, on
--                        the day applied (the cash left with the advance); a
--                        credit note / opening / manual credit never (no money)
--   only lots expensed at purchase -- a deferred lot reaches P&L when used
--   (its consumption expense rows, unchanged); a manual cost lot (428) never
--   here.
-- The 'WaterSupplierPayment' expense rows are no longer counted in operating
-- expenses (they duplicated "paid later").
--
-- Readers: spwaterreport_periodpnl, _pllines, _pldirectcostdetail,
-- _plexpensedetail, and the Daily Closing's raw spend / expenses (cash of the
-- day: purchases paid on entry + supplier payments made that day).
--
-- On dev no reported figure changes: there are no water supplier payments and
-- no deferred lots. Companies with either will see the duplicate removed.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.fnwaterpl_rawmaterialrows(p_farmid text, p_start timestamp, p_end timestamp)
RETURNS TABLE(entrydate timestamp, reference text, party text, detail text, amount numeric, kind text)
LANGUAGE sql STABLE AS $f$
    -- paid when the purchase was entered
    SELECT p.purchasedate, ('Purchase #' || p.waterrawmaterialpurchaseid)::text,
           COALESCE(NULLIF(btrim(p.suppliername), ''), 'Supplier')::text,
           COALESCE(i.itemname, 'Raw material')::text,
           GREATEST(COALESCE(p.amountpaid, 0)
                    - COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                                WHERE sa.farmid = p.farmid AND sa.module = 'water' AND sa.status = 'Posted'
                                  AND sa.documenttype = 'RawMaterialPurchase'
                                  AND sa.documentid = p.waterrawmaterialpurchaseid), 0), 0)::numeric(14,2),
           'PaidAtEntry'::text
    FROM   waterrawmaterialpurchases p
    LEFT   JOIN waterrawmaterialitems i ON i.waterrawmaterialitemid = p.waterrawmaterialitemid
    WHERE  p.farmid = p_farmid
      AND  COALESCE(p.lotsource, '') <> 'ManualDeferredCost'
      AND  fnwatercostrecognition_expenseatpurchase(COALESCE(p.costrecognitionmethod, 'EXPENSE_WHEN_PURCHASED'))
      AND  p.purchasedate >= p_start AND p.purchasedate < p_end
    UNION ALL
    -- paid later (supplier payment), or credit applied later
    SELECT CASE WHEN sa.fromcredit THEN sa.createdat ELSE sp.paymentdate END,
           ('Purchase #' || p.waterrawmaterialpurchaseid)::text,
           COALESCE(NULLIF(btrim(s.suppliername), ''), NULLIF(btrim(p.suppliername), ''), 'Supplier')::text,
           (COALESCE(i.itemname, 'Raw material') ||
            CASE WHEN sa.fromcredit THEN ' - supplier credit applied' ELSE ' - supplier payment SP-' ||
                 lpad(sp.watersupplierpaymentid::text, 5, '0') END)::text,
           sa.amountapplied::numeric(14,2),
           CASE WHEN sa.fromcredit THEN 'CreditApplied' ELSE 'PaidLater' END::text
    FROM   supplierpaymentallocation sa
    JOIN   watersupplierpayments sp ON sp.watersupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
    JOIN   waterrawmaterialpurchases p ON p.waterrawmaterialpurchaseid = sa.documentid AND p.farmid = sa.farmid
    LEFT   JOIN waterrawmaterialitems i ON i.waterrawmaterialitemid = p.waterrawmaterialitemid
    LEFT   JOIN watersuppliers s ON s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sa.farmid = p_farmid AND sa.module = 'water' AND sa.status = 'Posted'
      AND  sa.documenttype = 'RawMaterialPurchase'
      AND  COALESCE(sp.status, 'Posted') = 'Posted'
      AND  NOT public.fnwatersupplier_iscreditkind(sp.sourcetype)       -- a credit note moved no money
      AND  COALESCE(p.lotsource, '') <> 'ManualDeferredCost'
      AND  fnwatercostrecognition_expenseatpurchase(COALESCE(p.costrecognitionmethod, 'EXPENSE_WHEN_PURCHASED'))
      AND  CASE WHEN sa.fromcredit THEN sa.createdat ELSE sp.paymentdate END >= p_start
      AND  CASE WHEN sa.fromcredit THEN sa.createdat ELSE sp.paymentdate END <  p_end;
$f$;

CREATE OR REPLACE FUNCTION public.fnwaterpl_rawmaterials(p_farmid text, p_start timestamp, p_end timestamp)
RETURNS TABLE(total numeric, n integer) LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(SUM(r.amount), 0)::numeric(14,2), COUNT(*) FILTER (WHERE r.amount <> 0)::integer
    FROM   public.fnwaterpl_rawmaterialrows(p_farmid, p_start, p_end) r;
$f$;

CREATE OR REPLACE FUNCTION public.spwaterreport_periodpnl(p_farmid text, p_fromdate date, p_todate date)
 RETURNS TABLE(periodstart date, periodend date, totalincome numeric, totalexpenses numeric, rawmaterialcost numeric, productioncost numeric, totallosses numeric, netprofit numeric, profitmarginpct numeric, bagsproduced integer, bagssold integer, avgprofitperbag numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_start             timestamp;
    v_end               timestamp;
    v_storefrontincome  numeric;
    v_driverincome      numeric;
    v_totalincome       numeric;
    v_rawmaterialcost   numeric;
    v_productioncost    numeric;
    v_generalexpenses   numeric;
    v_deliveryexpenses  numeric;
    v_operatingexpenses numeric;
    v_productionlosses  numeric;
    v_shortagelosses    numeric;
    v_totallosses       numeric;
    v_netprofit         numeric;
    v_bagsproduced      integer;
    v_storefrontbagssold numeric;
    v_driverbagssold    numeric;
    v_bagssold          integer;
    v_profitmargin      numeric;
    v_avgprofitperbag   numeric;
BEGIN
    v_start := p_fromdate::timestamp;
    v_end   := p_todate::timestamp + make_interval(days => 1);

    -- Storefront sales only (exclude DeliveryRun - that income is on the return).
    v_storefrontincome := COALESCE((
        SELECT SUM(s.totalamount) FROM watersales s
        WHERE s.farmid = p_farmid AND s.status NOT IN ('Cancelled')
          AND COALESCE(s.sourcetype, '') <> 'DeliveryRun'
          AND s.saledate >= v_start AND s.saledate < v_end), 0);

    -- Driver-return income for the day (cash + momo + bank + credit sold).
    v_driverincome := COALESCE((
        SELECT SUM(dr.cashcollected + dr.momocollected + dr.bankcollected + dr.creditsalesamount)
        FROM waterdriverreturns dr
        WHERE dr.farmid = p_farmid AND dr.status IN ('Draft','Approved')
          AND dr.returndate >= v_start AND dr.returndate < v_end), 0);

    -- 424: a credit note is an allowance given -- revenue the business gave up.
    v_totalincome := (v_storefrontincome + v_driverincome
                      - COALESCE((SELECT SUM(cn.amount) FROM waterpayments cn
                                  WHERE cn.farmid = p_farmid AND cn.sourcetype = 'CreditNote'
                                    AND COALESCE(cn.status, 'Posted') = 'Posted'
                                    AND cn.paymentdate >= v_start AND cn.paymentdate < v_end), 0)
                      -- 425 (382): money paid on debts recorded by hand is revenue
                      + (SELECT dc.total FROM public.fnwaterpl_debtcollections(p_farmid, v_start, v_end) dc))::numeric(14,2);

    -- Cash paid for raw materials (matches the closing's AmountPaid basis).
    -- 429: cash, on the payment date (fnwaterpl_rawmaterialrows)
    v_rawmaterialcost := (SELECT x.total FROM public.fnwaterpl_rawmaterials(p_farmid, v_start, v_end) x);

    v_productioncost := COALESCE((
        SELECT SUM(b.totalproductioncost) FROM waterproductionbatches b
        WHERE b.farmid = p_farmid AND b.isdeleted = FALSE AND b.status = 'Approved'
          AND b.productiondate >= p_fromdate AND b.productiondate <= p_todate), 0);

    -- Operating expenses: general approved WaterExpenses (excl. the auto
    -- raw-material-purchase expense, already in RawMaterialCost) + delivery expenses.
    v_generalexpenses := COALESCE((
        SELECT SUM(e.amount) FROM waterexpenses e
        WHERE e.farmid = p_farmid AND e.isdeleted = FALSE AND e.status = 'Approved'
          AND COALESCE(e.sourcetype, '') <> 'RawMaterialPurchase'
          -- 429: a supplier payment's expense row duplicated raw materials (paid later)
          AND COALESCE(e.sourcetype, '') <> 'WaterSupplierPayment'
          AND e.expensedate >= v_start AND e.expensedate < v_end), 0);

    v_deliveryexpenses := COALESCE((
        SELECT SUM(de.amount) FROM waterdeliveryexpenses de
        INNER JOIN waterdriverreturns dr ON dr.waterdriverreturnid = de.waterdriverreturnid
        WHERE dr.farmid = p_farmid AND dr.status IN ('Draft','Approved') AND de.isapproved = TRUE
          AND dr.returndate >= v_start AND dr.returndate < v_end), 0);

    -- 427 (382): money paid on supplier debts recorded by hand is an operating expense
    v_operatingexpenses := (v_generalexpenses + v_deliveryexpenses
                            + (SELECT x.total FROM public.fnwaterpl_supplierdebtpayments(p_farmid, v_start, v_end) x))::numeric(14,2);

    -- Losses: production losses (damaged/rejected) + driver cash shortages.
    v_productionlosses := COALESCE((
        SELECT SUM(l.totalvalue) FROM waterproductionlosses l
        WHERE l.farmid = p_farmid AND l.lossdate >= v_start AND l.lossdate < v_end), 0);

    v_shortagelosses := COALESCE((
        SELECT SUM(dr.shortageamount) FROM waterdriverreturns dr
        WHERE dr.farmid = p_farmid AND dr.status IN ('Draft','Approved')
          AND dr.returndate >= v_start AND dr.returndate < v_end), 0);

    v_totallosses := (v_productionlosses + v_shortagelosses)::numeric(14,2);

    v_netprofit := (v_totalincome - v_rawmaterialcost - v_productioncost
                    - v_operatingexpenses - v_totallosses)::numeric(14,2);

    v_bagsproduced := COALESCE((
        SELECT SUM(b.bagsproduced - b.damagedbags)::int FROM waterproductionbatches b
        WHERE b.farmid = p_farmid AND b.isdeleted = FALSE AND b.status = 'Approved'
          AND b.productiondate >= p_fromdate AND b.productiondate <= p_todate), 0);

    -- Bags sold = storefront sale items (excl. DeliveryRun) + driver-return bags sold.
    v_storefrontbagssold := COALESCE((
        SELECT SUM(si.quantity) FROM watersales s
        INNER JOIN watersaleitems si ON si.watersaleid = s.watersaleid
        WHERE s.farmid = p_farmid AND s.status NOT IN ('Cancelled')
          AND COALESCE(s.sourcetype, '') <> 'DeliveryRun'
          AND s.saledate >= v_start AND s.saledate < v_end), 0);

    v_driverbagssold := COALESCE((
        SELECT SUM(dr.bagssold) FROM waterdriverreturns dr
        WHERE dr.farmid = p_farmid AND dr.status IN ('Draft','Approved')
          AND dr.returndate >= v_start AND dr.returndate < v_end), 0);

    -- T-SQL CAST(decimal AS INT) truncates toward zero; trunc() keeps that.
    v_bagssold := trunc(v_storefrontbagssold + v_driverbagssold)::int;

    v_profitmargin := (CASE WHEN v_totalincome > 0 THEN (v_netprofit / v_totalincome) * 100 ELSE 0 END)::numeric(8,2);
    v_avgprofitperbag := (CASE WHEN v_bagssold > 0 THEN v_netprofit / v_bagssold ELSE 0 END)::numeric(14,2);

    RETURN QUERY
    SELECT p_fromdate, p_todate,
           v_totalincome,
           v_operatingexpenses,   -- operating only
           v_rawmaterialcost,
           v_productioncost,
           v_totallosses,
           v_netprofit,
           v_profitmargin,
           v_bagsproduced,
           v_bagssold,
           v_avgprofitperbag;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spwaterreport_pllines(p_farmid text, p_startdate date, p_enddate date)
 RETURNS TABLE(section text, linekey text, linelabel text, amount numeric, sortorder integer, isinformational boolean, entrycount integer)
 LANGUAGE sql
 STABLE
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
        UNION ALL
        -- 425 (382): money paid on customer debts recorded by hand
        SELECT 'DebtCollections', 'Customer debt collections', dc.total, dc.n, 4
        FROM   bounds b CROSS JOIN LATERAL public.fnwaterpl_debtcollections(p_farmid, b.s, b.e) dc
        UNION ALL
        -- 424: credit notes -- allowances given, negative revenue
        SELECT 'CreditNotes', 'Credit notes & allowances',
               -COALESCE(SUM(cn.amount), 0), COUNT(*)::integer, 3
        FROM   waterpayments cn, bounds b
        WHERE  cn.farmid = p_farmid AND cn.sourcetype = 'CreditNote'
          AND  COALESCE(cn.status, 'Posted') = 'Posted'
          AND  cn.paymentdate >= b.s AND cn.paymentdate < b.e
    ),
    -- ---- Direct cost -------------------------------------------------------
    direct AS (
        -- 429: cash, on the payment date
        SELECT 'RawMaterials'::text AS k, 'Raw materials (paid)'::text AS lbl,
               x.total AS amt, x.n AS n, 11 AS ord
        FROM   bounds b CROSS JOIN LATERAL public.fnwaterpl_rawmaterials(p_farmid, b.s, b.e) x
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
          AND  COALESCE(e.sourcetype, '') <> 'WaterSupplierPayment'      -- 429
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
    -- 427 (382): money paid on supplier debts recorded by hand
    SELECT 'OperatingExpense', 'SupplierDebtPayments', 'Supplier debt payments', x.total, 41, FALSE, x.n
    FROM   bounds b CROSS JOIN LATERAL public.fnwaterpl_supplierdebtpayments(p_farmid, b.s, b.e) x
    WHERE  x.total <> 0
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

CREATE OR REPLACE FUNCTION public.spwaterreport_pldirectcostdetail(p_farmid text, p_startdate date, p_enddate date, p_linekey text DEFAULT NULL::text)
 RETURNS TABLE(entrydate timestamp without time zone, reference text, party text, detail text, amount numeric)
 LANGUAGE sql
 STABLE
AS $function$
    -- amountpaid, not totalcost: periodpnl counts raw materials on a CASH basis
    -- and a drilldown that showed the invoice value would not add up to its line.
    -- 429: the rows behind Raw materials, the same function periodpnl sums
    SELECT r.entrydate, r.reference, r.party, r.detail, r.amount
    FROM   public.fnwaterpl_rawmaterialrows(p_farmid, p_startdate::timestamp,
                                            p_enddate::timestamp + make_interval(days => 1)) r
    WHERE  r.amount <> 0 AND (p_linekey IS NULL OR p_linekey = 'RawMaterials')
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

CREATE OR REPLACE FUNCTION public.spwaterreport_plexpensedetail(p_farmid text, p_startdate date, p_enddate date, p_linekey text DEFAULT NULL::text)
 RETURNS TABLE(entrydate timestamp without time zone, reference text, party text, detail text, amount numeric)
 LANGUAGE sql
 STABLE
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
      AND  COALESCE(e.sourcetype, '') <> 'WaterSupplierPayment'          -- 429
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
    UNION ALL
    -- 427
    SELECT r.entrydate, ('SP-' || lpad(r.watersupplierpaymentid::text, 5, '0'))::text,
           COALESCE(r.suppliername, 'Supplier')::text,
           ('Paid on debt ' || COALESCE(r.debtnumber, '') || CASE WHEN r.fromcredit THEN ' (from an advance)' ELSE '' END)::text,
           r.amount
    FROM   public.fnwaterpl_supplierdebtpaymentrows(p_farmid, p_startdate::timestamp,
                                                    p_enddate::timestamp + make_interval(days => 1)) r
    WHERE  (p_linekey IS NULL OR p_linekey = 'SupplierDebtPayments')
    ORDER  BY 1 DESC, 2;
$function$;

CREATE OR REPLACE FUNCTION public.fnwaterdailyclosing_livetotals(p_farmid text, p_closingdate date)
 RETURNS TABLE(bagsproduced numeric, totalproductioncost numeric, bagssold numeric, totalincome numeric, creditsales numeric, customercollections numeric, bagsreturned numeric, bagsdamaged numeric, drivershortagestotal numeric, momobalance numeric, bankbalance numeric, rawmaterialspendtoday numeric, closingstockbags numeric, totalexpenses numeric, cashathand numeric)
 LANGUAGE sql
AS $function$
    WITH
    prod AS (
        SELECT
            COALESCE(SUM((pb.bagsproduced - COALESCE(pb.damagedbags, 0))::numeric(14,3)), 0) AS bagsproduced,
            COALESCE(SUM(pb.totalproductioncost), 0) AS totalproductioncost
        FROM waterproductionbatches pb
        WHERE pb.farmid = p_farmid AND pb.isdeleted = FALSE AND pb.status = 'Approved'
          AND pb.productiondate = p_closingdate
    ),
    sale_items AS (
        SELECT COALESCE(SUM(si.quantity::numeric(14,3)), 0) AS bagssold
        FROM   watersales s
        INNER  JOIN watersaleitems si ON si.watersaleid = s.watersaleid
        WHERE  s.farmid = p_farmid AND s.status NOT IN ('Cancelled')
           AND COALESCE(s.sourcetype, '') <> 'DeliveryRun'
           AND s.saledate >= p_closingdate::timestamp
           AND s.saledate <  p_closingdate::timestamp + interval '1 day'
    ),
    sale_money AS (
        SELECT
            COALESCE(SUM(s2.totalamount), 0) AS totalincome,
            -- 423: what was still OWED at the end of the day (364's rule), not
            -- what is owed now -- a payment made later must not rewrite a past day.
            COALESCE(SUM(public.fnwatersale_owedasof(p_farmid, s2.watersaleid, p_closingdate)), 0) AS creditsales
        FROM   watersales s2
        WHERE  s2.farmid = p_farmid AND s2.status NOT IN ('Cancelled')
           AND COALESCE(s2.sourcetype, '') <> 'DeliveryRun'
           AND s2.saledate >= p_closingdate::timestamp
           AND s2.saledate <  p_closingdate::timestamp + interval '1 day'
    ),
    payments AS (
        SELECT
            COALESCE(SUM(pay.amount), 0) AS customercollections,
            COALESCE(SUM(CASE WHEN pay.paymentmethod IN ('Mobile Money', 'MoMo', 'Momo') THEN pay.amount ELSE 0 END), 0) AS momopayments,
            COALESCE(SUM(CASE WHEN pay.paymentmethod IN ('Bank', 'Bank Transfer', 'Transfer') THEN pay.amount ELSE 0 END), 0) AS bankpayments
        FROM   waterpayments pay
        LEFT   JOIN watersales ps ON ps.watersaleid = pay.watersaleid AND ps.farmid = pay.farmid
        WHERE  pay.farmid = p_farmid
           AND COALESCE(pay.sourcetype, '') <> 'DeliveryRun'
           -- 423: a reversed payment collected nothing.
           AND COALESCE(pay.status, 'Posted') = 'Posted'
           -- 424: a customer advance went straight into its account; opening
           -- credit and credit notes are not money. None of it is in the drawer.
           AND NOT public.fnwater_ismanualcredit(pay.sourcetype)
           -- 423: a payment on a sale made the SAME day is already in that sale's
           -- paid part (income less credit); counting it here too doubled it.
           AND NOT (ps.watersaleid IS NOT NULL
                    AND COALESCE(ps.sourcetype, '') <> 'DeliveryRun'
                    AND ps.saledate >= p_closingdate::timestamp
                    AND ps.saledate <  p_closingdate::timestamp + interval '1 day')
           AND pay.paymentdate >= p_closingdate::timestamp
           AND pay.paymentdate <  p_closingdate::timestamp + interval '1 day'
    ),
    ranked_returns AS (
        SELECT
            dr.waterdriverreturnid, dr.watervehicleloadingid,
            dr.bagsreturned, dr.bagsdamaged, dr.bagssold,
            dr.cashcollected, dr.momocollected, dr.bankcollected, dr.creditsalesamount, dr.shortageamount,
            ROW_NUMBER() OVER (PARTITION BY dr.watervehicleloadingid ORDER BY dr.waterdriverreturnid DESC) AS rn
        FROM   waterdriverreturns dr
        WHERE  dr.farmid = p_farmid AND dr.status = 'Approved'
           AND dr.returndate >= p_closingdate::timestamp
           AND dr.returndate <  p_closingdate::timestamp + interval '1 day'
    ),
    driver_returns AS (
        SELECT
            COALESCE(SUM(rr.bagsreturned::numeric(14,3)), 0) AS bagsreturned,
            COALESCE(SUM(rr.bagsdamaged::numeric(14,3)), 0)  AS bagsdamaged,
            COALESCE(SUM(rr.bagssold::numeric(14,3)), 0)     AS driverbagssold,
            COALESCE(SUM(rr.cashcollected + rr.momocollected + rr.bankcollected + rr.creditsalesamount), 0) AS drivertotalincome,
            COALESCE(SUM(rr.creditsalesamount), 0) AS drivercreditsales,
            COALESCE(SUM(rr.momocollected), 0) AS drivermomo,
            COALESCE(SUM(rr.bankcollected), 0) AS driverbank,
            COALESCE(SUM(rr.shortageamount), 0) AS drivershortages
        FROM   ranked_returns rr
        WHERE  rr.rn = 1
    ),
    raw_spend AS (
        -- 429: the day's cash on raw materials -- what purchases entered today
        -- were paid on entry, plus supplier payments made today for purchases
        -- (deferred lots included: this is cash, not cost). Before, a purchase
        -- paid later counted on its own day AND again as the payment's expense.
        SELECT COALESCE((
                   SELECT SUM(GREATEST(rp.amountpaid - COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                                        WHERE sa.farmid = rp.farmid AND sa.module = 'water' AND sa.status = 'Posted'
                                          AND sa.documenttype = 'RawMaterialPurchase'
                                          AND sa.documentid = rp.waterrawmaterialpurchaseid), 0), 0))
                   FROM   waterrawmaterialpurchases rp
                   WHERE  rp.farmid = p_farmid
                     AND  COALESCE(rp.lotsource, '') <> 'ManualDeferredCost'
                     AND  rp.purchasedate >= p_closingdate::timestamp
                     AND  rp.purchasedate <  p_closingdate::timestamp + interval '1 day'), 0)
             + COALESCE((
                   SELECT SUM(sa.amountapplied)
                   FROM   supplierpaymentallocation sa
                   JOIN   watersupplierpayments sp ON sp.watersupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
                   WHERE  sa.farmid = p_farmid AND sa.module = 'water' AND sa.status = 'Posted'
                     AND  sa.documenttype = 'RawMaterialPurchase' AND NOT sa.fromcredit
                     AND  COALESCE(sp.status, 'Posted') = 'Posted'
                     AND  sp.paymentdate >= p_closingdate::timestamp
                     AND  sp.paymentdate <  p_closingdate::timestamp + interval '1 day'), 0) AS rawmaterialspendtoday
    ),
    gen_exp AS (
        SELECT COALESCE(SUM(e.amount), 0) AS generalexpenses
        FROM   waterexpenses e
        WHERE  e.farmid = p_farmid AND e.isdeleted = FALSE AND e.status = 'Approved'
           AND COALESCE(e.sourcetype, '') NOT IN ('RawMaterialPurchase', 'WaterInternalUsage',
                                                  'WaterSupplierPayment')   -- 429: now in raw spend
           AND e.expensedate >= p_closingdate::timestamp
           AND e.expensedate <  p_closingdate::timestamp + interval '1 day'
    ),
    delivery_exp AS (
        SELECT COALESCE(SUM(de.amount), 0) AS deliveryexpenses
        FROM   waterdeliveryexpenses de
        INNER  JOIN ranked_returns rr2 ON rr2.waterdriverreturnid = de.waterdriverreturnid AND rr2.rn = 1
        WHERE  de.isapproved = TRUE
    ),
    closing_stock AS (
        SELECT COALESCE(SUM(st.quantity::numeric(14,3)), 0) AS closingstockbags
        FROM   waterstocktransactions st WHERE st.farmid = p_farmid
    )
    SELECT
        prod.bagsproduced,
        prod.totalproductioncost,
        sale_items.bagssold + driver_returns.driverbagssold          AS bagssold,
        sale_money.totalincome + driver_returns.drivertotalincome    AS totalincome,
        sale_money.creditsales + driver_returns.drivercreditsales    AS creditsales,
        payments.customercollections,
        driver_returns.bagsreturned,
        driver_returns.bagsdamaged,
        driver_returns.drivershortages                               AS drivershortagestotal,
        driver_returns.drivermomo + payments.momopayments            AS momobalance,
        driver_returns.driverbank + payments.bankpayments            AS bankbalance,
        raw_spend.rawmaterialspendtoday,
        closing_stock.closingstockbags,
        prod.totalproductioncost + raw_spend.rawmaterialspendtoday
            + gen_exp.generalexpenses + delivery_exp.deliveryexpenses AS totalexpenses,
        (sale_money.totalincome + driver_returns.drivertotalincome)
            - (sale_money.creditsales + driver_returns.drivercreditsales)
            + payments.customercollections
            - (prod.totalproductioncost + raw_spend.rawmaterialspendtoday
               + gen_exp.generalexpenses + delivery_exp.deliveryexpenses) AS cashathand
    FROM   prod
    CROSS  JOIN sale_items
    CROSS  JOIN sale_money
    CROSS  JOIN payments
    CROSS  JOIN driver_returns
    CROSS  JOIN raw_spend
    CROSS  JOIN gen_exp
    CROSS  JOIN delivery_exp
    CROSS  JOIN closing_stock
$function$;

-- ----------------------------------------------------------- self-test ------
-- The itemisation must still equal periodpnl's raw materials for every company.
DO $t$
DECLARE v_bad integer;
BEGIN
    SELECT COUNT(*) INTO v_bad
    FROM   (SELECT DISTINCT farmid FROM waterrawmaterialpurchases) x
    WHERE  (SELECT rawmaterialcost FROM spwaterreport_periodpnl(x.farmid, DATE '2000-01-01', DATE '2100-01-01'))
        <> (SELECT COALESCE(SUM(l.amount), 0) FROM spwaterreport_pllines(x.farmid, DATE '2000-01-01', DATE '2100-01-01') l
            WHERE l.linekey = 'RawMaterials');
    IF v_bad > 0 THEN RAISE EXCEPTION '429: % compan(ies) raw materials do not reconcile', v_bad; END IF;
END
$t$;

COMMIT;

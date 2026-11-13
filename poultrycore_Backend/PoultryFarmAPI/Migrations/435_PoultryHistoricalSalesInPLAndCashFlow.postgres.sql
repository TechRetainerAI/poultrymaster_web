-- =============================================================================
-- 435_PoultryHistoricalSalesInPLAndCashFlow.postgres.sql   (requires 413, 382)
--
-- Purpose
-- -------
-- A historical bird sale (Batch Bird Reconciliation, 413) now reaches Profit &
-- Loss and Cash Flow (boss, 2026-11-13):
--
--   "The total cost of the batch purchase is going into P and L -- therefore
--    the historical sale should also go there."
--
-- 413 kept historical sales out of every money report on purpose ("NO sale row,
-- NO cash, NO revenue"). The batch purchase, though, IS an expense row, so a
-- batch of 16,000 with 8,500 sold before tracking carried the cost of all
-- 16,000 and the income of none of them.
--
-- WHAT IS COUNTED
-- ---------------
--   Only AMOUNT RECEIVED, on the sale date.
--     * The part still OWED is already an opening customer debt (369); when it
--       is paid, the payment reaches P&L as Customer Debt Collections (382)
--       and Cash Flow as a receipt. Counting the full value here would count
--       that part twice.
--     * Value unknown (birds only) -> nothing: there is no amount.
--     * Reversed -> nothing.
--
-- WHAT IS NOT WRITTEN
-- -------------------
--   Nothing. No sale row, no cash transaction, no payment. The cash accounts'
--   opening balances already hold this money; posting it would double them.
--   The reports READ poultryhistoricalbirdsales -- turning this off is a
--   re-run of the previous function bodies.
--
-- CHANGED
-- -------
--   fnpoultrypl_historicalsales            NEW  the one source of the figures
--   sppoultryreport_pllines                 + Revenue line 'HistoricalBirdSales'
--                                           (plsummary reads pllines, so Total
--                                           Revenue and Net Profit follow)
--   sppoultryreport_plrevenuedetail         + its drilldown rows
--   sppoultryhistoricalsale_cashflowrows    NEW  Cash Flow arm 9
--   sppoultrycashflow_rows                  calls arm 9 (spliced into the live
--                                           body, which is ~1,000 lines;
--                                           nothing else in it is touched)
--   sppoultrycashflow_detail                + category 'Bird sales (before tracking)'
--
--   Financial Activity reads sppoultrycashflow_rows, so it shows the same
--   money in. Not changed: Advanced Reports sppoultryreport_profitloss,
--   Profit & Loss by Flock.
--
-- Bodies of pllines / plrevenuedetail / cashflow_detail were read from the live
-- database 2026-11-13 before writing; only the arms marked 435 are new.
-- No API change: the new rows use the existing columns.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- ------------------------------------------------- 1. the one source -------
CREATE OR REPLACE FUNCTION public.fnpoultrypl_historicalsales(
    p_farmid text, p_startdate date, p_enddate date
) RETURNS TABLE(historicalsaleid integer, saledate date, batchid integer,
                batchname text, flockname text, customername text,
                birds integer, priceperbird numeric, totalvalue numeric,
                amountreceived numeric, description text)
LANGUAGE sql STABLE
AS $function$
    SELECT h.historicalsaleid, h.saledate, h.batchid,
           b.batchname::text, f.name::text, c.name::text,
           h.birds, h.priceperbird, h.totalvalue,
           h.amountreceived::numeric(14,2),
           ('Bird sale before tracking - ' || COALESCE(b.batchname::text, 'Batch #' || h.batchid::text)
              || COALESCE(' / ' || f.name::text, '')
              || ' (' || h.birds::text || ' birds)')::text
    FROM   poultryhistoricalbirdsales h
    LEFT   JOIN mainflockbatch b ON b.batchid = h.batchid
    LEFT   JOIN flock f          ON f.flockid = h.flockid
    LEFT   JOIN customer c       ON c.customerid = h.customerid AND c.farmid = h.farmid
    WHERE  lower(h.farmid) = lower(p_farmid)
      AND  h.status = 'Posted'
      AND  NOT h.valueunknown
      AND  h.amountreceived > 0
      AND  (p_startdate IS NULL OR h.saledate >= p_startdate)
      AND  (p_enddate   IS NULL OR h.saledate <= p_enddate);
$function$;

COMMENT ON FUNCTION public.fnpoultrypl_historicalsales(text, date, date) IS
    '435: historical bird sales (413) as money received, on the sale date. '
    'Only amountreceived: the owed part is an opening debt whose payments '
    'already reach P&L (382) and Cash Flow. The only reader of the table for '
    'P&L and Cash Flow.';

-- ------------------------------------------------- 2. P&L lines -----------
CREATE OR REPLACE FUNCTION public.sppoultryreport_pllines(p_farmid text, p_startdate date, p_enddate date)
 RETURNS TABLE(section text, linekey text, linelabel text, amount numeric, sortorder integer, isinformational boolean, entrycount integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH rev AS (
        SELECT r.revenueline AS k, SUM(r.totalamount) AS amt, COUNT(*)::integer AS n
        FROM   fnpoultrypl_revenuelines(p_farmid, p_startdate, p_enddate) r
        GROUP  BY r.revenueline
        UNION ALL
        -- 363: credit notes given to customers reduce revenue.
        SELECT 'CreditNotes', -SUM(pp.amount), COUNT(*)::integer
        FROM   poultrypayments pp
        WHERE  pp.farmid = p_farmid AND pp.sourcetype = 'CreditNote'
          AND  COALESCE(pp.status, 'Posted') = 'Posted'
          AND  pp.paymentdate >= p_startdate AND pp.paymentdate < (p_enddate + 1)
        HAVING COUNT(*) > 0
        UNION ALL
        -- 382: money collected on customer debts.
        SELECT 'DebtCollections', SUM(pp.amount), COUNT(*)::integer
        FROM   poultrypayments pp
        WHERE  pp.farmid = p_farmid AND pp.debtid IS NOT NULL
          AND  COALESCE(pp.status, 'Posted') = 'Posted'
          AND  NOT pp.excludefrompl
          AND  pp.paymentdate >= p_startdate AND pp.paymentdate < (p_enddate + 1)
        HAVING COUNT(*) > 0
        UNION ALL
        -- 435: birds sold before tracking, the money received.
        SELECT 'HistoricalBirdSales', SUM(h.amountreceived), COUNT(*)::integer
        FROM   fnpoultrypl_historicalsales(p_farmid, p_startdate, p_enddate) h
        HAVING COUNT(*) > 0
    ),
    exp AS (
        SELECT e.plsection AS sec, e.plline AS k, SUM(e.amount) AS amt, COUNT(*)::integer AS n
        FROM   fnpoultrypl_expenselines(p_farmid, p_startdate, p_enddate) e
        WHERE  e.plsection <> 'Excluded'
        GROUP  BY e.plsection, e.plline
        UNION ALL
        -- 382: money paid on supplier debts.
        SELECT 'OperatingExpense', 'SupplierDebtPayments', SUM(d.amount), COUNT(*)::integer
        FROM   fnpoultrypl_supplierdebtpayments(p_farmid, p_startdate, p_enddate) d
        HAVING COUNT(*) > 0
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
    SELECT 'Revenue', rev.k,
           CASE rev.k WHEN 'CreditNotes' THEN 'Credit Notes & Allowances'   -- 363: label
                      WHEN 'DebtCollections' THEN 'Customer Debt Collections'   -- 382
                      WHEN 'HistoricalBirdSales' THEN 'Bird Sales (before tracking)'   -- 435
                      ELSE fnpoultrysale_revenuelabel(rev.k) END,
           rev.amt::numeric(14,2),
           CASE rev.k WHEN 'EggSales' THEN 1 WHEN 'BirdSales' THEN 2
                      WHEN 'HistoricalBirdSales' THEN 2   -- 435: right after Bird Sales
                      WHEN 'ManureSales' THEN 3 WHEN 'FeedSales' THEN 4
                      WHEN 'CreditNotes' THEN 6 WHEN 'DebtCollections' THEN 7 ELSE 5 END,
           FALSE, rev.n
    FROM   rev WHERE rev.amt <> 0
    UNION ALL
    SELECT exp.sec, exp.k,
           CASE exp.k WHEN 'SupplierDebtPayments' THEN 'Supplier Debt Payments'   -- 382
                      ELSE fnpoultryexpense_pllinelabel(exp.k) END,
           exp.amt::numeric(14,2),
           CASE exp.k
                WHEN 'Feed' THEN 11 WHEN 'Medication' THEN 12 WHEN 'DirectLabour' THEN 13
                WHEN 'ProductionSupplies' THEN 14 WHEN 'FlockCost' THEN 15 WHEN 'OtherDirect' THEN 16
                WHEN 'Payroll' THEN 21 WHEN 'Utilities' THEN 22 WHEN 'Transport' THEN 23
                WHEN 'RepairsMaintenance' THEN 24 WHEN 'Rent' THEN 25 WHEN 'Marketing' THEN 26
                WHEN 'Insurance' THEN 27 WHEN 'Security' THEN 28 WHEN 'ProfessionalServices' THEN 29
                WHEN 'Communications' THEN 30 WHEN 'Administration' THEN 31 WHEN 'OtherOperating' THEN 32
                WHEN 'SupplierDebtPayments' THEN 33   -- 382
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

-- ------------------------------------------------- 3. P&L drilldown --------
CREATE OR REPLACE FUNCTION public.sppoultryreport_plrevenuedetail(p_farmid text, p_startdate date, p_enddate date, p_linekey text)
 RETURNS TABLE(saleid integer, saledate timestamp without time zone, product text, customername text, quantity numeric, unitprice numeric, totalamount numeric, amountpaid numeric, paymentmethod text, revenueline text, revenuelabel text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT r.saleid, r.saledate, r.product, r.customername, r.quantity, r.unitprice,
           r.totalamount, r.amountpaid, r.paymentmethod,
           r.revenueline, fnpoultrysale_revenuelabel(r.revenueline)
    FROM   fnpoultrypl_revenuelines(p_farmid, p_startdate, p_enddate) r
    WHERE  (p_linekey IS NULL OR r.revenueline = p_linekey)
    UNION ALL
    -- 363: credit notes, negative.
    SELECT NULL::integer, pp.paymentdate,
           ('Credit note ' || COALESCE(pp.paymentnumber, ''))::text,
           c.name::text, NULL::numeric, NULL::numeric,
           -pp.amount, 0::numeric, NULL::text,
           'CreditNotes'::text, 'Credit Notes & Allowances'::text
    FROM   poultrypayments pp
    LEFT   JOIN customer c ON c.customerid = pp.customerid AND c.farmid = pp.farmid
    WHERE  pp.farmid = p_farmid AND pp.sourcetype = 'CreditNote'
      AND  COALESCE(pp.status, 'Posted') = 'Posted'
      AND  pp.paymentdate >= p_startdate AND pp.paymentdate < (p_enddate + 1)
      AND  (p_linekey IS NULL OR p_linekey = 'CreditNotes')
    UNION ALL
    -- 382: money collected on customer debts.
    SELECT NULL::integer, pp.paymentdate,
           (CASE WHEN d.saletype IS NOT NULL THEN 'Old debt collected: ' || d.saletype || ' - ' ELSE '' END   -- 384
                    || 'Debt ' || COALESCE(d.debtnumber, '#' || pp.debtid::text)
                    || COALESCE(' - payment ' || pp.paymentnumber, ''))::text,
           c.name::text, NULL::numeric, NULL::numeric,
           pp.amount, pp.amount, pp.paymentmethod::text,
           'DebtCollections'::text, 'Customer Debt Collections'::text
    FROM   poultrypayments pp
    LEFT   JOIN poultrycustomerdebts d ON d.debtid = pp.debtid AND d.farmid = pp.farmid
    LEFT   JOIN customer c ON c.customerid = pp.customerid AND c.farmid = pp.farmid
    WHERE  pp.farmid = p_farmid AND pp.debtid IS NOT NULL
      AND  COALESCE(pp.status, 'Posted') = 'Posted'
      AND  NOT pp.excludefrompl
      AND  pp.paymentdate >= p_startdate AND pp.paymentdate < (p_enddate + 1)
      AND  (p_linekey IS NULL OR p_linekey = 'DebtCollections')
    UNION ALL
    -- 435: birds sold before tracking, the money received.
    SELECT NULL::integer, h.saledate::timestamp, h.description, h.customername,
           h.birds::numeric, h.priceperbird,
           h.amountreceived, h.amountreceived, NULL::text,
           'HistoricalBirdSales'::text, 'Bird Sales (before tracking)'::text
    FROM   fnpoultrypl_historicalsales(p_farmid, p_startdate, p_enddate) h
    WHERE  (p_linekey IS NULL OR p_linekey = 'HistoricalBirdSales')
    ORDER  BY 2 DESC, 1 DESC NULLS LAST;
$function$;

-- ------------------------------------------------- 4. Cash Flow arm 9 ------
CREATE OR REPLACE FUNCTION public.sppoultryhistoricalsale_cashflowrows(
    p_farmid text, p_fromdate timestamp, p_todate timestamp
) RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, createdat timestamp without time zone)
LANGUAGE sql STABLE
AS $function$
    -- No cash account: the money came in before the farm used the application
    -- and is already inside the opening balances that were typed in.
    SELECT 'HistoricalSale'::text, FALSE, h.historicalsaleid, NULL::integer, NULL::text,
           h.saledate::timestamp, 'CashIn'::text, 'HistoricalSale'::text, h.historicalsaleid,
           FALSE, h.amountreceived, h.description, 'OperatingIn'::text,
           hs.createdat
    FROM   fnpoultrypl_historicalsales(p_farmid, NULL, NULL) h
    JOIN   poultryhistoricalbirdsales hs ON hs.historicalsaleid = h.historicalsaleid
    WHERE  h.saledate::timestamp >= COALESCE(p_fromdate, '-infinity'::timestamp)
      AND  h.saledate::timestamp <= COALESCE(p_todate,   'infinity'::timestamp);
$function$;

-- Splice the call into the live sppoultrycashflow_rows, right after arm 8.
-- Its body is ~1,000 lines and has been replaced whole by many migrations;
-- copying it here would freeze whatever this file saw. Refuses (rather than
-- guesses) when the anchor is not there exactly once.
DO $splice$
DECLARE
    v_def    text := pg_get_functiondef('public.sppoultrycashflow_rows(text, timestamp, timestamp)'::regprocedure);
    v_anchor text := 'SELECT * FROM public.sppoultryemployeeloan_cashflowrows(p_farmid, v_from, v_to);';
    v_n      integer;
BEGIN
    IF position('sppoultryhistoricalsale_cashflowrows' IN v_def) > 0 THEN
        RAISE NOTICE '435: sppoultrycashflow_rows already calls arm 9 -- left as is.';
        RETURN;
    END IF;
    v_n := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
    IF v_n <> 1 THEN
        RAISE EXCEPTION '435: expected the employee-advance arm exactly once in sppoultrycashflow_rows, found %', v_n;
    END IF;
    EXECUTE replace(v_def, v_anchor, v_anchor || E'\n\n'
        || E'    -- ---- 9. (435) birds sold before tracking: the money received ------\n'
        || E'    RETURN QUERY\n'
        || E'    SELECT * FROM public.sppoultryhistoricalsale_cashflowrows(p_farmid, v_from, v_to);');
END
$splice$;

-- ------------------------------------------------- 5. Cash Flow category ---
CREATE OR REPLACE FUNCTION public.sppoultrycashflow_detail(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, category text, createdat timestamp without time zone)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname,
           r.transactiondate, r.transactiontype, r.sourcetype, r.sourceid,
           r.istransfer, r.amount, r.description, r.flowgroup,
           CASE
               WHEN r.rowsource IN ('Expense', 'ExpensePayment')
                   THEN COALESCE(NULLIF(btrim(e.category), ''), 'Uncategorised')
               WHEN r.rowsource IN ('Receipt', 'SaleResidual') THEN 'Sales'
               WHEN r.rowsource = 'ReceiptReversal' THEN 'Sale payment reversals'
               WHEN r.rowsource = 'CustomerRefund'  THEN 'Customer refunds'
               WHEN r.rowsource = 'CustomerRefundReversal' THEN 'Customer refunds'   -- 367: refund reversal
               WHEN r.rowsource = 'SupplierAdvance' THEN 'Supplier advances'   -- 370: supplier credit rows
               WHEN r.rowsource = 'SupplierDebtPayment' THEN 'Supplier debt payments'
               WHEN r.rowsource IN ('SupplierRefund', 'SupplierRefundReversal') THEN 'Supplier refunds'
               WHEN r.rowsource = 'HistoricalSale' THEN 'Bird sales (before tracking)'   -- 435
               -- Capital keeps its own type as the bucket, so an owner injection
               -- never merges into a generic "Adjustment" slice.
               ELSE COALESCE(NULLIF(btrim(r.sourcetype), ''), 'Other')
           END::text,
           r.createdat              -- 302: the entry time
    FROM   public.sppoultrycashflow_rows(p_farmid, p_fromdate, p_todate) r
    -- LEFT, so an expense deleted after the fact still appears in the totals as
    -- Uncategorised rather than dropping out of them.
    LEFT   JOIN expense e
           ON  r.rowsource IN ('Expense', 'ExpensePayment')
           AND e.expenseid = r.sourceid
           AND lower(e.farmid::text) = lower(p_farmid);
$function$;

-- ------------------------------------------------- 6. self-test ------------
-- For every farm with a counted historical sale: the P&L line, its drilldown,
-- Cash Flow rows and Cash Flow detail all equal the amount received.
DO $test$
DECLARE
    v_farm  record;
    v_pl    numeric;
    v_drill numeric;
    v_cf    numeric;
    v_cfd   numeric;
    v_n     integer := 0;
BEGIN
    FOR v_farm IN
        SELECT h.farmid, SUM(h.amountreceived) AS received
        FROM   poultryhistoricalbirdsales h
        WHERE  h.status = 'Posted' AND NOT h.valueunknown AND h.amountreceived > 0
        GROUP  BY h.farmid
    LOOP
        v_n := v_n + 1;
        SELECT COALESCE(SUM(amount), 0) INTO v_pl
        FROM   sppoultryreport_pllines(v_farm.farmid, '1900-01-01', '2999-12-31')
        WHERE  linekey = 'HistoricalBirdSales';
        SELECT COALESCE(SUM(totalamount), 0) INTO v_drill
        FROM   sppoultryreport_plrevenuedetail(v_farm.farmid, '1900-01-01', '2999-12-31', 'HistoricalBirdSales');
        SELECT COALESCE(SUM(amount), 0) INTO v_cf
        FROM   sppoultrycashflow_rows(v_farm.farmid, NULL, NULL)
        WHERE  rowsource = 'HistoricalSale';
        SELECT COALESCE(SUM(amount), 0) INTO v_cfd
        FROM   sppoultrycashflow_detail(v_farm.farmid, NULL, NULL)
        WHERE  category = 'Bird sales (before tracking)';
        IF v_pl <> v_farm.received OR v_drill <> v_farm.received
           OR v_cf <> v_farm.received OR v_cfd <> v_farm.received THEN
            RAISE EXCEPTION '435 self-test: farm % received % but P&L % / drilldown % / cash rows % / cash detail %',
                v_farm.farmid, v_farm.received, v_pl, v_drill, v_cf, v_cfd;
        END IF;
        -- Financial Activity reads the same rows; it must still run.
        PERFORM 1 FROM fnpoultryfa_events(v_farm.farmid, '1900-01-01', '2999-12-31') LIMIT 1;
    END LOOP;
    RAISE NOTICE '435 self-test passed for % farm(s) with historical sales received.', v_n;
END
$test$;

COMMIT;

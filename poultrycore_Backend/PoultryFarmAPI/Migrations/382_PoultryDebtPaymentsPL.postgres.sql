-- =============================================================================
-- 382_PoultryDebtPaymentsPL.postgres.sql            (requires 363, 369, 370)
--
-- Purpose
-- -------
-- Money paid against a debt recorded by hand now reaches Profit & Loss
-- (user, 2026-10-16):
--
--   recording a customer / supplier debt     nothing (no money moved)
--   recording customer / supplier credit     nothing until it is applied
--   a customer PAYS a customer debt          Revenue, on the payment date
--                                            line 'DebtCollections'
--   we PAY a supplier debt                   Operating Expense, on the payment
--                                            date, line 'SupplierDebtPayments'
--   a supplier ADVANCE applied to a debt     Operating Expense, on the day it
--                                            is applied (cash left with the
--                                            advance; an opening / manual
--                                            credit netted against a debt
--                                            moves no money and stays out)
--
-- Everything else already sits in P&L once: the part of a payment applied to a
-- sale (the sale is revenue), to a purchase / batch / expense (the expense row
-- is the cost), credit applied to a sale or expensed lot (351 / 370).
--
-- Each payment is IN by default. The owner or an admin can exclude a single
-- payment (and include it again): excludefrompl on poultrypayments (the whole
-- paymentgroupid) and on poultrysupplierpayments. The API sets it right after
-- recording, in the same transaction, when the payment dialog says so.
--
-- sppoultryreport_pllines / _plrevenuedetail / _plexpensedetail are replaced
-- whole: the live bodies (272 + 363) were read before writing and only the
-- arms marked 382 are new. sppoultryreport_plsummary reads pllines, so totals
-- and Net Profit follow. Not changed: Financial Activity (fnpoultryfa_*, as
-- 369 / 370), Advanced Reports sppoultryreport_profitloss, Cash Flow (already
-- shows debt payments, 3f).
-- =============================================================================

-- ------------------------------------------------------------ 1. columns ----
ALTER TABLE poultrypayments
    ADD COLUMN IF NOT EXISTS excludefrompl boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS plexcludedby  text,
    ADD COLUMN IF NOT EXISTS plexcludedat  timestamp;

ALTER TABLE poultrysupplierpayments
    ADD COLUMN IF NOT EXISTS excludefrompl boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS plexcludedby  text,
    ADD COLUMN IF NOT EXISTS plexcludedat  timestamp;

-- ------------------------------------- 2. what a payment puts on P&L -------
-- Customer: the payment group's Posted debt rows.
CREATE OR REPLACE FUNCTION public.fnpoultrypayment_plamount(p_farmid text, p_paymentgroupid uuid)
RETURNS numeric
LANGUAGE sql
STABLE
AS $function$
    SELECT COALESCE(SUM(pp.amount), 0)::numeric(14,2)
    FROM   poultrypayments pp
    WHERE  pp.farmid = p_farmid AND pp.paymentgroupid = p_paymentgroupid
      AND  pp.debtid IS NOT NULL
      AND  COALESCE(pp.status, 'Posted') = 'Posted';
$function$;

-- Supplier: what the payment put on supplier debts -- in cash, or, for a cash
-- advance, when applied.
CREATE OR REPLACE FUNCTION public.fnpoultrysupplierpayment_plamount(p_farmid text, p_paymentid integer)
RETURNS numeric
LANGUAGE sql
STABLE
AS $function$
    SELECT COALESCE(SUM(sa.amountapplied), 0)::numeric(14,2)
    FROM   supplierpaymentallocation sa
    JOIN   poultrysupplierpayments sp ON sp.poultrysupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
    WHERE  sa.farmid = p_farmid AND sa.paymentid = p_paymentid
      AND  sa.module = 'poultry' AND sa.documenttype = 'SupplierDebt'
      AND  COALESCE(sa.status, 'Posted') = 'Posted'
      AND  COALESCE(sp.status, 'Posted') = 'Posted'
      AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype);
$function$;

-- Supplier debt payment rows for a period (shared by pllines and the drilldown).
CREATE OR REPLACE FUNCTION public.fnpoultrypl_supplierdebtpayments(p_farmid text, p_startdate date, p_enddate date)
RETURNS TABLE(allocationid integer, paymentid integer, pldate timestamp, amount numeric,
              supplierid integer, debtnumber text, fromcredit boolean, paymentmethod text)
LANGUAGE sql
STABLE
AS $function$
    SELECT sa.allocationid, sp.poultrysupplierpaymentid,
           CASE WHEN COALESCE(sa.fromcredit, false) THEN sa.createdat ELSE sp.paymentdate END,
           sa.amountapplied::numeric(14,2), sp.supplierid, sd.debtnumber,
           COALESCE(sa.fromcredit, false), sp.paymentmethod
    FROM   supplierpaymentallocation sa
    JOIN   poultrysupplierpayments sp ON sp.poultrysupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
    LEFT   JOIN poultrysupplierdebts sd ON sd.debtid = sa.documentid AND sd.farmid = sa.farmid
    WHERE  sa.farmid = p_farmid
      AND  sa.module = 'poultry' AND sa.documenttype = 'SupplierDebt'
      AND  COALESCE(sa.status, 'Posted') = 'Posted'
      AND  COALESCE(sp.status, 'Posted') = 'Posted'
      AND  NOT sp.excludefrompl
      AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)
      AND  CASE WHEN COALESCE(sa.fromcredit, false) THEN sa.createdat ELSE sp.paymentdate END >= p_startdate
      AND  CASE WHEN COALESCE(sa.fromcredit, false) THEN sa.createdat ELSE sp.paymentdate END <  (p_enddate + 1);
$function$;

-- --------------------------------------------- 3. exclude / include -------
CREATE OR REPLACE FUNCTION public.sppoultrypayment_setplexclusion(
    p_farmid text, p_paymentgroupid uuid, p_exclude boolean, p_by text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM poultrypayments pp
                   WHERE pp.farmid = p_farmid AND pp.paymentgroupid = p_paymentgroupid) THEN
        RAISE EXCEPTION 'Payment not found for this company.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM poultrypayments pp
                   WHERE pp.farmid = p_farmid AND pp.paymentgroupid = p_paymentgroupid
                     AND COALESCE(pp.status, 'Posted') = 'Posted') THEN
        RAISE EXCEPTION 'This payment has been reversed, so it is not on Profit & Loss.' USING ERRCODE = 'P0001';
    END IF;
    IF fnpoultrypayment_plamount(p_farmid, p_paymentgroupid) = 0 THEN
        RAISE EXCEPTION 'Only a payment on a customer debt is added to Profit & Loss -- a sale is already revenue.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE poultrypayments pp
    SET    excludefrompl = COALESCE(p_exclude, false),
           plexcludedby  = CASE WHEN p_exclude THEN p_by END,
           plexcludedat  = CASE WHEN p_exclude THEN (now() at time zone 'utc') END
    WHERE  pp.farmid = p_farmid AND pp.paymentgroupid = p_paymentgroupid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrysupplierpayment_setplexclusion(
    p_farmid text, p_paymentid integer, p_exclude boolean, p_by text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
BEGIN
    SELECT COALESCE(sp.status, 'Posted') INTO v_status
    FROM   poultrysupplierpayments sp
    WHERE  sp.farmid = p_farmid AND sp.poultrysupplierpaymentid = p_paymentid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Supplier payment not found for this company.' USING ERRCODE = 'P0001';
    END IF;
    IF v_status <> 'Posted' THEN
        RAISE EXCEPTION 'This payment has been reversed, so it is not on Profit & Loss.' USING ERRCODE = 'P0001';
    END IF;
    IF fnpoultrysupplierpayment_plamount(p_farmid, p_paymentid) = 0 THEN
        RAISE EXCEPTION 'Only a payment on a supplier debt is added to Profit & Loss -- a purchase or expense is already a cost.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE poultrysupplierpayments sp
    SET    excludefrompl = COALESCE(p_exclude, false),
           plexcludedby  = CASE WHEN p_exclude THEN p_by END,
           plexcludedat  = CASE WHEN p_exclude THEN (now() at time zone 'utc') END
    WHERE  sp.farmid = p_farmid AND sp.poultrysupplierpaymentid = p_paymentid;
END;
$function$;

-- ----------------------------------------------------- 4. P&L lines --------
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
                      ELSE fnpoultrysale_revenuelabel(rev.k) END,
           rev.amt::numeric(14,2),
           CASE rev.k WHEN 'EggSales' THEN 1 WHEN 'BirdSales' THEN 2
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

-- --------------------------------------------------- 5. drilldowns ----------
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
           ('Debt ' || COALESCE(d.debtnumber, '#' || pp.debtid::text)
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
    ORDER  BY 2 DESC, 1 DESC NULLS LAST;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryreport_plexpensedetail(p_farmid text, p_startdate date, p_enddate date, p_linekey text)
 RETURNS TABLE(expenseid integer, expensedate timestamp without time zone, category text, description text, amount numeric, suppliername text, sourcetype text, sourcelabel text, paymentmethod text, paymentstatus text, costtype text, plline text, pllinelabel text, poultrycapitalassetid integer, islegacy boolean)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT e.expenseid, e.expensedate, e.category, e.description, e.amount,
           e.suppliername, e.sourcetype, fnpoultryexpense_sourcelabel(e.sourcetype),
           e.paymentmethod, e.paymentstatus, e.costtype,
           e.plline, fnpoultryexpense_pllinelabel(e.plline),
           e.poultrycapitalassetid, e.islegacy
    FROM   fnpoultrypl_expenselines(p_farmid, p_startdate, p_enddate) e
    WHERE  (p_linekey IS NULL OR e.plline = p_linekey)
      AND  e.plsection <> 'Excluded'
    UNION ALL
    -- 382: money paid on supplier debts (no expense row: expenseid NULL).
    SELECT NULL::integer, d.pldate, 'Supplier Debt Payment'::text,
           ('Debt ' || COALESCE(d.debtnumber, '') || ' - supplier payment #' || d.paymentid::text
                    || CASE WHEN d.fromcredit THEN ' (advance applied)' ELSE '' END)::text,
           d.amount, s.name::text, 'SupplierDebtPayment'::text, 'Supplier debt payment'::text,
           d.paymentmethod, 'Paid'::text, 'OperatingExpense'::text,
           'SupplierDebtPayments'::text, 'Supplier Debt Payments'::text,
           NULL::integer, false
    FROM   fnpoultrypl_supplierdebtpayments(p_farmid, p_startdate, p_enddate) d
    LEFT   JOIN supplier s ON s.supplierid = d.supplierid AND s.farmid = p_farmid
    WHERE  (p_linekey IS NULL OR p_linekey = 'SupplierDebtPayments')
    ORDER  BY 2 DESC, 1 DESC NULLS LAST;
$function$;

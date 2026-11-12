-- =============================================================================
-- 425_WaterSupplierDebtPaymentsPL.postgres.sql   (Water credits programme W4; requires 424)
--
-- Purpose
-- -------
-- Poultry 382 / 383, supplier side, for Water:
--
--   recording a supplier debt / supplier credit     nothing (no money moved)
--   WE PAY a supplier debt                          Operating Expense, on the
--                                                   payment date, line
--                                                   'SupplierDebtPayments'
--   a CASH advance applied to a supplier debt       Operating Expense, on the
--                                                   day it is applied (the cash
--                                                   left with the advance)
--   a credit note / opening / manual credit         never: it moved no money
--   netted against a debt
--
-- Each payment is IN by default; the owner / an admin can exclude one
-- (watersupplierpayments.excludefrompl). A cash advance's exclusion also covers
-- what it pays when applied later.
--
-- OLD DEBT (383): Record supplier payment -- money that pays no recorded
-- purchase, bill or debt is a payment of something owed from before the
-- system. spwatersupplierpayment_recordolddebt records it as a HistoricalDebt
-- (paidonentry) and pays it in the same call, so it is an operating expense,
-- not an advance. "Keep it as credit" calls the plain record. Reversing such a
-- payment reverses its debt.
--
-- P&L: periodpnl's operating expenses + pllines 'SupplierDebtPayments' +
-- plexpensedetail -- the itemisation still sums to periodpnl.
--
-- Deploy order: this migration, then the Farm API, then the web app.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

ALTER TABLE public.watersupplierpayments ADD COLUMN IF NOT EXISTS excludefrompl boolean NOT NULL DEFAULT false;
ALTER TABLE public.watersupplierpayments ADD COLUMN IF NOT EXISTS plexcludedby text;
ALTER TABLE public.watersupplierpayments ADD COLUMN IF NOT EXISTS plexcludedat timestamp;

-- Every amount a supplier payment puts on P&L, dated when it counts.
CREATE OR REPLACE FUNCTION public.fnwaterpl_supplierdebtpaymentrows(p_farmid text, p_start timestamp, p_end timestamp)
RETURNS TABLE(entrydate timestamp, allocationid integer, watersupplierpaymentid integer, debtnumber text,
              suppliername text, amount numeric, fromcredit boolean)
LANGUAGE sql STABLE AS $f$
    SELECT CASE WHEN sa.fromcredit THEN sa.createdat ELSE sp.paymentdate END,
           sa.allocationid, sp.watersupplierpaymentid, d.debtnumber::text, s.suppliername::text,
           sa.amountapplied::numeric(14,2), sa.fromcredit
    FROM   supplierpaymentallocation sa
    JOIN   watersupplierpayments sp ON sp.watersupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
    LEFT   JOIN watersupplierdebts d ON d.debtid = sa.documentid AND d.farmid = sa.farmid
    LEFT   JOIN watersuppliers s ON s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sa.farmid = p_farmid AND sa.module = 'water' AND sa.documenttype = 'SupplierDebt'
      AND  sa.status = 'Posted' AND COALESCE(sp.status, 'Posted') = 'Posted'
      AND  NOT sp.excludefrompl
      -- a credit that moved no money never reaches P&L
      AND  NOT public.fnwatersupplier_iscreditkind(sp.sourcetype)
      AND  CASE WHEN sa.fromcredit THEN sa.createdat ELSE sp.paymentdate END >= p_start
      AND  CASE WHEN sa.fromcredit THEN sa.createdat ELSE sp.paymentdate END <  p_end;
$f$;

CREATE OR REPLACE FUNCTION public.fnwaterpl_supplierdebtpayments(p_farmid text, p_start timestamp, p_end timestamp)
RETURNS TABLE(total numeric, n integer) LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(SUM(r.amount), 0)::numeric(14,2), COUNT(*)::integer
    FROM   public.fnwaterpl_supplierdebtpaymentrows(p_farmid, p_start, p_end) r;
$f$;

-- What one payment puts on P&L (in cash, or what it pays when applied as credit).
CREATE OR REPLACE FUNCTION public.fnwatersupplierpayment_plamount(p_farmid text, p_paymentid integer)
RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(SUM(sa.amountapplied), 0)::numeric(14,2)
    FROM   supplierpaymentallocation sa
    JOIN   watersupplierpayments sp ON sp.watersupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
    WHERE  sa.farmid = p_farmid AND sa.module = 'water' AND sa.paymentid = p_paymentid
      AND  sa.documenttype = 'SupplierDebt' AND sa.status = 'Posted'
      AND  NOT public.fnwatersupplier_iscreditkind(sp.sourcetype);
$f$;

CREATE OR REPLACE FUNCTION public.spwatersupplierpayment_setplexclusion(p_farmid text, p_paymentid integer,
                                                                        p_exclude boolean, p_by text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_sp watersupplierpayments%ROWTYPE;
BEGIN
    SELECT * INTO v_sp FROM watersupplierpayments sp WHERE sp.watersupplierpaymentid = p_paymentid AND sp.farmid = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found for this company.' USING ERRCODE = 'P0001'; END IF;
    IF COALESCE(v_sp.status, 'Posted') <> 'Posted' THEN
        RAISE EXCEPTION 'This payment has been reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF public.fnwatersupplierpayment_plamount(p_farmid, p_paymentid) <= 0 THEN
        RAISE EXCEPTION 'Only a payment on a supplier debt is on Profit & Loss.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE watersupplierpayments
    SET    excludefrompl = COALESCE(p_exclude, false),
           plexcludedby = CASE WHEN p_exclude THEN p_by END,
           plexcludedat = CASE WHEN p_exclude THEN (now() AT TIME ZONE 'utc') END
    WHERE  watersupplierpaymentid = p_paymentid AND farmid = p_farmid;
    RETURN 1;
END
$f$;

-- 383: the leftover pays a debt from before the system (an operating expense).
CREATE OR REPLACE FUNCTION public.spwatersupplierpayment_recordolddebt(p_farmid text, p_supplierid integer,
    p_amount numeric, p_allocations jsonb, p_paymentmethod text DEFAULT NULL, p_paymentdate timestamp DEFAULT NULL,
    p_cashaccountid integer DEFAULT NULL, p_reference text DEFAULT NULL, p_note text DEFAULT NULL,
    p_sourcetype text DEFAULT 'SupplierPayments', p_createdby text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_alloc jsonb := COALESCE(p_allocations, '[]'::jsonb);
    v_used  numeric(14,2);
    v_rest  numeric(14,2);
    v_res   jsonb;
    v_date  timestamp := COALESCE(p_paymentdate, (now() at time zone 'utc'));
BEGIN
    IF p_supplierid IS NULL THEN
        RAISE EXCEPTION 'Choose the supplier.' USING ERRCODE = 'P0001';
    END IF;
    SELECT COALESCE(SUM(a.amount), 0) INTO v_used
    FROM   jsonb_to_recordset(v_alloc) AS a(documenttype text, documentid integer, amount numeric)
    WHERE  a.documentid IS NOT NULL AND COALESCE(a.amount, 0) <> 0;
    v_rest := round(COALESCE(p_amount, 0), 2) - v_used;
    IF v_rest > 0 THEN
        v_res := public.spwatersupplierdebt_create(p_farmid, p_supplierid, v_rest, v_date::date, 'HistoricalDebt',
                     'Old debt paid on entry (from before the system)', p_reference, p_note, p_createdby);
        UPDATE watersupplierdebts SET paidonentry = TRUE WHERE debtid = (v_res->>'debtId')::int;
        v_alloc := v_alloc || jsonb_build_array(jsonb_build_object(
                       'documenttype', 'SupplierDebt', 'documentid', (v_res->>'debtId')::int, 'amount', v_rest));
    END IF;
    RETURN public.spwatersupplierpayment_record(p_farmid, p_supplierid, p_amount, v_alloc, p_paymentmethod,
               p_paymentdate, p_cashaccountid, p_reference, p_note, p_sourcetype, p_createdby);
END
$f$;

CREATE OR REPLACE FUNCTION public.spwatersupplierpayment_reverse(p_farmid text, p_paymentid integer, p_reason text DEFAULT NULL::text, p_reversedby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_now   timestamp := (now() at time zone 'utc');
    v_count integer := 0;
    v_row   record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM watersupplierpayments sp
                   WHERE sp.watersupplierpaymentid = p_paymentid AND sp.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Payment not found for this company.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM watersupplierpayments sp
                   WHERE sp.watersupplierpaymentid = p_paymentid AND sp.farmid = p_farmid
                     AND COALESCE(sp.status, 'Posted') = 'Posted') THEN
        RAISE EXCEPTION 'This payment has already been reversed.';
    END IF;
    -- 424
    IF EXISTS (SELECT 1 FROM watersupplierpayments sp WHERE sp.watersupplierpaymentid = p_paymentid
               AND sp.farmid = p_farmid AND public.fnwatersupplier_iscreditkind(sp.sourcetype)) THEN
        RAISE EXCEPTION 'This is supplier credit added by hand -- reverse it on Supplier Credits.';
    END IF;
    IF EXISTS (SELECT 1 FROM supplierpaymentallocation sa WHERE sa.farmid = p_farmid AND sa.module = 'water'
               AND sa.paymentid = p_paymentid AND sa.status = 'Posted' AND sa.fromcredit) THEN
        RAISE EXCEPTION 'Credit from this payment has been applied since. Undo those applications first.';
    END IF;
    IF EXISTS (SELECT 1 FROM watersupplierrefundlines rl JOIN watersupplierrefunds r ON r.refundid = rl.refundid
               WHERE rl.farmid = p_farmid AND rl.watersupplierpaymentid = p_paymentid AND r.status = 'Posted') THEN
        RAISE EXCEPTION 'The supplier refunded part of this payment. Reverse the refund first.';
    END IF;

    FOR v_row IN
        SELECT sa.documenttype, sa.documentid, sa.amountapplied
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = 'water'
          AND  sa.paymentid = p_paymentid AND sa.status = 'Posted'
    LOOP
        PERFORM public.fnwaterpayable_addpaid(p_farmid, v_row.documenttype, v_row.documentid, -v_row.amountapplied);   -- 424
        v_count := v_count + 1;
    END LOOP;

    UPDATE supplierpaymentallocation
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason
    WHERE  farmid = p_farmid AND module = 'water'
      AND  paymentid = p_paymentid AND status = 'Posted';

    -- Cash before the header flips, since the sync reads a Posted header.
    PERFORM spwatersupplierpaymentcash_unsync(p_farmid, p_paymentid, p_reversedby);

    UPDATE watersupplierpayments
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason
    WHERE  watersupplierpaymentid = p_paymentid AND farmid = p_farmid;

    -- 425 (383): a debt recorded only because this payment paid it goes with it.
    UPDATE watersupplierdebts d
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = COALESCE(p_reason, 'Payment reversed')
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'water' AND sa.paymentid = p_paymentid
      AND  sa.documenttype = 'SupplierDebt' AND d.debtid = sa.documentid AND d.farmid = p_farmid
      AND  d.paidonentry AND d.status = 'Posted' AND d.amountpaid = 0;
    RETURN v_count;
END;
$function$;

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

    -- 422: a credit note is an allowance given -- revenue the business gave up.
    v_totalincome := (v_storefrontincome + v_driverincome
                      - COALESCE((SELECT SUM(cn.amount) FROM waterpayments cn
                                  WHERE cn.farmid = p_farmid AND cn.sourcetype = 'CreditNote'
                                    AND COALESCE(cn.status, 'Posted') = 'Posted'
                                    AND cn.paymentdate >= v_start AND cn.paymentdate < v_end), 0)
                      -- 423 (382): money paid on debts recorded by hand is revenue
                      + (SELECT dc.total FROM public.fnwaterpl_debtcollections(p_farmid, v_start, v_end) dc))::numeric(14,2);

    -- Cash paid for raw materials (matches the closing's AmountPaid basis).
    v_rawmaterialcost := COALESCE((
        SELECT SUM(p.amountpaid) FROM waterrawmaterialpurchases p
        WHERE p.farmid = p_farmid AND p.purchasedate >= v_start AND p.purchasedate < v_end), 0);

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
          AND e.expensedate >= v_start AND e.expensedate < v_end), 0);

    v_deliveryexpenses := COALESCE((
        SELECT SUM(de.amount) FROM waterdeliveryexpenses de
        INNER JOIN waterdriverreturns dr ON dr.waterdriverreturnid = de.waterdriverreturnid
        WHERE dr.farmid = p_farmid AND dr.status IN ('Draft','Approved') AND de.isapproved = TRUE
          AND dr.returndate >= v_start AND dr.returndate < v_end), 0);

    -- 425 (382): money paid on supplier debts recorded by hand is an operating expense
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
        -- 423 (382): money paid on customer debts recorded by hand
        SELECT 'DebtCollections', 'Customer debt collections', dc.total, dc.n, 4
        FROM   bounds b CROSS JOIN LATERAL public.fnwaterpl_debtcollections(p_farmid, b.s, b.e) dc
        UNION ALL
        -- 422: credit notes -- allowances given, negative revenue
        SELECT 'CreditNotes', 'Credit notes & allowances',
               -COALESCE(SUM(cn.amount), 0), COUNT(*)::integer, 3
        FROM   waterpayments cn, bounds b
        WHERE  cn.farmid = p_farmid AND cn.sourcetype = 'CreditNote'
          AND  COALESCE(cn.status, 'Posted') = 'Posted'
          AND  cn.paymentdate >= b.s AND cn.paymentdate < b.e
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
    -- 425 (382): money paid on supplier debts recorded by hand
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
    -- 425
    SELECT r.entrydate, ('SP-' || lpad(r.watersupplierpaymentid::text, 5, '0'))::text,
           COALESCE(r.suppliername, 'Supplier')::text,
           ('Paid on debt ' || COALESCE(r.debtnumber, '') || CASE WHEN r.fromcredit THEN ' (from an advance)' ELSE '' END)::text,
           r.amount
    FROM   public.fnwaterpl_supplierdebtpaymentrows(p_farmid, p_startdate::timestamp,
                                                    p_enddate::timestamp + make_interval(days => 1)) r
    WHERE  (p_linekey IS NULL OR p_linekey = 'SupplierDebtPayments')
    ORDER  BY 1 DESC, 2;
$function$;

DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.spwatersupplierpayment_setplexclusion(text, integer, boolean, text) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- =============================================================================
-- 463  Water: Closing by Category -- a whole period on one page
--                                   (Water port of poultry 132/135/143)
-- =============================================================================
--
-- Water already had the per-day closing list (/water-reports/closing-report)
-- and the Daily Summary; Poultry's ported those FROM Water. What Water lacked
-- is Poultry's period report: one date range totalled into Financial,
-- Production, Inventory, Losses, Cash & Delivery and Staff.
--
-- READ-ONLY. Every figure comes from the function that already owns it, so the
-- report can never disagree with the screens it summarises:
--   money in the P&L      spwaterreport_plsummary   (= Profit & Loss)
--   cash                  spwatercashflow_summary   (= Cash Flow)
--   owed by customers     spwatercustomerbalancesummary (today, like Poultry's)
--   owed to suppliers     fnwaterpayables          (today)
--   held for staff        spwateremployeecredit_total (today)
-- Quantities come straight from their tables with the same filters those
-- screens use (approved, not deleted, not reversed).
--
-- Returns one jsonb object of PascalCase keys (the page reads them by name).
-- Idempotent. PostgreSQL.
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.spwaterclosingreport_get(text, date, date);

CREATE FUNCTION public.spwaterclosingreport_get(p_farmid text, p_fromdate date, p_todate date)
RETURNS jsonb
LANGUAGE plpgsql STABLE AS $f$
DECLARE
    v_from  date := LEAST(p_fromdate, p_todate);
    v_to    date := GREATEST(p_fromdate, p_todate);
    v_fts   timestamp;
    v_tts   timestamp;
    v_days  integer;
    v_pl    record;
    v_cf    record;
    v_prod  record;
    v_raw   record;
    v_del   record;
    v_open  numeric;
    v_close numeric;
    v_coll  numeric;
    v_cust  record;
    v_supp  numeric;
    v_held  numeric;
    v_pay   record;
BEGIN
    v_fts  := v_from::timestamp;
    v_tts  := (v_to + 1)::timestamp - interval '1 microsecond';
    v_days := (v_to - v_from) + 1;

    SELECT * INTO v_pl FROM public.spwaterreport_plsummary(p_farmid, v_from, v_to);
    SELECT * INTO v_cf FROM public.spwatercashflow_summary(p_farmid, v_fts, v_tts);

    -- production: approved, not deleted batches of the period
    SELECT COUNT(*)                                       AS batches,
           COALESCE(SUM(pb.bagsproduced), 0)              AS produced,
           COALESCE(SUM(COALESCE(pb.damagedbags, 0)), 0)  AS damaged,
           COALESCE(SUM(COALESCE(pb.rejectedsachets, 0)), 0) AS rejectedsachets,
           COALESCE(SUM(COALESCE(pb.estimatedwaterusedlitres, 0)), 0) AS litres
    INTO   v_prod
    FROM   waterproductionbatches pb
    WHERE  pb.farmid = p_farmid AND NOT COALESCE(pb.isdeleted, FALSE) AND pb.status = 'Approved'
      AND  pb.productiondate BETWEEN v_from AND v_to;

    -- raw materials: purchases (real ones -- not manual deferred cost, not a
    -- reversed receipt) and consumption (not reversed)
    SELECT COALESCE((SELECT SUM(pu.totalcost) FROM waterrawmaterialpurchases pu
                     WHERE pu.farmid = p_farmid AND COALESCE(pu.lotsource, '') <> 'ManualDeferredCost'
                       AND pu.reversedat IS NULL AND pu.purchasedate BETWEEN v_fts AND v_tts), 0) AS purchased,
           COALESCE((SELECT COUNT(*) FROM waterrawmaterialpurchases pu
                     WHERE pu.farmid = p_farmid AND COALESCE(pu.lotsource, '') <> 'ManualDeferredCost'
                       AND pu.reversedat IS NULL AND pu.purchasedate BETWEEN v_fts AND v_tts), 0) AS purchases,
           COALESCE((SELECT SUM(u.quantityused) FROM waterrawmaterialusage u
                     WHERE u.farmid = p_farmid AND NOT COALESCE(u.isreversed, FALSE)
                       AND u.useddate BETWEEN v_fts AND v_tts), 0) AS consumedqty,
           COALESCE((SELECT SUM(u.totalcost) FROM waterrawmaterialusage u
                     WHERE u.farmid = p_farmid AND NOT COALESCE(u.isreversed, FALSE)
                       AND u.useddate BETWEEN v_fts AND v_tts), 0) AS consumedvalue
    INTO   v_raw;

    -- finished-goods stock (bags): everything before the period, and through it
    SELECT COALESCE(SUM(st.quantity) FILTER (WHERE st.createddate < v_fts), 0),
           COALESCE(SUM(st.quantity) FILTER (WHERE st.createddate <= v_tts), 0)
    INTO   v_open, v_close
    FROM   waterstocktransactions st
    WHERE  st.farmid = p_farmid;

    -- delivery runs of the period
    SELECT COALESCE((SELECT SUM(l.bagsloaded) FROM watervehicleloadings l
                     WHERE l.farmid = p_farmid AND NOT COALESCE(l.isdeleted, FALSE)
                       AND l.loaddate BETWEEN v_fts AND v_tts), 0) AS loaded,
           COALESCE(SUM(dr.bagssold), 0)       AS sold,
           COALESCE(SUM(dr.bagsreturned), 0)   AS returned,
           COALESCE(SUM(dr.bagsdamaged), 0)    AS damaged,
           COALESCE(SUM(COALESCE(dr.cashcollected, 0) + COALESCE(dr.momocollected, 0) + COALESCE(dr.bankcollected, 0)), 0) AS collected,
           COALESCE(SUM(dr.creditsalesamount), 0) AS credit,
           COALESCE(SUM(dr.shortageamount), 0)    AS shortage,
           COUNT(dr.waterdriverreturnid)          AS runs,
           COALESCE((SELECT SUM(de.amount) FROM waterdeliveryexpenses de
                     JOIN waterdriverreturns d2 ON d2.waterdriverreturnid = de.waterdriverreturnid
                     WHERE de.farmid = p_farmid AND de.isapproved AND d2.status = 'Approved'
                       AND d2.returndate BETWEEN v_fts AND v_tts), 0) AS deliveryexpenses
    INTO   v_del
    FROM   waterdriverreturns dr
    WHERE  dr.farmid = p_farmid AND dr.status = 'Approved' AND dr.returndate BETWEEN v_fts AND v_tts;

    -- customer money received in the period (not credit that never was cash)
    SELECT COALESCE(SUM(p.amount), 0) INTO v_coll
    FROM   waterpayments p
    WHERE  p.farmid = p_farmid AND COALESCE(p.status, 'Posted') = 'Posted'
      AND  NOT public.fnwater_isnocashcredit(p.sourcetype)
      AND  p.paymentdate BETWEEN v_fts AND v_tts;

    -- positions today
    SELECT * INTO v_cust FROM public.spwatercustomerbalancesummary(p_farmid);
    SELECT COALESCE(SUM(x.balance), 0) INTO v_supp FROM public.fnwaterpayables(p_farmid) x WHERE x.balance > 0;
    SELECT COALESCE(t.totalheld, 0) INTO v_held FROM public.spwateremployeecredit_total(p_farmid) t;

    -- payroll of the period (by pay date)
    SELECT COUNT(*) AS runs,
           COALESCE(SUM(r.totalgrosspay), 0) AS gross,
           COALESCE(SUM(r.totalnetpay) FILTER (WHERE r.status = 'Paid'), 0) AS paid
    INTO   v_pay
    FROM   waterpayrollruns r
    WHERE  r.farmid = p_farmid AND NOT COALESCE(r.isdeleted, FALSE) AND r.status IN ('Approved', 'Paid')
      AND  COALESCE(r.paydate, r.periodend) BETWEEN v_from AND v_to;

    RETURN jsonb_build_object(
        'FromDate', v_from, 'ToDate', v_to, 'Days', v_days,
        -- Financial (= Profit & Loss for the same period)
        'TotalRevenue',            COALESCE(v_pl.totalrevenue, 0),
        'StorefrontSales',         COALESCE(v_pl.storefrontsales, 0),
        'DeliveryCollections',     COALESCE(v_pl.deliverycollections, 0),
        'RawMaterialsCost',        COALESCE(v_pl.rawmaterials, 0),
        'ProductionCost',          COALESCE(v_pl.productioncost, 0),
        'GrossProfit',             COALESCE(v_pl.grossprofit, 0),
        'OperatingExpenses',       COALESCE(v_pl.totaloperatingexpenses, 0) + COALESCE(v_pl.totalothercosts, 0),
        'TotalLosses',             COALESCE(v_pl.totallosses, 0),
        'NetProfit',               COALESCE(v_pl.netprofit, 0),
        'NetMarginPct',            COALESCE(v_pl.netmarginpercent, 0),
        'OwedByCustomers',         COALESCE(v_cust.totalbalance, 0),
        'OverdueFromCustomers',    COALESCE(v_cust.overduebalance, 0),
        'OwedToSuppliers',         v_supp
    ) || jsonb_build_object(
        -- Production
        'ProductionBatches',       v_prod.batches,
        'BagsProduced',            v_prod.produced,
        'BagsDamagedInProduction', v_prod.damaged,
        'GoodBags',                v_prod.produced - v_prod.damaged,
        'RejectedSachets',         v_prod.rejectedsachets,
        'WaterUsedLitres',         v_prod.litres,
        'AvgBagsPerDay',           round((v_prod.produced - v_prod.damaged)::numeric / NULLIF(v_days, 0), 1),
        'CostPerGoodBag',          round((COALESCE(v_pl.rawmaterials, 0) + COALESCE(v_pl.productioncost, 0))
                                         / NULLIF(v_prod.produced - v_prod.damaged, 0), 2)
    ) || jsonb_build_object(
        -- Inventory
        'OpeningStockBags',        v_open,
        'ClosingStockBags',        v_close,
        'BagsSold',                COALESCE(v_pl.bagssold, 0),
        'RawMaterialPurchases',    v_raw.purchases,
        'RawMaterialsPurchasedValue', v_raw.purchased,
        'RawMaterialsConsumedQty', v_raw.consumedqty,
        'RawMaterialsConsumedValue', v_raw.consumedvalue,
        -- Losses
        'ProductionLosses',        COALESCE(v_pl.productionlosses, 0),
        'DriverShortages',         COALESCE(v_pl.drivershortages, 0)
    ) || jsonb_build_object(
        -- Cash & Delivery (= Cash Flow for the same period)
        'OpeningCash',             COALESCE(v_cf.openingbalance, 0),
        'MoneyIn',                 COALESCE(v_cf.moneyin, 0),
        'MoneyOut',                COALESCE(v_cf.moneyout, 0),
        'NetCashFlow',             COALESCE(v_cf.netcashflow, 0),
        'ClosingCash',             COALESCE(v_cf.cashathand, 0),
        'CustomerPaymentsReceived', v_coll,
        'DeliveryRuns',            v_del.runs,
        'BagsLoaded',              v_del.loaded,
        'BagsSoldOnDelivery',      v_del.sold,
        'BagsReturned',            v_del.returned,
        'BagsDamagedOnDelivery',   v_del.damaged,
        'DriverCollections',       v_del.collected,
        'DeliveryCreditSales',     v_del.credit,
        'DeliveryExpenses',        v_del.deliveryexpenses
    ) || jsonb_build_object(
        -- Staff
        'PayrollRuns',             v_pay.runs,
        'PayrollGross',            v_pay.gross,
        'PayrollPaidOut',          v_pay.paid,
        'HeldForStaff',            v_held
    );
END $f$;

COMMIT;

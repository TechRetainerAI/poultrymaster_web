-- =============================================================================
-- 403: Broilers, phase 5 -- bird sales are not eggs sold.
--
-- Two readers summed EVERY sale's quantity as "eggs sold":
--   * fnpoultrydailyclosing_livetotals -- the daily closing's eggs sold, AND
--     its closing egg stock (eggs produced to date - "sold" to date), so 100
--     chickens sold took 100 eggs off the egg stock;
--   * sppoultryclosingreport_get       -- the period closing report's eggs sold
--     (its egg stock comes from the stock ledger and was already right).
-- On dev, 2026-11-03: 13 posted sales -- Birds, Chicken, Manure, droppings,
-- Broken Eggs -- added 2,654 units that were never eggs.
--
-- Now only egg sales count: the product says egg and it is not a byproduct
-- (Broken Eggs is its own stock, and production already excludes broken eggs)
-- -- the egg rule fnflock_lifetimesummary and P&L by flock use (375). Income,
-- credit and cash keep EVERY sale.
--
-- What moves: Draft closings and the closing report (both computed live).
-- Submitted / approved closings keep the figures frozen when they were
-- submitted (poultrydailyclosings.closingsnapshot / closingstock).
-- Bodies are the LIVE ones, read from dev 2026-11-03; same signatures.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION public.fnpoultrydailyclosing_livetotals(p_farmid text, p_closingdate date)
 RETURNS TABLE(eggsproduced numeric, prodcost numeric, eggsdamaged numeric, closingstock numeric, feedusedqty numeric, medusedqty numeric, mortality numeric, eggssold numeric, eggsreturned numeric, totalincome numeric, creditsales numeric, cashcollected numeric, momocollected numeric, bankcollected numeric, customercollections numeric, totalexpenses numeric, cashbalance numeric, momobalance numeric, bankbalance numeric, cashathand numeric)
 LANGUAGE sql
AS $function$
    WITH
    pr AS (   -- production for the day (Production Log)
        SELECT COALESCE(SUM(COALESCE(p.totalproduction,0)),0)          AS eggsproduced,
               COALESCE(SUM(COALESCE(p.brokeneggs,0)),0)               AS eggsdamaged,
               COALESCE(SUM(COALESCE(p.totalcostofproduction,0)),0)    AS prodcost,
               COALESCE(SUM(COALESCE(p.mortality,0)),0)                AS mortalityqty,
               COALESCE(SUM(COALESCE(p.feedkg,0)),0)                   AS feedusedqty,
               COALESCE(SUM(COALESCE(p.totalmedicationconsumed,0)),0)  AS medusedqty
        FROM   productionrecords p
        WHERE  p.farmid = p_farmid AND p.date::date = p_closingdate
    ),
    sale AS (  -- sales for the day
        -- 403: only egg sales are eggs sold (not birds, manure or byproducts).
        SELECT COALESCE(SUM(COALESCE(s.quantity,0)) FILTER (WHERE lower(COALESCE(s.product, '')) LIKE '%egg%' AND public.fnpoultrysale_byproductrole(s.product) IS NULL),0) AS eggssold,
               COALESCE(SUM(COALESCE(s.totalamount,0)),0)                                       AS totalincome,
               -- 364: owed at the end of the day, not the full total of a part-paid sale.
               COALESCE(SUM(public.fnpoultrysale_owedasof(p_farmid, s.saleid, p_closingdate)),0)                 AS creditsales,
               COALESCE(SUM(s.totalamount - public.fnpoultrysale_owedasof(p_farmid, s.saleid, p_closingdate)),0) AS cashcoll
        FROM   sale s
        WHERE  s.status = 'Posted' AND s.farmid = p_farmid AND s.saledate::date = p_closingdate
    ),
    egg AS (   -- cumulative egg stock as of the date
        SELECT COALESCE((SELECT SUM(COALESCE(p2.totalproduction,0) - COALESCE(p2.brokeneggs,0))
                         FROM public.productionrecords p2
                         WHERE p2.farmid = p_farmid AND p2.date::date <= p_closingdate),0) AS producedtodate,
               COALESCE((SELECT SUM(COALESCE(s2.quantity,0))
                         FROM public.sale s2
                         WHERE s2.status = 'Posted' AND s2.farmid = p_farmid AND s2.saledate::date <= p_closingdate
                           AND lower(COALESCE(s2.product, '')) LIKE '%egg%' AND public.fnpoultrysale_byproductrole(s2.product) IS NULL),0) AS soldtodate   -- 403: egg stock falls only by egg sales
    ),
    pay AS (
        SELECT COALESCE(SUM(pp.amount::numeric(18,2)),0) AS customercollections
        FROM   poultrypayments pp
        WHERE  pp.farmid = p_farmid AND pp.paymentdate::date = p_closingdate
          -- 363: Posted, and money that came in (not an opening credit / credit note).
          AND  COALESCE(pp.status, 'Posted') = 'Posted'
          AND  COALESCE(pp.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote')
          -- 364: paid at the sale itself is already in cash collected.
          AND  NOT EXISTS (SELECT 1 FROM public.sale s2
                           WHERE s2.saleid = pp.saleid AND s2.farmid = p_farmid
                             AND s2.status = 'Posted' AND s2.saledate::date = p_closingdate)
    ),
    exp AS (
        SELECT COALESCE(SUM(e.amount::numeric(18,2)),0) AS totalexpenses
        FROM   expense e
        WHERE  COALESCE(e.sourcetype, '') <> 'PoultryInternalUsage' AND e.farmid = (CASE WHEN p_farmid ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                                THEN p_farmid::uuid ELSE NULL END)
          AND  e.expensedate::date = p_closingdate
    ),
    bal AS (   -- flexible account-type matching (e.g. 'FarmCashBox' -> Cash)
        SELECT COALESCE(SUM(CASE WHEN a.accounttype ILIKE '%MoMo%' OR a.accounttype ILIKE '%Mobile%' THEN a.currentbalance ELSE 0 END),0) AS momobalance,
               COALESCE(SUM(CASE WHEN a.accounttype ILIKE '%Bank%' THEN a.currentbalance ELSE 0 END),0) AS bankbalance,
               COALESCE(SUM(CASE WHEN a.accounttype ILIKE '%MoMo%' OR a.accounttype ILIKE '%Mobile%' OR a.accounttype ILIKE '%Bank%' THEN 0 ELSE a.currentbalance END),0) AS cashbalance
        FROM   poultrycashaccounts a
        WHERE  a.farmid = p_farmid AND a.isactive = TRUE
    )
    SELECT
        pr.eggsproduced::numeric(18,3),
        pr.prodcost::numeric(18,2),
        pr.eggsdamaged::numeric(18,3),
        (egg.producedtodate - egg.soldtodate)::numeric(18,3)      AS closingstock,
        pr.feedusedqty::numeric(18,3),
        pr.medusedqty::numeric(18,3),
        pr.mortalityqty::numeric(18,3)                            AS mortality,
        sale.eggssold::numeric(18,3),
        0::numeric(18,3)                                          AS eggsreturned,
        sale.totalincome::numeric(18,2),
        sale.creditsales::numeric(18,2),
        sale.cashcoll::numeric(18,2)                              AS cashcollected,
        0::numeric(18,2)                                          AS momocollected,
        0::numeric(18,2)                                          AS bankcollected,
        pay.customercollections,
        exp.totalexpenses,
        bal.cashbalance::numeric(18,2),
        bal.momobalance::numeric(18,2),
        bal.bankbalance::numeric(18,2),
        ((sale.totalincome - sale.creditsales) + pay.customercollections - exp.totalexpenses)::numeric(18,2) AS cashathand
    FROM pr, sale, egg, pay, exp, bal
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryclosingreport_get(p_farmid text, p_fromdate date, p_todate date)
 RETURNS TABLE(fromdate date, todate date, totalsales numeric, totalexpenses numeric, totalrawmaterialpurchases numeric, totalfeedcost numeric, totalmedicationcost numeric, totalcostofproduction numeric, netprofitloss numeric, totalowedbycustomers numeric, totaleggsproduced integer, totalgoodeggs integer, totalbrokeneggs integer, totalproductionrecords integer, avgeggsperday numeric, avgeggsperrecord numeric, totalfeedkg numeric, totalfeedconsumed numeric, totalmedicationconsumed numeric, avgproductioncostperegg numeric, openingeggstock numeric, closingeggstock numeric, eggssold numeric, rawmaterialspurchased numeric, rawmaterialsconsumed numeric, productionlossqty numeric, approvedlossvalue numeric, brokeneggstotal integer, cashsalescollected numeric, cashadjustmentsnet numeric, estimatedcashinflows numeric, placedbirds numeric, birdsleft numeric, birdslost numeric, openingbirds numeric, birdspurchased numeric, birdssold numeric, mortalitycount integer, closingbirds numeric, mortalityratepct numeric, eggsloadedfordelivery numeric, eggsreturned numeric, drivercollections numeric, deliveryexpenses numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_gid uuid;
    v_egg integer;
    v_bird integer;
    v_totalsales      numeric(18,2);
    v_eggssold        numeric(18,3);
    v_cashsales       numeric(18,2);
    v_creditsales     numeric(18,2);
    v_totalexpenses   numeric(18,2) := 0;
    v_rawmatexpense   numeric(18,2) := 0;
    v_rawpurchases    numeric(18,2);
    v_rawconsumed     numeric(18,3);
    v_eggsproduced    integer       := 0;
    v_brokeneggs      integer       := 0;
    v_prodrecords     integer       := 0;
    v_feedcost        numeric(18,2) := 0;
    v_medcost         numeric(18,2) := 0;
    v_prodcost        numeric(18,2) := 0;
    v_feedconsumed    numeric(18,3) := 0;
    v_medconsumed     numeric(18,3) := 0;
    v_proddays        integer       := 0;
    v_feedkg          numeric(18,3) := 0;
    v_mortalityprod   numeric(18,3) := 0;
    v_prodlossqty     numeric(18,3);
    v_lossrecordval   numeric(18,2);
    v_closingeggstock numeric(18,3) := 0;
    v_openingeggstock numeric(18,3) := 0;
    v_placedbirds     numeric(18,3);
    v_birdsleft       numeric(18,3);
    v_birdslost       numeric(18,3);
    v_openingbirds    numeric(18,3) := 0;
    v_closingbirds    numeric(18,3) := 0;
    v_birdspurchased  numeric(18,3) := 0;
    v_birdssold       numeric(18,3) := 0;
    v_cashadjnet      numeric(18,2);
BEGIN
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;

    SELECT pp.poultryproductid INTO v_egg
    FROM   poultryproducts pp
    WHERE  pp.farmid = p_farmid AND (pp.israweggproduct = TRUE OR pp.name IN ('Eggs', 'Chicken Eggs'))
    ORDER  BY pp.israweggproduct DESC, pp.poultryproductid
    LIMIT 1;

    SELECT pp.poultryproductid INTO v_bird
    FROM   poultryproducts pp
    WHERE  pp.farmid = p_farmid AND (pp.isbirdproduct = TRUE OR pp.name = 'Birds')
    ORDER  BY pp.isbirdproduct DESC, pp.poultryproductid
    LIMIT 1;

    -- ---- Money ---------------------------------------------------------------
    v_totalsales  := COALESCE((SELECT SUM(s.totalamount) FROM sale s WHERE s.status = 'Posted' AND s.farmid = p_farmid AND s.saledate BETWEEN p_fromdate AND p_todate), 0);
    -- 403: only egg sales are eggs sold (not birds, manure or byproducts).
    v_eggssold    := COALESCE((SELECT SUM(s.quantity)    FROM sale s WHERE s.status = 'Posted' AND s.farmid = p_farmid AND s.saledate BETWEEN p_fromdate AND p_todate
                                 AND lower(COALESCE(s.product, '')) LIKE '%egg%' AND public.fnpoultrysale_byproductrole(s.product) IS NULL), 0);
    v_cashsales   := COALESCE((SELECT SUM(s.totalamount) FROM sale s WHERE s.status = 'Posted' AND s.farmid = p_farmid AND s.saledate BETWEEN p_fromdate AND p_todate AND s.paid = TRUE), 0);
    v_creditsales := COALESCE((SELECT SUM(s.totalamount) FROM sale s WHERE s.status = 'Posted' AND s.farmid = p_farmid AND s.saledate BETWEEN p_fromdate AND p_todate AND COALESCE(s.paid, FALSE) = FALSE), 0);

    IF v_gid IS NOT NULL THEN
        v_totalexpenses := COALESCE((SELECT SUM(e.amount) FROM expense e
                                     WHERE e.farmid = v_gid AND e.expensedate::date BETWEEN p_fromdate AND p_todate), 0);
        v_rawmatexpense := COALESCE((SELECT SUM(e.amount) FROM expense e
                                     WHERE e.farmid = v_gid AND e.expensedate::date BETWEEN p_fromdate AND p_todate
                                       AND e.category = 'Raw Materials / Inventory Purchase'), 0);
    END IF;

    v_rawpurchases := COALESCE((SELECT SUM(pu.totalcost) FROM poultryrawmaterialpurchases pu
                                WHERE pu.farmid = p_farmid AND pu.purchasedate::date BETWEEN p_fromdate AND p_todate AND pu.reversedat IS NULL AND COALESCE(pu.lotsource, '') <> 'ManualDeferredCost' /* 371: not a purchase of the period */), 0);
    v_rawconsumed  := COALESCE((SELECT SUM(us.quantityused) FROM poultryrawmaterialusage us
                                WHERE us.farmid = p_farmid AND us.useddate::date BETWEEN p_fromdate AND p_todate), 0);

    -- ---- Production (from ProductionRecords - same as the Production Log) -----
    SELECT COALESCE(SUM(r.totalproduction), 0), COALESCE(SUM(r.brokeneggs), 0), COUNT(*)::int,
           COALESCE(SUM(r.totalfeedcost), 0), COALESCE(SUM(r.totalmedicationcost), 0), COALESCE(SUM(r.totalcostofproduction), 0),
           COALESCE(SUM(r.totalfeedconsumed), 0), COALESCE(SUM(r.totalmedicationconsumed), 0), COUNT(DISTINCT r.date)::int,
           COALESCE(SUM(r.feedkg), 0), COALESCE(SUM(r.mortality), 0)
    INTO   v_eggsproduced, v_brokeneggs, v_prodrecords,
           v_feedcost, v_medcost, v_prodcost,
           v_feedconsumed, v_medconsumed, v_proddays,
           v_feedkg, v_mortalityprod
    FROM   productionrecords r
    WHERE  r.farmid = p_farmid AND r.date BETWEEN p_fromdate AND p_todate;

    v_prodlossqty   := COALESCE((SELECT SUM(pl.quantitylost) FROM poultryproductionloss pl
                                 WHERE pl.farmid = p_farmid AND pl.lossdate::date BETWEEN p_fromdate AND p_todate), 0);
    v_lossrecordval := COALESCE((SELECT SUM(lr.estimatedvalue) FROM poultrylossrecords lr
                                 WHERE lr.farmid = p_farmid AND lr.lossdate::date BETWEEN p_fromdate AND p_todate
                                   AND lr.status = 'Approved'), 0);

    -- ---- Egg stock (inventory module; 0 when not configured) ------------------
    IF v_egg IS NOT NULL THEN
        v_closingeggstock := COALESCE((SELECT SUM(st.quantity) FROM poultrystocktransactions st
                                       WHERE st.farmid = p_farmid AND st.poultryproductid = v_egg
                                         AND st.createddate::date <= p_todate), 0);
        v_openingeggstock := COALESCE((SELECT SUM(st.quantity) FROM poultrystocktransactions st
                                       WHERE st.farmid = p_farmid AND st.poultryproductid = v_egg
                                         AND st.createddate::date < p_fromdate), 0);
    END IF;

    -- ---- Birds (from Flock + ProductionRecords - same as the Production Log) --
    v_placedbirds := COALESCE((
        SELECT SUM(f.quantity) FROM flock f
        WHERE f.farmid = p_farmid AND f.active = TRUE AND f.hasarrived = TRUE AND COALESCE(f.isdeleted, FALSE) = FALSE), 0);

    v_birdsleft := COALESCE((
        SELECT SUM(
            CASE
                WHEN lr.noofbirdsleft IS NULL           THEN f.quantity
                WHEN lr.noofbirdsleft < 0               THEN 0
                WHEN lr.noofbirdsleft > f.quantity      THEN f.quantity
                ELSE lr.noofbirdsleft
            END)
        FROM flock f
        LEFT JOIN LATERAL (
            SELECT pr.noofbirdsleft
            FROM   productionrecords pr
            WHERE  pr.farmid = p_farmid AND pr.flockid = f.flockid AND pr.date <= p_todate
            ORDER  BY pr.date DESC
            LIMIT 1
        ) lr ON TRUE
        WHERE f.farmid = p_farmid AND f.active = TRUE AND f.hasarrived = TRUE AND COALESCE(f.isdeleted, FALSE) = FALSE), 0);

    v_birdslost := CASE WHEN v_placedbirds - v_birdsleft > 0 THEN v_placedbirds - v_birdsleft ELSE 0 END;

    -- Inventory-based bird movements (0 when the module is not configured).
    IF v_bird IS NOT NULL THEN
        v_openingbirds := COALESCE((SELECT SUM(st.quantity) FROM poultrystocktransactions st
                                    WHERE st.farmid = p_farmid AND st.poultryproductid = v_bird
                                      AND st.createddate::date < p_fromdate), 0);
        v_closingbirds := COALESCE((SELECT SUM(st.quantity) FROM poultrystocktransactions st
                                    WHERE st.farmid = p_farmid AND st.poultryproductid = v_bird
                                      AND st.createddate::date <= p_todate), 0);
        v_birdspurchased := COALESCE((SELECT SUM(st.quantity) FROM poultrystocktransactions st
                                      WHERE st.farmid = p_farmid AND st.poultryproductid = v_bird
                                        AND st.txntype = 'Bird Batch Purchase'
                                        AND st.createddate::date BETWEEN p_fromdate AND p_todate), 0);
        v_birdssold := -COALESCE((SELECT SUM(st.quantity) FROM poultrystocktransactions st
                                  WHERE st.farmid = p_farmid AND st.poultryproductid = v_bird
                                    AND st.txntype = 'Bird Sale'
                                    AND st.createddate::date BETWEEN p_fromdate AND p_todate), 0);
    END IF;

    v_cashadjnet := COALESCE((SELECT SUM(CASE WHEN ca.adjustmenttype IN ('In','Deposit','Add','Increase','Credit')  THEN ca.amount
                                              WHEN ca.adjustmenttype IN ('Out','Withdraw','Deduct','Decrease','Debit') THEN -ca.amount
                                              ELSE ca.amount END)
                              FROM cashadjustment ca
                              WHERE ca.farmid = p_farmid AND ca.adjustmentdate::date BETWEEN p_fromdate AND p_todate), 0);

    RETURN QUERY SELECT
        p_fromdate, p_todate,
        v_totalsales, v_totalexpenses, v_rawpurchases,
        v_feedcost, v_medcost, v_prodcost,
        (v_totalsales - v_totalexpenses)::numeric(18,2), v_creditsales,
        v_eggsproduced, (v_eggsproduced - v_brokeneggs)::int, v_brokeneggs,
        v_prodrecords,
        (CASE WHEN v_proddays    > 0 THEN v_eggsproduced * 1.0 / v_proddays    ELSE 0 END)::numeric(18,2),
        (CASE WHEN v_prodrecords > 0 THEN v_eggsproduced * 1.0 / v_prodrecords ELSE 0 END)::numeric(18,2),
        v_feedkg,
        v_feedconsumed, v_medconsumed,
        (CASE WHEN v_eggsproduced > 0 THEN v_prodcost / v_eggsproduced ELSE 0 END)::numeric(18,4),
        v_openingeggstock, v_closingeggstock, v_eggssold,
        v_rawpurchases, v_rawconsumed,
        v_prodlossqty, v_lossrecordval, v_brokeneggs,
        v_cashsales, v_cashadjnet, (v_cashsales + v_cashadjnet)::numeric(18,2),
        -- Birds (Production-Log reconciled)
        v_placedbirds, v_birdsleft, v_birdslost,
        v_openingbirds, v_birdspurchased, v_birdssold,
        v_mortalityprod::int, v_closingbirds,
        (CASE WHEN v_placedbirds > 0 THEN v_mortalityprod / v_placedbirds * 100 ELSE 0 END)::numeric(9,2),
        -- Delivery (populated by delivery module reconciliation)
        0::numeric(18,3), 0::numeric(18,3),
        0::numeric(18,2), 0::numeric(18,2);
END;
$function$;

COMMIT;

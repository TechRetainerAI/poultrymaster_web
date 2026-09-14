-- Behavioural checks for migration 278: opening the water deferred balance.
--
-- One DO block per theme, a NOTICE per check reading "expect X got Y". Run
-- inside a transaction you ROLL BACK; it writes settings, items and purchases.
--
--   psql ... -X -c "BEGIN;" -f water-deferred-cost-opening.test.sql -c "ROLLBACK;"
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **Nothing changes for anybody today.** The interlock is still shut, so no
-- company can produce an EXPENSE_WHEN_CONSUMED lot and both CASE expressions in
-- 278 write the zero that was already there. Section 0 asserts the interlock
-- AFTER the migration; everything past it lifts the interlock for this
-- transaction only, and the lift is discarded with the ROLLBACK.
--
-- The rest:
--   A. A normal purchase opens with NO deferred balance, and the rest of the lot
--      is untouched.
--   B. A deferred purchase opens with its WHOLE cost deferred -- including a
--      credit purchase where nothing has been paid, which is the case that
--      separates "what the stock cost" from "what we owe".
--   C. Editing an untouched deferred lot carries the balance with the cost, in
--      both directions, and an edit that does not touch the cost leaves it be.
--   D. The edit is keyed on the LOT's snapshot, not today's setting: turning
--      deferral off must not zero an existing deferred lot through an unrelated
--      edit.
--   E. THE GUARD 278 DEPENDS ON. spwaterrawmaterialpurchase_update refuses any
--      lot that has been drawn from. 278's header argues that this is what makes
--      rewriting the deferred pair outright safe rather than merely convenient,
--      so if that guard is ever relaxed this check must fail and take 278's
--      reasoning down with it in plain sight.
--   F. There is no lot-to-lot transfer to test, and why.

-- =============================================================================
-- 0. THE INTERLOCK IS STILL SHUT AFTER 278.
-- =============================================================================
DO $lock$
BEGIN
    RAISE NOTICE '0a. interlock still shut  expect        f  got %',
        fnwatercostrecognition_deferralready();
    IF fnwatercostrecognition_deferralready() THEN
        RAISE EXCEPTION '278 opened the deferral interlock. Only 279 may do that.';
    END IF;
END
$lock$;

CREATE OR REPLACE FUNCTION public.fnwatercostrecognition_deferralready()
RETURNS boolean LANGUAGE sql IMMUTABLE AS $ready$ SELECT TRUE $ready$;

DO $t$
DECLARE
    v_farm  text;
    v_acct  integer;
    v_item  integer;
    v_lot   integer;
    v_usage integer;
    v_def   numeric;
    v_tot   numeric;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE EXCEPTION 'No water company to run these checks against.';
    END IF;
    RAISE NOTICE '   using water company %', v_farm;

    DELETE FROM waterfinancialsettings WHERE farmid = v_farm;

    SELECT ca.watercashaccountid INTO v_acct
    FROM   watercashaccounts ca
    WHERE  ca.farmid = v_farm AND ca.isactive = TRUE
    ORDER  BY ca.watercashaccountid LIMIT 1;
    IF v_acct IS NULL THEN
        INSERT INTO watercashaccounts (farmid, accountname, accounttype, currentbalance, isactive)
        VALUES (v_farm, 'ZZ Test Till 278', 'Cash', 0, TRUE)
        RETURNING watercashaccountid INTO v_acct;
    END IF;

    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Film 278', 'SachetFilm', 'Roll', 'Roll', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_item;

    -- =====================================================================
    -- A. A NORMAL PURCHASE OPENS WITH NOTHING DEFERRED.
    -- =====================================================================
    v_lot := spwaterrawmaterialpurchase_insert(
        p_farmid => v_farm, p_waterrawmaterialitemid => v_item, p_suppliername => 'ZZ Supplier',
        p_purchasedate => (now() at time zone 'utc'), p_quantity => 10, p_unitcost => 100,
        p_paymentmethod => 'Cash', p_amountpaid => 1000, p_receipturl => NULL,
        p_receivedbystaffid => NULL, p_notes => 'ZZ 278 normal', p_createdby => 'ZZ tester',
        p_supplierid => NULL, p_totalcost => 1000, p_watercashaccountid => v_acct,
        p_productionunit => 'Roll', p_productionunitsperpurchaseunit => 1);

    SELECT deferredtotalcost, deferredremainingcost INTO v_tot, v_def
    FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot;
    RAISE NOTICE 'A1. normal opens at 0 total  expect     0.00  got %', v_tot;
    RAISE NOTICE 'A2. and 0 remaining          expect     0.00  got %', v_def;
    RAISE NOTICE 'A3. operational cost is real expect  1000.00  got %',
        (SELECT totalcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot);
    RAISE NOTICE 'A4. and the lot is full      expect  10.000   got %',
        (SELECT remainingquantity FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot);

    -- =====================================================================
    -- B. A DEFERRED PURCHASE OPENS AT ITS WHOLE COST.
    --
    -- Entered on CREDIT with nothing paid. This is the case that proves the
    -- balance is opened from totalcost and not from amountpaid: what we owe the
    -- supplier has nothing to do with what the stock cost.
    -- =====================================================================
    PERFORM spwaterfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');

    v_lot := spwaterrawmaterialpurchase_insert(
        p_farmid => v_farm, p_waterrawmaterialitemid => v_item, p_suppliername => 'ZZ Supplier',
        p_purchasedate => (now() at time zone 'utc'), p_quantity => 10, p_unitcost => 100,
        p_paymentmethod => 'Credit', p_amountpaid => 0, p_receipturl => NULL,
        p_receivedbystaffid => NULL, p_notes => 'ZZ 278 deferred', p_createdby => 'ZZ tester',
        p_supplierid => NULL, p_totalcost => 1000, p_watercashaccountid => NULL,
        p_productionunit => 'Roll', p_productionunitsperpurchaseunit => 1);

    SELECT deferredtotalcost, deferredremainingcost INTO v_tot, v_def
    FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot;
    RAISE NOTICE 'B1. deferred opens at cost   expect  1000.00  got %', v_tot;
    RAISE NOTICE 'B2. all of it still waiting  expect  1000.00  got %', v_def;
    RAISE NOTICE 'B3. though nothing was paid  expect     0.00  got %',
        (SELECT amountpaid FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot);
    RAISE NOTICE 'B4. and it wrote no expense  expect        t  got %',
        ((SELECT linkedwaterexpenseid FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot) IS NULL);
    -- Operational cost is untouched by any of this.
    RAISE NOTICE 'B5. operational cost unchanged expect  1000.00  got %',
        (SELECT totalcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot);

    -- =====================================================================
    -- C. AN EDIT CARRIES THE BALANCE WITH THE COST.
    -- =====================================================================
    PERFORM spwaterrawmaterialpurchase_update(
        p_waterrawmaterialpurchaseid => v_lot, p_farmid => v_farm,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 10, p_unitcost => 150, p_paymentmethod => 'Credit', p_amountpaid => 0,
        p_receipturl => NULL, p_notes => 'ZZ 278 repriced up', p_supplierid => NULL,
        p_totalcost => 1500, p_watercashaccountid => NULL,
        p_productionunit => 'Roll', p_productionunitsperpurchaseunit => 1);

    SELECT deferredtotalcost, deferredremainingcost INTO v_tot, v_def
    FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot;
    RAISE NOTICE 'C1. repricing up moves it    expect  1500.00  got %', v_tot;
    RAISE NOTICE 'C2. remaining follows too    expect  1500.00  got %', v_def;

    -- And down again, because a rescale that only works one way is a rescale
    -- that does not work.
    PERFORM spwaterrawmaterialpurchase_update(
        p_waterrawmaterialpurchaseid => v_lot, p_farmid => v_farm,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 10, p_unitcost => 80, p_paymentmethod => 'Credit', p_amountpaid => 0,
        p_receipturl => NULL, p_notes => 'ZZ 278 repriced down', p_supplierid => NULL,
        p_totalcost => 800, p_watercashaccountid => NULL,
        p_productionunit => 'Roll', p_productionunitsperpurchaseunit => 1);

    RAISE NOTICE 'C3. repricing down moves it  expect   800.00  got %',
        (SELECT deferredremainingcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot);

    -- =====================================================================
    -- D. THE EDIT READS THE LOT'S SNAPSHOT, NOT TODAY'S SETTING.
    --
    -- Turn deferral OFF, then edit the lot that was entered while it was on. The
    -- lot keeps its deferred balance: its snapshot still says
    -- EXPENSE_WHEN_CONSUMED, and that is the only thing the edit may consult.
    -- Otherwise an unrelated edit to the notes would silently move a closed
    -- month's P&L.
    -- =====================================================================
    PERFORM spwaterfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');

    PERFORM spwaterrawmaterialpurchase_update(
        p_waterrawmaterialpurchaseid => v_lot, p_farmid => v_farm,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 10, p_unitcost => 80, p_paymentmethod => 'Credit', p_amountpaid => 0,
        p_receipturl => NULL, p_notes => 'ZZ 278 just a note change', p_supplierid => NULL,
        p_totalcost => 800, p_watercashaccountid => NULL,
        p_productionunit => 'Roll', p_productionunitsperpurchaseunit => 1);

    RAISE NOTICE 'D1. snapshot survives the setting expect EXPENSE_WHEN_CONSUMED  got %',
        (SELECT costrecognitionmethod FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot);
    RAISE NOTICE 'D2. and so does the balance  expect   800.00  got %',
        (SELECT deferredremainingcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot);

    RAISE NOTICE '--- 278 checks done. ROLL BACK this transaction. ---';
END
$t$;

-- =============================================================================
-- E. THE GUARD 278 DEPENDS ON.
--
-- 278 rewrites the deferred pair outright on edit instead of rescaling it, and
-- the header's argument for why that is exact rather than merely convenient is
-- ENTIRELY this guard: a lot that has been drawn from cannot be edited at all,
-- so no part of its deferred balance can already have been recognised.
--
-- If someone relaxes that guard, 278's reasoning silently stops holding and a
-- partly-recognised balance could be rewritten underneath a reported expense.
-- This check exists so that change fails here, loudly, instead.
-- =============================================================================
DO $guard$
DECLARE
    v_farm  text;
    v_item  integer;
    v_lot   integer;
    v_usage integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;

    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Film 278e', 'SachetFilm', 'Roll', 'Roll', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_item;

    INSERT INTO waterrawmaterialpurchases
        (farmid, waterrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
         paymentmethod, amountpaid, remainingquantity, productionunit,
         productionunitsperpurchaseunit, costrecognitionmethod,
         deferredtotalcost, deferredremainingcost, createdby)
    VALUES (v_farm, v_item, (now() at time zone 'utc'), 10, 100, 1000,
            'Credit', 0, 10, 'Roll', 1, 'EXPENSE_WHEN_CONSUMED', 1000, 1000, 'ZZ tester')
    RETURNING waterrawmaterialpurchaseid INTO v_lot;

    INSERT INTO waterrawmaterialusage (farmid, waterrawmaterialitemid, useddate, quantityused, createdby)
    VALUES (v_farm, v_item, (now() at time zone 'utc'), 4, 'ZZ tester')
    RETURNING waterrawmaterialusageid INTO v_usage;

    PERFORM spwaterrawmaterialitem_consumebatches(v_farm, v_item, v_usage, 4);

    -- 277 should have recognised 400 of the 1000 onto the allocation.
    RAISE NOTICE 'E1. the lot has been drawn from expect   400.00  got %',
        (SELECT COALESCE(SUM(deferredcostdrawn), 0) FROM waterrawmaterialusagebatch
         WHERE waterrawmaterialusageid = v_usage);

    BEGIN
        PERFORM spwaterrawmaterialpurchase_update(
            p_waterrawmaterialpurchaseid => v_lot, p_farmid => v_farm,
            p_suppliername => NULL, p_purchasedate => (now() at time zone 'utc'),
            p_quantity => 10, p_unitcost => 999, p_paymentmethod => 'Credit', p_amountpaid => 0,
            p_receipturl => NULL, p_notes => 'ZZ 278 must be refused', p_supplierid => NULL,
            p_totalcost => 9990, p_watercashaccountid => NULL,
            p_productionunit => 'Roll', p_productionunitsperpurchaseunit => 1);
        RAISE NOTICE 'E2. editing a drawn lot      expect blocked  got ALLOWED -- WRONG';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'E2. editing a drawn lot      expect blocked  got blocked';
    END;

    -- The balance the guard protected is exactly where 277 left it.
    RAISE NOTICE 'E3. balance untouched by the attempt expect   600.00  got %',
        (SELECT deferredremainingcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot);

    -- =====================================================================
    -- F. THERE IS NO LOT-TO-LOT TRANSFER IN WATER.
    --
    -- Poultry's 265 carries deferred cost from ingredient lots into a produced
    -- feed lot. Water cannot: production writes finished goods to
    -- waterstocktransactions, and nothing but the purchase SP ever creates a lot.
    -- Asserted rather than merely asserted-in-a-comment, so that if water later
    -- grows a produced-lot path this stops being true and somebody has to decide
    -- what its deferred cost should be.
    -- =====================================================================
    RAISE NOTICE 'F1. only the purchase creates lots expect        1  got %',
        (SELECT COUNT(*) FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
         -- prokind 'f' = a plain function. pg_get_functiondef RAISES on an
         -- aggregate ("array_agg is an aggregate function"), so an unfiltered
         -- scan of pg_proc dies on the first one it meets.
         WHERE n.nspname = 'public' AND p.prokind = 'f'
           AND pg_get_functiondef(p.oid) LIKE '%INSERT INTO waterrawmaterialpurchases%');

    RAISE NOTICE '--- 278 guard checks done. ROLL BACK this transaction. ---';
END
$guard$;

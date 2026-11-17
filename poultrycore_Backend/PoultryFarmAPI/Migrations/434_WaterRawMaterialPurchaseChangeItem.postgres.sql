-- 434_WaterRawMaterialPurchaseChangeItem.postgres.sql
--
-- Lets an Inventory & Supply Purchase (/water-supply-purchases) be moved to a
-- different item when it was entered against the wrong one. Before this, the
-- item was fixed and the only fix was delete + re-enter, which also undoes and
-- re-creates the linked expense and cash entry.
--
-- spwaterrawmaterialpurchase_update gains p_waterrawmaterialitemid (DEFAULT
-- NULL = keep the item, so an API that does not send it behaves exactly as
-- before). When it names a different item:
--
--   * the purchase's production-level quantity comes OFF the old item's stock
--     and the (possibly re-entered) quantity goes ON the new item's stock;
--   * the linked expense's description is rewritten to name the new item.
--
-- Refused, with a message saying what to do, when:
--   1. a production batch has drawn from this purchase (already refused for
--      every edit -- unchanged);
--   2. the old item does not have the purchase's quantity left to give back
--      (it was used, so the item was not wrong);
--   3. the new item would be costed differently (expensed when bought vs when
--      used). The purchase's method is stamped at entry (275); switching it
--      would mean rebuilding the expense, not relabelling it.
--   4. the new item is not an active item on this farm.
--
-- The old signature is dropped first: adding a parameter to CREATE OR REPLACE
-- would leave both versions, and the API's named-argument call would then be
-- ambiguous.

BEGIN;

DROP FUNCTION IF EXISTS public.spwaterrawmaterialpurchase_update(
    integer, text, text, timestamp without time zone, numeric, numeric, text, numeric, text, text,
    integer, numeric, integer, text, numeric);

CREATE OR REPLACE FUNCTION public.spwaterrawmaterialpurchase_update(p_waterrawmaterialpurchaseid integer, p_farmid text, p_suppliername text DEFAULT NULL::text, p_purchasedate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_quantity numeric DEFAULT NULL::numeric, p_unitcost numeric DEFAULT NULL::numeric, p_paymentmethod text DEFAULT NULL::text, p_amountpaid numeric DEFAULT 0, p_receipturl text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_supplierid integer DEFAULT NULL::integer, p_totalcost numeric DEFAULT NULL::numeric, p_watercashaccountid integer DEFAULT NULL::integer, p_productionunit text DEFAULT NULL::text, p_productionunitsperpurchaseunit numeric DEFAULT NULL::numeric, p_waterrawmaterialitemid integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_totalcost       numeric := p_totalcost;
    v_suppliername    text    := p_suppliername;
    v_oldqty          numeric;
    v_itemid          integer;
    v_newitemid       integer;
    v_linkedexpenseid integer;
    v_oldmult         numeric;
    v_newmult         numeric;
    v_delta           numeric;
    v_oldprod         numeric;
    v_newprod         numeric;
    v_currentstock    numeric;
    v_msg1            text;
    v_updcashaccountid integer := NULL;
    v_stamped         text;
    v_newmethod       text;
    v_newitemname     text;
    v_purchasedate    timestamp;
BEGIN
    -- 426: a manual cost is not a purchase -- reverse it on Deferred costs.
    IF EXISTS (SELECT 1 FROM waterrawmaterialpurchases g WHERE g.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid
               AND g.farmid = p_farmid AND g.lotsource = 'ManualDeferredCost') THEN
        RAISE EXCEPTION 'This is a manual deferred cost, not a purchase. Reverse it on Deferred costs.' USING ERRCODE = 'P0001';
    END IF;
    -- A lot that an approved production batch has already drawn from can't be
    -- re-quantified underneath it - the draw records and remaining balances
    -- would stop agreeing. Reopen that batch first.
    IF EXISTS (SELECT 1 FROM waterrawmaterialusagebatch ub
               WHERE ub.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid) THEN
        RAISE EXCEPTION 'This purchase batch has already been drawn from by an approved production batch. Reopen that batch first.';
    END IF;

    IF (p_quantity <= 0) THEN
        RAISE EXCEPTION 'Quantity must be > 0.';
    END IF;
    IF (p_unitcost < 0) THEN
        RAISE EXCEPTION 'UnitCost cannot be negative.';
    END IF;

    IF (v_totalcost IS NULL OR v_totalcost <= 0) THEN
        v_totalcost := p_quantity::numeric(14,2) * p_unitcost;
    END IF;

    SELECT p.quantity, p.waterrawmaterialitemid, p.linkedwaterexpenseid,
           COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1),
           p.costrecognitionmethod, p.purchasedate
      INTO v_oldqty, v_itemid, v_linkedexpenseid, v_oldmult, v_stamped, v_purchasedate
    FROM waterrawmaterialpurchases p
    WHERE p.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid AND p.farmid = p_farmid
    FOR UPDATE;

    IF v_oldqty IS NULL THEN
        RAISE EXCEPTION 'Purchase % not found.', p_waterrawmaterialpurchaseid;
    END IF;

    v_newitemid := COALESCE(NULLIF(p_waterrawmaterialitemid, 0), v_itemid);

    -- Production-level quantities, before and after.
    v_newmult := COALESCE(NULLIF(p_productionunitsperpurchaseunit, 0), 1);
    v_oldprod := (v_oldqty * v_oldmult)::numeric(18,4);
    v_newprod := (p_quantity * v_newmult)::numeric(18,4);

    IF v_newitemid <> v_itemid THEN
        -- 434: moving the purchase to another item.
        SELECT mi.itemname::text INTO v_newitemname
        FROM   waterrawmaterialitems mi
        WHERE  mi.waterrawmaterialitemid = v_newitemid AND mi.farmid = p_farmid AND mi.isactive = TRUE;
        IF v_newitemname IS NULL THEN
            RAISE EXCEPTION 'Pick an active item on this company.' USING ERRCODE = 'P0001';
        END IF;

        -- Same cost treatment, or the expense would have to be rebuilt.
        SELECT r.method INTO v_newmethod
        FROM   fnwatercostrecognition_effective(
                   p_farmid, v_newitemid, NULL,
                   COALESCE(p_purchasedate, v_purchasedate, (now() at time zone 'utc'))::date) r;
        v_newmethod := COALESCE(v_newmethod, 'EXPENSE_WHEN_PURCHASED');
        IF v_newmethod IS DISTINCT FROM COALESCE(v_stamped, 'EXPENSE_WHEN_PURCHASED') THEN
            RAISE EXCEPTION '% is costed differently from the item on this purchase (one is expensed when bought, the other when used), so the purchase cannot simply be moved. Delete it and enter it again under %.',
                v_newitemname, v_newitemname USING ERRCODE = 'P0001';
        END IF;

        -- The old item must still hold what this purchase added.
        SELECT mi.currentquantity::numeric(18,4) INTO v_currentstock
        FROM   waterrawmaterialitems mi
        WHERE  mi.waterrawmaterialitemid = v_itemid AND mi.farmid = p_farmid
        FOR UPDATE;
        IF (COALESCE(v_currentstock, 0) - v_oldprod < 0) THEN
            v_msg1 := public.fnwaterrawmaterial_reducemessage(p_farmid, v_itemid, COALESCE(v_currentstock, 0), v_oldprod, 'move this purchase to another item');
            RAISE EXCEPTION '%', v_msg1 USING ERRCODE = 'P0001';
        END IF;
        v_delta := NULL;   -- not used on this path
    ELSE
        -- Stock delta measured in PRODUCTION units (new prod qty - old prod qty).
        v_delta := (v_newprod - v_oldprod)::numeric(18,4);

        IF (v_delta < 0) THEN
            SELECT mi.currentquantity::numeric(18,4) INTO v_currentstock
            FROM waterrawmaterialitems mi
            WHERE mi.waterrawmaterialitemid = v_itemid AND mi.farmid = p_farmid;

            IF (v_currentstock + v_delta < 0) THEN
                -- 428: say what to do.  Already below zero = the stock figure is
                -- wrong, not this purchase; otherwise usage has to be undone.
                v_msg1 := public.fnwaterrawmaterial_reducemessage(p_farmid, v_itemid, v_currentstock, -v_delta, 'reduce this purchase');
                RAISE EXCEPTION '%', v_msg1 USING ERRCODE = 'P0001';
            END IF;
        END IF;
    END IF;

    IF (p_supplierid IS NOT NULL AND (v_suppliername IS NULL OR v_suppliername = '')) THEN
        SELECT s.suppliername::text INTO v_suppliername FROM watersuppliers s
        WHERE s.watersupplierid = p_supplierid AND s.farmid = p_farmid;
    END IF;

    IF (p_watercashaccountid IS NOT NULL AND p_paymentmethod <> 'Credit') THEN
        SELECT ca.watercashaccountid INTO v_updcashaccountid FROM watercashaccounts ca
        WHERE ca.watercashaccountid = p_watercashaccountid AND ca.farmid = p_farmid AND ca.isactive = TRUE;
    END IF;

    UPDATE waterrawmaterialpurchases p
    SET waterrawmaterialitemid = v_newitemid,          -- 434
        suppliername  = v_suppliername,
        supplierid    = p_supplierid,
        purchasedate  = COALESCE(p_purchasedate, p.purchasedate),
        quantity      = p_quantity,
        unitcost      = p_unitcost,
        totalcost     = v_totalcost,
        paymentmethod = p_paymentmethod,
        amountpaid    = p_amountpaid,
        receipturl    = p_receipturl,
        notes         = p_notes,
        productionunit = p_productionunit,
        productionunitsperpurchaseunit = p_productionunitsperpurchaseunit,
        updatedat     = (now() at time zone 'utc'),
        remainingquantity = p_quantity,
        -- 278. The deferred balance follows the cost. Safe to rewrite outright
        -- rather than rescale, because the guard at the top of this function has
        -- already refused any lot that has been drawn from: nothing downstream
        -- can have recognised part of this balance yet, so there is no reported
        -- expense to contradict.
        --
        -- Keyed on the lot's OWN snapshot, never on today's setting. A company
        -- that switched deferral off last week must not have last month's
        -- deferred purchase silently zeroed by an unrelated edit to its notes.
        deferredtotalcost     = CASE WHEN fnwatercostrecognition_expenseatconsumption(p.costrecognitionmethod)
                                     THEN v_totalcost ELSE 0 END,
        deferredremainingcost = CASE WHEN fnwatercostrecognition_expenseatconsumption(p.costrecognitionmethod)
                                     THEN v_totalcost ELSE 0 END
    WHERE p.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid AND p.farmid = p_farmid;

    IF v_newitemid <> v_itemid THEN
        -- 434: the whole purchase moves -- off the old item, onto the new.
        UPDATE waterrawmaterialitems mi
        SET currentquantity = mi.currentquantity - v_oldprod,
            updatedat = (now() at time zone 'utc')
        WHERE mi.waterrawmaterialitemid = v_itemid AND mi.farmid = p_farmid;

        UPDATE waterrawmaterialitems mi
        SET currentquantity = mi.currentquantity + v_newprod,
            updatedat = (now() at time zone 'utc')
        WHERE mi.waterrawmaterialitemid = v_newitemid AND mi.farmid = p_farmid;
    ELSIF (v_delta <> 0) THEN
        UPDATE waterrawmaterialitems mi
        SET currentquantity = mi.currentquantity + v_delta,   -- production-level delta
            updatedat = (now() at time zone 'utc')
        WHERE mi.waterrawmaterialitemid = v_itemid AND mi.farmid = p_farmid;
    END IF;

    IF (v_linkedexpenseid IS NOT NULL) THEN
        UPDATE waterexpenses e
        SET amount     = p_amountpaid,
            paidto     = v_suppliername,
            supplierid = p_supplierid,
            expensedate = COALESCE(p_purchasedate, e.expensedate),
            watercashaccountid = CASE WHEN p_watercashaccountid IS NOT NULL THEN v_updcashaccountid ELSE e.watercashaccountid END,
            -- 434: name the item the purchase is now under, in the same words
            -- the purchase insert uses. Left alone when the item is unchanged.
            description = CASE WHEN v_newitemid <> v_itemid THEN
                concat('Raw material purchase: ', v_newitemname,
                       ' (', p_quantity::numeric(14,3)::text, ' units)',
                       CASE WHEN p_amountpaid < v_totalcost
                            THEN concat(' - part payment of ', p_amountpaid::numeric(14,2)::text,
                                        ' of ', v_totalcost::numeric(14,2)::text)
                            ELSE '' END)
                ELSE e.description END,
            updatedat  = (now() at time zone 'utc')
        WHERE e.waterexpenseid = v_linkedexpenseid AND e.farmid = p_farmid
          AND e.isdeleted = FALSE AND e.status IN ('Draft','Submitted','Approved');
    END IF;
END;
$function$;

DO $$
BEGIN
    IF (SELECT count(*) FROM pg_proc WHERE proname = 'spwaterrawmaterialpurchase_update') <> 1 THEN
        RAISE EXCEPTION '434: expected exactly one spwaterrawmaterialpurchase_update.';
    END IF;
    RAISE NOTICE '434_WaterRawMaterialPurchaseChangeItem: spwaterrawmaterialpurchase_update replaced.';
END
$$;

COMMIT;

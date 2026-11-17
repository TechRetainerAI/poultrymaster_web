-- =============================================================================
-- 430_WaterSourcedExpenseGuardAndStockMessages.postgres.sql   (requires 428)
--
-- Purpose
-- -------
-- A customer recorded a raw material purchase, made a mistake, and could not
-- correct it: "Cannot reduce quantity: only -539.1000 production units of this
-- item remain in stock. Reverse usages first."  The item's stock was already
-- below zero, so ANY reduction was refused, and the message pointed nowhere.
-- Trying to fix it she pressed the item's bin, which only deactivates the item.
--
-- On dev a second trap showed up: Water Expenses can Cancel the expense a raw
-- material purchase created (purchase 29 / expense 63).  The purchase keeps
-- its stock and supplier balance, the cost disappears, and nothing can
-- un-cancel it.  Payroll, employee-loan, capital-asset and internal-use
-- expenses have the same Cancel button.
--
-- What changes
-- ------------
--  1. fnwaterexpense_sourceblock(expense, farm, verb) -- the refusal message
--     when an expense belongs to a record that still exists, else NULL.
--  2. spwaterexpense_cancel / spwaterexpense_reject refuse such expenses and
--     name the page to undo them on.  An orphan (source row gone) can still be
--     cancelled, so a stranded expense is never stuck.
--  3. fnwaterrawmaterial_reducemessage(...) -- one message for "this would take
--     stock below zero": names the item, says whether stock is ALREADY below
--     zero (then Recalculate stock / check Usage history) or how much usage
--     has to be undone first.
--  4. spwaterrawmaterialpurchase_update / _delete use it.  Rules unchanged.
--
-- Bodies are the LIVE bodies (pg_get_functiondef, 2026-11-12) with only the
-- marked lines changed; signatures unchanged (CREATE OR REPLACE).
-- Deploy order: this migration, then the web app.  The API is unchanged.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- ------------------------------------------------ 1. source guard ----------
CREATE OR REPLACE FUNCTION public.fnwaterexpense_sourceblock(p_waterexpenseid integer, p_farmid text, p_verb text)
RETURNS text LANGUAGE plpgsql STABLE AS $f$
DECLARE
    v_type text; v_id integer; v_exists boolean := FALSE; v_what text; v_where text;
BEGIN
    SELECT e.sourcetype, e.sourceid INTO v_type, v_id
    FROM   waterexpenses e WHERE e.waterexpenseid = p_waterexpenseid AND e.farmid = p_farmid;
    IF v_type IS NULL OR v_id IS NULL THEN RETURN NULL; END IF;

    CASE v_type
    WHEN 'RawMaterialPurchase' THEN
        SELECT TRUE INTO v_exists FROM waterrawmaterialpurchases x
        WHERE x.waterrawmaterialpurchaseid = v_id AND x.farmid = p_farmid;
        v_what  := 'raw material purchase #' || v_id;
        v_where := 'Inventory & Supply Purchases (edit or delete the purchase there)';
    WHEN 'Payroll', 'PayrollEmployeeLoan' THEN
        SELECT TRUE INTO v_exists FROM waterpayrollruns x
        WHERE x.waterpayrollrunid = v_id AND x.farmid = p_farmid;
        v_what  := 'payroll run #' || v_id;
        v_where := 'Payroll (reverse the run there)';
    WHEN 'CapitalAsset' THEN
        SELECT TRUE INTO v_exists FROM watercapitalassets x
        WHERE x.watercapitalassetid = v_id AND x.farmid = p_farmid;
        v_what  := 'capital asset #' || v_id;
        v_where := 'Capital assets (correct or reverse the asset there)';
    WHEN 'WaterInternalUsage' THEN
        SELECT TRUE INTO v_exists FROM waterinternalusage x
        WHERE x.waterinternalusageid = v_id AND x.farmid = p_farmid;
        v_what  := 'internal use #' || v_id;
        v_where := 'Internal use (reverse it there)';
    ELSE
        RETURN NULL;   -- unknown source: keep the old behaviour
    END CASE;

    IF NOT COALESCE(v_exists, FALSE) THEN RETURN NULL; END IF;   -- orphan: allow
    RETURN 'This expense was created automatically by ' || v_what || ' and cannot be '
           || p_verb || ' here. Undo it on ' || v_where || ', which updates this expense too.';
END
$f$;

-- ------------------------------------------------ 3. stock message ---------
CREATE OR REPLACE FUNCTION public.fnwaterrawmaterial_reducemessage(p_farmid text, p_itemid integer, p_currentstock numeric, p_removing numeric, p_action text)
RETURNS text LANGUAGE sql STABLE AS $f$
    SELECT CASE
        WHEN p_currentstock < 0 THEN
            'Cannot ' || p_action || ': the stock of "' || COALESCE(i.itemname, 'this item')
            || '" is already below zero (' || trim_scale(round((p_currentstock)::numeric, 3))::text
            || ' ' || COALESCE(NULLIF(i.unitofmeasure, ''), 'units')
            || '), so the stock figure needs correcting first. Press Recalculate stock on Inventory & Supply Purchases, '
            || 'then check Usage history for usage recorded twice or in the wrong unit.'
        ELSE
            'Cannot ' || p_action || ': it would take ' || trim_scale(round((p_removing)::numeric, 3))::text
            || ' ' || COALESCE(NULLIF(i.unitofmeasure, ''), 'units') || ' of "' || COALESCE(i.itemname, 'this item')
            || '" out of stock, but only ' || trim_scale(round((p_currentstock)::numeric, 3))::text
            || ' remain. Reverse ' || trim_scale(round((p_removing - p_currentstock)::numeric, 3))::text
            || ' of usage first (Usage history), or press Recalculate stock if the stock figure looks wrong.'
        END
    FROM   (SELECT 1) one
    LEFT   JOIN waterrawmaterialitems i ON i.waterrawmaterialitemid = p_itemid AND i.farmid = p_farmid;
$f$;

-- ------------------------------------------------ 2. cancel / reject -------
CREATE OR REPLACE FUNCTION public.spwaterexpense_cancel(p_waterexpenseid integer, p_farmid text, p_cancelledby text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status        text;
    v_paymentmethod text;
    v_amount        numeric(14,2);
    v_cashaccountid integer;
    v_expensedate   timestamp;
    v_block         text;
BEGIN
    SELECT e.status, e.paymentmethod, e.amount, e.watercashaccountid, e.expensedate
    INTO   v_status, v_paymentmethod, v_amount, v_cashaccountid, v_expensedate
    FROM   waterexpenses e
    WHERE  e.waterexpenseid = p_waterexpenseid AND e.farmid = p_farmid
    LIMIT  1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Expense not found.';
    END IF;
    IF v_status = 'Cancelled' THEN
        RETURN;
    END IF;
    -- 430: an expense another record created is undone through that record,
    -- never here -- cancelling it alone strands the purchase / payroll / asset
    -- with no cost, and there is no un-cancel.
    v_block := public.fnwaterexpense_sourceblock(p_waterexpenseid, p_farmid, 'cancelled');
    IF v_block IS NOT NULL THEN
        RAISE EXCEPTION '%', v_block USING ERRCODE = 'P0001';
    END IF;

    IF v_status = 'Approved' AND v_paymentmethod <> 'Credit' AND v_cashaccountid IS NOT NULL THEN
        INSERT INTO watercashtransactions (
            farmid, watercashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, description, createdby, approvedby, approvedat
        )
        VALUES (
            p_farmid, v_cashaccountid, (now() at time zone 'utc'), 'Adjustment',
            'Expense', p_waterexpenseid, v_amount, 'Expense cancelled — reversal',
            p_cancelledby, p_cancelledby, (now() at time zone 'utc')
        );

        UPDATE watercashaccounts a
        SET    currentbalance = a.currentbalance + v_amount,
               updatedat      = (now() at time zone 'utc')
        WHERE  a.watercashaccountid = v_cashaccountid;
    END IF;

    UPDATE waterexpenses e
    SET    status = 'Cancelled',
           notes  = CASE WHEN p_reason IS NULL THEN e.notes
                         ELSE left(COALESCE(e.notes,'') || chr(10) || 'Cancelled: ' || p_reason, 1000) END,
           updatedat = (now() at time zone 'utc')
    WHERE  e.waterexpenseid = p_waterexpenseid AND e.farmid = p_farmid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spwaterexpense_reject(p_waterexpenseid integer, p_farmid text, p_approvedby text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_rc integer;
    v_block text;
BEGIN
    -- 430: same rule as cancel.
    v_block := public.fnwaterexpense_sourceblock(p_waterexpenseid, p_farmid, 'rejected');
    IF v_block IS NOT NULL THEN
        RAISE EXCEPTION '%', v_block USING ERRCODE = 'P0001';
    END IF;
    UPDATE waterexpenses e
    SET    status = 'Rejected',
           approvedby = p_approvedby,
           approvedat = (now() at time zone 'utc'),
           notes = CASE WHEN p_reason IS NULL THEN e.notes
                        ELSE left(COALESCE(e.notes,'') || chr(10) || 'Rejected: ' || p_reason, 1000) END,
           updatedat = (now() at time zone 'utc')
    WHERE  e.waterexpenseid = p_waterexpenseid
      AND  e.farmid = p_farmid
      AND  e.status IN ('Draft','Submitted');
    GET DIAGNOSTICS v_rc = ROW_COUNT;

    IF v_rc = 0 THEN
        RAISE EXCEPTION 'Expense cannot be rejected (not found or already finalized).';
    END IF;
END;
$function$;

-- ------------------------------------------------ 4. purchase edit / delete -
CREATE OR REPLACE FUNCTION public.spwaterrawmaterialpurchase_update(p_waterrawmaterialpurchaseid integer, p_farmid text, p_suppliername text DEFAULT NULL::text, p_purchasedate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_quantity numeric DEFAULT NULL::numeric, p_unitcost numeric DEFAULT NULL::numeric, p_paymentmethod text DEFAULT NULL::text, p_amountpaid numeric DEFAULT 0, p_receipturl text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_supplierid integer DEFAULT NULL::integer, p_totalcost numeric DEFAULT NULL::numeric, p_watercashaccountid integer DEFAULT NULL::integer, p_productionunit text DEFAULT NULL::text, p_productionunitsperpurchaseunit numeric DEFAULT NULL::numeric)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_totalcost       numeric := p_totalcost;
    v_suppliername    text    := p_suppliername;
    v_oldqty          numeric;
    v_itemid          integer;
    v_linkedexpenseid integer;
    v_oldmult         numeric;
    v_newmult         numeric;
    v_delta           numeric;
    v_currentstock    numeric;
    v_msg1            text;
    v_updcashaccountid integer := NULL;
BEGIN
    -- 428: a manual cost is not a purchase -- reverse it on Deferred costs.
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
           COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1)
      INTO v_oldqty, v_itemid, v_linkedexpenseid, v_oldmult
    FROM waterrawmaterialpurchases p
    WHERE p.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid AND p.farmid = p_farmid;

    IF v_oldqty IS NULL THEN
        RAISE EXCEPTION 'Purchase % not found.', p_waterrawmaterialpurchaseid;
    END IF;

    -- Stock delta measured in PRODUCTION units (new prod qty - old prod qty).
    v_newmult := COALESCE(NULLIF(p_productionunitsperpurchaseunit, 0), 1);
    v_delta   := ((p_quantity * v_newmult) - (v_oldqty * v_oldmult))::numeric(18,4);

    IF (v_delta < 0) THEN
        SELECT mi.currentquantity::numeric(18,4) INTO v_currentstock
        FROM waterrawmaterialitems mi
        WHERE mi.waterrawmaterialitemid = v_itemid AND mi.farmid = p_farmid;

        IF (v_currentstock + v_delta < 0) THEN
            -- 430: say what to do.  Already below zero = the stock figure is
            -- wrong, not this purchase; otherwise usage has to be undone.
            v_msg1 := public.fnwaterrawmaterial_reducemessage(p_farmid, v_itemid, v_currentstock, -v_delta, 'reduce this purchase');
            RAISE EXCEPTION '%', v_msg1 USING ERRCODE = 'P0001';
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
    SET suppliername  = v_suppliername,
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

    IF (v_delta <> 0) THEN
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
            updatedat  = (now() at time zone 'utc')
        WHERE e.waterexpenseid = v_linkedexpenseid AND e.farmid = p_farmid
          AND e.isdeleted = FALSE AND e.status IN ('Draft','Submitted','Approved');
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spwaterrawmaterialpurchase_delete(p_waterrawmaterialpurchaseid integer, p_farmid text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_qty             numeric;
    v_itemid          integer;
    v_linkedexpenseid integer;
    v_mult            numeric;
    v_prodqty         numeric;
    v_currentstock    numeric;
    v_msg2            text;
BEGIN
    -- 428: a manual cost is not a purchase -- reverse it on Deferred costs.
    IF EXISTS (SELECT 1 FROM waterrawmaterialpurchases g WHERE g.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid
               AND g.farmid = p_farmid AND g.lotsource = 'ManualDeferredCost') THEN
        RAISE EXCEPTION 'This is a manual deferred cost, not a purchase. Reverse it on Deferred costs.' USING ERRCODE = 'P0001';
    END IF;
    -- Deleting a drawn lot would strand its WaterRawMaterialUsageBatch rows
    -- against a purchase that no longer exists.
    IF EXISTS (SELECT 1 FROM waterrawmaterialusagebatch ub
               WHERE ub.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid) THEN
        RAISE EXCEPTION 'This purchase batch has already been drawn from by an approved production batch. Reopen that batch first.';
    END IF;

    SELECT p.quantity, p.waterrawmaterialitemid, p.linkedwaterexpenseid,
           COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1)
      INTO v_qty, v_itemid, v_linkedexpenseid, v_mult
    FROM waterrawmaterialpurchases p
    WHERE p.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid AND p.farmid = p_farmid;

    IF v_qty IS NULL THEN
        RAISE EXCEPTION 'Purchase % not found.', p_waterrawmaterialpurchaseid;
    END IF;

    v_prodqty := (v_qty * v_mult)::numeric(18,4);
    SELECT mi.currentquantity::numeric(18,4) INTO v_currentstock
    FROM waterrawmaterialitems mi
    WHERE mi.waterrawmaterialitemid = v_itemid AND mi.farmid = p_farmid;

    IF (v_currentstock < v_prodqty) THEN
        -- 430: say what to do (see fnwaterrawmaterial_reducemessage).
        v_msg2 := public.fnwaterrawmaterial_reducemessage(p_farmid, v_itemid, v_currentstock, v_prodqty, 'delete this purchase');
        RAISE EXCEPTION '%', v_msg2 USING ERRCODE = 'P0001';
    END IF;

    IF v_linkedexpenseid IS NOT NULL THEN
        PERFORM spwaterrawmaterialpurchase_cancellinkedexpense(
            p_waterrawmaterialpurchaseid => p_waterrawmaterialpurchaseid,
            p_farmid                     => p_farmid,
            p_cancelledby                => NULL);
    END IF;

    UPDATE waterrawmaterialitems mi
    SET currentquantity = mi.currentquantity - v_prodqty,   -- production-level qty
        updatedat       = (now() at time zone 'utc')
    WHERE mi.waterrawmaterialitemid = v_itemid AND mi.farmid = p_farmid;

    DELETE FROM waterrawmaterialpurchases p
    WHERE p.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid AND p.farmid = p_farmid;
END;
$function$;

COMMIT;

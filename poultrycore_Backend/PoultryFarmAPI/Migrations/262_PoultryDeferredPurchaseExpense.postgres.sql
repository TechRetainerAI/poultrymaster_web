-- =============================================================================
-- 262_PoultryDeferredPurchaseExpense.postgres.sql
--
-- Purpose
-- -------
-- 261 decided when an inventory cost should reach Profit & Loss and wrote the
-- decision onto each purchase. This file is the one that acts on it.
--
-- It changes exactly one thing: a purchase whose snapshot says
-- EXPENSE_WHEN_CONSUMED no longer writes a P&L expense. Everything else about
-- that purchase -- stock quantity, unit cost, remaining quantity, supplier
-- balance, cash account, cash flow, FIFO layers -- behaves precisely as it did
-- before, because none of that is what "expense" means.
--
-- SUPPRESSED IN TWO PLACES, NOT ONE
-- =================================
-- The thing that makes this file bigger than it looks. Poultry raw-material
-- recognition is CASH-BASIS today: the purchase writes an expense for
-- AMOUNTPAID, and every later supplier payment writes another (207's invariant
-- is that the linked expense rows sum to amountpaid).
--
-- So a deferred purchase has to be suppressed at BOTH ends:
--
--   sppoultryrawmaterialpurchase_insert    the expense at entry
--   sppoultrysupplierpayment_record        the expense at each later payment
--
-- Suppressing only the first would let a credit purchase expense itself in
-- instalments as the supplier was paid -- the deferral would appear to work on
-- the day it was entered and quietly fail for the rest of its life.
--
-- AND A THIRD PLACE THAT WOULD HAVE UNDONE IT
-- ===========================================
-- sppoultryrawmaterialpurchase_update carries a repair path from migration
-- 207: if a purchase has no linked expense, re-saving it creates one, because
-- historically that meant the link had been stripped by 153/157. On a deferred
-- purchase, "no linked expense" is CORRECT, and that path would have read it as
-- damage and helpfully restored the very expense the insert withheld. It is now
-- gated on the same predicate.
--
-- WHAT IS DELIBERATELY NOT CHANGED
-- ================================
--   * FlockBatch. Birds are not inventory items and have no cost-recognition
--     setting; the flock arm of the supplier payment is left exactly as it was.
--   * sppoultryrawmaterialpurchase_delete. It deletes linked expense rows; a
--     deferred purchase has none, so it already does the right thing and is not
--     reproduced here.
--   * sppoultryrawmaterialpurchasecash_sync. Cash is not expense. A deferred
--     purchase still moves money exactly when it is paid.
--   * Consumption. Nothing here recognises a deferred cost -- that is Phase 2.
--     Until then a deferred purchase holds its cost and never expenses it, which
--     is why the settings default to EXPENSE_WHEN_PURCHASED and the UI says what
--     the choice means.
--
-- EFFECT ON TODAY'S NUMBERS: none. Every existing purchase is snapshotted
-- EXPENSE_WHEN_PURCHASED by 261, the predicate returns true for all of them,
-- and all three functions take exactly the branch they took yesterday. The
-- check file proves that by driving a full purchase-pay-edit cycle both ways
-- and comparing the P&L either side.
--
-- Order: after 261.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The purchase: resolve the method once, stamp it, and gate the expense.
--
-- Reproduced from the LIVE definition. Validation, the total-cost fallback, the
-- amountpaid clamp, the 157 multiplier and the stock update are byte for byte
-- what they were.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialpurchase_insert(p_farmid text, p_poultryrawmaterialitemid integer, p_suppliername text DEFAULT NULL::text, p_supplierid integer DEFAULT NULL::integer, p_purchasedate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_quantity numeric DEFAULT NULL::numeric, p_unitcost numeric DEFAULT NULL::numeric, p_totalcost numeric DEFAULT NULL::numeric, p_productionunit text DEFAULT NULL::text, p_productionunitsperpurchaseunit numeric DEFAULT NULL::numeric, p_paymentmethod text DEFAULT NULL::text, p_amountpaid numeric DEFAULT 0, p_receipturl text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_totalcost  numeric(14,2) := p_totalcost;
    v_amountpaid numeric(14,2) := p_amountpaid;
    v_mult       numeric(18,8);
    v_newid      integer;
    v_itemname   text;
    v_unit       text;
    v_gid        uuid;
    v_method     text;
BEGIN
    IF (p_quantity <= 0) THEN RAISE EXCEPTION 'Quantity must be > 0.'; END IF;
    IF (p_unitcost < 0)  THEN RAISE EXCEPTION 'UnitCost cannot be negative.'; END IF;
    IF (v_totalcost IS NULL OR v_totalcost <= 0) THEN
        v_totalcost := (p_quantity::numeric(14,2)) * p_unitcost;
    END IF;
    IF (v_amountpaid IS NULL) THEN v_amountpaid := 0; END IF;
    IF (v_amountpaid > v_totalcost) THEN v_amountpaid := v_totalcost; END IF;

    v_mult := COALESCE(NULLIF(p_productionunitsperpurchaseunit, 0), 1);   -- 157

    SELECT i.itemname, i.unitofmeasure INTO v_itemname, v_unit
    FROM   poultryrawmaterialitems i
    WHERE  i.poultryrawmaterialitemid = p_poultryrawmaterialitemid AND i.farmid = p_farmid
    LIMIT 1;

    -- 262. Resolve ONCE, here, and stamp it on the row below. Asked again
    -- later it could give a different answer, and a purchase that changes its
    -- mind about how it was treated is how a closed month's P&L moves.
    SELECT r.method INTO v_method
    FROM   fnpoultrycostrecognition_effective(
               p_farmid, p_poultryrawmaterialitemid, NULL,
               COALESCE(p_purchasedate, (now() at time zone 'utc'))::date) r;
    v_method := COALESCE(v_method, 'EXPENSE_WHEN_PURCHASED');

    INSERT INTO poultryrawmaterialpurchases (
        farmid, poultryrawmaterialitemid, suppliername, supplierid, purchasedate,
        quantity, unitcost, totalcost, productionunit, productionunitsperpurchaseunit,
        paymentmethod, amountpaid, receipturl, notes, createdby, remainingquantity,
        costrecognitionmethod
    )
    VALUES (
        p_farmid, p_poultryrawmaterialitemid, p_suppliername, p_supplierid, COALESCE(p_purchasedate, (now() at time zone 'utc')),
        p_quantity, p_unitcost, v_totalcost, p_productionunit, p_productionunitsperpurchaseunit,
        p_paymentmethod, v_amountpaid, p_receipturl, p_notes, p_createdby, p_quantity,  -- RemainingQuantity in PURCHASE units
        v_method
    )
    RETURNING poultryrawmaterialpurchases.poultryrawmaterialpurchaseid INTO v_newid;

    UPDATE poultryrawmaterialitems i
    SET    currentquantity = i.currentquantity + (p_quantity * v_mult), updatedat = (now() at time zone 'utc')   -- 157: production units
    WHERE  i.poultryrawmaterialitemid = p_poultryrawmaterialitemid AND i.farmid = p_farmid;

    -- Linked expense (actual cash out). Guard on userid + uuid-castable farmid,
    -- so the purchase still succeeds when expense linking cannot run.   -- 130/207
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;

    -- 262. The one new condition. A deferred purchase writes NO expense: its
    -- cost is inventory value until Phase 2 recognises it on consumption. Cash,
    -- supplier balance and stock quantity below are all untouched -- paying for
    -- something and expensing it are different events.
    IF (v_gid IS NOT NULL AND p_createdby IS NOT NULL AND v_amountpaid > 0
        AND fnpoultrycostrecognition_expenseatpurchase(v_method)) THEN
        INSERT INTO expense (expensedate, category, description, amount, paymentmethod, supplier, flockid, createddate, userid, farmid, sourcetype, sourceid)
        VALUES (COALESCE(p_purchasedate, (now() at time zone 'utc')), 'Raw Materials / Inventory Purchase',
                'Raw material purchase: ' || COALESCE(v_itemname, 'item') || ' (' || p_quantity::text || ' ' || COALESCE(v_unit, '') || ')',
                v_amountpaid, COALESCE(p_paymentmethod, 'Cash'), p_suppliername, NULL, (now() at time zone 'utc'), p_createdby, v_gid,
                'PoultryRawMaterialPurchase', v_newid);
    END IF;

    RETURN v_newid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. The edit: do not "repair" an expense that was never meant to exist.
--
-- Reproduced from the LIVE definition. The quantity guards, the already-drawn
-- check, the stock delta and the expense-rebalancing arithmetic are unchanged;
-- the arithmetic simply no longer runs for a deferred purchase.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialpurchase_update(p_poultryrawmaterialpurchaseid integer, p_farmid text, p_suppliername text DEFAULT NULL::text, p_supplierid integer DEFAULT NULL::integer, p_purchasedate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_quantity numeric DEFAULT NULL::numeric, p_unitcost numeric DEFAULT NULL::numeric, p_totalcost numeric DEFAULT NULL::numeric, p_productionunit text DEFAULT NULL::text, p_productionunitsperpurchaseunit numeric DEFAULT NULL::numeric, p_paymentmethod text DEFAULT NULL::text, p_amountpaid numeric DEFAULT 0, p_receipturl text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_totalcost    numeric(14,2) := p_totalcost;
    v_oldqty       numeric(14,3);
    v_oldremaining numeric(14,3);
    v_itemid       integer;
    v_oldmult      numeric(18,8);
    v_alreadydrawn numeric(14,3);
    v_newmult      numeric(18,8);
    v_deltaprod    numeric(18,4);
    v_currentstock numeric(18,4);
    v_msg          text;
    v_msg2         text;
    v_gid          uuid;
    v_firstid      integer;
    v_others       numeric(14,2);
    v_target       numeric(14,2);
    v_createdby    text;
    v_itemname     text;
    v_unit         text;    v_method      text;

BEGIN
    IF (p_quantity <= 0) THEN RAISE EXCEPTION 'Quantity must be > 0.'; END IF;
    IF (p_unitcost < 0)  THEN RAISE EXCEPTION 'UnitCost cannot be negative.'; END IF;
    IF (v_totalcost IS NULL OR v_totalcost <= 0) THEN
        v_totalcost := (p_quantity::numeric(14,2)) * p_unitcost;
    END IF;

    SELECT pu.quantity, pu.remainingquantity, pu.poultryrawmaterialitemid,
           COALESCE(NULLIF(pu.productionunitsperpurchaseunit, 0), 1), pu.createdby
    INTO   v_oldqty, v_oldremaining, v_itemid, v_oldmult, v_createdby
    FROM   poultryrawmaterialpurchases pu
    WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid AND pu.farmid = p_farmid
    LIMIT 1;

    IF v_oldqty IS NULL THEN
        RAISE EXCEPTION 'Purchase % not found.', p_poultryrawmaterialpurchaseid;
    END IF;

    -- Cannot reduce the (purchase-unit) quantity below what's already been drawn.
    v_alreadydrawn := v_oldqty - COALESCE(v_oldremaining, v_oldqty);
    IF (p_quantity < v_alreadydrawn) THEN
        v_msg2 := 'Cannot reduce quantity below ' || v_alreadydrawn::text || ' — that much has already been used from this batch.';
        RAISE EXCEPTION '%', v_msg2;
    END IF;

    -- Stock delta in PRODUCTION units (157).
    v_newmult := COALESCE(NULLIF(p_productionunitsperpurchaseunit, 0), 1);
    v_deltaprod := ((p_quantity * v_newmult) - (v_oldqty * v_oldmult))::numeric(18,4);
    IF (v_deltaprod < 0) THEN
        SELECT i.currentquantity INTO v_currentstock
        FROM   poultryrawmaterialitems i
        WHERE  i.poultryrawmaterialitemid = v_itemid AND i.farmid = p_farmid;
        IF (v_currentstock + v_deltaprod < 0) THEN
            v_msg := 'Cannot reduce quantity: only ' || v_currentstock::text || ' production units remain in stock.';
            RAISE EXCEPTION '%', v_msg;
        END IF;
    END IF;

    UPDATE poultryrawmaterialpurchases pu
    SET    suppliername = p_suppliername, supplierid = p_supplierid,
           purchasedate = COALESCE(p_purchasedate, pu.purchasedate),
           quantity = p_quantity, unitcost = p_unitcost, totalcost = v_totalcost,
           productionunit = p_productionunit, productionunitsperpurchaseunit = p_productionunitsperpurchaseunit,
           paymentmethod = p_paymentmethod, amountpaid = p_amountpaid,
           receipturl = p_receipturl, notes = p_notes, updatedat = (now() at time zone 'utc'),
           remainingquantity = p_quantity - v_alreadydrawn   -- PURCHASE units, unchanged
    WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid AND pu.farmid = p_farmid;

    IF (v_deltaprod <> 0) THEN
        UPDATE poultryrawmaterialitems i
        SET    currentquantity = i.currentquantity + v_deltaprod, updatedat = (now() at time zone 'utc')   -- 157: production-level delta
        WHERE  i.poultryrawmaterialitemid = v_itemid AND i.farmid = p_farmid;
    END IF;

    -- Keep the linked expenses summing to amountpaid. The earliest row is the
    -- purchase's own expense; any later ones are PayBalance payments and are
    -- left alone, so the initial row absorbs the difference.            -- 130/207
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;

    -- 262. A deferred purchase has no linked expense and must not grow one.
    -- Without this, editing such a purchase would run the repair path below,
    -- find no expense row, decide the books were broken, and create the very
    -- expense the insert deliberately withheld.
    SELECT pu.costrecognitionmethod INTO v_method
    FROM   poultryrawmaterialpurchases pu
    WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid
      AND  pu.farmid = p_farmid;

    IF (v_gid IS NOT NULL AND fnpoultrycostrecognition_expenseatpurchase(v_method)) THEN
        SELECT min(e.expenseid) INTO v_firstid
        FROM   expense e
        WHERE  e.farmid = v_gid AND e.sourcetype = 'PoultryRawMaterialPurchase'
               AND e.sourceid = p_poultryrawmaterialpurchaseid;

        SELECT COALESCE(sum(e.amount), 0) INTO v_others
        FROM   expense e
        WHERE  e.farmid = v_gid AND e.sourcetype = 'PoultryRawMaterialPurchase'
               AND e.sourceid = p_poultryrawmaterialpurchaseid
               AND v_firstid IS NOT NULL AND e.expenseid <> v_firstid;

        v_target := GREATEST(COALESCE(p_amountpaid, 0) - v_others, 0)::numeric(14,2);

        IF (v_firstid IS NOT NULL) THEN
            UPDATE expense e
            SET    amount = v_target,
                   supplier = p_suppliername,
                   paymentmethod = COALESCE(p_paymentmethod, e.paymentmethod)
            WHERE  e.expenseid = v_firstid;
        ELSIF (v_target > 0 AND v_createdby IS NOT NULL) THEN
            -- No expense yet: a purchase recorded while 153/157 had the link
            -- stripped. Re-saving it repairs the books.
            SELECT i.itemname, i.unitofmeasure INTO v_itemname, v_unit
            FROM   poultryrawmaterialitems i
            WHERE  i.poultryrawmaterialitemid = v_itemid AND i.farmid = p_farmid
            LIMIT 1;

            INSERT INTO expense (expensedate, category, description, amount, paymentmethod, supplier, flockid, createddate, userid, farmid, sourcetype, sourceid)
            VALUES (COALESCE(p_purchasedate, (now() at time zone 'utc')), 'Raw Materials / Inventory Purchase',
                    'Raw material purchase: ' || COALESCE(v_itemname, 'item') || ' (' || p_quantity::text || ' ' || COALESCE(v_unit, '') || ')',
                    v_target, COALESCE(p_paymentmethod, 'Cash'), p_suppliername, NULL, (now() at time zone 'utc'), v_createdby, v_gid,
                    'PoultryRawMaterialPurchase', p_poultryrawmaterialpurchaseid);
        END IF;
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. The supplier payment: the other half of the deferral.
--
-- Reproduced from the LIVE definition. The allocation rows, the balance
-- arithmetic, the cash re-sync and the single CashOut are untouched. Only the
-- condition on the linked expense insert has changed.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrysupplierpayment_record(p_farmid text, p_supplierid integer, p_amount numeric, p_allocations jsonb, p_paymentmethod text DEFAULT NULL::text, p_paymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_cashaccountid integer DEFAULT NULL::integer, p_reference text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_sourcetype text DEFAULT 'SupplierBalances'::text, p_createdby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_paymentid integer;
    v_date      timestamp := COALESCE(p_paymentdate, (now() at time zone 'utc'));
    v_allocated numeric(14,2);
    v_count     integer;
    v_distinct  integer;
    v_minamount numeric(14,2);
    v_missing   integer;
    v_row       record;
    v_before    numeric(14,2);
    v_gid       uuid;
    v_allowneg  boolean;
    v_curbal    numeric(14,2);
    v_name      text;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than 0.';
    END IF;
    -- A NULL supplier is allowed (see the table comment) but a WRONG one is not.
    IF p_supplierid IS NOT NULL THEN
        SELECT s.name INTO v_name FROM supplier s
        WHERE  s.supplierid = p_supplierid AND s.farmid = p_farmid LIMIT 1;
        IF v_name IS NULL THEN
            RAISE EXCEPTION 'Supplier does not belong to this company.';
        END IF;
    END IF;

    IF p_cashaccountid IS NOT NULL THEN
        SELECT a.allownegativebalance, a.currentbalance INTO v_allowneg, v_curbal
        FROM   poultrycashaccounts a
        WHERE  a.poultrycashaccountid = p_cashaccountid AND a.farmid = p_farmid LIMIT 1;
        IF v_allowneg IS NULL THEN
            RAISE EXCEPTION 'Cash account does not belong to this company.';
        END IF;
        IF NOT v_allowneg AND (v_curbal - p_amount) < 0 THEN
            RAISE EXCEPTION 'This payment would overdraw the cash account (balance %, payment %).',
                  v_curbal, p_amount::numeric(14,2);
        END IF;
    END IF;

    SELECT COUNT(*), COUNT(DISTINCT (a.documenttype, a.documentid)),
           COALESCE(SUM(a.amount), 0), COALESCE(MIN(a.amount), 0)
    INTO   v_count, v_distinct, v_allocated, v_minamount
    FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
           AS a(documenttype text, documentid integer, amount numeric)
    WHERE  a.documentid IS NOT NULL AND COALESCE(a.amount, 0) <> 0;

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Select at least one item to apply this payment to.';
    END IF;
    IF v_distinct <> v_count THEN
        RAISE EXCEPTION 'The same item appears more than once in this payment.';
    END IF;
    IF v_minamount <= 0 THEN
        RAISE EXCEPTION 'Each allocation must be greater than 0.';
    END IF;
    IF v_allocated::numeric(14,2) <> p_amount::numeric(14,2) THEN
        RAISE EXCEPTION 'Allocated total (%) must equal the payment amount (%).',
              v_allocated::numeric(14,2), p_amount::numeric(14,2);
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
               AS a(documenttype text, documentid integer, amount numeric)
               WHERE COALESCE(a.documenttype, '') NOT IN ('RawMaterialPurchase', 'FlockBatch', 'Expense')) THEN
        RAISE EXCEPTION 'Unknown document type. Expected RawMaterialPurchase, FlockBatch or Expense.';
    END IF;

    INSERT INTO poultrysupplierpayments
        (farmid, supplierid, paymentdate, totalamount, paymentmethod, poultrycashaccountid,
         referenceno, notes, sourcetype, status, createdby, createdat)
    VALUES
        (p_farmid, p_supplierid, v_date, p_amount, p_paymentmethod, p_cashaccountid,
         p_reference, p_notes, COALESCE(p_sourcetype, 'SupplierBalances'), 'Posted',
         p_createdby, (now() at time zone 'utc'))
    RETURNING poultrysupplierpaymentid INTO v_paymentid;

    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;

    FOR v_row IN
        SELECT a.documenttype, a.documentid, a.amount::numeric(14,2) AS amount,
               d.totalcost, d.amountpaid, d.balance, d.docdate, d.label, d.cashaccountid
        FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
               AS a(documenttype text, documentid integer, amount numeric)
        JOIN   fnpoultrypayables(p_farmid) d
               ON d.documenttype = a.documenttype AND d.documentid = a.documentid
        WHERE  a.documentid IS NOT NULL AND COALESCE(a.amount, 0) <> 0
          -- IS NOT DISTINCT FROM so a no-supplier payment matches a no-supplier
          -- document; a plain = would silently drop every one of them.
          AND  d.supplierid IS NOT DISTINCT FROM p_supplierid
        ORDER  BY d.docdate, d.documentid
    LOOP
        v_before := GREATEST(COALESCE(v_row.balance, 0), 0);

        IF v_before <= 0 THEN
            RAISE EXCEPTION '% #% is already fully paid.',
                  v_row.documenttype, v_row.documentid;
        END IF;
        IF v_row.amount > v_before THEN
            RAISE EXCEPTION 'Cannot apply % to % #% -- its balance is only %.',
                  v_row.amount, v_row.documenttype, v_row.documentid, v_before;
        END IF;

        IF v_row.documenttype = 'RawMaterialPurchase' THEN
            UPDATE poultryrawmaterialpurchases pu
            SET    amountpaid = pu.amountpaid + v_row.amount,
                   updatedat = (now() at time zone 'utc')
            WHERE  pu.poultryrawmaterialpurchaseid = v_row.documentid AND pu.farmid = p_farmid;
        ELSIF v_row.documenttype = 'FlockBatch' THEN
            UPDATE mainflockbatch b
            SET    amountpaid = b.amountpaid + v_row.amount
            WHERE  b.batchid = v_row.documentid AND b.farmid = p_farmid;
        ELSE
            -- amountpaid is NULL on a fully paid expense, so resolve before adding
            -- or the sum restarts from zero and the row goes backwards.
            UPDATE expense e
            SET    amountpaid = LEAST(COALESCE(e.amountpaid, e.amount) + v_row.amount, e.amount)
            WHERE  e.expenseid = v_row.documentid
              AND  lower(e.farmid::text) = lower(p_farmid);
        END IF;

        INSERT INTO supplierpaymentallocation
            (farmid, module, paymentid, documenttype, documentid, amountapplied,
             documentbalancebefore, documentbalanceafter, status, createdby, createdat)
        VALUES
            (p_farmid, 'poultry', v_paymentid, v_row.documenttype, v_row.documentid, v_row.amount,
             v_before, v_before - v_row.amount, 'Posted', p_createdby, v_date);

        -- Keep migration 207's invariant: a purchase's linked expense rows sum to
        -- its amountpaid. Guarded exactly the way the pay-balance functions guard
        -- it, so a farm whose id will not cast to uuid still gets its payment.
        --
        -- Expenses are excluded: the expense being paid IS the cost, already in
        -- the P&L since the day it was entered. See the header.
        --
        -- 262. And the second half of the deferral. Because recognition here is
        -- CASH-BASIS, suppressing the expense on the purchase alone would not
        -- be enough: paying the supplier later would book the cost anyway, and
        -- a deferred purchase would quietly expense itself in instalments.
        --
        -- FlockBatch is untouched. Birds are not inventory items and have no
        -- cost-recognition setting; only RawMaterialPurchase can be deferred.
        IF (v_row.documenttype IN ('RawMaterialPurchase', 'FlockBatch')
            AND v_gid IS NOT NULL AND p_createdby IS NOT NULL
            AND (v_row.documenttype <> 'RawMaterialPurchase'
                 OR fnpoultrycostrecognition_expenseatpurchase(
                        (SELECT pu.costrecognitionmethod
                         FROM   poultryrawmaterialpurchases pu
                         WHERE  pu.poultryrawmaterialpurchaseid = v_row.documentid
                           AND  pu.farmid = p_farmid)))) THEN
            INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                                 supplier, flockid, createddate, userid, farmid, sourcetype, sourceid)
            VALUES (v_date,
                    CASE WHEN v_row.documenttype = 'FlockBatch'
                         THEN 'Flock / Bird Purchase'
                         ELSE 'Raw Materials / Inventory Purchase' END,
                    'Supplier payment #' || v_paymentid::text || ' against ' ||
                        v_row.documenttype || ' #' || v_row.documentid::text || ': ' || v_row.label,
                    v_row.amount, COALESCE(p_paymentmethod, 'Cash'), v_name, NULL,
                    (now() at time zone 'utc'), p_createdby, v_gid,
                    CASE WHEN v_row.documenttype = 'FlockBatch'
                         THEN 'MainFlockBatch' ELSE 'PoultryRawMaterialPurchase' END,
                    v_row.documentid);
        END IF;

        -- Re-sync the document's own cash line. It now excludes what this
        -- allocation covered, so this call REMOVES that portion from the
        -- document's account -- the payment's single CashOut below is where the
        -- money actually leaves.
        IF v_row.documenttype = 'RawMaterialPurchase' THEN
            PERFORM sppoultryrawmaterialpurchasecash_sync(
                p_farmid, v_row.documentid, v_row.cashaccountid, FALSE, p_createdby);
        ELSIF v_row.documenttype = 'Expense' THEN
            PERFORM sppoultryexpensecash_resync(p_farmid, v_row.documentid, p_createdby);
        END IF;
    END LOOP;

    -- Every id must have matched a document belonging to this supplier.
    SELECT v_count - COUNT(*) INTO v_missing
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.paymentid = v_paymentid;
    IF v_missing <> 0 THEN
        RAISE EXCEPTION '% of the selected items do not belong to this supplier or company.',
              v_missing;
    END IF;

    PERFORM sppoultrysupplierpaymentcash_sync(p_farmid, v_paymentid, p_createdby);

    RETURN v_paymentid;
END;
$function$;

COMMIT;

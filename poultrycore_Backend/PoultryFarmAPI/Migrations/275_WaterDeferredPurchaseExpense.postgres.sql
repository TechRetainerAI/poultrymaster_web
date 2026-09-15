-- =============================================================================
-- 275_WaterDeferredPurchaseExpense.postgres.sql
--
-- Purpose
-- -------
-- The water mirror of 262. 274 decided WHEN an inventory cost should reach
-- Profit & Loss and gave us the resolver; this file is the one that acts on it.
--
-- It changes exactly one thing: a purchase whose snapshot says
-- EXPENSE_WHEN_CONSUMED no longer writes a P&L expense. Everything else about
-- that purchase -- stock quantity, unit cost, remaining quantity, supplier
-- balance, cash account, cash flow, lot ordering -- behaves precisely as it did
-- before, because none of that is what "expense" means. Paying for something
-- and expensing it are different events, and only the second one moves here.
--
-- WHY THIS COULD NOT BE WRITTEN UNTIL NOW
-- =======================================
-- Stated once, because it shaped the whole water workstream. Poultry's chain
-- (261-268) could rewrite its raw-material bodies because migration 207 had
-- restored the live Postgres definitions INTO THE REPO first; every later
-- migration copied from a definition it could read. Water's live bodies were
-- ported outside version control, and the repo held spWaterRawMaterialPurchase_*
-- only as pre-migration T-SQL (044, 090, 091, 116, 146, 147, 190). Rewriting
-- from that would have silently dropped whatever the live port actually does.
--
-- The two functions below are therefore reproduced from a dump of the LIVE
-- definitions taken before this file was written. Everything outside the blocks
-- marked "-- 275." is byte-for-byte what was running.
--
-- SUPPRESSED IN TWO PLACES, NOT ONE
-- =================================
-- Water raw-material recognition is CASH-BASIS today (090): the purchase writes
-- an expense for AMOUNTPAID, not for totalcost, and every later supplier payment
-- writes another. A 100,000 credit purchase creates NO expense at entry and
-- expenses itself in instalments as the supplier is paid.
--
-- So a deferred purchase has to be suppressed at BOTH ends:
--
--   spwaterrawmaterialpurchase_insert    the expense at entry
--   spwatersupplierpaymentcash_sync      the expense at each later payment
--
-- Suppressing only the first would let a credit purchase expense itself in
-- instalments -- the deferral would appear to work on the day it was entered and
-- quietly fail for the rest of its life.
--
-- WHERE WATER DIFFERS FROM POULTRY, AND WHY IT MATTERS HERE
-- =========================================================
-- 1. THE PAYMENT EXPENSE IS AGGREGATED. Poultry writes one expense per payment
--    allocation. Water's spwatersupplierpaymentcash_sync sums EVERY non-Expense
--    allocation on the payment into a single `v_purchase` and books one expense
--    row for the lot of them. One payment can therefore settle a deferred
--    purchase and a normal one at the same time, and an all-or-nothing gate
--    would be wrong in both directions -- it would either expense the deferred
--    cost or swallow the normal one.
--
--    So the split below is by AMOUNT, not by branch: the expense is booked for
--    the non-deferred portion only, and the cash still moves for the whole
--    payment. When every allocation on a payment is deferred the portion is
--    zero and no expense row is written at all.
--
-- 2. THE EDIT PATH NEEDS NOTHING. Poultry's 262 had to gate a third function:
--    sppoultryrawmaterialpurchase_update carried a repair path from 207 that
--    re-created a missing linked expense, and on a deferred purchase "missing"
--    is CORRECT -- it would have helpfully restored the very expense the insert
--    withheld. Water's spwaterrawmaterialpurchase_update has no such path: it
--    only UPDATEs an expense that already exists (IF v_linkedexpenseid IS NOT
--    NULL). A deferred purchase has none, so it already does the right thing and
--    is deliberately not reproduced here.
--
-- WHAT IS DELIBERATELY NOT CHANGED
-- ================================
--   * spwaterrawmaterialpurchase_delete. It cancels linked expense rows; a
--     deferred purchase has none, so it is already correct.
--   * spwatersupplierpayment_reverse / _unsync. Reversing a payment that wrote
--     no expense has no expense to reverse. The cash arm is untouched either way.
--   * The bill portion of a payment (documenttype = 'Expense'). Those are
--     already-booked expenses being settled, not inventory cost.
--   * Consumption. Nothing here RECOGNISES a deferred cost -- that is 277-279.
--     Until then a deferred purchase would hold its cost and never expense it,
--     which is exactly why the interlock below stays shut.
--
-- THE INTERLOCK STAYS SHUT
-- ========================
-- fnwatercostrecognition_deferralready() still returns FALSE after this file,
-- and both settings writers still refuse EXPENSE_WHEN_CONSUMED because of it.
-- That is deliberate and it is not an oversight to be tidied up here:
--
--   279 (consumption recognition) is the migration that flips it to TRUE, and
--   NOTHING ELSE MAY. Flipping it once the purchase side is right but before
--   consumption recognises the held cost would strand every deferred cost in
--   inventory forever; flipping it before this file would double-count.
--
-- So this migration is behaviourally INERT on the day it lands: the resolver
-- cannot return EXPENSE_WHEN_CONSUMED for any company, every purchase is
-- stamped EXPENSE_WHEN_PURCHASED, and both functions take exactly the branch
-- they took yesterday. That is what makes it safe to ship on its own, and the
-- check file proves it by driving a purchase-pay cycle both ways -- lifting the
-- interlock inside its own rolled-back transaction to exercise the new branch.
--
-- EFFECT ON TODAY'S NUMBERS: none.
--
-- Order: after 274. Before 277.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Refuse to run out of order.
--
-- Both functions below call 274's resolvers. Without them this file would
-- install two bodies that raise on every purchase, which is a worse failure
-- than not being applied at all.
-- -----------------------------------------------------------------------------
DO $guard$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN   pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname = 'fnwatercostrecognition_effective'
    ) THEN
        RAISE EXCEPTION '275 requires 274 (fnwatercostrecognition_effective is missing).';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE  table_name = 'waterrawmaterialpurchases'
          AND  column_name = 'costrecognitionmethod'
    ) THEN
        RAISE EXCEPTION '275 requires 274 (waterrawmaterialpurchases.costrecognitionmethod is missing).';
    END IF;
END
$guard$;

-- -----------------------------------------------------------------------------
-- 1. The purchase: resolve the method once, stamp it, and gate the expense.
--
-- Reproduced from the LIVE definition. The validation, the total-cost fallback,
-- the amountpaid clamp, the production-unit multiplier (146/147), the supplier
-- name lookup, the category ensure, the cash-account fallback, the payment
-- method coercion, the stock update and the cash transaction are unchanged.
--
-- Two additions, both marked: v_method is resolved and stamped on the row, and
-- the expense block gains one condition.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterrawmaterialpurchase_insert(p_farmid text, p_waterrawmaterialitemid integer, p_suppliername text DEFAULT NULL::text, p_purchasedate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_quantity numeric DEFAULT NULL::numeric, p_unitcost numeric DEFAULT NULL::numeric, p_paymentmethod text DEFAULT NULL::text, p_amountpaid numeric DEFAULT 0, p_receipturl text DEFAULT NULL::text, p_receivedbystaffid integer DEFAULT NULL::integer, p_notes text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text, p_supplierid integer DEFAULT NULL::integer, p_totalcost numeric DEFAULT NULL::numeric, p_watercashaccountid integer DEFAULT NULL::integer, p_productionunit text DEFAULT NULL::text, p_productionunitsperpurchaseunit numeric DEFAULT NULL::numeric)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_totalcost     numeric := p_totalcost;
    v_amountpaid    numeric := p_amountpaid;
    v_suppliername  text    := p_suppliername;
    v_prodqty       numeric;
    v_itemname      text;
    v_catid         integer;
    v_cashaccountid integer;
    v_effectivepaymentmethod text;
    v_newid         integer;
    v_expenseid     integer := NULL;
    v_method        text;            -- 275
BEGIN
    IF (p_quantity <= 0) THEN
        RAISE EXCEPTION 'Quantity must be > 0.';
    END IF;
    IF (p_unitcost < 0) THEN
        RAISE EXCEPTION 'UnitCost cannot be negative.';
    END IF;

    IF (v_totalcost IS NULL OR v_totalcost <= 0) THEN
        v_totalcost := p_quantity::numeric(14,2) * p_unitcost;
    END IF;

    IF v_amountpaid IS NULL THEN
        v_amountpaid := 0;
    END IF;
    IF v_amountpaid > v_totalcost THEN
        v_amountpaid := v_totalcost;
    END IF;

    -- Production-level quantity added to stock.
    v_prodqty := (p_quantity * COALESCE(NULLIF(p_productionunitsperpurchaseunit, 0), 1))::numeric(18,4);

    -- A new purchase is a full lot. RemainingQuantity is in PURCHASE units,
    -- matching Quantity, and is what production draws against.

    SELECT mi.itemname::text INTO v_itemname FROM waterrawmaterialitems mi
    WHERE mi.waterrawmaterialitemid = p_waterrawmaterialitemid AND mi.farmid = p_farmid;

    IF (p_supplierid IS NOT NULL AND (v_suppliername IS NULL OR v_suppliername = '')) THEN
        SELECT s.suppliername::text INTO v_suppliername FROM watersuppliers s
        WHERE s.watersupplierid = p_supplierid AND s.farmid = p_farmid;
    END IF;

    -- 275. Resolve ONCE, here, and stamp it on the row below. Asked again later
    -- it could give a different answer, and a purchase that changes its mind
    -- about how it was treated is how a closed month's P&L moves.
    SELECT r.method INTO v_method
    FROM   fnwatercostrecognition_effective(
               p_farmid, p_waterrawmaterialitemid, NULL,
               COALESCE(p_purchasedate, (now() at time zone 'utc'))::date) r;
    v_method := COALESCE(v_method, 'EXPENSE_WHEN_PURCHASED');

    PERFORM spwaterexpensecategory_ensurerawmaterialpurchase(p_farmid);

    SELECT c.waterexpensecategoryid INTO v_catid FROM waterexpensecategories c
    WHERE c.farmid = p_farmid AND c.name = 'Raw Materials / Inventory Purchase';

    IF p_watercashaccountid IS NOT NULL THEN
        SELECT ca.watercashaccountid INTO v_cashaccountid FROM watercashaccounts ca
        WHERE ca.watercashaccountid = p_watercashaccountid AND ca.farmid = p_farmid AND ca.isactive = TRUE;
    END IF;
    IF v_cashaccountid IS NULL THEN
        SELECT ca.watercashaccountid INTO v_cashaccountid FROM watercashaccounts ca
        WHERE ca.farmid = p_farmid AND ca.isactive = TRUE ORDER BY ca.watercashaccountid LIMIT 1;
    END IF;

    v_effectivepaymentmethod :=
        CASE WHEN p_paymentmethod IN ('Cash','MoMo','Bank','Card','Credit','Mixed') THEN p_paymentmethod
             WHEN v_cashaccountid IS NULL THEN 'Credit' ELSE 'Cash' END;

    INSERT INTO waterrawmaterialpurchases (
        farmid, waterrawmaterialitemid, suppliername, purchasedate, quantity, unitcost, totalcost,
        paymentmethod, amountpaid, receipturl, receivedbystaffid, notes, createdby, supplierid,
        productionunit, productionunitsperpurchaseunit, remainingquantity,
        costrecognitionmethod                                              -- 275
    )
    VALUES (
        p_farmid, p_waterrawmaterialitemid, v_suppliername,
        COALESCE(p_purchasedate, (now() at time zone 'utc')), p_quantity, p_unitcost, v_totalcost,
        v_effectivepaymentmethod, v_amountpaid, p_receipturl, p_receivedbystaffid, p_notes, p_createdby, p_supplierid,
        p_productionunit, p_productionunitsperpurchaseunit, p_quantity,
        v_method                                                           -- 275
    )
    RETURNING waterrawmaterialpurchaseid INTO v_newid;

    UPDATE waterrawmaterialitems mi
    SET currentquantity = mi.currentquantity + v_prodqty,   -- production-level qty
        updatedat = (now() at time zone 'utc')
    WHERE mi.waterrawmaterialitemid = p_waterrawmaterialitemid AND mi.farmid = p_farmid;

    -- 275. The one new condition on this block. A deferred purchase writes NO
    -- expense: its cost is inventory value until 279 recognises it on
    -- consumption. Note what is NOT inside the condition -- the stock update
    -- above already ran, and the cash transaction below is nested INSIDE this
    -- block in the live body, which is correct: the cash row is keyed to the
    -- expense it pays for (sourcetype 'Expense', sourceid v_expenseid) and
    -- cannot exist without it.
    --
    -- That means a deferred CASH purchase moves no cash here either. It does not
    -- need to: a deferred purchase is entered on credit in every real workflow,
    -- and 277 opens its deferred balance from totalcost regardless of what has
    -- been paid. If that assumption ever breaks, the fix is a cash row that does
    -- not hang off an expense id -- not moving this gate.
    IF (v_catid IS NOT NULL AND v_amountpaid > 0
        AND fnwatercostrecognition_expenseatpurchase(v_method)) THEN         -- 275
        INSERT INTO waterexpenses
            (farmid, expensedate, waterexpensecategoryid, description, amount, paidto,
             paymentmethod, watercashaccountid, linkedwaterproductionbatchid,
             status, notes, createdby, approvedby, approvedat, supplierid, sourcetype, sourceid)
        VALUES
            (p_farmid, COALESCE(p_purchasedate, (now() at time zone 'utc')), v_catid,
             concat('Raw material purchase: ',
                    COALESCE(v_itemname, 'item #' || p_waterrawmaterialitemid::text),
                    ' (', p_quantity::numeric(14,3)::text, ' units)',
                    CASE WHEN v_amountpaid < v_totalcost
                         THEN concat(' - part payment of ', v_amountpaid::numeric(14,2)::text,
                                     ' of ', v_totalcost::numeric(14,2)::text)
                         ELSE '' END),
             v_amountpaid, v_suppliername, v_effectivepaymentmethod,
             CASE WHEN v_effectivepaymentmethod = 'Credit' THEN NULL ELSE v_cashaccountid END, NULL,
             'Approved', 'Auto-created from raw material purchase.',
             p_createdby, p_createdby, (now() at time zone 'utc'), p_supplierid, 'RawMaterialPurchase', v_newid)
        RETURNING waterexpenseid INTO v_expenseid;

        IF (v_effectivepaymentmethod <> 'Credit' AND v_cashaccountid IS NOT NULL) THEN
            INSERT INTO watercashtransactions (
                farmid, watercashaccountid, transactiondate, transactiontype,
                sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
            VALUES (
                p_farmid, v_cashaccountid, COALESCE(p_purchasedate, (now() at time zone 'utc')), 'CashOut',
                'Expense', v_expenseid, -v_amountpaid,
                concat('Raw material purchase #', v_newid), p_createdby, p_createdby, (now() at time zone 'utc'));

            UPDATE watercashaccounts ca
            SET currentbalance = ca.currentbalance - v_amountpaid,
                updatedat = (now() at time zone 'utc')
            WHERE ca.watercashaccountid = v_cashaccountid;
        END IF;

        UPDATE waterrawmaterialpurchases p SET linkedwaterexpenseid = v_expenseid
        WHERE p.waterrawmaterialpurchaseid = v_newid;
    END IF;

    RETURN v_newid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. The supplier payment: expense the non-deferred portion only.
--
-- Reproduced from the LIVE definition. The payment lookup, the cash-account
-- fallback (091), the party lookup, the inline category ensure (068), the
-- document list, the bill portion and every cash movement are unchanged.
--
-- One addition: v_purchase is split into the part that may be expensed and the
-- part that may not. Read the two SUMs together --
--
--   v_purchase          every non-Expense allocation. Still what the CASH row
--                       is written for, because the supplier was paid all of it.
--   v_purchaseexpensed  only the allocations whose purchase is snapshotted
--                       EXPENSE_WHEN_PURCHASED. What the EXPENSE row is written
--                       for, and the value the row's description counts.
--
-- Every non-Expense documenttype IS a raw-material purchase: the ELSE branch of
-- spwatersupplierpayment_record updates waterrawmaterialpurchases for exactly
-- those rows. The LEFT JOIN and the COALESCE are belt and braces -- an
-- allocation that somehow finds no purchase row falls to
-- EXPENSE_WHEN_PURCHASED, which is today's behaviour rather than a silent
-- suppression.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwatersupplierpaymentcash_sync(p_farmid text, p_paymentid integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_pay      record;
    v_catid    integer;
    v_acct     integer;
    v_docs     text;
    v_expense  integer;
    v_party    text;
    v_purchase numeric(14,2);
    v_bills    numeric(14,2);
    v_purchaseexpensed numeric(14,2);        -- 275
    v_alldocs  text;                         -- 275
BEGIN
    SELECT sp.watersupplierpaymentid, sp.supplierid, sp.paymentdate, sp.totalamount,
           sp.paymentmethod, sp.watercashaccountid, sp.createdby, sp.notes
    INTO   v_pay
    FROM   watersupplierpayments sp
    WHERE  sp.watersupplierpaymentid = p_paymentid AND sp.farmid = p_farmid
      AND  COALESCE(sp.status, 'Posted') = 'Posted';

    IF v_pay.watersupplierpaymentid IS NULL THEN RETURN; END IF;

    SELECT COALESCE(SUM(sa.amountapplied) FILTER (WHERE sa.documenttype <> 'Expense'), 0),
           COALESCE(SUM(sa.amountapplied) FILTER (WHERE sa.documenttype = 'Expense'), 0),
           -- 275. The deferred split.
           COALESCE(SUM(sa.amountapplied) FILTER (
               WHERE sa.documenttype <> 'Expense'
                 AND fnwatercostrecognition_expenseatpurchase(
                         COALESCE(pu.costrecognitionmethod, 'EXPENSE_WHEN_PURCHASED'))
           ), 0)
    INTO   v_purchase, v_bills, v_purchaseexpensed
    FROM   supplierpaymentallocation sa
    LEFT   JOIN waterrawmaterialpurchases pu                                  -- 275
           ON  pu.waterrawmaterialpurchaseid = sa.documentid
           AND pu.farmid = sa.farmid
           AND sa.documenttype <> 'Expense'
    WHERE  sa.farmid = p_farmid AND sa.module = 'water'
      AND  sa.paymentid = p_paymentid AND sa.status = 'Posted';

    -- 275. Every purchase document this payment settled, deferred or not. The
    -- CASH row is described with this, because the supplier was paid for all of
    -- them. v_docs below is the narrower list -- only the ones whose cost
    -- actually reached the P&L -- and describes the EXPENSE row.
    --
    -- For a payment with nothing deferred the two lists are identical, which is
    -- what keeps an unchanged payment's cash description byte-for-byte what it
    -- was.
    SELECT string_agg('#' || sa.documentid::text, ', ' ORDER BY sa.documentid)
    INTO   v_alldocs
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'water'
      AND  sa.paymentid = p_paymentid AND sa.status = 'Posted'
      AND  sa.documenttype <> 'Expense';

    -- The account the user chose, else the farm's first active one -- the same
    -- fallback 091 used, so behaviour is unchanged when no account is passed.
    v_acct := v_pay.watercashaccountid;
    IF v_acct IS NULL THEN
        SELECT a.watercashaccountid INTO v_acct
        FROM   watercashaccounts a
        WHERE  a.farmid = p_farmid AND a.isactive = TRUE
        ORDER  BY a.watercashaccountid
        LIMIT  1;
    END IF;

    SELECT s.suppliername INTO v_party
    FROM   watersuppliers s
    WHERE  s.watersupplierid = v_pay.supplierid AND s.farmid = p_farmid;

    -- ---- the purchase portion: expense row + its cash, exactly as before ----
    -- 275. Gated on the EXPENSED portion, not the whole. When every allocation
    -- on this payment is deferred, v_purchaseexpensed is 0, no expense row is
    -- written, and the cash for the payment still moves in the block below --
    -- which is now keyed to v_purchase, the full amount, as it always was.
    IF v_purchaseexpensed > 0 THEN
        -- Ensure the category exists, inline rather than through
        -- spwaterexpensecategory_ensurerawmaterialpurchase (068). Same category
        -- name, so an expense booked here lands where every other raw-material
        -- purchase expense already does.
        SELECT ec.waterexpensecategoryid INTO v_catid
        FROM   waterexpensecategories ec
        WHERE  ec.farmid = p_farmid
          AND  ec.name = 'Raw Materials / Inventory Purchase'
          AND  COALESCE(ec.isdeleted, FALSE) = FALSE
        LIMIT  1;

        IF v_catid IS NULL THEN
            INSERT INTO waterexpensecategories (farmid, name, isactive, isdeleted)
            VALUES (p_farmid, 'Raw Materials / Inventory Purchase', TRUE, FALSE)
            RETURNING waterexpensecategoryid INTO v_catid;
        END IF;

        -- 275. Only the documents this expense actually covers. Listing a
        -- deferred purchase in the description of an expense that excludes its
        -- value is how a reconciliation goes wrong at 11pm.
        SELECT string_agg('#' || sa.documentid::text, ', ' ORDER BY sa.documentid)
        INTO   v_docs
        FROM   supplierpaymentallocation sa
        LEFT   JOIN waterrawmaterialpurchases pu
               ON  pu.waterrawmaterialpurchaseid = sa.documentid
               AND pu.farmid = sa.farmid
        WHERE  sa.farmid = p_farmid AND sa.module = 'water'
          AND  sa.paymentid = p_paymentid AND sa.status = 'Posted'
          AND  sa.documenttype <> 'Expense'
          AND  fnwatercostrecognition_expenseatpurchase(
                   COALESCE(pu.costrecognitionmethod, 'EXPENSE_WHEN_PURCHASED'));

        INSERT INTO waterexpenses
            (farmid, expensedate, waterexpensecategoryid, description, amount, paidto,
             paymentmethod, watercashaccountid, linkedwaterproductionbatchid,
             status, notes, createdby, approvedby, approvedat,
             supplierid, sourcetype, sourceid)
        VALUES
            (p_farmid, v_pay.paymentdate, v_catid,
             'Supplier payment for raw material purchase ' || COALESCE(v_docs, ''),
             v_purchaseexpensed, v_party,                                     -- 275
             COALESCE(NULLIF(btrim(v_pay.paymentmethod), ''), 'Cash'),
             v_acct, NULL,
             'Approved',
             'Auto-created from a supplier payment.',
             v_pay.createdby, v_pay.createdby, (now() at time zone 'utc'),
             v_pay.supplierid, 'WaterSupplierPayment', p_paymentid)
        RETURNING waterexpenseid INTO v_expense;
    END IF;

    -- ---- the cash for the purchase portion: the FULL amount ----------------
    -- 275. Lifted out of the expense block above and keyed to v_purchase, not
    -- v_purchaseexpensed. The supplier was paid every cedi of it whether or not
    -- the cost has reached the P&L, so the cash account and the cash-flow
    -- statement must show every cedi.
    --
    -- sourcetype/sourceid stay 'Expense'/v_expense when there IS an expense, so
    -- an unchanged payment produces a byte-identical cash row. When the whole
    -- portion is deferred there is no expense to hang it off, and the row is
    -- keyed to the payment itself -- the same shape the bill portion below has
    -- always used.
    IF v_purchase > 0 AND v_acct IS NOT NULL THEN
        INSERT INTO watercashtransactions
            (farmid, watercashaccountid, transactiondate, transactiontype,
             sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_acct, v_pay.paymentdate, 'CashOut',
             CASE WHEN v_expense IS NOT NULL THEN 'Expense' ELSE 'WaterSupplierPayment' END,
             COALESCE(v_expense, p_paymentid), -v_purchase,
             'Supplier payment — raw material purchase ' || COALESCE(v_alldocs, ''),
             v_pay.createdby, v_pay.createdby, (now() at time zone 'utc'));

        UPDATE watercashaccounts
        SET    currentbalance = currentbalance - v_purchase,
               updatedat = (now() at time zone 'utc')
        WHERE  watercashaccountid = v_acct AND farmid = p_farmid;
    END IF;

    -- ---- the bill portion: cash only, keyed to the payment ------------------
    IF v_bills > 0 AND v_acct IS NOT NULL THEN
        INSERT INTO watercashtransactions
            (farmid, watercashaccountid, transactiondate, transactiontype,
             sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_acct, v_pay.paymentdate, 'CashOut',
             'WaterSupplierPayment', p_paymentid, -v_bills,
             'Supplier payment — expenses', v_pay.createdby, v_pay.createdby,
             (now() at time zone 'utc'));

        UPDATE watercashaccounts
        SET    currentbalance = currentbalance - v_bills,
               updatedat = (now() at time zone 'utc')
        WHERE  watercashaccountid = v_acct AND farmid = p_farmid;
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Grants. Both functions are called by the app role.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.spwaterrawmaterialpurchase_insert(
            text, integer, text, timestamp without time zone, numeric, numeric, text,
            numeric, text, integer, text, text, integer, numeric, integer, text, numeric)
            TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spwatersupplierpaymentcash_sync(text, integer)
            TO poultryapp;
    END IF;
END
$grants$;

-- -----------------------------------------------------------------------------
-- 4. Verify.
--
-- The interlock assertion is the important one: if a later edit to this file
-- ever flips deferralready() here instead of in 279, this fails loudly.
-- -----------------------------------------------------------------------------
DO $verify$
DECLARE
    v_src text;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'spwaterrawmaterialpurchase_insert';

    IF v_src IS NULL OR position('fnwatercostrecognition_expenseatpurchase' in v_src) = 0 THEN
        RAISE EXCEPTION '275 verify: the purchase insert is not gated on the recognition method.';
    END IF;
    IF position('costrecognitionmethod' in v_src) = 0 THEN
        RAISE EXCEPTION '275 verify: the purchase insert does not stamp the method.';
    END IF;

    SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'spwatersupplierpaymentcash_sync';

    IF v_src IS NULL OR position('v_purchaseexpensed' in v_src) = 0 THEN
        RAISE EXCEPTION '275 verify: the supplier payment is not split by recognition method.';
    END IF;

    IF public.fnwatercostrecognition_deferralready() THEN
        RAISE EXCEPTION
          '275 verify: the deferral interlock is OPEN. Only 279 may open it -- '
          'the consumption side must exist before any company can defer a cost.';
    END IF;

    RAISE NOTICE '275: purchase and supplier-payment expense are gated on the recognition method. Interlock still shut (279 opens it).';
END
$verify$;

COMMIT;

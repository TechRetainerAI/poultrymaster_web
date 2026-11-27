-- =============================================================================
-- 500_Enock_GenericPurchaseReversal: an approved Generic purchase is REVERSED
-- -- the Water (478) / Poultry (479) purchase reversal model, in the shape the
-- shared Reverse Purchase dialog reads.  (requires 449, 452, 472, 474, 483)
-- =============================================================================
--
-- WHY
-- ---
-- A Generic purchase could only be cancelled while it was a Draft. Once
-- approved -- stock in, cash out for what was paid at entry, the rest owed to
-- the supplier -- there was no way back short of hand-made adjustments.
--
-- THE RULE
-- --------
-- An approved purchase is REVERSED (GPR-00001). The reversal:
--   * is refused while any of its stock has been used: the product must still
--     hold what the purchase added, and (first in, first out) nothing may have
--     been drawn from the purchase's own lot;
--   * takes exactly that stock back out ('PurchaseReversal' movements);
--   * takes off the supplier's account what the purchase still owed them (the
--     purchase's own ledger lines, exactly);
--   * handles every amount paid on it as the user chooses:
--       KeepAsCredit  the supplier still holds the money. Paid at entry: a
--                     no-cash supplier payment row 'PurchaseReversalCredit'
--                     that is credit until used. A Supplier Payment: its
--                     allocation here is released, so its unapplied part --
--                     the supplier credit 449 already derives -- grows.
--       Refund        the supplier gave it back. Paid at entry: a CashIn
--                     'PurchaseReversal' to the purchase's account. A Supplier
--                     Payment that paid ONLY this purchase: it is reversed with
--                     spgenericsupplierpayment_reverse (cash back in).
--     Supplier credit spent on the purchase always goes back to the supplier.
--     A purchase with no supplier: refund only.
--   * records who, when, the reason (from the list; "Other" needs a note).
--
-- STATUS: A REVERSED PURCHASE IS 'Cancelled' + purchasereversalid (as 483 did
-- for sales). Every reader counts status = 'Approved' (payables, reports,
-- projects, KPIs); the screen says "Reversed" when purchasereversalid is set.
--
-- ALSO IN HERE
--   * trg_genericpurchase_reversedlock: a reversed purchase cannot be changed
--     (bypass: GUC generic.purchase_system, set only by the reversal).
--   * spgenericpurchase_getall returns purchasereversalid + reversalnumber.
--   * fngenericdeferred_lots / _draws leave a reversed purchase's lot and its
--     reversal movements out (a reversal is not usage).
--   * spgenericsupplierpayment_reverse refuses a 'PurchaseReversalCredit' row
--     (reversing it would make the credit vanish -- refund it instead).
--   * spgenericcashflow_rows (rebuilt from the live body):
--       - a reversed purchase's payment at entry stays on its day;
--       - a refund is its own row (money in, 'PurchaseRefund');
--       - 'PurchaseReversalCredit' rows are not cash and are left out.
-- =============================================================================

-- ------------------------------------------------------------- 1. columns ----
ALTER TABLE public.genericpurchases ADD COLUMN IF NOT EXISTS purchasereversalid integer   NULL;
ALTER TABLE public.genericpurchases ADD COLUMN IF NOT EXISTS reversedat         timestamp NULL;
ALTER TABLE public.genericpurchases ADD COLUMN IF NOT EXISTS reversedby         text      NULL;
ALTER TABLE public.genericpurchases ADD COLUMN IF NOT EXISTS reversalreason     text      NULL;

-- ------------------------------------------------------------- 2. tables -----
CREATE TABLE IF NOT EXISTS public.genericpurchasereversals (
    purchasereversalid serial        PRIMARY KEY,
    farmid             text          NOT NULL,
    reversalnumber     text          NOT NULL,
    genericpurchaseid  integer       NOT NULL,
    genericsupplierid  integer       NULL,
    suppliername       text          NULL,
    purchasedate       timestamp     NULL,
    reasoncode         text          NULL,
    reason             text          NOT NULL,
    businessdate       date          NOT NULL,
    occurredat         timestamp     NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    reversedby         text          NULL,
    paymenthandling    text          NOT NULL,
    totalamount        numeric(14,2) NOT NULL DEFAULT 0,
    paidamount         numeric(14,2) NOT NULL DEFAULT 0,
    outstandingamount  numeric(14,2) NOT NULL DEFAULT 0,
    creditcreated      numeric(14,2) NOT NULL DEFAULT 0,
    creditreleased     numeric(14,2) NOT NULL DEFAULT 0,
    refunded           numeric(14,2) NOT NULL DEFAULT 0,
    stockremoved       numeric(18,4) NOT NULL DEFAULT 0,
    idempotencykey     text          NULL,
    snapshot           jsonb         NULL,
    CONSTRAINT ck_genericpurchasereversals_handling
        CHECK (paymenthandling IN ('None', 'KeepAsCredit', 'Refund', 'Mixed'))
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericpurchasereversals_number   ON public.genericpurchasereversals (farmid, reversalnumber);
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericpurchasereversals_idem     ON public.genericpurchasereversals (farmid, idempotencykey) WHERE idempotencykey IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericpurchasereversals_purchase ON public.genericpurchasereversals (farmid, genericpurchaseid);

CREATE TABLE IF NOT EXISTS public.genericpurchasereversalpayments (
    purchasereversalpaymentid serial        PRIMARY KEY,
    purchasereversalid        integer       NOT NULL REFERENCES public.genericpurchasereversals (purchasereversalid),
    farmid                    text          NOT NULL,
    itemkey                   text          NOT NULL,     -- entry | sp:{paymentid}
    paymentid                 integer       NULL,         -- the supplier payment (sp:), or the credit row made (entry kept)
    amount                    numeric(14,2) NOT NULL,
    action                    text          NOT NULL,
    cashtransactionid         integer       NULL,         -- entry refunded: the CashIn
    CONSTRAINT ck_genericpurchasereversalpayments_action CHECK (action IN ('KeepAsCredit', 'Refund'))
);
CREATE INDEX IF NOT EXISTS ix_genericpurchasereversalpayments_rev ON public.genericpurchasereversalpayments (purchasereversalid);

-- ------------------------------------------------------------- 3. lock -------
DROP TRIGGER IF EXISTS trg_genericpurchase_reversedlock ON public.genericpurchases;
DROP FUNCTION IF EXISTS public.trg_genericpurchase_reversedlock_fn();
CREATE FUNCTION public.trg_genericpurchase_reversedlock_fn()
RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
    IF COALESCE(current_setting('generic.purchase_system', true), '') = 'on' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    IF OLD.purchasereversalid IS NOT NULL THEN
        RAISE EXCEPTION 'Purchase #% was reversed (%). A reversed purchase cannot be changed or deleted.',
            OLD.genericpurchaseid, COALESCE(OLD.reversalreason, '') USING ERRCODE = 'P0001';
    END IF;
    RETURN COALESCE(NEW, OLD);
END $f$;
CREATE TRIGGER trg_genericpurchase_reversedlock
    BEFORE UPDATE OR DELETE ON public.genericpurchases
    FOR EACH ROW EXECUTE FUNCTION public.trg_genericpurchase_reversedlock_fn();

-- --------------------------------------------------- 4. deferred lots/draws --
-- A reversed purchase's lot never existed, and its reversal is not usage.
CREATE OR REPLACE FUNCTION public.fngenericdeferred_lots(p_farmid text)
 RETURNS TABLE(lotid integer, genericproductid integer, lotdate timestamp without time zone, movementtype text, referencetype text, referenceid integer, quantity numeric, unitcost numeric, lotcost numeric, lotstart numeric, lotend numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH l AS (
        SELECT m.genericstockmovementid, m.genericproductid, m.movementdate, m.movementtype::text,
               m.referencetype::text, m.referenceid, m.quantity::numeric AS qty,
               round(COALESCE(NULLIF(abs(m.totalcostvalue), 0) / NULLIF(m.quantity, 0), m.unitcost, 0)::numeric, 6) AS uc,
               round(COALESCE(NULLIF(abs(m.totalcostvalue), 0), m.quantity * COALESCE(m.unitcost, 0), 0)::numeric, 2) AS cost
        FROM   genericstockmovements m
        WHERE  m.farmid = p_farmid AND m.quantity > 0
          AND  m.movementtype NOT IN ('Delivery Return', 'Delivery Cancel', 'ReturnIn')
          -- 500: the lot of a reversed purchase
          AND  NOT (m.referencetype = 'Purchase' AND EXISTS (
                   SELECT 1 FROM genericpurchases pu
                   WHERE  pu.genericpurchaseid = m.referenceid AND pu.farmid = p_farmid
                     AND  pu.purchasereversalid IS NOT NULL))
    )
    SELECT l.genericstockmovementid, l.genericproductid, l.movementdate, l.movementtype, l.referencetype,
           l.referenceid, l.qty, l.uc, l.cost,
           COALESCE(SUM(l.qty) OVER w, 0) - l.qty, COALESCE(SUM(l.qty) OVER w, 0)
    FROM   l
    WINDOW w AS (PARTITION BY l.genericproductid ORDER BY l.movementdate, l.genericstockmovementid
                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW);
$function$;

CREATE OR REPLACE FUNCTION public.fngenericdeferred_draws(p_farmid text)
 RETURNS TABLE(movementid integer, genericproductid integer, drawdate timestamp without time zone, movementtype text, referencetype text, referenceid integer, quantity numeric, cstart numeric, cend numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH d AS (
        SELECT m.genericstockmovementid, m.genericproductid, m.movementdate, m.movementtype::text,
               m.referencetype::text, m.referenceid, (-m.quantity)::numeric AS qty
        FROM   genericstockmovements m
        WHERE  m.farmid = p_farmid
          AND  (m.quantity < 0 OR (m.quantity > 0 AND m.movementtype IN ('Delivery Return', 'Delivery Cancel', 'ReturnIn')))
          AND  m.movementtype <> 'PurchaseReversal'   -- 500
    )
    SELECT d.genericstockmovementid, d.genericproductid, d.movementdate, d.movementtype, d.referencetype,
           d.referenceid, d.qty,
           SUM(d.qty) OVER w - d.qty, SUM(d.qty) OVER w
    FROM   d
    WINDOW w AS (PARTITION BY d.genericproductid ORDER BY d.movementdate, d.genericstockmovementid
                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW);
$function$;

-- ------------------------------------------------------------- 5. state ------
-- What reversing the purchase would do, in the shape of lib/api/purchase-reversal.ts
-- PurchaseReversalPreview (+ 'lines' and 'costOnPl' for a many-line purchase).
DROP FUNCTION IF EXISTS public.fngenericpurchase_reversalstate(text, integer);
CREATE FUNCTION public.fngenericpurchase_reversalstate(p_farmid text, p_purchaseid integer)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE
    pu          record;
    v_supplier  text;
    v_acctname  text;
    v_blockers  jsonb := '[]'::jsonb;
    v_lines     jsonb := '[]'::jsonb;
    v_pays      jsonb := '[]'::jsonb;
    v_alloc     numeric(14,2);
    v_fromcred  numeric(14,2);
    v_upfront   numeric(14,2);
    v_stock     numeric := 0;
    v_r         record;
    v_ok        boolean;
    v_why       text;
    v_allowed   jsonb;
    v_names     text;
    v_count     integer;
    v_fp        text;
BEGIN
    SELECT p.* INTO pu FROM genericpurchases p
    WHERE  p.genericpurchaseid = p_purchaseid AND p.farmid = p_farmid AND NOT COALESCE(p.isdeleted, false);
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', false, 'purchaseId', p_purchaseid, 'blockers',
            jsonb_build_array(jsonb_build_object('code', 'NotFound', 'message', 'Purchase not found for this company.')),
            'payments', '[]'::jsonb, 'lines', '[]'::jsonb, 'fingerprint', '');
    END IF;

    IF pu.genericsupplierid IS NOT NULL THEN
        SELECT s.suppliername INTO v_supplier FROM genericsuppliers s
        WHERE  s.genericsupplierid = pu.genericsupplierid AND s.farmid = p_farmid;
    END IF;
    IF pu.genericcashaccountid IS NOT NULL THEN
        SELECT a.accountname INTO v_acctname FROM genericcashaccounts a
        WHERE  a.genericcashaccountid = pu.genericcashaccountid AND a.farmid = p_farmid;
    END IF;

    -- ---- blockers: the purchase itself
    IF pu.purchasereversalid IS NOT NULL THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'AlreadyReversed', 'message', 'This purchase has already been reversed.');
    ELSIF pu.status = 'Draft' THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'Draft', 'message', 'This purchase is still a draft: nothing was posted. Cancel the draft instead.');
    ELSIF pu.status <> 'Approved' THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'NotApproved', 'message', format('Only an approved purchase can be reversed (this one is %s).', pu.status));
    END IF;

    -- ---- stock: what the purchase put in, per product, and whether any is used
    FOR v_r IN
        WITH mine AS (
            SELECT m.genericproductid, SUM(m.quantity) AS qty
            FROM   genericstockmovements m
            WHERE  m.farmid = p_farmid AND m.referencetype = 'Purchase' AND m.referenceid = p_purchaseid
              AND  m.movementtype IN ('PurchaseIn', 'PurchaseReversal')
            GROUP  BY m.genericproductid
            HAVING SUM(m.quantity) > 0
        ), lot AS (
            SELECT l.genericproductid, MIN(l.lotstart) AS lotstart
            FROM   fngenericdeferred_lots(p_farmid) l
            WHERE  l.referencetype = 'Purchase' AND l.referenceid = p_purchaseid
            GROUP  BY l.genericproductid
        ), drawn AS (
            SELECT d.genericproductid, SUM(d.quantity) AS qty
            FROM   fngenericdeferred_draws(p_farmid) d
            WHERE  d.genericproductid IN (SELECT genericproductid FROM mine)
            GROUP  BY d.genericproductid
        )
        SELECT mine.genericproductid, mine.qty, p.productname, p.currentstock,
               COALESCE(NULLIF(btrim(p.unitofmeasure), ''), 'units') AS unit,
               lot.lotstart, COALESCE(drawn.qty, 0) AS drawn
        FROM   mine
        JOIN   genericproducts p ON p.genericproductid = mine.genericproductid AND p.farmid = p_farmid
        LEFT   JOIN lot   ON lot.genericproductid   = mine.genericproductid
        LEFT   JOIN drawn ON drawn.genericproductid = mine.genericproductid
        ORDER  BY p.productname
    LOOP
        v_lines := v_lines || jsonb_build_object(
            'productId', v_r.genericproductid, 'name', v_r.productname, 'quantity', v_r.qty,
            'unit', v_r.unit, 'inStock', COALESCE(v_r.currentstock, 0));
        v_stock := v_stock + v_r.qty;
        IF COALESCE(v_r.currentstock, 0) < v_r.qty - 0.0005 THEN
            v_blockers := v_blockers || jsonb_build_object('code', 'StockUsed:' || v_r.genericproductid, 'message',
                format('%s: only %s %s left in stock, but this purchase added %s. Some of it has been sold or used.',
                       v_r.productname, trim(to_char(COALESCE(v_r.currentstock, 0), 'FM999999999990.###')), v_r.unit,
                       trim(to_char(v_r.qty, 'FM999999999990.###'))));
        ELSIF v_r.lotstart IS NOT NULL AND v_r.drawn > v_r.lotstart + 0.0005 THEN
            v_blockers := v_blockers || jsonb_build_object('code', 'StockUsed:' || v_r.genericproductid, 'message',
                format('%s: some of the stock from this purchase has already been sold or used (stock is used oldest first).',
                       v_r.productname));
        END IF;
    END LOOP;

    -- ---- old Draft/Approve supplier payments linked to the purchase (no allocation rows)
    SELECT string_agg('#' || sp.genericsupplierpaymentid, ', ' ORDER BY sp.genericsupplierpaymentid) INTO v_names
    FROM   genericsupplierpayments sp
    WHERE  sp.farmid = p_farmid AND sp.linkedpurchaseid = p_purchaseid
      AND  sp.status = 'Approved' AND sp.sourcetype IS NULL;
    IF v_names IS NOT NULL THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'LegacyPayment', 'message',
            format('Supplier payment %s was made against this purchase the old way. Reverse it on Supplier Payments first.', v_names));
    END IF;

    -- ---- money: Supplier Payments applied here (not credit), one line per payment
    FOR v_r IN
        SELECT sp.genericsupplierpaymentid AS id, sp.amount, sp.paymentdate, sp.paymentmethod, sp.genericcashaccountid,
               a.accountname, COALESCE(NULLIF(btrim(sp.referenceno), ''), 'Supplier payment #' || sp.genericsupplierpaymentid) AS num,
               SUM(sa.amountapplied) AS applied,
               (SELECT COALESCE(SUM(o.amountapplied), 0) FROM supplierpaymentallocation o
                WHERE  o.farmid = p_farmid AND o.module = 'generic' AND o.paymentid = sp.genericsupplierpaymentid
                  AND  o.status = 'Posted' AND NOT (o.documenttype = 'Purchase' AND o.documentid = p_purchaseid AND NOT o.fromcredit)) AS elsewhere,
               EXISTS (SELECT 1 FROM genericsupplierrefundlines rl JOIN genericsupplierrefunds rf ON rf.refundid = rl.refundid
                       WHERE rl.farmid = p_farmid AND rl.genericsupplierpaymentid = sp.genericsupplierpaymentid AND rf.status = 'Posted') AS refunded
        FROM   supplierpaymentallocation sa
        JOIN   genericsupplierpayments sp ON sp.genericsupplierpaymentid = sa.paymentid AND sp.farmid = p_farmid
        LEFT   JOIN genericcashaccounts a ON a.genericcashaccountid = sp.genericcashaccountid
        WHERE  sa.farmid = p_farmid AND sa.module = 'generic' AND sa.documenttype = 'Purchase'
          AND  sa.documentid = p_purchaseid AND sa.status = 'Posted' AND NOT sa.fromcredit
        GROUP  BY sp.genericsupplierpaymentid, sp.amount, sp.paymentdate, sp.paymentmethod, sp.genericcashaccountid, a.accountname, sp.referenceno
        ORDER  BY sp.genericsupplierpaymentid
    LOOP
        v_why := CASE
            WHEN v_r.elsewhere > 0 OR v_r.applied < v_r.amount - 0.005 THEN
                'This payment also paid other bills or left credit, so its share here becomes supplier credit. To get money back, reverse the payment itself on Supplier Payments.'
            WHEN v_r.refunded THEN
                'Part of this payment was already refunded, so its share here can only become supplier credit.'
            WHEN v_r.genericcashaccountid IS NULL THEN
                'This payment did not go through a cash account, so there is nothing to put back; it becomes supplier credit.'
            END;
        v_pays := v_pays || jsonb_build_object(
            'key', 'sp:' || v_r.id, 'source', 'SupplierPayment', 'paymentId', v_r.id, 'paymentNumbers', v_r.num,
            'allocated', v_r.applied, 'paymentDate', v_r.paymentdate, 'paymentMethod', v_r.paymentmethod,
            'cashAccountId', v_r.genericcashaccountid, 'cashAccountName', v_r.accountname,
            'allowed', CASE WHEN v_why IS NULL THEN '["KeepAsCredit","Refund"]'::jsonb ELSE '["KeepAsCredit"]'::jsonb END,
            'default', 'KeepAsCredit',
            'keepUnavailableReason', NULL, 'refundUnavailableReason', v_why, 'noCashNote', NULL);
    END LOOP;

    -- ---- money: paid when the purchase was entered (approval took it out of the account)
    SELECT COALESCE(SUM(sa.amountapplied) FILTER (WHERE NOT sa.fromcredit), 0),
           COALESCE(SUM(sa.amountapplied) FILTER (WHERE sa.fromcredit), 0)
    INTO   v_alloc, v_fromcred
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'generic' AND sa.documenttype = 'Purchase'
      AND  sa.documentid = p_purchaseid AND sa.status = 'Posted';
    v_upfront := GREATEST(ROUND(COALESCE(pu.amountpaid, 0) - v_alloc - v_fromcred, 2), 0);

    IF v_upfront > 0.004 AND pu.status = 'Approved' THEN
        v_allowed := CASE
            WHEN pu.genericsupplierid IS NULL THEN '["Refund"]'::jsonb
            WHEN pu.genericcashaccountid IS NULL THEN '["KeepAsCredit"]'::jsonb
            ELSE '["KeepAsCredit","Refund"]'::jsonb END;
        v_pays := jsonb_build_array(jsonb_build_object(
            'key', 'entry', 'source', 'PaidAtEntry', 'paymentId', NULL, 'paymentNumbers', 'Paid when the purchase was entered',
            'allocated', v_upfront, 'paymentDate', pu.purchasedate, 'paymentMethod', pu.paymentmethod,
            'cashAccountId', pu.genericcashaccountid, 'cashAccountName', v_acctname,
            'allowed', v_allowed,
            'default', CASE WHEN pu.genericsupplierid IS NULL THEN 'Refund' ELSE 'KeepAsCredit' END,
            'keepUnavailableReason', CASE WHEN pu.genericsupplierid IS NULL THEN 'This purchase has no supplier to hold the money as credit.' END,
            'refundUnavailableReason', CASE WHEN pu.genericcashaccountid IS NULL THEN 'This money did not go through a cash account.' END,
            'noCashNote', NULL)) || v_pays;
        IF pu.genericsupplierid IS NULL AND pu.genericcashaccountid IS NULL THEN
            v_blockers := v_blockers || jsonb_build_object('code', 'NoCashAccount', 'message',
                'Money was paid on this purchase but it has neither a supplier to hold it as credit nor a cash account to refund it to.');
        END IF;
    END IF;

    SELECT count(*) INTO v_count FROM jsonb_array_elements(v_lines);
    v_fp := md5(concat_ws('|', pu.status, pu.amountpaid, pu.balance, pu.totalamount, pu.updatedat, pu.purchasereversalid,
                (SELECT string_agg(sa.allocationid || ':' || sa.status || ':' || sa.amountapplied, ',' ORDER BY sa.allocationid)
                 FROM supplierpaymentallocation sa WHERE sa.farmid = p_farmid AND sa.module = 'generic'
                   AND sa.documenttype = 'Purchase' AND sa.documentid = p_purchaseid),
                (SELECT string_agg((x->>'productId') || ':' || (x->>'inStock'), ',') FROM jsonb_array_elements(v_lines) x)));

    RETURN jsonb_build_object(
        'found', true, 'purchaseId', p_purchaseid, 'purchaseDate', pu.purchasedate,
        'itemName', CASE WHEN v_count = 0 THEN 'No stocked items'
                         WHEN v_count = 1 THEN v_lines->0->>'name'
                         ELSE v_count || ' items' END,
        'unit', CASE WHEN v_count = 1 THEN v_lines->0->>'unit' END,
        'quantity', v_stock, 'stockToRemove', v_stock, 'lines', v_lines,
        'supplierId', pu.genericsupplierid, 'supplierName', COALESCE(v_supplier, 'No supplier'),
        'total', COALESCE(pu.totalamount, 0), 'paid', COALESCE(pu.amountpaid, 0),
        'creditApplied', v_fromcred,
        'outstanding', GREATEST(COALESCE(pu.totalamount, 0) - COALESCE(pu.amountpaid, 0), 0),
        'deferred', false, 'costOnPl', false,
        'payments', v_pays,
        'supplierCreditNow', COALESCE((SELECT SUM(fngenericsupplierpayment_unapplied(p_farmid, sp.genericsupplierpaymentid))
                                       FROM genericsupplierpayments sp
                                       WHERE sp.farmid = p_farmid AND sp.genericsupplierid = pu.genericsupplierid), 0),
        'blockers', v_blockers, 'fingerprint', v_fp);
END $f$;

DROP FUNCTION IF EXISTS public.spgenericpurchase_reversalpreview(text, integer);
CREATE FUNCTION public.spgenericpurchase_reversalpreview(p_farmid text, p_purchaseid integer)
RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT public.fngenericpurchase_reversalstate(p_farmid, p_purchaseid) $$;

-- ------------------------------------------------------------- 6. reverse ----
-- Releases one posted allocation on the purchase: the document's amount paid
-- comes down and the supplier is owed it again (taken off with the purchase).
DROP FUNCTION IF EXISTS public.fngenericpurchase_releaseallocation(text, integer, text, text);
CREATE FUNCTION public.fngenericpurchase_releaseallocation(p_farmid text, p_allocationid integer, p_reason text, p_by text)
RETURNS numeric LANGUAGE plpgsql AS $f$
DECLARE a record; v_supplier integer;
BEGIN
    SELECT sa.* INTO a FROM supplierpaymentallocation sa
    WHERE  sa.allocationid = p_allocationid AND sa.farmid = p_farmid AND sa.status = 'Posted' FOR UPDATE;
    IF NOT FOUND THEN RETURN 0; END IF;
    PERFORM public.fngenericpayable_addpaid(p_farmid, a.documenttype, a.documentid, -a.amountapplied);
    UPDATE supplierpaymentallocation SET status = 'Reversed', reversedby = p_by,
           reversedat = (now() AT TIME ZONE 'utc'), reversalreason = p_reason
    WHERE  allocationid = p_allocationid;
    SELECT sp.genericsupplierid INTO v_supplier FROM genericsupplierpayments sp
    WHERE  sp.genericsupplierpaymentid = a.paymentid AND sp.farmid = p_farmid;
    PERFORM public.fngenericsupplier_ledgermove(p_farmid, v_supplier, a.amountapplied, 'PurchaseReversal',
        p_reason, p_by, a.paymentid);
    RETURN a.amountapplied;
END $f$;

DROP FUNCTION IF EXISTS public.spgenericpurchase_reverse(text, integer, text, text, jsonb, text, text, text);
CREATE FUNCTION public.spgenericpurchase_reverse(p_farmid text, p_purchaseid integer, p_reasoncode text, p_reason text,
                                                 p_handling jsonb DEFAULT '{}'::jsonb, p_expectedfingerprint text DEFAULT NULL,
                                                 p_idempotencykey text DEFAULT NULL, p_reversedby text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_now      timestamp := (now() AT TIME ZONE 'utc');
    v_state    jsonb;
    v_item     jsonb;
    v_action   text;
    v_reason   text;
    v_label    text;
    v_existing integer;
    v_id       integer;
    v_number   text;
    v_amt      numeric(14,2);
    v_payid    integer;
    v_cashtx   integer;
    v_credit   numeric(14,2) := 0;
    v_released numeric(14,2) := 0;
    v_refund   numeric(14,2) := 0;
    v_net      numeric(14,2);
    v_bal      numeric(14,2);
    v_kinds    text[] := ARRAY[]::text[];
    v_a        record;
    pu         record;
BEGIN
    IF NULLIF(btrim(COALESCE(p_reasoncode, '')), '') IS NULL AND NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for reversing this purchase.' USING ERRCODE = 'P0001';
    END IF;
    IF lower(btrim(COALESCE(p_reasoncode, ''))) = 'other' AND NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Say in a few words what happened (the reason is "Other").' USING ERRCODE = 'P0001';
    END IF;
    v_reason := concat_ws(': ', NULLIF(btrim(COALESCE(p_reasoncode, '')), ''), NULLIF(btrim(COALESCE(p_reason, '')), ''));

    PERFORM pg_advisory_xact_lock(hashtext('generic-purchasereversal:' || p_farmid || ':' || p_purchaseid::text));
    PERFORM 1 FROM genericpurchases p WHERE p.farmid = p_farmid AND p.genericpurchaseid = p_purchaseid FOR UPDATE;

    IF p_idempotencykey IS NOT NULL THEN
        SELECT r.purchasereversalid INTO v_existing FROM genericpurchasereversals r
        WHERE  r.farmid = p_farmid AND r.idempotencykey = p_idempotencykey;
        IF FOUND THEN RETURN v_existing; END IF;
    END IF;

    v_state := fngenericpurchase_reversalstate(p_farmid, p_purchaseid);
    IF jsonb_array_length(v_state->'blockers') > 0 THEN
        RAISE EXCEPTION '%', v_state->'blockers'->0->>'message' USING ERRCODE = 'P0001';
    END IF;
    IF p_expectedfingerprint IS NOT NULL AND p_expectedfingerprint <> v_state->>'fingerprint' THEN
        RAISE EXCEPTION 'This purchase changed after the reversal preview was generated. Please review the updated impact before continuing.'
            USING ERRCODE = 'P0001', HINT = 'stale-preview';
    END IF;
    SELECT p.* INTO pu FROM genericpurchases p WHERE p.genericpurchaseid = p_purchaseid AND p.farmid = p_farmid;

    -- every choice is valid before anything changes
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_state->'payments') LOOP
        v_action := COALESCE(p_handling->>(v_item->>'key'), v_item->>'default');
        IF NOT (v_item->'allowed') ? v_action THEN
            RAISE EXCEPTION '%', CASE
                WHEN v_action = 'Refund' THEN COALESCE(v_item->>'refundUnavailableReason', 'This money cannot be recorded as refunded.')
                ELSE COALESCE(v_item->>'keepUnavailableReason', 'This money cannot be kept as supplier credit.') END
                USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    PERFORM set_config('generic.purchase_system', 'on', true);

    -- 1. the record (numbered)
    PERFORM pg_advisory_xact_lock(hashtext('generic-purchasereversal-no:' || p_farmid));
    SELECT 'GPR-' || lpad((COALESCE(MAX(NULLIF(regexp_replace(r.reversalnumber, '\D', '', 'g'), '')::int), 0) + 1)::text, 5, '0')
    INTO   v_number FROM genericpurchasereversals r WHERE r.farmid = p_farmid;
    v_label := 'Purchase #' || p_purchaseid || ' reversed (' || v_number || ')';

    INSERT INTO genericpurchasereversals (farmid, reversalnumber, genericpurchaseid, genericsupplierid, suppliername, purchasedate,
                                          reasoncode, reason, businessdate, occurredat, reversedby, paymenthandling,
                                          totalamount, paidamount, outstandingamount, stockremoved, idempotencykey, snapshot)
    VALUES (p_farmid, v_number, p_purchaseid, pu.genericsupplierid, v_state->>'supplierName', pu.purchasedate,
            NULLIF(btrim(COALESCE(p_reasoncode, '')), ''), v_reason, fncompany_businessdate(p_farmid), v_now, p_reversedby, 'None',
            COALESCE(pu.totalamount, 0), COALESCE(pu.amountpaid, 0), (v_state->>'outstanding')::numeric,
            (v_state->>'stockToRemove')::numeric, p_idempotencykey, v_state)
    RETURNING purchasereversalid INTO v_id;

    -- 2. each amount paid, as chosen
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_state->'payments') LOOP
        v_action := COALESCE(p_handling->>(v_item->>'key'), v_item->>'default');
        v_amt    := (v_item->>'allocated')::numeric;
        v_payid  := NULLIF(v_item->>'paymentId', '')::int;
        v_cashtx := NULL;
        IF v_item->>'key' = 'entry' THEN
            IF v_action = 'Refund' THEN
                PERFORM fngenericcash_move(p_farmid, pu.genericcashaccountid, v_amt, v_now, 'PurchaseReversal', p_purchaseid,
                                           v_label || ': supplier refunded what was paid', p_reversedby);
                SELECT MAX(t.genericcashtransactionid) INTO v_cashtx FROM genericcashtransactions t
                WHERE  t.farmid = p_farmid AND t.sourcetype = 'PurchaseReversal' AND t.sourceid = p_purchaseid;
                v_refund := v_refund + v_amt;
            ELSE
                -- the supplier keeps it: a no-cash credit row, credit until used
                INSERT INTO genericsupplierpayments (farmid, genericsupplierid, paymentdate, amount, paymentmethod,
                                                     genericcashaccountid, status, notes, referenceno, sourcetype,
                                                     createdby, approvedby, approvedat, createdat)
                VALUES (p_farmid, pu.genericsupplierid, v_now, v_amt, 'Credit', NULL, 'Approved',
                        v_label || ': paid at entry, kept as credit', v_number, 'PurchaseReversalCredit',
                        p_reversedby, p_reversedby, v_now, v_now)
                RETURNING genericsupplierpaymentid INTO v_payid;
                v_credit := v_credit + v_amt;
            END IF;
        ELSE
            IF v_action = 'Refund' THEN
                -- the payment paid only this purchase: reverse it (cash back in, allocation released)
                PERFORM spgenericsupplierpayment_reverse(p_farmid, v_payid, v_label || ': ' || v_reason, p_reversedby);
                v_refund := v_refund + v_amt;
            ELSE
                FOR v_a IN
                    SELECT sa.allocationid FROM supplierpaymentallocation sa
                    WHERE  sa.farmid = p_farmid AND sa.module = 'generic' AND sa.paymentid = v_payid
                      AND  sa.documenttype = 'Purchase' AND sa.documentid = p_purchaseid
                      AND  sa.status = 'Posted' AND NOT sa.fromcredit
                LOOP
                    PERFORM fngenericpurchase_releaseallocation(p_farmid, v_a.allocationid, v_label || ': kept as credit', p_reversedby);
                END LOOP;
                v_credit := v_credit + v_amt;
            END IF;
        END IF;
        v_kinds := array_append(v_kinds, v_action);
        INSERT INTO genericpurchasereversalpayments (purchasereversalid, farmid, itemkey, paymentid, amount, action, cashtransactionid)
        VALUES (v_id, p_farmid, v_item->>'key', v_payid, v_amt, v_action, v_cashtx);
    END LOOP;

    -- 3. supplier credit spent on it (and anything else still applied) goes back
    FOR v_a IN
        SELECT sa.allocationid FROM supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = 'generic' AND sa.documenttype = 'Purchase'
          AND  sa.documentid = p_purchaseid AND sa.status = 'Posted'
    LOOP
        v_released := v_released + fngenericpurchase_releaseallocation(p_farmid, v_a.allocationid, v_label || ': credit given back', p_reversedby);
    END LOOP;

    -- 4. the supplier's account: take off exactly what the purchase posted
    IF pu.genericsupplierid IS NOT NULL THEN
        SELECT COALESCE(SUM(l.creditamount), 0) - COALESCE(SUM(l.debitamount), 0) INTO v_net
        FROM   genericsupplierledger l
        WHERE  l.farmid = p_farmid AND l.genericsupplierid = pu.genericsupplierid AND l.purchaseid = p_purchaseid;
        IF v_net <> 0 THEN
            SELECT COALESCE(s.currentbalance, 0) INTO v_bal FROM genericsuppliers s
            WHERE  s.genericsupplierid = pu.genericsupplierid AND s.farmid = p_farmid FOR UPDATE;
            INSERT INTO genericsupplierledger (farmid, genericsupplierid, transactiondate, transactiontype, purchaseid,
                                               debitamount, creditamount, balanceaftertransaction, description, createdby)
            VALUES (p_farmid, pu.genericsupplierid, v_now, 'PurchaseReversal', p_purchaseid,
                    GREATEST(v_net, 0), GREATEST(-v_net, 0), GREATEST(v_bal - v_net, 0), v_label || ': ' || v_reason, p_reversedby);
            UPDATE genericsuppliers SET currentbalance = GREATEST(v_bal - v_net, 0), updatedat = v_now
            WHERE  genericsupplierid = pu.genericsupplierid AND farmid = p_farmid;
        END IF;
    END IF;

    -- 5. stock: take back out exactly what the purchase put in
    INSERT INTO genericstockmovements (farmid, genericproductid, movementdate, movementtype, quantity, unitcost,
                                       totalcostvalue, referencetype, referenceid, reason, createdby, approvedby, approvedat)
    SELECT m.farmid, m.genericproductid, v_now, 'PurchaseReversal', -SUM(m.quantity),
           CASE WHEN SUM(m.quantity) <> 0 THEN SUM(COALESCE(m.totalcostvalue, 0)) / SUM(m.quantity) END,
           SUM(COALESCE(m.totalcostvalue, 0)), 'Purchase', p_purchaseid, v_label, p_reversedby, p_reversedby, v_now
    FROM   genericstockmovements m
    WHERE  m.farmid = p_farmid AND m.referencetype = 'Purchase' AND m.referenceid = p_purchaseid
      AND  m.movementtype IN ('PurchaseIn', 'PurchaseReversal')
    GROUP  BY m.farmid, m.genericproductid
    HAVING SUM(m.quantity) > 0;

    UPDATE genericproducts p
    SET    currentstock = p.currentstock + x.qty, updatedat = v_now
    FROM  (SELECT m.genericproductid, SUM(m.quantity) AS qty     -- the rows just written (negative)
           FROM   genericstockmovements m
           WHERE  m.farmid = p_farmid AND m.referencetype = 'Purchase' AND m.referenceid = p_purchaseid
             AND  m.movementtype = 'PurchaseReversal' AND m.reason = v_label
           GROUP  BY m.genericproductid) x
    WHERE  p.genericproductid = x.genericproductid AND p.farmid = p_farmid AND p.trackinventory;

    -- 6. the record's totals, then the purchase itself
    UPDATE genericpurchasereversals r
    SET    creditcreated = v_credit, creditreleased = v_released, refunded = v_refund,
           paymenthandling = CASE
               WHEN cardinality(v_kinds) = 0 THEN 'None'
               WHEN 'KeepAsCredit' = ALL (v_kinds) THEN 'KeepAsCredit'
               WHEN 'Refund' = ALL (v_kinds) THEN 'Refund'
               ELSE 'Mixed' END
    WHERE  r.purchasereversalid = v_id;

    -- amountpaid is left as what was paid at entry (Cash Flow keeps that day's
    -- money out); nothing is owed on a reversed purchase.
    UPDATE genericpurchases p
    SET    status = 'Cancelled', purchasereversalid = v_id, reversedat = v_now, reversedby = p_reversedby,
           reversalreason = v_reason, balance = 0,
           cancelledat = v_now, cancelledby = p_reversedby, cancellationreason = 'Reversed (' || v_number || '): ' || v_reason,
           updatedat = v_now
    WHERE  p.genericpurchaseid = p_purchaseid AND p.farmid = p_farmid;

    PERFORM set_config('generic.purchase_system', 'off', true);
    RETURN v_id;
END $f$;

-- ------------------------------------------------------------- 7. read -------
DROP FUNCTION IF EXISTS public.spgenericpurchase_reversalget(text, integer);
CREATE FUNCTION public.spgenericpurchase_reversalget(p_farmid text, p_purchaseid integer)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'purchaseReversalId', r.purchasereversalid, 'reversalNumber', r.reversalnumber, 'purchaseId', r.genericpurchaseid,
        'reasonCode', r.reasoncode, 'reason', r.reason, 'occurredAt', r.occurredat, 'reversedBy', r.reversedby,
        'paymentHandling', r.paymenthandling, 'total', r.totalamount, 'paid', r.paidamount,
        'creditCreated', r.creditcreated, 'creditReleased', r.creditreleased, 'refunded', r.refunded,
        'stockRemoved', r.stockremoved)
    FROM genericpurchasereversals r
    WHERE r.farmid = p_farmid AND r.genericpurchaseid = p_purchaseid
$$;

-- the list says which purchases were reversed
DROP FUNCTION IF EXISTS public.spgenericpurchase_getall(text, text);
CREATE FUNCTION public.spgenericpurchase_getall(p_farmid text, p_status text DEFAULT NULL::text)
 RETURNS TABLE(genericpurchaseid integer, farmid text, genericsupplierid integer, suppliername text, purchasedate timestamp without time zone, branchid integer, subtotalamount numeric, discountamount numeric, taxamount numeric, totalamount numeric, amountpaid numeric, balance numeric, paymentstatus text, paymentmethod text, genericcashaccountid integer, invoicenumber text, receipturl text, receivedbystaffid integer, status text, notes text, createdby text, approvedby text, approvedat timestamp without time zone, cancelledby text, cancelledat timestamp without time zone, cancellationreason text, createdat timestamp without time zone, updatedat timestamp without time zone, purchasereversalid integer, reversalnumber text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT p.genericpurchaseid, p.farmid::text, p.genericsupplierid, s.suppliername::text,
           p.purchasedate, p.branchid,
           p.subtotalamount, p.discountamount, p.taxamount, p.totalamount,
           p.amountpaid, p.balance, p.paymentstatus::text, p.paymentmethod::text,
           p.genericcashaccountid, p.invoicenumber::text, p.receipturl::text, p.receivedbystaffid,
           p.status::text, p.notes::text, p.createdby::text, p.approvedby::text, p.approvedat,
           p.cancelledby::text, p.cancelledat, p.cancellationreason::text,
           p.createdat, p.updatedat,
           p.purchasereversalid, r.reversalnumber
    FROM   genericpurchases p
    LEFT   JOIN genericsuppliers s ON s.genericsupplierid = p.genericsupplierid
    LEFT   JOIN genericpurchasereversals r ON r.purchasereversalid = p.purchasereversalid
    WHERE  p.farmid = p_farmid AND p.isdeleted = FALSE
       AND (p_status IS NULL OR p.status = p_status)
    ORDER  BY p.purchasedate DESC, p.genericpurchaseid DESC;
END;
$function$;

-- ------------------------------------------- 8. supplier payment reverse -----
-- Live body (449) + one refusal: a purchase-reversal credit has no cash, so
-- reversing it would make the supplier's credit vanish.
CREATE OR REPLACE FUNCTION public.spgenericsupplierpayment_reverse(p_farmid text, p_paymentid integer, p_reason text DEFAULT NULL::text, p_reversedby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_now      timestamp := (now() at time zone 'utc');
    v_sp       genericsupplierpayments%ROWTYPE;
    v_own      numeric(14,2) := 0;
    v_count    integer := 0;
    v_row      record;
BEGIN
    SELECT * INTO v_sp FROM genericsupplierpayments sp
    WHERE  sp.genericsupplierpaymentid = p_paymentid AND sp.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment not found for this company.';
    END IF;
    IF COALESCE(v_sp.status, '') = 'Reversed' THEN
        RAISE EXCEPTION 'Only a posted payment can be reversed (this one is Reversed).';
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a payment.';
    END IF;
    IF v_sp.sourcetype = 'PurchaseReversalCredit' THEN   -- 500
        RAISE EXCEPTION 'This is credit kept from a reversed purchase (%). It cannot be reversed; use it on a bill or refund it on Supplier Credits.',
            COALESCE(v_sp.referenceno, '') USING ERRCODE = 'P0001';
    END IF;
    IF public.fngenericsupplier_iscreditkind(v_sp.sourcetype) THEN
        RETURN public.spgenericsuppliercredit_reverse(p_farmid, p_paymentid, p_reason, p_reversedby);
    END IF;
    IF EXISTS (SELECT 1 FROM supplierpaymentallocation sa WHERE sa.farmid = p_farmid AND sa.module = 'generic'
               AND sa.paymentid = p_paymentid AND sa.status = 'Posted' AND sa.fromcredit) THEN
        RAISE EXCEPTION 'Part of this payment''s credit has been applied. Undo those applications on Supplier Credits first.';
    END IF;
    IF EXISTS (SELECT 1 FROM genericsupplierrefundlines rl JOIN genericsupplierrefunds r ON r.refundid = rl.refundid
               WHERE rl.farmid = p_farmid AND rl.genericsupplierpaymentid = p_paymentid AND r.status = 'Posted') THEN
        RAISE EXCEPTION 'Part of this payment''s credit has been refunded. Reverse the refund on Supplier Credits first.';
    END IF;
    FOR v_row IN
        SELECT sa.allocationid, sa.documenttype, sa.documentid, sa.amountapplied
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = 'generic'
          AND  sa.paymentid = p_paymentid AND sa.status = 'Posted' AND NOT sa.fromcredit
    LOOP
        PERFORM public.fngenericpayable_addpaid(p_farmid, v_row.documenttype, v_row.documentid, -v_row.amountapplied);
        UPDATE supplierpaymentallocation SET status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
               reversalreason = p_reason
        WHERE  allocationid = v_row.allocationid;
        v_own := v_own + v_row.amountapplied;
        v_count := v_count + 1;
    END LOOP;
    -- An old Draft/Approve payment (no sourcetype) took its whole amount off the ledger.
    IF v_sp.sourcetype IS NULL THEN v_own := v_sp.amount; END IF;
    PERFORM public.fngenericsupplier_ledgermove(p_farmid, v_sp.genericsupplierid, v_own, 'PaymentReversal',
        'Reversal of payment #' || p_paymentid::text || ': ' || p_reason, p_reversedby, p_paymentid);
    IF v_sp.genericcashaccountid IS NOT NULL THEN
        PERFORM public.fngenericcash_move(p_farmid, v_sp.genericcashaccountid, v_sp.amount, v_now, 'SupplierPayment',
            p_paymentid, 'Reversal of payment #' || p_paymentid::text, p_reversedby);
    END IF;
    UPDATE genericsupplierpayments
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason, updatedat = v_now
    WHERE  genericsupplierpaymentid = p_paymentid AND farmid = p_farmid;
    RETURN v_count;
END;
$function$;

-- ------------------------------------------------------------- 9. cash flow --
-- Rebuilt from the live body (pg_get_functiondef) + three 500 edits.
CREATE OR REPLACE FUNCTION public.spgenericcashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, createdat timestamp without time zone)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);
    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);
BEGIN
    -- ---- 1. customer receipts ---------------------------------------------------
    RETURN QUERY
    SELECT 'Receipt'::text, FALSE,
           p.genericcustomerpaymentid, p.genericcashaccountid, NULL::text,
           p.paymentdate::timestamp, 'CashIn'::text, 'CustomerPayment'::text,
           p.genericcustomerpaymentid, FALSE,
           COALESCE(p.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(p.notes), ''), NULLIF(btrim(p.referenceno), ''),
                    'Customer payment #' || p.genericcustomerpaymentid::text)::text,
           'OperatingIn'::text, p.createdat::timestamp
    FROM   genericcustomerpayments p
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) > 0
      -- 483: a reversed payment WAS received on its day; its reversal is its own row (1b)
      AND  p.paymentdate::timestamp >= v_from
      AND  p.paymentdate::timestamp <= v_to;

    -- ---- 2. sale residuals (part paid at counter) -------------------------------
    RETURN QUERY
    SELECT 'SaleResidual'::text, FALSE,
           s.genericsaleid, s.genericcashaccountid, NULL::text,
           s.saledate::timestamp, 'CashIn'::text, 'Sale'::text,
           s.genericsaleid, FALSE, v.residual,
           ('Sale #' || s.genericsaleid::text ||
            COALESCE(' - ' || NULLIF(btrim(c.customername), ''), ''))::text,
           'OperatingIn'::text, s.createdat::timestamp
    FROM   genericsales s
    LEFT   JOIN genericcustomers c ON c.genericcustomerid = s.genericcustomerid
    CROSS  JOIN LATERAL (
        SELECT ROUND(
                   CASE WHEN COALESCE(s.paymentstatus, '') = 'Paid'
                        THEN COALESCE(s.totalamount, 0)
                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),
                                   COALESCE(s.totalamount, 0))
                   END
                 - COALESCE((SELECT SUM(ca.amountapplied)   -- 489: payments applied through allocations
                             FROM   customerpaymentallocation ca
                             WHERE  ca.module = 'generic' AND ca.saleid = s.genericsaleid
                               AND  lower(ca.farmid::text) = lower(p_farmid) AND ca.status = 'Posted'), 0)
                 - COALESCE((SELECT SUM(pp.amount)
                             FROM   genericcustomerpayments pp
                             WHERE  pp.linkedsaleid = s.genericsaleid
                               AND  lower(pp.farmid::text) = lower(p_farmid)
                               -- 483: reversed payments stay counted (receipt kept, reversal in 1b)
                               ), 0)
               , 2) AS residual
    ) v
    WHERE  lower(s.farmid::text) = lower(p_farmid)
      AND  COALESCE(s.isdeleted, FALSE) = FALSE
      -- 483: only money a sale actually took: approved, or approved then refunded / reversed (not drafts)
      AND  (s.status IN ('Approved', 'Refunded') OR s.salereversalid IS NOT NULL)
      AND  v.residual > 0
      AND  s.saledate::timestamp >= v_from
      AND  s.saledate::timestamp <= v_to;

    -- ---- 1b. reversed customer payments: money back out on the day of the reversal (483)
    RETURN QUERY
    SELECT 'ReceiptReversal'::text, FALSE,
           p.genericcustomerpaymentid::integer, p.genericcashaccountid::integer, NULL::text,
           p.reversedat::timestamp, 'CashOut'::text, 'CustomerPaymentReversal'::text,
           p.genericcustomerpaymentid, FALSE,
           -COALESCE(p.amount, 0)::numeric,
           ('Reversal of customer payment #' || p.genericcustomerpaymentid::text
            || COALESCE(': ' || NULLIF(btrim(p.reversalreason), ''), ''))::text,
           'OperatingOut'::text, p.reversedat::timestamp
    FROM   genericcustomerpayments p
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) > 0
      AND  p.status = 'Reversed' AND p.reversedat IS NOT NULL
      AND  p.genericcashaccountid IS NOT NULL
      AND  p.reversedat::timestamp >= v_from
      AND  p.reversedat::timestamp <= v_to;

    -- ---- 1c. sale refunds paid out of a cash account (old Refund, 483 SaleReversal) --
    RETURN QUERY
    SELECT 'SaleRefund'::text, FALSE,
           t.genericcashtransactionid::integer, t.genericcashaccountid::integer, NULL::text,
           t.transactiondate::timestamp, 'CashOut'::text, t.sourcetype::text,
           t.sourceid::integer, FALSE,
           -ABS(COALESCE(t.amount, 0))::numeric,
           COALESCE(NULLIF(btrim(t.description), ''), 'Sale refund')::text,
           'OperatingOut'::text, t.transactiondate::timestamp
    FROM   genericcashtransactions t
    WHERE  lower(t.farmid::text) = lower(p_farmid)
      AND  t.transactiontype = 'CashOut'
      AND  t.sourcetype IN ('Refund', 'SaleReversal')
      AND  COALESCE(t.amount, 0) <> 0
      AND  t.transactiondate::timestamp >= v_from
      AND  t.transactiondate::timestamp <= v_to;

    -- ---- 3. expenses (operational spending) ------------------------------------
    RETURN QUERY
    SELECT 'Expense'::text, FALSE,
           e.genericexpenseid, e.genericcashaccountid, NULL::text,
           e.expensedate::timestamp, 'CashOut'::text, 'Expense'::text,
           e.genericexpenseid, FALSE,
           -COALESCE(e.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(e.description), ''), 'Expense')::text,
           'OperatingOut'::text, e.createdat::timestamp
    FROM   genericexpenses e
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(e.amount, 0) > 0
      AND  COALESCE(e.isdeleted, FALSE) = FALSE
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
      AND  e.expensedate::timestamp >= v_from
      AND  e.expensedate::timestamp <= v_to;

    -- ---- 4. payroll (only paid runs WITHOUT a linked expense) ------------------
    IF to_regclass('public.genericpayrollruns') IS NOT NULL THEN
        RETURN QUERY EXECUTE format($sql$
            SELECT 'Payroll'::text, FALSE,
                   pr.genericpayrollrunid, pr.genericcashaccountid, NULL::text,
                   COALESCE(pr.paidat, pr.createdat)::timestamp, 'CashOut'::text,
                   'Payroll'::text, pr.genericpayrollrunid, FALSE,
                   -COALESCE(pr.totalnetpay, 0)::numeric,
                   COALESCE(NULLIF(btrim(pr.notes), ''),
                            'Payroll ' || to_char(pr.periodstart, 'DD Mon') || ' - ' || to_char(pr.periodend, 'DD Mon YYYY'))::text,
                   'OperatingOut'::text, pr.createdat::timestamp
            FROM   genericpayrollruns pr
            WHERE  lower(pr.farmid::text) = lower($1)
              AND  pr.status = 'Paid'
              AND  COALESCE(pr.totalnetpay, 0) > 0
              AND  COALESCE(pr.isdeleted, FALSE) = FALSE
              AND  NOT EXISTS (
                       SELECT 1 FROM genericexpenses e
                       WHERE  e.sourcetype = 'Payroll'
                         AND  e.sourceid = pr.genericpayrollrunid
                         AND  lower(e.farmid::text) = lower($1)
                         AND  COALESCE(e.isdeleted, FALSE) = FALSE
                   )
              AND  COALESCE(pr.paidat, pr.createdat)::timestamp >= $2
              AND  COALESCE(pr.paidat, pr.createdat)::timestamp <= $3
        $sql$)
        USING p_farmid, v_from, v_to;
    END IF;

    -- ---- 5. owner contributions (financing in) --------------------------------
    RETURN QUERY
    SELECT 'OwnerContribution'::text, FALSE,
           oc.genericownerentryid, oc.genericcashaccountid, NULL::text,
           oc.entrydate::timestamp, 'CashIn'::text, 'OwnerInjection'::text,
           oc.genericownerentryid, FALSE,
           COALESCE(oc.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(oc.notes), ''),
                    'Owner contribution' || COALESCE(' - ' || NULLIF(btrim(oc.ownername), ''), ''))::text,
           'FinancingIn'::text, oc.createdat::timestamp
    FROM   genericownercontributiondraws oc
    WHERE  lower(oc.farmid::text) = lower(p_farmid)
      AND  oc.entrytype = 'Contribution' AND oc.status = 'Posted'
      AND  COALESCE(oc.amount, 0) > 0
      AND  oc.entrydate::timestamp >= v_from
      AND  oc.entrydate::timestamp <= v_to;

    -- ---- 6. owner draws (financing out) ----------------------------------------
    RETURN QUERY
    SELECT 'OwnerDraw'::text, FALSE,
           oc.genericownerentryid, oc.genericcashaccountid, NULL::text,
           oc.entrydate::timestamp, 'CashOut'::text, 'Withdrawal'::text,
           oc.genericownerentryid, FALSE,
           -COALESCE(oc.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(oc.notes), ''),
                    'Owner draw' || COALESCE(' - ' || NULLIF(btrim(oc.ownername), ''), ''))::text,
           'FinancingOut'::text, oc.createdat::timestamp
    FROM   genericownercontributiondraws oc
    WHERE  lower(oc.farmid::text) = lower(p_farmid)
      AND  oc.entrytype = 'Draw' AND oc.status = 'Posted'
      AND  COALESCE(oc.amount, 0) > 0
      AND  oc.entrydate::timestamp >= v_from
      AND  oc.entrydate::timestamp <= v_to;

    -- ---- 7. loans received (financing in) --------------------------------------
    IF to_regclass('public."GenericLoans"') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'LoanReceived'::text, FALSE,
               l."GenericLoanId", l."GenericCashAccountId", NULL::text,
               COALESCE(l."LoanDate", l."CreatedAt")::timestamp, 'CashIn'::text,
               'LoanReceived'::text, l."GenericLoanId", FALSE,
               COALESCE(l."AmountReceived", 0)::numeric,
               COALESCE(NULLIF(btrim(l."Notes"), ''),
                        'Loan from ' || COALESCE(NULLIF(btrim(l."LenderName"), ''), 'unknown lender'))::text,
               'FinancingIn'::text, l."CreatedAt"::timestamp
        FROM   "GenericLoans" l
        WHERE  l."FarmId" = p_farmid
          AND  l."Status" IN ('Active', 'Paid')
          AND  COALESCE(l."AmountReceived", 0) > 0
          AND  COALESCE(l."LoanDate", l."CreatedAt")::timestamp >= v_from
          AND  COALESCE(l."LoanDate", l."CreatedAt")::timestamp <= v_to;
    END IF;

    -- ---- 8. loan repayments (financing out) ------------------------------------
    IF to_regclass('public."GenericLoanPayments"') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'LoanRepayment'::text, FALSE,
               lp."GenericLoanPaymentId", lp."GenericCashAccountId", NULL::text,
               lp."PaymentDate"::timestamp, 'CashOut'::text,
               'LoanRepayment'::text, lp."GenericLoanPaymentId", FALSE,
               -COALESCE(lp."TotalPayment", 0)::numeric,
               COALESCE(NULLIF(btrim(lp."Notes"), ''),
                        'Loan repayment #' || lp."GenericLoanPaymentId"::text)::text,
               'FinancingOut'::text, lp."CreatedAt"::timestamp
        FROM   "GenericLoanPayments" lp
        WHERE  lp."FarmId" = p_farmid
          AND  COALESCE(lp."IsReversed", FALSE) = FALSE
          AND  COALESCE(lp."TotalPayment", 0) > 0
          AND  lp."PaymentDate"::timestamp >= v_from
          AND  lp."PaymentDate"::timestamp <= v_to;
    END IF;

    -- ---- 9. legacy cash adjustments --------------------------------------------
    IF to_regclass('public.cashadjustment') IS NOT NULL OR
       to_regclass('public.cashadjustments') IS NOT NULL THEN
        RETURN QUERY EXECUTE format($sql$
            SELECT 'Adjustment'::text, FALSE,
                   ca.adjustmentid, NULL::integer, NULL::text,
                   ca.adjustmentdate,
                   CASE WHEN ca.amount >= 0 THEN 'CashIn' ELSE 'CashOut' END::text,
                   COALESCE(NULLIF(btrim(ca.adjustmenttype), ''), 'Adjustment')::text,
                   ca.adjustmentid, FALSE,
                   ca.amount::numeric,
                   COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text,
                   CASE WHEN ca.amount >= 0 THEN 'FinancingIn' ELSE 'FinancingOut' END::text,
                   NULL::timestamp
            FROM   %s ca
            WHERE  lower(ca.farmid::text) = lower($1)
              AND  ca.amount <> 0
              AND  ca.adjustmentdate >= $2
              AND  ca.adjustmentdate <= $3
        $sql$, COALESCE(to_regclass('public.cashadjustment')::text,
                        to_regclass('public.cashadjustments')::text))
        USING p_farmid, v_from, v_to;
    END IF;

    -- ========================================================================
    -- NEW (474): Purchase cash-out — the AmountPaid portion of approved
    -- purchases. This is money that left the business to pay for goods.
    -- ========================================================================
    RETURN QUERY
    SELECT 'PurchasePayment'::text, FALSE,
           pu.genericpurchaseid,
           pu.genericcashaccountid,
           NULL::text,
           pu.purchasedate::timestamp,
           'CashOut'::text,
           'Purchase'::text,
           pu.genericpurchaseid,
           FALSE,
           -COALESCE(pu.amountpaid, 0)::numeric,
           ('Purchase ' || COALESCE(NULLIF(btrim(pu.invoicenumber), ''), '#' || pu.genericpurchaseid::text)
            || COALESCE(' - ' || NULLIF(btrim(sp.suppliername), ''), ''))::text,
           'OperatingOut'::text,
           pu.createdat::timestamp
    FROM   genericpurchases pu
    LEFT   JOIN genericsuppliers sp ON sp.genericsupplierid = pu.genericsupplierid
    WHERE  lower(pu.farmid::text) = lower(p_farmid)
      AND  (pu.status = 'Approved' OR pu.purchasereversalid IS NOT NULL)   -- 500: reversed keeps its day
      AND  COALESCE(pu.isdeleted, FALSE) = FALSE
      AND  COALESCE(pu.amountpaid, 0) > 0
      AND  pu.purchasedate::timestamp >= v_from
      AND  pu.purchasedate::timestamp <= v_to;

    -- ========================================================================
    -- NEW (474): Supplier payments — standalone payments against outstanding
    -- supplier balances (purchases or expenses on credit).
    -- ========================================================================
    RETURN QUERY
    SELECT 'SupplierPayment'::text, FALSE,
           sp.genericsupplierpaymentid,
           sp.genericcashaccountid,
           NULL::text,
           sp.paymentdate::timestamp,
           'CashOut'::text,
           'SupplierPayment'::text,
           sp.genericsupplierpaymentid,
           FALSE,
           -COALESCE(sp.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(sp.notes), ''),
                    'Supplier payment #' || sp.genericsupplierpaymentid::text
                    || COALESCE(' - ' || NULLIF(btrim(sv.suppliername), ''), ''))::text,
           'OperatingOut'::text,
           sp.createdat::timestamp
    FROM   genericsupplierpayments sp
    LEFT   JOIN genericsuppliers sv ON sv.genericsupplierid = sp.genericsupplierid
    WHERE  lower(sp.farmid::text) = lower(p_farmid)
      AND  sp.status = 'Approved'
      AND  COALESCE(sp.sourcetype, '') <> 'PurchaseReversalCredit'   -- 500: kept as credit, no cash
      AND  COALESCE(sp.amount, 0) > 0
      AND  sp.paymentdate::timestamp >= v_from
      AND  sp.paymentdate::timestamp <= v_to;
    -- ========================================================================
    -- 500: a reversed purchase the supplier refunded -- money back in on the
    -- day of the reversal (its payment at entry stays on its own day above).
    -- ========================================================================
    RETURN QUERY
    SELECT 'PurchaseRefund'::text, FALSE,
           t.genericcashtransactionid::integer, t.genericcashaccountid::integer, NULL::text,
           t.transactiondate::timestamp, 'CashIn'::text, 'PurchaseReversal'::text,
           t.sourceid::integer, FALSE,
           ABS(COALESCE(t.amount, 0))::numeric,
           COALESCE(NULLIF(btrim(t.description), ''), 'Purchase refund')::text,
           'OperatingIn'::text, t.transactiondate::timestamp
    FROM   genericcashtransactions t
    WHERE  lower(t.farmid::text) = lower(p_farmid)
      AND  t.transactiontype = 'CashIn'
      AND  t.sourcetype = 'PurchaseReversal'
      AND  COALESCE(t.amount, 0) <> 0
      AND  t.transactiondate::timestamp >= v_from
      AND  t.transactiondate::timestamp <= v_to;
END;
$function$;

-- Cash Flow detail: the refund gets its own category (live body + one line).
CREATE OR REPLACE FUNCTION public.spgenericcashflow_detail(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, category text, createdat timestamp without time zone)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname,
           r.transactiondate, r.transactiontype, r.sourcetype, r.sourceid,
           r.istransfer, r.amount, r.description, r.flowgroup,
           CASE
               WHEN r.rowsource = 'Expense'
                   THEN COALESCE(NULLIF(btrim(ec.name), ''), 'Uncategorised')
               WHEN r.rowsource = 'Receipt'
                   THEN COALESCE('Sales revenue (' || NULLIF(btrim(gp.paymentmethod), '') || ')', 'Sales revenue')
               WHEN r.rowsource = 'SaleResidual'       THEN 'Sales'
               WHEN r.rowsource = 'Payroll'             THEN 'Staff wages'
               WHEN r.rowsource = 'OwnerContribution'   THEN 'Owner contribution'
               WHEN r.rowsource = 'OwnerDraw'           THEN 'Owner draw'
               WHEN r.rowsource = 'LoanReceived'        THEN 'Loan received'
               WHEN r.rowsource = 'LoanRepayment'       THEN 'Loan repayment'
               WHEN r.rowsource = 'PurchasePayment'     THEN 'Purchases'
               WHEN r.rowsource = 'SupplierPayment'     THEN 'Supplier payments'
               WHEN r.rowsource = 'PurchaseRefund'      THEN 'Purchase refunds'   -- 500
               WHEN r.rowsource = 'Adjustment'
                   THEN COALESCE(NULLIF(btrim(r.sourcetype), ''), 'Adjustment')
               ELSE 'Other'
           END::text,
           r.createdat
    FROM   public.spgenericcashflow_rows(p_farmid, p_fromdate, p_todate) r
    LEFT   JOIN genericexpenses ge
           ON  r.rowsource = 'Expense'
           AND ge.genericexpenseid = r.sourcerowid
           AND lower(ge.farmid::text) = lower(p_farmid)
    LEFT   JOIN genericexpensecategories ec
           ON  ge.genericexpensecategoryid = ec.genericexpensecategoryid
    LEFT   JOIN genericcustomerpayments gp
           ON  r.rowsource = 'Receipt'
           AND gp.genericcustomerpaymentid = r.sourcerowid
           AND lower(gp.farmid::text) = lower(p_farmid);
$function$;

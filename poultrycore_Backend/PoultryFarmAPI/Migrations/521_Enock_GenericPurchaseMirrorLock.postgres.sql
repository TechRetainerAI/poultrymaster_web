-- =============================================================================
-- 521_Enock_GenericPurchaseMirrorLock.postgres.sql
--
-- A purchase recorded + approved on Inventory & Purchases is reversed THERE
-- ONLY. The expense and supplier payment that approve (513/517) writes for it
-- are copies for display; reversing them on Expenses or Supplier Payments put
-- money back in the cash account and a fake debt on the supplier (seen on dev
-- 2026-11-28: payment #100, copy of purchase #148).
--
--   1. The copy expense is tagged sourcetype 'Purchase' / sourceid = purchase
--      again (513 did; 517 dropped it). 504 already refuses to reverse, edit
--      or delete a sourced expense ("made by Purchase -- reverse it there"),
--      the Expenses page already hides its actions for sourceType 'Purchase',
--      and fngenericpayables stops listing it as a second bill to pay.
--   2. The copy supplier payment stays sourcetype NULL ON PURPOSE: a payment
--      with a sourcetype and no allocations counts as unspent supplier credit
--      (fngenericsupplierpayment_isposted / _unapplied). The history list only
--      REPORTS it as 'PurchaseEntry' so the page can hide Reverse.
--   3. Lock triggers on both tables refuse any status / amount / delete change
--      to a copy, from any page or API, unless spgenericpurchase_reverse is
--      the caller (GUC generic.purchase_system).
--
-- Needs 519. Bodies are the LIVE ones (pg_get_functiondef 2026-11-28), with
-- only the "521" lines added. Idempotent. Not touched: 520's functions.
-- =============================================================================

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fngenericpurchase_ismirrorpayment') THEN
    RAISE EXCEPTION '521 needs 519_Enock_GenericPurchaseMirrorRows first.';
  END IF;
END $$;

-- ------------------------------------------------------------ 1. backfill --
-- A copy already reversed on Expenses (dev: #155) is tagged too; only the tag
-- changes, so the 504 reversed-expense lock is passed for this statement.
SELECT set_config('generic.expense_system', 'on', true);
UPDATE genericexpenses e
SET    sourcetype = 'Purchase', sourceid = pu.genericpurchaseid
FROM   genericpurchases pu
WHERE  pu.genericexpenseid = e.genericexpenseid AND pu.farmid = e.farmid
  AND  e.sourcetype IS NULL;
SELECT set_config('generic.expense_system', 'off', true);

-- ------------------------------------------------------------- 2. locks ----
CREATE OR REPLACE FUNCTION public.trg_genericpurchase_mirrorlock_fn()
RETURNS trigger LANGUAGE plpgsql AS $f$
DECLARE v_pu integer;
BEGIN
    IF COALESCE(current_setting('generic.purchase_system', true), '') = 'on' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    IF TG_TABLE_NAME = 'genericexpenses' THEN
        SELECT pu.genericpurchaseid INTO v_pu FROM genericpurchases pu WHERE pu.genericexpenseid = OLD.genericexpenseid LIMIT 1;
        IF v_pu IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;
        IF TG_OP = 'UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status AND NEW.amount IS NOT DISTINCT FROM OLD.amount
           AND NEW.isdeleted IS NOT DISTINCT FROM OLD.isdeleted AND NEW.expensereversalid IS NOT DISTINCT FROM OLD.expensereversalid
           AND NEW.amountpaid IS NOT DISTINCT FROM OLD.amountpaid THEN
            RETURN NEW;
        END IF;
        RAISE EXCEPTION 'This expense was created by purchase #% on Inventory & Purchases. Reverse the purchase there.', v_pu
            USING ERRCODE = 'P0001';
    ELSE
        IF NOT public.fngenericpurchase_ismirrorpayment(OLD.linkedpurchaseid, OLD.linkedexpenseid) THEN
            RETURN COALESCE(NEW, OLD);
        END IF;
        IF TG_OP = 'UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status AND NEW.amount IS NOT DISTINCT FROM OLD.amount
           AND NEW.reversedat IS NOT DISTINCT FROM OLD.reversedat THEN
            RETURN NEW;
        END IF;
        RAISE EXCEPTION 'This payment was made with purchase #% on Inventory & Purchases. Reverse the purchase there.', OLD.linkedpurchaseid
            USING ERRCODE = 'P0001';
    END IF;
END $f$;

DROP TRIGGER IF EXISTS trg_genericexpense_purchasemirrorlock ON public.genericexpenses;
CREATE TRIGGER trg_genericexpense_purchasemirrorlock
    BEFORE UPDATE OR DELETE ON public.genericexpenses
    FOR EACH ROW EXECUTE FUNCTION public.trg_genericpurchase_mirrorlock_fn();

DROP TRIGGER IF EXISTS trg_genericsupplierpayment_purchasemirrorlock ON public.genericsupplierpayments;
CREATE TRIGGER trg_genericsupplierpayment_purchasemirrorlock
    BEFORE UPDATE OR DELETE ON public.genericsupplierpayments
    FOR EACH ROW EXECUTE FUNCTION public.trg_genericpurchase_mirrorlock_fn();

CREATE OR REPLACE FUNCTION public.spgenericpurchase_approve(p_genericpurchaseid integer, p_farmid text, p_approvedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_supplierid integer;
    v_cashaccountid integer;
    v_amountpaid numeric;
    v_balance numeric;
    v_purchasedate timestamp;
    v_invoicenumber text;
    v_totalamount numeric;
    v_cashnewbalance numeric := NULL;
    v_cashallowneg boolean;
    v_cashcurrent numeric;
    v_suppliernewbalance numeric;
    v_expenseid integer;
    v_suppliername text;
    v_expensecategoryid integer;
BEGIN
    -- Idempotent: already approved → no-op.
    IF EXISTS (SELECT 1 FROM genericpurchases pu
               WHERE  pu.genericpurchaseid = p_genericpurchaseid AND pu.farmid = p_farmid
                  AND pu.status = 'Approved') THEN
        RETURN;
    END IF;

    SELECT pu.status, pu.genericsupplierid, pu.genericcashaccountid,
           pu.amountpaid, pu.balance, pu.purchasedate, pu.invoicenumber, pu.totalamount
    INTO   v_status, v_supplierid, v_cashaccountid,
           v_amountpaid, v_balance, v_purchasedate, v_invoicenumber, v_totalamount
    FROM   genericpurchases pu
    WHERE  pu.genericpurchaseid = p_genericpurchaseid AND pu.farmid = p_farmid
       AND pu.isdeleted = FALSE
    LIMIT 1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Purchase % not found.', p_genericpurchaseid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Purchase cannot be approved from status %.', v_status;
    END IF;
    IF (v_amountpaid > 0 AND v_cashaccountid IS NULL) THEN
        RAISE EXCEPTION 'AmountPaid is greater than zero but no GenericCashAccountId is set.';
    END IF;
    IF (v_balance > 0 AND v_supplierid IS NULL) THEN
        RAISE EXCEPTION 'Purchase has an unpaid balance but no supplier is attached.';
    END IF;

    -- Resolve supplier name for descriptions.
    IF v_supplierid IS NOT NULL THEN
        SELECT s.suppliername INTO v_suppliername
        FROM   genericsuppliers s
        WHERE  s.genericsupplierid = v_supplierid AND s.farmid = p_farmid;
    END IF;

    -- 517: resolve the expense category for the auto-created expense.
    -- Prefer "Inventory Purchases", fall back to any category on this farm.
    SELECT c.genericexpensecategoryid INTO v_expensecategoryid
    FROM   genericexpensecategories c
    WHERE  c.farmid = p_farmid AND c.name = 'Inventory Purchases'
    LIMIT 1;
    IF v_expensecategoryid IS NULL THEN
        SELECT c.genericexpensecategoryid INTO v_expensecategoryid
        FROM   genericexpensecategories c
        WHERE  c.farmid = p_farmid
        ORDER  BY c.genericexpensecategoryid
        LIMIT 1;
    END IF;
    -- If still null (no categories at all), create "Inventory Purchases".
    IF v_expensecategoryid IS NULL THEN
        INSERT INTO genericexpensecategories (farmid, name, createdat)
        VALUES (p_farmid, 'Inventory Purchases', (now() at time zone 'utc'))
        RETURNING genericexpensecategoryid INTO v_expensecategoryid;
    END IF;

    -- Cash overdraft check.
    IF (v_amountpaid > 0) THEN
        SELECT ca.allownegativebalance, ca.currentbalance
        INTO   v_cashallowneg, v_cashcurrent
        FROM   genericcashaccounts ca
        WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid
        LIMIT 1;

        IF v_cashcurrent IS NULL THEN
            RAISE EXCEPTION 'Cash account on the purchase does not exist or belongs to another farm.';
        END IF;
        v_cashnewbalance := v_cashcurrent - v_amountpaid;
        IF (v_cashnewbalance < 0 AND v_cashallowneg = FALSE) THEN
            RAISE EXCEPTION 'Purchase would push cash account negative; account does not allow it.';
        END IF;
    END IF;

    -- Mark approved.
    UPDATE genericpurchases pu
    SET    status = 'Approved', approvedby = p_approvedby,
           approvedat = (now() at time zone 'utc'), updatedat = (now() at time zone 'utc')
    WHERE  pu.genericpurchaseid = p_genericpurchaseid AND pu.farmid = p_farmid;

    -- Inventory: stock in (base units, applying unitfactor from 472).
    INSERT INTO genericstockmovements (
        farmid, genericproductid, movementdate, movementtype, quantity,
        unitcost, totalcostvalue, referencetype, referenceid,
        reason, createdby, approvedby, approvedat
    )
    SELECT p_farmid, i.genericproductid, v_purchasedate, 'PurchaseIn', i.quantity * i.unitfactor,
           i.unitcost / i.unitfactor, i.unitcost * i.quantity, 'Purchase', p_genericpurchaseid,
           'Purchase ' || COALESCE(v_invoicenumber, p_genericpurchaseid::text)
               || CASE WHEN i.purchaseunit IS NOT NULL AND i.unitfactor <> 1
                       THEN ' (' || trim(to_char(i.quantity, 'FM999999999990.###')) || ' ' || i.purchaseunit || ')'
                       ELSE '' END,
           p_approvedby, p_approvedby, (now() at time zone 'utc')
    FROM   genericpurchaseitems i
    INNER  JOIN genericproducts p
        ON p.genericproductid = i.genericproductid AND p.farmid = p_farmid
    WHERE  i.genericpurchaseid = p_genericpurchaseid
       AND p.trackinventory = TRUE;

    UPDATE genericproducts p
    SET    currentstock = p.currentstock + x.qty,
           updatedat    = (now() at time zone 'utc')
    FROM   (SELECT i.genericproductid, SUM(i.quantity * i.unitfactor) AS qty
            FROM   genericpurchaseitems i
            WHERE  i.genericpurchaseid = p_genericpurchaseid AND i.farmid = p_farmid
            GROUP  BY i.genericproductid) x
    WHERE  x.genericproductid = p.genericproductid
       AND p.trackinventory = TRUE
       AND p.farmid = p_farmid;

    -- Cash out.
    IF (v_amountpaid > 0) THEN
        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, balanceaftertransaction, description,
            createdby, approvedby, approvedat
        )
        VALUES (
            p_farmid, v_cashaccountid, v_purchasedate, 'CashOut',
            'Purchase', p_genericpurchaseid, -v_amountpaid, v_cashnewbalance,
            'Purchase ' || COALESCE(v_invoicenumber, p_genericpurchaseid::text),
            p_approvedby, p_approvedby, (now() at time zone 'utc')
        );

        UPDATE genericcashaccounts ca
        SET    currentbalance = v_cashnewbalance, updatedat = (now() at time zone 'utc')
        WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid;
    END IF;

    -- Supplier ledger (unpaid balance → supplier credit).
    IF (v_balance > 0 AND v_supplierid IS NOT NULL) THEN
        SELECT s.currentbalance + v_balance INTO v_suppliernewbalance
        FROM   genericsuppliers s
        WHERE  s.genericsupplierid = v_supplierid AND s.farmid = p_farmid
        LIMIT 1;

        INSERT INTO genericsupplierledger (
            farmid, genericsupplierid, transactiondate, transactiontype,
            purchaseid, debitamount, creditamount, balanceaftertransaction,
            description, createdby
        )
        VALUES (
            p_farmid, v_supplierid, v_purchasedate, 'PurchaseCredit',
            p_genericpurchaseid, 0, v_balance, v_suppliernewbalance,
            'Credit on purchase ' || COALESCE(v_invoicenumber, p_genericpurchaseid::text),
            p_approvedby
        );

        UPDATE genericsuppliers s
        SET    currentbalance = v_suppliernewbalance, updatedat = (now() at time zone 'utc')
        WHERE  s.genericsupplierid = v_supplierid AND s.farmid = p_farmid;
    END IF;

    -- 517: Create Expense record with the required category.
    INSERT INTO genericexpenses (
        farmid, expensedate, genericexpensecategoryid, amount, description, notes,
        paymentmethod, genericcashaccountid, genericsupplierid,
        amountpaid, status, sourcetype, sourceid,
        createdby, createdat, updatedat
    )
    VALUES (
        p_farmid, v_purchasedate, v_expensecategoryid,
        COALESCE(v_totalamount, v_amountpaid + v_balance),
        'Purchase ' || COALESCE(v_invoicenumber, p_genericpurchaseid::text)
            || COALESCE(' — ' || v_suppliername, ''),
        'Auto-created from purchase approval',
        CASE WHEN v_amountpaid > 0 THEN 'Cash' ELSE 'Credit' END,
        v_cashaccountid, v_supplierid,
        CASE WHEN v_amountpaid > 0 THEN v_amountpaid ELSE NULL END,
        'Approved', 'Purchase', p_genericpurchaseid,   -- 521: 513 had these; 517 dropped them
        p_approvedby,
        (now() at time zone 'utc'), (now() at time zone 'utc')
    )
    RETURNING genericexpenseid INTO v_expenseid;

    -- Link the expense back to the purchase.
    UPDATE genericpurchases pu
    SET    genericexpenseid = v_expenseid
    WHERE  pu.genericpurchaseid = p_genericpurchaseid AND pu.farmid = p_farmid;

    -- Create Supplier Payment record when cash was paid to a supplier.
    IF (v_amountpaid > 0 AND v_supplierid IS NOT NULL) THEN
        INSERT INTO genericsupplierpayments (
            farmid, genericsupplierid, paymentdate, amount,
            paymentmethod, genericcashaccountid,
            referenceno, notes, status,
            linkedpurchaseid, linkedexpenseid,
            createdby, createdat, updatedat
        )
        VALUES (
            p_farmid, v_supplierid, v_purchasedate, v_amountpaid,
            'Cash', v_cashaccountid,
            v_invoicenumber,
            'Auto-created from purchase #' || p_genericpurchaseid::text,
            'Approved',
            p_genericpurchaseid, v_expenseid,
            p_approvedby,
            (now() at time zone 'utc'), (now() at time zone 'utc')
        );
    END IF;
END
$function$;

CREATE OR REPLACE FUNCTION public.spgenericsupplierpayment_history(p_farmid text, p_supplierid integer DEFAULT NULL::integer, p_documenttype text DEFAULT NULL::text, p_documentid integer DEFAULT NULL::integer, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS TABLE(paymentid integer, partyid integer, partyname text, paymentdate timestamp without time zone, totalamount numeric, paymentmethod text, reference text, notes text, sourcetype text, status text, allocationcount integer, cashaccountid integer, createdby text, reversedby text, reversedat timestamp without time zone, reversalreason text, createdat timestamp without time zone)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT sp.genericsupplierpaymentid, sp.genericsupplierid, s.suppliername::text,
           sp.paymentdate, sp.amount, sp.paymentmethod::text, sp.referenceno,
           sp.notes::text,
           -- 521: reported (never stored -- a stored sourcetype would make it credit)
           CASE WHEN public.fngenericpurchase_ismirrorpayment(sp.linkedpurchaseid, sp.linkedexpenseid)
                THEN 'PurchaseEntry' ELSE sp.sourcetype END::text,
           (CASE WHEN COALESCE(sp.status, '') = 'Reversed' THEN 'Reversed' ELSE 'Posted' END)::text,
           (SELECT COUNT(*)::integer FROM supplierpaymentallocation sa
             WHERE sa.farmid = sp.farmid AND sa.module = 'generic'
               AND sa.paymentid = sp.genericsupplierpaymentid),
           sp.genericcashaccountid, sp.createdby, sp.reversedby, sp.reversedat, sp.reversalreason
           , sp.createdat   -- 304: the entry time
    FROM   genericsupplierpayments sp
    LEFT   JOIN genericsuppliers s ON s.genericsupplierid = sp.genericsupplierid
                                  AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  NOT public.fngenericsupplier_iscreditkind(sp.sourcetype)   -- 449
      AND  (p_supplierid IS NULL OR sp.genericsupplierid = p_supplierid)
      AND  (p_from IS NULL OR sp.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR sp.paymentdate::date <= p_to)
      AND  (p_documentid IS NULL OR EXISTS (
               SELECT 1 FROM supplierpaymentallocation sa
               WHERE sa.farmid = sp.farmid AND sa.module = 'generic'
                 AND sa.paymentid = sp.genericsupplierpaymentid
                 AND sa.documentid = p_documentid
                 AND (p_documenttype IS NULL OR sa.documenttype = p_documenttype)))
    ORDER  BY sp.paymentdate DESC, sp.genericsupplierpaymentid DESC;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpurchase_reverse(p_farmid text, p_purchaseid integer, p_reasoncode text, p_reason text, p_handling jsonb DEFAULT '{}'::jsonb, p_expectedfingerprint text DEFAULT NULL::text, p_idempotencykey text DEFAULT NULL::text, p_reversedby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
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
    -- 519: the expense + supplier payment approve (517) wrote for display go with the purchase
    PERFORM set_config('generic.purchase_system', 'on', true);   -- 521: past the mirror lock
    UPDATE genericexpenses e
    SET    status = 'Cancelled', updatedat = v_now
    WHERE  e.farmid = p_farmid AND e.status <> 'Cancelled'
      AND  e.genericexpenseid = (SELECT p.genericexpenseid FROM genericpurchases p
                                 WHERE p.genericpurchaseid = p_purchaseid AND p.farmid = p_farmid);
    UPDATE genericsupplierpayments sp
    SET    status = 'Cancelled', updatedat = v_now
    WHERE  sp.farmid = p_farmid AND sp.linkedpurchaseid = p_purchaseid AND sp.status = 'Approved'
      AND  public.fngenericpurchase_ismirrorpayment(sp.linkedpurchaseid, sp.linkedexpenseid);
    PERFORM set_config('generic.purchase_system', 'off', true);

    RETURN v_id;
END $function$;

COMMIT;

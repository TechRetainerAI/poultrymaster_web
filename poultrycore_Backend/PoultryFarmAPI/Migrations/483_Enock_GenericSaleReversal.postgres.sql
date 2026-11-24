-- =============================================================================
-- 483_Enock_GenericSaleReversal: a Generic sale is REVERSED, never refunded in
-- one click -- the Poultry (351/354) / Water (458) sale reversal model.
-- (requires 473-476 and 482_Enock_GenericWalkInSalePayment)
-- =============================================================================
--
-- WHY
-- ---
-- spgenericsale_refund did everything in one click with no reason asked: the
-- sale became 'Refunded', stock went back, the WHOLE amount paid went out of the
-- cash account, the unpaid part came off the customer. Since 475/476 approval
-- records a customer payment for the money received, and the refund never
-- touched it: the payment stayed Approved (still "received" on Customer
-- Payments) while the cash went out again. No choice to keep the money as
-- customer credit, no preview, no protection against a double click, and the
-- refund's cash-out never reached Cash Flow at all.
--
-- THE RULE FROM HERE ON
-- ---------------------
-- An approved sale is REVERSED (GSR-00001). The reversal:
--   * puts back exactly the stock the sale took out (net of any earlier return);
--   * takes off the customer's account every line the SALE posted (its debit,
--     and any credit applied to it -- that credit is the customer's again);
--   * handles each payment on the sale as the user chooses:
--       ReversePayment  money paid back: a payment record is reversed with the
--                       existing spgenericcustomerpayment_reverse (cash out of
--                       its account, customer adjustment, allocations
--                       released); money taken at the counter before 475
--                       (no payment record) goes out as a 'SaleReversal'
--                       cash-out;
--       KeepAsCredit    the money stays received and becomes customer credit
--                       (the sale's debit is gone, the payment's credit stays).
--     A Customer Balances payment that also paid other invoices can only be
--     kept as credit (reverse the payment itself to refund it). A walk-in sale
--     has nobody to hold credit: refund only.
--   * records who, when, the reason (from the list; "Other" needs a note) and
--     what happened to each payment; marks the sale.
--
-- STATUS: A REVERSED SALE IS 'Cancelled' + salereversalid
-- ------------------------------------------------------
-- Every Generic reader counts status = 'Approved' only (P&L, reports,
-- dashboards, invoices, daily closing, billing). Reusing 'Cancelled' (which
-- until now only drafts reached) keeps every one of them right; the screen says
-- "Reversed" whenever salereversalid is set. Old 'Refunded' sales stay.
--
-- ALSO IN HERE
--   * spgenericsale_refund refuses and points to Reverse.
--   * trg_genericsale_reversedlock: a reversed sale cannot be changed (bypass:
--     GUC generic.sale_system, set only by the reversal).
--   * spgenericcashflow_rows:
--       - a reversed customer payment keeps its receipt on its own day and adds
--         a negative row on the day it was reversed (it used to vanish from its
--         original period);
--       - refund cash-outs (old 'Refund' and new 'SaleReversal') show as money
--         out -- they never reached Cash Flow;
--       - "paid at the counter" residuals count only sales that were approved
--         (a DRAFT sale entered as paid showed as cash received).
-- =============================================================================

-- ------------------------------------------------------------- 1. columns ----
ALTER TABLE public.genericsales ADD COLUMN IF NOT EXISTS reversedat     timestamp NULL;
ALTER TABLE public.genericsales ADD COLUMN IF NOT EXISTS reversedby     text      NULL;
ALTER TABLE public.genericsales ADD COLUMN IF NOT EXISTS reversalreason text      NULL;
ALTER TABLE public.genericsales ADD COLUMN IF NOT EXISTS salereversalid integer   NULL;

-- ------------------------------------------------------------- 2. tables -----
CREATE TABLE IF NOT EXISTS public.genericsalereversals (
    salereversalid    serial        PRIMARY KEY,
    farmid            text          NOT NULL,
    reversalnumber    text          NOT NULL,
    genericsaleid     integer       NOT NULL,
    genericcustomerid integer       NULL,
    customername      text          NULL,
    saledate          timestamp     NULL,
    reasoncode        text          NULL,
    reason            text          NOT NULL,
    businessdate      date          NOT NULL,
    occurredat        timestamp     NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    reversedby        text          NULL,
    paymenthandling   text          NOT NULL,
    totalamount       numeric(14,2) NOT NULL DEFAULT 0,
    paidamount        numeric(14,2) NOT NULL DEFAULT 0,
    outstandingamount numeric(14,2) NOT NULL DEFAULT 0,
    creditcreated     numeric(14,2) NOT NULL DEFAULT 0,
    creditreleased    numeric(14,2) NOT NULL DEFAULT 0,
    cashreversed      numeric(14,2) NOT NULL DEFAULT 0,
    idempotencykey    text          NULL,
    snapshot          jsonb         NULL,
    CONSTRAINT ck_genericsalereversals_handling
        CHECK (paymenthandling IN ('None', 'KeepAsCredit', 'ReversePayment', 'Mixed'))
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericsalereversals_number ON public.genericsalereversals (farmid, reversalnumber);
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericsalereversals_idem   ON public.genericsalereversals (farmid, idempotencykey) WHERE idempotencykey IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericsalereversals_sale   ON public.genericsalereversals (farmid, genericsaleid);

CREATE TABLE IF NOT EXISTS public.genericsalereversalpayments (
    salereversalpaymentid serial        PRIMARY KEY,
    salereversalid        integer       NOT NULL REFERENCES public.genericsalereversals (salereversalid),
    farmid                text          NOT NULL,
    itemkey               text          NOT NULL,     -- pay:{id} | alloc:{id} | AT-SALE
    paymentid             integer       NULL,
    paymentnumbers        text          NULL,
    sourcetype            text          NULL,
    amount                numeric(14,2) NOT NULL,
    action                text          NOT NULL,
    cashtransactionid     integer       NULL,         -- AT-SALE refund cash-out
    CONSTRAINT ck_genericsalereversalpayments_action CHECK (action IN ('KeepAsCredit', 'ReversePayment'))
);
CREATE INDEX IF NOT EXISTS ix_genericsalereversalpayments_rev ON public.genericsalereversalpayments (salereversalid);

-- ------------------------------------------------------------- 3. lock -------
DROP TRIGGER IF EXISTS trg_genericsale_reversedlock ON public.genericsales;
DROP FUNCTION IF EXISTS public.trg_genericsale_reversedlock_fn();
CREATE FUNCTION public.trg_genericsale_reversedlock_fn()
RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
    IF COALESCE(current_setting('generic.sale_system', true), '') = 'on' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    IF OLD.salereversalid IS NOT NULL THEN
        RAISE EXCEPTION 'Sale #% was reversed (%). A reversed sale cannot be changed or deleted.',
            OLD.genericsaleid, COALESCE(OLD.reversalreason, '') USING ERRCODE = 'P0001';
    END IF;
    RETURN COALESCE(NEW, OLD);
END $f$;
CREATE TRIGGER trg_genericsale_reversedlock
    BEFORE UPDATE OR DELETE ON public.genericsales
    FOR EACH ROW EXECUTE FUNCTION public.trg_genericsale_reversedlock_fn();

-- ------------------------------------------------------------- 4. state -------
-- What reversing the sale would do, in the shape the shared Reverse Sale dialog
-- reads (lib/api/sale.ts SaleReversalPreview). Computed from the database only.
DROP FUNCTION IF EXISTS public.fngenericsale_reversalstate(text, integer);
CREATE FUNCTION public.fngenericsale_reversalstate(p_farmid text, p_saleid integer)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE
    s          record;
    v_cust     text;
    v_custbal  numeric(14,2);
    v_blockers jsonb := '[]'::jsonb;
    v_lines    jsonb;
    v_pays     jsonb := '[]'::jsonb;
    v_listed   numeric(14,2) := 0;
    v_resid    numeric(14,2);
    v_credit   numeric(14,2);
    v_r        record;
    v_both     jsonb;
    v_only     jsonb;
    v_fp       text;
BEGIN
    SELECT g.* INTO s FROM genericsales g WHERE g.genericsaleid = p_saleid AND g.farmid = p_farmid AND NOT COALESCE(g.isdeleted, false);
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', false, 'saleId', p_saleid, 'blockers',
            jsonb_build_array(jsonb_build_object('code', 'NotFound', 'message', 'Sale not found for this company.')),
            'payments', '[]'::jsonb, 'lines', '[]'::jsonb, 'fingerprint', '');
    END IF;

    IF s.genericcustomerid IS NOT NULL THEN
        SELECT c.customername, c.currentbalance INTO v_cust, v_custbal
        FROM genericcustomers c WHERE c.genericcustomerid = s.genericcustomerid AND c.farmid = p_farmid;
    END IF;

    -- blockers
    IF s.salereversalid IS NOT NULL THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'AlreadyReversed', 'message', 'This sale has already been reversed.');
    ELSIF s.status = 'Draft' THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'Draft', 'message', 'This sale is still a draft: nothing was posted. Cancel the draft instead.');
    ELSIF s.status = 'Refunded' THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'Refunded', 'message', 'This sale was already refunded (before reversals existed).');
    ELSIF s.status <> 'Approved' THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'NotApproved', 'message', format('Only an approved sale can be reversed (this one is %s).', s.status));
    END IF;
    IF s.genericsubscriptionid IS NOT NULL THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'SubscriptionInvoice', 'message',
            'This is a subscription invoice. Reversing it would let the next billing run raise it again; correct it from the subscription instead.');
    END IF;

    -- lines: what goes back into stock
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'saleId', i.genericsaleid,
               'product', COALESCE(p.productname, i.description, 'Item'),
               'quantity', i.quantity, 'unitPrice', i.unitprice, 'total', i.linetotal,
               'size', NULL, 'eggProductId', NULL,
               'restoreProductId', CASE WHEN p.trackinventory THEN p.genericproductid END,
               'restoreProductName', p.productname,
               'restoreQuantity', CASE WHEN i.itemtype = 'Product' AND COALESCE(p.trackinventory, false) THEN i.quantity ELSE 0 END,
               'restoreUnit', COALESCE(NULLIF(btrim(i.saleunit), ''), NULLIF(btrim(p.salesunit), ''), NULLIF(btrim(p.unitofmeasure), ''), 'units')
           ) ORDER BY i.genericsaleitemid), '[]'::jsonb)
    INTO v_lines
    FROM genericsaleitems i
    LEFT JOIN genericproducts p ON p.genericproductid = i.genericproductid AND p.farmid = p_farmid
    WHERE i.genericsaleid = p_saleid AND i.farmid = p_farmid;

    v_both := CASE WHEN s.genericcustomerid IS NULL THEN '["ReversePayment"]'::jsonb ELSE '["KeepAsCredit","ReversePayment"]'::jsonb END;
    v_only := '["KeepAsCredit"]'::jsonb;

    -- (a) payments recorded with the sale (approval, 475/476)
    FOR v_r IN
        SELECT p.genericcustomerpaymentid AS id, p.amount, p.paymentdate, p.paymentmethod, p.genericcashaccountid,
               a.accountname, p.paymentgroupid, COALESCE(NULLIF(btrim(p.referenceno), ''), '#' || p.genericcustomerpaymentid) AS num
        FROM genericcustomerpayments p
        LEFT JOIN genericcashaccounts a ON a.genericcashaccountid = p.genericcashaccountid
        WHERE p.farmid = p_farmid AND p.linkedsaleid = p_saleid AND p.status = 'Approved' AND COALESCE(p.amount, 0) > 0
        ORDER BY p.genericcustomerpaymentid
    LOOP
        v_pays := v_pays || jsonb_build_object(
            'key', 'pay:' || v_r.id, 'paymentId', v_r.id, 'paymentGroupId', v_r.paymentgroupid::text, 'paymentNumbers', v_r.num,
            'source', 'SaleEntry', 'saleGenerated', true, 'allocated', v_r.amount, 'paymentTotal', v_r.amount,
            'paymentDate', v_r.paymentdate, 'paymentMethod', v_r.paymentmethod,
            'cashAccountId', v_r.genericcashaccountid, 'cashAccountName', v_r.accountname,
            'customerId', s.genericcustomerid, 'recordedAtReversal', false,
            'allowed', v_both, 'default', CASE WHEN s.genericcustomerid IS NULL THEN 'ReversePayment' ELSE 'KeepAsCredit' END,
            'reverseUnavailableReason', NULL);
        v_listed := v_listed + v_r.amount;
    END LOOP;

    -- (b) Customer Balances payments allocated to the sale
    FOR v_r IN
        SELECT p.genericcustomerpaymentid AS id, SUM(ca.amountapplied) AS applied, p.amount, p.paymentdate, p.paymentmethod,
               p.genericcashaccountid, a.accountname, p.paymentgroupid,
               COALESCE(NULLIF(btrim(p.referenceno), ''), '#' || p.genericcustomerpaymentid) AS num,
               (SELECT COALESCE(SUM(o.amountapplied), 0) FROM customerpaymentallocation o
                WHERE o.module = 'generic' AND o.farmid = p_farmid AND o.paymentid = p.genericcustomerpaymentid
                  AND o.status = 'Posted' AND o.saleid <> p_saleid) AS elsewhere
        FROM customerpaymentallocation ca
        JOIN genericcustomerpayments p ON p.genericcustomerpaymentid = ca.paymentid AND p.farmid = p_farmid
        LEFT JOIN genericcashaccounts a ON a.genericcashaccountid = p.genericcashaccountid
        WHERE ca.module = 'generic' AND ca.farmid = p_farmid AND ca.saleid = p_saleid AND ca.status = 'Posted'
          AND p.status = 'Approved' AND COALESCE(p.linkedsaleid, -1) <> p_saleid
        GROUP BY p.genericcustomerpaymentid, p.amount, p.paymentdate, p.paymentmethod, p.genericcashaccountid, a.accountname, p.paymentgroupid, p.referenceno
        ORDER BY p.genericcustomerpaymentid
    LOOP
        v_pays := v_pays || jsonb_build_object(
            'key', 'alloc:' || v_r.id, 'paymentId', v_r.id, 'paymentGroupId', v_r.paymentgroupid::text, 'paymentNumbers', v_r.num,
            'source', 'CustomerBalances', 'saleGenerated', (v_r.elsewhere = 0 AND v_r.applied = v_r.amount),
            'allocated', v_r.applied, 'paymentTotal', v_r.amount,
            'paymentDate', v_r.paymentdate, 'paymentMethod', v_r.paymentmethod,
            'cashAccountId', v_r.genericcashaccountid, 'cashAccountName', v_r.accountname,
            'customerId', s.genericcustomerid, 'recordedAtReversal', false,
            'allowed', CASE WHEN v_r.elsewhere = 0 AND v_r.applied = v_r.amount THEN v_both ELSE v_only END,
            'default', 'KeepAsCredit',
            'reverseUnavailableReason', CASE WHEN v_r.elsewhere = 0 AND v_r.applied = v_r.amount THEN NULL
                ELSE 'This payment also paid other invoices, so its share here becomes customer credit. To give money back, reverse the payment itself on Customer Payments.' END);
        v_listed := v_listed + v_r.applied;
    END LOOP;

    -- (c) money taken at the counter with no payment record (sales approved before 475)
    v_credit := COALESCE(s.applycreditamount, 0);
    v_resid  := ROUND(COALESCE(s.amountpaid, 0) - v_listed, 2);
    IF v_resid > 0.004 AND s.status = 'Approved' THEN
        v_pays := v_pays || jsonb_build_object(
            'key', 'AT-SALE', 'paymentId', NULL, 'paymentGroupId', NULL, 'paymentNumbers', NULL,
            'source', 'AtSale', 'saleGenerated', true, 'allocated', v_resid, 'paymentTotal', v_resid,
            'paymentDate', s.saledate, 'paymentMethod', s.paymentmethod,
            'cashAccountId', s.genericcashaccountid,
            'cashAccountName', (SELECT a.accountname FROM genericcashaccounts a WHERE a.genericcashaccountid = s.genericcashaccountid),
            'customerId', s.genericcustomerid, 'recordedAtReversal', true,
            'allowed', v_both, 'default', CASE WHEN s.genericcustomerid IS NULL THEN 'ReversePayment' ELSE 'KeepAsCredit' END,
            'reverseUnavailableReason', NULL);
    END IF;
    IF v_resid > 0.004 AND s.genericcashaccountid IS NULL AND s.genericcustomerid IS NULL THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'NoCashAccount', 'message',
            'Money was received on this walk-in sale but it has no cash account to pay it back from.');
    END IF;

    v_fp := md5(concat_ws('|', s.status, s.amountpaid, s.balance, s.totalamount, s.updatedat, s.salereversalid,
                (SELECT string_agg(p.genericcustomerpaymentid || ':' || p.status || ':' || p.amount, ',' ORDER BY p.genericcustomerpaymentid)
                 FROM genericcustomerpayments p WHERE p.farmid = p_farmid AND p.linkedsaleid = p_saleid),
                (SELECT string_agg(ca.allocationid || ':' || ca.status || ':' || ca.amountapplied, ',' ORDER BY ca.allocationid)
                 FROM customerpaymentallocation ca WHERE ca.module = 'generic' AND ca.farmid = p_farmid AND ca.saleid = p_saleid),
                (SELECT string_agg(m.genericstockmovementid::text, ',' ORDER BY m.genericstockmovementid)
                 FROM genericstockmovements m WHERE m.farmid = p_farmid AND m.referencetype = 'Sale' AND m.referenceid = p_saleid)));

    RETURN jsonb_build_object(
        'found', true, 'saleId', p_saleid, 'saleIds', jsonb_build_array(p_saleid), 'saleGroupNo', s.receiptnumber,
        'saleDate', s.saledate, 'customerId', s.genericcustomerid, 'customerName', COALESCE(v_cust, 'Walk-in customer'),
        'total', COALESCE(s.totalamount, 0), 'paid', COALESCE(s.amountpaid, 0), 'outstanding', COALESCE(s.balance, 0),
        'lines', v_lines, 'payments', v_pays,
        'customerCreditNow', GREATEST(-COALESCE(v_custbal, 0), 0),
        'creditApplied', v_credit,
        'blockers', v_blockers, 'fingerprint', v_fp,
        'defaultCreditCreated', (SELECT COALESCE(SUM((x->>'allocated')::numeric), 0) FROM jsonb_array_elements(v_pays) x WHERE x->>'default' = 'KeepAsCredit'),
        'defaultCashOut', (SELECT COALESCE(SUM((x->>'allocated')::numeric), 0) FROM jsonb_array_elements(v_pays) x WHERE x->>'default' = 'ReversePayment'));
END $f$;

DROP FUNCTION IF EXISTS public.spgenericsale_reversalpreview(text, integer);
CREATE FUNCTION public.spgenericsale_reversalpreview(p_farmid text, p_saleid integer)
RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT public.fngenericsale_reversalstate(p_farmid, p_saleid) $$;

-- ------------------------------------------------------------- 5. reverse -----
-- Posts one customer-ledger line and moves the customer's balance with it.
DROP FUNCTION IF EXISTS public.fngenericcustomer_postledger(text, integer, text, integer, integer, numeric, numeric, text, text);
CREATE FUNCTION public.fngenericcustomer_postledger(p_farmid text, p_customerid integer, p_type text, p_saleid integer, p_paymentid integer,
                                                    p_debit numeric, p_credit numeric, p_description text, p_by text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_bal numeric(14,2);
BEGIN
    IF p_customerid IS NULL OR (COALESCE(p_debit, 0) = 0 AND COALESCE(p_credit, 0) = 0) THEN RETURN; END IF;
    SELECT c.currentbalance + COALESCE(p_debit, 0) - COALESCE(p_credit, 0) INTO v_bal
    FROM genericcustomers c WHERE c.genericcustomerid = p_customerid AND c.farmid = p_farmid FOR UPDATE;
    INSERT INTO genericcustomerledger (farmid, genericcustomerid, transactiondate, transactiontype, saleid, paymentid,
                                       debitamount, creditamount, balanceaftertransaction, description, createdby)
    VALUES (p_farmid, p_customerid, (now() AT TIME ZONE 'utc'), p_type, p_saleid, p_paymentid,
            COALESCE(p_debit, 0), COALESCE(p_credit, 0), v_bal, p_description, p_by);
    UPDATE genericcustomers c SET currentbalance = v_bal, updatedat = (now() AT TIME ZONE 'utc')
    WHERE c.genericcustomerid = p_customerid AND c.farmid = p_farmid;
END $f$;

DROP FUNCTION IF EXISTS public.spgenericsale_reverse(text, integer, text, text, jsonb, text, text, text);
CREATE FUNCTION public.spgenericsale_reverse(p_farmid text, p_saleid integer, p_reasoncode text, p_reason text,
                                             p_handling jsonb DEFAULT '{}'::jsonb, p_expectedfingerprint text DEFAULT NULL,
                                             p_idempotencykey text DEFAULT NULL, p_reversedby text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_now      timestamp := (now() AT TIME ZONE 'utc');
    v_today    date      := fncompany_businessdate(p_farmid);
    v_state    jsonb;
    v_item     jsonb;
    v_action   text;
    v_reason   text;
    v_existing integer;
    v_id       integer;
    v_number   text;
    v_cust     integer;
    v_net      numeric(14,2);
    v_credit   numeric(14,2) := 0;
    v_cashout  numeric(14,2) := 0;
    v_kinds    text[] := ARRAY[]::text[];
    v_acct     record;
    v_amt      numeric(14,2);
    v_payid    integer;
    v_cashtx   integer;
    v_bal      numeric(14,2);
    s          record;
BEGIN
    IF NULLIF(btrim(COALESCE(p_reasoncode, '')), '') IS NULL AND NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for reversing this sale.' USING ERRCODE = 'P0001';
    END IF;
    IF lower(btrim(COALESCE(p_reasoncode, ''))) = 'other' AND NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Say in a few words what happened (the reason is "Other").' USING ERRCODE = 'P0001';
    END IF;
    v_reason := concat_ws(': ', NULLIF(btrim(COALESCE(p_reasoncode, '')), ''), NULLIF(btrim(COALESCE(p_reason, '')), ''));

    PERFORM pg_advisory_xact_lock(hashtext('generic-salereversal:' || p_farmid || ':' || p_saleid::text));
    PERFORM 1 FROM genericsales g WHERE g.farmid = p_farmid AND g.genericsaleid = p_saleid FOR UPDATE;

    IF p_idempotencykey IS NOT NULL THEN
        SELECT r.salereversalid INTO v_existing FROM genericsalereversals r
        WHERE r.farmid = p_farmid AND r.idempotencykey = p_idempotencykey;
        IF FOUND THEN RETURN v_existing; END IF;
    END IF;

    v_state := fngenericsale_reversalstate(p_farmid, p_saleid);
    IF jsonb_array_length(v_state->'blockers') > 0 THEN
        RAISE EXCEPTION '%', v_state->'blockers'->0->>'message' USING ERRCODE = 'P0001';
    END IF;
    IF p_expectedfingerprint IS NOT NULL AND p_expectedfingerprint <> v_state->>'fingerprint' THEN
        RAISE EXCEPTION 'This sale changed after the reversal preview was generated. Please review the updated impact before continuing.'
            USING ERRCODE = 'P0001', HINT = 'stale-preview';
    END IF;
    v_cust := (v_state->>'customerId')::int;
    SELECT g.* INTO s FROM genericsales g WHERE g.genericsaleid = p_saleid AND g.farmid = p_farmid;

    -- every choice is valid before anything changes
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_state->'payments') LOOP
        v_action := COALESCE(p_handling->>(v_item->>'key'), v_item->>'default');
        IF NOT (v_item->'allowed') ? v_action THEN
            RAISE EXCEPTION '%', CASE
                WHEN v_action = 'ReversePayment' THEN COALESCE(v_item->>'reverseUnavailableReason',
                     'Payment ' || COALESCE(v_item->>'paymentNumbers', '') || ' cannot be paid back with this sale.')
                ELSE 'This sale has no customer to hold the money as credit, so the money received can only be paid back.' END
                USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    -- refunds must not push an account below zero when it does not allow it
    FOR v_acct IN
        SELECT (x->>'cashAccountId')::int AS acct, SUM((x->>'allocated')::numeric) AS amt
        FROM jsonb_array_elements(v_state->'payments') x
        WHERE COALESCE(p_handling->>(x->>'key'), x->>'default') = 'ReversePayment' AND x->>'cashAccountId' IS NOT NULL
        GROUP BY 1
    LOOP
        IF EXISTS (SELECT 1 FROM genericcashaccounts a WHERE a.genericcashaccountid = v_acct.acct AND a.farmid = p_farmid
                   AND NOT COALESCE(a.allownegativebalance, false) AND a.currentbalance - v_acct.amt < 0) THEN
            RAISE EXCEPTION 'Paying back % would take % below zero, and that account does not allow it. Keep the money as customer credit, or top up the account first.',
                v_acct.amt, (SELECT a.accountname FROM genericcashaccounts a WHERE a.genericcashaccountid = v_acct.acct)
                USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    PERFORM set_config('generic.sale_system', 'on', true);

    -- 1. the reversal record (numbered), so every row below can name it
    PERFORM pg_advisory_xact_lock(hashtext('generic-salereversal-no:' || p_farmid));
    SELECT 'GSR-' || lpad((COALESCE(MAX(NULLIF(regexp_replace(r.reversalnumber, '\D', '', 'g'), '')::int), 0) + 1)::text, 5, '0')
    INTO v_number FROM genericsalereversals r WHERE r.farmid = p_farmid;

    INSERT INTO genericsalereversals (farmid, reversalnumber, genericsaleid, genericcustomerid, customername, saledate,
                                      reasoncode, reason, businessdate, occurredat, reversedby, paymenthandling,
                                      totalamount, paidamount, outstandingamount, creditreleased, idempotencykey, snapshot)
    VALUES (p_farmid, v_number, p_saleid, v_cust, v_state->>'customerName', s.saledate,
            NULLIF(btrim(COALESCE(p_reasoncode, '')), ''), v_reason, v_today, v_now, p_reversedby, 'None',
            COALESCE(s.totalamount, 0), COALESCE(s.amountpaid, 0), COALESCE(s.balance, 0),
            COALESCE((v_state->>'creditApplied')::numeric, 0), p_idempotencykey, v_state)
    RETURNING salereversalid INTO v_id;

    -- 2. each payment, as chosen
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_state->'payments') LOOP
        v_action := COALESCE(p_handling->>(v_item->>'key'), v_item->>'default');
        v_amt    := (v_item->>'allocated')::numeric;
        v_payid  := NULLIF(v_item->>'paymentId', '')::int;
        v_cashtx := NULL;
        IF v_action = 'ReversePayment' THEN
            IF v_payid IS NOT NULL THEN
                PERFORM spgenericcustomerpayment_reverse(p_farmid, v_payid, 'Sale #' || p_saleid || ' reversed (' || v_number || '): ' || v_reason, p_reversedby);
            ELSE
                -- money taken at the counter: pay it back out of the sale's account
                SELECT a.currentbalance - v_amt INTO v_bal FROM genericcashaccounts a
                WHERE a.genericcashaccountid = s.genericcashaccountid AND a.farmid = p_farmid FOR UPDATE;
                INSERT INTO genericcashtransactions (farmid, genericcashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
                                                     amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
                VALUES (p_farmid, s.genericcashaccountid, v_now, 'CashOut', 'SaleReversal', p_saleid, -v_amt, v_bal,
                        'Sale #' || p_saleid || ' reversed (' || v_number || '): money paid back', p_reversedby, p_reversedby, v_now)
                RETURNING genericcashtransactionid INTO v_cashtx;
                UPDATE genericcashaccounts a SET currentbalance = v_bal, updatedat = v_now
                WHERE a.genericcashaccountid = s.genericcashaccountid AND a.farmid = p_farmid;
            END IF;
            v_cashout := v_cashout + v_amt;
        ELSE
            IF v_item->>'source' = 'CustomerBalances' THEN
                -- this sale's share of the payment is released: it is credit now
                UPDATE customerpaymentallocation ca
                SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
                       reversalreason = 'Sale #' || p_saleid || ' reversed (' || v_number || '): kept as credit'
                WHERE  ca.module = 'generic' AND ca.farmid = p_farmid AND ca.saleid = p_saleid
                  AND  ca.paymentid = v_payid AND ca.status = 'Posted';
            ELSIF v_payid IS NULL THEN
                -- counter money kept: the customer is credited for it
                PERFORM fngenericcustomer_postledger(p_farmid, v_cust, 'SaleReversalCredit', p_saleid, NULL, 0, v_amt,
                    'Sale #' || p_saleid || ' reversed (' || v_number || '): money kept as credit', p_reversedby);
            END IF;
            -- a payment made WITH the sale simply stays received: once the sale's
            -- debit is taken off below, its credit is the customer's credit.
            v_credit := v_credit + v_amt;
        END IF;
        v_kinds := array_append(v_kinds, v_action);
        INSERT INTO genericsalereversalpayments (salereversalid, farmid, itemkey, paymentid, paymentnumbers, sourcetype, amount, action, cashtransactionid)
        VALUES (v_id, p_farmid, v_item->>'key', v_payid, v_item->>'paymentNumbers', v_item->>'source', v_amt, v_action, v_cashtx);
    END LOOP;

    -- 3. anything still allocated to the sale is released (nothing pays a reversed sale)
    UPDATE customerpaymentallocation ca
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = 'Sale #' || p_saleid || ' reversed (' || v_number || ')'
    WHERE  ca.module = 'generic' AND ca.farmid = p_farmid AND ca.saleid = p_saleid AND ca.status = 'Posted';

    -- 4. the customer's account: take off every line the SALE posted (its debit,
    --    the credit applied to it, any earlier adjustment) -- exactly, whatever
    --    the approval path wrote.
    IF v_cust IS NOT NULL THEN
        SELECT COALESCE(SUM(l.debitamount), 0) - COALESCE(SUM(l.creditamount), 0) INTO v_net
        FROM genericcustomerledger l
        WHERE l.farmid = p_farmid AND l.genericcustomerid = v_cust AND l.saleid = p_saleid
          AND l.transactiontype <> 'SaleReversalCredit';
        IF v_net > 0 THEN
            PERFORM fngenericcustomer_postledger(p_farmid, v_cust, 'SaleReversal', p_saleid, NULL, 0, v_net,
                'Sale #' || p_saleid || ' reversed (' || v_number || '): ' || v_reason, p_reversedby);
        ELSIF v_net < 0 THEN
            PERFORM fngenericcustomer_postledger(p_farmid, v_cust, 'SaleReversal', p_saleid, NULL, -v_net, 0,
                'Sale #' || p_saleid || ' reversed (' || v_number || '): ' || v_reason, p_reversedby);
        END IF;
    END IF;
    IF COALESCE(s.applycreditamount, 0) > 0 AND v_cust IS NOT NULL THEN
        INSERT INTO genericcustomercreditapplications (farmid, genericcustomerid, genericsaleid, amountapplied, applicationdate, description, createdby)
        VALUES (p_farmid, v_cust, p_saleid, -s.applycreditamount, v_now,
                'Released: sale #' || p_saleid || ' reversed (' || v_number || ')', p_reversedby);
    END IF;

    -- 5. stock: put back exactly what the sale took out (net of any return)
    INSERT INTO genericstockmovements (farmid, genericproductid, movementdate, movementtype, quantity, unitcost,
                                       unitsellingprice, totalcostvalue, referencetype, referenceid, reason, createdby, approvedby, approvedat)
    SELECT m.farmid, m.genericproductid, v_now, 'ReturnIn', -SUM(m.quantity),
           CASE WHEN SUM(m.quantity) <> 0 THEN SUM(COALESCE(m.totalcostvalue, 0)) / ABS(SUM(m.quantity)) END,
           NULL, ABS(SUM(CASE WHEN m.movementtype = 'SaleOut' THEN COALESCE(m.totalcostvalue, 0) ELSE -COALESCE(m.totalcostvalue, 0) END)),
           'Sale', p_saleid, 'Sale #' || p_saleid || ' reversed (' || v_number || ')', p_reversedby, p_reversedby, v_now
    FROM genericstockmovements m
    WHERE m.farmid = p_farmid AND m.referencetype = 'Sale' AND m.referenceid = p_saleid AND m.movementtype IN ('SaleOut', 'ReturnIn')
    GROUP BY m.farmid, m.genericproductid
    HAVING SUM(m.quantity) < 0;

    UPDATE genericproducts p
    SET    currentstock = p.currentstock + x.qty, updatedat = v_now
    FROM  (SELECT m.genericproductid, SUM(m.quantity) AS qty      -- the ReturnIn rows just written (positive)
           FROM genericstockmovements m
           WHERE m.farmid = p_farmid AND m.referencetype = 'Sale' AND m.referenceid = p_saleid
             AND m.movementtype = 'ReturnIn' AND m.reason = 'Sale #' || p_saleid || ' reversed (' || v_number || ')'
           GROUP BY m.genericproductid) x
    WHERE  p.genericproductid = x.genericproductid AND p.farmid = p_farmid AND p.trackinventory;

    -- 6. the record's totals, then the sale itself
    UPDATE genericsalereversals r
    SET    creditcreated = v_credit, cashreversed = v_cashout,
           paymenthandling = CASE
               WHEN cardinality(v_kinds) = 0 THEN 'None'
               WHEN 'KeepAsCredit' = ALL (v_kinds) THEN 'KeepAsCredit'
               WHEN 'ReversePayment' = ALL (v_kinds) THEN 'ReversePayment'
               ELSE 'Mixed' END
    WHERE  r.salereversalid = v_id;

    UPDATE genericsales g
    SET    status = 'Cancelled', salereversalid = v_id, reversedat = v_now, reversedby = p_reversedby, reversalreason = v_reason,
           cancelledat = v_now, cancelledby = p_reversedby, cancellationreason = 'Reversed (' || v_number || '): ' || v_reason,
           updatedat = v_now
    WHERE  g.genericsaleid = p_saleid AND g.farmid = p_farmid;

    PERFORM set_config('generic.sale_system', 'off', true);
    RETURN v_id;
END $f$;

-- ------------------------------------------------------------- 6. read --------
DROP FUNCTION IF EXISTS public.spgenericsale_reversalget(text, integer);
CREATE FUNCTION public.spgenericsale_reversalget(p_farmid text, p_saleid integer)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'salereversalid', r.salereversalid, 'reversalNumber', r.reversalnumber, 'saleIds', jsonb_build_array(r.genericsaleid),
        'reasonCode', r.reasoncode, 'reason', r.reason, 'businessDate', r.businessdate, 'occurredAt', r.occurredat,
        'reversedBy', r.reversedby, 'paymentHandling', r.paymenthandling,
        'total', r.totalamount, 'paid', r.paidamount, 'outstanding', r.outstandingamount,
        'creditCreated', r.creditcreated, 'cashReversed', r.cashreversed, 'creditReleased', r.creditreleased,
        'correctionSaleId', NULL,
        'payments', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                        'paymentGroupId', rp.itemkey, 'paymentNumbers', rp.paymentnumbers, 'source', rp.sourcetype,
                        'amount', rp.amount, 'action', rp.action, 'recordedAtReversal', rp.itemkey = 'AT-SALE')
                        ORDER BY rp.salereversalpaymentid)
                     FROM genericsalereversalpayments rp WHERE rp.salereversalid = r.salereversalid), '[]'::jsonb),
        'lines', r.snapshot->'lines')
    FROM genericsalereversals r
    WHERE r.farmid = p_farmid AND r.genericsaleid = p_saleid;
$$;

-- ------------------------------------------------------------- 7. refund ------
CREATE OR REPLACE FUNCTION public.spgenericsale_refund(p_genericsaleid integer, p_farmid text, p_refundedby text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    RAISE EXCEPTION 'Refund has been replaced by Reverse: open the sale and choose Reverse. You will be asked for a reason and whether the money is paid back or kept as customer credit.'
        USING ERRCODE = 'P0001';
END $f$;

-- ------------------------------------------------------------- 8. Cash Flow --
-- Live body of spgenericcashflow_rows with the three 483 changes marked.
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
      AND  pu.status = 'Approved'
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
      AND  COALESCE(sp.amount, 0) > 0
      AND  sp.paymentdate::timestamp >= v_from
      AND  sp.paymentdate::timestamp <= v_to;
END;
$function$;

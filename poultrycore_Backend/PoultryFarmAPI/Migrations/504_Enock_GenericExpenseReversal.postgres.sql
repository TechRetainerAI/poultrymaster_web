-- =============================================================================
-- 504_Enock_GenericExpenseReversal: an approved Generic expense is final --
-- corrected by REVERSING it (the 500 purchase reversal model), never by editing.
-- (requires 448, 449, 457, 500, 501)
-- =============================================================================
--
-- WHAT A CUSTOMER SAW (2026-11-27)
--   1. A DRAFT expense was on Cash Flow: the expense arm had no status filter
--      (it also counted the full amount of an expense bought on credit).
--   2. Editing an APPROVED expense's money silently reversed and re-posted it
--      (spgenericexpense_update). The pair showed only on the cash account;
--      Cash Flow reads the expense, so it only ever showed the edited version.
--   3. A paid expense with a supplier made no Supplier Payment, so it was
--      missing from Supplier Payments and the supplier's statement.
--
-- THE RULE FROM HERE ON (decided by the user, 2026-11-27)
--   * An approved expense cannot be edited or deleted. It is reversed
--     (GER-00001) with a reason; a corrected one is entered as new.
--   * The reversal removes the cost (status 'Cancelled' + expensereversalid,
--     as 483/500), takes off the supplier what the expense still owed them, and
--     handles each amount paid as the user chooses:
--       Refund        paid at entry: a CashIn 'ExpenseReversal'; a Supplier
--                     Payment that paid only this expense: reversed (cash back);
--       KeepAsCredit  paid at entry: a no-cash 'ExpenseReversalCredit' row;
--                     a Supplier Payment: its allocation released (credit).
--     No supplier: refund only. Credit spent on it goes back to the supplier.
--   * Approving a PAID expense WITH a supplier records the payment as a
--     Supplier Payment 'ExpenseEntry' (Poultry's model) that carries the cash
--     out; without a supplier the cash goes out directly, as before.
--   * Cash Flow: only approved (or reversed) expenses, only the cash paid when
--     the expense was entered (later payments, ExpenseEntry included, are their
--     own rows); a refund is its own row; the no-cash credit row is left out.
-- =============================================================================

-- ------------------------------------------------------------- 1. columns ----
ALTER TABLE public.genericexpenses ADD COLUMN IF NOT EXISTS expensereversalid integer   NULL;
ALTER TABLE public.genericexpenses ADD COLUMN IF NOT EXISTS reversedat        timestamp NULL;
ALTER TABLE public.genericexpenses ADD COLUMN IF NOT EXISTS reversedby        text      NULL;
ALTER TABLE public.genericexpenses ADD COLUMN IF NOT EXISTS reversalreason    text      NULL;

-- ------------------------------------------------------------- 2. tables -----
CREATE TABLE IF NOT EXISTS public.genericexpensereversals (
    expensereversalid serial        PRIMARY KEY,
    farmid            text          NOT NULL,
    reversalnumber    text          NOT NULL,
    genericexpenseid  integer       NOT NULL,
    genericsupplierid integer       NULL,
    suppliername      text          NULL,
    expensedate       timestamp     NULL,
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
    refunded          numeric(14,2) NOT NULL DEFAULT 0,
    idempotencykey    text          NULL,
    snapshot          jsonb         NULL,
    CONSTRAINT ck_genericexpensereversals_handling
        CHECK (paymenthandling IN ('None', 'KeepAsCredit', 'Refund', 'Mixed'))
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericexpensereversals_number  ON public.genericexpensereversals (farmid, reversalnumber);
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericexpensereversals_idem    ON public.genericexpensereversals (farmid, idempotencykey) WHERE idempotencykey IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericexpensereversals_expense ON public.genericexpensereversals (farmid, genericexpenseid);

CREATE TABLE IF NOT EXISTS public.genericexpensereversalpayments (
    expensereversalpaymentid serial        PRIMARY KEY,
    expensereversalid        integer       NOT NULL REFERENCES public.genericexpensereversals (expensereversalid),
    farmid                   text          NOT NULL,
    itemkey                  text          NOT NULL,     -- entry | sp:{paymentid}
    paymentid                integer       NULL,
    amount                   numeric(14,2) NOT NULL,
    action                   text          NOT NULL,
    cashtransactionid        integer       NULL,
    CONSTRAINT ck_genericexpensereversalpayments_action CHECK (action IN ('KeepAsCredit', 'Refund'))
);
CREATE INDEX IF NOT EXISTS ix_genericexpensereversalpayments_rev ON public.genericexpensereversalpayments (expensereversalid);

-- ------------------------------------------------------------- 3. lock -------
DROP TRIGGER IF EXISTS trg_genericexpense_reversedlock ON public.genericexpenses;
DROP FUNCTION IF EXISTS public.trg_genericexpense_reversedlock_fn();
CREATE FUNCTION public.trg_genericexpense_reversedlock_fn()
RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
    IF COALESCE(current_setting('generic.expense_system', true), '') = 'on' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    IF OLD.expensereversalid IS NOT NULL THEN
        RAISE EXCEPTION 'Expense #% was reversed (%). A reversed expense cannot be changed or deleted.',
            OLD.genericexpenseid, COALESCE(OLD.reversalreason, '') USING ERRCODE = 'P0001';
    END IF;
    RETURN COALESCE(NEW, OLD);
END $f$;
CREATE TRIGGER trg_genericexpense_reversedlock
    BEFORE UPDATE OR DELETE ON public.genericexpenses
    FOR EACH ROW EXECUTE FUNCTION public.trg_genericexpense_reversedlock_fn();

-- -------------------------------------------------------- 4. approve ---------
-- A paid expense with a supplier: the payment is a Supplier Payment
-- 'ExpenseEntry' (cash out, statement, Supplier Payments). Otherwise as before.
CREATE OR REPLACE FUNCTION public.spgenericexpense_approve(p_genericexpenseid integer, p_farmid text, p_approvedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    e       record;
    v_paid  numeric(14,2);
    v_cash  numeric(14,2);
    v_neg   boolean;
BEGIN
    SELECT * INTO e FROM genericexpenses x
    WHERE  x.genericexpenseid = p_genericexpenseid AND x.farmid = p_farmid AND x.isdeleted = FALSE
    FOR UPDATE;
    IF e.genericexpenseid IS NULL THEN
        RAISE EXCEPTION 'Expense % not found.', p_genericexpenseid;
    END IF;
    IF e.status = 'Approved' THEN RETURN; END IF;   -- idempotent
    IF e.status NOT IN ('Draft', 'Submitted') THEN
        RAISE EXCEPTION 'Expense cannot be approved from status %.', e.status;
    END IF;

    v_paid := CASE WHEN e.paymentmethod IN ('Credit', 'NonCash') THEN 0
                   ELSE LEAST(COALESCE(e.amountpaid, e.amount), e.amount) END;

    IF v_paid > 0 AND e.genericsupplierid IS NOT NULL AND e.genericcashaccountid IS NOT NULL THEN
        SELECT ca.currentbalance, ca.allownegativebalance INTO v_cash, v_neg
        FROM   genericcashaccounts ca
        WHERE  ca.genericcashaccountid = e.genericcashaccountid AND ca.farmid = p_farmid;
        IF v_cash IS NULL THEN
            RAISE EXCEPTION 'Cash account on the expense does not exist or belongs to another company.';
        END IF;
        IF v_cash - v_paid < 0 AND v_neg = FALSE THEN
            RAISE EXCEPTION 'Not enough money in the cash account: it has %, this expense pays % from it.', v_cash, v_paid;
        END IF;
        -- the whole amount is owed first; the payment then pays its part
        UPDATE genericexpenses x
        SET    status = 'Approved', approvedby = p_approvedby,
               approvedat = (now() AT TIME ZONE 'utc'), updatedat = (now() AT TIME ZONE 'utc'), amountpaid = 0
        WHERE  x.genericexpenseid = p_genericexpenseid AND x.farmid = p_farmid;
        PERFORM public.spgenericexpense__post(p_genericexpenseid, p_farmid, 1, p_approvedby);
        PERFORM public.spgenericsupplierpayment_record(
            p_farmid, e.genericsupplierid, v_paid,
            jsonb_build_array(jsonb_build_object('documenttype', 'Expense', 'documentid', p_genericexpenseid, 'amount', v_paid)),
            COALESCE(e.paymentmethod, 'Cash'), e.expensedate, e.genericcashaccountid, NULL,
            COALESCE(NULLIF(btrim(e.description), ''), 'Expense #' || p_genericexpenseid) || ' (paid with the expense)',
            'ExpenseEntry', p_approvedby);
        RETURN;
    END IF;

    -- A Credit expense is owed in full (248's NULL would read as paid).
    UPDATE genericexpenses x
    SET    status = 'Approved', approvedby = p_approvedby,
           approvedat = (now() AT TIME ZONE 'utc'), updatedat = (now() AT TIME ZONE 'utc'),
           amountpaid = CASE WHEN x.paymentmethod = 'Credit' THEN 0 ELSE x.amountpaid END
    WHERE  x.genericexpenseid = p_genericexpenseid AND x.farmid = p_farmid;
    PERFORM public.spgenericexpense__post(p_genericexpenseid, p_farmid, 1, p_approvedby);
END
$function$;

-- ------------------------------------------------------------- 5. state ------
-- Same JSON shape as fngenericpurchase_reversalstate (the shared dialog).
DROP FUNCTION IF EXISTS public.fngenericexpense_reversalstate(text, integer);
CREATE FUNCTION public.fngenericexpense_reversalstate(p_farmid text, p_expenseid integer)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE
    e          record;
    v_supplier text;
    v_acctname text;
    v_cat      text;
    v_blockers jsonb := '[]'::jsonb;
    v_pays     jsonb := '[]'::jsonb;
    v_alloc    numeric(14,2);
    v_fromcred numeric(14,2);
    v_entry    numeric(14,2);
    v_r        record;
    v_why      text;
    v_allowed  jsonb;
    v_fp       text;
BEGIN
    SELECT x.* INTO e FROM genericexpenses x
    WHERE  x.genericexpenseid = p_expenseid AND x.farmid = p_farmid AND NOT COALESCE(x.isdeleted, false);
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', false, 'purchaseId', p_expenseid, 'blockers',
            jsonb_build_array(jsonb_build_object('code', 'NotFound', 'message', 'Expense not found for this company.')),
            'payments', '[]'::jsonb, 'lines', '[]'::jsonb, 'fingerprint', '');
    END IF;
    IF e.genericsupplierid IS NOT NULL THEN
        SELECT s.suppliername INTO v_supplier FROM genericsuppliers s WHERE s.genericsupplierid = e.genericsupplierid AND s.farmid = p_farmid;
    END IF;
    IF e.genericcashaccountid IS NOT NULL THEN
        SELECT a.accountname INTO v_acctname FROM genericcashaccounts a WHERE a.genericcashaccountid = e.genericcashaccountid AND a.farmid = p_farmid;
    END IF;
    SELECT c.name INTO v_cat FROM genericexpensecategories c WHERE c.genericexpensecategoryid = e.genericexpensecategoryid;

    IF e.expensereversalid IS NOT NULL THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'AlreadyReversed', 'message', 'This expense has already been reversed.');
    ELSIF e.status IN ('Draft', 'Submitted', 'Rejected') THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'Draft', 'message', 'This expense is not approved: nothing was posted. Edit or delete it instead.');
    ELSIF e.status <> 'Approved' THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'NotApproved', 'message', format('Only an approved expense can be reversed (this one is %s).', e.status));
    END IF;
    IF e.sourcetype IS NOT NULL THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'MadeElsewhere', 'message',
            format('This expense was made by %s -- reverse it there.', e.sourcetype));
    END IF;

    -- Supplier Payments applied here (ExpenseEntry included), one line each
    FOR v_r IN
        SELECT sp.genericsupplierpaymentid AS id, sp.amount, sp.paymentdate, sp.paymentmethod, sp.genericcashaccountid, sp.sourcetype,
               a.accountname,
               CASE WHEN sp.sourcetype = 'ExpenseEntry' THEN 'Paid with the expense'
                    ELSE COALESCE(NULLIF(btrim(sp.referenceno), ''), 'Supplier payment #' || sp.genericsupplierpaymentid) END AS num,
               SUM(sa.amountapplied) AS applied,
               (SELECT COALESCE(SUM(o.amountapplied), 0) FROM supplierpaymentallocation o
                WHERE  o.farmid = p_farmid AND o.module = 'generic' AND o.paymentid = sp.genericsupplierpaymentid
                  AND  o.status = 'Posted' AND NOT (o.documenttype = 'Expense' AND o.documentid = p_expenseid AND NOT o.fromcredit)) AS elsewhere,
               EXISTS (SELECT 1 FROM genericsupplierrefundlines rl JOIN genericsupplierrefunds rf ON rf.refundid = rl.refundid
                       WHERE rl.farmid = p_farmid AND rl.genericsupplierpaymentid = sp.genericsupplierpaymentid AND rf.status = 'Posted') AS refunded
        FROM   supplierpaymentallocation sa
        JOIN   genericsupplierpayments sp ON sp.genericsupplierpaymentid = sa.paymentid AND sp.farmid = p_farmid
        LEFT   JOIN genericcashaccounts a ON a.genericcashaccountid = sp.genericcashaccountid
        WHERE  sa.farmid = p_farmid AND sa.module = 'generic' AND sa.documenttype = 'Expense'
          AND  sa.documentid = p_expenseid AND sa.status = 'Posted' AND NOT sa.fromcredit
        GROUP  BY sp.genericsupplierpaymentid, sp.amount, sp.paymentdate, sp.paymentmethod, sp.genericcashaccountid, sp.sourcetype, a.accountname, sp.referenceno
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

    -- paid at entry straight from the account (no Supplier Payment: no supplier,
    -- or approved before 504)
    SELECT COALESCE(SUM(sa.amountapplied) FILTER (WHERE NOT sa.fromcredit), 0),
           COALESCE(SUM(sa.amountapplied) FILTER (WHERE sa.fromcredit), 0)
    INTO   v_alloc, v_fromcred
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'generic' AND sa.documenttype = 'Expense'
      AND  sa.documentid = p_expenseid AND sa.status = 'Posted';
    v_entry := CASE WHEN e.paymentmethod IN ('Credit', 'NonCash') OR e.genericcashaccountid IS NULL THEN 0
                    ELSE GREATEST(ROUND(LEAST(COALESCE(e.amountpaid, e.amount), e.amount) - v_alloc - v_fromcred, 2), 0) END;

    IF v_entry > 0.004 AND e.status = 'Approved' THEN
        v_allowed := CASE WHEN e.genericsupplierid IS NULL THEN '["Refund"]'::jsonb ELSE '["KeepAsCredit","Refund"]'::jsonb END;
        v_pays := jsonb_build_array(jsonb_build_object(
            'key', 'entry', 'source', 'PaidAtEntry', 'paymentId', NULL, 'paymentNumbers', 'Paid when the expense was entered',
            'allocated', v_entry, 'paymentDate', e.expensedate, 'paymentMethod', e.paymentmethod,
            'cashAccountId', e.genericcashaccountid, 'cashAccountName', v_acctname,
            'allowed', v_allowed,
            'default', CASE WHEN e.genericsupplierid IS NULL THEN 'Refund' ELSE 'KeepAsCredit' END,
            'keepUnavailableReason', CASE WHEN e.genericsupplierid IS NULL THEN 'This expense has no supplier to hold the money as credit.' END,
            'refundUnavailableReason', NULL, 'noCashNote', NULL)) || v_pays;
    END IF;

    v_fp := md5(concat_ws('|', e.status, e.amount, e.amountpaid, e.updatedat, e.expensereversalid,
                (SELECT string_agg(sa.allocationid || ':' || sa.status || ':' || sa.amountapplied, ',' ORDER BY sa.allocationid)
                 FROM supplierpaymentallocation sa WHERE sa.farmid = p_farmid AND sa.module = 'generic'
                   AND sa.documenttype = 'Expense' AND sa.documentid = p_expenseid)));

    RETURN jsonb_build_object(
        'found', true, 'purchaseId', p_expenseid, 'expenseId', p_expenseid, 'purchaseDate', e.expensedate,
        'itemName', COALESCE(NULLIF(btrim(e.description), ''), v_cat, 'Expense'),
        'unit', NULL, 'quantity', 0, 'stockToRemove', 0, 'lines', '[]'::jsonb, 'noStock', true,
        'supplierId', e.genericsupplierid, 'supplierName', COALESCE(v_supplier, NULLIF(btrim(e.paidto), ''), 'No supplier'),
        'total', COALESCE(e.amount, 0),
        'paid', CASE WHEN e.paymentmethod = 'Credit' THEN COALESCE(e.amountpaid, 0) ELSE LEAST(COALESCE(e.amountpaid, e.amount), e.amount) END,
        'creditApplied', v_fromcred,
        'outstanding', GREATEST(COALESCE(e.amount, 0) - CASE WHEN e.paymentmethod = 'Credit' THEN COALESCE(e.amountpaid, 0)
                                                             ELSE LEAST(COALESCE(e.amountpaid, e.amount), e.amount) END, 0),
        'deferred', false, 'costOnPl', true,
        'payments', v_pays,
        'supplierCreditNow', COALESCE((SELECT SUM(fngenericsupplierpayment_unapplied(p_farmid, sp.genericsupplierpaymentid))
                                       FROM genericsupplierpayments sp
                                       WHERE sp.farmid = p_farmid AND sp.genericsupplierid = e.genericsupplierid), 0),
        'blockers', v_blockers, 'fingerprint', v_fp);
END $f$;

DROP FUNCTION IF EXISTS public.spgenericexpense_reversalpreview(text, integer);
CREATE FUNCTION public.spgenericexpense_reversalpreview(p_farmid text, p_expenseid integer)
RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT public.fngenericexpense_reversalstate(p_farmid, p_expenseid) $$;

-- ------------------------------------------------------------- 6. reverse ----
-- fngenericpurchase_releaseallocation (500) releases any allocation, so it serves
-- expenses too (fngenericpayable_addpaid handles 'Expense').
DROP FUNCTION IF EXISTS public.spgenericexpense_reverse(text, integer, text, text, jsonb, text, text, text);
CREATE FUNCTION public.spgenericexpense_reverse(p_farmid text, p_expenseid integer, p_reasoncode text, p_reason text,
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
    e          record;
BEGIN
    IF NULLIF(btrim(COALESCE(p_reasoncode, '')), '') IS NULL AND NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for reversing this expense.' USING ERRCODE = 'P0001';
    END IF;
    IF lower(btrim(COALESCE(p_reasoncode, ''))) = 'other' AND NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Say in a few words what happened (the reason is "Other").' USING ERRCODE = 'P0001';
    END IF;
    v_reason := concat_ws(': ', NULLIF(btrim(COALESCE(p_reasoncode, '')), ''), NULLIF(btrim(COALESCE(p_reason, '')), ''));

    PERFORM pg_advisory_xact_lock(hashtext('generic-expensereversal:' || p_farmid || ':' || p_expenseid::text));
    PERFORM 1 FROM genericexpenses x WHERE x.farmid = p_farmid AND x.genericexpenseid = p_expenseid FOR UPDATE;

    IF p_idempotencykey IS NOT NULL THEN
        SELECT r.expensereversalid INTO v_existing FROM genericexpensereversals r
        WHERE  r.farmid = p_farmid AND r.idempotencykey = p_idempotencykey;
        IF FOUND THEN RETURN v_existing; END IF;
    END IF;

    v_state := fngenericexpense_reversalstate(p_farmid, p_expenseid);
    IF jsonb_array_length(v_state->'blockers') > 0 THEN
        RAISE EXCEPTION '%', v_state->'blockers'->0->>'message' USING ERRCODE = 'P0001';
    END IF;
    IF p_expectedfingerprint IS NOT NULL AND p_expectedfingerprint <> v_state->>'fingerprint' THEN
        RAISE EXCEPTION 'This expense changed after the reversal preview was generated. Please review the updated impact before continuing.'
            USING ERRCODE = 'P0001', HINT = 'stale-preview';
    END IF;
    SELECT x.* INTO e FROM genericexpenses x WHERE x.genericexpenseid = p_expenseid AND x.farmid = p_farmid;

    FOR v_item IN SELECT * FROM jsonb_array_elements(v_state->'payments') LOOP
        v_action := COALESCE(p_handling->>(v_item->>'key'), v_item->>'default');
        IF NOT (v_item->'allowed') ? v_action THEN
            RAISE EXCEPTION '%', CASE
                WHEN v_action = 'Refund' THEN COALESCE(v_item->>'refundUnavailableReason', 'This money cannot be recorded as refunded.')
                ELSE COALESCE(v_item->>'keepUnavailableReason', 'This money cannot be kept as supplier credit.') END
                USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    PERFORM set_config('generic.expense_system', 'on', true);

    PERFORM pg_advisory_xact_lock(hashtext('generic-expensereversal-no:' || p_farmid));
    SELECT 'GER-' || lpad((COALESCE(MAX(NULLIF(regexp_replace(r.reversalnumber, '\D', '', 'g'), '')::int), 0) + 1)::text, 5, '0')
    INTO   v_number FROM genericexpensereversals r WHERE r.farmid = p_farmid;
    v_label := 'Expense #' || p_expenseid || ' reversed (' || v_number || ')';

    INSERT INTO genericexpensereversals (farmid, reversalnumber, genericexpenseid, genericsupplierid, suppliername, expensedate,
                                         reasoncode, reason, businessdate, occurredat, reversedby, paymenthandling,
                                         totalamount, paidamount, outstandingamount, idempotencykey, snapshot)
    VALUES (p_farmid, v_number, p_expenseid, e.genericsupplierid, v_state->>'supplierName', e.expensedate,
            NULLIF(btrim(COALESCE(p_reasoncode, '')), ''), v_reason, fncompany_businessdate(p_farmid), v_now, p_reversedby, 'None',
            COALESCE(e.amount, 0), (v_state->>'paid')::numeric, (v_state->>'outstanding')::numeric, p_idempotencykey, v_state)
    RETURNING expensereversalid INTO v_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(v_state->'payments') LOOP
        v_action := COALESCE(p_handling->>(v_item->>'key'), v_item->>'default');
        v_amt    := (v_item->>'allocated')::numeric;
        v_payid  := NULLIF(v_item->>'paymentId', '')::int;
        v_cashtx := NULL;
        IF v_item->>'key' = 'entry' THEN
            IF v_action = 'Refund' THEN
                PERFORM fngenericcash_move(p_farmid, e.genericcashaccountid, v_amt, v_now, 'ExpenseReversal', p_expenseid,
                                           v_label || ': money paid back', p_reversedby);
                SELECT MAX(t.genericcashtransactionid) INTO v_cashtx FROM genericcashtransactions t
                WHERE  t.farmid = p_farmid AND t.sourcetype = 'ExpenseReversal' AND t.sourceid = p_expenseid;
                v_refund := v_refund + v_amt;
            ELSE
                INSERT INTO genericsupplierpayments (farmid, genericsupplierid, paymentdate, amount, paymentmethod,
                                                     genericcashaccountid, status, notes, referenceno, sourcetype,
                                                     createdby, approvedby, approvedat, createdat)
                VALUES (p_farmid, e.genericsupplierid, v_now, v_amt, 'Credit', NULL, 'Approved',
                        v_label || ': paid at entry, kept as credit', v_number, 'ExpenseReversalCredit',
                        p_reversedby, p_reversedby, v_now, v_now)
                RETURNING genericsupplierpaymentid INTO v_payid;
                v_credit := v_credit + v_amt;
            END IF;
        ELSE
            IF v_action = 'Refund' THEN
                PERFORM spgenericsupplierpayment_reverse(p_farmid, v_payid, v_label || ': ' || v_reason, p_reversedby);
                v_refund := v_refund + v_amt;
            ELSE
                FOR v_a IN
                    SELECT sa.allocationid FROM supplierpaymentallocation sa
                    WHERE  sa.farmid = p_farmid AND sa.module = 'generic' AND sa.paymentid = v_payid
                      AND  sa.documenttype = 'Expense' AND sa.documentid = p_expenseid
                      AND  sa.status = 'Posted' AND NOT sa.fromcredit
                LOOP
                    PERFORM fngenericpurchase_releaseallocation(p_farmid, v_a.allocationid, v_label || ': kept as credit', p_reversedby);
                END LOOP;
                v_credit := v_credit + v_amt;
            END IF;
        END IF;
        v_kinds := array_append(v_kinds, v_action);
        INSERT INTO genericexpensereversalpayments (expensereversalid, farmid, itemkey, paymentid, amount, action, cashtransactionid)
        VALUES (v_id, p_farmid, v_item->>'key', v_payid, v_amt, v_action, v_cashtx);
    END LOOP;

    -- credit spent on it (and anything else still applied) goes back
    FOR v_a IN
        SELECT sa.allocationid FROM supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = 'generic' AND sa.documenttype = 'Expense'
          AND  sa.documentid = p_expenseid AND sa.status = 'Posted'
    LOOP
        v_released := v_released + fngenericpurchase_releaseallocation(p_farmid, v_a.allocationid, v_label || ': credit given back', p_reversedby);
    END LOOP;

    -- the supplier's account: take off exactly what the expense posted
    IF e.genericsupplierid IS NOT NULL THEN
        SELECT COALESCE(SUM(l.creditamount), 0) - COALESCE(SUM(l.debitamount), 0) INTO v_net
        FROM   genericsupplierledger l
        WHERE  l.farmid = p_farmid AND l.genericsupplierid = e.genericsupplierid AND l.expenseid = p_expenseid;
        IF v_net <> 0 THEN
            SELECT COALESCE(s.currentbalance, 0) INTO v_bal FROM genericsuppliers s
            WHERE  s.genericsupplierid = e.genericsupplierid AND s.farmid = p_farmid FOR UPDATE;
            INSERT INTO genericsupplierledger (farmid, genericsupplierid, transactiondate, transactiontype, expenseid,
                                               debitamount, creditamount, balanceaftertransaction, description, createdby)
            VALUES (p_farmid, e.genericsupplierid, v_now, 'ExpenseReversal', p_expenseid,
                    GREATEST(v_net, 0), GREATEST(-v_net, 0), GREATEST(v_bal - v_net, 0), v_label || ': ' || v_reason, p_reversedby);
            UPDATE genericsuppliers SET currentbalance = GREATEST(v_bal - v_net, 0), updatedat = v_now
            WHERE  genericsupplierid = e.genericsupplierid AND farmid = p_farmid;
        END IF;
    END IF;

    UPDATE genericexpensereversals r
    SET    creditcreated = v_credit, creditreleased = v_released, refunded = v_refund,
           paymenthandling = CASE
               WHEN cardinality(v_kinds) = 0 THEN 'None'
               WHEN 'KeepAsCredit' = ALL (v_kinds) THEN 'KeepAsCredit'
               WHEN 'Refund' = ALL (v_kinds) THEN 'Refund'
               ELSE 'Mixed' END
    WHERE  r.expensereversalid = v_id;

    UPDATE genericexpenses x
    SET    status = 'Cancelled', expensereversalid = v_id, reversedat = v_now, reversedby = p_reversedby,
           reversalreason = v_reason, rejectionreason = 'Reversed (' || v_number || '): ' || v_reason, updatedat = v_now
    WHERE  x.genericexpenseid = p_expenseid AND x.farmid = p_farmid;

    PERFORM set_config('generic.expense_system', 'off', true);
    RETURN v_id;
END $f$;

DROP FUNCTION IF EXISTS public.spgenericexpense_reversalget(text, integer);
CREATE FUNCTION public.spgenericexpense_reversalget(p_farmid text, p_expenseid integer)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'purchaseReversalId', r.expensereversalid, 'expenseReversalId', r.expensereversalid, 'reversalNumber', r.reversalnumber,
        'purchaseId', r.genericexpenseid, 'expenseId', r.genericexpenseid,
        'reasonCode', r.reasoncode, 'reason', r.reason, 'occurredAt', r.occurredat, 'reversedBy', r.reversedby,
        'paymentHandling', r.paymenthandling, 'total', r.totalamount, 'paid', r.paidamount,
        'creditCreated', r.creditcreated, 'creditReleased', r.creditreleased, 'refunded', r.refunded, 'stockRemoved', 0)
    FROM genericexpensereversals r
    WHERE r.farmid = p_farmid AND r.genericexpenseid = p_expenseid
$$;

-- ------------------------------------------- 7. approved = final (live 448 bodies + one refusal each) --
CREATE OR REPLACE FUNCTION public.spgenericexpense_update(p_genericexpenseid integer, p_farmid text, p_expensedate timestamp without time zone, p_genericexpensecategoryid integer, p_genericsupplierid integer, p_description text, p_amount numeric, p_paidto text, p_paymentmethod text, p_genericcashaccountid integer, p_receipturl text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_amountpaid numeric DEFAULT NULL::numeric, p_duedate date DEFAULT NULL::date, p_updatedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    e record;
    n record;
    v_now timestamp := (now() AT TIME ZONE 'utc');
    v_paidon boolean;        -- a supplier payment is applied to it
    v_money_changed boolean := FALSE;
BEGIN
    SELECT * INTO e FROM genericexpenses x
    WHERE  x.genericexpenseid = p_genericexpenseid AND x.farmid = p_farmid AND x.isdeleted = FALSE
    FOR UPDATE;
    IF e.genericexpenseid IS NULL THEN
        RAISE EXCEPTION 'Expense % not found.', p_genericexpenseid;
    END IF;
    IF e.sourcetype IS NOT NULL THEN
        RAISE EXCEPTION 'This expense was made by % -- change it there.', e.sourcetype;
    END IF;
    IF e.status = 'Approved' THEN   -- 504: final; corrected by Reverse
        RAISE EXCEPTION 'An approved expense cannot be edited. Reverse it and enter it again.' USING ERRCODE = 'P0001';
    END IF;
    IF e.status NOT IN ('Draft', 'Submitted', 'Rejected', 'Approved') THEN
        RAISE EXCEPTION 'A % expense cannot be edited.', e.status;
    END IF;
    v_paidon := EXISTS (SELECT 1 FROM supplierpaymentallocation sa
                        WHERE sa.farmid = p_farmid AND sa.module = 'generic' AND sa.documenttype = 'Expense'
                          AND sa.documentid = p_genericexpenseid AND sa.status = 'Posted');

    IF e.status = 'Approved' AND v_paidon THEN
        -- Money is locked once a payment is applied: keep it, change the rest.
        UPDATE genericexpenses x
        SET    expensedate = COALESCE(p_expensedate, x.expensedate),
               genericexpensecategoryid = COALESCE(p_genericexpensecategoryid, x.genericexpensecategoryid),
               description = p_description, paidto = p_paidto,
               receipturl = COALESCE(p_receipturl, x.receipturl), notes = p_notes,
               duedate = CASE WHEN COALESCE(x.amountpaid, x.amount) >= x.amount THEN x.duedate ELSE p_duedate END,
               updatedat = v_now
        WHERE  x.genericexpenseid = p_genericexpenseid AND x.farmid = p_farmid;
        RETURN;
    END IF;

    SELECT * INTO n FROM public.fngenericexpense_normalise(p_farmid, p_amount, p_paymentmethod,
        p_genericcashaccountid, p_genericsupplierid, p_amountpaid);

    IF e.status = 'Approved' THEN
        v_money_changed := e.amount IS DISTINCT FROM p_amount
            OR e.paymentmethod IS DISTINCT FROM n.o_method
            OR e.genericcashaccountid IS DISTINCT FROM n.o_cashaccountid
            OR e.genericsupplierid IS DISTINCT FROM p_genericsupplierid
            OR COALESCE(e.amountpaid, e.amount) IS DISTINCT FROM COALESCE(n.o_amountpaid, p_amount);
        IF v_money_changed THEN
            PERFORM public.spgenericexpense__post(p_genericexpenseid, p_farmid, -1, p_updatedby);
        END IF;
    END IF;

    UPDATE genericexpenses x
    SET    expensedate = COALESCE(p_expensedate, x.expensedate),
           genericexpensecategoryid = COALESCE(p_genericexpensecategoryid, x.genericexpensecategoryid),
           genericsupplierid = p_genericsupplierid,
           description = p_description, amount = p_amount, paidto = p_paidto,
           paymentmethod = n.o_method, genericcashaccountid = n.o_cashaccountid,
           receipturl = COALESCE(p_receipturl, x.receipturl), notes = p_notes,
           amountpaid = n.o_amountpaid,
           duedate = CASE WHEN n.o_amountpaid IS NULL THEN NULL ELSE p_duedate END,
           status = CASE WHEN x.status = 'Rejected' THEN 'Draft' ELSE x.status END,
           rejectionreason = CASE WHEN x.status = 'Rejected' THEN NULL ELSE x.rejectionreason END,
           updatedat = v_now
    WHERE  x.genericexpenseid = p_genericexpenseid AND x.farmid = p_farmid;

    IF v_money_changed THEN
        PERFORM public.spgenericexpense__post(p_genericexpenseid, p_farmid, 1, p_updatedby);
    END IF;
END
$function$;

CREATE OR REPLACE FUNCTION public.spgenericexpense_delete(p_genericexpenseid integer, p_farmid text, p_reason text DEFAULT NULL::text, p_deletedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    e record;
BEGIN
    SELECT * INTO e FROM genericexpenses x
    WHERE  x.genericexpenseid = p_genericexpenseid AND x.farmid = p_farmid AND x.isdeleted = FALSE
    FOR UPDATE;
    IF e.genericexpenseid IS NULL THEN
        RAISE EXCEPTION 'Expense % not found.', p_genericexpenseid;
    END IF;
    IF e.sourcetype IS NOT NULL THEN
        RAISE EXCEPTION 'This expense was made by % -- reverse it there.', e.sourcetype;
    END IF;
    IF e.status = 'Approved' THEN
        RAISE EXCEPTION 'An approved expense cannot be deleted. Reverse it instead.' USING ERRCODE = 'P0001';   -- 504
        IF EXISTS (SELECT 1 FROM supplierpaymentallocation sa
                   WHERE sa.farmid = p_farmid AND sa.module = 'generic' AND sa.documenttype = 'Expense'
                     AND sa.documentid = p_genericexpenseid AND sa.status = 'Posted') THEN
            RAISE EXCEPTION 'A supplier payment is applied to this expense. Reverse that payment on Supplier Payments first.';
        END IF;
        PERFORM public.spgenericexpense__post(p_genericexpenseid, p_farmid, -1, p_deletedby);
    END IF;
    UPDATE genericexpenses x
    SET    isdeleted = TRUE,
           status = CASE WHEN x.status = 'Approved' THEN 'Cancelled' ELSE x.status END,
           rejectionreason = COALESCE(NULLIF(btrim(p_reason), ''), x.rejectionreason),
           updatedat = (now() AT TIME ZONE 'utc')
    WHERE  x.genericexpenseid = p_genericexpenseid AND x.farmid = p_farmid;
END
$function$;

-- ------------------------------------------- 8. supplier payment reverse: both kept-credit kinds -----
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
    IF v_sp.sourcetype IN ('PurchaseReversalCredit', 'ExpenseReversalCredit') THEN   -- 500, 504
        RAISE EXCEPTION 'This is credit kept from a reversed purchase or expense (%). It cannot be reversed; use it on a bill or refund it on Supplier Credits.',
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

-- ------------------------------------------- 9. Cash Flow (live body + 504 edits) ----------------------
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
           -xe.atentry,   -- 504: only what was paid when it was entered
           COALESCE(NULLIF(btrim(e.description), ''), 'Expense')::text,
           'OperatingOut'::text, e.createdat::timestamp
    FROM   genericexpenses e
    CROSS  JOIN LATERAL (
        -- 504: cash that left when the expense was entered: nothing for Credit; less
        -- what Supplier Payments (ExpenseEntry included) or credit paid -- those are
        -- their own rows.
        SELECT CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit' THEN 0
                    ELSE GREATEST(LEAST(COALESCE(e.amountpaid, e.amount), e.amount) - COALESCE((
                        SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                        WHERE  sa.module = 'generic' AND sa.documenttype = 'Expense'
                          AND  sa.documentid = e.genericexpenseid AND sa.status = 'Posted'
                          AND  lower(sa.farmid::text) = lower(p_farmid)), 0), 0) END::numeric AS atentry
    ) xe
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(e.amount, 0) > 0
      AND  COALESCE(e.isdeleted, FALSE) = FALSE
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
      AND  (e.status = 'Approved' OR e.expensereversalid IS NOT NULL)   -- 504: never a draft
      AND  xe.atentry > 0
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
           -pe.atentry,   -- 501: paid at entry only; later payments are their own rows
           ('Purchase ' || COALESCE(NULLIF(btrim(pu.invoicenumber), ''), '#' || pu.genericpurchaseid::text)
            || COALESCE(' - ' || NULLIF(btrim(sp.suppliername), ''), ''))::text,
           'OperatingOut'::text,
           pu.createdat::timestamp
    FROM   genericpurchases pu
    LEFT   JOIN genericsuppliers sp ON sp.genericsupplierid = pu.genericsupplierid
    CROSS  JOIN LATERAL (
        -- 501: amountpaid also holds every Supplier Payment (and credit) applied
        -- to the purchase later; those are counted on the payment's own row.
        SELECT GREATEST(COALESCE(pu.amountpaid, 0) - COALESCE((
                   SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                   WHERE  sa.module = 'generic' AND sa.documenttype = 'Purchase'
                     AND  sa.documentid = pu.genericpurchaseid AND sa.status = 'Posted'
                     AND  lower(sa.farmid::text) = lower(p_farmid)), 0), 0)::numeric AS atentry
    ) pe
    WHERE  lower(pu.farmid::text) = lower(p_farmid)
      AND  (pu.status = 'Approved' OR pu.purchasereversalid IS NOT NULL)   -- 500: reversed keeps its day
      AND  COALESCE(pu.isdeleted, FALSE) = FALSE
      AND  pe.atentry > 0
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
      AND  COALESCE(sp.sourcetype, '') <> 'ExpenseReversalCredit'    -- 504: kept as credit, no cash
      AND  NOT public.fngenericsupplier_iscreditkind(sp.sourcetype)   -- 501: credit note / opening / manual credit, no cash
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

    -- 504: a reversed expense paid back -- money in on the day of the reversal.
    RETURN QUERY
    SELECT 'ExpenseRefund'::text, FALSE,
           t.genericcashtransactionid::integer, t.genericcashaccountid::integer, NULL::text,
           t.transactiondate::timestamp, 'CashIn'::text, 'ExpenseReversal'::text,
           t.sourceid::integer, FALSE,
           ABS(COALESCE(t.amount, 0))::numeric,
           COALESCE(NULLIF(btrim(t.description), ''), 'Expense refund')::text,
           'OperatingIn'::text, t.transactiondate::timestamp
    FROM   genericcashtransactions t
    WHERE  lower(t.farmid::text) = lower(p_farmid)
      AND  t.transactiontype = 'CashIn'
      AND  t.sourcetype = 'ExpenseReversal'
      AND  COALESCE(t.amount, 0) <> 0
      AND  t.transactiondate::timestamp >= v_from
      AND  t.transactiondate::timestamp <= v_to;
END;
$function$;

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
               WHEN r.rowsource = 'ExpenseRefund'       THEN 'Expense refunds'    -- 504
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

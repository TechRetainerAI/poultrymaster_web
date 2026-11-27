-- =============================================================================
-- 507_Enock_PoultryBatchReversal: a flock batch is REVERSED, not deleted, so the
-- activity is tracked.  (requires 370, 376, 414, 438, 479, 506)
-- =============================================================================
--
-- WHY (user, 2026-11-27): deleting a batch erased it -- its expense rows AND
-- their cash-out rows went (sppoultryexpensecash_resync deletes them), leaving
-- no trace of who removed it, when, why, or what happened to the money.
--
-- DECIDED (2026-11-27): a numbered reversal record (PBR-00001) holds a full
-- snapshot of the batch, its flocks and its money; the batch row then leaves
-- the batch table as before, so the ~60 readers of mainflockbatch need no
-- change. The batch page lists reversed batches from the record.
--
-- THE REVERSAL
--   * Same blockers as 506: a flock with records (make it inactive instead),
--     birds reconciled straight from the batch. Its empty flocks are deleted
--     with it (414's safe delete) once the user confirmed the list.
--   * The money, per line, as the purchase reversal (479):
--       entry   paid when the batch was bought (its MainFlockBatch expense's
--               cash). The original CashOut rows are KEPT (relabelled
--               'FlockBatchPurchase' / batch id, so they no longer point at a
--               removed expense). Refund = CashIn 'FlockBatchReversal' today;
--               KeepAsCredit (supplier needed) = a SupplierManualCredit.
--       sp:{id} a Supplier Payment ("Pay balance") applied to the batch.
--               Refund = the payment is reversed (376) if it paid only this
--               batch; KeepAsCredit = its allocation released (credit).
--     Supplier credit spent on the batch goes back to the supplier.
--   * The batch's expense rows stop counting as spend (deleted WITHOUT the
--     cash resync), bird ledger rows taken out (438), batch row deleted.
--   * Cash Flow: the kept CashOut shows on its own day (Bird purchases) and a
--     refund on the reversal day -- both through one new helper.
-- =============================================================================

-- ------------------------------------------------------------- 1. tables -----
CREATE TABLE IF NOT EXISTS public.poultrybatchreversals (
    batchreversalid   serial        PRIMARY KEY,
    farmid            text          NOT NULL,
    reversalnumber    text          NOT NULL,
    batchid           integer       NOT NULL,
    batchcode         text          NULL,
    batchname         text          NULL,
    breed             text          NULL,
    numberofbirds     integer       NULL,
    startdate         timestamp     NULL,
    supplierid        integer       NULL,
    suppliername      text          NULL,
    totalcost         numeric(14,2) NOT NULL DEFAULT 0,
    paidamount        numeric(14,2) NOT NULL DEFAULT 0,
    reasoncode        text          NULL,
    reason            text          NOT NULL,
    businessdate      date          NOT NULL,
    occurredat        timestamp     NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    reversedby        text          NULL,
    paymenthandling   text          NOT NULL,
    refunded          numeric(14,2) NOT NULL DEFAULT 0,
    creditkept        numeric(14,2) NOT NULL DEFAULT 0,
    creditreleased    numeric(14,2) NOT NULL DEFAULT 0,
    flocksremoved     jsonb         NOT NULL DEFAULT '[]'::jsonb,
    idempotencykey    text          NULL,
    snapshot          jsonb         NULL,
    CONSTRAINT ck_poultrybatchreversals_handling CHECK (paymenthandling IN ('None', 'KeepAsCredit', 'Refund', 'Mixed'))
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrybatchreversals_number ON public.poultrybatchreversals (farmid, reversalnumber);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrybatchreversals_idem   ON public.poultrybatchreversals (farmid, idempotencykey) WHERE idempotencykey IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrybatchreversals_batch  ON public.poultrybatchreversals (farmid, batchid);

CREATE TABLE IF NOT EXISTS public.poultrybatchreversalpayments (
    batchreversalpaymentid serial        PRIMARY KEY,
    batchreversalid        integer       NOT NULL REFERENCES public.poultrybatchreversals (batchreversalid),
    farmid                 text          NOT NULL,
    linekey                text          NOT NULL,     -- entry:{account} | sp:{paymentid}
    source                 text          NOT NULL,
    paymentid              integer       NULL,         -- the supplier payment, or the credit made
    poultrycashaccountid   integer       NULL,
    amount                 numeric(14,2) NOT NULL,
    action                 text          NOT NULL,
    cashtransactionid      integer       NULL,
    CONSTRAINT ck_poultrybatchreversalpayments_action CHECK (action IN ('KeepAsCredit', 'Refund'))
);
CREATE INDEX IF NOT EXISTS ix_poultrybatchreversalpayments_rev ON public.poultrybatchreversalpayments (batchreversalid);

-- ------------------------------------------------------------- 2. state ------
DROP FUNCTION IF EXISTS public.fnpoultrybatch_reversalstate(text, integer);
CREATE FUNCTION public.fnpoultrybatch_reversalstate(p_farmid text, p_batchid integer)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE
    b          record;
    v_gid      uuid;
    v_pre      jsonb;
    v_blockers jsonb;
    v_money    jsonb := '[]'::jsonb;
    v_credit   numeric(14,2) := 0;
    v_supplier text;
    v_fp       text;
BEGIN
    SELECT x.* INTO b FROM mainflockbatch x WHERE x.batchid = p_batchid AND x.farmid = p_farmid;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', false, 'batchId', p_batchid, 'flocks', '[]'::jsonb, 'payments', '[]'::jsonb,
            'blockers', jsonb_build_array(jsonb_build_object('code', 'NotFound',
                'message', CASE WHEN EXISTS (SELECT 1 FROM poultrybatchreversals r WHERE r.farmid = p_farmid AND r.batchid = p_batchid)
                                THEN 'This batch has already been reversed.' ELSE 'That batch does not exist on this farm.' END)),
            'fingerprint', '');
    END IF;
    BEGIN v_gid := p_farmid::uuid; EXCEPTION WHEN OTHERS THEN v_gid := NULL; END;
    SELECT NULLIF(btrim(s.name), '') INTO v_supplier FROM supplier s WHERE s.supplierid = b.supplierid AND s.farmid::text = p_farmid;

    -- 506's preview: flocks, and blockers -- but a Supplier Payment is a money
    -- line here, not a blocker.
    v_pre := fnpoultrybatch_deletepreview(p_farmid, p_batchid);
    SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_blockers
    FROM   jsonb_array_elements(v_pre->'blockers') x WHERE x->>'code' <> 'SupplierPayments';

    SELECT COALESCE(SUM(sa.amountapplied), 0) INTO v_credit
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.status = 'Posted'
      AND  sa.documenttype = 'FlockBatch' AND sa.documentid = p_batchid AND sa.fromcredit;

    -- paid when the batch was bought: the cash its MainFlockBatch expense took, per account
    IF v_gid IS NOT NULL THEN
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'key', 'entry:' || c.poultrycashaccountid, 'source', 'PaidAtEntry', 'paymentId', NULL,
                   'paymentNumbers', 'Paid when the batch was bought',
                   'allocated', -c.net, 'paymentDate', b.startdate, 'paymentMethod', NULL,
                   'cashAccountId', c.poultrycashaccountid, 'cashAccountName', c.accountname,
                   'allowed', CASE WHEN b.supplierid IS NULL THEN '["Refund"]'::jsonb ELSE '["KeepAsCredit","Refund"]'::jsonb END,
                   'default', 'Refund',
                   'keepUnavailableReason', CASE WHEN b.supplierid IS NULL THEN 'This batch has no supplier to hold the money as credit.' END,
                   'refundUnavailableReason', NULL, 'noCashNote', NULL)), '[]'::jsonb)
        INTO   v_money
        FROM  (SELECT ct.poultrycashaccountid, a.accountname::text AS accountname, SUM(ct.amount)::numeric(14,2) AS net
               FROM   poultrycashtransactions ct
               LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = ct.poultrycashaccountid
               WHERE  ct.farmid = p_farmid AND ct.sourcetype = 'Expense'
                 AND  ct.sourceid IN (SELECT e.expenseid FROM expense e
                                      WHERE e.farmid = v_gid AND e.sourcetype = 'MainFlockBatch' AND e.sourceid = p_batchid)
               GROUP  BY ct.poultrycashaccountid, a.accountname
               HAVING SUM(ct.amount) < -0.005) c;
    END IF;

    -- Supplier Payments ("Pay balance") applied to it
    SELECT v_money || COALESCE(jsonb_agg(jsonb_build_object(
               'key', 'sp:' || x.paymentid, 'source', 'SupplierPayment', 'paymentId', x.paymentid,
               'paymentNumbers', 'Supplier payment #' || x.paymentid,
               'allocated', x.amt, 'paymentDate', x.paymentdate, 'paymentMethod', x.paymentmethod,
               'cashAccountId', x.poultrycashaccountid, 'cashAccountName', x.accountname,
               'allowed', CASE WHEN x.onlythis THEN '["KeepAsCredit","Refund"]'::jsonb ELSE '["KeepAsCredit"]'::jsonb END,
               'default', 'KeepAsCredit',
               'keepUnavailableReason', NULL,
               'refundUnavailableReason', CASE WHEN NOT x.onlythis THEN
                   'This payment also paid other things, so only this batch''s part is released -- as supplier credit. '
                   || 'To get the money back, refund it from Supplier Credits afterwards.' END,
               'noCashNote', CASE WHEN x.poultrycashaccountid IS NULL THEN
                   'This payment was not recorded in a cash account, so a refund puts nothing back into one.' END)
             ORDER BY x.paymentdate, x.paymentid), '[]'::jsonb)
    INTO   v_money
    FROM  (SELECT sp.poultrysupplierpaymentid AS paymentid, sp.paymentdate, sp.paymentmethod,
                  sp.poultrycashaccountid, a.accountname::text AS accountname,
                  SUM(sa.amountapplied)::numeric(14,2) AS amt,
                  (NOT EXISTS (SELECT 1 FROM supplierpaymentallocation o
                               WHERE o.farmid = p_farmid AND o.module = 'poultry' AND o.status = 'Posted'
                                 AND o.paymentid = sp.poultrysupplierpaymentid
                                 AND NOT (o.documenttype = 'FlockBatch' AND o.documentid = p_batchid AND NOT o.fromcredit))
                   AND public.fnpoultrysupplierpayment_unapplied(p_farmid, sp.poultrysupplierpaymentid) <= 0.005) AS onlythis
           FROM   supplierpaymentallocation sa
           JOIN   poultrysupplierpayments sp ON sp.poultrysupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
           LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = sp.poultrycashaccountid
           WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.status = 'Posted'
             AND  sa.documenttype = 'FlockBatch' AND sa.documentid = p_batchid AND NOT sa.fromcredit
           GROUP  BY sp.poultrysupplierpaymentid, sp.paymentdate, sp.paymentmethod, sp.poultrycashaccountid, a.accountname) x;

    SELECT md5(COALESCE(string_agg(t, '|' ORDER BY t), '')) INTO v_fp
    FROM (
        SELECT 'b' || b.batchid || ':' || b.numberofbirds || ':' || b.totalcost || ':' || COALESCE(b.amountpaid, 0) AS t
        UNION ALL
        SELECT 'a' || sa.allocationid || ':' || sa.status || ':' || sa.amountapplied
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.documenttype = 'FlockBatch' AND sa.documentid = p_batchid
        UNION ALL
        SELECT 'f' || (x->>'flockId') || ':' || (x->>'canDelete') || ':' || (x->>'liveBirds') FROM jsonb_array_elements(v_pre->'flocks') x
    ) z;

    RETURN jsonb_build_object(
        'found', true, 'batchId', p_batchid, 'batchCode', b.batchcode, 'batchName', b.batchname,
        'birds', COALESCE(b.numberofbirds, 0), 'purchaseDate', b.startdate,
        'supplierId', b.supplierid, 'supplierName', COALESCE(v_supplier, 'No supplier'),
        'total', COALESCE(b.totalcost, 0), 'paid', COALESCE(b.amountpaid, 0),
        'outstanding', GREATEST(COALESCE(b.totalcost, 0) - COALESCE(b.amountpaid, 0), 0),
        'creditApplied', v_credit,
        'flocks', v_pre->'flocks', 'expenseRemoved', v_pre->'expenseRemoved',
        'payments', v_money, 'blockers', v_blockers, 'fingerprint', v_fp);
END $f$;

DROP FUNCTION IF EXISTS public.sppoultrybatch_reversalpreview(text, integer);
CREATE FUNCTION public.sppoultrybatch_reversalpreview(p_farmid text, p_batchid integer)
RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT public.fnpoultrybatch_reversalstate(p_farmid, p_batchid) $$;

-- ------------------------------------------------------------- 3. reverse ----
DROP FUNCTION IF EXISTS public.sppoultrybatch_reverse(text, integer, text, text, jsonb, boolean, text, text, text);
CREATE FUNCTION public.sppoultrybatch_reverse(p_farmid text, p_batchid integer, p_reasoncode text, p_reason text,
                                              p_handling jsonb DEFAULT '{}'::jsonb, p_deleteflocks boolean DEFAULT false,
                                              p_expectedfingerprint text DEFAULT NULL, p_idempotencykey text DEFAULT NULL,
                                              p_reversedby text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_now      timestamp := (now() AT TIME ZONE 'utc');
    v_gid      uuid;
    v_state    jsonb;
    v_item     jsonb;
    v_action   text;
    v_reason   text;
    v_note     text;
    v_existing integer;
    v_id       integer;
    v_number   text;
    v_amt      numeric(14,2);
    v_acct     integer;
    v_bal      numeric(14,2);
    v_payid    integer;
    v_cashtx   integer;
    v_refund   numeric(14,2) := 0;
    v_kept     numeric(14,2) := 0;
    v_released numeric(14,2) := 0;
    v_kinds    text[] := ARRAY[]::text[];
    v_bird     integer;
    v_net      numeric;
    b          record;
    r          record;
BEGIN
    IF NULLIF(btrim(COALESCE(p_reasoncode, '')), '') IS NULL AND NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for reversing this batch.' USING ERRCODE = 'P0001';
    END IF;
    IF lower(btrim(COALESCE(p_reasoncode, ''))) = 'other' AND NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Say in a few words what happened (the reason is "Other").' USING ERRCODE = 'P0001';
    END IF;
    v_reason := concat_ws(': ', NULLIF(btrim(COALESCE(p_reasoncode, '')), ''), NULLIF(btrim(COALESCE(p_reason, '')), ''));

    PERFORM pg_advisory_xact_lock(hashtext('poultry-batchreversal:' || p_farmid || ':' || p_batchid::text));

    IF p_idempotencykey IS NOT NULL THEN
        SELECT r2.batchreversalid INTO v_existing FROM poultrybatchreversals r2
        WHERE  r2.farmid = p_farmid AND r2.idempotencykey = p_idempotencykey;
        IF FOUND THEN RETURN v_existing; END IF;
    END IF;

    SELECT x.* INTO b FROM mainflockbatch x WHERE x.batchid = p_batchid AND x.farmid = p_farmid FOR UPDATE;
    v_state := fnpoultrybatch_reversalstate(p_farmid, p_batchid);
    IF jsonb_array_length(v_state->'blockers') > 0 THEN
        RAISE EXCEPTION '%', v_state->'blockers'->0->>'message' USING ERRCODE = 'P0001';
    END IF;
    IF p_expectedfingerprint IS NOT NULL AND p_expectedfingerprint <> v_state->>'fingerprint' THEN
        RAISE EXCEPTION 'This batch changed after the reversal preview was generated. Please review the updated impact before continuing.'
            USING ERRCODE = 'P0001', HINT = 'stale-preview';
    END IF;
    IF jsonb_array_length(v_state->'flocks') > 0 AND NOT COALESCE(p_deleteflocks, false) THEN
        RAISE EXCEPTION 'Batch "%" was divided into % flock(s). Confirm that they are deleted with it.',
            b.batchcode, jsonb_array_length(v_state->'flocks') USING ERRCODE = 'P0001', HINT = 'BATCH_HAS_FLOCKS';
    END IF;
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_state->'payments') LOOP
        v_action := COALESCE(p_handling->>(v_item->>'key'), v_item->>'default');
        IF NOT (v_item->'allowed') ? v_action THEN
            RAISE EXCEPTION '%', CASE
                WHEN v_action = 'Refund' THEN COALESCE(v_item->>'refundUnavailableReason', 'This money cannot be recorded as refunded.')
                ELSE COALESCE(v_item->>'keepUnavailableReason', 'This money cannot be kept as supplier credit.') END
                USING ERRCODE = 'P0001';
        END IF;
    END LOOP;
    BEGIN v_gid := p_farmid::uuid; EXCEPTION WHEN OTHERS THEN v_gid := NULL; END;

    -- 1. the record (numbered), with the full snapshot
    PERFORM pg_advisory_xact_lock(hashtext('poultry-batchreversal-no:' || p_farmid));
    SELECT 'PBR-' || lpad((COALESCE(MAX(NULLIF(regexp_replace(r2.reversalnumber, '\D', '', 'g'), '')::int), 0) + 1)::text, 5, '0')
    INTO   v_number FROM poultrybatchreversals r2 WHERE r2.farmid = p_farmid;
    v_note := left('Batch ' || COALESCE(b.batchcode, '#' || p_batchid) || ' reversed (' || v_number || '): ' || v_reason, 500);

    INSERT INTO poultrybatchreversals (farmid, reversalnumber, batchid, batchcode, batchname, breed, numberofbirds, startdate,
                                       supplierid, suppliername, totalcost, paidamount, reasoncode, reason, businessdate, occurredat,
                                       reversedby, paymenthandling, flocksremoved, idempotencykey, snapshot)
    VALUES (p_farmid, v_number, p_batchid, b.batchcode, b.batchname, b.breed, b.numberofbirds, b.startdate,
            b.supplierid, v_state->>'supplierName', COALESCE(b.totalcost, 0), COALESCE(b.amountpaid, 0),
            NULLIF(btrim(COALESCE(p_reasoncode, '')), ''), v_reason, fncompany_businessdate(p_farmid), v_now,
            p_reversedby, 'None', COALESCE(v_state->'flocks', '[]'::jsonb), p_idempotencykey,
            jsonb_build_object('batch', to_jsonb(b), 'preview', v_state))
    RETURNING batchreversalid INTO v_id;

    -- 2. keep the cash history: the batch's own CashOut rows stop pointing at
    --    the expense rows removed below (never deleted, never resynced)
    IF v_gid IS NOT NULL THEN
        UPDATE poultrycashtransactions ct
        SET    sourcetype = 'FlockBatchPurchase', sourceid = p_batchid,
               description = left(COALESCE(ct.description, 'Flock batch purchase') || ' [' || v_number || ']', 500)
        WHERE  ct.farmid = p_farmid AND ct.sourcetype = 'Expense'
          AND  ct.sourceid IN (SELECT e.expenseid FROM expense e
                               WHERE e.farmid = v_gid AND e.sourcetype = 'MainFlockBatch' AND e.sourceid = p_batchid);
    END IF;

    -- 3. supplier credit spent on it goes back to the supplier
    FOR r IN SELECT sa.allocationid FROM supplierpaymentallocation sa
             WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.status = 'Posted'
               AND  sa.documenttype = 'FlockBatch' AND sa.documentid = p_batchid AND sa.fromcredit LOOP
        PERFORM public.sppoultrysuppliercredit_unapply(p_farmid, r.allocationid, v_note, p_reversedby);
        v_released := v_released + COALESCE((SELECT sa.amountapplied FROM supplierpaymentallocation sa WHERE sa.allocationid = r.allocationid), 0);
    END LOOP;

    -- 4. the money, line by line
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_state->'payments') LOOP
        v_action := COALESCE(p_handling->>(v_item->>'key'), v_item->>'default');
        v_amt    := (v_item->>'allocated')::numeric;
        v_acct   := NULLIF(v_item->>'cashAccountId', '')::int;
        v_payid  := NULLIF(v_item->>'paymentId', '')::int;
        v_cashtx := NULL;
        IF v_item->>'source' = 'SupplierPayment' AND v_action = 'Refund' THEN
            PERFORM public.sppoultrysupplierpayment_reverse(p_farmid, v_payid, v_note, p_reversedby);
        ELSIF v_item->>'source' = 'SupplierPayment' THEN
            UPDATE supplierpaymentallocation sa
            SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now, reversalreason = v_note
            WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.status = 'Posted'
              AND  sa.paymentid = v_payid AND sa.documenttype = 'FlockBatch' AND sa.documentid = p_batchid AND NOT sa.fromcredit;
        ELSIF v_action = 'Refund' THEN
            UPDATE poultrycashaccounts a
            SET    currentbalance = a.currentbalance + v_amt, updatedat = v_now
            WHERE  a.poultrycashaccountid = v_acct AND a.farmid = p_farmid
            RETURNING a.currentbalance INTO v_bal;
            INSERT INTO poultrycashtransactions
                (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
                 amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
            VALUES
                (p_farmid, v_acct, v_now, 'CashIn', 'FlockBatchReversal', p_batchid,
                 v_amt, v_bal, left(v_note || ' -- supplier refunded what was paid', 500), p_reversedby, p_reversedby, v_now)
            RETURNING poultrycashtransactionid INTO v_cashtx;
        ELSE
            -- the supplier keeps what was paid for the birds: credit for the next bill
            v_payid := public.sppoultrysuppliercredit_create(p_farmid, b.supplierid, 'SupplierManualCredit', v_amt, v_now,
                                                             v_number, v_note || ' -- paid for the birds, kept as credit', p_reversedby);
        END IF;
        IF v_action = 'Refund' THEN v_refund := v_refund + v_amt; ELSE v_kept := v_kept + v_amt; END IF;
        v_kinds := array_append(v_kinds, v_action);
        INSERT INTO poultrybatchreversalpayments (batchreversalid, farmid, linekey, source, paymentid, poultrycashaccountid,
                                                  amount, action, cashtransactionid)
        VALUES (v_id, p_farmid, v_item->>'key', v_item->>'source', v_payid, v_acct, v_amt, v_action, v_cashtx);
    END LOOP;

    -- 5. the confirmed, empty flocks (414's safe delete: birds released)
    FOR r IN SELECT f.flockid FROM flock f
             WHERE  f.farmid = p_farmid AND f.batchid = p_batchid AND NOT COALESCE(f.isdeleted, FALSE)
             ORDER  BY f.flockid LOOP
        PERFORM sppoultryflock_delete(p_farmid, r.flockid, p_reversedby);
    END LOOP;

    -- 6. its cost rows stop counting as spend -- deleted directly, so their cash
    --    (relabelled in step 2) stays in the cash book
    IF v_gid IS NOT NULL THEN
        DELETE FROM expense e WHERE e.farmid = v_gid AND e.sourcetype = 'MainFlockBatch' AND e.sourceid = p_batchid;
    END IF;

    -- 7. the birds (438): rows of its deleted flocks, then the purchase row
    SELECT p.poultryproductid INTO v_bird FROM poultryproducts p
    WHERE  p.farmid = p_farmid AND (COALESCE(p.isbirdproduct, FALSE) = TRUE OR p.name = 'Birds')
    ORDER  BY p.isbirdproduct DESC NULLS LAST, p.poultryproductid LIMIT 1;
    FOR r IN
        SELECT l.flockid, SUM(l.quantity) AS net
        FROM   fnpoultrybirdledger_rows(p_farmid) l
        WHERE  l.batchid = p_batchid AND l.flockid IS NOT NULL
        GROUP  BY l.flockid HAVING SUM(l.quantity) <> 0
    LOOP
        INSERT INTO poultrystocktransactions
            (farmid, poultryproductid, txntype, quantity, note, createdby, batchid, flockid, effectivedate, reason, birdscope)
        VALUES
            (p_farmid, v_bird, 'Ledger Correction', -r.net,
             left('Batch ' || b.batchcode || ' reversed (' || v_number || '): rows of its deleted flock #' || r.flockid || ' taken out', 500),
             p_reversedby, p_batchid, r.flockid, CURRENT_DATE, 'Batch Reversed', 'Flock');
    END LOOP;
    PERFORM sppoultrybirdstock_sync(p_farmid, 'Bird Batch Purchase', 0::numeric, p_batchid, NULL::text, p_reversedby);

    -- 8. totals, then the batch leaves the batch table (its record stays)
    UPDATE poultrybatchreversals r2
    SET    refunded = v_refund, creditkept = v_kept, creditreleased = v_released,
           paymenthandling = CASE
               WHEN cardinality(v_kinds) = 0 THEN 'None'
               WHEN 'KeepAsCredit' = ALL (v_kinds) THEN 'KeepAsCredit'
               WHEN 'Refund' = ALL (v_kinds) THEN 'Refund'
               ELSE 'Mixed' END
    WHERE  r2.batchreversalid = v_id;

    DELETE FROM mainflockbatch x WHERE x.batchid = p_batchid AND x.farmid = p_farmid;
    RETURN v_id;
END $f$;

-- ------------------------------------------------------------- 4. read -------
DROP FUNCTION IF EXISTS public.sppoultrybatch_reversalget(text, integer);
CREATE FUNCTION public.sppoultrybatch_reversalget(p_farmid text, p_batchreversalid integer)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'batchReversalId', r.batchreversalid, 'reversalNumber', r.reversalnumber, 'batchId', r.batchid,
        'batchCode', r.batchcode, 'batchName', r.batchname, 'reasonCode', r.reasoncode, 'reason', r.reason,
        'occurredAt', r.occurredat, 'reversedBy', r.reversedby, 'paymentHandling', r.paymenthandling,
        'total', r.totalcost, 'paid', r.paidamount, 'refunded', r.refunded, 'creditCreated', r.creditkept,
        'creditReleased', r.creditreleased, 'flocksRemoved', jsonb_array_length(r.flocksremoved))
    FROM poultrybatchreversals r
    WHERE r.farmid = p_farmid AND r.batchreversalid = p_batchreversalid
$$;

-- the batch page's "Reversed" list
DROP FUNCTION IF EXISTS public.sppoultrybatchreversal_list(text);
CREATE FUNCTION public.sppoultrybatchreversal_list(p_farmid text)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'batchReversalId', r.batchreversalid, 'reversalNumber', r.reversalnumber, 'batchId', r.batchid,
        'batchCode', r.batchcode, 'batchName', r.batchname, 'breed', r.breed, 'birds', r.numberofbirds,
        'startDate', r.startdate, 'supplierName', r.suppliername, 'total', r.totalcost, 'paid', r.paidamount,
        'reason', r.reason, 'occurredAt', r.occurredat, 'reversedBy', r.reversedby,
        'refunded', r.refunded, 'creditKept', r.creditkept + r.creditreleased,
        'flocksRemoved', (SELECT COALESCE(jsonb_agg(f->>'name'), '[]'::jsonb) FROM jsonb_array_elements(r.flocksremoved) f))
        ORDER BY r.occurredat DESC), '[]'::jsonb)
    FROM poultrybatchreversals r
    WHERE r.farmid = p_farmid
$$;

-- ------------------------------------------------------------- 5. cash flow --
-- The kept purchase CashOut (its expense row is gone, so arm 3 no longer shows
-- it) on its own day, and a refund on the reversal day.
DROP FUNCTION IF EXISTS public.sppoultrybatchreversal_cashflowrows(text, timestamp, timestamp);
CREATE FUNCTION public.sppoultrybatchreversal_cashflowrows(p_farmid text, p_from timestamp, p_to timestamp)
RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text,
              transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer,
              istransfer boolean, amount numeric, description text, flowgroup text, createdat timestamp without time zone)
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN t.sourcetype = 'FlockBatchPurchase' THEN 'BatchPurchase' ELSE 'BatchRefund' END,
           FALSE, t.poultrycashtransactionid, t.poultrycashaccountid, a.accountname::text,
           t.transactiondate, t.transactiontype::text, t.sourcetype::text, t.sourceid, FALSE,
           t.amount::numeric, COALESCE(t.description, t.sourcetype)::text,
           CASE WHEN t.amount < 0 THEN 'OperatingOut' ELSE 'OperatingIn' END, t.createdat
    FROM   poultrycashtransactions t
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = t.poultrycashaccountid
    WHERE  t.farmid = p_farmid AND t.sourcetype IN ('FlockBatchPurchase', 'FlockBatchReversal')
      AND  t.transactiondate >= p_from AND t.transactiondate <= p_to
$$;

-- Cash Flow rows: live body + one helper call (11).
CREATE OR REPLACE FUNCTION public.sppoultrycashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, createdat timestamp without time zone)
 LANGUAGE plpgsql
 STABLE
AS $function$

DECLARE

    v_tbl  text;
    v_createdcol text;               -- 302: 'ca.createddate' or NULL

    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);

    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);

BEGIN

    -- ---- 1. customer receipts, ONE row per payment (358) -------------------
    -- A payment (paymentgroupid) has one poultrypayments row per sale it pays.
    -- It is one receipt: one row here, whatever the number of sales.
    RETURN QUERY
    SELECT 'Receipt'::text,
           FALSE,
           MIN(p.poultrypaymentid),
           NULL::integer,
           NULL::text,
           MIN(p.paymentdate),
           'CashIn'::text,
           'CustomerPayment'::text,
           CASE WHEN COUNT(DISTINCT p.saleid) = 1 THEN MIN(p.saleid) END,
           FALSE,
           SUM(COALESCE(p.amount, 0))::numeric,
           concat_ws(' Â· ',
               CASE WHEN COUNT(DISTINCT p.saleid) = 1
                    THEN 'Sale ' || COALESCE(MIN(s.salegroupno), '#' || MIN(p.saleid)::text)
                    WHEN COUNT(p.saleid) = 0 AND COUNT(p.debtid) > 0 THEN 'Customer debt payment'   -- 369: debt, received
                    WHEN COUNT(p.saleid) = 0 THEN 'Customer advance'   -- 367: advance, received
                    ELSE COUNT(DISTINCT p.saleid)::text || ' sales' END,
               NULLIF(btrim(COALESCE(MIN(s.customername)::text,
                   (SELECT c.name::text FROM customer c
                    WHERE c.customerid = MIN(p.customerid) AND c.farmid = p_farmid))), ''),
               MIN(p.paymentnumber))::text,
           'OperatingIn'::text,
           MIN(p.createddate)
    FROM   poultrypayments p
    LEFT   JOIN sale s ON s.saleid = p.saleid AND s.farmid = p.farmid
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) <> 0
      -- 351: a REVERSED receipt still came in on its date; it goes back out
      -- on the reversal leg below, so the two net to zero and both show.
      AND  COALESCE(p.status, 'Posted') IN ('Posted', 'Reversed')
      -- 363: no cash behind an opening credit or a credit note.
      AND  COALESCE(p.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote')
      AND  p.paymentdate >= v_from
      AND  p.paymentdate <= v_to
    GROUP  BY COALESCE(p.paymentgroupid::text, 'row:' || p.poultrypaymentid::text);

    -- ---- 1b. (351) receipts reversed, on the business day of the reversal ----
    -- Money Out, but CONTRA-SALES: flowgroup OperatingIn with a negative amount.
    -- 358: one row per reversed payment, like the receipt it undoes.
    RETURN QUERY
    SELECT 'ReceiptReversal'::text,
           FALSE,
           MIN(p.poultrypaymentid),
           NULL::integer,
           NULL::text,
           fnpoultry_businessdateof(p_farmid, MIN(p.reversedat))::timestamp,
           'CashOut'::text,
           'PaymentReversal'::text,
           CASE WHEN COUNT(DISTINCT p.saleid) = 1 THEN MIN(p.saleid) END,
           FALSE,
           -SUM(COALESCE(p.amount, 0))::numeric,
           concat_ws(' Â· ',
               'Payment reversal' || COALESCE(' ' || MIN(p.paymentnumber), ''),
               CASE WHEN COUNT(DISTINCT p.saleid) = 1
                    THEN 'Sale ' || COALESCE(MIN(s.salegroupno), '#' || MIN(p.saleid)::text)
                    WHEN COUNT(p.saleid) = 0 AND COUNT(p.debtid) > 0 THEN 'Customer debt payment'   -- 369: debt, reversed
                    WHEN COUNT(p.saleid) = 0 THEN 'Customer advance'   -- 367: advance, reversed
                    ELSE COUNT(DISTINCT p.saleid)::text || ' sales' END)::text,
           'OperatingIn'::text,
           MIN(p.reversedat)
    FROM   poultrypayments p
    LEFT   JOIN sale s ON s.saleid = p.saleid AND s.farmid = p.farmid
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) <> 0
      AND  p.status = 'Reversed'
      AND  p.reversedat IS NOT NULL
      -- 363: an opening credit or credit note never came in, so never goes out.
      AND  COALESCE(p.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote')
      AND  fnpoultry_businessdateof(p_farmid, p.reversedat)::timestamp >= v_from
      AND  fnpoultry_businessdateof(p_farmid, p.reversedat)::timestamp <= v_to
    GROUP  BY COALESCE(p.paymentgroupid::text, 'row:' || p.poultrypaymentid::text),
              fnpoultry_businessdateof(p_farmid, p.reversedat);

    -- ---- 1c. (351) customer refunds: money handed back out of credit --------
    RETURN QUERY
    SELECT 'CustomerRefund'::text,
           FALSE,
           r.refundid,
           r.poultrycashaccountid,
           NULL::text,
           r.refunddate::timestamp,
           'CashOut'::text,
           'CustomerRefund'::text,
           r.refundid,
           FALSE,
           -r.amount::numeric,
           ('Customer refund ' || r.refundnumber || COALESCE(' - ' || NULLIF(btrim(c.name), ''), ''))::text,
           'OperatingIn'::text,
           r.createdat
    FROM   poultrycustomerrefunds r
    LEFT   JOIN customer c ON c.customerid = r.customerid AND c.farmid = r.farmid
    WHERE  lower(r.farmid) = lower(p_farmid)
      AND  r.status IN ('Posted', 'Reversed')   -- 367: a reversed refund keeps its Money Out
      AND  r.refunddate::timestamp >= v_from
      AND  r.refunddate::timestamp <= v_to;

    -- ---- 1d. (367) a refund reversed: the money came back ------------------
    RETURN QUERY
    SELECT 'CustomerRefundReversal'::text,
           FALSE,
           r.refundid,
           r.poultrycashaccountid,
           NULL::text,
           r.reversaldate::timestamp,
           'CashIn'::text,
           'CustomerRefundReversal'::text,
           r.refundid,
           FALSE,
           r.amount::numeric,
           ('Refund reversal ' || r.refundnumber || COALESCE(' - ' || NULLIF(btrim(c.name), ''), ''))::text,
           'OperatingIn'::text,
           r.reversedat
    FROM   poultrycustomerrefunds r
    LEFT   JOIN customer c ON c.customerid = r.customerid AND c.farmid = r.farmid
    WHERE  lower(r.farmid) = lower(p_farmid)
      AND  r.status = 'Reversed'
      AND  r.reversaldate IS NOT NULL
      AND  r.reversaldate::timestamp >= v_from
      AND  r.reversaldate::timestamp <= v_to;



    -- ---- 2. the part paid at the counter -----------------------------------

    -- Not every receipt becomes a payment row: a sale entered as already paid

    -- sets amountpaid directly. Counting the difference here picks those up

    -- without double counting the ones that DID create a row.

    --

    -- `paid` is honoured ahead of amountpaid because older rows were marked paid

    -- without amountpaid ever being populated -- the same rule CashController

    -- applies. Without it, historic cash sales vanish from the report.

    RETURN QUERY

    SELECT 'SaleResidual'::text,

           FALSE,

           s.saleid,

           s.poultrycashaccountid,

           NULL::text,

           -- sale.saledate is DATE while this function returns TIMESTAMP, so the

           -- cast is load-bearing: without it Postgres refuses the whole

           -- function with "structure of query does not match function result

           -- type". The live 235 carries this; the copy of 235 in this repo does

           -- NOT, so anyone reproducing that file inherits the fault.

           s.saledate::timestamp,

           'CashIn'::text,

           'Sale'::text,

           s.saleid,

           FALSE,

           v.residual,

           ('Sale #' || s.saleid::text ||

            COALESCE(' - ' || NULLIF(btrim(s.customername), ''), ''))::text,

           'OperatingIn'::text

           , s.createddate   -- 302: the entry time
    FROM   sale s

    CROSS  JOIN LATERAL (

        SELECT ROUND(

                   CASE WHEN COALESCE(s.paid, false)

                        THEN COALESCE(s.totalamount, 0)

                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),

                                   COALESCE(s.totalamount, 0))

                   END

                                  - fnpoultrysale_allocated(s.farmid::text, s.saleid)   -- 351: allocations, so applied credit is not fresh cash

               , 2) AS residual

    ) v

    WHERE  lower(s.farmid::text) = lower(p_farmid)

      -- Only a POSITIVE residual. A negative one means the payment rows already

      -- exceed what the sale records as paid, which is a data inconsistency; it

      -- is surfaced by this file's verification query rather than quietly

      -- subtracted from the day's income.

      AND  s.status = 'Posted'
      AND  v.residual > 0

      AND  s.saledate >= v_from

      AND  s.saledate <= v_to;



    -- ---- 3. money paid out when the expense was recorded --------------------

    -- Every kind of spending, because every module writes here. NonCash is still

    -- the only category-level exclusion: internal use posts it to record stock

    -- leaving without any money moving (migration 216).

    --

    -- What changed from 235 is the AMOUNT. It was e.amount -- the full bill.

    -- It is now what was actually paid at entry: the expense's resolved

    -- amountpaid, less anything a supplier payment has since covered (which the

    -- next arm reports on its own, later, date).

    --

    -- amountpaid IS NULL means paid in full, so a legacy row resolves straight

    -- back to e.amount and this arm returns exactly what 235 returned.

    RETURN QUERY

    SELECT 'Expense'::text,

           FALSE,

           e.expenseid,

           e.poultrycashaccountid,

           NULL::text,

           e.expensedate,

           'CashOut'::text,

           'Expense'::text,

           e.expenseid,

           FALSE,

           -v.paidatentry,

           COALESCE(NULLIF(btrim(e.description), ''), e.category)::text,

           'OperatingOut'::text

           , e.createddate   -- 302: the entry time
    FROM   expense e

    CROSS  JOIN LATERAL (

        SELECT GREATEST(

                   COALESCE(e.amountpaid, e.amount)

                 - COALESCE((SELECT SUM(sa.amountapplied)

                             FROM   supplierpaymentallocation sa

                             WHERE  sa.farmid = p_farmid

                               AND  sa.module = 'poultry'

                               AND  sa.status = 'Posted'

                               AND  sa.documenttype = 'Expense'

                               AND  sa.documentid = e.expenseid), 0)

               , 0)::numeric AS paidatentry

    ) v

    WHERE  lower(e.farmid::text) = lower(p_farmid)

      AND  v.paidatentry > 0

      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'

      AND  e.expensedate >= v_from

      AND  e.expensedate <= v_to;



    -- ---- 3b. money paid out later, against a bill already recorded ----------

    -- A supplier payment settling an unpaid expense. It belongs to the day the

    -- money moved, not the day the bill was entered -- the same principle arm 1

    -- applies to customer receipts.

    --

    -- sourceid is the EXPENSE id so the row still drills through to the bill it

    -- paid (and so _detail's category join finds it); sourcerowid is the

    -- allocation id, which is what makes each row unique.

    --

    -- Only documenttype='Expense'. A payment against a raw-material purchase or

    -- a flock batch books its own expense row dated the payment date (224:414)

    -- and is already counted by arm 3; adding it here would double it.

    RETURN QUERY

    SELECT 'ExpensePayment'::text,

           FALSE,

           sa.allocationid,

           sp.poultrycashaccountid,

           NULL::text,

           sp.paymentdate,

           'CashOut'::text,

           'ExpensePayment'::text,

           sa.documentid,

           FALSE,

           -sa.amountapplied::numeric,

           ('Payment for expense #' || sa.documentid::text ||

            COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,

           'OperatingOut'::text

           , sa.createdat   -- 302: the entry time
    FROM   supplierpaymentallocation sa

    JOIN   poultrysupplierpayments sp

           ON  sp.poultrysupplierpaymentid = sa.paymentid

           AND sp.farmid = sa.farmid

    LEFT   JOIN supplier s

           ON  s.supplierid = sp.supplierid AND s.farmid = sp.farmid

    WHERE  sa.farmid = p_farmid

      AND  sa.module = 'poultry'

      AND  sa.status = 'Posted'

      AND  sa.documenttype = 'Expense'
      AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)   -- 370: 3b not a manual credit

      AND  sp.status = 'Posted'

      AND  sa.amountapplied <> 0

      AND  sp.paymentdate >= v_from

      AND  sp.paymentdate <= v_to;

    -- ---- 3c. (341) paid at entry for stock expensed when USED ---------------
    -- A deferred lot books no expense, so arm 3 never sees its cash. Only
    -- the part not covered by a supplier payment (that is 3d's).
    RETURN QUERY
    SELECT 'InventoryPurchase'::text,
           FALSE,
           pu.poultryrawmaterialpurchaseid,
           pu.poultrycashaccountid,
           NULL::text,
           pu.purchasedate,
           'CashOut'::text,
           'RawMaterialPurchase'::text,
           pu.poultryrawmaterialpurchaseid,
           FALSE,
           -v.paidatentry,
           ('Stock purchase: ' || COALESCE(i.itemname, 'item'))::text,
           'OperatingOut'::text,
           pu.createdat
    FROM   poultryrawmaterialpurchases pu
    LEFT   JOIN poultryrawmaterialitems i
           ON i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
    CROSS  JOIN LATERAL (
        SELECT GREATEST(
                   pu.amountpaid
                 - COALESCE((SELECT SUM(sa.amountapplied)
                             FROM   supplierpaymentallocation sa
                             WHERE  sa.farmid = p_farmid
                               AND  sa.module = 'poultry'
                               AND  sa.status = 'Posted'
                               AND  sa.documenttype = 'RawMaterialPurchase'
                               AND  sa.documentid = pu.poultryrawmaterialpurchaseid), 0)
               , 0)::numeric AS paidatentry
    ) v
    WHERE  pu.farmid = p_farmid
      AND  NOT fnpoultrycostrecognition_expenseatpurchase(pu.costrecognitionmethod)
      AND  pu.sourcefeedproductionbatchid IS NULL
      AND  COALESCE(pu.lotsource, '') <> 'ManualDeferredCost'   -- 371: a manual cost is not cash
      AND  v.paidatentry > 0
      AND  pu.purchasedate >= v_from
      AND  pu.purchasedate <= v_to;

    -- ---- 3d. (341) supplier payments for stock expensed when USED -----------
    RETURN QUERY
    SELECT 'InventoryPurchasePayment'::text,
           FALSE,
           sa.allocationid,
           sp.poultrycashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'RawMaterialPurchase'::text,
           sa.documentid,
           FALSE,
           -sa.amountapplied::numeric,
           ('Payment for stock purchase' ||
            COALESCE(': ' || NULLIF(btrim(i.itemname), ''), '') ||
            COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text,
           sa.createdat
    FROM   supplierpaymentallocation sa
    JOIN   poultrysupplierpayments sp
           ON  sp.poultrysupplierpaymentid = sa.paymentid
           AND sp.farmid = sa.farmid
    JOIN   poultryrawmaterialpurchases pu
           ON  pu.poultryrawmaterialpurchaseid = sa.documentid
           AND pu.farmid = sa.farmid
    LEFT   JOIN poultryrawmaterialitems i
           ON  i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
    LEFT   JOIN supplier s
           ON  s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sa.farmid = p_farmid
      AND  sa.module = 'poultry'
      AND  sa.status = 'Posted'
      AND  sa.documenttype = 'RawMaterialPurchase'
      AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)   -- 370: 3d not a manual credit
      AND  sp.status = 'Posted'
      AND  sa.amountapplied <> 0
      AND  NOT fnpoultrycostrecognition_expenseatpurchase(pu.costrecognitionmethod)
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;




    -- ---- 3e. (370) supplier advances: the part of a payment no other row shows --
    -- A payment's cash otherwise reaches Cash Flow only through what it was
    -- applied to (arms 3, 3b, 3d, 3f). What is left -- an advance, an
    -- overpayment, or credit later applied to a lot expensed at purchase or
    -- to birds (their cost is booked NonCash, so arm 3 skips it) -- is shown
    -- here, on the payment's own day. A payment therefore always totals its
    -- amount, whatever happens to its credit later.
    RETURN QUERY
    SELECT 'SupplierAdvance'::text,
           FALSE,
           sp.poultrysupplierpaymentid,
           sp.poultrycashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'SupplierAdvance'::text,
           sp.poultrysupplierpaymentid,
           FALSE,
           -v.amt,
           ((CASE WHEN v.hadallocs THEN 'Supplier overpayment' ELSE 'Supplier advance' END) ||
            COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text,
           sp.createdat
    FROM   poultrysupplierpayments sp
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    CROSS  JOIN LATERAL (
        SELECT (sp.totalamount
                - COALESCE(SUM(sa.amountapplied), 0)
                + COALESCE(SUM(sa.amountapplied) FILTER (
                      WHERE sa.fromcredit
                        AND (sa.documenttype = 'FlockBatch'
                             OR (sa.documenttype = 'RawMaterialPurchase'
                                 AND fnpoultrycostrecognition_expenseatpurchase(
                                         (SELECT pu.costrecognitionmethod FROM poultryrawmaterialpurchases pu
                                          WHERE pu.poultryrawmaterialpurchaseid = sa.documentid AND pu.farmid = sa.farmid))))), 0)
               )::numeric AS amt,
               bool_or(NOT sa.fromcredit) IS TRUE AS hadallocs
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = sp.farmid AND sa.module = 'poultry'
          AND  sa.paymentid = sp.poultrysupplierpaymentid AND sa.status = 'Posted'
    ) v
    WHERE  sp.farmid = p_farmid
      AND  sp.status = 'Posted'
      AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)
      AND  v.amt <> 0
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;

    -- ---- 3f. (370) payments of supplier debts, on the payment's day ----------
    RETURN QUERY
    SELECT 'SupplierDebtPayment'::text,
           FALSE,
           sa.allocationid,
           sp.poultrycashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'SupplierDebtPayment'::text,
           sa.documentid,
           FALSE,
           -sa.amountapplied::numeric,
           ('Payment of supplier debt ' || COALESCE(d.debtnumber, '#' || sa.documentid::text) ||
            COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text,
           sa.createdat
    FROM   supplierpaymentallocation sa
    JOIN   poultrysupplierpayments sp
           ON  sp.poultrysupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
    LEFT   JOIN poultrysupplierdebts d ON d.debtid = sa.documentid AND d.farmid = sa.farmid
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sa.farmid = p_farmid
      AND  sa.module = 'poultry'
      AND  sa.status = 'Posted'
      AND  sa.documenttype = 'SupplierDebt'
      AND  sp.status = 'Posted'
      AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;

    -- ---- 3i. (376) a REVERSED supplier payment still went out on its day ---
    -- Every arm above reads Posted payments only, so a reversed payment used to
    -- vanish. Like a reversed customer receipt (1 / 1b): the payment keeps its
    -- Money Out on its own date -- one row, the full amount -- and the
    -- reversal is its own Money In (3j). The two net to zero and both show.
    RETURN QUERY
    SELECT 'SupplierPayment'::text,
           FALSE,
           sp.poultrysupplierpaymentid,
           sp.poultrycashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'PoultrySupplierPayment'::text,
           sp.poultrysupplierpaymentid,
           FALSE,
           -sp.totalamount::numeric,
           ('Supplier payment #' || sp.poultrysupplierpaymentid::text ||
            COALESCE(' - ' || NULLIF(btrim(s.name), ''), '') || ' (reversed later)')::text,
           'OperatingOut'::text,
           sp.createdat
    FROM   poultrysupplierpayments sp
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  sp.status = 'Reversed'
      AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)
      AND  COALESCE(sp.totalamount, 0) <> 0
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;

    -- ---- 3j. (376) a supplier payment reversed: the money came back --------
    -- Money In on the business day of the reversal, against operating
    -- outflows (like a supplier refund, 3g).
    RETURN QUERY
    SELECT 'SupplierPaymentReversal'::text,
           FALSE,
           sp.poultrysupplierpaymentid,
           sp.poultrycashaccountid,
           NULL::text,
           fnpoultry_businessdateof(p_farmid, sp.reversedat)::timestamp,
           'CashIn'::text,
           'SupplierPaymentReversal'::text,
           sp.poultrysupplierpaymentid,
           FALSE,
           sp.totalamount::numeric,
           ('Supplier payment reversal #' || sp.poultrysupplierpaymentid::text ||
            COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text,
           sp.reversedat
    FROM   poultrysupplierpayments sp
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  sp.status = 'Reversed'
      AND  sp.reversedat IS NOT NULL
      AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)
      AND  COALESCE(sp.totalamount, 0) <> 0
      AND  fnpoultry_businessdateof(p_farmid, sp.reversedat)::timestamp >= v_from
      AND  fnpoultry_businessdateof(p_farmid, sp.reversedat)::timestamp <= v_to;

    -- ---- 3g. (370) a supplier sends money back out of credit: Money In ------
    -- Kept when reversed; the reversal is its own Money Out (3h).
    RETURN QUERY
    SELECT 'SupplierRefund'::text,
           FALSE,
           r.refundid,
           r.poultrycashaccountid,
           NULL::text,
           r.refunddate::timestamp,
           'CashIn'::text,
           'SupplierRefund'::text,
           r.refundid,
           FALSE,
           r.amount::numeric,
           ('Supplier refund ' || r.refundnumber || COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text,
           r.createdat
    FROM   poultrysupplierrefunds r
    LEFT   JOIN supplier s ON s.supplierid = r.supplierid AND s.farmid = r.farmid
    WHERE  r.farmid = p_farmid
      AND  r.status IN ('Posted', 'Reversed')
      AND  r.refunddate::timestamp >= v_from
      AND  r.refunddate::timestamp <= v_to;

    -- ---- 3h. (370) a supplier refund reversed: Money Out --------------------
    RETURN QUERY
    SELECT 'SupplierRefundReversal'::text,
           FALSE,
           r.refundid,
           r.poultrycashaccountid,
           NULL::text,
           r.reversaldate::timestamp,
           'CashOut'::text,
           'SupplierRefundReversal'::text,
           r.refundid,
           FALSE,
           -r.amount::numeric,
           ('Supplier refund reversal ' || r.refundnumber || COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text,
           r.reversedat
    FROM   poultrysupplierrefunds r
    LEFT   JOIN supplier s ON s.supplierid = r.supplierid AND s.farmid = r.farmid
    WHERE  r.farmid = p_farmid
      AND  r.status = 'Reversed'
      AND  r.reversaldate IS NOT NULL
      AND  r.reversaldate::timestamp >= v_from
      AND  r.reversaldate::timestamp <= v_to;

    -- ---- 4. owner money (253) ----------------------------------------------

    -- Contributions and draws recorded through the Owner Money module.

    -- FINANCING, not operating: the owner funded the business or took funding

    -- back. Never revenue, never expense.

    --

    -- Reversed records are dropped entirely rather than netted to zero with a

    -- second row -- a contribution that was put in and taken back out is not

    -- funding, and showing both legs would put money the business never kept

    -- into Money In and Money Out.

    --

    -- Placed ABOVE the legacy capital arm on purpose: that arm RETURNs early

    -- when cashadjustment is absent, so anything below it is skipped on a farm

    -- with no capital records.

    RETURN QUERY

    SELECT 'OwnerMoney'::text,

           FALSE,

           o.poultryownermoneyid,

           o.poultrycashaccountid,

           a.accountname::text,

           o.transactiondate,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'CashIn' ELSE 'CashOut' END::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END::text,

           o.poultryownermoneyid,

           FALSE,

           -- Stored positive; the sign is applied here, once.

           (CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE -o.amount END)::numeric,

           COALESCE(NULLIF(btrim(o.notes), ''),

                    NULLIF(btrim(o.ownername), ''),

                    CASE WHEN o.transactiontype = 'Contribution'

                         THEN 'Owner contribution' ELSE 'Owner draw' END)::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'FinancingIn' ELSE 'FinancingOut' END::text

           , o.createdat   -- 302: the entry time
    FROM   poultryownermoney o

    LEFT   JOIN poultrycashaccounts a

           ON a.poultrycashaccountid = o.poultrycashaccountid

    WHERE  o.farmid = p_farmid

      AND  o.status = 'Posted'
      -- 296. A record backfilled from a Cash Flow adjustment has NO cash
      -- row of its own: the ADJUSTMENT is still the cash event, and the
      -- legacy adjustment arm below already reports it. Without this the
      -- same money is counted twice -- the trap 292 hit for loans.
      AND  o.sourceadjustmentid IS NULL

      AND  o.transactiondate >= v_from

      AND  o.transactiondate <= v_to;



    -- ---- 5. loans received (254) -------------------------------------------

    -- Borrowed money arriving. FINANCING: the business received it, it did not

    -- earn it, so it is money in and never revenue.

    --

    -- The AMOUNT RECEIVED, not the principal. A lender that withholds a fee

    -- pays out less than it lends, and only what arrived is cash in.

    RETURN QUERY

    SELECT 'Loan'::text,

           FALSE,

           l.poultryloanid,

           l.poultrycashaccountid,

           a.accountname::text,

           -- 256. loandate is a DATE, so this was always midnight and a loan

           -- recorded this afternoon sorted below everything else recorded

           -- today. Same rule as lib/utils/date-key.entryTimestamp: a loan

           -- dated TODAY carries the moment it was actually recorded, and a

           -- back-dated one keeps midnight, because nobody knows what time last

           -- Tuesday's disbursement landed.

           CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                ELSE l.loandate::timestamp END,

           'CashIn'::text,

           'LoanReceived'::text,

           l.poultryloanid,

           FALSE,

           l.amountreceived::numeric,

           ('Loan received from ' || l.lendername)::text,

           'FinancingIn'::text

           , l.createdat   -- 302: the entry time
    FROM   poultryloans l

    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = l.poultrycashaccountid

    WHERE  l.farmid = p_farmid

      AND  l.amountreceived > 0

      -- 292. A loan converted from a Cash Flow adjustment has NO cash row of

      -- its own: the ADJUSTMENT is the cash event, and arm 8 below already

      -- reports it. Without this the same borrowing is money-in twice -- which

      -- is precisely what the stage check caught.

      AND  l.sourceadjustmentid IS NULL

      AND  l.status NOT IN ('Cancelled', 'Reversed', 'Draft')

      AND  l.loandate::timestamp >= v_from

      AND  l.loandate::timestamp <= v_to;



    -- ---- 6. loan repayments (254) ------------------------------------------

    -- The FULL payment leaves the account, so the full payment is money out --

    -- principal, interest and fees together.

    --

    -- This does NOT double count the interest and fee expenses those payments

    -- create: they are written paymentmethod = 'NonCash', and arm 3 above skips

    -- NonCash. The P&L reads the expense table directly and still counts them,

    -- which is the whole point -- cash out is 12,500, cost is 2,500.

    RETURN QUERY

    SELECT 'LoanPayment'::text,

           FALSE,

           p.poultryloanpaymentid,

           p.poultrycashaccountid,

           a.accountname::text,

           p.paymentdate,

           'CashOut'::text,

           'LoanRepayment'::text,

           p.poultryloanid,

           FALSE,

           -p.totalamount::numeric,

           ('Loan repayment to ' || l.lendername)::text,

           'FinancingOut'::text

           , p.createdat   -- 302: the entry time
    FROM   poultryloanpayments p

    JOIN   poultryloans l ON l.poultryloanid = p.poultryloanid

    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = p.poultrycashaccountid

    WHERE  p.farmid = p_farmid

      AND  p.status = 'Posted'

      AND  p.paymentdate >= v_from

      AND  p.paymentdate <= v_to;



    -- ---- 7. capital in and out (legacy cash adjustments) --------------------

    -- Owner injections, loans received, withdrawals. Financing, not operating:

    -- money the business received or returned rather than earned or spent.

    --

    -- MUST STAY LAST: it RETURNs early when the table is absent, and anything

    -- below it would be silently skipped on a farm without capital records.

    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,

                      to_regclass('public.cashadjustments')::text);



    -- 302: only reference the creation column if the resolved table has one.
    SELECT CASE WHEN EXISTS (
               SELECT 1 FROM information_schema.columns c
               WHERE  c.table_schema = 'public'
                 AND  c.table_name = replace(v_tbl, 'public.', '')
                 AND  c.column_name = 'createddate')
           THEN 'ca.createddate' ELSE 'NULL::timestamp' END
      INTO v_createdcol;

    IF v_tbl IS NULL THEN

        RETURN;                     -- no capital records; the four legs stand

    END IF;



    RETURN QUERY EXECUTE format($sql$

        SELECT 'Adjustment'::text,

               FALSE,

               ca.adjustmentid,

               NULL::integer,

               NULL::text,

               ca.adjustmentdate,

               CASE WHEN ca.amount >= 0 THEN 'CashIn' ELSE 'CashOut' END::text,

               COALESCE(NULLIF(btrim(ca.adjustmenttype), ''), 'Adjustment')::text,

               ca.adjustmentid,

               FALSE,

               ca.amount::numeric,     -- already signed

               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text,

               CASE WHEN ca.amount >= 0 THEN 'FinancingIn' ELSE 'FinancingOut' END::text,
               %s                       -- 302: the entry time

        FROM   %s ca

        WHERE  lower(ca.farmid::text) = lower($1)

          AND  ca.amount <> 0

          AND  ca.adjustmentdate >= $2

          AND  ca.adjustmentdate <= $3

    $sql$, v_createdcol, v_tbl)

    USING p_farmid, v_from, v_to;

    -- ---- 8. employee advances (305/307) ------------------------------------

    -- Disbursements out, manual repayments in, payroll deductions NOWHERE:

    -- a deduction moves no money, so it is not a cash event. The arms live in

    -- their own function, so this body is touched once and never again.

    RETURN QUERY

    SELECT * FROM public.sppoultryemployeeloan_cashflowrows(p_farmid, v_from, v_to);

    -- ---- 9. (435) birds sold before tracking: the money received ------
    RETURN QUERY
    SELECT * FROM public.sppoultryhistoricalsale_cashflowrows(p_farmid, v_from, v_to);

    -- ---- 10. (441) employee credit: money handed in, paid out, reversed -----
    -- Payroll savings move no cash (net pay is already lower), so they are not
    -- here at all.
    RETURN QUERY
    SELECT * FROM public.sppoultryemployeecredit_cashflowrows(p_farmid, v_from, v_to);

    -- ---- 11. (507) a reversed flock batch: its purchase cash kept, any refund --
    RETURN QUERY
    SELECT * FROM public.sppoultrybatchreversal_cashflowrows(p_farmid, v_from, v_to);
END;
$function$;

-- Cash Flow detail: live body + two categories.
CREATE OR REPLACE FUNCTION public.sppoultrycashflow_detail(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, category text, createdat timestamp without time zone)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname,
           r.transactiondate, r.transactiontype, r.sourcetype, r.sourceid,
           r.istransfer, r.amount, r.description, r.flowgroup,
           CASE
               WHEN r.rowsource IN ('Expense', 'ExpensePayment')
                   THEN COALESCE(NULLIF(btrim(e.category), ''), 'Uncategorised')
               WHEN r.rowsource IN ('Receipt', 'SaleResidual') THEN 'Sales'
               WHEN r.rowsource = 'ReceiptReversal' THEN 'Sale payment reversals'
               WHEN r.rowsource = 'CustomerRefund'  THEN 'Customer refunds'
               WHEN r.rowsource = 'CustomerRefundReversal' THEN 'Customer refunds'   -- 367: refund reversal
               WHEN r.rowsource = 'SupplierAdvance' THEN 'Supplier advances'   -- 370: supplier credit rows
               WHEN r.rowsource = 'SupplierDebtPayment' THEN 'Supplier debt payments'
               WHEN r.rowsource IN ('SupplierRefund', 'SupplierRefundReversal') THEN 'Supplier refunds'
               WHEN r.rowsource = 'HistoricalSale' THEN 'Bird sales (before tracking)'   -- 435
               WHEN r.rowsource = 'BatchPurchase' THEN 'Flock / Bird Purchase'   -- 507: a reversed batch's purchase
               WHEN r.rowsource = 'BatchRefund' THEN 'Bird purchase refunds'     -- 507
               WHEN r.rowsource IN ('EmployeeCredit', 'EmployeeCreditReversal') THEN 'Employee credit'   -- 441
               -- Capital keeps its own type as the bucket, so an owner injection
               -- never merges into a generic "Adjustment" slice.
               ELSE COALESCE(NULLIF(btrim(r.sourcetype), ''), 'Other')
           END::text,
           r.createdat              -- 302: the entry time
    FROM   public.sppoultrycashflow_rows(p_farmid, p_fromdate, p_todate) r
    -- LEFT, so an expense deleted after the fact still appears in the totals as
    -- Uncategorised rather than dropping out of them.
    LEFT   JOIN expense e
           ON  r.rowsource IN ('Expense', 'ExpensePayment')
           AND e.expenseid = r.sourceid
           AND lower(e.farmid::text) = lower(p_farmid);
$function$;

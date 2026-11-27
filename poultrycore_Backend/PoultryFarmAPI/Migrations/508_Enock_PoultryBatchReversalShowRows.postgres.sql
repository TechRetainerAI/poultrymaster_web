-- =============================================================================
-- 508_Enock_PoultryBatchReversalShowRows: a reversed batch, the flocks removed
-- with it and its expense lines stay VISIBLE -- marked Reversed -- on the batch,
-- flock and expense lists.  (requires 507)
-- =============================================================================
-- The rows themselves still leave their tables (507's decision: no reader of
-- mainflockbatch / flock / expense changes, so no totals move). The reversal
-- record now also keeps the batch's expense lines, and the list returns
-- everything the three pages need to show the reversed rows.
-- Rebuilt from the live 507 body: one step added before the expense rows go.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sppoultrybatch_reverse(p_farmid text, p_batchid integer, p_reasoncode text, p_reason text, p_handling jsonb DEFAULT '{}'::jsonb, p_deleteflocks boolean DEFAULT false, p_expectedfingerprint text DEFAULT NULL::text, p_idempotencykey text DEFAULT NULL::text, p_reversedby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
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

    -- 508: keep the expense lines on the record, so the Expenses page can show
    --      them as Reversed
    IF v_gid IS NOT NULL THEN
        UPDATE poultrybatchreversals r2
        SET    snapshot = COALESCE(r2.snapshot, '{}'::jsonb) || jsonb_build_object('expenses', COALESCE((
                   SELECT jsonb_agg(jsonb_build_object(
                       'expenseId', e.expenseid, 'expenseDate', e.expensedate, 'category', e.category,
                       'description', e.description, 'amount', e.amount, 'paymentMethod', e.paymentmethod,
                       'supplier', e.supplier, 'supplierId', e.supplierid, 'amountPaid', e.amountpaid)
                       ORDER BY e.expensedate, e.expenseid)
                   FROM expense e WHERE e.farmid = v_gid AND e.sourcetype = 'MainFlockBatch' AND e.sourceid = p_batchid), '[]'::jsonb))
        WHERE  r2.batchreversalid = v_id;
    END IF;

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
END $function$;


-- the list, with everything the batch, flock and expense pages show
CREATE OR REPLACE FUNCTION public.sppoultrybatchreversal_list(p_farmid text)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'batchReversalId', r.batchreversalid, 'reversalNumber', r.reversalnumber, 'batchId', r.batchid,
        'batchCode', r.batchcode, 'batchName', r.batchname, 'breed', r.breed, 'birds', r.numberofbirds,
        'startDate', r.startdate, 'supplierId', r.supplierid, 'supplierName', r.suppliername,
        'total', r.totalcost, 'paid', r.paidamount,
        'costPerChick', r.snapshot->'batch'->'costperchick', 'supplierType', r.snapshot->'batch'->>'suppliertype',
        'reason', r.reason, 'occurredAt', r.occurredat, 'reversedBy', r.reversedby,
        'refunded', r.refunded, 'creditKept', r.creditkept + r.creditreleased,
        'flocksRemoved', (SELECT COALESCE(jsonb_agg(f->>'name'), '[]'::jsonb) FROM jsonb_array_elements(r.flocksremoved) f),
        'flocks', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                       'flockId', (f->>'flockId')::int, 'name', f->>'name', 'liveBirds', (f->>'liveBirds')::int,
                       'breed', fl.breed, 'flockType', fl.flocktype, 'startDate', fl.startdate, 'houseId', fl.houseid)), '[]'::jsonb)
                   FROM jsonb_array_elements(r.flocksremoved) f
                   LEFT JOIN flock fl ON fl.flockid = (f->>'flockId')::int AND fl.farmid = p_farmid),
        'expenses', COALESCE(r.snapshot->'expenses', '[]'::jsonb))
        ORDER BY r.occurredat DESC), '[]'::jsonb)
    FROM poultrybatchreversals r
    WHERE r.farmid = p_farmid
$$;

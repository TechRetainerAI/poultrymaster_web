-- =============================================================================
-- 506_Enock_PoultryBatchDeleteFlocks: deleting a flock batch takes its flocks
-- with it -- after a strict warning -- unless a flock has records, and never
-- leaves a supplier payment behind.  (requires 414, 438)
-- =============================================================================
--
-- WHAT WAS WRONG (2026-11-27)
--   * A batch with flocks could not be deleted at all ("delete those flocks
--     first"), so users deleted flocks one by one, or (before 438) the batch
--     went and its flocks were left orphaned (dev: flock 3066 of batch 57).
--   * "Pay balance" on a batch records a Supplier Payment (PurchaseEntry)
--     allocated to the batch plus a cost row. Deleting the batch removed the
--     cost rows but left the payment posted against a batch that no longer
--     exists (dev: payment 477 on batch 253) -- the money never came off.
--
-- THE RULE (user, 2026-11-27)
--   * Deleting a batch also deletes the flocks it was divided into, but only
--     when the user confirmed that list (p_deleteflocks), and only flocks with
--     NO records. A flock with production (or any other posted) records cannot
--     be deleted: the batch delete is refused and the user makes that flock
--     inactive instead.
--   * A batch with posted Supplier Payments applied to it cannot be deleted
--     until those payments are reversed on Supplier Payments.
--   * spmainflockbatch_delete keeps its 3-argument behaviour for other callers
--     (refuses while flocks exist); the new p_deleteflocks defaults to false.
--   * fnpoultrybatch_deletepreview tells the screen all of this up front.
-- =============================================================================

-- ------------------------------------------------------------- 1. preview ----
DROP FUNCTION IF EXISTS public.fnpoultrybatch_deletepreview(text, integer);
CREATE FUNCTION public.fnpoultrybatch_deletepreview(p_farmid text, p_batchid integer)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE
    b          record;
    v_gid      uuid;
    v_flocks   jsonb := '[]'::jsonb;
    v_blockers jsonb := '[]'::jsonb;
    v_r        record;
    v_list     jsonb;
    v_net      numeric;
    v_exp      numeric := 0;
    v_cash     numeric := 0;
    v_pays     text;
BEGIN
    SELECT x.* INTO b FROM mainflockbatch x WHERE x.batchid = p_batchid AND x.farmid = p_farmid;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', false, 'batchId', p_batchid, 'flocks', '[]'::jsonb,
            'blockers', jsonb_build_array(jsonb_build_object('code', 'NotFound', 'message', 'That batch does not exist on this farm.')));
    END IF;
    BEGIN v_gid := p_farmid::uuid; EXCEPTION WHEN OTHERS THEN v_gid := NULL; END;

    -- the flocks the batch was divided into
    FOR v_r IN
        SELECT f.flockid, f.name, COALESCE(f.active, true) AS active, bp.currentlivebirds, bp.productionrecordcount
        FROM   flock f
        LEFT   JOIN LATERAL fnflock_birdposition(p_farmid, f.flockid) bp ON true
        WHERE  f.farmid = p_farmid AND f.batchid = p_batchid AND NOT COALESCE(f.isdeleted, false)
        ORDER  BY f.name, f.flockid
    LOOP
        SELECT COALESCE(jsonb_agg(jsonb_build_object('label', d.label, 'rows', d.rows) ORDER BY d.rows DESC), '[]'::jsonb)
        INTO   v_list FROM fnpoultryflock_deleteblockers(p_farmid, v_r.flockid) d;
        v_flocks := v_flocks || jsonb_build_object(
            'flockId', v_r.flockid, 'name', v_r.name, 'active', v_r.active,
            'liveBirds', COALESCE(v_r.currentlivebirds, 0), 'productionRecords', COALESCE(v_r.productionrecordcount, 0),
            'records', v_list, 'canDelete', jsonb_array_length(v_list) = 0);
        IF jsonb_array_length(v_list) > 0 THEN
            v_blockers := v_blockers || jsonb_build_object('code', 'FlockHasRecords:' || v_r.flockid, 'message',
                format('Flock "%s" has %s, so it cannot be deleted. Make it inactive instead (Flocks, Edit, Inactive).',
                       v_r.name, (SELECT string_agg(x->>'rows' || ' ' || (x->>'label'), ', ') FROM jsonb_array_elements(v_list) x)));
        END IF;
    END LOOP;

    -- birds sold or lost straight from the batch (438)
    SELECT COALESCE(SUM(l.quantity), 0) INTO v_net FROM fnpoultrybirdledger_rows(p_farmid) l
    WHERE  l.batchid = p_batchid AND l.flockid IS NULL AND l.txntype <> 'Bird Batch Purchase';
    IF v_net <> 0 THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'BatchBirdsReconciled', 'message',
            format('%s birds sold or lost are recorded against this batch (Batch Bird Reconciliation). Reverse those first.', -v_net));
    END IF;

    -- Supplier Payments applied to the batch
    SELECT string_agg('#' || sa.paymentid || ' (' || trim(to_char(sa.amountapplied, 'FM999G999G999G990D00')) || ')', ', ' ORDER BY sa.paymentid)
    INTO   v_pays
    FROM   supplierpaymentallocation sa
    WHERE  sa.module = 'poultry' AND sa.documenttype = 'FlockBatch' AND sa.documentid = p_batchid
      AND  sa.farmid = p_farmid AND sa.status = 'Posted';
    IF v_pays IS NOT NULL THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'SupplierPayments', 'message',
            format('Supplier payment %s was paid against this batch. Reverse it on Supplier Payments first, so the money comes off too.', v_pays));
    END IF;

    -- the money that goes with it: the batch's cost rows and the cash they took
    IF v_gid IS NOT NULL THEN
        SELECT COALESCE(SUM(e.amount), 0) INTO v_exp FROM expense e
        WHERE  e.farmid = v_gid AND e.sourcetype = 'MainFlockBatch' AND e.sourceid = p_batchid;
        SELECT COALESCE(-SUM(t.amount), 0) INTO v_cash FROM poultrycashtransactions t
        WHERE  t.farmid = p_farmid AND t.sourcetype = 'Expense'
          AND  t.sourceid IN (SELECT e.expenseid FROM expense e
                              WHERE e.farmid = v_gid AND e.sourcetype = 'MainFlockBatch' AND e.sourceid = p_batchid);
    END IF;

    RETURN jsonb_build_object(
        'found', true, 'batchId', p_batchid, 'batchCode', b.batchcode, 'batchName', b.batchname,
        'birds', COALESCE(b.numberofbirds, 0), 'totalCost', COALESCE(b.totalcost, 0),
        'flocks', v_flocks,
        'flocksToDelete', (SELECT count(*) FROM jsonb_array_elements(v_flocks) x WHERE (x->>'canDelete')::boolean),
        'expenseRemoved', v_exp, 'cashReturned', GREATEST(v_cash, 0),
        'cashAccountName', (SELECT a.accountname FROM poultrycashaccounts a WHERE a.poultrycashaccountid = b.poultrycashaccountid),
        'blockers', v_blockers);
END $f$;

-- ------------------------------------------------------------- 2. delete -----
DROP FUNCTION IF EXISTS public.spmainflockbatch_delete(integer, text, text);
DROP FUNCTION IF EXISTS public.spmainflockbatch_delete(integer, text, text, boolean);
CREATE FUNCTION public.spmainflockbatch_delete(p_batchid integer, p_userid text, p_farmid text, p_deleteflocks boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_code  text;
    v_n     integer;
    v_net   numeric;
    v_bird  integer;
    v_pre   jsonb;
    v_names text;
    r       record;
BEGIN
    SELECT b.batchcode INTO v_code FROM mainflockbatch b
    WHERE  b.batchid = p_batchid AND b.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;

    v_pre := fnpoultrybatch_deletepreview(p_farmid, p_batchid);

    -- 506: anything that blocks it (a flock with records, birds reconciled
    -- straight from the batch, a Supplier Payment) -- the first reason.
    IF jsonb_array_length(v_pre->'blockers') > 0 THEN
        RAISE EXCEPTION 'Batch "%" cannot be deleted. %', v_code, v_pre->'blockers'->0->>'message'
            USING ERRCODE = 'P0001', HINT = 'BATCH_DELETE_BLOCKED';
    END IF;

    -- 506: its flocks go with it, but only when the user confirmed the list.
    SELECT COUNT(*), string_agg('"' || f.name || '"', ', ' ORDER BY f.name) INTO v_n, v_names FROM flock f
    WHERE  f.farmid = p_farmid AND f.batchid = p_batchid AND NOT COALESCE(f.isdeleted, FALSE);
    IF v_n > 0 AND NOT COALESCE(p_deleteflocks, false) THEN
        RAISE EXCEPTION 'Batch "%" still has % flock(s): %. Confirm that they are deleted with it.', v_code, v_n, v_names
            USING ERRCODE = 'P0001', HINT = 'BATCH_HAS_FLOCKS';
    END IF;
    FOR r IN
        SELECT f.flockid FROM flock f
        WHERE  f.farmid = p_farmid AND f.batchid = p_batchid AND NOT COALESCE(f.isdeleted, FALSE)
        ORDER  BY f.flockid
    LOOP
        -- the safe flock delete (414): releases its birds back to the batch
        PERFORM sppoultryflock_delete(p_farmid, r.flockid, p_userid);
    END LOOP;

    -- ---- from here: the 438 body, unchanged ----------------------------------
    SELECT COALESCE(SUM(l.quantity), 0) INTO v_net FROM fnpoultrybirdledger_rows(p_farmid) l
    WHERE  l.batchid = p_batchid AND l.flockid IS NULL AND l.txntype <> 'Bird Batch Purchase';
    IF v_net <> 0 THEN
        RAISE EXCEPTION 'Batch "%" has % birds sold or lost recorded against it (Batch Bird Reconciliation). Reverse those first.', v_code, -v_net
            USING ERRCODE = 'P0001';
    END IF;

    -- rows of its deleted flocks go with the batch.
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
             left('Batch ' || v_code || ' deleted: rows of its deleted flock #' || r.flockid || ' taken out', 500),
             p_userid, p_batchid, r.flockid, CURRENT_DATE, 'Batch Deleted', 'Flock');
    END LOOP;

    PERFORM sppoultrybirdstock_sync(p_farmid, 'Bird Batch Purchase', 0::numeric, p_batchid, NULL::text, p_userid);
    PERFORM spflockbatchexpense_sync(p_farmid, p_batchid, 0::numeric, NULL::timestamp, NULL::text, 0, p_userid);
    DELETE FROM mainflockbatch b WHERE b.batchid = p_batchid AND b.farmid = p_farmid;
END
$function$;

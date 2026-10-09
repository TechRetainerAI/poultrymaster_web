-- 354: reversing a sale needs a reason from the list, not an essay.
--
-- 351 required a free-text note on every reversal on top of the reason picked
-- from the list. The first UI test found that too much: picking "Wrong price"
-- or "Duplicate sale" already says why. Now the listed reason alone is enough
-- and the note is optional -- except for "Other", which says nothing on its
-- own and still needs a few words. Without a note the sale's reversal reason
-- reads just "Wrong price" (not "Wrong price: "), and the reversal record keeps
-- an empty note.
--
-- Only the reason check changes; the body is otherwise the live 351 function
-- (from pg_get_functiondef). Flock reopen passes its own note, unaffected.

CREATE OR REPLACE FUNCTION public.sppoultrysale_reverse(p_farmid text, p_saleid integer, p_reasoncode text, p_reason text, p_handling jsonb DEFAULT '{}'::jsonb, p_expectedfingerprint text DEFAULT NULL::text, p_idempotencykey text DEFAULT NULL::text, p_reversedby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_now       timestamp := (now() AT TIME ZONE 'utc');
    v_today     date      := fncompany_businessdate(p_farmid);
    v_ids       integer[];
    v_state     jsonb;
    v_item      jsonb;
    v_action    text;
    v_group     uuid;
    v_newgroup  uuid;
    v_reason    text;
    v_id        integer;
    v_existing  integer;
    v_number    text;
    v_credit    numeric(14,2) := 0;
    v_cashout   numeric(14,2) := 0;
    v_kinds     text[] := ARRAY[]::text[];
    v_s         record;
    v_amt       numeric(14,2);
    v_pid       integer;
    v_rev       jsonb := '[]'::jsonb;
BEGIN
    -- 354: a reason picked from the list is enough; the note is optional,
    -- except for 'Other', which says nothing on its own.
    IF NULLIF(btrim(COALESCE(p_reasoncode, '')), '') IS NULL AND NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for reversing this sale.' USING ERRCODE = 'P0001';
    END IF;
    IF lower(btrim(COALESCE(p_reasoncode, ''))) = 'other' AND NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Say in a few words what happened (the reason is "Other").' USING ERRCODE = 'P0001';
    END IF;
    v_reason := concat_ws(': ', NULLIF(btrim(COALESCE(p_reasoncode, '')), ''), NULLIF(btrim(COALESCE(p_reason, '')), ''));

    v_ids := fnpoultrysale_document(p_farmid, p_saleid);
    IF v_ids IS NULL THEN
        RAISE EXCEPTION 'This sale was not found for this company.' USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('poultry-salereversal:' || p_farmid || ':' || v_ids[1]::text));
    PERFORM 1 FROM sale s WHERE s.farmid = p_farmid AND s.saleid = ANY (v_ids) FOR UPDATE;

    IF p_idempotencykey IS NOT NULL THEN
        SELECT r.salereversalid INTO v_existing FROM poultrysalereversals r
        WHERE  r.farmid = p_farmid AND r.idempotencykey = p_idempotencykey;
        IF FOUND THEN RETURN v_existing; END IF;
    END IF;

    v_state := fnpoultrysale_reversalstate(p_farmid, p_saleid);
    IF jsonb_array_length(v_state->'blockers') > 0 THEN
        RAISE EXCEPTION '%', v_state->'blockers'->0->>'message' USING ERRCODE = 'P0001';
    END IF;
    IF p_expectedfingerprint IS NOT NULL AND p_expectedfingerprint <> v_state->>'fingerprint' THEN
        RAISE EXCEPTION 'This sale changed after the reversal preview was generated. Please review the updated impact before continuing.'
            USING ERRCODE = 'P0001', HINT = 'stale-preview';
    END IF;

    -- Validate every choice before changing anything.
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_state->'payments') LOOP
        v_action := COALESCE(p_handling->>(v_item->>'key'), v_item->>'default');
        IF NOT (v_item->'allowed') ? v_action THEN
            RAISE EXCEPTION '%', CASE
                WHEN v_action = 'ReversePayment' THEN COALESCE(v_item->>'reverseUnavailableReason',
                     'Payment ' || COALESCE(v_item->>'paymentNumbers', '') || ' cannot be reversed with this sale.')
                ELSE 'This sale has no customer to hold the money as credit, so the money received can only be reversed.' END
                USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    PERFORM set_config('poultry.sale_system', 'on', true);

    -- 1. Money received at the sale without a payment row becomes the SaleEntry
    --    payment it should always have been: same amount, account and date.
    --    The 'Sale' residual cash-in is replaced by the group's CashIn; the
    --    account balance does not move.
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_state->'payments') m WHERE m->>'key' = 'AT-SALE') THEN
        v_newgroup := gen_random_uuid();
        FOR v_s IN
            SELECT s.saleid, s.saledate, s.paymentmethod, s.poultrycashaccountid, s.customerid, s.totalamount,
                   GREATEST(fnpoultrysalereceived(s.paid, s.totalamount, s.amountpaid)
                            - fnpoultrysale_allocated(p_farmid, s.saleid), 0)::numeric(14,2) AS amt
            FROM   sale s WHERE s.farmid = p_farmid AND s.saleid = ANY (v_ids)
        LOOP
            CONTINUE WHEN v_s.amt <= 0;
            INSERT INTO poultrypayments
                (farmid, saleid, amount, paymentmethod, paymentdate, reference, note, createdby,
                 status, sourcetype, customerid, poultrycashaccountid, paymentgroupid)
            VALUES
                (p_farmid, v_s.saleid, v_s.amt, v_s.paymentmethod, v_s.saledate::timestamp, NULL,
                 'Received at the sale (recorded when the sale was reversed)', p_reversedby,
                 'Posted', 'SaleEntry', v_s.customerid, v_s.poultrycashaccountid, v_newgroup)
            RETURNING poultrypaymentid INTO v_pid;

            INSERT INTO customerpaymentallocation
                (farmid, module, paymentid, saleid, amountapplied, salebalancebefore, salebalanceafter,
                 status, createdby, createdat)
            VALUES
                (p_farmid, 'poultry', v_pid, v_s.saleid, v_s.amt, v_s.amt, 0, 'Posted', p_reversedby, v_now);

            PERFORM sppoultrysale_recompute(p_farmid, v_s.saleid, NULL, p_reversedby);
        END LOOP;
    END IF;

    -- 2. Pre-222 payments with no allocation row get the one they imply, so the
    --    step below can reverse it like any other.
    INSERT INTO customerpaymentallocation
        (farmid, module, paymentid, saleid, amountapplied, salebalancebefore, salebalanceafter,
         status, createdby, createdat)
    SELECT p_farmid, 'poultry', pp.poultrypaymentid, pp.saleid, pp.amount, pp.amount, 0,
           'Posted', p_reversedby, v_now
    FROM   poultrypayments pp
    WHERE  pp.farmid = p_farmid AND pp.saleid = ANY (v_ids)
      AND  COALESCE(pp.status, 'Posted') = 'Posted'
      AND  NOT EXISTS (SELECT 1 FROM customerpaymentallocation ca
                       WHERE ca.module = 'poultry' AND ca.paymentid = pp.poultrypaymentid AND ca.farmid = pp.farmid);

    -- 3. Release every allocation applied to the sale.
    UPDATE customerpaymentallocation ca
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = 'Sale reversed: ' || v_reason
    WHERE  ca.module = 'poultry' AND ca.farmid = p_farmid AND ca.saleid = ANY (v_ids)
      AND  ca.status = 'Posted';

    -- 4. Restore exactly what was sold: the egg class (or Unsorted) of the
    --    original movement, and birds through the append-only bird sync.
    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby)
    SELECT t.farmid, t.poultryproductid, 'Sale Reversal', -SUM(t.quantity), MIN(t.unitcost), t.relatedid,
           'Sale #' || t.relatedid || ' reversed', p_reversedby
    FROM   poultrystocktransactions t
    WHERE  t.farmid = p_farmid AND t.txntype = 'Sale' AND t.relatedid = ANY (v_ids)
    GROUP  BY t.farmid, t.poultryproductid, t.relatedid
    HAVING SUM(t.quantity) <> 0;

    FOR v_s IN SELECT s.saleid FROM sale s WHERE s.farmid = p_farmid AND s.saleid = ANY (v_ids) LOOP
        PERFORM sppoultrybirdstock_sync(p_farmid, 'Bird Sale', 0, v_s.saleid, NULL, p_reversedby);
    END LOOP;

    -- 5. The reversal record, then the sale itself.
    PERFORM pg_advisory_xact_lock(hashtext('poultry-salereversal-no:' || p_farmid));
    SELECT 'SR-' || lpad((COALESCE(MAX(NULLIF(regexp_replace(r.reversalnumber, '\D', '', 'g'), '')::int), 0) + 1)::text, 5, '0')
    INTO   v_number
    FROM   poultrysalereversals r WHERE r.farmid = p_farmid;

    INSERT INTO poultrysalereversals
        (farmid, reversalnumber, saleids, salegroupno, customerid, customername, saledate,
         reasoncode, reason, businessdate, occurredat, reversedby, paymenthandling,
         totalamount, paidamount, outstandingamount, idempotencykey, snapshot)
    VALUES
        (p_farmid, v_number, v_ids, v_state->>'saleGroupNo', (v_state->>'customerId')::int,
         v_state->>'customerName', (v_state->>'saleDate')::date,
         NULLIF(btrim(p_reasoncode), ''), btrim(COALESCE(p_reason, '')), v_today, v_now, p_reversedby, 'None',
         (v_state->>'total')::numeric, (v_state->>'paid')::numeric, (v_state->>'outstanding')::numeric,
         p_idempotencykey, v_state)
    RETURNING salereversalid INTO v_id;

    UPDATE sale s
    SET    status = 'Reversed', reversedat = v_now, reversedby = p_reversedby,
           reversalreason = v_reason, salereversalid = v_id,
           dateupdated = v_now, updatedby = p_reversedby
    WHERE  s.farmid = p_farmid AND s.saleid = ANY (v_ids);

    -- 6. The money: credit stays where it is; a reversal undoes the receipt.
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_state->'payments') LOOP
        v_action := COALESCE(p_handling->>(v_item->>'key'), v_item->>'default');
        v_amt    := (v_item->>'allocated')::numeric;
        v_group  := CASE WHEN v_item->>'key' = 'AT-SALE' THEN v_newgroup ELSE (v_item->>'paymentGroupId')::uuid END;

        IF v_action = 'ReversePayment' THEN
            PERFORM sppoultrycustomerpayment_reverse(p_farmid, v_group, 'Sale reversed: ' || v_reason, p_reversedby);
            v_cashout := v_cashout + v_amt;
        ELSE
            v_credit := v_credit + v_amt;
        END IF;
        v_kinds := v_kinds || v_action;

        INSERT INTO poultrysalereversalpayments
            (salereversalid, farmid, paymentgroupid, paymentnumbers, sourcetype, amount, action, recordedatreversal)
        VALUES
            (v_id, p_farmid, v_group,
             COALESCE(v_item->>'paymentNumbers',
                      (SELECT string_agg(DISTINCT pp.paymentnumber, ', ') FROM poultrypayments pp
                       WHERE pp.paymentgroupid = v_group AND pp.farmid = p_farmid)),
             v_item->>'source', v_amt, v_action, v_item->>'key' = 'AT-SALE');
    END LOOP;

    UPDATE poultrysalereversals r
    SET    creditcreated = v_credit,
           cashreversed  = v_cashout,
           paymenthandling = CASE
               WHEN array_length(v_kinds, 1) IS NULL THEN 'None'
               WHEN 'KeepAsCredit' = ALL (v_kinds) THEN 'KeepAsCredit'
               WHEN 'ReversePayment' = ALL (v_kinds) THEN 'ReversePayment'
               ELSE 'Mixed' END
    WHERE  r.salereversalid = v_id;

    PERFORM set_config('poultry.sale_system', 'off', true);
    RETURN v_id;
END
$function$;

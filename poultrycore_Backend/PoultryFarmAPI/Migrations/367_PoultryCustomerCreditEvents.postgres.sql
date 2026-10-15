-- =============================================================================
-- 367_PoultryCustomerCreditEvents.postgres.sql
--
-- Purpose (Phase 2 of the manual-entry & credits programme)
-- -------
--   1. Credit EVENTS: every payment row that holds or held customer credit,
--      with Original / Applied / Refunded / Available
--      (sppoultrycustomercredit_events). Credit stays DERIVED (351): nothing
--      is stored that could drift.
--   2. Refund a CHOSEN credit: sppoultrycustomerrefund_record gains
--      p_paymentid. Without it, refunds still take the oldest credit first.
--   3. Reverse a refund: sppoultrycustomerrefund_reverse. The refund is kept
--      (status Reversed, who / when / why); the money goes back into the SAME
--      account as a new CashIn; the credit comes back by itself, since credit
--      only subtracts Posted refunds. Cash Flow keeps the refund's Money Out
--      and adds a Money In at the reversal date; the statement does the same.
--   4. A customer payment need not be applied in full: what is left over is
--      kept as credit -- one more row in the SAME payment, with no sale and
--      sourcetype 'Deposit' (shown as "Customer advance"). Cash comes in ONCE,
--      for the whole payment. A payment with no sale at all is an advance.
--   5. "Deposit" reads "Customer advance" in the cash book and Cash Flow.
--
-- A credit that is the unapplied part of a payment is reversed with its
-- payment (Payments Received), not from Customer Credits.
--
-- Deploy order: this migration, then the API, then the web app. The old API
-- keeps working: every changed function keeps its old arguments (new ones are
-- optional), and the old web never sends a payment with a remainder.
-- =============================================================================
BEGIN;

-- ------------------------------------------------- 1. refund reversal columns --
ALTER TABLE public.poultrycustomerrefunds
    ADD COLUMN IF NOT EXISTS reversedat                timestamp,
    ADD COLUMN IF NOT EXISTS reversedby                text,
    ADD COLUMN IF NOT EXISTS reversalreason            text,
    ADD COLUMN IF NOT EXISTS reversaldate              date,
    ADD COLUMN IF NOT EXISTS reversalcashtransactionid integer;

-- ------------------------------------------------------------ patch helper --
CREATE FUNCTION pg_temp.m367_patch(p_fn text, p_marker text, p_old text, p_new text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
    v_oid oid;
    v_n   integer;
    v_def text;
    v_old text := replace(p_old, chr(13), '');
    v_new text := replace(p_new, chr(13), '');
BEGIN
    SELECT count(*), min(p.oid) INTO v_n, v_oid
    FROM   pg_proc p WHERE p.proname = p_fn AND p.pronamespace = 'public'::regnamespace;
    IF v_n <> 1 THEN
        RAISE EXCEPTION '367: expected exactly one %, found %', p_fn, v_n;
    END IF;
    v_def := replace(pg_get_functiondef(v_oid), chr(13), '');
    IF position(replace(p_marker, chr(13), '') IN v_def) > 0 THEN
        RAISE NOTICE '367: % already patched (%), skipped', p_fn, p_marker;
        RETURN;
    END IF;
    v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / greatest(length(v_old), 1);
    IF v_n <> 1 THEN
        RAISE EXCEPTION '367: anchor for % (%) found % times, expected 1', p_fn, p_marker, v_n;
    END IF;
    EXECUTE replace(v_def, v_old, v_new);
    RAISE NOTICE '367: patched % (%)', p_fn, p_marker;
END
$f$;

-- ------------------------------------------------------- 2. credit events --
-- One row per payment row that became credit. Original is what became credit
-- (the amount, less what is still applied to the payment's OWN sale); Applied
-- is what was later used on other sales; Refunded is Posted refund lines.
-- Original - Applied - Refunded = Available = fnpoultrypayment_unapplied.
CREATE OR REPLACE FUNCTION public.sppoultrycustomercredit_events(p_farmid text, p_customerid integer DEFAULT NULL)
RETURNS TABLE(poultrypaymentid integer, paymentgroupid uuid, paymentnumber text, creditdate timestamp,
              customerid integer, customername text, source text, sourcetype text, saleid integer,
              salegroupno text, reference text, originalamount numeric, applied numeric, refunded numeric,
              available numeric, status text, ismanual boolean, poultrycashaccountid integer)
LANGUAGE sql STABLE AS $f$
    WITH x AS (
        SELECT pp.*,
               COALESCE((SELECT SUM(ca.amountapplied) FROM customerpaymentallocation ca
                         WHERE ca.module = 'poultry' AND ca.paymentid = pp.poultrypaymentid
                           AND ca.farmid = pp.farmid AND ca.status = 'Posted'
                           AND ca.saleid = pp.saleid), 0) AS ownapplied,
               COALESCE((SELECT SUM(ca.amountapplied) FROM customerpaymentallocation ca
                         WHERE ca.module = 'poultry' AND ca.paymentid = pp.poultrypaymentid
                           AND ca.farmid = pp.farmid AND ca.status = 'Posted'
                           AND ca.saleid IS DISTINCT FROM pp.saleid), 0) AS otherapplied,
               COALESCE((SELECT SUM(rl.amount) FROM poultrycustomerrefundlines rl
                         JOIN poultrycustomerrefunds r ON r.refundid = rl.refundid
                         WHERE rl.poultrypaymentid = pp.poultrypaymentid AND rl.farmid = pp.farmid
                           AND r.status = 'Posted'), 0) AS refundedamt,
               EXISTS (SELECT 1 FROM customerpaymentallocation ca
                       WHERE ca.module = 'poultry' AND ca.paymentid = pp.poultrypaymentid
                         AND ca.farmid = pp.farmid) AS hasalloc,
               EXISTS (SELECT 1 FROM poultrypayments sib
                       WHERE sib.paymentgroupid = pp.paymentgroupid AND sib.farmid = pp.farmid
                         AND sib.saleid IS NOT NULL) AS hassalerows
        FROM   poultrypayments pp
        WHERE  pp.farmid = p_farmid AND pp.customerid IS NOT NULL
          AND  (p_customerid IS NULL OR pp.customerid = p_customerid)
          AND  COALESCE(pp.status, 'Posted') = 'Posted'
    )
    SELECT x.poultrypaymentid, x.paymentgroupid, x.paymentnumber::text, x.paymentdate,
           x.customerid, c.name::text,
           CASE
               WHEN x.saleid IS NULL AND x.sourcetype = 'OpeningCredit' THEN 'Opening credit'
               WHEN x.saleid IS NULL AND x.sourcetype = 'CreditNote'    THEN 'Credit note'
               WHEN x.saleid IS NULL AND x.hassalerows                  THEN 'Unapplied part of payment'
               WHEN x.saleid IS NULL                                    THEN 'Customer advance'
               WHEN s.status = 'Reversed'                               THEN 'Sale reversal - payment kept'
               ELSE 'Payment released from sale'
           END,
           x.sourcetype::text, x.saleid, s.salegroupno::text,
           COALESCE(NULLIF(btrim(x.reference), ''),
                    CASE WHEN x.saleid IS NOT NULL THEN 'Sale ' || COALESCE(s.salegroupno, '#' || x.saleid::text) END)::text,
           (x.amount - x.ownapplied)::numeric(14,2),
           x.otherapplied::numeric(14,2),
           x.refundedamt::numeric(14,2),
           fnpoultrypayment_unapplied(p_farmid, x.poultrypaymentid),
           CASE
               WHEN fnpoultrypayment_unapplied(p_farmid, x.poultrypaymentid) <= 0 AND x.refundedamt > 0 AND x.otherapplied = 0 THEN 'Refunded'
               WHEN fnpoultrypayment_unapplied(p_farmid, x.poultrypaymentid) <= 0 THEN 'Used'
               WHEN x.otherapplied > 0 OR x.refundedamt > 0 THEN 'Partly used'
               ELSE 'Available'
           END,
           (x.saleid IS NULL AND NOT x.hassalerows),
           fnpoultrypaymentgroupaccount(p_farmid, x.paymentgroupid)
    FROM   x
    LEFT   JOIN sale s ON s.saleid = x.saleid AND s.farmid = x.farmid
    LEFT   JOIN customer c ON c.customerid = x.customerid AND c.farmid = x.farmid
    -- A pre-222 sale payment with no allocation row was implicitly applied.
    WHERE  NOT (x.saleid IS NOT NULL AND NOT x.hasalloc)
      AND  (x.amount - x.ownapplied) > 0
    ORDER  BY x.paymentdate DESC, x.poultrypaymentid DESC;
$f$;

-- ------------------------------------------------ 3. refund a chosen credit --
DROP FUNCTION IF EXISTS public.sppoultrycustomerrefund_record(text, integer, numeric, integer, text, date, text, text);
CREATE FUNCTION public.sppoultrycustomerrefund_record(p_farmid text, p_customerid integer, p_amount numeric,
    p_cashaccountid integer, p_paymentmethod text, p_refunddate date, p_reason text, p_by text DEFAULT NULL::text,
    p_paymentid integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_left   numeric(14,2) := round(p_amount, 2);
    v_take   numeric(14,2);
    v_src    record;
    v_id     integer;
    v_number text;
    v_bal    numeric(14,2);
    v_txn    integer;
    v_name   text;
    v_avail  numeric(14,2);
    v_date   date := COALESCE(p_refunddate, fncompany_businessdate(p_farmid));
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Enter a refund amount greater than 0.' USING ERRCODE = 'P0001';
    END IF;
    IF p_reason IS NULL OR length(btrim(p_reason)) = 0 THEN
        RAISE EXCEPTION 'Give a reason for the refund.' USING ERRCODE = 'P0001';
    END IF;
    SELECT c.name INTO v_name FROM customer c WHERE c.customerid = p_customerid AND c.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer does not belong to this company.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM poultrycashaccounts a
                   WHERE a.poultrycashaccountid = p_cashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Choose the cash account the refund is paid from.' USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('poultry-customercredit:' || p_farmid || ':' || p_customerid::text));
    IF p_paymentid IS NOT NULL THEN
        -- 367: refund out of ONE chosen credit.
        IF NOT EXISTS (SELECT 1 FROM poultrypayments pp
                       WHERE pp.poultrypaymentid = p_paymentid AND pp.farmid = p_farmid
                         AND pp.customerid = p_customerid AND COALESCE(pp.status, 'Posted') = 'Posted') THEN
            RAISE EXCEPTION 'That credit does not belong to this customer.' USING ERRCODE = 'P0001';
        END IF;
        v_avail := fnpoultrypayment_unapplied(p_farmid, p_paymentid);
        IF v_left > v_avail THEN
            RAISE EXCEPTION 'That credit only has % available to refund.', v_avail USING ERRCODE = 'P0001';
        END IF;
    ELSIF v_left > fnpoultrycustomer_credit(p_farmid, p_customerid) THEN
        RAISE EXCEPTION 'The customer only has % of credit available to refund.', fnpoultrycustomer_credit(p_farmid, p_customerid)
            USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('poultry-refund-no:' || p_farmid));
    SELECT 'RF-' || lpad((COALESCE(MAX(NULLIF(regexp_replace(r.refundnumber, '\D', '', 'g'), '')::int), 0) + 1)::text, 5, '0')
    INTO   v_number FROM poultrycustomerrefunds r WHERE r.farmid = p_farmid;

    INSERT INTO poultrycustomerrefunds
        (farmid, refundnumber, customerid, amount, refunddate, poultrycashaccountid, paymentmethod, reason, createdby)
    VALUES
        (p_farmid, v_number, p_customerid, round(p_amount, 2), v_date, p_cashaccountid,
         NULLIF(btrim(COALESCE(p_paymentmethod, '')), ''), btrim(p_reason), p_by)
    RETURNING refundid INTO v_id;

    IF p_paymentid IS NOT NULL THEN
        INSERT INTO poultrycustomerrefundlines (refundid, farmid, poultrypaymentid, amount)
        VALUES (v_id, p_farmid, p_paymentid, v_left);
    ELSE
        FOR v_src IN SELECT * FROM sppoultrycustomercredit_list(p_farmid, p_customerid) LOOP
            EXIT WHEN v_left <= 0;
            v_take := LEAST(v_left, v_src.unapplied);
            INSERT INTO poultrycustomerrefundlines (refundid, farmid, poultrypaymentid, amount)
            VALUES (v_id, p_farmid, v_src.poultrypaymentid, v_take);
            v_left := v_left - v_take;
        END LOOP;
    END IF;

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - round(p_amount, 2), updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycashaccountid = p_cashaccountid AND a.farmid = p_farmid
    RETURNING a.currentbalance INTO v_bal;

    INSERT INTO poultrycashtransactions
        (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
         amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
    VALUES
        (p_farmid, p_cashaccountid, v_date::timestamp, 'CashOut', 'CustomerRefund', v_id,
         -round(p_amount, 2), v_bal, 'Customer refund ' || v_number || ' - ' || COALESCE(v_name, ''),
         p_by, p_by, (now() at time zone 'utc'))
    RETURNING poultrycashtransactionid INTO v_txn;

    UPDATE poultrycustomerrefunds r SET poultrycashtransactionid = v_txn WHERE r.refundid = v_id;
    RETURN v_id;
END
$function$;

-- --------------------------------------------------- 4. reverse a refund --
CREATE OR REPLACE FUNCTION public.sppoultrycustomerrefund_reverse(p_farmid text, p_refundid integer,
    p_reason text, p_by text DEFAULT NULL::text)
RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_r    record;
    v_bal  numeric(14,2);
    v_txn  integer;
    v_name text;
    v_date date := fncompany_businessdate(p_farmid);
BEGIN
    IF NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for reversing the refund.' USING ERRCODE = 'P0001';
    END IF;
    SELECT r.* INTO v_r FROM poultrycustomerrefunds r
    WHERE  r.refundid = p_refundid AND r.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Refund not found for this company.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('poultry-customercredit:' || p_farmid || ':' || v_r.customerid::text));
    IF v_r.status <> 'Posted' THEN
        RAISE EXCEPTION 'Refund % has already been reversed.', v_r.refundnumber USING ERRCODE = 'P0001';
    END IF;
    -- The money comes back into the account it left from -- never another.
    IF NOT EXISTS (SELECT 1 FROM poultrycashaccounts a
                   WHERE a.poultrycashaccountid = v_r.poultrycashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'The account this refund was paid from no longer exists.' USING ERRCODE = 'P0001';
    END IF;
    SELECT c.name INTO v_name FROM customer c WHERE c.customerid = v_r.customerid AND c.farmid = p_farmid;

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance + v_r.amount, updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycashaccountid = v_r.poultrycashaccountid AND a.farmid = p_farmid
    RETURNING a.currentbalance INTO v_bal;

    INSERT INTO poultrycashtransactions
        (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
         amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
    VALUES
        (p_farmid, v_r.poultrycashaccountid, v_date::timestamp, 'CashIn', 'CustomerRefundReversal', v_r.refundid,
         v_r.amount, v_bal, 'Refund reversal ' || v_r.refundnumber || ' - ' || COALESCE(v_name, ''),
         p_by, p_by, (now() at time zone 'utc'))
    RETURNING poultrycashtransactionid INTO v_txn;

    -- Credit only subtracts Posted refunds, so it is restored by this alone.
    UPDATE poultrycustomerrefunds r
    SET    status = 'Reversed', reversedat = (now() at time zone 'utc'), reversedby = p_by,
           reversalreason = btrim(p_reason), reversaldate = v_date, reversalcashtransactionid = v_txn
    WHERE  r.refundid = v_r.refundid;
    RETURN v_r.refundid;
END
$f$;

DROP FUNCTION IF EXISTS public.sppoultrycustomerrefund_list(text, integer);
CREATE FUNCTION public.sppoultrycustomerrefund_list(p_farmid text, p_customerid integer DEFAULT NULL::integer)
 RETURNS TABLE(refundid integer, refundnumber text, customerid integer, customername text, amount numeric,
               refunddate date, poultrycashaccountid integer, accountname text, paymentmethod text, reason text,
               status text, createdby text, createdat timestamp without time zone, paymentnumbers text,
               reversedat timestamp without time zone, reversedby text, reversalreason text, reversaldate date)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT r.refundid, r.refundnumber, r.customerid, c.name::text, r.amount, r.refunddate,
           r.poultrycashaccountid, a.accountname::text, r.paymentmethod, r.reason, r.status,
           r.createdby, r.createdat,
           (SELECT string_agg(DISTINCT pp.paymentnumber, ', ') FROM poultrycustomerrefundlines rl
            JOIN poultrypayments pp ON pp.poultrypaymentid = rl.poultrypaymentid
            WHERE rl.refundid = r.refundid)::text,
           r.reversedat, r.reversedby, r.reversalreason, r.reversaldate
    FROM   poultrycustomerrefunds r
    LEFT   JOIN customer c ON c.customerid = r.customerid AND c.farmid = r.farmid
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = r.poultrycashaccountid
    WHERE  r.farmid = p_farmid AND (p_customerid IS NULL OR r.customerid = p_customerid)
    ORDER  BY r.refunddate DESC, r.refundid DESC;
$function$;

-- Cash Flow: a reversed refund keeps its Money Out; the reversal is a Money In.
SELECT pg_temp.m367_patch('sppoultrycashflow_rows', '367: a reversed refund keeps its Money Out',
$o$      AND  r.status = 'Posted'
      AND  r.refunddate::timestamp >= v_from
      AND  r.refunddate::timestamp <= v_to;$o$,
$n$      AND  r.status IN ('Posted', 'Reversed')   -- 367: a reversed refund keeps its Money Out
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
      AND  r.reversaldate::timestamp <= v_to;$n$);

SELECT pg_temp.m367_patch('sppoultrycashflow_detail', '367: refund reversal',
$o$               WHEN r.rowsource = 'CustomerRefund'  THEN 'Customer refunds'$o$,
$n$               WHEN r.rowsource = 'CustomerRefund'  THEN 'Customer refunds'
               WHEN r.rowsource = 'CustomerRefundReversal' THEN 'Customer refunds'   -- 367: refund reversal$n$);

-- Statement: the refund stays; its reversal is a credit line.
SELECT pg_temp.m367_patch('sppoultrycustomerstatement', '367: a reversed refund',
$o$        FROM   poultrycustomerrefunds r
        WHERE  r.farmid = p_farmid AND r.customerid = p_customerid AND r.status = 'Posted'
          AND  (p_from IS NULL OR r.refunddate >= p_from)
          AND  (p_to   IS NULL OR r.refunddate <= p_to)$o$,
$n$        FROM   poultrycustomerrefunds r
        WHERE  r.farmid = p_farmid AND r.customerid = p_customerid
          AND  r.status IN ('Posted', 'Reversed')   -- 367: a reversed refund stays listed
          AND  (p_from IS NULL OR r.refunddate >= p_from)
          AND  (p_to   IS NULL OR r.refunddate <= p_to)

        UNION ALL

        -- 367: a reversed refund: the money came back, the credit with it.
        SELECT r.reversaldate, 'RefundReversal'::text, r.refundnumber::text,
               ('Refund reversed - ' || COALESCE(r.reversalreason, ''))::text,
               0::numeric(14,2), r.amount::numeric(14,2), NULL::integer, 3, 1,
               NULL::uuid, NULL::integer, 'RefundReversal'::text
        FROM   poultrycustomerrefunds r
        WHERE  r.farmid = p_farmid AND r.customerid = p_customerid AND r.status = 'Reversed'
          AND  r.reversaldate IS NOT NULL
          AND  (p_from IS NULL OR r.reversaldate >= p_from)
          AND  (p_to   IS NULL OR r.reversaldate <= p_to)$n$);

-- ------------------------------- 5. a payment with money left over (advance) --
SELECT pg_temp.m367_patch('sppoultrycustomerpayment_record', '367: need not be applied in full',
$o$    IF v_count = 0 THEN
        RAISE EXCEPTION 'Select at least one sale to apply this payment to.';
    END IF;$o$,
$n$    -- 367: need not be applied in full. What is left is kept as the customer's
    -- credit -- one more row in this payment, with no sale.
    IF v_count = 0 AND p_cashaccountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account the money was received into.';
    END IF;$n$);

SELECT pg_temp.m367_patch('sppoultrycustomerpayment_record', '367: more than the payment',
$o$    IF v_minamount <= 0 THEN
        RAISE EXCEPTION 'Each allocation must be greater than 0.';
    END IF;
    IF v_allocated::numeric(14,2) <> p_amount::numeric(14,2) THEN
        RAISE EXCEPTION 'Allocated total (%) must equal the payment amount (%).',
              v_allocated::numeric(14,2), p_amount::numeric(14,2);
    END IF;$o$,
$n$    IF v_count > 0 AND v_minamount <= 0 THEN
        RAISE EXCEPTION 'Each allocation must be greater than 0.';
    END IF;
    IF v_allocated::numeric(14,2) > p_amount::numeric(14,2) THEN   -- 367: more than the payment
        RAISE EXCEPTION 'Allocated total (%) is more than the payment amount (%).',
              v_allocated::numeric(14,2), p_amount::numeric(14,2);
    END IF;
    IF v_allocated::numeric(14,2) < round(p_amount, 2) AND p_cashaccountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account, so the amount kept as credit has somewhere to land.';
    END IF;$n$);

SELECT pg_temp.m367_patch('sppoultrycustomerpayment_record', '367: the part kept as credit',
$o$    FOR v_row IN
        SELECT a.saleid, a.amount::numeric(14,2) AS amount,$o$,
$n$    -- 367: the part kept as credit. Inserted before the sale rows, so every
    -- cash sync below already sees the whole payment.
    IF round(p_amount, 2) > v_allocated::numeric(14,2) THEN
        INSERT INTO poultrypayments
            (farmid, saleid, amount, paymentmethod, paymentdate, reference, note,
             createdby, status, sourcetype, customerid, poultrycashaccountid, paymentgroupid)
        VALUES
            (p_farmid, NULL, round(p_amount, 2) - v_allocated::numeric(14,2), p_paymentmethod, v_date,
             p_reference, p_note, p_createdby, 'Posted', 'Deposit', p_customerid, p_cashaccountid, v_group);
    END IF;

    FOR v_row IN
        SELECT a.saleid, a.amount::numeric(14,2) AS amount,$n$);

SELECT pg_temp.m367_patch('sppoultrycustomerpayment_record', '367: one CashIn',
$o$    RETURN v_group;
END;$o$,
$n$    -- 367: one CashIn for the whole payment (a no-op when a sale already synced it).
    PERFORM sppoultrycustomerpaymentcash_sync(p_farmid, v_group, p_createdby);
    RETURN v_group;
END;$n$);

-- A payment that paid sales AND kept the rest as credit is reversed as a
-- payment; only a credit with no sale at all is a "manual" credit.
SELECT pg_temp.m367_patch('sppoultrycustomerpayment_reverse', '367: only a credit with no sale',
$o$               WHERE pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid AND pp.saleid IS NULL)
       AND COALESCE(current_setting('poultry.manualcredit_reverse', true), '') <> 'on' THEN$o$,
$n$               WHERE pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid AND pp.saleid IS NULL)
       -- 367: only a credit with no sale at all; a payment with a part kept as credit is a payment.
       AND NOT EXISTS (SELECT 1 FROM poultrypayments pp
                       WHERE pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid AND pp.saleid IS NOT NULL)
       AND COALESCE(current_setting('poultry.manualcredit_reverse', true), '') <> 'on' THEN$n$);

SELECT pg_temp.m367_patch('sppoultrycustomercredit_reverse', '367: the unapplied part of a payment',
$o$        RAISE EXCEPTION 'That is not a manually created credit for this company.' USING ERRCODE = 'P0001';
    END IF;$o$,
$n$        RAISE EXCEPTION 'That is not a manually created credit for this company.' USING ERRCODE = 'P0001';
    END IF;
    -- 367: the unapplied part of a payment goes with its payment.
    IF EXISTS (SELECT 1 FROM poultrypayments pp
               WHERE pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid AND pp.saleid IS NOT NULL) THEN
        RAISE EXCEPTION 'This credit is the part of a customer payment that was not applied to a sale. Reverse the payment from Payments Received.' USING ERRCODE = 'P0001';
    END IF;$n$);

SELECT pg_temp.m367_patch('sppoultrycustomercredit_manuallist', '367: not the unapplied part of a payment',
$o$    WHERE  pp.farmid = p_farmid AND pp.saleid IS NULL
      AND  pp.sourcetype IN ('OpeningCredit', 'Deposit', 'CreditNote')$o$,
$n$    WHERE  pp.farmid = p_farmid AND pp.saleid IS NULL
      AND  pp.sourcetype IN ('OpeningCredit', 'Deposit', 'CreditNote')
      -- 367: not the unapplied part of a payment (that payment also paid sales).
      AND  NOT EXISTS (SELECT 1 FROM poultrypayments sib
                       WHERE sib.paymentgroupid = pp.paymentgroupid AND sib.farmid = pp.farmid
                         AND sib.saleid IS NOT NULL)$n$);

-- ---------------------------------------------- 6. "Deposit" -> "advance" --
SELECT pg_temp.m367_patch('sppoultrycustomerpaymentcash_sync', '367: Customer advance',
$o$    v_in_desc := CASE WHEN EXISTS (SELECT 1 FROM poultrypayments pp
                                   WHERE pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid
                                     AND pp.sourcetype = 'Deposit')
                      THEN 'Customer deposit' ELSE 'Customer payment' END$o$,
$n$    -- 367: Customer advance -- money with no sale at all.
    v_in_desc := CASE WHEN NOT EXISTS (SELECT 1 FROM poultrypayments pp
                                       WHERE pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid
                                         AND pp.saleid IS NOT NULL)
                      THEN 'Customer advance' ELSE 'Customer payment' END$n$);

SELECT pg_temp.m367_patch('sppoultrycashflow_rows', '367: advance, received',
$o$                    WHEN COUNT(p.saleid) = 0 THEN 'Customer deposit'   -- 363: deposit, received$o$,
$n$                    WHEN COUNT(p.saleid) = 0 THEN 'Customer advance'   -- 367: advance, received$n$);

SELECT pg_temp.m367_patch('sppoultrycashflow_rows', '367: advance, reversed',
$o$                    WHEN COUNT(p.saleid) = 0 THEN 'Customer deposit'   -- 363: deposit, reversed$o$,
$n$                    WHEN COUNT(p.saleid) = 0 THEN 'Customer advance'   -- 367: advance, reversed$n$);

SELECT pg_temp.m367_patch('sppoultrycustomercredit_create', '367: an advance',
$o$        RAISE EXCEPTION 'Choose what the credit is: an opening balance, a deposit or a credit note.' USING ERRCODE = 'P0001';$o$,
$n$        RAISE EXCEPTION 'Choose what the credit is: an opening balance, an advance or a credit note.' USING ERRCODE = 'P0001';   -- 367: an advance$n$);

SELECT pg_temp.m367_patch('sppoultrycustomercredit_create', '367: advance account',
$o$            RAISE EXCEPTION 'Choose the cash account the deposit was received into.' USING ERRCODE = 'P0001';$o$,
$n$            RAISE EXCEPTION 'Choose the cash account the advance was received into.' USING ERRCODE = 'P0001';   -- 367: advance account$n$);

SELECT pg_temp.m367_patch('sppoultrycustomercredit_create', '367: only an advance',
$o$        RAISE EXCEPTION 'Only a deposit moves cash; an opening credit or credit note has no cash account.' USING ERRCODE = 'P0001';$o$,
$n$        RAISE EXCEPTION 'Only an advance moves cash; an opening credit or credit note has no cash account.' USING ERRCODE = 'P0001';   -- 367: only an advance$n$);

-- Cash book rows written as "Customer deposit" before this read the same way.
UPDATE public.poultrycashtransactions ct
SET    description = 'Customer advance' || substr(ct.description, length('Customer deposit') + 1)
WHERE  ct.description LIKE 'Customer deposit%';

COMMIT;

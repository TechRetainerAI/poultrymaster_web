-- 353: the customer-payment cash sync keeps the receipt row it already wrote.
--
-- 351 made the payment-group cash ledger append-only in MEANING (the CashIn
-- keeps everything the group ever received; a reversal is a separate CashOut)
-- but sppoultrycustomerpaymentcash_sync still deleted every row of the group
-- and wrote it again on every call. Found in the first UI test (Gyimah Farm,
-- SR-00001): reversing sale #2571 replaced its 19:12 receipt with a new row
-- stamped 19:14, so the receipt's entry time (Running Cash, Financial
-- Activity), creator and bank-clearing mark were silently lost.
--
-- Now a row that already matches is UPDATED in place (only when its amount
-- actually changed), and only a row that no longer fits -- the group moved to
-- another account, or was split over several -- falls back to delete + insert.
-- Totals, dates and descriptions are exactly what 351 wrote, so no number in
-- any report moves; only rows that would have been rewritten survive instead.

CREATE OR REPLACE FUNCTION public.sppoultrycustomerpaymentcash_sync(p_farmid text, p_paymentgroupid uuid, p_createdby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_acct     integer;
    v_received numeric(14,2);
    v_reversed numeric(14,2);
    v_date     timestamp;
    v_revat    timestamp;
    v_srcid    integer;
    v_name     text;
    v_number   text;
    v_bal      numeric(14,2);
    v_in_n     integer;
    v_in_id    integer;
    v_in_acct  integer;
    v_in_amt   numeric(14,2);
    v_out_n    integer;
    v_out_id   integer;
    v_out_acct integer;
    v_out_amt  numeric(14,2);
    v_in_desc  text;
    v_out_desc text;
    v_out_date timestamp;
BEGIN
    SELECT COALESCE(SUM(pp.amount), 0)::numeric(14,2),
           COALESCE(SUM(pp.amount) FILTER (WHERE COALESCE(pp.status, 'Posted') = 'Reversed'), 0)::numeric(14,2),
           MIN(pp.paymentdate),
           MAX(pp.reversedat),
           MIN(pp.poultrypaymentid),
           MIN(c.name)::text,
           MIN(pp.paymentnumber)::text
    INTO   v_received, v_reversed, v_date, v_revat, v_srcid, v_name, v_number
    FROM   poultrypayments pp
    LEFT   JOIN customer c ON c.customerid = pp.customerid AND c.farmid = pp.farmid
    WHERE  pp.paymentgroupid = p_paymentgroupid
      AND  pp.farmid = p_farmid;

    IF COALESCE(v_received, 0) > 0 THEN
        v_acct := fnpoultrypaymentgroupaccount_any(p_farmid, p_paymentgroupid);
    END IF;

    SELECT count(*), MIN(ct.poultrycashtransactionid), MIN(ct.poultrycashaccountid), COALESCE(SUM(ct.amount), 0)
    INTO   v_in_n, v_in_id, v_in_acct, v_in_amt
    FROM   poultrycashtransactions ct
    WHERE  ct.sourcetype = 'CustomerPayment' AND ct.paymentgroupid = p_paymentgroupid AND ct.farmid = p_farmid;

    SELECT count(*), MIN(ct.poultrycashtransactionid), MIN(ct.poultrycashaccountid), COALESCE(SUM(ct.amount), 0)
    INTO   v_out_n, v_out_id, v_out_acct, v_out_amt
    FROM   poultrycashtransactions ct
    WHERE  ct.sourcetype = 'CustomerPaymentReversal' AND ct.paymentgroupid = p_paymentgroupid AND ct.farmid = p_farmid;

    -- Nothing received, or no account to hold it: the group has no cash rows
    -- (same as 351).
    IF COALESCE(v_received, 0) <= 0 OR v_acct IS NULL THEN
        v_in_id := NULL; v_out_id := NULL;
    ELSE
        -- A row is kept only if it is the group's single row of its kind and
        -- already sits on the group's account.
        IF NOT (v_in_n = 1 AND v_in_acct = v_acct) THEN v_in_id := NULL; END IF;
        IF NOT (v_out_n = 1 AND v_out_acct = v_acct AND v_reversed > 0) THEN v_out_id := NULL; END IF;
    END IF;

    -- Undo and remove every row that is not kept.
    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - t.net, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT ct.poultrycashaccountid, SUM(ct.amount) AS net
        FROM   poultrycashtransactions ct
        WHERE  ct.sourcetype IN ('CustomerPayment', 'CustomerPaymentReversal')
          AND  ct.paymentgroupid = p_paymentgroupid
          AND  ct.farmid = p_farmid
          AND  ct.poultrycashtransactionid IS DISTINCT FROM v_in_id
          AND  ct.poultrycashtransactionid IS DISTINCT FROM v_out_id
        GROUP  BY ct.poultrycashaccountid
    ) t
    WHERE  t.poultrycashaccountid = a.poultrycashaccountid
      AND  a.farmid = p_farmid;

    DELETE FROM poultrycashtransactions ct
    WHERE  ct.sourcetype IN ('CustomerPayment', 'CustomerPaymentReversal')
      AND  ct.paymentgroupid = p_paymentgroupid
      AND  ct.farmid = p_farmid
      AND  ct.poultrycashtransactionid IS DISTINCT FROM v_in_id
      AND  ct.poultrycashtransactionid IS DISTINCT FROM v_out_id;

    IF COALESCE(v_received, 0) <= 0 OR v_acct IS NULL THEN RETURN; END IF;

    v_in_desc := 'Customer payment' || COALESCE(' from ' || NULLIF(btrim(v_name), ''), '');

    -- The receipt: everything the group ever received.
    IF v_in_id IS NOT NULL THEN
        IF v_in_amt <> v_received THEN
            UPDATE poultrycashaccounts a
            SET    currentbalance = a.currentbalance + (v_received - v_in_amt), updatedat = (now() at time zone 'utc')
            WHERE  a.poultrycashaccountid = v_acct AND a.farmid = p_farmid;
            SELECT a.currentbalance INTO v_bal FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct LIMIT 1;
            UPDATE poultrycashtransactions
            SET    amount = v_received, balanceaftertransaction = v_bal
            WHERE  poultrycashtransactionid = v_in_id;
        END IF;
        UPDATE poultrycashtransactions
        SET    transactiondate = COALESCE(v_date, transactiondate),
               sourceid        = v_srcid,
               description     = v_in_desc
        WHERE  poultrycashtransactionid = v_in_id
          AND  (transactiondate IS DISTINCT FROM COALESCE(v_date, transactiondate)
                OR sourceid IS DISTINCT FROM v_srcid OR description IS DISTINCT FROM v_in_desc);
    ELSE
        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance + v_received, updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = v_acct AND a.farmid = p_farmid;
        SELECT a.currentbalance INTO v_bal FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct LIMIT 1;

        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             paymentgroupid, amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_acct, COALESCE(v_date, (now() at time zone 'utc')), 'CashIn',
             'CustomerPayment', v_srcid, p_paymentgroupid, v_received, v_bal, v_in_desc,
             p_createdby, p_createdby, (now() at time zone 'utc'));
    END IF;

    IF v_reversed <= 0 THEN RETURN; END IF;

    -- The reversal leg: what was reversed, on the reversal's business day.
    v_out_desc := 'Payment reversal' || COALESCE(' ' || v_number, '') || COALESCE(' - ' || NULLIF(btrim(v_name), ''), '');
    v_out_date := COALESCE(fnpoultry_businessdateof(p_farmid, v_revat), fncompany_businessdate(p_farmid))::timestamp;

    IF v_out_id IS NOT NULL THEN
        IF v_out_amt <> -v_reversed THEN
            UPDATE poultrycashaccounts a
            SET    currentbalance = a.currentbalance + (-v_reversed - v_out_amt), updatedat = (now() at time zone 'utc')
            WHERE  a.poultrycashaccountid = v_acct AND a.farmid = p_farmid;
            SELECT a.currentbalance INTO v_bal FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct LIMIT 1;
            -- More of the group was reversed later: the leg moves to that day.
            UPDATE poultrycashtransactions
            SET    amount = -v_reversed, balanceaftertransaction = v_bal, transactiondate = v_out_date
            WHERE  poultrycashtransactionid = v_out_id;
        END IF;
        UPDATE poultrycashtransactions
        SET    sourceid = v_srcid, description = v_out_desc
        WHERE  poultrycashtransactionid = v_out_id
          AND  (sourceid IS DISTINCT FROM v_srcid OR description IS DISTINCT FROM v_out_desc);
    ELSE
        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance - v_reversed, updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = v_acct AND a.farmid = p_farmid;
        SELECT a.currentbalance INTO v_bal FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct LIMIT 1;

        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             paymentgroupid, amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_acct, v_out_date,
             'CashOut', 'CustomerPaymentReversal', v_srcid, p_paymentgroupid, -v_reversed, v_bal, v_out_desc,
             p_createdby, p_createdby, (now() at time zone 'utc'));
    END IF;
END;
$function$;

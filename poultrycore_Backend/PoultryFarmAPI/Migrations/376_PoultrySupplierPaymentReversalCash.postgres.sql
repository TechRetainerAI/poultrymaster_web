-- =============================================================================
-- 376_PoultrySupplierPaymentReversalCash.postgres.sql            (requires 370)
--
-- Purpose
-- -------
-- Reversing a supplier payment used to ERASE it from the money record:
--   * the cash book: sppoultrysupplierpaymentcash_sync deleted the payment's
--     CashOut row from poultrycashtransactions;
--   * Cash Flow: every supplier-payment arm of sppoultrycashflow_rows reads
--     Posted payments only, and the reversal deletes the expense rows the
--     payment booked, so the payment vanished from the day it was made.
--
-- From here a reversal is a NEW entry, never a deletion -- the same rule as a
-- reversed customer receipt (351):
--   * the payment keeps its Money Out on its own date (cash book row
--     'PoultrySupplierPayment', Cash Flow arm 3i);
--   * the reversal is its own Money In on the business day it was reversed
--     (cash book row 'PoultrySupplierPaymentReversal', Cash Flow arm 3j).
-- The two net to zero, so balances are exactly what they were.
--
-- Backfill: payments already reversed get both rows. Each account's balance is
-- unchanged (-amount + amount); only the number of cash book rows grows.
--
-- Manual supplier credits (370) still post no cash at all.
-- No signature changes: the API needs no deploy for this.
-- =============================================================================
BEGIN;

-- ------------------------------------------------- 1. the cash book --------
CREATE OR REPLACE FUNCTION public.sppoultrysupplierpaymentcash_sync(p_farmid text, p_paymentid integer, p_createdby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_acct   integer;
    v_amt    numeric(14,2);
    v_status text;
    v_name   text;
    v_bal    numeric(14,2);
    v_date   timestamp;          -- 229: added
    v_revat  timestamp;          -- 376
    v_revdate timestamp;         -- 376
BEGIN
    -- Undo and remove this payment's cash rows (376: and its reversal row).
    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - t.net, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT ct.poultrycashaccountid, SUM(ct.amount) AS net
        FROM   poultrycashtransactions ct
        WHERE  ct.sourcetype IN ('PoultrySupplierPayment', 'PoultrySupplierPaymentReversal')
          AND  ct.sourceid = p_paymentid
          AND  ct.farmid = p_farmid
        GROUP  BY ct.poultrycashaccountid
    ) t
    WHERE  t.poultrycashaccountid = a.poultrycashaccountid AND a.farmid = p_farmid;

    DELETE FROM poultrycashtransactions ct
    WHERE  ct.sourcetype IN ('PoultrySupplierPayment', 'PoultrySupplierPaymentReversal')
      AND  ct.sourceid = p_paymentid
      AND  ct.farmid = p_farmid;

    SELECT sp.poultrycashaccountid, sp.totalamount, sp.status, s.name, sp.paymentdate, sp.reversedat
    INTO   v_acct, v_amt, v_status, v_name, v_date, v_revat
    FROM   poultrysupplierpayments sp
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.poultrysupplierpaymentid = p_paymentid AND sp.farmid = p_farmid
    LIMIT  1;

    -- 376: a REVERSED payment still went out on its day -- it keeps its CashOut
    -- and gets a separate CashIn for the reversal below.
    IF (v_acct IS NOT NULL AND COALESCE(v_amt, 0) > 0
        AND COALESCE(v_status, 'Posted') IN ('Posted', 'Reversed')
        -- 370: a manual credit posts no cash
        AND NOT EXISTS (SELECT 1 FROM poultrysupplierpayments x
                        WHERE  x.poultrysupplierpaymentid = p_paymentid AND x.farmid = p_farmid
                          AND  fnpoultrysupplier_iscreditkind(x.sourcetype))
        AND EXISTS (SELECT 1 FROM poultrycashaccounts a
                    WHERE a.poultrycashaccountid = v_acct AND a.farmid = p_farmid)) THEN

        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance - v_amt, updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = v_acct AND a.farmid = p_farmid;

        SELECT a.currentbalance INTO v_bal
        FROM   poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct LIMIT 1;

        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
        VALUES
            -- 229: transactiondate was (now() at time zone 'utc'). approvedat
            -- stays as now() -- that one IS a posting fact.
            (p_farmid, v_acct, COALESCE(v_date, (now() at time zone 'utc')),
             'CashOut', 'PoultrySupplierPayment',
             p_paymentid, -v_amt, v_bal,
             'Supplier payment: ' || COALESCE(v_name, 'supplier'), p_createdby, p_createdby,
             (now() at time zone 'utc'));

        -- 376: the reversal leg -- the money comes back, on the business day
        -- of the reversal.
        IF v_status = 'Reversed' THEN
            v_revdate := COALESCE(fnpoultry_businessdateof(p_farmid, v_revat), fncompany_businessdate(p_farmid))::timestamp;

            UPDATE poultrycashaccounts a
            SET    currentbalance = a.currentbalance + v_amt, updatedat = (now() at time zone 'utc')
            WHERE  a.poultrycashaccountid = v_acct AND a.farmid = p_farmid;

            SELECT a.currentbalance INTO v_bal
            FROM   poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct LIMIT 1;

            INSERT INTO poultrycashtransactions
                (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
                 amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
            VALUES
                (p_farmid, v_acct, v_revdate,
                 'CashIn', 'PoultrySupplierPaymentReversal',
                 p_paymentid, v_amt, v_bal,
                 'Supplier payment reversal #' || p_paymentid::text || ': ' || COALESCE(v_name, 'supplier'),
                 p_createdby, p_createdby, (now() at time zone 'utc'));
        END IF;
    END IF;
END;
$function$;

-- ------------------------------------------------- 2. Cash Flow ------------
CREATE FUNCTION pg_temp.m376_patch(p_fn text, p_marker text, p_old text, p_new text)
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
        RAISE EXCEPTION '376: expected exactly one %, found %', p_fn, v_n;
    END IF;
    v_def := replace(pg_get_functiondef(v_oid), chr(13), '');
    IF position(replace(p_marker, chr(13), '') IN v_def) > 0 THEN
        RAISE NOTICE '376: % already patched (%), skipped', p_fn, p_marker;
        RETURN;
    END IF;
    v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / greatest(length(v_old), 1);
    IF v_n <> 1 THEN
        RAISE EXCEPTION '376: anchor for % (%) found % times, expected %', p_fn, p_marker, v_n, 1;
    END IF;
    EXECUTE replace(v_def, v_old, v_new);
    RAISE NOTICE '376: patched % (%)', p_fn, p_marker;
END
$f$;

SELECT pg_temp.m376_patch('sppoultrycashflow_rows', '3i. (376)',
$o$    -- ---- 3g. (370) a supplier sends money back out of credit: Money In ------$o$,
$n$    -- ---- 3i. (376) a REVERSED supplier payment still went out on its day ---
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

    -- ---- 3g. (370) a supplier sends money back out of credit: Money In ------$n$);

-- ------------------------------------------------- 3. backfill -------------
-- Payments reversed before 376 lost their cash book row: give them back the
-- payment and add the reversal. Net zero on every balance.
DO $$
DECLARE
    v_r record;
    v_n integer := 0;
BEGIN
    FOR v_r IN
        SELECT sp.farmid, sp.poultrysupplierpaymentid
        FROM   poultrysupplierpayments sp
        WHERE  sp.status = 'Reversed'
          AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)
        ORDER  BY sp.poultrysupplierpaymentid
    LOOP
        PERFORM sppoultrysupplierpaymentcash_sync(v_r.farmid, v_r.poultrysupplierpaymentid, 'migration376');
        v_n := v_n + 1;
    END LOOP;
    RAISE NOTICE '376: % reversed supplier payment(s) given their cash book rows back', v_n;
END
$$;

COMMIT;

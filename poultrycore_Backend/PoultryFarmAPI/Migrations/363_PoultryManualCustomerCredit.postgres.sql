-- =============================================================================
-- 363_PoultryManualCustomerCredit.postgres.sql
--
-- Purpose
-- -------
-- Let the owner or an admin CREATE customer credit by hand (poultry). Until
-- now credit only arose from a payment kept when its sale was reversed.
--
-- Three kinds, each saying where the money came from, never a typed balance:
--
--   OpeningCredit  credit the customer already had before the farm started
--                  using the system. No cash, no profit or loss.
--   Deposit        the customer pays in advance, with no sale yet. REAL cash
--                  in to the chosen account (Cash Flow Money In).
--   CreditNote     goodwill credit the business gives (broken eggs, a late
--                  delivery...). No cash; it is a cost, shown on Profit & Loss
--                  as a negative revenue line "Credit Notes & Allowances".
--
-- THE MODEL
-- ---------
-- Credit is DERIVED (351): a Posted payment's amount - its Posted allocations
-- - its refund lines. A manual credit is therefore a poultrypayments row with
-- NO sale (saleid NULL) and the kind as its sourcetype. Applying it to a sale
-- (sppoultrycustomercredit_apply), refunding it (sppoultrycustomerrefund_record),
-- the credit pages and the Add Sale "Use customer credit" all work on it
-- unchanged. A mistake is reversed (sppoultrycustomercredit_reverse), never
-- edited or deleted.
--
-- LIVE-BODY PATCHES
-- -----------------
-- 33 live functions read poultrypayments; every one was audited for a row
-- with saleid NULL. 14 needed a change, patched below in place from
-- pg_get_functiondef (anchors must match exactly once, or the migration
-- RAISES and nothing is applied):
--   critical  fnpoultrypayment_unapplied  ("no allocation = implicitly applied"
--                                          would read every manual credit as 0)
--             sppoultrysalecash_sync      (credit-paid part of a sale would
--                                          post a phantom 'Sale' CashIn)
--   reversal  fnpoultrysale_reversalstate, spflock_reopen,
--             sppoultrycustomerpayment_reverse (a Deposit's cash-out; a manual
--             credit is only reversed through sppoultrycustomercredit_reverse)
--   not money received (Opening / CreditNote have no cash):
--             sppoultrycashflow_rows, fnpoultrydailyclosing_livetotals,
--             sppoultrycustomerbalancesummary, sppoultrydailyclosing_workspace_core,
--             fnpoultryfa_positions, sppoultrycustomerbalances
--   display   sppoultrycustomerpayment_history, sppoultrycustomerstatement,
--             sppoultrycustomerpaymentcash_sync (Deposit wording)
--   guard     spsale_delete (a sale with credit applied cannot be discarded)
-- plus Profit & Loss: sppoultryreport_pllines and sppoultryreport_plrevenuedetail.
--
-- Re-running is safe: each patch is skipped when its marker is already there.
-- =============================================================================

BEGIN;

-- ------------------------------------------------------------- 1. the table --
ALTER TABLE public.poultrypayments ALTER COLUMN saleid DROP NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_poultrypayments_saleorcredit') THEN
        ALTER TABLE public.poultrypayments ADD CONSTRAINT ck_poultrypayments_saleorcredit
            CHECK (saleid IS NOT NULL
                   OR (sourcetype IN ('OpeningCredit', 'Deposit', 'CreditNote') AND customerid IS NOT NULL));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_poultrypayments_manualcredit
    ON public.poultrypayments (farmid, paymentdate) WHERE saleid IS NULL;

-- ------------------------------------------------------- 2. patch helper --
CREATE FUNCTION pg_temp.m363_patch(p_fn text, p_marker text, p_old text, p_new text)
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
        RAISE EXCEPTION '363: expected exactly one %, found %', p_fn, v_n;
    END IF;
    v_def := replace(pg_get_functiondef(v_oid), chr(13), '');
    IF position(replace(p_marker, chr(13), '') IN v_def) > 0 THEN
        RAISE NOTICE '363: % already patched (%), skipped', p_fn, p_marker;
        RETURN;
    END IF;
    v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / greatest(length(v_old), 1);
    IF v_n <> 1 THEN
        RAISE EXCEPTION '363: anchor for % (%) found % times, expected 1', p_fn, p_marker, v_n;
    END IF;
    EXECUTE replace(v_def, v_old, v_new);
    RAISE NOTICE '363: patched % (%)', p_fn, p_marker;
END
$f$;

-- ------------------------------------------- 3. critical: credit is seen --
SELECT pg_temp.m363_patch('fnpoultrypayment_unapplied', '363: a manual credit',
$o$             WHEN NOT EXISTS (SELECT 1 FROM customerpaymentallocation ca$o$,
$n$             -- 363: a manual credit (saleid NULL) has no sale to be implicitly applied to.
             WHEN pp.saleid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM customerpaymentallocation ca$n$);

-- ---------------------------- 4. critical: no phantom cash on a credit-paid sale --
SELECT pg_temp.m363_patch('sppoultrysalecash_sync', 'pp.saleid IS DISTINCT FROM p_saleid',
$o$      AND  (pp.saleid <> p_saleid
            OR fnpoultrypaymentgroupaccount(p_farmid, pp.paymentgroupid) IS NOT NULL);$o$,
$n$      AND  (pp.saleid IS DISTINCT FROM p_saleid   -- 363: manual credit (saleid NULL) counts
            OR fnpoultrypaymentgroupaccount(p_farmid, pp.paymentgroupid) IS NOT NULL);$n$);

-- -------------------------------------------------------- 5. reversal --
-- A manual credit is never "wholly this sale's": reversing a sale it paid
-- releases the allocation back to credit, it never voids the credit itself.
SELECT pg_temp.m363_patch('fnpoultrysale_reversalstate', 'pp.saleid IS NULL OR pp.saleid <> ALL (v_ids)',
$o$                                  AND pp.saleid <> ALL (v_ids))$o$,
$n$                                  AND (pp.saleid IS NULL OR pp.saleid <> ALL (v_ids)))$n$);

SELECT pg_temp.m363_patch('spflock_reopen', '363: a credit-paid sale',
$o$                    (SELECT COALESCE(jsonb_object_agg(m->>'key', 'ReversePayment'), '{}'::jsonb)$o$,
$n$                    -- 363: a credit-paid sale can only hand its credit back (KeepAsCredit).
                    (SELECT COALESCE(jsonb_object_agg(m->>'key',
                                CASE WHEN m->'allowed' ? 'ReversePayment' THEN 'ReversePayment' ELSE 'KeepAsCredit' END),
                            '{}'::jsonb)$n$);

SELECT pg_temp.m363_patch('sppoultrycustomerpayment_reverse', 'FILTER (WHERE x.saleid IS NOT NULL)',
$o$    SELECT array_agg(DISTINCT x.saleid) INTO v_sales$o$,
$n$    SELECT array_agg(DISTINCT x.saleid) FILTER (WHERE x.saleid IS NOT NULL) INTO v_sales$n$);

SELECT pg_temp.m363_patch('sppoultrycustomerpayment_reverse', '363: a group with no row on a sale',
$o$    RETURN v_count;
END;$o$,
$n$    -- 363: a group with no row on a sale (a manual Deposit) is never reached
    -- by the recompute loop above, so sync its cash here. A no-op otherwise.
    PERFORM sppoultrycustomerpaymentcash_sync(p_farmid, p_paymentgroupid, p_reversedby);

    RETURN v_count;
END;$n$);

-- A manual credit is undone only through sppoultrycustomercredit_reverse
-- (owner / admin, from Customer Credits), never as an ordinary payment.
SELECT pg_temp.m363_patch('sppoultrycustomerpayment_reverse', '363: manual credit is reversed from Customer Credits',
$o$    PERFORM pg_advisory_xact_lock(hashtext('poultry-paymentgroup:' || p_paymentgroupid::text));$o$,
$n$    PERFORM pg_advisory_xact_lock(hashtext('poultry-paymentgroup:' || p_paymentgroupid::text));
    -- 363: manual credit is reversed from Customer Credits.
    IF EXISTS (SELECT 1 FROM poultrypayments pp
               WHERE pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid AND pp.saleid IS NULL)
       AND COALESCE(current_setting('poultry.manualcredit_reverse', true), '') <> 'on' THEN
        RAISE EXCEPTION 'This is a credit created by hand. Reverse it from Customer Credits.' USING ERRCODE = 'P0001';
    END IF;$n$);

-- --------------------- 6. Opening / CreditNote are not money received --
SELECT pg_temp.m363_patch('sppoultrycashflow_rows', '363: no cash behind an opening credit',
$o$      AND  COALESCE(p.status, 'Posted') IN ('Posted', 'Reversed')$o$,
$n$      AND  COALESCE(p.status, 'Posted') IN ('Posted', 'Reversed')
      -- 363: no cash behind an opening credit or a credit note.
      AND  COALESCE(p.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote')$n$);

SELECT pg_temp.m363_patch('sppoultrycashflow_rows', '363: an opening credit or credit note never came in',
$o$      AND  p.status = 'Reversed'
      AND  p.reversedat IS NOT NULL$o$,
$n$      AND  p.status = 'Reversed'
      AND  p.reversedat IS NOT NULL
      -- 363: an opening credit or credit note never came in, so never goes out.
      AND  COALESCE(p.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote')$n$);

SELECT pg_temp.m363_patch('sppoultrycashflow_rows', '363: deposit, received',
$o$                    ELSE COUNT(DISTINCT p.saleid)::text || ' sales' END,
               NULLIF(btrim(MIN(s.customername)::text), ''),$o$,
$n$                    WHEN COUNT(p.saleid) = 0 THEN 'Customer deposit'   -- 363: deposit, received
                    ELSE COUNT(DISTINCT p.saleid)::text || ' sales' END,
               NULLIF(btrim(COALESCE(MIN(s.customername)::text,
                   (SELECT c.name::text FROM customer c
                    WHERE c.customerid = MIN(p.customerid) AND c.farmid = p_farmid))), ''),$n$);

SELECT pg_temp.m363_patch('sppoultrycashflow_rows', '363: deposit, reversed',
$o$                    ELSE COUNT(DISTINCT p.saleid)::text || ' sales' END)::text,$o$,
$n$                    WHEN COUNT(p.saleid) = 0 THEN 'Customer deposit'   -- 363: deposit, reversed
                    ELSE COUNT(DISTINCT p.saleid)::text || ' sales' END)::text,$n$);

SELECT pg_temp.m363_patch('fnpoultrydailyclosing_livetotals', '363: Posted, and money that came in',
$o$        WHERE  pp.farmid = p_farmid AND pp.paymentdate::date = p_closingdate$o$,
$n$        WHERE  pp.farmid = p_farmid AND pp.paymentdate::date = p_closingdate
          -- 363: Posted, and money that came in (not an opening credit / credit note).
          AND  COALESCE(pp.status, 'Posted') = 'Posted'
          AND  COALESCE(pp.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote')$n$);

SELECT pg_temp.m363_patch('sppoultrycustomerbalancesummary', '363: received today',
$o$                       AND COALESCE(pp.status, 'Posted') = 'Posted'
                       AND pp.paymentdate::date = CURRENT_DATE), 0)::numeric(14,2),$o$,
$n$                       AND COALESCE(pp.status, 'Posted') = 'Posted'
                       AND COALESCE(pp.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote') -- 363: received today
                       AND pp.paymentdate::date = CURRENT_DATE), 0)::numeric(14,2),$n$);

SELECT pg_temp.m363_patch('sppoultrycustomerbalances', '363: last money received',
$o$            WHERE pp.farmid = p_farmid AND pp.customerid = c.customerid
              AND COALESCE(pp.status, 'Posted') = 'Posted'),$o$,
$n$            WHERE pp.farmid = p_farmid AND pp.customerid = c.customerid
              AND COALESCE(pp.status, 'Posted') = 'Posted'
              AND COALESCE(pp.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote')), -- 363: last money received$n$);

SELECT pg_temp.m363_patch('sppoultrydailyclosing_workspace_core', '363: payments received that day',
$o$    WHERE pp.farmid = p_farmid AND COALESCE(pp.status, 'Posted') = 'Posted'
      AND pp.paymentdate::date = v_date;$o$,
$n$    WHERE pp.farmid = p_farmid AND COALESCE(pp.status, 'Posted') = 'Posted'
      AND COALESCE(pp.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote') -- 363: payments received that day
      AND pp.paymentdate::date = v_date;$n$);

-- Financial Activity positions: a payment on a sale reduces what the customer
-- owes; a deposit instead creates credit held for them.
SELECT pg_temp.m363_patch('fnpoultryfa_positions', '363: customer paid in advance',
$o$    WHERE  lower(pp.farmid::text) = lower(p_farmid)
      AND  COALESCE(pp.status, 'Posted') = 'Posted'
      AND  pp.amount <> 0
      AND  pp.paymentdate >= p_from::timestamp AND pp.paymentdate < (p_to + 1)::timestamp
$o$,
$n$    WHERE  lower(pp.farmid::text) = lower(p_farmid)
      AND  COALESCE(pp.status, 'Posted') = 'Posted'
      AND  pp.amount <> 0
      AND  pp.saleid IS NOT NULL
      AND  pp.paymentdate >= p_from::timestamp AND pp.paymentdate < (p_to + 1)::timestamp

    UNION ALL
    -- 363: customer paid in advance (Deposit): credit held for them.
    SELECT 'CustomerPayment:' || pp.poultrypaymentid,
           'CustomerCredit',
           COALESCE(NULLIF(btrim(c.name), ''), 'Customer'),
           pp.amount::numeric, 0::numeric,
           'Customer paid in advance'
    FROM   poultrypayments pp
    LEFT   JOIN customer c ON c.customerid = pp.customerid AND c.farmid = pp.farmid
    WHERE  lower(pp.farmid::text) = lower(p_farmid)
      AND  pp.saleid IS NULL AND pp.sourcetype = 'Deposit'
      AND  COALESCE(pp.status, 'Posted') = 'Posted'
      AND  pp.amount <> 0
      AND  pp.paymentdate >= p_from::timestamp AND pp.paymentdate < (p_to + 1)::timestamp
$n$);

-- -------------------------------------------------------------- 7. display --
SELECT pg_temp.m363_patch('sppoultrycustomerpayment_history', 'p3.saleid IS DISTINCT FROM p_saleid',
$o$c3.saleid = p_saleid AND p3.saleid <> p_saleid))$o$,
$n$c3.saleid = p_saleid AND p3.saleid IS DISTINCT FROM p_saleid))$n$);

SELECT pg_temp.m363_patch('sppoultrycustomerpaymentcash_sync', '363: a deposit reads as one',
$o$    v_in_desc := 'Customer payment' || COALESCE(' from ' || NULLIF(btrim(v_name), ''), '');$o$,
$n$    -- 363: a deposit reads as one in the cash book.
    v_in_desc := CASE WHEN EXISTS (SELECT 1 FROM poultrypayments pp
                                   WHERE pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid
                                     AND pp.sourcetype = 'Deposit')
                      THEN 'Customer deposit' ELSE 'Customer payment' END
                 || COALESCE(' from ' || NULLIF(btrim(v_name), ''), '');$n$);

-- Statement: name the kind, no "against sale S<null>", and a sale paid by
-- applied credit is not ALSO credited as "Paid at point of sale".
SELECT pg_temp.m363_patch('sppoultrycustomerstatement', '363: paid from credit',
$o$          AND  NOT EXISTS (SELECT 1 FROM poultrypayments pp
                           WHERE pp.saleid = s.saleid AND pp.farmid = s.farmid
                             AND COALESCE(pp.status, 'Posted') = 'Posted')
$o$,
$n$          AND  NOT EXISTS (SELECT 1 FROM poultrypayments pp
                           WHERE pp.saleid = s.saleid AND pp.farmid = s.farmid
                             AND COALESCE(pp.status, 'Posted') = 'Posted')
          -- 363: paid from credit -- the credit's own line already counts it.
          AND  NOT EXISTS (SELECT 1 FROM customerpaymentallocation ca
                           WHERE ca.module = 'poultry' AND ca.saleid = s.saleid
                             AND ca.farmid = s.farmid AND ca.status = 'Posted')
$n$);

SELECT pg_temp.m363_patch('sppoultrycustomerstatement', '363: kind of credit',
$o$               ('Payment received'
                || COALESCE(' (' || NULLIF(btrim(MIN(pp.paymentmethod)), '') || ')', '')
                || CASE WHEN COUNT(DISTINCT pp.saleid) > 1$o$,
$n$               (CASE MIN(pp.sourcetype)   -- 363: kind of credit
                     WHEN 'OpeningCredit' THEN 'Opening credit'
                     WHEN 'CreditNote'    THEN 'Credit note'
                     WHEN 'Deposit'       THEN 'Deposit received'
                     ELSE 'Payment received' END
                || COALESCE(' (' || NULLIF(btrim(MIN(pp.paymentmethod)), '') || ')', '')
                || CASE WHEN COUNT(pp.saleid) = 0 THEN ''
                        WHEN COUNT(DISTINCT pp.saleid) > 1$n$);

-- ---------------------------------------------------------------- 8. guard --
SELECT pg_temp.m363_patch('spsale_delete', '363: credit applied',
$o$       AND EXISTS (SELECT 1 FROM poultrypayments pp WHERE pp.saleid = p_saleid AND pp.farmid = p_farmid
                                                      AND COALESCE(pp.status, 'Posted') = 'Posted') THEN$o$,
$n$       AND (EXISTS (SELECT 1 FROM poultrypayments pp WHERE pp.saleid = p_saleid AND pp.farmid = p_farmid
                                                       AND COALESCE(pp.status, 'Posted') = 'Posted')
            -- 363: credit applied to it counts as a payment too.
            OR EXISTS (SELECT 1 FROM customerpaymentallocation ca WHERE ca.module = 'poultry'
                          AND ca.saleid = p_saleid AND ca.farmid = p_farmid AND ca.status = 'Posted')) THEN$n$);

-- ------------------------------------------------- 9. Profit & Loss --
-- A credit note is a cost: a NEGATIVE revenue line, on the credit note's date.
SELECT pg_temp.m363_patch('sppoultryreport_pllines', '363: credit notes',
$o$        FROM   fnpoultrypl_revenuelines(p_farmid, p_startdate, p_enddate) r
        GROUP  BY r.revenueline
    ),$o$,
$n$        FROM   fnpoultrypl_revenuelines(p_farmid, p_startdate, p_enddate) r
        GROUP  BY r.revenueline
        UNION ALL
        -- 363: credit notes given to customers reduce revenue.
        SELECT 'CreditNotes', -SUM(pp.amount), COUNT(*)::integer
        FROM   poultrypayments pp
        WHERE  pp.farmid = p_farmid AND pp.sourcetype = 'CreditNote'
          AND  COALESCE(pp.status, 'Posted') = 'Posted'
          AND  pp.paymentdate >= p_startdate AND pp.paymentdate < (p_enddate + 1)
        HAVING COUNT(*) > 0
    ),$n$);

SELECT pg_temp.m363_patch('sppoultryreport_pllines', '363: label',
$o$    SELECT 'Revenue', rev.k, fnpoultrysale_revenuelabel(rev.k), rev.amt::numeric(14,2),
           CASE rev.k WHEN 'EggSales' THEN 1 WHEN 'BirdSales' THEN 2
                      WHEN 'ManureSales' THEN 3 WHEN 'FeedSales' THEN 4 ELSE 5 END,$o$,
$n$    SELECT 'Revenue', rev.k,
           CASE rev.k WHEN 'CreditNotes' THEN 'Credit Notes & Allowances'   -- 363: label
                      ELSE fnpoultrysale_revenuelabel(rev.k) END,
           rev.amt::numeric(14,2),
           CASE rev.k WHEN 'EggSales' THEN 1 WHEN 'BirdSales' THEN 2
                      WHEN 'ManureSales' THEN 3 WHEN 'FeedSales' THEN 4
                      WHEN 'CreditNotes' THEN 6 ELSE 5 END,$n$);

-- The line's drilldown: one row per credit note.
SELECT pg_temp.m363_patch('sppoultryreport_plrevenuedetail', '363: credit notes',
$o$    WHERE  (p_linekey IS NULL OR r.revenueline = p_linekey)
    ORDER  BY r.saledate DESC, r.saleid DESC;$o$,
$n$    WHERE  (p_linekey IS NULL OR r.revenueline = p_linekey)
    UNION ALL
    -- 363: credit notes, negative.
    SELECT NULL::integer, pp.paymentdate,
           ('Credit note ' || COALESCE(pp.paymentnumber, ''))::text,
           c.name::text, NULL::numeric, NULL::numeric,
           -pp.amount, 0::numeric, NULL::text,
           'CreditNotes'::text, 'Credit Notes & Allowances'::text
    FROM   poultrypayments pp
    LEFT   JOIN customer c ON c.customerid = pp.customerid AND c.farmid = pp.farmid
    WHERE  pp.farmid = p_farmid AND pp.sourcetype = 'CreditNote'
      AND  COALESCE(pp.status, 'Posted') = 'Posted'
      AND  pp.paymentdate >= p_startdate AND pp.paymentdate < (p_enddate + 1)
      AND  (p_linekey IS NULL OR p_linekey = 'CreditNotes')
    ORDER  BY 2 DESC, 1 DESC NULLS LAST;$n$);

-- ------------------------------------------------- 10. create / reverse / list --
CREATE OR REPLACE FUNCTION public.sppoultrycustomercredit_create(
    p_farmid        text,
    p_customerid    integer,
    p_kind          text,
    p_amount        numeric,
    p_date          timestamp DEFAULT NULL,
    p_cashaccountid integer   DEFAULT NULL,
    p_paymentmethod text      DEFAULT NULL,
    p_reference     text      DEFAULT NULL,
    p_reason        text      DEFAULT NULL,
    p_by            text      DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
AS $f$
DECLARE
    v_group  uuid := gen_random_uuid();
    v_id     integer;
    v_number text;
BEGIN
    IF p_kind NOT IN ('OpeningCredit', 'Deposit', 'CreditNote') THEN
        RAISE EXCEPTION 'Choose what the credit is: an opening balance, a deposit or a credit note.' USING ERRCODE = 'P0001';
    END IF;
    IF p_amount IS NULL OR round(p_amount, 2) <= 0 THEN
        RAISE EXCEPTION 'Enter an amount greater than 0.' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for the credit.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM customer c WHERE c.customerid = p_customerid AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Customer does not belong to this company.' USING ERRCODE = 'P0001';
    END IF;
    IF p_kind = 'Deposit' THEN
        IF p_cashaccountid IS NULL OR NOT EXISTS (SELECT 1 FROM poultrycashaccounts a
                                                  WHERE a.poultrycashaccountid = p_cashaccountid AND a.farmid = p_farmid) THEN
            RAISE EXCEPTION 'Choose the cash account the deposit was received into.' USING ERRCODE = 'P0001';
        END IF;
    ELSIF p_cashaccountid IS NOT NULL THEN
        RAISE EXCEPTION 'Only a deposit moves cash; an opening credit or credit note has no cash account.' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO poultrypayments
        (farmid, saleid, amount, paymentmethod, paymentdate, reference, note, createdby,
         status, sourcetype, customerid, poultrycashaccountid, paymentgroupid)
    VALUES
        (p_farmid, NULL, round(p_amount, 2),
         CASE WHEN p_kind = 'Deposit' THEN NULLIF(btrim(COALESCE(p_paymentmethod, '')), '') END,
         COALESCE(p_date, (now() AT TIME ZONE 'utc')),
         NULLIF(btrim(COALESCE(p_reference, '')), ''), left(btrim(p_reason), 300), p_by,
         'Posted', p_kind, p_customerid, CASE WHEN p_kind = 'Deposit' THEN p_cashaccountid END, v_group)
    RETURNING poultrypaymentid, paymentnumber INTO v_id, v_number;

    -- Only a deposit has cash: one CashIn on its account.
    IF p_kind = 'Deposit' THEN
        PERFORM sppoultrycustomerpaymentcash_sync(p_farmid, v_group, p_by);
    END IF;

    RETURN jsonb_build_object('paymentGroupId', v_group, 'poultryPaymentId', v_id, 'paymentNumber', v_number);
END
$f$;

-- Undo a manual credit. Whatever of it was already used on sales is released
-- (those sales are owed again); a deposit's cash goes back out. Refunded
-- credit cannot be undone this way (the refund moved real money).
CREATE OR REPLACE FUNCTION public.sppoultrycustomercredit_reverse(
    p_farmid text, p_paymentgroupid uuid, p_reason text, p_by text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $f$
DECLARE
    v_n integer;
BEGIN
    IF NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for reversing the credit.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM poultrypayments pp
                   WHERE pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid
                     AND pp.saleid IS NULL AND pp.sourcetype IN ('OpeningCredit', 'Deposit', 'CreditNote')) THEN
        RAISE EXCEPTION 'That is not a manually created credit for this company.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM set_config('poultry.manualcredit_reverse', 'on', true);
    v_n := sppoultrycustomerpayment_reverse(p_farmid, p_paymentgroupid, btrim(p_reason), p_by);
    PERFORM set_config('poultry.manualcredit_reverse', '', true);
    RETURN v_n;
END
$f$;

CREATE OR REPLACE FUNCTION public.sppoultrycustomercredit_manuallist(p_farmid text)
RETURNS TABLE(paymentgroupid uuid, poultrypaymentid integer, paymentnumber text, kind text,
              creditdate timestamp, customerid integer, customername text, amount numeric,
              used numeric, refunded numeric, remaining numeric, status text,
              poultrycashaccountid integer, cashaccountname text, paymentmethod text,
              reference text, reason text, createdby text, createdat timestamp,
              reversedat timestamp, reversalreason text)
LANGUAGE sql
STABLE
AS $f$
    SELECT pp.paymentgroupid, pp.poultrypaymentid, pp.paymentnumber::text, pp.sourcetype::text,
           pp.paymentdate, pp.customerid, c.name::text, pp.amount::numeric(14,2),
           COALESCE((SELECT SUM(ca.amountapplied) FROM customerpaymentallocation ca
                     WHERE ca.module = 'poultry' AND ca.paymentid = pp.poultrypaymentid
                       AND ca.farmid = pp.farmid AND ca.status = 'Posted'), 0)::numeric(14,2),
           COALESCE((SELECT SUM(rl.amount) FROM poultrycustomerrefundlines rl
                     JOIN poultrycustomerrefunds r ON r.refundid = rl.refundid
                     WHERE rl.poultrypaymentid = pp.poultrypaymentid AND rl.farmid = pp.farmid
                       AND r.status = 'Posted'), 0)::numeric(14,2),
           fnpoultrypayment_unapplied(p_farmid, pp.poultrypaymentid),
           COALESCE(pp.status, 'Posted')::text,
           pp.poultrycashaccountid, a.accountname::text, pp.paymentmethod::text,
           pp.reference::text, pp.note::text, pp.createdby::text, pp.createddate,
           pp.reversedat, pp.reversalreason::text
    FROM   poultrypayments pp
    LEFT   JOIN customer c ON c.customerid = pp.customerid AND c.farmid = pp.farmid
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = pp.poultrycashaccountid AND a.farmid = pp.farmid
    WHERE  pp.farmid = p_farmid AND pp.saleid IS NULL
      AND  pp.sourcetype IN ('OpeningCredit', 'Deposit', 'CreditNote')
    ORDER  BY pp.paymentdate DESC, pp.poultrypaymentid DESC;
$f$;

COMMIT;

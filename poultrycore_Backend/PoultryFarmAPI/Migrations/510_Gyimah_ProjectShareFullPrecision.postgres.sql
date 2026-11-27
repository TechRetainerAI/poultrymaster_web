-- 510: a project split by AMOUNT gives the project exactly the amount typed.
--
-- Until now the share was rounded to 6 decimals (numeric(9,6)), and every
-- project figure is share x the transaction's amount. So typing 664,815 of a
-- 677,440 loan saved 0.981364 and gave the project 664,815.23, and the split
-- reopened showing 664815.22816. The bigger the amount, the bigger the error.
--
-- Now the share keeps 15 decimals: the error is below a billionth of a cedi on
-- any realistic amount. Splits already saved by amount or quantity are
-- recalculated from what was typed, but only when the transaction is still the
-- size it was when the split was saved (otherwise the share, which follows the
-- transaction, is left alone). Nothing else changes: no amounts, no postings.
--
-- The five functions are the live definitions with only the rounding changed.

BEGIN;

ALTER TABLE genericprojectallocations ALTER COLUMN share TYPE numeric(18,15);

-- spgenericproject_allocate: only the rounding changed (6 -> 15 decimals).
CREATE OR REPLACE FUNCTION public.spgenericproject_allocate(p_farmid text, p_sourcetype text, p_sourceid integer, p_lineid integer, p_splits jsonb, p_reason text, p_by text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_size     record;
    v_new      jsonb := '[]'::jsonb;
    v_old      jsonb;
    v_total    numeric := 0;
    v_share    numeric;
    v_basis    text;
    v_entered  numeric;
    v_class    text;
    v_pid      integer;
    v_status   text;
    v_group    uuid := gen_random_uuid();
    s          jsonb;
    v_now      timestamp := (now() at time zone 'utc');
BEGIN
    IF p_splits IS NULL OR jsonb_typeof(p_splits) <> 'array' THEN
        RAISE EXCEPTION 'Project split must be a list.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('genericproject_alloc:' || p_farmid || ':' || p_sourcetype
                                           || ':' || p_sourceid || ':' || COALESCE(p_lineid, 0)));

    IF p_sourcetype IN ('SaleLine', 'PurchaseLine') AND p_lineid IS NULL THEN
        RAISE EXCEPTION 'Choose the line to assign.' USING ERRCODE = 'P0001';
    END IF;
    IF p_sourcetype NOT IN ('SaleLine', 'PurchaseLine') THEN p_lineid := NULL; END IF;

    SELECT * INTO v_size FROM fngenericproject_sourcesize(p_farmid, p_sourcetype, p_sourceid, p_lineid);
    IF v_size.label IS NULL THEN
        RAISE EXCEPTION 'That transaction was not found in this company.' USING ERRCODE = 'P0001';
    END IF;

    FOR s IN SELECT * FROM jsonb_array_elements(p_splits) LOOP
        v_pid := NULLIF(s->>'projectId', '')::int;
        IF v_pid IS NULL THEN CONTINUE; END IF;          -- "General" rows are implicit
        SELECT status INTO v_status FROM genericprojects WHERE genericprojectid = v_pid AND farmid = p_farmid;
        IF v_status IS NULL THEN
            RAISE EXCEPTION 'That project or contract was not found in this company.' USING ERRCODE = 'P0001';
        END IF;
        IF v_status = 'Archived' THEN
            RAISE EXCEPTION 'An archived project cannot receive transactions. Restore it first.' USING ERRCODE = 'P0001';
        END IF;

        IF NULLIF(s->>'share', '') IS NOT NULL THEN
            v_share := (s->>'share')::numeric; v_basis := 'Share'; v_entered := v_share;
        ELSIF NULLIF(s->>'quantity', '') IS NOT NULL THEN
            v_entered := (s->>'quantity')::numeric; v_basis := 'Quantity';
            IF COALESCE(v_size.quantity, 0) <= 0 THEN
                RAISE EXCEPTION 'This transaction has no quantity to split. Split it by amount instead.' USING ERRCODE = 'P0001';
            END IF;
            v_share := v_entered / v_size.quantity;
        ELSIF NULLIF(s->>'amount', '') IS NOT NULL THEN
            v_entered := (s->>'amount')::numeric; v_basis := 'Amount';
            IF COALESCE(v_size.amount, 0) = 0 THEN
                RAISE EXCEPTION 'This transaction has no amount to split.' USING ERRCODE = 'P0001';
            END IF;
            v_share := v_entered / abs(v_size.amount);
        ELSE
            v_share := 1; v_basis := 'Share'; v_entered := 1;
        END IF;
        v_share := round(v_share, 15);
        IF v_share <= 0 THEN
            RAISE EXCEPTION 'Each project''s part must be more than zero.' USING ERRCODE = 'P0001';
        END IF;
        v_class := COALESCE(NULLIF(s->>'costClass', ''), 'Direct');
        IF v_class NOT IN ('Direct', 'Shared', 'Overhead', 'Selling', 'Financing', 'Capital') THEN
            RAISE EXCEPTION 'Cost class "%" is not one of Direct, Shared, Overhead, Selling, Financing or Capital.', v_class
                USING ERRCODE = 'P0001';
        END IF;
        IF v_new @> jsonb_build_array(jsonb_build_object('projectId', v_pid)) THEN
            RAISE EXCEPTION 'The same project appears twice in this split.' USING ERRCODE = 'P0001';
        END IF;
        v_total := v_total + v_share;
        v_new := v_new || jsonb_build_array(jsonb_build_object(
                     'projectId', v_pid, 'share', v_share, 'basis', v_basis, 'entered', v_entered, 'costClass', v_class));
    END LOOP;

    IF v_total > 1.000001 THEN
        RAISE EXCEPTION 'The projects'' parts add up to more than the whole transaction (% %%). Reduce them so nothing is counted twice.',
            round(v_total * 100, 2) USING ERRCODE = 'P0001';
    END IF;

    -- Same as what is there already? Then this is a retry: do nothing.
    SELECT COALESCE(jsonb_agg(jsonb_build_object('projectId', a.genericprojectid, 'share', a.share, 'costClass', a.costclass)
                              ORDER BY a.genericprojectid), '[]'::jsonb)
      INTO v_old
      FROM genericprojectallocations a
     WHERE a.farmid = p_farmid AND a.sourcetype = p_sourcetype AND a.sourceid = p_sourceid
       AND COALESCE(a.sourcelineid, 0) = COALESCE(p_lineid, 0) AND a.status = 'Active';
    IF v_old = (SELECT COALESCE(jsonb_agg(jsonb_build_object('projectId', (x->>'projectId')::int,
                                                            'share', (x->>'share')::numeric(18,15),
                                                            'costClass', x->>'costClass')
                                          ORDER BY (x->>'projectId')::int), '[]'::jsonb)
                FROM jsonb_array_elements(v_new) x) THEN
        RETURN jsonb_array_length(v_new);
    END IF;

    -- Any real change needs the module on: switched off means "no new project
    -- assignment" until it is switched back on.
    PERFORM fngenericproject_assertenabled(p_farmid);

    UPDATE genericprojectallocations a
       SET status = 'Superseded', supersededby = p_by, supersededat = v_now,
           supersededreason = NULLIF(btrim(p_reason), '')
     WHERE a.farmid = p_farmid AND a.sourcetype = p_sourcetype AND a.sourceid = p_sourceid
       AND COALESCE(a.sourcelineid, 0) = COALESCE(p_lineid, 0) AND a.status = 'Active';

    INSERT INTO genericprojectallocations (farmid, genericprojectid, sourcetype, sourceid, sourcelineid, share,
                                           basis, enteredvalue, costclass, reason, changegroup, createdby, createdat)
    SELECT p_farmid, (x->>'projectId')::int, p_sourcetype, p_sourceid, p_lineid, (x->>'share')::numeric,
           x->>'basis', (x->>'entered')::numeric, x->>'costClass', NULLIF(btrim(p_reason), ''), v_group, p_by, v_now
    FROM jsonb_array_elements(v_new) x;

    RETURN jsonb_array_length(v_new);
END
$function$;

-- spgenericproject_activityshares: only the rounding changed (6 -> 15 decimals).
CREATE OR REPLACE FUNCTION public.spgenericproject_activityshares(p_farmid text, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH ev AS (
        SELECT e.eventkey,
               CASE
                 WHEN e.sourcetype IN ('SaleRevenue', 'SaleResidual', 'SaleRefund') THEN 'Sale'
                 WHEN e.sourcetype IN ('Receipt', 'ReceiptReversal') THEN 'CustomerPaymentCash'
                 WHEN e.sourcetype = 'Expense' THEN 'Expense'
                 WHEN e.sourcetype = 'PurchasePayment' THEN 'Purchase'
                 WHEN e.sourcetype = 'SupplierPayment' THEN 'SupplierPaymentCash'
                 WHEN e.sourcetype = 'Payroll' THEN 'PayrollRun'
                 WHEN e.sourcetype IN ('OwnerContribution', 'OwnerDraw') THEN 'OwnerEntry'
                 WHEN e.sourcetype IN ('LoanReceived', 'LoanRepayment') THEN 'Loan'
               END AS keytype,
               CASE
                 WHEN e.sourcetype = 'SaleRefund' THEN
                      (SELECT t.sourceid FROM genericcashtransactions t
                       WHERE t.genericcashtransactionid = e.sourceid AND t.farmid = p_farmid)
                 WHEN e.sourcetype = 'LoanRepayment' THEN
                      (SELECT lp."GenericLoanId" FROM "GenericLoanPayments" lp
                       WHERE lp."GenericLoanPaymentId" = e.sourceid AND lp."FarmId" = p_farmid)
                 ELSE e.sourceid
               END AS keyid
        FROM fngenericfa_events(p_farmid, p_from, p_to) e
    ), ks AS (
        SELECT keytype, keyid, projectid, sum(share) AS share
        FROM fngenericproject_keyshares(p_farmid)
        WHERE productid IS NULL AND share > 0
        GROUP BY 1, 2, 3
    ), x AS (
        SELECT ev.eventkey,
               jsonb_agg(jsonb_build_object('projectId', ks.projectid, 'share', round(ks.share, 15))
                         ORDER BY ks.projectid) AS projects
        FROM ev JOIN ks ON ks.keytype = ev.keytype AND ks.keyid = ev.keyid
        GROUP BY ev.eventkey
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object('eventKey', x.eventkey, 'projects', x.projects)), '[]'::jsonb)
    FROM x;
$function$;

-- spgenericproject_openbalances: only the rounding changed (6 -> 15 decimals).
CREATE OR REPLACE FUNCTION public.spgenericproject_openbalances(p_farmid text, p_side text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH docs AS (
        SELECT d.genericcustomerid AS partyid, d.documenttype, d.documentid, d.documentdate AS docdate,
               d.amountpaid, d.balance, d.duedate
        FROM fngenericopeninvoices(p_farmid) d
        WHERE p_side = 'customer' AND d.balance > 0
        UNION ALL
        SELECT d.supplierid, d.documenttype, d.documentid, d.docdate, d.amountpaid, d.balance,
               COALESCE(d.duedate, d.docdate + COALESCE(s.paymenttermsdays, 0))
        FROM fngenericpayables(p_farmid) d
        JOIN genericsuppliers s ON s.genericsupplierid = d.supplierid AND s.farmid = p_farmid
        WHERE p_side = 'supplier' AND d.balance > 0
    ), ks AS (
        SELECT keytype, keyid, projectid, sum(share) AS share
        FROM fngenericproject_keyshares(p_farmid)
        WHERE productid IS NULL AND share > 0 AND keytype IN ('Sale', 'Purchase', 'Expense')
        GROUP BY 1, 2, 3
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'partyId', d.partyid, 'documentType', d.documenttype, 'documentId', d.documentid,
               'documentDate', d.docdate, 'amountPaid', d.amountpaid, 'balance', d.balance,
               'dueDate', d.duedate, 'isOverdue', COALESCE(d.duedate < CURRENT_DATE, false),
               'projects', COALESCE((
                   SELECT jsonb_agg(jsonb_build_object('projectId', ks.projectid, 'share', round(ks.share, 15))
                                    ORDER BY ks.projectid)
                   FROM ks WHERE ks.keytype = CASE d.documenttype WHEN 'Invoice' THEN 'Sale' ELSE d.documenttype END
                     AND ks.keyid = d.documentid), '[]'::jsonb))
             ORDER BY d.partyid, d.docdate, d.documentid), '[]'::jsonb)
    FROM docs d;
$function$;

-- spgenericproject_cashshares: only the rounding changed (6 -> 15 decimals).
CREATE OR REPLACE FUNCTION public.spgenericproject_cashshares(p_farmid text, p_accountid integer, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('cashTransactionId', x.id, 'projects', x.projects)), '[]'::jsonb)
    FROM (
        SELECT c.cashtransactionid AS id,
               jsonb_agg(jsonb_build_object('projectId', c.projectid, 'share', round(c.share, 15),
                                            'label', p.projectnumber || ' — ' || p.name)
                         ORDER BY c.projectid) AS projects
        FROM fngenericproject_cash(p_farmid, COALESCE(p_from, DATE '2000-01-01'), COALESCE(p_to, DATE '2100-01-01')) c
        JOIN genericcashtransactions t ON t.genericcashtransactionid = c.cashtransactionid AND t.farmid = p_farmid
        JOIN genericprojects p ON p.genericprojectid = c.projectid
        WHERE c.projectid IS NOT NULL AND c.share > 0
          AND (p_accountid IS NULL OR t.genericcashaccountid = p_accountid)
        GROUP BY c.cashtransactionid
    ) x;
$function$;

-- spgenericproject_labels: only the rounding changed (6 -> 15 decimals).
CREATE OR REPLACE FUNCTION public.spgenericproject_labels(p_farmid text, p_sourcetype text, p_ids integer[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH a AS (
        -- Stored tags (unchanged from 483) for every type except payments.
        SELECT a.sourceid, a.genericprojectid,
               CASE WHEN a.sourcetype IN ('SaleLine', 'PurchaseLine') THEN NULL ELSE a.share END AS share
        FROM genericprojectallocations a
        WHERE p_sourcetype NOT IN ('CustomerPayment', 'SupplierPayment', 'DeferredLot')
          AND a.farmid = p_farmid AND a.status = 'Active'
          AND a.sourcetype = CASE p_sourcetype WHEN 'Sale' THEN 'SaleLine' WHEN 'Purchase' THEN 'PurchaseLine' ELSE p_sourcetype END
          AND (p_ids IS NULL OR a.sourceid = ANY (p_ids))
        UNION ALL
        -- Payments: what they paid follows the documents, the rest the advance.
        SELECT k.keyid, k.projectid, k.share
        FROM fngenericproject_keyshares(p_farmid) k
        WHERE p_sourcetype IN ('CustomerPayment', 'SupplierPayment')
          AND k.keytype = p_sourcetype || 'Cash'
          AND k.share > 0
          AND (p_ids IS NULL OR k.keyid = ANY (p_ids))
        UNION ALL
        -- 501: a deferred-cost lot is a stock-in movement; a purchase lot belongs
        -- to the projects of its purchase's lines for that product. Other lots
        -- (opening stock, adjustments, production) are General.
        SELECT m.genericstockmovementid, a.genericprojectid, NULL::numeric
        FROM genericstockmovements m
        JOIN genericpurchaseitems i ON i.genericpurchaseid = m.referenceid AND i.genericproductid = m.genericproductid
        JOIN genericprojectallocations a ON a.farmid = p_farmid AND a.status = 'Active' AND a.sourcetype = 'PurchaseLine'
             AND a.sourceid = i.genericpurchaseid AND a.sourcelineid = i.genericpurchaseitemid
        WHERE p_sourcetype = 'DeferredLot' AND m.farmid = p_farmid AND m.referencetype = 'Purchase'
          AND (p_ids IS NULL OR m.genericstockmovementid = ANY (p_ids))
    ), per AS (
        -- One entry per (record, project). A share is only given when every row
        -- behind it has one.
        SELECT a.sourceid, a.genericprojectid,
               CASE WHEN bool_or(a.share IS NULL) THEN NULL ELSE round(sum(a.share), 15) END AS share
        FROM a GROUP BY a.sourceid, a.genericprojectid
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object('sourceId', x.sourceid, 'projects', x.projects)), '[]'::jsonb)
    FROM (SELECT per.sourceid,
                 jsonb_agg(jsonb_build_object('projectId', per.genericprojectid,
                                              'label', p.projectnumber || ' — ' || p.name,
                                              'share', per.share)
                           ORDER BY p.projectnumber) AS projects
          FROM per JOIN genericprojects p ON p.genericprojectid = per.genericprojectid
          GROUP BY per.sourceid) x;
$function$;

-- Recalculate saved Amount / Quantity splits from what was typed, where the
-- transaction has not changed size since (the old 6-decimal share still matches).
WITH fix AS (
    SELECT a.genericprojectallocationid AS id,
           CASE a.basis WHEN 'Amount' THEN a.enteredvalue / abs(z.amount)
                        ELSE a.enteredvalue / z.quantity END AS exact
      FROM genericprojectallocations a
      CROSS JOIN LATERAL fngenericproject_sourcesize(a.farmid, a.sourcetype, a.sourceid, a.sourcelineid) z
     WHERE a.status = 'Active' AND a.basis IN ('Amount', 'Quantity') AND a.enteredvalue IS NOT NULL
       AND ((a.basis = 'Amount' AND COALESCE(z.amount, 0) <> 0) OR (a.basis = 'Quantity' AND COALESCE(z.quantity, 0) > 0))
)
UPDATE genericprojectallocations a
   SET share = round(f.exact, 15)
  FROM fix f
 WHERE a.genericprojectallocationid = f.id
   AND round(f.exact, 6) = round(a.share, 6)
   AND f.exact > 0 AND f.exact <= 1
   AND a.share <> round(f.exact, 15);

-- Self-test: the example from the report gives the project exactly 664,815.
DO $t$
DECLARE v numeric;
BEGIN
    v := round(664815::numeric / 677440, 15);
    IF round(v * 677440, 2) <> 664815.00 THEN
        RAISE EXCEPTION '510 self-test: 664,815 of 677,440 came back as %', round(v * 677440, 2);
    END IF;
    IF (SELECT numeric_scale FROM information_schema.columns
         WHERE table_name = 'genericprojectallocations' AND column_name = 'share') <> 15 THEN
        RAISE EXCEPTION '510 self-test: share column was not widened';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname LIKE 'spgenericproject%' AND (prosrc LIKE '%numeric(9,6)%'
               OR prosrc ~ 'round\((v_share|ks\.share|c\.share|sum\(a\.share\)), 6\)')) THEN
        RAISE EXCEPTION '510 self-test: a project function still rounds shares to 6 decimals';
    END IF;
    RAISE NOTICE '510 self-test passed';
END
$t$;

COMMIT;

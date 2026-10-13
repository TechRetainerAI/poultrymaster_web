-- =============================================================================
-- 361_PoultrySaleLinesRestore.postgres.sql                   (requires 358)
--
-- WHY
-- ---
-- On the dev database, migrations 349, 351 and 352 (and perhaps 353/354) were
-- run AGAIN after 358. That put ten functions back to their pre-358 bodies
-- (found 2026-10-13 with a read-only check):
--
--   sppoultryeggstock_syncforsale   <- the visible bug: a multi-size egg sale
--                                      took its WHOLE quantity off Unsorted
--                                      instead of one movement per size, so
--                                      JUMBO and Large never went down
--   sppoultrysale_reverse, fnpoultrysale_reversalstate  (restore per line)
--   spsale_getall / _getbyid / _getbyflock              (sales lose their lines)
--   sppoultrycashflow_rows          (one Cash Flow row per sale, not per payment)
--   sppoultrycustomeropensales      ("Fresh Eggs · 2 lines" label)
--   sppoultryreport_eggsales_rs1    (egg sales report by line)
--   sppoultrysale_ensuregroup       (349's "add a size to a posted sale")
--
-- 358 itself cannot simply be run again (its merge and patch steps are one-way),
-- so this file re-applies only its FUNCTION bodies, copied verbatim from 358
-- (generated from it, so the two cannot disagree).
--
-- WHAT IT DOES
-- ------------
--   0. Re-applies 354 (reversal reason optional) and 353 (cash sync in place)
--      first, ONLY if the live body lost them -- 358's reversal patch sits on
--      top of 354, and a re-run 351 also overwrites 353's function.
--   1. Re-applies 358's bodies. A patched body that still has the 358 change
--      is left as it is.
--   2. Repairs stock: every POSTED multi-line egg sale whose 'Sale' movement is
--      not per line is re-posted through the restored function -- one movement
--      per line, on the line's own egg class -- keeping the original movement's
--      date and creator. One-line sales only get their line link back.
--      Nothing else is written: no sale, payment, allocation or cash row.
--   3. Proves it: per company, total egg stock is unchanged (only the CLASS
--      moved), money/cash/receivables are unchanged, every repaired sale now
--      has one movement per line summing to its quantity, and every function
--      carries its marker. Any mismatch RAISES and nothing is saved.
--
-- RUN (from this Migrations folder; DRY RUN by default -- prints, then ROLLBACK)
--   psql ... -X -f 361_PoultrySaleLinesRestore.postgres.sql
--   psql ... -X -v apply=true -f 361_PoultrySaleLinesRestore.postgres.sql
--
-- Never re-run 341-354 after 358: each one puts its old bodies back.
-- =============================================================================

\set ON_ERROR_STOP on
\pset pager off
\if :{?apply}
\else
  \set apply false
\endif

BEGIN;
SELECT set_config('poultry.actor', 'migration-361', true);

-- -----------------------------------------------------------------------------
-- What is wrong before (shown on every run)
-- -----------------------------------------------------------------------------
CREATE FUNCTION pg_temp.m361_has(p_fn text, p_marker text) RETURNS boolean LANGUAGE sql AS $f$
    SELECT COALESCE(bool_or(position(p_marker IN pg_get_functiondef(p.oid)) > 0), false)
    FROM   pg_proc p WHERE p.proname = p_fn AND p.pronamespace = 'public'::regnamespace;
$f$;

CREATE TEMP TABLE m361_markers (fn text, marker text) ON COMMIT DROP;
INSERT INTO m361_markers VALUES
    ('sppoultryeggstock_syncforsale', 'ismultiline'),
    ('sppoultrysale_creategroup',     'ismultiline'),
    ('sppoultrysale_reverse',         't.salelineid'),
    ('sppoultrysale_reverse',         '354:'),
    ('sppoultrycustomerpaymentcash_sync', 'v_in_id'),
    ('fnpoultrysale_reversalstate',   'saleLineId'),
    ('fnpoultrysale_document',        'ARRAY[s.saleid]'),
    ('sppoultrysale_ensuregroup',     'cannot gain lines'),
    ('sppoultrycashflow_rows',        'ONE row per payment (358)'),
    ('sppoultrycustomeropensales',    'fnpoultrysale_productlabel'),
    ('sppoultrycustomerpayment_allocations', 'fnpoultrysale_productlabel'),
    ('spsale_getall',                 'fnpoultrysale_lines'),
    ('spsale_getbyid',                'fnpoultrysale_lines'),
    ('spsale_getbyflock',             'fnpoultrysale_lines'),
    ('sppoultryreport_eggsales_rs1',  'saleline');

\echo '== Before: functions missing their current change'
SELECT fn, marker FROM m361_markers WHERE NOT pg_temp.m361_has(fn, marker) ORDER BY 1, 2;

-- Sales to repair, captured before anything changes.
CREATE TEMP TABLE m361_fix ON COMMIT DROP AS
SELECT s.farmid::text AS farmid, s.saleid, s.salegroupno, s.quantity,
       MIN(t.createddate) AS createddate, MIN(t.createdby)::text AS createdby,
       string_agg(t.poultryproductid || ':' || t.quantity, ', ') AS old_rows
FROM   sale s
JOIN   poultrystocktransactions t ON t.relatedid = s.saleid AND t.farmid = s.farmid AND t.txntype = 'Sale'
WHERE  s.ismultiline AND s.status = 'Posted' AND s.product ILIKE '%egg%'
GROUP  BY s.farmid, s.saleid, s.salegroupno, s.quantity
HAVING bool_or(t.salelineid IS NULL);

\echo '== Sales whose egg stock will be re-posted per line'
SELECT farmid, saleid, salegroupno, quantity, old_rows FROM m361_fix ORDER BY farmid, saleid;

-- Money, cash, receivables and total stock per company: must not move.
CREATE TEMP TABLE m361_measure (phase text, farmid text, metric text, value numeric) ON COMMIT DROP;
CREATE FUNCTION pg_temp.m361_measure(p_phase text) RETURNS void LANGUAGE sql AS $f$
    INSERT INTO m361_measure
    SELECT p_phase, s.farmid, 'sales', SUM(s.totalamount) FROM sale s GROUP BY s.farmid
    UNION ALL
    SELECT p_phase, s.farmid, 'receivable', SUM(fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid))
    FROM sale s WHERE s.status = 'Posted' GROUP BY s.farmid
    UNION ALL
    SELECT p_phase, pp.farmid, 'payments', SUM(pp.amount) FROM poultrypayments pp GROUP BY pp.farmid
    UNION ALL
    SELECT p_phase, ct.farmid, 'cash', SUM(ct.amount) FROM poultrycashtransactions ct GROUP BY ct.farmid
    UNION ALL
    SELECT p_phase, a.farmid, 'cashbalance', SUM(a.currentbalance) FROM poultrycashaccounts a GROUP BY a.farmid
    UNION ALL
    SELECT p_phase, t.farmid, 'stock.all', SUM(t.quantity) FROM poultrystocktransactions t GROUP BY t.farmid
    UNION ALL
    SELECT p_phase, t.farmid, 'stock.rows.nonsale', COUNT(*) FROM poultrystocktransactions t
    WHERE t.txntype <> 'Sale' GROUP BY t.farmid;
$f$;
SELECT pg_temp.m361_measure('before');

CREATE TEMP TABLE m361_classes_before ON COMMIT DROP AS
SELECT t.farmid, t.poultryproductid, SUM(t.quantity) AS qty
FROM   poultrystocktransactions t
WHERE  t.farmid IN (SELECT farmid FROM m361_fix)
GROUP  BY 1, 2;

-- -----------------------------------------------------------------------------
-- 0. 354 and 353, only where the live body lost them
-- -----------------------------------------------------------------------------
SELECT NOT pg_temp.m361_has('sppoultrysale_reverse', '354:') AS need354,
       NOT pg_temp.m361_has('sppoultrycustomerpaymentcash_sync', 'v_in_id') AS need353 \gset
\if :need354
  \echo '-- re-applying 354 (sale reversal: listed reason is enough)'
  \ir 354_PoultrySaleReversalReasonOptional.postgres.sql
\endif
\if :need353
  \echo '-- re-applying 353 (customer payment cash sync in place)'
  \ir 353_PoultryPaymentCashSyncInPlace.postgres.sql
\endif

-- -----------------------------------------------------------------------------
-- 1. 358's function bodies (verbatim from 358_PoultrySaleLines.postgres.sql)
-- -----------------------------------------------------------------------------
-- 358 section 7a: egg stock for a sale, one movement per egg line

CREATE OR REPLACE FUNCTION public.sppoultryeggstock_syncforsale(p_farmid text, p_saleid integer, p_qtysold numeric, p_createdby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_s       record;
    v_egg     integer;
    v_unsorted integer;
BEGIN
    SELECT s.status, s.ismultiline, s.saledescription, s.poultryproductid INTO v_s
    FROM   sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid;
    IF FOUND AND v_s.status = 'Reversed' THEN
        RETURN;
    END IF;

    DELETE FROM poultrystocktransactions t
    WHERE t.farmid = p_farmid AND t.txntype = 'Sale' AND t.relatedid = p_saleid;

    IF (COALESCE(p_qtysold, 0) <= 0) THEN RETURN; END IF;

    IF v_s.saledescription ILIKE 'Driver return #%' OR v_s.saledescription ILIKE 'Delivery #%' THEN
        RETURN;
    END IF;

    v_unsorted := public.fnpoultry_unsortedeggproduct(p_farmid);

    -- 358: a multi-line sale's lines are the authority, each its own movement.
    IF COALESCE(v_s.ismultiline, FALSE) THEN
        INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby, salelineid)
        SELECT p_farmid,
               CASE WHEN l.poultryproductid IS NOT NULL AND public.fnpoultry_iseggclass(p_farmid, l.poultryproductid)
                    THEN l.poultryproductid ELSE v_unsorted END,
               'Sale', -(l.quantity::numeric(14,3)), NULL, p_saleid, 'Egg sale', p_createdby, l.salelineid
        FROM   saleline l
        WHERE  l.saleid = p_saleid AND l.farmid = p_farmid AND l.quantity > 0
        ORDER  BY l.lineno;
        RETURN;
    END IF;

    IF v_s.poultryproductid IS NOT NULL AND public.fnpoultry_iseggclass(p_farmid, v_s.poultryproductid) THEN
        v_egg := v_s.poultryproductid;
    ELSE
        v_egg := v_unsorted;
    END IF;

    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby, salelineid)
    VALUES (p_farmid, v_egg, 'Sale', -(p_qtysold::numeric(14,3)), NULL, p_saleid, 'Egg sale', p_createdby,
            (SELECT l.salelineid FROM saleline l WHERE l.saleid = p_saleid AND l.lineno = 1));
END;
$function$;

-- 358 section 7b

-- 349's "add an egg size to a posted sale" contradicts 351 and 358.
CREATE OR REPLACE FUNCTION public.sppoultrysale_ensuregroup(p_farmid text, p_saleid integer, p_by text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION 'A posted sale cannot gain lines. Use Correct Sale to re-enter it with every line.'
        USING ERRCODE = 'P0001';
END;
$function$;

-- 358 section 7c: patches to live bodies (skipped where already applied)

CREATE FUNCTION pg_temp.m361_patch(p_fn regprocedure, p_from text, p_to text, p_endanchor text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
    v_src text := replace(pg_get_functiondef(p_fn), E'\r', '');
    v_a   integer;
    v_b   integer;
BEGIN
    -- Live bodies are CRLF, and so is this file when a Windows tool hands it on.
    p_from      := replace(p_from, E'\r', '');
    p_to        := replace(p_to, E'\r', '');
    p_endanchor := replace(p_endanchor, E'\r', '');
    v_a := position(p_from IN v_src);
    IF v_a = 0 AND position(left(p_to, 300) IN v_src) > 0 THEN
        RAISE NOTICE '361: % already has the 358 change', p_fn;
        RETURN;
    END IF;
    IF v_a = 0 THEN
        RAISE EXCEPTION '361: anchor not found in %: %', p_fn, left(p_from, 80);
    END IF;
    IF p_endanchor IS NULL THEN
        v_src := overlay(v_src PLACING p_to FROM v_a FOR length(p_from));
    ELSE
        v_b := position(p_endanchor IN substr(v_src, v_a));
        IF v_b = 0 THEN
            RAISE EXCEPTION '361: end anchor not found in %: %', p_fn, left(p_endanchor, 80);
        END IF;
        v_src := overlay(v_src PLACING p_to FROM v_a FOR v_b - 1);
    END IF;
    EXECUTE v_src;
END
$f$;

-- Reversal restores each line's own movement.
SELECT pg_temp.m361_patch('public.sppoultrysale_reverse(text,integer,text,text,jsonb,text,text,text)'::regprocedure,
$a$    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby)
    SELECT t.farmid, t.poultryproductid, 'Sale Reversal', -SUM(t.quantity), MIN(t.unitcost), t.relatedid,
           'Sale #' || t.relatedid || ' reversed', p_reversedby
    FROM   poultrystocktransactions t
    WHERE  t.farmid = p_farmid AND t.txntype = 'Sale' AND t.relatedid = ANY (v_ids)
    GROUP  BY t.farmid, t.poultryproductid, t.relatedid
    HAVING SUM(t.quantity) <> 0;$a$,
$b$    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby, salelineid)
    SELECT t.farmid, t.poultryproductid, 'Sale Reversal', -SUM(t.quantity), MIN(t.unitcost), t.relatedid,
           'Sale #' || t.relatedid || ' reversed', p_reversedby, t.salelineid
    FROM   poultrystocktransactions t
    WHERE  t.farmid = p_farmid AND t.txntype = 'Sale' AND t.relatedid = ANY (v_ids)
    GROUP  BY t.farmid, t.poultryproductid, t.relatedid, t.salelineid
    HAVING SUM(t.quantity) <> 0;$b$);

-- The reversal preview lists the sale's LINES and what each restores.
SELECT pg_temp.m361_patch('public.fnpoultrysale_reversalstate(text,integer)'::regprocedure,
$a$    -- ---- stock to restore, from the sale's own movements$a$,
$b$    -- ---- stock to restore, per line, from the line's own movements (358)
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'saleId', l.saleid, 'saleLineId', l.salelineid, 'lineNo', l.lineno,
               'product', l.product, 'quantity', l.quantity,
               'unitPrice', l.unitprice, 'total', l.totalamount, 'size', l.size,
               'eggProductId', l.poultryproductid,
               'restoreProductId', mv.productid, 'restoreProductName', mv.productname,
               'restoreQuantity', COALESCE(mv.qty, 0), 'restoreUnit', mv.unit)
             ORDER BY l.saleid, l.lineno), '[]'::jsonb)
    INTO   v_lines
    FROM   saleline l
    LEFT   JOIN LATERAL (
        SELECT t.poultryproductid AS productid, MIN(p.name)::text AS productname,
               (-SUM(t.quantity))::numeric(14,3) AS qty,
               CASE WHEN MIN(t.txntype) = 'Bird Sale' THEN 'birds' ELSE 'eggs' END AS unit
        FROM   poultrystocktransactions t
        LEFT   JOIN poultryproducts p ON p.poultryproductid = t.poultryproductid
        WHERE  t.farmid = p_farmid AND t.relatedid = l.saleid AND t.txntype IN ('Sale', 'Bird Sale')
          AND  (t.salelineid = l.salelineid OR (t.salelineid IS NULL AND l.lineno = 1))
        GROUP  BY t.poultryproductid
        HAVING SUM(t.quantity) <> 0
        LIMIT  1) mv ON TRUE
    WHERE  l.farmid = p_farmid AND l.saleid = ANY (v_ids);

$b$,
'    -- ---- money already applied, one item per payment group');

-- Cash Flow: ONE receipt per payment, not one per sale it paid.
SELECT pg_temp.m361_patch('public.sppoultrycashflow_rows(text,timestamp without time zone,timestamp without time zone)'::regprocedure,
'    -- ---- 1. customer receipts, dated when the money arrived',
$b$    -- ---- 1. customer receipts, ONE row per payment (358) -------------------
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
           concat_ws(' · ',
               CASE WHEN COUNT(DISTINCT p.saleid) = 1
                    THEN 'Sale ' || COALESCE(MIN(s.salegroupno), '#' || MIN(p.saleid)::text)
                    ELSE COUNT(DISTINCT p.saleid)::text || ' sales' END,
               NULLIF(btrim(MIN(s.customername)::text), ''),
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
           concat_ws(' · ',
               'Payment reversal' || COALESCE(' ' || MIN(p.paymentnumber), ''),
               CASE WHEN COUNT(DISTINCT p.saleid) = 1
                    THEN 'Sale ' || COALESCE(MIN(s.salegroupno), '#' || MIN(p.saleid)::text)
                    ELSE COUNT(DISTINCT p.saleid)::text || ' sales' END)::text,
           'OperatingIn'::text,
           MIN(p.reversedat)
    FROM   poultrypayments p
    LEFT   JOIN sale s ON s.saleid = p.saleid AND s.farmid = p.farmid
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) <> 0
      AND  p.status = 'Reversed'
      AND  p.reversedat IS NOT NULL
      AND  fnpoultry_businessdateof(p_farmid, p.reversedat)::timestamp >= v_from
      AND  fnpoultry_businessdateof(p_farmid, p.reversedat)::timestamp <= v_to
    GROUP  BY COALESCE(p.paymentgroupid::text, 'row:' || p.poultrypaymentid::text),
              fnpoultry_businessdateof(p_farmid, p.reversedat);

$b$,
'    -- ---- 1c. (351) customer refunds');

-- 358 section 7d

CREATE OR REPLACE FUNCTION public.fnpoultrysale_productlabel(p_saleid integer)
RETURNS text
LANGUAGE sql
STABLE
AS $f$
    SELECT CASE WHEN s.ismultiline
                THEN s.product || ' · ' || (SELECT COUNT(*) FROM saleline l WHERE l.saleid = s.saleid) || ' lines'
                ELSE s.product END::text
    FROM   sale s WHERE s.saleid = p_saleid;
$f$;

SELECT pg_temp.m361_patch('public.sppoultrycustomerpayment_allocations(text,uuid)'::regprocedure,
    'ca.saleid, s.saledate, s.product::text,', 'ca.saleid, s.saledate, fnpoultrysale_productlabel(s.saleid),');
SELECT pg_temp.m361_patch('public.sppoultrycustomeropensales(text,integer,date,date,text)'::regprocedure,
    'SELECT s.saleid, s.saledate, s.product::text,', 'SELECT s.saleid, s.saledate, fnpoultrysale_productlabel(s.saleid),');

-- 358 section 7e: sale reads carry their lines

CREATE OR REPLACE FUNCTION public.fnpoultrysale_lines(p_saleid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'saleLineId', l.salelineid, 'lineNo', l.lineno, 'product', l.product,
               'eggProductId', l.poultryproductid, 'size', l.size, 'quantity', l.quantity,
               'unitPrice', l.unitprice, 'totalAmount', l.totalamount)
             ORDER BY l.lineno), '[]'::jsonb)
    FROM   saleline l WHERE l.saleid = p_saleid;
$f$;

DROP FUNCTION IF EXISTS public.spsale_getall(text);
CREATE FUNCTION public.spsale_getall(p_farmid text)
 RETURNS TABLE(saleid integer, userid text, farmid text, saledate date, product text, quantity numeric, unitprice numeric, totalamount numeric, paymentmethod text, customername text, flockid integer, saledescription text, paid boolean, size text, poultrycashaccountid integer, amountpaid numeric, createddate timestamp without time zone, customerid integer, poultryproductid integer, salegroupno text, status text, reversedat timestamp without time zone, reversedby text, reversalreason text, salereversalid integer, correctssaleid integer, correctedbysaleid integer, linecount integer, salelines text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT s.saleid, s.userid::text, s.farmid::text, s.saledate, s.product::text,
           s.quantity, s.unitprice, s.totalamount,
           s.paymentmethod::text, s.customername::text, s.flockid, s.saledescription::text,
           COALESCE(s.paid, TRUE) AS paid,
           s.size::text, s.poultrycashaccountid, COALESCE(s.amountpaid, 0) AS amountpaid,
           s.createddate, s.customerid,
           s.poultryproductid, s.salegroupno,
           s.status, s.reversedat, s.reversedby, s.reversalreason, s.salereversalid, s.correctssaleid,
           r.correctionsaleid,
           (SELECT COUNT(*)::int FROM saleline l WHERE l.saleid = s.saleid),
           fnpoultrysale_lines(s.saleid)::text
    FROM   sale s
    LEFT   JOIN poultrysalereversals r ON r.salereversalid = s.salereversalid
    WHERE  s.farmid = p_farmid
    ORDER  BY s.saledate DESC, s.createddate DESC;
$function$;

DROP FUNCTION IF EXISTS public.spsale_getbyid(integer, text);
CREATE FUNCTION public.spsale_getbyid(p_saleid integer, p_farmid text)
 RETURNS TABLE(saleid integer, userid text, farmid text, saledate date, product text, quantity numeric, unitprice numeric, totalamount numeric, paymentmethod text, customername text, flockid integer, saledescription text, paid boolean, size text, poultrycashaccountid integer, amountpaid numeric, createddate timestamp without time zone, customerid integer, poultryproductid integer, salegroupno text, status text, reversedat timestamp without time zone, reversedby text, reversalreason text, salereversalid integer, correctssaleid integer, correctedbysaleid integer, linecount integer, salelines text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT s.saleid, s.userid::text, s.farmid::text, s.saledate, s.product::text,
           s.quantity, s.unitprice, s.totalamount,
           s.paymentmethod::text, s.customername::text, s.flockid, s.saledescription::text,
           COALESCE(s.paid, TRUE) AS paid,
           s.size::text, s.poultrycashaccountid, COALESCE(s.amountpaid, 0) AS amountpaid,
           s.createddate, s.customerid,
           s.poultryproductid, s.salegroupno,
           s.status, s.reversedat, s.reversedby, s.reversalreason, s.salereversalid, s.correctssaleid,
           r.correctionsaleid,
           (SELECT COUNT(*)::int FROM saleline l WHERE l.saleid = s.saleid),
           fnpoultrysale_lines(s.saleid)::text
    FROM   sale s
    LEFT   JOIN poultrysalereversals r ON r.salereversalid = s.salereversalid
    WHERE  s.saleid = p_saleid AND s.farmid = p_farmid;
$function$;

DROP FUNCTION IF EXISTS public.spsale_getbyflock(integer, text);
CREATE FUNCTION public.spsale_getbyflock(p_flockid integer, p_farmid text)
 RETURNS TABLE(saleid integer, userid text, farmid text, saledate date, product text, quantity numeric, unitprice numeric, totalamount numeric, paymentmethod text, customername text, flockid integer, saledescription text, paid boolean, size text, poultrycashaccountid integer, amountpaid numeric, createddate timestamp without time zone, customerid integer, poultryproductid integer, salegroupno text, status text, reversedat timestamp without time zone, reversedby text, reversalreason text, salereversalid integer, correctssaleid integer, correctedbysaleid integer, linecount integer, salelines text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT s.saleid, s.userid::text, s.farmid::text, s.saledate, s.product::text,
           s.quantity, s.unitprice, s.totalamount,
           s.paymentmethod::text, s.customername::text, s.flockid, s.saledescription::text,
           COALESCE(s.paid, TRUE) AS paid,
           s.size::text, s.poultrycashaccountid, COALESCE(s.amountpaid, 0) AS amountpaid,
           s.createddate, s.customerid,
           s.poultryproductid, s.salegroupno,
           s.status, s.reversedat, s.reversedby, s.reversalreason, s.salereversalid, s.correctssaleid,
           NULL::integer,
           (SELECT COUNT(*)::int FROM saleline l WHERE l.saleid = s.saleid),
           fnpoultrysale_lines(s.saleid)::text
    FROM   sale s
    WHERE  s.flockid = p_flockid AND s.farmid = p_farmid AND s.status = 'Posted'
    ORDER  BY s.saledate DESC, s.createddate DESC;
$function$;

-- 358 section 7f: egg sales report, one row per egg line

CREATE OR REPLACE FUNCTION public.sppoultryreport_eggsales_rs1(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_customername text DEFAULT NULL::text)
 RETURNS TABLE(date date, saleid integer, customer text, product text, size text, quantitysold numeric, unitprice numeric, totalamount numeric, paid boolean, amountpaid numeric, paymentmethod text, flockid integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        s.saledate::date                AS date,
        s.saleid                        AS saleid,
        s.customername::text            AS customer,
        l.product::text                 AS product,
        l.size::text                    AS size,
        l.quantity                      AS quantitysold,
        l.unitprice                     AS unitprice,
        l.totalamount                   AS totalamount,
        COALESCE(s.paid, TRUE)          AS paid,
        CASE WHEN COALESCE(s.paid, TRUE) THEN l.totalamount
             WHEN s.totalamount > 0 THEN round(COALESCE(s.amountpaid, 0) * l.totalamount / s.totalamount, 2)
             ELSE 0 END                 AS amountpaid,
        s.paymentmethod::text           AS paymentmethod,
        s.flockid                       AS flockid
    FROM   sale s
    JOIN   saleline l ON l.saleid = s.saleid
    WHERE  s.status = 'Posted' AND s.farmid = p_farmid
      AND  s.saledate >= p_startdate AND s.saledate < (p_enddate + 1)
      AND  (p_flockid IS NULL OR s.flockid = p_flockid)
      AND  (p_customername IS NULL OR s.customername = p_customername)
      AND  COALESCE(l.product, '') ILIKE '%egg%'
    ORDER  BY s.saledate DESC, s.saleid DESC, l.lineno;
END
$function$;

-- -----------------------------------------------------------------------------
-- 2. Stock repair
-- -----------------------------------------------------------------------------
SELECT set_config('poultry.sale_system', 'on', true);

DO $fix$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT * FROM m361_fix ORDER BY farmid, saleid LOOP
        PERFORM public.sppoultryeggstock_syncforsale(r.farmid, r.saleid, r.quantity, r.createdby);
        -- keep the movement on the day it really happened
        UPDATE poultrystocktransactions t
        SET    createddate = r.createddate
        WHERE  t.farmid = r.farmid AND t.relatedid = r.saleid AND t.txntype = 'Sale';
    END LOOP;
END
$fix$;

-- One-line sales: only the line link the old body left out.
UPDATE poultrystocktransactions t
SET    salelineid = l.salelineid
FROM   sale s
JOIN   saleline l ON l.saleid = s.saleid AND l.lineno = 1
WHERE  t.relatedid = s.saleid AND t.farmid = s.farmid AND NOT s.ismultiline
  AND  t.txntype IN ('Sale', 'Sale Reversal', 'Bird Sale')
  AND  t.salelineid IS NULL;

SELECT set_config('poultry.sale_system', 'off', true);

-- -----------------------------------------------------------------------------
-- 3. Proof
-- -----------------------------------------------------------------------------
SELECT pg_temp.m361_measure('after');

DO $verify$
DECLARE
    v_bad text;
BEGIN
    SELECT string_agg(format('%s %s: %s -> %s', left(COALESCE(b.farmid, a.farmid), 8),
                             COALESCE(b.metric, a.metric), b.value, a.value), '; ')
    INTO   v_bad
    FROM  (SELECT * FROM m361_measure WHERE phase = 'before') b
    FULL   JOIN (SELECT * FROM m361_measure WHERE phase = 'after') a
           ON a.farmid = b.farmid AND a.metric = b.metric
    WHERE  COALESCE(a.value, 0) <> COALESCE(b.value, 0);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION '361: money or total stock moved: %', v_bad;
    END IF;

    -- every repaired sale: one movement per line, on the line's class, summing to the sale
    SELECT string_agg('#' || f.saleid, ', ') INTO v_bad
    FROM   m361_fix f
    WHERE  EXISTS (
        SELECT 1 FROM saleline l
        WHERE  l.saleid = f.saleid AND l.quantity > 0
          AND  NOT EXISTS (SELECT 1 FROM poultrystocktransactions t
                           WHERE t.relatedid = f.saleid AND t.txntype = 'Sale' AND t.salelineid = l.salelineid
                             AND t.quantity = -l.quantity
                             AND t.poultryproductid = CASE WHEN l.poultryproductid IS NOT NULL
                                                             AND fnpoultry_iseggclass(f.farmid, l.poultryproductid)
                                                           THEN l.poultryproductid
                                                           ELSE fnpoultry_unsortedeggproduct(f.farmid) END))
        OR (SELECT COALESCE(SUM(t.quantity), 0) FROM poultrystocktransactions t
            WHERE t.relatedid = f.saleid AND t.txntype = 'Sale') <> -f.quantity;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION '361: stock still not per line for sales %', v_bad;
    END IF;

    SELECT string_agg(m.fn || ' (' || m.marker || ')', ', ') INTO v_bad
    FROM   m361_markers m WHERE NOT pg_temp.m361_has(m.fn, m.marker);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION '361: still missing: %', v_bad;
    END IF;
END
$verify$;

\echo '== After: egg stock by class that moved (per company)'
SELECT COALESCE(b.farmid, a.farmid) AS farmid, p.name, b.qty AS before_qty, a.qty AS after_qty
FROM  (SELECT t.farmid, t.poultryproductid, SUM(t.quantity) AS qty FROM poultrystocktransactions t
       WHERE t.farmid IN (SELECT farmid FROM m361_fix) GROUP BY 1, 2) a
FULL  JOIN m361_classes_before b ON b.farmid = a.farmid AND b.poultryproductid = a.poultryproductid
LEFT  JOIN poultryproducts p ON p.poultryproductid = COALESCE(a.poultryproductid, b.poultryproductid)
WHERE COALESCE(a.qty, 0) <> COALESCE(b.qty, 0)
ORDER BY 1, 2;

\echo '== All checks passed.'
\if :apply
    COMMIT;
    \echo '>>> COMMITTED. No API restart needed: these functions are read live.'
\else
    ROLLBACK;
    \echo '>>> DRY RUN: nothing saved. Re-run with  -v apply=true  to write it.'
\endif

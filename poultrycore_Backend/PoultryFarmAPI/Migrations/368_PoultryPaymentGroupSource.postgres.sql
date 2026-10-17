-- =============================================================================
-- 368_PoultryPaymentGroupSource.postgres.sql
--
-- Since 367 a customer payment can pay sales AND keep the rest as credit: one
-- payment (group) with sale rows plus one row with no sale, sourcetype
-- 'Deposit'. Readers that summarise a payment took MIN(sourcetype) -- the
-- alphabetically first -- so such a payment read as a "Deposit": the wrong
-- label, and Payments Received hid its Reverse button (manual credit is
-- reversed from Customer Credits).
--
-- A payment's source is now that of its sale rows; a payment with no sale row
-- keeps its own. Patched in place (anchors must match exactly once):
--   sppoultrycustomerpayment_history   Payments Received / payment history
--   sppoultrycustomerstatement         the statement line, and "Customer advance received"
-- =============================================================================
BEGIN;

CREATE FUNCTION pg_temp.m368_patch(p_fn text, p_marker text, p_old text, p_new text)
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
        RAISE EXCEPTION '368: expected exactly one %, found %', p_fn, v_n;
    END IF;
    v_def := replace(pg_get_functiondef(v_oid), chr(13), '');
    IF position(replace(p_marker, chr(13), '') IN v_def) > 0 THEN
        RAISE NOTICE '368: % already patched (%), skipped', p_fn, p_marker;
        RETURN;
    END IF;
    v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / greatest(length(v_old), 1);
    IF v_n <> 1 THEN
        RAISE EXCEPTION '368: anchor for % (%) found % times, expected 1', p_fn, p_marker, v_n;
    END IF;
    EXECUTE replace(v_def, v_old, v_new);
    RAISE NOTICE '368: patched % (%)', p_fn, p_marker;
END
$f$;

SELECT pg_temp.m368_patch('sppoultrycustomerpayment_history', '368: the sale rows'' source',
$o$           MIN(pp.sourcetype)::text,$o$,
$n$           -- 368: the sale rows' source; a payment with no sale keeps its own.
           COALESCE(MIN(pp.sourcetype) FILTER (WHERE pp.saleid IS NOT NULL), MIN(pp.sourcetype))::text,$n$);

SELECT pg_temp.m368_patch('sppoultrycustomerstatement', '368: kind of payment',
$o$               (CASE MIN(pp.sourcetype)   -- 363: kind of credit
                     WHEN 'OpeningCredit' THEN 'Opening credit'
                     WHEN 'CreditNote'    THEN 'Credit note'
                     WHEN 'Deposit'       THEN 'Deposit received'$o$,
$n$               (CASE COALESCE(MIN(pp.sourcetype) FILTER (WHERE pp.saleid IS NOT NULL), MIN(pp.sourcetype))   -- 368: kind of payment
                     WHEN 'OpeningCredit' THEN 'Opening credit'
                     WHEN 'CreditNote'    THEN 'Credit note'
                     WHEN 'Deposit'       THEN 'Customer advance received'$n$);

SELECT pg_temp.m368_patch('sppoultrycustomerstatement', '368: the line''s source',
$o$               MIN(pp.sourcetype)::text
        FROM   poultrypayments pp$o$,
$n$               COALESCE(MIN(pp.sourcetype) FILTER (WHERE pp.saleid IS NOT NULL), MIN(pp.sourcetype))::text   -- 368: the line's source
        FROM   poultrypayments pp$n$);

COMMIT;

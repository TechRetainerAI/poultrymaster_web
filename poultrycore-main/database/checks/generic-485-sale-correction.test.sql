-- 485_Enock_GenericSaleCorrection -- Correct sale / Edit & repost on Generic.
-- Self-contained: BEGIN ... ROLLBACK. Builds its own sales in the Generic
-- company with the most sales.
--   485.1  a reversed sale has no correction; the list says so
--   485.2  a new sale links to it; list + reversal record name the correction
--   485.3  a second live correction is refused; only reversed sales can be corrected
--   485.4  cancelling the correcting draft frees the reversed sale to be reposted
--   485.5  list filters still partition (484 behaviour kept)
BEGIN;

CREATE FUNCTION pg_temp.mk_sale485(p_farm text, p_cust integer, p_acct integer, p_prod integer, p_approve boolean)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_id integer;
BEGIN
    INSERT INTO genericsales (farmid, saledate, status, genericcustomerid, genericcashaccountid, subtotalamount,
                              totalamount, amountpaid, balance, paymentmethod, applycreditamount, createdby)
    VALUES (p_farm, now() AT TIME ZONE 'utc', 'Draft', p_cust, p_acct, 200, 200, 0, 200, 'Cash', 0, '485-check')
    RETURNING genericsaleid INTO v_id;
    INSERT INTO genericsaleitems (genericsaleid, farmid, itemtype, genericproductid, description, quantity, unitprice, unitfactor)
    VALUES (v_id, p_farm, 'Product', p_prod, '485 check item', 2, 100, 1);
    IF p_approve THEN PERFORM spgenericsale_approve(v_id, p_farm, '485-check'); END IF;
    RETURN v_id;
END $$;

CREATE FUNCTION pg_temp.must_fail485(p_sql text, p_like text, p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM ILIKE '%' || p_like || '%' THEN RETURN; END IF;
        RAISE EXCEPTION 'FAIL %: refused with the wrong message: %', p_label, SQLERRM;
    END;
    RAISE EXCEPTION 'FAIL %: was accepted', p_label;
END $$;

DO $$
DECLARE
    v_farm text; v_cust integer; v_acct integer; v_prod integer;
    v_old integer; v_new integer; v_new2 integer; v_other integer; v_pre jsonb; v_by integer; v_rec jsonb;
BEGIN
    SELECT s.farmid INTO v_farm FROM genericsales s GROUP BY s.farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT c.genericcustomerid INTO v_cust FROM genericcustomers c WHERE c.farmid = v_farm ORDER BY c.genericcustomerid LIMIT 1;
    SELECT a.genericcashaccountid INTO v_acct FROM genericcashaccounts a WHERE a.farmid = v_farm ORDER BY a.genericcashaccountid LIMIT 1;
    SELECT p.genericproductid INTO v_prod FROM genericproducts p WHERE p.farmid = v_farm AND p.trackinventory ORDER BY p.genericproductid LIMIT 1;
    IF v_cust IS NULL OR v_acct IS NULL OR v_prod IS NULL THEN RAISE EXCEPTION 'FAIL 485.0: test company lacks a customer, account or product'; END IF;
    UPDATE genericproducts SET currentstock = currentstock + 1000 WHERE genericproductid = v_prod;

    -- 1. reverse an unpaid credit sale
    v_old := pg_temp.mk_sale485(v_farm, v_cust, v_acct, v_prod, true);
    v_pre := spgenericsale_reversalpreview(v_farm, v_old);
    PERFORM spgenericsale_reverse(v_farm, v_old, 'Wrong quantity', NULL, '{}'::jsonb, v_pre->>'fingerprint', NULL, '485-check');
    SELECT correctedbysaleid INTO v_by FROM spgenericsale_getall(v_farm, NULL) WHERE genericsaleid = v_old;
    IF v_by IS NOT NULL THEN RAISE EXCEPTION 'FAIL 485.1: a fresh reversal already shows a correction %', v_by; END IF;
    RAISE NOTICE 'ok 485.1 a reversed sale starts with no correction';

    -- 2. the corrected sale links to it
    v_new := pg_temp.mk_sale485(v_farm, v_cust, v_acct, v_prod, false);
    PERFORM spgenericsale_linkcorrection(v_farm, v_new, v_old, '485-check');
    IF (SELECT correctssaleid FROM genericsales WHERE genericsaleid = v_new) IS DISTINCT FROM v_old THEN
        RAISE EXCEPTION 'FAIL 485.2: the new sale does not point at the reversed one'; END IF;
    SELECT correctedbysaleid INTO v_by FROM spgenericsale_getall(v_farm, NULL) WHERE genericsaleid = v_old;
    IF v_by IS DISTINCT FROM v_new THEN RAISE EXCEPTION 'FAIL 485.2: list says corrected by % (expected %)', v_by, v_new; END IF;
    v_rec := spgenericsale_reversalget(v_farm, v_old);
    IF (v_rec->>'correctionSaleId')::int IS DISTINCT FROM v_new THEN
        RAISE EXCEPTION 'FAIL 485.2: reversal record names % (expected %)', v_rec->>'correctionSaleId', v_new; END IF;
    PERFORM spgenericsale_linkcorrection(v_farm, v_new, v_old, '485-check');  -- the same link again is harmless
    RAISE NOTICE 'ok 485.2 the new sale links to the reversed one; list and reversal record name it';

    -- 3. refusals
    v_new2 := pg_temp.mk_sale485(v_farm, v_cust, v_acct, v_prod, false);
    PERFORM pg_temp.must_fail485(format('SELECT spgenericsale_linkcorrection(%L, %s, %s)', v_farm, v_new2, v_old), 'already corrected', '485.3 second correction');
    v_other := pg_temp.mk_sale485(v_farm, v_cust, v_acct, v_prod, true);
    PERFORM pg_temp.must_fail485(format('SELECT spgenericsale_linkcorrection(%L, %s, %s)', v_farm, v_new2, v_other), 'not a reversed sale', '485.3 correct a live sale');
    PERFORM pg_temp.must_fail485(format('SELECT spgenericsale_linkcorrection(%L, %s, %s)', v_farm, v_old, v_old), 'cannot correct itself', '485.3 self');
    RAISE NOTICE 'ok 485.3 a second correction, correcting a live sale, and self-correction are refused';

    -- 4. cancelling the correcting draft frees the reversed sale
    PERFORM spgenericsale_cancel(v_new, v_farm, '485-check', 'Entered twice');
    SELECT correctedbysaleid INTO v_by FROM spgenericsale_getall(v_farm, NULL) WHERE genericsaleid = v_old;
    IF v_by IS NOT NULL THEN RAISE EXCEPTION 'FAIL 485.4: a cancelled draft still counts as the correction'; END IF;
    PERFORM spgenericsale_linkcorrection(v_farm, v_new2, v_old, '485-check');
    SELECT correctedbysaleid INTO v_by FROM spgenericsale_getall(v_farm, NULL) WHERE genericsaleid = v_old;
    IF v_by IS DISTINCT FROM v_new2 THEN RAISE EXCEPTION 'FAIL 485.4: repost after cancel not linked'; END IF;
    RAISE NOTICE 'ok 485.4 cancelling the correcting draft lets the reversed sale be reposted';

    -- 5. 484 filters still partition
    IF (SELECT count(*) FROM spgenericsale_getall(v_farm, 'Reversed')) + (SELECT count(*) FROM spgenericsale_getall(v_farm, 'Cancelled'))
       <> (SELECT count(*) FROM genericsales WHERE farmid = v_farm AND isdeleted = FALSE AND status = 'Cancelled') THEN
        RAISE EXCEPTION 'FAIL 485.5: Reversed + Cancelled no longer cover every cancelled sale'; END IF;
    RAISE NOTICE 'ok 485.5 Reversed / Cancelled filters still partition';

    RAISE NOTICE 'generic 485: all checks passed';
END $$;

ROLLBACK;

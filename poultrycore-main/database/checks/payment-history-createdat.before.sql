-- Baseline captured INSIDE the dry-run transaction, BEFORE 304 replaces the six
-- payment-history readers.
--
-- Two of them GROUP BY paymentgroupid, so the risk is not a missing column but a
-- changed grouping: add a column wrongly and one payment group becomes several
-- rows, which would double-count on the payments pages. Row count and the summed
-- total are captured so the checks can prove neither moved.

CREATE TEMP TABLE before304(reader text, rows bigint, total numeric);

DO $before$
DECLARE v_rows bigint; v_total numeric;
BEGIN
    SELECT COUNT(*), COALESCE(SUM(r.totalamount),0) INTO v_rows, v_total
    FROM farms f CROSS JOIN LATERAL
         public.sppoultrycustomerpayment_history(f.farmid, NULL, NULL, NULL, NULL) r;
    INSERT INTO before304 VALUES ('sppoultrycustomerpayment_history', v_rows, v_total);

    SELECT COUNT(*), COALESCE(SUM(r.totalamount),0) INTO v_rows, v_total
    FROM farms f CROSS JOIN LATERAL
         public.sppoultrysupplierpayment_history(f.farmid, NULL, NULL, NULL, NULL, NULL) r;
    INSERT INTO before304 VALUES ('sppoultrysupplierpayment_history', v_rows, v_total);

    SELECT COUNT(*), COALESCE(SUM(r.totalamount),0) INTO v_rows, v_total
    FROM farms f CROSS JOIN LATERAL
         public.spwatercustomerpayment_history(f.farmid, NULL, NULL, NULL, NULL) r;
    INSERT INTO before304 VALUES ('spwatercustomerpayment_history', v_rows, v_total);

    SELECT COUNT(*), COALESCE(SUM(r.totalamount),0) INTO v_rows, v_total
    FROM farms f CROSS JOIN LATERAL
         public.spwatersupplierpayment_history(f.farmid, NULL, NULL, NULL, NULL, NULL) r;
    INSERT INTO before304 VALUES ('spwatersupplierpayment_history', v_rows, v_total);

    SELECT COUNT(*), COALESCE(SUM(r.totalamount),0) INTO v_rows, v_total
    FROM farms f CROSS JOIN LATERAL
         public.spgenericcustomerpayment_history(f.farmid, NULL, NULL, NULL, NULL) r;
    INSERT INTO before304 VALUES ('spgenericcustomerpayment_history', v_rows, v_total);

    SELECT COUNT(*), COALESCE(SUM(r.totalamount),0) INTO v_rows, v_total
    FROM farms f CROSS JOIN LATERAL
         public.spgenericsupplierpayment_history(f.farmid, NULL, NULL, NULL, NULL, NULL) r;
    INSERT INTO before304 VALUES ('spgenericsupplierpayment_history', v_rows, v_total);

    RAISE NOTICE 'baseline captured for % payment readers', (SELECT COUNT(*) FROM before304);
END
$before$;

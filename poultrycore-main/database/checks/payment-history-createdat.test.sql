-- Checks for 304_PaymentHistoryReturnsCreatedAt.

\pset footer off

\echo
\echo === A. Same rows and same money from every reader ===
-- The grouped readers are the risk: a mis-added column would split one payment
-- group into several rows and double-count the payments pages.
DO $verify$
DECLARE b record; v_rows bigint; v_total numeric;
BEGIN
    FOR b IN SELECT * FROM before304 ORDER BY reader LOOP
        IF b.reader = 'sppoultrycustomerpayment_history' THEN
            SELECT COUNT(*), COALESCE(SUM(r.totalamount),0) INTO v_rows, v_total
            FROM farms f CROSS JOIN LATERAL
                 public.sppoultrycustomerpayment_history(f.farmid, NULL, NULL, NULL, NULL) r;
        ELSIF b.reader = 'sppoultrysupplierpayment_history' THEN
            SELECT COUNT(*), COALESCE(SUM(r.totalamount),0) INTO v_rows, v_total
            FROM farms f CROSS JOIN LATERAL
                 public.sppoultrysupplierpayment_history(f.farmid, NULL, NULL, NULL, NULL, NULL) r;
        ELSIF b.reader = 'spwatercustomerpayment_history' THEN
            SELECT COUNT(*), COALESCE(SUM(r.totalamount),0) INTO v_rows, v_total
            FROM farms f CROSS JOIN LATERAL
                 public.spwatercustomerpayment_history(f.farmid, NULL, NULL, NULL, NULL) r;
        ELSIF b.reader = 'spwatersupplierpayment_history' THEN
            SELECT COUNT(*), COALESCE(SUM(r.totalamount),0) INTO v_rows, v_total
            FROM farms f CROSS JOIN LATERAL
                 public.spwatersupplierpayment_history(f.farmid, NULL, NULL, NULL, NULL, NULL) r;
        ELSIF b.reader = 'spgenericcustomerpayment_history' THEN
            SELECT COUNT(*), COALESCE(SUM(r.totalamount),0) INTO v_rows, v_total
            FROM farms f CROSS JOIN LATERAL
                 public.spgenericcustomerpayment_history(f.farmid, NULL, NULL, NULL, NULL) r;
        ELSE
            SELECT COUNT(*), COALESCE(SUM(r.totalamount),0) INTO v_rows, v_total
            FROM farms f CROSS JOIN LATERAL
                 public.spgenericsupplierpayment_history(f.farmid, NULL, NULL, NULL, NULL, NULL) r;
        END IF;

        RAISE NOTICE '% rows  expect % got %',  b.reader, b.rows,  v_rows;
        RAISE NOTICE '% total  expect % got %', b.reader, b.total, v_total;
    END LOOP;
END
$verify$;

\echo
\echo === B. All six declare createdat ===
SELECT p.proname || '  expect yes got '
       || CASE WHEN pg_get_function_result(p.oid) ILIKE '%createdat%' THEN 'yes' ELSE 'no' END AS check
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname='public' AND p.prokind='f'
  AND  p.proname ~ '(customerpayment|supplierpayment)_history'
ORDER  BY p.proname;

\echo
\echo === C. Exactly one overload each ===
-- A wrong DROP signature would leave the old function beside the new one, and
-- which one the API binds to would be down to argument coercion.
SELECT p.proname || '  expect 1 got ' || COUNT(*)::text AS check
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname='public' AND p.prokind='f'
  AND  p.proname ~ '(customerpayment|supplierpayment)_history'
GROUP  BY p.proname ORDER BY p.proname;

\echo
\echo === D. The time is populated, not just declared ===
SELECT 'poultry customer payments without an entry time  expect 0 got '
       || COUNT(*) FILTER (WHERE r.createdat IS NULL)::text AS check
FROM farms f CROSS JOIN LATERAL
     public.sppoultrycustomerpayment_history(f.farmid, NULL, NULL, NULL, NULL) r;

SELECT 'poultry supplier payments without an entry time  expect 0 got '
       || COUNT(*) FILTER (WHERE r.createdat IS NULL)::text AS check
FROM farms f CROSS JOIN LATERAL
     public.sppoultrysupplierpayment_history(f.farmid, NULL, NULL, NULL, NULL, NULL) r;

\echo
\echo === E. The API role can still execute them ===
SELECT p.proname || '  expect true got '
       || has_function_privilege('poultryapp', p.oid, 'EXECUTE')::text AS check
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname='public' AND p.prokind='f'
  AND  p.proname ~ '(customerpayment|supplierpayment)_history'
ORDER  BY p.proname;

\echo
\echo === F. Sample: payment date vs entry time ===
SELECT r.paymentdate::date AS business_date, r.createdat AS entry_time, r.totalamount
FROM farms f CROSS JOIN LATERAL
     public.sppoultrycustomerpayment_history(f.farmid, NULL, NULL, NULL, NULL) r
ORDER BY r.createdat DESC NULLS LAST LIMIT 5;

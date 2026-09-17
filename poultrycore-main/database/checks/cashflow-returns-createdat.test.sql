-- Checks for 302_CashFlowReturnsCreatedAt.

\pset footer off

\echo
\echo === A. Every cash flow reader returns the SAME rows and the SAME money ===
-- The whole point. A union leg that quietly stops matching would change what the
-- Cash Flow page reports, which matters far more than a missing time.
DO $verify$
DECLARE
    b record; v_rows bigint; v_total numeric; v_sum text;
BEGIN
    FOR b IN SELECT * FROM before302 ORDER BY reader LOOP
        IF b.reader = 'sppoultrycashflow_rows' THEN
            SELECT COUNT(*), COALESCE(SUM(r.amount),0), md5(COALESCE(string_agg(t.sig,'|' ORDER BY t.sig),''))
              INTO v_rows, v_total, v_sum
            FROM farms f CROSS JOIN LATERAL public.sppoultrycashflow_rows(f.farmid, NULL, NULL) r
            CROSS JOIN LATERAL (SELECT r.rowsource||':'||COALESCE(r.sourcerowid::text,'')||':'
                                    ||COALESCE(r.amount::text,'')||':'||COALESCE(r.transactiondate::text,'')
                                    ||':'||COALESCE(r.flowgroup,'') AS sig) t
            WHERE f.type='Poultry';
        ELSIF b.reader = 'spwatercashflow_rows' THEN
            SELECT COUNT(*), COALESCE(SUM(r.amount),0), md5(COALESCE(string_agg(t.sig,'|' ORDER BY t.sig),''))
              INTO v_rows, v_total, v_sum
            FROM farms f CROSS JOIN LATERAL public.spwatercashflow_rows(f.farmid, NULL, NULL) r
            CROSS JOIN LATERAL (SELECT r.rowsource||':'||COALESCE(r.sourcerowid::text,'')||':'
                                    ||COALESCE(r.amount::text,'')||':'||COALESCE(r.transactiondate::text,'')
                                    ||':'||COALESCE(r.flowgroup,'') AS sig) t
            WHERE f.type='Water';
        ELSIF b.reader = 'sppoultrycashflow_detail' THEN
            SELECT COUNT(*), COALESCE(SUM(r.amount),0), md5(COALESCE(string_agg(t.sig,'|' ORDER BY t.sig),''))
              INTO v_rows, v_total, v_sum
            FROM farms f CROSS JOIN LATERAL public.sppoultrycashflow_detail(f.farmid, NULL, NULL) r
            CROSS JOIN LATERAL (SELECT r.rowsource||':'||COALESCE(r.sourcerowid::text,'')||':'
                                    ||COALESCE(r.amount::text,'')||':'||COALESCE(r.category,'') AS sig) t
            WHERE f.type='Poultry';
        ELSE
            SELECT COUNT(*), COALESCE(SUM(r.amount),0), md5(COALESCE(string_agg(t.sig,'|' ORDER BY t.sig),''))
              INTO v_rows, v_total, v_sum
            FROM farms f CROSS JOIN LATERAL public.spwatercashflow_detail(f.farmid, NULL, NULL) r
            CROSS JOIN LATERAL (SELECT r.rowsource||':'||COALESCE(r.sourcerowid::text,'')||':'
                                    ||COALESCE(r.amount::text,'')||':'||COALESCE(r.category,'') AS sig) t
            WHERE f.type='Water';
        END IF;

        RAISE NOTICE '% rows  expect % got %',   b.reader, b.rows,  v_rows;
        RAISE NOTICE '% total  expect % got %',  b.reader, b.total, v_total;
        RAISE NOTICE '% values  expect % got %', b.reader, b.checksum, v_sum;
    END LOOP;
END
$verify$;

\echo
\echo === B. All four declare createdat ===
SELECT p.proname || '  expect yes got '
       || CASE WHEN pg_get_function_result(p.oid) ILIKE '%createdat%' THEN 'yes' ELSE 'no' END AS check
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname='public' AND p.prokind='f'
  AND  p.proname IN ('sppoultrycashflow_rows','spwatercashflow_rows',
                     'sppoultrycashflow_detail','spwatercashflow_detail')
ORDER  BY p.proname;

\echo
\echo === C. The time is actually populated now ===
-- Before 302 only 64 of 388 poultry rows carried a real clock time. Every leg
-- except the legacy-adjustment one should now supply one, so the count of rows
-- WITHOUT a time should drop sharply.
SELECT 'poultry cash flow rows without an entry time  expect 0 got '
       || COUNT(*) FILTER (WHERE r.createdat IS NULL)::text AS check
FROM farms f CROSS JOIN LATERAL public.sppoultrycashflow_rows(f.farmid, NULL, NULL) r
WHERE f.type='Poultry';

SELECT 'water cash flow rows without an entry time  expect 0 got '
       || COUNT(*) FILTER (WHERE r.createdat IS NULL)::text AS check
FROM farms f CROSS JOIN LATERAL public.spwatercashflow_rows(f.farmid, NULL, NULL) r
WHERE f.type='Water';

\echo
\echo === D. The API role can still execute them ===
SELECT p.proname || '  expect true got '
       || has_function_privilege('poultryapp', p.oid, 'EXECUTE')::text AS check
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname='public' AND p.prokind='f'
  AND  p.proname IN ('sppoultrycashflow_rows','spwatercashflow_rows',
                     'sppoultrycashflow_detail','spwatercashflow_detail')
ORDER  BY p.proname;

\echo
\echo === E. Sample: business date vs entry time, by leg ===
SELECT r.rowsource, r.transactiondate::date AS business_date, r.createdat AS entry_time
FROM farms f CROSS JOIN LATERAL public.sppoultrycashflow_rows(f.farmid, NULL, NULL) r
WHERE f.type='Poultry'
ORDER BY r.createdat DESC NULLS LAST LIMIT 8;

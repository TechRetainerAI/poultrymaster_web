-- Checks for 301_ReadersReturnCreatedAt.
--
-- Runs inside the dry-run transaction, after the migration body and after
-- readers-return-createdat.before.sql captured the baseline.
--
-- Every value is wrapped so a NULL cannot render the row blank -- a blank row
-- produces no "expect X got Y" text, which the runner would read as clean.

\pset footer off

\echo
\echo === A. Every reader still returns EXACTLY the same rows ===
-- The real risk in 301 is not the new column; it is that hand-reproducing a body
-- quietly changed a join or a filter. Row count AND a checksum of the
-- pre-existing columns must both be unchanged.
DO $verify$
DECLARE
    b     record;
    v_rows bigint;
    v_sum  text;
BEGIN
    FOR b IN SELECT * FROM before301 ORDER BY reader LOOP
        IF b.reader = 'speggproduction_getall' THEN
            SELECT COUNT(*), md5(string_agg(t.sig, '|' ORDER BY t.sig)) INTO v_rows, v_sum
            FROM farms f CROSS JOIN LATERAL public.speggproduction_getall(f.farmid) r
            CROSS JOIN LATERAL (SELECT r.productionid::text || ':' || COALESCE(r.productiondate::text,'') || ':'
                                    || COALESCE(r.totalproduction::text,'') AS sig) t;
        ELSIF b.reader = 'spfeedusage_getall' THEN
            SELECT COUNT(*), md5(string_agg(t.sig, '|' ORDER BY t.sig)) INTO v_rows, v_sum
            FROM farms f CROSS JOIN LATERAL public.spfeedusage_getall(NULL, f.farmid) r
            CROSS JOIN LATERAL (SELECT r.feedusageid::text || ':' || COALESCE(r.usagedate::text,'') || ':'
                                    || COALESCE(r.quantitykg::text,'') || ':' || COALESCE(r.source,'') AS sig) t;
        ELSIF b.reader = 'spflock_getall' THEN
            SELECT COUNT(*), md5(string_agg(t.sig, '|' ORDER BY t.sig)) INTO v_rows, v_sum
            FROM farms f CROSS JOIN LATERAL public.spflock_getall(f.farmid, NULL) r
            CROSS JOIN LATERAL (SELECT r.flockid::text || ':' || COALESCE(r.name,'') || ':'
                                    || COALESCE(r.quantity::text,'') || ':' || COALESCE(r.batchname,'') AS sig) t;
        ELSIF b.reader = 'sphouse_getall' THEN
            SELECT COUNT(*), md5(string_agg(t.sig, '|' ORDER BY t.sig)) INTO v_rows, v_sum
            FROM farms f CROSS JOIN LATERAL public.sphouse_getall(NULL, f.farmid) r
            CROSS JOIN LATERAL (SELECT r.houseid::text || ':' || COALESCE(r.housename,'') || ':'
                                    || COALESCE(r.capacity::text,'') AS sig) t;
        ELSIF b.reader = 'spinventoryitem_getall' THEN
            SELECT COUNT(*), md5(string_agg(t.sig, '|' ORDER BY t.sig)) INTO v_rows, v_sum
            FROM farms f CROSS JOIN LATERAL public.spinventoryitem_getall(NULL, f.farmid) r
            CROSS JOIN LATERAL (SELECT r.itemid::text || ':' || COALESCE(r.itemname,'') || ':'
                                    || COALESCE(r.quantityinstock::text,'') AS sig) t;
        ELSIF b.reader = 'spgenericbillingrun_getall' THEN
            SELECT COUNT(*), md5(COALESCE(string_agg(t.sig, '|' ORDER BY t.sig), '')) INTO v_rows, v_sum
            FROM farms f CROSS JOIN LATERAL public.spgenericbillingrun_getall(f.farmid) r
            CROSS JOIN LATERAL (SELECT r.genericbillingrunid::text || ':' || COALESCE(r.status,'') AS sig) t;
        ELSIF b.reader = 'spgenericownerentry_getall' THEN
            SELECT COUNT(*), md5(COALESCE(string_agg(t.sig, '|' ORDER BY t.sig), '')) INTO v_rows, v_sum
            FROM farms f CROSS JOIN LATERAL public.spgenericownerentry_getall(f.farmid, NULL, NULL, NULL) r
            CROSS JOIN LATERAL (SELECT r.genericownerentryid::text || ':' || COALESCE(r.amount::text,'') AS sig) t;
        ELSE
            SELECT COUNT(*), md5(COALESCE(string_agg(t.sig, '|' ORDER BY t.sig), '')) INTO v_rows, v_sum
            FROM farms f CROSS JOIN LATERAL public.spgenericstaffpayment_getall(f.farmid, NULL, NULL, NULL) r
            CROSS JOIN LATERAL (SELECT r.genericstaffpaymentid::text || ':' || COALESCE(r.amount::text,'') AS sig) t;
        END IF;

        RAISE NOTICE '% rows  expect % got %', b.reader, b.rows, v_rows;
        RAISE NOTICE '% values  expect % got %', b.reader,
            COALESCE(b.checksum,'(none)'), COALESCE(v_sum,'(none)');
    END LOOP;
END
$verify$;

\echo
\echo === B. Every reader now declares createdat ===
SELECT p.proname || '  expect yes got '
       || CASE WHEN pg_get_function_result(p.oid) ILIKE '%createdat%' THEN 'yes' ELSE 'no' END AS check
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.prokind = 'f'
  AND  p.proname IN ('speggproduction_getall','spfeedusage_getall','spflock_getall',
                     'spgenericbillingrun_getall','spgenericownerentry_getall',
                     'spgenericstaffpayment_getall','sphouse_getall','spinventoryitem_getall')
ORDER  BY p.proname;

\echo
\echo === C. createdat is actually populated, not just declared ===
-- A declared-but-always-NULL column would leave the tables exactly as they were,
-- which is the failure mode this whole migration exists to remove.
SELECT 'egg production rows missing createdat  expect 0 got '
       || COUNT(*) FILTER (WHERE r.createdat IS NULL)::text AS check
FROM farms f CROSS JOIN LATERAL public.speggproduction_getall(f.farmid) r;

SELECT 'feed usage rows missing createdat  expect 0 got '
       || COUNT(*) FILTER (WHERE r.createdat IS NULL)::text AS check
FROM farms f CROSS JOIN LATERAL public.spfeedusage_getall(NULL, f.farmid) r;

SELECT 'flock rows missing createdat  expect 0 got '
       || COUNT(*) FILTER (WHERE r.createdat IS NULL)::text AS check
FROM farms f CROSS JOIN LATERAL public.spflock_getall(f.farmid, NULL) r;

SELECT 'house rows missing createdat  expect 0 got '
       || COUNT(*) FILTER (WHERE r.createdat IS NULL)::text AS check
FROM farms f CROSS JOIN LATERAL public.sphouse_getall(NULL, f.farmid) r;

SELECT 'inventory rows missing createdat  expect 0 got '
       || COUNT(*) FILTER (WHERE r.createdat IS NULL)::text AS check
FROM farms f CROSS JOIN LATERAL public.spinventoryitem_getall(NULL, f.farmid) r;

\echo
\echo === D. The API role can still execute them ===
-- DROP FUNCTION takes its grants with it. Forgetting to reissue them would make
-- every one of these pages start failing with a permission error.
SELECT p.proname || '  expect true got '
       || has_function_privilege('poultryapp', p.oid, 'EXECUTE')::text AS check
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.prokind = 'f'
  AND  p.proname IN ('speggproduction_getall','spfeedusage_getall','spflock_getall',
                     'spgenericbillingrun_getall','spgenericownerentry_getall',
                     'spgenericstaffpayment_getall','sphouse_getall','spinventoryitem_getall')
ORDER  BY p.proname;

\echo
\echo === E. A sample of what the tables will now show ===
SELECT r.productiondate AS business_date, r.createdat AS entry_time
FROM farms f CROSS JOIN LATERAL public.speggproduction_getall(f.farmid) r
ORDER BY r.createdat DESC LIMIT 5;

-- Captured INSIDE the dry-run transaction, BEFORE 301 replaces the functions.
--
-- 301 drops and recreates eight readers. The risk is not that the new column is
-- wrong -- it is that reproducing a function body by hand quietly changes a
-- join, a filter or an ORDER BY and silently returns different rows. So the row
-- count and a checksum of the pre-existing columns are captured here, and the
-- checks compare them afterwards.
--
-- The checksum deliberately EXCLUDES the new column: it is built from the row's
-- text representation with the trailing createdat stripped, so "same rows, same
-- values, one extra field" passes and anything else fails.

CREATE TEMP TABLE before301(reader text, farms int, rows bigint, checksum text);

DO $before$
DECLARE
    v_rows bigint;
    v_sum  text;
    v_farms int;
BEGIN
    -- Egg production
    SELECT COUNT(*), COUNT(DISTINCT f.farmid), md5(string_agg(t.sig, '|' ORDER BY t.sig))
      INTO v_rows, v_farms, v_sum
    FROM farms f
    CROSS JOIN LATERAL public.speggproduction_getall(f.farmid) r
    CROSS JOIN LATERAL (SELECT r.productionid::text || ':' || COALESCE(r.productiondate::text,'') || ':'
                            || COALESCE(r.totalproduction::text,'') AS sig) t;
    INSERT INTO before301 VALUES ('speggproduction_getall', v_farms, v_rows, v_sum);

    -- Feed usage
    SELECT COUNT(*), COUNT(DISTINCT f.farmid), md5(string_agg(t.sig, '|' ORDER BY t.sig))
      INTO v_rows, v_farms, v_sum
    FROM farms f
    CROSS JOIN LATERAL public.spfeedusage_getall(NULL, f.farmid) r
    CROSS JOIN LATERAL (SELECT r.feedusageid::text || ':' || COALESCE(r.usagedate::text,'') || ':'
                            || COALESCE(r.quantitykg::text,'') || ':' || COALESCE(r.source,'') AS sig) t;
    INSERT INTO before301 VALUES ('spfeedusage_getall', v_farms, v_rows, v_sum);

    -- Flock
    SELECT COUNT(*), COUNT(DISTINCT f.farmid), md5(string_agg(t.sig, '|' ORDER BY t.sig))
      INTO v_rows, v_farms, v_sum
    FROM farms f
    CROSS JOIN LATERAL public.spflock_getall(f.farmid, NULL) r
    CROSS JOIN LATERAL (SELECT r.flockid::text || ':' || COALESCE(r.name,'') || ':'
                            || COALESCE(r.quantity::text,'') || ':' || COALESCE(r.batchname,'') AS sig) t;
    INSERT INTO before301 VALUES ('spflock_getall', v_farms, v_rows, v_sum);

    -- Houses
    SELECT COUNT(*), COUNT(DISTINCT f.farmid), md5(string_agg(t.sig, '|' ORDER BY t.sig))
      INTO v_rows, v_farms, v_sum
    FROM farms f
    CROSS JOIN LATERAL public.sphouse_getall(NULL, f.farmid) r
    CROSS JOIN LATERAL (SELECT r.houseid::text || ':' || COALESCE(r.housename,'') || ':'
                            || COALESCE(r.capacity::text,'') AS sig) t;
    INSERT INTO before301 VALUES ('sphouse_getall', v_farms, v_rows, v_sum);

    -- Inventory items
    SELECT COUNT(*), COUNT(DISTINCT f.farmid), md5(string_agg(t.sig, '|' ORDER BY t.sig))
      INTO v_rows, v_farms, v_sum
    FROM farms f
    CROSS JOIN LATERAL public.spinventoryitem_getall(NULL, f.farmid) r
    CROSS JOIN LATERAL (SELECT r.itemid::text || ':' || COALESCE(r.itemname,'') || ':'
                            || COALESCE(r.quantityinstock::text,'') AS sig) t;
    INSERT INTO before301 VALUES ('spinventoryitem_getall', v_farms, v_rows, v_sum);

    -- Generic billing runs
    SELECT COUNT(*), COUNT(DISTINCT f.farmid), md5(COALESCE(string_agg(t.sig, '|' ORDER BY t.sig), ''))
      INTO v_rows, v_farms, v_sum
    FROM farms f
    CROSS JOIN LATERAL public.spgenericbillingrun_getall(f.farmid) r
    CROSS JOIN LATERAL (SELECT r.genericbillingrunid::text || ':' || COALESCE(r.status,'') AS sig) t;
    INSERT INTO before301 VALUES ('spgenericbillingrun_getall', v_farms, v_rows, v_sum);

    -- Generic owner entries
    SELECT COUNT(*), COUNT(DISTINCT f.farmid), md5(COALESCE(string_agg(t.sig, '|' ORDER BY t.sig), ''))
      INTO v_rows, v_farms, v_sum
    FROM farms f
    CROSS JOIN LATERAL public.spgenericownerentry_getall(f.farmid, NULL, NULL, NULL) r
    CROSS JOIN LATERAL (SELECT r.genericownerentryid::text || ':' || COALESCE(r.amount::text,'') AS sig) t;
    INSERT INTO before301 VALUES ('spgenericownerentry_getall', v_farms, v_rows, v_sum);

    -- Generic staff payments
    SELECT COUNT(*), COUNT(DISTINCT f.farmid), md5(COALESCE(string_agg(t.sig, '|' ORDER BY t.sig), ''))
      INTO v_rows, v_farms, v_sum
    FROM farms f
    CROSS JOIN LATERAL public.spgenericstaffpayment_getall(f.farmid, NULL, NULL, NULL) r
    CROSS JOIN LATERAL (SELECT r.genericstaffpaymentid::text || ':' || COALESCE(r.amount::text,'') AS sig) t;
    INSERT INTO before301 VALUES ('spgenericstaffpayment_getall', v_farms, v_rows, v_sum);

    RAISE NOTICE 'baseline captured for % readers', (SELECT COUNT(*) FROM before301);
END
$before$;

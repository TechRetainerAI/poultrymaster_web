-- Baseline captured INSIDE the dry-run transaction, BEFORE 302 replaces the
-- cash flow readers.
--
-- These are eight-leg unions. The danger is not the new column -- it is that a
-- leg quietly stops matching, and the Cash Flow page then under- or over-reports
-- money. Row count, signed total and a checksum of the pre-existing columns are
-- all captured so the checks can prove none of that moved.

CREATE TEMP TABLE before302(reader text, rows bigint, total numeric, checksum text);

DO $before$
DECLARE
    v_rows bigint; v_total numeric; v_sum text;
BEGIN
    SELECT COUNT(*), COALESCE(SUM(r.amount),0), md5(COALESCE(string_agg(t.sig,'|' ORDER BY t.sig),''))
      INTO v_rows, v_total, v_sum
    FROM farms f CROSS JOIN LATERAL public.sppoultrycashflow_rows(f.farmid, NULL, NULL) r
    CROSS JOIN LATERAL (SELECT r.rowsource||':'||COALESCE(r.sourcerowid::text,'')||':'
                            ||COALESCE(r.amount::text,'')||':'||COALESCE(r.transactiondate::text,'')
                            ||':'||COALESCE(r.flowgroup,'') AS sig) t
    WHERE f.type='Poultry';
    INSERT INTO before302 VALUES ('sppoultrycashflow_rows', v_rows, v_total, v_sum);

    SELECT COUNT(*), COALESCE(SUM(r.amount),0), md5(COALESCE(string_agg(t.sig,'|' ORDER BY t.sig),''))
      INTO v_rows, v_total, v_sum
    FROM farms f CROSS JOIN LATERAL public.spwatercashflow_rows(f.farmid, NULL, NULL) r
    CROSS JOIN LATERAL (SELECT r.rowsource||':'||COALESCE(r.sourcerowid::text,'')||':'
                            ||COALESCE(r.amount::text,'')||':'||COALESCE(r.transactiondate::text,'')
                            ||':'||COALESCE(r.flowgroup,'') AS sig) t
    WHERE f.type='Water';
    INSERT INTO before302 VALUES ('spwatercashflow_rows', v_rows, v_total, v_sum);

    -- the wrappers add the category bucket, which the page groups by
    SELECT COUNT(*), COALESCE(SUM(r.amount),0), md5(COALESCE(string_agg(t.sig,'|' ORDER BY t.sig),''))
      INTO v_rows, v_total, v_sum
    FROM farms f CROSS JOIN LATERAL public.sppoultrycashflow_detail(f.farmid, NULL, NULL) r
    CROSS JOIN LATERAL (SELECT r.rowsource||':'||COALESCE(r.sourcerowid::text,'')||':'
                            ||COALESCE(r.amount::text,'')||':'||COALESCE(r.category,'') AS sig) t
    WHERE f.type='Poultry';
    INSERT INTO before302 VALUES ('sppoultrycashflow_detail', v_rows, v_total, v_sum);

    SELECT COUNT(*), COALESCE(SUM(r.amount),0), md5(COALESCE(string_agg(t.sig,'|' ORDER BY t.sig),''))
      INTO v_rows, v_total, v_sum
    FROM farms f CROSS JOIN LATERAL public.spwatercashflow_detail(f.farmid, NULL, NULL) r
    CROSS JOIN LATERAL (SELECT r.rowsource||':'||COALESCE(r.sourcerowid::text,'')||':'
                            ||COALESCE(r.amount::text,'')||':'||COALESCE(r.category,'') AS sig) t
    WHERE f.type='Water';
    INSERT INTO before302 VALUES ('spwatercashflow_detail', v_rows, v_total, v_sum);

    RAISE NOTICE 'baseline captured for % cash flow readers', (SELECT COUNT(*) FROM before302);
END
$before$;

-- 480: Stock Movements shows the Batch / Flock of rows posted by a production record.
-- Read-only: reads every company's stock list, writes nothing.
DO $$
DECLARE
    v_bad int;
    v_shown int;
BEGIN
    CREATE TEMP TABLE c480 ON COMMIT DROP AS
    SELECT r.*, x.flockid AS rawflockid, x.batchid AS rawbatchid
    FROM   (SELECT DISTINCT farmid FROM poultrystocktransactions) f
    CROSS  JOIN LATERAL sppoultrystock_gettransactions(f.farmid) r
    JOIN   poultrystocktransactions x ON x.poultrystocktransactionid = r.poultrystocktransactionid;

    -- 1. a production-posted row shows its record's flock, and that flock's batch
    SELECT count(*) INTO v_bad
    FROM   c480 c JOIN productionrecords pr ON pr.id = c.relatedid AND pr.farmid = c.farmid
    JOIN   flock fl ON fl.flockid = pr.flockid
    WHERE  c.manualmovementid IS NULL AND c.rawflockid IS NULL
      AND  c.txntype IN ('Production', 'Broken Egg Prod', 'Broken Egg Disposal', 'Mortality In', 'Mortality Disposal', 'Mortality')
      AND  (c.flockid IS DISTINCT FROM pr.flockid OR c.flockname IS DISTINCT FROM fl.name::text
            OR c.batchid IS DISTINCT FROM COALESCE(c.rawbatchid, fl.batchid));
    IF v_bad > 0 THEN RAISE EXCEPTION 'FAIL 480.1: % production row(s) do not show their record''s flock/batch', v_bad; END IF;
    SELECT count(*) INTO v_shown FROM c480 WHERE txntype = 'Production' AND rawflockid IS NULL AND flockid IS NOT NULL;
    RAISE NOTICE 'ok 480.1 production rows show their record''s flock and batch (% egg rows)', v_shown;

    -- 2. every other row keeps exactly the flock/batch stored on it
    SELECT count(*) INTO v_bad FROM c480
    WHERE  NOT (manualmovementid IS NULL AND rawflockid IS NULL
                AND txntype IN ('Production', 'Broken Egg Prod', 'Broken Egg Disposal', 'Mortality In', 'Mortality Disposal', 'Mortality'))
      AND  (flockid IS DISTINCT FROM rawflockid OR batchid IS DISTINCT FROM rawbatchid);
    IF v_bad > 0 THEN RAISE EXCEPTION 'FAIL 480.2: % other row(s) changed flock/batch', v_bad; END IF;
    RAISE NOTICE 'ok 480.2 every other row keeps its own flock/batch';

    -- 3. one row out per stock row
    SELECT (SELECT count(*) FROM poultrystocktransactions x JOIN poultryproducts p ON p.poultryproductid = x.poultryproductid)
         - (SELECT count(*) FROM c480) INTO v_bad;
    IF v_bad <> 0 THEN RAISE EXCEPTION 'FAIL 480.3: row count differs by %', v_bad; END IF;
    RAISE NOTICE 'ok 480.3 one row per stock transaction';

    RAISE NOTICE 'poultry 480: all checks passed';
END $$;

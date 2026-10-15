-- =============================================================================
-- sale-batch-attribution.test.sql -- checks for migration 366.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Posts throwaway
-- sales on the first farm that has a batch with a flock, inside a transaction
-- that is rolled back.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm    text;
    v_batch   integer;
    v_flock   integer;
    v_other   integer;
    v_sale    integer;
    v_b       integer;
    v_failed  boolean;
    v_row     record;
BEGIN
    SELECT f.farmid, f.batchid, f.flockid INTO v_farm, v_batch, v_flock
    FROM   flock f JOIN mainflockbatch b ON b.batchid = f.batchid AND b.farmid = f.farmid
    ORDER  BY f.flockid DESC LIMIT 1;
    IF v_farm IS NULL THEN RAISE NOTICE 'skip: no farm with a batch and a flock'; RETURN; END IF;
    SELECT b.batchid INTO v_other FROM mainflockbatch b
    WHERE  b.farmid = v_farm AND b.batchid <> v_batch ORDER BY b.batchid DESC LIMIT 1;

    -- 1. A flock fills in its batch.
    v_sale := spsale_insert(p_userid => 'check366', p_farmid => v_farm, p_saledate => CURRENT_DATE::timestamp,
                            p_product => 'Check 366', p_quantity => 1, p_unitprice => 1, p_totalamount => 1,
                            p_paymentmethod => NULL, p_customername => NULL, p_flockid => v_flock,
                            p_saledescription => 'check366', p_paid => FALSE);
    SELECT batchid INTO v_b FROM sale WHERE saleid = v_sale;
    IF v_b IS DISTINCT FROM v_batch THEN RAISE EXCEPTION 'FAIL 1: flock did not fill its batch (% vs %)', v_b, v_batch; END IF;
    RAISE NOTICE 'ok 1 a flock fills in its batch';

    -- 2. Its own transaction may set the same batch again; a different batch is refused.
    PERFORM sppoultrysale_setbatch(v_farm, ARRAY[v_sale], v_batch);
    IF v_other IS NOT NULL THEN
        v_failed := FALSE;
        BEGIN
            PERFORM sppoultrysale_setbatch(v_farm, ARRAY[v_sale], v_other);
        EXCEPTION WHEN raise_exception THEN v_failed := TRUE;
        END;
        IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2: a batch not matching the flock was accepted'; END IF;
    END IF;
    RAISE NOTICE 'ok 2 a batch that does not match the flock is refused';

    -- 3. A batch with no flock is kept; a batch from another farm is refused.
    v_sale := spsale_insert(p_userid => 'check366', p_farmid => v_farm, p_saledate => CURRENT_DATE::timestamp,
                            p_product => 'Check 366', p_quantity => 1, p_unitprice => 1, p_totalamount => 1,
                            p_paymentmethod => NULL, p_customername => NULL, p_flockid => NULL,
                            p_saledescription => 'check366', p_paid => FALSE);
    PERFORM sppoultrysale_setbatch(v_farm, ARRAY[v_sale], v_batch);
    SELECT batchid INTO v_b FROM sale WHERE saleid = v_sale;
    IF v_b IS DISTINCT FROM v_batch THEN RAISE EXCEPTION 'FAIL 3: batch-only attribution not kept'; END IF;
    v_failed := FALSE;
    BEGIN
        PERFORM sppoultrysale_setbatch(v_farm, ARRAY[v_sale],
            (SELECT b.batchid FROM mainflockbatch b WHERE b.farmid <> v_farm ORDER BY b.batchid LIMIT 1));
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE;
    END;
    IF NOT v_failed AND EXISTS (SELECT 1 FROM mainflockbatch b WHERE b.farmid <> v_farm) THEN
        RAISE EXCEPTION 'FAIL 3: a batch from another farm was accepted';
    END IF;
    RAISE NOTICE 'ok 3 batch-only sale kept; another farm''s batch refused';

    -- 4. Readers return the batch.
    SELECT * INTO v_row FROM spsale_getbyid(p_saleid => v_sale, p_farmid => v_farm);
    IF v_row.batchid IS DISTINCT FROM v_batch THEN RAISE EXCEPTION 'FAIL 4: spsale_getbyid batchid'; END IF;
    IF NOT EXISTS (SELECT 1 FROM spsale_getall(v_farm) g WHERE g.saleid = v_sale AND g.batchid = v_batch) THEN
        RAISE EXCEPTION 'FAIL 4: spsale_getall batchid';
    END IF;
    RAISE NOTICE 'ok 4 readers return the batch';

    -- 5. Once posted (a later transaction), the batch is fixed like the flock.
    PERFORM set_config('poultry.sale_fresh', '', true);
    v_failed := FALSE;
    BEGIN
        UPDATE sale SET batchid = NULL WHERE saleid = v_sale;
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE;
    END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5: a posted sale''s batch could be changed'; END IF;
    RAISE NOTICE 'ok 5 a posted sale''s batch cannot be changed';

    RAISE NOTICE 'sale batch attribution: all checks passed';
END $$;

ROLLBACK;

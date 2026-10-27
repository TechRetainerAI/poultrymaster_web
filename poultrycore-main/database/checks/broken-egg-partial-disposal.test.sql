-- =============================================================================
-- broken-egg-partial-disposal.test.sql -- checks for migration 386.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f).
-- Some of a record's broken eggs disposed at once, the rest kept in stock.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_r      record;
    v_b0     numeric;
    v_n      integer;
    v_failed boolean;
    v_bad    integer;

    c_disp CONSTANT text := 'Broken Egg Disposal';
BEGIN
    -- 0. Records untouched by 386 keep exactly what they had: the disposal
    --    posted for each matches the old Keep / Disposed rule.
    SELECT count(*) INTO v_bad
    FROM   productionrecords pr
    LEFT   JOIN poultrybyproductsettings s ON s.farmid = pr.farmid
    WHERE  pr.brokeneggsdisposed IS NULL
      AND  EXISTS (SELECT 1 FROM poultrystocktransactions t WHERE t.farmid = pr.farmid AND t.relatedid = pr.id AND t.txntype = 'Broken Egg Prod')
      AND  -COALESCE((SELECT sum(t.quantity) FROM poultrystocktransactions t
                      WHERE t.farmid = pr.farmid AND t.relatedid = pr.id AND t.txntype = c_disp), 0)
           <> fnpoultry_brokeneggsdisposed(pr.brokeneggs, NULL, pr.brokeneggdisposition,
                                           s.cutoverat IS NOT NULL AND pr.createdat < s.cutoverat);
    IF v_bad > 0 THEN RAISE EXCEPTION 'FAIL 0: % existing record(s) disagree with the 372 rule', v_bad; END IF;
    RAISE NOTICE 'ok 0 existing records: disposal unchanged';

    -- A tracked (post-cutover) record with at least 3 broken eggs, on an open flock.
    SELECT pr.farmid, pr.id, pr.brokeneggs INTO v_r
    FROM   productionrecords pr
    JOIN   poultrybyproductsettings s ON s.farmid = pr.farmid
    LEFT   JOIN flock f ON f.flockid = pr.flockid
    WHERE  pr.createdat >= s.cutoverat AND COALESCE(pr.brokeneggs, 0) >= 3
      AND  (f.flockid IS NULL OR (f.closeddate IS NULL AND COALESCE(f.active, TRUE)))
    ORDER  BY pr.id DESC LIMIT 1;
    IF v_r.id IS NULL THEN
        RAISE NOTICE 'broken egg partial disposal: all checks passed (no tracked record with broken eggs to edit)';
        RETURN;
    END IF;

    -- Some stock of our own (both byproducts: removing a record takes both off),
    -- so the oversell guard (real sales of this farm's stock) never decides a step. Rolled back with the rest.
    PERFORM sppoultrybyproduct_post(v_r.farmid, 'BrokenEggs', 'Breakage In', -386, 100000, NULL, 'check386 buffer', 'check386');
    PERFORM sppoultrybyproduct_post(v_r.farmid, 'DeadBirds', 'Hist Mortality In', -386, 100000, NULL, 'check386 buffer', 'check386');

    -- Start from Keep: all in stock.
    PERFORM sppoultryproduction_setdisposition(v_r.farmid, v_r.id, NULL, NULL, 'check386', 0);
    v_b0 := fnpoultry_byproductonhand(v_r.farmid, 'BrokenEggs');

    -- 1. Dispose 2 of them: 2 go out, the rest stay.
    PERFORM sppoultryproduction_setdisposition(v_r.farmid, v_r.id, NULL, NULL, 'check386', 2);
    SELECT COALESCE(sum(t.quantity), 0) INTO v_n FROM poultrystocktransactions t
    WHERE  t.farmid = v_r.farmid AND t.relatedid = v_r.id AND t.txntype = c_disp;
    IF v_n <> -2 THEN RAISE EXCEPTION 'FAIL 1a: disposal net % (expected -2)', v_n; END IF;
    IF fnpoultry_byproductonhand(v_r.farmid, 'BrokenEggs') <> v_b0 - 2 THEN
        RAISE EXCEPTION 'FAIL 1b: on hand did not fall by 2'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultryproduction_dispositions(v_r.farmid) d
                   WHERE d.id = v_r.id AND d.brokeneggsdisposed = 2 AND d.brokeneggdisposition = 'Disposed') THEN
        RAISE EXCEPTION 'FAIL 1c: reader does not show 2 disposed'; END IF;
    RAISE NOTICE 'ok 1 part disposed: 2 out, % kept', v_r.brokeneggs - 2;

    -- 2. Re-saving the same count posts nothing new.
    SELECT count(*) INTO v_n FROM poultrystocktransactions t WHERE t.farmid = v_r.farmid AND t.relatedid = v_r.id;
    PERFORM sppoultryproduction_setdisposition(v_r.farmid, v_r.id, NULL, NULL, 'check386', 2);
    PERFORM sppoultrybyproduct_syncforproduction(v_r.farmid, v_r.id, FALSE, 'check386');
    IF (SELECT count(*) FROM poultrystocktransactions t WHERE t.farmid = v_r.farmid AND t.relatedid = v_r.id) <> v_n THEN
        RAISE EXCEPTION 'FAIL 2: re-save posted rows'; END IF;
    RAISE NOTICE 'ok 2 re-save is a no-op';

    -- 3. More than recorded, or negative, is refused.
    v_failed := FALSE;
    BEGIN
        PERFORM sppoultryproduction_setdisposition(v_r.farmid, v_r.id, NULL, NULL, 'check386', v_r.brokeneggs + 1);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE;
    END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3a: more than recorded accepted'; END IF;
    v_failed := FALSE;
    BEGIN
        PERFORM sppoultryproduction_setdisposition(v_r.farmid, v_r.id, NULL, NULL, 'check386', -1);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE;
    END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3b: negative accepted'; END IF;
    RAISE NOTICE 'ok 3 over-count and negative refused';

    -- 4. An older client: Disposed = all, Keep = none.
    PERFORM sppoultryproduction_setdisposition(v_r.farmid, v_r.id, NULL, 'Disposed', 'check386');
    IF fnpoultry_byproductonhand(v_r.farmid, 'BrokenEggs') <> v_b0 - v_r.brokeneggs THEN
        RAISE EXCEPTION 'FAIL 4a: Disposed did not dispose all'; END IF;
    PERFORM sppoultryproduction_setdisposition(v_r.farmid, v_r.id, NULL, 'Keep', 'check386');
    IF fnpoultry_byproductonhand(v_r.farmid, 'BrokenEggs') <> v_b0 THEN
        RAISE EXCEPTION 'FAIL 4b: Keep did not keep all'; END IF;
    RAISE NOTICE 'ok 4 Keep / Disposed still mean none / all';

    -- 5. Broken eggs lowered below the disposed count: only what exists is disposed.
    PERFORM sppoultryproduction_setdisposition(v_r.farmid, v_r.id, NULL, NULL, 'check386', 3);
    IF fnpoultry_brokeneggsdisposed(2, 3, 'Disposed', FALSE) <> 2 THEN
        RAISE EXCEPTION 'FAIL 5: disposed not capped at broken eggs'; END IF;
    RAISE NOTICE 'ok 5 disposed capped at the broken eggs recorded';

    -- 6. Removing the record takes generation and disposal off together.
    PERFORM sppoultrybyproduct_syncforproduction(v_r.farmid, v_r.id, TRUE, 'check386');
    IF fnpoultry_byproductonhand(v_r.farmid, 'BrokenEggs') <> v_b0 - v_r.brokeneggs THEN
        RAISE EXCEPTION 'FAIL 6: removal left % on hand (expected %)',
            fnpoultry_byproductonhand(v_r.farmid, 'BrokenEggs'), v_b0 - v_r.brokeneggs; END IF;
    RAISE NOTICE 'ok 6 removal reverses the kept part only';

    RAISE NOTICE 'broken egg partial disposal: all checks passed';
END $$;

ROLLBACK;

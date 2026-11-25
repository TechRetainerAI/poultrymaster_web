-- =============================================================================
-- Checks for 484_Enock_GenericSalesListReversed (read only; run inside the
-- apply script's rolled-back transaction, or on its own -- it writes nothing).
--
-- For every Generic company:
--   484.1  the list returns every sale, and salereversalid matches the table
--   484.2  'Reversed' returns exactly the reversed sales
--   484.3  'Cancelled' returns cancelled sales that were NOT reversed
--   484.4  Reversed + Cancelled = everything with status 'Cancelled'
--   484.5  other statuses filter as before
-- =============================================================================
DO $$
DECLARE
  f record;
  v_all int; v_tab int; v_mismatch int;
  v_rev int; v_rev_tab int; v_can int; v_can_tab int; v_cancel_all int;
  v_appr int; v_appr_tab int;
  v_companies int := 0;
BEGIN
  FOR f IN SELECT DISTINCT farmid FROM genericsales WHERE isdeleted = FALSE LOOP
    v_companies := v_companies + 1;

    SELECT count(*) INTO v_all FROM spgenericsale_getall(f.farmid, NULL);
    SELECT count(*) INTO v_tab FROM genericsales WHERE farmid = f.farmid AND isdeleted = FALSE;
    IF v_all <> v_tab THEN RAISE EXCEPTION 'FAIL 484.1 %: list % rows, table %', f.farmid, v_all, v_tab; END IF;

    SELECT count(*) INTO v_mismatch
    FROM spgenericsale_getall(f.farmid, NULL) l
    JOIN genericsales s ON s.genericsaleid = l.genericsaleid
    WHERE l.salereversalid IS DISTINCT FROM s.salereversalid;
    IF v_mismatch <> 0 THEN RAISE EXCEPTION 'FAIL 484.1 %: % rows with the wrong salereversalid', f.farmid, v_mismatch; END IF;

    SELECT count(*) INTO v_rev FROM spgenericsale_getall(f.farmid, 'Reversed');
    SELECT count(*) INTO v_rev_tab FROM genericsales WHERE farmid = f.farmid AND isdeleted = FALSE AND salereversalid IS NOT NULL;
    IF v_rev <> v_rev_tab THEN RAISE EXCEPTION 'FAIL 484.2 %: Reversed % rows, expected %', f.farmid, v_rev, v_rev_tab; END IF;

    SELECT count(*) INTO v_can FROM spgenericsale_getall(f.farmid, 'Cancelled');
    SELECT count(*) INTO v_can_tab FROM genericsales WHERE farmid = f.farmid AND isdeleted = FALSE AND status = 'Cancelled' AND salereversalid IS NULL;
    IF v_can <> v_can_tab THEN RAISE EXCEPTION 'FAIL 484.3 %: Cancelled % rows, expected %', f.farmid, v_can, v_can_tab; END IF;

    SELECT count(*) INTO v_cancel_all FROM genericsales WHERE farmid = f.farmid AND isdeleted = FALSE AND status = 'Cancelled';
    IF v_rev + v_can <> v_cancel_all THEN
      RAISE EXCEPTION 'FAIL 484.4 %: Reversed % + Cancelled % <> % cancelled', f.farmid, v_rev, v_can, v_cancel_all;
    END IF;

    SELECT count(*) INTO v_appr FROM spgenericsale_getall(f.farmid, 'Approved');
    SELECT count(*) INTO v_appr_tab FROM genericsales WHERE farmid = f.farmid AND isdeleted = FALSE AND status = 'Approved';
    IF v_appr <> v_appr_tab THEN RAISE EXCEPTION 'FAIL 484.5 %: Approved % rows, expected %', f.farmid, v_appr, v_appr_tab; END IF;
  END LOOP;

  RAISE NOTICE 'ok 484.1-484.5 on % Generic companies', v_companies;
  RAISE NOTICE 'generic 484: all checks passed';
END $$;

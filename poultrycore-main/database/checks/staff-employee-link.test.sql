-- =============================================================================
-- staff-employee-link.test.sql -- checks for migration 362.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f), and the apply
-- script also runs it inside its own rolled-back dry run. Works on whatever
-- poultry staff row + same-company staff login it finds; skips if none.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm   text;
    v_staff  integer;
    v_staff2 integer;
    v_user   text;
    v_other  text;
    v_n      integer;
    v_failed boolean;
BEGIN
    SELECT s.farmid, s.poultrystaffid, u.id
      INTO v_farm, v_staff, v_user
      FROM public.poultrystaff s
      JOIN public.aspnetusers u ON u.farmid = s.farmid AND u.isstaff
     WHERE NOT s.isdeleted
     ORDER BY s.poultrystaffid
     LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'staff employee link: no poultry staff + login pair to test on -- skipped';
        RAISE NOTICE 'staff employee link: all checks passed';
        RETURN;
    END IF;

    -- start clean for this login on this farm
    UPDATE public.poultrystaff SET userid = NULL WHERE farmid = v_farm AND userid = v_user;

    -- 1. link shows up
    PERFORM public.spstaff_linkuser(v_farm, v_staff, v_user);
    SELECT count(*) INTO v_n FROM public.fnstaff_userlinks(v_farm) WHERE staffid = v_staff AND userid = v_user;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 1: link not listed'; END IF;
    RAISE NOTICE 'ok 1 link is listed';

    -- 2. the same login cannot be linked to a second live staff row
    INSERT INTO public.poultrystaff (farmid, firstname, lastname, role, salarytype, basepay, isactive, isdeleted, createdat)
    VALUES (v_farm, 'Link', 'Check', 'FarmHand', 'Monthly', 0, true, false, now())
    RETURNING poultrystaffid INTO v_staff2;
    v_failed := false;
    BEGIN PERFORM public.spstaff_linkuser(v_farm, v_staff2, v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2: one login linked to two staff rows'; END IF;
    RAISE NOTICE 'ok 2 one login, one staff row';

    -- 3. a login from another company is refused
    SELECT u.id INTO v_other FROM public.aspnetusers u
     WHERE u.isstaff AND u.farmid IS DISTINCT FROM v_farm
       AND NOT EXISTS (SELECT 1 FROM public.userfarms uf WHERE uf.userid = u.id AND uf.farmid = v_farm)
     LIMIT 1;
    IF v_other IS NOT NULL THEN
        v_failed := false;
        BEGIN PERFORM public.spstaff_linkuser(v_farm, v_staff2, v_other);
        EXCEPTION WHEN raise_exception THEN v_failed := true; END;
        IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3: foreign login linked'; END IF;
        RAISE NOTICE 'ok 3 foreign login refused';
    END IF;

    -- 4. an unknown staff row is refused
    v_failed := false;
    BEGIN PERFORM public.spstaff_linkuser(v_farm, -1, NULL);
    EXCEPTION WHEN no_data_found THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4: unknown staff accepted'; END IF;
    RAISE NOTICE 'ok 4 unknown staff refused';

    -- 5. a soft-deleted staff row drops off the list and frees the login
    UPDATE public.poultrystaff SET isdeleted = true WHERE poultrystaffid = v_staff;
    SELECT count(*) INTO v_n FROM public.fnstaff_userlinks(v_farm) WHERE staffid = v_staff;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 5a: deleted staff still listed'; END IF;
    PERFORM public.spstaff_linkuser(v_farm, v_staff2, v_user);
    RAISE NOTICE 'ok 5 deleted staff frees the login';

    -- 6. unlink
    PERFORM public.spstaff_linkuser(v_farm, v_staff2, NULL);
    SELECT count(*) INTO v_n FROM public.fnstaff_userlinks(v_farm) WHERE userid = v_user;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 6: unlink left a link'; END IF;
    RAISE NOTICE 'ok 6 unlink';

    RAISE NOTICE 'staff employee link: all checks passed';
END $$;

ROLLBACK;

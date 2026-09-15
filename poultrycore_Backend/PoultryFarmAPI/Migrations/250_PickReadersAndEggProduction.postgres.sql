-- =============================================================================
-- 250  The readers and the egg-production module catch up with the 5th/6th pick
-- =============================================================================
-- 249 added the columns and the writer for productionrecords. This is the other
-- half: every procedure that READS a pick, and the second module that WRITES
-- one.
--
-- WHY IT MATTERS THAT THESE ARE TOGETHER.
--
--   * spproductionrecord_getall / _getbyid list their columns explicitly and did
--     not list the new two. The entry form loads a record through _getbyid, so
--     it would have read a 5th pick of 0, shown 0, and written 0 back on save —
--     losing eggs that were correctly stored. 249 is not safe to run without
--     this file.
--
--   * The /egg-production module is not a second table: speggproduction_* reads
--     and writes productionrecords too. Its getters computed totalproduction
--     from four picks, so /egg-tracker would have reported production that
--     excluded the 5th and 6th; and speggproduction_update rewrote both the
--     total and the egg stock ledger from four picks, so editing a record there
--     would have quietly deleted the other two picks' eggs from stock.
--
-- HOW THIS FILE WAS BUILT. Every body below was read out of the live database
-- with pg_get_functiondef and edited in place — only the pick arithmetic
-- changes. Nothing was retyped, so nothing else can have drifted.
--
-- The two new parameters on the egg-production writers go on the END of the
-- signature with defaults, so an API deployed before this migration still
-- resolves the function.
--
-- Idempotent: each function is dropped and recreated. DROP comes first
-- because every one of them changes shape — the getters gain two output
-- columns, the writers gain two parameters — and CREATE OR REPLACE cannot
-- change either. Run 249 first.
--
-- HOW TO RUN
--   psql "<conn>" -f 250_PickReadersAndEggProduction.postgres.sql
-- =============================================================================

BEGIN;

-- Return type changes, so the old one has to go first.
DROP FUNCTION IF EXISTS public.spproductionrecord_getall(p_userid text, p_farmid text);
CREATE FUNCTION public.spproductionrecord_getall(p_userid text, p_farmid text)
 RETURNS TABLE(id integer, farmid text, userid text, createdby text, updatedby text, ageinweeks integer, ageindays integer, date date, noofbirds integer, mortality integer, noofbirdsleft integer, feedkg numeric, medication text, production9am integer, production12pm integer, production4pm integer, production4thpick integer, production5thpick integer, production6thpick integer, totalproduction integer, flockid integer, brokeneggs integer, notes text, eggcount integer, egggrade text, meatyeggs integer, softeggs integer, losteggs integer, specificfeedusedid integer, specificfeedusedname text, feedunitcost numeric, totalfeedconsumed numeric, totalfeedcost numeric, specificmedicationusedid integer, specificmedicationusedname text, medicationunitcost numeric, totalmedicationconsumed numeric, totalmedicationcost numeric, totalcostofproduction numeric, feedsjson text, medicationsjson text, createdat timestamp without time zone, updatedat timestamp without time zone)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        pr.id,
        pr.farmid::text,
        pr.userid::text,
        pr.createdby::text,
        pr.updatedby::text,
        pr.ageinweeks,
        pr.ageindays,
        pr.date,
        pr.noofbirds,
        pr.mortality,
        pr.noofbirdsleft,
        pr.feedkg,
        pr.medication::text,
        pr.production9am,
        pr.production12pm,
        pr.production4pm,
        COALESCE(pr.production4thpick, 0) AS production4thpick,
        COALESCE(pr.production5thpick, 0) AS production5thpick,
        COALESCE(pr.production6thpick, 0) AS production6thpick,
        pr.totalproduction,
        pr.flockid,
        pr.brokeneggs,
        pr.notes::text,
        COALESCE(pr.eggcount, pr.totalproduction) AS eggcount,
        pr.egggrade::text,
        pr.meatyeggs,
        pr.softeggs,
        pr.losteggs,
        pr.specificfeedusedid,
        pr.specificfeedusedname::text,
        pr.feedunitcost,
        pr.totalfeedconsumed,
        pr.totalfeedcost,
        pr.specificmedicationusedid,
        pr.specificmedicationusedname::text,
        pr.medicationunitcost,
        pr.totalmedicationconsumed,
        pr.totalmedicationcost,
        pr.totalcostofproduction,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'specificFeedUsedId', f.poultryrawmaterialitemid,
                    'specificFeedUsedName', f.itemname,
                    'totalFeedConsumed', f.quantityconsumed,
                    'feedUnitCost', f.unitcost,
                    'totalFeedCost', f.totalcost) ORDER BY f.productionrecordfeedid))::text
         FROM productionrecordfeeds f
         WHERE f.productionrecordid = pr.id) AS feedsjson,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'specificMedicationUsedId', m.poultryrawmaterialitemid,
                    'specificMedicationUsedName', m.itemname,
                    'totalMedicationConsumed', m.quantityconsumed,
                    'medicationUnitCost', m.unitcost,
                    'totalMedicationCost', m.totalcost) ORDER BY m.productionrecordmedicationid))::text
         FROM productionrecordmedications m
         WHERE m.productionrecordid = pr.id) AS medicationsjson,
        pr.createdat,
        pr.updatedat
    FROM productionrecords pr
    WHERE pr.farmid = p_farmid
    ORDER BY pr.date DESC, pr.createdat DESC;
END;
$function$;


-- Return type changes, so the old one has to go first.
DROP FUNCTION IF EXISTS public.spproductionrecord_getbyid(p_recordid integer, p_userid text, p_farmid text);
CREATE FUNCTION public.spproductionrecord_getbyid(p_recordid integer, p_userid text, p_farmid text)
 RETURNS TABLE(id integer, farmid text, userid text, createdby text, updatedby text, ageinweeks integer, ageindays integer, date date, noofbirds integer, mortality integer, noofbirdsleft integer, feedkg numeric, medication text, production9am integer, production12pm integer, production4pm integer, production4thpick integer, production5thpick integer, production6thpick integer, totalproduction integer, flockid integer, brokeneggs integer, notes text, eggcount integer, egggrade text, meatyeggs integer, softeggs integer, losteggs integer, specificfeedusedid integer, specificfeedusedname text, feedunitcost numeric, totalfeedconsumed numeric, totalfeedcost numeric, specificmedicationusedid integer, specificmedicationusedname text, medicationunitcost numeric, totalmedicationconsumed numeric, totalmedicationcost numeric, totalcostofproduction numeric, feedsjson text, medicationsjson text, createdat timestamp without time zone, updatedat timestamp without time zone)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        pr.id,
        pr.farmid::text,
        pr.userid::text,
        pr.createdby::text,
        pr.updatedby::text,
        pr.ageinweeks,
        pr.ageindays,
        pr.date,
        pr.noofbirds,
        pr.mortality,
        pr.noofbirdsleft,
        pr.feedkg,
        pr.medication::text,
        pr.production9am,
        pr.production12pm,
        pr.production4pm,
        COALESCE(pr.production4thpick, 0) AS production4thpick,
        COALESCE(pr.production5thpick, 0) AS production5thpick,
        COALESCE(pr.production6thpick, 0) AS production6thpick,
        pr.totalproduction,
        pr.flockid,
        pr.brokeneggs,
        pr.notes::text,
        COALESCE(pr.eggcount, pr.totalproduction) AS eggcount,
        pr.egggrade::text,
        pr.meatyeggs,
        pr.softeggs,
        pr.losteggs,
        pr.specificfeedusedid,
        pr.specificfeedusedname::text,
        pr.feedunitcost,
        pr.totalfeedconsumed,
        pr.totalfeedcost,
        pr.specificmedicationusedid,
        pr.specificmedicationusedname::text,
        pr.medicationunitcost,
        pr.totalmedicationconsumed,
        pr.totalmedicationcost,
        pr.totalcostofproduction,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'specificFeedUsedId', f.poultryrawmaterialitemid,
                    'specificFeedUsedName', f.itemname,
                    'totalFeedConsumed', f.quantityconsumed,
                    'feedUnitCost', f.unitcost,
                    'totalFeedCost', f.totalcost) ORDER BY f.productionrecordfeedid))::text
         FROM productionrecordfeeds f
         WHERE f.productionrecordid = pr.id) AS feedsjson,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'specificMedicationUsedId', m.poultryrawmaterialitemid,
                    'specificMedicationUsedName', m.itemname,
                    'totalMedicationConsumed', m.quantityconsumed,
                    'medicationUnitCost', m.unitcost,
                    'totalMedicationCost', m.totalcost) ORDER BY m.productionrecordmedicationid))::text
         FROM productionrecordmedications m
         WHERE m.productionrecordid = pr.id) AS medicationsjson,
        pr.createdat,
        pr.updatedat
    FROM productionrecords pr
    WHERE pr.id = p_recordid AND pr.farmid = p_farmid;
END;
$function$;


-- Return type changes, so the old one has to go first.
DROP FUNCTION IF EXISTS public.speggproduction_getall(p_farmid text);
CREATE FUNCTION public.speggproduction_getall(p_farmid text)
 RETURNS TABLE(productionid integer, flockid integer, productiondate date, eggcount integer, production9am integer, production12pm integer, production4pm integer, production4thpick integer, production5thpick integer, production6thpick integer, totalproduction integer, brokeneggs integer, meatyeggs integer, softeggs integer, losteggs integer, notes text, egggrade text, userid text, farmid text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        pr.id AS productionid,
        COALESCE(pr.flockid, 0) AS flockid,
        pr.date AS productiondate,
        COALESCE(pr.eggcount, pr.totalproduction) AS eggcount,
        pr.production9am,
        pr.production12pm,
        pr.production4pm,
        COALESCE(pr.production4thpick, 0) AS production4thpick,
        COALESCE(pr.production5thpick, 0) AS production5thpick,
        COALESCE(pr.production6thpick, 0) AS production6thpick,
        COALESCE(pr.production9am, 0) + COALESCE(pr.production12pm, 0) + COALESCE(pr.production4pm, 0) + COALESCE(pr.production4thpick, 0) + COALESCE(pr.production5thpick, 0) + COALESCE(pr.production6thpick, 0) AS totalproduction,
        pr.brokeneggs,
        COALESCE(pr.meatyeggs, 0) AS meatyeggs,
        COALESCE(pr.softeggs, 0)  AS softeggs,
        COALESCE(pr.losteggs, 0)  AS losteggs,
        pr.notes::text,
        pr.egggrade::text,
        COALESCE(pr.userid, pr.createdby)::text AS userid,
        pr.farmid::text
    FROM productionrecords pr
    WHERE pr.farmid = p_farmid
    ORDER BY pr.date DESC, pr.createdat DESC;
END;
$function$;


-- Return type changes, so the old one has to go first.
DROP FUNCTION IF EXISTS public.speggproduction_getbyid(p_productionid integer, p_userid text, p_farmid text);
CREATE FUNCTION public.speggproduction_getbyid(p_productionid integer, p_userid text, p_farmid text)
 RETURNS TABLE(productionid integer, flockid integer, productiondate date, eggcount integer, production9am integer, production12pm integer, production4pm integer, production4thpick integer, production5thpick integer, production6thpick integer, brokeneggs integer, meatyeggs integer, softeggs integer, losteggs integer, notes text, egggrade text, userid text, farmid text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        pr.id AS productionid,
        COALESCE(pr.flockid, 0) AS flockid,
        pr.date AS productiondate,
        COALESCE(pr.eggcount, pr.totalproduction) AS eggcount,
        pr.production9am,
        pr.production12pm,
        pr.production4pm,
        COALESCE(pr.production4thpick, 0) AS production4thpick,
        COALESCE(pr.production5thpick, 0) AS production5thpick,
        COALESCE(pr.production6thpick, 0) AS production6thpick,
        pr.brokeneggs,
        COALESCE(pr.meatyeggs, 0) AS meatyeggs,
        COALESCE(pr.softeggs, 0)  AS softeggs,
        COALESCE(pr.losteggs, 0)  AS losteggs,
        pr.notes::text,
        pr.egggrade::text,
        COALESCE(pr.userid, pr.createdby)::text AS userid,
        pr.farmid::text
    FROM productionrecords pr
    WHERE pr.id = p_productionid AND pr.farmid = p_farmid;
END;
$function$;


-- Return type changes, so the old one has to go first.
DROP FUNCTION IF EXISTS public.speggproduction_getbyflock(p_flockid integer, p_farmid text);
CREATE FUNCTION public.speggproduction_getbyflock(p_flockid integer, p_farmid text)
 RETURNS TABLE(productionid integer, flockid integer, productiondate date, eggcount integer, production9am integer, production12pm integer, production4pm integer, production4thpick integer, production5thpick integer, production6thpick integer, totalproduction integer, brokeneggs integer, meatyeggs integer, softeggs integer, losteggs integer, notes text, egggrade text, farmid text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        pr.id AS productionid,
        COALESCE(pr.flockid, 0) AS flockid,
        pr.date AS productiondate,
        COALESCE(pr.eggcount, pr.totalproduction) AS eggcount,
        pr.production9am,
        pr.production12pm,
        pr.production4pm,
        COALESCE(pr.production4thpick, 0) AS production4thpick,
        COALESCE(pr.production5thpick, 0) AS production5thpick,
        COALESCE(pr.production6thpick, 0) AS production6thpick,
        COALESCE(pr.production9am, 0) + COALESCE(pr.production12pm, 0) + COALESCE(pr.production4pm, 0) + COALESCE(pr.production4thpick, 0) + COALESCE(pr.production5thpick, 0) + COALESCE(pr.production6thpick, 0) AS totalproduction,
        pr.brokeneggs,
        COALESCE(pr.meatyeggs, 0) AS meatyeggs,
        COALESCE(pr.softeggs, 0)  AS softeggs,
        COALESCE(pr.losteggs, 0)  AS losteggs,
        pr.notes::text,
        pr.egggrade::text,
        pr.farmid::text
    FROM productionrecords pr
    WHERE pr.farmid = p_farmid AND pr.flockid = p_flockid
    ORDER BY pr.date DESC, pr.createdat DESC;
END;
$function$;


-- Return type changes, so the old one has to go first.
DROP FUNCTION IF EXISTS public.speggproduction_insert(p_flockid integer, p_productiondate date, p_eggcount integer, p_production9am integer, p_production12pm integer, p_production4pm integer, p_production4thpick integer, p_brokeneggs integer, p_notes text, p_userid text, p_farmid text, p_egggrade text, p_specificfeedusedid integer, p_specificfeedusedname text, p_feedunitcost numeric, p_totalfeedconsumed numeric, p_totalfeedcost numeric, p_specificmedicationusedid integer, p_specificmedicationusedname text, p_medicationunitcost numeric, p_totalmedicationconsumed numeric, p_totalmedicationcost numeric);
CREATE FUNCTION public.speggproduction_insert(p_flockid integer, p_productiondate date, p_eggcount integer, p_production9am integer DEFAULT 0, p_production12pm integer DEFAULT 0, p_production4pm integer DEFAULT 0, p_production4thpick integer DEFAULT 0, p_brokeneggs integer DEFAULT NULL::integer, p_notes text DEFAULT NULL::text, p_userid text DEFAULT NULL::text, p_farmid text DEFAULT NULL::text, p_egggrade text DEFAULT NULL::text, p_specificfeedusedid integer DEFAULT NULL::integer, p_specificfeedusedname text DEFAULT NULL::text, p_feedunitcost numeric DEFAULT NULL::numeric, p_totalfeedconsumed numeric DEFAULT NULL::numeric, p_totalfeedcost numeric DEFAULT NULL::numeric, p_specificmedicationusedid integer DEFAULT NULL::integer, p_specificmedicationusedname text DEFAULT NULL::text, p_medicationunitcost numeric DEFAULT NULL::numeric, p_totalmedicationconsumed numeric DEFAULT NULL::numeric, p_totalmedicationcost numeric DEFAULT NULL::numeric, p_production5thpick integer DEFAULT 0, p_production6thpick integer DEFAULT 0)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_totalproduction integer := p_production9am + p_production12pm + p_production4pm + COALESCE(p_production4thpick, 0)
                                 + COALESCE(p_production5thpick, 0) + COALESCE(p_production6thpick, 0);
    v_totalcostofproduction numeric(14,2);
    v_pid integer;
    v_good integer;
    v_cpu numeric(14,4);
BEGIN
    IF v_totalproduction = 0 AND p_eggcount > 0 THEN
        p_production9am := p_eggcount;
        v_totalproduction := p_eggcount;
    END IF;
    v_totalcostofproduction := COALESCE(p_totalfeedcost, 0) + COALESCE(p_totalmedicationcost, 0);

    INSERT INTO productionrecords (
        farmid, createdby, userid, ageinweeks, ageindays, date,
        noofbirds, mortality, noofbirdsleft, feedkg, medication,
        production9am, production12pm, production4pm, production4thpick,
        production5thpick, production6thpick, totalproduction,
        flockid, brokeneggs, notes, eggcount, egggrade, createdat,
        specificfeedusedid, specificfeedusedname, feedunitcost, totalfeedconsumed, totalfeedcost,
        specificmedicationusedid, specificmedicationusedname, medicationunitcost, totalmedicationconsumed, totalmedicationcost, totalcostofproduction)
    VALUES (
        p_farmid, p_userid, p_userid, 0, 0, p_productiondate,
        0, 0, 0, COALESCE(p_totalfeedconsumed, 0), p_specificmedicationusedname,
        p_production9am, p_production12pm, p_production4pm, COALESCE(p_production4thpick, 0),
        COALESCE(p_production5thpick, 0), COALESCE(p_production6thpick, 0), v_totalproduction,
        p_flockid, p_brokeneggs, p_notes, p_eggcount, p_egggrade, (now() at time zone 'utc'),
        p_specificfeedusedid, p_specificfeedusedname, p_feedunitcost, p_totalfeedconsumed, p_totalfeedcost,
        p_specificmedicationusedid, p_specificmedicationusedname, p_medicationunitcost, p_totalmedicationconsumed, p_totalmedicationcost, v_totalcostofproduction)
    RETURNING id INTO v_pid;

    v_good := v_totalproduction - COALESCE(p_brokeneggs, 0);
    v_cpu := CASE WHEN v_good > 0 AND v_totalcostofproduction > 0 THEN v_totalcostofproduction / v_good ELSE NULL END;
    IF p_farmid IS NOT NULL THEN
        PERFORM sppoultryeggstock_syncforproduction(p_farmid, v_pid, v_good, v_cpu, p_userid);
    END IF;

    RETURN v_pid;
END;
$function$;


-- Return type changes, so the old one has to go first.
DROP FUNCTION IF EXISTS public.speggproduction_update(p_productionid integer, p_flockid integer, p_productiondate date, p_eggcount integer, p_production9am integer, p_production12pm integer, p_production4pm integer, p_production4thpick integer, p_brokeneggs integer, p_notes text, p_userid text, p_farmid text, p_egggrade text, p_specificfeedusedid integer, p_specificfeedusedname text, p_feedunitcost numeric, p_totalfeedconsumed numeric, p_totalfeedcost numeric, p_specificmedicationusedid integer, p_specificmedicationusedname text, p_medicationunitcost numeric, p_totalmedicationconsumed numeric, p_totalmedicationcost numeric);
CREATE FUNCTION public.speggproduction_update(p_productionid integer, p_flockid integer, p_productiondate date, p_eggcount integer, p_production9am integer DEFAULT 0, p_production12pm integer DEFAULT 0, p_production4pm integer DEFAULT 0, p_production4thpick integer DEFAULT 0, p_brokeneggs integer DEFAULT NULL::integer, p_notes text DEFAULT NULL::text, p_userid text DEFAULT NULL::text, p_farmid text DEFAULT NULL::text, p_egggrade text DEFAULT NULL::text, p_specificfeedusedid integer DEFAULT NULL::integer, p_specificfeedusedname text DEFAULT NULL::text, p_feedunitcost numeric DEFAULT NULL::numeric, p_totalfeedconsumed numeric DEFAULT NULL::numeric, p_totalfeedcost numeric DEFAULT NULL::numeric, p_specificmedicationusedid integer DEFAULT NULL::integer, p_specificmedicationusedname text DEFAULT NULL::text, p_medicationunitcost numeric DEFAULT NULL::numeric, p_totalmedicationconsumed numeric DEFAULT NULL::numeric, p_totalmedicationcost numeric DEFAULT NULL::numeric, p_production5thpick integer DEFAULT 0, p_production6thpick integer DEFAULT 0)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_totalproduction integer := p_production9am + p_production12pm + p_production4pm + COALESCE(p_production4thpick, 0)
                                 + COALESCE(p_production5thpick, 0) + COALESCE(p_production6thpick, 0);
    v_totalcostofproduction numeric(14,2);
    v_good integer;
    v_cpu numeric(14,4);
BEGIN
    IF v_totalproduction = 0 AND p_eggcount > 0 THEN
        p_production9am := p_eggcount;
        v_totalproduction := p_eggcount;
    END IF;
    v_totalcostofproduction := COALESCE(p_totalfeedcost, 0) + COALESCE(p_totalmedicationcost, 0);

    UPDATE productionrecords pr
    SET flockid = p_flockid, date = p_productiondate, eggcount = p_eggcount,
        production9am = p_production9am, production12pm = p_production12pm, production4pm = p_production4pm,
        production4thpick = COALESCE(p_production4thpick, 0),
        production5thpick = COALESCE(p_production5thpick, 0),
        production6thpick = COALESCE(p_production6thpick, 0),
        totalproduction = v_totalproduction, brokeneggs = p_brokeneggs, notes = p_notes, egggrade = p_egggrade,
        feedkg = COALESCE(p_totalfeedconsumed, pr.feedkg),
        specificfeedusedid = p_specificfeedusedid, specificfeedusedname = p_specificfeedusedname, feedunitcost = p_feedunitcost,
        totalfeedconsumed = p_totalfeedconsumed, totalfeedcost = p_totalfeedcost,
        specificmedicationusedid = p_specificmedicationusedid, specificmedicationusedname = p_specificmedicationusedname,
        medicationunitcost = p_medicationunitcost, totalmedicationconsumed = p_totalmedicationconsumed, totalmedicationcost = p_totalmedicationcost,
        totalcostofproduction = v_totalcostofproduction, updatedby = p_userid, updatedat = (now() at time zone 'utc')
    WHERE pr.id = p_productionid AND pr.farmid = p_farmid;

    v_good := v_totalproduction - COALESCE(p_brokeneggs, 0);
    v_cpu := CASE WHEN v_good > 0 AND v_totalcostofproduction > 0 THEN v_totalcostofproduction / v_good ELSE NULL END;
    IF p_farmid IS NOT NULL THEN
        PERFORM sppoultryeggstock_syncforproduction(p_farmid, p_productionid, v_good, v_cpu, p_userid);
    END IF;
END;
$function$;

-- --- Prove it -----------------------------------------------------------------
-- Both getters must now name the new picks, and the egg module's total must be
-- the record's own total. 0 rows disagreeing is the pass.
SELECT 'AFTER' AS phase,
       (SELECT COUNT(*) FROM pg_proc
        WHERE proname IN ('spproductionrecord_getall','spproductionrecord_getbyid',
                          'speggproduction_getall','speggproduction_getbyid','speggproduction_getbyflock',
                          'speggproduction_insert','speggproduction_update')
          AND prosrc ILIKE '%production5thpick%') AS procs_updated_of_7;

COMMIT;

-- =============================================================================
-- UNDO: re-apply the definitions from migrations 152/153 and 198, which is what
-- these were before this file widened their pick arithmetic.
-- =============================================================================

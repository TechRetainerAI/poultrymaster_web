-- =============================================================================
-- 251  Batch production records carry a 5th and a 6th pick
-- =============================================================================
-- The last module still stopping at four. Unlike the single-flock record, a
-- batch pick is not one number: it is entered on the batch, SPLIT across the
-- flocks in an allocation, and then written onto a generated production record
-- per flock. All three steps have to learn the two new picks together, or a 5th
-- pick would be enterable on a batch and vanish before it reached a flock.
--
-- WHAT CHANGES
--   * productionbatchrecords  — crates / loose / total for the 5th and 6th.
--   * productionbatchallocations — fifthpickeggs, sixthpickeggs, the per-flock
--     share of each.
--   * _insert / _update  — six new parameters, on the end and defaulted.
--   * _getall / _getbyid — return the new columns.
--   * _saveallocation    — reads fifthPickEggs / sixthPickEggs from the JSON the
--     allocate page posts.
--   * _post              — the important one. It reconciles allocated eggs
--     against the batch totals before writing anything, so the new picks have to
--     be in BOTH sides of that check, and it now calls
--     spproductionrecord_setextrapicks on each generated record.
--
-- POSTING STAYS ALL-OR-NOTHING. The reconciliation is what stops a batch being
-- posted half-allocated; adding the picks to only one side of it would let a
-- batch through with eggs that never reach a flock.
--
-- Existing rows: the new columns default to 0, so a batch recorded before this
-- balances exactly as it did, and _post's check still passes on it.
--
-- Requires 249 (spproductionrecord_setextrapicks). Run that first.
--
-- HOW TO RUN
--   psql "<conn>" -f 251_BatchProductionFifthSixthPick.postgres.sql
-- =============================================================================

BEGIN;

-- --- 1. Columns ---------------------------------------------------------------
ALTER TABLE productionbatchrecords
    ADD COLUMN IF NOT EXISTS fifthpickcrates    INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS fifthpicklooseeggs INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS fifthpicktotal     INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS sixthpickcrates    INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS sixthpicklooseeggs INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS sixthpicktotal     INTEGER NOT NULL DEFAULT 0;

ALTER TABLE productionbatchallocations
    ADD COLUMN IF NOT EXISTS fifthpickeggs INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS sixthpickeggs INTEGER NOT NULL DEFAULT 0;

-- --- 2. Procedures -------------------------------------------------------------
-- Shape changes, so the old one has to go first.
DROP FUNCTION IF EXISTS public.spproductionbatchrecord_insert(p_farmid text, p_userid text, p_createdby text, p_batchselectiontype text, p_selectedbirdbatchid integer, p_batchname text, p_productiondate date, p_ageinweeks integer, p_ageindays integer, p_agedisplay text, p_firstpickcrates integer, p_firstpicklooseeggs integer, p_firstpicktotal integer, p_secondpickcrates integer, p_secondpicklooseeggs integer, p_secondpicktotal integer, p_thirdpickcrates integer, p_thirdpicklooseeggs integer, p_thirdpicktotal integer, p_fourthpickcrates integer, p_fourthpicklooseeggs integer, p_fourthpicktotal integer, p_brokeneggs integer, p_meatyeggs integer, p_softeggs integer, p_losteggs integer, p_totaleggs integer, p_feedkg numeric, p_deaths integer, p_birdsleft integer, p_egggrade text, p_feedtype text, p_medication text, p_totalfeedcost numeric, p_totalmedicationcost numeric, p_totalcostofproduction numeric, p_status text, p_notes text, p_includedflocksjson text, p_feedsjson text, p_medicationsjson text);
CREATE FUNCTION public.spproductionbatchrecord_insert(p_farmid text, p_userid text, p_createdby text, p_batchselectiontype text, p_selectedbirdbatchid integer DEFAULT NULL::integer, p_batchname text DEFAULT NULL::text, p_productiondate date DEFAULT NULL::date, p_ageinweeks integer DEFAULT NULL::integer, p_ageindays integer DEFAULT NULL::integer, p_agedisplay text DEFAULT NULL::text, p_firstpickcrates integer DEFAULT NULL::integer, p_firstpicklooseeggs integer DEFAULT NULL::integer, p_firstpicktotal integer DEFAULT 0, p_secondpickcrates integer DEFAULT NULL::integer, p_secondpicklooseeggs integer DEFAULT NULL::integer, p_secondpicktotal integer DEFAULT 0, p_thirdpickcrates integer DEFAULT NULL::integer, p_thirdpicklooseeggs integer DEFAULT NULL::integer, p_thirdpicktotal integer DEFAULT 0, p_fourthpickcrates integer DEFAULT NULL::integer, p_fourthpicklooseeggs integer DEFAULT NULL::integer, p_fourthpicktotal integer DEFAULT 0, p_brokeneggs integer DEFAULT NULL::integer, p_meatyeggs integer DEFAULT NULL::integer, p_softeggs integer DEFAULT NULL::integer, p_losteggs integer DEFAULT NULL::integer, p_totaleggs integer DEFAULT 0, p_feedkg numeric DEFAULT NULL::numeric, p_deaths integer DEFAULT 0, p_birdsleft integer DEFAULT NULL::integer, p_egggrade text DEFAULT NULL::text, p_feedtype text DEFAULT NULL::text, p_medication text DEFAULT NULL::text, p_totalfeedcost numeric DEFAULT NULL::numeric, p_totalmedicationcost numeric DEFAULT NULL::numeric, p_totalcostofproduction numeric DEFAULT NULL::numeric, p_status text DEFAULT 'PendingAllocation'::text, p_notes text DEFAULT NULL::text, p_includedflocksjson text DEFAULT NULL::text, p_feedsjson text DEFAULT NULL::text, p_medicationsjson text DEFAULT NULL::text,
    p_fifthpickcrates integer DEFAULT 0, p_fifthpicklooseeggs integer DEFAULT 0, p_fifthpicktotal integer DEFAULT 0,
    p_sixthpickcrates integer DEFAULT 0, p_sixthpicklooseeggs integer DEFAULT 0, p_sixthpicktotal integer DEFAULT 0)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_newid integer;
BEGIN
    INSERT INTO productionbatchrecords (
        farmid, userid, batchselectiontype, selectedbirdbatchid, batchname, productiondate,
        ageinweeks, ageindays, agedisplay,
        firstpickcrates, firstpicklooseeggs, firstpicktotal,
        secondpickcrates, secondpicklooseeggs, secondpicktotal,
        thirdpickcrates, thirdpicklooseeggs, thirdpicktotal,
        fourthpickcrates, fourthpicklooseeggs, fourthpicktotal,
        fifthpickcrates, fifthpicklooseeggs, fifthpicktotal,
        sixthpickcrates, sixthpicklooseeggs, sixthpicktotal,
        brokeneggs, meatyeggs, softeggs, losteggs, totaleggs,
        feedkg, deaths, birdsleft, egggrade, feedtype, medication,
        totalfeedcost, totalmedicationcost, totalcostofproduction, status, notes, createdby, createddate)
    VALUES (
        p_farmid, p_userid, p_batchselectiontype, p_selectedbirdbatchid, p_batchname, p_productiondate,
        p_ageinweeks, p_ageindays, p_agedisplay,
        p_firstpickcrates, p_firstpicklooseeggs, COALESCE(p_firstpicktotal, 0),
        p_secondpickcrates, p_secondpicklooseeggs, COALESCE(p_secondpicktotal, 0),
        p_thirdpickcrates, p_thirdpicklooseeggs, COALESCE(p_thirdpicktotal, 0),
        p_fourthpickcrates, p_fourthpicklooseeggs, COALESCE(p_fourthpicktotal, 0),
        COALESCE(p_fifthpickcrates,0), COALESCE(p_fifthpicklooseeggs,0), COALESCE(p_fifthpicktotal,0),
        COALESCE(p_sixthpickcrates,0), COALESCE(p_sixthpicklooseeggs,0), COALESCE(p_sixthpicktotal,0),
        p_brokeneggs, p_meatyeggs, p_softeggs, p_losteggs, COALESCE(p_totaleggs, 0),
        p_feedkg, COALESCE(p_deaths, 0), p_birdsleft, p_egggrade, p_feedtype, p_medication,
        p_totalfeedcost, p_totalmedicationcost, p_totalcostofproduction, COALESCE(p_status, 'PendingAllocation'),
        p_notes, p_createdby, (now() AT TIME ZONE 'utc'))
    RETURNING id INTO v_newid;

    PERFORM spproductionbatchrecord_replacechildren(
        p_batchid            => v_newid,
        p_createdby          => p_createdby,
        p_includedflocksjson => p_includedflocksjson,
        p_feedsjson          => p_feedsjson,
        p_medicationsjson    => p_medicationsjson);

    RETURN v_newid;
END;
$function$;

-- Shape changes, so the old one has to go first.
DROP FUNCTION IF EXISTS public.spproductionbatchrecord_update(p_id integer, p_updatedby text, p_batchselectiontype text, p_selectedbirdbatchid integer, p_batchname text, p_productiondate date, p_ageinweeks integer, p_ageindays integer, p_agedisplay text, p_firstpickcrates integer, p_firstpicklooseeggs integer, p_firstpicktotal integer, p_secondpickcrates integer, p_secondpicklooseeggs integer, p_secondpicktotal integer, p_thirdpickcrates integer, p_thirdpicklooseeggs integer, p_thirdpicktotal integer, p_fourthpickcrates integer, p_fourthpicklooseeggs integer, p_fourthpicktotal integer, p_brokeneggs integer, p_meatyeggs integer, p_softeggs integer, p_losteggs integer, p_totaleggs integer, p_feedkg numeric, p_deaths integer, p_birdsleft integer, p_egggrade text, p_feedtype text, p_medication text, p_totalfeedcost numeric, p_totalmedicationcost numeric, p_totalcostofproduction numeric, p_status text, p_notes text, p_includedflocksjson text, p_feedsjson text, p_medicationsjson text);
CREATE FUNCTION public.spproductionbatchrecord_update(p_id integer, p_updatedby text, p_batchselectiontype text, p_selectedbirdbatchid integer DEFAULT NULL::integer, p_batchname text DEFAULT NULL::text, p_productiondate date DEFAULT NULL::date, p_ageinweeks integer DEFAULT NULL::integer, p_ageindays integer DEFAULT NULL::integer, p_agedisplay text DEFAULT NULL::text, p_firstpickcrates integer DEFAULT NULL::integer, p_firstpicklooseeggs integer DEFAULT NULL::integer, p_firstpicktotal integer DEFAULT 0, p_secondpickcrates integer DEFAULT NULL::integer, p_secondpicklooseeggs integer DEFAULT NULL::integer, p_secondpicktotal integer DEFAULT 0, p_thirdpickcrates integer DEFAULT NULL::integer, p_thirdpicklooseeggs integer DEFAULT NULL::integer, p_thirdpicktotal integer DEFAULT 0, p_fourthpickcrates integer DEFAULT NULL::integer, p_fourthpicklooseeggs integer DEFAULT NULL::integer, p_fourthpicktotal integer DEFAULT 0, p_brokeneggs integer DEFAULT NULL::integer, p_meatyeggs integer DEFAULT NULL::integer, p_softeggs integer DEFAULT NULL::integer, p_losteggs integer DEFAULT NULL::integer, p_totaleggs integer DEFAULT 0, p_feedkg numeric DEFAULT NULL::numeric, p_deaths integer DEFAULT 0, p_birdsleft integer DEFAULT NULL::integer, p_egggrade text DEFAULT NULL::text, p_feedtype text DEFAULT NULL::text, p_medication text DEFAULT NULL::text, p_totalfeedcost numeric DEFAULT NULL::numeric, p_totalmedicationcost numeric DEFAULT NULL::numeric, p_totalcostofproduction numeric DEFAULT NULL::numeric, p_status text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_includedflocksjson text DEFAULT NULL::text, p_feedsjson text DEFAULT NULL::text, p_medicationsjson text DEFAULT NULL::text,
    p_fifthpickcrates integer DEFAULT 0, p_fifthpicklooseeggs integer DEFAULT 0, p_fifthpicktotal integer DEFAULT 0,
    p_sixthpickcrates integer DEFAULT 0, p_sixthpicklooseeggs integer DEFAULT 0, p_sixthpicktotal integer DEFAULT 0)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_curstatus text;
BEGIN
    SELECT r.status INTO v_curstatus
    FROM productionbatchrecords r
    WHERE r.id = p_id
    FOR UPDATE;

    IF v_curstatus IS NULL THEN
        RAISE EXCEPTION 'Batch production record not found.';
    END IF;
    IF v_curstatus IN ('Posted', 'Cancelled') THEN
        RAISE EXCEPTION 'A posted or cancelled batch cannot be edited. Reverse a posted batch first.';
    END IF;

    UPDATE productionbatchrecords r
    SET batchselectiontype = p_batchselectiontype,
        selectedbirdbatchid = p_selectedbirdbatchid,
        batchname = p_batchname,
        productiondate = p_productiondate,
        ageinweeks = p_ageinweeks,
        ageindays = p_ageindays,
        agedisplay = p_agedisplay,
        firstpickcrates = p_firstpickcrates,
        firstpicklooseeggs = p_firstpicklooseeggs,
        firstpicktotal = COALESCE(p_firstpicktotal, 0),
        secondpickcrates = p_secondpickcrates,
        secondpicklooseeggs = p_secondpicklooseeggs,
        secondpicktotal = COALESCE(p_secondpicktotal, 0),
        thirdpickcrates = p_thirdpickcrates,
        thirdpicklooseeggs = p_thirdpicklooseeggs,
        thirdpicktotal = COALESCE(p_thirdpicktotal, 0),
        fourthpickcrates = p_fourthpickcrates,
        fourthpicklooseeggs = p_fourthpicklooseeggs,
        fourthpicktotal = COALESCE(p_fourthpicktotal, 0),
        fifthpickcrates = COALESCE(p_fifthpickcrates,0),
        fifthpicklooseeggs = COALESCE(p_fifthpicklooseeggs,0),
        fifthpicktotal = COALESCE(p_fifthpicktotal,0),
        sixthpickcrates = COALESCE(p_sixthpickcrates,0),
        sixthpicklooseeggs = COALESCE(p_sixthpicklooseeggs,0),
        sixthpicktotal = COALESCE(p_sixthpicktotal,0),
        brokeneggs = p_brokeneggs,
        meatyeggs = p_meatyeggs,
        softeggs = p_softeggs,
        losteggs = p_losteggs,
        totaleggs = COALESCE(p_totaleggs, 0),
        feedkg = p_feedkg,
        deaths = COALESCE(p_deaths, 0),
        birdsleft = p_birdsleft,
        egggrade = p_egggrade,
        feedtype = p_feedtype,
        medication = p_medication,
        totalfeedcost = p_totalfeedcost,
        totalmedicationcost = p_totalmedicationcost,
        totalcostofproduction = p_totalcostofproduction,
        status = COALESCE(p_status, r.status),
        notes = p_notes,
        updatedby = p_updatedby,
        updateddate = (now() at time zone 'utc')
    WHERE r.id = p_id;

    PERFORM spproductionbatchrecord_replacechildren(
        p_id, p_updatedby, p_includedflocksjson, p_feedsjson, p_medicationsjson);
END;
$function$;

-- Shape changes, so the old one has to go first.
DROP FUNCTION IF EXISTS public.spproductionbatchrecord_getall(p_userid text, p_farmid text);
CREATE FUNCTION public.spproductionbatchrecord_getall(p_userid text, p_farmid text)
 RETURNS TABLE(id integer, farmid text, userid text, batchselectiontype text, selectedbirdbatchid integer, batchname text, productiondate date, ageinweeks integer, ageindays integer, agedisplay text, firstpickcrates integer, firstpicklooseeggs integer, firstpicktotal integer, secondpickcrates integer, secondpicklooseeggs integer, secondpicktotal integer, thirdpickcrates integer, thirdpicklooseeggs integer, thirdpicktotal integer, fourthpickcrates integer, fourthpicklooseeggs integer, fourthpicktotal integer, fifthpickcrates integer, fifthpicklooseeggs integer, fifthpicktotal integer, sixthpickcrates integer, sixthpicklooseeggs integer, sixthpicktotal integer, brokeneggs integer, meatyeggs integer, softeggs integer, losteggs integer, totaleggs integer, feedkg numeric, deaths integer, birdsleft integer, egggrade text, totalfeedcost numeric, totalmedicationcost numeric, totalcostofproduction numeric, status text, notes text, createdby text, createddate timestamp without time zone, updatedby text, updateddate timestamp without time zone, postedby text, posteddate timestamp without time zone, postingversion integer, feedtype text, medication text, includedflocksjson text, feedsjson text, medicationsjson text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        r.id,
        r.farmid::text,
        r.userid::text,
        r.batchselectiontype::text,
        r.selectedbirdbatchid,
        r.batchname::text,
        r.productiondate,
        r.ageinweeks,
        r.ageindays,
        r.agedisplay::text,
        r.firstpickcrates,
        r.firstpicklooseeggs,
        r.firstpicktotal,
        r.secondpickcrates,
        r.secondpicklooseeggs,
        r.secondpicktotal,
        r.thirdpickcrates,
        r.thirdpicklooseeggs,
        r.thirdpicktotal,
        r.fourthpickcrates,
        r.fourthpicklooseeggs,
        r.fourthpicktotal,
        COALESCE(r.fifthpickcrates,0),
        COALESCE(r.fifthpicklooseeggs,0),
        COALESCE(r.fifthpicktotal,0),
        COALESCE(r.sixthpickcrates,0),
        COALESCE(r.sixthpicklooseeggs,0),
        COALESCE(r.sixthpicktotal,0),
        r.brokeneggs,
        r.meatyeggs,
        r.softeggs,
        r.losteggs,
        r.totaleggs,
        r.feedkg,
        r.deaths,
        r.birdsleft,
        r.egggrade::text,
        r.totalfeedcost,
        r.totalmedicationcost,
        r.totalcostofproduction,
        r.status::text,
        r.notes::text,
        r.createdby::text,
        r.createddate,
        r.updatedby::text,
        r.updateddate,
        r.postedby::text,
        r.posteddate,
        r.postingversion,
        r.feedtype::text,
        r.medication::text,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'flockId', f.flockid,
                    'flockName', f.flockname,
                    'birdBatchId', f.birdbatchid) ORDER BY f.id))::text
         FROM productionbatchincludedflocks f
         WHERE f.productionbatchrecordid = r.id) AS includedflocksjson,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'itemId', u.inventoryitemid,
                    'itemName', u.itemname,
                    'qty', u.quantityused) ORDER BY u.id))::text
         FROM productionbatchfeedusage u
         WHERE u.productionbatchrecordid = r.id) AS feedsjson,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'itemId', u.inventoryitemid,
                    'itemName', u.itemname,
                    'qty', u.quantityused) ORDER BY u.id))::text
         FROM productionbatchmedicationusage u
         WHERE u.productionbatchrecordid = r.id) AS medicationsjson
    FROM productionbatchrecords r
    WHERE r.farmid = p_farmid
    ORDER BY r.productiondate DESC, r.createddate DESC;
END;
$function$;

-- Shape changes, so the old one has to go first.
DROP FUNCTION IF EXISTS public.spproductionbatchrecord_getbyid(p_id integer, p_farmid text);
CREATE FUNCTION public.spproductionbatchrecord_getbyid(p_id integer, p_farmid text)
 RETURNS TABLE(id integer, farmid text, userid text, batchselectiontype text, selectedbirdbatchid integer, batchname text, productiondate date, ageinweeks integer, ageindays integer, agedisplay text, firstpickcrates integer, firstpicklooseeggs integer, firstpicktotal integer, secondpickcrates integer, secondpicklooseeggs integer, secondpicktotal integer, thirdpickcrates integer, thirdpicklooseeggs integer, thirdpicktotal integer, fourthpickcrates integer, fourthpicklooseeggs integer, fourthpicktotal integer, fifthpickcrates integer, fifthpicklooseeggs integer, fifthpicktotal integer, sixthpickcrates integer, sixthpicklooseeggs integer, sixthpicktotal integer, brokeneggs integer, meatyeggs integer, softeggs integer, losteggs integer, totaleggs integer, feedkg numeric, deaths integer, birdsleft integer, egggrade text, totalfeedcost numeric, totalmedicationcost numeric, totalcostofproduction numeric, status text, notes text, createdby text, createddate timestamp without time zone, updatedby text, updateddate timestamp without time zone, postedby text, posteddate timestamp without time zone, postingversion integer, feedtype text, medication text, includedflocksjson text, feedsjson text, medicationsjson text, allocationsjson text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        r.id,
        r.farmid::text,
        r.userid::text,
        r.batchselectiontype::text,
        r.selectedbirdbatchid,
        r.batchname::text,
        r.productiondate,
        r.ageinweeks,
        r.ageindays,
        r.agedisplay::text,
        r.firstpickcrates,
        r.firstpicklooseeggs,
        r.firstpicktotal,
        r.secondpickcrates,
        r.secondpicklooseeggs,
        r.secondpicktotal,
        r.thirdpickcrates,
        r.thirdpicklooseeggs,
        r.thirdpicktotal,
        r.fourthpickcrates,
        r.fourthpicklooseeggs,
        r.fourthpicktotal,
        COALESCE(r.fifthpickcrates,0),
        COALESCE(r.fifthpicklooseeggs,0),
        COALESCE(r.fifthpicktotal,0),
        COALESCE(r.sixthpickcrates,0),
        COALESCE(r.sixthpicklooseeggs,0),
        COALESCE(r.sixthpicktotal,0),
        r.brokeneggs,
        r.meatyeggs,
        r.softeggs,
        r.losteggs,
        r.totaleggs,
        r.feedkg,
        r.deaths,
        r.birdsleft,
        r.egggrade::text,
        r.totalfeedcost,
        r.totalmedicationcost,
        r.totalcostofproduction,
        r.status::text,
        r.notes::text,
        r.createdby::text,
        r.createddate,
        r.updatedby::text,
        r.updateddate,
        r.postedby::text,
        r.posteddate,
        r.postingversion,
        r.feedtype::text,
        r.medication::text,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'flockId', f.flockid,
                    'flockName', f.flockname,
                    'birdBatchId', f.birdbatchid) ORDER BY f.id))::text
         FROM productionbatchincludedflocks f
         WHERE f.productionbatchrecordid = r.id) AS includedflocksjson,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'id', u.id,
                    'itemId', u.inventoryitemid,
                    'itemName', u.itemname,
                    'qty', u.quantityused,
                    'unitCost', u.unitcost,
                    'totalCost', u.totalcost,
                    'method', u.costingmethod) ORDER BY u.id))::text
         FROM productionbatchfeedusage u
         WHERE u.productionbatchrecordid = r.id) AS feedsjson,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'id', u.id,
                    'itemId', u.inventoryitemid,
                    'itemName', u.itemname,
                    'qty', u.quantityused,
                    'unitCost', u.unitcost,
                    'totalCost', u.totalcost,
                    'method', u.costingmethod) ORDER BY u.id))::text
         FROM productionbatchmedicationusage u
         WHERE u.productionbatchrecordid = r.id) AS medicationsjson,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'id', a.id,
                    'flockId', a.flockid,
                    'flockName', a.flockname,
                    'allocationMethod', a.allocationmethod,
                    'ageInWeeks', a.ageinweeks,
                    'ageInDays', a.ageindays,
                    'birdsBefore', a.birdsbefore,
                    'deaths', a.deaths,
                    'birdsAfter', a.birdsafter,
                    'firstPickEggs', a.firstpickeggs,
                    'secondPickEggs', a.secondpickeggs,
                    'thirdPickEggs', a.thirdpickeggs,
                    'fourthPickEggs', a.fourthpickeggs,
                    'fifthPickEggs', COALESCE(a.fifthpickeggs, 0),
                    'sixthPickEggs', COALESCE(a.sixthpickeggs, 0),
                    'brokenEggs', a.brokeneggs,
                    'meatyEggs', a.meatyeggs,
                    'softEggs', a.softeggs,
                    'lostEggs', a.losteggs,
                    'totalEggs', a.totaleggs,
                    'eggPercentage', a.eggpercentage,
                    'feedKg', a.feedkg,
                    'totalFeedCost', a.totalfeedcost,
                    'totalMedicationCost', a.totalmedicationcost,
                    'totalCostOfProduction', a.totalcostofproduction,
                    'notes', a.notes,
                    'generatedProductionRecordId', a.generatedproductionrecordid,
                    'feeds', (SELECT json_agg(json_build_object(
                                    'batchUsageId', fu.productionbatchfeedusageid,
                                    'itemId', fu.inventoryitemid,
                                    'itemName', fu.itemname,
                                    'qty', fu.quantityallocated,
                                    'unitCost', fu.unitcost,
                                    'totalCost', fu.totalcost) ORDER BY fu.id)
                              FROM productionbatchallocationfeedusage fu
                              WHERE fu.productionbatchallocationid = a.id),
                    'medications', (SELECT json_agg(json_build_object(
                                    'batchUsageId', mu.productionbatchmedicationusageid,
                                    'itemId', mu.inventoryitemid,
                                    'itemName', mu.itemname,
                                    'qty', mu.quantityallocated,
                                    'unitCost', mu.unitcost,
                                    'totalCost', mu.totalcost) ORDER BY mu.id)
                              FROM productionbatchallocationmedicationusage mu
                              WHERE mu.productionbatchallocationid = a.id)
                 ) ORDER BY a.id))::text
         FROM productionbatchallocations a
         WHERE a.productionbatchrecordid = r.id) AS allocationsjson
    FROM productionbatchrecords r
    WHERE r.id = p_id AND r.farmid = p_farmid;
END;
$function$;

-- Shape changes, so the old one has to go first.
DROP FUNCTION IF EXISTS public.spproductionbatchrecord_saveallocation(p_id integer, p_farmid text, p_updatedby text, p_allocationsjson text, p_status text);
CREATE FUNCTION public.spproductionbatchrecord_saveallocation(p_id integer, p_farmid text, p_updatedby text, p_allocationsjson text, p_status text DEFAULT 'Allocated'::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_curstatus text;
    v_p         jsonb;
    v_allocid   integer;
BEGIN
    SELECT r.status INTO v_curstatus
    FROM productionbatchrecords r
    WHERE r.id = p_id AND r.farmid = p_farmid
    FOR UPDATE;

    IF v_curstatus IS NULL THEN
        RAISE EXCEPTION 'Batch production record not found.';
    END IF;
    IF v_curstatus IN ('Posted', 'Cancelled') THEN
        RAISE EXCEPTION 'Allocation cannot be edited for a posted or cancelled batch. Reverse a posted batch first.';
    END IF;

    DELETE FROM productionbatchallocations pa
    WHERE pa.productionbatchrecordid = p_id;  -- cascades feed/med

    IF p_allocationsjson IS NOT NULL AND length(p_allocationsjson) > 0 THEN
        FOR v_p IN
            SELECT e.value
            FROM jsonb_array_elements(p_allocationsjson::jsonb) WITH ORDINALITY AS e(value, ord)
            ORDER BY e.ord
        LOOP
            INSERT INTO productionbatchallocations (
                productionbatchrecordid, flockid, flockname, allocationmethod, ageinweeks, ageindays,
                birdsbefore, deaths, birdsafter, firstpickeggs, secondpickeggs, thirdpickeggs, fourthpickeggs, fifthpickeggs, sixthpickeggs,
                brokeneggs, meatyeggs, softeggs, losteggs, totaleggs, eggpercentage, feedkg,
                totalfeedcost, totalmedicationcost, totalcostofproduction, notes, createdby, createddate)
            VALUES (
                p_id,
                (v_p->>'flockId')::integer,
                (v_p->>'flockName')::varchar(150),
                (v_p->>'allocationMethod')::varchar(30),
                (v_p->>'ageInWeeks')::integer,
                (v_p->>'ageInDays')::integer,
                (v_p->>'birdsBefore')::integer,
                COALESCE((v_p->>'deaths')::integer, 0),
                (v_p->>'birdsAfter')::integer,
                COALESCE((v_p->>'firstPickEggs')::integer, 0),
                COALESCE((v_p->>'secondPickEggs')::integer, 0),
                COALESCE((v_p->>'thirdPickEggs')::integer, 0),
                COALESCE((v_p->>'fourthPickEggs')::integer, 0),
                COALESCE((v_p->>'fifthPickEggs')::integer, 0),
                COALESCE((v_p->>'sixthPickEggs')::integer, 0),
                (v_p->>'brokenEggs')::integer,
                (v_p->>'meatyEggs')::integer,
                (v_p->>'softEggs')::integer,
                (v_p->>'lostEggs')::integer,
                COALESCE((v_p->>'totalEggs')::integer, 0),
                (v_p->>'eggPercentage')::numeric(9,2),
                (v_p->>'feedKg')::numeric(18,2),
                (v_p->>'totalFeedCost')::numeric(14,2),
                (v_p->>'totalMedicationCost')::numeric(14,2),
                (v_p->>'totalCostOfProduction')::numeric(14,2),
                (v_p->>'notes'),
                p_updatedby,
                (now() at time zone 'utc'))
            RETURNING id INTO v_allocid;

            INSERT INTO productionbatchallocationfeedusage (
                productionbatchallocationid, productionbatchfeedusageid, inventoryitemid, itemname,
                quantityallocated, unitcost, totalcost, createdby)
            SELECT v_allocid,
                   (f.value->>'batchUsageId')::integer,
                   (f.value->>'itemId')::integer,
                   (f.value->>'itemName')::varchar(150),
                   (f.value->>'qty')::numeric(14,3),
                   (f.value->>'unitCost')::numeric(14,4),
                   (f.value->>'totalCost')::numeric(14,2),
                   p_updatedby
            FROM jsonb_array_elements(COALESCE(v_p->'feeds', '[]'::jsonb)) AS f(value)
            WHERE (f.value->>'itemId')::integer IS NOT NULL;

            INSERT INTO productionbatchallocationmedicationusage (
                productionbatchallocationid, productionbatchmedicationusageid, inventoryitemid, itemname,
                quantityallocated, unitcost, totalcost, createdby)
            SELECT v_allocid,
                   (m.value->>'batchUsageId')::integer,
                   (m.value->>'itemId')::integer,
                   (m.value->>'itemName')::varchar(150),
                   (m.value->>'qty')::numeric(14,3),
                   (m.value->>'unitCost')::numeric(14,4),
                   (m.value->>'totalCost')::numeric(14,2),
                   p_updatedby
            FROM jsonb_array_elements(COALESCE(v_p->'medications', '[]'::jsonb)) AS m(value)
            WHERE (m.value->>'itemId')::integer IS NOT NULL;
        END LOOP;
    END IF;

    UPDATE productionbatchrecords r
    SET status = COALESCE(p_status, 'Allocated'),
        updatedby = p_updatedby,
        updateddate = (now() at time zone 'utc')
    WHERE r.id = p_id;
END;
$function$;

-- Shape changes, so the old one has to go first.
DROP FUNCTION IF EXISTS public.spproductionbatchrecord_post(p_id integer, p_farmid text, p_postedby text);
CREATE FUNCTION public.spproductionbatchrecord_post(p_id integer, p_farmid text, p_postedby text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_userid          text;
    v_status          text;
    v_date            date;
    v_conflicts       text;
    v_dupmsg          text;
    v_bp1 integer; v_bp2 integer; v_bp3 integer; v_bp4 integer; v_bp5 integer; v_bp6 integer;
    v_bbroken integer; v_bmeaty integer; v_bsoft integer; v_blost integer; v_bdeaths integer;
    v_ap1 integer; v_ap2 integer; v_ap3 integer; v_ap4 integer; v_ap5 integer; v_ap6 integer;
    v_abroken integer; v_ameaty integer; v_asoft integer; v_alost integer; v_adeaths integer;
    v_egggrade        text;
    v_batchmedication text;
    v_feedsjson       text;
    v_medsjson        text;
    v_newrecid        integer;
    a                 record;
BEGIN
    -- Lock the header for the duration: a concurrent Post blocks here, then sees
    -- Status = 'Posted' below and throws (idempotent - no double side-effects).
    SELECT r.userid, r.status, r.productiondate
      INTO v_userid, v_status, v_date
    FROM productionbatchrecords r
    WHERE r.id = p_id AND r.farmid = p_farmid
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Batch production record not found.';
    END IF;
    IF v_status = 'Posted' THEN
        RAISE EXCEPTION 'This batch has already been posted.';
    END IF;
    IF v_status NOT IN ('Allocated', 'PendingAllocation', 'Reversed') THEN
        RAISE EXCEPTION 'Only an allocated or reversed batch can be posted.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM productionbatchallocations pa WHERE pa.productionbatchrecordid = p_id) THEN
        RAISE EXCEPTION 'This batch has no allocation rows to post.';
    END IF;

    -- ---- Duplicate daily flock production guard. ----
    -- Any pre-existing ProductionRecord for an allocated flock on the same date
    -- is a genuine conflict (manual entry or another batch). Records generated by
    -- THIS batch's previous posting were hard-deleted on reversal, so they never
    -- appear here.
    SELECT string_agg(
               COALESCE(NULLIF(btrim(a2.flockname), ''), 'Flock ' || a2.flockid::text),
               ', ' ORDER BY a2.id)
      INTO v_conflicts
    FROM productionbatchallocations a2
    WHERE a2.productionbatchrecordid = p_id
      AND EXISTS (SELECT 1 FROM productionrecords pr
                  WHERE pr.farmid = p_farmid AND pr.flockid = a2.flockid AND pr.date = v_date);

    IF v_conflicts IS NOT NULL AND length(v_conflicts) > 0 THEN
        v_dupmsg := 'Cannot post: the following flock(s) already have a production record for '
                    || to_char(v_date, 'Mon DD, YYYY') || ': ' || v_conflicts
                    || '. Edit or remove the existing production record(s) before posting this allocation.';
        RAISE EXCEPTION '%', v_dupmsg;
    END IF;

    -- ---- Reconciliation: allocated egg/death totals must equal batch totals. ----
    SELECT r.firstpicktotal, r.secondpicktotal, r.thirdpicktotal, r.fourthpicktotal,
           COALESCE(r.fifthpicktotal,0), COALESCE(r.sixthpicktotal,0),
           COALESCE(r.brokeneggs,0), COALESCE(r.meatyeggs,0), COALESCE(r.softeggs,0),
           COALESCE(r.losteggs,0), COALESCE(r.deaths,0)
      INTO v_bp1, v_bp2, v_bp3, v_bp4, v_bp5, v_bp6, v_bbroken, v_bmeaty, v_bsoft, v_blost, v_bdeaths
    FROM productionbatchrecords r WHERE r.id = p_id;

    SELECT COALESCE(SUM(a2.firstpickeggs),0), COALESCE(SUM(a2.secondpickeggs),0), COALESCE(SUM(a2.thirdpickeggs),0),
           COALESCE(SUM(a2.fourthpickeggs),0),
           COALESCE(SUM(COALESCE(a2.fifthpickeggs,0)),0), COALESCE(SUM(COALESCE(a2.sixthpickeggs,0)),0),
           COALESCE(SUM(COALESCE(a2.brokeneggs,0)),0),
           COALESCE(SUM(COALESCE(a2.meatyeggs,0)),0), COALESCE(SUM(COALESCE(a2.softeggs,0)),0),
           COALESCE(SUM(COALESCE(a2.losteggs,0)),0), COALESCE(SUM(COALESCE(a2.deaths,0)),0)
      INTO v_ap1, v_ap2, v_ap3, v_ap4, v_ap5, v_ap6, v_abroken, v_ameaty, v_asoft, v_alost, v_adeaths
    FROM productionbatchallocations a2 WHERE a2.productionbatchrecordid = p_id;

    IF (v_ap1 <> v_bp1 OR v_ap2 <> v_bp2 OR v_ap3 <> v_bp3 OR v_ap4 <> v_bp4
        OR v_ap5 <> v_bp5 OR v_ap6 <> v_bp6 OR v_abroken <> v_bbroken
        OR v_ameaty <> v_bmeaty OR v_asoft <> v_bsoft OR v_alost <> v_blost OR v_adeaths <> v_bdeaths) THEN
        RAISE EXCEPTION 'Allocation does not balance against the batch egg/death totals.';
    END IF;

    -- ---- Reconciliation: allocated feed qty per item must equal batch feed qty. ----
    IF EXISTS (
        SELECT bu.inventoryitemid
        FROM productionbatchfeedusage bu
        WHERE bu.productionbatchrecordid = p_id
        GROUP BY bu.inventoryitemid
        HAVING ABS(SUM(bu.quantityused) - COALESCE((
            SELECT SUM(afu.quantityallocated)
            FROM productionbatchallocationfeedusage afu
            JOIN productionbatchallocations a3 ON a3.id = afu.productionbatchallocationid
            WHERE a3.productionbatchrecordid = p_id AND afu.inventoryitemid = bu.inventoryitemid), 0)) > 0.001
    ) THEN
        RAISE EXCEPTION 'Allocated feed quantities do not balance against the batch feed totals.';
    END IF;

    -- ---- Reconciliation: allocated medication qty per item must equal batch. ----
    IF EXISTS (
        SELECT bu.inventoryitemid
        FROM productionbatchmedicationusage bu
        WHERE bu.productionbatchrecordid = p_id
        GROUP BY bu.inventoryitemid
        HAVING ABS(SUM(bu.quantityused) - COALESCE((
            SELECT SUM(amu.quantityallocated)
            FROM productionbatchallocationmedicationusage amu
            JOIN productionbatchallocations a4 ON a4.id = amu.productionbatchallocationid
            WHERE a4.productionbatchrecordid = p_id AND amu.inventoryitemid = bu.inventoryitemid), 0)) > 0.001
    ) THEN
        RAISE EXCEPTION 'Allocated medication quantities do not balance against the batch medication totals.';
    END IF;

    SELECT r.egggrade, r.medication INTO v_egggrade, v_batchmedication
    FROM productionbatchrecords r WHERE r.id = p_id;

    FOR a IN
        SELECT pa.id                                                            AS allocid,
               pa.flockid                                                       AS flockid,
               COALESCE(pa.ageinweeks,0)                                         AS aw,
               COALESCE(pa.ageindays,0)                                          AS ad,
               COALESCE(pa.birdsbefore,0)                                        AS birdsbefore,
               COALESCE(pa.deaths,0)                                             AS deaths,
               COALESCE(pa.birdsafter, COALESCE(pa.birdsbefore,0)-COALESCE(pa.deaths,0)) AS birdsafter,
               pa.firstpickeggs                                                  AS p1,
               pa.secondpickeggs                                                 AS p2,
               pa.thirdpickeggs                                                  AS p3,
               pa.fourthpickeggs                                                 AS p4,
               COALESCE(pa.fifthpickeggs, 0)                                     AS p5,
               COALESCE(pa.sixthpickeggs, 0)                                     AS p6,
               COALESCE(pa.brokeneggs,0)                                         AS broken,
               pa.meatyeggs                                                      AS meaty,
               pa.softeggs                                                       AS soft,
               pa.losteggs                                                       AS lost,
               pa.totaleggs                                                      AS total,
               COALESCE(pa.feedkg,0)                                             AS feedkg,
               pa.notes                                                          AS notes
        FROM productionbatchallocations pa
        WHERE pa.productionbatchrecordid = p_id
        ORDER BY pa.id
    LOOP
        -- Build [{itemId,qty}] feed/medication JSON for this allocation from the flattened usage.
        SELECT json_agg(json_build_object('itemId', afu.inventoryitemid, 'qty', afu.quantityallocated))::text
          INTO v_feedsjson
        FROM productionbatchallocationfeedusage afu
        WHERE afu.productionbatchallocationid = a.allocid AND afu.quantityallocated > 0;

        SELECT json_agg(json_build_object('itemId', amu.inventoryitemid, 'qty', amu.quantityallocated))::text
          INTO v_medsjson
        FROM productionbatchallocationmedicationusage amu
        WHERE amu.productionbatchallocationid = a.allocid AND amu.quantityallocated > 0;

        v_newrecid := NULL;
        SELECT spproductionrecord_insert(
                   p_farmid          => p_farmid,
                   p_createdby       => p_postedby,
                   p_userid          => v_userid,
                   p_ageinweeks      => a.aw,
                   p_ageindays       => a.ad,
                   p_date            => v_date,
                   p_noofbirds       => a.birdsbefore,
                   p_mortality       => a.deaths,
                   p_noofbirdsleft   => a.birdsafter,
                   p_feedkg          => a.feedkg,
                   p_medication      => v_batchmedication,
                   p_production9am   => a.p1,
                   p_production12pm  => a.p2,
                   p_production4pm   => a.p3,
                   p_totalproduction => a.total,
                   p_flockid         => a.flockid,
                   p_brokeneggs      => a.broken,
                   p_notes           => a.notes,
                   p_eggcount        => a.total,
                   p_egggrade        => v_egggrade,
                   p_meatyeggs       => a.meaty,
                   p_softeggs        => a.soft,
                   p_losteggs        => a.lost,
                   p_feedsjson       => v_feedsjson,
                   p_medicationsjson => v_medsjson)
          INTO v_newrecid;

        -- 4th pick + provenance stamp on the generated flock record.
        IF v_newrecid IS NOT NULL THEN
            IF to_regprocedure('spproductionrecord_setfourthpick(integer,text,integer)') IS NOT NULL THEN
                PERFORM spproductionrecord_setfourthpick(v_newrecid, p_farmid, a.p4);
            END IF;

            -- 5th / 6th pick on the generated flock record (migration 249).
            -- Probed the same way: a database without 249 simply posts four
            -- picks rather than failing the whole batch.
            IF to_regprocedure('spproductionrecord_setextrapicks(integer,text,integer,integer)') IS NOT NULL THEN
                PERFORM spproductionrecord_setextrapicks(v_newrecid, p_farmid, a.p5, a.p6);
            END IF;

            UPDATE productionrecords pr
            SET productionbatchid = p_id,
                productionbatchallocationid = a.allocid,
                sourcetype = 'BatchAllocation'
            WHERE pr.id = v_newrecid;

            UPDATE productionbatchallocations pa
            SET generatedproductionrecordid = v_newrecid
            WHERE pa.id = a.allocid;
        END IF;
    END LOOP;

    UPDATE productionbatchrecords r
    SET status = 'Posted',
        postingversion = COALESCE(r.postingversion,0) + 1,
        postedby = p_postedby,
        posteddate = (now() at time zone 'utc'),
        updatedby = p_postedby,
        updateddate = (now() at time zone 'utc')
    WHERE r.id = p_id;
END;
$function$;

-- --- 3. Prove it ---------------------------------------------------------------
-- All six procedures must now name the new picks, and every existing batch must
-- still balance: allocated picks equal batch picks, as they did before.
SELECT 'AFTER' AS phase,
       (SELECT COUNT(*) FROM pg_proc
        WHERE proname IN ('spproductionbatchrecord_insert','spproductionbatchrecord_update',
                          'spproductionbatchrecord_getall','spproductionbatchrecord_getbyid',
                          'spproductionbatchrecord_saveallocation','spproductionbatchrecord_post')
          AND prosrc ILIKE '%fifthpick%') AS procs_updated_of_6,
       (SELECT COUNT(*) FROM productionbatchrecords r
        WHERE EXISTS (SELECT 1 FROM productionbatchallocations a WHERE a.productionbatchrecordid = r.id)
          AND (SELECT COALESCE(SUM(a.fifthpickeggs),0) + COALESCE(SUM(a.sixthpickeggs),0)
               FROM productionbatchallocations a WHERE a.productionbatchrecordid = r.id)
              <> COALESCE(r.fifthpicktotal,0) + COALESCE(r.sixthpicktotal,0)) AS batches_now_unbalanced;

COMMIT;

-- =============================================================================
-- UNDO (paste separately if ever needed)
-- =============================================================================
-- Re-apply the six procedure definitions from the batch-module migration, then:
-- ALTER TABLE productionbatchrecords
--     DROP COLUMN IF EXISTS fifthpickcrates, DROP COLUMN IF EXISTS fifthpicklooseeggs,
--     DROP COLUMN IF EXISTS fifthpicktotal,  DROP COLUMN IF EXISTS sixthpickcrates,
--     DROP COLUMN IF EXISTS sixthpicklooseeggs, DROP COLUMN IF EXISTS sixthpicktotal;
-- ALTER TABLE productionbatchallocations
--     DROP COLUMN IF EXISTS fifthpickeggs, DROP COLUMN IF EXISTS sixthpickeggs;

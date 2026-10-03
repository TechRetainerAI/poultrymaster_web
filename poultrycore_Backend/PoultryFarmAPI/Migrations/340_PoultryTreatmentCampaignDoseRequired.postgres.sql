-- =============================================================================
-- 340_PoultryTreatmentCampaignDoseRequired.postgres.sql
--
-- Purpose
-- -------
-- A treatment campaign must state its dose: an amount AND what it is per
-- (per bird, per 1,000 birds or per flock). 339 allowed a campaign with no
-- dose; the page already requires one, and this makes the database refuse it
-- too, so no other caller can create one without it.
--
-- The dose is still the farm's own figure, typed on the campaign or taken
-- from the product's saved setting -- nothing is built in.
--
-- Only sppoultrytreatmentcampaign_create changes (same signature, one new
-- check). Campaigns created before this without a dose are left as they are;
-- their days are still recorded by typing each quantity.
--
-- Depends on 339. Idempotent.
-- EFFECT ON TODAY'S NUMBERS: none.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.sppoultrytreatmentcampaign_create(
    p_farmid             text,
    p_name               text,
    p_itemid             integer,
    p_reason             text,
    p_startdate          date,
    p_enddate            date,
    p_doseinstructions   text,
    p_dosequantity       numeric,
    p_dosebasis          text,
    p_dosesource         text,
    p_eggwithdrawaldays  integer,
    p_meatwithdrawaldays integer,
    p_withdrawalnotes    text,
    p_notes              text,
    p_flocksjson         text,
    p_createdby          text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
    v_item     record;
    v_id       integer;
    v_n        integer;
    v_problems text;
    v_basis    text := NULLIF(btrim(p_dosebasis), '');
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN RAISE EXCEPTION 'Company ID is required.'; END IF;
    IF NULLIF(btrim(p_name), '') IS NULL THEN RAISE EXCEPTION 'Give the campaign a name.'; END IF;
    IF p_startdate IS NULL OR p_enddate IS NULL THEN RAISE EXCEPTION 'A start date and an end date are required.'; END IF;
    IF p_enddate < p_startdate THEN RAISE EXCEPTION 'The end date is before the start date.'; END IF;
    IF p_enddate - p_startdate > 365 THEN RAISE EXCEPTION 'A campaign can run for at most a year.'; END IF;
    -- 340: a campaign always carries its dose.
    IF p_dosequantity IS NULL OR v_basis IS NULL THEN
        RAISE EXCEPTION 'A dose needs both an amount and what it is per (per bird, per 1,000 birds or per flock).';
    END IF;
    IF v_basis NOT IN ('PerBird', 'Per1000Birds', 'PerFlock') THEN
        RAISE EXCEPTION 'A dose is per bird, per 1,000 birds or per flock.';
    END IF;
    IF p_dosequantity <= 0 THEN RAISE EXCEPTION 'A dose must be more than 0.'; END IF;

    SELECT i.poultryrawmaterialitemid, i.itemname, i.unitofmeasure, i.category, COALESCE(i.isactive, TRUE) AS isactive
    INTO v_item FROM poultryrawmaterialitems i
    WHERE i.poultryrawmaterialitemid = p_itemid AND i.farmid = p_farmid;
    IF v_item.poultryrawmaterialitemid IS NULL THEN RAISE EXCEPTION 'Medication product not found for this company.'; END IF;
    IF NOT public.fnpoultry_ismedicationcategory(v_item.category) THEN
        RAISE EXCEPTION '% is not a medication product (category %).', v_item.itemname, v_item.category;
    END IF;
    IF NOT v_item.isactive THEN RAISE EXCEPTION 'This medication product is inactive.'; END IF;

    DROP TABLE IF EXISTS tmp_treatcamp_flocks;
    CREATE TEMP TABLE tmp_treatcamp_flocks ON COMMIT DROP AS
    SELECT (x->>'flockId')::int AS flockid,
           NULLIF(x->>'doseQuantity', '')::numeric AS dosequantity,
           NULLIF(btrim(x->>'notes'), '') AS notes
    FROM jsonb_array_elements(COALESCE(NULLIF(p_flocksjson, ''), '[]')::jsonb) x;

    SELECT count(*) INTO v_n FROM tmp_treatcamp_flocks;
    IF v_n = 0 THEN RAISE EXCEPTION 'Choose at least one flock.'; END IF;
    IF EXISTS (SELECT flockid FROM tmp_treatcamp_flocks GROUP BY flockid HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'A flock appears more than once in this campaign.';
    END IF;
    IF EXISTS (SELECT 1 FROM tmp_treatcamp_flocks WHERE dosequantity IS NOT NULL AND dosequantity <= 0) THEN
        RAISE EXCEPTION 'A flock''s dose must be more than 0.';
    END IF;
    IF EXISTS (SELECT 1 FROM tmp_treatcamp_flocks WHERE dosequantity IS NOT NULL) AND v_basis IS NULL THEN
        RAISE EXCEPTION 'Set what the dose is per (per bird, per 1,000 birds or per flock) before giving flocks their own dose.';
    END IF;

    SELECT string_agg(format('flock #%s %s', t.flockid,
               CASE WHEN f.flockid IS NULL THEN 'is not a flock of this company'
                    WHEN f.closeddate IS NOT NULL THEN 'is closed'
                    ELSE 'is not active' END), '; ')
    INTO v_problems
    FROM tmp_treatcamp_flocks t
    LEFT JOIN flock f ON f.flockid = t.flockid AND f.farmid = p_farmid
    WHERE f.flockid IS NULL OR f.closeddate IS NOT NULL OR NOT f.active OR f.isdeleted;
    IF v_problems IS NOT NULL THEN RAISE EXCEPTION 'Cannot create: %.', v_problems USING ERRCODE = 'P0004'; END IF;

    INSERT INTO poultrytreatmentcampaigns (farmid, name, poultryrawmaterialitemid, itemname, unitofmeasure, reason,
        startdate, enddate, doseinstructions, dosequantity, dosebasis, dosesource,
        eggwithdrawaldays, meatwithdrawaldays, withdrawalnotes, notes, lifecycle, createdby)
    VALUES (p_farmid, btrim(p_name), p_itemid, v_item.itemname, v_item.unitofmeasure, NULLIF(btrim(p_reason), ''),
            p_startdate, p_enddate, NULLIF(btrim(p_doseinstructions), ''), p_dosequantity, v_basis,
            CASE WHEN p_dosequantity IS NULL THEN 'None'
                 WHEN p_dosesource IN ('User', 'Product') THEN p_dosesource ELSE 'User' END,
            p_eggwithdrawaldays, p_meatwithdrawaldays, NULLIF(btrim(p_withdrawalnotes), ''),
            NULLIF(btrim(p_notes), ''), 'Open', p_createdby)
    RETURNING poultrytreatmentcampaignid INTO v_id;

    INSERT INTO poultrytreatmentcampaignflocks (poultrytreatmentcampaignid, farmid, flockid, flockname, birdsatcreation, dosequantity, notes)
    SELECT v_id, p_farmid, t.flockid, o.flockname, o.birds, t.dosequantity, t.notes
    FROM tmp_treatcamp_flocks t
    JOIN public.sppoultrytreatmentcampaign_flockoptions(p_farmid) o ON o.flockid = t.flockid;

    RETURN v_id;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification. Every fixture is rolled back by the sentinel at the end.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    a   text := '44444444-3333-4333-8333-000000000340';
    who text := '__340__';
    med integer; f1 integer; c1 integer;
BEGIN
    BEGIN
        INSERT INTO farms (id, farmid, name, email, type, timezoneid)
        VALUES (a, a, 'Selftest A', 'a@selftest.invalid', 'Poultry', 'UTC');
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, usagemethod)
        VALUES (a, 'Amoxy 20%', 'Medication', 'Litre', 0, TRUE, 'FIFO') RETURNING poultryrawmaterialitemid INTO med;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'F1', current_date - 30, 'Brown', 1000, TRUE, TRUE, -340, timestamp '2025-01-01')
        RETURNING flockid INTO f1;

        -- No dose at all, an amount without a basis, a basis without an amount: refused.
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_create(a, 'No dose', med, NULL, current_date, current_date, NULL,
                NULL, NULL, NULL, NULL, NULL, NULL, NULL, json_build_array(json_build_object('flockId', f1))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '340: created a campaign with no dose.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_create(a, 'No basis', med, NULL, current_date, current_date, NULL,
                1, NULL, 'User', NULL, NULL, NULL, NULL, json_build_array(json_build_object('flockId', f1))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '340: created a campaign with an amount but no basis.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_create(a, 'No amount', med, NULL, current_date, current_date, NULL,
                NULL, 'PerBird', 'User', NULL, NULL, NULL, NULL, json_build_array(json_build_object('flockId', f1))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '340: created a campaign with a basis but no amount.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_create(a, 'Bad basis', med, NULL, current_date, current_date, NULL,
                1, 'PerLitre', 'User', NULL, NULL, NULL, NULL, json_build_array(json_build_object('flockId', f1))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '340: accepted an unknown dose basis.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- A full dose is accepted, as before.
        c1 := public.sppoultrytreatmentcampaign_create(a, 'With dose', med, NULL, current_date, current_date, NULL,
            0.5, 'Per1000Birds', 'User', NULL, NULL, NULL, NULL, json_build_array(json_build_object('flockId', f1))::text, who);
        IF (SELECT c.dosequantity FROM poultrytreatmentcampaigns c WHERE c.poultrytreatmentcampaignid = c1) <> 0.5 THEN
            RAISE EXCEPTION '340: the dose was not saved.';
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '__340_ok__';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;
    END;
    RAISE NOTICE '340_PoultryTreatmentCampaignDoseRequired: verified (no dose, amount only, basis only, unknown basis refused; full dose accepted).';
END $$;

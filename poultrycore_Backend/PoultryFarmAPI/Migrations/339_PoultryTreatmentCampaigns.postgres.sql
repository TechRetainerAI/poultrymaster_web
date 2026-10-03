-- =============================================================================
-- 339_PoultryTreatmentCampaigns.postgres.sql
--
-- Purpose
-- -------
-- Treatment Campaigns: one medication / vaccine / treatment given to many
-- flocks, over one day or several ("5-day course of X for houses 2-4"). An
-- ORCHESTRATION tool -- every dose it posts is exactly the medication line a
-- farmer would get by opening that flock's production record for the day and
-- adding the medication by hand.
--
-- HOW MEDICATION LEAVES STOCK IN THIS SYSTEM (and therefore how this posts)
-- ========================================================================
-- Medication is drawn from inventory in exactly one place: the medication
-- LINES on a flock's production record. spproductionrecord_update calls
-- sppoultryproductionrawmaterialsync, which
--   * restores and re-draws the record's lots through
--     sppoultryrawmaterialitem_consumebatches (FIFO / LIFO / HIFO per item),
--   * writes poultryrawmaterialusage / usagebatch and productionrecordmedications,
--   * books or reverses the consumption expense (266 / 272) according to the
--     cost-recognition method stamped on each LOT -- nothing for medication
--     expensed at purchase, a NonCash 'PoultryMedicationConsumption' row for
--     medication expensed when consumed. Never both.
-- (Health Records are a free-text log and never touch stock; /medication-tracker
-- only reads. Neither is a path to reuse.)
--
-- So "Record Today's Treatment" = for each flock, call spproductionrecord_update
-- with every field of that flock's record unchanged, its existing medication
-- lines PLUS the campaign's line, and its feed lines passed through as they
-- are -- the same mechanism as Distribute Feed (335). No stock, lot, cost or
-- expense is computed here.
--
-- WHAT THIS DOES NOT DO
-- =====================
-- * No medical advice. No dose, duration or withdrawal period is built in. A
--   dose comes from the person creating the campaign, or from the farm's own
--   saved figure for that product (poultrymedicationproductsettings) -- with no
--   row, there is no suggestion. Suggested quantity is plain arithmetic on that
--   figure and the flock's bird count, shown for review; the ACTUAL quantity is
--   always typed and is the only thing posted.
-- * Nothing is consumed ahead of time. Creating a 5-day campaign moves no stock.
--   Each day's doses leave stock only when that day is posted.
-- * Withdrawal is recorded, not decided: the farm's own egg / meat withdrawal
--   days for the product (or typed on the campaign), and the date they run to
--   from the LAST posted dose. Nothing is blocked on it -- the system has no
--   egg-sale hold to attach it to.
--
-- PRODUCTION FIRST (same rule as 335, decided 2026-09-30)
-- ========================================================
-- A flock is dosed on a date only if it has exactly ONE production record for
-- that date. None: refused ("record production first") -- a medication-only
-- record would make Farm Completeness and Daily Closing read the day as done.
-- Two or more: refused (fix the duplicate first). A CLOSED flock is refused too:
-- the close-out guard on productionrecords does not fire on a medication-only
-- edit, so it is checked here.
--
-- WHICH PRODUCTS
-- ==============
-- Raw-material items whose category matches /medic|vaccin|drug/i -- the same
-- test the production forms use for their medication picker. The sync itself
-- never checks category, so this is enforced here.
--
-- LIFECYCLE
-- =========
-- Stored: Open | Completed | Cancelled. Shown: Scheduled (Open, before the start
-- date) | In Progress (Open, from the start date) | Completed | Cancelled.
-- Cancelling or completing stops further posting; it does not undo doses
-- already posted -- those birds were treated. To take a wrong day back, reverse
-- that day's posting (append-only, reason required).
--
-- ONE POSTING PER CAMPAIGN PER DAY
-- ================================
-- A unique index allows one LIVE posting per campaign and date, so a double
-- click or a second user cannot dose the same day twice. To correct a day:
-- reverse it, then post it again.
--
-- CONCURRENCY
-- ===========
-- Posting takes an advisory lock for (farm, product) and locks the product's
-- purchase lots FOR UPDATE, then re-reads what the lots can supply. Two people
-- posting the same product serialise; the second sees what the first left.
--
-- HISTORY
-- =======
-- Every posted dose is a line with the flock, its production record and the
-- campaign. sppoultrytreatmentcampaign_flockhistory(farm, flock) lists a
-- flock's treatments from campaigns; the production record's own medication
-- lines still show it too, as for any dose.
--
-- Depends on 332 (flock eligibility), 266/272 (consumption recognition), 298
-- (company business date). Idempotent. Safe to run more than once.
-- EFFECT ON TODAY'S NUMBERS: none until a treatment day is posted.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The farm's own figures per product. Nothing is assumed: no row, no
--    suggested dose and no withdrawal period.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultrymedicationproductsettings (
    farmid                   text NOT NULL,
    poultryrawmaterialitemid integer NOT NULL,
    -- A dose in the product's own unit of measure, per DOSEBASIS per day.
    dosequantity             numeric(14,4) CHECK (dosequantity IS NULL OR dosequantity > 0),
    dosebasis                text CHECK (dosebasis IS NULL OR dosebasis IN ('PerBird', 'Per1000Birds', 'PerFlock')),
    eggwithdrawaldays        integer CHECK (eggwithdrawaldays IS NULL OR eggwithdrawaldays BETWEEN 0 AND 365),
    meatwithdrawaldays       integer CHECK (meatwithdrawaldays IS NULL OR meatwithdrawaldays BETWEEN 0 AND 365),
    withdrawalnotes          text,
    updatedby                text,
    updatedatutc             timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (farmid, poultryrawmaterialitemid),
    CONSTRAINT ck_poultrymedsettings_dose CHECK ((dosequantity IS NULL) = (dosebasis IS NULL))
);

-- -----------------------------------------------------------------------------
-- 2. Campaigns (append-only), their flocks, and the daily postings.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultrytreatmentcampaigns (
    poultrytreatmentcampaignid serial      PRIMARY KEY,
    farmid                     text        NOT NULL,
    name                       text        NOT NULL,
    poultryrawmaterialitemid   integer     NOT NULL,
    itemname                   text,
    unitofmeasure              text,
    reason                     text,
    startdate                  date        NOT NULL,
    enddate                    date        NOT NULL,
    -- "Dose/Usage Information" as the person wrote it (e.g. the label's
    -- instruction). Free text, recorded, never interpreted.
    doseinstructions           text,
    dosequantity               numeric(14,4) CHECK (dosequantity IS NULL OR dosequantity > 0),
    dosebasis                  text CHECK (dosebasis IS NULL OR dosebasis IN ('PerBird', 'Per1000Birds', 'PerFlock')),
    -- Where the dose figure came from: typed for this campaign, or the
    -- product's saved setting. None = no figure, so no suggestion.
    dosesource                 text        NOT NULL DEFAULT 'None'
        CONSTRAINT ck_poultrytreatcamp_dosesource CHECK (dosesource IN ('User', 'Product', 'None')),
    eggwithdrawaldays          integer CHECK (eggwithdrawaldays IS NULL OR eggwithdrawaldays BETWEEN 0 AND 365),
    meatwithdrawaldays         integer CHECK (meatwithdrawaldays IS NULL OR meatwithdrawaldays BETWEEN 0 AND 365),
    withdrawalnotes            text,
    notes                      text,
    lifecycle                  text        NOT NULL DEFAULT 'Open'
        CONSTRAINT ck_poultrytreatcamp_lifecycle CHECK (lifecycle IN ('Open', 'Completed', 'Cancelled')),
    createdby                  text,
    createdatutc               timestamptz NOT NULL DEFAULT now(),
    completedby                text,
    completedatutc             timestamptz,
    cancelledby                text,
    cancelledatutc             timestamptz,
    cancelreason               text,
    CONSTRAINT ck_poultrytreatcamp_dates CHECK (enddate >= startdate),
    CONSTRAINT ck_poultrytreatcamp_dose CHECK ((dosequantity IS NULL) = (dosebasis IS NULL))
);
CREATE INDEX IF NOT EXISTS ix_poultrytreatcamp_farm ON public.poultrytreatmentcampaigns (farmid, startdate DESC);

CREATE TABLE IF NOT EXISTS public.poultrytreatmentcampaignflocks (
    poultrytreatmentcampaignflockid serial  PRIMARY KEY,
    poultrytreatmentcampaignid      integer NOT NULL REFERENCES public.poultrytreatmentcampaigns (poultrytreatmentcampaignid),
    farmid                          text    NOT NULL,
    flockid                         integer NOT NULL,
    flockname                       text,
    birdsatcreation                 integer,
    -- This flock's own dose, when it differs from the campaign's. Same basis.
    dosequantity                    numeric(14,4) CHECK (dosequantity IS NULL OR dosequantity > 0),
    notes                           text,
    CONSTRAINT ux_poultrytreatcampflock UNIQUE (poultrytreatmentcampaignid, flockid)
);
CREATE INDEX IF NOT EXISTS ix_poultrytreatcampflock_flock ON public.poultrytreatmentcampaignflocks (farmid, flockid);

CREATE TABLE IF NOT EXISTS public.poultrytreatmentcampaignposts (
    poultrytreatmentcampaignpostid serial      PRIMARY KEY,
    poultrytreatmentcampaignid     integer     NOT NULL REFERENCES public.poultrytreatmentcampaigns (poultrytreatmentcampaignid),
    farmid                         text        NOT NULL,
    businessdate                   date        NOT NULL,
    flockcount                     integer     NOT NULL,
    totalquantity                  numeric(14,4) NOT NULL,
    totalcost                      numeric(14,2),
    status                         text        NOT NULL DEFAULT 'Posted'
        CONSTRAINT ck_poultrytreatpost_status CHECK (status IN ('Posted', 'Reversed')),
    notes                          text,
    postedby                       text,
    postedatutc                    timestamptz NOT NULL DEFAULT now(),
    reversedby                     text,
    reversedatutc                  timestamptz,
    reversalreason                 text
);
CREATE INDEX IF NOT EXISTS ix_poultrytreatpost_campaign ON public.poultrytreatmentcampaignposts (poultrytreatmentcampaignid, businessdate);
-- One live posting per campaign per day.
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrytreatpost_liveday
    ON public.poultrytreatmentcampaignposts (poultrytreatmentcampaignid, businessdate) WHERE status = 'Posted';

CREATE TABLE IF NOT EXISTS public.poultrytreatmentcampaignpostlines (
    poultrytreatmentcampaignpostlineid serial  PRIMARY KEY,
    poultrytreatmentcampaignpostid     integer NOT NULL REFERENCES public.poultrytreatmentcampaignposts (poultrytreatmentcampaignpostid),
    poultrytreatmentcampaignid         integer NOT NULL,
    farmid                             text    NOT NULL,
    flockid                            integer NOT NULL,
    flockname                          text,
    productionrecordid                 integer NOT NULL,
    birds                              integer,
    dosequantity                       numeric(14,4),
    dosebasis                          text,
    suggestedquantity                  numeric(14,4),
    actualquantity                     numeric(14,4) NOT NULL CHECK (actualquantity > 0),
    unitcost                           numeric(14,4),
    totalcost                          numeric(14,2),
    notes                              text,
    reversalnote                       text
);
CREATE INDEX IF NOT EXISTS ix_poultrytreatpostline_post ON public.poultrytreatmentcampaignpostlines (poultrytreatmentcampaignpostid);
CREATE INDEX IF NOT EXISTS ix_poultrytreatpostline_flock ON public.poultrytreatmentcampaignpostlines (farmid, flockid);
CREATE INDEX IF NOT EXISTS ix_poultrytreatpostline_record ON public.poultrytreatmentcampaignpostlines (productionrecordid);

CREATE OR REPLACE FUNCTION public.trg_poultrytreatcamp_nodelete()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    RAISE EXCEPTION 'Treatment campaigns are append-only; cancel the campaign or reverse the posting instead of deleting it.';
END;
$function$;

DROP TRIGGER IF EXISTS trg_poultrytreatcamp_nodelete ON public.poultrytreatmentcampaigns;
CREATE TRIGGER trg_poultrytreatcamp_nodelete BEFORE DELETE ON public.poultrytreatmentcampaigns
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultrytreatcamp_nodelete();
DROP TRIGGER IF EXISTS trg_poultrytreatcampflock_nodelete ON public.poultrytreatmentcampaignflocks;
CREATE TRIGGER trg_poultrytreatcampflock_nodelete BEFORE DELETE ON public.poultrytreatmentcampaignflocks
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultrytreatcamp_nodelete();
DROP TRIGGER IF EXISTS trg_poultrytreatpost_nodelete ON public.poultrytreatmentcampaignposts;
CREATE TRIGGER trg_poultrytreatpost_nodelete BEFORE DELETE ON public.poultrytreatmentcampaignposts
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultrytreatcamp_nodelete();
DROP TRIGGER IF EXISTS trg_poultrytreatpostline_nodelete ON public.poultrytreatmentcampaignpostlines;
CREATE TRIGGER trg_poultrytreatpostline_nodelete BEFORE DELETE ON public.poultrytreatmentcampaignpostlines
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultrytreatcamp_nodelete();

-- -----------------------------------------------------------------------------
-- 3. Small helpers.
-- -----------------------------------------------------------------------------
-- The production forms' medication test.
CREATE OR REPLACE FUNCTION public.fnpoultry_ismedicationcategory(p_category text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $function$
    SELECT COALESCE(p_category, '') ~* '(medic|vaccin|drug)';
$function$;

-- Plain arithmetic on the farm's own dose figure. NULL when there is no figure
-- or no bird count to multiply -- never a stand-in.
CREATE OR REPLACE FUNCTION public.fnpoultrytreatment_suggest(p_dose numeric, p_basis text, p_birds integer)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $function$
    SELECT CASE
             WHEN p_dose IS NULL OR p_basis IS NULL THEN NULL
             WHEN p_basis = 'PerFlock'     THEN round(p_dose, 4)
             WHEN p_birds IS NULL          THEN NULL
             WHEN p_basis = 'PerBird'      THEN round(p_dose * p_birds, 4)
             WHEN p_basis = 'Per1000Birds' THEN round(p_dose * p_birds / 1000.0, 4)
           END;
$function$;

-- Shown status. Stored lifecycle + the company's own today.
CREATE OR REPLACE FUNCTION public.fnpoultrytreatmentcampaign_status(p_lifecycle text, p_startdate date, p_today date)
RETURNS text LANGUAGE sql IMMUTABLE AS $function$
    SELECT CASE
             WHEN p_lifecycle = 'Cancelled' THEN 'Cancelled'
             WHEN p_lifecycle = 'Completed' THEN 'Completed'
             WHEN p_today < p_startdate     THEN 'Scheduled'
             ELSE 'InProgress'
           END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Products: the farm's medication items, what their lots can supply, how
--    their cost is recognised, and the farm's own saved figures.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultrymedication_products(text);
CREATE FUNCTION public.sppoultrymedication_products(p_farmid text)
RETURNS TABLE(
    poultryrawmaterialitemid integer, itemname text, category text, unitofmeasure text,
    usagemethod text, isactive boolean, availablequantity numeric, lotcount integer,
    costrecognitionmethod text,
    dosequantity numeric, dosebasis text, eggwithdrawaldays integer, meatwithdrawaldays integer,
    withdrawalnotes text)
LANGUAGE sql
STABLE
AS $function$
    SELECT i.poultryrawmaterialitemid, i.itemname::text, i.category::text, i.unitofmeasure::text,
           COALESCE(i.usagemethod, 'FIFO')::text, COALESCE(i.isactive, TRUE),
           COALESCE((SELECT sum(p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1))
                     FROM poultryrawmaterialpurchases p
                     WHERE p.farmid = p_farmid AND p.poultryrawmaterialitemid = i.poultryrawmaterialitemid
                       AND p.remainingquantity > 0), 0)::numeric(14,4),
           (SELECT count(*)::int FROM poultryrawmaterialpurchases p
            WHERE p.farmid = p_farmid AND p.poultryrawmaterialitemid = i.poultryrawmaterialitemid
              AND p.remainingquantity > 0),
           (SELECT e.method FROM public.fnpoultrycostrecognition_effective(
                p_farmid, i.poultryrawmaterialitemid, i.category, public.fncompany_businessdate(p_farmid)) e),
           s.dosequantity, s.dosebasis, s.eggwithdrawaldays, s.meatwithdrawaldays, s.withdrawalnotes
    FROM   poultryrawmaterialitems i
    LEFT   JOIN poultrymedicationproductsettings s
           ON s.farmid = i.farmid AND s.poultryrawmaterialitemid = i.poultryrawmaterialitemid
    WHERE  i.farmid = p_farmid AND public.fnpoultry_ismedicationcategory(i.category)
    ORDER  BY i.itemname;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrymedication_setproductsettings(
    p_farmid text, p_itemid integer, p_dosequantity numeric, p_dosebasis text,
    p_eggwithdrawaldays integer, p_meatwithdrawaldays integer, p_withdrawalnotes text, p_updatedby text)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM poultryrawmaterialitems i
                   WHERE i.poultryrawmaterialitemid = p_itemid AND i.farmid = p_farmid
                     AND public.fnpoultry_ismedicationcategory(i.category)) THEN
        RAISE EXCEPTION 'Medication product not found for this company.';
    END IF;
    IF (p_dosequantity IS NULL) <> (NULLIF(p_dosebasis, '') IS NULL) THEN
        RAISE EXCEPTION 'A dose needs both an amount and what it is per (per bird, per 1,000 birds or per flock).';
    END IF;
    IF p_dosequantity IS NOT NULL AND p_dosequantity <= 0 THEN
        RAISE EXCEPTION 'A dose must be more than 0.';
    END IF;
    IF p_dosequantity IS NULL AND p_eggwithdrawaldays IS NULL AND p_meatwithdrawaldays IS NULL
       AND NULLIF(btrim(p_withdrawalnotes), '') IS NULL THEN
        DELETE FROM poultrymedicationproductsettings s WHERE s.farmid = p_farmid AND s.poultryrawmaterialitemid = p_itemid;
        RETURN;
    END IF;
    INSERT INTO poultrymedicationproductsettings AS t (farmid, poultryrawmaterialitemid, dosequantity, dosebasis,
        eggwithdrawaldays, meatwithdrawaldays, withdrawalnotes, updatedby, updatedatutc)
    VALUES (p_farmid, p_itemid, p_dosequantity, NULLIF(p_dosebasis, ''), p_eggwithdrawaldays, p_meatwithdrawaldays,
            NULLIF(btrim(p_withdrawalnotes), ''), p_updatedby, now())
    ON CONFLICT (farmid, poultryrawmaterialitemid) DO UPDATE
    SET dosequantity = EXCLUDED.dosequantity, dosebasis = EXCLUDED.dosebasis,
        eggwithdrawaldays = EXCLUDED.eggwithdrawaldays, meatwithdrawaldays = EXCLUDED.meatwithdrawaldays,
        withdrawalnotes = EXCLUDED.withdrawalnotes, updatedby = EXCLUDED.updatedby, updatedatutc = now();
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Flocks that can be put on a campaign: open (not closed), active, arrived,
--    not deleted -- with today's bird count for the grid.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultrytreatmentcampaign_flockoptions(text);
CREATE FUNCTION public.sppoultrytreatmentcampaign_flockoptions(p_farmid text)
RETURNS TABLE(flockid integer, flockname text, batchname text, housename text, birds integer)
LANGUAGE sql
STABLE
AS $function$
    SELECT f.flockid, f.name::text, b.batchname::text, h.housename::text,
           COALESCE(
               (SELECT pr.noofbirdsleft FROM productionrecords pr
                WHERE pr.farmid = p_farmid AND pr.flockid = f.flockid
                ORDER BY pr.date DESC, pr.id DESC LIMIT 1),
               f.quantity)
    FROM   flock f
    LEFT   JOIN mainflockbatch b ON b.batchid = f.batchid AND b.farmid = f.farmid
    LEFT   JOIN houses h         ON h.houseid = f.houseid AND h.farmid = f.farmid
    WHERE  f.farmid = p_farmid AND f.active AND f.hasarrived AND NOT f.isdeleted AND f.closeddate IS NULL
    ORDER  BY b.batchname NULLS LAST, h.housename NULLS LAST, f.name, f.flockid;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Create. p_flocksjson: [{flockId, doseQuantity?, notes?}].
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultrytreatmentcampaign_create(text, text, integer, text, date, date, text, numeric, text, text, integer, integer, text, text, text, text);
CREATE FUNCTION public.sppoultrytreatmentcampaign_create(
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
    IF (p_dosequantity IS NULL) <> (v_basis IS NULL) THEN
        RAISE EXCEPTION 'A dose needs both an amount and what it is per (per bird, per 1,000 birds or per flock).';
    END IF;
    IF p_dosequantity IS NOT NULL AND p_dosequantity <= 0 THEN RAISE EXCEPTION 'A dose must be more than 0.'; END IF;

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

-- -----------------------------------------------------------------------------
-- 7. Complete / cancel. Neither touches posted doses.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrytreatmentcampaign_complete(p_id integer, p_farmid text, p_by text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v_c record;
BEGIN
    SELECT * INTO v_c FROM poultrytreatmentcampaigns c
    WHERE c.poultrytreatmentcampaignid = p_id AND c.farmid = p_farmid FOR UPDATE;
    IF v_c.poultrytreatmentcampaignid IS NULL THEN RAISE EXCEPTION 'Treatment campaign not found.'; END IF;
    IF v_c.lifecycle <> 'Open' THEN RAISE EXCEPTION 'This campaign is already %.', lower(v_c.lifecycle); END IF;
    UPDATE poultrytreatmentcampaigns c
    SET lifecycle = 'Completed', completedby = p_by, completedatutc = now()
    WHERE c.poultrytreatmentcampaignid = p_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrytreatmentcampaign_cancel(p_id integer, p_farmid text, p_reason text, p_by text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v_c record;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'A reason is required to cancel a campaign.'; END IF;
    SELECT * INTO v_c FROM poultrytreatmentcampaigns c
    WHERE c.poultrytreatmentcampaignid = p_id AND c.farmid = p_farmid FOR UPDATE;
    IF v_c.poultrytreatmentcampaignid IS NULL THEN RAISE EXCEPTION 'Treatment campaign not found.'; END IF;
    IF v_c.lifecycle <> 'Open' THEN RAISE EXCEPTION 'This campaign is already %.', lower(v_c.lifecycle); END IF;
    UPDATE poultrytreatmentcampaigns c
    SET lifecycle = 'Cancelled', cancelledby = p_by, cancelledatutc = now(), cancelreason = btrim(p_reason)
    WHERE c.poultrytreatmentcampaignid = p_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 8. The day grid: each campaign flock on a date, with what posting needs.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultrytreatmentcampaign_daygrid(integer, text, date);
CREATE FUNCTION public.sppoultrytreatmentcampaign_daygrid(p_id integer, p_farmid text, p_date date)
RETURNS TABLE(
    flockid integer, flockname text, housename text, isclosed boolean,
    recordcount integer, productionrecordid integer, birds integer,
    dosequantity numeric, dosebasis text, suggestedquantity numeric,
    thisitemquantity numeric, postedquantity numeric, notes text)
LANGUAGE plpgsql
STABLE
AS $function$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    WITH c AS (
        SELECT * FROM poultrytreatmentcampaigns c
        WHERE c.poultrytreatmentcampaignid = p_id AND c.farmid = p_farmid
    ),
    rec AS (
        SELECT pr.flockid, count(*)::int AS n, min(pr.id) AS id
        FROM   productionrecords pr
        WHERE  pr.farmid = p_farmid AND pr.date = p_date
        GROUP  BY pr.flockid
    ),
    g AS (
        SELECT cf.flockid, COALESCE(f.name::text, cf.flockname) AS flockname, h.housename::text AS housename,
               (f.closeddate IS NOT NULL) AS isclosed,
               COALESCE(rec.n, 0) AS n,
               CASE WHEN rec.n = 1 THEN rec.id END AS recid,
               -- Birds: the day's record (opening birds, else birds left); with
               -- no record, the last record before the day, else the flock count.
               COALESCE(
                   (SELECT COALESCE(NULLIF(pr.noofbirds, 0), pr.noofbirdsleft) FROM productionrecords pr
                    WHERE pr.id = rec.id AND rec.n = 1),
                   (SELECT pr.noofbirdsleft FROM productionrecords pr
                    WHERE pr.farmid = p_farmid AND pr.flockid = cf.flockid AND pr.date < p_date
                    ORDER BY pr.date DESC, pr.id DESC LIMIT 1),
                   f.quantity) AS birds,
               COALESCE(cf.dosequantity, c.dosequantity) AS dose,
               c.dosebasis AS basis,
               c.poultryrawmaterialitemid AS itemid,
               cf.notes,
               cf.poultrytreatmentcampaignflockid AS ord
        FROM   c
        JOIN   poultrytreatmentcampaignflocks cf ON cf.poultrytreatmentcampaignid = c.poultrytreatmentcampaignid
        LEFT   JOIN flock f  ON f.flockid = cf.flockid AND f.farmid = p_farmid
        LEFT   JOIN houses h ON h.houseid = f.houseid AND h.farmid = p_farmid
        LEFT   JOIN rec      ON rec.flockid = cf.flockid
    )
    SELECT g.flockid, g.flockname, g.housename, g.isclosed, g.n, g.recid, g.birds,
           g.dose, g.basis, public.fnpoultrytreatment_suggest(g.dose, g.basis, g.birds),
           (SELECT COALESCE(sum(m.quantityconsumed), 0) FROM productionrecordmedications m
            WHERE g.n = 1 AND m.productionrecordid = g.recid AND m.poultryrawmaterialitemid = g.itemid),
           (SELECT l.actualquantity FROM poultrytreatmentcampaignpostlines l
            JOIN poultrytreatmentcampaignposts p ON p.poultrytreatmentcampaignpostid = l.poultrytreatmentcampaignpostid
            WHERE p.poultrytreatmentcampaignid = p_id AND p.businessdate = p_date AND p.status = 'Posted'
              AND l.flockid = g.flockid),
           g.notes
    FROM g
    ORDER BY g.ord;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 9. Change one record's quantity of one medication by p_delta, through the
--    ordinary record update. Internal: post and reverse are its only callers.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrytreatment_changerecordmed(
    p_farmid text, p_recordid integer, p_itemid integer, p_delta numeric, p_by text,
    OUT addedunitcost numeric, OUT addedtotalcost numeric)
RETURNS record
LANGUAGE plpgsql
AS $function$
DECLARE
    r       productionrecords%ROWTYPE;
    v_feeds jsonb;
    v_meds  jsonb;
    v_have  numeric;
BEGIN
    SELECT * INTO r FROM productionrecords pr WHERE pr.id = p_recordid AND pr.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Production record % not found for this company.', p_recordid;
    END IF;

    -- The record's current lines are its truth (the sync rewrites them).
    SELECT COALESCE(jsonb_agg(jsonb_build_object('itemId', f.poultryrawmaterialitemid, 'qty', f.quantityconsumed)
                              ORDER BY f.productionrecordfeedid), '[]'::jsonb)
    INTO v_feeds FROM productionrecordfeeds f WHERE f.productionrecordid = p_recordid;
    SELECT COALESCE(jsonb_agg(jsonb_build_object('itemId', m.poultryrawmaterialitemid, 'qty', m.quantityconsumed)
                              ORDER BY m.productionrecordmedicationid), '[]'::jsonb)
    INTO v_meds FROM productionrecordmedications m WHERE m.productionrecordid = p_recordid;

    IF p_delta > 0 THEN
        v_meds := v_meds || jsonb_build_object('itemId', p_itemid, 'qty', p_delta);
    ELSIF p_delta < 0 THEN
        SELECT COALESCE(sum((x->>'qty')::numeric), 0) INTO v_have
        FROM jsonb_array_elements(v_meds) x WHERE (x->>'itemId')::int = p_itemid;
        IF v_have + 0.00005 < -p_delta THEN
            RAISE EXCEPTION 'Record % now has only % of this medication, less than the % being reversed. It was edited after the treatment was posted; adjust it on the record instead.',
                p_recordid, v_have, -p_delta USING ERRCODE = 'P0005';
        END IF;
        -- Take the quantity back from this item's lines, newest line first.
        SELECT COALESCE(jsonb_agg(z.line ORDER BY z.ord), '[]'::jsonb) INTO v_meds
        FROM (
            SELECT w.ord,
                   CASE WHEN (w.line->>'itemId')::int <> p_itemid THEN w.line
                        ELSE jsonb_build_object('itemId', p_itemid,
                             'qty', (w.line->>'qty')::numeric - LEAST((w.line->>'qty')::numeric,
                                    GREATEST(-p_delta - COALESCE(w.takenafter, 0), 0)))
                   END AS line
            FROM (
                SELECT x.line, x.ord,
                       sum(CASE WHEN (x.line->>'itemId')::int = p_itemid THEN (x.line->>'qty')::numeric ELSE 0 END)
                           OVER (ORDER BY x.ord DESC ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS takenafter
                FROM jsonb_array_elements(v_meds) WITH ORDINALITY AS x(line, ord)
            ) w
        ) z
        WHERE (z.line->>'qty')::numeric > 0.00005;
    END IF;

    PERFORM public.spproductionrecord_update(
        p_recordid => r.id, p_updatedby => p_by,
        p_ageinweeks => r.ageinweeks, p_ageindays => r.ageindays, p_date => r.date,
        p_noofbirds => r.noofbirds, p_mortality => r.mortality, p_noofbirdsleft => r.noofbirdsleft,
        p_feedkg => r.feedkg, p_medication => r.medication,
        p_production9am => r.production9am, p_production12pm => r.production12pm, p_production4pm => r.production4pm,
        p_totalproduction => r.totalproduction, p_flockid => r.flockid, p_brokeneggs => r.brokeneggs,
        p_notes => r.notes, p_eggcount => r.eggcount, p_egggrade => r.egggrade,
        p_meatyeggs => r.meatyeggs, p_softeggs => r.softeggs, p_losteggs => r.losteggs,
        p_feedunitcost => r.feedunitcost, p_totalfeedcost => r.totalfeedcost,
        p_medicationunitcost => r.medicationunitcost, p_totalmedicationcost => r.totalmedicationcost,
        p_medicationsjson => v_meds::text,
        p_feedsjson => v_feeds::text);

    IF p_delta > 0 THEN
        -- The campaign's line is the last one the sync wrote for this item.
        SELECT m.unitcost, m.totalcost INTO addedunitcost, addedtotalcost
        FROM productionrecordmedications m
        WHERE m.productionrecordid = p_recordid AND m.poultryrawmaterialitemid = p_itemid
        ORDER BY m.productionrecordmedicationid DESC LIMIT 1;
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 10. Record a day's treatment.
--     p_linesjson: [{flockId, actualQuantity, suggestedQuantity?, notes?}].
--     All flocks or none: any problem raises and nothing moves.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultrytreatmentcampaign_post(integer, text, date, text, text, text);
CREATE FUNCTION public.sppoultrytreatmentcampaign_post(
    p_id           integer,
    p_farmid       text,
    p_businessdate date,
    p_notes        text,
    p_linesjson    text,
    p_postedby     text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
    v_c         record;
    v_available numeric;
    v_total     numeric;
    v_n         integer;
    v_postid    integer;
    v_line      record;
    v_cost      record;
    v_totalcost numeric := 0;
    v_problems  text;
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN RAISE EXCEPTION 'Company ID is required.'; END IF;
    IF p_businessdate IS NULL THEN RAISE EXCEPTION 'A treatment date is required.'; END IF;
    IF p_postedby IS NULL OR btrim(p_postedby) = '' THEN
        -- The consumption expense (266) is not written without a user.
        RAISE EXCEPTION 'The person posting is required.';
    END IF;

    SELECT * INTO v_c FROM poultrytreatmentcampaigns c
    WHERE c.poultrytreatmentcampaignid = p_id AND c.farmid = p_farmid FOR UPDATE;
    IF v_c.poultrytreatmentcampaignid IS NULL THEN RAISE EXCEPTION 'Treatment campaign not found.'; END IF;
    IF v_c.lifecycle <> 'Open' THEN
        RAISE EXCEPTION 'This campaign is %; no more treatment can be recorded on it.', lower(v_c.lifecycle);
    END IF;
    IF p_businessdate > public.fncompany_businessdate(p_farmid) THEN
        RAISE EXCEPTION 'You cannot record treatment for a future date.';
    END IF;
    IF p_businessdate < v_c.startdate OR p_businessdate > v_c.enddate THEN
        RAISE EXCEPTION 'This campaign runs % to %; % is outside it.', v_c.startdate, v_c.enddate, p_businessdate;
    END IF;
    IF EXISTS (SELECT 1 FROM poultrytreatmentcampaignposts p
               WHERE p.poultrytreatmentcampaignid = p_id AND p.businessdate = p_businessdate AND p.status = 'Posted') THEN
        RAISE EXCEPTION 'Treatment for % is already recorded on this campaign. Reverse that posting first to record it again.',
            p_businessdate USING ERRCODE = 'P0006';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM poultryrawmaterialitems i
                   WHERE i.poultryrawmaterialitemid = v_c.poultryrawmaterialitemid AND i.farmid = p_farmid
                     AND COALESCE(i.isactive, TRUE) AND public.fnpoultry_ismedicationcategory(i.category)) THEN
        RAISE EXCEPTION 'The campaign''s medication product is no longer an active medication item.';
    END IF;

    DROP TABLE IF EXISTS tmp_treatpost_lines;
    CREATE TEMP TABLE tmp_treatpost_lines ON COMMIT DROP AS
    SELECT (x->>'flockId')::int AS flockid,
           round((x->>'actualQuantity')::numeric, 4) AS actualquantity,
           round(NULLIF(x->>'suggestedQuantity', '')::numeric, 4) AS suggestedquantity,
           NULLIF(btrim(x->>'notes'), '') AS notes
    FROM jsonb_array_elements(COALESCE(NULLIF(p_linesjson, ''), '[]')::jsonb) x
    WHERE COALESCE((x->>'actualQuantity')::numeric, 0) > 0;

    SELECT count(*), sum(actualquantity) INTO v_n, v_total FROM tmp_treatpost_lines;
    IF v_n = 0 THEN RAISE EXCEPTION 'Enter the quantity given for at least one flock.'; END IF;
    IF EXISTS (SELECT flockid FROM tmp_treatpost_lines GROUP BY flockid HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'A flock appears more than once in this posting.';
    END IF;

    -- Serialise with any other posting of this product, and hold the lots so
    -- an individual production save cannot draw them out from under us.
    PERFORM pg_advisory_xact_lock(hashtext('poultry-medication:' || p_farmid || ':' || v_c.poultryrawmaterialitemid::text));
    PERFORM 1 FROM poultryrawmaterialpurchases p
    WHERE p.farmid = p_farmid AND p.poultryrawmaterialitemid = v_c.poultryrawmaterialitemid FOR UPDATE;

    SELECT a.availablequantity INTO v_available
    FROM public.sppoultrymedication_products(p_farmid) a
    WHERE a.poultryrawmaterialitemid = v_c.poultryrawmaterialitemid;
    IF v_total > COALESCE(v_available, 0) + 0.00005 THEN
        RAISE EXCEPTION 'Not enough % in stock: % available, % to give.',
            v_c.itemname, round(COALESCE(v_available, 0), 4), v_total USING ERRCODE = 'P0003';
    END IF;

    DROP TABLE IF EXISTS tmp_treatpost_grid;
    CREATE TEMP TABLE tmp_treatpost_grid ON COMMIT DROP AS
    SELECT g.* FROM public.sppoultrytreatmentcampaign_daygrid(p_id, p_farmid, p_businessdate) g;

    SELECT string_agg(
               CASE WHEN g.flockid IS NULL THEN format('flock #%s is not on this campaign', l.flockid)
                    WHEN g.isclosed THEN format('%s is closed', g.flockname)
                    WHEN g.recordcount = 0 THEN format('%s has no production record for this date — record production first', g.flockname)
                    WHEN g.recordcount > 1 THEN format('%s has %s production records for this date — fix the duplicate first', g.flockname, g.recordcount)
               END, '; ')
    INTO v_problems
    FROM tmp_treatpost_lines l LEFT JOIN tmp_treatpost_grid g ON g.flockid = l.flockid
    WHERE g.flockid IS NULL OR g.isclosed OR g.recordcount <> 1;
    IF v_problems IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot post: %.', v_problems USING ERRCODE = 'P0004';
    END IF;

    INSERT INTO poultrytreatmentcampaignposts (poultrytreatmentcampaignid, farmid, businessdate, flockcount,
        totalquantity, status, notes, postedby)
    VALUES (p_id, p_farmid, p_businessdate, v_n, v_total, 'Posted', NULLIF(btrim(p_notes), ''), p_postedby)
    RETURNING poultrytreatmentcampaignpostid INTO v_postid;

    FOR v_line IN
        SELECT l.*, g.flockname, g.productionrecordid, g.birds, g.dosequantity, g.dosebasis,
               g.suggestedquantity AS gridsuggested
        FROM tmp_treatpost_lines l JOIN tmp_treatpost_grid g ON g.flockid = l.flockid
        ORDER BY g.flockname, l.flockid
    LOOP
        SELECT * INTO v_cost FROM public.fnpoultrytreatment_changerecordmed(
            p_farmid, v_line.productionrecordid, v_c.poultryrawmaterialitemid, v_line.actualquantity, p_postedby);

        INSERT INTO poultrytreatmentcampaignpostlines (poultrytreatmentcampaignpostid, poultrytreatmentcampaignid,
            farmid, flockid, flockname, productionrecordid, birds, dosequantity, dosebasis,
            suggestedquantity, actualquantity, unitcost, totalcost, notes)
        VALUES (v_postid, p_id, p_farmid, v_line.flockid, v_line.flockname, v_line.productionrecordid, v_line.birds,
                v_line.dosequantity, v_line.dosebasis, COALESCE(v_line.suggestedquantity, v_line.gridsuggested),
                v_line.actualquantity, v_cost.addedunitcost, v_cost.addedtotalcost, v_line.notes);
        v_totalcost := v_totalcost + COALESCE(v_cost.addedtotalcost, 0);
    END LOOP;

    UPDATE poultrytreatmentcampaignposts p SET totalcost = v_totalcost WHERE p.poultrytreatmentcampaignpostid = v_postid;
    RETURN v_postid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 11. Reverse a day's posting. Reason required; the posting stays, marked
--     Reversed, and the doses come off the records through the same update.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultrytreatmentcampaign_reverse(integer, text, text, text);
CREATE FUNCTION public.sppoultrytreatmentcampaign_reverse(
    p_postid integer, p_farmid text, p_reason text, p_reversedby text)
RETURNS void
LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
    v_post record;
    v_item integer;
    v_line record;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a treatment posting.';
    END IF;
    IF p_reversedby IS NULL OR btrim(p_reversedby) = '' THEN
        RAISE EXCEPTION 'The person reversing is required.';
    END IF;

    SELECT * INTO v_post FROM poultrytreatmentcampaignposts p
    WHERE p.poultrytreatmentcampaignpostid = p_postid AND p.farmid = p_farmid FOR UPDATE;
    IF v_post.poultrytreatmentcampaignpostid IS NULL THEN RAISE EXCEPTION 'Treatment posting not found.'; END IF;
    IF v_post.status <> 'Posted' THEN RAISE EXCEPTION 'This treatment posting is already reversed.'; END IF;

    SELECT c.poultryrawmaterialitemid INTO v_item FROM poultrytreatmentcampaigns c
    WHERE c.poultrytreatmentcampaignid = v_post.poultrytreatmentcampaignid;
    PERFORM pg_advisory_xact_lock(hashtext('poultry-medication:' || p_farmid || ':' || v_item::text));

    FOR v_line IN
        SELECT * FROM poultrytreatmentcampaignpostlines l
        WHERE l.poultrytreatmentcampaignpostid = p_postid ORDER BY l.poultrytreatmentcampaignpostlineid
    LOOP
        IF NOT EXISTS (SELECT 1 FROM productionrecords pr WHERE pr.id = v_line.productionrecordid AND pr.farmid = p_farmid) THEN
            -- The record was deleted since: its delete already gave the stock
            -- back (the engine's pure reversal). Nothing left to undo here.
            UPDATE poultrytreatmentcampaignpostlines l
            SET reversalnote = 'Production record was deleted after posting; its stock had already been returned.'
            WHERE l.poultrytreatmentcampaignpostlineid = v_line.poultrytreatmentcampaignpostlineid;
            CONTINUE;
        END IF;
        PERFORM public.fnpoultrytreatment_changerecordmed(
            p_farmid, v_line.productionrecordid, v_item, -v_line.actualquantity, p_reversedby);
    END LOOP;

    UPDATE poultrytreatmentcampaignposts p
    SET status = 'Reversed', reversedby = p_reversedby, reversedatutc = now(), reversalreason = btrim(p_reason)
    WHERE p.poultrytreatmentcampaignpostid = p_postid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 12. Readers.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultrytreatmentcampaign_getall(text, integer);
CREATE FUNCTION public.sppoultrytreatmentcampaign_getall(p_farmid text, p_id integer DEFAULT NULL)
RETURNS TABLE(
    poultrytreatmentcampaignid integer, name text, poultryrawmaterialitemid integer, itemname text,
    unitofmeasure text, reason text, startdate date, enddate date, planneddays integer,
    doseinstructions text, dosequantity numeric, dosebasis text, dosesource text,
    eggwithdrawaldays integer, meatwithdrawaldays integer, withdrawalnotes text, notes text,
    lifecycle text, status text, companytoday date,
    flockcount integer, posteddays integer, totalquantity numeric, totalcost numeric,
    lastposteddate date, eggwithdrawaluntil date, meatwithdrawaluntil date,
    createdby text, createdatutc timestamptz, completedby text, completedatutc timestamptz,
    cancelledby text, cancelledatutc timestamptz, cancelreason text)
LANGUAGE sql
STABLE
AS $function$
    WITH t AS (SELECT public.fncompany_businessdate(p_farmid) AS today),
    live AS (
        SELECT p.poultrytreatmentcampaignid AS cid, count(DISTINCT p.businessdate)::int AS days,
               sum(p.totalquantity) AS qty, sum(p.totalcost) AS cost, max(p.businessdate) AS last
        FROM poultrytreatmentcampaignposts p
        WHERE p.farmid = p_farmid AND p.status = 'Posted'
        GROUP BY p.poultrytreatmentcampaignid
    )
    SELECT c.poultrytreatmentcampaignid, c.name, c.poultryrawmaterialitemid, c.itemname, c.unitofmeasure, c.reason,
           c.startdate, c.enddate, (c.enddate - c.startdate + 1)::int,
           c.doseinstructions, c.dosequantity, c.dosebasis, c.dosesource,
           c.eggwithdrawaldays, c.meatwithdrawaldays, c.withdrawalnotes, c.notes,
           c.lifecycle, public.fnpoultrytreatmentcampaign_status(c.lifecycle, c.startdate, t.today), t.today,
           (SELECT count(*)::int FROM poultrytreatmentcampaignflocks cf WHERE cf.poultrytreatmentcampaignid = c.poultrytreatmentcampaignid),
           COALESCE(live.days, 0), COALESCE(live.qty, 0), live.cost, live.last,
           live.last + c.eggwithdrawaldays, live.last + c.meatwithdrawaldays,
           c.createdby, c.createdatutc, c.completedby, c.completedatutc, c.cancelledby, c.cancelledatutc, c.cancelreason
    FROM poultrytreatmentcampaigns c
    CROSS JOIN t
    LEFT JOIN live ON live.cid = c.poultrytreatmentcampaignid
    WHERE c.farmid = p_farmid AND (p_id IS NULL OR c.poultrytreatmentcampaignid = p_id)
    ORDER BY (c.lifecycle = 'Open') DESC, c.startdate DESC, c.poultrytreatmentcampaignid DESC;
$function$;

DROP FUNCTION IF EXISTS public.sppoultrytreatmentcampaign_flocks(integer, text);
CREATE FUNCTION public.sppoultrytreatmentcampaign_flocks(p_id integer, p_farmid text)
RETURNS TABLE(
    flockid integer, flockname text, housename text, birdsatcreation integer, dosequantity numeric,
    notes text, isclosed boolean, posteddays integer, totalquantity numeric, lastposteddate date)
LANGUAGE sql
STABLE
AS $function$
    SELECT cf.flockid, COALESCE(f.name::text, cf.flockname), h.housename::text, cf.birdsatcreation, cf.dosequantity,
           cf.notes, (f.closeddate IS NOT NULL),
           (SELECT count(DISTINCT p.businessdate)::int FROM poultrytreatmentcampaignpostlines l
            JOIN poultrytreatmentcampaignposts p ON p.poultrytreatmentcampaignpostid = l.poultrytreatmentcampaignpostid
            WHERE l.poultrytreatmentcampaignid = cf.poultrytreatmentcampaignid AND l.flockid = cf.flockid AND p.status = 'Posted'),
           (SELECT COALESCE(sum(l.actualquantity), 0) FROM poultrytreatmentcampaignpostlines l
            JOIN poultrytreatmentcampaignposts p ON p.poultrytreatmentcampaignpostid = l.poultrytreatmentcampaignpostid
            WHERE l.poultrytreatmentcampaignid = cf.poultrytreatmentcampaignid AND l.flockid = cf.flockid AND p.status = 'Posted'),
           (SELECT max(p.businessdate) FROM poultrytreatmentcampaignpostlines l
            JOIN poultrytreatmentcampaignposts p ON p.poultrytreatmentcampaignpostid = l.poultrytreatmentcampaignpostid
            WHERE l.poultrytreatmentcampaignid = cf.poultrytreatmentcampaignid AND l.flockid = cf.flockid AND p.status = 'Posted')
    FROM poultrytreatmentcampaignflocks cf
    LEFT JOIN flock f  ON f.flockid = cf.flockid AND f.farmid = p_farmid
    LEFT JOIN houses h ON h.houseid = f.houseid AND h.farmid = p_farmid
    WHERE cf.poultrytreatmentcampaignid = p_id AND cf.farmid = p_farmid
    ORDER BY cf.poultrytreatmentcampaignflockid;
$function$;

DROP FUNCTION IF EXISTS public.sppoultrytreatmentcampaign_posts(integer, text);
CREATE FUNCTION public.sppoultrytreatmentcampaign_posts(p_id integer, p_farmid text)
RETURNS SETOF public.poultrytreatmentcampaignposts
LANGUAGE sql
STABLE
AS $function$
    SELECT * FROM poultrytreatmentcampaignposts p
    WHERE p.poultrytreatmentcampaignid = p_id AND p.farmid = p_farmid
    ORDER BY p.businessdate DESC, p.poultrytreatmentcampaignpostid DESC;
$function$;

DROP FUNCTION IF EXISTS public.sppoultrytreatmentcampaign_postlines(integer, text);
CREATE FUNCTION public.sppoultrytreatmentcampaign_postlines(p_postid integer, p_farmid text)
RETURNS SETOF public.poultrytreatmentcampaignpostlines
LANGUAGE sql
STABLE
AS $function$
    SELECT * FROM poultrytreatmentcampaignpostlines l
    WHERE l.poultrytreatmentcampaignpostid = p_postid AND l.farmid = p_farmid
    ORDER BY l.poultrytreatmentcampaignpostlineid;
$function$;

-- One flock's treatments from campaigns, newest first -- live and reversed,
-- each with its campaign, so the flock's own history survives the campaign.
DROP FUNCTION IF EXISTS public.sppoultrytreatmentcampaign_flockhistory(text, integer);
CREATE FUNCTION public.sppoultrytreatmentcampaign_flockhistory(p_farmid text, p_flockid integer)
RETURNS TABLE(
    poultrytreatmentcampaignpostlineid integer, poultrytreatmentcampaignpostid integer,
    poultrytreatmentcampaignid integer, campaignname text, reason text, itemname text, unitofmeasure text,
    businessdate date, productionrecordid integer, birds integer, actualquantity numeric, totalcost numeric,
    poststatus text, eggwithdrawaluntil date, meatwithdrawaluntil date, notes text)
LANGUAGE sql
STABLE
AS $function$
    SELECT l.poultrytreatmentcampaignpostlineid, l.poultrytreatmentcampaignpostid, c.poultrytreatmentcampaignid,
           c.name, c.reason, c.itemname, c.unitofmeasure, p.businessdate, l.productionrecordid, l.birds,
           l.actualquantity, l.totalcost, p.status,
           CASE WHEN p.status = 'Posted' THEN p.businessdate + c.eggwithdrawaldays END,
           CASE WHEN p.status = 'Posted' THEN p.businessdate + c.meatwithdrawaldays END,
           l.notes
    FROM poultrytreatmentcampaignpostlines l
    JOIN poultrytreatmentcampaignposts p ON p.poultrytreatmentcampaignpostid = l.poultrytreatmentcampaignpostid
    JOIN poultrytreatmentcampaigns c ON c.poultrytreatmentcampaignid = l.poultrytreatmentcampaignid
    WHERE l.farmid = p_farmid AND l.flockid = p_flockid
    ORDER BY p.businessdate DESC, l.poultrytreatmentcampaignpostlineid DESC;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification. Every fixture is rolled back by the sentinel at the end.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    a   text := '44444444-3333-4333-8333-000000000339';   -- uuid-shaped: expense.farmid is uuid
    b   text := '55555555-3333-4333-8333-000000000339';
    d   date := current_date - 3;                          -- a 3-day window ending yesterday
    v_created timestamp := timestamp '2025-01-01 08:00';
    who text := '__339__';
    med integer; med2 integer; feed integer; medb integer;
    lot1 integer; lot2 integer; lotd integer;
    f1 integer; f2 integer; f3 integer; fb integer;
    r1a integer; r1b integer; r1c integer; r2a integer; r2b integer; r2c integer; rb integer;
    c1 integer; c2 integer; c3 integer;
    p1 integer; p2 integer; p3 integer; p4 integer;
    v_n numeric; v_c numeric;
    rr record;
BEGIN
    BEGIN
        INSERT INTO farms (id, farmid, name, email, type, timezoneid)
        VALUES (a, a, 'Selftest A', 'a@selftest.invalid', 'Poultry', 'UTC'),
               (b, b, 'Selftest B', 'b@selftest.invalid', 'Poultry', 'UTC');

        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, usagemethod)
        VALUES (a, 'Amoxy 20%', 'Medication', 'Litre', 30, TRUE, 'FIFO') RETURNING poultryrawmaterialitemid INTO med;
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, usagemethod)
        VALUES (a, 'Vitamin pack', 'Vaccine', 'Kilogram', 10, TRUE, 'FIFO') RETURNING poultryrawmaterialitemid INTO med2;
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, usagemethod)
        VALUES (a, 'Layer Mash', 'FinishedFeed', 'kg', 100, TRUE, 'FIFO') RETURNING poultryrawmaterialitemid INTO feed;
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, usagemethod)
        VALUES (b, 'B Med', 'Medication', 'Litre', 10, TRUE, 'FIFO') RETURNING poultryrawmaterialitemid INTO medb;

        -- Amoxy: two lots expensed at purchase (cost 10, then 12).
        INSERT INTO poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
            productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod, deferredtotalcost, deferredremainingcost)
        VALUES (a, med, d - 10, 20, 10, 200, 1, 20, 'EXPENSE_WHEN_PURCHASED', 0, 0) RETURNING poultryrawmaterialpurchaseid INTO lot1;
        INSERT INTO poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
            productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod, deferredtotalcost, deferredremainingcost)
        VALUES (a, med, d - 5, 10, 12, 120, 1, 10, 'EXPENSE_WHEN_PURCHASED', 0, 0) RETURNING poultryrawmaterialpurchaseid INTO lot2;
        -- Vitamin pack: one lot expensed when CONSUMED (cost deferred), 5 per kg.
        INSERT INTO poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
            productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod, deferredtotalcost, deferredremainingcost)
        VALUES (a, med2, d - 5, 10, 5, 50, 1, 10, 'EXPENSE_WHEN_CONSUMED', 50, 50) RETURNING poultryrawmaterialpurchaseid INTO lotd;
        INSERT INTO poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
            productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod, deferredtotalcost, deferredremainingcost)
        VALUES (b, medb, d - 5, 10, 1, 10, 1, 10, 'EXPENSE_WHEN_PURCHASED', 0, 0);

        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'F1', d - 60, 'Brown', 1000, TRUE, TRUE, -339, v_created) RETURNING flockid INTO f1;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'F2', d - 60, 'Brown', 2000, TRUE, TRUE, -339, v_created) RETURNING flockid INTO f2;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'F3 no record', d - 60, 'Brown', 500, TRUE, TRUE, -339, v_created) RETURNING flockid INTO f3;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, b, 'B1', d - 60, 'Brown', 100, TRUE, TRUE, -339, v_created) RETURNING flockid INTO fb;

        -- F1 / F2: a record on each of the 3 days. F1's first record already
        -- has a FEED line, which must survive the medication posting.
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (a, who, who, 30, 210, d, 1000, 0, 1000, 5, 1, 1, 1, 3, f1, 'ManualSingleFlock', now()) RETURNING id INTO r1a;
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (a, who, who, 30, 211, d + 1, 1000, 0, 1000, 0, 1, 1, 1, 3, f1, 'ManualSingleFlock', now()) RETURNING id INTO r1b;
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (a, who, who, 30, 212, d + 2, 1000, 0, 1000, 0, 1, 1, 1, 3, f1, 'ManualSingleFlock', now()) RETURNING id INTO r1c;
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (a, who, who, 30, 210, d, 2000, 0, 2000, 0, 1, 1, 1, 3, f2, 'ManualSingleFlock', now()) RETURNING id INTO r2a;
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (a, who, who, 30, 211, d + 1, 2000, 0, 2000, 0, 1, 1, 1, 3, f2, 'ManualSingleFlock', now()) RETURNING id INTO r2b;
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (a, who, who, 30, 212, d + 2, 2000, 0, 2000, 0, 1, 1, 1, 3, f2, 'ManualSingleFlock', now()) RETURNING id INTO r2c;
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (b, who, who, 30, 210, d, 100, 0, 100, 0, 1, 1, 1, 3, fb, 'ManualSingleFlock', now()) RETURNING id INTO rb;
        INSERT INTO poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
            productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod, deferredtotalcost, deferredremainingcost)
        VALUES (a, feed, d - 5, 100, 2, 200, 1, 100, 'EXPENSE_WHEN_PURCHASED', 0, 0);
        PERFORM public.spproductionrecord_update(p_recordid => r1a, p_updatedby => who,
            p_ageinweeks => 30, p_ageindays => 210, p_date => d, p_noofbirds => 1000, p_mortality => 0,
            p_noofbirdsleft => 1000, p_feedkg => 5, p_production9am => 1, p_production12pm => 1, p_production4pm => 1,
            p_totalproduction => 3, p_flockid => f1, p_medicationsjson => '[]',
            p_feedsjson => json_build_array(json_build_object('itemId', feed, 'qty', 5))::text);

        -- ---- Products: only medication categories; isolation ------------------
        IF NOT EXISTS (SELECT 1 FROM public.sppoultrymedication_products(a) x WHERE x.poultryrawmaterialitemid = med)
           OR NOT EXISTS (SELECT 1 FROM public.sppoultrymedication_products(a) x WHERE x.poultryrawmaterialitemid = med2)
           OR EXISTS (SELECT 1 FROM public.sppoultrymedication_products(a) x WHERE x.poultryrawmaterialitemid IN (feed, medb)) THEN
            RAISE EXCEPTION '339: product list should be the medication / vaccine items of this company only.';
        END IF;
        IF (SELECT x.availablequantity FROM public.sppoultrymedication_products(a) x WHERE x.poultryrawmaterialitemid = med) <> 30 THEN
            RAISE EXCEPTION '339: Amoxy availability should be the lots'' 30.';
        END IF;
        -- No saved figure = no dose, no withdrawal. Nothing is assumed.
        IF (SELECT x.dosequantity FROM public.sppoultrymedication_products(a) x WHERE x.poultryrawmaterialitemid = med) IS NOT NULL THEN
            RAISE EXCEPTION '339: a dose appeared without anyone configuring one.';
        END IF;
        PERFORM public.sppoultrymedication_setproductsettings(a, med, 0.5, 'Per1000Birds', 7, 14, 'Per label', who);
        SELECT * INTO rr FROM public.sppoultrymedication_products(a) x WHERE x.poultryrawmaterialitemid = med;
        IF rr.dosequantity <> 0.5 OR rr.dosebasis <> 'Per1000Birds' OR rr.eggwithdrawaldays <> 7 THEN
            RAISE EXCEPTION '339: product settings not saved: %', rr;
        END IF;
        BEGIN
            PERFORM public.sppoultrymedication_setproductsettings(a, feed, 1, 'PerBird', NULL, NULL, NULL, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: saved a dose on a feed product.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- ---- Create: category guard, isolation, closed flock -----------------
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_create(a, 'Bad', feed, NULL, d, d, NULL, NULL, NULL, NULL,
                NULL, NULL, NULL, NULL, json_build_array(json_build_object('flockId', f1))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: created a campaign for a feed product.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_create(a, 'Bad', medb, NULL, d, d, NULL, NULL, NULL, NULL,
                NULL, NULL, NULL, NULL, json_build_array(json_build_object('flockId', f1))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: used another company''s medication.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_create(a, 'Bad', med, NULL, d, d, NULL, NULL, NULL, NULL,
                NULL, NULL, NULL, NULL, json_build_array(json_build_object('flockId', fb))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: put another company''s flock on a campaign.';
        EXCEPTION WHEN SQLSTATE 'P0004' THEN NULL;
        END;

        -- ---- One flock, one day ----------------------------------------------
        c1 := public.sppoultrytreatmentcampaign_create(a, 'Coccidiosis F1', med, 'Bloody droppings', d, d, 'As label',
            2, 'PerFlock', 'User', 3, NULL, NULL, NULL,
            json_build_array(json_build_object('flockId', f1))::text, who);
        IF (SELECT status FROM public.sppoultrytreatmentcampaign_getall(a, c1)) <> 'InProgress' THEN
            RAISE EXCEPTION '339: a campaign that started in the past should be In Progress.';
        END IF;
        -- Creating moves no stock.
        IF (SELECT currentquantity FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = med) <> 30 THEN
            RAISE EXCEPTION '339: creating a campaign moved stock.';
        END IF;
        SELECT * INTO rr FROM public.sppoultrytreatmentcampaign_daygrid(c1, a, d) g;
        IF rr.recordcount <> 1 OR rr.productionrecordid <> r1a OR rr.suggestedquantity <> 2 OR rr.birds <> 1000 THEN
            RAISE EXCEPTION '339: one-flock grid wrong: %', rr;
        END IF;
        p1 := public.sppoultrytreatmentcampaign_post(c1, a, d, NULL,
            json_build_array(json_build_object('flockId', f1, 'actualQuantity', 2, 'suggestedQuantity', 2))::text, who);
        SELECT * INTO rr FROM productionrecordmedications m WHERE m.productionrecordid = r1a;
        IF rr.quantityconsumed <> 2 OR rr.unitcost <> 10 OR rr.poultryrawmaterialitemid <> med THEN
            RAISE EXCEPTION '339: F1 should have one 2 L medication line at the FIFO cost 10: %', rr;
        END IF;
        IF (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = lot1) <> 18
           OR (SELECT currentquantity FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = med) <> 28 THEN
            RAISE EXCEPTION '339: one-flock stock wrong.';
        END IF;
        -- The record's feed line and feed kg survive the medication posting.
        IF (SELECT sum(quantityconsumed) FROM productionrecordfeeds WHERE productionrecordid = r1a) <> 5
           OR (SELECT feedkg FROM productionrecords WHERE id = r1a) <> 5 THEN
            RAISE EXCEPTION '339: posting medication disturbed the record''s feed.';
        END IF;
        -- Medication expensed at purchase: no consumption expense.
        IF EXISTS (SELECT 1 FROM expense e WHERE e.sourcetype = 'PoultryMedicationConsumption' AND e.sourceid = r1a) THEN
            RAISE EXCEPTION '339: medication expensed at purchase was expensed again at consumption.';
        END IF;
        -- Same day twice: refused.
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_post(c1, a, d, NULL,
                json_build_array(json_build_object('flockId', f1, 'actualQuantity', 2))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: posted the same day twice.';
        EXCEPTION WHEN SQLSTATE 'P0006' THEN NULL;
        END;

        -- ---- Many flocks, multi-day, per-bird dose -----------------------------
        c2 := public.sppoultrytreatmentcampaign_create(a, '3-day vitamins', med2, 'Heat stress', d, d + 2, NULL,
            1, 'Per1000Birds', 'User', NULL, NULL, NULL, 'whole farm',
            json_build_array(json_build_object('flockId', f1),
                             json_build_object('flockId', f2, 'doseQuantity', 1.5),
                             json_build_object('flockId', f3))::text, who);
        IF (SELECT flockcount FROM public.sppoultrytreatmentcampaign_getall(a, c2)) <> 3 THEN
            RAISE EXCEPTION '339: campaign flocks not saved.';
        END IF;
        -- F2 has its own dose: 1.5 per 1,000 x 2,000 birds = 3.
        IF (SELECT g.suggestedquantity FROM public.sppoultrytreatmentcampaign_daygrid(c2, a, d) g WHERE g.flockid = f2) <> 3
           OR (SELECT g.suggestedquantity FROM public.sppoultrytreatmentcampaign_daygrid(c2, a, d) g WHERE g.flockid = f1) <> 1 THEN
            RAISE EXCEPTION '339: per-1,000-bird suggestions wrong.';
        END IF;
        -- Day 1 for F1 + F2; F3 (no record) is refused if included.
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_post(c2, a, d, NULL,
                json_build_array(json_build_object('flockId', f1, 'actualQuantity', 1),
                                 json_build_object('flockId', f3, 'actualQuantity', 1))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: dosed a flock with no production record.';
        EXCEPTION WHEN SQLSTATE 'P0004' THEN NULL;
        END;
        IF (SELECT count(*) FROM productionrecordmedications WHERE productionrecordid = r1a AND poultryrawmaterialitemid = med2) <> 0 THEN
            RAISE EXCEPTION '339: a refused posting moved stock (not atomic).';
        END IF;
        p2 := public.sppoultrytreatmentcampaign_post(c2, a, d, 'day 1',
            json_build_array(json_build_object('flockId', f1, 'actualQuantity', 1),
                             json_build_object('flockId', f2, 'actualQuantity', 3))::text, who);
        p3 := public.sppoultrytreatmentcampaign_post(c2, a, d + 1, 'day 2',
            json_build_array(json_build_object('flockId', f1, 'actualQuantity', 1),
                             json_build_object('flockId', f2, 'actualQuantity', 3))::text, who);
        -- Two of three days posted: only those doses left stock; day 3 nothing.
        IF (SELECT currentquantity FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = med2) <> 2
           OR EXISTS (SELECT 1 FROM productionrecordmedications WHERE productionrecordid IN (r1c, r2c)) THEN
            RAISE EXCEPTION '339: future days were consumed, or stock wrong after two days.';
        END IF;
        SELECT * INTO rr FROM public.sppoultrytreatmentcampaign_getall(a, c2);
        IF rr.posteddays <> 2 OR rr.totalquantity <> 8 OR rr.status <> 'InProgress' THEN
            RAISE EXCEPTION '339: campaign progress wrong: %', rr;
        END IF;
        -- Consumption recognition: deferred lot, 5 per kg -> 1 kg on F1 day 1 = 5.
        SELECT COALESCE(sum(e.amount), 0) INTO v_c FROM expense e
        WHERE e.sourcetype = 'PoultryMedicationConsumption' AND e.sourceid = r1a AND e.paymentmethod = 'NonCash';
        IF v_c <> 5 THEN
            RAISE EXCEPTION '339: 1 kg of deferred medication at 5 should recognise 5, got %.', v_c;
        END IF;
        IF (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = lotd) <> 10 THEN
            RAISE EXCEPTION '339: the lot''s deferred cost should drop to 10 after 8 kg.';
        END IF;
        -- F1's day-1 record now holds BOTH medications and its feed.
        IF (SELECT count(*) FROM productionrecordmedications WHERE productionrecordid = r1a) <> 2
           OR (SELECT sum(quantityconsumed) FROM productionrecordfeeds WHERE productionrecordid = r1a) <> 5 THEN
            RAISE EXCEPTION '339: a second campaign on the same record lost a line.';
        END IF;

        -- ---- Insufficient stock: refused, nothing moves -----------------------
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_post(c2, a, d + 2, NULL,
                json_build_array(json_build_object('flockId', f1, 'actualQuantity', 1),
                                 json_build_object('flockId', f2, 'actualQuantity', 3))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: gave more than the lots hold.';
        EXCEPTION WHEN SQLSTATE 'P0003' THEN NULL;
        END;
        IF EXISTS (SELECT 1 FROM productionrecordmedications WHERE productionrecordid IN (r1c, r2c))
           OR EXISTS (SELECT 1 FROM poultrytreatmentcampaignposts WHERE poultrytreatmentcampaignid = c2 AND businessdate = d + 2) THEN
            RAISE EXCEPTION '339: a refused posting left something behind.';
        END IF;

        -- ---- Outside the window / future: refused -----------------------------
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_post(c2, a, d - 1, NULL,
                json_build_array(json_build_object('flockId', f1, 'actualQuantity', 1))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: posted before the campaign started.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- ---- Reversal ---------------------------------------------------------
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_reverse(p3, a, '  ', who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: reversed without a reason.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_reverse(p3, b, 'not mine', who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: another company reversed it.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        PERFORM public.sppoultrytreatmentcampaign_reverse(p2, a, 'Wrong day', who);
        IF (SELECT currentquantity FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = med2) <> 6
           OR (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = lotd) <> 6
           OR EXISTS (SELECT 1 FROM productionrecordmedications WHERE productionrecordid IN (r1a, r2a) AND poultryrawmaterialitemid = med2) THEN
            RAISE EXCEPTION '339: reversal did not restore the lot / remove the lines.';
        END IF;
        -- The expense nets to zero through an opposite row; nothing deleted.
        SELECT COALESCE(sum(e.amount), 0), count(*) INTO v_c, v_n FROM expense e
        WHERE e.sourcetype = 'PoultryMedicationConsumption' AND e.sourceid = r1a;
        IF v_c <> 0 OR v_n < 2 THEN
            RAISE EXCEPTION '339: reversed consumption expense should net to 0 through an opposite row (net %, rows %).', v_c, v_n;
        END IF;
        -- Amoxy (campaign 1) on the same record is untouched by reversing campaign 2.
        IF (SELECT quantityconsumed FROM productionrecordmedications WHERE productionrecordid = r1a AND poultryrawmaterialitemid = med) <> 2 THEN
            RAISE EXCEPTION '339: reversing one campaign removed another campaign''s dose.';
        END IF;
        IF (SELECT status FROM poultrytreatmentcampaignposts WHERE poultrytreatmentcampaignpostid = p2) <> 'Reversed' THEN
            RAISE EXCEPTION '339: posting not marked Reversed.';
        END IF;
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_reverse(p2, a, 'again', who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: reversed twice.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        -- A reversed day can be posted again (the unique index is on LIVE posts).
        p4 := public.sppoultrytreatmentcampaign_post(c2, a, d, 'day 1 again',
            json_build_array(json_build_object('flockId', f2, 'actualQuantity', 3))::text, who);

        -- ---- Flock history ----------------------------------------------------
        IF (SELECT count(*) FROM public.sppoultrytreatmentcampaign_flockhistory(a, f2)) <> 3
           OR (SELECT count(*) FROM public.sppoultrytreatmentcampaign_flockhistory(a, f2) h WHERE h.poststatus = 'Reversed') <> 1
           OR EXISTS (SELECT 1 FROM public.sppoultrytreatmentcampaign_flockhistory(b, f2)) THEN
            RAISE EXCEPTION '339: F2 history should show its 3 doses (1 reversed), and only to its own company.';
        END IF;
        IF (SELECT h.eggwithdrawaluntil FROM public.sppoultrytreatmentcampaign_flockhistory(a, f1) h
            WHERE h.poultrytreatmentcampaignid = c1) <> d + 3 THEN
            RAISE EXCEPTION '339: egg withdrawal should run 3 days from the dose.';
        END IF;

        -- ---- Cancellation -----------------------------------------------------
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_cancel(c2, a, '', who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: cancelled without a reason.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        PERFORM public.sppoultrytreatmentcampaign_cancel(c2, a, 'Vet changed the treatment', who);
        SELECT * INTO rr FROM public.sppoultrytreatmentcampaign_getall(a, c2);
        IF rr.status <> 'Cancelled' OR rr.posteddays <> 2 THEN
            RAISE EXCEPTION '339: cancelling should keep the doses already given: %', rr;
        END IF;
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_post(c2, a, d + 2, NULL,
                json_build_array(json_build_object('flockId', f1, 'actualQuantity', 0.5))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: posted on a cancelled campaign.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- ---- Completion / scheduled -------------------------------------------
        PERFORM public.sppoultrytreatmentcampaign_complete(c1, a, who);
        IF (SELECT status FROM public.sppoultrytreatmentcampaign_getall(a, c1)) <> 'Completed' THEN
            RAISE EXCEPTION '339: campaign not completed.';
        END IF;
        c3 := public.sppoultrytreatmentcampaign_create(a, 'Next week', med, NULL, current_date + 7, current_date + 9, NULL,
            NULL, NULL, NULL, NULL, NULL, NULL, NULL, json_build_array(json_build_object('flockId', f1))::text, who);
        IF (SELECT status FROM public.sppoultrytreatmentcampaign_getall(a, c3)) <> 'Scheduled' THEN
            RAISE EXCEPTION '339: a future campaign should be Scheduled.';
        END IF;
        IF (SELECT g.suggestedquantity FROM public.sppoultrytreatmentcampaign_daygrid(c3, a, current_date) g) IS NOT NULL THEN
            RAISE EXCEPTION '339: a campaign with no dose figure suggested a quantity.';
        END IF;

        -- ---- Company isolation on readers ------------------------------------
        IF EXISTS (SELECT 1 FROM public.sppoultrytreatmentcampaign_getall(b))
           OR EXISTS (SELECT 1 FROM public.sppoultrytreatmentcampaign_flocks(c2, b))
           OR EXISTS (SELECT 1 FROM public.sppoultrytreatmentcampaign_posts(c2, b))
           OR EXISTS (SELECT 1 FROM public.sppoultrytreatmentcampaign_daygrid(c2, b, d)) THEN
            RAISE EXCEPTION '339: another company can read this company''s campaigns.';
        END IF;
        BEGIN
            PERFORM public.sppoultrytreatmentcampaign_post(c3, b, current_date, NULL,
                json_build_array(json_build_object('flockId', fb, 'actualQuantity', 1))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: another company posted on this campaign.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- ---- Append-only ------------------------------------------------------
        BEGIN
            DELETE FROM poultrytreatmentcampaigns WHERE poultrytreatmentcampaignid = c1;
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: a campaign could be deleted.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        BEGIN
            DELETE FROM poultrytreatmentcampaignposts WHERE poultrytreatmentcampaignpostid = p1;
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '339: a posting could be deleted.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '__339_ok__';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;
    END;

    RAISE NOTICE '339_PoultryTreatmentCampaigns: verified (products, no assumed dose, one flock, many flocks, multi-day, nothing consumed ahead, per-flock dose, production first, atomic, insufficient stock, window, same-day guard, feed lines kept, purchase & consumption recognition, reversal, re-post, history, withdrawal, cancellation, completion, scheduled, isolation, append-only).';
END $$;

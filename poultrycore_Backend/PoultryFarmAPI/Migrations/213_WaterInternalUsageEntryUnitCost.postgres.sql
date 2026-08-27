-- =============================================================================
-- 213_WaterInternalUsageEntryUnitCost.postgres.sql
--
-- Symptom
-- -------
-- Internal Use asked for the cost per SACHET even when the user was giving out
-- BAGS. Nobody prices sachet water that way -- a bag costs GHC 9.00, and the
-- person recording it should be able to type 9.00. Dividing by 30 in your head
-- at data-entry time is exactly how a wrong number gets into the ledger.
--
-- Cause
-- -----
-- Migration 212 stored a single `unitcost` in BASE units (sachets) because that
-- is the unit stock is summed in. Two problems fell out of that:
--
--   1. The form had to ask for a per-sachet figure, which is not how the
--      business thinks or how the price list is written.
--
--   2. Rounding drift. A GHC 10.00 bag is 0.333333... per sachet, stored as
--      0.3333 in numeric(14,4). 100 bags = 3,000 sachets then costs
--      3000 * 0.3333 = GHC 999.90 instead of GHC 1,000.00. Ten pesewas per
--      hundred bags, silently, in every expense and report.
--
-- It was also inconsistent with the rest of the water module: migration 067
-- writes @CostPerBag straight into waterstocktransactions.unitcost (067:592),
-- so on that table `unitcost` has always meant "per entry unit", while 212 was
-- writing per-sachet into the same column.
--
-- Fix
-- ---
--   * Store entryunitcost -- what the user actually typed, in the unit they
--     typed it in. Same principle as entryquantity/entryunit/unitsperentryunit:
--     snapshot the input, derive the rest.
--   * totalcost = entryquantity * entryunitcost. Multiplication only, so the
--     division drift disappears.
--   * unitcost stays, derived as entryunitcost / unitsperentryunit, because a
--     per-sachet figure is still the useful one for stock valuation reporting.
--   * The stock ledger now receives entryunitcost, matching migration 067.
--
-- Scope: waterinternalusageitems + three functions. No data exists yet in
-- practice, but the backfill is written to be correct if any does.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE, delta-free backfill.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The column, and a backfill for anything already recorded.
-- -----------------------------------------------------------------------------
ALTER TABLE waterinternalusageitems
    ADD COLUMN IF NOT EXISTS entryunitcost numeric(14,4) NOT NULL DEFAULT 0;

-- Recover the entry-unit figure from what 212 stored. Runs once; afterwards
-- every row already has a non-zero entryunitcost wherever unitcost was non-zero.
UPDATE waterinternalusageitems
SET    entryunitcost = ROUND(unitcost * GREATEST(unitsperentryunit, 1), 4)
WHERE  entryunitcost = 0 AND unitcost <> 0;

-- -----------------------------------------------------------------------------
-- 2. Items are written with the cost in the unit the user chose.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterinternalusage_replaceitems(
    p_waterinternalusageid integer, p_farmid text, p_itemsjson text)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    DELETE FROM waterinternalusageitems WHERE waterinternalusageid = p_waterinternalusageid;

    IF p_itemsjson IS NULL OR btrim(p_itemsjson) IN ('', '[]') THEN
        RETURN;
    END IF;

    INSERT INTO waterinternalusageitems (
        waterinternalusageid, farmid, waterproductid, entryquantity, entryunit,
        unitsperentryunit, stockquantity, quantityperstaff,
        entryunitcost, unitcost, totalcost, itemnotes)
    SELECT p_waterinternalusageid,
           p_farmid,
           j.waterproductid,
           j.entryquantity,
           COALESCE(NULLIF(btrim(j.entryunit), ''), COALESCE(p.baseunit, p.unit)),
           v.factor,
           ROUND(j.entryquantity * v.factor, 3),
           j.quantityperstaff,
           COALESCE(j.entryunitcost, 0),
           -- Derived, for per-sachet valuation reporting. Never the other way
           -- round: entryunitcost is the figure the user stands behind.
           ROUND(COALESCE(j.entryunitcost, 0) / GREATEST(v.factor, 0.000001), 4),
           -- Multiplication only -- see the header note on rounding drift.
           ROUND(j.entryquantity * COALESCE(j.entryunitcost, 0), 2),
           j.itemnotes
    FROM   json_to_recordset(p_itemsjson::json) AS j(
               waterproductid   integer,
               entryquantity    numeric,
               entryunit        text,
               quantityperstaff numeric,
               entryunitcost    numeric,
               itemnotes        text)
    LEFT   JOIN waterproducts p ON p.waterproductid = j.waterproductid
    CROSS  JOIN LATERAL (
        SELECT CASE
                 WHEN lower(COALESCE(j.entryunit, '')) = 'bag'
                 THEN GREATEST(COALESCE(p.sachetsperbag, 30), 1)::numeric
                 ELSE 1::numeric
               END AS factor
    ) v
    WHERE  j.waterproductid IS NOT NULL
      AND  COALESCE(j.entryquantity, 0) > 0;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Posting: cost the lines from the entry-unit figure.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterinternalusage_post(
    p_waterinternalusageid integer, p_farmid text, p_postedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status  text;
    v_total   numeric(14,2) := 0;
    v_net     numeric(14,3);
    v_delta   numeric(14,3);
    v_onhand  numeric(14,3);
    v_catid   integer;
    r         record;
BEGIN
    SELECT h.status INTO v_status FROM waterinternalusage h
    WHERE  h.waterinternalusageid = p_waterinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Internal use record % not found.', p_waterinternalusageid;
    END IF;
    IF v_status = 'Posted' THEN RETURN; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Cannot post a % record.', v_status;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM waterinternalusageitems
                   WHERE waterinternalusageid = p_waterinternalusageid) THEN
        RAISE EXCEPTION 'Add at least one product before posting.';
    END IF;

    -- Fill in a cost for any line the user left blank, in the ENTRY unit, from
    -- the weighted average (which is per base unit -- scale it back up).
    UPDATE waterinternalusageitems i
    SET    entryunitcost = ROUND(
               public.fnwaterproductavgcost(p_farmid, i.waterproductid)
               * GREATEST(i.unitsperentryunit, 1), 4)
    WHERE  i.waterinternalusageid = p_waterinternalusageid
      AND  i.entryunitcost = 0;

    UPDATE waterinternalusageitems
    SET    unitcost  = ROUND(entryunitcost / GREATEST(unitsperentryunit, 0.000001), 4),
           totalcost = ROUND(entryquantity * entryunitcost, 2)
    WHERE  waterinternalusageid = p_waterinternalusageid;

    -- Pre-flight: never post a record that would drive a product negative.
    FOR r IN SELECT i.*, p.name AS productname
             FROM   waterinternalusageitems i
             LEFT   JOIN waterproducts p ON p.waterproductid = i.waterproductid
             WHERE  i.waterinternalusageid = p_waterinternalusageid
    LOOP
        SELECT COALESCE(SUM(COALESCE(st.basequantity, st.quantity)), 0) INTO v_onhand
        FROM   waterstocktransactions st
        WHERE  st.farmid = p_farmid AND st.waterproductid = r.waterproductid;

        IF r.stockquantity > v_onhand THEN
            RAISE EXCEPTION 'Not enough %: % in stock, % needed.',
                COALESCE(r.productname, 'product ' || r.waterproductid), v_onhand, r.stockquantity;
        END IF;
    END LOOP;

    FOR r IN SELECT * FROM waterinternalusageitems
             WHERE waterinternalusageid = p_waterinternalusageid
    LOOP
        -- Migration 179's delta rule; see 212 for the full note.
        SELECT COALESCE(SUM(COALESCE(st.basequantity, st.quantity)), 0) INTO v_net
        FROM   waterstocktransactions st
        WHERE  st.farmid = p_farmid
          AND  st.txntype = 'InternalUse'
          AND  st.relatedid = p_waterinternalusageid
          AND  st.waterproductid = r.waterproductid;

        v_delta := (-r.stockquantity) - v_net;

        IF v_delta <> 0 THEN
            INSERT INTO waterstocktransactions
                (farmid, waterproductid, txntype, quantity, basequantity, unitcost,
                 relatedid, note, createdby)
            VALUES (p_farmid, r.waterproductid, 'InternalUse',
                    ROUND(v_delta / GREATEST(r.unitsperentryunit, 0.000001))::integer,
                    v_delta,
                    -- Per ENTRY unit, matching migration 067's @CostPerBag.
                    NULLIF(r.entryunitcost, 0),
                    p_waterinternalusageid,
                    'Internal use ' || COALESCE(
                        (SELECT referenceno FROM waterinternalusage
                         WHERE waterinternalusageid = p_waterinternalusageid),
                        '#' || p_waterinternalusageid::text),
                    p_postedby);
        END IF;
    END LOOP;

    SELECT COALESCE(SUM(totalcost), 0) INTO v_total
    FROM   waterinternalusageitems WHERE waterinternalusageid = p_waterinternalusageid;

    UPDATE waterinternalusage
    SET    status = 'Posted', totalcostvalue = v_total,
           postedby = p_postedby, postedat = (now() at time zone 'utc'),
           updatedat = (now() at time zone 'utc')
    WHERE  waterinternalusageid = p_waterinternalusageid AND farmid = p_farmid;

    -- Linked non-cash expense. See 212 for why this never touches cash.
    IF v_total > 0 AND NOT EXISTS (
        SELECT 1 FROM waterexpenses e
        WHERE  e.farmid = p_farmid
          AND  e.sourcetype = 'WaterInternalUsage'
          AND  e.sourceid = p_waterinternalusageid
          AND  COALESCE(e.isdeleted, FALSE) = FALSE)
    THEN
        v_catid := public.spwaterexpensecategory_ensureinternaluse(p_farmid);

        INSERT INTO waterexpenses (farmid, expensedate, waterexpensecategoryid, description,
                                   amount, paymentmethod, watercashaccountid, status,
                                   notes, createdby, approvedby, approvedat,
                                   sourcetype, sourceid)
        SELECT p_farmid, h.usagedate, v_catid,
               'Internal use: ' || h.category || COALESCE(' - ' || h.recipientname, ''),
               v_total, 'Credit', NULL, 'Approved',
               'Non-cash: stock consumed internally (' || COALESCE(h.referenceno, '#' || h.waterinternalusageid::text) || ').',
               COALESCE(p_postedby, h.createdby), COALESCE(p_postedby, h.createdby),
               (now() at time zone 'utc'),
               'WaterInternalUsage', p_waterinternalusageid
        FROM   waterinternalusage h
        WHERE  h.waterinternalusageid = p_waterinternalusageid;
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Expose entryunitcost on the read path.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterinternalusage_getall(
    p_farmid   text,
    p_status   text      DEFAULT NULL,
    p_category text      DEFAULT NULL,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE(
    waterinternalusageid integer, farmid text, usagedate timestamp, referenceno text,
    category text, reason text, recipientname text, responsiblestaffid integer,
    staffcount integer, status text, totalcostvalue numeric, notes text,
    postedby text, postedat timestamp, reversedby text, reversedat timestamp,
    reversalreason text, createdby text, createdat timestamp, updatedat timestamp,
    itemsjson text)
LANGUAGE sql
STABLE
AS $$
    SELECT h.waterinternalusageid, h.farmid, h.usagedate, h.referenceno,
           h.category, h.reason, h.recipientname, h.responsiblestaffid,
           h.staffcount, h.status, h.totalcostvalue, h.notes,
           h.postedby, h.postedat, h.reversedby, h.reversedat,
           h.reversalreason, h.createdby, h.createdat, h.updatedat,
           COALESCE((
               SELECT json_agg(json_build_object(
                          'waterInternalUsageItemId', i.waterinternalusageitemid,
                          'waterProductId',           i.waterproductid,
                          'productName',              p.name,
                          'entryQuantity',            i.entryquantity,
                          'entryUnit',                i.entryunit,
                          'unitsPerEntryUnit',        i.unitsperentryunit,
                          'stockQuantity',            i.stockquantity,
                          'quantityPerStaff',         i.quantityperstaff,
                          'entryUnitCost',            i.entryunitcost,
                          'unitCost',                 i.unitcost,
                          'totalCost',                i.totalcost,
                          'itemNotes',                i.itemnotes)
                      ORDER BY i.waterinternalusageitemid)::text
               FROM   waterinternalusageitems i
               LEFT   JOIN waterproducts p ON p.waterproductid = i.waterproductid
               WHERE  i.waterinternalusageid = h.waterinternalusageid
           ), '[]') AS itemsjson
    FROM   waterinternalusage h
    WHERE  h.farmid = p_farmid
      AND  (p_status   IS NULL OR h.status   = p_status)
      AND  (p_category IS NULL OR h.category = p_category)
      AND  (p_fromdate IS NULL OR h.usagedate >= p_fromdate)
      AND  (p_todate   IS NULL OR h.usagedate <  (p_todate + interval '1 day'))
    ORDER  BY h.usagedate DESC, h.waterinternalusageid DESC;
$$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'entryunitcost column' AS check,
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_name='waterinternalusageitems' AND column_name='entryunitcost')
            THEN 'OK' ELSE 'MISSING' END AS result
UNION ALL
SELECT 'post uses entryunitcost',
       CASE WHEN (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
                  JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='spwaterinternalusage_post')
                 LIKE '%entryunitcost%'
            THEN 'OK' ELSE 'NOT APPLIED' END
UNION ALL
SELECT 'read path exposes it',
       CASE WHEN (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
                  JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE n.nspname='public' AND p.proname='spwaterinternalusage_getall')
                 LIKE '%entryUnitCost%'
            THEN 'OK' ELSE 'NOT APPLIED' END;

-- =============================================================================
-- 212_WaterInternalUsage.postgres.sql
--
-- Purpose
-- -------
-- "Internal Use": stock a water company intentionally consumes rather than
-- sells -- staff water allowance, owner use, office refreshment, samples,
-- donations, quality testing.
--
-- Until now there was nowhere to record this. Companies either booked it as a
-- loss (wrong: nothing was damaged, and it pollutes Damages & Loss reporting),
-- as a zero-price sale (wrong: invents a customer and distorts revenue), or not
-- at all (worst: stock silently drifts from reality and nobody can see what
-- internal consumption costs).
--
-- Design
-- ------
-- An Internal Use record is a costed, reversible stock reduction that creates an
-- expense and touches nothing else. Explicitly it must NOT create a sale, a
-- customer balance, a payment, or a cash transaction -- the cash left the
-- business when the stock was bought or produced, not now.
--
--   0. waterstocktransactions.relatedid -- correlation column for non-sale
--      sources. NOT relatedsaleid: a non-NULL value there pointing at a sale
--      that does not exist would confuse every sales report.
--   1. waterinternalusage / waterinternalusageitems -- header + items. Internal
--      use is realistically a basket, and both the expense link and the reversal
--      need a single id to hang off.
--   2. fnwaterproductavgcost -- weighted average cost per BASE unit (sachet).
--   3. spwaterexpensecategory_ensureinternaluse -- lazy category seed, so no
--      global data migration is needed and new farms get it on first use
--      (the pattern migration 075 established for payroll).
--   4. spwaterinternalusage_* -- getall, getbyid, insert, update, delete, post,
--      reverse.
--   5. The daily-closing exclusion (see below).
--   6. IAM catalog rows.
--
-- Stock arithmetic
-- ----------------
-- Water stock is summed in BASE units (sachets), never bags -- see migration
-- 084, which added basequantity and made spWaterSale_CreateV2 validate against
-- SUM(basequantity). So:
--
--     basequantity = the truth, always signed, always in base units
--     quantity     = the entry-unit figure (bags), for display only; it is an
--                    INT column, so it is rounded
--
-- Posting and reversal follow the append-only rule migration 179 laid down:
-- compute the NET already posted for this (txntype, relatedid, product), then
-- post the DELTA needed to reach the target. Target is -stockquantity on post
-- and 0 on reverse. Rows are never deleted or rewritten, so the ledger keeps the
-- full history and a repeated call is a no-op.
--
-- The daily-closing hazard
-- ------------------------
-- fnwaterdailyclosing_livetotals subtracts the day's approved expenses from
-- expected cash at hand. An Internal Use expense is NON-CASH, so leaving it in
-- that pool would understate expected cash and hand the manager a phantom cash
-- difference every single day. Migration 102 already carved out
-- 'RawMaterialPurchase' from gen_exp for the same reason; this extends that
-- carve-out. The patch is an anchored text replacement on the live function body
-- (migration 206/211's technique) and ABORTS if its anchor is missing, so a
-- drifted body fails loudly instead of silently skipping the fix.
--
-- Idempotent throughout: CREATE TABLE IF NOT EXISTS, ADD COLUMN IF NOT EXISTS,
-- CREATE OR REPLACE FUNCTION, ON CONFLICT DO NOTHING, and delta-based posting.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Correlation column on the water stock ledger.
-- -----------------------------------------------------------------------------
ALTER TABLE waterstocktransactions ADD COLUMN IF NOT EXISTS relatedid integer;

CREATE INDEX IF NOT EXISTS ix_waterstocktxn_related
    ON waterstocktransactions (farmid, txntype, relatedid)
    WHERE relatedid IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 1. Tables.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS waterinternalusage (
    waterinternalusageid serial PRIMARY KEY,
    farmid               text          NOT NULL,
    usagedate            timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    referenceno          text          NULL,
    -- StaffWelfare | OwnerUse | OfficeUse | Sample | Donation | QualityTest | InternalConsumption | Other
    category             text          NOT NULL,
    reason               text          NULL,
    recipientname        text          NULL,
    responsiblestaffid   integer       NULL,
    -- Helper inputs. Stored so the record can explain itself later ("12 staff x
    -- 1 bag"), but NOT load-bearing: stockquantity on the item is the truth.
    -- Never recompute quantity from these at post time, or editing staffcount
    -- would silently move stock.
    staffcount           integer       NULL,
    status               text          NOT NULL DEFAULT 'Draft',   -- Draft | Posted | Reversed
    totalcostvalue       numeric(14,2) NOT NULL DEFAULT 0,
    notes                text          NULL,
    postedby             text          NULL,
    postedat             timestamp     NULL,
    reversedby           text          NULL,
    reversedat           timestamp     NULL,
    reversalreason       text          NULL,
    createdby            text          NULL,
    createdat            timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedat            timestamp     NULL
);

CREATE TABLE IF NOT EXISTS waterinternalusageitems (
    waterinternalusageitemid serial PRIMARY KEY,
    waterinternalusageid int           NOT NULL
        REFERENCES waterinternalusage (waterinternalusageid) ON DELETE CASCADE,
    farmid               text          NOT NULL,
    waterproductid       int           NOT NULL,
    entryquantity        numeric(14,3) NOT NULL,           -- what the user typed (e.g. 5)
    entryunit            text          NULL,               -- 'Bag' | 'Sachet' | product unit
    unitsperentryunit    numeric(18,6) NOT NULL DEFAULT 1, -- SNAPSHOT of sachetsperbag at entry time
    stockquantity        numeric(14,3) NOT NULL,           -- entryquantity * unitsperentryunit, in BASE units
    quantityperstaff     numeric(14,3) NULL,
    unitcost             numeric(14,4) NOT NULL DEFAULT 0, -- per BASE unit; suggested, user-overridable
    totalcost            numeric(14,2) NOT NULL DEFAULT 0,
    itemnotes            text          NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_waterinternalusage_farm_ref
    ON waterinternalusage (farmid, referenceno) WHERE referenceno IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_waterinternalusage_farm_date
    ON waterinternalusage (farmid, usagedate);
CREATE INDEX IF NOT EXISTS ix_waterinternalusage_farm_status
    ON waterinternalusage (farmid, status);
CREATE INDEX IF NOT EXISTS ix_waterinternalusageitems_parent
    ON waterinternalusageitems (waterinternalusageid);

-- -----------------------------------------------------------------------------
-- 2. Weighted average cost per BASE unit.
-- -----------------------------------------------------------------------------
-- unitcost on waterstocktransactions is per ENTRY unit (per bag on a restock --
-- see migration 067, which writes @CostPerBag), while stock is counted in
-- sachets. Dividing the money by basequantity lands on cost per sachet.
-- Returns 0 when the product has no costed inflow; that is honest, and the
-- caller may override it.
CREATE OR REPLACE FUNCTION public.fnwaterproductavgcost(p_farmid text, p_waterproductid integer)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
             SUM(st.unitcost * st.quantity)
             / NULLIF(SUM(COALESCE(st.basequantity, st.quantity)), 0),
           0)::numeric
    FROM   waterstocktransactions st
    WHERE  st.farmid = p_farmid
      AND  st.waterproductid = p_waterproductid
      AND  st.quantity > 0
      AND  st.unitcost IS NOT NULL;
$$;

-- -----------------------------------------------------------------------------
-- 3. Lazy 'Internal Use' expense category.
-- -----------------------------------------------------------------------------
-- Migration 075's rationale, verbatim in spirit: seeding on first use avoids a
-- global data migration, and new farms get the category automatically.
CREATE OR REPLACE FUNCTION public.spwaterexpensecategory_ensureinternaluse(p_farmid text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id integer;
BEGIN
    SELECT c.waterexpensecategoryid INTO v_id
    FROM   waterexpensecategories c
    WHERE  c.farmid = p_farmid AND c.name = 'Internal Use' AND COALESCE(c.isdeleted, FALSE) = FALSE
    LIMIT  1;

    IF v_id IS NULL THEN
        INSERT INTO waterexpensecategories (farmid, name, description)
        VALUES (p_farmid, 'Internal Use',
                'Stock consumed internally - staff welfare, owner use, donations, samples, testing.')
        RETURNING waterexpensecategoryid INTO v_id;
    END IF;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Read paths.
-- -----------------------------------------------------------------------------
-- Items ride along as JSON so a list render is one round trip. The payload is
-- small (an internal-use basket is a handful of lines).
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

CREATE OR REPLACE FUNCTION public.spwaterinternalusage_getbyid(
    p_waterinternalusageid integer, p_farmid text)
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
    SELECT * FROM public.spwaterinternalusage_getall(p_farmid)
    WHERE  waterinternalusageid = p_waterinternalusageid;
$$;

-- -----------------------------------------------------------------------------
-- 5. Write paths (draft only).
-- -----------------------------------------------------------------------------
-- Items arrive as a JSON array. unitsperentryunit and stockquantity are computed
-- HERE, from waterproducts.sachetsperbag, so the client cannot post a quantity
-- that disagrees with the conversion. The factor is snapshotted onto the row --
-- the same thing watersaleitems does -- so later edits to the product's
-- sachetsperbag never silently restate a historic record.
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
        unitsperentryunit, stockquantity, quantityperstaff, unitcost, totalcost, itemnotes)
    SELECT p_waterinternalusageid,
           p_farmid,
           j.waterproductid,
           j.entryquantity,
           COALESCE(NULLIF(btrim(j.entryunit), ''), COALESCE(p.baseunit, p.unit)),
           v.factor,
           ROUND(j.entryquantity * v.factor, 3),
           j.quantityperstaff,
           COALESCE(j.unitcost, 0),
           ROUND(COALESCE(j.unitcost, 0) * ROUND(j.entryquantity * v.factor, 3), 2),
           j.itemnotes
    FROM   json_to_recordset(p_itemsjson::json) AS j(
               waterproductid   integer,
               entryquantity    numeric,
               entryunit        text,
               quantityperstaff numeric,
               unitcost         numeric,
               itemnotes        text)
    LEFT   JOIN waterproducts p ON p.waterproductid = j.waterproductid
    CROSS  JOIN LATERAL (
        SELECT CASE
                 -- Only a Bag entry converts. Sachet (or any base-unit) entry is 1:1.
                 WHEN lower(COALESCE(j.entryunit, '')) = 'bag'
                 THEN GREATEST(COALESCE(p.sachetsperbag, 30), 1)::numeric
                 ELSE 1::numeric
               END AS factor
    ) v
    WHERE  j.waterproductid IS NOT NULL
      AND  COALESCE(j.entryquantity, 0) > 0;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spwaterinternalusage_insert(
    p_farmid             text,
    p_usagedate          timestamp,
    p_category           text,
    p_reason             text DEFAULT NULL,
    p_recipientname      text DEFAULT NULL,
    p_responsiblestaffid integer DEFAULT NULL,
    p_staffcount         integer DEFAULT NULL,
    p_notes              text DEFAULT NULL,
    p_itemsjson          text DEFAULT NULL,
    p_createdby          text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id  integer;
    v_ref text;
BEGIN
    IF COALESCE(btrim(p_category), '') = '' THEN
        RAISE EXCEPTION 'Pick what the stock was used for.';
    END IF;

    INSERT INTO waterinternalusage (farmid, usagedate, category, reason, recipientname,
                                    responsiblestaffid, staffcount, notes, status, createdby)
    VALUES (p_farmid, COALESCE(p_usagedate, now() at time zone 'utc'), p_category, p_reason,
            p_recipientname, p_responsiblestaffid, p_staffcount, p_notes, 'Draft', p_createdby)
    RETURNING waterinternalusageid INTO v_id;

    -- Human-facing reference, unique per farm. Assigned after insert so it can
    -- carry the id; the year prefix keeps it readable across seasons.
    v_ref := 'IU-' || to_char(COALESCE(p_usagedate, now() at time zone 'utc'), 'YYYY')
                   || '-' || lpad(v_id::text, 4, '0');
    UPDATE waterinternalusage SET referenceno = v_ref WHERE waterinternalusageid = v_id;

    PERFORM public.spwaterinternalusage_replaceitems(v_id, p_farmid, p_itemsjson);
    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spwaterinternalusage_update(
    p_waterinternalusageid integer,
    p_farmid             text,
    p_usagedate          timestamp,
    p_category           text,
    p_reason             text DEFAULT NULL,
    p_recipientname      text DEFAULT NULL,
    p_responsiblestaffid integer DEFAULT NULL,
    p_staffcount         integer DEFAULT NULL,
    p_notes              text DEFAULT NULL,
    p_itemsjson          text DEFAULT NULL,
    p_updatedby          text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
BEGIN
    SELECT h.status INTO v_status FROM waterinternalusage h
    WHERE  h.waterinternalusageid = p_waterinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Internal use record % not found.', p_waterinternalusageid;
    END IF;
    -- Editing a posted record would move stock behind the ledger's back.
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a draft can be edited. This record is %. Reverse it and create a new one.', v_status;
    END IF;

    UPDATE waterinternalusage
    SET    usagedate          = COALESCE(p_usagedate, usagedate),
           category           = COALESCE(NULLIF(btrim(p_category), ''), category),
           reason             = p_reason,
           recipientname      = p_recipientname,
           responsiblestaffid = p_responsiblestaffid,
           staffcount         = p_staffcount,
           notes              = p_notes,
           updatedat          = (now() at time zone 'utc')
    WHERE  waterinternalusageid = p_waterinternalusageid AND farmid = p_farmid;

    PERFORM public.spwaterinternalusage_replaceitems(p_waterinternalusageid, p_farmid, p_itemsjson);
END;
$function$;

CREATE OR REPLACE FUNCTION public.spwaterinternalusage_delete(
    p_waterinternalusageid integer, p_farmid text, p_userid text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
BEGIN
    SELECT h.status INTO v_status FROM waterinternalusage h
    WHERE  h.waterinternalusageid = p_waterinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN RETURN; END IF;    -- already gone: deleting is idempotent
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'A % record cannot be deleted -- reverse it instead, so the stock history survives.', v_status;
    END IF;

    DELETE FROM waterinternalusage
    WHERE waterinternalusageid = p_waterinternalusageid AND farmid = p_farmid;   -- items cascade
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Post.
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
    -- Guard 1 of 2: already posted, nothing to do. Paired with the delta
    -- arithmetic below, a double-click cannot double-deduct.
    IF v_status = 'Posted' THEN RETURN; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Cannot post a % record.', v_status;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM waterinternalusageitems
                   WHERE waterinternalusageid = p_waterinternalusageid) THEN
        RAISE EXCEPTION 'Add at least one product before posting.';
    END IF;

    -- Pre-flight. Refuse the whole record rather than posting some lines and
    -- driving a product negative. COALESCE(basequantity, quantity) covers rows
    -- written before migration 084 backfilled basequantity.
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
        -- Migration 179's rule: post the DELTA needed to reach the target for
        -- this (txntype, relatedid, product). Never delete, never rewrite.
        -- Guard 2 of 2: a repeat run computes delta 0 and writes nothing.
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
                    -- quantity is an INT display column in the entry unit;
                    -- basequantity is what stock is actually summed on.
                    ROUND(v_delta / GREATEST(r.unitsperentryunit, 0.000001))::integer,
                    v_delta,
                    NULLIF(r.unitcost, 0),
                    p_waterinternalusageid,
                    'Internal use ' || COALESCE(
                        (SELECT referenceno FROM waterinternalusage
                         WHERE waterinternalusageid = p_waterinternalusageid),
                        '#' || p_waterinternalusageid::text),
                    p_postedby);
        END IF;

        -- Fall back to the computed average only where the user left it blank.
        IF r.unitcost = 0 THEN
            UPDATE waterinternalusageitems
            SET    unitcost = public.fnwaterproductavgcost(p_farmid, waterproductid)
            WHERE  waterinternalusageitemid = r.waterinternalusageitemid;
        END IF;
    END LOOP;

    UPDATE waterinternalusageitems
    SET    totalcost = ROUND(unitcost * stockquantity, 2)
    WHERE  waterinternalusageid = p_waterinternalusageid;

    SELECT COALESCE(SUM(totalcost), 0) INTO v_total
    FROM   waterinternalusageitems WHERE waterinternalusageid = p_waterinternalusageid;

    UPDATE waterinternalusage
    SET    status = 'Posted', totalcostvalue = v_total,
           postedby = p_postedby, postedat = (now() at time zone 'utc'),
           updatedat = (now() at time zone 'utc')
    WHERE  waterinternalusageid = p_waterinternalusageid AND farmid = p_farmid;

    -- ---- linked expense -----------------------------------------------------
    -- PaymentMethod 'Credit' with a NULL cash account, exactly as
    -- spWaterPayrollRun_Approve does (migration 075): an approved expense that
    -- moves NO cash. We insert the row ourselves and never call
    -- spWaterExpense_Approve, which is the only place water debits cash.
    -- The NOT EXISTS guard is belt-and-braces; UX_WaterExpenses_FarmSource_Active
    -- enforces single-active-expense-per-source in the database as well.
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
-- 7. Reverse.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterinternalusage_reverse(
    p_waterinternalusageid integer,
    p_farmid   text,
    p_reason   text DEFAULT NULL,
    p_reversedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_net    numeric(14,3);
    v_delta  numeric(14,3);
    r        record;
BEGIN
    SELECT h.status INTO v_status FROM waterinternalusage h
    WHERE  h.waterinternalusageid = p_waterinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Internal use record % not found.', p_waterinternalusageid;
    END IF;
    IF v_status = 'Reversed' THEN RETURN; END IF;          -- idempotent
    IF v_status <> 'Posted' THEN
        RAISE EXCEPTION 'Only a posted record can be reversed. This one is %.', v_status;
    END IF;

    FOR r IN SELECT * FROM waterinternalusageitems
             WHERE waterinternalusageid = p_waterinternalusageid
    LOOP
        -- Same delta rule, target 0: post the exact opposite of what is there.
        -- The original rows stay put, so the ledger tells the whole story.
        SELECT COALESCE(SUM(COALESCE(st.basequantity, st.quantity)), 0) INTO v_net
        FROM   waterstocktransactions st
        WHERE  st.farmid = p_farmid
          AND  st.txntype = 'InternalUse'
          AND  st.relatedid = p_waterinternalusageid
          AND  st.waterproductid = r.waterproductid;

        v_delta := 0 - v_net;

        IF v_delta <> 0 THEN
            INSERT INTO waterstocktransactions
                (farmid, waterproductid, txntype, quantity, basequantity, unitcost,
                 relatedid, note, createdby)
            VALUES (p_farmid, r.waterproductid, 'InternalUse',
                    ROUND(v_delta / GREATEST(r.unitsperentryunit, 0.000001))::integer,
                    v_delta,
                    NULLIF(r.unitcost, 0),
                    p_waterinternalusageid,
                    'Reversal of internal use ' || COALESCE(
                        (SELECT referenceno FROM waterinternalusage
                         WHERE waterinternalusageid = p_waterinternalusageid),
                        '#' || p_waterinternalusageid::text),
                    p_reversedby);
        END IF;
    END LOOP;

    -- Cancel rather than delete: waterexpenses has isdeleted/status, and the
    -- filtered unique index only counts active rows, so a later re-post would
    -- still be free to insert.
    UPDATE waterexpenses
    SET    isdeleted = TRUE, status = 'Cancelled', updatedat = (now() at time zone 'utc'),
           notes = COALESCE(notes, '') || ' [reversed' ||
                   COALESCE(': ' || NULLIF(btrim(p_reason), ''), '') || ']'
    WHERE  farmid = p_farmid
      AND  sourcetype = 'WaterInternalUsage'
      AND  sourceid = p_waterinternalusageid
      AND  COALESCE(isdeleted, FALSE) = FALSE;

    UPDATE waterinternalusage
    SET    status = 'Reversed', reversedby = p_reversedby,
           reversedat = (now() at time zone 'utc'), reversalreason = p_reason,
           updatedat = (now() at time zone 'utc')
    WHERE  waterinternalusageid = p_waterinternalusageid AND farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 8. Keep the non-cash expense out of expected cash at hand.
-- -----------------------------------------------------------------------------
-- Anchored patch on the live body, aborting if the anchor is gone. See header.
DO $patch$
DECLARE
    v_def  text;
    v_new  text;
    v_oid  oid;
BEGIN
    SELECT p.oid INTO v_oid
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'fnwaterdailyclosing_livetotals'
    LIMIT  1;

    IF v_oid IS NULL THEN
        RAISE EXCEPTION '212: fnwaterdailyclosing_livetotals not found -- cannot apply the non-cash carve-out.';
    END IF;

    v_def := pg_get_functiondef(v_oid);

    IF position('WaterInternalUsage' in v_def) > 0 THEN
        RAISE NOTICE '212: daily-closing carve-out already applied.';
        RETURN;
    END IF;

    IF position('''RawMaterialPurchase''' in v_def) = 0 THEN
        RAISE EXCEPTION '212: expected the RawMaterialPurchase exclusion in fnwaterdailyclosing_livetotals and did not find it. The body has drifted -- apply the carve-out by hand.';
    END IF;

    -- Widen the single-value exclusion into a set.
    v_new := replace(v_def,
                     '<> ''RawMaterialPurchase''',
                     'NOT IN (''RawMaterialPurchase'', ''WaterInternalUsage'')');

    IF v_new = v_def THEN
        RAISE EXCEPTION '212: found RawMaterialPurchase but not the "<> ''RawMaterialPurchase''" comparison. Apply the carve-out by hand.';
    END IF;

    EXECUTE v_new;
    RAISE NOTICE '212: daily-closing now excludes WaterInternalUsage from cash at hand.';
END;
$patch$;

-- -----------------------------------------------------------------------------
-- 9. IAM catalog.
-- -----------------------------------------------------------------------------
-- Defensive: the IAM tables arrived in 199 and this feature must not fail to
-- install on a database that predates them.
DO $iam$
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '212: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'water.internal-use.' || a.action, 'water', 'internal-use', a.action,
           'Inventory', 'Internal Use',
           'Stock consumed internally - staff welfare, owner use, donations, samples, testing.',
           'Water', FALSE, 52
    FROM   (VALUES ('view'), ('create'), ('edit'), ('delete')) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;
END;
$iam$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification. Every line should report OK.
-- -----------------------------------------------------------------------------
SELECT 'tables'         AS check,
       CASE WHEN to_regclass('public.waterinternalusage') IS NOT NULL
             AND to_regclass('public.waterinternalusageitems') IS NOT NULL
            THEN 'OK' ELSE 'MISSING' END AS result
UNION ALL
SELECT 'relatedid column',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_name = 'waterstocktransactions' AND column_name = 'relatedid')
            THEN 'OK' ELSE 'MISSING' END
UNION ALL
SELECT 'functions (7 expected)',
       CASE WHEN count(*) >= 7 THEN 'OK (' || count(*) || ')' ELSE 'MISSING (' || count(*) || ')' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname LIKE 'spwaterinternalusage%'
UNION ALL
SELECT 'cash carve-out',
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'fnwaterdailyclosing_livetotals'
                AND pg_get_functiondef(p.oid) LIKE '%WaterInternalUsage%')
            THEN 'OK' ELSE 'NOT APPLIED' END;

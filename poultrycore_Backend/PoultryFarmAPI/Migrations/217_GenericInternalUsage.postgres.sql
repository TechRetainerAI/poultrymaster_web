-- =============================================================================
-- 217_GenericInternalUsage.postgres.sql
--
-- Purpose
-- -------
-- Internal Use for generic companies: products consumed by the business rather
-- than sold -- staff welfare, owner use, office supplies, samples, donations,
-- testing. Third and last of the three company types (water 212-215,
-- poultry 216).
--
-- This one finally implements a constant the codebase reserved and never used:
-- GenericStockMovementTypes.InternalUseOut (Models/GenericInventoryModels.cs:18,
-- documented in migration 030) has existed since the generic module was built,
-- with no SP, service or endpoint behind it. There are zero rows of that type in
-- the database today.
--
-- Generic differences from water and poultry
-- ------------------------------------------
--   1. NO UNIT CONVERSION. genericproducts has a single freetext unitofmeasure
--      with no factor and no second unit, so unitsperentryunit is always 1 and
--      entryunitcost is simply the cost per unit. The column is kept for shape
--      parity, ready for a real requirement rather than a guessed one.
--   2. THE DENORMALISED CACHE. Unlike the other two, generic keeps
--      genericproducts.currentstock alongside the movement ledger, and
--      spgenericstockadjustment_approve maintains it as
--      `currentstock = currentstock + v_signedqty`. Every write here does the
--      same. Forgetting it is the single most likely generic bug: the ledger
--      would be right and every screen would be wrong.
--   3. THE EXPENSE LINK IS NEW. genericexpenses has status and isdeleted like
--      water, but no sourcetype/sourceid -- so this adds them, plus the filtered
--      unique index that gives idempotency for free. That is the only additive
--      DDL on an existing table.
--
-- Costing is exact here, uniquely: genericproducts.costprice is a real per-unit
-- cost, and it is what spgenericstockadjustment_approve already uses to value a
-- movement. No weighted average to approximate.
--
-- The daily-closing hazard
-- ------------------------
-- spgenericdailyclosing_submit sums approved genericexpenses into the day's
-- cash figure. An Internal Use expense is NON-CASH, so it is carved out below,
-- exactly as for water (102/212) and poultry (216).
-- spgenericreport_periodpnl and spgenericreport_dashboard_rs1 are deliberately
-- NOT patched: the cost is real and belongs in a P&L and in an expense tile. It
-- simply is not cash.
--
-- Carries forward 213 (entry-unit cost), 214 (quoted camelCase JSON keys) and
-- 215 (header total rolled up on save). Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Expense soft-link, mirroring water's UX_WaterExpenses_FarmSource_Active.
-- -----------------------------------------------------------------------------
ALTER TABLE genericexpenses ADD COLUMN IF NOT EXISTS sourcetype text;
ALTER TABLE genericexpenses ADD COLUMN IF NOT EXISTS sourceid   integer;

CREATE UNIQUE INDEX IF NOT EXISTS ux_genericexpenses_farmsource_active
    ON genericexpenses (farmid, sourcetype, sourceid)
    WHERE sourcetype IS NOT NULL AND isdeleted = FALSE;

-- -----------------------------------------------------------------------------
-- 1. Tables.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericinternalusage (
    genericinternalusageid serial PRIMARY KEY,
    farmid               text          NOT NULL,
    usagedate            timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    referenceno          text          NULL,
    category             text          NOT NULL,
    reason               text          NULL,
    recipientname        text          NULL,
    responsiblestaffid   integer       NULL,
    staffcount           integer       NULL,
    status               text          NOT NULL DEFAULT 'Draft',   -- Draft | Posted | Reversed
    totalcostvalue       numeric(14,2) NOT NULL DEFAULT 0,
    notes                text          NULL,
    postedby             text          NULL,  postedat   timestamp NULL,
    reversedby           text          NULL,  reversedat timestamp NULL,
    reversalreason       text          NULL,
    createdby            text          NULL,
    createdat            timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedat            timestamp     NULL
);

CREATE TABLE IF NOT EXISTS genericinternalusageitems (
    genericinternalusageitemid serial PRIMARY KEY,
    genericinternalusageid int      NOT NULL
        REFERENCES genericinternalusage (genericinternalusageid) ON DELETE CASCADE,
    farmid            text          NOT NULL,
    genericproductid  int           NOT NULL,
    entryquantity     numeric(14,3) NOT NULL,
    entryunit         text          NULL,               -- the product's unitofmeasure
    unitsperentryunit numeric(18,6) NOT NULL DEFAULT 1, -- always 1 today; see header
    stockquantity     numeric(14,3) NOT NULL,
    quantityperstaff  numeric(14,3) NULL,
    entryunitcost     numeric(14,4) NOT NULL DEFAULT 0,
    unitcost          numeric(14,4) NOT NULL DEFAULT 0,
    totalcost         numeric(14,2) NOT NULL DEFAULT 0,
    itemnotes         text          NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_genericinternalusage_farm_ref
    ON genericinternalusage (farmid, referenceno) WHERE referenceno IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_genericinternalusage_farm_date
    ON genericinternalusage (farmid, usagedate);
CREATE INDEX IF NOT EXISTS ix_genericinternalusage_farm_status
    ON genericinternalusage (farmid, status);
CREATE INDEX IF NOT EXISTS ix_genericinternalusageitems_parent
    ON genericinternalusageitems (genericinternalusageid);
CREATE INDEX IF NOT EXISTS ix_genericstockmovements_reference
    ON genericstockmovements (farmid, referencetype, referenceid) WHERE referenceid IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 2. Cost per unit -- exact, from the product's own cost price.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fngenericproductavgcost(p_farmid text, p_genericproductid integer)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(MAX(p.costprice), 0)::numeric
    FROM   genericproducts p
    WHERE  p.genericproductid = p_genericproductid AND p.farmid = p_farmid;
$$;

-- -----------------------------------------------------------------------------
-- 3. Lazy 'Internal Use' expense category.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericexpensecategory_ensureinternaluse(p_farmid text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id integer;
BEGIN
    SELECT c.genericexpensecategoryid INTO v_id
    FROM   genericexpensecategories c
    WHERE  c.farmid = p_farmid AND c.name = 'Internal Use' AND COALESCE(c.isdeleted, FALSE) = FALSE
    LIMIT  1;

    IF v_id IS NULL THEN
        INSERT INTO genericexpensecategories (farmid, name, description)
        VALUES (p_farmid, 'Internal Use',
                'Stock consumed internally - staff welfare, owner use, donations, samples, testing.')
        RETURNING genericexpensecategoryid INTO v_id;
    END IF;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Read path.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinternalusage_getall(
    p_farmid   text,
    p_status   text      DEFAULT NULL,
    p_category text      DEFAULT NULL,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE(
    genericinternalusageid integer, farmid text, usagedate timestamp, referenceno text,
    category text, reason text, recipientname text, responsiblestaffid integer,
    staffcount integer, status text, totalcostvalue numeric, notes text,
    postedby text, postedat timestamp, reversedby text, reversedat timestamp,
    reversalreason text, createdby text, createdat timestamp, updatedat timestamp,
    itemsjson text)
LANGUAGE sql
STABLE
AS $$
    SELECT h.genericinternalusageid, h.farmid, h.usagedate, h.referenceno,
           h.category, h.reason, h.recipientname, h.responsiblestaffid,
           h.staffcount, h.status, h.totalcostvalue, h.notes,
           h.postedby, h.postedat, h.reversedby, h.reversedat,
           h.reversalreason, h.createdby, h.createdat, h.updatedat,
           COALESCE((
               SELECT json_agg(json_build_object(
                          'genericInternalUsageItemId', i.genericinternalusageitemid,
                          'genericProductId',           i.genericproductid,
                          'productName',                p.productname,
                          'entryQuantity',              i.entryquantity,
                          'entryUnit',                  i.entryunit,
                          'unitsPerEntryUnit',          i.unitsperentryunit,
                          'stockQuantity',              i.stockquantity,
                          'quantityPerStaff',           i.quantityperstaff,
                          'entryUnitCost',              i.entryunitcost,
                          'unitCost',                   i.unitcost,
                          'totalCost',                  i.totalcost,
                          'itemNotes',                  i.itemnotes)
                      ORDER BY i.genericinternalusageitemid)::text
               FROM   genericinternalusageitems i
               LEFT   JOIN genericproducts p ON p.genericproductid = i.genericproductid
               WHERE  i.genericinternalusageid = h.genericinternalusageid
           ), '[]') AS itemsjson
    FROM   genericinternalusage h
    WHERE  h.farmid = p_farmid
      AND  (p_status   IS NULL OR h.status   = p_status)
      AND  (p_category IS NULL OR h.category = p_category)
      AND  (p_fromdate IS NULL OR h.usagedate >= p_fromdate)
      AND  (p_todate   IS NULL OR h.usagedate <  (p_todate + interval '1 day'))
    ORDER  BY h.usagedate DESC, h.genericinternalusageid DESC;
$$;

CREATE OR REPLACE FUNCTION public.spgenericinternalusage_getbyid(
    p_genericinternalusageid integer, p_farmid text)
RETURNS TABLE(
    genericinternalusageid integer, farmid text, usagedate timestamp, referenceno text,
    category text, reason text, recipientname text, responsiblestaffid integer,
    staffcount integer, status text, totalcostvalue numeric, notes text,
    postedby text, postedat timestamp, reversedby text, reversedat timestamp,
    reversalreason text, createdby text, createdat timestamp, updatedat timestamp,
    itemsjson text)
LANGUAGE sql
STABLE
AS $$
    SELECT * FROM public.spgenericinternalusage_getall(p_farmid)
    WHERE  genericinternalusageid = p_genericinternalusageid;
$$;

-- -----------------------------------------------------------------------------
-- 5. Write path.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinternalusage_replaceitems(
    p_genericinternalusageid integer, p_farmid text, p_itemsjson text)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    DELETE FROM genericinternalusageitems WHERE genericinternalusageid = p_genericinternalusageid;

    IF p_itemsjson IS NOT NULL AND btrim(p_itemsjson) NOT IN ('', '[]') THEN
        INSERT INTO genericinternalusageitems (
            genericinternalusageid, farmid, genericproductid, entryquantity, entryunit,
            unitsperentryunit, stockquantity, quantityperstaff,
            entryunitcost, unitcost, totalcost, itemnotes)
        -- Quoted identifiers: json_to_recordset matches keys case-sensitively
        -- and the payload is camelCase (migration 214).
        SELECT p_genericinternalusageid,
               p_farmid,
               j."genericProductId",
               j."entryQuantity",
               COALESCE(NULLIF(btrim(j."entryUnit"), ''), p.unitofmeasure),
               1,                                   -- no conversion; see header
               j."entryQuantity",
               j."quantityPerStaff",
               COALESCE(j."entryUnitCost", 0),
               COALESCE(j."entryUnitCost", 0),      -- same thing at factor 1
               ROUND(j."entryQuantity" * COALESCE(j."entryUnitCost", 0), 2),
               j."itemNotes"
        FROM   json_to_recordset(p_itemsjson::json) AS j(
                   "genericProductId" integer,
                   "entryQuantity"    numeric,
                   "entryUnit"        text,
                   "quantityPerStaff" numeric,
                   "entryUnitCost"    numeric,
                   "itemNotes"        text)
        LEFT   JOIN genericproducts p ON p.genericproductid = j."genericProductId"
        WHERE  j."genericProductId" IS NOT NULL
          AND  COALESCE(j."entryQuantity", 0) > 0;
    END IF;

    -- Header in step with its lines, draft included (migration 215).
    UPDATE genericinternalusage h
    SET    totalcostvalue = COALESCE((
               SELECT SUM(i.totalcost) FROM genericinternalusageitems i
               WHERE  i.genericinternalusageid = h.genericinternalusageid), 0),
           updatedat = (now() at time zone 'utc')
    WHERE  h.genericinternalusageid = p_genericinternalusageid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericinternalusage_insert(
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
    v_id integer;
BEGIN
    IF COALESCE(btrim(p_category), '') = '' THEN
        RAISE EXCEPTION 'Pick what the stock was used for.';
    END IF;

    INSERT INTO genericinternalusage (farmid, usagedate, category, reason, recipientname,
                                      responsiblestaffid, staffcount, notes, status, createdby)
    VALUES (p_farmid, COALESCE(p_usagedate, now() at time zone 'utc'), p_category, p_reason,
            p_recipientname, p_responsiblestaffid, p_staffcount, p_notes, 'Draft', p_createdby)
    RETURNING genericinternalusageid INTO v_id;

    UPDATE genericinternalusage
    SET    referenceno = 'IU-' || to_char(COALESCE(p_usagedate, now() at time zone 'utc'), 'YYYY')
                                || '-' || lpad(v_id::text, 4, '0')
    WHERE  genericinternalusageid = v_id;

    PERFORM public.spgenericinternalusage_replaceitems(v_id, p_farmid, p_itemsjson);
    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericinternalusage_update(
    p_genericinternalusageid integer,
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
    SELECT h.status INTO v_status FROM genericinternalusage h
    WHERE  h.genericinternalusageid = p_genericinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Internal use record % not found.', p_genericinternalusageid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a draft can be edited. This record is %. Reverse it and create a new one.', v_status;
    END IF;

    UPDATE genericinternalusage
    SET    usagedate          = COALESCE(p_usagedate, usagedate),
           category           = COALESCE(NULLIF(btrim(p_category), ''), category),
           reason             = p_reason,
           recipientname      = p_recipientname,
           responsiblestaffid = p_responsiblestaffid,
           staffcount         = p_staffcount,
           notes              = p_notes,
           updatedat          = (now() at time zone 'utc')
    WHERE  genericinternalusageid = p_genericinternalusageid AND farmid = p_farmid;

    PERFORM public.spgenericinternalusage_replaceitems(p_genericinternalusageid, p_farmid, p_itemsjson);
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericinternalusage_delete(
    p_genericinternalusageid integer, p_farmid text, p_userid text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
BEGIN
    SELECT h.status INTO v_status FROM genericinternalusage h
    WHERE  h.genericinternalusageid = p_genericinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN RETURN; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'A % record cannot be deleted -- reverse it instead, so the stock history survives.', v_status;
    END IF;

    DELETE FROM genericinternalusage
    WHERE genericinternalusageid = p_genericinternalusageid AND farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Post.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinternalusage_post(
    p_genericinternalusageid integer, p_farmid text, p_postedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_total  numeric(14,2) := 0;
    v_net    numeric(14,3);
    v_delta  numeric(14,3);
    v_onhand numeric(14,3);
    v_catid  integer;
    v_ref    text;
    r        record;
BEGIN
    SELECT h.status, h.referenceno INTO v_status, v_ref FROM genericinternalusage h
    WHERE  h.genericinternalusageid = p_genericinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Internal use record % not found.', p_genericinternalusageid;
    END IF;
    IF v_status = 'Posted' THEN RETURN; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Cannot post a % record.', v_status;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM genericinternalusageitems
                   WHERE genericinternalusageid = p_genericinternalusageid) THEN
        RAISE EXCEPTION 'Add at least one product before posting.';
    END IF;

    -- Fill any blank cost from the product's cost price.
    UPDATE genericinternalusageitems i
    SET    entryunitcost = public.fngenericproductavgcost(p_farmid, i.genericproductid)
    WHERE  i.genericinternalusageid = p_genericinternalusageid
      AND  i.entryunitcost = 0;

    UPDATE genericinternalusageitems
    SET    unitcost  = entryunitcost,          -- factor is always 1 here
           totalcost = ROUND(entryquantity * entryunitcost, 2)
    WHERE  genericinternalusageid = p_genericinternalusageid;

    -- Pre-flight against the ledger, which is the source of truth.
    FOR r IN SELECT i.*, p.productname
             FROM   genericinternalusageitems i
             LEFT   JOIN genericproducts p ON p.genericproductid = i.genericproductid
             WHERE  i.genericinternalusageid = p_genericinternalusageid
    LOOP
        SELECT COALESCE(SUM(m.quantity), 0) INTO v_onhand
        FROM   genericstockmovements m
        WHERE  m.farmid = p_farmid AND m.genericproductid = r.genericproductid;

        IF r.stockquantity > v_onhand THEN
            RAISE EXCEPTION 'Not enough %: % in stock, % needed.',
                COALESCE(r.productname, 'product ' || r.genericproductid), v_onhand, r.stockquantity;
        END IF;
    END LOOP;

    FOR r IN SELECT * FROM genericinternalusageitems
             WHERE genericinternalusageid = p_genericinternalusageid
    LOOP
        -- Migration 179's append-only delta rule, scoped on the generic ledger's
        -- (referencetype, referenceid) pair.
        SELECT COALESCE(SUM(m.quantity), 0) INTO v_net
        FROM   genericstockmovements m
        WHERE  m.farmid = p_farmid
          AND  m.referencetype = 'GenericInternalUsage'
          AND  m.referenceid = p_genericinternalusageid
          AND  m.genericproductid = r.genericproductid;

        v_delta := (-r.stockquantity) - v_net;

        IF v_delta <> 0 THEN
            -- InternalUseOut: reserved in migration 030 and in
            -- GenericStockMovementTypes, unimplemented until now.
            INSERT INTO genericstockmovements
                (farmid, genericproductid, movementdate, movementtype, quantity,
                 unitcost, totalcostvalue, referencetype, referenceid, reason,
                 createdby, approvedby, approvedat, createdat)
            SELECT p_farmid, r.genericproductid, h.usagedate, 'InternalUseOut', v_delta,
                   NULLIF(r.entryunitcost, 0), ROUND(ABS(v_delta) * r.entryunitcost, 2),
                   'GenericInternalUsage', p_genericinternalusageid,
                   'Internal use ' || COALESCE(v_ref, '#' || p_genericinternalusageid::text),
                   p_postedby, p_postedby, (now() at time zone 'utc'), (now() at time zone 'utc')
            FROM   genericinternalusage h
            WHERE  h.genericinternalusageid = p_genericinternalusageid;

            -- The denormalised cache every generic screen reads. Same signed
            -- delta, same shape as spgenericstockadjustment_approve.
            UPDATE genericproducts p
            SET    currentstock = p.currentstock + v_delta,
                   updatedat = (now() at time zone 'utc')
            WHERE  p.genericproductid = r.genericproductid AND p.farmid = p_farmid;
        END IF;
    END LOOP;

    SELECT COALESCE(SUM(totalcost), 0) INTO v_total
    FROM   genericinternalusageitems WHERE genericinternalusageid = p_genericinternalusageid;

    UPDATE genericinternalusage
    SET    status = 'Posted', totalcostvalue = v_total,
           postedby = p_postedby, postedat = (now() at time zone 'utc'),
           updatedat = (now() at time zone 'utc')
    WHERE  genericinternalusageid = p_genericinternalusageid AND farmid = p_farmid;

    -- Linked non-cash expense: Credit, no cash account, already Approved. Generic
    -- debits cash only when an expense is approved through its own path, which we
    -- never call.
    IF v_total > 0 AND NOT EXISTS (
        SELECT 1 FROM genericexpenses e
        WHERE  e.farmid = p_farmid
          AND  e.sourcetype = 'GenericInternalUsage'
          AND  e.sourceid = p_genericinternalusageid
          AND  COALESCE(e.isdeleted, FALSE) = FALSE)
    THEN
        v_catid := public.spgenericexpensecategory_ensureinternaluse(p_farmid);

        INSERT INTO genericexpenses (farmid, expensedate, genericexpensecategoryid, description,
                                     amount, paymentmethod, genericcashaccountid, status,
                                     notes, createdby, approvedby, approvedat,
                                     sourcetype, sourceid)
        SELECT p_farmid, h.usagedate, v_catid,
               'Internal use: ' || h.category || COALESCE(' - ' || h.recipientname, ''),
               v_total, 'Credit', NULL, 'Approved',
               'Non-cash: stock consumed internally (' || COALESCE(v_ref, '#' || h.genericinternalusageid::text) || ').',
               COALESCE(p_postedby, h.createdby), COALESCE(p_postedby, h.createdby),
               (now() at time zone 'utc'),
               'GenericInternalUsage', p_genericinternalusageid
        FROM   genericinternalusage h
        WHERE  h.genericinternalusageid = p_genericinternalusageid;
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. Reverse.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinternalusage_reverse(
    p_genericinternalusageid integer,
    p_farmid     text,
    p_reason     text DEFAULT NULL,
    p_reversedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_net    numeric(14,3);
    v_delta  numeric(14,3);
    v_ref    text;
    r        record;
BEGIN
    SELECT h.status, h.referenceno INTO v_status, v_ref FROM genericinternalusage h
    WHERE  h.genericinternalusageid = p_genericinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Internal use record % not found.', p_genericinternalusageid;
    END IF;
    IF v_status = 'Reversed' THEN RETURN; END IF;
    IF v_status <> 'Posted' THEN
        RAISE EXCEPTION 'Only a posted record can be reversed. This one is %.', v_status;
    END IF;

    FOR r IN SELECT * FROM genericinternalusageitems
             WHERE genericinternalusageid = p_genericinternalusageid
    LOOP
        SELECT COALESCE(SUM(m.quantity), 0) INTO v_net
        FROM   genericstockmovements m
        WHERE  m.farmid = p_farmid
          AND  m.referencetype = 'GenericInternalUsage'
          AND  m.referenceid = p_genericinternalusageid
          AND  m.genericproductid = r.genericproductid;

        v_delta := 0 - v_net;

        IF v_delta <> 0 THEN
            INSERT INTO genericstockmovements
                (farmid, genericproductid, movementdate, movementtype, quantity,
                 unitcost, totalcostvalue, referencetype, referenceid, reason,
                 createdby, approvedby, approvedat, createdat)
            VALUES (p_farmid, r.genericproductid, (now() at time zone 'utc'),
                    'InternalUseOut', v_delta,
                    NULLIF(r.entryunitcost, 0), ROUND(ABS(v_delta) * r.entryunitcost, 2),
                    'GenericInternalUsage', p_genericinternalusageid,
                    'Reversal of internal use ' || COALESCE(v_ref, '#' || p_genericinternalusageid::text),
                    p_reversedby, p_reversedby, (now() at time zone 'utc'), (now() at time zone 'utc'));

            UPDATE genericproducts p
            SET    currentstock = p.currentstock + v_delta,
                   updatedat = (now() at time zone 'utc')
            WHERE  p.genericproductid = r.genericproductid AND p.farmid = p_farmid;
        END IF;
    END LOOP;

    -- Cancel rather than delete: genericexpenses has isdeleted and status, and
    -- the filtered unique index only counts active rows.
    UPDATE genericexpenses
    SET    isdeleted = TRUE, status = 'Cancelled', updatedat = (now() at time zone 'utc'),
           notes = COALESCE(notes, '') || ' [reversed' ||
                   COALESCE(': ' || NULLIF(btrim(p_reason), ''), '') || ']'
    WHERE  farmid = p_farmid
      AND  sourcetype = 'GenericInternalUsage'
      AND  sourceid = p_genericinternalusageid
      AND  COALESCE(isdeleted, FALSE) = FALSE;

    UPDATE genericinternalusage
    SET    status = 'Reversed', reversedby = p_reversedby,
           reversedat = (now() at time zone 'utc'), reversalreason = p_reason,
           updatedat = (now() at time zone 'utc')
    WHERE  genericinternalusageid = p_genericinternalusageid AND farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 8. Keep the non-cash expense out of the day's cash figure.
-- -----------------------------------------------------------------------------
DO $patch$
DECLARE
    v_def text;
    v_new text;
    v_oid oid;
BEGIN
    SELECT p.oid INTO v_oid
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'spgenericdailyclosing_submit'
    LIMIT  1;

    IF v_oid IS NULL THEN
        RAISE EXCEPTION '217: spgenericdailyclosing_submit not found -- cannot apply the non-cash carve-out.';
    END IF;

    v_def := pg_get_functiondef(v_oid);

    IF position('GenericInternalUsage' in v_def) > 0 THEN
        RAISE NOTICE '217: daily-closing carve-out already applied.';
        RETURN;
    END IF;

    -- Whitespace-tolerant, as migration 216 had to be: the live bodies are
    -- CRLF-delimited and indented.
    IF v_def !~ 'FROM\s+genericexpenses\s+e\s+WHERE\s+e\.farmid' THEN
        RAISE EXCEPTION '217: expected a "FROM genericexpenses e WHERE e.farmid" clause in spgenericdailyclosing_submit and did not find it. The body has drifted -- apply the carve-out by hand.';
    END IF;

    v_new := regexp_replace(
                 v_def,
                 '(FROM\s+genericexpenses\s+e\s+WHERE\s+)(e\.farmid)',
                 '\1COALESCE(e.sourcetype, '''') <> ''GenericInternalUsage'' AND \2',
                 'g');

    IF v_new = v_def THEN
        RAISE EXCEPTION '217: the carve-out substitution changed nothing. Apply it by hand.';
    END IF;

    EXECUTE v_new;
    RAISE NOTICE '217: daily closing now excludes GenericInternalUsage from the cash figure.';
END;
$patch$;

-- -----------------------------------------------------------------------------
-- 9. IAM catalog.
-- -----------------------------------------------------------------------------
DO $iam$
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '217: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'generic.internal-use.' || a.action, 'generic', 'internal-use', a.action,
           'Inventory', 'Internal Use',
           'Stock consumed internally - staff welfare, owner use, donations, samples, testing.',
           'Generic', FALSE, 52
    FROM   (VALUES ('view'), ('create'), ('edit'), ('delete')) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;
END;
$iam$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'tables' AS check,
       CASE WHEN to_regclass('public.genericinternalusage') IS NOT NULL
             AND to_regclass('public.genericinternalusageitems') IS NOT NULL
            THEN 'OK' ELSE 'MISSING' END AS result
UNION ALL
SELECT 'genericexpenses source link',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_name='genericexpenses' AND column_name='sourcetype')
            THEN 'OK' ELSE 'MISSING' END
UNION ALL
SELECT 'functions (7 expected)',
       CASE WHEN count(*) >= 7 THEN 'OK (' || count(*) || ')' ELSE 'MISSING (' || count(*) || ')' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname LIKE 'spgenericinternalusage%'
UNION ALL
SELECT 'cash carve-out',
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'spgenericdailyclosing_submit'
                AND pg_get_functiondef(p.oid) LIKE '%GenericInternalUsage%')
            THEN 'OK' ELSE 'NOT APPLIED' END;

-- Round trip: post, check the ledger AND the denormalised cache moved together,
-- then reverse and check both came back. Rolled back.
BEGIN;
DO $verify$
DECLARE
    v_farm text; v_prod integer; v_id integer;
    v_stock0 numeric; v_stock1 numeric; v_stock2 numeric;
    v_ledger numeric;
BEGIN
    SELECT p.farmid, p.genericproductid, p.currentstock INTO v_farm, v_prod, v_stock0
    FROM   genericproducts p
    WHERE  COALESCE(p.isdeleted, FALSE) = FALSE
      AND  COALESCE((SELECT SUM(m.quantity) FROM genericstockmovements m
                     WHERE m.genericproductid = p.genericproductid AND m.farmid = p.farmid), 0) >= 5
    LIMIT  1;

    IF v_farm IS NULL THEN
        RAISE NOTICE '217: no generic product with stock on file, skipping the round-trip check.';
        RETURN;
    END IF;

    INSERT INTO genericinternalusage (farmid, category, status, createdby)
    VALUES (v_farm, 'StaffWelfare', 'Draft', '217-verify')
    RETURNING genericinternalusageid INTO v_id;

    PERFORM public.spgenericinternalusage_replaceitems(
        v_id, v_farm,
        '[{"genericProductId":' || v_prod || ',"entryQuantity":5,"entryUnitCost":4}]');

    PERFORM public.spgenericinternalusage_post(v_id, v_farm, '217-verify');

    SELECT currentstock INTO v_stock1 FROM genericproducts
    WHERE genericproductid = v_prod AND farmid = v_farm;
    SELECT COALESCE(SUM(quantity), 0) INTO v_ledger FROM genericstockmovements
    WHERE referencetype = 'GenericInternalUsage' AND referenceid = v_id;

    IF v_ledger <> -5 THEN
        RAISE EXCEPTION '217: expected a -5 ledger move, got %.', v_ledger;
    END IF;
    IF v_stock1 <> v_stock0 - 5 THEN
        RAISE EXCEPTION '217: currentstock did not follow the ledger (% -> %, expected %).',
            v_stock0, v_stock1, v_stock0 - 5;
    END IF;

    PERFORM public.spgenericinternalusage_reverse(v_id, v_farm, 'verify', '217-verify');

    SELECT currentstock INTO v_stock2 FROM genericproducts
    WHERE genericproductid = v_prod AND farmid = v_farm;
    IF v_stock2 <> v_stock0 THEN
        RAISE EXCEPTION '217: reversal did not restore currentstock (% -> %).', v_stock0, v_stock2;
    END IF;

    RAISE NOTICE '217: post -5 then reverse: stock % -> % -> %, ledger nets to %, cache tracked it.',
        v_stock0, v_stock1, v_stock2,
        (SELECT COALESCE(SUM(quantity), 0) FROM genericstockmovements
         WHERE referencetype = 'GenericInternalUsage' AND referenceid = v_id);
END;
$verify$;
ROLLBACK;

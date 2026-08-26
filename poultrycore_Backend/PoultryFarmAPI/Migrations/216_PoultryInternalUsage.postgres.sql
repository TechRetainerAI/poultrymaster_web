-- =============================================================================
-- 216_PoultryInternalUsage.postgres.sql
--
-- Purpose
-- -------
-- Internal Use for poultry companies: eggs given to staff, birds taken by the
-- owner, feed used for testing, stock donated or sampled. A costed, reversible
-- stock reduction that books an expense and touches nothing else -- no sale, no
-- customer balance, no payment, no cash movement.
--
-- The water half shipped as migrations 212-215. This is the same design with
-- three poultry differences, and it folds in everything those four rounds taught
-- us rather than repeating the mistakes:
--
--   * 213 -- cost is captured in the unit the user typed (entryunitcost), so a
--            crate costs what a crate costs and the line total is a
--            multiplication. Storing only a per-egg figure lost pesewas.
--   * 214 -- json_to_recordset matches keys CASE-SENSITIVELY, so the recordset
--            identifiers are quoted to keep their camelCase. Unquoted ones fold
--            to lowercase, never match, and every line is silently dropped.
--   * 215 -- the header total is rolled up whenever the lines change, not only
--            at post, or a draft reads 0.00 everywhere.
--
-- Poultry differences from water
-- ------------------------------
--   1. Conversion is CRATES -> EGGS via fnpoultrycrateunits (migration 211),
--      which returns eggspercrate only for a raw-egg product and 1 otherwise --
--      so loading birds or feed is untouched. Water used sachetsperbag.
--   2. poultrystocktransactions has ONE signed numeric `quantity` in stock units
--      and already carries `relatedid`. There is no basequantity column and no
--      ALTER needed. Egg stock is a piece count (migration 206), so the ledger
--      is written in eggs.
--   3. The expense table is `expense`: freetext `category` (no category table),
--      `farmid` is a uuid, and `userid` is NOT NULL. It has no isdeleted and no
--      status, so a reversal DELETES the linked row -- a negative-amount row
--      would corrupt every SUM(amount) report. The audit trail survives on the
--      header (status/reason/who/when) and in the append-only ledger.
--
-- The daily-closing hazard
-- ------------------------
-- fnpoultrydailyclosing_livetotals subtracts the day's expenses from expected
-- cash at hand, with no exclusion of any kind:
--
--     FROM expense e WHERE e.farmid = (CASE WHEN p_farmid ~* '^[0-9a-f]{8}-...'
--
-- An Internal Use expense is NON-CASH -- the money left when the stock was
-- bought or grown. Leaving it in that pool would understate expected cash and
-- hand the manager a phantom cash difference every day. Patched below, anchored,
-- aborting if the anchor is gone. sppoultryreport_profitloss is deliberately NOT
-- patched: the cost is real and belongs in the P&L. It just isn't cash.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Tables.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultryinternalusage (
    poultryinternalusageid serial PRIMARY KEY,
    farmid               text          NOT NULL,
    usagedate            timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    referenceno          text          NULL,
    -- StaffWelfare | OwnerUse | FarmUse | Sample | Donation | QualityTest | InternalConsumption | Other
    category             text          NOT NULL,
    reason               text          NULL,
    recipientname        text          NULL,
    responsiblestaffid   integer       NULL,
    staffcount           integer       NULL,   -- helper input, informational only
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

CREATE TABLE IF NOT EXISTS poultryinternalusageitems (
    poultryinternalusageitemid serial PRIMARY KEY,
    poultryinternalusageid int      NOT NULL
        REFERENCES poultryinternalusage (poultryinternalusageid) ON DELETE CASCADE,
    farmid            text          NOT NULL,
    poultryproductid  int           NOT NULL,
    entryquantity     numeric(14,3) NOT NULL,           -- what the user typed (e.g. 10)
    entryunit         text          NULL,               -- 'Crate' | 'Egg' | product unit
    unitsperentryunit numeric(18,6) NOT NULL DEFAULT 1, -- SNAPSHOT of eggs-per-crate
    stockquantity     numeric(14,3) NOT NULL,           -- in the LEDGER's unit (eggs, birds, kg)
    quantityperstaff  numeric(14,3) NULL,
    entryunitcost     numeric(14,4) NOT NULL DEFAULT 0, -- per ENTRY unit -- what the user typed
    unitcost          numeric(14,4) NOT NULL DEFAULT 0, -- derived, per stock unit
    totalcost         numeric(14,2) NOT NULL DEFAULT 0,
    itemnotes         text          NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryinternalusage_farm_ref
    ON poultryinternalusage (farmid, referenceno) WHERE referenceno IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_poultryinternalusage_farm_date
    ON poultryinternalusage (farmid, usagedate);
CREATE INDEX IF NOT EXISTS ix_poultryinternalusage_farm_status
    ON poultryinternalusage (farmid, status);
CREATE INDEX IF NOT EXISTS ix_poultryinternalusageitems_parent
    ON poultryinternalusageitems (poultryinternalusageid);
CREATE INDEX IF NOT EXISTS ix_poultrystocktxn_related
    ON poultrystocktransactions (farmid, txntype, relatedid) WHERE relatedid IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 2. Weighted average cost per STOCK unit.
-- -----------------------------------------------------------------------------
-- Best effort: unitcost on poultrystocktransactions is populated by egg
-- production and little else, so this returns 0 for many farms. That is honest,
-- and the user can type the real figure -- 0 must stay allowed, or people invent
-- numbers for a donation from a farm with no cost history.
CREATE OR REPLACE FUNCTION public.fnpoultryproductavgcost(p_farmid text, p_poultryproductid integer)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(SUM(t.unitcost * t.quantity) / NULLIF(SUM(t.quantity), 0), 0)::numeric
    FROM   poultrystocktransactions t
    WHERE  t.farmid = p_farmid
      AND  t.poultryproductid = p_poultryproductid
      AND  t.quantity > 0
      AND  t.unitcost IS NOT NULL;
$$;

-- -----------------------------------------------------------------------------
-- 3. Read path.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryinternalusage_getall(
    p_farmid   text,
    p_status   text      DEFAULT NULL,
    p_category text      DEFAULT NULL,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE(
    poultryinternalusageid integer, farmid text, usagedate timestamp, referenceno text,
    category text, reason text, recipientname text, responsiblestaffid integer,
    staffcount integer, status text, totalcostvalue numeric, notes text,
    postedby text, postedat timestamp, reversedby text, reversedat timestamp,
    reversalreason text, createdby text, createdat timestamp, updatedat timestamp,
    itemsjson text)
LANGUAGE sql
STABLE
AS $$
    SELECT h.poultryinternalusageid, h.farmid, h.usagedate, h.referenceno,
           h.category, h.reason, h.recipientname, h.responsiblestaffid,
           h.staffcount, h.status, h.totalcostvalue, h.notes,
           h.postedby, h.postedat, h.reversedby, h.reversedat,
           h.reversalreason, h.createdby, h.createdat, h.updatedat,
           COALESCE((
               SELECT json_agg(json_build_object(
                          'poultryInternalUsageItemId', i.poultryinternalusageitemid,
                          'poultryProductId',           i.poultryproductid,
                          'productName',                p.name,
                          'entryQuantity',              i.entryquantity,
                          'entryUnit',                  i.entryunit,
                          'unitsPerEntryUnit',          i.unitsperentryunit,
                          'stockQuantity',              i.stockquantity,
                          'quantityPerStaff',           i.quantityperstaff,
                          'entryUnitCost',              i.entryunitcost,
                          'unitCost',                   i.unitcost,
                          'totalCost',                  i.totalcost,
                          'itemNotes',                  i.itemnotes)
                      ORDER BY i.poultryinternalusageitemid)::text
               FROM   poultryinternalusageitems i
               LEFT   JOIN poultryproducts p ON p.poultryproductid = i.poultryproductid
               WHERE  i.poultryinternalusageid = h.poultryinternalusageid
           ), '[]') AS itemsjson
    FROM   poultryinternalusage h
    WHERE  h.farmid = p_farmid
      AND  (p_status   IS NULL OR h.status   = p_status)
      AND  (p_category IS NULL OR h.category = p_category)
      AND  (p_fromdate IS NULL OR h.usagedate >= p_fromdate)
      AND  (p_todate   IS NULL OR h.usagedate <  (p_todate + interval '1 day'))
    ORDER  BY h.usagedate DESC, h.poultryinternalusageid DESC;
$$;

CREATE OR REPLACE FUNCTION public.sppoultryinternalusage_getbyid(
    p_poultryinternalusageid integer, p_farmid text)
RETURNS TABLE(
    poultryinternalusageid integer, farmid text, usagedate timestamp, referenceno text,
    category text, reason text, recipientname text, responsiblestaffid integer,
    staffcount integer, status text, totalcostvalue numeric, notes text,
    postedby text, postedat timestamp, reversedby text, reversedat timestamp,
    reversalreason text, createdby text, createdat timestamp, updatedat timestamp,
    itemsjson text)
LANGUAGE sql
STABLE
AS $$
    SELECT * FROM public.sppoultryinternalusage_getall(p_farmid)
    WHERE  poultryinternalusageid = p_poultryinternalusageid;
$$;

-- -----------------------------------------------------------------------------
-- 4. Write path.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryinternalusage_replaceitems(
    p_poultryinternalusageid integer, p_farmid text, p_itemsjson text)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    DELETE FROM poultryinternalusageitems WHERE poultryinternalusageid = p_poultryinternalusageid;

    IF p_itemsjson IS NOT NULL AND btrim(p_itemsjson) NOT IN ('', '[]') THEN
        INSERT INTO poultryinternalusageitems (
            poultryinternalusageid, farmid, poultryproductid, entryquantity, entryunit,
            unitsperentryunit, stockquantity, quantityperstaff,
            entryunitcost, unitcost, totalcost, itemnotes)
        -- Identifiers quoted: json_to_recordset matches keys case-sensitively and
        -- the payload is camelCase. See migration 214 for what happens otherwise.
        SELECT p_poultryinternalusageid,
               p_farmid,
               j."poultryProductId",
               j."entryQuantity",
               COALESCE(NULLIF(btrim(j."entryUnit"), ''), p.unit),
               v.factor,
               ROUND(j."entryQuantity" * v.factor, 3),
               j."quantityPerStaff",
               COALESCE(j."entryUnitCost", 0),
               ROUND(COALESCE(j."entryUnitCost", 0) / GREATEST(v.factor, 0.000001), 4),
               ROUND(j."entryQuantity" * COALESCE(j."entryUnitCost", 0), 2),
               j."itemNotes"
        FROM   json_to_recordset(p_itemsjson::json) AS j(
                   "poultryProductId" integer,
                   "entryQuantity"    numeric,
                   "entryUnit"        text,
                   "quantityPerStaff" numeric,
                   "entryUnitCost"    numeric,
                   "eggsPerCrate"     integer,
                   "itemNotes"        text)
        LEFT   JOIN poultryproducts p ON p.poultryproductid = j."poultryProductId"
        CROSS  JOIN LATERAL (
            SELECT CASE
                     -- Only a crate entry converts, and fnpoultrycrateunits
                     -- returns 1 for anything that is not a raw-egg product, so
                     -- crate-counted birds or feed stay 1:1.
                     WHEN lower(COALESCE(j."entryUnit", '')) = 'crate'
                     THEN public.fnpoultrycrateunits(j."poultryProductId",
                                                     COALESCE(j."eggsPerCrate", 30))::numeric
                     ELSE 1::numeric
                   END AS factor
        ) v
        WHERE  j."poultryProductId" IS NOT NULL
          AND  COALESCE(j."entryQuantity", 0) > 0;
    END IF;

    -- Keep the header in step with its lines, draft included (migration 215).
    UPDATE poultryinternalusage h
    SET    totalcostvalue = COALESCE((
               SELECT SUM(i.totalcost) FROM poultryinternalusageitems i
               WHERE  i.poultryinternalusageid = h.poultryinternalusageid), 0),
           updatedat = (now() at time zone 'utc')
    WHERE  h.poultryinternalusageid = p_poultryinternalusageid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryinternalusage_insert(
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
BEGIN
    IF COALESCE(btrim(p_category), '') = '' THEN
        RAISE EXCEPTION 'Pick what the stock was used for.';
    END IF;

    INSERT INTO poultryinternalusage (farmid, usagedate, category, reason, recipientname,
                                      responsiblestaffid, staffcount, notes, status, createdby)
    VALUES (p_farmid, COALESCE(p_usagedate, now() at time zone 'utc'), p_category, p_reason,
            p_recipientname, p_responsiblestaffid, p_staffcount, p_notes, 'Draft', p_createdby)
    RETURNING poultryinternalusageid INTO v_id;

    UPDATE poultryinternalusage
    SET    referenceno = 'IU-' || to_char(COALESCE(p_usagedate, now() at time zone 'utc'), 'YYYY')
                                || '-' || lpad(v_id::text, 4, '0')
    WHERE  poultryinternalusageid = v_id;

    PERFORM public.sppoultryinternalusage_replaceitems(v_id, p_farmid, p_itemsjson);
    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryinternalusage_update(
    p_poultryinternalusageid integer,
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
    SELECT h.status INTO v_status FROM poultryinternalusage h
    WHERE  h.poultryinternalusageid = p_poultryinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Internal use record % not found.', p_poultryinternalusageid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a draft can be edited. This record is %. Reverse it and create a new one.', v_status;
    END IF;

    UPDATE poultryinternalusage
    SET    usagedate          = COALESCE(p_usagedate, usagedate),
           category           = COALESCE(NULLIF(btrim(p_category), ''), category),
           reason             = p_reason,
           recipientname      = p_recipientname,
           responsiblestaffid = p_responsiblestaffid,
           staffcount         = p_staffcount,
           notes              = p_notes,
           updatedat          = (now() at time zone 'utc')
    WHERE  poultryinternalusageid = p_poultryinternalusageid AND farmid = p_farmid;

    PERFORM public.sppoultryinternalusage_replaceitems(p_poultryinternalusageid, p_farmid, p_itemsjson);
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryinternalusage_delete(
    p_poultryinternalusageid integer, p_farmid text, p_userid text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
BEGIN
    SELECT h.status INTO v_status FROM poultryinternalusage h
    WHERE  h.poultryinternalusageid = p_poultryinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN RETURN; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'A % record cannot be deleted -- reverse it instead, so the stock history survives.', v_status;
    END IF;

    DELETE FROM poultryinternalusage
    WHERE poultryinternalusageid = p_poultryinternalusageid AND farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Post.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryinternalusage_post(
    p_poultryinternalusageid integer, p_farmid text, p_postedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status  text;
    v_total   numeric(14,2) := 0;
    v_net     numeric(14,3);
    v_delta   numeric(14,3);
    v_onhand  numeric(14,3);
    v_gid     uuid;
    v_user    text;
    r         record;
BEGIN
    SELECT h.status INTO v_status FROM poultryinternalusage h
    WHERE  h.poultryinternalusageid = p_poultryinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Internal use record % not found.', p_poultryinternalusageid;
    END IF;
    IF v_status = 'Posted' THEN RETURN; END IF;   -- guard 1 of 2
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Cannot post a % record.', v_status;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM poultryinternalusageitems
                   WHERE poultryinternalusageid = p_poultryinternalusageid) THEN
        RAISE EXCEPTION 'Add at least one product before posting.';
    END IF;

    -- Fill any blank cost from the weighted average, scaled into the entry unit.
    UPDATE poultryinternalusageitems i
    SET    entryunitcost = ROUND(
               public.fnpoultryproductavgcost(p_farmid, i.poultryproductid)
               * GREATEST(i.unitsperentryunit, 1), 4)
    WHERE  i.poultryinternalusageid = p_poultryinternalusageid
      AND  i.entryunitcost = 0;

    UPDATE poultryinternalusageitems
    SET    unitcost  = ROUND(entryunitcost / GREATEST(unitsperentryunit, 0.000001), 4),
           totalcost = ROUND(entryquantity * entryunitcost, 2)
    WHERE  poultryinternalusageid = p_poultryinternalusageid;

    -- Pre-flight: refuse the whole record rather than driving a product negative.
    FOR r IN SELECT i.*, p.name AS productname
             FROM   poultryinternalusageitems i
             LEFT   JOIN poultryproducts p ON p.poultryproductid = i.poultryproductid
             WHERE  i.poultryinternalusageid = p_poultryinternalusageid
    LOOP
        SELECT COALESCE(SUM(t.quantity), 0) INTO v_onhand
        FROM   poultrystocktransactions t
        WHERE  t.farmid = p_farmid AND t.poultryproductid = r.poultryproductid;

        IF r.stockquantity > v_onhand THEN
            RAISE EXCEPTION 'Not enough %: % in stock, % needed.',
                COALESCE(r.productname, 'product ' || r.poultryproductid), v_onhand, r.stockquantity;
        END IF;
    END LOOP;

    FOR r IN SELECT * FROM poultryinternalusageitems
             WHERE poultryinternalusageid = p_poultryinternalusageid
    LOOP
        -- Migration 179's append-only delta rule. Target -stockquantity on post,
        -- 0 on reverse. Nothing is ever deleted or rewritten, and a repeat run
        -- computes delta 0 -- guard 2 of 2.
        SELECT COALESCE(SUM(t.quantity), 0) INTO v_net
        FROM   poultrystocktransactions t
        WHERE  t.farmid = p_farmid
          AND  t.txntype = 'InternalUse'
          AND  t.relatedid = p_poultryinternalusageid
          AND  t.poultryproductid = r.poultryproductid;

        v_delta := (-r.stockquantity) - v_net;

        IF v_delta <> 0 THEN
            INSERT INTO poultrystocktransactions
                (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby)
            VALUES (p_farmid, r.poultryproductid, 'InternalUse', v_delta,
                    NULLIF(r.entryunitcost, 0),   -- per entry unit, as elsewhere
                    p_poultryinternalusageid,
                    'Internal use ' || COALESCE(
                        (SELECT referenceno FROM poultryinternalusage
                         WHERE poultryinternalusageid = p_poultryinternalusageid),
                        '#' || p_poultryinternalusageid::text),
                    p_postedby);
        END IF;
    END LOOP;

    SELECT COALESCE(SUM(totalcost), 0) INTO v_total
    FROM   poultryinternalusageitems WHERE poultryinternalusageid = p_poultryinternalusageid;

    UPDATE poultryinternalusage
    SET    status = 'Posted', totalcostvalue = v_total,
           postedby = p_postedby, postedat = (now() at time zone 'utc'),
           updatedat = (now() at time zone 'utc')
    WHERE  poultryinternalusageid = p_poultryinternalusageid AND farmid = p_farmid;

    -- ---- linked expense -----------------------------------------------------
    -- expense.farmid is a uuid and expense.userid is NOT NULL, so both are
    -- guarded: a farm id that will not cast, or no user to attribute it to,
    -- skips the expense rather than failing the whole posting (migration 207's
    -- convention). Cash is never touched -- poultry cash is written by
    -- SyncExpenseCashAsync in C#, never by an SP that inserts into expense.
    BEGIN v_gid := p_farmid::uuid; EXCEPTION WHEN OTHERS THEN v_gid := NULL; END;

    SELECT COALESCE(p_postedby, h.createdby) INTO v_user
    FROM   poultryinternalusage h WHERE h.poultryinternalusageid = p_poultryinternalusageid;

    IF v_gid IS NOT NULL AND v_user IS NOT NULL AND v_total > 0
       AND NOT EXISTS (SELECT 1 FROM expense e
                       WHERE e.farmid = v_gid
                         AND e.sourcetype = 'PoultryInternalUsage'
                         AND e.sourceid = p_poultryinternalusageid)
    THEN
        INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                             supplier, flockid, createddate, userid, farmid, sourcetype, sourceid)
        SELECT h.usagedate, 'Internal Use',
               'Internal use: ' || h.category || COALESCE(' - ' || h.recipientname, ''),
               v_total, 'NonCash', NULL, NULL, (now() at time zone 'utc'),
               v_user, v_gid, 'PoultryInternalUsage', p_poultryinternalusageid
        FROM   poultryinternalusage h
        WHERE  h.poultryinternalusageid = p_poultryinternalusageid;
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Reverse.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryinternalusage_reverse(
    p_poultryinternalusageid integer,
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
    v_gid    uuid;
    r        record;
BEGIN
    SELECT h.status INTO v_status FROM poultryinternalusage h
    WHERE  h.poultryinternalusageid = p_poultryinternalusageid AND h.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Internal use record % not found.', p_poultryinternalusageid;
    END IF;
    IF v_status = 'Reversed' THEN RETURN; END IF;
    IF v_status <> 'Posted' THEN
        RAISE EXCEPTION 'Only a posted record can be reversed. This one is %.', v_status;
    END IF;

    FOR r IN SELECT * FROM poultryinternalusageitems
             WHERE poultryinternalusageid = p_poultryinternalusageid
    LOOP
        SELECT COALESCE(SUM(t.quantity), 0) INTO v_net
        FROM   poultrystocktransactions t
        WHERE  t.farmid = p_farmid
          AND  t.txntype = 'InternalUse'
          AND  t.relatedid = p_poultryinternalusageid
          AND  t.poultryproductid = r.poultryproductid;

        v_delta := 0 - v_net;   -- the exact opposite; originals stay put

        IF v_delta <> 0 THEN
            INSERT INTO poultrystocktransactions
                (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby)
            VALUES (p_farmid, r.poultryproductid, 'InternalUse', v_delta,
                    NULLIF(r.entryunitcost, 0), p_poultryinternalusageid,
                    'Reversal of internal use ' || COALESCE(
                        (SELECT referenceno FROM poultryinternalusage
                         WHERE poultryinternalusageid = p_poultryinternalusageid),
                        '#' || p_poultryinternalusageid::text),
                    p_reversedby);
        END IF;
    END LOOP;

    -- DELETE, not a negative row: `expense` has no isdeleted and no status, and
    -- a negative amount would corrupt every SUM(amount) report. Migration 207
    -- deletes by (sourcetype, sourceid) for the same reason. The audit trail
    -- lives on the header and in the append-only ledger above.
    BEGIN v_gid := p_farmid::uuid; EXCEPTION WHEN OTHERS THEN v_gid := NULL; END;
    IF v_gid IS NOT NULL THEN
        DELETE FROM expense e
        WHERE e.farmid = v_gid
          AND e.sourcetype = 'PoultryInternalUsage'
          AND e.sourceid = p_poultryinternalusageid;
    END IF;

    UPDATE poultryinternalusage
    SET    status = 'Reversed', reversedby = p_reversedby,
           reversedat = (now() at time zone 'utc'), reversalreason = p_reason,
           updatedat = (now() at time zone 'utc')
    WHERE  poultryinternalusageid = p_poultryinternalusageid AND farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. Keep the non-cash expense out of expected cash at hand.
-- -----------------------------------------------------------------------------
DO $patch$
DECLARE
    v_def text;
    v_new text;
    v_oid oid;
BEGIN
    SELECT p.oid INTO v_oid
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'fnpoultrydailyclosing_livetotals'
    LIMIT  1;

    IF v_oid IS NULL THEN
        RAISE EXCEPTION '216: fnpoultrydailyclosing_livetotals not found -- cannot apply the non-cash carve-out.';
    END IF;

    v_def := pg_get_functiondef(v_oid);

    IF position('PoultryInternalUsage' in v_def) > 0 THEN
        RAISE NOTICE '216: daily-closing carve-out already applied.';
        RETURN;
    END IF;

    -- Whitespace-tolerant: the live body is CRLF-delimited and indented, so a
    -- literal anchor does not match. Match the clause, not its formatting.
    IF v_def !~ 'FROM\s+expense\s+e\s+WHERE\s+e\.farmid' THEN
        RAISE EXCEPTION '216: expected a "FROM expense e WHERE e.farmid" clause in fnpoultrydailyclosing_livetotals and did not find it. The body has drifted -- apply the carve-out by hand.';
    END IF;

    v_new := regexp_replace(
                 v_def,
                 '(FROM\s+expense\s+e\s+WHERE\s+)(e\.farmid)',
                 '\1COALESCE(e.sourcetype, '''') <> ''PoultryInternalUsage'' AND \2',
                 'g');

    IF v_new = v_def THEN
        RAISE EXCEPTION '216: the carve-out substitution changed nothing. Apply it by hand.';
    END IF;

    EXECUTE v_new;
    RAISE NOTICE '216: daily-closing now excludes PoultryInternalUsage from cash at hand.';
END;
$patch$;

-- -----------------------------------------------------------------------------
-- 8. IAM catalog.
-- -----------------------------------------------------------------------------
DO $iam$
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '216: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'poultry.internal-use.' || a.action, 'poultry', 'internal-use', a.action,
           'Inventory', 'Internal Use',
           'Stock consumed internally - staff welfare, owner use, donations, samples, testing.',
           'Poultry', FALSE, 52
    FROM   (VALUES ('view'), ('create'), ('edit'), ('delete')) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;
END;
$iam$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification, including a rolled-back round trip through the write path.
-- -----------------------------------------------------------------------------
SELECT 'tables' AS check,
       CASE WHEN to_regclass('public.poultryinternalusage') IS NOT NULL
             AND to_regclass('public.poultryinternalusageitems') IS NOT NULL
            THEN 'OK' ELSE 'MISSING' END AS result
UNION ALL
SELECT 'functions (7 expected)',
       CASE WHEN count(*) >= 7 THEN 'OK (' || count(*) || ')' ELSE 'MISSING (' || count(*) || ')' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname LIKE 'sppoultryinternalusage%'
UNION ALL
SELECT 'cash carve-out',
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = 'fnpoultrydailyclosing_livetotals'
                AND pg_get_functiondef(p.oid) LIKE '%PoultryInternalUsage%')
            THEN 'OK' ELSE 'NOT APPLIED' END;

BEGIN;
DO $verify$
DECLARE
    v_farm text; v_prod integer; v_id integer; r record;
BEGIN
    SELECT p.farmid, p.poultryproductid INTO v_farm, v_prod
    FROM   poultryproducts p WHERE COALESCE(p.israweggproduct, FALSE) = TRUE LIMIT 1;

    IF v_farm IS NULL THEN
        RAISE NOTICE '216: no raw-egg product on file, skipping the round-trip check.';
        RETURN;
    END IF;

    INSERT INTO poultryinternalusage (farmid, category, status, createdby)
    VALUES (v_farm, 'StaffWelfare', 'Draft', '216-verify')
    RETURNING poultryinternalusageid INTO v_id;

    PERFORM public.sppoultryinternalusage_replaceitems(
        v_id, v_farm,
        '[{"poultryProductId":' || v_prod || ',"entryQuantity":10,"entryUnit":"Crate","entryUnitCost":15}]');

    SELECT i.entryquantity, i.stockquantity, i.entryunitcost, i.unitcost, i.totalcost,
           h.totalcostvalue
    INTO   r
    FROM   poultryinternalusageitems i
    JOIN   poultryinternalusage h ON h.poultryinternalusageid = i.poultryinternalusageid
    WHERE  i.poultryinternalusageid = v_id;

    IF r IS NULL THEN
        RAISE EXCEPTION '216: the item line was dropped -- check the JSON key binding.';
    END IF;

    RAISE NOTICE '216: 10 crates -> % eggs, % per crate = % total (% per egg), header %.',
        r.stockquantity, r.entryunitcost, r.totalcost, r.unitcost, r.totalcostvalue;

    IF r.stockquantity <= r.entryquantity THEN
        RAISE EXCEPTION '216: the crate->egg conversion did not apply.';
    END IF;
    IF r.totalcostvalue <> r.totalcost THEN
        RAISE EXCEPTION '216: the header total did not roll up.';
    END IF;
END;
$verify$;
ROLLBACK;

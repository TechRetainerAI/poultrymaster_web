-- 485: Projects & Contracts -- reserving company stock for a project.
--
-- A reservation says "these units on the shelf are meant for Contract A". It is
-- NOT a stock movement: company stock, its value and its cost do not change.
-- Stock only ever changes through the existing ledger (genericstockmovements):
-- a purchase brings it in, a sale takes it out.
--
-- genericprojectstockreservations is a ledger of Reserve / Release /
-- TransferOut / TransferIn entries (quantities in the product's base unit).
-- A wrong entry is reversed (reversedat), never deleted.
--
-- Delivered (consumed) is DERIVED, never entered: the quantity of approved
-- sale lines given to the project for that product, dated on or after the
-- project's first reservation of it. Remaining reserved =
-- max(0, reserved - delivered). No hook is added to sale approval.
--
-- Rule: all projects' remaining reservations of a product together can never
-- exceed the company's stock on hand (genericproducts.currentstock). Checked
-- under one advisory lock per product.

BEGIN;

CREATE TABLE IF NOT EXISTS genericprojectstockreservations (
    genericprojectstockreservationid serial PRIMARY KEY,
    farmid            text          NOT NULL,
    genericprojectid  integer       NOT NULL REFERENCES genericprojects (genericprojectid),
    genericproductid  integer       NOT NULL,
    entrytype         text          NOT NULL CHECK (entrytype IN ('Reserve', 'Release', 'TransferOut', 'TransferIn')),
    quantity          numeric(18,3) NOT NULL CHECK (quantity > 0),
    entrydate         date          NOT NULL DEFAULT ((now() at time zone 'utc')::date),
    transfergroupid   uuid          NULL,
    note              text          NULL,
    createdby         text          NULL,
    createdat         timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedat        timestamp     NULL,
    reversedby        text          NULL,
    reversalreason    text          NULL
);
CREATE INDEX IF NOT EXISTS ix_genericprojectstockreservations_product
    ON genericprojectstockreservations (farmid, genericproductid) WHERE reversedat IS NULL;
CREATE INDEX IF NOT EXISTS ix_genericprojectstockreservations_project
    ON genericprojectstockreservations (farmid, genericprojectid);

-- Per project and product: reserved (net), delivered since first reserved,
-- remaining. Only products that have reservations or project sales/purchases.
CREATE OR REPLACE FUNCTION public.fngenericproject_stockposition(p_farmid text)
RETURNS TABLE(projectid integer, productid integer, reserved numeric, delivered numeric,
              remaining numeric, firstreserved date)
LANGUAGE sql STABLE AS $f$
    WITH r AS (
        SELECT genericprojectid AS projectid, genericproductid AS productid,
               sum(CASE WHEN entrytype IN ('Reserve', 'TransferIn') THEN quantity ELSE -quantity END) AS reserved,
               min(entrydate) FILTER (WHERE entrytype IN ('Reserve', 'TransferIn')) AS firstreserved
        FROM genericprojectstockreservations
        WHERE farmid = p_farmid AND reversedat IS NULL
        GROUP BY 1, 2
    ), d AS (
        SELECT a.genericprojectid AS projectid, i.genericproductid AS productid, s.saledate::date AS day,
               i.quantity * coalesce(nullif(i.unitfactor, 0), 1) * a.share AS qty
        FROM genericprojectallocations a
        JOIN genericsaleitems i ON i.genericsaleitemid = a.sourcelineid AND i.genericsaleid = a.sourceid
        JOIN genericsales s ON s.genericsaleid = i.genericsaleid AND s.farmid = p_farmid
        WHERE a.farmid = p_farmid AND a.status = 'Active' AND a.sourcetype = 'SaleLine'
          AND s.status = 'Approved' AND NOT coalesce(s.isdeleted, false) AND i.genericproductid IS NOT NULL
    )
    SELECT r.projectid, r.productid, r.reserved,
           COALESCE((SELECT sum(d.qty) FROM d WHERE d.projectid = r.projectid AND d.productid = r.productid
                       AND d.day >= r.firstreserved), 0),
           GREATEST(r.reserved - COALESCE((SELECT sum(d.qty) FROM d WHERE d.projectid = r.projectid
                       AND d.productid = r.productid AND d.day >= r.firstreserved), 0), 0),
           r.firstreserved
    FROM r;
$f$;

CREATE OR REPLACE FUNCTION public.fngenericproject_assertstock(p_farmid text, p_productid integer)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_onhand numeric; v_reserved numeric; v_name text;
BEGIN
    SELECT currentstock, productname INTO v_onhand, v_name
      FROM genericproducts WHERE genericproductid = p_productid AND farmid = p_farmid;
    SELECT COALESCE(sum(remaining), 0) INTO v_reserved
      FROM fngenericproject_stockposition(p_farmid) WHERE productid = p_productid;
    IF v_reserved > COALESCE(v_onhand, 0) THEN
        RAISE EXCEPTION 'Only % % in stock, and projects would then hold % of them. Reserve no more than is on the shelf.',
            trim(to_char(COALESCE(v_onhand, 0), 'FM999G999G990D###')), v_name,
            trim(to_char(v_reserved, 'FM999G999G990D###')) USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- p_action: Reserve | Release | Transfer (to p_toprojectid)
CREATE OR REPLACE FUNCTION public.spgenericproject_reservestock(
    p_farmid text, p_projectid integer, p_productid integer, p_action text, p_quantity numeric,
    p_toprojectid integer, p_date date, p_note text, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_prj genericprojects; v_to genericprojects; v_remaining numeric; v_id integer; v_group uuid;
    v_track boolean;
BEGIN
    PERFORM fngenericproject_assertenabled(p_farmid);
    v_prj := fngenericproject_require(p_farmid, p_projectid);
    IF v_prj.status IN ('Archived', 'Cancelled', 'Completed') AND p_action <> 'Release' THEN
        RAISE EXCEPTION 'This project is %; stock can only be released from it.', lower(v_prj.status) USING ERRCODE = 'P0001';
    END IF;
    SELECT trackinventory INTO v_track FROM genericproducts
     WHERE genericproductid = p_productid AND farmid = p_farmid AND NOT coalesce(isdeleted, false);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That product was not found in this company.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT COALESCE(v_track, false) THEN
        RAISE EXCEPTION 'This product''s stock is not tracked, so it cannot be reserved.' USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(p_quantity, 0) <= 0 THEN
        RAISE EXCEPTION 'Enter a quantity more than zero.' USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('genericproject_stock:' || p_farmid || ':' || p_productid));

    SELECT COALESCE(remaining, 0) INTO v_remaining FROM fngenericproject_stockposition(p_farmid)
     WHERE projectid = p_projectid AND productid = p_productid;
    v_remaining := COALESCE(v_remaining, 0);

    IF p_action = 'Reserve' THEN
        INSERT INTO genericprojectstockreservations (farmid, genericprojectid, genericproductid, entrytype, quantity,
                                                     entrydate, note, createdby)
        VALUES (p_farmid, p_projectid, p_productid, 'Reserve', p_quantity, COALESCE(p_date, (now() at time zone 'utc')::date),
                NULLIF(btrim(p_note), ''), p_by)
        RETURNING genericprojectstockreservationid INTO v_id;
        PERFORM fngenericproject_assertstock(p_farmid, p_productid);
    ELSIF p_action = 'Release' THEN
        IF p_quantity > v_remaining THEN
            RAISE EXCEPTION 'Only % are still reserved for this project.', trim(to_char(v_remaining, 'FM999G999G990D###'))
                USING ERRCODE = 'P0001';
        END IF;
        INSERT INTO genericprojectstockreservations (farmid, genericprojectid, genericproductid, entrytype, quantity,
                                                     entrydate, note, createdby)
        VALUES (p_farmid, p_projectid, p_productid, 'Release', p_quantity, COALESCE(p_date, (now() at time zone 'utc')::date),
                NULLIF(btrim(p_note), ''), p_by)
        RETURNING genericprojectstockreservationid INTO v_id;
    ELSIF p_action = 'Transfer' THEN
        v_to := fngenericproject_require(p_farmid, p_toprojectid);
        IF v_to.genericprojectid = v_prj.genericprojectid THEN
            RAISE EXCEPTION 'Choose a different project to move the stock to.' USING ERRCODE = 'P0001';
        END IF;
        IF v_to.status IN ('Archived', 'Cancelled', 'Completed') THEN
            RAISE EXCEPTION 'Stock cannot be moved to a % project.', lower(v_to.status) USING ERRCODE = 'P0001';
        END IF;
        IF p_quantity > v_remaining THEN
            RAISE EXCEPTION 'Only % are still reserved for this project.', trim(to_char(v_remaining, 'FM999G999G990D###'))
                USING ERRCODE = 'P0001';
        END IF;
        v_group := gen_random_uuid();
        INSERT INTO genericprojectstockreservations (farmid, genericprojectid, genericproductid, entrytype, quantity,
                                                     entrydate, transfergroupid, note, createdby)
        VALUES (p_farmid, p_projectid, p_productid, 'TransferOut', p_quantity, COALESCE(p_date, (now() at time zone 'utc')::date),
                v_group, NULLIF(btrim(p_note), ''), p_by),
               (p_farmid, p_toprojectid, p_productid, 'TransferIn', p_quantity, COALESCE(p_date, (now() at time zone 'utc')::date),
                v_group, NULLIF(btrim(p_note), ''), p_by);
        SELECT max(genericprojectstockreservationid) INTO v_id FROM genericprojectstockreservations WHERE transfergroupid = v_group;
        PERFORM fngenericproject_assertstock(p_farmid, p_productid);
    ELSE
        RAISE EXCEPTION 'Choose Reserve, Release or Transfer.' USING ERRCODE = 'P0001';
    END IF;
    RETURN v_id;
END
$f$;

-- Reverse a wrong entry (both halves of a transfer together).
CREATE OR REPLACE FUNCTION public.spgenericproject_reversereservation(
    p_farmid text, p_entryid integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE r genericprojectstockreservations;
BEGIN
    PERFORM fngenericproject_assertenabled(p_farmid);
    SELECT * INTO r FROM genericprojectstockreservations
     WHERE genericprojectstockreservationid = p_entryid AND farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That reservation entry was not found in this company.' USING ERRCODE = 'P0001';
    END IF;
    IF r.reversedat IS NOT NULL THEN RETURN; END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why this entry is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('genericproject_stock:' || p_farmid || ':' || r.genericproductid));
    UPDATE genericprojectstockreservations
       SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversalreason = btrim(p_reason)
     WHERE farmid = p_farmid AND reversedat IS NULL
       AND (genericprojectstockreservationid = p_entryid
            OR (r.transfergroupid IS NOT NULL AND transfergroupid = r.transfergroupid));
    -- Undoing a Release or a transfer puts stock back on a reservation: still
    -- may not exceed what is on the shelf.
    PERFORM fngenericproject_assertstock(p_farmid, r.genericproductid);
END
$f$;

-- The inventory tab of one project.
CREATE OR REPLACE FUNCTION public.spgenericproject_inventory(p_farmid text, p_projectid integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
BEGIN
    PERFORM fngenericproject_require(p_farmid, p_projectid);
    RETURN jsonb_build_object(
        'products', COALESCE((
            WITH pos AS (SELECT * FROM fngenericproject_stockposition(p_farmid)),
            bought AS (
                SELECT productid, sum(quantity) AS qty, sum(amount) AS value
                FROM fngenericproject_purchases(p_farmid, NULL, NULL) WHERE projectid = p_projectid GROUP BY 1
            ), sold AS (
                SELECT i.genericproductid AS productid,
                       sum(i.quantity * coalesce(nullif(i.unitfactor, 0), 1) * a.share) AS qty,
                       sum(i.linetotal * a.share) AS value
                FROM genericprojectallocations a
                JOIN genericsaleitems i ON i.genericsaleitemid = a.sourcelineid AND i.genericsaleid = a.sourceid
                JOIN genericsales s ON s.genericsaleid = i.genericsaleid AND s.farmid = p_farmid
                WHERE a.farmid = p_farmid AND a.status = 'Active' AND a.sourcetype = 'SaleLine'
                  AND a.genericprojectid = p_projectid AND s.status = 'Approved' AND NOT coalesce(s.isdeleted, false)
                  AND i.genericproductid IS NOT NULL
                GROUP BY 1
            ), ids AS (
                SELECT productid FROM bought UNION SELECT productid FROM sold
                UNION SELECT productid FROM pos WHERE projectid = p_projectid
            )
            SELECT jsonb_agg(jsonb_build_object(
                'productId', g.genericproductid, 'productName', g.productname, 'unit', g.unitofmeasure,
                'costPrice', g.costprice,
                'purchasedQuantity', round(COALESCE(b.qty, 0), 3), 'purchasedValue', round(COALESCE(b.value, 0), 2),
                'reservedQuantity', round(COALESCE(p.reserved, 0), 3),
                'deliveredQuantity', round(COALESCE(s.qty, 0), 3), 'deliveredValue', round(COALESCE(s.value, 0), 2),
                'remainingReserved', round(COALESCE(p.remaining, 0), 3),
                'remainingReservedValue', round(COALESCE(p.remaining, 0) * COALESCE(g.costprice, 0), 2),
                'companyOnHand', g.currentstock,
                'reservedForAllProjects', round(COALESCE((SELECT sum(remaining) FROM pos x WHERE x.productid = g.genericproductid), 0), 3),
                'availableToCompany', round(g.currentstock - COALESCE((SELECT sum(remaining) FROM pos x WHERE x.productid = g.genericproductid), 0), 3))
                ORDER BY g.productname)
            FROM ids i JOIN genericproducts g ON g.genericproductid = i.productid AND g.farmid = p_farmid
            LEFT JOIN bought b ON b.productid = i.productid
            LEFT JOIN sold s ON s.productid = i.productid
            LEFT JOIN pos p ON p.productid = i.productid AND p.projectid = p_projectid), '[]'::jsonb),
        'entries', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'entryId', r.genericprojectstockreservationid, 'productId', r.genericproductid,
                'productName', g.productname, 'entryType', r.entrytype, 'quantity', r.quantity,
                'date', r.entrydate, 'note', r.note, 'createdBy', r.createdby, 'createdAt', r.createdat,
                'otherProject', (SELECT p2.projectnumber || ' — ' || p2.name FROM genericprojectstockreservations r2
                                 JOIN genericprojects p2 ON p2.genericprojectid = r2.genericprojectid
                                 WHERE r.transfergroupid IS NOT NULL AND r2.transfergroupid = r.transfergroupid
                                   AND r2.genericprojectstockreservationid <> r.genericprojectstockreservationid),
                'reversedAt', r.reversedat, 'reversedBy', r.reversedby, 'reversalReason', r.reversalreason)
                ORDER BY r.createdat DESC, r.genericprojectstockreservationid DESC)
            FROM genericprojectstockreservations r
            JOIN genericproducts g ON g.genericproductid = r.genericproductid
            WHERE r.farmid = p_farmid AND r.genericprojectid = p_projectid), '[]'::jsonb));
END
$f$;

-- Company-wide: what is reserved for which project (inventory page column).
CREATE OR REPLACE FUNCTION public.spgenericproject_reservedstock(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'productId', x.productid, 'reserved', round(x.total, 3),
               'projects', x.projects)), '[]'::jsonb)
    FROM (SELECT s.productid, sum(s.remaining) AS total,
                 jsonb_agg(jsonb_build_object('projectId', s.projectid,
                     'label', p.projectnumber || ' — ' || p.name, 'remaining', round(s.remaining, 3))
                     ORDER BY p.projectnumber) AS projects
          FROM fngenericproject_stockposition(p_farmid) s
          JOIN genericprojects p ON p.genericprojectid = s.projectid
          WHERE s.remaining > 0
          GROUP BY s.productid) x;
$f$;

COMMIT;

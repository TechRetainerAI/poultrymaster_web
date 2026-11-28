-- 511_Winchester_GenericPharmacy.postgres.sql
--
-- Pharmacy for Generic companies whose industry template is "Pharmacy" (a drug shop:
-- a full pharmacy or a small over-the-counter chemical shop, Ghana). No NHIS / insurance.
--
--  1. genericpharmacysettings   : shop type (Pharmacy / ChemicalShop) and whether a
--                                 Class A sale needs a prescription record.
--  2. genericmedicines          : medicine details on top of a Generic product
--                                 (generic name, strength, form, class A/B/C, FDA Ghana reg. no.).
--  3. genericproductpacks       : how a product is sold in bigger packs (Strip = 10 tablets,
--                                 Box = 100 tablets) and the price of each pack. Saving a pack
--                                 also writes the product's unit conversion (364), so Purchases
--                                 and Sales already know "1 Box = 100 tablet".
--  4. genericproductbatches     : batches with batch number and expiry date. A batch is created
--                                 when a purchase whose lines carry batch details is APPROVED
--                                 (trigger), or by hand for stock already on the shelf.
--     genericpurchaseitems      : + batchnumber, expirydate (set while the purchase is Draft).
--  5. What is left in each batch is STORED (quantityremaining) and kept by one trigger on
--     genericstockmovements, so no existing stock flow (sales, POS, loss, internal use,
--     adjustments, reversals) had to change. Every stock movement OUT takes from:
--       a) the batch it names first: a purchase reversal takes from that purchase's batches,
--          a batch write-off (genericproductbatchwriteoffs) from that batch;
--       b) then stock with no batch recorded (older stock);
--       c) then batches that have not expired, earliest expiry first (first-expiry-first-out);
--       d) then expired batches.
--     Stock coming back IN (sale return, adjustment in) has no batch; label it by hand if needed.
--  6. genericprescriptions (+ items): the prescription a Class A sale was dispensed against.
--  7. spgenericpharmacy_report  : per-medicine sales, profit, stock and expiry for a period.
--
-- No existing function is changed. Safe to run twice. No BEGIN/COMMIT (RunMigration rule).

-- ---------------------------------------------------------------------------
-- 1. Settings
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericpharmacysettings (
    farmid                      VARCHAR(450) PRIMARY KEY,
    shoptype                    VARCHAR(20)  NOT NULL DEFAULT 'Pharmacy',
    requireprescriptionclassa   BOOLEAN      NOT NULL DEFAULT TRUE,
    expirywarningdays           INT          NOT NULL DEFAULT 90,
    updatedby                   TEXT NULL,
    updatedat                   TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    CONSTRAINT ck_genericpharmacysettings_shoptype CHECK (shoptype IN ('Pharmacy', 'ChemicalShop')),
    CONSTRAINT ck_genericpharmacysettings_days CHECK (expirywarningdays BETWEEN 1 AND 730)
);

-- ---------------------------------------------------------------------------
-- 2. Medicine details
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericmedicines (
    genericproductid    INT PRIMARY KEY,
    farmid              VARCHAR(450) NOT NULL,
    genericname         VARCHAR(200) NULL,
    strength            VARCHAR(80)  NULL,
    dosageform          VARCHAR(60)  NULL,
    medicineclass       CHAR(1)      NOT NULL DEFAULT 'C',
    fdaregno            VARCHAR(80)  NULL,
    manufacturer        VARCHAR(200) NULL,
    storagenote         VARCHAR(300) NULL,
    iscontrolled        BOOLEAN      NOT NULL DEFAULT FALSE,
    createdat           TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updatedat           TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updatedby           TEXT NULL,
    CONSTRAINT ck_genericmedicines_class CHECK (medicineclass IN ('A', 'B', 'C'))
);
CREATE INDEX IF NOT EXISTS ix_genericmedicines_farmid ON genericmedicines (farmid);

-- ---------------------------------------------------------------------------
-- 3. Packs (Strip, Box ...) with their own price
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericproductpacks (
    genericproductpackid SERIAL PRIMARY KEY,
    farmid               VARCHAR(450) NOT NULL,
    genericproductid     INT          NOT NULL,
    packname             VARCHAR(50)  NOT NULL,
    unitsperpack         NUMERIC(14, 4) NOT NULL,
    sellingprice         NUMERIC(18, 2) NOT NULL DEFAULT 0,
    isactive             BOOLEAN      NOT NULL DEFAULT TRUE,
    createdat            TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updatedat            TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    CONSTRAINT ck_genericproductpacks_units CHECK (unitsperpack > 0),
    CONSTRAINT ck_genericproductpacks_price CHECK (sellingprice >= 0),
    CONSTRAINT uq_genericproductpacks UNIQUE (farmid, genericproductid, packname)
);

-- ---------------------------------------------------------------------------
-- 4. Batches
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericproductbatches (
    genericproductbatchid SERIAL PRIMARY KEY,
    farmid                VARCHAR(450) NOT NULL,
    genericproductid      INT          NOT NULL,
    batchnumber           VARCHAR(80)  NULL,
    expirydate            DATE         NULL,
    quantityreceived      NUMERIC(18, 4) NOT NULL,
    unitcost              NUMERIC(18, 4) NULL,
    receiveddate          DATE         NOT NULL DEFAULT CURRENT_DATE,
    sourcetype            VARCHAR(20)  NOT NULL DEFAULT 'Manual',
    genericpurchaseid     INT NULL,
    genericpurchaseitemid INT NULL,
    notes                 VARCHAR(500) NULL,
    isdeleted             BOOLEAN      NOT NULL DEFAULT FALSE,
    createdby             TEXT NULL,
    createdat             TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updatedat             TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    CONSTRAINT ck_genericproductbatches_qty CHECK (quantityreceived > 0),
    CONSTRAINT ck_genericproductbatches_source CHECK (sourcetype IN ('Purchase', 'Manual'))
);
CREATE INDEX IF NOT EXISTS ix_genericproductbatches_product ON genericproductbatches (farmid, genericproductid);
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericproductbatches_purchaseitem
    ON genericproductbatches (genericpurchaseitemid)
    WHERE genericpurchaseitemid IS NOT NULL AND isdeleted = FALSE;

ALTER TABLE genericproductbatches ADD COLUMN IF NOT EXISTS quantityremaining NUMERIC(18, 4) NOT NULL DEFAULT 0;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_genericproductbatches_remaining') THEN
        ALTER TABLE genericproductbatches ADD CONSTRAINT ck_genericproductbatches_remaining
            CHECK (quantityremaining >= 0 AND quantityremaining <= quantityreceived);
    END IF;
END $$;

-- A write-off of one batch: the stock adjustment it raised, so the trigger takes the
-- adjustment's quantity from that batch.
CREATE TABLE IF NOT EXISTS genericproductbatchwriteoffs (
    genericproductbatchwriteoffid SERIAL PRIMARY KEY,
    farmid                     VARCHAR(450) NOT NULL,
    genericproductbatchid      INT NOT NULL REFERENCES genericproductbatches (genericproductbatchid),
    genericstockadjustmentid   INT NOT NULL,
    quantity                   NUMERIC(18, 4) NOT NULL,
    reason                     VARCHAR(500) NULL,
    createdby                  TEXT NULL,
    createdat                  TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    CONSTRAINT ck_genericproductbatchwriteoffs_qty CHECK (quantity > 0)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericproductbatchwriteoffs_adj ON genericproductbatchwriteoffs (genericstockadjustmentid);

ALTER TABLE genericpurchaseitems ADD COLUMN IF NOT EXISTS batchnumber VARCHAR(80) NULL;
ALTER TABLE genericpurchaseitems ADD COLUMN IF NOT EXISTS expirydate DATE NULL;

-- ---------------------------------------------------------------------------
-- 6. Prescriptions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericprescriptions (
    genericprescriptionid SERIAL PRIMARY KEY,
    farmid                VARCHAR(450) NOT NULL,
    genericsaleid         INT NULL,
    prescriptiondate      DATE NOT NULL DEFAULT CURRENT_DATE,
    patientname           VARCHAR(200) NOT NULL,
    patientphone          VARCHAR(40)  NULL,
    prescribername        VARCHAR(200) NOT NULL,
    prescriberfacility    VARCHAR(200) NULL,
    prescriptionref       VARCHAR(80)  NULL,
    notes                 VARCHAR(1000) NULL,
    isdeleted             BOOLEAN NOT NULL DEFAULT FALSE,
    createdby             TEXT NULL,
    createdat             TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
CREATE INDEX IF NOT EXISTS ix_genericprescriptions_farm ON genericprescriptions (farmid, prescriptiondate);

CREATE TABLE IF NOT EXISTS genericprescriptionitems (
    genericprescriptionitemid SERIAL PRIMARY KEY,
    genericprescriptionid     INT NOT NULL REFERENCES genericprescriptions (genericprescriptionid) ON DELETE CASCADE,
    farmid                    VARCHAR(450) NOT NULL,
    genericproductid          INT NULL,
    medicinename              VARCHAR(200) NOT NULL,
    quantity                  NUMERIC(18, 4) NOT NULL DEFAULT 0,
    unit                      VARCHAR(50) NULL,
    directions                VARCHAR(500) NULL
);

-- ===========================================================================
-- Settings functions
-- ===========================================================================
CREATE OR REPLACE FUNCTION spgenericpharmacy_settings_get(p_farmid TEXT)
RETURNS JSONB LANGUAGE sql STABLE AS $fn$
    SELECT jsonb_build_object(
        'shopType',                  COALESCE(s.shoptype, 'Pharmacy'),
        'requirePrescriptionClassA', COALESCE(s.requireprescriptionclassa, TRUE),
        'expiryWarningDays',         COALESCE(s.expirywarningdays, 90),
        'saved',                     s.farmid IS NOT NULL)
    FROM (SELECT 1) one
    LEFT JOIN genericpharmacysettings s ON s.farmid = p_farmid;
$fn$;

CREATE OR REPLACE FUNCTION spgenericpharmacy_settings_save(
    p_farmid TEXT, p_shoptype TEXT, p_requireprescriptionclassa BOOLEAN,
    p_expirywarningdays INT DEFAULT 90, p_by TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    IF p_shoptype NOT IN ('Pharmacy', 'ChemicalShop') THEN
        RAISE EXCEPTION 'Shop type must be Pharmacy or ChemicalShop.';
    END IF;
    INSERT INTO genericpharmacysettings AS s (farmid, shoptype, requireprescriptionclassa, expirywarningdays, updatedby, updatedat)
    VALUES (p_farmid, p_shoptype, COALESCE(p_requireprescriptionclassa, TRUE), COALESCE(p_expirywarningdays, 90), p_by, now() AT TIME ZONE 'utc')
    ON CONFLICT (farmid) DO UPDATE
        SET shoptype = EXCLUDED.shoptype,
            requireprescriptionclassa = EXCLUDED.requireprescriptionclassa,
            expirywarningdays = EXCLUDED.expirywarningdays,
            updatedby = EXCLUDED.updatedby,
            updatedat = EXCLUDED.updatedat;
END
$fn$;

-- ===========================================================================
-- 5. What is left in each batch (first-expiry-first-out)
-- ===========================================================================
-- Live batches with what is left in them (stored, kept by trg_genericstockmovement_batches).
DROP FUNCTION IF EXISTS fngenericproductbatch_rows(TEXT, INT);
CREATE FUNCTION fngenericproductbatch_rows(p_farmid TEXT, p_productid INT DEFAULT NULL)
RETURNS TABLE (
    genericproductbatchid INT, genericproductid INT, batchnumber TEXT, expirydate DATE,
    receiveddate DATE, quantityreceived NUMERIC, quantityremaining NUMERIC, unitcost NUMERIC,
    sourcetype TEXT, genericpurchaseid INT, notes TEXT)
LANGUAGE sql STABLE AS $fn$
    SELECT gb.genericproductbatchid, gb.genericproductid, gb.batchnumber::text, gb.expirydate,
           gb.receiveddate, gb.quantityreceived, gb.quantityremaining,
           gb.unitcost, gb.sourcetype::text, gb.genericpurchaseid, gb.notes::text
    FROM   genericproductbatches gb
    WHERE  gb.farmid = p_farmid AND gb.isdeleted = FALSE
       AND (p_productid IS NULL OR gb.genericproductid = p_productid);
$fn$;

-- Take p_qty out of a product's batches in the order described at the top of this file.
-- p_stockbefore = the product's stock before this movement. Returns nothing; batches change.
CREATE OR REPLACE FUNCTION fngenericproductbatch_consume(
    p_farmid TEXT, p_productid INT, p_qty NUMERIC, p_stockbefore NUMERIC,
    p_purchaseid INT DEFAULT NULL, p_batchid INT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $fn$
DECLARE
    v_left      NUMERIC := p_qty;
    v_held      NUMERIC;
    v_unbatched NUMERIC;
    v_take      NUMERIC;
    v_b         RECORD;
BEGIN
    IF v_left IS NULL OR v_left <= 0 THEN RETURN; END IF;
    IF NOT EXISTS (SELECT 1 FROM genericproductbatches b
                   WHERE b.farmid = p_farmid AND b.genericproductid = p_productid
                     AND b.isdeleted = FALSE AND b.quantityremaining > 0) THEN
        RETURN;
    END IF;

    -- a) the named batch / the reversed purchase's batches
    FOR v_b IN
        SELECT b.genericproductbatchid, b.quantityremaining FROM genericproductbatches b
        WHERE b.farmid = p_farmid AND b.genericproductid = p_productid AND b.isdeleted = FALSE
          AND b.quantityremaining > 0
          AND ((p_batchid IS NOT NULL AND b.genericproductbatchid = p_batchid)
            OR (p_purchaseid IS NOT NULL AND b.genericpurchaseid = p_purchaseid AND b.sourcetype = 'Purchase'))
        ORDER BY b.genericproductbatchid
        FOR UPDATE
    LOOP
        EXIT WHEN v_left <= 0;
        v_take := LEAST(v_left, v_b.quantityremaining);
        UPDATE genericproductbatches SET quantityremaining = quantityremaining - v_take,
               updatedat = now() AT TIME ZONE 'utc'
        WHERE genericproductbatchid = v_b.genericproductbatchid;
        v_left := v_left - v_take;
    END LOOP;
    IF v_left <= 0 THEN RETURN; END IF;

    -- b) stock with no batch recorded
    IF p_batchid IS NULL AND p_purchaseid IS NULL THEN
        SELECT COALESCE(SUM(b.quantityremaining), 0) INTO v_held FROM genericproductbatches b
        WHERE b.farmid = p_farmid AND b.genericproductid = p_productid AND b.isdeleted = FALSE;
        v_unbatched := GREATEST(COALESCE(p_stockbefore, 0) - v_held, 0);
        v_take := LEAST(v_left, v_unbatched);
        v_left := v_left - v_take;
        IF v_left <= 0 THEN RETURN; END IF;
    END IF;

    -- c) not expired, earliest expiry first; d) expired
    FOR v_b IN
        SELECT b.genericproductbatchid, b.quantityremaining FROM genericproductbatches b
        WHERE b.farmid = p_farmid AND b.genericproductid = p_productid AND b.isdeleted = FALSE
          AND b.quantityremaining > 0
        ORDER BY CASE WHEN b.expirydate IS NOT NULL AND b.expirydate < CURRENT_DATE THEN 1 ELSE 0 END,
                 b.expirydate NULLS LAST, b.receiveddate, b.genericproductbatchid
        FOR UPDATE
    LOOP
        EXIT WHEN v_left <= 0;
        v_take := LEAST(v_left, v_b.quantityremaining);
        UPDATE genericproductbatches SET quantityremaining = quantityremaining - v_take,
               updatedat = now() AT TIME ZONE 'utc'
        WHERE genericproductbatchid = v_b.genericproductbatchid;
        v_left := v_left - v_take;
    END LOOP;
END
$fn$;

CREATE OR REPLACE FUNCTION fngenericstockmovement_batches_trg()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$
DECLARE
    v_stock    NUMERIC;
    v_earlier  NUMERIC;
    v_batchid  INT;
BEGIN
    IF NEW.quantity IS NULL OR NEW.quantity >= 0 OR NEW.genericproductid IS NULL THEN
        RETURN NEW;
    END IF;

    -- Every writer inserts its movement rows first and updates genericproducts.currentstock
    -- after, so currentstock is still the stock before this document. Earlier rows of the
    -- same document (same statement) have already been taken off the batches.
    SELECT COALESCE(p.currentstock, 0) INTO v_stock FROM genericproducts p
    WHERE p.genericproductid = NEW.genericproductid AND p.farmid = NEW.farmid;
    SELECT COALESCE(SUM(m.quantity), 0) INTO v_earlier FROM genericstockmovements m
    WHERE m.farmid = NEW.farmid AND m.genericproductid = NEW.genericproductid
      AND m.referencetype IS NOT DISTINCT FROM NEW.referencetype
      AND m.referenceid IS NOT DISTINCT FROM NEW.referenceid
      AND m.genericstockmovementid < NEW.genericstockmovementid
      AND m.movementtype = NEW.movementtype;

    IF NEW.referencetype = 'Adjustment' THEN
        SELECT w.genericproductbatchid INTO v_batchid FROM genericproductbatchwriteoffs w
        WHERE w.genericstockadjustmentid = NEW.referenceid AND w.farmid = NEW.farmid;
    END IF;

    PERFORM fngenericproductbatch_consume(
        NEW.farmid, NEW.genericproductid, -NEW.quantity, v_stock + v_earlier,
        CASE WHEN NEW.movementtype = 'PurchaseReversal' AND NEW.referencetype = 'Purchase' THEN NEW.referenceid END,
        v_batchid);
    RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS trg_genericstockmovement_batches ON genericstockmovements;
CREATE TRIGGER trg_genericstockmovement_batches
    AFTER INSERT ON genericstockmovements
    FOR EACH ROW EXECUTE FUNCTION fngenericstockmovement_batches_trg();

-- ===========================================================================
-- Medicines (product + medicine details + packs + batch summary)
-- ===========================================================================
CREATE OR REPLACE FUNCTION spgenericmedicine_list(p_farmid TEXT)
RETURNS JSONB LANGUAGE sql STABLE AS $fn$
    WITH r AS (SELECT * FROM fngenericproductbatch_rows(p_farmid, NULL)),
    bs AS (
        SELECT r.genericproductid,
               SUM(r.quantityremaining) AS inbatches,
               SUM(r.quantityremaining) FILTER (WHERE r.expirydate < CURRENT_DATE) AS expiredqty,
               MIN(r.expirydate) FILTER (WHERE r.quantityremaining > 0 AND r.expirydate >= CURRENT_DATE) AS nearestexpiry,
               COUNT(*) FILTER (WHERE r.quantityremaining > 0) AS batchcount
        FROM r GROUP BY r.genericproductid
    )
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.name), '[]'::jsonb)
    FROM (
        SELECT lower(p.productname) AS name, jsonb_build_object(
            'genericProductId',  p.genericproductid,
            'productName',       p.productname,
            'sku',               p.sku,
            'barcode',           p.barcode,
            'categoryName',      c.name,
            'baseUnit',          COALESCE(NULLIF(trim(p.unitofmeasure), ''), 'unit'),
            'sellingPrice',      COALESCE(p.sellingprice, 0),
            'costPrice',         COALESCE(p.costprice, 0),
            'currentStock',      COALESCE(p.currentstock, 0),
            'minimumStockAlert', COALESCE(p.minimumstockalert, 0),
            'trackInventory',    COALESCE(p.trackinventory, TRUE),
            'isActive',          COALESCE(p.isactive, TRUE),
            'isMedicine',        m.genericproductid IS NOT NULL,
            'genericName',       m.genericname,
            'strength',          m.strength,
            'dosageForm',        m.dosageform,
            'medicineClass',     COALESCE(m.medicineclass, 'C'),
            'fdaRegNo',          m.fdaregno,
            'manufacturer',      m.manufacturer,
            'storageNote',       m.storagenote,
            'isControlled',      COALESCE(m.iscontrolled, FALSE),
            'packs', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                           'genericProductPackId', k.genericproductpackid,
                           'packName', k.packname,
                           'unitsPerPack', k.unitsperpack,
                           'sellingPrice', k.sellingprice) ORDER BY k.unitsperpack)
                FROM genericproductpacks k
                WHERE k.farmid = p_farmid AND k.genericproductid = p.genericproductid AND k.isactive), '[]'::jsonb),
            'expiredQty',        COALESCE(bs.expiredqty, 0),
            'unbatchedQty',      GREATEST(COALESCE(p.currentstock, 0), 0) - COALESCE(bs.inbatches, 0),
            'nearestExpiry',     bs.nearestexpiry,
            'batchCount',        COALESCE(bs.batchcount, 0)
        ) AS j
        FROM genericproducts p
        LEFT JOIN genericproductcategories c ON c.genericproductcategoryid = p.genericproductcategoryid
        LEFT JOIN genericmedicines m ON m.genericproductid = p.genericproductid AND m.farmid = p_farmid
        LEFT JOIN bs ON bs.genericproductid = p.genericproductid
        WHERE p.farmid = p_farmid AND p.isdeleted = FALSE
          AND COALESCE(p."ItemType", 'Product') <> 'SupplyItem'
    ) x;
$fn$;

CREATE OR REPLACE FUNCTION spgenericmedicine_save(p_farmid TEXT, p_productid INT, p_data JSONB, p_by TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $fn$
DECLARE
    v_base  TEXT;
    v_class TEXT;
    v_pack  JSONB;
    v_name  TEXT;
    v_units NUMERIC;
    v_price NUMERIC;
    v_id    INT;
    v_keep  INT[] := '{}';
BEGIN
    SELECT COALESCE(NULLIF(trim(p.unitofmeasure), ''), 'unit') INTO v_base
    FROM genericproducts p
    WHERE p.genericproductid = p_productid AND p.farmid = p_farmid AND p.isdeleted = FALSE;
    IF v_base IS NULL THEN
        RAISE EXCEPTION 'Product % was not found.', p_productid;
    END IF;

    v_class := upper(COALESCE(NULLIF(trim(p_data->>'medicineClass'), ''), 'C'));
    IF v_class NOT IN ('A', 'B', 'C') THEN
        RAISE EXCEPTION 'Medicine class must be A, B or C.';
    END IF;

    INSERT INTO genericmedicines AS m (genericproductid, farmid, genericname, strength, dosageform, medicineclass,
                                      fdaregno, manufacturer, storagenote, iscontrolled, updatedby)
    VALUES (p_productid, p_farmid,
            NULLIF(trim(p_data->>'genericName'), ''), NULLIF(trim(p_data->>'strength'), ''),
            NULLIF(trim(p_data->>'dosageForm'), ''), v_class,
            NULLIF(trim(p_data->>'fdaRegNo'), ''), NULLIF(trim(p_data->>'manufacturer'), ''),
            NULLIF(trim(p_data->>'storageNote'), ''), COALESCE((p_data->>'isControlled')::boolean, FALSE), p_by)
    ON CONFLICT (genericproductid) DO UPDATE
        SET genericname = EXCLUDED.genericname, strength = EXCLUDED.strength, dosageform = EXCLUDED.dosageform,
            medicineclass = EXCLUDED.medicineclass, fdaregno = EXCLUDED.fdaregno, manufacturer = EXCLUDED.manufacturer,
            storagenote = EXCLUDED.storagenote, iscontrolled = EXCLUDED.iscontrolled,
            updatedby = EXCLUDED.updatedby, updatedat = now() AT TIME ZONE 'utc';

    -- A medicine always tracks expiry (363 flag, read by the Inventory page).
    UPDATE genericproducts p SET trackexpiry = TRUE
    WHERE p.genericproductid = p_productid AND p.farmid = p_farmid AND p.trackexpiry = FALSE;

    IF p_data ? 'packs' THEN
        FOR v_pack IN SELECT value FROM jsonb_array_elements(COALESCE(p_data->'packs', '[]'::jsonb)) LOOP
            v_name  := NULLIF(trim(v_pack->>'packName'), '');
            CONTINUE WHEN v_name IS NULL;
            v_units := NULLIF(v_pack->>'unitsPerPack', '')::numeric;
            v_price := COALESCE(NULLIF(v_pack->>'sellingPrice', '')::numeric, 0);
            IF lower(v_name) = lower(v_base) THEN
                RAISE EXCEPTION 'A pack cannot have the same name as the base unit (%).', v_base;
            END IF;
            IF v_units IS NULL OR v_units <= 0 THEN
                RAISE EXCEPTION 'Say how many % are in one %.', v_base, v_name;
            END IF;
            IF v_price < 0 THEN
                RAISE EXCEPTION 'The price of a % cannot be below zero.', v_name;
            END IF;

            INSERT INTO genericproductpacks AS k (farmid, genericproductid, packname, unitsperpack, sellingprice, isactive)
            VALUES (p_farmid, p_productid, v_name, v_units, v_price, TRUE)
            ON CONFLICT (farmid, genericproductid, packname) DO UPDATE
                SET unitsperpack = EXCLUDED.unitsperpack, sellingprice = EXCLUDED.sellingprice,
                    isactive = TRUE, updatedat = now() AT TIME ZONE 'utc'
            RETURNING k.genericproductpackid INTO v_id;
            v_keep := v_keep || v_id;

            -- The product's own unit conversion (364): Purchases and Sales offer the pack.
            INSERT INTO genericuomconversions AS u (farmid, genericproductid, fromunit, tounit, conversionfactor, isactive)
            VALUES (p_farmid, p_productid, v_name, v_base, v_units, TRUE)
            ON CONFLICT ON CONSTRAINT uq_genericuomconversions_product DO UPDATE
                SET conversionfactor = EXCLUDED.conversionfactor, isactive = TRUE, updatedat = NOW();
        END LOOP;

        UPDATE genericproductpacks k SET isactive = FALSE, updatedat = now() AT TIME ZONE 'utc'
        WHERE k.farmid = p_farmid AND k.genericproductid = p_productid AND k.isactive
          AND NOT (k.genericproductpackid = ANY (v_keep));
    END IF;
END
$fn$;

-- ===========================================================================
-- Batches
-- ===========================================================================
CREATE OR REPLACE FUNCTION spgenericproductbatch_list(p_farmid TEXT, p_productid INT DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE AS $fn$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'genericProductBatchId', r.genericproductbatchid,
        'genericProductId',      r.genericproductid,
        'productName',           p.productname,
        'genericName',           m.genericname,
        'medicineClass',         m.medicineclass,
        'baseUnit',              COALESCE(NULLIF(trim(p.unitofmeasure), ''), 'unit'),
        'batchNumber',           r.batchnumber,
        'expiryDate',            r.expirydate,
        'daysToExpiry',          CASE WHEN r.expirydate IS NULL THEN NULL ELSE r.expirydate - CURRENT_DATE END,
        'receivedDate',          r.receiveddate,
        'quantityReceived',      r.quantityreceived,
        'quantityRemaining',     r.quantityremaining,
        'unitCost',              COALESCE(r.unitcost, p.costprice),
        'sourceType',            r.sourcetype,
        'genericPurchaseId',     r.genericpurchaseid,
        'invoiceNumber',         pu.invoicenumber,
        'notes',                 r.notes
    ) ORDER BY r.expirydate NULLS LAST, p.productname, r.genericproductbatchid), '[]'::jsonb)
    FROM fngenericproductbatch_rows(p_farmid, p_productid) r
    JOIN genericproducts p ON p.genericproductid = r.genericproductid AND p.farmid = p_farmid
    LEFT JOIN genericmedicines m ON m.genericproductid = r.genericproductid
    LEFT JOIN genericpurchases pu ON pu.genericpurchaseid = r.genericpurchaseid AND pu.farmid = p_farmid;
$fn$;

-- A batch for stock that is already on the shelf (opening stock, stock bought before
-- batches were used). It does not change stock, so it may only label stock that has
-- no batch yet.
CREATE OR REPLACE FUNCTION spgenericproductbatch_add(
    p_farmid TEXT, p_productid INT, p_batchnumber TEXT, p_expirydate DATE, p_quantity NUMERIC,
    p_unitcost NUMERIC DEFAULT NULL, p_receiveddate DATE DEFAULT NULL, p_notes TEXT DEFAULT NULL, p_by TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $fn$
DECLARE
    v_stock NUMERIC;
    v_unit  TEXT;
    v_held  NUMERIC;
    v_id    INT;
BEGIN
    SELECT GREATEST(COALESCE(p.currentstock, 0), 0), COALESCE(NULLIF(trim(p.unitofmeasure), ''), 'unit')
    INTO v_stock, v_unit
    FROM genericproducts p
    WHERE p.genericproductid = p_productid AND p.farmid = p_farmid AND p.isdeleted = FALSE;
    IF v_stock IS NULL THEN RAISE EXCEPTION 'Product % was not found.', p_productid; END IF;
    IF p_quantity IS NULL OR p_quantity <= 0 THEN RAISE EXCEPTION 'Enter the quantity in this batch.'; END IF;
    IF NULLIF(trim(p_batchnumber), '') IS NULL AND p_expirydate IS NULL THEN
        RAISE EXCEPTION 'Enter a batch number or an expiry date.';
    END IF;

    SELECT COALESCE(SUM(r.quantityremaining), 0) INTO v_held FROM fngenericproductbatch_rows(p_farmid, p_productid) r;
    IF p_quantity > v_stock - v_held THEN
        RAISE EXCEPTION 'Only % % of this product have no batch yet. Stock that arrives on a purchase gets its batch on the purchase.',
            trim(to_char(v_stock - v_held, 'FM999999999990.###')), v_unit;
    END IF;

    INSERT INTO genericproductbatches (farmid, genericproductid, batchnumber, expirydate, quantityreceived,
                                       quantityremaining, unitcost, receiveddate, sourcetype, notes, createdby)
    VALUES (p_farmid, p_productid, NULLIF(trim(p_batchnumber), ''), p_expirydate, p_quantity, p_quantity, p_unitcost,
            COALESCE(p_receiveddate, CURRENT_DATE), 'Manual', NULLIF(trim(p_notes), ''), p_by)
    RETURNING genericproductbatchid INTO v_id;
    RETURN v_id;
END
$fn$;

-- Write off (expired, damaged) part of one batch: an approved stock adjustment
-- ("Decrease") through the normal adjustment functions, taken from this batch.
-- It shows on Loss & Damage like any other loss.
CREATE OR REPLACE FUNCTION spgenericproductbatch_writeoff(
    p_farmid TEXT, p_batchid INT, p_quantity NUMERIC, p_reason TEXT DEFAULT NULL, p_by TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $fn$
DECLARE
    v_b     RECORD;
    v_adjid INT;
    v_kind  TEXT;
    v_text  TEXT;
BEGIN
    SELECT b.*, p.productname, COALESCE(NULLIF(trim(p.unitofmeasure), ''), 'unit') AS baseunit
    INTO v_b
    FROM genericproductbatches b
    JOIN genericproducts p ON p.genericproductid = b.genericproductid AND p.farmid = b.farmid
    WHERE b.genericproductbatchid = p_batchid AND b.farmid = p_farmid AND b.isdeleted = FALSE
    FOR UPDATE OF b;
    IF v_b.genericproductbatchid IS NULL THEN RAISE EXCEPTION 'Batch % was not found.', p_batchid; END IF;
    IF p_quantity IS NULL OR p_quantity <= 0 THEN RAISE EXCEPTION 'Enter the quantity to write off.'; END IF;
    IF p_quantity > v_b.quantityremaining THEN
        RAISE EXCEPTION 'Only % % are left in this batch.',
            trim(to_char(v_b.quantityremaining, 'FM999999999990.###')), v_b.baseunit;
    END IF;

    v_kind := CASE WHEN v_b.expirydate IS NOT NULL AND v_b.expirydate < CURRENT_DATE THEN 'Expired' ELSE 'Damage' END;
    v_text := '[' || v_kind || '] Batch ' || COALESCE(v_b.batchnumber, '#' || v_b.genericproductbatchid::text)
              || CASE WHEN v_b.expirydate IS NOT NULL THEN ' (expiry ' || to_char(v_b.expirydate, 'YYYY-MM-DD') || ')' ELSE '' END
              || CASE WHEN NULLIF(trim(p_reason), '') IS NOT NULL THEN ': ' || trim(p_reason) ELSE '' END;

    v_adjid := spgenericstockadjustment_insert(
        p_farmid, v_b.genericproductid, 'Decrease', p_quantity, v_text,
        (now() AT TIME ZONE 'utc')::timestamp, NULL, p_by);

    INSERT INTO genericproductbatchwriteoffs (farmid, genericproductbatchid, genericstockadjustmentid, quantity, reason, createdby)
    VALUES (p_farmid, p_batchid, v_adjid, p_quantity, NULLIF(trim(p_reason), ''), p_by);

    PERFORM spgenericstockadjustment_submit(v_adjid, p_farmid);
    PERFORM spgenericstockadjustment_approve(v_adjid, p_farmid, p_by);
    RETURN v_adjid;
END
$fn$;

-- Correct a batch number or expiry date (any batch).
CREATE OR REPLACE FUNCTION spgenericproductbatch_update(
    p_farmid TEXT, p_batchid INT, p_batchnumber TEXT, p_expirydate DATE, p_notes TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    IF NULLIF(trim(p_batchnumber), '') IS NULL AND p_expirydate IS NULL THEN
        RAISE EXCEPTION 'Enter a batch number or an expiry date.';
    END IF;
    UPDATE genericproductbatches b
    SET batchnumber = NULLIF(trim(p_batchnumber), ''), expirydate = p_expirydate,
        notes = NULLIF(trim(p_notes), ''), updatedat = now() AT TIME ZONE 'utc'
    WHERE b.genericproductbatchid = p_batchid AND b.farmid = p_farmid AND b.isdeleted = FALSE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Batch % was not found.', p_batchid; END IF;
END
$fn$;

-- Remove a batch added by hand. A purchase's batch goes when the purchase is reversed.
CREATE OR REPLACE FUNCTION spgenericproductbatch_delete(p_farmid TEXT, p_batchid INT)
RETURNS VOID LANGUAGE plpgsql AS $fn$
DECLARE v_source TEXT;
BEGIN
    SELECT b.sourcetype INTO v_source FROM genericproductbatches b
    WHERE b.genericproductbatchid = p_batchid AND b.farmid = p_farmid AND b.isdeleted = FALSE;
    IF v_source IS NULL THEN RAISE EXCEPTION 'Batch % was not found.', p_batchid; END IF;
    IF v_source <> 'Manual' THEN
        RAISE EXCEPTION 'This batch came from a purchase. Reverse the purchase instead, or correct its batch number and expiry.';
    END IF;
    UPDATE genericproductbatches b SET isdeleted = TRUE, updatedat = now() AT TIME ZONE 'utc'
    WHERE b.genericproductbatchid = p_batchid AND b.farmid = p_farmid;
END
$fn$;

-- ===========================================================================
-- Batch details on purchase lines
-- ===========================================================================
-- p_lines is in the same order as the purchase's lines (as sent to insert/update):
-- [{ "genericProductId": 5, "batchNumber": "B123", "expiryDate": "2027-06-30" }, ...]
CREATE OR REPLACE FUNCTION spgenericpurchase_setbatches(p_farmid TEXT, p_purchaseid INT, p_lines JSONB)
RETURNS VOID LANGUAGE plpgsql AS $fn$
DECLARE v_status TEXT;
BEGIN
    SELECT pu.status INTO v_status FROM genericpurchases pu
    WHERE pu.genericpurchaseid = p_purchaseid AND pu.farmid = p_farmid AND pu.isdeleted = FALSE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Purchase % was not found.', p_purchaseid; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Batch details can only be changed while the purchase is a Draft.';
    END IF;

    WITH l AS (
        SELECT value AS v, ordinality AS n FROM jsonb_array_elements(COALESCE(p_lines, '[]'::jsonb)) WITH ORDINALITY
    ), i AS (
        SELECT gi.genericpurchaseitemid, gi.genericproductid,
               row_number() OVER (ORDER BY gi.genericpurchaseitemid) AS n
        FROM genericpurchaseitems gi
        WHERE gi.genericpurchaseid = p_purchaseid AND gi.farmid = p_farmid
    )
    UPDATE genericpurchaseitems gi
    SET batchnumber = NULLIF(trim(l.v->>'batchNumber'), ''),
        expirydate  = NULLIF(l.v->>'expiryDate', '')::date
    FROM i JOIN l ON l.n = i.n
    WHERE gi.genericpurchaseitemid = i.genericpurchaseitemid
      AND (l.v->>'genericProductId' IS NULL OR (l.v->>'genericProductId')::int = i.genericproductid);
END
$fn$;

CREATE OR REPLACE FUNCTION spgenericpurchase_getbatches(p_farmid TEXT, p_purchaseid INT)
RETURNS JSONB LANGUAGE sql STABLE AS $fn$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'genericPurchaseItemId', gi.genericpurchaseitemid,
        'genericProductId',      gi.genericproductid,
        'batchNumber',           gi.batchnumber,
        'expiryDate',            gi.expirydate) ORDER BY gi.genericpurchaseitemid), '[]'::jsonb)
    FROM genericpurchaseitems gi
    WHERE gi.genericpurchaseid = p_purchaseid AND gi.farmid = p_farmid;
$fn$;

-- Approving a purchase creates its batches; leaving Approved (reverse / cancel) removes them.
CREATE OR REPLACE FUNCTION fngenericpurchase_batches_trg()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$
BEGIN
    IF NEW.status = 'Approved' AND OLD.status IS DISTINCT FROM 'Approved' THEN
        INSERT INTO genericproductbatches (farmid, genericproductid, batchnumber, expirydate, quantityreceived,
                                           quantityremaining, unitcost, receiveddate, sourcetype, genericpurchaseid,
                                           genericpurchaseitemid, createdby)
        SELECT NEW.farmid, gi.genericproductid, gi.batchnumber, gi.expirydate,
               gi.quantity * COALESCE(NULLIF(gi.unitfactor, 0), 1),
               gi.quantity * COALESCE(NULLIF(gi.unitfactor, 0), 1),
               gi.unitcost / COALESCE(NULLIF(gi.unitfactor, 0), 1),
               COALESCE(NEW.purchasedate::date, CURRENT_DATE), 'Purchase', NEW.genericpurchaseid,
               gi.genericpurchaseitemid, NEW.approvedby
        FROM genericpurchaseitems gi
        JOIN genericproducts p ON p.genericproductid = gi.genericproductid AND p.farmid = NEW.farmid
        WHERE gi.genericpurchaseid = NEW.genericpurchaseid AND gi.farmid = NEW.farmid
          AND p.trackinventory = TRUE
          AND gi.quantity > 0
          AND (gi.batchnumber IS NOT NULL OR gi.expirydate IS NOT NULL)
          AND NOT EXISTS (SELECT 1 FROM genericproductbatches b
                          WHERE b.genericpurchaseitemid = gi.genericpurchaseitemid AND b.isdeleted = FALSE);
    ELSIF OLD.status = 'Approved' AND NEW.status IS DISTINCT FROM 'Approved' THEN
        UPDATE genericproductbatches b SET isdeleted = TRUE, updatedat = now() AT TIME ZONE 'utc'
        WHERE b.genericpurchaseid = NEW.genericpurchaseid AND b.farmid = NEW.farmid
          AND b.sourcetype = 'Purchase' AND b.isdeleted = FALSE;
    END IF;
    RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS trg_genericpurchase_batches ON genericpurchases;
CREATE TRIGGER trg_genericpurchase_batches
    AFTER UPDATE OF status ON genericpurchases
    FOR EACH ROW EXECUTE FUNCTION fngenericpurchase_batches_trg();

-- ===========================================================================
-- Prescriptions
-- ===========================================================================
CREATE OR REPLACE FUNCTION spgenericprescription_create(p_farmid TEXT, p_data JSONB, p_by TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $fn$
DECLARE
    v_id     INT;
    v_saleid INT := NULLIF(p_data->>'genericSaleId', '')::int;
BEGIN
    IF NULLIF(trim(p_data->>'patientName'), '') IS NULL THEN RAISE EXCEPTION 'Enter the patient''s name.'; END IF;
    IF NULLIF(trim(p_data->>'prescriberName'), '') IS NULL THEN RAISE EXCEPTION 'Enter the prescriber''s name.'; END IF;
    IF v_saleid IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM genericsales s WHERE s.genericsaleid = v_saleid AND s.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Sale % was not found.', v_saleid;
    END IF;

    INSERT INTO genericprescriptions (farmid, genericsaleid, prescriptiondate, patientname, patientphone,
                                      prescribername, prescriberfacility, prescriptionref, notes, createdby)
    VALUES (p_farmid, v_saleid, COALESCE(NULLIF(p_data->>'prescriptionDate', '')::date, CURRENT_DATE),
            trim(p_data->>'patientName'), NULLIF(trim(p_data->>'patientPhone'), ''),
            trim(p_data->>'prescriberName'), NULLIF(trim(p_data->>'prescriberFacility'), ''),
            NULLIF(trim(p_data->>'prescriptionRef'), ''), NULLIF(trim(p_data->>'notes'), ''), p_by)
    RETURNING genericprescriptionid INTO v_id;

    INSERT INTO genericprescriptionitems (genericprescriptionid, farmid, genericproductid, medicinename, quantity, unit, directions)
    SELECT v_id, p_farmid, NULLIF(it->>'genericProductId', '')::int,
           COALESCE(NULLIF(trim(it->>'medicineName'), ''), '(medicine)'),
           COALESCE(NULLIF(it->>'quantity', '')::numeric, 0),
           NULLIF(trim(it->>'unit'), ''), NULLIF(trim(it->>'directions'), '')
    FROM jsonb_array_elements(COALESCE(p_data->'items', '[]'::jsonb)) it;

    RETURN v_id;
END
$fn$;

CREATE OR REPLACE FUNCTION spgenericprescription_list(p_farmid TEXT, p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE AS $fn$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'genericPrescriptionId', rx.genericprescriptionid,
        'prescriptionDate',      rx.prescriptiondate,
        'patientName',           rx.patientname,
        'patientPhone',          rx.patientphone,
        'prescriberName',        rx.prescribername,
        'prescriberFacility',    rx.prescriberfacility,
        'prescriptionRef',       rx.prescriptionref,
        'notes',                 rx.notes,
        'genericSaleId',         rx.genericsaleid,
        'receiptNumber',         s.receiptnumber,
        'saleStatus',            s.status,
        'createdBy',             rx.createdby,
        'items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                    'genericProductId', it.genericproductid, 'medicineName', it.medicinename,
                    'quantity', it.quantity, 'unit', it.unit, 'directions', it.directions)
                    ORDER BY it.genericprescriptionitemid)
                 FROM genericprescriptionitems it WHERE it.genericprescriptionid = rx.genericprescriptionid), '[]'::jsonb)
    ) ORDER BY rx.prescriptiondate DESC, rx.genericprescriptionid DESC), '[]'::jsonb)
    FROM genericprescriptions rx
    LEFT JOIN genericsales s ON s.genericsaleid = rx.genericsaleid AND s.farmid = p_farmid
    WHERE rx.farmid = p_farmid AND rx.isdeleted = FALSE
      AND (p_from IS NULL OR rx.prescriptiondate >= p_from)
      AND (p_to   IS NULL OR rx.prescriptiondate <= p_to);
$fn$;

-- ===========================================================================
-- 7. Pharmacy report: one row per sellable product
-- ===========================================================================
CREATE OR REPLACE FUNCTION spgenericpharmacy_report(p_farmid TEXT, p_from DATE, p_to DATE, p_expirydays INT DEFAULT 90)
RETURNS JSONB LANGUAGE sql STABLE AS $fn$
    WITH sold AS (
        SELECT i.genericproductid,
               SUM(i.quantity * COALESCE(NULLIF(i.unitfactor, 0), 1)) AS qty,
               SUM(COALESCE(i.linetotal, 0)) AS revenue
        FROM genericsaleitems i
        JOIN genericsales s ON s.genericsaleid = i.genericsaleid AND s.farmid = p_farmid
        WHERE i.farmid = p_farmid AND i.genericproductid IS NOT NULL
          AND s.status = 'Approved' AND s.isdeleted = FALSE
          AND s.saledate::date BETWEEN p_from AND p_to
        GROUP BY i.genericproductid
    ), lastsold AS (
        SELECT i.genericproductid, MAX(s.saledate) AS lastsoldat
        FROM genericsaleitems i
        JOIN genericsales s ON s.genericsaleid = i.genericsaleid AND s.farmid = p_farmid
        WHERE i.farmid = p_farmid AND i.genericproductid IS NOT NULL
          AND s.status = 'Approved' AND s.isdeleted = FALSE
        GROUP BY i.genericproductid
    ), bt AS (
        SELECT r.genericproductid,
               SUM(r.quantityremaining) FILTER (WHERE r.expirydate < CURRENT_DATE) AS expiredqty,
               SUM(r.quantityremaining) FILTER (WHERE r.expirydate >= CURRENT_DATE
                                                  AND r.expirydate <= CURRENT_DATE + COALESCE(p_expirydays, 90)) AS expiringqty,
               MIN(r.expirydate) FILTER (WHERE r.quantityremaining > 0 AND r.expirydate >= CURRENT_DATE) AS nearestexpiry
        FROM fngenericproductbatch_rows(p_farmid, NULL) r
        GROUP BY r.genericproductid
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'genericProductId', p.genericproductid,
        'productName',      p.productname,
        'genericName',      m.genericname,
        'medicineClass',    COALESCE(m.medicineclass, 'C'),
        'isMedicine',       m.genericproductid IS NOT NULL,
        'isControlled',     COALESCE(m.iscontrolled, FALSE),
        'baseUnit',         COALESCE(NULLIF(trim(p.unitofmeasure), ''), 'unit'),
        'qtySold',          COALESCE(sold.qty, 0),
        'revenue',          COALESCE(sold.revenue, 0),
        'cost',             COALESCE(sold.qty, 0) * COALESCE(p.costprice, 0),
        'profit',           COALESCE(sold.revenue, 0) - COALESCE(sold.qty, 0) * COALESCE(p.costprice, 0),
        'lastSoldAt',       lastsold.lastsoldat,
        'currentStock',     COALESCE(p.currentstock, 0),
        'stockValue',       GREATEST(COALESCE(p.currentstock, 0), 0) * COALESCE(p.costprice, 0),
        'expiredQty',       COALESCE(bt.expiredqty, 0),
        'expiringQty',      COALESCE(bt.expiringqty, 0),
        'nearestExpiry',    bt.nearestexpiry
    ) ORDER BY p.productname), '[]'::jsonb)
    FROM genericproducts p
    LEFT JOIN genericmedicines m ON m.genericproductid = p.genericproductid AND m.farmid = p_farmid
    LEFT JOIN sold ON sold.genericproductid = p.genericproductid
    LEFT JOIN lastsold ON lastsold.genericproductid = p.genericproductid
    LEFT JOIN bt ON bt.genericproductid = p.genericproductid
    WHERE p.farmid = p_farmid AND p.isdeleted = FALSE
      AND COALESCE(p."ItemType", 'Product') <> 'SupplyItem';
$fn$;

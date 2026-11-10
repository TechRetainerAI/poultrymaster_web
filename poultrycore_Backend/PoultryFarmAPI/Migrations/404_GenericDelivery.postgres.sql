-- 404: Generic Delivery module — load products onto a vehicle/driver, then
-- reconcile the return (sold/returned/damaged/short).
-- Same pattern as PoultryDelivery but for Generic companies.

-- =========================================================================
-- Table
-- =========================================================================
CREATE TABLE IF NOT EXISTS "GenericDeliveries" (
    "GenericDeliveryId"   SERIAL PRIMARY KEY,
    "FarmId"              TEXT NOT NULL,
    "DeliveryDate"        TIMESTAMP NOT NULL DEFAULT NOW(),
    "DriverName"          TEXT,
    "VehicleName"         TEXT,
    "Route"               TEXT,
    "GenericProductId"    INT NOT NULL,
    "ProductName"         TEXT,
    "QuantityLoaded"      NUMERIC(18,4) NOT NULL DEFAULT 0,
    "Unit"                VARCHAR(30),
    "UnitPrice"           NUMERIC(18,4) NOT NULL DEFAULT 0,
    "QuantitySold"        NUMERIC(18,4) NOT NULL DEFAULT 0,
    "QuantityReturned"    NUMERIC(18,4) NOT NULL DEFAULT 0,
    "QuantityDamaged"     NUMERIC(18,4) NOT NULL DEFAULT 0,
    "QuantityShort"       NUMERIC(18,4) NOT NULL DEFAULT 0,
    "CashCollected"       NUMERIC(18,4) NOT NULL DEFAULT 0,
    "CreditSales"         NUMERIC(18,4) NOT NULL DEFAULT 0,
    "DeliveryExpenses"    NUMERIC(18,4) NOT NULL DEFAULT 0,
    "TotalSales"          NUMERIC(18,4) NOT NULL DEFAULT 0,
    "Status"              VARCHAR(20) NOT NULL DEFAULT 'Loaded',
    "Notes"               TEXT,
    "CreatedBy"           TEXT,
    "CreatedAt"           TIMESTAMP NOT NULL DEFAULT NOW(),
    "ReconciledBy"        TEXT,
    "ReconciledAt"        TIMESTAMP
);

CREATE INDEX IF NOT EXISTS "IX_GenericDeliveries_FarmId"
    ON "GenericDeliveries" ("FarmId");

-- =========================================================================
-- SP: List all deliveries for a farm
-- =========================================================================
CREATE OR REPLACE FUNCTION spgenericdelivery_getall(
    p_farmid TEXT,
    p_status TEXT DEFAULT NULL,
    p_fromdate DATE DEFAULT NULL,
    p_todate DATE DEFAULT NULL
)
RETURNS TABLE (
    "GenericDeliveryId"   INT,
    "FarmId"              TEXT,
    "DeliveryDate"        TIMESTAMP,
    "DriverName"          TEXT,
    "VehicleName"         TEXT,
    "Route"               TEXT,
    "GenericProductId"    INT,
    "ProductName"         TEXT,
    "QuantityLoaded"      NUMERIC,
    "Unit"                VARCHAR,
    "UnitPrice"           NUMERIC,
    "QuantitySold"        NUMERIC,
    "QuantityReturned"    NUMERIC,
    "QuantityDamaged"     NUMERIC,
    "QuantityShort"       NUMERIC,
    "CashCollected"       NUMERIC,
    "CreditSales"         NUMERIC,
    "DeliveryExpenses"    NUMERIC,
    "TotalSales"          NUMERIC,
    "Status"              VARCHAR,
    "Notes"               TEXT,
    "CreatedAt"           TIMESTAMP,
    "ReconciledAt"        TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT d."GenericDeliveryId", d."FarmId", d."DeliveryDate",
           d."DriverName", d."VehicleName", d."Route",
           d."GenericProductId",
           COALESCE(d."ProductName", p."Name") AS "ProductName",
           d."QuantityLoaded", d."Unit", d."UnitPrice",
           d."QuantitySold", d."QuantityReturned", d."QuantityDamaged", d."QuantityShort",
           d."CashCollected", d."CreditSales", d."DeliveryExpenses", d."TotalSales",
           d."Status", d."Notes", d."CreatedAt", d."ReconciledAt"
    FROM "GenericDeliveries" d
    LEFT JOIN "GenericProducts" p ON p."GenericProductId" = d."GenericProductId"
    WHERE d."FarmId" = p_farmid
      AND (p_status IS NULL OR d."Status" = p_status)
      AND (p_fromdate IS NULL OR d."DeliveryDate" >= p_fromdate)
      AND (p_todate IS NULL OR d."DeliveryDate" <= p_todate + INTERVAL '1 day')
    ORDER BY d."DeliveryDate" DESC, d."GenericDeliveryId" DESC;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- SP: Load — create a new delivery, reduce product stock
-- =========================================================================
CREATE OR REPLACE FUNCTION spgenericdelivery_load(
    p_farmid TEXT,
    p_deliverydate TIMESTAMP,
    p_drivername TEXT,
    p_vehiclename TEXT,
    p_route TEXT,
    p_genericproductid INT,
    p_quantityloaded NUMERIC,
    p_unit TEXT,
    p_unitprice NUMERIC,
    p_notes TEXT,
    p_createdby TEXT
)
RETURNS INT AS $$
DECLARE v_id INT; v_productname TEXT;
BEGIN
    SELECT "Name" INTO v_productname FROM "GenericProducts"
    WHERE "GenericProductId" = p_genericproductid AND "FarmId" = p_farmid;

    INSERT INTO "GenericDeliveries"
        ("FarmId","DeliveryDate","DriverName","VehicleName","Route",
         "GenericProductId","ProductName","QuantityLoaded","Unit","UnitPrice",
         "Status","Notes","CreatedBy","CreatedAt")
    VALUES (p_farmid, COALESCE(p_deliverydate, NOW()), p_drivername, p_vehiclename, p_route,
            p_genericproductid, v_productname, p_quantityloaded, p_unit, p_unitprice,
            'Loaded', p_notes, p_createdby, NOW())
    RETURNING "GenericDeliveryId" INTO v_id;

    -- Reduce product stock
    UPDATE "GenericProducts"
    SET "CurrentStock" = COALESCE("CurrentStock", 0) - p_quantityloaded,
        "UpdatedAt" = NOW()
    WHERE "GenericProductId" = p_genericproductid AND "FarmId" = p_farmid;

    -- Record stock movement
    INSERT INTO "GenericStockMovements"
        ("FarmId","GenericProductId","MovementDate","MovementType","Quantity",
         "UnitCost","TotalCostValue","ReferenceType","ReferenceId","Reason","CreatedBy","CreatedAt")
    VALUES (p_farmid, p_genericproductid, COALESCE(p_deliverydate, NOW()),
            'Delivery Load', -p_quantityloaded, p_unitprice, -(p_quantityloaded * p_unitprice),
            'GenericDelivery', v_id, 'Loaded for delivery', p_createdby, NOW());

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- SP: Reconcile — record what was sold/returned/damaged/short
-- =========================================================================
CREATE OR REPLACE FUNCTION spgenericdelivery_reconcile(
    p_genericdeliveryid INT,
    p_farmid TEXT,
    p_quantitysold NUMERIC,
    p_quantityreturned NUMERIC,
    p_quantitydamaged NUMERIC,
    p_quantityshort NUMERIC,
    p_cashcollected NUMERIC,
    p_creditsales NUMERIC,
    p_deliveryexpenses NUMERIC,
    p_reconciledby TEXT
)
RETURNS VOID AS $$
DECLARE v_rec RECORD;
BEGIN
    SELECT * INTO v_rec FROM "GenericDeliveries"
    WHERE "GenericDeliveryId" = p_genericdeliveryid AND "FarmId" = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
    IF v_rec."Status" <> 'Loaded' THEN RAISE EXCEPTION 'Only Loaded deliveries can be reconciled'; END IF;

    UPDATE "GenericDeliveries" SET
        "QuantitySold" = p_quantitysold,
        "QuantityReturned" = p_quantityreturned,
        "QuantityDamaged" = p_quantitydamaged,
        "QuantityShort" = p_quantityshort,
        "CashCollected" = p_cashcollected,
        "CreditSales" = p_creditsales,
        "DeliveryExpenses" = p_deliveryexpenses,
        "TotalSales" = p_quantitysold * v_rec."UnitPrice",
        "Status" = 'Reconciled',
        "ReconciledBy" = p_reconciledby,
        "ReconciledAt" = NOW()
    WHERE "GenericDeliveryId" = p_genericdeliveryid;

    -- Return unsold stock
    IF p_quantityreturned > 0 THEN
        UPDATE "GenericProducts"
        SET "CurrentStock" = COALESCE("CurrentStock", 0) + p_quantityreturned,
            "UpdatedAt" = NOW()
        WHERE "GenericProductId" = v_rec."GenericProductId" AND "FarmId" = p_farmid;

        INSERT INTO "GenericStockMovements"
            ("FarmId","GenericProductId","MovementDate","MovementType","Quantity",
             "ReferenceType","ReferenceId","Reason","CreatedBy","CreatedAt")
        VALUES (p_farmid, v_rec."GenericProductId", NOW(),
                'Delivery Return', p_quantityreturned,
                'GenericDelivery', p_genericdeliveryid, 'Returned from delivery', p_reconciledby, NOW());
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- SP: Cancel — restore stock, mark cancelled
-- =========================================================================
CREATE OR REPLACE FUNCTION spgenericdelivery_cancel(
    p_genericdeliveryid INT,
    p_farmid TEXT
)
RETURNS VOID AS $$
DECLARE v_rec RECORD;
BEGIN
    SELECT * INTO v_rec FROM "GenericDeliveries"
    WHERE "GenericDeliveryId" = p_genericdeliveryid AND "FarmId" = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
    IF v_rec."Status" <> 'Loaded' THEN RAISE EXCEPTION 'Only Loaded deliveries can be cancelled'; END IF;

    UPDATE "GenericDeliveries" SET "Status" = 'Cancelled' WHERE "GenericDeliveryId" = p_genericdeliveryid;

    -- Restore stock
    UPDATE "GenericProducts"
    SET "CurrentStock" = COALESCE("CurrentStock", 0) + v_rec."QuantityLoaded",
        "UpdatedAt" = NOW()
    WHERE "GenericProductId" = v_rec."GenericProductId" AND "FarmId" = p_farmid;

    INSERT INTO "GenericStockMovements"
        ("FarmId","GenericProductId","MovementDate","MovementType","Quantity",
         "ReferenceType","ReferenceId","Reason","CreatedAt")
    VALUES (p_farmid, v_rec."GenericProductId", NOW(),
            'Delivery Cancel', v_rec."QuantityLoaded",
            'GenericDelivery', p_genericdeliveryid, 'Delivery cancelled — stock restored', NOW());
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- SP: Reverse — undo a reconciled delivery
-- =========================================================================
CREATE OR REPLACE FUNCTION spgenericdelivery_reverse(
    p_genericdeliveryid INT,
    p_farmid TEXT
)
RETURNS VOID AS $$
DECLARE v_rec RECORD;
BEGIN
    SELECT * INTO v_rec FROM "GenericDeliveries"
    WHERE "GenericDeliveryId" = p_genericdeliveryid AND "FarmId" = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
    IF v_rec."Status" <> 'Reconciled' THEN RAISE EXCEPTION 'Only Reconciled deliveries can be reversed'; END IF;

    -- Undo the return stock
    IF v_rec."QuantityReturned" > 0 THEN
        UPDATE "GenericProducts"
        SET "CurrentStock" = COALESCE("CurrentStock", 0) - v_rec."QuantityReturned",
            "UpdatedAt" = NOW()
        WHERE "GenericProductId" = v_rec."GenericProductId" AND "FarmId" = p_farmid;
    END IF;

    UPDATE "GenericDeliveries" SET
        "QuantitySold" = 0, "QuantityReturned" = 0, "QuantityDamaged" = 0, "QuantityShort" = 0,
        "CashCollected" = 0, "CreditSales" = 0, "DeliveryExpenses" = 0, "TotalSales" = 0,
        "Status" = 'Loaded', "ReconciledBy" = NULL, "ReconciledAt" = NULL
    WHERE "GenericDeliveryId" = p_genericdeliveryid;
END;
$$ LANGUAGE plpgsql;

-- 409: Delivery tracking — add customer/destination, InTransit and Delivered
-- statuses so deliveries can be tracked from load to arrival to reconciliation.
-- Flow: Loaded → InTransit → Delivered → Reconciled (or Cancelled at any point before Reconciled)

ALTER TABLE genericdeliveries ADD COLUMN IF NOT EXISTS "CustomerName" TEXT;
ALTER TABLE genericdeliveries ADD COLUMN IF NOT EXISTS "Destination" TEXT;
ALTER TABLE genericdeliveries ADD COLUMN IF NOT EXISTS "DeliveredAt" TIMESTAMP;
ALTER TABLE genericdeliveries ADD COLUMN IF NOT EXISTS "DeliveredBy" TEXT;

-- SP: Mark as dispatched (InTransit)
CREATE OR REPLACE FUNCTION spgenericdelivery_dispatch(
    p_genericdeliveryid INT, p_farmid TEXT
) RETURNS VOID AS $$
DECLARE v_rec RECORD;
BEGIN
    SELECT * INTO v_rec FROM genericdeliveries
    WHERE "GenericDeliveryId" = p_genericdeliveryid AND "FarmId" = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
    IF v_rec."Status" <> 'Loaded' THEN RAISE EXCEPTION 'Only Loaded deliveries can be dispatched'; END IF;

    UPDATE genericdeliveries SET "Status" = 'InTransit'
    WHERE "GenericDeliveryId" = p_genericdeliveryid;
END;
$$ LANGUAGE plpgsql;

-- SP: Mark as delivered
CREATE OR REPLACE FUNCTION spgenericdelivery_markdelivered(
    p_genericdeliveryid INT, p_farmid TEXT, p_deliveredby TEXT
) RETURNS VOID AS $$
DECLARE v_rec RECORD;
BEGIN
    SELECT * INTO v_rec FROM genericdeliveries
    WHERE "GenericDeliveryId" = p_genericdeliveryid AND "FarmId" = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
    IF v_rec."Status" NOT IN ('Loaded', 'InTransit') THEN
        RAISE EXCEPTION 'Only Loaded or InTransit deliveries can be marked as delivered';
    END IF;

    UPDATE genericdeliveries SET "Status" = 'Delivered',
        "DeliveredAt" = NOW(), "DeliveredBy" = p_deliveredby
    WHERE "GenericDeliveryId" = p_genericdeliveryid;
END;
$$ LANGUAGE plpgsql;

-- Update reconcile SP to also accept Delivered and InTransit status
CREATE OR REPLACE FUNCTION spgenericdelivery_reconcile(
    p_genericdeliveryid INT, p_farmid TEXT,
    p_quantitysold NUMERIC, p_quantityreturned NUMERIC,
    p_quantitydamaged NUMERIC, p_quantityshort NUMERIC,
    p_cashcollected NUMERIC, p_creditsales NUMERIC,
    p_deliveryexpenses NUMERIC, p_reconciledby TEXT
) RETURNS VOID AS $$
DECLARE v_rec RECORD;
BEGIN
    SELECT * INTO v_rec FROM genericdeliveries
    WHERE "GenericDeliveryId" = p_genericdeliveryid AND "FarmId" = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
    IF v_rec."Status" NOT IN ('Loaded', 'InTransit', 'Delivered') THEN
        RAISE EXCEPTION 'Only Loaded, InTransit or Delivered deliveries can be reconciled';
    END IF;

    UPDATE genericdeliveries SET
        "QuantitySold" = p_quantitysold, "QuantityReturned" = p_quantityreturned,
        "QuantityDamaged" = p_quantitydamaged, "QuantityShort" = p_quantityshort,
        "CashCollected" = p_cashcollected, "CreditSales" = p_creditsales,
        "DeliveryExpenses" = p_deliveryexpenses,
        "TotalSales" = p_quantitysold * v_rec."UnitPrice",
        "Status" = 'Reconciled', "ReconciledBy" = p_reconciledby, "ReconciledAt" = NOW()
    WHERE "GenericDeliveryId" = p_genericdeliveryid;

    IF p_quantityreturned > 0 THEN
        UPDATE genericproducts
        SET currentstock = COALESCE(currentstock, 0) + p_quantityreturned, updatedat = NOW()
        WHERE genericproductid = v_rec."GenericProductId" AND farmid = p_farmid;

        INSERT INTO genericstockmovements
            (farmid, genericproductid, movementdate, movementtype, quantity,
             referencetype, referenceid, reason, createdby, createdat)
        VALUES (p_farmid, v_rec."GenericProductId", NOW(),
                'Delivery Return', p_quantityreturned,
                'GenericDelivery', p_genericdeliveryid, 'Returned from delivery', p_reconciledby, NOW());
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Update cancel to also work on InTransit and Delivered
CREATE OR REPLACE FUNCTION spgenericdelivery_cancel(
    p_genericdeliveryid INT, p_farmid TEXT
) RETURNS VOID AS $$
DECLARE v_rec RECORD;
BEGIN
    SELECT * INTO v_rec FROM genericdeliveries
    WHERE "GenericDeliveryId" = p_genericdeliveryid AND "FarmId" = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
    IF v_rec."Status" NOT IN ('Loaded', 'InTransit', 'Delivered') THEN
        RAISE EXCEPTION 'Only non-reconciled deliveries can be cancelled';
    END IF;

    UPDATE genericdeliveries SET "Status" = 'Cancelled' WHERE "GenericDeliveryId" = p_genericdeliveryid;

    UPDATE genericproducts
    SET currentstock = COALESCE(currentstock, 0) + v_rec."QuantityLoaded", updatedat = NOW()
    WHERE genericproductid = v_rec."GenericProductId" AND farmid = p_farmid;

    INSERT INTO genericstockmovements
        (farmid, genericproductid, movementdate, movementtype, quantity,
         referencetype, referenceid, reason, createdat)
    VALUES (p_farmid, v_rec."GenericProductId", NOW(),
            'Delivery Cancel', v_rec."QuantityLoaded",
            'GenericDelivery', p_genericdeliveryid, 'Delivery cancelled — stock restored', NOW());
END;
$$ LANGUAGE plpgsql;

-- Update getall to include the new columns
CREATE OR REPLACE FUNCTION spgenericdelivery_getall(
    p_farmid TEXT, p_status TEXT DEFAULT NULL,
    p_fromdate DATE DEFAULT NULL, p_todate DATE DEFAULT NULL
)
RETURNS TABLE (
    "GenericDeliveryId" INT, "FarmId" TEXT, "DeliveryDate" TIMESTAMP,
    "DriverName" TEXT, "VehicleName" TEXT, "Route" TEXT,
    "CustomerName" TEXT, "Destination" TEXT,
    "GenericProductId" INT, "ProductName" TEXT,
    "QuantityLoaded" NUMERIC, "Unit" VARCHAR, "UnitPrice" NUMERIC,
    "QuantitySold" NUMERIC, "QuantityReturned" NUMERIC,
    "QuantityDamaged" NUMERIC, "QuantityShort" NUMERIC,
    "CashCollected" NUMERIC, "CreditSales" NUMERIC,
    "DeliveryExpenses" NUMERIC, "TotalSales" NUMERIC,
    "Status" VARCHAR, "Notes" TEXT,
    "CreatedAt" TIMESTAMP, "ReconciledAt" TIMESTAMP,
    "DeliveredAt" TIMESTAMP, "DeliveredBy" TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT d."GenericDeliveryId", d."FarmId", d."DeliveryDate",
           d."DriverName", d."VehicleName", d."Route",
           d."CustomerName", d."Destination",
           d."GenericProductId",
           COALESCE(d."ProductName", p.productname) AS "ProductName",
           d."QuantityLoaded", d."Unit", d."UnitPrice",
           d."QuantitySold", d."QuantityReturned", d."QuantityDamaged", d."QuantityShort",
           d."CashCollected", d."CreditSales", d."DeliveryExpenses", d."TotalSales",
           d."Status", d."Notes", d."CreatedAt", d."ReconciledAt",
           d."DeliveredAt", d."DeliveredBy"
    FROM genericdeliveries d
    LEFT JOIN genericproducts p ON p.genericproductid = d."GenericProductId"
    WHERE d."FarmId" = p_farmid
      AND (p_status IS NULL OR d."Status" = p_status)
      AND (p_fromdate IS NULL OR d."DeliveryDate" >= p_fromdate)
      AND (p_todate IS NULL OR d."DeliveryDate" <= p_todate + INTERVAL '1 day')
    ORDER BY d."DeliveryDate" DESC, d."GenericDeliveryId" DESC;
END;
$$ LANGUAGE plpgsql;

-- Update load SP to accept customer and destination
CREATE OR REPLACE FUNCTION spgenericdelivery_load(
    p_farmid TEXT, p_deliverydate TIMESTAMP, p_drivername TEXT,
    p_vehiclename TEXT, p_route TEXT, p_genericproductid INT,
    p_quantityloaded NUMERIC, p_unit TEXT, p_unitprice NUMERIC,
    p_notes TEXT, p_createdby TEXT,
    p_customername TEXT DEFAULT NULL, p_destination TEXT DEFAULT NULL
) RETURNS INT AS $$
DECLARE v_id INT; v_productname TEXT;
BEGIN
    SELECT productname INTO v_productname FROM genericproducts
    WHERE genericproductid = p_genericproductid AND farmid = p_farmid;

    INSERT INTO genericdeliveries
        ("FarmId","DeliveryDate","DriverName","VehicleName","Route",
         "GenericProductId","ProductName","QuantityLoaded","Unit","UnitPrice",
         "CustomerName","Destination",
         "Status","Notes","CreatedBy","CreatedAt")
    VALUES (p_farmid, COALESCE(p_deliverydate, NOW()), p_drivername, p_vehiclename, p_route,
            p_genericproductid, v_productname, p_quantityloaded, p_unit, p_unitprice,
            p_customername, p_destination,
            'Loaded', p_notes, p_createdby, NOW())
    RETURNING "GenericDeliveryId" INTO v_id;

    UPDATE genericproducts
    SET currentstock = COALESCE(currentstock, 0) - p_quantityloaded, updatedat = NOW()
    WHERE genericproductid = p_genericproductid AND farmid = p_farmid;

    INSERT INTO genericstockmovements
        (farmid, genericproductid, movementdate, movementtype, quantity,
         unitcost, totalcostvalue, referencetype, referenceid, reason, createdby, createdat)
    VALUES (p_farmid, p_genericproductid, COALESCE(p_deliverydate, NOW()),
            'Delivery Load', -p_quantityloaded, p_unitprice, -(p_quantityloaded * p_unitprice),
            'GenericDelivery', v_id, 'Loaded for delivery', p_createdby, NOW());
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

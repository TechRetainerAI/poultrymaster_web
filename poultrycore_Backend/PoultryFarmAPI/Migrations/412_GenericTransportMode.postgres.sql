-- 412: Transport mode — track what vehicle/transport type is used for each delivery trip.
-- Added to both drivers (default mode) and deliveries (actual mode used per trip).

-- Add to drivers (their default transport)
ALTER TABLE genericdrivers ADD COLUMN IF NOT EXISTS transportmode VARCHAR(30) DEFAULT 'Car';

-- Add to deliveries (what was actually used for this trip)
ALTER TABLE genericdeliveries ADD COLUMN IF NOT EXISTS "TransportMode" VARCHAR(30) DEFAULT 'Car';

-- Update getall SP to include TransportMode
DROP FUNCTION IF EXISTS spgenericdelivery_getall(text,text,date,date);
CREATE OR REPLACE FUNCTION spgenericdelivery_getall(
    p_farmid TEXT, p_status TEXT DEFAULT NULL,
    p_fromdate DATE DEFAULT NULL, p_todate DATE DEFAULT NULL
)
RETURNS TABLE (
    "GenericDeliveryId" INT, "FarmId" TEXT, "DeliveryDate" TIMESTAMP,
    "DriverName" TEXT, "VehicleName" TEXT, "Route" TEXT,
    "CustomerName" TEXT, "Destination" TEXT, "TransportMode" VARCHAR,
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
           d."CustomerName", d."Destination", d."TransportMode",
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

-- Update load SP to accept transport mode
DROP FUNCTION IF EXISTS spgenericdelivery_load(text,timestamp,text,text,text,int,numeric,text,numeric,text,text,text,text);
CREATE OR REPLACE FUNCTION spgenericdelivery_load(
    p_farmid TEXT, p_deliverydate TIMESTAMP, p_drivername TEXT,
    p_vehiclename TEXT, p_route TEXT, p_genericproductid INT,
    p_quantityloaded NUMERIC, p_unit TEXT, p_unitprice NUMERIC,
    p_notes TEXT, p_createdby TEXT,
    p_customername TEXT DEFAULT NULL, p_destination TEXT DEFAULT NULL,
    p_transportmode TEXT DEFAULT 'Car'
) RETURNS INT AS $$
DECLARE v_id INT; v_productname TEXT;
BEGIN
    SELECT productname INTO v_productname FROM genericproducts
    WHERE genericproductid = p_genericproductid AND farmid = p_farmid;

    INSERT INTO genericdeliveries
        ("FarmId","DeliveryDate","DriverName","VehicleName","Route",
         "GenericProductId","ProductName","QuantityLoaded","Unit","UnitPrice",
         "CustomerName","Destination","TransportMode",
         "Status","Notes","CreatedBy","CreatedAt")
    VALUES (p_farmid, COALESCE(p_deliverydate, NOW()), p_drivername, p_vehiclename, p_route,
            p_genericproductid, v_productname, p_quantityloaded, p_unit, p_unitprice,
            p_customername, p_destination, COALESCE(p_transportmode, 'Car'),
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

-- Update driver list SP to include transport mode
DROP FUNCTION IF EXISTS spgenericdriver_list(text);
CREATE OR REPLACE FUNCTION spgenericdriver_list(p_farmid TEXT)
RETURNS TABLE (
    "GenericDriverId" INT, "FarmId" TEXT, "DriverName" TEXT, "PhoneNumber" TEXT,
    "LicenseNumber" TEXT, "VehicleName" TEXT, "VehicleRegistration" TEXT,
    "TransportMode" VARCHAR,
    "IsActive" BOOLEAN, "Notes" TEXT, "CreatedAt" TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY SELECT d.genericdriverid, d.farmid, d.drivername, d.phonenumber,
        d.licensenumber, d.vehiclename, d.vehicleregistration,
        d.transportmode,
        d.isactive, d.notes, d.createdat
    FROM genericdrivers d WHERE d.farmid = p_farmid ORDER BY d.drivername;
END; $$ LANGUAGE plpgsql;

-- Update driver create SP
DROP FUNCTION IF EXISTS spgenericdriver_create(text,text,text,text,text,text,text,text);
CREATE OR REPLACE FUNCTION spgenericdriver_create(
    p_farmid TEXT, p_drivername TEXT, p_phonenumber TEXT, p_licensenumber TEXT,
    p_vehiclename TEXT, p_vehicleregistration TEXT, p_transportmode TEXT,
    p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO genericdrivers (farmid, drivername, phonenumber, licensenumber,
        vehiclename, vehicleregistration, transportmode, notes, createdby, createdat)
    VALUES (p_farmid, p_drivername, p_phonenumber, p_licensenumber,
        p_vehiclename, p_vehicleregistration, COALESCE(p_transportmode, 'Car'), p_notes, p_createdby, NOW())
    RETURNING genericdriverid INTO v_id;
    RETURN v_id;
END; $$ LANGUAGE plpgsql;

-- Update driver update SP
DROP FUNCTION IF EXISTS spgenericdriver_update(int,text,text,text,text,text,text,boolean,text);
CREATE OR REPLACE FUNCTION spgenericdriver_update(
    p_id INT, p_farmid TEXT, p_drivername TEXT, p_phonenumber TEXT, p_licensenumber TEXT,
    p_vehiclename TEXT, p_vehicleregistration TEXT, p_transportmode TEXT,
    p_isactive BOOLEAN, p_notes TEXT
) RETURNS VOID AS $$
BEGIN
    UPDATE genericdrivers SET drivername = p_drivername, phonenumber = p_phonenumber,
        licensenumber = p_licensenumber, vehiclename = p_vehiclename,
        vehicleregistration = p_vehicleregistration, transportmode = COALESCE(p_transportmode, 'Car'),
        isactive = p_isactive, notes = p_notes, updatedat = NOW()
    WHERE genericdriverid = p_id AND farmid = p_farmid;
END; $$ LANGUAGE plpgsql;

-- Update driver report to include transport mode breakdown
DROP FUNCTION IF EXISTS spgenericdelivery_driver_report(text,date,date,text);
CREATE OR REPLACE FUNCTION spgenericdelivery_driver_report(
    p_farmid TEXT, p_fromdate DATE DEFAULT NULL,
    p_todate DATE DEFAULT NULL, p_drivername TEXT DEFAULT NULL
)
RETURNS TABLE (
    "DriverName" TEXT, "TransportMode" VARCHAR,
    "TotalDeliveries" BIGINT, "TotalLoaded" NUMERIC,
    "TotalSold" NUMERIC, "TotalReturned" NUMERIC,
    "TotalDamaged" NUMERIC, "TotalShort" NUMERIC,
    "TotalSales" NUMERIC, "TotalCashCollected" NUMERIC,
    "TotalCreditSales" NUMERIC, "TotalExpenses" NUMERIC,
    "DeliveryRate" NUMERIC,
    "LoadedDeliveries" BIGINT, "InTransitDeliveries" BIGINT,
    "DeliveredDeliveries" BIGINT, "ReconciledDeliveries" BIGINT,
    "CancelledDeliveries" BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(d."DriverName", 'Unassigned') AS "DriverName",
        COALESCE(d."TransportMode", 'Car') AS "TransportMode",
        COUNT(*)::BIGINT AS "TotalDeliveries",
        COALESCE(SUM(d."QuantityLoaded"), 0), COALESCE(SUM(d."QuantitySold"), 0),
        COALESCE(SUM(d."QuantityReturned"), 0), COALESCE(SUM(d."QuantityDamaged"), 0),
        COALESCE(SUM(d."QuantityShort"), 0), COALESCE(SUM(d."TotalSales"), 0),
        COALESCE(SUM(d."CashCollected"), 0), COALESCE(SUM(d."CreditSales"), 0),
        COALESCE(SUM(d."DeliveryExpenses"), 0),
        CASE WHEN SUM(d."QuantityLoaded") > 0
            THEN ROUND(SUM(d."QuantitySold") / SUM(d."QuantityLoaded") * 100, 1) ELSE 0 END,
        COUNT(*) FILTER (WHERE d."Status" = 'Loaded')::BIGINT,
        COUNT(*) FILTER (WHERE d."Status" = 'InTransit')::BIGINT,
        COUNT(*) FILTER (WHERE d."Status" = 'Delivered')::BIGINT,
        COUNT(*) FILTER (WHERE d."Status" = 'Reconciled')::BIGINT,
        COUNT(*) FILTER (WHERE d."Status" = 'Cancelled')::BIGINT
    FROM genericdeliveries d
    WHERE d."FarmId" = p_farmid
      AND (p_fromdate IS NULL OR d."DeliveryDate" >= p_fromdate)
      AND (p_todate IS NULL OR d."DeliveryDate" <= p_todate + INTERVAL '1 day')
      AND (p_drivername IS NULL OR d."DriverName" = p_drivername)
    GROUP BY COALESCE(d."DriverName", 'Unassigned'), COALESCE(d."TransportMode", 'Car')
    ORDER BY "TotalSales" DESC;
END;
$$ LANGUAGE plpgsql;

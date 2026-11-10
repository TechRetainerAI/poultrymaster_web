-- 411: Generic Drivers and Routes — CRUD tables for managing delivery drivers and routes.

CREATE TABLE IF NOT EXISTS genericdrivers (
    genericdriverid     SERIAL PRIMARY KEY,
    farmid              TEXT NOT NULL,
    drivername          TEXT NOT NULL,
    phonenumber         TEXT,
    licensenumber       TEXT,
    vehiclename         TEXT,
    vehicleregistration TEXT,
    isactive            BOOLEAN NOT NULL DEFAULT TRUE,
    notes               TEXT,
    createdby           TEXT,
    createdat           TIMESTAMP NOT NULL DEFAULT NOW(),
    updatedat           TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_genericdrivers_farmid ON genericdrivers (farmid);

CREATE TABLE IF NOT EXISTS genericroutes (
    genericrouteid      SERIAL PRIMARY KEY,
    farmid              TEXT NOT NULL,
    routename           TEXT NOT NULL,
    description         TEXT,
    startpoint          TEXT,
    endpoint            TEXT,
    estimatedtime       TEXT,
    isactive            BOOLEAN NOT NULL DEFAULT TRUE,
    notes               TEXT,
    createdby           TEXT,
    createdat           TIMESTAMP NOT NULL DEFAULT NOW(),
    updatedat           TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_genericroutes_farmid ON genericroutes (farmid);

-- Driver CRUD
CREATE OR REPLACE FUNCTION spgenericdriver_list(p_farmid TEXT)
RETURNS TABLE (
    "GenericDriverId" INT, "FarmId" TEXT, "DriverName" TEXT, "PhoneNumber" TEXT,
    "LicenseNumber" TEXT, "VehicleName" TEXT, "VehicleRegistration" TEXT,
    "IsActive" BOOLEAN, "Notes" TEXT, "CreatedAt" TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY SELECT d.genericdriverid, d.farmid, d.drivername, d.phonenumber,
        d.licensenumber, d.vehiclename, d.vehicleregistration,
        d.isactive, d.notes, d.createdat
    FROM genericdrivers d WHERE d.farmid = p_farmid ORDER BY d.drivername;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericdriver_create(
    p_farmid TEXT, p_drivername TEXT, p_phonenumber TEXT, p_licensenumber TEXT,
    p_vehiclename TEXT, p_vehicleregistration TEXT, p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO genericdrivers (farmid, drivername, phonenumber, licensenumber,
        vehiclename, vehicleregistration, notes, createdby, createdat)
    VALUES (p_farmid, p_drivername, p_phonenumber, p_licensenumber,
        p_vehiclename, p_vehicleregistration, p_notes, p_createdby, NOW())
    RETURNING genericdriverid INTO v_id;
    RETURN v_id;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericdriver_update(
    p_id INT, p_farmid TEXT, p_drivername TEXT, p_phonenumber TEXT, p_licensenumber TEXT,
    p_vehiclename TEXT, p_vehicleregistration TEXT, p_isactive BOOLEAN, p_notes TEXT
) RETURNS VOID AS $$
BEGIN
    UPDATE genericdrivers SET drivername = p_drivername, phonenumber = p_phonenumber,
        licensenumber = p_licensenumber, vehiclename = p_vehiclename,
        vehicleregistration = p_vehicleregistration, isactive = p_isactive,
        notes = p_notes, updatedat = NOW()
    WHERE genericdriverid = p_id AND farmid = p_farmid;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericdriver_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM genericdrivers WHERE genericdriverid = p_id AND farmid = p_farmid;
END; $$ LANGUAGE plpgsql;

-- Route CRUD
CREATE OR REPLACE FUNCTION spgenericroute_list(p_farmid TEXT)
RETURNS TABLE (
    "GenericRouteId" INT, "FarmId" TEXT, "RouteName" TEXT, "Description" TEXT,
    "StartPoint" TEXT, "EndPoint" TEXT, "EstimatedTime" TEXT,
    "IsActive" BOOLEAN, "Notes" TEXT, "CreatedAt" TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY SELECT r.genericrouteid, r.farmid, r.routename, r.description,
        r.startpoint, r.endpoint, r.estimatedtime,
        r.isactive, r.notes, r.createdat
    FROM genericroutes r WHERE r.farmid = p_farmid ORDER BY r.routename;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericroute_create(
    p_farmid TEXT, p_routename TEXT, p_description TEXT,
    p_startpoint TEXT, p_endpoint TEXT, p_estimatedtime TEXT,
    p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO genericroutes (farmid, routename, description, startpoint, endpoint,
        estimatedtime, notes, createdby, createdat)
    VALUES (p_farmid, p_routename, p_description, p_startpoint, p_endpoint,
        p_estimatedtime, p_notes, p_createdby, NOW())
    RETURNING genericrouteid INTO v_id;
    RETURN v_id;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericroute_update(
    p_id INT, p_farmid TEXT, p_routename TEXT, p_description TEXT,
    p_startpoint TEXT, p_endpoint TEXT, p_estimatedtime TEXT,
    p_isactive BOOLEAN, p_notes TEXT
) RETURNS VOID AS $$
BEGIN
    UPDATE genericroutes SET routename = p_routename, description = p_description,
        startpoint = p_startpoint, endpoint = p_endpoint, estimatedtime = p_estimatedtime,
        isactive = p_isactive, notes = p_notes, updatedat = NOW()
    WHERE genericrouteid = p_id AND farmid = p_farmid;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericroute_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM genericroutes WHERE genericrouteid = p_id AND farmid = p_farmid;
END; $$ LANGUAGE plpgsql;

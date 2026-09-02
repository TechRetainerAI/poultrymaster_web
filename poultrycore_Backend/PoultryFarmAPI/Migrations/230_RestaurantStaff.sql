-- =============================================================================
-- Migration 230: Restaurant Staff table and stored procedures
-- =============================================================================
-- Own table for restaurant staff, separate from GenericStaff.
-- Idempotent. Run after 229.
-- =============================================================================

-- Table
CREATE TABLE IF NOT EXISTS RestaurantStaff (
    RestaurantStaffId  SERIAL PRIMARY KEY,
    FarmId             VARCHAR(450) NOT NULL,
    FirstName          VARCHAR(100) NOT NULL,
    LastName           VARCHAR(100) NOT NULL DEFAULT '',
    Phone              VARCHAR(50),
    Email              VARCHAR(200),
    Role               VARCHAR(40)  NOT NULL DEFAULT 'Other',
    SalaryType         VARCHAR(20)  NOT NULL DEFAULT 'Monthly',
    BasePay            NUMERIC(14,2) NOT NULL DEFAULT 0,
    IsActive           BOOLEAN NOT NULL DEFAULT TRUE,
    Notes              TEXT,
    CreatedAt          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UpdatedAt          TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_restaurantstaff_farmid ON RestaurantStaff (FarmId);

-- GetAll
CREATE OR REPLACE FUNCTION sprestaurant_staff_getall(
    p_farmid TEXT,
    p_role   TEXT DEFAULT NULL
) RETURNS TABLE (
    restaurantstaffid INT, farmid TEXT, firstname TEXT, lastname TEXT,
    phone TEXT, email TEXT, role TEXT, salarytype TEXT, basepay NUMERIC,
    isactive BOOLEAN, notes TEXT, createdat TIMESTAMPTZ, updatedat TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT s.restaurantstaffid, s.farmid::TEXT, s.firstname::TEXT, s.lastname::TEXT,
           s.phone::TEXT, s.email::TEXT, s.role::TEXT, s.salarytype::TEXT, s.basepay,
           s.isactive, s.notes::TEXT, s.createdat, s.updatedat
    FROM   RestaurantStaff s
    WHERE  s.farmid = p_farmid
      AND  (p_role IS NULL OR s.role = p_role)
    ORDER BY s.isactive DESC, s.lastname, s.firstname;
END;
$$ LANGUAGE plpgsql;

-- GetById
CREATE OR REPLACE FUNCTION sprestaurant_staff_getbyid(
    p_id     INT,
    p_farmid TEXT
) RETURNS TABLE (
    restaurantstaffid INT, farmid TEXT, firstname TEXT, lastname TEXT,
    phone TEXT, email TEXT, role TEXT, salarytype TEXT, basepay NUMERIC,
    isactive BOOLEAN, notes TEXT, createdat TIMESTAMPTZ, updatedat TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT s.restaurantstaffid, s.farmid::TEXT, s.firstname::TEXT, s.lastname::TEXT,
           s.phone::TEXT, s.email::TEXT, s.role::TEXT, s.salarytype::TEXT, s.basepay,
           s.isactive, s.notes::TEXT, s.createdat, s.updatedat
    FROM   RestaurantStaff s
    WHERE  s.restaurantstaffid = p_id AND s.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Insert
CREATE OR REPLACE FUNCTION sprestaurant_staff_insert(
    p_farmid     TEXT,
    p_firstname  TEXT,
    p_lastname   TEXT DEFAULT '',
    p_phone      TEXT DEFAULT NULL,
    p_email      TEXT DEFAULT NULL,
    p_role       TEXT DEFAULT 'Other',
    p_salarytype TEXT DEFAULT 'Monthly',
    p_basepay    NUMERIC DEFAULT 0,
    p_isactive   BOOLEAN DEFAULT TRUE,
    p_notes      TEXT DEFAULT NULL
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO RestaurantStaff (FarmId, FirstName, LastName, Phone, Email, Role, SalaryType, BasePay, IsActive, Notes)
    VALUES (p_farmid, p_firstname, p_lastname, p_phone, p_email, p_role, p_salarytype, p_basepay, p_isactive, p_notes)
    RETURNING RestaurantStaffId INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Update
CREATE OR REPLACE FUNCTION sprestaurant_staff_update(
    p_id         INT,
    p_farmid     TEXT,
    p_firstname  TEXT,
    p_lastname   TEXT,
    p_phone      TEXT DEFAULT NULL,
    p_email      TEXT DEFAULT NULL,
    p_role       TEXT DEFAULT 'Other',
    p_salarytype TEXT DEFAULT 'Monthly',
    p_basepay    NUMERIC DEFAULT 0,
    p_isactive   BOOLEAN DEFAULT TRUE,
    p_notes      TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    UPDATE RestaurantStaff
    SET    FirstName  = p_firstname,
           LastName   = p_lastname,
           Phone      = p_phone,
           Email      = p_email,
           Role       = p_role,
           SalaryType = p_salarytype,
           BasePay    = p_basepay,
           IsActive   = p_isactive,
           Notes      = p_notes,
           UpdatedAt  = NOW()
    WHERE  RestaurantStaffId = p_id AND FarmId = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Delete
CREATE OR REPLACE FUNCTION sprestaurant_staff_delete(
    p_id     INT,
    p_farmid TEXT
) RETURNS VOID AS $$
BEGIN
    DELETE FROM RestaurantStaff WHERE RestaurantStaffId = p_id AND FarmId = p_farmid;
END;
$$ LANGUAGE plpgsql;

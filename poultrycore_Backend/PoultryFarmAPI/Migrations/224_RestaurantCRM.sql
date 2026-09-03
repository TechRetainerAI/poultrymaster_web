-- Migration 224: Restaurant CRM — Customers, preferences, feedback, segmentation
-- Applied: 2026-08-30

CREATE TABLE IF NOT EXISTS restaurantcustomers (
    customerid           SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    name                 TEXT NOT NULL,
    phone                TEXT,
    email                TEXT,
    dateofbirth          DATE,
    anniversary          DATE,
    dietarypreferences   TEXT,          -- Vegetarian, Vegan, Gluten-Free, etc.
    allergies            TEXT,
    favouriteitems       TEXT,
    segment              TEXT DEFAULT 'New', -- New, Regular, VIP, Lapsed
    totalvisits          INT DEFAULT 0,
    totalspent           NUMERIC(12,2) DEFAULT 0,
    avgticket            NUMERIC(12,2) DEFAULT 0,
    lastvisit            TIMESTAMP,
    notes                TEXT,
    isactive             BOOLEAN DEFAULT TRUE,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantcustomers_farm ON restaurantcustomers(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantcustomers_phone ON restaurantcustomers(farmid, phone);
CREATE INDEX IF NOT EXISTS ix_restaurantcustomers_segment ON restaurantcustomers(farmid, segment);

CREATE TABLE IF NOT EXISTS restaurantcustomerfeedback (
    feedbackid           SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    customerid           INT REFERENCES restaurantcustomers(customerid) ON DELETE SET NULL,
    customername         TEXT,
    orderid              INT REFERENCES restaurantorders(orderid) ON DELETE SET NULL,
    rating               INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    foodrating           INT CHECK (foodrating BETWEEN 1 AND 5),
    servicerating        INT CHECK (servicerating BETWEEN 1 AND 5),
    ambiencerating       INT CHECK (ambiencerating BETWEEN 1 AND 5),
    comment              TEXT,
    source               TEXT DEFAULT 'InStore', -- InStore, Online, SMS, Email, QR
    status               TEXT DEFAULT 'New',     -- New, Read, Responded, Resolved
    response             TEXT,
    respondedby          TEXT,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantfeedback_farm ON restaurantcustomerfeedback(farmid);

CREATE TABLE IF NOT EXISTS restaurantcampaigns (
    campaignid           SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    name                 TEXT NOT NULL,
    campaigntype         TEXT NOT NULL,   -- Birthday, WinBack, Promotion, Announcement
    targetsegment        TEXT,            -- All, New, Regular, VIP, Lapsed
    subject              TEXT,
    message              TEXT,
    channel              TEXT DEFAULT 'SMS', -- SMS, Email, Push
    status               TEXT DEFAULT 'Draft', -- Draft, Scheduled, Sent, Cancelled
    scheduledat          TIMESTAMP,
    sentat               TIMESTAMP,
    recipientcount       INT DEFAULT 0,
    opencount            INT DEFAULT 0,
    createdat            TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantcampaigns_farm ON restaurantcampaigns(farmid);

-- SP: Customer CRUD
CREATE OR REPLACE FUNCTION sprestaurant_customer_list(p_farmid TEXT, p_segment TEXT DEFAULT NULL, p_search TEXT DEFAULT NULL)
RETURNS TABLE (
    customerid INT, farmid TEXT, name TEXT, phone TEXT, email TEXT,
    dateofbirth DATE, anniversary DATE, dietarypreferences TEXT, allergies TEXT,
    favouriteitems TEXT, segment TEXT, totalvisits INT, totalspent NUMERIC,
    avgticket NUMERIC, lastvisit TIMESTAMP, notes TEXT, isactive BOOLEAN,
    createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY SELECT c.* FROM restaurantcustomers c
    WHERE c.farmid = p_farmid
      AND (p_segment IS NULL OR c.segment = p_segment)
      AND (p_search IS NULL OR c.name ILIKE '%' || p_search || '%' OR c.phone ILIKE '%' || p_search || '%' OR c.email ILIKE '%' || p_search || '%')
    ORDER BY c.totalspent DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_customer_insert(
    p_farmid TEXT, p_name TEXT, p_phone TEXT, p_email TEXT, p_dateofbirth DATE,
    p_anniversary DATE, p_dietarypreferences TEXT, p_allergies TEXT,
    p_favouriteitems TEXT, p_segment TEXT, p_notes TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantcustomers (farmid, name, phone, email, dateofbirth, anniversary,
        dietarypreferences, allergies, favouriteitems, segment, notes)
    VALUES (p_farmid, p_name, p_phone, p_email, p_dateofbirth, p_anniversary,
        p_dietarypreferences, p_allergies, p_favouriteitems, COALESCE(p_segment, 'New'), p_notes)
    RETURNING customerid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_customer_update(
    p_id INT, p_farmid TEXT, p_name TEXT, p_phone TEXT, p_email TEXT, p_dateofbirth DATE,
    p_anniversary DATE, p_dietarypreferences TEXT, p_allergies TEXT,
    p_favouriteitems TEXT, p_segment TEXT, p_notes TEXT, p_isactive BOOLEAN
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantcustomers SET name=p_name, phone=p_phone, email=p_email, dateofbirth=p_dateofbirth,
        anniversary=p_anniversary, dietarypreferences=p_dietarypreferences, allergies=p_allergies,
        favouriteitems=p_favouriteitems, segment=p_segment, notes=p_notes, isactive=p_isactive, updatedat=NOW()
    WHERE customerid=p_id AND farmid=p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_customer_delete(p_id INT, p_farmid TEXT) RETURNS VOID AS $$
BEGIN DELETE FROM restaurantcustomers WHERE customerid=p_id AND farmid=p_farmid; END;
$$ LANGUAGE plpgsql;

-- Record a visit (called when order completes for a known customer)
CREATE OR REPLACE FUNCTION sprestaurant_customer_record_visit(p_id INT, p_farmid TEXT, p_orderamount NUMERIC) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantcustomers SET totalvisits=totalvisits+1, totalspent=totalspent+p_orderamount,
        avgticket=CASE WHEN totalvisits>0 THEN ROUND((totalspent+p_orderamount)/(totalvisits+1),2) ELSE p_orderamount END,
        lastvisit=NOW(), updatedat=NOW(),
        segment=CASE
            WHEN totalvisits+1>=20 THEN 'VIP'
            WHEN totalvisits+1>=5 THEN 'Regular'
            ELSE 'New' END
    WHERE customerid=p_id AND farmid=p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Customer stats
CREATE OR REPLACE FUNCTION sprestaurant_customer_stats(p_farmid TEXT)
RETURNS TABLE (total_customers BIGINT, new_count BIGINT, regular_count BIGINT, vip_count BIGINT, lapsed_count BIGINT, total_lifetime_value NUMERIC) AS $$
BEGIN
    RETURN QUERY SELECT COUNT(*),
        COUNT(*) FILTER (WHERE c.segment='New'), COUNT(*) FILTER (WHERE c.segment='Regular'),
        COUNT(*) FILTER (WHERE c.segment='VIP'), COUNT(*) FILTER (WHERE c.segment='Lapsed'),
        COALESCE(SUM(c.totalspent),0)
    FROM restaurantcustomers c WHERE c.farmid=p_farmid AND c.isactive=TRUE;
END;
$$ LANGUAGE plpgsql;

-- Feedback CRUD
CREATE OR REPLACE FUNCTION sprestaurant_feedback_list(p_farmid TEXT, p_status TEXT DEFAULT NULL)
RETURNS TABLE (
    feedbackid INT, farmid TEXT, customerid INT, customername TEXT, orderid INT,
    rating INT, foodrating INT, servicerating INT, ambiencerating INT,
    comment TEXT, source TEXT, status TEXT, response TEXT, respondedby TEXT,
    createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY SELECT f.* FROM restaurantcustomerfeedback f
    WHERE f.farmid=p_farmid AND (p_status IS NULL OR f.status=p_status)
    ORDER BY f.createdat DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_feedback_insert(
    p_farmid TEXT, p_customerid INT, p_customername TEXT, p_orderid INT,
    p_rating INT, p_foodrating INT, p_servicerating INT, p_ambiencerating INT,
    p_comment TEXT, p_source TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantcustomerfeedback (farmid, customerid, customername, orderid,
        rating, foodrating, servicerating, ambiencerating, comment, source)
    VALUES (p_farmid, p_customerid, p_customername, p_orderid,
        p_rating, p_foodrating, p_servicerating, p_ambiencerating, p_comment, p_source)
    RETURNING feedbackid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_feedback_respond(p_id INT, p_farmid TEXT, p_response TEXT, p_respondedby TEXT) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantcustomerfeedback SET status='Responded', response=p_response, respondedby=p_respondedby, updatedat=NOW()
    WHERE feedbackid=p_id AND farmid=p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Feedback stats
CREATE OR REPLACE FUNCTION sprestaurant_feedback_stats(p_farmid TEXT)
RETURNS TABLE (total_feedback BIGINT, avg_rating DOUBLE PRECISION, avg_food DOUBLE PRECISION, avg_service DOUBLE PRECISION, avg_ambience DOUBLE PRECISION, new_count BIGINT) AS $$
BEGIN
    RETURN QUERY SELECT COUNT(*), AVG(f.rating)::DOUBLE PRECISION, AVG(f.foodrating)::DOUBLE PRECISION,
        AVG(f.servicerating)::DOUBLE PRECISION, AVG(f.ambiencerating)::DOUBLE PRECISION,
        COUNT(*) FILTER (WHERE f.status='New')
    FROM restaurantcustomerfeedback f WHERE f.farmid=p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Campaign CRUD
CREATE OR REPLACE FUNCTION sprestaurant_campaign_list(p_farmid TEXT) RETURNS TABLE (
    campaignid INT, farmid TEXT, name TEXT, campaigntype TEXT, targetsegment TEXT,
    subject TEXT, message TEXT, channel TEXT, status TEXT, scheduledat TIMESTAMP,
    sentat TIMESTAMP, recipientcount INT, opencount INT, createdat TIMESTAMP
) AS $$
BEGIN RETURN QUERY SELECT ca.* FROM restaurantcampaigns ca WHERE ca.farmid=p_farmid ORDER BY ca.createdat DESC; END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_campaign_insert(
    p_farmid TEXT, p_name TEXT, p_campaigntype TEXT, p_targetsegment TEXT,
    p_subject TEXT, p_message TEXT, p_channel TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantcampaigns (farmid, name, campaigntype, targetsegment, subject, message, channel)
    VALUES (p_farmid, p_name, p_campaigntype, p_targetsegment, p_subject, p_message, p_channel)
    RETURNING campaignid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_campaign_delete(p_id INT, p_farmid TEXT) RETURNS VOID AS $$
BEGIN DELETE FROM restaurantcampaigns WHERE campaignid=p_id AND farmid=p_farmid; END;
$$ LANGUAGE plpgsql;

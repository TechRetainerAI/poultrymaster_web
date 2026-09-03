-- Migration 227: Restaurant Catering & Events
-- Applied: 2026-08-30

CREATE TABLE IF NOT EXISTS restaurantevents (
    eventid              SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    eventnumber          TEXT,
    name                 TEXT NOT NULL,
    eventtype            TEXT NOT NULL,   -- Corporate, Wedding, Birthday, HolidayParty, Buffet, Cocktail, Other
    eventdate            DATE NOT NULL,
    starttime            TEXT,
    endtime              TEXT,
    guestcount           INT DEFAULT 0,
    venue                TEXT,           -- InHouse, Offsite
    status               TEXT DEFAULT 'Inquiry', -- Inquiry, Confirmed, Deposit, InProgress, Completed, Cancelled
    contactname          TEXT,
    contactphone         TEXT,
    contactemail         TEXT,
    packagename          TEXT,
    priceperhead         NUMERIC(12,2) DEFAULT 0,
    totalamount          NUMERIC(12,2) DEFAULT 0,
    depositamount        NUMERIC(12,2) DEFAULT 0,
    depositpaid          BOOLEAN DEFAULT FALSE,
    balancedue           NUMERIC(12,2) DEFAULT 0,
    specialrequests      TEXT,
    dietarynotes         TEXT,
    notes                TEXT,
    createdby            TEXT,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantevents_farm ON restaurantevents(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantevents_date ON restaurantevents(farmid, eventdate);

-- SP: Events CRUD
CREATE OR REPLACE FUNCTION sprestaurant_event_list(p_farmid TEXT, p_status TEXT DEFAULT NULL)
RETURNS TABLE (
    eventid INT, farmid TEXT, eventnumber TEXT, name TEXT, eventtype TEXT, eventdate DATE,
    starttime TEXT, endtime TEXT, guestcount INT, venue TEXT, status TEXT,
    contactname TEXT, contactphone TEXT, contactemail TEXT, packagename TEXT,
    priceperhead NUMERIC, totalamount NUMERIC, depositamount NUMERIC, depositpaid BOOLEAN,
    balancedue NUMERIC, specialrequests TEXT, dietarynotes TEXT, notes TEXT, createdby TEXT,
    createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$ BEGIN RETURN QUERY SELECT e.* FROM restaurantevents e WHERE e.farmid=p_farmid AND (p_status IS NULL OR e.status=p_status) ORDER BY e.eventdate; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_event_insert(
    p_farmid TEXT, p_name TEXT, p_eventtype TEXT, p_eventdate DATE, p_starttime TEXT, p_endtime TEXT,
    p_guestcount INT, p_venue TEXT, p_contactname TEXT, p_contactphone TEXT, p_contactemail TEXT,
    p_packagename TEXT, p_priceperhead NUMERIC, p_specialrequests TEXT, p_dietarynotes TEXT, p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT; v_num TEXT; v_total NUMERIC;
BEGIN
    v_num := 'EVT-' || TO_CHAR(p_eventdate, 'YYYYMMDD') || '-' || LPAD((SELECT COUNT(*)::TEXT FROM restaurantevents WHERE farmid=p_farmid) + 1, 3, '0');
    v_total := p_priceperhead * p_guestcount;
    INSERT INTO restaurantevents (farmid, eventnumber, name, eventtype, eventdate, starttime, endtime, guestcount, venue,
        contactname, contactphone, contactemail, packagename, priceperhead, totalamount, balancedue, specialrequests, dietarynotes, notes, createdby)
    VALUES (p_farmid, v_num, p_name, p_eventtype, p_eventdate, p_starttime, p_endtime, p_guestcount, p_venue,
        p_contactname, p_contactphone, p_contactemail, p_packagename, p_priceperhead, v_total, v_total, p_specialrequests, p_dietarynotes, p_notes, p_createdby)
    RETURNING eventid INTO v_id; RETURN v_id;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_event_update_status(p_id INT, p_farmid TEXT, p_status TEXT) RETURNS VOID AS $$
BEGIN UPDATE restaurantevents SET status=p_status, updatedat=NOW() WHERE eventid=p_id AND farmid=p_farmid; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_event_delete(p_id INT, p_farmid TEXT) RETURNS VOID AS $$
BEGIN DELETE FROM restaurantevents WHERE eventid=p_id AND farmid=p_farmid; END; $$ LANGUAGE plpgsql;

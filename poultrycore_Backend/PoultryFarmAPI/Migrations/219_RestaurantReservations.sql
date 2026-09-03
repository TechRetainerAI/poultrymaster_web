-- Migration 219: Restaurant Management System — Reservations & Waitlist
-- Applied: 2026-08-30
-- Phase R4: Reservations, waitlist, reservation settings, no-show tracking

-- =============================================================================
-- 1. RESERVATION SETTINGS (per-restaurant config)
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantreservationsettings (
    reservationsettingid SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL UNIQUE,
    defaultdurationmins  INT DEFAULT 90,          -- default reservation slot length
    maxpartysizeonline   INT DEFAULT 12,
    minadvancehours      INT DEFAULT 1,           -- min hours before reservation
    maxadvancedays       INT DEFAULT 30,          -- max days ahead to book
    slotintervalmins     INT DEFAULT 30,          -- time slots: 30min intervals
    overbookingbuffer    INT DEFAULT 0,           -- extra reservations allowed beyond capacity
    autoconfirm          BOOLEAN DEFAULT TRUE,    -- auto-confirm or require manual
    noshow_threshold_mins INT DEFAULT 15,         -- minutes late before no-show
    cancellation_policy  TEXT,
    confirmation_message TEXT,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);

-- =============================================================================
-- 2. RESERVATIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantreservations (
    reservationid        SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    reservationnumber    TEXT NOT NULL,            -- RES-YYYYMMDD-NNN
    status               TEXT NOT NULL DEFAULT 'Confirmed', -- Pending, Confirmed, Seated, Completed, Cancelled, NoShow
    reservationdate      DATE NOT NULL,
    reservationtime      TEXT NOT NULL,            -- '18:30'
    endtime              TEXT,                     -- calculated: reservationtime + duration
    partysize            INT NOT NULL DEFAULT 2,
    guestname            TEXT NOT NULL,
    guestphone           TEXT,
    guestemail           TEXT,
    tableid              INT REFERENCES restauranttables(tableid) ON DELETE SET NULL,
    tablenumber          TEXT,
    specialrequests      TEXT,
    occasion             TEXT,                     -- Birthday, Anniversary, Business, Date, Other
    source               TEXT DEFAULT 'Phone',     -- Phone, WalkIn, Online, App
    isvip                BOOLEAN DEFAULT FALSE,
    notes                TEXT,
    cancelreason         TEXT,
    seatedat             TIMESTAMP,
    completedat          TIMESTAMP,
    noshowmarkedat       TIMESTAMP,
    remindersent         BOOLEAN DEFAULT FALSE,
    createdby            TEXT,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantreservations_farm ON restaurantreservations(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantreservations_farm_date ON restaurantreservations(farmid, reservationdate);
CREATE INDEX IF NOT EXISTS ix_restaurantreservations_farm_status ON restaurantreservations(farmid, status);
CREATE INDEX IF NOT EXISTS ix_restaurantreservations_farm_guest ON restaurantreservations(farmid, guestphone);

-- =============================================================================
-- 3. WAITLIST
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantwaitlist (
    waitlistid           SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    guestname            TEXT NOT NULL,
    guestphone           TEXT,
    partysize            INT NOT NULL DEFAULT 2,
    estimatedwaitmins    INT DEFAULT 15,
    status               TEXT NOT NULL DEFAULT 'Waiting', -- Waiting, Notified, Seated, Left, Cancelled
    notes                TEXT,
    quotedwaitmins       INT,                     -- what staff told the guest
    notifiedat           TIMESTAMP,               -- when SMS "table ready" sent
    seatedat             TIMESTAMP,
    tableid              INT REFERENCES restauranttables(tableid) ON DELETE SET NULL,
    tablenumber          TEXT,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantwaitlist_farm ON restaurantwaitlist(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantwaitlist_farm_status ON restaurantwaitlist(farmid, status);

-- =============================================================================
-- STORED PROCEDURES: RESERVATION SETTINGS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_reservationsettings_get(p_farmid TEXT)
RETURNS TABLE (
    reservationsettingid INT, farmid TEXT, defaultdurationmins INT,
    maxpartysizeonline INT, minadvancehours INT, maxadvancedays INT,
    slotintervalmins INT, overbookingbuffer INT, autoconfirm BOOLEAN,
    noshow_threshold_mins INT, cancellation_policy TEXT, confirmation_message TEXT,
    createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY SELECT s.* FROM restaurantreservationsettings s WHERE s.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_reservationsettings_upsert(
    p_farmid TEXT, p_defaultdurationmins INT, p_maxpartysizeonline INT,
    p_minadvancehours INT, p_maxadvancedays INT, p_slotintervalmins INT,
    p_overbookingbuffer INT, p_autoconfirm BOOLEAN, p_noshow_threshold_mins INT,
    p_cancellation_policy TEXT, p_confirmation_message TEXT
) RETURNS VOID AS $$
BEGIN
    INSERT INTO restaurantreservationsettings (farmid, defaultdurationmins, maxpartysizeonline,
        minadvancehours, maxadvancedays, slotintervalmins, overbookingbuffer, autoconfirm,
        noshow_threshold_mins, cancellation_policy, confirmation_message)
    VALUES (p_farmid, p_defaultdurationmins, p_maxpartysizeonline,
        p_minadvancehours, p_maxadvancedays, p_slotintervalmins, p_overbookingbuffer, p_autoconfirm,
        p_noshow_threshold_mins, p_cancellation_policy, p_confirmation_message)
    ON CONFLICT (farmid) DO UPDATE SET
        defaultdurationmins = p_defaultdurationmins, maxpartysizeonline = p_maxpartysizeonline,
        minadvancehours = p_minadvancehours, maxadvancedays = p_maxadvancedays,
        slotintervalmins = p_slotintervalmins, overbookingbuffer = p_overbookingbuffer,
        autoconfirm = p_autoconfirm, noshow_threshold_mins = p_noshow_threshold_mins,
        cancellation_policy = p_cancellation_policy, confirmation_message = p_confirmation_message,
        updatedat = NOW();
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: RESERVATIONS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_reservation_next_number(p_farmid TEXT, p_date DATE)
RETURNS TEXT AS $$
DECLARE v_seq INT; v_date TEXT;
BEGIN
    v_date := TO_CHAR(p_date, 'YYYYMMDD');
    SELECT COALESCE(MAX(
        CASE WHEN reservationnumber LIKE 'RES-' || v_date || '-%'
             THEN CAST(SPLIT_PART(reservationnumber, '-', 3) AS INT) ELSE 0 END
    ), 0) + 1 INTO v_seq
    FROM restaurantreservations WHERE farmid = p_farmid;
    RETURN 'RES-' || v_date || '-' || LPAD(v_seq::TEXT, 3, '0');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_reservation_insert(
    p_farmid TEXT, p_reservationdate DATE, p_reservationtime TEXT,
    p_endtime TEXT, p_partysize INT, p_guestname TEXT, p_guestphone TEXT,
    p_guestemail TEXT, p_tableid INT, p_tablenumber TEXT, p_specialrequests TEXT,
    p_occasion TEXT, p_source TEXT, p_isvip BOOLEAN, p_notes TEXT,
    p_createdby TEXT, p_autoconfirm BOOLEAN
) RETURNS TABLE (reservationid INT, reservationnumber TEXT) AS $$
DECLARE v_id INT; v_num TEXT; v_status TEXT;
BEGIN
    v_num := sprestaurant_reservation_next_number(p_farmid, p_reservationdate);
    v_status := CASE WHEN p_autoconfirm THEN 'Confirmed' ELSE 'Pending' END;
    INSERT INTO restaurantreservations (farmid, reservationnumber, status, reservationdate,
        reservationtime, endtime, partysize, guestname, guestphone, guestemail,
        tableid, tablenumber, specialrequests, occasion, source, isvip, notes, createdby)
    VALUES (p_farmid, v_num, v_status, p_reservationdate, p_reservationtime, p_endtime,
        p_partysize, p_guestname, p_guestphone, p_guestemail, p_tableid, p_tablenumber,
        p_specialrequests, p_occasion, p_source, p_isvip, p_notes, p_createdby)
    RETURNING restaurantreservations.reservationid INTO v_id;
    -- Mark table as reserved if assigned
    IF p_tableid IS NOT NULL THEN
        UPDATE restauranttables SET status = 'Reserved', updatedat = NOW()
        WHERE restauranttables.tableid = p_tableid AND restauranttables.farmid = p_farmid
          AND restauranttables.status = 'Available';
    END IF;
    RETURN QUERY SELECT v_id, v_num;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_reservation_list(
    p_farmid TEXT, p_date DATE DEFAULT NULL, p_status TEXT DEFAULT NULL,
    p_fromdate DATE DEFAULT NULL, p_todate DATE DEFAULT NULL
)
RETURNS TABLE (
    reservationid INT, farmid TEXT, reservationnumber TEXT, status TEXT,
    reservationdate DATE, reservationtime TEXT, endtime TEXT, partysize INT,
    guestname TEXT, guestphone TEXT, guestemail TEXT,
    tableid INT, tablenumber TEXT, specialrequests TEXT, occasion TEXT,
    source TEXT, isvip BOOLEAN, notes TEXT, cancelreason TEXT,
    seatedat TIMESTAMP, completedat TIMESTAMP, noshowmarkedat TIMESTAMP,
    remindersent BOOLEAN, createdby TEXT, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT r.reservationid, r.farmid, r.reservationnumber, r.status,
           r.reservationdate, r.reservationtime, r.endtime, r.partysize,
           r.guestname, r.guestphone, r.guestemail,
           r.tableid, r.tablenumber, r.specialrequests, r.occasion,
           r.source, r.isvip, r.notes, r.cancelreason,
           r.seatedat, r.completedat, r.noshowmarkedat,
           r.remindersent, r.createdby, r.createdat, r.updatedat
    FROM restaurantreservations r
    WHERE r.farmid = p_farmid
      AND (p_date IS NULL OR r.reservationdate = p_date)
      AND (p_status IS NULL OR r.status = p_status)
      AND (p_fromdate IS NULL OR r.reservationdate >= p_fromdate)
      AND (p_todate IS NULL OR r.reservationdate <= p_todate)
    ORDER BY r.reservationdate, r.reservationtime;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_reservation_get(p_id INT, p_farmid TEXT)
RETURNS TABLE (
    reservationid INT, farmid TEXT, reservationnumber TEXT, status TEXT,
    reservationdate DATE, reservationtime TEXT, endtime TEXT, partysize INT,
    guestname TEXT, guestphone TEXT, guestemail TEXT,
    tableid INT, tablenumber TEXT, specialrequests TEXT, occasion TEXT,
    source TEXT, isvip BOOLEAN, notes TEXT, cancelreason TEXT,
    seatedat TIMESTAMP, completedat TIMESTAMP, noshowmarkedat TIMESTAMP,
    remindersent BOOLEAN, createdby TEXT, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT r.reservationid, r.farmid, r.reservationnumber, r.status,
           r.reservationdate, r.reservationtime, r.endtime, r.partysize,
           r.guestname, r.guestphone, r.guestemail,
           r.tableid, r.tablenumber, r.specialrequests, r.occasion,
           r.source, r.isvip, r.notes, r.cancelreason,
           r.seatedat, r.completedat, r.noshowmarkedat,
           r.remindersent, r.createdby, r.createdat, r.updatedat
    FROM restaurantreservations r
    WHERE r.reservationid = p_id AND r.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_reservation_update(
    p_id INT, p_farmid TEXT, p_reservationdate DATE, p_reservationtime TEXT,
    p_endtime TEXT, p_partysize INT, p_guestname TEXT, p_guestphone TEXT,
    p_guestemail TEXT, p_tableid INT, p_tablenumber TEXT, p_specialrequests TEXT,
    p_occasion TEXT, p_source TEXT, p_isvip BOOLEAN, p_notes TEXT
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantreservations SET reservationdate = p_reservationdate,
        reservationtime = p_reservationtime, endtime = p_endtime, partysize = p_partysize,
        guestname = p_guestname, guestphone = p_guestphone, guestemail = p_guestemail,
        tableid = p_tableid, tablenumber = p_tablenumber, specialrequests = p_specialrequests,
        occasion = p_occasion, source = p_source, isvip = p_isvip, notes = p_notes,
        updatedat = NOW()
    WHERE reservationid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_reservation_update_status(
    p_id INT, p_farmid TEXT, p_status TEXT, p_reason TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantreservations SET status = p_status, updatedat = NOW(),
        cancelreason = CASE WHEN p_status = 'Cancelled' THEN p_reason ELSE cancelreason END,
        seatedat = CASE WHEN p_status = 'Seated' THEN NOW() ELSE seatedat END,
        completedat = CASE WHEN p_status = 'Completed' THEN NOW() ELSE completedat END,
        noshowmarkedat = CASE WHEN p_status = 'NoShow' THEN NOW() ELSE noshowmarkedat END
    WHERE reservationid = p_id AND farmid = p_farmid;
    -- Free table on cancel/noshow/complete
    IF p_status IN ('Cancelled', 'NoShow', 'Completed') THEN
        UPDATE restauranttables SET status = 'Available', updatedat = NOW()
        WHERE restauranttables.tableid = (SELECT r.tableid FROM restaurantreservations r WHERE r.reservationid = p_id)
          AND restauranttables.farmid = p_farmid AND restauranttables.status = 'Reserved';
    END IF;
    -- Mark table occupied on seated
    IF p_status = 'Seated' THEN
        UPDATE restauranttables SET status = 'Occupied', updatedat = NOW()
        WHERE restauranttables.tableid = (SELECT r.tableid FROM restaurantreservations r WHERE r.reservationid = p_id)
          AND restauranttables.farmid = p_farmid;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_reservation_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantreservations WHERE reservationid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Auto-assign table based on party size and availability for a date/time
CREATE OR REPLACE FUNCTION sprestaurant_reservation_auto_assign_table(
    p_farmid TEXT, p_partysize INT, p_date DATE, p_time TEXT
) RETURNS TABLE (tableid INT, tablenumber TEXT, capacity INT) AS $$
BEGIN
    RETURN QUERY
    SELECT t.tableid, t.tablenumber, t.capacity
    FROM restauranttables t
    WHERE t.farmid = p_farmid AND t.isactive = TRUE AND t.capacity >= p_partysize
      AND t.tableid NOT IN (
          SELECT r.tableid FROM restaurantreservations r
          WHERE r.farmid = p_farmid AND r.reservationdate = p_date
            AND r.status IN ('Pending', 'Confirmed')
            AND r.tableid IS NOT NULL
            AND (
                (r.reservationtime <= p_time AND (r.endtime IS NULL OR r.endtime > p_time))
                OR (r.reservationtime >= p_time AND r.reservationtime < p_time)
            )
      )
    ORDER BY t.capacity - p_partysize, t.tablenumber
    LIMIT 5;
END;
$$ LANGUAGE plpgsql;

-- Reservation stats for a date
CREATE OR REPLACE FUNCTION sprestaurant_reservation_stats(p_farmid TEXT, p_date DATE)
RETURNS TABLE (
    total_count BIGINT, confirmed_count BIGINT, seated_count BIGINT,
    completed_count BIGINT, cancelled_count BIGINT, noshow_count BIGINT,
    total_covers BIGINT, noshow_rate DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) AS total_count,
        COUNT(*) FILTER (WHERE r.status = 'Confirmed') AS confirmed_count,
        COUNT(*) FILTER (WHERE r.status = 'Seated') AS seated_count,
        COUNT(*) FILTER (WHERE r.status = 'Completed') AS completed_count,
        COUNT(*) FILTER (WHERE r.status = 'Cancelled') AS cancelled_count,
        COUNT(*) FILTER (WHERE r.status = 'NoShow') AS noshow_count,
        COALESCE(SUM(r.partysize), 0) AS total_covers,
        CASE WHEN COUNT(*) FILTER (WHERE r.status IN ('Completed','NoShow')) > 0
            THEN COUNT(*) FILTER (WHERE r.status = 'NoShow')::DOUBLE PRECISION /
                 COUNT(*) FILTER (WHERE r.status IN ('Completed','NoShow'))::DOUBLE PRECISION * 100
            ELSE 0 END AS noshow_rate
    FROM restaurantreservations r
    WHERE r.farmid = p_farmid AND r.reservationdate = p_date;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: WAITLIST
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_waitlist_list(p_farmid TEXT, p_status TEXT DEFAULT NULL)
RETURNS TABLE (
    waitlistid INT, farmid TEXT, guestname TEXT, guestphone TEXT,
    partysize INT, estimatedwaitmins INT, status TEXT, notes TEXT,
    quotedwaitmins INT, notifiedat TIMESTAMP, seatedat TIMESTAMP,
    tableid INT, tablenumber TEXT, createdat TIMESTAMP, updatedat TIMESTAMP,
    actualwaitmins DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT w.waitlistid, w.farmid, w.guestname, w.guestphone,
           w.partysize, w.estimatedwaitmins, w.status, w.notes,
           w.quotedwaitmins, w.notifiedat, w.seatedat,
           w.tableid, w.tablenumber, w.createdat, w.updatedat,
           EXTRACT(EPOCH FROM (COALESCE(w.seatedat, NOW()) - w.createdat)) / 60.0 AS actualwaitmins
    FROM restaurantwaitlist w
    WHERE w.farmid = p_farmid
      AND (p_status IS NULL OR w.status = p_status)
    ORDER BY w.createdat;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_waitlist_insert(
    p_farmid TEXT, p_guestname TEXT, p_guestphone TEXT, p_partysize INT,
    p_estimatedwaitmins INT, p_quotedwaitmins INT, p_notes TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantwaitlist (farmid, guestname, guestphone, partysize,
        estimatedwaitmins, quotedwaitmins, notes)
    VALUES (p_farmid, p_guestname, p_guestphone, p_partysize,
        p_estimatedwaitmins, p_quotedwaitmins, p_notes)
    RETURNING waitlistid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_waitlist_update_status(
    p_id INT, p_farmid TEXT, p_status TEXT, p_tableid INT DEFAULT NULL, p_tablenumber TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantwaitlist SET status = p_status, updatedat = NOW(),
        notifiedat = CASE WHEN p_status = 'Notified' THEN NOW() ELSE notifiedat END,
        seatedat = CASE WHEN p_status = 'Seated' THEN NOW() ELSE seatedat END,
        tableid = CASE WHEN p_status = 'Seated' THEN p_tableid ELSE tableid END,
        tablenumber = CASE WHEN p_status = 'Seated' THEN p_tablenumber ELSE tablenumber END
    WHERE waitlistid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_waitlist_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantwaitlist WHERE waitlistid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Current waitlist count and average wait
CREATE OR REPLACE FUNCTION sprestaurant_waitlist_stats(p_farmid TEXT)
RETURNS TABLE (
    waiting_count BIGINT, notified_count BIGINT,
    avg_wait_mins DOUBLE PRECISION, longest_wait_mins DOUBLE PRECISION,
    total_covers BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) FILTER (WHERE w.status = 'Waiting') AS waiting_count,
        COUNT(*) FILTER (WHERE w.status = 'Notified') AS notified_count,
        AVG(EXTRACT(EPOCH FROM (NOW() - w.createdat)) / 60.0) FILTER (WHERE w.status IN ('Waiting','Notified')) AS avg_wait_mins,
        MAX(EXTRACT(EPOCH FROM (NOW() - w.createdat)) / 60.0) FILTER (WHERE w.status IN ('Waiting','Notified')) AS longest_wait_mins,
        COALESCE(SUM(w.partysize) FILTER (WHERE w.status IN ('Waiting','Notified')), 0) AS total_covers
    FROM restaurantwaitlist w
    WHERE w.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

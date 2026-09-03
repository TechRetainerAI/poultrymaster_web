-- Migration 226: Restaurant Notifications & Alerts
-- Applied: 2026-08-30

CREATE TABLE IF NOT EXISTS restaurantnotifications (
    notificationid       SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    type                 TEXT NOT NULL,   -- OrderNew, OrderReady, LowStock, Reservation, KPIAlert, ShiftReminder, SystemAlert
    title                TEXT NOT NULL,
    message              TEXT NOT NULL,
    severity             TEXT DEFAULT 'Info', -- Info, Warning, Critical
    isread               BOOLEAN DEFAULT FALSE,
    targetuserid         TEXT,
    targetrole           TEXT,
    relatedid            INT,             -- orderId, ingredientId, reservationId, etc.
    relatedtype          TEXT,            -- Order, Ingredient, Reservation, etc.
    createdat            TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantnotifications_farm ON restaurantnotifications(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantnotifications_unread ON restaurantnotifications(farmid, isread) WHERE isread = FALSE;

CREATE TABLE IF NOT EXISTS restaurantnotificationsettings (
    notificationsettingid SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL UNIQUE,
    emailenabled         BOOLEAN DEFAULT TRUE,
    smsenabled           BOOLEAN DEFAULT FALSE,
    pushenabled          BOOLEAN DEFAULT FALSE,
    lowstockalerts       BOOLEAN DEFAULT TRUE,
    neworderalerts       BOOLEAN DEFAULT TRUE,
    reservationalerts    BOOLEAN DEFAULT TRUE,
    kpialerts            BOOLEAN DEFAULT TRUE,
    shiftreminders       BOOLEAN DEFAULT TRUE,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);

-- SP: List/create/mark-read notifications
CREATE OR REPLACE FUNCTION sprestaurant_notification_list(p_farmid TEXT, p_unreadonly BOOLEAN DEFAULT FALSE)
RETURNS TABLE (notificationid INT, farmid TEXT, type TEXT, title TEXT, message TEXT, severity TEXT, isread BOOLEAN, targetuserid TEXT, targetrole TEXT, relatedid INT, relatedtype TEXT, createdat TIMESTAMP) AS $$
BEGIN RETURN QUERY SELECT n.* FROM restaurantnotifications n WHERE n.farmid=p_farmid AND (NOT p_unreadonly OR n.isread=FALSE) ORDER BY n.createdat DESC LIMIT 100; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_notification_create(p_farmid TEXT, p_type TEXT, p_title TEXT, p_message TEXT, p_severity TEXT, p_targetrole TEXT DEFAULT NULL, p_relatedid INT DEFAULT NULL, p_relatedtype TEXT DEFAULT NULL) RETURNS INT AS $$
DECLARE v_id INT; BEGIN INSERT INTO restaurantnotifications (farmid, type, title, message, severity, targetrole, relatedid, relatedtype) VALUES (p_farmid, p_type, p_title, p_message, p_severity, p_targetrole, p_relatedid, p_relatedtype) RETURNING notificationid INTO v_id; RETURN v_id; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_notification_markread(p_id INT, p_farmid TEXT) RETURNS VOID AS $$
BEGIN UPDATE restaurantnotifications SET isread=TRUE WHERE notificationid=p_id AND farmid=p_farmid; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_notification_markallread(p_farmid TEXT) RETURNS VOID AS $$
BEGIN UPDATE restaurantnotifications SET isread=TRUE WHERE farmid=p_farmid AND isread=FALSE; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_notification_settings_get(p_farmid TEXT) RETURNS TABLE (
    notificationsettingid INT, farmid TEXT, emailenabled BOOLEAN, smsenabled BOOLEAN, pushenabled BOOLEAN,
    lowstockalerts BOOLEAN, neworderalerts BOOLEAN, reservationalerts BOOLEAN, kpialerts BOOLEAN, shiftreminders BOOLEAN,
    createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$ BEGIN RETURN QUERY SELECT s.* FROM restaurantnotificationsettings s WHERE s.farmid=p_farmid; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_notification_settings_upsert(
    p_farmid TEXT, p_emailenabled BOOLEAN, p_smsenabled BOOLEAN, p_pushenabled BOOLEAN,
    p_lowstockalerts BOOLEAN, p_neworderalerts BOOLEAN, p_reservationalerts BOOLEAN,
    p_kpialerts BOOLEAN, p_shiftreminders BOOLEAN
) RETURNS VOID AS $$
BEGIN INSERT INTO restaurantnotificationsettings (farmid, emailenabled, smsenabled, pushenabled, lowstockalerts, neworderalerts, reservationalerts, kpialerts, shiftreminders)
VALUES (p_farmid, p_emailenabled, p_smsenabled, p_pushenabled, p_lowstockalerts, p_neworderalerts, p_reservationalerts, p_kpialerts, p_shiftreminders)
ON CONFLICT (farmid) DO UPDATE SET emailenabled=p_emailenabled, smsenabled=p_smsenabled, pushenabled=p_pushenabled,
    lowstockalerts=p_lowstockalerts, neworderalerts=p_neworderalerts, reservationalerts=p_reservationalerts,
    kpialerts=p_kpialerts, shiftreminders=p_shiftreminders, updatedat=NOW(); END; $$ LANGUAGE plpgsql;

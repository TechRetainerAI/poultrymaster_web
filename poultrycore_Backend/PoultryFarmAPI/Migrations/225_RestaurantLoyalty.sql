-- Migration 225: Restaurant Loyalty & Rewards
-- Applied: 2026-08-30

CREATE TABLE IF NOT EXISTS restaurantloyaltysettings (
    loyaltysettingid     SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL UNIQUE,
    isenabled            BOOLEAN DEFAULT FALSE,
    pointspercurrencyunit NUMERIC(8,2) DEFAULT 1,  -- 1 point per $1
    pointsredemptionrate NUMERIC(8,4) DEFAULT 0.01, -- 1 point = $0.01
    minimumredeempoints  INT DEFAULT 100,
    pointsexpirydays     INT DEFAULT 365,
    tiersenabled         BOOLEAN DEFAULT FALSE,
    bronzethreshold      INT DEFAULT 0,
    silverthreshold      INT DEFAULT 500,
    goldthreshold        INT DEFAULT 1000,
    platinumthreshold    INT DEFAULT 2500,
    bronzemultiplier     NUMERIC(4,2) DEFAULT 1,
    silvermultiplier     NUMERIC(4,2) DEFAULT 1.5,
    goldmultiplier       NUMERIC(4,2) DEFAULT 2,
    platinummultiplier   NUMERIC(4,2) DEFAULT 3,
    referralbonus        INT DEFAULT 50,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);

CREATE TABLE IF NOT EXISTS restaurantloyaltyaccounts (
    loyaltyaccountid     SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    customerid           INT REFERENCES restaurantcustomers(customerid) ON DELETE CASCADE,
    customername         TEXT NOT NULL,
    customerphone        TEXT,
    totalpoints          INT DEFAULT 0,
    lifetimepoints       INT DEFAULT 0,
    currenttier          TEXT DEFAULT 'Bronze',
    referralcode         TEXT,
    referredby           INT,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantloyalty_farm ON restaurantloyaltyaccounts(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantloyalty_customer ON restaurantloyaltyaccounts(farmid, customerid);

CREATE TABLE IF NOT EXISTS restaurantpointtransactions (
    pointtransactionid   SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    loyaltyaccountid     INT NOT NULL REFERENCES restaurantloyaltyaccounts(loyaltyaccountid) ON DELETE CASCADE,
    transactiontype      TEXT NOT NULL, -- Earned, Redeemed, Bonus, Referral, Expired, Adjusted
    points               INT NOT NULL,
    description          TEXT,
    orderid              INT,
    createdat            TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantpointtx_account ON restaurantpointtransactions(farmid, loyaltyaccountid);

-- Settings CRUD
CREATE OR REPLACE FUNCTION sprestaurant_loyalty_settings_get(p_farmid TEXT) RETURNS TABLE (
    loyaltysettingid INT, farmid TEXT, isenabled BOOLEAN, pointspercurrencyunit NUMERIC, pointsredemptionrate NUMERIC,
    minimumredeempoints INT, pointsexpirydays INT, tiersenabled BOOLEAN,
    bronzethreshold INT, silverthreshold INT, goldthreshold INT, platinumthreshold INT,
    bronzemultiplier NUMERIC, silvermultiplier NUMERIC, goldmultiplier NUMERIC, platinummultiplier NUMERIC,
    referralbonus INT, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$ BEGIN RETURN QUERY SELECT s.* FROM restaurantloyaltysettings s WHERE s.farmid=p_farmid; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_loyalty_settings_upsert(
    p_farmid TEXT, p_isenabled BOOLEAN, p_pointspercurrencyunit NUMERIC, p_pointsredemptionrate NUMERIC,
    p_minimumredeempoints INT, p_pointsexpirydays INT, p_tiersenabled BOOLEAN,
    p_bronzethreshold INT, p_silverthreshold INT, p_goldthreshold INT, p_platinumthreshold INT,
    p_bronzemultiplier NUMERIC, p_silvermultiplier NUMERIC, p_goldmultiplier NUMERIC, p_platinummultiplier NUMERIC,
    p_referralbonus INT
) RETURNS VOID AS $$
BEGIN
    INSERT INTO restaurantloyaltysettings (farmid, isenabled, pointspercurrencyunit, pointsredemptionrate,
        minimumredeempoints, pointsexpirydays, tiersenabled, bronzethreshold, silverthreshold, goldthreshold,
        platinumthreshold, bronzemultiplier, silvermultiplier, goldmultiplier, platinummultiplier, referralbonus)
    VALUES (p_farmid, p_isenabled, p_pointspercurrencyunit, p_pointsredemptionrate,
        p_minimumredeempoints, p_pointsexpirydays, p_tiersenabled, p_bronzethreshold, p_silverthreshold,
        p_goldthreshold, p_platinumthreshold, p_bronzemultiplier, p_silvermultiplier, p_goldmultiplier,
        p_platinummultiplier, p_referralbonus)
    ON CONFLICT (farmid) DO UPDATE SET isenabled=p_isenabled, pointspercurrencyunit=p_pointspercurrencyunit,
        pointsredemptionrate=p_pointsredemptionrate, minimumredeempoints=p_minimumredeempoints,
        pointsexpirydays=p_pointsexpirydays, tiersenabled=p_tiersenabled,
        bronzethreshold=p_bronzethreshold, silverthreshold=p_silverthreshold, goldthreshold=p_goldthreshold,
        platinumthreshold=p_platinumthreshold, bronzemultiplier=p_bronzemultiplier, silvermultiplier=p_silvermultiplier,
        goldmultiplier=p_goldmultiplier, platinummultiplier=p_platinummultiplier, referralbonus=p_referralbonus, updatedat=NOW();
END; $$ LANGUAGE plpgsql;

-- Loyalty accounts CRUD
CREATE OR REPLACE FUNCTION sprestaurant_loyalty_account_list(p_farmid TEXT, p_tier TEXT DEFAULT NULL)
RETURNS TABLE (
    loyaltyaccountid INT, farmid TEXT, customerid INT, customername TEXT, customerphone TEXT,
    totalpoints INT, lifetimepoints INT, currenttier TEXT, referralcode TEXT, referredby INT,
    createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$ BEGIN RETURN QUERY SELECT a.* FROM restaurantloyaltyaccounts a WHERE a.farmid=p_farmid AND (p_tier IS NULL OR a.currenttier=p_tier) ORDER BY a.lifetimepoints DESC; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_loyalty_account_create(
    p_farmid TEXT, p_customerid INT, p_customername TEXT, p_customerphone TEXT
) RETURNS INT AS $$
DECLARE v_id INT; v_code TEXT;
BEGIN
    v_code := 'REF-' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 6));
    INSERT INTO restaurantloyaltyaccounts (farmid, customerid, customername, customerphone, referralcode)
    VALUES (p_farmid, p_customerid, p_customername, p_customerphone, v_code) RETURNING loyaltyaccountid INTO v_id;
    RETURN v_id;
END; $$ LANGUAGE plpgsql;

-- Earn points
CREATE OR REPLACE FUNCTION sprestaurant_loyalty_earn(p_accountid INT, p_farmid TEXT, p_points INT, p_description TEXT, p_orderid INT DEFAULT NULL) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantloyaltyaccounts SET totalpoints=totalpoints+p_points, lifetimepoints=lifetimepoints+p_points, updatedat=NOW()
    WHERE loyaltyaccountid=p_accountid AND farmid=p_farmid;
    INSERT INTO restaurantpointtransactions (farmid, loyaltyaccountid, transactiontype, points, description, orderid)
    VALUES (p_farmid, p_accountid, 'Earned', p_points, p_description, p_orderid);
    -- Auto tier upgrade
    UPDATE restaurantloyaltyaccounts SET currenttier = CASE
        WHEN lifetimepoints+p_points >= (SELECT platinumthreshold FROM restaurantloyaltysettings WHERE farmid=p_farmid) THEN 'Platinum'
        WHEN lifetimepoints+p_points >= (SELECT goldthreshold FROM restaurantloyaltysettings WHERE farmid=p_farmid) THEN 'Gold'
        WHEN lifetimepoints+p_points >= (SELECT silverthreshold FROM restaurantloyaltysettings WHERE farmid=p_farmid) THEN 'Silver'
        ELSE 'Bronze' END
    WHERE loyaltyaccountid=p_accountid AND farmid=p_farmid;
END; $$ LANGUAGE plpgsql;

-- Redeem points
CREATE OR REPLACE FUNCTION sprestaurant_loyalty_redeem(p_accountid INT, p_farmid TEXT, p_points INT, p_description TEXT) RETURNS BOOLEAN AS $$
DECLARE v_bal INT;
BEGIN
    SELECT totalpoints INTO v_bal FROM restaurantloyaltyaccounts WHERE loyaltyaccountid=p_accountid AND farmid=p_farmid;
    IF v_bal < p_points THEN RETURN FALSE; END IF;
    UPDATE restaurantloyaltyaccounts SET totalpoints=totalpoints-p_points, updatedat=NOW() WHERE loyaltyaccountid=p_accountid AND farmid=p_farmid;
    INSERT INTO restaurantpointtransactions (farmid, loyaltyaccountid, transactiontype, points, description) VALUES (p_farmid, p_accountid, 'Redeemed', -p_points, p_description);
    RETURN TRUE;
END; $$ LANGUAGE plpgsql;

-- Transaction history
CREATE OR REPLACE FUNCTION sprestaurant_loyalty_transactions(p_accountid INT, p_farmid TEXT)
RETURNS TABLE (pointtransactionid INT, transactiontype TEXT, points INT, description TEXT, orderid INT, createdat TIMESTAMP) AS $$
BEGIN RETURN QUERY SELECT t.pointtransactionid, t.transactiontype, t.points, t.description, t.orderid, t.createdat
FROM restaurantpointtransactions t WHERE t.loyaltyaccountid=p_accountid AND t.farmid=p_farmid ORDER BY t.createdat DESC; END; $$ LANGUAGE plpgsql;

-- Stats
CREATE OR REPLACE FUNCTION sprestaurant_loyalty_stats(p_farmid TEXT)
RETURNS TABLE (total_members BIGINT, total_points_outstanding BIGINT, bronze_count BIGINT, silver_count BIGINT, gold_count BIGINT, platinum_count BIGINT) AS $$
BEGIN RETURN QUERY SELECT COUNT(*), COALESCE(SUM(a.totalpoints)::BIGINT,0),
    COUNT(*) FILTER (WHERE a.currenttier='Bronze'), COUNT(*) FILTER (WHERE a.currenttier='Silver'),
    COUNT(*) FILTER (WHERE a.currenttier='Gold'), COUNT(*) FILTER (WHERE a.currenttier='Platinum')
FROM restaurantloyaltyaccounts a WHERE a.farmid=p_farmid; END; $$ LANGUAGE plpgsql;

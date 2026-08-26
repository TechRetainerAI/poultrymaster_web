-- Hotel Guest Loyalty Program
CREATE TABLE IF NOT EXISTS hotelloyaltymembers (
    hotelloyaltymemberid SERIAL PRIMARY KEY,
    farmid VARCHAR(450) NOT NULL,
    hotelguestid INTEGER NOT NULL REFERENCES hotelguests(hotelguestid) ON DELETE CASCADE,
    membershipnumber VARCHAR(50) NOT NULL,
    tier VARCHAR(20) NOT NULL DEFAULT 'Bronze',  -- Bronze, Silver, Gold, Platinum
    totalpoints INTEGER NOT NULL DEFAULT 0,
    lifetimepoints INTEGER NOT NULL DEFAULT 0,
    joinedat TIMESTAMP NOT NULL DEFAULT NOW(),
    lasttierupdate TIMESTAMP,
    notes TEXT,
    isactive BOOLEAN NOT NULL DEFAULT TRUE,
    createdat TIMESTAMP NOT NULL DEFAULT NOW(),
    updatedat TIMESTAMP,
    UNIQUE(farmid, hotelguestid),
    UNIQUE(farmid, membershipnumber)
);

CREATE TABLE IF NOT EXISTS hotelloyaltytransactions (
    hotelloyaltytransactionid SERIAL PRIMARY KEY,
    farmid VARCHAR(450) NOT NULL,
    hotelloyaltymemberid INTEGER NOT NULL REFERENCES hotelloyaltymembers(hotelloyaltymemberid) ON DELETE CASCADE,
    hotelbookingid INTEGER REFERENCES hotelbookings(hotelbookingid),
    transactiontype VARCHAR(20) NOT NULL,  -- Earn, Redeem, Adjust, Expire
    points INTEGER NOT NULL,
    description TEXT,
    createdat TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_hotelloyaltymembers_farm ON hotelloyaltymembers(farmid);
CREATE INDEX IF NOT EXISTS ix_hotelloyaltymembers_guest ON hotelloyaltymembers(hotelguestid);
CREATE INDEX IF NOT EXISTS ix_hotelloyaltytransactions_member ON hotelloyaltytransactions(hotelloyaltymemberid);

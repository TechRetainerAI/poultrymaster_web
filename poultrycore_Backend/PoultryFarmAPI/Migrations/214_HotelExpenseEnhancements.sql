-- Migration 214: Hotel Expense Enhancements (matching water-side pattern)
-- Adds: expense categories, cash account link, payment method, paid-to, status workflow

-- 1. Expense categories table
CREATE TABLE IF NOT EXISTS hotelexpensecategories (
    hotelexpensecategoryid SERIAL PRIMARY KEY,
    farmid TEXT NOT NULL,
    name VARCHAR(100) NOT NULL,
    isactive BOOLEAN NOT NULL DEFAULT TRUE,
    createdat TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_hotelexpcats_farm ON hotelexpensecategories(farmid);

-- 2. Add new columns to hotelexpenses
ALTER TABLE hotelexpenses ADD COLUMN IF NOT EXISTS paymentmethod VARCHAR(30) DEFAULT 'Cash';
ALTER TABLE hotelexpenses ADD COLUMN IF NOT EXISTS hotelcashaccountid INT REFERENCES hotelcashaccounts(hotelcashaccountid);
ALTER TABLE hotelexpenses ADD COLUMN IF NOT EXISTS paidto VARCHAR(200);
ALTER TABLE hotelexpenses ADD COLUMN IF NOT EXISTS hotelexpensecategoryid INT REFERENCES hotelexpensecategories(hotelexpensecategoryid);
ALTER TABLE hotelexpenses ADD COLUMN IF NOT EXISTS submittedby TEXT;
ALTER TABLE hotelexpenses ADD COLUMN IF NOT EXISTS submittedat TIMESTAMPTZ;
ALTER TABLE hotelexpenses ADD COLUMN IF NOT EXISTS approvedat TIMESTAMPTZ;
ALTER TABLE hotelexpenses ADD COLUMN IF NOT EXISTS cancelreason TEXT;

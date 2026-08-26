-- Migration 213: Hotel Cash Ledger Integration
-- Links payments, expenses, POS orders, and payroll to cash accounts
-- Applied: 2026-08-27

-- 1. Create cash transactions ledger table
CREATE TABLE IF NOT EXISTS hotelcashtransactions (
    hotelcashtxnid SERIAL PRIMARY KEY,
    farmid TEXT NOT NULL,
    hotelcashaccountid INT NOT NULL REFERENCES hotelcashaccounts(hotelcashaccountid),
    txntype VARCHAR(20) NOT NULL,           -- 'Credit' or 'Debit'
    amount NUMERIC(12,2) NOT NULL,
    balanceafter NUMERIC(12,2) NOT NULL,
    description VARCHAR(500),
    reference VARCHAR(100),
    sourcetype VARCHAR(30),                 -- 'Payment', 'Expense', 'Order', 'Payroll'
    sourceid INT,                           -- ID of the source record
    txndate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    createdby VARCHAR(450),
    createdat TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_hotelcashtxn_farm ON hotelcashtransactions(farmid);
CREATE INDEX IF NOT EXISTS ix_hotelcashtxn_account ON hotelcashtransactions(hotelcashaccountid);

-- 2. Add purpose column to cash accounts for default account identification
ALTER TABLE hotelcashaccounts ADD COLUMN IF NOT EXISTS purpose VARCHAR(30);
-- purpose values: 'FrontDesk', 'Expenses', 'POS', 'Payroll', NULL (user-created general account)

-- Hotel Payroll: run-based payroll system (Draft → Approved → Paid → Cancelled)
-- Matches the pattern in Poultry/Generic/Water payroll modules.

CREATE TABLE IF NOT EXISTS hotelpayrollruns (
    hotelpayrollrunid   SERIAL PRIMARY KEY,
    farmid              TEXT NOT NULL,
    periodstart         DATE NOT NULL,
    periodend           DATE NOT NULL,
    paydate             DATE,
    totalgrosspay       NUMERIC(12,2) NOT NULL DEFAULT 0,
    totaldeductions     NUMERIC(12,2) NOT NULL DEFAULT 0,
    totalnetpay         NUMERIC(12,2) NOT NULL DEFAULT 0,
    status              TEXT NOT NULL DEFAULT 'Draft',
    hotelcashaccountid  INT,
    cashaccountname     TEXT,
    notes               TEXT,
    createdby           TEXT,
    approvedby          TEXT,
    approvedat          TIMESTAMPTZ,
    paidby              TEXT,
    paidat              TIMESTAMPTZ,
    cancelledby         TEXT,
    cancelreason        TEXT,
    createdat           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updatedat           TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS hotelpayrollitems (
    hotelpayrollitemid  SERIAL PRIMARY KEY,
    hotelpayrollrunid   INT NOT NULL REFERENCES hotelpayrollruns(hotelpayrollrunid) ON DELETE CASCADE,
    hotelstaffid        INT NOT NULL,
    staffname           TEXT,
    staffrole           TEXT,
    basicpay            NUMERIC(12,2) NOT NULL DEFAULT 0,
    dailywage           NUMERIC(12,2) NOT NULL DEFAULT 0,
    commission          NUMERIC(12,2) NOT NULL DEFAULT 0,
    bonus               NUMERIC(12,2) NOT NULL DEFAULT 0,
    deductions          NUMERIC(12,2) NOT NULL DEFAULT 0,
    netpay              NUMERIC(12,2) NOT NULL DEFAULT 0,
    paymentmethod       TEXT DEFAULT 'Cash',
    notes               TEXT,
    createdat           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_hotelpayrollruns_farmid ON hotelpayrollruns(farmid);
CREATE INDEX IF NOT EXISTS ix_hotelpayrollitems_runid ON hotelpayrollitems(hotelpayrollrunid);

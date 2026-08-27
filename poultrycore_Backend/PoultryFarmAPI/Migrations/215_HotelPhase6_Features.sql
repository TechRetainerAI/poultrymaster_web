-- Migration 215: Hotel Phase 6 — New Features
-- Room availability, guest folio, stay history, deposits,
-- guest communication, requests, lost & found, DND flags,
-- housekeeping scheduling, shift handover notes

-- 1. Guest stay history (completed stays — aggregated view)
-- Already tracked via hotelcheckins/hotelcheckouts/hotelbookings — no new table needed, just query

-- 2. Deposit tracking
CREATE TABLE IF NOT EXISTS hoteldeposits (
    hoteldepositid SERIAL PRIMARY KEY,
    farmid TEXT NOT NULL,
    hotelbookingid INT NOT NULL,
    hotelguestid INT NOT NULL,
    deposittype VARCHAR(20) NOT NULL DEFAULT 'Collected',  -- Collected, Refunded, Applied
    amount NUMERIC(12,2) NOT NULL,
    method VARCHAR(30),
    reference VARCHAR(100),
    notes TEXT,
    processedby VARCHAR(450),
    createdat TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_hoteldeposits_farm ON hoteldeposits(farmid, hotelbookingid);

-- 3. Guest communication log
CREATE TABLE IF NOT EXISTS hotelguestcommunications (
    hotelguestcommid SERIAL PRIMARY KEY,
    farmid TEXT NOT NULL,
    hotelguestid INT NOT NULL,
    hotelbookingid INT,
    commtype VARCHAR(30) NOT NULL DEFAULT 'Note',  -- Note, Complaint, Request, Compliment, Incident
    subject VARCHAR(200),
    message TEXT NOT NULL,
    priority VARCHAR(20) DEFAULT 'Normal',  -- Low, Normal, High, Urgent
    status VARCHAR(20) DEFAULT 'Open',  -- Open, InProgress, Resolved, Closed
    assignedto VARCHAR(200),
    resolvedby VARCHAR(200),
    resolvedat TIMESTAMPTZ,
    createdby VARCHAR(450),
    createdat TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updatedat TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS ix_hotelguestcomm_farm ON hotelguestcommunications(farmid);
CREATE INDEX IF NOT EXISTS ix_hotelguestcomm_guest ON hotelguestcommunications(farmid, hotelguestid);

-- 4. Guest requests (wake-up calls, extra towels, etc.)
CREATE TABLE IF NOT EXISTS hotelguestrequests (
    hotelguestrequestid SERIAL PRIMARY KEY,
    farmid TEXT NOT NULL,
    hotelbookingid INT,
    hotelroomid INT,
    requesttype VARCHAR(50) NOT NULL,  -- WakeUpCall, ExtraTowels, RoomService, Maintenance, Transport, Other
    description TEXT,
    scheduledtime TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'Pending',  -- Pending, InProgress, Completed, Cancelled
    assignedto VARCHAR(200),
    completedby VARCHAR(200),
    completedat TIMESTAMPTZ,
    notes TEXT,
    createdby VARCHAR(450),
    createdat TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_hotelguestreq_farm ON hotelguestrequests(farmid);
CREATE INDEX IF NOT EXISTS ix_hotelguestreq_status ON hotelguestrequests(farmid, status);

-- 5. Lost and found register
CREATE TABLE IF NOT EXISTS hotellostandfound (
    hotellostandfoundid SERIAL PRIMARY KEY,
    farmid TEXT NOT NULL,
    hotelroomid INT,
    hotelbookingid INT,
    hotelguestid INT,
    itemdescription VARCHAR(500) NOT NULL,
    founddate DATE NOT NULL DEFAULT CURRENT_DATE,
    foundby VARCHAR(200),
    foundlocation VARCHAR(200),
    category VARCHAR(50) DEFAULT 'Other',  -- Electronics, Clothing, Documents, Jewelry, Personal, Other
    status VARCHAR(20) NOT NULL DEFAULT 'Found',  -- Found, Claimed, Disposed, Stored
    claimedby VARCHAR(200),
    claimedat TIMESTAMPTZ,
    storagelocation VARCHAR(200),
    notes TEXT,
    createdby VARCHAR(450),
    createdat TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_hotellostfound_farm ON hotellostandfound(farmid);

-- 6. Room flags (DND, special instructions, late checkout)
ALTER TABLE hotelrooms ADD COLUMN IF NOT EXISTS flags JSONB DEFAULT '{}';
-- flags: { "dnd": true, "lateCheckout": "14:00", "vipTreatment": true, "specialInstructions": "..." }

-- 7. Housekeeping schedule (daily roster)
CREATE TABLE IF NOT EXISTS hotelhousekeepingschedule (
    hotelschedid SERIAL PRIMARY KEY,
    farmid TEXT NOT NULL,
    scheduledate DATE NOT NULL,
    hotelroomid INT NOT NULL,
    assignedto VARCHAR(200),
    tasktype VARCHAR(30) NOT NULL DEFAULT 'Daily',  -- Daily, DeepClean, Turndown, Checkout
    priority VARCHAR(20) DEFAULT 'Normal',
    status VARCHAR(20) NOT NULL DEFAULT 'Scheduled',  -- Scheduled, InProgress, Completed, Skipped
    starttime TIMESTAMPTZ,
    endtime TIMESTAMPTZ,
    notes TEXT,
    createdby VARCHAR(450),
    createdat TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_hotelschedhk_farm_date ON hotelhousekeepingschedule(farmid, scheduledate);
CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelschedhk_room_date ON hotelhousekeepingschedule(farmid, hotelroomid, scheduledate, tasktype);

-- 8. Shift handover notes
CREATE TABLE IF NOT EXISTS hotelshifthandovers (
    hotelshifthandoverid SERIAL PRIMARY KEY,
    farmid TEXT NOT NULL,
    shiftdate DATE NOT NULL DEFAULT CURRENT_DATE,
    shifttype VARCHAR(20) NOT NULL DEFAULT 'Night',  -- Morning, Afternoon, Night
    handoverby VARCHAR(200) NOT NULL,
    receivedby VARCHAR(200),
    keymessages TEXT,
    pendingitems TEXT,
    vipguests TEXT,
    incidents TEXT,
    cashbalance NUMERIC(12,2),
    status VARCHAR(20) NOT NULL DEFAULT 'Draft',  -- Draft, Submitted, Acknowledged
    acknowledgedat TIMESTAMPTZ,
    createdat TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_hotelshifthandover_farm ON hotelshifthandovers(farmid, shiftdate DESC);

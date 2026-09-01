-- Migration 211: Hotel Composite Indexes for query performance
-- Applied: 2026-08-26

-- hotelbookings: status filter, calendar date range queries
CREATE INDEX IF NOT EXISTS ix_hotelbookings_farm_status ON hotelbookings(farmid, status);
CREATE INDEX IF NOT EXISTS ix_hotelbookings_farm_checkin ON hotelbookings(farmid, checkindate);
CREATE INDEX IF NOT EXISTS ix_hotelbookings_farm_checkout ON hotelbookings(farmid, checkoutdate);

-- hotelrooms: status queries (dashboard, availability)
CREATE INDEX IF NOT EXISTS ix_hotelrooms_farm_status ON hotelrooms(farmid, status);

-- hotelpayments: date-sorted lists
CREATE INDEX IF NOT EXISTS ix_hotelpayments_farm_date ON hotelpayments(farmid, paymentdate DESC);

-- hotelexpenses: date-sorted lists
CREATE INDEX IF NOT EXISTS ix_hotelexpenses_farm_date ON hotelexpenses(farmid, expensedate DESC);

-- hotelstaycharges: booking lookups + date for idempotent night audit
CREATE INDEX IF NOT EXISTS ix_hotelstaycharges_farm_booking ON hotelstaycharges(farmid, hotelbookingid);
CREATE INDEX IF NOT EXISTS ix_hotelstaycharges_farm_date ON hotelstaycharges(farmid, chargedate DESC);

-- hotelhousekeepingtasks: status filter
CREATE INDEX IF NOT EXISTS ix_hotelhousekeeping_farm_status ON hotelhousekeepingtasks(farmid, status);

-- hotelmaintenancerequests: status filter
CREATE INDEX IF NOT EXISTS ix_hotelmaintenance_farm_status ON hotelmaintenancerequests(farmid, status);

-- hotelcheckins/checkouts: date queries for night audit
CREATE INDEX IF NOT EXISTS ix_hotelcheckins_farm_time ON hotelcheckins(farmid, checkintime DESC);
CREATE INDEX IF NOT EXISTS ix_hotelcheckouts_farm_time ON hotelcheckouts(farmid, checkouttime DESC);

-- =============================================================================
-- 339_RestaurantWaitlistStatsFix.postgres.sql
--
-- sprestaurant_waitlist_stats (219) failed on every call with
--   42804: structure of query does not match function result type
-- because since PostgreSQL 14 EXTRACT(EPOCH FROM interval) returns NUMERIC,
-- while the function declares avg_wait_mins / longest_wait_mins as
-- DOUBLE PRECISION. The Restaurant dashboard swallowed the error, so its
-- Waitlist panel never showed. Same signature, same columns, same order
-- (the C# reader in RestaurantReservationService reads by ordinal) -- only
-- explicit casts added. Idempotent: CREATE OR REPLACE with an unchanged
-- RETURNS TABLE.
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_waitlist_stats(p_farmid TEXT)
RETURNS TABLE (
    waiting_count BIGINT, notified_count BIGINT,
    avg_wait_mins DOUBLE PRECISION, longest_wait_mins DOUBLE PRECISION,
    total_covers BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) FILTER (WHERE w.status = 'Waiting')::BIGINT,
        COUNT(*) FILTER (WHERE w.status = 'Notified')::BIGINT,
        (AVG(EXTRACT(EPOCH FROM (NOW() - w.createdat)) / 60.0) FILTER (WHERE w.status IN ('Waiting','Notified')))::DOUBLE PRECISION,
        (MAX(EXTRACT(EPOCH FROM (NOW() - w.createdat)) / 60.0) FILTER (WHERE w.status IN ('Waiting','Notified')))::DOUBLE PRECISION,
        COALESCE(SUM(w.partysize) FILTER (WHERE w.status IN ('Waiting','Notified')), 0)::BIGINT
    FROM restaurantwaitlist w
    WHERE w.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

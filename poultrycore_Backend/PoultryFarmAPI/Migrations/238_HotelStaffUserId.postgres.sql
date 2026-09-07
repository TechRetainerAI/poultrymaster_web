-- =============================================================================
-- Migration 238: Add UserId to HotelStaff  (PostgreSQL)
-- =============================================================================
-- Links hotel staff records to aspnetusers for login access.
-- =============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'hotelstaff'
          AND column_name  = 'userid'
    ) THEN
        ALTER TABLE public.hotelstaff ADD COLUMN userid character varying(450);
    END IF;
END $$;

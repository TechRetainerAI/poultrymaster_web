-- Migration 365: Add student extension fields to Generic customers.
--
-- These are nullable columns on the existing GenericCustomers table, only
-- populated when the business is a school/training centre. Keeping them on the
-- same table avoids a separate entity and a JOIN on every customer query.
--
-- Idempotent: safe to run multiple times.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'genericcustomers' AND column_name = 'dateofbirth') THEN
        ALTER TABLE genericcustomers ADD COLUMN dateofbirth DATE NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'genericcustomers' AND column_name = 'admissionnumber') THEN
        ALTER TABLE genericcustomers ADD COLUMN admissionnumber VARCHAR(50) NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'genericcustomers' AND column_name = 'classorgrade') THEN
        ALTER TABLE genericcustomers ADD COLUMN classorgrade VARCHAR(100) NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'genericcustomers' AND column_name = 'guardianname') THEN
        ALTER TABLE genericcustomers ADD COLUMN guardianname VARCHAR(200) NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'genericcustomers' AND column_name = 'guardianphone') THEN
        ALTER TABLE genericcustomers ADD COLUMN guardianphone VARCHAR(50) NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'genericcustomers' AND column_name = 'guardianemail') THEN
        ALTER TABLE genericcustomers ADD COLUMN guardianemail VARCHAR(150) NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'genericcustomers' AND column_name = 'enrollmentdate') THEN
        ALTER TABLE genericcustomers ADD COLUMN enrollmentdate DATE NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'genericcustomers' AND column_name = 'gender') THEN
        ALTER TABLE genericcustomers ADD COLUMN gender VARCHAR(20) NULL;
    END IF;

    -- Index for class lookup
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_genericcustomers_class') THEN
        CREATE INDEX ix_genericcustomers_class ON genericcustomers (farmid, classorgrade) WHERE classorgrade IS NOT NULL;
    END IF;
END $$;

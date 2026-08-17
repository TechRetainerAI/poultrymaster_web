-- =============================================================================
-- 206 (PostgreSQL): the egg product is measured in EGGS, not crates.
--
-- Every egg quantity in the system is a piece count: production records count
-- eggs, and the sales form converts crates x 30 + loose into pieces before
-- saving. The egg product was nevertheless created with Unit = 'Crate', so
-- /poultry-inventory rendered "Eggs | Crate | 45,331" — the label and the number
-- disagreeing by a factor of 30. Unit price on every egg product is 0, so
-- relabelling carries no pricing consequence.
--
-- Crates remain how the farm thinks: the inventory page now shows the crate
-- equivalent (at 30/crate) beside the egg count, the same way the Egg Stock
-- Balance report already does.
-- =============================================================================
BEGIN;

SELECT 'BEFORE' AS phase, poultryproductid, farmid, name, unit, unitprice
FROM   poultryproducts
WHERE  COALESCE(israweggproduct,FALSE) = TRUE OR name IN ('Eggs','Chicken Eggs')
ORDER  BY farmid;

-- 1. Existing egg products.
UPDATE poultryproducts
SET    unit = 'Egg', updateddate = NOW()
WHERE  (COALESCE(israweggproduct,FALSE) = TRUE OR name IN ('Eggs','Chicken Eggs'))
  AND  unit = 'Crate';

-- 2. The three functions that CREATE the egg product when a farm has none.
--    Each carries exactly one 'Crate' literal, in that INSERT. Rewriting each
--    function from its own definition keeps every other line byte-identical.
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid, pg_get_functiondef(p.oid) AS def
        FROM   pg_proc p
        WHERE  p.pronamespace = 'public'::regnamespace
          AND  p.prosrc ILIKE '%''Crate''%'
    LOOP
        EXECUTE replace(r.def, '''Crate''', '''Egg''');
    END LOOP;
END $$;

SELECT 'AFTER' AS phase, poultryproductid, farmid, name, unit, unitprice
FROM   poultryproducts
WHERE  COALESCE(israweggproduct,FALSE) = TRUE OR name IN ('Eggs','Chicken Eggs')
ORDER  BY farmid;

SELECT 'functions still saying Crate' AS check, count(*)
FROM   pg_proc p
WHERE  p.pronamespace = 'public'::regnamespace AND p.prosrc ILIKE '%''Crate''%';

COMMIT;

-- =============================================================================
-- 206_EggProductUnitIsEggsNotCrates.sql
--
-- Problem
-- -------
-- Every egg quantity in the system is a PIECE count. Production records count
-- individual eggs; the sales form enters crates x 30 + loose and saves the piece
-- count (see migration 124's note); the stock ledger carries pieces. But the egg
-- product has always been created with Unit = N'Crate', so /poultry-inventory
-- rendered the egg row as "Eggs | Crate | 45,331" — label and number disagreeing
-- by a factor of 30.
--
-- The Egg Stock Balance report sidesteps this by reporting eggs, crates and loose
-- as separate columns; the inventory page had no such escape.
--
-- Fix
-- ---
--   1. Relabel existing egg products from 'Crate' to 'Egg'.
--   2. Fix the five procs that CREATE the egg product when a farm has none, so
--      new farms are not born with the wrong unit. The proc bodies are otherwise
--      untouched — this only changes the literal in the INSERT.
--
-- Unit price on every egg product is 0, so relabelling carries no pricing
-- consequence. Crates remain how the farm thinks: /poultry-inventory now shows
-- the crate equivalent (30/crate) beneath the egg count.
--
-- Idempotent: the UPDATE is filtered on the old value and the procs are
-- CREATE OR ALTER.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Existing egg products.
-- -----------------------------------------------------------------------------
UPDATE dbo.PoultryProducts
SET    Unit = N'Egg', UpdatedDate = SYSUTCDATETIME()
WHERE  (ISNULL(IsRawEggProduct,0) = 1 OR Name IN (N'Eggs', N'Chicken Eggs'))
  AND  Unit = N'Crate';

PRINT CONCAT(N'206: relabelled ', @@ROWCOUNT, N' egg product(s) from Crate to Egg.');
GO

-- -----------------------------------------------------------------------------
-- 2. Creation sites. Each of these auto-creates the egg product when a farm has
--    none; all five carried N'Crate'. Only that literal changes here — but since
--    these are stored procedures, the whole body must be restated. Rather than
--    duplicate five large procs, patch the literal in place: each proc's INSERT
--    is identical, so a targeted definition rewrite is safe and keeps every
--    other line byte-identical to whichever migration last defined it.
--
--    Affected: spPoultryProduct_EnsureDefaultEgg (129), spPoultryEggStock_Sync
--    (131 -> 179 -> 198), spPoultryEggStock_SyncForSale (139).
-- -----------------------------------------------------------------------------
DECLARE @name SYSNAME, @def NVARCHAR(MAX), @newdef NVARCHAR(MAX), @fixed INT = 0;

DECLARE unit_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT o.name, m.definition
    FROM   sys.sql_modules m
    JOIN   sys.objects o ON o.object_id = m.object_id
    WHERE  o.type = 'P'
      AND  m.definition LIKE N'%N''Eggs'', N''Crate''%';

OPEN unit_cursor;
FETCH NEXT FROM unit_cursor INTO @name, @def;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- Only the product-creation literal, not any other use of the word.
    SET @newdef = REPLACE(@def, N'N''Eggs'', N''Crate''', N'N''Eggs'', N''Egg''');
    -- Re-issue as ALTER so permissions and the object id survive.
    SET @newdef = STUFF(@newdef, 1, CHARINDEX(N'PROCEDURE', @newdef) - 1, N'ALTER ');
    EXEC sp_executesql @newdef;
    SET @fixed = @fixed + 1;
    FETCH NEXT FROM unit_cursor INTO @name, @def;
END
CLOSE unit_cursor; DEALLOCATE unit_cursor;

PRINT CONCAT(N'206: patched ', @fixed, N' procedure(s) that created the egg product as Crate.');
GO

PRINT N'206_EggProductUnitIsEggsNotCrates.sql complete.';
GO

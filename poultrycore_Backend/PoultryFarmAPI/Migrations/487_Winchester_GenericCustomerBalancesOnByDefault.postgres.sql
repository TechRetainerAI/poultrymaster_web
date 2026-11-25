-- =============================================================================
-- 487_Winchester_GenericCustomerBalancesOnByDefault.postgres.sql
--
-- Problem: on a Generic business, "Customer balances" was not ticked by default
-- on Business Features, so Customer Balances was hidden from the menu. On
-- Poultry the page is always there.
--
-- Change (new businesses and businesses that never saved their features):
--   * genericmodulesettings.enablecustomerbalances defaults to TRUE.
--   * spgenericmodulesettings_get: the defaults it makes up for a business with
--     no saved row have Customer balances ON.
-- The web's recommended defaults (lib/generic/recommended-modules.ts) match.
-- The setup wizard's template is fixed in 490.
--
-- 24 Nov (rewritten): spgenericmodulesettings_get is also redefined by
-- 486_Gyimah_GenericProjectBudgetsMilestones (adds enableprojects). The first
-- version of this file replaced the whole function with the 13-column shape,
-- which (a) undid nothing on dev only because Gyimah's ran later and put
-- Customer balances back to FALSE, and (b) on a database that runs Gyimah's 486
-- first would FAIL ("cannot change return type"). So this file now patches the
-- LIVE body instead: only the made-up enablecustomerbalances value changes,
-- whatever columns the function has. Can run twice. No BEGIN/COMMIT.
-- =============================================================================

ALTER TABLE genericmodulesettings ALTER COLUMN enablecustomerbalances SET DEFAULT TRUE;

DO $patch$
DECLARE
    v_def text;
    -- The made-up row: products, inventory, stock adj., internal use, purchases,
    -- subscriptions, invoices, CUSTOMER BALANCES, ... (same order in both shapes).
    v_old text := 'SELECT p_farmid, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE,';
    v_new text := 'SELECT p_farmid, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, TRUE /* 487: customer balances */,';
BEGIN
    v_def := pg_get_functiondef('public.spgenericmodulesettings_get(text)'::regprocedure);
    IF position('487:' IN v_def) = 0 THEN
        IF position(v_old IN v_def) = 0 THEN
            IF position('SELECT p_farmid, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, TRUE,' IN v_def) > 0 THEN
                RETURN;   -- already on (an earlier version of this file)
            END IF;
            RAISE EXCEPTION '487: spgenericmodulesettings_get is not the expected shape (made-up defaults row).';
        END IF;
        EXECUTE replace(v_def, v_old, v_new);
    END IF;
END
$patch$;

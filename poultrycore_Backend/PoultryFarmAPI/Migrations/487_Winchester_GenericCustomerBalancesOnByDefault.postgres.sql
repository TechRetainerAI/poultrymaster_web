-- =============================================================================
-- 487_Winchester_GenericCustomerBalancesOnByDefault.postgres.sql
--
-- Problem: on a Generic business, "Customer balances" was not ticked by default
-- on Business Features, so Customer Balances and Customer Payments were hidden
-- and the server refused to record customer payments (RequireGenericModule ->
-- 403) until someone found the switch. On Poultry the page is always there.
--
-- Change (new businesses and businesses that never saved their features):
--   * genericmodulesettings.enablecustomerbalances defaults to TRUE.
--   * spgenericmodulesettings_get: the defaults it synthesises for a business
--     with no saved row now have Customer balances ON.
-- Businesses that already saved their features keep what they saved.
-- The web's recommended defaults (lib/generic/recommended-modules.ts) match.
--
-- Can run twice. No BEGIN/COMMIT (RunMigration wraps the file).
-- =============================================================================

ALTER TABLE genericmodulesettings ALTER COLUMN enablecustomerbalances SET DEFAULT TRUE;

-- Same columns and order as before; only the synthesised enablecustomerbalances
-- (9th column) changes from FALSE to TRUE.
CREATE OR REPLACE FUNCTION public.spgenericmodulesettings_get(p_farmid text)
 RETURNS TABLE(farmid text, enableproducts boolean, enableinventory boolean, enablestockadjustments boolean, enableinternaluse boolean, enablepurchases boolean, enablesubscriptions boolean, enableinvoices boolean, enablecustomerbalances boolean, enablestaffpayments boolean, enablecashaccounts boolean, enablerecurringexpenses boolean, enablesupplierbalances boolean)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT s.farmid::text, s.enableproducts, s.enableinventory, s.enablestockadjustments,
           s.enableinternaluse, s.enablepurchases, s.enablesubscriptions, s.enableinvoices,
           s.enablecustomerbalances, s.enablestaffpayments, s.enablecashaccounts,
           s.enablerecurringexpenses, s.enablesupplierbalances
    FROM   genericmodulesettings s
    WHERE  s.farmid = p_farmid
    UNION ALL
    SELECT p_farmid, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, TRUE, TRUE, TRUE,
           TRUE, TRUE
    WHERE  NOT EXISTS (SELECT 1 FROM genericmodulesettings s2 WHERE s2.farmid = p_farmid)
    LIMIT  1;
$function$;

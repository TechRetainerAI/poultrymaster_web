-- =============================================================================
-- 490_Winchester_GenericTemplateCustomerBalancesOn.postgres.sql
--
-- Found when cross-checking 487 (Customer balances ON by default) against
-- Poultry, where Customer Balances is always there.
--
-- 487 changed the column default and the made-up defaults, but a new Generic
-- business does not use either: the setup wizard applies a business template
-- (spgenericbusinesstemplate_apply, via _apply_extended), and that wrote
-- enablecustomerbalances = "is this a subscription business". So every shop /
-- general business set up through the wizard got Customer Balances switched OFF
-- and hidden from the menu. On dev that is exactly the 5 businesses that have it
-- off (all set up 28 Oct - 16 Nov, with Invoices and Subscriptions off as the
-- template leaves them).
--
-- Change:
--   * the template now turns Customer balances ON for every business type
--     (Invoices and Subscriptions still follow the template);
--   * businesses that have it off are switched on, once. It only shows the
--     Customer Balances page; no data changes. It can be switched off again in
--     Business Features.
--
-- Patched in the live body; skipped when already applied. No BEGIN/COMMIT.
-- =============================================================================

DO $patch$
DECLARE
    v_def text;
    v_old text := 'v_isSub, v_isSub, v_isSub,';
BEGIN
    v_def := pg_get_functiondef('public.spgenericbusinesstemplate_apply(text,text,text,text)'::regprocedure);
    IF position('490:' IN v_def) = 0 THEN
        IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
            RAISE EXCEPTION '490: spgenericbusinesstemplate_apply is not the expected shape (module flags marker).';
        END IF;
        -- Positions: enablesubscriptions, enableinvoices, enablecustomerbalances.
        EXECUTE replace(v_def, v_old,
            'v_isSub, v_isSub, TRUE,   -- 490: customer balances on for every template (as Poultry)');
    END IF;
END
$patch$;

UPDATE genericmodulesettings
SET    enablecustomerbalances = TRUE,
       updatedat = (now() at time zone 'utc')
WHERE  enablecustomerbalances = FALSE;

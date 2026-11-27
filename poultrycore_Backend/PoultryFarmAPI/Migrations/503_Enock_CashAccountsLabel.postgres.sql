-- =============================================================================
-- 503_Enock_CashAccountsLabel: "Cash & Accounts" is called "Cash Accounts".
-- =============================================================================
-- The menus and pages were renamed (no "&"); the permission catalog shown on
-- the roles screen still said "Cash & Accounts" for Poultry, Water, Generic and
-- Livestock (seeded by 199 / 461). Label text only; idempotent.
-- =============================================================================

UPDATE public.iampermissions
SET    resourcelabel = 'Cash Accounts'
WHERE  resourcelabel = 'Cash & Accounts';

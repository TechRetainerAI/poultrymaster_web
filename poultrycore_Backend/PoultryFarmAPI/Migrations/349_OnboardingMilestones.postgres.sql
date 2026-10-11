-- 349_OnboardingMilestones.postgres.sql
-- PROMPT 4 OF 7 — Onboarding milestones, setup completion, activation input.
--
-- The milestone CATALOG is configuration (onboardingmilestones): which
-- milestones apply per CompanyFamily, optionally overridden per Generic
-- BusinessTemplate (a template row set REPLACES the family defaults), with
-- weight/required/order. Adding a future template is config rows only.
--
-- Milestone DETECTION is set-based and uses the real workflows: the
-- platform_milestone_facts view unions "this company has at least one row in
-- the authoritative table" probes with the normalized activity events, so
-- historical customers are detected correctly even where runtime events
-- predate Prompt 1. Nothing fictional: every code below maps to an existing
-- feature's table.

CREATE TABLE IF NOT EXISTS onboardingmilestones (
    id                   serial PRIMARY KEY,
    companyfamily        text NOT NULL,          -- Poultry|Water|Hotel|Restaurant|Generic
    businesstemplatecode text NULL,              -- NULL = family default set
    milestonecode        text NOT NULL,
    title                text NOT NULL,
    weight               int NOT NULL DEFAULT 1,
    required             boolean NOT NULL DEFAULT false,  -- "essential setup" for activation
    sortorder            int NOT NULL DEFAULT 0,
    isactive             boolean NOT NULL DEFAULT true
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_onboardingmilestones
    ON onboardingmilestones (companyfamily, coalesce(businesstemplatecode, ''), milestonecode);

-- Idempotent seed (safe to re-run).
INSERT INTO onboardingmilestones (companyfamily, businesstemplatecode, milestonecode, title, weight, required, sortorder)
VALUES
-- Poultry
('Poultry', NULL, 'CompanyCreated',     'Company created',            1, true,  1),
('Poultry', NULL, 'FarmSetupCompleted', 'Initial farm setup completed', 2, false, 2),
('Poultry', NULL, 'HouseCreated',       'House/pen created',          2, false, 3),
('Poultry', NULL, 'FlockCreated',       'Flock created',              2, true,  4),
('Poultry', NULL, 'BatchCreated',       'Batch created',              1, false, 5),
('Poultry', NULL, 'CashAccountSetup',   'Cash account setup',         1, false, 6),
('Poultry', NULL, 'FirstProduction',    'First production record',    2, false, 7),
('Poultry', NULL, 'FirstSale',          'First sale',                 2, false, 8),
('Poultry', NULL, 'FirstPayment',       'First payment',              1, false, 9),
('Poultry', NULL, 'FirstDailyClosing',  'First daily closing',        1, false, 10),
-- Water
('Water', NULL, 'CompanyCreated',      'Company created',             1, true,  1),
('Water', NULL, 'ProductSetup',        'Product setup',               2, true,  2),
('Water', NULL, 'ProductionLineSetup', 'Production line setup',       2, false, 3),
('Water', NULL, 'FirstProduction',     'First production',            2, false, 4),
('Water', NULL, 'FirstSale',           'First sale',                  2, false, 5),
('Water', NULL, 'FirstDriverReturn',   'First driver return',         1, false, 6),
('Water', NULL, 'FirstPayment',        'First customer payment',      1, false, 7),
('Water', NULL, 'FirstDailyClosing',   'First daily closing',         1, false, 8),
-- Hotel
('Hotel', NULL, 'CompanyCreated',     'Company created',              1, true,  1),
('Hotel', NULL, 'RoomTypeSetup',      'Room types configured',        2, true,  2),
('Hotel', NULL, 'RoomSetup',          'Rooms created',                2, true,  3),
('Hotel', NULL, 'FirstBooking',       'First booking',                2, false, 4),
('Hotel', NULL, 'FirstCheckIn',       'First check-in',               2, false, 5),
('Hotel', NULL, 'FirstPayment',       'First customer payment',       1, false, 6),
('Hotel', NULL, 'FirstDailyClosing',  'First daily closing',          1, false, 7),
-- Restaurant
('Restaurant', NULL, 'CompanyCreated',    'Company created',          1, true,  1),
('Restaurant', NULL, 'MenuSetup',         'Menu items created',       2, true,  2),
('Restaurant', NULL, 'FloorTableSetup',   'Floors/tables configured', 1, false, 3),
('Restaurant', NULL, 'FirstOrder',        'First order',              2, false, 4),
('Restaurant', NULL, 'FirstPayment',      'First customer payment',   1, false, 5),
('Restaurant', NULL, 'FirstDailyClosing', 'First daily closing',      1, false, 6),
-- Generic (family default)
('Generic', NULL, 'CompanyCreated',    'Company created',             1, true,  1),
('Generic', NULL, 'ProfileSetup',      'Business profile setup',      2, true,  2),
('Generic', NULL, 'CashAccountSetup',  'Cash account setup',          1, false, 3),
('Generic', NULL, 'FirstCustomer',     'First customer created',      1, false, 4),
('Generic', NULL, 'FirstSale',         'First sale',                  2, false, 5),
('Generic', NULL, 'FirstPayment',      'First customer payment',      1, false, 6),
('Generic', NULL, 'FirstDailyClosing', 'First daily closing',         1, false, 7),
-- Generic template overrides (REPLACE the family set for that template)
('Generic', 'School', 'CompanyCreated',   'Company created',          1, true,  1),
('Generic', 'School', 'ProfileSetup',     'School profile setup',     2, true,  2),
('Generic', 'School', 'FirstCustomer',    'First student setup',      2, false, 3),
('Generic', 'School', 'FirstPayment',     'First fee payment',        2, false, 4),
('Generic', 'School', 'FirstDailyClosing','First daily closing',      1, false, 5),
('Generic', 'Gym', 'CompanyCreated',     'Company created',           1, true,  1),
('Generic', 'Gym', 'ProfileSetup',       'Gym profile setup',         2, true,  2),
('Generic', 'Gym', 'FirstCustomer',      'First member',              2, false, 3),
('Generic', 'Gym', 'FirstSubscription',  'First subscription',        2, false, 4),
('Generic', 'Gym', 'FirstPayment',       'First subscription payment',1, false, 5)
ON CONFLICT (companyfamily, coalesce(businesstemplatecode, ''), milestonecode) DO NOTHING;

-- ============================================================
-- Milestone facts: which companies have completed which milestone,
-- detected from the authoritative tables (+ normalized events for
-- workflow-completion milestones that have no single table).
-- ============================================================
CREATE OR REPLACE VIEW platform_milestone_facts AS
    SELECT farmid::text AS companyid, 'CompanyCreated' AS milestonecode
      FROM farms WHERE coalesce(isdeleted, false) = false
UNION ALL SELECT DISTINCT farmid::text, 'HouseCreated' FROM houses
UNION ALL SELECT DISTINCT farmid::text, 'FlockCreated' FROM flock
UNION ALL SELECT DISTINCT farmid::text, 'BatchCreated' FROM mainflockbatch
UNION ALL SELECT DISTINCT farmid::text, 'CashAccountSetup' FROM poultrycashaccounts
UNION ALL SELECT DISTINCT farmid::text, 'CashAccountSetup' FROM genericcashaccounts
UNION ALL SELECT DISTINCT farmid::text, 'FirstProduction' FROM eggproduction
UNION ALL SELECT DISTINCT farmid::text, 'FirstProduction' FROM productionrecords
UNION ALL SELECT DISTINCT farmid::text, 'FirstSale' FROM sale
UNION ALL SELECT DISTINCT farmid::text, 'FirstPayment' FROM poultrypayments
UNION ALL SELECT DISTINCT farmid::text, 'FirstDailyClosing' FROM poultrydailyclosings
UNION ALL SELECT DISTINCT farmid::text, 'ProductSetup' FROM waterproducts
UNION ALL SELECT DISTINCT farmid::text, 'ProductionLineSetup' FROM waterproductionlines
UNION ALL SELECT DISTINCT farmid::text, 'FirstProduction' FROM waterdailyproductions WHERE coalesce(isdeleted, false) = false
UNION ALL SELECT DISTINCT farmid::text, 'FirstSale' FROM watersales
UNION ALL SELECT DISTINCT farmid::text, 'FirstDriverReturn' FROM waterdriverreturns
UNION ALL SELECT DISTINCT farmid::text, 'FirstPayment' FROM waterpayments
UNION ALL SELECT DISTINCT farmid::text, 'FirstDailyClosing' FROM waterdailyclosings
UNION ALL SELECT DISTINCT farmid::text, 'RoomTypeSetup' FROM hotelroomtypes
UNION ALL SELECT DISTINCT farmid::text, 'RoomSetup' FROM hotelrooms
UNION ALL SELECT DISTINCT farmid::text, 'FirstBooking' FROM hotelbookings
UNION ALL SELECT DISTINCT farmid::text, 'FirstCheckIn' FROM hotelcheckins
UNION ALL SELECT DISTINCT farmid::text, 'FirstPayment' FROM hotelcustomerpayments
UNION ALL SELECT DISTINCT farmid::text, 'FirstDailyClosing' FROM hoteldailyclosings
UNION ALL SELECT DISTINCT farmid::text, 'MenuSetup' FROM restaurantmenuitems
UNION ALL SELECT DISTINCT farmid::text, 'FloorTableSetup' FROM restaurantfloors
UNION ALL SELECT DISTINCT farmid::text, 'FirstOrder' FROM restaurantorders
UNION ALL SELECT DISTINCT farmid::text, 'FirstPayment' FROM restaurantcustomerpayments
UNION ALL SELECT DISTINCT farmid::text, 'FirstDailyClosing' FROM restaurantdailyclosings
UNION ALL SELECT DISTINCT farmid::text, 'ProfileSetup' FROM genericcompanyprofiles
UNION ALL SELECT DISTINCT farmid::text, 'FirstCustomer' FROM genericcustomers
UNION ALL SELECT DISTINCT farmid::text, 'FirstSale' FROM genericsales WHERE coalesce(isdeleted, false) = false
UNION ALL SELECT DISTINCT farmid::text, 'FirstPayment' FROM genericcustomerpayments
UNION ALL SELECT DISTINCT farmid::text, 'FirstDailyClosing' FROM genericdailyclosings
UNION ALL SELECT DISTINCT farmid::text, 'FirstSubscription' FROM genericsubscriptions
-- Workflow-completion milestones detected from normalized events:
UNION ALL SELECT DISTINCT companyid, activitytype
      FROM platformactivityevents
     WHERE companyid IS NOT NULL
       AND activitytype IN ('FarmSetupCompleted', 'CompanySetupCompleted');

-- ============================================================
-- Which milestone set applies to a company: template override replaces the
-- family default when (and only when) override rows exist for that template.
-- ============================================================
CREATE OR REPLACE VIEW platform_company_milestones AS
WITH company AS (
    SELECT f.farmid::text AS companyid, f.type AS family,
           (SELECT nullif(p.genericbusinesstemplate, '')
              FROM genericcompanyprofiles p
             WHERE p.farmid = f.farmid
             ORDER BY p.genericcompanyprofileid DESC LIMIT 1) AS template
    FROM farms f
    WHERE coalesce(f.isdeleted, false) = false AND f.type IS DISTINCT FROM 'System'
)
SELECT c.companyid, c.family, c.template,
       m.milestonecode, m.title, m.weight, m.required, m.sortorder,
       EXISTS (SELECT 1 FROM platform_milestone_facts x
                WHERE x.companyid = c.companyid AND x.milestonecode = m.milestonecode) AS complete
FROM company c
JOIN onboardingmilestones m
  ON m.isactive
 AND m.companyfamily = c.family
 AND (
      (m.businesstemplatecode IS NOT NULL AND m.businesstemplatecode = c.template)
   OR (m.businesstemplatecode IS NULL AND NOT EXISTS (
          SELECT 1 FROM onboardingmilestones o
           WHERE o.isactive AND o.companyfamily = c.family
             AND o.businesstemplatecode = c.template))
 );

-- ============================================================
-- Per-company setup summary (set-based; one scan for all companies).
-- ============================================================
CREATE OR REPLACE FUNCTION platform_setup_summary()
RETURNS TABLE (
    companyid        text,
    totalweight      int,
    completedweight  int,
    setuppercent     int,
    requiredtotal    int,
    requiredcomplete int,
    missingtitles    text[]
)
LANGUAGE sql STABLE
AS $fn$
    SELECT m.companyid,
           sum(m.weight)::int,
           sum(m.weight) FILTER (WHERE m.complete)::int,
           CASE WHEN sum(m.weight) = 0 THEN 0
                ELSE round(100.0 * sum(m.weight) FILTER (WHERE m.complete) / sum(m.weight))::int END,
           count(*) FILTER (WHERE m.required)::int,
           count(*) FILTER (WHERE m.required AND m.complete)::int,
           coalesce(array_agg(m.title ORDER BY m.sortorder) FILTER (WHERE NOT m.complete), '{}')
    FROM platform_company_milestones m
    GROUP BY m.companyid;
$fn$;

-- 466: Livestock in the platform -- billing profile, onboarding milestones.
--
-- Needs 458-465 (reads livestock tables) and the platform migrations 329, 341
-- and 349. Safe to re-run: every insert is guarded per row, and the milestone
-- view is extended only if it does not already read livestock tables.
--
-- 1. BILLING. Livestock companies bill through LIVESTOCK_ANIMALS, counting the
--    animals alive in active groups (the head count every livestock page
--    shows). Until an admin decides real tiers and prices, every livestock
--    company qualifies as STARTER and NO price is seeded -- the engine then
--    reports "pricing not configured" instead of inventing a charge (the same
--    footing Hotel and Restaurant started on). Admins set tiers and prices in
--    the billing admin app; no code change is needed.
--    Code side: PlatformBillingRules.ResolveProfileCode("livestock") and the
--    ActiveAnimalCount branch in PlatformBillingService.MetricValueAsync.
--
-- 2. ONBOARDING. The "getting started" milestones for a Livestock company
--    (farms.type = 'Livestock'), detected from the livestock tables.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Billing
-- ---------------------------------------------------------------------------
INSERT INTO billingprofiles (code, name, metrictype, description)
SELECT 'LIVESTOCK_ANIMALS', 'Livestock — Active Animals', 'ActiveAnimalCount',
       'Animals alive across active groups; the same head count the livestock pages show. Billing reads, never writes.'
WHERE NOT EXISTS (SELECT 1 FROM billingprofiles WHERE code = 'LIVESTOCK_ANIMALS');

-- Starter for every count until an admin configures more -- a safe floor.
INSERT INTO billingtierrules (profilecode, tiercode, minvalue, maxvalue)
SELECT 'LIVESTOCK_ANIMALS', 'starter', 0, NULL
WHERE NOT EXISTS (SELECT 1 FROM billingtierrules WHERE profilecode = 'LIVESTOCK_ANIMALS');

CREATE OR REPLACE FUNCTION public.spplatformbilling_activeanimals(p_farmid text)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(SUM(GREATEST(fnlivestock_grouphead(g.groupid), 0)), 0)::numeric
      FROM livestockgroups g
     WHERE g.farmid = p_farmid AND g.status = 'Active' AND NOT g.isdeleted;
$$;

-- How the plan card reads (copy only, never amounts).
INSERT INTO pricingpresentationprofiles
    (billingprofilecode, businesstemplatecode, displayname, shortdescription, metricdisplayname, metricsingular, metricplural, sortorder)
SELECT 'LIVESTOCK_ANIMALS', NULL, 'Livestock Farm', 'Animals, breeding, feed, health and money, priced by your herd.',
       'Active Animals', 'animal', 'animals', 15
WHERE NOT EXISTS (SELECT 1 FROM pricingpresentationprofiles WHERE billingprofilecode = 'LIVESTOCK_ANIMALS' AND businesstemplatecode IS NULL);

INSERT INTO tierpresentations (presentationid, tiercode, headline, featurebullets, ismostpopular, ctatext, displayorder)
SELECT pp.id, 'starter', 'For livestock farms getting their records off paper.',
       E'Complete livestock management platform\nGroups, tagged animals & breeding\nDaily records: deaths, eggs, milk & feed\nFeed, health & vaccinations\nSales, expenses & cash accounts\nDaily closing, reports & audit logs',
       FALSE, 'Start free', 10
  FROM pricingpresentationprofiles pp
 WHERE pp.billingprofilecode = 'LIVESTOCK_ANIMALS' AND pp.businesstemplatecode IS NULL
   AND NOT EXISTS (SELECT 1 FROM tierpresentations t WHERE t.presentationid = pp.id AND t.tiercode = 'starter');

-- ---------------------------------------------------------------------------
-- 2. Onboarding milestones
-- ---------------------------------------------------------------------------
INSERT INTO onboardingmilestones (companyfamily, businesstemplatecode, milestonecode, title, weight, required, sortorder)
VALUES
('Livestock', NULL, 'CompanyCreated',    'Company created',          1, true,  1),
('Livestock', NULL, 'SpeciesChosen',     'Animals kept chosen',      2, true,  2),
('Livestock', NULL, 'HouseCreated',      'Pen created',              1, false, 3),
('Livestock', NULL, 'FlockCreated',      'Animal group created',     2, true,  4),
('Livestock', NULL, 'CashAccountSetup',  'Cash account setup',       1, false, 5),
('Livestock', NULL, 'FirstProduction',   'First daily record',       2, false, 6),
('Livestock', NULL, 'FirstSale',         'First sale',               2, false, 7),
('Livestock', NULL, 'FirstPayment',      'First customer payment',   1, false, 8),
('Livestock', NULL, 'FirstDailyClosing', 'First daily closing',      1, false, 9)
ON CONFLICT (companyfamily, coalesce(businesstemplatecode, ''), milestonecode) DO NOTHING;

-- Extend the milestone facts view with the livestock tables. Built from the
-- view's CURRENT definition, so nothing another migration added is lost.
DO $do$
DECLARE v_def text;
BEGIN
    v_def := pg_get_viewdef('platform_milestone_facts'::regclass, true);
    IF v_def ILIKE '%livestockgroups%' THEN
        RETURN;
    END IF;
    v_def := rtrim(btrim(v_def), ';');
    EXECUTE 'CREATE OR REPLACE VIEW platform_milestone_facts AS ' || v_def || $add$
UNION ALL SELECT DISTINCT farmid::text, 'SpeciesChosen' FROM livestockfarmspecies
UNION ALL SELECT DISTINCT farmid::text, 'HouseCreated' FROM livestockpens
UNION ALL SELECT DISTINCT farmid::text, 'FlockCreated' FROM livestockgroups WHERE NOT isdeleted
UNION ALL SELECT DISTINCT farmid::text, 'CashAccountSetup' FROM livestockcashaccounts
UNION ALL SELECT DISTINCT farmid::text, 'FirstProduction' FROM livestockproductionrecords WHERE NOT isdeleted
UNION ALL SELECT DISTINCT farmid::text, 'FirstSale' FROM livestocksales
UNION ALL SELECT DISTINCT farmid::text, 'FirstPayment' FROM livestockcustomerpayments
UNION ALL SELECT DISTINCT farmid::text, 'FirstDailyClosing' FROM livestockdailyclosings$add$;
END
$do$;

COMMIT;

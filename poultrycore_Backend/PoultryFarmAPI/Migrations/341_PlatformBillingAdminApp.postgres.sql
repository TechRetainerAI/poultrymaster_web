-- ============================================================================
-- 341: Platform billing ADMIN APP — water billing, pricing presentation,
--      discounts & promotions, account credits, enterprise contracts,
--      granular admin permissions (ADMIN APP spec, 2026-10-05).
--
-- Additive only. Changes commercial CONFIGURATION shape; it never touches
-- amounts on historical invoices (spec 38) and ships every new commercial
-- switch OFF or empty, for staff to configure through the admin app.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. WATER billing profile (spec 5/7): water bills by ACTIVE PRODUCTION LINES,
--    an operational fact, never an admin-typed number. The lines table itself
--    is water-module operational data (companies manage their own lines);
--    billing only READS it. Until a company records lines, the metric falls
--    back to the configured manual scale, exactly like today.
-- ----------------------------------------------------------------------------
INSERT INTO billingprofiles (code, name, metrictype, description)
SELECT 'WATER_PRODUCTION_LINES', 'Water — Production Lines', 'ActiveProductionLines',
       'Active production lines recorded by the water company itself; billing reads, never writes.'
WHERE NOT EXISTS (SELECT 1 FROM billingprofiles WHERE code = 'WATER_PRODUCTION_LINES');

CREATE TABLE IF NOT EXISTS waterproductionlines (
    id          bigserial PRIMARY KEY,
    farmid      varchar(450) NOT NULL,
    name        text NOT NULL,
    isactive    boolean NOT NULL DEFAULT TRUE,
    notes       text NULL,
    createdby   text NULL,
    createdat   timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updatedat   timestamp NULL
);
CREATE INDEX IF NOT EXISTS ix_waterproductionlines_farm ON waterproductionlines(farmid) WHERE isactive;

CREATE OR REPLACE FUNCTION spplatformbilling_activewaterlines(p_farmid text)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT COUNT(*)::numeric FROM waterproductionlines
     WHERE farmid = p_farmid AND isactive = TRUE;
$$;

-- Initial water tier rules (spec 5): Starter 0–1 line, Growth 2–3, Business 4+.
-- Thresholds are configuration — admins change them later without deploys.
INSERT INTO billingtierrules (profilecode, tiercode, minvalue, maxvalue, active)
SELECT v.p, v.t, v.lo, v.hi, TRUE
  FROM (VALUES ('WATER_PRODUCTION_LINES', 'starter',  0::numeric, 1::numeric),
               ('WATER_PRODUCTION_LINES', 'growth',   2::numeric, 3::numeric),
               ('WATER_PRODUCTION_LINES', 'business', 4::numeric, NULL::numeric)) AS v(p, t, lo, hi)
 WHERE NOT EXISTS (SELECT 1 FROM billingtierrules WHERE profilecode = 'WATER_PRODUCTION_LINES');

-- ----------------------------------------------------------------------------
-- 2. PRICING PRESENTATION (spec 11–16): how plan cards READ, per profile and
--    optionally per Generic template. Copy only — never amounts or tier math.
--    Template with no override falls back to its profile's presentation.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pricingpresentationprofiles (
    id                   bigserial PRIMARY KEY,
    billingprofilecode   text NOT NULL REFERENCES billingprofiles(code),
    businesstemplatecode text NULL,              -- NULL = the profile's default presentation
    displayname          text NOT NULL,          -- "Poultry Farm", "School"
    shortdescription     text NULL,
    metricdisplayname    text NULL,              -- "Active Birds"
    metricsingular       text NULL,              -- "bird"
    metricplural         text NULL,              -- "birds"
    sortorder            int  NOT NULL DEFAULT 100,
    active               boolean NOT NULL DEFAULT TRUE,
    updatedby            text NULL,
    updatedatutc         timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_presentation_profile_template
    ON pricingpresentationprofiles (billingprofilecode, COALESCE(businesstemplatecode, ''));

CREATE TABLE IF NOT EXISTS tierpresentations (
    id              bigserial PRIMARY KEY,
    presentationid  bigint NOT NULL REFERENCES pricingpresentationprofiles(id) ON DELETE CASCADE,
    tiercode        text NOT NULL REFERENCES platformtiers(code),
    headline        text NULL,
    description     text NULL,
    featurebullets  text NULL,                   -- one bullet per line
    badgetext       text NULL,
    ismostpopular   boolean NOT NULL DEFAULT FALSE,
    ctatext         text NULL,
    displayorder    int NOT NULL DEFAULT 100,
    UNIQUE (presentationid, tiercode)
);

-- Seed presentations: poultry (spec 13), water (spec 14), generic default,
-- School + Gym overrides (spec 15). Admin edits these without deploys.
INSERT INTO pricingpresentationprofiles
    (billingprofilecode, businesstemplatecode, displayname, shortdescription, metricdisplayname, metricsingular, metricplural, sortorder)
SELECT * FROM (VALUES
    ('POULTRY_BIRDS', NULL::text, 'Poultry Farm', 'Complete poultry management, priced by your flock.', 'Active Birds', 'bird', 'birds', 10),
    ('WATER_PRODUCTION_LINES', NULL, 'Water Production', 'Production to the last delivery, priced by production lines.', 'Active Production Lines', 'production line', 'production lines', 20),
    ('HOTEL_ROOMS', NULL, 'Hotel', 'Rooms, bookings and guest money in one system.', 'Rooms', 'room', 'rooms', 30),
    ('RESTAURANT_LOCATIONS', NULL, 'Restaurant', 'Orders, kitchen and cash for every location.', 'Locations', 'location', 'locations', 40),
    ('GENERIC_STANDARD', NULL, 'Business', 'The complete platform for your business.', 'Scale', 'unit', 'units', 50),
    ('GENERIC_STANDARD', 'School', 'School', 'For schools organizing students, fees and daily finances.', 'Scale', 'unit', 'units', 51),
    ('GENERIC_STANDARD', 'Gym', 'Gym / Fitness Centre', 'For gyms running members, sessions and payments.', 'Scale', 'unit', 'units', 52)
) AS v(p, t, d, s, m, ms, mp, o)
WHERE NOT EXISTS (SELECT 1 FROM pricingpresentationprofiles);

INSERT INTO tierpresentations (presentationid, tiercode, headline, featurebullets, ismostpopular, ctatext, displayorder)
SELECT pp.id, v.tier, v.head, v.bullets, v.popular, 'Start free', v.ord
  FROM (VALUES
    -- Poultry (spec 13)
    ('POULTRY_BIRDS', '', 'starter',  'For small farms getting their records off paper.',
     E'Complete poultry management platform\nProduction & flock records\nFeed, medication & inventory\nSales, expenses & cash accounts\nDaily closing, reports & audit logs', FALSE, 10),
    ('POULTRY_BIRDS', '', 'growth',   'For growing farms that run on their numbers.',
     E'Everything in Starter — same complete platform\nSized for flocks up to 5,000 birds\nProduction & flock records\nFeed, medication & inventory\nSales, expenses & cash accounts', TRUE, 20),
    ('POULTRY_BIRDS', '', 'business', 'For large operations with serious volume.',
     E'Everything in Growth — same complete platform\nNo upper limit on flock size\nProduction & flock records\nFeed, medication & inventory\nSales, expenses & cash accounts', FALSE, 30),
    ('POULTRY_BIRDS', '', 'enterprise', 'For groups running many companies.',
     E'Everything in Business\nMany companies, one consolidated bill\nBusiness Office — your organization HQ\nCustom contract terms', FALSE, 40),
    -- Water (spec 14)
    ('WATER_PRODUCTION_LINES', '', 'starter', 'For smaller water producers bringing production and distribution under control.',
     E'Water production records\nRaw materials & finished inventory\nSales & customer balances\nDrivers, routes & returns\nExpenses, cash & reporting', FALSE, 10),
    ('WATER_PRODUCTION_LINES', '', 'growth', 'For growing water businesses managing multiple production lines.',
     E'Everything in Starter — same complete platform\nSized for 2–3 production lines\nProduction batches & quality tests\nVehicle loading & route sales\nSupplier & payables tracking', TRUE, 20),
    ('WATER_PRODUCTION_LINES', '', 'business', 'For established producers running four or more lines.',
     E'Everything in Growth — same complete platform\nNo upper limit on production lines\nFull financial activity views\nMulti-vehicle distribution\nAudit logs across the business', FALSE, 30),
    ('WATER_PRODUCTION_LINES', '', 'enterprise', 'For groups running many companies.',
     E'Everything in Business\nMany companies, one consolidated bill\nBusiness Office — your organization HQ\nCustom contract terms', FALSE, 40),
    -- Generic default (spec 15/16 fallback)
    ('GENERIC_STANDARD', '', 'starter', 'For small businesses getting organized.',
     E'The complete platform — every feature included\nSales, expenses & cash accounts\nInventory & stock\nDaily closing, reports & audit logs', FALSE, 10),
    ('GENERIC_STANDARD', '', 'growth', 'For growing businesses that run on their numbers.',
     E'Everything in Starter — same complete platform\nTeam logins with roles\nCustomer balances & statements\nPhone, tablet & desktop', TRUE, 20),
    ('GENERIC_STANDARD', '', 'business', 'For established businesses with serious volume.',
     E'Everything in Growth — same complete platform\nNo scale limits\nFull financial activity views\nAudit logs across the business', FALSE, 30),
    ('GENERIC_STANDARD', '', 'enterprise', 'For groups running many companies.',
     E'Everything in Business\nMany companies, one consolidated bill\nBusiness Office — your organization HQ\nCustom contract terms', FALSE, 40),
    -- School override (spec 15)
    ('GENERIC_STANDARD', 'School', 'starter', 'For schools organizing students, fees and daily finances.',
     E'Student & class records\nFees & payments\nExpenses & cash accounts\nDaily closing & reports', FALSE, 10),
    ('GENERIC_STANDARD', 'School', 'growth', 'For growing schools with more students and staff.',
     E'Everything in Starter — same complete platform\nTeam logins for bursar & staff\nFee balances & statements\nPhone, tablet & desktop', TRUE, 20),
    -- Gym override (spec 15)
    ('GENERIC_STANDARD', 'Gym', 'starter', 'For gyms managing members, sessions and payments.',
     E'Member records & subscriptions\nSession & attendance tracking\nPayments & cash accounts\nDaily closing & reports', FALSE, 10),
    ('GENERIC_STANDARD', 'Gym', 'growth', 'For growing fitness centres with more members and staff.',
     E'Everything in Starter — same complete platform\nTeam logins with roles\nMember balances & statements\nPhone, tablet & desktop', TRUE, 20)
  ) AS v(profile, template, tier, head, bullets, popular, ord)
  JOIN pricingpresentationprofiles pp
    ON pp.billingprofilecode = v.profile AND COALESCE(pp.businesstemplatecode, '') = v.template
WHERE NOT EXISTS (SELECT 1 FROM tierpresentations);

-- ----------------------------------------------------------------------------
-- 3. AUTOMATIC multi-company discount rules gain the full configuration shape
--    (spec 18): name, optional max, type, market scope, dates, stacking.
-- ----------------------------------------------------------------------------
ALTER TABLE multicompanydiscountrules ADD COLUMN IF NOT EXISTS name         text;
ALTER TABLE multicompanydiscountrules ADD COLUMN IF NOT EXISTS maxcompanies int;
ALTER TABLE multicompanydiscountrules ADD COLUMN IF NOT EXISTS discounttype text NOT NULL DEFAULT 'Percentage';
ALTER TABLE multicompanydiscountrules ADD COLUMN IF NOT EXISTS marketcode   text;
ALTER TABLE multicompanydiscountrules ADD COLUMN IF NOT EXISTS stackable    boolean NOT NULL DEFAULT TRUE;
ALTER TABLE multicompanydiscountrules ADD COLUMN IF NOT EXISTS priority     int NOT NULL DEFAULT 0;
UPDATE multicompanydiscountrules SET name = mincompanies || '+ companies' WHERE name IS NULL;

-- ----------------------------------------------------------------------------
-- 4. SPECIAL DISCOUNTS (spec 21/22/24/25/28): organization-, company- or
--    profile-scoped, percentage or fixed, duration-limited, stackable with a
--    priority, reason REQUIRED, full who/when/why audit, revocable.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS platformdiscounts (
    id              bigserial PRIMARY KEY,
    accountid       bigint NOT NULL REFERENCES organizationbillingaccounts(id),
    name            text NOT NULL,
    discounttype    text NOT NULL DEFAULT 'Percentage',   -- Percentage | Fixed
    value           numeric(14,2) NOT NULL,
    scope           text NOT NULL DEFAULT 'Organization', -- Organization | Company | Profile
    farmid          text NULL,                            -- scope = Company
    profilecode     text NULL,                            -- scope = Profile
    startdate       date NOT NULL DEFAULT CURRENT_DATE,
    enddate         date NULL,
    durationperiods int NULL,                             -- N invoices; NULL = until enddate/forever
    stackable       boolean NOT NULL DEFAULT TRUE,
    priority        int NOT NULL DEFAULT 100,             -- lower applies first
    reason          text NOT NULL,
    internalnotes   text NULL,
    promotionid     bigint NULL,                          -- set when assigned from a promotion
    createdby       text NULL,
    createdatutc    timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    approvedby      text NULL,
    revokedby       text NULL,
    revokedatutc    timestamp NULL,
    active          boolean NOT NULL DEFAULT TRUE
);
CREATE INDEX IF NOT EXISTS ix_platformdiscounts_account ON platformdiscounts(accountid) WHERE active;

-- Which invoices a discount actually reduced (spec 25 "invoices remaining"
-- + 28 "invoices affected"). One row per discount per invoice.
CREATE TABLE IF NOT EXISTS platformdiscountapplications (
    id           bigserial PRIMARY KEY,
    discountid   bigint NOT NULL REFERENCES platformdiscounts(id),
    invoiceid    bigint NOT NULL REFERENCES platforminvoices(id),
    amount       numeric(14,2) NOT NULL,
    appliedatutc timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    UNIQUE (discountid, invoiceid)
);

-- ----------------------------------------------------------------------------
-- 5. PROMOTIONS (spec 20): defined centrally; assigning one to an organization
--    materializes a platformdiscounts row so ONE pipeline prices everything.
--    Customer-entered coupons come later; the model supports them now.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS platformpromotions (
    id               bigserial PRIMARY KEY,
    code             text NOT NULL UNIQUE,      -- LAUNCH20
    name             text NOT NULL,
    discounttype     text NOT NULL DEFAULT 'Percentage',
    value            numeric(14,2) NOT NULL,
    durationperiods  int NOT NULL DEFAULT 1,
    marketcode       text NULL,                 -- NULL = all markets
    profilecodes     text NULL,                 -- CSV; NULL = all profiles
    tiercodes        text NULL,                 -- CSV; NULL = all tiers
    newcustomersonly boolean NOT NULL DEFAULT FALSE,
    startdate        date NOT NULL DEFAULT CURRENT_DATE,
    enddate          date NULL,
    maxredemptions   int NULL,
    redemptions      int NOT NULL DEFAULT 0,
    stackable        boolean NOT NULL DEFAULT FALSE,
    active           boolean NOT NULL DEFAULT TRUE,
    createdby        text NULL,
    createdatutc     timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
CREATE TABLE IF NOT EXISTS platformpromotionredemptions (
    id           bigserial PRIMARY KEY,
    promotionid  bigint NOT NULL REFERENCES platformpromotions(id),
    accountid    bigint NOT NULL REFERENCES organizationbillingaccounts(id),
    discountid   bigint NULL REFERENCES platformdiscounts(id),
    redeemedby   text NULL,
    redeemedatutc timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    UNIQUE (promotionid, accountid)
);

-- ----------------------------------------------------------------------------
-- 6. ACCOUNT CREDITS (spec 26/27): money owed to the customer, in the account
--    currency, consumed by future invoices. A credit is NOT a discount.
--    Consumed credits are never deleted (the applications are the ledger).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS platformaccountcredits (
    id            bigserial PRIMARY KEY,
    accountid     bigint NOT NULL REFERENCES organizationbillingaccounts(id),
    amount        numeric(14,2) NOT NULL CHECK (amount > 0),
    currencycode  text NOT NULL,
    reason        text NOT NULL,
    internalnotes text NULL,
    reference     text NULL,
    expiresatutc  timestamp NULL,
    issuedby      text NULL,
    issuedatutc   timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    revokedby     text NULL,
    revokedatutc  timestamp NULL
);
CREATE INDEX IF NOT EXISTS ix_platformaccountcredits_account ON platformaccountcredits(accountid);

CREATE TABLE IF NOT EXISTS platformcreditapplications (
    id           bigserial PRIMARY KEY,
    creditid     bigint NOT NULL REFERENCES platformaccountcredits(id),
    invoiceid    bigint NOT NULL REFERENCES platforminvoices(id),
    amount       numeric(14,2) NOT NULL CHECK (amount > 0),
    appliedatutc timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
CREATE INDEX IF NOT EXISTS ix_platformcreditapplications_invoice ON platformcreditapplications(invoiceid);

-- Credits applied reduce what checkout collects, never the invoice's history.
ALTER TABLE platforminvoices ADD COLUMN IF NOT EXISTS creditapplied numeric(14,2) NOT NULL DEFAULT 0;

-- Per-discount snapshot on the invoice (spec 23/38): name + amount per line of
-- the discount breakdown, frozen at generation. Aggregate stays in
-- discountamount so nothing existing changes.
ALTER TABLE platforminvoices ADD COLUMN IF NOT EXISTS discountbreakdown text NULL;

-- ----------------------------------------------------------------------------
-- 7. ENTERPRISE CONTRACTS (spec 33/37): the commercial record. The numbers
--    themselves land on companybillingstates (customprice / participation
--    EnterpriseContract), which the engine already honors.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS enterprisecontracts (
    id                bigserial PRIMARY KEY,
    accountid         bigint NOT NULL REFERENCES organizationbillingaccounts(id),
    name              text NOT NULL,
    contractreference text NULL,
    billingfrequency  text NOT NULL DEFAULT 'monthly',
    effectivefrom     date NOT NULL DEFAULT CURRENT_DATE,
    effectiveto       date NULL,
    notes             text NULL,
    createdby         text NULL,
    approvedby        text NULL,
    createdatutc      timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    active            boolean NOT NULL DEFAULT TRUE
);

-- ----------------------------------------------------------------------------
-- 8. GRANULAR ADMIN PERMISSIONS (spec 29/30). SystemAdmin / PlatformOwner
--    keep implicit full access; everyone else needs explicit grants.
--    The approval threshold is configuration, not code.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS platformadminpermissions (
    userid       text NOT NULL,
    permission   text NOT NULL,     -- BillingAdmin.View / ManagePricing / ManageTierRules /
                                    -- ManagePresentations / ManageDiscountRules / AssignDiscount /
                                    -- IssueCredit / ManageEnterprisePricing / ApproveLargeDiscount
    grantedby    text NULL,
    grantedatutc timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    PRIMARY KEY (userid, permission)
);

INSERT INTO platformbillingsettings (key, value, description)
SELECT v.k, v.v, v.d FROM (VALUES
    ('discountapprovalthresholdpercent', '10',
     'Discounts above this percentage need the BillingAdmin.ApproveLargeDiscount permission (spec 30).'),
    ('multicompanyeligibility', 'BilledActive',
     'Which companies count toward the multi-company discount: BilledActive (default: active, priced companies only) | IncludeTrial.')
) AS v(k, v, d)
WHERE NOT EXISTS (SELECT 1 FROM platformbillingsettings WHERE key = v.k);

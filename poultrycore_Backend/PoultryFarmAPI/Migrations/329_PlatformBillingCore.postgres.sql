-- ============================================================================
-- 329_PlatformBillingCore.postgres.sql
--
-- Platform billing & subscription system, Phase A (introduce the generalized
-- model). Business-Office-level, multi-company, multi-market, multi-currency.
--
-- What exists today (inspected 2026-09-29, see the billing spec's Part 1):
--   * The Organization IS the owner's AspNetUsers row (BusinessOfficeName /
--     BusinessOfficeCurrency / BusinessOfficeCountry, OrganizationCode).
--   * Companies are rows in farms (type: Poultry|Water|Generic|Restaurant|
--     Hotel); a Generic company's template lives in
--     genericcompanyprofiles.genericbusinesstemplate.
--   * The only live pricing is the Poultry ladder in the Login API's
--     appsettings: <=2,000 birds GHS 500 / <=5,000 GHS 1,000 / above GHS
--     1,500 a month. Those exact values are seeded here as the Ghana price
--     book so nothing changes for existing customers.
--   * Paystack checkout is a one-time transaction with no webhook, no verify,
--     no server-side payment record and no enforcement, so there are no live
--     provider subscriptions to migrate or double-charge.
--
-- Phase A is ADDITIVE ONLY: no existing table is altered, nothing reads these
-- tables until the new services ship, and enforcement is seeded OFF.
--
-- Seeding policy (spec Parts 3.2, 8, 38): only commercially-live values are
-- seeded active — the Ghana Poultry ladder. Other markets (NG/US/INTL) and
-- profiles ship inactive/unpriced and surface as PricingNotConfigured rather
-- than inventing prices. Discount percentages are seeded but INACTIVE until
-- someone makes that commercial decision in admin.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Configuration: markets, tiers, profiles, qualification, price books
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS billingmarkets (
    code           text PRIMARY KEY,          -- GH, NG, US, INTL
    name           text NOT NULL,
    currencycode   text NOT NULL,             -- GHS, NGN, USD
    provider       text NOT NULL DEFAULT 'paystack',
    active         boolean NOT NULL DEFAULT FALSE,
    createdatutc   timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE TABLE IF NOT EXISTS platformtiers (
    code           text PRIMARY KEY,          -- starter, growth, business, enterprise
    name           text NOT NULL,
    rank           int  NOT NULL,             -- ordering / "next tier" display
    active         boolean NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS billingprofiles (
    code           text PRIMARY KEY,          -- POULTRY_BIRDS, GENERIC_STANDARD, ...
    name           text NOT NULL,
    metrictype     text NOT NULL,             -- ActiveBirdCount | ManualScale | ActiveRooms ...
    description    text NULL,
    active         boolean NOT NULL DEFAULT TRUE
);

-- Which tier a metric value qualifies for, per profile. Separate from price
-- (spec 2.7): changing a threshold never touches a currency amount.
CREATE TABLE IF NOT EXISTS billingtierrules (
    id             bigserial PRIMARY KEY,
    profilecode    text NOT NULL REFERENCES billingprofiles(code),
    tiercode       text NOT NULL REFERENCES platformtiers(code),
    minvalue       numeric(14,2) NOT NULL,
    maxvalue       numeric(14,2) NULL,        -- NULL = no upper bound
    effectivefrom  date NOT NULL DEFAULT '1900-01-01',
    effectiveto    date NULL,
    active         boolean NOT NULL DEFAULT TRUE
);
CREATE INDEX IF NOT EXISTS ix_billingtierrules_profile ON billingtierrules(profilecode) WHERE active;

CREATE TABLE IF NOT EXISTS pricebooks (
    id             bigserial PRIMARY KEY,
    code           text NOT NULL UNIQUE,      -- GH-2026
    marketcode     text NOT NULL REFERENCES billingmarkets(code),
    name           text NOT NULL,
    effectivefrom  date NOT NULL,
    effectiveto    date NULL,                 -- never overwrite: close and add a new book/entry
    active         boolean NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS pricebookentries (
    id             bigserial PRIMARY KEY,
    pricebookid    bigint NOT NULL REFERENCES pricebooks(id),
    tiercode       text NOT NULL REFERENCES platformtiers(code),
    profilecode    text NULL REFERENCES billingprofiles(code),  -- NULL = any profile
    currencycode   text NOT NULL,
    monthlyprice   numeric(14,2) NOT NULL,
    annualprice    numeric(14,2) NULL,        -- explicit, never derived (spec 11.3)
    taxinclusive   boolean NOT NULL DEFAULT TRUE,
    grandfatherable boolean NOT NULL DEFAULT TRUE,
    effectivefrom  date NOT NULL DEFAULT '1900-01-01',
    effectiveto    date NULL,
    active         boolean NOT NULL DEFAULT TRUE
);
CREATE INDEX IF NOT EXISTS ix_pricebookentries_book ON pricebookentries(pricebookid) WHERE active;

CREATE TABLE IF NOT EXISTS multicompanydiscountrules (
    id             bigserial PRIMARY KEY,
    mincompanies   int NOT NULL,
    percent        numeric(5,2) NOT NULL,
    active         boolean NOT NULL DEFAULT FALSE,   -- commercial decision pending
    effectivefrom  date NOT NULL DEFAULT '1900-01-01',
    effectiveto    date NULL
);

-- Small key/value knobs so policy changes need no deploy (spec 27).
CREATE TABLE IF NOT EXISTS platformbillingsettings (
    key            text PRIMARY KEY,
    value          text NOT NULL,
    description    text NULL,
    updatedatutc   timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

-- Add-on foundation only (spec 16) — no products implemented yet.
CREATE TABLE IF NOT EXISTS platformaddons (
    code           text PRIMARY KEY,
    name           text NOT NULL,
    pricingmodel   text NOT NULL DEFAULT 'flat-monthly',
    active         boolean NOT NULL DEFAULT FALSE
);

-- ---------------------------------------------------------------------------
-- The billing relationship: one account per Business Office (spec 2.1)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS organizationbillingaccounts (
    id                    bigserial PRIMARY KEY,
    owneruserid           text NOT NULL UNIQUE,   -- AspNetUsers.Id of the Business Office owner
    orgcode               text NULL,
    billingmarketcode     text NOT NULL REFERENCES billingmarkets(code),
    currencycode          text NOT NULL,
    billingemail          text NULL,
    billingcontactname    text NULL,
    billingaddress        text NULL,
    verificationstatus    text NOT NULL DEFAULT 'Unverified',  -- Unverified|AutoVerified|ReviewRequired|Verified
    verificationmethod    text NULL,                            -- SelfDeclared|PaymentProvider|BusinessDocument|ManualReview
    verifiedatutc         timestamp NULL,
    trialstartutc         timestamp NULL,
    trialendutc           timestamp NULL,
    status                text NOT NULL DEFAULT 'Trial',        -- Trial|Active|PastDue|GracePeriod|Suspended|Cancelled
    billingcycle          text NOT NULL DEFAULT 'monthly',      -- monthly|annual
    provider              text NULL,                            -- paystack
    externalcustomerid    text NULL,
    externalsubscriptionid text NULL,
    cancelatperiodend     boolean NOT NULL DEFAULT FALSE,
    currentperiodstart    date NULL,
    currentperiodend      date NULL,
    -- controlled market-change flow (spec 3.7): staged, not a live dropdown
    pendingmarketcode     text NULL,
    pendingmarketeffective date NULL,
    createdatutc          timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updatedatutc          timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

-- Per-company participation in the Organization bill (spec Part 9).
CREATE TABLE IF NOT EXISTS companybillingstates (
    farmid                text PRIMARY KEY,
    accountid             bigint NOT NULL REFERENCES organizationbillingaccounts(id),
    participationstatus   text NOT NULL DEFAULT 'Active',  -- Active|Archived|Exempt|EnterpriseContract|Suspended
    billingprofilecode    text NULL REFERENCES billingprofiles(code),  -- override; NULL = resolve from company type/template
    manualscalevalue      numeric(14,2) NULL,   -- profiles without an authoritative metric yet (spec 4.2-4.5)
    custommonthlyprice    numeric(14,2) NULL,   -- enterprise/custom (spec 6.2)
    grandfatheredmonthlyprice numeric(14,2) NULL, -- price lock (spec 11.2)
    exemptreason          text NULL,
    archivedatutc         timestamp NULL,
    createdatutc          timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updatedatutc          timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
CREATE INDEX IF NOT EXISTS ix_companybillingstates_account ON companybillingstates(accountid);

-- ---------------------------------------------------------------------------
-- Auditable evaluations — "why was this charged" answered forever (spec 5)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS companybillingevaluations (
    id                bigserial PRIMARY KEY,
    accountid         bigint NOT NULL REFERENCES organizationbillingaccounts(id),
    farmid            text NOT NULL,
    billingprofilecode text NOT NULL,
    metrictype        text NOT NULL,
    metricvalue       numeric(14,2) NOT NULL,
    tiercode          text NULL,
    marketcode        text NOT NULL,
    currencycode      text NOT NULL,
    pricebookentryid  bigint NULL,
    monthlyamount     numeric(14,2) NULL,
    pricingstatus     text NOT NULL,            -- Resolved|PricingNotConfigured|CustomPrice|Grandfathered|Exempt
    evaluationreason  text NOT NULL,            -- Preview|InvoiceGeneration|Manual
    billingperiodstart date NULL,
    billingperiodend   date NULL,
    evaluatedatutc    timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    createdby         text NOT NULL DEFAULT 'system'
);
CREATE INDEX IF NOT EXISTS ix_companybillingevaluations_farm ON companybillingevaluations(farmid, evaluatedatutc DESC);
CREATE INDEX IF NOT EXISTS ix_companybillingevaluations_acct ON companybillingevaluations(accountid, evaluatedatutc DESC);

-- ---------------------------------------------------------------------------
-- Consolidated Organization invoices — immutable snapshots (spec 7, 34)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS platforminvoices (
    id               bigserial PRIMARY KEY,
    invoicenumber    text NOT NULL UNIQUE,
    accountid        bigint NOT NULL REFERENCES organizationbillingaccounts(id),
    marketcode       text NOT NULL,
    currencycode     text NOT NULL,
    periodstart      date NOT NULL,
    periodend        date NOT NULL,
    issuedate        date NOT NULL,
    duedate          date NOT NULL,
    subtotal         numeric(14,2) NOT NULL,
    -- discount snapshot (spec 8.2): rule, count and amounts frozen on the invoice
    discountrulesnapshot text NULL,
    eligiblecompanycount int NOT NULL DEFAULT 0,
    discountpercent  numeric(5,2) NOT NULL DEFAULT 0,
    discountamount   numeric(14,2) NOT NULL DEFAULT 0,
    taxrate          numeric(5,2) NOT NULL DEFAULT 0,
    taxamount        numeric(14,2) NOT NULL DEFAULT 0,
    taxcode          text NULL,
    totalamount      numeric(14,2) NOT NULL,
    amountpaid       numeric(14,2) NOT NULL DEFAULT 0,
    balance          numeric(14,2) NOT NULL,
    status           text NOT NULL DEFAULT 'Open',  -- Open|Paid|PastDue|Void
    externalreference text NULL,                    -- provider checkout reference
    createdatutc     timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    -- deterministic period identity (spec 33): one invoice per account+period
    CONSTRAINT uq_platforminvoices_period UNIQUE (accountid, periodstart)
);

CREATE TABLE IF NOT EXISTS platforminvoicelines (
    id               bigserial PRIMARY KEY,
    invoiceid        bigint NOT NULL REFERENCES platforminvoices(id),
    farmid           text NULL,
    addoncode        text NULL,
    description      text NOT NULL,
    billingprofilecode text NULL,
    metrictype       text NULL,
    metricvalue      numeric(14,2) NULL,
    tiercode         text NULL,
    quantity         numeric(14,2) NOT NULL DEFAULT 1,
    unitprice        numeric(14,2) NOT NULL,
    lineamount       numeric(14,2) NOT NULL,
    evaluationid     bigint NULL REFERENCES companybillingevaluations(id)
);
CREATE INDEX IF NOT EXISTS ix_platforminvoicelines_invoice ON platforminvoicelines(invoiceid);

-- ---------------------------------------------------------------------------
-- First-class payments + idempotent webhook store (spec 13, 14)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS platformpayments (
    id               bigserial PRIMARY KEY,
    accountid        bigint NOT NULL REFERENCES organizationbillingaccounts(id),
    invoiceid        bigint NULL REFERENCES platforminvoices(id),
    provider         text NOT NULL,
    externalpaymentid text NULL,
    externalreference text NULL,
    amount           numeric(14,2) NOT NULL,
    currencycode     text NOT NULL,
    status           text NOT NULL,               -- Succeeded|Failed|Refunded|Pending
    paymentdateutc   timestamp NULL,
    receivedatutc    timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    methodsummary    text NULL,
    failurecode      text NULL,
    failuremessage   text NULL,
    refundedamount   numeric(14,2) NOT NULL DEFAULT 0,
    createdatutc     timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
-- one settlement per provider payment, however many times the webhook fires
CREATE UNIQUE INDEX IF NOT EXISTS uq_platformpayments_external
    ON platformpayments(provider, externalpaymentid) WHERE externalpaymentid IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_platformpayments_reference
    ON platformpayments(provider, externalreference) WHERE externalreference IS NOT NULL;

CREATE TABLE IF NOT EXISTS billingwebhookevents (
    id               bigserial PRIMARY KEY,
    provider         text NOT NULL,
    externaleventid  text NULL,
    eventtype        text NOT NULL,
    payloadhash      text NOT NULL,
    receivedatutc    timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    processedatutc   timestamp NULL,
    processingstatus text NOT NULL DEFAULT 'Received',  -- Received|Processed|Duplicate|Failed|Ignored
    error            text NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_billingwebhookevents_hash ON billingwebhookevents(provider, payloadhash);

-- Billing lifecycle audit (spec 36) — separate from operational auditlogs so
-- financial history survives any operational-log retention policy.
CREATE TABLE IF NOT EXISTS billingevents (
    id               bigserial PRIMARY KEY,
    accountid        bigint NULL,
    farmid           text NULL,
    eventtype        text NOT NULL,
    oldvalue         text NULL,
    newvalue         text NULL,
    reference        text NULL,
    reason           text NULL,
    actoruserid      text NULL,
    createdatutc     timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
CREATE INDEX IF NOT EXISTS ix_billingevents_account ON billingevents(accountid, createdatutc DESC);

-- ---------------------------------------------------------------------------
-- Seeds — idempotent. Only Ghana/Poultry is commercially live today.
-- ---------------------------------------------------------------------------

INSERT INTO billingmarkets (code, name, currencycode, provider, active) VALUES
    ('GH',   'Ghana',         'GHS', 'paystack', TRUE),
    ('NG',   'Nigeria',       'NGN', 'paystack', FALSE),
    ('US',   'United States', 'USD', 'none',     FALSE),
    ('INTL', 'International', 'USD', 'none',     FALSE)
ON CONFLICT (code) DO NOTHING;

INSERT INTO platformtiers (code, name, rank) VALUES
    ('starter',    'Starter',    1),
    ('growth',     'Growth',     2),
    ('business',   'Business',   3),
    ('enterprise', 'Enterprise', 4)
ON CONFLICT (code) DO NOTHING;

INSERT INTO billingprofiles (code, name, metrictype, description) VALUES
    ('POULTRY_BIRDS',        'Poultry — Active Birds',      'ActiveBirdCount',
     'Birds left across active flocks; the same figure the Production Log and reports use.'),
    ('WATER_STANDARD',       'Water — Company Scale',       'ManualScale',
     'Admin-configured company scale until a stable authoritative water metric is chosen.'),
    ('HOTEL_ROOMS',          'Hotel — Rooms',               'ManualScale',
     'Configured scale for now; switches to an authoritative active-room count when hotel data is complete.'),
    ('RESTAURANT_LOCATIONS', 'Restaurant — Locations',      'ManualScale',
     'Configured scale; becomes an outlet count when multi-location restaurant support exists.'),
    ('GENERIC_STANDARD',     'Generic — Standard',          'ManualScale',
     'One profile for every Generic business template. New templates bill through this with no code change.')
ON CONFLICT (code) DO NOTHING;

-- Poultry qualification — EXACTLY the live ladder (appsettings FarmSubscription):
-- 0–2,000 starter, 2,001–5,000 growth, above business.
INSERT INTO billingtierrules (profilecode, tiercode, minvalue, maxvalue)
SELECT v.p, v.t, v.lo, v.hi FROM (VALUES
    ('POULTRY_BIRDS', 'starter',  0::numeric,    2000::numeric),
    ('POULTRY_BIRDS', 'growth',   2001::numeric, 5000::numeric),
    ('POULTRY_BIRDS', 'business', 5001::numeric, NULL::numeric)
) AS v(p, t, lo, hi)
WHERE NOT EXISTS (SELECT 1 FROM billingtierrules r WHERE r.profilecode = v.p AND r.tiercode = v.t);

-- Every ManualScale profile qualifies as starter until an admin configures
-- more — a safe floor, never an invented higher charge.
INSERT INTO billingtierrules (profilecode, tiercode, minvalue, maxvalue)
SELECT v.p, 'starter', 0, NULL FROM (VALUES
    ('WATER_STANDARD'), ('HOTEL_ROOMS'), ('RESTAURANT_LOCATIONS'), ('GENERIC_STANDARD')
) AS v(p)
WHERE NOT EXISTS (SELECT 1 FROM billingtierrules r WHERE r.profilecode = v.p);

INSERT INTO pricebooks (code, marketcode, name, effectivefrom)
SELECT 'GH-2026', 'GH', 'Ghana 2026', DATE '2026-01-01'
WHERE NOT EXISTS (SELECT 1 FROM pricebooks WHERE code = 'GH-2026');

-- Ghana prices, POULTRY_BIRDS only — the live GHS 500/1000/1500 ladder,
-- migrated not invented. Other profiles/markets stay unpriced and resolve as
-- PricingNotConfigured (spec Parts 38–39).
INSERT INTO pricebookentries (pricebookid, tiercode, profilecode, currencycode, monthlyprice, taxinclusive)
SELECT pb.id, v.t, 'POULTRY_BIRDS', 'GHS', v.m, TRUE
FROM pricebooks pb, (VALUES
    ('starter',  500::numeric),
    ('growth',   1000::numeric),
    ('business', 1500::numeric)
) AS v(t, m)
WHERE pb.code = 'GH-2026'
  AND NOT EXISTS (
      SELECT 1 FROM pricebookentries e
      WHERE e.pricebookid = pb.id AND e.tiercode = v.t AND e.profilecode = 'POULTRY_BIRDS');

-- Example discount ladder from the spec — INACTIVE until the commercial
-- decision is made in admin. The engine treats "no active rule" as 0%.
INSERT INTO multicompanydiscountrules (mincompanies, percent, active)
SELECT v.n, v.p, FALSE FROM (VALUES (2, 5::numeric), (3, 10::numeric), (5, 15::numeric)) AS v(n, p)
WHERE NOT EXISTS (SELECT 1 FROM multicompanydiscountrules);

INSERT INTO platformbillingsettings (key, value, description) VALUES
    ('trialdays',          '150',   'Organization trial length in days. 150 matches what the current billing page promises.'),
    ('gracedays',          '14',    'Days of grace after a failed payment before restriction.'),
    ('enforcementenabled', 'false', 'Master switch. While false the platform never restricts access for billing reasons.'),
    ('taxratepercent',     '0',     'Flat tax rate applied to invoices. 0 until a tax policy is configured.')
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- The one metric function Phase A needs: authoritative active birds for a
-- farm. This is the migration-204 formula (latest noofbirdsleft per active,
-- arrived, non-deleted flock, clamped to [0, quantity]) — the same number the
-- Production Log shows. Do not fork this formula (spec 4.1).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION spplatformbilling_activebirds(p_farmid text)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE((
        SELECT SUM(CASE
                     WHEN lr.noofbirdsleft IS NULL          THEN f.quantity
                     WHEN lr.noofbirdsleft < 0              THEN 0
                     WHEN lr.noofbirdsleft > f.quantity     THEN f.quantity
                     ELSE lr.noofbirdsleft
                   END)
        FROM   flock f
        LEFT   JOIN LATERAL (
            SELECT pr.noofbirdsleft
            FROM   productionrecords pr
            WHERE  pr.farmid = p_farmid AND pr.flockid = f.flockid
            ORDER  BY pr.date DESC
            LIMIT 1
        ) lr ON TRUE
        WHERE  f.farmid = p_farmid AND f.active = TRUE AND f.hasarrived = TRUE
           AND COALESCE(f.isdeleted, FALSE) = FALSE), 0);
$$;

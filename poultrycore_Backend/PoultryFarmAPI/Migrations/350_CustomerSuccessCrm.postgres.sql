-- 350_CustomerSuccessCrm.postgres.sql
-- PROMPT 5 OF 7 — Customer Success CRM storage behind Organization/Company 360.
--
-- All three tables are INTERNAL-ONLY: they are read and written exclusively
-- through the platform-admin API (SystemAdmin/PlatformOwner) and are never
-- surfaced to customers. Author + timestamp are always recorded.

-- Internal notes, lightweight contact history and follow-ups in one stream.
-- contacttype NULL      => plain internal note
-- contacttype non-NULL  => recorded interaction (Called/Emailed/WhatsApp/
--                          Meeting/Demo/Training). This is an internal record
--                          only — the platform has no outbound connectors, so
--                          nothing here claims an external message was sent.
CREATE TABLE IF NOT EXISTS customercrmnotes (
    id              bigserial PRIMARY KEY,
    organizationid  text NOT NULL,
    companyid       text NULL,
    category        text NOT NULL DEFAULT 'General',  -- Support|Sales|Onboarding|Billing|Product Feedback|General
    contacttype     text NULL,                        -- Called|Emailed|WhatsApp|Meeting|Demo|Training
    note            text NOT NULL,
    followupatutc   timestamptz NULL,
    assignedtoname  text NULL,
    outcome         text NULL,
    attentionitemid bigint NULL REFERENCES customerattentionitems(id) ON DELETE SET NULL,
    createdby       text NOT NULL,
    createdatutc    timestamptz NOT NULL DEFAULT now(),
    updatedatutc    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_crmnotes_org ON customercrmnotes (organizationid, createdatutc DESC);
CREATE INDEX IF NOT EXISTS ix_crmnotes_company ON customercrmnotes (companyid) WHERE companyid IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_crmnotes_followup ON customercrmnotes (followupatutc) WHERE followupatutc IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_crmnotes_category ON customercrmnotes (category);

-- Structured product feedback captured by staff (aggregated later).
CREATE TABLE IF NOT EXISTS customerproductfeedback (
    id             bigserial PRIMARY KEY,
    organizationid text NOT NULL,
    companyid      text NULL,
    companyfamily  text NULL,
    category       text NOT NULL,          -- FeatureRequest|Problem|Praise|Other
    module         text NULL,              -- free text: which part of VisibilityCore
    severity       text NOT NULL DEFAULT 'Medium',   -- Low|Medium|High
    title          text NOT NULL,
    detail         text NULL,
    status         text NOT NULL DEFAULT 'Open',     -- Open|Reviewed|Planned|Done|Declined
    createdby      text NOT NULL,
    createdatutc   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_feedback_org ON customerproductfeedback (organizationid, createdatutc DESC);
CREATE INDEX IF NOT EXISTS ix_feedback_status ON customerproductfeedback (status, severity);

-- Structured cancellation reasons (recorded by staff when a subscription is
-- cancelled; the customer-facing cancel flow has no reason capture yet, so
-- this is the internal source of truth).
CREATE TABLE IF NOT EXISTS subscriptioncancellationreasons (
    id             bigserial PRIMARY KEY,
    organizationid text NOT NULL,
    accountid      bigint NULL,
    reasoncode     text NOT NULL,   -- TooExpensive|MissingFeature|HardToUse|BusinessClosed|TemporaryPause|Competitor|SupportIssue|Other
    note           text NULL,
    createdby      text NOT NULL,
    createdatutc   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_cancelreasons_org ON subscriptioncancellationreasons (organizationid, createdatutc DESC);

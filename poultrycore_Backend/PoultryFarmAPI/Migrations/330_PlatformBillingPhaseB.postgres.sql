-- ============================================================================
-- 330_PlatformBillingPhaseB.postgres.sql
--
-- Closes the gaps the Phase A completion report listed, additively:
--   3.5   per-company operating country (billing-owned, farms untouched)
--   4.6   template-level default billing profile
--   10.3  per-company evaluation window for companies added later
--   17    entitlement resolution (seeded EMPTY: absent = unlimited, so no
--         existing customer loses anything — spec Part 17)
--   35    credit-note foundation
--   20/33 lifecycle/scheduler knobs — auto-invoicing ships OFF so no account
--         starts receiving generated invoices until an admin turns it on
-- ============================================================================

ALTER TABLE companybillingstates
    ADD COLUMN IF NOT EXISTS operatingcountrycode text NULL,
    ADD COLUMN IF NOT EXISTS evaluationtrialenduntilutc timestamp NULL;

-- Template -> default profile (spec 4.6). Resolution order everywhere:
-- company override > template default > family map. Empty by default:
-- every Generic template keeps billing through GENERIC_STANDARD until an
-- admin deliberately points one somewhere else (e.g. School -> SCHOOL_STUDENTS).
CREATE TABLE IF NOT EXISTS businesstemplatebillingprofiles (
    templatecode          text PRIMARY KEY,      -- matches genericcompanyprofiles.genericbusinesstemplate
    defaultbillingprofile text NOT NULL REFERENCES billingprofiles(code),
    updatedatutc          timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

-- Entitlements (spec 17/24). A tier with NO row for a capability is
-- UNLIMITED — that convention is what guarantees migration restricts nobody.
CREATE TABLE IF NOT EXISTS planentitlements (
    id          bigserial PRIMARY KEY,
    tiercode    text NOT NULL REFERENCES platformtiers(code),
    capability  text NOT NULL,                   -- MAX_USERS, MAX_COMPANIES, API_ACCESS, ...
    enabled     boolean NOT NULL DEFAULT TRUE,
    limitvalue  numeric(14,2) NULL,              -- NULL = enabled without a numeric cap
    UNIQUE (tiercode, capability)
);

-- Credit notes (spec 35): corrections happen as new records, never as edits
-- to a paid invoice.
CREATE TABLE IF NOT EXISTS platformcreditnotes (
    id           bigserial PRIMARY KEY,
    accountid    bigint NOT NULL REFERENCES organizationbillingaccounts(id),
    invoiceid    bigint NULL REFERENCES platforminvoices(id),
    amount       numeric(14,2) NOT NULL,
    currencycode text NOT NULL,
    reason       text NOT NULL,
    status       text NOT NULL DEFAULT 'Applied',
    createdby    text NOT NULL,
    createdatutc timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

-- The scheduler scans these; partial indexes keep the daily pass cheap.
CREATE INDEX IF NOT EXISTS ix_platforminvoices_open
    ON platforminvoices(duedate) WHERE status IN ('Open', 'PastDue');
CREATE INDEX IF NOT EXISTS ix_billingaccounts_status
    ON organizationbillingaccounts(status);

INSERT INTO platformbillingsettings (key, value, description) VALUES
    ('autoinvoiceenabled', 'false',
     'When true the daily worker creates each Active account''s invoice at period start. Off until deliberately enabled.'),
    ('suspenddaysaftergrace', '14',
     'Days in GracePeriod before an account is marked Suspended. Status bookkeeping only while enforcementenabled=false.')
ON CONFLICT (key) DO NOTHING;

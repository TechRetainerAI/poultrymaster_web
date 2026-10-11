-- 346_PlatformActivityFoundation.postgres.sql
-- PROMPT 1 OF 7 — Cross-company activity & usage analytics foundation.
--
-- WHAT THIS IS
-- A normalized product-analytics layer that answers "is this customer
-- meaningfully using VisibilityCore?" — one table, cross-vertical, consumed by
-- the Admin app. It does NOT replace auditlogs (the authoritative action/
-- security trail) and it does NOT duplicate business transactions: each event
-- stores identifiers (sourcemodule + sourcerecordid) that point back at the
-- authoritative row, never the row's financial content.
--
-- VOCABULARY (matches the live schema, not an idealized one):
--   Company      = a row in farms (farms.farmid, farms.type = company family)
--   Organization = the Business Office owner (farms.owneruserid =
--                  organizationbillingaccounts.owneruserid = aspnetusers.id)
--   BusinessTemplateCode = genericcompanyprofiles.genericbusinesstemplate
--
-- TIMEZONE: businessdate is derived from the COMPANY's timezone
-- (farms.timezoneid, same tz database Postgres itself uses — see
-- CompanyTimeService), never the admin's browser. Falls back to UTC when the
-- company has no confirmed timezone.
--
-- IDEMPOTENCY: correlationid carries a caller-chosen identity (e.g. payment
-- provider reference, or 'bf:<table>:<pk>' for backfill). A partial unique
-- index + ON CONFLICT DO NOTHING makes re-emission a no-op.
--
-- companyusagedaily is a DERIVED CACHE (trigger-maintained, rebuildable via
-- platform_usagedaily_rebuild) — it is never a second source of truth.

-- ============================================================
-- 1. Normalized activity event stream
-- ============================================================
CREATE TABLE IF NOT EXISTS platformactivityevents (
    id                   bigserial PRIMARY KEY,
    organizationid       text NULL,          -- farms.owneruserid (aspnetusers.id)
    companyid            text NULL,          -- farms.farmid; NULL = organization-level event
    companyfamily        text NULL,          -- farms.type: Poultry|Water|Hotel|Restaurant|Generic|System
    businesstemplatecode text NULL,          -- Generic template (School, Gym, ...) when applicable
    userid               text NULL,
    employeeid           text NULL,
    activitycategory     text NOT NULL,      -- universal: SETUP|OPERATIONS|PRODUCTION|SALES|...
    activitytype         text NOT NULL,      -- specific: SaleRecorded, ProductionRecorded, ...
    sourcemodule         text NOT NULL,      -- Poultry|Water|Hotel|Restaurant|Generic|Shared|Billing|Auth
    sourcerecordid       text NULL,          -- id of the authoritative business row
    businessdate         date NULL,          -- in the COMPANY's timezone
    occurredatutc        timestamptz NOT NULL DEFAULT now(),
    ismeaningful         boolean NOT NULL DEFAULT false,
    source               text NOT NULL DEFAULT 'Runtime',  -- Runtime | HistoricalBackfill
    metadatajson         text NULL,          -- minimal analytics metadata only (no PII/financial copies)
    correlationid        text NULL,          -- idempotency key where duplicates must collapse
    createdatutc         timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_platformactivity_correlation
    ON platformactivityevents (correlationid) WHERE correlationid IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_platformactivity_company_occurred
    ON platformactivityevents (companyid, occurredatutc DESC);
CREATE INDEX IF NOT EXISTS ix_platformactivity_org_occurred
    ON platformactivityevents (organizationid, occurredatutc DESC);
CREATE INDEX IF NOT EXISTS ix_platformactivity_occurred
    ON platformactivityevents (occurredatutc DESC);
CREATE INDEX IF NOT EXISTS ix_platformactivity_businessdate
    ON platformactivityevents (businessdate);
CREATE INDEX IF NOT EXISTS ix_platformactivity_category
    ON platformactivityevents (activitycategory);
CREATE INDEX IF NOT EXISTS ix_platformactivity_type
    ON platformactivityevents (activitytype);
CREATE INDEX IF NOT EXISTS ix_platformactivity_family
    ON platformactivityevents (companyfamily);
-- The dashboard hot path: meaningful events per company per window.
CREATE INDEX IF NOT EXISTS ix_platformactivity_meaningful
    ON platformactivityevents (companyid, occurredatutc DESC) WHERE ismeaningful;

-- ============================================================
-- 2. Daily usage snapshot (derived cache, trigger-maintained)
-- ============================================================
CREATE TABLE IF NOT EXISTS companyusagedaily (
    companyid               text NOT NULL,
    businessdate            date NOT NULL,
    organizationid          text NULL,
    companyfamily           text NULL,
    totalactivitycount      int NOT NULL DEFAULT 0,   -- every recorded event
    meaningfulactivitycount int NOT NULL DEFAULT 0,   -- ismeaningful only
    activeusers             int NOT NULL DEFAULT 0,   -- distinct userids seen that day
    setupcount              int NOT NULL DEFAULT 0,   -- category counters: meaningful events only
    operationscount         int NOT NULL DEFAULT 0,
    productioncount         int NOT NULL DEFAULT 0,
    salescount              int NOT NULL DEFAULT 0,
    paymentscount           int NOT NULL DEFAULT 0,
    expensescount           int NOT NULL DEFAULT 0,
    inventorycount          int NOT NULL DEFAULT 0,
    deliverycount           int NOT NULL DEFAULT 0,
    customerscount          int NOT NULL DEFAULT 0,
    employeescount          int NOT NULL DEFAULT 0,
    payrollcount            int NOT NULL DEFAULT 0,
    closingcount            int NOT NULL DEFAULT 0,
    billingcount            int NOT NULL DEFAULT 0,
    updatedatutc            timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (companyid, businessdate)
);
CREATE INDEX IF NOT EXISTS ix_companyusagedaily_org ON companyusagedaily (organizationid, businessdate);
CREATE INDEX IF NOT EXISTS ix_companyusagedaily_date ON companyusagedaily (businessdate);

-- Distinct-user bookkeeping behind companyusagedaily.activeusers.
CREATE TABLE IF NOT EXISTS companyusagedailyusers (
    companyid    text NOT NULL,
    businessdate date NOT NULL,
    userid       text NOT NULL,
    PRIMARY KEY (companyid, businessdate, userid)
);

-- ============================================================
-- 3. Login / session engagement (tracked separately from business activity)
-- ============================================================
ALTER TABLE aspnetusers ADD COLUMN IF NOT EXISTS lastloginatutc timestamptz NULL;
ALTER TABLE aspnetusers ADD COLUMN IF NOT EXISTS logincount bigint NOT NULL DEFAULT 0;

-- One row per user per UTC day they logged in => ActiveUserDays without
-- a row per token refresh.
CREATE TABLE IF NOT EXISTS userlogindays (
    userid   text NOT NULL,
    loginday date NOT NULL,
    PRIMARY KEY (userid, loginday)
);

-- ============================================================
-- 4. Recording function — the single write path for activity events
-- ============================================================
-- Resolves organization / family / template / company-timezone businessdate
-- from the companyid so no caller ever duplicates that logic. Returns the new
-- event id, or NULL when the correlationid already exists (idempotent replay).
CREATE OR REPLACE FUNCTION platform_activity_record(
    p_companyid      text,
    p_userid         text,
    p_category       text,
    p_type           text,
    p_sourcemodule   text,
    p_sourcerecordid text        DEFAULT NULL,
    p_ismeaningful   boolean     DEFAULT false,
    p_metadatajson   text        DEFAULT NULL,
    p_correlationid  text        DEFAULT NULL,
    p_occurredatutc  timestamptz DEFAULT now(),
    p_source         text        DEFAULT 'Runtime',
    p_employeeid     text        DEFAULT NULL,
    p_businessdate   date        DEFAULT NULL   -- override (backfill knows the real business date)
) RETURNS bigint
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_org      text;
    v_family   text;
    v_template text;
    v_tz       text;
    v_bizdate  date;
    v_company  text := NULL;
    v_id       bigint;
BEGIN
    IF p_companyid IS NOT NULL AND p_companyid <> '' AND lower(p_companyid) <> 'unknown' THEN
        SELECT f.farmid, f.owneruserid, f.type, nullif(f.timezoneid, '')
          INTO v_company, v_org, v_family, v_tz
          FROM farms f
         WHERE f.farmid = p_companyid;
    END IF;

    IF v_company IS NOT NULL AND v_family = 'Generic' THEN
        SELECT nullif(g.genericbusinesstemplate, '') INTO v_template
          FROM genericcompanyprofiles g
         WHERE g.farmid = v_company
         ORDER BY g.genericcompanyprofileid DESC
         LIMIT 1;
    END IF;

    -- Organization-level event (no company): attribute to the user's own
    -- organization when that user owns companies or a billing account.
    IF v_company IS NULL AND p_userid IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM farms WHERE owneruserid = p_userid)
           OR EXISTS (SELECT 1 FROM organizationbillingaccounts WHERE owneruserid = p_userid) THEN
            v_org := p_userid;
        END IF;
    END IF;

    v_bizdate := p_businessdate;
    IF v_bizdate IS NULL THEN
        BEGIN
            v_bizdate := (p_occurredatutc AT TIME ZONE coalesce(v_tz, 'UTC'))::date;
        EXCEPTION WHEN OTHERS THEN
            v_bizdate := (p_occurredatutc AT TIME ZONE 'UTC')::date;
        END;
    END IF;

    INSERT INTO platformactivityevents
        (organizationid, companyid, companyfamily, businesstemplatecode,
         userid, employeeid, activitycategory, activitytype, sourcemodule,
         sourcerecordid, businessdate, occurredatutc, ismeaningful, source,
         metadatajson, correlationid)
    VALUES
        (v_org, v_company, v_family, v_template,
         nullif(nullif(p_userid, ''), 'Anonymous'), p_employeeid,
         upper(p_category), p_type, p_sourcemodule,
         p_sourcerecordid, v_bizdate, p_occurredatutc, p_ismeaningful, p_source,
         p_metadatajson, nullif(p_correlationid, ''))
    ON CONFLICT (correlationid) WHERE correlationid IS NOT NULL DO NOTHING
    RETURNING id INTO v_id;

    RETURN v_id;  -- NULL => duplicate correlationid, nothing recorded
END;
$fn$;

-- ============================================================
-- 5. Trigger that maintains the daily usage cache
-- ============================================================
CREATE OR REPLACE FUNCTION platform_activity_after_insert() RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_newuser int := 0;
BEGIN
    IF NEW.companyid IS NULL OR NEW.businessdate IS NULL THEN
        RETURN NEW;  -- org-level / auth events do not belong to a company day
    END IF;

    IF NEW.userid IS NOT NULL THEN
        INSERT INTO companyusagedailyusers (companyid, businessdate, userid)
        VALUES (NEW.companyid, NEW.businessdate, NEW.userid)
        ON CONFLICT DO NOTHING;
        GET DIAGNOSTICS v_newuser = ROW_COUNT;
    END IF;

    INSERT INTO companyusagedaily AS d
        (companyid, businessdate, organizationid, companyfamily,
         totalactivitycount, meaningfulactivitycount, activeusers,
         setupcount, operationscount, productioncount, salescount,
         paymentscount, expensescount, inventorycount, deliverycount,
         customerscount, employeescount, payrollcount, closingcount, billingcount)
    VALUES
        (NEW.companyid, NEW.businessdate, NEW.organizationid, NEW.companyfamily,
         1,
         CASE WHEN NEW.ismeaningful THEN 1 ELSE 0 END,
         v_newuser,
         CASE WHEN NEW.ismeaningful AND NEW.activitycategory = 'SETUP'      THEN 1 ELSE 0 END,
         CASE WHEN NEW.ismeaningful AND NEW.activitycategory = 'OPERATIONS' THEN 1 ELSE 0 END,
         CASE WHEN NEW.ismeaningful AND NEW.activitycategory = 'PRODUCTION' THEN 1 ELSE 0 END,
         CASE WHEN NEW.ismeaningful AND NEW.activitycategory = 'SALES'      THEN 1 ELSE 0 END,
         CASE WHEN NEW.ismeaningful AND NEW.activitycategory = 'PAYMENTS'   THEN 1 ELSE 0 END,
         CASE WHEN NEW.ismeaningful AND NEW.activitycategory = 'EXPENSES'   THEN 1 ELSE 0 END,
         CASE WHEN NEW.ismeaningful AND NEW.activitycategory = 'INVENTORY'  THEN 1 ELSE 0 END,
         CASE WHEN NEW.ismeaningful AND NEW.activitycategory = 'DELIVERY'   THEN 1 ELSE 0 END,
         CASE WHEN NEW.ismeaningful AND NEW.activitycategory = 'CUSTOMERS'  THEN 1 ELSE 0 END,
         CASE WHEN NEW.ismeaningful AND NEW.activitycategory = 'EMPLOYEES'  THEN 1 ELSE 0 END,
         CASE WHEN NEW.ismeaningful AND NEW.activitycategory = 'PAYROLL'    THEN 1 ELSE 0 END,
         CASE WHEN NEW.ismeaningful AND NEW.activitycategory = 'CLOSING'    THEN 1 ELSE 0 END,
         CASE WHEN NEW.ismeaningful AND NEW.activitycategory = 'BILLING'    THEN 1 ELSE 0 END)
    ON CONFLICT (companyid, businessdate) DO UPDATE SET
        totalactivitycount      = d.totalactivitycount + 1,
        meaningfulactivitycount = d.meaningfulactivitycount + excluded.meaningfulactivitycount,
        activeusers             = d.activeusers + excluded.activeusers,
        setupcount              = d.setupcount + excluded.setupcount,
        operationscount         = d.operationscount + excluded.operationscount,
        productioncount         = d.productioncount + excluded.productioncount,
        salescount              = d.salescount + excluded.salescount,
        paymentscount           = d.paymentscount + excluded.paymentscount,
        expensescount           = d.expensescount + excluded.expensescount,
        inventorycount          = d.inventorycount + excluded.inventorycount,
        deliverycount           = d.deliverycount + excluded.deliverycount,
        customerscount          = d.customerscount + excluded.customerscount,
        employeescount          = d.employeescount + excluded.employeescount,
        payrollcount            = d.payrollcount + excluded.payrollcount,
        closingcount            = d.closingcount + excluded.closingcount,
        billingcount            = d.billingcount + excluded.billingcount,
        organizationid          = coalesce(d.organizationid, excluded.organizationid),
        companyfamily           = coalesce(d.companyfamily, excluded.companyfamily),
        updatedatutc            = now();

    RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_platformactivity_usagedaily ON platformactivityevents;
CREATE TRIGGER trg_platformactivity_usagedaily
    AFTER INSERT ON platformactivityevents
    FOR EACH ROW EXECUTE FUNCTION platform_activity_after_insert();

-- Full rebuild of the cache from the event stream (safe to run any time; the
-- cache is derived, never authoritative). Also the recovery path if raw events
-- are ever archived: run BEFORE archiving so aggregates survive.
CREATE OR REPLACE FUNCTION platform_usagedaily_rebuild() RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
    TRUNCATE companyusagedaily;
    TRUNCATE companyusagedailyusers;

    INSERT INTO companyusagedailyusers (companyid, businessdate, userid)
    SELECT DISTINCT companyid, businessdate, userid
      FROM platformactivityevents
     WHERE companyid IS NOT NULL AND businessdate IS NOT NULL AND userid IS NOT NULL;

    INSERT INTO companyusagedaily
        (companyid, businessdate, organizationid, companyfamily,
         totalactivitycount, meaningfulactivitycount, activeusers,
         setupcount, operationscount, productioncount, salescount,
         paymentscount, expensescount, inventorycount, deliverycount,
         customerscount, employeescount, payrollcount, closingcount, billingcount)
    SELECT e.companyid, e.businessdate,
           max(e.organizationid), max(e.companyfamily),
           count(*),
           count(*) FILTER (WHERE e.ismeaningful),
           (SELECT count(*) FROM companyusagedailyusers u
             WHERE u.companyid = e.companyid AND u.businessdate = e.businessdate),
           count(*) FILTER (WHERE e.ismeaningful AND e.activitycategory = 'SETUP'),
           count(*) FILTER (WHERE e.ismeaningful AND e.activitycategory = 'OPERATIONS'),
           count(*) FILTER (WHERE e.ismeaningful AND e.activitycategory = 'PRODUCTION'),
           count(*) FILTER (WHERE e.ismeaningful AND e.activitycategory = 'SALES'),
           count(*) FILTER (WHERE e.ismeaningful AND e.activitycategory = 'PAYMENTS'),
           count(*) FILTER (WHERE e.ismeaningful AND e.activitycategory = 'EXPENSES'),
           count(*) FILTER (WHERE e.ismeaningful AND e.activitycategory = 'INVENTORY'),
           count(*) FILTER (WHERE e.ismeaningful AND e.activitycategory = 'DELIVERY'),
           count(*) FILTER (WHERE e.ismeaningful AND e.activitycategory = 'CUSTOMERS'),
           count(*) FILTER (WHERE e.ismeaningful AND e.activitycategory = 'EMPLOYEES'),
           count(*) FILTER (WHERE e.ismeaningful AND e.activitycategory = 'PAYROLL'),
           count(*) FILTER (WHERE e.ismeaningful AND e.activitycategory = 'CLOSING'),
           count(*) FILTER (WHERE e.ismeaningful AND e.activitycategory = 'BILLING')
      FROM platformactivityevents e
     WHERE e.companyid IS NOT NULL AND e.businessdate IS NOT NULL
     GROUP BY e.companyid, e.businessdate;
END;
$fn$;

-- ============================================================
-- 6. Login recording — called by the Login API after a VERIFIED login
--    (full credential or OTP success; never on token refresh).
-- ============================================================
CREATE OR REPLACE FUNCTION platform_record_login(p_userid text) RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_farmid text;
BEGIN
    IF p_userid IS NULL OR p_userid = '' THEN RETURN; END IF;

    UPDATE aspnetusers
       SET lastloginatutc = now(),
           logincount     = coalesce(logincount, 0) + 1
     WHERE id = p_userid
    RETURNING nullif(farmid, '') INTO v_farmid;

    INSERT INTO userlogindays (userid, loginday)
    VALUES (p_userid, (now() AT TIME ZONE 'UTC')::date)
    ON CONFLICT DO NOTHING;

    -- Trackable engagement signal; deliberately NOT meaningful activity.
    PERFORM platform_activity_record(
        p_companyid    => v_farmid,
        p_userid       => p_userid,
        p_category     => 'AUTHENTICATION',
        p_type         => 'UserLoggedIn',
        p_sourcemodule => 'Auth',
        p_ismeaningful => false);
END;
$fn$;

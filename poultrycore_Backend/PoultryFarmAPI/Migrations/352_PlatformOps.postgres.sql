-- 352_PlatformOps.postgres.sql
-- PROMPT 7 OF 7 — Platform operations: feature flags (+audit), security events,
-- release tracking and stored management briefs.
--
-- Error intelligence deliberately adds NO storage: customer-impact errors are
-- derived from the existing auditlogs trail (status='Failed', already carrying
-- farmid/userid/resource/action) and deep technical logs stay in GCP Cloud
-- Logging — this platform does not rebuild observability in SQL.

-- ============================================================
-- Feature flags: product rollout only. Core security/billing rules are never
-- flag-gated (enforced by review, documented in the admin UI).
-- ============================================================
CREATE TABLE IF NOT EXISTS platformfeatureflags (
    id           serial PRIMARY KEY,
    flagkey      text NOT NULL UNIQUE,         -- e.g. daily-closing-v2
    name         text NOT NULL,
    description  text NULL,
    enabled      boolean NOT NULL DEFAULT false,   -- master switch; rules refine
    defaulton    boolean NOT NULL DEFAULT false,   -- value when no rule matches
    createdby    text NOT NULL,
    createdatutc timestamptz NOT NULL DEFAULT now(),
    updatedatutc timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS platformfeatureflagrules (
    id         bigserial PRIMARY KEY,
    flagid     int NOT NULL REFERENCES platformfeatureflags(id) ON DELETE CASCADE,
    scopetype  text NOT NULL,   -- Global|Market|CompanyFamily|BusinessTemplate|Organization|Company|User
    scopevalue text NOT NULL DEFAULT '',   -- '' for Global
    enabled    boolean NOT NULL,
    createdby  text NOT NULL,
    createdatutc timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_flagrules_scope
    ON platformfeatureflagrules (flagid, scopetype, scopevalue);

CREATE TABLE IF NOT EXISTS platformfeatureflagaudit (
    id         bigserial PRIMARY KEY,
    flagkey    text NOT NULL,
    action     text NOT NULL,     -- Created|Enabled|Disabled|RuleSet|RuleRemoved|Updated
    scopetype  text NULL,
    scopevalue text NULL,
    oldvalue   text NULL,
    newvalue   text NULL,
    changedby  text NOT NULL,
    reason     text NULL,
    atutc      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_flagaudit_key ON platformfeatureflagaudit (flagkey, atutc DESC);

-- ============================================================
-- Security events: deterministic detections over existing data. Flag for
-- review — never an automatic fraud claim. One live row per condition per
-- subject per day; re-detection bumps occurrences.
-- ============================================================
CREATE TABLE IF NOT EXISTS platformsecurityevents (
    id             bigserial PRIMARY KEY,
    eventtype      text NOT NULL,     -- RepeatedFailedLogins|PlatformAdminChange|BillingMarketChange|PaymentConfigChange|AdminSurfaceDenied|...
    severity       text NOT NULL,     -- Info|Warning|Critical
    organizationid text NULL,
    companyid      text NULL,
    userid         text NULL,
    title          text NOT NULL,
    detail         text NULL,
    occurrences    int NOT NULL DEFAULT 1,
    eventdate      date NOT NULL DEFAULT (now() AT TIME ZONE 'UTC')::date,
    firstseenatutc timestamptz NOT NULL DEFAULT now(),
    lastseenatutc  timestamptz NOT NULL DEFAULT now(),
    status         text NOT NULL DEFAULT 'Open'   -- Open|Reviewed
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_securityevents_dedupe
    ON platformsecurityevents (eventtype, coalesce(userid, ''), coalesce(organizationid, ''), coalesce(companyid, ''), eventdate);
CREATE INDEX IF NOT EXISTS ix_securityevents_recent ON platformsecurityevents (lastseenatutc DESC);

CREATE OR REPLACE FUNCTION platform_security_event(
    p_eventtype text, p_severity text, p_organizationid text, p_companyid text,
    p_userid text, p_title text, p_detail text
) RETURNS bigint
LANGUAGE plpgsql
AS $fn$
DECLARE v_id bigint;
BEGIN
    INSERT INTO platformsecurityevents
        (eventtype, severity, organizationid, companyid, userid, title, detail)
    VALUES (p_eventtype, p_severity, p_organizationid, p_companyid, p_userid, p_title, p_detail)
    ON CONFLICT (eventtype, coalesce(userid, ''), coalesce(organizationid, ''), coalesce(companyid, ''), eventdate)
    DO UPDATE SET occurrences = platformsecurityevents.occurrences + 1,
                  lastseenatutc = now(),
                  severity = excluded.severity,
                  detail = excluded.detail
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$fn$;

-- ============================================================
-- Release tracking: each API instance registers the release it is running
-- (Cloud Run revision) at startup. Nothing is invented — if the platform
-- cannot see a version, there is simply no row.
-- ============================================================
CREATE TABLE IF NOT EXISTS platformreleases (
    id             serial PRIMARY KEY,
    service        text NOT NULL,     -- farm-api | login-api | admin-portal
    version        text NOT NULL,     -- Cloud Run revision / assembly version
    firstseenatutc timestamptz NOT NULL DEFAULT now(),
    UNIQUE (service, version)
);

-- ============================================================
-- Management briefs: deterministic metric snapshots (data first; any AI
-- summary would be derived FROM this stored source, never the reverse).
-- ============================================================
CREATE TABLE IF NOT EXISTS platformbriefs (
    id            bigserial PRIMARY KEY,
    brieftype     text NOT NULL,      -- Daily | Weekly
    briefdate     date NOT NULL,
    generatedby   text NOT NULL,
    generatedatutc timestamptz NOT NULL DEFAULT now(),
    metricsjson   text NOT NULL,      -- the structured brief exactly as served
    UNIQUE (brieftype, briefdate)
);

-- ============================================================
-- Retention policy (applied manually / by future scheduler — never silently):
--   security events: 730 days; flag audit: kept indefinitely (tiny, auditable);
--   briefs: 400 days; release rows: kept indefinitely.
-- Raw error metadata lives in auditlogs/Cloud Logging under their own policies.
-- ============================================================
CREATE OR REPLACE FUNCTION platform_ops_retention() RETURNS text
LANGUAGE plpgsql
AS $fn$
DECLARE v_sec int; v_briefs int;
BEGIN
    DELETE FROM platformsecurityevents WHERE lastseenatutc < now() - interval '730 days';
    GET DIAGNOSTICS v_sec = ROW_COUNT;
    DELETE FROM platformbriefs WHERE briefdate < current_date - 400;
    GET DIAGNOSTICS v_briefs = ROW_COUNT;
    RETURN format('security events pruned: %s; briefs pruned: %s', v_sec, v_briefs);
END;
$fn$;

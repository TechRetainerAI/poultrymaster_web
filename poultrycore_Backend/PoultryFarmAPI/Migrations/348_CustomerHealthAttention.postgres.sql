-- 348_CustomerHealthAttention.postgres.sql
-- PROMPT 3 OF 7 — Customer Health Engine + Needs Attention workflow.
--
-- Health itself is computed deterministically in the API (HealthEngine) from
-- the Prompt 1 activity foundation + billing signals; the database stores:
--   * customerattentionitems  — the actionable queue (deduplicated by rule)
--   * customerattentionnotes  — append-only internal notes (audit-friendly)
--   * customerhealthhistory   — daily/status-change health snapshots
-- plus the two functions the engine uses so duplicate suppression and
-- auto-resolution are transactional and testable in SQL.

CREATE TABLE IF NOT EXISTS customerattentionitems (
    id               bigserial PRIMARY KEY,
    organizationid   text NOT NULL,
    companyid        text NULL,                 -- NULL = organization-level item
    attentiontype    text NOT NULL,             -- e.g. PastDue, TrialEndingSoonHighEngagement
    severity         text NOT NULL,             -- High | Medium | Low
    title            text NOT NULL,
    reason           text NOT NULL,             -- human-readable, data-backed explanation
    sourcerule       text NOT NULL,             -- rule id that produced it
    status           text NOT NULL DEFAULT 'Open',  -- Open|Assigned|Contacted|Resolved|Dismissed
    assignedtouserid text NULL,
    assignedtoname   text NULL,
    followupatutc    timestamptz NULL,
    resolvedatutc    timestamptz NULL,
    resolvedby       text NULL,
    resolutionnote   text NULL,
    revenueatrisk    numeric NULL,              -- placeholder, filled by Prompt 6
    detectedatutc    timestamptz NOT NULL DEFAULT now(),
    lastdetectedatutc timestamptz NOT NULL DEFAULT now(),
    updatedatutc     timestamptz NOT NULL DEFAULT now()
);

-- Duplicate suppression: one LIVE item per (org, company, type). Resolved and
-- dismissed items drop out of the index, so history is preserved and the same
-- condition can legitimately re-open later as a NEW item.
CREATE UNIQUE INDEX IF NOT EXISTS ux_attention_live
    ON customerattentionitems (organizationid, coalesce(companyid, ''), attentiontype)
    WHERE status IN ('Open', 'Assigned', 'Contacted');
CREATE INDEX IF NOT EXISTS ix_attention_status ON customerattentionitems (status, severity, lastdetectedatutc DESC);
CREATE INDEX IF NOT EXISTS ix_attention_org ON customerattentionitems (organizationid);
CREATE INDEX IF NOT EXISTS ix_attention_followup ON customerattentionitems (followupatutc) WHERE followupatutc IS NOT NULL;

CREATE TABLE IF NOT EXISTS customerattentionnotes (
    id           bigserial PRIMARY KEY,
    itemid       bigint NOT NULL REFERENCES customerattentionitems(id) ON DELETE CASCADE,
    note         text NOT NULL,
    createdby    text NOT NULL,
    createdatutc timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_attentionnotes_item ON customerattentionnotes (itemid, createdatutc);

-- Health history: one row per subject per day, updated in place when the level
-- changes within the day. Enough to reconstruct Healthy → At Risk → Reactivated
-- without a snapshot every second.
CREATE TABLE IF NOT EXISTS customerhealthhistory (
    scope        text NOT NULL,                 -- 'Organization' | 'Company'
    subjectid    text NOT NULL,                 -- owneruserid or farmid
    recordeddate date NOT NULL,
    health       text NOT NULL,                 -- Healthy|NeedsAttention|AtRisk|Inactive|New
    reasons      text NULL,                     -- '; '-joined explanations as computed
    recordedatutc timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (scope, subjectid, recordeddate)
);
CREATE INDEX IF NOT EXISTS ix_healthhistory_subject ON customerhealthhistory (scope, subjectid, recordeddate DESC);

-- ============================================================
-- Upsert: refresh the live item for a condition, or open a new one.
-- Returns the item id. Never duplicates a live item (ux_attention_live).
-- ============================================================
CREATE OR REPLACE FUNCTION platform_attention_upsert(
    p_organizationid text,
    p_companyid      text,
    p_attentiontype  text,
    p_severity       text,
    p_title          text,
    p_reason         text,
    p_sourcerule     text
) RETURNS bigint
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_id bigint;
BEGIN
    UPDATE customerattentionitems
       SET reason = p_reason,
           severity = p_severity,
           title = p_title,
           sourcerule = p_sourcerule,
           lastdetectedatutc = now(),
           updatedatutc = now()
     WHERE organizationid = p_organizationid
       AND coalesce(companyid, '') = coalesce(p_companyid, '')
       AND attentiontype = p_attentiontype
       AND status IN ('Open', 'Assigned', 'Contacted')
    RETURNING id INTO v_id;

    IF v_id IS NOT NULL THEN
        RETURN v_id;
    END IF;

    INSERT INTO customerattentionitems
        (organizationid, companyid, attentiontype, severity, title, reason, sourcerule)
    VALUES
        (p_organizationid, p_companyid, p_attentiontype, p_severity, p_title, p_reason, p_sourcerule)
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$fn$;

-- ============================================================
-- Auto-resolve: close live items whose condition no longer holds
-- (e.g. "Auto Resolved — Customer Reactivated"). History is preserved;
-- the row stays, status becomes Resolved with resolvedby = 'system'.
-- Returns how many items were resolved.
-- ============================================================
CREATE OR REPLACE FUNCTION platform_attention_autoresolve(
    p_organizationid text,
    p_companyid      text,          -- NULL matches org-level items only
    p_attentiontypes text[],
    p_note           text
) RETURNS int
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_n int;
BEGIN
    UPDATE customerattentionitems
       SET status = 'Resolved',
           resolvedatutc = now(),
           resolvedby = 'system',
           resolutionnote = p_note,
           updatedatutc = now()
     WHERE organizationid = p_organizationid
       AND coalesce(companyid, '') = coalesce(p_companyid, '')
       AND attentiontype = ANY (p_attentiontypes)
       AND status IN ('Open', 'Assigned', 'Contacted');
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END;
$fn$;

-- ============================================================
-- Health history writer: one row per subject per day, updated on change.
-- ============================================================
CREATE OR REPLACE FUNCTION platform_health_record(
    p_scope     text,
    p_subjectid text,
    p_health    text,
    p_reasons   text
) RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
    INSERT INTO customerhealthhistory (scope, subjectid, recordeddate, health, reasons)
    VALUES (p_scope, p_subjectid, (now() AT TIME ZONE 'UTC')::date, p_health, p_reasons)
    ON CONFLICT (scope, subjectid, recordeddate) DO UPDATE
        SET health = excluded.health,
            reasons = excluded.reasons,
            recordedatutc = now()
        WHERE customerhealthhistory.health IS DISTINCT FROM excluded.health;
END;
$fn$;

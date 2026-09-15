-- =============================================================================
-- 263_PoultryFinancialSettingsPermissions.postgres.sql
--
-- Purpose
-- -------
-- Two IAM keys for the cost-recognition settings page, and the item-override
-- right that goes with it.
--
-- WHY ITS OWN RESOURCE
-- ====================
-- The obvious home was office.settings, where farmproductionsettings already
-- lives. It is the wrong home. Egg-pick times and "when does feed hit the P&L"
-- are not the same kind of decision, and the person who maintains the first is
-- not necessarily the person who should be making the second -- a change here
-- moves what the owner reads as profit.
--
-- So: poultry.financial-settings, in the Finance group, next to the money
-- resources 255 created.
--
-- WHO GETS IT
-- ===========
--   .view  to everyone holding poultry.reports.view
--   .edit  to everyone holding poultry.reports.export
--
-- Both lines want justifying, because neither is obvious.
--
-- VIEW rides poultry.reports.view because the setting explains a number in the
-- P&L. Anybody who can read the P&L should be able to see why it says what it
-- says; hiding the setting from them would leave the report unexplainable
-- without making anything safer.
--
-- EDIT rides poultry.reports.EXPORT, which looks odd until you count: 8 roles
-- can view reports and 6 can export them, and export is the closest thing the
-- reports resource has to a privileged action. Granting edit to all 8 would
-- hand a P&L-shaping decision to every person who can open a report. There is
-- no cleaner signal in the current catalog, and inventing a role hierarchy in a
-- migration would be worse. An admin can narrow it afterwards; the alternative
-- was to grant it to nobody and have the page 403 for everyone on day one.
--
-- THE ITEM OVERRIDE IS NOT A SEPARATE KEY
-- =======================================
-- Overriding one item's treatment is done on the Raw Materials item form and
-- rides poultry.raw-materials.edit, which already exists. A separate
-- CanOverrideItemCostRecognition key would have to be granted to somebody
-- before anyone could edit an item's financial treatment, and on day one that
-- somebody is nobody -- the form would render a control that always failed.
-- If the two rights need separating later, that is a migration of its own with
-- a grant strategy behind it.
--
-- EFFECT ON TODAY'S NUMBERS: none. This file touches only the IAM catalog and
-- grant tables. No money, no ledger, no balance.
--
-- Order: after 262.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $iam$
DECLARE
    v_added_keys  integer := 0;
    v_added_roles integer := 0;
    v_added_users integer := 0;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '263: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    -- ---- 1. the catalog ---------------------------------------------------
    -- view and edit only. There is nothing to create, nothing to approve and
    -- nothing to export: the page reads two values and writes two values.
    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'poultry.financial-settings.' || a.action, 'poultry', 'financial-settings', a.action,
           'Finance', 'Financial Settings',
           'When inventory costs reach Profit & Loss. Editing changes how FUTURE '
           || 'purchases are treated; existing purchases keep the method they were created with.',
           'Poultry',
           -- Edit is flagged dangerous: it changes what the owner reads as profit
           -- from here on, and that deserves a confirmation in any UI that
           -- honours the flag.
           a.action = 'edit', 88
    FROM (VALUES ('view'), ('edit')) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;

    GET DIAGNOSTICS v_added_keys = ROW_COUNT;

    -- ---- 2. role grants ---------------------------------------------------
    IF to_regclass('public.iamrolepermissions') IS NOT NULL THEN
        INSERT INTO iamrolepermissions (roleid, permissionkey)
        SELECT rp.roleid, m.new_key
        FROM   iamrolepermissions rp
        JOIN   (VALUES
                  -- see the header for both of these
                  ('poultry.reports.view',   'poultry.financial-settings.view'),
                  ('poultry.reports.export', 'poultry.financial-settings.edit')
               ) AS m(old_key, new_key) ON m.old_key = rp.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
        ON CONFLICT (roleid, permissionkey) DO NOTHING;

        GET DIAGNOSTICS v_added_roles = ROW_COUNT;
    END IF;

    -- ---- 3. user grants ---------------------------------------------------
    -- Per-user grants are farm-scoped and carry an effect; both are copied
    -- verbatim so a Deny stays a Deny.
    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        INSERT INTO iamuserpermissions (userid, farmid, permissionkey, effect, reason, grantedby, grantedat)
        SELECT up.userid, up.farmid, m.new_key, up.effect,
               'Carried over from ' || up.permissionkey || ' by migration 263',
               up.grantedby, (now() at time zone 'utc')
        FROM   iamuserpermissions up
        JOIN   (VALUES
                  ('poultry.reports.view',   'poultry.financial-settings.view'),
                  ('poultry.reports.export', 'poultry.financial-settings.edit')
               ) AS m(old_key, new_key) ON m.old_key = up.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
          AND  (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;

        GET DIAGNOSTICS v_added_users = ROW_COUNT;
    END IF;

    RAISE NOTICE '263: % catalog key(s), % role grant(s), % user grant(s) added.',
        v_added_keys, v_added_roles, v_added_users;
END;
$iam$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'catalog keys (2 expected)' AS check,
       CASE WHEN COUNT(*) = 2 THEN 'OK' ELSE 'MISSING (' || COUNT(*) || ')' END AS result
FROM   iampermissions
WHERE  permissionkey LIKE 'poultry.financial-settings.%'

UNION ALL
-- Anyone who can read the P&L can see why it says what it says.
SELECT 'every report viewer can see the setting',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'LOST ' || COUNT(*) END
FROM   iamrolepermissions rp
WHERE  rp.permissionkey = 'poultry.reports.view'
  AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                   WHERE x.roleid = rp.roleid
                     AND x.permissionkey = 'poultry.financial-settings.view')

UNION ALL
-- But editing is narrower than viewing, which is the whole point.
SELECT 'edit is no wider than reports.export',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'WIDENED ' || COUNT(*) END
FROM   iamrolepermissions rp
WHERE  rp.permissionkey = 'poultry.financial-settings.edit'
  AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                   WHERE x.roleid = rp.roleid
                     AND x.permissionkey = 'poultry.reports.export');

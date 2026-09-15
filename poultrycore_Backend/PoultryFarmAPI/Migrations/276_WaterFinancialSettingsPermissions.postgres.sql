-- =============================================================================
-- 276_WaterFinancialSettingsPermissions.postgres.sql
--
-- Purpose
-- -------
-- The water mirror of 263. Two IAM keys for the cost-recognition settings page,
-- and the item-override right that goes with it.
--
-- WHY ITS OWN RESOURCE
-- ====================
-- The obvious home was office.settings, where water/company and
-- water/farm-settings already live. It is the wrong home. Machine allocation and
-- "when does packaging hit the P&L" are not the same kind of decision, and the
-- person who maintains the first is not necessarily the person who should be
-- making the second -- a change here moves what the owner reads as profit.
--
-- So: water.financial-settings, in the Finance group, next to the money
-- resources 260 created (which ran to sortorder 87).
--
-- WHO GETS IT, AND WHY THE DONOR LIST IS LONGER THAN POULTRY'S
-- ============================================================
-- 263 carries from poultry.reports.view and poultry.reports.export, because the
-- poultry catalog is known and those two keys are known to exist in it.
--
-- The WATER catalog is not in this repo. IamPermissionMap.cs shows the resources
-- -- water.reports, water.expenses, water.cash -- but the rows that seed their
-- ACTIONS are seeded outside version control, so this file cannot verify that
-- water.reports.export exists the way 263 could verify poultry's.
--
-- Rather than guess one donor and risk granting to nobody, this file lists
-- several and lets the ones that do not exist contribute nothing. That is safe
-- by construction: each grant is `SELECT ... FROM iamrolepermissions WHERE
-- permissionkey = old_key`, so a donor that is not in the catalog simply matches
-- zero rows. It cannot error and it cannot over-grant beyond the donors named.
--
--   .view  from water.reports.view and water.cash.view
--   .edit  from water.reports.export and water.cash.edit
--
-- water.cash.* is included because 260 used exactly that donor for the water
-- money resources and it demonstrably reached real roles. The reports keys are
-- included because the setting explains a number in the P&L, and anybody who can
-- read the P&L should be able to see why it says what it says.
--
-- EDIT IS DELIBERATELY NARROWER THAN VIEW. Neither donor for edit is a plain
-- view right, so a person who can only read cannot reshape profit.
--
-- THE ITEM OVERRIDE IS NOT A SEPARATE KEY
-- =======================================
-- Overriding one item's treatment is done on the Raw Materials item form and
-- rides water.raw-materials.edit, which already exists. A separate
-- CanOverrideItemCostRecognition key would have to be granted to somebody before
-- anyone could edit an item's financial treatment, and on day one that somebody
-- is nobody -- the form would render a control that always failed.
--
-- EFFECT ON TODAY'S NUMBERS: none. This file touches only the IAM catalog and
-- grant tables. No money, no ledger, no balance.
--
-- Order: after 275.
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
        RAISE NOTICE '276: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    -- ---- 1. the catalog ---------------------------------------------------
    -- view and edit only. There is nothing to create, nothing to approve and
    -- nothing to export: the page reads two values and writes two values.
    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'water.financial-settings.' || a.action, 'water', 'financial-settings', a.action,
           'Finance', 'Financial Settings',
           'When inventory costs reach Profit & Loss. Editing changes how FUTURE '
           || 'purchases are treated; existing purchases keep the method they were created with.',
           'Water',
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
                  -- see the header for why there are two donors per action
                  ('water.reports.view',   'water.financial-settings.view'),
                  ('water.cash.view',      'water.financial-settings.view'),
                  ('water.reports.export', 'water.financial-settings.edit'),
                  ('water.cash.edit',      'water.financial-settings.edit')
               ) AS m(old_key, new_key) ON m.old_key = rp.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
        ON CONFLICT (roleid, permissionkey) DO NOTHING;

        GET DIAGNOSTICS v_added_roles = ROW_COUNT;
    END IF;

    -- ---- 3. user grants ---------------------------------------------------
    -- Per-user grants are company-scoped and carry an effect; both are copied
    -- verbatim so a Deny stays a Deny.
    --
    -- DISTINCT ON is needed here and not in 263: with two donors per new key a
    -- user holding both would produce two rows for one (userid, farmid,
    -- permissionkey), and ON CONFLICT cannot resolve a conflict inside the same
    -- statement. Deny wins the tie, because silently upgrading a Deny to an
    -- Allow while copying a grant would be the worst possible outcome here.
    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        INSERT INTO iamuserpermissions (userid, farmid, permissionkey, effect, reason, grantedby, grantedat)
        SELECT DISTINCT ON (up.userid, up.farmid, m.new_key)
               up.userid, up.farmid, m.new_key, up.effect,
               'Carried over from ' || up.permissionkey || ' by migration 276',
               up.grantedby, (now() at time zone 'utc')
        FROM   iamuserpermissions up
        JOIN   (VALUES
                  ('water.reports.view',   'water.financial-settings.view'),
                  ('water.cash.view',      'water.financial-settings.view'),
                  ('water.reports.export', 'water.financial-settings.edit'),
                  ('water.cash.edit',      'water.financial-settings.edit')
               ) AS m(old_key, new_key) ON m.old_key = up.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
          AND  (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
        ORDER  BY up.userid, up.farmid, m.new_key,
                  CASE WHEN up.effect = 'Deny' THEN 0 ELSE 1 END
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;

        GET DIAGNOSTICS v_added_users = ROW_COUNT;
    END IF;

    RAISE NOTICE '276: % catalog key(s), % role grant(s), % user grant(s) added.',
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
WHERE  permissionkey LIKE 'water.financial-settings.%'

UNION ALL
-- Somebody can reach the page. The donors are unverifiable from this repo, so
-- the check that matters is that the grants did not all evaporate.
SELECT 'at least one role can view it',
       CASE WHEN COUNT(*) > 0 THEN 'OK' ELSE 'GRANTED TO NOBODY' END
FROM   iamrolepermissions
WHERE  permissionkey = 'water.financial-settings.view'

UNION ALL
-- But editing is narrower than viewing, which is the whole point.
SELECT 'edit is no wider than view',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'WIDENED ' || COUNT(*) END
FROM   iamrolepermissions rp
WHERE  rp.permissionkey = 'water.financial-settings.edit'
  AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                   WHERE x.roleid = rp.roleid
                     AND x.permissionkey = 'water.financial-settings.view')

UNION ALL
-- 276 must not have touched the poultry keys 263 created.
SELECT 'poultry keys untouched',
       CASE WHEN COUNT(*) = 2 THEN 'OK' ELSE 'CHANGED (' || COUNT(*) || ')' END
FROM   iampermissions
WHERE  permissionkey LIKE 'poultry.financial-settings.%';

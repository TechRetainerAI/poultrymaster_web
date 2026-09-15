-- =============================================================================
-- 273_PoultryAssetPermissions.postgres.sql
--
-- Purpose
-- -------
-- IAM keys for the Asset Register and for depreciation.
--
-- TWO RESOURCES, NOT EIGHT KEYS
-- =============================
-- §74 lists eight rights: view, create, edit, add costs, generate depreciation,
-- reverse depreciation, dispose, reverse asset. Eight bespoke keys would be
-- eight things an administrator has to grant before anybody can do anything,
-- and on day one the answer to "who has them?" is nobody.
--
-- So they map onto the catalog's existing FIVE actions across two resources:
--
--   poultry.assets            .view    see the register and an asset's detail
--                             .create  add an asset, and add costs to one
--                             .edit    rename, relocate, set life and residual
--                             .delete  dispose or reverse an acquisition
--   poultry.asset-depreciation
--                             .create  generate the monthly charge
--                             .view    read the depreciation history
--                             .approve reverse or adjust a posted charge
--
-- Adding a cost rides .create because it IS creating an acquisition cost, and
-- disposal and reversal ride .delete because both end an asset's life in the
-- register. ResolveAction already maps a /reverse segment onto approve and a
-- /dispose onto delete, so the controller needs no extra wiring.
--
-- WHY DEPRECIATION IS ITS OWN RESOURCE
-- ====================================
-- Because generating it writes to Profit & Loss. Somebody who can add a vehicle
-- to the register is not necessarily somebody who should be able to change what
-- the owner reads as profit, and folding the two together would make that
-- impossible to separate later.
--
-- WHO GETS IT
-- ===========
--   assets.view              everyone with poultry.reports.view
--   assets.create/.edit      everyone with poultry.expenses.create / .edit
--   assets.delete            everyone with poultry.expenses.delete
--   depreciation.view        everyone with poultry.reports.view
--   depreciation.create      everyone with poultry.reports.export
--   depreciation.approve     everyone with poultry.reports.export
--
-- Assets ride the EXPENSES rights because a capital acquisition is a cost entry
-- in every practical sense -- the same person records "generator, 80,000" today
-- and will record it on the Assets page tomorrow. Depreciation rides reports
-- .export for the reason 263 gives at length: it is the narrowest privileged
-- action the reports resource has, and granting a P&L-shaping right to every
-- report viewer would be worse than granting it to the six who can export.
--
-- EFFECT ON TODAY'S NUMBERS: none. Catalog and grants only.
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
    v_n           integer;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '273: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    -- ---- 1. the catalog ---------------------------------------------------
    -- The resource is stored BARE, matching 260 and 263. Migration 255 stored a
    -- 'poultry/'-prefixed form for its own keys; that discrepancy is known and
    -- is not widened here.
    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'poultry.assets.' || a.action, 'poultry', 'assets', a.action,
           'Finance', 'Assets',
           'Major long-term purchases -- buildings, vehicles, machinery -- their '
           || 'cost, depreciation and current book value.',
           'Poultry',
           -- Delete covers disposal and reversal of an acquisition. Both end an
           -- asset's life in the register and both move money.
           a.action = 'delete', 89
    FROM (VALUES ('view'), ('create'), ('edit'), ('delete')) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_added_keys := v_added_keys + v_n;

    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'poultry.asset-depreciation.' || a.action, 'poultry', 'asset-depreciation', a.action,
           'Finance', 'Depreciation',
           'Charging an asset to Profit & Loss over its useful life. Depreciation '
           || 'is a non-cash cost: it changes profit and never moves money.',
           'Poultry',
           -- Both writes are flagged: generating charges the P&L, and reversing
           -- un-charges it. Neither should be a one-click action in a UI that
           -- honours the flag.
           a.action IN ('create', 'approve'), 90
    FROM (VALUES ('view'), ('create'), ('approve')) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_added_keys := v_added_keys + v_n;

    -- ---- 2. role grants ---------------------------------------------------
    IF to_regclass('public.iamrolepermissions') IS NOT NULL THEN
        INSERT INTO iamrolepermissions (roleid, permissionkey)
        SELECT rp.roleid, m.new_key
        FROM   iamrolepermissions rp
        JOIN   (VALUES
                  ('poultry.reports.view',    'poultry.assets.view'),
                  ('poultry.expenses.create', 'poultry.assets.create'),
                  ('poultry.expenses.edit',   'poultry.assets.edit'),
                  ('poultry.expenses.delete', 'poultry.assets.delete'),
                  ('poultry.reports.view',    'poultry.asset-depreciation.view'),
                  ('poultry.reports.export',  'poultry.asset-depreciation.create'),
                  ('poultry.reports.export',  'poultry.asset-depreciation.approve')
               ) AS m(old_key, new_key) ON m.old_key = rp.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
        ON CONFLICT (roleid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_added_roles = ROW_COUNT;
    END IF;

    -- ---- 3. user grants ---------------------------------------------------
    -- Farm-scoped and carrying an effect; both copied verbatim so a Deny stays
    -- a Deny rather than quietly becoming an Allow on a new key.
    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        INSERT INTO iamuserpermissions (userid, farmid, permissionkey, effect, reason, grantedby, grantedat)
        SELECT up.userid, up.farmid, m.new_key, up.effect,
               'Carried over from ' || up.permissionkey || ' by migration 273',
               up.grantedby, (now() at time zone 'utc')
        FROM   iamuserpermissions up
        JOIN   (VALUES
                  ('poultry.reports.view',    'poultry.assets.view'),
                  ('poultry.expenses.create', 'poultry.assets.create'),
                  ('poultry.expenses.edit',   'poultry.assets.edit'),
                  ('poultry.expenses.delete', 'poultry.assets.delete'),
                  ('poultry.reports.view',    'poultry.asset-depreciation.view'),
                  ('poultry.reports.export',  'poultry.asset-depreciation.create'),
                  ('poultry.reports.export',  'poultry.asset-depreciation.approve')
               ) AS m(old_key, new_key) ON m.old_key = up.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
          AND  (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_added_users = ROW_COUNT;
    END IF;

    RAISE NOTICE '273: % catalog key(s), % role grant(s), % user grant(s) added.',
        v_added_keys, v_added_roles, v_added_users;
END;
$iam$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'catalog keys (7 expected)' AS check,
       CASE WHEN COUNT(*) = 7 THEN 'OK' ELSE 'MISSING (' || COUNT(*) || ')' END AS result
FROM   iampermissions
WHERE  permissionkey LIKE 'poultry.assets.%'
    OR permissionkey LIKE 'poultry.asset-depreciation.%'

UNION ALL
-- Everyone who can read a report can see what the farm owns.
SELECT 'every report viewer can see the register',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'LOST ' || COUNT(*) END
FROM   iamrolepermissions rp
WHERE  rp.permissionkey = 'poultry.reports.view'
  AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                   WHERE x.roleid = rp.roleid AND x.permissionkey = 'poultry.assets.view')

UNION ALL
-- Recording an asset is no wider than recording an expense.
SELECT 'creating an asset is no wider than an expense',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'WIDENED ' || COUNT(*) END
FROM   iamrolepermissions rp
WHERE  rp.permissionkey = 'poultry.assets.create'
  AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                   WHERE x.roleid = rp.roleid AND x.permissionkey = 'poultry.expenses.create')

UNION ALL
-- And charging the P&L is narrower than reading it.
SELECT 'generating depreciation is narrower than viewing',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'WIDENED ' || COUNT(*) END
FROM   iamrolepermissions rp
WHERE  rp.permissionkey = 'poultry.asset-depreciation.create'
  AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                   WHERE x.roleid = rp.roleid AND x.permissionkey = 'poultry.reports.export');

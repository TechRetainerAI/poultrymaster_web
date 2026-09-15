-- =============================================================================
-- 286_WaterAssetPermissions.postgres.sql
--
-- Purpose
-- -------
-- The water mirror of 273. IAM keys for the Asset Register and for depreciation.
--
-- TWO RESOURCES, NOT EIGHT KEYS
-- =============================
-- The register needs eight rights: view, create, edit, add costs, generate
-- depreciation, reverse depreciation, dispose, reverse asset. Eight bespoke keys
-- would be eight things an administrator has to grant before anybody can do
-- anything, and on day one the answer to "who has them?" is nobody.
--
-- So they map onto the catalog's existing FIVE actions across two resources:
--
--   water.assets              .view    see the register and an asset's detail
--                             .create  add an asset, and add costs to one
--                             .edit    rename, relocate, set life and residual
--                             .delete  dispose or reverse an acquisition
--   water.asset-depreciation
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
-- Because generating it writes to Profit & Loss. Somebody who can add a delivery
-- truck to the register is not necessarily somebody who should be able to change
-- what the owner reads as profit, and folding the two together would make that
-- impossible to separate later.
--
-- WHO GETS IT
-- ===========
--   assets.view              water.reports.view, water.expenses.view
--   assets.create            water.expenses.create
--   assets.edit              water.expenses.edit
--   assets.delete            water.expenses.delete
--   depreciation.view        water.reports.view, water.expenses.view
--   depreciation.create      water.reports.export, water.cash.edit
--   depreciation.approve     water.reports.export, water.cash.delete
--
-- Assets ride the EXPENSES rights because a capital acquisition is a cost entry
-- in every practical sense -- the same person records "generator, 80,000" today
-- and will record it on the Assets page tomorrow. In water's case that is more
-- than an analogy: 283 makes the acquisition literally write a waterexpenses
-- row, so anybody granted assets.create is doing something they could already do
-- on the Expenses page.
--
-- Depreciation rides the narrowest privileged rights available, for the reason
-- 276 gives at length: granting a P&L-shaping right to every report viewer would
-- be worse than granting it to the few who can export or move cash. As in 276,
-- several donors are listed because the water IAM catalog is not in this repo to
-- verify against, and a donor that does not exist contributes nothing rather
-- than erroring.
--
-- EFFECT ON TODAY'S NUMBERS: none. Catalog and grants only.
--
-- Order: after 285.
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
        RAISE NOTICE '286: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    -- ---- 1. the catalog ---------------------------------------------------
    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'water.assets.' || a.action, 'water', 'assets', a.action,
           'Finance', 'Asset Register',
           'Boreholes, machines, tanks and vehicles the company owns, and what '
           || 'they are still worth. Create covers adding costs to an asset; '
           || 'delete covers disposal and reversing an acquisition.',
           'Water',
           -- Ending an asset's life in the register is the dangerous one.
           a.action = 'delete', 89
    FROM (VALUES ('view'), ('create'), ('edit'), ('delete')) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_added_keys := v_added_keys + v_n;

    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'water.asset-depreciation.' || a.action, 'water', 'asset-depreciation', a.action,
           'Finance', 'Depreciation',
           'Charging an asset to Profit & Loss over its useful life. Depreciation '
           || 'is a non-cash cost: it changes profit and never moves money.',
           'Water',
           a.action = 'approve', 90
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
                  ('water.reports.view',    'water.assets.view'),
                  ('water.expenses.view',   'water.assets.view'),
                  ('water.expenses.create', 'water.assets.create'),
                  ('water.expenses.edit',   'water.assets.edit'),
                  ('water.expenses.delete', 'water.assets.delete'),
                  ('water.reports.view',    'water.asset-depreciation.view'),
                  ('water.expenses.view',   'water.asset-depreciation.view'),
                  ('water.reports.export',  'water.asset-depreciation.create'),
                  ('water.cash.edit',       'water.asset-depreciation.create'),
                  ('water.reports.export',  'water.asset-depreciation.approve'),
                  ('water.cash.delete',     'water.asset-depreciation.approve')
               ) AS m(old_key, new_key) ON m.old_key = rp.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
        ON CONFLICT (roleid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_added_roles = ROW_COUNT;
    END IF;

    -- ---- 3. user grants ---------------------------------------------------
    -- DISTINCT ON for the same reason 276 needs it: several donors map onto one
    -- new key, and two matching donors for the same user would collide inside a
    -- single statement, where ON CONFLICT cannot help. Deny wins the tie.
    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        INSERT INTO iamuserpermissions (userid, farmid, permissionkey, effect, reason, grantedby, grantedat)
        SELECT DISTINCT ON (up.userid, up.farmid, m.new_key)
               up.userid, up.farmid, m.new_key, up.effect,
               'Carried over from ' || up.permissionkey || ' by migration 286',
               up.grantedby, (now() at time zone 'utc')
        FROM   iamuserpermissions up
        JOIN   (VALUES
                  ('water.reports.view',    'water.assets.view'),
                  ('water.expenses.view',   'water.assets.view'),
                  ('water.expenses.create', 'water.assets.create'),
                  ('water.expenses.edit',   'water.assets.edit'),
                  ('water.expenses.delete', 'water.assets.delete'),
                  ('water.reports.view',    'water.asset-depreciation.view'),
                  ('water.expenses.view',   'water.asset-depreciation.view'),
                  ('water.reports.export',  'water.asset-depreciation.create'),
                  ('water.cash.edit',       'water.asset-depreciation.create'),
                  ('water.reports.export',  'water.asset-depreciation.approve'),
                  ('water.cash.delete',     'water.asset-depreciation.approve')
               ) AS m(old_key, new_key) ON m.old_key = up.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
          AND  (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
        ORDER  BY up.userid, up.farmid, m.new_key,
                  CASE WHEN up.effect = 'Deny' THEN 0 ELSE 1 END
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_added_users = ROW_COUNT;
    END IF;

    RAISE NOTICE '286: % catalog key(s), % role grant(s), % user grant(s) added.',
        v_added_keys, v_added_roles, v_added_users;
END;
$iam$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'asset keys (4 expected)' AS check,
       CASE WHEN COUNT(*) = 4 THEN 'OK' ELSE 'MISSING (' || COUNT(*) || ')' END AS result
FROM   iampermissions WHERE permissionkey LIKE 'water.assets.%'

UNION ALL
SELECT 'depreciation keys (3 expected)',
       CASE WHEN COUNT(*) = 3 THEN 'OK' ELSE 'MISSING (' || COUNT(*) || ')' END
FROM   iampermissions WHERE permissionkey LIKE 'water.asset-depreciation.%'

UNION ALL
SELECT 'at least one role can view the register',
       CASE WHEN COUNT(*) > 0 THEN 'OK' ELSE 'GRANTED TO NOBODY' END
FROM   iamrolepermissions WHERE permissionkey = 'water.assets.view'

UNION ALL
-- Generating depreciation writes to the P&L, so it must not have reached every
-- role that can merely look at the register.
SELECT 'generating depreciation is narrower than viewing assets',
       CASE WHEN (SELECT COUNT(*) FROM iamrolepermissions WHERE permissionkey = 'water.asset-depreciation.create')
               <= (SELECT COUNT(*) FROM iamrolepermissions WHERE permissionkey = 'water.assets.view')
            THEN 'OK' ELSE 'WIDER THAN VIEW' END

UNION ALL
-- 286 must not have touched the poultry keys 273 created.
SELECT 'poultry asset keys untouched',
       CASE WHEN COUNT(*) = 7 THEN 'OK' ELSE 'CHANGED (' || COUNT(*) || ')' END
FROM   iampermissions
WHERE  permissionkey LIKE 'poultry.assets.%'
   OR  permissionkey LIKE 'poultry.asset-depreciation.%';

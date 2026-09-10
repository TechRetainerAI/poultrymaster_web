-- Behavioural checks for migration 273: Asset Register permissions.
--
-- Read-only. Safe to run at any time; still wrap it in BEGIN/ROLLBACK for
-- consistency with the rest of the suite.
--
--   psql ... -X -c "BEGIN;" -f poultry-asset-permissions.test.sql -c "ROLLBACK;"
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **Nobody gained a right they did not already have.** Every grant here is
-- copied from an existing key, so the set of people who can record an asset is
-- exactly the set who could already record an expense, and the set who can
-- charge depreciation to Profit & Loss is exactly the set who could already
-- export a report. Sections C and D assert both directions: nothing lost, and
-- nothing widened.

DO $t$
DECLARE
    v_keys integer;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE 'A0. iam catalog absent    expect present  got absent';
        RETURN;
    END IF;

    -- =====================================================================
    -- A. The catalog.
    -- =====================================================================
    SELECT COUNT(*)::integer INTO v_keys FROM iampermissions p
    WHERE  p.permissionkey LIKE 'poultry.assets.%';
    RAISE NOTICE 'A1. asset keys             expect 4  got %', v_keys;

    SELECT COUNT(*)::integer INTO v_keys FROM iampermissions p
    WHERE  p.permissionkey LIKE 'poultry.asset-depreciation.%';
    RAISE NOTICE 'A2. depreciation keys      expect 3  got %', v_keys;

    -- Stored BARE, like 260 and 263. 255 stored a prefixed form for its own
    -- keys; this file does not widen that discrepancy.
    RAISE NOTICE 'A3. resource is bare       expect assets  got %',
        (SELECT p.resource FROM iampermissions p WHERE p.permissionkey = 'poultry.assets.view');
    RAISE NOTICE 'A4. and grouped with money expect Finance  got %',
        (SELECT p.permissiongroup FROM iampermissions p WHERE p.permissionkey = 'poultry.assets.view');
    RAISE NOTICE 'A5. only for poultry       expect Poultry  got %',
        (SELECT p.companytype FROM iampermissions p WHERE p.permissionkey = 'poultry.assets.view');

    -- =====================================================================
    -- B. The dangerous flags are on the writes that move money or profit.
    -- =====================================================================
    RAISE NOTICE 'B1. viewing is not dangerous expect f  got %',
        (SELECT p.isdangerous FROM iampermissions p WHERE p.permissionkey = 'poultry.assets.view');
    RAISE NOTICE 'B2. disposal is            expect t  got %',
        (SELECT p.isdangerous FROM iampermissions p WHERE p.permissionkey = 'poultry.assets.delete');
    -- Generating depreciation writes to Profit & Loss. It is not a tidy-up.
    RAISE NOTICE 'B3. generating is          expect t  got %',
        (SELECT p.isdangerous FROM iampermissions p
          WHERE p.permissionkey = 'poultry.asset-depreciation.create');
    RAISE NOTICE 'B4. and reversing is       expect t  got %',
        (SELECT p.isdangerous FROM iampermissions p
          WHERE p.permissionkey = 'poultry.asset-depreciation.approve');

    -- =====================================================================
    -- C. THE CLAIM, first direction: nothing was lost.
    -- =====================================================================
    IF to_regclass('public.iamrolepermissions') IS NOT NULL THEN
        RAISE NOTICE 'C1. report viewers see assets expect 0  got %',
            (SELECT COUNT(*)::integer FROM iamrolepermissions rp
              WHERE rp.permissionkey = 'poultry.reports.view'
                AND NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                                WHERE x.roleid = rp.roleid AND x.permissionkey = 'poultry.assets.view'));
        RAISE NOTICE 'C2. expense creators create expect 0  got %',
            (SELECT COUNT(*)::integer FROM iamrolepermissions rp
              WHERE rp.permissionkey = 'poultry.expenses.create'
                AND NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                                WHERE x.roleid = rp.roleid AND x.permissionkey = 'poultry.assets.create'));
        RAISE NOTICE 'C3. exporters can generate expect 0  got %',
            (SELECT COUNT(*)::integer FROM iamrolepermissions rp
              WHERE rp.permissionkey = 'poultry.reports.export'
                AND NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                                WHERE x.roleid = rp.roleid
                                  AND x.permissionkey = 'poultry.asset-depreciation.create'));

        -- =================================================================
        -- D. THE CLAIM, second direction: nothing was widened.
        -- =================================================================
        RAISE NOTICE 'D1. no extra asset creators expect 0  got %',
            (SELECT COUNT(*)::integer FROM iamrolepermissions rp
              WHERE rp.permissionkey = 'poultry.assets.create'
                AND NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                                WHERE x.roleid = rp.roleid AND x.permissionkey = 'poultry.expenses.create'));
        RAISE NOTICE 'D2. no extra disposers     expect 0  got %',
            (SELECT COUNT(*)::integer FROM iamrolepermissions rp
              WHERE rp.permissionkey = 'poultry.assets.delete'
                AND NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                                WHERE x.roleid = rp.roleid AND x.permissionkey = 'poultry.expenses.delete'));
        -- The one that matters: charging profit is narrower than reading it.
        RAISE NOTICE 'D3. no extra P&L charging  expect 0  got %',
            (SELECT COUNT(*)::integer FROM iamrolepermissions rp
              WHERE rp.permissionkey = 'poultry.asset-depreciation.create'
                AND NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                                WHERE x.roleid = rp.roleid AND x.permissionkey = 'poultry.reports.export'));
        RAISE NOTICE 'D4. and it IS narrower     expect t  got %',
            ((SELECT COUNT(*) FROM iamrolepermissions WHERE permissionkey = 'poultry.asset-depreciation.create')
             < (SELECT COUNT(*) FROM iamrolepermissions WHERE permissionkey = 'poultry.assets.view'));
    END IF;

    -- =====================================================================
    -- E. Per-user grants keep their effect.
    -- =====================================================================
    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        -- A Deny copied as an Allow would silently hand somebody a right an
        -- administrator had deliberately taken away.
        RAISE NOTICE 'E1. no Deny became Allow   expect 0  got %',
            (SELECT COUNT(*)::integer
               FROM iamuserpermissions up
               JOIN iamuserpermissions src
                 ON src.userid = up.userid AND src.farmid = up.farmid
                AND src.permissionkey = 'poultry.expenses.create'
              WHERE up.permissionkey = 'poultry.assets.create'
                AND up.effect <> src.effect);
    END IF;
END
$t$;

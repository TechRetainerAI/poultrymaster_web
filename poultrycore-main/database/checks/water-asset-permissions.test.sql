-- Behavioural checks for migration 286: the water asset-register IAM keys.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK.
--
--   psql ... -X -c "BEGIN;" -f water-asset-permissions.test.sql -c "ROLLBACK;"
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **Generating depreciation is narrower than looking at the register.** Adding a
-- delivery truck to a list and changing what the owner reads as profit are not
-- the same act, and 286 exists to keep them separable. Section C is that check.
--
-- As in 276's checks, the donor keys cannot be assumed to exist -- the water IAM
-- catalog is seeded outside this repo -- so this file asserts the invariants
-- that hold whichever donors turned out to be real.

DO $t$
DECLARE
    v_aview integer;
    v_dcreate integer;
    v_dapprove integer;
    v_donor integer;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '   iampermissions not present, nothing to check.';
        RETURN;
    END IF;

    -- =====================================================================
    -- A. The catalog: two resources, seven keys.
    -- =====================================================================
    RAISE NOTICE 'A1. four asset keys        expect        4  got %',
        (SELECT COUNT(*)::integer FROM iampermissions WHERE permissionkey LIKE 'water.assets.%');
    RAISE NOTICE 'A2. three depreciation keys expect        3  got %',
        (SELECT COUNT(*)::integer FROM iampermissions WHERE permissionkey LIKE 'water.asset-depreciation.%');
    RAISE NOTICE 'A3. all Water-scoped       expect        7  got %',
        (SELECT COUNT(*)::integer FROM iampermissions
          WHERE (permissionkey LIKE 'water.assets.%' OR permissionkey LIKE 'water.asset-depreciation.%')
            AND companytype = 'Water');
    RAISE NOTICE 'A4. all in the Finance group expect        7  got %',
        (SELECT COUNT(*)::integer FROM iampermissions
          WHERE (permissionkey LIKE 'water.assets.%' OR permissionkey LIKE 'water.asset-depreciation.%')
            AND permissiongroup = 'Finance');
    -- Ending an asset's life, and reversing a posted charge, are the two
    -- dangerous ones.
    RAISE NOTICE 'A5. assets.delete is dangerous expect        t  got %',
        (SELECT isdangerous FROM iampermissions WHERE permissionkey = 'water.assets.delete');
    RAISE NOTICE 'A6. depreciation.approve is dangerous expect        t  got %',
        (SELECT isdangerous FROM iampermissions WHERE permissionkey = 'water.asset-depreciation.approve');
    RAISE NOTICE 'A7. assets.view is not     expect        f  got %',
        (SELECT isdangerous FROM iampermissions WHERE permissionkey = 'water.assets.view');
    -- Depreciation has no edit or delete: a posted charge is corrected by
    -- reversal and adjustment, never by editing the row.
    RAISE NOTICE 'A8. depreciation has no edit/delete expect        0  got %',
        (SELECT COUNT(*)::integer FROM iampermissions
          WHERE permissionkey LIKE 'water.asset-depreciation.%'
            AND action IN ('edit', 'delete'));

    IF to_regclass('public.iamrolepermissions') IS NULL THEN
        RAISE NOTICE '   iamrolepermissions not present, skipping grant checks.';
        RETURN;
    END IF;

    SELECT COUNT(*)::integer INTO v_aview    FROM iamrolepermissions WHERE permissionkey = 'water.assets.view';
    SELECT COUNT(*)::integer INTO v_dcreate  FROM iamrolepermissions WHERE permissionkey = 'water.asset-depreciation.create';
    SELECT COUNT(*)::integer INTO v_dapprove FROM iamrolepermissions WHERE permissionkey = 'water.asset-depreciation.approve';

    -- =====================================================================
    -- B. Somebody can actually reach the register.
    -- =====================================================================
    RAISE NOTICE 'B1. at least one role can view it expect        t  got %', (v_aview > 0);
    SELECT COUNT(*)::integer INTO v_donor FROM iamrolepermissions
     WHERE permissionkey IN ('water.reports.view', 'water.expenses.view', 'water.expenses.create',
                             'water.expenses.edit', 'water.expenses.delete',
                             'water.reports.export', 'water.cash.edit', 'water.cash.delete');
    RAISE NOTICE 'B2. a donor key existed    expect        t  got %', (v_donor > 0);

    -- =====================================================================
    -- C. THE CLAIM. Writing to the P&L is narrower than reading the register.
    -- =====================================================================
    RAISE NOTICE 'C1. generating is no wider than viewing expect        t  got %', (v_dcreate <= v_aview);
    RAISE NOTICE 'C2. reversing is no wider either expect        t  got %', (v_dapprove <= v_aview);
    -- And nobody got it without holding a privileged donor.
    RAISE NOTICE 'C3. generating came only from its donors expect        0  got %',
        (SELECT COUNT(*)::integer FROM iamrolepermissions rp
          WHERE rp.permissionkey = 'water.asset-depreciation.create'
            AND NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                            WHERE x.roleid = rp.roleid
                              AND x.permissionkey IN ('water.reports.export', 'water.cash.edit')));
    -- Every role that can generate can also read what it generated.
    RAISE NOTICE 'C4. every generator can view the history expect        0  got %',
        (SELECT COUNT(*)::integer FROM iamrolepermissions rp
          WHERE rp.permissionkey = 'water.asset-depreciation.create'
            AND NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                            WHERE x.roleid = rp.roleid
                              AND x.permissionkey = 'water.asset-depreciation.view'));

    -- =====================================================================
    -- D. Creating and deleting assets are narrower than viewing them.
    -- =====================================================================
    RAISE NOTICE 'D1. create is no wider than view expect        t  got %',
        ((SELECT COUNT(*) FROM iamrolepermissions WHERE permissionkey = 'water.assets.create') <= v_aview);
    RAISE NOTICE 'D2. delete is no wider than view expect        t  got %',
        ((SELECT COUNT(*) FROM iamrolepermissions WHERE permissionkey = 'water.assets.delete') <= v_aview);
    -- Assets ride the expenses rights: nobody can add an asset who could not
    -- already record the same money as a bill.
    RAISE NOTICE 'D3. asset creators can record expenses expect        0  got %',
        (SELECT COUNT(*)::integer FROM iamrolepermissions rp
          WHERE rp.permissionkey = 'water.assets.create'
            AND NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                            WHERE x.roleid = rp.roleid
                              AND x.permissionkey = 'water.expenses.create'));

    -- =====================================================================
    -- E. The poultry side is untouched.
    -- =====================================================================
    RAISE NOTICE 'E1. poultry asset keys still there expect        7  got %',
        (SELECT COUNT(*)::integer FROM iampermissions
          WHERE permissionkey LIKE 'poultry.assets.%'
             OR permissionkey LIKE 'poultry.asset-depreciation.%');

    -- =====================================================================
    -- F. Per-user grants kept their effect.
    -- =====================================================================
    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        RAISE NOTICE 'F1. no duplicate user grants expect        0  got %',
            (SELECT COUNT(*)::integer FROM (
                SELECT userid, farmid, permissionkey
                FROM   iamuserpermissions
                WHERE  permissionkey LIKE 'water.assets.%'
                    OR permissionkey LIKE 'water.asset-depreciation.%'
                GROUP  BY userid, farmid, permissionkey
                HAVING COUNT(*) > 1) d);
    END IF;
END
$t$;

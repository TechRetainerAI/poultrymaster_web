-- Behavioural checks for migration 276: the water financial-settings IAM keys.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK.
--
--   psql ... -X -c "BEGIN;" -f water-financial-settings-permissions.test.sql -c "ROLLBACK;"
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **The page is reachable, and editing it is narrower than reading it.** A
-- permissions migration has two ways to fail and they pull in opposite
-- directions: grant to nobody and the page 403s for everyone on day one; grant
-- too widely and a P&L-shaping decision lands in the hands of every person who
-- can open a report. Sections B and C check both ends.
--
-- WHY THIS FILE IS LOOSER THAN 263'S
-- ----------------------------------
-- 263 can assert "every poultry.reports.view role also has
-- poultry.financial-settings.view", because it knows poultry.reports.view is in
-- the catalog. The water catalog is seeded outside this repo, so 276 lists
-- several donors and this file cannot assume any particular one exists. It
-- asserts the INVARIANTS instead -- reachable, narrower than view, scoped to
-- Water, poultry untouched -- which hold whichever donors turned out to be real.

DO $t$
DECLARE
    v_view  integer;
    v_edit  integer;
    v_donor integer;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '   iampermissions not present, nothing to check.';
        RETURN;
    END IF;

    -- =====================================================================
    -- A. The catalog.
    -- =====================================================================
    RAISE NOTICE 'A1. two keys exist         expect        2  got %',
        (SELECT COUNT(*)::integer FROM iampermissions
          WHERE permissionkey LIKE 'water.financial-settings.%');
    RAISE NOTICE 'A2. they are Water-scoped  expect        2  got %',
        (SELECT COUNT(*)::integer FROM iampermissions
          WHERE permissionkey LIKE 'water.financial-settings.%' AND companytype = 'Water');
    RAISE NOTICE 'A3. and in the Finance group expect        2  got %',
        (SELECT COUNT(*)::integer FROM iampermissions
          WHERE permissionkey LIKE 'water.financial-settings.%' AND permissiongroup = 'Finance');
    -- Edit changes what the owner reads as profit, so any UI honouring the flag
    -- should confirm before saving.
    RAISE NOTICE 'A4. edit is flagged dangerous expect        t  got %',
        (SELECT isdangerous FROM iampermissions WHERE permissionkey = 'water.financial-settings.edit');
    RAISE NOTICE 'A5. view is not            expect        f  got %',
        (SELECT isdangerous FROM iampermissions WHERE permissionkey = 'water.financial-settings.view');
    -- Nothing else: the page reads two values and writes two values.
    RAISE NOTICE 'A6. no create/approve/export keys expect        0  got %',
        (SELECT COUNT(*)::integer FROM iampermissions
          WHERE permissionkey LIKE 'water.financial-settings.%'
            AND action NOT IN ('view', 'edit'));

    IF to_regclass('public.iamrolepermissions') IS NULL THEN
        RAISE NOTICE '   iamrolepermissions not present, skipping grant checks.';
        RETURN;
    END IF;

    SELECT COUNT(*)::integer INTO v_view FROM iamrolepermissions
     WHERE permissionkey = 'water.financial-settings.view';
    SELECT COUNT(*)::integer INTO v_edit FROM iamrolepermissions
     WHERE permissionkey = 'water.financial-settings.edit';

    -- =====================================================================
    -- B. Somebody can actually reach the page.
    -- =====================================================================
    RAISE NOTICE 'B1. at least one role can view it expect        t  got %', (v_view > 0);
    -- If NO donor existed the whole file was a no-op, which is worth saying out
    -- loud rather than passing quietly.
    SELECT COUNT(*)::integer INTO v_donor FROM iamrolepermissions
     WHERE permissionkey IN ('water.reports.view', 'water.cash.view',
                             'water.reports.export', 'water.cash.edit');
    RAISE NOTICE 'B2. a donor key existed    expect        t  got %', (v_donor > 0);

    -- =====================================================================
    -- C. Editing is narrower than viewing.
    -- =====================================================================
    RAISE NOTICE 'C1. edit is no wider than view expect        t  got %', (v_edit <= v_view);
    -- And every editor can also see the page they are editing.
    RAISE NOTICE 'C2. every editor can view it expect        0  got %',
        (SELECT COUNT(*)::integer FROM iamrolepermissions rp
          WHERE rp.permissionkey = 'water.financial-settings.edit'
            AND NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                            WHERE x.roleid = rp.roleid
                              AND x.permissionkey = 'water.financial-settings.view'));
    -- Nobody got edit without holding one of the two privileged donors.
    RAISE NOTICE 'C3. edit came only from its donors expect        0  got %',
        (SELECT COUNT(*)::integer FROM iamrolepermissions rp
          WHERE rp.permissionkey = 'water.financial-settings.edit'
            AND NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                            WHERE x.roleid = rp.roleid
                              AND x.permissionkey IN ('water.reports.export', 'water.cash.edit')));

    -- =====================================================================
    -- D. The poultry side is untouched.
    -- =====================================================================
    RAISE NOTICE 'D1. poultry keys still there expect        2  got %',
        (SELECT COUNT(*)::integer FROM iampermissions
          WHERE permissionkey LIKE 'poultry.financial-settings.%');
    RAISE NOTICE 'D2. no water key leaked into Poultry expect        0  got %',
        (SELECT COUNT(*)::integer FROM iampermissions
          WHERE permissionkey LIKE 'water.%' AND companytype = 'Poultry');

    -- =====================================================================
    -- E. Per-user grants kept their effect.
    -- =====================================================================
    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        -- A Deny must never have been copied across as an Allow.
        RAISE NOTICE 'E1. no Deny became an Allow expect        0  got %',
            (SELECT COUNT(*)::integer
               FROM iamuserpermissions up
               JOIN (VALUES
                       ('water.reports.view',   'water.financial-settings.view'),
                       ('water.cash.view',      'water.financial-settings.view'),
                       ('water.reports.export', 'water.financial-settings.edit'),
                       ('water.cash.edit',      'water.financial-settings.edit')
                    ) AS m(old_key, new_key) ON m.old_key = up.permissionkey
               JOIN iamuserpermissions n
                 ON n.userid = up.userid AND n.farmid = up.farmid
                AND n.permissionkey = m.new_key
              WHERE up.effect = 'Deny' AND n.effect <> 'Deny');
        -- One row per (user, farm, key): the DISTINCT ON in 276 is what makes
        -- two matching donors collapse rather than collide.
        RAISE NOTICE 'E2. no duplicate user grants expect        0  got %',
            (SELECT COUNT(*)::integer FROM (
                SELECT userid, farmid, permissionkey
                FROM   iamuserpermissions
                WHERE  permissionkey LIKE 'water.financial-settings.%'
                GROUP  BY userid, farmid, permissionkey
                HAVING COUNT(*) > 1) d);
    END IF;
END
$t$;

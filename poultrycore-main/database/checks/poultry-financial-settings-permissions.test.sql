-- Behavioural checks for migration 263: financial-settings permissions.
--
-- Run inside a transaction you ROLL BACK. Nothing here writes; it only reads
-- the IAM catalog and grant tables.
--
--   psql ... -X -c "BEGIN;" -f poultry-financial-settings-permissions.test.sql -c "ROLLBACK;"
--
-- The claims:
--   1. Two keys, view and edit. Nothing to create, approve or export.
--   2. **Everyone who can read the P&L can see the setting.** The setting is
--      the explanation for a number in that report; hiding it would leave the
--      report unexplainable without making anything safer.
--   3. **Editing is strictly narrower than viewing.** 8 roles read reports and
--      6 export them; granting edit to all 8 would hand a P&L-shaping decision
--      to everyone who can open a report.
--   4. Edit is flagged dangerous and view is not.
--   5. Nothing else in the catalog moved.

DO $t$
DECLARE
    v_keys      integer;
    v_lostview  integer;
    v_widened   integer;
    v_viewroles integer;
    v_editroles integer;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE EXCEPTION 'iampermissions is not present; these checks cannot run.';
    END IF;

    SELECT COUNT(*) INTO v_keys FROM iampermissions
    WHERE  permissionkey LIKE 'poultry.financial-settings.%';
    RAISE NOTICE 'A1. two keys exist         expect        2  got %', v_keys;

    RAISE NOTICE 'A2. view and edit only     expect        0  got %',
        (SELECT COUNT(*) FROM iampermissions
          WHERE permissionkey LIKE 'poultry.financial-settings.%'
            AND action NOT IN ('view', 'edit'));
    RAISE NOTICE 'A3. filed under Finance    expect        2  got %',
        (SELECT COUNT(*) FROM iampermissions
          WHERE permissionkey LIKE 'poultry.financial-settings.%'
            AND permissiongroup = 'Finance' AND companytype = 'Poultry');
    -- The bare resource, like its neighbours. 255 stored the prefixed key on
    -- its four; 263 does not repeat that.
    RAISE NOTICE 'A4. resource is bare       expect        2  got %',
        (SELECT COUNT(*) FROM iampermissions
          WHERE permissionkey LIKE 'poultry.financial-settings.%'
            AND resource = 'financial-settings');

    -- Editing changes what the owner reads as profit from here on.
    RAISE NOTICE 'A5. edit is dangerous      expect        t  got %',
        (SELECT isdangerous FROM iampermissions WHERE permissionkey = 'poultry.financial-settings.edit');
    RAISE NOTICE 'A6. view is not            expect        f  got %',
        (SELECT isdangerous FROM iampermissions WHERE permissionkey = 'poultry.financial-settings.view');

    -- =====================================================================
    -- B. Who got what.
    -- =====================================================================
    SELECT COUNT(*) INTO v_viewroles FROM iamrolepermissions
    WHERE  permissionkey = 'poultry.financial-settings.view';
    SELECT COUNT(*) INTO v_editroles FROM iamrolepermissions
    WHERE  permissionkey = 'poultry.financial-settings.edit';
    RAISE NOTICE '   (% role(s) can view, % can edit)', v_viewroles, v_editroles;

    SELECT COUNT(*) INTO v_lostview
    FROM   iamrolepermissions rp
    WHERE  rp.permissionkey = 'poultry.reports.view'
      AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                       WHERE x.roleid = rp.roleid
                         AND x.permissionkey = 'poultry.financial-settings.view');
    RAISE NOTICE 'B1. report viewers can see expect        0  got %', v_lostview;

    SELECT COUNT(*) INTO v_widened
    FROM   iamrolepermissions rp
    WHERE  rp.permissionkey = 'poultry.financial-settings.edit'
      AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                       WHERE x.roleid = rp.roleid
                         AND x.permissionkey = 'poultry.reports.export');
    RAISE NOTICE 'B2. edit is not widened    expect        0  got %', v_widened;

    -- The point of splitting the two grants: fewer people may change it than
    -- may look at it. If these ever match, the split has quietly stopped
    -- meaning anything.
    RAISE NOTICE 'B3. edit is narrower       expect        t  got %', (v_editroles < v_viewroles);

    -- =====================================================================
    -- C. Nothing else moved.
    -- =====================================================================
    RAISE NOTICE 'C1. 255 keys untouched     expect       16  got %',
        (SELECT COUNT(*) FROM iampermissions
          WHERE permissionkey LIKE 'poultry.cash-transfers.%'
             OR permissionkey LIKE 'poultry.owner-money.%'
             OR permissionkey LIKE 'poultry.loans.%'
             OR permissionkey LIKE 'poultry.loan-payments.%');
    -- The item override rides poultry.raw-materials.edit rather than a key of
    -- its own; see 263's header for why. If that key ever disappears, the item
    -- form's financial section becomes unreachable.
    RAISE NOTICE 'C2. raw-materials.edit lives expect        t  got %',
        (SELECT EXISTS (SELECT 1 FROM iampermissions WHERE permissionkey = 'poultry.raw-materials.edit'));
END
$t$;

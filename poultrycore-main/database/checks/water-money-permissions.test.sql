-- Behavioural checks for migration 260: water money permissions.
--
-- Run inside a transaction you ROLL BACK. Nothing here writes; it only reads
-- the IAM catalog and grant tables, so it is safe either way.
--
--   psql ... -X -c "BEGIN;" -f water-money-permissions.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its effect in one pass, concatenate 260
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- The claims:
--   1. Sixteen keys exist -- four resources times four actions.
--   2. **Nobody lost access.** Every role that could see cash can still see all
--      four new pages. This is the whole reason the migration copies grants
--      rather than just re-pointing routes: a missed copy shows up here as a
--      person locked out of a page they used yesterday.
--   3. **Nobody gained access either.** Reversal (approve) went only to roles
--      that already held the destructive cash right, not to everyone who can
--      create. Widening is as much a bug as losing.
--   4. The dangerous flag is on approve and only on approve.
--   5. No export key was invented for pages that cannot export.

DO $t$
DECLARE
    v_keys      integer;
    v_lostview  integer;
    v_lostedit  integer;
    v_widened   integer;
    v_dangerous integer;
    v_export    integer;
    v_cashview  integer;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE EXCEPTION 'iampermissions is not present; these checks cannot run.';
    END IF;

    -- =====================================================================
    -- A. The catalog.
    -- =====================================================================
    SELECT COUNT(*) INTO v_keys FROM iampermissions
    WHERE  permissionkey LIKE 'water.cash-transfers.%'
       OR  permissionkey LIKE 'water.owner-money.%'
       OR  permissionkey LIKE 'water.loans.%'
       OR  permissionkey LIKE 'water.loan-payments.%';
    RAISE NOTICE 'A1. sixteen keys exist      expect       16  got %', v_keys;

    -- The resource column holds the BARE name, like every other row in the
    -- catalog and like the IAM matrix's grouping key expects. 255 stored the
    -- prefixed key on the poultry side; 260 does not repeat that.
    RAISE NOTICE 'A2. all four resources      expect        4  got %',
        (SELECT COUNT(DISTINCT resource) FROM iampermissions
          WHERE resource IN ('cash-transfers', 'owner-money', 'loans', 'loan-payments')
            AND module = 'water');
    RAISE NOTICE 'A3. filed under Water       expect        4  got %',
        (SELECT COUNT(DISTINCT resource) FROM iampermissions
          WHERE resource IN ('cash-transfers', 'owner-money', 'loans', 'loan-payments')
            AND module = 'water' AND companytype = 'Water' AND permissiongroup = 'Finance');
    -- And it groups with its neighbours rather than standing apart from them.
    RAISE NOTICE 'A3b. bare, like water.cash  expect        t  got %',
        (SELECT NOT EXISTS (SELECT 1 FROM iampermissions
                             WHERE module = 'water' AND resource LIKE 'water.%'));

    -- The dangerous flag marks reversal, and nothing else.
    SELECT COUNT(*) INTO v_dangerous FROM iampermissions
    WHERE  module = 'water'
      AND  resource IN ('cash-transfers', 'owner-money', 'loans', 'loan-payments')
      AND  isdangerous <> (action = 'approve');
    RAISE NOTICE 'A4. dangerous = approve     expect        0  got %', v_dangerous;

    -- No export key: none of these pages has an export endpoint to gate.
    SELECT COUNT(*) INTO v_export FROM iampermissions
    WHERE  module = 'water'
      AND  resource IN ('cash-transfers', 'owner-money', 'loans', 'loan-payments')
      AND  action = 'export';
    RAISE NOTICE 'A5. no invented export key  expect        0  got %', v_export;

    -- =====================================================================
    -- B. Nobody lost access.
    -- =====================================================================
    SELECT COUNT(*) INTO v_cashview FROM iamrolepermissions
    WHERE  permissionkey = 'water.cash.view';
    RAISE NOTICE '   (% role(s) can see water cash today)', v_cashview;

    SELECT COUNT(*) INTO v_lostview
    FROM   iamrolepermissions rp
    CROSS  JOIN (VALUES ('water.cash-transfers'), ('water.owner-money'),
                        ('water.loans'), ('water.loan-payments')) AS res(resource_key)
    WHERE  rp.permissionkey = 'water.cash.view'
      AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                       WHERE x.roleid = rp.roleid
                         AND x.permissionkey = res.resource_key || '.view');
    RAISE NOTICE 'B1. no viewer lost a page   expect        0  got %', v_lostview;

    SELECT COUNT(*) INTO v_lostedit
    FROM   iamrolepermissions rp
    CROSS  JOIN (VALUES ('water.cash-transfers'), ('water.owner-money'),
                        ('water.loans'), ('water.loan-payments')) AS res(resource_key)
    WHERE  rp.permissionkey = 'water.cash.create'
      AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                       WHERE x.roleid = rp.roleid
                         AND x.permissionkey = res.resource_key || '.create');
    RAISE NOTICE 'B2. no creator lost a page  expect        0  got %', v_lostedit;

    -- Per-user grants keep their effect, so a Deny stays a Deny.
    RAISE NOTICE 'B3. user Denys stayed Denys expect        0  got %',
        (SELECT COUNT(*) FROM iamuserpermissions up
          WHERE up.permissionkey LIKE 'water.cash-transfers.%'
            AND up.effect <> COALESCE((SELECT o.effect FROM iamuserpermissions o
                                        WHERE o.userid = up.userid AND o.farmid = up.farmid
                                          AND o.permissionkey = 'water.cash.'
                                              || split_part(up.permissionkey, '.', 3)
                                        LIMIT 1), up.effect));

    -- =====================================================================
    -- C. Nobody gained access either.
    -- =====================================================================
    -- Reversal is the destructive act. It went to holders of water.cash.delete
    -- and to nobody else -- granting it to every creator would have roughly
    -- doubled the number of people who can undo a posted movement.
    SELECT COUNT(*) INTO v_widened
    FROM   iamrolepermissions rp
    WHERE  rp.permissionkey IN ('water.cash-transfers.approve', 'water.owner-money.approve',
                                'water.loans.approve', 'water.loan-payments.approve')
      AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                       WHERE x.roleid = rp.roleid
                         AND x.permissionkey = 'water.cash.delete');
    RAISE NOTICE 'C1. approve is not widened  expect        0  got %', v_widened;

    -- And the poultry keys were not disturbed on the way past.
    RAISE NOTICE 'C2. poultry keys untouched  expect       16  got %',
        (SELECT COUNT(*) FROM iampermissions
          WHERE permissionkey LIKE 'poultry.cash-transfers.%'
             OR permissionkey LIKE 'poultry.owner-money.%'
             OR permissionkey LIKE 'poultry.loans.%'
             OR permissionkey LIKE 'poultry.loan-payments.%');
END
$t$;

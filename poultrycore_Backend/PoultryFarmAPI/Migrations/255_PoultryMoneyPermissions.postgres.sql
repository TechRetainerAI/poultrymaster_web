-- =============================================================================
-- 255_PoultryMoneyPermissions.postgres.sql
--
-- Purpose
-- -------
-- Cash Transfers, Owner Money and Loans all shipped mapped to one permission:
-- poultry.cash. So anybody who could SEE the cash page could reverse a transfer,
-- record an owner draw, take out a loan and reverse a repayment. That was fine
-- while none of those pages existed; it is not fine now that all three do.
--
-- This file gives each of them a resource of its own, and -- the part that
-- matters more -- carries the existing grants across so nobody loses access on
-- the way.
--
-- WHY CARRYING THE GRANTS OVER IS THE WHOLE JOB
-- ---------------------------------------------
-- 25 role grants and 26 user grants currently name poultry.cash.*. Re-pointing
-- the routes without copying those would leave every one of them covering
-- nothing, and the first person to open Cash Transfers after a deploy would be
-- refused. So each new key is granted to exactly whoever holds the matching
-- cash key today:
--
--   <resource>.view     to everyone with poultry.cash.view
--   <resource>.create   to everyone with poultry.cash.create
--   <resource>.edit     to everyone with poultry.cash.edit
--   <resource>.approve  to everyone with poultry.cash.DELETE
--
-- That last line is the judgement call. Reversing a posted movement is the
-- destructive act in these modules, and delete is the closest thing the cash
-- resource has to a destructive right -- 3 roles hold it, against 6 that can
-- merely look. Granting approve to everyone who can create would have handed
-- reversal to twice as many people as hold it now.
--
-- THE CANCEL QUIRK, RECORDED RATHER THAN HIDDEN
-- ---------------------------------------------
-- IamPermissionMap.ResolveAction turns /reverse into the `approve` action, but
-- NOT /cancel -- that is not in ApproveSegments, so POST /loans/{id}/cancel
-- resolves to poultry.loans.CREATE. The honest options were to widen
-- ApproveSegments (which would silently re-resolve every other /cancel route in
-- the API, including payroll and transfers) or to hang an explicit
-- [RequirePermission] on the action -- which would make it one of the first
-- HARD-enforced endpoints in a system still running enforcement in shadow mode.
-- Neither belongs in this migration, so .create is seeded, the quirk is written
-- down here and in the map, and the decision stays open.
--
-- EFFECT ON TODAY'S NUMBERS: none. This file touches only the IAM catalog and
-- grant tables. No money, no ledger, no balance.
--
-- Order: after 254.
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
        RAISE NOTICE '255: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    -- ---- 1. the catalog ---------------------------------------------------
    -- Four resources, each with the actions its pages actually perform. No
    -- export yet: none of the three has an export endpoint to gate.
    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT r.resource_key || '.' || a.action, 'poultry', r.resource_key, a.action,
           'Finance', r.label, r.description, 'Poultry',
           -- Reversing a posted movement is the dangerous one in every case.
           a.action = 'approve', r.sort
    FROM (VALUES
            ('poultry.cash-transfers', 'Cash Transfers',
             'Move money between the farm''s own cash accounts. Approve covers reversing a posted transfer.', 84),
            ('poultry.owner-money', 'Owner Money',
             'Record what the owner puts into the business and takes out. Approve covers reversing a posted record.', 85),
            ('poultry.loans', 'Loans',
             'Borrowed money and what is still owed. Create covers cancelling a loan that was never drawn.', 86),
            ('poultry.loan-payments', 'Loan Repayments',
             'Repayments split into principal, interest and fees. Approve covers reversing a posted repayment.', 87)
         ) AS r(resource_key, label, description, sort)
    CROSS JOIN (VALUES ('view'), ('create'), ('edit'), ('approve')) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;

    GET DIAGNOSTICS v_added_keys = ROW_COUNT;

    -- ---- 2. carry the ROLE grants across ----------------------------------
    IF to_regclass('public.iamrolepermissions') IS NOT NULL THEN
        INSERT INTO iamrolepermissions (roleid, permissionkey)
        SELECT rp.roleid, n.new_key
        FROM   iamrolepermissions rp
        JOIN   (VALUES
                  ('poultry.cash.view',   'view'),
                  ('poultry.cash.create', 'create'),
                  ('poultry.cash.edit',   'edit'),
                  -- see the header: delete is the closest existing dangerous right
                  ('poultry.cash.delete', 'approve')
               ) AS m(old_key, action) ON m.old_key = rp.permissionkey
        CROSS  JOIN (VALUES ('poultry.cash-transfers'), ('poultry.owner-money'),
                            ('poultry.loans'), ('poultry.loan-payments')) AS res(resource_key)
        CROSS  JOIN LATERAL (SELECT res.resource_key || '.' || m.action AS new_key) n
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = n.new_key)
        ON CONFLICT (roleid, permissionkey) DO NOTHING;

        GET DIAGNOSTICS v_added_roles = ROW_COUNT;
    END IF;

    -- ---- 3. carry the USER grants across ----------------------------------
    -- Per-user grants are farm-scoped and carry an effect; both are copied
    -- verbatim so a Deny stays a Deny.
    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        INSERT INTO iamuserpermissions (userid, farmid, permissionkey, effect, reason, grantedby, grantedat)
        SELECT up.userid, up.farmid, n.new_key, up.effect,
               'Carried over from ' || up.permissionkey || ' by migration 255',
               up.grantedby, (now() at time zone 'utc')
        FROM   iamuserpermissions up
        JOIN   (VALUES
                  ('poultry.cash.view',   'view'),
                  ('poultry.cash.create', 'create'),
                  ('poultry.cash.edit',   'edit'),
                  ('poultry.cash.delete', 'approve')
               ) AS m(old_key, action) ON m.old_key = up.permissionkey
        CROSS  JOIN (VALUES ('poultry.cash-transfers'), ('poultry.owner-money'),
                            ('poultry.loans'), ('poultry.loan-payments')) AS res(resource_key)
        CROSS  JOIN LATERAL (SELECT res.resource_key || '.' || m.action AS new_key) n
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = n.new_key)
          -- Expired grants are not revived on the way past.
          AND  (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;

        GET DIAGNOSTICS v_added_users = ROW_COUNT;
    END IF;

    RAISE NOTICE '255: % catalog key(s), % role grant(s), % user grant(s) added.',
        v_added_keys, v_added_roles, v_added_users;
END;
$iam$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'catalog keys (16 expected)' AS check,
       CASE WHEN COUNT(*) = 16 THEN 'OK' ELSE 'MISSING (' || COUNT(*) || ')' END AS result
FROM   iampermissions
WHERE  permissionkey LIKE 'poultry.cash-transfers.%'
   OR  permissionkey LIKE 'poultry.owner-money.%'
   OR  permissionkey LIKE 'poultry.loans.%'
   OR  permissionkey LIKE 'poultry.loan-payments.%'

UNION ALL
-- Nobody who could see cash may have lost sight of the new pages.
SELECT 'every cash viewer still sees transfers',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'LOST ' || COUNT(*) END
FROM   iamrolepermissions rp
WHERE  rp.permissionkey = 'poultry.cash.view'
  AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                   WHERE x.roleid = rp.roleid
                     AND x.permissionkey = 'poultry.cash-transfers.view')

UNION ALL
SELECT 'every cash viewer still sees loans',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'LOST ' || COUNT(*) END
FROM   iamrolepermissions rp
WHERE  rp.permissionkey = 'poultry.cash.view'
  AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                   WHERE x.roleid = rp.roleid
                     AND x.permissionkey = 'poultry.loans.view');

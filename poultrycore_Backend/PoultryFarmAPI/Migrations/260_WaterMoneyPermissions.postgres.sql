-- =============================================================================
-- 260_WaterMoneyPermissions.postgres.sql
--
-- Purpose
-- -------
-- The water twin of 255. Cash Transfers were mapped to one permission,
-- water.cash, and Owner Money and Loans would inherit the same mapping the
-- moment their routes were added. So anybody who could SEE the cash page could
-- reverse a transfer, record an owner draw, take out a loan and reverse a
-- repayment. That was tolerable while none of those pages existed; it is not
-- tolerable now that all three do.
--
-- This file gives each of them a resource of its own, and -- the part that
-- matters more -- carries the existing grants across so nobody loses access on
-- the way.
--
-- WHY CARRYING THE GRANTS OVER IS THE WHOLE JOB
-- ---------------------------------------------
-- 19 role grants and 26 user grants currently name water.cash.*. Re-pointing
-- the routes without copying those would leave every one of them covering
-- nothing, and the first person to open Cash Transfers after a deploy would be
-- refused. So each new key is granted to exactly whoever holds the matching
-- cash key today:
--
--   <resource>.view     to everyone with water.cash.view
--   <resource>.create   to everyone with water.cash.create
--   <resource>.edit     to everyone with water.cash.edit
--   <resource>.approve  to everyone with water.cash.DELETE
--
-- That last line is the judgement call, and it is the same one 255 made.
-- Reversing a posted movement is the destructive act in these modules, and
-- delete is the closest thing the cash resource has to a destructive right --
-- 3 roles hold it, against 6 that can merely look. Granting approve to everyone
-- who can create would have handed reversal to nearly twice as many people as
-- hold it now.
--
-- water.cash.EXPORT is deliberately not carried anywhere. None of the three new
-- pages has an export endpoint to gate, so seeding an export key would create a
-- permission that grants nothing and has to be explained later.
--
-- THE CANCEL QUIRK, RECORDED RATHER THAN HIDDEN
-- ---------------------------------------------
-- IamPermissionMap.ResolveAction turns /reverse into the `approve` action, but
-- NOT /cancel -- that is not in ApproveSegments, so POST /loans/{id}/cancel
-- resolves to water.loans.CREATE. The honest options were to widen
-- ApproveSegments (which would silently re-resolve every other /cancel route in
-- the API, including payroll and transfers) or to hang an explicit
-- [RequirePermission] on the action -- which would make it one of the first
-- HARD-enforced endpoints in a system still running enforcement in shadow mode.
-- Neither belongs in this migration, so .create is seeded, the quirk is written
-- down here and in the map, and the decision stays open. Identical to poultry,
-- on purpose: two rails with different answers to the same question is worse
-- than one open question.
--
-- THE resource COLUMN, AND A POULTRY ROW THIS FILE DOES NOT TOUCH
-- ---------------------------------------------------------------
-- iampermissions.resource holds the BARE resource -- 'cash', 'expenses',
-- 'daily-closing' -- while permissionkey holds module.resource.action. The IAM
-- admin matrix groups its rows by that column, so it has to match the rest of
-- the catalog.
--
-- 255 got this wrong on the poultry side: its four new resources were stored as
-- 'poultry.cash-transfers' and so on, prefix and all. The matrix still renders
-- them (each value groups to itself and carries its own label), so nothing is
-- broken today -- but those four rows do not read like their 100-odd
-- neighbours.
--
-- This file stores the bare resource, matching the catalog rather than
-- matching 255's slip. Correcting the poultry rows is a one-line UPDATE and it
-- belongs in a poultry migration, not in this one: a file named
-- WaterMoneyPermissions has no business rewriting poultry metadata, and the
-- discrepancy is harmless until someone gets round to it.
--
-- EFFECT ON TODAY'S NUMBERS: none. This file touches only the IAM catalog and
-- grant tables. No money, no ledger, no balance.
--
-- Order: after 259.
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
        RAISE NOTICE '260: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    -- ---- 1. the catalog ---------------------------------------------------
    -- Four resources, each with the actions its pages actually perform. The
    -- sort orders continue the water Finance run: expenses 80, cash 81, daily
    -- closing 82, reconciliation 83, and these four next.
    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT r.resource_key || '.' || a.action, 'water',
           -- The bare resource, NOT the prefixed key. See the header note.
           split_part(r.resource_key, '.', 2), a.action,
           'Finance', r.label, r.description, 'Water',
           -- Reversing a posted movement is the dangerous one in every case.
           a.action = 'approve', r.sort
    FROM (VALUES
            ('water.cash-transfers', 'Cash Transfers',
             'Move money between the company''s own cash accounts. Approve covers reversing a posted transfer.', 84),
            ('water.owner-money', 'Owner Money',
             'Record what the owner puts into the business and takes out. Approve covers reversing a posted record.', 85),
            ('water.loans', 'Loans',
             'Borrowed money and what is still owed. Create covers cancelling a loan that was never drawn.', 86),
            ('water.loan-payments', 'Loan Repayments',
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
                  ('water.cash.view',   'view'),
                  ('water.cash.create', 'create'),
                  ('water.cash.edit',   'edit'),
                  -- see the header: delete is the closest existing dangerous right
                  ('water.cash.delete', 'approve')
               ) AS m(old_key, action) ON m.old_key = rp.permissionkey
        CROSS  JOIN (VALUES ('water.cash-transfers'), ('water.owner-money'),
                            ('water.loans'), ('water.loan-payments')) AS res(resource_key)
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
               'Carried over from ' || up.permissionkey || ' by migration 260',
               up.grantedby, (now() at time zone 'utc')
        FROM   iamuserpermissions up
        JOIN   (VALUES
                  ('water.cash.view',   'view'),
                  ('water.cash.create', 'create'),
                  ('water.cash.edit',   'edit'),
                  ('water.cash.delete', 'approve')
               ) AS m(old_key, action) ON m.old_key = up.permissionkey
        CROSS  JOIN (VALUES ('water.cash-transfers'), ('water.owner-money'),
                            ('water.loans'), ('water.loan-payments')) AS res(resource_key)
        CROSS  JOIN LATERAL (SELECT res.resource_key || '.' || m.action AS new_key) n
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = n.new_key)
          -- Expired grants are not revived on the way past.
          AND  (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;

        GET DIAGNOSTICS v_added_users = ROW_COUNT;
    END IF;

    RAISE NOTICE '260: % catalog key(s), % role grant(s), % user grant(s) added.',
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
WHERE  permissionkey LIKE 'water.cash-transfers.%'
   OR  permissionkey LIKE 'water.owner-money.%'
   OR  permissionkey LIKE 'water.loans.%'
   OR  permissionkey LIKE 'water.loan-payments.%'

UNION ALL
-- Nobody who could see cash may have lost sight of the new pages.
SELECT 'every cash viewer still sees transfers',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'LOST ' || COUNT(*) END
FROM   iamrolepermissions rp
WHERE  rp.permissionkey = 'water.cash.view'
  AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                   WHERE x.roleid = rp.roleid
                     AND x.permissionkey = 'water.cash-transfers.view')

UNION ALL
SELECT 'every cash viewer still sees loans',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'LOST ' || COUNT(*) END
FROM   iamrolepermissions rp
WHERE  rp.permissionkey = 'water.cash.view'
  AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                   WHERE x.roleid = rp.roleid
                     AND x.permissionkey = 'water.loans.view')

UNION ALL
-- And nobody gained reversal who did not hold the destructive cash right.
SELECT 'approve is no wider than cash.delete',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'WIDENED ' || COUNT(*) END
FROM   iamrolepermissions rp
WHERE  rp.permissionkey IN ('water.cash-transfers.approve', 'water.owner-money.approve',
                            'water.loans.approve', 'water.loan-payments.approve')
  AND  NOT EXISTS (SELECT 1 FROM iamrolepermissions x
                   WHERE x.roleid = rp.roleid
                     AND x.permissionkey = 'water.cash.delete');

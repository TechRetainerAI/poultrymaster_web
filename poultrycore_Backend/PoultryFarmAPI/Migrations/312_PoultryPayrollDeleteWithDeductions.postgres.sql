-- =============================================================================
-- 312_PoultryPayrollDeleteWithDeductions.postgres.sql
--
-- Fixes a bug in 306: deleting a reopened payroll run failed with
--
--     update or delete on table "poultrypayrollitemdeductions" violates
--     foreign key constraint "fk_poultryemployeeloanrepayments_deduction"
--
-- WHAT WAS ACTUALLY WRONG
-- =======================
-- Deleting a run cascades to its lines and, through 306, to their deductions.
-- But a repayment keeps poultrypayrolldeductionid pointing BACK at the
-- deduction that created it -- for ever, because that link is how the advance's
-- statement can say which payroll took the money. 306 declared that foreign key
-- with no ON DELETE action, which in Postgres means "refuse", so the cascade
-- hit it and the whole delete was rejected.
--
-- The sequence that produces it is the ordinary one:
--   approve   -> a repayment is posted, pointing at its deduction
--   reopen    -> 310 REVERSES the repayment. The repayment is kept, because
--                history is append-only; only the deduction's forward link is
--                cleared. The repayment still points back.
--   delete    -> cascade tries to remove the deduction. The reversed repayment
--                still references it. Refused.
--
-- THE FIX, AND WHY IT IS NOT JUST "CASCADE"
-- =========================================
-- Two different situations look alike here and must not be treated alike.
--
--   A REVERSED repayment has already given the money back. The advance is
--   whole. Deleting the payroll it came from costs nothing but the link, so
--   ON DELETE SET NULL is right: the repayment survives with its amount, its
--   dates, its balances and its reversal reason, and simply stops pointing at
--   a row that no longer exists.
--
--   A POSTED repayment has NOT. The advance is still reduced by it. Deleting
--   the payroll underneath it would leave a worker permanently credited for a
--   deduction with no payslip anywhere to explain it -- the exact wrong that
--   310 exists to prevent on reopening. That must be refused, loudly, with the
--   advance named.
--
-- ON DELETE SET NULL alone would quietly do the second one. So the constraint
-- is relaxed AND a trigger is added to hold the line the constraint used to
-- hold by accident.
--
-- WHY A TRIGGER RATHER THAN A CHECK IN sppoultrypayrollrun_delete
-- --------------------------------------------------------------
-- That function has never been checked into this repo, and this file should not
-- have to re-emit a body it has not read -- re-emitting from a guess is how an
-- arm gets silently dropped. A trigger on the deduction table also covers every
-- other path that might delete one, now or later, rather than just the one
-- caller that happens to exist today.
--
-- Idempotent.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Let a deleted deduction release its reversed repayments.
-- -----------------------------------------------------------------------------
ALTER TABLE poultryemployeeloanrepayments
    DROP CONSTRAINT IF EXISTS fk_poultryemployeeloanrepayments_deduction;

ALTER TABLE poultryemployeeloanrepayments
    ADD CONSTRAINT fk_poultryemployeeloanrepayments_deduction
    FOREIGN KEY (poultrypayrolldeductionid)
    REFERENCES poultrypayrollitemdeductions (poultrypayrollitemdeductionid)
    ON DELETE SET NULL;

COMMENT ON CONSTRAINT fk_poultryemployeeloanrepayments_deduction
    ON poultryemployeeloanrepayments IS
    'SET NULL, not CASCADE: deleting a payroll must never delete the repayment '
    'history of an advance. The repayment keeps everything except the pointer '
    'to a deduction row that no longer exists. Deleting a payroll that still '
    'has POSTED repayments is refused by trgpoultrypayrolldeduction_nodelete.';

-- -----------------------------------------------------------------------------
-- 2. And refuse to delete one whose repayment is still standing.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrypayrolldeduction_nodelete()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_loan text;
    v_staff text;
BEGIN
    SELECT COALESCE(l.loannumber, l.poultryemployeeloanid::text),
           btrim(s.firstname || ' ' || s.lastname)
    INTO   v_loan, v_staff
    FROM   poultryemployeeloanrepayments r
    JOIN   poultryemployeeloans l ON l.poultryemployeeloanid = r.poultryemployeeloanid
    JOIN   poultrystaff s ON s.poultrystaffid = r.poultrystaffid
    WHERE  r.poultrypayrolldeductionid = OLD.poultrypayrollitemdeductionid
      AND  r.status = 'Posted'
    LIMIT  1;

    IF v_loan IS NOT NULL THEN
        RAISE EXCEPTION
            'This payroll has already repaid % of %''s advance %. Reopen the payroll first -- that gives the money back; deleting it now would leave the advance short with no payslip to explain it.',
            (SELECT to_char(r.amount, 'FM999999990.00')
               FROM poultryemployeeloanrepayments r
              WHERE r.poultrypayrolldeductionid = OLD.poultrypayrollitemdeductionid
                AND r.status = 'Posted' LIMIT 1),
            v_staff, v_loan;
    END IF;

    RETURN OLD;
END;
$function$;

DROP TRIGGER IF EXISTS trgpoultrypayrolldeduction_nodelete
    ON poultrypayrollitemdeductions;

CREATE TRIGGER trgpoultrypayrolldeduction_nodelete
    BEFORE DELETE ON poultrypayrollitemdeductions
    FOR EACH ROW
    EXECUTE FUNCTION public.fnpoultrypayrolldeduction_nodelete();

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
DO $checks$
DECLARE v_action char;
BEGIN
    SELECT c.confdeltype INTO v_action
    FROM   pg_constraint c
    WHERE  c.conname = 'fk_poultryemployeeloanrepayments_deduction';

    IF v_action IS NULL THEN
        RAISE EXCEPTION '312: the deduction foreign key is missing.';
    END IF;
    -- 'n' = SET NULL. 'a'/'r' would mean a payroll can still be undeletable.
    IF v_action <> 'n' THEN
        RAISE EXCEPTION
            '312: the deduction foreign key is still ON DELETE %, not SET NULL.', v_action;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'trgpoultrypayrolldeduction_nodelete' AND NOT tgisinternal) THEN
        RAISE EXCEPTION
            '312: the guard trigger is missing, so a payroll with live repayments could be deleted.';
    END IF;

    -- Nothing should currently be in the state this file protects against.
    IF EXISTS (
        SELECT 1
        FROM   poultryemployeeloanrepayments r
        WHERE  r.status = 'Posted'
          AND  r.poultrypayrolldeductionid IS NOT NULL
          AND  NOT EXISTS (SELECT 1 FROM poultrypayrollitemdeductions d
                            WHERE d.poultrypayrollitemdeductionid = r.poultrypayrolldeductionid)) THEN
        RAISE EXCEPTION
            '312: a posted repayment already points at a deduction that is gone. Investigate before continuing.';
    END IF;

    RAISE NOTICE
        '312_PoultryPayrollDeleteWithDeductions: reopened payrolls can be deleted; approved ones still cannot.';
END
$checks$;

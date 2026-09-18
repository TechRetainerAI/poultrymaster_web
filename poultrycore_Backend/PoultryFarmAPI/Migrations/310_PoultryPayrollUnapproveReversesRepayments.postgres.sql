-- =============================================================================
-- 310_PoultryPayrollUnapproveReversesRepayments.postgres.sql
--
-- Purpose
-- -------
-- Undo what 309 did, without pretending it never happened.
--
-- APPLY THIS WITH 309, NEVER AFTER IT
-- ===================================
-- 309 makes approval reduce a worker's advance. Until this file exists,
-- unapproving a run deletes its cash and its expense and leaves that reduction
-- standing -- so the worker has been credited for a deduction that no longer
-- appears on any payslip, and the farm's receivable is short by exactly the
-- amount it is still owed (spec section 42, stated as "DO NOT leave the
-- employee loan artificially reduced"). The two files are one change.
--
-- TWO CONVENTIONS MEET HERE, AND THEY DISAGREE
-- ============================================
-- Payroll unapproval is DESTRUCTIVE. The live function DELETEs the run's cash
-- transactions and its linked expense outright and restores the account
-- balances by subtracting the net. That is the existing behaviour of this
-- module and this file does not change it.
--
-- Employee-loan repayments are APPEND-ONLY. Section 43 is explicit: a posted
-- repayment is undone by writing a reversal, never by deleting the row, so the
-- advance's statement still shows the 100 that was taken and the 100 that was
-- given back.
--
-- So the loop below calls sppoultryemployeeloanrepayment_reverse rather than
-- deleting anything. The repayment stays, marked Reversed, with its reason and
-- who did it -- and because 305 computes the balance from POSTED repayments
-- only, the advance goes back up by exactly what this run had taken off.
--
-- p_allowpayroll => TRUE is the one place in the system that passes it. Section
-- 60 blocks a payroll-created repayment from being reversed on its own from the
-- Employee Loans page, precisely so that it can only be undone by the payroll
-- that created it. This is that payroll.
--
-- WHY THE DEDUCTION GOES BACK TO 'Draft'
-- ======================================
-- Section 44: reverse the payroll, change the deduction from 100 to 150,
-- approve again, and the advance should end up 150 lighter with all three
-- events on the record. For the user to be able to change it, the deduction has
-- to be editable again -- and 306 only allows editing a Draft.
--
-- Its poultryemployeeloanrepaymentid is cleared at the same time, for two
-- reasons. The check constraint requires it (a Draft may not point at a
-- repayment), and more importantly the pointer would be a lie: the deduction
-- no longer has a live repayment. Nothing is lost, because the link is also
-- held on the repayment itself, which keeps poultrypayrolldeductionid for ever.
--
-- The partial unique index in 305 is what makes re-approval work: it only
-- covers POSTED repayments, so once this file marks one Reversed, the slot is
-- free for the next approval to post a fresh one against the same deduction.
--
-- The body below is the LIVE sppoultrypayrollrun_unapprove (pg_get_functiondef,
-- 2026-09-17) with the reversal loop and the top-up removal added, and nothing
-- else changed.
--
-- Idempotent. Safe to run more than once.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sppoultrypayrollrun_unapprove(
    p_poultrypayrollrunid integer,
    p_farmid text,
    p_reopenedby text DEFAULT NULL::text,
    p_reason text DEFAULT NULL::text
) RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_farmguid uuid;
    -- 310.
    v_r        record;
    v_reason   text;
    v_ctxloan  text := NULL;
    v_ctxstaff text := NULL;
BEGIN
    SELECT r.status INTO v_status
    FROM   poultrypayrollruns r
    WHERE  r.poultrypayrollrunid = p_poultrypayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found for this farm.';
    END IF;
    IF v_status NOT IN ('Approved', 'Paid') THEN
        RAISE EXCEPTION 'Payroll run is %; only Approved or Paid can be reopened.', v_status;
    END IF;
    BEGIN
        v_farmguid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_farmguid := NULL;
    END;

    -- ---- 310: give back every advance repayment this run took ---------------
    -- First, so that if an advance refuses the reversal nothing destructive has
    -- run yet. (One transaction either way, but a function that fails before it
    -- deletes is easier to reason about than one that fails after.)
    v_reason := 'Payroll reopened' ||
                COALESCE(': ' || NULLIF(btrim(p_reason), ''), '');

    BEGIN
        FOR v_r IN
            SELECT r.poultryemployeeloanrepaymentid AS repayid,
                   r.poultrypayrolldeductionid      AS dedid,
                   COALESCE(l.loannumber, l.poultryemployeeloanid::text) AS loannumber,
                   btrim(s.firstname || ' ' || s.lastname) AS staffname
            FROM   poultryemployeeloanrepayments r
            JOIN   poultryemployeeloans l ON l.poultryemployeeloanid = r.poultryemployeeloanid
            JOIN   poultrystaff s ON s.poultrystaffid = r.poultrystaffid
            WHERE  r.farmid = p_farmid
              AND  r.poultrypayrollrunid = p_poultrypayrollrunid
              AND  r.sourcetype = 'Payroll'
              -- Already-reversed ones are left alone: reversing a reversal
              -- would put the deduction back on the advance.
              AND  r.status = 'Posted'
            ORDER  BY r.poultryemployeeloanrepaymentid
        LOOP
            v_ctxloan  := v_r.loannumber;
            v_ctxstaff := v_r.staffname;

            -- Appends a reversal; does not delete. TRUE is what unlocks a
            -- payroll-created repayment, and this is the only caller that
            -- passes it.
            PERFORM public.sppoultryemployeeloanrepayment_reverse(
                p_farmid       => p_farmid,
                p_poultryemployeeloanrepaymentid => v_r.repayid,
                p_reversedby   => p_reopenedby,
                p_reason       => v_reason,
                p_allowpayroll => TRUE);

            -- Editable again, and no longer claiming a repayment it does not
            -- have. The reverse link survives on the repayment row.
            IF v_r.dedid IS NOT NULL THEN
                UPDATE poultrypayrollitemdeductions
                SET    status = 'Draft',
                       poultryemployeeloanrepaymentid = NULL,
                       updatedby = p_reopenedby,
                       updatedat = (now() at time zone 'utc')
                WHERE  poultrypayrollitemdeductionid = v_r.dedid
                  AND  farmid = p_farmid;
            END IF;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        IF v_ctxloan IS NULL THEN
            RAISE;
        END IF;
        RAISE EXCEPTION
            'Payroll was not reopened. The repayment against advance % for % could not be reversed: %',
            v_ctxloan, COALESCE(v_ctxstaff, 'this member of staff'), SQLERRM;
    END;

    -- Other deductions posted nothing, so there is nothing to reverse -- but
    -- they must become editable again along with the rest of the run.
    UPDATE poultrypayrollitemdeductions
    SET    status = 'Draft',
           updatedby = p_reopenedby,
           updatedat = (now() at time zone 'utc')
    WHERE  poultrypayrollrunid = p_poultrypayrollrunid
      AND  farmid = p_farmid
      AND  status = 'Posted'
      AND  poultryemployeeloanrepaymentid IS NULL;

    -- Reverse any payroll cash transactions for this run (restore balances).
    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - t.net,
           updatedat = (now() at time zone 'utc')
    FROM (
        SELECT ct.poultrycashaccountid, SUM(ct.amount) AS net
        FROM   poultrycashtransactions ct
        WHERE  ct.sourcetype = 'Payroll' AND ct.sourceid = p_poultrypayrollrunid AND ct.farmid = p_farmid
        GROUP  BY ct.poultrycashaccountid
    ) t
    WHERE t.poultrycashaccountid = a.poultrycashaccountid
      AND a.farmid = p_farmid;
    DELETE FROM poultrycashtransactions ct
    WHERE ct.sourcetype = 'Payroll' AND ct.sourceid = p_poultrypayrollrunid AND ct.farmid = p_farmid;
    -- Remove the linked expense.
    DELETE FROM expense e
    WHERE e.sourcetype = 'Payroll' AND e.sourceid = p_poultrypayrollrunid AND e.farmid = v_farmguid;

    -- ---- 310: and the advance top-up 309 added ------------------------------
    -- Deleted rather than compensated, deliberately: it is removed the same way
    -- and at the same moment as the payroll expense it belongs to, so the two
    -- cannot end up disagreeing about whether this run's cost exists. It also
    -- moved no cash, so there is no balance to put back.
    DELETE FROM expense e
    WHERE e.sourcetype = 'PayrollEmployeeLoan'
      AND e.sourceid = p_poultrypayrollrunid
      AND e.farmid = v_farmguid;

    UPDATE poultrypayrollruns r
    SET    status = 'Reopened', reopenedby = p_reopenedby, reopenedat = (now() at time zone 'utc'),
           reopenreason = p_reason, paidby = NULL, paidat = NULL, updatedat = (now() at time zone 'utc')
    WHERE  r.poultrypayrollrunid = p_poultrypayrollrunid AND r.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
DO $checks$
DECLARE
    v_body text;
    v_bad  integer;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_body
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'sppoultrypayrollrun_unapprove' LIMIT 1;

    IF v_body IS NULL OR position('sppoultryemployeeloanrepayment_reverse' in v_body) = 0 THEN
        RAISE EXCEPTION
            '310: sppoultrypayrollrun_unapprove does not reverse advance repayments. Reopening a payroll would leave every advance artificially reduced.';
    END IF;
    IF position('PayrollEmployeeLoan' in v_body) = 0 THEN
        RAISE EXCEPTION '310: the advance top-up is not removed on unapproval.';
    END IF;

    -- 309 must already be in place, or approval posts nothing for this to undo.
    SELECT pg_get_functiondef(p.oid) INTO v_body
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'sppoultrypayrollrun_approve' LIMIT 1;
    IF v_body IS NULL OR position('sppoultryemployeeloanrepayment_record' in v_body) = 0 THEN
        RAISE EXCEPTION '310: migration 309 has not been applied. Apply 309 and 310 together.';
    END IF;

    -- No reopened run may still hold a live repayment. This is section 42,
    -- checkable: a Reopened run with a Posted repayment is precisely the
    -- artificially-reduced advance the file exists to prevent.
    SELECT COUNT(*) INTO v_bad
    FROM   poultryemployeeloanrepayments r
    JOIN   poultrypayrollruns pr ON pr.poultrypayrollrunid = r.poultrypayrollrunid
    WHERE  r.sourcetype = 'Payroll'
      AND  r.status = 'Posted'
      AND  pr.status IN ('Reopened', 'Draft', 'Cancelled');
    IF v_bad > 0 THEN
        RAISE EXCEPTION
            '310: % advance repayment(s) are still posted against a payroll that is no longer approved.', v_bad;
    END IF;

    -- And no advance may owe more than it is worth, which is what a
    -- double-reversal would produce.
    SELECT COUNT(*) INTO v_bad
    FROM   poultryemployeeloans l
    WHERE  l.outstandingbalance > l.totalrepayable;
    IF v_bad > 0 THEN
        RAISE EXCEPTION '310: % advance(s) now owe more than they are worth.', v_bad;
    END IF;

    RAISE NOTICE '310_PoultryPayrollUnapproveReversesRepayments: unapproval reverses repayments, verified.';
END
$checks$;

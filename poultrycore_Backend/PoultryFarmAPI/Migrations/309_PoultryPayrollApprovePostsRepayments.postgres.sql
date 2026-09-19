-- =============================================================================
-- 309_PoultryPayrollApprovePostsRepayments.postgres.sql
--
-- Purpose
-- -------
-- The moment a planned deduction becomes a real repayment.
--
-- Up to now a deduction row has been an INTENTION: 306 writes it at status
-- 'Draft' and touches no advance, because spec section 38 is absolute -- a
-- draft payroll must not move a loan balance. This file is the other half of
-- that promise. Approving the run turns every loan deduction on it into an
-- EmployeeLoanRepayment, and nothing else ever does.
--
-- WHY THE POSTING LIVES INSIDE THE APPROVE FUNCTION
-- =================================================
-- Section 40: payroll must never be approved with a repayment that failed, and
-- a repayment must never be posted against a payroll that then failed to
-- approve. A Postgres function body is a single transaction, so putting the
-- posting HERE -- rather than in a second call the API layer makes afterwards
-- -- makes that free and unbreakable. If any advance has been paid off,
-- reversed or reduced since the deduction was entered, the RAISE from
-- sppoultryemployeeloanrepayment_record aborts the whole approval, the status
-- stays where it was, and the user gets told which advance and why.
--
-- Section 78 comes out of the same decision: a user who can edit deductions but
-- cannot approve payroll has no path that posts a repayment, because the only
-- path runs through this function.
--
-- Section 80, idempotency, is not enforced here either -- it is enforced by
-- ux_poultryemployeeloanrepayments_deduction in 305, which permits ONE posted
-- repayment per deduction. Approving twice cannot double-charge a worker even
-- if this loop were somehow entered twice, because the second INSERT is
-- refused by the index rather than by this code remembering anything.
--
-- THE PAYROLL EXPENSE TOP-UP
-- ==========================
-- The linked expense this function has always written is totalNETpay. So every
-- deduction of any kind already REDUCES recorded payroll cost, which was
-- invisible while deductions were an unexplained lump sum.
--
-- With loan repayments it stops being invisible. Over the life of a 2,000
-- advance repaid through wages, 2,000 of labour cost would quietly leave the
-- P&L while the receivable also went to zero -- the farm would look like it
-- had employed people more cheaply than it did.
--
-- So when a loan deduction posts, this function writes a SECOND payroll expense
-- row for exactly that amount, with paymentmethod 'NonCash':
--
--     Gross 2,200, loan deduction 100, net 2,100
--       expense  2,100  (Cash,    as always)
--       expense  +100   (NonCash, new)
--       -------------
--       P&L payroll cost 2,200      <- section 47
--       cash out         2,100
--       receivable        -100
--
-- 'NonCash' is not a new idea: it is the existing marker for "a cost recorded
-- without money moving for THIS row", used by internal use since 216 and by
-- loan interest since 254. Following it through the three places it matters:
--
--   sppoultrycashflow_rows   EXCLUDES NonCash from the expense arm, so the 100
--                            never becomes a second cash outflow.
--   fnpoultrypayables        EXCLUDES NonCash, so this never makes the worker
--                            a creditor on Supplier Balances.
--   sppoultryreport_profitloss  does NOT filter NonCash -- it sums e.amount --
--                            so the 100 DOES count as payroll cost.
--
-- A run with no loan deductions writes no top-up and behaves exactly as it did
-- before this file existed. Nothing historical is touched.
--
-- Other deductions are untouched by all of this. A uniform charge still reduces
-- net pay and therefore still reduces recorded payroll cost, exactly as it
-- always has -- section 48 says follow existing behaviour where no specific
-- treatment exists, and inventing one for "Other" would be guessing at what the
-- farm meant.
--
-- The body below is the LIVE sppoultrypayrollrun_approve (pg_get_functiondef,
-- 2026-09-17 -- this function was never checked into the repo) with the posting
-- loop and the top-up added, and nothing else changed.
--
-- Idempotent. Safe to run more than once.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sppoultrypayrollrun_approve(
    p_poultrypayrollrunid integer,
    p_farmid text,
    p_approvedby text DEFAULT NULL::text
) RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_periodstart date;
    v_periodend date;
    v_paydate date;
    v_net numeric;
    v_farmguid uuid;
    v_expdate date;
    v_desc text;
    -- 309.
    v_d          record;
    v_repayid    integer;
    v_loantotal  numeric := 0;
    v_ctxloan    text := NULL;
    v_ctxstaff   text := NULL;
BEGIN
    SELECT r.status, r.periodstart, r.periodend, r.paydate, r.totalnetpay
    INTO   v_status, v_periodstart, v_periodend, v_paydate, v_net
    FROM   poultrypayrollruns r
    WHERE  r.poultrypayrollrunid = p_poultrypayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found for this farm.';
    END IF;
    IF v_status NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION 'Payroll run is %; only Draft or Reopened can be approved.', v_status;
    END IF;
    BEGIN
        v_farmguid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_farmguid := NULL;
    END;
    v_expdate := COALESCE(v_paydate, ((now() at time zone 'utc'))::date);
    v_desc := concat('Payroll ', to_char(v_periodstart, 'YYYY-MM-DD'), ' to ', to_char(v_periodend, 'YYYY-MM-DD'));

    -- ---- 309: turn planned loan deductions into real repayments -------------
    -- BEFORE the status flips and before the expense is written, so that a
    -- rejected repayment leaves a run that still looks exactly as it did.
    -- (Belt and braces -- the whole function is one transaction either way.)
    --
    -- The validation is NOT repeated here. sppoultryemployeeloanrepayment_record
    -- re-checks the farm, the worker, the advance's status and its outstanding
    -- balance at posting time, which is the only moment those answers are
    -- authoritative. 306 checks the same things when the deduction is entered,
    -- so the user normally finds out early; this is what guarantees it.
    BEGIN
        FOR v_d IN
            SELECT d.poultrypayrollitemdeductionid AS dedid,
                   d.poultrypayrollitemid          AS itemid,
                   d.poultryemployeeloanid         AS loanid,
                   d.poultrystaffid                AS staffid,
                   d.amount                        AS amount,
                   l.loannumber                    AS loannumber,
                   btrim(s.firstname || ' ' || s.lastname) AS staffname
            FROM   poultrypayrollitemdeductions d
            JOIN   poultryemployeeloans l ON l.poultryemployeeloanid = d.poultryemployeeloanid
            JOIN   poultrystaff s ON s.poultrystaffid = d.poultrystaffid
            WHERE  d.poultrypayrollrunid = p_poultrypayrollrunid
              AND  d.farmid = p_farmid
              AND  d.status = 'Draft'
              AND  d.deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment')
            ORDER  BY d.poultrypayrollitemdeductionid
        LOOP
            v_ctxloan  := COALESCE(v_d.loannumber, v_d.loanid::text);
            v_ctxstaff := v_d.staffname;

            v_repayid := public.sppoultryemployeeloanrepayment_record(
                p_farmid                    => p_farmid,
                p_poultryemployeeloanid     => v_d.loanid,
                p_amount                    => v_d.amount,
                p_sourcetype                => 'Payroll',
                -- All principal. Interest on a staff advance is not charged per
                -- payroll period, and splitting it here would be inventing an
                -- amortisation rule the farm never asked for.
                p_principalamount           => v_d.amount,
                p_interestamount            => 0,
                p_repaymentdate             => v_expdate::timestamp,
                -- No cash account, and 305's constraint would refuse one: the
                -- wage paid out is already net, so no money moved for this.
                p_poultrycashaccountid      => NULL,
                p_description               => v_desc,
                p_poultrypayrollrunid       => p_poultrypayrollrunid,
                p_poultrypayrollitemid      => v_d.itemid,
                p_poultrypayrolldeductionid => v_d.dedid,
                p_poultrystaffid            => v_d.staffid,
                p_createdby                 => p_approvedby);

            UPDATE poultrypayrollitemdeductions
            SET    status = 'Posted',
                   poultryemployeeloanrepaymentid = v_repayid,
                   updatedby = p_approvedby,
                   updatedat = (now() at time zone 'utc')
            WHERE  poultrypayrollitemdeductionid = v_d.dedid;

            v_loantotal := v_loantotal + v_d.amount;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        -- Section 40: say which advance stopped the approval. Without this the
        -- user sees a balance error with no idea whose wage it came from.
        IF v_ctxloan IS NULL THEN
            RAISE;
        END IF;
        RAISE EXCEPTION
            'Payroll was not approved. The deduction against advance % for % could not be posted: %',
            v_ctxloan, COALESCE(v_ctxstaff, 'this member of staff'), SQLERRM;
    END;

    -- Every remaining planned deduction on the run is now in force. The loan
    -- ones already flipped above; this catches Other deductions, which post
    -- nothing but should not stay 'Draft' on an approved run.
    UPDATE poultrypayrollitemdeductions
    SET    status = 'Posted',
           updatedby = p_approvedby,
           updatedat = (now() at time zone 'utc')
    WHERE  poultrypayrollrunid = p_poultrypayrollrunid
      AND  farmid = p_farmid
      AND  status = 'Draft';

    IF v_status = 'Reopened' THEN
        UPDATE poultrypayrollruns r
        SET    status = 'Approved', reapprovedby = p_approvedby, reapprovedat = (now() at time zone 'utc'),
               updatedat = (now() at time zone 'utc')
        WHERE  r.poultrypayrollrunid = p_poultrypayrollrunid AND r.farmid = p_farmid;
    ELSE
        UPDATE poultrypayrollruns r
        SET    status = 'Approved', approvedby = p_approvedby, approvedat = (now() at time zone 'utc'),
               updatedat = (now() at time zone 'utc')
        WHERE  r.poultrypayrollrunid = p_poultrypayrollrunid AND r.farmid = p_farmid;
    END IF;
    -- Upsert the linked expense (matched by SourceType/SourceId).
    IF EXISTS (SELECT 1 FROM expense e WHERE e.sourcetype = 'Payroll' AND e.sourceid = p_poultrypayrollrunid) THEN
        UPDATE expense e
        SET    amount = v_net, expensedate = v_expdate, description = v_desc, category = 'Payroll'
        WHERE  e.sourcetype = 'Payroll' AND e.sourceid = p_poultrypayrollrunid AND e.farmid = v_farmguid;
    ELSE
        INSERT INTO expense (expensedate, category, description, amount, paymentmethod, flockid, userid, farmid, sourcetype, sourceid)
        VALUES (v_expdate, 'Payroll', v_desc, v_net, 'Cash', NULL, COALESCE(p_approvedby, ''), v_farmguid, 'Payroll', p_poultrypayrollrunid);
    END IF;

    -- ---- 309: put back the wage cost the deductions took out ----------------
    -- Only for LOAN deductions, and only when there are any. See the header for
    -- why 'NonCash' is the right marker and what it does in each report.
    --
    -- Its own sourcetype, so 310 can find and remove it on unapproval exactly
    -- the way the run's own expense is removed.
    IF v_loantotal > 0 THEN
        IF EXISTS (SELECT 1 FROM expense e
                    WHERE e.sourcetype = 'PayrollEmployeeLoan'
                      AND e.sourceid = p_poultrypayrollrunid) THEN
            UPDATE expense e
            SET    amount = v_loantotal, expensedate = v_expdate,
                   description = v_desc || ' - advances repaid from wages',
                   category = 'Payroll'
            WHERE  e.sourcetype = 'PayrollEmployeeLoan'
              AND  e.sourceid = p_poultrypayrollrunid
              AND  e.farmid = v_farmguid;
        ELSE
            INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                                 flockid, userid, farmid, sourcetype, sourceid)
            VALUES (v_expdate, 'Payroll', v_desc || ' - advances repaid from wages',
                    v_loantotal, 'NonCash', NULL, COALESCE(p_approvedby, ''), v_farmguid,
                    'PayrollEmployeeLoan', p_poultrypayrollrunid);
        END IF;
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- Verification.
--
-- Everything here is asserted against real rows, because the interesting
-- failures are the ones that leave the database internally inconsistent rather
-- than the ones that raise.
-- -----------------------------------------------------------------------------
DO $checks$
DECLARE
    v_body text;
    v_bad  integer;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_body
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'sppoultrypayrollrun_approve' LIMIT 1;

    IF v_body IS NULL OR position('sppoultryemployeeloanrepayment_record' in v_body) = 0 THEN
        RAISE EXCEPTION
            '309: sppoultrypayrollrun_approve does not post loan repayments. Approving payroll would leave every advance untouched.';
    END IF;
    IF position('PayrollEmployeeLoan' in v_body) = 0 THEN
        RAISE EXCEPTION '309: the payroll expense top-up is missing.';
    END IF;

    -- A posted deduction must carry the repayment it created, and a draft one
    -- must not. This is the section 38 promise, checkable.
    SELECT COUNT(*) INTO v_bad
    FROM   poultrypayrollitemdeductions d
    WHERE  d.deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment')
      AND  ((d.status = 'Posted' AND d.poultryemployeeloanrepaymentid IS NULL)
         OR (d.status = 'Draft'  AND d.poultryemployeeloanrepaymentid IS NOT NULL));
    IF v_bad > 0 THEN
        RAISE EXCEPTION
            '309: % loan deduction(s) disagree with their own posted state.', v_bad;
    END IF;

    -- No deduction may have posted more than one live repayment. The unique
    -- index in 305 makes this impossible; this proves the index is present and
    -- doing its job rather than assuming it.
    SELECT COUNT(*) INTO v_bad
    FROM  (SELECT r.poultrypayrolldeductionid
           FROM   poultryemployeeloanrepayments r
           WHERE  r.poultrypayrolldeductionid IS NOT NULL AND r.status = 'Posted'
           GROUP  BY r.poultrypayrolldeductionid
           HAVING COUNT(*) > 1) dup;
    IF v_bad > 0 THEN
        RAISE EXCEPTION
            '309: % payroll deduction(s) have posted more than one repayment.', v_bad;
    END IF;

    -- The top-up must never be a cash expense, or the 100 becomes a second
    -- outflow and Cash Flow is wrong by every repayment ever withheld.
    SELECT COUNT(*) INTO v_bad
    FROM   expense e
    WHERE  e.sourcetype = 'PayrollEmployeeLoan'
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash';
    IF v_bad > 0 THEN
        RAISE EXCEPTION
            '309: % payroll advance top-up row(s) are not marked NonCash.', v_bad;
    END IF;

    RAISE NOTICE '309_PoultryPayrollApprovePostsRepayments: approval posts repayments, verified.';
END
$checks$;

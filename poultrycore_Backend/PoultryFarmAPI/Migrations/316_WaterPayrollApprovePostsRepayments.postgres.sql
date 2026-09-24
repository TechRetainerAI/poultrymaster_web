-- =============================================================================
-- 316_WaterPayrollApprovePostsRepayments.postgres.sql
--
-- The water port of 309: approving a payroll turns its planned advance
-- deductions into real repayments, and nothing else ever does.
--
-- Read 309's header for why the posting lives inside the approve function
-- (section 40: one transaction, so "approved but the repayment failed" is
-- unreachable), why validation is not repeated here, and why idempotency is
-- the unique index in 313 rather than anything in this loop.
--
-- WHAT DIFFERS FROM POULTRY
-- =========================
-- The expense side. Poultry writes to the shared `expense` table with a
-- free-text category; water writes to `waterexpenses`, which carries a category
-- FOREIGN KEY, a status, and a soft-delete flag. So the top-up row is built the
-- way water builds its payroll expense -- same category id the function already
-- resolved, status 'Approved' -- rather than copied from the poultry version.
--
-- What is the same is the marker that makes it work: paymentmethod 'NonCash'.
-- Water's cash-flow arm 3 excludes it and its expense reports do not, exactly
-- as poultry's do, which is what lets a cost be recorded without inventing a
-- second cash outflow.
--
-- Body verbatim from the live database (pg_get_functiondef, 2026-09-18).
--
-- Idempotent.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spwaterpayrollrun_approve(p_waterpayrollrunid integer, p_farmid text, p_approvedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_priorstatus   text;
    -- 316.
    v_d          record;
    v_repayid    integer;
    v_loantotal  numeric := 0;
    v_ctxloan    text := NULL;
    v_ctxstaff   text := NULL;
    v_netpay        numeric(14,2);
    v_periodstart   date;
    v_periodend     date;
    v_paydate       date;
    v_cashaccountid integer;
    v_notes         text;
    v_catid         integer;
    v_expensedate   timestamp;
    v_description   text;
BEGIN
    SELECT r.status INTO v_priorstatus
    FROM   waterpayrollruns r
    WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE
    LIMIT  1;

    IF v_priorstatus IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found.';
    END IF;
    IF v_priorstatus NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION 'Payroll cannot be approved (current=%).', v_priorstatus;
    END IF;

    -- ---- 316: turn planned loan deductions into real repayments -------------
    -- Before anything else is written, so a rejected repayment leaves a run
    -- that still looks exactly as it did. (Belt and braces -- the whole
    -- function is one transaction either way.)
    --
    -- Validation is NOT repeated here. spwateremployeeloanrepayment_record
    -- re-checks the farm, the worker, the advance's status and its outstanding
    -- balance at posting time, which is the only moment those answers are
    -- authoritative.
    BEGIN
        FOR v_d IN
            SELECT d.waterpayrollitemdeductionid AS dedid,
                   d.waterpayrollitemid          AS itemid,
                   d.wateremployeeloanid         AS loanid,
                   d.waterstaffid                AS staffid,
                   d.amount                      AS amount,
                   l.loannumber                  AS loannumber,
                   btrim(s.firstname || ' ' || s.lastname) AS staffname
            FROM   waterpayrollitemdeductions d
            JOIN   wateremployeeloans l ON l.wateremployeeloanid = d.wateremployeeloanid
            JOIN   waterstaff s ON s.waterstaffid = d.waterstaffid
            WHERE  d.waterpayrollrunid = p_waterpayrollrunid
              AND  d.farmid = p_farmid
              AND  d.status = 'Draft'
              AND  d.deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment')
            ORDER  BY d.waterpayrollitemdeductionid
        LOOP
            v_ctxloan  := COALESCE(v_d.loannumber, v_d.loanid::text);
            v_ctxstaff := v_d.staffname;

            v_repayid := public.spwateremployeeloanrepayment_record(
                p_farmid                    => p_farmid,
                p_wateremployeeloanid       => v_d.loanid,
                p_amount                    => v_d.amount,
                p_sourcetype                => 'Payroll',
                p_principalamount           => v_d.amount,
                p_interestamount            => 0,
                p_repaymentdate             => COALESCE(
                    (SELECT r.paydate::timestamp FROM waterpayrollruns r
                      WHERE r.waterpayrollrunid = p_waterpayrollrunid),
                    (now() at time zone 'utc')),
                -- No cash account, and 313's constraint would refuse one: the
                -- wage paid out is already net, so no money moved for this.
                p_watercashaccountid        => NULL,
                p_waterpayrollrunid         => p_waterpayrollrunid,
                p_waterpayrollitemid        => v_d.itemid,
                p_waterpayrolldeductionid   => v_d.dedid,
                p_waterstaffid              => v_d.staffid,
                p_createdby                 => p_approvedby);

            UPDATE waterpayrollitemdeductions
            SET    status = 'Posted',
                   wateremployeeloanrepaymentid = v_repayid,
                   updatedby = p_approvedby,
                   updatedat = (now() at time zone 'utc')
            WHERE  waterpayrollitemdeductionid = v_d.dedid;

            v_loantotal := v_loantotal + v_d.amount;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        IF v_ctxloan IS NULL THEN
            RAISE;
        END IF;
        RAISE EXCEPTION
            'Payroll was not approved. The deduction against advance % for % could not be posted: %',
            v_ctxloan, COALESCE(v_ctxstaff, 'this member of staff'), SQLERRM;
    END;

    -- Every remaining planned deduction is now in force. The loan ones flipped
    -- above; this catches Other deductions, which post nothing but should not
    -- stay 'Draft' on an approved run.
    UPDATE waterpayrollitemdeductions
    SET    status = 'Posted',
           updatedby = p_approvedby,
           updatedat = (now() at time zone 'utc')
    WHERE  waterpayrollrunid = p_waterpayrollrunid
      AND  farmid = p_farmid
      AND  status = 'Draft';

    IF v_priorstatus = 'Reopened' THEN
        -- Reapproval: preserve the original ApprovedBy/At; record Reapproved*.
        UPDATE waterpayrollruns r
        SET    status       = 'Approved',
               reapprovedby = p_approvedby,
               reapprovedat = (now() at time zone 'utc'),
               updatedat    = (now() at time zone 'utc')
        WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid;
    ELSE  -- Draft
        UPDATE waterpayrollruns r
        SET    status     = 'Approved',
               approvedby = p_approvedby,
               approvedat = (now() at time zone 'utc'),
               updatedat  = (now() at time zone 'utc')
        WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid;
    END IF;

    -- Linked-expense upsert.
    SELECT r.totalnetpay, r.periodstart, r.periodend, r.paydate, r.watercashaccountid, r.notes
    INTO   v_netpay, v_periodstart, v_periodend, v_paydate, v_cashaccountid, v_notes
    FROM   waterpayrollruns r
    WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid
    LIMIT  1;

    SELECT c.waterexpensecategoryid INTO v_catid
    FROM   waterexpensecategories c
    WHERE  c.farmid = p_farmid
      AND  c.name IN ('Payroll', 'Salaries', 'Wages')
      AND  c.isactive = TRUE
    ORDER  BY CASE c.name WHEN 'Payroll' THEN 1 WHEN 'Salaries' THEN 2 ELSE 3 END
    LIMIT  1;

    IF v_catid IS NULL THEN
        INSERT INTO waterexpensecategories (farmid, name, isactive)
        VALUES (p_farmid, 'Payroll', TRUE)
        RETURNING waterexpensecategoryid INTO v_catid;
    END IF;

    v_expensedate := COALESCE(v_paydate::timestamp, (now() at time zone 'utc'));
    v_description := left(concat(
        'Payroll for ',
        to_char(v_periodstart, 'YYYY-MM-DD'),
        ' to ',
        to_char(v_periodend, 'YYYY-MM-DD'),
        ' (run #', p_waterpayrollrunid, ')'
    ), 500);

    IF EXISTS (
        SELECT 1 FROM waterexpenses e
        WHERE e.farmid = p_farmid AND e.sourcetype = 'Payroll'
          AND e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE
    ) THEN
        UPDATE waterexpenses e
        SET    amount        = v_netpay,
               expensedate   = v_expensedate,
               description   = v_description,
               waterexpensecategoryid = v_catid,
               watercashaccountid = v_cashaccountid,
               status        = 'Approved',
               approvedby    = p_approvedby,
               approvedat    = (now() at time zone 'utc'),
               updatedat     = (now() at time zone 'utc')
        WHERE  e.farmid = p_farmid AND e.sourcetype = 'Payroll'
          AND  e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE;
    ELSE
        INSERT INTO waterexpenses (
            farmid, expensedate, waterexpensecategoryid, description, amount,
            paymentmethod, watercashaccountid, status,
            sourcetype, sourceid,
            createdby, approvedby, approvedat
        )
        VALUES (
            p_farmid, v_expensedate, v_catid, v_description, v_netpay,
            CASE WHEN v_cashaccountid IS NULL THEN 'Credit' ELSE 'Cash' END,
            v_cashaccountid, 'Approved',
            'Payroll', p_waterpayrollrunid,
            p_approvedby, p_approvedby, (now() at time zone 'utc')
        );
    END IF;

    -- ---- 316: put back the wage cost the deductions took out ----------------
    -- The linked expense above is totalNETpay, so every deduction reduces
    -- recorded payroll cost. Over the life of a 2,000 advance repaid through
    -- wages, 2,000 of labour cost would quietly leave the reports while the
    -- receivable also went to zero.
    --
    -- 'NonCash' is the existing marker for "a cost recorded without money
    -- moving for THIS row". spwatercashflow_rows arm 3 excludes it, so the
    -- top-up never becomes a second outflow; the expense reports do not filter
    -- it, so the cost still counts. Same trick water already uses for loan
    -- interest (259).
    --
    -- Its own sourcetype, so 317 can find and cancel it the way the run's own
    -- expense is cancelled. A run with no loan deductions writes nothing here.
    IF v_loantotal > 0 THEN
        IF EXISTS (
            SELECT 1 FROM waterexpenses e
            WHERE e.farmid = p_farmid AND e.sourcetype = 'PayrollEmployeeLoan'
              AND e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE
        ) THEN
            UPDATE waterexpenses e
            SET    amount      = v_loantotal,
                   expensedate = v_expensedate,
                   description = left(v_description || ' - advances repaid from wages', 500),
                   waterexpensecategoryid = v_catid,
                   status      = 'Approved',
                   approvedby  = p_approvedby,
                   approvedat  = (now() at time zone 'utc'),
                   updatedat   = (now() at time zone 'utc')
            WHERE  e.farmid = p_farmid AND e.sourcetype = 'PayrollEmployeeLoan'
              AND  e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE;
        ELSE
            INSERT INTO waterexpenses (
                farmid, expensedate, waterexpensecategoryid, description, amount,
                paymentmethod, watercashaccountid, status,
                sourcetype, sourceid,
                createdby, approvedby, approvedat
            )
            VALUES (
                p_farmid, v_expensedate, v_catid,
                left(v_description || ' - advances repaid from wages', 500), v_loantotal,
                'NonCash', NULL, 'Approved',
                'PayrollEmployeeLoan', p_waterpayrollrunid,
                p_approvedby, p_approvedby, (now() at time zone 'utc')
            );
        END IF;
    END IF;
END;
$function$;

DO $checks$
DECLARE v_body text; v_bad integer;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_body
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'spwaterpayrollrun_approve' LIMIT 1;

    IF v_body IS NULL OR position('spwateremployeeloanrepayment_record' in v_body) = 0 THEN
        RAISE EXCEPTION
            '316: spwaterpayrollrun_approve does not post loan repayments.';
    END IF;
    IF position('PayrollEmployeeLoan' in v_body) = 0 THEN
        RAISE EXCEPTION '316: the payroll expense top-up is missing.';
    END IF;

    SELECT COUNT(*) INTO v_bad
    FROM   waterpayrollitemdeductions d
    WHERE  d.deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment')
      AND  ((d.status = 'Posted' AND d.wateremployeeloanrepaymentid IS NULL)
         OR (d.status = 'Draft'  AND d.wateremployeeloanrepaymentid IS NOT NULL));
    IF v_bad > 0 THEN
        RAISE EXCEPTION '316: % loan deduction(s) disagree with their own posted state.', v_bad;
    END IF;

    SELECT COUNT(*) INTO v_bad
    FROM   waterexpenses e
    WHERE  e.sourcetype = 'PayrollEmployeeLoan'
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash';
    IF v_bad > 0 THEN
        RAISE EXCEPTION '316: % advance top-up row(s) are not marked NonCash.', v_bad;
    END IF;

    RAISE NOTICE '316_WaterPayrollApprovePostsRepayments: approval posts repayments, verified.';
END
$checks$;

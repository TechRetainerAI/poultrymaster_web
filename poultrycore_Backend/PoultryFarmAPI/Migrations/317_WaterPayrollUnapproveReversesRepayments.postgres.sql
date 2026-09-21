-- =============================================================================
-- 317_WaterPayrollUnapproveReversesRepayments.postgres.sql
--
-- The water port of 310, and the other half of 316. APPLY THEM TOGETHER: 316
-- alone makes approval reduce a worker's advance with nothing able to give it
-- back, so an unapproved run would leave the advance permanently short.
--
-- WHAT DIFFERS FROM POULTRY
-- =========================
-- Water's unapproval is gentler than poultry's, and this file follows it rather
-- than importing poultry's habits:
--
--   poultry  DELETEs the run's cash rows and its linked expense outright.
--   water    appends a reversing cash transaction and CANCELS the expense
--            (status 'Cancelled', isdeleted = TRUE), so the filtered unique
--            index frees up for a fresh row on reapproval.
--
-- So the advance top-up 316 wrote is cancelled the same way, not deleted. The
-- repayments themselves are reversed by appending, exactly as on poultry --
-- that part was never up for debate, because an advance's statement has to keep
-- showing the 100 that was taken and the 100 that was given back.
--
-- Body verbatim from the live database (pg_get_functiondef, 2026-09-18).
--
-- Idempotent.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spwaterpayrollrun_unapprove(p_waterpayrollrunid integer, p_farmid text, p_reopenedby text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status        text;
    -- 317.
    v_r        record;
    v_reason   text;
    v_ctxloan  text := NULL;
    v_ctxstaff text := NULL;
    v_cashaccountid integer;
    v_netpay        numeric(14,2);
BEGIN
    SELECT r.status, r.watercashaccountid, r.totalnetpay
    INTO   v_status, v_cashaccountid, v_netpay
    FROM   waterpayrollruns r
    WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found.';
    END IF;
    IF v_status NOT IN ('Approved', 'Paid') THEN
        RAISE EXCEPTION 'Payroll can only be reopened from Approved or Paid (current=%).', v_status;
    END IF;

    -- ---- 317: give back every advance repayment this run took ---------------
    -- First, so that if an advance refuses the reversal nothing else has run.
    --
    -- Appends a reversal rather than deleting: the repayment stays, marked
    -- Reversed, and because 313 computes the balance from POSTED repayments
    -- only, the advance goes back up by exactly what this run had taken off.
    -- p_allowpayroll => TRUE is the one place in the water module that passes
    -- it, which is what makes a payroll-created repayment undoable only by the
    -- payroll that created it.
    v_reason := 'Payroll reopened' || COALESCE(': ' || NULLIF(btrim(p_reason), ''), '');

    BEGIN
        FOR v_r IN
            SELECT r.wateremployeeloanrepaymentid AS repayid,
                   r.waterpayrolldeductionid      AS dedid,
                   COALESCE(l.loannumber, l.wateremployeeloanid::text) AS loannumber,
                   btrim(s.firstname || ' ' || s.lastname) AS staffname
            FROM   wateremployeeloanrepayments r
            JOIN   wateremployeeloans l ON l.wateremployeeloanid = r.wateremployeeloanid
            JOIN   waterstaff s ON s.waterstaffid = r.waterstaffid
            WHERE  r.farmid = p_farmid
              AND  r.waterpayrollrunid = p_waterpayrollrunid
              AND  r.sourcetype = 'Payroll'
              AND  r.status = 'Posted'
            ORDER  BY r.wateremployeeloanrepaymentid
        LOOP
            v_ctxloan  := v_r.loannumber;
            v_ctxstaff := v_r.staffname;

            PERFORM public.spwateremployeeloanrepayment_reverse(
                p_farmid       => p_farmid,
                p_wateremployeeloanrepaymentid => v_r.repayid,
                p_reversedby   => p_reopenedby,
                p_reason       => v_reason,
                p_allowpayroll => TRUE);

            IF v_r.dedid IS NOT NULL THEN
                UPDATE waterpayrollitemdeductions
                SET    status = 'Draft',
                       wateremployeeloanrepaymentid = NULL,
                       updatedby = p_reopenedby,
                       updatedat = (now() at time zone 'utc')
                WHERE  waterpayrollitemdeductionid = v_r.dedid
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

    -- Other deductions posted nothing, but must become editable again with the
    -- rest of the run.
    UPDATE waterpayrollitemdeductions
    SET    status = 'Draft',
           updatedby = p_reopenedby,
           updatedat = (now() at time zone 'utc')
    WHERE  waterpayrollrunid = p_waterpayrollrunid
      AND  farmid = p_farmid
      AND  status = 'Posted'
      AND  wateremployeeloanrepaymentid IS NULL;

    -- If currently Paid, reverse the cash transaction + refund the cash account.
    IF v_status = 'Paid' AND v_cashaccountid IS NOT NULL AND v_netpay > 0 THEN
        INSERT INTO watercashtransactions (
            farmid, watercashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, description, createdby, approvedby, approvedat
        )
        VALUES (
            p_farmid, v_cashaccountid, (now() AT TIME ZONE 'utc'), 'Adjustment',
            'Payroll', p_waterpayrollrunid, v_netpay,
            concat('Payroll reopened � reversal',
                   CASE WHEN p_reason IS NULL THEN '' ELSE ': ' || p_reason END),
            p_reopenedby, p_reopenedby, (now() AT TIME ZONE 'utc')
        );

        UPDATE watercashaccounts a
        SET    currentbalance = a.currentbalance + v_netpay,
               updatedat      = (now() AT TIME ZONE 'utc')
        WHERE  a.watercashaccountid = v_cashaccountid;
    END IF;

    -- Flip the run to Reopened. Audit cols set; Paid* stays as historical
    -- record of the prior approval/payment cycle.
    UPDATE waterpayrollruns r
    SET    status       = 'Reopened',
           reopenedby   = p_reopenedby,
           reopenedat   = (now() AT TIME ZONE 'utc'),
           reopenreason = p_reason,
           updatedat    = (now() AT TIME ZONE 'utc')
    WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid;

    -- Reverse the linked expense - IsDeleted=TRUE so the filtered unique index
    -- frees up for a fresh active row when the run is reapproved later.
    UPDATE waterexpenses e
    SET    status    = 'Cancelled',
           isdeleted = TRUE,
           notes     = left(COALESCE(e.notes, '') || chr(10) || 'Payroll reopened'
                            || CASE WHEN p_reason IS NULL THEN '' ELSE ': ' || p_reason END, 1000),
           updatedat = (now() AT TIME ZONE 'utc')
    WHERE  e.farmid = p_farmid AND e.sourcetype = 'Payroll'
      AND  e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE;

    -- ---- 317: and the advance top-up 316 added ------------------------------
    -- Cancelled the same way and at the same moment as the payroll expense it
    -- belongs to, so the two cannot disagree about whether this run's cost
    -- exists. Soft-deleted, not removed: water cancels its expenses rather than
    -- deleting them, and this follows that rather than inventing a second rule.
    UPDATE waterexpenses e
    SET    status    = 'Cancelled',
           isdeleted = TRUE,
           updatedat = (now() at time zone 'utc')
    WHERE  e.farmid = p_farmid
      AND  e.sourcetype = 'PayrollEmployeeLoan'
      AND  e.sourceid = p_waterpayrollrunid
      AND  e.isdeleted = FALSE;
END;
$function$;

DO $checks$
DECLARE v_body text; v_bad integer;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_body
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'spwaterpayrollrun_unapprove' LIMIT 1;

    IF v_body IS NULL OR position('spwateremployeeloanrepayment_reverse' in v_body) = 0 THEN
        RAISE EXCEPTION
            '317: spwaterpayrollrun_unapprove does not reverse advance repayments.';
    END IF;
    IF position('PayrollEmployeeLoan' in v_body) = 0 THEN
        RAISE EXCEPTION '317: the advance top-up is not cancelled on unapproval.';
    END IF;

    SELECT pg_get_functiondef(p.oid) INTO v_body
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'spwaterpayrollrun_approve' LIMIT 1;
    IF v_body IS NULL OR position('spwateremployeeloanrepayment_record' in v_body) = 0 THEN
        RAISE EXCEPTION '317: migration 316 has not been applied. Apply 316 and 317 together.';
    END IF;

    -- No run that is no longer approved may still hold a live repayment.
    SELECT COUNT(*) INTO v_bad
    FROM   wateremployeeloanrepayments r
    JOIN   waterpayrollruns pr ON pr.waterpayrollrunid = r.waterpayrollrunid
    WHERE  r.sourcetype = 'Payroll' AND r.status = 'Posted'
      AND  pr.status IN ('Reopened', 'Draft', 'Cancelled');
    IF v_bad > 0 THEN
        RAISE EXCEPTION
            '317: % advance repayment(s) are still posted against a payroll that is no longer approved.', v_bad;
    END IF;

    SELECT COUNT(*) INTO v_bad FROM wateremployeeloans l
    WHERE  l.outstandingbalance > l.totalrepayable;
    IF v_bad > 0 THEN
        RAISE EXCEPTION '317: % advance(s) now owe more than they are worth.', v_bad;
    END IF;

    RAISE NOTICE '317_WaterPayrollUnapproveReversesRepayments: unapproval reverses repayments, verified.';
END
$checks$;

-- =============================================================================
-- 442_PoultryPayrollLineKeepCredit.postgres.sql
--
-- Purpose
-- -------
-- Let the payroll line form say, in one step, "keep this much of the wage as
-- employee credit" (441), next to the other deductions -- instead of add the
-- line, find its deductions, add a typed deduction.
--
-- THE BUG UNDERNEATH (fixed here, needed for the above)
-- =====================================================
-- fnpoultrypayrollitem_recalcdeductions (306) RECONCILED: if the line's total
-- was more than legacy + structured rows, the difference was moved into
-- legacydeductions ("someone typed in the old box"). But the same thing
-- happens whenever a structured row is REMOVED or LOWERED: the old total is
-- still on the line, so the removed amount was silently turned into an
-- unexplained "Other deduction" and net pay never went back up. Deleting a
-- 500 employee-credit row left 500 deducted.
--
-- The fix is to stop inferring. legacydeductions -- the "Other deductions"
-- typed on the line -- is now WRITTEN by sppoultrypayrollitem_upsert, and the
-- recalc is a plain sum:
--
--   deductions = legacydeductions + SUM(live structured rows)
--
-- sppoultrypayrollitem_upsert
--   p_otherdeductions (new)  -> legacydeductions, exactly.
--   p_deductions (old)       -> when p_otherdeductions is NULL, keeps its old
--                               meaning of the line TOTAL: legacy = total minus
--                               the structured rows already on the line. Old
--                               callers (templates 419, older clients) work
--                               unchanged.
--   p_employeecredit (new)   -> NULL leaves the line's draft "keep as employee
--                               credit" alone; a number replaces it (0 removes).
--   Also accepts a Reopened run, like every other payroll-line write (306).
--
-- Backfill: lines whose stored total disagrees with legacy + structured get
-- legacy = total - structured. No line's total or net pay changes.
--
-- Idempotent. Safe to run more than once.
-- EFFECT ON TODAY'S NUMBERS: none (checked by apply-payroll-line-credit.ps1).
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Backfill, BEFORE the recalc stops reconciling.
-- -----------------------------------------------------------------------------
UPDATE poultrypayrollitems i
SET    legacydeductions = i.deductions - COALESCE(s.amt, 0)
FROM  (SELECT it.poultrypayrollitemid,
              (SELECT COALESCE(SUM(d.amount), 0) FROM poultrypayrollitemdeductions d
               WHERE  d.poultrypayrollitemid = it.poultrypayrollitemid
                 AND  d.status <> 'Reversed') AS amt
       FROM   poultrypayrollitems it) s
WHERE  s.poultrypayrollitemid = i.poultrypayrollitemid
  AND  i.deductions <> i.legacydeductions + COALESCE(s.amt, 0)
  AND  i.deductions >= COALESCE(s.amt, 0);

-- -----------------------------------------------------------------------------
-- 2. Recalc: a sum, nothing inferred.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrypayrollitem_recalcdeductions(p_poultrypayrollitemid integer)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_runid      integer;
    v_legacy     numeric;
    v_structured numeric;
    v_total      numeric;
BEGIN
    SELECT i.poultrypayrollrunid, COALESCE(i.legacydeductions, 0)
    INTO   v_runid, v_legacy
    FROM   poultrypayrollitems i
    WHERE  i.poultrypayrollitemid = p_poultrypayrollitemid
    FOR UPDATE;

    IF v_runid IS NULL THEN
        RAISE EXCEPTION 'Payroll item % not found.', p_poultrypayrollitemid;
    END IF;

    SELECT COALESCE(SUM(d.amount), 0)
    INTO   v_structured
    FROM   poultrypayrollitemdeductions d
    WHERE  d.poultrypayrollitemid = p_poultrypayrollitemid
      AND  d.status <> 'Reversed';

    -- 442: no reconcile. A removed or lowered deduction now lowers the total.
    v_total := v_legacy + v_structured;

    UPDATE poultrypayrollitems
    SET    deductions = v_total
    WHERE  poultrypayrollitemid = p_poultrypayrollitemid;

    -- netpay is GENERATED on dev; the write is refused there, which is fine.
    BEGIN
        UPDATE poultrypayrollitems i
        SET    netpay = i.basicpay + i.dailywage + i.commission + i.bonus - i.deductions
        WHERE  i.poultrypayrollitemid = p_poultrypayrollitemid;
    EXCEPTION
        WHEN generated_always THEN NULL;
    END;

    UPDATE poultrypayrollruns r
    SET    totalgrosspay   = agg.gross,
           totaldeductions = agg.ded,
           totalnetpay     = agg.net,
           updatedat       = (now() at time zone 'utc')
    FROM (
        SELECT COALESCE(SUM(i.basicpay + i.dailywage + i.commission + i.bonus), 0) AS gross,
               COALESCE(SUM(i.deductions), 0) AS ded,
               COALESCE(SUM(i.netpay), 0)     AS net
        FROM   poultrypayrollitems i
        WHERE  i.poultrypayrollrunid = v_runid
    ) agg
    WHERE  r.poultrypayrollrunid = v_runid;

    RETURN v_total;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Line upsert: other deductions + keep-as-credit in one call.
-- Dropped BY NAME: the new parameters change the signature, and a stale
-- overload left behind would be picked by older named-argument calls.
-- -----------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT p.oid::regprocedure AS sig FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'sppoultrypayrollitem_upsert'
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig;
    END LOOP;
END $$;

CREATE FUNCTION public.sppoultrypayrollitem_upsert(
    p_poultrypayrollrunid integer,
    p_farmid text,
    p_poultrystaffid integer,
    p_basicpay numeric DEFAULT 0,
    p_dailywage numeric DEFAULT 0,
    p_commission numeric DEFAULT 0,
    p_bonus numeric DEFAULT 0,
    p_deductions numeric DEFAULT 0,
    p_paymentmethod text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text,
    p_otherdeductions numeric DEFAULT NULL::numeric,
    p_employeecredit numeric DEFAULT NULL::numeric,
    p_savedby text DEFAULT NULL::text)
 RETURNS TABLE(poultrypayrollitemid integer, poultrypayrollrunid integer, poultrystaffid integer, basicpay numeric, dailywage numeric, commission numeric, bonus numeric, deductions numeric, netpay numeric, paymentmethod text, notes text, createdat timestamp without time zone)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_runstatus  text;
    v_itemid     integer;
    v_structured numeric;
    v_legacy     numeric;
    v_net        numeric;
BEGIN
    SELECT r.status INTO v_runstatus
    FROM   poultrypayrollruns r
    WHERE  r.poultrypayrollrunid = p_poultrypayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE;

    IF v_runstatus IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found for this farm.';
    END IF;
    -- 442: Reopened too, the same pair every other line write accepts (306).
    IF v_runstatus NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION 'This payroll is %. Reopen it before changing its lines.', v_runstatus;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM poultrystaff st
                   WHERE st.poultrystaffid = p_poultrystaffid AND st.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Staff % not found on this farm.', p_poultrystaffid;
    END IF;

    IF (COALESCE(p_basicpay, 0) < 0 OR COALESCE(p_dailywage, 0) < 0 OR COALESCE(p_commission, 0) < 0
        OR COALESCE(p_bonus, 0) < 0 OR COALESCE(p_deductions, 0) < 0
        OR COALESCE(p_otherdeductions, 0) < 0 OR COALESCE(p_employeecredit, 0) < 0) THEN
        RAISE EXCEPTION 'Pay and deductions cannot be negative.';
    END IF;

    SELECT i.poultrypayrollitemid INTO v_itemid
    FROM   poultrypayrollitems i
    WHERE  i.poultrypayrollrunid = p_poultrypayrollrunid AND i.poultrystaffid = p_poultrystaffid;

    IF v_itemid IS NULL THEN
        INSERT INTO poultrypayrollitems (
            poultrypayrollrunid, poultrystaffid, basicpay, dailywage, commission, bonus,
            deductions, legacydeductions, paymentmethod, notes)
        VALUES (
            p_poultrypayrollrunid, p_poultrystaffid, COALESCE(p_basicpay, 0), COALESCE(p_dailywage, 0),
            COALESCE(p_commission, 0), COALESCE(p_bonus, 0), 0, 0, p_paymentmethod, p_notes)
        RETURNING poultrypayrollitems.poultrypayrollitemid INTO v_itemid;
    ELSE
        UPDATE poultrypayrollitems i
        SET    basicpay = COALESCE(p_basicpay, 0), dailywage = COALESCE(p_dailywage, 0),
               commission = COALESCE(p_commission, 0), bonus = COALESCE(p_bonus, 0),
               paymentmethod = p_paymentmethod, notes = p_notes
        WHERE  i.poultrypayrollitemid = v_itemid;
    END IF;

    -- Keep as employee credit: replace the line's DRAFT credit rows. Rows of a
    -- reopened run were put back to Draft by the unapprove, so this covers it.
    IF p_employeecredit IS NOT NULL THEN
        DELETE FROM poultrypayrollitemdeductions d
        WHERE  d.poultrypayrollitemid = v_itemid
          AND  d.deductiontype = 'EmployeeCredit'
          AND  d.status = 'Draft';
        IF p_employeecredit > 0 THEN
            INSERT INTO poultrypayrollitemdeductions (
                farmid, poultrypayrollrunid, poultrypayrollitemid, poultrystaffid,
                deductiontype, amount, poultryemployeeloanid, description, status, createdby)
            VALUES (
                p_farmid, p_poultrypayrollrunid, v_itemid, p_poultrystaffid,
                'EmployeeCredit', p_employeecredit, NULL, 'Kept from wages', 'Draft', p_savedby);
        END IF;
    END IF;

    -- Other deductions: given exactly, or derived from an old-style total.
    IF p_otherdeductions IS NOT NULL THEN
        v_legacy := p_otherdeductions;
    ELSE
        SELECT COALESCE(SUM(d.amount), 0) INTO v_structured
        FROM   poultrypayrollitemdeductions d
        WHERE  d.poultrypayrollitemid = v_itemid AND d.status <> 'Reversed';
        v_legacy := GREATEST(COALESCE(p_deductions, 0) - v_structured, 0);
    END IF;

    UPDATE poultrypayrollitems i SET legacydeductions = v_legacy WHERE i.poultrypayrollitemid = v_itemid;
    PERFORM public.fnpoultrypayrollitem_recalcdeductions(v_itemid);

    SELECT i.netpay INTO v_net FROM poultrypayrollitems i WHERE i.poultrypayrollitemid = v_itemid;
    IF v_net < 0 THEN
        RAISE EXCEPTION 'Deductions (%) are more than this line''s pay. Net pay cannot be negative.',
            (SELECT i.deductions FROM poultrypayrollitems i WHERE i.poultrypayrollitemid = v_itemid);
    END IF;

    RETURN QUERY
    SELECT i.poultrypayrollitemid, i.poultrypayrollrunid, i.poultrystaffid,
           i.basicpay, i.dailywage, i.commission, i.bonus, i.deductions, i.netpay,
           i.paymentmethod::text, i.notes::text, i.createdat
    FROM   poultrypayrollitems i
    WHERE  i.poultrypayrollitemid = v_itemid;
END;
$function$;

COMMIT;

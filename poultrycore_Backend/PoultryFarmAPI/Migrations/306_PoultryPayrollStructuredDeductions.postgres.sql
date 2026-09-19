-- =============================================================================
-- 306_PoultryPayrollStructuredDeductions.postgres.sql
--
-- Purpose
-- -------
-- Make a payroll deduction say WHAT IT IS.
--
-- Today an item row carries `deductions = 100` and nothing else. The farm can
-- see that Agya Abuu was docked 100 and cannot see why, which is the whole
-- complaint. This file adds the detail behind that number -- starting with the
-- one that matters, an employee loan repayment -- without changing what the
-- number means to anything that already reads it.
--
-- THE CONSTRAINT THAT DECIDES THE DESIGN
-- ======================================
-- poultrypayrollitems.netpay is COMPUTED from deductions:
--
--     netpay = basicpay + dailywage + commission + bonus - deductions
--
-- (migration 130 declared it PERSISTED; the Postgres conversion carries it as a
-- generated column). So `deductions` cannot be retired in favour of a detail
-- table, and it cannot be left behind either. Structured rows must DRIVE it:
--
--     items.deductions = legacydeductions + SUM(structured rows not reversed)
--
-- Every net pay ever calculated stays exactly what it was, because the scalar
-- the formula reads is still the scalar the formula reads. Nothing in this file
-- touches netpay, and nothing needs to.
--
-- WHAT legacydeductions IS FOR
-- ============================
-- Section 29 and 87: existing runs carry an amount with no explanation, and
-- reinterpreting it would be a lie. Inventing an EmployeeLoan record to
-- "explain" a 2024 deduction would be a worse lie.
--
-- So the bare amount gets a column of its own. It is backfilled from today's
-- `deductions` for every item that exists, which by definition has no
-- structured rows, and from then on it is the UNEXPLAINED REMAINDER: whatever
-- the total is that the structured rows do not account for. It surfaces in the
-- breakdown as one row labelled by the caller as Other / Legacy Deduction, and
-- it is a computed leftover rather than a record, so no fake history is created.
--
-- It also means the OLD UI KEEPS WORKING UNCHANGED. A user who types 100 into
-- the existing Deductions box still gets a deduction of 100; it simply lands in
-- the unexplained bucket, and the reconcile step at the top of every save below
-- notices and leaves it there. This file replaces no existing payroll function
-- and alters no existing payroll behaviour -- it is purely additive, which is
-- also why it can be applied while runs are open.
--
-- DRAFT MEANS PLANNED
-- ===================
-- Section 38, non-negotiable: a deduction on an unapproved run changes no loan
-- balance. Nothing here writes to poultryemployeeloans or
-- poultryemployeeloanrepayments. A deduction row is an INTENTION; 309 turns it
-- into a repayment at approval, and only then. That is why this file's rows
-- start at status 'Draft'.
--
-- "Unapproved" means status 'Draft' OR 'Reopened'. The live
-- sppoultrypayrollrun_unapprove sets a reopened run to 'Reopened' and _approve
-- accepts both -- so both are editable here. Refusing 'Reopened' would make the
-- reverse, change the deduction, re-approve cycle of section 44 impossible.
--
-- Idempotent. Safe to run more than once.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The unexplained remainder.
--
-- Added and backfilled in one step. Every item that exists right now has a
-- total with no detail behind it, so for all of them the whole amount is
-- unexplained -- which is the truth, and is what the backfill states.
-- -----------------------------------------------------------------------------
ALTER TABLE poultrypayrollitems
    ADD COLUMN IF NOT EXISTS legacydeductions numeric(14,2) NOT NULL DEFAULT 0;

-- The backfill itself is in section 2a, after the detail table exists -- it
-- needs to ask whether a line has any structured rows, and that is the only
-- honest way to write a guard that survives a re-run.

COMMENT ON COLUMN poultrypayrollitems.legacydeductions IS
    'The part of `deductions` that no structured row explains. Backfilled from '
    '`deductions` for every item that predates migration 306, and thereafter '
    'whatever a bare amount typed into the old Deductions box leaves over. '
    'Shown in the breakdown as one Other / Legacy row; never a real record.';

-- -----------------------------------------------------------------------------
-- 2. The detail.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultrypayrollitemdeductions (
    poultrypayrollitemdeductionid serial PRIMARY KEY,
    farmid               varchar(450) NOT NULL,
    poultrypayrollrunid  integer NOT NULL
                         REFERENCES poultrypayrollruns (poultrypayrollrunid),
    poultrypayrollitemid integer NOT NULL
                         REFERENCES poultrypayrollitems (poultrypayrollitemid) ON DELETE CASCADE,
    -- Denormalised so a deduction can be checked against the advance's owner
    -- without walking back up to the item.
    poultrystaffid       integer NOT NULL REFERENCES poultrystaff (poultrystaffid),

    -- Section 28. Statutory deduction types are deliberately absent: this is
    -- still lightweight payroll, and adding PAYE/SSNIT here would make a full
    -- statutory engine a dependency of employee loans.
    deductiontype text NOT NULL
                  CHECK (deductiontype IN ('EmployeeLoanRepayment',
                                           'SalaryAdvanceRepayment',
                                           'OtherDeduction')),

    amount numeric(14,2) NOT NULL CHECK (amount > 0),

    -- Which advance this is repaying. Required for the two repayment types and
    -- forbidden for OtherDeduction, so "a loan repayment against no loan" and
    -- "a uniform charge that quietly reduces a receivable" are both
    -- unrepresentable.
    poultryemployeeloanid integer NULL
                          REFERENCES poultryemployeeloans (poultryemployeeloanid),

    -- Filled in by 309 when approval turns this intention into a repayment.
    -- NULL on a Draft, which is how you can tell nothing has been posted.
    poultryemployeeloanrepaymentid integer NULL
                          REFERENCES poultryemployeeloanrepayments (poultryemployeeloanrepaymentid),

    description text NULL,
    reference   text NULL,

    status text NOT NULL DEFAULT 'Draft'
           CHECK (status IN ('Draft', 'Posted', 'Reversed')),

    createdby      text NULL,
    createdat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby      text NULL,
    updatedat      timestamp NULL,
    reversedby     text NULL,
    reversedat     timestamp NULL,
    reversalreason text NULL,

    CONSTRAINT ck_poultrypayrollitemdeductions_loan
        CHECK ((deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment')
                AND poultryemployeeloanid IS NOT NULL)
            OR (deductiontype = 'OtherDeduction'
                AND poultryemployeeloanid IS NULL)),
    -- A repayment can only hang off a deduction that has been posted.
    CONSTRAINT ck_poultrypayrollitemdeductions_posted
        CHECK (poultryemployeeloanrepaymentid IS NULL OR status <> 'Draft')
);

CREATE INDEX IF NOT EXISTS ix_poultrypayrollitemdeductions_item
    ON poultrypayrollitemdeductions (poultrypayrollitemid, status);
CREATE INDEX IF NOT EXISTS ix_poultrypayrollitemdeductions_run
    ON poultrypayrollitemdeductions (poultrypayrollrunid, status);
CREATE INDEX IF NOT EXISTS ix_poultrypayrollitemdeductions_loan
    ON poultrypayrollitemdeductions (poultryemployeeloanid)
    WHERE poultryemployeeloanid IS NOT NULL;

COMMENT ON TABLE poultrypayrollitemdeductions IS
    'What a payroll deduction actually IS. A Draft row is an intention and '
    'changes no loan balance (spec section 38); 309 turns it into an '
    'EmployeeLoanRepayment at approval and writes the id back here.';

-- -----------------------------------------------------------------------------
-- 2a. Backfill the remainder.
--
-- Every line that carries a total today has no detail behind it, so the whole
-- amount is unexplained -- which is the truth, and is what this states.
--
-- Self-guarding, so a re-run is a no-op: a line that has already been
-- backfilled has a non-zero remainder, and a line whose remainder has since
-- been consumed by structured rows is excluded by the NOT EXISTS. No
-- table-existence tricks, no marker rows.
-- -----------------------------------------------------------------------------
DO $$
DECLARE v_rows integer;
BEGIN
    UPDATE poultrypayrollitems i
    SET    legacydeductions = i.deductions
    WHERE  i.deductions <> 0
      AND  i.legacydeductions = 0
      AND  NOT EXISTS (SELECT 1 FROM poultrypayrollitemdeductions d
                        WHERE d.poultrypayrollitemid = i.poultrypayrollitemid);
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE '306: backfilled legacydeductions on % existing payroll line(s).', v_rows;
END $$;

-- The FK that 305 could not declare, because this table did not exist yet.
DO $$
BEGIN
    -- ON DELETE SET NULL, not the default refusal: deleting a payroll run
    -- cascades to its deductions, and a REVERSED repayment still points back at
    -- the one that created it. Refusing there made a reopened run undeletable.
    -- A POSTED repayment is a different matter and is stopped by the trigger in
    -- migration 312 instead, which is where this was found and fixed.
    ALTER TABLE poultryemployeeloanrepayments
        ADD CONSTRAINT fk_poultryemployeeloanrepayments_deduction
        FOREIGN KEY (poultrypayrolldeductionid)
        REFERENCES poultrypayrollitemdeductions (poultrypayrollitemdeductionid)
        ON DELETE SET NULL;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- -----------------------------------------------------------------------------
-- 3. Put the totals back in step.
--
-- The one place that writes items.deductions and the run totals, so there is
-- exactly one definition of what a total is:
--
--   item.deductions      = legacydeductions + SUM(live structured rows)
--   run.totaldeductions  = SUM(item.deductions)
--   run.totalgrosspay    = SUM(earnings)
--   run.totalnetpay      = SUM(item.netpay)          -- read, never written
--
-- Reversed rows are excluded, which is what makes a reversal take effect on
-- the payslip rather than only in the history.
--
-- RECONCILE FIRST. If the item's current total is MORE than the remainder plus
-- the structured rows, someone typed into the old Deductions box since the last
-- save; the difference is unexplained by definition, so it is added to the
-- remainder rather than silently erased. This is what lets the old UI and the
-- new one coexist without either having to know about the other.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrypayrollitem_recalcdeductions(
    p_poultrypayrollitemid integer
) RETURNS numeric
LANGUAGE plpgsql
AS $function$
DECLARE
    v_runid      integer;
    v_current    numeric;
    v_legacy     numeric;
    v_structured numeric;
    v_total      numeric;
BEGIN
    SELECT i.poultrypayrollrunid, i.deductions, i.legacydeductions
    INTO   v_runid, v_current, v_legacy
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

    -- The reconcile described above.
    IF v_current > v_legacy + v_structured THEN
        v_legacy := v_current - v_structured;
    END IF;

    v_total := v_legacy + v_structured;

    UPDATE poultrypayrollitems
    SET    legacydeductions = v_legacy,
           deductions       = v_total
    WHERE  poultrypayrollitemid = p_poultrypayrollitemid;

    -- netpay: migration 130 declared it a PERSISTED computed column in T-SQL,
    -- and if the Postgres conversion kept it GENERATED then the UPDATE above
    -- has already recomputed it and writing it is not allowed. If the
    -- conversion flattened it into an ordinary column -- which cannot be
    -- confirmed from this repo, because the converted payroll functions were
    -- never checked in -- then it is now STALE and every net pay on the run is
    -- wrong. So: try to write it, and treat the refusal as the good news.
    -- 428C9 is raised only by a generated column, so this catches nothing else.
    BEGIN
        UPDATE poultrypayrollitems i
        SET    netpay = i.basicpay + i.dailywage + i.commission + i.bonus - i.deductions
        WHERE  i.poultrypayrollitemid = p_poultrypayrollitemid;
    EXCEPTION
        WHEN generated_always THEN NULL;
    END;

    -- Roll the run. Recomputed from the items rather than adjusted by a delta,
    -- so a run's totals can never drift away from its own lines.
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
-- 4. Add or change a deduction.
--
-- Draft runs only. An approved run's deductions have already become
-- repayments, and editing one behind the payroll's back would leave the
-- payslip and the advance telling different stories -- so the answer is
-- unapprove, edit, re-approve, which 310 and 309 make safe.
--
-- The loan checks here are the SAME ones sppoultryemployeeloanrepayment_record
-- applies at posting time. Checking twice is deliberate: this one gives the
-- user an error while they can still fix it, and that one is the guarantee.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrypayrollitemdeduction_save(
    p_farmid                text,
    p_poultrypayrollitemid  integer,
    p_deductiontype         text,
    p_amount                numeric,
    p_poultryemployeeloanid integer DEFAULT NULL,
    p_description           text DEFAULT NULL,
    p_reference             text DEFAULT NULL,
    -- Given to edit an existing row, omitted to add one.
    p_poultrypayrollitemdeductionid integer DEFAULT NULL,
    p_savedby               text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id          integer := p_poultrypayrollitemdeductionid;
    v_runid       integer;
    v_staffid     integer;
    v_runstatus   text;
    v_type        text := NULLIF(btrim(p_deductiontype), '');
    v_amount      numeric := COALESCE(p_amount, 0);
    v_loanstaff   integer;
    v_loanstatus  text;
    v_outstanding numeric;
    v_number      text;
    v_claimed     numeric;
BEGIN
    IF v_amount <= 0 THEN
        RAISE EXCEPTION 'A deduction must be more than zero.';
    END IF;
    IF v_type IS NULL THEN
        RAISE EXCEPTION 'Say what kind of deduction this is.';
    END IF;

    SELECT i.poultrypayrollrunid, i.poultrystaffid, r.status
    INTO   v_runid, v_staffid, v_runstatus
    FROM   poultrypayrollitems i
    JOIN   poultrypayrollruns r ON r.poultrypayrollrunid = i.poultrypayrollrunid
    WHERE  i.poultrypayrollitemid = p_poultrypayrollitemid
      AND  r.farmid = p_farmid;

    IF v_runid IS NULL THEN
        RAISE EXCEPTION 'Payroll line not found on this farm.';
    END IF;
    -- 'Reopened', not just 'Draft'. sppoultrypayrollrun_unapprove sets a
    -- reopened run to 'Reopened' and _approve accepts both, so a deduction has
    -- to be editable in both states -- otherwise the reverse, change the
    -- deduction, re-approve cycle that spec section 44 requires is impossible:
    -- you could unapprove the payroll and then not be allowed to touch it.
    IF v_runstatus NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION
            'This payroll is %. Reopen it before changing deductions.', v_runstatus;
    END IF;

    IF v_type IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment') THEN
        IF p_poultryemployeeloanid IS NULL THEN
            RAISE EXCEPTION 'Choose which advance this repayment is against.';
        END IF;

        SELECT l.poultrystaffid, l.status, l.outstandingbalance, l.loannumber
        INTO   v_loanstaff, v_loanstatus, v_outstanding, v_number
        FROM   poultryemployeeloans l
        WHERE  l.poultryemployeeloanid = p_poultryemployeeloanid
          AND  l.farmid = p_farmid;

        IF v_loanstaff IS NULL THEN
            RAISE EXCEPTION 'Advance not found on this farm.';
        END IF;
        -- Section 33, enforced on the server. The dropdown is a convenience;
        -- this is the rule.
        IF v_loanstaff <> v_staffid THEN
            RAISE EXCEPTION 'That advance belongs to a different member of staff.';
        END IF;
        IF v_loanstatus <> 'Active' THEN
            RAISE EXCEPTION 'Advance % is %, so nothing can be deducted against it.',
                COALESCE(v_number, p_poultryemployeeloanid::text), v_loanstatus;
        END IF;

        -- Section 34. What this run ALREADY plans to take off the same advance
        -- counts against the balance, or two 300 deductions could both pass
        -- against a 500 balance and only fail at approval -- which is the worst
        -- possible moment to find out.
        SELECT COALESCE(SUM(d.amount), 0)
        INTO   v_claimed
        FROM   poultrypayrollitemdeductions d
        WHERE  d.poultryemployeeloanid = p_poultryemployeeloanid
          AND  d.status = 'Draft'
          AND  (v_id IS NULL OR d.poultrypayrollitemdeductionid <> v_id);

        IF v_amount + v_claimed > v_outstanding THEN
            IF v_claimed > 0 THEN
                RAISE EXCEPTION
                    'Only % is left on advance %, and % of it is already planned in a draft payroll.',
                    v_outstanding, COALESCE(v_number, p_poultryemployeeloanid::text), v_claimed;
            ELSE
                RAISE EXCEPTION 'Only % is left on advance %.',
                    v_outstanding, COALESCE(v_number, p_poultryemployeeloanid::text);
            END IF;
        END IF;
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO poultrypayrollitemdeductions (
            farmid, poultrypayrollrunid, poultrypayrollitemid, poultrystaffid,
            deductiontype, amount, poultryemployeeloanid,
            description, reference, status, createdby)
        VALUES (
            p_farmid, v_runid, p_poultrypayrollitemid, v_staffid,
            v_type, v_amount,
            CASE WHEN v_type = 'OtherDeduction' THEN NULL ELSE p_poultryemployeeloanid END,
            NULLIF(btrim(p_description), ''), NULLIF(btrim(p_reference), ''),
            'Draft', p_savedby)
        RETURNING poultrypayrollitemdeductionid INTO v_id;
    ELSE
        UPDATE poultrypayrollitemdeductions d
        SET    deductiontype = v_type,
               amount = v_amount,
               poultryemployeeloanid =
                   CASE WHEN v_type = 'OtherDeduction' THEN NULL
                        ELSE p_poultryemployeeloanid END,
               description = NULLIF(btrim(p_description), ''),
               reference   = NULLIF(btrim(p_reference), ''),
               updatedby   = p_savedby,
               updatedat   = (now() at time zone 'utc')
        WHERE  d.poultrypayrollitemdeductionid = v_id
          AND  d.farmid = p_farmid
          AND  d.status = 'Draft';

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'Deduction % cannot be edited -- it is not a draft on this farm.', v_id;
        END IF;
    END IF;

    PERFORM public.fnpoultrypayrollitem_recalcdeductions(p_poultrypayrollitemid);
    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Remove a deduction.
--
-- A Draft row has posted nothing, so it is genuinely deletable -- there is no
-- financial history to protect. A Posted one is not: it has an advance
-- repayment behind it, and the way to undo that is to unapprove the payroll.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrypayrollitemdeduction_delete(
    p_farmid text,
    p_poultrypayrollitemdeductionid integer,
    p_deletedby text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_itemid  integer;
    v_status  text;
    v_runstat text;
BEGIN
    SELECT d.poultrypayrollitemid, d.status, r.status
    INTO   v_itemid, v_status, v_runstat
    FROM   poultrypayrollitemdeductions d
    JOIN   poultrypayrollruns r ON r.poultrypayrollrunid = d.poultrypayrollrunid
    WHERE  d.poultrypayrollitemdeductionid = p_poultrypayrollitemdeductionid
      AND  d.farmid = p_farmid;

    IF v_itemid IS NULL THEN
        RAISE EXCEPTION 'Deduction % not found on this farm.', p_poultrypayrollitemdeductionid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION
            'This deduction has been posted to an advance. Unapprove the payroll to undo it.';
    END IF;
    -- Same pair of states as the save above, for the same reason.
    IF v_runstat NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION 'This payroll is %. Reopen it before changing deductions.', v_runstat;
    END IF;

    DELETE FROM poultrypayrollitemdeductions
    WHERE  poultrypayrollitemdeductionid = p_poultrypayrollitemdeductionid;

    PERFORM public.fnpoultrypayrollitem_recalcdeductions(v_itemid);
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. The breakdown behind one line's Deductions figure.
--
-- Returns the structured rows AND, when the total is not fully explained by
-- them, one synthetic row for the remainder. The synthetic row has a NULL id,
-- which is how the caller knows it is a leftover and not a record it can edit
-- or delete -- and is why section 29's "do not create fake EmployeeLoan
-- records" is satisfied by construction: there is nothing to create.
--
-- The rows always add up to items.deductions. That is the contract this
-- function exists to keep.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrypayrollitemdeduction_getall(
    p_farmid               text,
    p_poultrypayrollitemid integer
) RETURNS TABLE(
    poultrypayrollitemdeductionid integer,
    poultrypayrollitemid integer,
    poultrystaffid integer,
    deductiontype text,
    amount numeric,
    poultryemployeeloanid integer,
    loannumber text,
    loantype text,
    loanoutstanding numeric,
    poultryemployeeloanrepaymentid integer,
    description text,
    reference text,
    status text,
    islegacy boolean,
    createdby text,
    createdat timestamp
)
LANGUAGE sql
AS $function$
    SELECT d.poultrypayrollitemdeductionid, d.poultrypayrollitemid, d.poultrystaffid,
           d.deductiontype, d.amount,
           d.poultryemployeeloanid, l.loannumber, l.loantype, l.outstandingbalance,
           d.poultryemployeeloanrepaymentid,
           d.description, d.reference, d.status,
           FALSE AS islegacy,
           d.createdby, d.createdat
    FROM   poultrypayrollitemdeductions d
    LEFT   JOIN poultryemployeeloans l
           ON l.poultryemployeeloanid = d.poultryemployeeloanid
    WHERE  d.farmid = p_farmid
      AND  d.poultrypayrollitemid = p_poultrypayrollitemid

    UNION ALL

    -- The remainder. Not a record: a subtraction.
    SELECT NULL::integer, i.poultrypayrollitemid, i.poultrystaffid,
           'OtherDeduction'::text,
           (i.deductions - COALESCE((SELECT SUM(d2.amount)
                                       FROM poultrypayrollitemdeductions d2
                                      WHERE d2.poultrypayrollitemid = i.poultrypayrollitemid
                                        AND d2.status <> 'Reversed'), 0))::numeric(14,2),
           NULL::integer, NULL::text, NULL::text, NULL::numeric,
           NULL::integer,
           'Entered before deductions were itemised'::text, NULL::text,
           'Posted'::text,
           TRUE AS islegacy,
           NULL::text, NULL::timestamp
    FROM   poultrypayrollitems i
    JOIN   poultrypayrollruns r ON r.poultrypayrollrunid = i.poultrypayrollrunid
    WHERE  r.farmid = p_farmid
      AND  i.poultrypayrollitemid = p_poultrypayrollitemid
      AND  (i.deductions - COALESCE((SELECT SUM(d2.amount)
                                       FROM poultrypayrollitemdeductions d2
                                      WHERE d2.poultrypayrollitemid = i.poultrypayrollitemid
                                        AND d2.status <> 'Reversed'), 0)) > 0

    ORDER  BY islegacy, deductiontype, poultrypayrollitemdeductionid;
$function$;

-- -----------------------------------------------------------------------------
-- 7. One row per line for a whole run.
--
-- What the Employee Breakdown table needs: the totals it already shows, plus
-- enough to draw the "2 active loans" hint next to a name without a query per
-- row (sections 49 and 50).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrypayrollitemdeduction_getforrun(
    p_farmid              text,
    p_poultrypayrollrunid integer
) RETURNS TABLE(
    poultrypayrollitemid integer,
    poultrystaffid integer,
    staffname text,
    deductions numeric,
    legacydeductions numeric,
    structuredtotal numeric,
    structuredcount integer,
    loanrepaymenttotal numeric,
    activeloancount integer,
    activeloanoutstanding numeric,
    suggesteddeduction numeric
)
LANGUAGE sql
AS $function$
    SELECT i.poultrypayrollitemid, i.poultrystaffid,
           btrim(s.firstname || ' ' || s.lastname),
           i.deductions, i.legacydeductions,
           COALESCE(d.total, 0)::numeric(14,2),
           COALESCE(d.n, 0)::integer,
           COALESCE(d.loantotal, 0)::numeric(14,2),
           COALESCE(a.n, 0)::integer,
           COALESCE(a.outstanding, 0)::numeric(14,2),
           -- What the advances themselves suggest for this period. A
           -- SUGGESTION: nothing posts because of it (section 36).
           COALESCE(a.suggested, 0)::numeric(14,2)
    FROM   poultrypayrollitems i
    JOIN   poultrypayrollruns r ON r.poultrypayrollrunid = i.poultrypayrollrunid
    JOIN   poultrystaff s ON s.poultrystaffid = i.poultrystaffid
    LEFT   JOIN (
        SELECT d0.poultrypayrollitemid,
               SUM(d0.amount) AS total,
               COUNT(*) AS n,
               SUM(d0.amount) FILTER (
                   WHERE d0.deductiontype IN ('EmployeeLoanRepayment',
                                              'SalaryAdvanceRepayment')) AS loantotal
        FROM   poultrypayrollitemdeductions d0
        WHERE  d0.status <> 'Reversed'
        GROUP  BY d0.poultrypayrollitemid
    ) d ON d.poultrypayrollitemid = i.poultrypayrollitemid
    LEFT   JOIN (
        SELECT l.poultrystaffid, l.farmid,
               COUNT(*) AS n,
               SUM(l.outstandingbalance) AS outstanding,
               SUM(LEAST(COALESCE(l.defaultpayrolldeduction, 0),
                         l.outstandingbalance)) AS suggested
        FROM   poultryemployeeloans l
        WHERE  l.status = 'Active'
          AND  l.outstandingbalance > 0
          AND  l.repaymentmethod IN ('PayrollDeduction', 'Mixed')
        GROUP  BY l.poultrystaffid, l.farmid
    ) a ON a.poultrystaffid = i.poultrystaffid AND a.farmid = r.farmid
    WHERE  r.farmid = p_farmid
      AND  i.poultrypayrollrunid = p_poultrypayrollrunid
    ORDER  BY btrim(s.firstname || ' ' || s.lastname);
$function$;

-- -----------------------------------------------------------------------------
-- Verification.
--
-- The invariant is the point of the whole file, so it is asserted rather than
-- assumed: no payroll line may hold a total its parts cannot account for.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_missing text;
    v_bad     integer;
BEGIN
    SELECT string_agg(want, ', ')
    INTO   v_missing
    FROM   (VALUES
        ('fnpoultrypayrollitem_recalcdeductions'),
        ('sppoultrypayrollitemdeduction_save'),
        ('sppoultrypayrollitemdeduction_delete'),
        ('sppoultrypayrollitemdeduction_getall'),
        ('sppoultrypayrollitemdeduction_getforrun')
    ) AS w(want)
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = w.want);

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '306: missing function(s): %', v_missing;
    END IF;

    -- deductions must equal the remainder plus the live structured rows, for
    -- every line that exists. If this fires, net pay somewhere is wrong.
    SELECT COUNT(*)
    INTO   v_bad
    FROM   poultrypayrollitems i
    WHERE  i.deductions <> i.legacydeductions
           + COALESCE((SELECT SUM(d.amount) FROM poultrypayrollitemdeductions d
                        WHERE d.poultrypayrollitemid = i.poultrypayrollitemid
                          AND d.status <> 'Reversed'), 0);

    IF v_bad > 0 THEN
        RAISE EXCEPTION
            '306: % payroll line(s) hold a deductions total their parts do not explain.', v_bad;
    END IF;

    -- And net pay must still follow from the parts. This is the assertion that
    -- would catch a flattened netpay column before anyone is paid from it.
    SELECT COUNT(*)
    INTO   v_bad
    FROM   poultrypayrollitems i
    WHERE  i.netpay <> i.basicpay + i.dailywage + i.commission + i.bonus - i.deductions;

    IF v_bad > 0 THEN
        RAISE EXCEPTION
            '306: % payroll line(s) have a net pay that does not follow from their own figures.', v_bad;
    END IF;

    -- Nothing here may have touched a balance. Draft means planned.
    IF EXISTS (SELECT 1 FROM poultrypayrollitemdeductions
                WHERE status = 'Draft' AND poultryemployeeloanrepaymentid IS NOT NULL) THEN
        RAISE EXCEPTION '306: a draft deduction has already posted a repayment.';
    END IF;

    RAISE NOTICE '306_PoultryPayrollStructuredDeductions: 1 table, 1 column, 5 functions, verified.';
END $$;

-- =============================================================================
-- 451  Generic payroll, the Poultry way
-- =============================================================================
-- Gives the Generic company type the same payroll Poultry has (migrations 306,
-- 309, 310, 312, 419, 441, 442), on Generic's own tables:
--   * structured deductions per payslip line (advance repayments, other
--     deductions, wages kept as employee credit);
--   * approve posts the advance repayments (sourcetype 'Payroll', no cash) and
--     the PayrollSaving credits; reopen ("unapprove") reverses them, and from
--     Paid also puts the net pay back into the cash account;
--   * delete (soft) for Draft / Reopened / Cancelled runs;
--   * details with year-to-date figures;
--   * payroll templates.
--
-- Differences from Poultry, on purpose:
--   * No expense rows. Generic's P&L counts payroll as totalgrosspay of Paid
--     runs, and Generic Cash Flow counts Paid runs' totalnetpay, so writing
--     expense rows (as Poultry's approve does) would count wages twice.
--     rs5 (linked expense) therefore returns no rows.
--   * Reopening a Paid run returns the net pay with a CashIn row (sourcetype
--     'Payroll'), not by deleting the original CashOut, so the cash account
--     keeps its full history.
--   * Cancelling an Approved run reverses its postings first (Poultry leaves
--     them behind). A Paid run cannot be cancelled; reopen it first.
--   * Delete is a soft delete (isdeleted = TRUE); its deductions are removed.
--   * Lines can also be removed from a Reopened run (Poultry: Draft only).
-- Mark paid is Generic's existing function, unchanged.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------------
ALTER TABLE genericpayrollruns ADD COLUMN IF NOT EXISTS reopenedby               varchar(450);
ALTER TABLE genericpayrollruns ADD COLUMN IF NOT EXISTS reopenedat               timestamp without time zone;
ALTER TABLE genericpayrollruns ADD COLUMN IF NOT EXISTS reopenreason             varchar(500);
ALTER TABLE genericpayrollruns ADD COLUMN IF NOT EXISTS reapprovedby             varchar(450);
ALTER TABLE genericpayrollruns ADD COLUMN IF NOT EXISTS reapprovedat             timestamp without time zone;
ALTER TABLE genericpayrollruns ADD COLUMN IF NOT EXISTS genericpayrolltemplateid integer;

DO $c$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'genericpayrollitems'
                     AND column_name = 'legacydeductions') THEN
        ALTER TABLE genericpayrollitems ADD COLUMN legacydeductions numeric(14,2) NOT NULL DEFAULT 0;
        -- Every deduction typed before this migration is a plain "other" amount.
        UPDATE genericpayrollitems SET legacydeductions = deductions;
    END IF;
END $c$;

-- ---------------------------------------------------------------------------
-- 2. Deductions (Poultry 306 + 441 shape)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericpayrollitemdeductions (
    genericpayrollitemdeductionid  serial PRIMARY KEY,
    farmid                         varchar(450) NOT NULL,
    genericpayrollrunid            integer NOT NULL REFERENCES genericpayrollruns(genericpayrollrunid),
    genericpayrollitemid           integer NOT NULL REFERENCES genericpayrollitems(genericpayrollitemid) ON DELETE CASCADE,
    genericstaffid                 integer NOT NULL REFERENCES genericstaff(genericstaffid),
    deductiontype                  text NOT NULL CHECK (deductiontype IN
                                       ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment', 'OtherDeduction', 'EmployeeCredit')),
    amount                         numeric(14,2) NOT NULL CHECK (amount > 0),
    genericemployeeloanid          integer REFERENCES genericemployeeloans(genericemployeeloanid),
    genericemployeeloanrepaymentid integer REFERENCES genericemployeeloanrepayments(genericemployeeloanrepaymentid),
    genericemployeecreditid        integer REFERENCES genericemployeecredits(genericemployeecreditid),
    description                    text,
    reference                      text,
    status                         text NOT NULL DEFAULT 'Draft' CHECK (status IN ('Draft', 'Posted', 'Reversed')),
    createdby                      text,
    createdat                      timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updatedby                      text,
    updatedat                      timestamp without time zone,
    reversedby                     text,
    reversedat                     timestamp without time zone,
    reversalreason                 text,
    CONSTRAINT ck_genericpayrollitemdeductions_loan CHECK (
        (deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment') AND genericemployeeloanid IS NOT NULL)
        OR (deductiontype IN ('OtherDeduction', 'EmployeeCredit') AND genericemployeeloanid IS NULL)),
    CONSTRAINT ck_genericpayrollitemdeductions_posted CHECK (
        (genericemployeeloanrepaymentid IS NULL OR status <> 'Draft')
        AND (genericemployeecreditid IS NULL OR status <> 'Draft'))
);
CREATE INDEX IF NOT EXISTS ix_genericpayrollitemdeductions_item ON genericpayrollitemdeductions (genericpayrollitemid);
CREATE INDEX IF NOT EXISTS ix_genericpayrollitemdeductions_run  ON genericpayrollitemdeductions (genericpayrollrunid);
CREATE INDEX IF NOT EXISTS ix_genericpayrollitemdeductions_loan ON genericpayrollitemdeductions (genericemployeeloanid) WHERE genericemployeeloanid IS NOT NULL;

-- A posted deduction is undone by reopening the payroll, never by a delete
-- (Poultry 312).
CREATE OR REPLACE FUNCTION public.fngenericpayrolldeduction_nodelete()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_loan   text;
    v_staff  text;
    v_amount numeric;
BEGIN
    SELECT COALESCE(l.loannumber, l.genericemployeeloanid::text),
           btrim(s.firstname || ' ' || s.lastname), r.amount
    INTO   v_loan, v_staff, v_amount
    FROM   genericemployeeloanrepayments r
    JOIN   genericemployeeloans l ON l.genericemployeeloanid = r.genericemployeeloanid
    JOIN   genericstaff s ON s.genericstaffid = r.genericstaffid
    WHERE  r.genericemployeeloanrepaymentid = OLD.genericemployeeloanrepaymentid
      AND  r.status = 'Posted'
    LIMIT  1;

    IF v_loan IS NOT NULL THEN
        RAISE EXCEPTION
            'This payroll has already repaid % of %''s advance %. Reopen the payroll first -- that gives the money back; deleting it now would leave the advance short with no payslip to explain it.',
            to_char(v_amount, 'FM999999990.00'), v_staff, v_loan;
    END IF;

    IF OLD.genericemployeecreditid IS NOT NULL AND EXISTS (
        SELECT 1 FROM genericemployeecredits c
        WHERE  c.genericemployeecreditid = OLD.genericemployeecreditid AND c.status = 'Posted') THEN
        RAISE EXCEPTION
            'This payroll has already kept % as employee credit. Reopen the payroll first.',
            to_char(OLD.amount, 'FM999999990.00');
    END IF;

    RETURN OLD;
END;
$function$;

DROP TRIGGER IF EXISTS trggenericpayrolldeduction_nodelete ON genericpayrollitemdeductions;
CREATE TRIGGER trggenericpayrolldeduction_nodelete
    BEFORE DELETE ON genericpayrollitemdeductions
    FOR EACH ROW EXECUTE FUNCTION public.fngenericpayrolldeduction_nodelete();

-- ---------------------------------------------------------------------------
-- 3. Templates (Poultry 419 shape)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericpayrolltemplates (
    genericpayrolltemplateid serial PRIMARY KEY,
    farmid                   text NOT NULL,
    name                     text NOT NULL,
    frequency                text NOT NULL DEFAULT 'Monthly' CHECK (frequency IN ('Monthly', 'Fortnightly', 'Weekly')),
    genericcashaccountid     integer,
    notes                    text,
    isactive                 boolean NOT NULL DEFAULT TRUE,
    createdby                text,
    createdat                timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updatedby                text,
    updatedat                timestamp without time zone
);
CREATE INDEX IF NOT EXISTS ix_genericpayrolltemplates_farm ON genericpayrolltemplates (farmid);

CREATE TABLE IF NOT EXISTS genericpayrolltemplatelines (
    genericpayrolltemplatelineid serial PRIMARY KEY,
    genericpayrolltemplateid     integer NOT NULL REFERENCES genericpayrolltemplates(genericpayrolltemplateid) ON DELETE CASCADE,
    genericstaffid               integer NOT NULL,
    basicpay                     numeric(14,2) NOT NULL DEFAULT 0 CHECK (basicpay >= 0),
    dailywage                    numeric(14,2) NOT NULL DEFAULT 0 CHECK (dailywage >= 0),
    commission                   numeric(14,2) NOT NULL DEFAULT 0 CHECK (commission >= 0),
    bonus                        numeric(14,2) NOT NULL DEFAULT 0 CHECK (bonus >= 0),
    deductions                   numeric(14,2) NOT NULL DEFAULT 0 CHECK (deductions >= 0),
    paymentmethod                text,
    notes                        text,
    sortorder                    integer NOT NULL DEFAULT 0,
    UNIQUE (genericpayrolltemplateid, genericstaffid)
);

-- ---------------------------------------------------------------------------
-- 4. Old signatures that change shape
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spgenericpayrollrun_getall(text, text);
DROP FUNCTION IF EXISTS public.spgenericpayrollrun_getbyid_rs1(integer, text);
DROP FUNCTION IF EXISTS public.spgenericpayrollitem_upsert(integer, text, integer, numeric, numeric, numeric, numeric, numeric, text, text);

-- ---------------------------------------------------------------------------
-- 5. Reads
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericpayrollrun_getall(p_farmid text, p_status text DEFAULT NULL::text)
 RETURNS TABLE(genericpayrollrunid integer, farmid text, periodstart date, periodend date, paydate date, totalgrosspay numeric, totaldeductions numeric, totalnetpay numeric, status text, genericcashaccountid integer, cashaccountname text, notes text, createdby text, approvedby text, approvedat timestamp without time zone, paidby text, paidat timestamp without time zone, reopenedby text, reopenedat timestamp without time zone, reopenreason text, reapprovedby text, reapprovedat timestamp without time zone, createdat timestamp without time zone, updatedat timestamp without time zone)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT r.genericpayrollrunid, r.farmid::text, r.periodstart, r.periodend, r.paydate,
           r.totalgrosspay, r.totaldeductions, r.totalnetpay, r.status::text,
           r.genericcashaccountid, ca.accountname::text AS cashaccountname,
           r.notes::text, r.createdby::text, r.approvedby::text, r.approvedat, r.paidby::text, r.paidat,
           r.reopenedby::text, r.reopenedat, r.reopenreason::text, r.reapprovedby::text, r.reapprovedat,
           r.createdat, r.updatedat
    FROM   genericpayrollruns r
    LEFT   JOIN genericcashaccounts ca ON ca.genericcashaccountid = r.genericcashaccountid
    WHERE  r.farmid = p_farmid AND r.isdeleted = FALSE
       AND (p_status IS NULL OR r.status = p_status)
    ORDER  BY r.periodstart DESC, r.genericpayrollrunid DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrollrun_getbyid_rs1(p_genericpayrollrunid integer, p_farmid text)
 RETURNS TABLE(genericpayrollrunid integer, farmid text, periodstart date, periodend date, paydate date, totalgrosspay numeric, totaldeductions numeric, totalnetpay numeric, status text, genericcashaccountid integer, cashaccountname text, notes text, createdby text, approvedby text, approvedat timestamp without time zone, paidby text, paidat timestamp without time zone, reopenedby text, reopenedat timestamp without time zone, reopenreason text, reapprovedby text, reapprovedat timestamp without time zone, createdat timestamp without time zone, updatedat timestamp without time zone)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT r.genericpayrollrunid, r.farmid::text, r.periodstart, r.periodend, r.paydate,
           r.totalgrosspay, r.totaldeductions, r.totalnetpay, r.status::text,
           r.genericcashaccountid, ca.accountname::text,
           r.notes::text, r.createdby::text, r.approvedby::text, r.approvedat,
           r.paidby::text, r.paidat,
           r.reopenedby::text, r.reopenedat, r.reopenreason::text,
           r.reapprovedby::text, r.reapprovedat,
           r.createdat, r.updatedat
    FROM   genericpayrollruns r
    LEFT   JOIN genericcashaccounts ca ON ca.genericcashaccountid = r.genericcashaccountid
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid
      AND  r.isdeleted = FALSE;
END;
$function$;

-- rs2 keeps its shape (already the Poultry shape).

CREATE OR REPLACE FUNCTION public.spgenericpayrollrun_getdetailswithytd_rs1(p_genericpayrollrunid integer, p_farmid text)
 RETURNS TABLE(genericpayrollrunid integer, farmid text, periodstart date, periodend date, paydate date, totalgrosspay numeric, totaldeductions numeric, totalnetpay numeric, status text, genericcashaccountid integer, cashaccountname text, notes text, createdby text, approvedby text, approvedat timestamp without time zone, paidby text, paidat timestamp without time zone, reopenedby text, reopenedat timestamp without time zone, reopenreason text, reapprovedby text, reapprovedat timestamp without time zone, createdat timestamp without time zone, updatedat timestamp without time zone)
 LANGUAGE sql
AS $function$
    SELECT * FROM public.spgenericpayrollrun_getbyid_rs1(p_genericpayrollrunid, p_farmid);
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrollrun_getdetailswithytd_rs2(p_genericpayrollrunid integer, p_farmid text)
 RETURNS TABLE(genericpayrollitemid integer, genericpayrollrunid integer, genericstaffid integer, staffname text, staffrole text, basicpay numeric, dailywage numeric, commission numeric, bonus numeric, deductions numeric, netpay numeric, paymentmethod text, notes text, createdat timestamp without time zone)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT i.genericpayrollitemid, i.genericpayrollrunid, i.genericstaffid,
           (s.firstname || ' ' || s.lastname)::text, s.role::text,
           i.basicpay, i.dailywage, i.commission, i.bonus, i.deductions, i.netpay,
           i.paymentmethod::text, i.notes::text, i.createdat
    FROM   genericpayrollitems i
    INNER  JOIN genericpayrollruns r ON r.genericpayrollrunid = i.genericpayrollrunid
    INNER  JOIN genericstaff s ON s.genericstaffid = i.genericstaffid
    WHERE  i.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid
    ORDER  BY s.lastname, s.firstname;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrollrun_getdetailswithytd_rs3(p_genericpayrollrunid integer, p_farmid text)
 RETURNS TABLE(year integer, ytdgrosspaid numeric, ytddeductions numeric, ytdnetpaid numeric, totalpayrollruns integer, totalstaffpaid integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_year integer;
BEGIN
    SELECT date_part('year', r0.periodend)::int INTO v_year
    FROM   genericpayrollruns r0
    WHERE  r0.genericpayrollrunid = p_genericpayrollrunid AND r0.farmid = p_farmid
    LIMIT  1;

    RETURN QUERY
    SELECT v_year,
           COALESCE(SUM(r.totalgrosspay), 0),
           COALESCE(SUM(r.totaldeductions), 0),
           COALESCE(SUM(r.totalnetpay), 0),
           COUNT(*)::int,
           COALESCE((
               SELECT COUNT(DISTINCT i2.genericstaffid)
               FROM   genericpayrollitems i2
               INNER  JOIN genericpayrollruns r2 ON r2.genericpayrollrunid = i2.genericpayrollrunid
               WHERE  r2.farmid = p_farmid AND r2.status = 'Paid' AND r2.isdeleted = FALSE
                  AND date_part('year', r2.periodend)::int = v_year
           ), 0)::int
    FROM   genericpayrollruns r
    WHERE  r.farmid = p_farmid AND r.status = 'Paid' AND r.isdeleted = FALSE
       AND date_part('year', r.periodend)::int = v_year;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrollrun_getdetailswithytd_rs4(p_genericpayrollrunid integer, p_farmid text)
 RETURNS TABLE(genericstaffid integer, staffname text, staffrole text, ytdbasic numeric, ytddaily numeric, ytdcommission numeric, ytdbonus numeric, ytddeductions numeric, ytdgross numeric, ytdnet numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_year integer;
BEGIN
    SELECT date_part('year', r0.periodend)::int INTO v_year
    FROM   genericpayrollruns r0
    WHERE  r0.genericpayrollrunid = p_genericpayrollrunid AND r0.farmid = p_farmid
    LIMIT  1;

    RETURN QUERY
    SELECT i.genericstaffid,
           MAX(s.firstname || ' ' || s.lastname)::text,
           MAX(s.role)::text,
           SUM(i.basicpay), SUM(i.dailywage), SUM(i.commission), SUM(i.bonus), SUM(i.deductions),
           SUM(i.basicpay + i.dailywage + i.commission + i.bonus),
           SUM(i.netpay)
    FROM   genericpayrollitems i
    INNER  JOIN genericpayrollruns r ON r.genericpayrollrunid = i.genericpayrollrunid
    INNER  JOIN genericstaff s ON s.genericstaffid = i.genericstaffid
    WHERE  r.farmid = p_farmid AND r.status = 'Paid' AND r.isdeleted = FALSE
       AND date_part('year', r.periodend)::int = v_year
    GROUP  BY i.genericstaffid
    ORDER  BY MAX(s.firstname || ' ' || s.lastname);
END;
$function$;

-- Generic writes no payroll expense (P&L reads Paid runs), so there is never a
-- linked expense. Same columns as Poultry so the reader is a mechanical port.
CREATE OR REPLACE FUNCTION public.spgenericpayrollrun_getdetailswithytd_rs5(p_genericpayrollrunid integer, p_farmid text)
 RETURNS TABLE(expenseid integer, farmid text, expensedate timestamp without time zone, category text, description text, amount numeric, paymentmethod text, sourcetype text, sourceid integer, createddate timestamp without time zone)
 LANGUAGE sql
AS $function$
    SELECT NULL::integer, NULL::text, NULL::timestamp, NULL::text, NULL::text, NULL::numeric,
           NULL::text, NULL::text, NULL::integer, NULL::timestamp
    WHERE  FALSE;
$function$;

-- ---------------------------------------------------------------------------
-- 6. Lines
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fngenericpayrollitem_recalcdeductions(p_genericpayrollitemid integer)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_runid      integer;
    v_legacy     numeric;
    v_structured numeric;
    v_total      numeric;
BEGIN
    SELECT i.genericpayrollrunid, COALESCE(i.legacydeductions, 0)
    INTO   v_runid, v_legacy
    FROM   genericpayrollitems i
    WHERE  i.genericpayrollitemid = p_genericpayrollitemid
    FOR UPDATE;

    IF v_runid IS NULL THEN
        RAISE EXCEPTION 'Payroll item % not found.', p_genericpayrollitemid;
    END IF;

    SELECT COALESCE(SUM(d.amount), 0)
    INTO   v_structured
    FROM   genericpayrollitemdeductions d
    WHERE  d.genericpayrollitemid = p_genericpayrollitemid
      AND  d.status <> 'Reversed';

    v_total := v_legacy + v_structured;

    -- netpay is GENERATED (gross - deductions).
    UPDATE genericpayrollitems
    SET    deductions = v_total
    WHERE  genericpayrollitemid = p_genericpayrollitemid;

    PERFORM public.fngenericpayrollrun_rolluptotals(v_runid);
    RETURN v_total;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fngenericpayrollrun_rolluptotals(p_genericpayrollrunid integer)
 RETURNS void
 LANGUAGE sql
AS $function$
    UPDATE genericpayrollruns r
    SET    totalgrosspay   = agg.gross,
           totaldeductions = agg.ded,
           totalnetpay     = agg.net,
           updatedat       = (now() at time zone 'utc')
    FROM (
        SELECT COALESCE(SUM(i.basicpay + i.dailywage + i.commission + i.bonus), 0) AS gross,
               COALESCE(SUM(i.deductions), 0) AS ded,
               COALESCE(SUM(i.netpay), 0)     AS net
        FROM   genericpayrollitems i
        WHERE  i.genericpayrollrunid = p_genericpayrollrunid
    ) agg
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrollitem_upsert(p_genericpayrollrunid integer, p_farmid text, p_genericstaffid integer, p_basicpay numeric DEFAULT 0, p_dailywage numeric DEFAULT 0, p_commission numeric DEFAULT 0, p_bonus numeric DEFAULT 0, p_deductions numeric DEFAULT 0, p_paymentmethod text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_otherdeductions numeric DEFAULT NULL::numeric, p_employeecredit numeric DEFAULT NULL::numeric, p_savedby text DEFAULT NULL::text)
 RETURNS TABLE(genericpayrollitemid integer, genericpayrollrunid integer, genericstaffid integer, basicpay numeric, dailywage numeric, commission numeric, bonus numeric, deductions numeric, netpay numeric, paymentmethod text, notes text, createdat timestamp without time zone)
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
    FROM   genericpayrollruns r
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE;

    IF v_runstatus IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found for this business.';
    END IF;
    IF v_runstatus NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION 'This payroll is %. Reopen it before changing its lines.', v_runstatus;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM genericstaff st
                   WHERE st.genericstaffid = p_genericstaffid AND st.farmid = p_farmid
                     AND COALESCE(st.isdeleted, FALSE) = FALSE) THEN
        RAISE EXCEPTION 'Staff % not found on this business.', p_genericstaffid;
    END IF;

    IF (COALESCE(p_basicpay, 0) < 0 OR COALESCE(p_dailywage, 0) < 0 OR COALESCE(p_commission, 0) < 0
        OR COALESCE(p_bonus, 0) < 0 OR COALESCE(p_deductions, 0) < 0
        OR COALESCE(p_otherdeductions, 0) < 0 OR COALESCE(p_employeecredit, 0) < 0) THEN
        RAISE EXCEPTION 'Pay and deductions cannot be negative.';
    END IF;

    SELECT i.genericpayrollitemid INTO v_itemid
    FROM   genericpayrollitems i
    WHERE  i.genericpayrollrunid = p_genericpayrollrunid AND i.genericstaffid = p_genericstaffid;

    IF v_itemid IS NULL THEN
        INSERT INTO genericpayrollitems (
            genericpayrollrunid, genericstaffid, basicpay, dailywage, commission, bonus,
            deductions, legacydeductions, paymentmethod, notes)
        VALUES (
            p_genericpayrollrunid, p_genericstaffid, COALESCE(p_basicpay, 0), COALESCE(p_dailywage, 0),
            COALESCE(p_commission, 0), COALESCE(p_bonus, 0), 0, 0, p_paymentmethod, p_notes)
        RETURNING genericpayrollitems.genericpayrollitemid INTO v_itemid;
    ELSE
        UPDATE genericpayrollitems i
        SET    basicpay = COALESCE(p_basicpay, 0), dailywage = COALESCE(p_dailywage, 0),
               commission = COALESCE(p_commission, 0), bonus = COALESCE(p_bonus, 0),
               paymentmethod = p_paymentmethod, notes = p_notes
        WHERE  i.genericpayrollitemid = v_itemid;
    END IF;

    -- Keep as employee credit: replace the line's DRAFT credit rows.
    IF p_employeecredit IS NOT NULL THEN
        DELETE FROM genericpayrollitemdeductions d
        WHERE  d.genericpayrollitemid = v_itemid
          AND  d.deductiontype = 'EmployeeCredit'
          AND  d.status = 'Draft';
        IF p_employeecredit > 0 THEN
            INSERT INTO genericpayrollitemdeductions (
                farmid, genericpayrollrunid, genericpayrollitemid, genericstaffid,
                deductiontype, amount, genericemployeeloanid, description, status, createdby)
            VALUES (
                p_farmid, p_genericpayrollrunid, v_itemid, p_genericstaffid,
                'EmployeeCredit', p_employeecredit, NULL, 'Kept from wages', 'Draft', p_savedby);
        END IF;
    END IF;

    -- Other deductions: given exactly, or derived from an old-style total.
    IF p_otherdeductions IS NOT NULL THEN
        v_legacy := p_otherdeductions;
    ELSE
        SELECT COALESCE(SUM(d.amount), 0) INTO v_structured
        FROM   genericpayrollitemdeductions d
        WHERE  d.genericpayrollitemid = v_itemid AND d.status <> 'Reversed';
        v_legacy := GREATEST(COALESCE(p_deductions, 0) - v_structured, 0);
    END IF;

    UPDATE genericpayrollitems i SET legacydeductions = v_legacy WHERE i.genericpayrollitemid = v_itemid;
    PERFORM public.fngenericpayrollitem_recalcdeductions(v_itemid);

    SELECT i.netpay INTO v_net FROM genericpayrollitems i WHERE i.genericpayrollitemid = v_itemid;
    IF v_net < 0 THEN
        RAISE EXCEPTION 'Deductions (%) are more than this line''s pay. Net pay cannot be negative.',
            (SELECT i.deductions FROM genericpayrollitems i WHERE i.genericpayrollitemid = v_itemid);
    END IF;

    RETURN QUERY
    SELECT i.genericpayrollitemid, i.genericpayrollrunid, i.genericstaffid,
           i.basicpay, i.dailywage, i.commission, i.bonus, i.deductions, i.netpay::numeric,
           i.paymentmethod::text, i.notes::text, i.createdat
    FROM   genericpayrollitems i
    WHERE  i.genericpayrollitemid = v_itemid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrollitem_delete(p_genericpayrollitemid integer, p_farmid text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_runid integer;
    v_runstatus text;
BEGIN
    SELECT i.genericpayrollrunid, r.status INTO v_runid, v_runstatus
    FROM   genericpayrollitems i
    INNER  JOIN genericpayrollruns r ON r.genericpayrollrunid = i.genericpayrollrunid
    WHERE  i.genericpayrollitemid = p_genericpayrollitemid AND r.farmid = p_farmid
    LIMIT 1;

    IF v_runid IS NULL THEN
        RAISE EXCEPTION 'Payroll item not found on this business.';
    END IF;
    IF v_runstatus NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION 'Payroll run is %; only Draft or Reopened can be modified.', v_runstatus;
    END IF;

    -- Its deductions go with it (ON DELETE CASCADE; the trigger refuses posted ones).
    DELETE FROM genericpayrollitems i WHERE i.genericpayrollitemid = p_genericpayrollitemid;
    PERFORM public.fngenericpayrollrun_rolluptotals(v_runid);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 7. Deductions
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericpayrollitemdeduction_getall(p_farmid text, p_genericpayrollitemid integer)
 RETURNS TABLE(genericpayrollitemdeductionid integer, genericpayrollitemid integer, genericstaffid integer, deductiontype text, amount numeric, genericemployeeloanid integer, loannumber text, loantype text, loanoutstanding numeric, genericemployeeloanrepaymentid integer, description text, reference text, status text, islegacy boolean, createdby text, createdat timestamp without time zone)
 LANGUAGE sql
AS $function$
    SELECT d.genericpayrollitemdeductionid, d.genericpayrollitemid, d.genericstaffid,
           d.deductiontype, d.amount,
           d.genericemployeeloanid, l.loannumber, l.loantype, l.outstandingbalance,
           d.genericemployeeloanrepaymentid,
           d.description, d.reference, d.status,
           FALSE AS islegacy,
           d.createdby, d.createdat
    FROM   genericpayrollitemdeductions d
    LEFT   JOIN genericemployeeloans l
           ON l.genericemployeeloanid = d.genericemployeeloanid
    WHERE  d.farmid = p_farmid
      AND  d.genericpayrollitemid = p_genericpayrollitemid

    UNION ALL

    -- The remainder. Not a record: a subtraction.
    SELECT NULL::integer, i.genericpayrollitemid, i.genericstaffid,
           'OtherDeduction'::text,
           (i.deductions - COALESCE((SELECT SUM(d2.amount)
                                       FROM genericpayrollitemdeductions d2
                                      WHERE d2.genericpayrollitemid = i.genericpayrollitemid
                                        AND d2.status <> 'Reversed'), 0))::numeric(14,2),
           NULL::integer, NULL::text, NULL::text, NULL::numeric,
           NULL::integer,
           'Entered before deductions were itemised'::text, NULL::text,
           'Posted'::text,
           TRUE AS islegacy,
           NULL::text, NULL::timestamp
    FROM   genericpayrollitems i
    JOIN   genericpayrollruns r ON r.genericpayrollrunid = i.genericpayrollrunid
    WHERE  r.farmid = p_farmid
      AND  i.genericpayrollitemid = p_genericpayrollitemid
      AND  (i.deductions - COALESCE((SELECT SUM(d2.amount)
                                       FROM genericpayrollitemdeductions d2
                                      WHERE d2.genericpayrollitemid = i.genericpayrollitemid
                                        AND d2.status <> 'Reversed'), 0)) > 0

    ORDER  BY islegacy, deductiontype, genericpayrollitemdeductionid;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrollitemdeduction_getforrun(p_farmid text, p_genericpayrollrunid integer)
 RETURNS TABLE(genericpayrollitemid integer, genericstaffid integer, staffname text, deductions numeric, legacydeductions numeric, structuredtotal numeric, structuredcount integer, loanrepaymenttotal numeric, activeloancount integer, activeloanoutstanding numeric, suggesteddeduction numeric)
 LANGUAGE sql
AS $function$
    SELECT i.genericpayrollitemid, i.genericstaffid,
           btrim(s.firstname || ' ' || s.lastname),
           i.deductions, i.legacydeductions,
           COALESCE(d.total, 0)::numeric(14,2),
           COALESCE(d.n, 0)::integer,
           COALESCE(d.loantotal, 0)::numeric(14,2),
           COALESCE(a.n, 0)::integer,
           COALESCE(a.outstanding, 0)::numeric(14,2),
           COALESCE(a.suggested, 0)::numeric(14,2)
    FROM   genericpayrollitems i
    JOIN   genericpayrollruns r ON r.genericpayrollrunid = i.genericpayrollrunid
    JOIN   genericstaff s ON s.genericstaffid = i.genericstaffid
    LEFT   JOIN (
        SELECT d0.genericpayrollitemid,
               SUM(d0.amount) AS total,
               COUNT(*) AS n,
               SUM(d0.amount) FILTER (
                   WHERE d0.deductiontype IN ('EmployeeLoanRepayment',
                                              'SalaryAdvanceRepayment')) AS loantotal
        FROM   genericpayrollitemdeductions d0
        WHERE  d0.status <> 'Reversed'
        GROUP  BY d0.genericpayrollitemid
    ) d ON d.genericpayrollitemid = i.genericpayrollitemid
    LEFT   JOIN (
        SELECT l.genericstaffid, l.farmid,
               COUNT(*) AS n,
               SUM(l.outstandingbalance) AS outstanding,
               SUM(LEAST(COALESCE(l.defaultpayrolldeduction, 0),
                         l.outstandingbalance)) AS suggested
        FROM   genericemployeeloans l
        WHERE  l.status = 'Active'
          AND  l.outstandingbalance > 0
          AND  l.repaymentmethod IN ('PayrollDeduction', 'Mixed')
        GROUP  BY l.genericstaffid, l.farmid
    ) a ON a.genericstaffid = i.genericstaffid AND a.farmid = r.farmid
    WHERE  r.farmid = p_farmid
      AND  i.genericpayrollrunid = p_genericpayrollrunid
    ORDER  BY btrim(s.firstname || ' ' || s.lastname);
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrollitemdeduction_save(p_farmid text, p_genericpayrollitemid integer, p_deductiontype text, p_amount numeric, p_genericemployeeloanid integer DEFAULT NULL::integer, p_description text DEFAULT NULL::text, p_reference text DEFAULT NULL::text, p_genericpayrollitemdeductionid integer DEFAULT NULL::integer, p_savedby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id          integer := p_genericpayrollitemdeductionid;
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

    SELECT i.genericpayrollrunid, i.genericstaffid, r.status
    INTO   v_runid, v_staffid, v_runstatus
    FROM   genericpayrollitems i
    JOIN   genericpayrollruns r ON r.genericpayrollrunid = i.genericpayrollrunid
    WHERE  i.genericpayrollitemid = p_genericpayrollitemid
      AND  r.farmid = p_farmid AND r.isdeleted = FALSE;

    IF v_runid IS NULL THEN
        RAISE EXCEPTION 'Payroll line not found on this business.';
    END IF;
    IF v_runstatus NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION
            'This payroll is %. Reopen it before changing deductions.', v_runstatus;
    END IF;

    IF v_type IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment') THEN
        IF p_genericemployeeloanid IS NULL THEN
            RAISE EXCEPTION 'Choose which advance this repayment is against.';
        END IF;

        SELECT l.genericstaffid, l.status, l.outstandingbalance, l.loannumber
        INTO   v_loanstaff, v_loanstatus, v_outstanding, v_number
        FROM   genericemployeeloans l
        WHERE  l.genericemployeeloanid = p_genericemployeeloanid
          AND  l.farmid = p_farmid;

        IF v_loanstaff IS NULL THEN
            RAISE EXCEPTION 'Advance not found on this business.';
        END IF;
        IF v_loanstaff <> v_staffid THEN
            RAISE EXCEPTION 'That advance belongs to a different member of staff.';
        END IF;
        IF v_loanstatus <> 'Active' THEN
            RAISE EXCEPTION 'Advance % is %, so nothing can be deducted against it.',
                COALESCE(v_number, p_genericemployeeloanid::text), v_loanstatus;
        END IF;

        -- What draft payrolls ALREADY plan to take off the same advance counts
        -- against the balance.
        SELECT COALESCE(SUM(d.amount), 0)
        INTO   v_claimed
        FROM   genericpayrollitemdeductions d
        WHERE  d.genericemployeeloanid = p_genericemployeeloanid
          AND  d.status = 'Draft'
          AND  (v_id IS NULL OR d.genericpayrollitemdeductionid <> v_id);

        IF v_amount + v_claimed > v_outstanding THEN
            IF v_claimed > 0 THEN
                RAISE EXCEPTION
                    'Only % is left on advance %, and % of it is already planned in a draft payroll.',
                    v_outstanding, COALESCE(v_number, p_genericemployeeloanid::text), v_claimed;
            ELSE
                RAISE EXCEPTION 'Only % is left on advance %.',
                    v_outstanding, COALESCE(v_number, p_genericemployeeloanid::text);
            END IF;
        END IF;
    ELSIF v_type NOT IN ('OtherDeduction', 'EmployeeCredit') THEN
        RAISE EXCEPTION 'Unknown deduction type %.', v_type;
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO genericpayrollitemdeductions (
            farmid, genericpayrollrunid, genericpayrollitemid, genericstaffid,
            deductiontype, amount, genericemployeeloanid,
            description, reference, status, createdby)
        VALUES (
            p_farmid, v_runid, p_genericpayrollitemid, v_staffid,
            v_type, v_amount,
            CASE WHEN v_type IN ('OtherDeduction', 'EmployeeCredit') THEN NULL ELSE p_genericemployeeloanid END,
            NULLIF(btrim(p_description), ''), NULLIF(btrim(p_reference), ''),
            'Draft', p_savedby)
        RETURNING genericpayrollitemdeductionid INTO v_id;
    ELSE
        UPDATE genericpayrollitemdeductions d
        SET    deductiontype = v_type,
               amount = v_amount,
               genericemployeeloanid =
                   CASE WHEN v_type IN ('OtherDeduction', 'EmployeeCredit') THEN NULL
                        ELSE p_genericemployeeloanid END,
               description = NULLIF(btrim(p_description), ''),
               reference   = NULLIF(btrim(p_reference), ''),
               updatedby   = p_savedby,
               updatedat   = (now() at time zone 'utc')
        WHERE  d.genericpayrollitemdeductionid = v_id
          AND  d.farmid = p_farmid
          AND  d.genericpayrollitemid = p_genericpayrollitemid
          AND  d.status = 'Draft';

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'Deduction % cannot be edited -- it is not a draft on this business.', v_id;
        END IF;
    END IF;

    PERFORM public.fngenericpayrollitem_recalcdeductions(p_genericpayrollitemid);
    IF (SELECT i.netpay FROM genericpayrollitems i WHERE i.genericpayrollitemid = p_genericpayrollitemid) < 0 THEN
        RAISE EXCEPTION 'Deductions are more than this line''s pay. Net pay cannot be negative.';
    END IF;
    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrollitemdeduction_delete(p_farmid text, p_genericpayrollitemdeductionid integer, p_deletedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_itemid  integer;
    v_status  text;
    v_runstat text;
BEGIN
    SELECT d.genericpayrollitemid, d.status, r.status
    INTO   v_itemid, v_status, v_runstat
    FROM   genericpayrollitemdeductions d
    JOIN   genericpayrollruns r ON r.genericpayrollrunid = d.genericpayrollrunid
    WHERE  d.genericpayrollitemdeductionid = p_genericpayrollitemdeductionid
      AND  d.farmid = p_farmid;

    IF v_itemid IS NULL THEN
        RAISE EXCEPTION 'Deduction % not found on this business.', p_genericpayrollitemdeductionid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION
            'This deduction has been posted to an advance. Unapprove the payroll to undo it.';
    END IF;
    IF v_runstat NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION 'This payroll is %. Reopen it before changing deductions.', v_runstat;
    END IF;

    DELETE FROM genericpayrollitemdeductions
    WHERE  genericpayrollitemdeductionid = p_genericpayrollitemdeductionid;

    PERFORM public.fngenericpayrollitem_recalcdeductions(v_itemid);
END;
$function$;

-- ---------------------------------------------------------------------------
-- 8. Run lifecycle
-- ---------------------------------------------------------------------------

-- Advance repayment recorder (from 446-era live def), one fix: a 'Payroll'
-- repayment has no cash account, but the old ELSE branch still looked one up
-- and refused, so no payroll deduction could ever post.
CREATE OR REPLACE FUNCTION public.spgenericemployeeloanrepayment_record(p_farmid text, p_genericemployeeloanid integer, p_amount numeric, p_sourcetype text DEFAULT 'ManualCash'::text, p_genericcashaccountid integer DEFAULT NULL::integer, p_paymentmethod text DEFAULT NULL::text, p_referencenumber text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_genericpayrollrunid integer DEFAULT NULL::integer, p_genericpayrollitemid integer DEFAULT NULL::integer, p_repaymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_principalamount numeric DEFAULT NULL::numeric, p_interestamount numeric DEFAULT NULL::numeric, p_createdby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_outstanding numeric;
    v_total       numeric;
    v_interest_en boolean;
    v_staffid     integer;
    v_staffname   text;
    v_number      text;
    v_source      text;
    v_amount      numeric;
    v_principal   numeric;
    v_interest    numeric;
    v_newout      numeric;
    v_id          integer;
    v_txid        integer;
    v_seq         integer;
    v_date        timestamp;
    v_balance     numeric;
BEGIN
    v_amount := COALESCE(p_amount, 0);
    IF v_amount <= 0 THEN
        RAISE EXCEPTION 'Repayment amount must be positive.';
    END IF;

    v_source := COALESCE(NULLIF(btrim(p_sourcetype), ''), 'ManualCash');
    v_date   := COALESCE(p_repaymentdate, now() at time zone 'utc');

    SELECT l.outstandingbalance, l.totalrepayable, l.interestenabled,
           l.genericstaffid, l.loannumber
    INTO   v_outstanding, v_total, v_interest_en, v_staffid, v_number
    FROM   genericemployeeloans l
    WHERE  l.genericemployeeloanid = p_genericemployeeloanid AND l.farmid = p_farmid
    FOR UPDATE;

    IF v_outstanding IS NULL THEN
        RAISE EXCEPTION 'Advance % not found.', p_genericemployeeloanid;
    END IF;
    IF v_outstanding <= 0 THEN
        RAISE EXCEPTION 'This advance is fully repaid.';
    END IF;
    IF v_amount > v_outstanding THEN
        RAISE EXCEPTION 'Repayment of % exceeds the outstanding balance of %.', v_amount, v_outstanding;
    END IF;

    v_interest  := CASE WHEN v_interest_en THEN COALESCE(p_interestamount, 0) ELSE 0 END;
    v_principal := COALESCE(p_principalamount, v_amount - v_interest);
    IF v_principal + v_interest <> v_amount THEN
        RAISE EXCEPTION 'Principal (%) + interest (%) does not equal the repayment amount (%).', v_principal, v_interest, v_amount;
    END IF;

    IF v_source <> 'Payroll' AND p_genericcashaccountid IS NULL THEN
        RAISE EXCEPTION 'A % repayment must say which cash account received it.', v_source;
    ELSIF v_source = 'Payroll' AND p_genericcashaccountid IS NOT NULL THEN
        -- 451: a payroll repayment moves no cash (the wage paid out is net).
        RAISE EXCEPTION 'A payroll repayment does not take a cash account.';
    ELSIF v_source <> 'Payroll' THEN
        PERFORM 1 FROM genericcashaccounts a
        WHERE  a.genericcashaccountid = p_genericcashaccountid AND a.farmid = p_farmid;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Cash account does not exist or does not belong to this farm.';
        END IF;
    END IF;

    SELECT btrim(s.firstname || ' ' || s.lastname) INTO v_staffname
    FROM   genericstaff s WHERE s.genericstaffid = v_staffid;

    v_newout := v_outstanding - v_amount;

    INSERT INTO genericemployeeloanrepayments (
        farmid, genericemployeeloanid, genericstaffid, repaymentdate,
        amount, principalamount, interestamount, sourcetype,
        genericpayrollrunid, genericpayrollitemid,
        genericcashaccountid, paymentmethod, referencenumber, description, notes,
        balancebefore, balanceafter, status, createdby)
    VALUES (
        p_farmid, p_genericemployeeloanid, v_staffid, v_date,
        v_amount, v_principal, v_interest, v_source,
        p_genericpayrollrunid, p_genericpayrollitemid,
        p_genericcashaccountid, NULLIF(btrim(p_paymentmethod), ''),
        NULLIF(btrim(p_referencenumber), ''), NULLIF(btrim(p_description), ''),
        NULLIF(btrim(p_notes), ''),
        v_outstanding, v_newout, 'Posted', p_createdby)
    RETURNING genericemployeeloanrepaymentid INTO v_id;

    PERFORM pg_advisory_xact_lock(hashtext('genericemployeeloanrepayment:' || p_farmid));
    SELECT COUNT(*) INTO v_seq
    FROM   genericemployeeloanrepayments WHERE farmid = p_farmid;
    UPDATE genericemployeeloanrepayments
    SET    repaymentnumber = 'ELR-' || lpad(v_seq::text, 4, '0')
    WHERE  genericemployeeloanrepaymentid = v_id;

    -- ---- cash, only when cash actually moved ----------------------------
    IF v_source <> 'Payroll' THEN
        SELECT a.currentbalance INTO v_balance
        FROM   genericcashaccounts a WHERE a.genericcashaccountid = p_genericcashaccountid;

        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, balanceaftertransaction,
            description, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, p_genericcashaccountid, v_date, 'EmployeeLoanRepayment',
            'EmployeeLoanRepayment', v_id, v_amount,
            COALESCE(v_balance, 0) + v_amount,
            'Advance repayment from ' || COALESCE(v_staffname, 'staff') ||
                ' - ' || COALESCE(v_number, p_genericemployeeloanid::text),
            p_createdby, p_createdby, (now() at time zone 'utc'))
        RETURNING genericcashtransactionid INTO v_txid;

        UPDATE genericcashaccounts a
        SET    currentbalance = a.currentbalance + v_amount,
               updatedat = (now() at time zone 'utc')
        WHERE  a.genericcashaccountid = p_genericcashaccountid;

        UPDATE genericemployeeloanrepayments
        SET    genericcashtransactionid = v_txid
        WHERE  genericemployeeloanrepaymentid = v_id;
    END IF;

    -- ---- the receivable -------------------------------------------------
    UPDATE genericemployeeloans l
    SET    totalprincipalrepaid = l.totalprincipalrepaid + v_principal,
           totalinterestrepaid  = l.totalinterestrepaid + v_interest,
           outstandingbalance   = v_newout,
           status = CASE WHEN v_newout <= 0 THEN 'Paid' ELSE 'Active' END,
           paidat = CASE WHEN v_newout <= 0 THEN v_date ELSE NULL END,
           updatedat = (now() at time zone 'utc')
    WHERE  l.genericemployeeloanid = p_genericemployeeloanid AND l.farmid = p_farmid;

    RETURN v_id;
END;
$function$;

-- Insert: the existing function is already the Poultry shape (checks the cash
-- account belongs to the business). Kept as is.

CREATE OR REPLACE FUNCTION public.spgenericpayrollrun_approve(p_genericpayrollrunid integer, p_farmid text, p_approvedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status      text;
    v_periodstart date;
    v_periodend   date;
    v_paydate     date;
    v_expdate     date;
    v_desc        text;
    v_d           record;
    v_repayid     integer;
    v_ctxloan     text := NULL;
    v_ctxstaff    text := NULL;
    v_c           record;
    v_creditid    integer;
BEGIN
    SELECT r.status, r.periodstart, r.periodend, r.paydate
    INTO   v_status, v_periodstart, v_periodend, v_paydate
    FROM   genericpayrollruns r
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE
    FOR UPDATE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found for this business.';
    END IF;
    IF v_status NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION 'Payroll run is %; only Draft or Reopened can be approved.', v_status;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM genericpayrollitems i WHERE i.genericpayrollrunid = p_genericpayrollrunid) THEN
        RAISE EXCEPTION 'Payroll run has no lines; add staff before approving.';
    END IF;

    v_expdate := COALESCE(v_paydate, ((now() at time zone 'utc'))::date);
    v_desc := concat('Payroll ', to_char(v_periodstart, 'YYYY-MM-DD'), ' to ', to_char(v_periodend, 'YYYY-MM-DD'));

    -- ---- planned advance deductions become real repayments (no cash moves:
    -- the wage paid out is already net). The repayment function re-checks the
    -- business, the advance's status and its outstanding balance.
    BEGIN
        FOR v_d IN
            SELECT d.genericpayrollitemdeductionid AS dedid,
                   d.genericpayrollitemid          AS itemid,
                   d.genericemployeeloanid         AS loanid,
                   d.genericstaffid                AS staffid,
                   d.amount                        AS amount,
                   l.loannumber                    AS loannumber,
                   l.genericstaffid                AS loanstaffid,
                   btrim(s.firstname || ' ' || s.lastname) AS staffname
            FROM   genericpayrollitemdeductions d
            JOIN   genericemployeeloans l ON l.genericemployeeloanid = d.genericemployeeloanid
            JOIN   genericstaff s ON s.genericstaffid = d.genericstaffid
            WHERE  d.genericpayrollrunid = p_genericpayrollrunid
              AND  d.farmid = p_farmid
              AND  d.status = 'Draft'
              AND  d.deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment')
            ORDER  BY d.genericpayrollitemdeductionid
        LOOP
            v_ctxloan  := COALESCE(v_d.loannumber, v_d.loanid::text);
            v_ctxstaff := v_d.staffname;

            IF v_d.loanstaffid <> v_d.staffid THEN
                RAISE EXCEPTION 'That advance belongs to a different member of staff.';
            END IF;

            v_repayid := public.spgenericemployeeloanrepayment_record(
                p_farmid                => p_farmid,
                p_genericemployeeloanid => v_d.loanid,
                p_amount                => v_d.amount,
                p_sourcetype            => 'Payroll',
                p_genericcashaccountid  => NULL,
                p_description           => v_desc,
                p_genericpayrollrunid   => p_genericpayrollrunid,
                p_genericpayrollitemid  => v_d.itemid,
                p_repaymentdate         => v_expdate::timestamp,
                p_principalamount       => v_d.amount,
                p_interestamount        => 0,
                p_createdby             => p_approvedby);

            UPDATE genericpayrollitemdeductions
            SET    status = 'Posted',
                   genericemployeeloanrepaymentid = v_repayid,
                   updatedby = p_approvedby,
                   updatedat = (now() at time zone 'utc')
            WHERE  genericpayrollitemdeductionid = v_d.dedid;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        IF v_ctxloan IS NULL THEN
            RAISE;
        END IF;
        RAISE EXCEPTION
            'Payroll was not approved. The deduction against advance % for % could not be posted: %',
            v_ctxloan, COALESCE(v_ctxstaff, 'this member of staff'), SQLERRM;
    END;

    -- ---- wages kept as employee credit: money the business now OWES the worker.
    -- No expense row: Generic P&L counts the run's gross pay once it is Paid.
    FOR v_c IN
        SELECT d.genericpayrollitemdeductionid AS dedid,
               d.genericpayrollitemid          AS itemid,
               d.genericstaffid                AS staffid,
               d.amount                        AS amount
        FROM   genericpayrollitemdeductions d
        WHERE  d.genericpayrollrunid = p_genericpayrollrunid
          AND  d.farmid = p_farmid
          AND  d.status = 'Draft'
          AND  d.deductiontype = 'EmployeeCredit'
        ORDER  BY d.genericpayrollitemdeductionid
    LOOP
        INSERT INTO genericemployeecredits
            (farmid, genericstaffid, entrytype, amount, entrydate,
             genericpayrollrunid, genericpayrollitemid, description, createdby)
        VALUES
            (p_farmid, v_c.staffid, 'PayrollSaving', v_c.amount, v_expdate,
             p_genericpayrollrunid, v_c.itemid, v_desc || ' - kept as employee credit', p_approvedby)
        RETURNING genericemployeecreditid INTO v_creditid;

        UPDATE genericpayrollitemdeductions
        SET    status = 'Posted',
               genericemployeecreditid = v_creditid,
               updatedby = p_approvedby,
               updatedat = (now() at time zone 'utc')
        WHERE  genericpayrollitemdeductionid = v_c.dedid;
    END LOOP;

    -- Other deductions post nothing but should not stay 'Draft' on an approved run.
    UPDATE genericpayrollitemdeductions
    SET    status = 'Posted',
           updatedby = p_approvedby,
           updatedat = (now() at time zone 'utc')
    WHERE  genericpayrollrunid = p_genericpayrollrunid
      AND  farmid = p_farmid
      AND  status = 'Draft';

    IF v_status = 'Reopened' THEN
        UPDATE genericpayrollruns r
        SET    status = 'Approved', reapprovedby = p_approvedby, reapprovedat = (now() at time zone 'utc'),
               updatedat = (now() at time zone 'utc')
        WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid;
    ELSE
        UPDATE genericpayrollruns r
        SET    status = 'Approved', approvedby = p_approvedby, approvedat = (now() at time zone 'utc'),
               updatedat = (now() at time zone 'utc')
        WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid;
    END IF;
END;
$function$;

-- Shared by reopen and cancel: give back every advance repayment and kept
-- credit this run posted, and make its deductions editable (Draft) again.
CREATE OR REPLACE FUNCTION public.fngenericpayrollrun_reversepostings(p_genericpayrollrunid integer, p_farmid text, p_by text, p_reason text, p_verb text DEFAULT 'reopened')
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_r        record;
    v_c        record;
    v_ctxloan  text := NULL;
    v_ctxstaff text := NULL;
BEGIN
    BEGIN
        FOR v_r IN
            SELECT r.genericemployeeloanrepaymentid AS repayid,
                   COALESCE(l.loannumber, l.genericemployeeloanid::text) AS loannumber,
                   btrim(s.firstname || ' ' || s.lastname) AS staffname
            FROM   genericemployeeloanrepayments r
            JOIN   genericemployeeloans l ON l.genericemployeeloanid = r.genericemployeeloanid
            JOIN   genericstaff s ON s.genericstaffid = r.genericstaffid
            WHERE  r.farmid = p_farmid
              AND  r.genericpayrollrunid = p_genericpayrollrunid
              AND  r.sourcetype = 'Payroll'
              AND  r.status = 'Posted'
            ORDER  BY r.genericemployeeloanrepaymentid
        LOOP
            v_ctxloan  := v_r.loannumber;
            v_ctxstaff := v_r.staffname;

            PERFORM public.spgenericemployeeloanrepayment_reverse(
                p_farmid                         => p_farmid,
                p_genericemployeeloanrepaymentid => v_r.repayid,
                p_reversedby                     => p_by,
                p_reason                         => p_reason,
                p_allowpayroll                   => TRUE);

            UPDATE genericpayrollitemdeductions
            SET    status = 'Draft',
                   genericemployeeloanrepaymentid = NULL,
                   updatedby = p_by,
                   updatedat = (now() at time zone 'utc')
            WHERE  genericemployeeloanrepaymentid = v_r.repayid
              AND  farmid = p_farmid;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        IF v_ctxloan IS NULL THEN
            RAISE;
        END IF;
        RAISE EXCEPTION
            'Payroll was not %. The repayment against advance % for % could not be reversed: %',
            p_verb, v_ctxloan, COALESCE(v_ctxstaff, 'this member of staff'), SQLERRM;
    END;

    -- Refused (by the reverse core) if the kept money has already been paid out.
    FOR v_c IN
        SELECT c.genericemployeecreditid AS creditid,
               btrim(s.firstname || ' ' || s.lastname) AS staffname
        FROM   genericemployeecredits c
        JOIN   genericstaff s ON s.genericstaffid = c.genericstaffid
        WHERE  c.farmid = p_farmid
          AND  c.genericpayrollrunid = p_genericpayrollrunid
          AND  c.entrytype = 'PayrollSaving'
          AND  c.status = 'Posted'
        ORDER  BY c.genericemployeecreditid
    LOOP
        BEGIN
            PERFORM public.fngenericemployeecredit_reverserow(
                p_farmid, v_c.creditid, p_reason, p_by);
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Payroll was not %. The wages kept for % could not be taken back: %',
                p_verb, v_c.staffname, SQLERRM;
        END;
        UPDATE genericpayrollitemdeductions
        SET    status = 'Draft',
               genericemployeecreditid = NULL,
               updatedby = p_by,
               updatedat = (now() at time zone 'utc')
        WHERE  genericemployeecreditid = v_c.creditid
          AND  farmid = p_farmid;
    END LOOP;

    -- Other deductions posted nothing; make them editable again too.
    UPDATE genericpayrollitemdeductions
    SET    status = 'Draft',
           updatedby = p_by,
           updatedat = (now() at time zone 'utc')
    WHERE  genericpayrollrunid = p_genericpayrollrunid
      AND  farmid = p_farmid
      AND  status = 'Posted'
      AND  genericemployeeloanrepaymentid IS NULL
      AND  genericemployeecreditid IS NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrollrun_unapprove(p_genericpayrollrunid integer, p_farmid text, p_reopenedby text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_acct   integer;
    v_paid   numeric;
    v_reason text;
    v_t      record;
BEGIN
    SELECT r.status, r.genericcashaccountid INTO v_status, v_acct
    FROM   genericpayrollruns r
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE
    FOR UPDATE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found for this business.';
    END IF;
    IF v_status NOT IN ('Approved', 'Paid') THEN
        RAISE EXCEPTION 'Payroll run is %; only Approved or Paid can be reopened.', v_status;
    END IF;
    IF NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Say why the payroll is being reopened.';
    END IF;

    v_reason := 'Payroll reopened: ' || btrim(p_reason);

    PERFORM public.fngenericpayrollrun_reversepostings(
        p_genericpayrollrunid, p_farmid, p_reopenedby, v_reason, 'reopened');

    -- From Paid: put the net pay back where it was paid from. Every account
    -- this run's 'Payroll' cash rows touched is brought back to zero net, so
    -- an earlier reopen/repay cycle is handled too.
    IF v_status = 'Paid' THEN
        FOR v_t IN
            SELECT ct.genericcashaccountid AS acct, SUM(ct.amount) AS net
            FROM   genericcashtransactions ct
            WHERE  ct.farmid = p_farmid AND ct.sourcetype = 'Payroll'
              AND  ct.sourceid = p_genericpayrollrunid
            GROUP  BY ct.genericcashaccountid
            HAVING SUM(ct.amount) <> 0
        LOOP
            PERFORM public.fngenericcash_move(
                p_farmid, v_t.acct, -v_t.net, (now() at time zone 'utc'),
                'Payroll', p_genericpayrollrunid,
                'Payroll reopened - net pay returned', p_reopenedby);
        END LOOP;
    END IF;

    UPDATE genericpayrollruns r
    SET    status = 'Reopened', reopenedby = p_reopenedby, reopenedat = (now() at time zone 'utc'),
           reopenreason = left(btrim(p_reason), 500), paidby = NULL, paidat = NULL,
           updatedat = (now() at time zone 'utc')
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrollrun_cancel(p_genericpayrollrunid integer, p_farmid text, p_cancelledby text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
BEGIN
    SELECT r.status INTO v_status
    FROM   genericpayrollruns r
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found for this business.';
    END IF;
    IF v_status = 'Paid' THEN
        RAISE EXCEPTION 'This payroll has been paid. Reopen it first (that returns the money), then cancel or delete it.';
    END IF;
    IF v_status NOT IN ('Draft', 'Approved', 'Reopened') THEN
        RAISE EXCEPTION 'Payroll run is %; only Draft, Approved or Reopened can be cancelled.', v_status;
    END IF;

    -- An Approved run has posted repayments / credits: take them back first.
    IF v_status = 'Approved' THEN
        PERFORM public.fngenericpayrollrun_reversepostings(
            p_genericpayrollrunid, p_farmid, p_cancelledby,
            'Payroll cancelled' || COALESCE(': ' || NULLIF(btrim(p_reason), ''), ''), 'cancelled');
    END IF;

    UPDATE genericpayrollruns r
    SET    status = 'Cancelled',
           notes  = left(btrim(COALESCE(r.notes, '') ||
                          CASE WHEN NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN ''
                               ELSE chr(10) || 'Cancelled: ' || btrim(p_reason) END), 1000),
           updatedat = (now() at time zone 'utc')
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrollrun_delete(p_genericpayrollrunid integer, p_farmid text, p_deletedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
BEGIN
    SELECT r.status INTO v_status
    FROM   genericpayrollruns r
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found for this business.';
    END IF;
    IF v_status NOT IN ('Draft', 'Reopened', 'Cancelled') THEN
        RAISE EXCEPTION 'Payroll run is %; approve/paid runs must be reopened before deletion.', v_status;
    END IF;

    -- Belt and braces: nothing may still be posted (the trigger also refuses).
    IF EXISTS (SELECT 1 FROM genericemployeeloanrepayments r
               WHERE r.farmid = p_farmid AND r.genericpayrollrunid = p_genericpayrollrunid
                 AND r.sourcetype = 'Payroll' AND r.status = 'Posted')
       OR EXISTS (SELECT 1 FROM genericemployeecredits c
               WHERE c.farmid = p_farmid AND c.genericpayrollrunid = p_genericpayrollrunid
                 AND c.entrytype = 'PayrollSaving' AND c.status = 'Posted') THEN
        RAISE EXCEPTION 'This payroll still has posted advance repayments or kept credit. Reopen it first.';
    END IF;

    DELETE FROM genericpayrollitemdeductions d
    WHERE  d.genericpayrollrunid = p_genericpayrollrunid AND d.farmid = p_farmid;

    UPDATE genericpayrollruns r
    SET    isdeleted = TRUE,
           notes = left(btrim(COALESCE(r.notes, '') || chr(10) || 'Deleted' ||
                              COALESCE(' by ' || NULLIF(btrim(p_deletedby), ''), '')), 1000),
           updatedat = (now() at time zone 'utc')
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 9. Templates
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericpayrolltemplate_getall(p_farmid text, p_includeinactive boolean DEFAULT false)
 RETURNS TABLE(genericpayrolltemplateid integer, name text, frequency text, genericcashaccountid integer, cashaccountname text, notes text, isactive boolean, linecount integer, staffinactivecount integer, totalgross numeric, totaldeductions numeric, totalnet numeric, runcount integer, lastperiodstart date, lastperiodend date, createdby text, createdat timestamp without time zone, updatedby text, updatedat timestamp without time zone)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT t.genericpayrolltemplateid, t.name, t.frequency, t.genericcashaccountid,
           a.accountname::text, t.notes, t.isactive,
           COALESCE(l.cnt, 0)::int, COALESCE(l.inactive, 0)::int,
           COALESCE(l.gross, 0)::numeric(14,2), COALESCE(l.ded, 0)::numeric(14,2),
           (COALESCE(l.gross, 0) - COALESCE(l.ded, 0))::numeric(14,2),
           COALESCE(r.cnt, 0)::int, r.laststart, r.lastend,
           t.createdby, t.createdat, t.updatedby, t.updatedat
    FROM   genericpayrolltemplates t
    LEFT   JOIN genericcashaccounts a ON a.genericcashaccountid = t.genericcashaccountid
    LEFT   JOIN LATERAL (
               SELECT count(*) AS cnt,
                      count(*) FILTER (WHERE NOT COALESCE(st.isactive, false) OR COALESCE(st.isdeleted, false)) AS inactive,
                      SUM(tl.basicpay + tl.dailywage + tl.commission + tl.bonus) AS gross,
                      SUM(tl.deductions) AS ded
               FROM   genericpayrolltemplatelines tl
               LEFT   JOIN genericstaff st ON st.genericstaffid = tl.genericstaffid
               WHERE  tl.genericpayrolltemplateid = t.genericpayrolltemplateid) l ON TRUE
    LEFT   JOIN LATERAL (
               SELECT count(*) AS cnt, max(pr.periodstart)::date AS laststart, max(pr.periodend)::date AS lastend
               FROM   genericpayrollruns pr
               WHERE  pr.genericpayrolltemplateid = t.genericpayrolltemplateid
                 AND  pr.farmid = p_farmid AND NOT pr.isdeleted AND pr.status <> 'Cancelled') r ON TRUE
    WHERE  t.farmid = p_farmid AND (p_includeinactive OR t.isactive)
    ORDER  BY t.isactive DESC, lower(t.name);
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrolltemplate_getlines(p_farmid text, p_templateid integer)
 RETURNS TABLE(genericpayrolltemplatelineid integer, genericpayrolltemplateid integer, genericstaffid integer, staffname text, staffrole text, staffisactive boolean, basicpay numeric, dailywage numeric, commission numeric, bonus numeric, deductions numeric, netpay numeric, paymentmethod text, notes text, sortorder integer)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT tl.genericpayrolltemplatelineid, tl.genericpayrolltemplateid, tl.genericstaffid,
           btrim(COALESCE(st.firstname, '') || ' ' || COALESCE(st.lastname, ''))::text,
           st.role::text,
           (COALESCE(st.isactive, false) AND NOT COALESCE(st.isdeleted, false)),
           tl.basicpay, tl.dailywage, tl.commission, tl.bonus, tl.deductions,
           (tl.basicpay + tl.dailywage + tl.commission + tl.bonus - tl.deductions)::numeric(14,2),
           tl.paymentmethod, tl.notes, tl.sortorder
    FROM   genericpayrolltemplatelines tl
    JOIN   genericpayrolltemplates t ON t.genericpayrolltemplateid = tl.genericpayrolltemplateid
    LEFT   JOIN genericstaff st ON st.genericstaffid = tl.genericstaffid
    WHERE  t.farmid = p_farmid AND t.genericpayrolltemplateid = p_templateid
    ORDER  BY tl.sortorder, lower(COALESCE(st.firstname, '')), tl.genericpayrolltemplatelineid;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrolltemplate_save(p_farmid text, p_templateid integer, p_name text, p_frequency text, p_genericcashaccountid integer, p_notes text, p_lines jsonb, p_by text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id   integer;
    v_name text := btrim(COALESCE(p_name, ''));
    l      record;
    v_i    integer := 0;
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Give the template a name.';
    END IF;
    IF COALESCE(p_frequency, '') NOT IN ('Monthly', 'Fortnightly', 'Weekly') THEN
        RAISE EXCEPTION 'Pay frequency must be Monthly, Fortnightly or Weekly.';
    END IF;
    IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
        RAISE EXCEPTION 'Add at least one staff member to the template.';
    END IF;
    IF p_genericcashaccountid IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM genericcashaccounts a WHERE a.genericcashaccountid = p_genericcashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account not found for this business.';
    END IF;
    IF EXISTS (SELECT 1 FROM genericpayrolltemplates t
               WHERE lower(t.farmid) = lower(p_farmid) AND lower(btrim(t.name)) = lower(v_name)
                 AND t.genericpayrolltemplateid IS DISTINCT FROM p_templateid) THEN
        RAISE EXCEPTION 'A payroll template called "%" already exists.', v_name;
    END IF;

    IF p_templateid IS NULL THEN
        INSERT INTO genericpayrolltemplates (farmid, name, frequency, genericcashaccountid, notes, createdby)
        VALUES (p_farmid, v_name, p_frequency, p_genericcashaccountid, NULLIF(btrim(COALESCE(p_notes, '')), ''), p_by)
        RETURNING genericpayrolltemplateid INTO v_id;
    ELSE
        UPDATE genericpayrolltemplates t
        SET    name = v_name, frequency = p_frequency, genericcashaccountid = p_genericcashaccountid,
               notes = NULLIF(btrim(COALESCE(p_notes, '')), ''), updatedby = p_by,
               updatedat = (now() AT TIME ZONE 'utc')
        WHERE  t.genericpayrolltemplateid = p_templateid AND t.farmid = p_farmid
        RETURNING t.genericpayrolltemplateid INTO v_id;
        IF v_id IS NULL THEN
            RAISE EXCEPTION 'Payroll template not found for this business.';
        END IF;
        DELETE FROM genericpayrolltemplatelines tl WHERE tl.genericpayrolltemplateid = v_id;
    END IF;

    FOR l IN SELECT (x->>'genericStaffId')::int                 AS staffid,
                    COALESCE((x->>'basicPay')::numeric, 0)     AS basicpay,
                    COALESCE((x->>'dailyWage')::numeric, 0)    AS dailywage,
                    COALESCE((x->>'commission')::numeric, 0)   AS commission,
                    COALESCE((x->>'bonus')::numeric, 0)        AS bonus,
                    COALESCE((x->>'deductions')::numeric, 0)   AS deductions,
                    NULLIF(btrim(COALESCE(x->>'paymentMethod', '')), '') AS paymentmethod,
                    NULLIF(btrim(COALESCE(x->>'notes', '')), '')         AS notes
             FROM   jsonb_array_elements(p_lines) x LOOP
        v_i := v_i + 1;
        IF l.staffid IS NULL OR NOT EXISTS (
            SELECT 1 FROM genericstaff st WHERE st.genericstaffid = l.staffid AND st.farmid = p_farmid
              AND NOT COALESCE(st.isdeleted, false)) THEN
            RAISE EXCEPTION 'Line %: pick a staff member from this business.', v_i;
        END IF;
        IF l.basicpay < 0 OR l.dailywage < 0 OR l.commission < 0 OR l.bonus < 0 OR l.deductions < 0 THEN
            RAISE EXCEPTION 'Line %: pay amounts cannot be negative.', v_i;
        END IF;
        IF l.basicpay + l.dailywage + l.commission + l.bonus - l.deductions < 0 THEN
            RAISE EXCEPTION 'Line %: deductions are more than the pay.', v_i;
        END IF;
        IF EXISTS (SELECT 1 FROM genericpayrolltemplatelines tl
                   WHERE tl.genericpayrolltemplateid = v_id AND tl.genericstaffid = l.staffid) THEN
            RAISE EXCEPTION 'Line %: that staff member is already on this template.', v_i;
        END IF;
        INSERT INTO genericpayrolltemplatelines
            (genericpayrolltemplateid, genericstaffid, basicpay, dailywage, commission, bonus, deductions,
             paymentmethod, notes, sortorder)
        VALUES (v_id, l.staffid, l.basicpay, l.dailywage, l.commission, l.bonus, l.deductions,
                l.paymentmethod, l.notes, v_i);
    END LOOP;

    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrolltemplate_setactive(p_farmid text, p_templateid integer, p_active boolean, p_by text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE genericpayrolltemplates t
    SET    isactive = p_active, updatedby = p_by, updatedat = (now() AT TIME ZONE 'utc')
    WHERE  t.genericpayrolltemplateid = p_templateid AND t.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payroll template not found for this business.';
    END IF;
END $function$;

CREATE OR REPLACE FUNCTION public.spgenericpayrolltemplate_createrun(p_farmid text, p_templateid integer, p_periodstart date, p_periodend date, p_paydate date DEFAULT NULL::date, p_genericcashaccountid integer DEFAULT NULL::integer, p_notes text DEFAULT NULL::text, p_by text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_t      record;
    v_runid  integer;
    v_clash  record;
    l        record;
    v_lines  integer := 0;
BEGIN
    SELECT t.* INTO v_t FROM genericpayrolltemplates t
    WHERE  t.genericpayrolltemplateid = p_templateid AND t.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payroll template not found for this business.';
    END IF;
    IF NOT v_t.isactive THEN
        RAISE EXCEPTION 'Template "%" is archived. Restore it before using it.', v_t.name;
    END IF;
    IF p_periodstart IS NULL OR p_periodend IS NULL THEN
        RAISE EXCEPTION 'Pick the period start and end.';
    END IF;

    SELECT pr.periodstart, pr.periodend, pr.status INTO v_clash
    FROM   genericpayrollruns pr
    WHERE  pr.farmid = p_farmid AND pr.genericpayrolltemplateid = p_templateid
      AND  NOT pr.isdeleted AND pr.status <> 'Cancelled'
      AND  pr.periodstart::date <= p_periodend AND pr.periodend::date >= p_periodstart
    LIMIT  1;
    IF FOUND THEN
        RAISE EXCEPTION 'Template "%" already has a % run for % to %. Pick a period after it.',
            v_t.name, v_clash.status, to_char(v_clash.periodstart, 'YYYY-MM-DD'), to_char(v_clash.periodend, 'YYYY-MM-DD');
    END IF;

    v_runid := public.spgenericpayrollrun_insert(
        p_farmid, p_periodstart, p_periodend, p_paydate,
        COALESCE(p_genericcashaccountid, v_t.genericcashaccountid),
        COALESCE(NULLIF(btrim(COALESCE(p_notes, '')), ''), 'From template: ' || v_t.name),
        p_by);

    UPDATE genericpayrollruns pr SET genericpayrolltemplateid = p_templateid
    WHERE  pr.genericpayrollrunid = v_runid;

    FOR l IN SELECT tl.* FROM genericpayrolltemplatelines tl
             JOIN genericstaff st ON st.genericstaffid = tl.genericstaffid AND st.farmid = p_farmid
             WHERE tl.genericpayrolltemplateid = p_templateid
               AND COALESCE(st.isactive, false) AND NOT COALESCE(st.isdeleted, false)
             ORDER BY tl.sortorder LOOP
        PERFORM public.spgenericpayrollitem_upsert(
            v_runid, p_farmid, l.genericstaffid, l.basicpay, l.dailywage, l.commission,
            l.bonus, l.deductions, l.paymentmethod, l.notes);
        v_lines := v_lines + 1;
    END LOOP;

    IF v_lines = 0 THEN
        RAISE EXCEPTION 'Template "%" has no active staff on it.', v_t.name;
    END IF;

    RETURN v_runid;
END $function$;

-- =============================================================================
-- 249_GenericMoneyOut.postgres.sql
--
-- Purpose
-- -------
-- The money-out side of a Generic service business: what leaves every month
-- without anyone typing it in twice, who gets paid, and what the owner puts in
-- or takes out. Three things, one migration, because they all end at the same
-- place -- an expense and a cash movement -- and splitting them would mean
-- three near-identical posting routines.
--
--   Recurring expenses   hosting, tools, rent, retainers: a template that
--                        generates a real expense when it falls due.
--   Staff payments       paying a person without running full payroll.
--   Owner money          contributions in and draws out, tracked SEPARATELY
--                        from revenue and operating expenses.
--
-- What this REUSES rather than rebuilds
-- -------------------------------------
-- genericstaff already exists, with roles, salary types, base pay and
-- attendance, and so does a full payroll run/item/approve/markpaid chain. None
-- of that is touched. Section 1 only ADDS the four columns a contractor needs
-- that an employee record did not: how they are engaged, from when, how they
-- are paid and out of which account.
--
-- Payroll runs stay the way to pay a whole team for a period. Staff payments
-- are the other case the spec calls out -- a monthly contractor, a one-off
-- developer invoice -- where a full run is more machinery than the payment
-- deserves. Both post an expense and move cash; neither knows about the other.
--
-- Four things this file has to get right
-- --------------------------------------
--
-- 1. A RECURRING EXPENSE IS A TEMPLATE, NOT AN EXPENSE. It generates rows; it
--    is never itself a cost. Nothing reads it for the P&L, and pausing one
--    changes nothing that already happened.
--
-- 2. GENERATING TWICE FOR THE SAME PERIOD IS IMPOSSIBLE. Every generated
--    expense is stamped with the template that raised it and the period it
--    covers, and a partial unique index on the two makes the second attempt
--    FAIL rather than quietly double the month's hosting bill. This is the same
--    guarantee 243 gives subscription billing.
--
-- 3. THE LINK IS ITS OWN COLUMN, NOT sourcetype/sourceid. genericexpenses
--    already carries a UNIQUE index on (farmid, sourcetype, sourceid) where
--    sourcetype is set -- ONE live expense per source document, which is true
--    of every existing sourcetype: internal use, a purchase, a supplier
--    payment. A recurring template is the opposite: it produces MANY expenses,
--    one per period. Reusing sourcetype would have collided on the second
--    month, so the link is a dedicated genericrecurringexpenseid column with
--    its own uniqueness on (farm, template, period).
--
--    That also leaves sourcetype NULL on generated rows, which is what makes
--    them behave as ordinary bills: 248's payable arm takes sourcetype IS NULL,
--    so an unpaid recurring expense DOES reach Supplier Balances and is settled
--    like any other. Nothing special-cases it.
--
-- 4. OWNER MONEY IS NOT REVENUE AND NOT AN EXPENSE. A contribution is funding,
--    a draw is the owner taking their own money. Both move cash and neither
--    touches genericexpenses or genericsales, so profit is unaffected by how
--    the owner funds the business. They are their own table for exactly that
--    reason.
--
-- EFFECT ON TODAY'S NUMBERS: none. Three new tables, four nullable columns on
-- genericstaff, and functions. Nothing existing is read differently or
-- rewritten, and there is no backfill.
--
-- Order: after 248 (the expense payment columns it adds are used here).
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. genericstaff learns about contractors.
-- -----------------------------------------------------------------------------
-- Four nullable columns, no backfill. An existing staff row has NULL in all of
-- them and behaves exactly as it does today; the reads below treat a NULL
-- workertype as 'Employee', which is what every row written before now meant.
ALTER TABLE genericstaff ADD COLUMN IF NOT EXISTS workertype text NULL;
ALTER TABLE genericstaff ADD COLUMN IF NOT EXISTS startdate date NULL;
ALTER TABLE genericstaff ADD COLUMN IF NOT EXISTS paymentmethod text NULL;
ALTER TABLE genericstaff ADD COLUMN IF NOT EXISTS defaultcashaccountid integer NULL;

COMMENT ON COLUMN genericstaff.workertype IS
    'Employee | Contractor | Consultant | Other. NULL means Employee -- the '
    'meaning every row written before migration 249 already carries.';

-- -----------------------------------------------------------------------------
-- 2. Recurring expenses.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericrecurringexpenses (
    genericrecurringexpenseid serial PRIMARY KEY,
    farmid                    varchar(100) NOT NULL,
    expensename               varchar(200) NOT NULL,
    genericexpensecategoryid  integer      NOT NULL,
    genericsupplierid         integer      NULL,
    amount                    numeric(14,2) NOT NULL,
    frequency                 text         NOT NULL,
    startdate                 date         NOT NULL,
    enddate                   date         NULL,
    nextduedate               date         NULL,
    lastgenerateddate         date         NULL,
    paymentmethod             text         NULL,
    defaultcashaccountid      integer      NULL,
    -- When true the generated expense is marked paid and the cash moves; when
    -- false it is raised unpaid and somebody settles it later.
    autopayonGenerate         boolean      NOT NULL DEFAULT TRUE,
    reminderenabled           boolean      NOT NULL DEFAULT TRUE,
    status                    text         NOT NULL DEFAULT 'Active',
    notes                     text         NULL,
    createdby                 text         NULL,
    createdat                 timestamp    NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedat                 timestamp    NULL,
    cancelledby               text         NULL,
    cancelledat               timestamp    NULL,
    cancellationreason        text         NULL
);

CREATE INDEX IF NOT EXISTS ix_genericrecurringexpenses_farm
    ON genericrecurringexpenses (farmid, status);
CREATE INDEX IF NOT EXISTS ix_genericrecurringexpenses_due
    ON genericrecurringexpenses (farmid, nextduedate)
    WHERE status = 'Active';

-- Which template raised this expense, and the period it covers.
--
-- A dedicated column rather than sourcetype/sourceid, because genericexpenses
-- already has UNIQUE (farmid, sourcetype, sourceid) WHERE sourcetype IS NOT
-- NULL -- one live expense per source document. That holds for every existing
-- sourcetype and is exactly wrong for a template that raises one bill a month.
ALTER TABLE genericexpenses ADD COLUMN IF NOT EXISTS genericrecurringexpenseid integer NULL;
ALTER TABLE genericexpenses ADD COLUMN IF NOT EXISTS periodstart date NULL;
ALTER TABLE genericexpenses ADD COLUMN IF NOT EXISTS periodend   date NULL;

-- THE duplicate guard. Two people pressing Generate at the same moment cannot
-- both raise January's hosting bill; the second fails on the index, not on a
-- check that raced.
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericexpenses_recurring_period
    ON genericexpenses (farmid, genericrecurringexpenseid, periodstart)
    WHERE genericrecurringexpenseid IS NOT NULL AND COALESCE(isdeleted, FALSE) = FALSE;

-- Next due date. Deliberately the same shape as fngenericnextbillingdate (243)
-- so money in and money out advance by the same rules; monthly clamps into a
-- short month rather than skipping it.
CREATE OR REPLACE FUNCTION public.fngenericnextduedate(p_from date, p_frequency text)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT CASE p_frequency
                WHEN 'Weekly'     THEN p_from + interval '7 days'
                WHEN 'Monthly'    THEN p_from + interval '1 month'
                WHEN 'Quarterly'  THEN p_from + interval '3 months'
                WHEN 'SemiAnnual' THEN p_from + interval '6 months'
                WHEN 'Annual'     THEN p_from + interval '1 year'
                ELSE NULL
           END::date;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericrecurringexpense_getall(
    p_farmid text, p_status text DEFAULT NULL::text)
RETURNS TABLE(
    genericrecurringexpenseid integer, farmid text, expensename text,
    genericexpensecategoryid integer, categoryname text,
    genericsupplierid integer, suppliername text,
    amount numeric, frequency text, startdate date, enddate date,
    nextduedate date, lastgenerateddate date, paymentmethod text,
    defaultcashaccountid integer, autopayongenerate boolean, reminderenabled boolean,
    status text, notes text, isdue boolean, generatedcount integer,
    createdby text, createdat timestamp without time zone)
LANGUAGE sql
STABLE
AS $function$
    SELECT r.genericrecurringexpenseid, r.farmid::text, r.expensename::text,
           r.genericexpensecategoryid, c.name::text,
           r.genericsupplierid, s.suppliername::text,
           r.amount, r.frequency, r.startdate, r.enddate,
           r.nextduedate, r.lastgenerateddate, r.paymentmethod,
           r.defaultcashaccountid, r.autopayonGenerate, r.reminderenabled,
           r.status, r.notes,
           (r.status = 'Active' AND r.nextduedate IS NOT NULL AND r.nextduedate <= CURRENT_DATE),
           (SELECT COUNT(*)::int FROM genericexpenses e
             WHERE e.genericrecurringexpenseid = r.genericrecurringexpenseid
               AND COALESCE(e.isdeleted, FALSE) = FALSE),
           r.createdby, r.createdat
    FROM   genericrecurringexpenses r
    LEFT   JOIN genericexpensecategories c ON c.genericexpensecategoryid = r.genericexpensecategoryid
    LEFT   JOIN genericsuppliers s        ON s.genericsupplierid        = r.genericsupplierid
    WHERE  r.farmid = p_farmid
      AND  (p_status IS NULL OR p_status = 'All' OR r.status = p_status)
    ORDER  BY (r.status = 'Active') DESC, r.nextduedate NULLS LAST, r.expensename;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericrecurringexpense_insert(
    p_farmid                   text,
    p_expensename              text,
    p_genericexpensecategoryid integer,
    p_amount                   numeric,
    p_frequency                text,
    p_startdate                date,
    p_genericsupplierid        integer DEFAULT NULL::integer,
    p_enddate                  date    DEFAULT NULL::date,
    p_paymentmethod            text    DEFAULT NULL::text,
    p_defaultcashaccountid     integer DEFAULT NULL::integer,
    p_autopayongenerate        boolean DEFAULT TRUE,
    p_reminderenabled          boolean DEFAULT TRUE,
    p_notes                    text    DEFAULT NULL::text,
    p_createdby                text    DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id integer;
BEGIN
    IF COALESCE(btrim(p_expensename), '') = '' THEN
        RAISE EXCEPTION 'A name is required.';
    END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Amount must be greater than 0.';
    END IF;
    IF p_frequency NOT IN ('Weekly', 'Monthly', 'Quarterly', 'SemiAnnual', 'Annual') THEN
        RAISE EXCEPTION 'Unknown frequency "%".', p_frequency;
    END IF;
    IF p_startdate IS NULL THEN
        RAISE EXCEPTION 'A start date is required.';
    END IF;
    IF p_enddate IS NOT NULL AND p_enddate < p_startdate THEN
        RAISE EXCEPTION 'The end date cannot be before the start date.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM genericexpensecategories c
                   WHERE c.genericexpensecategoryid = p_genericexpensecategoryid
                     AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Expense category does not belong to this company.';
    END IF;

    INSERT INTO genericrecurringexpenses
        (farmid, expensename, genericexpensecategoryid, genericsupplierid, amount,
         frequency, startdate, enddate, nextduedate, paymentmethod,
         defaultcashaccountid, autopayonGenerate, reminderenabled, status, notes, createdby)
    VALUES
        (p_farmid, btrim(p_expensename), p_genericexpensecategoryid, p_genericsupplierid,
         p_amount, p_frequency, p_startdate, p_enddate, p_startdate, p_paymentmethod,
         p_defaultcashaccountid, COALESCE(p_autopayongenerate, TRUE),
         COALESCE(p_reminderenabled, TRUE), 'Active', p_notes, p_createdby)
    RETURNING genericrecurringexpenseid INTO v_id;

    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericrecurringexpense_setstatus(
    p_id     integer,
    p_farmid text,
    p_status text,
    p_by     text DEFAULT NULL::text,
    p_reason text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_status NOT IN ('Active', 'Paused', 'Cancelled', 'Expired') THEN
        RAISE EXCEPTION 'Unknown status "%".', p_status;
    END IF;
    IF p_status = 'Cancelled' AND COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to cancel a recurring expense.';
    END IF;

    UPDATE genericrecurringexpenses
    SET    status             = p_status,
           cancelledby        = CASE WHEN p_status = 'Cancelled' THEN p_by ELSE cancelledby END,
           cancelledat        = CASE WHEN p_status = 'Cancelled'
                                     THEN (now() at time zone 'utc') ELSE cancelledat END,
           cancellationreason = CASE WHEN p_status = 'Cancelled' THEN p_reason ELSE cancellationreason END,
           updatedat          = (now() at time zone 'utc')
    WHERE  genericrecurringexpenseid = p_id AND farmid = p_farmid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Recurring expense not found for this company.';
    END IF;
    RETURN p_id;
END;
$function$;

-- What generating now would raise. Shares its selection with _generate below,
-- so the owner cannot be shown one set and charged another.
CREATE OR REPLACE FUNCTION public.spgenericrecurringexpense_preview(
    p_farmid text, p_asof date DEFAULT NULL::date)
RETURNS TABLE(
    genericrecurringexpenseid integer, expensename text, categoryname text,
    suppliername text, amount numeric, frequency text,
    periodstart date, periodend date, alreadygenerated boolean)
LANGUAGE sql
STABLE
AS $function$
    WITH asof AS (SELECT COALESCE(p_asof, CURRENT_DATE) AS d)
    SELECT r.genericrecurringexpenseid, r.expensename::text, c.name::text, s.suppliername::text,
           r.amount, r.frequency,
           r.nextduedate,
           (COALESCE(fngenericnextduedate(r.nextduedate, r.frequency),
                     r.nextduedate + 1) - 1)::date,
           EXISTS (SELECT 1 FROM genericexpenses e
                   WHERE e.genericrecurringexpenseid = r.genericrecurringexpenseid
                     AND e.periodstart = r.nextduedate
                     AND COALESCE(e.isdeleted, FALSE) = FALSE)
    FROM   genericrecurringexpenses r
    LEFT   JOIN genericexpensecategories c ON c.genericexpensecategoryid = r.genericexpensecategoryid
    LEFT   JOIN genericsuppliers s        ON s.genericsupplierid        = r.genericsupplierid
    WHERE  r.farmid = p_farmid
      AND  r.status = 'Active'
      AND  r.nextduedate IS NOT NULL
      AND  r.nextduedate <= (SELECT d FROM asof)
      AND  (r.enddate IS NULL OR r.nextduedate <= r.enddate)
    ORDER  BY r.nextduedate, r.genericrecurringexpenseid;
$function$;

-- Generates every period a recurring expense is behind, one expense each, and
-- stops at the as-of date. The 60-iteration guard stops a bad frequency (which
-- returns a NULL next date) from spinning forever -- same as 243.
CREATE OR REPLACE FUNCTION public.spgenericrecurringexpense_generate(
    p_farmid    text,
    p_asof      date DEFAULT NULL::date,
    p_createdby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_asof      date := COALESCE(p_asof, CURRENT_DATE);
    v_rec       record;
    v_generated integer := 0;
    v_next      date;
    v_periodend date;
    v_guard     integer;
    v_expid     integer;
    v_cashbal   numeric(14,2);
BEGIN
    FOR v_rec IN
        SELECT r.* FROM genericrecurringexpenses r
        WHERE  r.farmid = p_farmid AND r.status = 'Active'
          AND  r.nextduedate IS NOT NULL AND r.nextduedate <= v_asof
        ORDER  BY r.genericrecurringexpenseid
    LOOP
        v_next  := v_rec.nextduedate;
        v_guard := 0;

        WHILE v_next IS NOT NULL AND v_next <= v_asof
              AND (v_rec.enddate IS NULL OR v_next <= v_rec.enddate)
              AND v_guard < 60
        LOOP
            v_guard     := v_guard + 1;
            v_periodend := (COALESCE(fngenericnextduedate(v_next, v_rec.frequency),
                                     v_next + 1) - 1)::date;

            IF NOT EXISTS (SELECT 1 FROM genericexpenses e
                           WHERE e.genericrecurringexpenseid = v_rec.genericrecurringexpenseid
                             AND e.periodstart = v_next
                             AND COALESCE(e.isdeleted, FALSE) = FALSE) THEN

                INSERT INTO genericexpenses
                    (farmid, expensedate, genericexpensecategoryid, genericsupplierid,
                     description, amount, paymentmethod, genericcashaccountid,
                     amountpaid, status, notes, genericrecurringexpenseid,
                     periodstart, periodend, createdby, approvedby, approvedat,
                     isdeleted, createdat)
                VALUES
                    (p_farmid, v_next::timestamp, v_rec.genericexpensecategoryid,
                     v_rec.genericsupplierid,
                     v_rec.expensename || ' (' || to_char(v_next, 'DD Mon YYYY') || ')',
                     v_rec.amount, COALESCE(v_rec.paymentmethod, 'Cash'),
                     CASE WHEN v_rec.autopayonGenerate THEN v_rec.defaultcashaccountid END,
                     -- Paid outright when an account is given, otherwise it is a
                     -- bill somebody settles later. NULL means paid in full.
                     CASE WHEN v_rec.autopayonGenerate AND v_rec.defaultcashaccountid IS NOT NULL
                          THEN NULL ELSE 0 END,
                     'Approved', v_rec.notes,
                     v_rec.genericrecurringexpenseid, v_next, v_periodend,
                     p_createdby, p_createdby, (now() at time zone 'utc'),
                     FALSE, (now() at time zone 'utc'))
                RETURNING genericexpenseid INTO v_expid;

                -- Cash moves only when it actually moved.
                IF v_rec.autopayonGenerate AND v_rec.defaultcashaccountid IS NOT NULL THEN
                    SELECT COALESCE(currentbalance, 0) INTO v_cashbal
                    FROM   genericcashaccounts
                    WHERE  genericcashaccountid = v_rec.defaultcashaccountid AND farmid = p_farmid;

                    INSERT INTO genericcashtransactions
                        (farmid, genericcashaccountid, transactiondate, transactiontype,
                         sourcetype, sourceid, amount, balanceaftertransaction, description,
                         createdby, approvedby, approvedat)
                    VALUES
                        (p_farmid, v_rec.defaultcashaccountid, v_next::timestamp, 'CashOut',
                         'GenericExpense', v_expid, -v_rec.amount, v_cashbal - v_rec.amount,
                         v_rec.expensename, p_createdby, p_createdby, (now() at time zone 'utc'));

                    UPDATE genericcashaccounts
                    SET    currentbalance = v_cashbal - v_rec.amount,
                           updatedat      = (now() at time zone 'utc')
                    WHERE  genericcashaccountid = v_rec.defaultcashaccountid AND farmid = p_farmid;
                END IF;

                v_generated := v_generated + 1;
            END IF;

            v_next := fngenericnextduedate(v_next, v_rec.frequency);
        END LOOP;

        UPDATE genericrecurringexpenses
        SET    nextduedate       = v_next,
               lastgenerateddate = CASE WHEN v_generated > 0 THEN v_asof ELSE lastgenerateddate END,
               status            = CASE WHEN enddate IS NOT NULL AND v_next IS NOT NULL
                                             AND v_next > enddate
                                        THEN 'Expired' ELSE status END,
               updatedat         = (now() at time zone 'utc')
        WHERE  genericrecurringexpenseid = v_rec.genericrecurringexpenseid;
    END LOOP;

    RETURN v_generated;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Staff and contractor payments.
-- -----------------------------------------------------------------------------
-- The simple case payroll runs are too heavy for: pay one person, now. It posts
-- an expense so the cost reaches the P&L and the expense reports, and one
-- CashOut so it reaches cash flow -- the same two things a payroll run does,
-- without the run.
CREATE TABLE IF NOT EXISTS genericstaffpayments (
    genericstaffpaymentid    serial PRIMARY KEY,
    farmid                   varchar(100) NOT NULL,
    genericstaffid           integer      NOT NULL,
    paymentdate              timestamp    NOT NULL,
    periodstart              date         NULL,
    periodend                date         NULL,
    amount                   numeric(14,2) NOT NULL,
    paymentmethod            text         NULL,
    genericcashaccountid     integer      NULL,
    genericexpensecategoryid integer      NULL,
    genericexpenseid         integer      NULL,
    description              text         NULL,
    referenceno              text         NULL,
    status                   text         NOT NULL DEFAULT 'Posted',
    createdby                text         NULL,
    createdat                timestamp    NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby               text         NULL,
    reversedat               timestamp    NULL,
    reversalreason           text         NULL
);

CREATE INDEX IF NOT EXISTS ix_genericstaffpayments_farm
    ON genericstaffpayments (farmid, paymentdate DESC);
CREATE INDEX IF NOT EXISTS ix_genericstaffpayments_staff
    ON genericstaffpayments (farmid, genericstaffid);

CREATE OR REPLACE FUNCTION public.spgenericstaffpayment_record(
    p_farmid                   text,
    p_genericstaffid           integer,
    p_amount                   numeric,
    p_paymentdate              timestamp DEFAULT NULL::timestamp,
    p_paymentmethod            text      DEFAULT NULL::text,
    p_cashaccountid            integer   DEFAULT NULL::integer,
    p_genericexpensecategoryid integer   DEFAULT NULL::integer,
    p_periodstart              date      DEFAULT NULL::date,
    p_periodend                date      DEFAULT NULL::date,
    p_description              text      DEFAULT NULL::text,
    p_reference                text      DEFAULT NULL::text,
    p_createdby                text      DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id       integer;
    v_expid    integer;
    v_date     timestamp := COALESCE(p_paymentdate, (now() at time zone 'utc'));
    v_name     text;
    v_worker   text;
    v_cat      integer := p_genericexpensecategoryid;
    v_cashbal  numeric(14,2);
    v_desc     text;
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than 0.';
    END IF;

    SELECT btrim(COALESCE(s.firstname, '') || ' ' || COALESCE(s.lastname, '')),
           COALESCE(s.workertype, 'Employee')
      INTO v_name, v_worker
    FROM   genericstaff s
    WHERE  s.genericstaffid = p_genericstaffid AND s.farmid = p_farmid
      AND  COALESCE(s.isdeleted, FALSE) = FALSE;

    IF v_name IS NULL THEN
        RAISE EXCEPTION 'Staff member not found for this company.';
    END IF;
    IF p_cashaccountid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM genericcashaccounts a
                       WHERE a.genericcashaccountid = p_cashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
    END IF;

    -- Fall back to the category that matches how this person is engaged, so a
    -- contractor's pay does not land under employee costs.
    IF v_cat IS NULL THEN
        SELECT c.genericexpensecategoryid INTO v_cat
        FROM   genericexpensecategories c
        WHERE  c.farmid = p_farmid
          AND  c.name ILIKE CASE WHEN v_worker = 'Employee'
                                 THEN 'Employee Payments' ELSE 'Contractor Payments' END
        LIMIT  1;
    END IF;
    IF v_cat IS NULL THEN
        SELECT c.genericexpensecategoryid INTO v_cat
        FROM   genericexpensecategories c WHERE c.farmid = p_farmid ORDER BY 1 LIMIT 1;
    END IF;
    IF v_cat IS NULL THEN
        RAISE EXCEPTION 'This company has no expense categories to post the payment against.';
    END IF;

    v_desc := COALESCE(NULLIF(btrim(p_description), ''),
                       'Payment to ' || v_name
                       || CASE WHEN p_periodstart IS NOT NULL
                               THEN ' (' || to_char(p_periodstart, 'DD Mon YYYY') || ')'
                               ELSE '' END);

    -- The cost. Marked paid when an account is given, so the expense's own
    -- payment state matches what the cash did.
    INSERT INTO genericexpenses
        -- No sourcetype, for the same reason the recurring rows carry none: the
        -- unique index would let this person be paid exactly once, ever. The
        -- link back lives on genericstaffpayments.genericexpenseid instead.
        (farmid, expensedate, genericexpensecategoryid, description, amount,
         paidto, paymentmethod, genericcashaccountid, amountpaid, status,
         staffid, createdby, approvedby, approvedat, isdeleted, createdat)
    VALUES
        (p_farmid, v_date, v_cat, v_desc, p_amount,
         v_name, COALESCE(p_paymentmethod, 'Cash'), p_cashaccountid,
         CASE WHEN p_cashaccountid IS NOT NULL THEN NULL ELSE 0 END,
         'Approved', p_genericstaffid,
         p_createdby, p_createdby, (now() at time zone 'utc'), FALSE, (now() at time zone 'utc'))
    RETURNING genericexpenseid INTO v_expid;

    INSERT INTO genericstaffpayments
        (farmid, genericstaffid, paymentdate, periodstart, periodend, amount,
         paymentmethod, genericcashaccountid, genericexpensecategoryid,
         genericexpenseid, description, referenceno, status, createdby)
    VALUES
        (p_farmid, p_genericstaffid, v_date, p_periodstart, p_periodend, p_amount,
         p_paymentmethod, p_cashaccountid, v_cat, v_expid, v_desc, p_reference,
         'Posted', p_createdby)
    RETURNING genericstaffpaymentid INTO v_id;

    IF p_cashaccountid IS NOT NULL THEN
        SELECT COALESCE(currentbalance, 0) INTO v_cashbal
        FROM   genericcashaccounts
        WHERE  genericcashaccountid = p_cashaccountid AND farmid = p_farmid;

        INSERT INTO genericcashtransactions
            (farmid, genericcashaccountid, transactiondate, transactiontype,
             sourcetype, sourceid, amount, balanceaftertransaction, description,
             createdby, approvedby, approvedat)
        VALUES
            (p_farmid, p_cashaccountid, v_date, 'CashOut', 'GenericStaffPayment', v_id,
             -p_amount, v_cashbal - p_amount, v_desc,
             p_createdby, p_createdby, (now() at time zone 'utc'));

        UPDATE genericcashaccounts
        SET    currentbalance = v_cashbal - p_amount, updatedat = (now() at time zone 'utc')
        WHERE  genericcashaccountid = p_cashaccountid AND farmid = p_farmid;
    END IF;

    RETURN v_id;
END;
$function$;

-- Append-only, like every other reversal here: the payment is marked Reversed
-- and kept, its expense is soft-deleted so it leaves the P&L, and the cash
-- comes back as its own row rather than by editing the original.
CREATE OR REPLACE FUNCTION public.spgenericstaffpayment_reverse(
    p_farmid     text,
    p_paymentid  integer,
    p_reason     text DEFAULT NULL::text,
    p_reversedby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_now     timestamp := (now() at time zone 'utc');
    v_status  text;
    v_amount  numeric(14,2);
    v_account integer;
    v_expid   integer;
    v_cashbal numeric(14,2);
BEGIN
    SELECT sp.status, sp.amount, sp.genericcashaccountid, sp.genericexpenseid
      INTO v_status, v_amount, v_account, v_expid
    FROM   genericstaffpayments sp
    WHERE  sp.genericstaffpaymentid = p_paymentid AND sp.farmid = p_farmid;

    IF v_amount IS NULL THEN
        RAISE EXCEPTION 'Payment not found for this company.';
    END IF;
    IF COALESCE(v_status, '') = 'Reversed' THEN
        RAISE EXCEPTION 'Only a posted payment can be reversed (this one is Reversed).';
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a payment.';
    END IF;

    IF v_expid IS NOT NULL THEN
        UPDATE genericexpenses
        SET    isdeleted = TRUE, updatedat = v_now,
               notes = COALESCE(notes, '') || ' | Reversed: ' || p_reason
        WHERE  genericexpenseid = v_expid AND farmid = p_farmid;
    END IF;

    IF v_account IS NOT NULL THEN
        SELECT COALESCE(currentbalance, 0) INTO v_cashbal
        FROM   genericcashaccounts
        WHERE  genericcashaccountid = v_account AND farmid = p_farmid;

        INSERT INTO genericcashtransactions
            (farmid, genericcashaccountid, transactiondate, transactiontype,
             sourcetype, sourceid, amount, balanceaftertransaction, description,
             createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_account, v_now, 'CashIn', 'GenericStaffPayment', p_paymentid,
             v_amount, v_cashbal + v_amount,
             'Reversal of staff payment #' || p_paymentid::text, p_reversedby, p_reversedby, v_now);

        UPDATE genericcashaccounts
        SET    currentbalance = v_cashbal + v_amount, updatedat = v_now
        WHERE  genericcashaccountid = v_account AND farmid = p_farmid;
    END IF;

    UPDATE genericstaffpayments
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason
    WHERE  genericstaffpaymentid = p_paymentid AND farmid = p_farmid;

    RETURN p_paymentid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericstaffpayment_getall(
    p_farmid  text,
    p_staffid integer DEFAULT NULL::integer,
    p_from    date    DEFAULT NULL::date,
    p_to      date    DEFAULT NULL::date)
RETURNS TABLE(
    genericstaffpaymentid integer, genericstaffid integer, staffname text,
    staffrole text, workertype text, paymentdate timestamp without time zone,
    periodstart date, periodend date, amount numeric, paymentmethod text,
    genericcashaccountid integer, cashaccountname text,
    genericexpenseid integer, categoryname text, description text,
    referenceno text, status text, createdby text,
    reversedby text, reversedat timestamp without time zone, reversalreason text)
LANGUAGE sql
STABLE
AS $function$
    SELECT sp.genericstaffpaymentid, sp.genericstaffid,
           btrim(COALESCE(s.firstname, '') || ' ' || COALESCE(s.lastname, ''))::text,
           s.role::text, COALESCE(s.workertype, 'Employee')::text,
           sp.paymentdate, sp.periodstart, sp.periodend, sp.amount, sp.paymentmethod,
           sp.genericcashaccountid, a.accountname::text,
           sp.genericexpenseid, c.name::text, sp.description, sp.referenceno,
           sp.status, sp.createdby, sp.reversedby, sp.reversedat, sp.reversalreason
    FROM   genericstaffpayments sp
    LEFT   JOIN genericstaff s          ON s.genericstaffid = sp.genericstaffid
    LEFT   JOIN genericcashaccounts a   ON a.genericcashaccountid = sp.genericcashaccountid
    LEFT   JOIN genericexpensecategories c ON c.genericexpensecategoryid = sp.genericexpensecategoryid
    WHERE  sp.farmid = p_farmid
      AND  (p_staffid IS NULL OR sp.genericstaffid = p_staffid)
      AND  (p_from IS NULL OR sp.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR sp.paymentdate::date <= p_to)
    ORDER  BY sp.paymentdate DESC, sp.genericstaffpaymentid DESC;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Owner contributions and draws.
-- -----------------------------------------------------------------------------
-- Owner money is NOT revenue and NOT an operating expense. A contribution is
-- the owner funding the business; a draw is them taking their own money out.
-- Both move cash and neither touches genericexpenses or genericsales, so profit
-- is unaffected by how the owner funds things -- which is the whole reason this
-- is its own table rather than a category on either side.
CREATE TABLE IF NOT EXISTS genericownercontributiondraws (
    genericownerentryid  serial PRIMARY KEY,
    farmid               varchar(100) NOT NULL,
    entrydate            timestamp    NOT NULL,
    entrytype            text         NOT NULL,   -- Contribution | Draw
    amount               numeric(14,2) NOT NULL,
    genericcashaccountid integer      NULL,
    paymentmethod        text         NULL,
    ownername            text         NULL,
    referenceno          text         NULL,
    notes                text         NULL,
    status               text         NOT NULL DEFAULT 'Posted',
    createdby            text         NULL,
    createdat            timestamp    NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby           text         NULL,
    reversedat           timestamp    NULL,
    reversalreason       text         NULL
);

CREATE INDEX IF NOT EXISTS ix_genericownerentries_farm
    ON genericownercontributiondraws (farmid, entrydate DESC);

CREATE OR REPLACE FUNCTION public.spgenericownerentry_record(
    p_farmid        text,
    p_entrytype     text,
    p_amount        numeric,
    p_cashaccountid integer   DEFAULT NULL::integer,
    p_entrydate     timestamp DEFAULT NULL::timestamp,
    p_paymentmethod text      DEFAULT NULL::text,
    p_ownername     text      DEFAULT NULL::text,
    p_reference     text      DEFAULT NULL::text,
    p_notes         text      DEFAULT NULL::text,
    p_createdby     text      DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id      integer;
    v_date    timestamp := COALESCE(p_entrydate, (now() at time zone 'utc'));
    v_cashbal numeric(14,2);
    v_signed  numeric(14,2);
BEGIN
    IF p_entrytype NOT IN ('Contribution', 'Draw') THEN
        RAISE EXCEPTION 'Entry type must be Contribution or Draw.';
    END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Amount must be greater than 0.';
    END IF;
    IF p_cashaccountid IS NULL THEN
        RAISE EXCEPTION 'A cash account is required -- owner money always moves cash.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM genericcashaccounts a
                   WHERE a.genericcashaccountid = p_cashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
    END IF;

    INSERT INTO genericownercontributiondraws
        (farmid, entrydate, entrytype, amount, genericcashaccountid, paymentmethod,
         ownername, referenceno, notes, status, createdby)
    VALUES
        (p_farmid, v_date, p_entrytype, p_amount, p_cashaccountid, p_paymentmethod,
         p_ownername, p_reference, p_notes, 'Posted', p_createdby)
    RETURNING genericownerentryid INTO v_id;

    v_signed := CASE WHEN p_entrytype = 'Contribution' THEN p_amount ELSE -p_amount END;

    SELECT COALESCE(currentbalance, 0) INTO v_cashbal
    FROM   genericcashaccounts
    WHERE  genericcashaccountid = p_cashaccountid AND farmid = p_farmid;

    -- sourcetype names it distinctly so cash flow can report owner money apart
    -- from sales income and operating expenses, which is what section 19 of the
    -- spec asks for.
    INSERT INTO genericcashtransactions
        (farmid, genericcashaccountid, transactiondate, transactiontype,
         sourcetype, sourceid, amount, balanceaftertransaction, description,
         createdby, approvedby, approvedat)
    VALUES
        (p_farmid, p_cashaccountid, v_date,
         CASE WHEN p_entrytype = 'Contribution' THEN 'CashIn' ELSE 'CashOut' END,
         'GenericOwner' || p_entrytype, v_id, v_signed, v_cashbal + v_signed,
         COALESCE(p_notes, 'Owner ' || lower(p_entrytype)),
         p_createdby, p_createdby, (now() at time zone 'utc'));

    UPDATE genericcashaccounts
    SET    currentbalance = v_cashbal + v_signed, updatedat = (now() at time zone 'utc')
    WHERE  genericcashaccountid = p_cashaccountid AND farmid = p_farmid;

    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericownerentry_reverse(
    p_farmid     text,
    p_entryid    integer,
    p_reason     text DEFAULT NULL::text,
    p_reversedby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_now     timestamp := (now() at time zone 'utc');
    v_status  text;
    v_type    text;
    v_amount  numeric(14,2);
    v_account integer;
    v_cashbal numeric(14,2);
    v_signed  numeric(14,2);
BEGIN
    SELECT o.status, o.entrytype, o.amount, o.genericcashaccountid
      INTO v_status, v_type, v_amount, v_account
    FROM   genericownercontributiondraws o
    WHERE  o.genericownerentryid = p_entryid AND o.farmid = p_farmid;

    IF v_amount IS NULL THEN
        RAISE EXCEPTION 'Entry not found for this company.';
    END IF;
    IF COALESCE(v_status, '') = 'Reversed' THEN
        RAISE EXCEPTION 'Only a posted entry can be reversed (this one is Reversed).';
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse an entry.';
    END IF;

    -- The opposite of what it did.
    v_signed := CASE WHEN v_type = 'Contribution' THEN -v_amount ELSE v_amount END;

    IF v_account IS NOT NULL THEN
        SELECT COALESCE(currentbalance, 0) INTO v_cashbal
        FROM   genericcashaccounts
        WHERE  genericcashaccountid = v_account AND farmid = p_farmid;

        INSERT INTO genericcashtransactions
            (farmid, genericcashaccountid, transactiondate, transactiontype,
             sourcetype, sourceid, amount, balanceaftertransaction, description,
             createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_account, v_now,
             CASE WHEN v_type = 'Contribution' THEN 'CashOut' ELSE 'CashIn' END,
             'GenericOwner' || v_type, p_entryid, v_signed, v_cashbal + v_signed,
             'Reversal of owner ' || lower(v_type) || ' #' || p_entryid::text,
             p_reversedby, p_reversedby, v_now);

        UPDATE genericcashaccounts
        SET    currentbalance = v_cashbal + v_signed, updatedat = v_now
        WHERE  genericcashaccountid = v_account AND farmid = p_farmid;
    END IF;

    UPDATE genericownercontributiondraws
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason
    WHERE  genericownerentryid = p_entryid AND farmid = p_farmid;

    RETURN p_entryid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericownerentry_getall(
    p_farmid    text,
    p_entrytype text DEFAULT NULL::text,
    p_from      date DEFAULT NULL::date,
    p_to        date DEFAULT NULL::date)
RETURNS TABLE(
    genericownerentryid integer, entrydate timestamp without time zone, entrytype text,
    amount numeric, genericcashaccountid integer, cashaccountname text,
    paymentmethod text, ownername text, referenceno text, notes text,
    status text, createdby text,
    reversedby text, reversedat timestamp without time zone, reversalreason text)
LANGUAGE sql
STABLE
AS $function$
    SELECT o.genericownerentryid, o.entrydate, o.entrytype, o.amount,
           o.genericcashaccountid, a.accountname::text, o.paymentmethod,
           o.ownername, o.referenceno, o.notes, o.status, o.createdby,
           o.reversedby, o.reversedat, o.reversalreason
    FROM   genericownercontributiondraws o
    LEFT   JOIN genericcashaccounts a ON a.genericcashaccountid = o.genericcashaccountid
    WHERE  o.farmid = p_farmid
      AND  (p_entrytype IS NULL OR p_entrytype = 'All' OR o.entrytype = p_entrytype)
      AND  (p_from IS NULL OR o.entrydate::date >= p_from)
      AND  (p_to   IS NULL OR o.entrydate::date <= p_to)
    ORDER  BY o.entrydate DESC, o.genericownerentryid DESC;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Permission catalog.
-- -----------------------------------------------------------------------------
DO $iam$
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '249: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions
        (permissionkey, module, resource, action, permissiongroup, resourcelabel,
         description, companytype, isdangerous, sortorder)
    SELECT 'generic.' || r.resource || '.' || a.action,
           'generic', r.resource, a.action, r.grp, r.label, r.descr, 'Generic',
           (a.action IN ('reverse', 'delete')), r.sortorder
    FROM (VALUES
        ('recurring-expenses', 'Expenses',            'Recurring Expenses',
         'Set up costs that repeat, and raise them when they fall due.',  76),
        ('staff-payments',     'People',              'Staff Payments',
         'Pay a member of staff or a contractor without a payroll run.',  86),
        ('owner-entries',      'Sales & Money',       'Owner Money',
         'Record money the owner puts in or takes out.',                  66)
    ) AS r(resource, grp, label, descr, sortorder)
    CROSS JOIN (VALUES ('view'), ('create'), ('edit'), ('reverse')) AS a(action)
    WHERE NOT EXISTS (SELECT 1 FROM iampermissions p
                      WHERE p.permissionkey = 'generic.' || r.resource || '.' || a.action);
END
$iam$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 6. Verification.
-- -----------------------------------------------------------------------------
SELECT 'tables' AS check,
       CASE WHEN to_regclass('public.genericrecurringexpenses') IS NOT NULL
             AND to_regclass('public.genericstaffpayments') IS NOT NULL
             AND to_regclass('public.genericownercontributiondraws') IS NOT NULL
            THEN 'OK' ELSE 'MISSING' END AS result;

SELECT 'functions' AS check,
       CASE WHEN COUNT(*) = 10 THEN 'OK' ELSE 'ONLY ' || COUNT(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('fngenericnextduedate', 'spgenericrecurringexpense_getall',
                     'spgenericrecurringexpense_insert', 'spgenericrecurringexpense_setstatus',
                     'spgenericrecurringexpense_preview', 'spgenericrecurringexpense_generate',
                     'spgenericstaffpayment_record', 'spgenericstaffpayment_reverse',
                     'spgenericstaffpayment_getall', 'spgenericownerentry_record');

-- The schedule, spelled out. Every row must say OK, and must agree with 243's
-- billing schedule -- money in and money out advance by the same rules.
SELECT 'schedule' AS check, freq, expected::text,
       fngenericnextduedate('2026-01-31', freq)::text,
       CASE WHEN fngenericnextduedate('2026-01-31', freq) IS NOT DISTINCT FROM expected
            THEN 'OK' ELSE 'WRONG' END AS result
FROM (VALUES
    ('Weekly',     '2026-02-07'::date),
    ('Monthly',    '2026-02-28'::date),   -- clamps, rather than skipping February
    ('Quarterly',  '2026-04-30'::date),
    ('SemiAnnual', '2026-07-31'::date),
    ('Annual',     '2027-01-31'::date)
) AS t(freq, expected);

-- No existing staff row was given a worker type. Expect NO ROWS.
SELECT genericstaffid, workertype FROM genericstaff WHERE workertype IS NOT NULL;

-- No existing expense picked up a period or a template. Expect NO ROWS.
SELECT genericexpenseid, periodstart, genericrecurringexpenseid
FROM   genericexpenses
WHERE  periodstart IS NOT NULL OR genericrecurringexpenseid IS NOT NULL;

-- The pre-existing one-expense-per-source invariant is untouched: nothing this
-- migration writes sets sourcetype at all. Expect NO ROWS.
SELECT farmid, sourcetype, sourceid, COUNT(*)
FROM   genericexpenses
WHERE  sourcetype IS NOT NULL AND COALESCE(isdeleted, FALSE) = FALSE
GROUP  BY 1, 2, 3 HAVING COUNT(*) > 1;

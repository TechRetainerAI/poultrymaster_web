-- =============================================================================
-- 238_PoultryExpensePayables.postgres.sql
--
-- Purpose
-- -------
-- Make `expense` the third poultry payable, alongside poultryrawmaterialpurchases
-- and mainflockbatch, so an unpaid or part-paid bill reaches Supplier Balances and
-- can be settled by the same SupplierPayment + SupplierPaymentAllocation machinery
-- that 222/224 already built.
--
-- 224's header says expenses are "deliberately NOT payables here: `expense` has no
-- amountpaid column to part-pay against, and its farmid is a uuid while every other
-- table uses text." This file removes the first objection and works around the
-- second the same way every other expense-writing SP does.
--
-- Four things this file has to get right
-- --------------------------------------
--
-- 1. TODAY'S NUMBERS MUST NOT MOVE. `amountpaid` is NULLABLE and NULL means "paid
--    in full", the semantics every existing row already has. So there is NO
--    backfill UPDATE: 153 existing expenses, and every future row written by
--    payroll, driver returns, internal use, purchases and supplier payments --
--    none of which know this column exists -- keep behaving exactly as before.
--    Effective paid is COALESCE(amountpaid, amount) everywhere, without exception.
--
-- 2. paymentstatus IS GENERATED, NOT STORED BY HAND. A dozen SPs insert into
--    `expense` and none of them will be taught about payment state. A generated
--    column cannot drift from the amounts it is derived from, and it makes every
--    one of those writers correct without touching a line of their code.
--
-- 3. NO SECOND EXPENSE WHEN AN EXPENSE IS PAID. 224 books an expense row per
--    allocation because a raw-material purchase is not itself an expense -- that
--    is how the cost reaches the P&L (migration 207's invariant). An expense IS
--    already the cost. Booking another would double-count it, which is exactly the
--    accounting error this work exists to prevent. The insert is therefore
--    narrowed to the two purchase types, and reversal's DELETE with it.
--
-- 4. NO DOUBLE-COUNTED CASH. Same v_alloc subtraction 224 used for purchases: the
--    expense's own cash line is narrowed to what allocations have NOT covered, so
--    money paid at entry and money paid later through a supplier payment stay
--    disjoint. Existing expenses have no allocations and are untouched.
--
-- Cash FLOW (as opposed to cash accounts) is migration 239's job -- since 235 it
-- reads `expense` directly rather than the ledger, so it needs the same two-arm
-- treatment. Apply 238 then 239; neither is correct alone.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Payment columns on expense.
-- -----------------------------------------------------------------------------
-- supplierid is the FK `expense` never had -- `supplier` has always been free
-- text, the same trap sales had with customers and purchases had with suppliers.
-- Free text stays and stays authoritative for display; supplierid is what makes a
-- row a payable. An expense with no supplierid can still be unpaid, it simply has
-- nobody to owe, so it cannot appear on Supplier Balances.
ALTER TABLE expense ADD COLUMN IF NOT EXISTS supplierid integer NULL;
ALTER TABLE expense ADD COLUMN IF NOT EXISTS amountpaid numeric(14,2) NULL;
ALTER TABLE expense ADD COLUMN IF NOT EXISTS duedate date NULL;

COMMENT ON COLUMN expense.amountpaid IS
    'Cash actually paid against this expense. NULL means paid in full -- the '
    'semantics every row written before migration 238 has, and every row written '
    'by an SP that does not know this column exists. Read it as '
    'COALESCE(amountpaid, amount), never bare.';

-- Generated, so it can never disagree with the amounts. NonCash wins outright:
-- internal use (216) posts paymentmethod='NonCash' to record stock leaving with
-- no money moving, and such a row must never be offered as something to pay.
DO $genstatus$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'expense' AND column_name = 'paymentstatus') THEN
        ALTER TABLE expense ADD COLUMN paymentstatus text
            GENERATED ALWAYS AS (
                CASE WHEN COALESCE(paymentmethod, '') = 'NonCash' THEN 'NonCash'
                     WHEN COALESCE(amountpaid, amount) >= COALESCE(amount, 0) THEN 'Paid'
                     WHEN COALESCE(amountpaid, amount) <= 0 THEN 'Unpaid'
                     ELSE 'PartiallyPaid'
                END) STORED;
        RAISE NOTICE '238: added generated column expense.paymentstatus';
    END IF;
END
$genstatus$;

-- Partial: the payables read only ever wants rows that still owe something.
CREATE INDEX IF NOT EXISTS ix_expense_farm_supplier
    ON expense (farmid, supplierid)
    WHERE supplierid IS NOT NULL AND amountpaid IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 2. The expense CRUD functions.
-- -----------------------------------------------------------------------------
-- Dropped BY NAME rather than by signature, deliberately. The live Postgres bodies
-- of these five are not in this repo -- only the T-SQL originals in 016/132, and
-- 229:26 is explicit that the T-SQL and the live functions have provably diverged
-- at least once. Dropping a guessed signature would leave the real one standing
-- and create an overload beside it, and every named-argument call would then fail
-- as ambiguous. Dropping every overload by name and recreating exactly one is the
-- only way to land in a known state without reading the database first.
--
-- What is reproduced here is the full contract ExpenseService.MapExpense reads
-- (016/132), plus the new payment columns and sourcetype/sourceid so the Expenses
-- page can show where a row came from.
DO $dropexpense$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure::text AS sig
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('spexpense_insert', 'spexpense_update',
                             'spexpense_getall', 'spexpense_getbyid',
                             'spexpense_getbyflock')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
        RAISE NOTICE '238: dropped %', r.sig;
    END LOOP;
END
$dropexpense$;

-- One composite type, three readers -- rather than the same 21-column list
-- written out three times and drifting apart on the next change.
DROP TYPE IF EXISTS public.poultryexpenserow CASCADE;
CREATE TYPE public.poultryexpenserow AS (
    expenseid            integer,
    expensedate          timestamp without time zone,
    category             text,
    description          text,
    amount               numeric,
    paymentmethod        text,
    supplier             text,
    supplierid           integer,
    suppliername         text,
    amountpaid           numeric,
    balance              numeric,
    paymentstatus        text,
    duedate              date,
    flockid              integer,
    poultrycashaccountid integer,
    sourcetype           text,
    sourceid             integer,
    createddate          timestamp without time zone,
    farmid               uuid,
    userid               text,
    hasattachmentimage   boolean);

-- amountpaid is surfaced RESOLVED (COALESCE'd), so no caller can read the raw
-- NULL and mistake "paid in full" for "paid nothing".
CREATE OR REPLACE FUNCTION public.fnpoultryexpenserows(p_farmid uuid)
RETURNS SETOF public.poultryexpenserow
LANGUAGE sql
STABLE
AS $function$
    SELECT e.expenseid,
           e.expensedate,
           e.category::text,
           e.description::text,
           e.amount::numeric(14,2),
           e.paymentmethod::text,
           e.supplier::text,
           e.supplierid,
           s.name::text,
           COALESCE(e.amountpaid, e.amount)::numeric(14,2),
           GREATEST(COALESCE(e.amount, 0) - COALESCE(e.amountpaid, e.amount), 0)::numeric(14,2),
           e.paymentstatus::text,
           e.duedate,
           e.flockid,
           e.poultrycashaccountid,
           e.sourcetype::text,
           e.sourceid,
           e.createddate,
           e.farmid,
           e.userid::text,
           (e.attachmentimage IS NOT NULL)
    FROM   expense e
    LEFT   JOIN supplier s
           ON  s.supplierid = e.supplierid
           AND lower(s.farmid::text) = lower(e.farmid::text)
    WHERE  e.farmid = p_farmid;
$function$;

CREATE OR REPLACE FUNCTION public.spexpense_getall(p_farmid uuid)
RETURNS SETOF public.poultryexpenserow
LANGUAGE sql
STABLE
AS $function$
    SELECT * FROM fnpoultryexpenserows(p_farmid) ORDER BY createddate DESC, expenseid DESC;
$function$;

CREATE OR REPLACE FUNCTION public.spexpense_getbyid(p_expenseid integer, p_farmid uuid)
RETURNS SETOF public.poultryexpenserow
LANGUAGE sql
STABLE
AS $function$
    SELECT * FROM fnpoultryexpenserows(p_farmid) WHERE expenseid = p_expenseid;
$function$;

CREATE OR REPLACE FUNCTION public.spexpense_getbyflock(p_flockid integer, p_farmid uuid)
RETURNS SETOF public.poultryexpenserow
LANGUAGE sql
STABLE
AS $function$
    SELECT * FROM fnpoultryexpenserows(p_farmid)
    WHERE  flockid = p_flockid
    ORDER  BY createddate DESC, expenseid DESC;
$function$;

-- Writes. The parameter list is a strict superset of what ExpenseService sends
-- today (016/132 order preserved, new arguments appended with defaults), so the
-- existing named-argument calls keep binding even before the C# is updated.
CREATE OR REPLACE FUNCTION public.spexpense_insert(
    p_expensedate           timestamp without time zone,
    p_category              text,
    p_description           text,
    p_amount                numeric,
    p_paymentmethod         text,
    p_supplier              text,
    p_flockid               integer,
    p_userid                text,
    p_farmid                uuid,
    p_attachmentimage       bytea   DEFAULT NULL,
    p_attachmentcontenttype text    DEFAULT NULL,
    p_supplierid            integer DEFAULT NULL,
    p_amountpaid            numeric DEFAULT NULL,
    p_duedate               date    DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id   integer;
    v_paid numeric(14,2) := p_amountpaid;
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than 0.';
    END IF;
    IF v_paid IS NOT NULL THEN
        IF v_paid < 0 THEN
            RAISE EXCEPTION 'Amount paid cannot be negative.';
        END IF;
        IF v_paid > p_amount THEN
            RAISE EXCEPTION 'Amount paid (%) cannot exceed the expense total (%).',
                  v_paid::numeric(14,2), p_amount::numeric(14,2);
        END IF;
        -- Fully paid is stored as NULL, the legacy shape, so a paid expense looks
        -- identical to every row written before this migration.
        IF v_paid >= p_amount THEN v_paid := NULL; END IF;
    END IF;
    IF p_supplierid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM supplier s
                       WHERE s.supplierid = p_supplierid
                         AND lower(s.farmid::text) = lower(p_farmid::text)) THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;

    INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                         supplier, supplierid, amountpaid, duedate, flockid,
                         userid, farmid, attachmentimage, attachmentcontenttype,
                         createddate)
    VALUES (p_expensedate, p_category, p_description, p_amount, p_paymentmethod,
            p_supplier, p_supplierid, v_paid, p_duedate, p_flockid,
            p_userid, p_farmid, p_attachmentimage, p_attachmentcontenttype,
            (now() at time zone 'utc'))
    RETURNING expenseid INTO v_id;

    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spexpense_update(
    p_expenseid             integer,
    p_expensedate           timestamp without time zone,
    p_category              text,
    p_description           text,
    p_amount                numeric,
    p_paymentmethod         text,
    p_supplier              text,
    p_flockid               integer,
    p_userid                text,
    p_farmid                uuid,
    p_attachmentimageset    boolean DEFAULT false,
    p_attachmentimage       bytea   DEFAULT NULL,
    p_attachmentcontenttype text    DEFAULT NULL,
    p_supplierid            integer DEFAULT NULL,
    p_amountpaid            numeric DEFAULT NULL,
    p_duedate               date    DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_alloc numeric(14,2);
    v_paid  numeric(14,2) := p_amountpaid;
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than 0.';
    END IF;

    -- What supplier payments have already settled against this expense. Editing
    -- the row must never contradict money that has actually moved -- the balance
    -- on screen and fnbalanceaudit would disagree from that moment on.
    SELECT COALESCE(SUM(sa.amountapplied), 0) INTO v_alloc
    FROM   supplierpaymentallocation sa
    WHERE  lower(sa.farmid) = lower(p_farmid::text) AND sa.module = 'poultry'
      AND  sa.status = 'Posted' AND sa.documenttype = 'Expense'
      AND  sa.documentid = p_expenseid;

    IF p_amount < v_alloc THEN
        RAISE EXCEPTION 'Supplier payments totalling % have been applied to this expense, so its total cannot be reduced to %.',
              v_alloc, p_amount::numeric(14,2);
    END IF;
    IF v_paid IS NOT NULL THEN
        IF v_paid < 0 THEN
            RAISE EXCEPTION 'Amount paid cannot be negative.';
        END IF;
        IF v_paid > p_amount THEN
            RAISE EXCEPTION 'Amount paid (%) cannot exceed the expense total (%).',
                  v_paid::numeric(14,2), p_amount::numeric(14,2);
        END IF;
        IF v_paid < v_alloc THEN
            RAISE EXCEPTION 'Supplier payments totalling % have been applied to this expense, so amount paid cannot be set to %.',
                  v_alloc, v_paid;
        END IF;
        IF v_paid >= p_amount THEN v_paid := NULL; END IF;
    END IF;
    IF p_supplierid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM supplier s
                       WHERE s.supplierid = p_supplierid
                         AND lower(s.farmid::text) = lower(p_farmid::text)) THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;

    UPDATE expense e
    SET    expensedate   = p_expensedate,
           category      = p_category,
           description   = p_description,
           amount        = p_amount,
           paymentmethod = p_paymentmethod,
           supplier      = p_supplier,
           supplierid    = p_supplierid,
           amountpaid    = v_paid,
           duedate       = p_duedate,
           flockid       = p_flockid,
           attachmentimage = CASE WHEN p_attachmentimageset THEN p_attachmentimage
                                  ELSE e.attachmentimage END,
           attachmentcontenttype = CASE WHEN p_attachmentimageset THEN p_attachmentcontenttype
                                        ELSE e.attachmentcontenttype END
    WHERE  e.expenseid = p_expenseid AND e.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Expense cash, narrowed to what allocations have not covered.
-- -----------------------------------------------------------------------------
-- Split in two. The resync is the whole behaviour and takes no account argument,
-- so a supplier payment can re-run it without disturbing which account the
-- expense is filed under. The sync keeps ExpenseService's existing six-argument
-- contract (it sets the account, then resyncs), so no C# change is required for
-- this part to be correct.
--
-- Dropped by name for the same reason as the CRUD functions: the live body is not
-- in this repo and 229:26 says the T-SQL in 132 has diverged from it.
DO $dropcash$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure::text AS sig
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public' AND p.proname = 'sppoultryexpensecash_sync'
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
        RAISE NOTICE '238: dropped %', r.sig;
    END LOOP;
END
$dropcash$;

CREATE OR REPLACE FUNCTION public.sppoultryexpensecash_resync(
    p_farmid text, p_expenseid integer, p_createdby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_acct   integer;
    v_amt    numeric(14,2);
    v_alloc  numeric(14,2);
    v_method text;
    v_desc   text;
    v_bal    numeric(14,2);
BEGIN
    -- Reverse any existing expense cash tx (restore balances, then delete them).
    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - t.net, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT ct.poultrycashaccountid, SUM(ct.amount) AS net
        FROM   poultrycashtransactions ct
        WHERE  ct.sourcetype = 'Expense' AND ct.sourceid = p_expenseid AND ct.farmid = p_farmid
        GROUP  BY ct.poultrycashaccountid
    ) t
    WHERE  t.poultrycashaccountid = a.poultrycashaccountid
      AND  a.farmid = p_farmid;

    DELETE FROM poultrycashtransactions ct
    WHERE  ct.sourcetype = 'Expense' AND ct.sourceid = p_expenseid AND ct.farmid = p_farmid;

    SELECT e.poultrycashaccountid,
           COALESCE(e.amountpaid, e.amount),
           e.paymentmethod,
           COALESCE(NULLIF(btrim(e.description), ''), e.category)
    INTO   v_acct, v_amt, v_method, v_desc
    FROM   expense e
    WHERE  e.expenseid = p_expenseid AND lower(e.farmid::text) = lower(p_farmid)
    LIMIT  1;

    -- Money a supplier payment already took out of a (possibly different) cash
    -- account. Posting it again here would double-count it.
    SELECT COALESCE(SUM(sa.amountapplied), 0) INTO v_alloc
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.status = 'Posted'
      AND  sa.documenttype = 'Expense' AND sa.documentid = p_expenseid;

    v_amt := GREATEST(COALESCE(v_amt, 0) - COALESCE(v_alloc, 0), 0);

    -- Internal use records stock leaving with no money moving (216). It must not
    -- reach a cash account even if one was somehow filed against it.
    IF COALESCE(v_method, '') = 'NonCash' THEN
        v_amt := 0;
    END IF;

    IF (v_acct IS NOT NULL AND v_amt > 0
        AND EXISTS (SELECT 1 FROM poultrycashaccounts a
                    WHERE a.poultrycashaccountid = v_acct AND a.farmid = p_farmid)) THEN

        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance - v_amt, updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = v_acct AND a.farmid = p_farmid;

        SELECT a.currentbalance INTO v_bal
        FROM   poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct LIMIT 1;

        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_acct, (now() at time zone 'utc'), 'CashOut', 'Expense', p_expenseid,
             -v_amt, v_bal, COALESCE(v_desc, 'Expense'), p_createdby, p_createdby,
             (now() at time zone 'utc'));
    END IF;
END;
$function$;

-- Signature preserved for ExpenseService.SyncExpenseCashAsync. p_amount and
-- p_description are now advisory only: the amount that moves is the expense's own
-- resolved amountpaid, which is the one number that cannot go stale. Callers that
-- pass a NULL account (delete) still get reverse-only behaviour.
CREATE OR REPLACE FUNCTION public.sppoultryexpensecash_sync(
    p_farmid text,
    p_expenseid integer,
    p_poultrycashaccountid integer DEFAULT NULL::integer,
    p_amount numeric DEFAULT 0,
    p_description text DEFAULT NULL::text,
    p_createdby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_gid uuid;
BEGIN
    -- expense.farmid is uuid while the cash tables are text; guarded exactly the
    -- way every other expense-writing SP guards it (224:407).
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;

    IF v_gid IS NOT NULL THEN
        UPDATE expense e SET poultrycashaccountid = p_poultrycashaccountid
        WHERE  e.expenseid = p_expenseid AND e.farmid = v_gid;
    END IF;

    PERFORM sppoultryexpensecash_resync(p_farmid, p_expenseid, p_createdby);
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Expenses become the third payable.
-- -----------------------------------------------------------------------------
-- 224:717 called this shot: "adding a third payable table later is a change in
-- exactly one place." It is. Everything downstream -- the balances rollup, open
-- items, the summary tiles and the statement -- reads this function and inherits
-- expenses without being touched.
--
-- Only expenses that name a supplier are payables. One with no supplierid can be
-- unpaid perfectly well, it just has nobody to owe, and putting it on Supplier
-- Balances would invent a creditor. NonCash is excluded outright (216).
--
-- duedate joins the shape because an expense carries a real one, entered by hand,
-- which should beat the supplier's default terms. Purchases have none and fall
-- back to docdate + paymenttermsdays exactly as before.
DROP FUNCTION IF EXISTS public.fnpoultrypayables(text);

CREATE OR REPLACE FUNCTION public.fnpoultrypayables(p_farmid text)
RETURNS TABLE(
    documenttype  text,
    documentid    integer,
    supplierid    integer,
    docdate       date,
    label         text,
    reference     text,
    totalcost     numeric,
    amountpaid    numeric,
    balance       numeric,
    cashaccountid integer,
    duedate       date)
LANGUAGE sql
STABLE
AS $function$
    SELECT 'RawMaterialPurchase'::text, pu.poultryrawmaterialpurchaseid, pu.supplierid,
           pu.purchasedate::date, COALESCE(i.itemname, 'Raw material')::text,
           ('P' || pu.poultryrawmaterialpurchaseid::text)::text,
           pu.totalcost, pu.amountpaid,
           GREATEST(pu.totalcost - pu.amountpaid, 0)::numeric(14,2),
           pu.poultrycashaccountid,
           NULL::date
    FROM   poultryrawmaterialpurchases pu
    LEFT   JOIN poultryrawmaterialitems i
           ON i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
    WHERE  pu.farmid = p_farmid
    UNION ALL
    SELECT 'FlockBatch'::text, b.batchid, b.supplierid,
           b.startdate::date, COALESCE(b.batchname, 'Flock batch')::text,
           COALESCE(NULLIF(btrim(b.batchcode), ''), 'B' || b.batchid::text)::text,
           b.totalcost, b.amountpaid,
           GREATEST(b.totalcost - b.amountpaid, 0)::numeric(14,2),
           NULL::integer,
           NULL::date
    FROM   mainflockbatch b
    WHERE  b.farmid = p_farmid
    UNION ALL
    SELECT 'Expense'::text, e.expenseid, e.supplierid,
           e.expensedate::date,
           COALESCE(NULLIF(btrim(e.description), ''), e.category)::text,
           ('E' || e.expenseid::text)::text,
           COALESCE(e.amount, 0)::numeric(14,2),
           COALESCE(e.amountpaid, e.amount)::numeric(14,2),
           GREATEST(COALESCE(e.amount, 0) - COALESCE(e.amountpaid, e.amount), 0)::numeric(14,2),
           e.poultrycashaccountid,
           e.duedate
    FROM   expense e
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  e.supplierid IS NOT NULL
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash';
$function$;

-- An expense's own due date wins where it has one; everything else keeps the
-- derived supplier-terms date. Return shapes are unchanged, so these are plain
-- replacements.
CREATE OR REPLACE FUNCTION public.sppoultrysupplieropenpurchases(
    p_farmid text,
    p_supplierid integer,
    p_from date DEFAULT NULL::date,
    p_to date DEFAULT NULL::date,
    p_status text DEFAULT 'All'::text)
RETURNS TABLE(
    documenttype  text,
    documentid    integer,
    reference     text,
    docdate       date,
    label         text,
    totalcost     numeric,
    amountpaid    numeric,
    balance       numeric,
    duedate       date,
    agedays       integer,
    status        text,
    isoverdue     boolean,
    cashaccountid integer)
LANGUAGE sql
STABLE
AS $function$
    SELECT d.documenttype, d.documentid, d.reference, d.docdate, d.label,
           d.totalcost, d.amountpaid, d.balance,
           COALESCE(d.duedate, (d.docdate + COALESCE(s.paymenttermsdays, 0)))::date,
           GREATEST((CURRENT_DATE - d.docdate), 0)::integer,
           CASE WHEN d.amountpaid > 0 THEN 'Partially Paid' ELSE 'Unpaid' END::text,
           (COALESCE(d.duedate, (d.docdate + COALESCE(s.paymenttermsdays, 0))) < CURRENT_DATE),
           d.cashaccountid
    FROM   fnpoultrypayables(p_farmid) d
    JOIN   supplier s ON s.supplierid = d.supplierid AND s.farmid = p_farmid
    WHERE  d.supplierid = p_supplierid
      AND  d.balance > 0
      AND  (p_from IS NULL OR d.docdate >= p_from)
      AND  (p_to   IS NULL OR d.docdate <= p_to)
      AND  CASE COALESCE(p_status, 'All')
                WHEN 'Partial' THEN d.amountpaid > 0
                WHEN 'Unpaid'  THEN d.amountpaid = 0
                WHEN 'Overdue' THEN COALESCE(d.duedate, (d.docdate + COALESCE(s.paymenttermsdays, 0))) < CURRENT_DATE
                ELSE TRUE
           END
    ORDER  BY d.docdate, d.documenttype, d.documentid;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrysupplierbalances(
    p_farmid text,
    p_from date DEFAULT NULL::date,
    p_to date DEFAULT NULL::date,
    p_supplierid integer DEFAULT NULL::integer,
    p_status text DEFAULT 'All'::text,
    p_minbalance numeric DEFAULT NULL::numeric,
    p_search text DEFAULT NULL::text)
RETURNS TABLE(
    supplierid        integer,
    suppliername      text,
    contactphone      text,
    contactemail      text,
    paymenttermsdays  integer,
    totalbalance      numeric,
    openpurchasecount integer,
    oldestpurchasedate date,
    latestpurchasedate date,
    lastpaymentdate   timestamp without time zone,
    overdueamount     numeric,
    totalpurchases    numeric,
    totalpaid         numeric)
LANGUAGE sql
STABLE
AS $function$
    WITH openpurchases AS (
        SELECT d.*, COALESCE(s.paymenttermsdays, 0) AS terms
        FROM   fnpoultrypayables(p_farmid) d
        JOIN   supplier s ON s.supplierid = d.supplierid AND s.farmid = p_farmid
        WHERE  d.supplierid IS NOT NULL
          AND  (p_supplierid IS NULL OR d.supplierid = p_supplierid)
          AND  (p_from IS NULL OR d.docdate >= p_from)
          AND  (p_to   IS NULL OR d.docdate <= p_to)
          AND  d.balance > 0
    ),
    filtered AS (
        SELECT o.*,
               (COALESCE(o.duedate, (o.docdate + o.terms)) < CURRENT_DATE) AS isoverdue
        FROM   openpurchases o
        WHERE  CASE COALESCE(p_status, 'All')
                    WHEN 'Partial' THEN o.amountpaid > 0
                    WHEN 'Unpaid'  THEN o.amountpaid = 0
                    WHEN 'Overdue' THEN COALESCE(o.duedate, (o.docdate + o.terms)) < CURRENT_DATE
                    ELSE TRUE
               END
    )
    SELECT s.supplierid,
           s.name::text,
           s.contactphone::text,
           s.contactemail::text,
           COALESCE(s.paymenttermsdays, 0),
           SUM(f.balance)::numeric(14,2),
           COUNT(*)::integer,
           MIN(f.docdate),
           MAX(f.docdate),
           (SELECT MAX(sp.paymentdate) FROM poultrysupplierpayments sp
            WHERE sp.farmid = p_farmid AND sp.supplierid = s.supplierid
              AND sp.status = 'Posted'),
           SUM(CASE WHEN f.isoverdue THEN f.balance ELSE 0 END)::numeric(14,2),
           SUM(f.totalcost)::numeric(14,2),
           SUM(f.amountpaid)::numeric(14,2)
    FROM   filtered f
    JOIN   supplier s ON s.supplierid = f.supplierid AND s.farmid = p_farmid
    WHERE  (p_search IS NULL OR btrim(p_search) = ''
            OR s.name ILIKE '%' || btrim(p_search) || '%'
            OR COALESCE(s.contactphone, '') ILIKE '%' || btrim(p_search) || '%')
    GROUP  BY s.supplierid, s.name, s.contactphone, s.contactemail, s.paymenttermsdays
    HAVING (p_minbalance IS NULL OR SUM(f.balance) >= p_minbalance)
    ORDER  BY SUM(f.balance) DESC;
$function$;

-- The statement gains expenses for free, but it should not call them "Purchase".
-- Everything else about it is unchanged.
CREATE OR REPLACE FUNCTION public.sppoultrysupplierstatement(
    p_farmid text, p_supplierid integer,
    p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
RETURNS TABLE(
    entrydate      date,
    entrytype      text,
    reference      text,
    description    text,
    credit         numeric,
    debit          numeric,
    runningbalance numeric,
    documenttype   text,
    documentid     integer,
    sortkey        integer)
LANGUAGE sql
STABLE
AS $function$
    WITH lines AS (
        SELECT CASE WHEN p_from IS NULL THEN NULL::date ELSE p_from END AS entrydate,
               'OpeningBalance'::text  AS entrytype,
               NULL::text              AS reference,
               'Opening balance'::text AS description,
               CASE WHEN p_from IS NULL THEN 0::numeric(14,2) ELSE COALESCE((
                   SELECT SUM(d.balance) FROM fnpoultrypayables(p_farmid) d
                   WHERE  d.supplierid = p_supplierid AND d.docdate < p_from), 0)::numeric(14,2) END
                                       AS credit,
               0::numeric(14,2)        AS debit,
               NULL::text              AS documenttype,
               NULL::integer           AS documentid,
               0 AS sortkey, 0 AS pin

        UNION ALL

        -- What we were billed.
        SELECT d.docdate,
               CASE WHEN d.documenttype = 'Expense' THEN 'Expense' ELSE 'Purchase' END::text,
               d.reference, d.label,
               d.totalcost::numeric(14,2), 0::numeric(14,2),
               d.documenttype, d.documentid, 1, 1
        FROM   fnpoultrypayables(p_farmid) d
        WHERE  d.supplierid = p_supplierid
          AND  (p_from IS NULL OR d.docdate >= p_from)
          AND  (p_to   IS NULL OR d.docdate <= p_to)

        UNION ALL

        -- Paid at the counter: amountpaid with no allocation behind it.
        SELECT d.docdate, 'Payment'::text, d.reference,
               CASE WHEN d.documenttype = 'Expense'
                    THEN 'Paid when recorded'
                    ELSE 'Paid at time of purchase' END::text,
               0::numeric(14,2),
               GREATEST(d.amountpaid - COALESCE((
                   SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                   WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.status = 'Posted'
                     AND  sa.documenttype = d.documenttype AND sa.documentid = d.documentid), 0),
                   0)::numeric(14,2),
               d.documenttype, d.documentid, 2, 1
        FROM   fnpoultrypayables(p_farmid) d
        WHERE  d.supplierid = p_supplierid
          AND  (p_from IS NULL OR d.docdate >= p_from)
          AND  (p_to   IS NULL OR d.docdate <= p_to)
          AND  d.amountpaid > COALESCE((
                   SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                   WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.status = 'Posted'
                     AND  sa.documenttype = d.documenttype AND sa.documentid = d.documentid), 0)

        UNION ALL

        SELECT sp.paymentdate::date, 'Payment'::text,
               COALESCE(NULLIF(btrim(sp.referenceno), ''), 'SP' || sp.poultrysupplierpaymentid::text)::text,
               ('Payment made' ||
                COALESCE(' (' || NULLIF(btrim(sp.paymentmethod), '') || ')', ''))::text,
               0::numeric(14,2), sp.totalamount::numeric(14,2),
               NULL::text, NULL::integer, 2, 1
        FROM   poultrysupplierpayments sp
        WHERE  sp.farmid = p_farmid AND sp.supplierid = p_supplierid
          AND  sp.status = 'Posted'
          AND  (p_from IS NULL OR sp.paymentdate::date >= p_from)
          AND  (p_to   IS NULL OR sp.paymentdate::date <= p_to)
    )
    SELECT l.entrydate, l.entrytype, l.reference, l.description, l.credit, l.debit,
           SUM(l.credit - l.debit) OVER (
               ORDER BY l.pin, l.entrydate, l.sortkey, l.documentid NULLS FIRST
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::numeric(14,2),
           l.documenttype, l.documentid, l.sortkey
    FROM   lines l
    WHERE  l.entrytype <> 'OpeningBalance' OR l.credit <> 0
    ORDER  BY l.pin, l.entrydate, l.sortkey, l.documentid NULLS FIRST;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Recording a payment against an expense.
-- -----------------------------------------------------------------------------
-- Three changes from 224, and nothing else:
--
--   a. 'Expense' joins the accepted document types.
--   b. The inline two-table union is replaced by fnpoultrypayables(), which is
--      now the single definition of what a payable is. 224 could not call it --
--      it is declared further down the same file -- so it hand-rolled the union.
--      Keeping both would mean adding every future payable type twice.
--   c. THE EXPENSE ROW IS BOOKED ONLY FOR THE TWO PURCHASE TYPES. A purchase is
--      not itself an expense, so 224 books one per allocation to get the cost
--      into the P&L (migration 207's invariant, and its comment is emphatic about
--      why skipping it is a regression). An expense already IS the cost. Booking
--      a second one would double-count it -- the exact error this work exists to
--      prevent -- and would also make the new row a payable in its own right.
--
-- Everything else is byte-for-byte 224: same validation, same order, same
-- overdraft guard, same single CashOut for the whole payment.
CREATE OR REPLACE FUNCTION public.sppoultrysupplierpayment_record(
    p_farmid text,
    p_supplierid integer,
    p_amount numeric,
    p_allocations jsonb,
    p_paymentmethod text DEFAULT NULL::text,
    p_paymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone,
    p_cashaccountid integer DEFAULT NULL::integer,
    p_reference text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text,
    p_sourcetype text DEFAULT 'SupplierBalances'::text,
    p_createdby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_paymentid integer;
    v_date      timestamp := COALESCE(p_paymentdate, (now() at time zone 'utc'));
    v_allocated numeric(14,2);
    v_count     integer;
    v_distinct  integer;
    v_minamount numeric(14,2);
    v_missing   integer;
    v_row       record;
    v_before    numeric(14,2);
    v_gid       uuid;
    v_allowneg  boolean;
    v_curbal    numeric(14,2);
    v_name      text;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than 0.';
    END IF;
    -- A NULL supplier is allowed (see the table comment) but a WRONG one is not.
    IF p_supplierid IS NOT NULL THEN
        SELECT s.name INTO v_name FROM supplier s
        WHERE  s.supplierid = p_supplierid AND s.farmid = p_farmid LIMIT 1;
        IF v_name IS NULL THEN
            RAISE EXCEPTION 'Supplier does not belong to this company.';
        END IF;
    END IF;

    IF p_cashaccountid IS NOT NULL THEN
        SELECT a.allownegativebalance, a.currentbalance INTO v_allowneg, v_curbal
        FROM   poultrycashaccounts a
        WHERE  a.poultrycashaccountid = p_cashaccountid AND a.farmid = p_farmid LIMIT 1;
        IF v_allowneg IS NULL THEN
            RAISE EXCEPTION 'Cash account does not belong to this company.';
        END IF;
        IF NOT v_allowneg AND (v_curbal - p_amount) < 0 THEN
            RAISE EXCEPTION 'This payment would overdraw the cash account (balance %, payment %).',
                  v_curbal, p_amount::numeric(14,2);
        END IF;
    END IF;

    SELECT COUNT(*), COUNT(DISTINCT (a.documenttype, a.documentid)),
           COALESCE(SUM(a.amount), 0), COALESCE(MIN(a.amount), 0)
    INTO   v_count, v_distinct, v_allocated, v_minamount
    FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
           AS a(documenttype text, documentid integer, amount numeric)
    WHERE  a.documentid IS NOT NULL AND COALESCE(a.amount, 0) <> 0;

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Select at least one item to apply this payment to.';
    END IF;
    IF v_distinct <> v_count THEN
        RAISE EXCEPTION 'The same item appears more than once in this payment.';
    END IF;
    IF v_minamount <= 0 THEN
        RAISE EXCEPTION 'Each allocation must be greater than 0.';
    END IF;
    IF v_allocated::numeric(14,2) <> p_amount::numeric(14,2) THEN
        RAISE EXCEPTION 'Allocated total (%) must equal the payment amount (%).',
              v_allocated::numeric(14,2), p_amount::numeric(14,2);
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
               AS a(documenttype text, documentid integer, amount numeric)
               WHERE COALESCE(a.documenttype, '') NOT IN ('RawMaterialPurchase', 'FlockBatch', 'Expense')) THEN
        RAISE EXCEPTION 'Unknown document type. Expected RawMaterialPurchase, FlockBatch or Expense.';
    END IF;

    INSERT INTO poultrysupplierpayments
        (farmid, supplierid, paymentdate, totalamount, paymentmethod, poultrycashaccountid,
         referenceno, notes, sourcetype, status, createdby, createdat)
    VALUES
        (p_farmid, p_supplierid, v_date, p_amount, p_paymentmethod, p_cashaccountid,
         p_reference, p_notes, COALESCE(p_sourcetype, 'SupplierBalances'), 'Posted',
         p_createdby, (now() at time zone 'utc'))
    RETURNING poultrysupplierpaymentid INTO v_paymentid;

    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;

    FOR v_row IN
        SELECT a.documenttype, a.documentid, a.amount::numeric(14,2) AS amount,
               d.totalcost, d.amountpaid, d.balance, d.docdate, d.label, d.cashaccountid
        FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
               AS a(documenttype text, documentid integer, amount numeric)
        JOIN   fnpoultrypayables(p_farmid) d
               ON d.documenttype = a.documenttype AND d.documentid = a.documentid
        WHERE  a.documentid IS NOT NULL AND COALESCE(a.amount, 0) <> 0
          -- IS NOT DISTINCT FROM so a no-supplier payment matches a no-supplier
          -- document; a plain = would silently drop every one of them.
          AND  d.supplierid IS NOT DISTINCT FROM p_supplierid
        ORDER  BY d.docdate, d.documentid
    LOOP
        v_before := GREATEST(COALESCE(v_row.balance, 0), 0);

        IF v_before <= 0 THEN
            RAISE EXCEPTION '% #% is already fully paid.',
                  v_row.documenttype, v_row.documentid;
        END IF;
        IF v_row.amount > v_before THEN
            RAISE EXCEPTION 'Cannot apply % to % #% -- its balance is only %.',
                  v_row.amount, v_row.documenttype, v_row.documentid, v_before;
        END IF;

        IF v_row.documenttype = 'RawMaterialPurchase' THEN
            UPDATE poultryrawmaterialpurchases pu
            SET    amountpaid = pu.amountpaid + v_row.amount,
                   updatedat = (now() at time zone 'utc')
            WHERE  pu.poultryrawmaterialpurchaseid = v_row.documentid AND pu.farmid = p_farmid;
        ELSIF v_row.documenttype = 'FlockBatch' THEN
            UPDATE mainflockbatch b
            SET    amountpaid = b.amountpaid + v_row.amount
            WHERE  b.batchid = v_row.documentid AND b.farmid = p_farmid;
        ELSE
            -- amountpaid is NULL on a fully paid expense, so resolve before adding
            -- or the sum restarts from zero and the row goes backwards.
            UPDATE expense e
            SET    amountpaid = LEAST(COALESCE(e.amountpaid, e.amount) + v_row.amount, e.amount)
            WHERE  e.expenseid = v_row.documentid
              AND  lower(e.farmid::text) = lower(p_farmid);
        END IF;

        INSERT INTO supplierpaymentallocation
            (farmid, module, paymentid, documenttype, documentid, amountapplied,
             documentbalancebefore, documentbalanceafter, status, createdby, createdat)
        VALUES
            (p_farmid, 'poultry', v_paymentid, v_row.documenttype, v_row.documentid, v_row.amount,
             v_before, v_before - v_row.amount, 'Posted', p_createdby, v_date);

        -- Keep migration 207's invariant: a purchase's linked expense rows sum to
        -- its amountpaid. Guarded exactly the way the pay-balance functions guard
        -- it, so a farm whose id will not cast to uuid still gets its payment.
        --
        -- Expenses are excluded: the expense being paid IS the cost, already in
        -- the P&L since the day it was entered. See the header.
        IF (v_row.documenttype IN ('RawMaterialPurchase', 'FlockBatch')
            AND v_gid IS NOT NULL AND p_createdby IS NOT NULL) THEN
            INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                                 supplier, flockid, createddate, userid, farmid, sourcetype, sourceid)
            VALUES (v_date,
                    CASE WHEN v_row.documenttype = 'FlockBatch'
                         THEN 'Flock / Bird Purchase'
                         ELSE 'Raw Materials / Inventory Purchase' END,
                    'Supplier payment #' || v_paymentid::text || ' against ' ||
                        v_row.documenttype || ' #' || v_row.documentid::text || ': ' || v_row.label,
                    v_row.amount, COALESCE(p_paymentmethod, 'Cash'), v_name, NULL,
                    (now() at time zone 'utc'), p_createdby, v_gid,
                    CASE WHEN v_row.documenttype = 'FlockBatch'
                         THEN 'MainFlockBatch' ELSE 'PoultryRawMaterialPurchase' END,
                    v_row.documentid);
        END IF;

        -- Re-sync the document's own cash line. It now excludes what this
        -- allocation covered, so this call REMOVES that portion from the
        -- document's account -- the payment's single CashOut below is where the
        -- money actually leaves.
        IF v_row.documenttype = 'RawMaterialPurchase' THEN
            PERFORM sppoultryrawmaterialpurchasecash_sync(
                p_farmid, v_row.documentid, v_row.cashaccountid, FALSE, p_createdby);
        ELSIF v_row.documenttype = 'Expense' THEN
            PERFORM sppoultryexpensecash_resync(p_farmid, v_row.documentid, p_createdby);
        END IF;
    END LOOP;

    -- Every id must have matched a document belonging to this supplier.
    SELECT v_count - COUNT(*) INTO v_missing
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.paymentid = v_paymentid;
    IF v_missing <> 0 THEN
        RAISE EXCEPTION '% of the selected items do not belong to this supplier or company.',
              v_missing;
    END IF;

    PERFORM sppoultrysupplierpaymentcash_sync(p_farmid, v_paymentid, p_createdby);

    RETURN v_paymentid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Reversal, with expenses restored too.
-- -----------------------------------------------------------------------------
-- The expense-row DELETE is deliberately left scoped to the two purchase
-- sourcetypes. A paid expense never had a second expense booked against it, so
-- there is nothing to remove -- and the LIKE it matches on would not find one
-- anyway. Deleting the payable itself would destroy the bill.
CREATE OR REPLACE FUNCTION public.sppoultrysupplierpayment_reverse(
    p_farmid text, p_paymentid integer,
    p_reason text DEFAULT NULL::text, p_reversedby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_now    timestamp := (now() at time zone 'utc');
    v_status text;
    v_row    record;
    v_count  integer := 0;
BEGIN
    SELECT sp.status INTO v_status FROM poultrysupplierpayments sp
    WHERE  sp.poultrysupplierpaymentid = p_paymentid AND sp.farmid = p_farmid LIMIT 1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payment not found for this company.';
    END IF;
    IF v_status <> 'Posted' THEN
        RAISE EXCEPTION 'This payment has already been reversed.';
    END IF;

    FOR v_row IN
        SELECT sa.documenttype, sa.documentid, sa.amountapplied
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = 'poultry'
          AND  sa.paymentid = p_paymentid AND sa.status = 'Posted'
    LOOP
        IF v_row.documenttype = 'RawMaterialPurchase' THEN
            UPDATE poultryrawmaterialpurchases pu
            SET    amountpaid = GREATEST(pu.amountpaid - v_row.amountapplied, 0),
                   updatedat = (now() at time zone 'utc')
            WHERE  pu.poultryrawmaterialpurchaseid = v_row.documentid AND pu.farmid = p_farmid;
        ELSIF v_row.documenttype = 'FlockBatch' THEN
            UPDATE mainflockbatch b
            SET    amountpaid = GREATEST(b.amountpaid - v_row.amountapplied, 0)
            WHERE  b.batchid = v_row.documentid AND b.farmid = p_farmid;
        ELSE
            UPDATE expense e
            SET    amountpaid = GREATEST(COALESCE(e.amountpaid, e.amount) - v_row.amountapplied, 0)
            WHERE  e.expenseid = v_row.documentid
              AND  lower(e.farmid::text) = lower(p_farmid);
        END IF;
        v_count := v_count + 1;
    END LOOP;

    -- Drop the expense rows this payment booked. 207 is explicit that a negative
    -- expense row would corrupt every SUM(amount) report, and `expense` has no
    -- status column to mark instead -- so the audit trail lives on the payment
    -- header and in the allocation rows, both of which are kept.
    DELETE FROM expense e
    WHERE  e.sourcetype IN ('PoultryRawMaterialPurchase', 'MainFlockBatch')
      AND  e.description LIKE 'Supplier payment #' || p_paymentid::text || ' against %';

    UPDATE supplierpaymentallocation sa
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason
    WHERE  sa.farmid = p_farmid AND sa.module = 'poultry'
      AND  sa.paymentid = p_paymentid AND sa.status = 'Posted';

    UPDATE poultrysupplierpayments sp
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason
    WHERE  sp.poultrysupplierpaymentid = p_paymentid AND sp.farmid = p_farmid;

    -- Allocations are Reversed now, so every sync recomputes without them: the
    -- payment's CashOut disappears and each document reclaims its own line.
    PERFORM sppoultrysupplierpaymentcash_sync(p_farmid, p_paymentid, p_reversedby);

    FOR v_row IN
        SELECT DISTINCT sa.documentid, sa.documenttype
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.paymentid = p_paymentid
          AND  sa.documenttype IN ('RawMaterialPurchase', 'Expense')
    LOOP
        IF v_row.documenttype = 'RawMaterialPurchase' THEN
            PERFORM sppoultryrawmaterialpurchasecash_sync(
                p_farmid, v_row.documentid, NULL, FALSE, p_reversedby);
        ELSE
            PERFORM sppoultryexpensecash_resync(p_farmid, v_row.documentid, p_reversedby);
        END IF;
    END LOOP;

    RETURN v_count;
END;
$function$;


-- -----------------------------------------------------------------------------
-- 7. The audit sees expenses too.
-- -----------------------------------------------------------------------------
-- fnbalanceaudit is the invariant the whole allocation layer is judged by: it
-- returns NOTHING when healthy, and a row the moment a document's amountpaid
-- stops agreeing with the allocations behind it. Adding a third payable without
-- adding it here would give expenses an unwatched corner.
--
-- Same test as the two purchase arms, for the same reason: an expense can be
-- part-paid at entry, before any payment record exists, so allocations must
-- never EXCEED what was paid but are not expected to equal it.
--
-- The first two arms are unchanged from 222.
CREATE OR REPLACE FUNCTION public.fnbalanceaudit(p_farmid text, p_module text DEFAULT 'poultry')
RETURNS TABLE (
    side          text,
    documenttype  text,
    documentid    integer,
    amountpaid    numeric,
    allocated     numeric,
    difference    numeric
)
LANGUAGE sql
STABLE
AS $function$
    SELECT 'customer'::text, 'Sale'::text, s.saleid,
           s.amountpaid,
           COALESCE(a.allocated, 0),
           s.amountpaid - COALESCE(a.allocated, 0)
    FROM   sale s
    LEFT   JOIN (
        SELECT c.saleid, SUM(c.amountapplied) AS allocated
        FROM   customerpaymentallocation c
        WHERE  c.farmid = p_farmid AND c.module = p_module AND c.status = 'Posted'
        GROUP  BY c.saleid
    ) a ON a.saleid = s.saleid
    WHERE  p_module = 'poultry'
      AND  s.farmid = p_farmid
      AND  s.amountpaid <> COALESCE(a.allocated, 0)

    UNION ALL

    SELECT 'supplier'::text, 'RawMaterialPurchase'::text, pu.poultryrawmaterialpurchaseid,
           pu.amountpaid,
           COALESCE(a.allocated, 0),
           pu.amountpaid - COALESCE(a.allocated, 0)
    FROM   poultryrawmaterialpurchases pu
    LEFT   JOIN (
        SELECT sa.documentid, SUM(sa.amountapplied) AS allocated
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = p_module
          AND  sa.status = 'Posted' AND sa.documenttype = 'RawMaterialPurchase'
        GROUP  BY sa.documentid
    ) a ON a.documentid = pu.poultryrawmaterialpurchaseid
    WHERE  p_module = 'poultry'
      AND  pu.farmid = p_farmid
      AND  COALESCE(a.allocated, 0) > pu.amountpaid

    UNION ALL

    SELECT 'supplier'::text, 'FlockBatch'::text, b.batchid,
           b.amountpaid,
           COALESCE(a.allocated, 0),
           b.amountpaid - COALESCE(a.allocated, 0)
    FROM   mainflockbatch b
    LEFT   JOIN (
        SELECT sa.documentid, SUM(sa.amountapplied) AS allocated
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = p_module
          AND  sa.status = 'Posted' AND sa.documenttype = 'FlockBatch'
        GROUP  BY sa.documentid
    ) a ON a.documentid = b.batchid
    WHERE  p_module = 'poultry'
      AND  b.farmid = p_farmid
      AND  COALESCE(a.allocated, 0) > b.amountpaid

    UNION ALL

    -- Expenses (238). amountpaid is read RESOLVED -- a NULL means paid in full,
    -- and comparing allocations against a bare NULL would return NULL and hide
    -- every discrepancy rather than report it.
    SELECT 'supplier'::text, 'Expense'::text, e.expenseid,
           COALESCE(e.amountpaid, e.amount),
           COALESCE(a.allocated, 0),
           COALESCE(e.amountpaid, e.amount) - COALESCE(a.allocated, 0)
    FROM   expense e
    LEFT   JOIN (
        SELECT sa.documentid, SUM(sa.amountapplied) AS allocated
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = p_module
          AND  sa.status = 'Posted' AND sa.documenttype = 'Expense'
        GROUP  BY sa.documentid
    ) a ON a.documentid = e.expenseid
    WHERE  p_module = 'poultry'
      AND  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(a.allocated, 0) > COALESCE(e.amountpaid, e.amount);
$function$;

-- -----------------------------------------------------------------------------
-- 8. Permission catalog.
-- -----------------------------------------------------------------------------
-- Alongside the poultry.supplier-* keys 222 seeded. Paying an expense is the same
-- act as paying a purchase, so it reuses supplier-payments.create; what is new is
-- being allowed to see an individual bill's payment history.
INSERT INTO iampermissions
    (permissionkey, module, resource, action, permissiongroup, resourcelabel,
     description, companytype, isdangerous, sortorder)
SELECT v.permissionkey, v.module, v.resource, v.action, v.permissiongroup,
       v.resourcelabel, v.description, v.companytype, v.isdangerous, v.sortorder
FROM  (VALUES
    ('poultry.expense-payments.create', 'poultry', 'expense-payments', 'create', 'Expenses',
     'Expense payments', 'Record a payment against an unpaid or part-paid expense', 'Poultry', false, 64),
    ('poultry.expense-payment-history.view', 'poultry', 'expense-payment-history', 'view', 'Expenses',
     'Expense payment history', 'See which supplier payments settled an expense', 'Poultry', false, 65)
) AS v(permissionkey, module, resource, action, permissiongroup, resourcelabel,
       description, companytype, isdangerous, sortorder)
WHERE NOT EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = v.permissionkey);

COMMIT;

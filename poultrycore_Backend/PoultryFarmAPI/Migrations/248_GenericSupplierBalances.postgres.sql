-- =============================================================================
-- 248_GenericSupplierBalances.postgres.sql
--
-- Purpose
-- -------
-- Give the Generic company a payables side: what it owes suppliers, on which
-- bills, and a way to pay them that writes back to the documents being settled.
--
-- This is the supplier twin of 244, and it closes the same gap. 244's header
-- said the Generic customer allocation migration "was never written"; the
-- supplier one was never written either. genericsupplierpayments has
-- linkedpurchaseid and linkedexpenseid columns that _insert writes and NOTHING
-- reads, so today an approved supplier payment moves the supplier's
-- currentbalance and the cash account while every purchase it was meant to
-- settle still shows its original balance.
--
-- Where Generic DIFFERS from poultry and water, and why it matters
-- ---------------------------------------------------------------
--
-- 1. genericexpenses HAS NO PAYMENT COLUMNS AT ALL. No amountpaid, no balance,
--    no paymentstatus, no duedate -- which is exactly why the Generic side was
--    deferred when 238 and 240 were written. Section 1 adds them in the shape
--    238 proved: amountpaid NULLABLE, where NULL means "paid in full", so there
--    is no backfill and every row written by an SP that has never heard of this
--    column keeps its meaning.
--
-- 2. genericpurchases ALREADY carries amountpaid, balance and paymentstatus, so
--    the purchase arm needs no schema change -- only surfacing. There are two
--    open purchases totalling 1,032.00 on dev today. After this migration they
--    APPEAR on Supplier Balances. That figure is not new debt and nothing about
--    it changes; it is an existing balance that finally has a page.
--
-- 3. PAYING A BILL BOOKS NO EXPENSE ROW. Poultry books one per allocation
--    because a raw-material purchase is not itself a cost (207's invariant).
--    Generic purchases do not work that way -- genericexpenses is empty while
--    two purchases exist, so a purchase has never produced an expense row and
--    its cost reaches the books by another route. An expense, meanwhile, IS
--    already the cost. So neither arm books anything: a payment moves money,
--    not cost.
--
-- 4. SYSTEM-GENERATED EXPENSES ARE NEVER PAYABLE. Same trap 240 section 2
--    describes: a row with a sourcetype is the shadow of another document, and
--    that other document is the real payable. The expense arm takes
--    sourcetype IS NULL only.
--
-- EFFECT ON TODAY'S NUMBERS: none. genericexpenses is EMPTY (0 rows), so the
-- new columns describe nothing that exists. genericpurchases is read, never
-- rewritten. No cash row, ledger row or balance is altered. The one figure that
-- becomes VISIBLE is the 1,032.00 already sitting in genericpurchases.balance.
--
-- Order: independent of 242-246. Nothing here depends on the subscription work.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Payment columns on genericexpenses.
-- -----------------------------------------------------------------------------
-- The 238 shape, for the reasons 238 gives. amountpaid is nullable and NULL
-- means paid in full, which is what every row written before today already
-- means, so there is no backfill UPDATE anywhere in this file. Read it as
-- COALESCE(amountpaid, amount), never bare.
ALTER TABLE genericexpenses ADD COLUMN IF NOT EXISTS amountpaid numeric(14,2) NULL;
ALTER TABLE genericexpenses ADD COLUMN IF NOT EXISTS duedate date NULL;

COMMENT ON COLUMN genericexpenses.amountpaid IS
    'Cash actually paid against this expense. NULL means paid in full -- the '
    'meaning every row written before migration 248 carries, and every row '
    'written by an SP that does not know this column exists. Read it as '
    'COALESCE(amountpaid, amount), never bare.';

-- Generated, so it can never disagree with the amounts it comes from. A dozen
-- SPs insert into genericexpenses and none of them will be taught about payment
-- state; a computed column makes all of them correct without touching a line.
DO $genstatus$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'genericexpenses' AND column_name = 'paymentstatus') THEN
        ALTER TABLE genericexpenses ADD COLUMN paymentstatus text
            GENERATED ALWAYS AS (
                CASE WHEN COALESCE(paymentmethod, '') = 'NonCash' THEN 'NonCash'
                     WHEN COALESCE(amountpaid, amount) >= COALESCE(amount, 0) THEN 'Paid'
                     WHEN COALESCE(amountpaid, amount) <= 0 THEN 'Unpaid'
                     ELSE 'PartiallyPaid'
                END) STORED;
        RAISE NOTICE '248: added generated column genericexpenses.paymentstatus';
    END IF;
END
$genstatus$;

-- Partial: the payables read only ever wants rows that still owe something.
CREATE INDEX IF NOT EXISTS ix_genericexpenses_farm_supplier
    ON genericexpenses (farmid, genericsupplierid)
    WHERE genericsupplierid IS NOT NULL AND amountpaid IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 2. Reversal and reference columns on genericsupplierpayments.
-- -----------------------------------------------------------------------------
-- Reversal is append-only: the payment and its allocations are marked Reversed
-- and every row is KEPT, so the history stays readable. Same as 244.
ALTER TABLE genericsupplierpayments ADD COLUMN IF NOT EXISTS referenceno text NULL;
ALTER TABLE genericsupplierpayments ADD COLUMN IF NOT EXISTS sourcetype text NULL;
ALTER TABLE genericsupplierpayments ADD COLUMN IF NOT EXISTS reversedby text NULL;
ALTER TABLE genericsupplierpayments ADD COLUMN IF NOT EXISTS reversedat timestamp NULL;
ALTER TABLE genericsupplierpayments ADD COLUMN IF NOT EXISTS reversalreason text NULL;

-- -----------------------------------------------------------------------------
-- 3. The payables union.
-- -----------------------------------------------------------------------------
-- One function, two arms, and everything downstream -- the balances rollup, open
-- bills, the summary tiles, the statement and the audit -- reads THIS rather
-- than the tables, so a third payable later is a change in one place. That is
-- the shape 224:717 called and 238 proved.
--
-- Only bills that name a supplier. One with no supplier can be unpaid perfectly
-- well; it simply has nobody to owe, and putting it here would invent a creditor.
CREATE OR REPLACE FUNCTION public.fngenericpayables(p_farmid text)
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
    -- Purchases already carry amountpaid/balance, so this arm is pure reading.
    SELECT 'Purchase'::text, p.genericpurchaseid, p.genericsupplierid,
           p.purchasedate::date,
           COALESCE(NULLIF(btrim(p.notes), ''), 'Purchase')::text,
           ('P' || p.genericpurchaseid::text)::text,
           COALESCE(p.totalamount, 0)::numeric(14,2),
           COALESCE(p.amountpaid, 0)::numeric(14,2),
           GREATEST(COALESCE(p.totalamount, 0) - COALESCE(p.amountpaid, 0), 0)::numeric(14,2),
           p.genericcashaccountid,
           NULL::date            -- purchases carry no due date of their own
    FROM   genericpurchases p
    WHERE  p.farmid = p_farmid
      AND  COALESCE(p.isdeleted, FALSE) = FALSE
      AND  p.genericsupplierid IS NOT NULL
      AND  COALESCE(p.status, '') <> 'Cancelled'

    UNION ALL

    -- Expenses (248). amountpaid is read RESOLVED -- NULL means paid in full.
    SELECT 'Expense'::text, e.genericexpenseid, e.genericsupplierid,
           e.expensedate::date,
           COALESCE(NULLIF(btrim(e.description), ''), 'Expense')::text,
           ('E' || e.genericexpenseid::text)::text,
           COALESCE(e.amount, 0)::numeric(14,2),
           COALESCE(e.amountpaid, e.amount)::numeric(14,2),
           GREATEST(COALESCE(e.amount, 0) - COALESCE(e.amountpaid, e.amount), 0)::numeric(14,2),
           e.genericcashaccountid,
           e.duedate
    FROM   genericexpenses e
    WHERE  e.farmid = p_farmid
      AND  COALESCE(e.isdeleted, FALSE) = FALSE
      AND  e.genericsupplierid IS NOT NULL
      -- A row with a sourcetype is another document's shadow, and that document
      -- is the real payable. Above all it is how a supplier payment's own
      -- expense row would otherwise become a debt to the supplier just paid.
      AND  e.sourcetype IS NULL
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
      AND  COALESCE(e.status, '') <> 'Cancelled';
$function$;

-- -----------------------------------------------------------------------------
-- 4. The reads.
-- -----------------------------------------------------------------------------
-- Column names deliberately match the API's own DTOs (partyid, documenttype,
-- balancebefore, ...) so the C# mapping stays thin, exactly as 244 did.
CREATE OR REPLACE FUNCTION public.spgenericsupplierbalances(
    p_farmid     text,
    p_from       date    DEFAULT NULL::date,
    p_to         date    DEFAULT NULL::date,
    p_supplierid integer DEFAULT NULL::integer,
    p_status     text    DEFAULT 'All'::text,
    p_minbalance numeric DEFAULT NULL::numeric,
    p_search     text    DEFAULT NULL::text)
RETURNS TABLE(
    partyid            integer,
    partyname          text,
    contactphone       text,
    contactemail       text,
    paymenttermsdays   integer,
    totalbalance       numeric,
    opendocumentcount  integer,
    oldestdocumentdate date,
    latestdocumentdate date,
    lastpaymentdate    timestamp without time zone,
    overdueamount      numeric,
    totalinvoiced      numeric,
    totalpaid          numeric)
LANGUAGE sql
STABLE
AS $function$
    WITH d AS (
        SELECT p.*,
               COALESCE(p.duedate, p.docdate + COALESCE(s.paymenttermsdays, 0)) AS effectivedue
        FROM   fngenericpayables(p_farmid) p
        JOIN   genericsuppliers s ON s.genericsupplierid = p.supplierid
        WHERE  (p_from IS NULL OR p.docdate >= p_from)
          AND  (p_to   IS NULL OR p.docdate <= p_to)
          AND  (p_supplierid IS NULL OR p.supplierid = p_supplierid)
    )
    SELECT s.genericsupplierid, s.suppliername::text, s.phonenumber::text, s.email::text,
           COALESCE(s.paymenttermsdays, 0),
           ROUND(COALESCE(SUM(d.balance) FILTER (WHERE d.balance > 0), 0), 2),
           COUNT(*) FILTER (WHERE d.balance > 0)::integer,
           MIN(d.docdate) FILTER (WHERE d.balance > 0),
           MAX(d.docdate) FILTER (WHERE d.balance > 0),
           (SELECT MAX(sp.paymentdate) FROM genericsupplierpayments sp
             WHERE sp.farmid = p_farmid AND sp.genericsupplierid = s.genericsupplierid
               AND COALESCE(sp.status, '') <> 'Reversed'),
           ROUND(COALESCE(SUM(d.balance) FILTER (
                     WHERE d.balance > 0 AND d.effectivedue < CURRENT_DATE), 0), 2),
           ROUND(COALESCE(SUM(d.totalcost), 0), 2),
           ROUND(COALESCE(SUM(d.amountpaid), 0), 2)
    FROM   genericsuppliers s
    JOIN   d ON d.supplierid = s.genericsupplierid
    WHERE  s.farmid = p_farmid
      AND  COALESCE(s.isdeleted, FALSE) = FALSE
      AND  (p_search IS NULL OR btrim(p_search) = ''
            OR s.suppliername ILIKE '%' || btrim(p_search) || '%'
            OR COALESCE(s.phonenumber, '') ILIKE '%' || btrim(p_search) || '%')
    GROUP  BY s.genericsupplierid, s.suppliername, s.phonenumber, s.email, s.paymenttermsdays
    HAVING COALESCE(SUM(d.balance) FILTER (WHERE d.balance > 0), 0) > 0
       AND (p_minbalance IS NULL
            OR COALESCE(SUM(d.balance) FILTER (WHERE d.balance > 0), 0) >= p_minbalance)
       AND (COALESCE(p_status, 'All') = 'All'
            OR (p_status = 'Overdue' AND COALESCE(SUM(d.balance) FILTER (
                    WHERE d.balance > 0 AND d.effectivedue < CURRENT_DATE), 0) > 0)
            OR (p_status = 'Unpaid'  AND COUNT(*) FILTER (WHERE d.amountpaid <= 0 AND d.balance > 0) > 0)
            OR (p_status = 'Partial' AND COUNT(*) FILTER (WHERE d.amountpaid > 0 AND d.balance > 0) > 0))
    ORDER  BY 6 DESC;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericsupplieropenbills(
    p_farmid     text,
    p_supplierid integer,
    p_from       date DEFAULT NULL::date,
    p_to         date DEFAULT NULL::date,
    p_status     text DEFAULT 'All'::text)
RETURNS TABLE(
    documenttype  text,
    documentid    integer,
    reference     text,
    documentdate  date,
    label         text,
    totalamount   numeric,
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
           COALESCE(d.duedate, d.docdate + COALESCE(s.paymenttermsdays, 0)),
           GREATEST(0, (CURRENT_DATE - d.docdate))::int,
           (CASE WHEN d.amountpaid <= 0 THEN 'Unpaid' ELSE 'Partially Paid' END)::text,
           COALESCE(d.duedate, d.docdate + COALESCE(s.paymenttermsdays, 0)) < CURRENT_DATE,
           d.cashaccountid
    FROM   fngenericpayables(p_farmid) d
    JOIN   genericsuppliers s ON s.genericsupplierid = d.supplierid AND s.farmid = p_farmid
    WHERE  d.supplierid = p_supplierid
      AND  d.balance > 0
      AND  (p_from IS NULL OR d.docdate >= p_from)
      AND  (p_to   IS NULL OR d.docdate <= p_to)
      AND  (COALESCE(p_status, 'All') = 'All'
            OR (p_status = 'Unpaid'  AND d.amountpaid <= 0)
            OR (p_status = 'Partial' AND d.amountpaid > 0)
            OR (p_status = 'Overdue'
                AND COALESCE(d.duedate, d.docdate + COALESCE(s.paymenttermsdays, 0)) < CURRENT_DATE))
    ORDER  BY d.docdate, d.documenttype, d.documentid;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericsupplierbalancesummary(p_farmid text)
RETURNS TABLE(
    totalbalance        numeric,
    partycount          integer,
    overduebalance      numeric,
    paymentstoday       numeric,
    largestbalance      numeric,
    largestbalanceparty text)
LANGUAGE sql
STABLE
AS $function$
    WITH b AS (SELECT * FROM spgenericsupplierbalances(p_farmid))
    SELECT ROUND(COALESCE(SUM(b.totalbalance), 0), 2),
           COUNT(*)::integer,
           ROUND(COALESCE(SUM(b.overdueamount), 0), 2),
           ROUND(COALESCE((SELECT SUM(sp.amount) FROM genericsupplierpayments sp
                            WHERE sp.farmid = p_farmid
                              AND sp.paymentdate::date = CURRENT_DATE
                              AND COALESCE(sp.status, '') <> 'Reversed'), 0), 2),
           ROUND(COALESCE(MAX(b.totalbalance), 0), 2),
           (SELECT b2.partyname FROM b b2 ORDER BY b2.totalbalance DESC LIMIT 1)
    FROM   b;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericsupplierstatement(
    p_farmid     text,
    p_supplierid integer,
    p_from       date DEFAULT NULL::date,
    p_to         date DEFAULT NULL::date)
RETURNS TABLE(
    entrydate      date,
    entrytype      text,
    reference      text,
    description    text,
    debit          numeric,
    credit         numeric,
    runningbalance numeric,
    documenttype   text,
    documentid     integer,
    sortkey        integer)
LANGUAGE sql
STABLE
AS $function$
    -- The supplier statement is the mirror of the customer one: a bill CREDITS
    -- the supplier (increases what is owed) and a payment DEBITS them. The
    -- running balance is what we still owe.
    WITH ev AS (
        SELECT d.docdate AS entrydate, d.documenttype AS entrytype, d.reference,
               d.label AS description, 0::numeric AS debit, d.totalcost AS credit,
               d.documenttype, d.documentid, 1 AS sortkey
        FROM   fngenericpayables(p_farmid) d
        WHERE  d.supplierid = p_supplierid

        UNION ALL

        SELECT sp.paymentdate::date, 'Payment'::text,
               COALESCE(sp.referenceno, 'PAY-' || sp.genericsupplierpaymentid::text),
               COALESCE(sp.notes, 'Supplier payment')::text,
               sp.amount, 0::numeric,
               'Payment'::text, sp.genericsupplierpaymentid, 2
        FROM   genericsupplierpayments sp
        WHERE  sp.farmid = p_farmid AND sp.genericsupplierid = p_supplierid
          AND  COALESCE(sp.status, '') <> 'Reversed'
    )
    SELECT ev.entrydate, ev.entrytype, ev.reference, ev.description,
           ROUND(ev.debit, 2), ROUND(ev.credit, 2),
           ROUND(SUM(ev.credit - ev.debit) OVER (
                 ORDER BY ev.entrydate, ev.sortkey, ev.documentid
                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2),
           ev.documenttype, ev.documentid, ev.sortkey
    FROM   ev
    WHERE  (p_from IS NULL OR ev.entrydate >= p_from)
      AND  (p_to   IS NULL OR ev.entrydate <= p_to)
    ORDER  BY ev.entrydate, ev.sortkey, ev.documentid;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Recording a payment.
-- -----------------------------------------------------------------------------
-- ONE function call, because one statement is one implicit transaction: the
-- payment either lands completely -- header, allocations, document balances,
-- supplier ledger, supplier balance and cash -- or not at all. Splitting these
-- across round trips from C# is what would let a payment post while its cash
-- posting failed.
--
-- NOTHING books an expense row. See header point 3.
CREATE OR REPLACE FUNCTION public.spgenericsupplierpayment_record(
    p_farmid        text,
    p_supplierid    integer,
    p_amount        numeric,
    p_allocations   jsonb,
    p_paymentmethod text DEFAULT NULL::text,
    p_paymentdate   timestamp DEFAULT NULL::timestamp,
    p_cashaccountid integer DEFAULT NULL::integer,
    p_reference     text DEFAULT NULL::text,
    p_notes         text DEFAULT NULL::text,
    p_sourcetype    text DEFAULT 'SupplierBalances'::text,
    p_createdby     text DEFAULT NULL::text)
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
    v_cashbal   numeric(14,2);
    v_supbal    numeric(14,2);
    v_row       record;
    v_before    numeric(14,2);
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than 0.';
    END IF;
    IF p_supplierid IS NULL THEN
        RAISE EXCEPTION 'A supplier is required to make a payment.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM genericsuppliers s
                   WHERE s.genericsupplierid = p_supplierid AND s.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;

    -- jsonb_to_recordset matches keys CASE-SENSITIVELY against unquoted (so
    -- lower-cased) identifiers. A camelCase key would silently produce NULL
    -- rows -- migration 214 lost a whole entry's lines to exactly that.
    SELECT COALESCE(SUM(a.amount), 0), COUNT(*), COUNT(DISTINCT (a.documenttype, a.documentid)),
           MIN(a.amount)
      INTO v_allocated, v_count, v_distinct, v_minamount
    FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
           AS a(documenttype text, documentid integer, amount numeric);

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Select at least one bill to apply this payment to.';
    END IF;
    IF v_distinct <> v_count THEN
        RAISE EXCEPTION 'The same bill appears more than once in this payment.';
    END IF;
    IF COALESCE(v_minamount, 0) <= 0 THEN
        RAISE EXCEPTION 'Every allocation must be greater than 0.';
    END IF;
    IF ROUND(v_allocated, 2) <> ROUND(p_amount, 2) THEN
        RAISE EXCEPTION 'Allocated total (%) must equal the payment amount (%).',
              ROUND(v_allocated, 2), ROUND(p_amount, 2);
    END IF;
    IF p_cashaccountid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM genericcashaccounts a
                       WHERE a.genericcashaccountid = p_cashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
    END IF;

    INSERT INTO genericsupplierpayments
        (farmid, genericsupplierid, paymentdate, amount, paymentmethod,
         genericcashaccountid, status, notes, referenceno, sourcetype,
         createdby, approvedby, approvedat, createdat)
    VALUES
        (p_farmid, p_supplierid, v_date, p_amount, COALESCE(p_paymentmethod, 'Cash'),
         p_cashaccountid, 'Approved', p_notes, p_reference, p_sourcetype,
         p_createdby, p_createdby, (now() at time zone 'utc'), (now() at time zone 'utc'))
    RETURNING genericsupplierpaymentid INTO v_paymentid;

    -- Each allocation, oldest first, writing the balance it found and the
    -- balance it left. Snapshotted rather than recomputed later, so the history
    -- still reads correctly after the document changes.
    FOR v_row IN
        SELECT a.documenttype, a.documentid, a.amount, d.balance AS docbalance, d.label
        FROM   jsonb_to_recordset(p_allocations)
               AS a(documenttype text, documentid integer, amount numeric)
        JOIN   fngenericpayables(p_farmid) d
               ON d.documenttype = a.documenttype AND d.documentid = a.documentid
        WHERE  d.supplierid = p_supplierid
        ORDER  BY d.docdate, a.documentid
    LOOP
        IF v_row.amount > v_row.docbalance + 0.005 THEN
            RAISE EXCEPTION 'Cannot apply % to % -- its balance is only %.',
                  ROUND(v_row.amount, 2), v_row.label, ROUND(v_row.docbalance, 2);
        END IF;

        v_before := v_row.docbalance;

        IF v_row.documenttype = 'Purchase' THEN
            UPDATE genericpurchases
            SET    amountpaid    = LEAST(COALESCE(amountpaid, 0) + v_row.amount, totalamount),
                   balance       = GREATEST(totalamount - (COALESCE(amountpaid, 0) + v_row.amount), 0),
                   paymentstatus = CASE
                       WHEN COALESCE(amountpaid, 0) + v_row.amount >= totalamount THEN 'Paid'
                       ELSE 'PartiallyPaid' END,
                   updatedat     = (now() at time zone 'utc')
            WHERE  genericpurchaseid = v_row.documentid AND farmid = p_farmid;
        ELSIF v_row.documenttype = 'Expense' THEN
            -- Resolved read: NULL amountpaid means paid in full, so a row that
            -- reaches here (balance > 0) has an explicit number already.
            UPDATE genericexpenses
            SET    amountpaid = LEAST(COALESCE(amountpaid, amount) + v_row.amount, amount),
                   updatedat  = (now() at time zone 'utc')
            WHERE  genericexpenseid = v_row.documentid AND farmid = p_farmid;
        ELSE
            RAISE EXCEPTION 'Unknown payable type "%".', v_row.documenttype;
        END IF;

        INSERT INTO supplierpaymentallocation
            (farmid, module, paymentid, documenttype, documentid, amountapplied,
             documentbalancebefore, documentbalanceafter, status, createdby, createdat)
        VALUES
            (p_farmid, 'generic', v_paymentid, v_row.documenttype, v_row.documentid,
             v_row.amount, v_before, v_before - v_row.amount, 'Posted', p_createdby, v_date);
    END LOOP;

    -- Every id must have matched a document belonging to this supplier.
    SELECT v_count - COUNT(*) INTO v_missing
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'generic' AND sa.paymentid = v_paymentid;
    IF v_missing <> 0 THEN
        RAISE EXCEPTION '% of the selected bills do not belong to this supplier or company.', v_missing;
    END IF;

    -- Supplier ledger + running balance. A payment DEBITS the supplier.
    SELECT COALESCE(currentbalance, 0) INTO v_supbal
    FROM   genericsuppliers WHERE genericsupplierid = p_supplierid AND farmid = p_farmid;

    INSERT INTO genericsupplierledger
        (farmid, genericsupplierid, transactiondate, transactiontype, paymentid,
         debitamount, creditamount, balanceaftertransaction, description, createdby)
    VALUES
        (p_farmid, p_supplierid, v_date, 'PaymentDebit', v_paymentid,
         p_amount, 0, GREATEST(v_supbal - p_amount, 0),
         COALESCE(p_notes, 'Supplier payment'), p_createdby);

    UPDATE genericsuppliers
    SET    currentbalance = GREATEST(COALESCE(currentbalance, 0) - p_amount, 0),
           updatedat      = (now() at time zone 'utc')
    WHERE  genericsupplierid = p_supplierid AND farmid = p_farmid;

    -- ONE cash movement for the whole payment, never one per allocation.
    IF p_cashaccountid IS NOT NULL THEN
        SELECT COALESCE(currentbalance, 0) INTO v_cashbal
        FROM   genericcashaccounts
        WHERE  genericcashaccountid = p_cashaccountid AND farmid = p_farmid;

        INSERT INTO genericcashtransactions
            (farmid, genericcashaccountid, transactiondate, transactiontype,
             sourcetype, sourceid, amount, balanceaftertransaction, description,
             createdby, approvedby, approvedat)
        VALUES
            (p_farmid, p_cashaccountid, v_date, 'CashOut', 'SupplierPayment', v_paymentid,
             -p_amount, v_cashbal - p_amount, COALESCE(p_notes, 'Supplier payment'),
             p_createdby, p_createdby, (now() at time zone 'utc'));

        UPDATE genericcashaccounts
        SET    currentbalance = v_cashbal - p_amount, updatedat = (now() at time zone 'utc')
        WHERE  genericcashaccountid = p_cashaccountid AND farmid = p_farmid;
    END IF;

    RETURN v_paymentid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Reversal.
-- -----------------------------------------------------------------------------
-- Append-only. Nothing is deleted: the payment and its allocations are marked
-- Reversed and every row is kept, so what happened stays readable.
CREATE OR REPLACE FUNCTION public.spgenericsupplierpayment_reverse(
    p_farmid     text,
    p_paymentid  integer,
    p_reason     text DEFAULT NULL::text,
    p_reversedby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_now      timestamp := (now() at time zone 'utc');
    v_status   text;
    v_amount   numeric(14,2);
    v_supplier integer;
    v_account  integer;
    v_cashbal  numeric(14,2);
    v_supbal   numeric(14,2);
    v_count    integer := 0;
    v_row      record;
BEGIN
    SELECT sp.status, sp.amount, sp.genericsupplierid, sp.genericcashaccountid
      INTO v_status, v_amount, v_supplier, v_account
    FROM   genericsupplierpayments sp
    WHERE  sp.genericsupplierpaymentid = p_paymentid AND sp.farmid = p_farmid;

    IF v_amount IS NULL THEN
        RAISE EXCEPTION 'Payment not found for this company.';
    END IF;
    IF COALESCE(v_status, '') = 'Reversed' THEN
        RAISE EXCEPTION 'Only a posted payment can be reversed (this one is Reversed).';
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a payment.';
    END IF;

    FOR v_row IN
        SELECT sa.allocationid, sa.documenttype, sa.documentid, sa.amountapplied
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = 'generic'
          AND  sa.paymentid = p_paymentid AND sa.status = 'Posted'
    LOOP
        IF v_row.documenttype = 'Purchase' THEN
            UPDATE genericpurchases
            SET    amountpaid    = GREATEST(COALESCE(amountpaid, 0) - v_row.amountapplied, 0),
                   balance       = LEAST(totalamount,
                                    totalamount - GREATEST(COALESCE(amountpaid, 0) - v_row.amountapplied, 0)),
                   paymentstatus = CASE
                       WHEN GREATEST(COALESCE(amountpaid, 0) - v_row.amountapplied, 0) <= 0 THEN 'Unpaid'
                       ELSE 'PartiallyPaid' END,
                   updatedat     = v_now
            WHERE  genericpurchaseid = v_row.documentid AND farmid = p_farmid;
        ELSIF v_row.documenttype = 'Expense' THEN
            UPDATE genericexpenses
            SET    amountpaid = GREATEST(COALESCE(amountpaid, amount) - v_row.amountapplied, 0),
                   updatedat  = v_now
            WHERE  genericexpenseid = v_row.documentid AND farmid = p_farmid;
        END IF;

        UPDATE supplierpaymentallocation
        SET    status = 'Reversed'
        WHERE  allocationid = v_row.allocationid;
        v_count := v_count + 1;
    END LOOP;

    -- Give the supplier back what they are owed.
    SELECT COALESCE(currentbalance, 0) INTO v_supbal
    FROM   genericsuppliers WHERE genericsupplierid = v_supplier AND farmid = p_farmid;

    INSERT INTO genericsupplierledger
        (farmid, genericsupplierid, transactiondate, transactiontype, paymentid,
         debitamount, creditamount, balanceaftertransaction, description, createdby)
    VALUES
        (p_farmid, v_supplier, v_now, 'PaymentReversal', p_paymentid,
         0, v_amount, v_supbal + v_amount,
         'Reversal of payment #' || p_paymentid::text || ': ' || p_reason, p_reversedby);

    UPDATE genericsuppliers
    SET    currentbalance = COALESCE(currentbalance, 0) + v_amount, updatedat = v_now
    WHERE  genericsupplierid = v_supplier AND farmid = p_farmid;

    -- Put the cash back.
    IF v_account IS NOT NULL THEN
        SELECT COALESCE(currentbalance, 0) INTO v_cashbal
        FROM   genericcashaccounts
        WHERE  genericcashaccountid = v_account AND farmid = p_farmid;

        INSERT INTO genericcashtransactions
            (farmid, genericcashaccountid, transactiondate, transactiontype,
             sourcetype, sourceid, amount, balanceaftertransaction, description,
             createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_account, v_now, 'CashIn', 'SupplierPayment', p_paymentid,
             v_amount, v_cashbal + v_amount,
             'Reversal of payment #' || p_paymentid::text, p_reversedby, p_reversedby, v_now);

        UPDATE genericcashaccounts
        SET    currentbalance = v_cashbal + v_amount, updatedat = v_now
        WHERE  genericcashaccountid = v_account AND farmid = p_farmid;
    END IF;

    UPDATE genericsupplierpayments
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason, updatedat = v_now
    WHERE  genericsupplierpaymentid = p_paymentid AND farmid = p_farmid;

    RETURN v_count;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. Payment history and allocations.
-- -----------------------------------------------------------------------------
-- genericsupplierpayments.status is Draft|Approved|Cancelled|Reversed while the
-- frontend's PaymentHistoryRow expects Posted|Reversed, so the TRANSLATION
-- happens here rather than the frontend guessing. Same as 244 did.
CREATE OR REPLACE FUNCTION public.spgenericsupplierpayment_history(
    p_farmid       text,
    p_supplierid   integer DEFAULT NULL::integer,
    p_documenttype text    DEFAULT NULL::text,
    p_documentid   integer DEFAULT NULL::integer,
    p_from         date    DEFAULT NULL::date,
    p_to           date    DEFAULT NULL::date)
RETURNS TABLE(
    paymentid       integer,
    partyid         integer,
    partyname       text,
    paymentdate     timestamp without time zone,
    totalamount     numeric,
    paymentmethod   text,
    reference       text,
    notes           text,
    sourcetype      text,
    status          text,
    allocationcount integer,
    cashaccountid   integer,
    createdby       text,
    reversedby      text,
    reversedat      timestamp without time zone,
    reversalreason  text)
LANGUAGE sql
STABLE
AS $function$
    SELECT sp.genericsupplierpaymentid, sp.genericsupplierid, s.suppliername::text,
           sp.paymentdate, sp.amount, sp.paymentmethod::text, sp.referenceno,
           sp.notes::text, sp.sourcetype,
           (CASE WHEN COALESCE(sp.status, '') = 'Reversed' THEN 'Reversed' ELSE 'Posted' END)::text,
           (SELECT COUNT(*)::integer FROM supplierpaymentallocation sa
             WHERE sa.farmid = sp.farmid AND sa.module = 'generic'
               AND sa.paymentid = sp.genericsupplierpaymentid),
           sp.genericcashaccountid, sp.createdby, sp.reversedby, sp.reversedat, sp.reversalreason
    FROM   genericsupplierpayments sp
    LEFT   JOIN genericsuppliers s ON s.genericsupplierid = sp.genericsupplierid
                                  AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  (p_supplierid IS NULL OR sp.genericsupplierid = p_supplierid)
      AND  (p_from IS NULL OR sp.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR sp.paymentdate::date <= p_to)
      AND  (p_documentid IS NULL OR EXISTS (
               SELECT 1 FROM supplierpaymentallocation sa
               WHERE sa.farmid = sp.farmid AND sa.module = 'generic'
                 AND sa.paymentid = sp.genericsupplierpaymentid
                 AND sa.documentid = p_documentid
                 AND (p_documenttype IS NULL OR sa.documenttype = p_documenttype)))
    ORDER  BY sp.paymentdate DESC, sp.genericsupplierpaymentid DESC;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericsupplierpayment_allocations(
    p_farmid text, p_paymentid integer)
RETURNS TABLE(
    allocationid  integer,
    paymentid     integer,
    documenttype  text,
    documentid    integer,
    reference     text,
    documentdate  date,
    label         text,
    documenttotal numeric,
    amountapplied numeric,
    balancebefore numeric,
    balanceafter  numeric,
    status        text)
LANGUAGE sql
STABLE
AS $function$
    SELECT sa.allocationid, sa.paymentid, sa.documenttype, sa.documentid,
           d.reference, d.docdate, d.label, d.totalcost,
           sa.amountapplied, sa.documentbalancebefore, sa.documentbalanceafter, sa.status
    FROM   supplierpaymentallocation sa
    LEFT   JOIN fngenericpayables(p_farmid) d
           ON d.documenttype = sa.documenttype AND d.documentid = sa.documentid
    WHERE  sa.farmid = p_farmid AND sa.module = 'generic' AND sa.paymentid = p_paymentid
    ORDER  BY d.docdate, sa.documenttype, sa.documentid;
$function$;

-- -----------------------------------------------------------------------------
-- 8. The audit sees the supplier side too.
-- -----------------------------------------------------------------------------
-- fngenericbalanceaudit returns NOTHING when healthy. 244 gave it a customer
-- arm; adding a payable side without adding it here would leave suppliers an
-- unwatched corner. The customer arm is reproduced EXACTLY as 244 wrote it.
--
-- All three arms test OVER-allocation rather than inequality: a bill can be
-- part-paid at entry before any payment record exists, so allocations must
-- never EXCEED what was paid but are not expected to equal it.
CREATE OR REPLACE FUNCTION public.fngenericbalanceaudit(p_farmid text)
RETURNS TABLE(
    side         text,
    documenttype text,
    documentid   integer,
    amountpaid   numeric,
    allocated    numeric,
    difference   numeric)
LANGUAGE sql
STABLE
AS $function$
    SELECT 'customer'::text, 'Sale'::text, g.genericsaleid,
           g.amountpaid,
           COALESCE(a.allocated, 0)::numeric(14,2),
           (g.amountpaid - COALESCE(a.allocated, 0))::numeric(14,2)
    FROM   genericsales g
    LEFT   JOIN LATERAL (
               SELECT SUM(ca.amountapplied) AS allocated
               FROM   customerpaymentallocation ca
               WHERE  ca.farmid = g.farmid AND ca.module = 'generic'
                 AND  ca.saleid = g.genericsaleid AND ca.status = 'Posted'
           ) a ON TRUE
    WHERE  g.farmid = p_farmid
      AND  COALESCE(a.allocated, 0) > g.amountpaid

    UNION ALL

    SELECT 'supplier'::text, 'Purchase'::text, p.genericpurchaseid,
           COALESCE(p.amountpaid, 0)::numeric(14,2),
           COALESCE(a.allocated, 0)::numeric(14,2),
           (COALESCE(p.amountpaid, 0) - COALESCE(a.allocated, 0))::numeric(14,2)
    FROM   genericpurchases p
    LEFT   JOIN LATERAL (
               SELECT SUM(sa.amountapplied) AS allocated
               FROM   supplierpaymentallocation sa
               WHERE  sa.farmid = p.farmid AND sa.module = 'generic'
                 AND  sa.documenttype = 'Purchase' AND sa.documentid = p.genericpurchaseid
                 AND  sa.status = 'Posted'
           ) a ON TRUE
    WHERE  p.farmid = p_farmid
      AND  COALESCE(a.allocated, 0) > COALESCE(p.amountpaid, 0)

    UNION ALL

    SELECT 'supplier'::text, 'Expense'::text, e.genericexpenseid,
           COALESCE(e.amountpaid, e.amount)::numeric(14,2),
           COALESCE(a.allocated, 0)::numeric(14,2),
           (COALESCE(e.amountpaid, e.amount) - COALESCE(a.allocated, 0))::numeric(14,2)
    FROM   genericexpenses e
    LEFT   JOIN LATERAL (
               SELECT SUM(sa.amountapplied) AS allocated
               FROM   supplierpaymentallocation sa
               WHERE  sa.farmid = e.farmid AND sa.module = 'generic'
                 AND  sa.documenttype = 'Expense' AND sa.documentid = e.genericexpenseid
                 AND  sa.status = 'Posted'
           ) a ON TRUE
    WHERE  e.farmid = p_farmid
      AND  COALESCE(a.allocated, 0) > COALESCE(e.amountpaid, e.amount);
$function$;

-- -----------------------------------------------------------------------------
-- 9. Permission catalog.
-- -----------------------------------------------------------------------------
-- Catalogued so the keys exist before anything is gated on them. IAM is still
-- in shadow mode; a key with no UI behind it is harmless, a UI with no key is a
-- support ticket waiting to happen (227's rule).
DO $iam$
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '248: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions
        (permissionkey, module, resource, action, permissiongroup, resourcelabel,
         description, companytype, isdangerous, sortorder)
    SELECT v.k, 'generic', v.res, v.act, 'Purchases & Suppliers', v.label,
           v.descr, 'Generic', v.danger, v.sortorder
    FROM (VALUES
        ('generic.supplier-balances.view',    'supplier-balances', 'view',
         'Supplier Balances', 'See who the business owes and the unpaid bills behind each balance.', false, 72),
        ('generic.supplier-payments.create',  'supplier-payments', 'create',
         'Supplier Payments', 'Pay a supplier and apply it to open bills.', false, 73),
        ('generic.supplier-payments.reverse', 'supplier-payments', 'reverse',
         'Supplier Payments', 'Reverse a posted supplier payment.', true, 73),
        ('generic.supplier-statements.view',  'supplier-statements', 'view',
         'Supplier Statements', 'Open a supplier statement.', false, 74)
    ) AS v(k, res, act, label, descr, danger, sortorder)
    WHERE NOT EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = v.k);
END
$iam$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 10. Verification.
-- -----------------------------------------------------------------------------
SELECT 'columns' AS check,
       CASE WHEN COUNT(*) = 8 THEN 'OK' ELSE 'ONLY ' || COUNT(*) END AS result
FROM   information_schema.columns
WHERE  (table_name, column_name) IN (
    ('genericexpenses', 'amountpaid'), ('genericexpenses', 'duedate'),
    ('genericexpenses', 'paymentstatus'),
    ('genericsupplierpayments', 'referenceno'), ('genericsupplierpayments', 'sourcetype'),
    ('genericsupplierpayments', 'reversedby'), ('genericsupplierpayments', 'reversedat'),
    ('genericsupplierpayments', 'reversalreason'));

SELECT 'functions' AS check,
       CASE WHEN COUNT(*) = 9 THEN 'OK' ELSE 'ONLY ' || COUNT(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('fngenericpayables', 'spgenericsupplierbalances',
                     'spgenericsupplieropenbills', 'spgenericsupplierbalancesummary',
                     'spgenericsupplierstatement', 'spgenericsupplierpayment_record',
                     'spgenericsupplierpayment_reverse', 'spgenericsupplierpayment_history',
                     'spgenericsupplierpayment_allocations');

-- NO EXPENSE became a payable: genericexpenses is empty and stays that way.
-- Expect 0.
SELECT 'expenses now payable' AS check, COUNT(*) AS result
FROM   (SELECT DISTINCT farmid FROM genericpurchases) f
CROSS  JOIN LATERAL fngenericpayables(f.farmid) d
WHERE  d.documenttype = 'Expense';

-- What the purchase arm now surfaces. This is EXISTING balance getting a page,
-- not new debt -- it should equal SUM(genericpurchases.balance) for open rows.
SELECT 'purchase payables surfaced' AS check,
       ROUND(COALESCE(SUM(d.balance), 0), 2) AS via_fngenericpayables,
       (SELECT ROUND(COALESCE(SUM(p.balance), 0), 2) FROM genericpurchases p
         WHERE NOT COALESCE(p.isdeleted, FALSE) AND p.genericsupplierid IS NOT NULL
           AND COALESCE(p.status, '') <> 'Cancelled') AS via_table
FROM   (SELECT DISTINCT farmid FROM genericpurchases) f
CROSS  JOIN LATERAL fngenericpayables(f.farmid) d
WHERE  d.documenttype = 'Purchase' AND d.balance > 0;

-- The invariant, per farm. Expect NO ROWS.
SELECT f.farmid, a.*
FROM   (SELECT DISTINCT farmid FROM genericsuppliers) f
CROSS  JOIN LATERAL fngenericbalanceaudit(f.farmid) a;

-- =============================================================================
-- 244_GenericCustomerBalances.postgres.sql
--
-- Purpose
-- -------
-- The migration that migration 222 promised and nobody wrote.
--
-- 222 built the shared allocation spine -- customerpaymentallocation, with a
-- `module` discriminator whose documented values are 'poultry | water | generic'
-- -- and said in its header that Water and Generic "get their own migrations
-- once the poultry side is proven". Poultry got 223/224. Water got 227. Generic
-- got nothing, and 222 named the exact consequence:
--
--     "Generic lets a payment float at the customer level with a linkedsaleid
--      column that is WRITTEN BY _Insert AND READ BY NOTHING AT ALL -- so an
--      approved Generic payment moves currentbalance and cash but leaves every
--      invoice showing its original unpaid balance."
--
-- That is still true today. Recurring billing cannot be built on top of it: you
-- would raise an invoice every month and never be able to say which ones were
-- paid. This file closes it.
--
-- What "balance" means here
-- -------------------------
-- An APPROVED sale with balance > 0. Draft invoices are not receivables -- a
-- generic sale only reaches genericcustomerledger and genericcustomers.
-- currentbalance when it is approved -- so a billing run that raises drafts does
-- not silently inflate what customers owe.
--
-- genericcustomers.currentbalance is left exactly as it is, still maintained by
-- the ledger, because the Customers page and the daily closing both read it.
-- The new balance reads derive from open invoices instead, which is how poultry
-- and water do it, and the two are reconciled by fngenericbalanceaudit.
--
-- EFFECT ON TODAY'S NUMBERS: none. Five nullable columns, new functions, and
-- allocation rows for payments that do not exist yet. The existing
-- _Insert/_Approve/_Cancel path is untouched and keeps working.
--
-- Order: 242, then 243, then 244.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. A payment can carry a reference, a source and a reversal.
-- -----------------------------------------------------------------------------
ALTER TABLE genericcustomerpayments ADD COLUMN IF NOT EXISTS referenceno text NULL;
ALTER TABLE genericcustomerpayments ADD COLUMN IF NOT EXISTS sourcetype text NULL;
ALTER TABLE genericcustomerpayments ADD COLUMN IF NOT EXISTS reversedby text NULL;
ALTER TABLE genericcustomerpayments ADD COLUMN IF NOT EXISTS reversedat timestamp NULL;
ALTER TABLE genericcustomerpayments ADD COLUMN IF NOT EXISTS reversalreason text NULL;

COMMENT ON COLUMN genericcustomerpayments.sourcetype IS
    'Where the payment was taken: InvoiceEntry | CustomerBalances | '
    'SubscriptionPayment | Manual. Recorded so the ledger can say how the money '
    'was collected, not just that it was.';

CREATE INDEX IF NOT EXISTS ix_genericcustomerpayments_farm_customer
    ON genericcustomerpayments (farmid, genericcustomerid)
    WHERE status = 'Approved';

-- -----------------------------------------------------------------------------
-- 2. Record a payment across one or more invoices.
-- -----------------------------------------------------------------------------
-- ONE function call, because one statement is one implicit transaction. The
-- payment, its allocations, every invoice balance, the customer ledger and the
-- cash movement land together or not at all. Splitting them across round trips
-- is how you get a payment with no allocations after a dropped connection.
--
-- p_allocations is a JSON array of {"saleid": <int>, "amount": <numeric>}.
-- LOWER-CASE KEYS: jsonb_to_recordset matches case-sensitively against unquoted
-- (therefore lower-cased) identifiers, and a camelCase key silently produces
-- NULL rows. Migration 214 lost a whole entry's lines to exactly that.
CREATE OR REPLACE FUNCTION public.spgenericcustomerpayment_record(
    p_farmid text,
    p_customerid integer,
    p_amount numeric,
    p_allocations jsonb,
    p_paymentmethod text DEFAULT NULL::text,
    p_paymentdate timestamp DEFAULT NULL::timestamp,
    p_cashaccountid integer DEFAULT NULL::integer,
    p_reference text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text,
    p_sourcetype text DEFAULT 'CustomerBalances'::text,
    p_createdby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_paymentid  integer;
    v_date       timestamp := COALESCE(p_paymentdate, (now() at time zone 'utc'));
    v_allocated  numeric(14,2);
    v_count      integer;
    v_distinct   integer;
    v_minamount  numeric(14,2);
    v_missing    integer;
    v_row        record;
    v_before     numeric(14,2);
    v_custname   text;
    v_custbal    numeric(14,2);
    v_newbal     numeric(14,2);
    v_cashbal    numeric(14,2);
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than 0.';
    END IF;

    SELECT c.customername, c.currentbalance INTO v_custname, v_custbal
    FROM   genericcustomers c
    WHERE  c.genericcustomerid = p_customerid AND c.farmid = p_farmid;
    IF v_custname IS NULL THEN
        RAISE EXCEPTION 'Customer does not belong to this company.';
    END IF;

    IF p_cashaccountid IS NOT NULL THEN
        SELECT a.currentbalance INTO v_cashbal
        FROM   genericcashaccounts a
        WHERE  a.genericcashaccountid = p_cashaccountid AND a.farmid = p_farmid;
        IF v_cashbal IS NULL THEN
            RAISE EXCEPTION 'Cash account does not belong to this company.';
        END IF;
    END IF;

    SELECT COUNT(*), COUNT(DISTINCT a.saleid), COALESCE(SUM(a.amount), 0), COALESCE(MIN(a.amount), 0)
    INTO   v_count, v_distinct, v_allocated, v_minamount
    FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
           AS a(saleid integer, amount numeric)
    WHERE  a.saleid IS NOT NULL AND COALESCE(a.amount, 0) <> 0;

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Select at least one invoice to apply this payment to.';
    END IF;
    IF v_distinct <> v_count THEN
        RAISE EXCEPTION 'The same invoice appears more than once in this payment.';
    END IF;
    IF v_minamount <= 0 THEN
        RAISE EXCEPTION 'Each allocation must be greater than 0.';
    END IF;
    IF v_allocated::numeric(14,2) <> p_amount::numeric(14,2) THEN
        RAISE EXCEPTION 'Allocated total (%) must equal the payment amount (%).',
              v_allocated::numeric(14,2), p_amount::numeric(14,2);
    END IF;

    INSERT INTO genericcustomerpayments
        (farmid, genericcustomerid, paymentdate, amount, paymentmethod,
         genericcashaccountid, referenceno, sourcetype, notes, status,
         createdby, approvedby, approvedat, createdat)
    VALUES
        (p_farmid, p_customerid, v_date, p_amount, p_paymentmethod,
         p_cashaccountid, p_reference, COALESCE(p_sourcetype, 'CustomerBalances'),
         p_notes, 'Approved', p_createdby, p_createdby,
         (now() at time zone 'utc'), (now() at time zone 'utc'))
    RETURNING genericcustomerpaymentid INTO v_paymentid;

    -- Oldest invoice first, so a part payment settles the debt that has been
    -- outstanding longest.
    FOR v_row IN
        SELECT a.saleid, a.amount::numeric(14,2) AS amount,
               g.balance, g.totalamount, g.amountpaid, g.saledate, g.receiptnumber
        FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
               AS a(saleid integer, amount numeric)
        JOIN   genericsales g ON g.genericsaleid = a.saleid AND g.farmid = p_farmid
        WHERE  a.saleid IS NOT NULL AND COALESCE(a.amount, 0) <> 0
          AND  g.genericcustomerid = p_customerid
          AND  g.status = 'Approved'
          AND  COALESCE(g.isdeleted, FALSE) = FALSE
        ORDER  BY g.saledate, g.genericsaleid
    LOOP
        v_before := GREATEST(COALESCE(v_row.balance, 0), 0);

        IF v_before <= 0 THEN
            RAISE EXCEPTION 'Invoice % is already fully paid.',
                  COALESCE(v_row.receiptnumber, v_row.saleid::text);
        END IF;
        IF v_row.amount > v_before THEN
            RAISE EXCEPTION 'Cannot apply % to invoice % -- its balance is only %.',
                  v_row.amount, COALESCE(v_row.receiptnumber, v_row.saleid::text), v_before;
        END IF;

        UPDATE genericsales
        SET    amountpaid    = amountpaid + v_row.amount,
               balance       = GREATEST(balance - v_row.amount, 0),
               paymentstatus = CASE
                                   WHEN balance - v_row.amount <= 0 THEN 'Paid'
                                   ELSE 'PartiallyPaid' END,
               updatedat     = (now() at time zone 'utc')
        WHERE  genericsaleid = v_row.saleid AND farmid = p_farmid;

        INSERT INTO customerpaymentallocation
            (farmid, module, paymentid, saleid, amountapplied,
             salebalancebefore, salebalanceafter, status, createdby, createdat)
        VALUES
            (p_farmid, 'generic', v_paymentid, v_row.saleid, v_row.amount,
             v_before, v_before - v_row.amount, 'Posted', p_createdby, v_date);
    END LOOP;

    -- Every id must have resolved to an APPROVED invoice belonging to this
    -- customer. Anything else and the caller is applying money to a document
    -- that cannot receive it.
    SELECT v_count - COUNT(*) INTO v_missing
    FROM   customerpaymentallocation ca
    WHERE  ca.farmid = p_farmid AND ca.module = 'generic' AND ca.paymentid = v_paymentid;
    IF v_missing <> 0 THEN
        RAISE EXCEPTION '% of the selected invoices are not approved invoices for this customer.', v_missing;
    END IF;

    -- Customer ledger + running balance, matching what _Approve has always done.
    v_newbal := v_custbal - p_amount;

    INSERT INTO genericcustomerledger
        (farmid, genericcustomerid, transactiondate, transactiontype, paymentid,
         debitamount, creditamount, balanceaftertransaction, description, createdby)
    VALUES
        (p_farmid, p_customerid, v_date, 'PaymentCredit', v_paymentid,
         0, p_amount, v_newbal, COALESCE(p_notes, 'Customer payment'), p_createdby);

    UPDATE genericcustomers
    SET    currentbalance = v_newbal, updatedat = (now() at time zone 'utc')
    WHERE  genericcustomerid = p_customerid AND farmid = p_farmid;

    -- One CashIn for the whole payment, never one per allocation.
    IF p_cashaccountid IS NOT NULL THEN
        INSERT INTO genericcashtransactions
            (farmid, genericcashaccountid, transactiondate, transactiontype,
             sourcetype, sourceid, amount, balanceaftertransaction, description,
             createdby, approvedby, approvedat)
        VALUES
            (p_farmid, p_cashaccountid, v_date, 'CashIn', 'CustomerPayment', v_paymentid,
             p_amount, v_cashbal + p_amount, COALESCE(p_notes, 'Customer payment'),
             p_createdby, p_createdby, (now() at time zone 'utc'));

        UPDATE genericcashaccounts
        SET    currentbalance = v_cashbal + p_amount, updatedat = (now() at time zone 'utc')
        WHERE  genericcashaccountid = p_cashaccountid AND farmid = p_farmid;
    END IF;

    RETURN v_paymentid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Reverse a payment.
-- -----------------------------------------------------------------------------
-- Append-only. Nothing is deleted: the payment and its allocations are marked
-- Reversed and a compensating CashOut is written, so the audit trail still shows
-- that the money came in and went back out.
CREATE OR REPLACE FUNCTION public.spgenericcustomerpayment_reverse(
    p_farmid text,
    p_paymentid integer,
    p_reason text DEFAULT NULL::text,
    p_reversedby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_now      timestamp := (now() at time zone 'utc');
    v_status   text;
    v_amount   numeric(14,2);
    v_customer integer;
    v_account  integer;
    v_row      record;
    v_count    integer := 0;
    v_custbal  numeric(14,2);
    v_cashbal  numeric(14,2);
BEGIN
    SELECT p.status, p.amount, p.genericcustomerid, p.genericcashaccountid
    INTO   v_status, v_amount, v_customer, v_account
    FROM   genericcustomerpayments p
    WHERE  p.genericcustomerpaymentid = p_paymentid AND p.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payment not found for this company.';
    END IF;
    IF v_status <> 'Approved' THEN
        RAISE EXCEPTION 'Only a posted payment can be reversed (this one is %).', v_status;
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a payment.';
    END IF;

    FOR v_row IN
        SELECT ca.saleid, ca.amountapplied
        FROM   customerpaymentallocation ca
        WHERE  ca.farmid = p_farmid AND ca.module = 'generic'
          AND  ca.paymentid = p_paymentid AND ca.status = 'Posted'
    LOOP
        UPDATE genericsales
        SET    amountpaid    = GREATEST(amountpaid - v_row.amountapplied, 0),
               balance       = LEAST(balance + v_row.amountapplied, totalamount),
               paymentstatus = CASE
                                   WHEN amountpaid - v_row.amountapplied <= 0 THEN 'Unpaid'
                                   ELSE 'PartiallyPaid' END,
               updatedat     = v_now
        WHERE  genericsaleid = v_row.saleid AND farmid = p_farmid;
        v_count := v_count + 1;
    END LOOP;

    UPDATE customerpaymentallocation
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason
    WHERE  farmid = p_farmid AND module = 'generic'
      AND  paymentid = p_paymentid AND status = 'Posted';

    UPDATE genericcustomerpayments
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason, updatedat = v_now
    WHERE  genericcustomerpaymentid = p_paymentid AND farmid = p_farmid;

    SELECT c.currentbalance INTO v_custbal
    FROM   genericcustomers c WHERE c.genericcustomerid = v_customer AND c.farmid = p_farmid;

    INSERT INTO genericcustomerledger
        (farmid, genericcustomerid, transactiondate, transactiontype, paymentid,
         debitamount, creditamount, balanceaftertransaction, description, createdby)
    VALUES
        (p_farmid, v_customer, v_now, 'AdjustmentDebit', p_paymentid,
         v_amount, 0, v_custbal + v_amount,
         'Reversal of payment #' || p_paymentid::text || ': ' || p_reason, p_reversedby);

    UPDATE genericcustomers
    SET    currentbalance = v_custbal + v_amount, updatedat = v_now
    WHERE  genericcustomerid = v_customer AND farmid = p_farmid;

    IF v_account IS NOT NULL THEN
        SELECT a.currentbalance INTO v_cashbal
        FROM   genericcashaccounts a
        WHERE  a.genericcashaccountid = v_account AND a.farmid = p_farmid;

        INSERT INTO genericcashtransactions
            (farmid, genericcashaccountid, transactiondate, transactiontype,
             sourcetype, sourceid, amount, balanceaftertransaction, description,
             createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_account, v_now, 'CashOut', 'CustomerPayment', p_paymentid,
             -v_amount, v_cashbal - v_amount,
             'Reversal of payment #' || p_paymentid::text, p_reversedby, p_reversedby, v_now);

        UPDATE genericcashaccounts
        SET    currentbalance = v_cashbal - v_amount, updatedat = v_now
        WHERE  genericcashaccountid = v_account AND farmid = p_farmid;
    END IF;

    RETURN v_count;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. The reads.
-- -----------------------------------------------------------------------------
-- One definition of "an open invoice", used by every read below, so the totals
-- on the summary tiles cannot disagree with the rows underneath them.
--
-- Due date is the invoice's own where it has one (a subscription sets its own
-- terms) and otherwise the party default, which is the rule 222:118-131 settled
-- on for poultry and water.
CREATE OR REPLACE FUNCTION public.fngenericopeninvoices(p_farmid text)
RETURNS TABLE(
    genericcustomerid integer,
    documenttype  text,
    documentid    integer,
    reference     text,
    documentdate  date,
    label         text,
    totalamount   numeric,
    amountpaid    numeric,
    balance       numeric,
    duedate       date,
    cashaccountid integer)
LANGUAGE sql
STABLE
AS $function$
    SELECT g.genericcustomerid,
           CASE WHEN g.genericsubscriptionid IS NOT NULL THEN 'Invoice' ELSE 'Sale' END::text,
           g.genericsaleid,
           COALESCE(NULLIF(btrim(g.receiptnumber), ''), 'S' || g.genericsaleid::text)::text,
           g.saledate::date,
           COALESCE(NULLIF(btrim(g.notes), ''), g.salestype, 'Sale')::text,
           g.totalamount, g.amountpaid, GREATEST(g.balance, 0)::numeric(14,2),
           COALESCE(g.duedate, (g.saledate::date + COALESCE(c.paymenttermsdays, 0)))::date,
           g.genericcashaccountid
    FROM   genericsales g
    JOIN   genericcustomers c
           ON c.genericcustomerid = g.genericcustomerid AND c.farmid = g.farmid
    WHERE  g.farmid = p_farmid
      -- Draft invoices are not receivables: a generic sale reaches the customer
      -- ledger only when approved.
      AND  g.status = 'Approved'
      AND  COALESCE(g.isdeleted, FALSE) = FALSE
      AND  g.genericcustomerid IS NOT NULL;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericcustomerbalances(
    p_farmid text,
    p_from date DEFAULT NULL::date,
    p_to date DEFAULT NULL::date,
    p_customerid integer DEFAULT NULL::integer,
    p_status text DEFAULT 'All'::text,
    p_minbalance numeric DEFAULT NULL::numeric,
    p_search text DEFAULT NULL::text)
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
    WITH open AS (
        SELECT d.*, (d.duedate < CURRENT_DATE) AS isoverdue
        FROM   fngenericopeninvoices(p_farmid) d
        WHERE  d.balance > 0
          AND  (p_customerid IS NULL OR d.genericcustomerid = p_customerid)
          AND  (p_from IS NULL OR d.documentdate >= p_from)
          AND  (p_to   IS NULL OR d.documentdate <= p_to)
    ),
    filtered AS (
        SELECT o.* FROM open o
        WHERE  CASE COALESCE(p_status, 'All')
                    WHEN 'Partial' THEN o.amountpaid > 0
                    WHEN 'Unpaid'  THEN o.amountpaid = 0
                    WHEN 'Overdue' THEN o.isoverdue
                    ELSE TRUE
               END
    )
    SELECT c.genericcustomerid,
           c.customername::text,
           c.phonenumber::text,
           c.email::text,
           COALESCE(c.paymenttermsdays, 0),
           SUM(f.balance)::numeric(14,2),
           COUNT(*)::integer,
           MIN(f.documentdate),
           MAX(f.documentdate),
           (SELECT MAX(p.paymentdate) FROM genericcustomerpayments p
            WHERE p.farmid = p_farmid AND p.genericcustomerid = c.genericcustomerid
              AND p.status = 'Approved'),
           SUM(CASE WHEN f.isoverdue THEN f.balance ELSE 0 END)::numeric(14,2),
           SUM(f.totalamount)::numeric(14,2),
           SUM(f.amountpaid)::numeric(14,2)
    FROM   filtered f
    JOIN   genericcustomers c
           ON c.genericcustomerid = f.genericcustomerid AND c.farmid = p_farmid
    WHERE  (p_search IS NULL OR btrim(p_search) = ''
            OR c.customername ILIKE '%' || btrim(p_search) || '%'
            OR COALESCE(c.phonenumber, '') ILIKE '%' || btrim(p_search) || '%')
    GROUP  BY c.genericcustomerid, c.customername, c.phonenumber, c.email, c.paymenttermsdays
    HAVING (p_minbalance IS NULL OR SUM(f.balance) >= p_minbalance)
    ORDER  BY SUM(f.balance) DESC;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericcustomeropeninvoices(
    p_farmid text,
    p_customerid integer,
    p_from date DEFAULT NULL::date,
    p_to date DEFAULT NULL::date,
    p_status text DEFAULT 'All'::text)
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
    SELECT d.documenttype, d.documentid, d.reference, d.documentdate, d.label,
           d.totalamount, d.amountpaid, d.balance, d.duedate,
           GREATEST((CURRENT_DATE - d.documentdate), 0)::integer,
           CASE WHEN d.amountpaid > 0 THEN 'Partially Paid' ELSE 'Unpaid' END::text,
           (d.duedate < CURRENT_DATE),
           d.cashaccountid
    FROM   fngenericopeninvoices(p_farmid) d
    WHERE  d.genericcustomerid = p_customerid
      AND  d.balance > 0
      AND  (p_from IS NULL OR d.documentdate >= p_from)
      AND  (p_to   IS NULL OR d.documentdate <= p_to)
      AND  CASE COALESCE(p_status, 'All')
                WHEN 'Partial' THEN d.amountpaid > 0
                WHEN 'Unpaid'  THEN d.amountpaid = 0
                WHEN 'Overdue' THEN d.duedate < CURRENT_DATE
                ELSE TRUE
           END
    ORDER  BY d.documentdate, d.documentid;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericcustomerbalancesummary(p_farmid text)
RETURNS TABLE(
    totalbalance       numeric,
    partycount         integer,
    overduebalance     numeric,
    paymentstoday      numeric,
    largestbalance     numeric,
    largestbalanceparty text)
LANGUAGE sql
STABLE
AS $function$
    WITH b AS (SELECT * FROM spgenericcustomerbalances(p_farmid))
    SELECT COALESCE(SUM(b.totalbalance), 0)::numeric(14,2),
           COUNT(*)::integer,
           COALESCE(SUM(b.overdueamount), 0)::numeric(14,2),
           COALESCE((SELECT SUM(p.amount) FROM genericcustomerpayments p
                     WHERE p.farmid = p_farmid AND p.status = 'Approved'
                       AND p.paymentdate::date = CURRENT_DATE), 0)::numeric(14,2),
           COALESCE(MAX(b.totalbalance), 0)::numeric(14,2),
           (SELECT b2.partyname FROM b b2 ORDER BY b2.totalbalance DESC LIMIT 1)
    FROM b;
$function$;

-- The statement. An invoice increases what is owed; a payment reduces it.
CREATE OR REPLACE FUNCTION public.spgenericcustomerstatement(
    p_farmid text, p_customerid integer,
    p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
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
    WITH lines AS (
        SELECT CASE WHEN p_from IS NULL THEN NULL::date ELSE p_from END AS entrydate,
               'OpeningBalance'::text  AS entrytype,
               NULL::text              AS reference,
               'Opening balance'::text AS description,
               CASE WHEN p_from IS NULL THEN 0::numeric(14,2) ELSE COALESCE((
                   SELECT SUM(d.balance) FROM fngenericopeninvoices(p_farmid) d
                   WHERE  d.genericcustomerid = p_customerid AND d.documentdate < p_from), 0)::numeric(14,2) END
                                       AS debit,
               0::numeric(14,2)        AS credit,
               NULL::text              AS documenttype,
               NULL::integer           AS documentid,
               0 AS sortkey, 0 AS pin

        UNION ALL

        SELECT d.documentdate, d.documenttype, d.reference, d.label,
               d.totalamount::numeric(14,2), 0::numeric(14,2),
               d.documenttype, d.documentid, 1, 1
        FROM   fngenericopeninvoices(p_farmid) d
        WHERE  d.genericcustomerid = p_customerid
          AND  (p_from IS NULL OR d.documentdate >= p_from)
          AND  (p_to   IS NULL OR d.documentdate <= p_to)

        UNION ALL

        SELECT p.paymentdate::date, 'Payment'::text,
               COALESCE(NULLIF(btrim(p.referenceno), ''), 'PMT' || p.genericcustomerpaymentid::text)::text,
               ('Payment received' ||
                COALESCE(' (' || NULLIF(btrim(p.paymentmethod), '') || ')', ''))::text,
               0::numeric(14,2), p.amount::numeric(14,2),
               NULL::text, NULL::integer, 2, 1
        FROM   genericcustomerpayments p
        WHERE  p.farmid = p_farmid AND p.genericcustomerid = p_customerid
          AND  p.status = 'Approved'
          AND  (p_from IS NULL OR p.paymentdate::date >= p_from)
          AND  (p_to   IS NULL OR p.paymentdate::date <= p_to)
    ),
    ordered AS (
        SELECT l.*, ROW_NUMBER() OVER (
            ORDER BY l.pin, l.entrydate NULLS FIRST, l.sortkey, l.documentid NULLS FIRST) AS rn
        FROM lines l
    )
    SELECT o.entrydate, o.entrytype, o.reference, o.description, o.debit, o.credit,
           SUM(o.debit - o.credit) OVER (ORDER BY o.rn
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::numeric(14,2),
           o.documenttype, o.documentid, o.sortkey
    FROM   ordered o
    WHERE  o.entrytype <> 'OpeningBalance' OR o.debit <> 0
    ORDER  BY o.rn;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericcustomerpayment_history(
    p_farmid text,
    p_customerid integer DEFAULT NULL::integer,
    p_saleid integer DEFAULT NULL::integer,
    p_from date DEFAULT NULL::date,
    p_to date DEFAULT NULL::date)
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
    SELECT p.genericcustomerpaymentid, p.genericcustomerid, c.customername::text,
           p.paymentdate, p.amount, p.paymentmethod::text, p.referenceno,
           p.notes::text, p.sourcetype,
           -- The balances UI speaks Posted/Reversed; generic has always stored
           -- Draft/Approved/Cancelled. Translated here rather than leaving the
           -- frontend to guess.
           CASE p.status WHEN 'Approved' THEN 'Posted'
                         WHEN 'Reversed' THEN 'Reversed'
                         ELSE p.status END::text,
           (SELECT COUNT(*)::integer FROM customerpaymentallocation ca
            WHERE ca.farmid = p_farmid AND ca.module = 'generic'
              AND ca.paymentid = p.genericcustomerpaymentid),
           p.genericcashaccountid, p.createdby::text,
           p.reversedby, p.reversedat, p.reversalreason
    FROM   genericcustomerpayments p
    LEFT   JOIN genericcustomers c ON c.genericcustomerid = p.genericcustomerid
    WHERE  p.farmid = p_farmid
      AND  p.status IN ('Approved', 'Reversed')
      AND  (p_customerid IS NULL OR p.genericcustomerid = p_customerid)
      AND  (p_from IS NULL OR p.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR p.paymentdate::date <= p_to)
      AND  (p_saleid IS NULL OR EXISTS (
                SELECT 1 FROM customerpaymentallocation ca
                WHERE ca.farmid = p_farmid AND ca.module = 'generic'
                  AND ca.paymentid = p.genericcustomerpaymentid AND ca.saleid = p_saleid))
    ORDER  BY p.paymentdate DESC, p.genericcustomerpaymentid DESC;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericcustomerpayment_allocations(
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
    SELECT ca.allocationid, ca.paymentid,
           CASE WHEN g.genericsubscriptionid IS NOT NULL THEN 'Invoice' ELSE 'Sale' END::text,
           ca.saleid,
           COALESCE(NULLIF(btrim(g.receiptnumber), ''), 'S' || ca.saleid::text)::text,
           g.saledate::date,
           COALESCE(NULLIF(btrim(g.notes), ''), g.salestype, 'Sale')::text,
           g.totalamount, ca.amountapplied, ca.salebalancebefore, ca.salebalanceafter,
           ca.status
    FROM   customerpaymentallocation ca
    LEFT   JOIN genericsales g ON g.genericsaleid = ca.saleid AND g.farmid = ca.farmid
    WHERE  ca.farmid = p_farmid AND ca.module = 'generic' AND ca.paymentid = p_paymentid
    ORDER  BY ca.allocationid;
$function$;

-- -----------------------------------------------------------------------------
-- 5. The invariant.
-- -----------------------------------------------------------------------------
-- Returns NOTHING when healthy. A row means an invoice's amountpaid no longer
-- agrees with the allocations behind it, and every balance on screen is then
-- untrustworthy. fnbalanceaudit (222) hardcodes poultry and fnwaterbalanceaudit
-- (227) covers water; this is the generic arm.
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
      -- Only flags OVER-allocation. A sale can legitimately be part-paid at the
      -- counter with no payment record behind it, exactly as a purchase can
      -- (222:189) -- so allocations must never exceed amountpaid, but they are
      -- not expected to equal it.
      AND  COALESCE(a.allocated, 0) > g.amountpaid;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 6. Verification.
-- -----------------------------------------------------------------------------
SELECT 'functions' AS check,
       CASE WHEN COUNT(*) = 9 THEN 'OK' ELSE 'ONLY ' || COUNT(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spgenericcustomerpayment_record', 'spgenericcustomerpayment_reverse',
                     'fngenericopeninvoices', 'spgenericcustomerbalances',
                     'spgenericcustomeropeninvoices', 'spgenericcustomerbalancesummary',
                     'spgenericcustomerstatement', 'spgenericcustomerpayment_history',
                     'spgenericcustomerpayment_allocations');

SELECT 'audit fn' AS check,
       CASE WHEN to_regprocedure('public.fngenericbalanceaudit(text)') IS NOT NULL
            THEN 'OK' ELSE 'MISSING' END AS result;

-- No generic allocation exists yet, so nothing can be inconsistent.
-- Expect NO ROWS.
SELECT f.farmid, a.*
FROM   (SELECT DISTINCT farmid FROM genericsales) f
CROSS  JOIN LATERAL fngenericbalanceaudit(f.farmid) a;

-- The spine was never wired to generic before this file. Expect 0.
SELECT 'pre-existing generic allocations' AS check, COUNT(*)::text AS result
FROM   customerpaymentallocation WHERE module = 'generic';

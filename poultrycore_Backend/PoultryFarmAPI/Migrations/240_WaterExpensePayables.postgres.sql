-- =============================================================================
-- 240_WaterExpensePayables.postgres.sql
--
-- Purpose
-- -------
-- The water twin of 238: make waterexpenses the second water payable alongside
-- waterrawmaterialpurchases, so an unpaid or part-paid bill reaches Supplier
-- Balances and can be settled by the same payment + allocation machinery.
--
-- Where water DIFFERS from poultry, and why it matters
-- ----------------------------------------------------
--
-- 1. WATER ALREADY HAS UNPAID EXPENSES. 047's rule is "on Approve, if
--    PaymentMethod <> Credit, debit the linked CashAccount", and migration 236
--    excludes Credit rows from cash-flow outflow for exactly that reason. So a
--    Credit expense IS an unpaid bill and has always been treated as one --
--    it simply never reached Supplier Balances.
--
--    This migration therefore resolves an untouched row as
--        COALESCE(amountpaid, CASE WHEN paymentmethod = 'Credit' THEN 0 ELSE amount END)
--    rather than poultry's flat COALESCE(amountpaid, amount).
--
--    CONSEQUENCE, DELIBERATE AND CHOSEN: existing Credit bills that name a
--    supplier become open payables the moment this lands, so water supplier
--    balances WILL increase. That is the one thing here that moves. Section 9 at
--    the foot of this file reports exactly which rows and what they total --
--    run it before you apply, and again after.
--
-- 2. SYSTEM-GENERATED EXPENSES MUST NEVER BE PAYABLE. Poultry could rely on
--    supplierid being NULL on every SP-written expense row. Water cannot:
--    spwatersupplierpaymentcash_sync (227:892) writes supplierid onto the
--    aggregated expense row it books for a payment. Left alone, paying a
--    supplier would create a new bill owed to that same supplier, payable in
--    turn -- money owed forever from nothing.
--
--    So the payable arm takes only rows with sourcetype IS NULL: bills a person
--    typed in. Anything with a sourcetype is the shadow of another document, and
--    that other document is the payable.
--
-- 3. ONE EXPENSE ROW PER PAYMENT, NOT PER ALLOCATION. 227 books a single
--    aggregated waterexpenses row for the whole payment. That row must now cover
--    only the PURCHASE portion -- booking the expense portion again would
--    double-count bills that already exist. Where a payment settles bills, the
--    cash for that portion is posted directly against the payment instead.
--
--    A payment with no expense allocations -- which is every payment that
--    already exists -- takes byte-for-byte the same path it takes today.
--
-- Cash flow is migration 241. Apply 240 then 241; neither is correct alone.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Payment columns on waterexpenses.
-- -----------------------------------------------------------------------------
ALTER TABLE waterexpenses ADD COLUMN IF NOT EXISTS amountpaid numeric(14,2) NULL;
ALTER TABLE waterexpenses ADD COLUMN IF NOT EXISTS duedate date NULL;

COMMENT ON COLUMN waterexpenses.amountpaid IS
    'Cash actually paid against this expense. NULL defers to paymentmethod: '
    '''Credit'' means nothing has been paid, anything else means paid in full -- '
    'the reading 047 established and migration 236 already relies on. Read it as '
    'COALESCE(amountpaid, CASE WHEN paymentmethod = ''Credit'' THEN 0 ELSE amount END).';

DO $genstatus$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'waterexpenses' AND column_name = 'paymentstatus') THEN
        ALTER TABLE waterexpenses ADD COLUMN paymentstatus text
            GENERATED ALWAYS AS (
                CASE
                    -- Internal use records stock leaving with no money moving
                    -- (212/213). It is filed as Credit, but it is not a debt.
                    WHEN sourcetype = 'WaterInternalUsage' THEN 'NonCash'
                    WHEN COALESCE(status, '') = 'Cancelled' THEN 'Cancelled'
                    WHEN COALESCE(amountpaid,
                             CASE WHEN COALESCE(paymentmethod, '') = 'Credit'
                                  THEN 0 ELSE amount END) >= COALESCE(amount, 0) THEN 'Paid'
                    WHEN COALESCE(amountpaid,
                             CASE WHEN COALESCE(paymentmethod, '') = 'Credit'
                                  THEN 0 ELSE amount END) <= 0 THEN 'Unpaid'
                    ELSE 'PartiallyPaid'
                END) STORED;
        RAISE NOTICE '240: added generated column waterexpenses.paymentstatus';
    END IF;
END
$genstatus$;

CREATE INDEX IF NOT EXISTS ix_waterexpenses_farm_supplier
    ON waterexpenses (farmid, supplierid)
    WHERE supplierid IS NOT NULL AND sourcetype IS NULL;

-- -----------------------------------------------------------------------------
-- 2. Expenses become the second water payable.
-- -----------------------------------------------------------------------------
-- Return shape gains duedate, so DROP first -- CREATE OR REPLACE cannot change a
-- return type.
DROP FUNCTION IF EXISTS public.fnwaterpayables(text);

CREATE OR REPLACE FUNCTION public.fnwaterpayables(p_farmid text)
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
    SELECT 'RawMaterialPurchase'::text, pu.waterrawmaterialpurchaseid, pu.supplierid,
           pu.purchasedate::date,
           COALESCE(i.itemname, pu.suppliername, 'Raw material')::text,
           ('P' || pu.waterrawmaterialpurchaseid::text)::text,
           pu.totalcost, pu.amountpaid,
           GREATEST(pu.totalcost - pu.amountpaid, 0)::numeric(14,2),
           -- Always NULL: unlike poultryrawmaterialpurchases, the water table
           -- has no cash account column -- WaterRawMaterialPurchaseModel
           -- exposes one, but it is a projection, not storage. The column is
           -- kept so fnwaterpayables matches the poultry shape, and the cash
           -- sync falls back to the farm's first active account exactly as
           -- migration 091 always did.
           NULL::integer,
           NULL::date
    FROM   waterrawmaterialpurchases pu
    LEFT   JOIN waterrawmaterialitems i
           ON i.waterrawmaterialitemid = pu.waterrawmaterialitemid
    WHERE  pu.farmid = p_farmid
    UNION ALL
    SELECT 'Expense'::text, e.waterexpenseid, e.supplierid,
           e.expensedate::date,
           COALESCE(NULLIF(btrim(e.description), ''), c.name, 'Expense')::text,
           ('E' || e.waterexpenseid::text)::text,
           COALESCE(e.amount, 0)::numeric(14,2),
           COALESCE(e.amountpaid,
                    CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                         THEN 0 ELSE e.amount END)::numeric(14,2),
           GREATEST(COALESCE(e.amount, 0)
                    - COALESCE(e.amountpaid,
                               CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                                    THEN 0 ELSE e.amount END), 0)::numeric(14,2),
           e.watercashaccountid,
           e.duedate
    FROM   waterexpenses e
    LEFT   JOIN waterexpensecategories c
           ON c.waterexpensecategoryid = e.waterexpensecategoryid
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  e.supplierid IS NOT NULL
      AND  COALESCE(e.isdeleted, FALSE) = FALSE
      -- 047: only an approved expense has been recognised at all. A Draft is
      -- not yet a debt.
      AND  COALESCE(e.status, '') = 'Approved'
      -- See the header, point 2. Only bills a person typed in are payable;
      -- anything with a sourcetype is another document's shadow.
      AND  e.sourcetype IS NULL;
$function$;

-- -----------------------------------------------------------------------------
-- 3. The reads, with an expense's own due date honoured.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spwatersupplieropenpurchases(text, integer, date, date, text);

CREATE OR REPLACE FUNCTION public.spwatersupplieropenpurchases(
    p_farmid text,
    p_supplierid integer,
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
    SELECT d.documenttype, d.documentid, d.reference, d.docdate, d.label,
           d.totalcost, d.amountpaid, d.balance,
           COALESCE(d.duedate, (d.docdate + COALESCE(s.paymenttermsdays, 0)))::date,
           GREATEST((CURRENT_DATE - d.docdate), 0)::integer,
           CASE WHEN d.amountpaid > 0 THEN 'Partially Paid' ELSE 'Unpaid' END::text,
           (COALESCE(d.duedate, (d.docdate + COALESCE(s.paymenttermsdays, 0))) < CURRENT_DATE),
           d.cashaccountid
    FROM   fnwaterpayables(p_farmid) d
    JOIN   watersuppliers s ON s.watersupplierid = d.supplierid AND s.farmid = p_farmid
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

CREATE OR REPLACE FUNCTION public.spwatersupplierbalances(
    p_farmid text,
    p_from date DEFAULT NULL::date,
    p_to date DEFAULT NULL::date,
    p_supplierid integer DEFAULT NULL::integer,
    p_status text DEFAULT 'All'::text,
    p_minbalance numeric DEFAULT NULL::numeric,
    p_search text DEFAULT NULL::text)
RETURNS TABLE(
    supplierid       integer,
    suppliername     text,
    contactphone     text,
    contactemail     text,
    paymenttermsdays integer,
    totalbalance     numeric,
    opendoccount     integer,
    oldestdocdate    date,
    latestdocdate    date,
    lastpaymentdate  timestamp without time zone,
    overdueamount    numeric,
    totalpurchased   numeric,
    totalpaid        numeric)
LANGUAGE sql
STABLE
AS $function$
    WITH opendocs AS (
        SELECT d.*, COALESCE(s.paymenttermsdays, 0) AS terms
        FROM   fnwaterpayables(p_farmid) d
        JOIN   watersuppliers s ON s.watersupplierid = d.supplierid AND s.farmid = p_farmid
        WHERE  d.supplierid IS NOT NULL
          AND  d.balance > 0
          AND  (p_supplierid IS NULL OR d.supplierid = p_supplierid)
          AND  (p_from IS NULL OR d.docdate >= p_from)
          AND  (p_to   IS NULL OR d.docdate <= p_to)
    ),
    filtered AS (
        SELECT o.*,
               COALESCE(o.duedate, (o.docdate + o.terms))                  AS effectiveduedate,
               (COALESCE(o.duedate, (o.docdate + o.terms)) < CURRENT_DATE) AS isoverdue
        FROM   opendocs o
        WHERE  CASE COALESCE(p_status, 'All')
                    WHEN 'Partial' THEN o.amountpaid > 0
                    WHEN 'Unpaid'  THEN o.amountpaid = 0
                    WHEN 'Overdue' THEN COALESCE(o.duedate, (o.docdate + o.terms)) < CURRENT_DATE
                    ELSE TRUE
               END
    )
    SELECT s.watersupplierid,
           s.suppliername::text,
           s.phone::text,
           s.email::text,
           COALESCE(s.paymenttermsdays, 0),
           SUM(f.balance)::numeric(14,2),
           COUNT(*)::integer,
           MIN(f.docdate),
           MAX(f.docdate),
           (SELECT MAX(sp.paymentdate) FROM watersupplierpayments sp
            WHERE sp.farmid = p_farmid AND sp.supplierid = s.watersupplierid
              AND COALESCE(sp.status, 'Posted') = 'Posted'),
           SUM(CASE WHEN f.isoverdue THEN f.balance ELSE 0 END)::numeric(14,2),
           SUM(f.totalcost)::numeric(14,2),
           SUM(f.amountpaid)::numeric(14,2)
    FROM   filtered f
    JOIN   watersuppliers s ON s.watersupplierid = f.supplierid AND s.farmid = p_farmid
    WHERE  (p_search IS NULL OR btrim(p_search) = ''
            OR s.suppliername ILIKE '%' || btrim(p_search) || '%'
            OR COALESCE(s.phone, '') ILIKE '%' || btrim(p_search) || '%')
    GROUP  BY s.watersupplierid, s.suppliername, s.phone, s.email, s.paymenttermsdays
    HAVING (p_minbalance IS NULL OR SUM(f.balance) >= p_minbalance)
    ORDER  BY SUM(f.balance) DESC;
$function$;

-- The statement gains expenses, and with them the arm poultry has always had:
-- a bill can be part-paid AT ENTRY, with no payment record behind it. Without
-- that credit line the running balance would carry a debt that was never owed.
CREATE OR REPLACE FUNCTION public.spwatersupplierstatement(
    p_farmid text, p_supplierid integer,
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
    -- Only the FIRST arm of a UNION names the columns, so every alias the outer
    -- query needs has to be declared here.
    WITH lines AS (
        SELECT CASE WHEN p_from IS NULL THEN NULL::date ELSE p_from END AS entrydate,
               'OpeningBalance'::text  AS entrytype,
               NULL::text              AS reference,
               'Opening balance'::text AS description,
               CASE WHEN p_from IS NULL THEN 0::numeric(14,2) ELSE COALESCE((
                   SELECT SUM(d.balance) FROM fnwaterpayables(p_farmid) d
                   WHERE  d.supplierid = p_supplierid AND d.docdate < p_from), 0)::numeric(14,2) END AS debit,
               0::numeric(14,2) AS credit,
               NULL::text       AS documenttype,
               NULL::integer    AS documentid,
               0                AS sortkey,
               0                AS pin

        UNION ALL

        -- A purchase or a bill INCREASES what we owe, so it is the debit here --
        -- the mirror of the customer statement, where a sale is the debit.
        SELECT d.docdate,
               CASE WHEN d.documenttype = 'Expense' THEN 'Expense' ELSE 'Purchase' END::text,
               d.reference, d.label,
               d.totalcost::numeric(14,2), 0::numeric(14,2),
               d.documenttype, d.documentid, 1, 1
        FROM   fnwaterpayables(p_farmid) d
        WHERE  d.supplierid = p_supplierid
          AND  (p_from IS NULL OR d.docdate >= p_from)
          AND  (p_to   IS NULL OR d.docdate <= p_to)

        UNION ALL

        -- Paid when it was recorded: amountpaid with no allocation behind it.
        SELECT d.docdate, 'Payment'::text, d.reference,
               CASE WHEN d.documenttype = 'Expense'
                    THEN 'Paid when recorded'
                    ELSE 'Paid at time of purchase' END::text,
               0::numeric(14,2),
               GREATEST(d.amountpaid - COALESCE((
                   SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                   WHERE  sa.farmid = p_farmid AND sa.module = 'water' AND sa.status = 'Posted'
                     AND  sa.documenttype = d.documenttype AND sa.documentid = d.documentid), 0),
                   0)::numeric(14,2),
               d.documenttype, d.documentid, 2, 1
        FROM   fnwaterpayables(p_farmid) d
        WHERE  d.supplierid = p_supplierid
          AND  (p_from IS NULL OR d.docdate >= p_from)
          AND  (p_to   IS NULL OR d.docdate <= p_to)
          AND  d.amountpaid > COALESCE((
                   SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                   WHERE  sa.farmid = p_farmid AND sa.module = 'water' AND sa.status = 'Posted'
                     AND  sa.documenttype = d.documenttype AND sa.documentid = d.documentid), 0)

        UNION ALL

        SELECT sp.paymentdate::date, 'Payment'::text,
               COALESCE(NULLIF(btrim(sp.referenceno), ''), 'PMT' || sp.watersupplierpaymentid::text)::text,
               ('Payment' || COALESCE(' — ' || NULLIF(btrim(sp.paymentmethod), ''), ''))::text,
               0::numeric(14,2), sp.totalamount::numeric(14,2),
               NULL::text, NULL::integer, 2, 1
        FROM   watersupplierpayments sp
        WHERE  sp.farmid = p_farmid AND sp.supplierid = p_supplierid
          AND  COALESCE(sp.status, 'Posted') = 'Posted'
          AND  (p_from IS NULL OR sp.paymentdate::date >= p_from)
          AND  (p_to   IS NULL OR sp.paymentdate::date <= p_to)
    ),
    ordered AS (
        SELECT l.*,
               ROW_NUMBER() OVER (ORDER BY l.pin, l.entrydate NULLS FIRST, l.sortkey, l.documentid) AS rn
        FROM   lines l
    )
    SELECT o.entrydate, o.entrytype, o.reference, o.description,
           o.debit, o.credit,
           SUM(o.debit - o.credit) OVER (ORDER BY o.rn
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::numeric(14,2),
           o.documenttype, o.documentid, o.sortkey
    FROM   ordered o
    ORDER  BY o.rn;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Cash and the aggregated expense row, split by what was actually paid.
-- -----------------------------------------------------------------------------
-- The expense row 227 books for a payment now covers the PURCHASE portion only.
-- The bill portion settles bills that already exist; booking them again would be
-- the double count this whole piece of work exists to prevent.
--
-- Cash for the bill portion is therefore posted directly against the payment
-- (sourcetype 'WaterSupplierPayment'), because there is no expense row to hang
-- it on. A payment with no bill allocations -- every payment that exists today --
-- takes exactly the path it took before: one expense, one cash row, same ids.
CREATE OR REPLACE FUNCTION public.spwatersupplierpaymentcash_sync(
    p_farmid text, p_paymentid integer)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_pay      record;
    v_catid    integer;
    v_acct     integer;
    v_docs     text;
    v_expense  integer;
    v_party    text;
    v_purchase numeric(14,2);
    v_bills    numeric(14,2);
BEGIN
    SELECT sp.watersupplierpaymentid, sp.supplierid, sp.paymentdate, sp.totalamount,
           sp.paymentmethod, sp.watercashaccountid, sp.createdby, sp.notes
    INTO   v_pay
    FROM   watersupplierpayments sp
    WHERE  sp.watersupplierpaymentid = p_paymentid AND sp.farmid = p_farmid
      AND  COALESCE(sp.status, 'Posted') = 'Posted';

    IF v_pay.watersupplierpaymentid IS NULL THEN RETURN; END IF;

    SELECT COALESCE(SUM(sa.amountapplied) FILTER (WHERE sa.documenttype <> 'Expense'), 0),
           COALESCE(SUM(sa.amountapplied) FILTER (WHERE sa.documenttype = 'Expense'), 0)
    INTO   v_purchase, v_bills
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'water'
      AND  sa.paymentid = p_paymentid AND sa.status = 'Posted';

    -- The account the user chose, else the farm's first active one -- the same
    -- fallback 091 used, so behaviour is unchanged when no account is passed.
    v_acct := v_pay.watercashaccountid;
    IF v_acct IS NULL THEN
        SELECT a.watercashaccountid INTO v_acct
        FROM   watercashaccounts a
        WHERE  a.farmid = p_farmid AND a.isactive = TRUE
        ORDER  BY a.watercashaccountid
        LIMIT  1;
    END IF;

    SELECT s.suppliername INTO v_party
    FROM   watersuppliers s
    WHERE  s.watersupplierid = v_pay.supplierid AND s.farmid = p_farmid;

    -- ---- the purchase portion: expense row + its cash, exactly as before ----
    IF v_purchase > 0 THEN
        -- Ensure the category exists, inline rather than through
        -- spwaterexpensecategory_ensurerawmaterialpurchase (068). Same category
        -- name, so an expense booked here lands where every other raw-material
        -- purchase expense already does.
        SELECT ec.waterexpensecategoryid INTO v_catid
        FROM   waterexpensecategories ec
        WHERE  ec.farmid = p_farmid
          AND  ec.name = 'Raw Materials / Inventory Purchase'
          AND  COALESCE(ec.isdeleted, FALSE) = FALSE
        LIMIT  1;

        IF v_catid IS NULL THEN
            INSERT INTO waterexpensecategories (farmid, name, isactive, isdeleted)
            VALUES (p_farmid, 'Raw Materials / Inventory Purchase', TRUE, FALSE)
            RETURNING waterexpensecategoryid INTO v_catid;
        END IF;

        SELECT string_agg('#' || sa.documentid::text, ', ' ORDER BY sa.documentid)
        INTO   v_docs
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = 'water'
          AND  sa.paymentid = p_paymentid AND sa.status = 'Posted'
          AND  sa.documenttype <> 'Expense';

        INSERT INTO waterexpenses
            (farmid, expensedate, waterexpensecategoryid, description, amount, paidto,
             paymentmethod, watercashaccountid, linkedwaterproductionbatchid,
             status, notes, createdby, approvedby, approvedat,
             supplierid, sourcetype, sourceid)
        VALUES
            (p_farmid, v_pay.paymentdate, v_catid,
             'Supplier payment for raw material purchase ' || COALESCE(v_docs, ''),
             v_purchase, v_party,
             COALESCE(NULLIF(btrim(v_pay.paymentmethod), ''), 'Cash'),
             v_acct, NULL,
             'Approved',
             'Auto-created from a supplier payment.',
             v_pay.createdby, v_pay.createdby, (now() at time zone 'utc'),
             v_pay.supplierid, 'WaterSupplierPayment', p_paymentid)
        RETURNING waterexpenseid INTO v_expense;

        IF v_acct IS NOT NULL THEN
            INSERT INTO watercashtransactions
                (farmid, watercashaccountid, transactiondate, transactiontype,
                 sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
            VALUES
                (p_farmid, v_acct, v_pay.paymentdate, 'CashOut',
                 'Expense', v_expense, -v_purchase,
                 'Supplier payment — raw material purchase ' || COALESCE(v_docs, ''),
                 v_pay.createdby, v_pay.createdby, (now() at time zone 'utc'));

            UPDATE watercashaccounts
            SET    currentbalance = currentbalance - v_purchase,
                   updatedat = (now() at time zone 'utc')
            WHERE  watercashaccountid = v_acct AND farmid = p_farmid;
        END IF;
    END IF;

    -- ---- the bill portion: cash only, keyed to the payment ------------------
    IF v_bills > 0 AND v_acct IS NOT NULL THEN
        INSERT INTO watercashtransactions
            (farmid, watercashaccountid, transactiondate, transactiontype,
             sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_acct, v_pay.paymentdate, 'CashOut',
             'WaterSupplierPayment', p_paymentid, -v_bills,
             'Supplier payment — expenses', v_pay.createdby, v_pay.createdby,
             (now() at time zone 'utc'));

        UPDATE watercashaccounts
        SET    currentbalance = currentbalance - v_bills,
               updatedat = (now() at time zone 'utc')
        WHERE  watercashaccountid = v_acct AND farmid = p_farmid;
    END IF;
END;
$function$;

-- Reversal of both halves. The purchase half keeps 227's behaviour exactly --
-- cancel the expense, post a compensating CashIn -- and the bill half undoes its
-- own cash row the same way.
CREATE OR REPLACE FUNCTION public.spwatersupplierpaymentcash_unsync(
    p_farmid text, p_paymentid integer, p_reversedby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_expense integer;
    v_amount  numeric(14,2);
    v_acct    integer;
    v_bills   numeric(14,2);
    v_bacct   integer;
BEGIN
    SELECT e.waterexpenseid, e.amount, e.watercashaccountid
    INTO   v_expense, v_amount, v_acct
    FROM   waterexpenses e
    WHERE  e.farmid = p_farmid AND e.sourcetype = 'WaterSupplierPayment'
      AND  e.sourceid = p_paymentid AND COALESCE(e.status, '') <> 'Cancelled'
    LIMIT  1;

    IF v_expense IS NOT NULL THEN
        UPDATE waterexpenses
        SET    status = 'Cancelled',
               notes  = COALESCE(notes, '') || ' | Reversed with the supplier payment.'
        WHERE  waterexpenseid = v_expense AND farmid = p_farmid;

        IF v_acct IS NOT NULL THEN
            INSERT INTO watercashtransactions
                (farmid, watercashaccountid, transactiondate, transactiontype,
                 sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
            VALUES
                (p_farmid, v_acct, (now() at time zone 'utc'), 'CashIn',
                 'Expense', v_expense, v_amount,
                 'Reversal of supplier payment #' || p_paymentid::text,
                 p_reversedby, p_reversedby, (now() at time zone 'utc'));

            UPDATE watercashaccounts
            SET    currentbalance = currentbalance + v_amount,
                   updatedat = (now() at time zone 'utc')
            WHERE  watercashaccountid = v_acct AND farmid = p_farmid;
        END IF;
    END IF;

    -- The bill half. Summed from the ledger rather than recomputed from the
    -- allocations, because reversal flips those to Reversed before the cash is
    -- undone in some paths and a recomputation would then find nothing.
    SELECT COALESCE(SUM(-ct.amount), 0), MAX(ct.watercashaccountid)
    INTO   v_bills, v_bacct
    FROM   watercashtransactions ct
    WHERE  ct.farmid = p_farmid AND ct.sourcetype = 'WaterSupplierPayment'
      AND  ct.sourceid = p_paymentid AND ct.amount < 0;

    IF v_bills > 0 AND v_bacct IS NOT NULL THEN
        INSERT INTO watercashtransactions
            (farmid, watercashaccountid, transactiondate, transactiontype,
             sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_bacct, (now() at time zone 'utc'), 'CashIn',
             'WaterSupplierPayment', p_paymentid, v_bills,
             'Reversal of supplier payment #' || p_paymentid::text || ' (expenses)',
             p_reversedby, p_reversedby, (now() at time zone 'utc'));

        UPDATE watercashaccounts
        SET    currentbalance = currentbalance + v_bills,
               updatedat = (now() at time zone 'utc')
        WHERE  watercashaccountid = v_bacct AND farmid = p_farmid;
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Recording and reversing, with bills alongside purchases.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwatersupplierpayment_record(
    p_farmid text,
    p_supplierid integer,
    p_amount numeric,
    p_allocations jsonb,
    p_paymentmethod text DEFAULT NULL::text,
    p_paymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone,
    p_cashaccountid integer DEFAULT NULL::integer,
    p_reference text DEFAULT NULL::text,
    p_note text DEFAULT NULL::text,
    p_sourcetype text DEFAULT 'SupplierBalances'::text,
    p_createdby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_date      timestamp := COALESCE(p_paymentdate, (now() at time zone 'utc'));
    v_allocated numeric(14,2);
    v_count     integer;
    v_distinct  integer;
    v_minamount numeric(14,2);
    v_missing   integer;
    v_paymentid integer;
    v_row       record;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than 0.';
    END IF;
    IF p_supplierid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM watersuppliers s
                       WHERE s.watersupplierid = p_supplierid AND s.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;
    IF p_cashaccountid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM watercashaccounts a
                       WHERE a.watercashaccountid = p_cashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
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

    SELECT COUNT(*) INTO v_missing
    FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
           AS a(documenttype text, documentid integer, amount numeric)
    WHERE  a.documentid IS NOT NULL AND COALESCE(a.amount, 0) <> 0
      AND  NOT EXISTS (SELECT 1 FROM fnwaterpayables(p_farmid) d
                       WHERE d.documenttype = COALESCE(a.documenttype, 'RawMaterialPurchase')
                         AND d.documentid = a.documentid);
    IF v_missing > 0 THEN
        RAISE EXCEPTION '% of the selected items do not belong to this company.', v_missing;
    END IF;

    INSERT INTO watersupplierpayments
        (farmid, supplierid, paymentdate, totalamount, paymentmethod,
         watercashaccountid, referenceno, notes, sourcetype, status, createdby, createdat)
    VALUES
        (p_farmid, p_supplierid, v_date, p_amount::numeric(14,2), p_paymentmethod,
         p_cashaccountid, p_reference, p_note,
         COALESCE(p_sourcetype, 'SupplierBalances'), 'Posted', p_createdby,
         (now() at time zone 'utc'))
    RETURNING watersupplierpaymentid INTO v_paymentid;

    FOR v_row IN
        SELECT COALESCE(a.documenttype, 'RawMaterialPurchase') AS documenttype,
               a.documentid,
               a.amount::numeric(14,2) AS amount,
               d.balance, d.supplierid, d.docdate
        FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
               AS a(documenttype text, documentid integer, amount numeric)
        JOIN   fnwaterpayables(p_farmid) d
               ON d.documenttype = COALESCE(a.documenttype, 'RawMaterialPurchase')
              AND d.documentid = a.documentid
        WHERE  a.documentid IS NOT NULL AND COALESCE(a.amount, 0) <> 0
        ORDER  BY d.docdate, a.documentid
    LOOP
        IF p_supplierid IS NOT NULL AND v_row.supplierid IS DISTINCT FROM p_supplierid THEN
            RAISE EXCEPTION '% #% does not belong to this supplier.',
                  v_row.documenttype, v_row.documentid;
        END IF;
        IF v_row.balance <= 0 THEN
            RAISE EXCEPTION '% #% is already fully paid.', v_row.documenttype, v_row.documentid;
        END IF;
        IF v_row.amount > v_row.balance THEN
            RAISE EXCEPTION 'Cannot apply % to % #% -- its balance is only %.',
                  v_row.amount, v_row.documenttype, v_row.documentid, v_row.balance;
        END IF;

        INSERT INTO supplierpaymentallocation
            (farmid, module, paymentid, documenttype, documentid, amountapplied,
             documentbalancebefore, documentbalanceafter, status, createdby, createdat)
        VALUES
            (p_farmid, 'water', v_paymentid, v_row.documenttype, v_row.documentid,
             v_row.amount, v_row.balance, v_row.balance - v_row.amount,
             'Posted', p_createdby, v_date);

        IF v_row.documenttype = 'Expense' THEN
            -- Resolve before adding: NULL means "settled at entry", and adding
            -- to a bare NULL would restart the sum from nothing.
            UPDATE waterexpenses
            SET    amountpaid = LEAST(
                       COALESCE(amountpaid,
                                CASE WHEN COALESCE(paymentmethod, '') = 'Credit'
                                     THEN 0 ELSE amount END) + v_row.amount, amount),
                   updatedat  = (now() at time zone 'utc')
            WHERE  waterexpenseid = v_row.documentid
              AND  lower(farmid::text) = lower(p_farmid);
        ELSE
            UPDATE waterrawmaterialpurchases
            SET    amountpaid = amountpaid + v_row.amount,
                   updatedat  = (now() at time zone 'utc')
            WHERE  waterrawmaterialpurchaseid = v_row.documentid AND farmid = p_farmid;
        END IF;
    END LOOP;

    -- One expense for the purchase portion, cash for the whole payment.
    PERFORM spwatersupplierpaymentcash_sync(p_farmid, v_paymentid);

    RETURN v_paymentid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spwatersupplierpayment_reverse(
    p_farmid text, p_paymentid integer,
    p_reason text DEFAULT NULL::text, p_reversedby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_now   timestamp := (now() at time zone 'utc');
    v_count integer := 0;
    v_row   record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM watersupplierpayments sp
                   WHERE sp.watersupplierpaymentid = p_paymentid AND sp.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Payment not found for this company.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM watersupplierpayments sp
                   WHERE sp.watersupplierpaymentid = p_paymentid AND sp.farmid = p_farmid
                     AND COALESCE(sp.status, 'Posted') = 'Posted') THEN
        RAISE EXCEPTION 'This payment has already been reversed.';
    END IF;

    FOR v_row IN
        SELECT sa.documenttype, sa.documentid, sa.amountapplied
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = 'water'
          AND  sa.paymentid = p_paymentid AND sa.status = 'Posted'
    LOOP
        IF v_row.documenttype = 'Expense' THEN
            UPDATE waterexpenses
            SET    amountpaid = GREATEST(
                       COALESCE(amountpaid,
                                CASE WHEN COALESCE(paymentmethod, '') = 'Credit'
                                     THEN 0 ELSE amount END) - v_row.amountapplied, 0),
                   updatedat  = v_now
            WHERE  waterexpenseid = v_row.documentid
              AND  lower(farmid::text) = lower(p_farmid);
        ELSE
            UPDATE waterrawmaterialpurchases
            SET    amountpaid = GREATEST(amountpaid - v_row.amountapplied, 0),
                   updatedat  = v_now
            WHERE  waterrawmaterialpurchaseid = v_row.documentid AND farmid = p_farmid;
        END IF;
        v_count := v_count + 1;
    END LOOP;

    UPDATE supplierpaymentallocation
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason
    WHERE  farmid = p_farmid AND module = 'water'
      AND  paymentid = p_paymentid AND status = 'Posted';

    -- Cash before the header flips, since the sync reads a Posted header.
    PERFORM spwatersupplierpaymentcash_unsync(p_farmid, p_paymentid, p_reversedby);

    UPDATE watersupplierpayments
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason
    WHERE  watersupplierpaymentid = p_paymentid AND farmid = p_farmid;

    RETURN v_count;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. The water expense read path, carrying payment state.
-- -----------------------------------------------------------------------------
-- Dropped BY NAME, for the reason 238 spells out: the live Postgres bodies are
-- not in this repo and their signatures have already drifted from the T-SQL --
-- 077 declares six parameters, WaterFinanceServices.cs:611 calls four. Dropping
-- every overload and creating exactly one lands in a known state without having
-- to read the database.
--
-- The projection is 077's, verified column for column against the reader in
-- WaterFinanceServices.Read, plus the four payment columns. Read() looks
-- everything up by NAME and guards the newer columns with HasCol, so an older
-- deployment that has not had this migration still maps cleanly.
--
-- The two optional trailing parameters keep 077's shape available for any caller
-- that passes them; the four-argument call the service makes binds unchanged.
DO $dropwaterexp$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure::text AS sig
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('spwaterexpense_getall', 'spwaterexpense_getbyid')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
        RAISE NOTICE '240: dropped %', r.sig;
    END LOOP;
END
$dropwaterexp$;

DROP TYPE IF EXISTS public.waterexpenserow CASCADE;
CREATE TYPE public.waterexpenserow AS (
    waterexpenseid               integer,
    farmid                       text,
    expensedate                  timestamp without time zone,
    waterexpensecategoryid       integer,
    categoryname                 text,
    description                  text,
    amount                       numeric,
    paidto                       text,
    paymentmethod                text,
    watercashaccountid           integer,
    cashaccountname              text,
    receipturl                   text,
    linkedwatervehicleid         integer,
    linkedwatermachineid         integer,
    linkedwaterproductionbatchid integer,
    supplierid                   integer,
    suppliername                 text,
    amountpaid                   numeric,
    balance                      numeric,
    paymentstatus                text,
    duedate                      date,
    sourcetype                   text,
    sourceid                     integer,
    status                       text,
    notes                        text,
    createdby                    text,
    approvedby                   text,
    approvedat                   timestamp without time zone,
    createdat                    timestamp without time zone,
    updatedat                    timestamp without time zone);

-- amountpaid is surfaced RESOLVED, so no caller can read the raw NULL and have
-- to remember that it means "look at paymentmethod".
CREATE OR REPLACE FUNCTION public.fnwaterexpenserows(p_farmid text)
RETURNS SETOF public.waterexpenserow
LANGUAGE sql
STABLE
AS $function$
    SELECT e.waterexpenseid, e.farmid::text, e.expensedate,
           e.waterexpensecategoryid, c.name::text,
           e.description::text, e.amount::numeric(14,2), e.paidto::text, e.paymentmethod::text,
           e.watercashaccountid, ca.accountname::text,
           e.receipturl::text,
           e.linkedwatervehicleid, e.linkedwatermachineid, e.linkedwaterproductionbatchid,
           e.supplierid, s.suppliername::text,
           COALESCE(e.amountpaid,
                    CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                         THEN 0 ELSE e.amount END)::numeric(14,2),
           GREATEST(COALESCE(e.amount, 0)
                    - COALESCE(e.amountpaid,
                               CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                                    THEN 0 ELSE e.amount END), 0)::numeric(14,2),
           e.paymentstatus::text,
           e.duedate,
           e.sourcetype::text, e.sourceid,
           e.status::text, e.notes::text,
           e.createdby::text, e.approvedby::text, e.approvedat,
           e.createdat, e.updatedat
    FROM   waterexpenses e
    INNER  JOIN waterexpensecategories c ON c.waterexpensecategoryid = e.waterexpensecategoryid
    LEFT   JOIN watercashaccounts ca     ON ca.watercashaccountid    = e.watercashaccountid
    LEFT   JOIN watersuppliers s         ON s.watersupplierid        = e.supplierid
    WHERE  e.farmid = p_farmid
      AND  COALESCE(e.isdeleted, FALSE) = FALSE;
$function$;

CREATE OR REPLACE FUNCTION public.spwaterexpense_getall(
    p_farmid text,
    p_status text DEFAULT NULL::text,
    p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone,
    p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone,
    p_supplierid integer DEFAULT NULL::integer,
    p_sourcetype text DEFAULT NULL::text)
RETURNS SETOF public.waterexpenserow
LANGUAGE sql
STABLE
AS $function$
    SELECT * FROM fnwaterexpenserows(p_farmid) e
    WHERE  (p_status     IS NULL OR e.status     = p_status)
      AND  (p_fromdate   IS NULL OR e.expensedate >= p_fromdate)
      AND  (p_todate     IS NULL OR e.expensedate <= p_todate)
      AND  (p_supplierid IS NULL OR e.supplierid  = p_supplierid)
      AND  (p_sourcetype IS NULL OR e.sourcetype  = p_sourcetype)
    ORDER  BY e.expensedate DESC, e.waterexpenseid DESC;
$function$;

CREATE OR REPLACE FUNCTION public.spwaterexpense_getbyid(
    p_waterexpenseid integer, p_farmid text)
RETURNS SETOF public.waterexpenserow
LANGUAGE sql
STABLE
AS $function$
    SELECT * FROM fnwaterexpenserows(p_farmid) e
    WHERE  e.waterexpenseid = p_waterexpenseid;
$function$;

-- Set payment state on an existing bill.
--
-- Deliberately a SEPARATE function rather than four more parameters on
-- spwaterexpense_insert / _update. Those write fifteen columns through a body
-- this repo does not contain, and rewriting them blind to add two fields would
-- risk the receipt, approval and asset-link behaviour for no gain. The Expenses
-- page calls this straight after creating or editing a bill.
CREATE OR REPLACE FUNCTION public.spwaterexpense_setpayment(
    p_farmid text,
    p_waterexpenseid integer,
    p_amountpaid numeric DEFAULT NULL::numeric,
    p_duedate date DEFAULT NULL::date)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_amount numeric(14,2);
    v_alloc  numeric(14,2);
    v_paid   numeric(14,2) := p_amountpaid;
BEGIN
    SELECT e.amount INTO v_amount
    FROM   waterexpenses e
    WHERE  e.waterexpenseid = p_waterexpenseid AND e.farmid = p_farmid
    LIMIT  1;

    IF v_amount IS NULL THEN
        RAISE EXCEPTION 'Expense not found for this company.';
    END IF;

    -- What supplier payments have already settled. An edit must never contradict
    -- money that has actually moved, or the balance on screen and
    -- fnwaterbalanceaudit disagree from that moment on.
    SELECT COALESCE(SUM(sa.amountapplied), 0) INTO v_alloc
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'water' AND sa.status = 'Posted'
      AND  sa.documenttype = 'Expense' AND sa.documentid = p_waterexpenseid;

    IF v_paid IS NOT NULL THEN
        IF v_paid < 0 THEN
            RAISE EXCEPTION 'Amount paid cannot be negative.';
        END IF;
        IF v_paid > v_amount THEN
            RAISE EXCEPTION 'Amount paid (%) cannot exceed the expense total (%).', v_paid, v_amount;
        END IF;
        IF v_paid < v_alloc THEN
            RAISE EXCEPTION 'Supplier payments totalling % have been applied to this expense, so amount paid cannot be set to %.',
                  v_alloc, v_paid;
        END IF;
    END IF;

    UPDATE waterexpenses
    SET    amountpaid = v_paid,
           duedate    = p_duedate,
           updatedat  = (now() at time zone 'utc')
    WHERE  waterexpenseid = p_waterexpenseid AND farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. The audit sees bills too.
-- -----------------------------------------------------------------------------
-- fnwaterbalanceaudit returns NOTHING when healthy. Adding a second payable
-- without adding it here would give bills an unwatched corner.
--
-- The new arm tests `allocated > paid` rather than `<> 0` like the two arms
-- above it: a bill can be part-paid at entry, before any payment record exists,
-- so allocations must never EXCEED what was paid but are not expected to equal
-- it. The existing arms are left exactly as 227 wrote them.
CREATE OR REPLACE FUNCTION public.fnwaterbalanceaudit(p_farmid text)
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
    SELECT 'customer'::text, 'WaterSale'::text, s.watersaleid,
           s.amountpaid,
           COALESCE(a.allocated, 0)::numeric(14,2),
           (s.amountpaid - COALESCE(a.allocated, 0))::numeric(14,2)
    FROM   watersales s
    LEFT   JOIN LATERAL (
               SELECT SUM(ca.amountapplied) AS allocated
               FROM   customerpaymentallocation ca
               WHERE  ca.farmid = s.farmid AND ca.module = 'water'
                 AND  ca.saleid = s.watersaleid AND ca.status = 'Posted'
           ) a ON TRUE
    WHERE  s.farmid = p_farmid
      AND  (s.amountpaid - COALESCE(a.allocated, 0)) <> 0
    UNION ALL
    SELECT 'supplier'::text, 'RawMaterialPurchase'::text, pu.waterrawmaterialpurchaseid,
           pu.amountpaid,
           COALESCE(a.allocated, 0)::numeric(14,2),
           (pu.amountpaid - COALESCE(a.allocated, 0))::numeric(14,2)
    FROM   waterrawmaterialpurchases pu
    LEFT   JOIN LATERAL (
               SELECT SUM(sa.amountapplied) AS allocated
               FROM   supplierpaymentallocation sa
               WHERE  sa.farmid = pu.farmid AND sa.module = 'water'
                 AND  sa.documenttype = 'RawMaterialPurchase'
                 AND  sa.documentid = pu.waterrawmaterialpurchaseid
                 AND  sa.status = 'Posted'
           ) a ON TRUE
    WHERE  pu.farmid = p_farmid
      AND  (pu.amountpaid - COALESCE(a.allocated, 0)) <> 0
    UNION ALL
    SELECT 'supplier'::text, 'Expense'::text, e.waterexpenseid,
           COALESCE(e.amountpaid,
                    CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                         THEN 0 ELSE e.amount END)::numeric(14,2),
           COALESCE(a.allocated, 0)::numeric(14,2),
           (COALESCE(e.amountpaid,
                     CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                          THEN 0 ELSE e.amount END) - COALESCE(a.allocated, 0))::numeric(14,2)
    FROM   waterexpenses e
    LEFT   JOIN LATERAL (
               SELECT SUM(sa.amountapplied) AS allocated
               FROM   supplierpaymentallocation sa
               WHERE  sa.farmid = e.farmid AND sa.module = 'water'
                 AND  sa.documenttype = 'Expense'
                 AND  sa.documentid = e.waterexpenseid
                 AND  sa.status = 'Posted'
           ) a ON TRUE
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(a.allocated, 0) > COALESCE(e.amountpaid,
               CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit' THEN 0 ELSE e.amount END);
$function$;

-- -----------------------------------------------------------------------------
-- 8. IAM catalog.
-- -----------------------------------------------------------------------------
INSERT INTO iampermissions
    (permissionkey, module, resource, action, permissiongroup, resourcelabel,
     description, companytype, isdangerous, sortorder)
SELECT v.permissionkey, v.module, v.resource, v.action, v.permissiongroup,
       v.resourcelabel, v.description, v.companytype, v.isdangerous, v.sortorder
FROM  (VALUES
    ('water.expense-payments.create', 'water', 'expense-payments', 'create', 'Expenses',
     'Expense payments', 'Record a payment against an unpaid or part-paid expense', 'Water', false, 64),
    ('water.expense-payment-history.view', 'water', 'expense-payment-history', 'view', 'Expenses',
     'Expense payment history', 'See which supplier payments settled an expense', 'Water', false, 65)
) AS v(permissionkey, module, resource, action, permissiongroup, resourcelabel,
       description, companytype, isdangerous, sortorder)
WHERE NOT EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = v.permissionkey);

COMMIT;

-- =============================================================================
-- 9. IMPACT REPORT -- run this BEFORE applying, and again after.
-- =============================================================================
-- This migration deliberately moves one number: existing Credit bills that name
-- a supplier become open payables. Everything else is unchanged. These queries
-- say exactly which rows and how much, so the movement is measured rather than
-- discovered.

-- 9a. The bills that become payable, per farm. This total is how much each
--     farm's supplier balance goes UP.
SELECT e.farmid,
       COUNT(*)                          AS bills_becoming_payable,
       ROUND(SUM(e.amount), 2)           AS total_now_owed,
       MIN(e.expensedate)::date          AS oldest,
       MAX(e.expensedate)::date          AS newest
FROM   waterexpenses e
WHERE  e.supplierid IS NOT NULL
  AND  COALESCE(e.isdeleted, FALSE) = FALSE
  AND  COALESCE(e.status, '') = 'Approved'
  AND  e.sourcetype IS NULL
  AND  COALESCE(e.paymentmethod, '') = 'Credit'
  AND  e.amountpaid IS NULL
GROUP  BY e.farmid
ORDER  BY total_now_owed DESC;

-- 9b. PROOF THAT NOTHING ELSE MOVES. A system-generated expense must never be
--     payable -- above all the row a supplier payment books for itself, which
--     would otherwise be a debt to the supplier you just paid, payable again,
--     forever. Expect NO ROWS.
SELECT d.documenttype, d.documentid, d.supplierid, d.balance
FROM   (SELECT DISTINCT farmid FROM waterexpenses) f
CROSS  JOIN LATERAL fnwaterpayables(f.farmid) d
JOIN   waterexpenses e ON e.waterexpenseid = d.documentid
WHERE  d.documenttype = 'Expense'
  AND  e.sourcetype IS NOT NULL;

-- 9c. Internal use is not a debt. Expect NO ROWS.
SELECT e.waterexpenseid, e.paymentstatus, e.amount
FROM   waterexpenses e
WHERE  e.sourcetype = 'WaterInternalUsage'
  AND  e.paymentstatus <> 'NonCash';

-- 9d. The invariant. Expect NO ROWS per farm.
SELECT f.farmid, a.*
FROM   (SELECT DISTINCT farmid FROM watersupplierpayments) f
CROSS  JOIN LATERAL fnwaterbalanceaudit(f.farmid) a;

-- =============================================================================
-- 224_PoultrySupplierBalances.postgres.sql
--
-- Purpose
-- -------
-- The poultry Supplier Balances control page: who we owe, which unpaid
-- purchases make up each balance, and one payment allocated across several.
--
-- The mirror of 223, but the poultry supplier side is greenfield in a way the
-- customer side was not. There is no supplier payment table at all, and there is
-- no single "purchase" document -- payables live in TWO tables:
--
--     poultryrawmaterialpurchases   feed, packaging, medication
--     mainflockbatch                birds and chicks
--
-- which is exactly why supplierpaymentallocation carries a documenttype
-- alongside the id. Expenses are deliberately NOT payables here: `expense` has
-- no amountpaid column to part-pay against, and its farmid is a uuid while every
-- other table uses text.
--
-- Four things this file has to get right
-- --------------------------------------
--
-- 1. SUPPLIER IDENTITY. All 74 raw-material purchases have supplierid NULL --
--    the supplier is free text in `suppliername`, the same trap the sales table
--    had with customers. Backfilled by name, creating supplier rows as needed.
--
-- 2. THE EXPENSE INVARIANT. Migration 207 fixed a long-standing bug by
--    establishing that a purchase's LINKED EXPENSE ROWS SUM TO ITS amountpaid --
--    insert books one expense for the amount paid, and each balance payment
--    books another. A supplier payment is a balance payment, so it books its
--    expense rows too. Skipping that would silently stop the cost reaching the
--    P&L, which is the exact regression 207 was written to repair.
--
-- 3. NO DOUBLE-COUNTED CASH. A raw-material purchase's cash is ONE collapsed
--    CashOut for its cumulative amountpaid, reposted from scratch on every edit
--    (sppoultryrawmaterialpurchasecash_sync). A supplier payment posts its own
--    CashOut on the account the user actually paid from -- so the document sync
--    is narrowed to `amountpaid MINUS what allocations already covered`.
--
--    That subtraction is what keeps the two disjoint. Existing purchases have no
--    allocations, so they are completely unaffected; only money that moved
--    through the new payment path is carved out, and only for purchases that
--    have been paid through it.
--
-- 4. THE USER'S CHOSEN ACCOUNT IS HONOURED. Cash comes out of the account named
--    on the payment, not the account each purchase happened to be filed under.
--    A bulk payment across four purchases is one CashOut from Bank, which is
--    what actually happened at the bank.
--
-- Deliberately unchanged: mainflockbatch has never posted to a cash account, and
-- this file does not retro-post its history. Bird purchases paid through the new
-- supplier-payment path DO move cash; anything paid before it does not. Making
-- the old rows appear would rewrite balances nobody asked us to touch.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Supplier payment header.
-- -----------------------------------------------------------------------------
-- Unlike the customer side there is no existing per-document payment table to
-- extend, so this is a proper header with its allocations in
-- supplierpaymentallocation. One row = one payment the user made.
CREATE TABLE IF NOT EXISTS poultrysupplierpayments (
    poultrysupplierpaymentid serial        PRIMARY KEY,
    farmid                   text          NOT NULL,
    -- NULLABLE on purpose. 38 of 74 raw-material purchases and 17 of 19 flock
    -- batches carry no supplier at all, and several of those are still open --
    -- the Purchases page must keep being able to pay them. Such a payment is a
    -- real record of money out; it simply has no supplier balance to roll up
    -- into, so the balances page filters it out rather than inventing a party.
    supplierid               integer       NULL,
    paymentdate              timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    totalamount              numeric(14,2) NOT NULL CHECK (totalamount > 0),
    paymentmethod            text          NULL,
    poultrycashaccountid     integer       NULL,
    referenceno              text          NULL,
    notes                    text          NULL,
    -- PurchaseEntry (recorded on the purchase itself) | SupplierBalances
    sourcetype               text          NOT NULL DEFAULT 'SupplierBalances',
    -- Posted | Reversed
    status                   text          NOT NULL DEFAULT 'Posted',
    createdby                text          NULL,
    createdat                timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby               text          NULL,
    reversedat               timestamp     NULL,
    reversalreason           text          NULL
);

CREATE INDEX IF NOT EXISTS ix_poultrysupplierpayments_farm_supplier
    ON poultrysupplierpayments (farmid, supplierid) WHERE status = 'Posted';
CREATE INDEX IF NOT EXISTS ix_poultrysupplierpayments_farm_date
    ON poultrysupplierpayments (farmid, paymentdate);

-- -----------------------------------------------------------------------------
-- 2. Supplier identity.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_poultryrawmatpurchase_farm_supplier
    ON poultryrawmaterialpurchases (farmid, supplierid);
CREATE INDEX IF NOT EXISTS ix_mainflockbatch_farm_supplier
    ON mainflockbatch (farmid, supplierid);

CREATE OR REPLACE FUNCTION public.fnpoultrysupplier_resolve(
    p_farmid text, p_suppliername text, p_userid text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id   integer;
    v_name text := btrim(COALESCE(p_suppliername, ''));
BEGIN
    IF v_name = '' THEN RETURN NULL; END IF;

    SELECT s.supplierid INTO v_id
    FROM   supplier s
    WHERE  s.farmid = p_farmid AND lower(btrim(s.name)) = lower(v_name)
    ORDER  BY s.supplierid
    LIMIT  1;

    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    INSERT INTO supplier (userid, farmid, name, createddate)
    VALUES (COALESCE(p_userid, '0'), p_farmid, v_name, (now() at time zone 'utc'))
    RETURNING supplierid INTO v_id;

    RETURN v_id;
END;
$function$;

DO $backfill$
DECLARE
    v_created integer := 0;
    v_linked  integer := 0;
BEGIN
    INSERT INTO supplier (userid, farmid, name, createddate)
    SELECT DISTINCT ON (pu.farmid, lower(btrim(pu.suppliername)))
           COALESCE(pu.createdby, '0'), pu.farmid, btrim(pu.suppliername),
           (now() at time zone 'utc')
    FROM   poultryrawmaterialpurchases pu
    WHERE  pu.supplierid IS NULL
      AND  pu.suppliername IS NOT NULL AND btrim(pu.suppliername) <> ''
      AND  NOT EXISTS (SELECT 1 FROM supplier s
                       WHERE s.farmid = pu.farmid
                         AND lower(btrim(s.name)) = lower(btrim(pu.suppliername)))
    ORDER  BY pu.farmid, lower(btrim(pu.suppliername)), pu.poultryrawmaterialpurchaseid;
    GET DIAGNOSTICS v_created = ROW_COUNT;

    UPDATE poultryrawmaterialpurchases pu
    SET    supplierid = s.supplierid
    FROM   supplier s
    WHERE  pu.supplierid IS NULL
      AND  pu.suppliername IS NOT NULL AND btrim(pu.suppliername) <> ''
      AND  s.farmid = pu.farmid
      AND  lower(btrim(s.name)) = lower(btrim(pu.suppliername));
    GET DIAGNOSTICS v_linked = ROW_COUNT;

    RAISE NOTICE '224: created % supplier(s) from purchase names, linked % purchase(s).',
                 v_created, v_linked;
END
$backfill$;

-- -----------------------------------------------------------------------------
-- 3. Narrow the purchase cash sync to what allocations have NOT covered.
-- -----------------------------------------------------------------------------
-- Byte-for-byte the migration-136 body except for the v_alloc subtraction. A
-- purchase with no supplier-payment allocations behaves exactly as before.
CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialpurchasecash_sync(
    p_farmid text, p_poultryrawmaterialpurchaseid integer,
    p_poultrycashaccountid integer DEFAULT NULL::integer,
    p_setaccount boolean DEFAULT true, p_createdby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_acct  integer;
    v_amt   numeric(14,2);
    v_alloc numeric(14,2);
    v_item  text;
    v_bal   numeric(14,2);
BEGIN
    IF (p_setaccount = TRUE) THEN
        UPDATE poultryrawmaterialpurchases pu
        SET    poultrycashaccountid = p_poultrycashaccountid, updatedat = (now() at time zone 'utc')
        WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid AND pu.farmid = p_farmid;
    END IF;

    -- Reverse any existing purchase cash tx (restore balances, then delete them).
    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - t.net, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT ct.poultrycashaccountid, SUM(ct.amount) AS net
        FROM   poultrycashtransactions ct
        WHERE  ct.sourcetype = 'RawMaterialPurchase' AND ct.sourceid = p_poultryrawmaterialpurchaseid AND ct.farmid = p_farmid
        GROUP  BY ct.poultrycashaccountid
    ) t
    WHERE  t.poultrycashaccountid = a.poultrycashaccountid
      AND  a.farmid = p_farmid;

    DELETE FROM poultrycashtransactions ct
    WHERE  ct.sourcetype = 'RawMaterialPurchase' AND ct.sourceid = p_poultryrawmaterialpurchaseid AND ct.farmid = p_farmid;

    SELECT pu.poultrycashaccountid, pu.amountpaid, i.itemname
    INTO   v_acct, v_amt, v_item
    FROM   poultryrawmaterialpurchases pu
    LEFT   JOIN poultryrawmaterialitems i ON i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
    WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid AND pu.farmid = p_farmid
    LIMIT 1;

    -- Money that a supplier payment already took out of a (possibly different)
    -- cash account. Posting it again here would double-count it.
    SELECT COALESCE(SUM(sa.amountapplied), 0) INTO v_alloc
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.status = 'Posted'
      AND  sa.documenttype = 'RawMaterialPurchase'
      AND  sa.documentid = p_poultryrawmaterialpurchaseid;

    v_amt := GREATEST(COALESCE(v_amt, 0) - COALESCE(v_alloc, 0), 0);

    IF (v_acct IS NOT NULL AND v_amt > 0
        AND EXISTS (SELECT 1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct AND a.farmid = p_farmid)) THEN

        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance - v_amt, updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = v_acct AND a.farmid = p_farmid;

        SELECT a.currentbalance INTO v_bal
        FROM   poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct LIMIT 1;

        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_acct, (now() at time zone 'utc'), 'CashOut', 'RawMaterialPurchase', p_poultryrawmaterialpurchaseid,
             -v_amt, v_bal, 'Raw material purchase: ' || COALESCE(v_item, 'item'), p_createdby, p_createdby, (now() at time zone 'utc'));
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Record a supplier payment across one or more purchases.
-- -----------------------------------------------------------------------------
-- p_allocations is a JSON array of
--     {"documenttype": "RawMaterialPurchase"|"FlockBatch", "documentid": <int>, "amount": <numeric>}
-- Lower-case keys, unquoted recordset identifiers -- see the note in 223.
--
-- Overpayment is blocked. Negative cash is blocked unless the account allows it,
-- which is more than the existing purchase cash sync does (it ignores
-- allownegativebalance entirely).
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
    v_newbal    numeric(14,2);
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
        RAISE EXCEPTION 'Select at least one purchase to apply this payment to.';
    END IF;
    IF v_distinct <> v_count THEN
        RAISE EXCEPTION 'The same purchase appears more than once in this payment.';
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
               WHERE COALESCE(a.documenttype, '') NOT IN ('RawMaterialPurchase', 'FlockBatch')) THEN
        RAISE EXCEPTION 'Unknown document type. Expected RawMaterialPurchase or FlockBatch.';
    END IF;

    INSERT INTO poultrysupplierpayments
        (farmid, supplierid, paymentdate, totalamount, paymentmethod, poultrycashaccountid,
         referenceno, notes, sourcetype, status, createdby, createdat)
    VALUES
        (p_farmid, p_supplierid, v_date, p_amount, p_paymentmethod, p_cashaccountid,
         p_reference, p_notes, COALESCE(p_sourcetype, 'SupplierBalances'), 'Posted',
         p_createdby, (now() at time zone 'utc'))
    RETURNING poultrysupplierpaymentid INTO v_paymentid;

    -- The two payable tables, normalised into one shape so the loop below does
    -- not have to branch on every line.
    FOR v_row IN
        SELECT a.documenttype, a.documentid, a.amount::numeric(14,2) AS amount,
               d.totalcost, d.amountpaid, d.docdate, d.label, d.cashaccountid
        FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
               AS a(documenttype text, documentid integer, amount numeric)
        JOIN (
            SELECT 'RawMaterialPurchase'::text AS documenttype,
                   pu.poultryrawmaterialpurchaseid AS documentid,
                   pu.totalcost, pu.amountpaid, pu.purchasedate::date AS docdate,
                   COALESCE(i.itemname, 'item')::text AS label,
                   pu.poultrycashaccountid AS cashaccountid, pu.supplierid
            FROM   poultryrawmaterialpurchases pu
            LEFT   JOIN poultryrawmaterialitems i
                   ON i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
            WHERE  pu.farmid = p_farmid
            UNION ALL
            SELECT 'FlockBatch'::text, b.batchid, b.totalcost, b.amountpaid,
                   b.startdate::date, COALESCE(b.batchname, 'batch')::text,
                   NULL::integer, b.supplierid
            FROM   mainflockbatch b
            WHERE  b.farmid = p_farmid
        ) d ON d.documenttype = a.documenttype AND d.documentid = a.documentid
        WHERE  a.documentid IS NOT NULL AND COALESCE(a.amount, 0) <> 0
          -- IS NOT DISTINCT FROM so a no-supplier payment matches a no-supplier
          -- document; a plain = would silently drop every one of them.
          AND  d.supplierid IS NOT DISTINCT FROM p_supplierid
        ORDER  BY d.docdate, d.documentid
    LOOP
        v_before := GREATEST(COALESCE(v_row.totalcost, 0) - COALESCE(v_row.amountpaid, 0), 0);

        IF v_before <= 0 THEN
            RAISE EXCEPTION 'Purchase % #% is already fully paid.',
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
        ELSE
            UPDATE mainflockbatch b
            SET    amountpaid = b.amountpaid + v_row.amount
            WHERE  b.batchid = v_row.documentid AND b.farmid = p_farmid;
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
        BEGIN
            v_gid := p_farmid::uuid;
        EXCEPTION WHEN OTHERS THEN
            v_gid := NULL;
        END;

        IF (v_gid IS NOT NULL AND p_createdby IS NOT NULL) THEN
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
        -- purchase's account -- the payment's single CashOut below is where the
        -- money actually leaves.
        IF v_row.documenttype = 'RawMaterialPurchase' THEN
            PERFORM sppoultryrawmaterialpurchasecash_sync(
                p_farmid, v_row.documentid, v_row.cashaccountid, FALSE, p_createdby);
        END IF;
    END LOOP;

    -- Every id must have matched a document belonging to this supplier.
    SELECT v_count - COUNT(*) INTO v_missing
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.paymentid = v_paymentid;
    IF v_missing <> 0 THEN
        RAISE EXCEPTION '% of the selected purchases do not belong to this supplier or company.',
              v_missing;
    END IF;

    PERFORM sppoultrysupplierpaymentcash_sync(p_farmid, v_paymentid, p_createdby);

    RETURN v_paymentid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Supplier payment cash.
-- -----------------------------------------------------------------------------
-- Same reverse-then-repost idiom as every other poultry cash sync, so reversal
-- is just another call. Posts nothing for a reversed payment, which is what
-- takes the money back.
CREATE OR REPLACE FUNCTION public.sppoultrysupplierpaymentcash_sync(
    p_farmid text, p_paymentid integer, p_createdby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_acct   integer;
    v_amt    numeric(14,2);
    v_status text;
    v_name   text;
    v_bal    numeric(14,2);
BEGIN
    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - t.net, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT ct.poultrycashaccountid, SUM(ct.amount) AS net
        FROM   poultrycashtransactions ct
        WHERE  ct.sourcetype = 'PoultrySupplierPayment' AND ct.sourceid = p_paymentid
          AND  ct.farmid = p_farmid
        GROUP  BY ct.poultrycashaccountid
    ) t
    WHERE  t.poultrycashaccountid = a.poultrycashaccountid AND a.farmid = p_farmid;

    DELETE FROM poultrycashtransactions ct
    WHERE  ct.sourcetype = 'PoultrySupplierPayment' AND ct.sourceid = p_paymentid
      AND  ct.farmid = p_farmid;

    SELECT sp.poultrycashaccountid, sp.totalamount, sp.status, s.name
    INTO   v_acct, v_amt, v_status, v_name
    FROM   poultrysupplierpayments sp
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.poultrysupplierpaymentid = p_paymentid AND sp.farmid = p_farmid
    LIMIT  1;

    IF (v_acct IS NOT NULL AND COALESCE(v_amt, 0) > 0 AND COALESCE(v_status, 'Posted') = 'Posted'
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
            (p_farmid, v_acct, (now() at time zone 'utc'), 'CashOut', 'PoultrySupplierPayment',
             p_paymentid, -v_amt, v_bal,
             'Supplier payment: ' || COALESCE(v_name, 'supplier'), p_createdby, p_createdby,
             (now() at time zone 'utc'));
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Reverse a supplier payment.
-- -----------------------------------------------------------------------------
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
        ELSE
            UPDATE mainflockbatch b
            SET    amountpaid = GREATEST(b.amountpaid - v_row.amountapplied, 0)
            WHERE  b.batchid = v_row.documentid AND b.farmid = p_farmid;
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

    -- Allocations are Reversed now, so both syncs recompute without them: the
    -- payment's CashOut disappears and each purchase reclaims its own line.
    PERFORM sppoultrysupplierpaymentcash_sync(p_farmid, p_paymentid, p_reversedby);

    FOR v_row IN
        SELECT DISTINCT sa.documentid, sa.documenttype
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.paymentid = p_paymentid
          AND  sa.documenttype = 'RawMaterialPurchase'
    LOOP
        PERFORM sppoultryrawmaterialpurchasecash_sync(
            p_farmid, v_row.documentid, NULL, FALSE, p_reversedby);
    END LOOP;

    RETURN v_count;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. The two pay-balance endpoints, routed through the allocation system.
-- -----------------------------------------------------------------------------
-- The Purchases page and the Flock Batch page keep their existing endpoints and
-- their existing signatures; what changes is that a payment made there now
-- produces the same payment header + allocation a bulk payment does. That is the
-- whole point of the design: one shape, two entry points.
--
-- Behaviour deliberately preserved from migrations 130/151:
--   * an over-payment is CLAMPED to the outstanding balance, not rejected -- the
--     Purchases page has always worked that way and the UI relies on it;
--   * the expense row is written (now by the payment function);
--   * a purchase with no supplier is still payable.
--
-- Behaviour that changes: cash for a raw-material balance payment now leaves the
-- purchase's cash account through the payment's CashOut rather than by inflating
-- the purchase's own collapsed line. Same account, same amount, clearer trail.
-- Flock batches gain cash movement they never had -- but only for payments made
-- from here on; nothing historical is retro-posted.
CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialpurchase_paybalance(
    p_poultryrawmaterialpurchaseid integer, p_farmid text, p_amount numeric,
    p_paymentmethod text DEFAULT NULL::text,
    p_paymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone,
    p_createdby text DEFAULT NULL::text)
RETURNS numeric
LANGUAGE plpgsql
AS $function$
DECLARE
    v_total       numeric(14,2);
    v_paid        numeric(14,2);
    v_supplier    integer;
    v_name        text;
    v_acct        integer;
    v_outstanding numeric(14,2);
    v_amount      numeric(14,2) := p_amount;
    v_balance     numeric(14,2);
BEGIN
    SELECT pu.totalcost, pu.amountpaid, pu.supplierid, pu.suppliername, pu.poultrycashaccountid
    INTO   v_total, v_paid, v_supplier, v_name, v_acct
    FROM   poultryrawmaterialpurchases pu
    WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid AND pu.farmid = p_farmid
    LIMIT  1;

    IF v_total IS NULL THEN RAISE EXCEPTION 'Purchase not found for this company.'; END IF;
    v_outstanding := v_total - v_paid;
    IF (v_outstanding <= 0) THEN RAISE EXCEPTION 'This purchase has no outstanding balance.'; END IF;
    IF (v_amount IS NULL OR v_amount <= 0) THEN RAISE EXCEPTION 'Payment amount must be greater than 0.'; END IF;
    IF (v_amount > v_outstanding) THEN v_amount := v_outstanding; END IF;

    -- Late-link a purchase that was entered with a name but no supplier record.
    IF v_supplier IS NULL AND COALESCE(btrim(v_name), '') <> '' THEN
        v_supplier := fnpoultrysupplier_resolve(p_farmid, v_name, p_createdby);
        UPDATE poultryrawmaterialpurchases pu SET supplierid = v_supplier
        WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid AND pu.farmid = p_farmid;
    END IF;

    PERFORM sppoultrysupplierpayment_record(
        p_farmid, v_supplier, v_amount,
        jsonb_build_array(jsonb_build_object(
            'documenttype', 'RawMaterialPurchase',
            'documentid',   p_poultryrawmaterialpurchaseid,
            'amount',       v_amount)),
        p_paymentmethod, p_paymentdate, v_acct, NULL, NULL, 'PurchaseEntry', p_createdby);

    SELECT (pu.totalcost - pu.amountpaid)::numeric(14,2) INTO v_balance
    FROM   poultryrawmaterialpurchases pu
    WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid AND pu.farmid = p_farmid
    LIMIT  1;

    RETURN v_balance;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spmainflockbatch_paybalance(
    p_batchid integer, p_farmid text, p_amount numeric,
    p_paymentmethod text DEFAULT NULL::text,
    p_paymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone,
    p_createdby text DEFAULT NULL::text)
RETURNS numeric
LANGUAGE plpgsql
AS $function$
DECLARE
    v_total       numeric(18,2);
    v_paid        numeric(18,2);
    v_supplier    integer;
    v_outstanding numeric(18,2);
    v_amount      numeric(14,2) := p_amount;
    v_balance     numeric(18,2);
BEGIN
    SELECT b.totalcost, b.amountpaid, b.supplierid
    INTO   v_total, v_paid, v_supplier
    FROM   mainflockbatch b
    WHERE  b.batchid = p_batchid AND b.farmid = p_farmid;

    IF v_total IS NULL THEN RAISE EXCEPTION 'Flock batch not found for this company.'; END IF;
    v_outstanding := v_total - v_paid;
    IF v_outstanding <= 0 THEN RAISE EXCEPTION 'This flock batch has no outstanding balance.'; END IF;
    IF v_amount IS NULL OR v_amount <= 0 THEN RAISE EXCEPTION 'Payment amount must be greater than 0.'; END IF;
    IF v_amount > v_outstanding THEN v_amount := v_outstanding::numeric(14,2); END IF;

    -- No cash account: mainflockbatch has never had one, so this posts an
    -- expense and an allocation but no cash, exactly as before.
    PERFORM sppoultrysupplierpayment_record(
        p_farmid, v_supplier, v_amount,
        jsonb_build_array(jsonb_build_object(
            'documenttype', 'FlockBatch',
            'documentid',   p_batchid,
            'amount',       v_amount)),
        p_paymentmethod, p_paymentdate, NULL, NULL, NULL, 'PurchaseEntry', p_createdby);

    SELECT (b.totalcost - b.amountpaid)::numeric(18,2) INTO v_balance
    FROM   mainflockbatch b WHERE b.batchid = p_batchid AND b.farmid = p_farmid;

    RETURN v_balance;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 8. Reads -- the balances page.
-- -----------------------------------------------------------------------------
-- Both payable tables unioned into one shape. Everything downstream -- the
-- balances rollup, the open-documents list, the statement -- reads this, so
-- adding a third payable table later is a change in exactly one place.
CREATE OR REPLACE FUNCTION public.fnpoultrypayables(p_farmid text)
RETURNS TABLE(
    documenttype text,
    documentid   integer,
    supplierid   integer,
    docdate      date,
    label        text,
    reference    text,
    totalcost    numeric,
    amountpaid   numeric,
    balance      numeric,
    cashaccountid integer)
LANGUAGE sql
STABLE
AS $function$
    SELECT 'RawMaterialPurchase'::text, pu.poultryrawmaterialpurchaseid, pu.supplierid,
           pu.purchasedate::date, COALESCE(i.itemname, 'Raw material')::text,
           ('P' || pu.poultryrawmaterialpurchaseid::text)::text,
           pu.totalcost, pu.amountpaid,
           GREATEST(pu.totalcost - pu.amountpaid, 0)::numeric(14,2),
           pu.poultrycashaccountid
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
           NULL::integer
    FROM   mainflockbatch b
    WHERE  b.farmid = p_farmid;
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
        SELECT o.*, ((o.docdate + o.terms) < CURRENT_DATE) AS isoverdue
        FROM   openpurchases o
        WHERE  CASE COALESCE(p_status, 'All')
                    WHEN 'Partial' THEN o.amountpaid > 0
                    WHEN 'Unpaid'  THEN o.amountpaid = 0
                    WHEN 'Overdue' THEN (o.docdate + o.terms) < CURRENT_DATE
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
           (d.docdate + COALESCE(s.paymenttermsdays, 0))::date,
           GREATEST((CURRENT_DATE - d.docdate), 0)::integer,
           CASE WHEN d.amountpaid > 0 THEN 'Partially Paid' ELSE 'Unpaid' END::text,
           ((d.docdate + COALESCE(s.paymenttermsdays, 0)) < CURRENT_DATE),
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
                WHEN 'Overdue' THEN (d.docdate + COALESCE(s.paymenttermsdays, 0)) < CURRENT_DATE
                ELSE TRUE
           END
    ORDER  BY d.docdate, d.documenttype, d.documentid;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrysupplierbalancesummary(p_farmid text)
RETURNS TABLE(
    totalbalance       numeric,
    suppliersowed      integer,
    overduepayables    numeric,
    paymentsmadetoday  numeric,
    largestbalance     numeric,
    largestbalancesupplier text)
LANGUAGE sql
STABLE
AS $function$
    WITH b AS (SELECT * FROM sppoultrysupplierbalances(p_farmid))
    SELECT COALESCE(SUM(b.totalbalance), 0)::numeric(14,2),
           COUNT(*)::integer,
           COALESCE(SUM(b.overdueamount), 0)::numeric(14,2),
           COALESCE((SELECT SUM(sp.totalamount) FROM poultrysupplierpayments sp
                     WHERE sp.farmid = p_farmid AND sp.status = 'Posted'
                       AND sp.paymentdate::date = CURRENT_DATE), 0)::numeric(14,2),
           COALESCE(MAX(b.totalbalance), 0)::numeric(14,2),
           (SELECT b2.suppliername FROM b b2 ORDER BY b2.totalbalance DESC LIMIT 1)
    FROM b;
$function$;

-- -----------------------------------------------------------------------------
-- 9. Supplier statement.
-- -----------------------------------------------------------------------------
-- Derived, like the customer one. A purchase paid in full at the counter emits
-- its credit line explicitly so the running balance behaves.
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
        SELECT d.docdate, 'Purchase'::text, d.reference, d.label,
               d.totalcost::numeric(14,2), 0::numeric(14,2),
               d.documenttype, d.documentid, 1, 1
        FROM   fnpoultrypayables(p_farmid) d
        WHERE  d.supplierid = p_supplierid
          AND  (p_from IS NULL OR d.docdate >= p_from)
          AND  (p_to   IS NULL OR d.docdate <= p_to)

        UNION ALL

        -- Paid at the counter: amountpaid with no allocation behind it.
        SELECT d.docdate, 'Payment'::text, d.reference, 'Paid at time of purchase'::text,
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
-- 10. Payment history + allocation detail.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrysupplierpayment_history(
    p_farmid text,
    p_supplierid integer DEFAULT NULL::integer,
    p_documenttype text DEFAULT NULL::text,
    p_documentid integer DEFAULT NULL::integer,
    p_from date DEFAULT NULL::date,
    p_to date DEFAULT NULL::date)
RETURNS TABLE(
    paymentid       integer,
    supplierid      integer,
    suppliername    text,
    paymentdate     timestamp without time zone,
    totalamount     numeric,
    paymentmethod   text,
    referenceno     text,
    notes           text,
    sourcetype      text,
    status          text,
    allocationcount integer,
    poultrycashaccountid integer,
    createdby       text,
    reversedby      text,
    reversedat      timestamp without time zone,
    reversalreason  text)
LANGUAGE sql
STABLE
AS $function$
    SELECT sp.poultrysupplierpaymentid, sp.supplierid, s.name::text, sp.paymentdate,
           sp.totalamount, sp.paymentmethod, sp.referenceno, sp.notes, sp.sourcetype, sp.status,
           (SELECT COUNT(*)::integer FROM supplierpaymentallocation sa
            WHERE sa.farmid = sp.farmid AND sa.module = 'poultry'
              AND sa.paymentid = sp.poultrysupplierpaymentid),
           sp.poultrycashaccountid, sp.createdby, sp.reversedby, sp.reversedat, sp.reversalreason
    FROM   poultrysupplierpayments sp
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  (p_supplierid IS NULL OR sp.supplierid = p_supplierid)
      AND  (p_from IS NULL OR sp.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR sp.paymentdate::date <= p_to)
      AND  (p_documentid IS NULL OR EXISTS (
              SELECT 1 FROM supplierpaymentallocation sa
              WHERE sa.farmid = sp.farmid AND sa.module = 'poultry'
                AND sa.paymentid = sp.poultrysupplierpaymentid
                AND sa.documentid = p_documentid
                AND (p_documenttype IS NULL OR sa.documenttype = p_documenttype)))
    ORDER  BY sp.paymentdate DESC, sp.poultrysupplierpaymentid DESC;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrysupplierpayment_allocations(
    p_farmid text, p_paymentid integer)
RETURNS TABLE(
    allocationid          integer,
    paymentid             integer,
    documenttype          text,
    documentid            integer,
    reference             text,
    docdate               date,
    label                 text,
    documenttotal         numeric,
    amountapplied         numeric,
    documentbalancebefore numeric,
    documentbalanceafter  numeric,
    status                text)
LANGUAGE sql
STABLE
AS $function$
    SELECT sa.allocationid, sa.paymentid, sa.documenttype, sa.documentid,
           d.reference, d.docdate, d.label, d.totalcost,
           sa.amountapplied, sa.documentbalancebefore, sa.documentbalanceafter, sa.status
    FROM   supplierpaymentallocation sa
    LEFT   JOIN fnpoultrypayables(p_farmid) d
           ON d.documenttype = sa.documenttype AND d.documentid = sa.documentid
    WHERE  sa.farmid = p_farmid AND sa.module = 'poultry' AND sa.paymentid = p_paymentid
    ORDER  BY d.docdate, sa.documenttype, sa.documentid;
$function$;

COMMIT;

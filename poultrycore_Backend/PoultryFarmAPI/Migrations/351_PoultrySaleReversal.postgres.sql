-- =============================================================================
-- 351  Posted sales are immutable: Sale Reversal, Customer Credit, Refunds
--      (poultry)                                    (requires 222/223/239, 341-344)
-- =============================================================================
--
-- WHY
-- ---
-- A sale posts the moment it is saved (stock out, revenue, and -- when paid --
-- a payment, its allocation and its cash-in). Until now it could then be
-- edited or deleted like an ordinary row, and neither path kept the money
-- side in step:
--
--   * Delete removed the sale row and its stock movement, but its payment
--     stayed Posted, the allocation stayed Posted and the CustomerPayment
--     cash-in stayed in the account -- Cash Flow still counted the receipt.
--   * Edit overwrote every column, `paid` included. Paid -> Pending on a sale
--     with a payment left it reading Paid; on a walk-in it silently deleted the
--     residual cash-in; Pending -> Paid posted cash with no payment record.
--
-- THE RULE FROM HERE ON
-- ---------------------
-- Once posted, a sale's financial and inventory content does not change.
-- A wrong sale is REVERSED (and, if needed, entered again as a corrected sale
-- linked to it). Nothing is deleted: the sale row, its stock rows, its
-- payments and their allocations all stay, and the reversal adds the opposite
-- entries.
--
-- FOUR DIFFERENT EVENTS, NOT ONE "DELETE"
-- ---------------------------------------
--   Sale reversal     undoes the SALE: revenue, receivable, stock, and every
--                     allocation applied to it. Says nothing by itself about
--                     money leaving the business.
--   Payment reversal  undoes a RECEIPT that should never have existed. Money
--                     Out on the original account (classified as a payment
--                     reversal, never as an expense).
--   Customer credit   money received and kept, applied to no active sale yet.
--                     Applying it to a sale is an allocation only: no new
--                     payment, no Money In, no cash movement.
--   Customer refund   money genuinely handed back. Money Out from whichever
--                     account the business chooses. No stock moves.
-- (A partial Sales Return is a fifth event and is NOT built here; a reversal
-- always undoes the whole sale.)
--
-- MONEY ON A REVERSED SALE
-- ------------------------
-- Every Posted allocation applied to the sale is reversed. What happens to the
-- money behind each one depends on where the payment came from:
--
--   Sale-generated and exclusive (SaleEntry, all of its rows on this sale)
--       the user chooses:  KeepAsCredit   -- payment stays Posted, cash
--                                            unchanged, becomes customer credit
--                          ReversePayment -- payment Reversed, CashOut on the
--                                            ORIGINAL account
--   Anything else (Customer Balances bulk payment, a payment that also pays
--   other sales, credit applied from another payment)
--       always returned to credit. Reversing one sale never reverses a payment
--       that belongs to the customer-payment event.
--   Money "received at the sale" with no payment row (walk-ins, and paid
--   sales from before 223) is first written as the SaleEntry payment it
--   should always have been -- same amount, same account, same date, the
--   cash ledger nets to the same balance -- and is then handled as above.
--   A walk-in has nobody to hold credit for, so its money can only be reversed.
--
-- CUSTOMER CREDIT IS DERIVED, NOT STORED
-- --------------------------------------
--   credit of a payment row = amount - Posted allocations - Posted refund lines
--   (a Posted payment row with NO allocation row at all is pre-222 data whose
--   allocation is implicit -- it holds no credit).
--
-- CASH LEDGER: PAYMENT REVERSALS ARE NOW APPEND-ONLY
-- --------------------------------------------------
-- sppoultrycustomerpaymentcash_sync used to delete a reversed group's CashIn,
-- so the receipt vanished from the account history. It now keeps the CashIn
-- for everything the group ever received and adds a CashOut
-- ('CustomerPaymentReversal') for what was reversed, dated on the business
-- day of the reversal. The account balance is exactly what it was before.
--
-- HOW THE LOCK IS ENFORCED
-- ------------------------
--   * spsale_update accepts a change to the description only, and refuses
--     anything that would move money or stock (with the reason).
--   * spsale_delete refuses a posted sale.
--   * trg_sale_postedguard refuses, at the table, a change to any column that
--     defines the sale, a delete, and any change to a Reversed sale. It lets
--     through: the transaction that INSERTED the sale (so creating a sale can
--     still stamp its egg class, account and payment in the same unit of
--     work -- SaleService.Insert is one transaction from 351 on), the reversal
--     itself (GUC poultry.sale_system), flock closeout, and sales owned by a
--     delivery / driver return, which those documents manage themselves.
--   paid / amountpaid / poultrycashaccountid stay writable: they are
--   projections that sppoultrysale_recompute maintains from the allocations.
--
-- DEPLOY ORDER: API first, then this migration. The previous API saved a sale
-- in several transactions, and the guard would refuse its egg-class step.
--
-- Readers (revenue, balances, reports, Cash Flow) learn about Reversed in 352.
-- Idempotent. PostgreSQL. Dry-run with database/apply-sale-reversal.ps1.
-- =============================================================================

BEGIN;

-- ------------------------------------------------------------------ 1. schema --

ALTER TABLE public.sale ADD COLUMN IF NOT EXISTS status         text      NOT NULL DEFAULT 'Posted';
ALTER TABLE public.sale ADD COLUMN IF NOT EXISTS reversedat     timestamp NULL;
ALTER TABLE public.sale ADD COLUMN IF NOT EXISTS reversedby     text      NULL;
ALTER TABLE public.sale ADD COLUMN IF NOT EXISTS reversalreason text      NULL;
ALTER TABLE public.sale ADD COLUMN IF NOT EXISTS salereversalid integer   NULL;
ALTER TABLE public.sale ADD COLUMN IF NOT EXISTS correctssaleid integer   NULL;

DO $s$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_sale_status') THEN
        ALTER TABLE public.sale ADD CONSTRAINT ck_sale_status CHECK (status IN ('Posted', 'Reversed'));
    END IF;
END $s$;

CREATE INDEX IF NOT EXISTS ix_sale_farm_status  ON public.sale (farmid, status);
CREATE INDEX IF NOT EXISTS ix_sale_correctssale ON public.sale (correctssaleid) WHERE correctssaleid IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.poultrysalereversals (
    salereversalid   serial        PRIMARY KEY,
    farmid           text          NOT NULL,
    reversalnumber   text          NOT NULL,
    saleids          integer[]     NOT NULL,
    salegroupno      text          NULL,
    customerid       integer       NULL,
    customername     text          NULL,
    saledate         date          NULL,
    reasoncode       text          NULL,
    reason           text          NOT NULL,
    businessdate     date          NOT NULL,
    occurredat       timestamp     NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    reversedby       text          NULL,
    paymenthandling  text          NOT NULL,
    totalamount      numeric(14,2) NOT NULL DEFAULT 0,
    paidamount       numeric(14,2) NOT NULL DEFAULT 0,
    outstandingamount numeric(14,2) NOT NULL DEFAULT 0,
    creditcreated    numeric(14,2) NOT NULL DEFAULT 0,
    cashreversed     numeric(14,2) NOT NULL DEFAULT 0,
    correctionsaleid integer       NULL,
    idempotencykey   text          NULL,
    snapshot         jsonb         NULL,
    CONSTRAINT ck_poultrysalereversals_handling
        CHECK (paymenthandling IN ('None', 'KeepAsCredit', 'ReversePayment', 'Mixed'))
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrysalereversals_number ON public.poultrysalereversals (farmid, reversalnumber);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrysalereversals_idem   ON public.poultrysalereversals (farmid, idempotencykey) WHERE idempotencykey IS NOT NULL;
CREATE INDEX        IF NOT EXISTS ix_poultrysalereversals_sales  ON public.poultrysalereversals USING gin (saleids);

-- What happened to each payment on the reversed sale.
CREATE TABLE IF NOT EXISTS public.poultrysalereversalpayments (
    salereversalpaymentid serial        PRIMARY KEY,
    salereversalid        integer       NOT NULL REFERENCES public.poultrysalereversals (salereversalid),
    farmid                text          NOT NULL,
    paymentgroupid        uuid          NOT NULL,
    paymentnumbers        text          NULL,
    sourcetype            text          NULL,
    amount                numeric(14,2) NOT NULL,
    action                text          NOT NULL,
    recordedatreversal    boolean       NOT NULL DEFAULT FALSE,
    CONSTRAINT ck_poultrysalereversalpayments_action CHECK (action IN ('KeepAsCredit', 'ReversePayment'))
);
CREATE INDEX IF NOT EXISTS ix_poultrysalereversalpayments_rev ON public.poultrysalereversalpayments (salereversalid);

-- Money handed back to a customer out of their credit.
CREATE TABLE IF NOT EXISTS public.poultrycustomerrefunds (
    refundid                 serial        PRIMARY KEY,
    farmid                   text          NOT NULL,
    refundnumber             text          NOT NULL,
    customerid               integer       NOT NULL,
    amount                   numeric(14,2) NOT NULL CHECK (amount > 0),
    refunddate               date          NOT NULL,
    poultrycashaccountid     integer       NOT NULL,
    paymentmethod            text          NULL,
    reason                   text          NOT NULL,
    status                   text          NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),
    poultrycashtransactionid integer       NULL,
    createdby                text          NULL,
    createdat                timestamp     NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrycustomerrefunds_number ON public.poultrycustomerrefunds (farmid, refundnumber);
CREATE INDEX        IF NOT EXISTS ix_poultrycustomerrefunds_cust   ON public.poultrycustomerrefunds (farmid, customerid);

-- Which payments the refunded money came out of.
CREATE TABLE IF NOT EXISTS public.poultrycustomerrefundlines (
    refundlineid     serial        PRIMARY KEY,
    refundid         integer       NOT NULL REFERENCES public.poultrycustomerrefunds (refundid),
    farmid           text          NOT NULL,
    poultrypaymentid integer       NOT NULL,
    amount           numeric(14,2) NOT NULL CHECK (amount > 0)
);
CREATE INDEX IF NOT EXISTS ix_poultrycustomerrefundlines_pay ON public.poultrycustomerrefundlines (farmid, poultrypaymentid);

-- ------------------------------------------------------- 2. drop what changes --
DO $d$
DECLARE r record;
BEGIN
    FOR r IN SELECT p.oid::regprocedure AS sig
             FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE  n.nspname = 'public'
               AND  p.proname IN ('fnpoultrysale_isgenerated', 'fnpoultrypayment_unapplied',
                                  'fnpoultrycustomer_credit', 'fnpoultrysale_allocated',
                                  'fnpoultrypaymentgroupaccount_any', 'fnpoultry_businessdateof',
                                  'fnpoultrysale_document', 'fnpoultrysale_reversalstate',
                                  'sppoultrysale_reversalpreview', 'sppoultrysale_reverse',
                                  'sppoultrysale_reversalget', 'sppoultrysale_linkcorrection',
                                  'sppoultrycustomercredit_list', 'sppoultrycustomercredit_apply', 'sppoultrycustomercredit_summary',
                                  'sppoultrycustomerrefund_record', 'sppoultrycustomerrefund_list',
                                  'spsale_getall', 'spsale_getbyid', 'spsale_getbyflock',
                                  'trg_sale_postedguard_fn')
    LOOP EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE'; END LOOP;
END $d$;

-- ------------------------------------------------------------- 3. helpers --

-- Sales a delivery reconciliation or a driver return generated. Those documents
-- create and remove their own sales; the sale screens leave them alone.
CREATE FUNCTION public.fnpoultrysale_isgenerated(p_description text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $f$
    SELECT COALESCE(p_description ILIKE 'Driver return #%' OR p_description ILIKE 'Delivery #%', FALSE);
$f$;

-- A UTC timestamp as the company's business date.
CREATE FUNCTION public.fnpoultry_businessdateof(p_farmid text, p_utc timestamp)
RETURNS date
LANGUAGE sql
STABLE
AS $f$
    SELECT ((p_utc AT TIME ZONE 'UTC') AT TIME ZONE public.fncompany_timezone(p_farmid))::date;
$f$;

-- What a payment row still holds unapplied: the customer's credit from it.
CREATE FUNCTION public.fnpoultrypayment_unapplied(p_farmid text, p_paymentid integer)
RETURNS numeric
LANGUAGE sql
STABLE
AS $f$
    SELECT CASE
             WHEN COALESCE(pp.status, 'Posted') <> 'Posted' THEN 0
             -- Pre-222 payment with no allocation row: implicitly applied to its sale.
             WHEN NOT EXISTS (SELECT 1 FROM customerpaymentallocation ca
                              WHERE ca.module = 'poultry' AND ca.paymentid = pp.poultrypaymentid
                                AND ca.farmid = pp.farmid) THEN 0
             ELSE GREATEST(
                    COALESCE(pp.amount, 0)
                  - COALESCE((SELECT SUM(ca.amountapplied) FROM customerpaymentallocation ca
                              WHERE ca.module = 'poultry' AND ca.paymentid = pp.poultrypaymentid
                                AND ca.farmid = pp.farmid AND ca.status = 'Posted'), 0)
                  - COALESCE((SELECT SUM(rl.amount) FROM poultrycustomerrefundlines rl
                              JOIN poultrycustomerrefunds r ON r.refundid = rl.refundid
                              WHERE rl.poultrypaymentid = pp.poultrypaymentid AND rl.farmid = pp.farmid
                                AND r.status = 'Posted'), 0), 0)
           END::numeric(14,2)
    FROM   poultrypayments pp
    WHERE  pp.poultrypaymentid = p_paymentid AND pp.farmid = p_farmid;
$f$;

CREATE FUNCTION public.fnpoultrycustomer_credit(p_farmid text, p_customerid integer)
RETURNS numeric
LANGUAGE sql
STABLE
AS $f$
    SELECT COALESCE(SUM(public.fnpoultrypayment_unapplied(p_farmid, pp.poultrypaymentid)), 0)::numeric(14,2)
    FROM   poultrypayments pp
    WHERE  pp.farmid = p_farmid AND pp.customerid = p_customerid
      AND  COALESCE(pp.status, 'Posted') = 'Posted';
$f$;

-- What has been applied to a sale: its Posted allocations, plus any pre-222
-- payment on it that has no allocation row at all. This is the authority
-- sale.amountpaid is projected from.
CREATE FUNCTION public.fnpoultrysale_allocated(p_farmid text, p_saleid integer)
RETURNS numeric
LANGUAGE sql
STABLE
AS $f$
    SELECT (COALESCE((SELECT SUM(ca.amountapplied) FROM customerpaymentallocation ca
                      WHERE ca.module = 'poultry' AND ca.saleid = p_saleid
                        AND ca.farmid = p_farmid AND ca.status = 'Posted'), 0)
          + COALESCE((SELECT SUM(pp.amount) FROM poultrypayments pp
                      WHERE pp.saleid = p_saleid AND pp.farmid = p_farmid
                        AND COALESCE(pp.status, 'Posted') = 'Posted'
                        AND NOT EXISTS (SELECT 1 FROM customerpaymentallocation ca
                                        WHERE ca.module = 'poultry' AND ca.paymentid = pp.poultrypaymentid
                                          AND ca.farmid = pp.farmid)), 0))::numeric(14,2);
$f$;

-- The account a payment group's money went to, whatever the rows' status now.
-- Same precedence as fnpoultrypaymentgroupaccount (the payment's own account,
-- else the sale's), which only looks at Posted rows.
CREATE FUNCTION public.fnpoultrypaymentgroupaccount_any(p_farmid text, p_paymentgroupid uuid)
RETURNS integer
LANGUAGE sql
STABLE
AS $f$
    SELECT a.poultrycashaccountid
    FROM   poultrycashaccounts a
    WHERE  a.farmid = p_farmid
      AND  a.poultrycashaccountid = (
            SELECT COALESCE(MIN(pp.poultrycashaccountid), MIN(s.poultrycashaccountid))
            FROM   poultrypayments pp
            LEFT   JOIN sale s ON s.saleid = pp.saleid AND s.farmid = pp.farmid
            WHERE  pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid)
    LIMIT  1;
$f$;

-- The sale rows that make up one sale as the user sees it: a multi-size egg
-- sale is several rows sharing an SG number (343) and is reversed as a whole.
CREATE FUNCTION public.fnpoultrysale_document(p_farmid text, p_saleid integer)
RETURNS integer[]
LANGUAGE sql
STABLE
AS $f$
    SELECT COALESCE(
             (SELECT array_agg(o.saleid ORDER BY o.saleid)
              FROM   sale s
              JOIN   sale o ON o.farmid = s.farmid AND o.salegroupno = s.salegroupno
              WHERE  s.saleid = p_saleid AND s.farmid = p_farmid
                AND  NULLIF(btrim(COALESCE(s.salegroupno, '')), '') IS NOT NULL),
             (SELECT ARRAY[s.saleid] FROM sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid));
$f$;

-- ------------------------------------------- 4. projections and cash syncs --

-- sale.amountpaid / paid are projections of the allocations. A Reversed sale
-- is frozen: its row is history and is never recomputed, but the cash of its
-- payment groups still is (that is how a payment reversal posts its CashOut).
CREATE OR REPLACE FUNCTION public.sppoultrysale_recompute(p_farmid text, p_saleid integer, p_cashaccountid integer DEFAULT NULL::integer, p_createdby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_total   numeric(14,2);
    v_acct    integer;
    v_status  text;
    v_sum     numeric(14,2);
    v_newpaid boolean;
    v_group   uuid;
BEGIN
    SELECT s.totalamount, s.poultrycashaccountid, s.status INTO v_total, v_acct, v_status
    FROM   sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid LIMIT 1;

    IF v_total IS NULL THEN RETURN; END IF;

    IF v_status = 'Posted' THEN
        v_sum := public.fnpoultrysale_allocated(p_farmid, p_saleid);
        v_newpaid := COALESCE(v_sum >= v_total, FALSE);

        UPDATE sale s SET amountpaid = v_sum, paid = v_newpaid
        WHERE  s.saleid = p_saleid AND s.farmid = p_farmid
          AND  (s.amountpaid IS DISTINCT FROM v_sum OR s.paid IS DISTINCT FROM v_newpaid);
    END IF;

    -- The payment events first, so the residual below is computed against a
    -- ledger that already holds them.
    FOR v_group IN
        SELECT DISTINCT pp.paymentgroupid
        FROM   poultrypayments pp
        WHERE  pp.saleid = p_saleid AND pp.farmid = p_farmid
          AND  pp.paymentgroupid IS NOT NULL
    LOOP
        PERFORM sppoultrycustomerpaymentcash_sync(p_farmid, v_group, p_createdby);
    END LOOP;

    IF v_status = 'Posted' THEN
        PERFORM sppoultrysalecash_sync(p_farmid, p_saleid, COALESCE(p_cashaccountid, v_acct),
                                       v_total, v_newpaid, 'Sale payment', p_createdby);
    END IF;
END;
$function$;

-- Unchanged from 239 except: a Reversed sale's cash is frozen, and "already
-- accounted for by a payment" now reads the allocations, so credit applied
-- from another payment is not posted again as fresh money at the counter.
CREATE OR REPLACE FUNCTION public.sppoultrysalecash_sync(p_farmid text, p_saleid integer, p_poultrycashaccountid integer DEFAULT NULL::integer, p_amount numeric DEFAULT 0, p_paid boolean DEFAULT true, p_description text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_bal      numeric(14,2);
    v_received numeric(14,2);
    v_onpay    numeric(14,2);
    v_post     numeric(14,2);
BEGIN
    IF EXISTS (SELECT 1 FROM sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid
                                      AND s.status = 'Reversed') THEN
        RETURN;
    END IF;

    -- Reverse any existing sale cash tx (restore balances, then delete them).
    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - t.net, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT ct.poultrycashaccountid, SUM(ct.amount) AS net
        FROM   poultrycashtransactions ct
        WHERE  ct.sourcetype = 'Sale' AND ct.sourceid = p_saleid AND ct.farmid = p_farmid
        GROUP  BY ct.poultrycashaccountid
    ) t
    WHERE  t.poultrycashaccountid = a.poultrycashaccountid
      AND  a.farmid = p_farmid;

    DELETE FROM poultrycashtransactions ct
    WHERE  ct.sourcetype = 'Sale' AND ct.sourceid = p_saleid AND ct.farmid = p_farmid;

    UPDATE sale s SET poultrycashaccountid = p_poultrycashaccountid
    WHERE  s.saleid = p_saleid AND s.farmid = p_farmid
      AND  s.poultrycashaccountid IS DISTINCT FROM p_poultrycashaccountid;

    IF COALESCE(p_paid, TRUE) THEN
        v_received := COALESCE(p_amount, 0);
    ELSE
        SELECT COALESCE(s.amountpaid, 0) INTO v_received
        FROM   sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid LIMIT 1;
        IF COALESCE(p_amount, 0) > 0 THEN
            v_received := LEAST(COALESCE(v_received, 0), p_amount);
        END IF;
    END IF;

    -- What the payment ledger already accounts for. The sale's own payments
    -- count when their group reached an account (the 239 rule); credit applied
    -- from another payment always counts -- that money is already in the
    -- ledger, wherever its payment put it.
    SELECT COALESCE(SUM(ca.amountapplied), 0)::numeric(14,2) INTO v_onpay
    FROM   customerpaymentallocation ca
    JOIN   poultrypayments pp ON pp.poultrypaymentid = ca.paymentid AND pp.farmid = ca.farmid
    WHERE  ca.module = 'poultry' AND ca.saleid = p_saleid AND ca.farmid = p_farmid
      AND  ca.status = 'Posted'
      AND  (pp.saleid <> p_saleid
            OR fnpoultrypaymentgroupaccount(p_farmid, pp.paymentgroupid) IS NOT NULL);

    v_onpay := v_onpay + COALESCE((
        SELECT SUM(pp.amount)
        FROM   poultrypayments pp
        WHERE  pp.saleid = p_saleid AND pp.farmid = p_farmid
          AND  COALESCE(pp.status, 'Posted') = 'Posted'
          AND  fnpoultrypaymentgroupaccount(p_farmid, pp.paymentgroupid) IS NOT NULL
          AND  NOT EXISTS (SELECT 1 FROM customerpaymentallocation ca
                           WHERE ca.module = 'poultry' AND ca.paymentid = pp.poultrypaymentid
                             AND ca.farmid = pp.farmid)), 0);

    v_post := GREATEST(ROUND(COALESCE(v_received, 0) - COALESCE(v_onpay, 0), 2), 0);

    IF (p_poultrycashaccountid IS NOT NULL AND v_post > 0
        AND EXISTS (SELECT 1 FROM poultrycashaccounts a
                    WHERE a.poultrycashaccountid = p_poultrycashaccountid AND a.farmid = p_farmid)) THEN

        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance + v_post, updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = p_poultrycashaccountid AND a.farmid = p_farmid;

        SELECT a.currentbalance INTO v_bal
        FROM   poultrycashaccounts a WHERE a.poultrycashaccountid = p_poultrycashaccountid LIMIT 1;

        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, p_poultrycashaccountid, (now() at time zone 'utc'), 'CashIn', 'Sale', p_saleid,
             v_post, v_bal, COALESCE(p_description, 'Sale receipt'), p_createdby, p_createdby,
             (now() at time zone 'utc'));
    END IF;
END;
$function$;

-- One payment group's cash. The CashIn is everything the group ever received
-- (Posted and Reversed rows), dated when it arrived; a separate CashOut
-- ('CustomerPaymentReversal') carries what was reversed, dated on the business
-- day of the reversal. Net = the Posted rows, exactly as before 351 -- but the
-- receipt no longer disappears from the account's history when it is reversed.
CREATE OR REPLACE FUNCTION public.sppoultrycustomerpaymentcash_sync(p_farmid text, p_paymentgroupid uuid, p_createdby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_acct     integer;
    v_received numeric(14,2);
    v_reversed numeric(14,2);
    v_date     timestamp;
    v_revat    timestamp;
    v_srcid    integer;
    v_name     text;
    v_number   text;
    v_bal      numeric(14,2);
BEGIN
    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - t.net, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT ct.poultrycashaccountid, SUM(ct.amount) AS net
        FROM   poultrycashtransactions ct
        WHERE  ct.sourcetype IN ('CustomerPayment', 'CustomerPaymentReversal')
          AND  ct.paymentgroupid = p_paymentgroupid
          AND  ct.farmid = p_farmid
        GROUP  BY ct.poultrycashaccountid
    ) t
    WHERE  t.poultrycashaccountid = a.poultrycashaccountid
      AND  a.farmid = p_farmid;

    DELETE FROM poultrycashtransactions ct
    WHERE  ct.sourcetype IN ('CustomerPayment', 'CustomerPaymentReversal')
      AND  ct.paymentgroupid = p_paymentgroupid
      AND  ct.farmid = p_farmid;

    SELECT COALESCE(SUM(pp.amount), 0)::numeric(14,2),
           COALESCE(SUM(pp.amount) FILTER (WHERE COALESCE(pp.status, 'Posted') = 'Reversed'), 0)::numeric(14,2),
           MIN(pp.paymentdate),
           MAX(pp.reversedat),
           MIN(pp.poultrypaymentid),
           MIN(c.name)::text,
           MIN(pp.paymentnumber)::text
    INTO   v_received, v_reversed, v_date, v_revat, v_srcid, v_name, v_number
    FROM   poultrypayments pp
    LEFT   JOIN customer c ON c.customerid = pp.customerid AND c.farmid = pp.farmid
    WHERE  pp.paymentgroupid = p_paymentgroupid
      AND  pp.farmid = p_farmid;

    IF COALESCE(v_received, 0) <= 0 THEN RETURN; END IF;

    v_acct := fnpoultrypaymentgroupaccount_any(p_farmid, p_paymentgroupid);
    IF v_acct IS NULL THEN RETURN; END IF;

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance + v_received, updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycashaccountid = v_acct AND a.farmid = p_farmid;
    SELECT a.currentbalance INTO v_bal FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct LIMIT 1;

    INSERT INTO poultrycashtransactions
        (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
         paymentgroupid, amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
    VALUES
        (p_farmid, v_acct, COALESCE(v_date, (now() at time zone 'utc')), 'CashIn',
         'CustomerPayment', v_srcid, p_paymentgroupid, v_received, v_bal,
         'Customer payment' || COALESCE(' from ' || NULLIF(btrim(v_name), ''), ''),
         p_createdby, p_createdby, (now() at time zone 'utc'));

    IF v_reversed > 0 THEN
        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance - v_reversed, updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = v_acct AND a.farmid = p_farmid;
        SELECT a.currentbalance INTO v_bal FROM poultrycashaccounts a WHERE a.poultrycashaccountid = v_acct LIMIT 1;

        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             paymentgroupid, amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_acct,
             COALESCE(fnpoultry_businessdateof(p_farmid, v_revat), fncompany_businessdate(p_farmid))::timestamp,
             'CashOut', 'CustomerPaymentReversal', v_srcid, p_paymentgroupid, -v_reversed, v_bal,
             'Payment reversal' || COALESCE(' ' || v_number, '') || COALESCE(' - ' || NULLIF(btrim(v_name), ''), ''),
             p_createdby, p_createdby, (now() at time zone 'utc'));
    END IF;
END;
$function$;

-- A Reversed sale's egg movement is history: never deleted or re-posted again
-- (the reversal posts its own 'Sale Reversal' row beside it).
CREATE OR REPLACE FUNCTION public.sppoultryeggstock_syncforsale(p_farmid text, p_saleid integer, p_qtysold numeric, p_createdby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_egg   integer;
    v_class integer;
BEGIN
    IF EXISTS (SELECT 1 FROM sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid
                                      AND s.status = 'Reversed') THEN
        RETURN;
    END IF;

    DELETE FROM poultrystocktransactions t
    WHERE t.farmid = p_farmid AND t.txntype = 'Sale' AND t.relatedid = p_saleid;

    IF (COALESCE(p_qtysold, 0) <= 0) THEN RETURN; END IF;

    IF EXISTS (SELECT 1 FROM sale s
               WHERE s.saleid = p_saleid AND s.farmid = p_farmid
                 AND (s.saledescription ILIKE 'Driver return #%' OR s.saledescription ILIKE 'Delivery #%')) THEN
        RETURN;
    END IF;

    SELECT s.poultryproductid INTO v_class
    FROM   sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid;

    IF v_class IS NOT NULL AND public.fnpoultry_iseggclass(p_farmid, v_class) THEN
        v_egg := v_class;
    ELSE
        v_egg := public.fnpoultry_unsortedeggproduct(p_farmid);
    END IF;

    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby)
    VALUES (p_farmid, v_egg, 'Sale', -(p_qtysold::numeric(14,3)), NULL, p_saleid, 'Egg sale', p_createdby);
END;
$function$;

-- ------------------------------------------------------- 5. the lock --

-- An edit may change the description and nothing else. Same signature as 223,
-- so callers built against it keep working and get a clear refusal instead.
CREATE OR REPLACE FUNCTION public.spsale_update(p_userid text, p_farmid text, p_saleid integer, p_saledate timestamp without time zone, p_product text, p_quantity numeric, p_unitprice numeric, p_totalamount numeric, p_paymentmethod text DEFAULT NULL::text, p_customername text DEFAULT NULL::text, p_flockid integer DEFAULT NULL::integer, p_saledescription text DEFAULT NULL::text, p_paid boolean DEFAULT true, p_size text DEFAULT NULL::text, p_customerid integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_s       sale%ROWTYPE;
    v_changed text[] := ARRAY[]::text[];
BEGIN
    SELECT * INTO v_s FROM sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sale #% was not found for this company.', p_saleid;
    END IF;
    IF v_s.status = 'Reversed' THEN
        RAISE EXCEPTION 'Sale #% has been reversed and can no longer be changed.', p_saleid;
    END IF;

    IF p_saledate IS NOT NULL AND p_saledate::date <> v_s.saledate THEN v_changed := array_append(v_changed, 'date'::text); END IF;
    IF btrim(COALESCE(p_product, '')) IS DISTINCT FROM btrim(COALESCE(v_s.product, '')) THEN v_changed := array_append(v_changed, 'product'::text); END IF;
    IF p_quantity IS NOT NULL AND p_quantity <> v_s.quantity THEN v_changed := array_append(v_changed, 'quantity'::text); END IF;
    IF p_unitprice IS NOT NULL AND p_unitprice <> v_s.unitprice THEN v_changed := array_append(v_changed, 'price'::text); END IF;
    IF p_totalamount IS NOT NULL AND p_totalamount <> v_s.totalamount THEN v_changed := array_append(v_changed, 'total'::text); END IF;
    IF NULLIF(btrim(COALESCE(p_paymentmethod, '')), '') IS DISTINCT FROM NULLIF(btrim(COALESCE(v_s.paymentmethod, '')), '')
       THEN v_changed := array_append(v_changed, 'payment method'::text); END IF;
    IF lower(NULLIF(btrim(COALESCE(p_customername, '')), '')) IS DISTINCT FROM lower(NULLIF(btrim(COALESCE(v_s.customername, '')), ''))
       OR (p_customerid IS NOT NULL AND p_customerid IS DISTINCT FROM v_s.customerid)
       THEN v_changed := array_append(v_changed, 'customer'::text); END IF;
    IF p_flockid IS DISTINCT FROM v_s.flockid THEN v_changed := array_append(v_changed, 'flock'::text); END IF;
    IF COALESCE(p_paid, TRUE) IS DISTINCT FROM COALESCE(v_s.paid, TRUE) THEN v_changed := array_append(v_changed, 'paid / pending'::text); END IF;

    IF array_length(v_changed, 1) > 0 THEN
        RAISE EXCEPTION 'Sale #% is posted, so its % can no longer be changed. Reverse the sale, or use Correct Sale to reverse it and enter it again.',
              p_saleid, array_to_string(v_changed, ', ');
    END IF;

    UPDATE sale s
    SET    saledescription = p_saledescription,
           updatedby       = p_userid,
           dateupdated     = (now() at time zone 'utc')
    WHERE  s.saleid = p_saleid AND s.farmid = p_farmid
      AND  s.saledescription IS DISTINCT FROM p_saledescription;
END;
$function$;

-- Kept for the documents that own their sales (delivery, driver return) and for
-- discarding a sale a failed workflow created moments ago in the same request
-- (flock closeout's compensation, GUC poultry.sale_discard). A user's posted
-- sale is reversed, never deleted.
CREATE OR REPLACE FUNCTION public.spsale_delete(p_farmid text, p_userid text, p_saleid integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_s sale%ROWTYPE;
BEGIN
    SELECT * INTO v_s FROM sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid;
    IF NOT FOUND THEN RETURN; END IF;

    IF NOT (fnpoultrysale_isgenerated(v_s.saledescription)
            OR position(',' || p_saleid::text || ',' IN COALESCE(current_setting('poultry.sale_fresh', true), '')) > 0
            OR current_setting('poultry.sale_discard', true) = 'on'
            OR current_setting('poultry.sale_system', true) = 'on') THEN
        RAISE EXCEPTION 'Sale #% is posted and cannot be deleted. Reverse it instead -- the sale stays in the history and its stock and money are undone.', p_saleid;
    END IF;
    IF current_setting('poultry.sale_discard', true) = 'on'
       AND EXISTS (SELECT 1 FROM poultrypayments pp WHERE pp.saleid = p_saleid AND pp.farmid = p_farmid
                                                      AND COALESCE(pp.status, 'Posted') = 'Posted') THEN
        RAISE EXCEPTION 'Sale #% already has a payment, so it cannot be discarded. Reverse it instead.', p_saleid;
    END IF;

    PERFORM sppoultrybirdstock_sync(p_farmid, 'Bird Sale', 0, p_saleid, NULL, p_userid);
    PERFORM sppoultryeggstock_syncforsale(p_farmid, p_saleid, 0, p_userid);
    DELETE FROM sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid;
END;
$function$;

-- The table-level guard. See the header for what it lets through and why.
CREATE FUNCTION public.trg_sale_postedguard_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $f$
DECLARE
    v_fresh text := COALESCE(current_setting('poultry.sale_fresh', true), '');
    v_id    integer := COALESCE(NEW.saleid, OLD.saleid);
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status IS DISTINCT FROM 'Posted' AND current_setting('poultry.sale_system', true) IS DISTINCT FROM 'on' THEN
            RAISE EXCEPTION 'A sale is created Posted.' USING ERRCODE = 'P0001';
        END IF;
        -- This transaction may finish shaping the sale it is posting.
        PERFORM set_config('poultry.sale_fresh', v_fresh || ',' || NEW.saleid::text || ',', true);
        RETURN NEW;
    END IF;

    IF current_setting('poultry.sale_system', true) = 'on'
       OR position(',' || v_id::text || ',' IN v_fresh) > 0
       OR fnflock_closeoutinprogress()
       OR fnpoultrysale_isgenerated(OLD.saledescription) THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    IF TG_OP = 'DELETE' THEN
        IF current_setting('poultry.sale_discard', true) = 'on' THEN RETURN OLD; END IF;
        RAISE EXCEPTION 'Sale #% is posted and cannot be deleted. Reverse it instead.', OLD.saleid
            USING ERRCODE = 'P0001';
    END IF;

    IF OLD.status = 'Reversed' THEN
        RAISE EXCEPTION 'Sale #% has been reversed and can no longer be changed.', OLD.saleid
            USING ERRCODE = 'P0001';
    END IF;

    IF NEW.status          IS DISTINCT FROM OLD.status
       OR NEW.reversedat   IS DISTINCT FROM OLD.reversedat
       OR NEW.salereversalid IS DISTINCT FROM OLD.salereversalid
       OR NEW.farmid       IS DISTINCT FROM OLD.farmid
       OR NEW.saledate     IS DISTINCT FROM OLD.saledate
       OR NEW.product      IS DISTINCT FROM OLD.product
       OR NEW.quantity     IS DISTINCT FROM OLD.quantity
       OR NEW.unitprice    IS DISTINCT FROM OLD.unitprice
       OR NEW.totalamount  IS DISTINCT FROM OLD.totalamount
       OR NEW.customerid   IS DISTINCT FROM OLD.customerid AND OLD.customerid IS NOT NULL
       OR NEW.customername IS DISTINCT FROM OLD.customername
       OR NEW.flockid      IS DISTINCT FROM OLD.flockid
       OR NEW.poultryproductid IS DISTINCT FROM OLD.poultryproductid
       OR NEW.paymentmethod IS DISTINCT FROM OLD.paymentmethod THEN
        RAISE EXCEPTION 'Sale #% is posted, so what was sold, to whom and for how much can no longer be changed. Reverse the sale, or use Correct Sale.', OLD.saleid
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END
$f$;
-- (customerid may still be FILLED IN once on a sale that never had one --
-- sppoultrypayment_record links a pre-223 sale to the customer its name
-- resolves to. Changing an existing customer is refused.)

DROP TRIGGER IF EXISTS trg_sale_postedguard ON public.sale;
CREATE TRIGGER trg_sale_postedguard
    BEFORE INSERT OR UPDATE OR DELETE ON public.sale
    FOR EACH ROW EXECUTE FUNCTION public.trg_sale_postedguard_fn();

-- A payment can only be applied to an active sale.
CREATE OR REPLACE FUNCTION public.sppoultrycustomerpayment_record(p_farmid text, p_customerid integer, p_amount numeric, p_allocations jsonb, p_paymentmethod text DEFAULT NULL::text, p_paymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_cashaccountid integer DEFAULT NULL::integer, p_reference text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_sourcetype text DEFAULT 'CustomerBalances'::text, p_createdby text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_group      uuid := gen_random_uuid();
    v_date       timestamp := COALESCE(p_paymentdate, (now() at time zone 'utc'));
    v_allocated  numeric(14,2);
    v_count      integer;
    v_distinct   integer;
    v_minamount  numeric(14,2);
    v_missing    integer;
    v_reversed   integer;
    v_row        record;
    v_before     numeric(14,2);
    v_paymentid  integer;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than 0.';
    END IF;
    IF p_customerid IS NULL THEN
        RAISE EXCEPTION 'A customer is required to receive a payment.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM customer c
                   WHERE c.customerid = p_customerid AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Customer does not belong to this company.';
    END IF;
    IF p_cashaccountid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM poultrycashaccounts a
                       WHERE a.poultrycashaccountid = p_cashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
    END IF;

    SELECT COUNT(*), COUNT(DISTINCT a.saleid), COALESCE(SUM(a.amount), 0),
           COALESCE(MIN(a.amount), 0)
    INTO   v_count, v_distinct, v_allocated, v_minamount
    FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
           AS a(saleid integer, amount numeric)
    WHERE  a.saleid IS NOT NULL AND COALESCE(a.amount, 0) <> 0;

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Select at least one sale to apply this payment to.';
    END IF;
    IF v_distinct <> v_count THEN
        RAISE EXCEPTION 'The same sale appears more than once in this payment.';
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
           AS a(saleid integer, amount numeric)
    WHERE  a.saleid IS NOT NULL AND COALESCE(a.amount, 0) <> 0
      AND  NOT EXISTS (SELECT 1 FROM sale s
                       WHERE s.saleid = a.saleid AND s.farmid = p_farmid);
    IF v_missing > 0 THEN
        RAISE EXCEPTION '% of the selected sales do not belong to this company.', v_missing;
    END IF;

    SELECT MIN(a.saleid) INTO v_reversed
    FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
           AS a(saleid integer, amount numeric)
    JOIN   sale s ON s.saleid = a.saleid AND s.farmid = p_farmid
    WHERE  s.status = 'Reversed';
    IF v_reversed IS NOT NULL THEN
        RAISE EXCEPTION 'Sale #% has been reversed, so a payment cannot be applied to it.', v_reversed;
    END IF;

    FOR v_row IN
        SELECT a.saleid, a.amount::numeric(14,2) AS amount,
               s.totalamount, s.amountpaid, s.paid, s.saledate
        FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
               AS a(saleid integer, amount numeric)
        JOIN   sale s ON s.saleid = a.saleid AND s.farmid = p_farmid
        WHERE  a.saleid IS NOT NULL AND COALESCE(a.amount, 0) <> 0
        ORDER  BY s.saledate, s.saleid
        FOR UPDATE OF s
    LOOP
        IF NOT EXISTS (SELECT 1 FROM sale s
                       WHERE s.saleid = v_row.saleid AND s.farmid = p_farmid
                         AND s.customerid = p_customerid) THEN
            RAISE EXCEPTION 'Sale #% does not belong to this customer.', v_row.saleid;
        END IF;

        v_before := fnpoultrysalebalance(v_row.paid, v_row.totalamount, v_row.amountpaid);

        IF v_before <= 0 THEN
            RAISE EXCEPTION 'Sale #% is already fully paid.', v_row.saleid;
        END IF;
        IF v_row.amount > v_before THEN
            RAISE EXCEPTION 'Cannot apply % to sale #% -- its balance is only %.',
                  v_row.amount, v_row.saleid, v_before;
        END IF;

        INSERT INTO poultrypayments
            (farmid, saleid, amount, paymentmethod, paymentdate, reference, note,
             createdby, status, sourcetype, customerid, poultrycashaccountid, paymentgroupid)
        VALUES
            (p_farmid, v_row.saleid, v_row.amount, p_paymentmethod, v_date, p_reference, p_note,
             p_createdby, 'Posted', COALESCE(p_sourcetype, 'CustomerBalances'), p_customerid,
             p_cashaccountid, v_group)
        RETURNING poultrypaymentid INTO v_paymentid;

        INSERT INTO customerpaymentallocation
            (farmid, module, paymentid, saleid, amountapplied,
             salebalancebefore, salebalanceafter, status, createdby, createdat)
        VALUES
            (p_farmid, 'poultry', v_paymentid, v_row.saleid, v_row.amount,
             v_before, v_before - v_row.amount, 'Posted', p_createdby, v_date);

        PERFORM sppoultrysale_recompute(p_farmid, v_row.saleid, p_cashaccountid, p_createdby);
    END LOOP;

    RETURN v_group;
END;
$function$;

-- Reversing a payment now also recomputes the sales its credit was applied
-- to, and refuses a payment whose credit has been refunded (reverse the
-- refund's effect first -- the money already went back once).
CREATE OR REPLACE FUNCTION public.sppoultrycustomerpayment_reverse(p_farmid text, p_paymentgroupid uuid, p_reason text DEFAULT NULL::text, p_reversedby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_now   timestamp := (now() at time zone 'utc');
    v_count integer := 0;
    v_sale  integer;
    v_sales integer[];
BEGIN
    IF NOT EXISTS (SELECT 1 FROM poultrypayments pp
                   WHERE pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Payment not found for this company.';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('poultry-paymentgroup:' || p_paymentgroupid::text));
    IF NOT EXISTS (SELECT 1 FROM poultrypayments pp
                   WHERE pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid
                     AND COALESCE(pp.status, 'Posted') = 'Posted') THEN
        RAISE EXCEPTION 'This payment has already been reversed.';
    END IF;
    IF EXISTS (SELECT 1 FROM poultrycustomerrefundlines rl
               JOIN poultrycustomerrefunds r ON r.refundid = rl.refundid AND r.status = 'Posted'
               JOIN poultrypayments pp ON pp.poultrypaymentid = rl.poultrypaymentid
               WHERE pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Part of this payment has been refunded to the customer, so it cannot be reversed.';
    END IF;

    SELECT array_agg(DISTINCT x.saleid) INTO v_sales
    FROM (SELECT pp.saleid FROM poultrypayments pp
          WHERE  pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid
          UNION
          SELECT ca.saleid FROM customerpaymentallocation ca
          JOIN   poultrypayments pp ON pp.poultrypaymentid = ca.paymentid AND pp.farmid = ca.farmid
          WHERE  pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid
            AND  ca.module = 'poultry' AND ca.status = 'Posted') x;

    UPDATE customerpaymentallocation ca
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason
    FROM   poultrypayments pp
    WHERE  pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid
      AND  ca.module = 'poultry' AND ca.paymentid = pp.poultrypaymentid
      AND  ca.status = 'Posted';

    UPDATE poultrypayments pp
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason
    WHERE  pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid
      AND  COALESCE(pp.status, 'Posted') = 'Posted';
    GET DIAGNOSTICS v_count = ROW_COUNT;

    FOREACH v_sale IN ARRAY COALESCE(v_sales, ARRAY[]::integer[]) LOOP
        PERFORM sppoultrysale_recompute(p_farmid, v_sale, NULL, p_reversedby);
    END LOOP;

    RETURN v_count;
END;
$function$;

-- ------------------------------------------------------ 6. reversal state --

-- Everything the preview shows and the reversal re-checks, from the database
-- alone. Called with p_lock = TRUE by the reversal, which then compares the
-- fingerprint with the one the user saw.
CREATE FUNCTION public.fnpoultrysale_reversalstate(p_farmid text, p_saleid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $f$
DECLARE
    v_ids       integer[];
    v_head      record;
    v_blockers  jsonb := '[]'::jsonb;
    v_lines     jsonb;
    v_money     jsonb;
    v_residual  jsonb;
    v_fp        text;
    v_closeout  record;
    v_cust      integer;
BEGIN
    v_ids := fnpoultrysale_document(p_farmid, p_saleid);
    IF v_ids IS NULL THEN
        RETURN jsonb_build_object('found', false,
               'blockers', jsonb_build_array(jsonb_build_object('code', 'NotFound',
                           'message', 'This sale was not found for this company.')));
    END IF;

    SELECT MIN(s.saledate) AS saledate, MIN(s.customerid) AS customerid,
           MIN(s.customername)::text AS customername, MIN(s.salegroupno) AS salegroupno,
           SUM(s.totalamount)::numeric(14,2) AS total,
           SUM(fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid))::numeric(14,2) AS outstanding,
           bool_or(s.status = 'Reversed') AS anyreversed,
           bool_or(fnpoultrysale_isgenerated(s.saledescription)) AS generated,
           MIN(s.saledescription)::text AS description,
           MIN(s.poultrycashaccountid) AS accountid
    INTO   v_head
    FROM   sale s WHERE s.farmid = p_farmid AND s.saleid = ANY (v_ids);
    v_cust := v_head.customerid;

    -- ---- blockers
    IF v_head.anyreversed THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'AlreadyReversed',
                      'message', 'This sale has already been reversed.');
    END IF;
    IF v_head.generated THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'GeneratedSale',
                      'message', 'This sale was created by ' || COALESCE(v_head.description, 'a delivery')
                                 || '. Reverse that delivery or driver return instead -- it owns this sale.');
    END IF;
    SELECT f.name AS flockname INTO v_closeout
    FROM   flockcloseoutdispositions x
    JOIN   flockcloseouts c ON c.closeoutid = x.closeoutid
    LEFT   JOIN flock f ON f.flockid = c.flockid
    WHERE  x.saleid = ANY (v_ids) AND x.reversedat IS NULL AND c.reopenedat IS NULL
    LIMIT  1;
    IF FOUND AND NOT fnflock_closeoutinprogress() THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'ClosedFlock',
                      'message', 'This sale closed flock "' || COALESCE(v_closeout.flockname, '?')
                                 || '". Reopen the flock to reverse it -- reopening reverses this sale too.');
    END IF;
    IF EXISTS (SELECT 1 FROM poultrycashtransactions ct
               WHERE ct.farmid = p_farmid AND ct.sourcetype = 'Sale' AND ct.sourceid = ANY (v_ids)
                 AND (ct.clearingstatus = 'Cleared' OR ct.poultrycashreconciliationid IS NOT NULL)) THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'Reconciled',
                      'message', 'The money received at this sale has been reconciled on its cash account. Undo that reconciliation before reversing the sale.');
    END IF;

    -- ---- stock to restore, from the sale's own movements
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'saleId', s.saleid, 'product', s.product, 'quantity', s.quantity,
               'unitPrice', s.unitprice, 'total', s.totalamount, 'size', s.size,
               'eggProductId', s.poultryproductid,
               'restoreProductId', mv.productid, 'restoreProductName', mv.productname,
               'restoreQuantity', COALESCE(mv.qty, 0), 'restoreUnit', mv.unit)
             ORDER BY s.saleid), '[]'::jsonb)
    INTO   v_lines
    FROM   sale s
    LEFT   JOIN LATERAL (
        SELECT t.poultryproductid AS productid, MIN(p.name)::text AS productname,
               (-SUM(t.quantity))::numeric(14,3) AS qty,
               CASE WHEN MIN(t.txntype) = 'Bird Sale' THEN 'birds' ELSE 'eggs' END AS unit
        FROM   poultrystocktransactions t
        LEFT   JOIN poultryproducts p ON p.poultryproductid = t.poultryproductid
        WHERE  t.farmid = p_farmid AND t.relatedid = s.saleid AND t.txntype IN ('Sale', 'Bird Sale')
        GROUP  BY t.poultryproductid
        HAVING SUM(t.quantity) <> 0
        LIMIT  1) mv ON TRUE
    WHERE  s.farmid = p_farmid AND s.saleid = ANY (v_ids);

    -- ---- money already applied, one item per payment group
    WITH al AS (
        SELECT ca.allocationid, ca.amountapplied, ca.saleid AS tosale,
               pp.poultrypaymentid, pp.paymentgroupid, pp.paymentnumber, pp.sourcetype,
               pp.customerid, pp.paymentdate, pp.paymentmethod
        FROM   customerpaymentallocation ca
        JOIN   poultrypayments pp ON pp.poultrypaymentid = ca.paymentid AND pp.farmid = ca.farmid
        WHERE  ca.module = 'poultry' AND ca.farmid = p_farmid AND ca.status = 'Posted'
          AND  ca.saleid = ANY (v_ids)
    ), legacy AS (    -- pre-222 payments with no allocation row
        SELECT pp.amount AS amountapplied, pp.saleid AS tosale, pp.poultrypaymentid, pp.paymentgroupid,
               pp.paymentnumber, pp.sourcetype, pp.customerid, pp.paymentdate, pp.paymentmethod
        FROM   poultrypayments pp
        WHERE  pp.farmid = p_farmid AND pp.saleid = ANY (v_ids)
          AND  COALESCE(pp.status, 'Posted') = 'Posted'
          AND  NOT EXISTS (SELECT 1 FROM customerpaymentallocation ca
                           WHERE ca.module = 'poultry' AND ca.paymentid = pp.poultrypaymentid AND ca.farmid = pp.farmid)
    ), x AS (
        SELECT amountapplied, paymentgroupid, paymentnumber, sourcetype, customerid, paymentdate, paymentmethod FROM al
        UNION ALL
        SELECT amountapplied, paymentgroupid, paymentnumber, sourcetype, customerid, paymentdate, paymentmethod FROM legacy
    ), g AS (
        SELECT x.paymentgroupid,
               string_agg(DISTINCT x.paymentnumber, ', ') AS numbers,
               MIN(x.sourcetype) AS sourcetype,
               MIN(x.customerid) AS customerid,
               MIN(x.paymentdate) AS paymentdate,
               MIN(x.paymentmethod) AS paymentmethod,
               SUM(x.amountapplied)::numeric(14,2) AS allocated
        FROM   x GROUP BY x.paymentgroupid
    ), w AS (
        SELECT g.*,
               (SELECT SUM(pp.amount) FROM poultrypayments pp
                WHERE pp.paymentgroupid = g.paymentgroupid AND pp.farmid = p_farmid
                  AND COALESCE(pp.status, 'Posted') = 'Posted')::numeric(14,2) AS grouptotal,
               fnpoultrypaymentgroupaccount(p_farmid, g.paymentgroupid) AS accountid,
               -- Wholly this sale's: every Posted row is on this sale and every
               -- Posted allocation of those rows is to this sale. Sale-generated
               -- (below) additionally needs a SaleEntry source; flock reopen,
               -- which has always reversed its sales' payments, only needs this.
               (NOT EXISTS (SELECT 1 FROM poultrypayments pp
                                WHERE pp.paymentgroupid = g.paymentgroupid AND pp.farmid = p_farmid
                                  AND COALESCE(pp.status, 'Posted') = 'Posted'
                                  AND pp.saleid <> ALL (v_ids))
                AND NOT EXISTS (SELECT 1 FROM customerpaymentallocation ca
                                JOIN poultrypayments pp ON pp.poultrypaymentid = ca.paymentid AND pp.farmid = ca.farmid
                                WHERE pp.paymentgroupid = g.paymentgroupid AND pp.farmid = p_farmid
                                  AND ca.module = 'poultry' AND ca.status = 'Posted'
                                  AND ca.saleid <> ALL (v_ids))
                AND NOT EXISTS (SELECT 1 FROM poultrycustomerrefundlines rl
                                JOIN poultrypayments pp ON pp.poultrypaymentid = rl.poultrypaymentid
                                WHERE pp.paymentgroupid = g.paymentgroupid AND pp.farmid = p_farmid)) AS wholly,
               EXISTS (SELECT 1 FROM poultrycashtransactions ct
                       WHERE ct.farmid = p_farmid AND ct.paymentgroupid = g.paymentgroupid
                         AND (ct.clearingstatus = 'Cleared' OR ct.poultrycashreconciliationid IS NOT NULL)) AS reconciled
        FROM g
    ), e AS (
        SELECT w.*,
               w.wholly AND (w.sourcetype IN ('SaleEntry', 'Backfill') OR fnflock_closeoutinprogress()) AS exclusive
        FROM   w
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'key', e.paymentgroupid::text,
               'paymentGroupId', e.paymentgroupid,
               'paymentNumbers', e.numbers,
               'source', e.sourcetype,
               'saleGenerated', e.exclusive,
               'allocated', e.allocated,
               'paymentTotal', e.grouptotal,
               'paymentDate', e.paymentdate,
               'paymentMethod', e.paymentmethod,
               'cashAccountId', e.accountid,
               'cashAccountName', (SELECT a.accountname FROM poultrycashaccounts a WHERE a.poultrycashaccountid = e.accountid),
               'customerId', e.customerid,
               'recordedAtReversal', false,
               'allowed', CASE
                   WHEN e.exclusive AND NOT e.reconciled AND e.customerid IS NOT NULL THEN '["KeepAsCredit","ReversePayment"]'::jsonb
                   WHEN e.exclusive AND NOT e.reconciled THEN '["ReversePayment"]'::jsonb
                   ELSE '["KeepAsCredit"]'::jsonb END,
               'default', CASE WHEN e.customerid IS NULL AND e.exclusive THEN 'ReversePayment' ELSE 'KeepAsCredit' END,
               'reverseUnavailableReason', CASE
                   WHEN e.exclusive AND e.reconciled THEN 'This payment''s cash has been reconciled, so it can only be kept as customer credit.'
                   WHEN NOT e.wholly AND e.sourcetype IN ('SaleEntry', 'Backfill') THEN 'This payment also pays other sales, so only this sale''s part is released -- as customer credit.'
                   WHEN NOT e.exclusive THEN 'This payment was received on its own and may pay other sales. Reversing the sale releases this sale''s part as customer credit and leaves the payment Posted.'
                   END)
             ORDER BY e.paymentdate), '[]'::jsonb)
    INTO   v_money
    FROM   e;

    -- ---- money received at the sale with no payment row (walk-ins, pre-223)
    SELECT CASE WHEN COALESCE(SUM(r.amt), 0) > 0 THEN jsonb_build_object(
               'key', 'AT-SALE',
               'paymentGroupId', NULL,
               'paymentNumbers', NULL,
               'source', 'AtSale',
               'saleGenerated', true,
               'allocated', SUM(r.amt)::numeric(14,2),
               'paymentTotal', SUM(r.amt)::numeric(14,2),
               'paymentDate', MIN(r.saledate),
               'paymentMethod', MIN(r.paymentmethod),
               'cashAccountId', MIN(r.acct),
               'cashAccountName', (SELECT a.accountname FROM poultrycashaccounts a WHERE a.poultrycashaccountid = MIN(r.acct)),
               'customerId', v_cust,
               'recordedAtReversal', true,
               'allowed', CASE WHEN v_cust IS NOT NULL THEN '["KeepAsCredit","ReversePayment"]'::jsonb
                               ELSE '["ReversePayment"]'::jsonb END,
               'default', CASE WHEN v_cust IS NOT NULL THEN 'KeepAsCredit' ELSE 'ReversePayment' END,
               'reverseUnavailableReason', NULL) END
    INTO   v_residual
    FROM (
        SELECT s.saleid, s.saledate, s.paymentmethod, s.poultrycashaccountid AS acct,
               GREATEST(fnpoultrysalereceived(s.paid, s.totalamount, s.amountpaid)
                        - fnpoultrysale_allocated(p_farmid, s.saleid), 0) AS amt
        FROM   sale s WHERE s.farmid = p_farmid AND s.saleid = ANY (v_ids) AND s.status = 'Posted'
    ) r;
    IF v_residual IS NOT NULL THEN
        v_money := v_money || jsonb_build_array(v_residual);
    END IF;

    -- ---- fingerprint: anything that changes what the reversal would do
    SELECT md5(COALESCE(string_agg(t, '|' ORDER BY t), '')) INTO v_fp
    FROM (
        SELECT 's' || s.saleid || ':' || s.status || ':' || s.totalamount || ':' || COALESCE(s.amountpaid, 0)
               || ':' || COALESCE(s.paid, true) || ':' || s.quantity || ':' || COALESCE(s.poultrycashaccountid, 0) AS t
        FROM   sale s WHERE s.farmid = p_farmid AND s.saleid = ANY (v_ids)
        UNION ALL
        SELECT 'a' || ca.allocationid || ':' || ca.status || ':' || ca.amountapplied
        FROM   customerpaymentallocation ca
        WHERE  ca.module = 'poultry' AND ca.farmid = p_farmid AND ca.saleid = ANY (v_ids)
        UNION ALL
        SELECT 'p' || pp.poultrypaymentid || ':' || COALESCE(pp.status, 'Posted') || ':' || pp.amount
        FROM   poultrypayments pp
        WHERE  pp.farmid = p_farmid AND pp.paymentgroupid IN (
                   SELECT p2.paymentgroupid FROM poultrypayments p2
                   JOIN   customerpaymentallocation ca ON ca.paymentid = p2.poultrypaymentid AND ca.module = 'poultry'
                   WHERE  p2.farmid = p_farmid AND ca.saleid = ANY (v_ids)
                   UNION
                   SELECT p3.paymentgroupid FROM poultrypayments p3 WHERE p3.farmid = p_farmid AND p3.saleid = ANY (v_ids))
    ) z;

    RETURN jsonb_build_object(
        'found', true,
        'saleId', p_saleid,
        'saleIds', to_jsonb(v_ids),
        'saleGroupNo', v_head.salegroupno,
        'saleDate', v_head.saledate,
        'customerId', v_head.customerid,
        'customerName', v_head.customername,
        'total', v_head.total,
        'paid', COALESCE((SELECT SUM((m->>'allocated')::numeric) FROM jsonb_array_elements(v_money) m), 0),
        'outstanding', v_head.outstanding,
        'lines', v_lines,
        'payments', v_money,
        'customerCreditNow', CASE WHEN v_cust IS NULL THEN 0 ELSE fnpoultrycustomer_credit(p_farmid, v_cust) END,
        'blockers', v_blockers,
        'fingerprint', v_fp);
END
$f$;

-- Preview for the confirmation dialog, with the outcome of the defaults.
CREATE FUNCTION public.sppoultrysale_reversalpreview(p_farmid text, p_saleid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $f$
    SELECT st || jsonb_build_object(
             'defaultCreditCreated', COALESCE((SELECT SUM((m->>'allocated')::numeric) FROM jsonb_array_elements(st->'payments') m
                                               WHERE m->>'default' = 'KeepAsCredit'), 0),
             'defaultCashOut',       COALESCE((SELECT SUM((m->>'allocated')::numeric) FROM jsonb_array_elements(st->'payments') m
                                               WHERE m->>'default' = 'ReversePayment'), 0))
    FROM   (SELECT public.fnpoultrysale_reversalstate(p_farmid, p_saleid) AS st) q;
$f$;

-- -------------------------------------------------------- 7. the reversal --
--
-- p_handling: {"<payment group id | AT-SALE>": "KeepAsCredit" | "ReversePayment"}
--   Missing keys take the default. A choice the payment does not allow
--   (ReversePayment on a bulk customer payment) is refused, not coerced.
-- p_expectedfingerprint: from the preview. NULL skips the check (flock reopen).
-- p_idempotencykey: a retried request returns the reversal it already made.
--
-- One transaction: if any step fails, nothing is reversed.
CREATE FUNCTION public.sppoultrysale_reverse(
    p_farmid              text,
    p_saleid              integer,
    p_reasoncode          text,
    p_reason              text,
    p_handling            jsonb   DEFAULT '{}'::jsonb,
    p_expectedfingerprint text    DEFAULT NULL,
    p_idempotencykey      text    DEFAULT NULL,
    p_reversedby          text    DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $f$
DECLARE
    v_now       timestamp := (now() AT TIME ZONE 'utc');
    v_today     date      := fncompany_businessdate(p_farmid);
    v_ids       integer[];
    v_state     jsonb;
    v_item      jsonb;
    v_action    text;
    v_group     uuid;
    v_newgroup  uuid;
    v_reason    text;
    v_id        integer;
    v_existing  integer;
    v_number    text;
    v_credit    numeric(14,2) := 0;
    v_cashout   numeric(14,2) := 0;
    v_kinds     text[] := ARRAY[]::text[];
    v_s         record;
    v_amt       numeric(14,2);
    v_pid       integer;
    v_rev       jsonb := '[]'::jsonb;
BEGIN
    IF p_reason IS NULL OR length(btrim(p_reason)) = 0 THEN
        RAISE EXCEPTION 'Give a reason for reversing this sale.' USING ERRCODE = 'P0001';
    END IF;
    v_reason := btrim(COALESCE(NULLIF(btrim(p_reasoncode), '') || ': ', '') || btrim(p_reason));

    v_ids := fnpoultrysale_document(p_farmid, p_saleid);
    IF v_ids IS NULL THEN
        RAISE EXCEPTION 'This sale was not found for this company.' USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('poultry-salereversal:' || p_farmid || ':' || v_ids[1]::text));
    PERFORM 1 FROM sale s WHERE s.farmid = p_farmid AND s.saleid = ANY (v_ids) FOR UPDATE;

    IF p_idempotencykey IS NOT NULL THEN
        SELECT r.salereversalid INTO v_existing FROM poultrysalereversals r
        WHERE  r.farmid = p_farmid AND r.idempotencykey = p_idempotencykey;
        IF FOUND THEN RETURN v_existing; END IF;
    END IF;

    v_state := fnpoultrysale_reversalstate(p_farmid, p_saleid);
    IF jsonb_array_length(v_state->'blockers') > 0 THEN
        RAISE EXCEPTION '%', v_state->'blockers'->0->>'message' USING ERRCODE = 'P0001';
    END IF;
    IF p_expectedfingerprint IS NOT NULL AND p_expectedfingerprint <> v_state->>'fingerprint' THEN
        RAISE EXCEPTION 'This sale changed after the reversal preview was generated. Please review the updated impact before continuing.'
            USING ERRCODE = 'P0001', HINT = 'stale-preview';
    END IF;

    -- Validate every choice before changing anything.
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_state->'payments') LOOP
        v_action := COALESCE(p_handling->>(v_item->>'key'), v_item->>'default');
        IF NOT (v_item->'allowed') ? v_action THEN
            RAISE EXCEPTION '%', CASE
                WHEN v_action = 'ReversePayment' THEN COALESCE(v_item->>'reverseUnavailableReason',
                     'Payment ' || COALESCE(v_item->>'paymentNumbers', '') || ' cannot be reversed with this sale.')
                ELSE 'This sale has no customer to hold the money as credit, so the money received can only be reversed.' END
                USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    PERFORM set_config('poultry.sale_system', 'on', true);

    -- 1. Money received at the sale without a payment row becomes the SaleEntry
    --    payment it should always have been: same amount, account and date.
    --    The 'Sale' residual cash-in is replaced by the group's CashIn; the
    --    account balance does not move.
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_state->'payments') m WHERE m->>'key' = 'AT-SALE') THEN
        v_newgroup := gen_random_uuid();
        FOR v_s IN
            SELECT s.saleid, s.saledate, s.paymentmethod, s.poultrycashaccountid, s.customerid, s.totalamount,
                   GREATEST(fnpoultrysalereceived(s.paid, s.totalamount, s.amountpaid)
                            - fnpoultrysale_allocated(p_farmid, s.saleid), 0)::numeric(14,2) AS amt
            FROM   sale s WHERE s.farmid = p_farmid AND s.saleid = ANY (v_ids)
        LOOP
            CONTINUE WHEN v_s.amt <= 0;
            INSERT INTO poultrypayments
                (farmid, saleid, amount, paymentmethod, paymentdate, reference, note, createdby,
                 status, sourcetype, customerid, poultrycashaccountid, paymentgroupid)
            VALUES
                (p_farmid, v_s.saleid, v_s.amt, v_s.paymentmethod, v_s.saledate::timestamp, NULL,
                 'Received at the sale (recorded when the sale was reversed)', p_reversedby,
                 'Posted', 'SaleEntry', v_s.customerid, v_s.poultrycashaccountid, v_newgroup)
            RETURNING poultrypaymentid INTO v_pid;

            INSERT INTO customerpaymentallocation
                (farmid, module, paymentid, saleid, amountapplied, salebalancebefore, salebalanceafter,
                 status, createdby, createdat)
            VALUES
                (p_farmid, 'poultry', v_pid, v_s.saleid, v_s.amt, v_s.amt, 0, 'Posted', p_reversedby, v_now);

            PERFORM sppoultrysale_recompute(p_farmid, v_s.saleid, NULL, p_reversedby);
        END LOOP;
    END IF;

    -- 2. Pre-222 payments with no allocation row get the one they imply, so the
    --    step below can reverse it like any other.
    INSERT INTO customerpaymentallocation
        (farmid, module, paymentid, saleid, amountapplied, salebalancebefore, salebalanceafter,
         status, createdby, createdat)
    SELECT p_farmid, 'poultry', pp.poultrypaymentid, pp.saleid, pp.amount, pp.amount, 0,
           'Posted', p_reversedby, v_now
    FROM   poultrypayments pp
    WHERE  pp.farmid = p_farmid AND pp.saleid = ANY (v_ids)
      AND  COALESCE(pp.status, 'Posted') = 'Posted'
      AND  NOT EXISTS (SELECT 1 FROM customerpaymentallocation ca
                       WHERE ca.module = 'poultry' AND ca.paymentid = pp.poultrypaymentid AND ca.farmid = pp.farmid);

    -- 3. Release every allocation applied to the sale.
    UPDATE customerpaymentallocation ca
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = 'Sale reversed: ' || v_reason
    WHERE  ca.module = 'poultry' AND ca.farmid = p_farmid AND ca.saleid = ANY (v_ids)
      AND  ca.status = 'Posted';

    -- 4. Restore exactly what was sold: the egg class (or Unsorted) of the
    --    original movement, and birds through the append-only bird sync.
    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby)
    SELECT t.farmid, t.poultryproductid, 'Sale Reversal', -SUM(t.quantity), MIN(t.unitcost), t.relatedid,
           'Sale #' || t.relatedid || ' reversed', p_reversedby
    FROM   poultrystocktransactions t
    WHERE  t.farmid = p_farmid AND t.txntype = 'Sale' AND t.relatedid = ANY (v_ids)
    GROUP  BY t.farmid, t.poultryproductid, t.relatedid
    HAVING SUM(t.quantity) <> 0;

    FOR v_s IN SELECT s.saleid FROM sale s WHERE s.farmid = p_farmid AND s.saleid = ANY (v_ids) LOOP
        PERFORM sppoultrybirdstock_sync(p_farmid, 'Bird Sale', 0, v_s.saleid, NULL, p_reversedby);
    END LOOP;

    -- 5. The reversal record, then the sale itself.
    PERFORM pg_advisory_xact_lock(hashtext('poultry-salereversal-no:' || p_farmid));
    SELECT 'SR-' || lpad((COALESCE(MAX(NULLIF(regexp_replace(r.reversalnumber, '\D', '', 'g'), '')::int), 0) + 1)::text, 5, '0')
    INTO   v_number
    FROM   poultrysalereversals r WHERE r.farmid = p_farmid;

    INSERT INTO poultrysalereversals
        (farmid, reversalnumber, saleids, salegroupno, customerid, customername, saledate,
         reasoncode, reason, businessdate, occurredat, reversedby, paymenthandling,
         totalamount, paidamount, outstandingamount, idempotencykey, snapshot)
    VALUES
        (p_farmid, v_number, v_ids, v_state->>'saleGroupNo', (v_state->>'customerId')::int,
         v_state->>'customerName', (v_state->>'saleDate')::date,
         NULLIF(btrim(p_reasoncode), ''), btrim(p_reason), v_today, v_now, p_reversedby, 'None',
         (v_state->>'total')::numeric, (v_state->>'paid')::numeric, (v_state->>'outstanding')::numeric,
         p_idempotencykey, v_state)
    RETURNING salereversalid INTO v_id;

    UPDATE sale s
    SET    status = 'Reversed', reversedat = v_now, reversedby = p_reversedby,
           reversalreason = v_reason, salereversalid = v_id,
           dateupdated = v_now, updatedby = p_reversedby
    WHERE  s.farmid = p_farmid AND s.saleid = ANY (v_ids);

    -- 6. The money: credit stays where it is; a reversal undoes the receipt.
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_state->'payments') LOOP
        v_action := COALESCE(p_handling->>(v_item->>'key'), v_item->>'default');
        v_amt    := (v_item->>'allocated')::numeric;
        v_group  := CASE WHEN v_item->>'key' = 'AT-SALE' THEN v_newgroup ELSE (v_item->>'paymentGroupId')::uuid END;

        IF v_action = 'ReversePayment' THEN
            PERFORM sppoultrycustomerpayment_reverse(p_farmid, v_group, 'Sale reversed: ' || v_reason, p_reversedby);
            v_cashout := v_cashout + v_amt;
        ELSE
            v_credit := v_credit + v_amt;
        END IF;
        v_kinds := v_kinds || v_action;

        INSERT INTO poultrysalereversalpayments
            (salereversalid, farmid, paymentgroupid, paymentnumbers, sourcetype, amount, action, recordedatreversal)
        VALUES
            (v_id, p_farmid, v_group,
             COALESCE(v_item->>'paymentNumbers',
                      (SELECT string_agg(DISTINCT pp.paymentnumber, ', ') FROM poultrypayments pp
                       WHERE pp.paymentgroupid = v_group AND pp.farmid = p_farmid)),
             v_item->>'source', v_amt, v_action, v_item->>'key' = 'AT-SALE');
    END LOOP;

    UPDATE poultrysalereversals r
    SET    creditcreated = v_credit,
           cashreversed  = v_cashout,
           paymenthandling = CASE
               WHEN array_length(v_kinds, 1) IS NULL THEN 'None'
               WHEN 'KeepAsCredit' = ALL (v_kinds) THEN 'KeepAsCredit'
               WHEN 'ReversePayment' = ALL (v_kinds) THEN 'ReversePayment'
               ELSE 'Mixed' END
    WHERE  r.salereversalid = v_id;

    PERFORM set_config('poultry.sale_system', 'off', true);
    RETURN v_id;
END
$f$;

-- The reversal of a sale (any row of its document), for the sale's detail view.
CREATE FUNCTION public.sppoultrysale_reversalget(p_farmid text, p_saleid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $f$
    SELECT jsonb_build_object(
             'salereversalid', r.salereversalid, 'reversalNumber', r.reversalnumber,
             'saleIds', to_jsonb(r.saleids), 'reasonCode', r.reasoncode, 'reason', r.reason,
             'businessDate', r.businessdate, 'occurredAt', r.occurredat, 'reversedBy', r.reversedby,
             'paymentHandling', r.paymenthandling, 'total', r.totalamount, 'paid', r.paidamount,
             'outstanding', r.outstandingamount, 'creditCreated', r.creditcreated,
             'cashReversed', r.cashreversed, 'correctionSaleId', r.correctionsaleid,
             'payments', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                             'paymentGroupId', p.paymentgroupid, 'paymentNumbers', p.paymentnumbers,
                             'source', p.sourcetype, 'amount', p.amount, 'action', p.action,
                             'recordedAtReversal', p.recordedatreversal) ORDER BY p.salereversalpaymentid)
                           FROM poultrysalereversalpayments p WHERE p.salereversalid = r.salereversalid), '[]'::jsonb),
             'lines', r.snapshot->'lines')
    FROM   poultrysalereversals r
    WHERE  r.farmid = p_farmid AND p_saleid = ANY (r.saleids)
    ORDER  BY r.salereversalid DESC
    LIMIT  1;
$f$;

-- A corrected sale points at the sale it replaces. One correction per reversal.
CREATE FUNCTION public.sppoultrysale_linkcorrection(p_farmid text, p_newsaleid integer, p_correctssaleid integer, p_by text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $f$
DECLARE
    v_rev  integer;
    v_prev integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sale s WHERE s.saleid = p_newsaleid AND s.farmid = p_farmid AND s.status = 'Posted') THEN
        RAISE EXCEPTION 'The corrected sale was not found for this company.' USING ERRCODE = 'P0001';
    END IF;
    SELECT s.salereversalid INTO v_rev FROM sale s
    WHERE  s.saleid = p_correctssaleid AND s.farmid = p_farmid AND s.status = 'Reversed';
    IF v_rev IS NULL THEN
        RAISE EXCEPTION 'Sale #% is not a reversed sale of this company, so nothing can be corrected from it.', p_correctssaleid
            USING ERRCODE = 'P0001';
    END IF;
    SELECT r.correctionsaleid INTO v_prev FROM poultrysalereversals r WHERE r.salereversalid = v_rev;
    IF v_prev IS NOT NULL AND v_prev NOT IN (SELECT unnest(fnpoultrysale_document(p_farmid, p_newsaleid))) THEN
        RAISE EXCEPTION 'Sale #% was already corrected by sale #%.', p_correctssaleid, v_prev USING ERRCODE = 'P0001';
    END IF;

    UPDATE sale s SET correctssaleid = p_correctssaleid
    WHERE  s.farmid = p_farmid AND s.saleid = ANY (fnpoultrysale_document(p_farmid, p_newsaleid))
      AND  s.correctssaleid IS DISTINCT FROM p_correctssaleid;
    UPDATE poultrysalereversals r SET correctionsaleid = COALESCE(r.correctionsaleid, p_newsaleid)
    WHERE  r.salereversalid = v_rev;
END
$f$;

-- --------------------------------------------- 8. customer credit, refunds --

-- The payments holding a customer's credit, oldest first (the order credit is
-- used and refunded in).
CREATE FUNCTION public.sppoultrycustomercredit_list(p_farmid text, p_customerid integer)
RETURNS TABLE(poultrypaymentid integer, paymentgroupid uuid, paymentnumber text, paymentdate timestamp,
              amount numeric, unapplied numeric, sourcetype text, saleid integer, salestatus text,
              poultrycashaccountid integer)
LANGUAGE sql
STABLE
AS $f$
    SELECT pp.poultrypaymentid, pp.paymentgroupid, pp.paymentnumber::text, pp.paymentdate,
           pp.amount::numeric(14,2), fnpoultrypayment_unapplied(p_farmid, pp.poultrypaymentid),
           pp.sourcetype::text, pp.saleid, s.status::text,
           fnpoultrypaymentgroupaccount(p_farmid, pp.paymentgroupid)
    FROM   poultrypayments pp
    LEFT   JOIN sale s ON s.saleid = pp.saleid AND s.farmid = pp.farmid
    WHERE  pp.farmid = p_farmid AND pp.customerid = p_customerid
      AND  COALESCE(pp.status, 'Posted') = 'Posted'
      AND  fnpoultrypayment_unapplied(p_farmid, pp.poultrypaymentid) > 0
    ORDER  BY pp.paymentdate, pp.poultrypaymentid;
$f$;

-- Every customer holding credit, for the Customer Balances page ("we are
-- holding this customer's money" -- shown beside, never netted into, what
-- they owe).
CREATE FUNCTION public.sppoultrycustomercredit_summary(p_farmid text)
RETURNS TABLE(customerid integer, customername text, availablecredit numeric, paymentcount integer, outstanding numeric)
LANGUAGE sql
STABLE
AS $f$
    SELECT c.customerid, c.name::text, x.credit, x.n,
           COALESCE((SELECT SUM(fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid)) FROM sale s
                     WHERE s.farmid = p_farmid AND s.customerid = c.customerid AND s.status = 'Posted'), 0)::numeric(14,2)
    FROM (
        SELECT pp.customerid, SUM(fnpoultrypayment_unapplied(p_farmid, pp.poultrypaymentid))::numeric(14,2) AS credit,
               COUNT(*) FILTER (WHERE fnpoultrypayment_unapplied(p_farmid, pp.poultrypaymentid) > 0)::integer AS n
        FROM   poultrypayments pp
        WHERE  pp.farmid = p_farmid AND pp.customerid IS NOT NULL
          AND  COALESCE(pp.status, 'Posted') = 'Posted'
        GROUP  BY pp.customerid
    ) x
    JOIN   customer c ON c.customerid = x.customerid AND c.farmid = p_farmid
    WHERE  x.credit > 0
    ORDER  BY x.credit DESC;
$f$;

-- Apply credit to an active sale of the same customer. An allocation only: no
-- payment row, no Money In, no cash movement.
CREATE FUNCTION public.sppoultrycustomercredit_apply(p_farmid text, p_customerid integer, p_saleid integer, p_amount numeric, p_by text DEFAULT NULL)
RETURNS numeric
LANGUAGE plpgsql
AS $f$
DECLARE
    v_s       sale%ROWTYPE;
    v_bal     numeric(14,2);
    v_left    numeric(14,2) := round(p_amount, 2);
    v_take    numeric(14,2);
    v_src     record;
    v_now     timestamp := (now() AT TIME ZONE 'utc');
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Enter an amount greater than 0.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('poultry-customercredit:' || p_farmid || ':' || p_customerid::text));

    SELECT * INTO v_s FROM sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sale #% was not found for this company.', p_saleid USING ERRCODE = 'P0001';
    END IF;
    IF v_s.status <> 'Posted' THEN
        RAISE EXCEPTION 'Sale #% has been reversed.', p_saleid USING ERRCODE = 'P0001';
    END IF;
    IF v_s.customerid IS DISTINCT FROM p_customerid THEN
        RAISE EXCEPTION 'Sale #% does not belong to this customer.', p_saleid USING ERRCODE = 'P0001';
    END IF;
    v_bal := fnpoultrysalebalance(v_s.paid, v_s.totalamount, v_s.amountpaid);
    IF v_bal <= 0 THEN
        RAISE EXCEPTION 'Sale #% is already fully paid.', p_saleid USING ERRCODE = 'P0001';
    END IF;
    IF v_left > v_bal THEN
        RAISE EXCEPTION 'Sale #% only has % outstanding.', p_saleid, v_bal USING ERRCODE = 'P0001';
    END IF;
    IF v_left > fnpoultrycustomer_credit(p_farmid, p_customerid) THEN
        RAISE EXCEPTION 'The customer only has % of credit available.', fnpoultrycustomer_credit(p_farmid, p_customerid)
            USING ERRCODE = 'P0001';
    END IF;

    FOR v_src IN SELECT * FROM sppoultrycustomercredit_list(p_farmid, p_customerid) LOOP
        EXIT WHEN v_left <= 0;
        -- A payment already applied to this sale once (and released) cannot be
        -- applied to it again -- the allocation history keeps one row per pair.
        CONTINUE WHEN EXISTS (SELECT 1 FROM customerpaymentallocation ca
                              WHERE ca.module = 'poultry' AND ca.paymentid = v_src.poultrypaymentid
                                AND ca.saleid = p_saleid);
        v_take := LEAST(v_left, v_src.unapplied);
        INSERT INTO customerpaymentallocation
            (farmid, module, paymentid, saleid, amountapplied, salebalancebefore, salebalanceafter,
             status, createdby, createdat)
        VALUES
            (p_farmid, 'poultry', v_src.poultrypaymentid, p_saleid, v_take, v_bal, v_bal - v_take,
             'Posted', p_by, v_now);
        v_bal  := v_bal - v_take;
        v_left := v_left - v_take;
    END LOOP;

    IF v_left > 0 THEN
        RAISE EXCEPTION 'Only % of the credit could be applied to sale #% (the rest came from a payment already applied to it once).',
              round(p_amount, 2) - v_left, p_saleid USING ERRCODE = 'P0001';
    END IF;

    PERFORM sppoultrysale_recompute(p_farmid, p_saleid, NULL, p_by);
    RETURN round(p_amount, 2);
END
$f$;

-- Hand credit back to the customer: real Money Out, from the account the
-- business chooses. Not an expense, and no stock moves.
CREATE FUNCTION public.sppoultrycustomerrefund_record(
    p_farmid text, p_customerid integer, p_amount numeric, p_cashaccountid integer,
    p_paymentmethod text, p_refunddate date, p_reason text, p_by text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $f$
DECLARE
    v_left   numeric(14,2) := round(p_amount, 2);
    v_take   numeric(14,2);
    v_src    record;
    v_id     integer;
    v_number text;
    v_bal    numeric(14,2);
    v_txn    integer;
    v_name   text;
    v_date   date := COALESCE(p_refunddate, fncompany_businessdate(p_farmid));
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Enter a refund amount greater than 0.' USING ERRCODE = 'P0001';
    END IF;
    IF p_reason IS NULL OR length(btrim(p_reason)) = 0 THEN
        RAISE EXCEPTION 'Give a reason for the refund.' USING ERRCODE = 'P0001';
    END IF;
    SELECT c.name INTO v_name FROM customer c WHERE c.customerid = p_customerid AND c.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer does not belong to this company.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM poultrycashaccounts a
                   WHERE a.poultrycashaccountid = p_cashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Choose the cash account the refund is paid from.' USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('poultry-customercredit:' || p_farmid || ':' || p_customerid::text));
    IF v_left > fnpoultrycustomer_credit(p_farmid, p_customerid) THEN
        RAISE EXCEPTION 'The customer only has % of credit available to refund.', fnpoultrycustomer_credit(p_farmid, p_customerid)
            USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('poultry-refund-no:' || p_farmid));
    SELECT 'RF-' || lpad((COALESCE(MAX(NULLIF(regexp_replace(r.refundnumber, '\D', '', 'g'), '')::int), 0) + 1)::text, 5, '0')
    INTO   v_number FROM poultrycustomerrefunds r WHERE r.farmid = p_farmid;

    INSERT INTO poultrycustomerrefunds
        (farmid, refundnumber, customerid, amount, refunddate, poultrycashaccountid, paymentmethod, reason, createdby)
    VALUES
        (p_farmid, v_number, p_customerid, round(p_amount, 2), v_date, p_cashaccountid,
         NULLIF(btrim(COALESCE(p_paymentmethod, '')), ''), btrim(p_reason), p_by)
    RETURNING refundid INTO v_id;

    FOR v_src IN SELECT * FROM sppoultrycustomercredit_list(p_farmid, p_customerid) LOOP
        EXIT WHEN v_left <= 0;
        v_take := LEAST(v_left, v_src.unapplied);
        INSERT INTO poultrycustomerrefundlines (refundid, farmid, poultrypaymentid, amount)
        VALUES (v_id, p_farmid, v_src.poultrypaymentid, v_take);
        v_left := v_left - v_take;
    END LOOP;

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - round(p_amount, 2), updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycashaccountid = p_cashaccountid AND a.farmid = p_farmid
    RETURNING a.currentbalance INTO v_bal;

    INSERT INTO poultrycashtransactions
        (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
         amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
    VALUES
        (p_farmid, p_cashaccountid, v_date::timestamp, 'CashOut', 'CustomerRefund', v_id,
         -round(p_amount, 2), v_bal, 'Customer refund ' || v_number || ' - ' || COALESCE(v_name, ''),
         p_by, p_by, (now() at time zone 'utc'))
    RETURNING poultrycashtransactionid INTO v_txn;

    UPDATE poultrycustomerrefunds r SET poultrycashtransactionid = v_txn WHERE r.refundid = v_id;
    RETURN v_id;
END
$f$;

CREATE FUNCTION public.sppoultrycustomerrefund_list(p_farmid text, p_customerid integer DEFAULT NULL)
RETURNS TABLE(refundid integer, refundnumber text, customerid integer, customername text, amount numeric,
              refunddate date, poultrycashaccountid integer, accountname text, paymentmethod text,
              reason text, status text, createdby text, createdat timestamp, paymentnumbers text)
LANGUAGE sql
STABLE
AS $f$
    SELECT r.refundid, r.refundnumber, r.customerid, c.name::text, r.amount, r.refunddate,
           r.poultrycashaccountid, a.accountname::text, r.paymentmethod, r.reason, r.status,
           r.createdby, r.createdat,
           (SELECT string_agg(DISTINCT pp.paymentnumber, ', ') FROM poultrycustomerrefundlines rl
            JOIN poultrypayments pp ON pp.poultrypaymentid = rl.poultrypaymentid
            WHERE rl.refundid = r.refundid)::text
    FROM   poultrycustomerrefunds r
    LEFT   JOIN customer c ON c.customerid = r.customerid AND c.farmid = r.farmid
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = r.poultrycashaccountid
    WHERE  r.farmid = p_farmid AND (p_customerid IS NULL OR r.customerid = p_customerid)
    ORDER  BY r.refunddate DESC, r.refundid DESC;
$f$;

-- ------------------------------------------------------- 9. sale readers --
-- The Sales page lists reversed sales too (filtered there, default hidden), so
-- these return status and the links. ByFlock lists active sales only.

CREATE FUNCTION public.spsale_getall(p_farmid text)
 RETURNS TABLE(saleid integer, userid text, farmid text, saledate date, product text, quantity numeric, unitprice numeric, totalamount numeric, paymentmethod text, customername text, flockid integer, saledescription text, paid boolean, size text, poultrycashaccountid integer, amountpaid numeric, createddate timestamp without time zone, customerid integer, poultryproductid integer, salegroupno text,
               status text, reversedat timestamp without time zone, reversedby text, reversalreason text, salereversalid integer, correctssaleid integer, correctedbysaleid integer)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT s.saleid, s.userid::text, s.farmid::text, s.saledate, s.product::text,
           s.quantity, s.unitprice, s.totalamount,
           s.paymentmethod::text, s.customername::text, s.flockid, s.saledescription::text,
           COALESCE(s.paid, TRUE) AS paid,
           s.size::text, s.poultrycashaccountid, COALESCE(s.amountpaid, 0) AS amountpaid,
           s.createddate, s.customerid,
           s.poultryproductid, s.salegroupno,
           s.status, s.reversedat, s.reversedby, s.reversalreason, s.salereversalid, s.correctssaleid,
           r.correctionsaleid
    FROM   sale s
    LEFT   JOIN poultrysalereversals r ON r.salereversalid = s.salereversalid
    WHERE  s.farmid = p_farmid
    ORDER  BY s.saledate DESC, s.createddate DESC;
$function$;

CREATE FUNCTION public.spsale_getbyid(p_saleid integer, p_farmid text)
 RETURNS TABLE(saleid integer, userid text, farmid text, saledate date, product text, quantity numeric, unitprice numeric, totalamount numeric, paymentmethod text, customername text, flockid integer, saledescription text, paid boolean, size text, poultrycashaccountid integer, amountpaid numeric, createddate timestamp without time zone, customerid integer, poultryproductid integer, salegroupno text,
               status text, reversedat timestamp without time zone, reversedby text, reversalreason text, salereversalid integer, correctssaleid integer, correctedbysaleid integer)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT s.saleid, s.userid::text, s.farmid::text, s.saledate, s.product::text,
           s.quantity, s.unitprice, s.totalamount,
           s.paymentmethod::text, s.customername::text, s.flockid, s.saledescription::text,
           COALESCE(s.paid, TRUE) AS paid,
           s.size::text, s.poultrycashaccountid, COALESCE(s.amountpaid, 0) AS amountpaid,
           s.createddate, s.customerid,
           s.poultryproductid, s.salegroupno,
           s.status, s.reversedat, s.reversedby, s.reversalreason, s.salereversalid, s.correctssaleid,
           r.correctionsaleid
    FROM   sale s
    LEFT   JOIN poultrysalereversals r ON r.salereversalid = s.salereversalid
    WHERE  s.saleid = p_saleid AND s.farmid = p_farmid;
$function$;

CREATE FUNCTION public.spsale_getbyflock(p_flockid integer, p_farmid text)
 RETURNS TABLE(saleid integer, userid text, farmid text, saledate date, product text, quantity numeric, unitprice numeric, totalamount numeric, paymentmethod text, customername text, flockid integer, saledescription text, paid boolean, size text, poultrycashaccountid integer, amountpaid numeric, createddate timestamp without time zone, customerid integer, poultryproductid integer, salegroupno text,
               status text, reversedat timestamp without time zone, reversedby text, reversalreason text, salereversalid integer, correctssaleid integer, correctedbysaleid integer)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT s.saleid, s.userid::text, s.farmid::text, s.saledate, s.product::text,
           s.quantity, s.unitprice, s.totalamount,
           s.paymentmethod::text, s.customername::text, s.flockid, s.saledescription::text,
           COALESCE(s.paid, TRUE) AS paid,
           s.size::text, s.poultrycashaccountid, COALESCE(s.amountpaid, 0) AS amountpaid,
           s.createddate, s.customerid,
           s.poultryproductid, s.salegroupno,
           s.status, s.reversedat, s.reversedby, s.reversalreason, s.salereversalid, s.correctssaleid,
           NULL::integer
    FROM   sale s
    WHERE  s.flockid = p_flockid AND s.farmid = p_farmid AND s.status = 'Posted'
    ORDER  BY s.saledate DESC, s.createddate DESC;
$function$;

-- ------------------------------------------- 10. flock reopen reverses --
-- Same as 339 except the sale branch: it now goes through the reversal.
CREATE OR REPLACE FUNCTION public.spflock_reopen(p_farmid text, p_flockid integer, p_reason text, p_reopenedby text, p_reversesales boolean DEFAULT true)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_flock       flock%ROWTYPE;
    v_closeout    flockcloseouts%ROWTYPE;
    v_disp        record;
    v_group       uuid;
    v_shared      record;
    v_today       date;
    v_hascloseout boolean;
    v_note        text;
BEGIN
    IF p_reason IS NULL OR length(btrim(p_reason)) = 0 THEN
        RAISE EXCEPTION 'A reason is required to reopen a flock.' USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_flock FROM flock f
    WHERE  f.flockid = p_flockid AND f.farmid = p_farmid
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Flock not found on this farm.' USING ERRCODE = 'P0002';
    END IF;
    IF v_flock.closeddate IS NULL THEN
        RAISE EXCEPTION 'Flock "%" is not closed.', v_flock.name USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_closeout FROM flockcloseouts c
    WHERE  c.flockid = p_flockid AND c.farmid = p_farmid AND c.reopenedat IS NULL
    FOR UPDATE;
    -- Captured now: every PERFORM below resets FOUND.
    v_hascloseout := FOUND;

    v_today := fncompany_businessdate(p_farmid);
    v_note  := 'Flock reopened: ' || btrim(p_reason);

    -- Refuse BEFORE changing anything: a payment that also pays another sale.
    IF v_hascloseout AND p_reversesales THEN
        SELECT pp.saleid, pp.paymentnumber, pp.paymentgroupid INTO v_shared
        FROM   flockcloseoutdispositions x
        JOIN   poultrypayments pp
               ON pp.saleid = x.saleid AND pp.farmid = p_farmid
              AND COALESCE(pp.status, 'Posted') = 'Posted'
        WHERE  x.closeoutid = v_closeout.closeoutid
          AND  x.disposition = 'Sale' AND x.reversedat IS NULL
          AND  EXISTS (SELECT 1 FROM poultrypayments o
                       WHERE o.paymentgroupid = pp.paymentgroupid AND o.farmid = p_farmid
                         AND o.saleid IS DISTINCT FROM pp.saleid
                         AND COALESCE(o.status, 'Posted') = 'Posted')
        LIMIT  1;
        IF FOUND THEN
            RAISE EXCEPTION 'Payment % on sale #% also pays other sales, so it cannot be reversed with this flock. Reverse it on Payments Received first, or reopen the flock keeping its sales.',
                COALESCE(v_shared.paymentnumber, v_shared.paymentgroupid::text), v_shared.saleid
                USING ERRCODE = 'P0001';
        END IF;
    END IF;

    PERFORM set_config('app.flock_closeout', 'on', true);

    IF v_hascloseout THEN
        FOR v_disp IN
            SELECT x.dispositionid, x.disposition, x.saleid
            FROM   flockcloseoutdispositions x
            WHERE  x.closeoutid = v_closeout.closeoutid AND x.reversedat IS NULL
        LOOP
            -- Posting quantity 0 makes the append-only sync write the exact
            -- opposite of what the closeout posted.
            IF v_disp.disposition = 'Cull' THEN
                PERFORM sppoultrybirdstock_postdated(p_farmid, 'Flock Cull', 0, v_disp.dispositionid,
                                                     v_today, NULL, p_reopenedby);
            ELSIF v_disp.disposition = 'Transfer' THEN
                PERFORM sppoultrybirdstock_postdated(p_farmid, 'Flock Transfer Out', 0, v_disp.dispositionid,
                                                     v_today, NULL, p_reopenedby);
            ELSIF v_disp.disposition = 'Sale' AND p_reversesales
                  AND EXISTS (SELECT 1 FROM sale s WHERE s.saleid = v_disp.saleid AND s.farmid = p_farmid
                                                     AND s.status = 'Posted') THEN

                -- Keep what the sale was, for the history.
                UPDATE flockcloseoutdispositions x
                SET    saletotalamount  = s.totalamount,
                       salecustomername = s.customername
                FROM   sale s
                WHERE  x.dispositionid = v_disp.dispositionid
                  AND  s.saleid = v_disp.saleid AND s.farmid = p_farmid;

                -- 351: the sale is REVERSED, not deleted -- stock back, allocations
                -- released and its payments reversed (Money Out on the original
                -- account), exactly what reopening has always meant for the money.
                PERFORM sppoultrysale_reverse(
                    p_farmid, v_disp.saleid, 'Flock reopened', btrim(p_reason),
                    (SELECT COALESCE(jsonb_object_agg(m->>'key', 'ReversePayment'), '{}'::jsonb)
                     FROM   jsonb_array_elements(fnpoultrysale_reversalstate(p_farmid, v_disp.saleid)->'payments') m),
                    NULL, NULL, p_reopenedby);

                UPDATE flockcloseoutdispositions x
                SET    salereversedat = (now() AT TIME ZONE 'utc')
                WHERE  x.dispositionid = v_disp.dispositionid;
            END IF;
        END LOOP;

        UPDATE flockcloseoutdispositions x
        SET    reversedat = (now() AT TIME ZONE 'utc')
        WHERE  x.closeoutid = v_closeout.closeoutid AND x.reversedat IS NULL;

        UPDATE flockcloseouts c
        SET    reopenedat   = (now() AT TIME ZONE 'utc'),
               reopenedby   = p_reopenedby,
               reopenreason = btrim(p_reason)
        WHERE  c.closeoutid = v_closeout.closeoutid;
    END IF;

    UPDATE flock f
    SET    active             = COALESCE(v_closeout.wasactive, TRUE),
           inactivationreason = CASE WHEN COALESCE(v_closeout.wasactive, TRUE) THEN NULL
                                     ELSE 'other' END,
           otherreason        = CASE WHEN COALESCE(v_closeout.wasactive, TRUE) THEN NULL
                                     ELSE 'Reopened after closeout: ' || btrim(p_reason) END,
           closeddate         = NULL,
           closedat           = NULL,
           closedby           = NULL,
           closereason        = NULL,
           closeoutid         = NULL,
           updatedat          = (now() AT TIME ZONE 'utc')
    WHERE  f.flockid = p_flockid AND f.farmid = p_farmid;

    PERFORM set_config('app.flock_closeout', 'off', true);

    RETURN v_closeout.closeoutid;
END
$function$;


-- ------------------------------------------------------- 11. permissions --
-- POST api/Sale/{id}/reverse resolves to `approve` (ResolveAction maps the
-- /reverse segment there), and the catalog has no poultry.sales.approve. Seed
-- it, carried over from whoever could DELETE a sale -- reversing is what
-- delete has become. Correct Sale is a reversal plus an ordinary create.
DO $iam$
DECLARE
    v_keys  integer := 0;
    v_roles integer := 0;
    v_users integer := 0;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '351: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'poultry.sales.approve', p.module, p.resource, 'approve',
           p.permissiongroup, p.resourcelabel,
           'Reverse a posted sale (and Correct Sale, which reverses it first). Undoes its revenue, '
           || 'stock and allocations; its money is kept as customer credit or paid back out.',
           p.companytype, TRUE, p.sortorder
    FROM   iampermissions p
    WHERE  p.permissionkey = 'poultry.sales.delete'
    ON CONFLICT (permissionkey) DO NOTHING;
    GET DIAGNOSTICS v_keys = ROW_COUNT;

    IF to_regclass('public.iamrolepermissions') IS NOT NULL THEN
        INSERT INTO iamrolepermissions (roleid, permissionkey)
        SELECT rp.roleid, 'poultry.sales.approve'
        FROM   iamrolepermissions rp
        WHERE  rp.permissionkey = 'poultry.sales.delete'
          AND  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = 'poultry.sales.approve')
        ON CONFLICT (roleid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_roles = ROW_COUNT;
    END IF;

    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        INSERT INTO iamuserpermissions (userid, farmid, permissionkey, effect, reason, grantedby, grantedat)
        SELECT up.userid, up.farmid, 'poultry.sales.approve', up.effect,
               'Carried over from poultry.sales.delete by migration 351',
               up.grantedby, (now() at time zone 'utc')
        FROM   iamuserpermissions up
        WHERE  up.permissionkey = 'poultry.sales.delete'
          AND  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = 'poultry.sales.approve')
          AND  (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_users = ROW_COUNT;
    END IF;

    RAISE NOTICE '351: % catalog key(s), % role grant(s), % user grant(s) added.', v_keys, v_roles, v_users;
END
$iam$;

COMMIT;

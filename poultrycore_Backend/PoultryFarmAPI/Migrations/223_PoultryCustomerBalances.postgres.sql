-- =============================================================================
-- 223_PoultryCustomerBalances.postgres.sql
--
-- Purpose
-- -------
-- The poultry Customer Balances control page: who owes us money, which unpaid
-- sales make up each balance, and one payment allocated across several of them.
--
-- Builds on 222 (customerpaymentallocation). Everything here treats `sale` as
-- the source of truth -- no second balance is stored anywhere.
--
-- Four things this file has to get right
-- --------------------------------------
--
-- 1. THE BALANCE FORMULA. `sale.paid` is a boolean that DEFAULTS TRUE, and a
--    cash sale is written with paid = true and amountpaid = 0. So the balance is
--    NOT `totalamount - amountpaid`; that would show every cash sale in the
--    history of the farm as unpaid. It is:
--
--        CASE WHEN paid THEN 0 ELSE GREATEST(totalamount - amountpaid, 0) END
--
--    This is the same rule migration 197 established for the customer-balance
--    report, and fnpoultrysalebalance below is now the single place it lives.
--
-- 2. CUSTOMER IDENTITY. `sale` had no customerid at all -- the customer was a
--    free-text name with no link to `customer`, which is why the existing report
--    groups by a string and cannot show a phone number or open a profile. This
--    adds the column, backfills it by case-insensitive name match, and creates a
--    customer row for every name that had none. From here on spsale_insert
--    resolves the link itself, so nothing upstream has to change for new sales
--    to be linked.
--
-- 3. ONE PAYMENT, MANY SALES. poultrypayments.saleid is NOT NULL and
--    sale.amountpaid is recomputed as SUM(poultrypayments.amount) -- an
--    invariant the Sales page, the Payments page and the cash sync all depend
--    on. Rather than break it with a new header table, a bulk payment writes ONE
--    poultrypayments ROW PER SALE sharing a `paymentgroupid`. The GROUP is the
--    payment the user thinks they made; the rows are its allocations. Both
--    routes -- the Sales page dialog and the balances page -- go through the
--    same function and produce the same shape, which is the point.
--
-- 4. CASH ON EVERY PAYMENT, NOT JUST THE LAST ONE. sppoultrysalecash_sync posted
--    the sale's FULL total, and only once paid = true. A part payment therefore
--    moved the receivable but no money, so a farm collecting GHC 300 of a GHC
--    500 sale saw nothing in its cash account until the final GHC 200 landed.
--    It now posts the cumulative amountpaid. Cash per sale is still exactly ONE
--    collapsed row (sourcetype 'Sale'), so nothing double-counts and reversal is
--    just another re-sync.
--
--    !! This changes existing balances for farms that have part-paid sales.
--       Money that was genuinely received but invisible will appear. Run
--       sppoultrycashaccount_reconcilebalance afterwards and diff.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Sale -> customer link.
-- -----------------------------------------------------------------------------
ALTER TABLE sale ADD COLUMN IF NOT EXISTS customerid integer NULL;
CREATE INDEX IF NOT EXISTS ix_sale_farm_customer ON sale (farmid, customerid);

-- The group-id that turns N per-sale payment rows into one payment.
ALTER TABLE poultrypayments ADD COLUMN IF NOT EXISTS paymentgroupid uuid NULL;
CREATE INDEX IF NOT EXISTS ix_poultrypayments_group ON poultrypayments (farmid, paymentgroupid);

-- Every historical payment is its own group of one.
UPDATE poultrypayments SET paymentgroupid = gen_random_uuid() WHERE paymentgroupid IS NULL;

-- -----------------------------------------------------------------------------
-- 2. Backfill the link.
-- -----------------------------------------------------------------------------
-- Match on trimmed lower-case name within the farm. Names that match nothing get
-- a customer row created for them -- the alternative is a balances page that
-- silently omits most of the farm's receivables.
--
-- The judgement call: 'Ama Store' and 'ama store' collapse into one customer,
-- and two genuinely different customers who share a name merge. That is the
-- right trade for a page whose job is to total up what one person owes, but it
-- is a real merge, so the counts are reported below.
DO $backfill$
DECLARE
    v_created integer := 0;
    v_linked  integer := 0;
BEGIN
    INSERT INTO customer (userid, farmid, name, createddate, datecreated, createdby)
    SELECT DISTINCT ON (s.farmid, lower(btrim(s.customername)))
           COALESCE(s.userid, '0'), s.farmid, btrim(s.customername),
           (now() at time zone 'utc'), (now() at time zone 'utc'), 'migration-223'
    FROM   sale s
    WHERE  s.customerid IS NULL
      AND  s.customername IS NOT NULL
      AND  btrim(s.customername) <> ''
      AND  NOT EXISTS (
            SELECT 1 FROM customer c
            WHERE  c.farmid = s.farmid
              AND  lower(btrim(c.name)) = lower(btrim(s.customername)))
    ORDER  BY s.farmid, lower(btrim(s.customername)), s.saleid;
    GET DIAGNOSTICS v_created = ROW_COUNT;

    UPDATE sale s
    SET    customerid = c.customerid
    FROM   customer c
    WHERE  s.customerid IS NULL
      AND  s.customername IS NOT NULL
      AND  btrim(s.customername) <> ''
      AND  c.farmid = s.farmid
      AND  lower(btrim(c.name)) = lower(btrim(s.customername));
    GET DIAGNOSTICS v_linked = ROW_COUNT;

    RAISE NOTICE '223: created % customer(s) from sale names, linked % sale(s).', v_created, v_linked;
END
$backfill$;

-- Stamp the customer onto historical payments so payment history can be read
-- per customer without joining back through the sale every time.
UPDATE poultrypayments pp
SET    customerid = s.customerid
FROM   sale s
WHERE  pp.customerid IS NULL
  AND  s.saleid = pp.saleid AND s.farmid = pp.farmid
  AND  s.customerid IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 3. The balance formula, in one place.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrysalebalance(
    p_paid boolean, p_totalamount numeric, p_amountpaid numeric)
RETURNS numeric
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE WHEN COALESCE(p_paid, TRUE) THEN 0::numeric
                ELSE GREATEST(COALESCE(p_totalamount, 0) - COALESCE(p_amountpaid, 0), 0)
           END::numeric(14,2);
$function$;

-- Effective amount received against a sale, for statements and totals. A cash
-- sale (paid, amountpaid 0) counted the full total; a credit sale counts what
-- actually came in.
CREATE OR REPLACE FUNCTION public.fnpoultrysalereceived(
    p_paid boolean, p_totalamount numeric, p_amountpaid numeric)
RETURNS numeric
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE WHEN COALESCE(p_paid, TRUE) THEN COALESCE(p_totalamount, 0)
                ELSE LEAST(COALESCE(p_amountpaid, 0), COALESCE(p_totalamount, 0))
           END::numeric(14,2);
$function$;

-- -----------------------------------------------------------------------------
-- 4. Cash sync -- post what has actually been received.
-- -----------------------------------------------------------------------------
-- Signature unchanged so SaleService keeps working. The only change is which
-- amount gets posted:
--
--   paid = true   -> p_amount (the sale total)          [unchanged]
--   paid = false  -> the sale's current amountpaid      [NEW: part payments]
--
-- Insert of an unpaid sale still posts nothing, because amountpaid is 0 at that
-- point. Delete still posts nothing, because SaleService passes a null account.
CREATE OR REPLACE FUNCTION public.sppoultrysalecash_sync(
    p_farmid text, p_saleid integer, p_poultrycashaccountid integer DEFAULT NULL::integer,
    p_amount numeric DEFAULT 0, p_paid boolean DEFAULT true,
    p_description text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_bal  numeric(14,2);
    v_post numeric(14,2);
BEGIN
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

    -- Record the chosen account on the sale row.
    UPDATE sale s SET poultrycashaccountid = p_poultrycashaccountid
    WHERE  s.saleid = p_saleid AND s.farmid = p_farmid;

    -- How much money has actually reached the farm for this sale.
    IF COALESCE(p_paid, TRUE) THEN
        v_post := COALESCE(p_amount, 0);
    ELSE
        SELECT COALESCE(s.amountpaid, 0) INTO v_post
        FROM   sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid LIMIT 1;
        -- Never post more than the sale is worth, whatever amountpaid says.
        IF COALESCE(p_amount, 0) > 0 THEN
            v_post := LEAST(COALESCE(v_post, 0), p_amount);
        END IF;
    END IF;

    IF (p_poultrycashaccountid IS NOT NULL AND COALESCE(v_post, 0) > 0
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

-- -----------------------------------------------------------------------------
-- 5. Sale insert/update resolve the customer link themselves.
-- -----------------------------------------------------------------------------
-- Dropped first: adding a defaulted parameter to an existing function creates an
-- OVERLOAD rather than replacing it, and two candidates make every named call
-- ambiguous.
DROP FUNCTION IF EXISTS public.spsale_insert(text,text,timestamp,text,numeric,numeric,numeric,text,text,integer,text,boolean,text);
DROP FUNCTION IF EXISTS public.spsale_update(text,text,integer,timestamp,text,numeric,numeric,numeric,text,text,integer,text,boolean,text);

-- Resolve a free-text name to a customer, creating one if needed. Returns NULL
-- for a blank name (a walk-in cash sale has no customer and should not invent
-- one).
CREATE OR REPLACE FUNCTION public.fnpoultrycustomer_resolve(
    p_farmid text, p_customername text, p_userid text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id   integer;
    v_name text := btrim(COALESCE(p_customername, ''));
BEGIN
    IF v_name = '' THEN RETURN NULL; END IF;

    SELECT c.customerid INTO v_id
    FROM   customer c
    WHERE  c.farmid = p_farmid AND lower(btrim(c.name)) = lower(v_name)
    ORDER  BY c.customerid
    LIMIT  1;

    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    INSERT INTO customer (userid, farmid, name, createddate, datecreated, createdby)
    VALUES (COALESCE(p_userid, '0'), p_farmid, v_name,
            (now() at time zone 'utc'), (now() at time zone 'utc'), p_userid)
    RETURNING customerid INTO v_id;

    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spsale_insert(
    p_userid text, p_farmid text, p_saledate timestamp without time zone, p_product text,
    p_quantity numeric, p_unitprice numeric, p_totalamount numeric,
    p_paymentmethod text DEFAULT NULL::text, p_customername text DEFAULT NULL::text,
    p_flockid integer DEFAULT NULL::integer, p_saledescription text DEFAULT NULL::text,
    p_paid boolean DEFAULT true, p_size text DEFAULT NULL::text,
    p_customerid integer DEFAULT NULL::integer)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_newid integer;
    v_p     text;
    v_bq    numeric;
    v_cust  integer := p_customerid;
BEGIN
    IF v_cust IS NULL THEN
        v_cust := fnpoultrycustomer_resolve(p_farmid, p_customername, p_userid);
    END IF;

    INSERT INTO sale (userid, farmid, saledate, product, quantity, unitprice, totalamount, paymentmethod, customername, customerid, flockid, saledescription, paid, size, createddate)
    VALUES (p_userid, p_farmid, p_saledate, p_product, p_quantity, p_unitprice, p_totalamount, p_paymentmethod, p_customername, v_cust, p_flockid, p_saledescription, COALESCE(p_paid, TRUE), p_size, (now() at time zone 'utc'))
    RETURNING saleid INTO v_newid;

    v_p := lower(COALESCE(p_product, ''));
    -- Bird sale: bird-like product, not eggs.
    IF (v_p = 'birds' OR v_p LIKE '%bird%' OR v_p LIKE '%chick%' OR v_p LIKE '%cockerel%') AND v_p NOT LIKE '%egg%' AND COALESCE(p_quantity, 0) > 0 THEN
        v_bq := -(p_quantity::numeric(14,3));
        PERFORM sppoultrybirdstock_sync(p_farmid, 'Bird Sale', v_bq, v_newid, 'Bird sale', p_userid);
    -- Egg sale: product mentions eggs -> reduce egg finished-product stock.
    ELSIF (v_p LIKE '%egg%') AND COALESCE(p_quantity, 0) > 0 THEN
        PERFORM sppoultryeggstock_syncforsale(p_farmid, v_newid, p_quantity, p_userid);
    END IF;

    RETURN v_newid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spsale_update(
    p_userid text, p_farmid text, p_saleid integer, p_saledate timestamp without time zone,
    p_product text, p_quantity numeric, p_unitprice numeric, p_totalamount numeric,
    p_paymentmethod text DEFAULT NULL::text, p_customername text DEFAULT NULL::text,
    p_flockid integer DEFAULT NULL::integer, p_saledescription text DEFAULT NULL::text,
    p_paid boolean DEFAULT true, p_size text DEFAULT NULL::text,
    p_customerid integer DEFAULT NULL::integer)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_p      text;
    v_isbird boolean;
    v_isegg  boolean;
    v_bq     numeric;
    v_eq     numeric;
    v_cust   integer := p_customerid;
BEGIN
    IF v_cust IS NULL THEN
        v_cust := fnpoultrycustomer_resolve(p_farmid, p_customername, p_userid);
    END IF;

    UPDATE sale s
    SET saledate = p_saledate, product = p_product, quantity = p_quantity, unitprice = p_unitprice, totalamount = p_totalamount,
        paymentmethod = p_paymentmethod, customername = p_customername, customerid = v_cust, flockid = p_flockid, saledescription = p_saledescription,
        paid = COALESCE(p_paid, TRUE), size = p_size
    WHERE s.saleid = p_saleid AND s.farmid = p_farmid;

    -- Keep the customer stamped on this sale's payments in step with an edit.
    UPDATE poultrypayments pp SET customerid = v_cust
    WHERE  pp.saleid = p_saleid AND pp.farmid = p_farmid;

    v_p := lower(COALESCE(p_product, ''));
    v_isbird := (v_p = 'birds' OR v_p LIKE '%bird%' OR v_p LIKE '%chick%' OR v_p LIKE '%cockerel%') AND v_p NOT LIKE '%egg%';
    v_isegg  := v_p LIKE '%egg%';

    -- Bird: apply if bird-like, else 0 removes any prior bird-sale movement.
    v_bq := CASE WHEN v_isbird THEN -(COALESCE(p_quantity, 0)::numeric(14,3)) ELSE 0 END;
    PERFORM sppoultrybirdstock_sync(p_farmid, 'Bird Sale', v_bq, p_saleid, 'Bird sale', p_userid);

    -- Egg: apply if egg, else 0 removes any prior egg-sale movement.
    v_eq := CASE WHEN v_isegg THEN COALESCE(p_quantity, 0)::numeric(18,3) ELSE 0 END;
    PERFORM sppoultryeggstock_syncforsale(p_farmid, p_saleid, v_eq, p_userid);
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Sale reads carry the customer link.
-- -----------------------------------------------------------------------------
-- Return type changes, so these must be dropped rather than replaced. The new
-- column is appended last; SaleService maps by name, so nothing breaks.
DROP FUNCTION IF EXISTS public.spsale_getall(text);
DROP FUNCTION IF EXISTS public.spsale_getbyid(integer,text);

CREATE OR REPLACE FUNCTION public.spsale_getall(p_farmid text)
RETURNS TABLE(saleid integer, userid text, farmid text, saledate date, product text,
              quantity numeric, unitprice numeric, totalamount numeric, paymentmethod text,
              customername text, flockid integer, saledescription text, paid boolean, size text,
              poultrycashaccountid integer, amountpaid numeric,
              createddate timestamp without time zone, customerid integer)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.saleid, s.userid::text, s.farmid::text, s.saledate, s.product::text,
           s.quantity, s.unitprice, s.totalamount,
           s.paymentmethod::text, s.customername::text, s.flockid, s.saledescription::text,
           COALESCE(s.paid, TRUE) AS paid,
           s.size::text, s.poultrycashaccountid, COALESCE(s.amountpaid, 0) AS amountpaid,
           s.createddate, s.customerid
    FROM sale s
    WHERE s.farmid = p_farmid
    ORDER BY s.saledate DESC, s.createddate DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spsale_getbyid(p_saleid integer, p_farmid text)
RETURNS TABLE(saleid integer, userid text, farmid text, saledate date, product text,
              quantity numeric, unitprice numeric, totalamount numeric, paymentmethod text,
              customername text, flockid integer, saledescription text, paid boolean, size text,
              poultrycashaccountid integer, amountpaid numeric,
              createddate timestamp without time zone, customerid integer)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.saleid, s.userid::text, s.farmid::text, s.saledate, s.product::text,
           s.quantity, s.unitprice, s.totalamount,
           s.paymentmethod::text, s.customername::text, s.flockid, s.saledescription::text,
           COALESCE(s.paid, TRUE) AS paid,
           s.size::text, s.poultrycashaccountid, COALESCE(s.amountpaid, 0) AS amountpaid,
           s.createddate, s.customerid
    FROM sale s
    WHERE s.saleid = p_saleid AND s.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. Recompute one sale from its posted payments.
-- -----------------------------------------------------------------------------
-- The single place amountpaid / paid / cash are brought back into agreement with
-- the payment rows. Called after recording and after reversing, so the two paths
-- cannot drift.
--
-- Only POSTED payments count -- before this file reversal did not exist, so the
-- old SUM had no status filter and a reversed payment would have kept paying the
-- sale forever.
CREATE OR REPLACE FUNCTION public.sppoultrysale_recompute(
    p_farmid text, p_saleid integer,
    p_cashaccountid integer DEFAULT NULL::integer, p_createdby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_total   numeric(14,2);
    v_acct    integer;
    v_sum     numeric(14,2);
    v_newpaid boolean;
BEGIN
    SELECT s.totalamount, s.poultrycashaccountid INTO v_total, v_acct
    FROM   sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid LIMIT 1;

    IF v_total IS NULL THEN RETURN; END IF;

    v_sum := COALESCE((SELECT SUM(pp.amount) FROM poultrypayments pp
                       WHERE pp.saleid = p_saleid AND pp.farmid = p_farmid
                         AND COALESCE(pp.status, 'Posted') = 'Posted'), 0);
    v_newpaid := COALESCE(v_sum >= v_total, FALSE);

    UPDATE sale s SET amountpaid = v_sum, paid = v_newpaid
    WHERE  s.saleid = p_saleid AND s.farmid = p_farmid;

    PERFORM sppoultrysalecash_sync(p_farmid, p_saleid, COALESCE(p_cashaccountid, v_acct),
                                   v_total, v_newpaid, 'Sale payment', p_createdby);
END;
$function$;

-- -----------------------------------------------------------------------------
-- 8. Record a customer payment across one or more sales.
-- -----------------------------------------------------------------------------
-- p_allocations is a JSON array of {"saleid": <int>, "amount": <numeric>}.
--
-- Keys are LOWER CASE and the recordset identifiers below are unquoted so they
-- fold to lower case and match. Migration 214 lost every line of a water usage
-- entry to exactly this: json_to_recordset matches keys case-sensitively, so a
-- camelCase key against an unquoted identifier silently produces NULL rows.
--
-- Overpayment is blocked: the allocations must add up to the payment, to the
-- pesewa. There is no customer credit balance in this build, so money that
-- cannot be applied has nowhere to live.
--
-- Returns the paymentgroupid -- the id of the payment as the user understands
-- it. The per-sale poultrypayments rows sharing that group are its allocations.
CREATE OR REPLACE FUNCTION public.sppoultrycustomerpayment_record(
    p_farmid text,
    p_customerid integer,
    p_amount numeric,
    p_allocations jsonb,
    p_paymentmethod text DEFAULT NULL::text,
    p_paymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone,
    p_cashaccountid integer DEFAULT NULL::integer,
    p_reference text DEFAULT NULL::text,
    p_note text DEFAULT NULL::text,
    p_sourcetype text DEFAULT 'CustomerBalances'::text,
    p_createdby text DEFAULT NULL::text)
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

    -- Every id must resolve, or the loop below would quietly process fewer sales
    -- than were validated and the payment would post short.
    SELECT COUNT(*) INTO v_missing
    FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
           AS a(saleid integer, amount numeric)
    WHERE  a.saleid IS NOT NULL AND COALESCE(a.amount, 0) <> 0
      AND  NOT EXISTS (SELECT 1 FROM sale s
                       WHERE s.saleid = a.saleid AND s.farmid = p_farmid);
    IF v_missing > 0 THEN
        RAISE EXCEPTION '% of the selected sales do not belong to this company.', v_missing;
    END IF;

    -- Oldest first, so the before/after pair on each allocation reads the way the
    -- statement will.
    FOR v_row IN
        SELECT a.saleid, a.amount::numeric(14,2) AS amount,
               s.totalamount, s.amountpaid, s.paid, s.saledate
        FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
               AS a(saleid integer, amount numeric)
        JOIN   sale s ON s.saleid = a.saleid AND s.farmid = p_farmid
        WHERE  a.saleid IS NOT NULL AND COALESCE(a.amount, 0) <> 0
        ORDER  BY s.saledate, s.saleid
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

-- The Sales page's existing endpoint, now a one-allocation call into the same
-- function. Signature and return value unchanged, so PoultryPaymentService and
-- the Sales page dialog keep working untouched -- and a payment taken there is
-- indistinguishable from one taken on the balances page.
CREATE OR REPLACE FUNCTION public.sppoultrypayment_record(
    p_farmid text, p_saleid integer, p_amount numeric,
    p_paymentmethod text DEFAULT NULL::text,
    p_paymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone,
    p_reference text DEFAULT NULL::text, p_note text DEFAULT NULL::text,
    p_createdby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_cust  integer;
    v_acct  integer;
    v_name  text;
    v_group uuid;
    v_id    integer;
BEGIN
    SELECT s.customerid, s.poultrycashaccountid, s.customername
    INTO   v_cust, v_acct, v_name
    FROM   sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sale does not belong to this company.';
    END IF;

    -- Sales predating the customerid column, or entered with a name that was
    -- never linked, still have to be payable from the Sales page.
    IF v_cust IS NULL THEN
        v_cust := fnpoultrycustomer_resolve(p_farmid, v_name, p_createdby);
        IF v_cust IS NULL THEN
            RAISE EXCEPTION 'This sale has no customer. Add a customer name to the sale before recording a payment.';
        END IF;
        UPDATE sale s SET customerid = v_cust WHERE s.saleid = p_saleid AND s.farmid = p_farmid;
    END IF;

    v_group := sppoultrycustomerpayment_record(
        p_farmid, v_cust, p_amount,
        jsonb_build_array(jsonb_build_object('saleid', p_saleid, 'amount', p_amount)),
        p_paymentmethod, p_paymentdate, v_acct, p_reference, p_note, 'SaleEntry', p_createdby);

    SELECT pp.poultrypaymentid INTO v_id
    FROM   poultrypayments pp WHERE pp.paymentgroupid = v_group LIMIT 1;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 9. Reverse a customer payment.
-- -----------------------------------------------------------------------------
-- Append-only: nothing is deleted. The payment rows and their allocations are
-- marked Reversed, every affected sale is recomputed from what is left, and the
-- cash sync reposts each sale's cash from its new amountpaid -- which nets the
-- money back out without a compensating row, because a sale's cash is a single
-- collapsed transaction by design.
CREATE OR REPLACE FUNCTION public.sppoultrycustomerpayment_reverse(
    p_farmid text, p_paymentgroupid uuid,
    p_reason text DEFAULT NULL::text, p_reversedby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_now   timestamp := (now() at time zone 'utc');
    v_count integer := 0;
    v_sale  integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM poultrypayments pp
                   WHERE pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Payment not found for this company.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM poultrypayments pp
                   WHERE pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid
                     AND COALESCE(pp.status, 'Posted') = 'Posted') THEN
        RAISE EXCEPTION 'This payment has already been reversed.';
    END IF;

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

    FOR v_sale IN
        SELECT DISTINCT pp.saleid FROM poultrypayments pp
        WHERE  pp.paymentgroupid = p_paymentgroupid AND pp.farmid = p_farmid
    LOOP
        PERFORM sppoultrysale_recompute(p_farmid, v_sale, NULL, p_reversedby);
    END LOOP;

    RETURN v_count;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 10. Reads -- the balances page.
-- -----------------------------------------------------------------------------
-- p_status: All | Partial | Unpaid | Overdue. Filters which SALES count, then
-- the customer totals are built from whatever survives -- so "Overdue" gives an
-- overdue-only balance per customer rather than a full balance on an overdue
-- customer.
CREATE OR REPLACE FUNCTION public.sppoultrycustomerbalances(
    p_farmid text,
    p_from date DEFAULT NULL::date,
    p_to date DEFAULT NULL::date,
    p_customerid integer DEFAULT NULL::integer,
    p_status text DEFAULT 'All'::text,
    p_minbalance numeric DEFAULT NULL::numeric,
    p_search text DEFAULT NULL::text)
RETURNS TABLE(
    customerid       integer,
    customername     text,
    contactphone     text,
    contactemail     text,
    paymenttermsdays integer,
    totalbalance     numeric,
    opensalecount    integer,
    oldestsaledate   date,
    latestsaledate   date,
    lastpaymentdate  timestamp without time zone,
    overdueamount    numeric,
    totalsales       numeric,
    totalpaid        numeric)
LANGUAGE sql
STABLE
AS $function$
    WITH opensales AS (
        SELECT s.customerid, s.saleid, s.saledate, s.totalamount,
               fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid)  AS balance,
               fnpoultrysalereceived(s.paid, s.totalamount, s.amountpaid) AS received,
               COALESCE(c.paymenttermsdays, 0)                            AS terms
        FROM   sale s
        JOIN   customer c ON c.customerid = s.customerid AND c.farmid = s.farmid
        WHERE  s.farmid = p_farmid
          AND  s.customerid IS NOT NULL
          AND  (p_customerid IS NULL OR s.customerid = p_customerid)
          AND  (p_from IS NULL OR s.saledate >= p_from)
          AND  (p_to   IS NULL OR s.saledate <= p_to)
          AND  fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid) > 0
    ),
    filtered AS (
        SELECT o.*,
               (o.saledate + o.terms)                          AS duedate,
               ((o.saledate + o.terms) < CURRENT_DATE)         AS isoverdue
        FROM   opensales o
        WHERE  CASE COALESCE(p_status, 'All')
                    WHEN 'Partial' THEN o.received > 0
                    WHEN 'Unpaid'  THEN o.received = 0
                    WHEN 'Overdue' THEN (o.saledate + o.terms) < CURRENT_DATE
                    ELSE TRUE
               END
    )
    SELECT c.customerid,
           c.name::text,
           c.contactphone::text,
           c.contactemail::text,
           COALESCE(c.paymenttermsdays, 0),
           SUM(f.balance)::numeric(14,2),
           COUNT(*)::integer,
           MIN(f.saledate),
           MAX(f.saledate),
           (SELECT MAX(pp.paymentdate) FROM poultrypayments pp
            WHERE pp.farmid = p_farmid AND pp.customerid = c.customerid
              AND COALESCE(pp.status, 'Posted') = 'Posted'),
           SUM(CASE WHEN f.isoverdue THEN f.balance ELSE 0 END)::numeric(14,2),
           SUM(f.totalamount)::numeric(14,2),
           SUM(f.received)::numeric(14,2)
    FROM   filtered f
    JOIN   customer c ON c.customerid = f.customerid AND c.farmid = p_farmid
    WHERE  (p_search IS NULL OR btrim(p_search) = ''
            OR c.name ILIKE '%' || btrim(p_search) || '%'
            OR COALESCE(c.contactphone, '') ILIKE '%' || btrim(p_search) || '%')
    GROUP  BY c.customerid, c.name, c.contactphone, c.contactemail, c.paymenttermsdays
    HAVING (p_minbalance IS NULL OR SUM(f.balance) >= p_minbalance)
    ORDER  BY SUM(f.balance) DESC;
$function$;

-- The sale rows behind one customer's balance -- what the expandable row shows,
-- and what the allocation grid is built from.
CREATE OR REPLACE FUNCTION public.sppoultrycustomeropensales(
    p_farmid text,
    p_customerid integer,
    p_from date DEFAULT NULL::date,
    p_to date DEFAULT NULL::date,
    p_status text DEFAULT 'All'::text)
RETURNS TABLE(
    saleid          integer,
    saledate        date,
    product         text,
    saledescription text,
    totalamount     numeric,
    amountpaid      numeric,
    balance         numeric,
    duedate         date,
    agedays         integer,
    status          text,
    isoverdue       boolean,
    poultrycashaccountid integer)
LANGUAGE sql
STABLE
AS $function$
    SELECT s.saleid, s.saledate, s.product::text, s.saledescription::text,
           s.totalamount,
           fnpoultrysalereceived(s.paid, s.totalamount, s.amountpaid),
           fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid),
           (s.saledate + COALESCE(c.paymenttermsdays, 0))::date,
           GREATEST((CURRENT_DATE - s.saledate), 0)::integer,
           CASE WHEN fnpoultrysalereceived(s.paid, s.totalamount, s.amountpaid) > 0
                THEN 'Partially Paid' ELSE 'Unpaid' END::text,
           ((s.saledate + COALESCE(c.paymenttermsdays, 0)) < CURRENT_DATE),
           s.poultrycashaccountid
    FROM   sale s
    JOIN   customer c ON c.customerid = s.customerid AND c.farmid = s.farmid
    WHERE  s.farmid = p_farmid
      AND  s.customerid = p_customerid
      AND  (p_from IS NULL OR s.saledate >= p_from)
      AND  (p_to   IS NULL OR s.saledate <= p_to)
      AND  fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid) > 0
      AND  CASE COALESCE(p_status, 'All')
                WHEN 'Partial' THEN fnpoultrysalereceived(s.paid, s.totalamount, s.amountpaid) > 0
                WHEN 'Unpaid'  THEN fnpoultrysalereceived(s.paid, s.totalamount, s.amountpaid) = 0
                WHEN 'Overdue' THEN (s.saledate + COALESCE(c.paymenttermsdays, 0)) < CURRENT_DATE
                ELSE TRUE
           END
    ORDER  BY s.saledate, s.saleid;
$function$;

-- Headline figures for the summary cards. One round trip rather than five.
CREATE OR REPLACE FUNCTION public.sppoultrycustomerbalancesummary(p_farmid text)
RETURNS TABLE(
    totalbalance          numeric,
    customersowing        integer,
    overduebalance        numeric,
    paymentsreceivedtoday numeric,
    largestbalance        numeric,
    largestbalancecustomer text)
LANGUAGE sql
STABLE
AS $function$
    WITH b AS (SELECT * FROM sppoultrycustomerbalances(p_farmid))
    SELECT COALESCE(SUM(b.totalbalance), 0)::numeric(14,2),
           COUNT(*)::integer,
           COALESCE(SUM(b.overdueamount), 0)::numeric(14,2),
           COALESCE((SELECT SUM(pp.amount) FROM poultrypayments pp
                     WHERE pp.farmid = p_farmid
                       AND COALESCE(pp.status, 'Posted') = 'Posted'
                       AND pp.paymentdate::date = CURRENT_DATE), 0)::numeric(14,2),
           COALESCE(MAX(b.totalbalance), 0)::numeric(14,2),
           (SELECT b2.customername FROM b b2 ORDER BY b2.totalbalance DESC LIMIT 1)
    FROM b;
$function$;

-- -----------------------------------------------------------------------------
-- 11. Customer statement.
-- -----------------------------------------------------------------------------
-- Poultry has no customer ledger table, so the statement is DERIVED from sales
-- and payments rather than read from one. That is the right call here: a ledger
-- would be a second copy of the balance, which is the exact thing this whole
-- feature exists to avoid.
--
-- A cash sale (paid, no payment rows) emits its debit AND a matching credit on
-- the same day, so the running balance behaves and the line is self-explaining
-- rather than mysteriously absent.
CREATE OR REPLACE FUNCTION public.sppoultrycustomerstatement(
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
    saleid         integer,
    sortkey        integer)
LANGUAGE sql
STABLE
AS $function$
    WITH lines AS (
        -- Opening balance: what was owed before the window opened.
        --
        -- p_from NULL means "the whole history", and a whole-history statement
        -- has nothing before it -- so the opening MUST be zero. Reusing the
        -- usual `p_from IS NULL OR ...` idiom here would instead match every
        -- sale ever and count the entire ledger twice.
        SELECT CASE WHEN p_from IS NULL THEN NULL::date ELSE p_from END AS entrydate,
               'OpeningBalance'::text  AS entrytype,
               NULL::text              AS reference,
               'Opening balance'::text AS description,
               CASE WHEN p_from IS NULL THEN 0::numeric(14,2) ELSE COALESCE((
                   SELECT SUM(fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid))
                   FROM   sale s
                   WHERE  s.farmid = p_farmid AND s.customerid = p_customerid
                     AND  s.saledate < p_from), 0)::numeric(14,2) END AS debit,
               0::numeric(14,2)        AS credit,
               NULL::integer           AS saleid,
               0                       AS sortkey,
               0                       AS pin

        UNION ALL

        SELECT s.saledate, 'Sale'::text,
               ('S' || s.saleid::text)::text,
               COALESCE(NULLIF(btrim(s.saledescription), ''), s.product)::text,
               s.totalamount::numeric(14,2), 0::numeric(14,2), s.saleid, 1, 1
        FROM   sale s
        WHERE  s.farmid = p_farmid AND s.customerid = p_customerid
          AND  (p_from IS NULL OR s.saledate >= p_from)
          AND  (p_to   IS NULL OR s.saledate <= p_to)

        UNION ALL

        -- Settled at the counter: no payment row exists, so without this the
        -- statement would show the debit and never the receipt.
        SELECT s.saledate, 'Payment'::text,
               ('S' || s.saleid::text)::text,
               'Paid at point of sale'::text,
               0::numeric(14,2), s.totalamount::numeric(14,2), s.saleid, 2, 1
        FROM   sale s
        WHERE  s.farmid = p_farmid AND s.customerid = p_customerid
          AND  COALESCE(s.paid, TRUE)
          AND  (p_from IS NULL OR s.saledate >= p_from)
          AND  (p_to   IS NULL OR s.saledate <= p_to)
          AND  NOT EXISTS (SELECT 1 FROM poultrypayments pp
                           WHERE pp.saleid = s.saleid AND pp.farmid = s.farmid
                             AND COALESCE(pp.status, 'Posted') = 'Posted')

        UNION ALL

        SELECT pp.paymentdate::date, 'Payment'::text,
               COALESCE(NULLIF(btrim(pp.reference), ''), 'S' || pp.saleid::text)::text,
               ('Payment received' ||
                COALESCE(' (' || NULLIF(btrim(pp.paymentmethod), '') || ')', '') ||
                ' against sale S' || pp.saleid::text)::text,
               0::numeric(14,2), pp.amount::numeric(14,2), pp.saleid, 2, 1
        FROM   poultrypayments pp
        WHERE  pp.farmid = p_farmid AND pp.customerid = p_customerid
          AND  COALESCE(pp.status, 'Posted') = 'Posted'
          AND  (p_from IS NULL OR pp.paymentdate::date >= p_from)
          AND  (p_to   IS NULL OR pp.paymentdate::date <= p_to)
    )
    -- Chronological, with the opening pinned to the top and a same-day sale
    -- printed before the payment that settles it (sortkey 1 before 2).
    SELECT l.entrydate, l.entrytype, l.reference, l.description, l.debit, l.credit,
           SUM(l.debit - l.credit) OVER (
               ORDER BY l.pin, l.entrydate, l.sortkey, l.saleid NULLS FIRST
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::numeric(14,2),
           l.saleid, l.sortkey
    FROM   lines l
    WHERE  l.entrytype <> 'OpeningBalance' OR l.debit <> 0
    ORDER  BY l.pin, l.entrydate, l.sortkey, l.saleid NULLS FIRST;
$function$;

-- -----------------------------------------------------------------------------
-- 12. Payment history.
-- -----------------------------------------------------------------------------
-- Grouped by paymentgroupid, because that is the payment the user made. A single
-- sale payment is a group of one; a bulk payment is a group of several, and its
-- allocationcount is what tells the two apart on screen.
CREATE OR REPLACE FUNCTION public.sppoultrycustomerpayment_history(
    p_farmid text,
    p_customerid integer DEFAULT NULL::integer,
    p_saleid integer DEFAULT NULL::integer,
    p_from date DEFAULT NULL::date,
    p_to date DEFAULT NULL::date)
RETURNS TABLE(
    paymentgroupid  uuid,
    customerid      integer,
    customername    text,
    paymentdate     timestamp without time zone,
    totalamount     numeric,
    paymentmethod   text,
    reference       text,
    note            text,
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
    SELECT pp.paymentgroupid,
           MIN(pp.customerid),
           MIN(c.name)::text,
           MIN(pp.paymentdate),
           SUM(pp.amount)::numeric(14,2),
           MIN(pp.paymentmethod)::text,
           MIN(pp.reference)::text,
           MIN(pp.note)::text,
           MIN(pp.sourcetype)::text,
           MIN(COALESCE(pp.status, 'Posted'))::text,
           COUNT(*)::integer,
           MIN(pp.poultrycashaccountid),
           MIN(pp.createdby)::text,
           MIN(pp.reversedby)::text,
           MIN(pp.reversedat),
           MIN(pp.reversalreason)::text
    FROM   poultrypayments pp
    LEFT   JOIN customer c ON c.customerid = pp.customerid AND c.farmid = pp.farmid
    WHERE  pp.farmid = p_farmid
      AND  (p_customerid IS NULL OR pp.customerid = p_customerid)
      AND  (p_from IS NULL OR pp.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR pp.paymentdate::date <= p_to)
      AND  (p_saleid IS NULL OR EXISTS (
              SELECT 1 FROM poultrypayments p2
              WHERE p2.paymentgroupid = pp.paymentgroupid AND p2.saleid = p_saleid))
    GROUP  BY pp.paymentgroupid
    ORDER  BY MIN(pp.paymentdate) DESC;
$function$;

-- The allocation detail behind one payment.
CREATE OR REPLACE FUNCTION public.sppoultrycustomerpayment_allocations(
    p_farmid text, p_paymentgroupid uuid)
RETURNS TABLE(
    allocationid      integer,
    paymentid         integer,
    saleid            integer,
    saledate          date,
    product           text,
    saletotal         numeric,
    amountapplied     numeric,
    salebalancebefore numeric,
    salebalanceafter  numeric,
    status            text)
LANGUAGE sql
STABLE
AS $function$
    SELECT ca.allocationid, ca.paymentid, ca.saleid, s.saledate, s.product::text,
           s.totalamount, ca.amountapplied, ca.salebalancebefore, ca.salebalanceafter, ca.status
    FROM   customerpaymentallocation ca
    JOIN   poultrypayments pp ON pp.poultrypaymentid = ca.paymentid AND pp.farmid = ca.farmid
    LEFT   JOIN sale s ON s.saleid = ca.saleid AND s.farmid = ca.farmid
    WHERE  ca.farmid = p_farmid AND ca.module = 'poultry'
      AND  pp.paymentgroupid = p_paymentgroupid
    ORDER  BY s.saledate, ca.saleid;
$function$;

-- -----------------------------------------------------------------------------
-- 13. Repoint the existing report at the same aggregation.
-- -----------------------------------------------------------------------------
-- The report grouped by the customername STRING and hardcoded lastpaymentdate
-- and overdueamount to NULL (PoultryAdvancedReportService even pushes a warning
-- saying due dates are not tracked). Both are now real, and because the report
-- and the page read the same balance formula they cannot disagree.
--
-- Return type changes, so this must be dropped first. The service that reads it
-- is updated alongside.
DROP FUNCTION IF EXISTS public.sppoultryreport_customerbalance(text,date,text);

CREATE OR REPLACE FUNCTION public.sppoultryreport_customerbalance(
    p_farmid text, p_enddate date, p_customername text DEFAULT NULL::text)
RETURNS TABLE(
    customer        text,
    customerid      integer,
    contactphone    text,
    totalsales      numeric,
    totalpaid       numeric,
    balance         numeric,
    overdueamount   numeric,
    opensalecount   integer,
    lastsaledate    date,
    lastpaymentdate timestamp without time zone)
LANGUAGE sql
STABLE
AS $function$
    SELECT COALESCE(c.name, s.customername)::text,
           c.customerid,
           c.contactphone::text,
           SUM(s.totalamount)::numeric(14,2),
           SUM(fnpoultrysalereceived(s.paid, s.totalamount, s.amountpaid))::numeric(14,2),
           SUM(fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid))::numeric(14,2),
           SUM(CASE WHEN (s.saledate + COALESCE(c.paymenttermsdays, 0)) < CURRENT_DATE
                    THEN fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid)
                    ELSE 0 END)::numeric(14,2),
           COUNT(*) FILTER (
               WHERE fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid) > 0)::integer,
           MAX(s.saledate),
           MAX((SELECT MAX(pp.paymentdate) FROM poultrypayments pp
                WHERE pp.farmid = p_farmid AND pp.saleid = s.saleid
                  AND COALESCE(pp.status, 'Posted') = 'Posted'))
    FROM   sale s
    LEFT   JOIN customer c ON c.customerid = s.customerid AND c.farmid = s.farmid
    WHERE  s.farmid = p_farmid
      AND  s.saledate < (p_enddate + 1)
      AND  s.customername IS NOT NULL AND btrim(s.customername) <> ''
      AND  (p_customername IS NULL OR s.customername = p_customername)
    GROUP  BY COALESCE(c.name, s.customername), c.customerid, c.contactphone
    ORDER  BY SUM(fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid)) DESC;
$function$;

COMMIT;

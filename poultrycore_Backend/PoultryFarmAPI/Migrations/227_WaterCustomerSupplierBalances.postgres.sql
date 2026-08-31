-- =============================================================================
-- 227_WaterCustomerSupplierBalances.postgres.sql
--
-- Purpose
-- -------
-- Customer Balances and Supplier Balances for the WATER module -- the same
-- feature migrations 222/223/224 built for Poultry. 222 built the shared spine
-- (customerpaymentallocation / supplierpaymentallocation, both carrying a
-- `module` discriminator) and explicitly deferred Water and Generic until the
-- poultry side was proven. It is proven; this is Water.
--
-- Nothing here is poultry-specific and nothing here touches a poultry object.
-- The allocation tables already exist and already accept module = 'water'.
--
-- What Water looks like, and where it differs from Poultry
-- --------------------------------------------------------
-- RECEIVABLES are simpler. `sale` (poultry) carries a `paid` boolean and needs
-- fnpoultrysalebalance() to decide what is actually outstanding; `watersales`
-- carries totalamount + amountpaid and the balance is the subtraction, exactly
-- as spwatersale_getall already computes it (migration 225). So there is no
-- fnwatersalebalance() here -- it would be a function wrapping a minus sign.
--
-- PAYABLES are simpler too. Poultry pays two document tables (raw-material
-- purchases AND flock batches), which is why fnpoultrypayables() unions them
-- and why supplierpaymentallocation needs a documenttype. Water buys through
-- one table, waterrawmaterialpurchases. fnwaterpayables() is still written as
-- the single place downstream reads from, so a second payable table later is
-- one edit, and documenttype is still written ('RawMaterialPurchase') so the
-- shared allocation table and the shared frontend keep one shape.
--
-- CASH. This is the one place the two modules genuinely disagree, and it is
-- deliberate:
--
--   * Customer payments post NO cash. No water sale-payment path has ever
--     posted cash -- spWaterPayment_Record (026) writes the payment and
--     recomputes the sale, nothing more. Water cash arrives through driver
--     return reconciliation and daily closing. A balances payment that posted
--     CashIn would double-count against those. The cash account is still
--     stored on the payment row for the audit trail, and the water customer
--     balances page offers no account picker, so nothing on screen claims to
--     move cash that doesn't.
--
--   * Supplier payments DO post cash, because water already does: migration 091
--     had spWaterRawMaterialPurchase_PayBalance write a WaterExpenses row and a
--     WaterCashTransactions CashOut. Section 5 keeps exactly that behaviour and
--     routes it through the allocation system, so a payment taken on the
--     Purchases page and one taken on the Supplier Balances page produce the
--     same rows.
--
-- Idempotent throughout, transactional. Safe to re-run.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Schema.
-- -----------------------------------------------------------------------------
-- waterpayments predates any notion of reversal, of a payment belonging to a
-- CUSTOMER rather than to a single sale, or of one payment spanning several
-- sales. All three are what the balances page is. Mirrors what 222 did to
-- poultrypayments.
ALTER TABLE waterpayments ADD COLUMN IF NOT EXISTS paymentgroupid      uuid      NULL;
-- Posted | Reversed
ALTER TABLE waterpayments ADD COLUMN IF NOT EXISTS status              text      NOT NULL DEFAULT 'Posted';
-- SaleEntry (recorded on the sale itself) | CustomerBalances (this page)
ALTER TABLE waterpayments ADD COLUMN IF NOT EXISTS sourcetype          text      NOT NULL DEFAULT 'SaleEntry';
ALTER TABLE waterpayments ADD COLUMN IF NOT EXISTS watercustomerid     integer   NULL;
ALTER TABLE waterpayments ADD COLUMN IF NOT EXISTS watercashaccountid  integer   NULL;
ALTER TABLE waterpayments ADD COLUMN IF NOT EXISTS reversedby          text      NULL;
ALTER TABLE waterpayments ADD COLUMN IF NOT EXISTS reversedat          timestamp NULL;
ALTER TABLE waterpayments ADD COLUMN IF NOT EXISTS reversalreason      text      NULL;

CREATE INDEX IF NOT EXISTS ix_waterpayments_farm_customer
    ON waterpayments (farmid, watercustomerid) WHERE status = 'Posted';
CREATE INDEX IF NOT EXISTS ix_waterpayments_group
    ON waterpayments (farmid, paymentgroupid);

-- Terms live on the PARTY and the due date is derived (documentdate + terms) --
-- the reasoning is in 222. 0 = due on the day, correct for a cash business.
ALTER TABLE watercustomers ADD COLUMN IF NOT EXISTS paymenttermsdays integer NOT NULL DEFAULT 0;
ALTER TABLE watersuppliers ADD COLUMN IF NOT EXISTS paymenttermsdays integer NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS ix_waterrawmatpurchase_farm_supplier
    ON waterrawmaterialpurchases (farmid, supplierid);

-- Supplier payment header. Unlike the customer side there is no existing
-- per-document payment table to extend, so this is a proper header whose
-- allocations live in supplierpaymentallocation. One row = one payment made.
CREATE TABLE IF NOT EXISTS watersupplierpayments (
    watersupplierpaymentid serial        PRIMARY KEY,
    farmid                 text          NOT NULL,
    -- NULLABLE on purpose, same reasoning as poultrysupplierpayments: a water
    -- raw-material purchase may carry only a freetext suppliername and no
    -- supplierid, and such a purchase must stay payable from the Purchases
    -- page. The payment is real; it simply has no supplier to roll up into, so
    -- the balances page filters it out rather than inventing a party.
    supplierid             integer       NULL,
    paymentdate            timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    totalamount            numeric(14,2) NOT NULL CHECK (totalamount > 0),
    paymentmethod          text          NULL,
    watercashaccountid     integer       NULL,
    referenceno            text          NULL,
    notes                  text          NULL,
    -- PurchaseEntry (recorded on the purchase itself) | SupplierBalances
    sourcetype             text          NOT NULL DEFAULT 'SupplierBalances',
    -- Posted | Reversed
    status                 text          NOT NULL DEFAULT 'Posted',
    createdby              text          NULL,
    createdat              timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby             text          NULL,
    reversedat             timestamp     NULL,
    reversalreason         text          NULL
);

CREATE INDEX IF NOT EXISTS ix_watersupplierpayments_farm_supplier
    ON watersupplierpayments (farmid, supplierid) WHERE status = 'Posted';
CREATE INDEX IF NOT EXISTS ix_watersupplierpayments_farm_date
    ON watersupplierpayments (farmid, paymentdate);

-- -----------------------------------------------------------------------------
-- 2. Backfill.
-- -----------------------------------------------------------------------------
-- Every existing water payment belongs to a customer, via its sale. Without
-- this the balances page would show correct totals (it reads amountpaid) but an
-- empty payment history for every customer.
UPDATE waterpayments p
SET    watercustomerid = s.watercustomerid
FROM   watersales s
WHERE  s.watersaleid = p.watersaleid
  AND  s.farmid = p.farmid
  AND  p.watercustomerid IS NULL;

-- One payment -> one sale historically, so each existing row becomes exactly
-- one allocation and its own payment group. The before/after pair is
-- reconstructed as a running total in payment order.
--
-- ON CONFLICT DO NOTHING against the unique (module, paymentid, saleid) index
-- is what makes this re-runnable.
WITH ordered AS (
    SELECT p.waterpaymentid,
           p.farmid,
           p.watersaleid,
           p.amount,
           p.paymentdate,
           p.createdby,
           s.totalamount,
           SUM(p.amount) OVER (PARTITION BY p.watersaleid
                               ORDER BY p.paymentdate, p.waterpaymentid
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS paidthrough
    FROM   waterpayments p
    JOIN   watersales s ON s.watersaleid = p.watersaleid AND s.farmid = p.farmid
    WHERE  COALESCE(p.status, 'Posted') = 'Posted'
)
INSERT INTO customerpaymentallocation
    (farmid, module, paymentid, saleid, amountapplied,
     salebalancebefore, salebalanceafter, status, createdby, createdat)
SELECT o.farmid, 'water', o.waterpaymentid, o.watersaleid, o.amount::numeric(14,2),
       GREATEST(o.totalamount - (o.paidthrough - o.amount), 0)::numeric(14,2),
       GREATEST(o.totalamount - o.paidthrough, 0)::numeric(14,2),
       'Posted', o.createdby, o.paymentdate
FROM   ordered o
ON CONFLICT (module, paymentid, saleid) DO NOTHING;

-- A pre-existing payment is its own group, so payment history has something to
-- key on. Done after the allocation insert so a half-run migration cannot leave
-- a grouped payment with no allocation.
UPDATE waterpayments
SET    paymentgroupid = gen_random_uuid()
WHERE  paymentgroupid IS NULL;

-- -----------------------------------------------------------------------------
-- 3. Recompute one water sale from its posted payments.
-- -----------------------------------------------------------------------------
-- The single definition of "what does this sale still owe". Lifted verbatim
-- from spWaterPayment_Record (026) so a payment taken on the Sales page and one
-- taken on the Balances page leave the sale in the same state -- including the
-- Cancelled guard, which must never be overwritten by a status recompute.
--
-- The COALESCE(status,'Posted') filter is what makes a reversal actually give
-- the money back: a reversed payment stops counting towards amountpaid.
CREATE OR REPLACE FUNCTION public.spwatersale_recompute(
    p_farmid text, p_watersaleid integer)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_total numeric(14,2);
    v_sum   numeric(14,2);
    v_status text;
BEGIN
    SELECT s.totalamount, s.status INTO v_total, v_status
    FROM   watersales s
    WHERE  s.watersaleid = p_watersaleid AND s.farmid = p_farmid
    LIMIT  1;

    IF v_total IS NULL THEN RETURN; END IF;

    v_sum := COALESCE((SELECT SUM(p.amount) FROM waterpayments p
                       WHERE p.watersaleid = p_watersaleid AND p.farmid = p_farmid
                         AND COALESCE(p.status, 'Posted') = 'Posted'), 0);

    UPDATE watersales s
    SET    amountpaid  = v_sum,
           status      = CASE
                             WHEN v_status = 'Cancelled'    THEN 'Cancelled'
                             WHEN v_sum >= s.totalamount    THEN 'Paid'
                             WHEN v_sum > 0                 THEN 'PartiallyPaid'
                             ELSE 'Pending'
                         END,
           updateddate = (now() at time zone 'utc')
    WHERE  s.watersaleid = p_watersaleid AND s.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. CUSTOMER SIDE.
-- -----------------------------------------------------------------------------

-- 4a. Record a customer payment across one or more sales.
--
-- p_allocations is a JSON array of {"saleid": <int>, "amount": <numeric>}.
-- Keys are LOWER CASE and the recordset identifiers are unquoted so they fold
-- to lower case and match -- jsonb_to_recordset matches keys case-sensitively,
-- and a camelCase key against an unquoted identifier silently yields NULL rows
-- (migration 214 lost every line of a water usage entry to exactly this).
--
-- Overpayment is blocked: allocations must add up to the payment to the pesewa.
-- There is no customer credit balance in this build, so money that cannot be
-- applied has nowhere to live.
--
-- Returns the paymentgroupid -- the id of the payment as the user understands
-- it. The per-sale waterpayments rows sharing that group are its allocations.
CREATE OR REPLACE FUNCTION public.spwatercustomerpayment_record(
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
    v_group     uuid := gen_random_uuid();
    v_date      timestamp := COALESCE(p_paymentdate, (now() at time zone 'utc'));
    v_allocated numeric(14,2);
    v_count     integer;
    v_distinct  integer;
    v_minamount numeric(14,2);
    v_missing   integer;
    v_row       record;
    v_before    numeric(14,2);
    v_paymentid integer;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than 0.';
    END IF;
    IF p_customerid IS NULL THEN
        RAISE EXCEPTION 'A customer is required to receive a payment.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM watercustomers c
                   WHERE c.watercustomerid = p_customerid AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Customer does not belong to this company.';
    END IF;
    IF p_cashaccountid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM watercashaccounts a
                       WHERE a.watercashaccountid = p_cashaccountid AND a.farmid = p_farmid) THEN
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

    -- Every id must resolve, or the loop below would quietly process fewer
    -- sales than were validated and the payment would post short.
    SELECT COUNT(*) INTO v_missing
    FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
           AS a(saleid integer, amount numeric)
    WHERE  a.saleid IS NOT NULL AND COALESCE(a.amount, 0) <> 0
      AND  NOT EXISTS (SELECT 1 FROM watersales s
                       WHERE s.watersaleid = a.saleid AND s.farmid = p_farmid);
    IF v_missing > 0 THEN
        RAISE EXCEPTION '% of the selected sales do not belong to this company.', v_missing;
    END IF;

    -- Oldest first, so the before/after pair on each allocation reads the way
    -- the statement will.
    FOR v_row IN
        SELECT a.saleid, a.amount::numeric(14,2) AS amount,
               s.totalamount, s.amountpaid, s.saledate, s.watercustomerid, s.status
        FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
               AS a(saleid integer, amount numeric)
        JOIN   watersales s ON s.watersaleid = a.saleid AND s.farmid = p_farmid
        WHERE  a.saleid IS NOT NULL AND COALESCE(a.amount, 0) <> 0
        ORDER  BY s.saledate, s.watersaleid
    LOOP
        IF v_row.watercustomerid IS DISTINCT FROM p_customerid THEN
            RAISE EXCEPTION 'Sale #% does not belong to this customer.', v_row.saleid;
        END IF;
        IF v_row.status = 'Cancelled' THEN
            RAISE EXCEPTION 'Sale #% is cancelled and cannot take a payment.', v_row.saleid;
        END IF;

        v_before := GREATEST(v_row.totalamount - v_row.amountpaid, 0)::numeric(14,2);

        IF v_before <= 0 THEN
            RAISE EXCEPTION 'Sale #% is already fully paid.', v_row.saleid;
        END IF;
        IF v_row.amount > v_before THEN
            RAISE EXCEPTION 'Cannot apply % to sale #% -- its balance is only %.',
                  v_row.amount, v_row.saleid, v_before;
        END IF;

        INSERT INTO waterpayments
            (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note,
             createdby, createddate, status, sourcetype, watercustomerid,
             watercashaccountid, paymentgroupid)
        VALUES
            (p_farmid, v_row.saleid, v_row.amount, p_paymentmethod, v_date, p_reference, p_note,
             p_createdby, (now() at time zone 'utc'), 'Posted',
             COALESCE(p_sourcetype, 'CustomerBalances'), p_customerid,
             p_cashaccountid, v_group)
        RETURNING waterpaymentid INTO v_paymentid;

        INSERT INTO customerpaymentallocation
            (farmid, module, paymentid, saleid, amountapplied,
             salebalancebefore, salebalanceafter, status, createdby, createdat)
        VALUES
            (p_farmid, 'water', v_paymentid, v_row.saleid, v_row.amount,
             v_before, v_before - v_row.amount, 'Posted', p_createdby, v_date);

        PERFORM spwatersale_recompute(p_farmid, v_row.saleid);
    END LOOP;

    RETURN v_group;
END;
$function$;

-- 4b. Reverse a customer payment. Append-only: the payment and its allocations
-- are marked Reversed and the sales recompute, so the money goes back onto the
-- balance without losing the record that it was ever taken.
CREATE OR REPLACE FUNCTION public.spwatercustomerpayment_reverse(
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
    IF NOT EXISTS (SELECT 1 FROM waterpayments p
                   WHERE p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Payment not found for this company.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM waterpayments p
                   WHERE p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid
                     AND COALESCE(p.status, 'Posted') = 'Posted') THEN
        RAISE EXCEPTION 'This payment has already been reversed.';
    END IF;

    UPDATE customerpaymentallocation ca
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason
    FROM   waterpayments p
    WHERE  p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid
      AND  ca.module = 'water' AND ca.paymentid = p.waterpaymentid
      AND  ca.status = 'Posted';

    UPDATE waterpayments p
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = p_reason
    WHERE  p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid
      AND  COALESCE(p.status, 'Posted') = 'Posted';
    GET DIAGNOSTICS v_count = ROW_COUNT;

    FOR v_sale IN
        SELECT DISTINCT p.watersaleid FROM waterpayments p
        WHERE  p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid
    LOOP
        PERFORM spwatersale_recompute(p_farmid, v_sale);
    END LOOP;

    RETURN v_count;
END;
$function$;

-- 4c. The balances page itself.
--
-- p_status filters which SALES count, then the customer totals are built from
-- whatever survives -- so "Overdue" gives an overdue-only balance per customer
-- rather than a full balance on an overdue customer.
--
-- Cancelled sales are excluded everywhere: a cancelled sale is not a debt.
DROP FUNCTION IF EXISTS public.spwatercustomerbalances(text, date, date, integer, text, numeric, text);

CREATE OR REPLACE FUNCTION public.spwatercustomerbalances(
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
        SELECT s.watercustomerid                                   AS customerid,
               s.watersaleid                                       AS saleid,
               s.saledate::date                                    AS saledate,
               s.totalamount,
               GREATEST(s.totalamount - s.amountpaid, 0)::numeric(14,2) AS balance,
               s.amountpaid                                        AS received,
               COALESCE(c.paymenttermsdays, 0)                      AS terms
        FROM   watersales s
        JOIN   watercustomers c ON c.watercustomerid = s.watercustomerid
                               AND c.farmid = s.farmid
        WHERE  s.farmid = p_farmid
          AND  s.watercustomerid IS NOT NULL
          AND  COALESCE(s.status, '') <> 'Cancelled'
          AND  (p_customerid IS NULL OR s.watercustomerid = p_customerid)
          AND  (p_from IS NULL OR s.saledate::date >= p_from)
          AND  (p_to   IS NULL OR s.saledate::date <= p_to)
          AND  (s.totalamount - s.amountpaid) > 0
    ),
    filtered AS (
        SELECT o.*,
               (o.saledate + o.terms)                  AS duedate,
               ((o.saledate + o.terms) < CURRENT_DATE) AS isoverdue
        FROM   opensales o
        WHERE  CASE COALESCE(p_status, 'All')
                    WHEN 'Partial' THEN o.received > 0
                    WHEN 'Unpaid'  THEN o.received = 0
                    WHEN 'Overdue' THEN (o.saledate + o.terms) < CURRENT_DATE
                    ELSE TRUE
               END
    )
    SELECT c.watercustomerid,
           c.name::text,
           c.contactphone::text,
           c.contactemail::text,
           COALESCE(c.paymenttermsdays, 0),
           SUM(f.balance)::numeric(14,2),
           COUNT(*)::integer,
           MIN(f.saledate),
           MAX(f.saledate),
           (SELECT MAX(p.paymentdate) FROM waterpayments p
            WHERE p.farmid = p_farmid AND p.watercustomerid = c.watercustomerid
              AND COALESCE(p.status, 'Posted') = 'Posted'),
           SUM(CASE WHEN f.isoverdue THEN f.balance ELSE 0 END)::numeric(14,2),
           SUM(f.totalamount)::numeric(14,2),
           SUM(f.received)::numeric(14,2)
    FROM   filtered f
    JOIN   watercustomers c ON c.watercustomerid = f.customerid AND c.farmid = p_farmid
    WHERE  (p_search IS NULL OR btrim(p_search) = ''
            OR c.name ILIKE '%' || btrim(p_search) || '%'
            OR COALESCE(c.contactphone, '') ILIKE '%' || btrim(p_search) || '%')
    GROUP  BY c.watercustomerid, c.name, c.contactphone, c.contactemail, c.paymenttermsdays
    HAVING (p_minbalance IS NULL OR SUM(f.balance) >= p_minbalance)
    ORDER  BY SUM(f.balance) DESC;
$function$;

-- 4d. The sales behind one customer's balance -- the expandable row, and what
-- the allocation grid is built from.
DROP FUNCTION IF EXISTS public.spwatercustomeropensales(text, integer, date, date, text);

CREATE OR REPLACE FUNCTION public.spwatercustomeropensales(
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
    watercashaccountid integer)
LANGUAGE sql
STABLE
AS $function$
    SELECT s.watersaleid,
           s.saledate::date,
           -- A water sale is a header with line items; name it by the first
           -- product so the row is recognisable, and say how many more there
           -- are rather than listing them in a cell.
           COALESCE(it.productname, 'Water sale')::text,
           CASE WHEN COALESCE(it.itemcount, 0) > 1
                THEN (it.productname || ' +' || (it.itemcount - 1)::text || ' more')
                ELSE COALESCE(s.notes, '') END::text,
           s.totalamount,
           s.amountpaid,
           GREATEST(s.totalamount - s.amountpaid, 0)::numeric(14,2),
           (s.saledate::date + COALESCE(c.paymenttermsdays, 0))::date,
           GREATEST((CURRENT_DATE - s.saledate::date), 0)::integer,
           CASE WHEN s.amountpaid > 0 THEN 'Partially Paid' ELSE 'Unpaid' END::text,
           ((s.saledate::date + COALESCE(c.paymenttermsdays, 0)) < CURRENT_DATE),
           NULL::integer
    FROM   watersales s
    JOIN   watercustomers c ON c.watercustomerid = s.watercustomerid AND c.farmid = s.farmid
    LEFT   JOIN LATERAL (
               -- waterproducts names its column `name`, not `productname` --
               -- the ProductName on WaterSaleItemModel is a projection the
               -- read SPs build from this join, not a column on watersaleitems.
               SELECT MIN(pr.name)::text AS productname, COUNT(*)::integer AS itemcount
               FROM   watersaleitems i
               LEFT   JOIN waterproducts pr ON pr.waterproductid = i.waterproductid
               WHERE  i.watersaleid = s.watersaleid
           ) it ON TRUE
    WHERE  s.farmid = p_farmid
      AND  s.watercustomerid = p_customerid
      AND  COALESCE(s.status, '') <> 'Cancelled'
      AND  (p_from IS NULL OR s.saledate::date >= p_from)
      AND  (p_to   IS NULL OR s.saledate::date <= p_to)
      AND  (s.totalamount - s.amountpaid) > 0
      AND  CASE COALESCE(p_status, 'All')
                WHEN 'Partial' THEN s.amountpaid > 0
                WHEN 'Unpaid'  THEN s.amountpaid = 0
                WHEN 'Overdue' THEN (s.saledate::date + COALESCE(c.paymenttermsdays, 0)) < CURRENT_DATE
                ELSE TRUE
           END
    ORDER  BY s.saledate, s.watersaleid;
$function$;

-- 4e. Headline figures for the summary cards. One round trip rather than five.
DROP FUNCTION IF EXISTS public.spwatercustomerbalancesummary(text);

CREATE OR REPLACE FUNCTION public.spwatercustomerbalancesummary(p_farmid text)
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
    WITH per AS (
        SELECT b.customerid, b.customername, b.totalbalance, b.overdueamount
        FROM   spwatercustomerbalances(p_farmid) b
    )
    SELECT COALESCE(SUM(p.totalbalance), 0)::numeric(14,2),
           COUNT(*)::integer,
           COALESCE(SUM(p.overdueamount), 0)::numeric(14,2),
           COALESCE((SELECT SUM(w.amount) FROM waterpayments w
                     WHERE w.farmid = p_farmid
                       AND COALESCE(w.status, 'Posted') = 'Posted'
                       AND w.paymentdate::date = CURRENT_DATE), 0)::numeric(14,2),
           COALESCE(MAX(p.totalbalance), 0)::numeric(14,2),
           (SELECT p2.customername FROM per p2 ORDER BY p2.totalbalance DESC LIMIT 1)
    FROM   per p;
$function$;

-- 4f. Customer statement -- every sale and payment in the window, with a
-- running balance. `pin` keeps the opening line first and the closing line last
-- regardless of date ties.
DROP FUNCTION IF EXISTS public.spwatercustomerstatement(text, integer, date, date);

CREATE OR REPLACE FUNCTION public.spwatercustomerstatement(
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
        -- Opening balance: what was owed before the window opened. p_from NULL
        -- means "the whole history", and a whole-history statement has nothing
        -- before it -- so the opening MUST be zero. The usual
        -- `p_from IS NULL OR ...` idiom here would instead match every sale ever
        -- and count the entire ledger twice.
        SELECT CASE WHEN p_from IS NULL THEN NULL::date ELSE p_from END AS entrydate,
               'OpeningBalance'::text  AS entrytype,
               NULL::text              AS reference,
               'Opening balance'::text AS description,
               CASE WHEN p_from IS NULL THEN 0::numeric(14,2) ELSE COALESCE((
                   SELECT SUM(GREATEST(s.totalamount - s.amountpaid, 0))
                   FROM   watersales s
                   WHERE  s.farmid = p_farmid AND s.watercustomerid = p_customerid
                     AND  COALESCE(s.status, '') <> 'Cancelled'
                     AND  s.saledate::date < p_from), 0)::numeric(14,2) END AS debit,
               0::numeric(14,2) AS credit,
               NULL::integer    AS saleid,
               0                AS sortkey,
               0                AS pin

        UNION ALL

        SELECT s.saledate::date, 'Sale'::text,
               ('W' || s.watersaleid::text)::text,
               COALESCE(NULLIF(btrim(s.notes), ''), 'Water sale')::text,
               s.totalamount::numeric(14,2), 0::numeric(14,2),
               s.watersaleid, 1, 1
        FROM   watersales s
        WHERE  s.farmid = p_farmid AND s.watercustomerid = p_customerid
          AND  COALESCE(s.status, '') <> 'Cancelled'
          AND  (p_from IS NULL OR s.saledate::date >= p_from)
          AND  (p_to   IS NULL OR s.saledate::date <= p_to)

        UNION ALL

        SELECT p.paymentdate::date, 'Payment'::text,
               COALESCE(NULLIF(btrim(p.reference), ''), 'PMT' || p.waterpaymentid::text)::text,
               ('Payment' || COALESCE(' — ' || NULLIF(btrim(p.paymentmethod), ''), '')
                          || ' (sale W' || p.watersaleid::text || ')')::text,
               0::numeric(14,2), p.amount::numeric(14,2),
               p.watersaleid, 2, 1
        FROM   waterpayments p
        WHERE  p.farmid = p_farmid AND p.watercustomerid = p_customerid
          AND  COALESCE(p.status, 'Posted') = 'Posted'
          AND  (p_from IS NULL OR p.paymentdate::date >= p_from)
          AND  (p_to   IS NULL OR p.paymentdate::date <= p_to)
    ),
    ordered AS (
        SELECT l.*,
               ROW_NUMBER() OVER (ORDER BY l.pin, l.entrydate NULLS FIRST, l.sortkey, l.saleid) AS rn
        FROM   lines l
    )
    SELECT o.entrydate, o.entrytype, o.reference, o.description,
           o.debit, o.credit,
           SUM(o.debit - o.credit) OVER (ORDER BY o.rn
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::numeric(14,2),
           o.saleid, o.sortkey
    FROM   ordered o
    ORDER  BY o.rn;
$function$;

-- 4g. Payment history, grouped the way the user made the payment.
DROP FUNCTION IF EXISTS public.spwatercustomerpayment_history(text, integer, integer, date, date);

CREATE OR REPLACE FUNCTION public.spwatercustomerpayment_history(
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
    watercashaccountid integer,
    createdby       text,
    reversedby      text,
    reversedat      timestamp without time zone,
    reversalreason  text)
LANGUAGE sql
STABLE
AS $function$
    SELECT p.paymentgroupid,
           MIN(p.watercustomerid),
           MIN(c.name)::text,
           MIN(p.paymentdate),
           SUM(p.amount)::numeric(14,2),
           MIN(p.paymentmethod)::text,
           MIN(p.reference)::text,
           MIN(p.note)::text,
           MIN(p.sourcetype)::text,
           MIN(COALESCE(p.status, 'Posted'))::text,
           COUNT(*)::integer,
           MIN(p.watercashaccountid),
           MIN(p.createdby)::text,
           MIN(p.reversedby)::text,
           MIN(p.reversedat),
           MIN(p.reversalreason)::text
    FROM   waterpayments p
    LEFT   JOIN watercustomers c ON c.watercustomerid = p.watercustomerid AND c.farmid = p.farmid
    WHERE  p.farmid = p_farmid
      AND  (p_customerid IS NULL OR p.watercustomerid = p_customerid)
      AND  (p_from IS NULL OR p.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR p.paymentdate::date <= p_to)
      AND  (p_saleid IS NULL OR EXISTS (
              SELECT 1 FROM waterpayments p2
              WHERE p2.paymentgroupid = p.paymentgroupid AND p2.watersaleid = p_saleid))
    GROUP  BY p.paymentgroupid
    ORDER  BY MIN(p.paymentdate) DESC;
$function$;

-- 4h. The allocation detail behind one payment.
DROP FUNCTION IF EXISTS public.spwatercustomerpayment_allocations(text, uuid);

CREATE OR REPLACE FUNCTION public.spwatercustomerpayment_allocations(
    p_farmid text, p_paymentgroupid uuid)
RETURNS TABLE(
    allocationid   integer,
    documenttype   text,
    documentid     integer,
    reference      text,
    documentdate   date,
    label          text,
    documenttotal  numeric,
    amountapplied  numeric,
    balancebefore  numeric,
    balanceafter   numeric,
    status         text)
LANGUAGE sql
STABLE
AS $function$
    SELECT ca.allocationid,
           'WaterSale'::text,
           ca.saleid,
           ('W' || ca.saleid::text)::text,
           s.saledate::date,
           COALESCE(NULLIF(btrim(s.notes), ''), 'Water sale')::text,
           s.totalamount,
           ca.amountapplied,
           ca.salebalancebefore,
           ca.salebalanceafter,
           ca.status::text
    FROM   customerpaymentallocation ca
    JOIN   waterpayments p ON p.waterpaymentid = ca.paymentid AND p.farmid = ca.farmid
    LEFT   JOIN watersales s ON s.watersaleid = ca.saleid AND s.farmid = ca.farmid
    WHERE  ca.farmid = p_farmid
      AND  ca.module = 'water'
      AND  p.paymentgroupid = p_paymentgroupid
    ORDER  BY s.saledate, ca.saleid;
$function$;

-- -----------------------------------------------------------------------------
-- 5. SUPPLIER SIDE.
-- -----------------------------------------------------------------------------

-- 5a. Every water payable in one shape. Downstream (the rollup, the open-
-- documents list, the statement) reads only this, so a second payable table
-- later is a change in exactly one place.
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
    cashaccountid integer)
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
           NULL::integer
    FROM   waterrawmaterialpurchases pu
    LEFT   JOIN waterrawmaterialitems i
           ON i.waterrawmaterialitemid = pu.waterrawmaterialitemid
    WHERE  pu.farmid = p_farmid;
$function$;

-- 5b. The cash and expense side of a supplier payment.
--
-- Lifted from spWaterRawMaterialPurchase_PayBalance (091) so both entry points
-- produce identical rows: an approved WaterExpenses row under the
-- "Raw Materials / Inventory Purchase" category, a WaterCashTransactions
-- CashOut, and the account balance moved. Called once per PAYMENT, not per
-- allocation, so one payment across three purchases is one expense and one cash
-- movement -- not three.
CREATE OR REPLACE FUNCTION public.spwatersupplierpaymentcash_sync(
    p_farmid text, p_paymentid integer)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_pay     record;
    v_catid   integer;
    v_acct    integer;
    v_docs    text;
    v_expense integer;
    v_party   text;
BEGIN
    SELECT sp.watersupplierpaymentid, sp.supplierid, sp.paymentdate, sp.totalamount,
           sp.paymentmethod, sp.watercashaccountid, sp.createdby, sp.notes
    INTO   v_pay
    FROM   watersupplierpayments sp
    WHERE  sp.watersupplierpaymentid = p_paymentid AND sp.farmid = p_farmid
      AND  COALESCE(sp.status, 'Posted') = 'Posted';

    IF v_pay.watersupplierpaymentid IS NULL THEN RETURN; END IF;

    -- Ensure the category exists, inline rather than through
    -- spwaterexpensecategory_ensurerawmaterialpurchase (068). Same category
    -- name, so an expense booked here lands where every other raw-material
    -- purchase expense already does -- but with no dependency on that
    -- function's Postgres parameter naming.
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

    SELECT string_agg('#' || sa.documentid::text, ', ' ORDER BY sa.documentid)
    INTO   v_docs
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'water'
      AND  sa.paymentid = p_paymentid AND sa.status = 'Posted';

    SELECT s.suppliername INTO v_party
    FROM   watersuppliers s
    WHERE  s.watersupplierid = v_pay.supplierid AND s.farmid = p_farmid;

    INSERT INTO waterexpenses
        (farmid, expensedate, waterexpensecategoryid, description, amount, paidto,
         paymentmethod, watercashaccountid, linkedwaterproductionbatchid,
         status, notes, createdby, approvedby, approvedat,
         supplierid, sourcetype, sourceid)
    VALUES
        (p_farmid, v_pay.paymentdate, v_catid,
         'Supplier payment for raw material purchase ' || COALESCE(v_docs, ''),
         v_pay.totalamount, v_party,
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
             'Expense', v_expense, -v_pay.totalamount,
             'Supplier payment — raw material purchase ' || COALESCE(v_docs, ''),
             v_pay.createdby, v_pay.createdby, (now() at time zone 'utc'));

        UPDATE watercashaccounts
        SET    currentbalance = currentbalance - v_pay.totalamount,
               updatedat = (now() at time zone 'utc')
        WHERE  watercashaccountid = v_acct AND farmid = p_farmid;
    END IF;
END;
$function$;

-- 5c. Reverse the cash and expense of a supplier payment.
CREATE OR REPLACE FUNCTION public.spwatersupplierpaymentcash_unsync(
    p_farmid text, p_paymentid integer, p_reversedby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_expense integer;
    v_amount  numeric(14,2);
    v_acct    integer;
BEGIN
    SELECT e.waterexpenseid, e.amount, e.watercashaccountid
    INTO   v_expense, v_amount, v_acct
    FROM   waterexpenses e
    WHERE  e.farmid = p_farmid AND e.sourcetype = 'WaterSupplierPayment'
      AND  e.sourceid = p_paymentid AND COALESCE(e.status, '') <> 'Cancelled'
    LIMIT  1;

    IF v_expense IS NULL THEN RETURN; END IF;

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
END;
$function$;

-- 5d. Record a supplier payment across one or more purchases.
--
-- p_allocations is a JSON array of
-- {"documenttype": <text>, "documentid": <int>, "amount": <numeric>}.
-- documenttype is accepted and validated even though water has one payable
-- table today, so the shared allocation table and the shared frontend keep one
-- shape and a second table later needs no signature change.
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

    SELECT COUNT(*) INTO v_missing
    FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb))
           AS a(documenttype text, documentid integer, amount numeric)
    WHERE  a.documentid IS NOT NULL AND COALESCE(a.amount, 0) <> 0
      AND  NOT EXISTS (SELECT 1 FROM fnwaterpayables(p_farmid) d
                       WHERE d.documenttype = COALESCE(a.documenttype, 'RawMaterialPurchase')
                         AND d.documentid = a.documentid);
    IF v_missing > 0 THEN
        RAISE EXCEPTION '% of the selected purchases do not belong to this company.', v_missing;
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
            RAISE EXCEPTION 'Purchase #% does not belong to this supplier.', v_row.documentid;
        END IF;
        IF v_row.balance <= 0 THEN
            RAISE EXCEPTION 'Purchase #% is already fully paid.', v_row.documentid;
        END IF;
        IF v_row.amount > v_row.balance THEN
            RAISE EXCEPTION 'Cannot apply % to purchase #% -- its balance is only %.',
                  v_row.amount, v_row.documentid, v_row.balance;
        END IF;

        INSERT INTO supplierpaymentallocation
            (farmid, module, paymentid, documenttype, documentid, amountapplied,
             documentbalancebefore, documentbalanceafter, status, createdby, createdat)
        VALUES
            (p_farmid, 'water', v_paymentid, v_row.documenttype, v_row.documentid,
             v_row.amount, v_row.balance, v_row.balance - v_row.amount,
             'Posted', p_createdby, v_date);

        UPDATE waterrawmaterialpurchases
        SET    amountpaid = amountpaid + v_row.amount,
               updatedat  = (now() at time zone 'utc')
        WHERE  waterrawmaterialpurchaseid = v_row.documentid AND farmid = p_farmid;
    END LOOP;

    -- One expense and one cash movement for the whole payment.
    PERFORM spwatersupplierpaymentcash_sync(p_farmid, v_paymentid);

    RETURN v_paymentid;
END;
$function$;

-- 5e. Reverse a supplier payment: put the balance back on every purchase it
-- touched, cancel its expense and give the cash back.
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
        UPDATE waterrawmaterialpurchases
        SET    amountpaid = GREATEST(amountpaid - v_row.amountapplied, 0),
               updatedat  = v_now
        WHERE  waterrawmaterialpurchaseid = v_row.documentid AND farmid = p_farmid;
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

-- 5f. The existing per-purchase pay-balance endpoint, routed through the
-- allocation system. Signature and return shape are UNCHANGED (091), so
-- WaterPhase3Services and the Raw Materials page keep working -- but a payment
-- taken there is now indistinguishable from one taken on Supplier Balances,
-- which is what stops the two screens disagreeing.
-- DROP first: the live function returns a different type, and CREATE OR REPLACE
-- refuses to change a return type. The signature below is the one PostgreSQL
-- itself names in its hint. Safe to drop -- WaterPhase3Services.PayBalanceAsync
-- is the only caller and reads the result with ExecuteScalar, which takes the
-- first column of the first row either way.
DROP FUNCTION IF EXISTS public.spwaterrawmaterialpurchase_paybalance(
    integer, text, numeric, text, timestamp without time zone, text);

CREATE OR REPLACE FUNCTION public.spwaterrawmaterialpurchase_paybalance(
    p_waterrawmaterialpurchaseid integer,
    p_farmid text,
    p_amount numeric,
    p_paymentmethod text DEFAULT NULL::text,
    p_paymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone,
    p_createdby text DEFAULT NULL::text)
RETURNS TABLE(balance numeric)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_doc    record;
    v_amount numeric(14,2);
BEGIN
    SELECT d.documentid, d.supplierid, d.balance, d.cashaccountid
    INTO   v_doc
    FROM   fnwaterpayables(p_farmid) d
    WHERE  d.documenttype = 'RawMaterialPurchase'
      AND  d.documentid = p_waterrawmaterialpurchaseid;

    IF v_doc.documentid IS NULL THEN
        RAISE EXCEPTION 'Purchase not found for this company.';
    END IF;
    IF v_doc.balance <= 0 THEN
        RAISE EXCEPTION 'This purchase has no outstanding balance.';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than 0.';
    END IF;

    -- Never overpay -- 091 clamped rather than erroring, and the Purchases page
    -- relies on that when the user types the full total on a part-paid row.
    v_amount := LEAST(p_amount, v_doc.balance)::numeric(14,2);

    PERFORM spwatersupplierpayment_record(
        p_farmid        => p_farmid,
        p_supplierid    => v_doc.supplierid,
        p_amount        => v_amount,
        p_allocations   => jsonb_build_array(jsonb_build_object(
                               'documenttype', 'RawMaterialPurchase',
                               'documentid',   p_waterrawmaterialpurchaseid,
                               'amount',       v_amount)),
        p_paymentmethod => p_paymentmethod,
        p_paymentdate   => p_paymentdate,
        p_cashaccountid => v_doc.cashaccountid,
        p_reference     => NULL,
        p_note          => NULL,
        p_sourcetype    => 'PurchaseEntry',
        p_createdby     => p_createdby);

    RETURN QUERY
    SELECT GREATEST(pu.totalcost - pu.amountpaid, 0)::numeric(14,2)
    FROM   waterrawmaterialpurchases pu
    WHERE  pu.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid
      AND  pu.farmid = p_farmid;
END;
$function$;

-- 5g. The supplier balances page.
DROP FUNCTION IF EXISTS public.spwatersupplierbalances(text, date, date, integer, text, numeric, text);

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
               (o.docdate + o.terms)                  AS duedate,
               ((o.docdate + o.terms) < CURRENT_DATE) AS isoverdue
        FROM   opendocs o
        WHERE  CASE COALESCE(p_status, 'All')
                    WHEN 'Partial' THEN o.amountpaid > 0
                    WHEN 'Unpaid'  THEN o.amountpaid = 0
                    WHEN 'Overdue' THEN (o.docdate + o.terms) < CURRENT_DATE
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

-- 5h. The purchases behind one supplier's balance.
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
           (d.docdate + COALESCE(s.paymenttermsdays, 0))::date,
           GREATEST((CURRENT_DATE - d.docdate), 0)::integer,
           CASE WHEN d.amountpaid > 0 THEN 'Partially Paid' ELSE 'Unpaid' END::text,
           ((d.docdate + COALESCE(s.paymenttermsdays, 0)) < CURRENT_DATE),
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
                WHEN 'Overdue' THEN (d.docdate + COALESCE(s.paymenttermsdays, 0)) < CURRENT_DATE
                ELSE TRUE
           END
    ORDER  BY d.docdate, d.documentid;
$function$;

-- 5i. Summary cards.
DROP FUNCTION IF EXISTS public.spwatersupplierbalancesummary(text);

CREATE OR REPLACE FUNCTION public.spwatersupplierbalancesummary(p_farmid text)
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
    WITH per AS (
        SELECT b.supplierid, b.suppliername, b.totalbalance, b.overdueamount
        FROM   spwatersupplierbalances(p_farmid) b
    )
    SELECT COALESCE(SUM(p.totalbalance), 0)::numeric(14,2),
           COUNT(*)::integer,
           COALESCE(SUM(p.overdueamount), 0)::numeric(14,2),
           COALESCE((SELECT SUM(sp.totalamount) FROM watersupplierpayments sp
                     WHERE sp.farmid = p_farmid
                       AND COALESCE(sp.status, 'Posted') = 'Posted'
                       AND sp.paymentdate::date = CURRENT_DATE), 0)::numeric(14,2),
           COALESCE(MAX(p.totalbalance), 0)::numeric(14,2),
           (SELECT p2.suppliername FROM per p2 ORDER BY p2.totalbalance DESC LIMIT 1)
    FROM   per p;
$function$;

-- 5j. Supplier statement.
DROP FUNCTION IF EXISTS public.spwatersupplierstatement(text, integer, date, date);

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

        -- A purchase INCREASES what we owe, so it is the debit here -- the
        -- mirror of the customer statement, where a sale is the debit.
        SELECT d.docdate, 'Purchase'::text, d.reference, d.label,
               d.totalcost::numeric(14,2), 0::numeric(14,2),
               d.documenttype, d.documentid, 1, 1
        FROM   fnwaterpayables(p_farmid) d
        WHERE  d.supplierid = p_supplierid
          AND  (p_from IS NULL OR d.docdate >= p_from)
          AND  (p_to   IS NULL OR d.docdate <= p_to)

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

-- 5k. Supplier payment history + allocation detail.
DROP FUNCTION IF EXISTS public.spwatersupplierpayment_history(text, integer, text, integer, date, date);

CREATE OR REPLACE FUNCTION public.spwatersupplierpayment_history(
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
    watercashaccountid integer,
    createdby       text,
    reversedby      text,
    reversedat      timestamp without time zone,
    reversalreason  text)
LANGUAGE sql
STABLE
AS $function$
    SELECT sp.watersupplierpaymentid,
           sp.supplierid,
           s.suppliername::text,
           sp.paymentdate,
           sp.totalamount,
           sp.paymentmethod::text,
           sp.referenceno::text,
           sp.notes::text,
           sp.sourcetype::text,
           COALESCE(sp.status, 'Posted')::text,
           (SELECT COUNT(*)::integer FROM supplierpaymentallocation sa
            WHERE sa.farmid = sp.farmid AND sa.module = 'water'
              AND sa.paymentid = sp.watersupplierpaymentid),
           sp.watercashaccountid,
           sp.createdby::text,
           sp.reversedby::text,
           sp.reversedat,
           sp.reversalreason::text
    FROM   watersupplierpayments sp
    LEFT   JOIN watersuppliers s ON s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  (p_supplierid IS NULL OR sp.supplierid = p_supplierid)
      AND  (p_from IS NULL OR sp.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR sp.paymentdate::date <= p_to)
      AND  (p_documentid IS NULL OR EXISTS (
              SELECT 1 FROM supplierpaymentallocation sa
              WHERE sa.paymentid = sp.watersupplierpaymentid
                AND sa.module = 'water'
                AND sa.documentid = p_documentid
                AND (p_documenttype IS NULL OR sa.documenttype = p_documenttype)))
    ORDER  BY sp.paymentdate DESC, sp.watersupplierpaymentid DESC;
$function$;

DROP FUNCTION IF EXISTS public.spwatersupplierpayment_allocations(text, integer);

CREATE OR REPLACE FUNCTION public.spwatersupplierpayment_allocations(
    p_farmid text, p_paymentid integer)
RETURNS TABLE(
    allocationid  integer,
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
    SELECT sa.allocationid, sa.documenttype, sa.documentid,
           d.reference, d.docdate, d.label, d.totalcost,
           sa.amountapplied, sa.documentbalancebefore, sa.documentbalanceafter,
           sa.status::text
    FROM   supplierpaymentallocation sa
    LEFT   JOIN fnwaterpayables(p_farmid) d
           ON d.documenttype = sa.documenttype AND d.documentid = sa.documentid
    WHERE  sa.farmid = p_farmid
      AND  sa.module = 'water'
      AND  sa.paymentid = p_paymentid
    ORDER  BY d.docdate, sa.documentid;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Audit helper -- allocations vs the document's own amountpaid.
-- -----------------------------------------------------------------------------
-- The two must agree. A non-zero difference means a payment moved a document's
-- amountpaid without writing an allocation (or the reverse), which is the one
-- failure mode this design can have.
-- Dropped first for the same reason as the pay-balance function above: if a
-- name already exists with a different return type, CREATE OR REPLACE fails.
DROP FUNCTION IF EXISTS public.fnwaterbalanceaudit(text);

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
      AND  (pu.amountpaid - COALESCE(a.allocated, 0)) <> 0;
$function$;

-- Note: the supplier audit rows will be non-zero for every purchase that was
-- part-paid BEFORE this migration, because those payments predate the
-- allocation table and there is no per-payment history to reconstruct them from
-- (unlike the customer side, where waterpayments held one row per payment).
-- That is a known, one-time opening difference, not a defect: the balances
-- themselves are correct because they read amountpaid.

-- -----------------------------------------------------------------------------
-- 7. IAM catalog.
-- -----------------------------------------------------------------------------
-- Seeded only now, with the pages: a permission that appears in the roles UI
-- before its page exists is a support ticket waiting to happen (222).
-- Same groups, labels and sort orders as the poultry rows in 222, so the two
-- modules' roles UIs read identically.
INSERT INTO iampermissions
    (permissionkey, module, resource, action, permissiongroup, resourcelabel, description, companytype, isdangerous, sortorder)
VALUES
    ('water.customer-balances.view',   'water', 'customer-balances', 'view',    'Sales & Customers', 'Customer Balances', 'See who owes money and the unpaid sales behind each balance.', 'Water', false, 62),
    ('water.customer-payments.create', 'water', 'customer-payments', 'create',  'Sales & Customers', 'Customer Balances', 'Receive a payment and allocate it across open sales.',        'Water', false, 62),
    ('water.customer-payments.reverse','water', 'customer-payments', 'reverse', 'Sales & Customers', 'Customer Balances', 'Reverse a posted customer payment.',                          'Water', true,  62),
    ('water.customer-statements.view', 'water', 'customer-statements','view',   'Sales & Customers', 'Customer Statements', 'Open a customer statement for a date range.',               'Water', false, 63),
    ('water.supplier-balances.view',   'water', 'supplier-balances', 'view',    'Purchasing',        'Supplier Balances', 'See who we owe and the unpaid purchases behind each balance.', 'Water', false, 71),
    ('water.supplier-payments.create', 'water', 'supplier-payments', 'create',  'Purchasing',        'Supplier Balances', 'Record a supplier payment and allocate it across open purchases.', 'Water', false, 71),
    ('water.supplier-payments.reverse','water', 'supplier-payments', 'reverse', 'Purchasing',        'Supplier Balances', 'Reverse a posted supplier payment.',                          'Water', true,  71),
    ('water.supplier-statements.view', 'water', 'supplier-statements','view',   'Purchasing',        'Supplier Statements', 'Open a supplier statement for a date range.',               'Water', false, 72)
ON CONFLICT (permissionkey) DO NOTHING;

COMMIT;

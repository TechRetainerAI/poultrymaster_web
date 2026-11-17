-- =============================================================================
-- 423_WaterPaymentsClosingCashFlowFixes.postgres.sql   (Water credits programme, W0)
--
-- Purpose
-- -------
-- Four existing Water bugs, fixed before the credit work (W1-W5) builds on
-- them.  Every body is the LIVE body (pg_get_functiondef, 2026-11-12); only the
-- marked lines change.
--
--  1. spwaterpayment_record (Sales page) recomputed the sale's amountpaid from
--     EVERY payment, reversed ones included, and never named the payment's
--     customer.  It now calls spwatersale_recompute (Posted only) and writes
--     watercustomerid + sourcetype 'SaleEntry'.  Payments it wrote before are
--     backfilled with their sale's customer where the sale has one.
--
--  2. fnwaterdailyclosing_livetotals (poultry 364's bug):
--       * credit sales = what is owed NOW, so a later payment rewrote a past
--         day.  Now fnwatersale_owedasof: owed at the END of that day.
--       * customer collections counted Reversed payments, and payments on a sale
--         made the same day -- already in that sale's paid part, so counted
--         twice.  Both excluded.
--     Approved closings keep the figures they stored.
--
--  3. spwatersupplierpaymentcash_unsync gave back the aggregated expense's
--     AMOUNT, which since 275 is only the part expensed at purchase, while the
--     CashOut was the full purchase portion: reversing a payment that covered
--     deferred stock left the cash account short.  It now gives back what the
--     ledger shows went out.
--
--  4. spwatercashflow_rows (poultry 376's rule):
--       * a REVERSED supplier payment vanished from Cash Flow (arm 3 dropped its
--         Cancelled expense, arm 3b its Reversed allocations), and no arm showed
--         the money coming back;
--       * the purchase part of a payment reached Cash Flow only through the
--         aggregated expense, which excludes deferred lots (275) -- so a payment
--         for deferred stock never showed at all.
--     Now: arm 3 skips the aggregated payment expense; new arm 3c reports the
--     FULL purchase portion on the payment date (reversed or not); arm 3b keeps
--     a reversed payment's bill money on its date; new arm 3d reports the
--     reversal's money IN on the reversal date.  spwatercashflow_detail
--     categorises the new rows as raw-material purchases.
--
-- Deploy order: this migration only.  No API or web change.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;


-- ------------------------------------------------ 1. Sales-page payment
CREATE OR REPLACE FUNCTION public.spwaterpayment_record(p_farmid text, p_watersaleid integer DEFAULT NULL::integer, p_amount numeric DEFAULT NULL::numeric, p_paymentmethod text DEFAULT NULL::text, p_paymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_reference text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_paymentdate timestamp := p_paymentdate;
    v_paymentid   integer;
    v_before      numeric;
BEGIN
    IF v_paymentdate IS NULL THEN
        v_paymentdate := (now() at time zone 'utc');
    END IF;

    -- Sale must belong to farm.
    IF NOT EXISTS (SELECT 1 FROM watersales s
                   WHERE s.watersaleid = p_watersaleid AND s.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Sale does not belong to this farm.';
    END IF;

    -- What the sale still owed a moment before this payment.
    SELECT s.totalamount
           - COALESCE((SELECT SUM(w.amount) FROM waterpayments w
                       WHERE w.watersaleid = s.watersaleid
                         AND COALESCE(w.status, 'Posted') <> 'Reversed'), 0)
    INTO   v_before
    FROM   watersales s
    WHERE  s.watersaleid = p_watersaleid;

    -- 423: the payment names its customer and its source, like every other
    -- writer's payment, so customer payment history can find it.
    INSERT INTO waterpayments
        (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note, createdby, paymentgroupid,
         watercustomerid, sourcetype)
    VALUES (p_farmid, p_watersaleid, p_amount, p_paymentmethod, v_paymentdate, p_reference, p_note, p_createdby, gen_random_uuid(),
            (SELECT s.watercustomerid FROM watersales s WHERE s.watersaleid = p_watersaleid AND s.farmid = p_farmid),
            'SaleEntry')
    RETURNING waterpaymentid INTO v_paymentid;

    -- The snapshot. Same shape spwatercustomerpayment_record writes, so both
    -- writers' payments read identically on the page and in the statement.
    INSERT INTO customerpaymentallocation
        (farmid, module, paymentid, saleid, amountapplied,
         salebalancebefore, salebalanceafter, status, createdby, createdat)
    VALUES
        (p_farmid, 'water', v_paymentid, p_watersaleid, p_amount,
         v_before, v_before - p_amount, 'Posted', p_createdby, v_paymentdate);

    -- 423: the shared recompute counts POSTED payments only. This writer used to
    -- sum every payment on the sale, reversed ones included, so the first
    -- reversal followed by a new payment left the sale over-paid.
    PERFORM public.spwatersale_recompute(p_farmid, p_watersaleid);

    RETURN v_paymentid;
END;
$function$;

-- backfill: the Sales-page payments that never named their customer / source
UPDATE waterpayments p SET watercustomerid = s.watercustomerid
FROM   watersales s
WHERE  s.watersaleid = p.watersaleid AND s.farmid = p.farmid
  AND  p.watercustomerid IS NULL AND s.watercustomerid IS NOT NULL;

-- ------------------------------------------------ 2. Daily closing
-- What a sale still owed at the END of a day: today's balance plus every
-- posted payment dated after that day.  Built from the balance (not from
-- totalamount less payments) because a water sale settled on the spot can set
-- amountpaid with no payment row at all.
CREATE OR REPLACE FUNCTION public.fnwatersale_owedasof(p_farmid text, p_watersaleid integer, p_asof date)
RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT GREATEST(
               COALESCE(s.totalamount, 0) - COALESCE(s.amountpaid, 0)
             + COALESCE((SELECT SUM(p.amount) FROM waterpayments p
                         WHERE p.farmid = s.farmid AND p.watersaleid = s.watersaleid
                           AND COALESCE(p.status, 'Posted') = 'Posted'
                           AND p.paymentdate >= p_asof::timestamp + interval '1 day'), 0),
           0)::numeric
    FROM   watersales s
    WHERE  s.watersaleid = p_watersaleid AND s.farmid = p_farmid;
$f$;

CREATE OR REPLACE FUNCTION public.fnwaterdailyclosing_livetotals(p_farmid text, p_closingdate date)
 RETURNS TABLE(bagsproduced numeric, totalproductioncost numeric, bagssold numeric, totalincome numeric, creditsales numeric, customercollections numeric, bagsreturned numeric, bagsdamaged numeric, drivershortagestotal numeric, momobalance numeric, bankbalance numeric, rawmaterialspendtoday numeric, closingstockbags numeric, totalexpenses numeric, cashathand numeric)
 LANGUAGE sql
AS $function$
    WITH
    prod AS (
        SELECT
            COALESCE(SUM((pb.bagsproduced - COALESCE(pb.damagedbags, 0))::numeric(14,3)), 0) AS bagsproduced,
            COALESCE(SUM(pb.totalproductioncost), 0) AS totalproductioncost
        FROM waterproductionbatches pb
        WHERE pb.farmid = p_farmid AND pb.isdeleted = FALSE AND pb.status = 'Approved'
          AND pb.productiondate = p_closingdate
    ),
    sale_items AS (
        SELECT COALESCE(SUM(si.quantity::numeric(14,3)), 0) AS bagssold
        FROM   watersales s
        INNER  JOIN watersaleitems si ON si.watersaleid = s.watersaleid
        WHERE  s.farmid = p_farmid AND s.status NOT IN ('Cancelled')
           AND COALESCE(s.sourcetype, '') <> 'DeliveryRun'
           AND s.saledate >= p_closingdate::timestamp
           AND s.saledate <  p_closingdate::timestamp + interval '1 day'
    ),
    sale_money AS (
        SELECT
            COALESCE(SUM(s2.totalamount), 0) AS totalincome,
            -- 423: what was still OWED at the end of the day (364's rule), not
            -- what is owed now -- a payment made later must not rewrite a past day.
            COALESCE(SUM(public.fnwatersale_owedasof(p_farmid, s2.watersaleid, p_closingdate)), 0) AS creditsales
        FROM   watersales s2
        WHERE  s2.farmid = p_farmid AND s2.status NOT IN ('Cancelled')
           AND COALESCE(s2.sourcetype, '') <> 'DeliveryRun'
           AND s2.saledate >= p_closingdate::timestamp
           AND s2.saledate <  p_closingdate::timestamp + interval '1 day'
    ),
    payments AS (
        SELECT
            COALESCE(SUM(pay.amount), 0) AS customercollections,
            COALESCE(SUM(CASE WHEN pay.paymentmethod IN ('Mobile Money', 'MoMo', 'Momo') THEN pay.amount ELSE 0 END), 0) AS momopayments,
            COALESCE(SUM(CASE WHEN pay.paymentmethod IN ('Bank', 'Bank Transfer', 'Transfer') THEN pay.amount ELSE 0 END), 0) AS bankpayments
        FROM   waterpayments pay
        LEFT   JOIN watersales ps ON ps.watersaleid = pay.watersaleid AND ps.farmid = pay.farmid
        WHERE  pay.farmid = p_farmid
           AND COALESCE(pay.sourcetype, '') <> 'DeliveryRun'
           -- 423: a reversed payment collected nothing.
           AND COALESCE(pay.status, 'Posted') = 'Posted'
           -- 423: a payment on a sale made the SAME day is already in that sale's
           -- paid part (income less credit); counting it here too doubled it.
           AND NOT (ps.watersaleid IS NOT NULL
                    AND COALESCE(ps.sourcetype, '') <> 'DeliveryRun'
                    AND ps.saledate >= p_closingdate::timestamp
                    AND ps.saledate <  p_closingdate::timestamp + interval '1 day')
           AND pay.paymentdate >= p_closingdate::timestamp
           AND pay.paymentdate <  p_closingdate::timestamp + interval '1 day'
    ),
    ranked_returns AS (
        SELECT
            dr.waterdriverreturnid, dr.watervehicleloadingid,
            dr.bagsreturned, dr.bagsdamaged, dr.bagssold,
            dr.cashcollected, dr.momocollected, dr.bankcollected, dr.creditsalesamount, dr.shortageamount,
            ROW_NUMBER() OVER (PARTITION BY dr.watervehicleloadingid ORDER BY dr.waterdriverreturnid DESC) AS rn
        FROM   waterdriverreturns dr
        WHERE  dr.farmid = p_farmid AND dr.status = 'Approved'
           AND dr.returndate >= p_closingdate::timestamp
           AND dr.returndate <  p_closingdate::timestamp + interval '1 day'
    ),
    driver_returns AS (
        SELECT
            COALESCE(SUM(rr.bagsreturned::numeric(14,3)), 0) AS bagsreturned,
            COALESCE(SUM(rr.bagsdamaged::numeric(14,3)), 0)  AS bagsdamaged,
            COALESCE(SUM(rr.bagssold::numeric(14,3)), 0)     AS driverbagssold,
            COALESCE(SUM(rr.cashcollected + rr.momocollected + rr.bankcollected + rr.creditsalesamount), 0) AS drivertotalincome,
            COALESCE(SUM(rr.creditsalesamount), 0) AS drivercreditsales,
            COALESCE(SUM(rr.momocollected), 0) AS drivermomo,
            COALESCE(SUM(rr.bankcollected), 0) AS driverbank,
            COALESCE(SUM(rr.shortageamount), 0) AS drivershortages
        FROM   ranked_returns rr
        WHERE  rr.rn = 1
    ),
    raw_spend AS (
        SELECT COALESCE(SUM(rp.amountpaid), 0) AS rawmaterialspendtoday
        FROM   waterrawmaterialpurchases rp
        WHERE  rp.farmid = p_farmid
           AND rp.purchasedate >= p_closingdate::timestamp
           AND rp.purchasedate <  p_closingdate::timestamp + interval '1 day'
    ),
    gen_exp AS (
        SELECT COALESCE(SUM(e.amount), 0) AS generalexpenses
        FROM   waterexpenses e
        WHERE  e.farmid = p_farmid AND e.isdeleted = FALSE AND e.status = 'Approved'
           AND COALESCE(e.sourcetype, '') NOT IN ('RawMaterialPurchase', 'WaterInternalUsage')
           AND e.expensedate >= p_closingdate::timestamp
           AND e.expensedate <  p_closingdate::timestamp + interval '1 day'
    ),
    delivery_exp AS (
        SELECT COALESCE(SUM(de.amount), 0) AS deliveryexpenses
        FROM   waterdeliveryexpenses de
        INNER  JOIN ranked_returns rr2 ON rr2.waterdriverreturnid = de.waterdriverreturnid AND rr2.rn = 1
        WHERE  de.isapproved = TRUE
    ),
    closing_stock AS (
        SELECT COALESCE(SUM(st.quantity::numeric(14,3)), 0) AS closingstockbags
        FROM   waterstocktransactions st WHERE st.farmid = p_farmid
    )
    SELECT
        prod.bagsproduced,
        prod.totalproductioncost,
        sale_items.bagssold + driver_returns.driverbagssold          AS bagssold,
        sale_money.totalincome + driver_returns.drivertotalincome    AS totalincome,
        sale_money.creditsales + driver_returns.drivercreditsales    AS creditsales,
        payments.customercollections,
        driver_returns.bagsreturned,
        driver_returns.bagsdamaged,
        driver_returns.drivershortages                               AS drivershortagestotal,
        driver_returns.drivermomo + payments.momopayments            AS momobalance,
        driver_returns.driverbank + payments.bankpayments            AS bankbalance,
        raw_spend.rawmaterialspendtoday,
        closing_stock.closingstockbags,
        prod.totalproductioncost + raw_spend.rawmaterialspendtoday
            + gen_exp.generalexpenses + delivery_exp.deliveryexpenses AS totalexpenses,
        (sale_money.totalincome + driver_returns.drivertotalincome)
            - (sale_money.creditsales + driver_returns.drivercreditsales)
            + payments.customercollections
            - (prod.totalproductioncost + raw_spend.rawmaterialspendtoday
               + gen_exp.generalexpenses + delivery_exp.deliveryexpenses) AS cashathand
    FROM   prod
    CROSS  JOIN sale_items
    CROSS  JOIN sale_money
    CROSS  JOIN payments
    CROSS  JOIN driver_returns
    CROSS  JOIN raw_spend
    CROSS  JOIN gen_exp
    CROSS  JOIN delivery_exp
    CROSS  JOIN closing_stock
$function$;

-- ------------------------------------------------ 3. supplier payment reversal cash
CREATE OR REPLACE FUNCTION public.spwatersupplierpaymentcash_unsync(p_farmid text, p_paymentid integer, p_reversedby text DEFAULT NULL::text)
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

    -- 423: give back the cash that LEFT, not the expense's amount. Since 275 the
    -- expense holds only the part expensed at purchase while the CashOut keyed to
    -- it is the full purchase portion, so refunding e.amount left a payment with
    -- deferred stock permanently short in the cash account.
    IF v_expense IS NOT NULL THEN
        SELECT COALESCE(SUM(-ct.amount), 0), COALESCE(MAX(ct.watercashaccountid), v_acct)
        INTO   v_amount, v_acct
        FROM   watercashtransactions ct
        WHERE  ct.farmid = p_farmid AND ct.sourcetype = 'Expense'
          AND  ct.sourceid = v_expense AND ct.amount < 0;
    END IF;

    IF v_expense IS NOT NULL THEN
        UPDATE waterexpenses
        SET    status = 'Cancelled',
               notes  = COALESCE(notes, '') || ' | Reversed with the supplier payment.'
        WHERE  waterexpenseid = v_expense AND farmid = p_farmid;

        IF v_acct IS NOT NULL AND v_amount > 0 THEN
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

-- ------------------------------------------------ 4. Cash Flow
CREATE OR REPLACE FUNCTION public.spwatercashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, createdat timestamp without time zone)
 LANGUAGE plpgsql
 STABLE
AS $function$

DECLARE

    v_tbl  text;
    v_createdcol text;               -- 302: 'ca.createddate' or NULL

    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);

    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);

BEGIN

    -- ---- 1. customer receipts, dated when the money arrived -----------------

    RETURN QUERY

    SELECT 'Receipt'::text,

           FALSE,

           p.waterpaymentid,

           NULL::integer,

           NULL::text,

           p.paymentdate,

           'CashIn'::text,

           'CustomerPayment'::text,

           p.watersaleid,

           FALSE,

           COALESCE(p.amount, 0)::numeric,

           COALESCE(NULLIF(btrim(p.note), ''),

                    NULLIF(btrim(p.reference), ''),

                    'Payment for sale #' || p.watersaleid::text)::text,

           'OperatingIn'::text

           , p.createddate   -- 302: the entry time
    FROM   waterpayments p

    WHERE  lower(p.farmid::text) = lower(p_farmid)

      AND  COALESCE(p.amount, 0) <> 0

      -- A REVERSED payment is money that came back. 227 added this column and

      -- flips it on reversal rather than deleting the row, so without this filter

      -- the report counts a refunded receipt as income for ever.

      AND  COALESCE(p.status, 'Posted') = 'Posted'

      AND  p.paymentdate >= v_from

      AND  p.paymentdate <= v_to;



    -- ---- 2. the part paid at the point of sale -----------------------------

    -- Same reasoning as 235: a sale settled on the spot may never create a

    -- payment row, and the difference is what picks those up.

    RETURN QUERY

    SELECT 'SaleResidual'::text,

           FALSE,

           s.watersaleid,

           NULL::integer,

           NULL::text,

           s.saledate,

           'CashIn'::text,

           'Sale'::text,

           s.watersaleid,

           FALSE,

           v.residual,

           ('Sale #' || s.watersaleid::text)::text,

           'OperatingIn'::text

           , s.createddate   -- 302: the entry time
    FROM   watersales s

    CROSS  JOIN LATERAL (

        SELECT ROUND(

                   CASE WHEN COALESCE(s.status, '') = 'Paid'

                        THEN COALESCE(s.totalamount, 0)

                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),

                                   COALESCE(s.totalamount, 0))

                   END

                 - COALESCE((SELECT SUM(wp.amount)

                             FROM   waterpayments wp

                             WHERE  wp.watersaleid = s.watersaleid

                               AND  lower(wp.farmid::text) = lower(p_farmid)

                               -- Same reason: a reversed payment never covered

                               -- anything, so it must not reduce the residual.

                               AND  COALESCE(wp.status, 'Posted') = 'Posted'), 0)

               , 2) AS residual

    ) v

    WHERE  lower(s.farmid::text) = lower(p_farmid)

      -- A cancelled sale is not income, whatever it once recorded as paid.

      AND  COALESCE(s.status, '') <> 'Cancelled'

      AND  v.residual > 0

      AND  s.saledate >= v_from

      AND  s.saledate <= v_to;



    -- ---- 3. money paid out when the bill was recorded -----------------------

    -- 236's gates are kept verbatim -- Approved, not deleted -- with two

    -- changes:

    --

    --   * the AMOUNT is what was actually paid at entry, not the whole bill:

    --     the resolved amountpaid, less anything a supplier payment has since

    --     covered (which the next arm reports on its own, later, date);

    --   * the `paymentmethod <> 'Credit'` filter is GONE, because the resolution

    --     subsumes it. A Credit bill resolves to 0 paid and drops out on

    --     `paidatentry > 0` instead -- same rows excluded, and a Credit bill

    --     that has since been part-paid is no longer wrongly invisible.

    RETURN QUERY

    SELECT 'Expense'::text,

           FALSE,

           e.waterexpenseid,

           e.watercashaccountid,

           NULL::text,

           e.expensedate,

           'CashOut'::text,

           'Expense'::text,

           e.waterexpenseid,

           FALSE,

           -v.paidatentry,

           COALESCE(NULLIF(btrim(e.description), ''),

                    NULLIF(btrim(e.paidto), ''),

                    'Expense #' || e.waterexpenseid::text)::text,

           'OperatingOut'::text

           , e.createdat   -- 302: the entry time
    FROM   waterexpenses e

    CROSS  JOIN LATERAL (

        SELECT GREATEST(

                   COALESCE(e.amountpaid,

                            CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'

                                 THEN 0 ELSE e.amount END)

                 - COALESCE((SELECT SUM(sa.amountapplied)

                             FROM   supplierpaymentallocation sa

                             WHERE  sa.farmid = p_farmid

                               AND  sa.module = 'water'

                               AND  sa.status = 'Posted'

                               AND  sa.documenttype = 'Expense'

                               AND  sa.documentid = e.waterexpenseid), 0)

               , 0)::numeric AS paidatentry

    ) v

    WHERE  lower(e.farmid::text) = lower(p_farmid)

      AND  COALESCE(e.isdeleted, false) = false

      AND  v.paidatentry > 0

      -- 047's rule: only an approved expense has been recognised at all.

      AND  COALESCE(e.status, '') = 'Approved'

      -- 259. 'NonCash' means "a cost recorded, but the money moved elsewhere".

      -- Loan interest and fees are written this way: the repayment's own arm

      -- below reports the FULL amount that left the account, so counting these

      -- rows here as well would take 12,500 out of the bank and 15,000 off the

      -- cash flow. Expense reports do not filter NonCash, so the cost still

      -- counts where it should.

      --

      -- No-op on today's data: there are zero water expenses with this marker.

      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'

      -- 423: a supplier payment's own aggregated expense row is not read here.
      -- It holds only the part expensed at purchase and is Cancelled on
      -- reversal; the payment's cash is reported from the payment below (3c).
      AND  COALESCE(e.sourcetype, '') <> 'WaterSupplierPayment'

      AND  e.expensedate >= v_from

      AND  e.expensedate <= v_to;



    -- ---- 3b. money paid out later, against a bill already recorded ----------

    -- A supplier payment settling a bill. It belongs to the day the money moved,

    -- not the day the bill was entered.

    --

    -- Only documenttype='Expense'. A payment against a raw-material purchase

    -- books its own aggregated expense row dated the payment date (240) and is

    -- already counted by arm 3; adding it here would double it.

    RETURN QUERY

    SELECT 'ExpensePayment'::text,

           FALSE,

           sa.allocationid,

           sp.watercashaccountid,

           NULL::text,

           sp.paymentdate,

           'CashOut'::text,

           'ExpensePayment'::text,

           sa.documentid,

           FALSE,

           -sa.amountapplied::numeric,

           ('Payment for expense #' || sa.documentid::text ||

            COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,

           'OperatingOut'::text

           , sa.createdat   -- 302: the entry time
    FROM   supplierpaymentallocation sa

    JOIN   watersupplierpayments sp

           ON  sp.watersupplierpaymentid = sa.paymentid

           AND sp.farmid = sa.farmid

    LEFT   JOIN watersuppliers s

           ON  s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid

    WHERE  sa.farmid = p_farmid

      AND  sa.module = 'water'

      -- 423: a reversed payment's money still LEFT on its date (376's rule);
      -- the reversal brings it back on its own date (3d). Allocations are only
      -- ever reversed together with their payment.
      AND  (sa.status = 'Posted' OR (sa.status = 'Reversed' AND sp.status = 'Reversed'))

      AND  sa.documenttype = 'Expense'

      AND  COALESCE(sp.status, 'Posted') IN ('Posted', 'Reversed')

      AND  sa.amountapplied <> 0

      AND  sp.paymentdate >= v_from

      AND  sp.paymentdate <= v_to;



    -- ---- 3c. 423: supplier payments for raw-material purchases ------------
    --
    -- The FULL purchase portion, on the payment date -- deferred lots included,
    -- because the supplier was paid for them whether or not their cost has
    -- reached the P&L (275). Reversed payments stay: the money did leave.
    RETURN QUERY
    SELECT 'SupplierPurchasePayment'::text,
           FALSE,
           sp.watersupplierpaymentid,
           sp.watercashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'WaterSupplierPayment'::text,
           sp.watersupplierpaymentid,
           FALSE,
           -x.amount,
           ('Supplier payment - raw material purchase' ||
            COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,
           'OperatingOut'::text,
           sp.createdat
    FROM   watersupplierpayments sp
    CROSS  JOIN LATERAL (
        SELECT COALESCE(SUM(sa.amountapplied), 0)::numeric AS amount
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = sp.farmid AND sa.module = 'water'
          AND  sa.paymentid = sp.watersupplierpaymentid
          AND  sa.documenttype <> 'Expense'
          AND  (sa.status = 'Posted' OR (sa.status = 'Reversed' AND sp.status = 'Reversed'))
    ) x
    LEFT   JOIN watersuppliers s
           ON  s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  COALESCE(sp.status, 'Posted') IN ('Posted', 'Reversed')
      AND  x.amount <> 0
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;

    -- ---- 3d. 423: a reversed supplier payment's money coming back ---------
    --
    -- Everything the payment paid out (purchases and bills), back in on the
    -- day it was reversed.
    RETURN QUERY
    SELECT 'SupplierPaymentReversal'::text,
           FALSE,
           sp.watersupplierpaymentid,
           sp.watercashaccountid,
           NULL::text,
           sp.reversedat,
           'CashIn'::text,
           'WaterSupplierPayment'::text,
           sp.watersupplierpaymentid,
           FALSE,
           x.amount,
           ('Reversal of supplier payment #' || sp.watersupplierpaymentid::text ||
            COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,
           'OperatingIn'::text,
           sp.reversedat
    FROM   watersupplierpayments sp
    CROSS  JOIN LATERAL (
        SELECT COALESCE(SUM(sa.amountapplied), 0)::numeric AS amount
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = sp.farmid AND sa.module = 'water'
          AND  sa.paymentid = sp.watersupplierpaymentid
          AND  sa.status = 'Reversed'
    ) x
    LEFT   JOIN watersuppliers s
           ON  s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  sp.status = 'Reversed'
      AND  sp.reversedat IS NOT NULL
      AND  x.amount <> 0
      AND  sp.reversedat >= v_from
      AND  sp.reversedat <= v_to;

    -- ---- 4. owner money (258) ----------------------------------------------

    -- Contributions and draws recorded through the Owner Money module.

    -- FINANCING, not operating: the owner funded the business or took funding

    -- back. Never revenue, never expense.

    --

    -- Reversed records are dropped entirely rather than netted to zero with a

    -- second row -- a contribution that was put in and taken back out is not

    -- funding, and showing both legs would put money the business never kept

    -- into Money In and Money Out.

    --

    -- Placed ABOVE the legacy capital arm on purpose: that arm RETURNs early

    -- when cashadjustment is absent, so anything below it is skipped on a

    -- company with no capital records.

    RETURN QUERY

    SELECT 'OwnerMoney'::text,

           FALSE,

           o.waterownermoneyid,

           o.watercashaccountid,

           a.accountname::text,

           o.transactiondate,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'CashIn' ELSE 'CashOut' END::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END::text,

           o.waterownermoneyid,

           FALSE,

           -- Stored positive; the sign is applied here, once.

           (CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE -o.amount END)::numeric,

           COALESCE(NULLIF(btrim(o.notes), ''),

                    NULLIF(btrim(o.ownername), ''),

                    CASE WHEN o.transactiontype = 'Contribution'

                         THEN 'Owner contribution' ELSE 'Owner draw' END)::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'FinancingIn' ELSE 'FinancingOut' END::text

           , o.createdat   -- 302: the entry time
    FROM   waterownermoney o

    LEFT   JOIN watercashaccounts a

           ON a.watercashaccountid = o.watercashaccountid

    WHERE  o.farmid = p_farmid

      AND  o.status = 'Posted'
      -- 297. A record backfilled from a Cash Flow adjustment has NO cash
      -- row of its own: the ADJUSTMENT is still the cash event, and the
      -- legacy adjustment arm below already reports it. Without this the
      -- same money is counted twice -- the trap 292 hit for loans.
      AND  o.sourceadjustmentid IS NULL

      AND  o.transactiondate >= v_from

      AND  o.transactiondate <= v_to;



    -- ---- 5. loans received (259) -------------------------------------------

    -- Borrowed money arriving. FINANCING: the business received it, it did not

    -- earn it, so it is money in and never revenue.

    --

    -- The AMOUNT RECEIVED, not the principal. A lender that withholds a fee

    -- pays out less than it lends, and only what arrived is cash in.

    --

    -- The timestamp carries 256's rule, baked in from the start rather than

    -- patched afterwards as it had to be on poultry: loandate is a DATE, so a

    -- plain cast gives midnight and a loan recorded this afternoon sorts below

    -- everything else recorded today. A loan dated TODAY reports the moment it

    -- was recorded; a BACK-DATED one keeps midnight, because using createdat

    -- unconditionally would drag last Tuesday's loan into today, above rows

    -- that really did happen after it.

    RETURN QUERY

    SELECT 'Loan'::text,

           FALSE,

           l.waterloanid,

           l.watercashaccountid,

           a.accountname::text,

           CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                ELSE l.loandate::timestamp END,

           'CashIn'::text,

           'LoanReceived'::text,

           l.waterloanid,

           FALSE,

           l.amountreceived::numeric,

           ('Loan received from ' || l.lendername)::text,

           'FinancingIn'::text

           , l.createdat   -- 302: the entry time
    FROM   waterloans l

    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = l.watercashaccountid

    WHERE  l.farmid = p_farmid

      AND  l.amountreceived > 0

      -- 293. A loan converted from a Cash Flow adjustment has NO cash row of

      -- its own: the ADJUSTMENT is the cash event, and the legacy adjustment arm

      -- already reports it. Without this the same borrowing is money-in twice --

      -- which is precisely what 292's stage check caught on the poultry side.

      AND  l.sourceadjustmentid IS NULL

      AND  l.status NOT IN ('Cancelled', 'Reversed', 'Draft')

      AND  (CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                 ELSE l.loandate::timestamp END) >= v_from

      AND  (CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                 ELSE l.loandate::timestamp END) <= v_to;



    -- ---- 6. loan repayments (259) ------------------------------------------

    -- The FULL payment leaves the account, so the full payment is money out --

    -- principal, interest and fees together.

    --

    -- This does NOT double count the interest and fee expenses those payments

    -- create: they are written paymentmethod = 'NonCash', and arm 3 above now

    -- skips NonCash. Expense reports read the expense table directly and still

    -- count them, which is the whole point -- cash out is 12,500, cost is 2,500.

    RETURN QUERY

    SELECT 'LoanPayment'::text,

           FALSE,

           p.waterloanpaymentid,

           p.watercashaccountid,

           a.accountname::text,

           p.paymentdate,

           'CashOut'::text,

           'LoanRepayment'::text,

           p.waterloanid,

           FALSE,

           -p.totalamount::numeric,

           ('Loan repayment to ' || l.lendername)::text,

           'FinancingOut'::text

           , p.createdat   -- 302: the entry time
    FROM   waterloanpayments p

    JOIN   waterloans l ON l.waterloanid = p.waterloanid

    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = p.watercashaccountid

    WHERE  p.farmid = p_farmid

      AND  p.status = 'Posted'

      AND  p.paymentdate >= v_from

      AND  p.paymentdate <= v_to;



    -- ---- 7. capital in and out (legacy cash adjustments) --------------------

    -- Expected to return nothing on Water today -- see 236's header note.

    --

    -- MUST STAY LAST: it RETURNs early when the table is absent, and anything

    -- below it would be silently skipped.

    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,

                      to_regclass('public.cashadjustments')::text);



    -- 302: only reference the creation column if the resolved table has one.
    SELECT CASE WHEN EXISTS (
               SELECT 1 FROM information_schema.columns c
               WHERE  c.table_schema = 'public'
                 AND  c.table_name = replace(v_tbl, 'public.', '')
                 AND  c.column_name = 'createddate')
           THEN 'ca.createddate' ELSE 'NULL::timestamp' END
      INTO v_createdcol;

    IF v_tbl IS NULL THEN

        RETURN;

    END IF;



    RETURN QUERY EXECUTE format($sql$

        SELECT 'Adjustment'::text,

               FALSE,

               ca.adjustmentid,

               NULL::integer,

               NULL::text,

               ca.adjustmentdate,

               CASE WHEN ca.amount >= 0 THEN 'CashIn' ELSE 'CashOut' END::text,

               COALESCE(NULLIF(btrim(ca.adjustmenttype), ''), 'Adjustment')::text,

               ca.adjustmentid,

               FALSE,

               ca.amount::numeric,

               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text,

               CASE WHEN ca.amount >= 0 THEN 'FinancingIn' ELSE 'FinancingOut' END::text,
               %s                       -- 302: the entry time

        FROM   %s ca

        WHERE  lower(ca.farmid::text) = lower($1)

          AND  ca.amount <> 0

          AND  ca.adjustmentdate >= $2

          AND  ca.adjustmentdate <= $3

    $sql$, v_createdcol, v_tbl)

    USING p_farmid, v_from, v_to;
    -- ---- 8. employee advances (313/315) ------------------------------------

    -- Disbursements out, manual repayments in, payroll deductions NOWHERE:

    -- a deduction moves no money, so it is not a cash event. The arms live in

    -- their own function, so this body is touched once and never again.

    RETURN QUERY

    SELECT * FROM public.spwateremployeeloan_cashflowrows(p_farmid, v_from, v_to);


END;

$function$;

CREATE OR REPLACE FUNCTION public.spwatercashflow_detail(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, category text, createdat timestamp without time zone)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname,
           r.transactiondate, r.transactiontype, r.sourcetype, r.sourceid,
           r.istransfer, r.amount, r.description, r.flowgroup,
           CASE
               WHEN r.rowsource IN ('Expense', 'ExpensePayment')
                   THEN COALESCE(NULLIF(btrim(c.name), ''), 'Uncategorised')
               WHEN r.rowsource IN ('Receipt', 'SaleResidual') THEN 'Sales'
               -- 423
               WHEN r.rowsource IN ('SupplierPurchasePayment', 'SupplierPaymentReversal')
                   THEN 'Raw Materials / Inventory Purchase'
               ELSE COALESCE(NULLIF(btrim(r.sourcetype), ''), 'Other')
           END::text,
           r.createdat              -- 302: the entry time
    FROM   public.spwatercashflow_rows(p_farmid, p_fromdate, p_todate) r
    LEFT   JOIN waterexpenses e
           ON  r.rowsource IN ('Expense', 'ExpensePayment')
           AND e.waterexpenseid = r.sourceid
           AND lower(e.farmid::text) = lower(p_farmid)
    LEFT   JOIN waterexpensecategories c
           ON  c.waterexpensecategoryid = e.waterexpensecategoryid;
$function$;

DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.fnwatersale_owedasof(text, integer, date) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

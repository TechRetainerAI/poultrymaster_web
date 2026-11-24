-- =============================================================================
-- 482_Enock_GenericWalkInSalePayment: approving a paid WALK-IN Generic sale fails.
--
-- 475/476 made spgenericsale_approve record a customer payment for every paid
-- sale (the cash entry points at it: sourcetype 'CustomerPayment', sourceid =
-- the payment). For a walk-in sale it wrote genericcustomerid = COALESCE(NULL, 0)
-- = 0, and fk_genericcustomerpayments_customer (added outside the migrations, on
-- dev and production) refuses customer 0: "insert or update on table
-- genericcustomerpayments violates foreign key constraint ..." (dev, sales 71/72,
-- 2026-11-23). Nothing reads 0 as "walk-in"; every reader looks customers up by id.
--
-- Fix: a payment may have NO customer (NULL -- the foreign key allows it).
--   * genericcustomerpayments.genericcustomerid becomes nullable
--   * spgenericsale_approve writes NULL for a walk-in, not 0
--   * spgenericcustomerpayment_reverse moves the customer ledger / balance only
--     when there is a customer (the cash side is unchanged)
--   * spgenericcustomerpayment_getall / _getbyid LEFT JOIN customers and show a
--     walk-in payment as customer 0 "Walk-in customer" (the API reads the id as a
--     non-null int; same shape, no API change), instead of hiding it
-- Bodies are the live dev functions with only those lines changed. Signatures
-- unchanged. No data is changed (no payment has customer 0 today).
-- =============================================================================

ALTER TABLE public.genericcustomerpayments ALTER COLUMN genericcustomerid DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.spgenericsale_approve(p_genericsaleid integer, p_farmid text, p_approvedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_customerid integer;
    v_cashaccountid integer;
    v_amountpaid numeric;
    v_balance numeric;
    v_totalamount numeric;
    v_saledate timestamp;
    v_receiptnumber text;
    v_paymentmethod text;
    v_applycreditamount numeric;
    v_cashnewbalance numeric := NULL;
    v_cashallowneg boolean;
    v_cashcurrent numeric;
    v_customernewbalance numeric;
    v_customerbalance numeric;
    v_paymentid integer;
    v_now timestamp := (now() at time zone 'utc');
BEGIN
    -- Idempotent
    IF EXISTS (SELECT 1 FROM genericsales s
               WHERE s.genericsaleid = p_genericsaleid AND s.farmid = p_farmid
                 AND s.status = 'Approved') THEN
        RETURN;
    END IF;

    SELECT s.status, s.genericcustomerid, s.genericcashaccountid,
           s.amountpaid, s.balance, s.totalamount, s.saledate,
           s.receiptnumber, s.paymentmethod,
           COALESCE(s.applycreditamount, 0)
    INTO   v_status, v_customerid, v_cashaccountid,
           v_amountpaid, v_balance, v_totalamount, v_saledate,
           v_receiptnumber, v_paymentmethod, v_applycreditamount
    FROM   genericsales s
    WHERE  s.genericsaleid = p_genericsaleid AND s.farmid = p_farmid
       AND s.isdeleted = FALSE
    LIMIT 1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Sale % not found.', p_genericsaleid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Sale cannot be approved from status %.', v_status;
    END IF;
    IF (v_amountpaid > 0 AND v_cashaccountid IS NULL) THEN
        RAISE EXCEPTION 'AmountPaid is greater than zero but no GenericCashAccountId is set.';
    END IF;
    -- Recalculate balance including credit
    v_balance := GREATEST(v_totalamount - v_amountpaid - v_applycreditamount, 0);
    IF (v_balance > 0 AND v_customerid IS NULL) THEN
        RAISE EXCEPTION 'Sale has an unpaid balance but no customer is attached (credit sales require a customer).';
    END IF;

    -- Credit pre-flight: pessimistic lock on customer to prevent double-spend
    IF (v_applycreditamount > 0) THEN
        IF v_customerid IS NULL THEN
            RAISE EXCEPTION 'Cannot apply credit without a customer.';
        END IF;
        SELECT c.currentbalance INTO v_customerbalance
        FROM   genericcustomers c
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid
        FOR UPDATE;  -- lock the row

        IF v_customerbalance IS NULL THEN
            RAISE EXCEPTION 'Customer not found.';
        END IF;
        -- Credit = negative balance; available = ABS of negative portion
        IF v_customerbalance >= 0 THEN
            RAISE EXCEPTION 'Customer has no credit available (balance: %).', v_customerbalance;
        END IF;
        IF v_applycreditamount > ABS(v_customerbalance) THEN
            RAISE EXCEPTION 'Credit requested (%) exceeds available credit (%).', v_applycreditamount, ABS(v_customerbalance);
        END IF;
    END IF;

    -- Stock pre-flight (using unitfactor for base-unit check)
    IF EXISTS (
        SELECT 1
        FROM   genericsaleitems i
        INNER  JOIN genericproducts p
            ON p.genericproductid = i.genericproductid AND p.farmid = p_farmid
        WHERE  i.genericsaleid = p_genericsaleid
           AND i.itemtype = 'Product'
           AND p.trackinventory = TRUE
           AND p.currentstock - (i.quantity * i.unitfactor) < 0
    ) THEN
        RAISE EXCEPTION 'Insufficient stock for one or more products on this sale.';
    END IF;

    -- Cash pre-flight
    IF (v_amountpaid > 0) THEN
        SELECT ca.allownegativebalance, ca.currentbalance
        INTO   v_cashallowneg, v_cashcurrent
        FROM   genericcashaccounts ca
        WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid
        LIMIT 1;

        IF v_cashcurrent IS NULL THEN
            RAISE EXCEPTION 'Cash account on the sale does not exist or belongs to another farm.';
        END IF;
        v_cashnewbalance := v_cashcurrent + v_amountpaid;
    END IF;

    -- =========================================================================
    -- TRANSACTION BODY
    -- =========================================================================

    -- 1. Mark sale approved, update balance to reflect credit
    UPDATE genericsales s
    SET    status = 'Approved', approvedby = p_approvedby,
           approvedat = v_now, updatedat = v_now,
           balance = v_balance,
           paymentstatus = CASE
               WHEN (v_amountpaid + v_applycreditamount) >= v_totalamount THEN 'Paid'
               WHEN (v_amountpaid + v_applycreditamount) > 0 THEN 'Partial'
               ELSE 'Unpaid'
           END
    WHERE  s.genericsaleid = p_genericsaleid AND s.farmid = p_farmid;

    -- 2. Inventory: SaleOut in BASE units (quantity * unitfactor)
    INSERT INTO genericstockmovements (
        farmid, genericproductid, movementdate, movementtype, quantity,
        unitcost, unitsellingprice, totalcostvalue, referencetype, referenceid,
        reason, createdby, approvedby, approvedat
    )
    SELECT p_farmid, i.genericproductid, v_saledate, 'SaleOut',
           -(i.quantity * i.unitfactor),  -- base units
           p.costprice,
           i.unitprice / i.unitfactor,    -- base-unit selling price
           p.costprice * i.quantity * i.unitfactor,  -- total cost in base units
           'Sale', p_genericsaleid,
           'Sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text)
               || CASE WHEN i.saleunit IS NOT NULL AND i.unitfactor <> 1
                       THEN ' (' || trim(to_char(i.quantity, 'FM999999999990.###')) || ' ' || i.saleunit || ')'
                       ELSE '' END,
           p_approvedby, p_approvedby, v_now
    FROM   genericsaleitems i
    INNER  JOIN genericproducts p
        ON p.genericproductid = i.genericproductid AND p.farmid = p_farmid
    WHERE  i.genericsaleid = p_genericsaleid
       AND i.itemtype = 'Product'
       AND p.trackinventory = TRUE;

    UPDATE genericproducts p
    SET    currentstock = p.currentstock - x.qty,
           updatedat    = v_now
    FROM   (SELECT i.genericproductid, SUM(i.quantity * i.unitfactor) AS qty
            FROM   genericsaleitems i
            WHERE  i.genericsaleid = p_genericsaleid AND i.farmid = p_farmid
              AND  i.itemtype = 'Product'
            GROUP  BY i.genericproductid) x
    WHERE  x.genericproductid = p.genericproductid
       AND p.trackinventory = TRUE
       AND p.farmid = p_farmid;

    -- 3. Customer side: SaleDebit for FULL TotalAmount (accrual revenue)
    IF (v_customerid IS NOT NULL AND v_totalamount > 0) THEN
        SELECT c.currentbalance INTO v_customerbalance
        FROM   genericcustomers c
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

        v_customernewbalance := v_customerbalance + v_totalamount;

        INSERT INTO genericcustomerledger (
            farmid, genericcustomerid, transactiondate, transactiontype,
            saleid, debitamount, creditamount, balanceaftertransaction,
            description, createdby
        )
        VALUES (
            p_farmid, v_customerid, v_saledate, 'SaleDebit',
            p_genericsaleid, v_totalamount, 0, v_customernewbalance,
            'Sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby
        );

        UPDATE genericcustomers c
        SET    currentbalance = v_customernewbalance, updatedat = v_now
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;
    END IF;

    -- 4. Auto-create customer payment for AmountPaid (unified payment path)
    IF (v_amountpaid > 0) THEN
        INSERT INTO genericcustomerpayments (
            farmid, genericcustomerid, paymentdate, amount, paymentmethod,
            genericcashaccountid, linkedsaleid, status, notes, createdby,
            paymentgroupid
        )
        VALUES (
            p_farmid, v_customerid, v_saledate, v_amountpaid,   -- 482: walk-in = no customer, never 0
            COALESCE(v_paymentmethod, 'Cash'), v_cashaccountid, p_genericsaleid,
            'Approved',
            'Payment on sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby, gen_random_uuid()
        )
        RETURNING genericcustomerpaymentid INTO v_paymentid;

        -- Customer ledger: PaymentCredit
        IF (v_customerid IS NOT NULL) THEN
            SELECT c.currentbalance INTO v_customerbalance
            FROM   genericcustomers c
            WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

            v_customernewbalance := v_customerbalance - v_amountpaid;

            INSERT INTO genericcustomerledger (
                farmid, genericcustomerid, transactiondate, transactiontype,
                paymentid, debitamount, creditamount, balanceaftertransaction,
                description, createdby
            )
            VALUES (
                p_farmid, v_customerid, v_saledate, 'PaymentCredit',
                v_paymentid, 0, v_amountpaid, v_customernewbalance,
                'Payment on sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
                p_approvedby
            );

            UPDATE genericcustomers c
            SET    currentbalance = v_customernewbalance, updatedat = v_now
            WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;
        END IF;

        -- Cash side: CashIn
        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, balanceaftertransaction, description,
            createdby, approvedby, approvedat
        )
        VALUES (
            p_farmid, v_cashaccountid, v_saledate, 'CashIn',
            'CustomerPayment', v_paymentid, v_amountpaid, v_cashnewbalance,
            'Payment on sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby, p_approvedby, v_now
        );

        UPDATE genericcashaccounts ca
        SET    currentbalance = v_cashnewbalance, updatedat = v_now
        WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid;
    END IF;

    -- 5. Explicit credit application (from form, with pessimistic lock above)
    IF (v_applycreditamount > 0 AND v_customerid IS NOT NULL) THEN
        SELECT c.currentbalance INTO v_customerbalance
        FROM   genericcustomers c
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

        v_customernewbalance := v_customerbalance + v_applycreditamount;

        INSERT INTO genericcustomerledger (
            farmid, genericcustomerid, transactiondate, transactiontype,
            saleid, debitamount, creditamount, balanceaftertransaction,
            description, createdby
        )
        VALUES (
            p_farmid, v_customerid, v_saledate, 'CreditApplied',
            p_genericsaleid, v_applycreditamount, 0, v_customernewbalance,
            'Credit applied to sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby
        );

        UPDATE genericcustomers c
        SET    currentbalance = v_customernewbalance, updatedat = v_now
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

        INSERT INTO genericcustomercreditapplications (
            farmid, genericcustomerid, genericsaleid, amountapplied,
            applicationdate, description, createdby
        )
        VALUES (
            p_farmid, v_customerid, p_genericsaleid, v_applycreditamount,
            v_saledate,
            'Credit applied to sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby
        );
    END IF;
END
$function$;

CREATE OR REPLACE FUNCTION public.spgenericcustomerpayment_reverse(p_farmid text, p_paymentid integer, p_reason text DEFAULT NULL::text, p_reversedby text DEFAULT NULL::text)
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

    -- 482: a walk-in payment has no customer: no customer ledger or balance to move.
    IF v_customer IS NOT NULL THEN
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
    END IF;

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

CREATE OR REPLACE FUNCTION public.spgenericcustomerpayment_getall(p_farmid text, p_status text DEFAULT NULL::text)
 RETURNS TABLE(genericcustomerpaymentid integer, farmid text, genericcustomerid integer, customername text, paymentdate timestamp without time zone, amount numeric, paymentmethod text, genericcashaccountid integer, receivedbystaffid integer, linkedsaleid integer, status text, notes text, createdby text, approvedby text, approvedat timestamp without time zone, createdat timestamp without time zone, updatedat timestamp without time zone)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT p.genericcustomerpaymentid, p.farmid::text, COALESCE(p.genericcustomerid, 0),
           COALESCE(c.customername::text, 'Walk-in customer'), p.paymentdate, p.amount, p.paymentmethod::text,
           p.genericcashaccountid, p.receivedbystaffid, p.linkedsaleid,
           p.status::text, p.notes::text, p.createdby::text, p.approvedby::text, p.approvedat,
           p.createdat, p.updatedat
    FROM   genericcustomerpayments p
    LEFT   JOIN genericcustomers c ON c.genericcustomerid = p.genericcustomerid
    WHERE  p.farmid = p_farmid
       AND (p_status IS NULL OR p.status = p_status)
    ORDER  BY p.paymentdate DESC, p.genericcustomerpaymentid DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericcustomerpayment_getbyid(p_genericcustomerpaymentid integer, p_farmid text)
 RETURNS TABLE(genericcustomerpaymentid integer, farmid text, genericcustomerid integer, customername text, paymentdate timestamp without time zone, amount numeric, paymentmethod text, genericcashaccountid integer, receivedbystaffid integer, linkedsaleid integer, status text, notes text, createdby text, approvedby text, approvedat timestamp without time zone, createdat timestamp without time zone, updatedat timestamp without time zone)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT p.genericcustomerpaymentid, p.farmid::text, COALESCE(p.genericcustomerid, 0),
           COALESCE(c.customername::text, 'Walk-in customer'), p.paymentdate, p.amount, p.paymentmethod::text,
           p.genericcashaccountid, p.receivedbystaffid, p.linkedsaleid,
           p.status::text, p.notes::text, p.createdby::text, p.approvedby::text, p.approvedat,
           p.createdat, p.updatedat
    FROM   genericcustomerpayments p
    LEFT   JOIN genericcustomers c ON c.genericcustomerid = p.genericcustomerid
    WHERE  p.genericcustomerpaymentid = p_genericcustomerpaymentid AND p.farmid = p_farmid;
END;
$function$;

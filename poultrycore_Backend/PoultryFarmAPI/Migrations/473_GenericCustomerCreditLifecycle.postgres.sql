-- =============================================================================
-- 473_GenericCustomerCreditLifecycle.postgres.sql
--
-- Three features that bring Generic customer credit management to parity with
-- the Poultry module:
--
--   Phase A — Auto-apply existing customer credit when approving a sale.
--   Phase B — Bulk payment allocation (one payment across multiple sales).
--   Phase C — Refund customer credit back as cash.
--
-- Tables created:
--   genericcustomercreditapplications  (Phase A)
--   genericcustomercreditrefunds       (Phase C)
--
-- Columns added:
--   genericcustomerpayments.paymentgroupid  (Phase B)
--
-- Functions created or replaced:
--   spgenericsale_approve              (Phase A — rewrite with credit logic)
--   spgenericcustomerpayment_bulkinsert (Phase B)
--   spgenericcustomercreditrefund_create (Phase C)
--   spgenericcustomercreditapplication_list (Phase A — read)
--   spgenericcustomercreditrefund_list  (Phase C — read)
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- =============================================================================
-- PHASE A — Credit auto-application table
-- =============================================================================

CREATE TABLE IF NOT EXISTS genericcustomercreditapplications (
    genericcustomercreditapplicationid  SERIAL PRIMARY KEY,
    farmid                              TEXT NOT NULL,
    genericcustomerid                   INTEGER NOT NULL,
    genericsaleid                       INTEGER NOT NULL,
    amountapplied                       NUMERIC(14,2) NOT NULL,
    applicationdate                     TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    description                         TEXT,
    createdby                           TEXT,
    createdat                           TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE INDEX IF NOT EXISTS ix_creditapp_farm_customer
    ON genericcustomercreditapplications (farmid, genericcustomerid);
CREATE INDEX IF NOT EXISTS ix_creditapp_farm_sale
    ON genericcustomercreditapplications (farmid, genericsaleid);

-- =============================================================================
-- PHASE B — Payment group ID on customer payments
-- =============================================================================

ALTER TABLE genericcustomerpayments ADD COLUMN IF NOT EXISTS paymentgroupid UUID NULL;
CREATE INDEX IF NOT EXISTS ix_genericcustpayments_group
    ON genericcustomerpayments (farmid, paymentgroupid);

-- Backfill: every existing payment is its own group of one.
UPDATE genericcustomerpayments
SET    paymentgroupid = gen_random_uuid()
WHERE  paymentgroupid IS NULL;

-- =============================================================================
-- PHASE C — Credit refund table
-- =============================================================================

CREATE TABLE IF NOT EXISTS genericcustomercreditrefunds (
    genericcustomercreditrefundid  SERIAL PRIMARY KEY,
    farmid                         TEXT NOT NULL,
    genericcustomerid              INTEGER NOT NULL,
    amount                         NUMERIC(14,2) NOT NULL,
    refundmethod                   VARCHAR(40) NOT NULL DEFAULT 'Cash',
    genericcashaccountid           INTEGER,
    refunddate                     TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    reason                         TEXT,
    status                         VARCHAR(20) NOT NULL DEFAULT 'Approved',
    createdby                      TEXT,
    approvedby                     TEXT,
    createdat                      TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    approvedat                     TIMESTAMP
);

CREATE INDEX IF NOT EXISTS ix_creditrefund_farm_customer
    ON genericcustomercreditrefunds (farmid, genericcustomerid);

-- =============================================================================
-- PHASE A — Rewrite spgenericsale_approve with credit auto-apply
-- =============================================================================
-- The logic is identical to the original EXCEPT:
--   After computing the customer balance side, if the customer has credit
--   (CurrentBalance < 0), we auto-reduce the sale Balance by min(|credit|, Balance),
--   create a CreditApplication row and a CustomerLedger CreditApplied entry,
--   and adjust the customer balance accordingly.
--   The sale's AmountPaid/Balance/PaymentStatus are updated to reflect the credit.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spgenericsale_approve(
    p_genericsaleid integer,
    p_farmid text,
    p_approvedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_customerid integer;
    v_cashaccountid integer;
    v_amountpaid numeric;
    v_balance numeric;
    v_saledate timestamp;
    v_receiptnumber text;
    v_cashnewbalance numeric := NULL;
    v_cashallowneg boolean;
    v_cashcurrent numeric;
    v_customernewbalance numeric;
    v_customerbalance numeric;
    v_creditavailable numeric;
    v_creditapply numeric;
    v_netbalance numeric;
    v_now timestamp := (now() at time zone 'utc');
BEGIN
    -- Idempotent
    IF EXISTS (SELECT 1 FROM genericsales s
               WHERE s.genericsaleid = p_genericsaleid AND s.farmid = p_farmid
                 AND s.status = 'Approved') THEN
        RETURN;
    END IF;

    SELECT s.status, s.genericcustomerid, s.genericcashaccountid,
           s.amountpaid, s.balance, s.saledate, s.receiptnumber
    INTO   v_status, v_customerid, v_cashaccountid,
           v_amountpaid, v_balance, v_saledate, v_receiptnumber
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
    IF (v_balance > 0 AND v_customerid IS NULL) THEN
        RAISE EXCEPTION 'Sale has an unpaid balance but no customer is attached (credit sales require a customer).';
    END IF;

    -- Stock pre-flight
    IF EXISTS (
        SELECT 1
        FROM   genericsaleitems i
        INNER  JOIN genericproducts p
            ON p.genericproductid = i.genericproductid AND p.farmid = p_farmid
        WHERE  i.genericsaleid = p_genericsaleid
           AND i.itemtype = 'Product'
           AND p.trackinventory = TRUE
           AND p.currentstock - i.quantity < 0
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
    -- PHASE A: Check for existing customer credit BEFORE the transaction
    -- =========================================================================
    v_creditapply := 0;
    IF (v_balance > 0 AND v_customerid IS NOT NULL) THEN
        SELECT c.currentbalance INTO v_customerbalance
        FROM   genericcustomers c
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

        -- Negative balance = customer has credit (they overpaid previously)
        IF v_customerbalance IS NOT NULL AND v_customerbalance < 0 THEN
            v_creditavailable := ABS(v_customerbalance);
            v_creditapply := LEAST(v_creditavailable, v_balance);
        END IF;
    END IF;

    -- =========================================================================
    -- BEGIN TRANSACTION BODY
    -- =========================================================================

    -- 1. Mark sale approved
    UPDATE genericsales s
    SET    status = 'Approved', approvedby = p_approvedby,
           approvedat = v_now, updatedat = v_now
    WHERE  s.genericsaleid = p_genericsaleid AND s.farmid = p_farmid;

    -- 2. Inventory: SaleOut movements + decrement product stock
    INSERT INTO genericstockmovements (
        farmid, genericproductid, movementdate, movementtype, quantity,
        unitcost, unitsellingprice, totalcostvalue, referencetype, referenceid,
        reason, createdby, approvedby, approvedat
    )
    SELECT p_farmid, i.genericproductid, v_saledate, 'SaleOut', -i.quantity,
           p.costprice, i.unitprice, p.costprice * i.quantity, 'Sale', p_genericsaleid,
           'Sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
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
    FROM   (SELECT i.genericproductid, SUM(i.quantity) AS qty
            FROM   genericsaleitems i
            WHERE  i.genericsaleid = p_genericsaleid AND i.farmid = p_farmid
              AND  i.itemtype = 'Product'
            GROUP  BY i.genericproductid) x
    WHERE  x.genericproductid = p.genericproductid
       AND p.trackinventory = TRUE
       AND p.farmid = p_farmid;

    -- 3. Cash side: CashIn for AmountPaid
    IF (v_amountpaid > 0) THEN
        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, balanceaftertransaction, description,
            createdby, approvedby, approvedat
        )
        VALUES (
            p_farmid, v_cashaccountid, v_saledate, 'CashIn',
            'Sale', p_genericsaleid, v_amountpaid, v_cashnewbalance,
            'Sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby, p_approvedby, v_now
        );

        UPDATE genericcashaccounts ca
        SET    currentbalance = v_cashnewbalance, updatedat = v_now
        WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid;
    END IF;

    -- 4. Customer side: SaleDebit ledger for the REMAINING balance after credit
    --    (original balance minus any credit applied).
    IF (v_customerid IS NOT NULL) THEN
        -- Get fresh customer balance for ledger entry
        SELECT c.currentbalance INTO v_customerbalance
        FROM   genericcustomers c
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

        v_netbalance := v_balance - v_creditapply;

        IF (v_netbalance > 0) THEN
            v_customernewbalance := v_customerbalance + v_netbalance;

            INSERT INTO genericcustomerledger (
                farmid, genericcustomerid, transactiondate, transactiontype,
                saleid, debitamount, creditamount, balanceaftertransaction,
                description, createdby
            )
            VALUES (
                p_farmid, v_customerid, v_saledate, 'SaleDebit',
                p_genericsaleid, v_netbalance, 0, v_customernewbalance,
                'Credit on sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
                p_approvedby
            );

            UPDATE genericcustomers c
            SET    currentbalance = v_customernewbalance, updatedat = v_now
            WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;
        END IF;

        -- =====================================================================
        -- PHASE A: Apply credit if available
        -- =====================================================================
        IF (v_creditapply > 0) THEN
            -- Re-read customer balance (may have been updated by SaleDebit above)
            SELECT c.currentbalance INTO v_customerbalance
            FROM   genericcustomers c
            WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

            v_customernewbalance := v_customerbalance + v_creditapply;

            -- Ledger entry: CreditApplied (debit because it reduces the credit)
            INSERT INTO genericcustomerledger (
                farmid, genericcustomerid, transactiondate, transactiontype,
                saleid, debitamount, creditamount, balanceaftertransaction,
                description, createdby
            )
            VALUES (
                p_farmid, v_customerid, v_saledate, 'CreditApplied',
                p_genericsaleid, v_creditapply, 0, v_customernewbalance,
                'Credit applied to sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
                p_approvedby
            );

            UPDATE genericcustomers c
            SET    currentbalance = v_customernewbalance, updatedat = v_now
            WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

            -- Record the application
            INSERT INTO genericcustomercreditapplications (
                farmid, genericcustomerid, genericsaleid, amountapplied,
                applicationdate, description, createdby
            )
            VALUES (
                p_farmid, v_customerid, p_genericsaleid, v_creditapply,
                v_saledate,
                'Auto-applied credit to sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
                p_approvedby
            );

            -- Update the sale itself to reflect the credit
            UPDATE genericsales s
            SET    amountpaid    = s.amountpaid + v_creditapply,
                   balance       = GREATEST(s.balance - v_creditapply, 0),
                   paymentstatus = CASE
                       WHEN (s.amountpaid + v_creditapply) >= s.totalamount THEN 'Paid'
                       WHEN (s.amountpaid + v_creditapply) > 0 THEN 'Partial'
                       ELSE s.paymentstatus
                   END,
                   updatedat     = v_now
            WHERE  s.genericsaleid = p_genericsaleid AND s.farmid = p_farmid;
        END IF;
    END IF;
END
$function$;

-- =============================================================================
-- PHASE A — List credit applications
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spgenericcustomercreditapplication_list(p_farmid text)
RETURNS TABLE(
    genericcustomercreditapplicationid integer,
    farmid text,
    genericcustomerid integer,
    customername text,
    genericsaleid integer,
    receiptnumber text,
    amountapplied numeric,
    applicationdate timestamp,
    description text,
    createdby text,
    createdat timestamp
)
LANGUAGE sql STABLE
AS $function$
    SELECT a.genericcustomercreditapplicationid,
           a.farmid::text,
           a.genericcustomerid,
           c.customername::text,
           a.genericsaleid,
           s.receiptnumber::text,
           a.amountapplied,
           a.applicationdate,
           a.description::text,
           a.createdby::text,
           a.createdat
    FROM   genericcustomercreditapplications a
    INNER  JOIN genericcustomers c ON c.genericcustomerid = a.genericcustomerid
    LEFT   JOIN genericsales s ON s.genericsaleid = a.genericsaleid
    WHERE  a.farmid = p_farmid
    ORDER  BY a.applicationdate DESC, a.genericcustomercreditapplicationid DESC;
$function$;

-- =============================================================================
-- PHASE B — Bulk payment insert + approve (one payment across multiple sales)
-- =============================================================================
-- Input: a JSONB array of { saleId, amount } allocations, plus the shared
-- payment header fields. All rows get the same paymentgroupid.
--
-- For each allocation:
--   1. Insert a GenericCustomerPayments row (Draft)
--   2. Immediately approve it (ledger + cash + customer balance)
--   3. Update the linked sale's AmountPaid / Balance / PaymentStatus
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spgenericcustomerpayment_bulkinsert(
    p_farmid text,
    p_genericcustomerid integer,
    p_paymentmethod text,
    p_genericcashaccountid integer DEFAULT NULL,
    p_receivedbystaffid integer DEFAULT NULL,
    p_paymentdate timestamp DEFAULT NULL,
    p_notes text DEFAULT NULL,
    p_createdby text DEFAULT NULL,
    p_allocations jsonb DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql
AS $function$
DECLARE
    v_groupid UUID := gen_random_uuid();
    v_paymentdate timestamp := COALESCE(p_paymentdate, (now() at time zone 'utc'));
    v_now timestamp := (now() at time zone 'utc');
    v_alloc record;
    v_paymentid integer;
    v_customerbalance numeric;
    v_customernewbalance numeric;
    v_cashcurrent numeric;
    v_cashnewbalance numeric;
    v_cashallowneg boolean;
    v_saletotal numeric;
    v_saleamountpaid numeric;
    v_salenewpaid numeric;
    v_salenewbalance numeric;
BEGIN
    IF p_allocations IS NULL OR jsonb_typeof(p_allocations) <> 'array' OR jsonb_array_length(p_allocations) = 0 THEN
        RAISE EXCEPTION 'Allocations must be a non-empty array.';
    END IF;

    -- Validate customer
    SELECT c.currentbalance INTO v_customerbalance
    FROM   genericcustomers c
    WHERE  c.genericcustomerid = p_genericcustomerid AND c.farmid = p_farmid;
    IF v_customerbalance IS NULL THEN
        RAISE EXCEPTION 'Customer % not found.', p_genericcustomerid;
    END IF;

    -- Validate cash account if provided
    IF p_genericcashaccountid IS NOT NULL THEN
        SELECT ca.currentbalance, ca.allownegativebalance
        INTO   v_cashcurrent, v_cashallowneg
        FROM   genericcashaccounts ca
        WHERE  ca.genericcashaccountid = p_genericcashaccountid AND ca.farmid = p_farmid;
        IF v_cashcurrent IS NULL THEN
            RAISE EXCEPTION 'Cash account not found.';
        END IF;
    END IF;

    FOR v_alloc IN
        SELECT a.saleid::integer AS saleid, a.amount::numeric AS amount
        FROM   jsonb_to_recordset(p_allocations) AS a(saleid integer, amount numeric)
    LOOP
        IF v_alloc.amount <= 0 THEN
            RAISE EXCEPTION 'Allocation amount must be greater than zero.';
        END IF;

        -- 1. Insert payment row
        INSERT INTO genericcustomerpayments (
            farmid, genericcustomerid, paymentdate, amount, paymentmethod,
            genericcashaccountid, receivedbystaffid, linkedsaleid, status,
            notes, createdby, paymentgroupid
        )
        VALUES (
            p_farmid, p_genericcustomerid, v_paymentdate, v_alloc.amount, p_paymentmethod,
            p_genericcashaccountid, p_receivedbystaffid, v_alloc.saleid, 'Draft',
            p_notes, p_createdby, v_groupid
        )
        RETURNING genericcustomerpaymentid INTO v_paymentid;

        -- 2. Approve it: mark approved
        UPDATE genericcustomerpayments p
        SET    status = 'Approved', approvedby = p_createdby,
               approvedat = v_now, updatedat = v_now
        WHERE  p.genericcustomerpaymentid = v_paymentid AND p.farmid = p_farmid;

        -- 3. Customer ledger entry
        v_customerbalance := (SELECT c.currentbalance FROM genericcustomers c
                              WHERE c.genericcustomerid = p_genericcustomerid AND c.farmid = p_farmid);
        v_customernewbalance := v_customerbalance - v_alloc.amount;

        INSERT INTO genericcustomerledger (
            farmid, genericcustomerid, transactiondate, transactiontype,
            paymentid, debitamount, creditamount, balanceaftertransaction,
            description, createdby
        )
        VALUES (
            p_farmid, p_genericcustomerid, v_paymentdate, 'PaymentCredit',
            v_paymentid, 0, v_alloc.amount, v_customernewbalance,
            COALESCE(p_notes, 'Bulk payment allocation for sale #' || v_alloc.saleid),
            p_createdby
        );

        UPDATE genericcustomers c
        SET    currentbalance = v_customernewbalance, updatedat = v_now
        WHERE  c.genericcustomerid = p_genericcustomerid AND c.farmid = p_farmid;

        -- 4. Cash side
        IF p_genericcashaccountid IS NOT NULL THEN
            v_cashcurrent := (SELECT ca.currentbalance FROM genericcashaccounts ca
                              WHERE ca.genericcashaccountid = p_genericcashaccountid AND ca.farmid = p_farmid);
            v_cashnewbalance := v_cashcurrent + v_alloc.amount;

            INSERT INTO genericcashtransactions (
                farmid, genericcashaccountid, transactiondate, transactiontype,
                sourcetype, sourceid, amount, balanceaftertransaction, description,
                createdby, approvedby, approvedat
            )
            VALUES (
                p_farmid, p_genericcashaccountid, v_paymentdate, 'CashIn',
                'CustomerPayment', v_paymentid, v_alloc.amount, v_cashnewbalance,
                COALESCE(p_notes, 'Customer payment for sale #' || v_alloc.saleid),
                p_createdby, p_createdby, v_now
            );

            UPDATE genericcashaccounts ca
            SET    currentbalance = v_cashnewbalance, updatedat = v_now
            WHERE  ca.genericcashaccountid = p_genericcashaccountid AND ca.farmid = p_farmid;
        END IF;

        -- 5. Update the linked sale
        IF v_alloc.saleid IS NOT NULL THEN
            SELECT s.totalamount, s.amountpaid
            INTO   v_saletotal, v_saleamountpaid
            FROM   genericsales s
            WHERE  s.genericsaleid = v_alloc.saleid AND s.farmid = p_farmid;

            IF v_saletotal IS NOT NULL THEN
                v_salenewpaid    := v_saleamountpaid + v_alloc.amount;
                v_salenewbalance := GREATEST(v_saletotal - v_salenewpaid, 0);

                UPDATE genericsales s
                SET    amountpaid    = v_salenewpaid,
                       balance       = v_salenewbalance,
                       paymentstatus = CASE
                           WHEN v_salenewpaid >= v_saletotal THEN 'Paid'
                           WHEN v_salenewpaid > 0 THEN 'Partial'
                           ELSE 'Unpaid'
                       END,
                       updatedat = v_now
                WHERE  s.genericsaleid = v_alloc.saleid AND s.farmid = p_farmid;
            END IF;
        END IF;
    END LOOP;

    RETURN v_groupid;
END
$function$;

-- =============================================================================
-- PHASE C — Refund customer credit as cash
-- =============================================================================
-- Pre-conditions:
--   Customer must have credit (CurrentBalance < 0)
--   Refund amount must not exceed available credit
--   Cash account must have sufficient funds (unless AllowNegativeBalance)
--
-- Effects:
--   1. GenericCustomerCreditRefunds row
--   2. GenericCustomerLedger CreditRefund entry (debit = reduces credit)
--   3. GenericCustomers.CurrentBalance += amount (less negative)
--   4. GenericCashTransactions CashOut
--   5. GenericCashAccounts.CurrentBalance -= amount
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spgenericcustomercreditrefund_create(
    p_farmid text,
    p_genericcustomerid integer,
    p_amount numeric,
    p_refundmethod text DEFAULT 'Cash',
    p_genericcashaccountid integer DEFAULT NULL,
    p_reason text DEFAULT NULL,
    p_createdby text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_now timestamp := (now() at time zone 'utc');
    v_customerbalance numeric;
    v_creditavailable numeric;
    v_customernewbalance numeric;
    v_cashcurrent numeric;
    v_cashnewbalance numeric;
    v_cashallowneg boolean;
    v_refundid integer;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Refund amount must be greater than zero.';
    END IF;

    -- Check customer credit
    SELECT c.currentbalance INTO v_customerbalance
    FROM   genericcustomers c
    WHERE  c.genericcustomerid = p_genericcustomerid AND c.farmid = p_farmid;

    IF v_customerbalance IS NULL THEN
        RAISE EXCEPTION 'Customer % not found.', p_genericcustomerid;
    END IF;

    v_creditavailable := CASE WHEN v_customerbalance < 0 THEN ABS(v_customerbalance) ELSE 0 END;

    IF p_amount > v_creditavailable THEN
        RAISE EXCEPTION 'Refund amount (%) exceeds available credit (%).', p_amount, v_creditavailable;
    END IF;

    -- Cash pre-flight
    IF p_genericcashaccountid IS NOT NULL THEN
        SELECT ca.allownegativebalance, ca.currentbalance
        INTO   v_cashallowneg, v_cashcurrent
        FROM   genericcashaccounts ca
        WHERE  ca.genericcashaccountid = p_genericcashaccountid AND ca.farmid = p_farmid;

        IF v_cashcurrent IS NULL THEN
            RAISE EXCEPTION 'Cash account not found.';
        END IF;
        v_cashnewbalance := v_cashcurrent - p_amount;
        IF (v_cashnewbalance < 0 AND v_cashallowneg = FALSE) THEN
            RAISE EXCEPTION 'Refund would push cash account negative; account does not allow it.';
        END IF;
    ELSE
        RAISE EXCEPTION 'Cash account is required for a credit refund.';
    END IF;

    v_customernewbalance := v_customerbalance + p_amount;  -- moves towards 0

    -- 1. Insert refund record
    INSERT INTO genericcustomercreditrefunds (
        farmid, genericcustomerid, amount, refundmethod,
        genericcashaccountid, refunddate, reason, status,
        createdby, approvedby, approvedat
    )
    VALUES (
        p_farmid, p_genericcustomerid, p_amount, p_refundmethod,
        p_genericcashaccountid, v_now, p_reason, 'Approved',
        p_createdby, p_createdby, v_now
    )
    RETURNING genericcustomercreditrefundid INTO v_refundid;

    -- 2. Customer ledger entry (CreditRefund — debit to reduce their credit)
    INSERT INTO genericcustomerledger (
        farmid, genericcustomerid, transactiondate, transactiontype,
        debitamount, creditamount, balanceaftertransaction,
        description, createdby
    )
    VALUES (
        p_farmid, p_genericcustomerid, v_now, 'CreditRefund',
        p_amount, 0, v_customernewbalance,
        COALESCE(p_reason, 'Credit refund #' || v_refundid),
        p_createdby
    );

    -- 3. Update customer balance
    UPDATE genericcustomers c
    SET    currentbalance = v_customernewbalance, updatedat = v_now
    WHERE  c.genericcustomerid = p_genericcustomerid AND c.farmid = p_farmid;

    -- 4. Cash out
    INSERT INTO genericcashtransactions (
        farmid, genericcashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, balanceaftertransaction, description,
        createdby, approvedby, approvedat
    )
    VALUES (
        p_farmid, p_genericcashaccountid, v_now, 'CashOut',
        'CreditRefund', v_refundid, -p_amount, v_cashnewbalance,
        COALESCE(p_reason, 'Customer credit refund #' || v_refundid),
        p_createdby, p_createdby, v_now
    );

    -- 5. Update cash account
    UPDATE genericcashaccounts ca
    SET    currentbalance = v_cashnewbalance, updatedat = v_now
    WHERE  ca.genericcashaccountid = p_genericcashaccountid AND ca.farmid = p_farmid;

    RETURN v_refundid;
END
$function$;

-- =============================================================================
-- PHASE C — List credit refunds
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spgenericcustomercreditrefund_list(p_farmid text)
RETURNS TABLE(
    genericcustomercreditrefundid integer,
    farmid text,
    genericcustomerid integer,
    customername text,
    amount numeric,
    refundmethod text,
    genericcashaccountid integer,
    accountname text,
    refunddate timestamp,
    reason text,
    status text,
    createdby text,
    approvedby text,
    createdat timestamp,
    approvedat timestamp
)
LANGUAGE sql STABLE
AS $function$
    SELECT r.genericcustomercreditrefundid,
           r.farmid::text,
           r.genericcustomerid,
           c.customername::text,
           r.amount,
           r.refundmethod::text,
           r.genericcashaccountid,
           ca.accountname::text,
           r.refunddate,
           r.reason::text,
           r.status::text,
           r.createdby::text,
           r.approvedby::text,
           r.createdat,
           r.approvedat
    FROM   genericcustomercreditrefunds r
    INNER  JOIN genericcustomers c ON c.genericcustomerid = r.genericcustomerid
    LEFT   JOIN genericcashaccounts ca ON ca.genericcashaccountid = r.genericcashaccountid
    WHERE  r.farmid = p_farmid
    ORDER  BY r.refunddate DESC, r.genericcustomercreditrefundid DESC;
$function$;

COMMIT;

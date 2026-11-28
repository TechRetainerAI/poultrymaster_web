-- =============================================================================
-- 513_Emma_GenericPurchaseExpenseSupplierPayment.postgres.sql
--
-- Bug fix: when a Generic inventory purchase is approved, it updates stock and
-- cash but does NOT create a corresponding Expense record or Supplier Payment
-- entry — unlike Poultry, which does both atomically.
--
-- Fix: extend spgenericpurchase_approve to:
--   1. Create a GenericExpense row (status=Approved) for the total purchase cost.
--   2. Create a GenericSupplierPayment row (status=Approved, LinkedPurchaseId set)
--      when AmountPaid > 0 and a supplier is attached.
--
-- This makes the Expense page and Supplier Payments page show purchase-related
-- entries automatically, matching customer expectations from the Poultry side.
--
-- Idempotent: CREATE OR REPLACE.
-- =============================================================================

BEGIN;

-- Add genericexpenseid column to link purchases back to their auto-created expense.
ALTER TABLE genericpurchases ADD COLUMN IF NOT EXISTS genericexpenseid INTEGER NULL;

CREATE OR REPLACE FUNCTION public.spgenericpurchase_approve(
    p_genericpurchaseid integer,
    p_farmid text,
    p_approvedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_supplierid integer;
    v_cashaccountid integer;
    v_amountpaid numeric;
    v_balance numeric;
    v_purchasedate timestamp;
    v_invoicenumber text;
    v_totalamount numeric;
    v_cashnewbalance numeric := NULL;
    v_cashallowneg boolean;
    v_cashcurrent numeric;
    v_suppliernewbalance numeric;
    v_expenseid integer;
    v_suppliername text;
BEGIN
    -- Idempotent: already approved → no-op.
    IF EXISTS (SELECT 1 FROM genericpurchases pu
               WHERE  pu.genericpurchaseid = p_genericpurchaseid AND pu.farmid = p_farmid
                  AND pu.status = 'Approved') THEN
        RETURN;
    END IF;

    SELECT pu.status, pu.genericsupplierid, pu.genericcashaccountid,
           pu.amountpaid, pu.balance, pu.purchasedate, pu.invoicenumber, pu.totalamount
    INTO   v_status, v_supplierid, v_cashaccountid,
           v_amountpaid, v_balance, v_purchasedate, v_invoicenumber, v_totalamount
    FROM   genericpurchases pu
    WHERE  pu.genericpurchaseid = p_genericpurchaseid AND pu.farmid = p_farmid
       AND pu.isdeleted = FALSE
    LIMIT 1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Purchase % not found.', p_genericpurchaseid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Purchase cannot be approved from status %.', v_status;
    END IF;
    IF (v_amountpaid > 0 AND v_cashaccountid IS NULL) THEN
        RAISE EXCEPTION 'AmountPaid is greater than zero but no GenericCashAccountId is set.';
    END IF;
    IF (v_balance > 0 AND v_supplierid IS NULL) THEN
        RAISE EXCEPTION 'Purchase has an unpaid balance but no supplier is attached.';
    END IF;

    -- Resolve supplier name for descriptions.
    IF v_supplierid IS NOT NULL THEN
        SELECT s.suppliername INTO v_suppliername
        FROM   genericsuppliers s
        WHERE  s.genericsupplierid = v_supplierid AND s.farmid = p_farmid;
    END IF;

    -- Cash overdraft check.
    IF (v_amountpaid > 0) THEN
        SELECT ca.allownegativebalance, ca.currentbalance
        INTO   v_cashallowneg, v_cashcurrent
        FROM   genericcashaccounts ca
        WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid
        LIMIT 1;

        IF v_cashcurrent IS NULL THEN
            RAISE EXCEPTION 'Cash account on the purchase does not exist or belongs to another farm.';
        END IF;
        v_cashnewbalance := v_cashcurrent - v_amountpaid;
        IF (v_cashnewbalance < 0 AND v_cashallowneg = FALSE) THEN
            RAISE EXCEPTION 'Purchase would push cash account negative; account does not allow it.';
        END IF;
    END IF;

    -- Mark approved.
    UPDATE genericpurchases pu
    SET    status = 'Approved', approvedby = p_approvedby,
           approvedat = (now() at time zone 'utc'), updatedat = (now() at time zone 'utc')
    WHERE  pu.genericpurchaseid = p_genericpurchaseid AND pu.farmid = p_farmid;

    -- Inventory: stock in (base units, applying unitfactor from 472).
    INSERT INTO genericstockmovements (
        farmid, genericproductid, movementdate, movementtype, quantity,
        unitcost, totalcostvalue, referencetype, referenceid,
        reason, createdby, approvedby, approvedat
    )
    SELECT p_farmid, i.genericproductid, v_purchasedate, 'PurchaseIn', i.quantity * i.unitfactor,
           i.unitcost / i.unitfactor, i.unitcost * i.quantity, 'Purchase', p_genericpurchaseid,
           'Purchase ' || COALESCE(v_invoicenumber, p_genericpurchaseid::text)
               || CASE WHEN i.purchaseunit IS NOT NULL AND i.unitfactor <> 1
                       THEN ' (' || trim(to_char(i.quantity, 'FM999999999990.###')) || ' ' || i.purchaseunit || ')'
                       ELSE '' END,
           p_approvedby, p_approvedby, (now() at time zone 'utc')
    FROM   genericpurchaseitems i
    INNER  JOIN genericproducts p
        ON p.genericproductid = i.genericproductid AND p.farmid = p_farmid
    WHERE  i.genericpurchaseid = p_genericpurchaseid
       AND p.trackinventory = TRUE;

    UPDATE genericproducts p
    SET    currentstock = p.currentstock + x.qty,
           updatedat    = (now() at time zone 'utc')
    FROM   (SELECT i.genericproductid, SUM(i.quantity * i.unitfactor) AS qty
            FROM   genericpurchaseitems i
            WHERE  i.genericpurchaseid = p_genericpurchaseid AND i.farmid = p_farmid
            GROUP  BY i.genericproductid) x
    WHERE  x.genericproductid = p.genericproductid
       AND p.trackinventory = TRUE
       AND p.farmid = p_farmid;

    -- Cash out.
    IF (v_amountpaid > 0) THEN
        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, balanceaftertransaction, description,
            createdby, approvedby, approvedat
        )
        VALUES (
            p_farmid, v_cashaccountid, v_purchasedate, 'CashOut',
            'Purchase', p_genericpurchaseid, -v_amountpaid, v_cashnewbalance,
            'Purchase ' || COALESCE(v_invoicenumber, p_genericpurchaseid::text),
            p_approvedby, p_approvedby, (now() at time zone 'utc')
        );

        UPDATE genericcashaccounts ca
        SET    currentbalance = v_cashnewbalance, updatedat = (now() at time zone 'utc')
        WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid;
    END IF;

    -- Supplier ledger (unpaid balance → supplier credit).
    IF (v_balance > 0 AND v_supplierid IS NOT NULL) THEN
        SELECT s.currentbalance + v_balance INTO v_suppliernewbalance
        FROM   genericsuppliers s
        WHERE  s.genericsupplierid = v_supplierid AND s.farmid = p_farmid
        LIMIT 1;

        INSERT INTO genericsupplierledger (
            farmid, genericsupplierid, transactiondate, transactiontype,
            purchaseid, debitamount, creditamount, balanceaftertransaction,
            description, createdby
        )
        VALUES (
            p_farmid, v_supplierid, v_purchasedate, 'PurchaseCredit',
            p_genericpurchaseid, 0, v_balance, v_suppliernewbalance,
            'Credit on purchase ' || COALESCE(v_invoicenumber, p_genericpurchaseid::text),
            p_approvedby
        );

        UPDATE genericsuppliers s
        SET    currentbalance = v_suppliernewbalance, updatedat = (now() at time zone 'utc')
        WHERE  s.genericsupplierid = v_supplierid AND s.farmid = p_farmid;
    END IF;

    -- =========================================================================
    -- 513: Create Expense record for the purchase (like Poultry does).
    -- =========================================================================
    INSERT INTO genericexpenses (
        farmid, expensedate, amount, amountpaid, balance,
        paymentmethod, paymentstatus,
        genericcashaccountid, genericsupplierid,
        description, notes, status, sourcetype, sourceid,
        createdby, approvedby, approvedat, createdat, updatedat
    )
    VALUES (
        p_farmid, v_purchasedate, COALESCE(v_totalamount, v_amountpaid + v_balance),
        v_amountpaid, v_balance,
        CASE WHEN v_amountpaid > 0 THEN 'Cash' ELSE 'Credit' END,
        CASE WHEN v_balance <= 0 THEN 'Paid'
             WHEN v_amountpaid > 0 THEN 'PartiallyPaid'
             ELSE 'Unpaid' END,
        v_cashaccountid, v_supplierid,
        'Purchase ' || COALESCE(v_invoicenumber, p_genericpurchaseid::text)
            || COALESCE(' — ' || v_suppliername, ''),
        'Auto-created from purchase approval',
        'Approved', 'Purchase', p_genericpurchaseid,
        p_approvedby, p_approvedby, (now() at time zone 'utc'),
        (now() at time zone 'utc'), (now() at time zone 'utc')
    )
    RETURNING genericexpenseid INTO v_expenseid;

    -- Link the expense back to the purchase.
    UPDATE genericpurchases pu
    SET    genericexpenseid = v_expenseid
    WHERE  pu.genericpurchaseid = p_genericpurchaseid AND pu.farmid = p_farmid;

    -- =========================================================================
    -- 513: Create Supplier Payment record when cash was paid to a supplier.
    -- =========================================================================
    IF (v_amountpaid > 0 AND v_supplierid IS NOT NULL) THEN
        INSERT INTO genericsupplierpayments (
            farmid, genericsupplierid, paymentdate, amount,
            paymentmethod, genericcashaccountid,
            referenceno, notes, status,
            linkedpurchaseid, linkedexpenseid,
            createdby, approvedby, approvedat, createdat, updatedat
        )
        VALUES (
            p_farmid, v_supplierid, v_purchasedate, v_amountpaid,
            'Cash', v_cashaccountid,
            v_invoicenumber,
            'Auto-created from purchase #' || p_genericpurchaseid::text,
            'Approved',
            p_genericpurchaseid, v_expenseid,
            p_approvedby, p_approvedby, (now() at time zone 'utc'),
            (now() at time zone 'utc'), (now() at time zone 'utc')
        );
    END IF;
END
$function$;

COMMIT;

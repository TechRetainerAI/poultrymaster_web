-- =============================================================================
-- 526_James_GenericPurchaseExpenseSourcetype.postgres.sql
--
-- Purchase-created ("mirror") expenses must carry sourcetype='Purchase' so the
-- Expenses page shows them as purchase-originated (view only -- no Reverse /
-- Edit / Delete; those belong on the Purchase). spgenericpurchase_approve
-- created the expense WITHOUT sourcetype, so some mirrors have a NULL sourcetype
-- and the page treated them as manual expenses and offered a Reverse button.
--
-- Two parts:
--   1. Back-fill existing mirror expenses (genericpurchases.genericexpenseid)
--      with sourcetype='Purchase', sourceid=<purchaseid> where it is blank.
--      Reversed/locked expenses are skipped (trg_genericexpense_reversedlock_fn).
--   2. Redefine spgenericpurchase_approve to set sourcetype/sourceid on the
--      expense it creates, so new purchases are always tagged. Body is the LIVE
--      approve (pg_get_functiondef) with ONLY sourcetype/sourceid added to the
--      expense INSERT.
--
-- Safe for the P&L / Financial Activity work (521-525): those identify purchase
-- mirrors by the purchase link (fngenericpurchase_ismirrorexpense), not by
-- sourcetype, so the totals do not move. Idempotent.
-- =============================================================================

BEGIN;

-- 1. back-fill -----------------------------------------------------------------
UPDATE genericexpenses e
SET    sourcetype = 'Purchase',
       sourceid   = pu.genericpurchaseid,
       updatedat  = (now() at time zone 'utc')
FROM   genericpurchases pu
WHERE  pu.genericexpenseid = e.genericexpenseid
  AND  pu.farmid = e.farmid
  AND  COALESCE(e.sourcetype, '') = ''
  AND  e.expensereversalid IS NULL;   -- reversed expenses are locked; leave them

-- 2. approve now tags the expense ---------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericpurchase_approve(p_genericpurchaseid integer, p_farmid text, p_approvedby text DEFAULT NULL::text)
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
    v_expensecategoryid integer;
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

    -- 517: resolve the expense category for the auto-created expense.
    SELECT c.genericexpensecategoryid INTO v_expensecategoryid
    FROM   genericexpensecategories c
    WHERE  c.farmid = p_farmid AND c.name = 'Inventory Purchases'
    LIMIT 1;
    IF v_expensecategoryid IS NULL THEN
        SELECT c.genericexpensecategoryid INTO v_expensecategoryid
        FROM   genericexpensecategories c
        WHERE  c.farmid = p_farmid
        ORDER  BY c.genericexpensecategoryid
        LIMIT 1;
    END IF;
    IF v_expensecategoryid IS NULL THEN
        INSERT INTO genericexpensecategories (farmid, name, createdat)
        VALUES (p_farmid, 'Inventory Purchases', (now() at time zone 'utc'))
        RETURNING genericexpensecategoryid INTO v_expensecategoryid;
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

    -- 517: Create Expense record with the required category.
    -- 526: tag it as a purchase mirror so the Expenses page treats it as
    -- purchase-originated (view only, no Reverse/Edit/Delete).
    INSERT INTO genericexpenses (
        farmid, expensedate, genericexpensecategoryid, amount, description, notes,
        paymentmethod, genericcashaccountid, genericsupplierid,
        sourcetype, sourceid,
        amountpaid, status,
        createdby, createdat, updatedat
    )
    VALUES (
        p_farmid, v_purchasedate, v_expensecategoryid,
        COALESCE(v_totalamount, v_amountpaid + v_balance),
        'Purchase ' || COALESCE(v_invoicenumber, p_genericpurchaseid::text)
            || COALESCE(' — ' || v_suppliername, ''),
        'From recorded purchase ' || COALESCE(v_invoicenumber, '#' || p_genericpurchaseid::text),
        CASE WHEN v_amountpaid > 0 THEN 'Cash' ELSE 'Credit' END,
        v_cashaccountid, v_supplierid,
        'Purchase', p_genericpurchaseid,
        CASE WHEN v_amountpaid > 0 THEN v_amountpaid ELSE NULL END,
        'Approved',
        p_approvedby,
        (now() at time zone 'utc'), (now() at time zone 'utc')
    )
    RETURNING genericexpenseid INTO v_expenseid;

    -- Link the expense back to the purchase.
    UPDATE genericpurchases pu
    SET    genericexpenseid = v_expenseid
    WHERE  pu.genericpurchaseid = p_genericpurchaseid AND pu.farmid = p_farmid;

    -- Create Supplier Payment record when cash was paid to a supplier.
    IF (v_amountpaid > 0 AND v_supplierid IS NOT NULL) THEN
        INSERT INTO genericsupplierpayments (
            farmid, genericsupplierid, paymentdate, amount,
            paymentmethod, genericcashaccountid,
            referenceno, notes, status,
            linkedpurchaseid, linkedexpenseid,
            createdby, createdat, updatedat
        )
        VALUES (
            p_farmid, v_supplierid, v_purchasedate, v_amountpaid,
            'Cash', v_cashaccountid,
            v_invoicenumber,
            'From recorded purchase ' || COALESCE(v_invoicenumber, '#' || p_genericpurchaseid::text),
            'Approved',
            p_genericpurchaseid, v_expenseid,
            p_approvedby,
            (now() at time zone 'utc'), (now() at time zone 'utc')
        );
    END IF;
END
$function$;

COMMIT;

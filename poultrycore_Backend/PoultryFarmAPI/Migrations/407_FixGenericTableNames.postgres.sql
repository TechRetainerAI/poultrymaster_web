-- 407: Fix table name references in Generic delivery/finance SPs.
-- The existing tables use lowercase (genericproducts, genericstockmovements, etc.)
-- but the SPs from migrations 404-406 used quoted PascalCase.

-- Also rename the new tables to match the existing lowercase convention.
ALTER TABLE IF EXISTS "GenericDeliveries" RENAME TO genericdeliveries;
ALTER TABLE IF EXISTS "GenericLoans" RENAME TO genericloans;
ALTER TABLE IF EXISTS "GenericLoanPayments" RENAME TO genericloanpayments;
ALTER TABLE IF EXISTS "GenericAssets" RENAME TO genericassets;
ALTER TABLE IF EXISTS "GenericCustomerCredits" RENAME TO genericcustomercredits;
ALTER TABLE IF EXISTS "GenericSupplierCredits" RENAME TO genericsuppliercredits;

-- =========================================================================
-- Fix delivery SPs
-- =========================================================================
CREATE OR REPLACE FUNCTION spgenericdelivery_getall(
    p_farmid TEXT,
    p_status TEXT DEFAULT NULL,
    p_fromdate DATE DEFAULT NULL,
    p_todate DATE DEFAULT NULL
)
RETURNS TABLE (
    "GenericDeliveryId"   INT,
    "FarmId"              TEXT,
    "DeliveryDate"        TIMESTAMP,
    "DriverName"          TEXT,
    "VehicleName"         TEXT,
    "Route"               TEXT,
    "GenericProductId"    INT,
    "ProductName"         TEXT,
    "QuantityLoaded"      NUMERIC,
    "Unit"                VARCHAR,
    "UnitPrice"           NUMERIC,
    "QuantitySold"        NUMERIC,
    "QuantityReturned"    NUMERIC,
    "QuantityDamaged"     NUMERIC,
    "QuantityShort"       NUMERIC,
    "CashCollected"       NUMERIC,
    "CreditSales"         NUMERIC,
    "DeliveryExpenses"    NUMERIC,
    "TotalSales"          NUMERIC,
    "Status"              VARCHAR,
    "Notes"               TEXT,
    "CreatedAt"           TIMESTAMP,
    "ReconciledAt"        TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT d.genericdeliveryid, d.farmid, d.deliverydate,
           d.drivername, d.vehiclename, d.route,
           d.genericproductid,
           COALESCE(d.productname, p.productname) AS "ProductName",
           d.quantityloaded, d.unit, d.unitprice,
           d.quantitysold, d.quantityreturned, d.quantitydamaged, d.quantityshort,
           d.cashcollected, d.creditsales, d.deliveryexpenses, d.totalsales,
           d.status, d.notes, d.createdat, d.reconciledat
    FROM genericdeliveries d
    LEFT JOIN genericproducts p ON p.genericproductid = d.genericproductid
    WHERE d.farmid = p_farmid
      AND (p_status IS NULL OR d.status = p_status)
      AND (p_fromdate IS NULL OR d.deliverydate >= p_fromdate)
      AND (p_todate IS NULL OR d.deliverydate <= p_todate + INTERVAL '1 day')
    ORDER BY d.deliverydate DESC, d.genericdeliveryid DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericdelivery_load(
    p_farmid TEXT, p_deliverydate TIMESTAMP, p_drivername TEXT,
    p_vehiclename TEXT, p_route TEXT, p_genericproductid INT,
    p_quantityloaded NUMERIC, p_unit TEXT, p_unitprice NUMERIC,
    p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT; v_productname TEXT;
BEGIN
    SELECT productname INTO v_productname FROM genericproducts
    WHERE genericproductid = p_genericproductid AND farmid = p_farmid;

    INSERT INTO genericdeliveries
        (farmid, deliverydate, drivername, vehiclename, route,
         genericproductid, productname, quantityloaded, unit, unitprice,
         status, notes, createdby, createdat)
    VALUES (p_farmid, COALESCE(p_deliverydate, NOW()), p_drivername, p_vehiclename, p_route,
            p_genericproductid, v_productname, p_quantityloaded, p_unit, p_unitprice,
            'Loaded', p_notes, p_createdby, NOW())
    RETURNING genericdeliveryid INTO v_id;

    UPDATE genericproducts
    SET currentstock = COALESCE(currentstock, 0) - p_quantityloaded, updatedat = NOW()
    WHERE genericproductid = p_genericproductid AND farmid = p_farmid;

    INSERT INTO genericstockmovements
        (farmid, genericproductid, movementdate, movementtype, quantity,
         unitcost, totalcostvalue, referencetype, referenceid, reason, createdby, createdat)
    VALUES (p_farmid, p_genericproductid, COALESCE(p_deliverydate, NOW()),
            'Delivery Load', -p_quantityloaded, p_unitprice, -(p_quantityloaded * p_unitprice),
            'GenericDelivery', v_id, 'Loaded for delivery', p_createdby, NOW());
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericdelivery_reconcile(
    p_genericdeliveryid INT, p_farmid TEXT,
    p_quantitysold NUMERIC, p_quantityreturned NUMERIC,
    p_quantitydamaged NUMERIC, p_quantityshort NUMERIC,
    p_cashcollected NUMERIC, p_creditsales NUMERIC,
    p_deliveryexpenses NUMERIC, p_reconciledby TEXT
) RETURNS VOID AS $$
DECLARE v_rec RECORD;
BEGIN
    SELECT * INTO v_rec FROM genericdeliveries
    WHERE genericdeliveryid = p_genericdeliveryid AND farmid = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
    IF v_rec.status <> 'Loaded' THEN RAISE EXCEPTION 'Only Loaded deliveries can be reconciled'; END IF;

    UPDATE genericdeliveries SET
        quantitysold = p_quantitysold, quantityreturned = p_quantityreturned,
        quantitydamaged = p_quantitydamaged, quantityshort = p_quantityshort,
        cashcollected = p_cashcollected, creditsales = p_creditsales,
        deliveryexpenses = p_deliveryexpenses,
        totalsales = p_quantitysold * v_rec.unitprice,
        status = 'Reconciled', reconciledby = p_reconciledby, reconciledat = NOW()
    WHERE genericdeliveryid = p_genericdeliveryid;

    IF p_quantityreturned > 0 THEN
        UPDATE genericproducts
        SET currentstock = COALESCE(currentstock, 0) + p_quantityreturned, updatedat = NOW()
        WHERE genericproductid = v_rec.genericproductid AND farmid = p_farmid;

        INSERT INTO genericstockmovements
            (farmid, genericproductid, movementdate, movementtype, quantity,
             referencetype, referenceid, reason, createdby, createdat)
        VALUES (p_farmid, v_rec.genericproductid, NOW(),
                'Delivery Return', p_quantityreturned,
                'GenericDelivery', p_genericdeliveryid, 'Returned from delivery', p_reconciledby, NOW());
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericdelivery_cancel(
    p_genericdeliveryid INT, p_farmid TEXT
) RETURNS VOID AS $$
DECLARE v_rec RECORD;
BEGIN
    SELECT * INTO v_rec FROM genericdeliveries
    WHERE genericdeliveryid = p_genericdeliveryid AND farmid = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
    IF v_rec.status <> 'Loaded' THEN RAISE EXCEPTION 'Only Loaded deliveries can be cancelled'; END IF;

    UPDATE genericdeliveries SET status = 'Cancelled' WHERE genericdeliveryid = p_genericdeliveryid;

    UPDATE genericproducts
    SET currentstock = COALESCE(currentstock, 0) + v_rec.quantityloaded, updatedat = NOW()
    WHERE genericproductid = v_rec.genericproductid AND farmid = p_farmid;

    INSERT INTO genericstockmovements
        (farmid, genericproductid, movementdate, movementtype, quantity,
         referencetype, referenceid, reason, createdat)
    VALUES (p_farmid, v_rec.genericproductid, NOW(),
            'Delivery Cancel', v_rec.quantityloaded,
            'GenericDelivery', p_genericdeliveryid, 'Delivery cancelled — stock restored', NOW());
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericdelivery_reverse(
    p_genericdeliveryid INT, p_farmid TEXT
) RETURNS VOID AS $$
DECLARE v_rec RECORD;
BEGIN
    SELECT * INTO v_rec FROM genericdeliveries
    WHERE genericdeliveryid = p_genericdeliveryid AND farmid = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
    IF v_rec.status <> 'Reconciled' THEN RAISE EXCEPTION 'Only Reconciled deliveries can be reversed'; END IF;

    IF v_rec.quantityreturned > 0 THEN
        UPDATE genericproducts
        SET currentstock = COALESCE(currentstock, 0) - v_rec.quantityreturned, updatedat = NOW()
        WHERE genericproductid = v_rec.genericproductid AND farmid = p_farmid;
    END IF;

    UPDATE genericdeliveries SET
        quantitysold = 0, quantityreturned = 0, quantitydamaged = 0, quantityshort = 0,
        cashcollected = 0, creditsales = 0, deliveryexpenses = 0, totalsales = 0,
        status = 'Loaded', reconciledby = NULL, reconciledat = NULL
    WHERE genericdeliveryid = p_genericdeliveryid;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- Fix loan SPs
-- =========================================================================
CREATE OR REPLACE FUNCTION spgenericloan_list(p_farmid TEXT)
RETURNS TABLE (
    "GenericLoanId" INT, "FarmId" TEXT, "LenderName" TEXT,
    "OriginalPrincipal" NUMERIC, "AmountReceived" NUMERIC,
    "InterestRate" NUMERIC, "TotalInterestPaid" NUMERIC,
    "TotalFeesPaid" NUMERIC, "TotalPrincipalPaid" NUMERIC,
    "OutstandingBalance" NUMERIC, "LoanDate" TIMESTAMP,
    "StartDate" TIMESTAMP, "DueDate" TIMESTAMP,
    "Status" VARCHAR, "Notes" TEXT, "CreatedAt" TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY SELECT l.genericloanid, l.farmid, l.lendername,
        l.originalprincipal, l.amountreceived, l.interestrate,
        l.totalinterestpaid, l.totalfeespaid, l.totalprincipalpaid,
        l.outstandingbalance, l.loandate, l.startdate, l.duedate,
        l.status, l.notes, l.createdat
    FROM genericloans l WHERE l.farmid = p_farmid ORDER BY l.loandate DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericloan_create(
    p_farmid TEXT, p_lendername TEXT, p_originalprincipal NUMERIC,
    p_amountreceived NUMERIC, p_interestrate NUMERIC,
    p_loandate TIMESTAMP, p_startdate TIMESTAMP, p_duedate TIMESTAMP,
    p_cashaccountid INT, p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO genericloans
        (farmid, lendername, originalprincipal, amountreceived, interestrate,
         outstandingbalance, loandate, startdate, duedate,
         genericcashaccountid, notes, createdby, createdat)
    VALUES (p_farmid, p_lendername, p_originalprincipal, p_amountreceived, COALESCE(p_interestrate,0),
            p_originalprincipal, COALESCE(p_loandate, NOW()), p_startdate, p_duedate,
            p_cashaccountid, p_notes, p_createdby, NOW())
    RETURNING genericloanid INTO v_id;

    IF p_cashaccountid IS NOT NULL AND p_amountreceived > 0 THEN
        UPDATE genericcashaccounts SET currentbalance = currentbalance + p_amountreceived
        WHERE genericcashaccountid = p_cashaccountid AND farmid = p_farmid;
    END IF;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericloan_repay(
    p_genericloanid INT, p_farmid TEXT,
    p_principalamount NUMERIC, p_interestamount NUMERIC, p_feeamount NUMERIC,
    p_paymentdate TIMESTAMP, p_cashaccountid INT, p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT; v_total NUMERIC;
BEGIN
    v_total := COALESCE(p_principalamount,0) + COALESCE(p_interestamount,0) + COALESCE(p_feeamount,0);
    INSERT INTO genericloanpayments
        (genericloanid, farmid, paymentdate, principalamount, interestamount,
         feeamount, totalpayment, genericcashaccountid, notes, createdby, createdat)
    VALUES (p_genericloanid, p_farmid, COALESCE(p_paymentdate, NOW()),
            COALESCE(p_principalamount,0), COALESCE(p_interestamount,0), COALESCE(p_feeamount,0),
            v_total, p_cashaccountid, p_notes, p_createdby, NOW())
    RETURNING genericloanpaymentid INTO v_id;

    UPDATE genericloans SET
        totalprincipalpaid = totalprincipalpaid + COALESCE(p_principalamount,0),
        totalinterestpaid = totalinterestpaid + COALESCE(p_interestamount,0),
        totalfeespaid = totalfeespaid + COALESCE(p_feeamount,0),
        outstandingbalance = outstandingbalance - COALESCE(p_principalamount,0)
    WHERE genericloanid = p_genericloanid AND farmid = p_farmid;

    UPDATE genericloans SET status = 'Paid'
    WHERE genericloanid = p_genericloanid AND outstandingbalance <= 0;

    IF p_cashaccountid IS NOT NULL AND v_total > 0 THEN
        UPDATE genericcashaccounts SET currentbalance = currentbalance - v_total
        WHERE genericcashaccountid = p_cashaccountid AND farmid = p_farmid;
    END IF;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericloan_payments(p_genericloanid INT, p_farmid TEXT)
RETURNS TABLE (
    "GenericLoanPaymentId" INT, "GenericLoanId" INT, "PaymentDate" TIMESTAMP,
    "PrincipalAmount" NUMERIC, "InterestAmount" NUMERIC, "FeeAmount" NUMERIC,
    "TotalPayment" NUMERIC, "Notes" TEXT, "IsReversed" BOOLEAN, "CreatedAt" TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY SELECT p.genericloanpaymentid, p.genericloanid, p.paymentdate,
        p.principalamount, p.interestamount, p.feeamount,
        p.totalpayment, p.notes, p.isreversed, p.createdat
    FROM genericloanpayments p
    WHERE p.genericloanid = p_genericloanid AND p.farmid = p_farmid AND p.isreversed = FALSE
    ORDER BY p.paymentdate DESC;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- Fix asset SPs
-- =========================================================================
CREATE OR REPLACE FUNCTION spgenericasset_list(p_farmid TEXT)
RETURNS TABLE (
    "GenericAssetId" INT, "FarmId" TEXT, "AssetName" TEXT, "Category" VARCHAR,
    "PurchaseDate" TIMESTAMP, "PurchaseCost" NUMERIC, "CurrentValue" NUMERIC,
    "TotalDepreciation" NUMERIC, "UsefulLifeMonths" INT, "DepreciationMethod" VARCHAR,
    "Status" VARCHAR, "DisposalDate" TIMESTAMP, "DisposalAmount" NUMERIC,
    "Location" TEXT, "SerialNumber" TEXT, "Notes" TEXT, "CreatedAt" TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY SELECT a.genericassetid, a.farmid, a.assetname, a.category,
        a.purchasedate, a.purchasecost, a.currentvalue, a.totaldepreciation,
        a.usefullifemonths, a.depreciationmethod, a.status,
        a.disposaldate, a.disposalamount, a.location, a.serialnumber,
        a.notes, a.createdat
    FROM genericassets a WHERE a.farmid = p_farmid ORDER BY a.purchasedate DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericasset_create(
    p_farmid TEXT, p_assetname TEXT, p_category VARCHAR, p_purchasedate TIMESTAMP,
    p_purchasecost NUMERIC, p_usefullifemonths INT, p_depreciationmethod VARCHAR,
    p_location TEXT, p_serialnumber TEXT, p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO genericassets
        (farmid, assetname, category, purchasedate, purchasecost, currentvalue,
         usefullifemonths, depreciationmethod, location, serialnumber, notes, createdby, createdat)
    VALUES (p_farmid, p_assetname, p_category, COALESCE(p_purchasedate, NOW()), p_purchasecost, p_purchasecost,
            p_usefullifemonths, COALESCE(p_depreciationmethod, 'StraightLine'),
            p_location, p_serialnumber, p_notes, p_createdby, NOW())
    RETURNING genericassetid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericasset_dispose(
    p_genericassetid INT, p_farmid TEXT, p_disposaldate TIMESTAMP, p_disposalamount NUMERIC
) RETURNS VOID AS $$
BEGIN
    UPDATE genericassets SET status = 'Disposed', disposaldate = COALESCE(p_disposaldate, NOW()),
        disposalamount = p_disposalamount
    WHERE genericassetid = p_genericassetid AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericasset_depreciate(
    p_genericassetid INT, p_farmid TEXT, p_amount NUMERIC
) RETURNS VOID AS $$
BEGIN
    UPDATE genericassets SET totaldepreciation = totaldepreciation + p_amount,
        currentvalue = GREATEST(0, currentvalue - p_amount)
    WHERE genericassetid = p_genericassetid AND farmid = p_farmid AND status = 'Active';
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- Fix credit SPs
-- =========================================================================
CREATE OR REPLACE FUNCTION spgenericcustomercredit_list(p_farmid TEXT)
RETURNS TABLE (
    "GenericCustomerCreditId" INT, "FarmId" TEXT, "GenericCustomerId" INT,
    "CustomerName" TEXT, "CreditType" VARCHAR, "Amount" NUMERIC,
    "RemainingBalance" NUMERIC, "CreditDate" TIMESTAMP,
    "ReferenceType" VARCHAR, "ReferenceId" INT, "Notes" TEXT,
    "Status" VARCHAR, "CreatedAt" TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT c.genericcustomercreditid, c.farmid, c.genericcustomerid,
        COALESCE(c.customername, cust.customername) AS "CustomerName",
        c.credittype, c.amount, c.remainingbalance, c.creditdate,
        c.referencetype, c.referenceid, c.notes, c.status, c.createdat
    FROM genericcustomercredits c
    LEFT JOIN genericcustomers cust ON cust.genericcustomerid = c.genericcustomerid
    WHERE c.farmid = p_farmid
    ORDER BY c.creditdate DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericcustomercredit_create(
    p_farmid TEXT, p_customerid INT, p_credittype VARCHAR,
    p_amount NUMERIC, p_creditdate TIMESTAMP, p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT; v_name TEXT;
BEGIN
    SELECT customername INTO v_name FROM genericcustomers
    WHERE genericcustomerid = p_customerid AND farmid = p_farmid;

    INSERT INTO genericcustomercredits
        (farmid, genericcustomerid, customername, credittype, amount,
         remainingbalance, creditdate, notes, createdby, createdat)
    VALUES (p_farmid, p_customerid, v_name, p_credittype, p_amount,
            p_amount, COALESCE(p_creditdate, NOW()), p_notes, p_createdby, NOW())
    RETURNING genericcustomercreditid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericsuppliercredit_list(p_farmid TEXT)
RETURNS TABLE (
    "GenericSupplierCreditId" INT, "FarmId" TEXT, "GenericSupplierId" INT,
    "SupplierName" TEXT, "CreditType" VARCHAR, "Amount" NUMERIC,
    "RemainingBalance" NUMERIC, "CreditDate" TIMESTAMP,
    "ReferenceType" VARCHAR, "ReferenceId" INT, "Notes" TEXT,
    "Status" VARCHAR, "CreatedAt" TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT s.genericsuppliercreditid, s.farmid, s.genericsupplierid,
        COALESCE(s.suppliername, sup.suppliername) AS "SupplierName",
        s.credittype, s.amount, s.remainingbalance, s.creditdate,
        s.referencetype, s.referenceid, s.notes, s.status, s.createdat
    FROM genericsuppliercredits s
    LEFT JOIN genericsuppliers sup ON sup.genericsupplierid = s.genericsupplierid
    WHERE s.farmid = p_farmid
    ORDER BY s.creditdate DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericsuppliercredit_create(
    p_farmid TEXT, p_supplierid INT, p_credittype VARCHAR,
    p_amount NUMERIC, p_creditdate TIMESTAMP, p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT; v_name TEXT;
BEGIN
    SELECT suppliername INTO v_name FROM genericsuppliers
    WHERE genericsupplierid = p_supplierid AND farmid = p_farmid;

    INSERT INTO genericsuppliercredits
        (farmid, genericsupplierid, suppliername, credittype, amount,
         remainingbalance, creditdate, notes, createdby, createdat)
    VALUES (p_farmid, p_supplierid, v_name, p_credittype, p_amount,
            p_amount, COALESCE(p_creditdate, NOW()), p_notes, p_createdby, NOW())
    RETURNING genericsuppliercreditid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Fix deferred cost SP
CREATE OR REPLACE FUNCTION spgenericdeferredcost_list(p_farmid TEXT)
RETURNS TABLE (
    "GenericProductId" INT, "ProductName" TEXT, "TotalPurchased" NUMERIC,
    "TotalSoldCost" NUMERIC, "DeferredBalance" NUMERIC, "CurrentStock" NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH purchase_totals AS (
        SELECT m.genericproductid, SUM(ABS(COALESCE(m.totalcostvalue, 0))) AS total
        FROM genericstockmovements m
        WHERE m.farmid = p_farmid AND m.movementtype = 'Purchase' AND m.quantity > 0
        GROUP BY m.genericproductid
    ),
    sold_cost AS (
        SELECT m.genericproductid, SUM(ABS(COALESCE(m.totalcostvalue, 0))) AS total
        FROM genericstockmovements m
        WHERE m.farmid = p_farmid AND m.movementtype = 'Sale' AND m.quantity < 0
        GROUP BY m.genericproductid
    )
    SELECT p.genericproductid, p.productname AS "ProductName",
        COALESCE(pt.total, 0) AS "TotalPurchased",
        COALESCE(sc.total, 0) AS "TotalSoldCost",
        COALESCE(pt.total, 0) - COALESCE(sc.total, 0) AS "DeferredBalance",
        COALESCE(p.currentstock, 0) AS "CurrentStock"
    FROM genericproducts p
    LEFT JOIN purchase_totals pt ON pt.genericproductid = p.genericproductid
    LEFT JOIN sold_cost sc ON sc.genericproductid = p.genericproductid
    WHERE p.farmid = p_farmid AND p.isdeleted = FALSE
        AND (COALESCE(pt.total, 0) > 0 OR COALESCE(sc.total, 0) > 0)
    ORDER BY (COALESCE(pt.total, 0) - COALESCE(sc.total, 0)) DESC;
END;
$$ LANGUAGE plpgsql;

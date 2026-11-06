-- 408: Fix column casing in SPs — the new tables have PascalCase columns
-- (created with quoted identifiers) so the SPs must use quoted names too.

-- =========================================================================
-- Delivery SPs — use quoted PascalCase columns
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
    SELECT d."GenericDeliveryId", d."FarmId", d."DeliveryDate",
           d."DriverName", d."VehicleName", d."Route",
           d."GenericProductId",
           COALESCE(d."ProductName", p.productname) AS "ProductName",
           d."QuantityLoaded", d."Unit", d."UnitPrice",
           d."QuantitySold", d."QuantityReturned", d."QuantityDamaged", d."QuantityShort",
           d."CashCollected", d."CreditSales", d."DeliveryExpenses", d."TotalSales",
           d."Status", d."Notes", d."CreatedAt", d."ReconciledAt"
    FROM genericdeliveries d
    LEFT JOIN genericproducts p ON p.genericproductid = d."GenericProductId"
    WHERE d."FarmId" = p_farmid
      AND (p_status IS NULL OR d."Status" = p_status)
      AND (p_fromdate IS NULL OR d."DeliveryDate" >= p_fromdate)
      AND (p_todate IS NULL OR d."DeliveryDate" <= p_todate + INTERVAL '1 day')
    ORDER BY d."DeliveryDate" DESC, d."GenericDeliveryId" DESC;
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
        ("FarmId","DeliveryDate","DriverName","VehicleName","Route",
         "GenericProductId","ProductName","QuantityLoaded","Unit","UnitPrice",
         "Status","Notes","CreatedBy","CreatedAt")
    VALUES (p_farmid, COALESCE(p_deliverydate, NOW()), p_drivername, p_vehiclename, p_route,
            p_genericproductid, v_productname, p_quantityloaded, p_unit, p_unitprice,
            'Loaded', p_notes, p_createdby, NOW())
    RETURNING "GenericDeliveryId" INTO v_id;

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
    WHERE "GenericDeliveryId" = p_genericdeliveryid AND "FarmId" = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
    IF v_rec."Status" <> 'Loaded' THEN RAISE EXCEPTION 'Only Loaded deliveries can be reconciled'; END IF;

    UPDATE genericdeliveries SET
        "QuantitySold" = p_quantitysold, "QuantityReturned" = p_quantityreturned,
        "QuantityDamaged" = p_quantitydamaged, "QuantityShort" = p_quantityshort,
        "CashCollected" = p_cashcollected, "CreditSales" = p_creditsales,
        "DeliveryExpenses" = p_deliveryexpenses,
        "TotalSales" = p_quantitysold * v_rec."UnitPrice",
        "Status" = 'Reconciled', "ReconciledBy" = p_reconciledby, "ReconciledAt" = NOW()
    WHERE "GenericDeliveryId" = p_genericdeliveryid;

    IF p_quantityreturned > 0 THEN
        UPDATE genericproducts
        SET currentstock = COALESCE(currentstock, 0) + p_quantityreturned, updatedat = NOW()
        WHERE genericproductid = v_rec."GenericProductId" AND farmid = p_farmid;

        INSERT INTO genericstockmovements
            (farmid, genericproductid, movementdate, movementtype, quantity,
             referencetype, referenceid, reason, createdby, createdat)
        VALUES (p_farmid, v_rec."GenericProductId", NOW(),
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
    WHERE "GenericDeliveryId" = p_genericdeliveryid AND "FarmId" = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
    IF v_rec."Status" <> 'Loaded' THEN RAISE EXCEPTION 'Only Loaded deliveries can be cancelled'; END IF;

    UPDATE genericdeliveries SET "Status" = 'Cancelled' WHERE "GenericDeliveryId" = p_genericdeliveryid;

    UPDATE genericproducts
    SET currentstock = COALESCE(currentstock, 0) + v_rec."QuantityLoaded", updatedat = NOW()
    WHERE genericproductid = v_rec."GenericProductId" AND farmid = p_farmid;

    INSERT INTO genericstockmovements
        (farmid, genericproductid, movementdate, movementtype, quantity,
         referencetype, referenceid, reason, createdat)
    VALUES (p_farmid, v_rec."GenericProductId", NOW(),
            'Delivery Cancel', v_rec."QuantityLoaded",
            'GenericDelivery', p_genericdeliveryid, 'Delivery cancelled — stock restored', NOW());
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericdelivery_reverse(
    p_genericdeliveryid INT, p_farmid TEXT
) RETURNS VOID AS $$
DECLARE v_rec RECORD;
BEGIN
    SELECT * INTO v_rec FROM genericdeliveries
    WHERE "GenericDeliveryId" = p_genericdeliveryid AND "FarmId" = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
    IF v_rec."Status" <> 'Reconciled' THEN RAISE EXCEPTION 'Only Reconciled deliveries can be reversed'; END IF;

    IF v_rec."QuantityReturned" > 0 THEN
        UPDATE genericproducts
        SET currentstock = COALESCE(currentstock, 0) - v_rec."QuantityReturned", updatedat = NOW()
        WHERE genericproductid = v_rec."GenericProductId" AND farmid = p_farmid;
    END IF;

    UPDATE genericdeliveries SET
        "QuantitySold" = 0, "QuantityReturned" = 0, "QuantityDamaged" = 0, "QuantityShort" = 0,
        "CashCollected" = 0, "CreditSales" = 0, "DeliveryExpenses" = 0, "TotalSales" = 0,
        "Status" = 'Loaded', "ReconciledBy" = NULL, "ReconciledAt" = NULL
    WHERE "GenericDeliveryId" = p_genericdeliveryid;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- Loan SPs — use quoted PascalCase for new table columns
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
    RETURN QUERY SELECT l."GenericLoanId", l."FarmId", l."LenderName",
        l."OriginalPrincipal", l."AmountReceived", l."InterestRate",
        l."TotalInterestPaid", l."TotalFeesPaid", l."TotalPrincipalPaid",
        l."OutstandingBalance", l."LoanDate", l."StartDate", l."DueDate",
        l."Status", l."Notes", l."CreatedAt"
    FROM genericloans l WHERE l."FarmId" = p_farmid ORDER BY l."LoanDate" DESC;
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
        ("FarmId","LenderName","OriginalPrincipal","AmountReceived","InterestRate",
         "OutstandingBalance","LoanDate","StartDate","DueDate",
         "GenericCashAccountId","Notes","CreatedBy","CreatedAt")
    VALUES (p_farmid, p_lendername, p_originalprincipal, p_amountreceived, COALESCE(p_interestrate,0),
            p_originalprincipal, COALESCE(p_loandate, NOW()), p_startdate, p_duedate,
            p_cashaccountid, p_notes, p_createdby, NOW())
    RETURNING "GenericLoanId" INTO v_id;

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
        ("GenericLoanId","FarmId","PaymentDate","PrincipalAmount","InterestAmount",
         "FeeAmount","TotalPayment","GenericCashAccountId","Notes","CreatedBy","CreatedAt")
    VALUES (p_genericloanid, p_farmid, COALESCE(p_paymentdate, NOW()),
            COALESCE(p_principalamount,0), COALESCE(p_interestamount,0), COALESCE(p_feeamount,0),
            v_total, p_cashaccountid, p_notes, p_createdby, NOW())
    RETURNING "GenericLoanPaymentId" INTO v_id;

    UPDATE genericloans SET
        "TotalPrincipalPaid" = "TotalPrincipalPaid" + COALESCE(p_principalamount,0),
        "TotalInterestPaid" = "TotalInterestPaid" + COALESCE(p_interestamount,0),
        "TotalFeesPaid" = "TotalFeesPaid" + COALESCE(p_feeamount,0),
        "OutstandingBalance" = "OutstandingBalance" - COALESCE(p_principalamount,0)
    WHERE "GenericLoanId" = p_genericloanid AND "FarmId" = p_farmid;

    UPDATE genericloans SET "Status" = 'Paid'
    WHERE "GenericLoanId" = p_genericloanid AND "OutstandingBalance" <= 0;

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
    RETURN QUERY SELECT p."GenericLoanPaymentId", p."GenericLoanId", p."PaymentDate",
        p."PrincipalAmount", p."InterestAmount", p."FeeAmount",
        p."TotalPayment", p."Notes", p."IsReversed", p."CreatedAt"
    FROM genericloanpayments p
    WHERE p."GenericLoanId" = p_genericloanid AND p."FarmId" = p_farmid AND p."IsReversed" = FALSE
    ORDER BY p."PaymentDate" DESC;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- Asset SPs — use quoted PascalCase for new table columns
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
    RETURN QUERY SELECT a."GenericAssetId", a."FarmId", a."AssetName", a."Category",
        a."PurchaseDate", a."PurchaseCost", a."CurrentValue", a."TotalDepreciation",
        a."UsefulLifeMonths", a."DepreciationMethod", a."Status",
        a."DisposalDate", a."DisposalAmount", a."Location", a."SerialNumber",
        a."Notes", a."CreatedAt"
    FROM genericassets a WHERE a."FarmId" = p_farmid ORDER BY a."PurchaseDate" DESC;
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
        ("FarmId","AssetName","Category","PurchaseDate","PurchaseCost","CurrentValue",
         "UsefulLifeMonths","DepreciationMethod","Location","SerialNumber","Notes","CreatedBy","CreatedAt")
    VALUES (p_farmid, p_assetname, p_category, COALESCE(p_purchasedate, NOW()), p_purchasecost, p_purchasecost,
            p_usefullifemonths, COALESCE(p_depreciationmethod, 'StraightLine'),
            p_location, p_serialnumber, p_notes, p_createdby, NOW())
    RETURNING "GenericAssetId" INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericasset_dispose(
    p_genericassetid INT, p_farmid TEXT, p_disposaldate TIMESTAMP, p_disposalamount NUMERIC
) RETURNS VOID AS $$
BEGIN
    UPDATE genericassets SET "Status" = 'Disposed', "DisposalDate" = COALESCE(p_disposaldate, NOW()),
        "DisposalAmount" = p_disposalamount
    WHERE "GenericAssetId" = p_genericassetid AND "FarmId" = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION spgenericasset_depreciate(
    p_genericassetid INT, p_farmid TEXT, p_amount NUMERIC
) RETURNS VOID AS $$
BEGIN
    UPDATE genericassets SET "TotalDepreciation" = "TotalDepreciation" + p_amount,
        "CurrentValue" = GREATEST(0, "CurrentValue" - p_amount)
    WHERE "GenericAssetId" = p_genericassetid AND "FarmId" = p_farmid AND "Status" = 'Active';
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- Credit SPs — use quoted PascalCase for new table columns
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
    SELECT c."GenericCustomerCreditId", c."FarmId", c."GenericCustomerId",
        COALESCE(c."CustomerName", cust.customername) AS "CustomerName",
        c."CreditType", c."Amount", c."RemainingBalance", c."CreditDate",
        c."ReferenceType", c."ReferenceId", c."Notes", c."Status", c."CreatedAt"
    FROM genericcustomercredits c
    LEFT JOIN genericcustomers cust ON cust.genericcustomerid = c."GenericCustomerId"
    WHERE c."FarmId" = p_farmid
    ORDER BY c."CreditDate" DESC;
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
        ("FarmId","GenericCustomerId","CustomerName","CreditType","Amount",
         "RemainingBalance","CreditDate","Notes","CreatedBy","CreatedAt")
    VALUES (p_farmid, p_customerid, v_name, p_credittype, p_amount,
            p_amount, COALESCE(p_creditdate, NOW()), p_notes, p_createdby, NOW())
    RETURNING "GenericCustomerCreditId" INTO v_id;
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
    SELECT s."GenericSupplierCreditId", s."FarmId", s."GenericSupplierId",
        COALESCE(s."SupplierName", sup.suppliername) AS "SupplierName",
        s."CreditType", s."Amount", s."RemainingBalance", s."CreditDate",
        s."ReferenceType", s."ReferenceId", s."Notes", s."Status", s."CreatedAt"
    FROM genericsuppliercredits s
    LEFT JOIN genericsuppliers sup ON sup.genericsupplierid = s."GenericSupplierId"
    WHERE s."FarmId" = p_farmid
    ORDER BY s."CreditDate" DESC;
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
        ("FarmId","GenericSupplierId","SupplierName","CreditType","Amount",
         "RemainingBalance","CreditDate","Notes","CreatedBy","CreatedAt")
    VALUES (p_farmid, p_supplierid, v_name, p_credittype, p_amount,
            p_amount, COALESCE(p_creditdate, NOW()), p_notes, p_createdby, NOW())
    RETURNING "GenericSupplierCreditId" INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

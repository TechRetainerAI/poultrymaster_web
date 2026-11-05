-- 406: Generic Customer Credits and Supplier Credits.
-- Customer credits: advances, overpayments and credit notes from customers.
-- Supplier credits: advance payments and credit notes from suppliers.

-- =========================================================================
-- Customer Credits
-- =========================================================================
CREATE TABLE IF NOT EXISTS "GenericCustomerCredits" (
    "GenericCustomerCreditId" SERIAL PRIMARY KEY,
    "FarmId"                  TEXT NOT NULL,
    "GenericCustomerId"       INT NOT NULL,
    "CustomerName"            TEXT,
    "CreditType"              VARCHAR(30) NOT NULL DEFAULT 'Overpayment',
    "Amount"                  NUMERIC(18,4) NOT NULL,
    "RemainingBalance"        NUMERIC(18,4) NOT NULL,
    "CreditDate"              TIMESTAMP NOT NULL DEFAULT NOW(),
    "ReferenceType"           VARCHAR(60),
    "ReferenceId"             INT,
    "Notes"                   TEXT,
    "Status"                  VARCHAR(20) NOT NULL DEFAULT 'Active',
    "CreatedBy"               TEXT,
    "CreatedAt"               TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "IX_GenericCustomerCredits_FarmId" ON "GenericCustomerCredits" ("FarmId");

-- SP: List customer credits
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
        COALESCE(c."CustomerName", cust."Name") AS "CustomerName",
        c."CreditType", c."Amount", c."RemainingBalance", c."CreditDate",
        c."ReferenceType", c."ReferenceId", c."Notes", c."Status", c."CreatedAt"
    FROM "GenericCustomerCredits" c
    LEFT JOIN "GenericCustomers" cust ON cust."GenericCustomerId" = c."GenericCustomerId"
    WHERE c."FarmId" = p_farmid
    ORDER BY c."CreditDate" DESC;
END;
$$ LANGUAGE plpgsql;

-- SP: Create customer credit
CREATE OR REPLACE FUNCTION spgenericcustomercredit_create(
    p_farmid TEXT, p_customerid INT, p_credittype VARCHAR,
    p_amount NUMERIC, p_creditdate TIMESTAMP, p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT; v_name TEXT;
BEGIN
    SELECT "Name" INTO v_name FROM "GenericCustomers"
    WHERE "GenericCustomerId" = p_customerid AND "FarmId" = p_farmid;

    INSERT INTO "GenericCustomerCredits"
        ("FarmId","GenericCustomerId","CustomerName","CreditType","Amount",
         "RemainingBalance","CreditDate","Notes","CreatedBy","CreatedAt")
    VALUES (p_farmid, p_customerid, v_name, p_credittype, p_amount,
            p_amount, COALESCE(p_creditdate, NOW()), p_notes, p_createdby, NOW())
    RETURNING "GenericCustomerCreditId" INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- Supplier Credits
-- =========================================================================
CREATE TABLE IF NOT EXISTS "GenericSupplierCredits" (
    "GenericSupplierCreditId" SERIAL PRIMARY KEY,
    "FarmId"                  TEXT NOT NULL,
    "GenericSupplierId"       INT NOT NULL,
    "SupplierName"            TEXT,
    "CreditType"              VARCHAR(30) NOT NULL DEFAULT 'Advance',
    "Amount"                  NUMERIC(18,4) NOT NULL,
    "RemainingBalance"        NUMERIC(18,4) NOT NULL,
    "CreditDate"              TIMESTAMP NOT NULL DEFAULT NOW(),
    "ReferenceType"           VARCHAR(60),
    "ReferenceId"             INT,
    "Notes"                   TEXT,
    "Status"                  VARCHAR(20) NOT NULL DEFAULT 'Active',
    "CreatedBy"               TEXT,
    "CreatedAt"               TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "IX_GenericSupplierCredits_FarmId" ON "GenericSupplierCredits" ("FarmId");

-- SP: List supplier credits
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
        COALESCE(s."SupplierName", sup."Name") AS "SupplierName",
        s."CreditType", s."Amount", s."RemainingBalance", s."CreditDate",
        s."ReferenceType", s."ReferenceId", s."Notes", s."Status", s."CreatedAt"
    FROM "GenericSupplierCredits" s
    LEFT JOIN "GenericSuppliers" sup ON sup."GenericSupplierId" = s."GenericSupplierId"
    WHERE s."FarmId" = p_farmid
    ORDER BY s."CreditDate" DESC;
END;
$$ LANGUAGE plpgsql;

-- SP: Create supplier credit
CREATE OR REPLACE FUNCTION spgenericsuppliercredit_create(
    p_farmid TEXT, p_supplierid INT, p_credittype VARCHAR,
    p_amount NUMERIC, p_creditdate TIMESTAMP, p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT; v_name TEXT;
BEGIN
    SELECT "Name" INTO v_name FROM "GenericSuppliers"
    WHERE "GenericSupplierId" = p_supplierid AND "FarmId" = p_farmid;

    INSERT INTO "GenericSupplierCredits"
        ("FarmId","GenericSupplierId","SupplierName","CreditType","Amount",
         "RemainingBalance","CreditDate","Notes","CreatedBy","CreatedAt")
    VALUES (p_farmid, p_supplierid, v_name, p_credittype, p_amount,
            p_amount, COALESCE(p_creditdate, NOW()), p_notes, p_createdby, NOW())
    RETURNING "GenericSupplierCreditId" INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- Deferred Inventory Cost — a read-only view built from existing tables.
-- For each product, sum purchases minus sold cost = deferred balance.
-- =========================================================================
CREATE OR REPLACE FUNCTION spgenericdeferredcost_list(p_farmid TEXT)
RETURNS TABLE (
    "GenericProductId" INT, "ProductName" TEXT, "TotalPurchased" NUMERIC,
    "TotalSoldCost" NUMERIC, "DeferredBalance" NUMERIC, "CurrentStock" NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH purchase_totals AS (
        SELECT m."GenericProductId", SUM(ABS(COALESCE(m."TotalCostValue", 0))) AS total
        FROM "GenericStockMovements" m
        WHERE m."FarmId" = p_farmid AND m."MovementType" = 'Purchase' AND m."Quantity" > 0
        GROUP BY m."GenericProductId"
    ),
    sold_cost AS (
        SELECT m."GenericProductId", SUM(ABS(COALESCE(m."TotalCostValue", 0))) AS total
        FROM "GenericStockMovements" m
        WHERE m."FarmId" = p_farmid AND m."MovementType" = 'Sale' AND m."Quantity" < 0
        GROUP BY m."GenericProductId"
    )
    SELECT p."GenericProductId", p."Name" AS "ProductName",
        COALESCE(pt.total, 0) AS "TotalPurchased",
        COALESCE(sc.total, 0) AS "TotalSoldCost",
        COALESCE(pt.total, 0) - COALESCE(sc.total, 0) AS "DeferredBalance",
        COALESCE(p."CurrentStock", 0) AS "CurrentStock"
    FROM "GenericProducts" p
    LEFT JOIN purchase_totals pt ON pt."GenericProductId" = p."GenericProductId"
    LEFT JOIN sold_cost sc ON sc."GenericProductId" = p."GenericProductId"
    WHERE p."FarmId" = p_farmid AND p."IsDeleted" = FALSE
        AND (COALESCE(pt.total, 0) > 0 OR COALESCE(sc.total, 0) > 0)
    ORDER BY (COALESCE(pt.total, 0) - COALESCE(sc.total, 0)) DESC;
END;
$$ LANGUAGE plpgsql;

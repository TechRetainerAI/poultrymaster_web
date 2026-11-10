-- 405: Generic finance modules — Customer Credits, Supplier Credits,
-- Loans, Capital Assets, and Deferred Inventory Cost.
-- Mirrors the poultry equivalents for generic companies.

-- =========================================================================
-- 1. Generic Loans
-- =========================================================================
CREATE TABLE IF NOT EXISTS "GenericLoans" (
    "GenericLoanId"         SERIAL PRIMARY KEY,
    "FarmId"                TEXT NOT NULL,
    "LenderName"            TEXT NOT NULL,
    "OriginalPrincipal"     NUMERIC(18,4) NOT NULL,
    "AmountReceived"        NUMERIC(18,4) NOT NULL DEFAULT 0,
    "InterestRate"          NUMERIC(8,4) DEFAULT 0,
    "TotalInterestPaid"     NUMERIC(18,4) NOT NULL DEFAULT 0,
    "TotalFeesPaid"         NUMERIC(18,4) NOT NULL DEFAULT 0,
    "TotalPrincipalPaid"    NUMERIC(18,4) NOT NULL DEFAULT 0,
    "OutstandingBalance"    NUMERIC(18,4) NOT NULL DEFAULT 0,
    "LoanDate"              TIMESTAMP NOT NULL DEFAULT NOW(),
    "StartDate"             TIMESTAMP,
    "DueDate"               TIMESTAMP,
    "Status"                VARCHAR(20) NOT NULL DEFAULT 'Active',
    "GenericCashAccountId"  INT,
    "Notes"                 TEXT,
    "CreatedBy"             TEXT,
    "CreatedAt"             TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "IX_GenericLoans_FarmId" ON "GenericLoans" ("FarmId");

CREATE TABLE IF NOT EXISTS "GenericLoanPayments" (
    "GenericLoanPaymentId"  SERIAL PRIMARY KEY,
    "GenericLoanId"         INT NOT NULL REFERENCES "GenericLoans"("GenericLoanId"),
    "FarmId"                TEXT NOT NULL,
    "PaymentDate"           TIMESTAMP NOT NULL DEFAULT NOW(),
    "PrincipalAmount"       NUMERIC(18,4) NOT NULL DEFAULT 0,
    "InterestAmount"        NUMERIC(18,4) NOT NULL DEFAULT 0,
    "FeeAmount"             NUMERIC(18,4) NOT NULL DEFAULT 0,
    "TotalPayment"          NUMERIC(18,4) NOT NULL DEFAULT 0,
    "GenericCashAccountId"  INT,
    "Notes"                 TEXT,
    "IsReversed"            BOOLEAN NOT NULL DEFAULT FALSE,
    "CreatedBy"             TEXT,
    "CreatedAt"             TIMESTAMP NOT NULL DEFAULT NOW()
);

-- SP: List loans
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
    FROM "GenericLoans" l WHERE l."FarmId" = p_farmid ORDER BY l."LoanDate" DESC;
END;
$$ LANGUAGE plpgsql;

-- SP: Create loan
CREATE OR REPLACE FUNCTION spgenericloan_create(
    p_farmid TEXT, p_lendername TEXT, p_originalprincipal NUMERIC,
    p_amountreceived NUMERIC, p_interestrate NUMERIC,
    p_loandate TIMESTAMP, p_startdate TIMESTAMP, p_duedate TIMESTAMP,
    p_cashaccountid INT, p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO "GenericLoans"
        ("FarmId","LenderName","OriginalPrincipal","AmountReceived","InterestRate",
         "OutstandingBalance","LoanDate","StartDate","DueDate",
         "GenericCashAccountId","Notes","CreatedBy","CreatedAt")
    VALUES (p_farmid, p_lendername, p_originalprincipal, p_amountreceived, COALESCE(p_interestrate,0),
            p_originalprincipal, COALESCE(p_loandate, NOW()), p_startdate, p_duedate,
            p_cashaccountid, p_notes, p_createdby, NOW())
    RETURNING "GenericLoanId" INTO v_id;

    IF p_cashaccountid IS NOT NULL AND p_amountreceived > 0 THEN
        UPDATE "GenericCashAccounts" SET "CurrentBalance" = "CurrentBalance" + p_amountreceived
        WHERE "GenericCashAccountId" = p_cashaccountid AND "FarmId" = p_farmid;
    END IF;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- SP: Record loan repayment
CREATE OR REPLACE FUNCTION spgenericloan_repay(
    p_genericloanid INT, p_farmid TEXT,
    p_principalamount NUMERIC, p_interestamount NUMERIC, p_feeamount NUMERIC,
    p_paymentdate TIMESTAMP, p_cashaccountid INT, p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT; v_total NUMERIC;
BEGIN
    v_total := COALESCE(p_principalamount,0) + COALESCE(p_interestamount,0) + COALESCE(p_feeamount,0);

    INSERT INTO "GenericLoanPayments"
        ("GenericLoanId","FarmId","PaymentDate","PrincipalAmount","InterestAmount",
         "FeeAmount","TotalPayment","GenericCashAccountId","Notes","CreatedBy","CreatedAt")
    VALUES (p_genericloanid, p_farmid, COALESCE(p_paymentdate, NOW()),
            COALESCE(p_principalamount,0), COALESCE(p_interestamount,0), COALESCE(p_feeamount,0),
            v_total, p_cashaccountid, p_notes, p_createdby, NOW())
    RETURNING "GenericLoanPaymentId" INTO v_id;

    UPDATE "GenericLoans" SET
        "TotalPrincipalPaid" = "TotalPrincipalPaid" + COALESCE(p_principalamount,0),
        "TotalInterestPaid" = "TotalInterestPaid" + COALESCE(p_interestamount,0),
        "TotalFeesPaid" = "TotalFeesPaid" + COALESCE(p_feeamount,0),
        "OutstandingBalance" = "OutstandingBalance" - COALESCE(p_principalamount,0)
    WHERE "GenericLoanId" = p_genericloanid AND "FarmId" = p_farmid;

    -- Mark as Paid if balance is zero
    UPDATE "GenericLoans" SET "Status" = 'Paid'
    WHERE "GenericLoanId" = p_genericloanid AND "OutstandingBalance" <= 0;

    IF p_cashaccountid IS NOT NULL AND v_total > 0 THEN
        UPDATE "GenericCashAccounts" SET "CurrentBalance" = "CurrentBalance" - v_total
        WHERE "GenericCashAccountId" = p_cashaccountid AND "FarmId" = p_farmid;
    END IF;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- SP: List loan payments
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
    FROM "GenericLoanPayments" p
    WHERE p."GenericLoanId" = p_genericloanid AND p."FarmId" = p_farmid AND p."IsReversed" = FALSE
    ORDER BY p."PaymentDate" DESC;
END;
$$ LANGUAGE plpgsql;

-- =========================================================================
-- 2. Generic Assets (Capital Investments)
-- =========================================================================
CREATE TABLE IF NOT EXISTS "GenericAssets" (
    "GenericAssetId"        SERIAL PRIMARY KEY,
    "FarmId"                TEXT NOT NULL,
    "AssetName"             TEXT NOT NULL,
    "Category"              VARCHAR(60),
    "PurchaseDate"          TIMESTAMP NOT NULL DEFAULT NOW(),
    "PurchaseCost"          NUMERIC(18,4) NOT NULL DEFAULT 0,
    "CurrentValue"          NUMERIC(18,4) NOT NULL DEFAULT 0,
    "TotalDepreciation"     NUMERIC(18,4) NOT NULL DEFAULT 0,
    "UsefulLifeMonths"      INT,
    "DepreciationMethod"    VARCHAR(30) DEFAULT 'StraightLine',
    "Status"                VARCHAR(20) NOT NULL DEFAULT 'Active',
    "DisposalDate"          TIMESTAMP,
    "DisposalAmount"        NUMERIC(18,4),
    "Location"              TEXT,
    "SerialNumber"          TEXT,
    "Notes"                 TEXT,
    "CreatedBy"             TEXT,
    "CreatedAt"             TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "IX_GenericAssets_FarmId" ON "GenericAssets" ("FarmId");

-- SP: List assets
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
    FROM "GenericAssets" a WHERE a."FarmId" = p_farmid ORDER BY a."PurchaseDate" DESC;
END;
$$ LANGUAGE plpgsql;

-- SP: Create asset
CREATE OR REPLACE FUNCTION spgenericasset_create(
    p_farmid TEXT, p_assetname TEXT, p_category VARCHAR, p_purchasedate TIMESTAMP,
    p_purchasecost NUMERIC, p_usefullifemonths INT, p_depreciationmethod VARCHAR,
    p_location TEXT, p_serialnumber TEXT, p_notes TEXT, p_createdby TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO "GenericAssets"
        ("FarmId","AssetName","Category","PurchaseDate","PurchaseCost","CurrentValue",
         "UsefulLifeMonths","DepreciationMethod","Location","SerialNumber","Notes","CreatedBy","CreatedAt")
    VALUES (p_farmid, p_assetname, p_category, COALESCE(p_purchasedate, NOW()), p_purchasecost, p_purchasecost,
            p_usefullifemonths, COALESCE(p_depreciationmethod, 'StraightLine'),
            p_location, p_serialnumber, p_notes, p_createdby, NOW())
    RETURNING "GenericAssetId" INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- SP: Dispose asset
CREATE OR REPLACE FUNCTION spgenericasset_dispose(
    p_genericassetid INT, p_farmid TEXT, p_disposaldate TIMESTAMP, p_disposalamount NUMERIC
) RETURNS VOID AS $$
BEGIN
    UPDATE "GenericAssets" SET
        "Status" = 'Disposed', "DisposalDate" = COALESCE(p_disposaldate, NOW()),
        "DisposalAmount" = p_disposalamount
    WHERE "GenericAssetId" = p_genericassetid AND "FarmId" = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- SP: Record depreciation
CREATE OR REPLACE FUNCTION spgenericasset_depreciate(
    p_genericassetid INT, p_farmid TEXT, p_amount NUMERIC
) RETURNS VOID AS $$
BEGIN
    UPDATE "GenericAssets" SET
        "TotalDepreciation" = "TotalDepreciation" + p_amount,
        "CurrentValue" = GREATEST(0, "CurrentValue" - p_amount)
    WHERE "GenericAssetId" = p_genericassetid AND "FarmId" = p_farmid AND "Status" = 'Active';
END;
$$ LANGUAGE plpgsql;

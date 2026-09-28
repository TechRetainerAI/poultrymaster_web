-- =============================================================================
-- 328_RestaurantCapitalAssets.postgres.sql
--
-- Purpose
-- -------
-- Capital Investments/Assets for the standalone Restaurant module: a combi oven,
-- a walk-in cold room, a delivery motorbike or a dining-room refit is not this
-- month's expense -- it is money the restaurant still owns.
--
-- This is the Poultry Asset Register (migrations 270, 271, 272's depreciation
-- line and 313's cost composition) copied rule for rule, adapted to the
-- Restaurant money model from 323:
--
--   * Buying an asset moves the amount PAID NOW out of a chosen cash account
--     through fnrestaurant_post (one ledger row, unique (sourcetype, sourceid),
--     overdraft rule, closed-day lock, no future dates). Source type
--     'AssetPurchase', sourceid = the cost row. It is NOT an expense and never
--     reaches Profit & Loss.
--   * Anything not paid now is OWED: it stays on the cost row as
--     amount - amountpaid, against the supplier named on it.
--     sprestaurant_capitalasset_payables lists every open one, so the Supplier
--     Balances feature (not built yet in Restaurant) can UNION it in as
--     documents of type 'AssetCost' keyed by assetcostid. When supplier payments
--     arrive, they must (a) allocate against that key and (b) add a guard to
--     sprestaurant_capitalasset_reverse / _cost_reverse / _correctoriginalcost,
--     exactly as Poultry 270/313 refuse once a supplier payment exists.
--   * Depreciation is straight line, a whole month at a time from the month the
--     asset goes into service, charged on demand ("N due"). Each charge is a
--     NON-CASH cost: a row in restaurantassetdepreciation and a "Depreciation"
--     line in the P&L's Depreciation & Financing section (section key 'Other').
--     No ledger row, no cash account, no supplier.
--   * Disposal proceeds are money IN ('AssetDisposal'), never revenue. As in
--     Poultry, gain or loss on disposal is NOT computed -- a known limitation of
--     the reference, copied rather than guessed at.
--   * Reversal (whole asset, or one added cost) is append-only: the rows are
--     kept and marked Reversed with a reason, and the cash paid comes back
--     through a new ledger row dated today ('AssetPurchaseReversal').
--
-- WHY NOT THE EXPENSE RAIL, AS POULTRY DOES
-- Poultry capitalises by writing an `expense` row stamped CapitalAsset, because
-- its P&L can exclude a classified expense. restaurantexpenses has no such
-- classification and every one of its rows is profit (323's P&L sums them by
-- category); it is also read with SELECT x.* elsewhere, so no column was added
-- to it. The asset's own cost rows are therefore the document here, and the
-- ledger row points at them. The effect is the one Poultry has: cash moves,
-- profit does not.
--
-- CASH FLOW: Poultry has no Investing group -- a capital purchase is an
-- Operating money-out there. The restaurant cash flow reads the ledger, and the
-- new source types fall into its Operating arm the same way; only their
-- category labels are added (sprestaurantcashflow_detail).
--
-- PROFIT vs CASH: two new lines keep "Unexplained" at 0 -- depreciation is
-- profit without cash; purchases and disposal proceeds are cash without profit.
--
-- Re-emits (from 326, every earlier arm kept): sprestaurantcashflow_detail,
-- sprestaurant_report_pnl_lines, sprestaurant_report_pnl_expenses,
-- sprestaurant_report_cash_profit_bridge. Re-running 323/324/326 alone undoes
-- these; re-run 328 after them. Same signatures and result columns, so CREATE
-- OR REPLACE is enough for those four.
--
-- Column additions to existing tables: NONE. Re-runnable: tables are IF NOT
-- EXISTS and every new function is dropped by name (all overloads) first.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Drop every NEW function this migration defines, all overloads.
-- -----------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
            'fnrestaurantasset_totalcost', 'fnrestaurantasset_acquisitioncost', 'fnrestaurantasset_additionalcost',
            'fnrestaurantasset_accumulated', 'fnrestaurantasset_monthly', 'fnrestaurantasset_financials',
            'fnrestaurantasset_refreshstatus', 'fnrestaurantasset_postcost',
            'sprestaurant_assetcategory_ensuredefaults', 'sprestaurant_assetcategory_list',
            'sprestaurant_assetcategory_upsert',
            'sprestaurant_capitalasset_create', 'sprestaurant_capitalasset_update',
            'sprestaurant_capitalasset_addcost', 'sprestaurant_capitalasset_correctoriginalcost',
            'sprestaurant_capitalasset_cost_reverse', 'sprestaurant_capitalasset_dispose',
            'sprestaurant_capitalasset_reverse', 'sprestaurant_capitalasset_list',
            'sprestaurant_capitalasset_costs', 'sprestaurant_capitalasset_summary',
            'sprestaurant_capitalasset_payables',
            'fnrestaurant_assetdepreciation_post', 'sprestaurant_assetdepreciation_generate',
            'sprestaurant_assetdepreciation_reverse', 'sprestaurant_assetdepreciation_adjust',
            'sprestaurant_assetdepreciation_list', 'sprestaurant_assetdepreciation_due')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------

-- Per restaurant, seeded on first read, editable (Poultry 270 §1).
CREATE TABLE IF NOT EXISTS restaurantassetcategories (
    assetcategoryid         SERIAL PRIMARY KEY,
    farmid                  TEXT NOT NULL,
    categoryname            TEXT NOT NULL,
    -- A suggestion the form fills in, never a rule.
    defaultusefullifemonths INT,
    sortorder               INT NOT NULL DEFAULT 0,
    isactive                BOOLEAN NOT NULL DEFAULT TRUE,
    createdby               TEXT,
    createdat               TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantassetcategories_name
    ON restaurantassetcategories (farmid, lower(categoryname));

-- The asset. No cost, accumulated depreciation or book value columns: all three
-- are sums (Poultry 270 §2).
CREATE TABLE IF NOT EXISTS restaurantcapitalassets (
    capitalassetid     SERIAL PRIMARY KEY,
    farmid             TEXT NOT NULL,
    assetnumber        TEXT NOT NULL,
    assetname          TEXT NOT NULL,
    assetcategoryid    INT REFERENCES restaurantassetcategories(assetcategoryid),
    description        TEXT,
    acquisitiondate    DATE NOT NULL,
    -- Depreciation starts in this month, not at acquisition.
    inservicedate      DATE,
    residualvalue      NUMERIC(14,2) NOT NULL DEFAULT 0,
    usefullifemonths   INT,
    depreciationmethod TEXT NOT NULL DEFAULT 'StraightLine',
    supplierid         INT REFERENCES restaurantsuppliers(restaurantsupplierid),
    suppliername       TEXT,
    location           TEXT,
    serialnumber       TEXT,
    status             TEXT NOT NULL DEFAULT 'Draft',
    disposaldate       DATE,
    disposalproceeds   NUMERIC(14,2),
    disposalaccountid  INT REFERENCES restaurantcashaccounts(cashaccountid),
    disposalnotes      TEXT,
    notes              TEXT,
    createdby          TEXT,
    createdat          TIMESTAMP NOT NULL DEFAULT NOW(),
    updatedby          TEXT,
    updatedat          TIMESTAMP,
    reversedby         TEXT,
    reversedat         TIMESTAMP,
    reversalreason     TEXT,
    CONSTRAINT ck_restaurantcapitalassets_status CHECK (status IN
        ('Draft', 'Active', 'FullyDepreciated', 'Disposed', 'Reversed')),
    CONSTRAINT ck_restaurantcapitalassets_residual CHECK (residualvalue >= 0),
    CONSTRAINT ck_restaurantcapitalassets_life CHECK (usefullifemonths IS NULL OR usefullifemonths > 0)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantcapitalassets_number
    ON restaurantcapitalassets (farmid, assetnumber);
CREATE INDEX IF NOT EXISTS ix_restaurantcapitalassets_farm
    ON restaurantcapitalassets (farmid, status);

-- Every amount capitalised into an asset, and how it was paid. This row IS the
-- purchase document: the ledger row points at it ('AssetPurchase', assetcostid)
-- and any unpaid part (amount - amountpaid) is owed to its supplier.
CREATE TABLE IF NOT EXISTS restaurantcapitalassetcosts (
    assetcostid     SERIAL PRIMARY KEY,
    farmid          TEXT NOT NULL,
    capitalassetid  INT NOT NULL REFERENCES restaurantcapitalassets(capitalassetid),
    costdate        DATE NOT NULL,
    description     TEXT,
    costcategory    TEXT,
    -- SIGNED only on an OriginalCostCorrection (313's rule).
    amount          NUMERIC(14,2) NOT NULL,
    -- Acquisition | AdditionalCost | OriginalCostCorrection.
    sourcetype      TEXT NOT NULL DEFAULT 'Acquisition',
    -- A correction points at the acquisition it corrects: they are one document.
    correctionofid  INT REFERENCES restaurantcapitalassetcosts(assetcostid),
    paymentmethod   TEXT,
    -- Cash that left when this row was posted. On a correction it is <= 0: the
    -- part of the original payment handed back because the cost was lower.
    amountpaid      NUMERIC(14,2) NOT NULL DEFAULT 0,
    cashaccountid   INT REFERENCES restaurantcashaccounts(cashaccountid),
    duedate         DATE,
    supplierid      INT REFERENCES restaurantsuppliers(restaurantsupplierid),
    suppliername    TEXT,
    status          TEXT NOT NULL DEFAULT 'Posted',
    createdby       TEXT,
    createdat       TIMESTAMP NOT NULL DEFAULT NOW(),
    reversedby      TEXT,
    reversedat      TIMESTAMP,
    reversalreason  TEXT,
    CONSTRAINT ck_restaurantcapitalassetcosts_source CHECK (sourcetype IN
        ('Acquisition', 'AdditionalCost', 'OriginalCostCorrection')),
    CONSTRAINT ck_restaurantcapitalassetcosts_amount CHECK
        (amount <> 0 AND (amount > 0 OR sourcetype = 'OriginalCostCorrection')),
    CONSTRAINT ck_restaurantcapitalassetcosts_paid CHECK
        ((sourcetype = 'OriginalCostCorrection' AND amountpaid <= 0)
         OR (sourcetype <> 'OriginalCostCorrection' AND amountpaid >= 0 AND amountpaid <= amount)),
    CONSTRAINT ck_restaurantcapitalassetcosts_status CHECK (status IN ('Posted', 'Reversed'))
);
CREATE INDEX IF NOT EXISTS ix_restaurantcapitalassetcosts_asset
    ON restaurantcapitalassetcosts (capitalassetid, status);
CREATE INDEX IF NOT EXISTS ix_restaurantcapitalassetcosts_farm
    ON restaurantcapitalassetcosts (farmid, costdate);

-- The depreciation ledger. Append-only and signed: a reversal is an opposite
-- row beside the original (Poultry 270 §4 / 271).
CREATE TABLE IF NOT EXISTS restaurantassetdepreciation (
    assetdepreciationid SERIAL PRIMARY KEY,
    farmid              TEXT NOT NULL,
    capitalassetid      INT NOT NULL REFERENCES restaurantcapitalassets(capitalassetid),
    periodstart         DATE NOT NULL,
    periodend           DATE NOT NULL,
    depreciationdate    DATE NOT NULL,
    amount              NUMERIC(14,2) NOT NULL,
    depreciationmethod  TEXT NOT NULL DEFAULT 'StraightLine',
    -- Scheduled | ManualAdjustment | Reversal.
    sourcetype          TEXT NOT NULL DEFAULT 'Scheduled',
    status              TEXT NOT NULL DEFAULT 'Posted',
    reversalofid        INT REFERENCES restaurantassetdepreciation(assetdepreciationid),
    createdby           TEXT,
    createdat           TIMESTAMP NOT NULL DEFAULT NOW(),
    reversedby          TEXT,
    reversedat          TIMESTAMP,
    reversalreason      TEXT,
    CONSTRAINT ck_restaurantassetdepreciation_status CHECK (status IN ('Posted', 'Reversed'))
);
-- One SCHEDULED charge per asset per month: pressing Generate twice cannot
-- charge a month twice.
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantassetdepreciation_period
    ON restaurantassetdepreciation (capitalassetid, periodstart)
    WHERE sourcetype = 'Scheduled';
CREATE INDEX IF NOT EXISTS ix_restaurantassetdepreciation_farm
    ON restaurantassetdepreciation (farmid, depreciationdate);

-- -----------------------------------------------------------------------------
-- 2. The derived numbers, defined once (Poultry 270 §6 + 313 §2).
-- -----------------------------------------------------------------------------

-- TOTAL capitalised cost: acquisition (as corrected) plus every added cost.
CREATE FUNCTION fnrestaurantasset_totalcost(p_assetid INT)
RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(c.amount), 0)::NUMERIC(14,2)
      FROM restaurantcapitalassetcosts c
     WHERE c.capitalassetid = p_assetid AND c.status = 'Posted';
$$;

CREATE FUNCTION fnrestaurantasset_acquisitioncost(p_assetid INT)
RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(c.amount), 0)::NUMERIC(14,2)
      FROM restaurantcapitalassetcosts c
     WHERE c.capitalassetid = p_assetid AND c.status = 'Posted'
       AND c.sourcetype IN ('Acquisition', 'OriginalCostCorrection');
$$;

CREATE FUNCTION fnrestaurantasset_additionalcost(p_assetid INT)
RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(c.amount), 0)::NUMERIC(14,2)
      FROM restaurantcapitalassetcosts c
     WHERE c.capitalassetid = p_assetid AND c.status = 'Posted'
       AND c.sourcetype NOT IN ('Acquisition', 'OriginalCostCorrection');
$$;

-- Signed sum over an append-only ledger.
CREATE FUNCTION fnrestaurantasset_accumulated(p_assetid INT)
RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(d.amount), 0)::NUMERIC(14,2)
      FROM restaurantassetdepreciation d
     WHERE d.capitalassetid = p_assetid;
$$;

-- Straight line only. A residual above cost charges zero, never a negative.
CREATE FUNCTION fnrestaurantasset_monthly(p_cost NUMERIC, p_residual NUMERIC, p_lifemonths INT)
RETURNS NUMERIC LANGUAGE sql IMMUTABLE AS $$
    SELECT ROUND(GREATEST(COALESCE(p_cost, 0) - COALESCE(p_residual, 0), 0) / NULLIF(p_lifemonths, 0), 2);
$$;

CREATE FUNCTION fnrestaurantasset_financials(p_assetid INT)
RETURNS TABLE(originalcost NUMERIC, residualvalue NUMERIC, depreciableamount NUMERIC,
              usefullifemonths INT, monthlydepreciation NUMERIC,
              accumulateddepreciation NUMERIC, currentbookvalue NUMERIC,
              remainingdepreciable NUMERIC, isfullydepreciated BOOLEAN)
LANGUAGE sql STABLE AS $$
    SELECT o.cost,
           a.residualvalue,
           GREATEST(o.cost - a.residualvalue, 0)::NUMERIC(14,2),
           a.usefullifemonths,
           fnrestaurantasset_monthly(o.cost, a.residualvalue, a.usefullifemonths),
           d.acc,
           -- Book value never falls below the residual value.
           GREATEST(o.cost - d.acc, a.residualvalue)::NUMERIC(14,2),
           GREATEST(GREATEST(o.cost - a.residualvalue, 0) - d.acc, 0)::NUMERIC(14,2),
           (GREATEST(o.cost - a.residualvalue, 0) - d.acc) <= 0.004
      FROM restaurantcapitalassets a
     CROSS JOIN LATERAL (SELECT fnrestaurantasset_totalcost(a.capitalassetid) AS cost) o
     CROSS JOIN LATERAL (SELECT fnrestaurantasset_accumulated(a.capitalassetid) AS acc) d
     WHERE a.capitalassetid = p_assetid;
$$;

-- Active <-> FullyDepreciated, the refresh 271's generator does at the end of
-- every run. Draft, Disposed and Reversed are never touched.
CREATE FUNCTION fnrestaurantasset_refreshstatus(p_farmid TEXT, p_assetid INT DEFAULT NULL)
RETURNS VOID LANGUAGE sql AS $$
    UPDATE restaurantcapitalassets ca
       SET status = s.newstatus, updatedat = NOW()
      FROM (SELECT x.capitalassetid AS id,
                   CASE WHEN f.isfullydepreciated THEN 'FullyDepreciated' ELSE 'Active' END AS newstatus
              FROM restaurantcapitalassets x
             CROSS JOIN LATERAL fnrestaurantasset_financials(x.capitalassetid) f
             WHERE x.farmid = p_farmid
               AND (p_assetid IS NULL OR x.capitalassetid = p_assetid)
               AND x.status IN ('Active', 'FullyDepreciated')) s
     WHERE ca.capitalassetid = s.id AND ca.status <> s.newstatus;
$$;

-- -----------------------------------------------------------------------------
-- 3. Categories (Poultry 270 §7), with restaurant defaults.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_assetcategory_ensuredefaults(p_farmid TEXT, p_createdby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO restaurantassetcategories (farmid, categoryname, defaultusefullifemonths, sortorder, createdby)
    SELECT p_farmid, d.name, d.life, d.ord, p_createdby
      FROM (VALUES
              ('Kitchen Equipment',             84, 1),
              ('Refrigeration & Cold Storage',  84, 2),
              ('Furniture & Fittings',          60, 3),
              ('POS & Electronics',             36, 4),
              ('Vehicles',                      60, 5),
              ('Building Improvements',        120, 6),
              ('Generators',                    84, 7),
              ('Office Equipment',              60, 8),
              ('Other Assets',                  60, 9)
           ) AS d(name, life, ord)
     WHERE NOT EXISTS (SELECT 1 FROM restaurantassetcategories c
                        WHERE c.farmid = p_farmid AND lower(c.categoryname) = lower(d.name));
END $$;

CREATE FUNCTION sprestaurant_assetcategory_list(p_farmid TEXT)
RETURNS TABLE(assetcategoryid INT, categoryname TEXT, defaultusefullifemonths INT,
              sortorder INT, isactive BOOLEAN, assetcount INT)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM sprestaurant_assetcategory_ensuredefaults(p_farmid, NULL);
    RETURN QUERY
    SELECT c.assetcategoryid, c.categoryname, c.defaultusefullifemonths, c.sortorder, c.isactive,
           (SELECT COUNT(*)::INT FROM restaurantcapitalassets a
             WHERE a.assetcategoryid = c.assetcategoryid AND a.status <> 'Reversed')
      FROM restaurantassetcategories c
     WHERE c.farmid = p_farmid
     ORDER BY c.sortorder, c.categoryname;
END $$;

CREATE FUNCTION sprestaurant_assetcategory_upsert(p_farmid TEXT, p_assetcategoryid INT, p_categoryname TEXT,
                                                  p_defaultusefullifemonths INT DEFAULT NULL,
                                                  p_isactive BOOLEAN DEFAULT TRUE, p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_id INT := p_assetcategoryid;
BEGIN
    IF COALESCE(btrim(p_categoryname), '') = '' THEN
        RAISE EXCEPTION 'Category name is required.';
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO restaurantassetcategories (farmid, categoryname, defaultusefullifemonths, sortorder, isactive, createdby)
        VALUES (p_farmid, btrim(p_categoryname), p_defaultusefullifemonths,
                COALESCE((SELECT MAX(c.sortorder) + 1 FROM restaurantassetcategories c WHERE c.farmid = p_farmid), 1),
                COALESCE(p_isactive, TRUE), p_createdby)
        RETURNING assetcategoryid INTO v_id;
    ELSE
        UPDATE restaurantassetcategories c
           SET categoryname = btrim(p_categoryname),
               defaultusefullifemonths = p_defaultusefullifemonths,
               isactive = COALESCE(p_isactive, c.isactive)
         WHERE c.assetcategoryid = v_id AND c.farmid = p_farmid;
        IF NOT FOUND THEN RAISE EXCEPTION 'Asset category does not belong to this company.'; END IF;
    END IF;
    RETURN v_id;
END $$;

-- -----------------------------------------------------------------------------
-- 4. The money leg, written once (the role 270's sppoultrycapitalassetexpense_post
--    plays): writes one cost row and posts what was paid now to the ledger.
-- -----------------------------------------------------------------------------
CREATE FUNCTION fnrestaurantasset_postcost(
    p_farmid TEXT, p_assetid INT, p_date DATE, p_sourcetype TEXT, p_description TEXT, p_costcategory TEXT,
    p_amount NUMERIC, p_paymentmethod TEXT, p_amountpaid NUMERIC, p_cashaccountid INT, p_duedate DATE,
    p_supplierid INT, p_suppliername TEXT, p_createdby TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
    v_amt    NUMERIC(14,2) := ROUND(COALESCE(p_amount, 0), 2);
    v_method TEXT := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
    v_credit BOOLEAN;
    v_paid   NUMERIC(14,2);
    v_acc    INT;
    v_sup    TEXT := NULLIF(btrim(p_suppliername), '');
    v_id     INT;
    v_name   TEXT;
BEGIN
    IF v_amt <= 0 THEN RAISE EXCEPTION 'Cost amount must be greater than 0.'; END IF;
    IF p_date IS NULL THEN RAISE EXCEPTION 'A date is required.'; END IF;
    IF p_date > CURRENT_DATE THEN RAISE EXCEPTION 'A capital investment cannot be dated in the future.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, p_date);

    v_credit := lower(v_method) = 'credit';
    -- Paid in full unless the form says otherwise; on credit, nothing is paid now.
    v_paid := ROUND(COALESCE(p_amountpaid, CASE WHEN v_credit THEN 0 ELSE v_amt END), 2);
    IF v_paid < 0 THEN RAISE EXCEPTION 'Amount paid cannot be negative.'; END IF;
    IF v_paid > v_amt THEN
        RAISE EXCEPTION 'Amount paid now (%) cannot be more than the cost (%).', v_paid, v_amt;
    END IF;
    IF v_credit AND v_paid > 0 THEN
        RAISE EXCEPTION 'A credit purchase has nothing paid now. Choose how the % was paid, or leave Amount paid now empty.', v_paid;
    END IF;

    IF p_supplierid IS NOT NULL THEN
        SELECT s.name INTO v_name FROM restaurantsuppliers s
         WHERE s.restaurantsupplierid = p_supplierid AND s.farmid = p_farmid;
        IF v_name IS NULL THEN RAISE EXCEPTION 'Supplier does not belong to this company.'; END IF;
        v_sup := COALESCE(v_sup, v_name);
    END IF;
    -- An unpaid balance is a debt to somebody. Without a name it could never be
    -- found again on Supplier Balances.
    IF v_paid < v_amt AND v_sup IS NULL THEN
        RAISE EXCEPTION 'Name the supplier / payee: % of this cost is still owed.', (v_amt - v_paid);
    END IF;

    -- Same account rule as an expense (323): an explicit account wins, cash
    -- defaults to the Main Cash Box (never an open till), card/bank and mobile
    -- money to their default accounts.
    IF v_paid > 0 THEN
        v_acc := p_cashaccountid;
        IF v_acc IS NULL THEN
            IF lower(replace(v_method, ' ', '')) = 'cash' THEN
                v_acc := fnrestaurant_default_account(p_farmid, 'Cash');
            ELSE
                v_acc := fnrestaurant_resolve_account(p_farmid, v_method, NULL, NULL, FALSE);
            END IF;
        END IF;
        IF v_acc IS NULL THEN RAISE EXCEPTION 'Choose the cash account this was paid from.'; END IF;
    END IF;

    INSERT INTO restaurantcapitalassetcosts
        (farmid, capitalassetid, costdate, description, costcategory, amount, sourcetype,
         paymentmethod, amountpaid, cashaccountid, duedate, supplierid, suppliername, createdby)
    VALUES
        (p_farmid, p_assetid, p_date, NULLIF(btrim(p_description), ''), NULLIF(btrim(p_costcategory), ''),
         v_amt, p_sourcetype, v_method, v_paid, v_acc,
         CASE WHEN v_paid < v_amt THEN p_duedate END, p_supplierid, v_sup, p_createdby)
    RETURNING assetcostid INTO v_id;

    IF v_paid > 0 THEN
        SELECT a.assetnumber || ' ' || a.assetname INTO v_name FROM restaurantcapitalassets a WHERE a.capitalassetid = p_assetid;
        PERFORM fnrestaurant_post(p_farmid, v_acc, p_date, -v_paid, 'AssetPurchase', v_id,
                                  'Capital investment: ' || v_name
                                  || COALESCE(' — ' || NULLIF(btrim(p_description), ''), '')
                                  || COALESCE(' (' || v_sup || ')', ''),
                                  p_createdby);
    END IF;
    RETURN v_id;
END $$;

-- -----------------------------------------------------------------------------
-- 5. Create (Poultry 270 §9). The cost is optional: something built cost by cost
--    starts at nothing and grows through Add cost.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_capitalasset_create(
    p_farmid TEXT, p_assetname TEXT, p_assetcategoryid INT DEFAULT NULL, p_description TEXT DEFAULT NULL,
    p_acquisitiondate DATE DEFAULT NULL, p_inservicedate DATE DEFAULT NULL, p_amount NUMERIC DEFAULT NULL,
    p_residualvalue NUMERIC DEFAULT 0, p_usefullifemonths INT DEFAULT NULL,
    p_suppliername TEXT DEFAULT NULL, p_supplierid INT DEFAULT NULL, p_paymentmethod TEXT DEFAULT 'Cash',
    p_amountpaid NUMERIC DEFAULT NULL, p_duedate DATE DEFAULT NULL, p_cashaccountid INT DEFAULT NULL,
    p_location TEXT DEFAULT NULL, p_serialnumber TEXT DEFAULT NULL, p_notes TEXT DEFAULT NULL,
    p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
    v_id INT; v_number TEXT; v_status TEXT;
    v_date DATE := COALESCE(p_acquisitiondate, CURRENT_DATE);
    v_supname TEXT := NULLIF(btrim(p_suppliername), '');
BEGIN
    IF COALESCE(btrim(p_assetname), '') = '' THEN RAISE EXCEPTION 'Asset name is required.'; END IF;
    IF p_amount IS NOT NULL AND p_amount <= 0 THEN RAISE EXCEPTION 'Asset cost must be greater than 0.'; END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'A capital investment cannot be dated in the future.'; END IF;
    IF p_assetcategoryid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM restaurantassetcategories c
                        WHERE c.assetcategoryid = p_assetcategoryid AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Asset category does not belong to this company.';
    END IF;
    IF p_supplierid IS NOT NULL THEN
        SELECT COALESCE(v_supname, s.name) INTO v_supname FROM restaurantsuppliers s
         WHERE s.restaurantsupplierid = p_supplierid AND s.farmid = p_farmid;
        IF NOT FOUND THEN RAISE EXCEPTION 'Supplier does not belong to this company.'; END IF;
    END IF;
    IF p_inservicedate IS NOT NULL AND p_inservicedate < v_date THEN
        RAISE EXCEPTION 'An asset cannot be in service before it was acquired.';
    END IF;
    IF p_usefullifemonths IS NOT NULL AND p_usefullifemonths <= 0 THEN
        RAISE EXCEPTION 'Useful life must be at least one month.';
    END IF;
    IF COALESCE(p_residualvalue, 0) < 0 THEN RAISE EXCEPTION 'Residual value cannot be negative.'; END IF;
    IF p_amount IS NOT NULL AND COALESCE(p_residualvalue, 0) > p_amount THEN
        RAISE EXCEPTION 'Residual value (%) cannot be more than the asset cost (%).',
            ROUND(p_residualvalue, 2), ROUND(p_amount, 2);
    END IF;

    -- Per-restaurant running number, under a transaction-scoped lock so two
    -- simultaneous saves cannot both claim AST-0007.
    PERFORM pg_advisory_xact_lock(hashtext('restaurantcapitalassets:' || p_farmid));
    SELECT 'AST-' || lpad((COALESCE(MAX(substring(a.assetnumber FROM '[0-9]+$')::INT), 0) + 1)::TEXT, 4, '0')
      INTO v_number
      FROM restaurantcapitalassets a
     WHERE a.farmid = p_farmid AND a.assetnumber ~ '^AST-[0-9]+$';
    v_number := COALESCE(v_number, 'AST-0001');

    -- In service and with a life = Active; anything else is still Draft.
    v_status := CASE WHEN p_inservicedate IS NOT NULL AND COALESCE(p_usefullifemonths, 0) > 0
                     THEN 'Active' ELSE 'Draft' END;

    INSERT INTO restaurantcapitalassets
        (farmid, assetnumber, assetname, assetcategoryid, description, acquisitiondate, inservicedate,
         residualvalue, usefullifemonths, depreciationmethod, supplierid, suppliername, location,
         serialnumber, status, notes, createdby)
    VALUES
        (p_farmid, v_number, btrim(p_assetname), p_assetcategoryid, NULLIF(btrim(p_description), ''), v_date,
         p_inservicedate, COALESCE(p_residualvalue, 0), p_usefullifemonths, 'StraightLine', p_supplierid,
         v_supname, NULLIF(btrim(p_location), ''), NULLIF(btrim(p_serialnumber), ''), v_status,
         NULLIF(btrim(p_notes), ''), p_createdby)
    RETURNING capitalassetid INTO v_id;

    IF COALESCE(p_amount, 0) > 0 THEN
        PERFORM fnrestaurantasset_postcost(p_farmid, v_id, v_date, 'Acquisition', btrim(p_assetname), 'Acquisition',
                                           p_amount, p_paymentmethod, p_amountpaid, p_cashaccountid, p_duedate,
                                           p_supplierid, v_supname, p_createdby);
    END IF;
    RETURN v_id;
END $$;

-- -----------------------------------------------------------------------------
-- 6. Add a cost (Poultry 270 §10): the construction / refit workflow.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_capitalasset_addcost(
    p_farmid TEXT, p_assetid INT, p_costdate DATE, p_description TEXT, p_costcategory TEXT, p_amount NUMERIC,
    p_suppliername TEXT DEFAULT NULL, p_supplierid INT DEFAULT NULL, p_paymentmethod TEXT DEFAULT 'Cash',
    p_amountpaid NUMERIC DEFAULT NULL, p_duedate DATE DEFAULT NULL, p_cashaccountid INT DEFAULT NULL,
    p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_status TEXT; v_name TEXT; v_acq DATE; v_date DATE := COALESCE(p_costdate, CURRENT_DATE);
BEGIN
    SELECT a.status, a.assetname, a.acquisitiondate INTO v_status, v_name, v_acq
      FROM restaurantcapitalassets a
     WHERE a.capitalassetid = p_assetid AND a.farmid = p_farmid
       FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Asset not found for this company.'; END IF;
    IF v_status IN ('Reversed', 'Disposed') THEN
        RAISE EXCEPTION 'Cannot add cost to a % asset.', lower(v_status);
    END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN RAISE EXCEPTION 'Cost amount must be greater than 0.'; END IF;
    IF v_date < v_acq THEN RAISE EXCEPTION 'A cost cannot be dated before the asset was acquired.'; END IF;
    -- Changing the cost under months already charged would make each one wrong.
    IF EXISTS (SELECT 1 FROM restaurantassetdepreciation d
                WHERE d.capitalassetid = p_assetid AND d.status = 'Posted') THEN
        RAISE EXCEPTION 'Depreciation has already been posted for this asset. Reverse it before changing the asset cost.';
    END IF;

    RETURN fnrestaurantasset_postcost(p_farmid, p_assetid, v_date, 'AdditionalCost',
                                      COALESCE(NULLIF(btrim(p_description), ''), v_name), p_costcategory,
                                      p_amount, p_paymentmethod, p_amountpaid, p_cashaccountid, p_duedate,
                                      p_supplierid, p_suppliername, p_createdby);
END $$;

-- -----------------------------------------------------------------------------
-- 7. Edit (Poultry 270 §11). Details always; in-service date, life and residual
--    only until depreciation has been posted.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_capitalasset_update(
    p_farmid TEXT, p_assetid INT, p_assetname TEXT, p_assetcategoryid INT DEFAULT NULL,
    p_description TEXT DEFAULT NULL, p_location TEXT DEFAULT NULL, p_serialnumber TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL, p_inservicedate DATE DEFAULT NULL, p_usefullifemonths INT DEFAULT NULL,
    p_residualvalue NUMERIC DEFAULT NULL, p_setfinancials BOOLEAN DEFAULT FALSE, p_updatedby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_status TEXT; v_acq DATE; v_posted BOOLEAN; v_cost NUMERIC(14,2);
BEGIN
    SELECT a.status, a.acquisitiondate INTO v_status, v_acq
      FROM restaurantcapitalassets a
     WHERE a.capitalassetid = p_assetid AND a.farmid = p_farmid
       FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Asset not found for this company.'; END IF;
    IF v_status = 'Reversed' THEN RAISE EXCEPTION 'A reversed asset cannot be edited.'; END IF;
    IF p_assetcategoryid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM restaurantassetcategories c
                        WHERE c.assetcategoryid = p_assetcategoryid AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Asset category does not belong to this company.';
    END IF;

    v_posted := EXISTS (SELECT 1 FROM restaurantassetdepreciation d
                         WHERE d.capitalassetid = p_assetid AND d.status = 'Posted');
    IF p_setfinancials AND v_posted THEN
        RAISE EXCEPTION 'Depreciation has already been posted for this asset, so its in-service date, useful life and residual value are locked. Reverse the depreciation first.';
    END IF;
    IF p_setfinancials AND p_inservicedate IS NOT NULL AND p_inservicedate < v_acq THEN
        RAISE EXCEPTION 'An asset cannot be in service before it was acquired.';
    END IF;
    IF p_setfinancials AND p_usefullifemonths IS NOT NULL AND p_usefullifemonths <= 0 THEN
        RAISE EXCEPTION 'Useful life must be at least one month.';
    END IF;
    IF p_setfinancials AND COALESCE(p_residualvalue, 0) < 0 THEN
        RAISE EXCEPTION 'Residual value cannot be negative.';
    END IF;
    IF p_setfinancials THEN
        v_cost := fnrestaurantasset_totalcost(p_assetid);
        IF p_residualvalue IS NOT NULL AND p_residualvalue > v_cost AND v_cost > 0 THEN
            RAISE EXCEPTION 'Residual value (%) cannot be more than the asset cost (%).',
                ROUND(p_residualvalue, 2), v_cost;
        END IF;
    END IF;

    UPDATE restaurantcapitalassets a
       SET assetname = COALESCE(NULLIF(btrim(p_assetname), ''), a.assetname),
           assetcategoryid = COALESCE(p_assetcategoryid, a.assetcategoryid),
           description  = NULLIF(btrim(p_description), ''),
           location     = NULLIF(btrim(p_location), ''),
           serialnumber = NULLIF(btrim(p_serialnumber), ''),
           notes        = NULLIF(btrim(p_notes), ''),
           inservicedate    = CASE WHEN p_setfinancials THEN p_inservicedate ELSE a.inservicedate END,
           usefullifemonths = CASE WHEN p_setfinancials THEN p_usefullifemonths ELSE a.usefullifemonths END,
           residualvalue    = CASE WHEN p_setfinancials THEN COALESCE(p_residualvalue, 0) ELSE a.residualvalue END,
           status = CASE WHEN a.status IN ('Draft', 'Active') AND p_setfinancials THEN
                             CASE WHEN p_inservicedate IS NOT NULL AND COALESCE(p_usefullifemonths, 0) > 0
                                  THEN 'Active' ELSE 'Draft' END
                         ELSE a.status END,
           updatedby = p_updatedby, updatedat = NOW()
     WHERE a.capitalassetid = p_assetid AND a.farmid = p_farmid;
END $$;

-- -----------------------------------------------------------------------------
-- 8. Correct the ORIGINAL acquisition cost (Poultry 313 §3). A dated, authored,
--    reasoned, signed row -- never an edit. If the corrected cost is below what
--    was paid, the difference comes back to the account it left.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_capitalasset_correctoriginalcost(
    p_farmid TEXT, p_assetid INT, p_newamount NUMERIC, p_effectivedate DATE DEFAULT NULL,
    p_reason TEXT DEFAULT NULL, p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
    v_status TEXT; v_residual NUMERIC(14,2); v_number TEXT;
    v_new NUMERIC(14,2) := ROUND(COALESCE(p_newamount, 0), 2);
    v_acqcost NUMERIC(14,2); v_addcost NUMERIC(14,2); v_diff NUMERIC(14,2);
    v_acq restaurantcapitalassetcosts%ROWTYPE; v_paid NUMERIC(14,2); v_refund NUMERIC(14,2);
    v_date DATE := COALESCE(p_effectivedate, CURRENT_DATE); v_newid INT;
BEGIN
    SELECT a.status, a.residualvalue, a.assetnumber INTO v_status, v_residual, v_number
      FROM restaurantcapitalassets a
     WHERE a.capitalassetid = p_assetid AND a.farmid = p_farmid
       FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Asset not found for this company.'; END IF;
    IF v_status = 'Reversed' THEN RAISE EXCEPTION 'A reversed investment cannot be corrected.'; END IF;
    IF v_status = 'Disposed' THEN RAISE EXCEPTION 'A disposed investment cannot be corrected.'; END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to correct the original cost.'; END IF;
    IF v_new <= 0 THEN
        RAISE EXCEPTION 'The corrected original cost must be greater than 0. To undo the acquisition entirely, reverse the investment.';
    END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'A correction cannot be dated in the future.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    v_acqcost := fnrestaurantasset_acquisitioncost(p_assetid);
    v_addcost := fnrestaurantasset_additionalcost(p_assetid);
    v_diff    := v_new - v_acqcost;
    IF ABS(v_diff) < 0.005 THEN RAISE EXCEPTION 'The original acquisition cost is already %.', v_acqcost; END IF;

    SELECT * INTO v_acq FROM restaurantcapitalassetcosts c
     WHERE c.capitalassetid = p_assetid AND c.farmid = p_farmid
       AND c.sourcetype = 'Acquisition' AND c.status = 'Posted'
     ORDER BY c.assetcostid LIMIT 1;
    IF v_acq.assetcostid IS NULL THEN
        RAISE EXCEPTION 'This investment has no original acquisition to correct -- its cost was built up with Add cost. Reverse the added cost that is wrong and add it again.';
    END IF;
    IF v_residual > (v_new + v_addcost) THEN
        RAISE EXCEPTION 'Residual value (%) cannot be more than the corrected cost (%). Lower the residual value first.',
            v_residual, (v_new + v_addcost)::NUMERIC(14,2);
    END IF;

    -- What is paid on the acquisition document so far, net of earlier corrections.
    SELECT COALESCE(SUM(c.amountpaid), 0) INTO v_paid FROM restaurantcapitalassetcosts c
     WHERE c.status = 'Posted' AND (c.assetcostid = v_acq.assetcostid OR c.correctionofid = v_acq.assetcostid);
    -- Nobody can have paid more than the bill is now for (313's LEAST).
    v_refund := GREATEST(v_paid - v_new, 0);

    INSERT INTO restaurantcapitalassetcosts
        (farmid, capitalassetid, costdate, description, costcategory, amount, sourcetype, correctionofid,
         paymentmethod, amountpaid, cashaccountid, supplierid, suppliername, createdby)
    VALUES
        (p_farmid, p_assetid, v_date, btrim(p_reason), 'Original Cost Correction', v_diff, 'OriginalCostCorrection',
         v_acq.assetcostid, v_acq.paymentmethod, -v_refund, CASE WHEN v_refund > 0 THEN v_acq.cashaccountid END,
         v_acq.supplierid, v_acq.suppliername, p_createdby)
    RETURNING assetcostid INTO v_newid;

    IF v_refund > 0 THEN
        PERFORM fnrestaurant_post(p_farmid, v_acq.cashaccountid, v_date, v_refund, 'AssetPurchaseReversal', v_newid,
                                  'Original cost of ' || v_number || ' corrected: ' || btrim(p_reason), p_createdby);
    END IF;

    UPDATE restaurantcapitalassets SET updatedby = p_createdby, updatedat = NOW() WHERE capitalassetid = p_assetid;
    PERFORM fnrestaurantasset_refreshstatus(p_farmid, p_assetid);
    RETURN v_newid;
END $$;

-- -----------------------------------------------------------------------------
-- 9. Reverse ONE added cost (Poultry 313 §4). Kept and marked; the cash paid on
--    it comes back today.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_capitalasset_cost_reverse(p_farmid TEXT, p_costid INT, p_reason TEXT,
                                                       p_createdby TEXT DEFAULT NULL, p_assetid INT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_c restaurantcapitalassetcosts%ROWTYPE; v_astatus TEXT; v_number TEXT;
BEGIN
    SELECT * INTO v_c FROM restaurantcapitalassetcosts c
     WHERE c.assetcostid = p_costid AND c.farmid = p_farmid
       FOR UPDATE;
    IF v_c.assetcostid IS NULL THEN RAISE EXCEPTION 'Cost entry not found for this company.'; END IF;
    IF p_assetid IS NOT NULL AND p_assetid <> v_c.capitalassetid THEN
        RAISE EXCEPTION 'That cost entry does not belong to this investment.';
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to reverse a cost.'; END IF;
    IF v_c.status <> 'Posted' THEN RAISE EXCEPTION 'This cost has already been reversed.'; END IF;
    IF v_c.sourcetype = 'Acquisition' THEN
        RAISE EXCEPTION 'This is the original acquisition. Use Correct original cost to change the amount, or reverse the whole investment.';
    END IF;
    IF v_c.sourcetype = 'OriginalCostCorrection' THEN
        RAISE EXCEPTION 'A correction cannot be reversed. Correct the original cost again to the amount you want.';
    END IF;

    SELECT a.status, a.assetnumber INTO v_astatus, v_number FROM restaurantcapitalassets a
     WHERE a.capitalassetid = v_c.capitalassetid AND a.farmid = p_farmid
       FOR UPDATE;
    IF v_astatus IN ('Reversed', 'Disposed') THEN
        RAISE EXCEPTION 'Cannot change the costs of a % investment.', lower(v_astatus);
    END IF;
    IF EXISTS (SELECT 1 FROM restaurantassetdepreciation d
                WHERE d.capitalassetid = v_c.capitalassetid AND d.status = 'Posted') THEN
        RAISE EXCEPTION 'Depreciation has already been posted for this investment. Reverse it before changing the investment cost.';
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    IF v_c.amountpaid > 0 THEN
        PERFORM fnrestaurant_post(p_farmid, v_c.cashaccountid, CURRENT_DATE, v_c.amountpaid, 'AssetPurchaseReversal',
                                  v_c.assetcostid, 'Reversal of a cost on ' || v_number || ': ' || btrim(p_reason),
                                  p_createdby,
                                  (SELECT t.cashtxnid FROM restaurantcashtransactions t
                                    WHERE t.sourcetype = 'AssetPurchase' AND t.sourceid = v_c.assetcostid));
    END IF;

    UPDATE restaurantcapitalassetcosts
       SET status = 'Reversed', reversedby = p_createdby, reversedat = NOW(), reversalreason = btrim(p_reason)
     WHERE assetcostid = p_costid;
    UPDATE restaurantcapitalassets SET updatedby = p_createdby, updatedat = NOW() WHERE capitalassetid = v_c.capitalassetid;
END $$;

-- -----------------------------------------------------------------------------
-- 10. Dispose (Poultry 270 §12). Proceeds are money IN, not revenue. Gain or
--     loss is NOT computed -- the reference's own documented limitation.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_capitalasset_dispose(p_farmid TEXT, p_assetid INT, p_disposaldate DATE,
                                                  p_proceeds NUMERIC DEFAULT NULL, p_cashaccountid INT DEFAULT NULL,
                                                  p_notes TEXT DEFAULT NULL, p_createdby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_status TEXT; v_name TEXT; v_number TEXT; v_acq DATE;
        v_date DATE := COALESCE(p_disposaldate, CURRENT_DATE);
        v_proceeds NUMERIC(14,2) := ROUND(COALESCE(p_proceeds, 0), 2);
BEGIN
    SELECT a.status, a.assetname, a.assetnumber, a.acquisitiondate INTO v_status, v_name, v_number, v_acq
      FROM restaurantcapitalassets a
     WHERE a.capitalassetid = p_assetid AND a.farmid = p_farmid
       FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Asset not found for this company.'; END IF;
    IF v_status IN ('Disposed', 'Reversed') THEN RAISE EXCEPTION 'This asset is already %.', lower(v_status); END IF;
    IF v_proceeds < 0 THEN RAISE EXCEPTION 'Proceeds cannot be negative.'; END IF;
    IF v_proceeds > 0 AND p_cashaccountid IS NULL THEN
        RAISE EXCEPTION 'Select the cash account the sale proceeds went into.';
    END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'A disposal cannot be dated in the future.'; END IF;
    IF v_date < v_acq THEN RAISE EXCEPTION 'An asset cannot be disposed of before it was acquired.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    UPDATE restaurantcapitalassets
       SET status = 'Disposed', disposaldate = v_date,
           disposalproceeds = CASE WHEN v_proceeds > 0 THEN v_proceeds END,
           disposalaccountid = CASE WHEN v_proceeds > 0 THEN p_cashaccountid END,
           disposalnotes = NULLIF(btrim(p_notes), ''), updatedby = p_createdby, updatedat = NOW()
     WHERE capitalassetid = p_assetid;

    IF v_proceeds > 0 THEN
        PERFORM fnrestaurant_post(p_farmid, p_cashaccountid, v_date, v_proceeds, 'AssetDisposal', p_assetid,
                                  'Disposal of ' || v_number || ' ' || v_name, p_createdby);
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 11. Reverse an acquisition (Poultry 270 §13 / 313 §5). Refused once
--     depreciation is posted or the asset is disposed. Every cost row is kept
--     and marked; the net cash paid on each document comes back today.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_capitalasset_reverse(p_farmid TEXT, p_assetid INT, p_reason TEXT,
                                                  p_createdby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_status TEXT; v_number TEXT; r RECORD;
BEGIN
    SELECT a.status, a.assetnumber INTO v_status, v_number
      FROM restaurantcapitalassets a
     WHERE a.capitalassetid = p_assetid AND a.farmid = p_farmid
       FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Asset not found for this company.'; END IF;
    IF v_status = 'Reversed' THEN RAISE EXCEPTION 'This asset has already been reversed.'; END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to reverse an asset.'; END IF;
    IF v_status = 'Disposed' THEN RAISE EXCEPTION 'A disposed asset cannot be reversed.'; END IF;
    IF EXISTS (SELECT 1 FROM restaurantassetdepreciation d
                WHERE d.capitalassetid = p_assetid AND d.status = 'Posted') THEN
        RAISE EXCEPTION 'Depreciation has been posted for this asset. Reverse the depreciation first.';
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    -- One refund per document: an acquisition together with its corrections, or
    -- one added cost. Corrections already handed back their part.
    FOR r IN
        SELECT d.assetcostid, d.cashaccountid,
               (SELECT COALESCE(SUM(x.amountpaid), 0) FROM restaurantcapitalassetcosts x
                 WHERE x.status = 'Posted' AND (x.assetcostid = d.assetcostid OR x.correctionofid = d.assetcostid)) AS netpaid
          FROM restaurantcapitalassetcosts d
         WHERE d.capitalassetid = p_assetid AND d.status = 'Posted' AND d.sourcetype <> 'OriginalCostCorrection'
         ORDER BY d.assetcostid
    LOOP
        IF r.netpaid > 0 THEN
            PERFORM fnrestaurant_post(p_farmid, r.cashaccountid, CURRENT_DATE, r.netpaid, 'AssetPurchaseReversal',
                                      r.assetcostid, 'Reversal of ' || v_number || ': ' || btrim(p_reason), p_createdby,
                                      (SELECT t.cashtxnid FROM restaurantcashtransactions t
                                        WHERE t.sourcetype = 'AssetPurchase' AND t.sourceid = r.assetcostid));
        END IF;
    END LOOP;

    UPDATE restaurantcapitalassetcosts
       SET status = 'Reversed', reversedby = p_createdby, reversedat = NOW(), reversalreason = btrim(p_reason)
     WHERE capitalassetid = p_assetid AND status = 'Posted';
    UPDATE restaurantcapitalassets
       SET status = 'Reversed', reversedby = p_createdby, reversedat = NOW(), reversalreason = btrim(p_reason),
           updatedat = NOW()
     WHERE capitalassetid = p_assetid;
END $$;

-- -----------------------------------------------------------------------------
-- 12. Reads.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_capitalasset_list(p_farmid TEXT, p_status TEXT DEFAULT NULL,
                                               p_categoryid INT DEFAULT NULL, p_assetid INT DEFAULT NULL)
RETURNS TABLE(capitalassetid INT, assetnumber TEXT, assetname TEXT, assetcategoryid INT, categoryname TEXT,
              description TEXT, acquisitiondate DATE, inservicedate DATE, location TEXT, serialnumber TEXT,
              supplierid INT, suppliername TEXT, status TEXT, notes TEXT,
              originalcost NUMERIC, residualvalue NUMERIC, depreciableamount NUMERIC,
              usefullifemonths INT, monthlydepreciation NUMERIC, accumulateddepreciation NUMERIC,
              currentbookvalue NUMERIC, remainingdepreciable NUMERIC, isfullydepreciated BOOLEAN,
              costentries INT, depreciationentries INT,
              disposaldate DATE, disposalproceeds NUMERIC, disposalaccountid INT, disposalnotes TEXT,
              createdby TEXT, createdat TIMESTAMP, updatedat TIMESTAMP,
              reversedby TEXT, reversedat TIMESTAMP, reversalreason TEXT,
              acquisitioncost NUMERIC, additionalcost NUMERIC, totalcapitalizedcost NUMERIC,
              amountowed NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT a.capitalassetid, a.assetnumber, a.assetname, a.assetcategoryid, c.categoryname,
           a.description, a.acquisitiondate, a.inservicedate, a.location, a.serialnumber,
           a.supplierid, a.suppliername, a.status, a.notes,
           f.originalcost, f.residualvalue, f.depreciableamount,
           f.usefullifemonths, f.monthlydepreciation, f.accumulateddepreciation,
           f.currentbookvalue, f.remainingdepreciable, f.isfullydepreciated,
           (SELECT COUNT(*)::INT FROM restaurantcapitalassetcosts cc
             WHERE cc.capitalassetid = a.capitalassetid AND cc.status = 'Posted'),
           (SELECT COUNT(*)::INT FROM restaurantassetdepreciation dd
             WHERE dd.capitalassetid = a.capitalassetid AND dd.status = 'Posted'),
           a.disposaldate, a.disposalproceeds, a.disposalaccountid, a.disposalnotes,
           a.createdby, a.createdat, a.updatedat,
           a.reversedby, a.reversedat, a.reversalreason,
           fnrestaurantasset_acquisitioncost(a.capitalassetid),
           fnrestaurantasset_additionalcost(a.capitalassetid),
           f.originalcost,
           (SELECT COALESCE(SUM(cc.amount - cc.amountpaid), 0)::NUMERIC(14,2) FROM restaurantcapitalassetcosts cc
             WHERE cc.capitalassetid = a.capitalassetid AND cc.status = 'Posted')
      FROM restaurantcapitalassets a
      LEFT JOIN restaurantassetcategories c ON c.assetcategoryid = a.assetcategoryid
     CROSS JOIN LATERAL fnrestaurantasset_financials(a.capitalassetid) f
     WHERE a.farmid = p_farmid
       AND (p_status IS NULL OR a.status = p_status)
       AND (p_categoryid IS NULL OR a.assetcategoryid = p_categoryid)
       AND (p_assetid IS NULL OR a.capitalassetid = p_assetid)
     ORDER BY a.acquisitiondate DESC, a.capitalassetid DESC;
$$;

-- The cost history. balance / paymentstatus are per DOCUMENT: an acquisition
-- carries its corrections, a correction row itself owes nothing.
CREATE FUNCTION sprestaurant_capitalasset_costs(p_farmid TEXT, p_assetid INT)
RETURNS TABLE(assetcostid INT, capitalassetid INT, costdate DATE, description TEXT, costcategory TEXT,
              amount NUMERIC, sourcetype TEXT, correctionofid INT, supplierid INT, suppliername TEXT,
              paymentmethod TEXT, amountpaid NUMERIC, balance NUMERIC, paymentstatus TEXT, duedate DATE,
              cashaccountid INT, cashaccountname TEXT, documentamount NUMERIC,
              status TEXT, createdby TEXT, createdat TIMESTAMP,
              reversedby TEXT, reversedat TIMESTAMP, reversalreason TEXT)
LANGUAGE sql STABLE AS $$
    SELECT c.assetcostid, c.capitalassetid, c.costdate, c.description, c.costcategory,
           c.amount, c.sourcetype, c.correctionofid, c.supplierid, c.suppliername,
           c.paymentmethod, c.amountpaid,
           CASE WHEN c.sourcetype = 'OriginalCostCorrection' THEN 0 ELSE doc.amt - doc.paid END,
           CASE WHEN c.sourcetype = 'OriginalCostCorrection' THEN NULL
                WHEN doc.amt - doc.paid <= 0 THEN 'Paid'
                WHEN doc.paid <= 0 THEN 'Unpaid' ELSE 'Partial' END,
           c.duedate, c.cashaccountid, ca.name,
           CASE WHEN c.sourcetype = 'OriginalCostCorrection' THEN NULL ELSE doc.amt END,
           c.status, c.createdby, c.createdat, c.reversedby, c.reversedat, c.reversalreason
      FROM restaurantcapitalassetcosts c
      LEFT JOIN restaurantcashaccounts ca ON ca.cashaccountid = c.cashaccountid
     CROSS JOIN LATERAL (
            SELECT COALESCE(SUM(x.amount), 0)::NUMERIC(14,2) AS amt, COALESCE(SUM(x.amountpaid), 0)::NUMERIC(14,2) AS paid
              FROM restaurantcapitalassetcosts x
             WHERE (x.assetcostid = c.assetcostid OR x.correctionofid = c.assetcostid)
               AND (x.status = 'Posted' OR c.status <> 'Posted')) doc
     WHERE c.farmid = p_farmid AND c.capitalassetid = p_assetid
     ORDER BY c.costdate, c.assetcostid;
$$;

-- The five cards. Book value is a BALANCE (what the restaurant owns today); only
-- "added in period" is period-scoped (Poultry 270 §14).
CREATE FUNCTION sprestaurant_capitalasset_summary(p_farmid TEXT, p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS TABLE(totalassets INT, activeassets INT, draftassets INT, disposedassets INT, fullydepreciated INT,
              totalassetcost NUMERIC, accumulateddepreciation NUMERIC, currentbookvalue NUMERIC,
              addedinperiod NUMERIC, addedcount INT, amountowed NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH live AS (
        SELECT a.capitalassetid, a.status, f.*
          FROM restaurantcapitalassets a
         CROSS JOIN LATERAL fnrestaurantasset_financials(a.capitalassetid) f
         WHERE a.farmid = p_farmid AND a.status <> 'Reversed'
    )
    SELECT COUNT(*)::INT,
           COUNT(*) FILTER (WHERE l.status = 'Active')::INT,
           COUNT(*) FILTER (WHERE l.status = 'Draft')::INT,
           COUNT(*) FILTER (WHERE l.status = 'Disposed')::INT,
           COUNT(*) FILTER (WHERE l.status = 'FullyDepreciated')::INT,
           COALESCE(SUM(l.originalcost), 0)::NUMERIC(14,2),
           COALESCE(SUM(l.accumulateddepreciation), 0)::NUMERIC(14,2),
           COALESCE(SUM(l.currentbookvalue), 0)::NUMERIC(14,2),
           COALESCE((SELECT SUM(cc.amount) FROM restaurantcapitalassetcosts cc
                      WHERE cc.farmid = p_farmid AND cc.status = 'Posted'
                        AND (p_from IS NULL OR cc.costdate >= p_from)
                        AND (p_to IS NULL OR cc.costdate <= p_to)), 0)::NUMERIC(14,2),
           COALESCE((SELECT COUNT(*) FROM restaurantcapitalassets aa
                      WHERE aa.farmid = p_farmid AND aa.status <> 'Reversed'
                        AND (p_from IS NULL OR aa.acquisitiondate >= p_from)
                        AND (p_to IS NULL OR aa.acquisitiondate <= p_to)), 0)::INT,
           COALESCE((SELECT SUM(cc.amount - cc.amountpaid) FROM restaurantcapitalassetcosts cc
                      WHERE cc.farmid = p_farmid AND cc.status = 'Posted'), 0)::NUMERIC(14,2)
      FROM live l;
$$;

-- What is still owed on capital purchases, one row per purchase document. This
-- is the seam for Supplier Balances: UNION it in as documenttype 'AssetCost',
-- documentid = assetcostid. (Balance is amount - paid-at-purchase today; once
-- supplier payments exist they subtract their allocations here.)
CREATE FUNCTION sprestaurant_capitalasset_payables(p_farmid TEXT)
RETURNS TABLE(assetcostid INT, capitalassetid INT, assetnumber TEXT, assetname TEXT, sourcetype TEXT,
              supplierid INT, suppliername TEXT, documentdate DATE, duedate DATE,
              amount NUMERIC, amountpaid NUMERIC, balance NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT d.assetcostid, a.capitalassetid, a.assetnumber, a.assetname, d.sourcetype,
           d.supplierid, d.suppliername, d.costdate, d.duedate, x.amt, x.paid, x.amt - x.paid
      FROM restaurantcapitalassetcosts d
      JOIN restaurantcapitalassets a ON a.capitalassetid = d.capitalassetid
     CROSS JOIN LATERAL (
            SELECT COALESCE(SUM(y.amount), 0)::NUMERIC(14,2) AS amt, COALESCE(SUM(y.amountpaid), 0)::NUMERIC(14,2) AS paid
              FROM restaurantcapitalassetcosts y
             WHERE y.status = 'Posted' AND (y.assetcostid = d.assetcostid OR y.correctionofid = d.assetcostid)) x
     WHERE d.farmid = p_farmid AND d.status = 'Posted' AND d.sourcetype <> 'OriginalCostCorrection'
       AND x.amt - x.paid > 0
     ORDER BY COALESCE(d.duedate, d.costdate), d.assetcostid;
$$;

-- -----------------------------------------------------------------------------
-- 13. Depreciation (Poultry 271). Moves no money: no ledger row, no account.
--     Not subject to the closed-day lock -- daily closing locks CASH, and a
--     depreciation charge is not cash. A charge is dated the last day of its
--     month; a reversal is dated today.
-- -----------------------------------------------------------------------------
CREATE FUNCTION fnrestaurant_assetdepreciation_post(p_farmid TEXT, p_assetid INT, p_periodstart DATE, p_amount NUMERIC,
                                                    p_sourcetype TEXT DEFAULT 'Scheduled', p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_id INT; v_start DATE := date_trunc('month', p_periodstart)::DATE;
        v_end DATE := (date_trunc('month', p_periodstart) + INTERVAL '1 month - 1 day')::DATE;
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN RETURN NULL; END IF;   -- nothing to charge is not an error
    IF NOT EXISTS (SELECT 1 FROM restaurantcapitalassets a WHERE a.capitalassetid = p_assetid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;
    INSERT INTO restaurantassetdepreciation
        (farmid, capitalassetid, periodstart, periodend, depreciationdate, amount, depreciationmethod,
         sourcetype, status, createdby)
    VALUES (p_farmid, p_assetid, v_start, v_end, v_end, ROUND(p_amount, 2), 'StraightLine', p_sourcetype, 'Posted', p_createdby)
    RETURNING assetdepreciationid INTO v_id;
    RETURN v_id;
END $$;

-- Charges every due month up to p_throughdate (default: this month). Idempotent.
-- The schedule is exactly usefullifemonths long and its LAST month takes what is
-- left, so accumulated depreciation lands on the depreciable amount exactly.
CREATE FUNCTION sprestaurant_assetdepreciation_generate(p_farmid TEXT, p_throughdate DATE DEFAULT NULL,
                                                        p_assetid INT DEFAULT NULL, p_createdby TEXT DEFAULT NULL)
RETURNS TABLE(assetsprocessed INT, entriescreated INT, totalamount NUMERIC)
LANGUAGE plpgsql AS $$
DECLARE
    v_through DATE := date_trunc('month', COALESCE(p_throughdate, CURRENT_DATE))::DATE;
    v_assets INT := 0; v_entries INT := 0; v_total NUMERIC(14,2) := 0;
    a RECORD; v_period DATE; v_monthly NUMERIC(14,2); v_remaining NUMERIC(14,2); v_charge NUMERIC(14,2);
    v_index INT; v_made BOOLEAN;
BEGIN
    -- One generator per restaurant at a time.
    PERFORM pg_advisory_xact_lock(hashtext('restaurantassetdepreciation:' || p_farmid));
    FOR a IN
        SELECT ca.capitalassetid AS assetid, ca.inservicedate, f.*
          FROM restaurantcapitalassets ca
         CROSS JOIN LATERAL fnrestaurantasset_financials(ca.capitalassetid) f
         WHERE ca.farmid = p_farmid
           AND (p_assetid IS NULL OR ca.capitalassetid = p_assetid)
           AND ca.status IN ('Active', 'FullyDepreciated')
           AND ca.inservicedate IS NOT NULL AND COALESCE(ca.usefullifemonths, 0) > 0
         ORDER BY ca.capitalassetid
    LOOP
        v_monthly := a.monthlydepreciation; v_remaining := a.remainingdepreciable; v_made := FALSE;
        IF COALESCE(v_monthly, 0) <= 0 THEN CONTINUE; END IF;
        v_period := date_trunc('month', a.inservicedate)::DATE;
        v_index := 0;
        WHILE v_period <= v_through AND v_remaining > 0 AND v_index < a.usefullifemonths LOOP
            IF NOT EXISTS (SELECT 1 FROM restaurantassetdepreciation d
                            WHERE d.capitalassetid = a.assetid AND d.periodstart = v_period
                              AND d.sourcetype = 'Scheduled') THEN
                v_charge := CASE WHEN v_index = a.usefullifemonths - 1 THEN v_remaining
                                 ELSE LEAST(v_monthly, v_remaining) END;
                IF fnrestaurant_assetdepreciation_post(p_farmid, a.assetid, v_period, v_charge, 'Scheduled', p_createdby) IS NOT NULL THEN
                    v_remaining := v_remaining - v_charge;
                    v_entries := v_entries + 1;
                    v_total := v_total + v_charge;
                    v_made := TRUE;
                END IF;
            END IF;
            v_period := (v_period + INTERVAL '1 month')::DATE;
            v_index := v_index + 1;
        END LOOP;
        IF v_made THEN v_assets := v_assets + 1; END IF;
    END LOOP;

    PERFORM fnrestaurantasset_refreshstatus(p_farmid, p_assetid);
    RETURN QUERY SELECT v_assets, v_entries, v_total;
END $$;

-- The original is kept and flagged; an opposite row is appended. The month is
-- NOT reopened to the generator (use _adjust for a corrected amount).
CREATE FUNCTION sprestaurant_assetdepreciation_reverse(p_farmid TEXT, p_entryid INT, p_reason TEXT,
                                                       p_createdby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_row restaurantassetdepreciation%ROWTYPE;
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to reverse depreciation.'; END IF;
    SELECT * INTO v_row FROM restaurantassetdepreciation d
     WHERE d.assetdepreciationid = p_entryid AND d.farmid = p_farmid
       FOR UPDATE;
    IF v_row.assetdepreciationid IS NULL THEN RAISE EXCEPTION 'Depreciation entry not found for this company.'; END IF;
    IF v_row.status = 'Reversed' THEN RAISE EXCEPTION 'This depreciation entry has already been reversed.'; END IF;
    IF v_row.amount < 0 THEN RAISE EXCEPTION 'A reversal cannot itself be reversed.'; END IF;

    INSERT INTO restaurantassetdepreciation
        (farmid, capitalassetid, periodstart, periodend, depreciationdate, amount, depreciationmethod,
         sourcetype, status, reversalofid, createdby, reversalreason)
    VALUES (p_farmid, v_row.capitalassetid, v_row.periodstart, v_row.periodend, CURRENT_DATE,
            -v_row.amount, v_row.depreciationmethod, 'Reversal', 'Posted', p_entryid, p_createdby, btrim(p_reason));

    UPDATE restaurantassetdepreciation
       SET status = 'Reversed', reversedby = p_createdby, reversedat = NOW(), reversalreason = btrim(p_reason)
     WHERE assetdepreciationid = p_entryid;

    PERFORM fnrestaurantasset_refreshstatus(p_farmid, v_row.capitalassetid);
END $$;

-- A corrected amount for one month, posted explicitly as a ManualAdjustment.
CREATE FUNCTION sprestaurant_assetdepreciation_adjust(p_farmid TEXT, p_assetid INT, p_periodstart DATE,
                                                      p_amount NUMERIC, p_reason TEXT, p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_status TEXT; v_left NUMERIC(14,2); v_id INT;
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required for a depreciation adjustment.'; END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN RAISE EXCEPTION 'Adjustment amount must be greater than 0.'; END IF;
    IF p_periodstart IS NULL THEN RAISE EXCEPTION 'Choose the month to adjust.'; END IF;
    SELECT a.status INTO v_status FROM restaurantcapitalassets a
     WHERE a.capitalassetid = p_assetid AND a.farmid = p_farmid
       FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Asset not found for this company.'; END IF;
    IF v_status IN ('Reversed', 'Draft') THEN
        RAISE EXCEPTION 'Depreciation cannot be adjusted on a % asset.', lower(v_status);
    END IF;
    SELECT f.remainingdepreciable INTO v_left FROM fnrestaurantasset_financials(p_assetid) f;
    IF p_amount > v_left THEN RAISE EXCEPTION 'This asset has only % left to depreciate.', v_left; END IF;

    v_id := fnrestaurant_assetdepreciation_post(p_farmid, p_assetid, p_periodstart, p_amount, 'ManualAdjustment', p_createdby);
    UPDATE restaurantassetdepreciation SET reversalreason = btrim(p_reason) WHERE assetdepreciationid = v_id;
    PERFORM fnrestaurantasset_refreshstatus(p_farmid, p_assetid);
    RETURN v_id;
END $$;

CREATE FUNCTION sprestaurant_assetdepreciation_list(p_farmid TEXT, p_assetid INT DEFAULT NULL,
                                                    p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS TABLE(assetdepreciationid INT, capitalassetid INT, assetnumber TEXT, assetname TEXT, categoryname TEXT,
              periodstart DATE, periodend DATE, depreciationdate DATE, amount NUMERIC, depreciationmethod TEXT,
              sourcetype TEXT, status TEXT, reversalofid INT, originalcost NUMERIC, monthlydepreciation NUMERIC,
              accumulatedafter NUMERIC, bookvalueafter NUMERIC,
              createdby TEXT, createdat TIMESTAMP, reversedby TEXT, reversedat TIMESTAMP, reversalreason TEXT)
LANGUAGE sql STABLE AS $$
    SELECT d.assetdepreciationid, d.capitalassetid, a.assetnumber, a.assetname, c.categoryname,
           d.periodstart, d.periodend, d.depreciationdate, d.amount, d.depreciationmethod,
           d.sourcetype, d.status, d.reversalofid,
           fnrestaurantasset_totalcost(d.capitalassetid),
           fnrestaurantasset_monthly(fnrestaurantasset_totalcost(d.capitalassetid), a.residualvalue, a.usefullifemonths),
           run.acc,
           GREATEST(fnrestaurantasset_totalcost(d.capitalassetid) - run.acc, a.residualvalue)::NUMERIC(14,2),
           d.createdby, d.createdat, d.reversedby, d.reversedat, d.reversalreason
      FROM restaurantassetdepreciation d
      JOIN restaurantcapitalassets a ON a.capitalassetid = d.capitalassetid
      LEFT JOIN restaurantassetcategories c ON c.assetcategoryid = a.assetcategoryid
     CROSS JOIN LATERAL (
            SELECT COALESCE(SUM(p.amount), 0)::NUMERIC(14,2) AS acc
              FROM restaurantassetdepreciation p
             WHERE p.capitalassetid = d.capitalassetid
               AND (p.depreciationdate, p.assetdepreciationid) <= (d.depreciationdate, d.assetdepreciationid)) run
     WHERE d.farmid = p_farmid
       AND (p_assetid IS NULL OR d.capitalassetid = p_assetid)
       AND (p_from IS NULL OR d.depreciationdate >= p_from)
       AND (p_to IS NULL OR d.depreciationdate <= p_to)
     ORDER BY d.depreciationdate DESC, d.assetdepreciationid DESC;
$$;

-- What Generate would do, without doing it -- the same walk, bound and last-month
-- rule included, so the "N due" badge can never promise a different number.
CREATE FUNCTION sprestaurant_assetdepreciation_due(p_farmid TEXT, p_throughdate DATE DEFAULT NULL)
RETURNS TABLE(capitalassetid INT, assetnumber TEXT, assetname TEXT, monthsdue INT, amountdue NUMERIC,
              monthlydepreciation NUMERIC, nextperiod DATE)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_through DATE := date_trunc('month', COALESCE(p_throughdate, CURRENT_DATE))::DATE;
    a RECORD; v_period DATE; v_months INT; v_amount NUMERIC(14,2); v_left NUMERIC(14,2);
    v_charge NUMERIC(14,2); v_index INT; v_next DATE;
BEGIN
    FOR a IN
        SELECT ca.capitalassetid AS assetid, ca.assetnumber AS num, ca.assetname AS nm, ca.inservicedate, f.*
          FROM restaurantcapitalassets ca
         CROSS JOIN LATERAL fnrestaurantasset_financials(ca.capitalassetid) f
         WHERE ca.farmid = p_farmid AND ca.status = 'Active'
           AND ca.inservicedate IS NOT NULL AND COALESCE(ca.usefullifemonths, 0) > 0
         ORDER BY ca.capitalassetid
    LOOP
        v_months := 0; v_amount := 0; v_next := NULL; v_left := a.remainingdepreciable;
        v_period := date_trunc('month', a.inservicedate)::DATE; v_index := 0;
        IF COALESCE(a.monthlydepreciation, 0) <= 0 THEN CONTINUE; END IF;
        WHILE v_period <= v_through AND v_left > 0 AND v_index < a.usefullifemonths LOOP
            IF NOT EXISTS (SELECT 1 FROM restaurantassetdepreciation d
                            WHERE d.capitalassetid = a.assetid AND d.periodstart = v_period
                              AND d.sourcetype = 'Scheduled') THEN
                v_charge := CASE WHEN v_index = a.usefullifemonths - 1 THEN v_left
                                 ELSE LEAST(a.monthlydepreciation, v_left) END;
                v_next := COALESCE(v_next, v_period);
                v_months := v_months + 1; v_amount := v_amount + v_charge; v_left := v_left - v_charge;
            END IF;
            v_period := (v_period + INTERVAL '1 month')::DATE;
            v_index := v_index + 1;
        END LOOP;
        IF v_months > 0 THEN
            capitalassetid := a.assetid; assetnumber := a.num; assetname := a.nm;
            monthsdue := v_months; amountdue := v_amount; monthlydepreciation := a.monthlydepreciation;
            nextperiod := v_next;
            RETURN NEXT;
        END IF;
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 14. Cash Flow, P&L and the profit-vs-cash bridge. Copied from 326 with only
--     the marked (328) additions; same signatures and result columns.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sprestaurantcashflow_detail(p_farmid TEXT, p_fromdate TIMESTAMP DEFAULT NULL,
                                            p_todate TIMESTAMP DEFAULT NULL)
RETURNS TABLE(rowsource TEXT, offledger BOOLEAN, sourcerowid INT, cashaccountid INT, accountname TEXT,
              transactiondate TIMESTAMP, transactiontype TEXT, sourcetype TEXT, sourceid INT,
              istransfer BOOLEAN, amount NUMERIC, description TEXT, flowgroup TEXT, category TEXT,
              createdat TIMESTAMP)
LANGUAGE sql STABLE AS $$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname, r.transactiondate,
           r.transactiontype, r.sourcetype, r.sourceid, r.istransfer, r.amount, r.description, r.flowgroup,
           CASE r.sourcetype
               WHEN 'OrderPayment' THEN 'Sales (' || COALESCE(NULLIF(btrim(p.paymentmethod), ''), 'Cash') || ')'
               WHEN 'OrderRefund' THEN 'Refunds to customers'
               WHEN 'Expense' THEN COALESCE(NULLIF(btrim(e.categoryname), ''), 'Uncategorised')
               WHEN 'ExpenseReversal' THEN 'Expense corrections'
               WHEN 'GiftCardSale' THEN 'Gift card sales'
               WHEN 'GiftCardReload' THEN 'Gift card sales'
               WHEN 'OwnerContribution' THEN 'Owner contributions'
               WHEN 'OwnerDraw' THEN 'Owner drawings'
               WHEN 'OwnerContributionReversal' THEN 'Owner money corrections'
               WHEN 'OwnerDrawReversal' THEN 'Owner money corrections'
               WHEN 'LoanReceived' THEN 'Loans received'
               WHEN 'LoanRepayment' THEN 'Loan repayments'
               WHEN 'LoanRepaymentReversal' THEN 'Loan corrections'
               WHEN 'LoanReceivedReversal' THEN 'Loan corrections'
               WHEN 'ShiftVariance' THEN 'Cash over / short'
               WHEN 'CountVariance' THEN 'Cash over / short'
               WHEN 'CountVarianceReversal' THEN 'Cash over / short'
               WHEN 'Payroll' THEN 'Staff wages (net pay)'
               WHEN 'EmployeeLoanDisbursement' THEN 'Staff advances paid out'
               WHEN 'EmployeeLoanReversal' THEN 'Staff advance corrections'
               WHEN 'EmployeeLoanRepayment' THEN 'Staff advances repaid'
               WHEN 'EmployeeLoanRepaymentReversal' THEN 'Staff advance corrections'
               -- 328: capital investments (Operating, as in Poultry: no Investing group)
               WHEN 'AssetPurchase' THEN 'Capital investments'
               WHEN 'AssetPurchaseReversal' THEN 'Capital investment corrections'
               WHEN 'AssetDisposal' THEN 'Capital investments sold'
               ELSE 'Other' END::TEXT,
           r.createdat
      FROM sprestaurantcashflow_rows(p_farmid, p_fromdate, p_todate) r
      LEFT JOIN restaurantorderpayments p ON r.sourcetype = 'OrderPayment' AND p.orderpaymentid = r.sourceid
      LEFT JOIN restaurantexpenses e ON r.sourcetype = 'Expense' AND e.expenseid = r.sourceid;
$$;

CREATE OR REPLACE FUNCTION sprestaurant_report_pnl_lines(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(section TEXT, linekey TEXT, label TEXT, amount NUMERIC, sortorder INT)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE v_sales NUMERIC; v_disc NUMERIC; v_sc NUMERIC; v_fee NUMERIC; v_ref NUMERIC; v_cogs NUMERIC;
        v_int NUMERIC; v_fees NUMERIC; v_var NUMERIC; v_wages NUMERIC; v_slint NUMERIC; v_dep NUMERIC;
BEGIN
    SELECT COALESCE(SUM(o.subtotal), 0), COALESCE(SUM(o.discountamount), 0),
           COALESCE(SUM(o.servicechargeamount), 0), COALESCE(SUM(o.deliveryfee), 0)
      INTO v_sales, v_disc, v_sc, v_fee
      FROM restaurantorders o
     WHERE o.farmid = p_farmid AND o.status = 'Completed'
       AND o.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(p.amount), 0) INTO v_ref
      FROM restaurantorderpayments p
      JOIN restaurantorders o ON o.orderid = p.orderid AND o.farmid = p.farmid
     WHERE p.farmid = p_farmid AND p.amount < 0 AND p.status = 'Completed' AND o.status = 'Completed'
       AND p.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(oi.quantity * COALESCE((
               SELECT SUM(r.quantity * (1 + COALESCE(r.wastepercent, 0) / 100) * i.costperunit)
                 FROM restaurantrecipes r
                 JOIN restaurantingredients i ON i.ingredientid = r.ingredientid AND i.farmid = r.farmid
                WHERE r.menuitemid = oi.menuitemid AND r.farmid = oi.farmid), 0)), 0)
      INTO v_cogs
      FROM restaurantorderitems oi
      JOIN restaurantorders o ON o.orderid = oi.orderid AND o.farmid = oi.farmid
     WHERE oi.farmid = p_farmid AND o.status = 'Completed' AND oi.status <> 'Cancelled'
       AND o.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(lp.interestamount), 0), COALESCE(SUM(lp.feeamount), 0)
      INTO v_int, v_fees
      FROM restaurantloanpayments lp
     WHERE lp.farmid = p_farmid AND lp.status = 'Posted' AND lp.paymentdate BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(t.amount), 0) INTO v_var
      FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.sourcetype IN ('ShiftVariance', 'CountVariance', 'CountVarianceReversal')
       AND t.txndate BETWEEN p_from AND p_to;

    -- Staff wages at GROSS pay for runs paid in the period (326).
    SELECT COALESCE(SUM(r.totalgross), 0) INTO v_wages
      FROM restaurantpayrollruns r
     WHERE r.farmid = p_farmid AND r.status = 'Paid' AND r.paydate BETWEEN p_from AND p_to;

    -- Interest repaid on staff loans (326).
    SELECT COALESCE(SUM(sr.interestamount), 0) INTO v_slint
      FROM restaurantstaffloanrepayments sr
     WHERE sr.farmid = p_farmid AND sr.status = 'Posted' AND sr.repaymentdate BETWEEN p_from AND p_to;

    -- 328: depreciation charged in the period, reversals (negative rows) netted.
    SELECT COALESCE(SUM(d.amount), 0) INTO v_dep
      FROM restaurantassetdepreciation d
     WHERE d.farmid = p_farmid AND d.depreciationdate BETWEEN p_from AND p_to;

    RETURN QUERY VALUES
        ('Revenue', 'food_sales', 'Food & beverage sales', ROUND(v_sales, 2), 10),
        ('Revenue', 'discounts', 'Less: discounts & promotions', ROUND(-v_disc, 2), 11),
        ('Revenue', 'refunds', 'Less: partial refunds', ROUND(v_ref, 2), 12),
        ('Revenue', 'service_charge', 'Service charge', ROUND(v_sc, 2), 13),
        ('Revenue', 'delivery_fees', 'Delivery fees', ROUND(v_fee, 2), 14),
        ('CostOfSales', 'recipe_cost', 'Ingredients (recipe cost)', ROUND(-v_cogs, 2), 20);

    IF v_wages <> 0 THEN
        RETURN QUERY VALUES ('Expenses', 'staff_wages', 'Staff wages (payroll)', ROUND(-v_wages, 2), 29);
    END IF;

    RETURN QUERY
    SELECT 'Expenses'::TEXT, 'expense:' || COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised'),
           COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised'), ROUND(-SUM(e.amount), 2), 30
      FROM restaurantexpenses e
     WHERE e.farmid = p_farmid AND e.expensedate BETWEEN p_from AND p_to
       AND COALESCE(e.status, 'Approved') NOT IN ('Rejected', 'Draft')
     GROUP BY COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised')
     ORDER BY SUM(e.amount) DESC;

    -- 328: Depreciation leads the Depreciation & Financing lines, as in Poultry.
    IF v_dep <> 0 THEN
        RETURN QUERY VALUES ('Other', 'depreciation', 'Depreciation', ROUND(-v_dep, 2), 39);
    END IF;

    RETURN QUERY VALUES
        ('Other', 'loan_interest', 'Loan interest', ROUND(-v_int, 2), 40),
        ('Other', 'loan_fees', 'Loan fees', ROUND(-v_fees, 2), 41),
        ('Other', 'cash_variance', 'Cash over / short', ROUND(v_var, 2), 42);
    IF v_slint <> 0 THEN
        RETURN QUERY VALUES ('Other', 'staff_loan_interest', 'Interest on staff loans', ROUND(v_slint, 2), 43);
    END IF;
END $$;

CREATE OR REPLACE FUNCTION sprestaurant_report_pnl_expenses(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(expense_category TEXT, entry_count BIGINT, expense_total NUMERIC, share_pct NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH x AS (
        SELECT COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised') AS cat, COUNT(*) AS n, SUM(e.amount) AS tot
          FROM restaurantexpenses e
         WHERE e.farmid = p_farmid AND e.expensedate BETWEEN p_from AND p_to
           AND COALESCE(e.status, 'Approved') NOT IN ('Rejected', 'Draft')
         GROUP BY 1
        UNION ALL
        SELECT 'Loan interest & fees', COUNT(*), SUM(lp.interestamount + lp.feeamount)
          FROM restaurantloanpayments lp
         WHERE lp.farmid = p_farmid AND lp.status = 'Posted' AND lp.paymentdate BETWEEN p_from AND p_to
        HAVING SUM(lp.interestamount + lp.feeamount) > 0
        UNION ALL
        SELECT 'Staff wages (payroll)', COUNT(*), SUM(r.totalgross)
          FROM restaurantpayrollruns r
         WHERE r.farmid = p_farmid AND r.status = 'Paid' AND r.paydate BETWEEN p_from AND p_to
        HAVING COALESCE(SUM(r.totalgross), 0) <> 0
        UNION ALL
        SELECT 'Interest on staff loans (income)', COUNT(*), -SUM(sr.interestamount)
          FROM restaurantstaffloanrepayments sr
         WHERE sr.farmid = p_farmid AND sr.status = 'Posted' AND sr.repaymentdate BETWEEN p_from AND p_to
        HAVING COALESCE(SUM(sr.interestamount), 0) <> 0
        UNION ALL
        SELECT 'Cash over / short', COUNT(*), -SUM(t.amount)
          FROM restaurantcashtransactions t
         WHERE t.farmid = p_farmid AND t.sourcetype IN ('ShiftVariance', 'CountVariance', 'CountVarianceReversal')
           AND t.txndate BETWEEN p_from AND p_to
        HAVING COALESCE(SUM(t.amount), 0) <> 0
        UNION ALL
        -- 328: depreciation, a non-cash cost.
        SELECT 'Depreciation', COUNT(*), SUM(d.amount)
          FROM restaurantassetdepreciation d
         WHERE d.farmid = p_farmid AND d.depreciationdate BETWEEN p_from AND p_to
        HAVING COALESCE(SUM(d.amount), 0) <> 0
    ), tot AS (SELECT COALESCE(SUM(x.tot), 0) AS allv FROM x)
    SELECT x.cat, x.n, ROUND(x.tot, 2),
           CASE WHEN tot.allv <> 0 THEN ROUND(x.tot / tot.allv * 100, 2) ELSE 0 END
      FROM x, tot
     ORDER BY x.tot DESC;
$$;

CREATE OR REPLACE FUNCTION sprestaurant_report_cash_profit_bridge(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(sortorder INT, linekey TEXT, label TEXT, amount NUMERIC, kind TEXT, explanation TEXT)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    v_profit NUMERIC; v_rev NUMERIC; v_cogs NUMERIC; v_exp_pl NUMERIC;
    v_tax NUMERIC; v_tips NUMERIC; v_gift_paid NUMERIC; v_sales_cash NUMERIC;
    v_gift_sold NUMERIC; v_exp_cash NUMERIC; v_loan_int NUMERIC; v_loan_cash NUMERIC;
    v_loan_in NUMERIC; v_owner NUMERIC; v_var NUMERIC; v_net NUMERIC;
    v_sales_timing NUMERIC; v_exp_timing NUMERIC; v_principal NUMERIC;
    v_wages_pl NUMERIC; v_wages_cash NUMERIC; v_slint NUMERIC; v_adv_out NUMERIC; v_adv_in NUMERIC;
    v_dep NUMERIC; v_asset_buy NUMERIC; v_asset_sold NUMERIC;
BEGIN
    SELECT s.net_profit, s.revenue, s.cogs INTO v_profit, v_rev, v_cogs
      FROM sprestaurant_report_pnl_summary(p_farmid, p_from, p_to) s;

    -- Staff wages (326) are bridged on their own line, not as expense timing.
    SELECT COALESCE(-SUM(l.amount) FILTER (WHERE l.section = 'Expenses' AND l.linekey <> 'staff_wages'), 0),
           COALESCE(-SUM(l.amount) FILTER (WHERE l.linekey IN ('loan_interest', 'loan_fees')), 0),
           COALESCE(SUM(l.amount) FILTER (WHERE l.linekey = 'cash_variance'), 0)
      INTO v_exp_pl, v_loan_int, v_var
      FROM sprestaurant_report_pnl_lines(p_farmid, p_from, p_to) l;

    SELECT COALESCE(-SUM(l.amount) FILTER (WHERE l.linekey = 'staff_wages'), 0),
           COALESCE(SUM(l.amount) FILTER (WHERE l.linekey = 'staff_loan_interest'), 0),
           -- 328: depreciation is in profit and moved no cash.
           COALESCE(-SUM(l.amount) FILTER (WHERE l.linekey = 'depreciation'), 0)
      INTO v_wages_pl, v_slint, v_dep
      FROM sprestaurant_report_pnl_lines(p_farmid, p_from, p_to) l;

    SELECT COALESCE(-SUM(t.amount) FILTER (WHERE t.sourcetype = 'Payroll'), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('EmployeeLoanDisbursement', 'EmployeeLoanReversal')), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('EmployeeLoanRepayment', 'EmployeeLoanRepaymentReversal')), 0),
           -- 328: capital purchases (net of corrections and reversals) and disposal proceeds.
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('AssetPurchase', 'AssetPurchaseReversal')), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype = 'AssetDisposal'), 0)
      INTO v_wages_cash, v_adv_out, v_adv_in, v_asset_buy, v_asset_sold
      FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.txndate BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(o.taxamount), 0) INTO v_tax FROM restaurantorders o
     WHERE o.farmid = p_farmid AND o.status = 'Completed' AND o.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(t.amount), 0) INTO v_sales_cash FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.sourcetype IN ('OrderPayment', 'OrderRefund')
       AND t.txndate BETWEEN p_from AND p_to;
    SELECT COALESCE(SUM(p.tipamount), 0) INTO v_tips FROM restaurantorderpayments p
     WHERE p.farmid = p_farmid AND p.status = 'Completed' AND p.amount > 0
       AND p.createdat::DATE BETWEEN p_from AND p_to;
    SELECT COALESCE(SUM(p.amount), 0) INTO v_gift_paid FROM restaurantorderpayments p
     WHERE p.farmid = p_farmid AND p.status = 'Completed' AND p.amount > 0
       AND NOT fnrestaurant_is_cash_method(p.paymentmethod)
       AND p.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('GiftCardSale', 'GiftCardReload')), 0),
           COALESCE(-SUM(t.amount) FILTER (WHERE t.sourcetype IN ('Expense', 'ExpenseReversal')), 0),
           COALESCE(-SUM(t.amount) FILTER (WHERE t.sourcetype IN ('LoanRepayment', 'LoanRepaymentReversal')), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('LoanReceived', 'LoanReceivedReversal')), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype LIKE 'Owner%'), 0)
      INTO v_gift_sold, v_exp_cash, v_loan_cash, v_loan_in, v_owner
      FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.txndate BETWEEN p_from AND p_to;

    SELECT s.netcashflow INTO v_net
      FROM sprestaurantcashflow_summary(p_farmid, p_from::TIMESTAMP, (p_to + 1)::TIMESTAMP - INTERVAL '1 microsecond') s;

    v_sales_timing := v_sales_cash - (v_rev + v_tax + v_tips - v_gift_paid);
    v_exp_timing := v_exp_pl - v_exp_cash;
    v_principal := v_loan_cash - v_loan_int;

    RETURN QUERY VALUES
        (10, 'net_profit', 'Net profit (from the P&L)', ROUND(v_profit, 2), 'start',
         'Revenue less cost of goods, expenses, loan costs and cash over/short.'),
        (20, 'cogs', 'Add back: recipe cost of food sold', ROUND(v_cogs, 2), 'adjust',
         'The P&L charges ingredient cost when food is sold; the cash left when stock was bought (recorded as expenses).'),
        (30, 'tax', 'Add: tax collected from customers', ROUND(v_tax, 2), 'adjust',
         'Customers paid it, but it is owed to the tax office, so it is not revenue.'),
        (40, 'tips', 'Add: tips received', ROUND(v_tips, 2), 'adjust',
         'Tips come into the till but belong to staff, so they are not revenue.'),
        (50, 'gift_paid', 'Less: sales paid with gift cards', ROUND(-v_gift_paid, 2), 'adjust',
         'Revenue with no cash today — the cash came in when the card was sold.'),
        (60, 'gift_sold', 'Add: gift cards sold and reloaded', ROUND(v_gift_sold, 2), 'adjust',
         'Cash received for food not yet served. It becomes revenue when the card is used.'),
        (70, 'sales_timing', 'Sales timing differences', ROUND(v_sales_timing, 2), 'adjust',
         'Payments taken this period for orders counted in another period (or the reverse), and full refunds.'),
        (80, 'expense_timing', 'Expense timing differences', ROUND(v_exp_timing, 2), 'adjust',
         'Expenses counted in the P&L but paid in another period, or paid without a cash movement.'),
        (90, 'loan_in', 'Add: loans received', ROUND(v_loan_in, 2), 'adjust',
         'Borrowed money is cash in but not income.'),
        (100, 'loan_principal', 'Less: loan principal repaid', ROUND(-v_principal, 2), 'adjust',
         'Paying back what was borrowed is cash out but not a cost. Interest and fees are already in the P&L.'),
        (110, 'owner', 'Add: owner money (contributions less drawings)', ROUND(v_owner, 2), 'adjust',
         'Owner money moves cash but is never income or expense.'),
        (120, 'wages_withheld', 'Add back: wages not paid out in cash', ROUND(v_wages_pl - v_wages_cash, 2), 'adjust',
         'The P&L charges gross wages; only net pay left the till. The rest repaid staff loans or was withheld.'),
        (130, 'staff_advances_out', 'Less: staff advances paid out', ROUND(v_adv_out, 2), 'adjust',
         'Money lent to staff is cash out but not a cost: they owe it back.'),
        (140, 'staff_advances_in', 'Add: staff advances repaid in cash', ROUND(v_adv_in, 2), 'adjust',
         'Staff paying back an advance is cash in but not income.'),
        (150, 'staff_loan_interest', 'Less: interest on staff loans (already in profit)', ROUND(-v_slint, 2), 'adjust',
         'Interest is counted in net profit; its cash is inside the repayment and wage lines above.'),
        (160, 'depreciation', 'Add back: depreciation', ROUND(v_dep, 2), 'adjust',
         'Depreciation is a real cost of the period that moves no money.'),
        (170, 'capital_investments', 'Less: capital investments paid for', ROUND(v_asset_buy, 2), 'adjust',
         'Buying equipment, furniture or a vehicle is cash out but not charged against profit — its cost reaches the P&L through depreciation.'),
        (180, 'asset_disposals', 'Add: proceeds from assets disposed of', ROUND(v_asset_sold, 2), 'adjust',
         'Money received for selling an asset is cash in but not sales revenue.'),
        (200, 'net_cash', 'Net cash flow (from Cash Flow)', ROUND(v_net, 2), 'result',
         'Money in less money out across every account, transfers excluded.'),
        (210, 'check', 'Unexplained', ROUND(v_net - (v_profit + v_cogs + v_tax + v_tips - v_gift_paid + v_gift_sold
                                                   + v_sales_timing + v_exp_timing + v_loan_in - v_principal + v_owner
                                                   + (v_wages_pl - v_wages_cash) + v_adv_out + v_adv_in - v_slint
                                                   + v_dep + v_asset_buy + v_asset_sold), 2),
         'check', 'Should be zero. Anything else is a ledger row this bridge does not classify yet.');
END $$;

-- -----------------------------------------------------------------------------
-- 15. Verification (read-only)
-- -----------------------------------------------------------------------------
DO $$
DECLARE v_missing TEXT;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
      FROM unnest(ARRAY[
            'fnrestaurantasset_totalcost', 'fnrestaurantasset_acquisitioncost', 'fnrestaurantasset_additionalcost',
            'fnrestaurantasset_accumulated', 'fnrestaurantasset_monthly', 'fnrestaurantasset_financials',
            'fnrestaurantasset_refreshstatus', 'fnrestaurantasset_postcost',
            'sprestaurant_assetcategory_ensuredefaults', 'sprestaurant_assetcategory_list', 'sprestaurant_assetcategory_upsert',
            'sprestaurant_capitalasset_create', 'sprestaurant_capitalasset_update', 'sprestaurant_capitalasset_addcost',
            'sprestaurant_capitalasset_correctoriginalcost', 'sprestaurant_capitalasset_cost_reverse',
            'sprestaurant_capitalasset_dispose', 'sprestaurant_capitalasset_reverse', 'sprestaurant_capitalasset_list',
            'sprestaurant_capitalasset_costs', 'sprestaurant_capitalasset_summary', 'sprestaurant_capitalasset_payables',
            'fnrestaurant_assetdepreciation_post', 'sprestaurant_assetdepreciation_generate',
            'sprestaurant_assetdepreciation_reverse', 'sprestaurant_assetdepreciation_adjust',
            'sprestaurant_assetdepreciation_list', 'sprestaurant_assetdepreciation_due',
            'sprestaurantcashflow_detail', 'sprestaurant_report_pnl_lines', 'sprestaurant_report_pnl_expenses',
            'sprestaurant_report_cash_profit_bridge']) f
     WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND p.proname = f);
    IF v_missing IS NOT NULL THEN RAISE EXCEPTION '328 verification failed, missing: %', v_missing; END IF;
    -- No asset source type may look like financing to the Cash Flow classifier.
    IF 'AssetPurchase' LIKE 'Loan%' OR 'AssetPurchase' LIKE 'Owner%' THEN
        RAISE EXCEPTION '328 verification failed: asset source types would classify as financing'; END IF;
END $$;

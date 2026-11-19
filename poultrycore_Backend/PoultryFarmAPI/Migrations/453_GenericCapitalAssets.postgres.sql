-- 453_GenericCapitalAssets.postgres.sql
--
-- Capital Investments/Assets for the Generic company type, ported from Water's
-- asset register (283, 284, 286, 314) so the Generic page reads and behaves like
-- Poultry's and Water's, but on Generic's own tables.
--
-- WHAT IS DIFFERENT FROM WATER, AND WHY
-- --------------------------------------
-- Water posts every acquisition as a waterexpenses row (financialcosttype
-- 'CapitalAsset') and lets readers skip it. genericexpenses has no such column,
-- and many Generic readers (P&L, expense reports, the dashboard, the cash flow's
-- expense arm) would count a capital purchase as an operating expense. So here
-- the COST LINE ITSELF is the document:
--   * the part paid now leaves a cash account through fngenericcash_move
--     (sourcetype 'CapitalAsset' / 'CapitalAssetCost'), never through an expense;
--   * the unpaid part is owed to the supplier through a new 'CapitalAsset' arm of
--     fngenericpayables (documentid = the cost line), so Supplier Balances, open
--     bills and Supplier Payments see it, and fngenericpayable_addpaid settles it;
--   * depreciation is still a NonCash, Approved genericexpenses row (sourcetype
--     'AssetDepreciation'), which is what the Generic P&L already reads;
--   * disposal proceeds come in through fngenericcash_move ('AssetDisposal').
-- Cash flow gets one arm for the asset cash movements and one for supplier
-- payments applied to asset bills, so each amount is counted exactly once.
--
-- The old one-table register ("GenericAssets") is copied in (marked migrated),
-- spgenericasset_list keeps working over the new tables, and the old writers
-- refuse with a pointer to the new page.

-- =============================================================================
-- 1. Tables
-- =============================================================================
CREATE TABLE IF NOT EXISTS genericassetcategories (
    genericassetcategoryid  serial PRIMARY KEY,
    farmid                  text NOT NULL,
    categoryname            text NOT NULL,
    defaultusefullifemonths integer,
    sortorder               integer NOT NULL DEFAULT 0,
    isactive                boolean NOT NULL DEFAULT TRUE,
    createdby               text,
    createdat               timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericassetcategories_farm_name
    ON genericassetcategories (farmid, lower(categoryname));

CREATE TABLE IF NOT EXISTS genericcapitalassets (
    genericcapitalassetid  serial PRIMARY KEY,
    farmid                 text NOT NULL,
    assetnumber            text NOT NULL,
    assetname              text NOT NULL,
    genericassetcategoryid integer REFERENCES genericassetcategories (genericassetcategoryid),
    description            text,
    acquisitiondate        date NOT NULL,
    inservicedate          date,
    residualvalue          numeric(14,2) NOT NULL DEFAULT 0,
    usefullifemonths       integer,
    depreciationmethod     text NOT NULL DEFAULT 'StraightLine',
    supplierid             integer,
    location               text,
    serialnumber           text,
    status                 text NOT NULL DEFAULT 'Draft'
                           CHECK (status IN ('Draft', 'Active', 'FullyDepreciated', 'Disposed', 'Reversed')),
    notes                  text,
    disposaldate           date,
    disposalproceeds       numeric(14,2),
    disposalcashaccountid  integer,
    disposalnotes          text,
    legacygenericassetid   integer,
    createdby              text,
    createdat              timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updatedby              text,
    updatedat              timestamp,
    reversedby             text,
    reversedat             timestamp,
    reversalreason         text
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericcapitalassets_farm_number
    ON genericcapitalassets (farmid, assetnumber);
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericcapitalassets_legacy
    ON genericcapitalassets (legacygenericassetid) WHERE legacygenericassetid IS NOT NULL;

CREATE TABLE IF NOT EXISTS genericcapitalassetcosts (
    genericcapitalassetcostid serial PRIMARY KEY,
    farmid                    text NOT NULL,
    genericcapitalassetid     integer NOT NULL REFERENCES genericcapitalassets (genericcapitalassetid),
    costdate                  date NOT NULL,
    description               text,
    costcategory              text,
    amount                    numeric(14,2) NOT NULL,
    sourcetype                text NOT NULL
                              CHECK (sourcetype IN ('Acquisition', 'AdditionalCost', 'OriginalCostCorrection')),
    -- A correction points at the acquisition line it corrects; the bill owed to
    -- the supplier is that line's amount plus its corrections.
    parentcostid              integer REFERENCES genericcapitalassetcosts (genericcapitalassetcostid),
    supplierid                integer,
    paymentmethod             text,
    -- What has been paid on this line: at purchase, plus supplier payments
    -- applied later (fngenericpayable_addpaid). Always 0 on a correction line.
    amountpaid                numeric(14,2) NOT NULL DEFAULT 0,
    duedate                   date,
    genericcashaccountid      integer,
    status                    text NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),
    createdby                 text,
    createdat                 timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    reversedby                text,
    reversedat                timestamp,
    reversalreason            text
);
CREATE INDEX IF NOT EXISTS ix_genericcapitalassetcosts_asset ON genericcapitalassetcosts (genericcapitalassetid);
CREATE INDEX IF NOT EXISTS ix_genericcapitalassetcosts_farm_supplier
    ON genericcapitalassetcosts (farmid, supplierid) WHERE supplierid IS NOT NULL;

CREATE TABLE IF NOT EXISTS genericassetdepreciation (
    genericassetdepreciationid serial PRIMARY KEY,
    farmid                     text NOT NULL,
    genericcapitalassetid      integer NOT NULL REFERENCES genericcapitalassets (genericcapitalassetid),
    periodstart                date NOT NULL,
    periodend                  date NOT NULL,
    depreciationdate           date NOT NULL,
    amount                     numeric(14,2) NOT NULL,
    depreciationmethod         text NOT NULL DEFAULT 'StraightLine',
    sourcetype                 text NOT NULL CHECK (sourcetype IN ('Scheduled', 'ManualAdjustment', 'Reversal')),
    status                     text NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),
    genericexpenseid           integer,
    reversalofid               integer REFERENCES genericassetdepreciation (genericassetdepreciationid),
    createdby                  text,
    createdat                  timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    reversedby                 text,
    reversedat                 timestamp,
    reversalreason             text
);
CREATE INDEX IF NOT EXISTS ix_genericassetdepreciation_asset ON genericassetdepreciation (genericcapitalassetid);
-- One scheduled charge per asset per month, ever (a reversed month is not
-- re-posted by the generator; /adjust re-posts a corrected amount).
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericassetdepreciation_scheduled
    ON genericassetdepreciation (genericcapitalassetid, periodstart) WHERE sourcetype = 'Scheduled';

ALTER TABLE "GenericAssets" ADD COLUMN IF NOT EXISTS "MigratedToAssetId" integer;

-- =============================================================================
-- 2. Financial helpers (one definition of cost, book value and what is owed)
-- =============================================================================
CREATE OR REPLACE FUNCTION fngenericcapitalasset_monthly(p_originalcost numeric, p_residual numeric, p_lifemonths integer)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $fn$
    SELECT ROUND(GREATEST(COALESCE(p_originalcost, 0) - COALESCE(p_residual, 0), 0)
                 / NULLIF(p_lifemonths, 0), 2);
$fn$;

CREATE OR REPLACE FUNCTION fngenericcapitalasset_originalcost(p_assetid integer)
RETURNS numeric LANGUAGE sql STABLE AS $fn$
    SELECT COALESCE(SUM(c.amount), 0)::numeric(14,2)
    FROM   genericcapitalassetcosts c
    WHERE  c.genericcapitalassetid = p_assetid AND c.status = 'Posted';
$fn$;

CREATE OR REPLACE FUNCTION fngenericcapitalasset_acquisitioncost(p_assetid integer)
RETURNS numeric LANGUAGE sql STABLE AS $fn$
    SELECT COALESCE(SUM(c.amount), 0)::numeric(14,2)
    FROM   genericcapitalassetcosts c
    WHERE  c.genericcapitalassetid = p_assetid AND c.status = 'Posted'
      AND  c.sourcetype IN ('Acquisition', 'OriginalCostCorrection');
$fn$;

CREATE OR REPLACE FUNCTION fngenericcapitalasset_additionalcost(p_assetid integer)
RETURNS numeric LANGUAGE sql STABLE AS $fn$
    SELECT COALESCE(SUM(c.amount), 0)::numeric(14,2)
    FROM   genericcapitalassetcosts c
    WHERE  c.genericcapitalassetid = p_assetid AND c.status = 'Posted'
      AND  c.sourcetype NOT IN ('Acquisition', 'OriginalCostCorrection');
$fn$;

CREATE OR REPLACE FUNCTION fngenericcapitalasset_accumulated(p_assetid integer)
RETURNS numeric LANGUAGE sql STABLE AS $fn$
    -- Signed sum over an append-only ledger: a reversal is a negative row.
    SELECT COALESCE(SUM(d.amount), 0)::numeric(14,2)
    FROM   genericassetdepreciation d
    WHERE  d.genericcapitalassetid = p_assetid;
$fn$;

-- The bill a cost line represents: its own amount plus the posted corrections
-- that point at it.
CREATE OR REPLACE FUNCTION fngenericcapitalassetcost_billtotal(p_costid integer)
RETURNS numeric LANGUAGE sql STABLE AS $fn$
    SELECT (c.amount + COALESCE((SELECT SUM(k.amount) FROM genericcapitalassetcosts k
                                  WHERE k.parentcostid = c.genericcapitalassetcostid
                                    AND k.status = 'Posted'
                                    AND k.sourcetype = 'OriginalCostCorrection'), 0))::numeric(14,2)
    FROM   genericcapitalassetcosts c
    WHERE  c.genericcapitalassetcostid = p_costid;
$fn$;

CREATE OR REPLACE FUNCTION fngenericcapitalasset_financials(p_assetid integer)
RETURNS TABLE(originalcost numeric, residualvalue numeric, depreciableamount numeric, usefullifemonths integer,
              monthlydepreciation numeric, accumulateddepreciation numeric, currentbookvalue numeric,
              remainingdepreciable numeric, isfullydepreciated boolean)
LANGUAGE sql STABLE AS $fn$
    SELECT o.cost,
           a.residualvalue,
           GREATEST(o.cost - a.residualvalue, 0)::numeric(14,2),
           a.usefullifemonths,
           fngenericcapitalasset_monthly(o.cost, a.residualvalue, a.usefullifemonths),
           d.acc,
           -- Book value never falls below residual value.
           GREATEST(o.cost - d.acc, a.residualvalue)::numeric(14,2),
           GREATEST(GREATEST(o.cost - a.residualvalue, 0) - d.acc, 0)::numeric(14,2),
           (GREATEST(o.cost - a.residualvalue, 0) - d.acc) <= 0.004
    FROM   genericcapitalassets a
    CROSS  JOIN LATERAL (SELECT fngenericcapitalasset_originalcost(a.genericcapitalassetid) AS cost) o
    CROSS  JOIN LATERAL (SELECT fngenericcapitalasset_accumulated(a.genericcapitalassetid) AS acc) d
    WHERE  a.genericcapitalassetid = p_assetid;
$fn$;

CREATE OR REPLACE FUNCTION fngenericdepreciationcategory(p_farmid text)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE v_catid integer;
BEGIN
    SELECT ec.genericexpensecategoryid INTO v_catid
    FROM   genericexpensecategories ec
    WHERE  ec.farmid = p_farmid AND lower(ec.name) = 'depreciation'
    ORDER  BY COALESCE(ec.isdeleted, FALSE), ec.genericexpensecategoryid
    LIMIT  1;
    IF v_catid IS NULL THEN
        INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted)
        VALUES (p_farmid, 'Depreciation', TRUE, FALSE)
        RETURNING genericexpensecategoryid INTO v_catid;
    END IF;
    RETURN v_catid;
END;
$fn$;

-- Keeps Active / FullyDepreciated honest after anything that moves book value.
CREATE OR REPLACE FUNCTION fngenericcapitalasset_refreshstatus(p_farmid text, p_assetid integer DEFAULT NULL)
RETURNS void LANGUAGE sql AS $fn$
    UPDATE genericcapitalassets ca
    SET    status = s.newstatus, updatedat = (now() AT TIME ZONE 'utc')
    FROM  (SELECT x.genericcapitalassetid AS id,
                  CASE WHEN f.isfullydepreciated THEN 'FullyDepreciated' ELSE 'Active' END AS newstatus
           FROM   genericcapitalassets x
           CROSS  JOIN LATERAL fngenericcapitalasset_financials(x.genericcapitalassetid) f
           WHERE  x.farmid = p_farmid
             AND  (p_assetid IS NULL OR x.genericcapitalassetid = p_assetid)
             AND  x.status IN ('Active', 'FullyDepreciated')) s
    WHERE  ca.genericcapitalassetid = s.id AND ca.status <> s.newstatus;
$fn$;

-- =============================================================================
-- 3. Categories
-- =============================================================================
CREATE OR REPLACE FUNCTION spgenericassetcategory_ensuredefaults(p_farmid text, p_createdby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
    INSERT INTO genericassetcategories (farmid, categoryname, defaultusefullifemonths, sortorder, createdby)
    SELECT p_farmid, d.name, d.life, d.ord, p_createdby
    FROM  (VALUES
              ('Land & Buildings',          240, 1),
              ('Leasehold Improvements',    120, 2),
              ('Machinery & Equipment',      84, 3),
              ('Vehicles',                   60, 4),
              ('Generators',                 84, 5),
              ('Furniture & Fittings',       60, 6),
              ('IT / Computer Equipment',    36, 7),
              ('Office Equipment',           60, 8),
              ('Tools',                      36, 9),
              ('Other Assets',               60, 10)
          ) AS d(name, life, ord)
    WHERE NOT EXISTS (SELECT 1 FROM genericassetcategories c
                      WHERE c.farmid = p_farmid AND lower(c.categoryname) = lower(d.name));
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericassetcategory_getall(p_farmid text)
RETURNS TABLE(genericassetcategoryid integer, farmid text, categoryname text, defaultusefullifemonths integer,
              sortorder integer, isactive boolean, assetcount integer)
LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM spgenericassetcategory_ensuredefaults(p_farmid, NULL);
    RETURN QUERY
    SELECT c.genericassetcategoryid, c.farmid::text, c.categoryname::text,
           c.defaultusefullifemonths, c.sortorder, c.isactive,
           (SELECT COUNT(*)::integer FROM genericcapitalassets a
             WHERE a.genericassetcategoryid = c.genericassetcategoryid AND a.status <> 'Reversed')
    FROM   genericassetcategories c
    WHERE  c.farmid = p_farmid
    ORDER  BY c.sortorder, c.categoryname;
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericassetcategory_upsert(p_farmid text, p_genericassetcategoryid integer, p_categoryname text,
    p_defaultusefullifemonths integer DEFAULT NULL, p_isactive boolean DEFAULT TRUE, p_createdby text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE v_id integer := p_genericassetcategoryid;
BEGIN
    IF COALESCE(btrim(p_categoryname), '') = '' THEN
        RAISE EXCEPTION 'Category name is required.';
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO genericassetcategories (farmid, categoryname, defaultusefullifemonths, sortorder, isactive, createdby)
        VALUES (p_farmid, btrim(p_categoryname), p_defaultusefullifemonths,
                COALESCE((SELECT MAX(c.sortorder) + 1 FROM genericassetcategories c WHERE c.farmid = p_farmid), 1),
                COALESCE(p_isactive, TRUE), p_createdby)
        RETURNING genericassetcategoryid INTO v_id;
    ELSE
        UPDATE genericassetcategories c
        SET    categoryname = btrim(p_categoryname),
               defaultusefullifemonths = p_defaultusefullifemonths,
               isactive = COALESCE(p_isactive, c.isactive)
        WHERE  c.genericassetcategoryid = v_id AND c.farmid = p_farmid;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Asset category does not belong to this company.';
        END IF;
    END IF;
    RETURN v_id;
END;
$fn$;

-- =============================================================================
-- 4. The money leg of a cost line (acquisition or additional cost)
-- =============================================================================
-- Validates the payment, takes the paid part out of cash and puts the unpaid
-- part on the supplier. Writes the paid amount, method, account and due date
-- onto the cost line, which is the document.
CREATE OR REPLACE FUNCTION spgenericcapitalassetcost_paylegs(p_farmid text, p_costid integer, p_paymentmethod text,
    p_amountpaid numeric, p_duedate date, p_cashaccountid integer, p_createdby text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    c        genericcapitalassetcosts%ROWTYPE;
    v_name   text;
    v_method text := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
    v_paid   numeric(14,2);
    v_acct   integer := p_cashaccountid;
    v_src    text;
    v_srcid  integer;
BEGIN
    SELECT * INTO c FROM genericcapitalassetcosts WHERE genericcapitalassetcostid = p_costid AND farmid = p_farmid;
    SELECT a.assetname INTO v_name FROM genericcapitalassets a WHERE a.genericcapitalassetid = c.genericcapitalassetid;

    -- A Credit purchase is unpaid until a supplier payment settles it.
    v_paid := ROUND(CASE WHEN v_method = 'Credit' THEN COALESCE(p_amountpaid, 0)
                         ELSE COALESCE(p_amountpaid, c.amount) END, 2);
    IF v_paid < 0 THEN
        RAISE EXCEPTION 'Amount paid cannot be negative.';
    END IF;
    IF v_paid > c.amount THEN
        RAISE EXCEPTION 'Amount paid (%) cannot exceed the asset cost (%).', v_paid, c.amount;
    END IF;
    IF c.supplierid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM genericsuppliers s
                       WHERE s.genericsupplierid = c.supplierid AND s.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;
    IF v_paid < c.amount AND c.supplierid IS NULL THEN
        RAISE EXCEPTION 'Select the supplier who is owed the unpaid % of this cost.', (c.amount - v_paid)::numeric(14,2);
    END IF;

    -- The account the user chose, else the company's first active one.
    IF v_acct IS NULL AND v_paid > 0 THEN
        SELECT a.genericcashaccountid INTO v_acct
        FROM   genericcashaccounts a
        WHERE  a.farmid = p_farmid AND a.isactive = TRUE
        ORDER  BY a.genericcashaccountid LIMIT 1;
        IF v_acct IS NULL THEN
            RAISE EXCEPTION 'Select the cash account the payment came from.';
        END IF;
    END IF;

    UPDATE genericcapitalassetcosts
    SET    paymentmethod = v_method, amountpaid = v_paid, duedate = p_duedate,
           genericcashaccountid = CASE WHEN v_paid > 0 THEN v_acct ELSE NULL END
    WHERE  genericcapitalassetcostid = p_costid;

    IF c.sourcetype = 'Acquisition' THEN v_src := 'CapitalAsset'; v_srcid := c.genericcapitalassetid;
    ELSE v_src := 'CapitalAssetCost'; v_srcid := c.genericcapitalassetcostid; END IF;

    -- Money out, refused if the account would go below what it allows.
    IF v_paid > 0 THEN
        PERFORM fngenericcash_move(p_farmid, v_acct, -v_paid, c.costdate::timestamp, v_src, v_srcid,
            COALESCE(NULLIF(btrim(c.description), ''), v_name, 'Capital asset'), p_createdby, TRUE);
    END IF;
    -- The unpaid part is owed to the supplier.
    IF c.supplierid IS NOT NULL AND c.amount - v_paid > 0 THEN
        PERFORM fngenericsupplier_ledgermove(p_farmid, c.supplierid, c.amount - v_paid, 'AssetPurchase',
            'Capital asset: ' || COALESCE(v_name, ''), p_createdby);
    END IF;
END;
$fn$;

-- Hands back a cost line's money: the part paid at purchase returns to its cash
-- account, what was still owed comes off the supplier. Refused by the callers
-- if any supplier payment was applied to it.
CREATE OR REPLACE FUNCTION spgenericcapitalassetcost_unwind(p_farmid text, p_costid integer, p_description text, p_createdby text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    c       genericcapitalassetcosts%ROWTYPE;
    v_total numeric(14,2);
BEGIN
    SELECT * INTO c FROM genericcapitalassetcosts WHERE genericcapitalassetcostid = p_costid AND farmid = p_farmid;
    IF c.sourcetype = 'OriginalCostCorrection' THEN RETURN; END IF;
    v_total := fngenericcapitalassetcost_billtotal(p_costid);
    IF c.amountpaid > 0 AND c.genericcashaccountid IS NOT NULL THEN
        PERFORM fngenericcash_move(p_farmid, c.genericcashaccountid, c.amountpaid, (now() AT TIME ZONE 'utc'),
            CASE WHEN c.sourcetype = 'Acquisition' THEN 'CapitalAsset' ELSE 'CapitalAssetCost' END,
            CASE WHEN c.sourcetype = 'Acquisition' THEN c.genericcapitalassetid ELSE c.genericcapitalassetcostid END,
            p_description, p_createdby);
    END IF;
    IF c.supplierid IS NOT NULL AND v_total - c.amountpaid > 0 THEN
        PERFORM fngenericsupplier_ledgermove(p_farmid, c.supplierid, -(v_total - c.amountpaid), 'AssetPurchaseReversal',
            p_description, p_createdby);
    END IF;
    UPDATE genericcapitalassetcosts SET amountpaid = 0 WHERE genericcapitalassetcostid = p_costid;
END;
$fn$;

-- =============================================================================
-- 5. Assets
-- =============================================================================
CREATE OR REPLACE FUNCTION spgenericcapitalasset_create(p_farmid text, p_assetname text,
    p_assetcategoryid integer DEFAULT NULL, p_description text DEFAULT NULL, p_acquisitiondate date DEFAULT NULL,
    p_inservicedate date DEFAULT NULL, p_amount numeric DEFAULT NULL, p_residualvalue numeric DEFAULT 0,
    p_usefullifemonths integer DEFAULT NULL, p_supplierid integer DEFAULT NULL, p_paymentmethod text DEFAULT 'Cash',
    p_amountpaid numeric DEFAULT NULL, p_duedate date DEFAULT NULL, p_cashaccountid integer DEFAULT NULL,
    p_expensecategory text DEFAULT NULL, p_location text DEFAULT NULL, p_serialnumber text DEFAULT NULL,
    p_notes text DEFAULT NULL, p_createdby text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE
    v_id     integer;
    v_number text;
    v_date   date := COALESCE(p_acquisitiondate, (now() AT TIME ZONE 'utc')::date);
    v_status text;
    v_costid integer;
BEGIN
    IF COALESCE(btrim(p_assetname), '') = '' THEN
        RAISE EXCEPTION 'Asset name is required.';
    END IF;
    IF p_amount IS NOT NULL AND p_amount <= 0 THEN
        RAISE EXCEPTION 'Asset cost must be greater than 0.';
    END IF;
    IF p_assetcategoryid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM genericassetcategories c
                       WHERE c.genericassetcategoryid = p_assetcategoryid AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Asset category does not belong to this company.';
    END IF;
    IF p_inservicedate IS NOT NULL AND p_inservicedate < v_date THEN
        RAISE EXCEPTION 'An asset cannot be in service before it was acquired.';
    END IF;
    IF COALESCE(p_residualvalue, 0) < 0 THEN
        RAISE EXCEPTION 'Residual value cannot be negative.';
    END IF;
    IF COALESCE(p_amount, 0) > 0 AND COALESCE(p_residualvalue, 0) > p_amount THEN
        RAISE EXCEPTION 'Residual value (%) cannot be more than the asset cost (%).',
              p_residualvalue::numeric(14,2), p_amount::numeric(14,2);
    END IF;

    -- Per-company running number under a company-wide lock, so two saves at
    -- once cannot both claim AST-0007.
    PERFORM pg_advisory_xact_lock(hashtext('genericcapitalassets:' || p_farmid));
    SELECT 'AST-' || lpad((COALESCE(MAX(substring(a.assetnumber from '[0-9]+$')::integer), 0) + 1)::text, 4, '0')
      INTO v_number
    FROM   genericcapitalassets a
    WHERE  a.farmid = p_farmid AND a.assetnumber ~ '^AST-[0-9]+$';
    v_number := COALESCE(v_number, 'AST-0001');

    v_status := CASE WHEN p_inservicedate IS NOT NULL AND COALESCE(p_usefullifemonths, 0) > 0
                     THEN 'Active' ELSE 'Draft' END;

    INSERT INTO genericcapitalassets
        (farmid, assetnumber, assetname, genericassetcategoryid, description, acquisitiondate, inservicedate,
         residualvalue, usefullifemonths, depreciationmethod, supplierid, location, serialnumber, status, notes, createdby)
    VALUES
        (p_farmid, v_number, btrim(p_assetname), p_assetcategoryid, p_description, v_date, p_inservicedate,
         COALESCE(p_residualvalue, 0), p_usefullifemonths, 'StraightLine', p_supplierid, p_location,
         p_serialnumber, v_status, p_notes, p_createdby)
    RETURNING genericcapitalassetid INTO v_id;

    IF COALESCE(p_amount, 0) > 0 THEN
        INSERT INTO genericcapitalassetcosts
            (farmid, genericcapitalassetid, costdate, description, costcategory, amount, sourcetype, supplierid, createdby)
        VALUES
            (p_farmid, v_id, v_date, btrim(p_assetname), 'Acquisition', ROUND(p_amount, 2), 'Acquisition',
             p_supplierid, p_createdby)
        RETURNING genericcapitalassetcostid INTO v_costid;

        PERFORM spgenericcapitalassetcost_paylegs(p_farmid, v_costid, p_paymentmethod, p_amountpaid,
                                                  p_duedate, p_cashaccountid, p_createdby);
    END IF;

    RETURN v_id;
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericcapitalasset_update(p_farmid text, p_assetid integer, p_assetname text,
    p_assetcategoryid integer DEFAULT NULL, p_description text DEFAULT NULL, p_location text DEFAULT NULL,
    p_serialnumber text DEFAULT NULL, p_notes text DEFAULT NULL, p_inservicedate date DEFAULT NULL,
    p_usefullifemonths integer DEFAULT NULL, p_residualvalue numeric DEFAULT NULL, p_setfinancials boolean DEFAULT FALSE,
    p_updatedby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    v_status  text;
    v_acqdate date;
    v_posted  boolean;
    v_cost    numeric(14,2);
BEGIN
    SELECT a.status, a.acquisitiondate INTO v_status, v_acqdate
    FROM   genericcapitalassets a
    WHERE  a.genericcapitalassetid = p_assetid AND a.farmid = p_farmid;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;
    IF v_status = 'Reversed' THEN
        RAISE EXCEPTION 'A reversed asset cannot be edited.';
    END IF;
    IF p_assetcategoryid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM genericassetcategories c
                       WHERE c.genericassetcategoryid = p_assetcategoryid AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Asset category does not belong to this company.';
    END IF;

    v_posted := EXISTS (SELECT 1 FROM genericassetdepreciation d
                        WHERE d.genericcapitalassetid = p_assetid AND d.status = 'Posted');

    IF p_setfinancials AND v_posted THEN
        RAISE EXCEPTION 'Depreciation has already been posted for this asset, so its in-service date, useful life and residual value are locked. Reverse the depreciation first.';
    END IF;
    IF p_setfinancials AND p_inservicedate IS NOT NULL AND p_inservicedate < v_acqdate THEN
        RAISE EXCEPTION 'An asset cannot be in service before it was acquired.';
    END IF;
    IF p_setfinancials AND p_usefullifemonths IS NOT NULL AND p_usefullifemonths <= 0 THEN
        RAISE EXCEPTION 'Useful life must be at least one month.';
    END IF;
    IF p_setfinancials THEN
        v_cost := fngenericcapitalasset_originalcost(p_assetid);
        IF COALESCE(p_residualvalue, 0) < 0 THEN
            RAISE EXCEPTION 'Residual value cannot be negative.';
        END IF;
        IF p_residualvalue IS NOT NULL AND p_residualvalue > v_cost AND v_cost > 0 THEN
            RAISE EXCEPTION 'Residual value (%) cannot be more than the asset cost (%).',
                  p_residualvalue::numeric(14,2), v_cost;
        END IF;
    END IF;

    UPDATE genericcapitalassets a
    SET    assetname = COALESCE(NULLIF(btrim(p_assetname), ''), a.assetname),
           genericassetcategoryid = COALESCE(p_assetcategoryid, a.genericassetcategoryid),
           description  = p_description,
           location     = p_location,
           serialnumber = p_serialnumber,
           notes        = p_notes,
           inservicedate    = CASE WHEN p_setfinancials THEN p_inservicedate ELSE a.inservicedate END,
           usefullifemonths = CASE WHEN p_setfinancials THEN p_usefullifemonths ELSE a.usefullifemonths END,
           residualvalue    = CASE WHEN p_setfinancials THEN COALESCE(p_residualvalue, 0) ELSE a.residualvalue END,
           status = CASE WHEN a.status IN ('Draft', 'Active') AND p_setfinancials THEN
                             CASE WHEN p_inservicedate IS NOT NULL AND COALESCE(p_usefullifemonths, 0) > 0
                                  THEN 'Active' ELSE 'Draft' END
                         ELSE a.status END,
           updatedby = p_updatedby,
           updatedat = (now() AT TIME ZONE 'utc')
    WHERE  a.genericcapitalassetid = p_assetid AND a.farmid = p_farmid;

    PERFORM fngenericcapitalasset_refreshstatus(p_farmid, p_assetid);
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericcapitalassetcost_add(p_farmid text, p_assetid integer, p_costdate date,
    p_description text, p_costcategory text, p_amount numeric, p_supplierid integer DEFAULT NULL,
    p_paymentmethod text DEFAULT 'Cash', p_amountpaid numeric DEFAULT NULL, p_duedate date DEFAULT NULL,
    p_cashaccountid integer DEFAULT NULL, p_expensecategory text DEFAULT NULL, p_createdby text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE
    v_status text;
    v_name   text;
    v_id     integer;
    v_date   date := COALESCE(p_costdate, (now() AT TIME ZONE 'utc')::date);
BEGIN
    SELECT a.status, a.assetname INTO v_status, v_name
    FROM   genericcapitalassets a
    WHERE  a.genericcapitalassetid = p_assetid AND a.farmid = p_farmid;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;
    IF v_status IN ('Reversed', 'Disposed') THEN
        RAISE EXCEPTION 'Cannot add cost to a % asset.', lower(v_status);
    END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Cost amount must be greater than 0.';
    END IF;
    IF EXISTS (SELECT 1 FROM genericassetdepreciation d
               WHERE d.genericcapitalassetid = p_assetid AND d.status = 'Posted') THEN
        RAISE EXCEPTION 'Depreciation has already been posted for this asset. Reverse it before changing the asset cost.';
    END IF;

    INSERT INTO genericcapitalassetcosts
        (farmid, genericcapitalassetid, costdate, description, costcategory, amount, sourcetype, supplierid, createdby)
    VALUES
        (p_farmid, p_assetid, v_date, COALESCE(NULLIF(btrim(p_description), ''), v_name), p_costcategory,
         ROUND(p_amount, 2), 'AdditionalCost', p_supplierid, p_createdby)
    RETURNING genericcapitalassetcostid INTO v_id;

    PERFORM spgenericcapitalassetcost_paylegs(p_farmid, v_id, p_paymentmethod, p_amountpaid,
                                              p_duedate, p_cashaccountid, p_createdby);

    UPDATE genericcapitalassets a
    SET    updatedby = p_createdby, updatedat = (now() AT TIME ZONE 'utc')
    WHERE  a.genericcapitalassetid = p_assetid;
    RETURN v_id;
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericcapitalasset_correctoriginalcost(p_farmid text, p_assetid integer, p_newamount numeric,
    p_effectivedate date DEFAULT NULL, p_reason text DEFAULT NULL, p_createdby text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE
    v_status   text;
    v_name     text;
    v_residual numeric(14,2);
    v_acqcost  numeric(14,2);
    v_addcost  numeric(14,2);
    v_new      numeric(14,2) := ROUND(COALESCE(p_newamount, 0), 2);
    v_diff     numeric(14,2);
    acq        genericcapitalassetcosts%ROWTYPE;
    v_alloc    numeric(14,2);
    v_newpaid  numeric(14,2);
    v_refund   numeric(14,2);
    v_date     date := COALESCE(p_effectivedate, (now() AT TIME ZONE 'utc')::date);
    v_newid    integer;
BEGIN
    SELECT a.status, a.residualvalue, a.assetname INTO v_status, v_residual, v_name
    FROM   genericcapitalassets a
    WHERE  a.genericcapitalassetid = p_assetid AND a.farmid = p_farmid;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;
    IF v_status = 'Reversed' THEN
        RAISE EXCEPTION 'A reversed asset cannot be corrected.';
    END IF;
    IF v_status = 'Disposed' THEN
        RAISE EXCEPTION 'A disposed asset cannot be corrected.';
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to correct the original cost.';
    END IF;
    IF v_new <= 0 THEN
        RAISE EXCEPTION 'The corrected original cost must be greater than 0. To undo the acquisition entirely, reverse the asset.';
    END IF;

    v_acqcost := fngenericcapitalasset_acquisitioncost(p_assetid);
    v_addcost := fngenericcapitalasset_additionalcost(p_assetid);
    v_diff    := v_new - v_acqcost;
    IF ABS(v_diff) < 0.005 THEN
        RAISE EXCEPTION 'The original acquisition cost is already %.', v_acqcost;
    END IF;

    SELECT * INTO acq FROM genericcapitalassetcosts c
    WHERE  c.genericcapitalassetid = p_assetid AND c.farmid = p_farmid
      AND  c.sourcetype = 'Acquisition' AND c.status = 'Posted'
    ORDER  BY c.genericcapitalassetcostid LIMIT 1
    FOR UPDATE;
    IF acq.genericcapitalassetcostid IS NULL THEN
        RAISE EXCEPTION 'This asset has no original acquisition to correct -- its cost was built up with Add cost. Reverse the added cost that is wrong and add it again.';
    END IF;
    IF v_residual > (v_new + v_addcost) THEN
        RAISE EXCEPTION 'Residual value (%) cannot be more than the corrected cost (%). Lower the residual value first.',
              v_residual, (v_new + v_addcost)::numeric(14,2);
    END IF;

    -- ---- the money leg ---------------------------------------------------------
    SELECT COALESCE(SUM(sa.amountapplied), 0) INTO v_alloc
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'generic' AND sa.status = 'Posted'
      AND  sa.documenttype = 'CapitalAsset' AND sa.documentid = acq.genericcapitalassetcostid;
    IF v_alloc > v_new THEN
        RAISE EXCEPTION 'Supplier payments of % have already been recorded against this acquisition, which is more than the corrected cost of %. Reverse the payment on Supplier Payments first.',
              v_alloc, v_new;
    END IF;

    -- Only ever capped: correcting the cost up must not invent a payment.
    v_newpaid := LEAST(acq.amountpaid, v_new);
    v_refund  := GREATEST(acq.amountpaid - v_newpaid, 0);

    IF v_refund > 0 THEN
        IF acq.genericcashaccountid IS NULL THEN
            RAISE EXCEPTION 'The acquisition has no cash account to return % to.', v_refund;
        END IF;
        -- Append-only: the money comes back as its own CashIn.
        PERFORM fngenericcash_move(p_farmid, acq.genericcashaccountid, v_refund, v_date::timestamp,
            'CapitalAsset', p_assetid, 'Original cost correction — ' || COALESCE(v_name, 'capital asset'), p_createdby);
    END IF;

    -- The supplier's balance follows the corrected bill.
    IF acq.supplierid IS NOT NULL THEN
        PERFORM fngenericsupplier_ledgermove(p_farmid, acq.supplierid,
            (v_new - v_newpaid) - (v_acqcost - acq.amountpaid), 'AssetCostCorrection',
            'Original cost correction — ' || COALESCE(v_name, ''), p_createdby);
    END IF;

    UPDATE genericcapitalassetcosts SET amountpaid = v_newpaid
    WHERE  genericcapitalassetcostid = acq.genericcapitalassetcostid;

    -- ---- the record --------------------------------------------------------------
    INSERT INTO genericcapitalassetcosts
        (farmid, genericcapitalassetid, costdate, description, costcategory, amount, sourcetype,
         parentcostid, supplierid, status, createdby)
    VALUES
        (p_farmid, p_assetid, v_date, btrim(p_reason), 'Original Cost Correction', v_diff, 'OriginalCostCorrection',
         acq.genericcapitalassetcostid, acq.supplierid, 'Posted', p_createdby)
    RETURNING genericcapitalassetcostid INTO v_newid;

    UPDATE genericcapitalassets a
    SET    updatedby = p_createdby, updatedat = (now() AT TIME ZONE 'utc')
    WHERE  a.genericcapitalassetid = p_assetid AND a.farmid = p_farmid;

    PERFORM fngenericcapitalasset_refreshstatus(p_farmid, p_assetid);
    RETURN v_newid;
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericcapitalassetcost_reverse(p_farmid text, p_costid integer, p_reason text,
    p_createdby text DEFAULT NULL, p_assetid integer DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    c         genericcapitalassetcosts%ROWTYPE;
    v_astatus text;
BEGIN
    SELECT * INTO c FROM genericcapitalassetcosts
    WHERE  genericcapitalassetcostid = p_costid AND farmid = p_farmid FOR UPDATE;
    IF c.genericcapitalassetcostid IS NULL THEN
        RAISE EXCEPTION 'Cost entry not found for this company.';
    END IF;
    IF p_assetid IS NOT NULL AND p_assetid <> c.genericcapitalassetid THEN
        RAISE EXCEPTION 'That cost entry does not belong to this asset.';
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a cost.';
    END IF;
    IF c.status <> 'Posted' THEN
        RAISE EXCEPTION 'This cost has already been reversed.';
    END IF;
    IF c.sourcetype = 'Acquisition' THEN
        RAISE EXCEPTION 'This is the original acquisition. Use Correct original cost to change the amount, or reverse the whole asset.';
    END IF;
    IF c.sourcetype = 'OriginalCostCorrection' THEN
        RAISE EXCEPTION 'A correction cannot be reversed. Correct the original cost again to the amount you want.';
    END IF;

    SELECT a.status INTO v_astatus FROM genericcapitalassets a
    WHERE  a.genericcapitalassetid = c.genericcapitalassetid AND a.farmid = p_farmid;
    IF v_astatus IN ('Reversed', 'Disposed') THEN
        RAISE EXCEPTION 'Cannot change the costs of a % asset.', lower(v_astatus);
    END IF;
    IF EXISTS (SELECT 1 FROM genericassetdepreciation d
               WHERE d.genericcapitalassetid = c.genericcapitalassetid AND d.status = 'Posted') THEN
        RAISE EXCEPTION 'Depreciation has already been posted for this asset. Reverse it before changing the asset cost.';
    END IF;
    IF EXISTS (SELECT 1 FROM supplierpaymentallocation sa
               WHERE sa.farmid = p_farmid AND sa.module = 'generic' AND sa.status = 'Posted'
                 AND sa.documenttype = 'CapitalAsset' AND sa.documentid = p_costid) THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this cost. Reverse the payment on Supplier Payments first.';
    END IF;

    PERFORM spgenericcapitalassetcost_unwind(p_farmid, p_costid,
        'Reversal of capital asset cost — ' || COALESCE(c.description, ''), p_createdby);

    UPDATE genericcapitalassetcosts
    SET    status = 'Reversed', reversedby = p_createdby,
           reversedat = (now() AT TIME ZONE 'utc'), reversalreason = btrim(p_reason)
    WHERE  genericcapitalassetcostid = p_costid;

    UPDATE genericcapitalassets a
    SET    updatedby = p_createdby, updatedat = (now() AT TIME ZONE 'utc')
    WHERE  a.genericcapitalassetid = c.genericcapitalassetid;
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericcapitalasset_dispose(p_farmid text, p_assetid integer, p_disposaldate date,
    p_proceeds numeric DEFAULT NULL, p_cashaccountid integer DEFAULT NULL, p_notes text DEFAULT NULL,
    p_createdby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    v_status text;
    v_name   text;
    v_acq    date;
    v_date   date := COALESCE(p_disposaldate, (now() AT TIME ZONE 'utc')::date);
BEGIN
    SELECT a.status, a.assetname, a.acquisitiondate INTO v_status, v_name, v_acq
    FROM   genericcapitalassets a
    WHERE  a.genericcapitalassetid = p_assetid AND a.farmid = p_farmid
    FOR UPDATE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;
    IF v_status IN ('Disposed', 'Reversed') THEN
        RAISE EXCEPTION 'This asset is already %.', lower(v_status);
    END IF;
    IF COALESCE(p_proceeds, 0) < 0 THEN
        RAISE EXCEPTION 'Sale proceeds cannot be negative.';
    END IF;
    IF v_date < v_acq THEN
        RAISE EXCEPTION 'An asset cannot be disposed of before it was acquired.';
    END IF;
    IF COALESCE(p_proceeds, 0) > 0 AND p_cashaccountid IS NULL THEN
        RAISE EXCEPTION 'Select the cash account the sale proceeds went into.';
    END IF;

    UPDATE genericcapitalassets a
    SET    status = 'Disposed', disposaldate = v_date,
           disposalproceeds = p_proceeds, disposalnotes = p_notes,
           disposalcashaccountid = CASE WHEN COALESCE(p_proceeds, 0) > 0 THEN p_cashaccountid END,
           updatedby = p_createdby, updatedat = (now() AT TIME ZONE 'utc')
    WHERE  a.genericcapitalassetid = p_assetid AND a.farmid = p_farmid;

    -- Money in. Cash only: selling equipment is not trading income.
    IF COALESCE(p_proceeds, 0) > 0 THEN
        PERFORM fngenericcash_move(p_farmid, p_cashaccountid, ROUND(p_proceeds, 2), v_date::timestamp,
            'AssetDisposal', p_assetid, 'Disposal of ' || v_name, p_createdby);
    END IF;
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericcapitalasset_reverse(p_farmid text, p_assetid integer, p_reason text,
    p_createdby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    v_status text;
    v_name   text;
    r        record;
BEGIN
    SELECT a.status, a.assetname INTO v_status, v_name
    FROM   genericcapitalassets a
    WHERE  a.genericcapitalassetid = p_assetid AND a.farmid = p_farmid
    FOR UPDATE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;
    IF v_status = 'Reversed' THEN
        RAISE EXCEPTION 'This asset has already been reversed.';
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse an asset.';
    END IF;
    IF v_status = 'Disposed' THEN
        RAISE EXCEPTION 'A disposed asset cannot be reversed.';
    END IF;
    IF EXISTS (SELECT 1 FROM genericassetdepreciation d
               WHERE d.genericcapitalassetid = p_assetid AND d.status = 'Posted') THEN
        RAISE EXCEPTION 'Depreciation has been posted for this asset. Reverse the depreciation first.';
    END IF;
    IF EXISTS (SELECT 1 FROM genericcapitalassetcosts c
               JOIN   supplierpaymentallocation sa
                 ON   sa.documenttype = 'CapitalAsset' AND sa.documentid = c.genericcapitalassetcostid
                AND   sa.farmid = p_farmid AND sa.module = 'generic' AND sa.status = 'Posted'
               WHERE  c.genericcapitalassetid = p_assetid AND c.status = 'Posted') THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this asset. Reverse the payment on Supplier Payments first.';
    END IF;

    -- Unwind each document's money (cash back, supplier balance off), then mark
    -- every line reversed. Nothing is deleted.
    FOR r IN SELECT c.genericcapitalassetcostid FROM genericcapitalassetcosts c
             WHERE  c.genericcapitalassetid = p_assetid AND c.status = 'Posted'
               AND  c.sourcetype IN ('Acquisition', 'AdditionalCost')
             ORDER  BY c.genericcapitalassetcostid
    LOOP
        PERFORM spgenericcapitalassetcost_unwind(p_farmid, r.genericcapitalassetcostid,
            'Reversal of capital asset — ' || COALESCE(v_name, ''), p_createdby);
    END LOOP;

    UPDATE genericcapitalassetcosts c
    SET    status = 'Reversed', reversedby = p_createdby,
           reversedat = (now() AT TIME ZONE 'utc'), reversalreason = p_reason
    WHERE  c.genericcapitalassetid = p_assetid AND c.status = 'Posted';

    UPDATE genericcapitalassets a
    SET    status = 'Reversed', reversedby = p_createdby,
           reversedat = (now() AT TIME ZONE 'utc'), reversalreason = p_reason,
           updatedat = (now() AT TIME ZONE 'utc')
    WHERE  a.genericcapitalassetid = p_assetid AND a.farmid = p_farmid;
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericcapitalasset_getall(p_farmid text, p_status text DEFAULT NULL, p_categoryid integer DEFAULT NULL)
RETURNS TABLE(genericcapitalassetid integer, farmid text, assetnumber text, assetname text, genericassetcategoryid integer,
              categoryname text, description text, acquisitiondate date, inservicedate date, location text,
              serialnumber text, supplierid integer, suppliername text, status text, notes text, originalcost numeric,
              residualvalue numeric, depreciableamount numeric, usefullifemonths integer, monthlydepreciation numeric,
              accumulateddepreciation numeric, currentbookvalue numeric, remainingdepreciable numeric,
              isfullydepreciated boolean, costentries integer, depreciationentries integer, disposaldate date,
              disposalproceeds numeric, createdby text, createdat timestamp, updatedat timestamp, reversedby text,
              reversedat timestamp, reversalreason text, acquisitioncost numeric, additionalcost numeric,
              totalcapitalizedcost numeric)
LANGUAGE plpgsql AS $fn$
BEGIN
    RETURN QUERY
    SELECT a.genericcapitalassetid, a.farmid::text, a.assetnumber::text, a.assetname::text,
           a.genericassetcategoryid, c.categoryname::text, a.description::text,
           a.acquisitiondate, a.inservicedate, a.location::text, a.serialnumber::text,
           a.supplierid, s.suppliername::text, a.status::text, a.notes::text,
           f.originalcost, f.residualvalue, f.depreciableamount,
           f.usefullifemonths, f.monthlydepreciation,
           f.accumulateddepreciation, f.currentbookvalue,
           f.remainingdepreciable, f.isfullydepreciated,
           (SELECT COUNT(*)::integer FROM genericcapitalassetcosts cc
             WHERE cc.genericcapitalassetid = a.genericcapitalassetid AND cc.status = 'Posted'),
           (SELECT COUNT(*)::integer FROM genericassetdepreciation dd
             WHERE dd.genericcapitalassetid = a.genericcapitalassetid AND dd.status = 'Posted'),
           a.disposaldate, a.disposalproceeds,
           a.createdby::text, a.createdat, a.updatedat,
           a.reversedby::text, a.reversedat, a.reversalreason::text,
           fngenericcapitalasset_acquisitioncost(a.genericcapitalassetid),
           fngenericcapitalasset_additionalcost(a.genericcapitalassetid),
           f.originalcost
    FROM   genericcapitalassets a
    LEFT   JOIN genericassetcategories c ON c.genericassetcategoryid = a.genericassetcategoryid
    LEFT   JOIN genericsuppliers s ON s.genericsupplierid = a.supplierid
    CROSS  JOIN LATERAL fngenericcapitalasset_financials(a.genericcapitalassetid) f
    WHERE  a.farmid = p_farmid
      AND  (p_status IS NULL OR a.status = p_status)
      AND  (p_categoryid IS NULL OR a.genericassetcategoryid = p_categoryid)
    ORDER  BY a.acquisitiondate DESC, a.genericcapitalassetid DESC;
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericcapitalassetcost_getall(p_farmid text, p_assetid integer)
RETURNS TABLE(genericcapitalassetcostid integer, genericcapitalassetid integer, costdate date, description text,
              costcategory text, amount numeric, sourcetype text, genericexpenseid integer, supplierid integer,
              suppliername text, paymentstatus text, amountpaid numeric, balance numeric, status text, createdby text,
              createdat timestamp, reversedby text, reversedat timestamp, reversalreason text, paymentmethod text,
              duedate date, cashaccountname text, expenseamount numeric, expensecategory text)
LANGUAGE plpgsql AS $fn$
BEGIN
    RETURN QUERY
    SELECT c.genericcapitalassetcostid, c.genericcapitalassetid,
           c.costdate, c.description::text, c.costcategory::text, c.amount,
           c.sourcetype::text,
           NULL::integer,                       -- no expense row: the cost line is the document
           c.supplierid, s.suppliername::text,
           CASE WHEN c.sourcetype = 'OriginalCostCorrection' THEN NULL
                WHEN c.status <> 'Posted' THEN NULL
                WHEN b.total - c.amountpaid <= 0.004 THEN 'Paid'
                WHEN c.amountpaid > 0 THEN 'PartiallyPaid'
                ELSE 'Unpaid' END::text,
           CASE WHEN c.sourcetype = 'OriginalCostCorrection' THEN NULL ELSE c.amountpaid END::numeric(14,2),
           CASE WHEN c.sourcetype = 'OriginalCostCorrection' OR c.status <> 'Posted' THEN NULL
                ELSE GREATEST(b.total - c.amountpaid, 0) END::numeric(14,2),
           c.status::text, c.createdby::text, c.createdat,
           c.reversedby::text, c.reversedat, c.reversalreason::text,
           c.paymentmethod::text, c.duedate, ca.accountname::text,
           -- The bill this line is: its amount plus its corrections.
           CASE WHEN c.sourcetype = 'OriginalCostCorrection' THEN NULL ELSE b.total END::numeric(14,2),
           NULL::text
    FROM   genericcapitalassetcosts c
    CROSS  JOIN LATERAL (SELECT fngenericcapitalassetcost_billtotal(c.genericcapitalassetcostid) AS total) b
    LEFT   JOIN genericsuppliers s ON s.genericsupplierid = c.supplierid
    LEFT   JOIN genericcashaccounts ca ON ca.genericcashaccountid = c.genericcashaccountid
    WHERE  c.farmid = p_farmid AND c.genericcapitalassetid = p_assetid
    ORDER  BY c.costdate, c.genericcapitalassetcostid;
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericcapitalasset_summary(p_farmid text, p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL)
RETURNS TABLE(totalassets integer, activeassets integer, draftassets integer, disposedassets integer,
              fullydepreciated integer, totalassetcost numeric, accumulateddepreciation numeric,
              currentbookvalue numeric, addedinperiod numeric, addedcount integer)
LANGUAGE plpgsql AS $fn$
BEGIN
    RETURN QUERY
    WITH live AS (
        SELECT a.genericcapitalassetid, a.status, a.acquisitiondate, f.*
        FROM   genericcapitalassets a
        CROSS  JOIN LATERAL fngenericcapitalasset_financials(a.genericcapitalassetid) f
        WHERE  a.farmid = p_farmid AND a.status <> 'Reversed'
    )
    SELECT COUNT(*)::integer,
           COUNT(*) FILTER (WHERE l.status = 'Active')::integer,
           COUNT(*) FILTER (WHERE l.status = 'Draft')::integer,
           COUNT(*) FILTER (WHERE l.status = 'Disposed')::integer,
           COUNT(*) FILTER (WHERE l.status = 'FullyDepreciated')::integer,
           COALESCE(SUM(l.originalcost), 0)::numeric(14,2),
           COALESCE(SUM(l.accumulateddepreciation), 0)::numeric(14,2),
           COALESCE(SUM(l.currentbookvalue), 0)::numeric(14,2),
           COALESCE((SELECT SUM(cc.amount) FROM genericcapitalassetcosts cc
                      WHERE cc.farmid = p_farmid AND cc.status = 'Posted'
                        AND (p_fromdate IS NULL OR cc.costdate >= p_fromdate)
                        AND (p_todate   IS NULL OR cc.costdate <= p_todate)), 0)::numeric(14,2),
           COALESCE((SELECT COUNT(*) FROM genericcapitalassets aa
                      WHERE aa.farmid = p_farmid AND aa.status <> 'Reversed'
                        AND (p_fromdate IS NULL OR aa.acquisitiondate >= p_fromdate)
                        AND (p_todate   IS NULL OR aa.acquisitiondate <= p_todate)), 0)::integer
    FROM   live l;
END;
$fn$;

-- =============================================================================
-- 6. Depreciation
-- =============================================================================
CREATE OR REPLACE FUNCTION spgenericassetdepreciation_post(p_farmid text, p_assetid integer, p_periodstart date,
    p_amount numeric, p_sourcetype text DEFAULT 'Scheduled', p_createdby text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE
    v_id    integer;
    v_expid integer;
    v_catid integer;
    v_end   date := (date_trunc('month', p_periodstart) + interval '1 month - 1 day')::date;
    v_name  text;
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN
        RETURN NULL;                    -- nothing to charge is not an error
    END IF;
    SELECT a.assetname INTO v_name FROM genericcapitalassets a
    WHERE  a.genericcapitalassetid = p_assetid AND a.farmid = p_farmid;
    IF v_name IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;

    INSERT INTO genericassetdepreciation
        (farmid, genericcapitalassetid, periodstart, periodend, depreciationdate,
         amount, depreciationmethod, sourcetype, status, createdby)
    VALUES
        (p_farmid, p_assetid, date_trunc('month', p_periodstart)::date, v_end, v_end,
         ROUND(p_amount, 2), 'StraightLine', p_sourcetype, 'Posted', p_createdby)
    RETURNING genericassetdepreciationid INTO v_id;

    v_catid := fngenericdepreciationcategory(p_farmid);

    -- The P&L side. NonCash, no supplier, no cash account: out of Cash Flow and
    -- out of payables, in profit. amountpaid = amount so it never reads as a bill.
    INSERT INTO genericexpenses
        (farmid, expensedate, genericexpensecategoryid, description, amount, paymentmethod,
         genericcashaccountid, genericsupplierid, amountpaid, status, notes, createdby, approvedby,
         approvedat, sourcetype, sourceid, isdeleted)
    VALUES
        (p_farmid, v_end, v_catid,
         'Depreciation - ' || v_name || ' (' || to_char(p_periodstart, 'Mon YYYY') || ')',
         ROUND(p_amount, 2), 'NonCash', NULL, NULL, ROUND(p_amount, 2), 'Approved',
         'Auto-created by the depreciation schedule.', p_createdby, p_createdby,
         (now() AT TIME ZONE 'utc'), 'AssetDepreciation', v_id, FALSE)
    RETURNING genericexpenseid INTO v_expid;

    UPDATE genericassetdepreciation d SET genericexpenseid = v_expid
    WHERE  d.genericassetdepreciationid = v_id;
    RETURN v_id;
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericassetdepreciation_due(p_farmid text, p_throughdate date DEFAULT NULL)
RETURNS TABLE(genericcapitalassetid integer, assetnumber text, assetname text, monthsdue integer, amountdue numeric,
              monthlydepreciation numeric, nextperiod date)
LANGUAGE plpgsql AS $fn$
DECLARE
    v_through date := date_trunc('month', COALESCE(p_throughdate, (now() AT TIME ZONE 'utc')::date))::date;
    a         record;
    v_period  date;
    v_months  integer;
    v_amount  numeric(14,2);
    v_left    numeric(14,2);
    v_charge  numeric(14,2);
    v_index   integer;
    v_next    date;
BEGIN
    FOR a IN
        SELECT ca.genericcapitalassetid AS assetid, ca.assetnumber AS anum, ca.assetname AS aname,
               ca.inservicedate, f.*
        FROM   genericcapitalassets ca
        CROSS  JOIN LATERAL fngenericcapitalasset_financials(ca.genericcapitalassetid) f
        WHERE  ca.farmid = p_farmid AND ca.status = 'Active'
          AND  ca.inservicedate IS NOT NULL AND COALESCE(ca.usefullifemonths, 0) > 0
        ORDER  BY ca.genericcapitalassetid
    LOOP
        v_months := 0; v_amount := 0; v_next := NULL;
        v_left   := a.remainingdepreciable;
        v_period := date_trunc('month', a.inservicedate)::date;
        v_index  := 0;
        -- The same walk as _generate, so the preview equals the button.
        WHILE v_period <= v_through AND v_left > 0 AND v_index < a.usefullifemonths LOOP
            IF NOT EXISTS (SELECT 1 FROM genericassetdepreciation d
                           WHERE d.genericcapitalassetid = a.assetid
                             AND d.periodstart = v_period AND d.sourcetype = 'Scheduled') THEN
                v_charge := CASE WHEN v_index = a.usefullifemonths - 1
                                 THEN v_left ELSE LEAST(a.monthlydepreciation, v_left) END;
                v_next   := COALESCE(v_next, v_period);
                v_months := v_months + 1;
                v_amount := v_amount + v_charge;
                v_left   := v_left - v_charge;
            END IF;
            v_period := (v_period + interval '1 month')::date;
            v_index  := v_index + 1;
        END LOOP;

        IF v_months > 0 THEN
            genericcapitalassetid := a.assetid;
            assetnumber           := a.anum::text;
            assetname             := a.aname::text;
            monthsdue             := v_months;
            amountdue             := v_amount;
            monthlydepreciation   := a.monthlydepreciation;
            nextperiod            := v_next;
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericassetdepreciation_generate(p_farmid text, p_throughdate date DEFAULT NULL,
    p_assetid integer DEFAULT NULL, p_createdby text DEFAULT NULL)
RETURNS TABLE(assetsprocessed integer, entriescreated integer, totalamount numeric)
LANGUAGE plpgsql AS $fn$
DECLARE
    v_through   date := date_trunc('month', COALESCE(p_throughdate, (now() AT TIME ZONE 'utc')::date))::date;
    v_assets    integer := 0;
    v_entries   integer := 0;
    v_total     numeric(14,2) := 0;
    a           record;
    v_period    date;
    v_monthly   numeric(14,2);
    v_remaining numeric(14,2);
    v_charge    numeric(14,2);
    v_index     integer;
    v_made      boolean;
BEGIN
    FOR a IN
        SELECT ca.genericcapitalassetid AS assetid, ca.inservicedate, f.*
        FROM   genericcapitalassets ca
        CROSS  JOIN LATERAL fngenericcapitalasset_financials(ca.genericcapitalassetid) f
        WHERE  ca.farmid = p_farmid
          AND  (p_assetid IS NULL OR ca.genericcapitalassetid = p_assetid)
          AND  ca.status IN ('Active', 'FullyDepreciated')
          AND  ca.inservicedate IS NOT NULL
          AND  COALESCE(ca.usefullifemonths, 0) > 0
        ORDER  BY ca.genericcapitalassetid
    LOOP
        v_monthly   := a.monthlydepreciation;
        v_remaining := a.remainingdepreciable;
        v_made      := FALSE;
        IF COALESCE(v_monthly, 0) <= 0 THEN CONTINUE; END IF;

        v_period := date_trunc('month', a.inservicedate)::date;
        v_index  := 0;
        -- Exactly usefullifemonths long; the final month takes what is left.
        WHILE v_period <= v_through AND v_remaining > 0 AND v_index < a.usefullifemonths LOOP
            IF NOT EXISTS (SELECT 1 FROM genericassetdepreciation d
                           WHERE d.genericcapitalassetid = a.assetid
                             AND d.periodstart = v_period AND d.sourcetype = 'Scheduled') THEN
                v_charge := CASE WHEN v_index = a.usefullifemonths - 1
                                 THEN v_remaining ELSE LEAST(v_monthly, v_remaining) END;
                IF spgenericassetdepreciation_post(p_farmid, a.assetid, v_period, v_charge, 'Scheduled', p_createdby) IS NOT NULL THEN
                    v_remaining := v_remaining - v_charge;
                    v_entries   := v_entries + 1;
                    v_total     := v_total + v_charge;
                    v_made      := TRUE;
                END IF;
            END IF;
            v_period := (v_period + interval '1 month')::date;
            v_index  := v_index + 1;
        END LOOP;
        IF v_made THEN v_assets := v_assets + 1; END IF;
    END LOOP;

    PERFORM fngenericcapitalasset_refreshstatus(p_farmid, p_assetid);
    RETURN QUERY SELECT v_assets, v_entries, v_total;
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericassetdepreciation_getall(p_farmid text, p_assetid integer DEFAULT NULL,
    p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL)
RETURNS TABLE(genericassetdepreciationid integer, genericcapitalassetid integer, assetnumber text, assetname text,
              categoryname text, periodstart date, periodend date, depreciationdate date, amount numeric,
              depreciationmethod text, sourcetype text, status text, genericexpenseid integer, reversalofid integer,
              originalcost numeric, monthlydepreciation numeric, accumulatedafter numeric, bookvalueafter numeric,
              createdby text, createdat timestamp, reversedby text, reversedat timestamp, reversalreason text)
LANGUAGE plpgsql AS $fn$
BEGIN
    RETURN QUERY
    SELECT d.genericassetdepreciationid, d.genericcapitalassetid,
           a.assetnumber::text, a.assetname::text, c.categoryname::text,
           d.periodstart, d.periodend, d.depreciationdate,
           d.amount, d.depreciationmethod::text, d.sourcetype::text, d.status::text,
           d.genericexpenseid, d.reversalofid,
           fngenericcapitalasset_originalcost(d.genericcapitalassetid),
           fngenericcapitalasset_monthly(fngenericcapitalasset_originalcost(d.genericcapitalassetid),
                                         a.residualvalue, a.usefullifemonths),
           (SELECT COALESCE(SUM(p.amount), 0)::numeric(14,2)
              FROM genericassetdepreciation p
             WHERE p.genericcapitalassetid = d.genericcapitalassetid
               AND (p.depreciationdate, p.genericassetdepreciationid)
                   <= (d.depreciationdate, d.genericassetdepreciationid)),
           GREATEST(fngenericcapitalasset_originalcost(d.genericcapitalassetid)
                    - (SELECT COALESCE(SUM(p.amount), 0)
                         FROM genericassetdepreciation p
                        WHERE p.genericcapitalassetid = d.genericcapitalassetid
                          AND (p.depreciationdate, p.genericassetdepreciationid)
                              <= (d.depreciationdate, d.genericassetdepreciationid)),
                    a.residualvalue)::numeric(14,2),
           d.createdby::text, d.createdat,
           d.reversedby::text, d.reversedat, d.reversalreason::text
    FROM   genericassetdepreciation d
    JOIN   genericcapitalassets a ON a.genericcapitalassetid = d.genericcapitalassetid
    LEFT   JOIN genericassetcategories c ON c.genericassetcategoryid = a.genericassetcategoryid
    WHERE  d.farmid = p_farmid
      AND  (p_assetid IS NULL OR d.genericcapitalassetid = p_assetid)
      AND  (p_fromdate IS NULL OR d.depreciationdate >= p_fromdate)
      AND  (p_todate   IS NULL OR d.depreciationdate <= p_todate)
    ORDER  BY d.depreciationdate DESC, d.genericassetdepreciationid DESC;
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericassetdepreciation_reverse(p_farmid text, p_entryid integer, p_reason text,
    p_createdby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    v_row   genericassetdepreciation%ROWTYPE;
    v_name  text;
    v_new   integer;
    v_expid integer;
    v_catid integer;
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse depreciation.';
    END IF;
    SELECT d.* INTO v_row FROM genericassetdepreciation d
    WHERE  d.genericassetdepreciationid = p_entryid AND d.farmid = p_farmid FOR UPDATE;
    IF v_row.genericassetdepreciationid IS NULL THEN
        RAISE EXCEPTION 'Depreciation entry not found for this company.';
    END IF;
    IF v_row.status = 'Reversed' THEN
        RAISE EXCEPTION 'This depreciation entry has already been reversed.';
    END IF;
    IF v_row.amount < 0 THEN
        RAISE EXCEPTION 'A reversal cannot itself be reversed.';
    END IF;

    SELECT a.assetname INTO v_name FROM genericcapitalassets a
    WHERE  a.genericcapitalassetid = v_row.genericcapitalassetid;

    INSERT INTO genericassetdepreciation
        (farmid, genericcapitalassetid, periodstart, periodend, depreciationdate,
         amount, depreciationmethod, sourcetype, status, reversalofid, createdby, reversalreason)
    VALUES
        (p_farmid, v_row.genericcapitalassetid, v_row.periodstart, v_row.periodend,
         (now() AT TIME ZONE 'utc')::date, -v_row.amount, v_row.depreciationmethod, 'Reversal', 'Posted',
         p_entryid, p_createdby, p_reason)
    RETURNING genericassetdepreciationid INTO v_new;

    v_catid := fngenericdepreciationcategory(p_farmid);

    -- The opposite P&L entry; also NonCash.
    INSERT INTO genericexpenses
        (farmid, expensedate, genericexpensecategoryid, description, amount, paymentmethod,
         genericcashaccountid, genericsupplierid, amountpaid, status, notes, createdby, approvedby,
         approvedat, sourcetype, sourceid, isdeleted)
    VALUES
        (p_farmid, (now() AT TIME ZONE 'utc')::date, v_catid,
         'Reversal of depreciation - ' || COALESCE(v_name, '') ||
         ' (' || to_char(v_row.periodstart, 'Mon YYYY') || '): ' || p_reason,
         -v_row.amount, 'NonCash', NULL, NULL, -v_row.amount, 'Approved',
         'Auto-created by a depreciation reversal.', p_createdby, p_createdby,
         (now() AT TIME ZONE 'utc'), 'AssetDepreciation', v_new, FALSE)
    RETURNING genericexpenseid INTO v_expid;

    UPDATE genericassetdepreciation d SET genericexpenseid = v_expid
    WHERE  d.genericassetdepreciationid = v_new;

    UPDATE genericassetdepreciation d
    SET    status = 'Reversed', reversedby = p_createdby,
           reversedat = (now() AT TIME ZONE 'utc'), reversalreason = p_reason
    WHERE  d.genericassetdepreciationid = p_entryid;

    PERFORM fngenericcapitalasset_refreshstatus(p_farmid, v_row.genericcapitalassetid);
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericassetdepreciation_adjust(p_farmid text, p_assetid integer, p_periodstart date,
    p_amount numeric, p_reason text, p_createdby text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE
    v_status text;
    v_left   numeric(14,2);
    v_id     integer;
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required for a depreciation adjustment.';
    END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Adjustment amount must be greater than 0.';
    END IF;
    SELECT a.status INTO v_status FROM genericcapitalassets a
    WHERE  a.genericcapitalassetid = p_assetid AND a.farmid = p_farmid;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;
    IF v_status IN ('Reversed', 'Draft', 'Disposed') THEN
        RAISE EXCEPTION 'Depreciation cannot be adjusted on a % asset.', lower(v_status);
    END IF;
    SELECT f.remainingdepreciable INTO v_left FROM fngenericcapitalasset_financials(p_assetid) f;
    IF p_amount > v_left THEN
        RAISE EXCEPTION 'This asset has only % left to depreciate.', v_left;
    END IF;

    v_id := spgenericassetdepreciation_post(p_farmid, p_assetid,
                date_trunc('month', p_periodstart)::date, p_amount, 'ManualAdjustment', p_createdby);
    UPDATE genericassetdepreciation d SET reversalreason = p_reason
    WHERE  d.genericassetdepreciationid = v_id;

    PERFORM fngenericcapitalasset_refreshstatus(p_farmid, p_assetid);
    RETURN v_id;
END;
$fn$;

-- =============================================================================
-- 7. Copy the old one-table register in, then keep its reader and retire its writers
-- =============================================================================
DO $mig$
DECLARE
    o       record;
    v_cat   integer;
    v_id    integer;
    v_num   text;
    v_life  integer;
    v_date  date;
BEGIN
    FOR o IN SELECT * FROM "GenericAssets" g WHERE g."MigratedToAssetId" IS NULL ORDER BY g."GenericAssetId" LOOP
        PERFORM spgenericassetcategory_ensuredefaults(o."FarmId", NULL);
        v_cat := NULL;
        IF COALESCE(btrim(o."Category"), '') <> '' THEN
            SELECT c.genericassetcategoryid INTO v_cat FROM genericassetcategories c
            WHERE  c.farmid = o."FarmId" AND lower(c.categoryname) = lower(btrim(o."Category"));
            IF v_cat IS NULL THEN
                v_cat := spgenericassetcategory_upsert(o."FarmId", NULL, btrim(o."Category"), o."UsefulLifeMonths", TRUE, 'migration-453');
            END IF;
        END IF;

        v_date := COALESCE(o."PurchaseDate", o."CreatedAt", (now() AT TIME ZONE 'utc'))::date;
        v_life := NULLIF(o."UsefulLifeMonths", 0);
        SELECT 'AST-' || lpad((COALESCE(MAX(substring(a.assetnumber from '[0-9]+$')::integer), 0) + 1)::text, 4, '0')
          INTO v_num FROM genericcapitalassets a WHERE a.farmid = o."FarmId" AND a.assetnumber ~ '^AST-[0-9]+$';

        INSERT INTO genericcapitalassets
            (farmid, assetnumber, assetname, genericassetcategoryid, acquisitiondate, inservicedate, residualvalue,
             usefullifemonths, location, serialnumber, status, notes, disposaldate, disposalproceeds,
             legacygenericassetid, createdby, createdat)
        VALUES
            (o."FarmId", COALESCE(v_num, 'AST-0001'), COALESCE(NULLIF(btrim(o."AssetName"), ''), 'Asset'), v_cat,
             v_date, CASE WHEN v_life IS NOT NULL THEN v_date END, 0, v_life, o."Location", o."SerialNumber",
             CASE WHEN o."Status" = 'Disposed' THEN 'Disposed'
                  WHEN v_life IS NOT NULL THEN 'Active' ELSE 'Draft' END,
             concat_ws(E'\n', NULLIF(btrim(o."Notes"), ''), 'Copied from the old asset register (asset #' || o."GenericAssetId" || ').'),
             o."DisposalDate"::date, o."DisposalAmount", o."GenericAssetId", o."CreatedBy",
             COALESCE(o."CreatedAt", (now() AT TIME ZONE 'utc')))
        RETURNING genericcapitalassetid INTO v_id;

        -- The old register never moved money, so the copy does not either: the
        -- cost is recorded as already settled, with no cash account and no supplier.
        IF COALESCE(o."PurchaseCost", 0) > 0 THEN
            INSERT INTO genericcapitalassetcosts
                (farmid, genericcapitalassetid, costdate, description, costcategory, amount, sourcetype,
                 paymentmethod, amountpaid, createdby)
            VALUES
                (o."FarmId", v_id, v_date, COALESCE(NULLIF(btrim(o."AssetName"), ''), 'Asset'), 'Acquisition',
                 ROUND(o."PurchaseCost", 2), 'Acquisition', 'Migrated', ROUND(o."PurchaseCost", 2), 'migration-453');
        END IF;

        -- Depreciation already charged on the old register (its expense rows
        -- already exist) becomes one adjustment row without a second expense.
        IF COALESCE(o."TotalDepreciation", 0) > 0 THEN
            INSERT INTO genericassetdepreciation
                (farmid, genericcapitalassetid, periodstart, periodend, depreciationdate, amount, sourcetype,
                 status, createdby, reversalreason)
            VALUES
                (o."FarmId", v_id, date_trunc('month', v_date)::date,
                 (date_trunc('month', v_date) + interval '1 month - 1 day')::date,
                 (now() AT TIME ZONE 'utc')::date, ROUND(o."TotalDepreciation", 2), 'ManualAdjustment',
                 'Posted', 'migration-453', 'Depreciation charged on the old asset register.');
        END IF;

        UPDATE "GenericAssets" SET "MigratedToAssetId" = v_id WHERE "GenericAssetId" = o."GenericAssetId";
    END LOOP;
END
$mig$;

-- The old reader, same columns, now over the new register (cost = capitalised cost).
CREATE OR REPLACE FUNCTION spgenericasset_list(p_farmid text)
RETURNS TABLE("GenericAssetId" integer, "FarmId" text, "AssetName" text, "Category" character varying,
              "PurchaseDate" timestamp without time zone, "PurchaseCost" numeric, "CurrentValue" numeric,
              "TotalDepreciation" numeric, "UsefulLifeMonths" integer, "DepreciationMethod" character varying,
              "Status" character varying, "DisposalDate" timestamp without time zone, "DisposalAmount" numeric,
              "Location" text, "SerialNumber" text, "Notes" text, "CreatedAt" timestamp without time zone)
LANGUAGE plpgsql AS $fn$
BEGIN
    RETURN QUERY
    SELECT g.genericcapitalassetid, g.farmid, g.assetname, g.categoryname::varchar,
           g.acquisitiondate::timestamp, g.originalcost, g.currentbookvalue, g.accumulateddepreciation,
           g.usefullifemonths, 'StraightLine'::varchar,
           CASE WHEN g.status = 'FullyDepreciated' THEN 'Active' ELSE g.status END::varchar,
           g.disposaldate::timestamp, g.disposalproceeds, g.location, g.serialnumber, g.notes, g.createdat
    FROM   spgenericcapitalasset_getall(p_farmid, NULL, NULL) g
    WHERE  g.status <> 'Reversed'
    ORDER  BY g.acquisitiondate DESC;
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericasset_create(p_farmid text, p_assetname text, p_category character varying,
    p_purchasedate timestamp without time zone, p_purchasecost numeric, p_usefullifemonths integer,
    p_depreciationmethod character varying, p_location text, p_serialnumber text, p_notes text, p_createdby text)
RETURNS integer LANGUAGE plpgsql AS $fn$
BEGIN
    RAISE EXCEPTION 'Assets are now recorded on the Capital Investments/Assets page.' USING ERRCODE = 'P0001';
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericasset_dispose(p_genericassetid integer, p_farmid text,
    p_disposaldate timestamp without time zone, p_disposalamount numeric)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
    RAISE EXCEPTION 'Assets are now disposed of on the Capital Investments/Assets page.' USING ERRCODE = 'P0001';
END;
$fn$;

CREATE OR REPLACE FUNCTION spgenericasset_depreciate(p_genericassetid integer, p_farmid text, p_amount numeric)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
    RAISE EXCEPTION 'Depreciation is now posted on the Capital Investments/Assets page.' USING ERRCODE = 'P0001';
END;
$fn$;

-- =============================================================================
-- 8. Shared Generic readers: copied from the live 449/450 bodies, only the 453
--    arms added (payables, addpaid, cash flow).
-- =============================================================================
CREATE OR REPLACE FUNCTION public.fngenericpayables(p_farmid text)
 RETURNS TABLE(documenttype text, documentid integer, supplierid integer, docdate date, label text, reference text, totalcost numeric, amountpaid numeric, balance numeric, cashaccountid integer, duedate date)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT 'Purchase'::text, p.genericpurchaseid, p.genericsupplierid,
           p.purchasedate::date,
           COALESCE(NULLIF(btrim(p.notes), ''), 'Purchase')::text,
           ('P' || p.genericpurchaseid::text)::text,
           COALESCE(p.totalamount, 0)::numeric(14,2),
           COALESCE(p.amountpaid, 0)::numeric(14,2),
           GREATEST(COALESCE(p.totalamount, 0) - COALESCE(p.amountpaid, 0), 0)::numeric(14,2),
           p.genericcashaccountid,
           NULL::date
    FROM   genericpurchases p
    WHERE  p.farmid = p_farmid
      AND  COALESCE(p.isdeleted, FALSE) = FALSE
      AND  p.genericsupplierid IS NOT NULL
      AND  COALESCE(p.status, '') <> 'Cancelled'

    UNION ALL

    SELECT 'Expense'::text, e.genericexpenseid, e.genericsupplierid,
           e.expensedate::date,
           COALESCE(NULLIF(btrim(e.description), ''), 'Expense')::text,
           ('E' || e.genericexpenseid::text)::text,
           COALESCE(e.amount, 0)::numeric(14,2),
           COALESCE(e.amountpaid, e.amount)::numeric(14,2),
           GREATEST(COALESCE(e.amount, 0) - COALESCE(e.amountpaid, e.amount), 0)::numeric(14,2),
           e.genericcashaccountid,
           e.duedate
    FROM   genericexpenses e
    WHERE  e.farmid = p_farmid
      AND  COALESCE(e.isdeleted, FALSE) = FALSE
      AND  e.genericsupplierid IS NOT NULL
      AND  e.sourcetype IS NULL
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
      AND  e.status = 'Approved'

    UNION ALL

    -- 449: debts recorded by hand (owed without a purchase here).
    SELECT 'SupplierDebt'::text, d.debtid, d.supplierid, d.debtdate,
           d.description::text, d.debtnumber::text,
           d.amount, d.amountpaid, GREATEST(d.amount - d.amountpaid, 0)::numeric(14,2),
           NULL::integer, NULL::date
    FROM   genericsupplierdebts d
    WHERE  d.farmid = p_farmid AND d.status = 'Posted'

    UNION ALL

    -- 453: a capital asset bought (partly) on credit. The cost line is the bill;
    -- what is owed is its amount plus its corrections, less what was paid.
    SELECT 'CapitalAsset'::text, c.genericcapitalassetcostid, c.supplierid, c.costdate,
           (a.assetname || CASE WHEN c.sourcetype = 'AdditionalCost'
                                THEN ' - ' || COALESCE(NULLIF(btrim(c.description), ''), 'added cost')
                                ELSE '' END)::text,
           a.assetnumber::text,
           b.total, c.amountpaid, GREATEST(b.total - c.amountpaid, 0)::numeric(14,2),
           c.genericcashaccountid, c.duedate
    FROM   genericcapitalassetcosts c
    JOIN   genericcapitalassets a ON a.genericcapitalassetid = c.genericcapitalassetid
    CROSS  JOIN LATERAL (SELECT fngenericcapitalassetcost_billtotal(c.genericcapitalassetcostid) AS total) b
    WHERE  c.farmid = p_farmid AND c.status = 'Posted' AND c.supplierid IS NOT NULL
      AND  c.sourcetype IN ('Acquisition', 'AdditionalCost')
      AND  COALESCE(c.paymentmethod, '') <> 'Migrated';
$function$;

CREATE OR REPLACE FUNCTION public.fngenericpayable_addpaid(p_farmid text, p_documenttype text, p_documentid integer, p_delta numeric)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_documenttype = 'Expense' THEN
        UPDATE genericexpenses
        SET    amountpaid = LEAST(GREATEST(COALESCE(amountpaid, amount) + p_delta, 0), amount),
               updatedat  = (now() AT TIME ZONE 'utc')
        WHERE  genericexpenseid = p_documentid AND farmid = p_farmid;
    ELSIF p_documenttype = 'SupplierDebt' THEN
        UPDATE genericsupplierdebts SET amountpaid = LEAST(GREATEST(amountpaid + p_delta, 0), amount)
        WHERE  debtid = p_documentid AND farmid = p_farmid;
    ELSIF p_documenttype = 'Purchase' THEN
        UPDATE genericpurchases
        SET    amountpaid    = LEAST(GREATEST(COALESCE(amountpaid, 0) + p_delta, 0), totalamount),
               balance       = GREATEST(totalamount - LEAST(GREATEST(COALESCE(amountpaid, 0) + p_delta, 0), totalamount), 0),
               paymentstatus = CASE WHEN COALESCE(amountpaid, 0) + p_delta >= totalamount THEN 'Paid'
                                    WHEN COALESCE(amountpaid, 0) + p_delta <= 0 THEN 'Unpaid'
                                    ELSE 'PartiallyPaid' END,
               updatedat     = (now() AT TIME ZONE 'utc')
        WHERE  genericpurchaseid = p_documentid AND farmid = p_farmid;
    ELSIF p_documenttype = 'CapitalAsset' THEN
        -- 453: a capital asset bill (the cost line).
        UPDATE genericcapitalassetcosts c
        SET    amountpaid = LEAST(GREATEST(c.amountpaid + p_delta, 0),
                                  fngenericcapitalassetcost_billtotal(c.genericcapitalassetcostid))
        WHERE  c.genericcapitalassetcostid = p_documentid AND c.farmid = p_farmid;
    ELSE
        RAISE EXCEPTION 'Unknown payable type "%".', p_documenttype USING ERRCODE = 'P0001';
    END IF;
END
$function$;

CREATE OR REPLACE FUNCTION public.spgenericcashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, createdat timestamp without time zone)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);
    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);
BEGIN
    -- ---- 1. customer receipts ---------------------------------------------------
    -- Money received from customers against sales/invoices.
    RETURN QUERY
    SELECT 'Receipt'::text,
           FALSE,
           p.genericcustomerpaymentid,
           p.genericcashaccountid,
           NULL::text,
           p.paymentdate::timestamp,
           'CashIn'::text,
           'CustomerPayment'::text,
           p.genericcustomerpaymentid,
           FALSE,
           COALESCE(p.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(p.notes), ''),
               NULLIF(btrim(p.referenceno), ''),
               'Customer payment #' || p.genericcustomerpaymentid::text
           )::text,
           'OperatingIn'::text,
           p.createdat::timestamp
    FROM   genericcustomerpayments p
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) > 0
      AND  COALESCE(p.status, 'Posted') <> 'Reversed'
      AND  p.paymentdate::timestamp >= v_from
      AND  p.paymentdate::timestamp <= v_to;

    -- ---- 2. sale residuals (part paid at counter) -------------------------------
    -- A sale entered as already paid or partially paid. The residual is the
    -- amount paid that did NOT create a genericcustomerpayments row.
    RETURN QUERY
    SELECT 'SaleResidual'::text,
           FALSE,
           s.genericsaleid,
           s.genericcashaccountid,
           NULL::text,
           s.saledate::timestamp,
           'CashIn'::text,
           'Sale'::text,
           s.genericsaleid,
           FALSE,
           v.residual,
           ('Sale #' || s.genericsaleid::text ||
            COALESCE(' - ' || NULLIF(btrim(c.customername), ''), ''))::text,
           'OperatingIn'::text,
           s.createdat::timestamp
    FROM   genericsales s
    LEFT   JOIN genericcustomers c ON c.genericcustomerid = s.genericcustomerid
    CROSS  JOIN LATERAL (
        SELECT ROUND(
                   CASE WHEN COALESCE(s.paymentstatus, '') = 'Paid'
                        THEN COALESCE(s.totalamount, 0)
                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),
                                   COALESCE(s.totalamount, 0))
                   END
                 - COALESCE((SELECT SUM(pp.amount)
                             FROM   genericcustomerpayments pp
                             WHERE  pp.linkedsaleid = s.genericsaleid
                               AND  lower(pp.farmid::text) = lower(p_farmid)
                               AND  COALESCE(pp.status, 'Posted') <> 'Reversed'), 0)
               , 2) AS residual
    ) v
    WHERE  lower(s.farmid::text) = lower(p_farmid)
      AND  COALESCE(s.isdeleted, FALSE) = FALSE
      AND  v.residual > 0
      AND  s.saledate::timestamp >= v_from
      AND  s.saledate::timestamp <= v_to;

    -- ---- 3. expenses (all operational spending) ---------------------------------
    -- Every kind of spending: supplier payments, staff payments, recurring,
    -- purchases, etc. all INSERT INTO genericexpenses. NonCash (internal use)
    -- is excluded — that records stock leaving without money moving.
    RETURN QUERY
    SELECT 'Expense'::text,
           FALSE,
           e.genericexpenseid,
           e.genericcashaccountid,
           NULL::text,
           e.expensedate::timestamp,
           'CashOut'::text,
           'Expense'::text,
           e.genericexpenseid,
           FALSE,
           -- 449: the part paid from supplier credit left with the advance
           -(COALESCE(e.amount, 0)
             - COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                         WHERE sa.module = 'generic' AND sa.documenttype = 'Expense'
                           AND sa.documentid = e.genericexpenseid AND sa.status = 'Posted'
                           AND sa.fromcredit), 0))::numeric,
           COALESCE(NULLIF(btrim(e.description), ''), 'Expense')::text,
           'OperatingOut'::text,
           e.createdat::timestamp
    FROM   genericexpenses e
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(e.amount, 0) > 0
      AND  COALESCE(e.isdeleted, FALSE) = FALSE
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
      AND  COALESCE(e.status, 'Approved') = 'Approved'   -- 448
      AND  e.expensedate::timestamp >= v_from
      AND  e.expensedate::timestamp <= v_to;

    -- ---- 4. payroll (only paid runs WITHOUT a linked expense) --------------------
    -- If payroll creates a linked expense, the expense leg already counts it.
    -- Only add standalone paid payroll runs that have no genericexpenseid.
    IF to_regclass('public.genericpayrollruns') IS NOT NULL THEN
        RETURN QUERY EXECUTE format($sql$
            SELECT 'Payroll'::text,
                   FALSE,
                   pr.genericpayrollrunid,
                   pr.genericcashaccountid,
                   NULL::text,
                   COALESCE(pr.paidat, pr.createdat)::timestamp,
                   'CashOut'::text,
                   'Payroll'::text,
                   pr.genericpayrollrunid,
                   FALSE,
                   -COALESCE(pr.totalnetpay, 0)::numeric,
                   COALESCE(
                       NULLIF(btrim(pr.notes), ''),
                       'Payroll ' || to_char(pr.periodstart, 'DD Mon') || ' - ' || to_char(pr.periodend, 'DD Mon YYYY')
                   )::text,
                   'OperatingOut'::text,
                   pr.createdat::timestamp
            FROM   genericpayrollruns pr
            WHERE  lower(pr.farmid::text) = lower($1)
              AND  pr.status = 'Paid'
              AND  COALESCE(pr.totalnetpay, 0) > 0
              AND  COALESCE(pr.isdeleted, FALSE) = FALSE
              AND  NOT EXISTS (
                       SELECT 1 FROM genericexpenses e
                       WHERE  e.sourcetype = 'Payroll'
                         AND  e.sourceid = pr.genericpayrollrunid
                         AND  lower(e.farmid::text) = lower($1)
                         AND  COALESCE(e.isdeleted, FALSE) = FALSE
                   )
              AND  COALESCE(pr.paidat, pr.createdat)::timestamp >= $2
              AND  COALESCE(pr.paidat, pr.createdat)::timestamp <= $3
        $sql$)
        USING p_farmid, v_from, v_to;
    END IF;

    -- ---- 5. owner contributions (financing in) ----------------------------------
    RETURN QUERY
    SELECT 'OwnerContribution'::text,
           FALSE,
           oc.genericownerentryid,
           oc.genericcashaccountid,
           NULL::text,
           oc.entrydate::timestamp,
           'CashIn'::text,
           'OwnerInjection'::text,
           oc.genericownerentryid,
           FALSE,
           COALESCE(oc.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(oc.notes), ''),
               'Owner contribution' || COALESCE(' - ' || NULLIF(btrim(oc.ownername), ''), '')
           )::text,
           'FinancingIn'::text,
           oc.createdat::timestamp
    FROM   genericownercontributiondraws oc
    WHERE  lower(oc.farmid::text) = lower(p_farmid)
      AND  oc.entrytype = 'Contribution'
      AND  oc.status = 'Posted'
      AND  COALESCE(oc.amount, 0) > 0
      AND  oc.entrydate::timestamp >= v_from
      AND  oc.entrydate::timestamp <= v_to;

    -- ---- 6. owner draws (financing out) -----------------------------------------
    RETURN QUERY
    SELECT 'OwnerDraw'::text,
           FALSE,
           oc.genericownerentryid,
           oc.genericcashaccountid,
           NULL::text,
           oc.entrydate::timestamp,
           'CashOut'::text,
           'Withdrawal'::text,
           oc.genericownerentryid,
           FALSE,
           -COALESCE(oc.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(oc.notes), ''),
               'Owner draw' || COALESCE(' - ' || NULLIF(btrim(oc.ownername), ''), '')
           )::text,
           'FinancingOut'::text,
           oc.createdat::timestamp
    FROM   genericownercontributiondraws oc
    WHERE  lower(oc.farmid::text) = lower(p_farmid)
      AND  oc.entrytype = 'Draw'
      AND  oc.status = 'Posted'
      AND  COALESCE(oc.amount, 0) > 0
      AND  oc.entrydate::timestamp >= v_from
      AND  oc.entrydate::timestamp <= v_to;

    -- ---- 7. loans received (financing in) ---------------------------------------
    IF to_regclass('public."GenericLoans"') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'LoanReceived'::text,
               FALSE,
               l."GenericLoanId",
               l."GenericCashAccountId",
               NULL::text,
               COALESCE(l."LoanDate", l."CreatedAt")::timestamp,
               'CashIn'::text,
               'LoanReceived'::text,
               l."GenericLoanId",
               FALSE,
               COALESCE(l."AmountReceived", 0)::numeric,
               COALESCE(
                   NULLIF(btrim(l."Notes"), ''),
                   'Loan from ' || COALESCE(NULLIF(btrim(l."LenderName"), ''), 'unknown lender')
               )::text,
               'FinancingIn'::text,
               l."CreatedAt"::timestamp
        FROM   "GenericLoans" l
        WHERE  l."FarmId" = p_farmid
          AND  l."Status" IN ('Active', 'Paid')
          AND  COALESCE(l."AmountReceived", 0) > 0
          AND  COALESCE(l."LoanDate", l."CreatedAt")::timestamp >= v_from
          AND  COALESCE(l."LoanDate", l."CreatedAt")::timestamp <= v_to;
    END IF;

    -- ---- 8. loan repayments (financing out) -------------------------------------
    IF to_regclass('public."GenericLoanPayments"') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'LoanRepayment'::text,
               FALSE,
               lp."GenericLoanPaymentId",
               lp."GenericCashAccountId",
               NULL::text,
               lp."PaymentDate"::timestamp,
               'CashOut'::text,
               'LoanRepayment'::text,
               lp."GenericLoanPaymentId",
               FALSE,
               -COALESCE(lp."TotalPayment", 0)::numeric,
               COALESCE(
                   NULLIF(btrim(lp."Notes"), ''),
                   'Loan repayment #' || lp."GenericLoanPaymentId"::text
               )::text,
               'FinancingOut'::text,
               lp."CreatedAt"::timestamp
        FROM   "GenericLoanPayments" lp
        WHERE  lp."FarmId" = p_farmid
          AND  COALESCE(lp."IsReversed", FALSE) = FALSE
          AND  COALESCE(lp."TotalPayment", 0) > 0
          AND  lp."PaymentDate"::timestamp >= v_from
          AND  lp."PaymentDate"::timestamp <= v_to;
    END IF;

    -- ---- 449a. supplier advances (the part of a payment not applied) -----------
    RETURN QUERY
    SELECT 'SupplierAdvance'::text,
           FALSE,
           sp.genericsupplierpaymentid,
           sp.genericcashaccountid,
           NULL::text,
           sp.paymentdate::timestamp,
           'CashOut'::text,
           'SupplierPayment'::text,
           sp.genericsupplierpaymentid,
           FALSE,
           -(sp.amount - COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                                   WHERE sa.farmid = sp.farmid AND sa.module = 'generic'
                                     AND sa.paymentid = sp.genericsupplierpaymentid
                                     AND sa.status = 'Posted' AND NOT sa.fromcredit), 0))::numeric,
           ('Supplier advance SP-' || lpad(sp.genericsupplierpaymentid::text, 5, '0'))::text,
           'OperatingOut'::text,
           sp.createdat::timestamp
    FROM   genericsupplierpayments sp
    WHERE  lower(sp.farmid::text) = lower(p_farmid)
      AND  public.fngenericsupplierpayment_isposted(sp.status, sp.sourcetype)
      AND  NOT public.fngenericsupplier_iscreditkind(sp.sourcetype)
      AND  sp.genericcashaccountid IS NOT NULL
      AND  sp.paymentdate::timestamp >= v_from
      AND  sp.paymentdate::timestamp <= v_to
      AND  sp.amount - COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                                 WHERE sa.farmid = sp.farmid AND sa.module = 'generic'
                                   AND sa.paymentid = sp.genericsupplierpaymentid
                                   AND sa.status = 'Posted' AND NOT sa.fromcredit), 0) > 0;

    -- ---- 449b. supplier refunds (money back from a supplier) -------------------
    RETURN QUERY
    SELECT 'SupplierRefund'::text,
           FALSE,
           r.refundid,
           r.genericcashaccountid,
           NULL::text,
           r.refunddate::timestamp,
           'CashIn'::text,
           'GenericSupplierRefund'::text,
           r.refundid,
           FALSE,
           r.amount::numeric,
           ('Supplier refund ' || r.refundnumber)::text,
           'OperatingIn'::text,
           r.createdat::timestamp
    FROM   genericsupplierrefunds r
    WHERE  lower(r.farmid::text) = lower(p_farmid)
      AND  r.status = 'Posted'
      AND  r.refunddate::timestamp >= v_from
      AND  r.refunddate::timestamp <= v_to;

    -- ---- 450. employee credit: money handed in (in), paid out (out), and the
    -- reversal of either on the day it was reversed ---------------------------
    RETURN QUERY
    SELECT 'EmployeeCredit'::text, FALSE, c.genericemployeecreditid, c.genericcashaccountid, NULL::text,
           CASE WHEN c.entrydate = c.createdat::date THEN c.createdat ELSE c.entrydate::timestamp END,
           CASE WHEN c.entrytype = 'Deposit' THEN 'CashIn' ELSE 'CashOut' END::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'EmployeeCreditDeposit' ELSE 'EmployeeCreditPayout' END::text,
           c.genericemployeecreditid, FALSE,
           (CASE WHEN c.entrytype = 'Deposit' THEN c.amount ELSE -c.amount END)::numeric,
           (CASE WHEN c.entrytype = 'Deposit' THEN 'Employee credit: money from ' ELSE 'Employee credit paid to ' END
             || btrim(s.firstname || ' ' || s.lastname))::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'OperatingIn' ELSE 'OperatingOut' END::text,
           c.createdat
    FROM   genericemployeecredits c JOIN genericstaff s ON s.genericstaffid = c.genericstaffid
    WHERE  lower(c.farmid::text) = lower(p_farmid) AND c.entrytype IN ('Deposit', 'Payout')
      AND  CASE WHEN c.entrydate = c.createdat::date THEN c.createdat ELSE c.entrydate::timestamp END BETWEEN v_from AND v_to;

    RETURN QUERY
    SELECT 'EmployeeCreditReversal'::text, FALSE, c.genericemployeecreditid, c.genericcashaccountid, NULL::text,
           c.reversedat,
           CASE WHEN c.entrytype = 'Deposit' THEN 'CashOut' ELSE 'CashIn' END::text,
           'EmployeeCreditReversal'::text, c.genericemployeecreditid, FALSE,
           (CASE WHEN c.entrytype = 'Deposit' THEN -c.amount ELSE c.amount END)::numeric,
           ('Reversal: employee credit ' || lower(c.entrytype) || ' for ' || btrim(s.firstname || ' ' || s.lastname))::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'OperatingOut' ELSE 'OperatingIn' END::text,
           c.reversedat
    FROM   genericemployeecredits c JOIN genericstaff s ON s.genericstaffid = c.genericstaffid
    WHERE  lower(c.farmid::text) = lower(p_farmid) AND c.entrytype IN ('Deposit', 'Payout')
      AND  c.status = 'Reversed' AND c.reversedat IS NOT NULL AND c.reversedat BETWEEN v_from AND v_to;

    -- ---- 453a. capital assets: cash paid at purchase, refunds on a correction or
    -- reversal, and disposal proceeds -- read from the cash ledger itself, so each
    -- movement counts once and only when money really moved.
    RETURN QUERY
    SELECT 'CapitalAsset'::text, FALSE, t.genericcashtransactionid::integer, t.genericcashaccountid, NULL::text,
           t.transactiondate, CASE WHEN t.amount >= 0 THEN 'CashIn' ELSE 'CashOut' END::text,
           t.sourcetype::text, t.sourceid, FALSE, t.amount::numeric,
           COALESCE(NULLIF(btrim(t.description), ''), 'Capital asset')::text,
           CASE WHEN t.amount >= 0 THEN 'OperatingIn' ELSE 'OperatingOut' END::text,
           t.createdat
    FROM   genericcashtransactions t
    WHERE  lower(t.farmid::text) = lower(p_farmid)
      AND  t.sourcetype IN ('CapitalAsset', 'CapitalAssetCost', 'AssetDisposal')
      AND  COALESCE(t.status, 'Approved') <> 'Reversed'
      AND  t.amount <> 0
      AND  t.transactiondate >= v_from
      AND  t.transactiondate <= v_to;

    -- ---- 453b. supplier payments applied to capital asset bills. The advance
    -- arm (449a) leaves every applied amount to its document; an asset bill is
    -- not an expense row, so its applied cash is counted here.
    RETURN QUERY
    SELECT 'CapitalAssetPayment'::text, FALSE, sa.allocationid, sp.genericcashaccountid, NULL::text,
           sp.paymentdate::timestamp, 'CashOut'::text, 'SupplierPayment'::text, sp.genericsupplierpaymentid, FALSE,
           -sa.amountapplied::numeric,
           ('Supplier payment SP-' || lpad(sp.genericsupplierpaymentid::text, 5, '0') || ' - capital asset')::text,
           'OperatingOut'::text,
           sa.createdat::timestamp
    FROM   supplierpaymentallocation sa
    JOIN   genericsupplierpayments sp ON sp.genericsupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
    WHERE  sa.module = 'generic' AND lower(sa.farmid) = lower(p_farmid)
      AND  sa.documenttype = 'CapitalAsset' AND sa.status = 'Posted' AND NOT sa.fromcredit
      AND  public.fngenericsupplierpayment_isposted(sp.status, sp.sourcetype)
      AND  NOT public.fngenericsupplier_iscreditkind(sp.sourcetype)
      AND  sp.genericcashaccountid IS NOT NULL
      AND  sp.paymentdate::timestamp >= v_from
      AND  sp.paymentdate::timestamp <= v_to;

    -- ---- 9. legacy cash adjustments (shared table) ------------------------------
    -- The cashadjustment table is used by all rails for capital events before
    -- dedicated owner-money and loan tables existed. Include any that belong
    -- to this farm.
    IF to_regclass('public.cashadjustment') IS NOT NULL OR
       to_regclass('public.cashadjustments') IS NOT NULL THEN

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
                   NULL::timestamp
            FROM   %s ca
            WHERE  lower(ca.farmid::text) = lower($1)
              AND  ca.amount <> 0
              AND  ca.adjustmentdate >= $2
              AND  ca.adjustmentdate <= $3
        $sql$, COALESCE(to_regclass('public.cashadjustment')::text,
                        to_regclass('public.cashadjustments')::text))
        USING p_farmid, v_from, v_to;
    END IF;
END;
$function$;

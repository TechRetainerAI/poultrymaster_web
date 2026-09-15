-- =============================================================================
-- 270_PoultryCapitalAssets.postgres.sql
--
-- Purpose
-- -------
-- Phase 3, part 2: the Asset Register. A poultry house, a feed mixer or a
-- generator is not this month's expense -- it is money the farm still owns.
--
-- THE ONE DECISION EVERYTHING ELSE FOLLOWS
-- ========================================
-- A capital acquisition rides the EXISTING expense rail. It writes an ordinary
-- `expense` row, classified CapitalAsset by 269, and that row is what moves the
-- cash, opens the supplier payable, appears on Supplier Balances, and gets
-- settled by an ordinary supplier payment.
--
-- Nothing about cash or payables is rebuilt here. The alternative -- a second
-- money rail for assets -- would mean a second Supplier Balances, a second cash
-- posting, a second reversal, and two sets of rules that would drift apart by
-- the second migration. The brief is explicit: do not create a parallel
-- accounting engine.
--
-- What makes an asset acquisition different from a bill is exactly ONE thing:
-- financialcosttype = 'CapitalAsset' keeps it out of profit. 269 already made
-- that mean something.
--
-- WHY THE ORIGINAL COST IS NOT A COLUMN
-- =====================================
-- A poultry house is built, not bought: cement, then wood, then labour, then
-- roofing. Storing originalcost as a number would mean a column that has to be
-- kept in step with the cost rows behind it, and the day they disagree there is
-- no way to tell which one is right.
--
-- So originalcost is the SUM of poultrycapitalassetcosts, always, and
-- fnpoultrycapitalasset_originalcost is the only place that sum is written.
-- That also gives §12's construction workflow for free: adding a cost to a
-- Draft asset is the same operation as acquiring one.
--
-- WHY THE DEPRECIATION TABLE IS DEFINED HERE
-- ==========================================
-- Because book value is not optional on an asset register, and book value needs
-- the depreciation ledger. The TABLE is here so the reads below can be written
-- once and be correct; the depreciation ENGINE -- generating, posting,
-- reversing -- is 271. Until 271 runs the table is empty and every asset reads
-- accumulated depreciation 0, which is exactly true.
--
-- WHAT THIS FILE IS NOT
-- =====================
-- It is not a general ledger, a chart of accounts, or journal entries. It is not
-- tax depreciation. It does not touch the P&L report (272 does). And it does not
-- reclassify one single historical expense: §77 is explicit that a row saying
-- "Generator" stays an expense until a human decides otherwise.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Asset categories. Per farm, seeded on demand, editable.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultryassetcategories (
    poultryassetcategoryid  serial PRIMARY KEY,
    farmid                  varchar(50)  NOT NULL,
    categoryname            varchar(80)  NOT NULL,
    -- A default life is a suggestion the form fills in, never a rule: two farms
    -- can disagree about how long a borehole pump lasts and both be right.
    defaultusefullifemonths integer,
    sortorder               integer      NOT NULL DEFAULT 0,
    isactive                boolean      NOT NULL DEFAULT TRUE,
    createdby               varchar(100),
    createdat               timestamp    NOT NULL DEFAULT (now() at time zone 'utc')
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryassetcategories_name
    ON poultryassetcategories (farmid, lower(categoryname));

-- -----------------------------------------------------------------------------
-- 2. The asset itself.
--
-- No originalcost, no accumulateddepreciation, no currentbookvalue: all three
-- are derived. What is stored is what a person decided -- the name, the life,
-- the residual value, the dates -- and nothing that a sum can answer.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultrycapitalassets (
    poultrycapitalassetid  serial PRIMARY KEY,
    farmid                 varchar(50)  NOT NULL,
    assetnumber            varchar(40)  NOT NULL,
    assetname              varchar(150) NOT NULL,
    poultryassetcategoryid integer REFERENCES poultryassetcategories(poultryassetcategoryid),
    description            varchar(500),
    acquisitiondate        date         NOT NULL,
    -- Depreciation starts here, not at acquisition: a house that is finished in
    -- March and stocked in June has not been earning anything since March.
    inservicedate          date,
    residualvalue          numeric(14,2) NOT NULL DEFAULT 0,
    usefullifemonths       integer,
    depreciationmethod     varchar(20)  NOT NULL DEFAULT 'StraightLine',
    supplierid             integer,
    location               varchar(150),
    serialnumber           varchar(80),
    status                 varchar(20)  NOT NULL DEFAULT 'Draft',
    disposaldate           date,
    disposalproceeds       numeric(14,2),
    disposalnotes          varchar(500),
    notes                  varchar(500),
    createdby              varchar(100),
    createdat              timestamp    NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby              varchar(100),
    updatedat              timestamp,
    reversedby             varchar(100),
    reversedat             timestamp,
    reversalreason         varchar(500),
    CONSTRAINT ck_poultrycapitalassets_status CHECK (status IN
        ('Draft', 'Active', 'FullyDepreciated', 'Disposed', 'Reversed')),
    CONSTRAINT ck_poultrycapitalassets_residual CHECK (residualvalue >= 0),
    CONSTRAINT ck_poultrycapitalassets_life CHECK (usefullifemonths IS NULL OR usefullifemonths > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrycapitalassets_number
    ON poultrycapitalassets (farmid, assetnumber);
CREATE INDEX IF NOT EXISTS ix_poultrycapitalassets_farm
    ON poultrycapitalassets (farmid, status);

-- -----------------------------------------------------------------------------
-- 3. Every cedi capitalised into an asset, and where it came from.
--
-- One row per capitalised cost. `expenseid` is the expense that moved the money
-- or opened the payable -- the link that makes "what did we pay, and to whom"
-- answerable without this table having to know anything about cash.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultrycapitalassetcosts (
    poultrycapitalassetcostid serial PRIMARY KEY,
    farmid                    varchar(50) NOT NULL,
    poultrycapitalassetid     integer     NOT NULL
        REFERENCES poultrycapitalassets(poultrycapitalassetid) ON DELETE CASCADE,
    costdate                  date        NOT NULL,
    description               varchar(300),
    costcategory              varchar(80),
    amount                    numeric(14,2) NOT NULL,
    -- Acquisition (the first cost) | AdditionalCost (built up over time).
    sourcetype                varchar(40) NOT NULL DEFAULT 'Acquisition',
    expenseid                 integer,
    supplierid                integer,
    status                    varchar(20) NOT NULL DEFAULT 'Posted',
    createdby                 varchar(100),
    createdat                 timestamp   NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby                varchar(100),
    reversedat                timestamp,
    reversalreason            varchar(500),
    CONSTRAINT ck_poultrycapitalassetcosts_amount CHECK (amount > 0),
    CONSTRAINT ck_poultrycapitalassetcosts_status CHECK (status IN ('Posted', 'Reversed'))
);

CREATE INDEX IF NOT EXISTS ix_poultrycapitalassetcosts_asset
    ON poultrycapitalassetcosts (poultrycapitalassetid, status);
CREATE INDEX IF NOT EXISTS ix_poultrycapitalassetcosts_expense
    ON poultrycapitalassetcosts (expenseid);

-- -----------------------------------------------------------------------------
-- 4. The depreciation ledger. Table only -- 271 owns the engine.
--
-- Append-only, like every other financial ledger here: a reversal writes an
-- opposite row and both are kept. `amount` is signed, so accumulated
-- depreciation is a SUM and never a subtraction of two half-truths.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultryassetdepreciation (
    poultryassetdepreciationid serial PRIMARY KEY,
    farmid                     varchar(50) NOT NULL,
    poultrycapitalassetid      integer     NOT NULL
        REFERENCES poultrycapitalassets(poultrycapitalassetid) ON DELETE CASCADE,
    periodstart                date        NOT NULL,
    periodend                  date        NOT NULL,
    depreciationdate           date        NOT NULL,
    amount                     numeric(14,2) NOT NULL,
    depreciationmethod         varchar(20) NOT NULL DEFAULT 'StraightLine',
    -- Scheduled (the monthly charge) | CatchUp | ManualAdjustment | Reversal.
    sourcetype                 varchar(30) NOT NULL DEFAULT 'Scheduled',
    status                     varchar(20) NOT NULL DEFAULT 'Posted',
    expenseid                  integer,
    reversalofid               integer REFERENCES poultryassetdepreciation(poultryassetdepreciationid),
    createdby                  varchar(100),
    createdat                  timestamp   NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby                 varchar(100),
    reversedat                 timestamp,
    reversalreason             varchar(500),
    CONSTRAINT ck_poultryassetdepreciation_status CHECK (status IN ('Posted', 'Reversed'))
);

-- One SCHEDULED charge per asset per period, and that index is the whole of
-- §15's "prevent duplicate depreciation": pressing Generate twice cannot charge
-- the same month twice, whatever the caller believes. Reversals and manual
-- adjustments are deliberately outside it -- there can be several of those.
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryassetdepreciation_period
    ON poultryassetdepreciation (poultrycapitalassetid, periodstart)
    WHERE sourcetype = 'Scheduled';

CREATE INDEX IF NOT EXISTS ix_poultryassetdepreciation_farm
    ON poultryassetdepreciation (farmid, depreciationdate);

-- -----------------------------------------------------------------------------
-- 5. The link from an expense row back to its asset.
--
-- 269 said a CapitalAsset expense exists; this says which asset it belongs to,
-- so the Expenses page can offer "open the asset" rather than showing a cost
-- with nowhere to go.
-- -----------------------------------------------------------------------------
ALTER TABLE expense ADD COLUMN IF NOT EXISTS poultrycapitalassetid integer;
CREATE INDEX IF NOT EXISTS ix_expense_capitalasset ON expense (poultrycapitalassetid);

-- And the read exposes it, so the Expenses page can offer "open the asset"
-- rather than showing a capital cost with nowhere to go. Appended to the end of
-- the composite type, like 269's columns, so no existing ordinal moves.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_attribute
                   WHERE attrelid = 'poultryexpenserow'::regclass
                     AND attname = 'poultrycapitalassetid' AND NOT attisdropped) THEN
        ALTER TYPE poultryexpenserow ADD ATTRIBUTE poultrycapitalassetid integer CASCADE;
        ALTER TYPE poultryexpenserow ADD ATTRIBUTE capitalassetname text CASCADE;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fnpoultryexpenserows(p_farmid uuid)
 RETURNS SETOF poultryexpenserow
 LANGUAGE sql
 STABLE
AS $function$
    SELECT e.expenseid,
           e.expensedate,
           e.category::text,
           e.description::text,
           e.amount::numeric(14,2),
           e.paymentmethod::text,
           e.supplier::text,
           e.supplierid,
           s.name::text,
           COALESCE(e.amountpaid, e.amount)::numeric(14,2),
           GREATEST(COALESCE(e.amount, 0) - COALESCE(e.amountpaid, e.amount), 0)::numeric(14,2),
           e.paymentstatus::text,
           e.duedate,
           e.flockid,
           e.poultrycashaccountid,
           e.sourcetype::text,
           e.sourceid,
           e.createddate,
           e.farmid,
           e.userid::text,
           (e.attachmentimage IS NOT NULL),
           -- 269. What kind of cost, which P&L line, which band, and where it
           -- came from -- resolved server-side so no screen has to re-derive it.
           c.costtype,
           (COALESCE(e.financialcosttype, '') <> ''),
           l.line,
           fnpoultryexpense_pllinelabel(l.line),
           fnpoultryexpense_plsection(l.line),
           fnpoultryexpense_sourcelabel(e.sourcetype::text),
           -- 270. The asset a capital cost belongs to.
           e.poultrycapitalassetid,
           ca.assetname::text
    FROM   expense e
    LEFT   JOIN supplier s
           ON  s.supplierid = e.supplierid
           AND lower(s.farmid::text) = lower(e.farmid::text)
    LEFT   JOIN poultrycapitalassets ca
           ON  ca.poultrycapitalassetid = e.poultrycapitalassetid
    CROSS  JOIN LATERAL (SELECT fnpoultryexpense_costtype(
                                    e.financialcosttype::text, e.sourcetype::text,
                                    e.category::text, e.paymentmethod::text) AS costtype) c
    CROSS  JOIN LATERAL (SELECT fnpoultryexpense_plline(
                                    c.costtype, e.sourcetype::text, e.category::text,
                                    fnpoultryexpense_itemcategory(e.sourcetype::text, e.sourceid)) AS line) l
    WHERE  e.farmid = p_farmid;
$function$;

-- -----------------------------------------------------------------------------
-- 6. The derived numbers, defined once.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrycapitalasset_originalcost(p_assetid integer)
RETURNS numeric
LANGUAGE sql STABLE
AS $function$
    SELECT COALESCE(SUM(c.amount), 0)::numeric(14,2)
    FROM   poultrycapitalassetcosts c
    WHERE  c.poultrycapitalassetid = p_assetid AND c.status = 'Posted';
$function$;

CREATE OR REPLACE FUNCTION public.fnpoultrycapitalasset_accumulated(p_assetid integer)
RETURNS numeric
LANGUAGE sql STABLE
AS $function$
    -- Signed sum over an append-only ledger: a reversal is a negative row, so
    -- this needs no knowledge of which rows reversed which.
    SELECT COALESCE(SUM(d.amount), 0)::numeric(14,2)
    FROM   poultryassetdepreciation d
    WHERE  d.poultrycapitalassetid = p_assetid;
$function$;

CREATE OR REPLACE FUNCTION public.fnpoultrycapitalasset_monthly(
    p_originalcost numeric, p_residual numeric, p_lifemonths integer
) RETURNS numeric
LANGUAGE sql IMMUTABLE
AS $function$
    -- Straight line, and only straight line. GREATEST guards the case an owner
    -- enters a residual above what the asset cost: the charge is zero, not a
    -- negative depreciation that would quietly increase profit.
    SELECT ROUND(GREATEST(COALESCE(p_originalcost, 0) - COALESCE(p_residual, 0), 0)
                 / NULLIF(p_lifemonths, 0), 2);
$function$;

COMMENT ON FUNCTION public.fnpoultrycapitalasset_monthly(numeric, numeric, integer) IS
    'Straight-line monthly charge: (cost - residual) / life in months. NULL when '
    'no useful life is set, which is what a Draft asset looks like.';

-- The whole financial picture of one asset, in one place, so the register, the
-- detail page and the depreciation engine cannot compute it three ways.
CREATE OR REPLACE FUNCTION public.fnpoultrycapitalasset_financials(p_assetid integer)
 RETURNS TABLE(originalcost numeric, residualvalue numeric, depreciableamount numeric,
               usefullifemonths integer, monthlydepreciation numeric,
               accumulateddepreciation numeric, currentbookvalue numeric,
               remainingdepreciable numeric, isfullydepreciated boolean)
LANGUAGE sql STABLE
AS $function$
    SELECT o.cost,
           a.residualvalue,
           GREATEST(o.cost - a.residualvalue, 0)::numeric(14,2),
           a.usefullifemonths,
           fnpoultrycapitalasset_monthly(o.cost, a.residualvalue, a.usefullifemonths),
           d.acc,
           -- Book value can never fall below residual value (§20). Anything
           -- lower would say the farm owns less than it agreed it still owns.
           GREATEST(o.cost - d.acc, a.residualvalue)::numeric(14,2),
           GREATEST(GREATEST(o.cost - a.residualvalue, 0) - d.acc, 0)::numeric(14,2),
           (GREATEST(o.cost - a.residualvalue, 0) - d.acc) <= 0.004
    FROM   poultrycapitalassets a
    CROSS  JOIN LATERAL (SELECT fnpoultrycapitalasset_originalcost(a.poultrycapitalassetid) AS cost) o
    CROSS  JOIN LATERAL (SELECT fnpoultrycapitalasset_accumulated(a.poultrycapitalassetid) AS acc) d
    WHERE  a.poultrycapitalassetid = p_assetid;
$function$;

-- -----------------------------------------------------------------------------
-- 7. Seeded categories.
--
-- Idempotent and per farm, following spcompany_create's shape: a farm that has
-- never opened the page gets the list on first read, and one that has renamed
-- "Vehicles" to "Trucks" keeps its name.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryassetcategory_ensuredefaults(
    p_farmid text, p_createdby text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO poultryassetcategories (farmid, categoryname, defaultusefullifemonths, sortorder, createdby)
    SELECT p_farmid, d.name, d.life, d.ord, p_createdby
    FROM  (VALUES
              ('Buildings / Poultry Houses', 240, 1),
              ('Vehicles',                    60, 2),
              ('Machinery',                  120, 3),
              ('Feed Equipment',              84, 4),
              ('Farm Equipment',              60, 5),
              ('Generators',                  84, 6),
              ('Borehole / Water Equipment', 120, 7),
              ('Cages',                       96, 8),
              ('Furniture',                   60, 9),
              ('IT / Computer Equipment',     36, 10),
              ('Land Improvements',          240, 11),
              ('Office Equipment',            60, 12),
              ('Other Assets',                60, 13)
          ) AS d(name, life, ord)
    WHERE NOT EXISTS (
        SELECT 1 FROM poultryassetcategories c
        WHERE  c.farmid = p_farmid AND lower(c.categoryname) = lower(d.name));
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryassetcategory_getall(p_farmid text)
 RETURNS TABLE(poultryassetcategoryid integer, farmid text, categoryname text,
               defaultusefullifemonths integer, sortorder integer, isactive boolean,
               assetcount integer)
LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM sppoultryassetcategory_ensuredefaults(p_farmid, NULL);

    RETURN QUERY
    SELECT c.poultryassetcategoryid, c.farmid::text, c.categoryname::text,
           c.defaultusefullifemonths, c.sortorder, c.isactive,
           (SELECT COUNT(*)::integer FROM poultrycapitalassets a
             WHERE a.poultryassetcategoryid = c.poultryassetcategoryid
               AND a.status <> 'Reversed')
    FROM   poultryassetcategories c
    WHERE  c.farmid = p_farmid
    ORDER  BY c.sortorder, c.categoryname;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryassetcategory_upsert(
    p_farmid text, p_poultryassetcategoryid integer, p_categoryname text,
    p_defaultusefullifemonths integer DEFAULT NULL, p_isactive boolean DEFAULT TRUE,
    p_createdby text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id integer := p_poultryassetcategoryid;
BEGIN
    IF COALESCE(btrim(p_categoryname), '') = '' THEN
        RAISE EXCEPTION 'Category name is required.';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO poultryassetcategories (farmid, categoryname, defaultusefullifemonths,
                                            sortorder, isactive, createdby)
        VALUES (p_farmid, btrim(p_categoryname), p_defaultusefullifemonths,
                COALESCE((SELECT MAX(c.sortorder) + 1 FROM poultryassetcategories c
                           WHERE c.farmid = p_farmid), 1),
                COALESCE(p_isactive, TRUE), p_createdby)
        RETURNING poultryassetcategoryid INTO v_id;
    ELSE
        UPDATE poultryassetcategories c
        SET    categoryname = btrim(p_categoryname),
               defaultusefullifemonths = p_defaultusefullifemonths,
               isactive = COALESCE(p_isactive, c.isactive)
        WHERE  c.poultryassetcategoryid = v_id AND c.farmid = p_farmid;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Asset category does not belong to this company.';
        END IF;
    END IF;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 8. The money leg, written once and used by both writers.
--
-- Creates the expense row that IS the acquisition's cash and payable, then
-- stamps it CapitalAsset. The stamp is applied here rather than passed to
-- spexpense_insert because 269 deliberately refuses that value: an expense
-- classified capital with no asset behind it would leave profit AND never be
-- depreciated, so the money would disappear from both sides of the report. This
-- is the one place that knows there is an asset.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycapitalassetexpense_post(
    p_farmid       text,
    p_assetid      integer,
    p_date         date,
    p_category     text,
    p_description  text,
    p_amount       numeric,
    p_paymentmethod text,
    p_supplier     text,
    p_supplierid   integer,
    p_amountpaid   numeric,
    p_duedate      date,
    p_cashaccountid integer,
    p_createdby    text
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_expid integer;
    v_uuid  uuid;
BEGIN
    v_uuid := p_farmid::uuid;

    v_expid := spexpense_insert(
        p_expensedate   => p_date::timestamp,
        p_category      => COALESCE(NULLIF(btrim(p_category), ''), 'Capital Asset'),
        p_description   => p_description,
        p_amount        => p_amount,
        p_paymentmethod => COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash'),
        p_supplier      => p_supplier,
        p_flockid       => NULL,
        p_userid        => p_createdby,
        p_farmid        => v_uuid,
        p_supplierid    => p_supplierid,
        p_amountpaid    => p_amountpaid,
        p_duedate       => p_duedate,
        p_cashaccountid => p_cashaccountid);

    UPDATE expense e
    SET    financialcosttype = 'CapitalAsset',
           sourcetype        = 'CapitalAsset',
           sourceid          = p_assetid,
           poultrycapitalassetid = p_assetid
    WHERE  e.expenseid = v_expid AND e.farmid = v_uuid;

    -- With a supplier, spexpense_insert has already recorded the payment and its
    -- CashOut. Without one there is nobody to owe, so the cash leg is this
    -- expense's own -- exactly the path a cash bill takes today.
    IF p_supplierid IS NULL AND p_cashaccountid IS NOT NULL THEN
        PERFORM sppoultryexpensecash_sync(p_farmid, v_expid, p_cashaccountid, p_amount,
                                          p_description, p_createdby);
    END IF;

    RETURN v_expid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 9. Create an asset.
--
-- The acquisition amount is optional: a house that will be built cost by cost
-- starts at zero and grows. That is §12's construction project, without a
-- second workflow to maintain.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycapitalasset_create(
    p_farmid            text,
    p_assetname         text,
    p_assetcategoryid   integer DEFAULT NULL,
    p_description       text    DEFAULT NULL,
    p_acquisitiondate   date    DEFAULT NULL,
    p_inservicedate     date    DEFAULT NULL,
    p_amount            numeric DEFAULT NULL,
    p_residualvalue     numeric DEFAULT 0,
    p_usefullifemonths  integer DEFAULT NULL,
    p_supplier          text    DEFAULT NULL,
    p_supplierid        integer DEFAULT NULL,
    p_paymentmethod     text    DEFAULT 'Cash',
    p_amountpaid        numeric DEFAULT NULL,
    p_duedate           date    DEFAULT NULL,
    p_cashaccountid     integer DEFAULT NULL,
    p_expensecategory   text    DEFAULT NULL,
    p_location          text    DEFAULT NULL,
    p_serialnumber      text    DEFAULT NULL,
    p_notes             text    DEFAULT NULL,
    p_createdby         text    DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id     integer;
    v_number text;
    v_date   date := COALESCE(p_acquisitiondate, (now() at time zone 'utc')::date);
    v_expid  integer;
    v_status text;
BEGIN
    IF COALESCE(btrim(p_assetname), '') = '' THEN
        RAISE EXCEPTION 'Asset name is required.';
    END IF;
    IF p_amount IS NOT NULL AND p_amount <= 0 THEN
        RAISE EXCEPTION 'Asset cost must be greater than 0.';
    END IF;
    IF p_assetcategoryid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM poultryassetcategories c
                       WHERE c.poultryassetcategoryid = p_assetcategoryid AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Asset category does not belong to this company.';
    END IF;
    IF p_supplierid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM supplier s
                       WHERE s.supplierid = p_supplierid AND lower(s.farmid::text) = lower(p_farmid)) THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;
    IF p_inservicedate IS NOT NULL AND p_inservicedate < v_date THEN
        RAISE EXCEPTION 'An asset cannot be in service before it was acquired.';
    END IF;

    -- Per-farm running number, taken under the farm's own row lock so two
    -- simultaneous saves cannot both claim AST-0007.
    PERFORM 1 FROM poultrycapitalassets a WHERE a.farmid = p_farmid FOR UPDATE;
    SELECT 'AST-' || lpad((COALESCE(MAX(substring(a.assetnumber from '[0-9]+$')::integer), 0) + 1)::text, 4, '0')
      INTO v_number
    FROM   poultrycapitalassets a
    WHERE  a.farmid = p_farmid AND a.assetnumber ~ '^AST-[0-9]+$';
    v_number := COALESCE(v_number, 'AST-0001');

    -- An asset is Active once it is earning: it is in service and the farm has
    -- said how long it will last. Anything else is still Draft, and Draft is
    -- what a half-built house is.
    v_status := CASE WHEN p_inservicedate IS NOT NULL AND COALESCE(p_usefullifemonths, 0) > 0
                     THEN 'Active' ELSE 'Draft' END;

    INSERT INTO poultrycapitalassets
        (farmid, assetnumber, assetname, poultryassetcategoryid, description,
         acquisitiondate, inservicedate, residualvalue, usefullifemonths,
         depreciationmethod, supplierid, location, serialnumber, status, notes, createdby)
    VALUES
        (p_farmid, v_number, btrim(p_assetname), p_assetcategoryid, p_description,
         v_date, p_inservicedate, COALESCE(p_residualvalue, 0), p_usefullifemonths,
         'StraightLine', p_supplierid, p_location, p_serialnumber, v_status, p_notes, p_createdby)
    RETURNING poultrycapitalassetid INTO v_id;

    IF COALESCE(p_amount, 0) > 0 THEN
        v_expid := sppoultrycapitalassetexpense_post(
            p_farmid, v_id, v_date,
            COALESCE(p_expensecategory, 'Capital Asset'),
            btrim(p_assetname), p_amount, p_paymentmethod,
            p_supplier, p_supplierid, p_amountpaid, p_duedate, p_cashaccountid, p_createdby);

        INSERT INTO poultrycapitalassetcosts
            (farmid, poultrycapitalassetid, costdate, description, costcategory,
             amount, sourcetype, expenseid, supplierid, createdby)
        VALUES
            (p_farmid, v_id, v_date, btrim(p_assetname), 'Acquisition',
             p_amount, 'Acquisition', v_expid, p_supplierid, p_createdby);
    END IF;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 10. Add a cost to an asset. The construction workflow.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycapitalassetcost_add(
    p_farmid          text,
    p_assetid         integer,
    p_costdate        date,
    p_description     text,
    p_costcategory    text,
    p_amount          numeric,
    p_supplier        text    DEFAULT NULL,
    p_supplierid      integer DEFAULT NULL,
    p_paymentmethod   text    DEFAULT 'Cash',
    p_amountpaid      numeric DEFAULT NULL,
    p_duedate         date    DEFAULT NULL,
    p_cashaccountid   integer DEFAULT NULL,
    p_expensecategory text    DEFAULT NULL,
    p_createdby       text    DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_name   text;
    v_expid  integer;
    v_id     integer;
    v_date   date := COALESCE(p_costdate, (now() at time zone 'utc')::date);
BEGIN
    SELECT a.status, a.assetname INTO v_status, v_name
    FROM   poultrycapitalassets a
    WHERE  a.poultrycapitalassetid = p_assetid AND a.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;
    IF v_status IN ('Reversed', 'Disposed') THEN
        RAISE EXCEPTION 'Cannot add cost to a % asset.', lower(v_status);
    END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Cost amount must be greater than 0.';
    END IF;

    -- Adding cost to an asset that is already being depreciated would change the
    -- monthly charge under months that have already been posted, and every one
    -- of those months would then be wrong. §58: block the unsafe edit rather
    -- than pretend to handle it.
    IF EXISTS (SELECT 1 FROM poultryassetdepreciation d
               WHERE d.poultrycapitalassetid = p_assetid AND d.status = 'Posted') THEN
        RAISE EXCEPTION 'Depreciation has already been posted for this asset. Reverse it before changing the asset cost.';
    END IF;

    v_expid := sppoultrycapitalassetexpense_post(
        p_farmid, p_assetid, v_date,
        COALESCE(p_expensecategory, 'Capital Asset'),
        COALESCE(NULLIF(btrim(p_description), ''), v_name),
        p_amount, p_paymentmethod, p_supplier, p_supplierid,
        p_amountpaid, p_duedate, p_cashaccountid, p_createdby);

    INSERT INTO poultrycapitalassetcosts
        (farmid, poultrycapitalassetid, costdate, description, costcategory,
         amount, sourcetype, expenseid, supplierid, createdby)
    VALUES
        (p_farmid, p_assetid, v_date, p_description, p_costcategory,
         p_amount, 'AdditionalCost', v_expid, p_supplierid, p_createdby)
    RETURNING poultrycapitalassetcostid INTO v_id;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 11. Edit an asset.
--
-- Metadata is always editable. The four financial fields -- cost is not among
-- them, it is the cost rows -- are frozen once depreciation has been posted,
-- because changing a useful life retroactively silently invalidates every
-- month already charged.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycapitalasset_update(
    p_farmid           text,
    p_assetid          integer,
    p_assetname        text,
    p_assetcategoryid  integer DEFAULT NULL,
    p_description      text    DEFAULT NULL,
    p_location         text    DEFAULT NULL,
    p_serialnumber     text    DEFAULT NULL,
    p_notes            text    DEFAULT NULL,
    p_inservicedate    date    DEFAULT NULL,
    p_usefullifemonths integer DEFAULT NULL,
    p_residualvalue    numeric DEFAULT NULL,
    p_setfinancials    boolean DEFAULT FALSE,
    p_updatedby        text    DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status  text;
    v_acqdate date;
    v_posted  boolean;
    v_cost    numeric(14,2);
BEGIN
    SELECT a.status, a.acquisitiondate INTO v_status, v_acqdate
    FROM   poultrycapitalassets a
    WHERE  a.poultrycapitalassetid = p_assetid AND a.farmid = p_farmid;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;
    IF v_status = 'Reversed' THEN
        RAISE EXCEPTION 'A reversed asset cannot be edited.';
    END IF;

    v_posted := EXISTS (SELECT 1 FROM poultryassetdepreciation d
                        WHERE d.poultrycapitalassetid = p_assetid AND d.status = 'Posted');

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
        v_cost := fnpoultrycapitalasset_originalcost(p_assetid);
        IF p_residualvalue IS NOT NULL AND p_residualvalue > v_cost AND v_cost > 0 THEN
            RAISE EXCEPTION 'Residual value (%) cannot be more than the asset cost (%).',
                  p_residualvalue::numeric(14,2), v_cost;
        END IF;
    END IF;

    UPDATE poultrycapitalassets a
    SET    assetname = COALESCE(NULLIF(btrim(p_assetname), ''), a.assetname),
           poultryassetcategoryid = COALESCE(p_assetcategoryid, a.poultryassetcategoryid),
           description  = p_description,
           location     = p_location,
           serialnumber = p_serialnumber,
           notes        = p_notes,
           inservicedate    = CASE WHEN p_setfinancials THEN p_inservicedate ELSE a.inservicedate END,
           usefullifemonths = CASE WHEN p_setfinancials THEN p_usefullifemonths ELSE a.usefullifemonths END,
           residualvalue    = CASE WHEN p_setfinancials THEN COALESCE(p_residualvalue, 0) ELSE a.residualvalue END,
           -- Setting a life and a date is what puts an asset into service, so
           -- the status follows rather than needing its own button.
           status = CASE WHEN a.status IN ('Draft', 'Active') AND p_setfinancials THEN
                             CASE WHEN p_inservicedate IS NOT NULL AND COALESCE(p_usefullifemonths, 0) > 0
                                  THEN 'Active' ELSE 'Draft' END
                         ELSE a.status END,
           updatedby = p_updatedby,
           updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycapitalassetid = p_assetid AND a.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 12. Dispose.
--
-- Status, dates, notes, and proceeds that reach CASH but not profit. Gain or
-- loss on disposal is deliberately NOT computed: doing it properly means
-- comparing proceeds with book value and recognising the difference, and a
-- half-done version would report a gain the farm never made. It is named as
-- future work in the header of the register instead of guessed at here.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycapitalasset_dispose(
    p_farmid        text,
    p_assetid       integer,
    p_disposaldate  date,
    p_proceeds      numeric DEFAULT NULL,
    p_cashaccountid integer DEFAULT NULL,
    p_notes         text    DEFAULT NULL,
    p_createdby     text    DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_name   text;
    v_bal    numeric(14,2);
    v_date   date := COALESCE(p_disposaldate, (now() at time zone 'utc')::date);
BEGIN
    SELECT a.status, a.assetname INTO v_status, v_name
    FROM   poultrycapitalassets a
    WHERE  a.poultrycapitalassetid = p_assetid AND a.farmid = p_farmid;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;
    IF v_status IN ('Disposed', 'Reversed') THEN
        RAISE EXCEPTION 'This asset is already %.', lower(v_status);
    END IF;
    IF COALESCE(p_proceeds, 0) > 0 AND p_cashaccountid IS NULL THEN
        RAISE EXCEPTION 'Select the cash account the sale proceeds went into.';
    END IF;

    UPDATE poultrycapitalassets a
    SET    status = 'Disposed', disposaldate = v_date,
           disposalproceeds = p_proceeds, disposalnotes = p_notes,
           updatedby = p_createdby, updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycapitalassetid = p_assetid AND a.farmid = p_farmid;

    -- Money in. Cash only: selling a machine is not trading income and must not
    -- appear as revenue.
    IF COALESCE(p_proceeds, 0) > 0 THEN
        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance + p_proceeds,
               updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = p_cashaccountid AND a.farmid = p_farmid;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Cash account does not belong to this company.';
        END IF;

        SELECT a.currentbalance INTO v_bal FROM poultrycashaccounts a
        WHERE  a.poultrycashaccountid = p_cashaccountid;

        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, p_cashaccountid, v_date::timestamp, 'CashIn', 'AssetDisposal', p_assetid,
             p_proceeds, v_bal, 'Disposal of ' || v_name, p_createdby, p_createdby,
             (now() at time zone 'utc'));
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 13. Reverse an acquisition.
--
-- Refused outright once anything downstream depends on it. §57 asks for exactly
-- this: do not silently corrupt history. The three refusals are depreciation,
-- supplier payments, and disposal -- each of them a record that would be left
-- pointing at nothing.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycapitalasset_reverse(
    p_farmid    text,
    p_assetid   integer,
    p_reason    text,
    p_createdby text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_uuid   uuid := p_farmid::uuid;
    r        record;
BEGIN
    SELECT a.status INTO v_status
    FROM   poultrycapitalassets a
    WHERE  a.poultrycapitalassetid = p_assetid AND a.farmid = p_farmid;
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

    IF EXISTS (SELECT 1 FROM poultryassetdepreciation d
               WHERE d.poultrycapitalassetid = p_assetid AND d.status = 'Posted') THEN
        RAISE EXCEPTION 'Depreciation has been posted for this asset. Reverse the depreciation first.';
    END IF;

    IF EXISTS (SELECT 1
               FROM   poultrycapitalassetcosts c
               JOIN   supplierpaymentallocation sa
                 ON   sa.documenttype = 'Expense' AND sa.documentid = c.expenseid
                AND   lower(sa.farmid) = lower(p_farmid) AND sa.module = 'poultry'
                AND   sa.status = 'Posted'
               WHERE  c.poultrycapitalassetid = p_assetid AND c.status = 'Posted') THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this asset. Reverse the payment on Supplier Payments first.';
    END IF;

    -- Unwind each cost's money leg, then remove it. Zeroing amountpaid before
    -- the resync is what hands the cash back: resync reverses whatever it posted
    -- and re-posts nothing.
    FOR r IN SELECT c.poultrycapitalassetcostid, c.expenseid
             FROM   poultrycapitalassetcosts c
             WHERE  c.poultrycapitalassetid = p_assetid AND c.status = 'Posted'
    LOOP
        IF r.expenseid IS NOT NULL THEN
            UPDATE expense e SET amountpaid = 0
            WHERE  e.expenseid = r.expenseid AND e.farmid = v_uuid;
            PERFORM sppoultryexpensecash_resync(p_farmid, r.expenseid, p_createdby);
            DELETE FROM expense e WHERE e.expenseid = r.expenseid AND e.farmid = v_uuid;
        END IF;

        UPDATE poultrycapitalassetcosts c
        SET    status = 'Reversed', reversedby = p_createdby,
               reversedat = (now() at time zone 'utc'), reversalreason = p_reason
        WHERE  c.poultrycapitalassetcostid = r.poultrycapitalassetcostid;
    END LOOP;

    UPDATE poultrycapitalassets a
    SET    status = 'Reversed', reversedby = p_createdby,
           reversedat = (now() at time zone 'utc'), reversalreason = p_reason,
           updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycapitalassetid = p_assetid AND a.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 14. Reads.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycapitalasset_getall(
    p_farmid text, p_status text DEFAULT NULL, p_categoryid integer DEFAULT NULL
) RETURNS TABLE(poultrycapitalassetid integer, farmid text, assetnumber text, assetname text,
                poultryassetcategoryid integer, categoryname text, description text,
                acquisitiondate date, inservicedate date, location text, serialnumber text,
                supplierid integer, suppliername text, status text, notes text,
                originalcost numeric, residualvalue numeric, depreciableamount numeric,
                usefullifemonths integer, monthlydepreciation numeric,
                accumulateddepreciation numeric, currentbookvalue numeric,
                remainingdepreciable numeric, isfullydepreciated boolean,
                costentries integer, depreciationentries integer,
                disposaldate date, disposalproceeds numeric,
                createdby text, createdat timestamp without time zone,
                updatedat timestamp without time zone,
                reversedby text, reversedat timestamp without time zone, reversalreason text)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT a.poultrycapitalassetid, a.farmid::text, a.assetnumber::text, a.assetname::text,
           a.poultryassetcategoryid, c.categoryname::text, a.description::text,
           a.acquisitiondate, a.inservicedate, a.location::text, a.serialnumber::text,
           a.supplierid, s.name::text, a.status::text, a.notes::text,
           f.originalcost, f.residualvalue, f.depreciableamount,
           f.usefullifemonths, f.monthlydepreciation,
           f.accumulateddepreciation, f.currentbookvalue,
           f.remainingdepreciable, f.isfullydepreciated,
           (SELECT COUNT(*)::integer FROM poultrycapitalassetcosts cc
             WHERE cc.poultrycapitalassetid = a.poultrycapitalassetid AND cc.status = 'Posted'),
           (SELECT COUNT(*)::integer FROM poultryassetdepreciation dd
             WHERE dd.poultrycapitalassetid = a.poultrycapitalassetid AND dd.status = 'Posted'),
           a.disposaldate, a.disposalproceeds,
           a.createdby::text, a.createdat, a.updatedat,
           a.reversedby::text, a.reversedat, a.reversalreason::text
    FROM   poultrycapitalassets a
    LEFT   JOIN poultryassetcategories c ON c.poultryassetcategoryid = a.poultryassetcategoryid
    LEFT   JOIN supplier s ON s.supplierid = a.supplierid
    CROSS  JOIN LATERAL fnpoultrycapitalasset_financials(a.poultrycapitalassetid) f
    WHERE  a.farmid = p_farmid
      AND  (p_status IS NULL OR a.status = p_status)
      AND  (p_categoryid IS NULL OR a.poultryassetcategoryid = p_categoryid)
    ORDER  BY a.acquisitiondate DESC, a.poultrycapitalassetid DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrycapitalassetcost_getall(
    p_farmid text, p_assetid integer
) RETURNS TABLE(poultrycapitalassetcostid integer, poultrycapitalassetid integer,
                costdate date, description text, costcategory text, amount numeric,
                sourcetype text, expenseid integer, supplierid integer, suppliername text,
                paymentstatus text, amountpaid numeric, balance numeric,
                status text, createdby text, createdat timestamp without time zone,
                reversedby text, reversedat timestamp without time zone, reversalreason text)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT c.poultrycapitalassetcostid, c.poultrycapitalassetid,
           c.costdate, c.description::text, c.costcategory::text, c.amount,
           c.sourcetype::text, c.expenseid, c.supplierid, s.name::text,
           e.paymentstatus::text,
           COALESCE(e.amountpaid, e.amount)::numeric(14,2),
           GREATEST(COALESCE(e.amount, 0) - COALESCE(e.amountpaid, e.amount), 0)::numeric(14,2),
           c.status::text, c.createdby::text, c.createdat,
           c.reversedby::text, c.reversedat, c.reversalreason::text
    FROM   poultrycapitalassetcosts c
    LEFT   JOIN expense e ON e.expenseid = c.expenseid
    LEFT   JOIN supplier s ON s.supplierid = c.supplierid
    WHERE  c.farmid = p_farmid AND c.poultrycapitalassetid = p_assetid
    ORDER  BY c.costdate, c.poultrycapitalassetcostid;
END;
$function$;

-- The five cards at the top of the register. Book value is a BALANCE, never a
-- period total (§61): it is what the farm owns today, not what it acquired
-- between two dates. Only "added in period" is period-scoped, and it says so.
CREATE OR REPLACE FUNCTION public.sppoultrycapitalasset_summary(
    p_farmid text, p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL
) RETURNS TABLE(totalassets integer, activeassets integer, draftassets integer,
                disposedassets integer, fullydepreciated integer,
                totalassetcost numeric, accumulateddepreciation numeric,
                currentbookvalue numeric, addedinperiod numeric, addedcount integer)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH live AS (
        SELECT a.poultrycapitalassetid, a.status, a.acquisitiondate, f.*
        FROM   poultrycapitalassets a
        CROSS  JOIN LATERAL fnpoultrycapitalasset_financials(a.poultrycapitalassetid) f
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
           COALESCE((SELECT SUM(cc.amount) FROM poultrycapitalassetcosts cc
                      WHERE cc.farmid = p_farmid AND cc.status = 'Posted'
                        AND (p_fromdate IS NULL OR cc.costdate >= p_fromdate)
                        AND (p_todate   IS NULL OR cc.costdate <= p_todate)), 0)::numeric(14,2),
           COALESCE((SELECT COUNT(*) FROM poultrycapitalassets aa
                      WHERE aa.farmid = p_farmid AND aa.status <> 'Reversed'
                        AND (p_fromdate IS NULL OR aa.acquisitiondate >= p_fromdate)
                        AND (p_todate   IS NULL OR aa.acquisitiondate <= p_todate)), 0)::integer
    FROM   live l;
END;
$function$;

-- -----------------------------------------------------------------------------
-- Post-conditions. New tables only -- nothing that existed has moved.
-- -----------------------------------------------------------------------------
SELECT 'no assets exist yet' AS check, COUNT(*) AS should_be_zero FROM poultrycapitalassets;

SELECT 'no expense is capital yet' AS check, COUNT(*) AS should_be_zero
FROM   expense WHERE financialcosttype = 'CapitalAsset';

SELECT 'no depreciation exists yet' AS check, COUNT(*) AS should_be_zero
FROM   poultryassetdepreciation;

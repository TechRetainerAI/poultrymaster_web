-- =============================================================================
-- 282_WaterFinancialCostType.postgres.sql
--
-- Purpose
-- -------
-- The water mirror of 269. Phase 3, part 1: say what KIND of financial cost a
-- row is, so the Profit & Loss report can stop guessing from words in a
-- description.
--
-- TWO QUESTIONS, TWO ANSWERS
-- ==========================
-- 274 asked WHEN an inventory cost reaches Profit & Loss and answered with
-- costrecognitionmethod. This file asks WHAT KIND of cost it is and answers with
-- financialcosttype. They are not alternatives and neither replaces the other:
--
--   costrecognitionmethod   EXPENSE_WHEN_PURCHASED | EXPENSE_WHEN_CONSUMED
--   financialcosttype       OperatingExpense | InventoryPurchase | CapitalAsset
--                           NonCashExpense   | FinancingExpense
--
-- A roll of sachet film can be EXPENSE_WHEN_CONSUMED and an InventoryPurchase at
-- the same time; a borehole is a CapitalAsset and has no recognition method at
-- all.
--
-- WHERE WATER DIFFERS FROM POULTRY, AND WHY IT MATTERS
-- ====================================================
--
-- 1. A DIFFERENT TABLE. Poultry classifies rows in the shared `expense` table.
--    Water has its own `waterexpenses`, so the column, the index and the check
--    constraint go there. 269's column on `expense` is untouched by this file
--    and the poultry resolvers are not reused -- water's sourcetypes and its
--    category vocabulary are its own.
--
-- 2. THE CATEGORY IS A FOREIGN KEY, NOT FREE TEXT. waterexpenses points at
--    waterexpensecategories, so the "category" these resolvers match on is the
--    category NAME, resolved by the join fnwaterexpenserows already does. That
--    makes the keyword fallback more reliable here than on the poultry side,
--    where the category is whatever somebody typed -- but it is still a
--    fallback, for the same reason.
--
-- 3. THE WRITERS ARE NOT REWRITTEN. 269 added a p_financialcosttype parameter to
--    spexpense_insert / _update. The water equivalents write fifteen columns
--    through a body this repo does not contain -- 240 section 6 says so in
--    terms, and chose a separate spwaterexpense_setpayment rather than risk
--    them. This file follows that established precedent exactly and adds
--    spwaterexpense_setcosttype instead. Same outcome, none of the risk.
--
-- STRUCTURE FIRST, KEYWORDS LAST
-- ==============================
-- The order of authority is:
--
--   1. waterexpenses.financialcosttype  stored, explicit, set by the writer
--   2. waterexpenses.sourcetype         which workflow produced the row
--   3. the ITEM's category              via 274's categorygroup resolver, for
--                                       rows that came from a purchase
--   4. the category name                keyword, LAST, and only then
--
-- Step 4 is not removed: a company has years of categories behind it and
-- deleting the fallback would silently move that history into Other. What
-- changes is that it is now the last resort rather than the only rule.
--
-- WHAT THIS FILE DOES NOT DO
-- ==========================
-- It does not backfill. Every existing row keeps financialcosttype NULL and is
-- classified by the resolver at read time, which reproduces today's answer for
-- everything except the raw-material purchases the resolver can now place
-- properly. Nothing is rewritten, so no company's history changes shape under
-- it.
--
-- It also does not change the P&L report. spwaterreport_periodpnl is untouched
-- here; 285 rewrites it. This file only makes the classification available.
--
-- Order: after 281.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The column. NULL means "not stated -- work it out", which is every row
--    written before today.
-- -----------------------------------------------------------------------------
ALTER TABLE waterexpenses ADD COLUMN IF NOT EXISTS financialcosttype varchar(30);

COMMENT ON COLUMN waterexpenses.financialcosttype IS
    'OperatingExpense | InventoryPurchase | CapitalAsset | NonCashExpense | '
    'FinancingExpense. NULL means legacy: fnwaterexpense_costtype derives it.';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_waterexpenses_financialcosttype') THEN
        ALTER TABLE waterexpenses ADD CONSTRAINT ck_waterexpenses_financialcosttype
            CHECK (financialcosttype IS NULL OR financialcosttype IN (
                'OperatingExpense', 'InventoryPurchase', 'CapitalAsset',
                'NonCashExpense', 'FinancingExpense'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_waterexpenses_costtype
    ON waterexpenses (farmid, financialcosttype);

-- -----------------------------------------------------------------------------
-- 2. What kind of cost is this?
--
-- Stored wins. Below it the SOURCE decides, because a workflow knows what it
-- wrote far better than any word in a description does. Nothing falls through
-- to a keyword here: the default is OperatingExpense, which is what an ordinary
-- bill is and what every legacy row has always been treated as.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwaterexpense_costtype(
    p_stored        text,
    p_sourcetype    text,
    p_category      text,
    p_paymentmethod text
) RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE
        WHEN COALESCE(p_stored, '') <> '' THEN p_stored
        -- Depreciation: an expense that never moves money (284).
        WHEN p_sourcetype = 'AssetDepreciation' THEN 'NonCashExpense'
        -- The cost of borrowing. Principal never reaches this table; 259 writes
        -- only the interest and fee legs, and their reversals.
        WHEN p_sourcetype IN ('LoanPayment', 'LoanPaymentInterest', 'LoanPaymentFee',
                              'LoanPaymentInterestReversal', 'LoanPaymentFeeReversal')
             THEN 'FinancingExpense'
        -- A capital acquisition rides the expense rail for its cash and its
        -- payable, and is kept out of profit by this value (283).
        WHEN p_sourcetype IN ('CapitalAsset', 'CapitalAssetCost') THEN 'CapitalAsset'
        -- Everything else, including Phase 2's consumption recognition. That one
        -- is non-cash but it is not NonCashExpense: it is a real operating cost
        -- of this period that simply happened to be paid for earlier. Calling it
        -- NonCashExpense would file packaging under Other Costs beside
        -- depreciation.
        ELSE 'OperatingExpense'
    END;
$function$;

COMMENT ON FUNCTION public.fnwaterexpense_costtype(text, text, text, text) IS
    'What KIND of financial cost a water expense row is. Stored value wins; '
    'otherwise the source workflow decides. Never keyword-based.';

-- -----------------------------------------------------------------------------
-- 3. Which P&L line?
--
-- p_itemcategory is the RAW MATERIAL ITEM's category when the row came from a
-- purchase or a consumption -- the caller resolves it by joining, because a
-- scalar function cannot. When it is supplied, 274's
-- fnwatercostrecognition_categorygroup decides between Packaging and Treatment,
-- so this file and the cost-recognition settings can never disagree about what
-- counts as packaging.
--
-- 'Excluded' is returned for anything that must not touch profit at all.
--
-- ONE WATER-SPECIFIC JUDGEMENT, RECORDED SO IT CAN BE ARGUED WITH
-- ---------------------------------------------------------------
-- ELECTRICITY IS AN OPERATING EXPENSE, NOT A DIRECT COST, unless the category
-- says it is production power. A water plant's pumps and chillers are a real
-- per-unit input and there is an argument for putting all of it above Gross
-- Profit -- but a single "Electricity" category almost always covers the office
-- and the plant together, and splitting it on a guess would move money between
-- Gross Profit and Operating Profit with nothing in the row to justify it. A
-- company that wants it counted as direct names the category so: "Production
-- Power" and "Plant Electricity" are matched below. This is the same reasoning
-- 269 applied to "Direct Labour" on the poultry side.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwaterexpense_plline(
    p_costtype     text,
    p_sourcetype   text,
    p_category     text,
    p_itemcategory text DEFAULT NULL
) RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE
        -- ---- never profit ---------------------------------------------------
        WHEN p_costtype IN ('CapitalAsset', 'InventoryPurchase') THEN 'Excluded'

        -- ---- the cost of borrowing -----------------------------------------
        WHEN p_costtype = 'FinancingExpense' THEN
            CASE WHEN p_category ILIKE '%interest%' THEN 'LoanInterest'
                 WHEN p_category ILIKE '%fee%' OR p_category ILIKE '%charge%' THEN 'LoanFees'
                 ELSE 'OtherFinancing' END

        -- ---- depreciation ---------------------------------------------------
        WHEN p_sourcetype = 'AssetDepreciation' OR p_category ILIKE '%deprec%' THEN 'Depreciation'

        -- ---- the item decides, when there is one ----------------------------
        -- 274's grouping, so "is this packaging?" has one answer in the system.
        WHEN COALESCE(p_itemcategory, '') <> '' THEN
            CASE fnwatercostrecognition_categorygroup(p_itemcategory)
                 WHEN 'Packaging' THEN 'Packaging'
                 WHEN 'Treatment' THEN 'Treatment'
                 ELSE 'ProductionSupplies' END

        -- ---- the source decides ---------------------------------------------
        WHEN p_sourcetype = 'WaterPackagingConsumption' THEN 'Packaging'
        WHEN p_sourcetype = 'WaterTreatmentConsumption' THEN 'Treatment'
        WHEN p_sourcetype = 'Payroll' THEN 'Payroll'
        WHEN p_sourcetype IN ('WaterDriverDelivery', 'DriverReturn', 'DeliveryReturn') THEN 'Transport'

        -- ---- direct production costs, by category ---------------------------
        WHEN p_category ILIKE '%sachet film%' OR p_category ILIKE '%packag%'
          OR p_category ILIKE '%preform%'     OR p_category ILIKE '%bottle%'
          OR p_category ILIKE '%shrink%'      OR p_category ILIKE '%label%'
          OR p_category ILIKE '%outer bag%'   OR p_category ILIKE '%cap%'
             THEN 'Packaging'
        WHEN p_category ILIKE '%chemical%'  OR p_category ILIKE '%chlorin%'
          OR p_category ILIKE '%treatment%' OR p_category ILIKE '%filter%'
          OR p_category ILIKE '%uv %'       OR p_category ILIKE '%lab test%'
          OR p_category ILIKE '%water quality%'
             THEN 'Treatment'
        -- See the header: production power must be NAMED to count as direct.
        WHEN p_category ILIKE '%production power%' OR p_category ILIKE '%plant electric%'
          OR p_category ILIKE '%production electric%'
             THEN 'ProductionUtilities'
        -- "Direct labour" has to be named to be counted as direct. A company
        -- that types "Labor" gets Payroll below, because nothing in the row says
        -- whether that wage belongs to the plant or to the office, and guessing
        -- would move real money between Gross Profit and Operating Profit.
        WHEN p_category ILIKE '%direct labo%' OR p_category ILIKE '%plant labo%'
          OR p_category ILIKE '%production labo%' THEN 'DirectLabour'
        WHEN p_category ILIKE '%production suppl%' OR p_category ILIKE '%raw material%'
          OR p_category ILIKE '%inventory purchase%' THEN 'ProductionSupplies'

        -- ---- operating expenses, by category --------------------------------
        WHEN p_category ILIKE '%payroll%' OR p_category ILIKE '%salary%'
          OR p_category ILIKE '%wage%'    OR p_category ILIKE '%labo%'
          OR p_category ILIKE '%staff%' THEN 'Payroll'
        WHEN p_category ILIKE '%utilit%'  OR p_category ILIKE '%electric%'
          OR p_category ILIKE '%power%'   OR p_category ILIKE '%water bill%' THEN 'Utilities'
        WHEN p_category ILIKE '%transport%' OR p_category ILIKE '%deliver%'
          OR p_category ILIKE '%fuel%'      OR p_category ILIKE '%vehicle%'
          OR p_category ILIKE '%travel%' THEN 'Transport'
        WHEN p_category ILIKE '%repair%' OR p_category ILIKE '%maintenance%'
          OR p_category ILIKE '%servicing%' THEN 'RepairsMaintenance'
        WHEN p_category ILIKE '%rent%' OR p_category ILIKE '%lease%' THEN 'Rent'
        WHEN p_category ILIKE '%market%' OR p_category ILIKE '%advert%'
          OR p_category ILIKE '%promot%' THEN 'Marketing'
        WHEN p_category ILIKE '%insur%' THEN 'Insurance'
        WHEN p_category ILIKE '%securit%' THEN 'Security'
        WHEN p_category ILIKE '%profession%' OR p_category ILIKE '%legal%'
          OR p_category ILIKE '%account%' OR p_category ILIKE '%consult%'
          OR p_category ILIKE '%audit%' THEN 'ProfessionalServices'
        WHEN p_category ILIKE '%licen%' OR p_category ILIKE '%permit%'
          OR p_category ILIKE '%fda%'   OR p_category ILIKE '%regulat%'
             THEN 'LicencesPermits'
        WHEN p_category ILIKE '%communic%' OR p_category ILIKE '%internet%'
          OR p_category ILIKE '%phone%' OR p_category ILIKE '%airtime%' THEN 'Communications'
        WHEN p_category ILIKE '%admin%' OR p_category ILIKE '%office%'
          OR p_category ILIKE '%stationer%' OR p_category ILIKE '%bank charge%' THEN 'Administration'

        ELSE 'OtherOperating'
    END;
$function$;

COMMENT ON FUNCTION public.fnwaterexpense_plline(text, text, text, text) IS
    'The Profit & Loss line a water expense row belongs on. Source and item '
    'category decide before any keyword does; keywords remain for hand-named '
    'categories only.';

-- -----------------------------------------------------------------------------
-- 4. Which band of the report is that line in?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwaterexpense_plsection(p_line text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_line IN ('Packaging', 'Treatment', 'DirectLabour', 'ProductionSupplies',
                        'ProductionUtilities', 'OtherDirect') THEN 'DirectCost'
        WHEN p_line IN ('Depreciation', 'LoanInterest', 'LoanFees', 'OtherFinancing')
             THEN 'OtherCost'
        WHEN p_line = 'Excluded' THEN 'Excluded'
        ELSE 'OperatingExpense'
    END;
$function$;

COMMENT ON FUNCTION public.fnwaterexpense_plsection(text) IS
    'DirectCost (above Gross Profit) | OperatingExpense (above Operating Profit) '
    '| OtherCost (below it) | Excluded (never in profit).';

-- -----------------------------------------------------------------------------
-- 5. Human wording, once, so every screen says the same thing.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwaterexpense_pllinelabel(p_line text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE p_line
        WHEN 'Packaging'           THEN 'Packaging Materials'
        WHEN 'Treatment'           THEN 'Water Treatment & Chemicals'
        WHEN 'DirectLabour'        THEN 'Direct Labour'
        WHEN 'ProductionSupplies'  THEN 'Production Supplies'
        WHEN 'ProductionUtilities' THEN 'Production Power'
        WHEN 'OtherDirect'         THEN 'Other Direct Costs'
        WHEN 'Payroll'             THEN 'Payroll & Administrative Labour'
        WHEN 'Utilities'           THEN 'Utilities'
        WHEN 'Transport'           THEN 'Transport & Distribution'
        WHEN 'RepairsMaintenance'  THEN 'Repairs & Maintenance'
        WHEN 'Rent'                THEN 'Rent'
        WHEN 'Marketing'           THEN 'Marketing'
        WHEN 'Insurance'           THEN 'Insurance'
        WHEN 'Security'            THEN 'Security'
        WHEN 'ProfessionalServices' THEN 'Professional Services'
        WHEN 'LicencesPermits'     THEN 'Licences & Permits'
        WHEN 'Communications'      THEN 'Communications & Internet'
        WHEN 'Administration'      THEN 'Office & Administration'
        WHEN 'OtherOperating'      THEN 'Other Operating Expenses'
        WHEN 'Depreciation'        THEN 'Depreciation'
        WHEN 'LoanInterest'        THEN 'Loan Interest'
        WHEN 'LoanFees'            THEN 'Loan Fees & Charges'
        WHEN 'OtherFinancing'      THEN 'Other Financing Costs'
        WHEN 'Excluded'            THEN 'Excluded from profit'
        ELSE COALESCE(p_line, 'Unclassified')
    END;
$function$;

CREATE OR REPLACE FUNCTION public.fnwaterexpense_sourcelabel(p_sourcetype text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE COALESCE(p_sourcetype, '')
        WHEN ''                             THEN 'Manual entry'
        WHEN 'RawMaterialPurchase'          THEN 'Raw material purchase'
        WHEN 'WaterSupplierPayment'         THEN 'Supplier payment'
        WHEN 'WaterPackagingConsumption'    THEN 'Packaging usage'
        WHEN 'WaterTreatmentConsumption'    THEN 'Treatment usage'
        WHEN 'WaterInternalUsage'           THEN 'Internal use'
        WHEN 'Payroll'                      THEN 'Payroll'
        WHEN 'LoanPayment'                  THEN 'Loan repayment'
        WHEN 'LoanPaymentInterest'          THEN 'Loan interest'
        WHEN 'LoanPaymentFee'               THEN 'Loan fees'
        WHEN 'LoanPaymentInterestReversal'  THEN 'Loan interest reversal'
        WHEN 'LoanPaymentFeeReversal'       THEN 'Loan fee reversal'
        WHEN 'AssetDepreciation'            THEN 'Depreciation'
        WHEN 'CapitalAsset'                 THEN 'Capital asset purchase'
        WHEN 'CapitalAssetCost'             THEN 'Capital asset cost'
        WHEN 'WaterDriverDelivery'          THEN 'Delivery'
        WHEN 'DriverReturn'                 THEN 'Driver return'
        ELSE p_sourcetype
    END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Revenue lines.
--
-- watersaleitems.productname is free text with no product master behind it, so
-- this one IS keyword-based and honestly so. It is pulled into a function so the
-- report and its drilldown cannot drift apart -- a drilldown that disagreed with
-- the figure above it is worse than no drilldown.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwatersale_revenueline(p_product text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_product ILIKE '%sachet%' OR p_product ILIKE '%pure water%'
          OR p_product ILIKE '%bag of water%' THEN 'SachetSales'
        -- Dispenser first: a "19L bottle" is a dispenser sale, and the bottle
        -- test below would otherwise swallow it.
        WHEN p_product ILIKE '%dispenser%' OR p_product ILIKE '%18l%'
          OR p_product ILIKE '%19l%'       OR p_product ILIKE '%20l%'
          OR p_product ILIKE '%gallon%' THEN 'DispenserSales'
        WHEN p_product ILIKE '%bottle%' OR p_product ILIKE '%500ml%'
          OR p_product ILIKE '%750ml%'  OR p_product ILIKE '%1.5l%'
          OR p_product ILIKE '%pet%' THEN 'BottleSales'
        ELSE 'OtherRevenue'
    END;
$function$;

COMMENT ON FUNCTION public.fnwatersale_revenueline(text) IS
    'Sachet / Bottle / Dispenser / Other, from the sale product name. Keyword by '
    'necessity: productname is free text with no product master behind it.';

CREATE OR REPLACE FUNCTION public.fnwatersale_revenuelabel(p_line text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE p_line
        WHEN 'SachetSales'    THEN 'Sachet Water Sales'
        WHEN 'BottleSales'    THEN 'Bottled Water Sales'
        WHEN 'DispenserSales' THEN 'Dispenser / Bulk Sales'
        ELSE 'Other Operating Revenue'
    END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. The item category behind an expense row, when there is one.
--
-- This is the join a scalar resolver cannot do. A raw-material purchase points
-- straight at its item, which is where the truth about "is this packaging?"
-- lives.
--
-- Internal use is deliberately NOT resolved here: its lines reference PRODUCTS
-- (sachets, bottles), not raw-material items, so there is no item category to
-- read. Those rows fall through to the category name, which is what they have
-- always been classified by.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwaterexpense_itemcategory(
    p_sourcetype text, p_sourceid integer
) RETURNS text
LANGUAGE sql STABLE
AS $function$
    SELECT CASE
        WHEN p_sourcetype = 'RawMaterialPurchase' THEN (
            SELECT i.category::text
            FROM   waterrawmaterialpurchases p
            JOIN   waterrawmaterialitems i ON i.waterrawmaterialitemid = p.waterrawmaterialitemid
            WHERE  p.waterrawmaterialpurchaseid = p_sourceid)
        ELSE NULL
    END;
$function$;

COMMENT ON FUNCTION public.fnwaterexpense_itemcategory(text, integer) IS
    'The raw-material item category behind a water expense row, or NULL. Lets '
    'fnwaterexpense_plline use 274 grouping instead of a keyword.';

-- -----------------------------------------------------------------------------
-- 8. The expense read gains its classification.
--
-- waterexpenserow is a composite type, so the columns are appended to it and
-- fnwaterexpenserows is reproduced from 240's definition with the new
-- expressions on the end. Existing ordinals do not move, which is what keeps
-- every current caller of spwaterexpense_getall / _getbyid binding correctly.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_attribute
                   WHERE attrelid = 'waterexpenserow'::regclass
                     AND attname = 'financialcosttype' AND NOT attisdropped) THEN
        ALTER TYPE waterexpenserow ADD ATTRIBUTE financialcosttype text CASCADE;
        ALTER TYPE waterexpenserow ADD ATTRIBUTE costtypeisstored boolean CASCADE;
        ALTER TYPE waterexpenserow ADD ATTRIBUTE plline text CASCADE;
        ALTER TYPE waterexpenserow ADD ATTRIBUTE pllinelabel text CASCADE;
        ALTER TYPE waterexpenserow ADD ATTRIBUTE plsection text CASCADE;
        ALTER TYPE waterexpenserow ADD ATTRIBUTE sourcelabel text CASCADE;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fnwaterexpenserows(p_farmid text)
RETURNS SETOF public.waterexpenserow
LANGUAGE sql
STABLE
AS $function$
    SELECT e.waterexpenseid, e.farmid::text, e.expensedate,
           e.waterexpensecategoryid, c.name::text,
           e.description::text, e.amount::numeric(14,2), e.paidto::text, e.paymentmethod::text,
           e.watercashaccountid, ca.accountname::text,
           e.receipturl::text,
           e.linkedwatervehicleid, e.linkedwatermachineid, e.linkedwaterproductionbatchid,
           e.supplierid, s.suppliername::text,
           COALESCE(e.amountpaid,
                    CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                         THEN 0 ELSE e.amount END)::numeric(14,2),
           GREATEST(COALESCE(e.amount, 0)
                    - COALESCE(e.amountpaid,
                               CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                                    THEN 0 ELSE e.amount END), 0)::numeric(14,2),
           e.paymentstatus::text,
           e.duedate,
           e.sourcetype::text, e.sourceid,
           e.status::text, e.notes::text,
           e.createdby::text, e.approvedby::text, e.approvedat,
           e.createdat, e.updatedat,
           -- 282. What kind of cost, which P&L line, which band, and where it
           -- came from -- resolved server-side so no screen has to re-derive it.
           ct.costtype,
           (COALESCE(e.financialcosttype, '') <> ''),
           l.line,
           fnwaterexpense_pllinelabel(l.line),
           fnwaterexpense_plsection(l.line),
           fnwaterexpense_sourcelabel(e.sourcetype::text)
    FROM   waterexpenses e
    INNER  JOIN waterexpensecategories c ON c.waterexpensecategoryid = e.waterexpensecategoryid
    LEFT   JOIN watercashaccounts ca     ON ca.watercashaccountid    = e.watercashaccountid
    LEFT   JOIN watersuppliers s         ON s.watersupplierid        = e.supplierid
    CROSS  JOIN LATERAL (SELECT fnwaterexpense_costtype(
                                    e.financialcosttype::text, e.sourcetype::text,
                                    c.name::text, e.paymentmethod::text) AS costtype) ct
    CROSS  JOIN LATERAL (SELECT fnwaterexpense_plline(
                                    ct.costtype, e.sourcetype::text, c.name::text,
                                    fnwaterexpense_itemcategory(e.sourcetype::text, e.sourceid)) AS line) l
    WHERE  e.farmid = p_farmid
      AND  COALESCE(e.isdeleted, FALSE) = FALSE;
$function$;

-- -----------------------------------------------------------------------------
-- 9. Writers can now state the classification.
--
-- A SEPARATE setter rather than a parameter on spwaterexpense_insert, following
-- 240 section 6: those bodies are not in this repo and rewriting them blind to
-- add one field would risk the receipt, approval and asset-link behaviour for no
-- gain. The asset workflow in 283 calls this straight after creating its bill.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterexpense_setcosttype(
    p_farmid           text,
    p_waterexpenseid   integer,
    p_financialcosttype text
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_source text;
BEGIN
    IF COALESCE(p_financialcosttype, '') <> ''
       AND p_financialcosttype NOT IN ('OperatingExpense', 'InventoryPurchase',
                                       'CapitalAsset', 'NonCashExpense', 'FinancingExpense') THEN
        RAISE EXCEPTION 'Unknown financial cost type: "%".', p_financialcosttype;
    END IF;

    SELECT e.sourcetype::text INTO v_source
    FROM   waterexpenses e
    WHERE  e.waterexpenseid = p_waterexpenseid AND e.farmid = p_farmid
      AND  COALESCE(e.isdeleted, FALSE) = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Expense not found for this company.';
    END IF;

    -- 282. A capital acquisition is recorded through the asset workflow, which
    -- links the row to its asset. Letting a plain bill be stamped CapitalAsset
    -- would create a cost that is excluded from profit and has no asset to
    -- depreciate -- money that vanishes from both sides of the report.
    IF p_financialcosttype = 'CapitalAsset'
       AND COALESCE(v_source, '') NOT IN ('CapitalAsset', 'CapitalAssetCost') THEN
        RAISE EXCEPTION 'Record a capital asset on the Assets page so it can be depreciated.';
    END IF;

    UPDATE waterexpenses
    SET    financialcosttype = NULLIF(p_financialcosttype, ''),
           updatedat         = (now() at time zone 'utc')
    WHERE  waterexpenseid = p_waterexpenseid AND farmid = p_farmid;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'nothing was backfilled' AS check,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'STAMPED ' || COUNT(*) END AS result
FROM   waterexpenses
WHERE  financialcosttype IS NOT NULL

UNION ALL
-- Every legacy row still reads as an ordinary operating expense, which is how
-- it has always been treated.
SELECT 'legacy rows read OperatingExpense',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'MOVED ' || COUNT(*) END
FROM   waterexpenses e
WHERE  e.financialcosttype IS NULL
  AND  COALESCE(e.sourcetype, '') NOT IN ('AssetDepreciation', 'LoanPayment',
       'LoanPaymentInterest', 'LoanPaymentFee', 'LoanPaymentInterestReversal',
       'LoanPaymentFeeReversal', 'CapitalAsset', 'CapitalAssetCost')
  AND  fnwaterexpense_costtype(e.financialcosttype::text, e.sourcetype::text, NULL, NULL)
       <> 'OperatingExpense'

UNION ALL
-- The six new attributes are on the composite type. Deliberately NOT a row
-- count against waterexpenses: fnwaterexpenserows has always INNER JOINed
-- waterexpensecategories, so a row whose category was deleted was already
-- absent before this file and comparing the two would raise a false alarm
-- about a gap 240 left, not one 282 opened.
SELECT 'row type carries the classification',
       CASE WHEN COUNT(*) = 6 THEN 'OK' ELSE 'FOUND ' || COUNT(*) || ' of 6' END
FROM   pg_attribute
WHERE  attrelid = 'waterexpenserow'::regclass
  AND  NOT attisdropped
  AND  attname IN ('financialcosttype', 'costtypeisstored', 'plline',
                   'pllinelabel', 'plsection', 'sourcelabel')

UNION ALL
-- And the read still runs for every water company. This is the check that the
-- CROSS JOIN LATERALs added above cannot throw on real data.
SELECT 'expense read runs for every company',
       CASE WHEN COUNT(*) >= 0 THEN 'OK' ELSE 'FAILED' END
FROM   farms f
CROSS  JOIN LATERAL fnwaterexpenserows(f.farmid) r
WHERE  f.type = 'Water';

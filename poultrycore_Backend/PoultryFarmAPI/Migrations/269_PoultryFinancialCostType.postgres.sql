-- =============================================================================
-- 269_PoultryFinancialCostType.postgres.sql
--
-- Purpose
-- -------
-- Phase 3, part 1: say what KIND of financial cost a row is, so the Profit &
-- Loss report can stop guessing from words in a description.
--
-- TWO QUESTIONS, TWO ANSWERS
-- ==========================
-- Phase 1 asked WHEN an inventory cost reaches Profit & Loss and answered with
-- costrecognitionmethod. This file asks WHAT KIND of cost it is and answers with
-- financialcosttype. They are not alternatives and neither replaces the other:
--
--   costrecognitionmethod   EXPENSE_WHEN_PURCHASED | EXPENSE_WHEN_CONSUMED
--   financialcosttype       OperatingExpense | InventoryPurchase | CapitalAsset
--                           NonCashExpense   | FinancingExpense
--
-- A bag of maize can be EXPENSE_WHEN_CONSUMED and an InventoryPurchase at the
-- same time; a poultry house is a CapitalAsset and has no recognition method at
-- all.
--
-- WHY NOT ONE ENUM FOR THE P&L TOO
-- ================================
-- Because the two axes genuinely cross. Depreciation and feed consumption are
-- both non-cash, and they belong in different bands of the report: depreciation
-- under Other Costs, feed under Direct Production Costs. A single column would
-- have to lie about one of them. So there are two resolvers:
--
--   fnpoultryexpense_costtype   what kind of cost      (the 5 values above)
--   fnpoultryexpense_plline     which P&L line it is   (Feed, Payroll, ...)
--
-- and one derived from the line:
--
--   fnpoultryexpense_plsection  DirectCost | OperatingExpense | OtherCost |
--                               Excluded
--
-- STRUCTURE FIRST, KEYWORDS LAST
-- ==============================
-- Today's report reads `category ILIKE '%feed%'` and drops everything else into
-- "Other". That is why 72 raw-material purchases -- most of them feed -- are
-- currently reported as Other rather than as Feed Cost.
--
-- The order of authority here is:
--
--   1. expense.financialcosttype        stored, explicit, set by the writer
--   2. expense.sourcetype               which workflow produced the row
--   3. the ITEM's category              via Phase 1's categorygroup resolver,
--                                       for rows that came from a purchase
--   4. the category text                keyword, LAST, and only then
--
-- Step 4 is not removed: a farm has three years of hand-typed categories and
-- deleting the fallback would silently move that history into Other. What
-- changes is that it is now the last resort rather than the only rule.
--
-- WHAT THIS FILE DOES NOT DO
-- ==========================
-- It does not backfill. Every existing row keeps financialcosttype NULL and is
-- classified by the resolver at read time, which reproduces today's answer for
-- everything except the raw-material purchases the resolver can now place
-- properly. Nothing is rewritten, so no farm's history changes shape under it.
--
-- It also does not change the P&L report. sppoultryreport_profitloss is
-- untouched here; 272 rewrites it. This file only makes the classification
-- available.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The column. NULL means "not stated -- work it out", which is every row
--    written before today.
-- -----------------------------------------------------------------------------
ALTER TABLE expense ADD COLUMN IF NOT EXISTS financialcosttype varchar(30);

COMMENT ON COLUMN expense.financialcosttype IS
    'OperatingExpense | InventoryPurchase | CapitalAsset | NonCashExpense | '
    'FinancingExpense. NULL means legacy: fnpoultryexpense_costtype derives it.';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_expense_financialcosttype') THEN
        ALTER TABLE expense ADD CONSTRAINT ck_expense_financialcosttype
            CHECK (financialcosttype IS NULL OR financialcosttype IN (
                'OperatingExpense', 'InventoryPurchase', 'CapitalAsset',
                'NonCashExpense', 'FinancingExpense'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_expense_costtype ON expense (farmid, financialcosttype);

-- -----------------------------------------------------------------------------
-- 2. What kind of cost is this?
--
-- Stored wins. Below it the SOURCE decides, because a workflow knows what it
-- wrote far better than any word in a description does. Nothing falls through
-- to a keyword here: the default is OperatingExpense, which is what an ordinary
-- bill is and what every legacy row has always been treated as.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryexpense_costtype(
    p_stored        text,
    p_sourcetype    text,
    p_category      text,
    p_paymentmethod text
) RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE
        WHEN COALESCE(p_stored, '') <> '' THEN p_stored
        -- Depreciation: an expense that never moves money (271).
        WHEN p_sourcetype = 'AssetDepreciation' THEN 'NonCashExpense'
        -- The cost of borrowing. Principal never reaches this table.
        WHEN p_sourcetype = 'LoanPayment' THEN 'FinancingExpense'
        -- A capital acquisition rides the expense rail for its cash and its
        -- payable, and is kept out of profit by this value (270).
        WHEN p_sourcetype IN ('CapitalAsset', 'CapitalAssetCost') THEN 'CapitalAsset'
        -- Everything else, including Phase 2's consumption recognition. That one
        -- is non-cash but it is not NonCashExpense: it is a real operating cost
        -- of this period that simply happened to be paid for earlier. Calling it
        -- NonCashExpense would file feed under Other Costs beside depreciation.
        ELSE 'OperatingExpense'
    END;
$function$;

COMMENT ON FUNCTION public.fnpoultryexpense_costtype(text, text, text, text) IS
    'What KIND of financial cost an expense row is. Stored value wins; otherwise '
    'the source workflow decides. Never keyword-based.';

-- -----------------------------------------------------------------------------
-- 3. Which P&L line?
--
-- p_itemcategory is the RAW MATERIAL ITEM's category when the row came from a
-- purchase, a consumption or an internal use -- the caller resolves it by
-- joining, because a scalar function cannot. When it is supplied, Phase 1's
-- fnpoultrycostrecognition_categorygroup decides between Feed and Medication,
-- so this file and the cost-recognition settings can never disagree about what
-- counts as feed.
--
-- 'Excluded' is returned for anything that must not touch profit at all.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryexpense_plline(
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
        -- Phase 1's grouping, so "is this feed?" has one answer in the system.
        WHEN COALESCE(p_itemcategory, '') <> '' THEN
            CASE fnpoultrycostrecognition_categorygroup(p_itemcategory)
                 WHEN 'Feed' THEN 'Feed'
                 WHEN 'Medication' THEN 'Medication'
                 ELSE 'ProductionSupplies' END

        -- ---- the source decides ---------------------------------------------
        WHEN p_sourcetype = 'PoultryFeedConsumption' THEN 'Feed'
        WHEN p_sourcetype = 'PoultryMedicationConsumption' THEN 'Medication'
        WHEN p_sourcetype = 'MainFlockBatch' THEN 'FlockCost'
        WHEN p_sourcetype = 'Payroll' THEN 'Payroll'
        WHEN p_sourcetype IN ('PoultryDriverDelivery', 'DriverReturn', 'DeliveryReturn') THEN 'Transport'

        -- ---- direct production costs, by category ---------------------------
        WHEN p_category ILIKE '%feed%' THEN 'Feed'
        WHEN p_category ILIKE '%medic%' OR p_category ILIKE '%vaccin%'
          OR p_category ILIKE '%drug%'  OR p_category ILIKE '%vet%'
          OR p_category ILIKE '%health%' THEN 'Medication'
        WHEN p_category ILIKE '%flock%' OR p_category ILIKE '%bird purchase%'
          OR p_category ILIKE '%day old%' OR p_category ILIKE '%day-old%' THEN 'FlockCost'
        -- "Direct labour" has to be named to be counted as direct. A farm that
        -- types "Labor" gets Payroll below, because nothing in the row says
        -- whether that wage belongs to the birds or to the office, and guessing
        -- would move real money between Gross Profit and Operating Profit.
        WHEN p_category ILIKE '%direct labo%' OR p_category ILIKE '%farm labo%'
          OR p_category ILIKE '%production labo%' THEN 'DirectLabour'
        WHEN p_category ILIKE '%production suppl%' OR p_category ILIKE '%litter%'
          OR p_category ILIKE '%sawdust%' OR p_category ILIKE '%shaving%'
          OR p_category ILIKE '%crate%' OR p_category ILIKE '%packag%' THEN 'ProductionSupplies'

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
        WHEN p_category ILIKE '%communic%' OR p_category ILIKE '%internet%'
          OR p_category ILIKE '%phone%' OR p_category ILIKE '%airtime%' THEN 'Communications'
        WHEN p_category ILIKE '%admin%' OR p_category ILIKE '%office%'
          OR p_category ILIKE '%stationer%' OR p_category ILIKE '%bank charge%' THEN 'Administration'

        ELSE 'OtherOperating'
    END;
$function$;

COMMENT ON FUNCTION public.fnpoultryexpense_plline(text, text, text, text) IS
    'The Profit & Loss line an expense row belongs on. Source and item category '
    'decide before any keyword does; keywords remain for hand-typed legacy '
    'categories only.';

-- -----------------------------------------------------------------------------
-- 4. Which band of the report is that line in?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryexpense_plsection(p_line text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_line IN ('Feed', 'Medication', 'DirectLabour', 'ProductionSupplies',
                        'FlockCost', 'OtherDirect') THEN 'DirectCost'
        WHEN p_line IN ('Depreciation', 'LoanInterest', 'LoanFees', 'OtherFinancing')
             THEN 'OtherCost'
        WHEN p_line = 'Excluded' THEN 'Excluded'
        ELSE 'OperatingExpense'
    END;
$function$;

COMMENT ON FUNCTION public.fnpoultryexpense_plsection(text) IS
    'DirectCost (above Gross Profit) | OperatingExpense (above Operating Profit) '
    '| OtherCost (below it) | Excluded (never in profit).';

-- -----------------------------------------------------------------------------
-- 5. Human wording, once, so every screen says the same thing.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryexpense_pllinelabel(p_line text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE p_line
        WHEN 'Feed'                 THEN 'Feed Cost'
        WHEN 'Medication'           THEN 'Medication & Veterinary'
        WHEN 'DirectLabour'         THEN 'Direct Labour'
        WHEN 'ProductionSupplies'   THEN 'Production Supplies'
        WHEN 'FlockCost'            THEN 'Flock / Bird Purchases'
        WHEN 'OtherDirect'          THEN 'Other Direct Costs'
        WHEN 'Payroll'              THEN 'Payroll & Administrative Labour'
        WHEN 'Utilities'            THEN 'Utilities'
        WHEN 'Transport'            THEN 'Transport & Delivery'
        WHEN 'RepairsMaintenance'   THEN 'Repairs & Maintenance'
        WHEN 'Rent'                 THEN 'Rent'
        WHEN 'Marketing'            THEN 'Marketing'
        WHEN 'Insurance'            THEN 'Insurance'
        WHEN 'Security'             THEN 'Security'
        WHEN 'ProfessionalServices' THEN 'Professional Services'
        WHEN 'Communications'       THEN 'Communications & Internet'
        WHEN 'Administration'       THEN 'Office & Administration'
        WHEN 'OtherOperating'       THEN 'Other Operating Expenses'
        WHEN 'Depreciation'         THEN 'Depreciation'
        WHEN 'LoanInterest'         THEN 'Loan Interest'
        WHEN 'LoanFees'             THEN 'Loan Fees & Charges'
        WHEN 'OtherFinancing'       THEN 'Other Financing Costs'
        WHEN 'Excluded'             THEN 'Excluded from profit'
        ELSE COALESCE(p_line, 'Unclassified')
    END;
$function$;

CREATE OR REPLACE FUNCTION public.fnpoultryexpense_sourcelabel(p_sourcetype text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE COALESCE(p_sourcetype, '')
        WHEN ''                             THEN 'Manual entry'
        WHEN 'PoultryRawMaterialPurchase'   THEN 'Raw material purchase'
        WHEN 'PoultryFeedConsumption'       THEN 'Feed usage'
        WHEN 'PoultryMedicationConsumption' THEN 'Medication usage'
        WHEN 'PoultryInternalUsage'         THEN 'Internal use'
        WHEN 'MainFlockBatch'               THEN 'Flock purchase'
        WHEN 'Payroll'                      THEN 'Payroll'
        WHEN 'LoanPayment'                  THEN 'Loan repayment'
        WHEN 'AssetDepreciation'            THEN 'Depreciation'
        WHEN 'CapitalAsset'                 THEN 'Capital asset purchase'
        WHEN 'CapitalAssetCost'             THEN 'Capital asset cost'
        WHEN 'PoultryDriverDelivery'        THEN 'Delivery'
        WHEN 'DriverReturn'                 THEN 'Driver return'
        ELSE p_sourcetype
    END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Revenue lines.
--
-- sale.product is free text and there is no product master behind it, so this
-- one IS keyword-based and honestly so. It is the same matching the current
-- report does, pulled into a function so the report and its drilldown cannot
-- drift apart -- a drilldown that disagreed with the figure above it is worse
-- than no drilldown.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrysale_revenueline(p_product text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_product ILIKE '%egg%' THEN 'EggSales'
        WHEN p_product ILIKE '%manure%' OR p_product ILIKE '%droppings%'
          OR p_product ILIKE '%compost%' THEN 'ManureSales'
        WHEN p_product ILIKE '%feed%' OR p_product ILIKE '%mash%'
          OR p_product ILIKE '%pellet%' THEN 'FeedSales'
        WHEN p_product ILIKE '%bird%'     OR p_product ILIKE '%layer%'
          OR p_product ILIKE '%broiler%'  OR p_product ILIKE '%cockerel%'
          OR p_product ILIKE '%chick%'    OR p_product ILIKE '%cock%'
          OR p_product ILIKE '%hen%'      OR p_product ILIKE '%spent%'
          OR p_product ILIKE '%pullet%'   OR p_product ILIKE '%fowl%'
          OR p_product ILIKE '%culled%'   OR p_product ILIKE '%chicken%' THEN 'BirdSales'
        ELSE 'OtherRevenue'
    END;
$function$;

COMMENT ON FUNCTION public.fnpoultrysale_revenueline(text) IS
    'Egg / Bird / Manure / Feed / Other, from the sale product name. Keyword by '
    'necessity: sale.product is free text with no product master behind it.';

CREATE OR REPLACE FUNCTION public.fnpoultrysale_revenuelabel(p_line text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE p_line
        WHEN 'EggSales'     THEN 'Egg Sales'
        WHEN 'BirdSales'    THEN 'Bird Sales'
        WHEN 'ManureSales'  THEN 'Manure Sales'
        WHEN 'FeedSales'    THEN 'Feed Sales'
        ELSE 'Other Operating Revenue'
    END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. The item category behind an expense row, when there is one.
--
-- This is the join a scalar resolver cannot do. A raw-material purchase points
-- straight at its item, which is where the truth about "is this feed?" lives.
--
-- Internal use is deliberately NOT resolved here: its lines reference PRODUCTS
-- (eggs, birds), not raw-material items, so there is no item category to read.
-- Those rows fall through to the category text, which is what they have always
-- been classified by.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryexpense_itemcategory(
    p_sourcetype text, p_sourceid integer
) RETURNS text
LANGUAGE sql STABLE
AS $function$
    SELECT CASE
        WHEN p_sourcetype = 'PoultryRawMaterialPurchase' THEN (
            SELECT i.category::text
            FROM   poultryrawmaterialpurchases p
            JOIN   poultryrawmaterialitems i ON i.poultryrawmaterialitemid = p.poultryrawmaterialitemid
            WHERE  p.poultryrawmaterialpurchaseid = p_sourceid)
        ELSE NULL
    END;
$function$;

COMMENT ON FUNCTION public.fnpoultryexpense_itemcategory(text, integer) IS
    'The raw-material item category behind an expense row, or NULL. Lets '
    'fnpoultryexpense_plline use Phase 1 grouping instead of a keyword.';

-- -----------------------------------------------------------------------------
-- 8. The expense read gains its classification.
--
-- poultryexpenserow is a composite type, so the columns are appended to it and
-- fnpoultryexpenserows is reproduced from the LIVE definition with the new
-- expressions on the end. Existing ordinals do not move.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_attribute
                   WHERE attrelid = 'poultryexpenserow'::regclass
                     AND attname = 'financialcosttype' AND NOT attisdropped) THEN
        ALTER TYPE poultryexpenserow ADD ATTRIBUTE financialcosttype text CASCADE;
        ALTER TYPE poultryexpenserow ADD ATTRIBUTE costtypeisstored boolean CASCADE;
        ALTER TYPE poultryexpenserow ADD ATTRIBUTE plline text CASCADE;
        ALTER TYPE poultryexpenserow ADD ATTRIBUTE pllinelabel text CASCADE;
        ALTER TYPE poultryexpenserow ADD ATTRIBUTE plsection text CASCADE;
        ALTER TYPE poultryexpenserow ADD ATTRIBUTE sourcelabel text CASCADE;
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
           fnpoultryexpense_sourcelabel(e.sourcetype::text)
    FROM   expense e
    LEFT   JOIN supplier s
           ON  s.supplierid = e.supplierid
           AND lower(s.farmid::text) = lower(e.farmid::text)
    CROSS  JOIN LATERAL (SELECT fnpoultryexpense_costtype(
                                    e.financialcosttype::text, e.sourcetype::text,
                                    e.category::text, e.paymentmethod::text) AS costtype) c
    CROSS  JOIN LATERAL (SELECT fnpoultryexpense_plline(
                                    c.costtype, e.sourcetype::text, e.category::text,
                                    fnpoultryexpense_itemcategory(e.sourcetype::text, e.sourceid)) AS line) l
    WHERE  e.farmid = p_farmid;
$function$;

-- -----------------------------------------------------------------------------
-- 9. Writers can now state the classification.
--
-- Both are reproduced from their LIVE definitions with ONE trailing parameter
-- added. The parameter defaults to NULL, so a caller that has not been
-- redeployed writes exactly the row it writes today -- an unstated
-- classification, resolved by the functions above.
--
-- DROP first: CREATE OR REPLACE cannot add a parameter, it would create a second
-- overload and every positional caller would become ambiguous.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spexpense_insert(timestamp without time zone, text, text, numeric, text, text, integer, text, uuid, bytea, text, integer, numeric, date, integer);

CREATE OR REPLACE FUNCTION public.spexpense_insert(p_expensedate timestamp without time zone, p_category text, p_description text, p_amount numeric, p_paymentmethod text, p_supplier text, p_flockid integer, p_userid text, p_farmid uuid, p_attachmentimage bytea DEFAULT NULL::bytea, p_attachmentcontenttype text DEFAULT NULL::text, p_supplierid integer DEFAULT NULL::integer, p_amountpaid numeric DEFAULT NULL::numeric, p_duedate date DEFAULT NULL::date, p_cashaccountid integer DEFAULT NULL::integer, p_financialcosttype text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id        integer;
    v_paid      numeric(14,2) := p_amountpaid;
    v_entrypaid numeric(14,2);
    v_pays      boolean;
    v_farmtext  text;
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than 0.';
    END IF;
    IF v_paid IS NOT NULL THEN
        IF v_paid < 0 THEN
            RAISE EXCEPTION 'Amount paid cannot be negative.';
        END IF;
        IF v_paid > p_amount THEN
            RAISE EXCEPTION 'Amount paid (%) cannot exceed the expense total (%).',
                  v_paid::numeric(14,2), p_amount::numeric(14,2);
        END IF;
    END IF;
    IF p_supplierid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM supplier s
                       WHERE s.supplierid = p_supplierid
                         AND lower(s.farmid::text) = lower(p_farmid::text)) THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;

    -- 269. A capital acquisition is recorded through the asset workflow, which
    -- links the row to its asset. Letting the plain expense form stamp
    -- CapitalAsset would create a cost that is excluded from profit and has no
    -- asset to depreciate -- money that vanishes from both sides of the report.
    IF p_financialcosttype = 'CapitalAsset' THEN
        RAISE EXCEPTION 'Record a capital asset on the Assets page so it can be depreciated.';
    END IF;

    -- Resolved: NULL has always meant "paid in full", so that is what was paid.
    v_entrypaid := COALESCE(v_paid, p_amount);
    -- The account is REQUIRED, and that is a safety interlock, not a nicety.
    -- sppoultrysupplierpaymentcash_sync posts the CashOut only when the payment
    -- names an account. Recording a payment without one would leave no CashOut
    -- AND zero the expense's own cash line (it resolves to paid-minus-
    -- allocations), so the money would simply disappear from the account.
    --
    -- It also makes this migration safe to apply BEFORE the API is redeployed:
    -- an older caller binds no account, so v_pays is false and the bill takes
    -- byte-for-byte the path it takes today. Payments start being recorded when
    -- the API that passes the account goes out, not a moment sooner.
    v_pays := fnpoultryexpenserecordspayment(p_supplierid, p_paymentmethod, v_entrypaid)
              AND p_cashaccountid IS NOT NULL;

    IF v_pays THEN
        -- Written UNPAID on purpose. _record ADDS to amountpaid, so the payment
        -- below is what moves it to v_entrypaid. Zero, never NULL: NULL reads as
        -- paid in full and the allocation would overshoot 238's guard.
        v_paid := 0;
    ELSIF v_paid IS NOT NULL AND v_paid >= p_amount THEN
        -- Unchanged legacy shape: a fully paid expense with no payment record to
        -- make looks identical to every row written before migration 238.
        v_paid := NULL;
    END IF;

    INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                         supplier, supplierid, amountpaid, duedate, flockid,
                         userid, farmid, attachmentimage, attachmentcontenttype,
                         createddate, financialcosttype)
    VALUES (p_expensedate, p_category, p_description, p_amount, p_paymentmethod,
            p_supplier, p_supplierid, v_paid, p_duedate, p_flockid,
            p_userid, p_farmid, p_attachmentimage, p_attachmentcontenttype,
            (now() at time zone 'utc'), NULLIF(p_financialcosttype, ''))
    RETURNING expenseid INTO v_id;

    IF v_pays THEN
        -- The supplier row carries the farmid in the TEXT form the payment
        -- tables use. expense.farmid is a uuid, and rendering it would risk a
        -- payment that does not group with the farm's others.
        SELECT s.farmid::text INTO v_farmtext
        FROM   supplier s WHERE s.supplierid = p_supplierid LIMIT 1;

        PERFORM sppoultrysupplierpayment_record(
            v_farmtext,
            p_supplierid,
            v_entrypaid,
            jsonb_build_array(jsonb_build_object(
                'documenttype', 'Expense', 'documentid', v_id, 'amount', v_entrypaid)),
            p_paymentmethod,
            p_expensedate,          -- dated the bill, which is when the money moved
            p_cashaccountid,
            NULL,
            'Paid when the bill was entered',
            'ExpenseEntry',
            p_userid);
    END IF;

    RETURN v_id;
END;
$function$;

DROP FUNCTION IF EXISTS public.spexpense_update(integer, timestamp without time zone, text, text, numeric, text, text, integer, text, uuid, boolean, bytea, text, integer, numeric, date, integer);

CREATE OR REPLACE FUNCTION public.spexpense_update(p_expenseid integer, p_expensedate timestamp without time zone, p_category text, p_description text, p_amount numeric, p_paymentmethod text, p_supplier text, p_flockid integer, p_userid text, p_farmid uuid, p_attachmentimageset boolean DEFAULT false, p_attachmentimage bytea DEFAULT NULL::bytea, p_attachmentcontenttype text DEFAULT NULL::text, p_supplierid integer DEFAULT NULL::integer, p_amountpaid numeric DEFAULT NULL::numeric, p_duedate date DEFAULT NULL::date, p_cashaccountid integer DEFAULT NULL::integer, p_financialcosttype text DEFAULT NULL::text, p_setfinancialcosttype boolean DEFAULT FALSE)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_alloc    numeric(14,2);
    v_paid     numeric(14,2) := p_amountpaid;
    v_current  numeric(14,2);
    v_target   numeric(14,2);
    v_delta    numeric(14,2);
    v_pays     boolean;
    v_acct     integer;
    v_farmtext text;
    v_existing text;
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than 0.';
    END IF;

    -- What supplier payments have already settled against this expense. Editing
    -- the row must never contradict money that has actually moved -- the balance
    -- on screen and fnbalanceaudit would disagree from that moment on.
    SELECT COALESCE(SUM(sa.amountapplied), 0) INTO v_alloc
    FROM   supplierpaymentallocation sa
    WHERE  lower(sa.farmid) = lower(p_farmid::text) AND sa.module = 'poultry'
      AND  sa.status = 'Posted' AND sa.documenttype = 'Expense'
      AND  sa.documentid = p_expenseid;

    -- What the bill says was paid before this edit, resolved.
    SELECT COALESCE(e.amountpaid, e.amount), e.financialcosttype::text
      INTO v_current, v_existing
    FROM   expense e
    WHERE  e.expenseid = p_expenseid AND e.farmid = p_farmid;

    IF v_current IS NULL THEN
        RAISE EXCEPTION 'Expense not found for this company.';
    END IF;

    -- 269. A capital acquisition belongs to its asset, and the asset's own
    -- workflow owns its cost. Editing it here would leave the asset register and
    -- the expense disagreeing about what the asset cost.
    IF v_existing = 'CapitalAsset' THEN
        RAISE EXCEPTION 'This cost belongs to a capital asset. Edit it on the Assets page.';
    END IF;
    IF p_setfinancialcosttype AND p_financialcosttype = 'CapitalAsset' THEN
        RAISE EXCEPTION 'Record a capital asset on the Assets page so it can be depreciated.';
    END IF;

    IF p_amount < v_alloc THEN
        RAISE EXCEPTION 'Supplier payments totalling % have been applied to this expense, so its total cannot be reduced to %.',
              v_alloc, p_amount::numeric(14,2);
    END IF;
    IF v_paid IS NOT NULL THEN
        IF v_paid < 0 THEN
            RAISE EXCEPTION 'Amount paid cannot be negative.';
        END IF;
        IF v_paid > p_amount THEN
            RAISE EXCEPTION 'Amount paid (%) cannot exceed the expense total (%).',
                  v_paid::numeric(14,2), p_amount::numeric(14,2);
        END IF;
        IF v_paid < v_alloc THEN
            RAISE EXCEPTION 'Supplier payments totalling % have been applied to this expense, so amount paid cannot be set to %. Reverse the payment on Supplier Payments first.',
                  v_alloc, v_paid;
        END IF;
    END IF;
    IF p_supplierid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM supplier s
                       WHERE s.supplierid = p_supplierid
                         AND lower(s.farmid::text) = lower(p_farmid::text)) THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;

    v_target := COALESCE(v_paid, p_amount);
    v_delta  := v_target - v_current;
    -- On an edit the bill usually already carries the account its cash went to
    -- (sppoultryexpensecash_sync stamps it), so fall back to that before giving
    -- up. Same interlock as the insert: no account, no payment, no lost cash.
    v_acct   := COALESCE(p_cashaccountid,
                         (SELECT e.poultrycashaccountid FROM expense e
                           WHERE e.expenseid = p_expenseid AND e.farmid = p_farmid));
    v_pays   := fnpoultryexpenserecordspayment(p_supplierid, p_paymentmethod, v_delta)
                AND v_acct IS NOT NULL;

    IF v_pays THEN
        -- Hold the row at what was already paid; the payment below adds the
        -- difference. An explicit number, never the NULL sentinel, for the same
        -- reason as the insert.
        v_paid := v_current;
    ELSIF v_paid IS NOT NULL AND v_paid >= p_amount THEN
        v_paid := NULL;
    END IF;

    UPDATE expense e
    SET    expensedate   = p_expensedate,
           category      = p_category,
           description   = p_description,
           amount        = p_amount,
           paymentmethod = p_paymentmethod,
           supplier      = p_supplier,
           supplierid    = p_supplierid,
           amountpaid    = v_paid,
           duedate       = p_duedate,
           flockid       = p_flockid,
           -- 269. Like the item override in Phase 1: NULL is a real value here
           -- ("not stated"), so a caller has to say it means the field at all.
           -- Editing a description must never silently reclassify a cost.
           financialcosttype = CASE WHEN p_setfinancialcosttype
                                    THEN NULLIF(p_financialcosttype, '')
                                    ELSE e.financialcosttype END,
           attachmentimage = CASE WHEN p_attachmentimageset THEN p_attachmentimage
                                  ELSE e.attachmentimage END,
           attachmentcontenttype = CASE WHEN p_attachmentimageset THEN p_attachmentcontenttype
                                        ELSE e.attachmentcontenttype END
    WHERE  e.expenseid = p_expenseid AND e.farmid = p_farmid;

    -- After the UPDATE, never before: _record reads the row's amount and
    -- supplier to validate the allocation against.
    IF v_pays THEN
        SELECT s.farmid::text INTO v_farmtext
        FROM   supplier s WHERE s.supplierid = p_supplierid LIMIT 1;

        PERFORM sppoultrysupplierpayment_record(
            v_farmtext,
            p_supplierid,
            v_delta,
            jsonb_build_array(jsonb_build_object(
                'documenttype', 'Expense', 'documentid', p_expenseid, 'amount', v_delta)),
            p_paymentmethod,
            (now() at time zone 'utc'),   -- paid today, not on the bill's date
            v_acct,
            NULL,
            'Recorded when the bill was edited',
            'ExpenseEntry',
            p_userid);
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 10. A capital cost cannot be deleted from the expense page either.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryexpense_iscapital(p_expenseid integer, p_farmid uuid)
RETURNS boolean
LANGUAGE sql STABLE
AS $function$
    SELECT EXISTS (SELECT 1 FROM expense e
                   WHERE e.expenseid = p_expenseid AND e.farmid = p_farmid
                     AND e.financialcosttype = 'CapitalAsset');
$function$;

-- -----------------------------------------------------------------------------
-- Post-conditions. Classification only -- no amount, no row, no total moves.
-- -----------------------------------------------------------------------------
SELECT 'every expense row classifies' AS check, COUNT(*) AS should_be_zero
FROM   expense e
WHERE  fnpoultryexpense_costtype(e.financialcosttype::text, e.sourcetype::text,
                                 e.category::text, e.paymentmethod::text) IS NULL;

SELECT 'raw material purchases no longer land in Other' AS check,
       COUNT(*) FILTER (WHERE l.line IN ('Feed', 'Medication', 'ProductionSupplies')) AS classified,
       COUNT(*) AS total
FROM   expense e
CROSS  JOIN LATERAL (SELECT fnpoultryexpense_plline(
                                'OperatingExpense', e.sourcetype::text, e.category::text,
                                fnpoultryexpense_itemcategory(e.sourcetype::text, e.sourceid)) AS line) l
WHERE  e.sourcetype = 'PoultryRawMaterialPurchase';

SELECT 'nothing is excluded from profit yet' AS check, COUNT(*) AS should_be_zero
FROM   expense e
WHERE  e.financialcosttype IN ('CapitalAsset', 'InventoryPurchase');

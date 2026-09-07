-- =============================================================================
-- 242_GenericBusinessTemplates.postgres.sql
--
-- Purpose
-- -------
-- Let a Generic company describe what KIND of business it is, so the app can
-- speak the owner's language -- "Members" for a gym, "Students" for a school,
-- "Clients" for a cleaning firm -- and show only the modules that business
-- actually uses.
--
-- Why this is not a new company type
-- ----------------------------------
-- A sixth Farms.Type would need its own farm guard, IAM companytype, controller
-- tree and spXxxCompany_Setup. Migration 028 already built the sub-type hook:
-- genericcompanyprofiles carries businesscategoryid + a name snapshot, one row
-- per farm. Two more columns on that row carry the template, and every existing
-- Generic company simply has NULL in them and behaves exactly as it does today.
--
-- Two ideas, deliberately separate
-- --------------------------------
--   genericbusinesstemplate   the MODULE BUNDLE -- which workflows exist at all.
--                             SubscriptionServiceBusiness | RetailBusiness |
--                             GeneralBusiness
--   genericindustrytemplate   the VOCABULARY and the SEEDS -- what things are
--                             called and what categories/accounts/plans a brand
--                             new company starts with. SaaS | Gym | School |
--                             CleaningService | SecurityService | Agency |
--                             RetainerBusiness | MembershipBusiness | Retail |
--                             Other
--
-- A gym and a SaaS company run the SAME bundle and differ only in vocabulary and
-- seeds. Splitting the two is what stops this becoming ten copies of one module.
--
-- spGenericCompany_Setup is NOT touched
-- ------------------------------------
-- Every Generic migration (028-113) is legacy T-SQL; the deployed objects are
-- machine-converted Postgres whose bodies are not in this repo. Rewriting one
-- blind is how you lose behaviour nobody wrote down. This adds a SEPARATE
-- spgenericbusinesstemplate_apply that runs after setup and only ever inserts.
--
-- EFFECT ON TODAY'S NUMBERS: none. Two nullable columns, one new table, one new
-- function, and catalog rows. Nothing existing is read or written differently.
--
-- Order: 242, then 243, then 244.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The template on the company profile.
-- -----------------------------------------------------------------------------
ALTER TABLE genericcompanyprofiles
    ADD COLUMN IF NOT EXISTS genericbusinesstemplate text NULL;
ALTER TABLE genericcompanyprofiles
    ADD COLUMN IF NOT EXISTS genericindustrytemplate text NULL;

COMMENT ON COLUMN genericcompanyprofiles.genericbusinesstemplate IS
    'Module bundle: SubscriptionServiceBusiness | RetailBusiness | GeneralBusiness. '
    'NULL means a company created before templates existed -- it keeps the full '
    'classic Generic menu, which is exactly what it has today.';
COMMENT ON COLUMN genericcompanyprofiles.genericindustrytemplate IS
    'Vocabulary and seed set: SaaS | Gym | School | CleaningService | '
    'SecurityService | Agency | RetainerBusiness | MembershipBusiness | Retail | '
    'Other. Drives labels and first-run defaults only -- never behaviour.';

-- -----------------------------------------------------------------------------
-- 2. Module visibility.
-- -----------------------------------------------------------------------------
-- A subscription business does not sell stock, so Products/Inventory/Purchases
-- are off by default -- but a gym DOES sell water and towels, and a school sells
-- books, so nothing is deleted, only hidden. Every flag can be switched back on.
CREATE TABLE IF NOT EXISTS genericmodulesettings (
    genericmodulesettingsid serial PRIMARY KEY,
    farmid                  varchar(450) NOT NULL,

    enableproducts          boolean NOT NULL DEFAULT TRUE,
    enableinventory         boolean NOT NULL DEFAULT TRUE,
    enablestockadjustments  boolean NOT NULL DEFAULT TRUE,
    enableinternaluse       boolean NOT NULL DEFAULT TRUE,
    enablepurchases         boolean NOT NULL DEFAULT TRUE,

    enablesubscriptions     boolean NOT NULL DEFAULT FALSE,
    enableinvoices          boolean NOT NULL DEFAULT FALSE,
    enablecustomerbalances  boolean NOT NULL DEFAULT FALSE,

    enablestaffpayments     boolean NOT NULL DEFAULT TRUE,
    enablecashaccounts      boolean NOT NULL DEFAULT TRUE,

    createdat               timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedat               timestamp NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_genericmodulesettings_farm
    ON genericmodulesettings (farmid);

-- Returns a SYNTHESISED row when the company has none, the way
-- spFarmProductionSettings_Get does (153:44-46). No caller handles null, and no
-- backfill is needed for the companies that already exist.
CREATE OR REPLACE FUNCTION public.spgenericmodulesettings_get(p_farmid text)
RETURNS TABLE(
    farmid                 text,
    enableproducts         boolean,
    enableinventory        boolean,
    enablestockadjustments boolean,
    enableinternaluse      boolean,
    enablepurchases        boolean,
    enablesubscriptions    boolean,
    enableinvoices         boolean,
    enablecustomerbalances boolean,
    enablestaffpayments    boolean,
    enablecashaccounts     boolean)
LANGUAGE sql
STABLE
AS $function$
    SELECT s.farmid::text, s.enableproducts, s.enableinventory, s.enablestockadjustments,
           s.enableinternaluse, s.enablepurchases, s.enablesubscriptions, s.enableinvoices,
           s.enablecustomerbalances, s.enablestaffpayments, s.enablecashaccounts
    FROM   genericmodulesettings s
    WHERE  s.farmid = p_farmid
    UNION ALL
    -- The default row: everything classic on, everything subscription off. This
    -- is what a pre-242 company sees, so nothing moves for them.
    SELECT p_farmid, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, TRUE, TRUE
    WHERE  NOT EXISTS (SELECT 1 FROM genericmodulesettings s2 WHERE s2.farmid = p_farmid)
    LIMIT  1;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericmodulesettings_upsert(
    p_farmid text,
    p_enableproducts boolean, p_enableinventory boolean, p_enablestockadjustments boolean,
    p_enableinternaluse boolean, p_enablepurchases boolean, p_enablesubscriptions boolean,
    p_enableinvoices boolean, p_enablecustomerbalances boolean,
    p_enablestaffpayments boolean, p_enablecashaccounts boolean)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO genericmodulesettings (
        farmid, enableproducts, enableinventory, enablestockadjustments,
        enableinternaluse, enablepurchases, enablesubscriptions, enableinvoices,
        enablecustomerbalances, enablestaffpayments, enablecashaccounts, updatedat)
    VALUES (
        p_farmid, p_enableproducts, p_enableinventory, p_enablestockadjustments,
        p_enableinternaluse, p_enablepurchases, p_enablesubscriptions, p_enableinvoices,
        p_enablecustomerbalances, p_enablestaffpayments, p_enablecashaccounts,
        (now() at time zone 'utc'))
    ON CONFLICT (farmid) DO UPDATE SET
        enableproducts         = EXCLUDED.enableproducts,
        enableinventory        = EXCLUDED.enableinventory,
        enablestockadjustments = EXCLUDED.enablestockadjustments,
        enableinternaluse      = EXCLUDED.enableinternaluse,
        enablepurchases        = EXCLUDED.enablepurchases,
        enablesubscriptions    = EXCLUDED.enablesubscriptions,
        enableinvoices         = EXCLUDED.enableinvoices,
        enablecustomerbalances = EXCLUDED.enablecustomerbalances,
        enablestaffpayments    = EXCLUDED.enablestaffpayments,
        enablecashaccounts     = EXCLUDED.enablecashaccounts,
        updatedat              = (now() at time zone 'utc');
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. A service becomes sellable on a schedule.
-- -----------------------------------------------------------------------------
-- A membership plan IS a service you sell repeatedly. genericservices already
-- carries name, price, cost, category and an active flag, and
-- genericsaleitems.itemtype = 'Service' already puts one on an invoice line, so
-- two columns turn the existing catalogue into a plan catalogue. A second table
-- would leave two places to look for "what do we sell".
ALTER TABLE genericservices ADD COLUMN IF NOT EXISTS plantype text NULL;
ALTER TABLE genericservices ADD COLUMN IF NOT EXISTS billingfrequency text NULL;

COMMENT ON COLUMN genericservices.plantype IS
    'Subscription | Membership | Retainer | ServiceContract | OneTimeService | '
    'SetupFee | Training | Tuition | Other. NULL is a plain one-off service, '
    'which is every row that existed before 242.';
COMMENT ON COLUMN genericservices.billingfrequency IS
    'OneTime | Weekly | Monthly | Quarterly | Termly | SemiAnnual | Annual. '
    'NULL behaves as OneTime.';

-- -----------------------------------------------------------------------------
-- 4. Apply a template to a company.
-- -----------------------------------------------------------------------------
-- Runs AFTER spGenericCompany_Setup, never instead of it. Only ever inserts, and
-- every insert is guarded, so re-running is a no-op rather than a duplicate set
-- of categories. Safe to call again when an owner changes their mind about the
-- industry: they get the new seeds and keep everything they already had.
-- Which template a company is on. Its own function rather than an extra column
-- on the profile getter: every Generic proc is machine-converted T-SQL whose
-- body is not in this repo, so a getter that selects a fixed column list would
-- silently keep omitting the two new columns. This one cannot.
--
-- Returns a row for a Generic company that has never been templated too, with
-- both columns NULL -- that company behaves exactly as it does today, and the
-- frontend falls back to the neutral labels rather than to an error.
CREATE OR REPLACE FUNCTION public.spgenericbusinesstemplate_get(p_farmid text)
RETURNS TABLE(
    farmid                  text,
    genericbusinesstemplate text,
    genericindustrytemplate text)
LANGUAGE sql
STABLE
AS $function$
    SELECT p.farmid::text, p.genericbusinesstemplate, p.genericindustrytemplate
    FROM   genericcompanyprofiles p
    WHERE  p.farmid = p_farmid
    LIMIT  1;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericbusinesstemplate_apply(
    p_farmid           text,
    p_businesstemplate text,
    p_industrytemplate text,
    p_createdby        text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_type  text;
    v_isSub boolean;
    v_row   record;
    v_catid integer;
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN
        RAISE EXCEPTION 'Company ID is required.';
    END IF;
    IF COALESCE(p_businesstemplate, '') NOT IN
       ('SubscriptionServiceBusiness', 'RetailBusiness', 'GeneralBusiness') THEN
        RAISE EXCEPTION 'Unknown business template "%".', p_businesstemplate;
    END IF;
    IF COALESCE(p_industrytemplate, '') NOT IN
       ('SaaS', 'Gym', 'School', 'CleaningService', 'SecurityService', 'Agency',
        'RetainerBusiness', 'MembershipBusiness', 'Retail', 'Other') THEN
        RAISE EXCEPTION 'Unknown industry template "%".', p_industrytemplate;
    END IF;

    -- The same guard every Generic SP applies. spfarm_gettype exists because the
    -- Farm API login has EXECUTE on procs but no SELECT on Farms (migration 089).
    SELECT * INTO v_type FROM spfarm_gettype(p_farmid => p_farmid);
    IF v_type IS NULL THEN
        RAISE EXCEPTION 'Company not found.';
    END IF;
    IF lower(v_type) <> 'generic' THEN
        RAISE EXCEPTION 'Templates apply to Generic companies only (this one is %).', v_type;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM genericcompanyprofiles WHERE farmid = p_farmid) THEN
        RAISE EXCEPTION 'Run company setup before applying a template.';
    END IF;

    v_isSub := (p_businesstemplate = 'SubscriptionServiceBusiness');

    UPDATE genericcompanyprofiles
    SET    genericbusinesstemplate = p_businesstemplate,
           genericindustrytemplate = p_industrytemplate,
           updatedat               = (now() at time zone 'utc')
    WHERE  farmid = p_farmid;

    -- Module visibility. A subscription business hides stock by default; a gym
    -- that later sells towels turns Products back on and nothing was lost.
    PERFORM spgenericmodulesettings_upsert(
        p_farmid,
        NOT v_isSub, NOT v_isSub, NOT v_isSub, NOT v_isSub, NOT v_isSub,
        v_isSub, v_isSub, v_isSub,
        TRUE, TRUE);

    -- ---- income categories (genericservicecategories) ----------------------
    -- Reused rather than a new income-category table: a service's category IS
    -- its revenue line, and every existing report already joins through it.
    FOR v_row IN
        SELECT name FROM (VALUES
            ('SaaS',            'Software Subscription Income'),
            ('SaaS',            'Setup / Onboarding Fee Income'),
            ('SaaS',            'Training Fee Income'),
            ('SaaS',            'Support Fee Income'),
            ('SaaS',            'Custom Development Income'),
            ('Gym',             'Membership Income'),
            ('Gym',             'Registration Fee Income'),
            ('Gym',             'Personal Training Income'),
            ('Gym',             'Class Fee Income'),
            ('School',          'Tuition Fee Income'),
            ('School',          'Term Fee Income'),
            ('School',          'Registration Fee Income'),
            ('School',          'Exam Fee Income'),
            ('School',          'Transport Fee Income'),
            ('CleaningService', 'Monthly Cleaning Contract Income'),
            ('CleaningService', 'One-Time Cleaning Income'),
            ('CleaningService', 'Deep Cleaning Income'),
            ('SecurityService', 'Monthly Security Contract Income'),
            ('SecurityService', 'Guard Service Income'),
            ('SecurityService', 'Installation Fee Income'),
            ('Agency',          'Monthly Retainer Income'),
            ('Agency',          'IT Support Income'),
            ('Agency',          'Consulting Income'),
            ('Agency',          'Project Income'),
            ('RetainerBusiness','Monthly Retainer Income'),
            ('RetainerBusiness','Project Income'),
            ('RetainerBusiness','Consulting Income'),
            ('MembershipBusiness','Membership Income'),
            ('MembershipBusiness','Registration Fee Income'),
            ('Retail',          'Product Sales Income'),
            ('Other',           'Service Income'),
            ('Other',           'Other Income')
        ) AS t(industry, name)
        WHERE t.industry = p_industrytemplate
    LOOP
        INSERT INTO genericservicecategories (farmid, name, isactive, isdeleted, createdat)
        SELECT p_farmid, v_row.name, TRUE, FALSE, (now() at time zone 'utc')
        WHERE  NOT EXISTS (SELECT 1 FROM genericservicecategories c
                           WHERE c.farmid = p_farmid AND c.name = v_row.name);
    END LOOP;

    -- ---- expense categories ------------------------------------------------
    FOR v_row IN
        SELECT name FROM (VALUES
            ('SaaS',            'Hosting / Cloud Infrastructure'),
            ('SaaS',            'Developer Payments'),
            ('SaaS',            'Contractor Payments'),
            ('SaaS',            'Software Tools'),
            ('SaaS',            'Domain Renewals'),
            ('SaaS',            'Payment Processing Fees'),
            ('Gym',             'Rent'),
            ('Gym',             'Trainer Payments'),
            ('Gym',             'Equipment Maintenance'),
            ('Gym',             'Cleaning Supplies'),
            ('School',          'Teacher Payments'),
            ('School',          'Teaching Materials'),
            ('School',          'Transport Expense'),
            ('School',          'Feeding Expense'),
            ('CleaningService', 'Cleaning Supplies'),
            ('CleaningService', 'Uniforms'),
            ('CleaningService', 'Transport'),
            ('SecurityService', 'Guard Payments'),
            ('SecurityService', 'Uniforms'),
            ('SecurityService', 'Communication'),
            ('Agency',          'Contractor Payments'),
            ('Agency',          'Software Tools'),
            ('Agency',          'Marketing / Ads'),
            ('RetainerBusiness','Contractor Payments'),
            ('RetainerBusiness','Software Tools'),
            ('MembershipBusiness','Rent'),
            ('MembershipBusiness','Staff Payments'),
            ('Retail',          'Rent'),
            ('Retail',          'Staff Payments'),
            ('Other',           'General Expense')
        ) AS t(industry, name)
        WHERE t.industry = p_industrytemplate
        UNION ALL
        -- Every business on earth pays these.
        SELECT name FROM (VALUES
            ('Employee Payments'), ('Marketing / Ads'), ('Internet / Phone'),
            ('Bank Charges'), ('Professional Fees'), ('Taxes / Government Fees'),
            ('Travel / Transportation'), ('Other Expense')
        ) AS c(name)
    LOOP
        INSERT INTO genericexpensecategories (farmid, name, isactive, isdeleted, createdat)
        SELECT p_farmid, v_row.name, TRUE, FALSE, (now() at time zone 'utc')
        WHERE  NOT EXISTS (SELECT 1 FROM genericexpensecategories c
                           WHERE c.farmid = p_farmid AND c.name = v_row.name);
    END LOOP;

    -- ---- cash accounts -----------------------------------------------------
    -- Opening balance 0 on purpose: real opening cash is recorded through the
    -- cash module so it lands on the ledger and can be reconciled, rather than
    -- being conjured into an account balance nothing accounts for.
    FOR v_row IN
        SELECT accountname, accounttype FROM (VALUES
            ('SaaS',            'Business Bank Account', 'BankAccount'),
            ('SaaS',            'Stripe / Card Payments','BankAccount'),
            ('SaaS',            'PayPal',                'BankAccount'),
            ('Gym',             'Cash',                  'MainCashBox'),
            ('Gym',             'Mobile Money / MoMo',   'MoMoWallet'),
            ('Gym',             'Business Bank Account', 'BankAccount'),
            ('School',          'Cash',                  'MainCashBox'),
            ('School',          'Mobile Money / MoMo',   'MoMoWallet'),
            ('School',          'Business Bank Account', 'BankAccount'),
            ('CleaningService', 'Cash',                  'MainCashBox'),
            ('CleaningService', 'Mobile Money / MoMo',   'MoMoWallet'),
            ('SecurityService', 'Cash',                  'MainCashBox'),
            ('SecurityService', 'Mobile Money / MoMo',   'MoMoWallet'),
            ('Agency',          'Business Bank Account', 'BankAccount'),
            ('Agency',          'Mobile Money / MoMo',   'MoMoWallet'),
            ('RetainerBusiness','Business Bank Account', 'BankAccount'),
            ('MembershipBusiness','Cash',                'MainCashBox'),
            ('MembershipBusiness','Mobile Money / MoMo', 'MoMoWallet'),
            ('Retail',          'Cash',                  'MainCashBox'),
            ('Other',           'Cash',                  'MainCashBox')
        ) AS t(industry, accountname, accounttype)
        WHERE t.industry = p_industrytemplate
        UNION ALL
        SELECT 'Petty Cash', 'PettyCash'
    LOOP
        INSERT INTO genericcashaccounts
            (farmid, accountname, accounttype, openingbalance, currentbalance,
             allownegativebalance, isactive, createdat)
        SELECT p_farmid, v_row.accountname, v_row.accounttype, 0, 0, FALSE, TRUE,
               (now() at time zone 'utc')
        WHERE  NOT EXISTS (SELECT 1 FROM genericcashaccounts a
                           WHERE a.farmid = p_farmid AND a.accountname = v_row.accountname);
    END LOOP;

    -- ---- starter plans -----------------------------------------------------
    -- Priced 0 deliberately: a seeded price would be a number the owner did not
    -- choose, and it would flow straight into an invoice. They edit the plan and
    -- set the real price before the first subscription.
    IF v_isSub THEN
        FOR v_row IN
            SELECT servicename, plantype, billingfrequency FROM (VALUES
                ('SaaS',            'Monthly Subscription',      'Subscription',    'Monthly'),
                ('SaaS',            'Annual Subscription',       'Subscription',    'Annual'),
                ('SaaS',            'Setup / Onboarding Fee',    'SetupFee',        'OneTime'),
                ('Gym',             'Monthly Membership',        'Membership',      'Monthly'),
                ('Gym',             'Annual Membership',         'Membership',      'Annual'),
                ('Gym',             'Registration Fee',          'SetupFee',        'OneTime'),
                ('School',          'Monthly Tuition',           'Tuition',         'Monthly'),
                ('School',          'Term Fee',                  'Tuition',         'Termly'),
                ('School',          'Registration Fee',          'SetupFee',        'OneTime'),
                ('CleaningService', 'Monthly Cleaning Contract', 'ServiceContract', 'Monthly'),
                ('CleaningService', 'One-Time Cleaning',         'OneTimeService',  'OneTime'),
                ('SecurityService', 'Monthly Security Contract', 'ServiceContract', 'Monthly'),
                ('SecurityService', 'Installation Fee',          'SetupFee',        'OneTime'),
                ('Agency',          'Monthly Retainer',          'Retainer',        'Monthly'),
                ('Agency',          'Project Fee',               'OneTimeService',  'OneTime'),
                ('RetainerBusiness','Monthly Retainer',          'Retainer',        'Monthly'),
                ('MembershipBusiness','Monthly Membership',      'Membership',      'Monthly'),
                ('MembershipBusiness','Annual Membership',       'Membership',      'Annual'),
                ('Other',           'Monthly Service',           'Subscription',    'Monthly')
            ) AS t(industry, servicename, plantype, billingfrequency)
            WHERE t.industry = p_industrytemplate
        LOOP
            SELECT c.genericservicecategoryid INTO v_catid
            FROM   genericservicecategories c
            WHERE  c.farmid = p_farmid AND COALESCE(c.isdeleted, FALSE) = FALSE
            ORDER  BY c.genericservicecategoryid
            LIMIT  1;

            INSERT INTO genericservices
                (farmid, genericservicecategoryid, servicename, defaultprice,
                 plantype, billingfrequency, isactive, isdeleted, createdat)
            SELECT p_farmid, v_catid, v_row.servicename, 0,
                   v_row.plantype, v_row.billingfrequency, TRUE, FALSE,
                   (now() at time zone 'utc')
            WHERE  NOT EXISTS (SELECT 1 FROM genericservices s
                               WHERE s.farmid = p_farmid AND s.servicename = v_row.servicename);
        END LOOP;
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Permission catalog.
-- -----------------------------------------------------------------------------
-- Seeded with the pages, not before them: a permission that appears in the roles
-- UI with nothing behind it is a support ticket waiting to happen (227's rule).
-- sortorder slots each resource beside its neighbours -- generic customers is 61
-- and cash is 81 in 199, so balances take 62/63 and the subscription block 64-67.
DO $iam$
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '242: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions
        (permissionkey, module, resource, action, permissiongroup, resourcelabel,
         description, companytype, isdangerous, sortorder)
    SELECT 'generic.' || r.resource || '.' || a.action,
           'generic', r.resource, a.action, r.grp, r.label, r.descr, 'Generic',
           (a.action IN ('reverse', 'delete')), r.sortorder
    FROM (VALUES
        ('subscription-plans', 'Subscriptions',      'Service Plans',
         'Create and price the plans customers subscribe to.',            64),
        ('subscriptions',      'Subscriptions',      'Subscriptions',
         'Start, pause, resume and cancel recurring billing.',            65),
        ('invoices',           'Sales & Customers',  'Invoices',
         'Raise and post invoices, including from a subscription.',       66),
        ('billing-runs',       'Subscriptions',      'Billing Runs',
         'Generate the invoices that are due.',                           67),
        ('customer-balances',  'Sales & Customers',  'Customer Balances',
         'See who owes money and the unpaid invoices behind each balance.', 62),
        ('customer-statements','Sales & Customers',  'Customer Statements',
         'Open a customer statement.',                                    63)
    ) AS r(resource, grp, label, descr, sortorder)
    CROSS JOIN (VALUES ('view'), ('create'), ('edit'), ('delete')) AS a(action)
    WHERE NOT EXISTS (SELECT 1 FROM iampermissions p
                      WHERE p.permissionkey = 'generic.' || r.resource || '.' || a.action);

    -- Reversal is its own dangerous action and only exists on payments.
    INSERT INTO iampermissions
        (permissionkey, module, resource, action, permissiongroup, resourcelabel,
         description, companytype, isdangerous, sortorder)
    SELECT v.k, 'generic', v.res, v.act, 'Sales & Customers', 'Customer Payments',
           v.descr, 'Generic', v.danger, 62
    FROM (VALUES
        ('generic.customer-payments.create',  'customer-payments', 'create',
         'Receive a customer payment and apply it to open invoices.', false),
        ('generic.customer-payments.reverse', 'customer-payments', 'reverse',
         'Reverse a posted customer payment.', true)
    ) AS v(k, res, act, descr, danger)
    WHERE NOT EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = v.k);
END
$iam$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 6. Verification.
-- -----------------------------------------------------------------------------
SELECT 'columns' AS check,
       CASE WHEN COUNT(*) = 4 THEN 'OK' ELSE 'ONLY ' || COUNT(*) END AS result
FROM   information_schema.columns
WHERE  (table_name, column_name) IN (
    ('genericcompanyprofiles', 'genericbusinesstemplate'),
    ('genericcompanyprofiles', 'genericindustrytemplate'),
    ('genericservices',        'plantype'),
    ('genericservices',        'billingfrequency'));

SELECT 'functions' AS check,
       CASE WHEN COUNT(*) = 4 THEN 'OK' ELSE 'ONLY ' || COUNT(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spgenericmodulesettings_get', 'spgenericmodulesettings_upsert',
                     'spgenericbusinesstemplate_apply', 'spgenericbusinesstemplate_get');

-- Every existing Generic company must still read as fully classic: all five
-- stock/purchase modules on, all three subscription modules off. Expect every
-- row to say OK.
SELECT 'untouched company defaults' AS check, f.farmid,
       CASE WHEN s.enableproducts AND s.enablepurchases
             AND NOT s.enablesubscriptions AND NOT s.enableinvoices
            THEN 'OK' ELSE 'CHANGED' END AS result
FROM   (SELECT DISTINCT farmid FROM genericcompanyprofiles) f
CROSS  JOIN LATERAL spgenericmodulesettings_get(f.farmid) s;

-- No company has a template yet. Expect NO ROWS.
SELECT farmid, genericbusinesstemplate, genericindustrytemplate
FROM   genericcompanyprofiles
WHERE  genericbusinesstemplate IS NOT NULL OR genericindustrytemplate IS NOT NULL;

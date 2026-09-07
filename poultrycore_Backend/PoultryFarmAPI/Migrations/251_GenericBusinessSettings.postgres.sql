-- =============================================================================
-- 251_GenericBusinessSettings.postgres.sql
--
-- Purpose
-- -------
-- The settings the last four migrations kept deferring. 242 shipped ten module
-- toggles, and 248 and 249 then added two modules with no toggle to hide them:
-- Supplier Balances was gated on enablePurchases, which is wrong for a service
-- business that has vendor bills but buys no stock, and Recurring Expenses was
-- ungated entirely. This file gives both a switch of their own, and adds the
-- company-level settings section 26 of the spec asks for.
--
-- WHAT IS WIRED, AND WHAT IS ONLY STORED
-- --------------------------------------
-- Every column in the spec's list exists here so no follow-up migration is
-- needed to add them. They are NOT all read yet, and the ones that are not are
-- deliberately absent from the settings page: a switch that changes nothing is
-- worse than no switch, because someone will set it and believe it.
--
-- Read by something today:
--   the 12 module toggles              menus, and the pages behind them
--   the 7 dashboard show* flags        the subscription dashboard's cards
--   defaultbillingfrequency            new-subscription form
--   defaultpaymentduedays              new-subscription form
--   autogenerateinvoices               new-subscription form's default
--   defaultcashaccountforpayments      new-subscription form
--   defaultrevenuecategoryid           new-plan form
--   autopostinvoices                   the billing run, below
--
-- Stored, read by nothing yet -- every one carries a COMMENT saying so:
--   defaultgraceperioddays, automarkoverdueinvoices, allowoverpayments,
--   allowcustomercredits, defaultexpensecashaccountid,
--   requirereceiptaboveamount, requireapprovalaboveamount, allowunpaidexpenses,
--   allowpartialexpensepayments, requirecashaccountforeverypayment,
--   allownegativecashaccounts, requirereconciliationwarning,
--   reconciliationreminderfrequency
--
-- Two of those deserve their reason spelled out:
--
--   defaultgraceperioddays is NOT wired into overdue. Overdue is derived --
--   duedate < today -- by fngenericopeninvoices and everything downstream of
--   it. Applying a grace period in the dashboard but not on the Customer
--   Balances page would give one company two different debtor lists, and
--   applying it in 244 and 248 would change what "overdue" has meant since
--   those migrations shipped. It belongs to the reminder work, which is where
--   "chase them after N days" is actually the question being asked.
--
--   allowoverpayments would relax a guard that SQL enforces today: an
--   allocation cannot exceed a document's balance. That invariant is what
--   fngenericbalanceaudit watches. Relaxing it needs a credit-note concept to
--   put the excess somewhere, not a boolean.
--
-- AUTO-POSTING INVOICES IS A REAL BEHAVIOUR CHANGE
-- -----------------------------------------------
-- 243 raises DRAFT invoices on purpose: a generic sale becomes a receivable
-- only when approved, and nothing should silently post to a customer's account
-- from a batch job. autopostinvoices lets an owner opt into exactly that, and
-- it defaults FALSE, so every existing company keeps today's behaviour.
--
-- When it is on, the billing run calls spgenericsale_approve -- the SAME
-- function the Approve button calls -- rather than repeating the posting logic.
-- That function is idempotent and refuses anything not in Draft, so a run that
-- half-fails cannot double-post.
--
-- EFFECT ON TODAY'S NUMBERS: none. Two boolean columns defaulting TRUE on a
-- settings table, one new settings table, and functions. The billing run's
-- behaviour is unchanged for every company until someone turns auto-posting on.
--
-- Order: after 250.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Drop by NAME, not by signature.
--
-- spgenericmodulesettings_get returns two more columns and _upsert takes two
-- more arguments, and CREATE OR REPLACE cannot do either. Dropping every
-- overload first is also what stops the OLD ten-argument _upsert surviving
-- alongside the new one, where Npgsql could pick either by named-argument
-- match and silently write a row missing the new toggles.
-- -----------------------------------------------------------------------------
DO $drop$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM   pg_proc p
        JOIN   pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('spgenericmodulesettings_get',
                             'spgenericmodulesettings_upsert',
                             'spgenericbusinesssettings_get',
                             'spgenericbusinesssettings_upsert')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- -----------------------------------------------------------------------------
-- 1. The two missing module toggles.
--
-- Both default TRUE, which is what every existing company already sees:
-- Recurring Expenses has been ungated since 249, and Supplier Balances has been
-- shown to anyone with Purchases on. A subscription business now gets Supplier
-- Balances WITHOUT Purchases, which is the spec's default and the one 248
-- actually supports -- its payables arm reads expenses, not just purchases.
-- -----------------------------------------------------------------------------
ALTER TABLE genericmodulesettings
    ADD COLUMN IF NOT EXISTS enablerecurringexpenses boolean NOT NULL DEFAULT TRUE;
ALTER TABLE genericmodulesettings
    ADD COLUMN IF NOT EXISTS enablesupplierbalances  boolean NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN genericmodulesettings.enablerecurringexpenses IS
    'Shows the Recurring Expenses menu item (249). Turning it off hides the '
    'templates; it never stops an expense a template already generated.';
COMMENT ON COLUMN genericmodulesettings.enablesupplierbalances IS
    'Shows the Supplier Balances menu item (248). Independent of enablepurchases '
    'on purpose: a service business owes vendors through expenses, not stock.';

-- -----------------------------------------------------------------------------
-- 2. Company settings.
--
-- One row per company, created on demand. A company without a row is not
-- broken -- spgenericbusinesssettings_get synthesises the same defaults the
-- table declares, exactly as spgenericmodulesettings_get already does, so a
-- company that predates this migration reads as "everything at its default"
-- rather than as an error the frontend has to special-case.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericbusinesssettings (
    genericbusinesssettingsid serial PRIMARY KEY,
    farmid                    varchar(450) NOT NULL,

    -- ---- subscription / billing ------------------------------------------
    defaultbillingfrequency        text    NOT NULL DEFAULT 'Monthly',
    defaultpaymentduedays          integer NOT NULL DEFAULT 0 CHECK (defaultpaymentduedays >= 0),
    defaultgraceperioddays         integer NOT NULL DEFAULT 0 CHECK (defaultgraceperioddays >= 0),
    autogenerateinvoices           boolean NOT NULL DEFAULT TRUE,
    autopostinvoices               boolean NOT NULL DEFAULT FALSE,
    automarkoverdueinvoices        boolean NOT NULL DEFAULT TRUE,
    allowoverpayments              boolean NOT NULL DEFAULT FALSE,
    allowcustomercredits           boolean NOT NULL DEFAULT FALSE,
    defaultrevenuecategoryid       integer NULL,
    defaultcashaccountforpayments  integer NULL,

    -- ---- expenses ---------------------------------------------------------
    defaultexpensecashaccountid    integer NULL,
    requirereceiptaboveamount      numeric(14,2) NULL,
    requireapprovalaboveamount     numeric(14,2) NULL,
    allowunpaidexpenses            boolean NOT NULL DEFAULT TRUE,
    allowpartialexpensepayments    boolean NOT NULL DEFAULT TRUE,

    -- ---- cash -------------------------------------------------------------
    requirecashaccountforeverypayment boolean NOT NULL DEFAULT TRUE,
    allownegativecashaccounts         boolean NOT NULL DEFAULT FALSE,
    requirereconciliationwarning      boolean NOT NULL DEFAULT TRUE,
    reconciliationreminderfrequency   text    NOT NULL DEFAULT 'Monthly',

    -- ---- dashboard cards --------------------------------------------------
    showmrr                    boolean NOT NULL DEFAULT TRUE,
    showburnrate               boolean NOT NULL DEFAULT TRUE,
    showbreakevencustomers     boolean NOT NULL DEFAULT TRUE,
    showcustomerbalances       boolean NOT NULL DEFAULT TRUE,
    showsupplierbalances       boolean NOT NULL DEFAULT TRUE,
    showcalculatedcashathand   boolean NOT NULL DEFAULT TRUE,
    showinventorycards         boolean NOT NULL DEFAULT FALSE,

    createdat timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedat timestamp NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_genericbusinesssettings_farm
    ON genericbusinesssettings (farmid);

COMMENT ON TABLE genericbusinesssettings IS
    'Company-level policy and defaults for a Generic business (spec section 26). '
    'Module VISIBILITY stays in genericmodulesettings; this table is about how '
    'the modules behave, not which ones exist.';

-- The wired ones.
COMMENT ON COLUMN genericbusinesssettings.defaultbillingfrequency IS
    'Prefills the new-subscription form. One of the fngenericnextbillingdate cases.';
COMMENT ON COLUMN genericbusinesssettings.autopostinvoices IS
    'When TRUE the billing run approves each invoice it raises, through '
    'spgenericsale_approve. FALSE -- the default and the behaviour since 243 -- '
    'leaves them Draft for a person to approve.';

-- The stored-but-unread ones. Each says what will read it, so the next person
-- does not wire a switch into a page and assume the rest already work.
COMMENT ON COLUMN genericbusinesssettings.defaultgraceperioddays IS
    'RESERVED for reminders. NOT applied to overdue: overdue is derived from '
    'duedate < today in fngenericopeninvoices, and changing that here would '
    'give the dashboard and the balances page two different debtor lists.';
COMMENT ON COLUMN genericbusinesssettings.automarkoverdueinvoices IS
    'RESERVED. Nothing stamps an overdue status in this schema -- overdue is '
    'derived on read -- so there is nothing yet for this to switch.';
COMMENT ON COLUMN genericbusinesssettings.allowoverpayments IS
    'RESERVED. An allocation above a document balance is blocked in SQL and '
    'watched by fngenericbalanceaudit; relaxing it needs somewhere to put the '
    'excess (a credit note), not a boolean.';
COMMENT ON COLUMN genericbusinesssettings.allowcustomercredits IS
    'RESERVED. Needs a credit-note document; see allowoverpayments.';
COMMENT ON COLUMN genericbusinesssettings.defaultexpensecashaccountid IS
    'RESERVED for the expense form.';
COMMENT ON COLUMN genericbusinesssettings.requirereceiptaboveamount IS
    'RESERVED for the expense form.';
COMMENT ON COLUMN genericbusinesssettings.requireapprovalaboveamount IS
    'RESERVED for the expense form.';
COMMENT ON COLUMN genericbusinesssettings.allowunpaidexpenses IS
    'RESERVED for the expense form.';
COMMENT ON COLUMN genericbusinesssettings.allowpartialexpensepayments IS
    'RESERVED for the expense payment form.';
COMMENT ON COLUMN genericbusinesssettings.requirecashaccountforeverypayment IS
    'RESERVED for the payment forms.';
COMMENT ON COLUMN genericbusinesssettings.allownegativecashaccounts IS
    'RESERVED as the default for NEW cash accounts. Each account already carries '
    'its own allownegativebalance, which is what the SPs actually enforce.';
COMMENT ON COLUMN genericbusinesssettings.requirereconciliationwarning IS
    'RESERVED for reminders.';
COMMENT ON COLUMN genericbusinesssettings.reconciliationreminderfrequency IS
    'RESERVED for reminders.';

-- -----------------------------------------------------------------------------
-- 3. Module settings, now with twelve toggles.
--
-- The default row keeps its rule: everything classic on, everything
-- subscription off, so a pre-242 company sees exactly what it sees today. Both
-- new toggles default ON, because both modules are visible to somebody today
-- and a migration must not take a menu away.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericmodulesettings_get(p_farmid text)
RETURNS TABLE(
    farmid                  text,
    enableproducts          boolean,
    enableinventory         boolean,
    enablestockadjustments  boolean,
    enableinternaluse       boolean,
    enablepurchases         boolean,
    enablesubscriptions     boolean,
    enableinvoices          boolean,
    enablecustomerbalances  boolean,
    enablestaffpayments     boolean,
    enablecashaccounts      boolean,
    enablerecurringexpenses boolean,
    enablesupplierbalances  boolean
)
LANGUAGE sql STABLE
AS $function$
    SELECT s.farmid::text, s.enableproducts, s.enableinventory, s.enablestockadjustments,
           s.enableinternaluse, s.enablepurchases, s.enablesubscriptions, s.enableinvoices,
           s.enablecustomerbalances, s.enablestaffpayments, s.enablecashaccounts,
           s.enablerecurringexpenses, s.enablesupplierbalances
    FROM   genericmodulesettings s
    WHERE  s.farmid = p_farmid
    UNION ALL
    SELECT p_farmid, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, TRUE, TRUE,
           TRUE, TRUE
    WHERE  NOT EXISTS (SELECT 1 FROM genericmodulesettings s2 WHERE s2.farmid = p_farmid)
    LIMIT  1;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericmodulesettings_upsert(
    p_farmid                  text,
    p_enableproducts          boolean,
    p_enableinventory         boolean,
    p_enablestockadjustments  boolean,
    p_enableinternaluse       boolean,
    p_enablepurchases         boolean,
    p_enablesubscriptions     boolean,
    p_enableinvoices          boolean,
    p_enablecustomerbalances  boolean,
    p_enablestaffpayments     boolean,
    p_enablecashaccounts      boolean,
    -- Defaulted so the ten-argument call inside spgenericbusinesstemplate_apply
    -- keeps working if it is ever run from an older copy of that function.
    p_enablerecurringexpenses boolean DEFAULT TRUE,
    p_enablesupplierbalances  boolean DEFAULT TRUE
) RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO genericmodulesettings (
        farmid, enableproducts, enableinventory, enablestockadjustments,
        enableinternaluse, enablepurchases, enablesubscriptions, enableinvoices,
        enablecustomerbalances, enablestaffpayments, enablecashaccounts,
        enablerecurringexpenses, enablesupplierbalances, updatedat)
    VALUES (
        p_farmid, p_enableproducts, p_enableinventory, p_enablestockadjustments,
        p_enableinternaluse, p_enablepurchases, p_enablesubscriptions, p_enableinvoices,
        p_enablecustomerbalances, p_enablestaffpayments, p_enablecashaccounts,
        COALESCE(p_enablerecurringexpenses, TRUE), COALESCE(p_enablesupplierbalances, TRUE),
        (now() at time zone 'utc'))
    ON CONFLICT (farmid) DO UPDATE
    SET enableproducts          = EXCLUDED.enableproducts,
        enableinventory         = EXCLUDED.enableinventory,
        enablestockadjustments  = EXCLUDED.enablestockadjustments,
        enableinternaluse       = EXCLUDED.enableinternaluse,
        enablepurchases         = EXCLUDED.enablepurchases,
        enablesubscriptions     = EXCLUDED.enablesubscriptions,
        enableinvoices          = EXCLUDED.enableinvoices,
        enablecustomerbalances  = EXCLUDED.enablecustomerbalances,
        enablestaffpayments     = EXCLUDED.enablestaffpayments,
        enablecashaccounts      = EXCLUDED.enablecashaccounts,
        enablerecurringexpenses = EXCLUDED.enablerecurringexpenses,
        enablesupplierbalances  = EXCLUDED.enablesupplierbalances,
        updatedat               = EXCLUDED.updatedat;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Company settings: read and write.
--
-- _get never returns nothing. A company with no row gets the declared defaults,
-- so "has this company been set up?" is not a question any caller has to ask.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericbusinesssettings_get(p_farmid text)
RETURNS TABLE(
    farmid                            text,
    defaultbillingfrequency           text,
    defaultpaymentduedays             integer,
    defaultgraceperioddays            integer,
    autogenerateinvoices              boolean,
    autopostinvoices                  boolean,
    automarkoverdueinvoices           boolean,
    allowoverpayments                 boolean,
    allowcustomercredits              boolean,
    defaultrevenuecategoryid          integer,
    defaultcashaccountforpayments     integer,
    defaultexpensecashaccountid       integer,
    requirereceiptaboveamount         numeric,
    requireapprovalaboveamount        numeric,
    allowunpaidexpenses               boolean,
    allowpartialexpensepayments       boolean,
    requirecashaccountforeverypayment boolean,
    allownegativecashaccounts         boolean,
    requirereconciliationwarning      boolean,
    reconciliationreminderfrequency   text,
    showmrr                           boolean,
    showburnrate                      boolean,
    showbreakevencustomers            boolean,
    showcustomerbalances              boolean,
    showsupplierbalances              boolean,
    showcalculatedcashathand          boolean,
    showinventorycards                boolean
)
LANGUAGE sql STABLE
AS $function$
    SELECT s.farmid::text,
           s.defaultbillingfrequency, s.defaultpaymentduedays, s.defaultgraceperioddays,
           s.autogenerateinvoices, s.autopostinvoices, s.automarkoverdueinvoices,
           s.allowoverpayments, s.allowcustomercredits,
           s.defaultrevenuecategoryid, s.defaultcashaccountforpayments,
           s.defaultexpensecashaccountid, s.requirereceiptaboveamount,
           s.requireapprovalaboveamount, s.allowunpaidexpenses,
           s.allowpartialexpensepayments, s.requirecashaccountforeverypayment,
           s.allownegativecashaccounts, s.requirereconciliationwarning,
           s.reconciliationreminderfrequency,
           s.showmrr, s.showburnrate, s.showbreakevencustomers,
           s.showcustomerbalances, s.showsupplierbalances,
           s.showcalculatedcashathand, s.showinventorycards
    FROM   genericbusinesssettings s
    WHERE  s.farmid = p_farmid
    UNION ALL
    -- The same values the columns declare. Kept in step by the check file,
    -- which asserts a synthesised row equals a freshly inserted one.
    SELECT p_farmid, 'Monthly', 0, 0,
           TRUE, FALSE, TRUE, FALSE, FALSE,
           NULL::integer, NULL::integer, NULL::integer,
           NULL::numeric, NULL::numeric, TRUE, TRUE, TRUE, FALSE, TRUE, 'Monthly',
           TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE
    WHERE  NOT EXISTS (SELECT 1 FROM genericbusinesssettings s2 WHERE s2.farmid = p_farmid)
    LIMIT  1;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericbusinesssettings_upsert(
    p_farmid                            text,
    p_defaultbillingfrequency           text    DEFAULT NULL,
    p_defaultpaymentduedays             integer DEFAULT NULL,
    p_defaultgraceperioddays            integer DEFAULT NULL,
    p_autogenerateinvoices              boolean DEFAULT NULL,
    p_autopostinvoices                  boolean DEFAULT NULL,
    p_automarkoverdueinvoices           boolean DEFAULT NULL,
    p_allowoverpayments                 boolean DEFAULT NULL,
    p_allowcustomercredits              boolean DEFAULT NULL,
    p_defaultrevenuecategoryid          integer DEFAULT NULL,
    p_defaultcashaccountforpayments     integer DEFAULT NULL,
    p_defaultexpensecashaccountid       integer DEFAULT NULL,
    p_requirereceiptaboveamount         numeric DEFAULT NULL,
    p_requireapprovalaboveamount        numeric DEFAULT NULL,
    p_allowunpaidexpenses               boolean DEFAULT NULL,
    p_allowpartialexpensepayments       boolean DEFAULT NULL,
    p_requirecashaccountforeverypayment boolean DEFAULT NULL,
    p_allownegativecashaccounts         boolean DEFAULT NULL,
    p_requirereconciliationwarning      boolean DEFAULT NULL,
    p_reconciliationreminderfrequency   text    DEFAULT NULL,
    p_showmrr                           boolean DEFAULT NULL,
    p_showburnrate                      boolean DEFAULT NULL,
    p_showbreakevencustomers            boolean DEFAULT NULL,
    p_showcustomerbalances              boolean DEFAULT NULL,
    p_showsupplierbalances              boolean DEFAULT NULL,
    p_showcalculatedcashathand          boolean DEFAULT NULL,
    p_showinventorycards                boolean DEFAULT NULL,
    -- The two id columns are nullable and "clear it" is a real intent, so NULL
    -- alone cannot mean "leave alone" for them. These say which of the three
    -- nullable columns the caller actually meant to touch.
    p_setrevenuecategory                boolean DEFAULT FALSE,
    p_setpaymentcashaccount             boolean DEFAULT FALSE,
    p_setexpensecashaccount             boolean DEFAULT FALSE
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_freq text := COALESCE(p_defaultbillingfrequency, 'Monthly');
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN
        RAISE EXCEPTION 'Company ID is required.';
    END IF;

    -- The frequency has to be one the billing run can actually advance, or a
    -- subscription created from this default would never raise a second
    -- invoice. Same list as fngenericnextbillingdate (243).
    IF v_freq NOT IN ('Weekly', 'Monthly', 'Quarterly', 'Termly', 'SemiAnnual', 'Annual', 'OneTime') THEN
        RAISE EXCEPTION 'Unknown billing frequency "%".', v_freq;
    END IF;

    IF COALESCE(p_reconciliationreminderfrequency, 'Monthly')
       NOT IN ('Never', 'Weekly', 'Monthly', 'Quarterly') THEN
        RAISE EXCEPTION 'Unknown reconciliation frequency "%".', p_reconciliationreminderfrequency;
    END IF;

    INSERT INTO genericbusinesssettings (farmid) VALUES (p_farmid)
    ON CONFLICT (farmid) DO NOTHING;

    -- COALESCE per column: a NULL means "leave this one alone", so a page that
    -- only edits the dashboard cards cannot blank the billing defaults it never
    -- showed. The three nullable ids opt in through their own flags.
    UPDATE genericbusinesssettings s
    SET defaultbillingfrequency           = COALESCE(p_defaultbillingfrequency, s.defaultbillingfrequency),
        defaultpaymentduedays             = COALESCE(p_defaultpaymentduedays, s.defaultpaymentduedays),
        defaultgraceperioddays            = COALESCE(p_defaultgraceperioddays, s.defaultgraceperioddays),
        autogenerateinvoices              = COALESCE(p_autogenerateinvoices, s.autogenerateinvoices),
        autopostinvoices                  = COALESCE(p_autopostinvoices, s.autopostinvoices),
        automarkoverdueinvoices           = COALESCE(p_automarkoverdueinvoices, s.automarkoverdueinvoices),
        allowoverpayments                 = COALESCE(p_allowoverpayments, s.allowoverpayments),
        allowcustomercredits              = COALESCE(p_allowcustomercredits, s.allowcustomercredits),
        defaultrevenuecategoryid          = CASE WHEN p_setrevenuecategory    THEN p_defaultrevenuecategoryid      ELSE s.defaultrevenuecategoryid END,
        defaultcashaccountforpayments     = CASE WHEN p_setpaymentcashaccount THEN p_defaultcashaccountforpayments ELSE s.defaultcashaccountforpayments END,
        defaultexpensecashaccountid       = CASE WHEN p_setexpensecashaccount THEN p_defaultexpensecashaccountid   ELSE s.defaultexpensecashaccountid END,
        requirereceiptaboveamount         = COALESCE(p_requirereceiptaboveamount, s.requirereceiptaboveamount),
        requireapprovalaboveamount        = COALESCE(p_requireapprovalaboveamount, s.requireapprovalaboveamount),
        allowunpaidexpenses               = COALESCE(p_allowunpaidexpenses, s.allowunpaidexpenses),
        allowpartialexpensepayments       = COALESCE(p_allowpartialexpensepayments, s.allowpartialexpensepayments),
        requirecashaccountforeverypayment = COALESCE(p_requirecashaccountforeverypayment, s.requirecashaccountforeverypayment),
        allownegativecashaccounts         = COALESCE(p_allownegativecashaccounts, s.allownegativecashaccounts),
        requirereconciliationwarning      = COALESCE(p_requirereconciliationwarning, s.requirereconciliationwarning),
        reconciliationreminderfrequency   = COALESCE(p_reconciliationreminderfrequency, s.reconciliationreminderfrequency),
        showmrr                           = COALESCE(p_showmrr, s.showmrr),
        showburnrate                      = COALESCE(p_showburnrate, s.showburnrate),
        showbreakevencustomers            = COALESCE(p_showbreakevencustomers, s.showbreakevencustomers),
        showcustomerbalances              = COALESCE(p_showcustomerbalances, s.showcustomerbalances),
        showsupplierbalances              = COALESCE(p_showsupplierbalances, s.showsupplierbalances),
        showcalculatedcashathand          = COALESCE(p_showcalculatedcashathand, s.showcalculatedcashathand),
        showinventorycards                = COALESCE(p_showinventorycards, s.showinventorycards),
        updatedat                         = (now() at time zone 'utc')
    WHERE s.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. The template seeds settings as well as modules.
--
-- Reproduced from the LIVE definition rather than from 242's file: the two can
-- drift, and the live one is what is actually running. The only edits are the
-- two extra module arguments and the settings seed.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericbusinesstemplate_apply(p_farmid text, p_businesstemplate text, p_industrytemplate text, p_createdby text DEFAULT NULL::text)
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
        TRUE, TRUE,
        -- 251: recurring expenses and supplier balances are ON for every
        -- template. A service business owes vendors through expenses even with
        -- Purchases hidden, which is exactly why Supplier Balances is no longer
        -- gated on stock buying.
        TRUE, TRUE);

    -- Company settings (251). Seeded rather than left to default, so the
    -- settings page opens on a real row and the billing defaults below actually
    -- reach a new subscription. Only the fields a TEMPLATE is entitled to
    -- decide are passed; every other setting keeps whatever it already had,
    -- which is what makes re-applying a template safe.
    PERFORM spgenericbusinesssettings_upsert(
        p_farmid                  => p_farmid,
        p_defaultbillingfrequency => CASE WHEN p_industrytemplate = 'School' THEN 'Termly'
                                          WHEN v_isSub THEN 'Monthly'
                                          ELSE 'OneTime' END,
        -- A gym takes the money at the door; an agency invoices on terms. A
        -- starting point the owner edits, not a promise.
        p_defaultpaymentduedays   => CASE WHEN p_industrytemplate IN ('Agency', 'RetainerBusiness',
                                                                     'CleaningService', 'SecurityService')
                                          THEN 14 ELSE 0 END,
        p_showinventorycards      => NOT v_isSub);

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
-- 6. The billing run can post what it raises.
--
-- Also reproduced from the LIVE definition. Three edits: one variable, one read
-- of the setting, one call to spgenericsale_approve. Everything else -- the
-- catch-up loop, the duplicate guard, the invoice numbering, the expiry rule --
-- is untouched.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericbillingrun_generate(p_farmid text, p_asof date DEFAULT NULL::date, p_createdby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_asof      date := COALESCE(p_asof, CURRENT_DATE);
    v_runid     integer;
    v_sub       record;
    v_checked   integer := 0;
    v_generated integer := 0;
    v_skipped   integer := 0;
    v_periodend date;
    v_next      date;
    v_saleid    integer;
    v_total     numeric(14,2);
    v_guard     integer;
    -- 251. Read once per run rather than once per invoice: the setting cannot
    -- change halfway through a run, and a company with no settings row reads
    -- FALSE, which is the behaviour every company has had since 243.
    v_autopost  boolean;
BEGIN
    INSERT INTO genericbillingruns (farmid, asofdate, status, createdby)
    VALUES (p_farmid, v_asof, 'Completed', p_createdby)
    RETURNING genericbillingrunid INTO v_runid;

    SELECT s.autopostinvoices INTO v_autopost
    FROM   spgenericbusinesssettings_get(p_farmid) s;
    v_autopost := COALESCE(v_autopost, FALSE);

    FOR v_sub IN
        SELECT s.* FROM genericsubscriptions s
        WHERE  s.farmid = p_farmid
          AND  s.status = 'Active'
          AND  s.autogenerateinvoice
          AND  s.nextbillingdate IS NOT NULL
          AND  s.nextbillingdate <= v_asof
        ORDER  BY s.genericsubscriptionid
    LOOP
        v_checked := v_checked + 1;
        v_next    := v_sub.nextbillingdate;
        v_total   := (v_sub.billingamount - v_sub.discountamount + v_sub.taxamount)::numeric(14,2);
        v_guard   := 0;

        -- Catch up period by period. The guard stops a bad frequency (which
        -- would return a NULL next date) from spinning forever.
        WHILE v_next IS NOT NULL AND v_next <= v_asof
              AND (v_sub.enddate IS NULL OR v_next <= v_sub.enddate)
              AND v_guard < 60
        LOOP
            v_guard     := v_guard + 1;
            v_periodend := (COALESCE(fngenericnextbillingdate(v_next, v_sub.billingfrequency),
                                     v_next + 1) - 1)::date;

            IF EXISTS (SELECT 1 FROM genericsales g
                       WHERE g.genericsubscriptionid = v_sub.genericsubscriptionid
                         AND g.billingperiodstart = v_next
                         AND g.status <> 'Cancelled') THEN
                v_skipped := v_skipped + 1;
            ELSE
                INSERT INTO genericsales
                    (farmid, saledate, genericcustomerid, salestype,
                     subtotalamount, discountamount, taxamount, totalamount,
                     amountpaid, balance, paymentstatus, status,
                     duedate, genericsubscriptionid, billingperiodstart, billingperiodend,
                     notes, createdby, createdat, isdeleted)
                VALUES
                    (p_farmid, v_next::timestamp, v_sub.genericcustomerid, 'SubscriptionInvoice',
                     v_sub.billingamount, v_sub.discountamount, v_sub.taxamount, v_total,
                     0, v_total, 'Unpaid', 'Draft',
                     (v_next + v_sub.paymentduedays)::date, v_sub.genericsubscriptionid,
                     v_next, v_periodend,
                     'Subscription ' || COALESCE(v_sub.subscriptionnumber, v_sub.genericsubscriptionid::text),
                     p_createdby, (now() at time zone 'utc'), FALSE)
                RETURNING genericsaleid INTO v_saleid;

                -- Post-insert numbering: the only race-free pattern in this
                -- codebase (216:291, 217:303).
                UPDATE genericsales
                SET    receiptnumber = 'INV-' || to_char(v_next, 'YYYY') || '-' || lpad(v_saleid::text, 4, '0')
                WHERE  genericsaleid = v_saleid;

                -- linetotal is GENERATED ALWAYS -- never insert it.
                INSERT INTO genericsaleitems
                    (genericsaleid, farmid, itemtype, genericserviceid, description,
                     quantity, unitprice, discountamount)
                VALUES
                    (v_saleid, p_farmid, 'Service', v_sub.genericserviceid,
                     to_char(v_next, 'DD Mon YYYY') || ' - ' || to_char(v_periodend, 'DD Mon YYYY'),
                     1, v_sub.billingamount, v_sub.discountamount);

                -- Auto-posting goes through the SAME function the Approve
                -- button calls, so the ledger write, the cash rules and the
                -- stock checks are the ones that already exist. It is
                -- idempotent and refuses anything not in Draft, so a re-run
                -- cannot double-post.
                IF v_autopost THEN
                    PERFORM spgenericsale_approve(
                        p_genericsaleid => v_saleid,
                        p_farmid        => p_farmid,
                        p_approvedby    => p_createdby);
                END IF;

                v_generated := v_generated + 1;
            END IF;

            v_next := fngenericnextbillingdate(v_next, v_sub.billingfrequency);
        END LOOP;

        UPDATE genericsubscriptions
        SET    lastbillingdate = CASE WHEN v_generated > 0 THEN v_asof ELSE lastbillingdate END,
               nextbillingdate = v_next,
               -- A subscription past its end date is finished, not silently idle.
               status = CASE WHEN enddate IS NOT NULL AND v_next IS NOT NULL AND v_next > enddate
                             THEN 'Expired' ELSE status END,
               updatedat = (now() at time zone 'utc')
        WHERE  genericsubscriptionid = v_sub.genericsubscriptionid;
    END LOOP;

    UPDATE genericbillingruns
    SET    totalsubscriptionschecked = v_checked,
           totalinvoicesgenerated    = v_generated,
           totalskipped              = v_skipped
    WHERE  genericbillingrunid = v_runid;

    RETURN v_runid;
END;
$function$;

COMMIT;

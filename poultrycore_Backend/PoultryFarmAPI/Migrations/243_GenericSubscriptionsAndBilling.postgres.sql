-- =============================================================================
-- 243_GenericSubscriptionsAndBilling.postgres.sql
--
-- Purpose
-- -------
-- Recurring billing for Generic companies: a customer is put on a plan, and the
-- owner presses a button to raise the invoices that have fallen due.
--
-- Invoices ARE sales
-- ------------------
-- genericsales is already an invoice header -- totalamount, amountpaid, balance,
-- paymentstatus, receiptnumber, line items with a persisted linetotal, and a
-- Draft -> Approved workflow. Four nullable columns turn it into a subscription
-- invoice as well. A separate invoice table would have duplicated the entry,
-- approval, cancellation, ledger and cash paths, and split revenue across two
-- tables so that every report and every customer balance had to union them.
--
-- Generated invoices are DRAFT
-- ----------------------------
-- A generic sale becomes a receivable when it is APPROVED (that is what writes
-- genericcustomerledger and moves genericcustomers.currentbalance). So a billing
-- run raises drafts and the owner approves them, exactly like a hand-entered
-- sale. Nothing is silently posted to a customer's account by a batch job.
--
-- Billing is a BUTTON, not a schedule
-- -----------------------------------
-- This codebase has no scheduler at all -- no AddHostedService, no Hangfire, no
-- Quartz, nothing in Program.cs. So billing is an explicit state machine in the
-- shape of the payroll run: preview, then generate. Making it automatic is a
-- hosting decision, not a SQL one.
--
-- Catch-up is deliberate. A subscription three months behind produces three
-- invoices, one per period, not one lump -- otherwise the billing period on the
-- invoice would be a lie and the customer statement would not reconcile.
--
-- EFFECT ON TODAY'S NUMBERS: none. Four nullable columns on genericsales, two
-- new tables, new functions. No existing row is read or written differently.
--
-- Order: 242, then 243, then 244.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. A sale can be a subscription invoice.
-- -----------------------------------------------------------------------------
ALTER TABLE genericsales ADD COLUMN IF NOT EXISTS duedate date NULL;
ALTER TABLE genericsales ADD COLUMN IF NOT EXISTS genericsubscriptionid integer NULL;
ALTER TABLE genericsales ADD COLUMN IF NOT EXISTS billingperiodstart date NULL;
ALTER TABLE genericsales ADD COLUMN IF NOT EXISTS billingperiodend date NULL;

COMMENT ON COLUMN genericsales.duedate IS
    'When payment is expected. NULL on a counter sale, which is due immediately. '
    'Stored rather than derived from the customer terms because a subscription '
    'carries its own paymentduedays that can differ from the party default.';
COMMENT ON COLUMN genericsales.genericsubscriptionid IS
    'Set when a billing run raised this invoice. NULL for a hand-entered sale.';

-- -----------------------------------------------------------------------------
-- 2. Subscriptions.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericsubscriptions (
    genericsubscriptionid serial PRIMARY KEY,
    farmid                varchar(450) NOT NULL,
    genericcustomerid     integer NOT NULL,
    -- The plan. A plan is a genericservices row with plantype/billingfrequency
    -- set (242), so a subscription points at the service catalogue.
    genericserviceid      integer NOT NULL,
    subscriptionnumber    text NULL,

    startdate             date NOT NULL,
    enddate               date NULL,
    billingfrequency      text NOT NULL,
    billingamount         numeric(14,2) NOT NULL CHECK (billingamount >= 0),
    discountamount        numeric(14,2) NOT NULL DEFAULT 0,
    taxamount             numeric(14,2) NOT NULL DEFAULT 0,

    nextbillingdate       date NULL,
    lastbillingdate       date NULL,
    paymentduedays        integer NOT NULL DEFAULT 0 CHECK (paymentduedays >= 0),
    autogenerateinvoice   boolean NOT NULL DEFAULT TRUE,

    defaultpaymentmethod  text NULL,
    defaultcashaccountid  integer NULL,

    status                text NOT NULL DEFAULT 'Draft',
    notes                 text NULL,

    createdby             text NULL,
    createdat             timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby             text NULL,
    updatedat             timestamp NULL,
    cancelledby           text NULL,
    cancelledat           timestamp NULL,
    cancellationreason    text NULL
);

CREATE INDEX IF NOT EXISTS ix_genericsubscriptions_farm_status
    ON genericsubscriptions (farmid, status);
CREATE INDEX IF NOT EXISTS ix_genericsubscriptions_farm_customer
    ON genericsubscriptions (farmid, genericcustomerid);
-- The billing run reads exactly this.
CREATE INDEX IF NOT EXISTS ix_genericsubscriptions_due
    ON genericsubscriptions (farmid, nextbillingdate)
    WHERE status = 'Active' AND autogenerateinvoice;
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericsubscriptions_number
    ON genericsubscriptions (farmid, subscriptionnumber)
    WHERE subscriptionnumber IS NOT NULL;

-- THE guard that makes a billing run safe to press twice. Without it a double
-- click bills the customer twice for the same month, and the second invoice
-- looks entirely legitimate.
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericsales_subscription_period
    ON genericsales (farmid, genericsubscriptionid, billingperiodstart, billingperiodend)
    WHERE genericsubscriptionid IS NOT NULL AND status <> 'Cancelled';

-- -----------------------------------------------------------------------------
-- 3. Billing runs.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericbillingruns (
    genericbillingrunid       serial PRIMARY KEY,
    farmid                    varchar(450) NOT NULL,
    billingrundate            timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    asofdate                  date NOT NULL,
    totalsubscriptionschecked integer NOT NULL DEFAULT 0,
    totalinvoicesgenerated    integer NOT NULL DEFAULT 0,
    totalskipped              integer NOT NULL DEFAULT 0,
    status                    text NOT NULL DEFAULT 'Completed',
    notes                     text NULL,
    createdby                 text NULL,
    createdat                 timestamp NOT NULL DEFAULT (now() at time zone 'utc')
);

CREATE INDEX IF NOT EXISTS ix_genericbillingruns_farm_date
    ON genericbillingruns (farmid, billingrundate DESC);

-- -----------------------------------------------------------------------------
-- 4. The schedule.
-- -----------------------------------------------------------------------------
-- Mirrored exactly by lib/generic/billing-schedule.ts on the frontend so the
-- date the form previews is the date the run will actually use. Postgres month
-- arithmetic clamps (31 Jan + 1 month = 28 Feb), which is the behaviour a
-- monthly subscription wants.
CREATE OR REPLACE FUNCTION public.fngenericnextbillingdate(p_from date, p_frequency text)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT CASE COALESCE(p_frequency, 'OneTime')
                WHEN 'Weekly'     THEN p_from + interval '7 days'
                WHEN 'Monthly'    THEN p_from + interval '1 month'
                WHEN 'Quarterly'  THEN p_from + interval '3 months'
                -- Three terms a year is the Ghanaian school calendar.
                WHEN 'Termly'     THEN p_from + interval '4 months'
                WHEN 'SemiAnnual' THEN p_from + interval '6 months'
                WHEN 'Annual'     THEN p_from + interval '1 year'
                ELSE NULL
           END::date;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Subscription reads and writes.
-- -----------------------------------------------------------------------------
-- A plan IS a genericservices row. The existing spgenericservice_* procs still
-- own creating and editing a service; these two only read and write the two
-- columns migration 242 added, so the Service Plans page can set a frequency
-- without this migration having to rewrite a live proc whose body is not in
-- this repo.
CREATE OR REPLACE FUNCTION public.spgenericserviceplan_getall(
    p_farmid text, p_activeonly boolean DEFAULT FALSE)
RETURNS TABLE(
    genericserviceid integer, farmid text, servicename text,
    genericservicecategoryid integer, categoryname text,
    defaultprice numeric, plantype text, billingfrequency text,
    notes text, isactive boolean,
    activesubscriptions integer, monthlyvalue numeric)
LANGUAGE sql
STABLE
AS $function$
    SELECT s.genericserviceid, s.farmid::text, s.servicename::text,
           s.genericservicecategoryid, c.name::text,
           s.defaultprice, s.plantype, s.billingfrequency,
           s.notes::text, s.isactive,
           (SELECT COUNT(*)::int FROM genericsubscriptions b
             WHERE b.genericserviceid = s.genericserviceid AND b.status = 'Active'),
           (SELECT COALESCE(SUM(b.billingamount - b.discountamount + b.taxamount), 0)::numeric(14,2)
              FROM genericsubscriptions b
             WHERE b.genericserviceid = s.genericserviceid AND b.status = 'Active')
    FROM   genericservices s
    LEFT   JOIN genericservicecategories c
           ON  c.genericservicecategoryid = s.genericservicecategoryid
    WHERE  s.farmid = p_farmid
      AND  COALESCE(s.isdeleted, FALSE) = FALSE
      AND  (NOT p_activeonly OR s.isactive)
    ORDER  BY s.servicename;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericserviceplan_setplan(
    p_genericserviceid  integer,
    p_farmid            text,
    p_plantype          text DEFAULT NULL::text,
    p_billingfrequency  text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_billingfrequency IS NOT NULL AND p_billingfrequency NOT IN
       ('Weekly', 'Monthly', 'Quarterly', 'Termly', 'SemiAnnual', 'Annual', 'OneTime') THEN
        RAISE EXCEPTION 'Unknown billing frequency "%".', p_billingfrequency;
    END IF;
    IF p_plantype IS NOT NULL AND p_plantype NOT IN ('Recurring', 'OneOff') THEN
        RAISE EXCEPTION 'Unknown plan type "%".', p_plantype;
    END IF;

    UPDATE genericservices
    SET    plantype         = p_plantype,
           billingfrequency = p_billingfrequency,
           updatedat        = (now() at time zone 'utc')
    WHERE  genericserviceid = p_genericserviceid
      AND  farmid = p_farmid
      AND  COALESCE(isdeleted, FALSE) = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Service not found for this company.';
    END IF;
    RETURN p_genericserviceid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericsubscription_getall(
    p_farmid text, p_status text DEFAULT NULL::text)
RETURNS TABLE(
    genericsubscriptionid integer, farmid text, genericcustomerid integer,
    customername text, genericserviceid integer, servicename text,
    subscriptionnumber text, startdate date, enddate date, billingfrequency text,
    billingamount numeric, discountamount numeric, taxamount numeric,
    totalbillingamount numeric, nextbillingdate date, lastbillingdate date,
    paymentduedays integer, autogenerateinvoice boolean, defaultpaymentmethod text,
    defaultcashaccountid integer, status text, notes text,
    openinvoicecount integer, openbalance numeric,
    createdby text, createdat timestamp without time zone)
LANGUAGE sql
STABLE
AS $function$
    SELECT s.genericsubscriptionid, s.farmid::text, s.genericcustomerid,
           c.customername::text, s.genericserviceid, sv.servicename::text,
           s.subscriptionnumber, s.startdate, s.enddate, s.billingfrequency,
           s.billingamount, s.discountamount, s.taxamount,
           (s.billingamount - s.discountamount + s.taxamount)::numeric(14,2),
           s.nextbillingdate, s.lastbillingdate, s.paymentduedays,
           s.autogenerateinvoice, s.defaultpaymentmethod, s.defaultcashaccountid,
           s.status, s.notes,
           COALESCE(i.cnt, 0)::integer, COALESCE(i.bal, 0)::numeric(14,2),
           s.createdby, s.createdat
    FROM   genericsubscriptions s
    LEFT   JOIN genericcustomers c ON c.genericcustomerid = s.genericcustomerid
    LEFT   JOIN genericservices sv ON sv.genericserviceid = s.genericserviceid
    LEFT   JOIN LATERAL (
        SELECT COUNT(*) AS cnt, SUM(g.balance) AS bal
        FROM   genericsales g
        WHERE  g.genericsubscriptionid = s.genericsubscriptionid
          AND  g.status = 'Approved' AND COALESCE(g.isdeleted, FALSE) = FALSE
          AND  g.balance > 0
    ) i ON TRUE
    WHERE  s.farmid = p_farmid
      AND  (p_status IS NULL OR s.status = p_status)
    ORDER  BY s.nextbillingdate NULLS LAST, s.genericsubscriptionid;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericsubscription_insert(
    p_farmid text,
    p_genericcustomerid integer,
    p_genericserviceid integer,
    p_startdate date,
    p_billingfrequency text,
    p_billingamount numeric,
    p_discountamount numeric DEFAULT 0,
    p_taxamount numeric DEFAULT 0,
    p_paymentduedays integer DEFAULT 0,
    p_autogenerateinvoice boolean DEFAULT TRUE,
    p_enddate date DEFAULT NULL::date,
    p_defaultpaymentmethod text DEFAULT NULL::text,
    p_defaultcashaccountid integer DEFAULT NULL::integer,
    p_notes text DEFAULT NULL::text,
    p_createdby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM genericcustomers c
                   WHERE c.genericcustomerid = p_genericcustomerid AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Customer does not belong to this company.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM genericservices s
                   WHERE s.genericserviceid = p_genericserviceid AND s.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Plan does not belong to this company.';
    END IF;
    IF COALESCE(p_billingamount, -1) < 0 THEN
        RAISE EXCEPTION 'Billing amount cannot be negative.';
    END IF;
    IF p_startdate IS NULL THEN
        RAISE EXCEPTION 'Start date is required.';
    END IF;
    IF p_enddate IS NOT NULL AND p_enddate < p_startdate THEN
        RAISE EXCEPTION 'End date cannot be before the start date.';
    END IF;
    IF p_defaultcashaccountid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM genericcashaccounts a
                       WHERE a.genericcashaccountid = p_defaultcashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
    END IF;

    INSERT INTO genericsubscriptions
        (farmid, genericcustomerid, genericserviceid, startdate, enddate,
         billingfrequency, billingamount, discountamount, taxamount,
         nextbillingdate, paymentduedays, autogenerateinvoice,
         defaultpaymentmethod, defaultcashaccountid, status, notes, createdby)
    VALUES
        (p_farmid, p_genericcustomerid, p_genericserviceid, p_startdate, p_enddate,
         p_billingfrequency, p_billingamount, COALESCE(p_discountamount, 0),
         COALESCE(p_taxamount, 0),
         -- First bill falls on the start date; nothing is back-dated.
         p_startdate, COALESCE(p_paymentduedays, 0), COALESCE(p_autogenerateinvoice, TRUE),
         p_defaultpaymentmethod, p_defaultcashaccountid, 'Draft', p_notes, p_createdby)
    RETURNING genericsubscriptionid INTO v_id;

    UPDATE genericsubscriptions
    SET    subscriptionnumber = 'SUB-' || to_char(p_startdate, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  genericsubscriptionid = v_id;

    RETURN v_id;
END;
$function$;

-- One function for every lifecycle move, so the legal transitions live in one
-- place instead of being re-decided by each caller.
CREATE OR REPLACE FUNCTION public.spgenericsubscription_setstatus(
    p_genericsubscriptionid integer,
    p_farmid text,
    p_status text,
    p_by text DEFAULT NULL::text,
    p_reason text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_current text;
    v_next    date;
BEGIN
    SELECT s.status, s.nextbillingdate INTO v_current, v_next
    FROM   genericsubscriptions s
    WHERE  s.genericsubscriptionid = p_genericsubscriptionid AND s.farmid = p_farmid;

    IF v_current IS NULL THEN
        RAISE EXCEPTION 'Subscription not found for this company.';
    END IF;
    IF p_status NOT IN ('Draft','Active','Paused','Suspended','Cancelled','Expired') THEN
        RAISE EXCEPTION 'Unknown subscription status "%".', p_status;
    END IF;
    IF v_current = 'Cancelled' THEN
        RAISE EXCEPTION 'A cancelled subscription cannot be changed.';
    END IF;
    IF p_status = 'Cancelled' AND COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to cancel a subscription.';
    END IF;

    UPDATE genericsubscriptions
    SET    status = p_status,
           -- Resuming a paused subscription must not bill for the months it was
           -- paused: billing restarts from today, not from where it left off.
           nextbillingdate = CASE
               WHEN p_status = 'Active' AND v_current IN ('Paused','Suspended')
                    AND (v_next IS NULL OR v_next < CURRENT_DATE)
               THEN CURRENT_DATE ELSE nextbillingdate END,
           cancelledby        = CASE WHEN p_status = 'Cancelled' THEN p_by ELSE cancelledby END,
           cancelledat        = CASE WHEN p_status = 'Cancelled'
                                     THEN (now() at time zone 'utc') ELSE cancelledat END,
           cancellationreason = CASE WHEN p_status = 'Cancelled' THEN p_reason ELSE cancellationreason END,
           updatedby = p_by,
           updatedat = (now() at time zone 'utc')
    WHERE  genericsubscriptionid = p_genericsubscriptionid AND farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. The billing run.
-- -----------------------------------------------------------------------------
-- Preview and generate share the same selection so the owner cannot be shown one
-- set and charged another. Preview is STABLE and writes nothing.
CREATE OR REPLACE FUNCTION public.spgenericbillingrun_preview(
    p_farmid text, p_asof date DEFAULT NULL::date)
RETURNS TABLE(
    genericsubscriptionid integer, subscriptionnumber text, genericcustomerid integer,
    customername text, servicename text, billingfrequency text,
    billingperiodstart date, billingperiodend date, duedate date,
    invoiceamount numeric, alreadybilled boolean)
LANGUAGE sql
STABLE
AS $function$
    WITH asof AS (SELECT COALESCE(p_asof, CURRENT_DATE) AS d),
    due AS (
        SELECT s.*, (SELECT d FROM asof) AS asofdate
        FROM   genericsubscriptions s
        WHERE  s.farmid = p_farmid
          AND  s.status = 'Active'
          AND  s.autogenerateinvoice
          AND  s.nextbillingdate IS NOT NULL
          AND  s.nextbillingdate <= (SELECT d FROM asof)
          AND  (s.enddate IS NULL OR s.nextbillingdate <= s.enddate)
    )
    SELECT d.genericsubscriptionid, d.subscriptionnumber, d.genericcustomerid,
           c.customername::text, sv.servicename::text, d.billingfrequency,
           d.nextbillingdate,
           (COALESCE(fngenericnextbillingdate(d.nextbillingdate, d.billingfrequency),
                     d.nextbillingdate + 1) - 1)::date,
           (d.nextbillingdate + d.paymentduedays)::date,
           (d.billingamount - d.discountamount + d.taxamount)::numeric(14,2),
           EXISTS (SELECT 1 FROM genericsales g
                   WHERE g.genericsubscriptionid = d.genericsubscriptionid
                     AND g.billingperiodstart = d.nextbillingdate
                     AND g.status <> 'Cancelled')
    FROM   due d
    LEFT   JOIN genericcustomers c ON c.genericcustomerid = d.genericcustomerid
    LEFT   JOIN genericservices sv ON sv.genericserviceid = d.genericserviceid
    ORDER  BY d.nextbillingdate, d.genericsubscriptionid;
$function$;

-- Generates every period a subscription is behind, one invoice each, and stops
-- at the as-of date. Invoices are DRAFT: approving them is what makes them a
-- receivable, and that stays a human decision.
CREATE OR REPLACE FUNCTION public.spgenericbillingrun_generate(
    p_farmid text,
    p_asof date DEFAULT NULL::date,
    p_createdby text DEFAULT NULL::text)
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
BEGIN
    INSERT INTO genericbillingruns (farmid, asofdate, status, createdby)
    VALUES (p_farmid, v_asof, 'Completed', p_createdby)
    RETURNING genericbillingrunid INTO v_runid;

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

-- The Invoices page: the same genericsales rows the Sales page shows, read
-- through an invoice-shaped lens. Its own function because the live
-- spgenericsale_getall selects a fixed column list -- it is machine-converted
-- T-SQL whose body is not in this repo -- and would silently keep omitting the
-- four columns section 1 just added.
--
-- p_subscriptiononly narrows to invoices a billing run raised; the default
-- shows counter sales too, because to a service business every approved sale
-- with a balance is a bill somebody owes.
CREATE OR REPLACE FUNCTION public.spgenericinvoice_getall(
    p_farmid            text,
    p_status            text DEFAULT NULL::text,
    p_subscriptiononly  boolean DEFAULT FALSE,
    p_from              date DEFAULT NULL::date,
    p_to                date DEFAULT NULL::date)
RETURNS TABLE(
    genericsaleid         integer,
    receiptnumber         text,
    saledate              timestamp without time zone,
    duedate               date,
    genericcustomerid     integer,
    customername          text,
    genericsubscriptionid integer,
    subscriptionnumber    text,
    billingperiodstart    date,
    billingperiodend      date,
    totalamount           numeric,
    amountpaid            numeric,
    balance               numeric,
    paymentstatus         text,
    status                text,
    isoverdue             boolean,
    agedays               integer,
    notes                 text,
    createdat             timestamp without time zone)
LANGUAGE sql
STABLE
AS $function$
    SELECT s.genericsaleid, s.receiptnumber::text, s.saledate, s.duedate,
           s.genericcustomerid, c.customername::text,
           s.genericsubscriptionid, b.subscriptionnumber,
           s.billingperiodstart, s.billingperiodend,
           s.totalamount, s.amountpaid, s.balance,
           s.paymentstatus::text, s.status::text,
           -- Only an APPROVED invoice with a balance can be overdue. A draft is
           -- not owed by anybody yet, however old it is.
           (s.status = 'Approved' AND s.balance > 0
            AND s.duedate IS NOT NULL AND s.duedate < CURRENT_DATE),
           GREATEST(0, (CURRENT_DATE - s.saledate::date))::int,
           s.notes::text, s.createdat
    FROM   genericsales s
    LEFT   JOIN genericcustomers c ON c.genericcustomerid = s.genericcustomerid
    LEFT   JOIN genericsubscriptions b ON b.genericsubscriptionid = s.genericsubscriptionid
    WHERE  s.farmid = p_farmid
      AND  COALESCE(s.isdeleted, FALSE) = FALSE
      AND  (p_status IS NULL OR p_status = 'All' OR s.status = p_status)
      AND  (NOT p_subscriptiononly OR s.genericsubscriptionid IS NOT NULL)
      AND  (p_from IS NULL OR s.saledate::date >= p_from)
      AND  (p_to   IS NULL OR s.saledate::date <= p_to)
    ORDER  BY s.saledate DESC, s.genericsaleid DESC;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericbillingrun_getall(p_farmid text)
RETURNS TABLE(
    genericbillingrunid integer, billingrundate timestamp without time zone, asofdate date,
    totalsubscriptionschecked integer, totalinvoicesgenerated integer,
    totalskipped integer, status text, notes text, createdby text)
LANGUAGE sql
STABLE
AS $function$
    SELECT r.genericbillingrunid, r.billingrundate, r.asofdate,
           r.totalsubscriptionschecked, r.totalinvoicesgenerated,
           r.totalskipped, r.status, r.notes, r.createdby
    FROM   genericbillingruns r
    WHERE  r.farmid = p_farmid
    ORDER  BY r.billingrundate DESC;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 7. Verification.
-- -----------------------------------------------------------------------------
SELECT 'tables' AS check,
       CASE WHEN to_regclass('public.genericsubscriptions') IS NOT NULL
             AND to_regclass('public.genericbillingruns') IS NOT NULL
            THEN 'OK' ELSE 'MISSING' END AS result;

SELECT 'functions' AS check,
       CASE WHEN COUNT(*) = 10 THEN 'OK' ELSE 'ONLY ' || COUNT(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('fngenericnextbillingdate', 'spgenericsubscription_getall',
                     'spgenericsubscription_insert', 'spgenericsubscription_setstatus',
                     'spgenericserviceplan_getall', 'spgenericserviceplan_setplan',
                     'spgenericbillingrun_preview', 'spgenericbillingrun_generate',
                     'spgenericbillingrun_getall', 'spgenericinvoice_getall');

-- The schedule, spelled out. Every row must say OK.
SELECT 'schedule' AS check, freq, expected::text, fngenericnextbillingdate('2026-01-31', freq)::text,
       CASE WHEN fngenericnextbillingdate('2026-01-31', freq) IS NOT DISTINCT FROM expected
            THEN 'OK' ELSE 'WRONG' END AS result
FROM (VALUES
    ('Weekly',     '2026-02-07'::date),
    ('Monthly',    '2026-02-28'::date),   -- clamps, which is what a monthly plan wants
    ('Quarterly',  '2026-04-30'::date),
    ('Termly',     '2026-05-31'::date),
    ('SemiAnnual', '2026-07-31'::date),
    ('Annual',     '2027-01-31'::date),
    ('OneTime',    NULL::date)
) AS t(freq, expected);

-- No existing sale may have picked up subscription columns. Expect NO ROWS.
SELECT genericsaleid, genericsubscriptionid, billingperiodstart
FROM   genericsales
WHERE  genericsubscriptionid IS NOT NULL OR billingperiodstart IS NOT NULL;

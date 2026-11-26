-- Migration 499 — Subscription enhancements: trial periods, upgrade/downgrade,
-- late fees, and coupon/discount codes.
--
-- Four features, one migration:
--   1. Trial Periods — trialdays column on subscriptions, skip billing during trial
--   2. Upgrade/Downgrade — change plan mid-cycle with proration
--   3. Late Fees — settings + tracking on overdue invoices
--   4. Coupon Codes — promo code table, apply to subscriptions

-- =========================================================================
-- 1. TRIAL PERIODS
-- =========================================================================

-- Add trial columns to subscriptions
ALTER TABLE genericsubscriptions ADD COLUMN IF NOT EXISTS trialdays integer NOT NULL DEFAULT 0;
ALTER TABLE genericsubscriptions ADD COLUMN IF NOT EXISTS trialenddate date NULL;

-- =========================================================================
-- 2. UPGRADE / DOWNGRADE
-- =========================================================================

-- Track plan changes for audit
CREATE TABLE IF NOT EXISTS genericsubscriptionplanchanges (
    genericsubscriptionplanchangeid serial PRIMARY KEY,
    farmid              text        NOT NULL,
    genericsubscriptionid integer   NOT NULL REFERENCES genericsubscriptions (genericsubscriptionid),
    -- Old plan
    oldserviceid        integer     NOT NULL,
    oldservicename      text        NULL,
    oldbillingamount    numeric(14,2) NOT NULL,
    -- New plan
    newserviceid        integer     NOT NULL,
    newservicename      text        NULL,
    newbillingamount    numeric(14,2) NOT NULL,
    -- Proration
    changetype          text        NOT NULL CHECK (changetype IN ('Upgrade', 'Downgrade', 'PlanChange')),
    proratedcredit      numeric(14,2) NOT NULL DEFAULT 0,
    proratedcharge      numeric(14,2) NOT NULL DEFAULT 0,
    effectivedate       date        NOT NULL,
    reason              text        NULL,
    changedby           text        NULL,
    changedat           timestamp   NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE INDEX IF NOT EXISTS ix_subscriptionplanchanges_sub
    ON genericsubscriptionplanchanges (genericsubscriptionid);

-- SP to change a subscription's plan
CREATE OR REPLACE FUNCTION public.spgenericsubscription_changeplan(
    p_farmid            text,
    p_subscriptionid    integer,
    p_newserviceid      integer,
    p_newbillingamount  numeric,
    p_effectivedate     date        DEFAULT NULL,
    p_reason            text        DEFAULT NULL,
    p_changedby         text        DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_sub           record;
    v_oldservice    text;
    v_newservice    text;
    v_effectivedate date := COALESCE(p_effectivedate, CURRENT_DATE);
    v_daysused      integer;
    v_daysintotal   integer;
    v_periodend     date;
    v_credit        numeric(14,2) := 0;
    v_charge        numeric(14,2) := 0;
    v_changetype    text;
    v_changeid      integer;
BEGIN
    -- 1. Load subscription
    SELECT * INTO v_sub FROM genericsubscriptions
    WHERE genericsubscriptionid = p_subscriptionid AND farmid = p_farmid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Subscription not found.';
    END IF;
    IF v_sub.status NOT IN ('Active', 'Paused') THEN
        RAISE EXCEPTION 'Can only change plan on Active or Paused subscriptions (current: %).', v_sub.status;
    END IF;
    IF v_sub.genericserviceid = p_newserviceid AND v_sub.billingamount = p_newbillingamount THEN
        RAISE EXCEPTION 'The subscription is already on this plan at this amount.';
    END IF;

    -- 2. Get service names
    SELECT servicename INTO v_oldservice FROM genericservices WHERE genericserviceid = v_sub.genericserviceid;
    SELECT servicename INTO v_newservice FROM genericservices WHERE genericserviceid = p_newserviceid;

    -- 3. Calculate proration (credit for unused old plan, charge for new plan remainder)
    IF v_sub.lastbillingdate IS NOT NULL AND v_sub.nextbillingdate IS NOT NULL THEN
        v_periodend := v_sub.nextbillingdate;
        v_daysintotal := v_periodend - v_sub.lastbillingdate;
        v_daysused := v_effectivedate - v_sub.lastbillingdate;

        IF v_daysintotal > 0 AND v_daysused >= 0 AND v_daysused < v_daysintotal THEN
            -- Credit: unused portion of old billing amount
            v_credit := ROUND(((v_sub.billingamount - v_sub.discountamount + v_sub.taxamount)
                        * (v_daysintotal - v_daysused)::numeric / v_daysintotal), 2);
            -- Charge: remaining portion at new rate
            v_charge := ROUND((p_newbillingamount
                        * (v_daysintotal - v_daysused)::numeric / v_daysintotal), 2);
        END IF;
    END IF;

    -- 4. Determine change type
    v_changetype := CASE
        WHEN p_newbillingamount > v_sub.billingamount THEN 'Upgrade'
        WHEN p_newbillingamount < v_sub.billingamount THEN 'Downgrade'
        ELSE 'PlanChange'
    END;

    -- 5. Record the plan change
    INSERT INTO genericsubscriptionplanchanges (
        farmid, genericsubscriptionid,
        oldserviceid, oldservicename, oldbillingamount,
        newserviceid, newservicename, newbillingamount,
        changetype, proratedcredit, proratedcharge,
        effectivedate, reason, changedby)
    VALUES (
        p_farmid, p_subscriptionid,
        v_sub.genericserviceid, v_oldservice, v_sub.billingamount,
        p_newserviceid, v_newservice, p_newbillingamount,
        v_changetype, v_credit, v_charge,
        v_effectivedate, p_reason, p_changedby)
    RETURNING genericsubscriptionplanchangeid INTO v_changeid;

    -- 6. Update the subscription
    UPDATE genericsubscriptions
    SET    genericserviceid = p_newserviceid,
           billingamount    = p_newbillingamount,
           updatedby        = p_changedby,
           updatedat        = now() AT TIME ZONE 'utc'
    WHERE  genericsubscriptionid = p_subscriptionid;

    RETURN v_changeid;
END;
$function$;

-- =========================================================================
-- 3. LATE FEES
-- =========================================================================

-- Late fee settings on the business settings table
ALTER TABLE genericbusinesssettings ADD COLUMN IF NOT EXISTS latefeeenabled boolean NOT NULL DEFAULT FALSE;
ALTER TABLE genericbusinesssettings ADD COLUMN IF NOT EXISTS latefeetype text NOT NULL DEFAULT 'Flat' CHECK (latefeetype IN ('Flat', 'Percentage'));
ALTER TABLE genericbusinesssettings ADD COLUMN IF NOT EXISTS latefeeamount numeric(14,2) NOT NULL DEFAULT 0;
ALTER TABLE genericbusinesssettings ADD COLUMN IF NOT EXISTS latefeegracedays integer NOT NULL DEFAULT 0;
ALTER TABLE genericbusinesssettings ADD COLUMN IF NOT EXISTS latefeemax numeric(14,2) NULL;

-- Track late fees applied to sales/invoices
CREATE TABLE IF NOT EXISTS genericlatefees (
    genericlatefeeid    serial      PRIMARY KEY,
    farmid              text        NOT NULL,
    genericsaleid       integer     NOT NULL,
    feeamount           numeric(14,2) NOT NULL,
    feetype             text        NOT NULL,
    applieddate         date        NOT NULL DEFAULT CURRENT_DATE,
    daysoverdue         integer     NOT NULL DEFAULT 0,
    notes               text        NULL,
    status              text        NOT NULL DEFAULT 'Applied' CHECK (status IN ('Applied', 'Waived')),
    waivedby            text        NULL,
    waivedat            timestamp   NULL,
    waivereason         text        NULL,
    createdby           text        NULL,
    createdat           timestamp   NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE INDEX IF NOT EXISTS ix_genericlatefees_sale
    ON genericlatefees (genericsaleid);

-- SP to calculate and apply late fees to overdue invoices
CREATE OR REPLACE FUNCTION public.spgenericlatefee_apply(
    p_farmid    text,
    p_createdby text DEFAULT NULL)
RETURNS TABLE(genericsaleid integer, feeamount numeric, daysoverdue integer)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_settings  record;
    v_sale      record;
    v_fee       numeric(14,2);
    v_days      integer;
BEGIN
    -- Load settings
    SELECT latefeeenabled, latefeetype, latefeeamount, latefeegracedays, latefeemax
    INTO   v_settings
    FROM   genericbusinesssettings
    WHERE  farmid = p_farmid;

    IF NOT FOUND OR NOT v_settings.latefeeenabled OR v_settings.latefeeamount <= 0 THEN
        RETURN;
    END IF;

    -- Find overdue invoices past grace period that don't already have a fee today
    FOR v_sale IN
        SELECT s.genericsaleid, s.totalamount, s.balance, s.duedate
        FROM   genericsales s
        WHERE  s.farmid = p_farmid
        AND    s.status IN ('Approved', 'Posted')
        AND    s.balance > 0
        AND    s.duedate IS NOT NULL
        AND    s.duedate < CURRENT_DATE - v_settings.latefeegracedays
        AND    NOT EXISTS (
            SELECT 1 FROM genericlatefees f
            WHERE f.genericsaleid = s.genericsaleid
            AND   f.applieddate = CURRENT_DATE
            AND   f.status = 'Applied')
        ORDER BY s.duedate
    LOOP
        v_days := CURRENT_DATE - v_sale.duedate;

        -- Calculate fee
        IF v_settings.latefeetype = 'Percentage' THEN
            v_fee := ROUND(v_sale.totalamount * v_settings.latefeeamount / 100, 2);
        ELSE
            v_fee := v_settings.latefeeamount;
        END IF;

        -- Cap at max if set
        IF v_settings.latefeemax IS NOT NULL AND v_fee > v_settings.latefeemax THEN
            v_fee := v_settings.latefeemax;
        END IF;

        IF v_fee > 0 THEN
            INSERT INTO genericlatefees (farmid, genericsaleid, feeamount, feetype, daysoverdue, createdby)
            VALUES (p_farmid, v_sale.genericsaleid, v_fee, v_settings.latefeetype, v_days, p_createdby);

            genericsaleid := v_sale.genericsaleid;
            feeamount := v_fee;
            daysoverdue := v_days;
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$function$;

-- SP to waive a late fee
CREATE OR REPLACE FUNCTION public.spgenericlatefee_waive(
    p_farmid    text,
    p_feeid     integer,
    p_reason    text,
    p_waivedby  text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF COALESCE(BTRIM(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to waive a late fee.';
    END IF;

    UPDATE genericlatefees
    SET    status = 'Waived',
           waivedby = p_waivedby,
           waivedat = now() AT TIME ZONE 'utc',
           waivereason = p_reason
    WHERE  genericlatefeeid = p_feeid
    AND    farmid = p_farmid
    AND    status = 'Applied';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Late fee not found or already waived.';
    END IF;
END;
$function$;

-- SP to get late fees for a sale
CREATE OR REPLACE FUNCTION public.spgenericlatefee_getbysale(
    p_farmid    text,
    p_saleid    integer)
RETURNS TABLE(
    genericlatefeeid integer, feeamount numeric, feetype text,
    applieddate date, daysoverdue integer, status text,
    waivedby text, waivereason text, notes text)
LANGUAGE sql
STABLE
AS $function$
    SELECT genericlatefeeid, feeamount, feetype, applieddate, daysoverdue,
           status, waivedby, waivereason, notes
    FROM   genericlatefees
    WHERE  farmid = p_farmid AND genericsaleid = p_saleid
    ORDER  BY applieddate DESC;
$function$;

-- =========================================================================
-- 4. COUPON / DISCOUNT CODES
-- =========================================================================

CREATE TABLE IF NOT EXISTS genericcoupons (
    genericcouponid     serial      PRIMARY KEY,
    farmid              text        NOT NULL,
    code                text        NOT NULL,
    description         text        NULL,
    discounttype        text        NOT NULL CHECK (discounttype IN ('Flat', 'Percentage')),
    discountvalue       numeric(14,2) NOT NULL CHECK (discountvalue > 0),
    -- Limits
    maxuses             integer     NULL,
    usedcount           integer     NOT NULL DEFAULT 0,
    maxusespercustomer  integer     NULL,
    -- Validity
    validfrom           date        NULL,
    validuntil          date        NULL,
    -- Which plans it applies to (NULL = all plans)
    applicableserviceid integer     NULL,
    -- State
    isactive            boolean     NOT NULL DEFAULT TRUE,
    createdby           text        NULL,
    createdat           timestamp   NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_genericcoupons_code
    ON genericcoupons (farmid, UPPER(code)) WHERE isactive;

-- Track coupon usage
CREATE TABLE IF NOT EXISTS genericcouponusages (
    genericcouponusageid serial     PRIMARY KEY,
    farmid              text        NOT NULL,
    genericcouponid     integer     NOT NULL REFERENCES genericcoupons (genericcouponid),
    genericsubscriptionid integer  NULL,
    genericcustomerid   integer     NULL,
    discountapplied     numeric(14,2) NOT NULL,
    usedat              timestamp   NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE INDEX IF NOT EXISTS ix_genericcouponusages_coupon
    ON genericcouponusages (genericcouponid);

-- Link coupon to subscription
ALTER TABLE genericsubscriptions ADD COLUMN IF NOT EXISTS genericcouponid integer NULL;

-- SP: validate and apply a coupon code
CREATE OR REPLACE FUNCTION public.spgenericcoupon_validate(
    p_farmid        text,
    p_code          text,
    p_customerid    integer DEFAULT NULL,
    p_serviceid     integer DEFAULT NULL,
    p_billingamount numeric DEFAULT NULL)
RETURNS TABLE(
    genericcouponid integer, code text, discounttype text, discountvalue numeric,
    calculatediscount numeric, description text, valid boolean, reason text)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_coupon    record;
    v_discount  numeric(14,2);
    v_custuses  integer;
BEGIN
    SELECT * INTO v_coupon
    FROM   genericcoupons c
    WHERE  c.farmid = p_farmid
    AND    UPPER(c.code) = UPPER(BTRIM(p_code))
    AND    c.isactive;

    IF NOT FOUND THEN
        genericcouponid := NULL; code := p_code; valid := FALSE;
        reason := 'Coupon code not found or inactive.';
        RETURN NEXT; RETURN;
    END IF;

    -- Check date validity
    IF v_coupon.validfrom IS NOT NULL AND CURRENT_DATE < v_coupon.validfrom THEN
        genericcouponid := v_coupon.genericcouponid; code := v_coupon.code; valid := FALSE;
        reason := 'Coupon is not yet active (starts ' || v_coupon.validfrom || ').';
        RETURN NEXT; RETURN;
    END IF;
    IF v_coupon.validuntil IS NOT NULL AND CURRENT_DATE > v_coupon.validuntil THEN
        genericcouponid := v_coupon.genericcouponid; code := v_coupon.code; valid := FALSE;
        reason := 'Coupon has expired.';
        RETURN NEXT; RETURN;
    END IF;

    -- Check max uses
    IF v_coupon.maxuses IS NOT NULL AND v_coupon.usedcount >= v_coupon.maxuses THEN
        genericcouponid := v_coupon.genericcouponid; code := v_coupon.code; valid := FALSE;
        reason := 'Coupon has reached its usage limit.';
        RETURN NEXT; RETURN;
    END IF;

    -- Check per-customer limit
    IF v_coupon.maxusespercustomer IS NOT NULL AND p_customerid IS NOT NULL THEN
        SELECT COUNT(*) INTO v_custuses
        FROM   genericcouponusages u
        WHERE  u.genericcouponid = v_coupon.genericcouponid
        AND    u.genericcustomerid = p_customerid;
        IF v_custuses >= v_coupon.maxusespercustomer THEN
            genericcouponid := v_coupon.genericcouponid; code := v_coupon.code; valid := FALSE;
            reason := 'This customer has already used this coupon.';
            RETURN NEXT; RETURN;
        END IF;
    END IF;

    -- Check applicable service
    IF v_coupon.applicableserviceid IS NOT NULL AND p_serviceid IS NOT NULL
       AND v_coupon.applicableserviceid <> p_serviceid THEN
        genericcouponid := v_coupon.genericcouponid; code := v_coupon.code; valid := FALSE;
        reason := 'Coupon is not valid for this plan.';
        RETURN NEXT; RETURN;
    END IF;

    -- Calculate discount
    IF v_coupon.discounttype = 'Percentage' THEN
        v_discount := ROUND(COALESCE(p_billingamount, 0) * v_coupon.discountvalue / 100, 2);
    ELSE
        v_discount := v_coupon.discountvalue;
    END IF;

    -- Don't exceed billing amount
    IF p_billingamount IS NOT NULL AND v_discount > p_billingamount THEN
        v_discount := p_billingamount;
    END IF;

    genericcouponid := v_coupon.genericcouponid; code := v_coupon.code;
    discounttype := v_coupon.discounttype; discountvalue := v_coupon.discountvalue;
    calculatediscount := v_discount; description := v_coupon.description;
    valid := TRUE; reason := NULL;
    RETURN NEXT;
END;
$function$;

-- SP: record coupon usage (called when subscription is created with a coupon)
CREATE OR REPLACE FUNCTION public.spgenericcoupon_use(
    p_farmid            text,
    p_couponid          integer,
    p_subscriptionid    integer DEFAULT NULL,
    p_customerid        integer DEFAULT NULL,
    p_discountapplied   numeric DEFAULT 0)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO genericcouponusages (farmid, genericcouponid, genericsubscriptionid, genericcustomerid, discountapplied)
    VALUES (p_farmid, p_couponid, p_subscriptionid, p_customerid, p_discountapplied);

    UPDATE genericcoupons
    SET    usedcount = usedcount + 1
    WHERE  genericcouponid = p_couponid;
END;
$function$;

-- CRUD SPs for coupons
CREATE OR REPLACE FUNCTION public.spgenericcoupon_create(
    p_farmid            text,
    p_code              text,
    p_description       text        DEFAULT NULL,
    p_discounttype      text        DEFAULT 'Flat',
    p_discountvalue     numeric     DEFAULT 0,
    p_maxuses           integer     DEFAULT NULL,
    p_maxusespercustomer integer    DEFAULT NULL,
    p_validfrom         date        DEFAULT NULL,
    p_validuntil        date        DEFAULT NULL,
    p_applicableserviceid integer   DEFAULT NULL,
    p_createdby         text        DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE v_id integer;
BEGIN
    IF COALESCE(BTRIM(p_code), '') = '' THEN
        RAISE EXCEPTION 'Coupon code is required.';
    END IF;
    IF p_discountvalue <= 0 THEN
        RAISE EXCEPTION 'Discount value must be greater than 0.';
    END IF;

    INSERT INTO genericcoupons (
        farmid, code, description, discounttype, discountvalue,
        maxuses, maxusespercustomer, validfrom, validuntil,
        applicableserviceid, createdby)
    VALUES (
        p_farmid, BTRIM(p_code), p_description, p_discounttype, p_discountvalue,
        p_maxuses, p_maxusespercustomer, p_validfrom, p_validuntil,
        p_applicableserviceid, p_createdby)
    RETURNING genericcouponid INTO v_id;

    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericcoupon_getall(
    p_farmid    text,
    p_activeonly boolean DEFAULT FALSE)
RETURNS TABLE(
    genericcouponid integer, code text, description text,
    discounttype text, discountvalue numeric,
    maxuses integer, usedcount integer, maxusespercustomer integer,
    validfrom date, validuntil date,
    applicableserviceid integer, servicename text,
    isactive boolean, createdat timestamp)
LANGUAGE sql
STABLE
AS $function$
    SELECT c.genericcouponid, c.code, c.description,
           c.discounttype, c.discountvalue,
           c.maxuses, c.usedcount, c.maxusespercustomer,
           c.validfrom, c.validuntil,
           c.applicableserviceid,
           s.servicename::text,
           c.isactive, c.createdat
    FROM   genericcoupons c
    LEFT   JOIN genericservices s ON s.genericserviceid = c.applicableserviceid
    WHERE  c.farmid = p_farmid
    AND    (NOT p_activeonly OR c.isactive)
    ORDER  BY c.createdat DESC;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericcoupon_deactivate(
    p_farmid    text,
    p_couponid  integer)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE genericcoupons SET isactive = FALSE
    WHERE genericcouponid = p_couponid AND farmid = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Coupon not found.'; END IF;
END;
$function$;

-- =========================================================================
-- Update billing preview/generate to skip trial period subscriptions
-- =========================================================================

-- Patch the preview to exclude subscriptions still in trial
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
          -- Skip subscriptions still in trial period
          AND  (s.trialenddate IS NULL OR s.trialenddate < (SELECT d FROM asof))
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

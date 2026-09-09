-- =============================================================================
-- 284_WaterAssetDepreciation.postgres.sql
--
-- Purpose
-- -------
-- The water mirror of 271. Phase 3, part 3: charge an asset to Profit & Loss a
-- month at a time, and move no money at all while doing it.
--
-- DEPRECIATION IS THE ONE EXPENSE WITH NO PAYMENT
-- ===============================================
-- It increases the P&L cost of the period, it reduces the asset's book value,
-- and it touches NOTHING else: no cash transaction, no cash account, no
-- supplier, no payable, no payment. That is the whole definition, and every
-- guard in this file exists to keep it true.
--
-- The mechanism is the one water already established for internal usage: a
-- `waterexpenses` row with paymentmethod 'NonCash'. 240 reads that marker
-- directly -- `WHEN sourcetype = 'WaterInternalUsage' THEN 'NonCash'` -- and the
-- cash-flow arms skip it, payables skip it, and the P&L counts it. Depreciation
-- needs exactly that, so it uses exactly that rather than a fourth way of saying
-- the same thing.
--
-- Two structural guarantees come free from 283 and cost nothing to restate:
-- the row carries no supplierid, and fnwaterpayables requires one -- so a
-- depreciation charge can never appear as a debt. And it carries no
-- watercashaccountid, so nothing here can move an account balance.
--
-- THE CONVENTION, STATED ONCE
-- ===========================
-- Depreciation is charged for the WHOLE month containing the in-service date,
-- and for every whole month after it. No proration.
--
-- A machine commissioned on the 28th is charged a full month for that month.
-- That is a deliberate simplification: it is consistent, it is explainable to an
-- owner in one sentence, and the alternative -- half-month conventions, day
-- counts, tax tables -- is the accounting software this system is explicitly not
-- trying to become.
--
-- WHY THE LAST MONTH IS SPECIAL
-- =============================
-- (cost - residual) / life rounds to the cedi, and twelve rounded months do not
-- necessarily add up to the year. So the final charge is whatever is LEFT rather
-- than the monthly figure, and accumulated depreciation lands on the depreciable
-- amount exactly. Without that an asset would sit at 3 pesewas of book value
-- above its residual for ever, and FullyDepreciated would never fire.
--
-- REVERSAL IS APPEND-ONLY
-- =======================
-- A reversed charge is KEPT and marked; an opposite row is written beside it,
-- and an opposite expense beside that. Accumulated depreciation is a signed SUM
-- (283), so it falls out correctly with no row ever being edited into a lie.
--
-- Order: after 283.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. The category depreciation is filed under.
--
-- Inline and idempotent, as 227 and 283 both do it: no dependency on another
-- function's Postgres parameter naming.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwaterdepreciationcategory(p_farmid text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_catid integer;
BEGIN
    SELECT ec.waterexpensecategoryid INTO v_catid
    FROM   waterexpensecategories ec
    WHERE  ec.farmid = p_farmid
      AND  lower(ec.name) = 'depreciation'
      AND  COALESCE(ec.isdeleted, FALSE) = FALSE
    LIMIT  1;

    IF v_catid IS NULL THEN
        INSERT INTO waterexpensecategories (farmid, name, isactive, isdeleted)
        VALUES (p_farmid, 'Depreciation', TRUE, FALSE)
        RETURNING waterexpensecategoryid INTO v_catid;
    END IF;

    RETURN v_catid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 1. Post one month's charge for one asset.
--
-- Internal: the generator below drives it. Separate because it is also what a
-- catch-up or a one-off adjustment needs, and having one writer means the
-- expense row, the ledger row and the link between them cannot drift.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterassetdepreciation_post(
    p_farmid      text,
    p_assetid     integer,
    p_periodstart date,
    p_amount      numeric,
    p_sourcetype  text DEFAULT 'Scheduled',
    p_createdby   text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id     integer;
    v_expid  integer;
    v_catid  integer;
    v_end    date := (date_trunc('month', p_periodstart) + interval '1 month - 1 day')::date;
    v_name   text;
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN
        RETURN NULL;                    -- nothing to charge is not an error
    END IF;

    SELECT a.assetname INTO v_name
    FROM   watercapitalassets a
    WHERE  a.watercapitalassetid = p_assetid AND a.farmid = p_farmid;
    IF v_name IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;

    INSERT INTO waterassetdepreciation
        (farmid, watercapitalassetid, periodstart, periodend, depreciationdate,
         amount, depreciationmethod, sourcetype, status, createdby)
    VALUES
        (p_farmid, p_assetid, date_trunc('month', p_periodstart)::date, v_end, v_end,
         p_amount, 'StraightLine', p_sourcetype, 'Posted', p_createdby)
    RETURNING waterassetdepreciationid INTO v_id;

    v_catid := fnwaterdepreciationcategory(p_farmid);

    -- The P&L side. NonCash, no supplier, no cash account: the three things that
    -- keep it out of Cash Flow and out of payables while leaving it in profit.
    -- amountpaid = amount so the row reads Paid rather than sitting on Supplier
    -- Balances as a bill nobody will ever settle.
    INSERT INTO waterexpenses
        (farmid, expensedate, waterexpensecategoryid, description, amount,
         paymentmethod, watercashaccountid, supplierid, amountpaid,
         status, notes, createdby, approvedby, approvedat,
         sourcetype, sourceid, financialcosttype, watercapitalassetid)
    VALUES
        (p_farmid, v_end, v_catid,
         'Depreciation - ' || v_name || ' (' || to_char(p_periodstart, 'Mon YYYY') || ')',
         p_amount, 'NonCash', NULL, NULL, p_amount,
         'Approved', 'Auto-created by the depreciation schedule.',
         p_createdby, p_createdby, (now() at time zone 'utc'),
         'AssetDepreciation', v_id, 'NonCashExpense', p_assetid)
    RETURNING waterexpenseid INTO v_expid;

    UPDATE waterassetdepreciation d SET waterexpenseid = v_expid
    WHERE  d.waterassetdepreciationid = v_id;

    RETURN v_id;
END;
$function$;

COMMENT ON FUNCTION public.spwaterassetdepreciation_post(text, integer, date, numeric, text, text) IS
    'Writes ONE depreciation charge and its non-cash P&L expense. Internal: use '
    'spwaterassetdepreciation_generate.';

-- -----------------------------------------------------------------------------
-- 2. Generate everything that is due.
--
-- Finds every month between an asset's in-service month and the target month
-- that has no scheduled charge yet, and charges it. Running it twice charges
-- nothing the second time -- the unique index from 283 is the guarantee, and the
-- NOT EXISTS below is what makes the second run quiet rather than an error.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterassetdepreciation_generate(
    p_farmid      text,
    p_throughdate date    DEFAULT NULL,
    p_assetid     integer DEFAULT NULL,
    p_createdby   text    DEFAULT NULL
) RETURNS TABLE(assetsprocessed integer, entriescreated integer, totalamount numeric)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_through   date := date_trunc('month', COALESCE(p_throughdate, (now() at time zone 'utc')::date))::date;
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
        SELECT ca.watercapitalassetid AS assetid, ca.inservicedate, f.*
        FROM   watercapitalassets ca
        CROSS  JOIN LATERAL fnwatercapitalasset_financials(ca.watercapitalassetid) f
        WHERE  ca.farmid = p_farmid
          AND  (p_assetid IS NULL OR ca.watercapitalassetid = p_assetid)
          -- Draft, Reversed and Disposed assets are not earning and are not
          -- charged. FullyDepreciated is included only so the status can be
          -- corrected if a reversal reopened it.
          AND  ca.status IN ('Active', 'FullyDepreciated')
          AND  ca.inservicedate IS NOT NULL
          AND  COALESCE(ca.usefullifemonths, 0) > 0
        ORDER  BY ca.watercapitalassetid
    LOOP
        v_monthly   := a.monthlydepreciation;
        v_remaining := a.remainingdepreciable;
        v_made      := FALSE;

        IF COALESCE(v_monthly, 0) <= 0 THEN CONTINUE; END IF;

        v_period := date_trunc('month', a.inservicedate)::date;
        v_index  := 0;
        -- The schedule is exactly usefullifemonths long. Without that bound the
        -- rounding remainder -- 1,000 over 3 months leaves a pesewa after three
        -- charges of 333.33 -- would buy itself a fourth month, and an asset with
        -- a three-month life would depreciate over four.
        WHILE v_period <= v_through AND v_remaining > 0 AND v_index < a.usefullifemonths LOOP
            IF NOT EXISTS (
                SELECT 1 FROM waterassetdepreciation d
                WHERE  d.watercapitalassetid = a.assetid
                  AND  d.periodstart = v_period
                  AND  d.sourcetype = 'Scheduled')
            THEN
                -- The FINAL month of the life takes whatever is left rather than
                -- the rounded monthly figure, so accumulated depreciation lands
                -- on the depreciable amount exactly and FullyDepreciated can
                -- ever fire.
                v_charge := CASE WHEN v_index = a.usefullifemonths - 1
                                 THEN v_remaining
                                 ELSE LEAST(v_monthly, v_remaining) END;
                IF spwaterassetdepreciation_post(p_farmid, a.assetid, v_period,
                                                 v_charge, 'Scheduled', p_createdby) IS NOT NULL THEN
                    v_remaining := v_remaining - v_charge;
                    v_entries   := v_entries + 1;
                    v_total     := v_total + v_charge;
                    v_made      := TRUE;
                END IF;
            END IF;
            v_period := (v_period + interval '1 month')::date;
            v_index  := v_index + 1;
        END LOOP;

        IF v_made THEN
            v_assets := v_assets + 1;
        END IF;
    END LOOP;

    -- An asset that owes nothing more says so, and stops appearing in the "due"
    -- list for ever. The reverse direction matters too: reversing a charge
    -- reopens the asset, and this is what puts it back to Active.
    UPDATE watercapitalassets ca
    SET    status = s.newstatus, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT x.watercapitalassetid AS id,
               CASE WHEN f.isfullydepreciated THEN 'FullyDepreciated' ELSE 'Active' END AS newstatus
        FROM   watercapitalassets x
        CROSS  JOIN LATERAL fnwatercapitalasset_financials(x.watercapitalassetid) f
        WHERE  x.farmid = p_farmid
          AND  (p_assetid IS NULL OR x.watercapitalassetid = p_assetid)
          AND  x.status IN ('Active', 'FullyDepreciated')
    ) s
    WHERE  ca.watercapitalassetid = s.id AND ca.status <> s.newstatus;

    RETURN QUERY SELECT v_assets, v_entries, v_total;
END;
$function$;

COMMENT ON FUNCTION public.spwaterassetdepreciation_generate(text, date, integer, text) IS
    'Charges every due month up to p_throughdate. Idempotent: a second run '
    'creates nothing. Never moves cash.';

-- -----------------------------------------------------------------------------
-- 3. Reverse one charge.
--
-- The original row is kept and flagged; an opposite row is appended, and an
-- opposite expense with it. Nothing is deleted and nothing is edited into a
-- different number, so the history still says what was charged and when.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterassetdepreciation_reverse(
    p_farmid    text,
    p_entryid   integer,
    p_reason    text,
    p_createdby text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_row   record;
    v_name  text;
    v_new   integer;
    v_expid integer;
    v_catid integer;
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse depreciation.';
    END IF;

    SELECT d.* INTO v_row
    FROM   waterassetdepreciation d
    WHERE  d.waterassetdepreciationid = p_entryid AND d.farmid = p_farmid;
    IF v_row IS NULL THEN
        RAISE EXCEPTION 'Depreciation entry not found for this company.';
    END IF;
    IF v_row.status = 'Reversed' THEN
        RAISE EXCEPTION 'This depreciation entry has already been reversed.';
    END IF;
    IF v_row.amount < 0 THEN
        RAISE EXCEPTION 'A reversal cannot itself be reversed.';
    END IF;

    SELECT a.assetname INTO v_name FROM watercapitalassets a
    WHERE  a.watercapitalassetid = v_row.watercapitalassetid;

    INSERT INTO waterassetdepreciation
        (farmid, watercapitalassetid, periodstart, periodend, depreciationdate,
         amount, depreciationmethod, sourcetype, status, reversalofid, createdby, reversalreason)
    VALUES
        (p_farmid, v_row.watercapitalassetid, v_row.periodstart, v_row.periodend,
         (now() at time zone 'utc')::date,
         -v_row.amount, v_row.depreciationmethod, 'Reversal', 'Posted', p_entryid,
         p_createdby, p_reason)
    RETURNING waterassetdepreciationid INTO v_new;

    v_catid := fnwaterdepreciationcategory(p_farmid);

    -- The opposite P&L entry. Also NonCash: reversing depreciation does not put
    -- money back into the bank either.
    INSERT INTO waterexpenses
        (farmid, expensedate, waterexpensecategoryid, description, amount,
         paymentmethod, watercashaccountid, supplierid, amountpaid,
         status, notes, createdby, approvedby, approvedat,
         sourcetype, sourceid, financialcosttype, watercapitalassetid)
    VALUES
        (p_farmid, (now() at time zone 'utc')::date, v_catid,
         'Reversal of depreciation - ' || COALESCE(v_name, '') ||
         ' (' || to_char(v_row.periodstart, 'Mon YYYY') || '): ' || p_reason,
         -v_row.amount, 'NonCash', NULL, NULL, -v_row.amount,
         'Approved', 'Auto-created by a depreciation reversal.',
         p_createdby, p_createdby, (now() at time zone 'utc'),
         'AssetDepreciation', v_new, 'NonCashExpense', v_row.watercapitalassetid)
    RETURNING waterexpenseid INTO v_expid;

    UPDATE waterassetdepreciation d SET waterexpenseid = v_expid
    WHERE  d.waterassetdepreciationid = v_new;

    UPDATE waterassetdepreciation d
    SET    status = 'Reversed', reversedby = p_createdby,
           reversedat = (now() at time zone 'utc'), reversalreason = p_reason
    WHERE  d.waterassetdepreciationid = p_entryid;

    -- Book value has gone back up, so the asset may no longer be finished.
    UPDATE watercapitalassets ca
    SET    status = s.newstatus, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT x.watercapitalassetid AS id,
               CASE WHEN f.isfullydepreciated THEN 'FullyDepreciated' ELSE 'Active' END AS newstatus
        FROM   watercapitalassets x
        CROSS  JOIN LATERAL fnwatercapitalasset_financials(x.watercapitalassetid) f
        WHERE  x.watercapitalassetid = v_row.watercapitalassetid
    ) s
    WHERE  ca.watercapitalassetid = s.id AND ca.status IN ('Active', 'FullyDepreciated');
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3b. Correct one period by hand.
--
-- A reversal does NOT reopen its month to the generator, and that is deliberate:
-- if it did, the next "Generate due depreciation" would silently put the charge
-- straight back and the reverse button would do nothing at all. So a corrected
-- amount is posted explicitly, as a ManualAdjustment -- outside the unique index
-- that holds scheduled charges to one per month, and labelled in the history as
-- something a person decided rather than something the schedule did.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterassetdepreciation_adjust(
    p_farmid      text,
    p_assetid     integer,
    p_periodstart date,
    p_amount      numeric,
    p_reason      text,
    p_createdby   text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
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

    SELECT a.status INTO v_status FROM watercapitalassets a
    WHERE  a.watercapitalassetid = p_assetid AND a.farmid = p_farmid;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;
    IF v_status IN ('Reversed', 'Draft') THEN
        RAISE EXCEPTION 'Depreciation cannot be adjusted on a % asset.', lower(v_status);
    END IF;

    -- An adjustment cannot charge more than the asset has left to give, or
    -- accumulated depreciation would pass the depreciable amount and book value
    -- would fall through the residual floor.
    SELECT f.remainingdepreciable INTO v_left
    FROM   fnwatercapitalasset_financials(p_assetid) f;
    IF p_amount > v_left THEN
        RAISE EXCEPTION 'This asset has only % left to depreciate.', v_left;
    END IF;

    v_id := spwaterassetdepreciation_post(p_farmid, p_assetid,
                date_trunc('month', p_periodstart)::date, p_amount, 'ManualAdjustment', p_createdby);

    UPDATE waterassetdepreciation d SET reversalreason = p_reason
    WHERE  d.waterassetdepreciationid = v_id;

    UPDATE watercapitalassets ca
    SET    status = s.newstatus, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT x.watercapitalassetid AS id,
               CASE WHEN f.isfullydepreciated THEN 'FullyDepreciated' ELSE 'Active' END AS newstatus
        FROM   watercapitalassets x
        CROSS  JOIN LATERAL fnwatercapitalasset_financials(x.watercapitalassetid) f
        WHERE  x.watercapitalassetid = p_assetid
    ) s
    WHERE  ca.watercapitalassetid = s.id AND ca.status IN ('Active', 'FullyDepreciated');

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Reads: the depreciation history and the drilldown behind the P&L line.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterassetdepreciation_getall(
    p_farmid text, p_assetid integer DEFAULT NULL,
    p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL
) RETURNS TABLE(waterassetdepreciationid integer, watercapitalassetid integer,
                assetnumber text, assetname text, categoryname text,
                periodstart date, periodend date, depreciationdate date,
                amount numeric, depreciationmethod text, sourcetype text, status text,
                waterexpenseid integer, reversalofid integer,
                originalcost numeric, monthlydepreciation numeric,
                accumulatedafter numeric, bookvalueafter numeric,
                createdby text, createdat timestamp without time zone,
                reversedby text, reversedat timestamp without time zone, reversalreason text)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT d.waterassetdepreciationid, d.watercapitalassetid,
           a.assetnumber::text, a.assetname::text, c.categoryname::text,
           d.periodstart, d.periodend, d.depreciationdate,
           d.amount, d.depreciationmethod::text, d.sourcetype::text, d.status::text,
           d.waterexpenseid, d.reversalofid,
           fnwatercapitalasset_originalcost(d.watercapitalassetid),
           fnwatercapitalasset_monthly(
               fnwatercapitalasset_originalcost(d.watercapitalassetid),
               a.residualvalue, a.usefullifemonths),
           -- Running accumulated and book value AS AT this row, so the history
           -- reads like a statement rather than a list of equal numbers.
           (SELECT COALESCE(SUM(p.amount), 0)::numeric(14,2)
              FROM waterassetdepreciation p
             WHERE p.watercapitalassetid = d.watercapitalassetid
               AND (p.depreciationdate, p.waterassetdepreciationid)
                   <= (d.depreciationdate, d.waterassetdepreciationid)),
           GREATEST(fnwatercapitalasset_originalcost(d.watercapitalassetid)
                    - (SELECT COALESCE(SUM(p.amount), 0)
                         FROM waterassetdepreciation p
                        WHERE p.watercapitalassetid = d.watercapitalassetid
                          AND (p.depreciationdate, p.waterassetdepreciationid)
                              <= (d.depreciationdate, d.waterassetdepreciationid)),
                    a.residualvalue)::numeric(14,2),
           d.createdby::text, d.createdat,
           d.reversedby::text, d.reversedat, d.reversalreason::text
    FROM   waterassetdepreciation d
    JOIN   watercapitalassets a ON a.watercapitalassetid = d.watercapitalassetid
    LEFT   JOIN waterassetcategories c ON c.waterassetcategoryid = a.waterassetcategoryid
    WHERE  d.farmid = p_farmid
      AND  (p_assetid IS NULL OR d.watercapitalassetid = p_assetid)
      AND  (p_fromdate IS NULL OR d.depreciationdate >= p_fromdate)
      AND  (p_todate   IS NULL OR d.depreciationdate <= p_todate)
    ORDER  BY d.depreciationdate DESC, d.waterassetdepreciationid DESC;
END;
$function$;

-- What Generate would do, without doing it. The register needs to say "3 assets,
-- 7 months, 14,000" before an owner presses a button that writes to the P&L.
CREATE OR REPLACE FUNCTION public.spwaterassetdepreciation_due(
    p_farmid text, p_throughdate date DEFAULT NULL
) RETURNS TABLE(watercapitalassetid integer, assetnumber text, assetname text,
                monthsdue integer, amountdue numeric, monthlydepreciation numeric,
                nextperiod date)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_through date := date_trunc('month', COALESCE(p_throughdate, (now() at time zone 'utc')::date))::date;
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
        SELECT ca.watercapitalassetid AS assetid, ca.assetnumber, ca.assetname,
               ca.inservicedate, f.*
        FROM   watercapitalassets ca
        CROSS  JOIN LATERAL fnwatercapitalasset_financials(ca.watercapitalassetid) f
        WHERE  ca.farmid = p_farmid AND ca.status = 'Active'
          AND  ca.inservicedate IS NOT NULL AND COALESCE(ca.usefullifemonths, 0) > 0
        ORDER  BY ca.watercapitalassetid
    LOOP
        v_months := 0; v_amount := 0; v_next := NULL;
        v_left   := a.remainingdepreciable;
        v_period := date_trunc('month', a.inservicedate)::date;
        v_index  := 0;

        -- Deliberately the same walk as _generate, bound and final-month rule
        -- included. A preview that promised a different number from the button
        -- beside it would be worse than no preview.
        WHILE v_period <= v_through AND v_left > 0 AND v_index < a.usefullifemonths LOOP
            IF NOT EXISTS (SELECT 1 FROM waterassetdepreciation d
                           WHERE d.watercapitalassetid = a.assetid
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
            watercapitalassetid := a.assetid;
            assetnumber         := a.assetnumber::text;
            assetname           := a.assetname::text;
            monthsdue           := v_months;
            amountdue           := v_amount;
            monthlydepreciation := a.monthlydepreciation;
            nextperiod          := v_next;
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Post-conditions. No depreciation has been generated by this file.
-- -----------------------------------------------------------------------------
SELECT 'no depreciation posted by the migration' AS check, COUNT(*) AS should_be_zero
FROM   waterassetdepreciation;

SELECT 'no depreciation expense exists yet' AS check, COUNT(*) AS should_be_zero
FROM   waterexpenses WHERE sourcetype = 'AssetDepreciation';

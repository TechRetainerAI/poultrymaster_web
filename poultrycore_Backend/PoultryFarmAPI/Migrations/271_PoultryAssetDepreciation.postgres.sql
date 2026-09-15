-- =============================================================================
-- 271_PoultryAssetDepreciation.postgres.sql
--
-- Purpose
-- -------
-- Phase 3, part 3: charge an asset to Profit & Loss a month at a time, and move
-- no money at all while doing it.
--
-- DEPRECIATION IS THE ONE EXPENSE WITH NO PAYMENT
-- ===============================================
-- It increases the P&L cost of the period, it reduces the asset's book value,
-- and it touches NOTHING else: no cash transaction, no cash account, no
-- supplier, no payable, no payment. That is the whole definition, and every
-- guard in this file exists to keep it true.
--
-- The mechanism is the one Phase 2 already established for feed consumption:
-- an `expense` row with paymentmethod 'NonCash'. Migration 216 made that marker
-- mean "cost recorded, no money moved" -- the cash-flow arms skip it, payables
-- skip it, and the P&L counts it. Depreciation needs exactly that, so it uses
-- exactly that rather than a fourth way of saying the same thing.
--
-- THE CONVENTION, STATED ONCE
-- ===========================
-- Depreciation is charged for the WHOLE month containing the in-service date,
-- and for every whole month after it. No proration.
--
-- A machine put into service on the 28th is charged a full month for that
-- month. That is a deliberate simplification (§19): it is consistent, it is
-- explainable to an owner in one sentence, and the alternative -- half-month
-- conventions, day counts, tax tables -- is the accounting software this system
-- is explicitly not trying to become. Consistency matters more here than
-- tax-level precision.
--
-- WHY THE LAST MONTH IS SPECIAL
-- =============================
-- (cost - residual) / life rounds to the cedi, and twelve rounded months do not
-- necessarily add up to the year. So the final charge is whatever is LEFT rather
-- than the monthly figure, and accumulated depreciation lands on the depreciable
-- amount exactly. Without that an asset would sit at 3 pesewas of book value
-- above its residual for ever, and §20's FullyDepreciated would never fire.
--
-- REVERSAL IS APPEND-ONLY
-- =======================
-- A reversed charge is KEPT and marked; an opposite row is written beside it,
-- and an opposite expense beside that. Accumulated depreciation is a signed SUM
-- (270), so it falls out correctly with no row ever being edited into a lie.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Post one month's charge for one asset.
--
-- Internal: the generator below drives it. Separate because it is also what a
-- catch-up or a one-off adjustment needs, and having one writer means the
-- expense row, the ledger row and the link between them cannot drift.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryassetdepreciation_post(
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
    v_id      integer;
    v_expid   integer;
    v_uuid    uuid := p_farmid::uuid;
    v_end     date := (date_trunc('month', p_periodstart) + interval '1 month - 1 day')::date;
    v_name    text;
    v_number  text;
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN
        RETURN NULL;                    -- nothing to charge is not an error
    END IF;

    SELECT a.assetname, a.assetnumber INTO v_name, v_number
    FROM   poultrycapitalassets a
    WHERE  a.poultrycapitalassetid = p_assetid AND a.farmid = p_farmid;
    IF v_name IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;

    INSERT INTO poultryassetdepreciation
        (farmid, poultrycapitalassetid, periodstart, periodend, depreciationdate,
         amount, depreciationmethod, sourcetype, status, createdby)
    VALUES
        (p_farmid, p_assetid, date_trunc('month', p_periodstart)::date, v_end, v_end,
         p_amount, 'StraightLine', p_sourcetype, 'Posted', p_createdby)
    RETURNING poultryassetdepreciationid INTO v_id;

    -- The P&L side. NonCash, no supplier, no cash account: the three things that
    -- keep it out of Cash Flow and out of payables while leaving it in profit.
    -- amountpaid = amount so the row reads Paid rather than sitting on Supplier
    -- Balances as a bill nobody will ever settle.
    INSERT INTO expense
        (farmid, expensedate, category, description, amount, paymentmethod,
         sourcetype, sourceid, poultrycashaccountid, supplierid, amountpaid,
         userid, financialcosttype, poultrycapitalassetid, createddate)
    VALUES
        (v_uuid, v_end::timestamp, 'Depreciation',
         'Depreciation - ' || v_name || ' (' || to_char(p_periodstart, 'Mon YYYY') || ')',
         p_amount, 'NonCash', 'AssetDepreciation', v_id, NULL, NULL, p_amount,
         p_createdby, 'NonCashExpense', p_assetid, (now() at time zone 'utc'))
    RETURNING expenseid INTO v_expid;

    UPDATE poultryassetdepreciation d SET expenseid = v_expid
    WHERE  d.poultryassetdepreciationid = v_id;

    RETURN v_id;
END;
$function$;

COMMENT ON FUNCTION public.sppoultryassetdepreciation_post(text, integer, date, numeric, text, text) IS
    'Writes ONE depreciation charge and its non-cash P&L expense. Internal: use '
    'sppoultryassetdepreciation_generate.';

-- -----------------------------------------------------------------------------
-- 2. Generate everything that is due.
--
-- Finds every month between an asset's in-service month and the target month
-- that has no scheduled charge yet, and charges it. Running it twice charges
-- nothing the second time -- the unique index from 270 is the guarantee, and
-- the NOT EXISTS below is what makes the second run quiet rather than an error.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryassetdepreciation_generate(
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
        SELECT ca.poultrycapitalassetid AS assetid, ca.inservicedate, f.*
        FROM   poultrycapitalassets ca
        CROSS  JOIN LATERAL fnpoultrycapitalasset_financials(ca.poultrycapitalassetid) f
        WHERE  ca.farmid = p_farmid
          AND  (p_assetid IS NULL OR ca.poultrycapitalassetid = p_assetid)
          -- Draft, Reversed and Disposed assets are not earning and are not
          -- charged. FullyDepreciated is included only so the status can be
          -- corrected if a reversal reopened it.
          AND  ca.status IN ('Active', 'FullyDepreciated')
          AND  ca.inservicedate IS NOT NULL
          AND  COALESCE(ca.usefullifemonths, 0) > 0
        ORDER  BY ca.poultrycapitalassetid
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
                SELECT 1 FROM poultryassetdepreciation d
                WHERE  d.poultrycapitalassetid = a.assetid
                  AND  d.periodstart = v_period
                  AND  d.sourcetype = 'Scheduled')
            THEN
                -- The FINAL month of the life takes whatever is left rather than
                -- the rounded monthly figure, so accumulated depreciation lands
                -- on the depreciable amount exactly and §20 can ever fire.
                v_charge := CASE WHEN v_index = a.usefullifemonths - 1
                                 THEN v_remaining
                                 ELSE LEAST(v_monthly, v_remaining) END;
                IF sppoultryassetdepreciation_post(p_farmid, a.assetid, v_period,
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

    -- §20. An asset that owes nothing more says so, and stops appearing in the
    -- "due" list for ever. The reverse direction matters too: reversing a charge
    -- reopens the asset, and this is what puts it back to Active.
    UPDATE poultrycapitalassets ca
    SET    status = s.newstatus, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT x.poultrycapitalassetid AS id,
               CASE WHEN f.isfullydepreciated THEN 'FullyDepreciated' ELSE 'Active' END AS newstatus
        FROM   poultrycapitalassets x
        CROSS  JOIN LATERAL fnpoultrycapitalasset_financials(x.poultrycapitalassetid) f
        WHERE  x.farmid = p_farmid
          AND  (p_assetid IS NULL OR x.poultrycapitalassetid = p_assetid)
          AND  x.status IN ('Active', 'FullyDepreciated')
    ) s
    WHERE  ca.poultrycapitalassetid = s.id AND ca.status <> s.newstatus;

    RETURN QUERY SELECT v_assets, v_entries, v_total;
END;
$function$;

COMMENT ON FUNCTION public.sppoultryassetdepreciation_generate(text, date, integer, text) IS
    'Charges every due month up to p_throughdate. Idempotent: a second run '
    'creates nothing. Never moves cash.';

-- -----------------------------------------------------------------------------
-- 3. Reverse one charge.
--
-- The original row is kept and flagged; an opposite row is appended, and an
-- opposite expense with it. Nothing is deleted and nothing is edited into a
-- different number, so the history still says what was charged and when.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryassetdepreciation_reverse(
    p_farmid   text,
    p_entryid  integer,
    p_reason   text,
    p_createdby text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_uuid   uuid := p_farmid::uuid;
    v_row    record;
    v_name   text;
    v_new    integer;
    v_expid  integer;
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse depreciation.';
    END IF;

    SELECT d.* INTO v_row
    FROM   poultryassetdepreciation d
    WHERE  d.poultryassetdepreciationid = p_entryid AND d.farmid = p_farmid;
    IF v_row IS NULL THEN
        RAISE EXCEPTION 'Depreciation entry not found for this company.';
    END IF;
    IF v_row.status = 'Reversed' THEN
        RAISE EXCEPTION 'This depreciation entry has already been reversed.';
    END IF;
    IF v_row.amount < 0 THEN
        RAISE EXCEPTION 'A reversal cannot itself be reversed.';
    END IF;

    SELECT a.assetname INTO v_name FROM poultrycapitalassets a
    WHERE  a.poultrycapitalassetid = v_row.poultrycapitalassetid;

    INSERT INTO poultryassetdepreciation
        (farmid, poultrycapitalassetid, periodstart, periodend, depreciationdate,
         amount, depreciationmethod, sourcetype, status, reversalofid, createdby, reversalreason)
    VALUES
        (p_farmid, v_row.poultrycapitalassetid, v_row.periodstart, v_row.periodend,
         (now() at time zone 'utc')::date,
         -v_row.amount, v_row.depreciationmethod, 'Reversal', 'Posted', p_entryid,
         p_createdby, p_reason)
    RETURNING poultryassetdepreciationid INTO v_new;

    -- The opposite P&L entry. Also NonCash: reversing depreciation does not put
    -- money back into the bank either.
    INSERT INTO expense
        (farmid, expensedate, category, description, amount, paymentmethod,
         sourcetype, sourceid, poultrycashaccountid, supplierid, amountpaid,
         userid, financialcosttype, poultrycapitalassetid, createddate)
    VALUES
        (v_uuid, (now() at time zone 'utc'), 'Depreciation',
         'Reversal of depreciation - ' || COALESCE(v_name, '') ||
         ' (' || to_char(v_row.periodstart, 'Mon YYYY') || '): ' || p_reason,
         -v_row.amount, 'NonCash', 'AssetDepreciation', v_new, NULL, NULL, -v_row.amount,
         p_createdby, 'NonCashExpense', v_row.poultrycapitalassetid, (now() at time zone 'utc'))
    RETURNING expenseid INTO v_expid;

    UPDATE poultryassetdepreciation d SET expenseid = v_expid
    WHERE  d.poultryassetdepreciationid = v_new;

    UPDATE poultryassetdepreciation d
    SET    status = 'Reversed', reversedby = p_createdby,
           reversedat = (now() at time zone 'utc'), reversalreason = p_reason
    WHERE  d.poultryassetdepreciationid = p_entryid;

    -- Book value has gone back up, so the asset may no longer be finished.
    UPDATE poultrycapitalassets ca
    SET    status = s.newstatus, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT x.poultrycapitalassetid AS id,
               CASE WHEN f.isfullydepreciated THEN 'FullyDepreciated' ELSE 'Active' END AS newstatus
        FROM   poultrycapitalassets x
        CROSS  JOIN LATERAL fnpoultrycapitalasset_financials(x.poultrycapitalassetid) f
        WHERE  x.poultrycapitalassetid = v_row.poultrycapitalassetid
    ) s
    WHERE  ca.poultrycapitalassetid = s.id AND ca.status IN ('Active', 'FullyDepreciated');
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
CREATE OR REPLACE FUNCTION public.sppoultryassetdepreciation_adjust(
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

    SELECT a.status INTO v_status FROM poultrycapitalassets a
    WHERE  a.poultrycapitalassetid = p_assetid AND a.farmid = p_farmid;
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
    FROM   fnpoultrycapitalasset_financials(p_assetid) f;
    IF p_amount > v_left THEN
        RAISE EXCEPTION 'This asset has only % left to depreciate.', v_left;
    END IF;

    v_id := sppoultryassetdepreciation_post(p_farmid, p_assetid,
                date_trunc('month', p_periodstart)::date, p_amount, 'ManualAdjustment', p_createdby);

    UPDATE poultryassetdepreciation d SET reversalreason = p_reason
    WHERE  d.poultryassetdepreciationid = v_id;

    UPDATE poultrycapitalassets ca
    SET    status = s.newstatus, updatedat = (now() at time zone 'utc')
    FROM (
        SELECT x.poultrycapitalassetid AS id,
               CASE WHEN f.isfullydepreciated THEN 'FullyDepreciated' ELSE 'Active' END AS newstatus
        FROM   poultrycapitalassets x
        CROSS  JOIN LATERAL fnpoultrycapitalasset_financials(x.poultrycapitalassetid) f
        WHERE  x.poultrycapitalassetid = p_assetid
    ) s
    WHERE  ca.poultrycapitalassetid = s.id AND ca.status IN ('Active', 'FullyDepreciated');

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Reads: the depreciation history and the drilldown behind the P&L line.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryassetdepreciation_getall(
    p_farmid text, p_assetid integer DEFAULT NULL,
    p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL
) RETURNS TABLE(poultryassetdepreciationid integer, poultrycapitalassetid integer,
                assetnumber text, assetname text, categoryname text,
                periodstart date, periodend date, depreciationdate date,
                amount numeric, depreciationmethod text, sourcetype text, status text,
                expenseid integer, reversalofid integer,
                originalcost numeric, monthlydepreciation numeric,
                accumulatedafter numeric, bookvalueafter numeric,
                createdby text, createdat timestamp without time zone,
                reversedby text, reversedat timestamp without time zone, reversalreason text)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT d.poultryassetdepreciationid, d.poultrycapitalassetid,
           a.assetnumber::text, a.assetname::text, c.categoryname::text,
           d.periodstart, d.periodend, d.depreciationdate,
           d.amount, d.depreciationmethod::text, d.sourcetype::text, d.status::text,
           d.expenseid, d.reversalofid,
           fnpoultrycapitalasset_originalcost(d.poultrycapitalassetid),
           fnpoultrycapitalasset_monthly(
               fnpoultrycapitalasset_originalcost(d.poultrycapitalassetid),
               a.residualvalue, a.usefullifemonths),
           -- Running accumulated and book value AS AT this row, so the history
           -- reads like a statement rather than a list of equal numbers.
           (SELECT COALESCE(SUM(p.amount), 0)::numeric(14,2)
              FROM poultryassetdepreciation p
             WHERE p.poultrycapitalassetid = d.poultrycapitalassetid
               AND (p.depreciationdate, p.poultryassetdepreciationid)
                   <= (d.depreciationdate, d.poultryassetdepreciationid)),
           GREATEST(fnpoultrycapitalasset_originalcost(d.poultrycapitalassetid)
                    - (SELECT COALESCE(SUM(p.amount), 0)
                         FROM poultryassetdepreciation p
                        WHERE p.poultrycapitalassetid = d.poultrycapitalassetid
                          AND (p.depreciationdate, p.poultryassetdepreciationid)
                              <= (d.depreciationdate, d.poultryassetdepreciationid)),
                    a.residualvalue)::numeric(14,2),
           d.createdby::text, d.createdat,
           d.reversedby::text, d.reversedat, d.reversalreason::text
    FROM   poultryassetdepreciation d
    JOIN   poultrycapitalassets a ON a.poultrycapitalassetid = d.poultrycapitalassetid
    LEFT   JOIN poultryassetcategories c ON c.poultryassetcategoryid = a.poultryassetcategoryid
    WHERE  d.farmid = p_farmid
      AND  (p_assetid IS NULL OR d.poultrycapitalassetid = p_assetid)
      AND  (p_fromdate IS NULL OR d.depreciationdate >= p_fromdate)
      AND  (p_todate   IS NULL OR d.depreciationdate <= p_todate)
    ORDER  BY d.depreciationdate DESC, d.poultryassetdepreciationid DESC;
END;
$function$;

-- What Generate would do, without doing it. The register needs to say "3 assets,
-- 7 months, 14,000" before an owner presses a button that writes to the P&L.
CREATE OR REPLACE FUNCTION public.sppoultryassetdepreciation_due(
    p_farmid text, p_throughdate date DEFAULT NULL
) RETURNS TABLE(poultrycapitalassetid integer, assetnumber text, assetname text,
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
        SELECT ca.poultrycapitalassetid AS assetid, ca.assetnumber, ca.assetname,
               ca.inservicedate, f.*
        FROM   poultrycapitalassets ca
        CROSS  JOIN LATERAL fnpoultrycapitalasset_financials(ca.poultrycapitalassetid) f
        WHERE  ca.farmid = p_farmid AND ca.status = 'Active'
          AND  ca.inservicedate IS NOT NULL AND COALESCE(ca.usefullifemonths, 0) > 0
        ORDER  BY ca.poultrycapitalassetid
    LOOP
        v_months := 0; v_amount := 0; v_next := NULL;
        v_left   := a.remainingdepreciable;
        v_period := date_trunc('month', a.inservicedate)::date;
        v_index  := 0;

        -- Deliberately the same walk as _generate, bound and final-month rule
        -- included. A preview that promised a different number from the button
        -- beside it would be worse than no preview.
        WHILE v_period <= v_through AND v_left > 0 AND v_index < a.usefullifemonths LOOP
            IF NOT EXISTS (SELECT 1 FROM poultryassetdepreciation d
                           WHERE d.poultrycapitalassetid = a.assetid
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
            poultrycapitalassetid := a.assetid;
            assetnumber           := a.assetnumber::text;
            assetname             := a.assetname::text;
            monthsdue             := v_months;
            amountdue             := v_amount;
            monthlydepreciation   := a.monthlydepreciation;
            nextperiod            := v_next;
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$function$;

-- -----------------------------------------------------------------------------
-- Post-conditions. No depreciation has been generated by this file.
-- -----------------------------------------------------------------------------
SELECT 'no depreciation posted by the migration' AS check, COUNT(*) AS should_be_zero
FROM   poultryassetdepreciation;

SELECT 'no depreciation expense exists yet' AS check, COUNT(*) AS should_be_zero
FROM   expense WHERE sourcetype = 'AssetDepreciation';

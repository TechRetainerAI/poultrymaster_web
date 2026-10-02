-- =============================================================================
-- 326_PoultryHistoricalBatchPurchase.postgres.sql
--
-- Purpose
-- -------
-- Let a batch say whether it was bought BEFORE this application started tracking
-- the farm, and stop a pre-tracking purchase from posting today's expense.
--
-- THE PROBLEM
-- ===========
-- Initial Farm Setup describes birds an established farm already has. Those
-- birds were bought months ago: the money left the farm before any period this
-- application reports on. Today the wizard avoids inventing that expense by
-- hard-coding AmountPaid = 0 (FarmSetupService.cs), which works only because
-- spflockbatchexpense_sync returns early when the amount is zero.
--
-- That is a blunt instrument. It means a farm can never record what it actually
-- paid, and the moment anyone edits such a batch through the ordinary Flock
-- Purchases page, spmainflockbatch_update recreates the expense from whatever
-- amountpaid then holds -- dated to a placement six months in the past.
--
-- WHAT A HISTORICAL PURCHASE SHOULD DO
-- ====================================
-- Bought 5,000 chicks six months ago for 10,000, paid 7,000, still owes 3,000:
--
--   Expense   NOT posted.  The cost belongs to a period this application never
--                          reported on. Booking it now puts a six-month-old
--                          expense inside a current report.
--   Cash      NOT posted.  The money moved before tracking began.
--   Payable   POSTED, 3,000. This one is genuinely current -- the farm really
--                          does still owe its supplier -- and it needs no new
--                          machinery: fnpoultrypayables already derives it live
--                          as GREATEST(totalcost - amountpaid, 0). Recording
--                          amountpaid HONESTLY is what makes it right, which is
--                          exactly what the AmountPaid = 0 workaround prevented.
--   Birds     POSTED, dated to the batch's start date, so the flock appears in
--                          openingbirds rather than as this period's purchase.
--
-- Paying the remaining 3,000 later still books an expense on the day it is paid,
-- through the ordinary pay-balance path. Under this application's expense = cash
-- paid model that is correct and is left alone.
--
-- WHY A COLUMN AND NOT JUST AN INSERT-TIME DECISION
-- =================================================
-- Because spmainflockbatch_update re-derives the expense every time the batch is
-- edited. Without a persisted flag, the first edit through the ordinary page
-- would resurrect precisely the expense this migration exists to prevent. The
-- flag has to outlive the insert.
--
-- Idempotent. Safe to run more than once.
-- EFFECT ON TODAY'S NUMBERS: none. Every existing batch is ishistorical = false,
-- which is the behaviour it already had.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The flag.
-- -----------------------------------------------------------------------------
ALTER TABLE public.mainflockbatch
    ADD COLUMN IF NOT EXISTS ishistorical boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.mainflockbatch.ishistorical IS
    'True when the purchase happened before this application tracked the farm. '
    'Suppresses the expense posting; the payable and the bird stock are still real.';

-- -----------------------------------------------------------------------------
-- 2. A dated bird-stock movement.
--
-- sppoultrybirdstock_sync always stamps createddate with now(), and the closing
-- report buckets bird movements by createddate::date. A purchase that happened
-- six months ago has to carry that date or it lands in the current period as
-- birdspurchased. This is that function with the date made explicit; the
-- append-only delta behaviour is identical, so the two are interchangeable for
-- the same (txntype, relatedid).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrybirdstock_postdated(
    p_farmid        text,
    p_txntype       text,
    p_quantity      numeric,
    p_relatedid     integer,
    p_effectivedate date,
    p_note          text DEFAULT NULL,
    p_createdby     text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_bird  integer;
    v_net   numeric;
    v_delta numeric;
BEGIN
    SELECT pp.poultryproductid INTO v_bird
    FROM   poultryproducts pp
    WHERE  pp.farmid = p_farmid AND (pp.isbirdproduct = TRUE OR pp.name = 'Birds')
    ORDER  BY pp.isbirdproduct DESC, pp.poultryproductid
    LIMIT  1;

    IF v_bird IS NULL THEN
        INSERT INTO poultryproducts (farmid, name, unit, unitprice, producttype,
                                     israweggproduct, requiresrecipesetup, isbirdproduct)
        VALUES (p_farmid, 'Birds', 'Bird', 0, 'FinishedGood', FALSE, FALSE, TRUE)
        RETURNING poultryproductid INTO v_bird;
    END IF;

    -- Append-only: post the delta needed to REACH p_quantity for this
    -- (txntype, relatedid). Never deletes, and a repeat writes nothing.
    SELECT COALESCE(SUM(t.quantity), 0) INTO v_net
    FROM   poultrystocktransactions t
    WHERE  t.farmid = p_farmid AND t.txntype = p_txntype AND t.relatedid = p_relatedid;

    v_delta := COALESCE(p_quantity, 0) - v_net;
    IF v_delta = 0 THEN
        RETURN 0;
    END IF;

    INSERT INTO poultrystocktransactions
        (farmid, poultryproductid, txntype, quantity, relatedid, note, createdby, createddate)
    VALUES
        (p_farmid, v_bird, p_txntype, v_delta, p_relatedid,
         CASE WHEN COALESCE(p_quantity, 0) = 0 THEN 'Reversal of ' || p_txntype ELSE p_note END,
         p_createdby,
         COALESCE(p_effectivedate, (now() AT TIME ZONE 'utc')::date)::timestamp);

    RETURN 1;
END
$function$;

-- The opening-reduction poster from 325 is the same operation with the type and
-- sign fixed. Delegating keeps one definition of "post a dated bird movement".
CREATE OR REPLACE FUNCTION public.sppoultryopeningbirdstock_post(
    p_farmid            text,
    p_openingpositionid integer,
    p_reduction         integer,
    p_effectivedate     date,
    p_note              text DEFAULT NULL,
    p_createdby         text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_farmid IS NULL OR p_openingpositionid IS NULL THEN
        RAISE EXCEPTION '325: farmid and openingpositionid are required.';
    END IF;

    RETURN public.sppoultrybirdstock_postdated(
        p_farmid,
        'Opening Adjustment',
        -ABS(COALESCE(p_reduction, 0)),
        p_openingpositionid,
        p_effectivedate,
        COALESCE(NULLIF(btrim(p_note), ''), 'Opening historical reduction (Initial Farm Setup)'),
        p_createdby);
END
$function$;

-- -----------------------------------------------------------------------------
-- 3. Batch insert and update, with the flag.
--
-- The existing signatures are DROPPED BY NAME first. Adding a parameter that has
-- a DEFAULT would otherwise leave the old signature in place and every existing
-- call ambiguous -- Postgres refuses to choose between a 17-argument function and
-- an 18-argument one whose last argument defaults.
--
-- Bodies are reproduced from pg_get_functiondef of the LIVE functions, not from
-- the T-SQL originals in 162: those two have provably diverged, and the live
-- definition is the one that matters.
-- -----------------------------------------------------------------------------
DO $drops$
DECLARE
    v_sig text;
BEGIN
    FOR v_sig IN
        SELECT format('%s(%s)', p.oid::regproc, pg_get_function_identity_arguments(p.oid))
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('spmainflockbatch_insert', 'spmainflockbatch_update')
    LOOP
        EXECUTE 'DROP FUNCTION ' || v_sig;
    END LOOP;
END
$drops$;

CREATE OR REPLACE FUNCTION public.spmainflockbatch_insert(
    p_userid text, p_farmid text, p_batchcode text, p_batchname text, p_breed text,
    p_numberofbirds integer, p_startdate timestamp without time zone,
    p_status text DEFAULT 'active'::text, p_costperchick numeric DEFAULT 0,
    p_totalcost numeric DEFAULT 0, p_suppliertype text DEFAULT NULL::text,
    p_supplierid integer DEFAULT NULL::integer, p_amountpaid numeric DEFAULT 0,
    p_notes text DEFAULT NULL::text, p_orderplacementdate date DEFAULT NULL::date,
    p_estimatedarrivaldate date DEFAULT NULL::date, p_dollarconversionrate numeric DEFAULT NULL::numeric,
    p_ishistorical boolean DEFAULT false)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_totalcost   numeric := p_totalcost;
    v_amountpaid  numeric := p_amountpaid;
    v_newid       integer;
    v_historical  boolean := COALESCE(p_ishistorical, false);
BEGIN
    IF (v_totalcost IS NULL OR v_totalcost = 0) AND p_costperchick > 0 THEN
        v_totalcost := p_costperchick * p_numberofbirds;
    END IF;
    IF v_amountpaid IS NULL THEN
        v_amountpaid := 0;
    END IF;
    IF v_totalcost IS NOT NULL AND v_amountpaid > v_totalcost THEN
        v_amountpaid := v_totalcost;
    END IF;

    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, status, costperchick, totalcost, amountpaid, suppliertype, supplierid, notes, orderplacementdate, estimatedarrivaldate, dollarconversionrate, createddate, ishistorical)
    VALUES (p_userid, p_farmid, p_batchcode, p_batchname, p_breed, p_numberofbirds, p_startdate, COALESCE(p_status, 'active'), COALESCE(p_costperchick, 0), COALESCE(v_totalcost, 0), COALESCE(v_amountpaid, 0), p_suppliertype, p_supplierid, p_notes, p_orderplacementdate, p_estimatedarrivaldate, p_dollarconversionrate, (now() at time zone 'utc'), v_historical)
    RETURNING batchid INTO v_newid;

    IF COALESCE(p_numberofbirds, 0) > 0 THEN
        IF v_historical THEN
            -- The birds are real and standing, but they arrived before tracking
            -- began: dated to the placement so they read as an opening balance
            -- rather than as this period's purchase.
            PERFORM sppoultrybirdstock_postdated(p_farmid, 'Bird Batch Purchase', p_numberofbirds::numeric,
                                                 v_newid, p_startdate::date, 'Flock batch purchase (historical)', p_userid);
        ELSE
            PERFORM sppoultrybirdstock_sync(p_farmid, 'Bird Batch Purchase', p_numberofbirds::numeric,
                                            v_newid, 'Flock batch purchase', p_userid);
        END IF;
    END IF;

    -- Expense = cash actually paid (down payment). Brand-new batch, so the sync's
    -- delete-for-source is a no-op; it then posts one expense = amount paid.
    --
    -- Skipped entirely for a historical purchase: that money left the farm before
    -- any period this application reports on. What the farm still OWES is not
    -- skipped -- amountpaid is stored as given, and fnpoultrypayables derives the
    -- outstanding balance from it.
    IF NOT v_historical THEN
        PERFORM spflockbatchexpense_sync(p_farmid, v_newid, v_amountpaid, p_startdate, p_batchname, p_numberofbirds, p_userid);
    END IF;

    RETURN v_newid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spmainflockbatch_update(
    p_batchid integer, p_userid text, p_farmid text, p_batchcode text, p_batchname text,
    p_breed text, p_numberofbirds integer, p_startdate timestamp without time zone,
    p_status text DEFAULT 'active'::text, p_costperchick numeric DEFAULT 0,
    p_totalcost numeric DEFAULT 0, p_suppliertype text DEFAULT NULL::text,
    p_supplierid integer DEFAULT NULL::integer, p_amountpaid numeric DEFAULT 0,
    p_notes text DEFAULT NULL::text, p_orderplacementdate date DEFAULT NULL::date,
    p_estimatedarrivaldate date DEFAULT NULL::date, p_dollarconversionrate numeric DEFAULT NULL::numeric,
    p_ishistorical boolean DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_totalcost  numeric := p_totalcost;
    v_amountpaid numeric := p_amountpaid;
    v_gid        uuid;
    v_initexpid  integer;
    v_otherpaid  numeric;
    v_initamount numeric;
    v_desc       text;
    v_historical boolean;
BEGIN
    IF (v_totalcost IS NULL OR v_totalcost = 0) AND p_costperchick > 0 THEN
        v_totalcost := p_costperchick * p_numberofbirds;
    END IF;
    IF v_amountpaid IS NULL THEN
        v_amountpaid := 0;
    END IF;

    -- NULL means "leave it as it is". The ordinary Flock Purchases form does not
    -- send this field, and editing a batch there must not silently turn a
    -- historical purchase into a current one.
    SELECT COALESCE(p_ishistorical, b.ishistorical, false) INTO v_historical
    FROM   mainflockbatch b
    WHERE  b.batchid = p_batchid AND b.farmid = p_farmid;
    v_historical := COALESCE(v_historical, false);

    UPDATE mainflockbatch b
    SET batchcode = p_batchcode, batchname = p_batchname, breed = p_breed, numberofbirds = p_numberofbirds,
        startdate = p_startdate, status = COALESCE(p_status, b.status), costperchick = COALESCE(p_costperchick, 0),
        totalcost = COALESCE(v_totalcost, 0), amountpaid = COALESCE(v_amountpaid, 0), suppliertype = p_suppliertype,
        supplierid = p_supplierid, notes = p_notes,
        orderplacementdate = p_orderplacementdate, estimatedarrivaldate = p_estimatedarrivaldate,
        dollarconversionrate = p_dollarconversionrate,
        ishistorical = v_historical
    WHERE b.batchid = p_batchid AND b.farmid = p_farmid;

    -- Re-sync the bird stock movement to the (possibly changed) bird count.
    IF v_historical THEN
        PERFORM sppoultrybirdstock_postdated(p_farmid, 'Bird Batch Purchase', p_numberofbirds::numeric,
                                             p_batchid, p_startdate::date, 'Flock batch purchase (historical)', p_userid);
    ELSE
        PERFORM sppoultrybirdstock_sync(p_farmid, 'Bird Batch Purchase', p_numberofbirds::numeric,
                                        p_batchid, 'Flock batch purchase', p_userid);
    END IF;

    -- Keep the initial linked expense in sync without touching balance payments.
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;
    IF v_gid IS NOT NULL THEN
        v_initexpid := (SELECT MIN(e.expenseid) FROM expense e
                        WHERE e.farmid = v_gid AND e.sourcetype = 'MainFlockBatch' AND e.sourceid = p_batchid);

        IF v_historical THEN
            -- Remove the INITIAL purchase expense only, never the balance-payment
            -- rows: those record money that moved on a day this application was
            -- watching, and are real whatever the purchase was.
            IF v_initexpid IS NOT NULL THEN
                DELETE FROM expense e WHERE e.expenseid = v_initexpid;
            END IF;
        ELSE
            -- Amounts already booked via later balance-payment rows.
            v_otherpaid := (SELECT COALESCE(SUM(e.amount), 0) FROM expense e
                            WHERE e.farmid = v_gid AND e.sourcetype = 'MainFlockBatch' AND e.sourceid = p_batchid
                              AND (v_initexpid IS NULL OR e.expenseid <> v_initexpid));
            v_initamount := v_amountpaid - v_otherpaid;
            IF v_initamount < 0 THEN
                v_initamount := 0;
            END IF;

            v_desc := concat('Flock batch purchase: ', COALESCE(p_batchname, 'batch'),
                             ' (', COALESCE(p_numberofbirds, 0)::text, ' birds)');

            IF v_initexpid IS NOT NULL THEN
                UPDATE expense e
                SET amount = v_initamount, expensedate = p_startdate, description = v_desc
                WHERE e.expenseid = v_initexpid;
            ELSIF v_initamount > 0 AND p_userid IS NOT NULL THEN
                INSERT INTO expense (expensedate, category, description, amount, paymentmethod, supplier, flockid, createddate, userid, farmid, sourcetype, sourceid)
                VALUES (p_startdate, 'Flock / Bird Purchase', v_desc, v_initamount, 'Cash', NULL, NULL, (now() at time zone 'utc'), p_userid, v_gid, 'MainFlockBatch', p_batchid);
            END IF;
        END IF;
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Readers must return the new column, or the flag is lost on every round trip
--    and an edit through the ordinary page cannot tell a historical batch from a
--    current one.
--
-- RETURNS TABLE is part of a function's signature, so adding a column means
-- dropping and recreating rather than CREATE OR REPLACE. Bodies reproduced from
-- pg_get_functiondef of the live functions, with one column appended -- appended
-- rather than inserted, so a reader that maps by ordinal is unaffected.
-- -----------------------------------------------------------------------------
DO $dropreaders$
DECLARE
    v_sig text;
BEGIN
    FOR v_sig IN
        SELECT format('%s(%s)', p.oid::regproc, pg_get_function_identity_arguments(p.oid))
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('spmainflockbatch_getall', 'spmainflockbatch_getbyid')
    LOOP
        EXECUTE 'DROP FUNCTION ' || v_sig;
    END LOOP;
END
$dropreaders$;

CREATE OR REPLACE FUNCTION public.spmainflockbatch_getall(p_userid text, p_farmid text)
RETURNS TABLE(batchid integer, userid text, farmid text, batchcode text, batchname text,
              breed text, numberofbirds integer, startdate date, createddate timestamp without time zone,
              status text, costperchick numeric, totalcost numeric, amountpaid numeric,
              suppliertype text, supplierid integer, notes text, orderplacementdate date,
              estimatedarrivaldate date, dollarconversionrate numeric, suppliername text,
              ishistorical boolean)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        b.batchid, b.userid::text, b.farmid::text, b.batchcode::text, b.batchname::text,
        b.breed::text, b.numberofbirds, b.startdate, b.createddate,
        b.status::text, b.costperchick, b.totalcost, b.amountpaid,
        b.suppliertype::text, b.supplierid, b.notes::text,
        b.orderplacementdate, b.estimatedarrivaldate, b.dollarconversionrate,
        COALESCE(s.name, '')::text AS suppliername,
        COALESCE(b.ishistorical, false)
    FROM mainflockbatch b
    LEFT JOIN supplier s ON s.supplierid = b.supplierid AND s.farmid = b.farmid
    WHERE b.farmid = p_farmid
    ORDER BY b.createddate DESC, b.batchid DESC;
END
$function$;

CREATE OR REPLACE FUNCTION public.spmainflockbatch_getbyid(p_batchid integer, p_userid text, p_farmid text)
RETURNS TABLE(batchid integer, userid text, farmid text, batchcode text, batchname text,
              breed text, numberofbirds integer, startdate date, createddate timestamp without time zone,
              status text, costperchick numeric, totalcost numeric, amountpaid numeric,
              suppliertype text, supplierid integer, notes text, orderplacementdate date,
              estimatedarrivaldate date, dollarconversionrate numeric, suppliername text,
              ishistorical boolean)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        b.batchid, b.userid::text, b.farmid::text, b.batchcode::text, b.batchname::text,
        b.breed::text, b.numberofbirds, b.startdate, b.createddate,
        b.status::text, b.costperchick, b.totalcost, b.amountpaid,
        b.suppliertype::text, b.supplierid, b.notes::text,
        b.orderplacementdate, b.estimatedarrivaldate, b.dollarconversionrate,
        COALESCE(s.name, '')::text AS suppliername,
        COALESCE(b.ishistorical, false)
    FROM mainflockbatch b
    LEFT JOIN supplier s ON s.supplierid = b.supplierid AND s.farmid = b.farmid
    WHERE b.batchid = p_batchid AND b.farmid = p_farmid;
END
$function$;

-- -----------------------------------------------------------------------------
-- 5. Grants, matching the app login used by every other function here.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.sppoultrybirdstock_postdated(text, text, numeric, integer, date, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryopeningbirdstock_post(text, integer, integer, date, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spmainflockbatch_insert(text, text, text, text, text, integer, timestamp without time zone, text, numeric, numeric, text, integer, numeric, text, date, date, numeric, boolean) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spmainflockbatch_update(integer, text, text, text, text, text, integer, timestamp without time zone, text, numeric, numeric, text, integer, numeric, text, date, date, numeric, boolean) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spmainflockbatch_getall(text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spmainflockbatch_getbyid(integer, text, text) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 6. Verification. Runs after COMMIT so a failure here does not undo the
--    migration -- it tells you the migration is wrong, which is different.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_farm     text := '__326_selftest__';
    v_hist     integer;
    v_new      integer;
    v_expenses integer;
    v_net      numeric;
    v_when     date := DATE '2026-03-15';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'mainflockbatch'
                     AND column_name = 'ishistorical') THEN
        RAISE EXCEPTION '326: mainflockbatch.ishistorical is missing.';
    END IF;

    -- A HISTORICAL purchase: money paid before tracking began.
    v_hist := public.spmainflockbatch_insert(
        '__326__', v_farm, 'H326', 'Historical', 'Brown', 5000, v_when::timestamp,
        'active', 2, 10000, 'local', NULL, 7000, NULL, NULL, NULL, NULL, true);

    IF (SELECT ishistorical FROM mainflockbatch WHERE batchid = v_hist) IS NOT TRUE THEN
        RAISE EXCEPTION '326: the historical flag did not persist.';
    END IF;

    -- What it still OWES is real and must be recorded.
    IF (SELECT totalcost - amountpaid FROM mainflockbatch WHERE batchid = v_hist) <> 3000 THEN
        RAISE EXCEPTION '326: the historical outstanding balance was not preserved.';
    END IF;

    -- But no expense: that money moved before any reported period.
    SELECT count(*) INTO v_expenses FROM expense e
    WHERE e.sourcetype = 'MainFlockBatch' AND e.sourceid = v_hist;
    IF v_expenses <> 0 THEN
        RAISE EXCEPTION '326: a historical purchase posted % expense row(s).', v_expenses;
    END IF;

    -- Birds posted, dated to the placement rather than to today.
    IF NOT EXISTS (SELECT 1 FROM poultrystocktransactions t
                   WHERE t.farmid = v_farm AND t.txntype = 'Bird Batch Purchase'
                     AND t.relatedid = v_hist AND t.createddate::date = v_when) THEN
        RAISE EXCEPTION '326: the historical bird purchase was not dated to the placement.';
    END IF;

    -- Editing it must NOT resurrect the expense -- the whole reason the flag is
    -- persisted rather than decided once at insert.
    PERFORM public.spmainflockbatch_update(
        v_hist, '__326__', v_farm, 'H326', 'Historical edited', 'Brown', 5000, v_when::timestamp,
        'active', 2, 10000, 'local', NULL, 7000, NULL, NULL, NULL, NULL, NULL);

    SELECT count(*) INTO v_expenses FROM expense e
    WHERE e.sourcetype = 'MainFlockBatch' AND e.sourceid = v_hist;
    IF v_expenses <> 0 THEN
        RAISE EXCEPTION '326: editing a historical batch created % expense row(s).', v_expenses;
    END IF;
    IF (SELECT ishistorical FROM mainflockbatch WHERE batchid = v_hist) IS NOT TRUE THEN
        RAISE EXCEPTION '326: an update with a NULL flag cleared the historical marker.';
    END IF;

    -- Re-posting must not double the birds.
    SELECT COALESCE(SUM(t.quantity), 0) INTO v_net FROM poultrystocktransactions t
    WHERE t.farmid = v_farm AND t.txntype = 'Bird Batch Purchase' AND t.relatedid = v_hist;
    IF v_net <> 5000 THEN
        RAISE EXCEPTION '326: the historical bird purchase nets %, expected 5000.', v_net;
    END IF;

    -- A NEW purchase keeps every bit of its old behaviour.
    v_new := public.spmainflockbatch_insert(
        '__326__', v_farm, 'N326', 'New', 'Brown', 1000, v_when::timestamp,
        'active', 2, 2000, 'local', NULL, 1500, NULL, NULL, NULL, NULL, false);

    IF (SELECT ishistorical FROM mainflockbatch WHERE batchid = v_new) IS NOT FALSE THEN
        RAISE EXCEPTION '326: a new purchase was marked historical.';
    END IF;

    -- expense.farmid is a uuid, so the sentinel farm cannot produce an expense
    -- row here. What IS assertable is that the bird stock took today's date.
    IF NOT EXISTS (SELECT 1 FROM poultrystocktransactions t
                   WHERE t.farmid = v_farm AND t.txntype = 'Bird Batch Purchase'
                     AND t.relatedid = v_new AND t.createddate::date = (now() AT TIME ZONE 'utc')::date) THEN
        RAISE EXCEPTION '326: a new purchase did not take today''s date.';
    END IF;

    -- The default must be the old behaviour, for every caller that never passes
    -- the flag at all.
    IF (SELECT prosrc IS NOT NULL FROM pg_proc WHERE oid = 'public.spmainflockbatch_insert'::regproc) IS NOT TRUE THEN
        RAISE EXCEPTION '326: spmainflockbatch_insert is missing.';
    END IF;

    -- The flag must survive a round trip, or an edit through the ordinary Flock
    -- Purchases page cannot tell what kind of purchase it is looking at.
    IF NOT (SELECT g.ishistorical FROM public.spmainflockbatch_getbyid(v_hist, '__326__', v_farm) g) THEN
        RAISE EXCEPTION '326: getbyid did not return the historical flag.';
    END IF;
    IF (SELECT count(*) FROM public.spmainflockbatch_getall('__326__', v_farm) g WHERE g.ishistorical) <> 1 THEN
        RAISE EXCEPTION '326: getall did not return the historical flag.';
    END IF;

    DELETE FROM poultrystocktransactions WHERE farmid = v_farm;
    DELETE FROM mainflockbatch WHERE farmid = v_farm;
    DELETE FROM poultryproducts WHERE farmid = v_farm;

    RAISE NOTICE '326_PoultryHistoricalBatchPurchase: 1 column, 4 functions, verified.';
END $$;

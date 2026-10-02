-- =============================================================================
-- 330_PoultryBatchCashAccount.postgres.sql
--
-- Purpose
-- -------
-- Let a flock batch purchase say which poultry cash account paid for it. Asked
-- for on the Farm Setup wizard's batch cards, under "Where did these birds come
-- from?", for both answers:
--
--   I am buying these birds now   The down payment (amountpaid) comes out of
--                                 the account: the batch's purchase expense is
--                                 filed against it, and the ordinary expense ->
--                                 cash sync (238) posts the CashOut.
--
--   I already had these birds     RECORDED ONLY. That money left before tracking
--                                 began, so the account's opening balance already
--                                 reflects it; taking it out again would count it
--                                 twice. A historical batch posts no expense
--                                 (326), so there is nothing for cash to follow.
--
-- Why the delete / rewrite paths change too
-- -----------------------------------------
-- Until now a batch's expense rows were deleted outright -- by
-- spflockbatchexpense_sync (batch delete, re-sync) and by spmainflockbatch_update
-- (a batch turned historical). That was safe only because those expenses never
-- carried a cash account. Once they do, deleting the expense would leave its
-- CashOut behind and the account short for good. So every path that removes or
-- rewrites a batch expense now reverses / re-syncs its cash first, through the
-- same sppoultryexpensecash_sync the Expenses page uses. For a batch with no
-- account -- every batch that exists today -- that call is a no-op.
--
-- The Flock Purchases edit form does not send an account, and
-- spmainflockbatch_update keeps its signature: an edit leaves the stored account
-- alone and re-syncs the cash to the new amount paid.
--
-- Bodies are reproduced from pg_get_functiondef of the LIVE functions
-- (2026-09-28), which match 326.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The column.
-- -----------------------------------------------------------------------------
ALTER TABLE mainflockbatch ADD COLUMN IF NOT EXISTS poultrycashaccountid integer NULL;

COMMENT ON COLUMN mainflockbatch.poultrycashaccountid IS
    'Poultry cash account the purchase was paid from (330). Current purchase: the amount paid is a CashOut on it. Historical purchase: recorded only.';

-- -----------------------------------------------------------------------------
-- 2. The batch expense sync: reverse cash before deleting, post it after.
--    Same signature, so grants and callers are untouched.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spflockbatchexpense_sync(
    p_farmid text, p_batchid integer, p_amount numeric, p_date timestamp without time zone,
    p_batchname text, p_numberofbirds integer, p_createdby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_gid    uuid;
    v_expid  integer;
    v_acct   integer;
BEGIN
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;
    IF v_gid IS NULL THEN
        RETURN;  -- Expense.FarmId is a GUID; skip if farmId isn't one.
    END IF;

    -- Give back any cash these rows took before they go (330). Clearing the
    -- account and re-syncing reverses the CashOut and restores the balance.
    FOR v_expid IN
        SELECT e.expenseid FROM expense e
        WHERE  e.farmid = v_gid AND e.sourcetype = 'MainFlockBatch' AND e.sourceid = p_batchid
    LOOP
        PERFORM sppoultryexpensecash_sync(p_farmid, v_expid, NULL, 0, NULL, p_createdby);
    END LOOP;

    -- Idempotent: drop any prior batch-purchase expense for this batch.
    DELETE FROM expense WHERE farmid = v_gid AND sourcetype = 'MainFlockBatch' AND sourceid = p_batchid;

    IF COALESCE(p_amount, 0) <= 0 THEN
        RETURN;
    END IF;

    INSERT INTO expense (expensedate, category, description, amount, paymentmethod, supplier, flockid, createddate, userid, farmid, sourcetype, sourceid)
    VALUES (COALESCE(p_date, (now() at time zone 'utc')), 'Flock / Bird Purchase',
            concat('Flock batch purchase: ', COALESCE(p_batchname, 'batch'), ' (', COALESCE(p_numberofbirds, 0)::text, ' birds)'),
            p_amount, 'Cash', NULL, NULL, (now() at time zone 'utc'), p_createdby, v_gid, 'MainFlockBatch', p_batchid)
    RETURNING expenseid INTO v_expid;

    -- Paid from a cash account: file the expense against it and let the
    -- ordinary expense -> cash sync post the CashOut, dated to the purchase.
    SELECT b.poultrycashaccountid INTO v_acct
    FROM   mainflockbatch b
    WHERE  b.batchid = p_batchid AND b.farmid = p_farmid;

    IF v_acct IS NOT NULL THEN
        PERFORM sppoultryexpensecash_sync(p_farmid, v_expid, v_acct, p_amount, NULL, p_createdby);
        PERFORM sppoultrycashtransaction_setbusinessdate(p_farmid, 'Expense', v_expid,
                                                         COALESCE(p_date, (now() at time zone 'utc')));
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Insert gains p_poultrycashaccountid, so the old signature is dropped first
--    (an extra defaulted argument would otherwise make an ambiguous overload).
-- -----------------------------------------------------------------------------
DO $drops$
DECLARE
    v_sig text;
BEGIN
    FOR v_sig IN
        SELECT format('%s(%s)', p.oid::regproc, pg_get_function_identity_arguments(p.oid))
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname = 'spmainflockbatch_insert'
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
    p_ishistorical boolean DEFAULT false,
    p_poultrycashaccountid integer DEFAULT NULL::integer)
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

    -- Another farm's account would move another farm's money.
    IF p_poultrycashaccountid IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM poultrycashaccounts a
        WHERE  a.poultrycashaccountid = p_poultrycashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'The selected cash account does not belong to this farm.';
    END IF;

    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, status, costperchick, totalcost, amountpaid, suppliertype, supplierid, notes, orderplacementdate, estimatedarrivaldate, dollarconversionrate, createddate, ishistorical, poultrycashaccountid)
    VALUES (p_userid, p_farmid, p_batchcode, p_batchname, p_breed, p_numberofbirds, p_startdate, COALESCE(p_status, 'active'), COALESCE(p_costperchick, 0), COALESCE(v_totalcost, 0), COALESCE(v_amountpaid, 0), p_suppliertype, p_supplierid, p_notes, p_orderplacementdate, p_estimatedarrivaldate, p_dollarconversionrate, (now() at time zone 'utc'), v_historical, p_poultrycashaccountid)
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
    -- delete-for-source is a no-op; it then posts one expense = amount paid, and
    -- (330) a CashOut on the batch's account when it has one.
    --
    -- Skipped entirely for a historical purchase: that money left the farm before
    -- any period this application reports on. What the farm still OWES is not
    -- skipped -- amountpaid is stored as given, and fnpoultrypayables derives the
    -- outstanding balance from it. Its cash account is stored, and moves nothing.
    IF NOT v_historical THEN
        PERFORM spflockbatchexpense_sync(p_farmid, v_newid, v_amountpaid, p_startdate, p_batchname, p_numberofbirds, p_userid);
    END IF;

    RETURN v_newid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Update: same signature (the edit form sends no account, and NULL here
--    would be ambiguous). Two changes only, both marked 330.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spmainflockbatch_update(
    p_batchid integer, p_userid text, p_farmid text, p_batchcode text, p_batchname text,
    p_breed text, p_numberofbirds integer, p_startdate timestamp without time zone,
    p_status text DEFAULT 'active'::text, p_costperchick numeric DEFAULT 0,
    p_totalcost numeric DEFAULT 0, p_suppliertype text DEFAULT NULL::text,
    p_supplierid integer DEFAULT NULL::integer, p_amountpaid numeric DEFAULT 0,
    p_notes text DEFAULT NULL::text, p_orderplacementdate date DEFAULT NULL::date,
    p_estimatedarrivaldate date DEFAULT NULL::date, p_dollarconversionrate numeric DEFAULT NULL::numeric,
    p_ishistorical boolean DEFAULT NULL::boolean)
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
    v_acct       integer;
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
    SELECT COALESCE(p_ishistorical, b.ishistorical, false), b.poultrycashaccountid
    INTO   v_historical, v_acct
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
                -- 330: give its cash back first, or the CashOut outlives it.
                PERFORM sppoultryexpensecash_sync(p_farmid, v_initexpid, NULL, 0, NULL, p_userid);
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
                VALUES (p_startdate, 'Flock / Bird Purchase', v_desc, v_initamount, 'Cash', NULL, NULL, (now() at time zone 'utc'), p_userid, v_gid, 'MainFlockBatch', p_batchid)
                RETURNING expenseid INTO v_initexpid;
            END IF;

            -- 330: the CashOut follows the (possibly changed) amount. Only for a
            -- batch with an account -- one without never had cash to move.
            IF v_initexpid IS NOT NULL AND v_acct IS NOT NULL THEN
                PERFORM sppoultryexpensecash_sync(p_farmid, v_initexpid, v_acct, v_initamount, NULL, p_userid);
                PERFORM sppoultrycashtransaction_setbusinessdate(p_farmid, 'Expense', v_initexpid, p_startdate);
            END IF;
        END IF;
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Grants, matching the app login used by every other function here.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.spflockbatchexpense_sync(text, integer, numeric, timestamp without time zone, text, integer, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spmainflockbatch_insert(text, text, text, text, text, integer, timestamp without time zone, text, numeric, numeric, text, integer, numeric, text, date, date, numeric, boolean, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spmainflockbatch_update(integer, text, text, text, text, text, integer, timestamp without time zone, text, numeric, numeric, text, integer, numeric, text, date, date, numeric, boolean) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

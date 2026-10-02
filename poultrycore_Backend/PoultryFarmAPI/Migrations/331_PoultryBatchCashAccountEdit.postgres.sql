-- =============================================================================
-- 331_PoultryBatchCashAccountEdit.postgres.sql
--
-- Purpose
-- -------
-- Follow-up to 330 for the Flock Purchases page, which now has the same
-- "Pay from cash account" picker as the Farm Setup wizard:
--
--   * spmainflockbatch_getall / _getbyid return the stored account (id and
--     name), so the edit form can show it. The C# reader tolerates missing
--     columns, so the API is safe on either side of this migration.
--
--   * spmainflockbatch_update gains p_poultrycashaccountid, read three ways:
--       NULL  leave the stored account alone. Every caller that does not know
--             about accounts -- the wizard's "update bird count", the detail
--             page -- keeps sending nothing, and must not clear it.
--       0     clear it. Moves the batch's cash back into the old account.
--       > 0   set it. The purchase expense's CashOut moves to that account.
--     A historical batch stores the account and moves nothing, as in 330.
--
-- Everything else in the update body is 330's, unchanged.
-- =============================================================================

BEGIN;

DO $drops$
DECLARE
    v_sig text;
BEGIN
    FOR v_sig IN
        SELECT format('%s(%s)', p.oid::regproc, pg_get_function_identity_arguments(p.oid))
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('spmainflockbatch_update', 'spmainflockbatch_getall', 'spmainflockbatch_getbyid')
    LOOP
        EXECUTE 'DROP FUNCTION ' || v_sig;
    END LOOP;
END
$drops$;

-- -----------------------------------------------------------------------------
-- 1. Reads: 326's columns plus the account.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spmainflockbatch_getall(p_userid text, p_farmid text)
RETURNS TABLE(batchid integer, userid text, farmid text, batchcode text, batchname text,
              breed text, numberofbirds integer, startdate date, createddate timestamp without time zone,
              status text, costperchick numeric, totalcost numeric, amountpaid numeric,
              suppliertype text, supplierid integer, notes text, orderplacementdate date,
              estimatedarrivaldate date, dollarconversionrate numeric, suppliername text,
              ishistorical boolean, poultrycashaccountid integer, poultrycashaccountname text)
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
        COALESCE(b.ishistorical, false),
        b.poultrycashaccountid,
        a.accountname::text
    FROM mainflockbatch b
    LEFT JOIN supplier s ON s.supplierid = b.supplierid AND s.farmid = b.farmid
    LEFT JOIN poultrycashaccounts a ON a.poultrycashaccountid = b.poultrycashaccountid AND a.farmid = b.farmid
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
              ishistorical boolean, poultrycashaccountid integer, poultrycashaccountname text)
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
        COALESCE(b.ishistorical, false),
        b.poultrycashaccountid,
        a.accountname::text
    FROM mainflockbatch b
    LEFT JOIN supplier s ON s.supplierid = b.supplierid AND s.farmid = b.farmid
    LEFT JOIN poultrycashaccounts a ON a.poultrycashaccountid = b.poultrycashaccountid AND a.farmid = b.farmid
    WHERE b.batchid = p_batchid AND b.farmid = p_farmid;
END
$function$;

-- -----------------------------------------------------------------------------
-- 2. Update: 330's body, plus the account.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spmainflockbatch_update(
    p_batchid integer, p_userid text, p_farmid text, p_batchcode text, p_batchname text,
    p_breed text, p_numberofbirds integer, p_startdate timestamp without time zone,
    p_status text DEFAULT 'active'::text, p_costperchick numeric DEFAULT 0,
    p_totalcost numeric DEFAULT 0, p_suppliertype text DEFAULT NULL::text,
    p_supplierid integer DEFAULT NULL::integer, p_amountpaid numeric DEFAULT 0,
    p_notes text DEFAULT NULL::text, p_orderplacementdate date DEFAULT NULL::date,
    p_estimatedarrivaldate date DEFAULT NULL::date, p_dollarconversionrate numeric DEFAULT NULL::numeric,
    p_ishistorical boolean DEFAULT NULL::boolean,
    p_poultrycashaccountid integer DEFAULT NULL::integer)
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

    -- 331: NULL leaves the stored account, 0 clears it, anything else sets it.
    IF p_poultrycashaccountid IS NOT NULL THEN
        IF p_poultrycashaccountid = 0 THEN
            v_acct := NULL;
        ELSE
            IF NOT EXISTS (SELECT 1 FROM poultrycashaccounts a
                           WHERE a.poultrycashaccountid = p_poultrycashaccountid AND a.farmid = p_farmid) THEN
                RAISE EXCEPTION 'The selected cash account does not belong to this farm.';
            END IF;
            v_acct := p_poultrycashaccountid;
        END IF;
    END IF;

    UPDATE mainflockbatch b
    SET batchcode = p_batchcode, batchname = p_batchname, breed = p_breed, numberofbirds = p_numberofbirds,
        startdate = p_startdate, status = COALESCE(p_status, b.status), costperchick = COALESCE(p_costperchick, 0),
        totalcost = COALESCE(v_totalcost, 0), amountpaid = COALESCE(v_amountpaid, 0), suppliertype = p_suppliertype,
        supplierid = p_supplierid, notes = p_notes,
        orderplacementdate = p_orderplacementdate, estimatedarrivaldate = p_estimatedarrivaldate,
        dollarconversionrate = p_dollarconversionrate,
        ishistorical = v_historical,
        poultrycashaccountid = v_acct
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

            -- The CashOut follows the amount and (331) the account: cleared, it
            -- is reversed; moved, it comes out of the new account instead. A
            -- batch with no account, edited by a caller that said nothing about
            -- one, is left exactly as 330 left it -- not even re-synced, so an
            -- account filed on its expense from the Expenses page survives.
            IF v_initexpid IS NOT NULL AND (v_acct IS NOT NULL OR p_poultrycashaccountid IS NOT NULL) THEN
                PERFORM sppoultryexpensecash_sync(p_farmid, v_initexpid, v_acct, v_initamount, NULL, p_userid);
                IF v_acct IS NOT NULL THEN
                    PERFORM sppoultrycashtransaction_setbusinessdate(p_farmid, 'Expense', v_initexpid, p_startdate);
                END IF;
            END IF;
        END IF;
    END IF;
END;
$function$;

DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.spmainflockbatch_update(integer, text, text, text, text, text, integer, timestamp without time zone, text, numeric, numeric, text, integer, numeric, text, date, date, numeric, boolean, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spmainflockbatch_getall(text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spmainflockbatch_getbyid(integer, text, text) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

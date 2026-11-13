-- =============================================================================
-- 436_PoultryHistoricalSalesView.postgres.sql          (requires 413, 435)
--
-- Purpose
-- -------
-- Historical bird sales can be seen, corrected and reversed from the Sales
-- page ("Before tracking" tab), without going back to Initial Farm Setup
-- (boss, 2026-11-13: "the man has a historical sale of 8,500 birds -- I don't
-- see that record shown anywhere in the system").
--
--   sppoultryhistoricalsale_list     every sale made before tracking, three kinds:
--       'Sale'         a poultryhistoricalbirdsales row (setup / reconciliation):
--                      editable and reversible.
--       'FlockOpening' a flock's opening "Sold" count not (fully) given a value:
--                      birds only; changed from the flock's opening history.
--       'Movement'     an older 'Historical Sale' bird movement with no sale row:
--                      birds only, read-only.
--   sppoultryhistoricalsale_update   date, price (or value unknown), customer,
--                      amount received, reference, notes.  NOT the birds -- a
--                      different count is Reverse, then enter it again.
--   sppoultryhistoricalsale_reverse  one sale: its birds go back to the batch's
--                      "not yet in a flock" pool, the debt it created is reversed.
--
-- MONEY RULES (unchanged from 413 / 435)
--   * Nothing here writes a sale row or cash. P&L and Cash Flow read the table
--     (435), so an edit shows there at once.
--   * The amount OWED is an opening customer debt.  Changing the owed amount or
--     the customer replaces that debt -- refused once anything has been paid on
--     it ("reverse those payments first").  A debt that was LINKED (recorded
--     separately, not created by the sale) is never changed from here.
--   * Owed with no customer = 'HistoricalUnpaidNotTracked' (no debt), as 413.
--
-- Deploy order: this migration, then the Farm API, then the web app.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

ALTER TABLE public.poultryhistoricalbirdsales ADD COLUMN IF NOT EXISTS reversalreason text;
ALTER TABLE public.poultryhistoricalbirdsales ADD COLUMN IF NOT EXISTS updatedby      text;
ALTER TABLE public.poultryhistoricalbirdsales ADD COLUMN IF NOT EXISTS updatedat      timestamp;

-- ------------------------------------------------- 1. list -----------------
CREATE OR REPLACE FUNCTION public.sppoultryhistoricalsale_list(p_farmid text)
RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH sales AS (
        SELECT jsonb_build_object(
                   'kind', 'Sale',
                   'key', 'S' || h.historicalsaleid,
                   'historicalSaleId', h.historicalsaleid,
                   'saleDate', h.saledate,
                   'batchId', h.batchid,
                   'batchName', COALESCE(b.batchname::text, 'Batch #' || h.batchid),
                   'flockId', h.flockid,
                   'flockName', f.name,
                   'scope', h.scope,
                   'birds', h.birds,
                   'pricePerBird', h.priceperbird,
                   'totalValue', h.totalvalue,
                   'valueUnknown', h.valueunknown,
                   'customerId', h.customerid,
                   'customerName', c.name,
                   'amountReceived', h.amountreceived,
                   'amountOwed', h.amountowed,
                   'financialTreatment', h.financialtreatment,
                   'debtId', h.debtid,
                   'debtNumber', d.debtnumber,
                   'debtCreated', h.debtcreated,
                   'debtPaid', CASE WHEN d.debtid IS NULL THEN 0
                                    ELSE fnpoultrycustomerdebt_paid(p_farmid, d.debtid) END,
                   'reconciliationNo', r.reconciliationno,
                   'source', r.source,
                   'reference', h.reference,
                   'notes', h.notes,
                   'status', h.status,
                   'reversalReason', h.reversalreason,
                   'createdBy', h.createdby,
                   'createdAt', h.createdat,
                   'updatedAt', h.updatedat,
                   'canEdit', h.status = 'Posted') AS j,
               h.saledate AS d, 0 AS ord, h.historicalsaleid AS id
        FROM   poultryhistoricalbirdsales h
        LEFT   JOIN mainflockbatch b ON b.batchid = h.batchid
        LEFT   JOIN flock f          ON f.flockid = h.flockid
        LEFT   JOIN customer c       ON c.customerid = h.customerid AND c.farmid = h.farmid
        LEFT   JOIN poultrycustomerdebts d ON d.debtid = h.debtid AND d.farmid = h.farmid
        LEFT   JOIN poultrybatchbirdreconciliations r ON r.reconciliationid = h.reconciliationid
        WHERE  h.farmid = p_farmid
    ),
    -- A flock's opening "Sold": the part not valued by a sale row above.
    opening AS (
        SELECT jsonb_build_object(
                   'kind', 'FlockOpening',
                   'key', 'F' || f.flockid,
                   'saleDate', COALESCE(o.effectivebusinessdate, f.startdate),
                   'batchId', f.batchid,
                   'batchName', COALESCE(b.batchname::text, CASE WHEN f.batchid IS NULL THEN NULL ELSE 'Batch #' || f.batchid END),
                   'flockId', f.flockid,
                   'flockName', f.name,
                   'scope', 'Flock',
                   'birds', o.historicalsold - COALESCE(v.valued, 0),
                   'valueUnknown', TRUE,
                   'amountReceived', 0,
                   'amountOwed', 0,
                   'financialTreatment', 'QuantityOnly',
                   'source', 'Opening position',
                   'status', 'Posted',
                   'canEdit', FALSE) AS j,
               COALESCE(o.effectivebusinessdate, f.startdate) AS d, 1 AS ord, f.flockid AS id
        FROM   poultryopeningflockposition o
        JOIN   flock f ON f.flockid = o.flockid AND f.farmid = o.farmid
        LEFT   JOIN mainflockbatch b ON b.batchid = f.batchid
        LEFT   JOIN LATERAL (
                   SELECT SUM(h.birds) AS valued FROM poultryhistoricalbirdsales h
                   WHERE  h.farmid = o.farmid AND h.flockid = f.flockid AND h.status = 'Posted') v ON TRUE
        WHERE  o.farmid = p_farmid
          AND  NOT COALESCE(f.isdeleted, FALSE)
          AND  o.historicalsold - COALESCE(v.valued, 0) > 0
    ),
    -- Older bird movements recorded as a historical sale with no sale row.
    moves AS (
        SELECT jsonb_build_object(
                   'kind', 'Movement',
                   'key', 'M' || a.birdadjustmentid,
                   'saleDate', a.adjustmentdate,
                   'batchId', a.batchid,
                   'batchName', COALESCE(b.batchname::text, CASE WHEN a.batchid IS NULL THEN NULL ELSE 'Batch #' || a.batchid END),
                   'flockId', a.flockid,
                   'flockName', f.name,
                   'scope', COALESCE(a.scope, CASE WHEN a.flockid IS NULL THEN 'BatchUnallocated' ELSE 'Flock' END),
                   'birds', abs(a.quantity),
                   'valueUnknown', TRUE,
                   'amountReceived', 0,
                   'amountOwed', 0,
                   'financialTreatment', 'QuantityOnly',
                   'source', 'Bird movement',
                   'notes', a.note,
                   'status', CASE WHEN a.reversedbyid IS NULL THEN 'Posted' ELSE 'Reversed' END,
                   'canEdit', FALSE) AS j,
               a.adjustmentdate::date AS d, 2 AS ord, a.birdadjustmentid AS id
        FROM   poultrybirdadjustments a
        LEFT   JOIN mainflockbatch b ON b.batchid = a.batchid
        LEFT   JOIN flock f ON f.flockid = a.flockid
        WHERE  a.farmid = p_farmid
          AND  a.reason IN ('Historical Sale', 'Historical Sale / Use')
          AND  a.reversesid IS NULL
          AND  NOT EXISTS (SELECT 1 FROM poultryhistoricalbirdsales h WHERE h.birdadjustmentid = a.birdadjustmentid)
    )
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.d DESC, x.ord, x.id DESC), '[]'::jsonb)
    FROM   (SELECT * FROM sales UNION ALL SELECT * FROM opening UNION ALL SELECT * FROM moves) x;
$f$;

-- ------------------------------------------------- 2. update ---------------
CREATE OR REPLACE FUNCTION public.sppoultryhistoricalsale_update(
    p_farmid text, p_historicalsaleid integer, p_saledate date,
    p_valueunknown boolean, p_priceperbird numeric, p_amountreceived numeric,
    p_customerid integer, p_reference text DEFAULT NULL, p_notes text DEFAULT NULL,
    p_by text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    h          record;
    v_today    date := fncompany_businessdate(p_farmid);
    v_batch    text;
    v_price    numeric(14,2);
    v_total    numeric(14,2);
    v_recv     numeric(14,2);
    v_owed     numeric(14,2);
    v_treat    text;
    v_debt     integer;
    v_created  boolean;
    v_paid     numeric(14,2) := 0;
    v_keepdebt boolean;
    v_res      jsonb;
BEGIN
    SELECT x.* INTO h FROM poultryhistoricalbirdsales x
    WHERE  x.historicalsaleid = p_historicalsaleid AND x.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Historical sale not found for this company.' USING ERRCODE = 'P0001';
    END IF;
    IF h.status <> 'Posted' THEN
        RAISE EXCEPTION 'This historical sale has been reversed and cannot be changed.' USING ERRCODE = 'P0001';
    END IF;
    IF p_saledate IS NULL THEN
        RAISE EXCEPTION 'Enter the date of the sale.' USING ERRCODE = 'P0001';
    END IF;
    IF p_saledate > v_today THEN
        RAISE EXCEPTION 'The date % is in the future.', p_saledate USING ERRCODE = 'P0001';
    END IF;
    IF p_customerid IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM customer c WHERE c.customerid = p_customerid AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'That customer does not belong to this company.' USING ERRCODE = 'P0001';
    END IF;

    IF COALESCE(p_valueunknown, FALSE) THEN
        v_price := NULL; v_total := NULL; v_recv := 0; v_owed := 0; v_treat := 'QuantityOnly';
    ELSE
        v_price := round(COALESCE(p_priceperbird, -1), 2);
        IF v_price < 0 THEN
            RAISE EXCEPTION 'Enter the selling price per bird, or mark the value as unknown.' USING ERRCODE = 'P0001';
        END IF;
        v_total := round(h.birds * v_price, 2);
        v_recv  := round(COALESCE(p_amountreceived, v_total), 2);
        IF v_recv < 0 OR v_recv > v_total THEN
            RAISE EXCEPTION 'Amount received (%) must be between 0 and the sale value (%).', v_recv, v_total USING ERRCODE = 'P0001';
        END IF;
        v_owed := v_total - v_recv;
    END IF;

    -- The debt that carries the owed part.
    v_debt    := h.debtid;
    v_created := h.debtcreated;
    IF v_debt IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM poultrycustomerdebts d WHERE d.debtid = v_debt AND d.farmid = p_farmid AND d.status = 'Posted') THEN
        v_debt := NULL; v_created := FALSE;          -- reversed elsewhere
    END IF;
    v_keepdebt := v_debt IS NOT NULL
                  AND v_owed = h.amountowed
                  AND p_customerid IS NOT DISTINCT FROM h.customerid;

    IF v_debt IS NOT NULL AND NOT v_keepdebt THEN
        IF NOT v_created THEN
            RAISE EXCEPTION 'The amount owed is linked to debt % recorded separately. Change or reverse that debt on Customer Debts first.',
                (SELECT d.debtnumber FROM poultrycustomerdebts d WHERE d.debtid = v_debt) USING ERRCODE = 'P0001';
        END IF;
        v_paid := fnpoultrycustomerdebt_paid(p_farmid, v_debt);
        IF v_paid > 0 THEN
            RAISE EXCEPTION '% has already been paid on debt %, so the amount owed and the customer cannot change. Reverse those payments first (Payments Received).',
                v_paid, (SELECT d.debtnumber FROM poultrycustomerdebts d WHERE d.debtid = v_debt) USING ERRCODE = 'P0001';
        END IF;
        PERFORM sppoultrycustomerdebt_reverse(p_farmid, v_debt, 'Historical bird sale corrected', p_by);
        v_debt := NULL; v_created := FALSE;
    END IF;

    SELECT COALESCE(b.batchcode::text, b.batchname::text, '#' || h.batchid) INTO v_batch
    FROM   mainflockbatch b WHERE b.batchid = h.batchid;
    v_batch := COALESCE(v_batch, '#' || h.batchid);

    IF v_treat IS NULL THEN
        IF v_owed = 0 THEN
            v_treat := 'HistoricalPaid';
        ELSIF v_debt IS NOT NULL THEN
            v_treat := 'HistoricalReceivable';
        ELSIF p_customerid IS NOT NULL THEN
            v_res := sppoultrycustomerdebt_create(p_farmid, p_customerid, v_owed, p_saledate, 'HistoricalDebt',
                         'Historical bird sale - batch ' || v_batch || ', ' || h.birds || ' birds on ' || p_saledate,
                         NULLIF(btrim(COALESCE(p_reference, '')), ''), NULLIF(btrim(COALESCE(p_notes, '')), ''), p_by);
            v_debt := (v_res->>'debtId')::int;
            v_created := TRUE;
            v_treat := 'HistoricalReceivable';
        ELSE
            v_treat := 'HistoricalUnpaidNotTracked';
        END IF;
    END IF;

    -- A kept, unpaid debt follows the new date.
    IF v_keepdebt AND v_created AND p_saledate <> h.saledate
       AND fnpoultrycustomerdebt_paid(p_farmid, v_debt) = 0 THEN
        UPDATE poultrycustomerdebts d SET debtdate = p_saledate WHERE d.debtid = v_debt;
    END IF;

    -- The birds left the batch on the sale date.
    IF h.birdadjustmentid IS NOT NULL AND p_saledate <> h.saledate THEN
        UPDATE poultrybirdadjustments a SET adjustmentdate = p_saledate
        WHERE  a.birdadjustmentid = h.birdadjustmentid AND a.farmid = p_farmid;
    END IF;

    UPDATE poultryhistoricalbirdsales x
    SET    saledate = p_saledate, priceperbird = v_price, totalvalue = v_total,
           valueunknown = COALESCE(p_valueunknown, FALSE), customerid = p_customerid,
           amountreceived = v_recv, amountowed = v_owed, financialtreatment = v_treat,
           debtid = v_debt, debtcreated = COALESCE(v_created, FALSE),
           reference = NULLIF(btrim(COALESCE(p_reference, '')), ''),
           notes = NULLIF(btrim(COALESCE(p_notes, '')), ''),
           updatedby = p_by, updatedat = (now() AT TIME ZONE 'utc')
    WHERE  x.historicalsaleid = h.historicalsaleid;

    RETURN jsonb_build_object(
        'historicalSaleId', h.historicalsaleid, 'status', 'Posted',
        'totalValue', v_total, 'amountReceived', v_recv, 'amountOwed', v_owed,
        'financialTreatment', v_treat, 'debtId', v_debt,
        'debtNumber', (SELECT d.debtnumber FROM poultrycustomerdebts d WHERE d.debtid = v_debt),
        'newCashMovement', 0);
END
$f$;

-- ------------------------------------------------- 3. reverse --------------
CREATE OR REPLACE FUNCTION public.sppoultryhistoricalsale_reverse(
    p_farmid text, p_historicalsaleid integer, p_reason text, p_by text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    h   record;
    a   record;
    v_returned integer := 0;
    v_label text;
BEGIN
    IF NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Say why this historical sale is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    SELECT x.* INTO h FROM poultryhistoricalbirdsales x
    WHERE  x.historicalsaleid = p_historicalsaleid AND x.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Historical sale not found for this company.' USING ERRCODE = 'P0001';
    END IF;
    IF h.status <> 'Posted' THEN
        RAISE EXCEPTION 'This historical sale is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    v_label := 'historical sale of ' || h.birds || ' birds on ' || h.saledate;

    -- The debt it created (refused by the debt function if anything was paid).
    IF h.debtcreated AND h.debtid IS NOT NULL AND EXISTS (
        SELECT 1 FROM poultrycustomerdebts d WHERE d.debtid = h.debtid AND d.status = 'Posted') THEN
        PERFORM sppoultrycustomerdebt_reverse(p_farmid, h.debtid, 'Reversal of ' || v_label || ': ' || btrim(p_reason), p_by);
    END IF;

    -- The birds go back to the batch's "not yet in a flock" pool -- unless the
    -- batch itself has since been deleted: there is no pool to return them to.
    IF h.birdadjustmentid IS NOT NULL AND EXISTS (
        SELECT 1 FROM mainflockbatch mb WHERE mb.batchid = h.batchid AND mb.farmid = p_farmid) THEN
        SELECT x.* INTO a FROM poultrybirdadjustments x
        WHERE  x.birdadjustmentid = h.birdadjustmentid AND x.farmid = p_farmid AND x.reversedbyid IS NULL;
        IF FOUND THEN
            PERFORM sppoultrybirdmovement_post(p_farmid, 'BatchUnallocated', a.batchid, NULL, 'Reversal', -a.quantity,
                        fncompany_businessdate(p_farmid), 'Reversal',
                        left('Reversal of ' || v_label || ': ' || btrim(p_reason), 500),
                        'HistoricalSaleReversal', h.historicalsaleid, NULL, p_by, a.birdadjustmentid);
            v_returned := h.birds;
        END IF;
    END IF;

    UPDATE poultryhistoricalbirdsales x
    SET    status = 'Reversed', reversedat = (now() AT TIME ZONE 'utc'), reversedby = p_by,
           reversalreason = btrim(p_reason)
    WHERE  x.historicalsaleid = h.historicalsaleid;

    RETURN jsonb_build_object('historicalSaleId', h.historicalsaleid, 'status', 'Reversed',
                              'birdsReturned', v_returned,
                              'unallocatedNow', CASE WHEN EXISTS (SELECT 1 FROM mainflockbatch mb WHERE mb.batchid = h.batchid AND mb.farmid = p_farmid)
                                                     THEN fnpoultrybatch_unallocated(p_farmid, h.batchid) END);
END
$f$;

DO $grant$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.sppoultryhistoricalsale_list(text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryhistoricalsale_update(text, integer, date, boolean, numeric, numeric, integer, text, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryhistoricalsale_reverse(text, integer, text, text) TO poultryapp;
    END IF;
END
$grant$;

-- ------------------------------------------------- 4. self-test ------------
-- On a copy of a real paid sale (all inside this transaction, rolled back by
-- the test itself): edit to part-paid with a customer -> a debt appears and
-- P&L follows the amount received; reverse -> birds back in the pool, debt
-- reversed, P&L line gone.
DO $test$
DECLARE
    h        record;
    v_cust   integer;
    v_pool0  integer;
    v_pool1  integer;
    v_pl     numeric;
    v_res    jsonb;
    v_list   jsonb;
BEGIN
    SELECT x.* INTO h FROM poultryhistoricalbirdsales x
    WHERE  x.status = 'Posted' AND NOT x.valueunknown AND x.amountowed = 0
      AND  x.birdadjustmentid IS NOT NULL AND x.scope = 'BatchUnallocated'
      AND  EXISTS (SELECT 1 FROM mainflockbatch mb WHERE mb.batchid = x.batchid AND mb.farmid = x.farmid)
    ORDER  BY x.historicalsaleid LIMIT 1;
    IF NOT FOUND THEN
        RAISE NOTICE '436 self-test: no paid batch-level historical sale to test on -- skipped.';
        RETURN;
    END IF;
    SELECT c.customerid INTO v_cust FROM customer c WHERE c.farmid = h.farmid ORDER BY c.customerid LIMIT 1;

    BEGIN
        v_list := sppoultryhistoricalsale_list(h.farmid);
        IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_list) e WHERE (e->>'historicalSaleId')::int = h.historicalsaleid) THEN
            RAISE EXCEPTION '436 self-test: sale % missing from the list', h.historicalsaleid;
        END IF;

        IF v_cust IS NOT NULL THEN
            v_res := sppoultryhistoricalsale_update(h.farmid, h.historicalsaleid, h.saledate, FALSE,
                         h.priceperbird, h.totalvalue - 100, v_cust, h.reference, h.notes, 'selftest');
            IF (v_res->>'amountOwed')::numeric <> 100 OR v_res->>'debtId' IS NULL THEN
                RAISE EXCEPTION '436 self-test: part-paid edit did not create a 100 debt: %', v_res;
            END IF;
            SELECT COALESCE(SUM(amount), 0) INTO v_pl FROM sppoultryreport_pllines(h.farmid, h.saledate, h.saledate)
            WHERE linekey = 'HistoricalBirdSales';
            IF v_pl <> (SELECT SUM(x.amountreceived) FROM poultryhistoricalbirdsales x
                        WHERE x.farmid = h.farmid AND x.saledate = h.saledate AND x.status = 'Posted' AND NOT x.valueunknown) THEN
                RAISE EXCEPTION '436 self-test: P&L % does not follow the edited amount received', v_pl;
            END IF;
            -- back to fully paid: the debt it created is reversed again
            v_res := sppoultryhistoricalsale_update(h.farmid, h.historicalsaleid, h.saledate, FALSE,
                         h.priceperbird, NULL, v_cust, h.reference, h.notes, 'selftest');
            IF (v_res->>'amountOwed')::numeric <> 0 OR v_res->>'debtId' IS NOT NULL THEN
                RAISE EXCEPTION '436 self-test: back to paid kept a debt: %', v_res;
            END IF;
        END IF;

        v_pool0 := fnpoultrybatch_unallocated(h.farmid, h.batchid);
        v_res   := sppoultryhistoricalsale_reverse(h.farmid, h.historicalsaleid, 'self-test', 'selftest');
        v_pool1 := fnpoultrybatch_unallocated(h.farmid, h.batchid);
        IF v_pool1 - v_pool0 <> h.birds THEN
            RAISE EXCEPTION '436 self-test: reverse returned % birds to the pool, expected %', v_pool1 - v_pool0, h.birds;
        END IF;
        IF EXISTS (SELECT 1 FROM fnpoultrypl_historicalsales(h.farmid, NULL, NULL) s WHERE s.historicalsaleid = h.historicalsaleid) THEN
            RAISE EXCEPTION '436 self-test: a reversed sale is still in P&L';
        END IF;

        RAISE EXCEPTION 'selftest-ok';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'selftest-ok' THEN RAISE; END IF;
    END;
    RAISE NOTICE '436 self-test passed on historical sale % (changes undone).', h.historicalsaleid;
END
$test$;

COMMIT;

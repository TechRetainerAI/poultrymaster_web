-- =============================================================================
-- 458  Water: a saved sale is never deleted or edited -- it is REVERSED
--      (the Water port of poultry 351/354)               (requires 423-431)
-- =============================================================================
--
-- WHY
-- ---
-- A Water sale takes its stock out the moment it is saved, and its payments
-- and applied credit hang off it. Until now it could then be:
--
--   * DELETED -- spwatersale_delete removed the sale, its stock rows and even
--     its POSTED payments, and left their allocation rows pointing at nothing;
--   * CANCELLED -- spwatersale_cancel put the stock back but left the payments
--     Posted (still on Cash Flow and in the daily closing), could run twice
--     (stock returned twice), and recorded neither a reason nor a person.
--
-- And reversing a DRIVER RETURN cancelled its delivery sales but only wrote
-- "[Reversed ...]" into their payments' note: the payments stayed Posted, so
-- Cash Flow kept counting delivery money the business had taken back out
-- (dev: 22 payments, 81,314, on 14 sales of returns never re-approved).
--
-- THE RULE FROM HERE ON
-- ---------------------
-- A saved sale's content does not change. A wrong sale is REVERSED, and if
-- needed entered again as a new sale linked to it (Edit & repost). Nothing is
-- deleted. The reversal:
--   * puts back exactly the stock the sale took out (once -- a second
--     reversal is refused);
--   * releases every allocation applied to the sale -- applied customer credit
--     goes back to the customer;
--   * handles each payment on the sale as the user chooses:
--       ReversePayment  the payment is Reversed (water customer payments post
--                       no cash, so this is a status change; Cash Flow shows
--                       the receipt on its day and the reversal on the day of
--                       the reversal);
--       KeepAsCredit    the payment stays Posted (the money WAS received) and
--                       the customer gets a 'SaleReversalCredit' credit row for
--                       it -- credit, not money: never a receipt again;
--     A payment taken on Customer Balances (it may pay other sales) can only be
--     kept as credit; a walk-in sale has nobody to hold credit, so reverse only.
--   * records WSR-00001 (who, when, reason from the list, what happened to
--     each payment) and marks the sale.
--
-- STATUS: A REVERSED SALE IS 'Cancelled' + salereversalid
-- ------------------------------------------------------
-- Every Water reader already excludes status 'Cancelled' (P&L, daily closing,
-- balances, statement, Cash Flow, dashboards ...). Using a new 'Reversed'
-- value would slip through all ~20 of them; reusing 'Cancelled' and marking
-- the reversal (salereversalid, reversedat/by, reason) keeps every one right
-- and keeps any FUTURE reader right by the existing convention. The screen
-- shows "Reversed" whenever salereversalid is set. Older 'Cancelled' sales
-- (no salereversalid) stay as they are.
--
-- HOW THE LOCK IS ENFORCED
-- ------------------------
--   * spwatersale_delete and spwatersale_cancel refuse, with the reason.
--   * trg_watersale_guard refuses at the table: a delete, a change to what was
--     sold / to whom / for how much / when, and any change to a reversed sale.
--     It lets through: the transaction that INSERTED the sale (create shapes it
--     in several statements), the reversal (GUC water.sale_system), and
--     delivery sales (the driver return owns them). amountpaid and the payment
--     states of status stay writable -- spwatersale_recompute maintains them.
--   * trg_watersaleitem_guard does the same for the lines.
--
-- ALSO IN HERE (each a reader that would otherwise get this wrong)
--   * spwaterdriverreturn_reverse reverses its sales' payments + allocations.
--   * spwatercashflow_rows: a reversed customer payment keeps its receipt on
--     its own day and adds a negative row on the reversal day (append-only,
--     like supplier payments in 421). This also applies to payments reversed
--     before today: they used to vanish from their original period.
--   * fnwaterdailyclosing_livetotals: a payment on a cancelled/reversed sale
--     made the same day is NOT already in the day's sales any more, so it
--     counts as a collection; SaleReversalCredit is never a collection.
--   * spwatersale_recompute leaves a reversed sale alone; spwaterpayment_record
--     refuses a cancelled sale; spwatercustomerpayment_reverse refuses a
--     reversal credit (refund it instead); fnwaterbalanceaudit skips cancelled
--     sales; payment history / credit events show the new credit properly.
--   * water.sales.approve seeded from water.sales.delete (POST .../reverse
--     resolves to `approve`).
--
-- Legacy data (payments still Posted on sales cancelled before this) is NOT
-- touched here -- see 459.
--
-- DEPLOY ORDER: migration, then API, then web. The old API's Delete / Cancel
-- calls are refused with a readable message once this is applied.
-- Idempotent. PostgreSQL. Dry-run with database/apply-water-sale-reversal.ps1.
-- =============================================================================

BEGIN;

-- ------------------------------------------------------------------ 1. schema --

ALTER TABLE public.watersales ADD COLUMN IF NOT EXISTS reversedat     timestamp NULL;
ALTER TABLE public.watersales ADD COLUMN IF NOT EXISTS reversedby     text      NULL;
ALTER TABLE public.watersales ADD COLUMN IF NOT EXISTS reversalreason text      NULL;
ALTER TABLE public.watersales ADD COLUMN IF NOT EXISTS salereversalid integer   NULL;
ALTER TABLE public.watersales ADD COLUMN IF NOT EXISTS correctssaleid integer   NULL;
CREATE INDEX IF NOT EXISTS ix_watersales_correctssale ON public.watersales (correctssaleid) WHERE correctssaleid IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.watersalereversals (
    salereversalid    serial        PRIMARY KEY,
    farmid            text          NOT NULL,
    reversalnumber    text          NOT NULL,
    watersaleid       integer       NOT NULL,
    watercustomerid   integer       NULL,
    customername      text          NULL,
    saledate          timestamp     NULL,
    reasoncode        text          NULL,
    reason            text          NOT NULL,
    businessdate      date          NOT NULL,
    occurredat        timestamp     NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    reversedby        text          NULL,
    paymenthandling   text          NOT NULL,
    totalamount       numeric(14,2) NOT NULL DEFAULT 0,
    paidamount        numeric(14,2) NOT NULL DEFAULT 0,
    outstandingamount numeric(14,2) NOT NULL DEFAULT 0,
    creditcreated     numeric(14,2) NOT NULL DEFAULT 0,
    creditreleased    numeric(14,2) NOT NULL DEFAULT 0,
    paymentsreversed  numeric(14,2) NOT NULL DEFAULT 0,
    correctionsaleid  integer       NULL,
    idempotencykey    text          NULL,
    snapshot          jsonb         NULL,
    CONSTRAINT ck_watersalereversals_handling
        CHECK (paymenthandling IN ('None', 'KeepAsCredit', 'ReversePayment', 'Mixed'))
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_watersalereversals_number ON public.watersalereversals (farmid, reversalnumber);
CREATE UNIQUE INDEX IF NOT EXISTS ux_watersalereversals_idem   ON public.watersalereversals (farmid, idempotencykey) WHERE idempotencykey IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_watersalereversals_sale   ON public.watersalereversals (farmid, watersaleid);

CREATE TABLE IF NOT EXISTS public.watersalereversalpayments (
    salereversalpaymentid serial        PRIMARY KEY,
    salereversalid        integer       NOT NULL REFERENCES public.watersalereversals (salereversalid),
    farmid                text          NOT NULL,
    paymentgroupid        uuid          NOT NULL,
    paymentnumbers        text          NULL,
    sourcetype            text          NULL,
    amount                numeric(14,2) NOT NULL,
    action                text          NOT NULL,
    creditpaymentid       integer       NULL,     -- the SaleReversalCredit row KeepAsCredit wrote
    CONSTRAINT ck_watersalereversalpayments_action CHECK (action IN ('KeepAsCredit', 'ReversePayment'))
);
CREATE INDEX IF NOT EXISTS ix_watersalereversalpayments_rev ON public.watersalereversalpayments (salereversalid);

-- ---------------------------------------------- 2. the reversal-credit kind --
-- Money received on a sale that was then reversed, kept for the customer.
-- Credit (applied / refunded like any credit) but NOT money received: the
-- original payment, which stays Posted, is the receipt.
CREATE OR REPLACE FUNCTION public.fnwater_iscreditkind(p_kind text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $f$
    SELECT COALESCE(p_kind, '') IN ('Deposit', 'Overpayment', 'OpeningCredit', 'CreditNote', 'SaleReversalCredit');
$f$;

CREATE OR REPLACE FUNCTION public.fnwater_isnocashcredit(p_kind text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $f$
    SELECT COALESCE(p_kind, '') IN ('OpeningCredit', 'CreditNote', 'SaleReversalCredit');
$f$;

ALTER TABLE public.waterpayments DROP CONSTRAINT IF EXISTS ck_waterpayments_saleorcredit;
ALTER TABLE public.waterpayments ADD CONSTRAINT ck_waterpayments_saleorcredit CHECK (
       (watersaleid IS NOT NULL AND waterdebtid IS NULL)
    OR (watersaleid IS NULL AND waterdebtid IS NOT NULL AND watercustomerid IS NOT NULL)
    OR (watersaleid IS NULL AND waterdebtid IS NULL AND watercustomerid IS NOT NULL
        AND sourcetype::text IN ('Deposit', 'Overpayment', 'OpeningCredit', 'CreditNote', 'SaleReversalCredit')));

-- ------------------------------------------------------- 3. drop what changes --
DO $d$
DECLARE r record;
BEGIN
    FOR r IN SELECT p.oid::regprocedure AS sig
             FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE  n.nspname = 'public'
               AND  p.proname IN ('fnwatersale_reversalstate', 'spwatersale_reversalpreview', 'spwatersale_reverse',
                                  'spwatersale_reversalget', 'spwatersale_linkcorrection',
                                  'spwatersale_getall', 'spwatersale_getbyid_rs1',
                                  'trg_watersale_guard_fn', 'trg_watersaleitem_guard_fn')
    LOOP EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE'; END LOOP;
END $d$;

-- ------------------------------------------------------------- 4. the lock --

CREATE FUNCTION public.trg_watersale_guard_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $f$
DECLARE
    v_fresh text := COALESCE(current_setting('water.sale_fresh', true), '');
    v_id    integer := COALESCE(NEW.watersaleid, OLD.watersaleid);
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- This transaction may finish shaping the sale it is creating.
        PERFORM set_config('water.sale_fresh', v_fresh || ',' || NEW.watersaleid::text || ',', true);
        RETURN NEW;
    END IF;

    IF current_setting('water.sale_system', true) = 'on'
       OR position(',' || v_id::text || ',' IN v_fresh) > 0
       OR COALESCE(OLD.sourcetype, '') = 'DeliveryRun' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Sale #% is saved and cannot be deleted. Reverse it instead -- the sale stays in the history and its stock and money are undone.', OLD.watersaleid
            USING ERRCODE = 'P0001';
    END IF;

    IF OLD.salereversalid IS NOT NULL THEN
        RAISE EXCEPTION 'Sale #% has been reversed and can no longer be changed.', OLD.watersaleid
            USING ERRCODE = 'P0001';
    END IF;

    IF NEW.farmid          IS DISTINCT FROM OLD.farmid
       OR NEW.saledate     IS DISTINCT FROM OLD.saledate
       OR NEW.totalamount  IS DISTINCT FROM OLD.totalamount
       OR (NEW.watercustomerid IS DISTINCT FROM OLD.watercustomerid AND OLD.watercustomerid IS NOT NULL)
       OR NEW.sourcetype   IS DISTINCT FROM OLD.sourcetype
       OR NEW.sourceid     IS DISTINCT FROM OLD.sourceid
       OR NEW.salereversalid IS DISTINCT FROM OLD.salereversalid
       OR NEW.reversedat   IS DISTINCT FROM OLD.reversedat
       OR (NEW.status = 'Cancelled' AND OLD.status IS DISTINCT FROM 'Cancelled')
       OR (OLD.status = 'Cancelled' AND NEW.status IS DISTINCT FROM 'Cancelled') THEN
        RAISE EXCEPTION 'Sale #% is saved, so what was sold, to whom, when and for how much can no longer be changed. Reverse the sale (Edit & repost enters it again).', OLD.watersaleid
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END
$f$;

DROP TRIGGER IF EXISTS trg_watersale_guard ON public.watersales;
CREATE TRIGGER trg_watersale_guard
    BEFORE INSERT OR UPDATE OR DELETE ON public.watersales
    FOR EACH ROW EXECUTE FUNCTION public.trg_watersale_guard_fn();

CREATE FUNCTION public.trg_watersaleitem_guard_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $f$
DECLARE
    v_fresh text := COALESCE(current_setting('water.sale_fresh', true), '');
    v_id    integer := COALESCE(NEW.watersaleid, OLD.watersaleid);
BEGIN
    IF current_setting('water.sale_system', true) = 'on'
       OR position(',' || v_id::text || ',' IN v_fresh) > 0
       OR EXISTS (SELECT 1 FROM watersales s WHERE s.watersaleid = v_id AND COALESCE(s.sourcetype, '') = 'DeliveryRun')
       OR NOT EXISTS (SELECT 1 FROM watersales s WHERE s.watersaleid = v_id) THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    RAISE EXCEPTION 'Sale #% is saved, so its lines can no longer be changed. Reverse the sale (Edit & repost enters it again).', v_id
        USING ERRCODE = 'P0001';
END
$f$;

DROP TRIGGER IF EXISTS trg_watersaleitem_guard ON public.watersaleitems;
CREATE TRIGGER trg_watersaleitem_guard
    BEFORE INSERT OR UPDATE OR DELETE ON public.watersaleitems
    FOR EACH ROW EXECUTE FUNCTION public.trg_watersaleitem_guard_fn();

CREATE OR REPLACE FUNCTION public.spwatersale_delete(p_watersaleid integer, p_farmid text)
RETURNS void
LANGUAGE plpgsql
AS $f$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM watersales s WHERE s.watersaleid = p_watersaleid AND s.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Sale not found.' USING ERRCODE = 'P0001';
    END IF;
    -- 458: nothing saved is deleted any more.
    RAISE EXCEPTION 'Sale #% is saved and cannot be deleted. Reverse it instead -- the sale stays in the history and its stock and money are undone.', p_watersaleid
        USING ERRCODE = 'P0001';
END
$f$;

CREATE OR REPLACE FUNCTION public.spwatersale_cancel(p_watersaleid integer, p_farmid text)
RETURNS void
LANGUAGE plpgsql
AS $f$
BEGIN
    -- 458: Cancel left the payments Posted and could run twice. Reverse does it properly.
    RAISE EXCEPTION 'Cancel has been replaced by Reverse: reverse sale #% instead (it also handles its payments).', p_watersaleid
        USING ERRCODE = 'P0001';
END
$f$;

-- ------------------------------------------------------ 5. reversal state --

-- Everything the preview shows and the reversal re-checks, from the database
-- alone. Same JSON shape as fnpoultrysale_reversalstate so the web dialog is
-- shared.
CREATE FUNCTION public.fnwatersale_reversalstate(p_farmid text, p_saleid integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $f$
DECLARE
    v_s        record;
    v_blockers jsonb := '[]'::jsonb;
    v_lines    jsonb;
    v_money    jsonb;
    v_credit   numeric(14,2);
    v_fp       text;
BEGIN
    SELECT s.*, c.name::text AS customername
    INTO   v_s
    FROM   watersales s
    LEFT   JOIN watercustomers c ON c.watercustomerid = s.watercustomerid AND c.farmid = s.farmid
    WHERE  s.watersaleid = p_saleid AND s.farmid = p_farmid;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', false,
               'blockers', jsonb_build_array(jsonb_build_object('code', 'NotFound',
                           'message', 'This sale was not found for this company.')),
               'payments', '[]'::jsonb, 'lines', '[]'::jsonb);
    END IF;

    -- ---- blockers
    IF v_s.salereversalid IS NOT NULL THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'AlreadyReversed',
                      'message', 'This sale has already been reversed.');
    ELSIF v_s.status = 'Cancelled' THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'AlreadyCancelled',
                      'message', 'This sale was cancelled before reversals existed; there is nothing left to reverse.');
    END IF;
    IF COALESCE(v_s.sourcetype, '') = 'DeliveryRun' THEN
        v_blockers := v_blockers || jsonb_build_object('code', 'GeneratedSale',
                      'message', 'This sale was created by driver return #' || COALESCE(v_s.sourceid::text, '?')
                                 || '. Reverse that driver return instead -- it owns this sale.');
    END IF;

    -- ---- stock to restore, from the sale's own movements
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'saleId', p_saleid, 'product', p.name, 'quantity', si.quantity,
               'unitPrice', si.unitprice, 'total', si.linetotal, 'size', si.sellingunit,
               'restoreProductId', si.waterproductid, 'restoreProductName', p.name,
               'restoreQuantity', COALESCE(mv.qty, 0), 'restoreUnit', COALESCE(si.sellingunit, p.unit, 'units'))
             ORDER BY si.watersaleitemid), '[]'::jsonb)
    INTO   v_lines
    FROM   watersaleitems si
    LEFT   JOIN waterproducts p ON p.waterproductid = si.waterproductid
    LEFT   JOIN LATERAL (
        SELECT (-SUM(t.quantity))::numeric(14,3) AS qty
        FROM   waterstocktransactions t
        WHERE  t.farmid = p_farmid AND t.relatedsaleid = p_saleid
          AND  t.waterproductid = si.waterproductid AND t.txntype IN ('Sale', 'Return')) mv ON TRUE
    WHERE  si.watersaleid = p_saleid;

    -- ---- applied customer credit: always goes back to the customer
    v_credit := public.fnwatersale_creditapplied(p_farmid, p_saleid);

    -- ---- payments on the sale, one item per payment group
    WITH g AS (
        SELECT p.paymentgroupid,
               string_agg(DISTINCT p.paymentnumber, ', ') AS numbers,
               MIN(p.sourcetype) AS sourcetype,
               MIN(p.watercustomerid) AS customerid,
               MIN(p.paymentdate) AS paymentdate,
               MIN(p.paymentmethod) AS paymentmethod,
               SUM(p.amount)::numeric(14,2) AS allocated
        FROM   waterpayments p
        WHERE  p.farmid = p_farmid AND p.watersaleid = p_saleid
          AND  COALESCE(p.status, 'Posted') = 'Posted'
        GROUP  BY p.paymentgroupid
    ), w AS (
        SELECT g.*,
               (SELECT SUM(p.amount) FROM waterpayments p
                WHERE p.paymentgroupid = g.paymentgroupid AND p.farmid = p_farmid
                  AND COALESCE(p.status, 'Posted') = 'Posted')::numeric(14,2) AS grouptotal,
               -- Wholly this sale's: every Posted row of the group is on this
               -- sale and nothing of it was applied or refunded elsewhere.
               (NOT EXISTS (SELECT 1 FROM waterpayments p
                            WHERE p.paymentgroupid = g.paymentgroupid AND p.farmid = p_farmid
                              AND COALESCE(p.status, 'Posted') = 'Posted'
                              AND p.watersaleid IS DISTINCT FROM p_saleid)
                AND NOT EXISTS (SELECT 1 FROM customerpaymentallocation ca
                                JOIN waterpayments p ON p.waterpaymentid = ca.paymentid AND p.farmid = ca.farmid
                                WHERE p.paymentgroupid = g.paymentgroupid AND p.farmid = p_farmid
                                  AND ca.module IN ('water', 'water-debt') AND ca.status = 'Posted'
                                  AND ca.saleid IS DISTINCT FROM p_saleid)
                AND NOT EXISTS (SELECT 1 FROM watercustomerrefundlines rl
                                JOIN waterpayments p ON p.waterpaymentid = rl.waterpaymentid AND p.farmid = rl.farmid
                                WHERE p.paymentgroupid = g.paymentgroupid AND p.farmid = p_farmid)) AS wholly
        FROM g
    ), e AS (
        -- Taken at the sale (Sales page, or before 421 when no source was kept).
        -- A Customer Balances payment is the customer's own event: never undone
        -- by reversing one of the sales it paid.
        SELECT w.*, w.wholly AND COALESCE(w.sourcetype, 'SaleEntry') = 'SaleEntry' AS exclusive
        FROM   w
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'key', e.paymentgroupid::text,
               'paymentGroupId', e.paymentgroupid,
               'paymentNumbers', e.numbers,
               'source', COALESCE(e.sourcetype, 'SaleEntry'),
               'saleGenerated', e.exclusive,
               'allocated', e.allocated,
               'paymentTotal', e.grouptotal,
               'paymentDate', e.paymentdate,
               'paymentMethod', e.paymentmethod,
               'cashAccountId', NULL,
               'cashAccountName', NULL,
               'customerId', e.customerid,
               'recordedAtReversal', false,
               'allowed', CASE
                   WHEN e.exclusive AND v_s.watercustomerid IS NOT NULL THEN '["KeepAsCredit","ReversePayment"]'::jsonb
                   WHEN e.exclusive THEN '["ReversePayment"]'::jsonb
                   ELSE '["KeepAsCredit"]'::jsonb END,
               'default', CASE WHEN v_s.watercustomerid IS NULL AND e.exclusive THEN 'ReversePayment' ELSE 'KeepAsCredit' END,
               'reverseUnavailableReason', CASE
                   WHEN NOT e.wholly AND COALESCE(e.sourcetype, 'SaleEntry') = 'SaleEntry'
                        THEN 'This payment also pays other sales, so only this sale''s part is released -- as customer credit.'
                   WHEN NOT e.exclusive
                        THEN 'This payment was taken on Customer Balances and may pay other sales. Reversing the sale keeps this sale''s part as customer credit and leaves the payment as it is.'
                   END)
             ORDER BY e.paymentdate), '[]'::jsonb)
    INTO   v_money
    FROM   e;

    -- ---- fingerprint: anything that changes what the reversal would do
    SELECT md5(COALESCE(string_agg(t, '|' ORDER BY t), '')) INTO v_fp
    FROM (
        SELECT 's' || s.watersaleid || ':' || s.status || ':' || s.totalamount || ':' || COALESCE(s.amountpaid, 0)
               || ':' || COALESCE(s.salereversalid, 0) AS t
        FROM   watersales s WHERE s.farmid = p_farmid AND s.watersaleid = p_saleid
        UNION ALL
        SELECT 'a' || ca.allocationid || ':' || ca.status || ':' || ca.amountapplied
        FROM   customerpaymentallocation ca
        WHERE  ca.module = 'water' AND ca.farmid = p_farmid AND ca.saleid = p_saleid
        UNION ALL
        SELECT 'p' || p.waterpaymentid || ':' || COALESCE(p.status, 'Posted') || ':' || p.amount
        FROM   waterpayments p
        WHERE  p.farmid = p_farmid AND p.paymentgroupid IN (
                   SELECT p2.paymentgroupid FROM waterpayments p2 WHERE p2.farmid = p_farmid AND p2.watersaleid = p_saleid)
    ) z;

    RETURN jsonb_build_object(
        'found', true,
        'saleId', p_saleid,
        'saleIds', jsonb_build_array(p_saleid),
        'saleGroupNo', NULL,
        'saleDate', v_s.saledate,
        'customerId', v_s.watercustomerid,
        'customerName', COALESCE(v_s.customername, 'Walk-in'),
        'total', v_s.totalamount,
        'paid', COALESCE((SELECT SUM((m->>'allocated')::numeric) FROM jsonb_array_elements(v_money) m), 0) + v_credit,
        'creditApplied', v_credit,
        'outstanding', GREATEST(v_s.totalamount - v_s.amountpaid, 0),
        'lines', v_lines,
        'payments', v_money,
        'customerCreditNow', CASE WHEN v_s.watercustomerid IS NULL THEN 0
                                  ELSE public.fnwatercustomer_credit(p_farmid, v_s.watercustomerid) END,
        'blockers', v_blockers,
        'fingerprint', v_fp);
END
$f$;

CREATE FUNCTION public.spwatersale_reversalpreview(p_farmid text, p_saleid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $f$
    SELECT st || jsonb_build_object(
             'defaultCreditCreated', COALESCE((SELECT SUM((m->>'allocated')::numeric) FROM jsonb_array_elements(st->'payments') m
                                               WHERE m->>'default' = 'KeepAsCredit'), 0),
             'defaultCashOut',       COALESCE((SELECT SUM((m->>'allocated')::numeric) FROM jsonb_array_elements(st->'payments') m
                                               WHERE m->>'default' = 'ReversePayment'), 0))
    FROM   (SELECT public.fnwatersale_reversalstate(p_farmid, p_saleid) AS st) q;
$f$;

-- ------------------------------------------------------------ 6. the reversal --

CREATE FUNCTION public.spwatersale_reverse(p_farmid text, p_saleid integer, p_reasoncode text, p_reason text,
                                           p_handling jsonb DEFAULT '{}'::jsonb, p_expectedfingerprint text DEFAULT NULL,
                                           p_idempotencykey text DEFAULT NULL, p_reversedby text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $f$
DECLARE
    v_now      timestamp := (now() AT TIME ZONE 'utc');
    v_today    date      := fncompany_businessdate(p_farmid);
    v_state    jsonb;
    v_item     jsonb;
    v_action   text;
    v_group    uuid;
    v_reason   text;
    v_id       integer;
    v_existing integer;
    v_number   text;
    v_credit   numeric(14,2) := 0;
    v_back     numeric(14,2) := 0;
    v_kinds    text[] := ARRAY[]::text[];
    v_amt      numeric(14,2);
    v_cpid     integer;
    v_cust     integer;
BEGIN
    -- 354's rule: a reason from the list is enough; "Other" needs a few words.
    IF NULLIF(btrim(COALESCE(p_reasoncode, '')), '') IS NULL AND NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for reversing this sale.' USING ERRCODE = 'P0001';
    END IF;
    IF lower(btrim(COALESCE(p_reasoncode, ''))) = 'other' AND NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Say in a few words what happened (the reason is "Other").' USING ERRCODE = 'P0001';
    END IF;
    v_reason := concat_ws(': ', NULLIF(btrim(COALESCE(p_reasoncode, '')), ''), NULLIF(btrim(COALESCE(p_reason, '')), ''));

    PERFORM pg_advisory_xact_lock(hashtext('water-salereversal:' || p_farmid || ':' || p_saleid::text));
    PERFORM 1 FROM watersales s WHERE s.farmid = p_farmid AND s.watersaleid = p_saleid FOR UPDATE;

    IF p_idempotencykey IS NOT NULL THEN
        SELECT r.salereversalid INTO v_existing FROM watersalereversals r
        WHERE  r.farmid = p_farmid AND r.idempotencykey = p_idempotencykey;
        IF FOUND THEN RETURN v_existing; END IF;
    END IF;

    v_state := fnwatersale_reversalstate(p_farmid, p_saleid);
    IF jsonb_array_length(v_state->'blockers') > 0 THEN
        RAISE EXCEPTION '%', v_state->'blockers'->0->>'message' USING ERRCODE = 'P0001';
    END IF;
    IF p_expectedfingerprint IS NOT NULL AND p_expectedfingerprint <> v_state->>'fingerprint' THEN
        RAISE EXCEPTION 'This sale changed after the reversal preview was generated. Please review the updated impact before continuing.'
            USING ERRCODE = 'P0001', HINT = 'stale-preview';
    END IF;
    v_cust := (v_state->>'customerId')::int;

    -- Validate every choice before changing anything.
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_state->'payments') LOOP
        v_action := COALESCE(p_handling->>(v_item->>'key'), v_item->>'default');
        IF NOT (v_item->'allowed') ? v_action THEN
            RAISE EXCEPTION '%', CASE
                WHEN v_action = 'ReversePayment' THEN COALESCE(v_item->>'reverseUnavailableReason',
                     'Payment ' || COALESCE(v_item->>'paymentNumbers', '') || ' cannot be reversed with this sale.')
                ELSE 'This sale has no customer to hold the money as credit, so the money received can only be reversed.' END
                USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    PERFORM set_config('water.sale_system', 'on', true);

    -- 1. Applied customer credit is the customer's again.
    v_back := COALESCE((v_state->>'creditApplied')::numeric, 0);
    PERFORM public.fnwatersale_releasecredit(p_farmid, p_saleid, p_reversedby, 'Sale reversed: ' || v_reason);

    -- 2. Release every other allocation applied to the sale.
    UPDATE customerpaymentallocation ca
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = 'Sale reversed: ' || v_reason
    WHERE  ca.module = 'water' AND ca.farmid = p_farmid AND ca.saleid = p_saleid
      AND  ca.status = 'Posted';

    -- 3. Put back exactly what the sale took out (net of anything already returned).
    INSERT INTO waterstocktransactions (farmid, waterproductid, txntype, quantity, basequantity, relatedsaleid, note, createdby)
    SELECT t.farmid, t.waterproductid, 'Return', -SUM(t.quantity), -SUM(COALESCE(t.basequantity, t.quantity)), p_saleid,
           'Sale #' || p_saleid || ' reversed', p_reversedby
    FROM   waterstocktransactions t
    WHERE  t.farmid = p_farmid AND t.relatedsaleid = p_saleid AND t.txntype IN ('Sale', 'Return')
    GROUP  BY t.farmid, t.waterproductid
    HAVING SUM(t.quantity) <> 0;

    -- 4. The reversal record, then the sale itself.
    PERFORM pg_advisory_xact_lock(hashtext('water-salereversal-no:' || p_farmid));
    SELECT 'WSR-' || lpad((COALESCE(MAX(NULLIF(regexp_replace(r.reversalnumber, '\D', '', 'g'), '')::int), 0) + 1)::text, 5, '0')
    INTO   v_number
    FROM   watersalereversals r WHERE r.farmid = p_farmid;

    INSERT INTO watersalereversals
        (farmid, reversalnumber, watersaleid, watercustomerid, customername, saledate,
         reasoncode, reason, businessdate, occurredat, reversedby, paymenthandling,
         totalamount, paidamount, outstandingamount, creditreleased, idempotencykey, snapshot)
    VALUES
        (p_farmid, v_number, p_saleid, v_cust, v_state->>'customerName', (v_state->>'saleDate')::timestamp,
         NULLIF(btrim(p_reasoncode), ''), btrim(COALESCE(p_reason, '')), v_today, v_now, p_reversedby, 'None',
         (v_state->>'total')::numeric, (v_state->>'paid')::numeric, (v_state->>'outstanding')::numeric,
         v_back, p_idempotencykey, v_state)
    RETURNING salereversalid INTO v_id;

    UPDATE watersales s
    SET    status = 'Cancelled', reversedat = v_now, reversedby = p_reversedby,
           reversalreason = v_reason, salereversalid = v_id, updateddate = v_now
    WHERE  s.farmid = p_farmid AND s.watersaleid = p_saleid;

    -- 5. The money.
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_state->'payments') LOOP
        v_action := COALESCE(p_handling->>(v_item->>'key'), v_item->>'default');
        v_amt    := (v_item->>'allocated')::numeric;
        v_group  := (v_item->>'paymentGroupId')::uuid;
        v_cpid   := NULL;

        IF v_action = 'ReversePayment' THEN
            PERFORM spwatercustomerpayment_reverse(p_farmid, v_group, 'Sale reversed: ' || v_reason, p_reversedby);
        ELSE
            -- The payment stays Posted (the money was received); what it paid on
            -- this sale becomes the customer's credit.
            INSERT INTO waterpayments
                (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note, createdby,
                 paymentgroupid, watercustomerid, sourcetype, sourceid, status)
            VALUES
                (p_farmid, NULL, v_amt, v_item->>'paymentMethod', v_now, v_number,
                 'Kept from reversed sale #' || p_saleid || COALESCE(' (' || (v_item->>'paymentNumbers') || ')', ''),
                 p_reversedby, gen_random_uuid(), v_cust, 'SaleReversalCredit', p_saleid, 'Posted')
            RETURNING waterpaymentid INTO v_cpid;
            v_credit := v_credit + v_amt;
        END IF;
        v_kinds := v_kinds || v_action;

        INSERT INTO watersalereversalpayments
            (salereversalid, farmid, paymentgroupid, paymentnumbers, sourcetype, amount, action, creditpaymentid)
        VALUES
            (v_id, p_farmid, v_group, v_item->>'paymentNumbers', v_item->>'source', v_amt, v_action, v_cpid);
    END LOOP;

    UPDATE watersalereversals r
    SET    creditcreated    = v_credit,
           paymentsreversed = COALESCE((SELECT SUM(rp.amount) FROM watersalereversalpayments rp
                                        WHERE rp.salereversalid = v_id AND rp.action = 'ReversePayment'), 0),
           paymenthandling  = CASE
               WHEN array_length(v_kinds, 1) IS NULL THEN 'None'
               WHEN 'KeepAsCredit' = ALL (v_kinds) THEN 'KeepAsCredit'
               WHEN 'ReversePayment' = ALL (v_kinds) THEN 'ReversePayment'
               ELSE 'Mixed' END
    WHERE  r.salereversalid = v_id;

    PERFORM set_config('water.sale_system', 'off', true);
    RETURN v_id;
END
$f$;

CREATE FUNCTION public.spwatersale_reversalget(p_farmid text, p_saleid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $f$
    SELECT jsonb_build_object(
             'salereversalid', r.salereversalid, 'reversalNumber', r.reversalnumber,
             'saleIds', jsonb_build_array(r.watersaleid), 'reasonCode', r.reasoncode, 'reason', r.reason,
             'businessDate', r.businessdate, 'occurredAt', r.occurredat, 'reversedBy', r.reversedby,
             'paymentHandling', r.paymenthandling, 'total', r.totalamount, 'paid', r.paidamount,
             'outstanding', r.outstandingamount, 'creditCreated', r.creditcreated,
             'creditReleased', r.creditreleased,
             'cashReversed', r.paymentsreversed, 'correctionSaleId', r.correctionsaleid,
             'payments', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                             'paymentGroupId', p.paymentgroupid, 'paymentNumbers', p.paymentnumbers,
                             'source', p.sourcetype, 'amount', p.amount, 'action', p.action,
                             'recordedAtReversal', false) ORDER BY p.salereversalpaymentid)
                           FROM watersalereversalpayments p WHERE p.salereversalid = r.salereversalid), '[]'::jsonb),
             'lines', r.snapshot->'lines')
    FROM   watersalereversals r
    WHERE  r.farmid = p_farmid AND r.watersaleid = p_saleid
    ORDER  BY r.salereversalid DESC
    LIMIT  1;
$f$;

-- A corrected sale points at the sale it replaces. One correction per reversal.
CREATE FUNCTION public.spwatersale_linkcorrection(p_farmid text, p_newsaleid integer, p_correctssaleid integer, p_by text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $f$
DECLARE
    v_rev  integer;
    v_prev integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM watersales s WHERE s.watersaleid = p_newsaleid AND s.farmid = p_farmid
                   AND s.salereversalid IS NULL AND s.status <> 'Cancelled') THEN
        RAISE EXCEPTION 'The corrected sale was not found for this company.' USING ERRCODE = 'P0001';
    END IF;
    SELECT s.salereversalid INTO v_rev FROM watersales s
    WHERE  s.watersaleid = p_correctssaleid AND s.farmid = p_farmid AND s.salereversalid IS NOT NULL;
    IF v_rev IS NULL THEN
        RAISE EXCEPTION 'Sale #% is not a reversed sale of this company, so nothing can be corrected from it.', p_correctssaleid
            USING ERRCODE = 'P0001';
    END IF;
    SELECT r.correctionsaleid INTO v_prev FROM watersalereversals r WHERE r.salereversalid = v_rev;
    IF v_prev IS NOT NULL AND v_prev <> p_newsaleid THEN
        RAISE EXCEPTION 'Sale #% was already corrected by sale #%.', p_correctssaleid, v_prev USING ERRCODE = 'P0001';
    END IF;

    PERFORM set_config('water.sale_system', 'on', true);
    UPDATE watersales s SET correctssaleid = p_correctssaleid
    WHERE  s.farmid = p_farmid AND s.watersaleid = p_newsaleid
      AND  s.correctssaleid IS DISTINCT FROM p_correctssaleid;
    PERFORM set_config('water.sale_system', 'off', true);
    UPDATE watersalereversals r SET correctionsaleid = COALESCE(r.correctionsaleid, p_newsaleid)
    WHERE  r.salereversalid = v_rev;
END
$f$;

-- ----------------------------------------------------- 7. sale list / detail --
-- Same columns as before plus the reversal, so the page can show "Reversed".
CREATE FUNCTION public.spwatersale_getall(p_farmid text)
RETURNS TABLE(watersaleid integer, farmid text, watercustomerid integer, customername text, saledate timestamp without time zone,
              totalamount numeric, amountpaid numeric, balance numeric, status text, notes text,
              createddate timestamp without time zone, createdby text, updateddate timestamp without time zone,
              sourcetype text, sourceid integer, paymentmethod text,
              salereversalid integer, reversalnumber text, reversedat timestamp without time zone, reversedby text,
              reversalreason text, correctssaleid integer, correctedbysaleid integer)
LANGUAGE plpgsql
AS $f$
BEGIN
    RETURN QUERY
    SELECT s.watersaleid, s.farmid::text, s.watercustomerid, c.name::text AS customername,
           s.saledate, s.totalamount, s.amountpaid,
           (s.totalamount - s.amountpaid) AS balance,
           s.status::text, s.notes::text, s.createddate, s.createdby::text, s.updateddate,
           s.sourcetype::text, s.sourceid,
           m.paymentmethod,
           s.salereversalid, r.reversalnumber, s.reversedat, s.reversedby, s.reversalreason,
           s.correctssaleid, r.correctionsaleid
    FROM   watersales s
    LEFT   JOIN watercustomers c ON c.watercustomerid = s.watercustomerid
    LEFT   JOIN watersalereversals r ON r.salereversalid = s.salereversalid
    LEFT   JOIN LATERAL (
               SELECT CASE COUNT(DISTINCT p.paymentmethod)
                        WHEN 0 THEN NULL
                        WHEN 1 THEN MIN(p.paymentmethod)::text
                        ELSE 'Mixed'
                      END AS paymentmethod
               FROM   waterpayments p
               WHERE  p.watersaleid = s.watersaleid
                 AND  p.farmid = s.farmid
                 AND  NULLIF(BTRIM(p.paymentmethod), '') IS NOT NULL
           ) m ON TRUE
    WHERE  s.farmid = p_farmid
    ORDER  BY s.saledate DESC, s.watersaleid DESC;
END;
$f$;

CREATE FUNCTION public.spwatersale_getbyid_rs1(p_watersaleid integer, p_farmid text)
RETURNS TABLE(watersaleid integer, farmid text, watercustomerid integer, customername text, saledate timestamp without time zone,
              totalamount numeric, amountpaid numeric, balance numeric, status text, notes text,
              createddate timestamp without time zone, createdby text, updateddate timestamp without time zone,
              paymentmethod text,
              salereversalid integer, reversalnumber text, reversedat timestamp without time zone, reversedby text,
              reversalreason text, correctssaleid integer, correctedbysaleid integer)
LANGUAGE plpgsql
AS $f$
BEGIN
    RETURN QUERY
    SELECT s.watersaleid, s.farmid::text, s.watercustomerid, c.name::text,
           s.saledate, s.totalamount, s.amountpaid,
           (s.totalamount - s.amountpaid),
           s.status::text, s.notes::text, s.createddate, s.createdby::text, s.updateddate,
           m.paymentmethod,
           s.salereversalid, r.reversalnumber, s.reversedat, s.reversedby, s.reversalreason,
           s.correctssaleid, r.correctionsaleid
    FROM   watersales s
    LEFT   JOIN watercustomers c ON c.watercustomerid = s.watercustomerid
    LEFT   JOIN watersalereversals r ON r.salereversalid = s.salereversalid
    LEFT   JOIN LATERAL (
               SELECT CASE COUNT(DISTINCT p.paymentmethod)
                        WHEN 0 THEN NULL
                        WHEN 1 THEN MIN(p.paymentmethod)::text
                        ELSE 'Mixed'
                      END AS paymentmethod
               FROM   waterpayments p
               WHERE  p.watersaleid = s.watersaleid
                 AND  p.farmid = s.farmid
                 AND  NULLIF(BTRIM(p.paymentmethod), '') IS NOT NULL
           ) m ON TRUE
    WHERE  s.watersaleid = p_watersaleid AND s.farmid = p_farmid;
END;
$f$;

-- --------------------------------------------- 8. readers and writers (live) --
-- Each below is the live body (pg_get_functiondef, 2026-11-20) with only the
-- marked 458 change.

-- 458: a reversed sale is never recomputed.
CREATE OR REPLACE FUNCTION public.spwatersale_recompute(p_farmid text, p_watersaleid integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_total numeric(14,2);
    v_sum   numeric(14,2);
    v_status text;
BEGIN
    SELECT s.totalamount, s.status INTO v_total, v_status
    FROM   watersales s
    WHERE  s.watersaleid = p_watersaleid AND s.farmid = p_farmid
    LIMIT  1;

    IF v_total IS NULL THEN RETURN; END IF;
    -- 458: a reversed sale is history -- never recomputed.
    IF EXISTS (SELECT 1 FROM watersales s WHERE s.watersaleid = p_watersaleid AND s.farmid = p_farmid
               AND s.salereversalid IS NOT NULL) THEN
        RETURN;
    END IF;

    v_sum := COALESCE((SELECT SUM(p.amount) FROM waterpayments p
                       WHERE p.watersaleid = p_watersaleid AND p.farmid = p_farmid
                         AND COALESCE(p.status, 'Posted') = 'Posted'), 0)
           -- 422: plus customer credit applied to the sale (no payment row)
           + public.fnwatersale_creditapplied(p_farmid, p_watersaleid);

    UPDATE watersales s
    SET    amountpaid  = v_sum,
           status      = CASE
                             WHEN v_status = 'Cancelled'    THEN 'Cancelled'
                             WHEN v_sum >= s.totalamount    THEN 'Paid'
                             WHEN v_sum > 0                 THEN 'PartiallyPaid'
                             ELSE 'Pending'
                         END,
           updateddate = (now() at time zone 'utc')
    WHERE  s.watersaleid = p_watersaleid AND s.farmid = p_farmid;
END;
$function$;

-- 458: refuses a cancelled / reversed sale.
CREATE OR REPLACE FUNCTION public.spwaterpayment_record(p_farmid text, p_watersaleid integer DEFAULT NULL::integer, p_amount numeric DEFAULT NULL::numeric, p_paymentmethod text DEFAULT NULL::text, p_paymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_reference text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_paymentdate timestamp := p_paymentdate;
    v_paymentid   integer;
    v_before      numeric;
BEGIN
    IF v_paymentdate IS NULL THEN
        v_paymentdate := (now() at time zone 'utc');
    END IF;

    -- Sale must belong to farm.
    IF NOT EXISTS (SELECT 1 FROM watersales s
                   WHERE s.watersaleid = p_watersaleid AND s.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Sale does not belong to this farm.';
    END IF;
    -- 458: nothing is owed on a cancelled or reversed sale.
    IF EXISTS (SELECT 1 FROM watersales s WHERE s.watersaleid = p_watersaleid AND s.farmid = p_farmid
               AND s.status = 'Cancelled') THEN
        RAISE EXCEPTION 'Sale #% has been reversed or cancelled, so it takes no payments.', p_watersaleid
            USING ERRCODE = 'P0001';
    END IF;

    -- What the sale still owed a moment before this payment.
    -- 422: the balance the sale shows (payments AND applied credit)
    SELECT GREATEST(s.totalamount - s.amountpaid, 0)
    INTO   v_before
    FROM   watersales s
    WHERE  s.watersaleid = p_watersaleid;

    -- 421: the payment names its customer and its source, like every other
    -- writer's payment, so customer payment history can find it.
    INSERT INTO waterpayments
        (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note, createdby, paymentgroupid,
         watercustomerid, sourcetype)
    VALUES (p_farmid, p_watersaleid, p_amount, p_paymentmethod, v_paymentdate, p_reference, p_note, p_createdby, gen_random_uuid(),
            (SELECT s.watercustomerid FROM watersales s WHERE s.watersaleid = p_watersaleid AND s.farmid = p_farmid),
            'SaleEntry')
    RETURNING waterpaymentid INTO v_paymentid;

    -- The snapshot. Same shape spwatercustomerpayment_record writes, so both
    -- writers' payments read identically on the page and in the statement.
    INSERT INTO customerpaymentallocation
        (farmid, module, paymentid, saleid, amountapplied,
         salebalancebefore, salebalanceafter, status, createdby, createdat)
    VALUES
        (p_farmid, 'water', v_paymentid, p_watersaleid, p_amount,
         v_before, v_before - p_amount, 'Posted', p_createdby, v_paymentdate);

    -- 421: the shared recompute counts POSTED payments only. This writer used to
    -- sum every payment on the sale, reversed ones included, so the first
    -- reversal followed by a new payment left the sale over-paid.
    PERFORM public.spwatersale_recompute(p_farmid, p_watersaleid);

    RETURN v_paymentid;
END;
$function$;

-- 458: refuses a sale-reversal credit.
CREATE OR REPLACE FUNCTION public.spwatercustomerpayment_reverse(p_farmid text, p_paymentgroupid uuid, p_reason text DEFAULT NULL::text, p_reversedby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_now   timestamp := (now() at time zone 'utc');
    v_count integer := 0;
    v_sale  integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM waterpayments p
                   WHERE p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Payment not found for this company.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM waterpayments p
                   WHERE p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid
                     AND COALESCE(p.status, 'Posted') = 'Posted') THEN
        RAISE EXCEPTION 'This payment has already been reversed.';
    END IF;
    -- 422: credit added by hand is reversed on the Customer Credits page.
    IF NOT EXISTS (SELECT 1 FROM waterpayments p
                   WHERE p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid
                     AND NOT public.fnwater_ismanualcredit(p.sourcetype)) THEN
        RAISE EXCEPTION 'This is credit added by hand -- reverse it on the Customer Credits page.';
    END IF;
    -- 458: credit kept from a reversed sale is not a payment; refund it instead.
    IF NOT EXISTS (SELECT 1 FROM waterpayments p
                   WHERE p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid
                     AND COALESCE(p.sourcetype, '') <> 'SaleReversalCredit') THEN
        RAISE EXCEPTION 'This credit was kept from a reversed sale. To give the money back, record a refund on Customer Credits.';
    END IF;
    -- 422: what this payment left as credit and then refunded must come back first.
    IF EXISTS (SELECT 1 FROM waterpayments p
               JOIN watercustomerrefundlines rl ON rl.waterpaymentid = p.waterpaymentid AND rl.farmid = p.farmid
               JOIN watercustomerrefunds r ON r.refundid = rl.refundid AND r.status = 'Posted'
               WHERE p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Part of this payment was refunded to the customer. Reverse the refund first.';
    END IF;

    -- the sales this payment (or its left-over credit) paid -- they are owed again
    CREATE TEMP TABLE IF NOT EXISTS _wpr_sales (saleid integer) ON COMMIT DROP;
    DELETE FROM _wpr_sales;
    INSERT INTO _wpr_sales
    SELECT DISTINCT ca.saleid FROM customerpaymentallocation ca
    JOIN   waterpayments p ON p.waterpaymentid = ca.paymentid AND p.farmid = ca.farmid
    WHERE  p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid
      AND  ca.module = 'water' AND ca.status = 'Posted';

    UPDATE customerpaymentallocation ca
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now, reversalreason = p_reason
    FROM   waterpayments p
    WHERE  p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid
      AND  ca.module IN ('water', 'water-debt')           -- 423: debt allocations too
      AND  ca.paymentid = p.waterpaymentid AND ca.status = 'Posted';
    UPDATE waterpayments p
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now, reversalreason = p_reason
    WHERE  p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid
      AND  COALESCE(p.status, 'Posted') = 'Posted';
    GET DIAGNOSTICS v_count = ROW_COUNT;

    FOR v_sale IN SELECT saleid FROM _wpr_sales UNION
                  SELECT DISTINCT p.watersaleid FROM waterpayments p
                  WHERE p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid AND p.watersaleid IS NOT NULL
    LOOP
        PERFORM spwatersale_recompute(p_farmid, v_sale);
    END LOOP;

    -- 383: a debt recorded only because this payment paid it goes with it --
    -- otherwise it would be owed again, money nobody owes.
    UPDATE watercustomerdebts d
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = COALESCE(p_reason, 'Payment reversed')
    FROM   waterpayments p
    WHERE  p.paymentgroupid = p_paymentgroupid AND p.farmid = p_farmid
      AND  d.debtid = p.waterdebtid AND d.farmid = p.farmid
      AND  d.paidonentry AND d.status = 'Posted'
      AND  public.fnwatercustomerdebt_paid(p_farmid, d.debtid) = 0;
    RETURN v_count;
END;
$function$;

-- 458: credit kept from a reversed sale is on the Credits page, not a payment.
CREATE OR REPLACE FUNCTION public.spwatercustomerpayment_history(p_farmid text, p_customerid integer DEFAULT NULL::integer, p_saleid integer DEFAULT NULL::integer, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS TABLE(paymentgroupid uuid, paymentnumber text, customerid integer, customername text, paymentdate timestamp without time zone, totalamount numeric, paymentmethod text, reference text, note text, sourcetype text, status text, allocationcount integer, watercashaccountid integer, createdby text, reversedby text, reversedat timestamp without time zone, reversalreason text, saleid integer, saletotal numeric, balancebefore numeric, amountapplied numeric, balanceafter numeric, createdat timestamp without time zone)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT p.paymentgroupid,
           MIN(p.paymentnumber)::text,
           MIN(p.watercustomerid),
           MIN(c.name)::text,
           MIN(p.paymentdate),
           SUM(p.amount)::numeric(14,2),
           MIN(p.paymentmethod)::text,
           MIN(p.reference)::text,
           MIN(p.note)::text,
           MIN(p.sourcetype)::text,
           MIN(COALESCE(p.status, 'Posted'))::text,
           -- DISTINCT on the payment row, not COUNT(*): the joins below are 1:1
           -- today, and this stays right if one of them ever is not.
           COUNT(DISTINCT p.waterpaymentid)::integer,
           MIN(p.watercashaccountid),
           MIN(p.createdby)::text,
           MIN(p.reversedby)::text,
           MIN(p.reversedat),
           MIN(p.reversalreason)::text,
           CASE WHEN COUNT(DISTINCT p.waterpaymentid) = 1 THEN MIN(p.watersaleid) END,
           CASE WHEN COUNT(DISTINCT p.waterpaymentid) = 1 THEN MIN(s.totalamount)::numeric(14,2) END,
           CASE WHEN COUNT(DISTINCT p.waterpaymentid) = 1 THEN MIN(ca.salebalancebefore)::numeric(14,2) END,
           CASE WHEN COUNT(DISTINCT p.waterpaymentid) = 1 THEN MIN(ca.amountapplied)::numeric(14,2) END,
           CASE WHEN COUNT(DISTINCT p.waterpaymentid) = 1 THEN MIN(ca.salebalanceafter)::numeric(14,2) END
           , MIN(p.createddate)   -- 304: the entry time
    FROM   waterpayments p
    LEFT   JOIN watercustomers c ON c.watercustomerid = p.watercustomerid AND c.farmid = p.farmid
    LEFT   JOIN watersales s     ON s.watersaleid = p.watersaleid AND s.farmid = p.farmid
    -- Payments taken before 227 have no allocation row; those columns come back
    -- NULL and the page falls back to what it can show.
    LEFT   JOIN customerpaymentallocation ca
           ON  ca.module = 'water'
           AND ca.paymentid = p.waterpaymentid
           AND ca.farmid = p.farmid
           -- 422: the payment's own sale only; a credit row's applications to
           -- other sales would multiply the payment's amount
           AND ca.saleid = p.watersaleid
    WHERE  p.farmid = p_farmid
      AND  (p_customerid IS NULL OR p.watercustomerid = p_customerid)
      AND  (p_from IS NULL OR p.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR p.paymentdate::date <= p_to)
      AND  (p_saleid IS NULL OR EXISTS (
              SELECT 1 FROM waterpayments p2
              WHERE p2.paymentgroupid = p.paymentgroupid AND p2.watersaleid = p_saleid))
    GROUP  BY p.paymentgroupid
    -- 422: credit added by hand lives on the Customer Credits page
    HAVING bool_or(NOT public.fnwater_ismanualcredit(p.sourcetype)
                   AND COALESCE(p.sourcetype, '') <> 'SaleReversalCredit')   -- 458
    ORDER  BY MIN(p.paymentdate) DESC;
$function$;

-- 458: names the new credit kind and its sale.
CREATE OR REPLACE FUNCTION public.spwatercustomercredit_events(p_farmid text, p_customerid integer DEFAULT NULL::integer)
 RETURNS TABLE(waterpaymentid integer, paymentgroupid uuid, paymentnumber text, creditdate timestamp without time zone, customerid integer, customername text, source text, sourcetype text, saleid integer, salegroupno text, reference text, originalamount numeric, applied numeric, refunded numeric, available numeric, status text, ismanual boolean, watercashaccountid integer)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT p.waterpaymentid, p.paymentgroupid, p.paymentnumber::text, p.paymentdate,
           p.watercustomerid, c.name::text,
           CASE p.sourcetype WHEN 'Deposit' THEN 'Customer advance'
                             WHEN 'Overpayment' THEN 'Payment left over'
                             WHEN 'OpeningCredit' THEN 'Opening credit'
                             WHEN 'CreditNote' THEN 'Credit note'
                             WHEN 'SaleReversalCredit' THEN 'Kept from reversed sale'   -- 458
                             ELSE COALESCE(p.sourcetype, 'Credit') END::text,
           p.sourcetype::text,
           CASE WHEN p.sourcetype = 'SaleReversalCredit' THEN p.sourceid END,   -- 458: the reversed sale
           NULL::text,
           COALESCE(NULLIF(btrim(p.reference), ''), NULL)::text,
           p.amount::numeric(14,2), a.applied, r.refunded,
           CASE WHEN COALESCE(p.status, 'Posted') = 'Posted'
                THEN GREATEST(p.amount - a.applied - r.refunded, 0) ELSE 0 END::numeric(14,2),
           COALESCE(p.status, 'Posted')::text,
           public.fnwater_ismanualcredit(p.sourcetype),
           p.watercashaccountid
    FROM   waterpayments p
    LEFT   JOIN watercustomers c ON c.watercustomerid = p.watercustomerid AND c.farmid = p.farmid
    CROSS  JOIN LATERAL (SELECT COALESCE(SUM(ca.amountapplied), 0)::numeric(14,2) AS applied
                         FROM customerpaymentallocation ca
                         WHERE ca.farmid = p.farmid AND ca.module = 'water'
                           AND ca.paymentid = p.waterpaymentid AND ca.status = 'Posted') a
    CROSS  JOIN LATERAL (SELECT COALESCE(SUM(rl.amount), 0)::numeric(14,2) AS refunded
                         FROM watercustomerrefundlines rl JOIN watercustomerrefunds rf ON rf.refundid = rl.refundid
                         WHERE rl.farmid = p.farmid AND rl.waterpaymentid = p.waterpaymentid
                           AND rf.status = 'Posted') r
    WHERE  p.farmid = p_farmid AND public.fnwater_iscreditkind(p.sourcetype)
      AND  (p_customerid IS NULL OR p.watercustomerid = p_customerid)
    ORDER  BY p.paymentdate DESC, p.waterpaymentid DESC;
$function$;

-- 458: skips cancelled / reversed sales.
CREATE OR REPLACE FUNCTION public.fnwaterbalanceaudit(p_farmid text)
 RETURNS TABLE(side text, documenttype text, documentid integer, amountpaid numeric, allocated numeric, difference numeric)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT 'customer'::text, 'WaterSale'::text, s.watersaleid,
           s.amountpaid,
           COALESCE(a.allocated, 0)::numeric(14,2),
           (s.amountpaid - COALESCE(a.allocated, 0))::numeric(14,2)
    FROM   watersales s
    LEFT   JOIN LATERAL (
               SELECT SUM(ca.amountapplied) AS allocated
               FROM   customerpaymentallocation ca
               WHERE  ca.farmid = s.farmid AND ca.module = 'water'
                 AND  ca.saleid = s.watersaleid AND ca.status = 'Posted'
           ) a ON TRUE
    WHERE  s.farmid = p_farmid
      AND  COALESCE(s.status, '') <> 'Cancelled'   -- 458: cancelled / reversed sales are history
      AND  (s.amountpaid - COALESCE(a.allocated, 0)) <> 0
    UNION ALL
    SELECT 'supplier'::text, 'RawMaterialPurchase'::text, pu.waterrawmaterialpurchaseid,
           pu.amountpaid,
           COALESCE(a.allocated, 0)::numeric(14,2),
           (pu.amountpaid - COALESCE(a.allocated, 0))::numeric(14,2)
    FROM   waterrawmaterialpurchases pu
    LEFT   JOIN LATERAL (
               SELECT SUM(sa.amountapplied) AS allocated
               FROM   supplierpaymentallocation sa
               WHERE  sa.farmid = pu.farmid AND sa.module = 'water'
                 AND  sa.documenttype = 'RawMaterialPurchase'
                 AND  sa.documentid = pu.waterrawmaterialpurchaseid
                 AND  sa.status = 'Posted'
           ) a ON TRUE
    WHERE  pu.farmid = p_farmid
      AND  COALESCE(pu.lotsource, '') <> 'ManualDeferredCost'   -- 426
      AND  (pu.amountpaid - COALESCE(a.allocated, 0)) <> 0
    UNION ALL
    SELECT 'supplier'::text, 'Expense'::text, e.waterexpenseid,
           COALESCE(e.amountpaid,
                    CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                         THEN 0 ELSE e.amount END)::numeric(14,2),
           COALESCE(a.allocated, 0)::numeric(14,2),
           (COALESCE(e.amountpaid,
                     CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                          THEN 0 ELSE e.amount END) - COALESCE(a.allocated, 0))::numeric(14,2)
    FROM   waterexpenses e
    LEFT   JOIN LATERAL (
               SELECT SUM(sa.amountapplied) AS allocated
               FROM   supplierpaymentallocation sa
               WHERE  sa.farmid = e.farmid AND sa.module = 'water'
                 AND  sa.documenttype = 'Expense'
                 AND  sa.documentid = e.waterexpenseid
                 AND  sa.status = 'Posted'
           ) a ON TRUE
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(a.allocated, 0) > COALESCE(e.amountpaid,
               CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit' THEN 0 ELSE e.amount END);
$function$;

-- 458: collections -- reversal credit is not money; a kept payment on a reversed sale counts.
CREATE OR REPLACE FUNCTION public.fnwaterdailyclosing_livetotals(p_farmid text, p_closingdate date)
 RETURNS TABLE(bagsproduced numeric, totalproductioncost numeric, bagssold numeric, totalincome numeric, creditsales numeric, customercollections numeric, bagsreturned numeric, bagsdamaged numeric, drivershortagestotal numeric, momobalance numeric, bankbalance numeric, rawmaterialspendtoday numeric, closingstockbags numeric, totalexpenses numeric, cashathand numeric)
 LANGUAGE sql
AS $function$
    WITH
    prod AS (
        SELECT
            COALESCE(SUM((pb.bagsproduced - COALESCE(pb.damagedbags, 0))::numeric(14,3)), 0) AS bagsproduced,
            COALESCE(SUM(pb.totalproductioncost), 0) AS totalproductioncost
        FROM waterproductionbatches pb
        WHERE pb.farmid = p_farmid AND pb.isdeleted = FALSE AND pb.status = 'Approved'
          AND pb.productiondate = p_closingdate
    ),
    sale_items AS (
        SELECT COALESCE(SUM(si.quantity::numeric(14,3)), 0) AS bagssold
        FROM   watersales s
        INNER  JOIN watersaleitems si ON si.watersaleid = s.watersaleid
        WHERE  s.farmid = p_farmid AND s.status NOT IN ('Cancelled')
           AND COALESCE(s.sourcetype, '') <> 'DeliveryRun'
           AND s.saledate >= p_closingdate::timestamp
           AND s.saledate <  p_closingdate::timestamp + interval '1 day'
    ),
    sale_money AS (
        SELECT
            COALESCE(SUM(s2.totalamount), 0) AS totalincome,
            -- 423: what was still OWED at the end of the day (364's rule), not
            -- what is owed now -- a payment made later must not rewrite a past day.
            COALESCE(SUM(public.fnwatersale_owedasof(p_farmid, s2.watersaleid, p_closingdate)), 0) AS creditsales
        FROM   watersales s2
        WHERE  s2.farmid = p_farmid AND s2.status NOT IN ('Cancelled')
           AND COALESCE(s2.sourcetype, '') <> 'DeliveryRun'
           AND s2.saledate >= p_closingdate::timestamp
           AND s2.saledate <  p_closingdate::timestamp + interval '1 day'
    ),
    payments AS (
        SELECT
            COALESCE(SUM(pay.amount), 0) AS customercollections,
            COALESCE(SUM(CASE WHEN pay.paymentmethod IN ('Mobile Money', 'MoMo', 'Momo') THEN pay.amount ELSE 0 END), 0) AS momopayments,
            COALESCE(SUM(CASE WHEN pay.paymentmethod IN ('Bank', 'Bank Transfer', 'Transfer') THEN pay.amount ELSE 0 END), 0) AS bankpayments
        FROM   waterpayments pay
        LEFT   JOIN watersales ps ON ps.watersaleid = pay.watersaleid AND ps.farmid = pay.farmid
        WHERE  pay.farmid = p_farmid
           AND COALESCE(pay.sourcetype, '') <> 'DeliveryRun'
           -- 423: a reversed payment collected nothing.
           AND COALESCE(pay.status, 'Posted') = 'Posted'
           -- 424: a customer advance went straight into its account; opening
           -- credit and credit notes are not money. None of it is in the drawer.
           AND NOT public.fnwater_ismanualcredit(pay.sourcetype)
           -- 458: credit kept from a reversed sale is not money received.
           AND NOT public.fnwater_isnocashcredit(pay.sourcetype)
           -- 423: a payment on a sale made the SAME day is already in that sale's
           -- paid part (income less credit); counting it here too doubled it.
           AND NOT (ps.watersaleid IS NOT NULL
                    AND COALESCE(ps.sourcetype, '') <> 'DeliveryRun'
                    -- 458: a cancelled / reversed sale is not in the day's sales,
                    -- so money kept from it is a collection in its own right.
                    AND COALESCE(ps.status, '') <> 'Cancelled'
                    AND ps.saledate >= p_closingdate::timestamp
                    AND ps.saledate <  p_closingdate::timestamp + interval '1 day')
           AND pay.paymentdate >= p_closingdate::timestamp
           AND pay.paymentdate <  p_closingdate::timestamp + interval '1 day'
    ),
    ranked_returns AS (
        SELECT
            dr.waterdriverreturnid, dr.watervehicleloadingid,
            dr.bagsreturned, dr.bagsdamaged, dr.bagssold,
            dr.cashcollected, dr.momocollected, dr.bankcollected, dr.creditsalesamount, dr.shortageamount,
            ROW_NUMBER() OVER (PARTITION BY dr.watervehicleloadingid ORDER BY dr.waterdriverreturnid DESC) AS rn
        FROM   waterdriverreturns dr
        WHERE  dr.farmid = p_farmid AND dr.status = 'Approved'
           AND dr.returndate >= p_closingdate::timestamp
           AND dr.returndate <  p_closingdate::timestamp + interval '1 day'
    ),
    driver_returns AS (
        SELECT
            COALESCE(SUM(rr.bagsreturned::numeric(14,3)), 0) AS bagsreturned,
            COALESCE(SUM(rr.bagsdamaged::numeric(14,3)), 0)  AS bagsdamaged,
            COALESCE(SUM(rr.bagssold::numeric(14,3)), 0)     AS driverbagssold,
            COALESCE(SUM(rr.cashcollected + rr.momocollected + rr.bankcollected + rr.creditsalesamount), 0) AS drivertotalincome,
            COALESCE(SUM(rr.creditsalesamount), 0) AS drivercreditsales,
            COALESCE(SUM(rr.momocollected), 0) AS drivermomo,
            COALESCE(SUM(rr.bankcollected), 0) AS driverbank,
            COALESCE(SUM(rr.shortageamount), 0) AS drivershortages
        FROM   ranked_returns rr
        WHERE  rr.rn = 1
    ),
    raw_spend AS (
        -- 429: the day's cash on raw materials -- what purchases entered today
        -- were paid on entry, plus supplier payments made today for purchases
        -- (deferred lots included: this is cash, not cost). Before, a purchase
        -- paid later counted on its own day AND again as the payment's expense.
        SELECT COALESCE((
                   SELECT SUM(GREATEST(rp.amountpaid - COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                                        WHERE sa.farmid = rp.farmid AND sa.module = 'water' AND sa.status = 'Posted'
                                          AND sa.documenttype = 'RawMaterialPurchase'
                                          AND sa.documentid = rp.waterrawmaterialpurchaseid), 0), 0))
                   FROM   waterrawmaterialpurchases rp
                   WHERE  rp.farmid = p_farmid
                     AND  COALESCE(rp.lotsource, '') <> 'ManualDeferredCost'
                     AND  rp.purchasedate >= p_closingdate::timestamp
                     AND  rp.purchasedate <  p_closingdate::timestamp + interval '1 day'), 0)
             + COALESCE((
                   SELECT SUM(sa.amountapplied)
                   FROM   supplierpaymentallocation sa
                   JOIN   watersupplierpayments sp ON sp.watersupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
                   WHERE  sa.farmid = p_farmid AND sa.module = 'water' AND sa.status = 'Posted'
                     AND  sa.documenttype = 'RawMaterialPurchase' AND NOT sa.fromcredit
                     AND  COALESCE(sp.status, 'Posted') = 'Posted'
                     AND  sp.paymentdate >= p_closingdate::timestamp
                     AND  sp.paymentdate <  p_closingdate::timestamp + interval '1 day'), 0) AS rawmaterialspendtoday
    ),
    gen_exp AS (
        SELECT COALESCE(SUM(e.amount), 0) AS generalexpenses
        FROM   waterexpenses e
        WHERE  e.farmid = p_farmid AND e.isdeleted = FALSE AND e.status = 'Approved'
           AND COALESCE(e.sourcetype, '') NOT IN ('RawMaterialPurchase', 'WaterInternalUsage',
                                                  'WaterSupplierPayment')   -- 429: now in raw spend
           AND e.expensedate >= p_closingdate::timestamp
           AND e.expensedate <  p_closingdate::timestamp + interval '1 day'
    ),
    delivery_exp AS (
        SELECT COALESCE(SUM(de.amount), 0) AS deliveryexpenses
        FROM   waterdeliveryexpenses de
        INNER  JOIN ranked_returns rr2 ON rr2.waterdriverreturnid = de.waterdriverreturnid AND rr2.rn = 1
        WHERE  de.isapproved = TRUE
    ),
    closing_stock AS (
        SELECT COALESCE(SUM(st.quantity::numeric(14,3)), 0) AS closingstockbags
        FROM   waterstocktransactions st WHERE st.farmid = p_farmid
    )
    SELECT
        prod.bagsproduced,
        prod.totalproductioncost,
        sale_items.bagssold + driver_returns.driverbagssold          AS bagssold,
        sale_money.totalincome + driver_returns.drivertotalincome    AS totalincome,
        sale_money.creditsales + driver_returns.drivercreditsales    AS creditsales,
        payments.customercollections,
        driver_returns.bagsreturned,
        driver_returns.bagsdamaged,
        driver_returns.drivershortages                               AS drivershortagestotal,
        driver_returns.drivermomo + payments.momopayments            AS momobalance,
        driver_returns.driverbank + payments.bankpayments            AS bankbalance,
        raw_spend.rawmaterialspendtoday,
        closing_stock.closingstockbags,
        prod.totalproductioncost + raw_spend.rawmaterialspendtoday
            + gen_exp.generalexpenses + delivery_exp.deliveryexpenses AS totalexpenses,
        (sale_money.totalincome + driver_returns.drivertotalincome)
            - (sale_money.creditsales + driver_returns.drivercreditsales)
            + payments.customercollections
            - (prod.totalproductioncost + raw_spend.rawmaterialspendtoday
               + gen_exp.generalexpenses + delivery_exp.deliveryexpenses) AS cashathand
    FROM   prod
    CROSS  JOIN sale_items
    CROSS  JOIN sale_money
    CROSS  JOIN payments
    CROSS  JOIN driver_returns
    CROSS  JOIN raw_spend
    CROSS  JOIN gen_exp
    CROSS  JOIN delivery_exp
    CROSS  JOIN closing_stock
$function$;

-- 458: customer payment reversals are append-only on Cash Flow.
CREATE OR REPLACE FUNCTION public.spwatercashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, createdat timestamp without time zone)
 LANGUAGE plpgsql
 STABLE
AS $function$

DECLARE

    v_tbl  text;
    v_createdcol text;               -- 302: 'ca.createddate' or NULL

    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);

    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);

BEGIN

    -- ---- 1. customer receipts, dated when the money arrived -----------------

    RETURN QUERY

    SELECT 'Receipt'::text,

           FALSE,

           p.waterpaymentid,

           NULL::integer,

           NULL::text,

           p.paymentdate,

           'CashIn'::text,

           'CustomerPayment'::text,

           p.watersaleid,

           FALSE,

           COALESCE(p.amount, 0)::numeric,

           COALESCE(NULLIF(btrim(p.note), ''),

                    NULLIF(btrim(p.reference), ''),

                    'Payment for sale #' || p.watersaleid::text)::text,

           'OperatingIn'::text

           , p.createddate   -- 302: the entry time
    FROM   waterpayments p

    WHERE  lower(p.farmid::text) = lower(p_farmid)

      AND  COALESCE(p.amount, 0) <> 0

      -- 458: a REVERSED payment keeps its receipt on the day the money came in;
      -- arm 1a below takes it back out on the day it was reversed. Before 458
      -- the receipt vanished, rewriting the period it was received in.
      AND  COALESCE(p.status, 'Posted') IN ('Posted', 'Reversed')

      -- 422: opening credit and credit notes are credit, not money received.
      AND  NOT public.fnwater_isnocashcredit(p.sourcetype)

      AND  p.paymentdate >= v_from

      AND  p.paymentdate <= v_to;



    -- ---- 1a. 458: a reversed customer payment, out on the reversal day ------
    RETURN QUERY
    SELECT 'ReceiptReversal'::text, FALSE, p.waterpaymentid, NULL::integer, NULL::text,
           p.reversedat, 'CashOut'::text, 'CustomerPaymentReversal'::text, p.watersaleid, FALSE,
           -COALESCE(p.amount, 0)::numeric,
           ('Reversal of payment ' || COALESCE(p.paymentnumber, '#' || p.waterpaymentid::text)
            || COALESCE(' - ' || NULLIF(btrim(p.reversalreason), ''), ''))::text,
           'OperatingOut'::text, p.reversedat
    FROM   waterpayments p
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) <> 0
      AND  p.status = 'Reversed' AND p.reversedat IS NOT NULL
      AND  NOT public.fnwater_isnocashcredit(p.sourcetype)
      AND  p.reversedat >= v_from
      AND  p.reversedat <= v_to;

    -- ---- 1b. 422: customer refunds -----------------------------------------
    -- Money out on the refund date, and it stays there when the refund is
    -- reversed (the money did leave); the reversal is money back in on its date.
    RETURN QUERY
    SELECT 'CustomerRefund'::text, FALSE, r.refundid, r.watercashaccountid, NULL::text,
           r.refunddate::timestamp, 'CashOut'::text, 'WaterCustomerRefund'::text, r.refundid, FALSE,
           -r.amount, ('Customer refund ' || r.refundnumber ||
                       COALESCE(' - ' || NULLIF(btrim(c.name), ''), ''))::text,
           'OperatingOut'::text, r.createdat
    FROM   watercustomerrefunds r
    LEFT   JOIN watercustomers c ON c.watercustomerid = r.watercustomerid AND c.farmid = r.farmid
    WHERE  r.farmid = p_farmid AND r.status IN ('Posted', 'Reversed')
      AND  r.refunddate::timestamp >= v_from AND r.refunddate::timestamp <= v_to;

    RETURN QUERY
    SELECT 'CustomerRefundReversal'::text, FALSE, r.refundid, r.watercashaccountid, NULL::text,
           r.reversedat, 'CashIn'::text, 'WaterCustomerRefund'::text, r.refundid, FALSE,
           r.amount, ('Reversal of customer refund ' || r.refundnumber)::text,
           'OperatingIn'::text, r.reversedat
    FROM   watercustomerrefunds r
    WHERE  r.farmid = p_farmid AND r.status = 'Reversed' AND r.reversedat IS NOT NULL
      AND  r.reversedat >= v_from AND r.reversedat <= v_to;

    -- ---- 2. the part paid at the point of sale -----------------------------

    -- Same reasoning as 235: a sale settled on the spot may never create a

    -- payment row, and the difference is what picks those up.

    RETURN QUERY

    SELECT 'SaleResidual'::text,

           FALSE,

           s.watersaleid,

           NULL::integer,

           NULL::text,

           s.saledate,

           'CashIn'::text,

           'Sale'::text,

           s.watersaleid,

           FALSE,

           v.residual,

           ('Sale #' || s.watersaleid::text)::text,

           'OperatingIn'::text

           , s.createddate   -- 302: the entry time
    FROM   watersales s

    CROSS  JOIN LATERAL (

        SELECT ROUND(

                   CASE WHEN COALESCE(s.status, '') = 'Paid'

                        THEN COALESCE(s.totalamount, 0)

                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),

                                   COALESCE(s.totalamount, 0))

                   END

                 - COALESCE((SELECT SUM(wp.amount)

                             FROM   waterpayments wp

                             WHERE  wp.watersaleid = s.watersaleid

                               AND  lower(wp.farmid::text) = lower(p_farmid)

                               -- Same reason: a reversed payment never covered

                               -- anything, so it must not reduce the residual.

                               AND  COALESCE(wp.status, 'Posted') = 'Posted'), 0)
                 -- 422: credit applied to the sale is not money taken at the till
                 - public.fnwatersale_creditapplied(p_farmid, s.watersaleid)

               , 2) AS residual

    ) v

    WHERE  lower(s.farmid::text) = lower(p_farmid)

      -- A cancelled sale is not income, whatever it once recorded as paid.

      AND  COALESCE(s.status, '') <> 'Cancelled'

      AND  v.residual > 0

      AND  s.saledate >= v_from

      AND  s.saledate <= v_to;



    -- ---- 3. money paid out when the bill was recorded -----------------------

    -- 236's gates are kept verbatim -- Approved, not deleted -- with two

    -- changes:

    --

    --   * the AMOUNT is what was actually paid at entry, not the whole bill:

    --     the resolved amountpaid, less anything a supplier payment has since

    --     covered (which the next arm reports on its own, later, date);

    --   * the `paymentmethod <> 'Credit'` filter is GONE, because the resolution

    --     subsumes it. A Credit bill resolves to 0 paid and drops out on

    --     `paidatentry > 0` instead -- same rows excluded, and a Credit bill

    --     that has since been part-paid is no longer wrongly invisible.

    RETURN QUERY

    SELECT 'Expense'::text,

           FALSE,

           e.waterexpenseid,

           e.watercashaccountid,

           NULL::text,

           e.expensedate,

           'CashOut'::text,

           'Expense'::text,

           e.waterexpenseid,

           FALSE,

           -v.paidatentry,

           COALESCE(NULLIF(btrim(e.description), ''),

                    NULLIF(btrim(e.paidto), ''),

                    'Expense #' || e.waterexpenseid::text)::text,

           'OperatingOut'::text

           , e.createdat   -- 302: the entry time
    FROM   waterexpenses e

    CROSS  JOIN LATERAL (

        SELECT GREATEST(

                   COALESCE(e.amountpaid,

                            CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'

                                 THEN 0 ELSE e.amount END)

                 - COALESCE((SELECT SUM(sa.amountapplied)

                             FROM   supplierpaymentallocation sa

                             WHERE  sa.farmid = p_farmid

                               AND  sa.module = 'water'

                               AND  sa.status = 'Posted'

                               AND  sa.documenttype = 'Expense'

                               AND  sa.documentid = e.waterexpenseid), 0)

               , 0)::numeric AS paidatentry

    ) v

    WHERE  lower(e.farmid::text) = lower(p_farmid)

      AND  COALESCE(e.isdeleted, false) = false

      AND  v.paidatentry > 0

      -- 047's rule: only an approved expense has been recognised at all.

      AND  COALESCE(e.status, '') = 'Approved'

      -- 259. 'NonCash' means "a cost recorded, but the money moved elsewhere".

      -- Loan interest and fees are written this way: the repayment's own arm

      -- below reports the FULL amount that left the account, so counting these

      -- rows here as well would take 12,500 out of the bank and 15,000 off the

      -- cash flow. Expense reports do not filter NonCash, so the cost still

      -- counts where it should.

      --

      -- No-op on today's data: there are zero water expenses with this marker.

      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'

      -- 421: a supplier payment's own aggregated expense row is not read here.
      -- It holds only the part expensed at purchase and is Cancelled on
      -- reversal; the payment's cash is reported from the payment below (3c).
      AND  COALESCE(e.sourcetype, '') <> 'WaterSupplierPayment'

      AND  e.expensedate >= v_from

      AND  e.expensedate <= v_to;



    -- ---- 3b. money paid out later, against a bill already recorded ----------

    -- A supplier payment settling a bill. It belongs to the day the money moved,

    -- not the day the bill was entered.

    --

    -- Only documenttype='Expense'. A payment against a raw-material purchase

    -- books its own aggregated expense row dated the payment date (240) and is

    -- already counted by arm 3; adding it here would double it.

    RETURN QUERY

    SELECT 'ExpensePayment'::text,

           FALSE,

           sa.allocationid,

           sp.watercashaccountid,

           NULL::text,

           sp.paymentdate,

           'CashOut'::text,

           'ExpensePayment'::text,

           sa.documentid,

           FALSE,

           -sa.amountapplied::numeric,

           ('Payment for expense #' || sa.documentid::text ||

            COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,

           'OperatingOut'::text

           , sa.createdat   -- 302: the entry time
    FROM   supplierpaymentallocation sa

    JOIN   watersupplierpayments sp

           ON  sp.watersupplierpaymentid = sa.paymentid

           AND sp.farmid = sa.farmid

    LEFT   JOIN watersuppliers s

           ON  s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid

    WHERE  sa.farmid = p_farmid

      AND  sa.module = 'water'

      -- 421: a reversed payment's money still LEFT on its date (376's rule);
      -- the reversal brings it back on its own date (3d). Allocations are only
      -- ever reversed together with their payment.
      AND  (sa.status = 'Posted' OR (sa.status = 'Reversed' AND sp.status = 'Reversed'))

      AND  NOT sa.fromcredit                                -- 424

      AND  sa.documenttype = 'Expense'

      AND  COALESCE(sp.status, 'Posted') IN ('Posted', 'Reversed')

      AND  sa.amountapplied <> 0

      AND  sp.paymentdate >= v_from

      AND  sp.paymentdate <= v_to;



    -- ---- 3c. 421: supplier payments for raw-material purchases ------------
    --
    -- The FULL purchase portion, on the payment date -- deferred lots included,
    -- because the supplier was paid for them whether or not their cost has
    -- reached the P&L (275). Reversed payments stay: the money did leave.
    RETURN QUERY
    SELECT 'SupplierPurchasePayment'::text,
           FALSE,
           sp.watersupplierpaymentid,
           sp.watercashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'WaterSupplierPayment'::text,
           sp.watersupplierpaymentid,
           FALSE,
           -x.amount,
           ('Supplier payment - raw material purchase' ||
            COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,
           'OperatingOut'::text,
           sp.createdat
    FROM   watersupplierpayments sp
    CROSS  JOIN LATERAL (
        SELECT COALESCE(SUM(sa.amountapplied), 0)::numeric AS amount
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = sp.farmid AND sa.module = 'water'
          AND  sa.paymentid = sp.watersupplierpaymentid
          AND  sa.documenttype NOT IN ('Expense', 'SupplierDebt')     -- 424
          AND  NOT sa.fromcredit                                     -- 424
          AND  (sa.status = 'Posted' OR (sa.status = 'Reversed' AND sp.status = 'Reversed'))
    ) x
    LEFT   JOIN watersuppliers s
           ON  s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  COALESCE(sp.status, 'Posted') IN ('Posted', 'Reversed')
      AND  x.amount <> 0
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;

    -- ---- 3d. 421: a reversed supplier payment's money coming back ---------
    --
    -- Everything the payment paid out (purchases and bills), back in on the
    -- day it was reversed.
    RETURN QUERY
    SELECT 'SupplierPaymentReversal'::text,
           FALSE,
           sp.watersupplierpaymentid,
           sp.watercashaccountid,
           NULL::text,
           sp.reversedat,
           'CashIn'::text,
           'WaterSupplierPayment'::text,
           sp.watersupplierpaymentid,
           FALSE,
           x.amount,
           ('Reversal of supplier payment #' || sp.watersupplierpaymentid::text ||
            COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,
           'OperatingIn'::text,
           sp.reversedat
    FROM   watersupplierpayments sp
    CROSS  JOIN LATERAL (
        -- 424: the whole payment (an advance has no allocations at all)
        SELECT sp.totalamount::numeric AS amount
    ) x
    LEFT   JOIN watersuppliers s
           ON  s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  sp.status = 'Reversed'
      AND  NOT public.fnwatersupplier_iscreditkind(sp.sourcetype)   -- 424
      AND  sp.reversedat IS NOT NULL
      AND  x.amount <> 0
      AND  sp.reversedat >= v_from
      AND  sp.reversedat <= v_to;

    -- ---- 3e. 424: supplier debts and advances --------------------------------
    -- The part of a payment no other row shows: what it paid on supplier debts
    -- and what it applied to nothing (an advance / overpayment), on the
    -- payment's own day. With 3b and 3c a payment always totals its amount.
    RETURN QUERY
    SELECT 'SupplierAdvanceOrDebt'::text, FALSE, sp.watersupplierpaymentid, sp.watercashaccountid, NULL::text,
           sp.paymentdate, 'CashOut'::text, 'WaterSupplierPayment'::text, sp.watersupplierpaymentid, FALSE,
           -x.amount,
           ('Supplier payment - debts / advance' || COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,
           'OperatingOut'::text, sp.createdat
    FROM   watersupplierpayments sp
    CROSS  JOIN LATERAL (
        SELECT sp.totalamount - COALESCE(SUM(sa.amountapplied), 0)::numeric AS amount
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = sp.farmid AND sa.module = 'water'
          AND  sa.paymentid = sp.watersupplierpaymentid
          AND  sa.documenttype IN ('RawMaterialPurchase', 'Expense')
          AND  NOT sa.fromcredit
          AND  (sa.status = 'Posted' OR (sa.status = 'Reversed' AND sp.status = 'Reversed'))
    ) x
    LEFT   JOIN watersuppliers s ON s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  COALESCE(sp.status, 'Posted') IN ('Posted', 'Reversed')
      AND  NOT public.fnwatersupplier_iscreditkind(sp.sourcetype)
      AND  x.amount > 0
      AND  sp.paymentdate >= v_from AND sp.paymentdate <= v_to;

    -- ---- 3g / 3h. 424: supplier refunds ---------------------------------------
    RETURN QUERY
    SELECT 'SupplierRefund'::text, FALSE, r.refundid, r.watercashaccountid, NULL::text,
           r.refunddate::timestamp, 'CashIn'::text, 'WaterSupplierRefund'::text, r.refundid, FALSE,
           r.amount, ('Supplier refund ' || r.refundnumber || COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,
           'OperatingIn'::text, r.createdat
    FROM   watersupplierrefunds r
    LEFT   JOIN watersuppliers s ON s.watersupplierid = r.supplierid AND s.farmid = r.farmid
    WHERE  r.farmid = p_farmid AND r.status IN ('Posted', 'Reversed')
      AND  r.refunddate::timestamp >= v_from AND r.refunddate::timestamp <= v_to;

    RETURN QUERY
    SELECT 'SupplierRefundReversal'::text, FALSE, r.refundid, r.watercashaccountid, NULL::text,
           r.reversedat, 'CashOut'::text, 'WaterSupplierRefund'::text, r.refundid, FALSE,
           -r.amount, ('Reversal of supplier refund ' || r.refundnumber)::text,
           'OperatingOut'::text, r.reversedat
    FROM   watersupplierrefunds r
    WHERE  r.farmid = p_farmid AND r.status = 'Reversed' AND r.reversedat IS NOT NULL
      AND  r.reversedat >= v_from AND r.reversedat <= v_to;

    -- ---- 4. owner money (258) ----------------------------------------------

    -- Contributions and draws recorded through the Owner Money module.

    -- FINANCING, not operating: the owner funded the business or took funding

    -- back. Never revenue, never expense.

    --

    -- Reversed records are dropped entirely rather than netted to zero with a

    -- second row -- a contribution that was put in and taken back out is not

    -- funding, and showing both legs would put money the business never kept

    -- into Money In and Money Out.

    --

    -- Placed ABOVE the legacy capital arm on purpose: that arm RETURNs early

    -- when cashadjustment is absent, so anything below it is skipped on a

    -- company with no capital records.

    RETURN QUERY

    SELECT 'OwnerMoney'::text,

           FALSE,

           o.waterownermoneyid,

           o.watercashaccountid,

           a.accountname::text,

           o.transactiondate,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'CashIn' ELSE 'CashOut' END::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END::text,

           o.waterownermoneyid,

           FALSE,

           -- Stored positive; the sign is applied here, once.

           (CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE -o.amount END)::numeric,

           COALESCE(NULLIF(btrim(o.notes), ''),

                    NULLIF(btrim(o.ownername), ''),

                    CASE WHEN o.transactiontype = 'Contribution'

                         THEN 'Owner contribution' ELSE 'Owner draw' END)::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'FinancingIn' ELSE 'FinancingOut' END::text

           , o.createdat   -- 302: the entry time
    FROM   waterownermoney o

    LEFT   JOIN watercashaccounts a

           ON a.watercashaccountid = o.watercashaccountid

    WHERE  o.farmid = p_farmid

      AND  o.status = 'Posted'
      -- 297. A record backfilled from a Cash Flow adjustment has NO cash
      -- row of its own: the ADJUSTMENT is still the cash event, and the
      -- legacy adjustment arm below already reports it. Without this the
      -- same money is counted twice -- the trap 292 hit for loans.
      AND  o.sourceadjustmentid IS NULL

      AND  o.transactiondate >= v_from

      AND  o.transactiondate <= v_to;



    -- ---- 5. loans received (259) -------------------------------------------

    -- Borrowed money arriving. FINANCING: the business received it, it did not

    -- earn it, so it is money in and never revenue.

    --

    -- The AMOUNT RECEIVED, not the principal. A lender that withholds a fee

    -- pays out less than it lends, and only what arrived is cash in.

    --

    -- The timestamp carries 256's rule, baked in from the start rather than

    -- patched afterwards as it had to be on poultry: loandate is a DATE, so a

    -- plain cast gives midnight and a loan recorded this afternoon sorts below

    -- everything else recorded today. A loan dated TODAY reports the moment it

    -- was recorded; a BACK-DATED one keeps midnight, because using createdat

    -- unconditionally would drag last Tuesday's loan into today, above rows

    -- that really did happen after it.

    RETURN QUERY

    SELECT 'Loan'::text,

           FALSE,

           l.waterloanid,

           l.watercashaccountid,

           a.accountname::text,

           CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                ELSE l.loandate::timestamp END,

           'CashIn'::text,

           'LoanReceived'::text,

           l.waterloanid,

           FALSE,

           l.amountreceived::numeric,

           ('Loan received from ' || l.lendername)::text,

           'FinancingIn'::text

           , l.createdat   -- 302: the entry time
    FROM   waterloans l

    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = l.watercashaccountid

    WHERE  l.farmid = p_farmid

      AND  l.amountreceived > 0

      -- 293. A loan converted from a Cash Flow adjustment has NO cash row of

      -- its own: the ADJUSTMENT is the cash event, and the legacy adjustment arm

      -- already reports it. Without this the same borrowing is money-in twice --

      -- which is precisely what 292's stage check caught on the poultry side.

      AND  l.sourceadjustmentid IS NULL

      AND  l.status NOT IN ('Cancelled', 'Reversed', 'Draft')

      AND  (CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                 ELSE l.loandate::timestamp END) >= v_from

      AND  (CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                 ELSE l.loandate::timestamp END) <= v_to;



    -- ---- 6. loan repayments (259) ------------------------------------------

    -- The FULL payment leaves the account, so the full payment is money out --

    -- principal, interest and fees together.

    --

    -- This does NOT double count the interest and fee expenses those payments

    -- create: they are written paymentmethod = 'NonCash', and arm 3 above now

    -- skips NonCash. Expense reports read the expense table directly and still

    -- count them, which is the whole point -- cash out is 12,500, cost is 2,500.

    RETURN QUERY

    SELECT 'LoanPayment'::text,

           FALSE,

           p.waterloanpaymentid,

           p.watercashaccountid,

           a.accountname::text,

           p.paymentdate,

           'CashOut'::text,

           'LoanRepayment'::text,

           p.waterloanid,

           FALSE,

           -p.totalamount::numeric,

           ('Loan repayment to ' || l.lendername)::text,

           'FinancingOut'::text

           , p.createdat   -- 302: the entry time
    FROM   waterloanpayments p

    JOIN   waterloans l ON l.waterloanid = p.waterloanid

    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = p.watercashaccountid

    WHERE  p.farmid = p_farmid

      AND  p.status = 'Posted'

      AND  p.paymentdate >= v_from

      AND  p.paymentdate <= v_to;



    -- ---- 7. capital in and out (legacy cash adjustments) --------------------

    -- Expected to return nothing on Water today -- see 236's header note.

    --

    -- MUST STAY LAST: it RETURNs early when the table is absent, and anything

    -- below it would be silently skipped.

    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,

                      to_regclass('public.cashadjustments')::text);



    -- 302: only reference the creation column if the resolved table has one.
    SELECT CASE WHEN EXISTS (
               SELECT 1 FROM information_schema.columns c
               WHERE  c.table_schema = 'public'
                 AND  c.table_name = replace(v_tbl, 'public.', '')
                 AND  c.column_name = 'createddate')
           THEN 'ca.createddate' ELSE 'NULL::timestamp' END
      INTO v_createdcol;

    IF v_tbl IS NULL THEN

        RETURN;

    END IF;



    RETURN QUERY EXECUTE format($sql$

        SELECT 'Adjustment'::text,

               FALSE,

               ca.adjustmentid,

               NULL::integer,

               NULL::text,

               ca.adjustmentdate,

               CASE WHEN ca.amount >= 0 THEN 'CashIn' ELSE 'CashOut' END::text,

               COALESCE(NULLIF(btrim(ca.adjustmenttype), ''), 'Adjustment')::text,

               ca.adjustmentid,

               FALSE,

               ca.amount::numeric,

               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text,

               CASE WHEN ca.amount >= 0 THEN 'FinancingIn' ELSE 'FinancingOut' END::text,
               %s                       -- 302: the entry time

        FROM   %s ca

        WHERE  lower(ca.farmid::text) = lower($1)

          AND  ca.amount <> 0

          AND  ca.adjustmentdate >= $2

          AND  ca.adjustmentdate <= $3

    $sql$, v_createdcol, v_tbl)

    USING p_farmid, v_from, v_to;
    -- ---- 8. employee advances (313/315) ------------------------------------

    -- Disbursements out, manual repayments in, payroll deductions NOWHERE:

    -- a deduction moves no money, so it is not a cash event. The arms live in

    -- their own function, so this body is touched once and never again.

    RETURN QUERY

    SELECT * FROM public.spwateremployeeloan_cashflowrows(p_farmid, v_from, v_to);


END;

$function$;

-- 458: reverses the delivery sales' payments instead of annotating them.
CREATE OR REPLACE FUNCTION public.spwaterdriverreturn_reverse(p_waterdriverreturnid integer, p_farmid text, p_reversedby text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status      text;
    v_loadingid   integer;
    v_sale        record;
    v_reversenote text;
BEGIN
    SELECT dr.status, dr.watervehicleloadingid
      INTO v_status, v_loadingid
    FROM   waterdriverreturns dr
    WHERE  dr.waterdriverreturnid = p_waterdriverreturnid AND dr.farmid = p_farmid
    LIMIT  1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Driver return % not found.', p_waterdriverreturnid;
    END IF;
    IF v_status <> 'Approved' THEN
        RAISE EXCEPTION 'Only Approved driver returns can be reversed. Current status: %.', v_status;
    END IF;

    -- 1. Cancel sales created from this run (SourceType='DeliveryRun', SourceId=ReturnId).
    FOR v_sale IN
        SELECT s.watersaleid, s.amountpaid
        FROM   watersales s
        WHERE  s.farmid = p_farmid
          AND  s.sourcetype = 'DeliveryRun'
          AND  s.sourceid   = p_waterdriverreturnid
          AND  COALESCE(s.status, '') NOT IN ('Cancelled','Reversed')
    LOOP
        -- 458: the sale's payments are REVERSED (status, by, when, why) with
        -- their allocations. Before, only their note was annotated: they stayed
        -- Posted and Cash Flow kept counting money the return took back.
        UPDATE customerpaymentallocation ca
        SET    status = 'Reversed', reversedby = p_reversedby, reversedat = (now() at time zone 'utc'),
               reversalreason = 'Driver return reversed' || COALESCE(': ' || NULLIF(btrim(p_reason), ''), '')
        FROM   waterpayments p
        WHERE  p.farmid = p_farmid AND p.watersaleid = v_sale.watersaleid
          AND  ca.farmid = p.farmid AND ca.module = 'water' AND ca.paymentid = p.waterpaymentid
          AND  ca.status = 'Posted';
        UPDATE waterpayments p
        SET    status = 'Reversed', reversedby = p_reversedby, reversedat = (now() at time zone 'utc'),
               reversalreason = 'Driver return reversed' || COALESCE(': ' || NULLIF(btrim(p_reason), ''), '')
        WHERE  p.farmid = p_farmid
          AND  p.watersaleid = v_sale.watersaleid
          AND  COALESCE(p.status, 'Posted') = 'Posted';

        -- Cancel the sale itself.
        UPDATE watersales s
        SET    status      = 'Cancelled',
               updateddate = (now() at time zone 'utc'),
               notes       = left(COALESCE(s.notes, '') || chr(10) || 'Reversed - delivery reconciliation reversed.', 500)
        WHERE  s.watersaleid = v_sale.watersaleid AND s.farmid = p_farmid;
        -- 422: credit applied to this sale is the customer's again.
        PERFORM public.fnwatersale_releasecredit(p_farmid, v_sale.watersaleid, p_reversedby, 'Delivery return reversed');
    END LOOP;

    -- 2. Reverse the LoadReturnIn stock txns this reconciliation created.
    v_reversenote := concat('Reverse reconciliation - driver return #', p_waterdriverreturnid);

    INSERT INTO waterstocktransactions
        (farmid, waterproductid, txntype, quantity, unitcost, relatedsaleid, note, createdby)
    SELECT st.farmid, st.waterproductid, 'Adjust', -st.quantity, NULL, NULL,
           v_reversenote, p_reversedby
    FROM   waterstocktransactions st
    WHERE  st.farmid = p_farmid
      AND  st.txntype = 'LoadReturnIn'
      AND  st.note LIKE concat('Driver return #', p_waterdriverreturnid, '%');

    -- 3. Flip loading back to "Returned" so the user can edit the return.
    UPDATE watervehicleloadings l
    SET    status = 'Returned', updatedat = (now() at time zone 'utc')
    WHERE  l.watervehicleloadingid = v_loadingid AND l.farmid = p_farmid;

    -- 4. Flip the return back to Draft + record the reversal.
    UPDATE waterdriverreturns dr
    SET    status     = 'Draft',
           approvedby = NULL,
           approvedat = NULL,
           updatedat  = (now() at time zone 'utc'),
           notes      = left(COALESCE(dr.notes, '') || chr(10) ||
                             'Reversed by ' || COALESCE(p_reversedby, '') ||
                             '. Reason: ' || COALESCE(p_reason, '(none)'), 1000)
    WHERE  dr.waterdriverreturnid = p_waterdriverreturnid AND dr.farmid = p_farmid;
END;
$function$;


-- ------------------------------------------------------------ 9. permissions --
-- POST api/Water/sales/{id}/reverse resolves to `approve`, and the catalog has
-- no water.sales.approve. Seed it, carried over from whoever could DELETE a
-- sale -- reversing is what delete has become (as 351 did for poultry).
DO $iam$
DECLARE
    v_keys  integer := 0;
    v_roles integer := 0;
    v_users integer := 0;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '458: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'water.sales.approve', p.module, p.resource, 'approve',
           p.permissiongroup, p.resourcelabel,
           'Reverse a saved sale (and Edit & repost, which reverses it first). Puts its stock back, '
           || 'releases its allocations; its payments are reversed or kept as customer credit.',
           p.companytype, TRUE, p.sortorder
    FROM   iampermissions p
    WHERE  p.permissionkey = 'water.sales.delete'
    ON CONFLICT (permissionkey) DO NOTHING;
    GET DIAGNOSTICS v_keys = ROW_COUNT;

    IF to_regclass('public.iamrolepermissions') IS NOT NULL THEN
        INSERT INTO iamrolepermissions (roleid, permissionkey)
        SELECT rp.roleid, 'water.sales.approve'
        FROM   iamrolepermissions rp
        WHERE  rp.permissionkey = 'water.sales.delete'
          AND  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = 'water.sales.approve')
        ON CONFLICT (roleid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_roles = ROW_COUNT;
    END IF;

    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        INSERT INTO iamuserpermissions (userid, farmid, permissionkey, effect, reason, grantedby, grantedat)
        SELECT up.userid, up.farmid, 'water.sales.approve', up.effect,
               'Carried over from water.sales.delete by migration 458',
               up.grantedby, (now() at time zone 'utc')
        FROM   iamuserpermissions up
        WHERE  up.permissionkey = 'water.sales.delete'
          AND  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = 'water.sales.approve')
          AND  (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_users = ROW_COUNT;
    END IF;

    RAISE NOTICE '458: % catalog key(s), % role grant(s), % user grant(s) added.', v_keys, v_roles, v_users;
END
$iam$;

COMMIT;

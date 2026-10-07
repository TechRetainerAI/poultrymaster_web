-- =============================================================================
-- 343_PoultryEggSortingIntegration.postgres.sql      (requires 341 and 342)
--
-- Purpose
-- -------
-- Wires egg classes and sorting into the rest of the farm:
--
--   1. Sorting settings: turn sorting on (seeds the sizes) and choose what
--      Daily Closing does with unsorted eggs.
--   2. Multi-size egg sale: ONE entry that sells several classes (Large +
--      Medium + Unsorted ...) as several sale rows sharing a sale number
--      (SG-00001), atomically, with ONE payment allocated across them when it
--      is paid at the point of sale -- the existing multi-sale payment
--      (sppoultrycustomerpayment_record), so balances, cash, PAY numbers and
--      every sales report keep working on rows they already understand.
--   3. The egg ledger: every movement of every egg class with a running
--      balance per class -- the one coherent ledger the Egg Tracker shows.
--   4. Size composition: by production date, flock, batch, flock age, pick,
--      or sorting date. Pick composition reads ByPick sessions ONLY; a
--      Combined session is never attributed to a pick. Other groupings share
--      a Combined session across its source records by quantity.
--   5. Daily Closing: an "eggs.unsorted" check, Warning by default, Blocking
--      only when the farm says so, nothing when sorting is off.
--
-- DAILY CLOSING WRAPPER
-- =====================
-- sppoultrydailyclosing_workspace is ~400 lines (333 plus later edits that
-- live only in the database). Rather than copy it, the live function is
-- renamed to sppoultrydailyclosing_workspace_core and a thin function with the
-- original name and signature calls it and appends the sorting check. Every
-- caller -- including sppoultrydailyclosing_close, which resolves the name at
-- run time -- gets the check. A FUTURE migration that redefines
-- sppoultrydailyclosing_workspace must redefine _core instead, or it will
-- silently drop this wrapper.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Settings
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryeggsortingsettings_set(
    p_farmid text, p_enableeggsorting boolean, p_closingpolicy text DEFAULT 'Warning', p_by text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF COALESCE(p_closingpolicy, 'Warning') NOT IN ('Off', 'Warning', 'Blocking') THEN
        RAISE EXCEPTION 'Daily Closing can treat unsorted eggs as Off, Warning or Blocking.';
    END IF;
    INSERT INTO poultryeggsortingsettings (farmid, enableeggsorting, closingpolicy, updatedby, updatedatutc)
    VALUES (p_farmid, COALESCE(p_enableeggsorting, FALSE), COALESCE(p_closingpolicy, 'Warning'), p_by, now())
    ON CONFLICT (farmid) DO UPDATE
    SET enableeggsorting = EXCLUDED.enableeggsorting, closingpolicy = EXCLUDED.closingpolicy,
        updatedby = EXCLUDED.updatedby, updatedatutc = now();

    IF COALESCE(p_enableeggsorting, FALSE) THEN
        PERFORM public.sppoultryeggsizes_ensure(p_farmid, p_by);
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. Multi-size egg sale
-- -----------------------------------------------------------------------------
-- p_linesjson: [{"product":"Fresh Eggs","eggProductId":123|null,"quantity":300,
--                "unitPrice":20,"totalAmount":200}, ...]   quantity in EGGS.
CREATE OR REPLACE FUNCTION public.sppoultrysale_creategroup(
    p_farmid text, p_userid text, p_saledate timestamp without time zone,
    p_customername text, p_customerid integer, p_paymentmethod text,
    p_cashaccountid integer, p_paid boolean, p_description text, p_flockid integer,
    p_linesjson text)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_lines   jsonb := COALESCE(NULLIF(btrim(COALESCE(p_linesjson, '')), ''), '[]')::jsonb;
    v_cust    integer := p_customerid;
    v_group   text;
    v_ids     integer[] := '{}';
    v_id      integer;
    v_total   numeric(14,2) := 0;
    v_alloc   jsonb := '[]'::jsonb;
    v_walkin  boolean;
    ln        jsonb;
BEGIN
    IF jsonb_typeof(v_lines) <> 'array' OR jsonb_array_length(v_lines) = 0 THEN
        RAISE EXCEPTION 'Add at least one line to the sale.';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_lines) e
               WHERE COALESCE((e->>'quantity')::numeric, 0) <= 0
                  OR COALESCE((e->>'totalAmount')::numeric, -1) < 0
                  OR btrim(COALESCE(e->>'product', '')) = '') THEN
        RAISE EXCEPTION 'Every line needs a product, a quantity above 0 and an amount.';
    END IF;
    IF p_cashaccountid IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = p_cashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
    END IF;

    IF v_cust IS NULL THEN
        v_cust := fnpoultrycustomer_resolve(p_farmid, p_customername, p_userid);
    ELSIF NOT EXISTS (SELECT 1 FROM customer c WHERE c.customerid = v_cust AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Customer does not belong to this company.';
    END IF;
    -- A walk-in (no customer) cannot carry a customer payment, so a paid
    -- walk-in sale is recorded paid on each row exactly as a single sale is.
    v_walkin := v_cust IS NULL;

    PERFORM pg_advisory_xact_lock(hashtext('poultry-salegroup-no:' || p_farmid));
    SELECT 'SG-' || lpad((COALESCE(max(NULLIF(regexp_replace(s.salegroupno, '\D', '', 'g'), '')::int), 0) + 1)::text, 5, '0')
    INTO   v_group
    FROM   sale s WHERE s.farmid = p_farmid AND s.salegroupno LIKE 'SG-%';

    FOR ln IN SELECT value FROM jsonb_array_elements(v_lines) LOOP
        v_id := public.spsale_insert(
            p_userid => p_userid, p_farmid => p_farmid, p_saledate => p_saledate,
            p_product => btrim(ln->>'product'),
            p_quantity => (ln->>'quantity')::numeric,
            p_unitprice => COALESCE((ln->>'unitPrice')::numeric, 0),
            p_totalamount => (ln->>'totalAmount')::numeric,
            p_paymentmethod => p_paymentmethod, p_customername => p_customername,
            p_flockid => p_flockid, p_saledescription => p_description,
            p_paid => (COALESCE(p_paid, FALSE) AND v_walkin),
            p_size => NULL, p_customerid => v_cust);

        PERFORM public.sppoultrysale_setegg(p_farmid, v_id, NULLIF(ln->>'eggProductId', '')::int, v_group, p_userid);

        PERFORM public.sppoultrysalecash_sync(p_farmid, v_id, p_cashaccountid, (ln->>'totalAmount')::numeric,
                                              (COALESCE(p_paid, FALSE) AND v_walkin), p_description, p_userid);
        PERFORM public.sppoultrycashtransaction_setbusinessdate(p_farmid, 'Sale', v_id, p_saledate);

        v_ids   := v_ids || v_id;
        v_total := v_total + (ln->>'totalAmount')::numeric;
        IF (ln->>'totalAmount')::numeric > 0 THEN
            v_alloc := v_alloc || jsonb_build_array(jsonb_build_object('saleid', v_id, 'amount', (ln->>'totalAmount')::numeric));
        END IF;
    END LOOP;

    -- Paid now by a known customer: one payment event across every line.
    IF COALESCE(p_paid, FALSE) AND NOT v_walkin AND v_total > 0 THEN
        PERFORM public.sppoultrycustomerpayment_record(
            p_farmid => p_farmid, p_customerid => v_cust, p_amount => v_total, p_allocations => v_alloc,
            p_paymentmethod => p_paymentmethod, p_paymentdate => p_saledate, p_cashaccountid => p_cashaccountid,
            p_reference => v_group, p_note => 'Paid at point of sale', p_sourcetype => 'SaleEntry',
            p_createdby => p_userid);
    END IF;

    RETURN jsonb_build_object('saleGroupNo', v_group, 'saleIds', to_jsonb(v_ids), 'totalAmount', v_total);
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. The egg ledger, every class, one running balance per class
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryeggledger(
    p_farmid text, p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL, p_poultryproductid integer DEFAULT NULL)
RETURNS TABLE (transactionid integer, createdatutc timestamp without time zone, businessdate date,
               txntype text, poultryproductid integer, classname text, classkind text,
               quantityin numeric, quantityout numeric, runningbalance numeric,
               relatedid integer, note text, createdby text,
               flockid integer, flockname text, productionrecordid integer, picknumbers text,
               sortingsessionno text, saleid integer, customername text, salegroupno text, reference text)
LANGUAGE sql
STABLE
AS $function$
    WITH cls AS (
        SELECT c.poultryproductid, c.name, c.classkind FROM public.sppoultryeggclasses_get(p_farmid, TRUE) c
    ),
    t AS (
        SELECT t.poultrystocktransactionid, t.createddate, t.txntype::text AS txntype, t.poultryproductid,
               t.quantity, t.relatedid, t.note::text AS note, t.createdby::text AS createdby,
               SUM(t.quantity) OVER (PARTITION BY t.poultryproductid
                                     ORDER BY t.createddate, t.poultrystocktransactionid) AS bal
        FROM   poultrystocktransactions t
        WHERE  t.farmid = p_farmid AND t.poultryproductid IN (SELECT poultryproductid FROM cls)
          AND  (p_poultryproductid IS NULL OR t.poultryproductid = p_poultryproductid)
    )
    SELECT t.poultrystocktransactionid, t.createddate,
           COALESCE(CASE WHEN t.txntype = 'Production' THEN pr.date
                         WHEN t.txntype = 'Sale' THEN sa.saledate
                         WHEN t.txntype LIKE 'Sorting%' THEN se.sortingdate END,
                    t.createddate::date) AS businessdate,
           t.txntype, t.poultryproductid, cls.name, cls.classkind,
           GREATEST(t.quantity, 0), GREATEST(-t.quantity, 0), t.bal,
           t.relatedid, t.note, t.createdby,
           COALESCE(pr.flockid, se.flockid, sa.flockid),
           COALESCE(fp.name, fs.name, fa.name)::text,
           CASE WHEN t.txntype = 'Production' THEN t.relatedid END,
           CASE WHEN t.txntype LIKE 'Sorting%' THEN
                (SELECT string_agg(DISTINCT 'P' || src.picknumber, ', ')
                 FROM poultryeggsortingsources src WHERE src.sessionid = t.relatedid) END,
           se.sessionno,
           CASE WHEN t.txntype = 'Sale' THEN t.relatedid END,
           sa.customername::text, sa.salegroupno,
           CASE WHEN t.txntype LIKE 'Sorting%' THEN se.sessionno
                WHEN t.txntype = 'Sale' THEN COALESCE(sa.salegroupno, 'Sale #' || t.relatedid)
                WHEN t.txntype = 'Production' THEN 'Production #' || t.relatedid
                WHEN t.relatedid IS NOT NULL THEN '#' || t.relatedid END
    FROM   t
    JOIN   cls ON cls.poultryproductid = t.poultryproductid
    LEFT   JOIN productionrecords pr ON t.txntype = 'Production' AND pr.id = t.relatedid AND pr.farmid = p_farmid
    LEFT   JOIN sale sa ON t.txntype = 'Sale' AND sa.saleid = t.relatedid AND sa.farmid = p_farmid
    LEFT   JOIN poultryeggsortingsessions se ON t.txntype LIKE 'Sorting%' AND se.sessionid = t.relatedid AND se.farmid = p_farmid
    LEFT   JOIN flock fp ON fp.flockid = pr.flockid
    LEFT   JOIN flock fs ON fs.flockid = se.flockid
    LEFT   JOIN flock fa ON fa.flockid = sa.flockid
    WHERE  (p_fromdate IS NULL OR t.createddate >= p_fromdate)
      AND  (p_todate   IS NULL OR t.createddate <  p_todate + 1)
    ORDER  BY t.createddate DESC, t.poultrystocktransactionid DESC;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Size composition
-- -----------------------------------------------------------------------------
-- p_groupby: 'productiondate' | 'sortingdate' | 'flock' | 'batch' | 'age' | 'pick'
-- The date range filters PRODUCTION date, except for 'sortingdate'.
-- One row per group x line kind (a size, or a loss type). quantity is eggs.
CREATE OR REPLACE FUNCTION public.sppoultryeggsorting_composition(
    p_farmid text, p_fromdate date, p_todate date, p_groupby text DEFAULT 'productiondate',
    p_flockid integer DEFAULT NULL)
RETURNS TABLE (groupkey text, grouplabel text, groupsort text, linetype text, eggsizeid integer,
               sizename text, sizesort integer, quantity numeric, sessions integer, combinedsessions integer)
LANGUAGE sql
STABLE
AS $function$
    WITH ses AS (
        SELECT s.* FROM poultryeggsortingsessions s
        WHERE  s.farmid = p_farmid AND s.status = 'Posted'
          AND  (p_flockid IS NULL OR s.flockid = p_flockid)
          AND  (p_groupby <> 'pick' OR s.sortingmode = 'ByPick')
    ),
    -- Each line spread over the session's sources by quantity. A ByPick
    -- session has one source, so its share is exact.
    share AS (
        SELECT ses.sessionid, ses.sortingmode, ses.sortingdate, src.productionrecordid, src.picknumber,
               src.flockid, src.productiondate,
               l.linetype, l.eggsizeid, l.quantity::numeric * src.quantity / NULLIF(ses.inputquantity, 0) AS qty
        FROM   ses
        JOIN   poultryeggsortingsources src ON src.sessionid = ses.sessionid
        JOIN   poultryeggsortinglines l     ON l.sessionid = ses.sessionid
    ),
    keyed AS (
        SELECT sh.*,
               CASE p_groupby
                    WHEN 'sortingdate' THEN sh.sortingdate::text
                    WHEN 'flock'       THEN sh.flockid::text
                    WHEN 'batch'       THEN COALESCE(f.batchid::text, 'none')
                    WHEN 'age'         THEN ((sh.productiondate - f.startdate) / 7)::text
                    WHEN 'pick'        THEN sh.picknumber::text
                    ELSE sh.productiondate::text END AS gkey,
               CASE p_groupby
                    WHEN 'sortingdate' THEN to_char(sh.sortingdate, 'FMDD Mon YYYY')
                    WHEN 'flock'       THEN COALESCE(f.name, 'Flock ' || sh.flockid)
                    WHEN 'batch'       THEN COALESCE(b.batchname, 'No batch')
                    WHEN 'age'         THEN 'Week ' || ((sh.productiondate - f.startdate) / 7)
                    WHEN 'pick'        THEN 'Pick ' || sh.picknumber
                    ELSE to_char(sh.productiondate, 'FMDD Mon YYYY') END AS glabel,
               CASE p_groupby
                    WHEN 'sortingdate' THEN to_char(sh.sortingdate, 'YYYY-MM-DD')
                    WHEN 'flock'       THEN COALESCE(f.name, '')
                    WHEN 'batch'       THEN COALESCE(b.batchname, '~')
                    WHEN 'age'         THEN lpad(((sh.productiondate - f.startdate) / 7)::text, 4, '0')
                    WHEN 'pick'        THEN sh.picknumber::text
                    ELSE to_char(sh.productiondate, 'YYYY-MM-DD') END AS gsort
        FROM   share sh
        LEFT   JOIN flock f ON f.flockid = sh.flockid
        LEFT   JOIN mainflockbatch b ON b.batchid = f.batchid AND b.farmid = f.farmid
        WHERE  CASE WHEN p_groupby = 'sortingdate' THEN sh.sortingdate ELSE sh.productiondate END
               BETWEEN p_fromdate AND p_todate
    )
    SELECT k.gkey, MAX(k.glabel), MAX(k.gsort), k.linetype, k.eggsizeid, MAX(z.name)::text,
           COALESCE(MAX(z.sortorder), 100000),
           ROUND(SUM(k.qty), 2),
           COUNT(DISTINCT k.sessionid)::int,
           COUNT(DISTINCT k.sessionid) FILTER (WHERE k.sortingmode = 'Combined')::int
    FROM   keyed k
    LEFT   JOIN poultryeggsizes z ON z.eggsizeid = k.eggsizeid
    GROUP  BY k.gkey, k.linetype, k.eggsizeid
    ORDER  BY 3, 7, 4;
$function$;

-- Production vs sorted vs still unsorted, per production date (carryover).
CREATE OR REPLACE FUNCTION public.sppoultryeggsorting_carryover(
    p_farmid text, p_fromdate date, p_todate date, p_flockid integer DEFAULT NULL)
RETURNS TABLE (productiondate date, records integer, gross bigint, collectionloss bigint,
               saleable bigint, sorted bigint, leftunsorted bigint)
LANGUAGE sql
STABLE
AS $function$
    SELECT r.productiondate, COUNT(*)::int, SUM(r.recordgross)::bigint, SUM(r.recordcollectionloss)::bigint,
           SUM(r.recordsaleable)::bigint, SUM(r.recordsorted)::bigint, SUM(r.recordleft)::bigint
    FROM (
        SELECT DISTINCT ON (x.productionrecordid) x.*
        FROM   public.sppoultryeggsorting_picks(p_farmid, p_fromdate, p_todate, p_flockid, NULL) x
    ) r
    GROUP  BY r.productiondate
    ORDER  BY r.productiondate DESC;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Daily Closing
-- -----------------------------------------------------------------------------
DO $rename$
BEGIN
    IF to_regprocedure('public.sppoultrydailyclosing_workspace_core(text,date,timestamp with time zone)') IS NULL THEN
        ALTER FUNCTION public.sppoultrydailyclosing_workspace(text, date, timestamp with time zone)
            RENAME TO sppoultrydailyclosing_workspace_core;
    END IF;
END;
$rename$;

CREATE OR REPLACE FUNCTION public.sppoultrydailyclosing_workspace(
    p_farmid text, p_businessdate date DEFAULT NULL::date, p_asof timestamp with time zone DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_ws      jsonb := public.sppoultrydailyclosing_workspace_core(p_farmid, p_businessdate, p_asof);
    v_date    date;
    v_on      boolean;
    v_policy  text;
    v_prod    bigint;
    v_sorted  bigint;
    v_left    bigint;
    v_onhand  numeric;
    v_checks  jsonb;
    v_item    jsonb;
BEGIN
    SELECT g.enableeggsorting, g.closingpolicy INTO v_on, v_policy
    FROM   public.sppoultryeggsortingsettings_get(p_farmid) g;
    IF NOT COALESCE(v_on, FALSE) OR v_policy = 'Off' THEN
        RETURN v_ws;
    END IF;

    v_date := (v_ws->>'businessDate')::date;
    SELECT COALESCE(SUM(c.saleable), 0), COALESCE(SUM(c.sorted), 0), COALESCE(SUM(c.leftunsorted), 0)
    INTO   v_prod, v_sorted, v_left
    FROM   public.sppoultryeggsorting_carryover(p_farmid, v_date, v_date) c;

    -- Eggs sold or used unsorted can never be sorted, so what is "waiting" is
    -- capped by what Unsorted actually holds.
    SELECT COALESCE(SUM(c.onhand), 0) INTO v_onhand
    FROM   public.sppoultryeggclasses_get(p_farmid) c WHERE c.classkind = 'Unsorted';
    v_left := LEAST(v_left, GREATEST(trunc(v_onhand), 0)::bigint);

    IF v_prod = 0 THEN
        RETURN v_ws || jsonb_build_object('eggSorting', jsonb_build_object(
            'enabled', TRUE, 'policy', v_policy, 'productionEggs', 0, 'sorted', 0, 'remainingUnsorted', 0));
    END IF;

    v_item := CASE WHEN v_left = 0
        THEN jsonb_build_object('key', 'eggs.unsorted', 'section', 'production', 'status', 'Complete',
                 'title', 'All eggs collected today are sorted',
                 'description', format('%s eggs sorted.', v_sorted), 'action', 'egg-sorting')
        ELSE jsonb_build_object('key', 'eggs.unsorted', 'section', 'production', 'status', v_policy,
                 'title', format('%s egg(s) from today are not sorted yet', v_left),
                 'description', format('Production %s, sorted %s, remaining %s.', v_prod, v_sorted, v_left),
                 'action', 'egg-sorting') END;

    SELECT COALESCE(jsonb_agg(c.value ORDER BY
               CASE c.value->>'status' WHEN 'Blocking' THEN 0 WHEN 'Warning' THEN 1 ELSE 2 END, c.ordinality), '[]'::jsonb)
    INTO   v_checks
    FROM   jsonb_array_elements(COALESCE(v_ws->'checklist', '[]'::jsonb) || jsonb_build_array(v_item)) WITH ORDINALITY c;

    RETURN v_ws
        || jsonb_build_object('checklist', v_checks,
               'counts', jsonb_build_object(
                   'blocking', (SELECT count(*) FROM jsonb_array_elements(v_checks) c WHERE c->>'status' = 'Blocking'),
                   'warning',  (SELECT count(*) FROM jsonb_array_elements(v_checks) c WHERE c->>'status' = 'Warning'),
                   'complete', (SELECT count(*) FROM jsonb_array_elements(v_checks) c WHERE c->>'status' = 'Complete')),
               'eggSorting', jsonb_build_object('enabled', TRUE, 'policy', v_policy,
                   'productionEggs', v_prod, 'sorted', v_sorted, 'remainingUnsorted', v_left));
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification. Every fixture is rolled back by the sentinel at the end.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    a   text := '44444444-3333-4333-8333-000000000343';
    d   date := current_date - 2;
    who text := '__343__';
    f1 integer; r1 integer;
    un integer; lg integer; md integer; sm integer;
    zl integer; zm integer; zs integer;
    s1 integer; s2 integer; v_ws jsonb; v_g jsonb; v_n numeric;
    acct integer;
BEGIN
    BEGIN
        INSERT INTO farms (id, farmid, name, email, type, timezoneid)
        VALUES (a, a, 'Selftest A', 'a@selftest.invalid', 'Poultry', 'UTC');
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'Flock 3', d - 140, 'Brown', 2000, TRUE, TRUE, -343, timestamp '2026-01-01') RETURNING flockid INTO f1;

        -- 66: sorting OFF -- production -> Unsorted, sold directly, no workspace.
        r1 := public.spproductionrecord_insert(a, who, who, 20, 140, d, 2000, 0, 2000, 0, NULL, 500, 600, 610, 1710, f1, 0);
        un := public.fnpoultry_unsortedeggproduct(a);
        v_ws := public.sppoultrydailyclosing_workspace(a, d);
        IF v_ws ? 'eggSorting' OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_ws->'checklist') c WHERE c->>'key' = 'eggs.unsorted') THEN
            RAISE EXCEPTION '343: sorting is off, Daily Closing must not mention it.';
        END IF;
        v_g := public.sppoultrysale_creategroup(a, who, d::timestamp, NULL, NULL, 'Cash', NULL, TRUE, NULL, NULL,
               json_build_array(json_build_object('product', 'Fresh Eggs', 'eggProductId', NULL, 'quantity', 1000,
                                                  'unitPrice', 16, 'totalAmount', 533.33))::text);
        IF (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = un) <> 710 THEN
            RAISE EXCEPTION '343: selling 1,000 unsorted should leave 710.';
        END IF;
        IF NOT (SELECT paid FROM sale WHERE saleid = (v_g->'saleIds'->>0)::int) THEN
            RAISE EXCEPTION '343: a paid walk-in line should be marked paid.';
        END IF;

        -- Turn sorting on: sizes seeded, Daily Closing warns about 710.
        PERFORM public.sppoultryeggsortingsettings_set(a, TRUE, 'Warning', who);
        SELECT eggsizeid, poultryproductid INTO zl, lg FROM poultryeggsizes WHERE farmid = a AND name = 'Large';
        SELECT eggsizeid, poultryproductid INTO zm, md FROM poultryeggsizes WHERE farmid = a AND name = 'Medium';
        SELECT eggsizeid, poultryproductid INTO zs, sm FROM poultryeggsizes WHERE farmid = a AND name = 'Small';
        v_ws := public.sppoultrydailyclosing_workspace(a, d);
        IF (SELECT c->>'status' FROM jsonb_array_elements(v_ws->'checklist') c WHERE c->>'key' = 'eggs.unsorted') <> 'Warning'
           OR (v_ws->'eggSorting'->>'remainingUnsorted')::int <> 710 THEN
            -- 1,710 produced, 1,000 of them sold unsorted: 710 can still be sorted.
            RAISE EXCEPTION '343: Daily Closing should warn that 710 eggs are unsorted: %', v_ws->'eggSorting';
        END IF;
        PERFORM public.sppoultryeggsortingsettings_set(a, TRUE, 'Blocking', who);
        v_ws := public.sppoultrydailyclosing_workspace(a, d);
        IF (v_ws->'counts'->>'blocking')::int < 1 THEN
            RAISE EXCEPTION '343: a Blocking policy must count as blocking.';
        END IF;

        -- Sort pick 1 by pick and the rest combined; 700 of the 710 left.
        s1 := public.sppoultryeggsorting_save(a, NULL, 'ByPick', d, ARRAY[r1], 1,
              json_build_array(json_build_object('lineType', 'SizedOutput', 'eggSizeId', zl, 'quantity', 300),
                               json_build_object('lineType', 'SizedOutput', 'eggSizeId', zm, 'quantity', 200))::text, NULL, NULL, who);
        PERFORM public.sppoultryeggsorting_post(a, s1, who);
        s2 := public.sppoultryeggsorting_save(a, NULL, 'Combined', d, ARRAY[r1], NULL,
              json_build_array(json_build_object('lineType', 'SizedOutput', 'eggSizeId', zl, 'quantity', 100),
                               json_build_object('lineType', 'SizedOutput', 'eggSizeId', zs, 'quantity', 90),
                               json_build_object('lineType', 'Reject', 'quantity', 10))::text, NULL, NULL, who);
        PERFORM public.sppoultryeggsorting_post(a, s2, who);
        IF (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = un) <> 10 THEN
            RAISE EXCEPTION '343: Unsorted should be 10 after sorting 700.';
        END IF;

        -- 55/56: pick composition uses ONLY the ByPick session.
        IF (SELECT SUM(quantity) FROM public.sppoultryeggsorting_composition(a, d, d, 'pick')) <> 500
           OR EXISTS (SELECT 1 FROM public.sppoultryeggsorting_composition(a, d, d, 'pick') WHERE combinedsessions > 0) THEN
            RAISE EXCEPTION '343: pick composition must come from by-pick sorting only.';
        END IF;
        IF (SELECT SUM(quantity) FROM public.sppoultryeggsorting_composition(a, d, d, 'productiondate')) <> 700
           OR (SELECT SUM(quantity) FROM public.sppoultryeggsorting_composition(a, d, d, 'flock') WHERE linetype = 'Reject') <> 10 THEN
            RAISE EXCEPTION '343: daily composition should hold all 700, loss included.';
        END IF;
        IF (SELECT leftunsorted FROM public.sppoultryeggsorting_carryover(a, d, d)) <> 1010 THEN
            RAISE EXCEPTION '343: carryover: 1,710 produced, 700 sorted, 1,010 not sorted from production.';
        END IF;

        -- 72/73: one sale, several classes, one payment.
        INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance)
        VALUES (a, 'Till', 'Cash', 0, 0) RETURNING poultrycashaccountid INTO acct;
        v_g := public.sppoultrysale_creategroup(a, who, d::timestamp, 'Market Woman A', NULL, 'Cash', acct, TRUE, NULL, NULL,
               json_build_array(
                   json_build_object('product', 'Fresh Eggs', 'eggProductId', lg, 'quantity', 300, 'unitPrice', 20, 'totalAmount', 200),
                   json_build_object('product', 'Fresh Eggs', 'eggProductId', md, 'quantity', 150, 'unitPrice', 18, 'totalAmount', 90),
                   json_build_object('product', 'Fresh Eggs', 'eggProductId', sm, 'quantity', 72, 'unitPrice', 15, 'totalAmount', 36),
                   json_build_object('product', 'Fresh Eggs', 'eggProductId', NULL, 'quantity', 10, 'unitPrice', 16, 'totalAmount', 5.33))::text);
        IF jsonb_array_length(v_g->'saleIds') <> 4
           OR (SELECT count(DISTINCT salegroupno) FROM sale WHERE saleid IN (SELECT (x)::int FROM jsonb_array_elements_text(v_g->'saleIds') x)) <> 1 THEN
            RAISE EXCEPTION '343: four lines, one sale number: %', v_g;
        END IF;
        IF (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = lg) <> 100
           OR (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = md) <> 50
           OR (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = sm) <> 18
           OR (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = un) <> 0 THEN
            RAISE EXCEPTION '343: each class should drop by its own line.';
        END IF;
        IF (SELECT count(DISTINCT paymentgroupid) FROM poultrypayments
            WHERE saleid IN (SELECT (x)::int FROM jsonb_array_elements_text(v_g->'saleIds') x)) <> 1
           OR (SELECT bool_and(paid) FROM sale WHERE saleid IN (SELECT (x)::int FROM jsonb_array_elements_text(v_g->'saleIds') x)) IS NOT TRUE
           OR (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = acct) <> 331.33 THEN
            RAISE EXCEPTION '343: one payment should settle all four lines and put 331.33 in the till.';
        END IF;

        -- Ledger: every class, running balance per class.
        IF (SELECT runningbalance FROM public.sppoultryeggledger(a, NULL, NULL, lg) LIMIT 1) <> 100 THEN
            RAISE EXCEPTION '343: the Large running balance should end at 100.';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.sppoultryeggledger(a) WHERE txntype = 'Sorting In' AND sortingsessionno IS NOT NULL) THEN
            RAISE EXCEPTION '343: sorting rows should carry their session number.';
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '__343_ok__';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;
    END;

    RAISE NOTICE '343_PoultryEggSortingIntegration: verified (no-sorting farm sells unsorted, Daily Closing silent when off / warns / blocks, by-pick vs combined composition, carryover, multi-class sale with one payment and one till entry, per-class ledger).';
END $$;

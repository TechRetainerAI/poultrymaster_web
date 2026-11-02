-- =============================================================================
-- 394: Egg packaging, phase 2 -- selling in Boxes, Crates and Pieces.
-- Needs 393 (the packaging configuration and conversion functions).
--
-- Stock is still taken in individual eggs: a line of 2 boxes + 3 crates +
-- 10 pcs at 14 crates/box takes exactly 940 eggs out of its class. Boxes are
-- never stock of their own.
--
--   1. Box and piece prices beside the existing price per crate (344): per
--      egg size, and for Unsorted / General. Optional: a missing box price is
--      crates-per-box x the crate price, a missing piece price is the crate
--      price shared over the crate (the pro-rata rule sales use today).
--      sppoultryeggclassprices_get / sppoultryeggclass_setprices.
--   2. saleline keeps what the line was ENTERED as and what it was PRICED at:
--      boxes / crates / pieces, eggs per crate, crates per box, the three unit
--      prices, the calculated amount, and whether the total was overridden.
--      All NULL on lines posted before 394 (or entered without packaging):
--      those are shown as derived equivalents, never as "boxes sold".
--   3. fnpoultry_eggpackagedamount: the one pricing rule.
--        boxes x box price + crates x crate price + pieces x piece price,
--        rounded once to the cent. Each part is a different portion of the
--        eggs, so a box is never charged again as crates.
--   4. sppoultrysale_creategroup (live body, read from dev 2026-11-02) gains:
--        - lines carrying boxes / crates / pieces are converted HERE, with
--          THIS company's configuration -- never the browser's -- and a
--          browser egg count that disagrees is refused;
--        - the line amount must equal the calculated amount unless the line
--          says the total was overridden (the existing Add Sale override);
--        - the conversion and prices are stored on the line, so a later
--          change of box size or price never changes a posted sale;
--        - the multi-line header's price per crate uses the farm's crate size
--          instead of a hardcoded 30.
--      Lines without packaging keys go exactly the old way.
--   5. fnpoultrysale_lines returns the snapshot, so sale details, the invoice
--      and every sale reader get it without changing.
--
-- Reversal needs no change: it restores the ledger rows the sale posted, which
-- are already individual eggs. Configuration changes after posting cannot
-- reach a posted sale (they are not read again).
--
-- Idempotent: safe to run twice.
-- =============================================================================

DO $pre$
BEGIN
    IF to_regprocedure('public.fnpoultry_eggpieces(integer,integer,integer,integer,integer)') IS NULL THEN
        RAISE EXCEPTION '394 needs 393 (egg packaging) first.';
    END IF;
END;
$pre$;

-- -----------------------------------------------------------------------------
-- 1. Box and piece prices
-- -----------------------------------------------------------------------------
ALTER TABLE public.poultryeggsizes ADD COLUMN IF NOT EXISTS priceperbox numeric(14,2)
    CHECK (priceperbox IS NULL OR priceperbox >= 0);
ALTER TABLE public.poultryeggsizes ADD COLUMN IF NOT EXISTS priceperpiece numeric(14,4)
    CHECK (priceperpiece IS NULL OR priceperpiece >= 0);
ALTER TABLE public.poultryeggsortingsettings ADD COLUMN IF NOT EXISTS unsortedpriceperbox numeric(14,2)
    CHECK (unsortedpriceperbox IS NULL OR unsortedpriceperbox >= 0);
ALTER TABLE public.poultryeggsortingsettings ADD COLUMN IF NOT EXISTS unsortedpriceperpiece numeric(14,4)
    CHECK (unsortedpriceperpiece IS NULL OR unsortedpriceperpiece >= 0);

-- Unsorted / General is the farm's raw egg product (same pick as sppoultryeggclasses_get).
CREATE OR REPLACE FUNCTION public.fnpoultry_unsortedeggproduct(p_farmid text)
RETURNS integer
LANGUAGE sql
STABLE
AS $function$
    SELECT pp.poultryproductid
    FROM   poultryproducts pp
    WHERE  pp.farmid = p_farmid AND (pp.israweggproduct = TRUE OR pp.name IN ('Eggs', 'Chicken Eggs'))
    ORDER  BY pp.israweggproduct DESC, pp.poultryproductid
    LIMIT  1;
$function$;

DROP FUNCTION IF EXISTS public.sppoultryeggclassprices_get(text);
CREATE FUNCTION public.sppoultryeggclassprices_get(p_farmid text)
RETURNS TABLE (poultryproductid integer, pricepercrate numeric, priceperbox numeric, priceperpiece numeric)
LANGUAGE sql
STABLE
AS $function$
    SELECT u.id, s.unsortedpricepercrate, s.unsortedpriceperbox, s.unsortedpriceperpiece
    FROM   (SELECT public.fnpoultry_unsortedeggproduct(p_farmid) AS id) u
    LEFT   JOIN poultryeggsortingsettings s ON s.farmid = p_farmid
    WHERE  u.id IS NOT NULL
    UNION ALL
    SELECT z.poultryproductid, z.pricepercrate, z.priceperbox, z.priceperpiece
    FROM   poultryeggsizes z
    WHERE  z.farmid = p_farmid;
$function$;

-- One class's three prices. NULL = not set (the fallback rule applies).
CREATE OR REPLACE FUNCTION public.sppoultryeggclass_setprices(
    p_farmid text, p_poultryproductid integer,
    p_pricepercrate numeric, p_priceperbox numeric, p_priceperpiece numeric, p_by text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_size   poultryeggsizes%ROWTYPE;
    v_before jsonb;
    v_name   text;
BEGIN
    IF COALESCE(p_pricepercrate, 0) < 0 OR COALESCE(p_priceperbox, 0) < 0 OR COALESCE(p_priceperpiece, 0) < 0 THEN
        RAISE EXCEPTION 'A price cannot be negative.';
    END IF;

    IF p_poultryproductid IS NOT DISTINCT FROM public.fnpoultry_unsortedeggproduct(p_farmid) THEN
        SELECT jsonb_build_object('pricePerBox', s.unsortedpriceperbox, 'pricePerPiece', s.unsortedpriceperpiece)
        INTO   v_before FROM poultryeggsortingsettings s WHERE s.farmid = p_farmid;
        INSERT INTO poultryeggsortingsettings (farmid, unsortedpricepercrate, unsortedpriceperbox, unsortedpriceperpiece,
                                               updatedby, updatedatutc)
        VALUES (p_farmid, round(p_pricepercrate, 2), round(p_priceperbox, 2), round(p_priceperpiece, 4), p_by, now())
        ON CONFLICT (farmid) DO UPDATE
        SET unsortedpricepercrate = EXCLUDED.unsortedpricepercrate,
            unsortedpriceperbox   = EXCLUDED.unsortedpriceperbox,
            unsortedpriceperpiece = EXCLUDED.unsortedpriceperpiece,
            updatedby = EXCLUDED.updatedby, updatedatutc = now();
        v_name := 'Unsorted / General';
    ELSE
        SELECT * INTO v_size FROM poultryeggsizes z
        WHERE  z.farmid = p_farmid AND z.poultryproductid = p_poultryproductid FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That egg class does not belong to this company.';
        END IF;
        v_before := jsonb_build_object('pricePerBox', v_size.priceperbox, 'pricePerPiece', v_size.priceperpiece);
        UPDATE poultryeggsizes
        SET    pricepercrate = round(p_pricepercrate, 2),
               priceperbox   = round(p_priceperbox, 2),
               priceperpiece = round(p_priceperpiece, 4)
        WHERE  eggsizeid = v_size.eggsizeid;
        v_name := v_size.name;
    END IF;

    -- The crate price is audited by the 344 triggers; box and piece prices here.
    IF v_before IS DISTINCT FROM jsonb_build_object('pricePerBox', round(p_priceperbox, 2), 'pricePerPiece', round(p_priceperpiece, 4)) THEN
        INSERT INTO poultryeggsortingaudit (farmid, entity, entityid, action, actor, details)
        VALUES (p_farmid, 'EggPrices', p_poultryproductid, 'PackagingPricesChanged', COALESCE(p_by, public.fnpoultryeggaudit_actor(NULL)),
                jsonb_build_object('name', v_name, 'pricePerBox', round(p_priceperbox, 2), 'pricePerPiece', round(p_priceperpiece, 4),
                                   'before', v_before));
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. The sale line keeps its packaging and prices
-- -----------------------------------------------------------------------------
ALTER TABLE public.saleline ADD COLUMN IF NOT EXISTS qtyboxes integer NULL;
ALTER TABLE public.saleline ADD COLUMN IF NOT EXISTS qtycrates integer NULL;
ALTER TABLE public.saleline ADD COLUMN IF NOT EXISTS qtypieces integer NULL;
ALTER TABLE public.saleline ADD COLUMN IF NOT EXISTS eggspercrate integer NULL;
ALTER TABLE public.saleline ADD COLUMN IF NOT EXISTS cratesperbox integer NULL;
ALTER TABLE public.saleline ADD COLUMN IF NOT EXISTS priceperbox numeric(14,2) NULL;
ALTER TABLE public.saleline ADD COLUMN IF NOT EXISTS pricepercrate numeric(14,2) NULL;
ALTER TABLE public.saleline ADD COLUMN IF NOT EXISTS priceperpiece numeric(14,4) NULL;
ALTER TABLE public.saleline ADD COLUMN IF NOT EXISTS calculatedamount numeric(14,2) NULL;
ALTER TABLE public.saleline ADD COLUMN IF NOT EXISTS amountoverridden boolean NULL;

DO $c$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_saleline_packaging') THEN
        ALTER TABLE public.saleline ADD CONSTRAINT ck_saleline_packaging CHECK (
            COALESCE(qtyboxes, 0) >= 0 AND COALESCE(qtycrates, 0) >= 0 AND COALESCE(qtypieces, 0) >= 0
            AND (eggspercrate IS NULL OR eggspercrate >= 1)
            AND (cratesperbox IS NULL OR cratesperbox >= 1)
            AND (COALESCE(qtyboxes, 0) = 0 OR cratesperbox IS NOT NULL));
    END IF;
END;
$c$;

-- -----------------------------------------------------------------------------
-- 3. The pricing rule
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultry_eggpackagedamount(
    p_boxes integer, p_crates integer, p_pieces integer, p_eggspercrate integer, p_cratesperbox integer,
    p_priceperbox numeric, p_pricepercrate numeric, p_priceperpiece numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT round(
          COALESCE(p_boxes, 0)  * COALESCE(p_priceperbox,   COALESCE(p_pricepercrate, 0) * COALESCE(p_cratesperbox, 0))
        + COALESCE(p_crates, 0) * COALESCE(p_pricepercrate, 0)
        + COALESCE(p_pieces, 0) * COALESCE(p_priceperpiece, COALESCE(p_pricepercrate, 0) / GREATEST(COALESCE(p_eggspercrate, 30), 1)::numeric),
        2);
$function$;

-- A whole, non-negative count from a JSON value, or an error naming the field.
CREATE OR REPLACE FUNCTION public.fnpoultry_jsoncount(p_v jsonb, p_key text, p_line integer)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
    v_t text := NULLIF(btrim(COALESCE(p_v->>p_key, '')), '');
    v_n numeric;
BEGIN
    IF v_t IS NULL THEN RETURN 0; END IF;
    BEGIN
        v_n := v_t::numeric;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Line %: % must be a whole number.', p_line, p_key;
    END;
    IF v_n < 0 THEN RAISE EXCEPTION 'Line %: % cannot be negative.', p_line, p_key; END IF;
    IF v_n <> trunc(v_n) THEN RAISE EXCEPTION 'Line %: % must be a whole number.', p_line, p_key; END IF;
    IF v_n > 100000000 THEN RAISE EXCEPTION 'Line %: % is too large.', p_line, p_key; END IF;
    RETURN v_n::integer;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Group create: the live body + packaged lines
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrysale_creategroup(p_farmid text, p_userid text, p_saledate timestamp without time zone, p_customername text, p_customerid integer, p_paymentmethod text, p_cashaccountid integer, p_paid boolean, p_description text, p_flockid integer, p_linesjson text, p_requestkey text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_lines   jsonb := COALESCE(NULLIF(btrim(COALESCE(p_linesjson, '')), ''), '[]')::jsonb;
    v_key     text  := NULLIF(btrim(COALESCE(p_requestkey, '')), '');
    v_cust    integer := p_customerid;
    v_walkin  boolean;
    v_paidrow boolean;
    v_group   text;
    v_id      integer;
    v_n       integer;
    v_qty     numeric(14,2);
    v_total   numeric(14,2);
    v_product text;
    v_isegg   boolean;
    v_bad     integer;
    -- 394: packaged egg lines
    v_pk      record;
    v_norm    jsonb := '[]'::jsonb;
    v_e       jsonb;
    v_ord     integer;
    v_b       integer;
    v_c       integer;
    v_p       integer;
    v_eggs    bigint;
    v_cpb     integer;
    v_bp      numeric;
    v_cp      numeric;
    v_pp      numeric;
    v_calc    numeric(14,2);
    v_amt     numeric(14,2);
    v_ovr     boolean;
BEGIN
    IF jsonb_typeof(v_lines) <> 'array' OR jsonb_array_length(v_lines) = 0 THEN
        RAISE EXCEPTION 'Add at least one line to the sale.';
    END IF;

    -- 394: an egg line entered as boxes / crates / pieces is converted here,
    -- with this company's configuration, and its pricing checked. The egg
    -- count it produces is the quantity from here on; the snapshot rides along
    -- in "_pk" and is written onto the line below.
    SELECT * INTO v_pk FROM public.fnpoultry_eggpackaging(p_farmid);
    FOR v_e, v_ord IN SELECT e.v, e.ord::int FROM jsonb_array_elements(v_lines) WITH ORDINALITY e(v, ord) LOOP
        IF (v_e ? 'boxes' OR v_e ? 'crates' OR v_e ? 'pieces')
           AND lower(btrim(COALESCE(v_e->>'product', ''))) LIKE '%egg%'
           AND public.fnpoultrysale_byproductrole(btrim(v_e->>'product')) IS NULL THEN
            v_b := public.fnpoultry_jsoncount(v_e, 'boxes', v_ord);
            v_c := public.fnpoultry_jsoncount(v_e, 'crates', v_ord);
            v_p := public.fnpoultry_jsoncount(v_e, 'pieces', v_ord);
            IF v_b > 0 AND NOT v_pk.enableboxes THEN
                RAISE EXCEPTION 'Line %: boxes are not turned on for this company. Enter crates and pieces, or turn boxes on in Egg Sorting > Sizes & settings.', v_ord;
            END IF;
            v_cpb  := CASE WHEN v_pk.enableboxes THEN v_pk.cratesperbox END;
            v_eggs := public.fnpoultry_eggpieces(v_b, v_c, v_p, v_pk.eggspercrate, v_cpb);
            IF v_eggs <= 0 THEN
                RAISE EXCEPTION 'Line %: enter at least one box, crate or egg.', v_ord;
            END IF;
            IF NULLIF(v_e->>'quantity', '') IS NOT NULL AND (v_e->>'quantity')::numeric <> v_eggs THEN
                RAISE EXCEPTION 'Line %: % eggs does not match % at this company''s packaging (% eggs). Reload the page and try again.',
                    v_ord, (v_e->>'quantity')::numeric, public.fnpoultry_eggqtytext(v_eggs, v_pk.eggspercrate, v_cpb, 'BoxesCratesPieces'), v_eggs;
            END IF;
            v_cp := round(COALESCE(NULLIF(v_e->>'unitPrice', '')::numeric, 0), 2);
            v_bp := round(NULLIF(v_e->>'pricePerBox', '')::numeric, 2);
            v_pp := round(NULLIF(v_e->>'pricePerPiece', '')::numeric, 4);
            IF v_cp < 0 OR COALESCE(v_bp, 0) < 0 OR COALESCE(v_pp, 0) < 0 THEN
                RAISE EXCEPTION 'Line %: a price cannot be negative.', v_ord;
            END IF;
            IF v_b = 0 THEN v_bp := NULL; END IF;     -- no boxes, no box price to keep
            IF v_p = 0 THEN v_pp := NULL; END IF;
            v_calc := public.fnpoultry_eggpackagedamount(v_b, v_c, v_p, v_pk.eggspercrate, v_cpb, v_bp, v_cp, v_pp);
            v_amt  := round(COALESCE(NULLIF(v_e->>'totalAmount', '')::numeric, v_calc), 2);
            v_ovr  := COALESCE(NULLIF(v_e->>'amountOverridden', '')::boolean, FALSE);
            IF NOT v_ovr AND abs(v_amt - v_calc) > 0.01 THEN
                RAISE EXCEPTION 'Line %: the amount % does not match % at these prices (%). Reload the page and try again.',
                    v_ord, v_amt, public.fnpoultry_eggqtytext(v_eggs, v_pk.eggspercrate, v_cpb, 'BoxesCratesPieces'), v_calc;
            END IF;
            v_e := v_e || jsonb_build_object(
                'quantity', v_eggs, 'totalAmount', v_amt,
                '_pk', jsonb_build_object(
                    'boxes', v_b, 'crates', v_c, 'pieces', v_p,
                    'eggsPerCrate', v_pk.eggspercrate, 'cratesPerBox', v_cpb,
                    'pricePerBox', CASE WHEN v_b > 0 THEN COALESCE(v_bp, v_cp * v_cpb) END,
                    'pricePerCrate', v_cp,
                    'pricePerPiece', CASE WHEN v_p > 0 THEN COALESCE(v_pp, round(v_cp / v_pk.eggspercrate, 4)) END,
                    'calculatedAmount', v_calc, 'amountOverridden', v_ovr));
        END IF;
        v_norm := v_norm || jsonb_build_array(v_e);
    END LOOP;
    v_lines := v_norm;

    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_lines) e
               WHERE COALESCE((e->>'quantity')::numeric, 0) <= 0
                  OR COALESCE((e->>'totalAmount')::numeric, -1) < 0
                  OR btrim(COALESCE(e->>'product', '')) = '') THEN
        RAISE EXCEPTION 'Every line needs a product, a quantity above 0 and an amount.';
    END IF;
    IF (SELECT COUNT(DISTINCT lower(btrim(e->>'product'))) FROM jsonb_array_elements(v_lines) e) > 1 THEN
        RAISE EXCEPTION 'Every line of one sale must be the same product (egg sizes may differ). Enter other products as their own sale.';
    END IF;
    SELECT NULLIF(e->>'eggProductId', '')::int INTO v_bad
    FROM   jsonb_array_elements(v_lines) e
    WHERE  NULLIF(e->>'eggProductId', '') IS NOT NULL
      AND  NOT public.fnpoultry_iseggclass(p_farmid, (e->>'eggProductId')::int)
    LIMIT  1;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'That egg class does not belong to this company.';
    END IF;
    IF p_cashaccountid IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM poultrycashaccounts a WHERE a.poultrycashaccountid = p_cashaccountid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
    END IF;

    -- A double-click, a retry after a timeout: the same request is the same sale.
    IF v_key IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext('poultry-salerequest:' || p_farmid || ':' || v_key));
        SELECT s.saleid, s.salegroupno, s.totalamount INTO v_id, v_group, v_total
        FROM   sale s WHERE s.farmid = p_farmid AND s.requestkey = v_key;
        IF FOUND THEN
            RETURN jsonb_build_object('saleGroupNo', v_group, 'saleId', v_id, 'saleIds', jsonb_build_array(v_id),
                                      'totalAmount', v_total, 'duplicate', true);
        END IF;
    END IF;

    IF v_cust IS NULL THEN
        v_cust := fnpoultrycustomer_resolve(p_farmid, p_customername, p_userid);
    ELSIF NOT EXISTS (SELECT 1 FROM customer c WHERE c.customerid = v_cust AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Customer does not belong to this company.';
    END IF;
    -- A walk-in (no customer) cannot carry a customer payment, so a paid
    -- walk-in sale is recorded paid on the sale itself, as a single sale is.
    v_walkin  := v_cust IS NULL;
    v_paidrow := COALESCE(p_paid, FALSE) AND v_walkin;

    v_product := btrim(v_lines->0->>'product');
    v_isegg   := lower(v_product) LIKE '%egg%' AND public.fnpoultrysale_byproductrole(v_product) IS NULL;   -- 374: a byproduct is not an egg sale
    SELECT COUNT(*), SUM(round((e->>'quantity')::numeric, 2)), SUM(round((e->>'totalAmount')::numeric, 2))
    INTO   v_n, v_qty, v_total
    FROM   jsonb_array_elements(v_lines) e;

    PERFORM pg_advisory_xact_lock(hashtext('poultry-salegroup-no:' || p_farmid));
    SELECT 'SG-' || lpad((COALESCE(max(NULLIF(regexp_replace(s.salegroupno, '\D', '', 'g'), '')::int), 0) + 1)::text, 5, '0')
    INTO   v_group
    FROM   sale s WHERE s.farmid = p_farmid AND s.salegroupno LIKE 'SG-%';

    IF v_n = 1 THEN
        -- One line: the ordinary sale path; its line mirrors the header.
        v_id := public.spsale_insert(
            p_userid => p_userid, p_farmid => p_farmid, p_saledate => p_saledate,
            p_product => v_product, p_quantity => v_qty,
            p_unitprice => COALESCE((v_lines->0->>'unitPrice')::numeric, 0),
            p_totalamount => v_total,
            p_paymentmethod => p_paymentmethod, p_customername => p_customername,
            p_flockid => p_flockid, p_saledescription => p_description,
            p_paid => v_paidrow, p_size => NULL, p_customerid => v_cust);
        PERFORM public.sppoultrysale_setegg(p_farmid, v_id, NULLIF(v_lines->0->>'eggProductId', '')::int, v_group, p_userid);
        -- 394: the mirrored line keeps what it was entered and priced as.
        IF v_lines->0 ? '_pk' THEN
            UPDATE saleline l
            SET    qtyboxes = (v_lines->0->'_pk'->>'boxes')::int,
                   qtycrates = (v_lines->0->'_pk'->>'crates')::int,
                   qtypieces = (v_lines->0->'_pk'->>'pieces')::int,
                   eggspercrate = (v_lines->0->'_pk'->>'eggsPerCrate')::int,
                   cratesperbox = NULLIF(v_lines->0->'_pk'->>'cratesPerBox', '')::int,
                   priceperbox = NULLIF(v_lines->0->'_pk'->>'pricePerBox', '')::numeric,
                   pricepercrate = (v_lines->0->'_pk'->>'pricePerCrate')::numeric,
                   priceperpiece = NULLIF(v_lines->0->'_pk'->>'pricePerPiece', '')::numeric,
                   calculatedamount = (v_lines->0->'_pk'->>'calculatedAmount')::numeric,
                   amountoverridden = (v_lines->0->'_pk'->>'amountOverridden')::boolean
            WHERE  l.saleid = v_id AND l.lineno = 1;
        END IF;
    ELSE
        INSERT INTO sale (userid, farmid, saledate, product, quantity, unitprice, totalamount, paymentmethod,
                          customername, customerid, flockid, saledescription, paid, size, poultryproductid,
                          salegroupno, ismultiline, createddate)
        VALUES (p_userid, p_farmid, p_saledate, v_product, v_qty,
                -- 394: the farm's crate size, not a hardcoded 30.
                CASE WHEN v_qty > 0 THEN round(v_total / CASE WHEN v_isegg THEN v_qty / public.fnpoultry_eggspercrate(p_farmid)::numeric ELSE v_qty END, 2) ELSE 0 END,
                v_total, p_paymentmethod, p_customername, v_cust, p_flockid, p_description, v_paidrow, NULL, NULL,
                v_group, TRUE, (now() AT TIME ZONE 'utc'))
        RETURNING saleid INTO v_id;

        INSERT INTO saleline (saleid, farmid, lineno, product, poultryproductid, size, quantity, unitprice, totalamount,
                              qtyboxes, qtycrates, qtypieces, eggspercrate, cratesperbox,
                              priceperbox, pricepercrate, priceperpiece, calculatedamount, amountoverridden)
        SELECT v_id, p_farmid, e.ord::int, btrim(e.v->>'product'),
               CASE WHEN v_isegg THEN z.poultryproductid END,
               CASE WHEN v_isegg THEN z.name END,
               round((e.v->>'quantity')::numeric, 2),
               round(COALESCE((e.v->>'unitPrice')::numeric, 0), 2),
               round((e.v->>'totalAmount')::numeric, 2),
               (e.v->'_pk'->>'boxes')::int, (e.v->'_pk'->>'crates')::int, (e.v->'_pk'->>'pieces')::int,
               (e.v->'_pk'->>'eggsPerCrate')::int, NULLIF(e.v->'_pk'->>'cratesPerBox', '')::int,
               NULLIF(e.v->'_pk'->>'pricePerBox', '')::numeric, (e.v->'_pk'->>'pricePerCrate')::numeric,
               NULLIF(e.v->'_pk'->>'pricePerPiece', '')::numeric,
               (e.v->'_pk'->>'calculatedAmount')::numeric, (e.v->'_pk'->>'amountOverridden')::boolean
        FROM   jsonb_array_elements(v_lines) WITH ORDINALITY e(v, ord)
        LEFT   JOIN poultryeggsizes z
               ON z.poultryproductid = NULLIF(e.v->>'eggProductId', '')::int AND z.farmid = p_farmid
        ORDER  BY e.ord;

        -- Stock per line (eggs), or the birds as one movement.
        IF public.fnpoultrysale_byproductrole(v_product) IS NOT NULL THEN
            PERFORM public.sppoultrybyproduct_syncforsale(p_farmid, v_id, p_userid);   -- 374: byproduct lines
        ELSIF v_isegg THEN
            PERFORM public.sppoultryeggstock_syncforsale(p_farmid, v_id, v_qty, p_userid);
        ELSIF fnpoultrysale_isbirdsale(v_product) THEN
            PERFORM sppoultrybirdstock_sync(p_farmid, 'Bird Sale', -(v_qty::numeric(14,3)), v_id, 'Bird sale', p_userid);
        END IF;
    END IF;

    UPDATE sale s SET requestkey = v_key WHERE s.saleid = v_id AND v_key IS NOT NULL;

    -- ONE cash sync, ONE business date, ONE payment for the whole sale.
    PERFORM public.sppoultrysalecash_sync(p_farmid, v_id, p_cashaccountid, v_total, v_paidrow, p_description, p_userid);
    PERFORM public.sppoultrycashtransaction_setbusinessdate(p_farmid, 'Sale', v_id, p_saledate);

    IF COALESCE(p_paid, FALSE) AND NOT v_walkin AND v_total > 0 THEN
        PERFORM public.sppoultrycustomerpayment_record(
            p_farmid => p_farmid, p_customerid => v_cust, p_amount => v_total,
            p_allocations => jsonb_build_array(jsonb_build_object('saleid', v_id, 'amount', v_total)),
            p_paymentmethod => p_paymentmethod, p_paymentdate => p_saledate, p_cashaccountid => p_cashaccountid,
            p_reference => v_group, p_note => 'Paid at point of sale', p_sourcetype => 'SaleEntry',
            p_createdby => p_userid);
    END IF;

    RETURN jsonb_build_object('saleGroupNo', v_group, 'saleId', v_id, 'saleIds', jsonb_build_array(v_id),
                              'totalAmount', v_total, 'lineCount', v_n);
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Sale reads carry the snapshot (NULLs on older lines)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrysale_lines(p_saleid integer)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $function$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'saleLineId', l.salelineid, 'lineNo', l.lineno, 'product', l.product,
               'eggProductId', l.poultryproductid, 'size', l.size, 'quantity', l.quantity,
               'unitPrice', l.unitprice, 'totalAmount', l.totalamount,
               -- 394
               'boxes', l.qtyboxes, 'crates', l.qtycrates, 'pieces', l.qtypieces,
               'eggsPerCrate', l.eggspercrate, 'cratesPerBox', l.cratesperbox,
               'pricePerBox', l.priceperbox, 'pricePerCrate', l.pricepercrate, 'pricePerPiece', l.priceperpiece,
               'calculatedAmount', l.calculatedamount, 'amountOverridden', l.amountoverridden)
             ORDER BY l.lineno), '[]'::jsonb)
    FROM   saleline l WHERE l.saleid = p_saleid;
$function$;

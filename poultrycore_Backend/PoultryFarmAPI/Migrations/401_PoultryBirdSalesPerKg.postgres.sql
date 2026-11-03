-- =============================================================================
-- 401: Broilers, phase 3 -- selling birds per kg, and the meat withdrawal warning.
--
-- 1. saleline keeps how a bird line was priced:
--      pricingbasis  'PerBird' | 'PerKg'   (NULL on every line before 401, and
--                                           on lines that are not birds)
--      liveweightkg  total live weight of the birds on the line
--      priceperkg    the price per kg, when priced per kg
--    quantity stays the BIRD COUNT -- the bird position subtracts it -- and
--    unitprice stays a per-bird price (amount / birds for a per-kg line), so
--    every existing report that multiplies quantity by unit price agrees.
--    Live weight may be recorded on a per-bird line too: phase 4 (kg sold,
--    FCR) reads it.
--
-- 2. sppoultrysale_creategroup -- LIVE body read from dev 2026-11-03 (it
--    already carries 394's egg packaging), plus the bird branch: a per-kg line
--    is checked kg x price per kg = amount unless the amount was overridden,
--    exactly as 394 checks a packaged egg line. The browser's per-bird price
--    is not trusted for a per-kg line.
--
-- 3. sppoultrysale_setliveweight -- Flock Closeout creates its sales through
--    the single-sale path (spsale_insert), whose line is a mirror of the
--    header. This records basis / kg / price per kg on that line afterwards.
--    WRITE-ONCE and MONEY-NEUTRAL: refused when the line already has a basis,
--    and refused when a per-kg amount does not equal kg x price per kg (unless
--    flagged overridden). It never changes an amount.
--
-- 4. fnpoultrysale_lines returns the three new fields.
--
-- 5. fnpoultryflock_meatwithdrawal(farm, date) -- flocks still inside a meat
--    withdrawal period on a date. Two sources, both the farm's own figures
--    (no withdrawal period is built in, as 339 promised):
--      * posted treatment campaign days: day + the campaign's meat days;
--      * medication on production records: record date + the product's meat
--        days in poultrymedicationproductsettings.
--    "Until" is inclusive, as the Treatment Campaigns page shows it ("Meat
--    until 12 Nov"): a sale dated on or before it is inside the period.
--    A WARNING only -- nothing here refuses a sale. The farm decides.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

-- 1. The columns ----------------------------------------------------------------
ALTER TABLE public.saleline ADD COLUMN IF NOT EXISTS pricingbasis text;
ALTER TABLE public.saleline ADD COLUMN IF NOT EXISTS liveweightkg numeric(12,3);
ALTER TABLE public.saleline ADD COLUMN IF NOT EXISTS priceperkg   numeric(14,4);

ALTER TABLE public.saleline DROP CONSTRAINT IF EXISTS ck_saleline_birdpricing;
ALTER TABLE public.saleline ADD CONSTRAINT ck_saleline_birdpricing CHECK (
        (pricingbasis IS NULL OR pricingbasis IN ('PerBird', 'PerKg'))
    AND (liveweightkg IS NULL OR liveweightkg > 0)
    AND (priceperkg IS NULL OR priceperkg >= 0)
    AND (pricingbasis IS DISTINCT FROM 'PerKg' OR (liveweightkg IS NOT NULL AND priceperkg IS NOT NULL)));

-- 2. Creating a sale ------------------------------------------------------------
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
    -- 401: bird lines priced per bird or per kg
    v_basis   text;
    v_birds   numeric;
    v_kg      numeric;
    v_ppk     numeric;
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
        -- 401: a bird line priced per kg of live weight, or per bird with the
        -- live weight recorded. The bird COUNT stays the quantity (it is what
        -- the flock's bird position subtracts); kg and price per kg ride along
        -- in "_kg". Per kg, the amount is kg x price per kg, checked here like
        -- the egg amount above, and the per-bird price becomes amount / birds
        -- so every reader that multiplies quantity by unit price still agrees.
        ELSIF public.fnpoultrysale_isbirdsale(btrim(COALESCE(v_e->>'product', '')))
              AND (v_e ? 'pricingBasis' OR v_e ? 'liveWeightKg') THEN
            v_basis := COALESCE(NULLIF(btrim(COALESCE(v_e->>'pricingBasis', '')), ''), 'PerBird');
            IF v_basis NOT IN ('PerBird', 'PerKg') THEN
                RAISE EXCEPTION 'Line %: price birds per bird or per kg.', v_ord;
            END IF;
            v_birds := NULLIF(v_e->>'quantity', '')::numeric;
            IF v_birds IS NULL OR v_birds <= 0 OR v_birds <> trunc(v_birds) THEN
                RAISE EXCEPTION 'Line %: enter the number of birds as a whole number.', v_ord;
            END IF;
            v_kg := round(NULLIF(v_e->>'liveWeightKg', '')::numeric, 3);
            IF v_kg IS NOT NULL AND v_kg <= 0 THEN
                RAISE EXCEPTION 'Line %: the live weight must be above 0 kg.', v_ord;
            END IF;
            IF v_kg IS NOT NULL AND v_kg / v_birds > 20 THEN
                RAISE EXCEPTION 'Line %: % kg for % birds is over 20 kg a bird. Check the weight and the number of birds.', v_ord, v_kg, v_birds;
            END IF;
            IF v_basis = 'PerKg' THEN
                IF v_kg IS NULL THEN
                    RAISE EXCEPTION 'Line %: a sale priced per kg needs the total live weight in kg.', v_ord;
                END IF;
                v_ppk := round(NULLIF(v_e->>'pricePerKg', '')::numeric, 4);
                IF v_ppk IS NULL OR v_ppk < 0 THEN
                    RAISE EXCEPTION 'Line %: enter the price per kg.', v_ord;
                END IF;
                v_calc := round(v_kg * v_ppk, 2);
                v_amt  := round(COALESCE(NULLIF(v_e->>'totalAmount', '')::numeric, v_calc), 2);
                v_ovr  := COALESCE(NULLIF(v_e->>'amountOverridden', '')::boolean, FALSE);
                IF NOT v_ovr AND abs(v_amt - v_calc) > 0.01 THEN
                    RAISE EXCEPTION 'Line %: the amount % does not match % kg at % per kg (%). Reload the page and try again.',
                        v_ord, v_amt, v_kg, v_ppk, v_calc;
                END IF;
                v_e := v_e || jsonb_build_object('unitPrice', round(v_amt / v_birds, 2), 'totalAmount', v_amt);
            ELSE
                v_ppk := NULL; v_calc := NULL; v_ovr := NULL;
            END IF;
            v_e := v_e || jsonb_build_object('_kg', jsonb_build_object(
                'basis', v_basis, 'kg', v_kg, 'pricePerKg', v_ppk,
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
        -- 401: and a bird line its pricing basis and live weight.
        IF v_lines->0 ? '_kg' THEN
            UPDATE saleline l
            SET    pricingbasis = v_lines->0->'_kg'->>'basis',
                   liveweightkg = NULLIF(v_lines->0->'_kg'->>'kg', '')::numeric,
                   priceperkg = NULLIF(v_lines->0->'_kg'->>'pricePerKg', '')::numeric,
                   calculatedamount = NULLIF(v_lines->0->'_kg'->>'calculatedAmount', '')::numeric,
                   amountoverridden = NULLIF(v_lines->0->'_kg'->>'amountOverridden', '')::boolean
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
                              priceperbox, pricepercrate, priceperpiece, calculatedamount, amountoverridden,
                              pricingbasis, liveweightkg, priceperkg)
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
               COALESCE((e.v->'_pk'->>'calculatedAmount')::numeric, NULLIF(e.v->'_kg'->>'calculatedAmount', '')::numeric),
               COALESCE((e.v->'_pk'->>'amountOverridden')::boolean, NULLIF(e.v->'_kg'->>'amountOverridden', '')::boolean),
               e.v->'_kg'->>'basis', NULLIF(e.v->'_kg'->>'kg', '')::numeric, NULLIF(e.v->'_kg'->>'pricePerKg', '')::numeric
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

-- 3. Closeout sales: record the weight on the line after it is created ----------
CREATE OR REPLACE FUNCTION public.sppoultrysale_setliveweight(
    p_farmid       text,
    p_saleid       integer,
    p_pricingbasis text,
    p_liveweightkg numeric,
    p_priceperkg   numeric DEFAULT NULL,
    p_overridden   boolean DEFAULT FALSE,
    p_by           text    DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    v_s    record;
    v_l    record;
    v_kg   numeric := round(p_liveweightkg, 3);
    v_ppk  numeric := round(p_priceperkg, 4);
    v_calc numeric(14,2);
BEGIN
    SELECT s.saleid, s.product, s.status INTO v_s
      FROM sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sale not found.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT public.fnpoultrysale_isbirdsale(v_s.product) THEN
        RAISE EXCEPTION 'Only a sale of live birds can carry a live weight.' USING ERRCODE = 'P0001';
    END IF;
    IF v_s.status IS DISTINCT FROM 'Posted' THEN
        RAISE EXCEPTION 'That sale has been reversed.' USING ERRCODE = 'P0001';
    END IF;

    SELECT l.salelineid, l.quantity, l.totalamount, l.pricingbasis INTO v_l
      FROM saleline l WHERE l.saleid = p_saleid ORDER BY l.lineno LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sale #% has no line.', p_saleid USING ERRCODE = 'P0001';
    END IF;
    IF (SELECT count(*) FROM saleline l WHERE l.saleid = p_saleid) > 1 THEN
        RAISE EXCEPTION 'Sale #% has several lines; record weights when entering it.', p_saleid USING ERRCODE = 'P0001';
    END IF;
    IF v_l.pricingbasis IS NOT NULL THEN
        RAISE EXCEPTION 'Sale #% already records how it was priced. Use Correct Sale to change it.', p_saleid
            USING ERRCODE = 'P0001';
    END IF;

    IF p_pricingbasis NOT IN ('PerBird', 'PerKg') THEN
        RAISE EXCEPTION 'Price birds per bird or per kg.' USING ERRCODE = 'P0001';
    END IF;
    IF v_kg IS NOT NULL AND v_kg <= 0 THEN
        RAISE EXCEPTION 'The live weight must be above 0 kg.' USING ERRCODE = 'P0001';
    END IF;
    IF v_kg IS NOT NULL AND v_kg / NULLIF(v_l.quantity, 0) > 20 THEN
        RAISE EXCEPTION '% kg for % birds is over 20 kg a bird.', v_kg, v_l.quantity USING ERRCODE = 'P0001';
    END IF;
    IF p_pricingbasis = 'PerKg' THEN
        IF v_kg IS NULL OR v_ppk IS NULL OR v_ppk < 0 THEN
            RAISE EXCEPTION 'A sale priced per kg needs the live weight and the price per kg.' USING ERRCODE = 'P0001';
        END IF;
        v_calc := round(v_kg * v_ppk, 2);
        IF NOT COALESCE(p_overridden, FALSE) AND abs(v_l.totalamount - v_calc) > 0.01 THEN
            RAISE EXCEPTION 'The sale is for % but % kg at % per kg is %.', v_l.totalamount, v_kg, v_ppk, v_calc
                USING ERRCODE = 'P0001';
        END IF;
    ELSE
        v_ppk := NULL;
    END IF;

    -- The line guard admits only the sale system; this is money-neutral and
    -- write-once (checked above), so it may speak as the system for one row.
    PERFORM set_config('poultry.sale_system', 'on', true);
    UPDATE saleline SET
        pricingbasis = p_pricingbasis,
        liveweightkg = v_kg,
        priceperkg = v_ppk,
        calculatedamount = CASE WHEN p_pricingbasis = 'PerKg' THEN v_calc ELSE calculatedamount END,
        amountoverridden = CASE WHEN p_pricingbasis = 'PerKg' THEN COALESCE(p_overridden, FALSE) ELSE amountoverridden END
    WHERE salelineid = v_l.salelineid;
    PERFORM set_config('poultry.sale_system', 'off', true);
END
$function$;

-- 4. Reading the lines ------------------------------------------------------------
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
               'calculatedAmount', l.calculatedamount, 'amountOverridden', l.amountoverridden,
               -- 401
               'pricingBasis', l.pricingbasis, 'liveWeightKg', l.liveweightkg, 'pricePerKg', l.priceperkg)
             ORDER BY l.lineno), '[]'::jsonb)
    FROM   saleline l WHERE l.saleid = p_saleid;
$function$;

-- 5. Meat withdrawal --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryflock_meatwithdrawal(p_farmid text, p_date date)
RETURNS TABLE(flockid integer, flockname text, itemname text, lastdosedate date,
              withdrawaldays integer, withdrawaluntil date, source text)
LANGUAGE sql STABLE AS $function$
    WITH doses AS (
        -- Treatment campaign days actually posted.
        SELECT l.flockid, c.itemname::text AS itemname, p.businessdate AS dosedate,
               c.meatwithdrawaldays AS days, 'Treatment campaign'::text AS source
        FROM   poultrytreatmentcampaignpostlines l
        JOIN   poultrytreatmentcampaignposts p ON p.poultrytreatmentcampaignpostid = l.poultrytreatmentcampaignpostid
        JOIN   poultrytreatmentcampaigns c ON c.poultrytreatmentcampaignid = l.poultrytreatmentcampaignid
        WHERE  l.farmid = p_farmid AND p.status = 'Posted' AND c.meatwithdrawaldays IS NOT NULL
        UNION ALL
        -- Medication recorded on a production record, at the product's own figure.
        SELECT r.flockid, m.itemname::text, r.date::date, s.meatwithdrawaldays, 'Production record'::text
        FROM   productionrecordmedications m
        JOIN   productionrecords r ON r.id = m.productionrecordid AND r.farmid = m.farmid
        JOIN   poultrymedicationproductsettings s
               ON s.farmid = m.farmid AND s.poultryrawmaterialitemid = m.poultryrawmaterialitemid
        WHERE  m.farmid = p_farmid AND s.meatwithdrawaldays IS NOT NULL
          AND  COALESCE(m.quantityconsumed, 0) > 0 AND r.flockid IS NOT NULL
    ),
    live AS (
        SELECT d.*, d.dosedate + d.days AS until
        FROM   doses d
        WHERE  d.dosedate <= p_date AND d.dosedate + d.days >= p_date
    )
    -- One row per flock and product: the dose that ends the latest.
    SELECT DISTINCT ON (l.flockid, l.itemname)
           l.flockid, f.name::text, l.itemname, l.dosedate, l.days, l.until, l.source
    FROM   live l
    JOIN   flock f ON f.farmid = p_farmid AND f.flockid = l.flockid
    ORDER  BY l.flockid, l.itemname, l.until DESC, l.dosedate DESC;
$function$;

COMMIT;

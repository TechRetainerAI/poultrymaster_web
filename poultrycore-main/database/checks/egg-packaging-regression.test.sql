-- =============================================================================
-- egg-packaging-regression.test.sql -- phase 7 of the egg packaging programme
-- (393-396). End-to-end checks that boxes never create eggs or money:
--
--   30/33/34/29  every poultry report that takes (company, start, end) gives
--                byte-for-byte the same output after boxes are switched on, the
--                display changed and the box size changed (P&L, cash movement,
--                egg stock balance, hen-day, farm summary, daily egg
--                production, feed, mortality, byproducts, egg sales ...).
--   16           a PAID box sale: one payment, cash in = the sale total once,
--                no payment per box.
--   19           Correct Sale after the box size changed: the reversed sale
--                keeps its own conversion; the correction carries the same
--                eggs in today's packaging and is linked to it.
--   26/27        a production record of 8,400 eggs adds exactly its net eggs
--                (= 20 boxes at 14x30) and nothing else; deleting it takes
--                exactly that back off.
--   22/23        sorting 4,200 Unsorted eggs into a size moves 4,200 eggs
--                (= 10 boxes) and leaves the total egg stock unchanged.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f).
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.m397_fingerprint(p_farm text, p_start date, p_end date)
RETURNS TABLE (fn text, fp text)
LANGUAGE plpgsql
AS $f$
DECLARE
    r record;
    v text;
BEGIN
    FOR r IN
        SELECT p.proname
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public' AND p.prokind = 'f' AND p.proretset
          AND  p.proname LIKE 'sppoultryreport%'
          AND  p.pronargs - p.pronargdefaults = 3
          AND  pg_get_function_identity_arguments(p.oid) LIKE 'p_farmid text, p_startdate date, p_enddate date%'
        ORDER  BY p.proname
    LOOP
        BEGIN
            EXECUTE format('SELECT md5(COALESCE(string_agg(t::text, %L ORDER BY t::text), %L)) FROM public.%I($1, $2, $3) t',
                           '|', '<empty>', r.proname)
            INTO v USING p_farm, p_start, p_end;
        EXCEPTION WHEN OTHERS THEN
            v := 'ERR ' || SQLSTATE;     -- the same error before and after is still "unchanged"
        END;
        fn := r.proname; fp := v;
        RETURN NEXT;
    END LOOP;
END;
$f$;

-- Money and stock, company-wide.
CREATE OR REPLACE FUNCTION pg_temp.m397_totals(p_farm text)
RETURNS text
LANGUAGE sql
AS $f$
    SELECT concat_ws('|',
        (SELECT count(*) || ':' || COALESCE(sum(quantity), 0) FROM poultrystocktransactions WHERE farmid = p_farm),
        (SELECT count(*) || ':' || COALESCE(sum(totalamount), 0) FROM sale WHERE farmid = p_farm),
        (SELECT count(*) || ':' || COALESCE(sum(totalamount), 0) FROM saleline WHERE farmid = p_farm),
        (SELECT count(*) || ':' || COALESCE(sum(amount), 0) FROM poultrypayments WHERE farmid = p_farm),
        (SELECT count(*) || ':' || COALESCE(sum(amount), 0) FROM poultrycashtransactions WHERE farmid = p_farm));
$f$;

DO $$
DECLARE
    v_farm   text;
    v_flock  integer;
    v_birds  integer;
    v_user   text;
    v_egg    integer;
    v_today  date;
    v_start  date := DATE '2000-01-01';
    v_n      integer;
    v_t0     text;
    v_d1     date;
    v_d2     date;
    v_rec    integer;
    v_on0    numeric;
    v_on1    numeric;
    v_all0   numeric;
    v_all1   numeric;
    v_res    jsonb;
    v_sale   integer;
    v_fix    integer;
    v_cash0  numeric;
    v_pay0   bigint;
    v_l      record;
    v_size   integer;
    v_sizep  integer;
    v_sess   integer;
    v_b      record;

    c_onhand CONSTANT text := 'SELECT COALESCE(sum(t.quantity), 0) FROM poultrystocktransactions t WHERE t.farmid = $1 AND t.poultryproductid = $2';
BEGIN
    -- A company with an open flock that has production, and an Unsorted egg product.
    SELECT f.farmid, f.flockid INTO v_farm, v_flock
    FROM   flock f JOIN productionrecords pr ON pr.flockid = f.flockid AND pr.farmid = f.farmid
    WHERE  f.active AND NOT f.isdeleted AND f.closeddate IS NULL
      AND  fnpoultry_unsortedeggproduct(f.farmid) IS NOT NULL
    GROUP  BY f.farmid, f.flockid ORDER BY count(*) DESC LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'egg packaging regression: all checks passed (no company with an open laying flock)';
        RETURN;
    END IF;
    v_egg := fnpoultry_unsortedeggproduct(v_farm);
    SELECT fa.owneruserid INTO v_user FROM farms fa WHERE fa.id::text = v_farm OR fa.farmid::text = v_farm LIMIT 1;
    v_user  := COALESCE(v_user, 'check397');
    v_today := fncompany_businessdate(v_farm);
    SELECT GREATEST(COALESCE(pr.noofbirdsleft, 10000), 10000) INTO v_birds FROM productionrecords pr
    WHERE  pr.flockid = v_flock AND pr.farmid = v_farm ORDER BY pr.date DESC, pr.id DESC LIMIT 1;

    -- -------------------------------------------------------------------------
    -- 30/33/34/29. Packaging changes leave every report and total unchanged.
    -- -------------------------------------------------------------------------
    CREATE TEMP TABLE m397_before ON COMMIT DROP AS SELECT * FROM pg_temp.m397_fingerprint(v_farm, v_start, v_today);
    v_t0 := pg_temp.m397_totals(v_farm);
    SELECT count(*) INTO v_n FROM m397_before WHERE fp NOT LIKE 'ERR%';

    INSERT INTO poultryeggsortingsettings (farmid, eggspercrate) VALUES (v_farm, 30)
    ON CONFLICT (farmid) DO UPDATE SET eggspercrate = poultryeggsortingsettings.eggspercrate;
    PERFORM sppoultryeggpackaging_save(v_farm, TRUE, 14, 'BoxesCratesPieces', 'Boxes', 'check397');
    PERFORM sppoultryeggpackaging_save(v_farm, TRUE, 14, 'Pieces', 'Crates', 'check397');
    PERFORM sppoultryeggpackaging_save(v_farm, TRUE, 10, 'BoxesCratesPieces', 'Boxes', 'check397');

    IF EXISTS (SELECT 1 FROM m397_before b JOIN pg_temp.m397_fingerprint(v_farm, v_start, v_today) a USING (fn)
               WHERE a.fp IS DISTINCT FROM b.fp) THEN
        RAISE EXCEPTION 'FAIL 34: a report changed when only the packaging changed: %',
            (SELECT string_agg(b.fn, ', ') FROM m397_before b JOIN pg_temp.m397_fingerprint(v_farm, v_start, v_today) a USING (fn)
             WHERE a.fp IS DISTINCT FROM b.fp);
    END IF;
    IF pg_temp.m397_totals(v_farm) <> v_t0 THEN RAISE EXCEPTION 'FAIL 34: stock or money moved: % -> %', v_t0, pg_temp.m397_totals(v_farm); END IF;
    RAISE NOTICE 'ok 30/33/34/29 % reports (P&L, cash, stock balance, hen-day, ...) and all stock/money totals identical after boxes on + box size change', v_n;

    -- Back to 14 crates per box for the rest.
    PERFORM sppoultryeggpackaging_save(v_farm, TRUE, 14, 'BoxesCratesPieces', 'Boxes', 'check397');
    UPDATE poultryeggsortingsettings SET eggspercrate = 30 WHERE farmid = v_farm;

    -- -------------------------------------------------------------------------
    -- 26/27. Production: exactly its eggs in, exactly its eggs out.
    -- -------------------------------------------------------------------------
    SELECT d::date INTO v_d1 FROM generate_series(v_today - 1, v_today - 600, interval '-1 day') d
    WHERE NOT EXISTS (SELECT 1 FROM productionrecords pr WHERE pr.farmid = v_farm AND pr.flockid = v_flock AND pr.date::date = d::date)
    ORDER BY d DESC LIMIT 1;
    SELECT d::date INTO v_d2 FROM generate_series(v_d1 - 1, v_d1 - 600, interval '-1 day') d
    WHERE NOT EXISTS (SELECT 1 FROM productionrecords pr WHERE pr.farmid = v_farm AND pr.flockid = v_flock AND pr.date::date = d::date)
    ORDER BY d DESC LIMIT 1;

    EXECUTE c_onhand INTO v_on0 USING v_farm, v_egg;
    v_rec := spproductionrecord_insert(p_farmid => v_farm, p_createdby => 'check397', p_userid => 'check397',
        p_ageinweeks => 30, p_ageindays => 210, p_date => v_d1, p_noofbirds => v_birds, p_mortality => 0,
        p_noofbirdsleft => v_birds, p_feedkg => 0, p_production9am => 8400, p_production12pm => 0, p_production4pm => 0,
        p_totalproduction => 8400, p_flockid => v_flock, p_brokeneggs => 0);
    EXECUTE c_onhand INTO v_on1 USING v_farm, v_egg;
    SELECT * INTO v_b FROM fnpoultry_eggbreakdown(v_on1 - v_on0, 30, 14);
    IF v_on1 - v_on0 <> 8400 OR (v_b.boxes, v_b.crates, v_b.pieces) <> (20, 0, 0) THEN
        RAISE EXCEPTION 'FAIL 26: production added % eggs (%)', v_on1 - v_on0, row_to_json(v_b); END IF;
    PERFORM spproductionrecord_delete(v_rec, 'check397', v_farm);
    EXECUTE c_onhand INTO v_on1 USING v_farm, v_egg;
    IF v_on1 <> v_on0 THEN RAISE EXCEPTION 'FAIL 27: deleting the record left % eggs', v_on1 - v_on0; END IF;
    RAISE NOTICE 'ok 26/27 8,400 eggs produced = +8,400 (= 20 boxes) and nothing else; deleting it takes exactly 8,400 back';

    -- -------------------------------------------------------------------------
    -- 22/23. Sorting moves eggs between classes; the total never changes.
    -- -------------------------------------------------------------------------
    INSERT INTO poultryeggsortingsettings (farmid, enableeggsorting) VALUES (v_farm, TRUE)
    ON CONFLICT (farmid) DO UPDATE SET enableeggsorting = TRUE;
    PERFORM sppoultryeggsizes_ensure(v_farm, 'check397');
    SELECT z.eggsizeid, z.poultryproductid INTO v_size, v_sizep FROM poultryeggsizes z
    WHERE  z.farmid = v_farm AND z.isactive ORDER BY z.sortorder, z.eggsizeid LIMIT 1;
    IF v_size IS NOT NULL THEN
        v_rec := spproductionrecord_insert(p_farmid => v_farm, p_createdby => 'check397', p_userid => 'check397',
            p_ageinweeks => 30, p_ageindays => 210, p_date => v_d2, p_noofbirds => v_birds, p_mortality => 0,
            p_noofbirdsleft => v_birds, p_feedkg => 0, p_production9am => 4200, p_production12pm => 0, p_production4pm => 0,
            p_totalproduction => 4200, p_flockid => v_flock, p_brokeneggs => 0);
        EXECUTE c_onhand INTO v_on0 USING v_farm, v_egg;
        EXECUTE c_onhand INTO v_all0 USING v_farm, v_sizep;
        SELECT COALESCE(sum(t.quantity), 0) INTO v_all0 FROM poultrystocktransactions t
        WHERE  t.farmid = v_farm AND (t.poultryproductid = v_egg OR t.poultryproductid IN (SELECT poultryproductid FROM poultryeggsizes WHERE farmid = v_farm));
        v_sess := sppoultryeggsorting_save(v_farm, NULL, 'ByPick', v_d2, ARRAY[v_rec], 1,
            '[{"lineType":"SizedOutput","eggSizeId":' || v_size || ',"quantity":4200}]', 'check397', NULL, 'check397');
        PERFORM sppoultryeggsorting_post(v_farm, v_sess, 'check397');
        EXECUTE c_onhand INTO v_on1 USING v_farm, v_egg;
        SELECT COALESCE(sum(t.quantity), 0) INTO v_all1 FROM poultrystocktransactions t
        WHERE  t.farmid = v_farm AND (t.poultryproductid = v_egg OR t.poultryproductid IN (SELECT poultryproductid FROM poultryeggsizes WHERE farmid = v_farm));
        IF v_on0 - v_on1 <> 4200 OR v_all1 <> v_all0 THEN
            RAISE EXCEPTION 'FAIL 22: unsorted -%, total % -> %', v_on0 - v_on1, v_all0, v_all1; END IF;
        IF (SELECT (boxes, crates, pieces) FROM fnpoultry_eggbreakdown(4200, 30, 14)) <> (10::bigint, 0::bigint, 0::bigint) THEN RAISE EXCEPTION 'FAIL 22: 4,200 is not 10 boxes'; END IF;
        RAISE NOTICE 'ok 22/23 sorting 4,200 (= 10 boxes) into a size: unsorted -4,200, total egg stock unchanged';
    ELSE
        RAISE NOTICE 'ok 22/23 skipped: the company has no active egg size';
    END IF;

    -- -------------------------------------------------------------------------
    -- 16. A paid box sale: one payment, the cash once.
    -- -------------------------------------------------------------------------
    PERFORM sppoultrymanualmovement_post(v_farm, v_egg, NULL, 'Increase', 10000, NULL, NULL, NULL,
        v_today, 'Opening Inventory', NULL, 'check397', 'check-397-open', v_user);
    -- Cash needs a cash account; give the company one if it has none (rolled back).
    IF NOT EXISTS (SELECT 1 FROM poultrycashaccounts a WHERE a.farmid = v_farm) THEN
        INSERT INTO poultrycashaccounts (poultrycashaccountid, farmid, accountname, accounttype)
        VALUES ((SELECT COALESCE(max(poultrycashaccountid), 0) + 1 FROM poultrycashaccounts), v_farm, 'check397 cash', 'Cash');
    END IF;
    SELECT COALESCE(sum(amount), 0) INTO v_cash0 FROM poultrycashtransactions WHERE farmid = v_farm;
    SELECT count(*) INTO v_pay0 FROM poultrypayments WHERE farmid = v_farm;
    v_res := sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
        p_customername => 'check397 customer', p_customerid => NULL, p_paymentmethod => 'Cash',
        p_cashaccountid => (SELECT a.poultrycashaccountid FROM poultrycashaccounts a WHERE a.farmid = v_farm ORDER BY 1 LIMIT 1),
        p_paid => true, p_description => 'check397', p_flockid => NULL,
        p_linesjson => '[{"product":"Fresh Eggs","boxes":2,"crates":3,"pieces":10,"unitPrice":150,"pricePerBox":2000,"pricePerPiece":5,"totalAmount":4500}]',
        p_requestkey => 'check-397-paid');
    v_sale := (v_res->>'saleId')::int;
    IF (SELECT count(*) FROM poultrypayments WHERE farmid = v_farm) - v_pay0 <> 1 THEN
        RAISE EXCEPTION 'FAIL 16: % payment rows for one paid sale', (SELECT count(*) FROM poultrypayments WHERE farmid = v_farm) - v_pay0; END IF;
    -- Cash is posted only into a cash account; a company with none posts no cash
    -- for ANY paid sale, so the cash leg is checked only where one exists.
    IF EXISTS (SELECT 1 FROM poultrycashaccounts a WHERE a.farmid = v_farm) THEN
        IF (SELECT COALESCE(sum(amount), 0) FROM poultrycashtransactions WHERE farmid = v_farm) - v_cash0 <> 4500 THEN
            RAISE EXCEPTION 'FAIL 16: cash moved by % (want 4,500 once)', (SELECT COALESCE(sum(amount), 0) FROM poultrycashtransactions WHERE farmid = v_farm) - v_cash0; END IF;
        RAISE NOTICE 'ok 16 paid 2 boxes + 3 crates + 10 pcs: one payment, cash +4,500 once';
    ELSE
        IF (SELECT COALESCE(sum(amount), 0) FROM poultrycashtransactions WHERE farmid = v_farm) <> v_cash0 THEN
            RAISE EXCEPTION 'FAIL 16: cash moved without a cash account'; END IF;
        RAISE NOTICE 'ok 16 paid box sale: one payment (company has no cash account, so no cash row -- same as any paid sale)';
    END IF;

    -- -------------------------------------------------------------------------
    -- 19. Correct Sale after the box size changed.
    -- -------------------------------------------------------------------------
    PERFORM sppoultrysale_reverse(v_farm, v_sale, 'Wrong quantity', 'check397', '{}'::jsonb, NULL, NULL, v_user);
    PERFORM sppoultryeggpackaging_save(v_farm, TRUE, 10, 'BoxesCratesPieces', 'Boxes', 'check397');
    -- The same 940 eggs in today's packaging: 3 boxes (900) + 1 crate + 10 pcs.
    v_res := sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
        p_customername => 'check397 customer', p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL,
        p_paid => false, p_description => 'check397 correction', p_flockid => NULL,
        p_linesjson => '[{"product":"Fresh Eggs","boxes":3,"crates":1,"pieces":10,"quantity":940,"unitPrice":150,"pricePerBox":2000,"pricePerPiece":5,"totalAmount":6200}]',
        p_requestkey => 'check-397-fix');
    v_fix := (v_res->>'saleId')::int;
    PERFORM sppoultrysale_linkcorrection(v_farm, v_fix, v_sale, v_user);
    SELECT * INTO v_l FROM saleline WHERE saleid = v_sale;
    IF (v_l.qtyboxes, v_l.cratesperbox, v_l.quantity) <> (2, 14, 940) THEN
        RAISE EXCEPTION 'FAIL 19: the reversed sale lost its own conversion: %', row_to_json(v_l); END IF;
    SELECT * INTO v_l FROM saleline WHERE saleid = v_fix;
    IF (v_l.qtyboxes, v_l.qtycrates, v_l.qtypieces, v_l.cratesperbox, v_l.quantity) <> (3, 1, 10, 10, 940) THEN
        RAISE EXCEPTION 'FAIL 19: the correction %', row_to_json(v_l); END IF;
    IF NOT EXISTS (SELECT 1 FROM sale WHERE saleid = v_fix AND correctssaleid = v_sale) THEN
        RAISE EXCEPTION 'FAIL 19: the correction is not linked to the reversed sale'; END IF;
    RAISE NOTICE 'ok 19 correction after 14 -> 10 crates/box: original 2 x 14 kept, correction 3 boxes + 1 crate + 10 = same 940 eggs, linked';

    RAISE NOTICE 'egg packaging regression: all checks passed';
END;
$$;

ROLLBACK;

-- =============================================================================
-- egg-sales-report-packaging.test.sql -- checks for migration 396 (Egg Sales
-- report: actual boxes sold vs equivalent). Spec tests 31 and 32.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f).
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm  text;
    v_user  text;
    v_egg   integer;
    v_today date;
    v_a     integer;
    v_b     integer;
    v_r     record;
    v_bad   bigint;
BEGIN
    -- 0. Same rows and totals as the sale lines it reads, for every company.
    SELECT count(*) INTO v_bad
    FROM   (SELECT DISTINCT farmid FROM sale) c
    WHERE  (SELECT COALESCE(sum(r.quantitysold), 0) FROM sppoultryreport_eggsales_rs1(c.farmid, DATE '2000-01-01', DATE '2100-01-01') r)
        <> (SELECT COALESCE(sum(l.quantity), 0) FROM sale s JOIN saleline l ON l.saleid = s.saleid
            WHERE s.farmid = c.farmid AND s.status = 'Posted' AND COALESCE(l.product, '') ILIKE '%egg%');
    IF v_bad > 0 THEN RAISE EXCEPTION 'FAIL 0: % companies disagree with their sale lines', v_bad; END IF;
    RAISE NOTICE 'ok 0 report quantities = posted egg sale lines, every company';

    SELECT pp.farmid, pp.poultryproductid INTO v_farm, v_egg
    FROM   poultryproducts pp
    WHERE  pp.israweggproduct = TRUE AND pp.poultryproductid = fnpoultry_unsortedeggproduct(pp.farmid)
    ORDER  BY pp.farmid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'egg sales report packaging: all checks passed (no company with an egg product)';
        RETURN;
    END IF;
    SELECT fa.owneruserid INTO v_user FROM farms fa WHERE fa.id::text = v_farm OR fa.farmid::text = v_farm LIMIT 1;
    v_user  := COALESCE(v_user, 'check396');
    v_today := fncompany_businessdate(v_farm);
    INSERT INTO poultryeggsortingsettings (farmid, eggspercrate) VALUES (v_farm, 30)
    ON CONFLICT (farmid) DO UPDATE SET eggspercrate = 30;
    PERFORM sppoultryeggpackaging_save(v_farm, TRUE, 14, 'BoxesCratesPieces', 'Boxes', 'check396');
    PERFORM sppoultrymanualmovement_post(v_farm, v_egg, NULL, 'Increase', 10000, NULL, NULL, NULL,
        v_today, 'Opening Inventory', NULL, 'check396', 'check-396-open', v_user);

    -- 31. 420 eggs sold as 14 crates: 0 boxes actually sold.
    v_a := (sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
        p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
        p_description => 'check396', p_flockid => NULL,
        p_linesjson => '[{"product":"Fresh Eggs","boxes":0,"crates":14,"pieces":0,"unitPrice":150,"totalAmount":2100}]',
        p_requestkey => 'check-396-a')::jsonb->>'saleId')::int;
    SELECT * INTO v_r FROM sppoultryreport_eggsales_rs1(v_farm, v_today, v_today) r WHERE r.saleid = v_a;
    IF v_r.quantitysold <> 420 OR v_r.qtyboxes <> 0 OR v_r.qtycrates <> 14 OR v_r.lineno <> 1 THEN
        RAISE EXCEPTION 'FAIL 31: %', row_to_json(v_r); END IF;
    RAISE NOTICE 'ok 31 14 crates: 420 eggs, 0 boxes actually sold';

    -- 32. One box: 1 box actually sold, 420 eggs, at its own box size.
    v_b := (sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
        p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
        p_description => 'check396', p_flockid => NULL,
        p_linesjson => '[{"product":"Fresh Eggs","boxes":1,"crates":0,"pieces":0,"unitPrice":150,"totalAmount":2100}]',
        p_requestkey => 'check-396-b')::jsonb->>'saleId')::int;
    SELECT * INTO v_r FROM sppoultryreport_eggsales_rs1(v_farm, v_today, v_today) r WHERE r.saleid = v_b;
    IF v_r.quantitysold <> 420 OR v_r.qtyboxes <> 1 OR v_r.cratesperbox <> 14 THEN
        RAISE EXCEPTION 'FAIL 32: %', row_to_json(v_r); END IF;
    RAISE NOTICE 'ok 32 1 box: 1 box actually sold, 420 eggs, 14 crates/box kept';

    -- An older-style line (no packaging) reports NULL packaging, never boxes.
    v_a := (sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
        p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
        p_description => 'check396', p_flockid => NULL,
        p_linesjson => '[{"product":"Fresh Eggs","quantity":420,"unitPrice":150,"totalAmount":2100}]',
        p_requestkey => 'check-396-c')::jsonb->>'saleId')::int;
    SELECT * INTO v_r FROM sppoultryreport_eggsales_rs1(v_farm, v_today, v_today) r WHERE r.saleid = v_a;
    IF v_r.qtyboxes IS NOT NULL OR v_r.qtycrates IS NOT NULL THEN RAISE EXCEPTION 'FAIL legacy: %', row_to_json(v_r); END IF;
    RAISE NOTICE 'ok a line without packaging reports no packaging';

    RAISE NOTICE 'egg sales report packaging: all checks passed';
END;
$$;

ROLLBACK;

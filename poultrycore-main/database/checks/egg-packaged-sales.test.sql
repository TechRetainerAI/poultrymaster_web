-- =============================================================================
-- egg-packaged-sales.test.sql -- checks for migration 394 (selling in Boxes,
-- Crates and Pieces). Spec tests 9-14, 17, 18 plus the refusals.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f).
-- Uses the first company that has an Unsorted egg product; gives it 10,000
-- eggs of opening stock and 14 crates per box inside the transaction.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm    text;
    v_user    text;
    v_egg     integer;
    v_today   date;
    v_epc     integer;
    v_res     jsonb;
    v_sale    integer;
    v_sale2   integer;
    v_l       record;
    v_on0     numeric;
    v_on1     numeric;
    v_failed  boolean;
    v_msg     text;
    v_cash0   numeric;
    v_pay0    bigint;
    v_lines   text;

    -- eggs on hand in one class
    c_onhand CONSTANT text := 'SELECT COALESCE(sum(t.quantity), 0) FROM poultrystocktransactions t WHERE t.farmid = $1 AND t.poultryproductid = $2';
BEGIN
    -- 0. A packaging snapshot is only ever a whole one, and only on a line
    --    whose eggs match it (nothing invented for older lines).
    IF EXISTS (SELECT 1 FROM saleline
               WHERE (qtycrates IS NULL) <> (eggspercrate IS NULL)
                  OR (qtycrates IS NOT NULL AND quantity <> fnpoultry_eggpieces(qtyboxes, qtycrates, qtypieces, eggspercrate, cratesperbox))) THEN
        RAISE EXCEPTION 'FAIL 0: a sale line has a partial or wrong packaging snapshot';
    END IF;
    RAISE NOTICE 'ok 0 every packaging snapshot is whole and matches its eggs';

    -- The pricing rule (13 and the fallbacks).
    IF fnpoultry_eggpackagedamount(2, 3, 10, 30, 14, 2000, 150, 5) <> 4500 THEN RAISE EXCEPTION 'FAIL 13: mixed pricing'; END IF;
    IF fnpoultry_eggpackagedamount(2, 0, 0, 30, 14, 2000, 150, NULL) <> 4000 THEN RAISE EXCEPTION 'FAIL 12: box pricing'; END IF;
    -- No box / piece price: a box is 14 crates, a piece is 1/30 of a crate -- the old rule.
    IF fnpoultry_eggpackagedamount(1, 2, 15, 30, 14, NULL, 150, NULL) <> 2475 THEN RAISE EXCEPTION 'FAIL fallback: %', fnpoultry_eggpackagedamount(1, 2, 15, 30, 14, NULL, 150, NULL); END IF;
    IF fnpoultry_eggpackagedamount(0, 7, 13, 30, NULL, NULL, 137.50, NULL) <> round((7 * 30 + 13) / 30.0 * 137.50, 2) THEN
        RAISE EXCEPTION 'FAIL crate-only farm: packaged amount differs from the pre-394 pro-rata rule'; END IF;
    RAISE NOTICE 'ok 12-13 pricing rule (box, mixed, fallbacks = old pro-rata)';

    SELECT pp.farmid, pp.poultryproductid INTO v_farm, v_egg
    FROM   poultryproducts pp
    WHERE  pp.israweggproduct = TRUE AND pp.poultryproductid = fnpoultry_unsortedeggproduct(pp.farmid)
    ORDER  BY pp.farmid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'egg packaged sales: all checks passed (no company with an egg product)';
        RETURN;
    END IF;
    SELECT fa.owneruserid INTO v_user FROM farms fa WHERE fa.id::text = v_farm OR fa.farmid::text = v_farm LIMIT 1;
    v_user  := COALESCE(v_user, 'check394');
    v_today := fncompany_businessdate(v_farm);

    -- A known starting point: 30 eggs per crate, 14 crates per box, 10,000 more eggs.
    INSERT INTO poultryeggsortingsettings (farmid, eggspercrate) VALUES (v_farm, 30)
    ON CONFLICT (farmid) DO UPDATE SET eggspercrate = 30;
    PERFORM sppoultryeggpackaging_save(v_farm, TRUE, 14, 'BoxesCratesPieces', 'Boxes', 'check394');
    PERFORM sppoultrymanualmovement_post(v_farm, v_egg, NULL, 'Increase', 10000, NULL, NULL, NULL,
        v_today, 'Opening Inventory', NULL, NULL, NULL, 'check394');
    EXECUTE c_onhand INTO v_on0 USING v_farm, v_egg;
    SELECT COALESCE(sum(amount), 0) INTO v_cash0 FROM poultrycashtransactions WHERE farmid = v_farm;
    SELECT count(*) INTO v_pay0 FROM poultrypayments WHERE farmid = v_farm;

    -- 9. Box-only sale: 2 boxes = 840 eggs, one sale, one line.
    v_res := sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
        p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
        p_description => 'check394', p_flockid => NULL,
        p_linesjson => '[{"product":"Fresh Eggs","eggProductId":null,"boxes":2,"crates":0,"pieces":0,"quantity":840,"unitPrice":150,"pricePerBox":2000,"totalAmount":4000}]',
        p_requestkey => 'check-394-a')::jsonb;
    v_sale := (v_res->>'saleId')::int;
    EXECUTE c_onhand INTO v_on1 USING v_farm, v_egg;
    IF v_on0 - v_on1 <> 840 THEN RAISE EXCEPTION 'FAIL 9: % eggs taken (want 840)', v_on0 - v_on1; END IF;
    IF (SELECT count(*) FROM saleline WHERE saleid = v_sale) <> 1 THEN RAISE EXCEPTION 'FAIL 9: line count'; END IF;
    SELECT * INTO v_l FROM saleline WHERE saleid = v_sale;
    IF (v_l.qtyboxes, v_l.qtycrates, v_l.qtypieces, v_l.eggspercrate, v_l.cratesperbox) <> (2, 0, 0, 30, 14)
       OR v_l.quantity <> 840 OR v_l.totalamount <> 4000 OR v_l.priceperbox <> 2000 OR v_l.calculatedamount <> 4000 THEN
        RAISE EXCEPTION 'FAIL 9: snapshot %', row_to_json(v_l); END IF;
    IF (SELECT totalamount FROM sale WHERE saleid = v_sale) <> 4000 THEN RAISE EXCEPTION 'FAIL 12: header total'; END IF;
    RAISE NOTICE 'ok 9/12 2 boxes = 840 eggs taken, 4,000 at the box price, snapshot kept';

    -- 15. Pay later: no new payment, no cash.
    IF (SELECT count(*) FROM poultrypayments WHERE farmid = v_farm) <> v_pay0
       OR (SELECT COALESCE(sum(amount), 0) FROM poultrycashtransactions WHERE farmid = v_farm) <> v_cash0 THEN
        RAISE EXCEPTION 'FAIL 15: a pay-later sale moved cash or created a payment'; END IF;
    RAISE NOTICE 'ok 15 pay later: no payment, no cash';

    -- 10/13. Mixed: 2 boxes + 3 crates + 10 pcs = 940 eggs, priced 4,500.
    EXECUTE c_onhand INTO v_on0 USING v_farm, v_egg;
    v_sale2 := (sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
        p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
        p_description => 'check394', p_flockid => NULL,
        p_linesjson => '[{"product":"Fresh Eggs","eggProductId":null,"boxes":2,"crates":3,"pieces":10,"unitPrice":150,"pricePerBox":2000,"pricePerPiece":5,"totalAmount":4500}]',
        p_requestkey => 'check-394-b')::jsonb->>'saleId')::int;
    EXECUTE c_onhand INTO v_on1 USING v_farm, v_egg;
    IF v_on0 - v_on1 <> 940 THEN RAISE EXCEPTION 'FAIL 10: % eggs taken (want 940)', v_on0 - v_on1; END IF;
    IF (SELECT totalamount FROM sale WHERE saleid = v_sale2) <> 4500 THEN RAISE EXCEPTION 'FAIL 13: total'; END IF;
    RAISE NOTICE 'ok 10/13 2 boxes + 3 crates + 10 pcs = 940 eggs, 4,500';

    -- 11. Two lines, one sale: both lines keep their own packaging.
    v_res := sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
        p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
        p_description => 'check394', p_flockid => NULL,
        p_linesjson => '[{"product":"Fresh Eggs","eggProductId":null,"boxes":1,"crates":0,"pieces":0,"unitPrice":150,"totalAmount":2100},'
                    || '{"product":"Fresh Eggs","eggProductId":null,"boxes":0,"crates":4,"pieces":0,"unitPrice":150,"totalAmount":600}]',
        p_requestkey => 'check-394-c')::jsonb;
    IF (SELECT count(*) FROM sale WHERE saleid = (v_res->>'saleId')::int) <> 1
       OR (SELECT count(*) FROM saleline WHERE saleid = (v_res->>'saleId')::int) <> 2
       OR (SELECT sum(quantity) FROM saleline WHERE saleid = (v_res->>'saleId')::int) <> 540
       OR (SELECT qtyboxes FROM saleline WHERE saleid = (v_res->>'saleId')::int AND lineno = 1) <> 1
       OR (SELECT qtycrates FROM saleline WHERE saleid = (v_res->>'saleId')::int AND lineno = 2) <> 4 THEN
        RAISE EXCEPTION 'FAIL 11: one header, two lines, 540 eggs'; END IF;
    -- The header's price per crate follows the farm's crate size: 2,700 / (540 / 30) = 150.
    IF (SELECT unitprice FROM sale WHERE saleid = (v_res->>'saleId')::int) <> 150 THEN
        RAISE EXCEPTION 'FAIL 11: header price per crate %', (SELECT unitprice FROM sale WHERE saleid = (v_res->>'saleId')::int); END IF;
    RAISE NOTICE 'ok 11 one sale, two lines, own packaging each';

    -- 14. Override: the amount changes, the eggs do not; the calculation is kept.
    EXECUTE c_onhand INTO v_on0 USING v_farm, v_egg;
    v_res := sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
        p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
        p_description => 'check394', p_flockid => NULL,
        p_linesjson => '[{"product":"Fresh Eggs","eggProductId":null,"boxes":2,"crates":3,"pieces":10,"unitPrice":150,"pricePerBox":2000,"pricePerPiece":5,"totalAmount":4350,"amountOverridden":true}]',
        p_requestkey => 'check-394-d')::jsonb;
    EXECUTE c_onhand INTO v_on1 USING v_farm, v_egg;
    SELECT * INTO v_l FROM saleline WHERE saleid = (v_res->>'saleId')::int;
    IF v_on0 - v_on1 <> 940 OR v_l.totalamount <> 4350 OR v_l.calculatedamount <> 4500 OR NOT v_l.amountoverridden THEN
        RAISE EXCEPTION 'FAIL 14: override %', row_to_json(v_l); END IF;
    RAISE NOTICE 'ok 14 override: 4,350 posted, 4,500 calculated kept, 940 eggs';

    -- Refusals.
    v_failed := FALSE;   -- an amount that does not match, without override
    BEGIN
        PERFORM sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
            p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
            p_description => 'check394', p_flockid => NULL,
            p_linesjson => '[{"product":"Fresh Eggs","boxes":1,"unitPrice":150,"totalAmount":99}]', p_requestkey => 'check-394-e');
    EXCEPTION WHEN OTHERS THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL refusal: mismatched amount accepted'; END IF;
    v_failed := FALSE;   -- the browser's egg count disagrees with the company's packaging
    BEGIN
        PERFORM sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
            p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
            p_description => 'check394', p_flockid => NULL,
            p_linesjson => '[{"product":"Fresh Eggs","boxes":1,"quantity":300,"unitPrice":150,"totalAmount":2100}]', p_requestkey => 'check-394-f');
    EXCEPTION WHEN OTHERS THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL refusal: client egg count trusted'; END IF;
    v_failed := FALSE;   -- fractional and negative packaging
    BEGIN
        PERFORM sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
            p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
            p_description => 'check394', p_flockid => NULL,
            p_linesjson => '[{"product":"Fresh Eggs","crates":1.5,"unitPrice":150,"totalAmount":225}]', p_requestkey => 'check-394-g');
    EXCEPTION WHEN OTHERS THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL refusal: 1.5 crates accepted'; END IF;
    v_failed := FALSE;
    BEGIN
        PERFORM sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
            p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
            p_description => 'check394', p_flockid => NULL,
            p_linesjson => '[{"product":"Fresh Eggs","crates":-2,"pieces":70,"unitPrice":150,"totalAmount":50}]', p_requestkey => 'check-394-h');
    EXCEPTION WHEN OTHERS THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL refusal: negative crates accepted'; END IF;
    RAISE NOTICE 'ok refusals: wrong amount, browser egg count, fractions, negatives';

    -- Idempotency: the same request key is the same sale, no second deduction.
    EXECUTE c_onhand INTO v_on0 USING v_farm, v_egg;
    v_res := sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
        p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
        p_description => 'check394', p_flockid => NULL,
        p_linesjson => '[{"product":"Fresh Eggs","eggProductId":null,"boxes":2,"crates":0,"pieces":0,"quantity":840,"unitPrice":150,"pricePerBox":2000,"totalAmount":4000}]',
        p_requestkey => 'check-394-a')::jsonb;
    EXECUTE c_onhand INTO v_on1 USING v_farm, v_egg;
    IF NOT COALESCE((v_res->>'duplicate')::boolean, FALSE) OR (v_res->>'saleId')::int <> v_sale OR v_on1 <> v_on0 THEN
        RAISE EXCEPTION 'FAIL idempotency: %', v_res; END IF;
    RAISE NOTICE 'ok double-submit returns the same sale, no second deduction';

    -- 18. Box size changes: the posted sale keeps 840 eggs, its prices and its snapshot.
    PERFORM sppoultryeggpackaging_save(v_farm, TRUE, 10, 'BoxesCratesPieces', 'Boxes', 'check394');
    SELECT * INTO v_l FROM saleline WHERE saleid = v_sale;
    IF v_l.quantity <> 840 OR v_l.cratesperbox <> 14 OR v_l.qtyboxes <> 2 OR v_l.totalamount <> 4000 THEN
        RAISE EXCEPTION 'FAIL 18: posted line changed with the configuration %', row_to_json(v_l); END IF;
    v_lines := fnpoultrysale_lines(v_sale)::text;
    IF v_lines NOT LIKE '%"cratesPerBox": 14%' OR v_lines NOT LIKE '%"boxes": 2%' THEN
        RAISE EXCEPTION 'FAIL 18: reader does not return the snapshot: %', v_lines; END IF;
    RAISE NOTICE 'ok 18 box size 14 -> 10: posted sale still 2 boxes x 14 = 840 eggs, 4,000';

    -- 17. Reversal restores exactly the eggs taken (840), whatever the box size is now.
    EXECUTE c_onhand INTO v_on0 USING v_farm, v_egg;
    PERFORM sppoultrysale_reverse(v_farm, v_sale, 'Other', 'check394', '{}'::jsonb, NULL, NULL, v_user);
    EXECUTE c_onhand INTO v_on1 USING v_farm, v_egg;
    IF v_on1 - v_on0 <> 840 THEN RAISE EXCEPTION 'FAIL 17: reversal restored % (want 840)', v_on1 - v_on0; END IF;
    RAISE NOTICE 'ok 17 reversal restores 840 eggs, not 2 x the new box size';

    -- 37. A line without packaging keys goes exactly the old way.
    EXECUTE c_onhand INTO v_on0 USING v_farm, v_egg;
    v_res := sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
        p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
        p_description => 'check394', p_flockid => NULL,
        p_linesjson => '[{"product":"Fresh Eggs","eggProductId":null,"quantity":95,"unitPrice":150,"totalAmount":475}]',
        p_requestkey => 'check-394-i')::jsonb;
    EXECUTE c_onhand INTO v_on1 USING v_farm, v_egg;
    SELECT * INTO v_l FROM saleline WHERE saleid = (v_res->>'saleId')::int;
    IF v_on0 - v_on1 <> 95 OR v_l.totalamount <> 475 OR v_l.qtycrates IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL 37: legacy line %', row_to_json(v_l); END IF;
    RAISE NOTICE 'ok 37 a line without packaging is saved as before (no snapshot)';

    -- Boxes off: a box line is refused, crates still work.
    PERFORM sppoultryeggpackaging_save(v_farm, FALSE, 10, 'CratesPieces', 'Crates', 'check394');
    v_failed := FALSE;
    BEGIN
        PERFORM sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
            p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
            p_description => 'check394', p_flockid => NULL,
            p_linesjson => '[{"product":"Fresh Eggs","boxes":1,"unitPrice":150,"totalAmount":1500}]', p_requestkey => 'check-394-j');
    EXCEPTION WHEN OTHERS THEN v_failed := TRUE; GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT; END;
    IF NOT v_failed OR v_msg NOT LIKE '%boxes are not turned on%' THEN RAISE EXCEPTION 'FAIL: box line with boxes off (%)', v_msg; END IF;
    v_res := sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => v_today::timestamp,
        p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
        p_description => 'check394', p_flockid => NULL,
        p_linesjson => '[{"product":"Fresh Eggs","crates":3,"pieces":5,"unitPrice":150,"totalAmount":475}]',
        p_requestkey => 'check-394-k')::jsonb;
    SELECT * INTO v_l FROM saleline WHERE saleid = (v_res->>'saleId')::int;
    IF v_l.quantity <> 95 OR v_l.cratesperbox IS NOT NULL OR v_l.qtycrates <> 3 THEN
        RAISE EXCEPTION 'FAIL crates-only line %', row_to_json(v_l); END IF;
    RAISE NOTICE 'ok boxes off: box line refused, crates + pieces still sell (95 eggs, 475)';

    -- Prices: set and read back, company-scoped.
    PERFORM sppoultryeggclass_setprices(v_farm, v_egg, 150, 2000, 5, 'check394');
    IF NOT EXISTS (SELECT 1 FROM sppoultryeggclassprices_get(v_farm) p
                   WHERE p.poultryproductid = v_egg AND p.pricepercrate = 150 AND p.priceperbox = 2000 AND p.priceperpiece = 5) THEN
        RAISE EXCEPTION 'FAIL prices: not read back'; END IF;
    IF NOT EXISTS (SELECT 1 FROM poultryeggsortingaudit WHERE farmid = v_farm AND entity = 'EggPrices') THEN
        RAISE EXCEPTION 'FAIL prices: not audited'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultryeggclass_setprices('check394-other-farm', v_egg, 1, 1, 1, 'check394');
    EXCEPTION WHEN OTHERS THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL prices: another company could price this class'; END IF;
    RAISE NOTICE 'ok prices set, read back, audited, company-scoped';

    RAISE NOTICE 'egg packaged sales: all checks passed';
END;
$$;

ROLLBACK;

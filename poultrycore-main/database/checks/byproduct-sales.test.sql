-- =============================================================================
-- byproduct-sales.test.sql -- checks for migration 374.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Uses the open,
-- batched flock with the most production records on dev.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm    text;
    v_user    text;
    v_flock   integer;
    v_batch   integer;
    v_egg     integer;
    v_brk     integer;
    v_dead    integer;
    v_sale    integer;
    v_sale2   integer;
    v_res     jsonb;
    v_live0   integer;
    v_sold0   integer;
    v_egg0    numeric;
    v_brk0    numeric;
    v_dead0   numeric;
    v_failed  boolean;
    v_today   date;
BEGIN
    SELECT f.farmid, f.flockid, f.batchid INTO v_farm, v_flock, v_batch
    FROM   flock f JOIN productionrecords pr ON pr.flockid = f.flockid AND pr.farmid = f.farmid
    WHERE  f.active AND NOT f.isdeleted AND f.closeddate IS NULL AND f.batchid IS NOT NULL
    GROUP  BY f.farmid, f.flockid, f.batchid ORDER BY count(*) DESC LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'byproduct sales: all checks passed';
        RETURN;
    END IF;
    SELECT fa.owneruserid INTO v_user FROM farms fa WHERE fa.id::text = v_farm OR fa.farmid::text = v_farm LIMIT 1;
    v_user  := COALESCE(v_user, 'check374');
    v_today := fncompany_businessdate(v_farm);
    PERFORM sppoultryproduct_ensurebyproducts(v_farm);
    v_egg  := fnpoultry_unsortedeggproduct(v_farm);
    v_brk  := fnpoultry_byproduct(v_farm, 'BrokenEggs');
    v_dead := fnpoultry_byproduct(v_farm, 'DeadBirds');

    -- Stock to sell, entered the 373 way.
    PERFORM sppoultrymanualmovement_post(v_farm, v_brk, NULL, 'Increase', 40, NULL, NULL, NULL, v_today, 'Opening Inventory', NULL, NULL, NULL, 'check374');
    PERFORM sppoultrymanualmovement_post(v_farm, v_dead, NULL, 'Increase', 10, NULL, v_batch, v_flock, v_today, 'Opening Inventory', NULL, NULL, NULL, 'check374');

    -- 1. The tests themselves.
    IF fnpoultrysale_isbirdsale('Dead Birds') OR NOT fnpoultrysale_isbirdsale('Birds') OR NOT fnpoultrysale_isbirdsale('Old Layers Birds')
       OR fnpoultrysale_byproductrole('broken eggs ') <> 'BrokenEggs' OR fnpoultrysale_byproductrole('Fresh Eggs') IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL 1: role / bird-sale test'; END IF;
    RAISE NOTICE 'ok 1 Dead Birds is not a live bird sale; byproducts found by name';

    -- 2. A Broken Eggs sale comes out of Broken Eggs, not eggs.
    SELECT COALESCE(sum(quantity), 0) INTO v_egg0 FROM poultrystocktransactions WHERE farmid = v_farm AND poultryproductid = v_egg;
    v_brk0 := fnpoultry_byproductonhand(v_farm, 'BrokenEggs');
    v_sale := (sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => now()::timestamp,
              p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
              p_description => 'check374', p_flockid => v_flock,
              p_linesjson => '[{"product":"Broken Eggs","eggProductId":null,"quantity":12,"unitPrice":1,"totalAmount":12}]',
              p_requestkey => 'check-374-a')::jsonb->>'saleId')::integer;
    IF fnpoultry_byproductonhand(v_farm, 'BrokenEggs') <> v_brk0 - 12 THEN RAISE EXCEPTION 'FAIL 2a: broken eggs not -12'; END IF;
    IF (SELECT COALESCE(sum(quantity), 0) FROM poultrystocktransactions WHERE farmid = v_farm AND poultryproductid = v_egg) <> v_egg0 THEN
        RAISE EXCEPTION 'FAIL 2b: egg stock moved'; END IF;
    IF NOT EXISTS (SELECT 1 FROM poultrystocktransactions t WHERE t.relatedid = v_sale AND t.txntype = 'Sale' AND t.poultryproductid = v_brk
                   AND t.salelineid IS NOT NULL AND t.flockid = v_flock AND t.batchid = v_batch) THEN
        RAISE EXCEPTION 'FAIL 2c: line / flock provenance'; END IF;
    IF (SELECT poultryproductid FROM sale WHERE saleid = v_sale) IS NOT NULL THEN RAISE EXCEPTION 'FAIL 2d: got an egg class'; END IF;
    RAISE NOTICE 'ok 2 Broken Eggs sale: Broken Eggs -12, eggs unchanged, line and flock kept';

    -- 3. Not more than is on hand.
    v_failed := FALSE;
    BEGIN PERFORM sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => now()::timestamp,
              p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
              p_description => 'check374', p_flockid => NULL,
              p_linesjson => '[{"product":"Broken Eggs","eggProductId":null,"quantity":100000,"unitPrice":1,"totalAmount":100000}]',
              p_requestkey => 'check-374-b');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3: oversold'; END IF;
    RAISE NOTICE 'ok 3 cannot sell more Broken Eggs than are on hand';

    -- 4. Dead Birds: off until enabled; then -3 Dead Birds, live birds untouched.
    PERFORM sppoultrybyproductsettings_set(v_farm, NULL, FALSE, 'check374');
    v_failed := FALSE;
    BEGIN PERFORM sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => now()::timestamp,
              p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
              p_description => 'check374', p_flockid => v_flock,
              p_linesjson => '[{"product":"Dead Birds","eggProductId":null,"quantity":3,"unitPrice":5,"totalAmount":15}]',
              p_requestkey => 'check-374-c');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4a: Dead Birds sold while not offered'; END IF;
    PERFORM sppoultrybyproductsettings_set(v_farm, NULL, TRUE, 'check374');
    IF NOT (SELECT deadbirdsinsales FROM sppoultrybyproductsettings_get(v_farm)) THEN RAISE EXCEPTION 'FAIL 4b: setting'; END IF;
    SELECT bp.currentlivebirds, bp.birdssold INTO v_live0, v_sold0 FROM fnflock_birdposition(v_farm, v_flock) bp;
    v_dead0 := fnpoultry_byproductonhand(v_farm, 'DeadBirds');
    v_sale2 := (sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => now()::timestamp,
              p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
              p_description => 'check374', p_flockid => v_flock,
              p_linesjson => '[{"product":"Dead Birds","eggProductId":null,"quantity":3,"unitPrice":5,"totalAmount":15}]',
              p_requestkey => 'check-374-d')::jsonb->>'saleId')::integer;
    IF fnpoultry_byproductonhand(v_farm, 'DeadBirds') <> v_dead0 - 3 THEN RAISE EXCEPTION 'FAIL 4c: dead birds not -3'; END IF;
    IF (SELECT bp.currentlivebirds FROM fnflock_birdposition(v_farm, v_flock) bp) <> v_live0
       OR (SELECT bp.birdssold FROM fnflock_birdposition(v_farm, v_flock) bp) <> v_sold0 THEN
        RAISE EXCEPTION 'FAIL 4d: live birds moved'; END IF;
    IF EXISTS (SELECT 1 FROM poultrystocktransactions WHERE relatedid = v_sale2 AND txntype = 'Bird Sale') THEN
        RAISE EXCEPTION 'FAIL 4e: a live bird movement'; END IF;
    RAISE NOTICE 'ok 4 Dead Birds: refused until offered; then Dead Birds -3, live birds unchanged';

    -- 5. Several lines of one byproduct: one movement per line.
    v_brk0 := fnpoultry_byproductonhand(v_farm, 'BrokenEggs');
    v_res := sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => now()::timestamp,
              p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
              p_description => 'check374', p_flockid => NULL,
              p_linesjson => '[{"product":"Broken Eggs","eggProductId":null,"quantity":5,"unitPrice":1,"totalAmount":5},{"product":"Broken Eggs","eggProductId":null,"quantity":4,"unitPrice":2,"totalAmount":8}]',
              p_requestkey => 'check-374-e')::jsonb;
    IF (SELECT count(*) FROM poultrystocktransactions WHERE relatedid = (v_res->>'saleId')::int AND txntype = 'Sale') <> 2
       OR fnpoultry_byproductonhand(v_farm, 'BrokenEggs') <> v_brk0 - 9 THEN RAISE EXCEPTION 'FAIL 5: multi-line'; END IF;
    RAISE NOTICE 'ok 5 two lines, two movements, -9';

    -- 6. A mixed entry (eggs + broken eggs) is split; each draws on its own stock.
    SELECT COALESCE(sum(quantity), 0) INTO v_egg0 FROM poultrystocktransactions WHERE farmid = v_farm AND poultryproductid = v_egg;
    v_brk0 := fnpoultry_byproductonhand(v_farm, 'BrokenEggs');
    v_res := sppoultrysale_createsplit(p_farmid => v_farm, p_userid => v_user, p_saledate => now()::timestamp,
              p_customername => NULL, p_customerid => NULL, p_paymentmethod => 'Cash', p_cashaccountid => NULL, p_paid => false,
              p_description => 'check374', p_flockid => NULL,
              p_linesjson => '[{"product":"Fresh Eggs","eggProductId":null,"quantity":30,"unitPrice":50,"totalAmount":50},{"product":"Broken Eggs","eggProductId":null,"quantity":6,"unitPrice":1,"totalAmount":6}]',
              p_requestkey => 'check-374-f');
    IF (SELECT COALESCE(sum(quantity), 0) FROM poultrystocktransactions WHERE farmid = v_farm AND poultryproductid = v_egg) <> v_egg0 - 30 THEN
        RAISE EXCEPTION 'FAIL 6a: eggs not -30'; END IF;
    IF fnpoultry_byproductonhand(v_farm, 'BrokenEggs') <> v_brk0 - 6 THEN RAISE EXCEPTION 'FAIL 6b: broken eggs not -6'; END IF;
    RAISE NOTICE 'ok 6 mixed entry: eggs -30 from eggs, broken -6 from Broken Eggs';

    -- 7. Reversal puts them back where they came from.
    v_brk0 := fnpoultry_byproductonhand(v_farm, 'BrokenEggs');
    v_dead0 := fnpoultry_byproductonhand(v_farm, 'DeadBirds');
    SELECT bp.currentlivebirds INTO v_live0 FROM fnflock_birdposition(v_farm, v_flock) bp;
    SELECT COALESCE(sum(quantity), 0) INTO v_egg0 FROM poultrystocktransactions WHERE farmid = v_farm AND poultryproductid = v_egg;
    PERFORM sppoultrysale_reverse(v_farm, v_sale, 'Other', 'check374', '{}'::jsonb, NULL, NULL, v_user);
    PERFORM sppoultrysale_reverse(v_farm, v_sale2, 'Other', 'check374', '{}'::jsonb, NULL, NULL, v_user);
    IF fnpoultry_byproductonhand(v_farm, 'BrokenEggs') <> v_brk0 + 12 THEN RAISE EXCEPTION 'FAIL 7a: broken eggs not restored'; END IF;
    IF fnpoultry_byproductonhand(v_farm, 'DeadBirds') <> v_dead0 + 3 THEN RAISE EXCEPTION 'FAIL 7b: dead birds not restored'; END IF;
    IF (SELECT bp.currentlivebirds FROM fnflock_birdposition(v_farm, v_flock) bp) <> v_live0 THEN RAISE EXCEPTION 'FAIL 7c: live birds moved'; END IF;
    IF (SELECT COALESCE(sum(quantity), 0) FROM poultrystocktransactions WHERE farmid = v_farm AND poultryproductid = v_egg) <> v_egg0 THEN
        RAISE EXCEPTION 'FAIL 7d: eggs moved'; END IF;
    RAISE NOTICE 'ok 7 reversal: Broken Eggs back to Broken Eggs, Dead Birds back to Dead Birds';

    RAISE NOTICE 'byproduct sales: all checks passed';
END $$;

ROLLBACK;

-- =============================================================================
-- Checks for 477 (Water production reopen / re-approve stock). SELF-ROLLING-BACK,
-- fixtures (own product + Draft record) in a real Water company, dated 2001.
-- Prints 'water 477: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.w477_refused(p_sql text) RETURNS text LANGUAGE plpgsql AS $r$
BEGIN
    EXECUTE p_sql;
    RETURN NULL;
EXCEPTION WHEN OTHERS THEN
    RETURN SQLERRM;
END $r$;

DO $t$
DECLARE
    v_farm text; v_prod integer; v_b integer; v_err text;
    v_no text := '__w477-' || substr(md5(random()::text), 1, 8);
    -- on hand for the fixture product, in base units
    v_onhand numeric;
BEGIN
    SELECT p.farmid INTO v_farm FROM waterproducts p
    WHERE lower(COALESCE(spfarm_gettype(p.farmid), '')) = 'water' ORDER BY p.waterproductid LIMIT 1;

    INSERT INTO waterproducts (farmid, name, unit, baseunit, packagingunit, sachetsperbag, issachetproduct, producttype, isactive)
    VALUES (v_farm, '__w477_bottle', 'Bottle', 'Bottle', 'Pack', 12, TRUE, 'FinishedGood', TRUE)
    RETURNING waterproductid INTO v_prod;

    INSERT INTO waterproductionbatches (farmid, batchnumber, productiondate, waterproductid, bagsproduced, sachetsperbag, status, createdby)
    VALUES (v_farm, v_no, DATE '2001-07-10', v_prod, 100, 12, 'Draft', '__w477')
    RETURNING waterproductionbatchid INTO v_b;

    -- 1. first approval books 100 packs x 12 = 1200
    PERFORM spwaterproductionbatch_approve(v_b, v_farm, '__w477');
    SELECT COALESCE(SUM(basequantity), 0) INTO v_onhand FROM waterstocktransactions WHERE waterproductid = v_prod;
    IF v_onhand <> 1200 THEN RAISE EXCEPTION 'FAIL 1: first approval booked %', v_onhand; END IF;
    RAISE NOTICE 'ok 1 approval books packs x per-pack';

    -- 2. pack size changes to 15, then reopen: reverses the 1200 booked, not 1500
    UPDATE waterproducts SET sachetsperbag = 15 WHERE waterproductid = v_prod;
    PERFORM spwaterproductionbatch_reopen(v_b, v_farm, '__w477');
    SELECT COALESCE(SUM(basequantity), 0) INTO v_onhand FROM waterstocktransactions WHERE waterproductid = v_prod;
    IF v_onhand <> 0 THEN RAISE EXCEPTION 'FAIL 2: reopen left % (expected 0)', v_onhand; END IF;
    IF (SELECT SUM(quantity) FROM waterstocktransactions WHERE waterproductid = v_prod) <> 0 THEN
        RAISE EXCEPTION 'FAIL 2b: packs do not net to zero';
    END IF;
    RAISE NOTICE 'ok 2 reopen reverses exactly what was booked, after a pack-size change';

    -- 3. re-approval puts the stock back (it used to stay at zero)
    PERFORM spwaterproductionbatch_approve(v_b, v_farm, '__w477');
    SELECT COALESCE(SUM(basequantity), 0) INTO v_onhand FROM waterstocktransactions WHERE waterproductid = v_prod;
    IF v_onhand <> 1500 THEN RAISE EXCEPTION 'FAIL 3: re-approval left % (expected 1500)', v_onhand; END IF;
    RAISE NOTICE 'ok 3 re-approval restocks at the current per-pack';

    -- 4. approving an Approved record is still a no-op
    PERFORM spwaterproductionbatch_approve(v_b, v_farm, '__w477');
    SELECT COALESCE(SUM(basequantity), 0) INTO v_onhand FROM waterstocktransactions WHERE waterproductid = v_prod;
    IF v_onhand <> 1500 THEN RAISE EXCEPTION 'FAIL 4: double approval moved stock to %', v_onhand; END IF;
    RAISE NOTICE 'ok 4 approving twice does not double the stock';

    -- 5. a second reopen / approve round trip still nets correctly
    PERFORM spwaterproductionbatch_reopen(v_b, v_farm, '__w477');
    PERFORM spwaterproductionbatch_approve(v_b, v_farm, '__w477');
    SELECT COALESCE(SUM(basequantity), 0) INTO v_onhand FROM waterstocktransactions WHERE waterproductid = v_prod;
    IF v_onhand <> 1500 THEN RAISE EXCEPTION 'FAIL 5: second round trip left %', v_onhand; END IF;
    RAISE NOTICE 'ok 5 repeated reopen / approve nets correctly';

    -- 6. reopen is refused once the stock has been sold, counted in base units
    INSERT INTO waterstocktransactions (farmid, waterproductid, txntype, quantity, basequantity, note, createdby)
    VALUES (v_farm, v_prod, 'Sale', -1, -15, '__w477 sale', '__w477');
    v_err := pg_temp.w477_refused(format('SELECT * FROM spwaterproductionbatch_reopen(%s, %L, %L)', v_b, v_farm, '__w477'));
    IF v_err IS NULL OR v_err NOT LIKE 'Cannot reopen%' THEN RAISE EXCEPTION 'FAIL 6: %', COALESCE(v_err, 'reopen was allowed'); END IF;
    RAISE NOTICE 'ok 6 reopen refused when the stock has been sold';

    RAISE NOTICE 'water 477: all checks passed';
END
$t$;

ROLLBACK;

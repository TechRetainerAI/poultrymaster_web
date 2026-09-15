-- Behavioural checks for migration 274: the water cost-recognition foundation.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y", then negative
-- cases that must each be blocked. Run inside a transaction you ROLL BACK; it
-- writes settings, items and an override.
--
--   psql ... -X -c "BEGIN;" -f water-cost-recognition-foundation.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 274
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- WHY THE ITEMS ARE INSERTED DIRECTLY
-- -----------------------------------
-- The poultry equivalent calls sppoultryrawmaterialitem_insert, because 261
-- reproduced that function and therefore knows its signature exactly. 274
-- deliberately does NOT touch spwaterrawmaterialitem_insert -- its live
-- Postgres body is not in the repo to copy from -- so calling it here would
-- couple these checks to a signature this workstream has not read. The rows go
-- in with a plain INSERT instead, which is what the SP does anyway for the
-- columns this file cares about, and the whole block is rolled back.
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **Nothing changes for a company that does not touch the settings.** 274 is a
-- configuration layer; it must be inert until somebody chooses otherwise. Every
-- other claim here is about the resolver getting the right answer, and this one
-- is about it giving today's answer by default -- to a company with no settings
-- row, to a category nobody configured, to an item with no override, and to a
-- purchase that predates the whole feature.
--
-- The rest:
--   1. Resolution order: item override beats company default beats the baseline.
--   2. The two settings are INDEPENDENT -- packaging deferred with treatment
--      immediate is a valid, common combination.
--   3. Only the Packaging and Chemical categories follow a company setting.
--      Filter, UVLamp, SparePart, Fuel, CleaningSupply and anything invented
--      later stay on purchase whatever the settings say.
--   4. An override survives a category change, because the user chose a method
--      rather than a category's method.
--   5. A forward-dated setting is not in force before its date.
--   6. The two predicates are exhaustive and mutually exclusive, which is what
--      stops a cost being expensed twice or never.
--   7. And, before any of that: deferral CANNOT BE SWITCHED ON at all until the
--      phase-2 chain is applied. Section 0 below.

-- =============================================================================
-- 0. THE INTERLOCK, tested first because everything after it depends on lifting
--    it.
--
-- 274 ships with fnwatercostrecognition_deferralready() returning FALSE, and the
-- two writers refuse EXPENSE_WHEN_CONSUMED while it does. That is what stops a
-- company stamping purchases as deferred while 275 is still expensing them at
-- purchase -- which would charge the same cost to Profit & Loss twice once 279
-- lands. See 274 section 7b.
-- =============================================================================
DO $lock$
DECLARE
    v_farm text;
    v_item integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE EXCEPTION 'No water company to run these checks against.';
    END IF;

    RAISE NOTICE '0a. deferral is not ready yet expect        f  got %',
        fnwatercostrecognition_deferralready();

    BEGIN
        PERFORM spwaterfinancialsettings_upsert(
            v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');
        RAISE NOTICE '0b. deferral before phase 2 <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE '0b. deferral before phase 2 blocked: %', SQLERRM;
    END;

    -- The item override reaches the purchase snapshot by the same path, so
    -- leaving that door open would make the guard above decorative.
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Interlock Probe', 'PackagingRoll', 'Roll', 'Roll', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_item;

    BEGIN
        PERFORM spwaterrawmaterialitem_setcostrecognition(
            v_item, v_farm, 'EXPENSE_WHEN_CONSUMED', 'ZZ tester');
        RAISE NOTICE '0c. deferred override before phase 2 <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE '0c. deferred override before phase 2 blocked: %', SQLERRM;
    END;

    -- Expense-when-purchased is unaffected: the interlock must not block the
    -- method every company is already on.
    PERFORM spwaterfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');
    RAISE NOTICE '0d. the safe method still works expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT packagingcostrecognitionmethod FROM spwaterfinancialsettings_get(v_farm));

    -- The read surfaces the state, so the page can explain the disabled option
    -- rather than hardcoding a fact the database owns.
    RAISE NOTICE '0e. the read surfaces it   expect        f  got %',
        (SELECT deferralavailable FROM spwaterfinancialsettings_get(v_farm));
END
$lock$;

-- Lift the interlock FOR THIS TRANSACTION ONLY so the resolution logic below can
-- be exercised. This is what the phase-2 migration will do permanently; here it
-- is discarded with the ROLLBACK, and the checks that follow are testing the
-- resolver, not the guard.
CREATE OR REPLACE FUNCTION public.fnwatercostrecognition_deferralready()
RETURNS boolean LANGUAGE sql IMMUTABLE AS $ready$ SELECT TRUE $ready$;

DO $t$
DECLARE
    v_farm  text;
    v_roll  integer;   -- PackagingRoll, no override
    v_film  integer;   -- SachetFilm,   no override
    v_chem  integer;   -- Chemical,     no override
    v_fuel  integer;   -- Fuel, unconfigured category
    v_lamp  integer;   -- UVLamp, deliberately unconfigured
    v_r     record;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE EXCEPTION 'No water company to run these checks against.';
    END IF;
    RAISE NOTICE '   using water company %', v_farm;

    -- The company must start clean, or "unconfigured behaves like today" is not
    -- being tested at all.
    DELETE FROM waterfinancialsettings WHERE farmid = v_farm;

    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Film Roll', 'PackagingRoll', 'Roll', 'Roll', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_roll;
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Sachet Film', 'SachetFilm', 'Roll', 'Roll', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_film;
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Chlorine', 'Chemical', 'Litre', 'Litre', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_chem;
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Diesel', 'Fuel', 'Litre', 'Litre', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_fuel;
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ UV Lamp', 'UVLamp', 'Piece', 'Piece', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_lamp;

    -- =====================================================================
    -- A. Unconfigured company behaves exactly like today.
    -- =====================================================================
    RAISE NOTICE 'A1. no settings row yet    expect        f  got %',
        (SELECT isconfigured FROM spwaterfinancialsettings_get(v_farm));
    RAISE NOTICE 'A2. and it reads purchased expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT packagingcostrecognitionmethod FROM spwaterfinancialsettings_get(v_farm));

    SELECT * INTO v_r FROM fnwatercostrecognition_effective(v_farm, v_roll, NULL, NULL);
    RAISE NOTICE 'A3. packaging is purchased expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    RAISE NOTICE 'A4. and says FarmDefault   expect FarmDefault  got %', v_r.source;
    SELECT * INTO v_r FROM fnwatercostrecognition_effective(v_farm, v_chem, NULL, NULL);
    RAISE NOTICE 'A5. chemical is purchased  expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    -- The interlock was lifted above, for this transaction only. Everything from
    -- here on is testing the resolver, not the guard.
    RAISE NOTICE 'A6. interlock lifted for the rest expect        t  got %',
        (SELECT deferralavailable FROM spwaterfinancialsettings_get(v_farm));

    -- =====================================================================
    -- B. The two settings are independent.
    -- =====================================================================
    PERFORM spwaterfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');

    SELECT * INTO v_r FROM fnwatercostrecognition_effective(v_farm, v_roll, NULL, NULL);
    RAISE NOTICE 'B1. packaging now deferred expect EXPENSE_WHEN_CONSUMED  got %', v_r.method;
    SELECT * INTO v_r FROM fnwatercostrecognition_effective(v_farm, v_chem, NULL, NULL);
    RAISE NOTICE 'B2. treatment unaffected   expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    -- SachetFilm follows the packaging default. See 274's header for why.
    SELECT * INTO v_r FROM fnwatercostrecognition_effective(v_farm, v_film, NULL, NULL);
    RAISE NOTICE 'B3. film follows packaging expect EXPENSE_WHEN_CONSUMED  got %', v_r.method;
    RAISE NOTICE 'B4. and is grouped Packaging expect Packaging  got %', v_r.categorygroup;

    -- The other direction, to prove neither setting is really driving both.
    PERFORM spwaterfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED', NULL, 'ZZ tester');
    SELECT * INTO v_r FROM fnwatercostrecognition_effective(v_farm, v_roll, NULL, NULL);
    RAISE NOTICE 'B5. packaging back to purchased expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    SELECT * INTO v_r FROM fnwatercostrecognition_effective(v_farm, v_chem, NULL, NULL);
    RAISE NOTICE 'B6. treatment now deferred expect EXPENSE_WHEN_CONSUMED  got %', v_r.method;

    -- =====================================================================
    -- C. Unconfigured categories are unreachable from the settings.
    -- =====================================================================
    -- Both settings deferred: if a category leaked, this is where it shows.
    PERFORM spwaterfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_CONSUMED', NULL, 'ZZ tester');

    SELECT * INTO v_r FROM fnwatercostrecognition_effective(v_farm, v_fuel, NULL, NULL);
    RAISE NOTICE 'C1. fuel stays purchased   expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    RAISE NOTICE 'C2. and is Unconfigured    expect Unconfigured  got %', v_r.categorygroup;
    -- UVLamp is deliberately NOT treatment. Deferring it would move a real
    -- category on a company that only asked about chemicals.
    SELECT * INTO v_r FROM fnwatercostrecognition_effective(v_farm, v_lamp, NULL, NULL);
    RAISE NOTICE 'C3. uv lamp stays too      expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    -- A category nobody has invented yet must fail safe, not fail deferred.
    RAISE NOTICE 'C4. unknown category safe  expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT method FROM fnwatercostrecognition_effective(v_farm, NULL, 'ZZ Invented', NULL));

    -- =====================================================================
    -- D. Item override beats the company default, both ways.
    -- =====================================================================
    -- Company defers packaging; this item opts back out.
    PERFORM spwaterrawmaterialitem_setcostrecognition(
        v_roll, v_farm, 'EXPENSE_WHEN_PURCHASED', 'ZZ tester');

    SELECT * INTO v_r FROM fnwatercostrecognition_effective(v_farm, v_roll, NULL, NULL);
    RAISE NOTICE 'D1. override wins          expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    RAISE NOTICE 'D2. and says ItemOverride  expect ItemOverride  got %', v_r.source;
    -- The company default is still reported, so the form can say "you are
    -- overriding X" rather than making the user go and look.
    RAISE NOTICE 'D3. company default reported expect EXPENSE_WHEN_CONSUMED  got %', v_r.farmdefault;

    -- And the opposite: an unconfigured category deferred item by item.
    PERFORM spwaterrawmaterialitem_setcostrecognition(
        v_fuel, v_farm, 'EXPENSE_WHEN_CONSUMED', 'ZZ tester');
    SELECT * INTO v_r FROM fnwatercostrecognition_effective(v_farm, v_fuel, NULL, NULL);
    RAISE NOTICE 'D4. fuel can defer         expect EXPENSE_WHEN_CONSUMED  got %', v_r.method;

    -- Clearing it returns the item to the company default. 'USE_DEFAULT' is the
    -- radio value the frontend sends, and must mean "no override".
    PERFORM spwaterrawmaterialitem_setcostrecognition(
        v_roll, v_farm, 'USE_DEFAULT', 'ZZ tester');
    SELECT * INTO v_r FROM fnwatercostrecognition_effective(v_farm, v_roll, NULL, NULL);
    RAISE NOTICE 'D5. cleared, back to company expect EXPENSE_WHEN_CONSUMED  got %', v_r.method;
    RAISE NOTICE 'D6. and says FarmDefault   expect FarmDefault  got %', v_r.source;
    -- A plain NULL clears it too.
    PERFORM spwaterrawmaterialitem_setcostrecognition(v_fuel, v_farm, NULL, 'ZZ tester');
    RAISE NOTICE 'D7. NULL clears as well    expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT method FROM fnwatercostrecognition_effective(v_farm, v_fuel, NULL, NULL));

    -- =====================================================================
    -- E. An override survives a category change; an inherited method does not.
    -- =====================================================================
    -- Explicit override, then moved from Chemical to PackagingRoll.
    PERFORM spwaterrawmaterialitem_setcostrecognition(
        v_chem, v_farm, 'EXPENSE_WHEN_PURCHASED', 'ZZ tester');
    UPDATE waterrawmaterialitems SET category = 'PackagingRoll'
     WHERE waterrawmaterialitemid = v_chem AND farmid = v_farm;

    SELECT * INTO v_r FROM fnwatercostrecognition_effective(v_farm, v_chem, NULL, NULL);
    RAISE NOTICE 'E1. override survived move expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    RAISE NOTICE 'E2. still an ItemOverride  expect ItemOverride  got %', v_r.source;
    RAISE NOTICE 'E3. but grouped Packaging now expect Packaging  got %', v_r.categorygroup;

    -- An INHERITED item, by contrast, follows its new category. SachetFilm ->
    -- the packaging default already; move it to Fuel and it should stop
    -- deferring.
    UPDATE waterrawmaterialitems SET category = 'Fuel'
     WHERE waterrawmaterialitemid = v_film AND farmid = v_farm;
    SELECT * INTO v_r FROM fnwatercostrecognition_effective(v_farm, v_film, NULL, NULL);
    RAISE NOTICE 'E4. inherited follows cat  expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;

    -- =====================================================================
    -- F. A forward-dated setting is not in force yet.
    -- =====================================================================
    PERFORM spwaterfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_CONSUMED',
        CURRENT_DATE + 30, 'ZZ tester');

    RAISE NOTICE 'F1. today: not yet in force expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT method FROM fnwatercostrecognition_effective(v_farm, NULL, 'PackagingRoll', CURRENT_DATE));
    RAISE NOTICE 'F2. after the date: in force expect EXPENSE_WHEN_CONSUMED  got %',
        (SELECT method FROM fnwatercostrecognition_effective(v_farm, NULL, 'PackagingRoll', CURRENT_DATE + 31));
    -- An item override is a decision about the item, not about the schedule, so
    -- it applies immediately either way.
    RAISE NOTICE 'F3. override ignores the date expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT method FROM fnwatercostrecognition_effective(v_farm, v_chem, NULL, CURRENT_DATE));

    -- =====================================================================
    -- G. The predicates are exhaustive and mutually exclusive.
    -- =====================================================================
    RAISE NOTICE 'G1. purchased -> at purchase expect        t  got %',
        fnwatercostrecognition_expenseatpurchase('EXPENSE_WHEN_PURCHASED');
    RAISE NOTICE 'G2. purchased -> not on use expect        f  got %',
        fnwatercostrecognition_expenseatconsumption('EXPENSE_WHEN_PURCHASED');
    RAISE NOTICE 'G3. consumed -> not at purchase expect        f  got %',
        fnwatercostrecognition_expenseatpurchase('EXPENSE_WHEN_CONSUMED');
    RAISE NOTICE 'G4. consumed -> on use     expect        t  got %',
        fnwatercostrecognition_expenseatconsumption('EXPENSE_WHEN_CONSUMED');
    -- Garbage in must read as today's behaviour. A method nobody recognises
    -- must never quietly defer a cost out of the P&L.
    RAISE NOTICE 'G5. NULL fails safe        expect        t  got %',
        fnwatercostrecognition_expenseatpurchase(NULL);
    RAISE NOTICE 'G6. nonsense fails safe    expect        t  got %',
        fnwatercostrecognition_expenseatpurchase('WHENEVER');
    RAISE NOTICE 'G7. never both at once     expect        0  got %',
        (SELECT COUNT(*) FROM (VALUES ('EXPENSE_WHEN_PURCHASED'), ('EXPENSE_WHEN_CONSUMED'),
                                      ('WHENEVER'), (NULL)) AS m(x)
          WHERE fnwatercostrecognition_expenseatpurchase(m.x)
              = fnwatercostrecognition_expenseatconsumption(m.x));

    -- =====================================================================
    -- H. The resolved read exposes the same answer as the resolver.
    -- =====================================================================
    RAISE NOTICE 'H1. items read resolves method expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT effectivecostrecognitionmethod FROM spwatercostrecognition_items(v_farm)
          WHERE waterrawmaterialitemid = v_chem);
    RAISE NOTICE 'H2. and names the source   expect ItemOverride  got %',
        (SELECT costrecognitionsource FROM spwatercostrecognition_items(v_farm)
          WHERE waterrawmaterialitemid = v_chem);
    -- Every item the read returns must agree with the resolver, row for row.
    RAISE NOTICE 'H3. read agrees with resolver expect        0  got %',
        (SELECT COUNT(*) FROM spwatercostrecognition_items(v_farm) x
         CROSS JOIN LATERAL fnwatercostrecognition_effective(v_farm, x.waterrawmaterialitemid, NULL, NULL) r
          WHERE x.effectivecostrecognitionmethod <> r.method);

    -- =====================================================================
    -- I. Existing purchases were snapshotted, and not as deferred.
    -- =====================================================================
    RAISE NOTICE 'I1. no purchase left NULL  expect        0  got %',
        (SELECT COUNT(*) FROM waterrawmaterialpurchases WHERE costrecognitionmethod IS NULL);
    RAISE NOTICE 'I2. none backfilled deferred expect        0  got %',
        (SELECT COUNT(*) FROM waterrawmaterialpurchases WHERE costrecognitionmethod = 'EXPENSE_WHEN_CONSUMED');
    -- The column defaults to the safe method, so a writer that forgets it still
    -- produces today's behaviour rather than a NULL nobody notices.
    RAISE NOTICE 'I3. column default is safe expect        t  got %',
        (SELECT column_default LIKE '%EXPENSE_WHEN_PURCHASED%' FROM information_schema.columns
          WHERE table_name = 'waterrawmaterialpurchases' AND column_name = 'costrecognitionmethod');
    -- 274 must not have disturbed the poultry side it was copied from.
    RAISE NOTICE 'I4. poultry settings intact expect        t  got %',
        (SELECT COUNT(*) > 0 FROM information_schema.tables WHERE table_name = 'poultryfinancialsettings');
END
$t$;

-- =============================================================================
-- Negative cases. Each must be BLOCKED.
-- =============================================================================
DO $n$
DECLARE
    v_farm text;
    v_item integer;
    v_other text;
    v_purchase integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    SELECT waterrawmaterialitemid INTO v_item FROM waterrawmaterialitems
     WHERE farmid = v_farm AND itemname = 'ZZ Film Roll';

    BEGIN
        PERFORM spwaterfinancialsettings_upsert(v_farm, 'SOMETIMES', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');
        RAISE NOTICE 'N1. an invented packaging method <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N1. an invented packaging method blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spwaterfinancialsettings_upsert(v_farm, 'EXPENSE_WHEN_PURCHASED', 'NEVER', NULL, 'ZZ tester');
        RAISE NOTICE 'N2. an invented treatment method <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N2. an invented treatment method blocked: %', SQLERRM;
    END;

    -- Backdating would claim to change how past purchases were treated while
    -- their snapshots say otherwise.
    BEGIN
        PERFORM spwaterfinancialsettings_upsert(
            v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_CONSUMED', CURRENT_DATE - 30, 'ZZ tester');
        RAISE NOTICE 'N3. a backdated effective date <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N3. a backdated effective date blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spwaterrawmaterialitem_setcostrecognition(
            v_item, v_farm, 'EXPENSE_EVENTUALLY', 'ZZ tester');
        RAISE NOTICE 'N4. an invented override   <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N4. an invented override   blocked: %', SQLERRM;
    END;

    -- An item id from ANOTHER company must not be writable just because it
    -- exists. This is the check that farm scoping is real and not decorative.
    SELECT f.farmid INTO v_other FROM farms f
     WHERE f.type = 'Water' AND f.farmid <> v_farm ORDER BY f.farmid LIMIT 1;
    IF v_other IS NULL THEN
        RAISE NOTICE 'N5. cross-company write    skipped: only one water company exists';
    ELSE
        BEGIN
            PERFORM spwaterrawmaterialitem_setcostrecognition(
                v_item, v_other, 'EXPENSE_WHEN_CONSUMED', 'ZZ tester');
            RAISE NOTICE 'N5. cross-company write    <-- BUG, allowed';
        EXCEPTION WHEN others THEN
            RAISE NOTICE 'N5. cross-company write    blocked: %', SQLERRM;
        END;
    END IF;

    -- The table itself refuses it too, so a direct write cannot get round the SP.
    BEGIN
        UPDATE waterrawmaterialitems SET costrecognitionoverride = 'MAYBE'
        WHERE  waterrawmaterialitemid = v_item;
        RAISE NOTICE 'N6. a direct bad write     <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N6. a direct bad write     blocked: %', SQLERRM;
    END;

    -- Not company-scoped, deliberately. The test company may have no purchases
    -- of its own, so scoping this to it would update zero rows and "pass"
    -- without the constraint ever being asked. Any real purchase row proves the
    -- point, and the whole block is rolled back.
    SELECT waterrawmaterialpurchaseid INTO v_purchase
    FROM   waterrawmaterialpurchases ORDER BY 1 LIMIT 1;

    IF v_purchase IS NULL THEN
        RAISE NOTICE 'N7. a bad snapshot value   skipped: no purchase rows exist';
    ELSE
        BEGIN
            UPDATE waterrawmaterialpurchases SET costrecognitionmethod = 'SOON'
            WHERE  waterrawmaterialpurchaseid = v_purchase;
            RAISE NOTICE 'N7. a bad snapshot value   <-- BUG, allowed';
        EXCEPTION WHEN others THEN
            RAISE NOTICE 'N7. a bad snapshot value   blocked: %', SQLERRM;
        END;
    END IF;
END
$n$;

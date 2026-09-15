-- Behavioural checks for migration 261: the cost-recognition foundation.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y", then negative
-- cases that must each be blocked. Run inside a transaction you ROLL BACK; it
-- writes settings, items and an override.
--
--   psql ... -X -c "BEGIN;" -f poultry-cost-recognition-foundation.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 261
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **Nothing changes for a farm that does not touch the settings.** 261 is a
-- configuration layer; it must be inert until somebody chooses otherwise. Every
-- other claim here is about the resolver getting the right answer, and this one
-- is about it giving today's answer by default -- to a farm with no settings
-- row, to a category nobody configured, to an item with no override, and to a
-- purchase that predates the whole feature.
--
-- The rest:
--   1. Resolution order: item override beats farm default beats the baseline.
--   2. The two settings are INDEPENDENT -- feed deferred with medication
--      immediate is a valid, common combination.
--   3. Only Feed and Medication categories follow a farm setting. Packaging,
--      Equipment, Supplement and anything invented later stay on purchase
--      whatever the settings say.
--   4. An override survives a category change, because the user chose a method
--      rather than a category's method.
--   5. A forward-dated setting is not in force before its date.
--   6. The two predicates are exhaustive and mutually exclusive, which is what
--      stops a cost being expensed twice or never.

DO $t$
DECLARE
    v_farm  text;
    v_feed  integer;   -- FeedIngredient, no override
    v_grain integer;   -- Grain, no override
    v_med   integer;   -- Medication, no override
    v_pack  integer;   -- Packaging, unconfigured category
    v_supp  integer;   -- Supplement, deliberately unconfigured
    v_r     record;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Poultry' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE EXCEPTION 'No poultry company to run these checks against.';
    END IF;
    RAISE NOTICE '   using poultry farm %', v_farm;

    -- The farm must start clean, or "unconfigured behaves like today" is not
    -- being tested at all.
    DELETE FROM poultryfinancialsettings WHERE farmid = v_farm;

    v_feed  := sppoultryrawmaterialitem_insert(v_farm, 'ZZ Maize',   'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'bag');
    v_grain := sppoultryrawmaterialitem_insert(v_farm, 'ZZ Soya',    'Grain',          'kg', 0, NULL, 'FIFO', 'bag');
    v_med   := sppoultryrawmaterialitem_insert(v_farm, 'ZZ Vaccine', 'Medication',     'ml', 0, NULL, 'FIFO', 'bottle');
    v_pack  := sppoultryrawmaterialitem_insert(v_farm, 'ZZ Sacks',   'Packaging',      'pc', 0, NULL, 'FIFO', 'pc');
    v_supp  := sppoultryrawmaterialitem_insert(v_farm, 'ZZ Premix',  'Supplement',     'kg', 0, NULL, 'FIFO', 'bag');

    -- =====================================================================
    -- A. Unconfigured farm behaves exactly like today.
    -- =====================================================================
    RAISE NOTICE 'A1. no settings row yet    expect        f  got %',
        (SELECT isconfigured FROM sppoultryfinancialsettings_get(v_farm));
    RAISE NOTICE 'A2. and it reads purchased expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT feedcostrecognitionmethod FROM sppoultryfinancialsettings_get(v_farm));

    SELECT * INTO v_r FROM fnpoultrycostrecognition_effective(v_farm, v_feed, NULL, NULL);
    RAISE NOTICE 'A3. feed item is purchased expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    RAISE NOTICE 'A4. and says FarmDefault   expect FarmDefault  got %', v_r.source;
    SELECT * INTO v_r FROM fnpoultrycostrecognition_effective(v_farm, v_med, NULL, NULL);
    RAISE NOTICE 'A5. med item is purchased  expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;

    -- =====================================================================
    -- B. The two settings are independent.
    -- =====================================================================
    PERFORM sppoultryfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');

    SELECT * INTO v_r FROM fnpoultrycostrecognition_effective(v_farm, v_feed, NULL, NULL);
    RAISE NOTICE 'B1. feed now deferred      expect EXPENSE_WHEN_CONSUMED  got %', v_r.method;
    SELECT * INTO v_r FROM fnpoultrycostrecognition_effective(v_farm, v_med, NULL, NULL);
    RAISE NOTICE 'B2. medication unaffected  expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    -- Grain follows the feed default. See 261's header for why.
    SELECT * INTO v_r FROM fnpoultrycostrecognition_effective(v_farm, v_grain, NULL, NULL);
    RAISE NOTICE 'B3. grain follows feed     expect EXPENSE_WHEN_CONSUMED  got %', v_r.method;
    RAISE NOTICE 'B4. and is grouped Feed    expect     Feed  got %', v_r.categorygroup;

    -- The other direction, to prove neither setting is really driving both.
    PERFORM sppoultryfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED', NULL, 'ZZ tester');
    SELECT * INTO v_r FROM fnpoultrycostrecognition_effective(v_farm, v_feed, NULL, NULL);
    RAISE NOTICE 'B5. feed back to purchased expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    SELECT * INTO v_r FROM fnpoultrycostrecognition_effective(v_farm, v_med, NULL, NULL);
    RAISE NOTICE 'B6. medication now deferred expect EXPENSE_WHEN_CONSUMED  got %', v_r.method;

    -- =====================================================================
    -- C. Unconfigured categories are unreachable from the settings.
    -- =====================================================================
    -- Both settings deferred: if a category leaked, this is where it shows.
    PERFORM sppoultryfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_CONSUMED', NULL, 'ZZ tester');

    SELECT * INTO v_r FROM fnpoultrycostrecognition_effective(v_farm, v_pack, NULL, NULL);
    RAISE NOTICE 'C1. packaging stays purchased expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    RAISE NOTICE 'C2. and is Unconfigured    expect Unconfigured  got %', v_r.categorygroup;
    -- Supplement is deliberately NOT medication. Deferring it would move a real
    -- category on a farm that only asked about drugs.
    SELECT * INTO v_r FROM fnpoultrycostrecognition_effective(v_farm, v_supp, NULL, NULL);
    RAISE NOTICE 'C3. supplement stays too   expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    -- A category nobody has invented yet must fail safe, not fail deferred.
    RAISE NOTICE 'C4. unknown category safe  expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT method FROM fnpoultrycostrecognition_effective(v_farm, NULL, 'ZZ Invented', NULL));

    -- =====================================================================
    -- D. Item override beats the farm default, both ways.
    -- =====================================================================
    -- Farm defers feed; this item opts back out.
    PERFORM sppoultryrawmaterialitem_update(
        v_feed, v_farm, 'ZZ Maize', 'FeedIngredient', 'kg', 0, TRUE, NULL, 'FIFO', 'bag',
        'EXPENSE_WHEN_PURCHASED', TRUE);

    SELECT * INTO v_r FROM fnpoultrycostrecognition_effective(v_farm, v_feed, NULL, NULL);
    RAISE NOTICE 'D1. override wins          expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    RAISE NOTICE 'D2. and says ItemOverride  expect ItemOverride  got %', v_r.source;
    -- The farm default is still reported, so the form can say "you are
    -- overriding X" rather than making the user go and look.
    RAISE NOTICE 'D3. farm default reported  expect EXPENSE_WHEN_CONSUMED  got %', v_r.farmdefault;

    -- And the opposite: an unconfigured category deferred item by item.
    PERFORM sppoultryrawmaterialitem_update(
        v_pack, v_farm, 'ZZ Sacks', 'Packaging', 'pc', 0, TRUE, NULL, 'FIFO', 'pc',
        'EXPENSE_WHEN_CONSUMED', TRUE);
    SELECT * INTO v_r FROM fnpoultrycostrecognition_effective(v_farm, v_pack, NULL, NULL);
    RAISE NOTICE 'D4. packaging can defer    expect EXPENSE_WHEN_CONSUMED  got %', v_r.method;

    -- Clearing it returns the item to the farm default.
    PERFORM sppoultryrawmaterialitem_update(
        v_feed, v_farm, 'ZZ Maize', 'FeedIngredient', 'kg', 0, TRUE, NULL, 'FIFO', 'bag',
        NULL, TRUE);
    SELECT * INTO v_r FROM fnpoultrycostrecognition_effective(v_farm, v_feed, NULL, NULL);
    RAISE NOTICE 'D5. cleared, back to farm  expect EXPENSE_WHEN_CONSUMED  got %', v_r.method;
    RAISE NOTICE 'D6. and says FarmDefault   expect FarmDefault  got %', v_r.source;

    -- =====================================================================
    -- E. An override survives a category change; an inherited method does not.
    -- =====================================================================
    -- Explicit override, then moved from Medication to FeedIngredient.
    PERFORM sppoultryrawmaterialitem_update(
        v_med, v_farm, 'ZZ Vaccine', 'Medication', 'ml', 0, TRUE, NULL, 'FIFO', 'bottle',
        'EXPENSE_WHEN_PURCHASED', TRUE);
    PERFORM sppoultryrawmaterialitem_update(
        v_med, v_farm, 'ZZ Vaccine', 'FeedIngredient', 'ml', 0, TRUE, NULL, 'FIFO', 'bottle',
        NULL, FALSE);          -- category edit only; the override is not touched

    SELECT * INTO v_r FROM fnpoultrycostrecognition_effective(v_farm, v_med, NULL, NULL);
    RAISE NOTICE 'E1. override survived move expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;
    RAISE NOTICE 'E2. still an ItemOverride  expect ItemOverride  got %', v_r.source;
    RAISE NOTICE 'E3. but grouped as Feed now expect     Feed  got %', v_r.categorygroup;

    -- An INHERITED item, by contrast, follows its new category. Grain -> the
    -- feed default already; move it to Packaging and it should stop deferring.
    PERFORM sppoultryrawmaterialitem_update(
        v_grain, v_farm, 'ZZ Soya', 'Packaging', 'kg', 0, TRUE, NULL, 'FIFO', 'bag',
        NULL, FALSE);
    SELECT * INTO v_r FROM fnpoultrycostrecognition_effective(v_farm, v_grain, NULL, NULL);
    RAISE NOTICE 'E4. inherited follows cat  expect EXPENSE_WHEN_PURCHASED  got %', v_r.method;

    -- =====================================================================
    -- F. A forward-dated setting is not in force yet.
    -- =====================================================================
    PERFORM sppoultryfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_CONSUMED',
        CURRENT_DATE + 30, 'ZZ tester');

    RAISE NOTICE 'F1. today: not yet in force expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT method FROM fnpoultrycostrecognition_effective(v_farm, NULL, 'FeedIngredient', CURRENT_DATE));
    RAISE NOTICE 'F2. after the date: in force expect EXPENSE_WHEN_CONSUMED  got %',
        (SELECT method FROM fnpoultrycostrecognition_effective(v_farm, NULL, 'FeedIngredient', CURRENT_DATE + 31));
    -- An item override is a decision about the item, not about the schedule, so
    -- it applies immediately either way.
    RAISE NOTICE 'F3. override ignores the date expect EXPENSE_WHEN_CONSUMED  got %',
        (SELECT method FROM fnpoultrycostrecognition_effective(v_farm, v_pack, NULL, CURRENT_DATE));

    -- =====================================================================
    -- G. The predicates are exhaustive and mutually exclusive.
    -- =====================================================================
    RAISE NOTICE 'G1. purchased -> at purchase expect        t  got %',
        fnpoultrycostrecognition_expenseatpurchase('EXPENSE_WHEN_PURCHASED');
    RAISE NOTICE 'G2. purchased -> not on use expect        f  got %',
        fnpoultrycostrecognition_expenseatconsumption('EXPENSE_WHEN_PURCHASED');
    RAISE NOTICE 'G3. consumed -> not at purchase expect        f  got %',
        fnpoultrycostrecognition_expenseatpurchase('EXPENSE_WHEN_CONSUMED');
    RAISE NOTICE 'G4. consumed -> on use     expect        t  got %',
        fnpoultrycostrecognition_expenseatconsumption('EXPENSE_WHEN_CONSUMED');
    -- Garbage in must read as today's behaviour. A method nobody recognises
    -- must never quietly defer a cost out of the P&L.
    RAISE NOTICE 'G5. NULL fails safe        expect        t  got %',
        fnpoultrycostrecognition_expenseatpurchase(NULL);
    RAISE NOTICE 'G6. nonsense fails safe    expect        t  got %',
        fnpoultrycostrecognition_expenseatpurchase('WHENEVER');
    RAISE NOTICE 'G7. never both at once     expect        0  got %',
        (SELECT COUNT(*) FROM (VALUES ('EXPENSE_WHEN_PURCHASED'), ('EXPENSE_WHEN_CONSUMED'),
                                      ('WHENEVER'), (NULL)) AS m(x)
          WHERE fnpoultrycostrecognition_expenseatpurchase(m.x)
              = fnpoultrycostrecognition_expenseatconsumption(m.x));

    -- =====================================================================
    -- H. The item read exposes the resolved answer.
    -- =====================================================================
    RAISE NOTICE 'H1. getall resolves method expect EXPENSE_WHEN_CONSUMED  got %',
        (SELECT effectivecostrecognitionmethod FROM sppoultryrawmaterialitem_getall(v_farm)
          WHERE poultryrawmaterialitemid = v_pack);
    RAISE NOTICE 'H2. and names the source   expect ItemOverride  got %',
        (SELECT costrecognitionsource FROM sppoultryrawmaterialitem_getall(v_farm)
          WHERE poultryrawmaterialitemid = v_pack);
    RAISE NOTICE 'H3. FIFO/LIFO/HIFO intact  expect     FIFO  got %',
        (SELECT usagemethod FROM sppoultryrawmaterialitem_getall(v_farm)
          WHERE poultryrawmaterialitemid = v_pack);

    -- =====================================================================
    -- I. Existing purchases were snapshotted, and not as deferred.
    -- =====================================================================
    RAISE NOTICE 'I1. no purchase left NULL  expect        0  got %',
        (SELECT COUNT(*) FROM poultryrawmaterialpurchases WHERE costrecognitionmethod IS NULL);
    RAISE NOTICE 'I2. none backfilled deferred expect        0  got %',
        (SELECT COUNT(*) FROM poultryrawmaterialpurchases WHERE costrecognitionmethod = 'EXPENSE_WHEN_CONSUMED');
    -- The column defaults to the safe method, so a writer that forgets it still
    -- produces today's behaviour rather than a NULL nobody notices.
    RAISE NOTICE 'I3. column default is safe expect        t  got %',
        (SELECT column_default LIKE '%EXPENSE_WHEN_PURCHASED%' FROM information_schema.columns
          WHERE table_name = 'poultryrawmaterialpurchases' AND column_name = 'costrecognitionmethod');
END
$t$;

-- =============================================================================
-- Negative cases. Each must be BLOCKED.
-- =============================================================================
DO $n$
DECLARE
    v_farm text;
    v_item integer;
    v_purchase integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Poultry' ORDER BY f.farmid LIMIT 1;
    SELECT poultryrawmaterialitemid INTO v_item FROM poultryrawmaterialitems
     WHERE farmid = v_farm AND itemname = 'ZZ Maize';

    BEGIN
        PERFORM sppoultryfinancialsettings_upsert(v_farm, 'SOMETIMES', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');
        RAISE NOTICE 'N1. an invented feed method <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N1. an invented feed method blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM sppoultryfinancialsettings_upsert(v_farm, 'EXPENSE_WHEN_PURCHASED', 'NEVER', NULL, 'ZZ tester');
        RAISE NOTICE 'N2. an invented med method <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N2. an invented med method blocked: %', SQLERRM;
    END;

    -- Backdating would claim to change how past purchases were treated while
    -- their snapshots say otherwise.
    BEGIN
        PERFORM sppoultryfinancialsettings_upsert(
            v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_CONSUMED', CURRENT_DATE - 30, 'ZZ tester');
        RAISE NOTICE 'N3. a backdated effective date <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N3. a backdated effective date blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM sppoultryrawmaterialitem_update(
            v_item, v_farm, 'ZZ Maize', 'FeedIngredient', 'kg', 0, TRUE, NULL, 'FIFO', 'bag',
            'EXPENSE_EVENTUALLY', TRUE);
        RAISE NOTICE 'N4. an invented override   <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N4. an invented override   blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM sppoultryrawmaterialitem_insert(
            v_farm, 'ZZ Bad', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'bag', 'LATER');
        RAISE NOTICE 'N5. an invented override on insert <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N5. an invented override on insert blocked: %', SQLERRM;
    END;

    -- The table itself refuses it too, so a direct write cannot get round the SP.
    BEGIN
        UPDATE poultryrawmaterialitems SET costrecognitionoverride = 'MAYBE'
        WHERE  poultryrawmaterialitemid = v_item;
        RAISE NOTICE 'N6. a direct bad write     <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N6. a direct bad write     blocked: %', SQLERRM;
    END;

    -- Not farm-scoped, deliberately. The test farm has no purchases of its own,
    -- so scoping this to it would update zero rows and "pass" without the
    -- constraint ever being asked. Any real purchase row proves the point, and
    -- the whole block is rolled back.
    SELECT poultryrawmaterialpurchaseid INTO v_purchase
    FROM   poultryrawmaterialpurchases ORDER BY 1 LIMIT 1;

    IF v_purchase IS NULL THEN
        RAISE NOTICE 'N7. a bad snapshot value   skipped: no purchase rows exist';
    ELSE
        BEGIN
            UPDATE poultryrawmaterialpurchases SET costrecognitionmethod = 'SOON'
            WHERE  poultryrawmaterialpurchaseid = v_purchase;
            RAISE NOTICE 'N7. a bad snapshot value   <-- BUG, allowed';
        EXCEPTION WHEN others THEN
            RAISE NOTICE 'N7. a bad snapshot value   blocked: %', SQLERRM;
        END;
    END IF;
END
$n$;

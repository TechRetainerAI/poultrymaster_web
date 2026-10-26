-- =============================================================================
-- 386  Galdus Magic Feed formula (0-10 days) -- the 5th default feed formula
-- =============================================================================
-- The "Layers - Gold Line" sheet behind 385 has five columns: Galdus Magic Feed
-- (till 10 days), Starter, Grower, Developer, Layer. 385 made Galdus a finished
-- feed with no formula, because the sheet mixes nothing into it -- Galdus 969574
-- is given as it is, 100 g per bird. The boss wants it listed with the others,
-- so it now has a formula like them:
--
--   + ingredient  Galdus Magic Feed (bag)                   (FeedIngredient)
--   + formula     Galdus Magic Feed Formula (0-10 days)     1,000 kg Galdus
--                 -> Galdus Magic Feed (0-10 days)
--   ~ finished feed "Pre-Starter Feed (0-10 days)" renamed "Galdus Magic Feed
--     (0-10 days)", as the sheet calls it. The bought bags are the "(bag)"
--     ingredient, so the two names never clash (item names are unique per farm).
--
-- How existing farms get it
--   poultryfeeddefaultsapplied.version was 1. The function is now version 2 and
--   each default row says which version added it. A farm seeded at version 1
--   gets ONLY the version-2 rows on its next Feed Formulas / Feed Production /
--   Supply Purchases page load -- so a default the farm deleted under 385 still
--   stays deleted. p_force still re-adds everything missing, as before.
--
-- Changes
--   ~ sppoultryfeed_ensuredefaults   (version 2: + Galdus ingredient + formula)
--   ~ the 0-10 day finished feed's name and note, on farms that still have the
--     385 name / wording (a farm's own name or note is left alone)
--
-- Re-running 385 after this would put the version-1 function back -- run 386
-- again after it. Idempotent. Self-test at the bottom cleans up after itself.
-- =============================================================================

-- ---------------------------------------------------------------- ensure
CREATE OR REPLACE FUNCTION sppoultryfeed_ensuredefaults(
    p_farmid text,
    p_userid text    DEFAULT NULL,
    p_force  boolean DEFAULT false)
RETURNS TABLE(itemscreated integer, formulascreated integer, alreadyapplied boolean)
LANGUAGE plpgsql
AS $function$
DECLARE
    c_version  constant integer := 2;
    v_applied  integer;          -- version this farm was last seeded at (NULL = never)
    v_items    integer := 0;
    v_formulas integer := 0;
    v_id       integer;
    v_formid   integer;
    r          record;
    l          record;
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN
        RAISE EXCEPTION 'Company ID is required.';
    END IF;

    -- Two tabs opening the page at once must not both seed.
    PERFORM pg_advisory_xact_lock(hashtext('poultryfeeddefaults:' || p_farmid));

    SELECT a.version INTO v_applied FROM poultryfeeddefaultsapplied a WHERE a.farmid = p_farmid;

    IF NOT COALESCE(p_force, false) AND v_applied >= c_version THEN
        RETURN QUERY SELECT 0, 0, true;
        RETURN;
    END IF;

    -- Forced, or never seeded: every row. Seeded at an older version: only the
    -- rows added since, so nothing the farm deleted comes back.
    IF COALESCE(p_force, false) THEN
        v_applied := 0;
    END IF;
    v_applied := COALESCE(v_applied, 0);

    -- ---- items ------------------------------------------------------------
    -- aliases: other names (lower-case) under which the farm may already keep
    -- the same ingredient. Only a FeedIngredient is reused, so a "Maize" filed
    -- as FinishedFeed is left alone.
    FOR r IN
        SELECT * FROM (VALUES
          ('ing.starter-concentrate', 'Starter Concentrate (35%)',          'FeedIngredient', ARRAY[]::text[],
           'Protein/mineral concentrate for starter feed, e.g. KBSC 35 (3 mm). Mixed with maize and wheat bran.', 1),
          ('ing.grower-concentrate',  'Grower Concentrate (35%)',           'FeedIngredient', ARRAY[]::text[],
           'Protein/mineral concentrate for grower feed, e.g. KBC 35 (4 mm). Mixed with maize and wheat bran.', 1),
          ('ing.layer-concentrate',   'Layer Concentrate (5%)',             'FeedIngredient', ARRAY[]::text[],
           'Vitamin/mineral concentrate for developer and layer feed, e.g. KLC 5 Caro.', 1),
          ('ing.maize',               'Maize (8.5% CP)',                    'FeedIngredient', ARRAY['maize','corn','yellow maize'],
           'Energy source. About 8.5% crude protein.', 1),
          ('ing.soybean-meal',        'Soybean Meal (46% CP)',              'FeedIngredient', ARRAY['soybean meal','soya bean meal','soyabean meal','soya meal','soymeal'],
           'Protein source. About 46% crude protein.', 1),
          ('ing.wheat-bran',          'Wheat Bran (15% CP)',                'FeedIngredient', ARRAY['wheat bran','wheatbran','bran'],
           'Fibre and protein. About 15% crude protein.', 1),
          ('ing.limestone',           'Limestone / Oyster Shell (37% Ca)',  'FeedIngredient', ARRAY['limestone','oyster shell','oyster shells','shell'],
           'Calcium for strong egg shells. About 37% calcium.', 1),
          ('ing.galdus',              'Galdus Magic Feed (bag)',            'FeedIngredient', ARRAY['galdus','galdus magic','galdus feed','galdus magic feed'],
           'Ready-made chick feed for the first 10 days, as bought (Galdus 969574). Given as it is -- about 100 g per bird in total, so 1,000 chicks need about 100 kg. About 23% crude protein.', 2),

          ('feed.prestarter', 'Galdus Magic Feed (0-10 days)',      'FinishedFeed', ARRAY[]::text[],
           'Feed for chicks from day 0 to 10 -- Galdus Magic Feed, given as it is. About 100 g per bird in total.', 1),
          ('feed.starter',    'Starter Feed (11 days - 6 weeks)',   'FinishedFeed', ARRAY[]::text[],
           'Feed for chicks from 11 days to 6 weeks old.', 1),
          ('feed.grower',     'Grower Feed (7-12 weeks)',           'FinishedFeed', ARRAY[]::text[],
           'Feed for pullets from 7 to 12 weeks old.', 1),
          ('feed.developer',  'Developer Feed (13-16 weeks)',       'FinishedFeed', ARRAY[]::text[],
           'Feed for pullets from 13 to 16 weeks old, before lay.', 1),
          ('feed.layer',      'Layer Feed (17 weeks onward)',       'FinishedFeed', ARRAY[]::text[],
           'Feed for laying hens from 17 weeks to the end of lay.', 1)
        ) AS t(dkey, name, category, aliases, notes, since)
        WHERE t.since > v_applied
    LOOP
        v_id := NULL;

        SELECT i.poultryrawmaterialitemid INTO v_id
        FROM   poultryrawmaterialitems i
        WHERE  i.farmid = p_farmid AND i.defaultkey = r.dkey;

        IF v_id IS NULL THEN
            -- Same name (any category: the name is unique per farm, so a clash
            -- would fail the insert anyway), else a known alias filed as an
            -- ingredient. Adopt it rather than add a near-duplicate.
            SELECT i.poultryrawmaterialitemid INTO v_id
            FROM   poultryrawmaterialitems i
            WHERE  i.farmid = p_farmid
              AND  (lower(btrim(i.itemname)) = lower(r.name)
                    OR (i.category = r.category AND lower(btrim(i.itemname)) = ANY (r.aliases)))
              AND  i.defaultkey IS NULL
            ORDER  BY (lower(btrim(i.itemname)) = lower(r.name)) DESC, i.isactive DESC, i.poultryrawmaterialitemid
            LIMIT  1;

            IF v_id IS NOT NULL THEN
                UPDATE poultryrawmaterialitems i SET defaultkey = r.dkey
                WHERE  i.poultryrawmaterialitemid = v_id;
            ELSE
                INSERT INTO poultryrawmaterialitems
                    (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, notes, usagemethod, defaultkey)
                VALUES
                    (p_farmid, r.name, r.category, 'kg', 'kg', 0, r.notes, 'FIFO', r.dkey);
                v_items := v_items + 1;
            END IF;
        END IF;
    END LOOP;

    -- ---- formulas ---------------------------------------------------------
    FOR r IN
        SELECT * FROM (VALUES
          ('formula.prestarter', 'Galdus Magic Feed Formula (0-10 days)', 'feed.prestarter',
           'Default for the first 10 days, from the Gold Line feeding sheet: Galdus Magic Feed is given as it is -- nothing is mixed in, so 1,000 kg of Galdus makes 1,000 kg of pre-starter feed. About 100 g per bird in total: 1,000 chicks need about 100 kg. From day 11, move to the Starter formula.', 2),
          ('formula.starter',   'Starter Formula (11 days - 6 weeks)', 'feed.starter',
           'Default formula for 1,000 kg of starter feed. One widely used layer programme -- many farms use their own variation, so edit it or make your own copy. To make 2 tonnes, every amount doubles.', 1),
          ('formula.grower',    'Grower Formula (7-12 weeks)',         'feed.grower',
           'Default formula for 1,000 kg of grower feed. One widely used layer programme -- many farms use their own variation, so edit it or make your own copy.', 1),
          ('formula.developer', 'Developer Formula (13-16 weeks)',     'feed.developer',
           'Default formula for 1,000 kg of developer feed. For a smooth change to layer feed, mix grower and layer feed in weeks 14 and 15 (70/30, 50/50, 30/70, then 0/100). Many farms use their own variation -- edit it or make your own copy.', 1),
          ('formula.layer',     'Layer Formula (17 weeks onward)',     'feed.layer',
           'Default formula for 1,000 kg of layer feed. To improve performance, replace 1% maize with 1% soya oil. For cheaper mixing, replace 2.5% maize with 2.5% wheat bran. Many farms use their own variation -- edit it or make your own copy.', 1)
        ) AS t(dkey, name, feedkey, notes, since)
        WHERE t.since > v_applied
    LOOP
        IF EXISTS (SELECT 1 FROM poultryfeedformulas f
                   WHERE f.farmid = p_farmid
                     AND (f.defaultkey = r.dkey OR lower(btrim(f.formulaname)) = lower(r.name))) THEN
            CONTINUE;
        END IF;

        INSERT INTO poultryfeedformulas
            (farmid, formulaname, finishedfeeditemid, defaultoutputunit, notes, isactive, createdby, updatedby, updatedat, defaultkey)
        VALUES
            (p_farmid, r.name,
             (SELECT i.poultryrawmaterialitemid FROM poultryrawmaterialitems i
              WHERE i.farmid = p_farmid AND i.defaultkey = r.feedkey),
             'kg', r.notes, true, p_userid, p_userid, (now() at time zone 'utc'), r.dkey)
        RETURNING poultryfeedformulaid INTO v_formid;

        FOR l IN
            SELECT * FROM (VALUES
              ('formula.prestarter', 'ing.galdus',             1000::numeric, 0),

              ('formula.starter',   'ing.starter-concentrate', 310,          0),
              ('formula.starter',   'ing.maize',               560,          1),
              ('formula.starter',   'ing.wheat-bran',          130,          2),

              ('formula.grower',    'ing.grower-concentrate',  300,          0),
              ('formula.grower',    'ing.maize',               550,          1),
              ('formula.grower',    'ing.wheat-bran',          150,          2),

              ('formula.developer', 'ing.layer-concentrate',    50,          0),
              ('formula.developer', 'ing.maize',               510,          1),
              ('formula.developer', 'ing.soybean-meal',        125,          2),
              ('formula.developer', 'ing.wheat-bran',          300,          3),
              ('formula.developer', 'ing.limestone',            15,          4),

              ('formula.layer',     'ing.layer-concentrate',    50,          0),
              ('formula.layer',     'ing.maize',               620,          1),
              ('formula.layer',     'ing.soybean-meal',        190,          2),
              ('formula.layer',     'ing.wheat-bran',           50,          3),
              ('formula.layer',     'ing.limestone',            90,          4)
            ) AS x(formulakey, itemkey, kg, sortorder)
            WHERE x.formulakey = r.dkey
        LOOP
            INSERT INTO poultryfeedformulalines
                (poultryfeedformulaid, ingredientitemid, quantitymode, percentage, fixedquantity, unitofmeasure, sortorder, notes)
            SELECT v_formid, i.poultryrawmaterialitemid, 'FixedQuantity', NULL, l.kg, 'kg', l.sortorder, NULL
            FROM   poultryrawmaterialitems i
            WHERE  i.farmid = p_farmid AND i.defaultkey = l.itemkey;
        END LOOP;

        v_formulas := v_formulas + 1;
    END LOOP;

    INSERT INTO poultryfeeddefaultsapplied (farmid, version, appliedat, appliedby)
    VALUES (p_farmid, c_version, (now() at time zone 'utc'), p_userid)
    ON CONFLICT (farmid) DO UPDATE
        SET version = EXCLUDED.version, appliedat = EXCLUDED.appliedat, appliedby = EXCLUDED.appliedby;

    RETURN QUERY SELECT v_items, v_formulas, false;
END;
$function$;

-- ---------------------------------------------------------------- 0-10 day feed: name + note
-- 385 called it "Pre-Starter Feed (0-10 days)"; the sheet calls it Galdus Magic
-- Feed. Rename only the untouched default, and only where the farm has no other
-- item by the new name (names are unique per farm).
UPDATE poultryrawmaterialitems i
SET    itemname = 'Galdus Magic Feed (0-10 days)'
WHERE  i.defaultkey = 'feed.prestarter'
  AND  i.itemname = 'Pre-Starter Feed (0-10 days)'
  AND  NOT EXISTS (SELECT 1 FROM poultryrawmaterialitems o
                   WHERE o.farmid = i.farmid
                     AND lower(btrim(o.itemname)) = lower('Galdus Magic Feed (0-10 days)'));

-- 385's note said "Bought in, not mixed" -- now it has a formula. Only rows
-- still carrying that exact note; a farm's own wording is left alone.
UPDATE poultryrawmaterialitems
SET    notes = 'Feed for chicks from day 0 to 10 -- Galdus Magic Feed, given as it is. About 100 g per bird in total.'
WHERE  defaultkey = 'feed.prestarter'
  AND  notes = 'Ready-made chick feed for the first 10 days, e.g. Galdus Magic Feed -- about 100 g per bird in total. Bought in, not mixed.';

-- ---------------------------------------------------------------- self-test
DO $selftest$
DECLARE
    f   constant text := '__selftest_386__';
    res record;
    n   integer;
    v_formid integer;
BEGIN
    -- New farm: all 13 items and 5 formulas, each exactly 1,000 kg and linked.
    SELECT * INTO res FROM sppoultryfeed_ensuredefaults(f, 'selftest');
    IF res.itemscreated <> 13 OR res.formulascreated <> 5 OR res.alreadyapplied THEN
        RAISE EXCEPTION '386 self-test: first run made % items / % formulas (want 13 / 5)', res.itemscreated, res.formulascreated;
    END IF;
    SELECT count(*) INTO n FROM (
        SELECT fo.poultryfeedformulaid
        FROM   poultryfeedformulas fo JOIN poultryfeedformulalines li USING (poultryfeedformulaid)
        WHERE  fo.farmid = f AND fo.finishedfeeditemid IS NOT NULL
        GROUP  BY fo.poultryfeedformulaid
        HAVING sum(li.fixedquantity) = 1000 AND bool_and(li.quantitymode = 'FixedQuantity')) ok;
    IF n <> 5 THEN RAISE EXCEPTION '386 self-test: % linked 1,000 kg formulas (want 5)', n; END IF;
    SELECT count(*) INTO n FROM poultryrawmaterialitems
    WHERE  farmid = f AND (  (defaultkey = 'feed.prestarter' AND itemname = 'Galdus Magic Feed (0-10 days)' AND category = 'FinishedFeed')
                          OR (defaultkey = 'ing.galdus'      AND itemname = 'Galdus Magic Feed (bag)'       AND category = 'FeedIngredient'));
    IF n <> 2 THEN RAISE EXCEPTION '386 self-test: Galdus finished feed / bag ingredient not named as expected'; END IF;

    SELECT * INTO res FROM sppoultryfeed_ensuredefaults(f, 'selftest');
    IF res.itemscreated <> 0 OR res.formulascreated <> 0 OR NOT res.alreadyapplied THEN
        RAISE EXCEPTION '386 self-test: second run was not a no-op';
    END IF;

    -- A farm seeded under 385 (version 1, no Galdus) that deleted its Grower
    -- formula: the upgrade adds Galdus only; Grower stays deleted.
    DELETE FROM poultryfeedformulas     WHERE farmid = f AND defaultkey IN ('formula.prestarter', 'formula.grower');
    DELETE FROM poultryrawmaterialitems WHERE farmid = f AND defaultkey = 'ing.galdus';
    UPDATE poultryfeeddefaultsapplied SET version = 1 WHERE farmid = f;

    SELECT * INTO res FROM sppoultryfeed_ensuredefaults(f, 'selftest');
    IF res.itemscreated <> 1 OR res.formulascreated <> 1 OR res.alreadyapplied THEN
        RAISE EXCEPTION '386 self-test: upgrade made % items / % formulas (want 1 / 1)', res.itemscreated, res.formulascreated;
    END IF;
    SELECT count(*) INTO n FROM poultryfeedformulas WHERE farmid = f AND defaultkey = 'formula.grower';
    IF n <> 0 THEN RAISE EXCEPTION '386 self-test: deleted Grower formula came back on upgrade'; END IF;

    SELECT fo.poultryfeedformulaid INTO v_formid
    FROM   poultryfeedformulas fo
    JOIN   poultryrawmaterialitems fi ON fi.poultryrawmaterialitemid = fo.finishedfeeditemid AND fi.defaultkey = 'feed.prestarter'
    WHERE  fo.farmid = f AND fo.defaultkey = 'formula.prestarter';
    IF v_formid IS NULL THEN RAISE EXCEPTION '386 self-test: Galdus formula not linked to the Galdus finished feed'; END IF;
    SELECT count(*) INTO n
    FROM   poultryfeedformulalines li JOIN poultryrawmaterialitems i ON i.poultryrawmaterialitemid = li.ingredientitemid
    WHERE  li.poultryfeedformulaid = v_formid AND i.defaultkey = 'ing.galdus' AND li.fixedquantity = 1000;
    IF n <> 1 THEN RAISE EXCEPTION '386 self-test: Galdus formula is not 1,000 kg of Galdus'; END IF;

    -- Force still brings back what is missing.
    SELECT * INTO res FROM sppoultryfeed_ensuredefaults(f, 'selftest', true);
    IF res.formulascreated <> 1 OR res.itemscreated <> 0 THEN
        RAISE EXCEPTION '386 self-test: forced run made % items / % formulas (want 0 / 1)', res.itemscreated, res.formulascreated;
    END IF;

    DELETE FROM poultryfeedformulas        WHERE farmid = f;
    DELETE FROM poultryrawmaterialitems    WHERE farmid = f;
    DELETE FROM poultryfeeddefaultsapplied WHERE farmid = f;
    RAISE NOTICE '386 self-test passed';
END;
$selftest$;

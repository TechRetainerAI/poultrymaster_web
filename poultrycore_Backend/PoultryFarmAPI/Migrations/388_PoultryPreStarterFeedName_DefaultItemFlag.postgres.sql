-- =============================================================================
-- 388  Pre-Starter Feed name back + a "Default" flag on the item list
-- =============================================================================
-- Asked for on Supply Purchases (2026-10-29):
--
--   ~ finished feed "Galdus Magic Feed (0-10 days)" renamed back to
--     "Pre-Starter Feed (0-10 days)" (386 had renamed it the other way). Only the
--     untouched default, and only where the farm has no other item by that name.
--     The bought bags stay "Galdus Magic Feed (bag)" and the formula keeps its
--     name -- its one ingredient is Galdus.
--   ~ sppoultryfeed_ensuredefaults   same body as 386 (version 2), new name for
--     feed.prestarter so farms seeded from now on get "Pre-Starter Feed".
--     Version unchanged: there are no new rows to hand out.
--   ~ sppoultryrawmaterialitem_getall   + isdefault (defaultkey IS NOT NULL), so
--     the item list can mark the seeded feeds and ingredients "Default". DROP +
--     CREATE because the return type changes; the API reads the column with
--     HasColumn, so old DB + new API is safe.
--
-- Run after 386 (re-running 385 or 386 after this would put the Galdus name back
-- in the function -- run 388 again after them). Idempotent. Self-test cleans up.
-- No new tables. Farm API rebuild needed for the Default badge.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------- ensure
CREATE OR REPLACE FUNCTION public.sppoultryfeed_ensuredefaults(p_farmid text, p_userid text DEFAULT NULL::text, p_force boolean DEFAULT false)
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

          ('feed.prestarter', 'Pre-Starter Feed (0-10 days)',       'FinishedFeed', ARRAY[]::text[],
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
$function$

;

-- ---------------------------------------------------------------- 0-10 day feed name
UPDATE poultryrawmaterialitems i
SET    itemname  = 'Pre-Starter Feed (0-10 days)',
       updatedat = (now() at time zone 'utc')
WHERE  i.defaultkey = 'feed.prestarter'
  AND  i.itemname   = 'Galdus Magic Feed (0-10 days)'
  AND  NOT EXISTS (SELECT 1 FROM poultryrawmaterialitems o
                   WHERE o.farmid = i.farmid
                     AND lower(btrim(o.itemname)) = lower('Pre-Starter Feed (0-10 days)'));

-- ---------------------------------------------------------------- getall + isdefault
DROP FUNCTION IF EXISTS public.sppoultryrawmaterialitem_getall(text);
CREATE FUNCTION public.sppoultryrawmaterialitem_getall(p_farmid text)
RETURNS TABLE(
    poultryrawmaterialitemid integer,
    farmid                   text,
    itemname                 text,
    category                 text,
    unitofmeasure            text,
    minimumstockalert        numeric,
    currentquantity          numeric,
    isactive                 boolean,
    notes                    text,
    createdat                timestamp without time zone,
    updatedat                timestamp without time zone,
    usagemethod              text,
    purchaseunitofmeasure    text,
    islowstock               boolean,
    costrecognitionoverride  text,
    effectivecostrecognitionmethod text,
    costrecognitionsource    text,
    costrecognitioncategorygroup   text,
    -- 388. One of the seeded default feeds / ingredients (385, 386).
    isdefault                boolean
)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT i.poultryrawmaterialitemid, i.farmid::text, i.itemname::text, i.category::text,
           i.unitofmeasure::text, i.minimumstockalert, i.currentquantity, i.isactive,
           i.notes::text, i.createdat, i.updatedat, i.usagemethod::text, i.purchaseunitofmeasure::text,
           COALESCE(i.currentquantity <= i.minimumstockalert, FALSE) AS islowstock,
           i.costrecognitionoverride::text,
           r.method, r.source, r.categorygroup,
           (i.defaultkey IS NOT NULL) AS isdefault
    FROM   poultryrawmaterialitems i
    CROSS  JOIN LATERAL public.fnpoultrycostrecognition_effective(
                            p_farmid, i.poultryrawmaterialitemid, i.category, NULL) r
    WHERE  i.farmid = p_farmid
    ORDER  BY i.isactive DESC NULLS LAST, i.itemname;
END;
$function$;

-- ---------------------------------------------------------------- self-test
DO $selftest$
DECLARE
    f   constant text := '__selftest_388__';
    res record;
    n   integer;
BEGIN
    SELECT * INTO res FROM sppoultryfeed_ensuredefaults(f, 'selftest');
    IF res.itemscreated <> 13 OR res.formulascreated <> 5 THEN
        RAISE EXCEPTION '388 self-test: first run made % items / % formulas (want 13 / 5)', res.itemscreated, res.formulascreated;
    END IF;
    SELECT count(*) INTO n FROM poultryrawmaterialitems
    WHERE  farmid = f AND defaultkey = 'feed.prestarter' AND itemname = 'Pre-Starter Feed (0-10 days)' AND category = 'FinishedFeed';
    IF n <> 1 THEN RAISE EXCEPTION '388 self-test: 0-10 day finished feed is not named Pre-Starter Feed'; END IF;

    INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, minimumstockalert, usagemethod)
    VALUES (f, 'My own feed', 'FinishedFeed', 'kg', 0, 'FIFO');
    SELECT count(*) INTO n FROM sppoultryrawmaterialitem_getall(f) WHERE isdefault;
    IF n <> 13 THEN RAISE EXCEPTION '388 self-test: getall marks % items default (want 13)', n; END IF;
    SELECT count(*) INTO n FROM sppoultryrawmaterialitem_getall(f) WHERE itemname = 'My own feed' AND NOT isdefault;
    IF n <> 1 THEN RAISE EXCEPTION '388 self-test: a farm''s own item is marked default'; END IF;

    DELETE FROM poultryfeedformulas        WHERE farmid = f;
    DELETE FROM poultryrawmaterialitems    WHERE farmid = f;
    DELETE FROM poultryfeeddefaultsapplied WHERE farmid = f;
    RAISE NOTICE '388 self-test passed';
END;
$selftest$;

COMMIT;

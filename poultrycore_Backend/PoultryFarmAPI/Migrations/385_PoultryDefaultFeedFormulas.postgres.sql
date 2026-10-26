-- =============================================================================
-- 385  Default feed formulas, finished feeds and ingredients for poultry farms
-- =============================================================================
-- Every poultry farm gets a ready-to-use layer feeding programme:
--
--   7 ingredients     Starter / Grower / Layer concentrate, Maize, Soybean meal,
--                     Wheat bran, Limestone/Oyster shell           (FeedIngredient)
--   5 finished feeds  named with the bird age they are for         (FinishedFeed)
--   4 formulas        Starter, Grower, Developer, Layer -- each for 1,000 kg
--
-- The numbers are a widely used layer programme (concentrate + maize + soybean
-- meal + wheat bran + limestone, per tonne). Many farms mix their own variation,
-- so the notes say so and the farm can edit, copy or delete any of it.
--
-- How it behaves
--   * COPIED, not shared. Rows land in the farm's own tables; the farm owns them.
--   * ONCE per farm. poultryfeeddefaultsapplied remembers the farm was seeded, so
--     deleting a default does not bring it back on the next page load. Passing
--     p_force => true ("Add the default formulas" button) re-adds what is
--     missing, and only what is missing.
--   * ADD-ONLY. An item or formula the farm already has under the same name is
--     reused or skipped, never overwritten. A plain "Maize" / "Wheat Bran" /
--     "Soybean Meal" / "Limestone" FeedIngredient is reused for the matching
--     default rather than adding a near-duplicate beside it.
--   * defaultkey marks a row as one of these defaults. Editing a default formula
--     makes it the farm's own: sppoultryfeedformula_upsert clears the key, so the
--     list stops calling it "Default".
--
-- Formula quantities are FixedQuantity kg lines totalling 1,000. The feed
-- production form already treats an all-fixed formula as a base recipe and
-- scales it to any batch (lib/feed-formula-scale.ts) -- 2 tonnes doubles every
-- line, 500 kg halves it.
--
-- Changes
--   + poultryrawmaterialitems.defaultkey, poultryfeedformulas.defaultkey
--   + poultryfeeddefaultsapplied
--   + sppoultryfeed_ensuredefaults(p_farmid, p_userid, p_force)
--   ~ sppoultryfeedformula_getall / _getbyid_rs1  (+ isdefault column; DROP+CREATE)
--   ~ sppoultryfeedformula_upsert                 (update clears defaultkey)
--
-- Idempotent. Re-running is safe. Self-test at the bottom runs against a
-- throwaway farm id inside one DO block and removes everything it made.
-- =============================================================================

-- ---------------------------------------------------------------- columns
ALTER TABLE poultryrawmaterialitems ADD COLUMN IF NOT EXISTS defaultkey varchar(40);
ALTER TABLE poultryfeedformulas     ADD COLUMN IF NOT EXISTS defaultkey varchar(40);

CREATE UNIQUE INDEX IF NOT EXISTS uq_poultryrawmaterialitems_farm_defaultkey
    ON poultryrawmaterialitems (farmid, defaultkey) WHERE defaultkey IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_poultryfeedformulas_farm_defaultkey
    ON poultryfeedformulas (farmid, defaultkey) WHERE defaultkey IS NOT NULL;

CREATE TABLE IF NOT EXISTS poultryfeeddefaultsapplied (
    farmid       varchar(450) PRIMARY KEY,
    version      integer      NOT NULL,
    appliedat    timestamp without time zone NOT NULL DEFAULT (now() at time zone 'utc'),
    appliedby    varchar(450)
);

-- ---------------------------------------------------------------- ensure
CREATE OR REPLACE FUNCTION sppoultryfeed_ensuredefaults(
    p_farmid text,
    p_userid text    DEFAULT NULL,
    p_force  boolean DEFAULT false)
RETURNS TABLE(itemscreated integer, formulascreated integer, alreadyapplied boolean)
LANGUAGE plpgsql
AS $function$
DECLARE
    c_version  constant integer := 1;
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

    IF NOT COALESCE(p_force, false)
       AND EXISTS (SELECT 1 FROM poultryfeeddefaultsapplied a WHERE a.farmid = p_farmid) THEN
        RETURN QUERY SELECT 0, 0, true;
        RETURN;
    END IF;

    -- ---- items ------------------------------------------------------------
    -- aliases: other names (lower-case) under which the farm may already keep
    -- the same ingredient. Only a FeedIngredient is reused, so a "Maize" filed
    -- as FinishedFeed is left alone.
    FOR r IN
        SELECT * FROM (VALUES
          ('ing.starter-concentrate', 'Starter Concentrate (35%)',          'FeedIngredient', ARRAY[]::text[],
           'Protein/mineral concentrate for starter feed, e.g. KBSC 35 (3 mm). Mixed with maize and wheat bran.'),
          ('ing.grower-concentrate',  'Grower Concentrate (35%)',           'FeedIngredient', ARRAY[]::text[],
           'Protein/mineral concentrate for grower feed, e.g. KBC 35 (4 mm). Mixed with maize and wheat bran.'),
          ('ing.layer-concentrate',   'Layer Concentrate (5%)',             'FeedIngredient', ARRAY[]::text[],
           'Vitamin/mineral concentrate for developer and layer feed, e.g. KLC 5 Caro.'),
          ('ing.maize',               'Maize (8.5% CP)',                    'FeedIngredient', ARRAY['maize','corn','yellow maize'],
           'Energy source. About 8.5% crude protein.'),
          ('ing.soybean-meal',        'Soybean Meal (46% CP)',              'FeedIngredient', ARRAY['soybean meal','soya bean meal','soyabean meal','soya meal','soymeal'],
           'Protein source. About 46% crude protein.'),
          ('ing.wheat-bran',          'Wheat Bran (15% CP)',                'FeedIngredient', ARRAY['wheat bran','wheatbran','bran'],
           'Fibre and protein. About 15% crude protein.'),
          ('ing.limestone',           'Limestone / Oyster Shell (37% Ca)',  'FeedIngredient', ARRAY['limestone','oyster shell','oyster shells','shell'],
           'Calcium for strong egg shells. About 37% calcium.'),

          ('feed.prestarter', 'Pre-Starter Feed (0-10 days)',       'FinishedFeed', ARRAY[]::text[],
           'Ready-made chick feed for the first 10 days, e.g. Galdus Magic Feed -- about 100 g per bird in total. Bought in, not mixed.'),
          ('feed.starter',    'Starter Feed (11 days - 6 weeks)',   'FinishedFeed', ARRAY[]::text[],
           'Feed for chicks from 11 days to 6 weeks old.'),
          ('feed.grower',     'Grower Feed (7-12 weeks)',           'FinishedFeed', ARRAY[]::text[],
           'Feed for pullets from 7 to 12 weeks old.'),
          ('feed.developer',  'Developer Feed (13-16 weeks)',       'FinishedFeed', ARRAY[]::text[],
           'Feed for pullets from 13 to 16 weeks old, before lay.'),
          ('feed.layer',      'Layer Feed (17 weeks onward)',       'FinishedFeed', ARRAY[]::text[],
           'Feed for laying hens from 17 weeks to the end of lay.')
        ) AS t(dkey, name, category, aliases, notes)
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
          ('formula.starter',   'Starter Formula (11 days - 6 weeks)', 'feed.starter',
           'Default formula for 1,000 kg of starter feed. One widely used layer programme -- many farms use their own variation, so edit it or make your own copy. To make 2 tonnes, every amount doubles.'),
          ('formula.grower',    'Grower Formula (7-12 weeks)',         'feed.grower',
           'Default formula for 1,000 kg of grower feed. One widely used layer programme -- many farms use their own variation, so edit it or make your own copy.'),
          ('formula.developer', 'Developer Formula (13-16 weeks)',     'feed.developer',
           'Default formula for 1,000 kg of developer feed. For a smooth change to layer feed, mix grower and layer feed in weeks 14 and 15 (70/30, 50/50, 30/70, then 0/100). Many farms use their own variation -- edit it or make your own copy.'),
          ('formula.layer',     'Layer Formula (17 weeks onward)',     'feed.layer',
           'Default formula for 1,000 kg of layer feed. To improve performance, replace 1% maize with 1% soya oil. For cheaper mixing, replace 2.5% maize with 2.5% wheat bran. Many farms use their own variation -- edit it or make your own copy.')
        ) AS t(dkey, name, feedkey, notes)
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
              ('formula.starter',   'ing.starter-concentrate', 310::numeric, 0),
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

-- ---------------------------------------------------------------- reads (+ isdefault)
DROP FUNCTION IF EXISTS sppoultryfeedformula_getall(text);
CREATE FUNCTION sppoultryfeedformula_getall(p_farmid text)
 RETURNS TABLE(poultryfeedformulaid integer, farmid text, formulaname text, finishedfeeditemid integer, defaultoutputunit text, notes text, isactive boolean, createdby text, createdat timestamp without time zone, updatedby text, updatedat timestamp without time zone, finishedfeeditemname text, finishedfeedunit text, linecount integer, percentagetotal numeric, isdefault boolean)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT f.poultryfeedformulaid, f.farmid::text, f.formulaname::text, f.finishedfeeditemid,
           f.defaultoutputunit::text, f.notes::text, f.isactive, f.createdby::text, f.createdat,
           f.updatedby::text, f.updatedat,
           i.itemname::text      AS finishedfeeditemname,
           i.unitofmeasure::text AS finishedfeedunit,
           (SELECT COUNT(*) FROM poultryfeedformulalines l WHERE l.poultryfeedformulaid = f.poultryfeedformulaid)::int AS linecount,
           COALESCE((SELECT SUM(l.percentage) FROM poultryfeedformulalines l
                     WHERE l.poultryfeedformulaid = f.poultryfeedformulaid AND l.quantitymode = 'Percentage'), 0)::numeric(9,4) AS percentagetotal,
           (f.defaultkey IS NOT NULL) AS isdefault
    FROM poultryfeedformulas f
    LEFT JOIN poultryrawmaterialitems i ON i.poultryrawmaterialitemid = f.finishedfeeditemid
    WHERE f.farmid = p_farmid
    ORDER BY f.isactive DESC, f.formulaname;
END;
$function$;

DROP FUNCTION IF EXISTS sppoultryfeedformula_getbyid_rs1(text, integer);
CREATE FUNCTION sppoultryfeedformula_getbyid_rs1(p_farmid text, p_poultryfeedformulaid integer)
 RETURNS TABLE(poultryfeedformulaid integer, farmid text, formulaname text, finishedfeeditemid integer, defaultoutputunit text, notes text, isactive boolean, createdby text, createdat timestamp without time zone, updatedby text, updatedat timestamp without time zone, finishedfeeditemname text, finishedfeedunit text, isdefault boolean)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT f.poultryfeedformulaid,
           f.farmid::text,
           f.formulaname::text,
           f.finishedfeeditemid,
           f.defaultoutputunit::text,
           f.notes::text,
           f.isactive,
           f.createdby::text,
           f.createdat,
           f.updatedby::text,
           f.updatedat,
           i.itemname::text,
           i.unitofmeasure::text,
           (f.defaultkey IS NOT NULL)
    FROM   poultryfeedformulas f
    LEFT   JOIN poultryrawmaterialitems i ON i.poultryrawmaterialitemid = f.finishedfeeditemid
    WHERE  f.farmid = p_farmid AND f.poultryfeedformulaid = p_poultryfeedformulaid;
END;
$function$;

-- ---------------------------------------------------------------- upsert (edit => farm's own)
CREATE OR REPLACE FUNCTION sppoultryfeedformula_upsert(p_farmid text, p_poultryfeedformulaid integer DEFAULT NULL::integer, p_formulaname text DEFAULT NULL::text, p_finishedfeeditemid integer DEFAULT NULL::integer, p_defaultoutputunit text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_isactive boolean DEFAULT true, p_userid text DEFAULT NULL::text, p_linesjson text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_feeditem integer := NULLIF(p_finishedfeeditemid, 0);
    v_id integer := p_poultryfeedformulaid;
BEGIN
    IF v_id IS NULL OR v_id = 0 THEN
        INSERT INTO poultryfeedformulas (farmid, formulaname, finishedfeeditemid, defaultoutputunit, notes, isactive, createdby, updatedby, updatedat)
        VALUES (p_farmid, p_formulaname, v_feeditem, p_defaultoutputunit, p_notes, COALESCE(p_isactive, TRUE), p_userid, p_userid, (now() at time zone 'utc'))
        RETURNING poultryfeedformulaid INTO v_id;
    ELSE
        -- 385: an edited default is the farm's own formula from now on.
        UPDATE poultryfeedformulas f
        SET formulaname = p_formulaname, finishedfeeditemid = v_feeditem,
            defaultoutputunit = p_defaultoutputunit, notes = p_notes, isactive = COALESCE(p_isactive, TRUE),
            updatedby = p_userid, updatedat = (now() at time zone 'utc'),
            defaultkey = NULL
        WHERE f.poultryfeedformulaid = v_id AND f.farmid = p_farmid;

        DELETE FROM poultryfeedformulalines l WHERE l.poultryfeedformulaid = v_id;
    END IF;

    IF p_linesjson IS NOT NULL AND length(p_linesjson) > 2 THEN
        INSERT INTO poultryfeedformulalines
            (poultryfeedformulaid, ingredientitemid, quantitymode, percentage, fixedquantity, unitofmeasure, sortorder, notes)
        SELECT v_id,
               (j.e->>'ingredientItemId')::integer,
               CASE WHEN (j.e->>'quantityMode') IN ('Percentage','FixedQuantity') THEN (j.e->>'quantityMode') ELSE 'Percentage' END,
               (j.e->>'percentage')::numeric,
               (j.e->>'fixedQuantity')::numeric,
               j.e->>'unitOfMeasure',
               COALESCE((j.e->>'sortOrder')::integer, 0),
               j.e->>'notes'
        FROM jsonb_array_elements(p_linesjson::jsonb) AS j(e)
        WHERE (j.e->>'ingredientItemId')::integer IS NOT NULL;
    END IF;

    RETURN v_id;
END;
$function$;

-- ---------------------------------------------------------------- self-test
DO $selftest$
DECLARE
    f   constant text := '__selftest_385__';
    res record;
    n   integer;
    v_formid integer;
BEGIN
    -- A pre-existing "Maize" ingredient must be reused, not duplicated.
    INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure)
    VALUES (f, 'Maize', 'FeedIngredient', 'kg');

    SELECT * INTO res FROM sppoultryfeed_ensuredefaults(f, 'selftest');
    IF res.itemscreated <> 11 OR res.formulascreated <> 4 OR res.alreadyapplied THEN
        RAISE EXCEPTION '385 self-test: first run made % items / % formulas (want 11 / 4)', res.itemscreated, res.formulascreated;
    END IF;

    SELECT count(*) INTO n FROM poultryrawmaterialitems WHERE farmid = f AND lower(itemname) LIKE 'maize%';
    IF n <> 1 THEN RAISE EXCEPTION '385 self-test: % maize items (want 1, the existing one reused)', n; END IF;

    -- Every formula is exactly 1,000 kg of fixed lines, and linked to its feed.
    SELECT count(*) INTO n FROM (
        SELECT fo.poultryfeedformulaid
        FROM   poultryfeedformulas fo JOIN poultryfeedformulalines li USING (poultryfeedformulaid)
        WHERE  fo.farmid = f
        GROUP  BY fo.poultryfeedformulaid
        HAVING sum(li.fixedquantity) = 1000 AND bool_and(li.quantitymode = 'FixedQuantity')) ok;
    IF n <> 4 THEN RAISE EXCEPTION '385 self-test: % formulas total 1,000 kg (want 4)', n; END IF;
    SELECT count(*) INTO n FROM poultryfeedformulas WHERE farmid = f AND finishedfeeditemid IS NULL;
    IF n <> 0 THEN RAISE EXCEPTION '385 self-test: % formulas without a finished feed', n; END IF;
    SELECT count(*) INTO n FROM poultryfeedformulalines li JOIN poultryfeedformulas fo USING (poultryfeedformulaid) WHERE fo.farmid = f;
    IF n <> 16 THEN RAISE EXCEPTION '385 self-test: % formula lines (want 16)', n; END IF;

    -- Second run: nothing, and says so.
    SELECT * INTO res FROM sppoultryfeed_ensuredefaults(f, 'selftest');
    IF res.itemscreated <> 0 OR res.formulascreated <> 0 OR NOT res.alreadyapplied THEN
        RAISE EXCEPTION '385 self-test: second run was not a no-op';
    END IF;

    -- A deleted default stays deleted ...
    DELETE FROM poultryfeedformulas WHERE farmid = f AND defaultkey = 'formula.grower';
    SELECT * INTO res FROM sppoultryfeed_ensuredefaults(f, 'selftest');
    IF res.formulascreated <> 0 THEN RAISE EXCEPTION '385 self-test: deleted default came back without force'; END IF;
    -- ... until the farm asks for it back, and then only it comes back.
    SELECT * INTO res FROM sppoultryfeed_ensuredefaults(f, 'selftest', true);
    IF res.formulascreated <> 1 OR res.itemscreated <> 0 THEN
        RAISE EXCEPTION '385 self-test: forced run made % items / % formulas (want 0 / 1)', res.itemscreated, res.formulascreated;
    END IF;

    -- Editing a default makes it the farm's own.
    SELECT poultryfeedformulaid INTO v_formid FROM poultryfeedformulas WHERE farmid = f AND defaultkey = 'formula.layer';
    PERFORM sppoultryfeedformula_upsert(f, v_formid, 'My Layer Mix', NULL, 'kg', NULL, true, 'selftest', '[]');
    SELECT count(*) INTO n FROM sppoultryfeedformula_getall(f) g WHERE g.isdefault;
    IF n <> 3 THEN RAISE EXCEPTION '385 self-test: % formulas still flagged default after an edit (want 3)', n; END IF;

    -- Clean up.
    DELETE FROM poultryfeedformulas        WHERE farmid = f;
    DELETE FROM poultryrawmaterialitems    WHERE farmid = f;
    DELETE FROM poultryfeeddefaultsapplied WHERE farmid = f;
    RAISE NOTICE '385 self-test passed';
END;
$selftest$;

-- =============================================================================
-- 218_InternalUsageCostFromProductSetup.postgres.sql
--
-- Symptom
-- -------
-- The cost field on Internal Use came back 0.00 for most products. It was seeded
-- from a weighted average of what stock had actually cost, and almost no product
-- in the database has a costed inflow yet -- so people had to type a figure they
-- had already entered once, in Product setup.
--
-- Decision
-- --------
-- Seed from the price already configured on the product. Only genericproducts
-- carries a real costprice; waterproducts and poultryproducts carry selling
-- prices only (bagprice / sachetprice / unitprice). The product owner chose to
-- use those rather than add a cost field, so internal use on water and poultry
-- is valued at the selling price. Worth knowing: that overstates the expense
-- versus what the stock actually cost to make. Swapping to a real cost price
-- later means changing only these three functions.
--
-- Fix
-- ---
-- Three unit-aware functions. Unit-aware matters: a bag is priced as a bag, not
-- as thirty sachets, because bulk pricing means bagprice <> 30 * sachetprice.
-- Asking the server for "the cost of one Bag" avoids the client scaling a
-- per-sachet figure and quietly losing the bulk discount.
--
--   fnwaterproductentrycost(farm, product, entryunit)
--   fnpoultryproductentrycost(farm, product, entryunit, eggspercrate)
--   fngenericproductentrycost(farm, product)
--
-- Order of preference in each: the price configured for that unit, then the
-- product's generic unit price, then the weighted average from stock history,
-- then 0. Zero stays legitimate -- a donation from a farm with no pricing set
-- is still a real record, and the user can always type the figure.
--
-- The three _post functions now use these for the blank-cost fallback too, so
-- the form's suggestion and the server's fallback can never disagree.
--
-- The older fn*avgcost functions are kept: they are the last fallback here, and
-- they remain the honest answer for stock valuation reporting.
--
-- Idempotent: CREATE OR REPLACE only, no data change.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- Water: bag price for a bag, sachet price for a sachet.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwaterproductentrycost(
    p_farmid text, p_waterproductid integer, p_entryunit text DEFAULT NULL)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT CASE
             WHEN lower(COALESCE(p_entryunit, '')) = 'bag' THEN
               COALESCE(
                 NULLIF(p.bagprice, 0),
                 NULLIF(p.unitprice, 0),
                 -- avgcost is per base unit, so scale it up to a bag
                 NULLIF(public.fnwaterproductavgcost(p_farmid, p_waterproductid)
                        * GREATEST(COALESCE(p.sachetsperbag, 30), 1), 0),
                 0)
             ELSE
               COALESCE(
                 NULLIF(p.sachetprice, 0),
                 NULLIF(p.unitprice, 0),
                 NULLIF(public.fnwaterproductavgcost(p_farmid, p_waterproductid), 0),
                 0)
           END::numeric
    FROM   waterproducts p
    WHERE  p.waterproductid = p_waterproductid AND p.farmid = p_farmid;
$$;

-- -----------------------------------------------------------------------------
-- Poultry: unitprice is per stock unit (per egg since migration 206), so a
-- crate is that times the eggs in a crate.
-- -----------------------------------------------------------------------------
-- NO average fallback for raw-egg products, deliberately. Egg rows in
-- poultrystocktransactions carry a unitcost in CRATES (45-55 observed) against a
-- quantity in EGGS (10,000+) -- a legacy of migration 206 changing the egg unit
-- to a piece count without restating historical unitcost. Averaging those two
-- yields ~51 "per egg", which is really a crate price; multiplying it by 30 for
-- a crate entry produced GHC 1,542 per crate in testing. Returning 0 and letting
-- someone type the real figure is honest; a confidently wrong number is not.
-- Birds, feed and supplies are unaffected, so they keep the fallback.
CREATE OR REPLACE FUNCTION public.fnpoultryproductentrycost(
    p_farmid text, p_poultryproductid integer,
    p_entryunit text DEFAULT NULL, p_eggspercrate integer DEFAULT 30)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT (COALESCE(
              NULLIF(p.unitprice, 0),
              CASE WHEN COALESCE(p.israweggproduct, FALSE) THEN NULL
                   ELSE NULLIF(public.fnpoultryproductavgcost(p_farmid, p_poultryproductid), 0)
              END,
              0)
            * CASE WHEN lower(COALESCE(p_entryunit, '')) = 'crate'
                   THEN public.fnpoultrycrateunits(p_poultryproductid, COALESCE(p_eggspercrate, 30))
                   ELSE 1 END)::numeric
    FROM   poultryproducts p
    WHERE  p.poultryproductid = p_poultryproductid AND p.farmid = p_farmid;
$$;

-- -----------------------------------------------------------------------------
-- Generic: a real cost price already exists. No conversion, so no unit param.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fngenericproductentrycost(
    p_farmid text, p_genericproductid integer)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(NULLIF(p.costprice, 0), NULLIF(p.sellingprice, 0), 0)::numeric
    FROM   genericproducts p
    WHERE  p.genericproductid = p_genericproductid AND p.farmid = p_farmid;
$$;

-- -----------------------------------------------------------------------------
-- Point the three post paths at the same source the form uses.
-- -----------------------------------------------------------------------------
DO $patch$
DECLARE
    r      record;
    v_def  text;
    v_new  text;
    v_hits int := 0;
BEGIN
    FOR r IN
        SELECT p.oid, p.proname,
               CASE p.proname
                 WHEN 'spwaterinternalusage_post' THEN
                   'public.fnwaterproductavgcost(p_farmid, i.waterproductid)'
                 WHEN 'sppoultryinternalusage_post' THEN
                   'public.fnpoultryproductavgcost(p_farmid, i.poultryproductid)'
                 WHEN 'spgenericinternalusage_post' THEN
                   'public.fngenericproductavgcost(p_farmid, i.genericproductid)'
               END AS old_call,
               CASE p.proname
                 WHEN 'spwaterinternalusage_post' THEN
                   'public.fnwaterproductentrycost(p_farmid, i.waterproductid, i.entryunit)'
                 WHEN 'sppoultryinternalusage_post' THEN
                   'public.fnpoultryproductentrycost(p_farmid, i.poultryproductid, i.entryunit, 30)'
                 WHEN 'spgenericinternalusage_post' THEN
                   'public.fngenericproductentrycost(p_farmid, i.genericproductid)'
               END AS new_call
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('spwaterinternalusage_post','sppoultryinternalusage_post','spgenericinternalusage_post')
    LOOP
        v_def := pg_get_functiondef(r.oid);

        IF position(r.new_call in v_def) > 0 THEN
            RAISE NOTICE '218: % already uses the product-setup cost.', r.proname;
            v_hits := v_hits + 1;
            CONTINUE;
        END IF;

        IF position(r.old_call in v_def) = 0 THEN
            RAISE EXCEPTION '218: could not find "%" in % -- the body has drifted, repoint it by hand.',
                r.old_call, r.proname;
        END IF;

        -- The water and poultry bodies scale the fallback by unitsperentryunit,
        -- which the new unit-aware call already accounts for. Drop that factor.
        v_new := replace(v_def, r.old_call, r.new_call);
        v_new := replace(v_new,
                         E'\n               * GREATEST(i.unitsperentryunit, 1), 4)',
                         E', 4)');
        v_new := replace(v_new,
                         'ROUND(\n               ' || r.new_call || ', 4)',
                         'ROUND(' || r.new_call || ', 4)');

        EXECUTE v_new;
        v_hits := v_hits + 1;
        RAISE NOTICE '218: % now seeds blank costs from product setup.', r.proname;
    END LOOP;

    IF v_hits < 3 THEN
        RAISE EXCEPTION '218: expected to patch 3 post functions, handled %.', v_hits;
    END IF;
END;
$patch$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'entry-cost functions (3 expected)' AS check,
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'MISSING (' || count(*) || ')' END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname IN
       ('fnwaterproductentrycost','fnpoultryproductentrycost','fngenericproductentrycost')
UNION ALL
SELECT 'post paths repointed (3 expected)',
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'ONLY ' || count(*) END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spwaterinternalusage_post','sppoultryinternalusage_post','spgenericinternalusage_post')
  AND  pg_get_functiondef(p.oid) ~ 'productentrycost';

-- What the form will now suggest, for a real sachet product and a real egg
-- product, so the numbers can be eyeballed against Product setup.
SELECT p.name AS product, 'Bag'    AS unit, public.fnwaterproductentrycost(p.farmid, p.waterproductid, 'Bag')    AS suggested
FROM   waterproducts p WHERE COALESCE(p.issachetproduct, FALSE) LIMIT 1;
SELECT p.name AS product, 'Sachet' AS unit, public.fnwaterproductentrycost(p.farmid, p.waterproductid, 'Sachet') AS suggested
FROM   waterproducts p WHERE COALESCE(p.issachetproduct, FALSE) LIMIT 1;
SELECT p.name AS product, 'Crate'  AS unit, public.fnpoultryproductentrycost(p.farmid, p.poultryproductid, 'Crate', 30) AS suggested
FROM   poultryproducts p WHERE COALESCE(p.israweggproduct, FALSE) LIMIT 1;

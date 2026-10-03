-- =============================================================================
-- 330_RestaurantInternalUse.postgres.sql
--
-- Purpose
-- -------
-- Internal Use for the standalone Restaurant, copied from Poultry (216, 218,
-- 219, 220): stock the restaurant uses itself -- staff meals, the owner's
-- family, complimentary or sample food, donations, tasting and quality
-- testing, cleaning and kitchen consumables used in-house. A costed, reversible
-- stock reduction. No sale, no customer balance, no payment, no cash movement.
--
-- Same lifecycle as Poultry: Draft -> Posted -> Reversed, "Post again" after a
-- reversal (219, which also clears the reversal columns on the header), and a
-- reversed record edits and deletes like a draft (220), with the net-zero
-- assertion before a delete.
--
-- WHAT CAN BE USED
-- ----------------
-- A line is either a STOCK ITEM (restaurantingredients: ingredients, drinks,
-- cleaning supplies, takeaway packaging ...) or a MENU ITEM. A staff meal is
-- usually "3 plates of jollof", not "0.6 kg rice, 0.4 kg tomatoes ...": a menu
-- item line takes its RECIPE out of stock (quantity x recipe quantity x (1 +
-- prep waste %)), exactly the arithmetic the sale deduction uses
-- (sprestaurant_recipe_deduct_order). A menu item with no recipe has nothing to
-- take out of stock and is refused at posting.
--
-- HOW STOCK MOVES (the 329 FIFO lot engine)
-- ------------------------------------------
-- Posting writes one 'InternalUse' stock movement per ingredient and draws it
-- through fnrestaurant_stock_draw with drawtype 'InternalUse', dated the usage
-- date -- the same engine sales, waste and stock-outs use. Stock with no
-- purchase behind it goes first, then purchase lots oldest first.
-- restaurantinternalusagestock records which movement each posting made, so a
-- reversal can find its own draws.
--
-- Reversing writes the opposite: one 'InternalUseReversal' movement per
-- ingredient (+quantity), and for every draw the posting made, the quantity and
-- deferred cost go BACK to the same lot, with a 'InternalUseReversal' row in
-- restaurantstockdraws carrying the negative deferred cost, dated today. Nothing
-- is deleted or rewritten; the out-and-back pair stays in the stock history.
-- A lot that was drawn can never have been reversed in between: purchase
-- reversal is refused once any of a lot's stock has been used.
--
-- THE COST REACHES PROFIT & LOSS EXACTLY ONCE
-- -------------------------------------------
-- Poultry books a NonCash expense row (category 'Internal Use') for the whole
-- cost. The restaurant cannot: since 329 every unit of stock is charged to the
-- P&L exactly once, at one of two moments decided by its lot's cost mode --
--   * EXPENSE_WHEN_PURCHASED: charged in full on the purchase date
--     ("Stock purchases (expense when purchased)"). Using it later, for anything,
--     must NOT charge it again.
--   * EXPENSE_WHEN_CONSUMED: held as stock value; charged pro rata as it is
--     drawn. An internal-use draw is that moment.
--   * Stock with no purchase behind it (opening stock, adjustments in) was
--     expensed however it was paid for (usually through Expenses) and carries no
--     deferred cost.
-- So the P&L cost of an internal use is the DEFERRED cost its draws moved, and
-- nothing else. It is a Cost of Sales line of its own,
-- 'stock_internal_use' "Internal Use (expense when consumed)", next to the
-- sale / waste / adjustment draws, so the whole cost of the stock sits in one
-- section whichever mode it was bought under. A reversal takes it back on the
-- day it is reversed (as a purchase reversal does); a re-post charges it again.
-- The record's own "Cost" is what the user entered (suggested from stock
-- history, Poultry 218): the value of what was used, for the list and the
-- reports. The list also returns plcost, the part of it that reached the P&L.
--
-- NON-CASH: the Profit vs Cash bridge gets its own add-back line
-- ('internal_use'), so "Unexplained" stays 0. There is no new ledger source
-- type, so Cash Flow, the cash-flow detail categories and daily closing are
-- untouched (Poultry needed its 216 daily-closing carve-out only because its
-- expense table feeds expected cash; the restaurant's closing reads the ledger).
--
-- Re-emits, from 329 (every arm kept): sprestaurant_report_pnl_lines,
-- sprestaurant_report_cash_profit_bridge, sprestaurant_deferredpurchase_history
-- (labels internal-use draws and marks reversed ones, as Poultry's history does).
-- Re-run order: 323 -> 324 -> 326 -> 328 -> 329 -> 330.
--
-- Column additions to existing tables: NONE. Re-runnable: tables are IF NOT
-- EXISTS; new functions are dropped by name (all overloads) first; re-emitted
-- ones keep their signatures.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Drop every function this migration defines for the first time, all overloads.
-- -----------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
            'fnrestaurant_internalusage_unitcost', 'sprestaurant_internalusage_items',
            'sprestaurant_internalusage_getall', 'sprestaurant_internalusage_getbyid',
            'sprestaurant_internalusage_replaceitems', 'sprestaurant_internalusage_insert',
            'sprestaurant_internalusage_update', 'sprestaurant_internalusage_delete',
            'sprestaurant_internalusage_post', 'sprestaurant_internalusage_reverse',
            'fnrestaurant_internalusage_needs', 'fnrestaurant_internalusage_categoryok')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 1. Tables (Poultry 216's header + items, restaurant keys).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS restaurantinternalusage (
    internalusageid     SERIAL PRIMARY KEY,
    farmid              TEXT NOT NULL,
    usagedate           DATE NOT NULL DEFAULT CURRENT_DATE,
    referenceno         TEXT,
    -- StaffWelfare (Staff meal) | OwnerUse | Sample (Complimentary / sample) |
    -- Donation | QualityTest | InternalConsumption (Kitchen use) | Other
    category            TEXT NOT NULL,
    reason              TEXT,
    recipientname       TEXT,
    responsiblestaffid  INT,
    staffcount          INT,                     -- helper input, informational only
    status              TEXT NOT NULL DEFAULT 'Draft',
    totalcostvalue      NUMERIC(14,2) NOT NULL DEFAULT 0,
    notes               TEXT,
    postedby            TEXT, postedat   TIMESTAMP,
    reversedby          TEXT, reversedat TIMESTAMP,
    reversalreason      TEXT,
    createdby           TEXT,
    createdat           TIMESTAMP NOT NULL DEFAULT NOW(),
    updatedat           TIMESTAMP,
    CONSTRAINT ck_restaurantinternalusage_status CHECK (status IN ('Draft', 'Posted', 'Reversed'))
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantinternalusage_farm_ref
    ON restaurantinternalusage (farmid, referenceno) WHERE referenceno IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_restaurantinternalusage_farm_date ON restaurantinternalusage (farmid, usagedate);
CREATE INDEX IF NOT EXISTS ix_restaurantinternalusage_farm_status ON restaurantinternalusage (farmid, status);

CREATE TABLE IF NOT EXISTS restaurantinternalusageitems (
    internalusageitemid SERIAL PRIMARY KEY,
    internalusageid     INT NOT NULL REFERENCES restaurantinternalusage(internalusageid) ON DELETE CASCADE,
    farmid              TEXT NOT NULL,
    itemtype            TEXT NOT NULL,           -- Ingredient | MenuItem
    ingredientid        INT REFERENCES restaurantingredients(ingredientid),
    menuitemid          INT REFERENCES restaurantmenuitems(menuitemid),
    entryquantity       NUMERIC(14,4) NOT NULL,  -- in the item's unit, or portions of a menu item
    entryunit           TEXT,
    quantityperstaff    NUMERIC(14,4),
    entryunitcost       NUMERIC(14,4) NOT NULL DEFAULT 0,
    totalcost           NUMERIC(14,2) NOT NULL DEFAULT 0,
    itemnotes           TEXT,
    CONSTRAINT ck_restaurantinternalusageitems_type CHECK (
        (itemtype = 'Ingredient' AND ingredientid IS NOT NULL AND menuitemid IS NULL)
        OR (itemtype = 'MenuItem' AND menuitemid IS NOT NULL AND ingredientid IS NULL)),
    CONSTRAINT ck_restaurantinternalusageitems_qty CHECK (entryquantity > 0 AND entryunitcost >= 0)
);
CREATE INDEX IF NOT EXISTS ix_restaurantinternalusageitems_parent ON restaurantinternalusageitems (internalusageid);

-- One row per ingredient per posting: the stock movement the posting wrote, and
-- once reversed, the movement that brought it back. The draws hang off the
-- movement (restaurantstockdraws.stockmovementid). Header delete (only ever of
-- a draft or a fully reversed record) takes these with it; the movements and
-- draws themselves stay, each naming the record's reference.
CREATE TABLE IF NOT EXISTS restaurantinternalusagestock (
    usagestockid         SERIAL PRIMARY KEY,
    internalusageid      INT NOT NULL REFERENCES restaurantinternalusage(internalusageid) ON DELETE CASCADE,
    farmid               TEXT NOT NULL,
    ingredientid         INT NOT NULL REFERENCES restaurantingredients(ingredientid),
    quantity             NUMERIC(14,4) NOT NULL CHECK (quantity > 0),
    stockmovementid      INT NOT NULL,
    deferredcost         NUMERIC(14,2) NOT NULL DEFAULT 0,
    reversalmovementid   INT,
    createdat            TIMESTAMP NOT NULL DEFAULT NOW(),
    reversedat           TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantinternalusagestock_parent ON restaurantinternalusagestock (internalusageid);
CREATE INDEX IF NOT EXISTS ix_restaurantinternalusagestock_movement ON restaurantinternalusagestock (stockmovementid);
CREATE INDEX IF NOT EXISTS ix_restaurantstockdraws_movement ON restaurantstockdraws (stockmovementid);

-- -----------------------------------------------------------------------------
-- 2. Reasons and the suggested cost (Poultry 218: "Suggested from your stock
--    history"). A stock item's cost per unit is kept by the 329 engine as the
--    value of what is on hand; with nothing costed it falls back to the last
--    purchase, then 0 (zero stays legitimate -- the user can type the figure).
--    A menu item costs its recipe.
-- -----------------------------------------------------------------------------
CREATE FUNCTION fnrestaurant_internalusage_categoryok(p_category TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE AS $$
    SELECT p_category IN ('StaffWelfare', 'OwnerUse', 'Sample', 'Donation', 'QualityTest',
                          'InternalConsumption', 'Other');
$$;

CREATE FUNCTION fnrestaurant_internalusage_unitcost(p_farmid TEXT, p_itemtype TEXT, p_itemid INT)
RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    WITH ing AS (
        SELECT i.ingredientid,
               COALESCE(NULLIF(i.costperunit, 0),
                        (SELECT p.unitcost FROM restaurantpurchases p
                          WHERE p.ingredientid = i.ingredientid AND p.status = 'Posted'
                          ORDER BY p.purchasedate DESC, p.purchaseid DESC LIMIT 1),
                        0) AS cost
          FROM restaurantingredients i
         WHERE i.farmid = p_farmid
    )
    SELECT ROUND(COALESCE(CASE p_itemtype
        WHEN 'Ingredient' THEN (SELECT ing.cost FROM ing WHERE ing.ingredientid = p_itemid)
        WHEN 'MenuItem' THEN (SELECT SUM(r.quantity * (1 + COALESCE(r.wastepercent, 0) / 100) * ing.cost)
                                FROM restaurantrecipes r JOIN ing ON ing.ingredientid = r.ingredientid
                               WHERE r.menuitemid = p_itemid AND r.farmid = p_farmid)
    END, 0), 4)::NUMERIC;
$$;

-- What the form can pick: active stock items, and active menu items that have
-- a recipe. onhand is the stock for an item, and for a menu item the whole
-- portions the recipe can still make -- the same check posting does.
CREATE FUNCTION sprestaurant_internalusage_items(p_farmid TEXT)
RETURNS TABLE(itemtype TEXT, itemid INT, name TEXT, category TEXT, unit TEXT, onhand NUMERIC,
              suggestedunitcost NUMERIC, costmode TEXT)
LANGUAGE sql STABLE AS $$
    SELECT 'Ingredient'::TEXT, i.ingredientid, i.name::TEXT, i.category::TEXT, i.unit::TEXT,
           COALESCE(i.currentstock, 0)::NUMERIC,
           fnrestaurant_internalusage_unitcost(p_farmid, 'Ingredient', i.ingredientid),
           fnrestaurant_costmode(p_farmid, i.category)
      FROM restaurantingredients i
     WHERE i.farmid = p_farmid AND COALESCE(i.isactive, TRUE)
    UNION ALL
    SELECT 'MenuItem'::TEXT, m.menuitemid, m.name::TEXT, 'Menu items'::TEXT, 'portion'::TEXT,
           GREATEST(FLOOR(MIN(COALESCE(i.currentstock, 0)
                              / NULLIF(r.quantity * (1 + COALESCE(r.wastepercent, 0) / 100), 0))), 0)::NUMERIC,
           fnrestaurant_internalusage_unitcost(p_farmid, 'MenuItem', m.menuitemid),
           NULL::TEXT
      FROM restaurantmenuitems m
      JOIN restaurantrecipes r ON r.menuitemid = m.menuitemid AND r.farmid = p_farmid
      JOIN restaurantingredients i ON i.ingredientid = r.ingredientid AND i.farmid = p_farmid
     WHERE m.farmid = p_farmid AND COALESCE(m.isactive, TRUE)
     GROUP BY m.menuitemid, m.name
     ORDER BY 1, 3;
$$;

-- -----------------------------------------------------------------------------
-- 3. Read path (Poultry 216's getall/getbyid, items as camelCase json).
--    plcost: what the CURRENT posting moved into Profit & Loss (0 for a draft
--    or a reversed record, and 0 for stock expensed when purchased).
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_internalusage_getall(
    p_farmid TEXT, p_status TEXT DEFAULT NULL, p_category TEXT DEFAULT NULL,
    p_fromdate DATE DEFAULT NULL, p_todate DATE DEFAULT NULL)
RETURNS TABLE(internalusageid INT, farmid TEXT, usagedate DATE, referenceno TEXT, category TEXT, reason TEXT,
              recipientname TEXT, responsiblestaffid INT, staffcount INT, status TEXT, totalcostvalue NUMERIC,
              plcost NUMERIC, notes TEXT, postedby TEXT, postedat TIMESTAMP, reversedby TEXT, reversedat TIMESTAMP,
              reversalreason TEXT, createdby TEXT, createdat TIMESTAMP, updatedat TIMESTAMP, itemsjson TEXT)
LANGUAGE sql STABLE AS $$
    SELECT h.internalusageid, h.farmid, h.usagedate, h.referenceno, h.category, h.reason,
           h.recipientname, h.responsiblestaffid, h.staffcount, h.status, h.totalcostvalue,
           COALESCE((SELECT SUM(s.deferredcost) FROM restaurantinternalusagestock s
                      WHERE s.internalusageid = h.internalusageid AND s.reversalmovementid IS NULL), 0)::NUMERIC(14,2),
           h.notes, h.postedby, h.postedat, h.reversedby, h.reversedat, h.reversalreason,
           h.createdby, h.createdat, h.updatedat,
           COALESCE((
               SELECT json_agg(json_build_object(
                          'internalUsageItemId', i.internalusageitemid,
                          'itemType',            i.itemtype,
                          'ingredientId',        i.ingredientid,
                          'menuItemId',          i.menuitemid,
                          'itemName',            COALESCE(g.name, m.name),
                          'entryQuantity',       i.entryquantity,
                          'entryUnit',           i.entryunit,
                          'quantityPerStaff',    i.quantityperstaff,
                          'entryUnitCost',       i.entryunitcost,
                          'totalCost',           i.totalcost,
                          'itemNotes',           i.itemnotes)
                      ORDER BY i.internalusageitemid)::TEXT
                 FROM restaurantinternalusageitems i
                 LEFT JOIN restaurantingredients g ON g.ingredientid = i.ingredientid
                 LEFT JOIN restaurantmenuitems m ON m.menuitemid = i.menuitemid
                WHERE i.internalusageid = h.internalusageid), '[]')
      FROM restaurantinternalusage h
     WHERE h.farmid = p_farmid
       AND (p_status IS NULL OR h.status = p_status)
       AND (p_category IS NULL OR h.category = p_category)
       AND (p_fromdate IS NULL OR h.usagedate >= p_fromdate)
       AND (p_todate IS NULL OR h.usagedate <= p_todate)
     ORDER BY h.usagedate DESC, h.internalusageid DESC;
$$;

CREATE FUNCTION sprestaurant_internalusage_getbyid(p_internalusageid INT, p_farmid TEXT)
RETURNS TABLE(internalusageid INT, farmid TEXT, usagedate DATE, referenceno TEXT, category TEXT, reason TEXT,
              recipientname TEXT, responsiblestaffid INT, staffcount INT, status TEXT, totalcostvalue NUMERIC,
              plcost NUMERIC, notes TEXT, postedby TEXT, postedat TIMESTAMP, reversedby TEXT, reversedat TIMESTAMP,
              reversalreason TEXT, createdby TEXT, createdat TIMESTAMP, updatedat TIMESTAMP, itemsjson TEXT)
LANGUAGE sql STABLE AS $$
    SELECT g.* FROM sprestaurant_internalusage_getall(p_farmid) g WHERE g.internalusageid = p_internalusageid;
$$;

-- -----------------------------------------------------------------------------
-- 4. Write path. Lines are replaced whole (Poultry 216); the header total
--    follows the lines, draft included (215). Every item must belong to this
--    restaurant.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_internalusage_replaceitems(p_internalusageid INT, p_farmid TEXT, p_itemsjson TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_bad INT;
BEGIN
    DELETE FROM restaurantinternalusageitems WHERE internalusageid = p_internalusageid;

    IF p_itemsjson IS NOT NULL AND btrim(p_itemsjson) NOT IN ('', '[]') THEN
        -- Quoted identifiers: json_to_recordset matches keys case-sensitively (214).
        SELECT COUNT(*) INTO v_bad
          FROM json_to_recordset(p_itemsjson::json) AS j("itemType" TEXT, "ingredientId" INT, "menuItemId" INT,
                                                         "entryQuantity" NUMERIC)
         WHERE COALESCE(j."entryQuantity", 0) > 0
           AND NOT (   (COALESCE(j."itemType", 'Ingredient') = 'Ingredient'
                        AND EXISTS (SELECT 1 FROM restaurantingredients i
                                     WHERE i.ingredientid = j."ingredientId" AND i.farmid = p_farmid))
                    OR (j."itemType" = 'MenuItem'
                        AND EXISTS (SELECT 1 FROM restaurantmenuitems m
                                     WHERE m.menuitemid = j."menuItemId" AND m.farmid = p_farmid)));
        IF v_bad > 0 THEN RAISE EXCEPTION 'Pick a stock item or menu item of this restaurant.'; END IF;

        INSERT INTO restaurantinternalusageitems (internalusageid, farmid, itemtype, ingredientid, menuitemid,
                                                  entryquantity, entryunit, quantityperstaff, entryunitcost,
                                                  totalcost, itemnotes)
        SELECT p_internalusageid, p_farmid, COALESCE(j."itemType", 'Ingredient'),
               CASE WHEN COALESCE(j."itemType", 'Ingredient') = 'Ingredient' THEN j."ingredientId" END,
               CASE WHEN j."itemType" = 'MenuItem' THEN j."menuItemId" END,
               ROUND(j."entryQuantity", 4),
               CASE WHEN j."itemType" = 'MenuItem' THEN 'portion'
                    ELSE COALESCE(NULLIF(btrim(j."entryUnit"), ''), g.unit) END,
               j."quantityPerStaff",
               ROUND(GREATEST(COALESCE(j."entryUnitCost", 0), 0), 4),
               ROUND(j."entryQuantity" * GREATEST(COALESCE(j."entryUnitCost", 0), 0), 2),
               NULLIF(btrim(j."itemNotes"), '')
          FROM json_to_recordset(p_itemsjson::json) AS j("itemType" TEXT, "ingredientId" INT, "menuItemId" INT,
                                                         "entryQuantity" NUMERIC, "entryUnit" TEXT,
                                                         "quantityPerStaff" NUMERIC, "entryUnitCost" NUMERIC,
                                                         "itemNotes" TEXT)
          LEFT JOIN restaurantingredients g ON g.ingredientid = j."ingredientId" AND g.farmid = p_farmid
         WHERE COALESCE(j."entryQuantity", 0) > 0;
    END IF;

    UPDATE restaurantinternalusage h
       SET totalcostvalue = COALESCE((SELECT SUM(i.totalcost) FROM restaurantinternalusageitems i
                                       WHERE i.internalusageid = h.internalusageid), 0),
           updatedat = NOW()
     WHERE h.internalusageid = p_internalusageid;
END $$;

CREATE FUNCTION sprestaurant_internalusage_insert(
    p_farmid TEXT, p_usagedate DATE, p_category TEXT, p_reason TEXT DEFAULT NULL,
    p_recipientname TEXT DEFAULT NULL, p_responsiblestaffid INT DEFAULT NULL, p_staffcount INT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL, p_itemsjson TEXT DEFAULT NULL, p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_id INT; v_date DATE := COALESCE(p_usagedate, CURRENT_DATE);
BEGIN
    IF NOT COALESCE(fnrestaurant_internalusage_categoryok(p_category), FALSE) THEN
        RAISE EXCEPTION 'Pick what the stock was used for.';
    END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'The date cannot be in the future.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    INSERT INTO restaurantinternalusage (farmid, usagedate, category, reason, recipientname,
                                         responsiblestaffid, staffcount, notes, status, createdby)
    VALUES (p_farmid, v_date, p_category, NULLIF(btrim(p_reason), ''), NULLIF(btrim(p_recipientname), ''),
            p_responsiblestaffid, p_staffcount, NULLIF(btrim(p_notes), ''), 'Draft', p_createdby)
    RETURNING internalusageid INTO v_id;

    UPDATE restaurantinternalusage
       SET referenceno = 'IU-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::TEXT, 4, '0')
     WHERE internalusageid = v_id;

    PERFORM sprestaurant_internalusage_replaceitems(v_id, p_farmid, p_itemsjson);
    RETURN v_id;
END $$;

-- 220: a draft or a reversed record can be edited. Editing a reversed record
-- leaves it Reversed; posting it again is the separate step that moves stock.
CREATE FUNCTION sprestaurant_internalusage_update(
    p_internalusageid INT, p_farmid TEXT, p_usagedate DATE, p_category TEXT, p_reason TEXT DEFAULT NULL,
    p_recipientname TEXT DEFAULT NULL, p_responsiblestaffid INT DEFAULT NULL, p_staffcount INT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL, p_itemsjson TEXT DEFAULT NULL, p_updatedby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_status TEXT; v_date DATE;
BEGIN
    SELECT h.status, COALESCE(p_usagedate, h.usagedate) INTO v_status, v_date
      FROM restaurantinternalusage h
     WHERE h.internalusageid = p_internalusageid AND h.farmid = p_farmid FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Internal use record % not found.', p_internalusageid; END IF;
    IF v_status NOT IN ('Draft', 'Reversed') THEN
        RAISE EXCEPTION 'Only a draft or a reversed record can be edited. This one is %. Reverse it first.', v_status;
    END IF;
    IF p_category IS NOT NULL AND btrim(p_category) <> ''
       AND NOT fnrestaurant_internalusage_categoryok(p_category) THEN
        RAISE EXCEPTION 'Pick what the stock was used for.';
    END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'The date cannot be in the future.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    UPDATE restaurantinternalusage
       SET usagedate = v_date,
           category = COALESCE(NULLIF(btrim(p_category), ''), category),
           reason = NULLIF(btrim(p_reason), ''),
           recipientname = NULLIF(btrim(p_recipientname), ''),
           responsiblestaffid = p_responsiblestaffid,
           staffcount = p_staffcount,
           notes = NULLIF(btrim(p_notes), ''),
           updatedat = NOW()
     WHERE internalusageid = p_internalusageid AND farmid = p_farmid;

    PERFORM sprestaurant_internalusage_replaceitems(p_internalusageid, p_farmid, p_itemsjson);
END $$;

-- 220: a draft or a reversed record can be deleted. The stock movements and
-- draws stay; a Reversed record whose postings do not all have their reversal
-- is refused (the net-zero assertion), so no real movement is stranded.
CREATE FUNCTION sprestaurant_internalusage_delete(p_internalusageid INT, p_farmid TEXT, p_userid TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_status TEXT; v_open NUMERIC;
BEGIN
    SELECT h.status INTO v_status FROM restaurantinternalusage h
     WHERE h.internalusageid = p_internalusageid AND h.farmid = p_farmid FOR UPDATE;
    IF v_status IS NULL THEN RETURN; END IF;
    IF v_status NOT IN ('Draft', 'Reversed') THEN
        RAISE EXCEPTION 'A % record cannot be deleted -- reverse it first, so the stock history survives.', v_status;
    END IF;
    SELECT COALESCE(SUM(s.quantity), 0) INTO v_open FROM restaurantinternalusagestock s
     WHERE s.internalusageid = p_internalusageid AND s.reversalmovementid IS NULL;
    IF v_open <> 0 THEN
        RAISE EXCEPTION 'This record is marked Reversed but % units are still out of stock. Reverse it properly before deleting it.',
            trim_scale(v_open);
    END IF;
    DELETE FROM restaurantinternalusage WHERE internalusageid = p_internalusageid AND farmid = p_farmid;
END $$;

-- -----------------------------------------------------------------------------
-- 5. What a record takes out of stock, per ingredient: a stock-item line as
--    entered, a menu-item line through its recipe (the sale deduction's
--    arithmetic). A menu item without a recipe returns a row with no ingredient
--    so posting can name it.
-- -----------------------------------------------------------------------------
CREATE FUNCTION fnrestaurant_internalusage_needs(p_internalusageid INT, p_farmid TEXT)
RETURNS TABLE(ingredientid INT, qty NUMERIC, menuname TEXT)
LANGUAGE sql STABLE AS $$
    WITH raw AS (
        SELECT i.ingredientid AS ing, i.entryquantity AS q, NULL::TEXT AS mname
          FROM restaurantinternalusageitems i
         WHERE i.internalusageid = p_internalusageid AND i.itemtype = 'Ingredient'
        UNION ALL
        SELECT r.ingredientid, r.quantity * (1 + COALESCE(r.wastepercent, 0) / 100) * i.entryquantity, m.name
          FROM restaurantinternalusageitems i
          JOIN restaurantmenuitems m ON m.menuitemid = i.menuitemid
          LEFT JOIN restaurantrecipes r ON r.menuitemid = i.menuitemid AND r.farmid = p_farmid
         WHERE i.internalusageid = p_internalusageid AND i.itemtype = 'MenuItem'
    )
    SELECT raw.ing, ROUND(SUM(raw.q), 4), MIN(raw.mname) FILTER (WHERE raw.ing IS NULL)
      FROM raw GROUP BY raw.ing ORDER BY raw.ing NULLS FIRST;
$$;

-- -----------------------------------------------------------------------------
-- 6. Post (Poultry 216 + 219: a reversed record may be posted again).
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_internalusage_post(p_internalusageid INT, p_farmid TEXT, p_postedby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_h restaurantinternalusage%ROWTYPE; v_total NUMERIC(14,2); v_stock NUMERIC; v_name TEXT;
    v_mid INT; v_cost NUMERIC(14,2); v_ref TEXT; n RECORD;
BEGIN
    SELECT * INTO v_h FROM restaurantinternalusage h
     WHERE h.internalusageid = p_internalusageid AND h.farmid = p_farmid FOR UPDATE;
    IF v_h.internalusageid IS NULL THEN RAISE EXCEPTION 'Internal use record % not found.', p_internalusageid; END IF;
    IF v_h.status = 'Posted' THEN RETURN; END IF;   -- guard 1 of 2
    IF v_h.status NOT IN ('Draft', 'Reversed') THEN RAISE EXCEPTION 'Cannot post a % record.', v_h.status; END IF;
    IF v_h.usagedate > CURRENT_DATE THEN RAISE EXCEPTION 'The date cannot be in the future.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_h.usagedate);
    IF NOT EXISTS (SELECT 1 FROM restaurantinternalusageitems WHERE internalusageid = p_internalusageid) THEN
        RAISE EXCEPTION 'Add at least one product before posting.';
    END IF;
    -- guard 2 of 2: a posting still standing (never on a Draft/Reversed record,
    -- but never write a second one).
    IF EXISTS (SELECT 1 FROM restaurantinternalusagestock s
                WHERE s.internalusageid = p_internalusageid AND s.reversalmovementid IS NULL) THEN
        RAISE EXCEPTION 'This record already has stock out. Reverse it first.';
    END IF;

    -- Fill any blank cost from stock history (218: the form's suggestion and the
    -- server's fallback can never disagree), then the line totals.
    UPDATE restaurantinternalusageitems i
       SET entryunitcost = fnrestaurant_internalusage_unitcost(p_farmid, i.itemtype, COALESCE(i.ingredientid, i.menuitemid))
     WHERE i.internalusageid = p_internalusageid AND i.entryunitcost = 0;
    UPDATE restaurantinternalusageitems SET totalcost = ROUND(entryquantity * entryunitcost, 2)
     WHERE internalusageid = p_internalusageid;

    -- Pre-flight: refuse the whole record rather than drive an item negative.
    -- Ingredient rows are locked in id order (the draw locks them again).
    FOR n IN SELECT * FROM fnrestaurant_internalusage_needs(p_internalusageid, p_farmid) LOOP
        IF n.ingredientid IS NULL THEN
            RAISE EXCEPTION '% has no recipe, so there is no stock to take out for it. Add its recipe on the menu, or record the ingredients themselves.',
                n.menuname;
        END IF;
        v_name := NULL;
        SELECT COALESCE(i.currentstock, 0), i.name INTO v_stock, v_name FROM restaurantingredients i
         WHERE i.ingredientid = n.ingredientid AND i.farmid = p_farmid FOR UPDATE;
        IF v_name IS NULL THEN RAISE EXCEPTION 'Pick a stock item or menu item of this restaurant.'; END IF;
        IF n.qty > v_stock THEN
            RAISE EXCEPTION 'Not enough %: % in stock, % needed.', v_name, trim_scale(v_stock), trim_scale(n.qty);
        END IF;
    END LOOP;

    v_ref := COALESCE(v_h.referenceno, 'IU #' || p_internalusageid);
    FOR n IN SELECT * FROM fnrestaurant_internalusage_needs(p_internalusageid, p_farmid) WHERE qty > 0 LOOP
        INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, unitcost, reference, reason, createdby)
        SELECT p_farmid, n.ingredientid, 'InternalUse', -n.qty, i.costperunit, v_ref,
               'Internal use: ' || v_h.category || COALESCE(' - ' || v_h.recipientname, ''), p_postedby
          FROM restaurantingredients i WHERE i.ingredientid = n.ingredientid
        RETURNING stockmovementid INTO v_mid;
        -- The draw BEFORE stock is lowered (fnrestaurant_stock_draw's contract).
        v_cost := fnrestaurant_stock_draw(p_farmid, n.ingredientid, n.qty, 'InternalUse', v_mid, v_h.usagedate,
                                          'Internal use ' || v_ref, p_postedby);
        UPDATE restaurantingredients SET currentstock = currentstock - n.qty, updatedat = NOW()
         WHERE ingredientid = n.ingredientid AND farmid = p_farmid;
        PERFORM fnrestaurant_ingredient_refreshcost(n.ingredientid);
        INSERT INTO restaurantinternalusagestock (internalusageid, farmid, ingredientid, quantity, stockmovementid, deferredcost)
        VALUES (p_internalusageid, p_farmid, n.ingredientid, n.qty, v_mid, COALESCE(v_cost, 0));
    END LOOP;

    SELECT COALESCE(SUM(totalcost), 0) INTO v_total FROM restaurantinternalusageitems WHERE internalusageid = p_internalusageid;
    UPDATE restaurantinternalusage
       SET status = 'Posted', totalcostvalue = v_total, postedby = p_postedby, postedat = NOW(),
           -- A re-post is not a reversed record (219). The reversal survives in
           -- the stock history; the header is current state.
           reversedby = NULL, reversedat = NULL, reversalreason = NULL,
           updatedat = NOW()
     WHERE internalusageid = p_internalusageid AND farmid = p_farmid;
END $$;

-- -----------------------------------------------------------------------------
-- 7. Reverse: the opposite movement, dated today, and every draw handed back to
--    the lot it came from with its deferred cost (a negative-cost draw row, so
--    the P&L takes it back on the day it was reversed). Append-only.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_internalusage_reverse(p_internalusageid INT, p_farmid TEXT, p_reason TEXT DEFAULT NULL,
                                                   p_reversedby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_h restaurantinternalusage%ROWTYPE; v_ref TEXT; v_mid INT; s RECORD; d RECORD;
BEGIN
    SELECT * INTO v_h FROM restaurantinternalusage h
     WHERE h.internalusageid = p_internalusageid AND h.farmid = p_farmid FOR UPDATE;
    IF v_h.internalusageid IS NULL THEN RAISE EXCEPTION 'Internal use record % not found.', p_internalusageid; END IF;
    IF v_h.status = 'Reversed' THEN RETURN; END IF;
    IF v_h.status <> 'Posted' THEN
        RAISE EXCEPTION 'Only a posted record can be reversed. This one is %.', v_h.status;
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to reverse this internal use.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    v_ref := COALESCE(v_h.referenceno, 'IU #' || p_internalusageid);
    FOR s IN SELECT * FROM restaurantinternalusagestock x
              WHERE x.internalusageid = p_internalusageid AND x.reversalmovementid IS NULL
              ORDER BY x.ingredientid FOR UPDATE
    LOOP
        PERFORM 1 FROM restaurantingredients i WHERE i.ingredientid = s.ingredientid FOR UPDATE;
        INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, unitcost, reference, reason, createdby)
        SELECT p_farmid, s.ingredientid, 'InternalUseReversal', s.quantity, i.costperunit, v_ref,
               'Reversal of internal use: ' || btrim(p_reason), p_reversedby
          FROM restaurantingredients i WHERE i.ingredientid = s.ingredientid
        RETURNING stockmovementid INTO v_mid;

        FOR d IN SELECT * FROM restaurantstockdraws x
                  WHERE x.stockmovementid = s.stockmovementid AND x.drawtype = 'InternalUse' ORDER BY x.drawid
        LOOP
            IF d.purchaseid IS NOT NULL THEN
                UPDATE restaurantpurchases
                   SET remainingquantity = remainingquantity + d.quantity,
                       deferredremainingcost = deferredremainingcost + d.deferredcost
                 WHERE purchaseid = d.purchaseid AND status = 'Posted';
                IF NOT FOUND THEN
                    RAISE EXCEPTION 'The purchase this stock came from (#%) is no longer on the books, so the stock cannot go back to it.', d.purchaseid;
                END IF;
            END IF;
            INSERT INTO restaurantstockdraws (farmid, ingredientid, purchaseid, stockmovementid, drawtype, drawdate,
                                              quantity, unitcost, costmode, deferredcost, reference, createdby)
            VALUES (p_farmid, d.ingredientid, d.purchaseid, v_mid, 'InternalUseReversal', CURRENT_DATE,
                    d.quantity, d.unitcost, d.costmode, -d.deferredcost, 'Reversal of internal use ' || v_ref, p_reversedby);
        END LOOP;

        UPDATE restaurantingredients SET currentstock = COALESCE(currentstock, 0) + s.quantity, updatedat = NOW()
         WHERE ingredientid = s.ingredientid;
        PERFORM fnrestaurant_ingredient_refreshcost(s.ingredientid);
        UPDATE restaurantinternalusagestock SET reversalmovementid = v_mid, reversedat = NOW()
         WHERE usagestockid = s.usagestockid;
    END LOOP;

    UPDATE restaurantinternalusage
       SET status = 'Reversed', reversedby = p_reversedby, reversedat = NOW(), reversalreason = btrim(p_reason),
           updatedat = NOW()
     WHERE internalusageid = p_internalusageid AND farmid = p_farmid;
END $$;

-- -----------------------------------------------------------------------------
-- 8. P&L lines, the profit-vs-cash bridge and the deferred history, re-emitted
--    from 329 with only the marked (330) changes; same signatures and columns.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION sprestaurant_report_pnl_lines(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(section TEXT, linekey TEXT, label TEXT, amount NUMERIC, sortorder INT)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE v_sales NUMERIC; v_disc NUMERIC; v_sc NUMERIC; v_fee NUMERIC; v_ref NUMERIC; v_cogs NUMERIC;
        v_int NUMERIC; v_fees NUMERIC; v_var NUMERIC; v_wages NUMERIC; v_slint NUMERIC; v_dep NUMERIC;
        v_purch NUMERIC; v_used NUMERIC; v_waste NUMERIC; v_adj NUMERIC; v_iu NUMERIC;
BEGIN
    SELECT COALESCE(SUM(o.subtotal), 0), COALESCE(SUM(o.discountamount), 0),
           COALESCE(SUM(o.servicechargeamount), 0), COALESCE(SUM(o.deliveryfee), 0)
      INTO v_sales, v_disc, v_sc, v_fee
      FROM restaurantorders o
     WHERE o.farmid = p_farmid AND o.status = 'Completed'
       AND o.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(p.amount), 0) INTO v_ref
      FROM restaurantorderpayments p
      JOIN restaurantorders o ON o.orderid = p.orderid AND o.farmid = p.farmid
     WHERE p.farmid = p_farmid AND p.amount < 0 AND p.status = 'Completed' AND o.status = 'Completed'
       AND p.createdat::DATE BETWEEN p_from AND p_to;

    -- 329: cost of sales is charged once per unit of stock (see the header).
    -- Purchases expensed when purchased: in full on the purchase date; a
    -- reversal takes it back on the day it was reversed.
    SELECT COALESCE(SUM(p.totalcost) FILTER (WHERE p.purchasedate BETWEEN p_from AND p_to), 0)
         - COALESCE(SUM(p.totalcost) FILTER (WHERE p.status = 'Reversed' AND p.reversedat::DATE BETWEEN p_from AND p_to), 0)
      INTO v_purch
      FROM restaurantpurchases p
     WHERE p.farmid = p_farmid AND p.costmode = 'EXPENSE_WHEN_PURCHASED';

    -- Purchases expensed when consumed: the deferred cost each draw moved.
    SELECT COALESCE(SUM(d.deferredcost) FILTER (WHERE d.drawtype = 'OrderDeduction'), 0),
           COALESCE(SUM(d.deferredcost) FILTER (WHERE d.drawtype = 'Waste'), 0),
           COALESCE(SUM(d.deferredcost) FILTER (WHERE d.drawtype NOT IN ('OrderDeduction', 'Waste',
                                                                          'InternalUse', 'InternalUseReversal')), 0),
           -- 330: Internal Use draws, net of reversals (negative rows dated the day reversed).
           COALESCE(SUM(d.deferredcost) FILTER (WHERE d.drawtype IN ('InternalUse', 'InternalUseReversal')), 0)
      INTO v_used, v_waste, v_adj, v_iu
      FROM restaurantstockdraws d
     WHERE d.farmid = p_farmid AND d.drawdate BETWEEN p_from AND p_to;
    v_cogs := v_used;

    SELECT COALESCE(SUM(lp.interestamount), 0), COALESCE(SUM(lp.feeamount), 0)
      INTO v_int, v_fees
      FROM restaurantloanpayments lp
     WHERE lp.farmid = p_farmid AND lp.status = 'Posted' AND lp.paymentdate BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(t.amount), 0) INTO v_var
      FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.sourcetype IN ('ShiftVariance', 'CountVariance', 'CountVarianceReversal')
       AND t.txndate BETWEEN p_from AND p_to;

    -- Staff wages at GROSS pay for runs paid in the period (326).
    SELECT COALESCE(SUM(r.totalgross), 0) INTO v_wages
      FROM restaurantpayrollruns r
     WHERE r.farmid = p_farmid AND r.status = 'Paid' AND r.paydate BETWEEN p_from AND p_to;

    -- Interest repaid on staff loans (326).
    SELECT COALESCE(SUM(sr.interestamount), 0) INTO v_slint
      FROM restaurantstaffloanrepayments sr
     WHERE sr.farmid = p_farmid AND sr.status = 'Posted' AND sr.repaymentdate BETWEEN p_from AND p_to;

    -- 328: depreciation charged in the period, reversals (negative rows) netted.
    SELECT COALESCE(SUM(d.amount), 0) INTO v_dep
      FROM restaurantassetdepreciation d
     WHERE d.farmid = p_farmid AND d.depreciationdate BETWEEN p_from AND p_to;

    RETURN QUERY VALUES
        ('Revenue', 'food_sales', 'Food & beverage sales', ROUND(v_sales, 2), 10),
        ('Revenue', 'discounts', 'Less: discounts & promotions', ROUND(-v_disc, 2), 11),
        ('Revenue', 'refunds', 'Less: partial refunds', ROUND(v_ref, 2), 12),
        ('Revenue', 'service_charge', 'Service charge', ROUND(v_sc, 2), 13),
        ('Revenue', 'delivery_fees', 'Delivery fees', ROUND(v_fee, 2), 14),
        ('CostOfSales', 'recipe_cost', 'Ingredients used (expense when consumed)', ROUND(-v_cogs, 2), 20);

    -- 329
    IF v_purch <> 0 THEN
        RETURN QUERY VALUES ('CostOfSales', 'stock_purchased', 'Stock purchases (expense when purchased)', ROUND(-v_purch, 2), 19);
    END IF;
    IF v_waste <> 0 THEN
        RETURN QUERY VALUES ('CostOfSales', 'stock_waste', 'Stock wasted (expense when consumed)', ROUND(-v_waste, 2), 21);
    END IF;
    IF v_adj <> 0 THEN
        RETURN QUERY VALUES ('CostOfSales', 'stock_adjustments', 'Stock adjustments (expense when consumed)', ROUND(-v_adj, 2), 22);
    END IF;
    -- 330: stock used by the restaurant itself (staff meals, owner use, samples,
    -- donations, tasting). Only deferred stock: stock expensed when purchased
    -- was charged in full on its purchase date and is not charged again.
    IF v_iu <> 0 THEN
        RETURN QUERY VALUES ('CostOfSales', 'stock_internal_use', 'Internal Use (expense when consumed)', ROUND(-v_iu, 2), 23);
    END IF;

    IF v_wages <> 0 THEN
        RETURN QUERY VALUES ('Expenses', 'staff_wages', 'Staff wages (payroll)', ROUND(-v_wages, 2), 29);
    END IF;

    RETURN QUERY
    SELECT 'Expenses'::TEXT, 'expense:' || COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised'),
           COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised'), ROUND(-SUM(e.amount), 2), 30
      FROM restaurantexpenses e
     WHERE e.farmid = p_farmid AND e.expensedate BETWEEN p_from AND p_to
       AND COALESCE(e.status, 'Approved') NOT IN ('Rejected', 'Draft')
     GROUP BY COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised')
     ORDER BY SUM(e.amount) DESC;

    -- 328: Depreciation leads the Depreciation & Financing lines, as in Poultry.
    IF v_dep <> 0 THEN
        RETURN QUERY VALUES ('Other', 'depreciation', 'Depreciation', ROUND(-v_dep, 2), 39);
    END IF;

    RETURN QUERY VALUES
        ('Other', 'loan_interest', 'Loan interest', ROUND(-v_int, 2), 40),
        ('Other', 'loan_fees', 'Loan fees', ROUND(-v_fees, 2), 41),
        ('Other', 'cash_variance', 'Cash over / short', ROUND(v_var, 2), 42);
    IF v_slint <> 0 THEN
        RETURN QUERY VALUES ('Other', 'staff_loan_interest', 'Interest on staff loans', ROUND(v_slint, 2), 43);
    END IF;
END $$;
CREATE OR REPLACE FUNCTION sprestaurant_report_cash_profit_bridge(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(sortorder INT, linekey TEXT, label TEXT, amount NUMERIC, kind TEXT, explanation TEXT)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    v_profit NUMERIC; v_rev NUMERIC; v_cogs NUMERIC; v_exp_pl NUMERIC;
    v_tax NUMERIC; v_tips NUMERIC; v_gift_paid NUMERIC; v_sales_cash NUMERIC;
    v_gift_sold NUMERIC; v_exp_cash NUMERIC; v_loan_int NUMERIC; v_loan_cash NUMERIC;
    v_loan_in NUMERIC; v_owner NUMERIC; v_var NUMERIC; v_net NUMERIC;
    v_sales_timing NUMERIC; v_exp_timing NUMERIC; v_principal NUMERIC;
    v_wages_pl NUMERIC; v_wages_cash NUMERIC; v_slint NUMERIC; v_adv_out NUMERIC; v_adv_in NUMERIC;
    v_dep NUMERIC; v_asset_buy NUMERIC; v_asset_sold NUMERIC;
    v_purch_pl NUMERIC; v_stock_paid NUMERIC; v_sp_exp NUMERIC; v_sp_asset NUMERIC; v_sp_stock NUMERIC;
    v_iu NUMERIC;
BEGIN
    SELECT s.net_profit, s.revenue INTO v_profit, v_rev
      FROM sprestaurant_report_pnl_summary(p_farmid, p_from, p_to) s;

    -- 329: stock USED is profit without cash; stock PURCHASED (expense when
    -- purchased) is profit whose cash moves when it is paid.
    SELECT COALESCE(-SUM(l.amount) FILTER (WHERE l.linekey IN ('recipe_cost', 'stock_waste', 'stock_adjustments')), 0),
           COALESCE(-SUM(l.amount) FILTER (WHERE l.linekey = 'stock_purchased'), 0),
           -- 330: stock used internally is profit without cash, like stock used.
           COALESCE(-SUM(l.amount) FILTER (WHERE l.linekey = 'stock_internal_use'), 0)
      INTO v_cogs, v_purch_pl, v_iu
      FROM sprestaurant_report_pnl_lines(p_farmid, p_from, p_to) l;

    -- 329: each supplier payment (and its reversal) is split by what it settled:
    -- an expense joins expense cash, a capital investment joins capital
    -- investments, a purchase joins stock paid for. Allocations always add up to
    -- the payment, so the three parts add up to the ledger row exactly.
    SELECT COALESCE(SUM(sp.exp), 0), COALESCE(SUM(sp.asset), 0), COALESCE(SUM(t.amount - sp.exp - sp.asset), 0)
      INTO v_sp_exp, v_sp_asset, v_sp_stock
      FROM restaurantcashtransactions t
     CROSS JOIN LATERAL (
            SELECT ROUND(t.amount * COALESCE(SUM(a.amountapplied) FILTER (WHERE a.documenttype = 'Expense'), 0)
                         / NULLIF(p.totalamount, 0), 2) AS exp,
                   ROUND(t.amount * COALESCE(SUM(a.amountapplied) FILTER (WHERE a.documenttype = 'AssetCost'), 0)
                         / NULLIF(p.totalamount, 0), 2) AS asset
              FROM restaurantsupplierpayments p
              LEFT JOIN supplierpaymentallocation a
                     ON a.farmid = p.farmid AND a.module = 'restaurant' AND a.paymentid = p.supplierpaymentid
             WHERE p.supplierpaymentid = t.sourceid
             GROUP BY p.totalamount) sp
     WHERE t.farmid = p_farmid AND t.sourcetype IN ('SupplierPayment', 'SupplierPaymentReversal')
       AND t.txndate BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(t.amount), 0) INTO v_stock_paid FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.sourcetype IN ('StockPurchase', 'StockPurchaseReversal')
       AND t.txndate BETWEEN p_from AND p_to;
    v_stock_paid := v_stock_paid + v_sp_stock;

    -- Staff wages (326) are bridged on their own line, not as expense timing.
    SELECT COALESCE(-SUM(l.amount) FILTER (WHERE l.section = 'Expenses' AND l.linekey <> 'staff_wages'), 0),
           COALESCE(-SUM(l.amount) FILTER (WHERE l.linekey IN ('loan_interest', 'loan_fees')), 0),
           COALESCE(SUM(l.amount) FILTER (WHERE l.linekey = 'cash_variance'), 0)
      INTO v_exp_pl, v_loan_int, v_var
      FROM sprestaurant_report_pnl_lines(p_farmid, p_from, p_to) l;

    SELECT COALESCE(-SUM(l.amount) FILTER (WHERE l.linekey = 'staff_wages'), 0),
           COALESCE(SUM(l.amount) FILTER (WHERE l.linekey = 'staff_loan_interest'), 0),
           -- 328: depreciation is in profit and moved no cash.
           COALESCE(-SUM(l.amount) FILTER (WHERE l.linekey = 'depreciation'), 0)
      INTO v_wages_pl, v_slint, v_dep
      FROM sprestaurant_report_pnl_lines(p_farmid, p_from, p_to) l;

    SELECT COALESCE(-SUM(t.amount) FILTER (WHERE t.sourcetype = 'Payroll'), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('EmployeeLoanDisbursement', 'EmployeeLoanReversal')), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('EmployeeLoanRepayment', 'EmployeeLoanRepaymentReversal')), 0),
           -- 328: capital purchases (net of corrections and reversals) and disposal proceeds.
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('AssetPurchase', 'AssetPurchaseReversal')), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype = 'AssetDisposal'), 0)
      INTO v_wages_cash, v_adv_out, v_adv_in, v_asset_buy, v_asset_sold
      FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.txndate BETWEEN p_from AND p_to;
    v_asset_buy := v_asset_buy + v_sp_asset;   -- 329

    SELECT COALESCE(SUM(o.taxamount), 0) INTO v_tax FROM restaurantorders o
     WHERE o.farmid = p_farmid AND o.status = 'Completed' AND o.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(t.amount), 0) INTO v_sales_cash FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.sourcetype IN ('OrderPayment', 'OrderRefund')
       AND t.txndate BETWEEN p_from AND p_to;
    SELECT COALESCE(SUM(p.tipamount), 0) INTO v_tips FROM restaurantorderpayments p
     WHERE p.farmid = p_farmid AND p.status = 'Completed' AND p.amount > 0
       AND p.createdat::DATE BETWEEN p_from AND p_to;
    SELECT COALESCE(SUM(p.amount), 0) INTO v_gift_paid FROM restaurantorderpayments p
     WHERE p.farmid = p_farmid AND p.status = 'Completed' AND p.amount > 0
       AND NOT fnrestaurant_is_cash_method(p.paymentmethod)
       AND p.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('GiftCardSale', 'GiftCardReload')), 0),
           COALESCE(-SUM(t.amount) FILTER (WHERE t.sourcetype IN ('Expense', 'ExpenseReversal')), 0) - v_sp_exp,
           COALESCE(-SUM(t.amount) FILTER (WHERE t.sourcetype IN ('LoanRepayment', 'LoanRepaymentReversal')), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('LoanReceived', 'LoanReceivedReversal')), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype LIKE 'Owner%'), 0)
      INTO v_gift_sold, v_exp_cash, v_loan_cash, v_loan_in, v_owner
      FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.txndate BETWEEN p_from AND p_to;

    SELECT s.netcashflow INTO v_net
      FROM sprestaurantcashflow_summary(p_farmid, p_from::TIMESTAMP, (p_to + 1)::TIMESTAMP - INTERVAL '1 microsecond') s;

    v_sales_timing := v_sales_cash - (v_rev + v_tax + v_tips - v_gift_paid);
    v_exp_timing := v_exp_pl - v_exp_cash;
    v_principal := v_loan_cash - v_loan_int;

    RETURN QUERY VALUES
        (10, 'net_profit', 'Net profit (from the P&L)', ROUND(v_profit, 2), 'start',
         'Revenue less cost of goods, expenses, loan costs and cash over/short.'),
        (20, 'cogs', 'Add back: stock used (expense when consumed)', ROUND(v_cogs, 2), 'adjust',
         'The P&L charges the cost of stock as it is used; its cash left when the stock was bought or the supplier was paid.'),
        (21, 'internal_use', 'Add back: stock used internally (Internal Use)', ROUND(v_iu, 2), 'adjust',
         'Stock given to staff, the owner, guests or charity is a cost in profit; its cash left when the stock was bought or the supplier was paid.'),
        (22, 'stock_purchased', 'Add back: stock purchases charged to profit', ROUND(v_purch_pl, 2), 'adjust',
         'Stock expensed when purchased is charged in full on the purchase date, paid or not.'),
        (24, 'stock_paid', 'Less: paid for stock (at purchase and to suppliers)', ROUND(v_stock_paid, 2), 'adjust',
         'Cash that left for stock purchases: the amount paid when recorded plus supplier payments applied to purchases.'),
        (30, 'tax', 'Add: tax collected from customers', ROUND(v_tax, 2), 'adjust',
         'Customers paid it, but it is owed to the tax office, so it is not revenue.'),
        (40, 'tips', 'Add: tips received', ROUND(v_tips, 2), 'adjust',
         'Tips come into the till but belong to staff, so they are not revenue.'),
        (50, 'gift_paid', 'Less: sales paid with gift cards', ROUND(-v_gift_paid, 2), 'adjust',
         'Revenue with no cash today — the cash came in when the card was sold.'),
        (60, 'gift_sold', 'Add: gift cards sold and reloaded', ROUND(v_gift_sold, 2), 'adjust',
         'Cash received for food not yet served. It becomes revenue when the card is used.'),
        (70, 'sales_timing', 'Sales timing differences', ROUND(v_sales_timing, 2), 'adjust',
         'Payments taken this period for orders counted in another period (or the reverse), and full refunds.'),
        (80, 'expense_timing', 'Expense timing differences', ROUND(v_exp_timing, 2), 'adjust',
         'Expenses counted in the P&L but paid in another period, or paid without a cash movement.'),
        (90, 'loan_in', 'Add: loans received', ROUND(v_loan_in, 2), 'adjust',
         'Borrowed money is cash in but not income.'),
        (100, 'loan_principal', 'Less: loan principal repaid', ROUND(-v_principal, 2), 'adjust',
         'Paying back what was borrowed is cash out but not a cost. Interest and fees are already in the P&L.'),
        (110, 'owner', 'Add: owner money (contributions less drawings)', ROUND(v_owner, 2), 'adjust',
         'Owner money moves cash but is never income or expense.'),
        (120, 'wages_withheld', 'Add back: wages not paid out in cash', ROUND(v_wages_pl - v_wages_cash, 2), 'adjust',
         'The P&L charges gross wages; only net pay left the till. The rest repaid staff loans or was withheld.'),
        (130, 'staff_advances_out', 'Less: staff advances paid out', ROUND(v_adv_out, 2), 'adjust',
         'Money lent to staff is cash out but not a cost: they owe it back.'),
        (140, 'staff_advances_in', 'Add: staff advances repaid in cash', ROUND(v_adv_in, 2), 'adjust',
         'Staff paying back an advance is cash in but not income.'),
        (150, 'staff_loan_interest', 'Less: interest on staff loans (already in profit)', ROUND(-v_slint, 2), 'adjust',
         'Interest is counted in net profit; its cash is inside the repayment and wage lines above.'),
        (160, 'depreciation', 'Add back: depreciation', ROUND(v_dep, 2), 'adjust',
         'Depreciation is a real cost of the period that moves no money.'),
        (170, 'capital_investments', 'Less: capital investments paid for', ROUND(v_asset_buy, 2), 'adjust',
         'Buying equipment, furniture or a vehicle is cash out but not charged against profit — its cost reaches the P&L through depreciation.'),
        (180, 'asset_disposals', 'Add: proceeds from assets disposed of', ROUND(v_asset_sold, 2), 'adjust',
         'Money received for selling an asset is cash in but not sales revenue.'),
        (200, 'net_cash', 'Net cash flow (from Cash Flow)', ROUND(v_net, 2), 'result',
         'Money in less money out across every account, transfers excluded.'),
        (210, 'check', 'Unexplained', ROUND(v_net - (v_profit + v_cogs + v_tax + v_tips - v_gift_paid + v_gift_sold
                                                   + v_sales_timing + v_exp_timing + v_loan_in - v_principal + v_owner
                                                   + (v_wages_pl - v_wages_cash) + v_adv_out + v_adv_in - v_slint
                                                   + v_dep + v_asset_buy + v_asset_sold
                                                   + v_purch_pl + v_stock_paid + v_iu), 2),
         'check', 'Should be zero. Anything else is a ledger row this bridge does not classify yet.');
END $$;

-- What moved one purchase's cost into Profit & Loss.
CREATE OR REPLACE FUNCTION sprestaurant_deferredpurchase_history(p_farmid TEXT, p_purchaseid INT)
RETURNS TABLE(drawid INT, useddate DATE, sourcetype TEXT, sourcelabel TEXT, quantitydrawn NUMERIC, unit TEXT,
              unitcostatdraw NUMERIC, operationalcost NUMERIC, recognizedcost NUMERIC, recognitionoutcome TEXT,
              isreversed BOOLEAN)
LANGUAGE sql STABLE AS $$
    SELECT d.drawid, d.drawdate,
           CASE d.drawtype WHEN 'OrderDeduction' THEN 'Sale' WHEN 'Waste' THEN 'Waste'
                           WHEN 'StockTake' THEN 'Stock take' WHEN 'Shortfall' THEN 'Used before delivery'
                           WHEN 'InternalUse' THEN 'Internal use'
                           ELSE 'Adjustment' END::TEXT,
           COALESCE(d.reference, d.drawtype)::TEXT,
           d.quantity, p.unit, d.unitcost, ROUND(d.quantity * d.unitcost, 2), d.deferredcost,
           CASE WHEN d.costmode = 'EXPENSE_WHEN_CONSUMED' THEN 'Expensed now' ELSE 'Already expensed at purchase' END::TEXT,
           -- 330: an internal use that was reversed shows struck through and out of
           -- the totals (Poultry's isReversed); its hand-back row is not listed.
           (d.drawtype = 'InternalUse' AND EXISTS (
                SELECT 1 FROM restaurantinternalusagestock s
                 WHERE s.stockmovementid = d.stockmovementid AND s.reversalmovementid IS NOT NULL))
      FROM restaurantstockdraws d
      JOIN restaurantpurchases p ON p.purchaseid = d.purchaseid
     WHERE d.farmid = p_farmid AND d.purchaseid = p_purchaseid AND d.drawtype <> 'InternalUseReversal'
     ORDER BY d.drawdate, d.drawid;
$$;

-- -----------------------------------------------------------------------------
-- 9. Verification (read-only)
-- -----------------------------------------------------------------------------
DO $$
DECLARE v_missing TEXT;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
      FROM unnest(ARRAY[
            'fnrestaurant_internalusage_categoryok', 'fnrestaurant_internalusage_unitcost',
            'sprestaurant_internalusage_items', 'sprestaurant_internalusage_getall',
            'sprestaurant_internalusage_getbyid', 'sprestaurant_internalusage_replaceitems',
            'sprestaurant_internalusage_insert', 'sprestaurant_internalusage_update',
            'sprestaurant_internalusage_delete', 'fnrestaurant_internalusage_needs',
            'sprestaurant_internalusage_post', 'sprestaurant_internalusage_reverse',
            'sprestaurant_report_pnl_lines', 'sprestaurant_report_cash_profit_bridge',
            'sprestaurant_deferredpurchase_history']) f
     WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND p.proname = f);
    IF v_missing IS NOT NULL THEN RAISE EXCEPTION '330 verification failed, missing: %', v_missing; END IF;
    IF position('stock_internal_use' in pg_get_functiondef('sprestaurant_report_cash_profit_bridge'::regproc)) = 0 THEN
        RAISE EXCEPTION '330 verification failed: the bridge does not classify Internal Use';
    END IF;
END $$;

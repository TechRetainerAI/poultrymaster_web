-- =============================================================================
-- 329_RestaurantSuppliersPayablesDeferredCost.postgres.sql
--
-- Purpose
-- -------
-- The supplier side of the standalone Restaurant, copied from Poultry:
--
--   * Purchases that CARRY A COST. A restaurant buys rice, tomatoes, chicken,
--     fish, drinks, cooking gas, takeaway boxes, poly bags, plates, cups,
--     cleaning supplies. Each purchase (sprestaurant_purchase_create) is one
--     ingredient/supply, a quantity and a total cost from a supplier. It adds
--     the stock, becomes a FIFO cost LOT (Poultry keeps its purchases as lots and
--     draws them FIFO -- 264's consumption engine, default method), refreshes the
--     ingredient's cost per unit from what is on hand, moves only the amount PAID
--     NOW out of a cash account ('StockPurchase', fnrestaurant_post) and leaves
--     the rest OWED to the supplier.
--     "Adjust Stock -> Purchase / Received" no longer exists: it raised stock with
--     no cost, no money and no supplier.
--
--   * Supplier Balances and Supplier Payments with the SAME contract as Poultry
--     (224 / 238 / 262): balances, summary, open documents, record (with a jsonb
--     allocation list that must add up to the payment), reverse, history,
--     allocations and a statement. The payables are:
--       'Purchase'  restaurantpurchases (unpaid part)
--       'Expense'   restaurantexpenses linked to a supplier (unpaid part)
--       'AssetCost' capital investment costs (the 328 seam)
--     Allocations are written to the SHARED supplierpaymentallocation table
--     (222) with module = 'restaurant'. That table has no FK and no CHECK on
--     module, and its unique key starts with module, so restaurant rows cannot
--     collide with poultry/water/generic ones; every poultry/water/generic reader
--     filters on its own module value, so nothing they read changes.
--     A payment posts ONE ledger row ('SupplierPayment', -amount) from the chosen
--     account; a reversal posts the opposite row dated today, with a reason. A
--     document's own amountpaid is what left at entry and is never touched by a
--     payment: balance = amount - amountpaid - allocations. So no cash is ever
--     counted twice.
--
--   * Expenses gain an optional supplier and a payment status. restaurantexpenses
--     is read with SELECT e.* (sprestaurant_expense_list) and by ordinal
--     (RestaurantExtendedServices.ListExpensesAsync), so NO column is added to
--     it: the link lives in restaurantexpensepayables (one row per expense that
--     names a supplier or was not paid in full). Existing expenses whose free-text
--     supplier matches exactly one supplier are linked, as paid.
--
--   * Deferred inventory cost (Poultry 261-268, 288, 289). Each ingredient
--     CATEGORY is "Expense when purchased" (default) or "Expense when consumed".
--     The choice is resolved once, as of the purchase, and stamped on the
--     purchase (costmode). A purchase expensed when purchased is charged to
--     Profit & Loss in full on its purchase date. A purchase expensed when
--     consumed is held as stock value and each draw on its lot (recipe deduction
--     on a sale, waste, a stock-out adjustment, a stock-take shortfall) moves its
--     pro-rata share into Profit & Loss, non-cash.
--
-- THE P&L MODEL (why the old recipe-cost line changes)
-- Before 329 the P&L charged the THEORETICAL recipe cost of everything sold
-- (at today's cost per unit) AND every expense in full, so food bought through
-- Expenses was charged twice. Now every unit of stock is charged exactly once:
--   Stock purchases (expense when purchased)  purchases stamped purchased, in
--                                              full, on the purchase date
--   Ingredients used (expense when consumed)  deferred cost drawn by sales
--   Stock wasted / Stock adjustments          deferred cost drawn by waste / outs
-- Stock that was never bought through a purchase (opening stock, legacy stock,
-- adjustments in) carries no deferred cost: the restaurant expensed it however
-- it paid for it (usually an expense), so using it charges nothing again. The
-- linekey 'recipe_cost' is kept (the P&L page and reports read it).
--
-- PROFIT vs CASH: new bridge lines keep "Unexplained" at 0 -- stock used is
-- profit without cash; stock purchased and paid for is cash in the period it
-- was paid; supplier payments are split by what they settled (a purchase, an
-- expense or a capital investment) and join the matching line.
--
-- Re-emits, from 328 (every earlier arm kept): sprestaurantcashflow_detail,
-- sprestaurant_report_pnl_lines, sprestaurant_report_cash_profit_bridge.
-- From 323: sprestaurant_expense_record (+3 optional params), _expense_insert,
-- _expense_delete (supplier-payment guard), sprestaurant_recipe_deduct_order.
-- From 222: sprestaurant_ingredient_adjust_stock (sign fix + draws),
-- sprestaurant_wastelog_insert, sprestaurant_stocktake_complete,
-- sprestaurant_ingredient_delete. From 242: sprestaurant_supplier_delete.
-- From 328 (supplier-payment guards / allocations): sprestaurant_capitalasset_
-- reverse, _cost_reverse, _correctoriginalcost, _payables, _list, _summary,
-- _costs. Re-run order: 323 -> 324 -> 326 -> 328 -> 329.
--
-- Column additions to existing tables: NONE. Re-runnable: tables are IF NOT
-- EXISTS, the backfill skips linked rows, every function is dropped by name
-- (all overloads) or replaced with an identical signature.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Drop every function this migration (re)defines with a new or changed
--    signature, all overloads.
-- -----------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
            'fnrestaurant_costmode', 'sprestaurant_costmode_list', 'sprestaurant_costmode_set',
            'fnrestaurant_ingredient_refreshcost', 'fnrestaurant_stock_draw',
            'sprestaurant_purchase_create', 'sprestaurant_purchase_reverse', 'sprestaurant_purchase_list',
            'fnrestaurant_allocated', 'fnrestaurant_payables',
            'sprestaurant_supplierbalances', 'sprestaurant_supplierbalancesummary',
            'sprestaurant_supplieropenpurchases', 'sprestaurant_supplierpayment_record',
            'sprestaurant_supplierpayment_reverse', 'sprestaurant_supplierpayment_history',
            'sprestaurant_supplierpayment_allocations', 'sprestaurant_supplierstatement',
            'sprestaurant_expense_record', 'sprestaurant_expense_insert', 'sprestaurant_expense_delete',
            'sprestaurant_expense_payments',
            'sprestaurant_recipe_deduct_order', 'sprestaurant_ingredient_adjust_stock',
            'sprestaurant_wastelog_insert', 'sprestaurant_stocktake_complete',
            'sprestaurant_ingredient_delete', 'sprestaurant_supplier_delete',
            'fnrestaurant_deferredpurchase_rows', 'sprestaurant_deferredpurchase_getall',
            'sprestaurant_deferredpurchase_summary', 'sprestaurant_deferredpurchase_history')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------

-- Per restaurant, per ingredient category. No row = Expense when purchased.
CREATE TABLE IF NOT EXISTS restaurantingredientcostmodes (
    farmid     TEXT NOT NULL,
    category   TEXT NOT NULL,
    costmode   TEXT NOT NULL DEFAULT 'EXPENSE_WHEN_PURCHASED',
    updatedby  TEXT,
    updatedat  TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_restaurantingredientcostmodes_mode
        CHECK (costmode IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED'))
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantingredientcostmodes
    ON restaurantingredientcostmodes (farmid, lower(category));

-- The purchase document AND its FIFO stock lot (Poultry keeps both on
-- poultryrawmaterialpurchases the same way).
CREATE TABLE IF NOT EXISTS restaurantpurchases (
    purchaseid            SERIAL PRIMARY KEY,
    farmid                TEXT NOT NULL,
    ingredientid          INT NOT NULL REFERENCES restaurantingredients(ingredientid),
    purchasedate          DATE NOT NULL,
    supplierid            INT REFERENCES restaurantsuppliers(restaurantsupplierid),
    suppliername          TEXT,
    quantity              NUMERIC(14,4) NOT NULL,
    unit                  TEXT,
    unitcost              NUMERIC(14,4) NOT NULL,
    totalcost             NUMERIC(14,2) NOT NULL,
    paymentmethod         TEXT,
    -- Cash that left when the purchase was recorded. Supplier payments never
    -- change it: they are allocations.
    amountpaid            NUMERIC(14,2) NOT NULL DEFAULT 0,
    cashaccountid         INT REFERENCES restaurantcashaccounts(cashaccountid),
    duedate               DATE,
    -- EXPENSE_WHEN_PURCHASED | EXPENSE_WHEN_CONSUMED, resolved once, never recomputed.
    costmode              TEXT NOT NULL DEFAULT 'EXPENSE_WHEN_PURCHASED',
    -- The lot.
    remainingquantity     NUMERIC(14,4) NOT NULL,
    deferredtotalcost     NUMERIC(14,2) NOT NULL DEFAULT 0,
    deferredremainingcost NUMERIC(14,2) NOT NULL DEFAULT 0,
    notes                 TEXT,
    status                TEXT NOT NULL DEFAULT 'Posted',
    createdby             TEXT,
    createdat             TIMESTAMP NOT NULL DEFAULT NOW(),
    reversedby            TEXT,
    reversedat            TIMESTAMP,
    reversalreason        TEXT,
    CONSTRAINT ck_restaurantpurchases_qty CHECK (quantity > 0),
    CONSTRAINT ck_restaurantpurchases_cost CHECK (totalcost >= 0),
    CONSTRAINT ck_restaurantpurchases_paid CHECK (amountpaid >= 0 AND amountpaid <= totalcost),
    CONSTRAINT ck_restaurantpurchases_mode CHECK (costmode IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED')),
    CONSTRAINT ck_restaurantpurchases_lot CHECK (remainingquantity >= 0 AND remainingquantity <= quantity
                                                 AND deferredremainingcost >= 0
                                                 AND deferredremainingcost <= deferredtotalcost),
    CONSTRAINT ck_restaurantpurchases_status CHECK (status IN ('Posted', 'Reversed'))
);
CREATE INDEX IF NOT EXISTS ix_restaurantpurchases_farm ON restaurantpurchases (farmid, purchasedate);
CREATE INDEX IF NOT EXISTS ix_restaurantpurchases_lots
    ON restaurantpurchases (ingredientid, purchasedate, purchaseid) WHERE status = 'Posted' AND remainingquantity > 0;
CREATE INDEX IF NOT EXISTS ix_restaurantpurchases_supplier ON restaurantpurchases (farmid, supplierid);

-- Every draw on stock: which lot (or none: stock that never came through a
-- purchase), how much, at what cost, and how much deferred cost it moved into
-- Profit & Loss. Append-only.
CREATE TABLE IF NOT EXISTS restaurantstockdraws (
    drawid          SERIAL PRIMARY KEY,
    farmid          TEXT NOT NULL,
    ingredientid    INT NOT NULL REFERENCES restaurantingredients(ingredientid) ON DELETE CASCADE,
    purchaseid      INT REFERENCES restaurantpurchases(purchaseid),
    stockmovementid INT REFERENCES restaurantstockmovements(stockmovementid) ON DELETE SET NULL,
    -- OrderDeduction | Waste | Adjustment | StockTake | Shortfall
    drawtype        TEXT NOT NULL,
    drawdate        DATE NOT NULL,
    quantity        NUMERIC(14,4) NOT NULL CHECK (quantity > 0),
    unitcost        NUMERIC(14,4) NOT NULL DEFAULT 0,
    -- The lot's costmode, or 'UNLOTTED'.
    costmode        TEXT NOT NULL,
    deferredcost    NUMERIC(14,2) NOT NULL DEFAULT 0,
    reference       TEXT,
    createdby       TEXT,
    createdat       TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantstockdraws_farm ON restaurantstockdraws (farmid, drawdate);
CREATE INDEX IF NOT EXISTS ix_restaurantstockdraws_purchase ON restaurantstockdraws (purchaseid);

-- The supplier payment header (Poultry 224's poultrysupplierpayments).
CREATE TABLE IF NOT EXISTS restaurantsupplierpayments (
    supplierpaymentid SERIAL PRIMARY KEY,
    farmid            TEXT NOT NULL,
    supplierid        INT NOT NULL REFERENCES restaurantsuppliers(restaurantsupplierid),
    paymentdate       TIMESTAMP NOT NULL,
    totalamount       NUMERIC(14,2) NOT NULL CHECK (totalamount > 0),
    paymentmethod     TEXT,
    cashaccountid     INT NOT NULL REFERENCES restaurantcashaccounts(cashaccountid),
    referenceno       TEXT,
    notes             TEXT,
    sourcetype        TEXT NOT NULL DEFAULT 'SupplierBalances',
    status            TEXT NOT NULL DEFAULT 'Posted',
    createdby         TEXT,
    createdat         TIMESTAMP NOT NULL DEFAULT NOW(),
    reversedby        TEXT,
    reversedat        TIMESTAMP,
    reversalreason    TEXT,
    CONSTRAINT ck_restaurantsupplierpayments_status CHECK (status IN ('Posted', 'Reversed'))
);
CREATE INDEX IF NOT EXISTS ix_restaurantsupplierpayments_farm ON restaurantsupplierpayments (farmid, paymentdate);
CREATE INDEX IF NOT EXISTS ix_restaurantsupplierpayments_supplier
    ON restaurantsupplierpayments (farmid, supplierid) WHERE status = 'Posted';

-- The supplier link and payment state of an expense (no column is added to
-- restaurantexpenses, see the header).
CREATE TABLE IF NOT EXISTS restaurantexpensepayables (
    expenseid   INT PRIMARY KEY REFERENCES restaurantexpenses(expenseid) ON DELETE CASCADE,
    farmid      TEXT NOT NULL,
    supplierid  INT REFERENCES restaurantsuppliers(restaurantsupplierid),
    -- Cash that left when the expense was recorded.
    amountpaid  NUMERIC(14,2) NOT NULL,
    duedate     DATE,
    createdat   TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantexpensepayables_supplier ON restaurantexpensepayables (farmid, supplierid);

-- One row of a supplier payment's allocation list, parsed from the jsonb.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                    WHERE n.nspname = 'public' AND t.typname = 'restaurant_alloc_row') THEN
        CREATE TYPE restaurant_alloc_row AS (documenttype TEXT, documentid INT, amount NUMERIC(14,2));
    END IF;
END $$;

-- Backfill: an existing expense whose free-text supplier names exactly one
-- supplier of the same restaurant is linked to it, as paid in full (every
-- pre-329 expense was paid when recorded).
INSERT INTO restaurantexpensepayables (expenseid, farmid, supplierid, amountpaid)
SELECT e.expenseid, e.farmid, s.restaurantsupplierid, e.amount
  FROM restaurantexpenses e
  JOIN LATERAL (
        SELECT MIN(x.restaurantsupplierid) AS restaurantsupplierid, COUNT(*) AS n
          FROM restaurantsuppliers x
         WHERE x.farmid = e.farmid AND lower(btrim(x.name)) = lower(btrim(e.suppliername))) s ON s.n = 1
 WHERE NULLIF(btrim(e.suppliername), '') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM restaurantexpensepayables p WHERE p.expenseid = e.expenseid);

-- -----------------------------------------------------------------------------
-- 2. Cost recognition per ingredient category (Poultry 261's resolver, keyed
--    on the restaurant's ingredient category instead of a farm-wide group).
-- -----------------------------------------------------------------------------
CREATE FUNCTION fnrestaurant_costmode(p_farmid TEXT, p_category TEXT)
RETURNS TEXT LANGUAGE sql STABLE AS $$
    SELECT COALESCE((SELECT m.costmode FROM restaurantingredientcostmodes m
                      WHERE m.farmid = p_farmid AND lower(m.category) = lower(btrim(p_category))),
                    'EXPENSE_WHEN_PURCHASED');
$$;

-- Every category in use (ingredients) or configured, with its current choice.
CREATE FUNCTION sprestaurant_costmode_list(p_farmid TEXT)
RETURNS TABLE(category TEXT, costmode TEXT, ingredientcount INT, isconfigured BOOLEAN,
              updatedby TEXT, updatedat TIMESTAMP)
LANGUAGE sql STABLE AS $$
    WITH cats AS (
        SELECT btrim(i.category) AS category FROM restaurantingredients i
         WHERE i.farmid = p_farmid AND NULLIF(btrim(i.category), '') IS NOT NULL
        UNION
        SELECT m.category FROM restaurantingredientcostmodes m WHERE m.farmid = p_farmid
    ), one AS (
        SELECT DISTINCT ON (lower(c.category)) c.category FROM cats c ORDER BY lower(c.category), c.category
    )
    SELECT o.category, fnrestaurant_costmode(p_farmid, o.category),
           (SELECT COUNT(*)::INT FROM restaurantingredients i
             WHERE i.farmid = p_farmid AND lower(btrim(i.category)) = lower(o.category)),
           EXISTS (SELECT 1 FROM restaurantingredientcostmodes m
                    WHERE m.farmid = p_farmid AND lower(m.category) = lower(o.category)),
           m.updatedby, m.updatedat
      FROM one o
      LEFT JOIN restaurantingredientcostmodes m ON m.farmid = p_farmid AND lower(m.category) = lower(o.category)
     ORDER BY o.category;
$$;

-- Applies to purchases recorded from now on. Purchases already recorded keep
-- the choice stamped on them (Poultry: resolved once, never recomputed).
CREATE FUNCTION sprestaurant_costmode_set(p_farmid TEXT, p_category TEXT, p_costmode TEXT, p_updatedby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF COALESCE(btrim(p_category), '') = '' THEN RAISE EXCEPTION 'Choose a category.'; END IF;
    IF p_costmode NOT IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED') THEN
        RAISE EXCEPTION 'Choose Expense when purchased or Expense when consumed.';
    END IF;
    INSERT INTO restaurantingredientcostmodes (farmid, category, costmode, updatedby, updatedat)
    VALUES (p_farmid, btrim(p_category), p_costmode, p_updatedby, NOW())
    ON CONFLICT (farmid, lower(category))
    DO UPDATE SET costmode = EXCLUDED.costmode, updatedby = EXCLUDED.updatedby, updatedat = NOW();
END $$;

-- What supplier payments have settled on one document (Posted allocations).
CREATE FUNCTION fnrestaurant_allocated(p_farmid TEXT, p_documenttype TEXT, p_documentid INT)
RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(a.amountapplied), 0)::NUMERIC(14,2)
      FROM supplierpaymentallocation a
     WHERE a.farmid = p_farmid AND a.module = 'restaurant' AND a.status = 'Posted'
       AND a.documenttype = p_documenttype AND a.documentid = p_documentid;
$$;

-- -----------------------------------------------------------------------------
-- 3. Stock cost: the FIFO engine
-- -----------------------------------------------------------------------------

-- Cost per unit = the value of what is on hand / the quantity on hand: lots at
-- their own cost, stock that never came through a purchase at the old figure.
-- With nothing on hand the last purchase's unit cost stands.
CREATE FUNCTION fnrestaurant_ingredient_refreshcost(p_ingredientid INT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_stock NUMERIC; v_old NUMERIC; v_lq NUMERIC; v_lv NUMERIC; v_un NUMERIC; v_last NUMERIC;
BEGIN
    SELECT COALESCE(i.currentstock, 0), COALESCE(i.costperunit, 0) INTO v_stock, v_old
      FROM restaurantingredients i WHERE i.ingredientid = p_ingredientid;
    SELECT COALESCE(SUM(p.remainingquantity), 0), COALESCE(SUM(p.remainingquantity * p.unitcost), 0)
      INTO v_lq, v_lv
      FROM restaurantpurchases p
     WHERE p.ingredientid = p_ingredientid AND p.status = 'Posted' AND p.remainingquantity > 0;
    v_un := GREATEST(v_stock - v_lq, 0);
    IF v_lq + v_un > 0 THEN
        UPDATE restaurantingredients SET costperunit = ROUND((v_lv + v_un * v_old) / (v_lq + v_un), 4), updatedat = NOW()
         WHERE ingredientid = p_ingredientid;
    ELSE
        SELECT p.unitcost INTO v_last FROM restaurantpurchases p
         WHERE p.ingredientid = p_ingredientid AND p.status = 'Posted'
         ORDER BY p.purchasedate DESC, p.purchaseid DESC LIMIT 1;
        IF v_last IS NOT NULL THEN
            UPDATE restaurantingredients SET costperunit = v_last, updatedat = NOW() WHERE ingredientid = p_ingredientid;
        END IF;
    END IF;
END $$;

-- Draws p_qty of an ingredient. MUST be called BEFORE currentstock is lowered.
-- Stock that did not come through a purchase is drawn first (it is the oldest,
-- and it carries no deferred cost), then the purchase lots oldest first. Each
-- lot gives up its deferred cost pro rata (the last unit takes what is left),
-- exactly as Poultry 264's consumebatches. Returns the deferred cost moved into
-- Profit & Loss.
CREATE FUNCTION fnrestaurant_stock_draw(p_farmid TEXT, p_ingredientid INT, p_qty NUMERIC, p_drawtype TEXT,
                                        p_movementid INT, p_date DATE, p_reference TEXT, p_createdby TEXT)
RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE
    v_left NUMERIC := COALESCE(p_qty, 0); v_stock NUMERIC; v_cpu NUMERIC; v_lots NUMERIC; v_un NUMERIC;
    v_take NUMERIC; v_share NUMERIC(14,2); v_total NUMERIC(14,2) := 0; l RECORD;
BEGIN
    IF v_left <= 0 THEN RETURN 0; END IF;
    SELECT COALESCE(i.currentstock, 0), COALESCE(i.costperunit, 0) INTO v_stock, v_cpu
      FROM restaurantingredients i WHERE i.ingredientid = p_ingredientid AND i.farmid = p_farmid
       FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ingredient not found for this restaurant.'; END IF;
    SELECT COALESCE(SUM(p.remainingquantity), 0) INTO v_lots FROM restaurantpurchases p
     WHERE p.ingredientid = p_ingredientid AND p.status = 'Posted' AND p.remainingquantity > 0;

    v_un := LEAST(GREATEST(v_stock - v_lots, 0), v_left);
    IF v_un > 0 THEN
        INSERT INTO restaurantstockdraws (farmid, ingredientid, purchaseid, stockmovementid, drawtype, drawdate,
                                          quantity, unitcost, costmode, deferredcost, reference, createdby)
        VALUES (p_farmid, p_ingredientid, NULL, p_movementid, p_drawtype, p_date, v_un, v_cpu, 'UNLOTTED', 0,
                p_reference, p_createdby);
        v_left := v_left - v_un;
    END IF;

    FOR l IN
        SELECT p.purchaseid, p.remainingquantity, p.unitcost, p.costmode, p.deferredremainingcost
          FROM restaurantpurchases p
         WHERE p.ingredientid = p_ingredientid AND p.status = 'Posted' AND p.remainingquantity > 0
         ORDER BY p.purchasedate, p.purchaseid
           FOR UPDATE
    LOOP
        EXIT WHEN v_left <= 0;
        v_take := LEAST(v_left, l.remainingquantity);
        v_share := CASE WHEN v_take >= l.remainingquantity THEN l.deferredremainingcost
                        ELSE ROUND(l.deferredremainingcost * v_take / l.remainingquantity, 2) END;
        UPDATE restaurantpurchases
           SET remainingquantity = remainingquantity - v_take,
               deferredremainingcost = deferredremainingcost - v_share
         WHERE purchaseid = l.purchaseid;
        INSERT INTO restaurantstockdraws (farmid, ingredientid, purchaseid, stockmovementid, drawtype, drawdate,
                                          quantity, unitcost, costmode, deferredcost, reference, createdby)
        VALUES (p_farmid, p_ingredientid, l.purchaseid, p_movementid, p_drawtype, p_date, v_take, l.unitcost,
                l.costmode, v_share, p_reference, p_createdby);
        v_total := v_total + v_share;
        v_left := v_left - v_take;
    END LOOP;

    -- More drawn than is on hand: the rest has no cost to move (stock goes
    -- negative, as it always could).
    IF v_left > 0 THEN
        INSERT INTO restaurantstockdraws (farmid, ingredientid, purchaseid, stockmovementid, drawtype, drawdate,
                                          quantity, unitcost, costmode, deferredcost, reference, createdby)
        VALUES (p_farmid, p_ingredientid, NULL, p_movementid, p_drawtype, p_date, v_left, v_cpu, 'UNLOTTED', 0,
                p_reference, p_createdby);
    END IF;
    RETURN v_total;
END $$;

-- -----------------------------------------------------------------------------
-- 4. Purchases
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_purchase_create(
    p_farmid TEXT, p_ingredientid INT, p_quantity NUMERIC, p_totalcost NUMERIC,
    p_purchasedate DATE DEFAULT NULL, p_supplierid INT DEFAULT NULL, p_suppliername TEXT DEFAULT NULL,
    p_paymentmethod TEXT DEFAULT 'Cash', p_amountpaid NUMERIC DEFAULT NULL, p_cashaccountid INT DEFAULT NULL,
    p_duedate DATE DEFAULT NULL, p_notes TEXT DEFAULT NULL, p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
    v_date   DATE := COALESCE(p_purchasedate, CURRENT_DATE);
    v_qty    NUMERIC(14,4) := ROUND(COALESCE(p_quantity, 0), 4);
    v_total  NUMERIC(14,2) := ROUND(COALESCE(p_totalcost, 0), 2);
    v_method TEXT := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
    v_credit BOOLEAN; v_paid NUMERIC(14,2); v_acc INT;
    v_sup INT := p_supplierid; v_supname TEXT := NULLIF(btrim(p_suppliername), '');
    v_ing restaurantingredients%ROWTYPE; v_mode TEXT; v_id INT; v_short NUMERIC;
BEGIN
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Quantity must be greater than 0.'; END IF;
    IF v_total < 0 THEN RAISE EXCEPTION 'Total cost cannot be negative.'; END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'A purchase cannot be dated in the future.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    SELECT * INTO v_ing FROM restaurantingredients i
     WHERE i.ingredientid = p_ingredientid AND i.farmid = p_farmid FOR UPDATE;
    IF v_ing.ingredientid IS NULL THEN RAISE EXCEPTION 'Pick an ingredient or supply of this restaurant.'; END IF;

    IF v_sup IS NOT NULL THEN
        SELECT s.name INTO v_supname FROM restaurantsuppliers s
         WHERE s.restaurantsupplierid = v_sup AND s.farmid = p_farmid;
        IF v_supname IS NULL THEN RAISE EXCEPTION 'Supplier does not belong to this company.'; END IF;
    ELSIF v_supname IS NOT NULL THEN
        -- A typed name that is exactly one supplier is that supplier.
        SELECT MIN(s.restaurantsupplierid) INTO v_sup FROM restaurantsuppliers s
         WHERE s.farmid = p_farmid AND lower(btrim(s.name)) = lower(v_supname)
        HAVING COUNT(*) = 1;
    END IF;

    v_credit := lower(v_method) = 'credit';
    v_paid := ROUND(COALESCE(p_amountpaid, CASE WHEN v_credit THEN 0 ELSE v_total END), 2);
    IF v_paid < 0 THEN RAISE EXCEPTION 'Amount paid cannot be negative.'; END IF;
    IF v_paid > v_total THEN
        RAISE EXCEPTION 'Amount paid now (%) cannot be more than the total cost (%).', v_paid, v_total;
    END IF;
    IF v_credit AND v_paid > 0 THEN
        RAISE EXCEPTION 'A credit purchase has nothing paid now. Choose how the % was paid, or leave Amount paid now empty.', v_paid;
    END IF;
    -- A balance is owed to somebody; without a supplier it could never be found
    -- again on Supplier Balances.
    IF v_paid < v_total AND v_sup IS NULL THEN
        RAISE EXCEPTION 'Choose the supplier: % of this purchase is still owed.', (v_total - v_paid);
    END IF;

    IF v_paid > 0 THEN
        v_acc := p_cashaccountid;
        IF v_acc IS NULL THEN
            IF lower(replace(v_method, ' ', '')) = 'cash' THEN
                v_acc := fnrestaurant_default_account(p_farmid, 'Cash');
            ELSE
                v_acc := fnrestaurant_resolve_account(p_farmid, v_method, NULL, NULL, FALSE);
            END IF;
        END IF;
        IF v_acc IS NULL THEN RAISE EXCEPTION 'Choose the cash account this was paid from.'; END IF;
    END IF;

    v_mode := fnrestaurant_costmode(p_farmid, v_ing.category);

    INSERT INTO restaurantpurchases
        (farmid, ingredientid, purchasedate, supplierid, suppliername, quantity, unit, unitcost, totalcost,
         paymentmethod, amountpaid, cashaccountid, duedate, costmode, remainingquantity,
         deferredtotalcost, deferredremainingcost, notes, createdby)
    VALUES
        (p_farmid, p_ingredientid, v_date, v_sup, v_supname, v_qty, v_ing.unit, ROUND(v_total / v_qty, 4), v_total,
         v_method, v_paid, CASE WHEN v_paid > 0 THEN v_acc END, CASE WHEN v_paid < v_total THEN p_duedate END,
         v_mode, v_qty,
         CASE WHEN v_mode = 'EXPENSE_WHEN_CONSUMED' THEN v_total ELSE 0 END,
         CASE WHEN v_mode = 'EXPENSE_WHEN_CONSUMED' THEN v_total ELSE 0 END,
         NULLIF(btrim(p_notes), ''), p_createdby)
    RETURNING purchaseid INTO v_id;

    INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, unitcost, reference, reason, createdby)
    VALUES (p_farmid, p_ingredientid, 'PurchaseIn', v_qty, ROUND(v_total / v_qty, 4), 'Purchase #' || v_id,
            COALESCE(v_supname, 'Purchase'), p_createdby);

    -- Stock already used before this delivery was recorded (stock below zero)
    -- is taken from the new lot straight away, so its cost is not left waiting.
    v_short := LEAST(GREATEST(-COALESCE(v_ing.currentstock, 0), 0), v_qty);
    UPDATE restaurantingredients SET currentstock = COALESCE(currentstock, 0) + v_qty, updatedat = NOW()
     WHERE ingredientid = p_ingredientid;
    IF v_short > 0 THEN
        -- Stock is now (negative + qty); the lots hold qty, so the shortfall is
        -- drawn from the lot, which leaves stock and lots in step.
        -- No stock movement: the quantity already left in the earlier movement
        -- that took stock below zero; only its cost is caught up here.
        UPDATE restaurantingredients SET currentstock = currentstock + v_short WHERE ingredientid = p_ingredientid;
        PERFORM fnrestaurant_stock_draw(p_farmid, p_ingredientid, v_short, 'Shortfall', NULL, v_date,
                                        'Purchase #' || v_id, p_createdby);
        UPDATE restaurantingredients SET currentstock = currentstock - v_short WHERE ingredientid = p_ingredientid;
    END IF;
    PERFORM fnrestaurant_ingredient_refreshcost(p_ingredientid);

    IF v_paid > 0 THEN
        PERFORM fnrestaurant_post(p_farmid, v_acc, v_date, -v_paid, 'StockPurchase', v_id,
                                  'Purchase: ' || v_ing.name || COALESCE(' (' || v_supname || ')', ''), p_createdby);
    END IF;
    RETURN v_id;
END $$;

-- Undo a purchase recorded in error. Refused once any of its stock has been
-- used or a supplier payment was applied to it. The rows are kept and marked;
-- the cash paid comes back today; the stock goes back out.
CREATE FUNCTION sprestaurant_purchase_reverse(p_farmid TEXT, p_purchaseid INT, p_reason TEXT, p_reversedby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_p restaurantpurchases%ROWTYPE; v_name TEXT;
BEGIN
    SELECT * INTO v_p FROM restaurantpurchases p WHERE p.purchaseid = p_purchaseid AND p.farmid = p_farmid FOR UPDATE;
    IF v_p.purchaseid IS NULL THEN RAISE EXCEPTION 'Purchase not found for this company.'; END IF;
    IF v_p.status = 'Reversed' THEN RAISE EXCEPTION 'This purchase has already been reversed.'; END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to reverse a purchase.'; END IF;
    IF fnrestaurant_allocated(p_farmid, 'Purchase', p_purchaseid) > 0 THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this purchase. Reverse the payment on Supplier Payments first.';
    END IF;
    IF v_p.remainingquantity < v_p.quantity THEN
        RAISE EXCEPTION 'Stock from this purchase has already been used, so it cannot be reversed. Record an adjustment instead.';
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    SELECT i.name INTO v_name FROM restaurantingredients i WHERE i.ingredientid = v_p.ingredientid FOR UPDATE;
    UPDATE restaurantingredients SET currentstock = currentstock - v_p.quantity, updatedat = NOW()
     WHERE ingredientid = v_p.ingredientid;
    INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, unitcost, reference, reason, createdby)
    VALUES (p_farmid, v_p.ingredientid, 'PurchaseReversal', -v_p.quantity, v_p.unitcost, 'Purchase #' || v_p.purchaseid,
            btrim(p_reason), p_reversedby);

    IF v_p.amountpaid > 0 THEN
        PERFORM fnrestaurant_post(p_farmid, v_p.cashaccountid, CURRENT_DATE, v_p.amountpaid, 'StockPurchaseReversal',
                                  v_p.purchaseid, 'Reversal of purchase: ' || v_name || ' — ' || btrim(p_reason),
                                  p_reversedby,
                                  (SELECT t.cashtxnid FROM restaurantcashtransactions t
                                    WHERE t.sourcetype = 'StockPurchase' AND t.sourceid = v_p.purchaseid));
    END IF;

    UPDATE restaurantpurchases
       SET status = 'Reversed', remainingquantity = 0, deferredremainingcost = 0,
           reversedby = p_reversedby, reversedat = NOW(), reversalreason = btrim(p_reason)
     WHERE purchaseid = p_purchaseid;
    PERFORM fnrestaurant_ingredient_refreshcost(v_p.ingredientid);
END $$;

CREATE FUNCTION sprestaurant_purchase_list(p_farmid TEXT, p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL,
                                           p_supplierid INT DEFAULT NULL, p_ingredientid INT DEFAULT NULL,
                                           p_purchaseid INT DEFAULT NULL)
RETURNS TABLE(purchaseid INT, purchasedate DATE, ingredientid INT, ingredientname TEXT, category TEXT, unit TEXT,
              supplierid INT, suppliername TEXT, quantity NUMERIC, unitcost NUMERIC, totalcost NUMERIC,
              paymentmethod TEXT, amountpaid NUMERIC, allocated NUMERIC, balance NUMERIC, paymentstatus TEXT,
              duedate DATE, cashaccountid INT, cashaccountname TEXT, costmode TEXT, remainingquantity NUMERIC,
              deferredtotalcost NUMERIC, deferredremainingcost NUMERIC, notes TEXT, status TEXT,
              createdby TEXT, createdat TIMESTAMP, reversedby TEXT, reversedat TIMESTAMP, reversalreason TEXT)
LANGUAGE sql STABLE AS $$
    SELECT p.purchaseid, p.purchasedate, p.ingredientid, i.name, i.category, p.unit,
           p.supplierid, COALESCE(s.name, p.suppliername), p.quantity, p.unitcost, p.totalcost,
           p.paymentmethod, p.amountpaid, a.alloc,
           CASE WHEN p.status = 'Posted' THEN GREATEST(p.totalcost - p.amountpaid - a.alloc, 0) ELSE 0 END::NUMERIC(14,2),
           CASE WHEN p.status = 'Reversed' THEN 'Reversed'
                WHEN p.totalcost - p.amountpaid - a.alloc <= 0 THEN 'Paid'
                WHEN p.amountpaid + a.alloc > 0 THEN 'Partially Paid' ELSE 'Unpaid' END,
           p.duedate, p.cashaccountid, ca.name, p.costmode, p.remainingquantity,
           p.deferredtotalcost, p.deferredremainingcost, p.notes, p.status,
           p.createdby, p.createdat, p.reversedby, p.reversedat, p.reversalreason
      FROM restaurantpurchases p
      JOIN restaurantingredients i ON i.ingredientid = p.ingredientid
      LEFT JOIN restaurantsuppliers s ON s.restaurantsupplierid = p.supplierid
      LEFT JOIN restaurantcashaccounts ca ON ca.cashaccountid = p.cashaccountid
     CROSS JOIN LATERAL (SELECT fnrestaurant_allocated(p_farmid, 'Purchase', p.purchaseid) AS alloc) a
     WHERE p.farmid = p_farmid
       AND (p_from IS NULL OR p.purchasedate >= p_from)
       AND (p_to IS NULL OR p.purchasedate <= p_to)
       AND (p_supplierid IS NULL OR p.supplierid = p_supplierid)
       AND (p_ingredientid IS NULL OR p.ingredientid = p_ingredientid)
       AND (p_purchaseid IS NULL OR p.purchaseid = p_purchaseid)
     ORDER BY p.purchasedate DESC, p.purchaseid DESC;
$$;

-- -----------------------------------------------------------------------------
-- 5. The stock writers draw through the FIFO engine. Same signatures as before.
-- -----------------------------------------------------------------------------

-- 323's body, now one movement + one draw per ingredient. Still idempotent.
CREATE FUNCTION sprestaurant_recipe_deduct_order(p_orderid INT, p_farmid TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_count INT := 0; v_item RECORD; v_r RECORD; v_ref TEXT := 'Order #' || p_orderid; v_mid INT;
BEGIN
    IF EXISTS (SELECT 1 FROM restaurantstockmovements m
                WHERE m.farmid = p_farmid AND m.movementtype = 'OrderDeduction' AND m.reference = v_ref) THEN
        RETURN 0;
    END IF;
    FOR v_item IN
        SELECT oi.menuitemid, oi.quantity AS orderqty
          FROM restaurantorderitems oi
         WHERE oi.orderid = p_orderid AND oi.farmid = p_farmid
           AND oi.menuitemid IS NOT NULL AND oi.status <> 'Cancelled'
    LOOP
        FOR v_r IN
            SELECT r.ingredientid, SUM(r.quantity * (1 + COALESCE(r.wastepercent, 0) / 100) * v_item.orderqty) AS qty
              FROM restaurantrecipes r
              JOIN restaurantingredients i ON i.ingredientid = r.ingredientid AND i.farmid = r.farmid
             WHERE r.menuitemid = v_item.menuitemid AND r.farmid = p_farmid
             GROUP BY r.ingredientid
        LOOP
            INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, unitcost, reference, createdby)
            SELECT p_farmid, v_r.ingredientid, 'OrderDeduction', -v_r.qty, i.costperunit, v_ref, 'System'
              FROM restaurantingredients i WHERE i.ingredientid = v_r.ingredientid
            RETURNING stockmovementid INTO v_mid;
            PERFORM fnrestaurant_stock_draw(p_farmid, v_r.ingredientid, v_r.qty, 'OrderDeduction', v_mid,
                                            CURRENT_DATE, v_ref, 'System');
            UPDATE restaurantingredients SET currentstock = currentstock - v_r.qty, updatedat = NOW()
             WHERE ingredientid = v_r.ingredientid AND farmid = p_farmid;
            PERFORM fnrestaurant_ingredient_refreshcost(v_r.ingredientid);
        END LOOP;
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END $$;

-- 222's body. Signed by type: the dialog sends the quantity as typed (always
-- positive), and "Adjustment Out" used to ADD it. A purchase is no longer an
-- adjustment: it carries a cost, a supplier and money (sprestaurant_purchase_create).
CREATE FUNCTION sprestaurant_ingredient_adjust_stock(
    p_id INT, p_farmid TEXT, p_quantity NUMERIC, p_movementtype TEXT, p_reason TEXT, p_createdby TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_q NUMERIC; v_mid INT;
BEGIN
    IF p_movementtype = 'PurchaseIn' THEN
        RAISE EXCEPTION 'Record a delivery with Record Purchase, so it carries its cost and supplier.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM restaurantingredients i WHERE i.ingredientid = p_id AND i.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Ingredient not found for this restaurant.';
    END IF;
    v_q := CASE WHEN p_movementtype ILIKE '%Out' THEN -ABS(COALESCE(p_quantity, 0))
                WHEN p_movementtype ILIKE '%In' THEN ABS(COALESCE(p_quantity, 0))
                ELSE COALESCE(p_quantity, 0) END;
    IF v_q = 0 THEN RAISE EXCEPTION 'Quantity must not be 0.'; END IF;
    INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, unitcost, reason, createdby)
    SELECT p_farmid, p_id, p_movementtype, v_q, i.costperunit, p_reason, p_createdby
      FROM restaurantingredients i WHERE i.ingredientid = p_id
    RETURNING stockmovementid INTO v_mid;
    IF v_q < 0 THEN
        PERFORM fnrestaurant_stock_draw(p_farmid, p_id, -v_q, 'Adjustment', v_mid, CURRENT_DATE,
                                        COALESCE(NULLIF(btrim(p_reason), ''), p_movementtype), p_createdby);
    END IF;
    UPDATE restaurantingredients SET currentstock = COALESCE(currentstock, 0) + v_q, updatedat = NOW()
     WHERE ingredientid = p_id AND farmid = p_farmid;
    PERFORM fnrestaurant_ingredient_refreshcost(p_id);
END $$;

-- 222's body, drawing through the engine.
CREATE FUNCTION sprestaurant_wastelog_insert(
    p_farmid TEXT, p_ingredientid INT, p_menuitemid INT, p_ingredientname TEXT,
    p_quantity NUMERIC, p_unit TEXT, p_costamount NUMERIC, p_reason TEXT,
    p_notes TEXT, p_loggedby TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_id INT; v_mid INT;
BEGIN
    INSERT INTO restaurantwastelog (farmid, ingredientid, menuitemid, ingredientname,
        quantity, unit, costamount, reason, notes, loggedby)
    VALUES (p_farmid, p_ingredientid, p_menuitemid, p_ingredientname,
        p_quantity, p_unit, p_costamount, p_reason, p_notes, p_loggedby)
    RETURNING wastelogid INTO v_id;
    IF p_ingredientid IS NOT NULL AND COALESCE(p_quantity, 0) > 0 THEN
        INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, unitcost, reason, createdby)
        SELECT p_farmid, p_ingredientid, 'WasteOut', -p_quantity, i.costperunit,
               p_reason || ': ' || COALESCE(p_notes, ''), p_loggedby
          FROM restaurantingredients i WHERE i.ingredientid = p_ingredientid AND i.farmid = p_farmid
        RETURNING stockmovementid INTO v_mid;
        IF v_mid IS NOT NULL THEN
            PERFORM fnrestaurant_stock_draw(p_farmid, p_ingredientid, p_quantity, 'Waste', v_mid, CURRENT_DATE,
                                            'Waste #' || v_id, p_loggedby);
            UPDATE restaurantingredients SET currentstock = currentstock - p_quantity, updatedat = NOW()
             WHERE ingredientid = p_ingredientid AND farmid = p_farmid;
            PERFORM fnrestaurant_ingredient_refreshcost(p_ingredientid);
        END IF;
    END IF;
    RETURN v_id;
END $$;

-- 222's body. A count below what is on hand draws the shortfall.
CREATE FUNCTION sprestaurant_stocktake_complete(p_id INT, p_farmid TEXT, p_completedby TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_item RECORD; v_cur NUMERIC; v_mid INT;
BEGIN
    FOR v_item IN SELECT * FROM restaurantstocktakeitems WHERE stocktakeid = p_id AND farmid = p_farmid AND variance != 0
    LOOP
        SELECT COALESCE(i.currentstock, 0) INTO v_cur FROM restaurantingredients i
         WHERE i.ingredientid = v_item.ingredientid AND i.farmid = p_farmid;
        INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, reason, createdby)
        VALUES (p_farmid, v_item.ingredientid,
            CASE WHEN v_item.variance > 0 THEN 'AdjustmentIn' ELSE 'AdjustmentOut' END,
            v_item.variance, 'Stock take adjustment', p_completedby)
        RETURNING stockmovementid INTO v_mid;
        IF v_cur > v_item.actualqty THEN
            PERFORM fnrestaurant_stock_draw(p_farmid, v_item.ingredientid, v_cur - v_item.actualqty, 'StockTake',
                                            v_mid, CURRENT_DATE, 'Stock take #' || p_id, p_completedby);
        END IF;
        UPDATE restaurantingredients SET currentstock = v_item.actualqty, updatedat = NOW()
         WHERE ingredientid = v_item.ingredientid AND farmid = p_farmid;
        PERFORM fnrestaurant_ingredient_refreshcost(v_item.ingredientid);
    END LOOP;
    UPDATE restaurantstocktakes SET status = 'Completed', completedby = p_completedby, completedat = NOW()
    WHERE stocktakeid = p_id AND farmid = p_farmid;
END $$;

-- 222's body: an item with purchases behind it is part of the books.
CREATE FUNCTION sprestaurant_ingredient_delete(p_id INT, p_farmid TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM restaurantpurchases p WHERE p.ingredientid = p_id AND p.farmid = p_farmid) THEN
        RAISE EXCEPTION 'This item has purchases recorded against it, so it cannot be deleted. Edit it and mark it inactive instead.';
    END IF;
    DELETE FROM restaurantingredients WHERE ingredientid = p_id AND farmid = p_farmid;
END $$;

-- -----------------------------------------------------------------------------
-- 6. Payables: the ONE definition every supplier reader uses (Poultry 238's
--    fnpoultrypayables). amountpaid = paid at entry + supplier payments applied.
-- -----------------------------------------------------------------------------
CREATE FUNCTION fnrestaurant_payables(p_farmid TEXT)
RETURNS TABLE(documenttype TEXT, documentid INT, supplierid INT, docdate DATE, label TEXT, reference TEXT,
              totalcost NUMERIC, paidatentry NUMERIC, allocated NUMERIC, amountpaid NUMERIC, balance NUMERIC,
              cashaccountid INT, duedate DATE)
LANGUAGE sql STABLE AS $$
    SELECT 'Purchase'::TEXT, p.purchaseid, p.supplierid, p.purchasedate,
           (i.name || ' — ' || rtrim(rtrim(p.quantity::TEXT, '0'), '.') || COALESCE(' ' || p.unit, ''))::TEXT,
           ('PO-' || p.purchaseid)::TEXT,
           p.totalcost, p.amountpaid, a.x, (p.amountpaid + a.x)::NUMERIC(14,2),
           GREATEST(p.totalcost - p.amountpaid - a.x, 0)::NUMERIC(14,2), p.cashaccountid, p.duedate
      FROM restaurantpurchases p
      JOIN restaurantingredients i ON i.ingredientid = p.ingredientid
     CROSS JOIN LATERAL (SELECT fnrestaurant_allocated(p_farmid, 'Purchase', p.purchaseid) AS x) a
     WHERE p.farmid = p_farmid AND p.status = 'Posted' AND p.supplierid IS NOT NULL
    UNION ALL
    SELECT 'Expense'::TEXT, e.expenseid, x.supplierid, e.expensedate,
           e.description::TEXT, ('E' || e.expenseid)::TEXT,
           e.amount::NUMERIC(14,2), x.amountpaid, a.x, (x.amountpaid + a.x)::NUMERIC(14,2),
           GREATEST(e.amount - x.amountpaid - a.x, 0)::NUMERIC(14,2), NULL::INT, x.duedate
      FROM restaurantexpensepayables x
      JOIN restaurantexpenses e ON e.expenseid = x.expenseid AND e.farmid = x.farmid
     CROSS JOIN LATERAL (SELECT fnrestaurant_allocated(p_farmid, 'Expense', e.expenseid) AS x) a
     WHERE x.farmid = p_farmid AND x.supplierid IS NOT NULL
       AND COALESCE(e.status, 'Approved') NOT IN ('Rejected', 'Draft')
    UNION ALL
    -- An acquisition carries its corrections: one document (328 / Poultry 313).
    SELECT 'AssetCost'::TEXT, d.assetcostid, d.supplierid, d.costdate,
           ('Capital investment: ' || ca.assetname || COALESCE(' — ' || NULLIF(d.description, ca.assetname), ''))::TEXT,
           ca.assetnumber::TEXT,
           doc.amt, doc.paid, a.x, (doc.paid + a.x)::NUMERIC(14,2),
           GREATEST(doc.amt - doc.paid - a.x, 0)::NUMERIC(14,2), d.cashaccountid, d.duedate
      FROM restaurantcapitalassetcosts d
      JOIN restaurantcapitalassets ca ON ca.capitalassetid = d.capitalassetid
     CROSS JOIN LATERAL (
            SELECT COALESCE(SUM(y.amount), 0)::NUMERIC(14,2) AS amt, COALESCE(SUM(y.amountpaid), 0)::NUMERIC(14,2) AS paid
              FROM restaurantcapitalassetcosts y
             WHERE y.status = 'Posted' AND (y.assetcostid = d.assetcostid OR y.correctionofid = d.assetcostid)) doc
     CROSS JOIN LATERAL (SELECT fnrestaurant_allocated(p_farmid, 'AssetCost', d.assetcostid) AS x) a
     WHERE d.farmid = p_farmid AND d.status = 'Posted' AND d.sourcetype <> 'OriginalCostCorrection'
       AND d.supplierid IS NOT NULL;
$$;

-- 242's body: a supplier on the books is deactivated, never deleted; one still
-- owed money is refused.
CREATE FUNCTION sprestaurant_supplier_delete(p_id INT, p_farmid TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_owed NUMERIC;
BEGIN
    SELECT COALESCE(SUM(d.balance), 0) INTO v_owed FROM fnrestaurant_payables(p_farmid) d WHERE d.supplierid = p_id;
    IF v_owed > 0 THEN
        RAISE EXCEPTION 'This supplier is still owed %. Settle it on Supplier Balances before deleting the supplier.', v_owed;
    END IF;
    IF EXISTS (SELECT 1 FROM restaurantpurchases x WHERE x.supplierid = p_id)
       OR EXISTS (SELECT 1 FROM restaurantsupplierpayments x WHERE x.supplierid = p_id)
       OR EXISTS (SELECT 1 FROM restaurantexpensepayables x WHERE x.supplierid = p_id)
       OR EXISTS (SELECT 1 FROM restaurantcapitalassetcosts x WHERE x.supplierid = p_id)
       OR EXISTS (SELECT 1 FROM restaurantcapitalassets x WHERE x.supplierid = p_id) THEN
        UPDATE restaurantsuppliers SET isactive = FALSE, updatedat = NOW()
         WHERE restaurantsupplierid = p_id AND farmid = p_farmid;
        RETURN;
    END IF;
    DELETE FROM restaurantsuppliers WHERE restaurantsupplierid = p_id AND farmid = p_farmid;
END $$;

-- -----------------------------------------------------------------------------
-- 7. Supplier Balances (Poultry 238 / 224, same result columns).
--    restaurantsuppliers has no payment terms, so terms are 0 (Poultry's default).
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_supplierbalances(
    p_farmid TEXT, p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL, p_supplierid INT DEFAULT NULL,
    p_status TEXT DEFAULT 'All', p_minbalance NUMERIC DEFAULT NULL, p_search TEXT DEFAULT NULL)
RETURNS TABLE(supplierid INT, suppliername TEXT, contactphone TEXT, contactemail TEXT, paymenttermsdays INT,
              totalbalance NUMERIC, openpurchasecount INT, oldestpurchasedate DATE, latestpurchasedate DATE,
              lastpaymentdate TIMESTAMP, overdueamount NUMERIC, totalpurchases NUMERIC, totalpaid NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH openpurchases AS (
        SELECT d.* FROM fnrestaurant_payables(p_farmid) d
         WHERE (p_supplierid IS NULL OR d.supplierid = p_supplierid)
           AND (p_from IS NULL OR d.docdate >= p_from)
           AND (p_to IS NULL OR d.docdate <= p_to)
           AND d.balance > 0
    ), filtered AS (
        SELECT o.*, (COALESCE(o.duedate, o.docdate) < CURRENT_DATE) AS isoverdue
          FROM openpurchases o
         WHERE CASE COALESCE(p_status, 'All')
                    WHEN 'Partial' THEN o.amountpaid > 0
                    WHEN 'Unpaid'  THEN o.amountpaid = 0
                    WHEN 'Overdue' THEN COALESCE(o.duedate, o.docdate) < CURRENT_DATE
                    ELSE TRUE END
    )
    SELECT s.restaurantsupplierid, s.name::TEXT, s.phone::TEXT, s.email::TEXT, 0,
           SUM(f.balance)::NUMERIC(14,2), COUNT(*)::INT, MIN(f.docdate), MAX(f.docdate),
           (SELECT MAX(sp.paymentdate) FROM restaurantsupplierpayments sp
             WHERE sp.farmid = p_farmid AND sp.supplierid = s.restaurantsupplierid AND sp.status = 'Posted'),
           SUM(CASE WHEN f.isoverdue THEN f.balance ELSE 0 END)::NUMERIC(14,2),
           SUM(f.totalcost)::NUMERIC(14,2), SUM(f.amountpaid)::NUMERIC(14,2)
      FROM filtered f
      JOIN restaurantsuppliers s ON s.restaurantsupplierid = f.supplierid AND s.farmid = p_farmid
     WHERE (p_search IS NULL OR btrim(p_search) = ''
            OR s.name ILIKE '%' || btrim(p_search) || '%'
            OR COALESCE(s.phone, '') ILIKE '%' || btrim(p_search) || '%')
     GROUP BY s.restaurantsupplierid, s.name, s.phone, s.email
    HAVING (p_minbalance IS NULL OR SUM(f.balance) >= p_minbalance)
     ORDER BY SUM(f.balance) DESC;
$$;

CREATE FUNCTION sprestaurant_supplierbalancesummary(p_farmid TEXT)
RETURNS TABLE(totalbalance NUMERIC, suppliersowed INT, overduepayables NUMERIC, paymentsmadetoday NUMERIC,
              largestbalance NUMERIC, largestbalancesupplier TEXT)
LANGUAGE sql STABLE AS $$
    WITH b AS (SELECT * FROM sprestaurant_supplierbalances(p_farmid))
    SELECT COALESCE(SUM(b.totalbalance), 0)::NUMERIC(14,2), COUNT(*)::INT,
           COALESCE(SUM(b.overdueamount), 0)::NUMERIC(14,2),
           COALESCE((SELECT SUM(sp.totalamount) FROM restaurantsupplierpayments sp
                      WHERE sp.farmid = p_farmid AND sp.status = 'Posted'
                        AND sp.paymentdate::DATE = CURRENT_DATE), 0)::NUMERIC(14,2),
           COALESCE(MAX(b.totalbalance), 0)::NUMERIC(14,2),
           (SELECT b2.suppliername FROM b b2 ORDER BY b2.totalbalance DESC LIMIT 1)
      FROM b;
$$;

CREATE FUNCTION sprestaurant_supplieropenpurchases(p_farmid TEXT, p_supplierid INT, p_from DATE DEFAULT NULL,
                                                   p_to DATE DEFAULT NULL, p_status TEXT DEFAULT 'All')
RETURNS TABLE(documenttype TEXT, documentid INT, reference TEXT, docdate DATE, label TEXT, totalcost NUMERIC,
              amountpaid NUMERIC, balance NUMERIC, duedate DATE, agedays INT, status TEXT, isoverdue BOOLEAN,
              cashaccountid INT)
LANGUAGE sql STABLE AS $$
    SELECT d.documenttype, d.documentid, d.reference, d.docdate, d.label, d.totalcost, d.amountpaid, d.balance,
           COALESCE(d.duedate, d.docdate), GREATEST(CURRENT_DATE - d.docdate, 0)::INT,
           CASE WHEN d.amountpaid > 0 THEN 'Partially Paid' ELSE 'Unpaid' END::TEXT,
           (COALESCE(d.duedate, d.docdate) < CURRENT_DATE), d.cashaccountid
      FROM fnrestaurant_payables(p_farmid) d
     WHERE d.supplierid = p_supplierid AND d.balance > 0
       AND (p_from IS NULL OR d.docdate >= p_from)
       AND (p_to IS NULL OR d.docdate <= p_to)
       AND CASE COALESCE(p_status, 'All')
                WHEN 'Partial' THEN d.amountpaid > 0
                WHEN 'Unpaid'  THEN d.amountpaid = 0
                WHEN 'Overdue' THEN COALESCE(d.duedate, d.docdate) < CURRENT_DATE
                ELSE TRUE END
     ORDER BY d.docdate, d.documenttype, d.documentid;
$$;

-- -----------------------------------------------------------------------------
-- 8. Supplier payments (Poultry 262's record, 238's reverse), posting through
--    the restaurant ledger: ONE cash-out per payment.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_supplierpayment_record(
    p_farmid TEXT, p_supplierid INT, p_amount NUMERIC, p_allocations JSONB,
    p_paymentmethod TEXT DEFAULT NULL, p_paymentdate TIMESTAMP DEFAULT NULL, p_cashaccountid INT DEFAULT NULL,
    p_reference TEXT DEFAULT NULL, p_notes TEXT DEFAULT NULL, p_sourcetype TEXT DEFAULT 'SupplierBalances',
    p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
    v_amt NUMERIC(14,2) := ROUND(COALESCE(p_amount, 0), 2);
    v_when TIMESTAMP := COALESCE(p_paymentdate, NOW());
    v_name TEXT; v_n INT; v_sum NUMERIC; v_min NUMERIC; v_dups INT; v_bad INT; v_id INT; v_matched INT := 0;
    a RECORD; v_bal NUMERIC(14,2); v_rows restaurant_alloc_row[];
BEGIN
    IF v_amt <= 0 THEN RAISE EXCEPTION 'Payment amount must be greater than 0.'; END IF;
    IF p_supplierid IS NULL THEN RAISE EXCEPTION 'Choose the supplier this payment is for.'; END IF;
    SELECT s.name INTO v_name FROM restaurantsuppliers s
     WHERE s.restaurantsupplierid = p_supplierid AND s.farmid = p_farmid;
    IF v_name IS NULL THEN RAISE EXCEPTION 'Supplier does not belong to this company.'; END IF;
    IF p_cashaccountid IS NULL THEN RAISE EXCEPTION 'Choose the cash account this payment is paid from.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM restaurantcashaccounts c WHERE c.cashaccountid = p_cashaccountid AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
    END IF;
    IF v_when::DATE > CURRENT_DATE THEN RAISE EXCEPTION 'A payment cannot be dated in the future.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_when::DATE);

    -- The allocation list, parsed once into a local array of rows.
    SELECT COALESCE(array_agg(ROW(btrim(x.documenttype), x.documentid, ROUND(x.amount, 2))::restaurant_alloc_row), '{}')
      INTO v_rows
      FROM jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb)) AS x(documenttype TEXT, documentid INT, amount NUMERIC)
     WHERE x.documentid IS NOT NULL AND COALESCE(x.amount, 0) <> 0;

    SELECT COUNT(*), COALESCE(SUM(t.amount), 0), MIN(t.amount) INTO v_n, v_sum, v_min FROM unnest(v_rows) t;
    IF v_n = 0 THEN RAISE EXCEPTION 'Select at least one item to apply this payment to.'; END IF;
    SELECT COUNT(*) INTO v_dups FROM (SELECT 1 FROM unnest(v_rows) t GROUP BY t.documenttype, t.documentid HAVING COUNT(*) > 1) z;
    IF v_dups > 0 THEN RAISE EXCEPTION 'The same item appears more than once in this payment.'; END IF;
    IF v_min <= 0 THEN RAISE EXCEPTION 'Each allocation must be greater than 0.'; END IF;
    IF ROUND(v_sum, 2) <> v_amt THEN
        RAISE EXCEPTION 'Allocated total (%) must equal the payment amount (%).', ROUND(v_sum, 2), v_amt;
    END IF;
    SELECT COUNT(*) INTO v_bad FROM unnest(v_rows) t WHERE COALESCE(t.documenttype, '') NOT IN ('Purchase', 'Expense', 'AssetCost');
    IF v_bad > 0 THEN RAISE EXCEPTION 'Unknown document type. Expected Purchase, Expense or AssetCost.'; END IF;

    -- One payment run per restaurant at a time: two cashiers paying the same
    -- bill cannot both see its full balance.
    PERFORM pg_advisory_xact_lock(hashtext('restaurantsupplierpayment:' || p_farmid));

    INSERT INTO restaurantsupplierpayments (farmid, supplierid, paymentdate, totalamount, paymentmethod, cashaccountid,
                                            referenceno, notes, sourcetype, createdby)
    VALUES (p_farmid, p_supplierid, v_when, v_amt, NULLIF(btrim(p_paymentmethod), ''), p_cashaccountid,
            NULLIF(btrim(p_reference), ''), NULLIF(btrim(p_notes), ''),
            COALESCE(NULLIF(btrim(p_sourcetype), ''), 'SupplierBalances'), p_createdby)
    RETURNING supplierpaymentid INTO v_id;

    FOR a IN
        SELECT t.documenttype, t.documentid, t.amount, d.balance, d.reference
          FROM unnest(v_rows) t
          JOIN fnrestaurant_payables(p_farmid) d
            ON d.documenttype = t.documenttype AND d.documentid = t.documentid AND d.supplierid = p_supplierid
         ORDER BY d.docdate, d.documentid
    LOOP
        v_matched := v_matched + 1;
        v_bal := a.balance;
        IF v_bal <= 0 THEN RAISE EXCEPTION '% #% is already fully paid.', a.documenttype, a.documentid; END IF;
        IF a.amount > v_bal THEN
            RAISE EXCEPTION 'Cannot apply % to % #% -- its balance is only %.', a.amount, a.documenttype, a.documentid, v_bal;
        END IF;
        INSERT INTO supplierpaymentallocation (farmid, module, paymentid, documenttype, documentid, amountapplied,
                                               documentbalancebefore, documentbalanceafter, status, createdby)
        VALUES (p_farmid, 'restaurant', v_id, a.documenttype, a.documentid, a.amount, v_bal, v_bal - a.amount,
                'Posted', p_createdby);
    END LOOP;
    IF v_matched < v_n THEN
        RAISE EXCEPTION '% of the selected items do not belong to this supplier or company.', (v_n - v_matched);
    END IF;

    PERFORM fnrestaurant_post(p_farmid, p_cashaccountid, v_when::DATE, -v_amt, 'SupplierPayment', v_id,
                              'Supplier payment: ' || v_name || COALESCE(' (' || NULLIF(btrim(p_reference), '') || ')', ''),
                              p_createdby);
    RETURN v_id;
END $$;

CREATE FUNCTION sprestaurant_supplierpayment_reverse(p_farmid TEXT, p_paymentid INT, p_reason TEXT DEFAULT NULL,
                                                     p_reversedby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_p restaurantsupplierpayments%ROWTYPE; v_n INT; v_name TEXT;
BEGIN
    SELECT * INTO v_p FROM restaurantsupplierpayments sp
     WHERE sp.supplierpaymentid = p_paymentid AND sp.farmid = p_farmid FOR UPDATE;
    IF v_p.supplierpaymentid IS NULL THEN RAISE EXCEPTION 'Payment not found for this company.'; END IF;
    IF v_p.status = 'Reversed' THEN RAISE EXCEPTION 'This payment has already been reversed.'; END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to reverse a payment.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    UPDATE supplierpaymentallocation
       SET status = 'Reversed', reversedby = p_reversedby, reversedat = NOW(), reversalreason = btrim(p_reason)
     WHERE farmid = p_farmid AND module = 'restaurant' AND paymentid = p_paymentid AND status = 'Posted';
    GET DIAGNOSTICS v_n = ROW_COUNT;

    UPDATE restaurantsupplierpayments
       SET status = 'Reversed', reversedby = p_reversedby, reversedat = NOW(), reversalreason = btrim(p_reason)
     WHERE supplierpaymentid = p_paymentid;

    SELECT s.name INTO v_name FROM restaurantsuppliers s WHERE s.restaurantsupplierid = v_p.supplierid;
    PERFORM fnrestaurant_post(p_farmid, v_p.cashaccountid, CURRENT_DATE, v_p.totalamount, 'SupplierPaymentReversal',
                              p_paymentid, 'Reversal of supplier payment to ' || COALESCE(v_name, '?') || ': ' || btrim(p_reason),
                              p_reversedby,
                              (SELECT t.cashtxnid FROM restaurantcashtransactions t
                                WHERE t.sourcetype = 'SupplierPayment' AND t.sourceid = p_paymentid));
    RETURN v_n;
END $$;

CREATE FUNCTION sprestaurant_supplierpayment_history(p_farmid TEXT, p_supplierid INT DEFAULT NULL,
                                                     p_documenttype TEXT DEFAULT NULL, p_documentid INT DEFAULT NULL,
                                                     p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS TABLE(paymentid INT, supplierid INT, suppliername TEXT, paymentdate TIMESTAMP, totalamount NUMERIC,
              paymentmethod TEXT, referenceno TEXT, notes TEXT, sourcetype TEXT, status TEXT, allocationcount INT,
              cashaccountid INT, createdby TEXT, reversedby TEXT, reversedat TIMESTAMP, reversalreason TEXT,
              createdat TIMESTAMP)
LANGUAGE sql STABLE AS $$
    SELECT sp.supplierpaymentid, sp.supplierid, s.name::TEXT, sp.paymentdate, sp.totalamount, sp.paymentmethod,
           sp.referenceno, sp.notes, sp.sourcetype, sp.status,
           (SELECT COUNT(*)::INT FROM supplierpaymentallocation a
             WHERE a.farmid = p_farmid AND a.module = 'restaurant' AND a.paymentid = sp.supplierpaymentid),
           sp.cashaccountid, sp.createdby, sp.reversedby, sp.reversedat, sp.reversalreason, sp.createdat
      FROM restaurantsupplierpayments sp
      LEFT JOIN restaurantsuppliers s ON s.restaurantsupplierid = sp.supplierid
     WHERE sp.farmid = p_farmid
       AND (p_supplierid IS NULL OR sp.supplierid = p_supplierid)
       AND (p_from IS NULL OR sp.paymentdate::DATE >= p_from)
       AND (p_to IS NULL OR sp.paymentdate::DATE <= p_to)
       AND (p_documentid IS NULL OR EXISTS (
            SELECT 1 FROM supplierpaymentallocation a
             WHERE a.farmid = p_farmid AND a.module = 'restaurant' AND a.paymentid = sp.supplierpaymentid
               AND a.documentid = p_documentid
               AND (p_documenttype IS NULL OR a.documenttype = p_documenttype)))
     ORDER BY sp.paymentdate DESC, sp.supplierpaymentid DESC;
$$;

CREATE FUNCTION sprestaurant_supplierpayment_allocations(p_farmid TEXT, p_paymentid INT)
RETURNS TABLE(allocationid INT, paymentid INT, documenttype TEXT, documentid INT, reference TEXT, docdate DATE,
              label TEXT, documenttotal NUMERIC, amountapplied NUMERIC, documentbalancebefore NUMERIC,
              documentbalanceafter NUMERIC, status TEXT)
LANGUAGE sql STABLE AS $$
    SELECT a.allocationid, a.paymentid, a.documenttype, a.documentid, d.reference, d.docdate, d.label,
           d.totalcost, a.amountapplied, a.documentbalancebefore, a.documentbalanceafter, a.status
      FROM supplierpaymentallocation a
      LEFT JOIN fnrestaurant_payables(p_farmid) d ON d.documenttype = a.documenttype AND d.documentid = a.documentid
     WHERE a.farmid = p_farmid AND a.module = 'restaurant' AND a.paymentid = p_paymentid
     ORDER BY a.allocationid;
$$;

-- Poultry 238's statement: opening balance, what was billed, what was paid at
-- the counter, and each payment made. credit = billed, debit = paid.
CREATE FUNCTION sprestaurant_supplierstatement(p_farmid TEXT, p_supplierid INT, p_from DATE DEFAULT NULL,
                                               p_to DATE DEFAULT NULL)
RETURNS TABLE(entrydate DATE, entrytype TEXT, reference TEXT, description TEXT, credit NUMERIC, debit NUMERIC,
              runningbalance NUMERIC, documenttype TEXT, documentid INT, sortkey INT)
LANGUAGE sql STABLE AS $$
    WITH docs AS (SELECT * FROM fnrestaurant_payables(p_farmid) d WHERE d.supplierid = p_supplierid),
    lines AS (
        SELECT p_from AS entrydate, 'OpeningBalance'::TEXT AS entrytype, NULL::TEXT AS reference,
               'Opening balance'::TEXT AS description,
               CASE WHEN p_from IS NULL THEN 0::NUMERIC(14,2)
                    ELSE COALESCE((SELECT SUM(d.balance) FROM docs d WHERE d.docdate < p_from), 0)::NUMERIC(14,2) END AS credit,
               0::NUMERIC(14,2) AS debit, NULL::TEXT AS documenttype, NULL::INT AS documentid, 0 AS sortkey, 0 AS pin
        UNION ALL
        SELECT d.docdate, CASE WHEN d.documenttype = 'Expense' THEN 'Expense' ELSE 'Purchase' END::TEXT,
               d.reference, d.label, d.totalcost::NUMERIC(14,2), 0::NUMERIC(14,2), d.documenttype, d.documentid, 1, 1
          FROM docs d
         WHERE (p_from IS NULL OR d.docdate >= p_from) AND (p_to IS NULL OR d.docdate <= p_to)
        UNION ALL
        SELECT d.docdate, 'Payment'::TEXT, d.reference,
               CASE WHEN d.documenttype = 'Expense' THEN 'Paid when recorded' ELSE 'Paid at time of purchase' END::TEXT,
               0::NUMERIC(14,2), d.paidatentry::NUMERIC(14,2), d.documenttype, d.documentid, 2, 1
          FROM docs d
         WHERE d.paidatentry > 0
           AND (p_from IS NULL OR d.docdate >= p_from) AND (p_to IS NULL OR d.docdate <= p_to)
        UNION ALL
        SELECT sp.paymentdate::DATE, 'Payment'::TEXT,
               COALESCE(NULLIF(btrim(sp.referenceno), ''), 'SP' || sp.supplierpaymentid::TEXT)::TEXT,
               ('Payment made' || COALESCE(' (' || NULLIF(btrim(sp.paymentmethod), '') || ')', ''))::TEXT,
               0::NUMERIC(14,2), sp.totalamount::NUMERIC(14,2), NULL::TEXT, NULL::INT, 2, 1
          FROM restaurantsupplierpayments sp
         WHERE sp.farmid = p_farmid AND sp.supplierid = p_supplierid AND sp.status = 'Posted'
           AND (p_from IS NULL OR sp.paymentdate::DATE >= p_from)
           AND (p_to IS NULL OR sp.paymentdate::DATE <= p_to)
    )
    SELECT l.entrydate, l.entrytype, l.reference, l.description, l.credit, l.debit,
           SUM(l.credit - l.debit) OVER (ORDER BY l.pin, l.entrydate, l.sortkey, l.documentid NULLS FIRST
                                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::NUMERIC(14,2),
           l.documenttype, l.documentid, l.sortkey
      FROM lines l
     WHERE NOT (l.entrytype = 'OpeningBalance' AND l.credit = 0)
     ORDER BY l.pin, l.entrydate, l.sortkey, l.documentid NULLS FIRST;
$$;

-- -----------------------------------------------------------------------------
-- 9. Expenses: an optional supplier, and what was paid now (Poultry 238's
--    expense payables). 323's body otherwise unchanged.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_expense_record(p_farmid TEXT, p_expensedate DATE, p_categoryid INT,
                                            p_categoryname TEXT, p_description TEXT, p_amount NUMERIC,
                                            p_paymentmethod TEXT, p_suppliername TEXT, p_receiptref TEXT,
                                            p_createdby TEXT, p_cashaccountid INT DEFAULT NULL,
                                            p_supplierid INT DEFAULT NULL, p_amountpaid NUMERIC DEFAULT NULL,
                                            p_duedate DATE DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_id INT; v_acc INT; v_cat TEXT := NULLIF(btrim(p_categoryname), '');
        v_amt NUMERIC := ROUND(COALESCE(p_amount, 0), 2);
        v_date DATE := COALESCE(p_expensedate, CURRENT_DATE);
        v_method TEXT := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
        v_paid NUMERIC(14,2); v_supname TEXT := NULLIF(btrim(p_suppliername), '');
BEGIN
    IF v_amt <= 0 THEN RAISE EXCEPTION 'Expense amount must be more than zero.'; END IF;
    IF btrim(COALESCE(p_description, '')) = '' THEN RAISE EXCEPTION 'Description is required.'; END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'An expense cannot be dated in the future.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    IF p_supplierid IS NOT NULL THEN
        SELECT COALESCE(v_supname, s.name) INTO v_supname FROM restaurantsuppliers s
         WHERE s.restaurantsupplierid = p_supplierid AND s.farmid = p_farmid;
        IF NOT FOUND THEN RAISE EXCEPTION 'Supplier does not belong to this company.'; END IF;
    END IF;
    -- NULL = paid in full: the shape of every expense written before 329.
    v_paid := ROUND(COALESCE(p_amountpaid, v_amt), 2);
    IF v_paid < 0 THEN RAISE EXCEPTION 'Amount paid cannot be negative.'; END IF;
    IF v_paid > v_amt THEN RAISE EXCEPTION 'Amount paid cannot exceed the % total.', v_amt; END IF;

    IF v_cat IS NULL AND p_categoryid IS NOT NULL THEN
        SELECT c.name INTO v_cat FROM restaurantexpensecategories c
         WHERE c.expensecategoryid = p_categoryid AND c.farmid = p_farmid;
    END IF;

    INSERT INTO restaurantexpenses (farmid, expensedate, categoryid, categoryname, description, amount,
                                    paymentmethod, suppliername, receiptref, createdby, status)
    VALUES (p_farmid, v_date, p_categoryid, v_cat, btrim(p_description), v_amt, v_method,
            v_supname, p_receiptref, p_createdby, 'Approved')
    RETURNING expenseid INTO v_id;

    IF p_supplierid IS NOT NULL OR v_paid < v_amt THEN
        INSERT INTO restaurantexpensepayables (expenseid, farmid, supplierid, amountpaid, duedate)
        VALUES (v_id, p_farmid, p_supplierid, v_paid, CASE WHEN v_paid < v_amt THEN p_duedate END);
    END IF;

    IF v_paid > 0 THEN
        v_acc := fnrestaurant_resolve_account(p_farmid, v_method, p_cashaccountid, NULL, FALSE);
        -- Cash expenses default to the cash box, not an open till.
        IF p_cashaccountid IS NULL AND lower(replace(v_method, ' ', '')) = 'cash' THEN
            v_acc := fnrestaurant_default_account(p_farmid, 'Cash');
        END IF;
        IF v_acc IS NOT NULL THEN
            PERFORM fnrestaurant_post(p_farmid, v_acc, v_date, -v_paid, 'Expense', v_id,
                                      btrim(p_description) || COALESCE(' (' || v_cat || ')', ''), p_createdby);
        END IF;
    END IF;
    RETURN v_id;
END $$;

CREATE FUNCTION sprestaurant_expense_insert(p_farmid TEXT, p_expensedate DATE, p_categoryid INT,
                                            p_categoryname TEXT, p_description TEXT, p_amount NUMERIC,
                                            p_paymentmethod TEXT, p_suppliername TEXT, p_receiptref TEXT,
                                            p_createdby TEXT)
RETURNS INT LANGUAGE sql AS $$
    SELECT sprestaurant_expense_record(p_farmid, p_expensedate, p_categoryid, p_categoryname, p_description,
                                       p_amount, p_paymentmethod, p_suppliername, p_receiptref, p_createdby, NULL);
$$;

-- 323's body plus the supplier-payment guard.
CREATE FUNCTION sprestaurant_expense_delete(p_id INT, p_farmid TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_e restaurantexpenses%ROWTYPE; v_t RECORD;
BEGIN
    SELECT * INTO v_e FROM restaurantexpenses WHERE expenseid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    IF fnrestaurant_allocated(p_farmid, 'Expense', p_id) > 0 THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this expense. Reverse the payment on Supplier Payments first.';
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_e.expensedate);

    FOR v_t IN
        SELECT t.cashtxnid, t.cashaccountid, t.amount FROM restaurantcashtransactions t
         WHERE t.sourcetype = 'Expense' AND t.sourceid = p_id AND t.farmid = p_farmid
           AND NOT EXISTS (SELECT 1 FROM restaurantcashtransactions r WHERE r.reversesid = t.cashtxnid)
    LOOP
        PERFORM fnrestaurant_post(p_farmid, v_t.cashaccountid, v_e.expensedate, -v_t.amount, 'ExpenseReversal', p_id,
                                  'Deleted expense: ' || v_e.description, v_e.createdby, v_t.cashtxnid);
    END LOOP;
    DELETE FROM restaurantexpenses WHERE expenseid = p_id AND farmid = p_farmid;
END $$;

-- The payment state of each expense, read next to sprestaurant_expense_list
-- (whose shape cannot change -- see the header).
CREATE FUNCTION sprestaurant_expense_payments(p_farmid TEXT, p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS TABLE(expenseid INT, supplierid INT, suppliername TEXT, amountpaid NUMERIC, balance NUMERIC,
              paymentstatus TEXT, duedate DATE)
LANGUAGE sql STABLE AS $$
    SELECT e.expenseid, x.supplierid, COALESCE(s.name, e.suppliername)::TEXT,
           (COALESCE(x.amountpaid, e.amount) + a.x)::NUMERIC(14,2),
           GREATEST(e.amount - COALESCE(x.amountpaid, e.amount) - a.x, 0)::NUMERIC(14,2),
           CASE WHEN e.amount - COALESCE(x.amountpaid, e.amount) - a.x <= 0 THEN 'Paid'
                WHEN COALESCE(x.amountpaid, e.amount) + a.x > 0 THEN 'PartiallyPaid' ELSE 'Unpaid' END,
           x.duedate
      FROM restaurantexpenses e
      LEFT JOIN restaurantexpensepayables x ON x.expenseid = e.expenseid
      LEFT JOIN restaurantsuppliers s ON s.restaurantsupplierid = x.supplierid
     CROSS JOIN LATERAL (SELECT fnrestaurant_allocated(p_farmid, 'Expense', e.expenseid) AS x) a
     WHERE e.farmid = p_farmid
       AND (p_from IS NULL OR e.expensedate >= p_from)
       AND (p_to IS NULL OR e.expensedate <= p_to);
$$;

-- -----------------------------------------------------------------------------
-- 10. Capital investments (328) meet supplier payments: allocations reduce what
--     is owed, and a document with a payment against it cannot be reversed or
--     corrected below what was paid (Poultry 270 / 313). 328's bodies, same
--     signatures; only the marked (329) parts differ.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sprestaurant_capitalasset_correctoriginalcost(
    p_farmid TEXT, p_assetid INT, p_newamount NUMERIC, p_effectivedate DATE DEFAULT NULL,
    p_reason TEXT DEFAULT NULL, p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
    v_status TEXT; v_residual NUMERIC(14,2); v_number TEXT;
    v_new NUMERIC(14,2) := ROUND(COALESCE(p_newamount, 0), 2);
    v_acqcost NUMERIC(14,2); v_addcost NUMERIC(14,2); v_diff NUMERIC(14,2);
    v_acq restaurantcapitalassetcosts%ROWTYPE; v_paid NUMERIC(14,2); v_refund NUMERIC(14,2);
    v_date DATE := COALESCE(p_effectivedate, CURRENT_DATE); v_newid INT; v_alloc NUMERIC(14,2);
BEGIN
    SELECT a.status, a.residualvalue, a.assetnumber INTO v_status, v_residual, v_number
      FROM restaurantcapitalassets a
     WHERE a.capitalassetid = p_assetid AND a.farmid = p_farmid
       FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Asset not found for this company.'; END IF;
    IF v_status = 'Reversed' THEN RAISE EXCEPTION 'A reversed investment cannot be corrected.'; END IF;
    IF v_status = 'Disposed' THEN RAISE EXCEPTION 'A disposed investment cannot be corrected.'; END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to correct the original cost.'; END IF;
    IF v_new <= 0 THEN
        RAISE EXCEPTION 'The corrected original cost must be greater than 0. To undo the acquisition entirely, reverse the investment.';
    END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'A correction cannot be dated in the future.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    v_acqcost := fnrestaurantasset_acquisitioncost(p_assetid);
    v_addcost := fnrestaurantasset_additionalcost(p_assetid);
    v_diff    := v_new - v_acqcost;
    IF ABS(v_diff) < 0.005 THEN RAISE EXCEPTION 'The original acquisition cost is already %.', v_acqcost; END IF;

    SELECT * INTO v_acq FROM restaurantcapitalassetcosts c
     WHERE c.capitalassetid = p_assetid AND c.farmid = p_farmid
       AND c.sourcetype = 'Acquisition' AND c.status = 'Posted'
     ORDER BY c.assetcostid LIMIT 1;
    IF v_acq.assetcostid IS NULL THEN
        RAISE EXCEPTION 'This investment has no original acquisition to correct -- its cost was built up with Add cost. Reverse the added cost that is wrong and add it again.';
    END IF;
    IF v_residual > (v_new + v_addcost) THEN
        RAISE EXCEPTION 'Residual value (%) cannot be more than the corrected cost (%). Lower the residual value first.',
            v_residual, (v_new + v_addcost)::NUMERIC(14,2);
    END IF;

    -- What is paid on the acquisition document so far, net of earlier corrections.
    SELECT COALESCE(SUM(c.amountpaid), 0) INTO v_paid FROM restaurantcapitalassetcosts c
     WHERE c.status = 'Posted' AND (c.assetcostid = v_acq.assetcostid OR c.correctionofid = v_acq.assetcostid);
    -- (329) Supplier payments already applied stay applied; only the part paid
    -- at purchase can come back, and never below what payments settled.
    v_alloc := fnrestaurant_allocated(p_farmid, 'AssetCost', v_acq.assetcostid);
    IF v_alloc > v_new THEN
        RAISE EXCEPTION 'Supplier payments of % have already been recorded against this acquisition, which is more than the corrected cost of %. Reverse the payment on Supplier Payments first.',
            v_alloc, v_new;
    END IF;
    -- Nobody can have paid more than the bill is now for (313's LEAST).
    v_refund := GREATEST(v_paid + v_alloc - v_new, 0);

    INSERT INTO restaurantcapitalassetcosts
        (farmid, capitalassetid, costdate, description, costcategory, amount, sourcetype, correctionofid,
         paymentmethod, amountpaid, cashaccountid, supplierid, suppliername, createdby)
    VALUES
        (p_farmid, p_assetid, v_date, btrim(p_reason), 'Original Cost Correction', v_diff, 'OriginalCostCorrection',
         v_acq.assetcostid, v_acq.paymentmethod, -v_refund, CASE WHEN v_refund > 0 THEN v_acq.cashaccountid END,
         v_acq.supplierid, v_acq.suppliername, p_createdby)
    RETURNING assetcostid INTO v_newid;

    IF v_refund > 0 THEN
        PERFORM fnrestaurant_post(p_farmid, v_acq.cashaccountid, v_date, v_refund, 'AssetPurchaseReversal', v_newid,
                                  'Original cost of ' || v_number || ' corrected: ' || btrim(p_reason), p_createdby);
    END IF;

    UPDATE restaurantcapitalassets SET updatedby = p_createdby, updatedat = NOW() WHERE capitalassetid = p_assetid;
    PERFORM fnrestaurantasset_refreshstatus(p_farmid, p_assetid);
    RETURN v_newid;
END $$;
CREATE OR REPLACE FUNCTION sprestaurant_capitalasset_cost_reverse(p_farmid TEXT, p_costid INT, p_reason TEXT,
                                                       p_createdby TEXT DEFAULT NULL, p_assetid INT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_c restaurantcapitalassetcosts%ROWTYPE; v_astatus TEXT; v_number TEXT;
BEGIN
    SELECT * INTO v_c FROM restaurantcapitalassetcosts c
     WHERE c.assetcostid = p_costid AND c.farmid = p_farmid
       FOR UPDATE;
    IF v_c.assetcostid IS NULL THEN RAISE EXCEPTION 'Cost entry not found for this company.'; END IF;
    IF p_assetid IS NOT NULL AND p_assetid <> v_c.capitalassetid THEN
        RAISE EXCEPTION 'That cost entry does not belong to this investment.';
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to reverse a cost.'; END IF;
    IF v_c.status <> 'Posted' THEN RAISE EXCEPTION 'This cost has already been reversed.'; END IF;
    IF v_c.sourcetype = 'Acquisition' THEN
        RAISE EXCEPTION 'This is the original acquisition. Use Correct original cost to change the amount, or reverse the whole investment.';
    END IF;
    IF v_c.sourcetype = 'OriginalCostCorrection' THEN
        RAISE EXCEPTION 'A correction cannot be reversed. Correct the original cost again to the amount you want.';
    END IF;
    -- (329)
    IF fnrestaurant_allocated(p_farmid, 'AssetCost', v_c.assetcostid) > 0 THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this cost. Reverse the payment on Supplier Payments first.';
    END IF;

    SELECT a.status, a.assetnumber INTO v_astatus, v_number FROM restaurantcapitalassets a
     WHERE a.capitalassetid = v_c.capitalassetid AND a.farmid = p_farmid
       FOR UPDATE;
    IF v_astatus IN ('Reversed', 'Disposed') THEN
        RAISE EXCEPTION 'Cannot change the costs of a % investment.', lower(v_astatus);
    END IF;
    IF EXISTS (SELECT 1 FROM restaurantassetdepreciation d
                WHERE d.capitalassetid = v_c.capitalassetid AND d.status = 'Posted') THEN
        RAISE EXCEPTION 'Depreciation has already been posted for this investment. Reverse it before changing the investment cost.';
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    IF v_c.amountpaid > 0 THEN
        PERFORM fnrestaurant_post(p_farmid, v_c.cashaccountid, CURRENT_DATE, v_c.amountpaid, 'AssetPurchaseReversal',
                                  v_c.assetcostid, 'Reversal of a cost on ' || v_number || ': ' || btrim(p_reason),
                                  p_createdby,
                                  (SELECT t.cashtxnid FROM restaurantcashtransactions t
                                    WHERE t.sourcetype = 'AssetPurchase' AND t.sourceid = v_c.assetcostid));
    END IF;

    UPDATE restaurantcapitalassetcosts
       SET status = 'Reversed', reversedby = p_createdby, reversedat = NOW(), reversalreason = btrim(p_reason)
     WHERE assetcostid = p_costid;
    UPDATE restaurantcapitalassets SET updatedby = p_createdby, updatedat = NOW() WHERE capitalassetid = v_c.capitalassetid;
END $$;
CREATE OR REPLACE FUNCTION sprestaurant_capitalasset_reverse(p_farmid TEXT, p_assetid INT, p_reason TEXT,
                                                  p_createdby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_status TEXT; v_number TEXT; r RECORD;
BEGIN
    SELECT a.status, a.assetnumber INTO v_status, v_number
      FROM restaurantcapitalassets a
     WHERE a.capitalassetid = p_assetid AND a.farmid = p_farmid
       FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Asset not found for this company.'; END IF;
    IF v_status = 'Reversed' THEN RAISE EXCEPTION 'This asset has already been reversed.'; END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to reverse an asset.'; END IF;
    IF v_status = 'Disposed' THEN RAISE EXCEPTION 'A disposed asset cannot be reversed.'; END IF;
    -- (329)
    IF EXISTS (SELECT 1 FROM restaurantcapitalassetcosts c
                WHERE c.capitalassetid = p_assetid AND c.farmid = p_farmid
                  AND fnrestaurant_allocated(p_farmid, 'AssetCost', c.assetcostid) > 0) THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this asset. Reverse the payment on Supplier Payments first.';
    END IF;
    IF EXISTS (SELECT 1 FROM restaurantassetdepreciation d
                WHERE d.capitalassetid = p_assetid AND d.status = 'Posted') THEN
        RAISE EXCEPTION 'Depreciation has been posted for this asset. Reverse the depreciation first.';
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    -- One refund per document: an acquisition together with its corrections, or
    -- one added cost. Corrections already handed back their part.
    FOR r IN
        SELECT d.assetcostid, d.cashaccountid,
               (SELECT COALESCE(SUM(x.amountpaid), 0) FROM restaurantcapitalassetcosts x
                 WHERE x.status = 'Posted' AND (x.assetcostid = d.assetcostid OR x.correctionofid = d.assetcostid)) AS netpaid
          FROM restaurantcapitalassetcosts d
         WHERE d.capitalassetid = p_assetid AND d.status = 'Posted' AND d.sourcetype <> 'OriginalCostCorrection'
         ORDER BY d.assetcostid
    LOOP
        IF r.netpaid > 0 THEN
            PERFORM fnrestaurant_post(p_farmid, r.cashaccountid, CURRENT_DATE, r.netpaid, 'AssetPurchaseReversal',
                                      r.assetcostid, 'Reversal of ' || v_number || ': ' || btrim(p_reason), p_createdby,
                                      (SELECT t.cashtxnid FROM restaurantcashtransactions t
                                        WHERE t.sourcetype = 'AssetPurchase' AND t.sourceid = r.assetcostid));
        END IF;
    END LOOP;

    UPDATE restaurantcapitalassetcosts
       SET status = 'Reversed', reversedby = p_createdby, reversedat = NOW(), reversalreason = btrim(p_reason)
     WHERE capitalassetid = p_assetid AND status = 'Posted';
    UPDATE restaurantcapitalassets
       SET status = 'Reversed', reversedby = p_createdby, reversedat = NOW(), reversalreason = btrim(p_reason),
           updatedat = NOW()
     WHERE capitalassetid = p_assetid;
END $$;
CREATE OR REPLACE FUNCTION sprestaurant_capitalasset_list(p_farmid TEXT, p_status TEXT DEFAULT NULL,
                                               p_categoryid INT DEFAULT NULL, p_assetid INT DEFAULT NULL)
RETURNS TABLE(capitalassetid INT, assetnumber TEXT, assetname TEXT, assetcategoryid INT, categoryname TEXT,
              description TEXT, acquisitiondate DATE, inservicedate DATE, location TEXT, serialnumber TEXT,
              supplierid INT, suppliername TEXT, status TEXT, notes TEXT,
              originalcost NUMERIC, residualvalue NUMERIC, depreciableamount NUMERIC,
              usefullifemonths INT, monthlydepreciation NUMERIC, accumulateddepreciation NUMERIC,
              currentbookvalue NUMERIC, remainingdepreciable NUMERIC, isfullydepreciated BOOLEAN,
              costentries INT, depreciationentries INT,
              disposaldate DATE, disposalproceeds NUMERIC, disposalaccountid INT, disposalnotes TEXT,
              createdby TEXT, createdat TIMESTAMP, updatedat TIMESTAMP,
              reversedby TEXT, reversedat TIMESTAMP, reversalreason TEXT,
              acquisitioncost NUMERIC, additionalcost NUMERIC, totalcapitalizedcost NUMERIC,
              amountowed NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT a.capitalassetid, a.assetnumber, a.assetname, a.assetcategoryid, c.categoryname,
           a.description, a.acquisitiondate, a.inservicedate, a.location, a.serialnumber,
           a.supplierid, a.suppliername, a.status, a.notes,
           f.originalcost, f.residualvalue, f.depreciableamount,
           f.usefullifemonths, f.monthlydepreciation, f.accumulateddepreciation,
           f.currentbookvalue, f.remainingdepreciable, f.isfullydepreciated,
           (SELECT COUNT(*)::INT FROM restaurantcapitalassetcosts cc
             WHERE cc.capitalassetid = a.capitalassetid AND cc.status = 'Posted'),
           (SELECT COUNT(*)::INT FROM restaurantassetdepreciation dd
             WHERE dd.capitalassetid = a.capitalassetid AND dd.status = 'Posted'),
           a.disposaldate, a.disposalproceeds, a.disposalaccountid, a.disposalnotes,
           a.createdby, a.createdat, a.updatedat,
           a.reversedby, a.reversedat, a.reversalreason,
           fnrestaurantasset_acquisitioncost(a.capitalassetid),
           fnrestaurantasset_additionalcost(a.capitalassetid),
           f.originalcost,
           -- (329) net of supplier payments applied
           (SELECT (COALESCE(SUM(cc.amount - cc.amountpaid), 0)
                    - COALESCE(SUM(fnrestaurant_allocated(p_farmid, 'AssetCost', cc.assetcostid)), 0))::NUMERIC(14,2)
              FROM restaurantcapitalassetcosts cc
             WHERE cc.capitalassetid = a.capitalassetid AND cc.status = 'Posted')
      FROM restaurantcapitalassets a
      LEFT JOIN restaurantassetcategories c ON c.assetcategoryid = a.assetcategoryid
     CROSS JOIN LATERAL fnrestaurantasset_financials(a.capitalassetid) f
     WHERE a.farmid = p_farmid
       AND (p_status IS NULL OR a.status = p_status)
       AND (p_categoryid IS NULL OR a.assetcategoryid = p_categoryid)
       AND (p_assetid IS NULL OR a.capitalassetid = p_assetid)
     ORDER BY a.acquisitiondate DESC, a.capitalassetid DESC;
$$;
CREATE OR REPLACE FUNCTION sprestaurant_capitalasset_summary(p_farmid TEXT, p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS TABLE(totalassets INT, activeassets INT, draftassets INT, disposedassets INT, fullydepreciated INT,
              totalassetcost NUMERIC, accumulateddepreciation NUMERIC, currentbookvalue NUMERIC,
              addedinperiod NUMERIC, addedcount INT, amountowed NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH live AS (
        SELECT a.capitalassetid, a.status, f.*
          FROM restaurantcapitalassets a
         CROSS JOIN LATERAL fnrestaurantasset_financials(a.capitalassetid) f
         WHERE a.farmid = p_farmid AND a.status <> 'Reversed'
    )
    SELECT COUNT(*)::INT,
           COUNT(*) FILTER (WHERE l.status = 'Active')::INT,
           COUNT(*) FILTER (WHERE l.status = 'Draft')::INT,
           COUNT(*) FILTER (WHERE l.status = 'Disposed')::INT,
           COUNT(*) FILTER (WHERE l.status = 'FullyDepreciated')::INT,
           COALESCE(SUM(l.originalcost), 0)::NUMERIC(14,2),
           COALESCE(SUM(l.accumulateddepreciation), 0)::NUMERIC(14,2),
           COALESCE(SUM(l.currentbookvalue), 0)::NUMERIC(14,2),
           COALESCE((SELECT SUM(cc.amount) FROM restaurantcapitalassetcosts cc
                      WHERE cc.farmid = p_farmid AND cc.status = 'Posted'
                        AND (p_from IS NULL OR cc.costdate >= p_from)
                        AND (p_to IS NULL OR cc.costdate <= p_to)), 0)::NUMERIC(14,2),
           COALESCE((SELECT COUNT(*) FROM restaurantcapitalassets aa
                      WHERE aa.farmid = p_farmid AND aa.status <> 'Reversed'
                        AND (p_from IS NULL OR aa.acquisitiondate >= p_from)
                        AND (p_to IS NULL OR aa.acquisitiondate <= p_to)), 0)::INT,
           -- (329) net of supplier payments applied
           COALESCE((SELECT SUM(cc.amount - cc.amountpaid - fnrestaurant_allocated(p_farmid, 'AssetCost', cc.assetcostid))
                       FROM restaurantcapitalassetcosts cc
                      WHERE cc.farmid = p_farmid AND cc.status = 'Posted'), 0)::NUMERIC(14,2)
      FROM live l;
$$;
CREATE OR REPLACE FUNCTION sprestaurant_capitalasset_costs(p_farmid TEXT, p_assetid INT)
RETURNS TABLE(assetcostid INT, capitalassetid INT, costdate DATE, description TEXT, costcategory TEXT,
              amount NUMERIC, sourcetype TEXT, correctionofid INT, supplierid INT, suppliername TEXT,
              paymentmethod TEXT, amountpaid NUMERIC, balance NUMERIC, paymentstatus TEXT, duedate DATE,
              cashaccountid INT, cashaccountname TEXT, documentamount NUMERIC,
              status TEXT, createdby TEXT, createdat TIMESTAMP,
              reversedby TEXT, reversedat TIMESTAMP, reversalreason TEXT)
LANGUAGE sql STABLE AS $$
    SELECT c.assetcostid, c.capitalassetid, c.costdate, c.description, c.costcategory,
           c.amount, c.sourcetype, c.correctionofid, c.supplierid, c.suppliername,
           c.paymentmethod, c.amountpaid,
           -- (329) balance and status net of supplier payments applied
           CASE WHEN c.sourcetype = 'OriginalCostCorrection' THEN 0 ELSE doc.amt - doc.paid - al.x END,
           CASE WHEN c.sourcetype = 'OriginalCostCorrection' THEN NULL
                WHEN doc.amt - doc.paid - al.x <= 0 THEN 'Paid'
                WHEN doc.paid + al.x <= 0 THEN 'Unpaid' ELSE 'Partial' END,
           c.duedate, c.cashaccountid, ca.name,
           CASE WHEN c.sourcetype = 'OriginalCostCorrection' THEN NULL ELSE doc.amt END,
           c.status, c.createdby, c.createdat, c.reversedby, c.reversedat, c.reversalreason
      FROM restaurantcapitalassetcosts c
      LEFT JOIN restaurantcashaccounts ca ON ca.cashaccountid = c.cashaccountid
     CROSS JOIN LATERAL (
            SELECT COALESCE(SUM(x.amount), 0)::NUMERIC(14,2) AS amt, COALESCE(SUM(x.amountpaid), 0)::NUMERIC(14,2) AS paid
              FROM restaurantcapitalassetcosts x
             WHERE (x.assetcostid = c.assetcostid OR x.correctionofid = c.assetcostid)
               AND (x.status = 'Posted' OR c.status <> 'Posted')) doc
     CROSS JOIN LATERAL (SELECT CASE WHEN c.status = 'Posted'
                                     THEN fnrestaurant_allocated(p_farmid, 'AssetCost', c.assetcostid) ELSE 0 END AS x) al
     WHERE c.farmid = p_farmid AND c.capitalassetid = p_assetid
     ORDER BY c.costdate, c.assetcostid;
$$;
CREATE OR REPLACE FUNCTION sprestaurant_capitalasset_payables(p_farmid TEXT)
RETURNS TABLE(assetcostid INT, capitalassetid INT, assetnumber TEXT, assetname TEXT, sourcetype TEXT,
              supplierid INT, suppliername TEXT, documentdate DATE, duedate DATE,
              amount NUMERIC, amountpaid NUMERIC, balance NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT d.assetcostid, a.capitalassetid, a.assetnumber, a.assetname, d.sourcetype,
           d.supplierid, d.suppliername, d.costdate, d.duedate, x.amt,
           -- (329) paid = at purchase + supplier payments applied
           (x.paid + al.x)::NUMERIC(14,2), (x.amt - x.paid - al.x)::NUMERIC(14,2)
      FROM restaurantcapitalassetcosts d
      JOIN restaurantcapitalassets a ON a.capitalassetid = d.capitalassetid
     CROSS JOIN LATERAL (
            SELECT COALESCE(SUM(y.amount), 0)::NUMERIC(14,2) AS amt, COALESCE(SUM(y.amountpaid), 0)::NUMERIC(14,2) AS paid
              FROM restaurantcapitalassetcosts y
             WHERE y.status = 'Posted' AND (y.assetcostid = d.assetcostid OR y.correctionofid = d.assetcostid)) x
     CROSS JOIN LATERAL (SELECT fnrestaurant_allocated(p_farmid, 'AssetCost', d.assetcostid) AS x) al
     WHERE d.farmid = p_farmid AND d.status = 'Posted' AND d.sourcetype <> 'OriginalCostCorrection'
       AND x.amt - x.paid - al.x > 0
     ORDER BY COALESCE(d.duedate, d.costdate), d.assetcostid;
$$;

-- -----------------------------------------------------------------------------
-- 11. Cash Flow, P&L and the profit-vs-cash bridge. Copied from 328 with only
--     the marked (329) changes; same signatures and result columns.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sprestaurantcashflow_detail(p_farmid TEXT, p_fromdate TIMESTAMP DEFAULT NULL,
                                            p_todate TIMESTAMP DEFAULT NULL)
RETURNS TABLE(rowsource TEXT, offledger BOOLEAN, sourcerowid INT, cashaccountid INT, accountname TEXT,
              transactiondate TIMESTAMP, transactiontype TEXT, sourcetype TEXT, sourceid INT,
              istransfer BOOLEAN, amount NUMERIC, description TEXT, flowgroup TEXT, category TEXT,
              createdat TIMESTAMP)
LANGUAGE sql STABLE AS $$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname, r.transactiondate,
           r.transactiontype, r.sourcetype, r.sourceid, r.istransfer, r.amount, r.description, r.flowgroup,
           CASE r.sourcetype
               WHEN 'OrderPayment' THEN 'Sales (' || COALESCE(NULLIF(btrim(p.paymentmethod), ''), 'Cash') || ')'
               WHEN 'OrderRefund' THEN 'Refunds to customers'
               WHEN 'Expense' THEN COALESCE(NULLIF(btrim(e.categoryname), ''), 'Uncategorised')
               WHEN 'ExpenseReversal' THEN 'Expense corrections'
               WHEN 'GiftCardSale' THEN 'Gift card sales'
               WHEN 'GiftCardReload' THEN 'Gift card sales'
               WHEN 'OwnerContribution' THEN 'Owner contributions'
               WHEN 'OwnerDraw' THEN 'Owner drawings'
               WHEN 'OwnerContributionReversal' THEN 'Owner money corrections'
               WHEN 'OwnerDrawReversal' THEN 'Owner money corrections'
               WHEN 'LoanReceived' THEN 'Loans received'
               WHEN 'LoanRepayment' THEN 'Loan repayments'
               WHEN 'LoanRepaymentReversal' THEN 'Loan corrections'
               WHEN 'LoanReceivedReversal' THEN 'Loan corrections'
               WHEN 'ShiftVariance' THEN 'Cash over / short'
               WHEN 'CountVariance' THEN 'Cash over / short'
               WHEN 'CountVarianceReversal' THEN 'Cash over / short'
               WHEN 'Payroll' THEN 'Staff wages (net pay)'
               WHEN 'EmployeeLoanDisbursement' THEN 'Staff advances paid out'
               WHEN 'EmployeeLoanReversal' THEN 'Staff advance corrections'
               WHEN 'EmployeeLoanRepayment' THEN 'Staff advances repaid'
               WHEN 'EmployeeLoanRepaymentReversal' THEN 'Staff advance corrections'
               -- 328: capital investments (Operating, as in Poultry: no Investing group)
               WHEN 'AssetPurchase' THEN 'Capital investments'
               WHEN 'AssetPurchaseReversal' THEN 'Capital investment corrections'
               WHEN 'AssetDisposal' THEN 'Capital investments sold'
               -- 329: stock bought and suppliers paid (Operating)
               WHEN 'StockPurchase' THEN 'Stock purchases'
               WHEN 'StockPurchaseReversal' THEN 'Stock purchase corrections'
               WHEN 'SupplierPayment' THEN 'Supplier payments'
               WHEN 'SupplierPaymentReversal' THEN 'Supplier payment corrections'
               ELSE 'Other' END::TEXT,
           r.createdat
      FROM sprestaurantcashflow_rows(p_farmid, p_fromdate, p_todate) r
      LEFT JOIN restaurantorderpayments p ON r.sourcetype = 'OrderPayment' AND p.orderpaymentid = r.sourceid
      LEFT JOIN restaurantexpenses e ON r.sourcetype = 'Expense' AND e.expenseid = r.sourceid;
$$;
CREATE OR REPLACE FUNCTION sprestaurant_report_pnl_lines(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(section TEXT, linekey TEXT, label TEXT, amount NUMERIC, sortorder INT)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE v_sales NUMERIC; v_disc NUMERIC; v_sc NUMERIC; v_fee NUMERIC; v_ref NUMERIC; v_cogs NUMERIC;
        v_int NUMERIC; v_fees NUMERIC; v_var NUMERIC; v_wages NUMERIC; v_slint NUMERIC; v_dep NUMERIC;
        v_purch NUMERIC; v_used NUMERIC; v_waste NUMERIC; v_adj NUMERIC;
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
           COALESCE(SUM(d.deferredcost) FILTER (WHERE d.drawtype NOT IN ('OrderDeduction', 'Waste')), 0)
      INTO v_used, v_waste, v_adj
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
BEGIN
    SELECT s.net_profit, s.revenue INTO v_profit, v_rev
      FROM sprestaurant_report_pnl_summary(p_farmid, p_from, p_to) s;

    -- 329: stock USED is profit without cash; stock PURCHASED (expense when
    -- purchased) is profit whose cash moves when it is paid.
    SELECT COALESCE(-SUM(l.amount) FILTER (WHERE l.linekey IN ('recipe_cost', 'stock_waste', 'stock_adjustments')), 0),
           COALESCE(-SUM(l.amount) FILTER (WHERE l.linekey = 'stock_purchased'), 0)
      INTO v_cogs, v_purch_pl
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
                                                   + v_purch_pl + v_stock_paid), 2),
         'check', 'Should be zero. Anything else is a ledger row this bridge does not classify yet.');
END $$;

-- -----------------------------------------------------------------------------
-- 12. Deferred inventory cost page (Poultry 288 / 289, read-only). One row per
--     purchase lot; the cards and the table read the same rows.
-- -----------------------------------------------------------------------------
CREATE FUNCTION fnrestaurant_deferredpurchase_rows(p_farmid TEXT)
RETURNS TABLE(purchaseid INT, purchasedate DATE, ingredientid INT, itemname TEXT, category TEXT, unit TEXT,
              supplierid INT, suppliername TEXT, purchasedquantity NUMERIC, consumedquantity NUMERIC,
              remainingquantity NUMERIC, operationalcost NUMERIC, deferredtotalcost NUMERIC, recognizedcost NUMERIC,
              deferredremainingcost NUMERIC, recognitionpercent NUMERIC, allocatedrecognizedcost NUMERIC,
              recognitiondrift NUMERIC, costrecognitionmethod TEXT, recognitionmethodlabel TEXT, status TEXT,
              exceptionreason TEXT, recognitionevents INT, lastrecognitiondate DATE, costingmethod TEXT,
              queueposition INT, quantityaheadinqueue NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH lots AS (
        SELECT p.*, i.name AS iname, i.category AS icat, COALESCE(i.currentstock, 0) AS stock,
               COALESCE(s.name, p.suppliername) AS sname,
               COALESCE((SELECT SUM(d.deferredcost) FROM restaurantstockdraws d WHERE d.purchaseid = p.purchaseid), 0) AS drawn,
               (SELECT COUNT(*)::INT FROM restaurantstockdraws d WHERE d.purchaseid = p.purchaseid AND d.deferredcost <> 0) AS events,
               (SELECT MAX(d.drawdate) FROM restaurantstockdraws d WHERE d.purchaseid = p.purchaseid AND d.deferredcost <> 0) AS lastdate
          FROM restaurantpurchases p
          JOIN restaurantingredients i ON i.ingredientid = p.ingredientid
          LEFT JOIN restaurantsuppliers s ON s.restaurantsupplierid = p.supplierid
         WHERE p.farmid = p_farmid AND p.status = 'Posted'
    ), q AS (
        -- The engine's own order: stock with no purchase behind it first, then
        -- lots oldest first.
        SELECT l.purchaseid,
               (ROW_NUMBER() OVER (PARTITION BY l.ingredientid ORDER BY l.purchasedate, l.purchaseid))::INT AS pos,
               GREATEST(l.stock - SUM(l.remainingquantity) OVER (PARTITION BY l.ingredientid), 0)
               + COALESCE(SUM(l.remainingquantity) OVER (PARTITION BY l.ingredientid ORDER BY l.purchasedate, l.purchaseid
                                                          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS ahead
          FROM lots l WHERE l.remainingquantity > 0
    )
    SELECT l.purchaseid, l.purchasedate, l.ingredientid, l.iname::TEXT, l.icat::TEXT, l.unit::TEXT,
           l.supplierid, l.sname::TEXT, l.quantity, l.quantity - l.remainingquantity, l.remainingquantity,
           l.totalcost, l.deferredtotalcost, (l.deferredtotalcost - l.deferredremainingcost)::NUMERIC(14,2),
           l.deferredremainingcost,
           CASE WHEN l.deferredtotalcost > 0
                THEN ROUND((l.deferredtotalcost - l.deferredremainingcost) / l.deferredtotalcost * 100, 1) ELSE 0 END,
           l.drawn::NUMERIC(14,2),
           ((l.deferredtotalcost - l.deferredremainingcost) - l.drawn)::NUMERIC(14,2),
           l.costmode,
           CASE WHEN l.costmode = 'EXPENSE_WHEN_CONSUMED' THEN 'Expense when used' ELSE 'Expense when purchased' END,
           CASE WHEN (l.remainingquantity = 0 AND l.deferredremainingcost > 0)
                  OR ABS((l.deferredtotalcost - l.deferredremainingcost) - l.drawn) > 0.05 THEN 'Exception'
                WHEN l.costmode = 'EXPENSE_WHEN_PURCHASED' OR l.deferredtotalcost = 0 THEN 'Expensed at purchase'
                WHEN l.deferredremainingcost >= l.deferredtotalcost THEN 'Not yet expensed'
                WHEN l.deferredremainingcost <= 0 THEN 'Fully expensed'
                ELSE 'Partly expensed' END,
           CASE WHEN l.remainingquantity = 0 AND l.deferredremainingcost > 0
                  THEN 'Cost is still deferred but none of this stock is left.'
                WHEN ABS((l.deferredtotalcost - l.deferredremainingcost) - l.drawn) > 0.05
                  THEN 'Lot balance says ' || (l.deferredtotalcost - l.deferredremainingcost) || '; its usages say ' || l.drawn || '.'
           END::TEXT,
           l.events, l.lastdate, 'FIFO'::TEXT, q.pos, COALESCE(q.ahead, 0)::NUMERIC
      FROM lots l
      LEFT JOIN q ON q.purchaseid = l.purchaseid;
$$;

CREATE FUNCTION sprestaurant_deferredpurchase_getall(p_farmid TEXT, p_scope TEXT DEFAULT 'DEFERRED',
                                                     p_ingredientid INT DEFAULT NULL, p_supplierid INT DEFAULT NULL,
                                                     p_category TEXT DEFAULT NULL, p_fromdate DATE DEFAULT NULL,
                                                     p_todate DATE DEFAULT NULL, p_search TEXT DEFAULT NULL)
RETURNS TABLE(purchaseid INT, purchasedate DATE, ingredientid INT, itemname TEXT, category TEXT, unit TEXT,
              supplierid INT, suppliername TEXT, purchasedquantity NUMERIC, consumedquantity NUMERIC,
              remainingquantity NUMERIC, operationalcost NUMERIC, deferredtotalcost NUMERIC, recognizedcost NUMERIC,
              deferredremainingcost NUMERIC, recognitionpercent NUMERIC, allocatedrecognizedcost NUMERIC,
              recognitiondrift NUMERIC, costrecognitionmethod TEXT, recognitionmethodlabel TEXT, status TEXT,
              exceptionreason TEXT, recognitionevents INT, lastrecognitiondate DATE, costingmethod TEXT,
              queueposition INT, quantityaheadinqueue NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT r.* FROM fnrestaurant_deferredpurchase_rows(p_farmid) r
     WHERE CASE upper(COALESCE(p_scope, 'DEFERRED'))
                WHEN 'DEFERRED'   THEN r.deferredremainingcost > 0
                WHEN 'RECOGNIZED' THEN r.deferredtotalcost > 0 AND r.deferredremainingcost <= 0
                WHEN 'EXCEPTION'  THEN r.status = 'Exception'
                ELSE TRUE END
       AND (p_ingredientid IS NULL OR r.ingredientid = p_ingredientid)
       AND (p_supplierid IS NULL OR r.supplierid = p_supplierid)
       AND (p_category IS NULL OR lower(r.category) = lower(p_category))
       AND (p_fromdate IS NULL OR r.purchasedate >= p_fromdate)
       AND (p_todate IS NULL OR r.purchasedate <= p_todate)
       AND (p_search IS NULL OR btrim(p_search) = ''
            OR r.itemname ILIKE '%' || btrim(p_search) || '%'
            OR COALESCE(r.suppliername, '') ILIKE '%' || btrim(p_search) || '%'
            OR r.purchaseid::TEXT = regexp_replace(btrim(p_search), '^(PO-|#)', '', 'i'))
     ORDER BY r.purchasedate DESC, r.purchaseid DESC;
$$;

CREATE FUNCTION sprestaurant_deferredpurchase_summary(p_farmid TEXT, p_scope TEXT DEFAULT 'DEFERRED',
                                                      p_ingredientid INT DEFAULT NULL, p_supplierid INT DEFAULT NULL,
                                                      p_category TEXT DEFAULT NULL, p_fromdate DATE DEFAULT NULL,
                                                      p_todate DATE DEFAULT NULL, p_search TEXT DEFAULT NULL)
RETURNS TABLE(remainingdeferredcost NUMERIC, recognizedcost NUMERIC, deferredbasis NUMERIC, operationalcost NUMERIC,
              purchasecount INT, deferredpurchases INT, fullyrecognized INT, notrecognized INT, exceptions INT,
              exceptiondrift NUMERIC, recognitionpercent NUMERIC, blockedpurchases INT, blockedcost NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH r AS (SELECT * FROM sprestaurant_deferredpurchase_getall(p_farmid, p_scope, p_ingredientid, p_supplierid,
                                                                    p_category, p_fromdate, p_todate, p_search))
    SELECT COALESCE(SUM(r.deferredremainingcost), 0)::NUMERIC(14,2),
           COALESCE(SUM(r.recognizedcost), 0)::NUMERIC(14,2),
           COALESCE(SUM(r.deferredtotalcost), 0)::NUMERIC(14,2),
           COALESCE(SUM(r.operationalcost), 0)::NUMERIC(14,2),
           COUNT(*)::INT,
           COUNT(*) FILTER (WHERE r.deferredremainingcost > 0)::INT,
           COUNT(*) FILTER (WHERE r.deferredtotalcost > 0 AND r.deferredremainingcost <= 0)::INT,
           COUNT(*) FILTER (WHERE r.deferredtotalcost > 0 AND r.recognizedcost = 0)::INT,
           COUNT(*) FILTER (WHERE r.status = 'Exception')::INT,
           COALESCE(SUM(r.recognitiondrift) FILTER (WHERE r.status = 'Exception'), 0)::NUMERIC(14,2),
           CASE WHEN COALESCE(SUM(r.deferredtotalcost), 0) > 0
                THEN ROUND(SUM(r.recognizedcost) / SUM(r.deferredtotalcost) * 100, 1) ELSE 0 END,
           -- Queued behind older stock: nothing can draw on it until that goes.
           COUNT(*) FILTER (WHERE r.deferredremainingcost > 0 AND r.quantityaheadinqueue > 0)::INT,
           COALESCE(SUM(r.deferredremainingcost) FILTER (WHERE r.quantityaheadinqueue > 0), 0)::NUMERIC(14,2)
      FROM r;
$$;

-- What moved one purchase's cost into Profit & Loss.
CREATE FUNCTION sprestaurant_deferredpurchase_history(p_farmid TEXT, p_purchaseid INT)
RETURNS TABLE(drawid INT, useddate DATE, sourcetype TEXT, sourcelabel TEXT, quantitydrawn NUMERIC, unit TEXT,
              unitcostatdraw NUMERIC, operationalcost NUMERIC, recognizedcost NUMERIC, recognitionoutcome TEXT,
              isreversed BOOLEAN)
LANGUAGE sql STABLE AS $$
    SELECT d.drawid, d.drawdate,
           CASE d.drawtype WHEN 'OrderDeduction' THEN 'Sale' WHEN 'Waste' THEN 'Waste'
                           WHEN 'StockTake' THEN 'Stock take' WHEN 'Shortfall' THEN 'Used before delivery'
                           ELSE 'Adjustment' END::TEXT,
           COALESCE(d.reference, d.drawtype)::TEXT,
           d.quantity, p.unit, d.unitcost, ROUND(d.quantity * d.unitcost, 2), d.deferredcost,
           CASE WHEN d.costmode = 'EXPENSE_WHEN_CONSUMED' THEN 'Expensed now' ELSE 'Already expensed at purchase' END::TEXT,
           FALSE
      FROM restaurantstockdraws d
      JOIN restaurantpurchases p ON p.purchaseid = d.purchaseid
     WHERE d.farmid = p_farmid AND d.purchaseid = p_purchaseid
     ORDER BY d.drawdate, d.drawid;
$$;

-- -----------------------------------------------------------------------------
-- 13. Verification (read-only)
-- -----------------------------------------------------------------------------
DO $$
DECLARE v_missing TEXT;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
      FROM unnest(ARRAY[
            'fnrestaurant_costmode', 'sprestaurant_costmode_list', 'sprestaurant_costmode_set',
            'fnrestaurant_ingredient_refreshcost', 'fnrestaurant_stock_draw',
            'sprestaurant_purchase_create', 'sprestaurant_purchase_reverse', 'sprestaurant_purchase_list',
            'fnrestaurant_allocated', 'fnrestaurant_payables',
            'sprestaurant_supplierbalances', 'sprestaurant_supplierbalancesummary', 'sprestaurant_supplieropenpurchases',
            'sprestaurant_supplierpayment_record', 'sprestaurant_supplierpayment_reverse',
            'sprestaurant_supplierpayment_history', 'sprestaurant_supplierpayment_allocations',
            'sprestaurant_supplierstatement', 'sprestaurant_expense_record', 'sprestaurant_expense_insert',
            'sprestaurant_expense_delete', 'sprestaurant_expense_payments', 'sprestaurant_recipe_deduct_order',
            'sprestaurant_ingredient_adjust_stock', 'sprestaurant_wastelog_insert', 'sprestaurant_stocktake_complete',
            'sprestaurant_ingredient_delete', 'sprestaurant_supplier_delete',
            'fnrestaurant_deferredpurchase_rows', 'sprestaurant_deferredpurchase_getall',
            'sprestaurant_deferredpurchase_summary', 'sprestaurant_deferredpurchase_history',
            'sprestaurant_capitalasset_payables', 'sprestaurantcashflow_detail', 'sprestaurant_report_pnl_lines',
            'sprestaurant_report_cash_profit_bridge']) f
     WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND p.proname = f);
    IF v_missing IS NOT NULL THEN RAISE EXCEPTION '329 verification failed, missing: %', v_missing; END IF;
    -- No new source type may look like financing to the Cash Flow classifier.
    IF EXISTS (SELECT 1 FROM unnest(ARRAY['StockPurchase', 'StockPurchaseReversal', 'SupplierPayment',
                                          'SupplierPaymentReversal']) t WHERE t LIKE 'Loan%' OR t LIKE 'Owner%') THEN
        RAISE EXCEPTION '329 verification failed: a source type would classify as financing';
    END IF;
END $$;

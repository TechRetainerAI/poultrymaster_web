-- Migration 229: Restaurant Accounting & Financial + Settings completion
-- Applied: 2026-08-30

CREATE TABLE IF NOT EXISTS restaurantexpensecategories (
    expensecategoryid    SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    name                 TEXT NOT NULL,
    isactive             BOOLEAN DEFAULT TRUE,
    sortorder            INT DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ix_restaurantexpensecategories_farm ON restaurantexpensecategories(farmid);

CREATE TABLE IF NOT EXISTS restaurantexpenses (
    expenseid            SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    expensedate          DATE NOT NULL DEFAULT CURRENT_DATE,
    categoryid           INT REFERENCES restaurantexpensecategories(expensecategoryid) ON DELETE SET NULL,
    categoryname         TEXT,
    description          TEXT NOT NULL,
    amount               NUMERIC(12,2) NOT NULL,
    paymentmethod        TEXT DEFAULT 'Cash',
    suppliername         TEXT,
    receiptref           TEXT,
    status               TEXT DEFAULT 'Approved', -- Draft, Approved, Rejected
    createdby            TEXT,
    createdat            TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantexpenses_farm ON restaurantexpenses(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantexpenses_date ON restaurantexpenses(farmid, expensedate DESC);

CREATE TABLE IF NOT EXISTS restaurantreceipttemplates (
    receipttemplateid    SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL UNIQUE,
    headertext           TEXT,
    footertext           TEXT,
    showlogo             BOOLEAN DEFAULT TRUE,
    showtaxdetails       BOOLEAN DEFAULT TRUE,
    showservernames      BOOLEAN DEFAULT TRUE,
    thanksmessage        TEXT DEFAULT 'Thank you for dining with us!',
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);

-- SP: Expense categories
CREATE OR REPLACE FUNCTION sprestaurant_expensecategory_list(p_farmid TEXT) RETURNS TABLE (expensecategoryid INT, farmid TEXT, name TEXT, isactive BOOLEAN, sortorder INT) AS $$
BEGIN RETURN QUERY SELECT c.* FROM restaurantexpensecategories c WHERE c.farmid=p_farmid ORDER BY c.sortorder, c.name; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_expensecategory_insert(p_farmid TEXT, p_name TEXT) RETURNS INT AS $$
DECLARE v_id INT; BEGIN INSERT INTO restaurantexpensecategories (farmid, name) VALUES (p_farmid, p_name) RETURNING expensecategoryid INTO v_id; RETURN v_id; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_expensecategory_delete(p_id INT, p_farmid TEXT) RETURNS VOID AS $$
BEGIN DELETE FROM restaurantexpensecategories WHERE expensecategoryid=p_id AND farmid=p_farmid; END; $$ LANGUAGE plpgsql;

-- SP: Expenses
CREATE OR REPLACE FUNCTION sprestaurant_expense_list(p_farmid TEXT, p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS TABLE (expenseid INT, farmid TEXT, expensedate DATE, categoryid INT, categoryname TEXT, description TEXT, amount NUMERIC, paymentmethod TEXT, suppliername TEXT, receiptref TEXT, status TEXT, createdby TEXT, createdat TIMESTAMP) AS $$
BEGIN RETURN QUERY SELECT e.* FROM restaurantexpenses e WHERE e.farmid=p_farmid AND (p_from IS NULL OR e.expensedate>=p_from) AND (p_to IS NULL OR e.expensedate<=p_to) ORDER BY e.expensedate DESC; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_expense_insert(p_farmid TEXT, p_expensedate DATE, p_categoryid INT, p_categoryname TEXT, p_description TEXT, p_amount NUMERIC, p_paymentmethod TEXT, p_suppliername TEXT, p_receiptref TEXT, p_createdby TEXT) RETURNS INT AS $$
DECLARE v_id INT; BEGIN INSERT INTO restaurantexpenses (farmid, expensedate, categoryid, categoryname, description, amount, paymentmethod, suppliername, receiptref, createdby)
VALUES (p_farmid, p_expensedate, p_categoryid, p_categoryname, p_description, p_amount, p_paymentmethod, p_suppliername, p_receiptref, p_createdby) RETURNING expenseid INTO v_id; RETURN v_id; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_expense_delete(p_id INT, p_farmid TEXT) RETURNS VOID AS $$
BEGIN DELETE FROM restaurantexpenses WHERE expenseid=p_id AND farmid=p_farmid; END; $$ LANGUAGE plpgsql;

-- SP: P&L Report
CREATE OR REPLACE FUNCTION sprestaurant_report_pnl(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE (
    total_revenue NUMERIC, total_cogs NUMERIC, gross_profit NUMERIC,
    total_expenses NUMERIC, net_profit NUMERIC,
    expense_by_category TEXT, expense_amount NUMERIC
) AS $$
BEGIN
    -- Revenue from orders
    CREATE TEMP TABLE IF NOT EXISTS _pnl_revenue AS
    SELECT COALESCE(SUM(o.subtotal),0) AS rev FROM restaurantorders o
    WHERE o.farmid=p_farmid AND o.createdat::DATE BETWEEN p_from AND p_to AND o.status='Completed';

    -- COGS from recipes
    CREATE TEMP TABLE IF NOT EXISTS _pnl_cogs AS
    SELECT COALESCE(SUM(
        oi.quantity * COALESCE((SELECT SUM(r.quantity * (1 + r.wastepercent/100) * i.costperunit)
        FROM restaurantrecipes r JOIN restaurantingredients i ON i.ingredientid=r.ingredientid AND i.farmid=r.farmid
        WHERE r.menuitemid=oi.menuitemid AND r.farmid=oi.farmid), 0)
    ), 0) AS cogs
    FROM restaurantorderitems oi JOIN restaurantorders o ON o.orderid=oi.orderid
    WHERE oi.farmid=p_farmid AND o.createdat::DATE BETWEEN p_from AND p_to AND o.status='Completed' AND oi.status!='Cancelled';

    -- Expenses by category
    RETURN QUERY
    SELECT (SELECT rev FROM _pnl_revenue), (SELECT cogs FROM _pnl_cogs),
        (SELECT rev FROM _pnl_revenue) - (SELECT cogs FROM _pnl_cogs),
        COALESCE(SUM(e.amount),0), (SELECT rev FROM _pnl_revenue) - (SELECT cogs FROM _pnl_cogs) - COALESCE(SUM(e.amount),0),
        COALESCE(e.categoryname, 'Uncategorized'), COALESCE(SUM(e.amount),0)
    FROM restaurantexpenses e WHERE e.farmid=p_farmid AND e.expensedate BETWEEN p_from AND p_to
    GROUP BY e.categoryname;

    DROP TABLE IF EXISTS _pnl_revenue; DROP TABLE IF EXISTS _pnl_cogs;
END; $$ LANGUAGE plpgsql;

-- Receipt template
CREATE OR REPLACE FUNCTION sprestaurant_receipttemplate_get(p_farmid TEXT) RETURNS TABLE (receipttemplateid INT, farmid TEXT, headertext TEXT, footertext TEXT, showlogo BOOLEAN, showtaxdetails BOOLEAN, showservernames BOOLEAN, thanksmessage TEXT, createdat TIMESTAMP, updatedat TIMESTAMP) AS $$
BEGIN RETURN QUERY SELECT r.* FROM restaurantreceipttemplates r WHERE r.farmid=p_farmid; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_receipttemplate_upsert(p_farmid TEXT, p_headertext TEXT, p_footertext TEXT, p_showlogo BOOLEAN, p_showtaxdetails BOOLEAN, p_showservernames BOOLEAN, p_thanksmessage TEXT) RETURNS VOID AS $$
BEGIN INSERT INTO restaurantreceipttemplates (farmid, headertext, footertext, showlogo, showtaxdetails, showservernames, thanksmessage)
VALUES (p_farmid, p_headertext, p_footertext, p_showlogo, p_showtaxdetails, p_showservernames, p_thanksmessage)
ON CONFLICT (farmid) DO UPDATE SET headertext=p_headertext, footertext=p_footertext, showlogo=p_showlogo,
    showtaxdetails=p_showtaxdetails, showservernames=p_showservernames, thanksmessage=p_thanksmessage, updatedat=NOW(); END; $$ LANGUAGE plpgsql;

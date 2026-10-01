-- =============================================================================
-- 337_RestaurantExpenseUpdate.postgres.sql
--
-- Edit a Restaurant expense, as Poultry's Edit Expense does (spexpense_update,
-- 238/245/269): date, category, description, amount, payment method, the cash
-- account, and the supplier / amount paid now / due date that live in 329's
-- restaurantexpensepayables side table. No column is added to
-- restaurantexpenses (it is read with SELECT e.* and by ordinal).
--
-- THE MONEY. The ledger is append-only and posts a document once per
-- (sourcetype, sourceid). An expense's first payment is ('Expense', expenseid).
-- Each edit writes one restaurantexpenserevisions row (the audit: what it was,
-- what it became, who, when) and, only when the payment itself changed (amount
-- paid now, account or date):
--     ('ExpenseEditReversal', revisionid)  the live posting, reversed on ITS date
--     ('ExpenseEdit',         revisionid)  the new payment, on the new date
-- so every edit is a new pair of unique keys and nothing is rewritten. The live
-- posting of an expense is therefore its 'Expense' row or its latest
-- 'ExpenseEdit' row -- whichever has not been reversed
-- (fnrestaurant_expense_liveposting). Both dates must be open days (a closed
-- day's cash never moves); no future date.
--
-- GUARDS (Poultry 245's wording): once supplier payments are allocated to the
-- expense, what is still owed (amount - paid now) cannot drop below them, and
-- the supplier cannot change. System-generated expense rows: none exist -- every
-- restaurantexpenses row is written by sprestaurant_expense_record (payroll,
-- internal use, stock and assets post elsewhere) -- so there is nothing to
-- refuse; the check is documented here rather than invented.
--
-- Re-emits: sprestaurant_expense_delete (329; now reverses whichever posting is
-- live), sprestaurantcashflow_detail and sprestaurant_report_cash_profit_bridge
-- (333; the two new source types are expense cash). Re-run order:
-- 323 -> 324 -> 326 -> 328 -> 329 -> 330 -> 333 -> 335 -> 337.
-- =============================================================================

DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname IN ('sprestaurant_expense_update', 'fnrestaurant_expense_liveposting',
                                                     'sprestaurant_expense_payments')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

CREATE TABLE IF NOT EXISTS restaurantexpenserevisions (
    revisionid      SERIAL PRIMARY KEY,
    farmid          TEXT NOT NULL,
    expenseid       INT NOT NULL,          -- no FK: the history outlives a deleted expense
    oldexpensedate  DATE, newexpensedate DATE,
    oldamount       NUMERIC(14,2), newamount NUMERIC(14,2),
    oldamountpaid   NUMERIC(14,2), newamountpaid NUMERIC(14,2),
    oldcashaccountid INT, newcashaccountid INT,
    olddescription  TEXT, newdescription TEXT,
    oldcategory     TEXT, newcategory TEXT,
    oldpaymentmethod TEXT, newpaymentmethod TEXT,
    oldsupplierid   INT, newsupplierid INT,
    movedcash       BOOLEAN NOT NULL DEFAULT FALSE,
    editedby        TEXT,
    editedat        TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantexpenserevisions_expense ON restaurantexpenserevisions (expenseid);

-- The expense's payment that is still standing, or no row.
CREATE FUNCTION fnrestaurant_expense_liveposting(p_farmid TEXT, p_expenseid INT)
RETURNS SETOF restaurantcashtransactions LANGUAGE sql STABLE AS $$
    SELECT t.* FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid
       AND ((t.sourcetype = 'Expense' AND t.sourceid = p_expenseid)
            OR (t.sourcetype = 'ExpenseEdit' AND t.sourceid IN
                  (SELECT v.revisionid FROM restaurantexpenserevisions v WHERE v.expenseid = p_expenseid)))
       AND NOT EXISTS (SELECT 1 FROM restaurantcashtransactions r WHERE r.reversesid = t.cashtxnid)
     ORDER BY t.cashtxnid DESC;
$$;

CREATE FUNCTION sprestaurant_expense_update(
    p_id INT, p_farmid TEXT, p_expensedate DATE, p_categoryid INT, p_categoryname TEXT, p_description TEXT,
    p_amount NUMERIC, p_paymentmethod TEXT, p_suppliername TEXT, p_receiptref TEXT, p_updatedby TEXT,
    p_cashaccountid INT DEFAULT NULL, p_supplierid INT DEFAULT NULL, p_amountpaid NUMERIC DEFAULT NULL,
    p_duedate DATE DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_e restaurantexpenses%ROWTYPE; v_x restaurantexpensepayables%ROWTYPE; v_live restaurantcashtransactions%ROWTYPE;
    v_amt NUMERIC(14,2) := ROUND(COALESCE(p_amount, 0), 2);
    v_date DATE := COALESCE(p_expensedate, CURRENT_DATE);
    v_method TEXT := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
    v_cat TEXT := NULLIF(btrim(p_categoryname), ''); v_supname TEXT := NULLIF(btrim(p_suppliername), '');
    v_paid NUMERIC(14,2); v_alloc NUMERIC(14,2); v_acc INT; v_rev INT; v_move BOOLEAN;
BEGIN
    SELECT * INTO v_e FROM restaurantexpenses WHERE expenseid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Expense not found for this company.'; END IF;
    SELECT * INTO v_x FROM restaurantexpensepayables WHERE expenseid = p_id;

    IF v_amt <= 0 THEN RAISE EXCEPTION 'Expense amount must be more than zero.'; END IF;
    IF btrim(COALESCE(p_description, '')) = '' THEN RAISE EXCEPTION 'Description is required.'; END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'An expense cannot be dated in the future.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_e.expensedate);
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    IF p_supplierid IS NOT NULL THEN
        SELECT COALESCE(v_supname, s.name) INTO v_supname FROM restaurantsuppliers s
         WHERE s.restaurantsupplierid = p_supplierid AND s.farmid = p_farmid;
        IF NOT FOUND THEN RAISE EXCEPTION 'Supplier does not belong to this company.'; END IF;
    END IF;
    v_paid := ROUND(COALESCE(p_amountpaid, v_amt), 2);
    IF v_paid < 0 THEN RAISE EXCEPTION 'Amount paid cannot be negative.'; END IF;
    IF v_paid > v_amt THEN RAISE EXCEPTION 'Amount paid (%) cannot exceed the expense total (%).', v_paid, v_amt; END IF;

    v_alloc := fnrestaurant_allocated(p_farmid, 'Expense', p_id);
    IF v_alloc > 0 THEN
        IF v_amt < v_alloc + v_paid THEN
            RAISE EXCEPTION 'Supplier payments totalling % have been applied to this expense, so its total cannot be reduced to %.',
                v_alloc, v_amt;
        END IF;
        IF p_supplierid IS DISTINCT FROM v_x.supplierid THEN
            RAISE EXCEPTION 'Supplier payments totalling % have been applied to this expense, so its supplier cannot change. Reverse the payment on Supplier Payments first.',
                v_alloc;
        END IF;
    END IF;
    IF v_paid < v_amt AND p_supplierid IS NULL THEN
        RAISE EXCEPTION 'Choose the supplier: % of this expense is still owed.', (v_amt - v_paid);
    END IF;

    IF v_cat IS NULL AND p_categoryid IS NOT NULL THEN
        SELECT c.name INTO v_cat FROM restaurantexpensecategories c
         WHERE c.expensecategoryid = p_categoryid AND c.farmid = p_farmid;
    END IF;

    -- Where the new payment goes (sprestaurant_expense_record's rule).
    IF v_paid > 0 THEN
        v_acc := fnrestaurant_resolve_account(p_farmid, v_method, p_cashaccountid, NULL, FALSE);
        IF p_cashaccountid IS NULL AND lower(replace(v_method, ' ', '')) = 'cash' THEN
            v_acc := fnrestaurant_default_account(p_farmid, 'Cash');
        END IF;
    END IF;

    SELECT * INTO v_live FROM fnrestaurant_expense_liveposting(p_farmid, p_id) LIMIT 1;
    v_move := CASE
        WHEN v_live.cashtxnid IS NULL THEN v_paid > 0 AND v_acc IS NOT NULL
        WHEN v_paid = 0 OR v_acc IS NULL THEN TRUE
        ELSE v_live.cashaccountid <> v_acc OR v_live.amount <> -v_paid OR v_live.txndate <> v_date END;

    INSERT INTO restaurantexpenserevisions (farmid, expenseid, oldexpensedate, newexpensedate, oldamount, newamount,
        oldamountpaid, newamountpaid, oldcashaccountid, newcashaccountid, olddescription, newdescription,
        oldcategory, newcategory, oldpaymentmethod, newpaymentmethod, oldsupplierid, newsupplierid, movedcash, editedby)
    VALUES (p_farmid, p_id, v_e.expensedate, v_date, v_e.amount, v_amt,
            COALESCE(v_x.amountpaid, v_e.amount), v_paid, v_live.cashaccountid, CASE WHEN v_paid > 0 THEN v_acc END,
            v_e.description, btrim(p_description), v_e.categoryname, v_cat, v_e.paymentmethod, v_method,
            v_x.supplierid, p_supplierid, v_move, p_updatedby)
    RETURNING revisionid INTO v_rev;

    IF v_move THEN
        IF v_live.cashtxnid IS NOT NULL THEN
            PERFORM fnrestaurant_post(p_farmid, v_live.cashaccountid, v_live.txndate, -v_live.amount, 'ExpenseEditReversal',
                                      v_rev, 'Edited expense (was): ' || v_e.description, p_updatedby, v_live.cashtxnid);
        END IF;
        IF v_paid > 0 AND v_acc IS NOT NULL THEN
            PERFORM fnrestaurant_post(p_farmid, v_acc, v_date, -v_paid, 'ExpenseEdit', v_rev,
                                      btrim(p_description) || COALESCE(' (' || v_cat || ')', ''), p_updatedby);
        END IF;
    END IF;

    UPDATE restaurantexpenses
       SET expensedate = v_date, categoryid = p_categoryid, categoryname = v_cat, description = btrim(p_description),
           amount = v_amt, paymentmethod = v_method, suppliername = v_supname, receiptref = p_receiptref
     WHERE expenseid = p_id AND farmid = p_farmid;

    IF p_supplierid IS NOT NULL OR v_paid < v_amt THEN
        INSERT INTO restaurantexpensepayables (expenseid, farmid, supplierid, amountpaid, duedate)
        VALUES (p_id, p_farmid, p_supplierid, v_paid, CASE WHEN v_paid < v_amt THEN p_duedate END)
        ON CONFLICT (expenseid) DO UPDATE SET supplierid = EXCLUDED.supplierid, amountpaid = EXCLUDED.amountpaid,
                                              duedate = EXCLUDED.duedate;
    ELSE
        DELETE FROM restaurantexpensepayables WHERE expenseid = p_id;
    END IF;
END $$;

-- 329's body plus two trailing columns the Edit dialog needs: what was paid when
-- the expense was recorded (paidatentry -- the figure the edit changes) and what
-- supplier payments have settled (allocated). amountpaid stays their sum, as
-- before. Read by name (RestaurantSupplierService), so the added columns are safe.
CREATE FUNCTION sprestaurant_expense_payments(p_farmid TEXT, p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS TABLE(expenseid INT, supplierid INT, suppliername TEXT, amountpaid NUMERIC, balance NUMERIC,
              paymentstatus TEXT, duedate DATE, paidatentry NUMERIC, allocated NUMERIC, cashaccountid INT)
LANGUAGE sql STABLE AS $$
    SELECT e.expenseid, x.supplierid, COALESCE(s.name, e.suppliername)::TEXT,
           (COALESCE(x.amountpaid, e.amount) + a.x)::NUMERIC(14,2),
           GREATEST(e.amount - COALESCE(x.amountpaid, e.amount) - a.x, 0)::NUMERIC(14,2),
           CASE WHEN e.amount - COALESCE(x.amountpaid, e.amount) - a.x <= 0 THEN 'Paid'
                WHEN COALESCE(x.amountpaid, e.amount) + a.x > 0 THEN 'PartiallyPaid' ELSE 'Unpaid' END,
           x.duedate,
           COALESCE(x.amountpaid, e.amount)::NUMERIC(14,2), a.x::NUMERIC(14,2),
           (SELECT t.cashaccountid FROM fnrestaurant_expense_liveposting(p_farmid, e.expenseid) t LIMIT 1)
      FROM restaurantexpenses e
      LEFT JOIN restaurantexpensepayables x ON x.expenseid = e.expenseid
      LEFT JOIN restaurantsuppliers s ON s.restaurantsupplierid = x.supplierid
     CROSS JOIN LATERAL (SELECT fnrestaurant_allocated(p_farmid, 'Expense', e.expenseid) AS x) a
     WHERE e.farmid = p_farmid
       AND (p_from IS NULL OR e.expensedate >= p_from)
       AND (p_to IS NULL OR e.expensedate <= p_to);
$$;

-- 329's body; reverses whichever posting is live (the first payment or the
-- latest edit's), on the expense's date.
CREATE OR REPLACE FUNCTION sprestaurant_expense_delete(p_id INT, p_farmid TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_e restaurantexpenses%ROWTYPE; v_t RECORD;
BEGIN
    SELECT * INTO v_e FROM restaurantexpenses WHERE expenseid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    IF fnrestaurant_allocated(p_farmid, 'Expense', p_id) > 0 THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this expense. Reverse the payment on Supplier Payments first.';
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_e.expensedate);

    FOR v_t IN SELECT * FROM fnrestaurant_expense_liveposting(p_farmid, p_id) LOOP
        PERFORM fnrestaurant_post(p_farmid, v_t.cashaccountid, v_t.txndate, -v_t.amount, 'ExpenseReversal', p_id,
                                  'Deleted expense: ' || v_e.description, v_e.createdby, v_t.cashtxnid);
    END LOOP;
    DELETE FROM restaurantexpenses WHERE expenseid = p_id AND farmid = p_farmid;
END $$;

-- -----------------------------------------------------------------------------
-- Cash-flow detail and the profit-vs-cash bridge, re-emitted from 333 with only
-- the marked (337) changes.
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
               -- 337: an edited expense's new payment keeps its category; the reversed old one is a correction
               WHEN 'ExpenseEdit' THEN COALESCE(NULLIF(btrim(e.categoryname), ''), 'Uncategorised')
               WHEN 'ExpenseEditReversal' THEN 'Expense corrections'
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
               -- 333: pay-later orders collected, and payment reversals (Operating)
               WHEN 'CustomerPayment' THEN 'Customer payments'
               WHEN 'CustomerPaymentReversal' THEN 'Customer payment corrections'
               WHEN 'OrderPaymentReversal' THEN 'Sales payment corrections'
               ELSE 'Other' END::TEXT,
           r.createdat
      FROM sprestaurantcashflow_rows(p_farmid, p_fromdate, p_todate) r
      LEFT JOIN restaurantorderpayments p ON r.sourcetype = 'OrderPayment' AND p.orderpaymentid = r.sourceid
      LEFT JOIN restaurantexpenserevisions v ON r.sourcetype = 'ExpenseEdit' AND v.revisionid = r.sourceid
      LEFT JOIN restaurantexpenses e ON e.expenseid = CASE WHEN r.sourcetype = 'Expense' THEN r.sourceid
                                                          WHEN r.sourcetype = 'ExpenseEdit' THEN v.expenseid END;
$$;
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
     -- 333: balance payments on pay-later orders and payment reversals are sales cash too;
     -- an order completed unpaid is revenue now and cash later (sales timing).
     WHERE t.farmid = p_farmid AND t.sourcetype IN ('OrderPayment', 'OrderRefund', 'OrderPaymentReversal',
                                                    'CustomerPayment', 'CustomerPaymentReversal')
       AND t.txndate BETWEEN p_from AND p_to;
    SELECT COALESCE(SUM(p.tipamount), 0) INTO v_tips FROM restaurantorderpayments p
     WHERE p.farmid = p_farmid AND p.status = 'Completed' AND p.amount > 0
       AND p.createdat::DATE BETWEEN p_from AND p_to;
    SELECT COALESCE(SUM(p.amount), 0) INTO v_gift_paid FROM restaurantorderpayments p
     WHERE p.farmid = p_farmid AND p.status = 'Completed' AND p.amount > 0
       AND NOT fnrestaurant_is_cash_method(p.paymentmethod)
       AND p.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('GiftCardSale', 'GiftCardReload')), 0),
           COALESCE(-SUM(t.amount) FILTER (WHERE t.sourcetype IN ('Expense', 'ExpenseReversal',
                                                                  'ExpenseEdit', 'ExpenseEditReversal')), 0) - v_sp_exp,  -- 337
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
         'Payments taken this period for orders counted in another period (or the reverse), pay-later orders not yet collected, and full refunds.'),
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

-- -----------------------------------------------------------------------------
-- Verification (read-only)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF position('ExpenseEdit' in pg_get_functiondef('sprestaurant_report_cash_profit_bridge'::regproc)) = 0
       OR position('CustomerPayment' in pg_get_functiondef('sprestaurant_report_cash_profit_bridge'::regproc)) = 0
       OR position('stock_internal_use' in pg_get_functiondef('sprestaurant_report_cash_profit_bridge'::regproc)) = 0 THEN
        RAISE EXCEPTION '337 verification failed: the bridge lost an arm';
    END IF;
    IF position('ExpenseEdit' in pg_get_functiondef('sprestaurantcashflow_detail'::regproc)) = 0 THEN
        RAISE EXCEPTION '337 verification failed: cash-flow detail does not categorise ExpenseEdit';
    END IF;
END $$;

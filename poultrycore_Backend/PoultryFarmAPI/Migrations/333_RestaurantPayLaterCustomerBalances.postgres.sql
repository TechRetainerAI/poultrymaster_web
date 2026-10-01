-- =============================================================================
-- 333_RestaurantPayLaterCustomerBalances.postgres.sql
--
-- Purpose
-- -------
-- The Restaurant SALES column, copied from Poultry: pay-later (credit) orders,
-- Customer Balances and Payments.
--
-- PAY LATER. Until now an order could only be Completed when fully paid (323).
-- An order linked to a saved CRM customer (restaurantorders.customerid ->
-- restaurantcustomers) can now be marked "Pay later" (sprestaurant_order_paylater,
-- optional due date) and then Completed unpaid or part-paid. The flag lives in
-- restaurantorderpaylater (no column is added to restaurantorders, which is read
-- by SELECT o.* and by ordinal). Walk-ins still have to pay in full.
--
-- CUSTOMER BALANCES (Poultry 223/240/241/242/304 contract, the shared
-- components/balances pages): the balance is DERIVED -- every Completed
-- pay-later order's total less what has been paid on it. Terms are 0 days: an
-- order is overdue from the day after it, unless a due date was set.
--
-- RECEIVING A BALANCE PAYMENT. One restaurantcustomerpayments header, one ledger
-- row ('CustomerPayment', fnrestaurant_post) for the whole amount, and one
-- allocation per order in the SHARED customerpaymentallocation table
-- (module = 'restaurant', saleid = orderid). Each allocation also writes a
-- restaurantorderpayments row WITHOUT a ledger row (the header's one row carries
-- the cash), so the order's paid amount, payment status, takings-by-method and
-- the P&L refund/tip readers all keep working from the one table they read.
-- restaurantcustomerpaymentlines links allocation -> order payment.
--
-- PAYMENTS page: one row per payment actually received -- 'OP-n' a payment taken
-- on an order (till/POS, source SaleEntry), 'CP-n' a balance payment (source
-- CustomerBalances). Reverse, with a reason, is append-only: the order payment
-- rows are marked Voided and an opposite ledger row is posted today
-- ('OrderPaymentReversal' / 'CustomerPaymentReversal'). A gift card payment is
-- not reversed here (its value would have to go back on the card), and a payment
-- on a completed walk-in order is refunded on the order instead (reversing it
-- would leave a walk-in owing money).
--
-- REVENUE. The P&L already counts every Completed order on its order date,
-- whether or not it was paid (accrual, as Poultry counts a sale on its sale
-- date). A pay-later order therefore reaches revenue when it is completed and
-- its cash reaches Cash Flow when it is collected. No P&L change.
-- fnrestaurant_order_settle is re-emitted so a Completed pay-later order reports
-- Unpaid / Partial rather than Paid.
--
-- PROFIT vs CASH: the three new ledger source types join sales cash, so the
-- existing "Sales timing differences" line absorbs pay-later orders and their
-- later collection; "Unexplained" stays 0. Cash-flow detail categorises them.
--
-- Re-emits: fnrestaurant_order_settle, sprestaurant_order_update_status (323);
-- sprestaurantcashflow_detail (329); sprestaurant_report_cash_profit_bridge (330).
-- Re-run order: 323 -> 324 -> 326 -> 328 -> 329 -> 330 -> 333.
-- Column additions to existing tables: NONE.
-- =============================================================================

DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
            'sprestaurant_order_paylater', 'sprestaurant_order_paylater_clear', 'fnrestaurant_receivables',
            'sprestaurant_customerbalances', 'sprestaurant_customerbalancesummary', 'sprestaurant_customeropenorders',
            'sprestaurant_customerpayment_record', 'sprestaurant_customerpayment_reverse',
            'sprestaurant_customerpayment_history', 'sprestaurant_customerpayment_allocations',
            'sprestaurant_customerstatement', 'sprestaurant_customerbalance_audit')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS restaurantorderpaylater (
    orderid     INT PRIMARY KEY REFERENCES restaurantorders(orderid) ON DELETE CASCADE,
    farmid      TEXT NOT NULL,
    customerid  INT NOT NULL REFERENCES restaurantcustomers(customerid),
    duedate     DATE,
    notes       TEXT,
    markedby    TEXT,
    markedat    TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantorderpaylater_customer ON restaurantorderpaylater (farmid, customerid);

CREATE TABLE IF NOT EXISTS restaurantcustomerpayments (
    customerpaymentid SERIAL PRIMARY KEY,
    farmid            TEXT NOT NULL,
    customerid        INT NOT NULL REFERENCES restaurantcustomers(customerid),
    paymentdate       DATE NOT NULL,
    totalamount       NUMERIC(14,2) NOT NULL CHECK (totalamount > 0),
    paymentmethod     TEXT NOT NULL,
    cashaccountid     INT NOT NULL REFERENCES restaurantcashaccounts(cashaccountid),
    referenceno       TEXT,
    notes             TEXT,
    sourcetype        TEXT NOT NULL DEFAULT 'CustomerBalances',
    status            TEXT NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),
    createdby         TEXT,
    createdat         TIMESTAMP NOT NULL DEFAULT NOW(),
    reversedby        TEXT,
    reversedat        TIMESTAMP,
    reversalreason    TEXT
);
CREATE INDEX IF NOT EXISTS ix_restaurantcustomerpayments_farm ON restaurantcustomerpayments (farmid, paymentdate);

CREATE TABLE IF NOT EXISTS restaurantcustomerpaymentlines (
    allocationid    INT PRIMARY KEY,
    farmid          TEXT NOT NULL,
    paymentid       INT NOT NULL REFERENCES restaurantcustomerpayments(customerpaymentid),
    orderpaymentid  INT NOT NULL UNIQUE REFERENCES restaurantorderpayments(orderpaymentid)
);
CREATE INDEX IF NOT EXISTS ix_restaurantcustomerpaymentlines_payment ON restaurantcustomerpaymentlines (paymentid);

-- A till/order payment reversed from the Payments page (restaurantorderpayments
-- has no reversal columns; the row is marked Voided and the why lives here).
CREATE TABLE IF NOT EXISTS restaurantorderpaymentreversals (
    orderpaymentid  INT PRIMARY KEY REFERENCES restaurantorderpayments(orderpaymentid),
    farmid          TEXT NOT NULL,
    reason          TEXT NOT NULL,
    reversedby      TEXT,
    reversedat      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 2. Order settlement and completion (323 bodies + pay later)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fnrestaurant_order_settle(p_orderid INT, p_farmid TEXT)
RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE v_paid NUMERIC; v_total NUMERIC; v_status TEXT; v_later BOOLEAN;
BEGIN
    SELECT COALESCE(SUM(p.amount), 0) INTO v_paid FROM restaurantorderpayments p
     WHERE p.orderid = p_orderid AND p.farmid = p_farmid AND p.status = 'Completed';
    SELECT o.totalamount, o.status INTO v_total, v_status FROM restaurantorders o
     WHERE o.orderid = p_orderid AND o.farmid = p_farmid;
    v_later := EXISTS (SELECT 1 FROM restaurantorderpaylater l WHERE l.orderid = p_orderid);
    UPDATE restaurantorders o
       SET paidamount = v_paid, updatedat = NOW(),
           paymentstatus = CASE
               WHEN v_status = 'Refunded' THEN 'Refunded'
               -- 333: a completed PAY-LATER order owes what is left, so it is not
               -- "Paid" just because something was paid.
               WHEN v_status = 'Completed' AND v_paid > 0 AND NOT v_later THEN 'Paid'
               WHEN v_paid <= 0 AND EXISTS (SELECT 1 FROM restaurantorderpayments p
                                             WHERE p.orderid = p_orderid AND p.amount < 0) THEN 'Refunded'
               WHEN v_paid <= 0 THEN 'Unpaid'
               WHEN v_paid >= v_total THEN 'Paid'
               ELSE 'Partial' END
     WHERE o.orderid = p_orderid AND o.farmid = p_farmid;
    RETURN v_paid;
END $$;

-- 323's body; Completed unpaid is allowed only for a pay-later order.
CREATE OR REPLACE FUNCTION sprestaurant_order_update_status(p_id INT, p_farmid TEXT, p_status TEXT, p_reason TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_o restaurantorders%ROWTYPE;
BEGIN
    SELECT * INTO v_o FROM restaurantorders WHERE orderid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;

    IF p_status = 'Completed' AND v_o.status <> 'Completed'
       AND v_o.totalamount > 0 AND v_o.paidamount < v_o.totalamount
       AND NOT EXISTS (SELECT 1 FROM restaurantorderpaylater l WHERE l.orderid = p_id) THEN
        RAISE EXCEPTION 'Order % still has % to pay. Take payment before completing it, or mark it Pay later for a saved customer.',
            v_o.ordernumber, to_char(v_o.totalamount - v_o.paidamount, 'FM999,999,999,990.00');
    END IF;
    IF p_status = 'Cancelled' AND v_o.paidamount > 0 THEN
        RAISE EXCEPTION 'Order % has % paid against it. Refund it instead of cancelling.',
            v_o.ordernumber, to_char(v_o.paidamount, 'FM999,999,999,990.00');
    END IF;
    IF p_status = 'Refunded' AND v_o.status <> 'Refunded' THEN
        RAISE EXCEPTION 'Use Refund on the order to give money back; it sets the Refunded status.';
    END IF;
    IF v_o.status IN ('Cancelled', 'Refunded') AND p_status <> v_o.status THEN
        RAISE EXCEPTION 'Order % is % and cannot change status.', v_o.ordernumber, lower(v_o.status);
    END IF;

    UPDATE restaurantorders SET status = p_status, updatedat = NOW(),
        cancelreason = CASE WHEN p_status = 'Cancelled' THEN p_reason ELSE cancelreason END,
        completedat = CASE WHEN p_status IN ('Completed','Cancelled') THEN NOW() ELSE completedat END
    WHERE orderid = p_id AND farmid = p_farmid;
    IF p_status IN ('Completed', 'Cancelled') THEN
        UPDATE restauranttables SET status = 'NeedsCleaning', currentorderid = NULL, updatedat = NOW()
         WHERE currentorderid = p_id AND farmid = p_farmid;
    END IF;
    -- 333: a cancelled order owes nothing.
    IF p_status = 'Cancelled' THEN DELETE FROM restaurantorderpaylater WHERE orderid = p_id; END IF;
    IF p_status = 'Completed' THEN PERFORM fnrestaurant_order_settle(p_id, p_farmid); END IF;
END $$;

-- Marks an order Pay later for a saved customer (the caller then completes it).
-- The customer is the order's own link, or the one passed (which becomes the
-- order's link). Re-marking updates the due date.
CREATE FUNCTION sprestaurant_order_paylater(p_farmid TEXT, p_orderid INT, p_customerid INT DEFAULT NULL,
                                            p_duedate DATE DEFAULT NULL, p_notes TEXT DEFAULT NULL,
                                            p_markedby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_o restaurantorders%ROWTYPE; v_c INT; v_name TEXT;
BEGIN
    SELECT * INTO v_o FROM restaurantorders WHERE orderid = p_orderid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
    IF v_o.status IN ('Cancelled', 'Refunded') THEN
        RAISE EXCEPTION 'Order % is % and cannot be paid later.', v_o.ordernumber, lower(v_o.status);
    END IF;
    IF v_o.status = 'Completed' AND NOT EXISTS (SELECT 1 FROM restaurantorderpaylater l WHERE l.orderid = p_orderid) THEN
        RAISE EXCEPTION 'Order % is already completed and paid.', v_o.ordernumber;
    END IF;
    IF COALESCE(v_o.totalamount, 0) - COALESCE(v_o.paidamount, 0) <= 0 THEN
        RAISE EXCEPTION 'Order % is fully paid; there is nothing to pay later.', v_o.ordernumber;
    END IF;
    v_c := COALESCE(p_customerid, v_o.customerid);
    IF v_c IS NULL THEN
        RAISE EXCEPTION 'Only a saved customer can pay later. Add this guest as a customer first.';
    END IF;
    SELECT c.name INTO v_name FROM restaurantcustomers c WHERE c.customerid = v_c AND c.farmid = p_farmid;
    IF v_name IS NULL THEN RAISE EXCEPTION 'Customer not found for this restaurant.'; END IF;
    IF p_duedate IS NOT NULL AND p_duedate < v_o.createdat::DATE THEN
        RAISE EXCEPTION 'The due date cannot be before the order date.';
    END IF;

    IF v_o.customerid IS DISTINCT FROM v_c THEN
        UPDATE restaurantorders SET customerid = v_c, customername = COALESCE(customername, v_name), updatedat = NOW()
         WHERE orderid = p_orderid;
    END IF;
    INSERT INTO restaurantorderpaylater (orderid, farmid, customerid, duedate, notes, markedby)
    VALUES (p_orderid, p_farmid, v_c, p_duedate, NULLIF(btrim(p_notes), ''), p_markedby)
    ON CONFLICT (orderid) DO UPDATE SET customerid = EXCLUDED.customerid, duedate = EXCLUDED.duedate,
                                        notes = EXCLUDED.notes, markedby = EXCLUDED.markedby, markedat = NOW();
END $$;

-- -----------------------------------------------------------------------------
-- 3. Receivables: the ONE definition every customer reader uses.
-- -----------------------------------------------------------------------------
CREATE FUNCTION fnrestaurant_receivables(p_farmid TEXT)
RETURNS TABLE(orderid INT, customerid INT, ordernumber TEXT, ordertype TEXT, orderdate DATE, totalamount NUMERIC,
              amountpaid NUMERIC, balance NUMERIC, duedate DATE)
LANGUAGE sql STABLE AS $$
    SELECT o.orderid, l.customerid, o.ordernumber::TEXT, o.ordertype::TEXT, o.createdat::DATE,
           COALESCE(o.totalamount, 0)::NUMERIC(14,2), COALESCE(o.paidamount, 0)::NUMERIC(14,2),
           GREATEST(COALESCE(o.totalamount, 0) - COALESCE(o.paidamount, 0), 0)::NUMERIC(14,2),
           COALESCE(l.duedate, o.createdat::DATE)
      FROM restaurantorderpaylater l
      JOIN restaurantorders o ON o.orderid = l.orderid AND o.farmid = p_farmid
     WHERE l.farmid = p_farmid AND o.status = 'Completed';
$$;

-- -----------------------------------------------------------------------------
-- 4. Customer Balances (Poultry 223 / 240 result columns)
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_customerbalances(p_farmid TEXT, p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL,
                                              p_customerid INT DEFAULT NULL, p_status TEXT DEFAULT 'All',
                                              p_minbalance NUMERIC DEFAULT NULL, p_search TEXT DEFAULT NULL)
RETURNS TABLE(customerid INT, customername TEXT, contactphone TEXT, contactemail TEXT, paymenttermsdays INT,
              totalbalance NUMERIC, opendocumentcount INT, oldestdocumentdate DATE, latestdocumentdate DATE,
              lastpaymentdate DATE, overdueamount NUMERIC, totalinvoiced NUMERIC, totalpaid NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH r AS (
        SELECT * FROM fnrestaurant_receivables(p_farmid) x
         WHERE (p_from IS NULL OR x.orderdate >= p_from) AND (p_to IS NULL OR x.orderdate <= p_to)
    ), g AS (
        SELECT r.customerid,
               SUM(r.balance) AS bal, COUNT(*) FILTER (WHERE r.balance > 0)::INT AS n,
               MIN(r.orderdate) FILTER (WHERE r.balance > 0) AS oldest,
               MAX(r.orderdate) FILTER (WHERE r.balance > 0) AS latest,
               SUM(r.balance) FILTER (WHERE r.balance > 0 AND r.duedate < CURRENT_DATE) AS overdue,
               SUM(r.totalamount) AS inv, SUM(r.amountpaid) AS paid,
               BOOL_OR(r.balance > 0 AND r.amountpaid <= 0) AS anyunpaid,
               BOOL_OR(r.balance > 0 AND r.amountpaid > 0) AS anypartial
          FROM r GROUP BY r.customerid
    )
    SELECT c.customerid, c.name::TEXT, c.phone::TEXT, c.email::TEXT, 0,
           g.bal::NUMERIC(14,2), g.n, g.oldest, g.latest,
           (SELECT MAX(d) FROM (
                SELECT MAX(cp.paymentdate) AS d FROM restaurantcustomerpayments cp
                 WHERE cp.farmid = p_farmid AND cp.customerid = c.customerid AND cp.status = 'Posted'
                UNION ALL
                SELECT MAX(op.createdat::DATE) FROM restaurantorderpayments op
                  JOIN restaurantorderpaylater l ON l.orderid = op.orderid
                 WHERE op.farmid = p_farmid AND l.customerid = c.customerid AND op.status = 'Completed' AND op.amount > 0) z),
           COALESCE(g.overdue, 0)::NUMERIC(14,2), g.inv::NUMERIC(14,2), g.paid::NUMERIC(14,2)
      FROM g JOIN restaurantcustomers c ON c.customerid = g.customerid AND c.farmid = p_farmid
     WHERE g.bal > 0
       AND (p_customerid IS NULL OR c.customerid = p_customerid)
       AND (p_minbalance IS NULL OR g.bal >= p_minbalance)
       AND (p_search IS NULL OR btrim(p_search) = '' OR c.name ILIKE '%' || btrim(p_search) || '%'
            OR COALESCE(c.phone, '') ILIKE '%' || btrim(p_search) || '%')
       AND CASE COALESCE(p_status, 'All')
                WHEN 'Unpaid' THEN g.anyunpaid
                WHEN 'Partial' THEN g.anypartial
                WHEN 'Overdue' THEN COALESCE(g.overdue, 0) > 0
                ELSE TRUE END
     ORDER BY g.bal DESC, c.name;
$$;

CREATE FUNCTION sprestaurant_customerbalancesummary(p_farmid TEXT)
RETURNS TABLE(totalbalance NUMERIC, partycount INT, overduebalance NUMERIC, paymentstoday NUMERIC,
              largestbalance NUMERIC, largestbalanceparty TEXT)
LANGUAGE sql STABLE AS $$
    WITH b AS (SELECT * FROM sprestaurant_customerbalances(p_farmid))
    SELECT COALESCE(SUM(b.totalbalance), 0)::NUMERIC(14,2), COUNT(*)::INT,
           COALESCE(SUM(b.overdueamount), 0)::NUMERIC(14,2),
           (COALESCE((SELECT SUM(cp.totalamount) FROM restaurantcustomerpayments cp
                       WHERE cp.farmid = p_farmid AND cp.status = 'Posted' AND cp.paymentdate = CURRENT_DATE), 0)
            + COALESCE((SELECT SUM(op.amount) FROM restaurantorderpayments op
                         JOIN restaurantorderpaylater l ON l.orderid = op.orderid
                        WHERE op.farmid = p_farmid AND op.status = 'Completed' AND op.amount > 0
                          AND op.createdat::DATE = CURRENT_DATE
                          AND NOT EXISTS (SELECT 1 FROM restaurantcustomerpaymentlines x
                                           WHERE x.orderpaymentid = op.orderpaymentid)), 0))::NUMERIC(14,2),
           COALESCE(MAX(b.totalbalance), 0)::NUMERIC(14,2),
           (SELECT b2.customername FROM b b2 ORDER BY b2.totalbalance DESC LIMIT 1)
      FROM b;
$$;

CREATE FUNCTION sprestaurant_customeropenorders(p_farmid TEXT, p_customerid INT, p_from DATE DEFAULT NULL,
                                                p_to DATE DEFAULT NULL, p_status TEXT DEFAULT NULL)
RETURNS TABLE(documenttype TEXT, documentid INT, reference TEXT, documentdate DATE, label TEXT, description TEXT,
              totalamount NUMERIC, amountpaid NUMERIC, balance NUMERIC, duedate DATE, agedays INT, status TEXT,
              isoverdue BOOLEAN, cashaccountid INT)
LANGUAGE sql STABLE AS $$
    SELECT 'Order'::TEXT, r.orderid, r.ordernumber, r.orderdate, COALESCE(r.ordertype, 'Order'),
           'Pay-later order ' || r.ordernumber, r.totalamount, r.amountpaid, r.balance, r.duedate,
           (CURRENT_DATE - r.orderdate)::INT,
           CASE WHEN r.balance <= 0 THEN 'Paid' WHEN r.amountpaid > 0 THEN 'Partial' ELSE 'Unpaid' END,
           r.balance > 0 AND r.duedate < CURRENT_DATE, NULL::INT
      FROM fnrestaurant_receivables(p_farmid) r
     WHERE r.customerid = p_customerid
       AND (p_from IS NULL OR r.orderdate >= p_from) AND (p_to IS NULL OR r.orderdate <= p_to)
       AND (r.balance > 0 OR upper(COALESCE(p_status, '')) = 'ALL')
     ORDER BY r.orderdate, r.orderid;
$$;

-- -----------------------------------------------------------------------------
-- 5. Receive a balance payment: one cash row, allocations per order.
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_customerpayment_record(
    p_farmid TEXT, p_customerid INT, p_amount NUMERIC, p_paymentdate DATE DEFAULT NULL,
    p_paymentmethod TEXT DEFAULT 'Cash', p_cashaccountid INT DEFAULT NULL, p_reference TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL, p_sourcetype TEXT DEFAULT 'CustomerBalances', p_createdby TEXT DEFAULT NULL,
    p_allocations JSONB DEFAULT '[]')
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
    v_amt NUMERIC(14,2) := ROUND(COALESCE(p_amount, 0), 2); v_date DATE := COALESCE(p_paymentdate, CURRENT_DATE);
    v_method TEXT := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash'); v_name TEXT; v_acc INT; v_id INT;
    v_sum NUMERIC(14,2); v_opid INT; v_alloc INT; v_o RECORD; a RECORD; v_ref TEXT;
BEGIN
    SELECT c.name INTO v_name FROM restaurantcustomers c WHERE c.customerid = p_customerid AND c.farmid = p_farmid;
    IF v_name IS NULL THEN RAISE EXCEPTION 'Customer not found for this restaurant.'; END IF;
    IF v_amt <= 0 THEN RAISE EXCEPTION 'Payment amount must be greater than 0.'; END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'A payment cannot be dated in the future.'; END IF;
    IF NOT fnrestaurant_is_cash_method(v_method) THEN
        RAISE EXCEPTION 'A balance is paid in Cash, Card, Bank Transfer or Mobile Money.';
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    SELECT COALESCE(SUM((x->>'amount')::NUMERIC), 0) INTO v_sum FROM jsonb_array_elements(COALESCE(p_allocations, '[]')) x;
    IF jsonb_array_length(COALESCE(p_allocations, '[]')) = 0 THEN
        RAISE EXCEPTION 'Select at least one sale to apply this payment to.';
    END IF;
    IF ROUND(v_sum, 2) <> v_amt THEN
        RAISE EXCEPTION 'The amounts applied (%) must add up to the payment (%).', ROUND(v_sum, 2), v_amt;
    END IF;

    v_acc := fnrestaurant_resolve_account(p_farmid, v_method, p_cashaccountid, NULL, FALSE);
    IF v_acc IS NULL OR NOT EXISTS (SELECT 1 FROM restaurantcashaccounts ca WHERE ca.cashaccountid = v_acc AND ca.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Choose the cash account this payment goes into.';
    END IF;

    INSERT INTO restaurantcustomerpayments (farmid, customerid, paymentdate, totalamount, paymentmethod, cashaccountid,
                                            referenceno, notes, sourcetype, createdby)
    VALUES (p_farmid, p_customerid, v_date, v_amt, v_method, v_acc, NULLIF(btrim(p_reference), ''),
            NULLIF(btrim(p_notes), ''), COALESCE(NULLIF(btrim(p_sourcetype), ''), 'CustomerBalances'), p_createdby)
    RETURNING customerpaymentid INTO v_id;
    v_ref := 'CP-' || v_id;

    FOR a IN SELECT (x->>'documentId')::INT AS orderid, ROUND((x->>'amount')::NUMERIC, 2) AS amt
               FROM jsonb_array_elements(p_allocations) x ORDER BY 1
    LOOP
        IF a.amt IS NULL OR a.amt <= 0 THEN RAISE EXCEPTION 'Each allocation must be greater than 0.'; END IF;
        PERFORM 1 FROM restaurantorders o WHERE o.orderid = a.orderid AND o.farmid = p_farmid FOR UPDATE;
        SELECT * INTO v_o FROM fnrestaurant_receivables(p_farmid) r WHERE r.orderid = a.orderid;
        IF v_o.orderid IS NULL OR v_o.customerid <> p_customerid THEN
            RAISE EXCEPTION 'Order % is not a pay-later order of this customer.', a.orderid;
        END IF;
        IF a.amt > v_o.balance THEN
            RAISE EXCEPTION 'This payment applies % to %, which only has % still owed.', a.amt, v_o.ordernumber, v_o.balance;
        END IF;
        INSERT INTO restaurantorderpayments (farmid, orderid, paymentmethod, amount, tipamount, reference, processedby)
        VALUES (p_farmid, a.orderid, v_method, a.amt, 0, 'Customer payment ' || v_ref, p_createdby)
        RETURNING orderpaymentid INTO v_opid;
        INSERT INTO customerpaymentallocation (farmid, module, paymentid, saleid, amountapplied, salebalancebefore,
                                               salebalanceafter, status, createdby)
        VALUES (p_farmid, 'restaurant', v_id, a.orderid, a.amt, v_o.balance, v_o.balance - a.amt, 'Posted', p_createdby)
        RETURNING allocationid INTO v_alloc;
        INSERT INTO restaurantcustomerpaymentlines (allocationid, farmid, paymentid, orderpaymentid)
        VALUES (v_alloc, p_farmid, v_id, v_opid);
        PERFORM fnrestaurant_order_settle(a.orderid, p_farmid);
    END LOOP;

    PERFORM fnrestaurant_post(p_farmid, v_acc, v_date, v_amt, 'CustomerPayment', v_id,
                              'Payment from ' || v_name || ' (' || v_method || ')', p_createdby);
    RETURN v_id;
END $$;

-- Reverse a payment from the Payments page. 'CP-n' = a balance payment,
-- 'OP-n' = a payment taken on an order. Returns the allocations reversed.
CREATE FUNCTION sprestaurant_customerpayment_reverse(p_farmid TEXT, p_paymentid TEXT, p_reason TEXT,
                                                     p_reversedby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_kind TEXT := upper(split_part(COALESCE(p_paymentid, ''), '-', 1)); v_n INT; v_cp restaurantcustomerpayments%ROWTYPE;
        v_op restaurantorderpayments%ROWTYPE; v_o restaurantorders%ROWTYPE; v_t restaurantcashtransactions%ROWTYPE;
        v_count INT := 0; ln RECORD;
BEGIN
    BEGIN v_n := split_part(p_paymentid, '-', 2)::INT; EXCEPTION WHEN OTHERS THEN v_n := NULL; END;
    IF v_n IS NULL OR v_kind NOT IN ('CP', 'OP') THEN RAISE EXCEPTION 'Payment not found for this company.'; END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to reverse a payment.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    IF v_kind = 'CP' THEN
        SELECT * INTO v_cp FROM restaurantcustomerpayments p WHERE p.customerpaymentid = v_n AND p.farmid = p_farmid FOR UPDATE;
        IF v_cp.customerpaymentid IS NULL THEN RAISE EXCEPTION 'Payment not found for this company.'; END IF;
        IF v_cp.status = 'Reversed' THEN RAISE EXCEPTION 'This payment has already been reversed.'; END IF;
        FOR ln IN SELECT x.allocationid, x.orderpaymentid, op.orderid FROM restaurantcustomerpaymentlines x
                   JOIN restaurantorderpayments op ON op.orderpaymentid = x.orderpaymentid
                  WHERE x.paymentid = v_n ORDER BY x.allocationid
        LOOP
            PERFORM 1 FROM restaurantorders o WHERE o.orderid = ln.orderid FOR UPDATE;
            UPDATE restaurantorderpayments SET status = 'Voided' WHERE orderpaymentid = ln.orderpaymentid;
            UPDATE customerpaymentallocation SET status = 'Reversed', reversedby = p_reversedby,
                   reversedat = NOW(), reversalreason = btrim(p_reason)
             WHERE allocationid = ln.allocationid;
            PERFORM fnrestaurant_order_settle(ln.orderid, p_farmid);
            v_count := v_count + 1;
        END LOOP;
        UPDATE restaurantcustomerpayments SET status = 'Reversed', reversedby = p_reversedby, reversedat = NOW(),
               reversalreason = btrim(p_reason) WHERE customerpaymentid = v_n;
        PERFORM fnrestaurant_post(p_farmid, v_cp.cashaccountid, CURRENT_DATE, -v_cp.totalamount, 'CustomerPaymentReversal', v_n,
                                  'Reversal of payment CP-' || v_n || ' — ' || btrim(p_reason), p_reversedby,
                                  (SELECT t.cashtxnid FROM restaurantcashtransactions t
                                    WHERE t.sourcetype = 'CustomerPayment' AND t.sourceid = v_n));
        RETURN v_count;
    END IF;

    SELECT * INTO v_op FROM restaurantorderpayments p WHERE p.orderpaymentid = v_n AND p.farmid = p_farmid FOR UPDATE;
    IF v_op.orderpaymentid IS NULL OR v_op.amount <= 0 THEN RAISE EXCEPTION 'Payment not found for this company.'; END IF;
    IF EXISTS (SELECT 1 FROM restaurantcustomerpaymentlines x WHERE x.orderpaymentid = v_n) THEN
        RAISE EXCEPTION 'This is part of a customer payment. Reverse that payment instead.';
    END IF;
    IF v_op.status <> 'Completed' THEN RAISE EXCEPTION 'This payment has already been reversed.'; END IF;
    IF NOT fnrestaurant_is_cash_method(v_op.paymentmethod) THEN
        RAISE EXCEPTION 'A % payment cannot be reversed here. To return value to a gift card, reload it from Gift Cards.', v_op.paymentmethod;
    END IF;
    SELECT * INTO v_o FROM restaurantorders o WHERE o.orderid = v_op.orderid FOR UPDATE;
    IF v_o.status = 'Completed' AND NOT EXISTS (SELECT 1 FROM restaurantorderpaylater l WHERE l.orderid = v_o.orderid) THEN
        RAISE EXCEPTION 'Order % is completed and has no customer to owe it. Refund it on the order instead.', v_o.ordernumber;
    END IF;
    IF v_o.status IN ('Refunded', 'Cancelled') THEN
        RAISE EXCEPTION 'Order % is %; its payments cannot be reversed.', v_o.ordernumber, lower(v_o.status);
    END IF;

    UPDATE restaurantorderpayments SET status = 'Voided' WHERE orderpaymentid = v_n;
    INSERT INTO restaurantorderpaymentreversals (orderpaymentid, farmid, reason, reversedby)
    VALUES (v_n, p_farmid, btrim(p_reason), p_reversedby);
    SELECT * INTO v_t FROM restaurantcashtransactions t WHERE t.sourcetype = 'OrderPayment' AND t.sourceid = v_n;
    IF v_t.cashtxnid IS NOT NULL THEN
        PERFORM fnrestaurant_post(p_farmid, v_t.cashaccountid, CURRENT_DATE, -v_t.amount, 'OrderPaymentReversal', v_n,
                                  'Reversal of payment on ' || v_o.ordernumber || ' — ' || btrim(p_reason), p_reversedby,
                                  v_t.cashtxnid);
    END IF;
    PERFORM fnrestaurant_order_settle(v_o.orderid, p_farmid);
    RETURN 1;
END $$;

-- -----------------------------------------------------------------------------
-- 6. Payments received, allocations, statement, audit
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_customerpayment_history(p_farmid TEXT, p_customerid INT DEFAULT NULL,
                                                     p_saleid INT DEFAULT NULL, p_from DATE DEFAULT NULL,
                                                     p_to DATE DEFAULT NULL)
RETURNS TABLE(paymentid TEXT, paymentnumber TEXT, partyid INT, partyname TEXT, paymentdate DATE, totalamount NUMERIC,
              paymentmethod TEXT, reference TEXT, notes TEXT, sourcetype TEXT, status TEXT, allocationcount INT,
              cashaccountid INT, createdby TEXT, reversedby TEXT, reversedat TIMESTAMP, reversalreason TEXT,
              saleid INT, saletotal NUMERIC, balancebefore NUMERIC, amountapplied NUMERIC, balanceafter NUMERIC,
              createdat TIMESTAMP)
LANGUAGE sql STABLE AS $$
    SELECT * FROM (
        SELECT 'CP-' || p.customerpaymentid, 'CP-' || p.customerpaymentid, p.customerid, c.name::TEXT, p.paymentdate,
               p.totalamount, p.paymentmethod, p.referenceno, p.notes, p.sourcetype, p.status, a.n,
               p.cashaccountid, p.createdby, p.reversedby, p.reversedat, p.reversalreason,
               CASE WHEN a.n = 1 THEN a.saleid END, CASE WHEN a.n = 1 THEN o.totalamount END::NUMERIC,
               CASE WHEN a.n = 1 THEN a.before END, CASE WHEN a.n = 1 THEN a.applied END,
               CASE WHEN a.n = 1 THEN a.after END, p.createdat
          FROM restaurantcustomerpayments p
          JOIN restaurantcustomers c ON c.customerid = p.customerid
         CROSS JOIN LATERAL (
                SELECT COUNT(*)::INT AS n, MIN(x.saleid) AS saleid, MIN(x.salebalancebefore) AS before,
                       MIN(x.amountapplied) AS applied, MIN(x.salebalanceafter) AS after
                  FROM customerpaymentallocation x
                 WHERE x.module = 'restaurant' AND x.farmid = p_farmid AND x.paymentid = p.customerpaymentid) a
          LEFT JOIN restaurantorders o ON o.orderid = a.saleid
         WHERE p.farmid = p_farmid
           AND (p_customerid IS NULL OR p.customerid = p_customerid)
           AND (p_saleid IS NULL OR EXISTS (SELECT 1 FROM customerpaymentallocation x
                                             WHERE x.module = 'restaurant' AND x.farmid = p_farmid
                                               AND x.paymentid = p.customerpaymentid AND x.saleid = p_saleid))
           AND (p_from IS NULL OR p.paymentdate >= p_from) AND (p_to IS NULL OR p.paymentdate <= p_to)
        UNION ALL
        SELECT 'OP-' || op.orderpaymentid, 'OP-' || op.orderpaymentid, o.customerid,
               COALESCE(c.name, NULLIF(btrim(o.customername), ''), 'Walk-in')::TEXT, op.createdat::DATE,
               op.amount, op.paymentmethod, op.reference, NULL::TEXT, 'SaleEntry',
               CASE WHEN op.status = 'Completed' THEN 'Posted' ELSE 'Reversed' END, 1,
               t.cashaccountid, op.processedby, rv.reversedby, rv.reversedat, rv.reason,
               op.orderid, o.totalamount::NUMERIC, NULL::NUMERIC, op.amount, NULL::NUMERIC, op.createdat
          FROM restaurantorderpayments op
          JOIN restaurantorders o ON o.orderid = op.orderid
          LEFT JOIN restaurantcustomers c ON c.customerid = o.customerid AND c.farmid = p_farmid
          LEFT JOIN restaurantorderpaymentreversals rv ON rv.orderpaymentid = op.orderpaymentid
          LEFT JOIN restaurantcashtransactions t ON t.sourcetype = 'OrderPayment' AND t.sourceid = op.orderpaymentid
         WHERE op.farmid = p_farmid AND op.amount > 0
           AND (op.status = 'Completed' OR rv.orderpaymentid IS NOT NULL)
           AND NOT EXISTS (SELECT 1 FROM restaurantcustomerpaymentlines x WHERE x.orderpaymentid = op.orderpaymentid)
           AND (p_customerid IS NULL OR o.customerid = p_customerid)
           AND (p_saleid IS NULL OR op.orderid = p_saleid)
           AND (p_from IS NULL OR op.createdat::DATE >= p_from) AND (p_to IS NULL OR op.createdat::DATE <= p_to)
    ) h
    ORDER BY 5 DESC, 23 DESC;
$$;

CREATE FUNCTION sprestaurant_customerpayment_allocations(p_farmid TEXT, p_paymentid TEXT)
RETURNS TABLE(allocationid INT, documenttype TEXT, documentid INT, reference TEXT, documentdate DATE, label TEXT,
              documenttotal NUMERIC, amountapplied NUMERIC, balancebefore NUMERIC, balanceafter NUMERIC, status TEXT)
LANGUAGE sql STABLE AS $$
    SELECT x.allocationid, 'Order'::TEXT, x.saleid, o.ordernumber::TEXT, o.createdat::DATE, o.ordertype::TEXT,
           o.totalamount::NUMERIC, x.amountapplied, x.salebalancebefore, x.salebalanceafter, x.status
      FROM customerpaymentallocation x
      JOIN restaurantorders o ON o.orderid = x.saleid
     WHERE upper(split_part(p_paymentid, '-', 1)) = 'CP' AND x.module = 'restaurant' AND x.farmid = p_farmid
       AND x.paymentid::TEXT = split_part(p_paymentid, '-', 2)
    UNION ALL
    SELECT op.orderpaymentid, 'Order'::TEXT, op.orderid, o.ordernumber::TEXT, o.createdat::DATE, o.ordertype::TEXT,
           o.totalamount::NUMERIC, op.amount, NULL::NUMERIC, NULL::NUMERIC,
           CASE WHEN op.status = 'Completed' THEN 'Posted' ELSE 'Reversed' END
      FROM restaurantorderpayments op
      JOIN restaurantorders o ON o.orderid = op.orderid
     WHERE upper(split_part(p_paymentid, '-', 1)) = 'OP' AND op.farmid = p_farmid
       AND op.orderpaymentid::TEXT = split_part(p_paymentid, '-', 2);
$$;

-- A customer's pay-later orders (debits) and the posted payments on them
-- (credits), with an opening balance line when a start date is given.
CREATE FUNCTION sprestaurant_customerstatement(p_farmid TEXT, p_customerid INT, p_from DATE DEFAULT NULL,
                                               p_to DATE DEFAULT NULL)
RETURNS TABLE(entrydate DATE, entrytype TEXT, reference TEXT, description TEXT, debit NUMERIC, credit NUMERIC,
              runningbalance NUMERIC, documenttype TEXT, documentid INT, paymentid TEXT, allocationcount INT,
              sourcetype TEXT)
LANGUAGE sql STABLE AS $$
    WITH e AS (
        SELECT r.orderdate AS d, 1 AS k, 'Sale'::TEXT AS t, r.ordernumber AS ref, 'Pay-later order ' || r.ordernumber AS descr,
               r.totalamount AS dr, 0::NUMERIC AS cr, 'Order'::TEXT AS dt, r.orderid AS did, NULL::TEXT AS pid,
               NULL::INT AS ac, NULL::TEXT AS st, r.orderid AS seq
          FROM fnrestaurant_receivables(p_farmid) r WHERE r.customerid = p_customerid
        UNION ALL
        SELECT p.paymentdate, 2, 'Payment', 'CP-' || p.customerpaymentid, 'Payment (' || p.paymentmethod || ')',
               0, p.totalamount, NULL, NULL, 'CP-' || p.customerpaymentid,
               (SELECT COUNT(*)::INT FROM restaurantcustomerpaymentlines x WHERE x.paymentid = p.customerpaymentid),
               p.sourcetype, p.customerpaymentid
          FROM restaurantcustomerpayments p
         WHERE p.farmid = p_farmid AND p.customerid = p_customerid AND p.status = 'Posted'
        UNION ALL
        SELECT op.createdat::DATE, 2, 'Payment', 'OP-' || op.orderpaymentid,
               'Paid on ' || o.ordernumber || ' (' || op.paymentmethod || ')',
               0, op.amount, 'Order', op.orderid, 'OP-' || op.orderpaymentid, 1, 'SaleEntry', op.orderpaymentid
          FROM restaurantorderpayments op
          JOIN restaurantorderpaylater l ON l.orderid = op.orderid AND l.customerid = p_customerid
          JOIN restaurantorders o ON o.orderid = op.orderid AND o.status = 'Completed'
         WHERE op.farmid = p_farmid AND op.status = 'Completed' AND op.amount <> 0
           AND NOT EXISTS (SELECT 1 FROM restaurantcustomerpaymentlines x WHERE x.orderpaymentid = op.orderpaymentid)
    ), opening AS (
        SELECT COALESCE(SUM(e.dr - e.cr), 0) AS bal FROM e WHERE p_from IS NOT NULL AND e.d < p_from
    ), lines AS (
        SELECT p_from AS d, 0 AS k, 'OpeningBalance'::TEXT AS t, NULL::TEXT AS ref, 'Balance brought forward' AS descr,
               GREATEST(o.bal, 0) AS dr, GREATEST(-o.bal, 0) AS cr, NULL::TEXT AS dt, NULL::INT AS did, NULL::TEXT AS pid,
               NULL::INT AS ac, NULL::TEXT AS st, 0 AS seq
          FROM opening o WHERE p_from IS NOT NULL
        UNION ALL
        SELECT * FROM e WHERE (p_from IS NULL OR e.d >= p_from) AND (p_to IS NULL OR e.d <= p_to)
    )
    SELECT l.d, l.t, l.ref, l.descr, l.dr::NUMERIC(14,2), l.cr::NUMERIC(14,2),
           SUM(l.dr - l.cr) OVER (ORDER BY l.d NULLS FIRST, l.k, l.seq ROWS UNBOUNDED PRECEDING)::NUMERIC(14,2),
           l.dt, l.did, l.pid, l.ac, l.st
      FROM lines l
     ORDER BY l.d NULLS FIRST, l.k, l.seq;
$$;

-- Orders whose paid amount disagrees with their payments. Empty when healthy.
CREATE FUNCTION sprestaurant_customerbalance_audit(p_farmid TEXT)
RETURNS TABLE(side TEXT, documenttype TEXT, documentid INT, amountpaid NUMERIC, allocated NUMERIC, difference NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT 'customer'::TEXT, 'Order'::TEXT, o.orderid, o.paidamount::NUMERIC, p.s::NUMERIC, (o.paidamount - p.s)::NUMERIC
      FROM restaurantorders o
     CROSS JOIN LATERAL (SELECT COALESCE(SUM(x.amount), 0) AS s FROM restaurantorderpayments x
                          WHERE x.orderid = o.orderid AND x.status = 'Completed') p
     WHERE o.farmid = p_farmid AND COALESCE(o.paidamount, 0) <> p.s
       AND EXISTS (SELECT 1 FROM restaurantorderpaylater l WHERE l.orderid = o.orderid);
$$;

-- -----------------------------------------------------------------------------
-- 7. Cash-flow detail (from 329) and the profit-vs-cash bridge (from 330),
--    re-emitted with only the marked (333) changes.
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
               -- 333: pay-later orders collected, and payment reversals (Operating)
               WHEN 'CustomerPayment' THEN 'Customer payments'
               WHEN 'CustomerPaymentReversal' THEN 'Customer payment corrections'
               WHEN 'OrderPaymentReversal' THEN 'Sales payment corrections'
               ELSE 'Other' END::TEXT,
           r.createdat
      FROM sprestaurantcashflow_rows(p_farmid, p_fromdate, p_todate) r
      LEFT JOIN restaurantorderpayments p ON r.sourcetype = 'OrderPayment' AND p.orderpaymentid = r.sourceid
      LEFT JOIN restaurantexpenses e ON r.sourcetype = 'Expense' AND e.expenseid = r.sourceid;
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
-- 8. Verification (read-only)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF position('CustomerPayment' in pg_get_functiondef('sprestaurant_report_cash_profit_bridge'::regproc)) = 0
       OR position('stock_internal_use' in pg_get_functiondef('sprestaurant_report_cash_profit_bridge'::regproc)) = 0 THEN
        RAISE EXCEPTION '333 verification failed: the bridge lost an arm';
    END IF;
    IF position('CustomerPayment' in pg_get_functiondef('sprestaurantcashflow_detail'::regproc)) = 0 THEN
        RAISE EXCEPTION '333 verification failed: cash-flow detail does not categorise CustomerPayment';
    END IF;
END $$;

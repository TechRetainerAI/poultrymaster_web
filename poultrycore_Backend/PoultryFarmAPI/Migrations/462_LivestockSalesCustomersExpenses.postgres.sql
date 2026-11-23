-- 462: Livestock sales, customer payments and balances, paid expenses.
--
-- Needs 458-461.
--
-- 1. Sales (livestocksales + lines). Customers are the shared `customer`
--    table (the shared Customer API every company type uses). A line is:
--      'Animals' -- head sold out of a group (a 'Sale' head movement);
--      'Tagged'  -- one tagged animal (its 'Sale' movement; it is marked Sold);
--      'Product' -- stock sold: eggs and milk from the daily records (459's
--                   produce items), meat, manure, or any other stock item.
--                   Its cost is what the stock cost (average), kept on the line.
--    Everything a sale posts carries sourcetype 'Sale', so reversing the sale
--    undoes it all. What was received at the time goes into a cash account.
--    A sale with no customer (walk-in) must be paid in full.
--    Animals still under a meat withdrawal (460) are refused unless the sale
--    says it overrides it -- the person selling is told and must confirm.
--
-- 2. Customer payments (livestockcustomerpayments + allocations): money in,
--    set against the customer's oldest unpaid sales first; more than is owed
--    is refused.
--
-- 3. Paid expenses (livestockexpenses): labour, vet, transport, fuel... paid
--    from a cash account at the time, optionally for one group. A bill owed to
--    a supplier is an 'Expense' line on a purchase (461) instead.
--
-- 4. IAM: sales <- sales, customers <- customers, customer-payments <-
--    customer-payments, customer-balances <- customer-balances, expenses <-
--    expenses. (The shared Customer API's *.customers resolves to
--    livestock.customers on a Livestock farm.)

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Sales
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestocksales (
    saleid        serial PRIMARY KEY,
    farmid        text NOT NULL,
    customerid    integer REFERENCES customer(customerid),
    saledate      date NOT NULL,
    reference     text,
    duedate       date,
    total         numeric(14,2) NOT NULL CHECK (total >= 0),
    notes         text,
    withdrawaloverride text,          -- set when animals under a withdrawal period were sold anyway, and why
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text
);
CREATE INDEX IF NOT EXISTS ixlivestocksales_farm ON livestocksales (farmid, saledate) WHERE reversedat IS NULL;

CREATE TABLE IF NOT EXISTS livestocksalelines (
    lineid     serial PRIMARY KEY,
    saleid     integer NOT NULL REFERENCES livestocksales(saleid),
    linetype   text NOT NULL CHECK (linetype IN ('Animals', 'Tagged', 'Product')),
    groupid    integer REFERENCES livestockgroups(groupid),
    animalid   integer REFERENCES livestockanimals(animalid),
    itemid     integer REFERENCES livestockitems(itemid),
    quantity   numeric(14,3) NOT NULL CHECK (quantity > 0),
    unitprice  numeric(14,4) NOT NULL CHECK (unitprice >= 0),
    linetotal  numeric(14,2) NOT NULL,
    costtotal  numeric(14,2),          -- Product lines: what the stock sold had cost
    weightkg   numeric(12,2),          -- live weight sold, when animals are sold by weight
    CHECK ((linetype = 'Animals' AND groupid IS NOT NULL) OR (linetype = 'Tagged' AND animalid IS NOT NULL)
           OR (linetype = 'Product' AND itemid IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS ixlivestocksalelines_sale ON livestocksalelines (saleid);

CREATE TABLE IF NOT EXISTS livestockcustomerpayments (
    paymentid     serial PRIMARY KEY,
    farmid        text NOT NULL,
    customerid    integer REFERENCES customer(customerid),   -- NULL: a walk-in sale paid at the time
    paymentdate   date NOT NULL,
    amount        numeric(14,2) NOT NULL CHECK (amount > 0),
    accountid     integer NOT NULL REFERENCES livestockcashaccounts(accountid),
    reference     text,
    notes         text,
    isupfront     boolean NOT NULL DEFAULT FALSE,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text
);
CREATE TABLE IF NOT EXISTS livestockcustomerallocations (
    allocationid serial PRIMARY KEY,
    paymentid    integer NOT NULL REFERENCES livestockcustomerpayments(paymentid),
    saleid       integer NOT NULL REFERENCES livestocksales(saleid),
    amount       numeric(14,2) NOT NULL CHECK (amount > 0)
);
CREATE INDEX IF NOT EXISTS ixlivestockcustomerallocations_sale ON livestockcustomerallocations (saleid);

CREATE OR REPLACE FUNCTION public.fnlivestock_salepaid(p_saleid integer)
 RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(SUM(al.amount), 0) FROM livestockcustomerallocations al
    JOIN livestockcustomerpayments p ON p.paymentid = al.paymentid AND p.reversedat IS NULL
    WHERE al.saleid = p_saleid;
$f$;

CREATE OR REPLACE FUNCTION public.fnlivestock_customerowes(p_farmid text, p_customerid integer)
 RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(SUM(s.total - fnlivestock_salepaid(s.saleid)), 0) FROM livestocksales s
    WHERE s.farmid = p_farmid AND s.customerid = p_customerid AND s.reversedat IS NULL;
$f$;

CREATE OR REPLACE FUNCTION public.fnlivestock_salejson(p_id integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'saleId', s.saleid, 'customerId', s.customerid, 'customerName', c.name, 'customerPhone', c.contactphone,
        'date', s.saledate, 'reference', s.reference, 'dueDate', s.duedate, 'total', s.total, 'notes', s.notes,
        'withdrawalOverride', s.withdrawaloverride,
        'paid', fnlivestock_salepaid(s.saleid),
        'owed', CASE WHEN s.reversedat IS NULL THEN s.total - fnlivestock_salepaid(s.saleid) ELSE 0 END,
        'cost', (SELECT COALESCE(SUM(l.costtotal), 0) FROM livestocksalelines l WHERE l.saleid = s.saleid),
        'status', CASE WHEN s.reversedat IS NOT NULL THEN 'Reversed'
                       WHEN fnlivestock_salepaid(s.saleid) >= s.total THEN 'Paid'
                       WHEN fnlivestock_salepaid(s.saleid) > 0 THEN 'PartPaid' ELSE 'Unpaid' END,
        'overdue', s.reversedat IS NULL AND s.duedate IS NOT NULL AND s.duedate < (now() at time zone 'utc')::date
                   AND fnlivestock_salepaid(s.saleid) < s.total,
        'lines', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'lineId', l.lineid, 'lineType', l.linetype, 'groupId', l.groupid, 'groupName', g.name,
                    'animalId', l.animalid, 'tagNumber', a.tagnumber, 'itemId', l.itemid, 'itemName', i.name, 'unit', i.unit,
                    'speciesName', COALESCE(sp1.name, sp2.name), 'quantity', l.quantity, 'unitPrice', l.unitprice,
                    'lineTotal', l.linetotal, 'costTotal', l.costtotal, 'weightKg', l.weightkg) ORDER BY l.lineid), '[]'::jsonb)
                  FROM livestocksalelines l
                  LEFT JOIN livestockgroups g ON g.groupid = l.groupid
                  LEFT JOIN livestockanimals a ON a.animalid = l.animalid
                  LEFT JOIN livestockitems i ON i.itemid = l.itemid
                  LEFT JOIN livestockspecies sp1 ON sp1.speciescode = g.speciescode
                  LEFT JOIN livestockspecies sp2 ON sp2.speciescode = a.speciescode
                  WHERE l.saleid = s.saleid),
        'payments', (SELECT COALESCE(jsonb_agg(jsonb_build_object('paymentId', p.paymentid, 'date', p.paymentdate,
                        'amount', al.amount, 'accountName', ac.name, 'isUpfront', p.isupfront, 'reversedAt', p.reversedat)
                        ORDER BY p.paymentdate), '[]'::jsonb)
                     FROM livestockcustomerallocations al JOIN livestockcustomerpayments p ON p.paymentid = al.paymentid
                     JOIN livestockcashaccounts ac ON ac.accountid = p.accountid WHERE al.saleid = s.saleid),
        'createdBy', s.createdby, 'reversedAt', s.reversedat, 'reverseReason', s.reversereason)
    FROM livestocksales s LEFT JOIN customer c ON c.customerid = s.customerid
    WHERE s.saleid = p_id;
$f$;

-- p_filter: {customerId, status: Unpaid, from, to, groupId}
CREATE OR REPLACE FUNCTION public.splivestocksale_list(p_farmid text, p_filter jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(fnlivestock_salejson(s.saleid) ORDER BY s.saledate DESC, s.saleid DESC), '[]'::jsonb)
    FROM livestocksales s
    WHERE s.farmid = p_farmid
      AND (NULLIF(p_filter->>'customerId', '') IS NULL OR s.customerid = (p_filter->>'customerId')::int)
      AND (COALESCE(p_filter->>'status', '') <> 'Unpaid' OR (s.reversedat IS NULL AND fnlivestock_salepaid(s.saleid) < s.total))
      AND (NULLIF(p_filter->>'from', '') IS NULL OR s.saledate >= (p_filter->>'from')::date)
      AND (NULLIF(p_filter->>'to', '') IS NULL OR s.saledate <= (p_filter->>'to')::date)
      AND (NULLIF(p_filter->>'groupId', '') IS NULL OR EXISTS (
            SELECT 1 FROM livestocksalelines l LEFT JOIN livestockanimals a ON a.animalid = l.animalid
            WHERE l.saleid = s.saleid AND COALESCE(l.groupid, a.groupid) = (p_filter->>'groupId')::int));
$f$;

CREATE OR REPLACE FUNCTION public.splivestocksale_get(p_farmid text, p_id integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM livestocksales WHERE saleid = p_id AND farmid = p_farmid) THEN
        RAISE EXCEPTION 'That sale was not found.' USING ERRCODE = 'P0001';
    END IF;
    RETURN fnlivestock_salejson(p_id);
END
$f$;

-- Takes money in and sets it against the customer's oldest unpaid sales (or
-- the one sale given). Shared by the sale itself (upfront) and Receive Payment.
CREATE OR REPLACE FUNCTION public.splivestockcustomerpayment_core(p_farmid text, p_customerid integer, p_date date, p_amount numeric,
    p_accountid integer, p_reference text, p_notes text, p_by text, p_saleid integer DEFAULT NULL, p_upfront boolean DEFAULT FALSE)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_id integer; v_left numeric := p_amount; r record; v_take numeric; v_owes numeric; v_name text;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Enter the amount received.' USING ERRCODE = 'P0001';
    END IF;
    IF p_customerid IS NULL AND p_saleid IS NULL THEN
        RAISE EXCEPTION 'Choose the customer.' USING ERRCODE = 'P0001';
    END IF;
    IF p_saleid IS NULL THEN
        v_owes := fnlivestock_customerowes(p_farmid, p_customerid);
        IF p_amount > v_owes THEN
            RAISE EXCEPTION 'This customer owes %; you cannot receive more than that.', to_char(v_owes, 'FM999,999,999,990.00')
                USING ERRCODE = 'P0001';
        END IF;
    END IF;
    SELECT name INTO v_name FROM customer WHERE customerid = p_customerid;
    INSERT INTO livestockcustomerpayments (farmid, customerid, paymentdate, amount, accountid, reference, notes, isupfront, createdby)
    VALUES (p_farmid, p_customerid, p_date, p_amount, p_accountid, NULLIF(btrim(p_reference), ''), NULLIF(btrim(p_notes), ''), p_upfront, p_by)
    RETURNING paymentid INTO v_id;
    PERFORM splivestockcash_post(p_farmid, p_accountid, p_date, p_amount, 'CustomerPayment',
        CASE WHEN v_name IS NULL THEN 'Sale paid in cash' ELSE 'Received from ' || v_name END, p_by, 'CustomerPayment', v_id);

    FOR r IN SELECT s.saleid, s.total - fnlivestock_salepaid(s.saleid) AS owed FROM livestocksales s
             WHERE s.farmid = p_farmid AND s.reversedat IS NULL
               AND (CASE WHEN p_saleid IS NOT NULL THEN s.saleid = p_saleid ELSE s.customerid = p_customerid END)
               AND s.total - fnlivestock_salepaid(s.saleid) > 0
             ORDER BY s.saledate, s.saleid LOOP
        EXIT WHEN v_left <= 0;
        v_take := LEAST(v_left, r.owed);
        INSERT INTO livestockcustomerallocations (paymentid, saleid, amount) VALUES (v_id, r.saleid, v_take);
        v_left := v_left - v_take;
    END LOOP;
    IF v_left > 0 THEN
        RAISE EXCEPTION 'More is received than is owed.' USING ERRCODE = 'P0001';
    END IF;
    RETURN v_id;
END
$f$;

-- Record a sale:
--   {customerId, date, reference, dueDate, notes, overrideWithdrawal (reason),
--    lines: [{lineType:'Animals', groupId, quantity, unitPrice, weightKg}
--          | {lineType:'Tagged', animalId, unitPrice, weightKg}
--          | {lineType:'Product', itemId, quantity, unitPrice}],
--    amountReceived, accountId}
CREATE OR REPLACE FUNCTION public.splivestocksale_post(p_farmid text, p_s jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_date   date    := NULLIF(p_s->>'date', '')::date;
    v_cust   integer := NULLIF(p_s->>'customerId', '')::int;
    v_recv   numeric := COALESCE(NULLIF(p_s->>'amountReceived', '')::numeric, 0);
    v_over   text    := NULLIF(btrim(COALESCE(p_s->>'overrideWithdrawal', '')), '');
    v_id     integer;
    v_l      jsonb;
    v_qty    numeric;
    v_price  numeric;
    v_total  numeric := 0;
    v_g      livestockgroups%ROWTYPE;
    v_a      livestockanimals%ROWTYPE;
    v_it     livestockitems%ROWTYPE;
    v_mid    integer;
    v_cost   numeric;
    v_until  date;
    v_cname  text;
BEGIN
    IF v_date IS NULL OR v_date > (now() at time zone 'utc')::date + 1 THEN
        RAISE EXCEPTION 'Enter the sale date (not in the future).' USING ERRCODE = 'P0001';
    END IF;
    IF v_cust IS NOT NULL THEN
        SELECT name INTO v_cname FROM customer WHERE customerid = v_cust AND farmid = p_farmid;
        IF v_cname IS NULL THEN
            RAISE EXCEPTION 'That customer was not found.' USING ERRCODE = 'P0001';
        END IF;
    END IF;
    IF jsonb_array_length(COALESCE(p_s->'lines', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'Add what was sold.' USING ERRCODE = 'P0001';
    END IF;
    IF v_recv < 0 THEN
        RAISE EXCEPTION 'The amount received cannot be negative.' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO livestocksales (farmid, customerid, saledate, reference, duedate, total, notes, withdrawaloverride, createdby)
    VALUES (p_farmid, v_cust, v_date, NULLIF(btrim(p_s->>'reference'), ''), NULLIF(p_s->>'dueDate', '')::date, 0,
            NULLIF(btrim(p_s->>'notes'), ''), v_over, p_by)
    RETURNING saleid INTO v_id;

    FOR v_l IN SELECT * FROM jsonb_array_elements(p_s->'lines') LOOP
        v_price := NULLIF(v_l->>'unitPrice', '')::numeric;
        IF v_price IS NULL OR v_price < 0 THEN
            RAISE EXCEPTION 'Enter the price on every line.' USING ERRCODE = 'P0001';
        END IF;
        CASE COALESCE(v_l->>'lineType', '')
        WHEN 'Animals' THEN
            v_qty := NULLIF(v_l->>'quantity', '')::numeric;
            SELECT * INTO v_g FROM livestockgroups WHERE groupid = NULLIF(v_l->>'groupId', '')::int AND farmid = p_farmid AND NOT isdeleted;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Choose the group the animals came from.' USING ERRCODE = 'P0001';
            END IF;
            IF v_qty IS NULL OR v_qty <= 0 OR v_qty <> trunc(v_qty) THEN
                RAISE EXCEPTION 'Enter how many animals from % (a whole number).', v_g.name USING ERRCODE = 'P0001';
            END IF;
            v_until := (SELECT max((w->>'meatUntil')::date) FROM jsonb_array_elements(splivestockwithdrawals(p_farmid, v_g.groupid)) w);
            IF v_until IS NOT NULL AND v_until >= v_date AND v_over IS NULL THEN
                RAISE EXCEPTION '% is under a medicine withdrawal period until %. Its animals should not be sold for meat before then.',
                    v_g.name, to_char(v_until, 'DD Mon YYYY') USING ERRCODE = 'LV005';
            END IF;
            -- Untagged animals only: tagged ones are sold one by one so their record closes.
            PERFORM splivestockhead_post(p_farmid, v_g.groupid, v_date, 'Sale', -v_qty::int, p_by,
                'Sold' || COALESCE(' to ' || v_cname, ''), NULL, NULL, 'Sale', v_id);
            INSERT INTO livestocksalelines (saleid, linetype, groupid, quantity, unitprice, linetotal, weightkg)
            VALUES (v_id, 'Animals', v_g.groupid, v_qty, v_price, round(v_qty * v_price, 2), NULLIF(v_l->>'weightKg', '')::numeric);
            v_total := v_total + round(v_qty * v_price, 2);
        WHEN 'Tagged' THEN
            SELECT * INTO v_a FROM livestockanimals WHERE animalid = NULLIF(v_l->>'animalId', '')::int AND farmid = p_farmid AND NOT isdeleted FOR UPDATE;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Choose the animal sold.' USING ERRCODE = 'P0001';
            END IF;
            IF v_a.status <> 'Active' THEN
                RAISE EXCEPTION 'Tag % is already marked %.', v_a.tagnumber, lower(v_a.status) USING ERRCODE = 'P0001';
            END IF;
            v_until := (SELECT max((w->>'meatUntil')::date) FROM jsonb_array_elements(splivestockwithdrawals(p_farmid, v_a.groupid)) w);
            IF v_until IS NOT NULL AND v_until >= v_date AND v_over IS NULL THEN
                RAISE EXCEPTION 'Tag % is under a medicine withdrawal period until %.', v_a.tagnumber, to_char(v_until, 'DD Mon YYYY')
                    USING ERRCODE = 'LV005';
            END IF;
            PERFORM splivestockhead_post(p_farmid, v_a.groupid, v_date, 'Sale', -1, p_by,
                'Tag ' || v_a.tagnumber || ' sold' || COALESCE(' to ' || v_cname, ''), NULL, v_a.animalid, 'Sale', v_id);
            UPDATE livestockanimals SET status = 'Sold', statusdate = v_date, statusnotes = 'Sale ' || v_id,
                updatedat = (now() at time zone 'utc'), updatedby = p_by
            WHERE animalid = v_a.animalid;
            INSERT INTO livestocksalelines (saleid, linetype, groupid, animalid, quantity, unitprice, linetotal, weightkg)
            VALUES (v_id, 'Tagged', v_a.groupid, v_a.animalid, 1, v_price, round(v_price, 2), NULLIF(v_l->>'weightKg', '')::numeric);
            v_total := v_total + round(v_price, 2);
        WHEN 'Product' THEN
            v_qty := NULLIF(v_l->>'quantity', '')::numeric;
            SELECT * INTO v_it FROM livestockitems WHERE itemid = NULLIF(v_l->>'itemId', '')::int AND farmid = p_farmid AND NOT isdeleted;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Choose what was sold.' USING ERRCODE = 'P0001';
            END IF;
            IF v_qty IS NULL OR v_qty <= 0 THEN
                RAISE EXCEPTION 'Enter how much % was sold.', v_it.name USING ERRCODE = 'P0001';
            END IF;
            v_mid := splivestockstock_post(p_farmid, v_it.itemid, v_date, 'Usage', -v_qty, NULL, p_by,
                'Sold' || COALESCE(' to ' || v_cname, ''), 'Sale', v_id);
            v_cost := -(SELECT totalcost FROM livestockstockmovements WHERE movementid = v_mid);
            INSERT INTO livestocksalelines (saleid, linetype, itemid, quantity, unitprice, linetotal, costtotal)
            VALUES (v_id, 'Product', v_it.itemid, v_qty, v_price, round(v_qty * v_price, 2), v_cost);
            v_total := v_total + round(v_qty * v_price, 2);
        ELSE
            RAISE EXCEPTION 'Unknown line type "%".', v_l->>'lineType' USING ERRCODE = 'P0001';
        END CASE;
    END LOOP;
    UPDATE livestocksales SET total = v_total WHERE saleid = v_id;

    IF v_recv > v_total THEN
        RAISE EXCEPTION 'More is received (%) than the sale comes to (%).', v_recv, v_total USING ERRCODE = 'P0001';
    END IF;
    IF v_cust IS NULL AND v_recv < v_total THEN
        RAISE EXCEPTION 'A sale with no customer must be paid in full at the time. Choose the customer to sell on credit.' USING ERRCODE = 'P0001';
    END IF;
    IF v_recv > 0 THEN
        PERFORM splivestockcustomerpayment_core(p_farmid, v_cust, v_date, v_recv, NULLIF(p_s->>'accountId', '')::int,
            NULLIF(btrim(p_s->>'reference'), ''), 'Paid with the sale', p_by, v_id, TRUE);
    END IF;
    RETURN v_id;
END
$f$;

-- Reverse a sale entered by mistake: its animals go back into their groups
-- (tagged ones back to alive), its stock back into stock, its upfront money
-- back out of the account. A later payment set against it must be reversed
-- first; a closed group must be reopened first.
CREATE OR REPLACE FUNCTION public.splivestocksale_reverse(p_farmid text, p_id integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_s livestocksales%ROWTYPE; r record;
BEGIN
    SELECT * INTO v_s FROM livestocksales WHERE saleid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND OR v_s.reversedat IS NOT NULL THEN
        RAISE EXCEPTION 'That sale was not found or is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM livestockcustomerallocations al JOIN livestockcustomerpayments cp ON cp.paymentid = al.paymentid
               WHERE al.saleid = p_id AND cp.reversedat IS NULL AND NOT cp.isupfront) THEN
        RAISE EXCEPTION 'A customer payment was set against this sale. Reverse that payment first.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM livestocksalelines l JOIN livestockgroups g ON g.groupid = l.groupid
               WHERE l.saleid = p_id AND g.status = 'Closed') THEN
        RAISE EXCEPTION 'A group these animals came from is closed. Reopen it first.' USING ERRCODE = 'P0001';
    END IF;

    UPDATE livestocksales SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason) WHERE saleid = p_id;
    PERFORM fnlivestock_reversesource('Sale', p_id, p_by, btrim(p_reason));
    UPDATE livestockanimals a SET status = 'Active', statusdate = NULL, statusnotes = NULL,
        updatedat = (now() at time zone 'utc'), updatedby = p_by
    FROM livestocksalelines l WHERE l.saleid = p_id AND l.animalid = a.animalid AND a.status = 'Sold';
    FOR r IN SELECT cp.paymentid FROM livestockcustomerpayments cp
             JOIN livestockcustomerallocations al ON al.paymentid = cp.paymentid AND al.saleid = p_id
             WHERE cp.isupfront AND cp.reversedat IS NULL LOOP
        UPDATE livestockcustomerpayments SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
        WHERE paymentid = r.paymentid;
        PERFORM fnlivestock_reversecash('CustomerPayment', r.paymentid, p_by, btrim(p_reason));
    END LOOP;
END
$f$;

-- What can be sold now: active groups with untagged head, tagged animals,
-- and stock items with stock (produce first).
CREATE OR REPLACE FUNCTION public.splivestocksale_options(p_farmid text, p_date date DEFAULT NULL)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'groups', (SELECT COALESCE(jsonb_agg(jsonb_build_object('groupId', g.groupid, 'name', g.name, 'speciesName', s.name,
                       'head', fnlivestock_grouphead(g.groupid),
                       'untagged', fnlivestock_grouphead(g.groupid) - (SELECT count(*) FROM livestockanimals a
                                    WHERE a.groupid = g.groupid AND a.status = 'Active' AND NOT a.isdeleted),
                       'meatWithdrawalUntil', (SELECT max((w->>'meatUntil')::date) FROM jsonb_array_elements(splivestockwithdrawals(p_farmid, g.groupid)) w))
                       ORDER BY s.sortorder, lower(g.name)), '[]'::jsonb)
                   FROM livestockgroups g JOIN livestockspecies s ON s.speciescode = g.speciescode
                   WHERE g.farmid = p_farmid AND g.status = 'Active' AND NOT g.isdeleted AND fnlivestock_grouphead(g.groupid) > 0),
        'animals', (SELECT COALESCE(jsonb_agg(jsonb_build_object('animalId', a.animalid, 'tagNumber', a.tagnumber, 'name', a.name,
                       'sex', a.sex, 'speciesName', s.singular, 'groupId', a.groupid, 'groupName', g.name)
                       ORDER BY lower(a.tagnumber)), '[]'::jsonb)
                    FROM livestockanimals a JOIN livestockgroups g ON g.groupid = a.groupid JOIN livestockspecies s ON s.speciescode = a.speciescode
                    WHERE a.farmid = p_farmid AND a.status = 'Active' AND NOT a.isdeleted),
        'products', (SELECT COALESCE(jsonb_agg(jsonb_build_object('itemId', i.itemid, 'name', i.name, 'unit', i.unit, 'category', i.category,
                        'stock', fnlivestock_itemstock(i.itemid), 'avgCost', fnlivestock_itemavgcost(i.itemid))
                        ORDER BY (i.category = 'Produce') DESC, lower(i.name)), '[]'::jsonb)
                     FROM livestockitems i WHERE i.farmid = p_farmid AND NOT i.isdeleted AND i.isactive AND fnlivestock_itemstock(i.itemid) > 0));
$f$;

-- ---------------------------------------------------------------------------
-- 2. Customer payments and balances
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.splivestockcustomerpayment_post(p_farmid text, p_pay jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
BEGIN
    IF NULLIF(p_pay->>'customerId', '') IS NULL OR NOT EXISTS (
        SELECT 1 FROM customer WHERE customerid = (p_pay->>'customerId')::int AND farmid = p_farmid) THEN
        RAISE EXCEPTION 'Choose the customer.' USING ERRCODE = 'P0001';
    END IF;
    RETURN splivestockcustomerpayment_core(p_farmid, (p_pay->>'customerId')::int, NULLIF(p_pay->>'date', '')::date,
        NULLIF(p_pay->>'amount', '')::numeric, NULLIF(p_pay->>'accountId', '')::int, p_pay->>'reference', p_pay->>'notes', p_by,
        NULLIF(p_pay->>'saleId', '')::int, FALSE);
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockcustomerpayment_reverse(p_farmid text, p_paymentid integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_p livestockcustomerpayments%ROWTYPE;
BEGIN
    SELECT * INTO v_p FROM livestockcustomerpayments WHERE paymentid = p_paymentid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND OR v_p.reversedat IS NOT NULL THEN
        RAISE EXCEPTION 'That payment was not found or is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF v_p.isupfront THEN
        RAISE EXCEPTION 'This was paid with the sale. Reverse the sale instead.' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockcustomerpayments SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
    WHERE paymentid = p_paymentid;
    PERFORM fnlivestock_reversecash('CustomerPayment', p_paymentid, p_by, btrim(p_reason));
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockcustomerpayment_list(p_farmid text, p_customerid integer DEFAULT NULL)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'paymentId', cp.paymentid, 'customerId', cp.customerid, 'customerName', c.name, 'date', cp.paymentdate,
        'amount', cp.amount, 'accountId', cp.accountid, 'accountName', a.name, 'reference', cp.reference, 'notes', cp.notes,
        'isUpfront', cp.isupfront, 'createdBy', cp.createdby, 'reversedAt', cp.reversedat, 'reverseReason', cp.reversereason)
        ORDER BY cp.paymentdate DESC, cp.paymentid DESC), '[]'::jsonb)
    FROM livestockcustomerpayments cp LEFT JOIN customer c ON c.customerid = cp.customerid
    JOIN livestockcashaccounts a ON a.accountid = cp.accountid
    WHERE cp.farmid = p_farmid AND (p_customerid IS NULL OR cp.customerid = p_customerid);
$f$;

CREATE OR REPLACE FUNCTION public.splivestockcustomer_balances(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.owes DESC, x.name), '[]'::jsonb) FROM (
        SELECT c.name, fnlivestock_customerowes(p_farmid, c.customerid) AS owes, jsonb_build_object(
            'customerId', c.customerid, 'name', c.name, 'phone', c.contactphone,
            'bought', (SELECT COALESCE(SUM(total), 0) FROM livestocksales s WHERE s.farmid = p_farmid AND s.customerid = c.customerid AND s.reversedat IS NULL),
            'paid', (SELECT COALESCE(SUM(amount), 0) FROM livestockcustomerpayments cp WHERE cp.farmid = p_farmid AND cp.customerid = c.customerid AND cp.reversedat IS NULL),
            'owes', fnlivestock_customerowes(p_farmid, c.customerid),
            'overdue', (SELECT COALESCE(SUM(s.total - fnlivestock_salepaid(s.saleid)), 0) FROM livestocksales s
                        WHERE s.farmid = p_farmid AND s.customerid = c.customerid AND s.reversedat IS NULL AND s.duedate < (now() at time zone 'utc')::date),
            'lastSale', (SELECT max(saledate) FROM livestocksales s WHERE s.farmid = p_farmid AND s.customerid = c.customerid AND s.reversedat IS NULL)) AS j
        FROM customer c
        WHERE c.farmid = p_farmid AND EXISTS (SELECT 1 FROM livestocksales s WHERE s.customerid = c.customerid AND s.farmid = p_farmid)
    ) x;
$f$;

CREATE OR REPLACE FUNCTION public.splivestockcustomer_statement(p_farmid text, p_customerid integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE v_name text;
BEGIN
    SELECT name INTO v_name FROM customer WHERE customerid = p_customerid AND farmid = p_farmid;
    IF v_name IS NULL THEN
        RAISE EXCEPTION 'That customer was not found.' USING ERRCODE = 'P0001';
    END IF;
    RETURN jsonb_build_object('customerId', p_customerid, 'name', v_name, 'owes', fnlivestock_customerowes(p_farmid, p_customerid),
        'lines', (SELECT COALESCE(jsonb_agg(jsonb_build_object('date', y.d, 'kind', y.kind, 'id', y.id, 'description', y.descr,
                     'sold', y.sold, 'paid', y.paid, 'balance', y.balance) ORDER BY y.d, y.ord, y.id), '[]'::jsonb)
                  FROM (SELECT x.*, SUM(COALESCE(x.sold, 0) - COALESCE(x.paid, 0)) OVER (ORDER BY x.d, x.ord, x.id) AS balance
                  FROM (SELECT s.saledate AS d, 0 AS ord, 'Sale' AS kind, s.saleid AS id, COALESCE(s.reference, 'Sale') AS descr,
                               s.total AS sold, NULL::numeric AS paid
                        FROM livestocksales s WHERE s.farmid = p_farmid AND s.customerid = p_customerid AND s.reversedat IS NULL
                        UNION ALL
                        SELECT cp.paymentdate, 1, 'Payment', cp.paymentid,
                               CASE WHEN cp.isupfront THEN 'Paid with sale' ELSE COALESCE('Payment ' || cp.reference, 'Payment') END,
                               NULL, cp.amount
                        FROM livestockcustomerpayments cp WHERE cp.farmid = p_farmid AND cp.customerid = p_customerid AND cp.reversedat IS NULL) x) y));
END
$f$;

-- ---------------------------------------------------------------------------
-- 3. Paid expenses
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockexpenses (
    expenseid     serial PRIMARY KEY,
    farmid        text NOT NULL,
    expensedate   date NOT NULL,
    category      text NOT NULL CHECK (fnlivestock_isexpensecategory(category)),
    description   text,
    amount        numeric(14,2) NOT NULL CHECK (amount > 0),
    groupid       integer REFERENCES livestockgroups(groupid),
    accountid     integer NOT NULL REFERENCES livestockcashaccounts(accountid),
    paidto        text,
    reference     text,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text
);
CREATE INDEX IF NOT EXISTS ixlivestockexpenses_farm ON livestockexpenses (farmid, expensedate) WHERE reversedat IS NULL;

CREATE OR REPLACE FUNCTION public.splivestockexpense_post(p_farmid text, p_e jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_date date    := NULLIF(p_e->>'date', '')::date;
    v_amt  numeric := NULLIF(p_e->>'amount', '')::numeric;
    v_cat  text    := NULLIF(p_e->>'category', '');
    v_gid  integer := NULLIF(p_e->>'groupId', '')::int;
    v_id   integer;
BEGIN
    IF NOT fnlivestock_isexpensecategory(v_cat) THEN
        RAISE EXCEPTION 'Choose what the money was spent on.' USING ERRCODE = 'P0001';
    END IF;
    IF v_amt IS NULL OR v_amt <= 0 THEN
        RAISE EXCEPTION 'Enter the amount.' USING ERRCODE = 'P0001';
    END IF;
    IF v_cat = 'Other' AND NULLIF(btrim(p_e->>'description'), '') IS NULL THEN
        RAISE EXCEPTION 'Say what it was for.' USING ERRCODE = 'P0001';
    END IF;
    IF v_gid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM livestockgroups WHERE groupid = v_gid AND farmid = p_farmid AND NOT isdeleted) THEN
        RAISE EXCEPTION 'That group was not found.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO livestockexpenses (farmid, expensedate, category, description, amount, groupid, accountid, paidto, reference, createdby)
    VALUES (p_farmid, v_date, v_cat, NULLIF(btrim(p_e->>'description'), ''), v_amt, v_gid, NULLIF(p_e->>'accountId', '')::int,
            NULLIF(btrim(p_e->>'paidTo'), ''), NULLIF(btrim(p_e->>'reference'), ''), p_by)
    RETURNING expenseid INTO v_id;
    PERFORM splivestockcash_post(p_farmid, NULLIF(p_e->>'accountId', '')::int, v_date, -v_amt, 'Expense',
        v_cat || COALESCE(': ' || NULLIF(btrim(p_e->>'description'), ''), ''), p_by, 'Expense', v_id);
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockexpense_reverse(p_farmid text, p_id integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockexpenses SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
    WHERE expenseid = p_id AND farmid = p_farmid AND reversedat IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That expense was not found or is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM fnlivestock_reversecash('Expense', p_id, p_by, btrim(p_reason));
END
$f$;

-- Every expense in a period: paid expenses, and bills on purchases (461).
-- p_filter: {from, to, category, groupId}
CREATE OR REPLACE FUNCTION public.splivestockexpense_list(p_farmid text, p_filter jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH x AS (
        SELECT 'Paid' AS source, e.expenseid AS id, e.expensedate AS d, e.category, e.description, e.amount, e.groupid,
               a.name AS accountname, e.paidto AS payee, e.reference, e.createdby, e.reversedat, e.reversereason, NULL::int AS purchaseid
        FROM livestockexpenses e JOIN livestockcashaccounts a ON a.accountid = e.accountid
        WHERE e.farmid = p_farmid
        UNION ALL
        SELECT 'Bill', l.lineid, p.purchasedate, l.expensecategory, l.description, l.linetotal, l.groupid,
               NULL, s.name, p.reference, p.createdby, p.reversedat, p.reversereason, p.purchaseid
        FROM livestockpurchaselines l JOIN livestockpurchases p ON p.purchaseid = l.purchaseid
        LEFT JOIN supplier s ON s.supplierid = p.supplierid
        WHERE p.farmid = p_farmid AND l.linetype = 'Expense'
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'source', x.source, 'id', x.id, 'date', x.d, 'category', x.category, 'description', x.description, 'amount', x.amount,
        'groupId', x.groupid, 'groupName', g.name, 'accountName', x.accountname, 'payee', x.payee, 'reference', x.reference,
        'purchaseId', x.purchaseid, 'createdBy', x.createdby, 'reversedAt', x.reversedat, 'reverseReason', x.reversereason)
        ORDER BY x.d DESC, x.id DESC), '[]'::jsonb)
    FROM x LEFT JOIN livestockgroups g ON g.groupid = x.groupid
    WHERE (NULLIF(p_filter->>'from', '') IS NULL OR x.d >= (p_filter->>'from')::date)
      AND (NULLIF(p_filter->>'to', '') IS NULL OR x.d <= (p_filter->>'to')::date)
      AND (NULLIF(p_filter->>'category', '') IS NULL OR x.category = p_filter->>'category')
      AND (NULLIF(p_filter->>'groupId', '') IS NULL OR x.groupid = (p_filter->>'groupId')::int);
$f$;

-- ---------------------------------------------------------------------------
-- 4. IAM
-- ---------------------------------------------------------------------------
DO $iam$
DECLARE v integer := 0;
BEGIN
    v := v + splivestock_iammirror('sales', 'sales', 'Sales & Customers', 'Sales',
            'Selling animals, eggs, milk, meat and other stock, and money received with the sale.', 60);
    v := v + splivestock_iammirror('customers', 'customers', 'Sales & Customers', 'Customers', 'The customers list.', 61);
    v := v + splivestock_iammirror('customer-payments', 'customer-payments', 'Sales & Customers', 'Customer Payments',
            'Receiving what customers owe.', 62);
    v := v + splivestock_iammirror('customer-balances', 'customer-balances', 'Sales & Customers', 'Customer Balances',
            'What each customer owes.', 63);
    v := v + splivestock_iammirror('expenses', 'expenses', 'Finance', 'Expenses',
            'Money spent on labour, vet, transport, fuel and other running costs.', 80);
    RAISE NOTICE '462: % livestock permission key(s) added.', v;
END
$iam$;

COMMIT;

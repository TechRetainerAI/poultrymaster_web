-- 461: Livestock cash accounts, purchases from suppliers, supplier payments
--      and balances, stock losses, head counts, and the animal stock report.
--
-- Needs 458, 459, 460.
--
-- 1. Cash accounts (livestockcashaccounts) and the cash ledger
--    (livestockcashtransactions). An account's balance is its opening balance
--    plus its unreversed transactions -- one definition, like stock and head.
--    Everything that moves money posts here with a sourcetype; transfers and
--    reconciliation arrive with the money step and post into the same ledger.
--
-- 2. Purchases (livestockpurchases + lines). Suppliers are the shared
--    `supplier` table (the shared Supplier API, used by every company type).
--    A line is either a stock item (a 'Purchase' stock movement at the line's
--    cost) or animals (an intake batch, 458, carrying the purchase). Anything
--    paid at the time leaves a cash account. What is owed is the total less
--    what has been paid.
--
-- 3. Supplier payments (livestocksupplierpayments + allocations). A payment
--    leaves a cash account and is set against the supplier's oldest unpaid
--    purchases first. A payment beyond what is owed is refused -- there is no
--    supplier credit here (that is the money step's job).
--
-- 4. Stock losses: a 'Loss' stock movement with a reason (spoiled, expired,
--    spilled, stolen, damaged, other) -- the poultry Loss & Damage page for
--    stock. Animal losses are deaths and culls, already on the head ledger.
--
-- 5. Head count (poultry's Batch Bird Count, 440/441): counted animals per
--    group on a date. Each difference from the head on that date is a
--    'Correction' head movement dated that day.
--
-- 6. The animal stock report: per group over a period -- opening, came in,
--    born, moved in/out, died, culled, sold, corrections, closing.
--
-- 7. IAM: cash <- cash, purchases <- purchase-receipts, suppliers <- suppliers
--    (the shared Supplier API's *.suppliers resolves to livestock.suppliers on
--    a Livestock farm), supplier-payments <- supplier-payments,
--    supplier-balances <- supplier-balances, losses <- loss-records,
--    head-count <- bird-count, animal-stock <- stock.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Cash accounts
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockcashaccounts (
    accountid      serial PRIMARY KEY,
    farmid         text NOT NULL,
    name           text NOT NULL,
    accounttype    text NOT NULL DEFAULT 'Cash' CHECK (accounttype IN ('Cash', 'Bank', 'MobileMoney', 'Other')),
    openingbalance numeric(14,2) NOT NULL DEFAULT 0,
    openingdate    date NOT NULL DEFAULT (now() at time zone 'utc')::date,
    allownegative  boolean NOT NULL DEFAULT FALSE,
    isdefault      boolean NOT NULL DEFAULT FALSE,
    isactive       boolean NOT NULL DEFAULT TRUE,
    notes          text,
    createdat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby      text
);
CREATE UNIQUE INDEX IF NOT EXISTS uxlivestockcashaccounts_name ON livestockcashaccounts (farmid, lower(btrim(name)));

CREATE TABLE IF NOT EXISTS livestockcashtransactions (
    txid          serial PRIMARY KEY,
    farmid        text NOT NULL,
    accountid     integer NOT NULL REFERENCES livestockcashaccounts(accountid),
    txdate        date NOT NULL,
    amount        numeric(14,2) NOT NULL CHECK (amount <> 0),   -- + in, - out
    category      text NOT NULL,                                -- 'Purchase', 'SupplierPayment', 'Sale', 'Expense', ...
    description   text,
    sourcetype    text,
    sourceid      integer,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text
);
CREATE INDEX IF NOT EXISTS ixlivestockcashtransactions_account ON livestockcashtransactions (accountid, txdate) WHERE reversedat IS NULL;
CREATE INDEX IF NOT EXISTS ixlivestockcashtransactions_source ON livestockcashtransactions (sourcetype, sourceid) WHERE reversedat IS NULL;

CREATE OR REPLACE FUNCTION public.fnlivestock_cashbalance(p_accountid integer)
 RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT a.openingbalance + COALESCE((SELECT SUM(t.amount) FROM livestockcashtransactions t
                                        WHERE t.accountid = a.accountid AND t.reversedat IS NULL), 0)
    FROM livestockcashaccounts a WHERE a.accountid = p_accountid;
$f$;

-- Money in (+) or out (-) of an account. Out is refused beyond the balance
-- unless the account allows going below zero.
CREATE OR REPLACE FUNCTION public.splivestockcash_post(p_farmid text, p_accountid integer, p_date date, p_amount numeric,
    p_category text, p_description text, p_by text, p_sourcetype text DEFAULT NULL, p_sourceid integer DEFAULT NULL)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_a livestockcashaccounts%ROWTYPE; v_bal numeric; v_id integer;
BEGIN
    SELECT * INTO v_a FROM livestockcashaccounts WHERE accountid = p_accountid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Choose the account the money is paid from or into.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT v_a.isactive THEN
        RAISE EXCEPTION '% is closed.', v_a.name USING ERRCODE = 'P0001';
    END IF;
    IF p_amount IS NULL OR p_amount = 0 THEN
        RAISE EXCEPTION 'Enter an amount.' USING ERRCODE = 'P0001';
    END IF;
    IF p_date IS NULL OR p_date > (now() at time zone 'utc')::date + 1 THEN
        RAISE EXCEPTION 'Enter a date that is not in the future.' USING ERRCODE = 'P0001';
    END IF;
    IF p_date < v_a.openingdate THEN
        RAISE EXCEPTION '% was opened on %; choose a later date.', v_a.name, to_char(v_a.openingdate, 'DD Mon YYYY') USING ERRCODE = 'P0001';
    END IF;
    v_bal := fnlivestock_cashbalance(p_accountid);
    IF p_amount < 0 AND NOT v_a.allownegative AND v_bal + p_amount < 0 THEN
        RAISE EXCEPTION '% has only % available; % is needed.', v_a.name, to_char(v_bal, 'FM999,999,999,990.00'),
            to_char(-p_amount, 'FM999,999,999,990.00') USING ERRCODE = 'LV004';
    END IF;
    INSERT INTO livestockcashtransactions (farmid, accountid, txdate, amount, category, description, sourcetype, sourceid, createdby)
    VALUES (p_farmid, p_accountid, p_date, round(p_amount, 2), p_category, NULLIF(btrim(p_description), ''), p_sourcetype, p_sourceid, p_by)
    RETURNING txid INTO v_id;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.fnlivestock_reversecash(p_sourcetype text, p_sourceid integer, p_by text, p_reason text)
 RETURNS void LANGUAGE sql AS $f$
    UPDATE livestockcashtransactions SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = p_reason
    WHERE sourcetype = p_sourcetype AND sourceid = p_sourceid AND reversedat IS NULL;
$f$;

CREATE OR REPLACE FUNCTION public.splivestockcashaccount_list(p_farmid text, p_includeinactive boolean DEFAULT FALSE)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'accountId', a.accountid, 'name', a.name, 'accountType', a.accounttype, 'openingBalance', a.openingbalance,
        'openingDate', a.openingdate, 'allowNegative', a.allownegative, 'isDefault', a.isdefault, 'isActive', a.isactive,
        'notes', a.notes, 'balance', fnlivestock_cashbalance(a.accountid),
        'hasTransactions', EXISTS (SELECT 1 FROM livestockcashtransactions t WHERE t.accountid = a.accountid))
        ORDER BY a.isactive DESC, a.isdefault DESC, lower(a.name)), '[]'::jsonb)
    FROM livestockcashaccounts a WHERE a.farmid = p_farmid AND (p_includeinactive OR a.isactive);
$f$;

CREATE OR REPLACE FUNCTION public.splivestockcashaccount_get(p_farmid text, p_accountid integer, p_from date DEFAULT NULL, p_to date DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE v_a livestockcashaccounts%ROWTYPE;
BEGIN
    SELECT * INTO v_a FROM livestockcashaccounts WHERE accountid = p_accountid AND farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That account was not found.' USING ERRCODE = 'P0001';
    END IF;
    RETURN jsonb_build_object(
        'accountId', v_a.accountid, 'name', v_a.name, 'accountType', v_a.accounttype, 'openingBalance', v_a.openingbalance,
        'openingDate', v_a.openingdate, 'allowNegative', v_a.allownegative, 'isDefault', v_a.isdefault, 'isActive', v_a.isactive,
        'notes', v_a.notes, 'balance', fnlivestock_cashbalance(v_a.accountid),
        'balanceBefore', v_a.openingbalance + COALESCE((SELECT SUM(amount) FROM livestockcashtransactions
                         WHERE accountid = v_a.accountid AND reversedat IS NULL AND p_from IS NOT NULL AND txdate < p_from), 0),
        'transactions', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'txId', t.txid, 'date', t.txdate, 'amount', t.amount, 'category', t.category, 'description', t.description,
                'sourceType', t.sourcetype, 'sourceId', t.sourceid, 'createdBy', t.createdby,
                'reversedAt', t.reversedat, 'reverseReason', t.reversereason)
                ORDER BY t.txdate DESC, t.txid DESC), '[]'::jsonb)
            FROM livestockcashtransactions t WHERE t.accountid = v_a.accountid
              AND (p_from IS NULL OR t.txdate >= p_from) AND (p_to IS NULL OR t.txdate <= p_to)));
END
$f$;

-- {accountId?, name, accountType, openingBalance, openingDate, allowNegative, isDefault, isActive, notes}
CREATE OR REPLACE FUNCTION public.splivestockcashaccount_save(p_farmid text, p_a jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id   integer := NULLIF(p_a->>'accountId', '')::int;
    v_name text    := btrim(COALESCE(p_a->>'name', ''));
    v_type text    := COALESCE(NULLIF(p_a->>'accountType', ''), 'Cash');
    v_open numeric := COALESCE(NULLIF(p_a->>'openingBalance', '')::numeric, 0);
    v_od   date    := COALESCE(NULLIF(p_a->>'openingDate', '')::date, (now() at time zone 'utc')::date);
    v_def  boolean := COALESCE((p_a->>'isDefault')::boolean, FALSE);
    v_old  livestockcashaccounts%ROWTYPE;
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Give the account a name.' USING ERRCODE = 'P0001';
    END IF;
    IF v_type NOT IN ('Cash', 'Bank', 'MobileMoney', 'Other') THEN
        RAISE EXCEPTION 'Unknown account type "%".', v_type USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM livestockcashaccounts WHERE farmid = p_farmid AND lower(btrim(name)) = lower(v_name)
               AND accountid IS DISTINCT FROM v_id) THEN
        RAISE EXCEPTION 'You already have an account called "%".', v_name USING ERRCODE = 'P0001';
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO livestockcashaccounts (farmid, name, accounttype, openingbalance, openingdate, allownegative, isdefault, notes, createdby)
        VALUES (p_farmid, v_name, v_type, v_open, v_od, COALESCE((p_a->>'allowNegative')::boolean, FALSE), v_def,
                NULLIF(btrim(p_a->>'notes'), ''), p_by)
        RETURNING accountid INTO v_id;
    ELSE
        SELECT * INTO v_old FROM livestockcashaccounts WHERE accountid = v_id AND farmid = p_farmid FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That account was not found.' USING ERRCODE = 'P0001';
        END IF;
        IF (v_open <> v_old.openingbalance OR v_od <> v_old.openingdate)
           AND EXISTS (SELECT 1 FROM livestockcashtransactions WHERE accountid = v_id AND reversedat IS NULL AND txdate < v_od) THEN
            RAISE EXCEPTION 'Money has moved through this account before that opening date.' USING ERRCODE = 'P0001';
        END IF;
        IF COALESCE((p_a->>'isActive')::boolean, TRUE) = FALSE AND fnlivestock_cashbalance(v_id) <> 0 THEN
            RAISE EXCEPTION '% still holds money. Move it out before closing the account.', v_old.name USING ERRCODE = 'P0001';
        END IF;
        UPDATE livestockcashaccounts SET name = v_name, accounttype = v_type, openingbalance = v_open, openingdate = v_od,
            allownegative = COALESCE((p_a->>'allowNegative')::boolean, allownegative), isdefault = v_def,
            isactive = COALESCE((p_a->>'isActive')::boolean, isactive), notes = NULLIF(btrim(p_a->>'notes'), '')
        WHERE accountid = v_id;
    END IF;
    IF v_def THEN
        UPDATE livestockcashaccounts SET isdefault = FALSE WHERE farmid = p_farmid AND accountid <> v_id;
    END IF;
    RETURN v_id;
END
$f$;

-- ---------------------------------------------------------------------------
-- 2. Purchases
-- ---------------------------------------------------------------------------
-- What a farm spends money on outside stock and animals. Used by bills on
-- purchases here and by paid expenses (462).
CREATE OR REPLACE FUNCTION public.fnlivestock_isexpensecategory(p_cat text)
 RETURNS boolean LANGUAGE sql IMMUTABLE AS $f$
    SELECT COALESCE(p_cat, '') IN ('Labour', 'Veterinary', 'Transport', 'Fuel', 'Utilities', 'Rent', 'Repairs',
                                   'Equipment', 'Fees', 'Security', 'Other');
$f$;

CREATE TABLE IF NOT EXISTS livestockpurchases (
    purchaseid    serial PRIMARY KEY,
    farmid        text NOT NULL,
    supplierid    integer REFERENCES supplier(supplierid),
    purchasedate  date NOT NULL,
    reference     text,                 -- the supplier's invoice / receipt number
    duedate       date,
    total         numeric(14,2) NOT NULL CHECK (total >= 0),
    notes         text,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text
);
CREATE INDEX IF NOT EXISTS ixlivestockpurchases_farm ON livestockpurchases (farmid, purchasedate) WHERE reversedat IS NULL;

CREATE TABLE IF NOT EXISTS livestockpurchaselines (
    lineid      serial PRIMARY KEY,
    purchaseid  integer NOT NULL REFERENCES livestockpurchases(purchaseid),
    linetype    text NOT NULL CHECK (linetype IN ('Item', 'Animals', 'Expense')),
    itemid      integer REFERENCES livestockitems(itemid),
    batchid     integer REFERENCES livestockbatches(batchid),
    expensecategory text,         -- Expense lines: a bill on credit (vet, transport, repairs)
    description     text,
    groupid     integer REFERENCES livestockgroups(groupid),   -- Expense lines: the group it was for, if one
    quantity    numeric(14,3) NOT NULL CHECK (quantity > 0),
    unitcost    numeric(14,4) NOT NULL CHECK (unitcost >= 0),
    linetotal   numeric(14,2) NOT NULL,
    CHECK ((linetype = 'Item' AND itemid IS NOT NULL) OR (linetype = 'Animals' AND batchid IS NOT NULL)
           OR (linetype = 'Expense' AND expensecategory IS NOT NULL))
);

ALTER TABLE livestockbatches ADD COLUMN IF NOT EXISTS purchaseid integer REFERENCES livestockpurchases(purchaseid);

CREATE TABLE IF NOT EXISTS livestocksupplierpayments (
    paymentid     serial PRIMARY KEY,
    farmid        text NOT NULL,
    supplierid    integer REFERENCES supplier(supplierid),   -- NULL: a cash purchase with no supplier
    paymentdate   date NOT NULL,
    amount        numeric(14,2) NOT NULL CHECK (amount > 0),
    accountid     integer NOT NULL REFERENCES livestockcashaccounts(accountid),
    reference     text,
    notes         text,
    isupfront     boolean NOT NULL DEFAULT FALSE,   -- paid with the purchase itself
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text
);
CREATE TABLE IF NOT EXISTS livestocksupplierallocations (
    allocationid serial PRIMARY KEY,
    paymentid    integer NOT NULL REFERENCES livestocksupplierpayments(paymentid),
    purchaseid   integer NOT NULL REFERENCES livestockpurchases(purchaseid),
    amount       numeric(14,2) NOT NULL CHECK (amount > 0)
);
CREATE INDEX IF NOT EXISTS ixlivestocksupplierallocations_purchase ON livestocksupplierallocations (purchaseid);

-- Paid so far on a purchase (unreversed payments only).
CREATE OR REPLACE FUNCTION public.fnlivestock_purchasepaid(p_purchaseid integer)
 RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(SUM(al.amount), 0) FROM livestocksupplierallocations al
    JOIN livestocksupplierpayments p ON p.paymentid = al.paymentid AND p.reversedat IS NULL
    WHERE al.purchaseid = p_purchaseid;
$f$;

CREATE OR REPLACE FUNCTION public.fnlivestock_purchasejson(p_id integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'purchaseId', p.purchaseid, 'supplierId', p.supplierid, 'supplierName', s.name, 'date', p.purchasedate,
        'reference', p.reference, 'dueDate', p.duedate, 'total', p.total, 'notes', p.notes,
        'paid', fnlivestock_purchasepaid(p.purchaseid),
        'owed', CASE WHEN p.reversedat IS NULL THEN p.total - fnlivestock_purchasepaid(p.purchaseid) ELSE 0 END,
        'status', CASE WHEN p.reversedat IS NOT NULL THEN 'Reversed'
                       WHEN fnlivestock_purchasepaid(p.purchaseid) >= p.total THEN 'Paid'
                       WHEN fnlivestock_purchasepaid(p.purchaseid) > 0 THEN 'PartPaid' ELSE 'Unpaid' END,
        'overdue', p.reversedat IS NULL AND p.duedate IS NOT NULL AND p.duedate < (now() at time zone 'utc')::date
                   AND fnlivestock_purchasepaid(p.purchaseid) < p.total,
        'lines', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'lineId', l.lineid, 'lineType', l.linetype, 'itemId', l.itemid, 'itemName', i.name, 'unit', i.unit,
                    'batchId', l.batchid, 'batchCode', b.batchcode, 'speciesName', sp.name,
                    'expenseCategory', l.expensecategory, 'description', l.description, 'groupId', l.groupid,
                    'quantity', l.quantity, 'unitCost', l.unitcost, 'lineTotal', l.linetotal) ORDER BY l.lineid), '[]'::jsonb)
                  FROM livestockpurchaselines l
                  LEFT JOIN livestockitems i ON i.itemid = l.itemid
                  LEFT JOIN livestockbatches b ON b.batchid = l.batchid
                  LEFT JOIN livestockspecies sp ON sp.speciescode = b.speciescode
                  WHERE l.purchaseid = p.purchaseid),
        'payments', (SELECT COALESCE(jsonb_agg(jsonb_build_object('paymentId', sp2.paymentid, 'date', sp2.paymentdate,
                        'amount', al.amount, 'accountName', a.name, 'isUpfront', sp2.isupfront, 'reversedAt', sp2.reversedat)
                        ORDER BY sp2.paymentdate), '[]'::jsonb)
                     FROM livestocksupplierallocations al JOIN livestocksupplierpayments sp2 ON sp2.paymentid = al.paymentid
                     JOIN livestockcashaccounts a ON a.accountid = sp2.accountid WHERE al.purchaseid = p.purchaseid),
        'createdBy', p.createdby, 'reversedAt', p.reversedat, 'reverseReason', p.reversereason)
    FROM livestockpurchases p LEFT JOIN supplier s ON s.supplierid = p.supplierid
    WHERE p.purchaseid = p_id;
$f$;

-- p_filter: {supplierId, status: Unpaid|All, from, to}
CREATE OR REPLACE FUNCTION public.splivestockpurchase_list(p_farmid text, p_filter jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(fnlivestock_purchasejson(p.purchaseid) ORDER BY p.purchasedate DESC, p.purchaseid DESC), '[]'::jsonb)
    FROM livestockpurchases p
    WHERE p.farmid = p_farmid
      AND (NULLIF(p_filter->>'supplierId', '') IS NULL OR p.supplierid = (p_filter->>'supplierId')::int)
      AND (COALESCE(p_filter->>'status', '') <> 'Unpaid' OR (p.reversedat IS NULL AND fnlivestock_purchasepaid(p.purchaseid) < p.total))
      AND (NULLIF(p_filter->>'from', '') IS NULL OR p.purchasedate >= (p_filter->>'from')::date)
      AND (NULLIF(p_filter->>'to', '') IS NULL OR p.purchasedate <= (p_filter->>'to')::date);
$f$;

CREATE OR REPLACE FUNCTION public.splivestockpurchase_get(p_farmid text, p_id integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM livestockpurchases WHERE purchaseid = p_id AND farmid = p_farmid) THEN
        RAISE EXCEPTION 'That purchase was not found.' USING ERRCODE = 'P0001';
    END IF;
    RETURN fnlivestock_purchasejson(p_id);
END
$f$;

-- Record a purchase:
--   {supplierId, date, reference, dueDate, notes,
--    lines: [{lineType:'Item', itemId, quantity, unitCost}
--          | {lineType:'Animals', speciesCode, quantity, unitCost, breed, ageAtIntake}],
--    amountPaid, accountId}
-- All or nothing.
CREATE OR REPLACE FUNCTION public.splivestockpurchase_post(p_farmid text, p_p jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_date  date    := NULLIF(p_p->>'date', '')::date;
    v_sup   integer := NULLIF(p_p->>'supplierId', '')::int;
    v_paid  numeric := COALESCE(NULLIF(p_p->>'amountPaid', '')::numeric, 0);
    v_id    integer;
    v_l     jsonb;
    v_qty   numeric;
    v_cost  numeric;
    v_total numeric := 0;
    v_item  livestockitems%ROWTYPE;
    v_batch integer;
    v_supname text;
BEGIN
    IF v_date IS NULL OR v_date > (now() at time zone 'utc')::date + 1 THEN
        RAISE EXCEPTION 'Enter the purchase date (not in the future).' USING ERRCODE = 'P0001';
    END IF;
    IF v_sup IS NOT NULL THEN
        SELECT name INTO v_supname FROM supplier WHERE supplierid = v_sup AND farmid = p_farmid;
        IF v_supname IS NULL THEN
            RAISE EXCEPTION 'That supplier was not found.' USING ERRCODE = 'P0001';
        END IF;
    END IF;
    IF jsonb_array_length(COALESCE(p_p->'lines', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'Add what was bought.' USING ERRCODE = 'P0001';
    END IF;
    IF v_paid < 0 THEN
        RAISE EXCEPTION 'The amount paid cannot be negative.' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO livestockpurchases (farmid, supplierid, purchasedate, reference, duedate, total, notes, createdby)
    VALUES (p_farmid, v_sup, v_date, NULLIF(btrim(p_p->>'reference'), ''), NULLIF(p_p->>'dueDate', '')::date, 0,
            NULLIF(btrim(p_p->>'notes'), ''), p_by)
    RETURNING purchaseid INTO v_id;

    FOR v_l IN SELECT * FROM jsonb_array_elements(p_p->'lines') LOOP
        v_qty  := NULLIF(v_l->>'quantity', '')::numeric;
        v_cost := NULLIF(v_l->>'unitCost', '')::numeric;
        IF v_qty IS NULL OR v_qty <= 0 THEN
            RAISE EXCEPTION 'Enter a quantity on every line.' USING ERRCODE = 'P0001';
        END IF;
        IF v_cost IS NULL OR v_cost < 0 THEN
            RAISE EXCEPTION 'Enter the price on every line (0 if free).' USING ERRCODE = 'P0001';
        END IF;
        IF COALESCE(v_l->>'lineType', 'Item') = 'Item' THEN
            SELECT * INTO v_item FROM livestockitems WHERE itemid = NULLIF(v_l->>'itemId', '')::int AND farmid = p_farmid AND NOT isdeleted;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Choose the item on every line.' USING ERRCODE = 'P0001';
            END IF;
            PERFORM splivestockstock_post(p_farmid, v_item.itemid, v_date, 'Purchase', v_qty, v_cost, p_by,
                'Bought' || COALESCE(' from ' || v_supname, ''), 'Purchase', v_id);
            INSERT INTO livestockpurchaselines (purchaseid, linetype, itemid, quantity, unitcost, linetotal)
            VALUES (v_id, 'Item', v_item.itemid, v_qty, v_cost, round(v_qty * v_cost, 2));
        ELSIF v_l->>'lineType' = 'Animals' THEN
            IF v_qty <> trunc(v_qty) THEN
                RAISE EXCEPTION 'Animals are counted in whole numbers.' USING ERRCODE = 'P0001';
            END IF;
            v_batch := splivestockbatch_save(p_farmid, jsonb_build_object(
                'speciesCode', v_l->>'speciesCode', 'quantity', v_qty::int, 'intakeDate', v_date, 'source', 'Purchased',
                'supplierId', v_sup, 'costPerHead', v_cost, 'breed', v_l->>'breed', 'ageAtIntake', v_l->>'ageAtIntake',
                'notes', 'Purchase' || COALESCE(' ' || NULLIF(btrim(p_p->>'reference'), ''), '')), p_by);
            UPDATE livestockbatches SET purchaseid = v_id WHERE batchid = v_batch;
            INSERT INTO livestockpurchaselines (purchaseid, linetype, batchid, quantity, unitcost, linetotal)
            VALUES (v_id, 'Animals', v_batch, v_qty, v_cost, round(v_qty * v_cost, 2));
        ELSIF v_l->>'lineType' = 'Expense' THEN
            IF NOT fnlivestock_isexpensecategory(v_l->>'expenseCategory') THEN
                RAISE EXCEPTION 'Choose what the bill was for.' USING ERRCODE = 'P0001';
            END IF;
            IF NULLIF(v_l->>'groupId', '') IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM livestockgroups WHERE groupid = (v_l->>'groupId')::int AND farmid = p_farmid AND NOT isdeleted) THEN
                RAISE EXCEPTION 'That group was not found.' USING ERRCODE = 'P0001';
            END IF;
            INSERT INTO livestockpurchaselines (purchaseid, linetype, expensecategory, description, groupid, quantity, unitcost, linetotal)
            VALUES (v_id, 'Expense', v_l->>'expenseCategory', NULLIF(btrim(v_l->>'description'), ''), NULLIF(v_l->>'groupId', '')::int,
                    v_qty, v_cost, round(v_qty * v_cost, 2));
        ELSE
            RAISE EXCEPTION 'Unknown line type "%".', v_l->>'lineType' USING ERRCODE = 'P0001';
        END IF;
        v_total := v_total + round(v_qty * v_cost, 2);
    END LOOP;
    UPDATE livestockpurchases SET total = v_total WHERE purchaseid = v_id;

    IF v_paid > v_total THEN
        RAISE EXCEPTION 'More is paid (%) than the purchase comes to (%).', v_paid, v_total USING ERRCODE = 'P0001';
    END IF;
    IF v_sup IS NULL AND v_paid < v_total THEN
        RAISE EXCEPTION 'A purchase with no supplier must be paid in full at the time.' USING ERRCODE = 'P0001';
    END IF;
    IF v_paid > 0 THEN
        PERFORM splivestocksupplierpayment_core(p_farmid, v_sup, v_date, v_paid, NULLIF(p_p->>'accountId', '')::int,
            NULLIF(btrim(p_p->>'reference'), ''), 'Paid with the purchase', p_by, v_id, TRUE);
    END IF;
    RETURN v_id;
END
$f$;

-- Reverse a purchase entered by mistake: its stock and animals come back out,
-- its payments go back into their accounts. Refused once its stock is used or
-- its animals are in groups.
CREATE OR REPLACE FUNCTION public.splivestockpurchase_reverse(p_farmid text, p_id integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_p livestockpurchases%ROWTYPE; r record;
BEGIN
    SELECT * INTO v_p FROM livestockpurchases WHERE purchaseid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND OR v_p.reversedat IS NOT NULL THEN
        RAISE EXCEPTION 'That purchase was not found or is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    FOR r IN SELECT l.*, i.name FROM livestockpurchaselines l LEFT JOIN livestockitems i ON i.itemid = l.itemid WHERE l.purchaseid = p_id LOOP
        IF r.linetype = 'Item' AND fnlivestock_itemstock(r.itemid) < r.quantity THEN
            RAISE EXCEPTION 'Some of the % from this purchase has been used, so it cannot be reversed. Correct the stock instead.', r.name
                USING ERRCODE = 'P0001';
        END IF;
        IF r.linetype = 'Animals' AND EXISTS (SELECT 1 FROM livestockgroups g WHERE g.batchid = r.batchid AND NOT g.isdeleted) THEN
            RAISE EXCEPTION 'The animals from this purchase are already in groups. Delete those groups first.' USING ERRCODE = 'P0001';
        END IF;
    END LOOP;
    -- Payments made later against other purchases too cannot be half-undone here.
    IF EXISTS (SELECT 1 FROM livestocksupplierallocations al JOIN livestocksupplierpayments sp ON sp.paymentid = al.paymentid
               WHERE al.purchaseid = p_id AND sp.reversedat IS NULL AND NOT sp.isupfront) THEN
        RAISE EXCEPTION 'A supplier payment was set against this purchase. Reverse that payment first.' USING ERRCODE = 'P0001';
    END IF;

    UPDATE livestockpurchases SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
    WHERE purchaseid = p_id;
    UPDATE livestockstockmovements SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
    WHERE sourcetype = 'Purchase' AND sourceid = p_id AND reversedat IS NULL;
    UPDATE livestockbatches SET isdeleted = TRUE, updatedat = (now() at time zone 'utc'), updatedby = p_by
    WHERE purchaseid = p_id AND NOT isdeleted;
    FOR r IN SELECT sp.paymentid FROM livestocksupplierpayments sp
             JOIN livestocksupplierallocations al ON al.paymentid = sp.paymentid AND al.purchaseid = p_id
             WHERE sp.isupfront AND sp.reversedat IS NULL LOOP
        UPDATE livestocksupplierpayments SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
        WHERE paymentid = r.paymentid;
        PERFORM fnlivestock_reversecash('SupplierPayment', r.paymentid, p_by, btrim(p_reason));
    END LOOP;
END
$f$;

-- ---------------------------------------------------------------------------
-- 3. Supplier payments and balances
-- ---------------------------------------------------------------------------
-- What the farm owes a supplier now.
CREATE OR REPLACE FUNCTION public.fnlivestock_supplierowed(p_farmid text, p_supplierid integer)
 RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(SUM(p.total - fnlivestock_purchasepaid(p.purchaseid)), 0) FROM livestockpurchases p
    WHERE p.farmid = p_farmid AND p.supplierid = p_supplierid AND p.reversedat IS NULL;
$f$;

-- Pays a supplier and sets it against their oldest unpaid purchases (or the
-- one purchase given). Shared by the purchase itself (upfront) and Pay Supplier.
CREATE OR REPLACE FUNCTION public.splivestocksupplierpayment_core(p_farmid text, p_supplierid integer, p_date date, p_amount numeric,
    p_accountid integer, p_reference text, p_notes text, p_by text, p_purchaseid integer DEFAULT NULL, p_upfront boolean DEFAULT FALSE)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_id integer; v_left numeric := p_amount; r record; v_take numeric; v_owed numeric; v_name text;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Enter the amount paid.' USING ERRCODE = 'P0001';
    END IF;
    IF p_supplierid IS NULL AND p_purchaseid IS NULL THEN
        RAISE EXCEPTION 'Choose the supplier.' USING ERRCODE = 'P0001';
    END IF;
    IF p_purchaseid IS NULL THEN
        v_owed := fnlivestock_supplierowed(p_farmid, p_supplierid);
        IF p_amount > v_owed THEN
            RAISE EXCEPTION 'You owe this supplier %; you cannot pay more than that.', to_char(v_owed, 'FM999,999,999,990.00')
                USING ERRCODE = 'P0001';
        END IF;
    END IF;
    SELECT name INTO v_name FROM supplier WHERE supplierid = p_supplierid;
    INSERT INTO livestocksupplierpayments (farmid, supplierid, paymentdate, amount, accountid, reference, notes, isupfront, createdby)
    VALUES (p_farmid, p_supplierid, p_date, p_amount, p_accountid, NULLIF(btrim(p_reference), ''), NULLIF(btrim(p_notes), ''), p_upfront, p_by)
    RETURNING paymentid INTO v_id;

    PERFORM splivestockcash_post(p_farmid, p_accountid, p_date, -p_amount, 'SupplierPayment',
        CASE WHEN v_name IS NULL THEN 'Bought for cash' ELSE 'Paid ' || v_name END, p_by, 'SupplierPayment', v_id);

    FOR r IN SELECT p.purchaseid, p.total - fnlivestock_purchasepaid(p.purchaseid) AS owed FROM livestockpurchases p
             WHERE p.farmid = p_farmid AND p.reversedat IS NULL
               AND (CASE WHEN p_purchaseid IS NOT NULL THEN p.purchaseid = p_purchaseid ELSE p.supplierid = p_supplierid END)
               AND p.total - fnlivestock_purchasepaid(p.purchaseid) > 0
             ORDER BY p.purchasedate, p.purchaseid LOOP
        EXIT WHEN v_left <= 0;
        v_take := LEAST(v_left, r.owed);
        INSERT INTO livestocksupplierallocations (paymentid, purchaseid, amount) VALUES (v_id, r.purchaseid, v_take);
        v_left := v_left - v_take;
    END LOOP;
    IF v_left > 0 THEN
        RAISE EXCEPTION 'More is paid than is owed.' USING ERRCODE = 'P0001';
    END IF;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestocksupplierpayment_post(p_farmid text, p_pay jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
BEGIN
    IF NULLIF(p_pay->>'supplierId', '') IS NULL OR NOT EXISTS (
        SELECT 1 FROM supplier WHERE supplierid = (p_pay->>'supplierId')::int AND farmid = p_farmid) THEN
        RAISE EXCEPTION 'Choose the supplier.' USING ERRCODE = 'P0001';
    END IF;
    RETURN splivestocksupplierpayment_core(p_farmid, (p_pay->>'supplierId')::int, NULLIF(p_pay->>'date', '')::date,
        NULLIF(p_pay->>'amount', '')::numeric, NULLIF(p_pay->>'accountId', '')::int, p_pay->>'reference', p_pay->>'notes', p_by,
        NULLIF(p_pay->>'purchaseId', '')::int, FALSE);
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestocksupplierpayment_reverse(p_farmid text, p_paymentid integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_p livestocksupplierpayments%ROWTYPE;
BEGIN
    SELECT * INTO v_p FROM livestocksupplierpayments WHERE paymentid = p_paymentid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND OR v_p.reversedat IS NOT NULL THEN
        RAISE EXCEPTION 'That payment was not found or is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF v_p.isupfront THEN
        RAISE EXCEPTION 'This was paid with the purchase. Reverse the purchase instead.' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestocksupplierpayments SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
    WHERE paymentid = p_paymentid;
    PERFORM fnlivestock_reversecash('SupplierPayment', p_paymentid, p_by, btrim(p_reason));
END
$f$;

-- Every supplier the farm has bought from: total bought, paid, owed, overdue.
CREATE OR REPLACE FUNCTION public.splivestocksupplier_balances(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.owed DESC, x.name), '[]'::jsonb) FROM (
        SELECT s.name, fnlivestock_supplierowed(p_farmid, s.supplierid) AS owed, jsonb_build_object(
            'supplierId', s.supplierid, 'name', s.name, 'phone', s.contactphone,
            'bought', (SELECT COALESCE(SUM(total), 0) FROM livestockpurchases p WHERE p.farmid = p_farmid AND p.supplierid = s.supplierid AND p.reversedat IS NULL),
            'paid', (SELECT COALESCE(SUM(amount), 0) FROM livestocksupplierpayments sp WHERE sp.farmid = p_farmid AND sp.supplierid = s.supplierid AND sp.reversedat IS NULL),
            'owed', fnlivestock_supplierowed(p_farmid, s.supplierid),
            'overdue', (SELECT COALESCE(SUM(p.total - fnlivestock_purchasepaid(p.purchaseid)), 0) FROM livestockpurchases p
                        WHERE p.farmid = p_farmid AND p.supplierid = s.supplierid AND p.reversedat IS NULL
                          AND p.duedate < (now() at time zone 'utc')::date),
            'lastPurchase', (SELECT max(purchasedate) FROM livestockpurchases p WHERE p.farmid = p_farmid AND p.supplierid = s.supplierid AND p.reversedat IS NULL)) AS j
        FROM supplier s
        WHERE s.farmid = p_farmid AND EXISTS (SELECT 1 FROM livestockpurchases p WHERE p.supplierid = s.supplierid AND p.farmid = p_farmid)
    ) x;
$f$;

-- One supplier: purchases and payments in date order with a running balance.
CREATE OR REPLACE FUNCTION public.splivestocksupplier_statement(p_farmid text, p_supplierid integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE v_name text;
BEGIN
    SELECT name INTO v_name FROM supplier WHERE supplierid = p_supplierid AND farmid = p_farmid;
    IF v_name IS NULL THEN
        RAISE EXCEPTION 'That supplier was not found.' USING ERRCODE = 'P0001';
    END IF;
    RETURN jsonb_build_object('supplierId', p_supplierid, 'name', v_name, 'owed', fnlivestock_supplierowed(p_farmid, p_supplierid),
        'lines', (SELECT COALESCE(jsonb_agg(jsonb_build_object('date', y.d, 'kind', y.kind, 'id', y.id, 'description', y.descr,
                     'bought', y.bought, 'paid', y.paid, 'balance', y.balance)
                     ORDER BY y.d, y.ord, y.id), '[]'::jsonb)
                  FROM (SELECT x.*, SUM(COALESCE(x.bought, 0) - COALESCE(x.paid, 0)) OVER (ORDER BY x.d, x.ord, x.id) AS balance
                  FROM (SELECT p.purchasedate AS d, 0 AS ord, 'Purchase' AS kind, p.purchaseid AS id,
                               COALESCE(p.reference, 'Purchase') AS descr, p.total AS bought, NULL::numeric AS paid
                        FROM livestockpurchases p WHERE p.farmid = p_farmid AND p.supplierid = p_supplierid AND p.reversedat IS NULL
                        UNION ALL
                        SELECT sp.paymentdate, 1, 'Payment', sp.paymentid,
                               CASE WHEN sp.isupfront THEN 'Paid with purchase' ELSE COALESCE('Payment ' || sp.reference, 'Payment') END,
                               NULL, sp.amount
                        FROM livestocksupplierpayments sp WHERE sp.farmid = p_farmid AND sp.supplierid = p_supplierid AND sp.reversedat IS NULL) x) y));
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestocksupplierpayment_list(p_farmid text, p_supplierid integer DEFAULT NULL)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'paymentId', sp.paymentid, 'supplierId', sp.supplierid, 'supplierName', s.name, 'date', sp.paymentdate,
        'amount', sp.amount, 'accountId', sp.accountid, 'accountName', a.name, 'reference', sp.reference, 'notes', sp.notes,
        'isUpfront', sp.isupfront, 'createdBy', sp.createdby, 'reversedAt', sp.reversedat, 'reverseReason', sp.reversereason,
        'purchases', (SELECT COALESCE(jsonb_agg(jsonb_build_object('purchaseId', al.purchaseid, 'amount', al.amount)), '[]'::jsonb)
                      FROM livestocksupplierallocations al WHERE al.paymentid = sp.paymentid))
        ORDER BY sp.paymentdate DESC, sp.paymentid DESC), '[]'::jsonb)
    FROM livestocksupplierpayments sp LEFT JOIN supplier s ON s.supplierid = sp.supplierid
    JOIN livestockcashaccounts a ON a.accountid = sp.accountid
    WHERE sp.farmid = p_farmid AND (p_supplierid IS NULL OR sp.supplierid = p_supplierid);
$f$;

-- ---------------------------------------------------------------------------
-- 4. Stock losses
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.splivestockstock_loss(p_farmid text, p_itemid integer, p_date date, p_quantity numeric,
    p_reason text, p_notes text, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_id integer;
BEGIN
    IF COALESCE(p_reason, '') NOT IN ('Spoiled', 'Expired', 'Spilled', 'Stolen', 'Damaged', 'Other') THEN
        RAISE EXCEPTION 'Say what happened to it.' USING ERRCODE = 'P0001';
    END IF;
    IF p_reason = 'Other' AND NULLIF(btrim(p_notes), '') IS NULL THEN
        RAISE EXCEPTION 'Describe what happened.' USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(p_quantity, 0) <= 0 THEN
        RAISE EXCEPTION 'Enter how much was lost.' USING ERRCODE = 'P0001';
    END IF;
    v_id := splivestockstock_post(p_farmid, p_itemid, p_date, 'Loss', -p_quantity, NULL, p_by, p_notes);
    UPDATE livestockstockmovements SET lossreason = p_reason WHERE movementid = v_id;
    RETURN v_id;
END
$f$;

-- Stock lost and animals lost (deaths, culls) over a period.
CREATE OR REPLACE FUNCTION public.splivestock_losses(p_farmid text, p_from date, p_to date)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'stock', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'movementId', m.movementid, 'date', m.movementdate, 'itemId', m.itemid, 'itemName', i.name, 'unit', i.unit,
                     'quantity', -m.quantity, 'value', -m.totalcost, 'reason', m.lossreason, 'notes', m.notes,
                     'createdBy', m.createdby, 'reversedAt', m.reversedat) ORDER BY m.movementdate DESC, m.movementid DESC), '[]'::jsonb)
                  FROM livestockstockmovements m JOIN livestockitems i ON i.itemid = m.itemid
                  WHERE m.farmid = p_farmid AND m.movementtype = 'Loss' AND m.movementdate BETWEEN p_from AND p_to),
        'stockValue', (SELECT COALESCE(-SUM(m.totalcost), 0) FROM livestockstockmovements m
                       WHERE m.farmid = p_farmid AND m.movementtype = 'Loss' AND m.reversedat IS NULL AND m.movementdate BETWEEN p_from AND p_to),
        'animals', (SELECT COALESCE(jsonb_agg(jsonb_build_object('groupId', g.groupid, 'groupName', g.name, 'speciesName', s.name,
                       'deaths', x.deaths, 'culls', x.culls, 'placed', x.placed) ORDER BY x.deaths + x.culls DESC), '[]'::jsonb)
                    FROM (SELECT m.groupid,
                                 COALESCE(-SUM(m.quantity) FILTER (WHERE m.movementtype = 'Death'), 0) AS deaths,
                                 COALESCE(-SUM(m.quantity) FILTER (WHERE m.movementtype = 'Cull'), 0) AS culls,
                                 (SELECT COALESCE(SUM(q.quantity), 0) FROM livestockheadmovements q WHERE q.groupid = m.groupid
                                  AND q.reversedat IS NULL AND q.movementtype IN ('Opening', 'Intake', 'Birth', 'TransferIn')) AS placed
                          FROM livestockheadmovements m
                          WHERE m.farmid = p_farmid AND m.reversedat IS NULL AND m.movementtype IN ('Death', 'Cull')
                            AND m.movementdate BETWEEN p_from AND p_to
                          GROUP BY m.groupid) x
                    JOIN livestockgroups g ON g.groupid = x.groupid JOIN livestockspecies s ON s.speciescode = g.speciescode));
$f$;

-- ---------------------------------------------------------------------------
-- 5. Head count
-- ---------------------------------------------------------------------------
-- The sheet: active groups (optionally of one kind or batch) with their head
-- on the count date and now.
CREATE OR REPLACE FUNCTION public.splivestockheadcount_sheet(p_farmid text, p_date date, p_speciescode text DEFAULT NULL, p_batchid integer DEFAULT NULL)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('groupId', g.groupid, 'name', g.name, 'speciesName', s.name, 'penName', p.name,
               'headOnDate', fnlivestock_groupheadasof(g.groupid, p_date), 'headNow', fnlivestock_grouphead(g.groupid),
               'tagged', (SELECT count(*) FROM livestockanimals a WHERE a.groupid = g.groupid AND a.status = 'Active' AND NOT a.isdeleted))
               ORDER BY s.sortorder, lower(g.name)), '[]'::jsonb)
    FROM livestockgroups g JOIN livestockspecies s ON s.speciescode = g.speciescode
    LEFT JOIN livestockpens p ON p.penid = g.penid
    WHERE g.farmid = p_farmid AND g.status = 'Active' AND NOT g.isdeleted AND g.startdate <= p_date
      AND (p_speciescode IS NULL OR g.speciescode = p_speciescode)
      AND (p_batchid IS NULL OR g.batchid = p_batchid);
$f$;

-- p_lines [{groupId, counted}]: each difference from the head on p_date
-- becomes a Correction dated p_date. Groups whose count matches are skipped.
CREATE OR REPLACE FUNCTION public.splivestockheadcount_post(p_farmid text, p_date date, p_lines jsonb, p_notes text, p_by text)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_l jsonb; v_gid integer; v_counted integer; v_then integer; v_out jsonb := '[]'::jsonb; v_name text;
BEGIN
    IF p_date IS NULL OR p_date > (now() at time zone 'utc')::date THEN
        RAISE EXCEPTION 'Enter the count date (today or earlier).' USING ERRCODE = 'P0001';
    END IF;
    FOR v_l IN SELECT * FROM jsonb_array_elements(COALESCE(p_lines, '[]'::jsonb)) LOOP
        v_gid := NULLIF(v_l->>'groupId', '')::int;
        CONTINUE WHEN NULLIF(v_l->>'counted', '') IS NULL;
        v_counted := (v_l->>'counted')::int;
        IF v_counted < 0 THEN
            RAISE EXCEPTION 'A count cannot be negative.' USING ERRCODE = 'P0001';
        END IF;
        SELECT name INTO v_name FROM livestockgroups WHERE groupid = v_gid AND farmid = p_farmid AND NOT isdeleted;
        IF v_name IS NULL THEN
            RAISE EXCEPTION 'A group on the sheet was not found.' USING ERRCODE = 'P0001';
        END IF;
        v_then := fnlivestock_groupheadasof(v_gid, p_date);
        CONTINUE WHEN v_counted = v_then;
        PERFORM splivestockhead_post(p_farmid, v_gid, p_date, 'Correction', v_counted - v_then, p_by,
            'Head count: counted ' || v_counted || ', records said ' || v_then || COALESCE(' · ' || NULLIF(btrim(p_notes), ''), ''));
        v_out := v_out || jsonb_build_object('groupId', v_gid, 'name', v_name, 'before', v_then, 'counted', v_counted,
                                             'change', v_counted - v_then, 'headNow', fnlivestock_grouphead(v_gid));
    END LOOP;
    IF jsonb_array_length(v_out) = 0 THEN
        RAISE EXCEPTION 'Every count matches the records, so nothing needs correcting.' USING ERRCODE = 'P0001';
    END IF;
    RETURN v_out;
END
$f$;

-- ---------------------------------------------------------------------------
-- 6. Animal stock report
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.splivestock_animalstock(p_farmid text, p_from date, p_to date, p_speciescode text DEFAULT NULL)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'groupId', g.groupid, 'groupName', g.name, 'speciesCode', g.speciescode, 'speciesName', s.name, 'status', g.status,
        'opening', fnlivestock_groupheadasof(g.groupid, p_from - 1),
        'cameIn', x.cameIn, 'born', x.born, 'movedIn', x.movedIn, 'movedOut', x.movedOut,
        'died', x.died, 'culled', x.culled, 'sold', x.sold, 'corrections', x.corr,
        'closing', fnlivestock_groupheadasof(g.groupid, p_to))
        ORDER BY s.sortorder, lower(g.name)), '[]'::jsonb)
    FROM livestockgroups g JOIN livestockspecies s ON s.speciescode = g.speciescode
    CROSS JOIN LATERAL (
        SELECT COALESCE(SUM(m.quantity) FILTER (WHERE m.movementtype IN ('Opening', 'Intake')), 0) AS cameIn,
               COALESCE(SUM(m.quantity) FILTER (WHERE m.movementtype = 'Birth'), 0) AS born,
               COALESCE(SUM(m.quantity) FILTER (WHERE m.movementtype = 'TransferIn'), 0) AS movedIn,
               COALESCE(-SUM(m.quantity) FILTER (WHERE m.movementtype = 'TransferOut'), 0) AS movedOut,
               COALESCE(-SUM(m.quantity) FILTER (WHERE m.movementtype = 'Death'), 0) AS died,
               COALESCE(-SUM(m.quantity) FILTER (WHERE m.movementtype = 'Cull'), 0) AS culled,
               COALESCE(-SUM(m.quantity) FILTER (WHERE m.movementtype = 'Sale'), 0) AS sold,
               COALESCE(SUM(m.quantity) FILTER (WHERE m.movementtype = 'Correction'), 0) AS corr
        FROM livestockheadmovements m
        WHERE m.groupid = g.groupid AND m.reversedat IS NULL AND m.movementdate BETWEEN p_from AND p_to) x
    WHERE g.farmid = p_farmid AND NOT g.isdeleted AND (p_speciescode IS NULL OR g.speciescode = p_speciescode)
      AND g.startdate <= p_to AND (g.closeddate IS NULL OR g.closeddate >= p_from);
$f$;

-- ---------------------------------------------------------------------------
-- 7. IAM
-- ---------------------------------------------------------------------------
DO $iam$
DECLARE v integer := 0;
BEGIN
    v := v + splivestock_iammirror('cash', 'cash', 'Finance', 'Cash & Accounts',
            'Cash, bank and mobile money accounts and the money moving through them.', 81);
    v := v + splivestock_iammirror('purchases', 'purchase-receipts', 'Purchasing', 'Purchases',
            'Buying stock and animals from suppliers, and paying for them at the time.', 69);
    v := v + splivestock_iammirror('suppliers', 'suppliers', 'Purchasing', 'Suppliers', 'The suppliers list.', 70);
    v := v + splivestock_iammirror('supplier-payments', 'supplier-payments', 'Purchasing', 'Supplier Payments',
            'Paying what is owed to suppliers.', 71);
    v := v + splivestock_iammirror('supplier-balances', 'supplier-balances', 'Purchasing', 'Supplier Balances',
            'What is owed to each supplier.', 72);
    v := v + splivestock_iammirror('losses', 'loss-records', 'Feed & Stock', 'Losses',
            'Stock that was spoiled, expired, spilled or stolen; animal losses.', 52);
    v := v + splivestock_iammirror('head-count', 'bird-count', 'Animals', 'Head Count',
            'Counting the animals in the pens and correcting the records to match.', 16);
    v := v + splivestock_iammirror('animal-stock', 'stock', 'Animals', 'Animal Stock',
            'Animals in, born, out and on hand over a period.', 17);
    RAISE NOTICE '461: % livestock permission key(s) added.', v;
END
$iam$;

COMMIT;

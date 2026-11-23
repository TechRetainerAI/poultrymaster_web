-- 463: Livestock money -- transfers, reconciliation, staff and payroll, staff
--      advances, owner money, outside loans, assets, profit & loss, cash flow.
--
-- Needs 458-462. Everything that moves money posts to the one cash ledger
-- (livestockcashtransactions, 461) with a category and a sourcetype, and is
-- reversed, never deleted.
--
-- 1. Transfers between accounts (a bank fee becomes a paid Fees expense).
-- 2. Reconciliation: counted against the books on a date; a difference is a
--    'CashDifference' transaction dated that day.
-- 3. Staff (livestockstaff) and pay runs: gross pay, other deductions and
--    advance repayments per person; the net leaves one account. Gross pay is
--    the Labour cost in profit & loss.
-- 4. Staff advances and loans: money lent to staff, repaid in cash or from pay.
-- 5. Owner money: money the owner puts in or takes out. Not income, not cost.
-- 6. Outside loans: money borrowed; repayments split into principal and
--    interest (interest is a cost).
-- 7. Assets: buildings, equipment, vehicles. Straight-line depreciation is
--    worked out when asked (no monthly posting to forget); selling one gives a
--    gain or loss against its book value.
-- 8. Profit & loss, for the farm or one group, for any period:
--      income  : sales (animals, produce, other stock)
--      costs   : stock sold (its cost), animals bought (counted when they
--                join a group), feed used, medicine used, other stock used,
--                stock lost, expenses by kind (paid and on credit), staff pay,
--                loan interest, depreciation, cash differences, asset gains/losses
--    Feed mixed from ingredients is counted when the FEED is used, not when
--    the ingredients go into the mixer, so nothing is counted twice.
--    Produce sales cannot be traced to one group, so a group's statement shows
--    its animal sales and every cost tagged to it; the farm statement has all.
-- 9. Cash flow: opening money, money in and out by kind, closing money.
-- 10. IAM mirrors.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Transfers
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockcashtransfers (
    transferid    serial PRIMARY KEY,
    farmid        text NOT NULL,
    transferdate  date NOT NULL,
    fromaccountid integer NOT NULL REFERENCES livestockcashaccounts(accountid),
    toaccountid   integer NOT NULL REFERENCES livestockcashaccounts(accountid),
    amount        numeric(14,2) NOT NULL CHECK (amount > 0),
    fee           numeric(14,2) NOT NULL DEFAULT 0 CHECK (fee >= 0),
    feeexpenseid  integer,
    notes         text,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text,
    CHECK (fromaccountid <> toaccountid)
);

CREATE OR REPLACE FUNCTION public.splivestocktransfer_post(p_farmid text, p_t jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_from integer := NULLIF(p_t->>'fromAccountId', '')::int;
    v_to   integer := NULLIF(p_t->>'toAccountId', '')::int;
    v_amt  numeric := NULLIF(p_t->>'amount', '')::numeric;
    v_fee  numeric := COALESCE(NULLIF(p_t->>'fee', '')::numeric, 0);
    v_date date    := NULLIF(p_t->>'date', '')::date;
    v_id   integer;
    v_fn   text; v_tn text;
BEGIN
    IF v_from IS NULL OR v_to IS NULL OR v_from = v_to THEN
        RAISE EXCEPTION 'Choose two different accounts.' USING ERRCODE = 'P0001';
    END IF;
    IF v_amt IS NULL OR v_amt <= 0 THEN
        RAISE EXCEPTION 'Enter the amount moved.' USING ERRCODE = 'P0001';
    END IF;
    IF v_fee < 0 THEN
        RAISE EXCEPTION 'The fee cannot be negative.' USING ERRCODE = 'P0001';
    END IF;
    SELECT name INTO v_fn FROM livestockcashaccounts WHERE accountid = v_from AND farmid = p_farmid;
    SELECT name INTO v_tn FROM livestockcashaccounts WHERE accountid = v_to AND farmid = p_farmid;
    IF v_fn IS NULL OR v_tn IS NULL THEN
        RAISE EXCEPTION 'That account was not found.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO livestockcashtransfers (farmid, transferdate, fromaccountid, toaccountid, amount, fee, notes, createdby)
    VALUES (p_farmid, v_date, v_from, v_to, v_amt, v_fee, NULLIF(btrim(p_t->>'notes'), ''), p_by)
    RETURNING transferid INTO v_id;
    PERFORM splivestockcash_post(p_farmid, v_from, v_date, -v_amt, 'Transfer', 'Moved to ' || v_tn, p_by, 'Transfer', v_id);
    PERFORM splivestockcash_post(p_farmid, v_to, v_date, v_amt, 'Transfer', 'Moved from ' || v_fn, p_by, 'Transfer', v_id);
    IF v_fee > 0 THEN
        UPDATE livestockcashtransfers SET feeexpenseid = splivestockexpense_post(p_farmid, jsonb_build_object(
            'date', v_date, 'category', 'Fees', 'description', 'Transfer fee: ' || v_fn || ' to ' || v_tn,
            'amount', v_fee, 'accountId', v_from), p_by)
        WHERE transferid = v_id;
    END IF;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestocktransfer_reverse(p_farmid text, p_id integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_t livestockcashtransfers%ROWTYPE;
BEGIN
    SELECT * INTO v_t FROM livestockcashtransfers WHERE transferid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND OR v_t.reversedat IS NOT NULL THEN
        RAISE EXCEPTION 'That transfer was not found or is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    -- Taking the money back out of the receiving account must not overdraw it.
    IF fnlivestock_cashbalance(v_t.toaccountid) < v_t.amount
       AND NOT (SELECT allownegative FROM livestockcashaccounts WHERE accountid = v_t.toaccountid) THEN
        RAISE EXCEPTION 'The receiving account no longer holds this money.' USING ERRCODE = 'LV004';
    END IF;
    UPDATE livestockcashtransfers SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
    WHERE transferid = p_id;
    PERFORM fnlivestock_reversecash('Transfer', p_id, p_by, btrim(p_reason));
    IF v_t.feeexpenseid IS NOT NULL THEN
        PERFORM splivestockexpense_reverse(p_farmid, v_t.feeexpenseid, btrim(p_reason), p_by);
    END IF;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestocktransfer_list(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'transferId', t.transferid, 'date', t.transferdate, 'fromAccountId', t.fromaccountid, 'fromName', fa.name,
        'toAccountId', t.toaccountid, 'toName', ta.name, 'amount', t.amount, 'fee', t.fee, 'notes', t.notes,
        'createdBy', t.createdby, 'reversedAt', t.reversedat, 'reverseReason', t.reversereason)
        ORDER BY t.transferdate DESC, t.transferid DESC), '[]'::jsonb)
    FROM livestockcashtransfers t
    JOIN livestockcashaccounts fa ON fa.accountid = t.fromaccountid
    JOIN livestockcashaccounts ta ON ta.accountid = t.toaccountid
    WHERE t.farmid = p_farmid;
$f$;

-- ---------------------------------------------------------------------------
-- 2. Reconciliation
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockcashreconciliations (
    reconid     serial PRIMARY KEY,
    farmid      text NOT NULL,
    accountid   integer NOT NULL REFERENCES livestockcashaccounts(accountid),
    recondate   date NOT NULL,
    booked      numeric(14,2) NOT NULL,
    counted     numeric(14,2) NOT NULL,
    difference  numeric(14,2) NOT NULL,
    notes       text,
    createdat   timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby   text
);

CREATE OR REPLACE FUNCTION public.fnlivestock_cashbalanceasof(p_accountid integer, p_date date)
 RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT a.openingbalance + COALESCE((SELECT SUM(t.amount) FROM livestockcashtransactions t
                                        WHERE t.accountid = a.accountid AND t.reversedat IS NULL AND t.txdate <= p_date), 0)
    FROM livestockcashaccounts a WHERE a.accountid = p_accountid;
$f$;

CREATE OR REPLACE FUNCTION public.splivestockreconcile_post(p_farmid text, p_accountid integer, p_date date, p_counted numeric,
    p_notes text, p_by text)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_book numeric; v_diff numeric; v_id integer; v_a livestockcashaccounts%ROWTYPE;
BEGIN
    SELECT * INTO v_a FROM livestockcashaccounts WHERE accountid = p_accountid AND farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That account was not found.' USING ERRCODE = 'P0001';
    END IF;
    IF p_counted IS NULL THEN
        RAISE EXCEPTION 'Enter what you counted.' USING ERRCODE = 'P0001';
    END IF;
    IF p_date IS NULL OR p_date > (now() at time zone 'utc')::date OR p_date < v_a.openingdate THEN
        RAISE EXCEPTION 'Enter a date between the account''s opening and today.' USING ERRCODE = 'P0001';
    END IF;
    v_book := fnlivestock_cashbalanceasof(p_accountid, p_date);
    v_diff := round(p_counted - v_book, 2);
    IF v_diff <> 0 AND NULLIF(btrim(p_notes), '') IS NULL THEN
        RAISE EXCEPTION 'The count is % % than the books. Say what you know about the difference.',
            to_char(abs(v_diff), 'FM999,999,999,990.00'), CASE WHEN v_diff < 0 THEN 'less' ELSE 'more' END USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO livestockcashreconciliations (farmid, accountid, recondate, booked, counted, difference, notes, createdby)
    VALUES (p_farmid, p_accountid, p_date, v_book, p_counted, v_diff, NULLIF(btrim(p_notes), ''), p_by)
    RETURNING reconid INTO v_id;
    IF v_diff <> 0 THEN
        -- A shortage may take the account below zero: it is what is there.
        INSERT INTO livestockcashtransactions (farmid, accountid, txdate, amount, category, description, sourcetype, sourceid, createdby)
        VALUES (p_farmid, p_accountid, p_date, v_diff, 'CashDifference',
                CASE WHEN v_diff < 0 THEN 'Short at count' ELSE 'Over at count' END || ': ' || btrim(p_notes), 'Reconciliation', v_id, p_by);
    END IF;
    RETURN jsonb_build_object('reconId', v_id, 'booked', v_book, 'counted', p_counted, 'difference', v_diff,
                              'balance', fnlivestock_cashbalance(p_accountid));
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockreconcile_list(p_farmid text, p_accountid integer DEFAULT NULL)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('reconId', r.reconid, 'accountId', r.accountid, 'accountName', a.name,
        'date', r.recondate, 'booked', r.booked, 'counted', r.counted, 'difference', r.difference, 'notes', r.notes,
        'createdBy', r.createdby) ORDER BY r.recondate DESC, r.reconid DESC), '[]'::jsonb)
    FROM livestockcashreconciliations r JOIN livestockcashaccounts a ON a.accountid = r.accountid
    WHERE r.farmid = p_farmid AND (p_accountid IS NULL OR r.accountid = p_accountid);
$f$;

-- ---------------------------------------------------------------------------
-- 3. Staff and payroll
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockstaff (
    staffid    serial PRIMARY KEY,
    farmid     text NOT NULL,
    name       text NOT NULL,
    role       text,
    phone      text,
    paytype    text NOT NULL DEFAULT 'Monthly' CHECK (paytype IN ('Monthly', 'Daily')),
    payrate    numeric(14,2) NOT NULL DEFAULT 0 CHECK (payrate >= 0),
    startdate  date,
    isactive   boolean NOT NULL DEFAULT TRUE,
    notes      text,
    createdat  timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby  text
);

CREATE TABLE IF NOT EXISTS livestockstaffloans (
    loanid        serial PRIMARY KEY,
    farmid        text NOT NULL,
    staffid       integer NOT NULL REFERENCES livestockstaff(staffid),
    loandate      date NOT NULL,
    amount        numeric(14,2) NOT NULL CHECK (amount > 0),
    accountid     integer NOT NULL REFERENCES livestockcashaccounts(accountid),
    reason        text,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text
);
CREATE TABLE IF NOT EXISTS livestockstaffloanrepayments (
    repaymentid   serial PRIMARY KEY,
    farmid        text NOT NULL,
    staffid       integer NOT NULL REFERENCES livestockstaff(staffid),
    repaydate     date NOT NULL,
    amount        numeric(14,2) NOT NULL CHECK (amount > 0),
    accountid     integer REFERENCES livestockcashaccounts(accountid),   -- NULL when taken from pay
    sourcetype    text,          -- 'PayRun' when deducted from pay
    sourceid      integer,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text
);

CREATE OR REPLACE FUNCTION public.fnlivestock_staffowes(p_staffid integer)
 RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT COALESCE((SELECT SUM(amount) FROM livestockstaffloans WHERE staffid = p_staffid AND reversedat IS NULL), 0)
         - COALESCE((SELECT SUM(amount) FROM livestockstaffloanrepayments WHERE staffid = p_staffid AND reversedat IS NULL), 0);
$f$;

CREATE TABLE IF NOT EXISTS livestockpayruns (
    runid         serial PRIMARY KEY,
    farmid        text NOT NULL,
    periodstart   date NOT NULL,
    periodend     date NOT NULL,
    paydate       date NOT NULL,
    accountid     integer NOT NULL REFERENCES livestockcashaccounts(accountid),
    notes         text,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text,
    CHECK (periodend >= periodstart)
);
CREATE TABLE IF NOT EXISTS livestockpaylines (
    lineid        serial PRIMARY KEY,
    runid         integer NOT NULL REFERENCES livestockpayruns(runid),
    staffid       integer NOT NULL REFERENCES livestockstaff(staffid),
    days          numeric(6,2),
    gross         numeric(14,2) NOT NULL CHECK (gross >= 0),
    deductions    numeric(14,2) NOT NULL DEFAULT 0 CHECK (deductions >= 0),
    loanrepayment numeric(14,2) NOT NULL DEFAULT 0 CHECK (loanrepayment >= 0),
    net           numeric(14,2) NOT NULL CHECK (net >= 0),
    notes         text
);

CREATE OR REPLACE FUNCTION public.splivestockstaff_list(p_farmid text, p_includeinactive boolean DEFAULT FALSE)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('staffId', s.staffid, 'name', s.name, 'role', s.role, 'phone', s.phone,
        'payType', s.paytype, 'payRate', s.payrate, 'startDate', s.startdate, 'isActive', s.isactive, 'notes', s.notes,
        'owes', fnlivestock_staffowes(s.staffid),
        'lastPaid', (SELECT max(r.paydate) FROM livestockpaylines l JOIN livestockpayruns r ON r.runid = l.runid
                     WHERE l.staffid = s.staffid AND r.reversedat IS NULL)) ORDER BY s.isactive DESC, lower(s.name)), '[]'::jsonb)
    FROM livestockstaff s WHERE s.farmid = p_farmid AND (p_includeinactive OR s.isactive);
$f$;

CREATE OR REPLACE FUNCTION public.splivestockstaff_save(p_farmid text, p_s jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_id integer := NULLIF(p_s->>'staffId', '')::int; v_name text := btrim(COALESCE(p_s->>'name', ''));
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Enter the name.' USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(p_s->>'payType', 'Monthly') NOT IN ('Monthly', 'Daily') THEN
        RAISE EXCEPTION 'Pay is monthly or daily.' USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(NULLIF(p_s->>'payRate', '')::numeric, 0) < 0 THEN
        RAISE EXCEPTION 'Pay cannot be negative.' USING ERRCODE = 'P0001';
    END IF;
    IF v_id IS NULL THEN
        INSERT INTO livestockstaff (farmid, name, role, phone, paytype, payrate, startdate, notes, createdby)
        VALUES (p_farmid, v_name, NULLIF(btrim(p_s->>'role'), ''), NULLIF(btrim(p_s->>'phone'), ''), COALESCE(p_s->>'payType', 'Monthly'),
                COALESCE(NULLIF(p_s->>'payRate', '')::numeric, 0), NULLIF(p_s->>'startDate', '')::date, NULLIF(btrim(p_s->>'notes'), ''), p_by)
        RETURNING staffid INTO v_id;
    ELSE
        UPDATE livestockstaff SET name = v_name, role = NULLIF(btrim(p_s->>'role'), ''), phone = NULLIF(btrim(p_s->>'phone'), ''),
            paytype = COALESCE(p_s->>'payType', 'Monthly'), payrate = COALESCE(NULLIF(p_s->>'payRate', '')::numeric, 0),
            startdate = NULLIF(p_s->>'startDate', '')::date, isactive = COALESCE((p_s->>'isActive')::boolean, isactive),
            notes = NULLIF(btrim(p_s->>'notes'), '')
        WHERE staffid = v_id AND farmid = p_farmid;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That person was not found.' USING ERRCODE = 'P0001';
        END IF;
    END IF;
    RETURN v_id;
END
$f$;

-- {periodStart, periodEnd, payDate, accountId, notes,
--  lines: [{staffId, days, gross, deductions, loanRepayment, notes}]}
CREATE OR REPLACE FUNCTION public.splivestockpayrun_post(p_farmid text, p_r jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id   integer;
    v_l    jsonb;
    v_s    livestockstaff%ROWTYPE;
    v_g    numeric; v_d numeric; v_lr numeric; v_net numeric;
    v_tot  numeric := 0;
    v_pay  date := NULLIF(p_r->>'payDate', '')::date;
BEGIN
    IF NULLIF(p_r->>'periodStart', '') IS NULL OR NULLIF(p_r->>'periodEnd', '') IS NULL
       OR (p_r->>'periodEnd')::date < (p_r->>'periodStart')::date THEN
        RAISE EXCEPTION 'Enter the period the pay is for.' USING ERRCODE = 'P0001';
    END IF;
    IF jsonb_array_length(COALESCE(p_r->'lines', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'Add the people being paid.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO livestockpayruns (farmid, periodstart, periodend, paydate, accountid, notes, createdby)
    VALUES (p_farmid, (p_r->>'periodStart')::date, (p_r->>'periodEnd')::date, v_pay, NULLIF(p_r->>'accountId', '')::int,
            NULLIF(btrim(p_r->>'notes'), ''), p_by)
    RETURNING runid INTO v_id;
    FOR v_l IN SELECT * FROM jsonb_array_elements(p_r->'lines') LOOP
        SELECT * INTO v_s FROM livestockstaff WHERE staffid = NULLIF(v_l->>'staffId', '')::int AND farmid = p_farmid;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'A person on the pay run was not found.' USING ERRCODE = 'P0001';
        END IF;
        IF EXISTS (SELECT 1 FROM livestockpaylines l JOIN livestockpayruns r ON r.runid = l.runid
                   WHERE l.staffid = v_s.staffid AND r.reversedat IS NULL AND r.runid <> v_id
                     AND r.periodstart <= (p_r->>'periodEnd')::date AND r.periodend >= (p_r->>'periodStart')::date) THEN
            RAISE EXCEPTION '% has already been paid for part of this period.', v_s.name USING ERRCODE = 'P0001';
        END IF;
        v_g  := COALESCE(NULLIF(v_l->>'gross', '')::numeric, 0);
        v_d  := COALESCE(NULLIF(v_l->>'deductions', '')::numeric, 0);
        v_lr := COALESCE(NULLIF(v_l->>'loanRepayment', '')::numeric, 0);
        IF v_g < 0 OR v_d < 0 OR v_lr < 0 THEN
            RAISE EXCEPTION 'Pay amounts cannot be negative (%).', v_s.name USING ERRCODE = 'P0001';
        END IF;
        IF v_lr > fnlivestock_staffowes(v_s.staffid) THEN
            RAISE EXCEPTION '% owes only %, so no more than that can be taken from pay.', v_s.name,
                to_char(fnlivestock_staffowes(v_s.staffid), 'FM999,999,990.00') USING ERRCODE = 'P0001';
        END IF;
        v_net := v_g - v_d - v_lr;
        IF v_net < 0 THEN
            RAISE EXCEPTION 'Deductions for % are more than the pay.', v_s.name USING ERRCODE = 'P0001';
        END IF;
        INSERT INTO livestockpaylines (runid, staffid, days, gross, deductions, loanrepayment, net, notes)
        VALUES (v_id, v_s.staffid, NULLIF(v_l->>'days', '')::numeric, v_g, v_d, v_lr, v_net, NULLIF(btrim(v_l->>'notes'), ''));
        IF v_lr > 0 THEN
            INSERT INTO livestockstaffloanrepayments (farmid, staffid, repaydate, amount, sourcetype, sourceid, createdby)
            VALUES (p_farmid, v_s.staffid, v_pay, v_lr, 'PayRun', v_id, p_by);
        END IF;
        v_tot := v_tot + v_net;
    END LOOP;
    IF v_tot > 0 THEN
        PERFORM splivestockcash_post(p_farmid, NULLIF(p_r->>'accountId', '')::int, v_pay, -v_tot, 'Payroll',
            'Pay ' || to_char((p_r->>'periodStart')::date, 'DD Mon') || ' – ' || to_char((p_r->>'periodEnd')::date, 'DD Mon YYYY'),
            p_by, 'PayRun', v_id);
    END IF;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockpayrun_reverse(p_farmid text, p_id integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockpayruns SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
    WHERE runid = p_id AND farmid = p_farmid AND reversedat IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That pay run was not found or is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM fnlivestock_reversecash('PayRun', p_id, p_by, btrim(p_reason));
    UPDATE livestockstaffloanrepayments SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
    WHERE sourcetype = 'PayRun' AND sourceid = p_id AND reversedat IS NULL;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockpayrun_list(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'runId', r.runid, 'periodStart', r.periodstart, 'periodEnd', r.periodend, 'payDate', r.paydate,
        'accountId', r.accountid, 'accountName', a.name, 'notes', r.notes, 'createdBy', r.createdby,
        'reversedAt', r.reversedat, 'reverseReason', r.reversereason,
        'gross', (SELECT COALESCE(SUM(gross), 0) FROM livestockpaylines WHERE runid = r.runid),
        'net', (SELECT COALESCE(SUM(net), 0) FROM livestockpaylines WHERE runid = r.runid),
        'lines', (SELECT COALESCE(jsonb_agg(jsonb_build_object('staffId', l.staffid, 'name', s.name, 'days', l.days, 'gross', l.gross,
                     'deductions', l.deductions, 'loanRepayment', l.loanrepayment, 'net', l.net, 'notes', l.notes) ORDER BY s.name), '[]'::jsonb)
                  FROM livestockpaylines l JOIN livestockstaff s ON s.staffid = l.staffid WHERE l.runid = r.runid))
        ORDER BY r.paydate DESC, r.runid DESC), '[]'::jsonb)
    FROM livestockpayruns r JOIN livestockcashaccounts a ON a.accountid = r.accountid
    WHERE r.farmid = p_farmid;
$f$;

-- ---------------------------------------------------------------------------
-- 4. Staff advances / loans
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.splivestockstaffloan_post(p_farmid text, p_l jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_id integer; v_s livestockstaff%ROWTYPE; v_amt numeric := NULLIF(p_l->>'amount', '')::numeric;
BEGIN
    SELECT * INTO v_s FROM livestockstaff WHERE staffid = NULLIF(p_l->>'staffId', '')::int AND farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Choose the person.' USING ERRCODE = 'P0001';
    END IF;
    IF v_amt IS NULL OR v_amt <= 0 THEN
        RAISE EXCEPTION 'Enter the amount given.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO livestockstaffloans (farmid, staffid, loandate, amount, accountid, reason, createdby)
    VALUES (p_farmid, v_s.staffid, NULLIF(p_l->>'date', '')::date, v_amt, NULLIF(p_l->>'accountId', '')::int, NULLIF(btrim(p_l->>'reason'), ''), p_by)
    RETURNING loanid INTO v_id;
    PERFORM splivestockcash_post(p_farmid, NULLIF(p_l->>'accountId', '')::int, NULLIF(p_l->>'date', '')::date, -v_amt, 'StaffLoan',
        'Advance to ' || v_s.name, p_by, 'StaffLoan', v_id);
    RETURN v_id;
END
$f$;

-- Repaid in cash (into an account). Pay-run deductions are made on the pay run.
CREATE OR REPLACE FUNCTION public.splivestockstaffloan_repay(p_farmid text, p_r jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_id integer; v_s livestockstaff%ROWTYPE; v_amt numeric := NULLIF(p_r->>'amount', '')::numeric;
BEGIN
    SELECT * INTO v_s FROM livestockstaff WHERE staffid = NULLIF(p_r->>'staffId', '')::int AND farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Choose the person.' USING ERRCODE = 'P0001';
    END IF;
    IF v_amt IS NULL OR v_amt <= 0 THEN
        RAISE EXCEPTION 'Enter the amount repaid.' USING ERRCODE = 'P0001';
    END IF;
    IF v_amt > fnlivestock_staffowes(v_s.staffid) THEN
        RAISE EXCEPTION '% owes only %.', v_s.name, to_char(fnlivestock_staffowes(v_s.staffid), 'FM999,999,990.00') USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO livestockstaffloanrepayments (farmid, staffid, repaydate, amount, accountid, sourcetype, createdby)
    VALUES (p_farmid, v_s.staffid, NULLIF(p_r->>'date', '')::date, v_amt, NULLIF(p_r->>'accountId', '')::int, 'Cash', p_by)
    RETURNING repaymentid INTO v_id;
    UPDATE livestockstaffloanrepayments SET sourceid = v_id WHERE repaymentid = v_id;
    PERFORM splivestockcash_post(p_farmid, NULLIF(p_r->>'accountId', '')::int, NULLIF(p_r->>'date', '')::date, v_amt, 'StaffLoanRepayment',
        'Repaid by ' || v_s.name, p_by, 'StaffLoanRepayment', v_id);
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockstaffloan_reverse(p_farmid text, p_kind text, p_id integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_staff integer; v_amt numeric;
BEGIN
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF p_kind = 'Loan' THEN
        SELECT staffid, amount INTO v_staff, v_amt FROM livestockstaffloans WHERE loanid = p_id AND farmid = p_farmid AND reversedat IS NULL;
        IF v_staff IS NULL THEN
            RAISE EXCEPTION 'That advance was not found or is already reversed.' USING ERRCODE = 'P0001';
        END IF;
        IF fnlivestock_staffowes(v_staff) - v_amt < 0 THEN
            RAISE EXCEPTION 'Part of this advance has been repaid. Reverse those repayments first.' USING ERRCODE = 'P0001';
        END IF;
        UPDATE livestockstaffloans SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason) WHERE loanid = p_id;
        PERFORM fnlivestock_reversecash('StaffLoan', p_id, p_by, btrim(p_reason));
    ELSIF p_kind = 'Repayment' THEN
        UPDATE livestockstaffloanrepayments SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
        WHERE repaymentid = p_id AND farmid = p_farmid AND reversedat IS NULL AND sourcetype = 'Cash';
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That repayment was not found, is already reversed, or was taken from pay (reverse the pay run).' USING ERRCODE = 'P0001';
        END IF;
        PERFORM fnlivestock_reversecash('StaffLoanRepayment', p_id, p_by, btrim(p_reason));
    ELSE
        RAISE EXCEPTION 'Unknown kind.' USING ERRCODE = 'P0001';
    END IF;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockstaffloan_list(p_farmid text, p_staffid integer DEFAULT NULL)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.d DESC, x.id DESC), '[]'::jsonb) FROM (
        SELECT l.loandate AS d, l.loanid AS id, jsonb_build_object('kind', 'Loan', 'id', l.loanid, 'staffId', l.staffid, 'name', s.name,
            'date', l.loandate, 'amount', l.amount, 'accountName', a.name, 'note', l.reason, 'reversedAt', l.reversedat) AS j
        FROM livestockstaffloans l JOIN livestockstaff s ON s.staffid = l.staffid JOIN livestockcashaccounts a ON a.accountid = l.accountid
        WHERE l.farmid = p_farmid AND (p_staffid IS NULL OR l.staffid = p_staffid)
        UNION ALL
        SELECT r.repaydate, r.repaymentid, jsonb_build_object('kind', 'Repayment', 'id', r.repaymentid, 'staffId', r.staffid, 'name', s.name,
            'date', r.repaydate, 'amount', r.amount, 'accountName', a.name,
            'note', CASE WHEN r.sourcetype = 'PayRun' THEN 'Taken from pay' ELSE 'Repaid in cash' END,
            'fromPay', r.sourcetype = 'PayRun', 'reversedAt', r.reversedat)
        FROM livestockstaffloanrepayments r JOIN livestockstaff s ON s.staffid = r.staffid LEFT JOIN livestockcashaccounts a ON a.accountid = r.accountid
        WHERE r.farmid = p_farmid AND (p_staffid IS NULL OR r.staffid = p_staffid)) x;
$f$;

-- ---------------------------------------------------------------------------
-- 5. Owner money
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockownermoney (
    entryid       serial PRIMARY KEY,
    farmid        text NOT NULL,
    entrydate     date NOT NULL,
    direction     text NOT NULL CHECK (direction IN ('In', 'Out')),
    amount        numeric(14,2) NOT NULL CHECK (amount > 0),
    accountid     integer NOT NULL REFERENCES livestockcashaccounts(accountid),
    notes         text,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text
);

CREATE OR REPLACE FUNCTION public.splivestockowner_post(p_farmid text, p_o jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_id integer; v_dir text := p_o->>'direction'; v_amt numeric := NULLIF(p_o->>'amount', '')::numeric;
BEGIN
    IF COALESCE(v_dir, '') NOT IN ('In', 'Out') THEN
        RAISE EXCEPTION 'Say whether the owner put money in or took it out.' USING ERRCODE = 'P0001';
    END IF;
    IF v_amt IS NULL OR v_amt <= 0 THEN
        RAISE EXCEPTION 'Enter the amount.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO livestockownermoney (farmid, entrydate, direction, amount, accountid, notes, createdby)
    VALUES (p_farmid, NULLIF(p_o->>'date', '')::date, v_dir, v_amt, NULLIF(p_o->>'accountId', '')::int, NULLIF(btrim(p_o->>'notes'), ''), p_by)
    RETURNING entryid INTO v_id;
    PERFORM splivestockcash_post(p_farmid, NULLIF(p_o->>'accountId', '')::int, NULLIF(p_o->>'date', '')::date,
        CASE WHEN v_dir = 'In' THEN v_amt ELSE -v_amt END, CASE WHEN v_dir = 'In' THEN 'OwnerIn' ELSE 'OwnerOut' END,
        CASE WHEN v_dir = 'In' THEN 'Owner put in' ELSE 'Owner took out' END || COALESCE(': ' || NULLIF(btrim(p_o->>'notes'), ''), ''),
        p_by, 'OwnerMoney', v_id);
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockowner_reverse(p_farmid text, p_id integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockownermoney SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
    WHERE entryid = p_id AND farmid = p_farmid AND reversedat IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That entry was not found or is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM fnlivestock_reversecash('OwnerMoney', p_id, p_by, btrim(p_reason));
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockowner_list(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'putIn', (SELECT COALESCE(SUM(amount), 0) FROM livestockownermoney WHERE farmid = p_farmid AND direction = 'In' AND reversedat IS NULL),
        'tookOut', (SELECT COALESCE(SUM(amount), 0) FROM livestockownermoney WHERE farmid = p_farmid AND direction = 'Out' AND reversedat IS NULL),
        'entries', (SELECT COALESCE(jsonb_agg(jsonb_build_object('entryId', o.entryid, 'date', o.entrydate, 'direction', o.direction,
                      'amount', o.amount, 'accountName', a.name, 'notes', o.notes, 'createdBy', o.createdby,
                      'reversedAt', o.reversedat, 'reverseReason', o.reversereason) ORDER BY o.entrydate DESC, o.entryid DESC), '[]'::jsonb)
                    FROM livestockownermoney o JOIN livestockcashaccounts a ON a.accountid = o.accountid WHERE o.farmid = p_farmid));
$f$;

-- ---------------------------------------------------------------------------
-- 6. Outside loans
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockloans (
    loanid        serial PRIMARY KEY,
    farmid        text NOT NULL,
    lender        text NOT NULL,
    receiveddate  date NOT NULL,
    amount        numeric(14,2) NOT NULL CHECK (amount > 0),
    accountid     integer NOT NULL REFERENCES livestockcashaccounts(accountid),
    interestnote  text,             -- "3% a month", agreed terms
    duedate       date,
    notes         text,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text
);
CREATE TABLE IF NOT EXISTS livestockloanrepayments (
    repaymentid   serial PRIMARY KEY,
    loanid        integer NOT NULL REFERENCES livestockloans(loanid),
    repaydate     date NOT NULL,
    principal     numeric(14,2) NOT NULL DEFAULT 0 CHECK (principal >= 0),
    interest      numeric(14,2) NOT NULL DEFAULT 0 CHECK (interest >= 0),
    accountid     integer NOT NULL REFERENCES livestockcashaccounts(accountid),
    notes         text,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby     text,
    reversedat    timestamp,
    reversedby    text,
    reversereason text,
    CHECK (principal + interest > 0)
);

CREATE OR REPLACE FUNCTION public.fnlivestock_loanbalance(p_loanid integer)
 RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT l.amount - COALESCE((SELECT SUM(principal) FROM livestockloanrepayments r WHERE r.loanid = l.loanid AND r.reversedat IS NULL), 0)
    FROM livestockloans l WHERE l.loanid = p_loanid;
$f$;

CREATE OR REPLACE FUNCTION public.splivestockloan_post(p_farmid text, p_l jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_id integer; v_amt numeric := NULLIF(p_l->>'amount', '')::numeric;
BEGIN
    IF btrim(COALESCE(p_l->>'lender', '')) = '' THEN
        RAISE EXCEPTION 'Enter who lent the money.' USING ERRCODE = 'P0001';
    END IF;
    IF v_amt IS NULL OR v_amt <= 0 THEN
        RAISE EXCEPTION 'Enter the amount borrowed.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO livestockloans (farmid, lender, receiveddate, amount, accountid, interestnote, duedate, notes, createdby)
    VALUES (p_farmid, btrim(p_l->>'lender'), NULLIF(p_l->>'date', '')::date, v_amt, NULLIF(p_l->>'accountId', '')::int,
            NULLIF(btrim(p_l->>'interestNote'), ''), NULLIF(p_l->>'dueDate', '')::date, NULLIF(btrim(p_l->>'notes'), ''), p_by)
    RETURNING loanid INTO v_id;
    PERFORM splivestockcash_post(p_farmid, NULLIF(p_l->>'accountId', '')::int, NULLIF(p_l->>'date', '')::date, v_amt, 'LoanIn',
        'Loan from ' || btrim(p_l->>'lender'), p_by, 'Loan', v_id);
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockloan_repay(p_farmid text, p_r jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_id integer; v_l livestockloans%ROWTYPE; v_p numeric := COALESCE(NULLIF(p_r->>'principal', '')::numeric, 0);
        v_i numeric := COALESCE(NULLIF(p_r->>'interest', '')::numeric, 0);
BEGIN
    SELECT * INTO v_l FROM livestockloans WHERE loanid = NULLIF(p_r->>'loanId', '')::int AND farmid = p_farmid AND reversedat IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That loan was not found.' USING ERRCODE = 'P0001';
    END IF;
    IF v_p < 0 OR v_i < 0 OR v_p + v_i = 0 THEN
        RAISE EXCEPTION 'Enter what was repaid (loan and interest).' USING ERRCODE = 'P0001';
    END IF;
    IF v_p > fnlivestock_loanbalance(v_l.loanid) THEN
        RAISE EXCEPTION 'Only % of the loan is left to repay.', to_char(fnlivestock_loanbalance(v_l.loanid), 'FM999,999,999,990.00') USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO livestockloanrepayments (loanid, repaydate, principal, interest, accountid, notes, createdby)
    VALUES (v_l.loanid, NULLIF(p_r->>'date', '')::date, v_p, v_i, NULLIF(p_r->>'accountId', '')::int, NULLIF(btrim(p_r->>'notes'), ''), p_by)
    RETURNING repaymentid INTO v_id;
    PERFORM splivestockcash_post(p_farmid, NULLIF(p_r->>'accountId', '')::int, NULLIF(p_r->>'date', '')::date, -(v_p + v_i), 'LoanRepayment',
        'Repaid ' || v_l.lender, p_by, 'LoanRepayment', v_id);
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockloan_reverse(p_farmid text, p_kind text, p_id integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF p_kind = 'Loan' THEN
        IF EXISTS (SELECT 1 FROM livestockloanrepayments WHERE loanid = p_id AND reversedat IS NULL) THEN
            RAISE EXCEPTION 'Repayments are recorded on this loan. Reverse them first.' USING ERRCODE = 'P0001';
        END IF;
        UPDATE livestockloans SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
        WHERE loanid = p_id AND farmid = p_farmid AND reversedat IS NULL;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That loan was not found or is already reversed.' USING ERRCODE = 'P0001';
        END IF;
        PERFORM fnlivestock_reversecash('Loan', p_id, p_by, btrim(p_reason));
    ELSE
        UPDATE livestockloanrepayments r SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason)
        FROM livestockloans l WHERE r.repaymentid = p_id AND l.loanid = r.loanid AND l.farmid = p_farmid AND r.reversedat IS NULL;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That repayment was not found or is already reversed.' USING ERRCODE = 'P0001';
        END IF;
        PERFORM fnlivestock_reversecash('LoanRepayment', p_id, p_by, btrim(p_reason));
    END IF;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockloan_list(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'loanId', l.loanid, 'lender', l.lender, 'date', l.receiveddate, 'amount', l.amount, 'accountName', a.name,
        'interestNote', l.interestnote, 'dueDate', l.duedate, 'notes', l.notes, 'balance', fnlivestock_loanbalance(l.loanid),
        'interestPaid', (SELECT COALESCE(SUM(interest), 0) FROM livestockloanrepayments r WHERE r.loanid = l.loanid AND r.reversedat IS NULL),
        'reversedAt', l.reversedat, 'reverseReason', l.reversereason,
        'repayments', (SELECT COALESCE(jsonb_agg(jsonb_build_object('repaymentId', r.repaymentid, 'date', r.repaydate, 'principal', r.principal,
                         'interest', r.interest, 'accountName', ra.name, 'notes', r.notes, 'reversedAt', r.reversedat) ORDER BY r.repaydate), '[]'::jsonb)
                       FROM livestockloanrepayments r JOIN livestockcashaccounts ra ON ra.accountid = r.accountid WHERE r.loanid = l.loanid))
        ORDER BY (l.reversedat IS NULL) DESC, l.receiveddate DESC), '[]'::jsonb)
    FROM livestockloans l JOIN livestockcashaccounts a ON a.accountid = l.accountid
    WHERE l.farmid = p_farmid;
$f$;

-- ---------------------------------------------------------------------------
-- 7. Assets
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS livestockassets (
    assetid          serial PRIMARY KEY,
    farmid           text NOT NULL,
    name             text NOT NULL,
    category         text NOT NULL CHECK (category IN ('Building', 'Equipment', 'Vehicle', 'Land', 'Other')),
    acquireddate     date NOT NULL,
    cost             numeric(14,2) NOT NULL CHECK (cost >= 0),
    salvagevalue     numeric(14,2) NOT NULL DEFAULT 0 CHECK (salvagevalue >= 0),
    usefulmonths     integer CHECK (usefulmonths IS NULL OR usefulmonths > 0),   -- NULL: not depreciated (land)
    accountid        integer REFERENCES livestockcashaccounts(accountid),        -- NULL: owned before recording began
    notes            text,
    disposeddate     date,
    disposalamount   numeric(14,2),
    disposalaccountid integer REFERENCES livestockcashaccounts(accountid),
    createdat        timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    createdby        text,
    reversedat       timestamp,
    reversedby       text,
    reversereason    text,
    CHECK (salvagevalue <= cost)
);

-- Depreciation between two dates (straight line by day; stops at disposal or
-- when fully written down).
CREATE OR REPLACE FUNCTION public.fnlivestock_depreciation(p_assetid integer, p_from date, p_to date)
 RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT CASE WHEN a.usefulmonths IS NULL OR a.reversedat IS NOT NULL THEN 0 ELSE
        -- Its last day of life is the day before the month count comes round.
        round(GREATEST(0, (LEAST(p_to, COALESCE(a.disposeddate, p_to), (a.acquireddate + make_interval(months => a.usefulmonths))::date - 1)
                          - GREATEST(p_from, a.acquireddate) + 1))
              * (a.cost - a.salvagevalue)
              / NULLIF(((a.acquireddate + make_interval(months => a.usefulmonths))::date - a.acquireddate), 0), 2) END
    FROM livestockassets a WHERE a.assetid = p_assetid;
$f$;

CREATE OR REPLACE FUNCTION public.fnlivestock_bookvalue(p_assetid integer, p_date date)
 RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT a.cost - fnlivestock_depreciation(a.assetid, a.acquireddate, p_date) FROM livestockassets a WHERE a.assetid = p_assetid;
$f$;

CREATE OR REPLACE FUNCTION public.splivestockasset_list(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'assetId', a.assetid, 'name', a.name, 'category', a.category, 'acquiredDate', a.acquireddate, 'cost', a.cost,
        'salvageValue', a.salvagevalue, 'usefulMonths', a.usefulmonths, 'accountName', ac.name, 'notes', a.notes,
        'bookValue', fnlivestock_bookvalue(a.assetid, COALESCE(a.disposeddate, (now() at time zone 'utc')::date)),
        'depreciationToDate', fnlivestock_depreciation(a.assetid, a.acquireddate, COALESCE(a.disposeddate, (now() at time zone 'utc')::date)),
        'monthlyDepreciation', CASE WHEN a.usefulmonths IS NULL THEN 0 ELSE round((a.cost - a.salvagevalue) / a.usefulmonths, 2) END,
        'disposedDate', a.disposeddate, 'disposalAmount', a.disposalamount,
        'gainOnDisposal', CASE WHEN a.disposeddate IS NOT NULL THEN a.disposalamount - fnlivestock_bookvalue(a.assetid, a.disposeddate) END,
        'createdBy', a.createdby, 'reversedAt', a.reversedat, 'reverseReason', a.reversereason)
        ORDER BY (a.reversedat IS NULL AND a.disposeddate IS NULL) DESC, a.acquireddate DESC), '[]'::jsonb)
    FROM livestockassets a LEFT JOIN livestockcashaccounts ac ON ac.accountid = a.accountid
    WHERE a.farmid = p_farmid;
$f$;

-- {name, category, acquiredDate, cost, salvageValue, usefulMonths, accountId (null = owned before), notes}
CREATE OR REPLACE FUNCTION public.splivestockasset_post(p_farmid text, p_a jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_id integer; v_cost numeric := NULLIF(p_a->>'cost', '')::numeric;
BEGIN
    IF btrim(COALESCE(p_a->>'name', '')) = '' THEN
        RAISE EXCEPTION 'Name the asset.' USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(p_a->>'category', '') NOT IN ('Building', 'Equipment', 'Vehicle', 'Land', 'Other') THEN
        RAISE EXCEPTION 'Choose the kind of asset.' USING ERRCODE = 'P0001';
    END IF;
    IF v_cost IS NULL OR v_cost < 0 THEN
        RAISE EXCEPTION 'Enter what it cost.' USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(NULLIF(p_a->>'salvageValue', '')::numeric, 0) > v_cost THEN
        RAISE EXCEPTION 'What it will be worth at the end cannot be more than it cost.' USING ERRCODE = 'P0001';
    END IF;
    IF p_a->>'category' <> 'Land' AND NULLIF(p_a->>'usefulMonths', '') IS NULL THEN
        RAISE EXCEPTION 'Enter how many months it will be useful for.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO livestockassets (farmid, name, category, acquireddate, cost, salvagevalue, usefulmonths, accountid, notes, createdby)
    VALUES (p_farmid, btrim(p_a->>'name'), p_a->>'category', NULLIF(p_a->>'acquiredDate', '')::date, v_cost,
            COALESCE(NULLIF(p_a->>'salvageValue', '')::numeric, 0),
            CASE WHEN p_a->>'category' = 'Land' THEN NULL ELSE NULLIF(p_a->>'usefulMonths', '')::int END,
            NULLIF(p_a->>'accountId', '')::int, NULLIF(btrim(p_a->>'notes'), ''), p_by)
    RETURNING assetid INTO v_id;
    IF NULLIF(p_a->>'accountId', '') IS NOT NULL AND v_cost > 0 THEN
        PERFORM splivestockcash_post(p_farmid, (p_a->>'accountId')::int, NULLIF(p_a->>'acquiredDate', '')::date, -v_cost, 'AssetPurchase',
            'Bought ' || btrim(p_a->>'name'), p_by, 'Asset', v_id);
    END IF;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockasset_dispose(p_farmid text, p_id integer, p_date date, p_amount numeric, p_accountid integer, p_by text)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_a livestockassets%ROWTYPE;
BEGIN
    SELECT * INTO v_a FROM livestockassets WHERE assetid = p_id AND farmid = p_farmid AND reversedat IS NULL FOR UPDATE;
    IF NOT FOUND OR v_a.disposeddate IS NOT NULL THEN
        RAISE EXCEPTION 'That asset was not found or is already sold or scrapped.' USING ERRCODE = 'P0001';
    END IF;
    IF p_date IS NULL OR p_date < v_a.acquireddate THEN
        RAISE EXCEPTION 'Enter a date after it was bought.' USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(p_amount, 0) < 0 THEN
        RAISE EXCEPTION 'The amount cannot be negative.' USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(p_amount, 0) > 0 AND p_accountid IS NULL THEN
        RAISE EXCEPTION 'Choose the account the money went into.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE livestockassets SET disposeddate = p_date, disposalamount = COALESCE(p_amount, 0), disposalaccountid = p_accountid WHERE assetid = p_id;
    IF COALESCE(p_amount, 0) > 0 THEN
        PERFORM splivestockcash_post(p_farmid, p_accountid, p_date, p_amount, 'AssetSale', 'Sold ' || v_a.name, p_by, 'AssetSale', p_id);
    END IF;
    RETURN jsonb_build_object('bookValue', fnlivestock_bookvalue(p_id, p_date), 'gain', COALESCE(p_amount, 0) - fnlivestock_bookvalue(p_id, p_date));
END
$f$;

CREATE OR REPLACE FUNCTION public.splivestockasset_reverse(p_farmid text, p_id integer, p_reason text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_a livestockassets%ROWTYPE;
BEGIN
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Say why it is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO v_a FROM livestockassets WHERE assetid = p_id AND farmid = p_farmid AND reversedat IS NULL FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That asset was not found or is already reversed.' USING ERRCODE = 'P0001';
    END IF;
    IF v_a.disposeddate IS NOT NULL THEN
        -- Undo the sale or scrapping first; the asset stays.
        UPDATE livestockassets SET disposeddate = NULL, disposalamount = NULL, disposalaccountid = NULL WHERE assetid = p_id;
        PERFORM fnlivestock_reversecash('AssetSale', p_id, p_by, btrim(p_reason));
        RETURN;
    END IF;
    UPDATE livestockassets SET reversedat = (now() at time zone 'utc'), reversedby = p_by, reversereason = btrim(p_reason) WHERE assetid = p_id;
    PERFORM fnlivestock_reversecash('Asset', p_id, p_by, btrim(p_reason));
END
$f$;

-- ---------------------------------------------------------------------------
-- 8. Profit & loss
-- ---------------------------------------------------------------------------
-- Stock used in a period by kind (feed / medicine / other), optionally for one group.
CREATE OR REPLACE FUNCTION public.fnlivestock_stockused(p_farmid text, p_from date, p_to date, p_groupid integer, p_cats text[])
 RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(-SUM(m.totalcost), 0) FROM livestockstockmovements m JOIN livestockitems i ON i.itemid = m.itemid
    WHERE m.farmid = p_farmid AND m.reversedat IS NULL AND m.movementtype = 'Usage'
      AND m.sourcetype IN ('ProductionRecord', 'TreatmentDay', 'HealthRecord')
      AND i.category = ANY (p_cats) AND m.movementdate BETWEEN p_from AND p_to
      AND (p_groupid IS NULL OR m.groupid = p_groupid);
$f$;

CREATE OR REPLACE FUNCTION public.splivestock_profitloss(p_farmid text, p_from date, p_to date, p_groupid integer DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE
    v_animalsales numeric; v_producesales numeric; v_othersales numeric;
    v_cogs numeric; v_animalsbought numeric; v_feed numeric; v_med numeric; v_otherstock numeric; v_lost numeric;
    v_expenses jsonb; v_exptotal numeric; v_pay numeric; v_interest numeric; v_dep numeric; v_cashdiff numeric; v_assetgain numeric;
    v_income numeric; v_costs numeric;
BEGIN
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
        RAISE EXCEPTION 'Choose a period.' USING ERRCODE = 'P0001';
    END IF;
    IF p_groupid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM livestockgroups WHERE groupid = p_groupid AND farmid = p_farmid) THEN
        RAISE EXCEPTION 'That group was not found.' USING ERRCODE = 'P0001';
    END IF;

    -- Income
    SELECT COALESCE(SUM(l.linetotal) FILTER (WHERE l.linetype IN ('Animals', 'Tagged')), 0),
           COALESCE(SUM(l.linetotal) FILTER (WHERE l.linetype = 'Product' AND i.category = 'Produce'), 0),
           COALESCE(SUM(l.linetotal) FILTER (WHERE l.linetype = 'Product' AND i.category <> 'Produce'), 0),
           COALESCE(SUM(l.costtotal), 0)
    INTO v_animalsales, v_producesales, v_othersales, v_cogs
    FROM livestocksalelines l JOIN livestocksales s ON s.saleid = l.saleid
    LEFT JOIN livestockitems i ON i.itemid = l.itemid
    WHERE s.farmid = p_farmid AND s.reversedat IS NULL AND s.saledate BETWEEN p_from AND p_to
      AND (p_groupid IS NULL OR l.groupid = p_groupid);

    -- Animals bought: cost per head of the batch, counted as they join a group.
    SELECT COALESCE(SUM(m.quantity * COALESCE(b.costperhead, 0)), 0) INTO v_animalsbought
    FROM livestockheadmovements m JOIN livestockbatches b ON b.batchid = m.batchid
    WHERE m.farmid = p_farmid AND m.reversedat IS NULL AND m.movementtype = 'Intake' AND m.movementdate BETWEEN p_from AND p_to
      AND (p_groupid IS NULL OR m.groupid = p_groupid);
    -- Tagged animals bought one by one (registered as new, with a price).
    v_animalsbought := v_animalsbought + COALESCE((SELECT SUM(a.purchasecost) FROM livestockanimals a
        JOIN livestockheadmovements m ON m.animalid = a.animalid AND m.movementtype = 'Intake' AND m.reversedat IS NULL AND m.batchid IS NULL
        WHERE a.farmid = p_farmid AND NOT a.isdeleted AND a.purchasecost IS NOT NULL AND m.movementdate BETWEEN p_from AND p_to
          AND (p_groupid IS NULL OR m.groupid = p_groupid)), 0);

    v_feed := fnlivestock_stockused(p_farmid, p_from, p_to, p_groupid, ARRAY['Feed']);
    v_med  := fnlivestock_stockused(p_farmid, p_from, p_to, p_groupid, ARRAY['Medication', 'Vaccine']);
    v_otherstock := fnlivestock_stockused(p_farmid, p_from, p_to, p_groupid, ARRAY['Supply', 'Other', 'Ingredient', 'Produce']);
    v_lost := CASE WHEN p_groupid IS NULL THEN COALESCE((SELECT -SUM(totalcost) FROM livestockstockmovements
                  WHERE farmid = p_farmid AND reversedat IS NULL AND movementtype = 'Loss' AND movementdate BETWEEN p_from AND p_to), 0) ELSE 0 END;

    -- Expenses by kind: paid and on credit.
    WITH e AS (
        SELECT category, amount FROM livestockexpenses
        WHERE farmid = p_farmid AND reversedat IS NULL AND expensedate BETWEEN p_from AND p_to AND (p_groupid IS NULL OR groupid = p_groupid)
        UNION ALL
        SELECT l.expensecategory, l.linetotal FROM livestockpurchaselines l JOIN livestockpurchases p ON p.purchaseid = l.purchaseid
        WHERE p.farmid = p_farmid AND p.reversedat IS NULL AND l.linetype = 'Expense' AND p.purchasedate BETWEEN p_from AND p_to
          AND (p_groupid IS NULL OR l.groupid = p_groupid)
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object('category', category, 'amount', amount) ORDER BY amount DESC), '[]'::jsonb), COALESCE(SUM(amount), 0)
    INTO v_expenses, v_exptotal
    FROM (SELECT category, SUM(amount) AS amount FROM e GROUP BY category) x;

    -- Farm-wide costs (not tagged to a group).
    IF p_groupid IS NULL THEN
        SELECT COALESCE(SUM(l.gross), 0) INTO v_pay FROM livestockpaylines l JOIN livestockpayruns r ON r.runid = l.runid
        WHERE r.farmid = p_farmid AND r.reversedat IS NULL AND r.paydate BETWEEN p_from AND p_to;
        SELECT COALESCE(SUM(r.interest), 0) INTO v_interest FROM livestockloanrepayments r JOIN livestockloans l ON l.loanid = r.loanid
        WHERE l.farmid = p_farmid AND r.reversedat IS NULL AND r.repaydate BETWEEN p_from AND p_to;
        SELECT COALESCE(SUM(fnlivestock_depreciation(a.assetid, p_from, p_to)), 0) INTO v_dep FROM livestockassets a WHERE a.farmid = p_farmid;
        SELECT COALESCE(-SUM(amount), 0) INTO v_cashdiff FROM livestockcashtransactions
        WHERE farmid = p_farmid AND reversedat IS NULL AND category = 'CashDifference' AND txdate BETWEEN p_from AND p_to;
        SELECT COALESCE(SUM(a.disposalamount - fnlivestock_bookvalue(a.assetid, a.disposeddate)), 0) INTO v_assetgain FROM livestockassets a
        WHERE a.farmid = p_farmid AND a.reversedat IS NULL AND a.disposeddate BETWEEN p_from AND p_to;
    ELSE
        v_pay := 0; v_interest := 0; v_dep := 0; v_cashdiff := 0; v_assetgain := 0;
    END IF;

    v_income := v_animalsales + v_producesales + v_othersales + GREATEST(v_assetgain, 0);
    v_costs := v_cogs + v_animalsbought + v_feed + v_med + v_otherstock + v_lost + v_exptotal + v_pay + v_interest + v_dep
             + v_cashdiff + GREATEST(-v_assetgain, 0);

    RETURN jsonb_build_object(
        'from', p_from, 'to', p_to, 'groupId', p_groupid,
        'groupName', (SELECT name FROM livestockgroups WHERE groupid = p_groupid),
        'income', jsonb_build_object('animals', v_animalsales, 'produce', v_producesales, 'otherStock', v_othersales,
                                     'assetGain', GREATEST(v_assetgain, 0), 'total', v_income),
        'costs', jsonb_build_object('stockSold', v_cogs, 'animalsBought', v_animalsbought, 'feed', v_feed, 'medicine', v_med,
                                    'otherStock', v_otherstock, 'stockLost', v_lost, 'expenses', v_expenses, 'expensesTotal', v_exptotal,
                                    'staffPay', v_pay, 'loanInterest', v_interest, 'depreciation', v_dep, 'cashDifferences', v_cashdiff,
                                    'assetLoss', GREATEST(-v_assetgain, 0), 'total', v_costs),
        'profit', v_income - v_costs,
        'producesNotByGroup', p_groupid IS NOT NULL);
END
$f$;

-- Profit for every group in a period, side by side (what each group earned
-- from its animals, against what was spent on it).
CREATE OR REPLACE FUNCTION public.splivestock_profitbygroup(p_farmid text, p_from date, p_to date)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('groupId', g.groupid, 'name', g.name, 'speciesName', s.name, 'status', g.status,
               'income', (pl->'income'->>'total')::numeric, 'costs', (pl->'costs'->>'total')::numeric, 'profit', (pl->>'profit')::numeric,
               'feed', (pl->'costs'->>'feed')::numeric, 'animalsBought', (pl->'costs'->>'animalsBought')::numeric,
               'head', fnlivestock_groupheadasof(g.groupid, p_to))
           ORDER BY (pl->>'profit')::numeric DESC), '[]'::jsonb)
    FROM livestockgroups g JOIN livestockspecies s ON s.speciescode = g.speciescode
    CROSS JOIN LATERAL (SELECT splivestock_profitloss(p_farmid, p_from, p_to, g.groupid) AS pl) x
    WHERE g.farmid = p_farmid AND NOT g.isdeleted AND g.startdate <= p_to AND (g.closeddate IS NULL OR g.closeddate >= p_from);
$f$;

-- ---------------------------------------------------------------------------
-- 9. Cash flow
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.splivestock_cashflow(p_farmid text, p_from date, p_to date)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH t AS (
        SELECT t.category, t.amount FROM livestockcashtransactions t
        WHERE t.farmid = p_farmid AND t.reversedat IS NULL AND t.txdate BETWEEN p_from AND p_to AND t.category <> 'Transfer'
    ),
    opening AS (
        -- Money in every account at the start, including accounts opened during
        -- the period (their opening balance counts as money already held).
        SELECT COALESCE(SUM(CASE WHEN a.openingdate < p_from THEN fnlivestock_cashbalanceasof(a.accountid, p_from - 1) ELSE 0 END), 0) AS held,
               COALESCE(SUM(CASE WHEN a.openingdate BETWEEN p_from AND p_to THEN a.openingbalance ELSE 0 END), 0) AS added
        FROM livestockcashaccounts a WHERE a.farmid = p_farmid
    )
    SELECT jsonb_build_object(
        'from', p_from, 'to', p_to,
        'opening', (SELECT held FROM opening),
        'accountsOpened', (SELECT added FROM opening),
        'moneyIn', (SELECT COALESCE(jsonb_agg(jsonb_build_object('category', category, 'amount', amount) ORDER BY amount DESC), '[]'::jsonb)
                    FROM (SELECT category, SUM(amount) AS amount FROM t WHERE amount > 0 GROUP BY category) x),
        'moneyOut', (SELECT COALESCE(jsonb_agg(jsonb_build_object('category', category, 'amount', amount) ORDER BY amount DESC), '[]'::jsonb)
                     FROM (SELECT category, -SUM(amount) AS amount FROM t WHERE amount < 0 GROUP BY category) x),
        'totalIn', (SELECT COALESCE(SUM(amount), 0) FROM t WHERE amount > 0),
        'totalOut', (SELECT COALESCE(-SUM(amount), 0) FROM t WHERE amount < 0),
        'closing', (SELECT COALESCE(SUM(fnlivestock_cashbalanceasof(a.accountid, p_to)), 0) FROM livestockcashaccounts a
                    WHERE a.farmid = p_farmid AND a.openingdate <= p_to),
        'accounts', (SELECT COALESCE(jsonb_agg(jsonb_build_object('accountId', a.accountid, 'name', a.name,
                        'closing', fnlivestock_cashbalanceasof(a.accountid, p_to)) ORDER BY a.name), '[]'::jsonb)
                     FROM livestockcashaccounts a WHERE a.farmid = p_farmid AND a.openingdate <= p_to));
$f$;

-- ---------------------------------------------------------------------------
-- 10. IAM
-- ---------------------------------------------------------------------------
DO $iam$
DECLARE v integer := 0;
BEGIN
    v := v + splivestock_iammirror('cash-transfers', 'cash-transfers', 'Finance', 'Cash Transfers', 'Moving money between accounts.', 84);
    v := v + splivestock_iammirror('cash-reconciliation', 'cash-reconciliation', 'Finance', 'Cash Reconciliation',
            'Counting an account and correcting the books to match.', 83);
    v := v + splivestock_iammirror('staff', 'staff', 'People', 'Staff', 'The people who work on the farm and their pay rate.', 90);
    v := v + splivestock_iammirror('payroll', 'payroll', 'People', 'Payroll', 'Paying staff.', 91);
    v := v + splivestock_iammirror('staff-loans', 'payroll', 'People', 'Staff Advances', 'Money lent to staff and repaid.', 92);
    v := v + splivestock_iammirror('owner-money', 'owner-money', 'Finance', 'Owner Money', 'Money the owner puts in or takes out.', 85);
    v := v + splivestock_iammirror('loans', 'loans', 'Finance', 'Loans', 'Money borrowed and repaid.', 86);
    v := v + splivestock_iammirror('assets', 'assets', 'Finance', 'Assets', 'Buildings, equipment and vehicles, and what they are worth.', 89);
    v := v + splivestock_iammirror('reports', 'reports', 'Reports', 'Reports', 'Profit & loss, cash flow and the other reports.', 110);
    RAISE NOTICE '463: % livestock permission key(s) added.', v;
END
$iam$;

COMMIT;
